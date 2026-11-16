-- EldoUI Action Bars: how buttons look.
--
--   * EldoUI's own buttons (LibActionButton): flat 1 px template, cropped
--     icons (also for wide, non-square buttons), theme fonts, keybind
--     abbreviations, per-bar text, cooldown numbers, range / power / not
--     usable colors, equipped border, gray while on cooldown, charge
--     cooldown style, press and hover effects, proc glow, Masque.
--   * Blizzard's buttons, when the player keeps Blizzard's bars: the same
--     flat look on top of Blizzard's frames (art faded with SetAlpha, our own
--     child frame for the border, no fields written into Blizzard frames).
--   * The "Action button look" element: Blizzard's spell flyout, text on
--     Blizzard buttons, cooldown numbers on Blizzard buttons, the proc alert
--     overlay in the middle of the screen, and cast on key down.
--
-- Proc glow only follows Blizzard's own SPELL_ACTIVATION_OVERLAY_GLOW
-- events. EldoUI never decides when a button should light up.
-- Assisted Highlight is switched off on WoW: Forever (Camelot
-- InterfaceOverrides.HasAssistedCombat returns false), so it is not offered.
local _, E = ...
local L = E.L

local M = E:GetModule("ActionBars")
local LAB = _G.LibStub("LibActionButton-1.0")

-- Action slot queries through C_ActionBar. The embedded library is an
-- unchanged upstream copy, and another addon may load its own copy of the
-- same version first, so these are set on EldoUI's own buttons after they
-- are made, whichever copy the game uses. A button that holds a spell,
-- item or macro keeps the library's own method; other addons' buttons are
-- never touched.
local ActionBarAPI = C_ActionBar or {}
local function SlotCall(name)
	if type(ActionBarAPI[name]) ~= "function" then return nil end
	return function(action, ...) return ActionBarAPI[name](action, ...) end
end
local SLOT_METHODS = {
	HasAction = SlotCall("HasAction"),
	GetActionText = SlotCall("GetActionText"),
	GetTexture = SlotCall("GetActionTexture"),
	GetCount = SlotCall("GetActionUseCount"),
	IsAttack = SlotCall("IsAttackAction"),
	IsEquipped = SlotCall("IsEquippedAction"),
	IsCurrentlyActive = SlotCall("IsCurrentAction"),
	IsAutoRepeat = SlotCall("IsAutoRepeatAction"),
	IsUsable = SlotCall("IsUsableAction"),
	IsUnitInRange = SlotCall("IsActionInRange"),
}
if ActionBarAPI.IsConsumableAction and ActionBarAPI.IsStackableAction and ActionBarAPI.IsItemAction
	and ActionBarAPI.GetActionUseCount then
	SLOT_METHODS.IsConsumableOrStackable = function(action)
		if ActionBarAPI.IsConsumableAction(action) or ActionBarAPI.IsStackableAction(action) then return true end
		if ActionBarAPI.IsItemAction(action) then return false end
		local uses = ActionBarAPI.GetActionUseCount(action)
		return not E.Secret(uses) and type(uses) == "number" and uses > 0
	end
end

function M.UseActionSlotAPI(button)
	for name, call in pairs(SLOT_METHODS) do
		rawset(button, name, function(self, ...)
			if self._state_type == "action" then return call(self._state_action, ...) end
			local meta = getmetatable(self)
			local index = meta and meta.__index
			local base = type(index) == "table" and index[name]
			if base then return base(self, ...) end
		end)
	end
end

local paintGeometryEpoch = {}
local geometrySecret, authorityEqual = E.Secret, rawequal
local moverGeometrySource = E.MoverAuthoritySource
local existingGeometry
if type(moverGeometrySource) == "function" then local _, _, _, _, existing = moverGeometrySource();existingGeometry = existing end
local function GeometrySame(value, saved) return not geometrySecret(value) and authorityEqual(value, saved) end
local admitGeometry
if type(moverGeometrySource) == "function" then local _, _, _, _, _, _, admit = moverGeometrySource();admitGeometry = admit end
local function ObserveOwnedGeometry(object)
	if type(admitGeometry) ~= "function" then return end
	return admitGeometry(object)
end

local function ObservePaint(object)
	local capture, seal
	if existingGeometry then capture, seal = existingGeometry(object) end
	if not capture then
		local record = ObserveOwnedGeometry(object)
		if not record then return end
		capture, seal = record.capture, record.source
	end
	return { capture = capture, source = seal }
end
-- Getter identities belong to the actual parts created in this file.
local dockGetters = setmetatable({}, { __mode = "k" })
local function BindDockPart(object)
	if dockGetters[object] then return end
	local methods = {}
	for _, key in ipairs({ "GetParent", "GetNumPoints", "GetPoint", "GetRect", "GetEffectiveScale", "IsShown", "IsVisible" }) do methods[key] = object[key] end
	local geometry = ObservePaint(object)
	dockGetters[object] = { methods = methods, geometry = geometry }
	paintGeometryEpoch = {}
end

local ELEMENT = "action-button-look"

---------------------------------------------------------------------------
-- Keybind text
---------------------------------------------------------------------------
-- Longest first, so NUMPADPLUS wins over NUMPAD.
local ABBREVIATIONS = {
	{ "MOUSEWHEELUP", "MwU" }, { "MOUSEWHEELDOWN", "MwD" },
	{ "MIDDLEMOUSE", "M3" }, { "BUTTON(%d+)", "M%1" },
	{ "NUMPADPLUS", "N+" }, { "NUMPADMINUS", "N-" }, { "NUMPADMULTIPLY", "N*" },
	{ "NUMPADDIVIDE", "N/" }, { "NUMPADDECIMAL", "N." }, { "NUMPAD", "N" },
	{ "PAGEUP", "PU" }, { "PAGEDOWN", "PD" }, { "SPACEBAR", "Sp" }, { "SPACE", "Sp" },
	{ "BACKSPACE", "Bs" }, { "CAPSLOCK", "Cl" }, { "INSERT", "Ins" }, { "DELETE", "Del" },
	{ "HOME", "Hm" }, { "ESCAPE", "Esc" }, { "ENTER", "Ent" }, { "TAB", "Tab" },
	{ "ALT%-", "A" }, { "CTRL%-", "C" }, { "SHIFT%-", "S" }, { "META%-", "M" },
}

-- Short keybind text, e.g. "SHIFT-BUTTON4" -> "SM4".
function M:AbbreviateKey(key)
	if type(key) ~= "string" or key == "" then return key end
	local text = key:upper()
	for _, pair in ipairs(ABBREVIATIONS) do text = text:gsub(pair[1], pair[2]) end
	return text
end

-- Keybind text on a button follows the abbreviation setting. Hooked once
-- per FontString; the hook only rewrites text while ActionBars is active.
local hotkeyHooked = setmetatable({}, { __mode = "k" })
local rewriting = false

local function RewriteHotkey(fontString, text)
	if rewriting or not M.active or type(text) ~= "string" then return end
	if issecretvalue and issecretvalue(text) then return end
	if text == "" or text == RANGE_INDICATOR then return end
	local new
	if M.db.hotkeyAbbrev then
		new = M:AbbreviateKey(text)
	elseif not text:find("%l") then
		-- LibActionButton shows the raw key ("SHIFT-1"); show the game's name.
		new = GetBindingText(text)
	end
	if new and new ~= text then
		rewriting = true
		fontString:SetText(new)
		rewriting = false
	end
end

function M:HookHotkey(fontString)
	if not fontString or hotkeyHooked[fontString] then return end
	hotkeyHooked[fontString] = true
	hooksecurefunc(fontString, "SetText", RewriteHotkey)
	RewriteHotkey(fontString, fontString:GetText())
end

---------------------------------------------------------------------------
-- LibActionButton config for EldoUI's buttons
---------------------------------------------------------------------------
-- Base offset and justification per corner; the direction an extra inward
-- nudge (textOffsetX/Y) moves the text.
local TEXT_OFFSETS = {
	TOPRIGHT = { -2, -3, "RIGHT", -1, -1 }, TOPLEFT = { 2, -3, "LEFT", 1, -1 },
	BOTTOMRIGHT = { -2, 3, "RIGHT", -1, 1 }, BOTTOMLEFT = { 2, 3, "LEFT", 1, 1 },
	TOP = { 0, -3, "CENTER", 0, -1 }, BOTTOM = { 0, 3, "CENTER", 0, 1 },
	LEFT = { 2, 0, "LEFT", 1, 0 }, RIGHT = { -2, 0, "RIGHT", -1, 0 }, CENTER = { 0, 0, "CENTER", 0, 0 },
}

-- Outline of the button texts: the theme's (General > Fonts) or a choice.
local function TextFlags()
	local outline = M.db.textOutline
	if outline == "NONE" then return "" end
	if outline == "OUTLINE" or outline == "THICKOUTLINE" then return outline end
	return E.db.general.fontOutline or "OUTLINE"
end

local function Copy(color, fallback)
	color = type(color) == "table" and color or fallback
	return { color[1] or 1, color[2] or 1, color[3] or 1 }
end

local function TextRow(anchor)
	if anchor:find("^TOP") then return "TOP" end
	if anchor:find("^BOTTOM") then return "BOTTOM" end
	return ""
end

local function TextConfig(size, anchor, color)
	local offset = TEXT_OFFSETS[anchor] or TEXT_OFFSETS.TOPRIGHT
	local db = M.db
	local nudgeX = M.Clamp(db.textOffsetX, -10, 10, 0)
	local nudgeY = M.Clamp(db.textOffsetY, -10, 10, 0)
	return {
		font = { font = E.media.font, size = M.Clamp(size, 6, 32, 12), flags = TextFlags() },
		color = Copy(color, { 1, 1, 1 }),
		position = { anchor = anchor, relAnchor = anchor,
			offsetX = offset[1] + offset[4] * nudgeX, offsetY = offset[2] + offset[5] * nudgeY },
		justifyH = offset[3],
	}
end

-- Bars 1 to 3 show their keys when the player's key map asks for it
-- (Core/KeymapSync.lua), whatever the text style says.
local function KeysForced(barDB)
	if not (E.KeymapSetting and E:KeymapSetting("showKeys")) then return false end
	local bars = M.db and M.db.bars
	return bars ~= nil and barDB ~= nil and (barDB == bars[1] or barDB == bars[2] or barDB == bars[3])
end

