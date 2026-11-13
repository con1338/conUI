-- EldoUI Instances: reset notices and the leader's reset notice.
--
-- When instances are reset the game prints one system line per instance
-- (INSTANCE_RESET_SUCCESS / _FAILED / _FAILED_OFFLINE / _FAILED_ZONING,
-- matched through E.ChatParse "reset", never against English text). EldoUI
-- gathers the lines of one reset and prints one summary in your own chat:
-- what was reset, and what wasn't and why. A line that arrives as a secret
-- value (chat messaging lockdown) is skipped.
--
-- Leader notice (off by default: the reset may come from the game's own
-- menu, not a click in EldoUI): when you lead the group and a reset
-- succeeds, the names of the reset instances go to the group as an EldoUI
-- addon message (prefix EUI_IR, E:SendComm). It waits while the game
-- holds addon messages back and is never sent in a battleground. Members running
-- EldoUI print "Instances were reset by the leader (Name)". Nothing shows
-- in group chat.
--
-- "Announce reset" (off by default) adds a menu entry to the Instances
-- datatext and a right-click on the Raid Tools "Reset" button: one click
-- sends one line with the last reset to the group.
local _, E = ...
local L = E.L
local M = E.Instances
local P = E.ChatParse

local PREFIX = "EUI_IR"
local BATCH = 1         -- seconds the lines of one reset take to arrive
local ANNOUNCE_AGE = 900 -- the last reset can be announced this long

local IsSecret = M.IsSecret

local RESULT_TEXT = E:TranslateValues({
	failed = E.Key("players are still inside"),
	offline = E.Key("someone in the group is offline"),
	zoning = E.Key("someone is zoning into an instance"),
})

local function InPvP()
	local _, kind = IsInInstance()
	if IsSecret(kind) then return true end
	return kind == "pvp" or kind == "arena"
end

local function IsLeader()
	if not IsInGroup() then return false end
	local leader = UnitIsGroupLeader("player")
	return not IsSecret(leader) and leader == true
end

---------------------------------------------------------------------------
-- One reset: the lines that arrive together
---------------------------------------------------------------------------
local batch

function M:LastReset()
	return self:Store().lastReset
end

