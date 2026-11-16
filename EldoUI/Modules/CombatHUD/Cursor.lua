-- Combat HUD: cursor ring with GCD and cast sweeps,
-- and a character crosshair at the screen center.
-- EldoUI's own display, off by default. A ring follows the mouse cursor so
-- it is easy to find in combat. The sweeps are drawn by the game from
-- duration objects only (secret-safe, nothing is computed):
--   GCD   the global cooldown's duration from the combat kit's cooldown
--         source (K.Cooldowns in Kit.lua) -> SetCooldownFromDurationObject
--   cast  UnitCastingDuration / UnitChannelDuration -> SetCooldownFromDurationObject
-- The crosshair is four plain bars around the screen center. Its optional
-- range tint only shows Blizzard's own answer to "is the target in range of
-- this spell" (C_Spell.IsSpellInRange) as a color; no distance is shown or
-- estimated. A secret answer goes straight to SetVertexColorFromBoolean.
-- Written from scratch for EldoUI; the ring texture is EldoUI's own art.
local _, E = ...
local L = E.L
local K = E.CombatKit
local M = E.CombatHUD

local RING = "Interface\\AddOns\\EldoUI\\Modules\\CombatHUD\\Media\\EldoRing.tga"
local CD = K.Cooldowns
local GCD_KEY = "cursor:gcd"

local F = { key = "cursor", title = "Cursor ring" }
F.defaults = {
	enabled = false,
	size = 48,
	colorMode = "class",
	color = { 1, 1, 1 },
	alpha = 80,
	visibility = "always",
	gcd = true,
	cast = true,
	castColor = { 1, 1, 1 },
}

local ring, gcd, cast

local function RingColor()
	local db = M.db.cursor
	if db.colorMode == "accent" then
		local r, g, b = unpack(E.media.accentColor)
		return r, g, b
	elseif db.colorMode == "class" then
		return E:ClassColor("player")
	end
	return unpack(db.color)
end

local function Follow(self)
	local x, y = GetCursorPosition()
	local scale = UIParent:GetEffectiveScale()
	self:ClearAllPoints()
	self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)
end

local function CreateSweep(parent, reverse)
	local sweep = CreateFrame("Cooldown", nil, parent, "CooldownFrameTemplate")
	sweep:SetAllPoints()
	sweep:SetSwipeTexture(RING)
	sweep:SetDrawEdge(false)
	sweep:SetDrawBling(false)
	sweep:SetHideCountdownNumbers(true)
	sweep:SetReverse(reverse)
	if sweep.SetUseCircularEdge then sweep:SetUseCircularEdge(true) end
	return sweep
end

local function UpdateGCD()
	if not (gcd and M.db.cursor.gcd) then return end
	local duration = CD.GCDDuration()
	if duration and gcd.SetCooldownFromDurationObject then
		gcd:SetCooldownFromDurationObject(duration, true)
	end
end

local function UpdateCast()
	if not (cast and M.db.cursor.cast) then return end
	local duration = UnitCastingDuration and UnitCastingDuration("player")
	if not duration and UnitChannelDuration then duration = UnitChannelDuration("player") end
	if duration and cast.SetCooldownFromDurationObject then
		cast:SetCooldownFromDurationObject(duration, true)
	else
		cast:Clear()
	end
end

local function StopCast()
	if cast then cast:Clear() end
end

local CAST_START = { "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_CHANNEL_UPDATE" }
local CAST_STOP = { "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED" }

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event)
	if tContains(CAST_STOP, event) then
		StopCast()
	else
		UpdateCast()
	end
end)

function F:Setup()
	ring = CreateFrame("Frame", nil, UIParent)
	ring:SetFrameStrata("TOOLTIP")
	ring.texture = ring:CreateTexture(nil, "BACKGROUND")
	ring.texture:SetAllPoints()
	ring.texture:SetTexture(RING)
	gcd = CreateSweep(ring, false)
	cast = CreateSweep(ring, true)
	cast:SetPoint("TOPLEFT", 6, -6)
	cast:SetPoint("BOTTOMRIGHT", -6, 6)
	ring:SetScript("OnUpdate", Follow)
end

