-- EldoUI Loot Sim: our own spell tables and stat rules.
--
-- Written by us from public Classic game mechanics. Each ability names the
-- spell ID of its first rank: the reader looks the name up in your own
-- spellbook (the game returns the highest rank you know) and reads the
-- numbers from that rank's own description. The numbers below are only a
-- fallback for a description the client has not loaded yet (the top rank at
-- level 60, scaled down for lower levels).
--
-- Ability fields:
--   kind      melee (special weapon attack), queue (replaces the next main
--             hand swing), ranged (special shot), spell (direct), dot,
--             channel, finisher (combo points), buff
--   school    physical, holy, fire, nature, frost, shadow, arcane
--   weapon    adds a weapon swing (mult = share of it), normalized = uses
--             the normalized weapon speed
--   bonus     flat damage on top of the weapon; apPct = percent of attack power
--   min, max  damage of a spell (dot: total over the duration)
--   cost      rage, energy or mana; cd = cooldown, cast = cast time (s)
--   parse     how the description gives the numbers: "range" (x to y),
--             "first" (the first number), "percent" (the first n %),
--             "afterPercent" (the number after "n %"), "perTick" (per tick)
--   coef      spell power coefficient when it is not the standard rule
local _, S = ...
-- The reasons in D.NOT_SIMULATED are shown in the Character tab.
local L = S.E and S.E.L or setmetatable({}, { __index = function(_, key) return key end })

local D = {}
S.Data = D

---------------------------------------------------------------------------
-- Stats: what one point gives, per class (level 60 values; lower levels get
-- more crit per point, scaled in Gear.lua).
--   apStr, apAgi: melee attack power per point; rapAgi: ranged
--   critAgi: agility for 1 % melee crit; spellCritInt: intellect for 1 %
--   regen: mana per 2 s tick out of the five second rule = base + spirit / div
---------------------------------------------------------------------------
D.CLASS = {
	WARRIOR = { apStr = 2, apAgi = 0, rapAgi = 1, critAgi = 20, power = "rage" },
	PALADIN = { apStr = 2, apAgi = 0, rapAgi = 0, critAgi = 20, spellCritInt = 54, regen = { 15, 5 }, power = "mana" },
	HUNTER = { apStr = 1, apAgi = 1, rapAgi = 2, critAgi = 53, spellCritInt = nil, regen = { 15, 5 }, power = "mana" },
	ROGUE = { apStr = 1, apAgi = 1, rapAgi = 1, critAgi = 29, power = "energy" },
	PRIEST = { apStr = 1, apAgi = 0, rapAgi = 0, critAgi = 20, spellCritInt = 59.2, regen = { 13, 4 }, power = "mana" },
	SHAMAN = { apStr = 2, apAgi = 0, rapAgi = 0, critAgi = 20, spellCritInt = 59.5, regen = { 17, 5 }, power = "mana" },
	MAGE = { apStr = 1, apAgi = 0, rapAgi = 0, critAgi = 20, spellCritInt = 59.5, regen = { 13, 4 }, power = "mana" },
	WARLOCK = { apStr = 1, apAgi = 0, rapAgi = 0, critAgi = 20, spellCritInt = 60.6, regen = { 8, 4 }, power = "mana" },
	DRUID = { apStr = 2, apAgi = 0, apAgiCat = 1, rapAgi = 0, critAgi = 20, spellCritInt = 60, regen = { 15, 5 }, power = "mana" },
}
D.MANA_PER_INT = 15
D.ENERGY_TICK = 20      -- energy every 2 s
D.ENERGY_MAX = 100

-- Target choices in the simulator window: levels above yours.
D.TARGETS = { { key = "same", plus = 0 }, { key = "plus1", plus = 1 }, { key = "plus2", plus = 2 }, { key = "boss", plus = 3 } }
D.LENGTHS = { 60, 180, 300 }
D.SPEEDS = { smooth = 4, fast = 8, turbo = 16 }

