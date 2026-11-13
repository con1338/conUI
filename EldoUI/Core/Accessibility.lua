-- EldoUI accessibility: one place that makes EldoUI easier to read,
-- to hear and to follow. General > Accessibility offers five switches,
-- each built on the shared look systems instead of a look of its own:
--
--   High contrast   the "High contrast" art style (Core/Media.lua: black,
--                   opaque panels with 2-pixel white borders) and the thick
--                   text outline. Turning it off puts back the art style and
--                   outline you had.
--   Large text      one scale (100-160 %) for every EldoUI text through
--                   E:SetFont / E:CreateText (general.textScale).
--   Color-blind     safe colors from the Okabe-Ito set (E.tokens.palette
--                   .safe) for reactions, threat, dispel types, unit states,
--                   heal prediction and the good / warning / bad text tokens,
--                   per kind (protan, deutan, tritan). Off, on, or follow the
--                   game's own color-blind mode (the colorblindMode CVar is
--                   read, never changed). Colors the player picked on the
--                   Colors page still win. Class colors stay the game's (a
--                   class is a name, not a meaning), and every color with a
--                   meaning also carries a word or a shape (DESIGN.md §2,
--                   E:StatusMark).
--   Sound cues      distinct sounds through Fanfare for
--                   moments the game announces: ready check, whisper, enter
--                   combat, loss of control, raid warning and death. Low
--                   health and aggro are not offered: on Forever a unit's
--                   health and threat are secret values, and a sound chosen
--                   from them would compute hidden combat data.
--   Reduce motion   General > Animations the other way round (one saved
--                   setting, Core/Animation.lua): glows, pulses and slides
--                   hold still and every highlight stays.
--
-- "Undo" puts back the switches (and what they changed) from before the
-- last change made on this page. The installer offers the first three as
-- an optional step with nothing ticked (Core/Installer.lua, "access").
local _, E = ...
local L = E.L

E.defaults.general.access = {
	highContrast = false,
	largeText = false,
	textScale = 1.3,          -- the scale Large text uses
	colorBlind = "off",       -- off | on | game
	colorBlindType = "deutan", -- protan | deutan | tritan
	shapeMarks = true,        -- a word or shape next to colors with a meaning
	soundCues = false,
	cues = {
		readycheck = "kit:READY_CHECK", whisper = "eldo:Glass", combatstart = "eldo:Whoosh",
		losscontrol = "eldo:EldoWarning", raidwarning = "kit:RAID_WARNING", death = "eldo:OhNo",
	},
}

-- The cue list: Fanfare source = label. Order as shown.
E.ACCESS_CUES = {
	{ key = "readycheck", label = "Ready check", desc = "A ready check starts." },
	{ key = "whisper", label = "Whisper", desc = "Someone whispers you." },
	{ key = "combatstart", label = "Enter combat", desc = "You enter combat: something attacks you, or you attack." },
	{ key = "losscontrol", label = "Loss of control", desc = "You are stunned, feared, rooted or silenced (the game's loss of control alert)." },
	{ key = "raidwarning", label = "Raid warning", desc = "A raid warning appears in the middle of the screen." },
	{ key = "death", label = "You die", desc = "Your character dies." },
}

local function Access()
	local general = E.db and E.db.general
	return general and general.access or E.defaults.general.access
end

---------------------------------------------------------------------------
-- Color-blind safe colors
---------------------------------------------------------------------------
local SAFE = E.tokens.palette.safe

