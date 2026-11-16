-- EldoUI UI scale. EldoUI is made for 1440p: every layout in Core/Layout.lua
-- and Data/Layouts.lua is designed on a screen 1440 UI units tall.
--
-- "auto" therefore draws that 2560x1440 canvas on every screen (design
-- decision): the scale is 768 / 1440 (0.5333). On a 1440p screen that is
-- also pixel perfect (one UI unit is one screen pixel). On 1920x1080 every
-- layout looks exactly as designed, only smaller;
-- on 4K it looks the same size as on 1440p instead of tiny. A screen
-- narrower than 16:9 (16:10, 4:3) is 2560 units wide instead and a little
-- taller than 1440: the layouts keep all their width, and the frames anchor
-- to the part of the screen they sit in (top, middle or bottom), so the
-- extra height only widens the gaps between those parts. On 2560x1600 one
-- unit is again one pixel. Pixel-perfect
-- sizes on other screens would keep the frames at 1440p size while the
-- layout fit moves the gaps between them, and frames would overlap.
--
-- "pixel" makes one UI unit one screen pixel for the screen instead. A
-- number is a custom scale.
local _, E = ...
local L = E.L

local Key = E.Key
E.defaults.general.uiScale = "auto" -- "auto" (1440p canvas), "pixel" or a number such as 0.64
-- Before 2026-10-12 "auto" was pixel perfect on 1440p and taller screens and
-- this switch ("Same layout below 1440p") picked the canvas below 1440p. A
-- profile that had it off moves to "pixel" (E:ApplyScale).
E.defaults.general.layoutFitScale = true

local LAYOUT_HEIGHT, LAYOUT_WIDTH = 1440, 2560

function E:GetPixelPerfectScale()
	local _, height = GetPhysicalScreenSize()
	return 768 / height
end

-- The scale that draws the 2560x1440 canvas: the screen is 1440 UI units
-- tall, and a screen narrower than 16:9 (16:10, 4:3) is 2560 units wide
-- instead, taller than 1440, so every layout keeps the room it was made for.
function E:GetLayoutCanvasScale()
	local scale = 768 / LAYOUT_HEIGHT
	local width, height = GetPhysicalScreenSize()
	if type(width) == "number" and type(height) == "number" and width > 0 and height > 0 then
		scale = math.min(scale, 768 * width / (height * LAYOUT_WIDTH))
	end
	return scale
end

-- Does the current setting draw the 1440-unit canvas?
function E:WantsLayoutCanvas()
	local general = self.db and self.db.general
	return general ~= nil and general.uiScale == "auto"
end

-- The scale "auto" stands for: the 1440p canvas on every screen.
function E:GetAutoScale()
	return self:GetLayoutCanvasScale()
end

function E:GetTargetScale()
	local setting = self.db.general.uiScale
	if type(setting) == "number" then return setting end
	if setting == "pixel" then return self:GetPixelPerfectScale() end
	return self:GetAutoScale()
end

-- How a UI scale suits EldoUI's layouts, for the markers in the options
-- and the setup. The layouts are made on the 1440-unit canvas (Auto), so:
--   recommended  the canvas itself: every layout looks exactly as designed
--   supported    a little smaller: the layouts keep their room, the text is
--                smaller but still reads on this screen
--   small        smaller still: the smallest text gets hard to read here
--   large        bigger than the canvas: the layouts have less room than
--                they were made for, and frames can overlap
-- The smallest text EldoUI draws in its layouts is 11 units; on screen that
-- is 11 x scale x screen height / 768 pixels, and 9 pixels is where it
-- stops reading well. value: a number, "auto" or "pixel". Returns the tier
-- and a short text for the player, or nil for no value.
local READABLE_PIXELS, SMALLEST_TEXT = 9, 11
-- The tiny size token, the smallest text in windows and lists.
local function SmallestText()
	local size = E.tokens and E.tokens.size and tonumber(E.tokens.size.tiny)
	return size and size > 0 and size or 10
