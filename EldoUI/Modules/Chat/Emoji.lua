-- EldoUI Chat, part 8: emoji in chat. Part of the "improve" switch of
-- the Blizzard element chat-frames.
--
--   * Unicode emoji (also ZWJ sequences, skin tones, flags, keycaps) and
--     :shortcode: tokens (:smile:, :thumbsup:) in chat lines show as small
--     pictures. A line hook (Messages.lua, M:AddLineHook) rewrites the
--     plain text of a line; hyperlinks, textures and color codes are never
--     touched. Hover an emoji for its name and shortcode.
--   * Text smileys (:) ;) <3 ...) turn into emoji, on by default, but only
--     when they stand alone: whitespace or the line start/end on both sides.
--     So http://, 12:30, :Dalaran, item:123 and links stay as they are.
--     Only what you see changes; what you send stays your own text.
--   * A smiley button on the chat edit box opens the picker: search, the
--     official categories, a Recent row and a skin tone choice. Picked emoji
--     go in as :shortcode: (readable for everyone) or, by option, as the
--     Unicode character.
--   * Autocomplete: typing :sm in the edit box lists matching emoji; Tab or
--     a click puts the shortcode in.
--
-- The pictures and the emoji list live in the load-on-demand folder
-- EldoUI_Emoji (tools/emoji/gen_emoji.py: Twemoji graphics, CC-BY 4.0;
-- emojibase names and shortcodes, MIT). It is loaded the first time chat
-- emoji are on, never in combat.
--
-- Taint rules: EldoUI never opens or focuses the chat edit box. Emoji only
-- go into an edit box that is already open, through its own Insert/SetText
-- widget methods, and never into a line that starts with "/" (so /cast,
-- /target and other secure commands are never touched). Tab completion
-- uses ChatEdit_CustomTabPressed, which Blizzard keeps global and calls
-- through securecall for exactly this purpose; with no emoji token before
-- the cursor it hands over to the previous handler and the game's own Tab
-- (channel and whisper target cycling) runs as before.
--
-- Midnight rule: secret lines (chat lockdown) are never read; the line hook
-- does not run for them, and the rewrite checks again.
-- Written from scratch for EldoUI; no code from other addons.
local _, E = ...
local L = E.L

local M = E:GetModule("Chat")
local ADDON = "EldoUI_Emoji"
local FORMATS = { [1] = true }

local IsSecret = function(value) return issecretvalue and issecretvalue(value) or false end

for key, value in pairs({
	emoji = true,             -- emoji pictures in chat lines
	emojiSize = 0,            -- 0 = the chat font's height, else pixels
	emojiSmileys = true,      -- :) shows as an emoji (standalone only)
	emojiAutocomplete = true, -- :sm in the edit box lists matches
	emojiSend = "shortcode",  -- shortcode, unicode
	emojiTone = "none",       -- none, light, medium-light, medium, medium-dark, dark
}) do
	if M.defaults[key] == nil then M.defaults[key] = value end
end
-- Recently picked emoji, per character.
E:RegisterPrivate("chatEmoji", { recent = {} })

local Emoji = {}
M.Emoji = Emoji

local TONES = { "none", "light", "medium-light", "medium", "medium-dark", "dark" }
local TONE_INDEX = {}
for index, key in ipairs(TONES) do TONE_INDEX[key] = index - 1 end
local RECENT_MAX = 9

---------------------------------------------------------------------------
-- Data: EldoUI_Emoji
-- status: "pending", "loaded", "missing", "disabled", "old", "failed"
---------------------------------------------------------------------------
local D               -- the EldoUI_Emoji table once adopted
local status, loadReason = "pending", nil
local byKey = {}      -- byte sequence -> list index (chars and aliases)
local byCode = {}     -- shortcode -> list index
local codeList = {}   -- sorted shortcodes of base emoji, for autocomplete
local smileys = {}    -- text smiley -> list index
local tones = {}      -- base index -> { [1..5] = index of the single-tone variant }
local groupLists = {} -- picker group -> base indexes in order
local maxCodepoints = 10
local loadQueued = false

local function FirstCode(entry)
	return entry and entry[3] and entry[3]:match("^(%S+)") or nil
end