function F:Apply(db)
	ring:SetSize(db.size, db.size)
	local r, g, b = RingColor()
	ring.texture:SetVertexColor(r, g, b, db.alpha / 100)
	gcd:SetSwipeColor(r, g, b, 1)
	gcd:SetShown(db.gcd)
	local cr, cg, cb = unpack(db.castColor)
	cast:SetSwipeColor(cr, cg, cb, 0.9)
	cast:SetShown(db.cast)
	ring:SetParent(K.Visibility("cursor", nil, db.visibility, 0))
	ring:Show()
	events:UnregisterAllEvents()
	if db.gcd then
		CD.Subscribe(GCD_KEY, function(changes) if changes.spells then UpdateGCD() end end)
	else
		CD.Unsubscribe(GCD_KEY)
	end
	if db.cast then
		for _, event in ipairs(CAST_START) do events:RegisterUnitEvent(event, "player") end
		for _, event in ipairs(CAST_STOP) do events:RegisterUnitEvent(event, "player") end
	end
end

function F:Restore()
	events:UnregisterAllEvents()
	CD.Unsubscribe(GCD_KEY)
	K.StopVisibility("cursor")
	if ring then ring:Hide() end
end

local function Off() return not (M.db and M.db.cursor and M.db.cursor.enabled) end
local VIS = { always = "Always", combat = "In combat", target = "With a hostile target", combatOrTarget = "In combat or with a target" }
F.note = L["EldoUI's own ring around the mouse cursor. The GCD and cast sweeps are drawn by the game from its own timers."]
F.options = {
	{ type = "toggle", key = "cursor.enabled", label = "Cursor ring", desc = "A ring that follows the mouse cursor." },
	{ type = "select", key = "cursor.visibility", label = "Show", values = VIS, hidden = Off, desc = "When the ring shows." },
	{ type = "range", key = "cursor.size", label = "Size", min = 24, max = 128, step = 2, hidden = Off, desc = "Diameter of the ring." },
	{ type = "select", key = "cursor.colorMode", label = "Color", hidden = Off,
		values = { class = "Class color", accent = "Accent color", custom = "Custom color" }, desc = "Color of the ring and the GCD sweep." },
	{ type = "color", key = "cursor.color", label = "Custom color", desc = "Color of the ring and the GCD sweep.",
		hidden = function() return Off() or M.db.cursor.colorMode ~= "custom" end },
	{ type = "range", key = "cursor.alpha", label = "Ring opacity", unit = "%", min = 10, max = 100, step = 5, hidden = Off,
		desc = "Opacity of the ring itself, in percent." },
	{ type = "toggle", key = "cursor.gcd", label = "GCD sweep", hidden = Off, desc = "The ring fills while the global cooldown runs." },
	{ type = "toggle", key = "cursor.cast", label = "Cast sweep", hidden = Off, desc = "An inner ring fills while you cast or channel." },
	{ type = "color", key = "cursor.castColor", label = "Cast color", desc = "Color of the cast sweep.",
		hidden = function() return Off() or not M.db.cursor.cast end },
}

M:AddFeature(F)

---------------------------------------------------------------------------
-- Crosshair: a thin cross at the center of the screen, where your
-- character stands with the default camera. Four bars with a gap in the
-- middle, each with an optional dark border behind it.
---------------------------------------------------------------------------
local C = { key = "crosshair", title = "Crosshair" }
C.defaults = {
	enabled = false,
	visibility = "combat",
	length = 12,
	thickness = 2,
	gap = 6,
	border = true,
	colorMode = "accent",
	color = { 1, 1, 1 },
	alpha = 85,
	offsetY = 0,
	rangeTint = false,
	rangeColor = { 1, 0.25, 0.25 },
	rangeSpell = "",
}

-- A melee ability of each class that has one from level 1-10 on Forever:
-- its range check is the melee range. Other classes pick a spell.
local MELEE_SPELL = {
	WARRIOR = 78,   -- Heroic Strike
	ROGUE = 1752,   -- Sinister Strike
	HUNTER = 2974,  -- Wing Clip
	DRUID = 1082,   -- Claw (cat form)
}
local MELEE_CLASS = { WARRIOR = true, ROGUE = true, HUNTER = true, DRUID = true, PALADIN = true, SHAMAN = true }

local cross            -- the crosshair frame
local outOfRange       -- last plain answer (true = out of range), nil = no tint
local rangeTicker

local function PlayerClass()
	local _, class = UnitClass("player")
	return class
end

local function CrossColor()
	local db = M.db.crosshair
	if db.colorMode == "class" then
		return E:ClassColor("player")
	elseif db.colorMode == "custom" then
		return unpack(db.color)
	end
	local r, g, b = unpack(E.media.accentColor)
	return r, g, b
end

-- The spell whose range check is used: the player's choice, else the class
-- default. Number strings become spell IDs.
local function RangeSpell()
	local db = M.db.crosshair
	local text = type(db.rangeSpell) == "string" and strtrim(db.rangeSpell) or ""
	if text ~= "" then return tonumber(text) or text end
	return MELEE_SPELL[PlayerClass() or ""]