-- The text settings a bar uses: its own while "Own text settings"
-- is on, otherwise the Text tab's. styleOnly: without the key map's
-- "show keys on bars 1 to 3".
function M:BarText(barDB, styleOnly)
	local db = self.db
	local own = barDB and barDB.ownText and type(barDB.text) == "table" and barDB.text
	local text
	if own then
		text = {
			showHotkey = own.showHotkey ~= false, hotkeySize = own.hotkeySize, hotkeyPosition = own.hotkeyPosition,
			showCount = own.showCount ~= false, countSize = own.countSize, countPosition = own.countPosition,
			showMacro = own.showMacro and true or false, macroSize = own.macroSize, macroPosition = own.macroPosition or "BOTTOM",
		}
	else
		text = {
			showHotkey = db.showHotkey ~= false, hotkeySize = db.fontSize, hotkeyPosition = db.hotkeyPosition,
			showCount = db.showCount ~= false, countSize = db.countSize, countPosition = db.countPosition,
			showMacro = db.showMacro and true or false, macroSize = db.macroSize, macroPosition = db.macroPosition or "BOTTOM",
		}
	end
	text.macroPosition = TEXT_OFFSETS[text.macroPosition] and text.macroPosition or "BOTTOM"
	text.countPosition = TEXT_OFFSETS[text.countPosition] and text.countPosition or "BOTTOMRIGHT"
	text.hotkeyPosition = TEXT_OFFSETS[text.hotkeyPosition] and text.hotkeyPosition or "TOPRIGHT"
	if not styleOnly and KeysForced(barDB) then text.showHotkey = true end
	if text.showMacro and text.showCount then
		local macroRow, countRow = TextRow(text.macroPosition), TextRow(text.countPosition)
		if macroRow == countRow then
			local opposite = macroRow == "TOP" and "BOTTOM" or "TOP"
			local column = text.countPosition:match("LEFT$") or text.countPosition:match("RIGHT$") or ""
			text.countPosition = opposite .. column
			if text.showHotkey and text.countPosition == text.hotkeyPosition then
				text.countPosition = opposite .. (column == "LEFT" and "RIGHT" or "LEFT")
			end
		end
	end
	return text
end

local function CooldownCount(mode)
	if mode == "eldoui" then return true end
	if mode == "off" then return false end
	return nil -- the game's "countdown for cooldowns" setting
end

-- LibActionButton config of one EldoUI button on the bar `barDB`.
function M:ButtonConfig(binding, barDB, flyout)
	local db = self.db
	local text = self:BarText(barDB)
	return {
		outOfRangeColoring = db.rangeColoring == "off" and "none" or db.rangeColoring,
		tooltip = db.tooltips,
		showGrid = not barDB or barDB.showGrid ~= false,
		colors = {
			range = Copy(db.rangeColor, { 0.8, 0.1, 0.1 }),
			mana = Copy(db.manaColor, { 0.5, 0.5, 1 }),
		},
		hideElements = {
			macro = not text.showMacro,
			hotkey = not text.showHotkey,
			-- EldoUI draws its own equipped border on the flat look; with
			-- Masque the library's border (recolored) is used instead.
			equipped = not (db.equippedBorder and db.masque and self:GetMasque()),
		},
		keyBoundTarget = binding,
		flyoutDirection = flyout or "UP",
		cooldownCount = CooldownCount(db.cooldownText),
		spellCastVFX = db.castVFX and true or false,
		text = {
			hotkey = TextConfig(text.hotkeySize, text.hotkeyPosition, db.hotkeyColor),
			count = TextConfig(text.countSize, text.countPosition, db.countColor),
			macro = TextConfig(text.macroSize, text.macroPosition, db.macroColor),
		},
	}
end

---------------------------------------------------------------------------
-- Text presets (options rule: three or more options that change together
-- get a preset). A preset writes the Text tab's keys; changing one of them
-- by hand turns the dropdown to Custom.
---------------------------------------------------------------------------
local TEXT_PRESETS = {
	standard = { title = "Standard", showHotkey = true, fontSize = 13, hotkeyPosition = "TOPRIGHT",
		showCount = true, countSize = 14, countPosition = "BOTTOMRIGHT", showMacro = false, macroSize = 11, macroPosition = "BOTTOM" },
	compact = { title = "Compact", showHotkey = true, fontSize = 10, hotkeyPosition = "TOPRIGHT",
		showCount = true, countSize = 11, countPosition = "BOTTOMRIGHT", showMacro = false, macroSize = 9, macroPosition = "BOTTOM" },
	large = { title = "Large", showHotkey = true, fontSize = 16, hotkeyPosition = "TOPRIGHT",
		showCount = true, countSize = 17, countPosition = "BOTTOMRIGHT", showMacro = false, macroSize = 13, macroPosition = "BOTTOM" },
	macros = { title = "With macro names", showHotkey = true, fontSize = 12, hotkeyPosition = "TOPRIGHT",
		showCount = true, countSize = 13, countPosition = "TOPLEFT", showMacro = true, macroSize = 10, macroPosition = "BOTTOM" },
	clean = { title = "Clean (no keybinds)", showHotkey = false, fontSize = 13, hotkeyPosition = "TOPRIGHT",
		showCount = true, countSize = 14, countPosition = "BOTTOMRIGHT", showMacro = false, macroSize = 11, macroPosition = "BOTTOM" },
}
local TEXT_PRESET_KEYS = { "showHotkey", "fontSize", "hotkeyPosition", "showCount", "countSize", "countPosition", "showMacro", "macroSize", "macroPosition" }
M.TEXT_PRESETS = TEXT_PRESETS

local function MatchesTextPreset(db, key)
	local preset = TEXT_PRESETS[key]
	if not preset then return false end
	for _, field in ipairs(TEXT_PRESET_KEYS) do
		if preset[field] ~= db[field] then return false end
	end
	return true
end

local appliedText = setmetatable({}, { __mode = "k" })  -- settings table -> preset last in line

function M:NormalizeTextPreset()
	local db = self.db
	if not db then return end
	local preset = db.textPreset
	if TEXT_PRESETS[preset] and appliedText[db] ~= nil and appliedText[db] ~= preset then
		-- The dropdown just changed: write the preset.
		for _, field in ipairs(TEXT_PRESET_KEYS) do db[field] = TEXT_PRESETS[preset][field] end
	elseif not MatchesTextPreset(db, preset) then
		db.textPreset = "custom"
		for key in pairs(TEXT_PRESETS) do
			if MatchesTextPreset(db, key) then
				db.textPreset = key
				break
			end
		end
	end
	appliedText[db] = db.textPreset
end

-- Cooldown look for a button of `size` pixels.
function M:CooldownOptions(size, keepShown)
	local db = self.db
	-- The shared look of General > Fonts and Text unless the bars keep their own.
	local look = db.cooldownOwnLook and db or E.db.general
	return {
		mode = db.cooldownText,
		size = math.max(8, math.min(db.cooldownSize, math.floor((size or 40) * 0.6))),
		expiring = look.cooldownExpiring,
		tenths = look.cooldownTenths,
		color = look.cooldownColor,
		secondsColor = look.cooldownSecondsColor,
		expiringColor = look.cooldownExpiringColor,
		swipeAlpha = db.swipeAlpha,
		bling = db.drawBling,
		minDuration = db.cooldownMinDuration,
		edge = db.cooldownEdge,
		keepShown = keepShown,
	}
end

---------------------------------------------------------------------------
-- Press, hover and checked effects
---------------------------------------------------------------------------
local skinHover = setmetatable({}, { __mode = "k" })  -- highlight texture -> its own blend mode

-- Back from the skin's hover art: the blend mode and full coordinates.
local function PlainOverlay(texture)
	local blend = skinHover[texture]
	if blend == nil then return end
	skinHover[texture] = nil
	texture:SetTexCoord(0, 1, 0, 1)
	texture:SetBlendMode(blend)
end

local function StyleOverlay(texture, style, alpha, anchor)
	if not texture then return end
	PlainOverlay(texture)
	texture:ClearAllPoints()
	texture:SetAllPoints(anchor)
	if style == "none" then
		texture:SetAlpha(0)
		return
	end
	texture:SetAlpha(1)
	if style == "accent" then
		E:AccentTexture(texture, alpha + 0.1)
	else
		E:ReleaseAccentTexture(texture)
		texture:SetColorTexture(1, 1, 1, alpha)
	end
end

---------------------------------------------------------------------------
-- The skin's button frame. Native skins (Core/Skins.lua) draw their button
-- frame on the box under the button, which is our own frame: the button
-- itself keeps its size, points and hit rect. The icon sits inside the
-- frame's rim, and the mouse-over highlight shows the skin's hover art in
-- the player's highlight style. The five classic skins keep the flat box.
---------------------------------------------------------------------------
-- Paint the box; returns the skin's manifest when it draws a frame.
local function SkinFrame(box)
	local id = E:PaintSurface(box, "button", "actionbuttons")
	local m = E:SkinManifest(id)
	if m.legacy or not (m.data and m.data.files and m.data.files.button) then return nil end
	return m
end
M.SkinFrame = SkinFrame

-- How far the icon sits inside the frame: the rim of the button art,
-- measured in UI units at the size the frame is drawn.
-- button: the icon's own button, so a bar at another scale still insets by
-- one whole screen pixel.
function M:SkinIconInset(m, button)
	local px = button and E.PixelFor and E:PixelFor(button) or E.pixel
	if not m then return px end
	local metrics = m.data.metrics
	local slice = metrics.button and metrics.button.sliceMargin
	local scale = (slice and slice.texels > 0) and slice.ui / slice.texels or 0.5
	return math.max(px, math.floor((metrics.borderSize or 1) * scale + 0.5))
end

-- The mouse-over highlight in the skin's hover art: the skin's highlight
-- color, or the accent with the Accent style; "none" stays empty.
local function SkinOverlay(texture, style, m, anchor)
	if not texture then return end
	if style == "none" then return StyleOverlay(texture, style, 0, anchor) end
	if skinHover[texture] == nil then skinHover[texture] = texture.GetBlendMode and texture:GetBlendMode() or "ADD" end
	E:ReleaseAccentTexture(texture)
	texture:ClearAllPoints()
	texture:SetAllPoints(anchor)
	texture:SetAlpha(1)
	texture:SetTexture(m.data.files.button)
	texture:SetTexCoord(0.5, 1, 0, 1)
	texture:SetBlendMode("ADD")
	local c = style == "accent" and E.media.accentColor or m.data.colors.highlight
	texture:SetVertexColor(c[1], c[2], c[3], E.tokens.skin.hoverAlpha)
