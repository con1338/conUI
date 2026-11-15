-- Combat Text animation styles. Each style is a function of the line's
-- progress p (0 at the start, 1 at the end) that returns where the line
-- sits inside its box and how it looks:
--   x, y    offset of the line's center from the bottom center of the box
--   alpha   0-1
--   scale   >0 (1 = normal)
-- Nothing is measured: every position comes from the box size, the fixed
-- line height and the line's slot, so secret text never moves a frame.
--
-- E.CombatText:RegisterAnimation(key, {
--     title = "My style", kind = "scroll" | "sticky" | "plate",
--     duration = 1.6,   -- seconds at 100 % speed
--     position = function(p, line, width, height) return x, y, alpha, scale end,
-- })
-- line fields a style may read: up (true when the area scrolls up), bend
-- (-1 left, 1 right), side (-1 or 1, alternates line by line), slot (0 =
-- newest), lineHeight, shake, crit (plate lines: a critical hit).
-- A plate style may set critDuration for critical hits.
-- Written from scratch for EldoUI.
local _, E = ...
local L = E.L
local M = E:GetModule("CombatText")

M.animations = {}
M.animationOrder = { scroll = {}, sticky = {}, plate = {} }

function M:RegisterAnimation(key, def)
	if type(key) ~= "string" or type(def) ~= "table" or type(def.position) ~= "function" then
		error("RegisterAnimation(key, { kind, duration, position }): bad arguments", 2)
	end
	def.key = key
	def.kind = def.kind or "scroll"
	def.duration = def.duration or 1.6
	def.title = def.title or key
	if not self.animations[key] then table.insert(self.animationOrder[def.kind] or self.animationOrder.scroll, key) end
	self.animations[key] = def
	return def
end

-- Option values of one kind ("scroll", "sticky", "plate").
function M:AnimationValues(kind)
	local values = {}
	for _, key in ipairs(self.animationOrder[kind] or {}) do values[key] = self.animations[key].title end
	return values
end

local sin, pi = math.sin, math.pi

-- Fade over the last quarter (and a quick fade-in).
local function Fade(p)
	if p < 0.06 then return p / 0.06 end
	if p > 0.75 then return math.max(0, (1 - p) / 0.25) end
	return 1
end

-- Height along the box: from one edge to the other.
local function Travel(p, line, height)
	local margin = line.lineHeight / 2
	local span = math.max(0, height - line.lineHeight)
	if line.up then return margin + p * span end
	return margin + (1 - p) * span
end

M:RegisterAnimation("straight", { title = L["Straight"], duration = 1.7,
	position = function(p, line, _, height)
		return 0, Travel(p, line, height), Fade(p), 1
	end })

M:RegisterAnimation("arc", { title = L["Arc"], duration = 1.8,
	position = function(p, line, width, height)
		return line.bend * sin(p * pi) * width * 0.35, Travel(p, line, height), Fade(p), 1
	end })

M:RegisterAnimation("angled", { title = L["Angled"], duration = 1.7,
	position = function(p, line, width, height)
		return line.bend * (p - 0.5) * width * 0.6, Travel(p, line, height), Fade(p), 1
	end })

-- Pushed sideways (alternating sides), then drops back.
M:RegisterAnimation("fountain", { title = L["Fountain"], duration = 1.6,
	position = function(p, line, width, height)
		local rise = 4 * p * (1 - p) -- 0 -> 1 -> 0
		local base = line.lineHeight / 2
		local y = base + rise * math.max(0, height - line.lineHeight)
		if not line.up then y = height - y end
		return line.side * p * width * 0.4, y, Fade(p), 1
	end })

-- Lines stand still; the newest on top, older ones step down.
M:RegisterAnimation("stack", { title = L["Stack"], duration = 3.5,
	position = function(p, line, _, height)
		local y
		if line.up then
			y = line.lineHeight * (line.slot + 0.5)
		else
			y = height - line.lineHeight * (line.slot + 0.5)
		end
		return 0, y, Fade(p), 1
	end })

-- Sticky styles: in the middle of the box, stacked by slot.
local function StickyY(line, height)
	local y = height / 2 - line.slot * line.lineHeight
	if line.up then y = height / 2 + line.slot * line.lineHeight end
	return y
end

