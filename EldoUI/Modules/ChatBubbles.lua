-- EldoUI Chat bubbles: the speech bubbles over players and NPCs.
--
-- Gated by the Blizzard element "chat-bubbles":
--   skin  a flat EldoUI box instead of the parchment bubble and the EldoUI
--         font on the bubble text
--   hide  which bubbles the game shows (say, party, raid) and hiding them in
--         instances, all through Blizzard's own bubble CVars
--
-- Inside instances (dungeons, raids, battlegrounds) the game makes bubbles
-- forbidden frames: no addon may touch them. There only the font (a shared
-- font object) and the CVars apply; EldoUI never tries to skin a forbidden
-- bubble (C_ChatBubbles.GetAllChatBubbles(false) leaves them out).
--
-- Taint rules: no field is written into a bubble frame. EldoUI keeps its
-- own weak tables (bubble -> box textures, texture -> original alpha) and
-- only calls widget methods.
local _, E = ...

local ELEMENT = "chat-bubbles"

local M = E:NewModule("ChatBubbles", {
	title = "Chat Bubbles",
	desc = "Flat EldoUI speech bubbles with the EldoUI font, and control over which bubbles show, also in instances.",
	category = "Chat & Social",
	frames = {},
	movers = {},
	blizzard = { "chat-bubbles" },
	savedKeys = { "profile.modules.ChatBubbles" },
	optionsPage = "module:ChatBubbles",
	presets = { "Accent", "Compact", "Flat", "Glass", "Large", "Quiet", "TextOnly" },
	reload = false,
	defaults = {
		-- Skin
		font = true,
		fontSize = 13,
		fontOutline = "NONE",
		background = "flat",    -- flat, transparent, none
		alpha = 0.85,
		border = "dark",        -- dark, accent, none
		padding = 6,
		-- Which bubbles (element switch "hide")
		say = "KEEP",           -- KEEP, ON, OFF (CVar chatBubbles)
		party = "KEEP",         -- KEEP, ON, OFF (CVar chatBubblesParty)
		raid = "KEEP",          -- KEEP, ON, OFF (CVar chatBubblesRaid)
		hideInInstances = false,
	},
})

-- Weak tables: EldoUI's own bookkeeping, never fields on Blizzard frames.
local boxes = setmetatable({}, { __mode = "k" })      -- bubble holder -> { bg, top, bottom, left, right }
local own = setmetatable({}, { __mode = "k" })        -- EldoUI's own box textures
local hiddenArt = setmetatable({}, { __mode = "k" })  -- texture -> original alpha (art and tail)
local originalFont                                     -- { path, size, flags }

local BUBBLE_EVENTS = {
	"CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
	"CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_MONSTER_SAY",
	"CHAT_MSG_MONSTER_YELL", "CHAT_MSG_MONSTER_PARTY",
}

local CVARS = {
	{ cvar = "chatBubbles", key = "say" },
	{ cvar = "chatBubblesParty", key = "party" },
	{ cvar = "chatBubblesRaid", key = "raid" },
}

function M:Allowed(action)
	return self.active and E:BlizzardAllowed(ELEMENT, action)
end

---------------------------------------------------------------------------
-- Font: ChatBubbleFont is shared by every bubble, forbidden ones too.
---------------------------------------------------------------------------
-- The chat font picked in Chat (Panel, Chat font), so bubbles read like the
-- chat; the theme font when Chat keeps the theme font.
function M:FontPath()
	local chat = E.modules and E.modules.Chat
	if chat and chat.db and chat.ChatFontPath then
		local ok, path = pcall(chat.ChatFontPath, chat)
		if ok and type(path) == "string" and path ~= "" then return path end
	end
	return E.media.font
end

function M:ApplyFont()
	if not ChatBubbleFont then return end
	if self:Allowed("skin") and self.db.font then
		if not originalFont then originalFont = { ChatBubbleFont:GetFont() } end
		local outline = self.db.fontOutline ~= "NONE" and self.db.fontOutline or ""
		local path = self:FontPath()
		-- The game's bubble font object: set directly, with Large text.
		local size = self.db.fontSize * E:TextScale()
		-- The chat font's name font, so a bubble in another alphabet keeps
		-- its letters.
		if not E:SetMessageFont(ChatBubbleFont, path, size, outline) then
			E:SetMessageFont(ChatBubbleFont, E.media.font, size, outline)
		end
	else
		self:RestoreFont()
	end