end

-- The equipped tint on a skin frame: the rim in the equipped color (the
-- icon covers the middle).
local function EquippedTint(parts, color)
	if not parts.tint then
		parts.tint = parts.backdrop:CreateTexture(nil, "OVERLAY")
		BindDockPart(parts.tint)
		parts.tint:SetAllPoints(parts.backdrop)
	end
	if color then
		parts.tint:SetColorTexture(color[1], color[2], color[3], 0.6)
		parts.tint:Show()
	else
		parts.tint:Hide()
	end
end

---------------------------------------------------------------------------
-- EldoUI's own buttons
---------------------------------------------------------------------------
local styled = setmetatable({}, { __mode = "k" })  -- button -> parts

-- Crop the icon: `zoom` percent off every edge, and more off the top and
-- bottom (or the sides) so a non-square button shows the icon unstretched.
function M:IconCoords(zoom, width, height)
	return E:IconCoords(math.max(0, math.min(0.25, (zoom or 8) / 100)), width, height)
end

local function IconInset(button, zoom, width, height, inset)
	local icon = button.icon
	if not icon then return end
	inset = inset or E.pixel
	icon:SetTexCoord(M:IconCoords(zoom, width, height))
	icon:ClearAllPoints()
	icon:SetPoint("TOPLEFT", inset, -inset)
	icon:SetPoint("BOTTOMRIGHT", -inset, inset)
end

-- Equipped items: EldoUI's border in the chosen color on the flat
-- look; LibActionButton's border, recolored, under Masque.
-- IsEquippedAction is gear state, not combat data.
local function UpdateEquipped(button)
	local parts = styled[button]
	if not parts then return end
	local db = M.db
	local equipped = false
	if M.active and db.equippedBorder and button.IsEquipped then
		local value = button:IsEquipped()
		equipped = not (issecretvalue and issecretvalue(value)) and value and true or false
	end
	local color = Copy(db.equippedColor, { 0.3, 0.85, 0.3 })
	if button.MasqueSkinned then
		if equipped and button.Border then button.Border:SetVertexColor(color[1], color[2], color[3], 0.8) end
		return
	end
	if equipped then
		parts.backdrop:SetBackdropBorderColor(color[1], color[2], color[3], 1)
		parts.equipped = true
	elseif parts.equipped then
		parts.backdrop:SetBackdropBorderColor(unpack(E.media.borderColor))
		parts.equipped = nil
	end
	-- A skin frame covers the box's edge: the rim takes the color instead.
	if parts.skinned or parts.tint then EquippedTint(parts, equipped and parts.skinned and color or nil) end
end

-- Read-only: the parts EldoUI draws on one of its buttons (backdrop, tint).
function M:ButtonParts(button) return styled[button] end

function M:StyleButton(button, width, height, barDB)
	local db = self.db
	height = height or width
	local parts = styled[button]
	if not parts then
		parts = {}
		parts.backdrop = CreateFrame("Frame", nil, button)
		BindDockPart(parts.backdrop)
		parts.backdrop:SetAllPoints()
		parts.backdrop:SetFrameLevel(math.max(button:GetFrameLevel() - 1, 0))
		if button.IconMask and button.icon then button.icon:RemoveMaskTexture(button.IconMask) end
		styled[button] = parts
		self:HookHotkey(button.HotKey)
		self:HookIconColor(button)
	end

	if not button.MasqueSkinned then
		local normal = button:GetNormalTexture()
		if normal then normal:SetAlpha(0) end
		if button.SlotBackground then button.SlotBackground:SetAlpha(0) end
		if button.SlotArt then button.SlotArt:SetAlpha(0) end
		E:SetTemplate(parts.backdrop)
		-- A bar at another scale keeps one whole screen pixel of border.
		if E.SnapBorders then E:SnapBorders(parts.backdrop, true) end
		local skin = SkinFrame(parts.backdrop)
		parts.skinned = skin and true or nil
		IconInset(button, db.buttonZoom, width, height, self:SkinIconInset(skin, button))
		parts.equipped = nil
		parts.backdrop:Show()
		if skin then
			SkinOverlay(button:GetHighlightTexture(), db.highlightStyle, skin, button)
		else
			StyleOverlay(button:GetHighlightTexture(), db.highlightStyle, E.tokens.hover.hud, button.icon)
		end
		StyleOverlay(button:GetPushedTexture(), db.pushedStyle, E.tokens.pressed, button.icon)
		StyleOverlay(button:GetCheckedTexture(), db.checkedStyle or "accent", E.tokens.pressed, button.icon)
		-- The game's rounded overlays take the button's shape: the Auto
		-- Attack and Auto Shot pulse, the glow on a newly placed spell and
		-- the highlight while its spell is hovered in the spellbook.
		local flash = button.Flash
		if flash then
			flash:ClearAllPoints()
			flash:SetAllPoints(button.icon)
			flash:SetColorTexture(E:TokenColor("bad", 0.35))
		end
		if E.AccentTexture then
			StyleOverlay(button.NewActionTexture, "accent", E.tokens.pressed, button.icon)
			StyleOverlay(button.SpellHighlightTexture, "accent", E.tokens.pressed, button.icon)
		end
	else
		E:ReleaseSurface(parts.backdrop)
		parts.skinned = nil
		parts.backdrop:Hide()
	end
	local text = self:BarText(barDB)
	if button.Count then button.Count:SetAlpha(text.showCount and 1 or 0) end
	-- The macro name gets the button's width, not the template's fixed one.
	if button.Name and button.Name.SetWidth then button.Name:SetWidth(math.max(width - 4, 10)) end
	if button.cooldown then E:StyleCooldownText(button.cooldown, self:CooldownOptions(math.min(width, height))) end
	self:StyleChargeCooldown(button)
	self:UpdateGlowSize(button, width)
	UpdateEquipped(button)
	self:UpdateDesaturation(button)
	RewriteHotkey(button.HotKey, button.HotKey and button.HotKey:GetText())
end