-- Per kind: the colors that carry a meaning. Okabe-Ito colors stay apart
-- for every kind; green and blue swap where a kind confuses them.
local function Palette(kind)
	local good = kind == "tritan" and SAFE.green or SAFE.sky
	local friendly = kind == "tritan" and SAFE.green or SAFE.blue
	return {
		text = { good = good, warn = SAFE.orange, bad = SAFE.vermilion },
		reaction = { [1] = SAFE.vermilion, [2] = SAFE.vermilion, [3] = SAFE.orange, [4] = SAFE.yellow,
			[5] = friendly, [6] = friendly, [7] = friendly, [8] = friendly },
		threat = { [0] = SAFE.gray, [1] = SAFE.yellow, [2] = SAFE.orange, [3] = SAFE.vermilion },
		dispel = { Magic = SAFE.sky, Curse = SAFE.purple, Disease = SAFE.orange, Poison = SAFE.green,
			Bleed = SAFE.vermilion, None = SAFE.vermilion },
		status = { lowHealth = SAFE.vermilion, lowPower = SAFE.orange, trail = SAFE.vermilion, execute = SAFE.orange,
			offTank = SAFE.purple, gradientLow = SAFE.vermilion, gradientMid = SAFE.yellow, gradientHigh = good },
		prediction = { healMine = SAFE.sky, healOther = SAFE.blue, healAbsorb = SAFE.vermilion },
	}
end
E.AccessibilityPalette = Palette

-- The game's own color-blind mode (read only).
function E:GameColorBlindMode()
	local get = C_CVar and C_CVar.GetCVar
	local value = get and get("colorblindMode")
	if issecretvalue and issecretvalue(value) then return false end
	return value ~= nil and value ~= "0" and value ~= ""
end

function E:ColorBlindActive()
	local mode = Access().colorBlind
	if mode == "on" then return true end
	if mode == "game" then return self:GameColorBlindMode() end
	return false
end

-- The text tokens keep their tables (code holds references to them), so
-- the safe colors are written in place and the originals kept here.
local originalText = {
	good = { unpack(E.tokens.text.good) }, warn = { unpack(E.tokens.text.warn) }, bad = { unpack(E.tokens.text.bad) },
}

local function SetToken(key, color)
	local token = E.tokens.text[key]
	token[1], token[2], token[3] = color[1], color[2], color[3]
end