end

function M:RestoreFont()
	if originalFont and originalFont[1] and ChatBubbleFont then
		ChatBubbleFont:SetFont(originalFont[1], originalFont[2], originalFont[3] or "")
	end
	originalFont = nil
end

---------------------------------------------------------------------------
-- Skin one bubble (the ChatBubbleTemplate frame inside the bubble)
--
-- The game's bubble is a nine-slice frame drawn 16 units around its text,
-- with a parchment tail under it. The skin draws a flat box straight
-- around the text (padding), sized in screen pixels of the bubble itself
-- (bubbles are not scaled like the rest of the interface), on the
-- bubble's own BACKGROUND layer so it is always under the text. The game's
-- art and tail are made invisible: the tail hangs where the game's wider
-- frame ends, so it would float apart from a tighter box.
---------------------------------------------------------------------------
local function BubbleHolder(bubble)
	if not bubble or E.FrameCheck(bubble, "IsForbidden") then return end
	for _, child in ipairs({ bubble:GetChildren() }) do
		if not E.FrameCheck(child, "IsForbidden") and child.String then return child end
	end
end

local SIDES = { "top", "bottom", "left", "right" }

local function HideArt(holder, hide)
	local text = holder.String
	for _, region in ipairs({ holder:GetRegions() }) do
		if region ~= text and not own[region] and region:IsObjectType("Texture") then
			if hide then
				if hiddenArt[region] == nil then hiddenArt[region] = region:GetAlpha() end
				region:SetAlpha(0)
			elseif hiddenArt[region] ~= nil then
				region:SetAlpha(hiddenArt[region])
				hiddenArt[region] = nil
			end
		end
	end
end

local function Box(holder)
	local box = boxes[holder]
	if box then return box end
	box = { bg = holder:CreateTexture(nil, "BACKGROUND", nil, -8) }
	for _, side in ipairs(SIDES) do box[side] = holder:CreateTexture(nil, "BACKGROUND", nil, -7) end
	for _, texture in pairs(box) do own[texture] = true end
	boxes[holder] = box
	return box
end

local function ShowBox(box, shown)
	for _, texture in pairs(box) do texture:SetShown(shown) end
end

-- One screen pixel of the bubble (two under the high contrast style).
function M:EdgeFor(holder)
	return E:PixelFor(holder) * E:EdgeSize() / (E.pixel or 1)
end

function M:PaintBox(holder, box)
	local db = self.db
	local pad, text = db.padding, holder.String
	local bg = box.bg
	bg:ClearAllPoints()
	bg:SetPoint("TOPLEFT", text, "TOPLEFT", -pad, pad)
	bg:SetPoint("BOTTOMRIGHT", text, "BOTTOMRIGHT", pad, -pad)
	local r, g, b = unpack(E.media.backdropColor)
	local alpha = db.background == "transparent" and db.alpha * 0.6 or db.alpha
	bg:SetColorTexture(r, g, b, alpha)
	bg:SetShown(db.background ~= "none")
	local edge = self:EdgeFor(holder)
	local er, eg, eb, ea
	if db.border == "accent" then
		er, eg, eb = unpack(E.media.accentColor)
		ea = 1
	else
		er, eg, eb, ea = unpack(E.media.borderColor)
	end
	for _, side in ipairs(SIDES) do
		local line = box[side]
		line:ClearAllPoints()
		if side == "top" or side == "bottom" then
			local corner = side == "top" and "TOP" or "BOTTOM"
			line:SetPoint(corner .. "LEFT", bg, corner .. "LEFT")
			line:SetPoint(corner .. "RIGHT", bg, corner .. "RIGHT")
			line:SetHeight(edge)
		else
			local corner = side == "left" and "LEFT" or "RIGHT"
			line:SetPoint("TOP" .. corner, bg, "TOP" .. corner)
			line:SetPoint("BOTTOM" .. corner, bg, "BOTTOM" .. corner)
			line:SetWidth(edge)
		end
		line:SetColorTexture(er, eg, eb, ea or 1)
		line:SetShown(db.border ~= "none")
	end