-- A fixed shake pattern (no randomness: the same every time).
local SHAKE = { 3, -3, 2, -2, 1, -1 }
local function Shake(p, line)
	if not line.shake or p > 0.15 then return 0 end
	return SHAKE[math.floor(p / 0.15 * #SHAKE) + 1] or 0
end

M:RegisterAnimation("pop", { title = L["Pop"], kind = "sticky", duration = 2.2,
	position = function(p, line, _, height)
		local scale = 1
		if p < 0.08 then scale = 1.6 - (p / 0.08) * 0.6 end
		local alpha = p > 0.8 and math.max(0, (1 - p) / 0.2) or 1
		return Shake(p, line), StickyY(line, height), alpha, scale
	end })

M:RegisterAnimation("hold", { title = L["Hold"], kind = "sticky", duration = 2.2,
	position = function(p, line, _, height)
		local alpha = p < 0.05 and p / 0.05 or (p > 0.8 and math.max(0, (1 - p) / 0.2) or 1)
		return Shake(p, line), StickyY(line, height), alpha, 1
	end })

---------------------------------------------------------------------------
-- The Punchy style's motion (Options.lua): quick off the mark, slowing
-- down, and a soft fade at the end.
---------------------------------------------------------------------------
-- 0 -> 1, fast at first.
local function EaseOut(t)
	local u = 1 - t
	return 1 - u * u * u
end
M.EaseOut = EaseOut

-- 0 -> a little past 1 -> 1: the size of a punch overshoots and settles.
local function Overshoot(t)
	local c, u = 1.9, t - 1
	return 1 + (c + 1) * u * u * u + c * u * u
end
M.Overshoot = Overshoot

-- Fully there for longer, then gone softly.
local function SoftFade(p)
	if p < 0.05 then return p / 0.05 end
	if p > 0.62 then
		local t = (p - 0.62) / 0.38
		return math.max(0, 1 - t * t)
	end
	return 1
end
M.SoftFade = SoftFade

-- Thrown off the start edge, slowing down along a slight bend, a little
-- bigger for its first moment.
M:RegisterAnimation("throw", { title = L["Throw"], duration = 1.6,
	position = function(p, line, width, height)
		local e = EaseOut(p)
		local scale = p < 0.1 and (1.3 - 0.3 * EaseOut(p / 0.1)) or 1
		return line.bend * sin(e * pi) * width * 0.25, Travel(e, line, height), SoftFade(p), scale
	end })

-- In at twice the size, past normal and back, with a short shake.
M:RegisterAnimation("punch", { title = L["Punch"], kind = "sticky", duration = 2.0,
	position = function(p, line, _, height)
		local scale = p < 0.12 and (2 - Overshoot(p / 0.12)) or 1
		return Shake(p, line), StickyY(line, height), SoftFade(p), scale
	end })

-- Plate styles: offsets above the plate's text anchor (height = rise room).
M:RegisterAnimation("rise", { title = L["Rise"], kind = "plate", duration = 1.2,
	position = function(p, line, _, height)
		return 0, p * height, Fade(p), 1
	end })

M:RegisterAnimation("plateFountain", { title = L["Fountain"], kind = "plate", duration = 1.2,
	position = function(p, line, width, height)
		return line.side * p * width, 4 * p * (1 - p) * height, Fade(p), 1
	end })

M:RegisterAnimation("platePop", { title = L["Pop"], kind = "plate", duration = 1.1,
	position = function(p, line)
		local scale = p < 0.1 and (1.5 - p / 0.1 * 0.5) or 1
		local alpha = p > 0.7 and math.max(0, (1 - p) / 0.3) or 1
		return 0, line.slot * line.lineHeight, alpha, scale
	end })

M:RegisterAnimation("plateStack", { title = L["Stack"], kind = "plate", duration = 1.6,
	position = function(p, line)
		return 0, line.slot * line.lineHeight, Fade(p), 1
	end })

-- Thrown off the plate to alternating sides, rising fast and sinking a
-- little at the end; a critical hit punches out above the plate instead.
M:RegisterAnimation("plateThrow", { title = L["Throw"], kind = "plate", duration = 1.05, critDuration = 1.3,
	position = function(p, line, width, height)
		if line.crit then
			local scale = p < 0.18 and (2.1 - 1.1 * Overshoot(p / 0.18)) or 1
			return Shake(p, line), height * 0.3 + height * 0.6 * EaseOut(p), SoftFade(p), scale
		end
		local e = EaseOut(p)
		local scale = p < 0.12 and (1.25 - 0.25 * EaseOut(p / 0.12)) or 1
		return line.side * width * 0.7 * e, height * 1.15 * e - height * 0.4 * p * p, SoftFade(p), scale
	end })