---------------------------------------------------------------------------
-- Usable colors: LibActionButton tints an action you can't use
-- gray; EldoUI swaps in the chosen "not usable" color. Out of range and
-- not enough power keep their own colors (LibActionButton's config).
---------------------------------------------------------------------------
local iconHooked = setmetatable({}, { __mode = "k" })
local recolouring = false
local UNUSABLE = 0.4   -- LibActionButton's gray for "not usable"

local function IconColor(icon, r, g, b)
	if recolouring or not M.active then return end
	if issecretvalue and (issecretvalue(r) or issecretvalue(g) or issecretvalue(b)) then return end
	if r == UNUSABLE and g == UNUSABLE and b == UNUSABLE then
		local color = Copy(M.db.unusableColor, { UNUSABLE, UNUSABLE, UNUSABLE })
		recolouring = true
		icon:SetVertexColor(color[1], color[2], color[3])
		recolouring = false
	end
end

function M:HookIconColor(button)
	local icon = button.icon
	if not icon or iconHooked[icon] then return end
	iconHooked[icon] = true
	hooksecurefunc(icon, "SetVertexColor", IconColor)
end

---------------------------------------------------------------------------
-- Desaturate while on cooldown. Only the game's own cooldown state
-- is read: C_ActionBar.GetActionCooldown's isActive and isOnGCD are never
-- secret (API docs: NeverSecret), so no time is read or compared. The
-- global cooldown alone never grays a button.
---------------------------------------------------------------------------
local desaturated = setmetatable({}, { __mode = "k" })  -- buttons EldoUI grayed

local function OnCooldown(button)
	if not (C_ActionBar and C_ActionBar.GetActionCooldown and button.GetAction) then return false end
	local kind, action = button:GetAction()
	if kind ~= "action" or type(action) ~= "number" then return false end
	local ok, info = pcall(C_ActionBar.GetActionCooldown, action)
	if not ok or type(info) ~= "table" then return false end
	local active, gcd = info.isActive, info.isOnGCD
	if issecretvalue and (issecretvalue(active) or issecretvalue(gcd)) then return false end
	return active and not gcd and true or false
end

function M:UpdateDesaturation(button)
	local icon = button.icon
	if not icon then return end
	local grey = self.active and self.db.desaturateCooldown and OnCooldown(button)
	if grey then
		icon:SetDesaturated(true)
		desaturated[button] = true
	elseif desaturated[button] then
		icon:SetDesaturated(false)
		desaturated[button] = nil
	end
end

---------------------------------------------------------------------------
-- Charge cooldowns: the recharge of a spell with charges is drawn as
-- a full swipe, only the bright edge (LibActionButton's default) or not at
-- all. LibActionButton creates that frame the first time it is needed.
---------------------------------------------------------------------------
local chargeStyled = setmetatable({}, { __mode = "k" })  -- cooldown -> mode

function M:StyleChargeCooldown(button, force)
	local cooldown = button.chargeCooldown
	if not cooldown then return end
	local mode = self.db.chargeCooldown
	if not force and chargeStyled[cooldown] == mode then return end
	chargeStyled[cooldown] = mode
	cooldown:SetDrawSwipe(mode == "swipe")
	cooldown:SetDrawEdge(mode ~= "none")
	if cooldown.SetDrawBling then cooldown:SetDrawBling(false) end
	if mode == "swipe" then
		cooldown:SetSwipeColor(0, 0, 0, M.Clamp(self.db.swipeAlpha, 0, 100, 80) / 200)
	end
	cooldown:SetAlpha(mode == "none" and 0 or 1)
end

-- LibActionButton's own flyout buttons get the same look.
LAB.RegisterCallback(M, "OnFlyoutButtonCreated", function(_, button)
	if M.active then M:StyleButton(button, button:GetWidth(), button:GetHeight()) end
end)

---------------------------------------------------------------------------
-- Proc glow on EldoUI's buttons, drawn by the shared glow engine
-- (Core/Glow.lua). Its look is the "Action bar procs" row on
-- General > Glows; the module's own "Proc glow" setting picks between that
-- look ("blizzard", the default), the older accent pulse ("eldoui") and
-- no glow ("none").
---------------------------------------------------------------------------
local glowing = setmetatable({}, { __mode = "k" })   -- button -> current native request
local IsSpellOverlayed = C_SpellActivationOverlay and C_SpellActivationOverlay.IsSpellOverlayed or _G.IsSpellOverlayed
local RefreshGlow

local function ProcGlowAllowed()
	local db = M.db
	return E.modules.ActionBars == M and M.active and not E:IsSecret(db) and type(db) == "table"
		and not E:IsSecret(db.procGlow) and type(db.procGlow) == "string"
		and not E:StandsBack(M, "procGlow")
end

local function CurrentGlow(button, own)
	return own and glowing[button] == own and own.db == M.db and own.profile == E.db and styled[button]
		and ProcGlowAllowed() and own.mode == M.db.procGlow
end

E:RegisterGlowUser("procs", {
	title = "Action bar procs",
	desc = "Buttons whose spell the game lights up (a proc). Only the game's own proc signal starts it.",
	order = 10,
	button = true,
	default = { style = "blizzard", colorMode = "custom", color = { 1, 0.82, 0 } },
})

function M:UpdateGlowSize(button)
	if glowing[button] then E:UpdateGlowLayout(button) end
end

local function HideGlow(button, force)
	local own = glowing[button]
	if not own and not force then return end
	glowing[button] = nil
	local ok, problem = pcall(E.HideGlow, E, button)
	if not ok then
		if own and not glowing[button] then glowing[button] = own end
		error(problem, 0)
	end
	-- A callback may have acquired this pooled native child for a new request.
	if CurrentGlow(button, glowing[button]) then RefreshGlow(button, true) end
end

local function ShowGlow(button, force)
	if not ProcGlowAllowed() or not styled[button] then return HideGlow(button) end
	local mode = M.db.procGlow
	if mode == "none" then return HideGlow(button) end
	local prior = glowing[button]
	if not force and CurrentGlow(button, prior) and E:IsGlowShown(button) then return end
	local own = { mode = mode, db = M.db, profile = E.db }
	glowing[button] = own
	local ok, problem = pcall(function()
		if mode == "eldoui" then
			-- The look EldoUI had before the shared glows: an accent pulse just
			-- outside the icon.
			E:ShowGlow(button, "pulse", { color = E.media.accentColor, speed = 0.25, thickness = 2, inset = -2 })
		else
			E:ShowUserGlow(button, "procs")
		end
	end)
	if not ok then
		if glowing[button] == own then pcall(HideGlow, button) end
		error(problem, 0)
	end
	if glowing[button] ~= own then
		if CurrentGlow(button, glowing[button]) then RefreshGlow(button, true)
		else HideGlow(button, true) end
	elseif not CurrentGlow(button, own) then
		HideGlow(button)
	end
end

-- Glow when Blizzard says the button's spell is lit up.
RefreshGlow = function(button, force)
	if not ProcGlowAllowed() or not styled[button] then return HideGlow(button) end
	local spellID = button.GetSpellId and button:GetSpellId()
	if not (issecretvalue and issecretvalue(spellID)) and spellID and IsSpellOverlayed and IsSpellOverlayed(spellID) then
		ShowGlow(button, force)
	else
		HideGlow(button)
	end
end

local function ForEachButton(fn)
	for _, header in pairs(M.bars) do
		for _, button in ipairs(header.buttons) do fn(button) end
	end
end

function M:RefreshProcGlows()
	ForEachButton(RefreshGlow)
end

function M:OnStandBack(feature)
	if feature == "procGlow" then self:RefreshProcGlows()
	elseif feature == "procOverlay" then self:RefreshProcOverlay() end
end

local function GlowEvent(_, event, spellID)
	if (issecretvalue and issecretvalue(spellID)) or not spellID then return end
	ForEachButton(function(button)
		local id = button:GetSpellId()
		if id == spellID then
			if event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" then ShowGlow(button) else HideGlow(button) end
		end
	end)
end

-- After LibActionButton updates a button (new action, page change).
LAB.RegisterCallback(M, "OnButtonUpdate", function(_, button)
	if not styled[button] then return end
	RefreshGlow(button)
	UpdateEquipped(button)
	M:UpdateDesaturation(button)
	M:StyleChargeCooldown(button)
end)

-- Cooldowns started or ended: gray icons follow, and charge cooldown
-- frames LibActionButton just made get their look (next frame, after the
-- library has handled the same event).
-- Only buttons that hold an action on a shown bar are visited: an empty or
-- hidden button has no cooldown to show (a bar that shows again catches up
-- in M:RefreshBarCooldowns). With "gray while on cooldown" off and no new
-- charge cooldown frame from LibActionButton, nothing is visited at all.
local COOLDOWN_EVENTS = { "SPELL_UPDATE_COOLDOWN", "ACTIONBAR_UPDATE_COOLDOWN", "SPELL_UPDATE_CHARGES" }
local cooldownPending = false
local chargeFramesSeen = -1
M.cooldownSweeps = 0 -- buttons the cooldown events have visited so far
local function CooldownLook(button, gray, charges)
	if gray then M:UpdateDesaturation(button) end
	if charges then M:StyleChargeCooldown(button) end
end
local function CooldownEvent()
	if cooldownPending then return end
	cooldownPending = true
	C_Timer.After(0, function()
		cooldownPending = false
		if not M.active then return end
		local made = LAB.NumChargeCooldowns or 0
		local charges = made ~= chargeFramesSeen
		chargeFramesSeen = made
		local gray = M.db.desaturateCooldown and true or false
		-- Gray turned off: the icons EldoUI grayed get their color back.
		if not gray and next(desaturated) then
			for button in pairs(desaturated) do M:UpdateDesaturation(button) end
		end
		if not (gray or charges) then return end
		for _, header in pairs(M.bars) do
			if header:IsShown() then
				for _, button in ipairs(header.buttons) do
					if button:HasAction() then
						M.cooldownSweeps = M.cooldownSweeps + 1
						CooldownLook(button, gray, charges)
					end
				end
			end
		end
	end)
end

-- A bar that shows again: its buttons' gray icons and charge looks follow
-- the cooldowns that ran while it was hidden.
function M:RefreshBarCooldowns(header)
	if not (self.active and header and header.buttons) then return end
	local gray = self.db.desaturateCooldown and true or false
	for _, button in ipairs(header.buttons) do
		if button:HasAction() then CooldownLook(button, gray, true) end
	end
end

---------------------------------------------------------------------------
-- Masque (optional): if Masque is installed, EldoUI's buttons can use its
-- skins through Masque's public API (Masque:Group, group:AddButton).
---------------------------------------------------------------------------
local masqueGroups = {}

function M:GetMasque()
	return _G.LibStub and _G.LibStub("Masque", true)
end

function M:UpdateMasque()
	local Masque = self:GetMasque()
	if not Masque then return end
	for index, header in pairs(self.bars) do
		local group = masqueGroups[index]
		if not group and self.db.masque then
			group = Masque:Group("EldoUI", "Action Bar " .. index)
			masqueGroups[index] = group
		end
		if group then
			for _, button in ipairs(header.buttons) do
				if self.db.masque and not button.MasqueSkinned then
					button:AddToMasque(group)
				elseif not self.db.masque and button.MasqueSkinned then
					group:RemoveButton(button)
					button.MasqueSkinned = nil
				end
			end
		end
	end
end

---------------------------------------------------------------------------
-- Blizzard's buttons
---------------------------------------------------------------------------
local blizzardSkins = setmetatable({}, { __mode = "k" })   -- button -> parts
local styledCooldowns = setmetatable({}, { __mode = "k" }) -- cooldown -> true while EldoUI formats it

-- Icon zoom and the cooldown numbers of the bars on a skinned game button
-- (pet, stance, possess and the game's own bars).
local function BlizzardButtonLook(self, button)
	local icon = button.icon or button.Icon
	if icon and icon.SetTexCoord then
		local width, height = button:GetSize()
		icon:SetTexCoord(self:IconCoords(self.db.buttonZoom, width, height))
	end
	local cooldown = button.cooldown
	if cooldown then
		E:StyleCooldownText(cooldown, self:CooldownOptions(math.min(button:GetWidth(), button:GetHeight()), true))
		styledCooldowns[cooldown] = true
	end
end

-- Back to the game's own cooldown number format.
local function ReleaseCooldownText(cooldown)
	if not (cooldown and styledCooldowns[cooldown]) then return end
	styledCooldowns[cooldown] = nil
	E:StyleCooldownText(cooldown, { mode = "blizzard", keepShown = true })
	if cooldown.SetMinimumCountdownDuration then pcall(cooldown.SetMinimumCountdownDuration, cooldown, 0) end
end

-- Flat EldoUI look on a Blizzard action-style button. Only alpha, texture
-- coordinates, fonts and our own child frame; safe to call again.
function M:SkinBlizzardButton(button)
	if not E:SkinUsable(button) then return end
	local parts = blizzardSkins[button]
	if not parts then
		parts = {}
		parts.backdrop = CreateFrame("Frame", nil, button)
		parts.backdrop:SetAllPoints()
		parts.backdrop:SetFrameLevel(math.max(button:GetFrameLevel() - 1, 0))
		blizzardSkins[button] = parts
	end
	if parts.on then
		E:SetTemplate(parts.backdrop)
		if E.SnapBorders then E:SnapBorders(parts.backdrop, true) end
		self:InsetBlizzardIcon(button, SkinFrame(parts.backdrop))
		-- The Text and Buttons tabs apply on every pass, so a change shows at once.
		BlizzardButtonLook(self, button)
		self:StyleBlizzardText(button)
		return
	end
	parts.on = true
	local normal = button.GetNormalTexture and button:GetNormalTexture()
	if normal then normal:SetAlpha(0) end
	for _, key in ipairs({ "SlotArt", "SlotBackground", "FloatingBG", "Border" }) do
		local region = button[key]
		if region and region.SetAlpha and key ~= "Border" then region:SetAlpha(0) end
	end
	local icon = button.icon or button.Icon
	if icon then
		if button.IconMask and icon.RemoveMaskTexture then icon:RemoveMaskTexture(button.IconMask) end
	end
	BlizzardButtonLook(self, button)
	E:SetTemplate(parts.backdrop)
	if E.SnapBorders then E:SnapBorders(parts.backdrop, true) end
	self:InsetBlizzardIcon(button, SkinFrame(parts.backdrop))
	parts.backdrop:Show()
	self:StyleBlizzardText(button)
end

-- The icon of a skinned Blizzard button inside the box, or inside the
-- skin's button frame (only the icon texture moves, never the button).
function M:InsetBlizzardIcon(button, skin)
	local icon = button.icon or button.Icon
	if not icon then return end
	local inset = self:SkinIconInset(skin, button)
	icon:ClearAllPoints()
	icon:SetPoint("TOPLEFT", button, "TOPLEFT", inset, -inset)
	icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -inset, inset)
end

-- Back to Blizzard's look (best effort; a /reload is exact).
function M:UnskinBlizzardButton(button)
	local parts = blizzardSkins[button]
	if not parts or not parts.on then return end
	parts.on = nil
	local normal = button.GetNormalTexture and button:GetNormalTexture()
	if normal then normal:SetAlpha(1) end
	for _, key in ipairs({ "SlotArt", "SlotBackground", "FloatingBG" }) do
		local region = button[key]
		if region and region.SetAlpha then region:SetAlpha(1) end
	end
	local icon = button.icon or button.Icon
	if icon then
		icon:SetTexCoord(0, 1, 0, 1)
		icon:ClearAllPoints()
		icon:SetAllPoints(button)
		if button.IconMask and icon.AddMaskTexture then icon:AddMaskTexture(button.IconMask) end
	end
	ReleaseCooldownText(button.cooldown)
	E:ReleaseSurface(parts.backdrop)
	parts.backdrop:Hide()
end

-- The Text tab on a Blizzard button (pet, stance, possess, and Blizzard's
-- own bars): font, size, outline, color, corner and whether each text
-- shows, plus abbreviated keybinds. On a small button the keybind shrinks
-- to fit (at most 40 % of the button's width).
local function StyleBlizzardString(fontString, button, size, anchor, color, shown)
	local cfg = TextConfig(size, anchor, color)
	E:SetFont(fontString, cfg.font.size, cfg.font.flags)
	fontString:SetTextColor(cfg.color[1], cfg.color[2], cfg.color[3])
	fontString:ClearAllPoints()
	fontString:SetPoint(cfg.position.anchor, button, cfg.position.relAnchor, cfg.position.offsetX, cfg.position.offsetY)
	if fontString.SetJustifyH then fontString:SetJustifyH(cfg.justifyH) end
	-- Alpha, not Hide: the game shows and hides these texts itself.
	fontString:SetAlpha(shown and 1 or 0)
end

function M:StyleBlizzardText(button)
	local db = self.db
	local text = self:BarText(nil, true)
	if button.HotKey then
		local size = text.hotkeySize
		local width = button.GetWidth and button:GetWidth()
		if type(width) == "number" and width > 0 then size = math.min(size or 12, math.max(6, math.floor(width * 0.4))) end
		StyleBlizzardString(button.HotKey, button, size, text.hotkeyPosition or "TOPRIGHT", db.hotkeyColor, text.showHotkey)
		self:HookHotkey(button.HotKey)
	end
	if button.Count then
		StyleBlizzardString(button.Count, button, text.countSize, text.countPosition or "BOTTOMRIGHT", db.countColor, text.showCount)
	end
	if button.Name then
		StyleBlizzardString(button.Name, button, text.macroSize, text.macroPosition or "BOTTOM", db.macroColor, text.showMacro)
	end
end

local function BlizzardBarButtons(index, fn)
	local prefix = M.BARS[index].buttons
	for slot = 1, 12 do
		local button = _G[prefix .. slot]
		if button then fn(button) end
	end
end

-- Main bar art: the frame behind the buttons (skin).
local borderArtHidden = false
local function UpdateMainBarArt(skin)
	local bar = MainActionBar
	if not bar or not bar.BorderArt then return end
	if skin then
		bar.BorderArt:SetAlpha(0)
		borderArtHidden = true
	elseif borderArtHidden then
		bar.BorderArt:SetAlpha(1)
		borderArtHidden = false
	end
end

-- The end caps (gryphons) beside Blizzard's main bar. This works with the
-- Action Bars module off too (it used to be a Quality of Life option): it
-- only needs "Let EldoUI change this" on Main action bar. Alpha only, so
-- Blizzard's own show/hide of the caps keeps working.
local endCapsHidden = false
local endCapsOwner = {}   -- event owner key (the module may be off)
function M:UpdateEndCaps()
	local bar = MainActionBar
	local caps = bar and bar.EndCaps
	if not caps or not self.db then return end
	local hide = self.db.endCaps == "hide" and E:BlizzardAllowed("main-action-bar")
	if hide then
		caps:SetAlpha(0)
		endCapsHidden = true
	elseif endCapsHidden then
		caps:SetAlpha(1)
		endCapsHidden = false
	end
end

E:RegisterEvent("PLAYER_ENTERING_WORLD", function() M:UpdateEndCaps() end, endCapsOwner)
-- Main action bar has one handler, the module's own (Modules/ActionBars.lua);
-- it updates the caps while the module is on. With the module off, the
-- caps follow every change of the element's switches from here.
local function EndCapsWhenOff()
	if not M.active then M:UpdateEndCaps() end
end
for _, name in ipairs({ "SetBlizzardElement", "ResetBlizzard", "RestoreBlizzard", "ApplyBlizzardElements" }) do
	if E[name] then hooksecurefunc(E, name, EndCapsWhenOff) end
end

---------------------------------------------------------------------------
-- Vanilla Original: the 2004 main bar under EldoUI's bar 1. A skin that
-- draws the game's own art (E:OriginalArtSkin) gets the stone tray behind
-- the row and a gryphon at each end, the client's classic files drawn by
-- E:SetOriginalArt (Core/Media.lua). Only while bar 1 is one row: the
-- pieces stretch with it (the classic row is 498 wide, twelve 36 px
-- buttons 6 px apart, on a tray 43 high that starts 8 left of the first
-- button and 4 below it). The gryphons follow End caps (Hide hides them). Nothing
-- here takes the mouse; every other skin draws none of it.
---------------------------------------------------------------------------
local CLASSIC_ROW, CLASSIC_BUTTON = 498, 36
local TRAY_SLOTS = { "tray-1", "tray-2" }
local CAP_SLOTS = { left = "endcap-left", right = "endcap-right" }

-- Does the action bar skin draw the game's own art?
function M:OriginalArtOn()
	return E.OriginalArtSkin and E:OriginalArtSkin(E:SkinPart("actionbuttons")) or false
end

-- A slot the client (or a shipped copy) can draw.
function M.OriginalDrawable(slot)
	local row = E.OriginalArt and E:OriginalArt(slot)
	return row ~= nil and (row.shipped ~= nil or E:OriginalArtState(slot) ~= "missing")
end

local dockOriginalArt, dockHudTray
function M:PaintOriginalTray(header, barDB)
	if not header then return false end
	-- Only bar 1 carries the tray; any other holder never shows one.
	if header ~= self.bars[1] then
		if header.originalArt then header.originalArt:Hide() end
		return false
	end
	local art = header.originalArt
	local count = math.floor(math.max(1, math.min(12, tonumber(barDB and barDB.buttons) or 12)))
	local oneRow = barDB and (tonumber(barDB.perRow) or 12) >= count
	local want = self.active and barDB and barDB.enabled and oneRow and self:OriginalArtOn()
		and self.OriginalDrawable(TRAY_SLOTS[1]) and self.OriginalDrawable(TRAY_SLOTS[2])
	if not want then
		if art then art:Hide() end
		return false
	end
	if not art then
		art = CreateFrame("Frame", nil, header)
		art:EnableMouse(false)
		art.tray = { art:CreateTexture(nil, "BACKGROUND"), art:CreateTexture(nil, "BACKGROUND") }
		art.caps = { left = art:CreateTexture(nil, "BORDER"), right = art:CreateTexture(nil, "BORDER") }
		header.originalArt = art
		dockOriginalArt = { header = header, frame = art, tray = { art.tray[1], art.tray[2] }, left = art.caps.left, right = art.caps.right }
		BindDockPart(art)
		for _, texture in ipairs(art.tray) do BindDockPart(texture) end
		BindDockPart(art.caps.left);BindDockPart(art.caps.right)
	end
	art:SetFrameLevel(math.max(header:GetFrameLevel() - 1, 0))
	art:ClearAllPoints()
	art:SetAllPoints(header)
	local width, height = header:GetSize()
	local kx, ky = width / CLASSIC_ROW, height / CLASSIC_BUTTON
	local left, bottom = -8 * kx, -4 * ky
	for index, texture in ipairs(art.tray) do
		texture:ClearAllPoints()
		texture:SetPoint("BOTTOMLEFT", art, "BOTTOMLEFT", left + (index - 1) * 256 * kx, bottom)
		texture:SetSize(256 * kx, 43 * ky)
		E:SetOriginalArt(texture, TRAY_SLOTS[index])
		texture:Show()
	end
	local trayRight = left + 512 * kx
	local caps = self.db.endCaps ~= "hide"
	for side, texture in pairs(art.caps) do
		local slot = CAP_SLOTS[side]
		if caps and self.OriginalDrawable(slot) then
			texture:ClearAllPoints()
			if side == "left" then
				texture:SetPoint("BOTTOMRIGHT", art, "BOTTOMLEFT", left + 32 * ky, bottom)
			else
				texture:SetPoint("BOTTOMLEFT", art, "BOTTOMLEFT", trayRight - 32 * ky, bottom)
			end
			texture:SetSize(128 * ky, 128 * ky)
			E:SetOriginalArt(texture, slot)
			texture:Show()
		else
			texture:Hide()
		end
	end
	art:Show()
	return true
end

---------------------------------------------------------------------------
-- The HUD tray: one bar background behind bars 1 and 2 together, so the two
-- rows sit in a single panel of the action bar skin (made for the Twin Orbs
-- layout, which turns it on). It follows bar 1: shown while bar 1 is, gone
-- while bar 1 is off; with bar 2 off it holds bar 1 alone. Art only: it
-- takes no mouse and is laid out with the bars, out of combat. A skin with
-- the game's own art keeps its classic tray under bar 1 instead.
---------------------------------------------------------------------------
-- pad: the tray's margin around the rows.
E.tokens.hudTray = E.tokens.hudTray or { pad = 8 }

function M:UpdateHudTray()
	local bar1, bar2 = self.bars and self.bars[1], self.bars and self.bars[2]
	if not bar1 then return false end
	local tray = bar1.hudTray
	local db = self.db
	local want = self.active and db and db.hudTray and db.bars[1].enabled and not self:OriginalArtOn()
	if not want then
		if tray then tray:Hide() end
		return false
	end
	if not tray then
		tray = CreateFrame("Frame", nil, bar1)
		tray:EnableMouse(false)
		bar1.hudTray = tray
		dockHudTray = { header = bar1, frame = tray }
		BindDockPart(tray)
	end
	tray:SetFrameLevel(math.max(bar1:GetFrameLevel() - 2, 0))
	local pad = E.tokens.hudTray.pad
	local top = bar2 and db.bars[2].enabled and bar2 or bar1
	tray:ClearAllPoints()
	tray:SetPoint("BOTTOMLEFT", bar1, "BOTTOMLEFT", -pad, -pad)
	tray:SetPoint("TOPRIGHT", top, "TOPRIGHT", pad, pad)
	-- A see-through panel of the action bar skin; it repaints itself when the
	-- skin changes.
	E:PaintSurface(tray, "panel", "actionbuttons", { transparent = true })
	tray:Show()
	return true
end

-- Exact objects made above, not guessed native texture extents or children.
do
	local function Same(a, b) return not geometrySecret(a) and not geometrySecret(b) and rawequal(a, b) end
	M:RegisterDockPaintSource(function(index)
		local header = M.bars[index]
		if E.Secret(header) or not header then return end
		local original, hud = index == 1 and dockOriginalArt or nil, index == 1 and dockHudTray or nil
		local getters, sources = {}, {}
		local function Include(object)
			local saved = dockGetters[object]
			if not saved or not saved.geometry or not saved.geometry.source() then return false end
			local methods = {};for key, fn in pairs(saved.methods) do methods[key] = fn end
			getters[object], sources[object] = methods, saved;return true
		end
		for _, button in ipairs(header.buttons) do
			local part = styled[button]
			if not part or not Include(part.backdrop) or (part.tint and not Include(part.tint)) then return end
		end
		local function Current()
			if not Same(M.bars[index], header) then return false end
			if index == 1 and (not Same(dockOriginalArt, original) or not Same(dockHudTray, hud)) then return false end
			for object, saved in pairs(sources) do
				if not Same(dockGetters[object], saved) then return false end
				if not saved.geometry.source() then return false end
				for key, fn in pairs(saved.methods) do if not Same(object[key], fn) or not Same(getters[object][key], fn) then return false end end
			end
			if original then
				if not Same(original.header, header) or not Same(header.originalArt, original.frame)
					or E.Secret(original.frame.tray) or type(original.frame.tray) ~= "table"
					or E.Secret(original.frame.caps) or type(original.frame.caps) ~= "table"
					or not Same(original.frame.tray[1], original.tray[1]) or not Same(original.frame.tray[2], original.tray[2])
					or not Same(original.frame.caps.left, original.left) or not Same(original.frame.caps.right, original.right) then return false end
			elseif not Same(header.originalArt, nil) then return false end
			if hud then return Same(hud.header, header) and Same(header.hudTray, hud.frame) end
			return Same(header.hudTray, nil)
		end
		if not Current() then return end
		local parts = {}
		if original then
			parts = { { object = original.frame, parent = header, surface = false },
				{ object = original.tray[1], parent = original.frame, surface = false },
				{ object = original.tray[2], parent = original.frame, surface = false },
				{ object = original.left, parent = original.frame, surface = false },
				{ object = original.right, parent = original.frame, surface = false } }
		end
		if hud then parts[#parts + 1] = { object = hud.frame, parent = header, surface = true } end
		for _, part in ipairs(parts) do if not Include(part.object) then return end end
		return { kind = "live", parts = parts, getters = getters, current = Current }
	end, function()
		local expected, records, sources = paintGeometryEpoch, {}, {}
		for _, saved in pairs(dockGetters) do
			if not saved.geometry then return end
			records[#records + 1] = saved.geometry.capture();sources[#sources + 1] = saved.geometry.source
		end
		local function CurrentGeometry(full)
			if not Same(paintGeometryEpoch, expected) or not Same(rawget(E, "MoverAuthoritySource"), moverGeometrySource) then return false end
			for _, check in ipairs(records) do if not check() then return false end end
			if full then for _, check in ipairs(sources) do if not check() then return false end end end
			return true
		end
		return CurrentGeometry, function(object)
			if geometrySecret(object) then return false end
			local saved = rawget(dockGetters, object)
			return saved and saved.geometry and saved.geometry.source() or false
		end
	end)
end

function M:UpdateBlizzardButtonSkins()
	local active = self.active
	for index = 1, self.NUM_BARS do
		local element = self.BARS[index].element
		local skin = active and self:BlizzardBarShown(index) and E:BlizzardAllowed(element, "skin")
		local text = active and E:BlizzardAllowed(ELEMENT, "skin")
		BlizzardBarButtons(index, function(button)
			if skin then
				self:SkinBlizzardButton(button)
			else
				self:UnskinBlizzardButton(button)
				if text then self:StyleBlizzardText(button) end
			end
			if active and E:BlizzardAllowed(ELEMENT, "improve") and button.cooldown then
				E:StyleCooldownText(button.cooldown, self:CooldownOptions(button:GetWidth(), true))
				styledCooldowns[button.cooldown] = true
			else
				ReleaseCooldownText(button.cooldown)
			end
		end)
		if index == 1 then UpdateMainBarArt(skin) end
	end
	self:UpdateEndCaps()
end

---------------------------------------------------------------------------
-- Blizzard's spell flyout (action-button-look: skin)
---------------------------------------------------------------------------
local flyoutHooked = false
local flyoutSkinned = false
local FLYOUT_ART = { "Start", "End", "HorizontalMiddle", "VerticalMiddle" }

-- Skin Blizzard's flyout while the option and switch allow it; put its art
-- back once when they no longer do.
local function SkinFlyout()
	if InCombatLockdown() or not SpellFlyout then return end
	local want = M.active and M.db.flyoutSkin and E:BlizzardAllowed(ELEMENT, "skin")
	if not want and not flyoutSkinned then return end
	for _, child in ipairs({ SpellFlyout:GetChildren() }) do
		if child.icon and child.GetNormalTexture then
			if want then M:SkinBlizzardButton(child) else M:UnskinBlizzardButton(child) end
		end
	end
	if SpellFlyout.Background then
		for _, key in ipairs(FLYOUT_ART) do
			local region = SpellFlyout.Background[key]
			if region and region.SetAlpha then region:SetAlpha(want and 0 or 1) end
		end
	end
	flyoutSkinned = want and true or false
end

local function HookFlyout()
	if flyoutHooked or not SpellFlyout or not SpellFlyout.Toggle then return end
	flyoutHooked = true
	hooksecurefunc(SpellFlyout, "Toggle", SkinFlyout)
end

---------------------------------------------------------------------------
-- Proc alert overlay (the art around the character) and key-down casting
---------------------------------------------------------------------------
-- Only still-owned fields return to their prior values. A later independent
-- point, scale, alpha or CVar change ends ownership of that field alone.
local procOverlay, procOverlayBusy, procOverlaySerial = nil, false, 0
local procOverlayRequest, procOverlayPending, procOverlayDraining
local procOverlayHolder, procOverlayMover
local PROC_MOVER = "EldoUI_ProcOverlay"
local PROC_DISPLAY, PROC_OPACITY = "displaySpellActivationOverlays", "spellActivationOverlayOpacity"

-- Put the player's own value of a CVar back when the EldoUI option that
-- changed it goes off (E:SetCVar remembered it).
-- Back on "Game setting": the player's own value once, and the record goes,
-- so a later change in the game's own options stays.
function M:RestoreOwnCVar(name, element)
	E:RestoreCVar(name, element)
end

local function OverlayNumber(value)
	return not E:IsSecret(value) and type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function OverlayRead(object, method, ...)
	if E:IsSecret(object) or not object then return end
	return E.PlainCall(object[method], object, ...)
end

local function OverlayPoints(frame)
	local count = OverlayRead(frame, "GetNumPoints")
	if not OverlayNumber(count) or count < 0 or count > 16 or count % 1 ~= 0 then return end
	local points = {}
	for index = 1, count do
		local point, relative, relativePoint, x, y = E.PlainCallAll(frame.GetPoint, frame, index)
		if type(point) ~= "string" or type(relativePoint) ~= "string" or not OverlayNumber(x) or not OverlayNumber(y) then return end
		points[index] = { point, relative, relativePoint, x, y }
	end
	return points
end

local function OverlayEqual(a, b)
	if type(a) ~= "table" or type(b) ~= "table" then return a == b end
	if #a ~= #b then return false end
	for index, row in ipairs(a) do
		for part = 1, 5 do if row[part] ~= b[index][part] then return false end end
	end
	return true
end

local function OverlayFrameOwned(own)
	return own.parent and SpellActivationOverlayFrame == own.frame and own.frame.GetParent == own.parentGetter
		and OverlayRead(own.frame, "GetParent") == own.parent
end

local function OverlayFieldValue(own, key)
	local field = own[key]
	if not OverlayFrameOwned(own) then return end
	for method, fn in pairs(field.methods) do if own.frame[method] ~= fn then return end end
	if key == "points" then return OverlayPoints(own.frame) end
	local value = OverlayRead(own.frame, key == "scale" and "GetScale" or "GetAlpha")
	if not OverlayNumber(value) or (key == "scale" and value <= 0) then return end
	return value
end

local function OverlayAcquireField(own, key)
	if own[key] then return own[key] end
	local methods = key == "points" and { "GetNumPoints", "GetPoint", "ClearAllPoints", "SetPoint" }
		or key == "scale" and { "GetScale", "SetScale" } or { "GetAlpha", "SetAlpha" }
	local field = { methods = {} }
	for _, name in ipairs(methods) do
		if type(own.frame[name]) ~= "function" then return end
		field.methods[name] = own.frame[name]
	end
	own[key] = field
	field.before = OverlayFieldValue(own, key)
	if field.before == nil then own[key] = nil return end
	field.last = field.before
	return field
end

local function OverlayWriteField(own, key, target, current)
	local field = own[key]
	if not current() or not field or field.foreign then return false end
	local value = OverlayFieldValue(own, key)
	if value == nil then return false end
	if not OverlayEqual(value, field.last) then
		if field.pending and OverlayEqual(value, field.pending) then field.last = value
		else field.foreign = true return false end
	end
	field.pending = nil
	if OverlayEqual(value, target) then return current() end
	local frame = own.frame
	local function Write(expected, fn, ...)
		local previous = field.last
		field.pending = expected
		local ok, problem = pcall(fn, frame, ...)
		local observed = OverlayFieldValue(own, key)
		if OverlayEqual(observed, expected) then field.last, field.pending = expected, nil
		elseif observed ~= nil then
			field.pending = nil
			if OverlayEqual(observed, previous) then field.last = previous else field.foreign = true end
		end
		if not ok then error(problem, 0) end
		return current() and not field.foreign and OverlayEqual(observed, expected)
	end
	if key == "points" then
		if not Write({}, frame.ClearAllPoints) then return false end
		for _, row in ipairs(target) do
			local nextPoints = {}
			for index, point in ipairs(field.last) do nextPoints[index] = point end
			nextPoints[#nextPoints + 1] = row
			if not Write(nextPoints, frame.SetPoint, unpack(row, 1, 5)) then return false end
		end
	else
		if not Write(target, frame[key == "scale" and "SetScale" or "SetAlpha"], target) then return false end
	end
	return true
end

local function OverlayCVarApiOwned(field)
	return E:SafeEquals(C_CVar, field.api) and C_CVar.GetCVar == field.get and C_CVar.SetCVar == field.set
end

local function OverlayCVarValue(field)
	if not OverlayCVarApiOwned(field) then return end
	local value = E.PlainCall(field.get, field.name)
	if type(value) ~= "string" then return end
	local number = tonumber(value)
	if not OverlayNumber(number) or number < 0 or number > 1 then return end
	if field.name == PROC_DISPLAY and number ~= 0 and number ~= 1 then return end
	return value
end

local function OverlayCVarLast(field, observed)
	if observed == nil then return false end
	if observed == field.last then field.pending = nil return true end
	if field.pending and tonumber(observed) == tonumber(field.pending) then
		field.last, field.pending = observed, nil
		return true
	end
	return false
end

local function OverlaySnapshotOwned(field)
	return type(getmetatable(field.root)) == "nil" and E:SafeEquals(rawget(_G, "EldoUIDB"), field.root)
		and type(getmetatable(field.snapshot)) == "nil" and type(getmetatable(field.saved)) == "nil"
		and E:SafeEquals(rawget(field.root, "cvarSnapshot"), field.snapshot)
		and E:SafeEquals(rawget(field.snapshot, field.name), field.saved) and E:SafeEquals(rawget(field.saved, "owner"), ELEMENT)
		and E:SafeEquals(rawget(field.saved, "value"), field.savedValue)
end

local function OverlayCVar(own, name, target, current)
	own.cvars = own.cvars or {}
	local field = own.cvars[name]
	if not field then
		if E:IsSecret(C_CVar) or type(C_CVar) ~= "table" or type(C_CVar.GetCVar) ~= "function" or type(C_CVar.SetCVar) ~= "function" then return false end
		if E:IsSecret(EldoUIDB) or type(EldoUIDB) ~= "table" then return false end
		field = { name = name, api = C_CVar, get = C_CVar.GetCVar, set = C_CVar.SetCVar }
		local existing, root = E:GetCVarSnapshot()
		if E:IsSecret(existing) or (existing ~= nil and type(existing) ~= "table") then return false end
		if not root or not OverlayCVarApiOwned(field) or type(getmetatable(root)) ~= "nil"
			or not E:SafeEquals(rawget(_G, "EldoUIDB"), root) or not E:SafeEquals(rawget(root, "cvarSnapshot"), existing)
			or (existing and type(getmetatable(existing)) ~= "nil") then return false end
		local saved = existing and rawget(existing, name)
		if E:IsSecret(saved) or (saved ~= nil and (type(saved) ~= "table" or type(getmetatable(saved)) ~= "nil" or not E:SafeEquals(saved.owner, ELEMENT))) then return false end
		local savedValue = saved and saved.value
		if saved and (E:IsSecret(savedValue) or type(savedValue) ~= "string") then return false end
		field.before = OverlayCVarValue(field)
		if field.before == nil or not current() or not OverlayCVarApiOwned(field)
			or type(getmetatable(root)) ~= "nil" or not E:SafeEquals(rawget(_G, "EldoUIDB"), root)
			or not E:SafeEquals(rawget(root, "cvarSnapshot"), existing) then return false end
		-- The existing owner records the prior value without a setter callback.
		local admitted = false
		E:SetCVar(name, field.before, ELEMENT, function(live)
			admitted = current() and OverlayCVarApiOwned(field) and E:SafeEquals(live, field.before)
				and type(getmetatable(root)) == "nil" and E:SafeEquals(rawget(_G, "EldoUIDB"), root) and E:SafeEquals(rawget(root, "cvarSnapshot"), existing)
				and (not existing or type(getmetatable(existing)) == "nil") and E:SafeEquals(existing and rawget(existing, name), saved)
				and (not saved or (type(getmetatable(saved)) == "nil" and E:SafeEquals(saved.owner, ELEMENT) and E:SafeEquals(saved.value, savedValue)))
			return admitted
		end)
		if not admitted then return false end
		local snapshot, snapshotRoot = E:GetCVarSnapshot()
		if not current() or not OverlayCVarApiOwned(field) or not E:SafeEquals(root, snapshotRoot)
			or E:IsSecret(snapshot) or type(snapshot) ~= "table" or type(getmetatable(snapshot)) ~= "nil" then return false end
		saved = rawget(snapshot, name)
		if E:IsSecret(saved) or type(saved) ~= "table" or type(getmetatable(saved)) ~= "nil" or not E:SafeEquals(rawget(saved, "owner"), ELEMENT)
			or E:IsSecret(rawget(saved, "value")) or type(rawget(saved, "value")) ~= "string" then return false end
		field.snapshot, field.saved, field.root = snapshot, saved, root
		field.savedValue = rawget(saved, "value")
		if not OverlaySnapshotOwned(field) then return false end
		field.last = field.before
		own.cvars[name] = field
	end
	if field.foreign or not current() then return false end
	if not OverlaySnapshotOwned(field) then field.foreign = true return false end
	local live = OverlayCVarValue(field)
	if live == nil then return false end
	if not OverlayCVarLast(field, live) then field.foreign = true return false end
	local previous = field.last
	local admitted = false
	local ok, problem = pcall(E.SetCVar, E, name, target, ELEMENT, function(observed)
		if not current() or not OverlayCVarApiOwned(field) or not OverlaySnapshotOwned(field) then return false end
		if not OverlayCVarLast(field, observed) then field.foreign = true return false end
		previous, field.pending, admitted = field.last, target, true
		return true
	end)
	if not admitted then
		if not ok then error(problem, 0) end
		return false
	end
	local observed = OverlayCVarValue(field)
	if observed and tonumber(observed) == tonumber(target) then field.last, field.pending = observed, nil
	elseif observed ~= nil then
		field.pending = nil
		if observed == previous then field.last = previous else field.foreign = true end
	end
	if not ok then error(problem, 0) end
	if not observed or tonumber(observed) ~= tonumber(target) then return false end
	if not current() or not OverlayCVarApiOwned(field) or not OverlaySnapshotOwned(field) then return false end
	return true
end

local function OverlayRelease(own, geometry, display)
	local problem, qualified = nil, true
	local function Step(fn)
		local ok, why = pcall(fn)
		if not ok then problem = problem or why end
	end
	local function Current() return procOverlay == own and E.modules.ActionBars == M end
	if geometry then
		for _, key in ipairs({ "points", "scale", "alpha" }) do
			Step(function()
				local field = own[key]
				if field then
					if field.foreign then own[key] = nil
					elseif not OverlayFrameOwned(own) then
						qualified = false
						local parent = OverlayRead(own.frame, "GetParent")
						if SpellActivationOverlayFrame ~= own.frame or (parent and parent ~= own.parent) then own[key] = nil end
					elseif OverlayFieldValue(own, key) ~= nil then
						if OverlayWriteField(own, key, field.before, Current) or field.foreign then own[key] = nil end
					end
				end
			end)
		end
		Step(function()
			local mover = E.movers[PROC_MOVER]
			if own.holder and M.procHolder == own.holder and (not mover or (mover == own.mover and mover.frame == own.holder)) then
				if mover then M:SetMoverActive(PROC_MOVER, false) end
				if Current() and M.procHolder == own.holder and E.movers[PROC_MOVER] == mover and (not mover or mover.frame == own.holder) then own.holder:Hide() end
			end
		end)
	end
	for _, name in ipairs({ PROC_DISPLAY, PROC_OPACITY }) do
		if (name == PROC_DISPLAY and display) or (name == PROC_OPACITY and geometry) then
			Step(function()
				local field = own.cvars and own.cvars[name]
				if not field or not Current() then return end
				if OverlaySnapshotOwned(field) then
					if not OverlayCVarApiOwned(field) then
						field.snapshot[name] = nil
						own.cvars[name] = nil
						qualified = false
						return
					end
					local observed = OverlayCVarValue(field)
					if observed == nil then return end
					if not Current() or not OverlayCVarApiOwned(field) or not OverlaySnapshotOwned(field) then qualified = false return end
					if not field.foreign and OverlayCVarLast(field, observed) and tonumber(observed) ~= tonumber(field.before) then
						field.pending = field.before
						local ok, why = pcall(field.set, name, field.before)
						local after = OverlayCVarValue(field)
						if after and tonumber(after) == tonumber(field.before) then field.last, field.pending = after, nil
						elseif after ~= nil then
							field.pending = nil
							if after ~= observed then field.foreign = true end
						end
						if not ok then error(why, 0) end
						if not Current() then return end
						if not OverlaySnapshotOwned(field) or not OverlayCVarApiOwned(field) then qualified = false end
						if OverlaySnapshotOwned(field) and OverlayCVarApiOwned(field) and not field.foreign
							and (after == nil or tonumber(after) ~= tonumber(field.before)) then return end
					end
					-- Do not leave a stale global restorer for a relinquished CVar.
					if Current() and OverlaySnapshotOwned(field) then
						field.snapshot[name] = nil
					end
				end
				own.cvars[name] = nil
			end)
		end
	end
	if problem then error(problem, 0) end
	return qualified and not (own.creating and not own.mover and E.movers[PROC_MOVER])
		and (not geometry or (not own.points and not own.scale and not own.alpha and not (own.cvars and own.cvars[PROC_OPACITY])))
		and (not display or not (own.cvars and own.cvars[PROC_DISPLAY]))
end

local function OverlaySameRequest(a, b)
	if not b then return false end
	for _, key in ipairs({ "profile", "db", "settings", "frame", "active", "scale", "alpha", "on", "move", "hide", "holder", "mover" }) do
		if not E:SafeEquals(a[key], b[key]) then return false end
	end
	return true
end

local function UpdateProcOverlay()
	local profile, db, frame = E.db, M.db, SpellActivationOverlayFrame
	local settings = not E:IsSecret(db) and type(db) == "table" and db.proc
	local active = M.active
	if E:IsSecret(settings) or type(settings) ~= "table" then procOverlaySerial = procOverlaySerial + 1 return false end
	local scale, alpha = settings.scale, settings.alpha
	local on = active and E:BlizzardAllowed(ELEMENT) and not E:StandsBack(M, "procOverlay")
	local move, hide = on and E:BlizzardAllowed(ELEMENT, "move"), on and E:BlizzardAllowed(ELEMENT, "hide")
	local expectedHolder, expectedMover = M.procHolder, E.movers[PROC_MOVER]
	local request = { profile = profile, db = db, settings = settings, frame = frame, active = active,
		scale = scale, alpha = alpha, on = on, move = move, hide = hide, holder = expectedHolder, mover = expectedMover }
	if procOverlayBusy and procOverlaySerial == procOverlayRequest.serial and OverlaySameRequest(request, procOverlayRequest) then return false end
	procOverlaySerial = procOverlaySerial + 1
	local serial = procOverlaySerial
	request.serial = serial
	local boundHolder, boundMover
	local function Current()
		return serial == procOverlaySerial and E.modules.ActionBars == M and E.db == profile and M.db == db
			and db.proc == settings and M.active == active and SpellActivationOverlayFrame == frame
			and E:SafeEquals(settings.scale, scale) and E:SafeEquals(settings.alpha, alpha)
			and (active and E:BlizzardAllowed(ELEMENT) and not E:StandsBack(M, "procOverlay")) == on
			and (on and E:BlizzardAllowed(ELEMENT, "move")) == move and (on and E:BlizzardAllowed(ELEMENT, "hide")) == hide
			and M.procHolder == expectedHolder and E.movers[PROC_MOVER] == expectedMover
			and (not boundHolder or (M.procHolder == boundHolder and E.movers[PROC_MOVER] == boundMover and boundMover.frame == boundHolder))
	end
	if procOverlayBusy then
		procOverlayPending = function() if Current() then return UpdateProcOverlay() end return false end
		return false
	end
	procOverlayPending = nil
	local applied = false
	local ran = E:RunOutOfCombat(function()
		if not Current() then return end
		procOverlayBusy, procOverlayRequest = true, request
		local own = procOverlay or { frame = frame, parent = frame and OverlayRead(frame, "GetParent"), parentGetter = frame and frame.GetParent }
		procOverlay = own
		local ok, problem = pcall(function()
			local released = OverlayRelease(own, not move, not hide)
			if not Current() then return end
			if not move and not hide then
				if released then procOverlay = nil end
				applied = released
				return
			end
			if not own.frame and frame then own.frame, own.parent, own.parentGetter = frame, OverlayRead(frame, "GetParent"), frame.GetParent end
			local display = not hide or OverlayCVar(own, PROC_DISPLAY, "0", Current)
			if not move then applied = display and released return end
			if not frame or own.frame ~= frame or not OverlayFrameOwned(own) then return end
			if M.procHolder ~= procOverlayHolder or E.movers[PROC_MOVER] ~= procOverlayMover then return end
			if not OverlayNumber(settings.scale) or not OverlayNumber(settings.alpha) then return end
			for _, key in ipairs({ "points", "scale", "alpha" }) do if not OverlayAcquireField(own, key) then return end end
			if not E.movers[PROC_MOVER] then
				-- A failed constructor may have allocated its named frame before
				-- registration. Its absence from the registry is not ownership.
				if rawget(_G, PROC_MOVER .. "Mover") then return end
				local width, height = OverlayRead(frame, "GetWidth"), OverlayRead(frame, "GetHeight")
				if not OverlayNumber(width) or not OverlayNumber(height) or width <= 0 or height <= 0 then return end
				local holder = M.procHolder
				if not holder then
					holder = CreateFrame("Frame", "EldoUI_ProcOverlayHolder", UIParent)
					if not Current() or M.procHolder then return end
					M.procHolder, own.holder, expectedHolder = holder, holder, holder
					procOverlayHolder, request.holder = holder, holder
					holder.eldoMover = PROC_MOVER
					holder:SetSize(width, height)
					if not Current() then return end
					holder:Hide()
				elseif own.holder ~= holder then return end
				if not Current() or M.procHolder ~= holder then return end
				own.creating = true
				local created = E:CreateMover(holder, PROC_MOVER, L["Proc Alerts"], { "CENTER", "UIParent", "CENTER", 0, 0 })
				if E:IsSecret(created) or not created or created.frame ~= holder then return end
				own.mover, expectedMover, own.creating = created, created, nil
				procOverlayMover, request.mover = created, created
				if not Current() or M.procHolder ~= holder then return end
			end
			local holder, mover = M.procHolder, E.movers[PROC_MOVER]
			if own.creating and not own.mover then return end
			if not holder or not mover or mover.frame ~= holder or (own.holder and own.holder ~= holder) or (own.mover and own.mover ~= mover) then return end
			own.holder, own.mover = holder, mover
			boundHolder, boundMover = holder, mover
			M:SetMoverActive(PROC_MOVER, true)
			if not Current() or M.procHolder ~= holder or E.movers[PROC_MOVER] ~= mover then return end
			holder:Show()
			if not OverlayWriteField(own, "points", { { "CENTER", holder, "CENTER", 0, 0 } }, Current) then return end
			if not OverlayWriteField(own, "scale", M.Clamp(settings.scale, 50, 200, 100) / 100, Current) then return end
			local targetAlpha = M.Clamp(settings.alpha, 0, 100, 100) / 100
			local opacity = OverlayCVar(own, PROC_OPACITY, tostring(targetAlpha), Current)
			local alphaSet = OverlayWriteField(own, "alpha", targetAlpha, Current)
			applied = display and released and opacity and alphaSet
		end)
		if not ok or not Current() then pcall(OverlayRelease, own, true, true) end
		procOverlayBusy, procOverlayRequest = false, nil
		-- One bounded follow-up owns the latest explicit changed request. A
		-- nonconverging callback stays pending instead of recursing forever.
		if procOverlayPending and not procOverlayDraining then
			local retry = procOverlayPending
			procOverlayPending, procOverlayDraining = nil, true
			local retryOK, result = pcall(retry)
			procOverlayDraining = false
			applied = retryOK and result == true and not procOverlayPending
			if not retryOK and ok then ok, problem = false, result end
		end
		if not ok then error(problem, 0) end
	end, "ActionBars:proc-overlay")
	return ran and applied
end

function M:RefreshProcOverlay()
	return UpdateProcOverlay()
end

-- Casting on key press is the game's secure ActionButtonUseKeyDown
-- setting: no addon may change it, so the Action Bars page only shows it
-- and builds the player's own chat command. An entry an older version kept
-- for it changed nothing and is dropped.
local function UpdateKeyDown()
	E:ForgetCVar("ActionButtonUseKeyDown", ELEMENT)
end

-- Locked bars and the pick-up key. Both are the game's own settings
-- (Options > Action Bars: "Lock action bars" and "Pick up action key");
-- EldoUI only writes them when the player picks a value here, and EldoUI's
-- buttons always follow them, like Blizzard's.
local PICKUP_KEYS = { SHIFT = true, CTRL = true, ALT = true }

-- Older versions put the saved value back on every pass and never dropped
-- it. A record still there at the first pass of a session on "Game
-- setting" is such a leftover: it is dropped without writing, so the
-- player's own later choice stays.
local lockChecked
local function UpdateLock()
	local allowed = M.active and E:BlizzardAllowed(ELEMENT, "improve")
	local lock = allowed and M.db.lockBars or "game"
	local first = not lockChecked
	lockChecked = true
	if lock == "locked" then
		E:SetCVar("lockActionBars", "1", ELEMENT)
	elseif lock == "unlocked" then
		E:SetCVar("lockActionBars", "0", ELEMENT)
	elseif first then
		E:ForgetCVar("lockActionBars", ELEMENT)
	elseif E:BlizzardAllowed(ELEMENT) then
		M:RestoreOwnCVar("lockActionBars", ELEMENT)
	end
	local key = allowed and M.db.pickupKey
	if PICKUP_KEYS[key] and GetModifiedClick and SetModifiedClick and GetModifiedClick("PICKUPACTION") ~= key then
		SetModifiedClick("PICKUPACTION", key)
		if SaveBindings and GetCurrentBindingSet then SaveBindings(GetCurrentBindingSet()) end
	end
	if M.active then M:UpdateButtonLock() end
end

---------------------------------------------------------------------------
-- Apply
---------------------------------------------------------------------------
function M:ApplyLook()
	if self.active then
		self:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", GlowEvent)
		self:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", GlowEvent)
		self:UpdateMasque()
		ForEachButton(function(button)
			HideGlow(button)
			RefreshGlow(button)
		end)
		HookFlyout()
		for _, event in ipairs(COOLDOWN_EVENTS) do self:RegisterEvent(event, CooldownEvent) end
		ForEachButton(function(button) self:StyleChargeCooldown(button, true) end)
	else
		self:UnregisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
		self:UnregisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
		ForEachButton(HideGlow)
		for _, event in ipairs(COOLDOWN_EVENTS) do self:UnregisterEvent(event) end
	end
	self:UpdateBlizzardButtonSkins()
	SkinFlyout()
	UpdateProcOverlay()
	UpdateKeyDown()
	UpdateLock()
end

local function ReapplyLook()
	if M.active then M:ApplyLook() end
end

E:RegisterBlizzardHandler(ELEMENT, {
	owner = "ActionBars",
	apply = ReapplyLook,
	undo = ReapplyLook,
	reload = { skin = true, move = true },
	install = { skin = true, improve = true },
	legacy = function() return M.db.enabled end,
	refreshModule = false,
})