end

function M:SkinBubble(bubble)
	local holder = BubbleHolder(bubble)
	if not holder then return end
	HideArt(holder, true)
	self:PaintBox(holder, Box(holder))
end

function M:UnskinBubble(holder, box)
	ShowBox(box, false)
	if E.FrameCheck(holder, "IsForbidden") then return end
	HideArt(holder, false)
end

function M:ScanBubbles()
	if not self:Allowed("skin") or not (C_ChatBubbles and C_ChatBubbles.GetAllChatBubbles) then return end
	for _, bubble in ipairs(C_ChatBubbles.GetAllChatBubbles(false)) do
		self:SkinBubble(bubble)
	end
end

function M:RestoreBubbles()
	for holder, box in pairs(boxes) do self:UnskinBubble(holder, box) end
end

-- New bubbles appear a frame after the chat event that makes them.
function M:QueueScan()
	if self.scanQueued then return end
	self.scanQueued = true
	C_Timer.After(0, function()
		self.scanQueued = nil
		self:ScanBubbles()
	end)
end

---------------------------------------------------------------------------
-- Which bubbles show: Blizzard's CVars, through E:SetCVar so "Blizzard
-- default" puts the player's own values back.
---------------------------------------------------------------------------
function M:ApplyCVars()
	E:RunOutOfCombat(function()
		-- Start from the player's own values, then set what EldoUI controls.
		E:RestoreCVars(ELEMENT)
		if not self:Allowed("hide") then return end
		local db = self.db
		for _, entry in ipairs(CVARS) do
			local mode = db[entry.key]
			if mode == "ON" then
				E:SetCVar(entry.cvar, "1", ELEMENT)
			elseif mode == "OFF" then
				E:SetCVar(entry.cvar, "0", ELEMENT)
			end
		end
		if db.hideInInstances then
			local inInstance = IsInInstance()
			if inInstance then E:SetCVar("chatBubbles", "0", ELEMENT) end
		end
	end)
end

---------------------------------------------------------------------------
-- Apply and undo
---------------------------------------------------------------------------
function M:Apply()
	self:ApplyFont()
	if self:Allowed("skin") then
		for _, event in ipairs(BUBBLE_EVENTS) do
			self:RegisterEvent(event, function() M:QueueScan() end)
		end
		self:ScanBubbles()
	else
		for _, event in ipairs(BUBBLE_EVENTS) do self:UnregisterEvent(event) end
		self:RestoreBubbles()
	end
	self:ApplyCVars()
end

function M:RestoreBlizzard()
	for _, event in ipairs(BUBBLE_EVENTS) do self:UnregisterEvent(event) end
	self:RestoreBubbles()
	self:RestoreFont()
	E:RestoreCVars(ELEMENT)
end

function M:OnEnable()
	self:RegisterEvent("PLAYER_ENTERING_WORLD", function() M:ApplyCVars() end)
	self:RegisterEvent("ZONE_CHANGED_NEW_AREA", function() M:ApplyCVars() end)
	E:RunOutOfCombat(function() self:Apply() end)
end

function M:OnDisable()
	self:UnregisterEvent("PLAYER_ENTERING_WORLD")
	self:UnregisterEvent("ZONE_CHANGED_NEW_AREA")
	E:RunOutOfCombat(function() self:RestoreBlizzard() end)
end

function M:OnProfileChanged()
	if self.active then E:RunOutOfCombat(function() self:Apply() end) end
end

E:RegisterBlizzardHandler(ELEMENT, {
	owner = "ChatBubbles",
	apply = function() if M.active then M:Apply() end end,
	undo = function() M:RestoreBlizzard() end,
	install = { skin = true },
	legacy = false,
})

---------------------------------------------------------------------------
-- Options
---------------------------------------------------------------------------
local function NoBackground() return M.db and M.db.background == "none" end

