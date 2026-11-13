-- EldoUI Attunements: guild and group survey.
--
-- Click-only, both ways. With "Share with guild and group" on:
--   Ask the guild / Ask my group   sends one line: "R\t<data version>"
--   someone asks you               "When someone asks" = Ask me: a toast with
--                                  a Send button; Never: nothing happens.
--                                  There is no answer without your click.
--   Send mine                      one line per click:
--     "P\t<name>\t<class>\t<level>\t<faction>\t<role>\t<data version>\t<entries>"
--     entries: "key=done/total/steps;..." for each raid, key and chain you
--     have started; steps are the done flags of the entry's steps in order,
--     five to a character (base 32), read only when both sides have the
--     same data version.
-- Lines come through E:RegisterComm with trusted senders only (guild,
-- group, friends); secret text or sender is dropped there. A "P" line whose
-- name is not its sender is dropped. Results live in EldoUIDB.attunePeers
-- (at most 500, older than "Keep results" days are removed).
local _, E = ...
local LG = E.LootGuide
local Kit = LG.Kit
local P = LG.PageKit
local L = E.L
local A = E:GetModule("Attunements")

local PREFIX = "EUI_ATT"
local PEER_CAP = 500
local DIGITS = "0123456789abcdefghijklmnopqrstuv"
local ASK_ICON = "Interface\\Icons\\INV_Misc_Key_04"
A.COMM_PREFIX = PREFIX
A.PEER_CAP = PEER_CAP

local guildState = { asked = nil, answers = 0, waiting = false }
local askedBy = {}       -- sender -> time of their last request (one toast a minute)
local online = {}        -- guild members online (Online chip)
A.guildState = guildState

local function Now()
	return time and time() or 0
end

local function DataVersion()
	local LD = A.Data()
	return LD and LD.attuneVersion and tostring(LD.attuneVersion) or "0"
end

local function Clean(text)
	return (tostring(text or ""):gsub("[\t\n;=|]", " "))
end

-- "Name-Realm" for the player: the name without the surname, as
-- the sender of the guild message carries it, and the realm from
-- GetNormalizedRealmName (UnitFullName may give the surname there).
local function FullName()
	local name = A.Plain(E:PlayerName())
	if type(name) ~= "string" or name == "" then name = "?" end
	local realm = GetNormalizedRealmName and A.Plain(GetNormalizedRealmName()) or nil
	return (type(realm) == "string" and realm ~= "") and (name .. "-" .. realm) or name
end
A.FullName = FullName

local function SplitName(text)
	local name, realm = tostring(text or ""):match("^([^%-]+)%-(.+)$")
	if name then return name:lower(), realm:lower():gsub("[%s']", "") end
	return tostring(text or ""):lower(), nil
end

-- The same character (a realm on only one side counts as the same realm).
function A.SameName(a, b)
	local na, ra = SplitName(a)
	local nb, rb = SplitName(b)
	if na ~= nb or na == "" then return false end
	return ra == nil or rb == nil or ra == rb
end

---------------------------------------------------------------------------
-- Peers
---------------------------------------------------------------------------
local function Peers(create)
	if type(EldoUIDB) ~= "table" then return create and {} or nil end
	if type(EldoUIDB.attunePeers) ~= "table" then
		if not create then return end
		EldoUIDB.attunePeers = {}
	end
	return EldoUIDB.attunePeers
end

function A:Peers()
	return Peers(false) or {}
end

