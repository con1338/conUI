-- EldoUI Quest Tracker: Blizzard's objective tracker (ObjectiveTrackerFrame)
-- in the EldoUI look, on the EldoUI_Quests mover, with a fixed height, its
-- own font, and a see-through mode in combat or in instances. Questie's
-- tracker gets the same backdrop and spot when Questie is loaded.
--
-- Everything here is gated by the "objective-tracker" Blizzard element
-- switch (Core/Blizzard.lua). With it off EldoUI leaves the tracker exactly
-- as Blizzard made it; the hooks below stay installed but return at once.
--
-- Taint notes, read before changing this file:
--   * The tracker is not protected, but its quest item buttons call the
--     protected UseQuestLogSpecialItem with an attribute Blizzard sets during
--     layout. Calling tracker methods (SetCollapsed, Update, Show, Hide) from
--     addon code would run that layout tainted and break the item buttons,
--     and Show/Hide would also taint the right-side managed frame container
--     (boss frames). So EldoUI never calls them: "collapse in combat" and
--     "hide" only change the alpha and the anchor, which run no Blizzard code.
--   * The anchor is set with two points (top and bottom), so Blizzard's own
--     SetHeight calls change nothing and cannot start a resize loop.
--   * Sizes of the tracker and its lines are read only once the game has
--     laid them out (E.RectReady). An earlier read makes the game lay them
--     out inside EldoUI's code, the tracker's own size handler then queues
--     its next update from there, and that update and every later one run
--     tainted (in a battleground its aura check then fails).
--   * Skins only set alpha, textures, fonts and colors on Blizzard regions,
--     and add child frames/regions; no Blizzard table gets a new field.
--   * Objective counts (valueCounts) are drawn the same way, after
--     Blizzard's layout (hooksecurefunc on EndLayout): EldoUI's own font
--     string on the line holds the count, and the line's text is set to the
--     part without it, only when it still fits. Blizzard writes the full
--     text again at its next layout and measured the line before, so its
--     layout, the item buttons and their secure attributes never see EldoUI
--     code. EldoUI's state lives in a weak table keyed by the line.
--
-- Quest item key: EldoUI's own secure button
-- (EldoUI_QuestItemButton) on the "Quest item button" mover. It holds the
-- item of the super-tracked quest, else the first tracked quest that has
-- one. The player binds a key to it (keybind mode, or /eui keybind); the
-- item is used only by that key press or a click, through Blizzard's own
-- "item" secure action. Its attributes, shown state and position change out
-- of combat only; a change in combat waits for combat to end. It is
-- EldoUI's own frame, so it follows this module's settings, not the
-- tracker's Blizzard UI switch.
local _, E = ...
local L = E.L

local Key = E.Key
local ELEMENT = "objective-tracker"
local WIDTH = 260          -- Blizzard's tracker width (ObjectiveTrackerContainerTemplate)
local HEADER_ATLAS = "ui-questtracker-primary-objective-header"
local MODULE_HEADER_ATLAS = "UI-QuestTracker-Secondary-Objective-Header"

local M = E:NewModule("ObjectiveTracker", {
	title = "Quest Tracker",
	desc = "Blizzard's quest and objective tracker: EldoUI look, mover, height, font, fade in combat and Questie support.",
	category = "Interface",
	frames = { "EldoUI_QuestItem" },
	movers = { "EldoUI_Quests", "EldoUI_QuestItem" },
	blizzard = { "objective-tracker" },
	savedKeys = { "profile.modules.ObjectiveTracker" },
	optionsPage = "module:ObjectiveTracker",
	presets = { "Blizzard", "Clean", "Compact", "Focus", "Large", "Panel", "Quiet" },
	defaults = {
		-- Size and place (Move and scale switch)
		height = 480,
		scale = 1,
		-- Look (Skin switch)
		font = true,              -- EldoUI font face on tracker text
		fontSize = 0,             -- 0 keeps Blizzard's text size (Edit Mode)
		headerSize = 0,           -- 0 = line size + 2, like Blizzard
		accentHeaders = true,
		valueCounts = true,       -- objective counts at the right end of the line, in the accent color
		headerLine = true,        -- thin accent lines on section headers
		headerStyle = "fold",     -- fold: the name centered between two lines | under: one line under it
		backdrop = "none",        -- none | transparent | panel
		skinBars = true,
		skinItems = true,
		skinButtons = true,
		-- Behavior (Improve switch)
		-- When the tracker shows and how it fades: the shared rules
		-- (Core/Visibility.lua), alpha only.
		visibility = E:VisibilityDefaults(),
		-- Which instances count for the visibility rules' instance settings.
		instanceTypes = { party = true, raid = true, pvp = true, arena = true, scenario = false },
		-- Questie
		questie = { skin = true, move = true },
		-- Quest item key (EldoUI's own button)
		questItem = {
			enabled = true,
			source = "super",     -- super (super-tracked first) | tracker (tracker order only)
			size = 36,
			showButton = true,    -- false: key only, the button stays invisible
			hotkey = true,
			count = true,
			range = true,
			glow = true,
			complete = false,     -- also offer items of quests that are ready to turn in
		},
	},
})
-- The tracker follows its visibility block; the quest item button shows
-- while a tracked quest has an item to use.
E:RegisterVisibilityFacet("EldoUI_Quests", "rules", { module = "ObjectiveTracker", setting = "visibility" })
E:RegisterVisibilityFacet("EldoUI_QuestItem", "event", { module = "ObjectiveTracker" })

local function Allowed(action) return E:BlizzardAllowed(ELEMENT, action) end
-- Allowed and the module is on: what every apply step checks.
local function Can(action) return M.active and Allowed(action) end
local function Tracker() return _G.ObjectiveTrackerFrame end
local BOX = "EldoUI_Quests"
-- Hide on the Quest Tracker box (move mode or the Hidden boxes page). The
-- trackers are pinned to the box, not parented, so hiding the box alone
-- would leave them on screen; they are parked off screen and invisible.
-- Only while the box exists (Move and scale on), so Show can bring it back.
local function BoxHidden() return Can("move") and E:IsHidden(BOX) end

---------------------------------------------------------------------------
-- Pins: keep a frame on EldoUI's anchor. Blizzard (Edit Mode's layout
-- passes, the right managed frame container) or another addon re-anchors
-- these frames; the core pin (E:PinBlizzardFrame, Core/Blizzard.lua) puts
-- them back with the plain widget methods, so Edit Mode's SetPoint override
-- never runs from EldoUI. Unprotected frames follow at once, even in
-- combat; a protected one waits for combat to end.
---------------------------------------------------------------------------
local pinned = {}   -- frame -> the anchor function EldoUI uses now

local function Pin(frame, anchor, spec)
	if not E:SkinUsable(frame) then return end
	pinned[frame] = anchor
	spec = spec or {}
	spec.anchor = anchor
	spec.active = function() return pinned[frame] == anchor end
	E:PinBlizzardFrame(frame, spec)
end

-- restore: put the frame back on the points it had before the pin (the
-- fold opening again); otherwise Blizzard's next layout places it.
local function Unpin(frame, restore)
	if not frame or not pinned[frame] then return end
	pinned[frame] = nil
	E:UnpinBlizzardFrame(frame, not restore)
end

---------------------------------------------------------------------------
-- Holder and mover
---------------------------------------------------------------------------
-- Move mode's stand-in while the tracker is empty: a sample quest in the
-- tracker's text sizes, header color, background and see-through.
local function StandIn()
	local db = M.db
	if not db then return nil end
	local size = db.font and (db.fontSize or 0) > 0 and db.fontSize or 12
	local headerSize = db.font and (db.headerSize or 0) > 0 and db.headerSize or size + 2
	local header = { E:TokenColor(db.accentHeaders and db.font ~= false and "accent" or "gold") }
	local visibility = db.visibility
	local fade = visibility and visibility.show == "mouseover" and tonumber(visibility.fadedAlpha) or nil
	return "tooltip", {
		width = WIDTH, fontSize = size, headerSize = headerSize, align = "TOPRIGHT", fade = fade,
		alpha = db.backdrop == "none" and 0 or (db.backdrop == "transparent" and 0.6 or nil),
		lines = {
			{ L["Quests"], header },
			{ L["Sample quest"], { E:TokenColor("gold") } },
			{ L["Sample objective: 3/8"] },
		},
	}
end

function M:CreateHolder()
	if self.holder then return end
	local holder = CreateFrame("Frame", BOX, UIParent)
	holder:SetSize(WIDTH, self.db.height)
	self.holder = holder
	-- Top right, under the minimap (placement.md 2.6, 1440 points).
	local previous = E.currentModule
	E.currentModule = self -- tag the mover with this module for exports
	self.mover = E:CreateMover(holder, BOX, L["Quest Tracker"], { "TOPRIGHT", "UIParent", "TOPRIGHT", -90, -358 },
		{ sample = { config = StandIn } })
	E.currentModule = previous