end

local function Paint(r, g, b)
	local alpha = (M.db.crosshair.alpha or 85) / 100
	for _, bar in ipairs(cross.bars) do bar:SetVertexColor(r, g, b, alpha) end
end

local function PaintNormal()
	Paint(CrossColor())
end

-- The two colors the game picks between for a secret range answer, kept
-- from one setup to the next and refreshed only when the look changes.
local normalColor, tintColor

local function RefreshRangeColors(db)
	local r, g, b = CrossColor()
	local alpha = (db.alpha or 85) / 100
	local tint = db.rangeColor
	if not normalColor then
		normalColor, tintColor = CreateColor(r, g, b, alpha), CreateColor(tint[1], tint[2], tint[3], alpha)
	else
		normalColor:SetRGBA(r, g, b, alpha)
		tintColor:SetRGBA(tint[1], tint[2], tint[3], alpha)
	end
end

local function UpdateRange()
	-- Seen, not only shown: the visibility rule fades the parent out.
	if not cross or not cross:IsVisible() or cross:GetEffectiveAlpha() <= 0 then return end
	local db = M.db.crosshair
	if not db.rangeTint then return end
	local spell = RangeSpell()
	local inRange
	if spell and UnitExists("target") and C_Spell and C_Spell.IsSpellInRange then
		inRange = C_Spell.IsSpellInRange(spell, "target")
	end
	-- Secret test first: comparing a secret answer with nil errors.
	local secret = issecretvalue and issecretvalue(inRange)
	if not secret and type(inRange) == "nil" then
		if outOfRange ~= nil then
			outOfRange = nil
			PaintNormal()
		end
		return
	end
	if secret then
		-- Hand the secret answer to the game's own color switch.
		outOfRange = "secret"
		for _, bar in ipairs(cross.bars) do
			if bar.SetVertexColorFromBoolean then bar:SetVertexColorFromBoolean(inRange, normalColor, tintColor) end
		end
		return
	end
	local out = not inRange
	if out == outOfRange then return end
	outOfRange = out
	if out then Paint(unpack(db.rangeColor)) else PaintNormal() end
end

local function Bar(parent, layer)
	local bar = parent:CreateTexture(nil, layer)
	bar:SetColorTexture(1, 1, 1, 1)
	return bar
end

function C:Setup()
	cross = CreateFrame("Frame", "EldoUI_Crosshair", UIParent)
	cross:SetFrameStrata("BACKGROUND")
	cross:SetSize(1, 1)
	cross:EnableMouse(false)
	cross.bars, cross.borders = {}, {}
	for index = 1, 4 do
		cross.borders[index] = Bar(cross, "BORDER")
		cross.borders[index]:SetVertexColor(0, 0, 0, 0.8)
		cross.bars[index] = Bar(cross, "ARTWORK")
	end
end

-- Bars in order up, down, left, right.
local DIRECTIONS = { { 0, 1 }, { 0, -1 }, { -1, 0 }, { 1, 0 } }

function C:Apply(db)
	cross:SetParent(K.Visibility("crosshair", nil, db.visibility, 0))
	cross:SetFrameStrata("BACKGROUND")
	cross:ClearAllPoints()
	cross:SetPoint("CENTER", UIParent, "CENTER", 0, db.offsetY or 0)
	local length, thick, gap = db.length, db.thickness, db.gap
	local edge = E.pixel or 1
	for index, dir in ipairs(DIRECTIONS) do
		local bar, border = cross.bars[index], cross.borders[index]
		local horizontal = dir[2] == 0
		local w, h = horizontal and length or thick, horizontal and thick or length
		local offset = gap + length / 2
		bar:ClearAllPoints()
		bar:SetSize(w, h)
		bar:SetPoint("CENTER", cross, "CENTER", dir[1] * offset, dir[2] * offset)
		border:ClearAllPoints()
		border:SetPoint("TOPLEFT", bar, "TOPLEFT", -edge, edge)
		border:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", edge, -edge)
		border:SetShown(db.border and true or false)
	end
	outOfRange = nil
	RefreshRangeColors(db)
	PaintNormal()
	cross:Show()
	if db.rangeTint and not rangeTicker then
		rangeTicker = C_Timer.NewTicker(0.1, UpdateRange)
	elseif not db.rangeTint and rangeTicker then
		rangeTicker:Cancel()
		rangeTicker = nil
	end
end

function C:Restore()
	K.StopVisibility("crosshair")
	if rangeTicker then
		rangeTicker:Cancel()
		rangeTicker = nil
	end
	if cross then cross:Hide() end
