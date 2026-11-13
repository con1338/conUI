-- EldoUI Characters: the Guild tab.
--
-- Guild bank: the items of every guild bank tab one of your characters
-- opened, with the last visit and the guild's gold.
--
-- Alt exchange (off by default): with "Share alt info with your guild" on,
-- the tab gets two buttons: "Send my alts" sends your characters on this
-- realm (name, class, level, item level) to guild members who also use
-- EldoUI, and "Ask the guild" asks them for theirs. Nothing is ever sent
-- without one of those clicks, and an incoming request is only shown, not
-- answered. Lists you receive show in "Guild alts".
--
-- Export: "Export" makes an EldoUI string of your alt list (share kind
-- "alts"); /eui import or the Import button reads one and adds it to the
-- Guild alts list.
local _, E = ...
local L = E.L
local Key = E.Key
local Kit = E.UIKit
local M = E.modules.Characters

local function Store() return E.Characters end

local COMM = "EUI_ALTS"
local SHARE_PREFIX = "!EUA1!"

local function Grey(text) return M.Grey(text) end

-- Received alt lists older than this, or past the newest PEER_MAX, leave.
local PEER_DAYS, PEER_MAX = 90, 100

local function PrunePeers(peers)
	local now = Store().Now()
	local list = {}
	for owner, peer in pairs(peers) do
		if type(peer) ~= "table" or type(peer.at) ~= "number" or now - peer.at > PEER_DAYS * 86400 then
			peers[owner] = nil
		else
			list[#list + 1] = { owner = owner, at = peer.at }
		end
	end
	if #list > PEER_MAX then
		table.sort(list, function(a, b) return a.at > b.at end)
		for index = PEER_MAX + 1, #list do peers[list[index].owner] = nil end
	end
end
M.PruneGuildPeers = PrunePeers

local function Peers()
	local data = E:GetGlobal("characters")
	if type(data) ~= "table" then return {} end
	data.guildPeers = type(data.guildPeers) == "table" and data.guildPeers or {}
	if not M.peersPruned then
		M.peersPruned = true
		PrunePeers(data.guildPeers)
	end
	return data.guildPeers
end
M.GuildPeers = Peers

---------------------------------------------------------------------------
-- The alt list (sent, exported and imported in the same shape)
---------------------------------------------------------------------------
-- { { name, class, level, ilvl }, ... } for this realm's characters.
function M:AltList()
	local list = {}
	for _, key in ipairs(Store():Keys("realm")) do
		local record = Store():Get(key)
		list[#list + 1] = { name = record.name, class = record.class, level = record.level, ilvl = record.gear and record.gear.ilvl }
	end
	return list
end

local function Encode(list)
	local parts = {}
	for _, alt in ipairs(list) do
		local name = tostring(alt.name or "?"):gsub("[:;]", "")
		parts[#parts + 1] = ("%s:%s:%d:%s"):format(name, alt.class or "", tonumber(alt.level) or 0, alt.ilvl and tostring(alt.ilvl) or "")
	end
	return table.concat(parts, ";")
end

local function Decode(text)
	local list = {}
	if type(text) ~= "string" then return list end
	for part in text:gmatch("[^;]+") do
		local name, class, level, ilvl = part:match("^([^:]*):([%u]*):(%d+):([%d%.]*)$")
		if name and name ~= "" and #list < 60 then
			list[#list + 1] = { name = name, class = class ~= "" and class or nil, level = tonumber(level), ilvl = tonumber(ilvl) }
		end
	end
	return list
end
M.EncodeAlts, M.DecodeAlts = Encode, Decode

local function Remember(owner, list, how)
	if type(owner) ~= "string" or owner == "" then return end
	local peers = Peers()
	peers[owner] = { at = Store().Now(), alts = list, how = how }
	PrunePeers(peers)
	M:Refresh({ section = "guildPeers" })
end

---------------------------------------------------------------------------
-- Guild exchange (opt-in, click only)
---------------------------------------------------------------------------
local function CanSend()
	if not M.db.guildShare then
		M:Say(L["Turn on \"Share alt info with your guild\" in /eui > Alts first."], true)
		return false
	end
	if not IsInGuild() then
		M:Say(L["You are not in a guild."], true)
		return false
	end
	if (E.AddonCommsRestricted and E:AddonCommsRestricted()) or (E.CommRestricted and E:CommRestricted()) then
		M:Say(L["The game holds addon messages back right now. Try again later."], true)
		return false
	end
	return true
end

function M:SendAlts()
	if not CanSend() then return false end
	local ok = E:SendComm(COMM, "A" .. Encode(self:AltList()), "GUILD")
	if ok then M:Say(L["Your alt list went to your guild."]) end
	return ok and true or false
end

function M:AskGuild()
	if not CanSend() then return false end
	local ok = E:SendComm(COMM, "Q", "GUILD")
	if ok then M:Say(L["Asked your guild for their alt lists. Answers show in the Guild tab."]) end
	return ok and true or false
end

local function OnMessage(payload, sender)
	if not (M.active and M.db.guildShare) then return end
	local kind, body = payload:sub(1, 1), payload:sub(2)
	if kind == "A" then
		local name = Ambiguate and Ambiguate(sender, "none")
		Remember(type(name) == "string" and name ~= "" and name or sender, Decode(body), "guild")
	elseif kind == "Q" then
		M.asked = M.asked or {}
		M.asked[sender] = Store().Now()
		M:Refresh({ section = "guildPeers" })
	end
end
M.OnGuildMessage = OnMessage

local function Listen()
	-- Registering the prefix sends nothing; messages are ignored while the
	-- exchange is off.
	if M.listening or not E.RegisterComm then return end
	M.listening = E:RegisterComm(COMM, OnMessage, { trusted = "guild" }) and true or false
end
M.ListenGuild = Listen

---------------------------------------------------------------------------
-- Export and import (share kind "alts")
---------------------------------------------------------------------------
local function RegisterShare()
	if M.shareRegistered or not E.RegisterShareKind then return end
	M.shareRegistered = true
	E:RegisterShareKind("alts", {
		prefix = SHARE_PREFIX,
		title = function(data) return L["Alt list of %s"]:format(type(data) == "table" and tostring(data.owner) or "?") end,
		version = 1,
		build = function()
			return { owner = E:PlayerName(), alts = Encode(M:AltList()) }
		end,
		describe = function(data)
			local lines = {}
			for _, alt in ipairs(Decode(type(data) == "table" and data.alts)) do
				lines[#lines + 1] = ("%s (%d)"):format(alt.name, alt.level or 0)
			end
			return lines
		end,
		apply = function(data)
			if type(data) ~= "table" then return end
			Remember(tostring(data.owner or "?"), Decode(data.alts), "import")
		end,
	})
end

function M:ExportAlts()
	RegisterShare()
	local text = E:ExportShareKind("alts")
	if text and E.ShowCopyBox then
		E:ShowCopyBox(L["Your alt list"], L["Copy this string and give it to a friend. They paste it in /eui import."], text)
	end
	return text
end

---------------------------------------------------------------------------
-- The tab
---------------------------------------------------------------------------
function M:GuildBankRows(guildKey, tabFilter)
	local guild = Store():Guilds()[guildKey]
	local rows, index = {}, {}
	if type(guild) ~= "table" then return rows end
	for tabIndex, tab in pairs(type(guild.tabs) == "table" and guild.tabs or {}) do
		if not tabFilter or tabFilter == tabIndex then
			for _, value in ipairs(tab.items or {}) do
				local short, count = Store().Decode(value)
				if short then
					local slot = tabIndex .. short
					local row = index[slot]
					if not row then
						row = { short = short, id = Store().ItemIDOf(short), count = 0, tab = tabIndex, tabName = tab.name or ("#" .. tabIndex) }
						index[slot] = row
						rows[#rows + 1] = row
					end
					row.count = row.count + count
				end
			end
		end
	end
	return rows
end

function M:PeerRows()
	local rows = {}
	for owner, peer in pairs(Peers()) do
		if type(peer) == "table" then rows[#rows + 1] = { owner = owner, peer = peer } end
	end
	for sender, at in pairs(self.asked or {}) do
		if not Peers()[sender] then rows[#rows + 1] = { owner = sender, asked = at } end
	end
	return rows
end

local function ItemText(row)
	local name, _, quality, _, _, _, _, _, _, icon = C_Item.GetItemInfo(row.short)
	if not name and row.id and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(row.id) end
	local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
	local text = name or ("item:" .. tostring(row.id))
	if color and color.hex then text = color.hex .. text .. "|r" end
	icon = icon or (row.id and C_Item.GetItemIconByID and C_Item.GetItemIconByID(row.id))
	return (icon and ("|T%s:14:14:0:0:64:64:5:59:5:59|t "):format(icon) or "") .. text, name or ""
end

local function AltsText(alts)
	local parts = {}
	for _, alt in ipairs(alts or {}) do
		local r, g, b = M.ClassColor(alt.class)
		parts[#parts + 1] = Kit.Hex(r, g, b) .. alt.name .. "|r" .. Grey(" " .. (alt.level or "?"))
	end
	return table.concat(parts, ", ")
end

local COLUMNS = {
	bank = {
		{ key = "item", title = "Item", value = function(row) return select(2, ItemText(row)) end, text = function(row) return (ItemText(row)) end },
		{ key = "count", title = "Count", width = 70, align = "RIGHT", value = function(row) return row.count end },
		{ key = "tab", title = "Tab", width = 160, value = function(row) return row.tab end, text = function(row) return row.tabName end },
	},
	peers = {
		{ key = "owner", title = "Player", width = 150, value = function(row) return row.owner end },
		{ key = "alts", title = "Characters", value = function(row) return row.peer and #row.peer.alts or 0 end,
			text = function(row)
				if row.asked and not row.peer then return Grey(L["asked for your alt list"]) end
				return AltsText(row.peer.alts)
			end },
		{ key = "ilvl", title = "Best ilvl", width = 80, align = "RIGHT",
			value = function(row)
				local best = 0
				for _, alt in ipairs(row.peer and row.peer.alts or {}) do best = math.max(best, alt.ilvl or 0) end
				return best
			end },
		{ key = "at", title = "Received", width = 90, align = "RIGHT", value = function(row) return row.peer and row.peer.at or row.asked or 0 end,
			text = function(row)
				local at = row.peer and row.peer.at or row.asked
				if not at then return "" end
				local seconds = Store().Now() - at
				return seconds < 3600 and L["now"] or (seconds < 86400 and L["%dh"]:format(seconds / 3600) or L["%dd"]:format(seconds / 86400))
			end },
	},
}

local function Build(frame, view)
	for _, tbl in pairs(frame.tables) do tbl:Hide() end
	local tbl = frame.tables[view]
	if not tbl then
		tbl = Kit.CreateTable(frame, COLUMNS[view], {
			sortKey = view == "bank" and "item" or "owner", rowHeight = 18,
			onClick = function(row, button, widget)
				if row.short and IsModifiedClick() and HandleModifiedItemClick then
					local _, link = C_Item.GetItemInfo(row.short)
					HandleModifiedItemClick(link or row.short)
				elseif row.owner and button == "RightButton" then
					E.UIKit.ContextMenu(widget, function(_, root)
						root:CreateButton(L["Remove from the list"], function()
							Peers()[row.owner] = nil
							if M.asked then M.asked[row.owner] = nil end
							M:Refresh()
						end)
					end)
				end
			end,
			createRow = function(widget)
				widget:HookScript("OnEnter", function(own)
					local row = own.item
					if not (row and row.short) then return end
					GameTooltip:SetOwner(own, "ANCHOR_RIGHT")
					GameTooltip:SetHyperlink(row.short)
					GameTooltip:Show()
				end)
				widget:HookScript("OnLeave", function() GameTooltip:Hide() end)
			end,
			empty = view == "bank"
				and { L["No guild bank saved"], L["Open your guild bank and click through its tabs once; each tab you see is saved here."] }
				or { L["No alt lists yet"], L["Turn on \"Share alt info with your guild\" in /eui > Alts, then click Ask the guild. Lists you import show here too."] },
		})
		tbl:SetPoint("TOPLEFT", frame.toolbar, "BOTTOMLEFT", 0, -6)
		tbl:SetPoint("BOTTOMRIGHT")
		frame.tables[view] = tbl
	end
	tbl:Show()
	return tbl
end

function M:ShowGuildMenu(anchor, frame)
	E.UIKit.ContextMenu(anchor, function(_, root)
		root:CreateTitle(L["Guild bank"])
		for _, key in ipairs(Store():GuildKeys(M.db.scope)) do
			root:CreateRadio(key, function() return frame.guild == key end, function()
				frame.guild, frame.tabFilter = key, nil
				M.UpdateGuild(frame)
			end)
		end
		local guild = frame.guild and Store():Guilds()[frame.guild]
		if type(guild) == "table" and type(guild.tabs) == "table" then
			root:CreateDivider()
			root:CreateTitle(L["Tab"])
			root:CreateRadio(L["All tabs"], function() return frame.tabFilter == nil end, function() frame.tabFilter = nil M.UpdateGuild(frame) end)
			local tabs = {}
			for index in pairs(guild.tabs) do tabs[#tabs + 1] = index end
			table.sort(tabs)
			for _, index in ipairs(tabs) do
				root:CreateRadio(guild.tabs[index].name or ("#" .. index), function() return frame.tabFilter == index end, function()
					frame.tabFilter = index
					M.UpdateGuild(frame)
				end)
			end
		end
	end, { at = "owner" })
end

local function Update(frame)
	local view = next(frame.view:GetSelected()) or "bank"
	local tbl = Build(frame, view)
	local bankView = view == "bank"
	frame.guildButton:SetShown(bankView)
	frame.send:SetShown(not bankView and M.db.guildShare)
	frame.ask:SetShown(not bankView and M.db.guildShare)
	frame.export:SetShown(not bankView)
	frame.import:SetShown(not bankView)
	if bankView then
		local keys = Store():GuildKeys(M.db.scope)
		local found = false
		for _, key in ipairs(keys) do if key == frame.guild then found = true end end
		if not found then frame.guild, frame.tabFilter = Store().CurrentGuildKey() or keys[1], nil end
		local guild = frame.guild and Store():Guilds()[frame.guild]
		frame.guildButton:SetText(type(guild) == "table" and guild.name or L["No guild bank"])
		Kit.FitButton(frame.guildButton, 120)
		if type(guild) == "table" then
			local seen = guild.updated and M.Duration(Store().Now() - guild.updated) or "?"
			frame.note:SetText(L["%s · last visit %s ago"]:format(M.Money(guild.money or 0, true), seen))
		else
			frame.note:SetText("")
		end
		frame.rows = frame.guild and M:GuildBankRows(frame.guild, frame.tabFilter) or {}
	else
		frame.note:SetText(M.db.guildShare and "" or L["Sharing with the guild is off (/eui > Alts)."])
		frame.rows = M:PeerRows()
	end
	tbl:SetData(frame.rows)
end
M.UpdateGuild = Update

M:AddTab({
	key = "guild", order = 80, title = "Guild",
	desc = "Your guild banks, and the alt lists of guild members who share theirs.",
	create = function(content)
		local frame = CreateFrame("Frame", nil, content)
		frame:SetAllPoints()
		frame.tables = {}
		frame.toolbar = CreateFrame("Frame", nil, frame)
		frame.toolbar:SetPoint("TOPLEFT")
		frame.toolbar:SetPoint("TOPRIGHT")
		frame.toolbar:SetHeight(22)
		frame.view = Kit.ChipBar(frame.toolbar, {
			selected = "bank",
			chips = {
				{ "bank", L["Guild bank"], L["The items of every guild bank tab one of your characters opened."] },
				{ "peers", L["Guild alts"], L["Alt lists guild members sent you, or that you imported."] },
			},
			onChange = function(selected, key)
				if not next(selected) then frame.view:SetSelected(key) end
				Update(frame)
			end,
		})
		frame.view:SetPoint("LEFT", 2, 0)
		frame.guildButton = Kit.Button(frame.toolbar, "", 120, 20, function(button) M:ShowGuildMenu(button, frame) end,
			L["Guild bank"], L["Pick the guild and the tab to show."])
		frame.guildButton:SetPoint("LEFT", frame.view, "RIGHT", 10, 0)
		frame.import = Kit.Button(frame.toolbar, L["Import"], 70, 20, function() if E.ShowImport then E:ShowImport() end end,
			L["Import"], L["Paste an alt list string someone gave you."])
		frame.import:SetPoint("RIGHT", -2, 0)
		frame.export = Kit.Button(frame.toolbar, L["Export"], 70, 20, function() M:ExportAlts() end,
			L["Export"], L["Makes a string of your alt list on this realm (name, class, level, item level) to give to a friend."])
		frame.export:SetPoint("RIGHT", frame.import, "LEFT", -4, 0)
		frame.ask = Kit.Button(frame.toolbar, L["Ask the guild"], 100, 20, function() M:AskGuild() end,
			L["Ask the guild"], L["Asks guild members who use EldoUI and share their alts to send you their list. Their answer needs their click too."])
		frame.ask:SetPoint("RIGHT", frame.export, "LEFT", -4, 0)
		frame.send = Kit.Button(frame.toolbar, L["Send my alts"], 100, 20, function() M:SendAlts() end,
			L["Send my alts"], L["Sends your characters on this realm (name, class, level, item level) to guild members who use EldoUI and share theirs."])
		frame.send:SetPoint("RIGHT", frame.ask, "LEFT", -4, 0)
		frame.note = Kit.Text(frame.toolbar, 11, "RIGHT", "dim")
		frame.note:SetPoint("RIGHT", frame.export, "LEFT", -8, 0)
		frame.note:SetPoint("LEFT", frame.guildButton, "RIGHT", 10, 0)
		return frame
	end,
	show = function(frame, arg)
		if arg == "bank" or arg == "peers" then frame.view:SetSelected(arg) end
		Update(frame)
	end,
	refresh = function(frame) Update(frame) end,
	enable = function()
		RegisterShare()
		Listen()
	end,
})