---------------------------------------------------------------------------
-- Abilities per class
---------------------------------------------------------------------------
D.SPELLS = {
	WARRIOR = {
		heroicStrike = { id = 78, kind = "queue", school = "physical", bonus = 157, cost = 15, parse = "first" },
		mortalStrike = { id = 12294, kind = "melee", school = "physical", weapon = true, normalized = true, bonus = 160, cost = 30, cd = 6, parse = "first" },
		bloodthirst = { id = 23881, kind = "melee", school = "physical", apPct = 45, cost = 30, cd = 6, parse = "percent" },
		whirlwind = { id = 1680, kind = "melee", school = "physical", weapon = true, normalized = true, cost = 25, cd = 10 },
		overpower = { id = 7384, kind = "melee", school = "physical", weapon = true, normalized = true, bonus = 35, cost = 5, cd = 5, noDodge = true, afterDodge = true, parse = "first" },
		shieldSlam = { id = 23922, kind = "melee", school = "physical", min = 342, max = 358, cost = 20, cd = 6, parse = "range" },
		sunderArmor = { id = 7386, kind = "melee", school = "physical", cost = 15, armor = 450, stacks = 5, noDamage = true },
		bloodrage = { id = 2687, kind = "buff", school = "physical", rage = 20, cd = 60, offGcd = true },
		deathWish = { id = 12292, kind = "buff", school = "physical", cost = 10, cd = 180, duration = 30, damage = 0.2 },
	},
	ROGUE = {
		sinisterStrike = { id = 1752, kind = "melee", school = "physical", weapon = true, normalized = true, bonus = 68, cost = 45, builder = true, parse = "first" },
		backstab = { id = 53, kind = "melee", school = "physical", weapon = true, normalized = true, mult = 1.5, bonus = 225, cost = 60, builder = true, dagger = true, parse = "afterPercent" },
		hemorrhage = { id = 16511, kind = "melee", school = "physical", weapon = true, normalized = true, cost = 35, builder = true },
		ambush = { id = 8676, kind = "melee", school = "physical", weapon = true, normalized = true, mult = 2.5, bonus = 290, cost = 60, builder = true, dagger = true, opener = true, parse = "afterPercent" },
		eviscerate = { id = 2098, kind = "finisher", school = "physical", cost = 35, perPoint = { { 224, 332 }, { 394, 502 }, { 564, 672 }, { 734, 842 }, { 904, 1012 } } },
		sliceAndDice = { id = 5171, kind = "buff", school = "physical", cost = 25, finisher = true, haste = 0.2, base = 6, perPoint = 3 },
		bladeFlurry = { id = 13877, kind = "buff", school = "physical", cost = 25, cd = 120, duration = 15, haste = 0.2 },
		adrenalineRush = { id = 13750, kind = "buff", school = "physical", cd = 300, duration = 15, energyRate = 2 },
	},
	HUNTER = {
		-- WoW: Forever (client tables of 1.60.1.70862): Aimed Shot casts in
		-- 2 s with a flat bonus up to 350 at its top rank; it and Multi-Shot
		-- share one 6 s cooldown, and Multi-Shot adds no flat damage.
		aimedShot = { id = 19434, kind = "ranged", school = "physical", weapon = true, bonus = 350, cost = 310, cd = 6, cast = 2, share = "shot", parse = "first" },
		multiShot = { id = 2643, kind = "ranged", school = "physical", weapon = true, bonus = 0, cost = 230, cd = 6, share = "shot" },
		arcaneShot = { id = 3044, kind = "spell", school = "arcane", min = 183, max = 183, cost = 225, cd = 6, coef = 0, parse = "first" },
		serpentSting = { id = 1978, kind = "dot", school = "nature", min = 555, max = 555, duration = 15, ticks = 5, cost = 225, coef = 0, parse = "first" },
		rapidFire = { id = 3045, kind = "buff", school = "physical", cd = 300, duration = 15, rangedHaste = 0.4, offGcd = true },
		huntersMark = { id = 1130, kind = "buff", school = "arcane", cost = 60, rap = 110, parse = "first", once = true },
	},
	MAGE = {
		frostbolt = { id = 116, kind = "spell", school = "frost", min = 515, max = 555, cost = 290, cast = 3, coef = 0.814, parse = "range" },
		fireball = { id = 133, kind = "spell", school = "fire", min = 596, max = 760, cost = 410, cast = 3.5, coef = 1, dot = 76, dotDuration = 8, parse = "range" },
		-- Coefficients from the game's spell effects: 0.286 per missile.
		arcaneMissiles = { id = 5143, kind = "channel", school = "arcane", min = 1150, max = 1150, duration = 5, ticks = 5, cost = 655, coef = 1.43, parse = "perTick" },
		fireBlast = { id = 2136, kind = "spell", school = "fire", min = 446, max = 524, cost = 340, cd = 8, parse = "range" },
		scorch = { id = 2948, kind = "spell", school = "fire", min = 237, max = 280, cost = 150, cast = 1.5, parse = "range" },
		arcanePower = { id = 12042, kind = "buff", school = "arcane", cd = 180, duration = 15, damage = 0.3, costMult = 1.3, offGcd = true },
		evocation = { id = 12051, kind = "channel", school = "arcane", noDamage = true, duration = 8, cd = 480, manaPct = 60 },
	},
	WARLOCK = {
		shadowBolt = { id = 686, kind = "spell", school = "shadow", min = 482, max = 538, cost = 380, cast = 3, coef = 0.857, parse = "range" },
		-- Corruption 0.2 per 3 s tick, Bane of Agony 0.133 per 2 s tick.
		corruption = { id = 172, kind = "dot", school = "shadow", min = 822, max = 822, duration = 18, ticks = 6, cost = 340, cast = 2, coef = 1.2, parse = "first" },
		curseOfAgony = { id = 980, kind = "dot", school = "shadow", min = 1044, max = 1044, duration = 24, ticks = 12, cost = 265, coef = 1.596, parse = "first" },
		immolate = { id = 348, kind = "spell", school = "fire", min = 279, max = 279, cost = 380, cast = 2, coef = 0.2, dot = 510, dotDuration = 15, dotCoef = 0.65, parse = "first" },
		siphonLife = { id = 18265, kind = "dot", school = "shadow", min = 450, max = 450, duration = 30, ticks = 10, cost = 410, coef = 0.5, parse = "first" },
		lifeTap = { id = 1454, kind = "buff", school = "shadow", mana = 424, parse = "first" },
	},
	PRIEST = {
		mindBlast = { id = 8092, kind = "spell", school = "shadow", min = 503, max = 531, cost = 350, cast = 1.5, cd = 8, parse = "range" },
		-- Shadow Word: Pain 0.2 per 3 s tick, Mind Flay 0.167 per 1 s tick,
		-- Holy Fire 0.75 and 0.05 per 2 s tick.
		shadowWordPain = { id = 589, kind = "dot", school = "shadow", min = 852, max = 852, duration = 18, ticks = 6, cost = 470, coef = 1.2, parse = "first" },
		mindFlay = { id = 15407, kind = "channel", school = "shadow", min = 426, max = 426, duration = 3, ticks = 3, cost = 205, coef = 0.501, parse = "first" },
		smite = { id = 585, kind = "spell", school = "holy", min = 371, max = 421, cost = 280, cast = 2.5, parse = "range" },
		holyFire = { id = 14914, kind = "spell", school = "holy", min = 355, max = 449, cost = 290, cast = 3.5, coef = 0.75, dot = 145, dotDuration = 10, dotCoef = 0.25, parse = "range" },
	},
	PALADIN = {
		sealOfRighteousness = { id = 21084, kind = "buff", school = "holy", cost = 120, duration = 30, seal = "righteousness", perSpeed = 17, coef = 0.092 },
		sealOfCommand = { id = 20375, kind = "buff", school = "holy", cost = 65, duration = 30, seal = "command", ppm = 7, weaponPct = 70, coef = 0.2 },
		-- rangedHit: a ranged attack's miss roll since the hotfix of 11 November 2026 (Engine.lua, Fight:SpellLands).
		judgement = { id = 20271, kind = "spell", school = "holy", min = 116, max = 127, cost = 86, cd = 10, coef = 0.5, judge = true, rangedHit = true },
		consecration = { id = 26573, kind = "dot", school = "holy", min = 384, max = 384, duration = 8, ticks = 4, cost = 565, cd = 8, coef = 0.33, parse = "first" },
	},
	SHAMAN = {
		-- Lightning Bolt 0.714; Flame Shock 0.214 and 0.1 per 3 s tick.
		lightningBolt = { id = 403, kind = "spell", school = "nature", min = 428, max = 477, cost = 265, cast = 3, coef = 0.714, parse = "range" },
		chainLightning = { id = 421, kind = "spell", school = "nature", min = 493, max = 551, cost = 760, cast = 2.5, cd = 6, coef = 0.714, parse = "range" },
		earthShock = { id = 8042, kind = "spell", school = "nature", min = 517, max = 545, cost = 345, cd = 6, coef = 0.386, shock = true, parse = "range" },
		flameShock = { id = 8050, kind = "spell", school = "fire", min = 292, max = 292, cost = 450, cd = 6, coef = 0.214, dot = 320, dotDuration = 12, dotCoef = 0.4, shock = true, parse = "first" },
		stormstrike = { id = 17364, kind = "melee", school = "physical", weapon = true, cost = 319, cd = 20, natureBonus = 0.2, charges = 2 },
	},
	DRUID = {
		shred = { id = 5221, kind = "melee", school = "physical", weapon = true, mult = 2.25, bonus = 180, cost = 60, builder = true, form = "cat", parse = "afterPercent" },
		claw = { id = 1082, kind = "melee", school = "physical", weapon = true, bonus = 115, cost = 45, builder = true, form = "cat", parse = "first" },
		ferociousBite = { id = 22568, kind = "finisher", school = "physical", cost = 35, form = "cat", energyDamage = 2.5,
			perPoint = { { 199, 259 }, { 346, 406 }, { 493, 553 }, { 640, 700 }, { 787, 847 } } },
		maul = { id = 6807, kind = "queue", school = "physical", bonus = 128, cost = 15, form = "bear", parse = "first" },
		swipe = { id = 779, kind = "melee", school = "physical", min = 83, max = 83, cost = 20, form = "bear", parse = "first" },
		starfire = { id = 2912, kind = "spell", school = "arcane", min = 540, max = 636, cost = 370, cast = 3.5, parse = "range" },
		wrath = { id = 5176, kind = "spell", school = "nature", min = 278, max = 313, cost = 180, cast = 2, coef = 0.571, parse = "range" },
		moonfire = { id = 8921, kind = "spell", school = "arcane", min = 195, max = 228, cost = 375, coef = 0.15, dot = 384, dotDuration = 12, dotCoef = 0.52, parse = "range" },
		-- Insect Swarm 0.158 per 2 s tick.
		insectSwarm = { id = 5570, kind = "dot", school = "nature", min = 324, max = 324, duration = 12, ticks = 6, cost = 160, coef = 0.948, parse = "first" },
	},
}

