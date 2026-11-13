-- EldoUI Chat, part 6: content filters, local display only.
--
--   * Repeated lines: the same text from the same player in a public
--     channel within the repeat window shows once.
--   * Blocked phrases: a list (at most 50), literal, ignoring A-Z case,
--     optionally whole words only, matched on the message and the names of
--     links in it (never on hidden link data). In public channels, or in
--     all chat except your own lines.
--   * Script filter: lines with Cyrillic letters (script, not language).
--   * Channel mutes: one player in one public channel only (for example
--     Trade), without /ignore. From the list editor, /eui chat mute, or a
--     right-click on the sender of a channel line.
--   * Guild and friend notices: a burst of joined, left, online and
--     offline lines folded into one line (off by default).
-- One decision per line ID, made in the message event filter, so a hidden
-- line never reaches a chat window, the Alert tab or saved history. Secret
-- lines are never read and never hidden. The server ignore list is never
-- touched, and the game still plays its own sounds.
-- Written from scratch for EldoUI.
local _, E = ...
local L = E.L

local M = E:GetModule("Chat")

local IsSecret = function(value) return issecretvalue and issecretvalue(value) or false end
local Readable = E.Plain

local MAX_PHRASES, MAX_MUTES = 50, 50

local function Improve()
	return M.active and M:Allowed("improve")
end

local PUBLIC = { CHAT_MSG_CHANNEL = true, CHAT_MSG_SAY = true, CHAT_MSG_YELL = true, CHAT_MSG_EMOTE = true }
local ALL = {
	CHAT_MSG_GUILD = true, CHAT_MSG_OFFICER = true, CHAT_MSG_PARTY = true, CHAT_MSG_PARTY_LEADER = true,
	CHAT_MSG_RAID = true, CHAT_MSG_RAID_LEADER = true, CHAT_MSG_RAID_WARNING = true, CHAT_MSG_INSTANCE_CHAT = true,
	CHAT_MSG_INSTANCE_CHAT_LEADER = true, CHAT_MSG_WHISPER = true, CHAT_MSG_BN_WHISPER = true,
	CHAT_MSG_COMMUNITIES_CHANNEL = true,
}
M.FILTER_EVENTS = {}
for event in pairs(PUBLIC) do table.insert(M.FILTER_EVENTS, event) end
for event in pairs(ALL) do table.insert(M.FILTER_EVENTS, event) end
table.insert(M.FILTER_EVENTS, "CHAT_MSG_TRADESKILLS")
table.insert(M.FILTER_EVENTS, "CHAT_MSG_SYSTEM")
table.sort(M.FILTER_EVENTS)

