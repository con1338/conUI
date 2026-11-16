-- EldoUI Chat Input: long messages in parts, undo and redo, draft
-- recovery, and an opt-in party "is typing" line, all on Blizzard's own
-- chat edit boxes.
--
--   * Long messages: the edit box takes more than 255 letters while
--     "Split long messages" is on, and a part counter shows "1/3". Enter
--     sends part 1 through the game's own send (the edit box's
--     ChatFrame.OnEditBoxPreSendText hook, which the game offers for final
--     edits), and the rest comes back in the box with the same channel.
--     Every part is your own Enter press: EldoUI never sends a chat line by
--     itself. Parts end on a space where it can, never inside a link,
--     texture, color code or UTF-8 character, and not inside "quotes"
--     when another place fits.
--   * Undo and redo in the edit box: Ctrl+Z and Ctrl+Y.
--   * Drafts: a message closed with Escape, or open during a loading
--     screen, is kept (per character, at most the time you set) and comes
--     back with Ctrl+Shift+Z. Secure slash commands are never kept.
--   * "Mira is typing": off by default. With "Share that you are typing" on,
--     typing in party chat sends one short addon message at most every
--     few seconds to your party (party only, never during chat lockdown);
--     party members who share theirs show above the edit box.
-- Text the game keeps secret (chat lockdown) is never read, split, kept or
-- compared.
local _, E = ...
local L = E.L

local M = E:NewModule("ChatInput", {
	title = "Chat Input",
	category = "Chat & Social",
	desc = "Long chat messages in parts you send one Enter at a time, undo and redo, draft recovery and an opt-in party \"is typing\" line.",
	frames = { "EldoUI_ChatInputCounter", "EldoUI_ChatTyping" },
	movers = {},
	blizzard = {},
	savedKeys = { "profile.modules.ChatInput", "private.ChatInput" },
	optionsPage = "module:ChatInput",
	presets = { "Counter", "CounterTyping", "Large", "Minimal", "Plain" },
	reload = false,
	defaults = {
		split = true,           -- more than 255 letters, sent in parts
		maxLetters = 1020,      -- how much the edit box takes while splitting
		counter = true,         -- the part counter on the edit box
		counterSize = 11,
		undo = true,            -- Ctrl+Z / Ctrl+Y
		draftMinutes = 10,      -- 0 = no drafts
		shareTyping = false,    -- sends addon messages for you: off by default
		showTyping = true,      -- party members who share theirs
	},
})
E.ChatInput = M

local LIMIT = 255               -- bytes the server takes in one message
local DEFAULT_VISIBLE = 255     -- the template's visibleBytes ...
local DEFAULT_BYTES = 1280      -- ... and bytes
local UNDO_MAX = 50
local TYPING_PREFIX = "EUI_TYP"
local TYPING_INTERVAL = 4       -- seconds between "typing" messages
local TYPING_SHOW = 6           -- a typer shows this long after the last one

local function IsSecret(value) return issecretvalue and issecretvalue(value) or false end
local Readable = E.Plain

local function Lockdown()
	if E.CommRestricted then return E:CommRestricted() end
	if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown then
		local ok, locked = pcall(C_ChatInfo.InChatMessagingLockdown)
		return ok and locked and true or false
	end
	return false
end
M.Lockdown = Lockdown

-- The edit box's text, or nil when it is secret.
local function TextOf(editBox)
	local ok, text = pcall(editBox.GetText, editBox)
	if not ok or IsSecret(text) or type(text) ~= "string" then return nil end
	return text
end

---------------------------------------------------------------------------
-- Splitting
---------------------------------------------------------------------------
-- Escapes that must stay whole, tried at a "|".
local ATOMS = {
	"^|c%x%x%x%x%x%x%x%x|H.-|h.-|h|r", "^|H.-|h.-|h", "^|T.-|t", "^|A.-|a", "^|K.-|k",
	"^|c%x%x%x%x%x%x%x%x", "^|r", "^||",
}

local function AtomEnd(text, pos)
	for _, pattern in ipairs(ATOMS) do
		local _, stop = text:find(pattern, pos)
		if stop then return stop end
	end
	return pos
end