-- Fill in keys and defaults once.
for class, spells in pairs(D.SPELLS) do
	for key, spell in pairs(spells) do
		spell.key, spell.class = key, class
		spell.min = spell.min or spell.bonus
		spell.max = spell.max or spell.min
	end
end

---------------------------------------------------------------------------
-- Known spells the models do not play, with the reason (the "not
-- simulated" list in the Character tab). By rank-1 spell ID.
---------------------------------------------------------------------------
D.NOT_SIMULATED = {
	WARRIOR = {
		{ 5308, L["only below 20 % health"] }, { 1464, L["resets the swing timer; not modeled"] },
		{ 6572, L["needs a block, dodge or parry; the dummy does not hit back"] }, { 772, L["bleeds are not modeled"] },
		{ 1719, L["a long cooldown kept for hard fights"] }, { 12328, L["one target only"] }, { 845, L["one target only"] },
		{ 6343, L["one target only"] }, { 100, L["movement"] },
	},
	ROGUE = {
		{ 1943, L["bleeds are not modeled"] }, { 703, L["bleeds are not modeled"] }, { 14177, L["a cooldown kept for hard fights"] },
		{ 1833, L["the dummy cannot be stunned in a useful way"] }, { 8647, L["armor debuffs from your group are not modeled"] },
	},
	HUNTER = {
		{ 2973, L["melee range only"] }, { 19574, L["pet cooldowns are not modeled"] }, { 13165, L["its proc is not modeled"] },
		{ 1510, L["one target only"] },
	},
	MAGE = {
		{ 11366, L["too slow to cast on a dummy"] }, { 11129, L["a cooldown kept for hard fights"] }, { 12043, L["a cooldown kept for hard fights"] },
		{ 1449, L["one target only"] }, { 120, L["one target only"] },
	},
	WARLOCK = {
		{ 603, L["a one-minute bane; Bane of Agony is used"] }, { 17877, L["needs soul shards"] }, { 17962, L["a cooldown kept for hard fights"] },
		{ 689, L["worse than Shadow Bolt on a dummy"] }, { 1120, L["only on a dying target"] }, { 5676, L["worse than Shadow Bolt on a dummy"] },
	},
	PRIEST = { { 2944, L["a racial spell; not modeled"] }, { 15286, L["healing only"] }, { 14751, L["a cooldown kept for hard fights"] } },
	PALADIN = {
		{ 879, L["undead and demons only"] }, { 24275, L["only below 20 % health"] }, { 20473, L["kept for healing"] },
		{ 21082, L["its attack speed change is not modeled"] },
	},
	SHAMAN = {
		{ 3599, L["totems are not modeled"] }, { 16166, L["a cooldown kept for hard fights"] }, { 8056, L["worse than Earth Shock on a dummy"] },
		{ 324, L["the dummy does not hit back"] },
	},
	DRUID = {
		{ 1079, L["bleeds are not modeled"] }, { 1822, L["bleeds are not modeled"] }, { 5217, L["too costly for its gain"] },
		{ 770, L["armor debuffs are not modeled"] },
	},
}

---------------------------------------------------------------------------
-- Talents the sim plays, by the talent's English name (other client
-- languages list them under "Other talents", not simulated). Talents that only move a number on your character sheet
-- (crit, hit, stats, attack power) are already in what the reader takes.
--   dmg = { target, per rank }, crit = crit damage bonus (share of the
--   normal bonus), critChance, cast, cost, cd (seconds), special = a name
--   Engine.lua knows. Targets: all, physical, white, offhand, twohand,
--   onehand, ranged, pet, yellow, builder, school:<s>, spell:<key>.
---------------------------------------------------------------------------
D.TALENTS = {
	WARRIOR = {
		["Impale"] = { crit = { "yellow", 0.1 } },
		["Two-Handed Weapon Specialization"] = { dmg = { "twohand", 0.01 } },
		["One-Handed Weapon Specialization"] = { dmg = { "onehand", 0.02 } },
		["Dual Wield Specialization"] = { dmg = { "offhand", 0.05 } },
		["Improved Heroic Strike"] = { cost = { "spell:heroicStrike", 1 } },
		["Improved Overpower"] = { critChance = { "spell:overpower", 25 } },
		["Flurry"] = { special = "flurry", values = { 0.1, 0.15, 0.2, 0.25, 0.3 } },
		["Deep Wounds"] = { special = "deepWounds", per = 0.2 },
		["Unbridled Wrath"] = { special = "unbridledWrath", per = 8 },
		["Sword Specialization"] = { special = "swordSpec", per = 1 },
	},
	ROGUE = {
		["Lethality"] = { crit = { "builder", 0.06 } },
		["Dual Wield Specialization"] = { dmg = { "offhand", 0.1 } },
		["Improved Eviscerate"] = { dmg = { "spell:eviscerate", 0.05 } },
		["Aggression"] = { dmg = { "spell:sinisterStrike", 0.02 }, dmg2 = { "spell:eviscerate", 0.02 } },
		["Opportunity"] = { dmg = { "spell:backstab", 0.04 }, dmg2 = { "spell:ambush", 0.04 } },
		["Improved Sinister Strike"] = { cost = { "spell:sinisterStrike", 2.5 } },
		["Improved Backstab"] = { critChance = { "spell:backstab", 10 } },
		["Improved Ambush"] = { critChance = { "spell:ambush", 15 } },
		["Improved Slice and Dice"] = { special = "longerSnD", per = 0.15 },
		["Relentless Strikes"] = { special = "relentless", per = 0.2 },
		["Seal Fate"] = { special = "sealFate", per = 20 },
		["Sword Specialization"] = { special = "swordSpec", per = 1 },
	},
	HUNTER = {
		["Mortal Shots"] = { crit = { "ranged", 0.06 } },
		["Ranged Weapon Specialization"] = { dmg = { "ranged", 0.01 } },
		["Barrage"] = { dmg = { "spell:multiShot", 0.05 }, dmg2 = { "spell:aimedShot", 0.05 } },
		-- WoW: Forever's own (client tables of 1.60.1.70862, per rank).
		["Lone Wolf"] = { special = "loneWolf", per = 0.2 },
		["Focused Fire"] = { special = "focusedFire", per = 0.01 },
		["Rapid Killing"] = { cd = { "spell:rapidFire", 60 } },
		["Careful Aim"] = { special = "carefulAim", per = 0.2 },
		["Improved Serpent Sting"] = { dmg = { "spell:serpentSting", 0.02 } },
		["Improved Arcane Shot"] = { cd = { "spell:arcaneShot", 0.2 } },
		["Unleashed Fury"] = { dmg = { "pet", 0.04 } },
		["Efficiency"] = { special = "efficiency", per = 0.02 },
	},
	MAGE = {
		["Fire Power"] = { dmg = { "school:fire", 0.02 } },
		["Ice Shards"] = { crit = { "school:frost", 0.2 } },
		["Piercing Ice"] = { dmg = { "school:frost", 0.02 } },
		["Arcane Instability"] = { dmg = { "all", 0.01 }, critChance = { "all", 1 } },
		["Improved Fireball"] = { cast = { "spell:fireball", 0.1 } },
		["Improved Frostbolt"] = { cast = { "spell:frostbolt", 0.1 } },
		["Ignite"] = { special = "ignite", per = 0.08 },
		["Arcane Concentration"] = { special = "clearcasting", per = 2 },
	},
	WARLOCK = {
		["Ruin"] = { crit = { "spell:shadowBolt", 1 }, crit2 = { "spell:immolate", 1 } },
		["Bane"] = { cast = { "spell:shadowBolt", 0.1 }, cast2 = { "spell:immolate", 0.1 } },
		["Shadow Mastery"] = { dmg = { "school:shadow", 0.02 } },
		["Improved Corruption"] = { cast = { "spell:corruption", 0.4 } },
		["Improved Shadow Bolt"] = { special = "isb", per = 0.04 },
		["Emberstorm"] = { dmg = { "school:fire", 0.02 } },
		["Improved Bane of Agony"] = { dmg = { "spell:curseOfAgony", 0.02 } },
		["Improved Immolate"] = { dmg = { "spell:immolate", 0.05 } },
		["Improved Life Tap"] = { special = "lifeTap", per = 0.1 },
	},
	PRIEST = {
		["Darkness"] = { dmg = { "school:shadow", 0.02 } },
		["Shadow Weaving"] = { special = "shadowWeaving", per = 20 },
		["Improved Mind Blast"] = { cd = { "spell:mindBlast", 0.5 } },
		["Improved Shadow Word: Pain"] = { special = "longerSWP", per = 3 },
		["Searing Light"] = { dmg = { "spell:smite", 0.05 }, dmg2 = { "spell:holyFire", 0.05 } },
		["Divine Fury"] = { cast = { "spell:smite", 0.1 }, cast2 = { "spell:holyFire", 0.1 } },
		["Force of Will"] = { dmg = { "all", 0.01 }, critChance = { "all", 1 } },
	},
	PALADIN = {
		["Two-Handed Weapon Specialization"] = { dmg = { "twohand", 0.02 } },
		["One-Handed Weapon Specialization"] = { dmg = { "onehand", 0.02 } },
		["Vengeance"] = { special = "vengeance", per = 0.03 },
		["Improved Judgement"] = { cd = { "spell:judgement", 1 } },
		["Improved Seal of Righteousness"] = { dmg = { "spell:sealOfRighteousness", 0.03 } },
	},
	SHAMAN = {
		["Concussion"] = { dmg = { "spell:lightningBolt", 0.01 }, dmg2 = { "spell:chainLightning", 0.01 }, dmg3 = { "spell:earthShock", 0.01 } },
		["Elemental Fury"] = { crit = { "school:nature", 1 }, crit2 = { "school:fire", 1 } },
		["Lightning Mastery"] = { cast = { "spell:lightningBolt", 0.2 }, cast2 = { "spell:chainLightning", 0.2 } },
		["Weapon Mastery"] = { dmg = { "physical", 0.02 } },
		["Flurry"] = { special = "flurry", values = { 0.1, 0.15, 0.2, 0.25, 0.3 } },
		["Elemental Weapons"] = { special = "windfuryAP", per = 0.1333 },
		["Call of Thunder"] = { critChance = { "spell:lightningBolt", 1 }, critChance2 = { "spell:chainLightning", 1 } },
	},
	DRUID = {
		["Natural Weapons"] = { dmg = { "physical", 0.02 } },
		["Improved Shred"] = { cost = { "spell:shred", 6 } },
		["Ferocity"] = { cost = { "spell:maul", 1 }, cost2 = { "spell:swipe", 1 }, cost3 = { "spell:claw", 1 } },
		["Feral Aggression"] = { dmg = { "spell:ferociousBite", 0.03 } },
		["Blood Frenzy"] = { special = "sealFate", per = 50 },
		["Vengeance"] = { crit = { "spell:starfire", 0.2 }, crit2 = { "spell:moonfire", 0.2 }, crit3 = { "spell:wrath", 0.2 } },
		["Moonfury"] = { dmg = { "spell:starfire", 0.02 }, dmg2 = { "spell:moonfire", 0.02 }, dmg3 = { "spell:wrath", 0.02 } },
		["Improved Wrath"] = { cast = { "spell:wrath", 0.1 } },
		["Improved Starfire"] = { cast = { "spell:starfire", 0.1 } },
	},
}