-- Code that keeps status colors as ready-made |cff strings registers a
-- refresh here: fn runs at once and again each time the safe colors are
-- switched, so those strings never keep the colors read at load.
local statusColorWatchers = {}
function E:OnStatusColors(fn)
	statusColorWatchers[#statusColorWatchers + 1] = fn
	fn()
end

function E:UpdateColorBlind()
	if self:ColorBlindActive() then
		local palette = Palette(Access().colorBlindType)
		self.colorBlindPalette = palette
		for key, color in pairs(palette.text) do SetToken(key, color) end
	else
		self.colorBlindPalette = nil
		for key, color in pairs(originalText) do SetToken(key, color) end
	end
	for _, fn in ipairs(statusColorWatchers) do
		local ok, err = pcall(fn)
		if not ok then geterrorhandler()(err) end
	end
	if self.UpdateColors then self:UpdateColors() end
end

-- A word or shape next to a color with a meaning (DESIGN.md §2): "+" good,
-- "!" warning, "x" bad. Empty while shape marks are off.
local MARKS = { good = "+", warn = "!", bad = "x" }
function E:StatusMark(kind)
	if Access().shapeMarks == false then return "" end
	return MARKS[kind] or ""
end

-- Text in a status color with its mark: E:StatusText("bad", "Missing").
function E:StatusText(kind, text)
	local color = self.tokens.text[kind] or self.tokens.text.body
	local mark = self:StatusMark(kind)
	return self:TokenHex(color) .. (mark ~= "" and (mark .. " ") or "") .. tostring(text) .. "|r"
end

---------------------------------------------------------------------------
-- High contrast, large text, sound cues: applied from the switches
---------------------------------------------------------------------------
-- What a switch changed, so turning it off puts it back (saved per profile).
local function Backup()
	local general = E.db.general
	if type(general.accessBackup) ~= "table" then general.accessBackup = {} end
	return general.accessBackup
end

local function Fanfare()
	local module = E:GetModule("Fanfare")
	if module and module.db and type(module.db.triggers) == "table" then return module end
end

local function ApplyContrast(on)
	local general, backup = E.db.general, Backup()
	if on and not backup.contrast then
		backup.contrast = { artStyle = general.artStyle, fontOutline = general.fontOutline }
		general.artStyle = "Contrast"
		general.fontOutline = "THICKOUTLINE"
		return true
	elseif not on and backup.contrast then
		local old = backup.contrast
		backup.contrast = nil
		-- Only what is still ours goes back; a style picked since stays.
		if general.artStyle == "Contrast" then general.artStyle = old.artStyle or "Modern" end
		if general.fontOutline == "THICKOUTLINE" then general.fontOutline = old.fontOutline or "OUTLINE" end
		return true
	end
	return false
end

local function ApplyCues(on)
	local backup = Backup()
	local module = Fanfare()
	if on then
		if not module then return false end
		-- Fanfare plays the cues: switch it on first.
		if not backup.cues and not module.active then
			backup.cues = { fanfareWasOn = false, triggers = {} }
			E:SetModuleEnabled("Fanfare", true)
		end
		if module.Seed then module:Seed() end
		backup.cues = backup.cues or { fanfareWasOn = true, triggers = {} }
		local cues = Access().cues
		for _, cue in ipairs(E.ACCESS_CUES) do
			local trigger = module.db.triggers[cue.key]
			if type(trigger) == "table" and type(trigger.actions) == "table" then
				if not backup.cues.triggers[cue.key] then
					backup.cues.triggers[cue.key] = {
						enabled = trigger.enabled, deleted = trigger.deleted, allowInCombat = trigger.allowInCombat,
						sound = CopyTable(trigger.actions.sound or {}),
					}
				end
				trigger.enabled, trigger.deleted, trigger.allowInCombat = true, nil, true
				trigger.actions.sound = trigger.actions.sound or {}
				trigger.actions.sound.id = cues[cue.key] or trigger.actions.sound.id
			end
		end
		if module.active and module.Rebuild then module:Rebuild() end
		return true
	elseif backup.cues then
		local old = backup.cues
		backup.cues = nil
		if module then
			for key, saved in pairs(old.triggers or {}) do
				local trigger = module.db.triggers[key]
				if type(trigger) == "table" then
					trigger.enabled, trigger.deleted, trigger.allowInCombat = saved.enabled, saved.deleted, saved.allowInCombat
					if type(trigger.actions) == "table" then trigger.actions.sound = CopyTable(saved.sound or {}) end
				end
			end
			if module.active and module.Rebuild then module:Rebuild() end
		end
		if old.fanfareWasOn == false then E:SetModuleEnabled("Fanfare", false) end
		return true
	end
	return false
end

-- Bring everything in line with the switches. Theme parts repaint at once.
function E:ApplyAccessibility()
	if not (self.db and self.db.general) then return end
	local access = Access()
	local themeChanged = ApplyContrast(access.highContrast == true)
	local scale = access.largeText and math.max(1, math.min(1.6, tonumber(access.textScale) or 1.3)) or 1
	if self.db.general.textScale ~= scale then
		self.db.general.textScale = scale
		themeChanged = true
	end
	ApplyCues(access.soundCues == true)
	self:UpdateColorBlind()
	if themeChanged and self.RefreshTheme then self:RefreshTheme() end
end

-- Undo: the switches as they were before the last change here.
local SWITCH_KEYS = { "highContrast", "largeText", "textScale", "colorBlind", "colorBlindType", "shapeMarks", "soundCues" }
local function Snapshot()
	local copy = {}
	for _, key in ipairs(SWITCH_KEYS) do copy[key] = Access()[key] end
	copy.cues = CopyTable(Access().cues)
	copy.reduceMotion = E.MotionOn and not E:MotionOn() or false
	return copy
end
local before    -- switches before the page's last change
local shown     -- switches as the page last applied them

function E:AccessibilityChanged()
	local now = Snapshot()
	if shown and not E.DeepEqual(now, shown) then before = shown end
	shown = now
	self:ApplyAccessibility()
end

function E:CanUndoAccessibility()
	return before ~= nil
end

function E:UndoAccessibility()
	if not before then return false end
	local access = self.db.general.access
	for _, key in ipairs(SWITCH_KEYS) do access[key] = before[key] end
	access.cues = CopyTable(before.cues)
	if E.SetReduceMotion then E:SetReduceMotion(before.reduceMotion) end
	before = nil
	shown = Snapshot()
	self:ApplyAccessibility()
	return true
end

-- Presets: Default, High contrast, Large text, Color-blind safe,
-- Everything. Each writes the four switches; Default and Everything also
-- set Reduce motion.
E.ACCESS_PRESETS = {
	{ key = "default", title = "Default", desc = "Every switch off: EldoUI's normal look, sounds and motion.",
		values = { highContrast = false, largeText = false, colorBlind = "off", soundCues = false, reduceMotion = false } },
	{ key = "contrast", title = "High contrast", desc = "Black opaque panels with bright borders and a thick text outline.",
		values = { highContrast = true, largeText = false, colorBlind = "off", soundCues = false } },
	{ key = "large", title = "Large text", desc = "Every EldoUI text at 130 %.",
		values = { highContrast = false, largeText = true, textScale = 1.3, colorBlind = "off", soundCues = false } },
	{ key = "colorblind", title = "Color-blind safe", desc = "Safe colors with shape marks, always on.",
		values = { highContrast = false, largeText = false, colorBlind = "on", shapeMarks = true, soundCues = false } },
	{ key = "everything", title = "Everything", desc = "High contrast, large text, safe colors, sound cues and reduced motion together.",
		values = { highContrast = true, largeText = true, textScale = 1.4, colorBlind = "on", shapeMarks = true, soundCues = true, reduceMotion = true } },
}

function E:ApplyAccessibilityPreset(key)
	for _, preset in ipairs(self.ACCESS_PRESETS) do
		if preset.key == key then
			local access = self.db.general.access
			for field, value in pairs(preset.values) do
				-- Reduce motion is General > Animations (Core/Animation.lua).
				if field == "reduceMotion" then
					if E.SetReduceMotion then E:SetReduceMotion(value) end
				else
					access[field] = value
				end
			end
			self:AccessibilityChanged()
			return true
		end
	end
	return false
end

-- Reduce motion is General > Animations the other way round: one saved
-- setting, shown on both pages.
local motionRoot = setmetatable({}, {
	__index = function(_, key)
		if key == "reduceMotion" then return E.MotionOn and not E:MotionOn() or false end
	end,
	__newindex = function(_, key, value)
		if key == "reduceMotion" and E.SetReduceMotion then E:SetReduceMotion(value and true or false) end
	end,
})
local function MotionRoot() return motionRoot end

---------------------------------------------------------------------------
-- Preview: a panel in the chosen look, text at the chosen size, and the
-- status and reaction colors with their marks.
---------------------------------------------------------------------------
local function CreatePreview(frame)
	if not frame then return end
	local panel = CreateFrame("Frame", nil, frame)
	panel:SetSize(280, 76)
	panel:SetPoint("LEFT", 4, 0)
	frame.panel = panel
	frame.title = E:CreateText(panel, E.tokens.size.dialogTitle, "LEFT")
	frame.title:SetPoint("TOPLEFT", 10, -8)
	frame.body = E:CreateText(panel, E.tokens.size.body, "LEFT")
	frame.body:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -4)
	frame.swatches = {}
	for index = 1, 6 do
		local swatch = CreateFrame("Frame", nil, frame)
		swatch:SetSize(86, 20)
		swatch:SetPoint("TOPLEFT", panel, "TOPRIGHT", 16 + ((index - 1) % 3) * 92, -8 - math.floor((index - 1) / 3) * 28)
		swatch.text = E:CreateText(swatch, E.tokens.size.label, "CENTER")
		swatch.text:SetPoint("CENTER")
		frame.swatches[index] = swatch
	end