local function Adopt()
	if D then return true end
	local data = rawget(_G, ADDON)
	if type(data) ~= "table" or type(data.list) ~= "table" then return false end
	if not FORMATS[tonumber(data.format) or 0] then
		status = "old"
		return false
	end
	wipe(byKey); wipe(byCode); wipe(codeList); wipe(smileys); wipe(tones); wipe(groupLists)
	for index, entry in ipairs(data.list) do
		if byKey[entry[1]] == nil then byKey[entry[1]] = index end
		for code in (entry[3] or ""):gmatch("%S+") do
			if byCode[code] == nil then
				byCode[code] = index
				if (entry[5] or 0) == 0 then codeList[#codeList + 1] = code end
			end
		end
		local base, tone = entry[5] or 0, entry[6] or 0
		if base > 0 then
			if tone > 0 then
				tones[base] = tones[base] or {}
				if tones[base][tone] == nil then tones[base][tone] = index end
			end
		elseif (entry[4] or 0) > 0 then
			local list = groupLists[entry[4]] or {}
			groupLists[entry[4]] = list
			list[#list + 1] = index
		end
	end
	for text, index in pairs(data.aliases or {}) do
		if byKey[text] == nil then byKey[text] = index end
	end
	for text, index in pairs(data.smileys or {}) do smileys[text] = index end
	table.sort(codeList)
	maxCodepoints = tonumber(data.maxCodepoints) or 10
	D = data
	status = "loaded"
	return true
end
Emoji.Adopt = Adopt

-- Load EldoUI_Emoji now if we may. Never in combat: the list is a large
-- file and would stall a frame; a combat attempt waits for the end.
function Emoji:Load()
	if D then return true end
	if Adopt() then
		self:OnDataLoaded()
		return true
	end
	if status == "missing" or status == "disabled" or status == "old" then return false end
	if InCombatLockdown() then
		if not loadQueued then
			loadQueued = true
			E:RunOutOfCombat(function()
				loadQueued = false
				Emoji:Refresh()
			end)
		end
		return false
	end
	if not (C_AddOns and C_AddOns.GetAddOnInfo and C_AddOns.LoadAddOn) then
		status = "failed"
		return false
	end
	local name, _, _, loadable, reason = C_AddOns.GetAddOnInfo(ADDON)
	if not name then
		status = "missing"
		return false
	end
	if reason == "DISABLED" or reason == "DEP_DISABLED" then
		status = "disabled"
		return false
	end
	local loaded, why = C_AddOns.LoadAddOn(ADDON)
	if loaded and Adopt() then
		self:OnDataLoaded()
		return true
	end
	if status ~= "old" then
		status = "failed"
		loadReason = why or reason or (loadable == false and "NOT_LOADABLE") or nil
	end
	return false
end

function Emoji:HasData() return D ~= nil end

-- Memory EldoUI_Emoji uses in KB (nil when it is not loaded).
function Emoji:DataMemory()
	if not D or not (UpdateAddOnMemoryUsage and GetAddOnMemoryUsage) then return nil end
	pcall(UpdateAddOnMemoryUsage)
	local ok, kb = pcall(GetAddOnMemoryUsage, ADDON)
	if ok and type(kb) == "number" and not IsSecret(kb) then return kb end
	return nil
end

function Emoji:StatusText()
	if D then
		local kb = self:DataMemory()
		if kb then
			return L["Emoji ready: %d emoji, Twemoji %s, %.1f MB in memory."]:format(#D.list, tostring(D.twemoji or "?"), kb / 1024)
		end
		return L["Emoji ready: %d emoji, Twemoji %s."]:format(#D.list, tostring(D.twemoji or "?"))
	end
	if status == "missing" then return L["The EldoUI_Emoji folder is not installed. Put it next to the EldoUI folder in Interface\\AddOns."] end
	if status == "disabled" then return L["EldoUI_Emoji is switched off in the addon list."] end
	if status == "old" then return L["EldoUI_Emoji does not match this EldoUI version. Update both folders."] end
	if status == "failed" then return L["EldoUI_Emoji could not load (%s)."]:format(tostring(loadReason or L["unknown"])) end
	return L["EldoUI_Emoji loads when emoji are on and you are out of combat."]
end

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------
-- Chat on, message extras allowed and emoji switched on.
function Emoji:Wanted()
	return M.active and M.db and M.db.emoji and M:Allowed("improve") and true or false
end

function Emoji:Active()
	return D ~= nil and self:Wanted()
end

local function Store()
	local store = E:GetPrivate("chatEmoji")
	if type(store) ~= "table" then return { recent = {} } end
	if type(store.recent) ~= "table" then store.recent = {} end
	return store
end

function Emoji:Entry(index) return D and D.list[index] end

-- The byte sequence -> list index, or nil.
function Emoji:Lookup(text) return byKey[text] end

-- The shortcode -> list index, or nil.
function Emoji:FromCode(code) return code and byCode[code:lower()] or nil end

-- The variant of a base emoji in the chosen skin tone (or the emoji itself).
function Emoji:WithTone(index, tone)
	tone = tone or TONE_INDEX[M.db.emojiTone] or 0
	local entry = D and D.list[index]
	if not entry or tone == 0 then return index end
	local base = (entry[5] or 0) > 0 and entry[5] or index
	return tones[base] and tones[base][tone] or index
end

---------------------------------------------------------------------------
-- Texture tags
---------------------------------------------------------------------------
local tagCache = {}
local tagSize

-- Sheet path and pixel rectangle of list[index].
function Emoji:Cell(index)
	local sheets = D.sheets
	local perSheet = (sheets.size / sheets.cell) ^ 2
	local perRow = sheets.size / sheets.cell
	local sheet = math.floor((index - 1) / perSheet) + 1
	local slot = (index - 1) % perSheet
	local left = (slot % perRow) * sheets.cell
	local top = math.floor(slot / perRow) * sheets.cell
	return sheets.path:format(sheet), left, left + sheets.cell, top, top + sheets.cell, sheets.size
end

-- A texture widget shows list[index].
function Emoji:SetIcon(texture, index)
	if not (D and index and D.list[index]) then
		texture:SetTexture(nil)
		return
	end
	local path, left, right, top, bottom, size = self:Cell(index)
	texture:SetTexture(path)
	texture:SetTexCoord(left / size, right / size, top / size, bottom / size)
end

-- The chat text for list[index]: the picture inside an addon link, so
-- hovering it shows the name. size 0 follows the font.
function Emoji:Tag(index, size)
	size = size or tonumber(M.db.emojiSize) or 0
	if size ~= tagSize then
		wipe(tagCache)
		tagSize = size
	end
	local tag = tagCache[index]
	if not tag then
		local path, left, right, top, bottom, dim = self:Cell(index)
		tag = ("|Haddon:EldoUIEmoji:%d|h|T%s:%d:%d:0:0:%d:%d:%d:%d:%d:%d|t|h"):format(index, path, size, size, dim, dim,
			left, right, top, bottom)
		tagCache[index] = tag
	end
	return tag
end

---------------------------------------------------------------------------
-- The rewrite of one line
---------------------------------------------------------------------------
-- Split a chat line into plain text and escape sequences. Color codes are
-- "color" (transparent for the smiley rule); links, textures, atlases and
-- protected names are "opaque"; |n is a line break ("space").
local function Segments(text)
	local list, pos, plain = {}, 1, {}
	local length = #text
	local function Flush()
		if #plain > 0 then
			list[#list + 1] = { "text", table.concat(plain) }
			wipe(plain)
		end
	end
	while pos <= length do
		local bar = text:find("|", pos, true)
		if not bar then
			plain[#plain + 1] = text:sub(pos)
			break
		end
		if bar > pos then plain[#plain + 1] = text:sub(pos, bar - 1) end
		local code = text:sub(bar + 1, bar + 1)
		local stop, kind
		if code == "|" then
			plain[#plain + 1] = "||"
			stop = bar + 1
		elseif code == "c" then
			kind = "colour"
			if text:sub(bar + 2, bar + 2) == "n" then
				stop = text:find(":", bar + 3, true) or length
			else
				stop = math.min(bar + 9, length)
			end
		elseif code == "r" then
			kind, stop = "colour", bar + 1
		elseif code == "n" then
			kind, stop = "space", bar + 1
		elseif code == "H" then
			local _, linkEnd = text:find("^|H.-|h.-|h", bar)
			kind, stop = "opaque", linkEnd or length
		elseif code == "T" or code == "A" or code == "K" then
			local _, close = text:find("|" .. code:lower(), bar + 2, true)
			kind, stop = "opaque", close or length
		elseif code == "" then
			plain[#plain + 1] = "|"
			stop = bar
		else
			plain[#plain + 1] = text:sub(bar, bar + 1)
			stop = bar + 1
		end
		if kind then
			Flush()
			list[#list + 1] = { kind, text:sub(bar, stop) }
		end
		pos = stop + 1
	end
	Flush()
	return list
end
Emoji.Segments = Segments

-- Is the edge next to segment i open (whitespace or the line edge)?
local function EdgeOpen(list, i, step)
	local j = i + step
	while list[j] do
		local kind, text = list[j][1], list[j][2]
		if kind == "text" then
			if step < 0 then return text:find("%s$") ~= nil end
			return text:find("^%s") ~= nil
		elseif kind == "space" then
			return true
		elseif kind == "opaque" then
			return false
		end
		j = j + step
	end
	return true
end

local function CharLength(byte)
	if byte < 0xC0 then return 1 end
	if byte < 0xE0 then return 2 end
	if byte < 0xF0 then return 3 end
	return 4
end

local KEYCAP = "\226\131\163"   -- U+20E3
local VS16 = "\239\184\143"     -- U+FE0F
local VS15 = "\239\184\142"     -- U+FE0E: the sender asked for text

-- Unicode emoji in a piece of plain text: greedy, longest sequence first.
local function ConvertUnicode(self, text, out)
	if not text:find("[\194-\244#%*0-9]") then
		out[#out + 1] = text
		return
	end
	local pos, length, start = 1, #text, 1
	while pos <= length do
		local byte = text:byte(pos)
		local candidate = byte >= 0xC2
		if not candidate and (byte == 35 or byte == 42 or (byte >= 48 and byte <= 57)) then
			local after = text:sub(pos + 1, pos + 3)
			candidate = after == VS16 or after == KEYCAP
		end
		local matched = false
		if candidate then
			local ends, at = {}, pos
			for n = 1, maxCodepoints do
				if at > length then break end
				local b = text:byte(at)
				if n > 1 and b < 0x80 then break end
				at = at + CharLength(b)
				ends[n] = at - 1
			end
			for n = #ends, 1, -1 do
				local index = byKey[text:sub(pos, ends[n])]
				if index and text:sub(ends[n] + 1, ends[n] + 3) ~= VS15 then
					if pos > start then out[#out + 1] = text:sub(start, pos - 1) end
					out[#out + 1] = self:Tag(index)
					pos = ends[n] + 1
					start = pos
					matched = true
					break
				end
			end
		end
		if not matched then pos = pos + CharLength(byte) end
	end
	if start <= length then out[#out + 1] = text:sub(start) end
end

-- Characters that may not stand right before or after a :shortcode:, so
-- times (12:30:45), item:123: and web addresses stay as they are.
local function CodeBlocked(char)
	return char ~= "" and char:find("[%w/%.:_%-=?&#%%]") ~= nil
end

-- Shortcodes, then Unicode emoji, in one whitespace-free word.
local function ConvertWord(self, word, out)
	if not word:find(":", 1, true) then
		ConvertUnicode(self, word, out)
		return
	end
	local pos, start, lastEnd = 1, 1, 0
	while true do
		local first, last, code = word:find(":([%w_+%-]+):", pos)
		if not first then break end
		local index = byCode[code:lower()]
		local before = word:sub(first - 1, first - 1)
		local after = word:sub(last + 1, last + 1)
		if index and (first - 1 == lastEnd or not CodeBlocked(before)) and not (after ~= "" and after:find("[%w/]")) then
			if first > start then ConvertUnicode(self, word:sub(start, first - 1), out) end
			out[#out + 1] = self:Tag(index)
			start, pos, lastEnd = last + 1, last + 1, last
		else
			pos = last -- the closing colon may open the next shortcode
		end
	end
	if start <= #word then ConvertUnicode(self, word:sub(start), out) end
end

-- The plain text of one segment: smileys (standalone words only), then
-- shortcodes and Unicode emoji.
local function ConvertText(self, text, leftOpen, rightOpen, withSmileys)
	local out, pos = {}, 1
	for first, word, stop in text:gmatch("()(%S+)()") do
		if first > pos then out[#out + 1] = text:sub(pos, first - 1) end
		local index = withSmileys and smileys[word]
		if index and (first > 1 or leftOpen) and (stop <= #text or rightOpen) then
			out[#out + 1] = self:Tag(index)
		else
			ConvertWord(self, word, out)
		end
		pos = stop
	end
	if pos <= #text then out[#out + 1] = text:sub(pos) end
	return table.concat(out)
end

-- The whole line. Plain text only; links, textures and color codes stay.
function Emoji:RenderLine(text, withSmileys)
	if type(text) ~= "string" or IsSecret(text) or not D then return text end
	if withSmileys == nil then withSmileys = M.db.emojiSmileys end
	local list = Segments(text)
	local out = {}
	for i, segment in ipairs(list) do
		if segment[1] == "text" then
			out[#out + 1] = ConvertText(self, segment[2], EdgeOpen(list, i, -1), EdgeOpen(list, i, 1), withSmileys)
		else
			out[#out + 1] = segment[2]
		end
	end
	return table.concat(out)
end

-- After the other line hooks (colors, sender details): those only add
-- color codes and links, which the rewrite steps over.
M:AddLineHook(90, function(text, r, g, b)
	if not Emoji:Active() or type(text) ~= "string" or IsSecret(text) then return nil end
	local rewritten = Emoji:RenderLine(text)
	if rewritten == text then return nil end
	return rewritten, r, g, b
end)

-- Lines that arrived before the data loaded (history, login messages).
function Emoji:RerenderFrames()
	if not self:Active() then return end
	for _, frame in M:IterateFrames() do
		if frame.TransformMessages then
			frame:TransformMessages(function(message)
				return type(message) == "string" and not IsSecret(message) and Emoji:RenderLine(message) ~= message
			end, function(message, ...)
				return Emoji:RenderLine(message), ...
			end)
		end
	end
end

---------------------------------------------------------------------------
-- Hover: name and shortcode
---------------------------------------------------------------------------
local hoverFrame
local function OnLinkEnter(frame, link)
	if not Emoji:Active() or type(link) ~= "string" or IsSecret(link) then return end
	local index = tonumber(link:match("^addon:EldoUIEmoji:(%d+)$"))
	local entry = index and D.list[index]
	if not entry then return end
	GameTooltip:SetOwner(frame, "ANCHOR_CURSOR")
	GameTooltip:SetText(entry[2], 1, 1, 1)
	local code = FirstCode(entry)
	if code then E.UIKit.TipText(GameTooltip, ":" .. code .. ":") end
	GameTooltip:Show()
	hoverFrame = frame
end

local function OnLinkLeave(frame)
	if hoverFrame and (frame == nil or frame == hoverFrame) then
		hoverFrame = nil
		GameTooltip:Hide()
	end
end
Emoji.OnLinkEnter, Emoji.OnLinkLeave = OnLinkEnter, OnLinkLeave

if EventRegistry and EventRegistry.RegisterCallback then
	EventRegistry:RegisterCallback("ChatFrame.OnHyperlinkEnter", function(_, frame, link) OnLinkEnter(frame, link) end, Emoji)
	EventRegistry:RegisterCallback("ChatFrame.OnHyperlinkLeave", function(_, frame) OnLinkLeave(frame) end, Emoji)
end

---------------------------------------------------------------------------
-- Putting emoji into the edit box
---------------------------------------------------------------------------
local attached = setmetatable({}, { __mode = "k" })   -- edit box -> { button }
local pendingInsert          -- text waiting for the next time a chat box opens
local pendingAt = 0
local PENDING_SECONDS = 60

-- What a picked emoji puts into the edit box.
function Emoji:InsertText(index)
	local entry = D and D.list[index]
	if not entry then return nil end
	if M.db.emojiSend == "unicode" then return entry[1] end
	local code = FirstCode(entry)
	return code and (":" .. code .. ":") or entry[1]
end

-- The chat edit box that is open now, or nil. Never opens one.
local function OpenBox(preferred)
	local active = ChatFrameUtil and ChatFrameUtil.GetActiveWindow and ChatFrameUtil.GetActiveWindow()
	if active then return active end
	if preferred and preferred:IsShown() and preferred:IsVisible() then return preferred end
	return nil
end

-- Lines that start with "/" are commands: nothing goes in (taint rule).
local function IsCommand(box)
	local text = box:GetText()
	return type(text) ~= "string" or IsSecret(text) or text:sub(1, 1) == "/"
end

local function AddRecent(text)
	local recent = Store().recent
	for i = #recent, 1, -1 do
		if recent[i] == text then table.remove(recent, i) end
	end
	table.insert(recent, 1, text)
	while #recent > RECENT_MAX do table.remove(recent) end
end

-- Put list[index] into the open edit box (or keep it for the next time the
-- chat opens). Returns "inserted", "pending" or "command".
function Emoji:Insert(index, preferred)
	local text = self:InsertText(index)
	if not text then return nil end
	AddRecent(D.list[index][1])
	local box = OpenBox(preferred)
	if box then
		if IsCommand(box) then return "command" end
		local before = box:GetText():sub(1, box:GetCursorPosition())
		if before ~= "" and not before:find("%s$") then text = " " .. text end
		box:Insert(text)
		pendingInsert = nil
		return "inserted"
	end
	pendingInsert, pendingAt = text, GetTime()
	return "pending"
end

function Emoji:ClearRecent()
	wipe(Store().recent)
	if self.picker and self.picker:IsShown() then self:RefreshPicker() end
end

function Emoji:Recent()
	local list = {}
	for _, text in ipairs(Store().recent) do
		local index = type(text) == "string" and byKey[text]
		if index then list[#list + 1] = index end
	end
	return list
end

---------------------------------------------------------------------------
-- Autocomplete
---------------------------------------------------------------------------
local SUGGEST_ROWS = 8
local suggest = { results = {} }

-- Base emoji whose shortcode starts with the query, then ones that
-- contain it.
function Emoji:Suggest(query, limit)
	limit = limit or SUGGEST_ROWS
	local results, seen = {}, {}
	if not D or not query or #query < 2 then return results end
	query = query:lower()
	for pass = 1, 2 do
		for _, code in ipairs(codeList) do
			if #results >= limit then return results end
			local index = byCode[code]
			local at = code:find(query, 1, true)
			if at and ((pass == 1 and at == 1) or (pass == 2 and at > 1)) and not seen[index] then
				seen[index] = true
				results[#results + 1] = { code = code, index = index }
			end
		end
	end
	return results
end

-- The :token right before the cursor, with its byte range, or nil.
function Emoji:TokenAt(text, cursor)
	if type(text) ~= "string" or IsSecret(text) or text:sub(1, 1) == "/" then return nil end
	local before = text:sub(1, cursor or #text)
	local first, query = before:match("():([%w_+%-]+)$")
	if not first then return nil end
	local prev = before:sub(first - 1, first - 1)
	if prev ~= "" and not prev:find("%s") then return nil end
	if #query < 2 then return nil end
	return first, #before, query
end

local function SuggestRow(popup, i)
	local row = CreateFrame("Button", nil, popup)
	row:SetHeight(20)
	row:SetPoint("TOPLEFT", 4, -4 - (i - 1) * 20)
	row:SetPoint("TOPRIGHT", -4, -4 - (i - 1) * 20)
	row.highlight = row:CreateTexture(nil, "BACKGROUND")
	row.highlight:SetAllPoints()
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(16, 16)
	row.icon:SetPoint("LEFT", 4, 0)
	row.code = E:CreateText(row, E.tokens.size.label, "LEFT")
	row.code:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
	row.name = E:CreateText(row, E.tokens.size.small, "RIGHT")
	row.name:SetPoint("RIGHT", -4, 0)
	row.name:SetPoint("LEFT", row.code, "RIGHT", 8, 0)
	row.name:SetTextColor(unpack(E.media.text.secondary))
	row:SetScript("OnEnter", function(self)
		suggest.selected = self.slot
		Emoji:PaintSuggestions()
	end)
	row:SetScript("OnClick", function(self) Emoji:AcceptSuggestion(suggest.box, self.slot) end)
	return row
end

function Emoji:PaintSuggestions()
	local popup = self.suggestPopup
	if not popup then return end
	local accent = E.media.accentColor
	for i, row in ipairs(popup.rows) do
		local item = suggest.results[i]
		row:SetShown(item ~= nil)
		if item then
			row.slot = i
			local index = self:WithTone(item.index)
			self:SetIcon(row.icon, index)
			row.code:SetText(":" .. item.code .. ":")
			row.name:SetText(D.list[item.index][2])
			if i == suggest.selected then
				row.highlight:SetColorTexture(accent[1], accent[2], accent[3], 0.25)
			else
				row.highlight:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.03 or 0)
			end
		end
	end
	popup:SetHeight(8 + #suggest.results * 20)
end

function Emoji:HideSuggestions()
	suggest.box, suggest.results, suggest.selected = nil, {}, nil
	if self.suggestPopup then self.suggestPopup:Hide() end
end

function Emoji:ShowSuggestions(box, first, last, results)
	local popup = self.suggestPopup
	if not popup then
		popup = CreateFrame("Frame", "EldoUI_EmojiSuggest", UIParent)
		popup:SetFrameStrata("TOOLTIP")
		popup:SetClampedToScreen(true)
		popup:SetWidth(280)
		E:SetPanelTemplate(popup)
		popup.rows = {}
		for i = 1, SUGGEST_ROWS do popup.rows[i] = SuggestRow(popup, i) end
		popup.hint = E:CreateText(popup, E.tokens.size.tiny, "RIGHT")
		popup.hint:SetPoint("BOTTOMRIGHT", popup, "TOPRIGHT", -2, 2)
		popup.hint:SetTextColor(unpack(E.media.text.secondary))
		popup.hint:SetText(L["Tab or click puts it in"])
		self.suggestPopup = popup
	end
	suggest.box, suggest.first, suggest.last, suggest.results = box, first, last, results
	suggest.selected = 1
	popup:ClearAllPoints()
	local _, centre = box:GetCenter()
	if centre and centre > (UIParent:GetHeight() or 768) / 2 then
		popup:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 0, -2)
	else
		popup:SetPoint("BOTTOMLEFT", box, "TOPLEFT", 0, 16)
	end
	self:PaintSuggestions()
	popup:Show()
end

function Emoji:OnEditText(box)
	if not (self:Active() and M.db.emojiAutocomplete) then
		if suggest.box then self:HideSuggestions() end
		return
	end
	local text = box:GetText()
	local first, last, query = self:TokenAt(text, box:GetCursorPosition())
	local results = first and self:Suggest(query) or nil
	if results and #results > 0 then
		self:ShowSuggestions(box, first, last, results)
	elseif suggest.box then
		self:HideSuggestions()
	end
end

-- Replace the :token with the chosen shortcode. Returns true when done.
function Emoji:AcceptSuggestion(box, slot)
	if not box or box ~= suggest.box then return false end
	local item = suggest.results[slot or suggest.selected or 1]
	if not item then return false end
	local text = box:GetText()
	if IsCommand(box) or #text < suggest.last then
		self:HideSuggestions()
		return false
	end
	local index = self:WithTone(item.index)
	local insert = self:InsertText(index) .. " "
	local first, last = suggest.first, suggest.last
	self:HideSuggestions()
	AddRecent(D.list[index][1])
	box:SetText(text:sub(1, first - 1) .. insert .. text:sub(last + 1))
	box:SetCursorPosition(first - 1 + #insert)
	return true
end

-- Tab: Blizzard calls this global through securecall before its own Tab
-- handling ("left intentionally global ... to enable secure tab completion
-- hooks in addons"). Nothing to complete: the previous handler and then
-- the game's own Tab run as before.
function Emoji:TabHandler(previous)
	return function(box, ...)
		if suggest.box and box == suggest.box and Emoji:AcceptSuggestion(box) then return true end
		if previous then return previous(box, ...) end
		return false
	end
end

local previousTab = rawget(_G, "ChatEdit_CustomTabPressed")
if type(previousTab) == "function" then
	-- luacheck: globals ChatEdit_CustomTabPressed
	ChatEdit_CustomTabPressed = Emoji:TabHandler(previousTab)
end

---------------------------------------------------------------------------
-- Picker
---------------------------------------------------------------------------
local COLS, ROWS, CELL = 9, 6, 30
local PAD = 8

local function CellButton(parent)
	local button = CreateFrame("Button", nil, parent)
	button:SetSize(CELL, CELL)
	button.hover = button:CreateTexture(nil, "BACKGROUND")
	button.hover:SetAllPoints()
	button.hover:Hide()
	button.icon = button:CreateTexture(nil, "ARTWORK")
	button.icon:SetSize(CELL - 6, CELL - 6)
	button.icon:SetPoint("CENTER")
	button:SetScript("OnEnter", function(self)
		local accent = E.media.accentColor
		self.hover:SetColorTexture(accent[1], accent[2], accent[3], 0.25)
		self.hover:Show()
		Emoji:ShowInfo(self.index)
	end)
	button:SetScript("OnLeave", function(self)
		self.hover:Hide()
		Emoji:ShowInfo(nil)
	end)
	button:SetScript("OnClick", function(self) Emoji:Pick(self.index) end)
	return button
end

function Emoji:ShowInfo(index)
	local picker = self.picker
	if not picker then return end
	local entry = index and D and D.list[index]
	if entry then
		local code = FirstCode(entry)
		picker.info:SetText(entry[2] .. (code and ("  " .. E:TextHex("secondary") .. ":" .. code .. ":|r") or ""))
	else
		picker.info:SetText(picker.message or "")
	end
end

function Emoji:Pick(index)
	if not index then return end
	local result = self:Insert(index, self.pickerBox)
	local picker = self.picker
	if picker then
		if result == "command" then
			picker.message = L["Emoji don't go into slash commands."]
		elseif result == "pending" then
			picker.message = L["Open the chat (Enter): the emoji goes in there."]
		else
			picker.message = nil
		end
		if picker.search:HasFocus() then picker.search:ClearFocus() end
		self:RefreshPicker()
		self:ShowInfo(nil)
	end
end

-- The emoji the grid shows now: search results or one category.
function Emoji:PickerItems()
	local picker = self.picker
	local query = picker and strtrim(picker.search:GetText() or ""):lower() or ""
	if query == "" then return groupLists[picker and picker.group or 1] or {} end
	local words = {}
	for word in query:gmatch("%S+") do words[#words + 1] = word end
	local results = {}
	for _, list in ipairs(groupLists) do
		for _, index in ipairs(list) do
			local entry = D.list[index]
			local hay = entry[2]:lower() .. " " .. (entry[3] or "") .. " " .. (entry[7] or "")
			local ok = true
			for _, word in ipairs(words) do
				if not hay:find(word, 1, true) then ok = false break end
			end
			if ok then results[#results + 1] = index end
		end
	end
	return results
end

function Emoji:RefreshPicker()
	local picker = self.picker
	if not (picker and D) then return end
	local accent = E.media.accentColor
	-- Category tabs
	local searching = strtrim(picker.search:GetText() or "") ~= ""
	for g, tab in ipairs(picker.tabs) do
		local active = not searching and g == picker.group
		tab.underline:SetShown(active)
		tab.icon:SetAlpha(active and 1 or 0.6)
	end
	-- Skin tones
	local tone = TONE_INDEX[M.db.emojiTone] or 0
	for t, button in ipairs(picker.toneButtons) do
		button:SetBackdropBorderColor(unpack(t - 1 == tone and accent or E.media.borderColor))
	end
	-- Recent row
	local recent = self:Recent()
	for i, button in ipairs(picker.recent) do
		button.index = recent[i]
		button:SetShown(recent[i] ~= nil)
		if recent[i] then self:SetIcon(button.icon, recent[i]) end
	end
	picker.recentEmpty:SetShown(#recent == 0)
	-- Grid
	local items = self:PickerItems()
	local rows = math.ceil(#items / COLS)
	picker.offset = math.max(0, math.min(picker.offset or 0, rows - ROWS))
	for i, button in ipairs(picker.cells) do
		local index = items[picker.offset * COLS + i]
		if index then index = self:WithTone(index, tone) end
		button.index = index
		button:SetShown(index ~= nil)
		if index then self:SetIcon(button.icon, index) end
	end
	picker.empty:SetShown(#items == 0)
	picker.heading:SetText(searching and L["%d found"]:format(#items) or (D.groups[picker.group] and D.groups[picker.group].name or ""))
	-- Scroll thumb
	if rows > ROWS then
		local track = picker.track:GetHeight()
		local size = math.max(12, track * ROWS / rows)
		picker.thumb:SetHeight(size)
		picker.thumb:SetPoint("TOP", picker.track, "TOP", 0, -(track - size) * picker.offset / (rows - ROWS))
		picker.thumb:Show()
	else
		picker.thumb:Hide()
	end
	self:ShowInfo(nil)
end

function Emoji:CreatePicker()
	local width = PAD * 2 + COLS * CELL + 8
	local picker = CreateFrame("Frame", "EldoUI_EmojiPicker", UIParent)
	picker:SetSize(width, 0)
	picker:SetFrameStrata("DIALOG")
	picker:SetToplevel(true)
	picker:SetClampedToScreen(true)
	picker:EnableMouse(true)
	E:SetPanelTemplate(picker)
	tinsert(UISpecialFrames, "EldoUI_EmojiPicker")
	picker:Hide()
	picker.group, picker.offset = 1, 0

	-- Search and skin tones
	local toneSize = 18
	local search = M.FlatInput(picker, width - PAD * 2 - (toneSize + 2) * #TONES - 4)
	search:SetPoint("TOPLEFT", PAD, -PAD)
	search.hint:SetText(L["Search emoji"])
	search:HookScript("OnTextChanged", function()
		picker.offset = 0
		Emoji:RefreshPicker()
	end)
	search:SetScript("OnEnterPressed", function(field)
		local first = picker.cells[1] and picker.cells[1]:IsShown() and picker.cells[1].index
		field:ClearFocus()
		if first then Emoji:Pick(first) end
	end)
	picker.search = search
	picker.toneButtons = {}
	local anchor
	for t = #TONES, 1, -1 do
		local button = CreateFrame("Button", nil, picker)
		button:SetSize(toneSize, toneSize)
		E:SetTemplate(button)
		button.icon = button:CreateTexture(nil, "ARTWORK")
		button.icon:SetPoint("TOPLEFT", 2, -2)
		button.icon:SetPoint("BOTTOMRIGHT", -2, 2)
		if anchor then button:SetPoint("RIGHT", anchor, "LEFT", -2, 0) else button:SetPoint("TOPRIGHT", -PAD, -PAD - 1) end
		anchor = button
		button.tone = t - 1
		button:SetScript("OnClick", function(chosen)
			M.db.emojiTone = TONES[chosen.tone + 1]
			Emoji:RefreshPicker()
		end)
		M.Tip(button, L["Skin tone"], t == 1 and L["No skin tone (yellow). Also the default in Chat options."] or L["Emoji that come in skin tones use this one."])
		picker.toneButtons[t] = button
	end

	-- Category tabs
	local top = -PAD - 24
	picker.tabs = {}
	local tabWidth = math.floor((width - PAD * 2) / #D.groups)
	for g, group in ipairs(D.groups) do
		local tab = CreateFrame("Button", nil, picker)
		tab:SetSize(tabWidth, 24)
		tab:SetPoint("TOPLEFT", PAD + (g - 1) * tabWidth, top)
		tab.icon = tab:CreateTexture(nil, "ARTWORK")
		tab.icon:SetSize(18, 18)
		tab.icon:SetPoint("CENTER", 0, 1)
		self:SetIcon(tab.icon, group.icon)
		tab.underline = tab:CreateTexture(nil, "OVERLAY")
		tab.underline:SetPoint("BOTTOMLEFT", 3, 0)
		tab.underline:SetPoint("BOTTOMRIGHT", -3, 0)
		tab.underline:SetHeight(2)
		E:AccentTexture(tab.underline)
		tab:SetScript("OnClick", function()
			picker.group, picker.offset = g, 0
			if picker.search:GetText() ~= "" then picker.search:SetText("") end
			Emoji:RefreshPicker()
		end)
		M.Tip(tab, group.name)
		picker.tabs[g] = tab
	end
	top = top - 28

	-- Recent row
	local recentLabel = E:CreateText(picker, E.tokens.size.small, "LEFT")
	recentLabel:SetPoint("TOPLEFT", PAD, top)
	recentLabel:SetTextColor(unpack(E.media.text.secondary))
	recentLabel:SetText(L["Recent"])
	top = top - 14
	picker.recent = {}
	for i = 1, COLS do
		local button = CellButton(picker)
		button:SetPoint("TOPLEFT", PAD + (i - 1) * CELL, top)
		picker.recent[i] = button
	end
	picker.recentEmpty = E:CreateText(picker, E.tokens.size.small, "LEFT")
	picker.recentEmpty:SetPoint("TOPLEFT", PAD + 4, top - 9)
	picker.recentEmpty:SetTextColor(unpack(E.media.text.dim))
	picker.recentEmpty:SetText(L["Emoji you pick show up here."])
	top = top - CELL - 4

	-- Grid
	picker.heading = E:CreateText(picker, E.tokens.size.small, "LEFT")
	picker.heading:SetPoint("TOPLEFT", PAD, top)
	picker.heading:SetTextColor(unpack(E.media.text.secondary))
	top = top - 14
	local grid = CreateFrame("Frame", nil, picker)
	grid:SetPoint("TOPLEFT", PAD, top)
	grid:SetSize(COLS * CELL + 8, ROWS * CELL)
	grid:EnableMouseWheel(true)
	grid:SetScript("OnMouseWheel", function(_, delta)
		picker.offset = math.max(0, (picker.offset or 0) - delta)
		Emoji:RefreshPicker()
	end)
	picker.cells = {}
	for i = 1, COLS * ROWS do
		local button = CellButton(grid)
		button:SetPoint("TOPLEFT", ((i - 1) % COLS) * CELL, -math.floor((i - 1) / COLS) * CELL)
		picker.cells[i] = button
	end
	picker.track = grid:CreateTexture(nil, "BACKGROUND")
	picker.track:SetPoint("TOPRIGHT", 0, 0)
	picker.track:SetPoint("BOTTOMRIGHT", 0, 0)
	picker.track:SetWidth(3)
	picker.track:SetColorTexture(unpack(E.tokens.track))
	picker.thumb = grid:CreateTexture(nil, "ARTWORK")
	picker.thumb:SetWidth(3)
	E:AccentTexture(picker.thumb)
	picker.empty = E:CreateText(grid, E.tokens.size.small, "CENTER")
	picker.empty:SetPoint("CENTER")
	picker.empty:SetTextColor(unpack(E.media.text.dim))
	picker.empty:SetText(L["No emoji found."])
	top = top - ROWS * CELL - 4

	-- Name of the emoji under the mouse, or a short message.
	picker.info = E:CreateText(picker, E.tokens.size.small, "LEFT")
	picker.info:SetPoint("TOPLEFT", PAD, top)
	picker.info:SetPoint("TOPRIGHT", -PAD, top)
	top = top - 16
	picker:SetHeight(-top + PAD - 4)

	-- Tone button pictures: the waving hand in each tone.
	local wave = byKey["\240\159\145\139"] -- U+1F44B
	for t, button in ipairs(picker.toneButtons) do
		if wave then self:SetIcon(button.icon, self:WithTone(wave, t - 1)) end
	end
	picker:SetScript("OnHide", function(frame)
		frame.message = nil
		if frame.search:HasFocus() then frame.search:ClearFocus() end
	end)
	self.picker = picker
	return picker
end

-- Open the picker next to an edit box (or close it again).
function Emoji:TogglePicker(box)
	if not self:Active() then return end
	local picker = self.picker or self:CreatePicker()
	if picker:IsShown() and self.pickerBox == box then
		picker:Hide()
		return
	end
	self.pickerBox = box
	picker:ClearAllPoints()
	local _, centre = box:GetCenter()
	if centre and centre > (UIParent:GetHeight() or 768) / 2 then
		picker:SetPoint("TOPRIGHT", box, "BOTTOMRIGHT", 0, -2)
	else
		picker:SetPoint("BOTTOMRIGHT", box, "TOPRIGHT", 0, 2)
	end
	picker:Show()
	self:RefreshPicker()
end

---------------------------------------------------------------------------
-- Edit box: smiley button, insets, autocomplete hooks
---------------------------------------------------------------------------
local BUTTON = 18
local RIGHT_INSET = 13 -- Blizzard's own right inset (ChatFrameEditBox UpdateHeader)

local function FixInsets(box)
	local info = attached[box]
	if not info or not box.GetTextInsets then return end
	local left, _, top, bottom = box:GetTextInsets()
	local right = RIGHT_INSET + (info.button:IsShown() and BUTTON + 4 or 0)
	box:SetTextInsets(left or 0, right, top or 0, bottom or 0)
end

function Emoji:AttachEditBox(box)
	if not box or attached[box] then
		if box then self:UpdateEditBox(box) end
		return
	end
	local button = CreateFrame("Button", nil, box)
	button:SetSize(BUTTON, BUTTON)
	button:SetPoint("RIGHT", -6, 0)
	button:SetFrameLevel(box:GetFrameLevel() + 5)
	button.icon = button:CreateTexture(nil, "ARTWORK")
	button.icon:SetAllPoints()
	button.icon:SetAlpha(0.75)
	button:SetScript("OnEnter", function(smiley)
		smiley.icon:SetAlpha(1)
		GameTooltip:SetOwner(smiley, "ANCHOR_TOP")
		GameTooltip:SetText(L["Emoji"], 1, 1, 1)
		E.UIKit.TipText(GameTooltip, L["Pick an emoji to put into this line. Typing :sm also lists matches (Tab puts one in)."])
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function(smiley)
		smiley.icon:SetAlpha(0.75)
		GameTooltip:Hide()
	end)
	button:SetScript("OnClick", function(smiley, mouse)
		if E:IsOptionsLinkClick(smiley, mouse) then return end
		Emoji:TogglePicker(box)
	end)
	E:BindOptionsLink(button, { page = "module:Chat", key = "emoji" })
	button:Hide()
	attached[box] = { button = button }

	box:HookScript("OnTextChanged", function(edit) Emoji:OnEditText(edit) end)
	box:HookScript("OnEditFocusLost", function(edit)
		if suggest.box == edit then Emoji:HideSuggestions() end
	end)
	box:HookScript("OnHide", function(edit)
		if suggest.box == edit then Emoji:HideSuggestions() end
		-- The line was sent or the chat closed: the picker goes too (not
		-- when its own search field took the focus).
		local picker = Emoji.picker
		if picker and picker:IsShown() and Emoji.pickerBox == edit and not picker.search:HasFocus() then picker:Hide() end
	end)
	-- An emoji picked while no chat box was open goes in when one opens.
	box:HookScript("OnEditFocusGained", function(edit)
		if pendingInsert and GetTime() - pendingAt > PENDING_SECONDS then pendingInsert = nil end
		if pendingInsert and Emoji:Active() and not IsCommand(edit) then
			local text = pendingInsert
			pendingInsert = nil
			edit:Insert(text)
		end
	end)
	if box.UpdateHeader then hooksecurefunc(box, "UpdateHeader", FixInsets) end
	self:UpdateEditBox(box)
end

function Emoji:UpdateEditBox(box)
	local info = attached[box]
	if not info then return end
	local show = self:Active()
	info.button:SetShown(show)
	if show then
		self:SetIcon(info.button.icon, byKey["\240\159\153\130"]) -- U+1F642
	end
	FixInsets(box)
end

---------------------------------------------------------------------------
-- Wiring: Core.lua's Apply, restore and edit box styling
---------------------------------------------------------------------------
function Emoji:OnDataLoaded()
	wipe(tagCache)
	for box in pairs(attached) do self:UpdateEditBox(box) end
	self:RerenderFrames()
	if M.RefreshPreview then M:RefreshPreview() end
end

function Emoji:Refresh()
	if self:Wanted() then self:Load() end
	wipe(tagCache)
	tagSize = nil
	for box in pairs(attached) do self:UpdateEditBox(box) end
	if not self:Active() then
		if self.picker then self.picker:Hide() end
		self:HideSuggestions()
		OnLinkLeave(nil)
	elseif self.picker and self.picker:IsShown() then
		self:RefreshPicker()
	end
end

hooksecurefunc(M, "StyleEditBox", function(_, box) Emoji:AttachEditBox(box) end)
hooksecurefunc(M, "Apply", function() Emoji:Refresh() end)
hooksecurefunc(M, "RestoreBlizzard", function() Emoji:Refresh() end)
hooksecurefunc(M, "DisableMessages", function()
	if Emoji.picker then Emoji.picker:Hide() end
	Emoji:HideSuggestions()
	for box, info in pairs(attached) do
		info.button:Hide()
		FixInsets(box)
	end
end)

---------------------------------------------------------------------------
-- Options: Chat -> Emoji (before the Errors tab)
---------------------------------------------------------------------------
local function NoEmoji() return not M.db.emoji end

local function DrawSample(canvas)
	if not canvas then return end
	if not canvas.sample then
		canvas.sample = E:CreateText(canvas, E.tokens.size.body, "LEFT")
		canvas.sample:SetPoint("TOPLEFT", 6, -6)
		canvas.sample:SetPoint("TOPRIGHT", -6, -6)
		canvas.status = E:CreateText(canvas, E.tokens.size.small, "LEFT")
		canvas.status:SetPoint("BOTTOMLEFT", 6, 6)
		canvas.status:SetPoint("BOTTOMRIGHT", -6, 6)
		canvas.status:SetWordWrap(true)
		canvas.status:SetTextColor(unpack(E.media.text.secondary))
	end
	if M.db.emoji and M:Allowed("improve") and not D then Emoji:Load() end
	local sample = L["[Friend]: gg :) that was fun :tada: see you at 12:30 <3"]
	if D and M.db.emoji then
		sample = Emoji:RenderLine(sample)
	end
	canvas.sample:SetText(sample)
	canvas.status:SetText(Emoji:StatusText())
end

local OPTIONS = {
	{ type = "tab", label = "Emoji" },
	{ type = "preview", label = "Preview", height = 56, desc = "A sample line with your emoji settings, and whether the emoji folder is ready.",
		create = DrawSample, update = DrawSample },
	{ type = "description", label = "Emoji and :shortcodes: such as :smile: show as pictures in chat. Needs the Blizzard UI switch Improve. Emoji graphics: Twemoji, CC-BY 4.0." },
	{ type = "toggle", key = "emoji", label = "Show emoji",
		desc = "Emoji characters and :shortcodes: in chat lines show as pictures, and the edit box gets a smiley button for the picker. Hover an emoji in chat for its name and shortcode." },
	{ type = "range", key = "emojiSize", label = "Emoji size", min = 0, max = 32, step = 1, dependsOn = "emoji",
		zeroText = "Auto", desc = "Size of the emoji in chat lines, in pixels. Auto follows the chat font size." },
	{ type = "toggle", key = "emojiSmileys", label = "Turn text smileys into emoji", dependsOn = "emoji",
		desc = ":) :D ;) :( :P <3 and other text smileys show as emoji when they stand alone, so addresses and times like 12:30 stay as they are. What you send is not changed." },
	{ type = "toggle", key = "emojiAutocomplete", label = "Autocomplete", dependsOn = "emoji",
		desc = "Type a colon and two letters (such as :sm) to list matching emoji; Tab or a click puts one in. Without a colon, Tab works as before." },
	{ type = "select", key = "emojiSend", label = "Send emoji as", dependsOn = "emoji",
		values = { shortcode = "Shortcode", unicode = "Unicode character" },
		desc = "What the picker puts into your line. Shortcode (:smile:) reads fine for everyone and is a picture for EldoUI users. Unicode sends the character; others may see boxes." },
	{ type = "select", key = "emojiTone", label = "Default skin tone", dependsOn = "emoji",
		values = { none = "None (yellow)", light = "Light", ["medium-light"] = "Medium-light", medium = "Medium",
			["medium-dark"] = "Medium-dark", dark = "Dark" },
		desc = "Skin tone of hands and people in the picker and autocomplete. The picker's tone buttons change it too. Emoji other players send keep their own tone." },
	{ type = "execute", label = "Clear recent emoji", confirm = true, hidden = NoEmoji,
		desc = "Empties the Recent row of the picker for this character.",
		func = function() Emoji:ClearRecent() end },
}

do
	local at = #M.options + 1
	for index, option in ipairs(M.options) do
		if option.type == "tab" and option.label == "Errors and help" then at = index break end
	end
	for offset, option in ipairs(OPTIONS) do table.insert(M.options, at + offset - 1, option) end
end