end
function E:ScaleAdvice(value)
	local scale = value == "auto" and self:GetAutoScale() or value == "pixel" and self:GetPixelPerfectScale() or tonumber(value)
	if not scale or scale <= 0 then return nil end
	local canvas = self:GetLayoutCanvasScale()
	if math.abs(scale - canvas) < 0.005 then
		return "recommended", L["Recommended: every layout looks exactly as designed."]
	end
	if scale > canvas then
		return "large", L["Not recommended: the layouts have less room here than they were made for, so frames can overlap. For bigger text, keep Auto and turn on Large text on the Accessibility page."]
	end
	local _, height = GetPhysicalScreenSize()
	height = tonumber(height) or 1440
	local readable = READABLE_PIXELS * 768 / (SMALLEST_TEXT * height)
	if scale + 0.0001 >= math.max(readable, 0.45) then
		return "supported", L["Supported: the layouts keep their room and the text gets smaller."]
	end
	return "small", L["Not recommended: the smallest text gets hard to read on this screen. Keep Auto, and turn on Large text on the Accessibility page for bigger text."]
end

-- Screens under 1440 pixels tall: Auto keeps the 1440-unit canvas, so the
-- smallest text draws smaller than on the canvas. Returns that size in
-- screen pixels with Large text as it is now, and the Large text scale
-- (rounded up to 5 %, at most 160 %) that brings it to 9 pixels; nil when
-- the text already reads well. A hint only: nothing changes by itself.
function E:SmallTextAdvice()
	local _, height = GetPhysicalScreenSize()
	height = tonumber(height)
	if not height or height <= 0 or height >= 1440 then return nil end
	local scale = self.db and self:GetTargetScale()
	if not scale or scale <= 0 then return nil end
	local plain = SmallestText() * scale * height / 768
	local general = self.db and self.db.general
	local now = plain * (tonumber(general and general.textScale) or 1)
	if now >= READABLE_PIXELS - 0.05 then return nil end
	local need = math.ceil(READABLE_PIXELS / plain * 20 - 0.001) / 20
	return now, math.max(1.05, math.min(1.6, need))
end

-- One screen pixel in UI units (E.pixel), for 1-pixel borders and lines.
-- `scale` is the UIParent scale to measure for; default the one in use.
-- At ADDON_LOADED (Core/Init.lua) it is the scale EldoUI is about to set,
-- so frames modules build before PLAYER_LOGIN get the right border size.
-- When the value changes, E:RefreshPixel re-sizes what was built with the
-- old one.
local pixelCallbacks = {}

function E:UpdatePixel(scale)
	local _, height = GetPhysicalScreenSize()
	scale = tonumber(scale) or UIParent:GetScale()
	if not (height and height > 0 and scale and scale > 0) then return end
	local old = self.pixel
	self.pixel = 768 / height / scale
	if old and math.abs(old - self.pixel) > 0.00001 then self:RefreshPixel(old) end
end

-- fn(pixel, oldPixel) after E.pixel changed (a new UI scale or screen
-- size). Borders made with E:SetTemplate and the panels follow by
-- themselves; code that sized lines or gaps with E.pixel listens here.
function E:RegisterPixelCallback(fn)
	assert(type(fn) == "function", "EldoUI:RegisterPixelCallback(fn)")
	table.insert(pixelCallbacks, fn)
end

function E:RefreshPixel(old)
	if self.RefreshPixelEdges then self:RefreshPixelEdges() end
	for _, fn in ipairs(pixelCallbacks) do
		local ok, err = pcall(fn, self.pixel, old)
		if not ok then geterrorhandler()(err) end
	end
end

