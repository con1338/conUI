-- EldoUI Chat, part 6: alert keywords and the Alerts tab.
--
--   * Keyword list: up to 50 words or phrases, each with its own sound
--     (none or any sound from the media list), plus Pause / Resume. The
--     old comma field moves into the list once.
--   * Alerts tab (off by default): every line that matches a keyword is
--     also copied into a normal docked chat tab called "Alerts" that has
--     no channels or message groups of its own. The copy shows the time,
--     the source ([Trade], [Guild], [Whisper]), a clickable sender and the
--     line in its source color, through the same rewrite as every chat
--     window. One copy per line ID, also from joined channels that no tab
--     shows. The tab flashes and never takes focus.
--   * The window is made outside combat only. Until it exists, up to 50
--     matches wait and come in afterwards; the options say why.
--
-- Presentation only: nothing is sent, secret lines (chat lockdown) are
-- never matched, and lines the content filters hide are not copied.
-- Written from scratch for EldoUI.
local _, E = ...
local L = E.L

local M = E:GetModule("Chat")

local IsSecret = function(value) return issecretvalue and issecretvalue(value) or false end
local Readable = E.Plain

local ALERT_NAME = "Alerts"
local MAX_KEYWORDS, MAX_QUEUE = 50, 50
M.ALERT_NAME = ALERT_NAME
M.MAX_KEYWORDS = MAX_KEYWORDS

local function Improve()
	return M.active and M:Allowed("improve")
end

local function Hex(r, g, b)
	return ("ff%02x%02x%02x"):format(math.floor((r or 1) * 255 + 0.5), math.floor((g or 1) * 255 + 0.5), math.floor((b or 1) * 255 + 0.5))
end

---------------------------------------------------------------------------
-- The keyword list
---------------------------------------------------------------------------
local function CleanText(text, limit)
	text = strtrim(tostring(text or "")):gsub("|", "")
	text = strtrim((text:gsub(",", " ")))
	return E:Utf8Sub(text, limit)
end

local function KeywordsChanged()
	if M.InvalidateKeywords then M.InvalidateKeywords() end
	M:RefreshListEditor("keywords")
end

function M:FindKeyword(text)
	local lower = tostring(text or ""):lower()
	for index, entry in ipairs(self.db.keywordList) do
		if type(entry) == "table" and tostring(entry.word):lower() == lower then return index end
	end
end

