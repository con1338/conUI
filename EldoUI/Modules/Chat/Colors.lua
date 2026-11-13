-- EldoUI Chat, part 4: chat colors per type and per channel, the
-- Quiet text mode, and the live preview on the Messages tab.
--
-- Colors go through the game's own ChangeChatColor (never ChatTypeInfo
-- itself). The player's color of every slot EldoUI changes is kept per
-- character (EldoUIMessagesDB.colorOriginals) and put back on "Game
-- colors", when the module or the Improve switch goes off, and when a
-- channel moves to another number. A color the player changes in the
-- game's own color picker while EldoUI's color is on is taken over, not
-- fought. Numbered channels are keyed by the zone channel ID (General,
-- Trade, LFG ...) or by name (custom channels), so a color follows its
-- channel when its number changes.
-- Written from scratch for EldoUI.
local _, E = ...
local L = E.L

local M = E:GetModule("Chat")

local IsSecret = function(value) return issecretvalue and issecretvalue(value) or false end

local function Improve()
	return M.active and M:Allowed("improve")
end

-- The chat types with a color of their own, in the order of the editor.
M.COLOR_TYPES = {
	{ "SAY", "Say" }, { "YELL", E.Key("Yell") }, { "EMOTE", "Emote" },
	{ "WHISPER", "Whisper" }, { "BN_WHISPER", "Battle.net whisper" },
	{ "GUILD", "Guild" }, { "OFFICER", "Officer" },
	{ "PARTY", "Party" }, { "PARTY_LEADER", "Party leader" },
	{ "RAID", "Raid" }, { "RAID_LEADER", "Raid leader" }, { "RAID_WARNING", "Raid warning" },
	{ "INSTANCE_CHAT", "Instance" }, { "INSTANCE_CHAT_LEADER", "Instance leader" },
}

local function Store()
	local store = E:GetMessagesDB()
	if type(store.colorOriginals) ~= "table" then store.colorOriginals = {} end
	return store.colorOriginals
end

local function Info(slot)
	local all = rawget(_G, "ChatTypeInfo")
	local info = type(all) == "table" and all[slot]
	if type(info) ~= "table" then return nil end
	return info
end

local function Same(a, r, g, b)
	return a and math.abs((a[1] or 0) - r) < 0.005 and math.abs((a[2] or 0) - g) < 0.005 and math.abs((a[3] or 0) - b) < 0.005
end

---------------------------------------------------------------------------
-- Joined numbered channels: { index, name, key }
---------------------------------------------------------------------------
local function ChannelKey(name)
	if type(name) ~= "string" or IsSecret(name) or name == "" then return nil end
	local info = C_ChatInfo and C_ChatInfo.GetChannelInfoFromIdentifier and C_ChatInfo.GetChannelInfoFromIdentifier(name)
	local zone = info and info.zoneChannelID
	if type(zone) == "number" and not IsSecret(zone) and zone > 0 then return "zone:" .. zone end
	return "name:" .. name:lower()
end
M.ChannelKey = ChannelKey