function E:ApplyScale()
	self:RunOutOfCombat(function()
		local general = self.db.general
		if general.uiScale == "auto" and general.layoutFitScale == false then
			general.uiScale, general.layoutFitScale = "pixel", true
		end
		local target = self:GetTargetScale()
		-- Only set when different, so a scale event can't trigger a loop.
		local changed = math.abs(UIParent:GetScale() - target) > 0.0001
		if changed then
			UIParent:SetScale(target)
		end
		self:UpdatePixel()
		-- The safe area is measured in UI units, so it follows the scale.
		self:UpdateSafeArea()
		-- Layout points are fitted to the screen height in UI units; a screen
		-- of another width can pick a layout's narrow points (Core/Layout.lua).
		local width = UIParent:GetWidth() or 0
		local widthChanged = self.layoutWidthSeen ~= nil and math.abs(width - self.layoutWidthSeen) > 1
		self.layoutWidthSeen = width
		if (changed and self.db.general.layoutFit) or widthChanged then self:RefreshMovers() end
	end)
end

-- Blizzard re-applies its own scale when the display or the uiScale CVar
-- changes, so EldoUI re-applies its scale after those events.
-- The player changing Blizzard's own UI scale slider (Options > Graphics)
-- is overridden too: say so once per session, with where to change it.
-- E.scaleOverrideTold: said this session.
local scaleOwner = {}
local function Reapply(_, event)
	if not E.db then return end
	if event == "UI_SCALE_CHANGED" and not E.scaleOverrideTold and IsLoggedIn() and not InCombatLockdown()
		and math.abs(UIParent:GetScale() - E:GetTargetScale()) > 0.0001 then
		E.scaleOverrideTold = true
		-- A notice the player can act on: an alert, not a chat line.
		E:PushAlert({ key = "EldoUI_ScaleOverride", title = L["UI scale"], options = { page = "general", key = "uiScale" },
			text = L["EldoUI keeps its own UI scale (%s), so the game's UI scale setting has no effect. Change it with %s or in /eui > General."]
				:format(E:ScaleLabel(), E:Highlight("/eui scale")) })
	end
	E:ApplyScale()
end
E:RegisterEvent("UI_SCALE_CHANGED", Reapply, scaleOwner)
E:RegisterEvent("DISPLAY_SIZE_CHANGED", Reapply, scaleOwner)

-- The scale setting in words, for chat lines.
function E:ScaleLabel()
	local setting = self.db.general.uiScale
	if setting == "auto" then return L["auto, 1440p (%.4f)"]:format(self:GetAutoScale()) end
	if setting == "pixel" then return L["pixel perfect (%.4f)"]:format(self:GetPixelPerfectScale()) end
	return ("%.2f"):format(tonumber(setting) or self:GetTargetScale())
end

---------------------------------------------------------------------------
-- Ultrawide safe area
--
-- On a 21:9 or 32:9 screen the player can keep the HUD inside a centered
-- 16:9 (or chosen width) area while the game world fills the whole screen.
-- Every EldoUI mover measures its position from this area instead of from
-- UIParent (Core/Movers.lua asks E:GetMoverAnchor()), so "top right" means
-- the top right of the area. Center-anchored frames stay where they are.
--
-- Only EldoUI's own holder frame is sized; UIParent and Blizzard frames are
-- never touched. A Blizzard frame follows only when its element's move
-- switch already puts it on an EldoUI mover. Resizing the area moves movers
-- that protected frames hang from, so it always runs out of combat.
---------------------------------------------------------------------------
E.defaults.general.safeArea = "off"      -- off | 16:9 | 21:9 | custom
E.defaults.general.safeAreaWidth = 2560  -- custom width in UI units
E.defaults.general.safeAreaMargin = 0    -- extra gap inside the area, each side
E.defaults.general.safeAreaCorners = true -- corner frames inside the area too

local RATIOS = { ["16:9"] = 16 / 9, ["21:9"] = 21 / 9 }
local area -- EldoUI_SafeArea, created on first use