M.options = {
	{ type = "description", label = "What EldoUI may do with bubbles is set on the Blizzard UI page. In instances the game locks them: only the font and which ones show apply." },
	{ type = "header", label = "Text" },
	{ type = "toggle", key = "font", label = "EldoUI font", desc = "Bubble text in your chat font (the Chat font picked under Chat, or the theme font), also inside instances. Off keeps Blizzard's font." },
	{ type = "range", key = "fontSize", label = "Text size", min = 8, max = 24, step = 1, desc = "Size of the bubble text." },
	{ type = "select", key = "fontOutline", label = "Outline", values = { NONE = "None", OUTLINE = "Outline", THICKOUTLINE = "Thick outline" },
		desc = "Outline around the bubble text. Helps when the background is off." },
	{ type = "header", label = "Box" },
	{ type = "select", key = "background", label = "Background", values = { flat = "Flat", transparent = "Transparent", none = "None (text only)" },
		desc = "The box behind the bubble text, replacing Blizzard's parchment bubble and its pointer." },
	{ type = "range", percent = true, key = "alpha", label = "Background opacity", min = 0.1, max = 1, step = 0.05, hidden = NoBackground, desc = "How dark the bubble box is." },
	{ type = "select", key = "border", label = "Border", values = { dark = "Dark", accent = "Accent color", none = "None" },
		desc = "The 1-pixel line around the bubble box." },
	{ type = "range", key = "padding", label = "Padding", min = 2, max = 16, step = 1, desc = "Space between the text and the edge of the box." },
	{ type = "header", label = "Which bubbles show" },
	{ type = "description", label = "Needs the Blizzard UI switch Hide for chat bubbles. Game setting leaves Blizzard's Social option alone." },
	{ type = "select", key = "say", label = "Say and yell bubbles", values = { KEEP = "Game setting", ON = "Show", OFF = "Hide" },
		desc = "Bubbles for /say, /yell and NPC speech (CVar chatBubbles; off hides every bubble)." },
	{ type = "select", key = "party", label = "Party bubbles", values = { KEEP = "Game setting", ON = "Show", OFF = "Hide" },
		desc = "Bubbles for party chat (CVar chatBubblesParty)." },
	{ type = "select", key = "raid", label = "Raid bubbles", values = { KEEP = "Game setting", ON = "Show", OFF = "Hide" },
		desc = "Bubbles for raid chat (CVar chatBubblesRaid)." },
	{ type = "toggle", key = "hideInInstances", label = "No bubbles in instances", desc = "Turn every bubble off in dungeons, raids and battlegrounds, and back on when you leave." },
}

E:RegisterStyles("ChatBubbles", {
	{ key = "Flat", title = "Flat", desc = "Dark flat box with a dark border.",
		settings = { font = true, fontSize = 13, fontOutline = "NONE", background = "flat", alpha = 0.85, border = "dark", padding = 6 } },
	{ key = "Accent", title = "Accent", desc = "Flat box with an accent-colored border.",
		settings = { font = true, fontSize = 13, fontOutline = "NONE", background = "flat", alpha = 0.9, border = "accent", padding = 6 } },
	{ key = "Glass", title = "Glass", desc = "See-through box, no border.",
		settings = { font = true, fontSize = 13, fontOutline = "NONE", background = "transparent", alpha = 0.7, border = "none", padding = 7 } },
	{ key = "TextOnly", title = "Text only", desc = "No box, outlined text floating over the speaker.",
		settings = { font = true, fontSize = 14, fontOutline = "OUTLINE", background = "none", border = "none", padding = 4 } },
	{ key = "Large", title = "Large", desc = "Bigger text and roomier boxes, easy to read from afar.",
		settings = { font = true, fontSize = 17, fontOutline = "NONE", background = "flat", alpha = 0.9, border = "dark", padding = 9 } },
	{ key = "Compact", title = "Compact", desc = "Small text and tight boxes for busy cities.",
		settings = { font = true, fontSize = 11, fontOutline = "NONE", background = "flat", alpha = 0.8, border = "dark", padding = 3 } },
	{ key = "Quiet", title = "Quiet", desc = "Flat bubbles, none in instances, no raid bubbles.",
		settings = { font = true, fontSize = 13, fontOutline = "NONE", background = "flat", alpha = 0.85, border = "dark", padding = 6,
			raid = "OFF", hideInInstances = true } },
})