end

local function UpdatePreview(frame)
	if not (frame and frame.panel) then return end
	local access = Access()
	local style = access.highContrast and "Contrast" or (E.db.general.accessBackup and E.db.general.accessBackup.contrast
		and E.db.general.accessBackup.contrast.artStyle) or E.db.general.artStyle
	E:PaintArtStyleSample(frame.panel, style)
	local scale = access.largeText and (tonumber(access.textScale) or 1.3) or 1
	local outline = access.highContrast and "THICKOUTLINE" or E.db.general.fontOutline
	frame.title:SetFont(E.media.fontHeader, E.tokens.size.dialogTitle * scale, outline or "")
	frame.title:SetText(L["Easy to read"])
	frame.title:SetTextColor(E:TokenColor("accent"))
	frame.body:SetFont(E.media.font, E.tokens.size.body * scale, outline or "")
	frame.body:SetText(L["Body text at this size."])
	frame.body:SetTextColor(unpack(E.tokens.text.body))
	local palette = (access.colorBlind == "on" or (access.colorBlind == "game" and E:GameColorBlindMode())) and Palette(access.colorBlindType)
	local items = {
		{ "good", L["Good"] }, { "warn", L["Warning"] }, { "bad", L["Bad"] },
		{ "hostile", L["Hostile"] }, { "neutral", L["Neutral"] }, { "friendly", L["Friendly"] },
	}
	for index, item in ipairs(items) do
		local swatch = frame.swatches[index]
		local r, g, b
		if index <= 3 then
			local color = palette and palette.text[item[1]] or originalText[item[1]]
			r, g, b = color[1], color[2], color[3]
		else
			local reaction = ({ hostile = 2, neutral = 4, friendly = 5 })[item[1]]
			local color = palette and palette.reaction[reaction]
			if color then r, g, b = color[1], color[2], color[3] else r, g, b = E:GameColor("reaction", reaction) end
		end
		E:SetTemplate(swatch)
		swatch:SetBackdropBorderColor(r or 1, g or 1, b or 1, 1)
		local mark = index <= 3 and access.shapeMarks ~= false and MARKS[item[1]] or ""
		swatch.text:SetText((mark ~= "" and (mark .. " ") or "") .. item[2])
		swatch.text:SetTextColor(r or 1, g or 1, b or 1)
	end