-- Width the area should have, or nil when it would cover the whole screen.
function E:GetSafeAreaWidth()
	local general = self.db and self.db.general
	if not general or general.safeArea == "off" then return nil end
	local screenW, screenH = UIParent:GetSize()
	local width
	if RATIOS[general.safeArea] then
		width = screenH * RATIOS[general.safeArea]
	elseif general.safeArea == "custom" then
		width = tonumber(general.safeAreaWidth) or screenW
	end
	if not width then return nil end
	width = width - 2 * (tonumber(general.safeAreaMargin) or 0)
	if width >= screenW - 1 or width < 400 then return nil end
	return math.floor(width + 0.5)
end

function E:IsSafeAreaActive()
	return area ~= nil and area.active == true
end

local CORNERS = { TOPLEFT = true, TOPRIGHT = true, BOTTOMLEFT = true, BOTTOMRIGHT = true }

-- The frame mover positions are measured from. relPoint is the point the
-- position uses on that frame: with "Corner frames at the screen corners"
-- on, corner-anchored frames (chat, minimap, meters, bags) keep the true
-- screen corners, as placement.md suggests for 21:9.
function E:GetMoverAnchor(relPoint)
	if not (area and area.active) then return UIParent end
	if relPoint and CORNERS[relPoint] and self.db.general.safeAreaCorners == false then return UIParent end
	return area
end

local function CreateArea()
	area = CreateFrame("Frame", "EldoUI_SafeArea", UIParent)
	area:SetPoint("TOP", UIParent, "TOP")
	area:SetPoint("BOTTOM", UIParent, "BOTTOM")
	area:SetWidth(UIParent:GetWidth())
	area:EnableMouse(false)
	-- Preview: an accent outline and dimmed sides, so the player sees where
	-- "the edge of the screen" now is for EldoUI.
	local preview = CreateFrame("Frame", nil, UIParent)
	preview:SetAllPoints(UIParent)
	preview:SetFrameStrata("BACKGROUND")
	preview:Hide()
	area.preview = preview
	preview.lines = {}
	for i = 1, 4 do preview.lines[i] = preview:CreateTexture(nil, "OVERLAY") end
	preview.left = preview:CreateTexture(nil, "BORDER")
	preview.right = preview:CreateTexture(nil, "BORDER")
	preview.label = E:CreateText(preview, E.tokens.size.label)
	preview.label:SetPoint("TOP", area, "TOP", 0, -4)
end

local function LayoutPreview()
	local preview = area.preview
	local r, g, b = unpack(E.media.accentColor)
	local px = (E.pixel or 1) * 2
	local lines = preview.lines
	for _, line in ipairs(lines) do
		line:ClearAllPoints()
		line:SetColorTexture(r, g, b, 0.9)
	end
	lines[1]:SetPoint("TOPLEFT", area, "TOPLEFT")
	lines[1]:SetPoint("BOTTOMLEFT", area, "BOTTOMLEFT")
	lines[1]:SetWidth(px)
	lines[2]:SetPoint("TOPRIGHT", area, "TOPRIGHT")
	lines[2]:SetPoint("BOTTOMRIGHT", area, "BOTTOMRIGHT")
	lines[2]:SetWidth(px)
	lines[3]:SetPoint("TOPLEFT", area, "TOPLEFT")
	lines[3]:SetPoint("TOPRIGHT", area, "TOPRIGHT")
	lines[3]:SetHeight(px)
	lines[4]:SetPoint("BOTTOMLEFT", area, "BOTTOMLEFT")
	lines[4]:SetPoint("BOTTOMRIGHT", area, "BOTTOMRIGHT")
	lines[4]:SetHeight(px)
	for _, shade in ipairs({ preview.left, preview.right }) do
		shade:ClearAllPoints()
		shade:SetColorTexture(0, 0, 0, 0.35)
	end
	preview.left:SetPoint("TOPLEFT", preview, "TOPLEFT")
	preview.left:SetPoint("BOTTOMRIGHT", area, "BOTTOMLEFT")
	preview.right:SetPoint("TOPRIGHT", preview, "TOPRIGHT")
	preview.right:SetPoint("BOTTOMLEFT", area, "BOTTOMRIGHT")
	preview.label:SetText(L["EldoUI safe area: %d wide"]:format(math.floor(area:GetWidth() + 0.5)))