function A:PrunePeers()
	local store = Peers(false)
	if not store then return end
	local days = tonumber(self.db and self.db.guildKeepDays) or 60
	local cutoff = Now() - days * 86400
	local list = {}
	for name, peer in pairs(store) do
		if type(peer) ~= "table" or (tonumber(peer.at) or 0) < cutoff then
			store[name] = nil
		else
			list[#list + 1] = { name = name, at = tonumber(peer.at) or 0 }
		end
	end
	if #list > PEER_CAP then
		table.sort(list, function(a, b) return a.at > b.at end)
		for index = PEER_CAP + 1, #list do store[list[index].name] = nil end
	end
end

function A:ClearPeers()
	if type(EldoUIDB) == "table" then EldoUIDB.attunePeers = nil end
	guildState.answers = 0
	LG:Fire("attunePeers")
end

function A:RemovePeer(name)
	local store = Peers(false)
	if store then store[name] = nil end
	LG:Fire("attunePeers")
end

---------------------------------------------------------------------------
-- What you send: your progress, packed
---------------------------------------------------------------------------
local function PackSteps(key, charKey)
	local entry = A:Get(key)
	local out, value, n = {}, 0, 0
	for _, step in ipairs(entry.steps.list) do
		if A:StepState(key, step.id, charKey) == "done" then value = value + 2 ^ n end
		n = n + 1
		if n == 5 then
			out[#out + 1] = DIGITS:sub(value + 1, value + 1)
			value, n = 0, 0
		end
	end
	if n > 0 then out[#out + 1] = DIGITS:sub(value + 1, value + 1) end
	return table.concat(out)
end

local function UnpackStep(bits, index)
	local char = bits:sub(math.floor((index - 1) / 5) + 1, math.floor((index - 1) / 5) + 1)
	local value = char ~= "" and (DIGITS:find(char, 1, true) or 1) - 1 or 0
	return math.floor(value / 2 ^ ((index - 1) % 5)) % 2 == 1
end
A.UnpackStep = UnpackStep

function A:MyPayload()
	local player = LG:Player()
	local parts = {}
	for _, key in ipairs(self:MainKeys(true)) do
		local done, total, _, state = self:Progress(key)
		if total > 0 and (done > 0 or state == "done") then
			parts[#parts + 1] = ("%s=%d/%d/%s"):format(key, done, total, PackSteps(key))
		end
	end
	local role = UnitGroupRolesAssigned and A.Plain(UnitGroupRolesAssigned("player"))
	if type(role) ~= "string" then role = "NONE" end
	return table.concat({ "P", Clean(FullName()), Clean(player.class or ""), tostring(player.level or 0), Clean(player.faction or ""),
		Clean(role), Clean(DataVersion()), table.concat(parts, ";") }, "\t")
end

---------------------------------------------------------------------------
-- Sending (each one a click)
---------------------------------------------------------------------------
local function Send(payload, channel, target)
	if not (A.db and A.db.guildShare) then return false, "off" end
	local ok, why = E:SendComm(PREFIX, payload, channel, target)
	guildState.waiting = ok and E:CommRestricted() or false
	LG:Fire("attunePeers")
	return ok, why
end

function A:AskGuild()
	local ok, why = Send("R\t" .. Clean(DataVersion()), "GUILD")
	if ok then guildState.asked = Now() end
	return ok, why
end

function A:AskGroup()
	local ok, why = Send("R\t" .. Clean(DataVersion()), "GROUP")
	if ok then guildState.asked = Now() end
	return ok, why
end

-- channel nil: your guild, else your group.
function A:SendMine(channel, target)
	if not channel then channel = (IsInGuild and IsInGuild()) and "GUILD" or "GROUP" end
	return Send(self:MyPayload(), channel, target)
end

---------------------------------------------------------------------------
-- Receiving
---------------------------------------------------------------------------
local function Split(text)
	local out = {}
	for part in (tostring(text) .. "\t"):gmatch("([^\t]*)\t") do out[#out + 1] = part end
	return out
end

function A:OnRequest(sender, channel)
	if not self.db.guildShare or self.db.guildAnswer ~= "ask" then return end
	local now = Now()
	if askedBy[sender] and now - askedBy[sender] < 60 then return end
	askedBy[sender] = now
	local short = Ambiguate and Ambiguate(sender, "short") or sender
	local reply = channel == "GUILD" and "GUILD" or "WHISPER"
	A:PushAlert({
		key = "attune:ask:" .. sender, title = L["Attunements asked"], icon = ASK_ICON, duration = 30,
		text = (L["%s asks for your attunements."]):format(short),
		actions = {
			{ label = L["Send"], tip = L["Sends one line with your attunement progress. Nothing else is sent."], func = function()
				A:SendMine(reply, reply == "WHISPER" and sender or nil)
			end },
		},
	})
end

function A:OnProgress(fields, sender)
	if not self.db.guildShare then return end
	local name = fields[2]
	if type(name) ~= "string" or name == "" or not A.SameName(name, sender) then return end
	local peer = { at = Now(), class = fields[3], level = tonumber(fields[4]) or 0, faction = fields[5], role = fields[6],
		dv = fields[7], bits = {} }
	for key, done, total, bits in tostring(fields[8] or ""):gmatch("([%w_:]+)=(%d+)/(%d+)/([0-9a-v]*)") do
		if self:Get(key) then peer.bits[key] = { done = tonumber(done), total = tonumber(total), steps = bits } end
	end
	if IsInGuild and IsInGuild() and online[name] ~= nil then peer.guild = true end
	local store = Peers(true)
	-- Keep the sender's spelling (with realm) as the key.
	for other in pairs(store) do
		if other ~= sender and A.SameName(other, sender) then store[other] = nil end
	end
	store[sender] = peer
	guildState.answers = (guildState.answers or 0) + 1
	self:PrunePeers()
	LG:Fire("attunePeers")
end

local function OnComm(payload, sender, channel)
	if not (A.db and A.db.guildShare) or type(payload) ~= "string" then return end
	local fields = Split(payload)
	if fields[1] == "R" then
		A:OnRequest(sender, channel)
	elseif fields[1] == "P" then
		A:OnProgress(fields, sender)
	end
end
A.OnComm = OnComm

---------------------------------------------------------------------------
-- Reading the results
---------------------------------------------------------------------------
-- A peer's cell: a check, "x/n" or "-".
function A:PeerCell(peer, key)
	local row = type(peer.bits) == "table" and peer.bits[key]
	local entry = self:Get(key)
	if entry and entry.side and peer.faction and peer.faction ~= "" and entry.side ~= peer.faction then return A.Secondary("-") end
	if type(row) ~= "table" then return A.Secondary("-") end
	if row.total > 0 and row.done >= row.total then return A.CheckMark() end
	return ("%d/%d"):format(row.done, row.total)
end

function A:PeerDone(peer, key)
	local row = type(peer.bits) == "table" and peer.bits[key]
	return type(row) == "table" and row.total > 0 and row.done >= row.total
end

-- Guild members whose next step this is: { { name, text } }.
function A:GuildOnStep(key, step)
	local out = {}
	local entry = self:Get(key)
	if not (entry and step and step.index) then return out end
	local dv = DataVersion()
	for name, peer in pairs(self:Peers()) do
		local row = type(peer) == "table" and type(peer.bits) == "table" and peer.bits[key]
		if type(row) == "table" and peer.dv == dv and row.done < row.total and type(row.steps) == "string" then
			if not UnpackStep(row.steps, step.index) then
				local ready = true
				for _, f in ipairs(step.follows) do
					local up = entry.steps.byId[f]
					if up and up.index and not UnpackStep(row.steps, up.index) then ready = false end
				end
				if ready then
					local short = Ambiguate and Ambiguate(name, "short") or name
					out[#out + 1] = { name = name, text = short .. "  " .. A.Secondary(peer.level or "") }
				end
			end
		end
	end
	table.sort(out, function(a, b) return a.name < b.name end)
	return out
end

local function ScanRoster()
	wipe(online)
	if not (GetNumGuildMembers and GetGuildRosterInfo) then return end
	local ok, count = pcall(GetNumGuildMembers)
	count = ok and A.Plain(count) or 0
	for i = 1, (type(count) == "number" and count or 0) do
		local fine, name, _, _, _, _, _, _, _, isOnline = pcall(GetGuildRosterInfo, i)
		name, isOnline = A.Plain(name), A.Plain(isOnline)
		if fine and type(name) == "string" then online[name] = isOnline and true or false end
	end
end

function A:IsOnline(name)
	for other, on in pairs(online) do
		if on and A.SameName(other, name) then return true end
	end
	return false
end

---------------------------------------------------------------------------
-- The Guild view (Overview > Guild)
---------------------------------------------------------------------------
local ROLE_TITLE = { TANK = "TANK", HEALER = "HEALER", DAMAGER = "DAMAGER" }

local function RoleText(role)
	local global = ROLE_TITLE[role or ""] and rawget(_G, ROLE_TITLE[role])
	return type(global) == "string" and global or A.Secondary("-")
end

local function SeenText(at)
	local age = Now() - (tonumber(at) or 0)
	if age < 3600 then return (L["%d min"]):format(math.max(math.floor(age / 60), 1)) end
	if age < 86400 then return (L["%d h"]):format(math.floor(age / 3600)) end
	return (L["%d d"]):format(math.floor(age / 86400))
end

local function StatusText()
	if not A.db.guildShare then return "" end
	if E:CommRestricted() then return L["Waiting: addon messages are paused here"] end
	local bits = {}
	local count = 0
	for _ in pairs(A:Peers()) do count = count + 1 end
	bits[#bits + 1] = E:Plural(count, "%d answer", "%d answers"):format(count)
	if guildState.asked then
		local age = Now() - guildState.asked
		bits[#bits + 1] = age < 60 and L["last asked just now"] or (L["last asked %d min ago"]):format(math.floor(age / 60))
	end
	return table.concat(bits, "  ·  ")
end
A.GuildStatusText = StatusText

function A.CreateGuildView(_, parent)
	local view = CreateFrame("Frame", nil, parent)
	view:SetAllPoints()
	view.filters = { notDone = false, max = false, online = false }
	view.groups = {}
	local anchor
	for _, group in ipairs({ { "raids", L["Raids"] }, { "keys", L["Keys"] }, { "misc", L["Other chains"] } }) do
		local key = group[1]
		local chip = P.Toggle(view, group[2], function()
			local s = A.PageState()
			s.group, s.columnPage = key, 1
			view:Draw()
		end, group[2], L["Which attunements the columns show."])
		if anchor then chip:SetPoint("LEFT", anchor, "RIGHT", 4, 0) else chip:SetPoint("TOPLEFT", 0, 0) end
		anchor = chip
		view.groups[key] = chip
	end
	local function Filter(field, label, tip)
		local chip = P.Toggle(view, label, function()
			view.filters[field] = not view.filters[field]
			view:Draw()
		end, label, tip)
		chip:SetPoint("LEFT", anchor, "RIGHT", anchor == view.groups.misc and 16 or 4, 0)
		anchor = chip
		return chip
	end
	view.notDone = Filter("notDone", L["Not done"], L["Only members who have not finished every attunement in the columns."])
	view.max = Filter("max", L["Level 60"], L["Only members at level 60."])
	view.online = Filter("online", L["Online"], L["Only guild members who are online now."])
	view.grid = A.CreateGrid(view, {
		nameWidth = 150,
		cellTooltip = function(tooltip, item, column)
			local sr, sg, sb = unpack(E.tokens.text.secondary)
			E.UIKit.TipTitle(tooltip, item.short or item.name)
			if column.key then
				local row = item.peer.bits and item.peer.bits[column.key]
				tooltip:AddLine(A:Name(column.key), sr, sg, sb)
				if row then E.UIKit.TipTitle(tooltip, E:Plural(row.total, "%d of %d step", "%d of %d steps"):format(row.done, row.total)) end
			end
			tooltip:AddLine((L["Sent %s ago"]):format(SeenText(item.peer.at)), sr, sg, sb)
			tooltip:AddLine(" ")
			E:TooltipHint(tooltip, { L["Right-click"], L["whisper, invite or remove"] })
		end,
		onClick = function(item, button, owner)
			if button == "RightButton" then view:RowMenu(owner, item) end
		end,
	})
	view.grid:SetPoint("TOPLEFT", 0, -26)
	view.grid:SetPoint("BOTTOMRIGHT", 0, 30)
	view.empty = Kit.EmptyState(view)
	view.empty:ClearAllPoints()
	view.empty:SetPoint("TOPLEFT", 0, -26)
	view.empty:SetPoint("BOTTOMRIGHT", 0, 30)
	view.empty:Hide()
	view.status = Kit.Text(view, 11, "LEFT", "secondary")
	view.status:SetPoint("BOTTOMLEFT", 2, 6)
	view.sendMine = Kit.Button(view, L["Send mine"], 100, 22, function()
		A:SendMine()
		view:Draw()
	end, L["Send mine"], L["Sends one line with your attunement progress to your guild (or your group when you have no guild)."])
	view.sendMine:SetPoint("BOTTOMRIGHT", 0, 2)
	view.askGroup = Kit.Button(view, L["Ask my group"], 110, 22, function()
		A:AskGroup()
		view:Draw()
	end, L["Ask my group"], L["Asks your party or raid. Members who use EldoUI get a toast and choose whether to answer."])
	view.askGroup:SetPoint("RIGHT", view.sendMine, "LEFT", -6, 0)
	view.askGuild = Kit.Button(view, L["Ask the guild"], 110, 22, function()
		A:AskGuild()
		view:Draw()
	end, L["Ask the guild"], L["Asks your guild. Members who use EldoUI get a toast and choose whether to answer."])
	view.askGuild:SetPoint("RIGHT", view.askGroup, "LEFT", -6, 0)
	view.status:SetPoint("BOTTOMRIGHT", view.askGuild, "BOTTOMLEFT", -8, 4)
	view.status:SetWordWrap(false)

	function view:RowMenu(owner, item)
		E.UIKit.ContextMenu(owner, function(_, root)
			root:CreateTitle(item.short or item.name)
			root:CreateButton(L["Whisper"], function()
				local util = ChatFrameUtil
				if util and util.SendTell then util.SendTell(item.name) elseif ChatFrame_SendTell then ChatFrame_SendTell(item.name) end
			end)
			root:CreateButton(L["Invite"], function()
				if C_PartyInfo and C_PartyInfo.InviteUnit then C_PartyInfo.InviteUnit(item.name) end
			end)
			root:CreateButton(L["Remove"], function() A:RemovePeer(item.name) end)
		end)
	end

	function view:Draw()
		local s = A.PageState()
		local db = A.db
		for key, chip in pairs(self.groups) do chip:SetOn(s.group == key) end
		self.notDone:SetOn(self.filters.notDone)
		self.max:SetOn(self.filters.max)
		self.online:SetOn(self.filters.online)
		local share = db.guildShare
		local inGuild = IsInGuild and IsInGuild() and true or false
		local inGroup = IsInGroup and IsInGroup() and true or false
		self.askGuild:SetEnabled(share and inGuild)
		self.askGroup:SetEnabled(share and inGroup)
		self.sendMine:SetEnabled(share and (inGuild or inGroup))
		self.status:SetText(StatusText())
		if not share then
			self.grid:Hide()
			self.empty:Set(L["Sharing is off"], L["Turn on sharing to ask guild and group members who use EldoUI for their attunements and to send yours. Nothing is sent until you click Ask or Send mine."],
				ASK_ICON, { { L["Turn on sharing"], function()
					db.guildShare = true
					if E.RefreshConfig then E:RefreshConfig() end
					self:Draw()
				end, L["Turns on Share with guild and group (Attunements settings)."] } })
			self.empty:Show()
			return
		end
		local keys = {}
		for _, key in ipairs(A:MainKeys(true)) do
			if A:Get(key).group == s.group then keys[#keys + 1] = key end
		end
		local first = 1
		local columns = {}
		for index = first, math.min(first + 4, #keys) do
			columns[#columns + 1] = { key = keys[index], title = A:Name(keys[index]), tip = A:Desc(keys[index]), width = 84 }
		end
		columns[#columns + 1] = { title = L["Role"], width = 70, tip = L["The role they had when they sent it."] }
		columns[#columns + 1] = { title = L["Sent"], width = 56, tip = L["How long ago they sent it."] }
		self.grid:SetColumns(L["Name"], columns)
		local rows = {}
		for name, peer in pairs(A:Peers()) do
			if type(peer) == "table" then
				local keep = true
				if self.filters.max and (peer.level or 0) < 60 then keep = false end
				if self.filters.online and not A:IsOnline(name) then keep = false end
				if keep and self.filters.notDone then
					local all = true
					for index = 1, #columns - 2 do
						if not A:PeerDone(peer, columns[index].key) then all = false end
					end
					if all then keep = false end
				end
				if keep then
					local short = Ambiguate and Ambiguate(name, "short") or name
					local color = E:ClassColorObject(peer.class) -- custom class colors
					local label = color and Kit.Hex(color.r, color.g, color.b) .. short .. "|r" or short
					label = label .. "  " .. A.Secondary(peer.level or "?")
					local cells = {}
					for index = 1, #columns - 2 do cells[index] = A:PeerCell(peer, columns[index].key) end
					cells[#cells + 1] = RoleText(peer.role)
					cells[#cells + 1] = A.Secondary(SeenText(peer.at))
					rows[#rows + 1] = { name = name, short = short, label = label, cells = cells, peer = peer }
				end
			end
		end
		table.sort(rows, function(a, b) return a.short < b.short end)
		if #rows == 0 then
			self.grid:Hide()
			local any = next(A:Peers()) ~= nil
			if any then
				self.empty:Set(L["Nothing matches"], L["The filters hide every answer."], ASK_ICON, { { L["Reset"], function()
					self.filters.notDone, self.filters.max, self.filters.online = false, false, false
					self:Draw()
				end, L["Turns the filters off."] } })
			else
				self.empty:Set(L["Nobody has answered yet"], L["Nobody has answered yet. Ask the guild?"], ASK_ICON,
					inGuild and { { L["Ask the guild"], function() A:AskGuild() self:Draw() end,
						L["Asks your guild. Members who use EldoUI get a toast and choose whether to answer."] } } or nil)
			end
			self.empty:Show()
			return
		end
		self.empty:Hide()
		self.grid:Show()
		self.grid:SetRows(rows)
	end
	return view
end

---------------------------------------------------------------------------
-- Start and stop with the module
---------------------------------------------------------------------------
function A:StartGuild()
	E:RegisterComm(PREFIX, OnComm, { trusted = true })
	self:PrunePeers()
	self:RegisterEvent("GUILD_ROSTER_UPDATE", function() ScanRoster() end)
	ScanRoster()
end

function A:StopGuild()
	E:UnregisterComm(PREFIX)
	self:UnregisterEvent("GUILD_ROSTER_UPDATE")
end