function M:AddKeyword(text, sound)
	text = CleanText(text, 60)
	if text == "" then return false, L["Type a word or phrase first."] end
	if self:FindKeyword(text) then return false, L["\"%s\" is already on the list."]:format(text) end
	local list = self.db.keywordList
	if #list >= MAX_KEYWORDS then return false, L["The list is full (%d keywords)."]:format(MAX_KEYWORDS) end
	list[#list + 1] = { word = text, sound = sound or "none" }
	KeywordsChanged()
	return true, L["Added \"%s\"."]:format(text)
end

function M:RemoveKeyword(index)
	if not self.db.keywordList[index] then return end
	table.remove(self.db.keywordList, index)
	KeywordsChanged()
end

-- /eui chat alert <phrase>: adds the phrase, or removes it when it is there.
function M:ToggleKeyword(text)
	local index = self:FindKeyword(CleanText(text, 60))
	if index then
		local word = self.db.keywordList[index].word
		self:RemoveKeyword(index)
		return true, L["Removed \"%s\" from the alert keywords."]:format(word)
	end
	return self:AddKeyword(text)
end

function M:SetKeywordSound(index, id)
	local entry = self.db.keywordList[index]
	if not entry then return end
	entry.sound = id or "none"
	if entry.sound ~= "none" then E:PlayMedia(entry.sound, nil, { preview = true }) end
	self:RefreshListEditor("keywords")
end

function M:SetKeywordsPaused(paused)
	self.db.keywordsPaused = paused and true or false
	KeywordsChanged()
	if E.RefreshConfig then E:RefreshConfig() end
end

-- The old comma field becomes the list once. Its one sound goes to every
-- word, so nothing sounds different after the update.
-- Sound settings saved before the pickers used the media list hold a bare
-- SOUNDKIT name ("TELL_MESSAGE") or "NONE"; they become media ids.
local function MediaSound(value)
	if type(value) ~= "string" or value == "" or value == "NONE" or value == "none" then return "none" end
	if value:find(":", 1, true) then return value end
	return "kit:" .. value
end
M.MediaSound = MediaSound

function M:MigrateSounds()
	self.db.keywordSound = MediaSound(self.db.keywordSound)
	self.db.whisperSound = MediaSound(self.db.whisperSound)
end

function M:MigrateKeywords()
	local db = self.db
	if type(db.keywords) ~= "string" or strtrim(db.keywords) == "" then return end
	local sound = MediaSound(db.keywordSound)
	for _, word in ipairs(self.SplitList(db.keywords)) do self:AddKeyword(word, sound) end
	db.keywords = ""
end

---------------------------------------------------------------------------
-- Sound and taskbar flash: once per line, however many windows show it
---------------------------------------------------------------------------
local sounded, soundedCount = {}, 0
local lastSound = 0

local function SoundOf(entry)
	if type(entry) ~= "table" then return nil end
	if entry.isName then
		local sound = MediaSound(M.db.keywordSound)
		return sound ~= "none" and sound or nil
	end
	return entry.sound ~= "none" and entry.sound or nil
end

function M:OnKeywordMatch(lineID, entry)
	if lineID ~= nil then
		if sounded[lineID] then return end
		sounded[lineID] = true
		soundedCount = soundedCount + 1
		if soundedCount > 400 then wipe(sounded); soundedCount = 0 end
	end
	if self:QuietNow() then return end
	local sound = SoundOf(entry)
	local now = GetTime()
	if sound and now - lastSound >= 2 then
		lastSound = now
		E:PlayMedia(sound)
	end
	if self.db.keywordFlash and FlashClientIcon then FlashClientIcon() end
end

---------------------------------------------------------------------------
-- The Alerts window
---------------------------------------------------------------------------
local alertFrame
local queue = {}
local copied, copiedCount = {}, 0
local reason            -- nil, "combat", "full", "unavailable"
local flushPending = false

local function MaxWindows()
	return Constants and Constants.ChatFrameConstants and Constants.ChatFrameConstants.MaxChatWindows or NUM_CHAT_WINDOWS or 10
end

local function WindowInfo(index)
	if not GetChatWindowInfo then return nil end
	local name, _, _, _, _, _, shown, _, docked = GetChatWindowInfo(index)
	return name, shown, docked
end

function M:IsAlertFrame(frame)
	if not frame then return false end
	if frame == alertFrame then return true end
	local id = frame.GetID and frame:GetID()
	if type(id) ~= "number" or id < 1 then return false end
	return (WindowInfo(id)) == ALERT_NAME
end

-- The open Alerts window, found by its name (also after a reload).
function M:FindAlertFrame()
	if alertFrame then
		local name, shown, docked = WindowInfo(alertFrame:GetID())
		if name == ALERT_NAME and (shown or docked) then return alertFrame end
		alertFrame = nil
	end
	for index = 1, MaxWindows() do
		local name, shown, docked = WindowInfo(index)
		if name == ALERT_NAME and (shown or docked) then
			alertFrame = _G["ChatFrame" .. index]
			return alertFrame
		end
	end
end

local function HasFreeWindow()
	for index = 3, MaxWindows() do
		local _, shown, docked = WindowInfo(index)
		if _G["ChatFrame" .. index] and not (shown or docked) then return true end
	end
	return false
end

local function SelectedWindow()
	local dock = _G.GENERAL_CHAT_DOCK
	if dock and FCFDock_GetSelectedWindow then return FCFDock_GetSelectedWindow(dock) end
	return _G.SELECTED_CHAT_FRAME
end

local function ClearSubscriptions(frame)
	if frame.RemoveAllMessageGroups then frame:RemoveAllMessageGroups()
	elseif ChatFrame_RemoveAllMessageGroups then ChatFrame_RemoveAllMessageGroups(frame) end
	if frame.RemoveAllChannels then frame:RemoveAllChannels()
	elseif ChatFrame_RemoveAllChannels then ChatFrame_RemoveAllChannels(frame) end
end

local function WaitForCombat()
	reason = "combat"
	if flushPending then return end
	flushPending = true
	E:RunOutOfCombat(function()
		flushPending = false
		M:FlushAlerts()
	end)
end

-- Finds the window or makes it (outside combat). Returns the frame or nil;
-- reason says why there is none.
function M:EnsureAlertFrame()
	local frame = self:FindAlertFrame()
	if frame then
		reason = nil
		return frame
	end
	if InCombatLockdown() then
		WaitForCombat()
		return nil
	end
	if type(FCF_OpenNewWindow) ~= "function" then
		reason = "unavailable"
		return nil
	end
	if not HasFreeWindow() then
		reason = "full"
		return nil
	end
	local selected = SelectedWindow()
	frame = FCF_OpenNewWindow(ALERT_NAME, true)
	if not frame then
		reason = "full"
		return nil
	end
	ClearSubscriptions(frame)
	-- The new tab must not take the focus away from the tab you read.
	if selected and selected ~= frame and FCF_SelectDockFrame then FCF_SelectDockFrame(selected) end
	alertFrame = frame
	reason = nil
	return frame
end

-- "Open Alerts tab" in the options and the keyword window.
function M:OpenAlertTab()
	if InCombatLockdown() then
		E:Print(L["The Alerts tab can be opened after combat."])
		return
	end
	local frame = self:EnsureAlertFrame()
	if not frame then
		E:Print(self:AlertStatus())
		return
	end
	if FCF_SelectDockFrame then FCF_SelectDockFrame(frame) end
	self:FlushAlerts()
end

local SOURCES = {
	SAY = "Say", YELL = E.Key("Yell"), EMOTE = "Emote", GUILD = "Guild", OFFICER = "Officer",
	PARTY = "Party", PARTY_LEADER = "Party", RAID = "Raid", RAID_LEADER = "Raid", RAID_WARNING = "Raid warning",
	INSTANCE_CHAT = "Instance", INSTANCE_CHAT_LEADER = "Instance", WHISPER = "Whisper", BN_WHISPER = "Whisper",
	COMMUNITIES_CHANNEL = "Community",
}

local function DisplayName(sender)
	if Ambiguate then
		local ok, short = pcall(Ambiguate, sender, "none")
		if ok and type(short) == "string" then return short end
	end
	return sender
end

local function SenderLink(chatType, sender, args, lineID)
	if chatType == "BN_WHISPER" then
		local bnID = Readable(args[13])
		if GetBNPlayerLink and bnID then
			local ok, link = pcall(GetBNPlayerLink, sender, ("[%s]"):format(sender), bnID, lineID, chatType, 0)
			if ok and type(link) == "string" then return link end
		end
		return ("[%s]"):format(sender)
	end
	local display = ("[%s]"):format(DisplayName(sender))
	local target = chatType == "CHANNEL" and Readable(args[8]) or nil
	if GetPlayerLink then
		local ok, link = pcall(GetPlayerLink, sender, display, lineID, chatType, target)
		if ok and type(link) == "string" then return link end
	end
	return ("|Hplayer:%s:%s:%s|h%s|h"):format(sender, tostring(lineID or 0), chatType, display)
end

-- The copy of one line, before the shared rewrite: [time] [source] [Name]: text
function M:AlertLine(event, args, stamp)
	local chatType = event:sub(10)
	local message, sender = Readable(args[1]), Readable(args[2])
	if type(message) ~= "string" then return nil end
	local lineID = Readable(args[11])
	local colorKey, source = chatType, SOURCES[chatType] and L[SOURCES[chatType]] or chatType
	if chatType == "CHANNEL" then
		local index = Readable(args[8])
		if index then colorKey = "CHANNEL" .. tostring(index) end
		local name = Readable(args[9])
		if type(name) ~= "string" or name == "" then name = Readable(args[4]) end
		name = type(name) == "string" and strtrim((name:gsub("^%d+%.%s*", ""):gsub("%s+%-%s+.*$", ""))) or ""
		source = name ~= "" and name or L["Channel"]
	end
	local types = _G.ChatTypeInfo
	local info = types and (types[colorKey] or types[chatType])
	local r, g, b = 1, 1, 1
	if info then r, g, b = info.r or 1, info.g or 1, info.b or 1 end
	local body
	if type(sender) == "string" and sender ~= "" then
		local link = SenderLink(chatType, sender, args, lineID)
		body = chatType == "EMOTE" and (link .. " " .. message) or (link .. ": " .. message)
	else
		body = message
	end
	local time = ("|c%s[%s]|r "):format(Hex(unpack(self.db.timestampColor)), stamp or E:FormatTime())
	return time .. ("[%s] "):format(source) .. body, r, g, b
end

local function Flash(frame)
	if SelectedWindow() ~= frame and FCF_StartAlertFlash then FCF_StartAlertFlash(frame) end
end

local function AddCopy(frame, item)
	local text, r, g, b = M:AlertLine(item.event, item.args, item.stamp)
	if not text then return end
	if M.FormatLine then text, r, g, b = M.FormatLine(frame, text, r, g, b, item.event, item.args, true) end
	frame:AddMessage(text, r, g, b)
end

function M:FlushAlerts()
	if #queue == 0 then return end
	local frame = self:EnsureAlertFrame()
	if not frame then return end
	local items = queue
	queue = {}
	for _, item in ipairs(items) do AddCopy(frame, item) end
	Flash(frame)
	self:RefreshListEditor("keywords")
end

function M:QueuedAlerts()
	return #queue
end

local function Copy(event, args)
	local item = { event = event, args = args, stamp = E:FormatTime() }
	local frame = M:EnsureAlertFrame()
	if frame and #queue == 0 then
		AddCopy(frame, item)
		Flash(frame)
		return
	end
	queue[#queue + 1] = item
	if #queue > MAX_QUEUE then table.remove(queue, 1) end
	if frame then M:FlushAlerts() end
	M:RefreshListEditor("keywords")
end

local function Pack(...)
	return { n = select("#", ...), ... }
end

-- Every keyword event, also from channels no tab shows.
local function OnChatEvent(_, event, ...)
	if not (Improve() and M.db.alertTab) or M.db.keywordsPaused then return end
	local args = Pack(...)
	local entry = M.MatchKeyword and M.MatchKeyword(event, args)
	if not entry then return end
	-- Hidden by the content filters (same decision as the chat windows).
	if M.FilterLine then
		local ok, hide = pcall(M.FilterLine, M, event, ...)
		if ok and hide then return end
	end
	local lineID = Readable(args[11])
	if lineID ~= nil then
		if copied[lineID] then return end
		copied[lineID] = true
		copiedCount = copiedCount + 1
		if copiedCount > 400 then wipe(copied); copiedCount = 0 end
	end
	M:OnKeywordMatch(lineID, entry)
	Copy(event, args)
end

function M:AlertStatus()
	local db = self.db
	if not db.alertTab then return L["Alerts tab off"] end
	if db.keywordsPaused then return E:TextHex("warn") .. L["Paused"] .. "|r" end
	local function Waiting(text)
		return #queue > 0 and L["%s (%d waiting)"]:format(text, #queue) or text
	end
	if reason == "combat" then return Waiting(E:TextHex("warn") .. L["Waiting for combat to end"] .. "|r") end
	if reason == "full" then return Waiting(E:TextHex("bad") .. L["No free chat window: close a chat tab"] .. "|r") end
	if reason == "unavailable" then return Waiting(E:TextHex("bad") .. L["This client can't make chat windows"] .. "|r") end
	if self:FindAlertFrame() then return L["Alerts tab ready"] end
	return L["The Alerts tab opens with the first match"]
end

---------------------------------------------------------------------------
-- Wiring
---------------------------------------------------------------------------
local owner = {}          -- its own event owner: the chat events are shared
local registered = false

function M:ApplyAlerts()
	self:MigrateSounds()
	self:MigrateKeywords()
	local want = Improve() and self.db.alertTab and true or false
	if want and not registered then
		for event in pairs(self.KEYWORD_EVENTS or {}) do E:RegisterEvent(event, OnChatEvent, owner) end
		registered = true
	elseif not want and registered then
		for event in pairs(self.KEYWORD_EVENTS or {}) do E:UnregisterEvent(event, owner) end
		registered = false
	end
	if not want then
		wipe(queue)
		reason = nil
	else
		self:FindAlertFrame()
		if #queue > 0 and not InCombatLockdown() then self:FlushAlerts() end
	end
	self:RefreshListEditor("keywords")
end

function M:DisableAlerts()
	if registered then
		for event in pairs(self.KEYWORD_EVENTS or {}) do E:UnregisterEvent(event, owner) end
		registered = false
	end
	wipe(queue)
	reason = nil
end

---------------------------------------------------------------------------
-- The keyword window
---------------------------------------------------------------------------
function M:ChooseKeywordSound(button, index)
	local groups, sources = {}, {}
	for _, entry in ipairs(E:MediaList("sound")) do
		if not groups[entry.source] then
			groups[entry.source] = {}
			sources[#sources + 1] = entry.source
		end
		table.insert(groups[entry.source], entry)
	end
	E.UIKit.ContextMenu(button, function(_, root)
		local function Radio(menu, label, id)
			menu:CreateRadio(label, function()
				local entry = M.db.keywordList[index]
				return entry ~= nil and entry.sound == id
			end, function() M:SetKeywordSound(index, id) end)
		end
		Radio(root, NONE or L["None"], "none")
		for _, source in ipairs(sources) do
			local menu = #sources > 1 and root:CreateButton(source) or root
			if menu.SetScrollMode then menu:SetScrollMode(360) end
			for _, entry in ipairs(groups[source]) do Radio(menu, entry.name, entry.id) end
		end
	end, { at = "owner" })
end

function M:OpenKeywordEditor()
	return self:OpenListEditor({
		key = "keywords",
		title = L["Alert keywords"],
		help = L["Lines with one of these words are highlighted and play the word's sound. With the Alerts tab on they are copied there too. Upper and lower case don't matter."],
		emptyText = L["No keywords yet. Your name still counts while \"Alert on my name\" is on."],
		items = function() return M.db.keywordList end,
		text = function(entry) return tostring(entry.word) end,
		controls = {
			{ kind = "button", label = L["Remove"], width = 60, click = function(_, index) M:RemoveKeyword(index) end },
			{ kind = "button", width = 150, tipTitle = L["Sound"], tip = L["The sound for this keyword. Choosing one plays it once."],
				label = function(entry) return entry and L["Sound: %s"]:format(E:MediaLabel("sound", entry.sound)) or L["Sound"] end,
				click = function(_, index, widget) M:ChooseKeywordSound(widget, index) end },
		},
		add = { hint = L["Word or phrase, for example: tank"], button = L["Add"], func = function(text) return M:AddKeyword(text) end },
		status = function() return ("%d / %d   %s"):format(#M.db.keywordList, MAX_KEYWORDS, M:AlertStatus()) end,
		footer = {
			{ label = function() return M.db.keywordsPaused and L["Resume"] or L["Pause"] end, width = 80,
				tip = L["Pause stops highlights, sounds and Alerts tab copies for all keywords; the list stays."],
				click = function() M:SetKeywordsPaused(not M.db.keywordsPaused) end },
			{ label = L["Open Alerts tab"], width = 110, tip = L["Opens the Alerts tab now (outside combat) and shows it."],
				shown = function() return M.db.alertTab end,
				click = function() M:OpenAlertTab() end },
		},
	})
end
