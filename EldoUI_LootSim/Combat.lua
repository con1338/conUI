-- EldoUI Loot Sim: combat formulas.
--
-- Plain functions over numbers, written from the public Classic game
-- mechanics (the community-documented attack table, armor, spell hit and
-- resistance rules). Nothing here reads the game; Engine.lua and the class
-- models call these with the character sheet Reader.lua took.
--
-- Melee attack table against a target (attacks from behind, so no parry or
-- block). The defense of a mob is 5 x its level; diff = defense - weapon skill.
--   miss   5 % + 0.1 % per point of diff (diff above 10: 0.2 % per point and
--          the first 1 % of hit from gear does nothing); dual wielding adds
--          19 % to white swings; never below 0
--   dodge  5 % + 0.1 % per point of diff
--   glance (white swings at a target of your level or higher)
--          10 % + 2 % per point of (defense - min(skill, 5 x your level));
--          a glancing blow does (low + high) / 2 of its damage with
--          low = 1.3 - 0.05 x diff (0.01 .. 0.91), high = 1.2 - 0.03 x diff
--          (0.2 .. 0.99): 65 % at +15, 85 % at +10
--   crit   the sheet's crit, minus 0.2 % per point of diff above 10 (0.04 %
--          per point up to 10); limited by what is left of the table
--   hit    the rest
-- White swings use one roll over that table. Special attacks roll miss and
-- dodge first, then crit on a hit (no glancing).
-- Armor: reduction = armor / (armor + 400 + 85 x attacker level), up to 75 %.
-- Spells: hit 96 / 95 / 94 % against +0 / +1 / +2 levels, 83 % at +3, then
-- 11 % less per level; at most 99 % with hit from gear. A level advantage
-- gives the target 8 resistance per level; the average part resisted is
-- 0.75 x resistance / (5 x attacker level) (6 % against a boss at 60).
-- Rage: 7.5 x damage / c per hit, c = 0.0091107836 L^2 + 3.225598133 L + 4.2652911.
-- Normalized weapon speeds for instant attacks: dagger 1.7, one-hand 2.4,
-- two-hand 3.3, ranged 2.8.
-- Spell power coefficients: direct spells cast time / 3.5 (1.5 s .. 3.5 s),
-- damage over time duration / 15, spells below level 20 lose 3.75 % per level.
local _, S = ...

local C = {}
S.Combat = C

local function Clamp(value, low, high)
	if value < low then return low end
	if value > high then return high end
	return value
end
C.Clamp = Clamp

-- Defense of a target minus your weapon skill.
function C.SkillDiff(targetLevel, skill)
	return targetLevel * 5 - skill
end

-- Melee miss chance (percent) after hit from gear.
function C.MissChance(diff, hit, dualWield)
	hit = hit or 0
	local miss
	if diff > 10 then
		miss = 5 + diff * 0.2
		hit = math.max(0, hit - 1)
	elseif diff >= 0 then
		miss = 5 + diff * 0.1
	else
		miss = 5 + diff * 0.04
	end
	if dualWield then miss = miss + 19 end
	return Clamp(miss - hit, 0, 100)
end

-- expertise: percent the game's sheet gives (GetExpertise), taken off.
function C.DodgeChance(diff, expertise)
	return Clamp(5 + diff * 0.1 - (expertise or 0), 0, 100)
end

function C.GlanceChance(targetLevel, playerLevel, skill)
	if targetLevel < playerLevel then return 0 end
	local diff = targetLevel * 5 - math.min(skill, playerLevel * 5)
	return Clamp(10 + diff * 2, 0, 100)
end

-- Damage a glancing blow keeps (0..1).
function C.GlanceMultiplier(diff)
	local low = Clamp(1.3 - 0.05 * diff, 0.01, 0.91)
	local high = Clamp(1.2 - 0.03 * diff, 0.2, 0.99)
	if low > high then low = high end
	return (low + high) / 2
end

function C.CritChance(crit, diff)
	if diff > 10 then return math.max(0, crit - diff * 0.2) end
	if diff > 0 then return math.max(0, crit - diff * 0.04) end
	return crit
end