end

---------------------------------------------------------------------------
-- General > Accessibility
---------------------------------------------------------------------------
local function SoundCueRows()
	local rows = {}
	for _, cue in ipairs(E.ACCESS_CUES) do
		rows[#rows + 1] = { type = "media", key = "cues." .. cue.key, label = cue.label, mediaKind = "sound", dependsOn = "soundCues",
			desc = L["Sound when: %s"]:format(L[cue.desc]) }
	end
	return rows
end

local function BuildRows()
	local rows = {
		{ type = "preview", label = "Preview", height = 92, create = CreatePreview, update = UpdatePreview },
		{ type = "description", label = "Make EldoUI easier to read, to hear and to follow. Each switch works on its own; Undo puts back what you had before the last change." },
		{ type = "header", label = "Presets" },
	}
	for _, preset in ipairs(E.ACCESS_PRESETS) do
		rows[#rows + 1] = { type = "execute", label = preset.title, desc = preset.desc, width = 200,
			func = function()
				E:ApplyAccessibilityPreset(preset.key)
				if E.ConfigNotice then E:ConfigNotice(L["Accessibility preset %s applied."]:format(L[preset.title])) end
				if E.RefreshConfig then E:RefreshConfig() end
			end }
	end
	rows[#rows + 1] = { type = "execute", label = "Undo", width = 200,
		desc = "Put back the switches from before the last change on this page.",
		disabled = function() return not E:CanUndoAccessibility() and L["Nothing to undo yet."] end,
		func = function()
			if E:UndoAccessibility() and E.ConfigNotice then E:ConfigNotice(L["Accessibility settings put back."]) end
			if E.RefreshConfig then E:RefreshConfig() end
		end }
	local more = {
		{ type = "header", label = "Reading" },
		{ type = "toggle", key = "highContrast", label = "High contrast",
			desc = "Black opaque panels with bright 2-pixel borders (the High contrast art style) and a thick outline on every EldoUI text. Off puts back the art style and outline you had." },
		{ type = "toggle", key = "largeText", label = "Large text",
			desc = "Every EldoUI text grows by the scale below." },
		{ type = "range", percent = true, key = "textScale", label = "Text scale", min = 1, max = 1.6, step = 0.05, dependsOn = "largeText",
			desc = "How much bigger EldoUI's text gets with Large text on, from 100 to 160 %." },
		{ type = "header", label = "Colors" },
		{ type = "select", key = "colorBlind", label = "Color-blind safe colors", order = { "off", "game", "on" },
			values = { off = "Off", game = "Follow the game", on = "On" },
			desc = "Color-blind safe colors for reactions, threat, dispel types, unit states and status text. Follow the game uses them while the game's color-blind mode is on. Your own picked colors stay." },
		{ type = "select", key = "colorBlindType", label = "Kind", order = { "deutan", "protan", "tritan" },
			values = { deutan = "Deuteranopia (green)", protan = "Protanopia (red)", tritan = "Tritanopia (blue)" },
			hidden = function() return Access().colorBlind == "off" end,
			desc = "Which colors you mix up. Red and green kinds get blue for good and friendly; the blue kind gets green." },
		{ type = "toggle", key = "shapeMarks", label = "Shape marks",
			desc = "Put a mark next to colors that mean something: + good, ! warning, x bad, so color alone never carries the meaning." },
		{ type = "header", label = "Motion" },
		{ type = "toggle", key = "reduceMotion", root = MotionRoot, label = "Reduce motion",
			desc = "Glows, pulses and sliding windows hold still; highlights stay as a steady border in their color. For players who get dizzy or distracted by moving parts. Same switch as General > Animations." },
		{ type = "header", label = "Sound cues" },
		{ type = "toggle", key = "soundCues", label = "Enable",
			desc = "Plays a distinct sound for each moment below, through Fanfare. Low health and aggro have no cue: Forever hides them from addons. Off puts back the triggers you had." },
	}
	for _, row in ipairs(more) do rows[#rows + 1] = row end
	for _, row in ipairs(SoundCueRows()) do rows[#rows + 1] = row end
	return rows
end

E:RegisterEvent("PLAYER_LOGIN", function()
	shown = Snapshot()
	E:ApplyAccessibility()
	if E.RegisterConfigPage then
		local page = E:RegisterConfigPage("accessibility", "Accessibility", nil,
			function() return E.db.general.access end,
			function() E:AccessibilityChanged() end, 3.3)
		if page then
			page.build = BuildRows
			page.defaults = function() return E.defaults.general.access end
			page.desc = L["High contrast, large text, color-blind safe colors, sound cues and reduced motion."]
		end
	end
end, Access, "modules")

-- Another profile has its own switches: its safe colors (written into the
-- shared text tokens) apply at once, and Undo starts over, so it never
-- writes one profile's switches into another.
hooksecurefunc(E, "SetProfile", function()
	before, shown = nil, Snapshot()
	E:UpdateColorBlind()
end)

-- The game's color-blind mode may change while "Follow the game" is on.
E:RegisterEvent("CVAR_UPDATE", function(_, _, name)
	if name == "colorblindMode" and E.db and Access().colorBlind == "game" then E:UpdateColorBlind() end
end, Access)