end

-- The holder is protected while a protected frame sits on it, so its size
-- changes wait for the end of combat.
function M:SizeHolder()
	if InCombatLockdown() then
		E:RunOutOfCombat(function() M:SizeHolder() end, "objectiveTracker:size")
		return
	end
	local scale = self.db.scale or 1
	self.holder:SetSize(WIDTH * scale, (self.db.height or 480) * scale)
end

local AnchorToHolder

---------------------------------------------------------------------------
-- Room at the bottom: another EldoUI frame that sits in the quest
-- column (the My Adventure journal tracker) asks for a band at the bottom
-- of the holder, and Blizzard's tracker ends above it. Only EldoUI's own
-- holder and the two-point anchor change, out of combat, and only while
-- Move and scale puts the tracker on the holder.
--   M:ReserveBottom(key, height)   height in UIParent units; nil or 0 drops it
--   M:ReservedBottom()             the band now (the tallest ask), 0 when none
--   M:ColumnHolder()               the holder while the tracker sits on it
---------------------------------------------------------------------------
local reserved = {}   -- key -> height

function M:ReservedBottom()
	local most = 0
	for _, height in pairs(reserved) do
		if height > most then most = height end
	end
	return most
end

local function Reanchor()
	local tracker = Tracker()
	if tracker and pinned[tracker] == AnchorToHolder then E.BlizzardKeep.ApplyPin(tracker) end
end

function M:ReserveBottom(key, height)
	if type(key) ~= "string" then return false end
	height = tonumber(height)
	if height and height > 0 then
		height = math.floor(height + 0.5)
	else
		height = nil
	end
	-- The band and the anchor change together, out of combat.
	E:RunOutOfCombat(function()
		if reserved[key] == height then return end
		reserved[key] = height
		Reanchor()
	end, "objectiveTracker:band:" .. key)
	return self:ColumnHolder() ~= nil
end

-- The holder, while Blizzard's tracker (Move and scale on, Hide off) or
-- Questie's tracker is pinned to it, so a frame docked in the column knows
-- where the column is.
function M:ColumnHolder()
	if not (self.active and self.holder and self.holder:IsShown()) then return nil end
	local tracker = Tracker()
	if (tracker and pinned[tracker] == AnchorToHolder) or self:QuestieInColumn() then return self.holder end
	return nil
end

-- Offsets of a pinned frame are in its own scale: the band is divided by
-- the tracker's scale, so it stays the same height on screen.
AnchorToHolder = function()
	local band = M:ReservedBottom()
	local scale = M.db and M.db.scale or 1
	if scale <= 0 then scale = 1 end
	return {
		{ "TOPRIGHT", M.holder, "TOPRIGHT", 0, 0 },
		{ "BOTTOMRIGHT", M.holder, "BOTTOMRIGHT", 0, band / scale },
	}
end

-- Hidden: parked off the left edge of the screen (and invisible), so no
-- Blizzard OnHide code runs from EldoUI.
local function AnchorOffscreen()
	return {
		{ "TOPRIGHT", UIParent, "TOPLEFT", -400, 0 },
		{ "BOTTOMRIGHT", UIParent, "TOPLEFT", -400, -200 },
	}
end

---------------------------------------------------------------------------
-- Fonts: the tracker draws its text with two shared font objects.
---------------------------------------------------------------------------
local blizzardFonts -- Blizzard's own font of each object: { path, size, flags }

local function FontObjects()
	return _G.ObjectiveTrackerLineFont, _G.ObjectiveTrackerHeaderFont
end

-- Remember what Blizzard set (at first use and after each of its text size
-- changes), so "0 = Blizzard's size" and undo have something to go back to.
local function SaveBlizzardFonts()
	local line, header = FontObjects()
	if not (line and header and line.GetFont) then return end
	blizzardFonts = { line = { line:GetFont() }, header = { header:GetFont() } }
end

function M:ApplyFonts()
	local line, header = FontObjects()
	if not (line and header and line.GetFont) then return end
	local previousFont, previousSize, previousFlags = E.PlainCallAll(header.GetFont, header)
	if Can("skin") and self.db.font then
		if not blizzardFonts then SaveBlizzardFonts() end
		local outline = E.db.general.fontOutline or ""
		local size = (self.db.fontSize or 0) > 0 and self.db.fontSize or math.floor((blizzardFonts.line[2] or 12) + 0.5)
		local headerSize = (self.db.headerSize or 0) > 0 and self.db.headerSize or size + 2
		-- Game font objects shared by every tracker line: set directly (with
		-- Large text, as E:SetFont would), restored when the skin turns off.
		local scale = E:TextScale()
		line:SetFont(E.media.font, size * scale, outline)
		header:SetFont(E.media.font, headerSize * scale, outline)
		self.fontsSet = true
	elseif self.fontsSet and blizzardFonts then
		line:SetFont(unpack(blizzardFonts.line))
		header:SetFont(unpack(blizzardFonts.header))
		self.fontsSet = false
	else
		return
	end
	local font, size, flags = E.PlainCallAll(header.GetFont, header)
	if font == previousFont and size == previousSize and flags == previousFlags then return end
	-- The title overlay owns its own font and does not follow this object.
	local marks = E:GetModule("QuestTint")
	if marks and marks.active and marks.UpdateTracker then marks:UpdateTracker() end
end

---------------------------------------------------------------------------
-- Skin
---------------------------------------------------------------------------
local skinned = setmetatable({}, { __mode = "k" })   -- Blizzard frame -> parts

local function Accent() return unpack(E.media.accentColor) end

-- Blizzard's minimize button drawn as the fold chevron of EldoUI's
-- windows (down while open, right while folded) that follows its state.
-- Only a texture is added; the click stays Blizzard's own.
local function SkinMinimize(header)
	local button = header and header.MinimizeButton
	if not E:SkinUsable(button) then return end
	local parts = skinned[button]
	if not parts then
		if not Can("skin") then return end
		parts = {}
		parts.chevron = E.UIKit.Chevron(button, "down", 10)
		parts.chevron:SetPoint("CENTER", 0, 0)
		parts.update = function(collapsed)
			local on = Can("skin") and M.db.skinButtons
			local alpha = on and 0 or 1
			for _, texture in ipairs({ button:GetNormalTexture() or false, button:GetPushedTexture() or false, button:GetHighlightTexture() or false }) do
				if texture then texture:SetAlpha(alpha) end
			end
			parts.chevron:SetShown(on and true or false)
			parts.collapsed = collapsed and true or false
			E.UIKit.SetGlyph(parts.chevron, parts.collapsed and "chevron-right" or "chevron-down")
		end
		parts.paint = function()
			if parts.hover then
				parts.chevron:SetVertexColor(E:TokenColor("accent"))
			else
				parts.chevron:SetVertexColor(unpack(E.tokens.text.secondary))
			end
		end
		button:HookScript("OnEnter", function() parts.hover = true parts.paint() end)
		button:HookScript("OnLeave", function() parts.hover = false parts.paint() end)
		hooksecurefunc(header, "SetCollapsed", function(_, collapsed) parts.update(collapsed) end)
		E:RegisterThemed(parts.chevron, parts.paint)
		skinned[button] = parts
	end
	local owner = header:GetParent()
	parts.update(owner and owner.isCollapsed)
	parts.paint()
end

-- Header lines (DESIGN.md §0a rule 4): "fold" centers the section name
-- between two thin accent lines, the look of EldoUI's fold dividers;
-- "under" draws one line under the header. Blizzard's text keeps its
-- size and click; only where it sits changes, and its own anchor comes
-- back when the lines go.
local function SavePoints(region)
	local points = {}
	for index = 1, (region.GetNumPoints and region:GetNumPoints() or 0) do
		points[index] = { region:GetPoint(index) }
	end
	return points
end

local function PlaceHeaderText(header, parts, centered)
	local text = header.Text
	if not (text and text.SetPoint and text.ClearAllPoints) then return end
	if centered and not parts.textPoints then
		parts.textPoints = SavePoints(text)
		text:ClearAllPoints()
		text:SetPoint("CENTER", header, "CENTER", 0, 1)
	elseif not centered and parts.textPoints then
		text:ClearAllPoints()
		for _, point in ipairs(parts.textPoints) do text:SetPoint(unpack(point)) end
		parts.textPoints = nil
	end
end

-- A control another module puts on the tracker's top row, left of
-- Blizzard's fold button (the quest tracker button of Quality of Life).
local headerControl