end

local function CrossOff() return not (M.db and M.db.crosshair and M.db.crosshair.enabled) end
local function TintOff() return CrossOff() or not M.db.crosshair.rangeTint end
local CROSS_VIS = { always = "Always", combat = "In combat", target = "With a hostile target", combatOrTarget = "In combat or with a target" }
C.note = L["A thin cross at the center of the screen. The range tint shows the game's own in-range answer for a spell as a color."]
C.options = {
	{ type = "toggle", key = "crosshair.enabled", label = "Crosshair", desc = "A thin cross at the center of the screen." },
	{ type = "select", key = "crosshair.visibility", label = "Show", values = CROSS_VIS, hidden = CrossOff, desc = "When the crosshair shows." },
	{ type = "select", key = "crosshair.colorMode", label = "Color", hidden = CrossOff,
		values = { accent = "Accent color", class = "Class color", custom = "Custom color" }, desc = "Color of the four bars." },
	{ type = "color", key = "crosshair.color", label = "Custom color", hidden = function() return CrossOff() or M.db.crosshair.colorMode ~= "custom" end,
		desc = "Used with Custom color." },
	{ type = "range", key = "crosshair.alpha", label = "Opacity", unit = "%", min = 10, max = 100, step = 5, hidden = CrossOff, desc = "Opacity of the crosshair, in percent." },
	{ type = "cog", label = "Shape", dependsOn = "crosshair.enabled", desc = "Arm length, width, center gap, border and vertical offset.", options = {
		{ type = "range", key = "crosshair.length", label = "Arm length", min = 4, max = 40, step = 1, desc = "Length of each of the four bars, in pixels." },
		{ type = "range", unit = "px", key = "crosshair.thickness", label = "Arm width", min = 1, max = 6, step = 1, desc = "Thickness of the bars, in pixels." },
		{ type = "range", unit = "px", key = "crosshair.gap", label = "Center gap", min = 0, max = 30, step = 1, desc = "Empty space between the center and each bar." },
		{ type = "toggle", key = "crosshair.border", label = "Dark border", desc = "A thin dark edge around each bar, so it shows on bright ground." },
		{ type = "range", unit = "px", key = "crosshair.offsetY", label = "Y offset", min = -300, max = 300, step = 1, desc = "Moves the crosshair up or down from the screen center, in pixels (for a camera that is not centered on you)." },
	} },
	{ type = "toggle", key = "crosshair.rangeTint", label = "Out-of-range tint", hidden = CrossOff,
		requires = function() return MELEE_CLASS[PlayerClass() or ""] or false end,
		desc = "Melee classes: the crosshair turns the tint color while your target is out of range of your melee ability (the game's own range check)." },
	{ type = "color", key = "crosshair.rangeColor", label = "Tint color", hidden = TintOff,
		requires = function() return MELEE_CLASS[PlayerClass() or ""] or false end, desc = "Color while the target is out of range." },
	{ type = "input", key = "crosshair.rangeSpell", label = "Range spell", hidden = TintOff,
		requires = function() return MELEE_CLASS[PlayerClass() or ""] or false end,
		desc = "Spell ID or name whose range is checked. Empty uses your class's melee ability (Paladins and Shamans pick one, for example a melee strike)." },
}

M:AddFeature(C)

E:AddCommand("crosshair", "[on|off]  EldoUI crosshair at the screen center", function(arg)
	local db = M.db and M.db.crosshair
	if not db then return end
	if not M.active then E:Print(E:ModuleOffHint("CombatHUD")) return end
	arg = (arg or ""):lower()
	if arg == "on" then db.enabled = true
	elseif arg == "off" then db.enabled = false
	elseif arg == "" or arg == "toggle" then db.enabled = not db.enabled
	else E:Print(L["Usage: /eui crosshair [on|off]"]) return end
	M:ApplyFeature(C)
	E:Print(db.enabled and L["Crosshair on."] or L["Crosshair off."])
end, "Tools")

E:AddCommand("cursor", "[on|off]  EldoUI cursor ring", function(arg)
	local db = M.db and M.db.cursor
	if not db then return end
	if not M.active then E:Print(E:ModuleOffHint("CombatHUD")) return end
	arg = (arg or ""):lower()
	if arg == "on" then db.enabled = true
	elseif arg == "off" then db.enabled = false
	elseif arg == "" or arg == "toggle" then db.enabled = not db.enabled
	else E:Print(L["Usage: /eui cursor [on|off]"]) return end
	M:ApplyFeature(F)
	E:Print(db.enabled and L["Cursor ring on."] or L["Cursor ring off."])
end, "Tools")