-- Parts of at most `limit` bytes. A cut goes at the last space outside
-- quotes, else the last space, else the last character boundary; never
-- inside an escape (an escape longer than a part stays whole).
function M.Split(text, limit)
	limit = limit or LIMIT
	local parts = {}
	if type(text) ~= "string" or IsSecret(text) then return parts end
	text = strtrim(text)
	local start = 1
	while start <= #text do
		if #text - start + 1 <= limit then
			parts[#parts + 1] = text:sub(start)
			break
		end
		local spaceOut, space, boundary
		local inQuote = false
		local pos = start
		local stopAt = start + limit -- the first byte that no longer fits
		while pos < stopAt do
			local byte = text:byte(pos)
			local atomEnd = pos
			if byte == 124 then atomEnd = AtomEnd(text, pos) end -- "|"
			if atomEnd >= stopAt then break end
			if atomEnd == pos then
				if byte == 34 then inQuote = not inQuote end -- '"'
				if byte == 32 then
					space = pos
					if not inQuote then spaceOut = pos end
				end
			end
			pos = atomEnd + 1
			-- A character boundary: the next byte starts a character.
			local nextByte = text:byte(pos)
			if pos > start and (not nextByte or nextByte < 0x80 or nextByte > 0xBF) then boundary = pos - 1 end
		end
		local cut = spaceOut or space
		local nextStart
		if cut and cut > start then
			nextStart = cut + 1
			cut = cut - 1
		else
			cut = boundary
			if not cut or cut < start then
				-- One escape longer than a part: keep it whole.
				cut = AtomEnd(text, start)
			end
			nextStart = cut + 1
		end
		parts[#parts + 1] = strtrim(text:sub(start, cut))
		start = nextStart
		while text:byte(start) == 32 do start = start + 1 end
	end
	for index = #parts, 1, -1 do
		if parts[index] == "" then table.remove(parts, index) end
	end
	return parts
end

-- The slash header that sends a text to the edit box's channel again, the
-- way the game writes it into the history ("/p", "/w Name", "/2").
function M.Header(editBox)
	local chatType = Readable(editBox:GetChatType())
	if type(chatType) ~= "string" then return nil end
	if chatType == "WHISPER" or chatType == "BN_WHISPER" then
		local target = Readable(editBox:GetTellTarget())
		if type(target) ~= "string" or target == "" then return nil end
		local command = _G[chatType == "WHISPER" and "SLASH_WHISPER1" or "SLASH_SMART_WHISPER1"] or _G.SLASH_WHISPER1
		return type(command) == "string" and (command .. " " .. target) or nil
	elseif chatType == "CHANNEL" then
		local channel = Readable(editBox:GetChannelTarget())
		return channel and ("/" .. tostring(channel)) or nil
	end
	local command = _G["SLASH_" .. chatType .. "1"]
	return type(command) == "string" and command or nil
end

-- A whisper target with a surname holds a space, which a typed "/w Name"
-- line would cut at: such a target goes back through the game's own
-- SendTell, which keeps the name whole. Returns the target or nil.
function M.TellTarget(editBox)
	if Readable(editBox:GetChatType()) ~= "WHISPER" then return nil end
	local target = Readable(editBox:GetTellTarget())
	return type(target) == "string" and target:find(" ", 1, true) and target or nil
end

-- Open the chat line to `target` the game's way and put `text` in it.
local function ReopenTell(target, chatFrame, text, fallback)
	local util = rawget(_G, "ChatFrameUtil")
	local tell = util and util.SendTell or rawget(_G, "ChatFrame_SendTell")
	if type(tell) ~= "function" then return false end
	tell(target, chatFrame)
	local active = util and util.GetActiveWindow or rawget(_G, "ChatEdit_GetActiveWindow")
	local box = type(active) == "function" and active() or fallback
	if box and type(text) == "string" and text ~= "" then
		box:SetText(text)
		if box.SetCursorPosition then pcall(box.SetCursorPosition, box, #text) end
	end
	return true
end
M.ReopenTell = ReopenTell

---------------------------------------------------------------------------
-- Edit box state (EldoUI's own tables: nothing is written onto the box)
---------------------------------------------------------------------------
local state = setmetatable({}, { __mode = "k" }) -- editBox -> { pending, undo, redo, last, header, ... }
local hooked = setmetatable({}, { __mode = "k" })
local limits = setmetatable({}, { __mode = "k" }) -- editBox -> { visible, bytes } before EldoUI changed them

local function State(editBox)
	local s = state[editBox]
	if not s then
		s = { undo = {}, redo = {}, last = "" }
		state[editBox] = s
	end
	return s
end
M.EditState = State

function M:ApplyLimits(editBox)
	local want = self.active and self.db.split and not Lockdown()
	if want then
		if not limits[editBox] then
			limits[editBox] = {
				visible = editBox.GetVisibleTextByteLimit and editBox:GetVisibleTextByteLimit() or DEFAULT_VISIBLE,
				bytes = editBox.GetMaxBytes and editBox:GetMaxBytes() or DEFAULT_BYTES,
			}
		end
		local visible = math.max(LIMIT, math.floor(self.db.maxLetters or 1020))
		if editBox.SetVisibleTextByteLimit then editBox:SetVisibleTextByteLimit(visible) end
		if editBox.SetMaxBytes then editBox:SetMaxBytes(visible + 1025) end
	elseif limits[editBox] then
		local old = limits[editBox]
		if editBox.SetVisibleTextByteLimit then editBox:SetVisibleTextByteLimit(old.visible) end
		if editBox.SetMaxBytes then editBox:SetMaxBytes(old.bytes) end
		limits[editBox] = nil
	end
end

---------------------------------------------------------------------------
-- Counter and hints
---------------------------------------------------------------------------
local counter

local function Counter()
	if counter then return counter end
	counter = CreateFrame("Frame", "EldoUI_ChatInputCounter", UIParent)
	counter:SetSize(80, 16)
	counter:SetFrameStrata("DIALOG")
	counter:EnableMouse(false)
	counter.text = E:CreateText(counter, M.db and M.db.counterSize or 11, "RIGHT")
	counter.text:SetPoint("RIGHT")
	counter:Hide()
	return counter
end

function M:CounterText(editBox)
	local text = TextOf(editBox)
	if not text then return "" end
	if text == "" then
		local draft = self:Draft()
		if draft then return E:TokenHex(E.tokens.text.secondary) .. L["Ctrl+Shift+Z: your draft"] .. "|r" end
		return ""
	end
	local parts = self.db.split and #text > LIMIT and M.Split(text) or nil
	if parts and #parts > 1 then
		return E:Highlight(("1/%d"):format(#parts))
	end
	if #text >= LIMIT - 55 then
		local color = #text > LIMIT and E.tokens.text.warn or E.tokens.text.secondary
		return E:TokenHex(color) .. ("%d/%d"):format(#text, LIMIT) .. "|r"
	end
	return ""
end

function M:UpdateCounter(editBox)
	local frame = Counter()
	if not (self.active and self.db.counter and editBox and editBox:IsShown()) then
		frame:Hide()
		return
	end
	local text = self:CounterText(editBox)
	if text == "" then
		frame:Hide()
		return
	end
	E:SetFont(frame.text, self.db.counterSize)
	frame.text:SetText(text)
	frame:SetWidth(math.max(40, (frame.text:GetStringWidth() or 40) + 4))
	frame:ClearAllPoints()
	-- Just above the box's right end: inside it, it would cover the emoji
	-- button and the last letters typed.
	frame:SetPoint("BOTTOMRIGHT", editBox, "TOPRIGHT", -8, 2)
	frame:SetFrameLevel((editBox:GetFrameLevel() or 1) + 5)
	frame:Show()
end

---------------------------------------------------------------------------
-- Sending in parts
---------------------------------------------------------------------------
-- Inside the game's send, after it parsed the channel and before it reads
-- the text: keep part 1 in the box, hold the rest.
function M:OnPreSend(editBox)
	if not (self.active and editBox) then return end
	local s = State(editBox)
	s.pending, s.pendingHeader, s.pendingTell = nil, nil, nil
	s.sent = true
	if not self.db.split then return end
	local text = TextOf(editBox)
	if not text then return end
	text = strtrim(text)
	if #text <= LIMIT then return end
	local parts = M.Split(text)
	if #parts <= 1 then return end
	local header = M.Header(editBox)
	if not header then return end -- nowhere to put the rest: the game sends as it would
	-- Part 1 is the start of the text; the rest is everything after it,
	-- exactly as typed.
	editBox:SetText(parts[1])
	s.pending = strtrim(text:sub(#parts[1] + 1))
	s.pendingHeader = header
	s.pendingTell = M.TellTarget(editBox)
end

-- After the game sent part 1 and cleared the box: the rest comes back,
-- addressed the same way, for your next Enter.
function M:AfterEnter(editBox)
	local s = state[editBox]
	if not s then return end
	local pending, header, tell = s.pending, s.pendingHeader, s.pendingTell
	s.pending, s.pendingHeader, s.pendingTell = nil, nil, nil
	if s.sent then
		s.sent = nil
		-- The sent text is no draft: an Escape on the next empty box keeps nothing.
		s.draftText, s.header = nil, nil
		wipe(s.undo)
		wipe(s.redo)
		self:ClearDraft()
		self:StopTyping()
	end
	if not (self.active and pending and header) then return end
	if tell and ReopenTell(tell, editBox.chatFrame, pending, editBox) then return end
	local open = ChatFrameUtil and ChatFrameUtil.OpenChat or rawget(_G, "ChatFrame_OpenChat")
	if open then open(header .. " " .. pending, editBox.chatFrame) end
end

---------------------------------------------------------------------------
-- Undo and redo
---------------------------------------------------------------------------
function M:OnTextChanged(editBox, userInput)
	local s = State(editBox)
	local text = TextOf(editBox)
	if not text then
		s.last = ""
		return
	end
	if userInput and not s.applying and self.db.undo then
		local now = GetTime()
		-- One step per word, paste or pause, not per letter.
		local jump = math.abs(#text - #s.last) > 1
		local word = text:sub(-1) == " "
		if s.last ~= text and (jump or word or now - (s.at or 0) > 1.5 or #s.undo == 0) then
			s.undo[#s.undo + 1] = s.last
			if #s.undo > UNDO_MAX then table.remove(s.undo, 1) end
			s.at = now
		end
		wipe(s.redo)
	end
	s.last = text
	if text ~= "" then
		s.header = M.Header(editBox)
		s.tell = M.TellTarget(editBox)
		s.draftText = text
	end
	if userInput then self:NoteTyping(editBox) end
	self:UpdateCounter(editBox)
end

local function SetBoxText(editBox, text)
	local s = State(editBox)
	s.applying = true
	editBox:SetText(text)
	if editBox.SetCursorPosition then pcall(editBox.SetCursorPosition, editBox, #text) end
	s.applying = false
	s.last = text
end

function M:Undo(editBox)
	local s = State(editBox)
	local current = TextOf(editBox)
	if not current or #s.undo == 0 then return false end
	s.redo[#s.redo + 1] = current
	SetBoxText(editBox, table.remove(s.undo))
	return true
end

function M:Redo(editBox)
	local s = State(editBox)
	local current = TextOf(editBox)
	if not current or #s.redo == 0 then return false end
	s.undo[#s.undo + 1] = current
	SetBoxText(editBox, table.remove(s.redo))
	return true
end

function M:OnKeyDown(editBox, key)
	if not self.active or not IsControlKeyDown() then return end
	if key == "Z" and IsShiftKeyDown() then
		self:RestoreDraft(editBox)
	elseif key == "Z" and self.db.undo then
		self:Undo(editBox)
	elseif key == "Y" and self.db.undo then
		self:Redo(editBox)
	end
end

---------------------------------------------------------------------------
-- Drafts (per character, never secret, never a secure command)
---------------------------------------------------------------------------
local function DraftStore()
	return E:GetPrivate("ChatInput") or {}
end

local function Keepable(text)
	if type(text) ~= "string" or IsSecret(text) then return false end
	text = strtrim(text)
	if text == "" then return false end
	local command = text:match("^(/[^%s]+)")
	if command and IsSecureCmd then
		local ok, secure = pcall(IsSecureCmd, command:lower())
		if ok and secure then return false end
	end
	return true
end

function M:SaveDraft(text, header, tell)
	if (self.db.draftMinutes or 0) <= 0 or Lockdown() or not Keepable(text) then return false end
	if header and not Keepable(header) then header = nil end
	if type(tell) ~= "string" or tell == "" then tell = nil end
	local store = DraftStore()
	store.draft = { text = strtrim(text):sub(1, 2000), header = header, tell = tell, at = time() }
	return true
end

function M:Draft()
	local store = DraftStore()
	local draft = store.draft
	if type(draft) ~= "table" or type(draft.text) ~= "string" then return nil end
	local minutes = self.db.draftMinutes or 0
	if minutes <= 0 or time() - (draft.at or 0) > minutes * 60 then
		store.draft = nil
		return nil
	end
	return draft
end

function M:ClearDraft()
	DraftStore().draft = nil
end

function M:RestoreDraft(editBox)
	local draft = self:Draft()
	if not draft then return false end
	local text = draft.text
	-- A whisper to a name with a surname: the game's own tell keeps it whole.
	if type(draft.tell) == "string" and ReopenTell(draft.tell, editBox.chatFrame, text, editBox) then
		self:ClearDraft()
		self:UpdateCounter(editBox)
		return true
	end
	if draft.header and draft.header ~= "" then text = draft.header .. " " .. text end
	SetBoxText(editBox, text)
	self:ClearDraft()
	self:UpdateCounter(editBox)
	return true
end

-- Escape: the game cleared the box; the text it held becomes the draft.
function M:AfterEscape(editBox)
	local s = state[editBox]
	if not s then return end
	if s.draftText and s.draftText ~= "" then self:SaveDraft(s.draftText, s.header, s.tell) end
	s.draftText, s.last = nil, ""
	wipe(s.undo)
	wipe(s.redo)
	self:StopTyping()
	self:UpdateCounter(editBox)
end

-- A loading screen with a message open.
function M:SaveOpenDrafts()
	for editBox in pairs(state) do
		local text = editBox:IsShown() and TextOf(editBox)
		if text and text ~= "" then self:SaveDraft(text, M.Header(editBox), M.TellTarget(editBox)) end
	end
end

---------------------------------------------------------------------------
-- "Is typing" (opt-in, party only)
---------------------------------------------------------------------------
local lastSent, typingSent = 0, false
local typers = {} -- sender -> time of their last message

local function PartyChat(editBox)
	local chatType = Readable(editBox:GetChatType())
	return chatType == "PARTY" or chatType == "PARTY_LEADER"
end

local function InHomeParty()
	if not IsInGroup or IsInRaid() then return false end
	local home = rawget(_G, "LE_PARTY_CATEGORY_HOME")
	if home then return IsInGroup(home) and true or false end
	return IsInGroup() and true or false
end

function M:NoteTyping(editBox)
	if not (self.active and self.db.shareTyping) or not PartyChat(editBox) or not InHomeParty() then return false end
	if Lockdown() then return false end
	local now = GetTime()
	if now - lastSent < TYPING_INTERVAL then return false end
	lastSent = now
	typingSent = true
	return E:SendComm(TYPING_PREFIX, "T", "PARTY") and true or false
end

function M:StopTyping()
	if not typingSent then return false end
	typingSent = false
	if not (self.active and self.db.shareTyping) or Lockdown() or not InHomeParty() then return false end
	if GetTime() - lastSent > TYPING_SHOW then return false end
	return E:SendComm(TYPING_PREFIX, "S", "PARTY") and true or false
end

local typingFrame, ticker

local function TypingFrame()
	if typingFrame then return typingFrame end
	typingFrame = CreateFrame("Frame", "EldoUI_ChatTyping", UIParent)
	typingFrame:SetSize(300, 16)
	typingFrame:SetFrameStrata("DIALOG")
	typingFrame:EnableMouse(false)
	typingFrame.text = E:CreateText(typingFrame, M.db and M.db.counterSize or 11, "LEFT")
	typingFrame.text:SetPoint("LEFT")
	typingFrame.text:SetTextColor(unpack(E.tokens.text.secondary))
	typingFrame:Hide()
	return typingFrame
end

local function ShownName(sender)
	local streamer = E.Streamer
	local alias = streamer and streamer.SenderAlias and streamer:SenderAlias(sender)
	if alias then return alias end
	local short = Ambiguate and Readable(Ambiguate(sender, "none"))
	if type(short) == "string" and short ~= "" then return short end
	return (sender:gsub("%-.*$", ""))
end

function M:TypingText()
	local now, names = GetTime(), {}
	for sender, at in pairs(typers) do
		if now - at > TYPING_SHOW then typers[sender] = nil else names[#names + 1] = ShownName(sender) end
	end
	table.sort(names)
	if #names == 0 then return "" end
	if #names == 1 then return L["%s is typing..."]:format(names[1]) end
	if #names == 2 then return L["%s and %s are typing..."]:format(names[1], names[2]) end
	return L["%d party members are typing..."]:format(#names)
end

function M:UpdateTyping()
	local frame = TypingFrame()
	local text = (self.active and self.db.showTyping) and self:TypingText() or ""
	if text == "" then
		frame:Hide()
		if ticker then ticker:Cancel() ticker = nil end
		return
	end
	local editBox = (ChatFrameUtil and ChatFrameUtil.GetLastActiveWindow and ChatFrameUtil.GetLastActiveWindow())
		or (DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.editBox)
	if not editBox then
		frame:Hide()
		return
	end
	E:SetFont(frame.text, self.db.counterSize)
	frame.text:SetText(text)
	frame:ClearAllPoints()
	frame:SetPoint("BOTTOMLEFT", editBox, "TOPLEFT", 4, 2)
	frame:Show()
	if not ticker and C_Timer and C_Timer.NewTicker then
		ticker = C_Timer.NewTicker(1, function() M:UpdateTyping() end)
	end
end

function M:OnTypingMessage(payload, sender)
	if not (self.active and self.db.showTyping) or type(sender) ~= "string" then return end
	if payload == "T" then
		typers[sender] = GetTime()
	elseif payload == "S" then
		typers[sender] = nil
	else
		return
	end
	self:UpdateTyping()
end

---------------------------------------------------------------------------
-- Hooks (post-hooks and EventRegistry callbacks only)
---------------------------------------------------------------------------
function M:HookEditBox(editBox)
	if not editBox or hooked[editBox] or not editBox.HookScript then return end
	hooked[editBox] = true
	editBox:HookScript("OnTextChanged", function(box, userInput) if M.active then M:OnTextChanged(box, userInput) end end)
	editBox:HookScript("OnEnterPressed", function(box) if M.active then M:AfterEnter(box) end end)
	editBox:HookScript("OnEscapePressed", function(box) if M.active then M:AfterEscape(box) end end)
	editBox:HookScript("OnKeyDown", function(box, key) M:OnKeyDown(box, key) end)
	editBox:HookScript("OnEditFocusGained", function(box)
		if not M.active then return end
		M:ApplyLimits(box)
		M:UpdateCounter(box)
	end)
	editBox:HookScript("OnHide", function() if counter then counter:Hide() end end)
	self:ApplyLimits(editBox)
end

function M:HookAll()
	for index = 1, (rawget(_G, "NUM_CHAT_WINDOWS") or 10) do
		local editBox = _G["ChatFrame" .. index .. "EditBox"]
		if editBox then self:HookEditBox(editBox) end
	end
end

local registry = {}

function M:OnInitialize()
	E:RegisterPrivate("ChatInput", {})
end

function M:OnEnable()
	self:HookAll()
	if EventRegistry and not self.registryHooked then
		self.registryHooked = true
		EventRegistry:RegisterCallback("ChatFrame.OnEditBoxPreSendText", function(_, editBox)
			local ok, err = pcall(M.OnPreSend, M, editBox)
			if not ok then geterrorhandler()(err) end
		end, registry)
		-- Temporary whisper windows bring their own edit box.
		EventRegistry:RegisterCallback("ChatFrame.OnEditBoxFocusGained", function(_, editBox)
			if M.active and not hooked[editBox] then
				M:HookEditBox(editBox)
				M:ApplyLimits(editBox)
			end
		end, registry)
	end
	if not self.commRegistered and E.RegisterComm then
		-- Registering the prefix sends nothing; messages are ignored while
		-- "Show who is typing" is off.
		self.commRegistered = E:RegisterComm(TYPING_PREFIX, function(payload, sender) M:OnTypingMessage(payload, sender) end, { trusted = "group" }) and true or false
	end
	self:RegisterEvent("PLAYER_LEAVING_WORLD", function() M:SaveOpenDrafts() end)
	self:RegisterEvent("GROUP_ROSTER_UPDATE", function() if not InHomeParty() then wipe(typers) M:UpdateTyping() end end)
	self:OnProfileChanged()
end

function M:OnDisable()
	self:UnregisterEvent("PLAYER_LEAVING_WORLD")
	self:UnregisterEvent("GROUP_ROSTER_UPDATE")
	for editBox in pairs(hooked) do self:ApplyLimits(editBox) end
	if counter then counter:Hide() end
	wipe(typers)
	self:UpdateTyping()
end

function M:OnProfileChanged()
	for editBox in pairs(hooked) do self:ApplyLimits(editBox) end
	if counter then E:SetFont(counter.text, self.db.counterSize) end
	if not self.db.showTyping then wipe(typers) end
	self:UpdateTyping()
end
M.refreshWhenOff = function(module)
	for editBox in pairs(hooked) do module:ApplyLimits(editBox) end
end

---------------------------------------------------------------------------
-- Options and styles
---------------------------------------------------------------------------
M.options = {
	{ type = "description", label = "Works on the game's chat edit box. Every part of a long message is sent by your own Enter press; EldoUI never sends a line by itself." },
	{ type = "header", label = "Long messages" },
	{ type = "toggle", key = "split", label = "Split long messages", desc = "Past 255 letters, Enter sends the first part and puts the rest back in the box for your next Enter. Parts end on a space and keep links whole." },
	{ type = "range", key = "maxLetters", label = "Longest message", min = 510, max = 2000, step = 10, dependsOn = "split",
		desc = "How many letters the edit box takes while splitting is on (links count with their hidden part)." },
	{ type = "toggle", key = "counter", label = "Part counter", desc = "Shows 1/3 on the edit box while a message needs more than one part, and the letters used close to the 255 limit." },
	{ type = "range", key = "counterSize", label = "Text size", min = 9, max = 16, step = 1, desc = "Size of the part counter and the typing line.",
		disabled = function() return not (M.db.counter or M.db.showTyping) and L["Turn on \"Part counter\" or \"Show who is typing\" first."] end },
	{ type = "header", label = "Undo and drafts" },
	{ type = "toggle", key = "undo", label = "Undo and redo", desc = "Ctrl+Z undoes your last change in the edit box, Ctrl+Y brings it back. One step per word or paste." },
	{ type = "range", key = "draftMinutes", label = "Keep drafts", unit = "min", min = 0, max = 60, step = 1,
		zeroText = "Off", desc = "A message closed with Escape, or open during a loading screen, comes back with Ctrl+Shift+Z for this long. Secure commands (/cast and the like) are never kept." },
	{ type = "header", label = "Party typing" },
	{ type = "toggle", key = "shareTyping", label = "Share that you are typing", desc = "While you type in party chat, your party members who use EldoUI see that you are typing. Sends one short addon message at most every 4 seconds, party only, never during boss fights. Off by default." },
	{ type = "toggle", key = "showTyping", label = "Show who is typing", desc = "\"Mira is typing...\" above the edit box when party members share theirs." },
}

E:RegisterStyles("ChatInput", {
	{ key = "Plain", title = "Plain", desc = "Long messages in parts, no counter and no typing line.",
		settings = { split = true, counter = false, counterSize = 11, showTyping = false } },
	{ key = "Counter", title = "Counter", desc = "The part counter on the edit box.",
		settings = { split = true, counter = true, counterSize = 11, showTyping = false } },
	{ key = "CounterTyping", title = "Counter and typing", desc = "The part counter, and who in your party is typing (when they share it).",
		settings = { split = true, counter = true, counterSize = 11, showTyping = true } },
	{ key = "Large", title = "Large", desc = "A bigger counter and typing line.",
		settings = { split = true, counter = true, counterSize = 14, showTyping = true } },
	{ key = "Minimal", title = "Minimal", desc = "Only undo and drafts; long messages are cut at 255 letters as the game does.",
		settings = { split = false, counter = false, showTyping = false, undo = true } },
})