-- Buffs on you that change damage the character sheet does not show (by
-- spell ID): { target, bonus }.
D.AURAS = {
	[15473] = { "school:shadow", 0.15 },  -- Shadowform
	[18791] = { "school:shadow", 0.15 },  -- Touch of Shadow (Demonic Sacrifice)
	[18789] = { "school:fire", 0.15 },    -- Burning Wish (Demonic Sacrifice)
	[20218] = { "school:holy", 0.1 },     -- Sanctity Aura
}

-- Weapon enchants the sim plays: temporary ones by enchant ID (from the
-- game's weapon enchant info), permanent ones by the enchant ID in the
-- item link.
D.ENCHANTS = {
	[283] = { kind = "windfury", ap = 46 }, [284] = { kind = "windfury", ap = 119 }, [525] = { kind = "windfury", ap = 249 },
	[1669] = { kind = "windfury", ap = 333 }, [2636] = { kind = "windfury", ap = 445 },
	[323] = { kind = "poison", min = 19, max = 25 }, [324] = { kind = "poison", min = 30, max = 38 },
	[325] = { kind = "poison", min = 44, max = 56 }, [623] = { kind = "poison", min = 67, max = 85 },
	[624] = { kind = "poison", min = 92, max = 118 }, [625] = { kind = "poison", min = 112, max = 148 },
	[1900] = { kind = "crusader", str = 100, ppm = 1, duration = 15 },
	[803] = { kind = "fiery", min = 40, max = 40, ppm = 6 },
	-- Lifestealing: its proc (spell 20004) drains 30 Shadow damage, client
	-- tables of build 1.60.1.70862. The client carries no proc rate for
	-- enchants; it procs like Fiery Weapon.
	[1898] = { kind = "lifesteal", min = 30, max = 30, ppm = 6 },
}

-- Damage of a spell rank from the top rank at level 60 (the fallback when
-- the description gives no numbers).
function D.Fallback(value, level)
	if not value then return end
	level = math.max(1, math.min(60, level or 60))
	return value * (0.15 + 0.85 * level / 60)
end

-- Weapon kind from the item subclass (C_Item.GetItemInfoInstant).
D.WEAPON_KIND = {
	[0] = "axe", [1] = "axe", [2] = "bow", [3] = "gun", [4] = "mace", [5] = "mace", [6] = "polearm", [7] = "sword",
	[8] = "sword", [10] = "staff", [13] = "fist", [15] = "dagger", [16] = "thrown", [18] = "crossbow", [19] = "wand",
}
D.TWO_HAND = { [1] = true, [5] = true, [6] = true, [8] = true, [10] = true }

-- Weapon skill line of each weapon subclass (C_SkillInfo skillID), and
-- Unarmed for an empty main hand.
D.WEAPON_SKILL = {
	[0] = 44, [1] = 172, [2] = 45, [3] = 46, [4] = 54, [5] = 160, [6] = 229, [7] = 43,
	[8] = 55, [10] = 136, [13] = 473, [15] = 173, [16] = 176, [18] = 226, [19] = 228,
}
D.UNARMED_SKILL = 162
-- The weapon skill a druid uses in Cat, Bear and Dire Bear Form.
D.FERAL_SKILL = 3014