-- The white-swing table: { miss, dodge, glance, crit } as percent (the rest
-- hits) and the glancing damage multiplier.
function C.WhiteTable(opts)
	local diff = C.SkillDiff(opts.targetLevel, opts.skill)
	local miss = C.MissChance(diff, opts.hit, opts.dualWield)
	local dodge = opts.noDodge and 0 or C.DodgeChance(diff, opts.expertise)
	local glance = opts.ranged and 0 or C.GlanceChance(opts.targetLevel, opts.level, opts.skill)
	local room = math.max(0, 100 - miss - dodge - glance)
	local crit = math.min(C.CritChance(opts.crit or 0, diff), room)
	return { miss = miss, dodge = dodge, glance = glance, crit = crit, glanceMult = C.GlanceMultiplier(diff) }
end

-- Special attacks: miss and dodge, then crit on a hit.
function C.YellowTable(opts)
	local diff = C.SkillDiff(opts.targetLevel, opts.skill)
	local miss = C.MissChance(diff, opts.hit, false)
	local dodge = opts.noDodge and 0 or C.DodgeChance(diff, opts.expertise)
	return { miss = miss, dodge = dodge, crit = Clamp(C.CritChance(opts.crit or 0, diff), 0, 100) }
end

function C.ArmorReduction(armor, attackerLevel)
	armor = math.max(0, armor or 0)
	local reduction = armor / (armor + 400 + 85 * attackerLevel)
	return Clamp(reduction, 0, 0.75)
end

-- Spell hit chance (percent). The game's hit tooltip names 17 % spell hit
-- to never miss a raid boss, so hit reaches 100 %.
function C.SpellHitChance(levelDiff, hit)
	local base
	if levelDiff <= 2 then
		base = 96 - math.max(levelDiff, -4)
	else
		base = 94 - (levelDiff - 2) * 11
	end
	return Clamp(base + (hit or 0), 1, 100)
end

-- Average fraction of a spell's damage the target resists.
function C.ResistFraction(levelDiff, attackerLevel, extraResist)
	local resist = math.max(0, levelDiff) * 8 + (extraResist or 0)
	if resist <= 0 then return 0 end
	return Clamp(0.75 * resist / (5 * math.max(attackerLevel, 1)), 0, 0.75)
end

function C.RageConversion(level)
	return 0.0091107836 * level * level + 3.225598133 * level + 4.2652911
end

function C.RageFromDamage(damage, level)
	return 7.5 * damage / C.RageConversion(level)
end

C.NORMALIZED = { dagger = 1.7, onehand = 2.4, twohand = 3.3, ranged = 2.8 }

-- Spell power coefficient of a direct spell (cast time in seconds).
function C.DirectCoefficient(castTime)
	return Clamp(castTime or 1.5, 1.5, 3.5) / 3.5
end

function C.DotCoefficient(duration)
	return Clamp((duration or 15) / 15, 0, 1)
end

function C.ChannelCoefficient(duration)
	return Clamp((duration or 3.5) / 3.5, 0, 1)
end

-- Spells learned before level 20 count less of your spell power.
function C.LowLevelPenalty(spellLevel)
	if not spellLevel or spellLevel >= 20 then return 1 end
	return Clamp(1 - (20 - spellLevel) * 0.0375, 0, 1)
end

-- Target armor of a training dummy by level (our own table from public
-- Classic mob armor: about 20 per level early on, 3731 for a level 63 boss).
local ARMOR_BY_LEVEL = { { 1, 20 }, { 10, 200 }, { 20, 650 }, { 30, 1200 }, { 40, 1900 }, { 50, 2700 }, { 60, 3300 }, { 63, 3731 } }
function C.TargetArmor(level)
	level = Clamp(level or 60, 1, 63)
	for index = 2, #ARMOR_BY_LEVEL do
		local low, high = ARMOR_BY_LEVEL[index - 1], ARMOR_BY_LEVEL[index]
		if level <= high[1] then
			local t = (level - low[1]) / (high[1] - low[1])
			return math.floor(low[2] + (high[2] - low[2]) * t + 0.5)
		end
	end
	return ARMOR_BY_LEVEL[#ARMOR_BY_LEVEL][2]
end