-- The centered name sits 1 unit above the header's middle line, so every
-- end of both lines uses that same height: the two ends of a line agree.
-- The right line ends before the leftmost control shown on the row.
local function LayoutFoldLines(header, parts)
	local text, left, right = header.Text, parts.left, parts.right
	left:ClearAllPoints()
	right:ClearAllPoints()
	left:SetPoint("LEFT", header, "LEFT", 0, 1)
	left:SetPoint("RIGHT", text, "LEFT", -8, 0)
	right:SetPoint("LEFT", text, "RIGHT", 8, 0)
	local button = header.MinimizeButton
	local tracker = Tracker()
	if headerControl and headerControl:IsShown() and tracker and header == tracker.Header then button = headerControl end
	if button and button.IsShown and button:IsShown() then
		right:SetPoint("RIGHT", button, "LEFT", -6, 1)
	else
		right:SetPoint("RIGHT", header, "RIGHT", 0, 1)
	end
end

-- "fold", "under" or "none": the header lines the settings ask for.
function M.HeaderStyle()
	local db = M.db
	if not (db and db.headerLine) then return "none" end
	return db.headerStyle == "under" and "under" or "fold"
end

local function SkinHeader(header, atlas)
	if not E:SkinUsable(header) then return end
	local on = Can("skin")
	local parts = skinned[header]
	if not parts then
		if not on then return end
		parts = { atlas = atlas }
		parts.line = header:CreateTexture(nil, "ARTWORK")
		parts.line:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 2)
		parts.line:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 2)
		parts.line:SetHeight(E.pixel)
		E:AccentTexture(parts.line, E.tokens.foldLine)
		parts.left = header:CreateTexture(nil, "ARTWORK")
		E:Hairline(parts.left, "h", 1)
		E:AccentTexture(parts.left, E.tokens.foldLine)
		parts.right = header:CreateTexture(nil, "ARTWORK")
		E:Hairline(parts.right, "h", 1)
		E:AccentTexture(parts.right, E.tokens.foldLine)
		skinned[header] = parts
	end
	local background = header.Background
	if background and background.SetAtlas then
		-- The add animation fades Background back in, so the texture itself
		-- is cleared instead of setting its alpha.
		if on then
			background:SetTexture(nil)
		elseif parts.cleared then
			background:SetAtlas(parts.atlas, true)
		end
		parts.cleared = on
	end
	local style = on and M.HeaderStyle() or "none"
	local fold = style == "fold" and header.Text ~= nil
	PlaceHeaderText(header, parts, fold)
	if fold then LayoutFoldLines(header, parts) end
	parts.line:SetShown(style == "under")
	parts.left:SetShown(fold)
	parts.right:SetShown(fold)
	parts.style = style
	local text = header.Text
	if text and text.SetTextColor then
		if on and M.db.accentHeaders then
			text:SetTextColor(E:TokenColor("accent"))
			parts.colored = true
		elseif parts.colored then
			text:SetTextColor(E:TokenColor("gold")) -- Blizzard's gold header color (NORMAL_FONT_COLOR)
			parts.colored = false
		end
	end
	SkinMinimize(header)
end