local function Flush()
	local current = batch
	batch = nil
	if not current or #current.results == 0 then return end
	local store = M:Store()
	store.lastReset = { at = M:Now(), results = current.results }
	local done, failed = {}, {}
	for _, entry in ipairs(current.results) do
		if entry.result == "success" then
			done[#done + 1] = entry.instance
		else
			failed[#failed + 1] = ("%s (%s)"):format(entry.instance, RESULT_TEXT[entry.result] or entry.result)
		end
	end
	if #done > 0 then store.lastResetAt = M:Now() end
	if M.db.resetNotice then
		local parts = {}
		if #done > 0 then parts[#parts + 1] = (L["Reset: %s."]):format(table.concat(done, ", ")) end
		if #failed > 0 then parts[#parts + 1] = (L["Not reset: %s."]):format(table.concat(failed, ", ")) end
		local text = table.concat(parts, " ")
		if #done > 0 and M.db.announceReset and IsInGroup() then
			text = text .. " " .. E:ChatLink("instances", "announce", L["Announce to the group"])
		end
		M:Notice(text)
	end
	if #done > 0 and M.db.leaderSend and IsLeader() and not InPvP() then
		E:SendComm(PREFIX, "1" .. table.concat(done, "\t"), "GROUP")
	end
	M:Changed("reset")
end

local function OnSystem(_, text)
	local fields = P:Parse("reset", text)
	if not (fields and type(fields.instance) == "string" and fields.instance ~= "") then return end
	if not batch then
		batch = { results = {} }
		C_Timer.After(BATCH, Flush)
	end
	batch.results[#batch.results + 1] = { instance = fields.instance, result = fields.result or "success" }
end

M:Listen("CHAT_MSG_SYSTEM", "reset", OnSystem)

---------------------------------------------------------------------------
-- The leader's notice, received
---------------------------------------------------------------------------
function M:OnResetComm(payload, sender)
	if not (self.active and self.db.leaderShow) or InPvP() then return end
	if IsSecret(payload) or IsSecret(sender) or type(payload) ~= "string" or type(sender) ~= "string" then return end
	if payload:sub(1, 1) ~= "1" then return end
	-- The unit name of the sender: "Name" on your realm, "Name-Realm" from
	-- another realm (UnitIsGroupLeader needs the realm then).
	local unit = Ambiguate and Ambiguate(sender, "none")
	if type(unit) ~= "string" or IsSecret(unit) or unit == "" then unit = sender end
	local short = sender:match("^[^%-]+") or sender
	local leader
	for _, name in ipairs({ unit, sender, short }) do
		leader = UnitIsGroupLeader(name)
		if IsSecret(leader) then return end
		if leader then break end
	end
	if not leader then return end
	local names = {}
	for name in payload:sub(2):gmatch("[^\t]+") do
		-- Shown as plain words: a doubled bar turns any link, color or
		-- texture code the sender put in into visible text.
		if #names < 10 then names[#names + 1] = (E:Utf8Clip(name, 64):gsub("|", "||")) end
	end
	if #names == 0 then return end
	self:Store().lastResetAt = self:Now()
	self:Notice((L["Instances were reset by the leader (%s): %s."]):format(short, table.concat(names, ", ")))
	self:Changed("reset")
end

E:RegisterComm(PREFIX, function(payload, sender) M:OnResetComm(payload, sender) end, { trusted = "group" })

---------------------------------------------------------------------------
-- "Announce reset": one line to the group, one click
---------------------------------------------------------------------------
function M:CanAnnounceReset()
	local last = self:LastReset()
	if not (self.db.announceReset and last and IsInGroup()) then return false end
	if self:Now() - (last.at or 0) > ANNOUNCE_AGE then return false end
	for _, entry in ipairs(last.results or {}) do
		if entry.result == "success" then return true end
	end
	return false
end

function M:AnnounceReset()
	if not self.db.announceReset then
		self:Notice(L["Turn on \"Announce reset\" under Instances > Resets first."])
		return false
	end
	if not self:CanAnnounceReset() then
		self:Notice(L["No reset in the last 15 minutes to announce."])
		return false
	end
	local done = {}
	for _, entry in ipairs(self:LastReset().results) do
		if entry.result == "success" then done[#done + 1] = entry.instance end
	end
	local channel = self:GroupChannel()
	if not channel then return false end
	local text = ("Instances reset: %s"):format(table.concat(done, ", ")) -- no-L: sent to group chat, other players read it in English
	if #text > 255 then text = E:Utf8Clip(text, 252) .. "..." end
	if not E:TryChatPost(text, channel) then
		self:Notice(E:ChatRefusedText())
		return false
	end
	return true
end

-- Raid Tools "Reset" button: the player's own click, the same call as the
-- portrait menu's "Reset all instances".
function M:ResetInstancesClick()
	if IsInGroup() and not IsLeader() then
		self:Notice(L["Only the group leader can reset instances."])
		return false
	end
	if type(ResetInstances) ~= "function" then return false end
	return (pcall(ResetInstances))
end

local previousMenu = M.FillDataMenu
function M:FillDataMenu(root)
	if previousMenu then previousMenu(self, root) end
	if self:CanAnnounceReset() then
		root:CreateButton(L["Announce the last reset"], function() M:AnnounceReset() end)
	end
end

local previousLink = M.OnChatLink
function M:OnChatLink(action, arg)
	if action == "announce" then return self:AnnounceReset() end
	if previousLink then return previousLink(self, action, arg) end
end

---------------------------------------------------------------------------
-- Options
---------------------------------------------------------------------------
M.optionParts = M.optionParts or {}
table.insert(M.optionParts, function(options)
	local rows = {
		{ type = "tab", label = L["Resets"] },
		{ type = "description", label = L["The game's reset lines are summed up in one. The leader's notice to other EldoUI users is an addon message, not group chat."] },
		{ type = "toggle", key = "resetNotice", label = L["Reset summary"], desc = L["One line in your chat after a reset: which instances were reset, and which weren't and why."] },
		{ type = "toggle", key = "leaderSend", label = L["Tell the group when I reset"], desc = L["As group leader, each reset sends the instance names to group members who run EldoUI, as an addon message (never in a battleground)."] },

		{ type = "toggle", key = "leaderShow", label = L["Show the leader's resets"], desc = L["Prints \"Instances were reset by the leader\" when your group leader runs EldoUI and resets."] },
		{ type = "header", label = L["Acts for you"] },
		{ type = "toggle", key = "announceReset", label = L["Announce reset"], desc = L["Adds \"Announce the last reset\" to the Instances datatext menu, the reset line and the Raid Tools Reset button. Each click sends one line to group chat."] },
		{ type = "description", label = L["A \"Reset\" button for the leader is on the Raid Tools bar (Group > Raid Tools > Reset instances, off by default)."] },
	}
	for _, row in ipairs(rows) do options[#options + 1] = row end
end)
