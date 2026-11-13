-- EldoUI Spell Efficiency: efficiency lines on spell tooltips,
-- worked out only from the numbers the tooltip itself shows.
--
--   "DPS 84.2 · DPM 1.9 · 6% mana"   (HPS and HPM for heals)
--   Shift: the inputs (average of the range, cast time or the global
--   cooldown, the part over time and its duration).
--   On a rank you don't use (the Training window, a trainer, a link):
--   "Your rank 6: DPM 1.7" next to this rank's numbers.
--
-- Sources, all static: the spell's description (C_Spell.GetSpellDescription,
-- the same text the tooltip shows), its cast time (C_Spell.GetSpellInfo)
-- and its power cost (C_Spell.GetSpellPowerCost); your own maximum mana
-- for the share of your pool. No combat log, no crits, no spell power, no
-- hit chance: the tooltip's numbers and nothing else.
--
-- The description is read with patterns per client language (enUS and
-- deDE below). The game has no global strings for spell descriptions, so
-- the patterns are EldoUI's own. A description no pattern understands gives
-- no line at all; nothing is guessed. Shields ("absorbs") and procs ("when
-- struck") are left out on purpose.
--
-- Public API (E.SpellEfficiency):
--   M.Parse(text[, locale])  -> { kind, direct, min, max, over, duration, channel } or nil
--   M:Numbers(spellID)       -> { parse, cast, time, cost, power, dps, dpm, pct } or nil
--   M:Lines(spellID, shift)  -> { { left, right } } the rows the tooltip gets
-- Written from scratch for EldoUI; no code, strings or data from other addons.
local _, E = ...
local L = E.L

local GCD = 1.5
local GCD_ENERGY = 1.0
local MANA = (Enum and Enum.PowerType and Enum.PowerType.Mana) or 0
local ENERGY = (Enum and Enum.PowerType and Enum.PowerType.Energy) or 3

local M = E:NewModule("SpellEfficiency", {
	title = "Spell Efficiency",
	desc = "Damage or healing per second and per mana, and the mana cost as a share of your pool, on spell tooltips. Worked out from the tooltip's own numbers.",
	category = "Combat",
	savedKeys = { "profile.modules.SpellEfficiency" },
	optionsPage = "module:SpellEfficiency",
	presets = { "OneLine", "Detailed", "NumbersOnly", "ManaFocus", "ForeverBronze" },
	reload = false,
	defaults = {
		perSecond = true,         -- DPS / HPS
		perMana = true,           -- DPM / HPM
		manaShare = true,         -- cost as % of your mana
		decimals = 1,
		oneLine = true,           -- all values in one line (else one row each)
		inputs = true,            -- Shift adds the inputs
		compareRanks = true,      -- "Your rank N" on a rank you don't use
		accentValues = false,     -- the values in the accent color
	},
})
E.SpellEfficiency = M

local Secret = E.Secret

local Read = E.PlainCall

---------------------------------------------------------------------------
-- Description patterns
---------------------------------------------------------------------------
-- Each locale: number(text) reads one number; skip lists words that make
-- a description unsafe to read (shields, procs); heal finds a heal; range,
-- flat, over, channel find the parts. All patterns are plain Lua patterns
-- over the description, which the client gives in its own language.
local LOCALES = {}

LOCALES.enUS = {
	number = function(text) return tonumber((text:gsub(",", ""))) end,
	skip = { "absorb", "attacker", "when struck", "each time", "next melee", "chance on hit" },
	heal = function(lower) return lower:find("heal", 1, true) ~= nil end,
	-- "14 to 22 Fire damage", "for 47 to 58"
	range = "(%d[%d,]*) to (%d[%d,]*)",
	-- "2 Fire damage over 4 sec", "of 45 damage over 15 sec", "for 32 over 12 sec"
	over = { "(%d[%d,]*)[%a%s]-damage over (%d+%.?%d*) sec", "(%d[%d,]*) over (%d+%.?%d*) sec" },
	-- "causing 26 Arcane damage each second for 3 sec"
	channel = { "(%d[%d,]*)[%a%s]-damage each second for (%d+%.?%d*) sec", "(%d[%d,]*)[%a%s]-damage every second for (%d+%.?%d*) sec" },
	-- "for 11 Fire damage and", "causes 30 Holy damage." (not followed by over / each)
	flat = { damage = "(%d[%d,]*)[%a%s]-damage", heal = "for (%d[%d,]*)" },
	overFollows = { "^[%a%s]-damage over", "^ over", "^[%a%s]-damage each second", "^[%a%s]-damage every second" },
}

LOCALES.deDE = {
	-- German writes 1.234 for thousands and 1,5 for decimals.
	number = function(text) return tonumber((text:gsub("%.", ""):gsub(",", "."))) end,
	skip = { "absorbiert", "angreifer", "bei jedem", "chance", "nächste" },
	heal = function(lower) return lower:find("heil", 1, true) ~= nil end,
	-- "14 bis 22 Feuerschaden", "um 47 bis 58"
	range = "(%d[%d%.]*) bis (%d[%d%.]*)",
	-- "im Verlauf von 18 Sek. 30 Schattenschaden", "im Verlauf von 4 Sek. zusätzlich 2 Feuerschaden",
	-- "im Verlauf von 15 Sek. um 45 Punkte" (duration first)
	overFirst = { "im Verlauf von (%d+,?%d*) Sek%.[^%d]-(%d[%d%.]*)" },
	channel = {},
	flat = { damage = "(%d[%d%.]*) [^%d%s]-schaden", heal = "um (%d[%d%.]*)" },
	overFollows = {},
}

-- Clients that write spell descriptions in the same words as another one
-- (European English reports "enGB").
local ALIASES = { enGB = "enUS" }

local function LocaleRules(locale)
	locale = locale or (GetLocale and GetLocale())
	return LOCALES[ALIASES[locale] or locale] or nil
end
M.LOCALES = LOCALES

-- Positions of every match of `pattern` in text: { { s, e, a, b }, ... }
local function All(text, pattern)
	local list, start = {}, 1
	while true do
		local s, e, a, b = text:find(pattern, start)
		if not s then break end
		list[#list + 1] = { s = s, e = e, a = a, b = b }
		start = e + 1
	end
	return list
end

local function Inside(pos, spans)
	for _, span in ipairs(spans) do
		if pos >= span.s and pos <= span.e then return true end
	end
	return false
end

function M.Parse(text, locale)
	if type(text) ~= "string" or Secret(text) or text == "" then return nil end
	local rules = LocaleRules(locale)
	if not rules then return nil end
	local lower = text:lower()
	for _, word in ipairs(rules.skip) do
		if lower:find(word, 1, true) then return nil end
	end
	local result = { kind = rules.heal(lower) and "heal" or "damage" }
	local used = {}
	-- Over time (duration after the amount; enUS)
	for _, pattern in ipairs(rules.over or {}) do
		local hit = All(text, pattern)[1]
		if hit and not result.over then
			result.over, result.duration = rules.number(hit.a), rules.number(hit.b)
			used[#used + 1] = hit
		end
	end
	-- Over time (duration first; deDE)
	for _, pattern in ipairs(rules.overFirst or {}) do
		local hit = All(text, pattern)[1]
		if hit and not result.over then
			result.duration, result.over = rules.number(hit.a), rules.number(hit.b)
			used[#used + 1] = hit
		end
	end
	-- Channels: per second for N seconds
	for _, pattern in ipairs(rules.channel or {}) do
		local hit = All(text, pattern)[1]
		if hit and not result.over then
			local each, duration = rules.number(hit.a), rules.number(hit.b)
			if each and duration then
				result.over, result.duration, result.channel = each * duration, duration, true
				used[#used + 1] = hit
			end
		end
	end
	-- Direct: a range first, else one flat amount that is not part of the above.
	for _, hit in ipairs(All(text, rules.range)) do
		if not Inside(hit.s, used) then
			local low, high = rules.number(hit.a), rules.number(hit.b)
			local rest = text:sub(hit.e + 1)
			local isOver = false
			for _, follow in ipairs(rules.overFollows or {}) do
				if rest:find(follow) then isOver = true end
			end
			if low and high and high >= low and not isOver then
				result.min, result.max, result.direct = low, high, (low + high) / 2
				used[#used + 1] = hit
				break
			end
		end
	end
	if not result.direct then
		local flat = rules.flat[result.kind] or rules.flat.damage
		for _, hit in ipairs(All(text, flat)) do
			if not Inside(hit.s, used) then
				local rest = text:sub(hit.e + 1)
				local isOver = false
				for _, follow in ipairs(rules.overFollows or {}) do
					if rest:find(follow) then isOver = true end
				end
				local value = rules.number(hit.a)
				if value and not isOver then
					result.direct, result.min, result.max = value, value, value
					break
				end
			end
		end
	end
	if not (result.direct or result.over) then return nil end
	if result.over and not (result.duration and result.duration > 0) then return nil end
	return result
end

---------------------------------------------------------------------------
-- Numbers for one spell
---------------------------------------------------------------------------
local function ManaCost(spellID)
	local costs = Read(C_Spell and C_Spell.GetSpellPowerCost, spellID)
	if type(costs) ~= "table" then return nil end
	for _, info in ipairs(costs) do
		if type(info) == "table" and not Secret(info.type) and not Secret(info.cost) then
			if info.type == MANA and type(info.cost) == "number" and info.cost > 0 then return info.cost, MANA end
			if info.type == ENERGY then return nil, ENERGY end
		end
	end
	return nil
end

local function CastSeconds(spellID)
	local info = Read(C_Spell and C_Spell.GetSpellInfo, spellID)
	if type(info) ~= "table" or Secret(info.castTime) or type(info.castTime) ~= "number" then return nil end
	return math.max(0, info.castTime / 1000)
end

function M:Numbers(spellID)
	if Secret(spellID) or type(spellID) ~= "number" then return nil end
	local parse = M.Parse(Read(C_Spell and C_Spell.GetSpellDescription, spellID))
	if not parse then return nil end
	local cast = CastSeconds(spellID) or 0
	local cost, power = ManaCost(spellID)
	local floor = power == ENERGY and GCD_ENERGY or GCD
	local out = { parse = parse, cast = cast, cost = cost, power = power }
	local total = (parse.direct or 0) + (parse.over or 0)
	if parse.channel then
		-- A channel's time is its duration.
		out.time = math.max(parse.duration, floor)
		out.dps = total / out.time
	elseif parse.direct then
		out.time = math.max(cast, floor)
		out.dps = parse.direct / out.time
		if parse.over then out.dot = parse.over / parse.duration end
	else
		-- Only over time: its total over its duration.
		out.time = parse.duration
		out.dps = parse.over / parse.duration
	end
	out.total = total
	if cost then
		out.dpm = total / cost
		local maxMana = Read(UnitPowerMax, "player", MANA)
		if type(maxMana) == "number" and maxMana > 0 then out.pct = cost / maxMana * 100 end
	end
	return out
end

---------------------------------------------------------------------------
-- Lines
---------------------------------------------------------------------------
-- Halves round up, the same on every system (the C library's own
-- rounding differs between them).
local function Fmt(value)
	local decimals = math.max(0, math.min(2, tonumber(M.db.decimals) or 1))
	local scale = 10 ^ decimals
	return ("%." .. decimals .. "f"):format(math.floor(value * scale + 0.5) / scale)
end

local function Value(text)
	if M.db.accentValues then
		local c = E.media.accentColor
		return ("|cff%02x%02x%02x%s|r"):format(c[1] * 255, c[2] * 255, c[3] * 255, text)
	end
	return text
end

local function Parts(numbers)
	local db, heal = M.db, numbers.parse.kind == "heal"
	local parts = {}
	if db.perSecond and numbers.dps then
		parts[#parts + 1] = { heal and L["HPS"] or L["DPS"], Value(Fmt(numbers.dps)) }
	end
	if db.perSecond and numbers.dot then
		parts[#parts + 1] = { heal and L["HoT/s"] or L["DoT/s"], Value(Fmt(numbers.dot)) }
	end
	if db.perMana and numbers.dpm then
		parts[#parts + 1] = { heal and L["HPM"] or L["DPM"], Value(Fmt(numbers.dpm)) }
	end
	if db.manaShare and numbers.pct then
		parts[#parts + 1] = { L["Mana"], Value(("%d%%"):format(math.floor(numbers.pct + 0.5))) }
	end
	return parts
end

local function Joined(parts)
	local bits = {}
	for _, part in ipairs(parts) do
		if part[1] == L["Mana"] then
			bits[#bits + 1] = L["%s mana"]:format(part[2])
		else
			bits[#bits + 1] = part[1] .. " " .. part[2]
		end
	end
	return table.concat(bits, " · ")
end

-- The spell ID of the rank you know with the same name, when it differs.
local function KnownRank(spellID)
	local name = Read(C_Spell and C_Spell.GetSpellName, spellID)
	if type(name) ~= "string" then return nil end
	local info = Read(C_Spell and C_Spell.GetSpellInfo, name)
	local known = type(info) == "table" and not Secret(info.spellID) and info.spellID or nil
	if type(known) ~= "number" or known == spellID then return nil end
	return known
end
M.KnownRank = KnownRank

function M:Lines(spellID, shift)
	local numbers = self:Numbers(spellID)
	if not numbers then return {} end
	local parts = Parts(numbers)
	local rows = {}
	if #parts > 0 then
		if self.db.oneLine then
			rows[#rows + 1] = { Joined(parts) }
		else
			for _, part in ipairs(parts) do rows[#rows + 1] = { part[1], part[2] } end
		end
	end
	if shift and self.db.inputs then
		local parse = numbers.parse
		if parse.direct then
			local range = parse.min ~= parse.max and ("%s-%s"):format(parse.min, parse.max) or tostring(parse.direct)
			rows[#rows + 1] = { L["Average"], ("%s (%s)"):format(Fmt(parse.direct), range) }
		end
		if parse.over then
			rows[#rows + 1] = { parse.channel and L["Channel"] or L["Over time"], L["%s over %s sec"]:format(parse.over, parse.duration) }
		end
		local timeText = Fmt(numbers.time) .. " " .. L["sec"]
		if not parse.channel and parse.direct and numbers.cast < numbers.time then timeText = timeText .. " " .. L["(global cooldown)"] end
		rows[#rows + 1] = { L["Time"], timeText }
		if numbers.cost then rows[#rows + 1] = { L["Mana cost"], tostring(numbers.cost) } end
	end
	if self.db.compareRanks then
		local known = KnownRank(spellID)
		local other = known and self:Numbers(known)
		if other then
			local rank = Read(C_Spell and C_Spell.GetSpellSubtext, known)
			local label = type(rank) == "string" and rank ~= "" and L["Your %s"]:format(rank) or L["Your rank"]
			local otherParts = Parts(other)
			if #otherParts > 0 then rows[#rows + 1] = { label, Joined(otherParts) } end
		end
	end
	return rows
end

local LABEL = E.tokens.text.secondary
local BODY = E.tokens.text.body

-- The rows go into the tooltip's shared info area, as the "Spell
-- efficiency" section: when it shows (Always, with Shift, Ctrl or Alt, or
-- Never) is picked on the Tooltip page like every other part of that area.
function M.SectionRows(_, spellID, add)
	if not M.active or Secret(spellID) or type(spellID) ~= "number" then return end
	for _, row in ipairs(M:Lines(spellID, IsShiftKeyDown())) do
		if row[2] then
			add(row[1], row[2], LABEL[1], LABEL[2], LABEL[3], BODY[1], BODY[2], BODY[3])
		else
			add(row[1], nil, BODY[1], BODY[2], BODY[3])
		end
	end
end

E:RegisterTooltipSection("spellEfficiency", { order = 55, title = "Spell efficiency", default = "always",
	desc = "On a spell: damage or healing per second and per mana, and the mana cost as a share of your pool (Spell Efficiency module).",
	spell = M.SectionRows, module = "SpellEfficiency" })

-- The module adds nothing of its own besides the section: on and off only
-- redraw the tooltip under the cursor, so the line comes or goes at once.
function M:OnEnable()
	E:RefreshTooltipSections()
end

function M:OnDisable()
	E:RefreshTooltipSections()
end

function M:OnProfileChanged()
	E:RefreshTooltipSections()
end

-- "Show the line" used to be a setting of this module; it is now the
-- section's own choice on the Tooltip page.
function M.MigrateMode(profile)
	local modules = type(profile) == "table" and type(profile.modules) == "table" and profile.modules
	local own = modules and type(modules.SpellEfficiency) == "table" and modules.SpellEfficiency
	if not own or own.mode == nil then return end
	local mode = own.mode
	own.mode = nil
	if not (mode == "always" or mode == "shift" or mode == "ctrl" or mode == "alt" or mode == "never") then return end
	if type(modules.Tooltip) ~= "table" then modules.Tooltip = {} end
	if type(modules.Tooltip.sections) ~= "table" then modules.Tooltip.sections = {} end
	local sections = modules.Tooltip.sections
	if sections.spellEfficiency == nil then sections.spellEfficiency = mode end
end
E:RegisterProfileMigration(M.MigrateMode, "SpellEfficiency:mode", 1)