function M:JoinedChannels()
	local list = {}
	if not GetChannelList then return list end
	local values = { GetChannelList() }
	for index = 1, #values, 3 do
		local id, name = values[index], values[index + 1]
		if type(id) == "number" and not IsSecret(id) and type(name) == "string" and not IsSecret(name) then
			local key = ChannelKey(name)
			if key then list[#list + 1] = { index = id, name = name, key = key } end
		end
	end
	table.sort(list, function(a, b) return a.index < b.index end)
	return list
end

-- Short name for a channel key, for the editor ("Trade").
local function ChannelLabel(name)
	return (name:gsub("%s+%-%s+.*$", ""))
end

---------------------------------------------------------------------------
-- Apply and restore
---------------------------------------------------------------------------
local expected = {}  -- slot -> { r, g, b } EldoUI just asked the game for
local LINKED = { WHISPER = "WHISPER_INFORM", BN_WHISPER = "BN_WHISPER_INFORM" }

local function SetSlot(slot, r, g, b)
	if not ChangeChatColor then return end
	expected[slot] = { r, g, b }
	ChangeChatColor(slot, r, g, b)
end

-- The color every slot should have now: slot -> { r, g, b }.
function M:WantedColors()
	local want = {}
	local db = self.db
	if not (Improve() and db.colorMode ~= "game") then return want end
	for _, entry in ipairs(M.COLOR_TYPES) do
		local color = db.colors[entry[1]]
		if type(color) == "table" then
			want[entry[1]] = color
			-- Sent whispers share the whisper color.
			if LINKED[entry[1]] then want[LINKED[entry[1]]] = color end
		end
	end
	for _, channel in ipairs(self:JoinedChannels()) do
		local color = db.colors[channel.key]
		if type(color) == "table" then want["CHANNEL" .. channel.index] = color end
	end
	return want
end

function M:ApplyChatColors()
	if not self.db then return end
	local want = self:WantedColors()
	local originals = Store()
	-- Slots EldoUI no longer colors get the player's own color back.
	for slot, original in pairs(originals) do
		if not want[slot] then
			if type(original) == "table" then SetSlot(slot, original[1], original[2], original[3]) end
			originals[slot] = nil
		end
	end
	for slot, color in pairs(want) do
		local info = Info(slot)
		if info then
			if not originals[slot] then originals[slot] = { info.r or 1, info.g or 1, info.b or 1 } end
			if not Same(color, info.r or 1, info.g or 1, info.b or 1) then SetSlot(slot, color[1], color[2], color[3]) end
		end
	end
end

-- Everything back to the player's colors (module off, Improve off).
function M:RestoreChatColors()
	local originals = Store()
	for slot, original in pairs(originals) do
		if type(original) == "table" then SetSlot(slot, original[1], original[2], original[3]) end
		originals[slot] = nil
	end
end

-- The game reports every color change. EldoUI's own are expected; any
-- other change to a slot EldoUI colors is the player's (or another
-- addon's) choice: it becomes EldoUI's color for that slot.
function M:OnChatColor(slot, r, g, b)
	if type(slot) ~= "string" or IsSecret(slot) or type(r) ~= "number" then return end
	local wanted = expected[slot]
	if wanted and Same(wanted, r, g, b) then
		expected[slot] = nil
		return
	end
	local originals = Store()
	if not originals[slot] then return end
	local key = slot
	for own, linked in pairs(LINKED) do
		if linked == slot then key = own end
	end
	local index = slot:match("^CHANNEL(%d+)$")
	if index then
		key = nil
		for _, channel in ipairs(self:JoinedChannels()) do
			if channel.index == tonumber(index) then key = channel.key end
		end
	end
	if key and type(self.db.colors[key]) == "table" then
		self.db.colors[key] = { r, g, b }
		if self.RefreshListEditor then self:RefreshListEditor("colors") end
	end
end

---------------------------------------------------------------------------
-- Quiet text: the channel tag and sender keep the channel color, the
-- message is a calm neutral gray, the game's timestamp a darker gray.
---------------------------------------------------------------------------
local QUIET_TEXT = { 0.85, 0.85, 0.85 }
local QUIET_TIME = "ff7a7a80"
local QUIET_EVENTS = {
	CHAT_MSG_SAY = true, CHAT_MSG_YELL = true, CHAT_MSG_CHANNEL = true, CHAT_MSG_GUILD = true, CHAT_MSG_OFFICER = true,
	CHAT_MSG_PARTY = true, CHAT_MSG_PARTY_LEADER = true, CHAT_MSG_RAID = true, CHAT_MSG_RAID_LEADER = true,
	CHAT_MSG_RAID_WARNING = true, CHAT_MSG_INSTANCE_CHAT = true, CHAT_MSG_INSTANCE_CHAT_LEADER = true,
	CHAT_MSG_WHISPER = true, CHAT_MSG_WHISPER_INFORM = true, CHAT_MSG_BN_WHISPER = true, CHAT_MSG_BN_WHISPER_INFORM = true,
	CHAT_MSG_COMMUNITIES_CHANNEL = true,
}
M.QUIET_EVENTS = QUIET_EVENTS

local function Hex(r, g, b)
	return ("ff%02x%02x%02x"):format(math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

-- Color a piece of text, also after any color end inside it (a class-
-- colored name ends its own color).
local function Paint(text, hex)
	return "|c" .. hex .. text:gsub("|r", "|r|c" .. hex) .. "|r"
end

function M:QuietLine(text, r, g, b)
	local starts = {}
	for _, marker in ipairs({ "|Hchannel:", "|Hplayer:", "|HBNplayer:" }) do
		local at = text:find(marker, 1, true)
		if at then starts[#starts + 1] = at end
	end
	if #starts == 0 then return nil end
	table.sort(starts)
	local head = starts[1]
	local _, sender = text:find("|H[BN]*player:.-|h.-|h", head)
	if not sender then return nil end
	-- The header ends with the first ": " after the sender ("says: ", "whispers: ").
	local colon = text:find(": ", sender + 1, true)
	local headEnd = (colon and colon - sender <= 40) and colon + 1 or sender
	local prefix, header, body = text:sub(1, head - 1), text:sub(head, headEnd), text:sub(headEnd + 1)
	if prefix ~= "" and self.db.quietTimestamps and not prefix:find("|c", 1, true) then prefix = Paint(prefix, QUIET_TIME) end
	return prefix .. Paint(header, Hex(r, g, b)) .. body, QUIET_TEXT[1], QUIET_TEXT[2], QUIET_TEXT[3]
end

M:AddLineHook(80, function(text, r, g, b, event)
	if M.db.colorMode ~= "quiet" or not (event and QUIET_EVENTS[event]) then return nil end
	if type(r) ~= "number" or IsSecret(r) then return nil end
	return M:QuietLine(text, r, g, b)
end)

---------------------------------------------------------------------------
-- Color editor: one row per chat type and joined channel
---------------------------------------------------------------------------
local function EditorItems()
	local items = {}
	for _, entry in ipairs(M.COLOR_TYPES) do items[#items + 1] = { key = entry[1], slot = entry[1], label = L[entry[2]] } end
	for _, channel in ipairs(M:JoinedChannels()) do
		items[#items + 1] = { key = channel.key, slot = "CHANNEL" .. channel.index,
			label = ("%d. %s"):format(channel.index, ChannelLabel(channel.name)) }
	end
	return items
end

-- What the row shows: EldoUI's color, or the game's own.
local function RowColor(item)
	local own = M.db.colors[item.key]
	if type(own) == "table" then return own[1], own[2], own[3] end
	local original = Store()[item.slot]
	if type(original) == "table" then return original[1], original[2], original[3] end
	local info = Info(item.slot)
	if info then return info.r, info.g, info.b end
	return 1, 1, 1
end

local function Changed()
	M:ApplyChatColors()
	if M.RefreshPreview then M:RefreshPreview() end
end

local function PickColor(item)
	local r, g, b = RowColor(item)
	local previous = M.db.colors[item.key]
	local function Set(nr, ng, nb)
		M.db.colors[item.key] = { nr, ng, nb }
		Changed()
		M:RefreshListEditor("colors")
	end
	ColorPickerFrame:SetupColorPickerAndShow({
		r = r, g = g, b = b,
		swatchFunc = function() Set(ColorPickerFrame:GetColorRGB()) end,
		cancelFunc = function()
			M.db.colors[item.key] = previous
			Changed()
			M:RefreshListEditor("colors")
		end,
	})
end

function M:OpenColorEditor()
	return self:OpenListEditor({
		key = "colors",
		title = L["Chat colors"],
		help = L["Click a color to change it. Game puts the game's own color back. Numbered channels keep their color when their number changes."],
		items = EditorItems,
		text = function(item)
			return item.label, type(M.db.colors[item.key]) == "table" and "|cff" .. Hex(unpack(E.media.accentText)):sub(3) .. L["yours"] .. "|r" or L["game"]
		end,
		controls = {
			{ kind = "button", label = L["Game"], width = 50, tipTitle = L["Game color"], tip = L["Back to the game's own color for this line."],
				shown = function(item) return type(M.db.colors[item.key]) == "table" end,
				click = function(item) M.db.colors[item.key] = nil; Changed() end },
			{ kind = "swatch", color = RowColor, click = PickColor },
		},
		status = function()
			if M.db.colorMode == "game" then return E:TextHex("warn") .. L["Off: Game colors"] .. "|r" end
			return ""
		end,
		footer = {
			{ label = L["All game colors"], width = 120, tip = L["Removes every color you set here."],
				click = function() wipe(M.db.colors); Changed() end },
		},
	})
end

---------------------------------------------------------------------------
-- Live preview (Messages tab): sample lines through the real rewrite.
---------------------------------------------------------------------------
local PREVIEW_LINES = 6

local function Template(globalName, fallback)
	local value = rawget(_G, globalName)
	if type(value) == "string" and value:find("%s", 1, true) then return value end
	return fallback
end

-- A sample line's color: EldoUI's color when one is set and on, else the
-- player's own (kept original, or the game's current value).
local function SampleColor(slot, key, r, g, b)
	local own = M.db.colorMode ~= "game" and Improve() and M.db.colors[key]
	if type(own) == "table" then return own[1], own[2], own[3] end
	local original = Store()[slot]
	if type(original) == "table" then return original[1], original[2], original[3] end
	local info = Info(slot)
	if info and type(info.r) == "number" then return info.r, info.g, info.b end
	return r, g, b
end

-- Trade (or the second channel) as the preview's channel line.
local function SampleChannel()
	local channels = M:JoinedChannels()
	for _, channel in ipairs(channels) do
		if ChannelLabel(channel.name):lower() == "trade" then return channel end
	end
	return channels[2] or channels[1]
end

local function PlayerLink(name, lineID, chatType, target)
	return ("|Hplayer:%s:%d:%s%s|h[%s]|h"):format(name, lineID, chatType, target and (":" .. target) or "", name)
end

-- The sample lines: { text, r, g, b, event, args }
function M:PreviewSamples()
	local me = E.PlayerName and E:PlayerName() or "Eldo"
	if type(me) ~= "string" or IsSecret(me) then me = "Eldo" end
	local guid = UnitGUID and UnitGUID("player")
	if IsSecret(guid) then guid = nil end
	local function Args(message, sender, lineID)
		return { message, sender, "", "", sender, "", 0, 0, "", 0, lineID, guid, 0, false, false, false }
	end
	-- Sample links in the game's own colors: epic quality, quest gold.
	local epic = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[4]
	local item = (epic and epic.hex or E:TextHex("accent")) .. "|Hitem:19019::::::::60:::::|h[Thunderfury, Blessed Blade of the Windseeker]|h|r"
	local quest = E:TextHex("gold") .. "|Hquest:2:60|h[Sharptalon's Claw]|h|r"
	local samples = {}
	local function Add(text, slot, fallback, event, args, key)
		local r, g, b = SampleColor(slot, key or slot, unpack(fallback))
		samples[#samples + 1] = { text, r, g, b, event, args }
	end
	local channel = SampleChannel()
	local index, name = channel and channel.index or 2, channel and channel.name or "Trade - City"
	Add(("|Hchannel:channel:%d|h[%d. %s]|h %s: WTS %s, www.example.com"):format(index, index, name, PlayerLink(me, 9001, "CHANNEL", tostring(index)), item),
		"CHANNEL" .. index, { 1, 0.75, 0.75 }, "CHAT_MSG_CHANNEL", Args("WTS", me, 9001), channel and channel.key or "zone:2")
	Add(("|Hchannel:GUILD|h[Guild]|h %s: "):format(PlayerLink(me, 9002, "GUILD")) .. L["anyone for %s?"]:format(quest),
		"GUILD", { 0.25, 1, 0.25 }, "CHAT_MSG_GUILD", Args("anyone", me, 9002))
	Add(Template("CHAT_SAY_GET", "%s says: "):format(PlayerLink(me, 9003, "SAY")) .. L["Well met!"],
		"SAY", { 1, 1, 1 }, "CHAT_MSG_SAY", Args(L["Well met!"], me, 9003))
	Add(Template("CHAT_WHISPER_GET", "%s whispers: "):format(PlayerLink(me, 9004, "WHISPER")) .. L["inv please"],
		"WHISPER", { 1, 0.5, 1 }, "CHAT_MSG_WHISPER", Args(L["inv please"], me, 9004))
	Add(Template("CHAT_WHISPER_INFORM_GET", "To %s: "):format(PlayerLink(me, 9005, "WHISPER")) .. L["on my way"],
		"WHISPER_INFORM", { 1, 0.5, 1 }, "CHAT_MSG_WHISPER_INFORM", Args(L["on my way"], me, 9005), "WHISPER")
	Add(Template("CHAT_PARTY_GET", "[Party] %s: "):format(PlayerLink(me, 9006, "PARTY")) .. L["ready"],
		"PARTY", { 0.67, 0.67, 1 }, "CHAT_MSG_PARTY", Args(L["ready"], me, 9006))
	return samples
end

-- The game's own timestamp in front, as the client would add it.
local function GameStamp()
	local db = M.db
	if db.eldoTimestamps then return "" end
	local format = db.timestamps
	if format == "KEEP" then format = C_CVar and C_CVar.GetCVar and C_CVar.GetCVar("showTimestamps") end
	if type(format) ~= "string" or format == "none" or format == "" then return "" end
	local ok, text = pcall(date, format, 1767225600 + 15 * 3600 + 4 * 60)
	return ok and type(text) == "string" and text or ""
end

function M:ChatFontPath()
	local id = self.db.chatFont
	if id and id ~= "theme" then
		local path = E:FetchMedia("font", id)
		if path then return path end
	end
	return E.media.font
end

local previewCanvas

function M:DrawPreview(canvas)
	if not canvas then return end
	previewCanvas = canvas
	canvas.lines = canvas.lines or {}
	local db = self.db
	local path, size, outline = self:ChatFontPath(), db.fontSize, self:Outline()
	local spacing = db.lineSpacing or 0
	local y = 0
	for index, sample in ipairs(self:PreviewSamples()) do
		if index > PREVIEW_LINES then break end
		local line = canvas.lines[index]
		if not line then
			line = canvas:CreateFontString(nil, "OVERLAY")
			line:SetJustifyH("LEFT")
			line:SetWordWrap(false)
			canvas.lines[index] = line
		end
		-- Direct on purpose: the preview shows the chat font at the chat's own size.
		if not line:SetFont(path, size, outline) then line:SetFont(E.media.font, size, outline) end
		if db.fontShadow then line:SetShadowOffset(1, -1) line:SetShadowColor(0, 0, 0, 1) else line:SetShadowOffset(0, 0) end
		line:ClearAllPoints()
		line:SetPoint("TOPLEFT", canvas, "TOPLEFT", 0, -y)
		line:SetPoint("TOPRIGHT", canvas, "TOPRIGHT", 0, -y)
		local text, r, g, b = GameStamp() .. sample[1], sample[2], sample[3], sample[4]
		if Improve() and self.FormatLine then
			text, r, g, b = self.FormatLine(nil, text, r, g, b, sample[5], sample[6], false)
		end
		line:SetText(text)
		line:SetTextColor(r, g, b)
		y = y + size + spacing + 2
	end
end

function M:RefreshPreview()
	if previewCanvas and previewCanvas:IsVisible() then self:DrawPreview(previewCanvas) end
end

---------------------------------------------------------------------------
-- Font and line spacing for the chat windows (skin switch)
---------------------------------------------------------------------------
local spacingOriginal = setmetatable({}, { __mode = "k" })

function M:ApplyFrameText(frame, skin)
	if not frame.GetSpacing then return end
	local want = skin and (self.db.lineSpacing or 0) > 0
	if want then
		if spacingOriginal[frame] == nil then spacingOriginal[frame] = frame:GetSpacing() or 0 end
		if frame:GetSpacing() ~= self.db.lineSpacing then frame:SetSpacing(self.db.lineSpacing) end
	elseif spacingOriginal[frame] ~= nil then
		frame:SetSpacing(spacingOriginal[frame])
		spacingOriginal[frame] = nil
	end
end

---------------------------------------------------------------------------
-- Wiring
---------------------------------------------------------------------------
function M:EnableColors()
	self:RegisterEvent("UPDATE_CHAT_COLOR", function(_, _, slot, r, g, b) M:OnChatColor(slot, r, g, b) end)
	self:RegisterEvent("CHANNEL_UI_UPDATE", function() if M.active then M:ApplyChatColors() end end)
	self:RegisterEvent("CHAT_MSG_CHANNEL_NOTICE", function() if M.active then C_Timer.After(0.5, function() M:ApplyChatColors() end) end end)
end

function M:DisableColors()
	self:UnregisterEvent("UPDATE_CHAT_COLOR")
	self:UnregisterEvent("CHANNEL_UI_UPDATE")
	self:UnregisterEvent("CHAT_MSG_CHANNEL_NOTICE")
	self:RestoreChatColors()
end