---------------------------------------------------------------------------
-- Text helpers
---------------------------------------------------------------------------
-- What a player reads: colors gone, links reduced to their names.
local function PlainLower(message)
	M.plainLowers = (M.plainLowers or 0) + 1
	local text = message:gsub("|H.-|h(.-)|h", "%1"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	text = text:gsub("|T.-|t", ""):gsub("|A.-|a", "")
	return (text:lower():gsub("%s+", " "))
end

-- The same without lowering: item links become their names.
local function PlainText(message)
	return (message:gsub("|H.-|h(.-)|h", "%1"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

local function HasCyrillic(text)
	-- U+0400 to U+04FF: lead byte 0xD0 to 0xD3 and a continuation byte.
	return text:find("[\208-\211][\128-\191]") ~= nil
end
M.HasCyrillic = HasCyrillic

-- Lower-case copies of the saved phrases, by position. An entry is used
-- only while it was made from the same phrase, so a list edit or another
-- profile lowers just the phrases that changed.
local lowerPhrases = {}

local function LowerPhrase(index, phrase)
	local cached = lowerPhrases[index]
	if cached and cached[1] == phrase then return cached[2] end
	M.phraseLowers = (M.phraseLowers or 0) + 1
	local wanted = phrase:lower()
	lowerPhrases[index] = { phrase, wanted }
	return wanted
end

-- Phrase matched in `lower` (already plain and lower case), or nil.
function M:MatchPhrase(lower)
	local whole = self.db.filterWholeWords
	for index, phrase in ipairs(self.db.filterPhrases) do
		if type(phrase) == "string" and phrase ~= "" then
			local wanted = LowerPhrase(index, phrase)
			if whole then
				if M.FindWord(lower, wanted) then return phrase end
			elseif lower:find(wanted, 1, true) then
				return phrase
			end
		end
	end
	return nil
end

-- "Trade - City" and "2. Trade - City" both give "trade".
local function ChannelName(text)
	if type(text) ~= "string" or IsSecret(text) then return nil end
	text = text:gsub("^%d+%.%s*", ""):gsub("%s+%-%s+.*$", "")
	text = strtrim(text)
	return text ~= "" and text:lower() or nil
end
M.ChannelName = ChannelName

local function NameKey(name)
	if type(name) ~= "string" or IsSecret(name) or name == "" then return nil end
	return name:lower()
end

local function SameName(a, b)
	a, b = NameKey(a), NameKey(b)
	if not (a and b) then return false end
	if a == b then return true end
	-- A name typed without its realm matches that name on any realm.
	if not a:find("-", 1, true) or not b:find("-", 1, true) then
		return a:match("^[^%-]+") == b:match("^[^%-]+")
	end
	return false
end

-- The channel of each saved mute, as ChannelName gives it, kept while the
-- rule and its channel text stay the same.
local muteChannels = {}

local function RuleChannel(index, rule)
	local cached = muteChannels[index]
	if cached and cached[1] == rule and cached[2] == rule.channel then return cached[3] end
	M.muteNames = (M.muteNames or 0) + 1
	local name = ChannelName(rule.channel)
	muteChannels[index] = { rule, rule.channel, name }
	return name
end

function M:FindMute(channel, sender)
	channel = ChannelName(channel)
	if not (channel and sender) then return nil end
	for index, rule in ipairs(self.db.channelMutes) do
		if type(rule) == "table" and RuleChannel(index, rule) == channel and SameName(rule.name, sender) then return index end
	end
	return nil
end

---------------------------------------------------------------------------
-- The decision
---------------------------------------------------------------------------
local decisions, decisionCount = {}, 0  -- lineID -> true (hide) / false (show)
local lastSeen = {}                     -- sender .. text -> time
local channelLines, channelOrder = {}, {} -- lineID -> { channel, sender }, last 500 channel lines

local function NoteChannelLine(lineID, channel, sender)
	if not (lineID and channel and sender) or channelLines[lineID] then return end
	channelLines[lineID] = { channel = channel, sender = sender }
	channelOrder[#channelOrder + 1] = lineID
	if #channelOrder > 500 then
		channelLines[table.remove(channelOrder, 1)] = nil
	end
end

function M:ChannelLineInfo(lineID)
	lineID = Readable(lineID)
	return lineID and channelLines[lineID] or nil
end

-- Why a line would be hidden (a short reason), or nil. args are the event
-- arguments after the message: sender, language, channel string, target,
-- flags, zone channel ID, channel index, channel base name ...
function M:HideReason(event, message, sender, channel, channelBase)
	local db = self.db
	if type(message) ~= "string" or IsSecret(message) then return nil end
	local filters = db.contentFilters
	local public = PUBLIC[event]
	if not filters and not (db.spamFilter and public) then return nil end
	local lower = PlainLower(message)
	if filters then
		if public and event == "CHAT_MSG_CHANNEL" and #db.channelMutes > 0 then
			if self:FindMute(channelBase or channel, sender) then return "muted in this channel" end
		end
		if public or (db.filterScope == "all" and ALL[event]) then
			local phrase = self:MatchPhrase(lower)
			if phrase then return ("phrase \"%s\""):format(phrase) end
			if db.filterCyrillic and HasCyrillic(lower) then return "Cyrillic letters" end
		end
	end
	if db.spamFilter and public then
		local key = tostring(sender) .. "\0" .. lower
		local now = GetTime()
		local last = lastSeen[key]
		lastSeen[key] = now
		if last and now - last < db.spamWindow then return "repeated" end
	end
	return nil
end

-- Other players' crafting ("Name creates Item."), matched on the game's
-- own TRADESKILL_LOG_THIRDPERSON line in the client's language (also its
-- numbered "%1$s erschafft %2$s." form). Your own crafts use the
-- first-person line and always show.
function M:IsOthersCraft(message)
	return E.ChatParse:MatchFormat(PlainText(message), _G.TRADESKILL_LOG_THIRDPERSON) ~= nil
end

function M:FilterLine(event, message, sender, ...)
	if IsSecret(message) or type(message) ~= "string" then return false end
	if event == "CHAT_MSG_SYSTEM" then return false end
	if event == "CHAT_MSG_TRADESKILLS" then
		return self.db.hideOthersCrafts == true and self:IsOthersCraft(message)
	end
	sender = Readable(sender)
	if not sender or self.IsMe(sender) then return false end
	local _, channel, _, _, _, _, channelBase, _, lineID = ...
	lineID = Readable(lineID)
	channel, channelBase = Readable(channel), Readable(channelBase)
	if event == "CHAT_MSG_CHANNEL" and lineID then NoteChannelLine(lineID, ChannelName(channelBase or channel), sender) end
	if lineID ~= nil and decisions[lineID] ~= nil then return decisions[lineID] end
	local hide = self:HideReason(event, message, sender, channel, channelBase) ~= nil
	if lineID ~= nil then
		decisions[lineID] = hide
		decisionCount = decisionCount + 1
		if decisionCount > 600 then
			wipe(decisions)
			decisionCount = 0
			-- Repeats are only compared inside the window, so older lines go
			-- and a spammer's recent lines stay.
			local now, window = GetTime(), self.db.spamWindow or 0
			for key, seen in pairs(lastSeen) do
				if now - seen >= window then lastSeen[key] = nil end
			end
		end
	end
	return hide
end

-- Settings changed: decisions made with the old lists don't count any more.
function M:ResetFilterDecisions()
	wipe(decisions)
	decisionCount = 0
	wipe(lowerPhrases)
	wipe(muteChannels)
end

-- For tests: how many lines the repeat filter remembers.
function M:RepeatMemory()
	local count = 0
	for _ in pairs(lastSeen) do count = count + 1 end
	return count
end

---------------------------------------------------------------------------
-- Guild and friend notices folded into one line
--
-- A burst of "has joined the guild", "has left the guild", "has come
-- online" and "has gone offline" system lines (logins after a server
-- restart, a guild recruiting) is shown as one line per kind. The first
-- line of a burst shows as usual; the others are held back and, once the
-- burst is over, one summary line names them in the chat windows that
-- would have shown them ("5 more came online: A, B, C ... [all]", hover
-- the link for every name). Lines are matched with the game's own
-- localized strings, never English text. Friends keep their own lines
-- unless "Fold friends too" is on. Secret lines are never read or held.
---------------------------------------------------------------------------
local BURST_QUIET, BURST_MAX = 4, 15  -- seconds: a burst ends after 4 s without a line, or 15 s in all
local NAMES_SHOWN = 4                  -- names written out in the summary line
local ROSTER_KINDS = {
	-- kind, global string, argument that holds the shown name
	{ kind = "online", global = "ERR_FRIEND_ONLINE_SS", arg = 2, friend = true },
	{ kind = "offline", global = "ERR_FRIEND_OFFLINE_S", arg = 1, friend = true },
	{ kind = "joined", global = "ERR_GUILD_JOIN_S", arg = 1 },
	{ kind = "left", global = "ERR_GUILD_LEAVE_S", arg = 1 },
}
local ROSTER_TEXT = E:TranslateValues({
	online = E.Key("%d more came online: %s"),
	offline = E.Key("%d more went offline: %s"),
	joined = E.Key("%d more joined the guild: %s"),
	left = E.Key("%d more left the guild: %s"),
})
local bursts = {}                         -- kind -> { started, last, names, frames, timer }
local rosterDecisions, rosterCount = {}, 0 -- lineID -> true (held) / false (shown)
local summaries, summaryOrder = {}, {}    -- summary id -> names (the hover list), last 30
local summaryID = 0

-- kind, shown name, link name of a roster line, or nil.
function M:RosterLine(message)
	local text = E.ChatParse:Readable(message)
	if not text then return nil end
	for _, entry in ipairs(ROSTER_KINDS) do
		local format = rawget(_G, entry.global)
		if type(format) == "string" then
			local args = E.ChatParse:MatchFormat(text, format)
			if args then
				local name = args[entry.arg] or args[1]
				if type(name) == "string" and name ~= "" then return entry.kind, name, args[1], entry.friend end
			end
		end
	end
	return nil
end

local function Contains(list, value)
	for _, item in ipairs(list) do
		if item == value then return true end
	end
	return false
end

local function IsFriend(name)
	local friends = C_FriendList
	if type(name) ~= "string" or not (friends and friends.GetFriendInfo) then return false end
	local ok, info = pcall(friends.GetFriendInfo, name)
	if not ok or IsSecret(info) then return false end
	return info ~= nil
end

local function SummaryLine(kind, names)
	local shown = {}
	for index = 1, math.min(#names, NAMES_SHOWN) do shown[index] = names[index] end
	local list = table.concat(shown, ", ")
	if #names > NAMES_SHOWN then
		summaryID = summaryID + 1
		summaries[summaryID] = names
		summaryOrder[#summaryOrder + 1] = summaryID
		if #summaryOrder > 30 then summaries[table.remove(summaryOrder, 1)] = nil end
		list = list .. ", ... " .. E:ChatLink("roster", summaryID, L["all"])
	end
	return ROSTER_TEXT[kind]:format(#names, list)
end

function M:FlushRosterBurst(kind)
	local burst = bursts[kind]
	bursts[kind] = nil
	if not burst then return end
	if burst.timer then burst.timer:Cancel() end
	if #burst.names == 0 then return end
	local info = ChatTypeInfo and ChatTypeInfo.SYSTEM
	local r, g, b = 1, 1, 0
	if info then r, g, b = info.r or r, info.g or g, info.b or b end
	local line = SummaryLine(kind, burst.names)
	for _, frame in ipairs(burst.frames) do frame:AddMessage(line, r, g, b) end
end

function M:ScheduleRosterFlush(kind)
	local burst = bursts[kind]
	if burst.timer then burst.timer:Cancel() end
	local wait = math.min(BURST_QUIET, math.max(0, burst.started + BURST_MAX - GetTime()))
	burst.timer = C_Timer.NewTimer(wait, function() M:FlushRosterBurst(kind) end)
end

-- Every hover name of a summary line (the [all] link), or nil.
function M:RosterSummaryNames(id)
	return summaries[tonumber(id) or 0]
end

-- true hides this copy of the line. Called once per chat window that shows
-- system lines; the first call for a line decides for all of them.
function M:FoldRoster(frame, message, ...)
	if not self.db.foldRoster then return false end
	local lineID = Readable((select(10, ...)))
	if lineID ~= nil and rosterDecisions[lineID] ~= nil then
		local held = rosterDecisions[lineID]
		if held then
			for _, burst in pairs(bursts) do
				if burst.lines[lineID] and not Contains(burst.frames, frame) then burst.frames[#burst.frames + 1] = frame end
			end
		end
		return held
	end
	local kind, name, linkName, friendKind = self:RosterLine(message)
	local held = false
	if kind and not (friendKind and not self.db.foldFriends and IsFriend(linkName)) then
		local now = GetTime()
		local burst = bursts[kind]
		if burst then
			held = true
			burst.names[#burst.names + 1] = name
			if lineID ~= nil then burst.lines[lineID] = true end
			if frame and not Contains(burst.frames, frame) then burst.frames[#burst.frames + 1] = frame end
			burst.last = now
		else
			-- The first line of a burst shows as usual.
			bursts[kind] = { started = now, last = now, names = {}, frames = {}, lines = {} }
		end
		self:ScheduleRosterFlush(kind)
	end
	if lineID ~= nil then
		rosterDecisions[lineID] = held
		rosterCount = rosterCount + 1
		if rosterCount > 400 then
			wipe(rosterDecisions)
			rosterCount = 0
		end
	end
	return held
end

-- Turning the option off (or the module) writes out what was held.
function M:FlushRosterBursts()
	for kind in pairs(bursts) do self:FlushRosterBurst(kind) end
end

---------------------------------------------------------------------------
-- Lists: phrases and mutes
---------------------------------------------------------------------------
local function CleanText(text, limit)
	text = strtrim(tostring(text or "")):gsub("|", "")
	return E:Utf8Sub(text, limit)
end

function M:AddPhrase(text)
	text = CleanText(text, 100)
	if text == "" then return false, L["Type a word or phrase first."] end
	local list = self.db.filterPhrases
	for _, phrase in ipairs(list) do
		if phrase:lower() == text:lower() then return false, L["\"%s\" is already on the list."]:format(text) end
	end
	if #list >= MAX_PHRASES then return false, L["The list is full (%d phrases)."]:format(MAX_PHRASES) end
	list[#list + 1] = text
	self:ResetFilterDecisions()
	return true, L["Added \"%s\"."]:format(text)
end

function M:RemovePhrase(index)
	table.remove(self.db.filterPhrases, index)
	self:ResetFilterDecisions()
end

function M:AddMute(channel, name)
	channel, name = CleanText(channel, 40), CleanText(name, 60)
	channel = channel:gsub("^%d+%.%s*", ""):gsub("%s+%-%s+.*$", "")
	if channel == "" or name == "" then return false, L["Give a channel and a player name, for example Trade and Name-Realm."] end
	if self:FindMute(channel, name) then return false, L["%s is already muted in %s."]:format(name, channel) end
	local list = self.db.channelMutes
	if #list >= MAX_MUTES then return false, L["The list is full (%d mutes)."]:format(MAX_MUTES) end
	list[#list + 1] = { channel = channel, name = name }
	-- A new mute should work at once: the content filters go on.
	self.db.contentFilters = true
	self:ResetFilterDecisions()
	return true, L["%s is muted in %s."]:format(name, channel)
end

function M:RemoveMute(channel, name)
	local index = self:FindMute(channel, name)
	if not index then return false, L["%s is not muted in %s."]:format(tostring(name), tostring(channel)) end
	table.remove(self.db.channelMutes, index)
	self:ResetFilterDecisions()
	return true, L["%s is no longer muted in %s."]:format(name, channel)
end

-- The old comma field becomes the list, once.
function M:MigrateFilters()
	local db = self.db
	if type(db.spamWords) == "string" and strtrim(db.spamWords) ~= "" then
		for _, word in ipairs(self.SplitList(db.spamWords)) do self:AddPhrase(word) end
		db.spamWords = ""
	end
end

function M:FilterStatus()
	local db = self.db
	local parts = {}
	if #db.filterPhrases > 0 then parts[#parts + 1] = (#db.filterPhrases == 1 and L["%d phrase"] or L["%d phrases"]):format(#db.filterPhrases) end
	if #db.channelMutes > 0 then parts[#parts + 1] = (#db.channelMutes == 1 and L["%d mute"] or L["%d mutes"]):format(#db.channelMutes) end
	if db.filterCyrillic then parts[#parts + 1] = L["Cyrillic"] end
	if not db.contentFilters then
		return E:TextHex("warn") .. L["Paused: Content filters are off"] .. "|r"
	end
	if #parts == 0 then return L["Nothing is filtered"] end
	return L["On: %s"]:format(table.concat(parts, ", "))
end

---------------------------------------------------------------------------
-- Editors
---------------------------------------------------------------------------
function M:OpenPhraseEditor()
	return self:OpenListEditor({
		key = "phrases",
		title = L["Blocked phrases"],
		help = L["Lines with one of these words or phrases are hidden (ignoring upper and lower case). Test a line below before you add a phrase."],
		emptyText = L["No blocked phrases yet."],
		items = function() return M.db.filterPhrases end,
		text = function(phrase) return phrase end,
		controls = {
			{ kind = "button", label = L["Remove"], width = 60, click = function(_, index) M:RemovePhrase(index) end },
		},
		add = { hint = L["Word or phrase, for example: wts gold"], button = L["Add"], func = function(text) return M:AddPhrase(text) end },
		status = function() return ("%d / %d   %s"):format(#M.db.filterPhrases, MAX_PHRASES, M:FilterStatus()) end,
		extraHeight = 30,
		extra = function(window)
			local test = M.FlatInput(window, 220)
			test:SetPoint("TOPLEFT", window.body, "TOPLEFT", 10, window.extraTop)
			test.hint:SetText(L["Test a line"])
			window.test = test
			window.testResult = E:CreateText(window, E.tokens.size.small, "LEFT")
			window.testResult:SetPoint("LEFT", test, "RIGHT", 8, 0)
			window.testResult:SetPoint("RIGHT", window, "RIGHT", -10, 0)
			test:HookScript("OnTextChanged", function() M:RefreshListEditor("phrases") end)
			test:SetScript("OnEnterPressed", function(box) box:ClearFocus() end)
		end,
		refresh = function(window)
			local text = window.test and window.test:GetText() or ""
			if text == "" then
				window.testResult:SetText("")
			else
				local lower = PlainLower(text)
				local phrase = M:MatchPhrase(lower)
				if phrase then
					window.testResult:SetText(L["%s (phrase \"%s\")"]:format(E:TextHex("bad") .. L["Hidden"] .. "|r", phrase))
				elseif M.db.filterCyrillic and HasCyrillic(lower) then
					window.testResult:SetText(L["%s (Cyrillic letters)"]:format(E:TextHex("bad") .. L["Hidden"] .. "|r"))
				else
					window.testResult:SetText(E:TextHex("good") .. L["Shown"] .. "|r")
				end
			end
		end,
		footer = {
			{ label = L["Remove all"], width = 90, tip = L["Empties the list (asks first)."], click = function()
				if #M.db.filterPhrases == 0 then return end
				M:Confirm(L["Remove all %d blocked phrases?"]:format(#M.db.filterPhrases), function()
					wipe(M.db.filterPhrases)
					M:ResetFilterDecisions()
					M:RefreshListEditor("phrases")
				end)
			end },
		},
	})
end

function M:OpenMuteEditor()
	return self:OpenListEditor({
		key = "mutes",
		title = L["Channel mutes"],
		help = L["Hide one player in one public channel only. Whispers, guild and group chat and your /ignore list stay as they are. Right-click a sender in a channel line to mute them there."],
		emptyText = L["Nobody is muted."],
		items = function() return M.db.channelMutes end,
		text = function(rule) return tostring(rule.name), tostring(rule.channel) end,
		controls = {
			{ kind = "button", label = L["Remove"], width = 60, click = function(rule) M:RemoveMute(rule.channel, rule.name) end },
		},
		add = { hint = L["Channel, e.g. Trade"], hint2 = L["Player, e.g. Name-Realm"], button = L["Mute"],
			func = function(channel, name) return M:AddMute(channel, name) end },
		status = function() return ("%d / %d   %s"):format(#M.db.channelMutes, MAX_MUTES, M:FilterStatus()) end,
	})
end

---------------------------------------------------------------------------
-- Right-click on a sender in a channel line: "Mute in Trade"
---------------------------------------------------------------------------
local menuAdded = false

function M:AddMuteMenu()
	local menu = _G.Menu
	if menuAdded or not (type(menu) == "table" and menu.ModifyMenu) then return end
	menuAdded = true
	menu.ModifyMenu("MENU_UNIT_FRIEND", function(_, root, context)
		if not (Improve() and type(context) == "table" and root) then return end
		if Readable(context.chatType) ~= "CHANNEL" then return end
		local info = M:ChannelLineInfo(context.lineID)
		if not info then return end
		local channel = info.channel
		local label = channel:gsub("^%l", string.upper)
		root:CreateDivider()
		if M:FindMute(channel, info.sender) then
			root:CreateButton(L["Unmute in %s"]:format(label), function()
				local _, message = M:RemoveMute(label, info.sender)
				M:Print(message)
				M:RefreshListEditor("mutes")
			end)
		else
			root:CreateButton(L["Mute in %s"]:format(label), function()
				local _, message = M:AddMute(label, info.sender)
				M:Print(message)
				M:RefreshListEditor("mutes")
			end)
		end
	end)
end

---------------------------------------------------------------------------
-- /eui chat mute <channel>; <name>   /eui chat unmute <channel>; <name>
-- /eui chat filters   /eui chat mutes
---------------------------------------------------------------------------
E:AddCommand("chat", "mute <channel>; <name> | unmute <channel>; <name> | filters | mutes | colors | alerts | alert <word>", function(arg)
	local word, rest = strtrim(arg or ""):match("^(%S*)%s*(.-)$")
	word = (word or ""):lower()
	if not M.db then return end
	if word == "mute" or word == "unmute" then
		local channel, name = rest:match("^(.-)%s*;%s*(.+)$")
		if not channel or channel == "" then
			E:Print(L["Usage: /eui chat %s <channel>; <name>, for example /eui chat mute Trade; Name-Realm"]:format(word))
			return
		end
		local _, message
		if word == "mute" then _, message = M:AddMute(channel, name) else _, message = M:RemoveMute(channel, name) end
		E:Print(message)
		M:RefreshListEditor("mutes")
	elseif word == "alert" then
		if strtrim(rest or "") == "" then
			E:Print(L["Usage: /eui chat alert <word or phrase> (adds it, or removes it when it is on the list)"])
			return
		end
		local _, message = M:ToggleKeyword(rest)
		E:Print(message)
	elseif word == "filters" then
		M:OpenPhraseEditor()
	elseif word == "mutes" then
		M:OpenMuteEditor()
	elseif word == "colors" or word == "colours" then
		M:OpenColorEditor()
	elseif word == "alerts" then
		M:OpenKeywordEditor()
	else
		E:Print(L["/eui chat mute <channel>; <name>, unmute <channel>; <name>, filters, mutes, colors, alerts, alert <word>"])
	end
end)