end

-- Show or hide the outline (move mode, or the button on the options page).
-- Nothing shows while the area is off or the screen is not wider than it.
function E:ShowSafeArea(state)
	if not area then
		if not state then return end
		CreateArea()
	end
	area.previewWanted = state and true or false
	local show = state and area.active
	if show then LayoutPreview() end
	area.preview:SetShown(show and true or false)
end

-- Re-size the area from the settings and put every mover on it.
function E:UpdateSafeArea()
	self:RunOutOfCombat(function()
		local width = self:GetSafeAreaWidth()
		if not width and not area then return end
		if not area then CreateArea() end
		local wasActive = area.active
		area.active = width ~= nil
		area:SetWidth(width or UIParent:GetWidth())
		self:ShowSafeArea(area.previewWanted or self:IsMoveMode())
		-- Movers measured from the old area move to the new one.
		if area.active or wasActive then self:RefreshMovers() end
	end)
end

-- Options page "Screen area", next to Positions.
local SAFE_AREA_VALUES = {
	off = Key("Whole screen"),
	["16:9"] = Key("Centered 16:9"),
	["21:9"] = Key("Centered 21:9 (for 32:9 screens)"),
	custom = Key("Custom width"),
}

-- The margin and the corner switch mean nothing without an area.
local function WholeScreen()
	return E.db.general.safeArea == "off" and L["Pick a usable area other than Whole screen first."] or false
end

E:RegisterEvent("PLAYER_LOGIN", function()
	if not E.RegisterConfigPage then return end
	local options = {
		{ type = "description", label = "On a very wide screen, EldoUI's frames stay inside a centered area while the game world fills the screen." },
		{ type = "header", label = "Safe area" },
		{ type = "select", key = "safeArea", label = "Usable area", values = SAFE_AREA_VALUES,
			desc = "Whole screen: no limit. Centered 16:9: the width a 16:9 screen of the same height has (2560 on a 1440 px tall screen). Has no effect when the screen is not wider than the area." },
		{ type = "range", unit = "px", key = "safeAreaWidth", label = "Custom width", min = 1024, max = 7680, step = 16,
			desc = "Width of the area in UI units, used with \"Custom width\". With the auto UI scale a 16:9 area is 2560 wide.",
			hidden = function() return E.db.general.safeArea ~= "custom" end },
		{ type = "range", key = "safeAreaMargin", label = "Side margin", min = 0, max = 400, step = 4, disabled = WholeScreen,
			desc = "Extra space between the area's edges and the frames along them, on the left and the right." },
		{ type = "toggle", key = "safeAreaCorners", label = "Corner frames inside the area", disabled = WholeScreen,
			desc = "On: frames in a corner (chat, minimap, meters, bags) move into the area too, best for 32:9. Off: they stay in the true screen corners and only the rest of the HUD moves in." },
		{ type = "execute", label = "Show the area", testSafe = true,
			desc = "Shows the outline of the area until you click again. Move mode (/eui move) shows it too.",
			func = function()
				local show = not (area and area.previewWanted)
				E:ShowSafeArea(show)
				if show and not E:IsSafeAreaActive() then
					E:Print(L["The safe area is off, or this screen is not wider than it."])
				end
			end },
	}
	local page = E:RegisterConfigPage("safearea", E.Key("Screen area"), options,
		function() return E.db.general end,
		function() E:UpdateSafeArea() end, 3.1)
	if page then page.desc = L["Limit EldoUI to a centered area on ultrawide screens."] end
end, SAFE_AREA_VALUES, "pages")