-- Another module's control on the top row (nil: none): the header lines
-- make room for it.
-- The per-character fold (Quality of Life's button and /eui tracker). Like
-- Hide, the tracker is parked off screen and invisible; Blizzard's own
-- SetCollapsed is never called from EldoUI (see the taint notes above). The
-- spot where the tracker's top right corner was is kept for the button.
function M:SetUserCollapsed(collapsed)
	collapsed = collapsed and true or false
	if (self.userCollapsed or false) == collapsed then return end
	local tracker = Tracker()
	-- Its corner is read only once the game has laid the tracker out (see
	-- the taint notes); otherwise the button keeps its own spot.
	if collapsed and tracker and not self.userCollapsed and E.RectReady(tracker) then
		local right, top = E.PlainCall(tracker.GetRight, tracker), E.PlainCall(tracker.GetTop, tracker)
		local scale = E.PlainCall(tracker.GetEffectiveScale, tracker)
		local parent = UIParent:GetEffectiveScale()
		if type(right) == "number" and type(top) == "number" and type(scale) == "number" and parent > 0 then
			self.foldSpot = { right * scale / parent, top * scale / parent }
		else
			self.foldSpot = nil
		end
	end
	self.userCollapsed = collapsed or nil
	if not collapsed then self.foldSpot = nil end
	if tracker then
		if not collapsed and not Can("move") and not Can("hide") and not Can("replace") and not BoxHidden() then
			Unpin(tracker, true)
		end
		self:ApplyPosition()
		self:UpdateAlpha()
	end
end

-- Where the folded tracker's top right corner was (UIParent units), or nil.
function M:FoldSpot()
	return self.active and self.userCollapsed and self.foldSpot or nil
end

function M:SetHeaderControl(control)
	if headerControl == control then return end
	headerControl = control
	local tracker = Tracker()
	if tracker and tracker.Header then SkinHeader(tracker.Header, HEADER_ATLAS) end
end

local function SkinBar(holder)
	local bar = type(holder) == "table" and holder.Bar
	if not E:SkinUsable(bar) or not bar.SetStatusBarTexture then return end
	local on = Can("skin") and M.db.skinBars
	local parts = skinned[bar]
	if not parts then
		if not on then return end
		local texture = bar:GetStatusBarTexture()
		parts = { texture = texture and texture:GetTexture() }
		parts.bd = CreateFrame("Frame", nil, bar)
		parts.bd:SetPoint("TOPLEFT", -E.pixel, E.pixel)
		parts.bd:SetPoint("BOTTOMRIGHT", E.pixel, -E.pixel)
		parts.bd:SetFrameLevel(math.max(bar:GetFrameLevel() - 1, 0))
		E:SetTemplate(parts.bd, true)
		skinned[bar] = parts
	end
	local alpha = on and 0 or 1
	for _, region in ipairs({ bar.BorderLeft or false, bar.BorderRight or false, bar.BorderMid or false }) do
		if region then region:SetAlpha(alpha) end
	end
	if on then
		bar:SetStatusBarTexture(E.media.statusbar)
	elseif parts.texture then
		bar:SetStatusBarTexture(parts.texture)
	end
	if on and bar.Label and bar.Label.SetFont then E:SetFont(bar.Label, E.tokens.size.label) end
	parts.bd:SetShown(on and true or false)
end

-- Quest item buttons: trimmed icon in a 1 px box. Only regions change; the
-- button itself (its attributes and scripts) is never touched.
local function SkinItemButton(button)
	if not E:SkinUsable(button) or type(button.icon) ~= "table" or not button.GetNormalTexture then return end
	local on = Can("skin") and M.db.skinItems
	local parts = skinned[button]
	if not parts then
		if not on then return end
		parts = {}
		parts.bd = CreateFrame("Frame", nil, button)
		parts.bd:SetPoint("TOPLEFT", -E.pixel, E.pixel)
		parts.bd:SetPoint("BOTTOMRIGHT", E.pixel, -E.pixel)
		parts.bd:SetFrameLevel(math.max(button:GetFrameLevel() - 1, 0))
		E:SetTemplate(parts.bd)
		skinned[button] = parts
	end
	local alpha = on and 0 or 1
	local normal, pushed = button:GetNormalTexture(), button:GetPushedTexture()
	if normal then normal:SetAlpha(alpha) end
	if pushed then pushed:SetAlpha(alpha) end
	if on then
		E:TrimIcon(button.icon)
	else
		button.icon:SetTexCoord(0, 1, 0, 1)
	end
	parts.bd:SetShown(on and true or false)
end

-- Objective counts as value rows. "Boars slain: 3/8" or "3/8 Boars slain"
-- -> "Boars slain", "3/8". Anything else (or secret text) gives nil.
local countParts = setmetatable({}, { __mode = "k" })   -- Blizzard line -> parts

local function SplitCount(text)
	if type(text) ~= "string" or E.Secret(text) then return nil end
	local label, have, need = text:match("^(.-):%s*(%d+)%s*/%s*(%d+)$")
	if not (label and label:find("%S")) then
		have, need, label = text:match("^(%d+)%s*/%s*(%d+)%s+(.-)%s*$")
	end
	if not (label and label:find("%S")) then return nil end
	return label, have .. "/" .. need, tonumber(have) >= tonumber(need)
end

-- Blizzard's own text back on a line EldoUI shortened.
local function RestoreCount(line, parts)
	parts.count:Hide()
	local text = line.Text
	if parts.short and text and text:GetText() == parts.short then text:SetText(parts.full) end
	parts.short, parts.full = nil, nil
end

-- Lines whose count waits for the game's layout: one pass on the next frame.
local CountLine
local countQueue = setmetatable({}, { __mode = "k" })
local countQueued = false
local function QueueCount(line)
	countQueue[line] = true
	if countQueued then return end
	countQueued = true
	C_Timer.After(0, function()
		countQueued = false
		local on = Can("skin") and M.db.valueCounts and true or false
		local lines = {}
		for queued in pairs(countQueue) do lines[#lines + 1] = queued end
		wipe(countQueue)
		for _, queued in ipairs(lines) do
			-- Only a line the game still shows and has laid out by now.
			if queued.IsShown and queued:IsShown() and E.RectReady(queued.Text) then CountLine(queued, on) end
		end
	end)
end

CountLine = function(line, on)
	local text = type(line) == "table" and line.Text
	local parts = countParts[line]
	if not (text and text.GetText) then return end
	if not on then
		if parts then RestoreCount(line, parts) end
		return
	end
	local current = text:GetText()
	-- The layout left this line alone: it still shows what EldoUI set.
	if parts and parts.short and current == parts.short and parts.key == line.objectiveKey then
		parts.count:Show()
		return
	end
	local label, count, done = SplitCount(current)
	if not label then
		if parts then parts.count:Hide() parts.short, parts.full = nil, nil end
		return
	end
	if not parts then
		local fs = line:CreateFontString(nil, "OVERLAY")
		fs:SetJustifyH("RIGHT")
		fs:SetWordWrap(false)
		parts = { count = fs }
		countParts[line] = parts
	end
	local fs = parts.count
	local font, size, flags = text:GetFont()
	if font then fs:SetFont(font, size, flags) end
	fs:ClearAllPoints()
	fs:SetPoint("TOPRIGHT", line, "TOPRIGHT", 0, 0)
	fs:SetText(count)
	if done then fs:SetTextColor(text:GetTextColor()) else fs:SetTextColor(E:TokenColor("accent")) end
	-- The line's width is read only once the game has laid it out (see the
	-- taint notes); until then the line keeps the game's text, and the
	-- count moves out on the next frame.
	if not E.RectReady(text) then
		fs:Hide()
		parts.short, parts.full = nil, nil
		QueueCount(line)
		return
	end
	-- Only when the text and the count fit side by side on one line.
	local room = text:GetWidth() - fs:GetStringWidth() - 6
	text:SetText(label)
	if room <= 0 or text:GetStringWidth() > room then
		text:SetText(current)
		fs:Hide()
		parts.short, parts.full = nil, nil
		return
	end
	parts.short, parts.full, parts.key = label, current, line.objectiveKey
	fs:Show()
end

local function CountModule(module)
	local on = Can("skin") and M.db.valueCounts and true or false
	if not on and not next(countParts) then return end
	if type(module.usedBlocks) ~= "table" then return end
	for _, blocks in pairs(module.usedBlocks) do
		if type(blocks) == "table" then
			for _, block in pairs(blocks) do
				if type(block) == "table" and type(block.usedLines) == "table" then
					for _, line in pairs(block.usedLines) do CountLine(line, on) end
				end
			end
		end
	end
end
M.SplitCount = SplitCount

-- One tracker module (quests, achievements, scenario ...): header, bars and
-- item buttons. Runs after each of its layouts, so new rows get skinned.
local function SkinModule(module)
	if not E:SkinUsable(module) then return end
	CountModule(module)
	if not Can("skin") and not next(skinned) then return end
	SkinHeader(module.Header, MODULE_HEADER_ATLAS)
	for _, list in ipairs({ module.usedProgressBars or false, module.usedTimerBars or false }) do
		if type(list) == "table" then
			for _, bar in pairs(list) do SkinBar(bar) end
		end
	end
	if type(module.usedRightEdgeFrames) == "table" then
		for _, frame in pairs(module.usedRightEdgeFrames) do SkinItemButton(frame) end
	end
end

local hookedModules = setmetatable({}, { __mode = "k" })

local function HookModule(module)
	if not E:SkinUsable(module) or hookedModules[module] or type(module.EndLayout) ~= "function" then return end
	hookedModules[module] = true
	hooksecurefunc(module, "EndLayout", SkinModule)
end

function M:UpdateBackdrop()
	local tracker = Tracker()
	local kind = Can("skin") and self.db.backdrop or "none"
	if kind ~= "none" and not self.backdrop then
		local bd = CreateFrame("Frame", nil, tracker)
		bd:SetPoint("TOPLEFT", tracker, "TOPLEFT", -8, 4)
		bd:SetPoint("BOTTOMRIGHT", tracker, "BOTTOMRIGHT", 4, -4)
		bd:SetFrameLevel(math.max(tracker:GetFrameLevel() - 1, 0))
		self.backdrop = bd
	end
	if self.backdrop then
		if kind ~= "none" then E:SetPanelTemplate(self.backdrop, kind == "transparent") end
		self.backdrop:SetShown(kind ~= "none")
	end
	-- Blizzard's own background (Edit Mode opacity) gives way to EldoUI's,
	-- and comes back at Blizzard's opacity.
	local nineSlice = tracker.NineSlice
	if nineSlice and kind ~= "none" then
		nineSlice:SetAlpha(0)
		self.nineSliceHidden = true
	elseif nineSlice and self.nineSliceHidden then
		local manager = _G.ObjectiveTrackerManager
		nineSlice:SetAlpha(manager and tonumber(manager.backgroundAlpha) or 0)
		self.nineSliceHidden = false
	end
end

-- Skin on, or put every skinned part back when the switch went off.
function M:ApplySkin()
	local tracker = Tracker()
	SkinHeader(tracker.Header, HEADER_ATLAS)
	if type(tracker.modules) == "table" then
		for _, module in ipairs(tracker.modules) do
			if Can("skin") then HookModule(module) end
			SkinModule(module)
		end
	end
	self:UpdateBackdrop()
	self:ApplyFonts()
end

---------------------------------------------------------------------------
-- Place, hide and fade
---------------------------------------------------------------------------
-- The tracker's instance type ticks decide what counts as an instance for
-- the visibility rules (In instances: Hide, Fade, ...).
local function InTrackedInstance()
	local inInstance, kind = IsInInstance()
	if issecretvalue and issecretvalue(inInstance) then return false end
	local types = M.db and M.db.instanceTypes
	return inInstance and kind and types and types[kind] and true or false
end

-- During a boss fight the boss mod addon can hide the tracker itself (its
-- own option). While it does, the visibility rule keeps the tracker hidden
-- too; after the fight the rule decides again.
local function BossModHides()
	if not (E.BossModHidesTracker and E:BossModHidesTracker()) then return false end
	local fighting = IsEncounterInProgress and IsEncounterInProgress()
	return E.Plain(fighting) == true
end
M.BossModHides = BossModHides

-- v0.6 had its own fade settings (in combat / in instances: keep, see-
-- through or invisible; see-through until mouse-over). They become the
-- shared visibility block once: one faded alpha (the lowest of the old
-- ones), "Out of combat" or "Mouse over" as the rule, and "Fade in
-- instances" for the instance setting. Mouse-over always shows it now.
local LEGACY_KEYS = { "combat", "combatAlpha", "instance", "instanceAlpha", "hoverShow", "idleFade", "idleAlpha" }

function M:MigrateVisibility()
	local db = self.db
	if type(db) ~= "table" then return end
	local found = false
	for _, key in ipairs(LEGACY_KEYS) do
		if db[key] ~= nil then found = true break end
	end
	if not found then return end
	local combat, instance, idle = db.combat or "keep", db.instance or "keep", db.idleFade == true
	local alphas = {}
	local function Add(mode, alpha, default)
		if mode == "hide" then
			alphas[#alphas + 1] = 0
		elseif mode == "fade" then
			alphas[#alphas + 1] = tonumber(alpha) or default
		end
	end
	Add(combat, db.combatAlpha, 0.25)
	Add(instance, db.instanceAlpha, 0.25)
	Add(idle and "fade" or "keep", db.idleAlpha, 0.5)
	local faded = 0
	for index, alpha in ipairs(alphas) do
		if index == 1 or alpha < faded then faded = alpha end
	end
	local show = "always"
	if idle then
		show = "mouseover"
	elseif combat == "fade" or combat == "hide" then
		show = "nocombat"
	end
	if show ~= "always" or instance ~= "keep" then
		db.visibility = E:VisibilityDefaults({ preset = "custom", show = show, instance = instance ~= "keep" and "fade" or "same",
			fadedAlpha = math.max(0, math.min(1, faded)) })
		E:NormalizeVisibility(db.visibility)
	end
	for _, key in ipairs(LEGACY_KEYS) do db[key] = nil end
end

-- Visibility: the shared rules drive the tracker's alpha while the
-- Improve switch is on. Alpha only: the tracker is never folded or hidden,
-- so its quest item buttons keep working in combat. With the Hide switch
-- or a hidden box the tracker is parked off screen and invisible
-- (ApplyPosition); the alpha follows at once, also in combat.
function M:UpdateAlpha()
	self:UpdateQuestieAlpha()
	local tracker = Tracker()
	if not tracker then return end
	self:MigrateVisibility()
	local hidden = self.active and (E:BlizzardHidden(ELEMENT) or BoxHidden() or self.userCollapsed)
	if self.active and not hidden and Allowed("improve") then
		if type(self.db.visibility) ~= "table" then self.db.visibility = E:VisibilityDefaults() end
		E:AttachVisibility(tracker, self.db.visibility, { inInstance = InTrackedInstance, forceHide = BossModHides })
		self.alphaSet = true
		return
	end
	if E:IsVisibilityAttached(tracker) then
		E:DetachVisibility(tracker)
		self.alphaSet = false
	end
	if hidden then
		tracker:SetAlpha(0)
		self.alphaSet = true
	elseif self.alphaSet then
		tracker:SetAlpha(1)
		self.alphaSet = false
	end
end

function M:ApplyPosition()
	local tracker = Tracker()
	local boxHidden = BoxHidden()
	local hidden = Can("hide") or Can("replace") or boxHidden or (self.active and self.userCollapsed)
	local move = Can("move")
	if move then
		self:CreateHolder()
		self:SizeHolder()
		if not boxHidden then self.holder:Show() end
		self.mover:Show()
	elseif self.mover then
		self.holder:Hide()
		self.mover:Hide()
	end
	-- SetScaleBase on the Edit Mode system: Edit Mode's override never runs.
	local Keep = E.BlizzardKeep
	if move and not hidden then
		Keep.SetScale(tracker, self.db.scale or 1)
		self.scaled = true
	elseif self.scaled then
		Keep.SetScale(tracker, 1)
		self.scaled = false
	end
	if hidden then
		Pin(tracker, AnchorOffscreen)
	elseif move then
		Pin(tracker, AnchorToHolder, { holder = self.holder, scale = function() return M.db.scale or 1 end })
	else
		Unpin(tracker)
	end
end

---------------------------------------------------------------------------
-- Questie: Questie draws its own tracker (Questie_BaseFrame). EldoUI
-- gives it the EldoUI backdrop and puts it on the EldoUI_Quests mover.
-- Questie's own drag is overridden while "Put Questie's tracker on the
-- mover" is on. Questie's frames belong to an addon, so taint is no concern.
---------------------------------------------------------------------------
local questieBusy = false

local function QuestieAnchor() return "TOPRIGHT", M.holder, "TOPRIGHT", 0, 0 end

local function QuestieFrame()
	local frame = _G.Questie_BaseFrame
	return E:SkinUsable(frame) and frame or nil
end

function M:QuestieLoaded()
	return C_AddOns.IsAddOnLoaded("Questie")
end

-- The Questie rows show only while Questie is loaded.
local function NoQuestie() return not M:QuestieLoaded() end

local function ClearQuestieBackdrop(frame)
	if questieBusy or not frame.SetBackdropColor then return end
	questieBusy = true
	frame:SetBackdropColor(0, 0, 0, 0)
	if frame.SetBackdropBorderColor then frame:SetBackdropBorderColor(0, 0, 0, 0) end
	questieBusy = false
end

function M:ApplyQuestie()
	local base = QuestieFrame()
	if not base then return end
	-- The quest addon can build its tracker in combat (the wait below finds
	-- it then); sizing the holder and pinning the tracker wait for the end
	-- of combat.
	if InCombatLockdown() then
		E:RunOutOfCombat(function() M:ApplyQuestie() end, "objectiveTracker:questTracker")
		return
	end
	local skin = Can("skin") and self.db.questie.skin
	if skin and not self.questieBackdrop then
		local bd = CreateFrame("Frame", nil, base)
		bd:SetAllPoints()
		bd:SetFrameLevel(base:GetFrameLevel())
		self.questieBackdrop = bd
		-- Questie re-colors its background when it fades; keep it clear.
		if base.SetBackdropColor then
			hooksecurefunc(base, "SetBackdropColor", function(frame)
				if M.questieBackdrop and M.questieBackdrop:IsShown() then ClearQuestieBackdrop(frame) end
			end)
		end
	end
	if self.questieBackdrop then
		self.questieBackdrop:SetShown(skin and true or false)
		if skin then
			E:SetPanelTemplate(self.questieBackdrop, true)
			ClearQuestieBackdrop(base)
		end
	end
	if BoxHidden() then
		Pin(base, AnchorOffscreen)
	elseif Can("move") and self.db.questie.move then
		self:CreateHolder()
		self:SizeHolder()
		Pin(base, QuestieAnchor)
	else
		Unpin(base)
	end
	self:UpdateQuestieAlpha()
end

-- Questie's tracker is invisible while the Quest Tracker box is hidden.
function M:UpdateQuestieAlpha()
	local base = QuestieFrame()
	if not base then return end
	if BoxHidden() then
		base:SetAlpha(0)
		self.questieHidden = true
	elseif self.questieHidden then
		base:SetAlpha(1)
		self.questieHidden = false
	end
end

-- Questie's tracker while it sits on the holder ("Put Questie's tracker on
-- the mover"); it sizes itself, so a frame docked under it reads its live
-- bottom edge instead of asking for a band.
function M:QuestieInColumn()
	local base = QuestieFrame()
	if base and pinned[base] == QuestieAnchor then return base end
	return nil
end

-- The waits below run on the shared ticker and end with the module.
local QUESTIE_TICK = "ObjectiveTracker:questie"
local BIND_TICK = "ObjectiveTracker:bindKey"
local RANGE_TICK = "ObjectiveTracker:itemRange"

-- Questie builds its tracker a while after login; look for it a few times.
function M:WatchQuestie()
	if E.Ticker:IsSubscribed(QUESTIE_TICK) or not self:QuestieLoaded() then return end
	if QuestieFrame() then
		self:ApplyQuestie()
		return
	end
	local tries = 0
	E.Ticker:Subscribe(QUESTIE_TICK, 2, function()
		tries = tries + 1
		if QuestieFrame() or tries >= 30 then
			E.Ticker:Unsubscribe(QUESTIE_TICK)
			if QuestieFrame() then M:ApplyQuestie() end
		end
	end, M)
end

---------------------------------------------------------------------------
-- Quest item key
---------------------------------------------------------------------------
local QUEST_ITEM = "EldoUI_QuestItemButton"
local QUEST_ITEM_COMMAND = "CLICK " .. QUEST_ITEM .. ":LeftButton"
local QUEST_ITEM_PLACEHOLDER = 134400 -- the game's question-mark icon

E:RegisterGlowUser("questItem", {
	title = "Quest item button",
	desc = "The quest item button glows for a few seconds when a new quest item lands on it.",
	order = 60,
	button = true,
})

-- The quest whose item the button holds: { logIndex, questID, link, texture,
-- charges } or nil. Only plain values from the quest log; nothing secret.
local function ItemOfQuest(questID, allowComplete)
	if not questID or questID == 0 or not C_QuestLog.GetLogIndexForQuestID then return nil end
	local logIndex = C_QuestLog.GetLogIndexForQuestID(questID)
	if not logIndex or not GetQuestLogSpecialItemInfo then return nil end
	local link, texture, charges, showWhenComplete = GetQuestLogSpecialItemInfo(logIndex)
	if not link then return nil end
	local complete = C_QuestLog.IsComplete and C_QuestLog.IsComplete(questID)
	if complete and not (showWhenComplete or allowComplete) then return nil end
	return { logIndex = logIndex, questID = questID, link = link, texture = texture, charges = charges }
end

function M:FindQuestItem()
	local db = self.db.questItem
	if db.source == "super" and C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID then
		local found = ItemOfQuest(E.PlainCall(C_SuperTrack.GetSuperTrackedQuestID), db.complete)
		if found then return found end
	end
	for _, questID in ipairs(self:WatchedQuests()) do
		local found = ItemOfQuest(questID, db.complete)
		if found then return found end
	end
end

local function ItemString(link)
	local id = type(link) == "string" and link:match("item:(%d+)")
	return id and ("item:" .. id) or link
end

local function KeyText()
	local key = GetBindingKey(QUEST_ITEM_COMMAND)
	if not key then return nil end
	return GetBindingText(key, "KEY_", true)
end

function M:CreateQuestItemButton()
	if self.questItemButton then return end
	local holder = CreateFrame("Frame", "EldoUI_QuestItem", UIParent)
	holder:SetSize(36, 36)
	self.questItemHolder = holder
	local previous = E.currentModule
	E.currentModule = self
	-- Left of the quest tracker's top (placement.md 2.6).
	self.questItemMover = E:CreateMover(holder, "EldoUI_QuestItem", L["Quest Item Button"], { "TOPRIGHT", "UIParent", "TOPRIGHT", -360, -358 })
	E.currentModule = previous

	local button = CreateFrame("Button", QUEST_ITEM, holder, "SecureActionButtonTemplate")
	button:SetAllPoints(holder)
	-- Down and up: a key acts on the press or the release as the game's
	-- "cast on key down" setting says; a mouse click acts on the release.
	button:RegisterForClicks("AnyUp", "AnyDown")
	button:SetAttribute("type", "item")
	E:SetTemplate(button)
	button.icon = button:CreateTexture(nil, "ARTWORK")
	button.icon:SetPoint("TOPLEFT", E.pixel, -E.pixel)
	button.icon:SetPoint("BOTTOMRIGHT", -E.pixel, E.pixel)
	E:TrimIcon(button.icon)
	button.cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
	button.cooldown:SetAllPoints(button.icon)
	if E.ApplyCooldownFont then E:ApplyCooldownFont(button.cooldown) end
	button.hotkey = E:CreateText(button, E.tokens.size.small, "RIGHT", "OVERLAY")
	button.hotkey:SetPoint("TOPRIGHT", -2, -3)
	button.count = E:CreateText(button, E.tokens.size.label, "RIGHT", "OVERLAY")
	button.count:SetPoint("BOTTOMRIGHT", -2, 3)
	button.highlight = button:CreateTexture(nil, "HIGHLIGHT")
	button.highlight:SetAllPoints(button.icon)
	E:AccentTexture(button.highlight, 0.25)
	button:SetScript("OnEnter", function(owner)
		if E.FrameCheck(GameTooltip, "IsForbidden") then return end
		GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
		local current = M.questItem
		if current and GameTooltip.SetQuestLogSpecialItem then
			GameTooltip:SetQuestLogSpecialItem(current.logIndex)
		else
			E.UIKit.TipTitle(GameTooltip, L["Quest item button"])
			E.UIKit.TipText(GameTooltip, L["Holds the item of your tracked quest. Bind a key to it in keybind mode."])
		end
		local key = KeyText()
		GameTooltip:AddLine(key and L["Key: %s"]:format(key) or L["No key bound (EldoUI > Quest Tracker > Quest item)"], E:TokenColor("secondary"))
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function() if not E.FrameCheck(GameTooltip, "IsForbidden") then GameTooltip:Hide() end end)
	button:Hide()
	self.questItemButton = button
	E:RegisterKeybindButton(button, QUEST_ITEM_COMMAND)

	-- Range color on the key text: the game's own answer for the item,
	-- five times a second while the button shows.
	local function Range()
		local current = M.questItem
		if not (current and M.db.questItem.range and IsQuestLogSpecialItemInRange) then
			button.hotkey:SetTextColor(unpack(E.media.text.body))
			return
		end
		local valid = IsQuestLogSpecialItemInRange(current.logIndex)
		if issecretvalue and issecretvalue(valid) then return end
		if valid == 0 then
			button.hotkey:SetTextColor(E:TokenColor("bad"))
		else
			button.hotkey:SetTextColor(unpack(E.media.text.body))
		end
	end
	button:HookScript("OnShow", function()
		if M.active then E.Ticker:Subscribe(RANGE_TICK, 0.2, Range, M) end
	end)
	button:HookScript("OnHide", function() E.Ticker:Unsubscribe(RANGE_TICK) end)
end

-- Cooldown and count: shown as the game gives them (cooldown values go
-- straight to the cooldown widget).
function M:UpdateQuestItemState()
	local button, current = self.questItemButton, self.questItem
	if not button then return end
	local db = self.db.questItem
	if current and GetQuestLogSpecialItemCooldown then
		local start, duration, enable = GetQuestLogSpecialItemCooldown(current.logIndex)
		if start then
			pcall(CooldownFrame_Set or function(cd, s, d) cd:SetCooldown(s, d) end, button.cooldown, start, duration, enable)
		else
			button.cooldown:Clear()
		end
	else
		button.cooldown:Clear()
	end
	local charges = current and current.charges
	if db.count and not (issecretvalue and issecretvalue(charges)) and charges and charges > 1 then
		button.count:SetText(charges)
	else
		button.count:SetText("")
	end
	local key = db.hotkey and KeyText() or nil
	button.hotkey:SetText(key or "")
end

-- Attributes and shown state: out of combat only.
function M:ApplyQuestItem()
	local db = self.db.questItem
	local on = self.active and db.enabled
	if not on then
		if self.questItemButton then
			E:RunOutOfCombat(function()
				if M.active and M.db.questItem.enabled then return end
				M.questItemButton:Hide()
				M.questItemButton:SetAttribute("item", nil)
				M.questItemHolder:Hide()
				M.questItemMover:Hide()
				E:UnregisterKeybindButton(M.questItemButton)
			end)
		end
		self.questItem = nil
		return
	end
	if InCombatLockdown() then
		if not self.questItemQueued then
			self.questItemQueued = true
			E:RunOutOfCombat(function()
				M.questItemQueued = false
				M:ApplyQuestItem()
			end)
		end
		return
	end
	self:CreateQuestItemButton()
	local button, holder = self.questItemButton, self.questItemHolder
	E:RegisterKeybindButton(button, QUEST_ITEM_COMMAND)
	holder:Show()
	self.questItemMover:Show()
	holder:SetSize(db.size, db.size)
	local found = self:FindQuestItem()
	local previousLink = self.questItem and self.questItem.link
	self.questItem = found
	local binding = self.questItemBinding or E:IsKeybindMode()
	if found then
		button:SetAttribute("item", ItemString(found.link))
		button.icon:SetTexture(found.texture or QUEST_ITEM_PLACEHOLDER)
		button.icon:SetDesaturated(false)
	else
		button:SetAttribute("item", nil)
		button.icon:SetTexture(QUEST_ITEM_PLACEHOLDER)
		button.icon:SetDesaturated(true)
	end
	-- "Key only": invisible and click-through, but still there for the key.
	local visible = db.showButton or binding
	button:SetAlpha(visible and 1 or 0)
	button:EnableMouse(visible and true or false)
	button:SetShown((found or binding) and true or false)
	E:SetTemplate(button)
	self:UpdateQuestItemState()
	-- A new item (not the one already there at login) glows for a moment.
	if found and found.link ~= previousLink and self.questItemSeen and db.glow and visible then
		E:ShowUserGlow(button, "questItem")
		C_Timer.After(3, function() E:HideGlow(button) end)
	end
	self.questItemSeen = true
end

-- Quest log, watch list and bag changes come in bursts; one update a frame.
function M:QueueQuestItem()
	if self.questItemPending then return end
	self.questItemPending = true
	C_Timer.After(0.1, function()
		M.questItemPending = false
		M:ApplyQuestItem()
	end)
end

-- Keybind mode with the button forced visible until the mode closes.
function M:BindQuestItemKey()
	if not (self.active and self.db.questItem.enabled) then
		E:Print(L["Turn on the quest item button first."])
		return
	end
	if InCombatLockdown() then
		E:Print(L["Keys can't be bound in combat."])
		return
	end
	self.questItemBinding = true
	self:ApplyQuestItem()
	E:ToggleKeybindMode(true)
	E:KeybindStatus(L["Hover the quest item button and press a key, then click Save."])
	E.Ticker:Subscribe(BIND_TICK, 0.5, function()
		if E:IsKeybindMode() then return end
		E.Ticker:Unsubscribe(BIND_TICK)
		M.questItemBinding = false
		M:ApplyQuestItem()
	end, M)
end

local QUEST_ITEM_EVENTS = { "QUEST_LOG_UPDATE", "QUEST_WATCH_LIST_CHANGED", "SUPER_TRACKING_CHANGED",
	"BAG_UPDATE_DELAYED", "UPDATE_BINDINGS" }

---------------------------------------------------------------------------
-- Apply / undo
---------------------------------------------------------------------------
-- Re-reads every setting and switch. With the element switched off (or the
-- module off) each step puts back what it changed, so this is also the undo.
-- Moves Blizzard only redoes on its next layout ask for a /reload.
local function ApplyFoldOwner()
	local qol = E:GetModule("QoL")
	if qol and qol.active and qol.ApplyTracker then qol:ApplyTracker() end
end

function M:Refresh()
	if not Tracker() then
		if self.active then
			E:OnBlizzardAddOn("Blizzard_ObjectiveTracker", function() if Tracker() then M:Refresh() end end)
		end
		return
	end
	if Can() then self:HookTracker() end
	if self.active then ApplyFoldOwner() end
	self:ApplyPosition()
	self:ApplySkin()
	self:UpdateAlpha()
	self:ApplyQuestie()
end

function M:HookTracker()
	if self.trackerHooked then return end
	local tracker = Tracker()
	self.trackerHooked = true
	if type(tracker.AddModule) == "function" then
		hooksecurefunc(tracker, "AddModule", function(_, module)
			HookModule(module)
		end)
	end
	-- Blizzard's text size setting swaps the font objects; put EldoUI's back.
	local manager = _G.ObjectiveTrackerManager
	if manager and type(manager.SetTextSize) == "function" then
		hooksecurefunc(manager, "SetTextSize", function()
			SaveBlizzardFonts()
			M.fontsSet = false
			if Can("skin") then M:ApplyFonts() end
		end)
	end
end

local function BossFightChanged()
	local tracker = Tracker()
	if tracker and E:IsVisibilityAttached(tracker) then E:UpdateVisibility(tracker) end
end

-- Combat, zone and the other conditions are followed by Core/Visibility.lua.
local EVENTS = {
	PLAYER_ENTERING_WORLD = function()
		M:UpdateAlpha()
		M:WatchQuestie()
	end,
	ENCOUNTER_START = BossFightChanged,
	ENCOUNTER_END = BossFightChanged,
}

function M:OnInitialize()
	self:MigrateVisibility()
	E:RegisterBlizzardHandler(ELEMENT, {
		owner = "ObjectiveTracker",
		apply = function() M:Refresh() end,
		undo = function() M:Refresh() end,
		reload = { skin = true, move = true, hide = true, replace = true },
		install = { skin = true, move = true, improve = true },
	})
	-- Hide or Show on the box: invisible or back at once, moved out of combat.
	E:RegisterHideListener(function(key)
		if key ~= nil and key ~= BOX then return end
		M:UpdateAlpha()
		if M.active or M.holder then E:RunOutOfCombat(function() M:Refresh() end, "objectiveTracker:hide") end
	end)
end

function M:OnEnable()
	for event, handler in pairs(EVENTS) do self:RegisterEvent(event, handler) end
	for _, event in ipairs(QUEST_ITEM_EVENTS) do
		self:RegisterEvent(event, function() M:QueueQuestItem() end)
	end
	self:RegisterEvent("BAG_UPDATE_COOLDOWN", function() M:UpdateQuestItemState() end)
	self:QueueQuestItem()
	E:OnBlizzardAddOn("Questie", function() M:WatchQuestie() end)
	E:RunOutOfCombat(function()
		if M.active then M:Refresh() end
	end, "objectiveTracker:foldOwner")
end

function M:OnDisable()
	-- The Questie watcher, the quest item key wait and the range color
	-- stop with the module.
	E.Ticker:UnsubscribeOwner(M)
	self.questItemBinding = false
	for event in pairs(EVENTS) do self:UnregisterEvent(event) end
	for _, event in ipairs(QUEST_ITEM_EVENTS) do self:UnregisterEvent(event) end
	self:UnregisterEvent("BAG_UPDATE_COOLDOWN")
	self:ApplyQuestItem()
	self:UpdateAlpha() -- alpha is safe in combat: full again at once
	-- Give QoL the frame back on its last native points before it fades it.
	E:RunOutOfCombat(function()
		if M.active then return end
		if M.userCollapsed then
			Unpin(Tracker(), true)
			M.userCollapsed, M.foldSpot = nil, nil
		end
		M:Refresh()
		ApplyFoldOwner()
	end, "objectiveTracker:foldOwner")
end

function M:OnProfileChanged()
	self:UpdateAlpha() -- alpha and the visibility rules follow at once, also in combat
	if self.active then E:RunOutOfCombat(function() M:Refresh() end) end
	self:ApplyQuestItem()
end

---------------------------------------------------------------------------
-- Watched quests in the game's watch-list order
---------------------------------------------------------------------------
local function IsQuestID(value)
	return type(value) == "number" and value > 0 and value < math.huge and value % 1 == 0
end

function M:WatchedQuests()
	local list = {}
	local log = C_QuestLog
	if not log then return list end
	local watchConsts = Constants and Constants.QuestWatchConsts
	local limit = watchConsts and watchConsts.MAX_QUEST_WATCHES or 25
	local count = E.PlainCall(log.GetNumQuestWatches)
	if type(count) ~= "number" or count < 0 or count > limit or count % 1 ~= 0 then return list end
	local seen = {}
	for index = 1, count do
		local questID = E.PlainCall(log.GetQuestIDForQuestWatchIndex, index)
		if IsQuestID(questID) and not seen[questID] then
			list[#list + 1] = questID
			seen[questID] = true
		end
	end
	return list
end

-- Only a binding calls this. Selecting the native focus also refreshes the
-- quest item through SUPER_TRACKING_CHANGED, as when the player uses the map.
function M:CycleWatchedQuest(direction)
	local tracking = C_SuperTrack
	if not (tracking and tracking.GetSuperTrackedQuestID and tracking.SetSuperTrackedQuestID) then return end
	local quests = self:WatchedQuests()
	if #quests == 0 then return end
	local ok, current = pcall(tracking.GetSuperTrackedQuestID)
	if not ok or E.Secret(current) or (current ~= nil and current ~= 0 and not IsQuestID(current)) then return end
	local nextIndex = direction > 0 and 1 or #quests
	for index, questID in ipairs(quests) do
		if questID == current then
			nextIndex = (index + direction - 1) % #quests + 1
			break
		end
	end
	local nextQuest = quests[nextIndex]
	if nextQuest ~= current then pcall(tracking.SetSuperTrackedQuestID, nextQuest) end
end

-- Only from the player's click on the options page, after a question, and
-- out of combat. Quests stay in the log.
function M:UntrackAllQuests()
	local log = C_QuestLog
	if not (log and log.RemoveQuestWatch) then return false end
	E:RunOutOfCombat(function()
		-- Read the list first: removing a watch shifts the indexes.
		for _, questID in ipairs(M:WatchedQuests()) do pcall(log.RemoveQuestWatch, questID) end
	end)
	return true
end

function M:ConfirmUntrackAll()
	local count = #self:WatchedQuests()
	if count == 0 then
		if E.ConfigNotice then E:ConfigNotice(L["No quest is tracked."]) end
		return false
	end
	E:ShowConfirm({ key = "ELDOUI_TRACKER_UNTRACK", title = L["Untrack all quests"],
		text = E:Plural(count, "Stop tracking %d quest? It stays in your quest log.", "Stop tracking all %d quests? They stay in your quest log."):format(count),
		accept = L["Untrack"], cancel = E:GameText(CANCEL, L["Cancel"]), onAccept = function() M:UntrackAllQuests() end })
	return true
end

---------------------------------------------------------------------------
-- Options
---------------------------------------------------------------------------
local function Off(action)
	return function() return not Allowed(action) end
end

-- The instance type ticks matter only while an instance setting is on.
local function NoInstanceRule()
	if not Allowed("improve") then return true end
	local block = M.db and M.db.visibility
	if not (type(block) == "table" and block.show ~= "never") then return true end
	local mode = E:VisibilityInstanceMode(block)
	return mode == "same" or (mode == "show" and block.show == "always")
end

-- While the tracker is hidden (its Hide switch, or its box hidden in move
-- mode) the rules have nothing to fade: the rows stay in view, grayed, and
-- say why.
local function TrackerHidden()
	if M.active and (E:BlizzardHidden(ELEMENT) or BoxHidden()) then
		return L["The tracker is hidden (Hide switch or its box in move mode), so these rules apply once it shows again."]
	end
end

M.options = {
	{ type = "tab", label = "General" },
	{ type = "description", label = "These work while Blizzard UI > Objective / quest tracker is on. Each group below follows one of its switches." },
	{ type = "execute", label = "Open Blizzard UI switches", desc = "Open the Blizzard UI page to switch the tracker's Skin, Move, Hide and Improve on or off.",
		func = function() E:ToggleConfig("blizzard") end },
	{ type = "header", label = "Size and place (Move and scale)" },
	{ type = "description", label = "Needs Move and scale on the Blizzard UI page. The tracker then sits on the \"Quest tracker\" mover, and Edit Mode no longer moves it.", hidden = function() return Allowed("move") end },
	{ type = "range", unit = "px", key = "height", label = "Height", desc = "How tall the tracker may grow. Quests that don't fit are cut off, as in Blizzard's tracker.", min = 160, max = 900, step = 10, hidden = Off("move") },
	{ type = "range", percent = true, key = "scale", label = "Scale", desc = "Size of the whole tracker.", min = 0.6, max = 1.5, step = 0.05, hidden = Off("move") },
	{ type = "header", label = "Collapse" },
	{ type = "description", label = "Blizzard's -/+ buttons fold the tracker and its sections. Quality of Life adds a button and /eui tracker that remember it per character." },
	{ type = "execute", label = "Quest tracker button", desc = "Open Quality of Life, where the per-character fold button for the tracker is switched on.",
		func = function() E:ToggleConfig("module:QoL") end },
	{ type = "header", label = "Tracked quests" },
	{ type = "execute", label = "Untrack all quests", desc = "Stops tracking every quest, after a question. The quests stay in your quest log; track them again from the log. Works out of combat.",
		func = function() M:ConfirmUntrackAll() end },

	{ type = "tab", label = "Look" },
	{ type = "description", label = "Turn on Skin on the Blizzard UI page to use these.", hidden = function() return Allowed("skin") end },
	{ type = "header", label = "Text" },
	{ type = "toggle", key = "font", label = "EldoUI font", desc = "Tracker text in the EldoUI font with its outline. Off keeps Blizzard's font.", hidden = Off("skin") },
	{ type = "range", key = "fontSize", label = "Text size", desc = "Size of quest and objective lines in the EldoUI font. Game keeps Blizzard's size (Edit Mode setting).", min = 0, max = 20, step = 1, zeroText = "Game", dependsOn = "font", hidden = Off("skin") },
	{ type = "range", key = "headerSize", label = "Header size", desc = "Size of the section and quest titles in the EldoUI font. Auto is two sizes larger than the lines.", min = 0, max = 22, step = 1, zeroText = "Auto", dependsOn = "font", hidden = Off("skin") },
	{ type = "toggle", key = "valueCounts", label = "Counts on the right", desc = "An objective's count (3/8) sits at the right end of its line in the accent color. Lines too long for both keep Blizzard's text.", hidden = Off("skin") },
	{ less = true, type = "toggle", key = "accentHeaders", label = "Accent-colored headers", desc = "Section headers (Quests, Achievements ...) in the accent color.", hidden = Off("skin") },
	{ type = "header", label = "Frame" },
	{ type = "select", key = "backdrop", label = "Background", desc = "A panel behind the tracker in the EldoUI art style. None keeps Blizzard's background (opacity from Edit Mode).",
		values = { none = "Blizzard's", transparent = "See-through panel", panel = "Solid panel" }, hidden = Off("skin") },
	{ type = "toggle", key = "headerLine", label = "Header lines", desc = "Thin accent lines on each section header instead of Blizzard's header art.", hidden = Off("skin") },
	{ type = "select", key = "headerStyle", label = "Header line style", desc = "Beside the name: the name sits centered between two lines, like the sections of EldoUI's windows. Under the name: one line under the header.",
		values = { fold = "Beside the name", under = "Under the name" }, order = { "fold", "under" }, dependsOn = "headerLine", hidden = Off("skin") },
	{ type = "toggle", key = "skinButtons", label = "Flat fold arrows", desc = "Blizzard's collapse buttons drawn as a small arrow: down while a section is open, right while it is folded. The click stays Blizzard's.", hidden = Off("skin") },
	{ type = "toggle", key = "skinBars", label = "Flat progress bars", desc = "Progress and timer bars with the EldoUI bar texture and a 1 px border.", hidden = Off("skin") },
	{ type = "toggle", key = "skinItems", label = "Quest item buttons", desc = "Quest item buttons with a trimmed icon and a 1 px border. The button still works the same.", hidden = Off("skin") },

	{ type = "tab", label = "Behavior" },
	{ type = "description", label = "Turn on Improve on the Blizzard UI page to use these.", hidden = function() return Allowed("improve") end },
	{ type = "description", label = "The tracker turns see-through or invisible but is never hidden, so quest item buttons keep working in combat. Hover it to see it fully.", hidden = Off("improve") },
}
for _, row in ipairs(E:VisibilityOptions("visibility", { label = "Visibility", hidden = Off("improve"), disabled = TrackerHidden,
	instanceText = Key("the instance types checked under Instances"), db = function() return M.db end })) do
	table.insert(M.options, row)
end
-- Instance types, by the kind IsInInstance() returns (read in
-- InTrackedInstance through instanceTypes[kind]).
table.insert(M.options, { type = "header", label = "Instances", hidden = NoInstanceRule })
table.insert(M.options, { type = "description", label = "Which instances count for the instance settings (the gear button next to Show).", hidden = NoInstanceRule })
for _, kind in ipairs({
	{ "party", "Dungeons", E.Key("Five-player dungeons.") },
	{ "raid", "Raids", E.Key("Raid instances.") },
	{ "pvp", "Battlegrounds", E.Key("Battlegrounds and their queued matches.") },
	{ "arena", E.Key("Arenas"), E.Key("Rated and skirmish arena matches.") },
	{ "scenario", E.Key("Scenarios"), E.Key("Scenarios and other instanced events that the game calls a scenario.") },
}) do
	table.insert(M.options, { type = "toggle", key = "instanceTypes." .. kind[1], label = kind[2], desc = kind[3], hidden = NoInstanceRule,
		disabled = TrackerHidden })
end
for _, row in ipairs({
	{ type = "tab", label = "Quest item" },
	{ type = "description", label = "A button with your tracked quest's item. Bind a key to it to use the item with your key press. It changes only out of combat." },
	{ type = "toggle", key = "questItem.enabled", label = "Quest item button", desc = "A button (and key) for the item of the super-tracked quest, or of the first tracked quest that has one. Move it with /eui move." },
	{ type = "execute", label = "Bind a key", desc = "Opens keybind mode with the button shown: hover it, press a key, then click Save.",
		func = function() M:BindQuestItemKey() end, hidden = function() return not M.db.questItem.enabled end },
	{ type = "select", key = "questItem.source", label = "Which quest", desc = "Super-tracked first: the quest you picked on the map or tracker comes first, then the tracker order. Tracker order: the first tracked quest with an item.",
		values = { super = "Super-tracked first", tracker = "Tracker order" }, dependsOn = "questItem.enabled" },
	{ type = "toggle", key = "questItem.showButton", label = "Show the button", desc = "Off keeps only the key: the button stays invisible and takes no clicks.", dependsOn = "questItem.enabled" },
	{ type = "range", key = "questItem.size", label = "Size", desc = "Size of the button in pixels.", min = 24, max = 64, step = 1, dependsOn = "questItem.enabled" },
	{ type = "cog", label = "Details", dependsOn = "questItem.enabled", desc = "Key text, count, range color, glow and finished quests.", options = {
		{ type = "toggle", key = "questItem.hotkey", label = "Key text", desc = "The bound key in the button's top corner." },
		{ type = "toggle", key = "questItem.count", label = "Charges", desc = "How many uses the item has left, when more than one." },
		{ type = "toggle", key = "questItem.range", label = "Out-of-range color", desc = "The key text turns red while the game says your target is out of the item's range." },
		{ type = "toggle", key = "questItem.glow", label = "Glow on a new item", desc = "The button glows for a few seconds when a new quest item lands on it (look under the Glows page)." },
		{ type = "toggle", key = "questItem.complete", label = "Finished quests too", desc = "Also offer the item of a quest that is ready to turn in." },
	} },

	{ type = "tab", label = "Questie", empty = E.Key("These settings show when Questie is loaded.") },
	{ type = "description", label = "Questie's tracker can share the EldoUI look and the Quest tracker mover.", hidden = NoQuestie },
	{ type = "toggle", key = "questie.skin", hidden = NoQuestie, label = "EldoUI background on Questie's tracker", desc = "Questie's tracker gets the EldoUI panel instead of its own background. Needs the tracker's Skin switch." },
	{ type = "toggle", key = "questie.move", hidden = NoQuestie, label = "Put Questie's tracker on the mover", desc = "Questie's tracker sits on the Quest tracker mover; drag that mover instead of Questie's frame. Needs the tracker's Move and scale switch. Turn on Hide for Blizzard's tracker if both show." },
}) do
	table.insert(M.options, row)
end

---------------------------------------------------------------------------
-- Style presets (Core/Styles.lua). Size, look and behavior only; the
-- position comes from the layout preset.
---------------------------------------------------------------------------
E:RegisterStyles("ObjectiveTracker", {
	{ key = "Clean", title = "Clean", desc = "No background, accent headers between two thin lines, EldoUI font at Blizzard's size.",
		settings = { backdrop = "none", accentHeaders = true, headerLine = true, headerStyle = "fold", font = true, fontSize = 0, headerSize = 0, scale = 1, height = 480,
			visibility = E:VisibilityDefaults() } },
	{ key = "Panel", title = "Panel", desc = "A see-through EldoUI panel behind the tracker.",
		settings = { backdrop = "transparent", accentHeaders = true, headerLine = false, font = true, fontSize = 13, headerSize = 15, scale = 1, height = 480 } },
	{ key = "Compact", title = "Compact", desc = "Smaller text and a shorter tracker for busy screens.",
		settings = { backdrop = "none", accentHeaders = true, font = true, fontSize = 12, headerSize = 13, scale = 0.9, height = 360, headerLine = true, headerStyle = "under" } },
	{ key = "Large", title = "Large print", desc = "Bigger text, easy to read from a distance.",
		settings = { backdrop = "transparent", accentHeaders = true, font = true, fontSize = 15, headerSize = 17, scale = 1.1, height = 560 } },
	{ mode = true, key = "Focus", title = "Combat focus", desc = "See-through in combat and in dungeons, raids, battlegrounds and arenas; hover to read it.",
		settings = { visibility = E:VisibilityDefaults({ preset = "custom", show = "nocombat", fadedAlpha = 0.2, instance = "fade" }),
			instanceTypes = { party = true, raid = true, pvp = true, arena = true, scenario = false } } },
	{ key = "Blizzard", title = "Blizzard-like", desc = "Blizzard's font and gold headers; only the position comes from EldoUI.",
		settings = { font = false, accentHeaders = false, headerLine = false, backdrop = "none", skinButtons = false, skinBars = false, skinItems = false, valueCounts = false,
			visibility = E:VisibilityDefaults() } },
	{ key = "Quiet", title = "Quiet", desc = "See-through at all times, fully visible under the mouse.",
		settings = { visibility = E:VisibilityDefaults({ preset = "custom", show = "mouseover", fadedAlpha = 0.4 }), backdrop = "none" } },
})
