-- EldoUI Chat, guild mutes: hide what members of listed guilds
-- write, without /ignore. Local display only.
--
--   * A list of muted guilds (at most 50), edited in the chat list editor,
--     with /eui chat guilds, or from a player's right-click menu ("Mute
--     their guild").
--   * Public channels, say and yell, and emotes from their members are
--     hidden (each kind its own switch). Outside instances their chat
--     bubbles fade out too; inside, bubbles are forbidden frames and stay
--     as the game draws them.
--   * A "Hidden lines" log of the last 15 minutes, to peek at what was
--     hidden. It lives in memory only.
--   * Optional, off by default: decline group invites and duels from
--     members of muted guilds (an extra next to Quality of Life's blocks).
-- A sender's guild is not part of a chat line, so EldoUI keeps a name ->
-- guild list from the units it sees (mouse-over, target, focus,
-- nameplates, group), out of combat and only from values the game hands
-- out readable. A sender not seen yet is shown. Secret lines are never
-- read and never hidden. The server ignore list is never touched.
-- Hooks into the Chat module (its list editor and line filter hooks) from
-- this file only. Written from scratch for EldoUI.
local _, E = ...
local L = E.L

local M = E:GetModule("Chat")

local IsSecret = function(value) return issecretvalue and issecretvalue(value) or false end
local Readable = E.Plain

local function Try(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a, b, c = pcall(fn, ...)
	if ok then return Readable(a), Readable(b), Readable(c) end
end

local MAX_GUILDS = 50
local CACHE_MAX = 3000
local LOG_SECONDS = 15 * 60
local LOG_MAX = 200
local BUBBLE_SECONDS = 30

-- Defaults join the Chat module's own before its settings load.
M.defaults.guildMutes = {}              -- guild names, as typed or picked
M.defaults.guildMuteChannels = true     -- numbered channels (Trade, General ...)
M.defaults.guildMuteSay = true          -- say and yell
M.defaults.guildMuteEmotes = true       -- /e and /wave lines
M.defaults.guildMuteBubbles = true      -- their bubbles, outside instances
M.defaults.guildMuteLog = true          -- the 15-minute Hidden lines log
M.defaults.guildMuteInvites = false     -- decline their group invites (acts for you)
M.defaults.guildMuteDuels = false       -- decline their duels (acts for you)

E:RegisterGlobal("ChatGuildCache", { names = {} }, { title = "Chat: guilds of players seen",
	desc = "Which guild the players you saw belong to, for the muted guilds list in Chat." })

local function Improve()
	return M.active and M:Allowed("improve")
end

local KIND = {
	CHAT_MSG_CHANNEL = "guildMuteChannels",
	CHAT_MSG_SAY = "guildMuteSay", CHAT_MSG_YELL = "guildMuteSay",
	CHAT_MSG_EMOTE = "guildMuteEmotes", CHAT_MSG_TEXT_EMOTE = "guildMuteEmotes",
}
M.GUILD_MUTE_EVENTS = { "CHAT_MSG_CHANNEL", "CHAT_MSG_EMOTE", "CHAT_MSG_SAY", "CHAT_MSG_TEXT_EMOTE", "CHAT_MSG_YELL" }

---------------------------------------------------------------------------
-- Names and the name -> guild list
---------------------------------------------------------------------------
local function MyRealm()
	local realm = Try(GetNormalizedRealmName)
	return type(realm) == "string" and realm ~= "" and realm or ""
end

-- "Name" / "Name-Realm" -> "name-realm".
local function NameKey(name)
	name = Readable(name)
	if type(name) ~= "string" then return nil end
	name = strtrim(name)
	if name == "" then return nil end
	local short, realm = name:match("^([^%-]+)%-(.+)$")
	short = short or name
	realm = (realm or MyRealm()):gsub("[%s%-]", "")
	return (short .. "-" .. realm):lower()
end
M.GuildNameKey = NameKey

local function GuildKey(guild)
	guild = Readable(guild)
	if type(guild) ~= "string" then return nil end
	guild = strtrim(guild)
	return guild ~= "" and guild:lower() or nil
end

local function Cache()
	local data = E:GetGlobal("ChatGuildCache")
	if type(data) ~= "table" then return {} end
	data.names = type(data.names) == "table" and data.names or {}
	return data.names
end
M.GuildCache = Cache

local cacheCount
local function Prune(names)
	local list = {}
	for key, entry in pairs(names) do
		if type(entry) ~= "table" or type(entry.g) ~= "string" then
			names[key] = nil
		else
			list[#list + 1] = { key = key, t = entry.t or 0 }
		end
	end
	if #list > CACHE_MAX then
		table.sort(list, function(a, b) return a.t > b.t end)
		for index = CACHE_MAX + 1, #list do names[list[index].key] = nil end
	end
	cacheCount = math.min(#list, CACHE_MAX)
end

-- Remember the guild of a unit the game shows. Out of combat only.
function M:RememberGuildOf(unit)
	if InCombatLockdown() or type(unit) ~= "string" then return end
	if not Try(UnitIsPlayer, unit) or not GetGuildInfo then return end
	local ok, guild = pcall(GetGuildInfo, unit)
	-- A secret guild says nothing: the entry stays as it was.
	if not ok or IsSecret(guild) then return end
	-- "Name-Realm" the way chat senders are keyed, never with the surname.
	local key = NameKey(E:UnitNameKey(unit, true))
	if not key then return end
	local names = Cache()
	if type(guild) == "string" and guild ~= "" then
		local entry = names[key]
		if entry and entry.g == guild then
			entry.t = time()
			return
		end
		names[key] = { g = guild, t = time() }
		if cacheCount == nil then Prune(names) end
		cacheCount = cacheCount + 1
		if cacheCount > CACHE_MAX + 100 then Prune(names) end
	elseif names[key] then
		-- Seen without a guild: they left it.
		names[key] = nil
	end
end

function M:GuildOf(sender)
	local key = NameKey(sender)
	local entry = key and Cache()[key]
	return entry and entry.g or nil
end

---------------------------------------------------------------------------
-- The list
---------------------------------------------------------------------------
local muteIndex, muteSource, muteCount = {}, nil, -1

local function MutedIndex()
	local list = M.db.guildMutes
	if muteSource ~= list or muteCount ~= #list then
		muteSource, muteCount = list, #list
		wipe(muteIndex)
		for _, guild in ipairs(list) do
			local key = GuildKey(guild)
			if key then muteIndex[key] = guild end
		end
	end
	return muteIndex
end

function M:IsGuildMuted(guild)
	local key = GuildKey(guild)
	return key and MutedIndex()[key] ~= nil or false
end

function M:AddGuildMute(guild)
	guild = strtrim(tostring(guild or "")):gsub("|", ""):sub(1, 60)
	if guild == "" then return false, L["Type a guild name first."] end
	if self:IsGuildMuted(guild) then return false, L["<%s> is already muted."]:format(guild) end
	local list = self.db.guildMutes
	if #list >= MAX_GUILDS then return false, L["The list is full (%d guilds)."]:format(MAX_GUILDS) end
	list[#list + 1] = guild
	if self.ResetFilterDecisions then self:ResetFilterDecisions() end
	self:ResetGuildDecisions()
	return true, L["<%s> is muted."]:format(guild)
end

function M:RemoveGuildMute(guild)
	local key = GuildKey(guild)
	local list = self.db.guildMutes
	for index = #list, 1, -1 do
		if GuildKey(list[index]) == key then
			table.remove(list, index)
			self:ResetGuildDecisions()
			return true, L["<%s> is no longer muted."]:format(guild)
		end
	end
	return false, L["<%s> is not muted."]:format(tostring(guild))
end

---------------------------------------------------------------------------
-- Hidden lines log (memory only)
---------------------------------------------------------------------------
local hiddenLog = {}

local function TrimLog()
	local cutoff = GetTime() - LOG_SECONDS
	while hiddenLog[1] and hiddenLog[1].at < cutoff do table.remove(hiddenLog, 1) end
	while #hiddenLog > LOG_MAX do table.remove(hiddenLog, 1) end
end

function M:LogHidden(kind, sender, guild, text)
	if not self.db.guildMuteLog then return end
	hiddenLog[#hiddenLog + 1] = { at = GetTime(), kind = kind, sender = sender, guild = guild, text = text }
	TrimLog()
	self:RefreshListEditor("guildHidden")
end

function M:HiddenLines()
	TrimLog()
	local rows = {}
	for index = #hiddenLog, 1, -1 do rows[#rows + 1] = hiddenLog[index] end
	return rows
end

function M:ClearHiddenLines()
	wipe(hiddenLog)
	self:RefreshListEditor("guildHidden")
end

---------------------------------------------------------------------------
-- Bubbles: outside instances only, faded with their alpha
---------------------------------------------------------------------------
local hiddenTexts = {}                                   -- text -> time it was hidden
local fadedBubbles = setmetatable({}, { __mode = "k" })  -- holder -> true

local function BubbleHolder(bubble)
	if not bubble or E.FrameCheck(bubble, "IsForbidden") then return nil end
	for _, child in ipairs({ bubble:GetChildren() }) do
		if not E.FrameCheck(child, "IsForbidden") and child.String then return child end
	end
end

local function InInstance()
	return Try(IsInInstance) and true or false
end

function M:ScanGuildBubbles()
	if not (C_ChatBubbles and C_ChatBubbles.GetAllChatBubbles) or InInstance() then return 0 end
	local now, faded = GetTime(), 0
	for text, at in pairs(hiddenTexts) do
		if now - at > BUBBLE_SECONDS then hiddenTexts[text] = nil end
	end
	local on = Improve() and self.db.guildMuteBubbles
	for _, bubble in ipairs(C_ChatBubbles.GetAllChatBubbles(false) or {}) do
		local holder = BubbleHolder(bubble)
		if holder then
			local text = Readable(holder.String:GetText())
			if on and type(text) == "string" and hiddenTexts[text] then
				holder:SetAlpha(0)
				fadedBubbles[holder] = true
				faded = faded + 1
			elseif fadedBubbles[holder] then
				-- A bubble frame is reused for the next speaker.
				holder:SetAlpha(1)
				fadedBubbles[holder] = nil
			end
		end
	end
	return faded
end

local bubbleQueued = false
local function QueueBubbleScan()
	if bubbleQueued or not C_Timer then return end
	bubbleQueued = true
	C_Timer.After(0, function()
		bubbleQueued = false
		M:ScanGuildBubbles()
		-- The game may draw the bubble a moment after the line.
		C_Timer.After(0.15, function() M:ScanGuildBubbles() end)
	end)
end
M.QueueGuildBubbleScan = QueueBubbleScan

---------------------------------------------------------------------------
-- The line filter
---------------------------------------------------------------------------
local decisions, decisionCount = {}, 0

function M:ResetGuildDecisions()
	wipe(decisions)
	decisionCount = 0
	muteSource = nil
end

-- The muted guild a line comes from, or nil (shown).
function M:GuildMuteReason(event, message, sender)
	local db = self.db
	if #db.guildMutes == 0 then return nil end
	local kind = KIND[event or ""]
	if not (kind and db[kind]) then return nil end
	if IsSecret(message) or IsSecret(sender) or type(sender) ~= "string" then return nil end
	if self.IsMe and self.IsMe(sender) then return nil end
	local guild = self:GuildOf(sender)
	if guild and self:IsGuildMuted(guild) then return guild end
	return nil
end

function M:GuildMuteFilter(event, message, sender, ...)
	if not Improve() or IsSecret(message) or type(message) ~= "string" then return false end
	local lineID = Readable((select(9, ...)))
	if lineID ~= nil and decisions[lineID] ~= nil then return decisions[lineID] end
	local guild = self:GuildMuteReason(event, message, sender)
	local hide = guild ~= nil
	if hide then
		self:LogHidden(event, sender, guild, message)
		if (event == "CHAT_MSG_SAY" or event == "CHAT_MSG_YELL") and self.db.guildMuteBubbles and not InInstance() then
			hiddenTexts[message] = GetTime()
			QueueBubbleScan()
		end
	elseif next(fadedBubbles) and (event == "CHAT_MSG_SAY" or event == "CHAT_MSG_YELL") then
		QueueBubbleScan()
	end
	if lineID ~= nil then
		decisions[lineID] = hide
		decisionCount = decisionCount + 1
		if decisionCount > 600 then M:ResetGuildDecisions() end
	end
	return hide
end

local function MessageFilter(_, event, ...)
	local ok, hide = pcall(M.GuildMuteFilter, M, event, ...)
	if not ok then
		geterrorhandler()(hide)
		return false
	end
	return hide and true or false
end
M.GuildMessageFilter = MessageFilter

local filtersAdded = false
local function AddFilters()
	if filtersAdded then return end
	local addFilter = ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter or ChatFrame_AddMessageEventFilter
	if not addFilter then return end
	filtersAdded = true
	for _, event in ipairs(M.GUILD_MUTE_EVENTS) do addFilter(event, MessageFilter) end
end

---------------------------------------------------------------------------
-- Invites and duels (off by default)
---------------------------------------------------------------------------
-- One chat line per decline, so the player knows who was turned away.
local function ShortName(name)
	local short = Ambiguate and Readable(Ambiguate(tostring(name), "none"))
	return type(short) == "string" and short ~= "" and short or tostring(name)
end

function M:ReportGuildMuteDecline(kind, name, guild)
	local text = kind == "duel" and L["Declined a duel from %s <%s>, a muted guild."]
		or L["Declined a group invite from %s <%s>, a muted guild."]
	E:Print(text:format(E:Highlight(ShortName(name)), tostring(guild)))
end

function M:OnGuildMuteInvite(name)
	if not (M.active and self.db.guildMuteInvites) or InCombatLockdown() then return false end
	local guild = self:GuildOf(name)
	if not (guild and self:IsGuildMuted(guild)) then return false end
	if DeclineGroup then DeclineGroup() end
	if StaticPopup_Hide then StaticPopup_Hide("PARTY_INVITE") end
	self:LogHidden("invite", name, guild, L["Group invite declined"])
	self:ReportGuildMuteDecline("invite", name, guild)
	return true
end

function M:OnGuildMuteDuel(name)
	if not (M.active and self.db.guildMuteDuels) or InCombatLockdown() then return false end
	local guild = self:GuildOf(name)
	if not (guild and self:IsGuildMuted(guild)) then return false end
	if CancelDuel then CancelDuel() end
	if StaticPopup_Hide then StaticPopup_Hide("DUEL_REQUESTED") end
	self:LogHidden("duel", name, guild, L["Duel declined"])
	self:ReportGuildMuteDecline("duel", name, guild)
	return true
end

---------------------------------------------------------------------------
-- Events (own owner: one handler per owner)
---------------------------------------------------------------------------
local owner = {}

local function ScanGroupGuilds()
	if InCombatLockdown() then return end
	local raid = Try(IsInRaid)
	if not (raid or Try(IsInGroup)) then return end
	for index = 1, raid and 40 or 4 do M:RememberGuildOf((raid and "raid" or "party") .. index) end
end

local UNIT_EVENTS = {
	UPDATE_MOUSEOVER_UNIT = function() M:RememberGuildOf("mouseover") end,
	PLAYER_TARGET_CHANGED = function() M:RememberGuildOf("target") end,
	PLAYER_FOCUS_CHANGED = function() M:RememberGuildOf("focus") end,
	NAME_PLATE_UNIT_ADDED = function(unit) M:RememberGuildOf(Readable(unit)) end,
	GROUP_ROSTER_UPDATE = ScanGroupGuilds,
}
M.GUILD_UNIT_EVENTS = UNIT_EVENTS

E:RegisterEvent("PLAYER_LOGIN", function()
	AddFilters()
	for event, fn in pairs(UNIT_EVENTS) do
		E:RegisterEvent(event, function(_, _, unit)
			if M.active and #M.db.guildMutes > 0 then fn(unit) end
		end, owner)
	end
	E:RegisterEvent("PARTY_INVITE_REQUEST", function(_, _, name) M:OnGuildMuteInvite(Readable(name)) end, owner)
	E:RegisterEvent("DUEL_REQUESTED", function(_, _, name) M:OnGuildMuteDuel(Readable(name)) end, owner)
	M:AddGuildMuteMenu()
end, owner)

---------------------------------------------------------------------------
-- Right-click a player: "Mute their guild"
---------------------------------------------------------------------------
local MENUS = { "MENU_UNIT_PLAYER", "MENU_UNIT_PARTY", "MENU_UNIT_RAID_PLAYER", "MENU_UNIT_FRIEND", "MENU_UNIT_TARGET" }
local menuAdded = false

-- The guild of a menu's player: from the unit, else the name list.
function M:MenuGuild(context)
	if type(context) ~= "table" then return nil end
	local unit = Readable(context.unit)
	if type(unit) == "string" then
		local guild = Try(GetGuildInfo, unit)
		if type(guild) == "string" and guild ~= "" then return guild end
	end
	local name, server = Readable(context.name), Readable(context.server)
	if type(name) ~= "string" then return nil end
	return self:GuildOf(type(server) == "string" and server ~= "" and (name .. "-" .. server) or name)
end

function M:AddGuildMuteMenu()
	local menu = _G.Menu
	if menuAdded or not (type(menu) == "table" and menu.ModifyMenu) then return end
	menuAdded = true
	for _, tag in ipairs(MENUS) do
		menu.ModifyMenu(tag, function(_, root, context)
			if not (Improve() and root) then return end
			local guild = M:MenuGuild(context)
			if not guild then return end
			local own = Try(GetGuildInfo, "player")
			if own and GuildKey(own) == GuildKey(guild) then return end
			root:CreateDivider()
			if M:IsGuildMuted(guild) then
				root:CreateButton(L["Unmute their guild <%s>"]:format(guild), function()
					local _, message = M:RemoveGuildMute(guild)
					M:Print(message)
					M:RefreshListEditor("guildMutes")
				end)
			else
				root:CreateButton(L["Mute their guild <%s>"]:format(guild), function()
					local _, message = M:AddGuildMute(guild)
					M:Print(message)
					M:RefreshListEditor("guildMutes")
				end)
			end
		end)
	end
end

---------------------------------------------------------------------------
-- Editors (the chat list editor)
---------------------------------------------------------------------------
function M:GuildMuteStatus()
	if not Improve() then return E:TokenHex(E.tokens.text.warn) .. L["Paused: Chat message extras are off"] .. "|r" end
	local seen = 0
	for _ in pairs(Cache()) do seen = seen + 1 end
	return L["%d / %d · %d players seen"]:format(#self.db.guildMutes, MAX_GUILDS, seen)
end

function M:OpenGuildMuteEditor()
	return self:OpenListEditor({
		key = "guildMutes",
		title = L["Muted guilds"],
		help = L["Public channels, say, yell and emotes from members of these guilds are hidden, and their bubbles outside instances. EldoUI learns guilds from players you see (mouse-over, target, nameplates, group); a player not seen yet is shown."],
		emptyText = L["No guild is muted."],
		items = function() return M.db.guildMutes end,
		text = function(guild) return "<" .. tostring(guild) .. ">" end,
		controls = {
			{ kind = "button", label = L["Remove"], width = 60, click = function(guild) M:RemoveGuildMute(guild) end },
		},
		add = { hint = L["Guild name, e.g. Eldo Guild"], button = L["Mute"], func = function(text) return M:AddGuildMute(text) end },
		status = function() return M:GuildMuteStatus() end,
		footer = {
			{ label = L["Hidden lines"], width = 100, tip = L["What was hidden in the last 15 minutes."],
				click = function() M:OpenHiddenLines() end },
		},
	})
end

local function Ago(seconds)
	seconds = math.max(0, math.floor(seconds))
	if seconds < 60 then return L["%ds"]:format(seconds) end
	return L["%dm"]:format(math.floor(seconds / 60))
end

function M:OpenHiddenLines()
	return self:OpenListEditor({
		key = "guildHidden",
		title = L["Hidden lines"],
		help = L["Lines hidden from muted guilds in the last 15 minutes, newest first. Kept in memory only."],
		emptyText = L["Nothing was hidden."],
		width = 520,
		items = function() return M:HiddenLines() end,
		text = function(row)
			local short = Ambiguate and Readable(Ambiguate(tostring(row.sender), "none")) or tostring(row.sender)
			local body = tostring(row.text or ""):gsub("|H.-|h(.-)|h", "%1"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
			return ("%s: %s"):format(tostring(short), body), ("<%s> · %s"):format(tostring(row.guild), Ago(GetTime() - row.at))
		end,
		status = function() return M.db.guildMuteLog and "" or L["The log is off."] end,
		footer = {
			{ label = L["Clear"], width = 70, tip = L["Empties the log."], click = function() M:ClearHiddenLines() end },
		},
	})
end

---------------------------------------------------------------------------
-- /eui chat guilds | guildmute <guild> | guildunmute <guild> | hidden
---------------------------------------------------------------------------
E:AddCommand("chatguild", "[mute <guild> | unmute <guild> | hidden]  muted guilds in chat (no word opens the list)", function(arg)
	if not M.db then return end
	local word, rest = strtrim(arg or ""):match("^(%S*)%s*(.-)$")
	word = (word or ""):lower()
	if word == "mute" or word == "unmute" then
		if rest == "" then
			E:Print(L["Usage: /eui chatguild %s <guild>"]:format(word))
			return
		end
		local _, message
		if word == "mute" then _, message = M:AddGuildMute(rest) else _, message = M:RemoveGuildMute(rest) end
		E:Print(message)
		M:RefreshListEditor("guildMutes")
	elseif word == "hidden" then
		M:OpenHiddenLines()
	else
		M:OpenGuildMuteEditor()
	end
end)

---------------------------------------------------------------------------
-- Options: after the content filters on the Alerts and filters tab
---------------------------------------------------------------------------
local ROWS = {
	{ type = "header", label = "Muted guilds" },
	{ type = "description", label = "Hide whole guilds you don't want to read, without /ignore. Only what you see changes; your ignore list is untouched." },
	{ type = "execute", label = "Edit the list", desc = "Edit the list of guilds whose members' lines are hidden (up to 50). Also right-click a player and pick Mute their guild, or /eui chatguild.",
		func = function() M:OpenGuildMuteEditor() end },
	{ type = "execute", label = "Hidden lines", desc = "What was hidden from muted guilds in the last 15 minutes. Also /eui chatguild hidden.",
		func = function() M:OpenHiddenLines() end },
	{ type = "toggle", key = "guildMuteChannels", label = "Hide in numbered channels", desc = "Trade, General and other numbered channels." },
	{ type = "toggle", key = "guildMuteSay", label = "Hide say and yell", desc = "What they say and yell near you." },
	{ type = "toggle", key = "guildMuteEmotes", label = "Hide emotes", desc = "Their typed emotes and emote commands (/wave)." },
	{ type = "toggle", key = "guildMuteBubbles", label = "Hide their chat bubbles", desc = "Fades the speech bubble of a hidden say or yell line. Outside instances only: inside, the game keeps bubbles out of reach of addons." },
	{ type = "toggle", key = "guildMuteLog", label = "Keep a hidden-lines log", desc = "Remembers what was hidden for 15 minutes (in memory only), for the Hidden lines window." },
	{ type = "toggle", acts = true, key = "guildMuteInvites", label = "Decline their group invites", desc = "Group invites from members of muted guilds are declined, and one chat line names who and which guild. Not in combat. This acts for you. Off by default." },
	{ type = "toggle", acts = true, key = "guildMuteDuels", label = "Decline their duels", desc = "Duel requests from members of muted guilds are declined, and one chat line names who and which guild. Not in combat. This acts for you. Off by default." },
}

local function InsertRows()
	local options = M.options
	if type(options) ~= "table" then return end
	local at
	for index, row in ipairs(options) do
		if row.key == "filterCyrillic" then at = index + 1 end
	end
	if not at then
		-- The tab moved: put the rows at the end of the Alerts and filters tab.
		for index, row in ipairs(options) do
			if row.type == "tab" and row.label == "History and search" then at = index end
		end
	end
	at = at or #options + 1
	for offset, row in ipairs(ROWS) do table.insert(options, at + offset - 1, row) end
end
InsertRows()

-- Declining for the muted guilds acts for the player: listed for the
-- setup's Convenience step and the Conveniences page (Core/Conveniences.lua),
-- off until ticked and never recommended.
E:RegisterConvenience({ id = "guildMuteInvites", module = "Chat", setting = "guildMuteInvites", order = 140,
	label = "Decline group invites from muted guilds",
	desc = "Acts for you: declines group invites from members of the guilds you muted, out of combat, and says who in chat." })
E:RegisterConvenience({ id = "guildMuteDuels", module = "Chat", setting = "guildMuteDuels", order = 150,
	label = "Decline duels from muted guilds",
	desc = "Acts for you: declines duel requests from members of the guilds you muted, out of combat, and says who in chat." })
