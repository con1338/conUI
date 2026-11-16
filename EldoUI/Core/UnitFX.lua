-- EldoUI UnitFX: the shared effects engine of the unit
-- frames, the party and raid frames and the nameplates. One code path and
-- one look for every danger visual, pulse and glow on a unit, switched from
-- one Effects tab with the presets Off, Subtle, Standard and Vivid.
--
-- Rules (Forever applies the Midnight restrictions, docs/rules):
--   * Presentation only. Health, power, threat, range and the important-
--     spell flag may be secret. They are never compared (not even with
--     nil), never used in arithmetic, joined into a string, measured or
--     used as a table key. They go only into sinks the client accepts:
--     curves (UnitHealthPercent / UnitPowerPercent with a curve,
--     curve:Evaluate), SetAlphaFromBoolean, SetVertexColorFromBoolean,
--     SetVertexColor / SetAlpha with a curve result, StatusBar:SetValue.
--     A nil test is `type(x) == "nil"`, a secret test E:IsSecret(x).
--   * The same code runs for plain and secret values: the curve decides,
--     Lua never branches on the value. A plain value is read only to know
--     that a gate is closed (to pause a glow), never to pick a look.
--   * Every API is feature-detected: without curves the curve effects skip
--     silently and their option rows are hidden (`requiresAPI`).
--   * Gates are EldoUI child frames, never the secure unit button. When the
--     parent is protected and the player is in combat, anchoring waits for
--     E:RunOutOfCombat. Nothing here calls a protected function.
--   * Motion follows General > Animations; pulses are capped at 2 Hz.
--   * Looks come from General > Colors (E.colors.status, .prediction,
--     .threat), General > Glows (glow users) and the design tokens.
--
-- API (methods on E; the same functions are on E.UnitFX for plugins):
--
-- Curves
--   E:UnitCurve(key, spec)          the cached curve object, or nil (no curve API, or the
--                                   spec turns it off). Built once per key and spec
--                                   values; a changed setting gives a new curve, and new
--                                   colors (General > Colors) rebuild them all.
--       keys  threat       color, Step; spec.role "tank" | "dps", spec.full (color the
--                          "safe" status too, for bar colors), spec.colors[0..3]
--             threatPulse  alpha, Step; 1 only at "tanking" for DPS, at 0-1 for tanks
--             execute      color, Step on the health share; spec.lower (%, 20)
--             execute2     color, Step; spec.upper (%, 0 = off -> nil)
--             healthGradient  color, Linear; spec.low, spec.mid, spec.high colors
--             healthThreshold color, Step; spec.low (%, 20), spec.high (%, 50), spec.base
--             lowHealth    color, Step; spec.threshold (%, 30)
--             lowPower     color, Step; spec.threshold (%, 20)
--             auraExpiring color, Step on seconds left; spec.seconds (5), spec.normal
--       spec.output = "alpha" turns a color curve into an alpha curve (the color's alpha).
--       Spec values are plain settings, never game values.
--   E:RegisterUnitCurve(key, def)   def = { kind = "color" | "alpha", type = "Step" | "Linear",
--                                   build = function(spec) return { { x, { r, g, b, a } | n }, ... } end }
--   E:RefreshUnitCurves()           rebuild on next use (General > Colors does it itself)
--   E:UnitCurveHealth(unit, key, spec)          UnitHealthPercent(unit, true, curve); may be secret
--   E:UnitCurvePower(unit, key, spec, power)    UnitPowerPercent(unit, power, false, curve)
--   E:UnitCurveEval(key, x, spec)               curve:Evaluate(x); x may be secret
--   E:PaintColorResult(region, color[, method]) region[method](color:GetRGBA()); true when done
--
-- Gates: E:CreateGate(parent[, level]) -> gate, an EldoUI frame over the parent
--   (frame level parent + level, default 4) with an inner frame for motion.
--     gate:SetLook(style[, opts])  BORDER | TINT | EDGE | GLOW | LINE | ZONE | NONE
--                                  opts: thickness (px), alpha (tint strength), size (px),
--                                  glow (glow user key), percent / upper (LINE, ZONE),
--                                  color (plain { r, g, b } for the static zone)
--     gate:FromBoolean(b, on, off) alpha from a maybe-secret boolean (SetAlphaFromBoolean)
--     gate:FromColor(color)        tints the look with a curve result (the color's alpha gates)
--     gate:FromAlpha(value)        alpha from a maybe-secret number (an alpha curve result)
--     gate:Paint(color)            FromColor for color looks, the color's alpha for GLOW
--     gate:SetOpen(open)           plain open (1) or closed (0)
--     gate:Pulse(on[, hz[, low]])  looping alpha on the inner frame, 0.25-2 Hz, static with
--                                  animations off; returns true while it pulses
--     gate:Glow(key, on[, overrides])  glow user `key` on the inner frame
--     gate:Clear()                 closed: no pulse, no glow, alpha 0
--     gate:IsKnownClosed()         true when a plain value closed it (its glow is paused)
--   E.UnitFX.MAX_HZ = 2
--
-- Effect drivers. Each takes the effect's settings table from the block below;
-- `enabled = false` (or nil settings) clears the gate.
--   E:UnitFXThreat(gate, unit, settings[, opts])   threat border / glow / tint; opts.other
--                                   (threat against this unit), opts.role, opts.pulseGate,
--                                   opts.mark (false: no danger mark), opts.markSize
--   E:UnitFXLowHealth(gate, unit, settings)        low-health edge / tint / glow, pulse
--   E:UnitFXLowPower(gate, unit, settings[, powerType])
--   E:UnitFXExecute(gate, unit, settings[, upperGate])  execute shade (opt-in only)
--   E:UnitFXImportantCast(gate, spellID, settings) castImportant glow -> the game's flag
--   E:UnitFXImportantSound(flag, settings)         one sound when the flag is plain true (opt-in)
--   E:UnitFXRange(frame, unit, settings)           range fade (SetAlphaFromBoolean)
--   E:UnitFXFadeIn(frame, settings)                E:FadeIn when the effect is on
--   E:AttachAbsorb(healthBar[, opts]) -> handle    absorb bar on the health fill's edge
--   E:UpdateAbsorb(unit, handle, enabled)          values from the game's calculator
--
-- Options and presets. A block lives in the consumer's settings:
--   { preset = "subtle", threat = { enabled = false, style = "BORDER", pulse = false }, ... }
--   E.UNITFX_EFFECTS / E:UnitFXEffect(key)       the effect catalog (groups Animations,
--                                                Danger, Casts; defaults, rows, presets)
--   E:RegisterUnitFXPresets(consumer, presets[, effects])  the consumer's effect list and its
--                                                changes to the four presets
--   E:UnitFXInUse()                               true once a consumer registered (the
--                                                General > Colors groups show from then)
--   E:UnitFXDefaults(consumer[, preset])          a fresh block for the module's defaults
--   E:ApplyUnitFXPreset(block, key[, consumer])   write a preset (off | subtle | standard | vivid)
--   E:UnitFXPresetOf(block[, consumer])           that key, or "custom"
--   E:NormalizeUnitFX(block[, consumer])          fill, clamp, apply a picked preset or
--                                                detect Custom (call from OnProfileChanged)
--   E:UnitFXOptions(path, opts)                   the declarative rows: preset select, then
--                                                Animations / Danger / Casts, each effect a
--                                                toggle with its tunables in the cog.
--       opts: consumer, db = function() return settings end, label (false: no header),
--             hidden = function or { effectKey = function }, effects (a subset)
-- Execute shade and the important-cast sound are opt-in: off by default, and
-- no preset turns them on or reads them.
-- Written from scratch for EldoUI.
local _, E = ...

local FX = {}
E.UnitFX = FX

local issecret = issecretvalue or function() return false end
local EMPTY = {}

FX.MAX_HZ = 2
FX.MIN_HZ = 0.25
FX.stats = { builds = 0, sigs = 0 }

local function Clamp(value, low, high, default)
	value = tonumber(value) or default
	if value < low then return low end
	if value > high then return high end
	return value
end

-- Percent setting (plain) as a share of 0-1.
local function Share(value, default)
	return Clamp(value, 1, 99, default) / 100
end

local function Expose(name)
	FX[name] = function(...) return E[name](E, ...) end
end

---------------------------------------------------------------------------
-- 1. Curve cache
---------------------------------------------------------------------------
local defs = {}
-- key .. "#" .. spec signature -> { curve = object | false }. One entry per
-- distinct spec, so frames with different thresholds keep their own curve;
-- a new color (General > Colors) or E:RefreshUnitCurves() empties it.
local cache = {}

local function CurveAPI()
	return C_CurveUtil and C_CurveUtil.CreateColorCurve and C_CurveUtil.CreateCurve and CreateColor and true or false
end
FX.HasCurves = CurveAPI

function E:RegisterUnitCurve(key, def)
	if type(key) ~= "string" or type(def) ~= "table" or type(def.build) ~= "function" then return false end
	defs[key] = def
	wipe(cache)
	return true
end

function E:RefreshUnitCurves()
	wipe(cache)
end

-- New colors from General > Colors: curves rebuild on their next use.
hooksecurefunc(E, "UpdateColors", function() E:RefreshUnitCurves() end)

-- A plain spec (settings, never game values) as a short string. Keys are
-- sorted so two tables with the same values give the same string.
local function SortKeys(a, b)
	if type(a) == type(b) then return a < b end
	return type(a) == "number"
end
local function SpecSig(spec, depth)
	if type(spec) ~= "table" then return "" end
	depth = depth or 0
	if depth == 0 then FX.stats.sigs = FX.stats.sigs + 1 end
	local keys = {}
	for key in pairs(spec) do
		local kind = type(key)
		if (kind == "string" or kind == "number") and not issecret(key) then keys[#keys + 1] = key end
	end
	table.sort(keys, SortKeys)
	local parts = {}
	for _, key in ipairs(keys) do
		local value = spec[key]
		local kind = type(value)
		if issecret(value) then
			value = "?"
		elseif kind == "table" then
			value = depth < 3 and ("{" .. SpecSig(value, depth + 1) .. "}") or "{}"
		elseif kind == "number" or kind == "string" or kind == "boolean" then
			value = tostring(value)
		else
			value = kind
		end
		parts[#parts + 1] = tostring(key) .. "=" .. value
	end
	return table.concat(parts, ";")
end

-- Specs and look options the effects below make from settings values: one
-- table per distinct value, never changed after, with its signature worked
-- out once, so a health event builds no tables or strings.
local fixedSigs = setmetatable({}, { __mode = "k" })
local function Fixed(store, key, a, av, b, bv, c, cv)
	local spec = store[key]
	if not spec then
		spec = { [a] = av }
		if b then spec[b] = bv end
		if c then spec[c] = cv end
		fixedSigs[spec] = SpecSig(spec)
		store[key] = spec
	end
	return spec
end
local function Sig(spec) return fixedSigs[spec] or SpecSig(spec) end
fixedSigs[EMPTY] = ""
-- A fixed spec -> curve key -> cache key, so its cache key is made once.
local cacheKeys = setmetatable({}, { __mode = "k" })
local SPECS = { lowHealth = {}, lowPower = {}, execute = {}, execute2 = {}, warnLook = {}, executeLook = {}, upperLook = {},
	threat = {}, threatPulse = {} }

-- Color points become alpha points for spec.output = "alpha".
local function ToAlpha(points)
	local out = {}
	for index, point in ipairs(points) do
		local y = point[2]
		out[index] = { point[1], type(y) == "table" and (y[4] or 1) or y }
	end
	return out
end

local function NewCurve(alpha, curveType)
	local ok, curve = pcall(alpha and C_CurveUtil.CreateCurve or C_CurveUtil.CreateColorCurve)
	if not ok or type(curve) ~= "table" then return nil end
	local kinds = Enum and Enum.LuaCurveType
	local kind = kinds and kinds[curveType or "Step"]
	if kind and curve.SetType then pcall(curve.SetType, curve, kind) end
	return curve
end

local function Fill(curve, points, alpha)
	if curve.ClearPoints then pcall(curve.ClearPoints, curve) end
	for _, point in ipairs(points) do
		local y = point[2]
		local value = alpha and y or CreateColor(y[1], y[2], y[3], y[4] or 1)
		if not pcall(curve.AddPoint, curve, point[1], value) then return false end
	end
	return true
end

function E:UnitCurve(key, spec)
	local def = defs[key]
	if not def or not CurveAPI() then return nil end
	spec = type(spec) == "table" and spec or EMPTY
	local keys = cacheKeys[spec]
	local cacheKey = keys and keys[key]
	if not cacheKey then
		cacheKey = key .. "#" .. Sig(spec)
		if fixedSigs[spec] then
			keys = keys or {}
			keys[key] = cacheKey
			cacheKeys[spec] = keys
		end
	end
	local entry = cache[cacheKey]
	if entry then return entry.curve or nil end
	local curve = false
	local ok, points = pcall(def.build, spec)
	-- No points: off for this spec (an upper shade at 0 %).
	if ok and type(points) == "table" and #points > 0 then
		local alpha = def.kind == "alpha" or spec.output == "alpha"
		if alpha and def.kind ~= "alpha" then points = ToAlpha(points) end
		local made = NewCurve(alpha, def.type)
		if made and Fill(made, points, alpha) then
			curve = made
			FX.stats.builds = FX.stats.builds + 1
		end
	end
	cache[cacheKey] = { curve = curve }
	return curve or nil
end

-- The client evaluates; the result may be secret and goes straight to a setter.
function E:UnitCurveHealth(unit, key, spec)
	if not UnitHealthPercent or type(unit) ~= "string" then return nil end
	local curve = self:UnitCurve(key, spec)
	if not curve then return nil end
	local ok, result = pcall(UnitHealthPercent, unit, true, curve)
	if ok then return result end
	return nil
end

function E:UnitCurvePower(unit, key, spec, powerType)
	if not UnitPowerPercent or type(unit) ~= "string" then return nil end
	local curve = self:UnitCurve(key, spec)
	if not curve then return nil end
	local ok, result = pcall(UnitPowerPercent, unit, powerType, false, curve)
	if ok then return result end
	return nil
end

function E:UnitCurveEval(key, x, spec)
	if type(x) == "nil" then return nil end
	local curve = self:UnitCurve(key, spec)
	if not curve or not curve.Evaluate then return nil end
	local ok, result = pcall(curve.Evaluate, curve, x)
	if ok then return result end
	return nil
end

-- A curve color into a setter (SetVertexColor, SetStatusBarColor,
-- SetBackdropBorderColor, ...). Its parts may be secret: only the setter
-- sees them.
function E:PaintColorResult(region, color, method)
	if type(region) ~= "table" or type(color) == "nil" or issecret(color) then return false end
	local setter = region[method or "SetVertexColor"]
	if type(setter) ~= "function" then return false end
	local get = type(color) == "table" and color.GetRGBA
	if type(get) ~= "function" then return false end
	local ok, r, g, b, a = pcall(get, color)
	if not ok then return false end
	return pcall(setter, region, r, g, b, a) and true or false
end

Expose("UnitCurve")
Expose("RegisterUnitCurve")
Expose("RefreshUnitCurves")
Expose("UnitCurveHealth")
Expose("UnitCurvePower")
Expose("UnitCurveEval")
Expose("PaintColorResult")

---------------------------------------------------------------------------
-- Built-in curves. Colors are read when the curve is (re)built.
---------------------------------------------------------------------------
local CLEAR = { 0, 0, 0, 0 }

local function RGBA(r, g, b, a)
	if type(r) ~= "number" then return { 1, 1, 1, a or 1 } end
	return { r, g, b, a or 1 }
end

local function Status(key) return RGBA(E:GetStatusColor(key)) end
local function ThreatColor(status) return RGBA(E:GetThreatStatusColor(status)) end

-- A color the spec overrides ({ r, g, b[, a] }), else the default.
local function Pick(spec, field, default)
	local c = spec[field]
	if type(c) == "table" and type(c[1]) == "number" and type(c[2]) == "number" and type(c[3]) == "number" then
		return { c[1], c[2], c[3], type(c[4]) == "number" and c[4] or 1 }
	end
	return default
end

-- Threat status 0-3 (UnitThreatSituation): 0 not on top and low threat,
-- 1 higher threat than the tank, 2 tanking but not first, 3 tanking.
E:RegisterUnitCurve("threat", { kind = "color", type = "Step", build = function(spec)
	local tank = spec.role == "tank"
	local full = spec.full and true or false
	local map
	if tank then
		-- For a tank the danger is NOT holding the mob.
		map = { [0] = ThreatColor(3), [1] = ThreatColor(2), [2] = ThreatColor(1), [3] = full and ThreatColor(0) or CLEAR }
	else
		map = { [0] = full and ThreatColor(0) or CLEAR, [1] = ThreatColor(1), [2] = ThreatColor(2), [3] = ThreatColor(3) }
	end
	local colors = type(spec.colors) == "table" and spec.colors or EMPTY
	local points = {}
	for status = 0, 3 do
		local c = colors[status]
		if c == false then
			map[status] = CLEAR
		elseif type(c) == "table" then
			map[status] = Pick({ c = c }, "c", map[status])
		end
		points[#points + 1] = { status, map[status] }
	end
	return points
end })

-- Whether you play as the tank: the game marks Defensive Stance, Bear Form,
-- Dire Bear Form and Righteous Fury with its "effectively tank" aura, which
-- counts without a group role; else the group role. A secret answer from
-- the aura call falls back to the role.
function E:PlayerIsTank()
	if UnitHasEffectivelyTankAura then
		local ok, aura = pcall(UnitHasEffectivelyTankAura, "player")
		if ok and not self:IsSecret(aura) and aura == true then return true end
	end
	if not UnitGroupRolesAssigned then return false end
	local ok, role = pcall(UnitGroupRolesAssigned, "player")
	return ok and not self:IsSecret(role) and role == "TANK"
end

-- The threat status a frame colors by. A tank reads its lead over second
-- place (UnitThreatLeadSituation: 0 a safe lead, 1 and 2 someone is
-- catching up, 3 not first), so the warning comes before the mob turns;
-- its colors run like a damage dealer's, hence role "lead". Everyone else,
-- and a client without the lead call, reads UnitThreatSituation.
function E:ThreatStatusFor(unit, mob, tank)
	if tank and UnitThreatLeadSituation and mob then
		local ok, status = pcall(UnitThreatLeadSituation, unit, mob)
		if ok then return status, "lead" end
	end
	local ok, status
	if mob then
		ok, status = pcall(UnitThreatSituation, unit, mob)
	else
		ok, status = pcall(UnitThreatSituation, unit)
	end
	if ok then return status, tank and "tank" or "dps" end
	return nil, tank and "tank" or "dps"
end

E:RegisterUnitCurve("threatPulse", { kind = "alpha", type = "Step", build = function(spec)
	if spec.role == "tank" then
		return { { 0, 1 }, { 1, 1 }, { 2, 0 }, { 3, 0 } }
	end
	return { { 0, 0 }, { 1, 0 }, { 2, 0 }, { 3, 1 } }
end })

E:RegisterUnitCurve("execute", { kind = "color", type = "Step", build = function(spec)
	return { { 0, Pick(spec, "color", Status("execute")) }, { Share(spec.lower, 20), CLEAR } }
end })

E:RegisterUnitCurve("execute2", { kind = "color", type = "Step", build = function(spec)
	local upper = tonumber(spec.upper) or 0
	if upper <= 0 then return nil end
	return { { 0, CLEAR }, { Share(upper, 80), Pick(spec, "color", Status("execute")) } }
end })

E:RegisterUnitCurve("healthGradient", { kind = "color", type = "Linear", build = function(spec)
	return {
		{ 0, Pick(spec, "low", Status("gradientLow")) },
		{ 0.5, Pick(spec, "mid", Status("gradientMid")) },
		{ 1, Pick(spec, "high", Status("gradientHigh")) },
	}
end })

E:RegisterUnitCurve("healthThreshold", { kind = "color", type = "Step", build = function(spec)
	local low, high = Share(spec.low, 20), Share(spec.high, 50)
	if high <= low then high = math.min(0.99, low + 0.01) end
	return {
		{ 0, Pick(spec, "lowColor", Status("gradientLow")) },
		{ low, Pick(spec, "midColor", Status("gradientMid")) },
		{ high, Pick(spec, "base", CLEAR) },
	}
end })

E:RegisterUnitCurve("lowHealth", { kind = "color", type = "Step", build = function(spec)
	return { { 0, Pick(spec, "color", Status("lowHealth")) }, { Share(spec.threshold, 30), CLEAR } }
end })

E:RegisterUnitCurve("lowPower", { kind = "color", type = "Step", build = function(spec)
	return { { 0, Pick(spec, "color", Status("lowPower")) }, { Share(spec.threshold, 20), CLEAR } }
end })

E:RegisterUnitCurve("auraExpiring", { kind = "color", type = "Step", build = function(spec)
	local bad, body = E.tokens.text.bad, E.tokens.text.body
	return {
		{ 0, Pick(spec, "color", RGBA(bad[1], bad[2], bad[3])) },
		{ Clamp(spec.seconds, 1, 30, 5), Pick(spec, "normal", RGBA(body[1], body[2], body[3])) },
	}
end })

---------------------------------------------------------------------------
-- 2. Gates
---------------------------------------------------------------------------
local Gate = {}

-- Anchoring to a protected frame waits until combat ends.
local function Restricted(frame)
	if not InCombatLockdown() then return false end
	return E.FrameCheck(frame, "IsProtected")
end

local function Anchor(gate)
	local parent = gate.anchorTo
	if type(parent) ~= "table" then return end
	gate:ClearAllPoints()
	gate:SetAllPoints(parent)
	local ok, level = pcall(parent.GetFrameLevel, parent)
	if ok and type(level) == "number" and not issecret(level) then
		gate:SetFrameLevel(level + gate.levelOffset)
	end
	gate.anchored = true
	gate.pendingAnchor = nil
	if gate.Relayout then gate:Relayout() end
end

function Gate:SetAnchor(frame)
	self.anchorTo = frame or self:GetParent()
	if Restricted(self.anchorTo) then
		if not self.pendingAnchor then
			self.pendingAnchor = true
			E:RunOutOfCombat(function() Anchor(self) end)
		end
		return false
	end
	Anchor(self)
	return true
end

local function Flat(gate, layer, sub)
	local texture = gate.inner:CreateTexture(nil, layer or "OVERLAY", nil, sub or 6)
	texture:SetTexture(E.media.flat)
	return texture
end

local function HideLook(gate)
	for _, texture in ipairs(gate.textures) do texture:Hide() end
	if gate.zone then gate.zone:Hide() end
	if gate.divider then gate.divider:Hide() end
	if gate.glowKey and gate.lookGlow then
		E:HideGlow(gate.inner)
		gate.lookGlow = nil
	end
end

local function Edges(gate, size)
	local t = gate.textures
	for index = 1, 4 do t[index] = t[index] or Flat(gate) end
	local px = E:PixelFor(gate) * size
	local inner = gate.inner
	t[1]:ClearAllPoints() t[1]:SetPoint("TOPLEFT", inner) t[1]:SetPoint("TOPRIGHT", inner) t[1]:SetHeight(px)
	t[2]:ClearAllPoints() t[2]:SetPoint("BOTTOMLEFT", inner) t[2]:SetPoint("BOTTOMRIGHT", inner) t[2]:SetHeight(px)
	t[3]:ClearAllPoints() t[3]:SetPoint("TOPLEFT", inner) t[3]:SetPoint("BOTTOMLEFT", inner) t[3]:SetWidth(px)
	t[4]:ClearAllPoints() t[4]:SetPoint("TOPRIGHT", inner) t[4]:SetPoint("BOTTOMRIGHT", inner) t[4]:SetWidth(px)
	for index = 1, 4 do
		t[index]:SetAlpha(1)
		t[index]:Show()
	end
	for index = 5, #t do t[index]:Hide() end
end

-- Width of the gate (our own frame) as a plain number, or nil.
local function PlainWidth(gate)
	local ok, w = pcall(gate.GetWidth, gate)
	if not ok or type(w) ~= "number" or issecret(w) or w <= 0 then return nil end
	return w
end

-- LINE and ZONE sit at fixed positions from the setting, never from health.
local function LayoutMarks(gate)
	local opts = gate.lookOpts or EMPTY
	local w = PlainWidth(gate)
	local percent = Clamp(opts.percent, 1, 99, 20)
	if gate.divider then
		gate.divider:ClearAllPoints()
		if w then
			gate.divider:SetPoint("TOP", gate.inner, "TOPLEFT", w * percent / 100, 0)
			gate.divider:SetPoint("BOTTOM", gate.inner, "BOTTOMLEFT", w * percent / 100, 0)
			gate.divider:SetWidth(E:PixelFor(gate) * Clamp(opts.thickness, 1, 4, 1))
			gate.divider:SetShown(gate.look == "LINE" or gate.look == "ZONE")
		else
			gate.divider:Hide()
		end
	end
	if gate.zone then
		gate.zone:ClearAllPoints()
		if w and gate.look == "ZONE" then
			gate.zone:SetPoint("TOPLEFT", gate.inner, "TOPLEFT")
			gate.zone:SetPoint("BOTTOMLEFT", gate.inner, "BOTTOMLEFT")
			gate.zone:SetWidth(w * percent / 100)
			gate.zone:Show()
		else
			gate.zone:Hide()
		end
	end
	gate.markOffset = w and (w * percent / 100) or nil
end

function Gate:Relayout()
	if self.look == "BORDER" then
		Edges(self, Clamp(self.lookOpts and self.lookOpts.thickness, 1, 4, 1))
	elseif self.look == "EDGE" then
		Edges(self, Clamp(self.lookOpts and self.lookOpts.size, 2, 12, 4))
		for index = 1, 4 do self.textures[index]:SetAlpha(Clamp(self.lookOpts and self.lookOpts.alpha, 0.1, 1, 0.6)) end
	elseif self.look == "LINE" or self.look == "ZONE" then
		LayoutMarks(self)
	end
end

local LOOKS = { BORDER = true, TINT = true, EDGE = true, GLOW = true, LINE = true, ZONE = true, NONE = true }
FX.LOOKS = LOOKS

function Gate:SetLook(style, opts)
	style = LOOKS[style] and style or "BORDER"
	opts = opts or EMPTY
	local sig = Sig(opts)
	if self.look == style and self.lookSig == sig then
		self.lookOpts = opts
		return
	end
	HideLook(self)
	self.look, self.lookOpts, self.lookSig = style, opts, sig
	if style == "BORDER" or style == "EDGE" then
		self:Relayout()
	elseif style == "TINT" then
		local t = self.textures
		t[1] = t[1] or Flat(self, "ARTWORK", 7)
		t[1]:ClearAllPoints()
		t[1]:SetAllPoints(self.inner)
		t[1]:SetAlpha(Clamp(opts.alpha, 0.1, 1, 0.35))
		t[1]:Show()
		for index = 2, #t do t[index]:Hide() end
	elseif style == "GLOW" then
		self.glowKey = opts.glow or self.glowKey
		if self.glowKey then
			E:ShowUserGlow(self.inner, self.glowKey)
			self.lookGlow = true
		end
	elseif style == "LINE" or style == "ZONE" then
		-- The divider (and the zone) is a static mark in a plain color; the
		-- lit part is the border, gated by the curve.
		self.divider = self.divider or Flat(self, "OVERLAY", 7)
		self.zone = self.zone or Flat(self, "ARTWORK", 5)
		local c = type(opts.color) == "table" and opts.color or { E:GetStatusColor("execute") }
		self.divider:SetVertexColor(c[1] or 1, c[2] or 1, c[3] or 1, 1)
		self.zone:SetVertexColor(c[1] or 1, c[2] or 1, c[3] or 1, Clamp(opts.alpha, 0.05, 0.6, 0.2))
		Edges(self, Clamp(opts.thickness, 1, 4, 1))
		LayoutMarks(self)
	end
	self:UpdatePause()
end

-- Known closed only from a plain value: then a moving glow inside pauses.
function Gate:IsKnownClosed()
	return self.state == "closed"
end

function Gate:UpdatePause()
	if self.lookGlow then E:SetGlowPaused(self.inner, self.state == "closed") end
end

local function Track(gate, state)
	gate.state = state
	gate:UpdatePause()
end

function Gate:SetOpen(open)
	self:SetAlpha(open and 1 or 0)
	Track(self, open and "open" or "closed")
end

function Gate:FromBoolean(b, on, off)
	on, off = on or 1, off or 0
	if type(b) == "nil" then
		self:SetAlpha(off)
		Track(self, off == 0 and "closed" or "open")
		return false
	end
	local secret = issecret(b)
	if self.SetAlphaFromBoolean and pcall(self.SetAlphaFromBoolean, self, b, on, off) then
		if secret then
			Track(self, "secret")
		else
			Track(self, (b or off ~= 0) and "open" or "closed")
		end
		return true
	end
	if secret then
		-- No client sink for a secret boolean: stay closed, never guess.
		self:SetAlpha(off)
		Track(self, off == 0 and "closed" or "open")
		return false
	end
	self:SetAlpha(b and on or off)
	Track(self, (b or off ~= 0) and "open" or "closed")
	return true
end

-- The look's textures take the color; its alpha does the gating.
function Gate:FromColor(color)
	self:SetAlpha(1)
	if type(color) == "nil" or issecret(color) then
		for _, texture in ipairs(self.textures) do texture:SetVertexColor(1, 1, 1, 0) end
		Track(self, "closed")
		return false
	end
	local painted = true
	for index, texture in ipairs(self.textures) do
		if texture:IsShown() and not E:PaintColorResult(texture, color) then painted = false end
	end
	if not painted then
		Track(self, "closed")
		return false
	end
	local ok, _, _, _, a = pcall(color.GetRGBA, color)
	if ok and type(a) == "number" and not issecret(a) then
		Track(self, a == 0 and "closed" or "open")
	else
		Track(self, "secret")
	end
	return true
end

function Gate:FromAlpha(value)
	if type(value) == "nil" then
		self:SetAlpha(0)
		Track(self, "closed")
		return false
	end
	if not pcall(self.SetAlpha, self, value) then
		self:SetAlpha(0)
		Track(self, "closed")
		return false
	end
	if issecret(value) then
		Track(self, "secret")
	else
		Track(self, value == 0 and "closed" or "open")
	end
	return true
end

function Gate:Paint(color)
	if self.look == "GLOW" then
		if type(color) == "nil" or issecret(color) then return self:FromAlpha(nil) end
		local ok, _, _, _, a = pcall(color.GetRGBA, color)
		return self:FromAlpha(ok and a or nil)
	end
	return self:FromColor(color)
end

function Gate:Pulse(on, hz, low)
	local group = self.pulseGroup
	if not on or not E.db.general.animations then
		if group then group:Stop() end
		self.inner:SetAlpha(1)
		self.pulsing = false
		return false
	end
	if not group then
		group = self.inner:CreateAnimationGroup()
		group:SetLooping("BOUNCE")
		group.fade = group:CreateAnimation("Alpha")
		group.fade:SetSmoothing("IN_OUT")
		group.fade:SetFromAlpha(1)
		self.pulseGroup = group
	end
	hz = Clamp(hz, FX.MIN_HZ, FX.MAX_HZ, 1)
	-- One bounce leg is half a cycle.
	local duration = 1 / (2 * hz)
	group.fade:SetToAlpha(Clamp(low, 0, 0.9, 0.35))
	if group.duration ~= duration or not group:IsPlaying() then
		group:Stop()
		group.fade:SetDuration(duration)
		group.duration = duration
		group:Play()
	end
	self.pulsing = true
	return true
end

function Gate:Glow(key, on, overrides)
	if on and key then
		if self.lookGlow and self.glowKey == key and type(overrides) == "nil"
			and type(self.glowOverrides) == "nil" and E:IsGlowShown(self.inner) then
			self:UpdatePause()
			return
		end
		self.glowKey = key
		self.glowOverrides = overrides
		-- A callback during the show may clear the gate.
		self.lookGlow = true
		E:ShowUserGlow(self.inner, key, overrides)
		if not self.lookGlow then E:HideGlow(self.inner) end
	elseif self.lookGlow then
		E:HideGlow(self.inner)
		self.lookGlow = nil
		self.glowOverrides = nil
	end
	self:UpdatePause()
end

function Gate:Clear()
	self:Pulse(false)
	if self.lookGlow then
		E:HideGlow(self.inner)
		self.lookGlow = nil
		self.glowOverrides = nil
		-- The look is drawn again by the next SetLook.
		self.look = nil
	end
	if self.pulseGate then self.pulseGate:Clear() end
	if self.upperGate then self.upperGate:Clear() end
	if self.markGate then self.markGate:Clear() end
	self:SetAlpha(0)
	Track(self, "closed")
end

function E:CreateGate(parent, level)
	if type(parent) ~= "table" or not parent.CreateTexture then return nil end
	local gate = CreateFrame("Frame", nil, parent)
	gate.inner = CreateFrame("Frame", nil, gate)
	gate.inner:SetAllPoints(gate)
	gate.textures = {}
	gate.levelOffset = Clamp(level, 0, 40, 4)
	for name, fn in pairs(Gate) do gate[name] = fn end
	gate:EnableMouse(false)
	gate:SetAlpha(0)
	gate.state = "closed"
	gate:SetScript("OnSizeChanged", function(frame) frame:Relayout() end)
	gate:SetAnchor(parent)
	return gate
end
Expose("CreateGate")

---------------------------------------------------------------------------
-- 3. Glow users. castImportant moved here from the unit frames (same key
-- and defaults, so the saved look is kept) so it exists with Unit Frames
-- off. The danger glows register only when a consumer offers that effect.
---------------------------------------------------------------------------
E:RegisterGlowUser("castImportant", {
	title = "Cast bars: important spells",
	desc = "Glows round a cast bar on unit frames and nameplates while the spell is one the game marks as important.",
	order = 41,
	default = { style = "pixel", colorMode = "custom", color = { 1, 0.35, 0.1 }, lines = 8, speed = 0.3, thickness = 2, inset = 0 },
})

local GLOW_USERS = {
	unitThreat = { title = "Danger: threat", order = 42,
		desc = "The threat glow on unit frames and nameplates (Effects, Threat border with the Glow style). The game's threat state turns it on.",
		default = { style = "pulse", colorMode = "custom", color = { 1, 0.1, 0.1 }, speed = 0.2, thickness = 2 } },
	unitLowHealth = { title = "Danger: low health", order = 43,
		desc = "The glow of the low health warning on the Effects page (Glow style).",
		default = { style = "pulse", colorMode = "custom", color = { 0.9, 0.1, 0.1 }, speed = 0.2, thickness = 2 } },
	unitExecute = { title = "Danger: execute range", order = 44,
		desc = "The glow of the execute shade on the Effects page (Glow style).",
		default = { style = "pixel", colorMode = "custom", color = { 1, 0.55, 0.2 }, speed = 0.25, thickness = 2 } },
}
FX.GLOW_USERS = GLOW_USERS

local function UseGlowUser(key)
	local info = GLOW_USERS[key]
	if info and not E.glowUsers[key] then E:RegisterGlowUser(key, info) end
end

---------------------------------------------------------------------------
-- 4. Effect drivers
---------------------------------------------------------------------------
local function On(settings)
	return type(settings) == "table" and settings.enabled == true
end

local function PulseGate(gate)
	if not gate.pulseGate then
		gate.pulseGate = E:CreateGate(gate:GetParent(), gate.levelOffset + 1)
	end
	return gate.pulseGate
end

local THREAT_LOOKS = { BORDER = "BORDER", GLOW = "GLOW", TINT = "TINT" }

-- Snapshot the four settings colors so callers can rebuild the outer
-- table or edit a color in place. Equal settings reuse a fixed spec,
-- and a changed channel gets a new one.
local function ThreatSpec(gate, role, colors)
	if type(colors) ~= "table" then return Fixed(SPECS.threat, role, "role", role) end
	local previous = gate.threatColors
	local changed = type(previous) ~= "table"
	if not changed then
		for status = 0, 3 do
			local color, old = colors[status], previous[status]
			if type(color) == "table" and type(old) == "table" then
				for component = 1, 4 do
					if color[component] ~= old[component] then
						changed = true
						break
					end
				end
			elseif color ~= old then
				changed = true
			end
			if changed then break end
		end
	end
	if changed then
		local snapshot = {}
		for status = 0, 3 do
			local color = colors[status]
			snapshot[status] = type(color) == "table" and { color[1], color[2], color[3], color[4] } or color
		end
		gate.threatColors = snapshot
		gate.threatSpecs = {}
	end
	return Fixed(gate.threatSpecs, role, "role", role, "colors", gate.threatColors)
end

-- The danger mark (DESIGN.md "Never color alone"): the warning mark ("!")
-- in the threat color at the top right, shown only at the dangerous
-- status (its alpha from the threatPulse curve, which the client
-- evaluates), while Shape marks are on. So "you have aggro" (for a tank:
-- "you lost it") has a shape, not only a color.
local function MarkGate(gate, size)
	local mark = gate.markGate
	if not mark then
		mark = E:CreateGate(gate:GetParent(), gate.levelOffset + 2)
		mark.text = E:CreateText(mark.inner, size, "RIGHT", "OVERLAY")
		mark.text:SetPoint("TOPRIGHT", mark.inner, "TOPRIGHT", -3, -1)
		mark.text:SetDrawLayer("OVERLAY", 7)
		gate.markGate = mark
	end
	if mark.anchorTo ~= gate.anchorTo then mark:SetAnchor(gate.anchorTo) end
	if mark.size ~= size then
		E:SetFont(mark.text, size)
		mark.size = size
	end
	return mark
end
FX.MarkGate = MarkGate

local function ThreatMark(self, gate, status, color, role, opts)
	local symbol = opts.mark ~= false and self:StatusMark("warn") or ""
	if symbol == "" then
		if gate.markGate then gate.markGate:Clear() end
		return
	end
	local mark = MarkGate(gate, opts.markSize or 12)
	mark.text:SetText(symbol)
	if not self:PaintColorResult(mark.text, color, "SetTextColor") then
		local c = self.tokens.text.bad
		mark.text:SetTextColor(c[1], c[2], c[3])
	end
	mark:FromAlpha(self:UnitCurveEval("threatPulse", status, Fixed(SPECS.threatPulse, role, "role", role)))
end

function E:UnitFXThreat(gate, unit, settings, opts)
	if not gate then return false end
	opts = opts or EMPTY
	if not On(settings) or not UnitThreatSituation or type(unit) ~= "string" then
		gate:Clear()
		return false
	end
	local status, role = self:ThreatStatusFor(unit, opts.other, opts.role == "tank")
	local spec = ThreatSpec(gate, role, opts.colors)
	local curve = self:UnitCurve("threat", spec)
	if not curve then
		gate:Clear()
		return false
	end
	-- nil: not on this unit's threat table (a plain answer).
	if type(status) == "nil" then
		gate:Clear()
		return false
	end
	local look = THREAT_LOOKS[settings.style] or "BORDER"
	if look == "GLOW" then UseGlowUser("unitThreat") end
	local lookOpts = gate.threatLook
	if lookOpts and (lookOpts.thickness ~= opts.thickness or lookOpts.alpha ~= opts.tint) then
		gate.threatLook = nil
	end
	lookOpts = Fixed(gate, "threatLook", "glow", "unitThreat", "thickness", opts.thickness, "alpha", opts.tint)
	local color = self:UnitCurveEval("threat", status, spec)
	gate:SetLook(look, lookOpts)
	gate:Paint(color)
	ThreatMark(self, gate, status, color, role, opts)
	-- Pulse at danger: a second layer with the same look, its alpha from the
	-- pulse curve (1 only at the dangerous status), pulsing on its own.
	if settings.pulse and self.db.general.animations then
		local pulse = opts.pulseGate or PulseGate(gate)
		pulse:SetLook(look, lookOpts)
		if look ~= "GLOW" then pulse:FromColor(color) end
		pulse:FromAlpha(self:UnitCurveEval("threatPulse", status, Fixed(SPECS.threatPulse, role, "role", role)))
		pulse:Pulse(true, opts.hz or 1)
	elseif gate.pulseGate then
		gate.pulseGate:Clear()
	end
	return true
end

local HEALTH_LOOKS = { EDGE = "EDGE", TINT = "TINT", GLOW = "GLOW" }

local function CurveWarning(self, gate, result, settings, glowKey)
	local look = HEALTH_LOOKS[settings.style] or "EDGE"
	if look == "GLOW" then UseGlowUser(glowKey) end
	gate:SetLook(look, Fixed(SPECS.warnLook, glowKey, "glow", glowKey))
	gate:Paint(result)
	gate:Pulse(settings.pulse, settings.hz)
end

function E:UnitFXLowHealth(gate, unit, settings)
	if not gate then return false end
	if not On(settings) then
		gate:Clear()
		return false
	end
	local threshold = settings.threshold
	local result = self:UnitCurveHealth(unit, "lowHealth", Fixed(SPECS.lowHealth, threshold or false, "threshold", threshold))
	if type(result) == "nil" then
		gate:Clear()
		return false
	end
	CurveWarning(self, gate, result, settings, "unitLowHealth")
	return true
end

function E:UnitFXLowPower(gate, unit, settings, powerType)
	if not gate then return false end
	if not On(settings) then
		gate:Clear()
		return false
	end
	local threshold = settings.threshold
	local result = self:UnitCurvePower(unit, "lowPower", Fixed(SPECS.lowPower, threshold or false, "threshold", threshold), powerType)
	if type(result) == "nil" then
		gate:Clear()
		return false
	end
	local look = HEALTH_LOOKS[settings.style] or "TINT"
	gate:SetLook(look == "GLOW" and "TINT" or look)
	gate:Paint(result)
	gate:Pulse(settings.pulse, settings.hz)
	return true
end

local EXECUTE_LOOKS = { LINE = "LINE", ZONE = "ZONE", GLOW = "GLOW" }

-- "Use your execute spell": the spells that work below a health percent, by
-- every Forever rank (Execute, Hammer of Wrath), and that percent. Read from
-- the player's spellbook when it changes; nothing is cast.
local EXECUTE_SPELLS = {
	{ range = 20, ids = { 5308, 20658, 20660, 20661, 20662 } }, -- Execute
	{ range = 20, ids = { 24275, 24274, 24239 } },              -- Hammer of Wrath
}
local executeRange -- nil: not read yet; false: no such spell known
local function Knows(id)
	if type(IsPlayerSpell) == "function" then
		local ok, known = pcall(IsPlayerSpell, id)
		if ok and not issecret(known) and known then return true end
	end
	if C_SpellBook and type(C_SpellBook.IsSpellKnown) == "function" then
		local ok, known = pcall(C_SpellBook.IsSpellKnown, id)
		if ok and not issecret(known) and known then return true end
	end
	return false
end
-- The lower range of the player's own execute spell, or nil without one.
function E:ExecuteSpellRange()
	if type(executeRange) == "nil" then
		executeRange = false
		for _, entry in ipairs(EXECUTE_SPELLS) do
			for _, id in ipairs(entry.ids) do
				if Knows(id) and (not executeRange or entry.range > executeRange) then executeRange = entry.range end
			end
		end
	end
	return executeRange or nil
end
E:RegisterEvent("SPELLS_CHANGED", function() executeRange = nil end)

-- Execute shade (opt-in): the zone and divider sit where the setting puts
-- them; whether the unit is inside is the game's curve evaluation.
function E:UnitFXExecute(gate, unit, settings, upperGate)
	if not gate then return false end
	if not On(settings) then
		gate:Clear()
		if upperGate then upperGate:Clear() end
		return false
	end
	local look = EXECUTE_LOOKS[settings.style] or "ZONE"
	if look == "GLOW" then UseGlowUser("unitExecute") end
	local lower = settings.lower
	if settings.fromSpell then
		lower = self:ExecuteSpellRange()
		if not lower then
			gate:Clear()
			if upperGate then upperGate:Clear() end
			return false
		end
	end
	local result = self:UnitCurveHealth(unit, "execute", Fixed(SPECS.execute, lower or false, "lower", lower))
	if type(result) == "nil" then
		gate:Clear()
		if upperGate then upperGate:Clear() end
		return false
	end
	local percent = Clamp(lower, 1, 99, 20)
	gate:SetLook(look, Fixed(SPECS.executeLook, percent, "glow", "unitExecute", "percent", percent))
	gate:Paint(result)
	if upperGate then
		local upper = tonumber(settings.upper) or 0
		local upperResult = upper > 0 and self:UnitCurveHealth(unit, "execute2", Fixed(SPECS.execute2, upper, "upper", upper)) or nil
		if type(upperResult) == "nil" then
			upperGate:Clear()
		else
			local upperPercent = Clamp(upper, 1, 99, 80)
			upperGate:SetLook(look == "ZONE" and "LINE" or look, Fixed(SPECS.upperLook, upperPercent, "glow", "unitExecute", "percent", upperPercent))
			upperGate:Paint(upperResult)
		end
	end
	return true
end

function E:UnitFXImportantCast(gate, spellID, settings)
	if not gate then return nil end
	local api = C_Spell and C_Spell.IsSpellImportant
	if not On(settings) or not api or type(spellID) == "nil" then
		gate:Clear()
		return nil
	end
	local ok, important = pcall(api, spellID)
	if not ok or type(important) == "nil" then
		gate:Clear()
		return nil
	end
	gate:Glow("castImportant", true)
	gate:FromBoolean(important, 1, 0)
	gate:Pulse(settings.pulse, settings.hz or 1)
	return important
end

-- Only a plain "true" plays: a secret flag stays silent, never guessed.
function E:UnitFXImportantSound(important, settings)
	if not On(settings) or issecret(important) or type(important) ~= "boolean" or not important then return false end
	local sound = settings.sound
	if type(sound) ~= "string" or sound == "none" or sound == "" then return false end
	return self:PlayMedia(sound) and true or false
end

function E:UnitFXRange(frame, unit, settings)
	if type(frame) ~= "table" or not frame.SetAlpha then return false end
	if not On(settings) or not UnitInRange or type(unit) ~= "string" then
		frame:SetAlpha(1)
		return false
	end
	local ok, inRange = pcall(UnitInRange, unit)
	if not ok or type(inRange) == "nil" then
		frame:SetAlpha(1)
		return false
	end
	local outside = Clamp(settings.alpha, 0.1, 1, 0.5)
	if frame.SetAlphaFromBoolean and pcall(frame.SetAlphaFromBoolean, frame, inRange, 1, outside) then return true end
	if issecret(inRange) then
		frame:SetAlpha(1)
		return false
	end
	frame:SetAlpha(inRange and 1 or outside)
	return true
end

function E:UnitFXFadeIn(frame, settings)
	if not On(settings) then return false end
	return self:FadeIn(frame, settings.duration)
end

for _, name in ipairs({ "UnitFXThreat", "UnitFXLowHealth", "UnitFXLowPower", "UnitFXExecute", "UnitFXImportantCast",
	"UnitFXImportantSound", "UnitFXRange", "UnitFXFadeIn" }) do
	Expose(name)
end

---------------------------------------------------------------------------
-- 5. Absorb shield: Blizzard's calculator does the math and clamping; the
-- bar only receives its results.
---------------------------------------------------------------------------
local calculator
local function Calculator()
	-- Only a real calculator is kept: without the API nothing is cached, so
	-- a client that gains it later still gets one.
	if not calculator then
		if CreateUnitHealPredictionCalculator then
			local ok, calc = pcall(CreateUnitHealPredictionCalculator)
			if ok and calc then
				calculator = calc
				pcall(function()
					if Enum.UnitDamageAbsorbClampMode and calc.SetDamageAbsorbClampMode then
						calc:SetDamageAbsorbClampMode(Enum.UnitDamageAbsorbClampMode.MissingHealth)
					end
				end)
			end
		end
	end
	return calculator or nil
end

local function LayoutAbsorb(handle)
	local health, bar, opts = handle.health, handle.bar, handle.opts
	local fill = health:GetStatusBarTexture()
	local vertical = opts.vertical and true or false
	local reverse = opts.reverse and true or false
	bar:ClearAllPoints()
	bar:SetOrientation(vertical and "VERTICAL" or "HORIZONTAL")
	bar:SetReverseFill(reverse)
	if vertical then
		local edge, back = reverse and "BOTTOM" or "TOP", reverse and "TOP" or "BOTTOM"
		bar:SetPoint(back .. "LEFT", fill, edge .. "LEFT")
		bar:SetPoint(back .. "RIGHT", fill, edge .. "RIGHT")
		local ok, h = pcall(health.GetHeight, health)
		if ok and type(h) == "number" and not issecret(h) then bar:SetHeight(math.max(1, h)) end
	else
		local edge, back = reverse and "LEFT" or "RIGHT", reverse and "RIGHT" or "LEFT"
		bar:SetPoint("TOP" .. back, fill, "TOP" .. edge)
		bar:SetPoint("BOTTOM" .. back, fill, "BOTTOM" .. edge)
		local w = PlainWidth(health)
		if w then bar:SetWidth(w) end
	end
	local marker = handle.marker
	marker:ClearAllPoints()
	local px = E:PixelFor(health) * 2
	if vertical then
		marker:SetPoint(reverse and "BOTTOMLEFT" or "TOPLEFT", health)
		marker:SetPoint(reverse and "BOTTOMRIGHT" or "TOPRIGHT", health)
		marker:SetHeight(px)
	else
		marker:SetPoint(reverse and "TOPLEFT" or "TOPRIGHT", health)
		marker:SetPoint(reverse and "BOTTOMLEFT" or "BOTTOMRIGHT", health)
		marker:SetWidth(px)
	end
end

local function ColorAbsorb(handle)
	local r, g, b = E:GetPredictionColor("absorb")
	handle.bar:SetStatusBarColor(r or 1, g or 1, b or 1, Clamp(handle.opts.alpha, 0.1, 1, 0.35))
	r, g, b = E:GetPredictionColor("overAbsorb")
	handle.marker:SetVertexColor(r or 1, g or 1, b or 1, 0.9)
end

function E:AttachAbsorb(healthBar, opts)
	if type(healthBar) ~= "table" or not healthBar.GetStatusBarTexture then return nil end
	local handle = { health = healthBar, opts = opts or {} }
	local bar = CreateFrame("StatusBar", nil, healthBar)
	bar:SetStatusBarTexture(self.media.statusbar)
	self.statusBars[bar] = true
	local ok, level = pcall(healthBar.GetFrameLevel, healthBar)
	if ok and type(level) == "number" and not issecret(level) then bar:SetFrameLevel(level + 1) end
	bar:Hide()
	handle.bar = bar
	handle.marker = bar:CreateTexture(nil, "OVERLAY")
	handle.marker:SetTexture(self.media.flat)
	handle.marker:Hide()
	healthBar:HookScript("OnSizeChanged", function() LayoutAbsorb(handle) end)
	handle.Layout = LayoutAbsorb
	LayoutAbsorb(handle)
	ColorAbsorb(handle)
	return handle
end

function E:UpdateAbsorb(unit, handle, enabled)
	if type(handle) ~= "table" or not handle.bar then return false end
	local bar, marker = handle.bar, handle.marker
	local calc = Calculator()
	if not enabled or type(unit) ~= "string" or not calc or not UnitGetDetailedHealPrediction then
		bar:Hide()
		marker:Hide()
		return false
	end
	ColorAbsorb(handle)
	local amount, clamped
	if pcall(UnitGetDetailedHealPrediction, unit, "player", calc) then
		local ok, total, over = pcall(calc.GetDamageAbsorbs, calc)
		if ok then amount, clamped = total, over end
	end
	if type(amount) == "nil" then
		bar:Hide()
		marker:Hide()
		return false
	end
	local okMax, max = pcall(UnitHealthMax, unit)
	if okMax and type(max) ~= "nil" then pcall(bar.SetMinMaxValues, bar, 0, max) end
	pcall(bar.SetValue, bar, amount)
	bar:Show()
	-- The "clamped" flag is the game's own: shown through a boolean sink.
	if type(clamped) ~= "nil" and marker.SetAlphaFromBoolean then
		marker:Show()
		pcall(marker.SetAlphaFromBoolean, marker, clamped, 1, 0)
	else
		marker:Hide()
	end
	return true
end
Expose("AttachAbsorb")
Expose("UpdateAbsorb")

---------------------------------------------------------------------------
-- 6. Effect catalog, presets and option rows
---------------------------------------------------------------------------
-- Select values are translated centrally by Config.
local STYLE_THREAT = { BORDER = "Border", GLOW = "Glow", TINT = "Health tint" }
local STYLE_WARNING = { EDGE = "Inner edge", TINT = "Tint", GLOW = "Glow" }
local STYLE_EXECUTE = { LINE = "Divider line", ZONE = "Shaded zone", GLOW = "Glow" }
local STYLE_EXPIRING = { PULSE = "Pulse", TEXT = "Red time text", BOTH = "Pulse and red text" }

E.UNITFX_GROUPS = {
	{ key = "animations", label = "Animations" },
	{ key = "danger", label = "Danger" },
	{ key = "casts", label = "Casts" },
}

E.UNITFX_PRESET_ORDER = { "off", "subtle", "standard", "vivid" }
E.UNITFX_PRESET_TITLES = { off = "Off", subtle = "Subtle", standard = "Standard", vivid = "Vivid", custom = "Custom" }

local function ON(extra)
	local t = { enabled = true }
	for k, v in pairs(extra or EMPTY) do t[k] = v end
	return t
end
local OFF = { enabled = false }

-- Each effect: key, group, label, desc, defaults, rows (tunables, in the
-- cog), presets (per preset key, the fields it writes), requiresAPI, optIn.
E.UNITFX_EFFECTS = {
	-- Animations ---------------------------------------------------------
	{ key = "fadeIn", group = "animations", label = "Fade in when shown",
		desc = "The frame fades in when it appears, for example a new target, focus or boss. Follows General > Animations.",
		defaults = { enabled = true, duration = 0.15 },
		rows = { { type = "range", unit = "s", field = "duration", label = "Fade time", min = 0.05, max = 0.5, step = 0.05,
			desc = "Seconds the fade takes." } },
		presets = { off = OFF, subtle = ON(), standard = ON(), vivid = ON() } },
	{ key = "targetFlash", group = "animations", label = "Target change flash",
		desc = "A short flash on the frame when your target changes. Follows General > Animations.",
		defaults = { enabled = false, duration = 0.3 },
		rows = { { type = "range", unit = "s", field = "duration", label = "Flash time", min = 0.2, max = 0.5, step = 0.05,
			desc = "Seconds the flash takes to fade." } },
		presets = { off = OFF, subtle = OFF, standard = OFF, vivid = ON() } },
	{ key = "castFade", group = "animations", label = "Cast bar fade",
		desc = "Cast bars fade in and out instead of popping. Follows General > Animations.",
		defaults = { enabled = true },
		presets = { off = OFF, subtle = ON(), standard = ON(), vivid = ON() } },
	{ key = "castSpark", group = "animations", label = "Cast bar spark",
		desc = "A bright line at the end of the cast bar fill.",
		defaults = { enabled = true },
		presets = { off = OFF, subtle = ON(), standard = ON(), vivid = ON() } },
	{ key = "questPop", group = "animations", label = "Quest icon pop",
		desc = "The quest icon pops in when a unit becomes part of one of your quests.",
		defaults = { enabled = true },
		presets = { off = OFF, subtle = ON(), standard = ON(), vivid = ON() } },
	{ key = "auraPop", group = "animations", label = "Aura pop-in",
		desc = "New buffs and debuffs pop in. The game plays the animation.",
		unavailable = function() return E.AuraWidget and E.AuraWidget.popInBlocked end,
		defaults = { enabled = true },
		presets = { off = OFF, subtle = ON(), standard = ON(), vivid = ON() } },
	{ key = "auraExpiring", group = "animations", label = "Aura expiring",
		desc = "In the last seconds of an aura its icon pulses or its time turns red.",
		defaults = { enabled = false, style = "PULSE", seconds = 5 },
		rows = {
			{ type = "select", field = "style", label = "Style", values = STYLE_EXPIRING,
				desc = "How an aura that is about to run out shows.",
				valueDescs = { PULSE = E.Key("The icon breathes."), TEXT = E.Key("The time turns red."), BOTH = E.Key("The icon breathes and the time turns red.") } },
			{ type = "range", unit = "s", field = "seconds", label = "Seconds left", min = 1, max = 10, step = 1,
				desc = "The red time text starts at this many seconds left." },
		},
		presets = { off = OFF, subtle = OFF, standard = OFF, vivid = ON({ style = "PULSE" }) } },
	{ key = "statusPulse", group = "animations", label = "Resurrection and summon pulse",
		desc = "The status icon breathes while a resurrection or summon is on its way.",
		defaults = { enabled = true },
		presets = { off = OFF, subtle = ON(), standard = ON(), vivid = ON() } },
	-- Danger -------------------------------------------------------------
	{ key = "threat", group = "danger", label = "Threat border", requiresAPI = "UnitThreatSituation",
		desc = "A border, glow or tint in the threat color (Colors page). Only the game's threat state is used; the game's color curve shows it even where the state is hidden.",
		defaults = { enabled = false, style = "BORDER", pulse = false },
		rows = {
			{ type = "select", field = "style", label = "Style", values = STYLE_THREAT,
				desc = "Border: a thin line round the frame. Glow: the look from the Glows page (Danger: threat). Health tint: the bar takes the color." },
			{ type = "toggle", field = "pulse", label = "Pulse at danger",
				desc = "Pulses slowly when it matters most: when you have aggro as damage dealer or healer, or lose it as a tank. Static with animations off." },
		},
		presets = { off = OFF, subtle = OFF, standard = ON({ style = "BORDER", pulse = false }), vivid = ON({ style = "BORDER", pulse = true }) } },
	{ key = "anotherTank", group = "danger", label = "Another tank has it", requiresAPI = "UnitThreatSituation",
		desc = "Tanks only: a calm color (Colors page) for mobs another tank in your group holds. Only when the game shows that tank's threat.",
		defaults = { enabled = false },
		presets = { off = OFF, subtle = OFF, standard = OFF, vivid = OFF } },
	{ key = "lowHealth", group = "danger", label = "Low health warning",
		requiresAPI = { "UnitHealthPercent", "C_CurveUtil.CreateColorCurve" },
		desc = "Warns you when a frame's health drops below the value you set, with a red edge, tint or glow. The game's own red screen edge is a separate setting in Options > Combat.",
		defaults = { enabled = false, threshold = 30, style = "EDGE", pulse = false, hz = 1 },
		rows = {
			{ type = "range", field = "threshold", label = "Below health", unit = "%", min = 10, max = 50, step = 5,
				desc = "The warning shows while the unit's health is under this percent." },
			{ type = "select", field = "style", label = "Style", values = STYLE_WARNING,
				desc = "How the warning shows on the frame.",
				valueDescs = { EDGE = E.Key("A red band inside the frame."), TINT = E.Key("The frame takes the color."), GLOW = E.Key("The look from the Glows page (Danger: low health).") } },
			{ type = "toggle", field = "pulse", label = "Pulse",
				desc = "The warning pulses slowly. Static with animations off." },
			{ type = "range", field = "hz", label = "Pulse speed", unit = "/s", min = 0.5, max = 2, step = 0.25,
				desc = "Pulses per second, at most two." },
		},
		presets = { off = OFF, subtle = ON({ style = "EDGE", pulse = false }), standard = ON({ style = "EDGE", pulse = false }),
			vivid = ON({ style = "EDGE", pulse = true }) } },
	{ key = "lowPower", group = "danger", label = "Low power tint",
		requiresAPI = { "UnitPowerPercent", "C_CurveUtil.CreateColorCurve" },
		desc = "The power bar turns the low power color (Colors page) when it drops below the value you set. Handy for keeping an eye on a healer's mana.",
		defaults = { enabled = false, threshold = 20 },
		rows = { { type = "range", field = "threshold", label = "Below power", unit = "%", min = 5, max = 50, step = 5,
			desc = "The tint shows while power is under this percent." } },
		presets = { off = OFF, subtle = OFF, standard = OFF, vivid = OFF } },
	{ key = "execute", group = "danger", label = "Execute shade", optIn = true,
		requiresAPI = { "UnitHealthPercent", "C_CurveUtil.CreateColorCurve" },
		desc = "Shades the bottom of the health bar and highlights the frame once a target is low enough for your execute spell. Turn it on yourself; no preset does.",
		defaults = { enabled = false, fromSpell = false, lower = 20, upper = 0, style = "ZONE" },
		rows = {
			{ type = "toggle", field = "fromSpell", label = "Use your execute spell",
				desc = "The lower range comes from your own spell: 20 % with Execute or Hammer of Wrath. Without such a spell, no shade shows." },
			{ type = "range", field = "lower", label = "Below health", unit = "%", min = 5, max = 50, step = 1,
				disabledWhen = "fromSpell", disabledReason = E.Key("Taken from your execute spell."),
				desc = "The shade starts once health is under this percent." },
			{ type = "range", field = "upper", label = "Above health", unit = "%", zeroText = "Off", min = 0, max = 95, step = 1,
				desc = "A second shade above this percent, for abilities that work on healthy units." },
			{ type = "select", field = "style", label = "Style", values = STYLE_EXECUTE,
				desc = "How the execute range shows on the health bar.",
				valueDescs = { LINE = E.Key("A mark at the percent."), ZONE = E.Key("The range is tinted."), GLOW = E.Key("The look from the Glows page (Danger: execute range).") } },
		} },
	{ key = "absorb", group = "danger", label = "Absorb shield", requiresAPI = "CreateUnitHealPredictionCalculator",
		desc = "The unit's absorb shield over the health bar. Color on the Colors page.",
		defaults = { enabled = false },
		presets = { off = OFF, subtle = OFF, standard = ON(), vivid = ON() } },
	{ key = "range", group = "danger", label = "Out-of-range fade", requiresAPI = "UnitInRange",
		desc = "Group members out of range fade. The game answers the range; the frame's alpha comes straight from it.",
		defaults = { enabled = true, alpha = 0.5 },
		rows = { { type = "range", percent = true, field = "alpha", label = "Out-of-range opacity", min = 0.1, max = 1, step = 0.05,
			desc = "Opacity of a member who is out of range." } },
		presets = { off = OFF, subtle = ON(), standard = ON(), vivid = ON() } },
	{ key = "deadLook", group = "danger", label = "Dead and offline look",
		desc = "Dead, ghost and offline units take their colors from the Colors page.",
		defaults = { enabled = true },
		presets = { off = OFF, subtle = ON(), standard = ON(), vivid = ON() } },
	-- Casts --------------------------------------------------------------
	{ key = "importantGlow", group = "casts", label = "Important cast glow", requiresAPI = "C_Spell.IsSpellImportant",
		desc = "A glow while the game marks the spell as important. The look is on the Glows page (Cast bars: important spells), shared by every cast bar.",
		defaults = { enabled = true, pulse = false },
		rows = { { type = "toggle", field = "pulse", label = "Pulse",
			desc = "The glow also pulses slowly. Static with animations off." } },
		presets = { off = ON({ pulse = false }), subtle = ON({ pulse = false }), standard = ON({ pulse = false }), vivid = ON({ pulse = true }) } },
	{ key = "interrupter", group = "casts", label = "Interrupter's name",
		desc = "Shows who interrupted a cast, like the game's own cast bar.",
		defaults = { enabled = true },
		presets = { off = OFF, subtle = ON(), standard = ON(), vivid = ON() } },
	{ key = "importantSound", group = "casts", label = "Important cast sound", optIn = true,
		requiresAPI = "C_Spell.IsSpellImportant",
		desc = "A sound when a cast starts that the game marks as important. Stays silent where the game hides that flag. Off by default; no preset turns it on.",
		defaults = { enabled = false, sound = "kit:RAID_WARNING" },
		rows = { { type = "media", field = "sound", label = "Sound", mediaKind = "sound",
			desc = "The sound to play. General > Sounds has the volume channel." } } },
}

local effectsByKey = {}
for index, effect in ipairs(E.UNITFX_EFFECTS) do
	effect.order = index
	effectsByKey[effect.key] = effect
end

function E:UnitFXEffect(key) return effectsByKey[key] end

-- Consumers: their effect list and their preset changes.
local consumers = {}
FX.consumers = consumers

local function AllEffects()
	local list = {}
	for _, effect in ipairs(E.UNITFX_EFFECTS) do list[#list + 1] = effect.key end
	return list
end

local function Consumer(name)
	return consumers[name or ""] or { effects = AllEffects(), presets = {} }
end

local function CopyValue(value)
	if type(value) == "table" then return CopyTable(value) end
	return value
end

-- The fields preset `key` writes for an effect, with the consumer's
-- changes merged on top. nil for opt-in effects: no preset touches them.
local function PresetFields(info, key, effect)
	if effect.optIn then return nil end
	local fields = {}
	for field, value in pairs(effect.presets and effect.presets[key] or EMPTY) do fields[field] = value end
	local own = info.presets[key] and info.presets[key][effect.key]
	for field, value in pairs(own or EMPTY) do fields[field] = value end
	return fields
end

local function Has(list, key)
	for _, k in ipairs(list) do if k == key then return true end end
	return false
end

-- A module uses the effects (registered its presets). Until one does, the
-- effect colors on General > Colors stay hidden (Core/MediaRegistry.lua).
function E:UnitFXInUse()
	return next(consumers) and true or false
end

function E:RegisterUnitFXPresets(consumer, presets, effects)
	if type(consumer) ~= "string" then return false end
	local list = {}
	for _, key in ipairs(type(effects) == "table" and effects or AllEffects()) do
		if effectsByKey[key] then list[#list + 1] = key end
	end
	local clean = {}
	for _, key in ipairs(E.UNITFX_PRESET_ORDER) do
		clean[key] = {}
		for effectKey, fields in pairs(type(presets) == "table" and presets[key] or EMPTY) do
			local effect = effectsByKey[effectKey]
			-- Opt-in effects stay the player's own choice.
			if effect and not effect.optIn and type(fields) == "table" then clean[key][effectKey] = CopyTable(fields) end
		end
	end
	consumers[consumer] = { effects = list, presets = clean }
	if Has(list, "threat") then UseGlowUser("unitThreat") end
	if Has(list, "lowHealth") then UseGlowUser("unitLowHealth") end
	if Has(list, "execute") then UseGlowUser("unitExecute") end
	return true
end

function E:ApplyUnitFXPreset(block, key, consumer)
	if type(block) ~= "table" or not E.UNITFX_PRESET_TITLES[key] or key == "custom" then return false end
	local info = Consumer(consumer)
	for _, effectKey in ipairs(info.effects) do
		local effect = effectsByKey[effectKey]
		local fields = PresetFields(info, key, effect)
		if fields then
			block[effectKey] = type(block[effectKey]) == "table" and block[effectKey] or CopyTable(effect.defaults)
			for field, value in pairs(fields) do block[effectKey][field] = CopyValue(value) end
		end
	end
	block.preset = key
	return true
end

local function Matches(block, key, info)
	for _, effectKey in ipairs(info.effects) do
		local effect = effectsByKey[effectKey]
		local fields = PresetFields(info, key, effect)
		if fields then
			local current = type(block[effectKey]) == "table" and block[effectKey] or EMPTY
			for field, value in pairs(fields) do
				if current[field] ~= value then return false end
			end
		end
	end
	return true
end

function E:UnitFXPresetOf(block, consumer)
	if type(block) ~= "table" then return "custom" end
	local info = Consumer(consumer)
	for _, key in ipairs(E.UNITFX_PRESET_ORDER) do
		if Matches(block, key, info) then return key end
	end
	return "custom"
end

local function Values(row)
	local values = row.values
	if type(values) == "function" then values = values() end
	return type(values) == "table" and values or EMPTY
end

local function FillEffect(block, effect)
	local settings = block[effect.key]
	if type(settings) ~= "table" then
		settings = CopyTable(effect.defaults)
		block[effect.key] = settings
	end
	for field, value in pairs(effect.defaults) do
		if type(settings[field]) == "nil" then settings[field] = CopyValue(value) end
	end
	if type(settings.enabled) ~= "boolean" then settings.enabled = effect.defaults.enabled and true or false end
	for _, row in ipairs(effect.rows or EMPTY) do
		local value = settings[row.field]
		if row.type == "range" then
			settings[row.field] = Clamp(value, row.min, row.max, effect.defaults[row.field])
		elseif row.type == "select" and type(Values(row)[value]) == "nil" then
			settings[row.field] = effect.defaults[row.field]
		elseif row.type == "toggle" and type(value) ~= "boolean" then
			settings[row.field] = effect.defaults[row.field] and true or false
		end
	end
end

-- Remembers the preset each block was last brought in line with, so a
-- changed dropdown writes its preset and a changed row shows Custom
-- (the pattern of Core/Visibility.lua). Runtime only.
local applied = setmetatable({}, { __mode = "k" })

function E:NormalizeUnitFX(block, consumer)
	if type(block) ~= "table" then return end
	local info = Consumer(consumer)
	for _, effectKey in ipairs(info.effects) do FillEffect(block, effectsByKey[effectKey]) end
	local preset = block.preset
	local named = E.UNITFX_PRESET_TITLES[preset] and preset ~= "custom"
	if named and type(applied[block]) ~= "nil" and applied[block] ~= preset then
		self:ApplyUnitFXPreset(block, preset, consumer)
	elseif not (named and Matches(block, preset, info)) then
		block.preset = self:UnitFXPresetOf(block, consumer)
	end
	applied[block] = block.preset
end

function E:UnitFXDefaults(consumer, preset)
	local block = { preset = "subtle" }
	local info = Consumer(consumer)
	for _, effectKey in ipairs(info.effects) do
		block[effectKey] = CopyTable(effectsByKey[effectKey].defaults)
	end
	self:ApplyUnitFXPreset(block, preset or "subtle", consumer)
	applied[block] = nil
	return block
end

local function GetPath(tbl, path)
	for part in tostring(path):gmatch("[^%.]+") do
		if type(tbl) ~= "table" then return nil end
		tbl = tbl[part]
	end
	return tbl
end

function E:UnitFXOptions(path, opts)
	opts = opts or {}
	local consumer = opts.consumer
	local info = Consumer(consumer)
	local list = {}
	for _, key in ipairs(opts.effects or info.effects) do
		if effectsByKey[key] and Has(info.effects, key) then list[#list + 1] = key end
	end
	local p = path .. "."
	local parentHidden = opts.hidden
	local function Block()
		local db = opts.db and opts.db()
		local block = db and GetPath(db, path)
		if type(block) == "table" then
			E:NormalizeUnitFX(block, consumer)
			return block
		end
	end
	local function Hidden(effectKey)
		return function()
			if type(parentHidden) == "function" and parentHidden() then return true end
			local own = type(parentHidden) == "table" and parentHidden[effectKey]
			if type(own) == "function" and own() then return true end
			if own == true then return true end
			local effect = effectKey and effectsByKey[effectKey]
			if effect and effect.unavailable and effect.unavailable() then return true end
			Block()
			return false
		end
	end
	-- Off, Subtle, Standard, Vivid in that order. Custom is a state, not a
	-- pick (choosing it would change nothing): it is listed only while the
	-- rows match no preset, so the select can still name it.
	local function PresetValues()
		local values = {}
		for _, key in ipairs(E.UNITFX_PRESET_ORDER) do values[key] = E.UNITFX_PRESET_TITLES[key] end
		local block = Block()
		if block and block.preset == "custom" then values.custom = E.UNITFX_PRESET_TITLES.custom end
		return values
	end
	local presetOrder = {}
	for index, key in ipairs(E.UNITFX_PRESET_ORDER) do presetOrder[index] = key end
	presetOrder[#presetOrder + 1] = "custom"
	local rows = {}
	if opts.label ~= false then
		rows[#rows + 1] = { type = "header", label = opts.label or "Effects", hidden = Hidden(nil) }
	end
	rows[#rows + 1] = { type = "select", key = p .. "preset", label = "Effects preset", values = PresetValues, order = presetOrder,
		desc = "Off: only the important cast glow. Subtle: gentle motion and basic warnings. Standard: adds threat and absorbs. Vivid: adds pulses and flashes. Changing a row below makes it Custom.",
		hidden = Hidden(nil) }
	for _, group in ipairs(E.UNITFX_GROUPS) do
		local first = true
		for _, key in ipairs(list) do
			local effect = effectsByKey[key]
			if effect.group == group.key then
				if first then
					rows[#rows + 1] = { type = "header", label = group.label, hidden = Hidden(nil) }
					first = false
				end
				local hidden = Hidden(key)
				rows[#rows + 1] = { type = "toggle", key = p .. key .. ".enabled", label = effect.label, desc = effect.desc,
					requiresAPI = effect.requiresAPI, hidden = hidden }
				for _, row in ipairs(effect.rows or EMPTY) do
					local option = { type = row.type, key = p .. key .. "." .. row.field, label = row.label, desc = row.desc,
						cog = true, min = row.min, max = row.max, step = row.step, unit = row.unit, percent = row.percent,
						zeroText = row.zeroText, values = row.values,
						-- A choice's own line in the dropdown, in the player's language.
						valueDescs = row.valueDescs and function()
							local descs = {}
							for value, text in pairs(row.valueDescs) do descs[value] = E:Translate(text) end
							return descs
						end,
						mediaKind = row.mediaKind, requiresAPI = effect.requiresAPI, hidden = hidden }
					if row.disabledWhen then
						local field, reason = row.disabledWhen, row.disabledReason
						option.disabled = function()
							local block = Block()
							local settings = block and block[key]
							if type(settings) == "table" and settings[field] then return E:Translate(reason) end
						end
					end
					rows[#rows + 1] = option
				end
			end
		end
	end
	return rows
end

for _, name in ipairs({ "UnitFXEffect", "UnitFXInUse", "RegisterUnitFXPresets", "ApplyUnitFXPreset", "UnitFXPresetOf",
	"NormalizeUnitFX", "UnitFXDefaults", "UnitFXOptions" }) do
	Expose(name)
end

-- Diagnostics: what this client offers the effects.
do
	E:RegisterDiagnostics("UnitFX", function()
		return {
			("curves %s, UnitHealthPercent %s, UnitPowerPercent %s"):format(tostring(CurveAPI()),
				tostring(type(UnitHealthPercent) == "function"), tostring(type(UnitPowerPercent) == "function")),
			("SetAlphaFromBoolean %s, important-spell flag %s, heal calculator %s"):format(
				tostring(type(UIParent and UIParent.SetAlphaFromBoolean) == "function"),
				tostring(type(C_Spell and C_Spell.IsSpellImportant) == "function"),
				tostring(type(CreateUnitHealPredictionCalculator) == "function")),
			("curves built %d"):format(FX.stats.builds),
		}
	end)
end

