-- EldoUI stat weights: the data behind the shared scoring engine
-- (Core/ItemScore.lua). All values are EldoUI's own rough numbers, written
-- from general, public knowledge of what each class and spec wants. They are
-- a starting point to tune, not a simulation.
--
-- Two kinds of scale live here:
--   * starter: the class scales the Upgrades module has always offered. They
--     use the plain model: an item's score is the sum of stat x weight, every
--     stat counted per point as the game lists it. Kept exactly as before so
--     upgrade arrows don't change.
--   * specs: one scale per talent spec (31 with Feral as Cat and Bear and the
--     healer trees played for damage). They use the spec model (see
--     Core/ItemScore.lua): ratings are turned into percent by the game's own
--     rating table first, so their weights are per 1 % (Defense per skill
--     point, Expertise per point); everything else is per point.
local _, E = ...

local W = {}
E.StatWeights = W

---------------------------------------------------------------------------
-- Starter class scales (plain model)
---------------------------------------------------------------------------
local function Scale(name, class, weights) return { name = name, class = class, weights = weights } end

W.starter = {
	WARRIOR_DPS = Scale("Warrior: Damage", "WARRIOR", { Strength = 1, Agility = 0.6, AttackPower = 0.5, Crit = 0.9, Hit = 0.9, Haste = 0.6, Expertise = 0.7, Stamina = 0.2, Dps = 3 }),
	WARRIOR_TANK = Scale("Warrior: Tank", "WARRIOR", { Stamina = 1, Armor = 0.08, Defense = 1, Dodge = 0.8, Parry = 0.7, Block = 0.5, BlockValue = 0.3, Strength = 0.5, Agility = 0.5, Hit = 0.4, Expertise = 0.5, Dps = 1 }),
	PALADIN_HOLY = Scale("Paladin: Healing", "PALADIN", { Intellect = 1, Healing = 0.9, SpellPower = 0.9, Mp5 = 1, Crit = 0.6, SpellCrit = 0.6, Haste = 0.5, Spirit = 0.2, Stamina = 0.15 }),
	PALADIN_TANK = Scale("Paladin: Tank", "PALADIN", { Stamina = 1, Armor = 0.08, Defense = 1, Dodge = 0.8, Parry = 0.7, Block = 0.5, BlockValue = 0.4, SpellPower = 0.4, Strength = 0.4, Agility = 0.4, Hit = 0.4, Dps = 0.8 }),
	PALADIN_RET = Scale("Paladin: Retribution", "PALADIN", { Strength = 1, Agility = 0.5, AttackPower = 0.45, Crit = 0.9, Hit = 0.9, Haste = 0.5, Expertise = 0.6, Intellect = 0.15, SpellPower = 0.2, Stamina = 0.2, Dps = 3 }),
	HUNTER = Scale("Hunter", "HUNTER", { Agility = 1, AttackPower = 0.45, RangedAttackPower = 0.45, Crit = 0.9, Hit = 1, Haste = 0.6, Intellect = 0.3, Mp5 = 0.4, Stamina = 0.2, Dps = 2.5 }),
	ROGUE = Scale("Rogue", "ROGUE", { Agility = 1, Strength = 0.5, AttackPower = 0.5, Crit = 0.9, Hit = 1, Haste = 0.7, Expertise = 0.7, Stamina = 0.2, Dps = 3 }),
	PRIEST_HEAL = Scale("Priest: Healing", "PRIEST", { Healing = 1, SpellPower = 1, Intellect = 0.9, Spirit = 0.7, Mp5 = 0.9, Crit = 0.5, SpellCrit = 0.5, Haste = 0.5, Stamina = 0.15 }),
	PRIEST_SHADOW = Scale("Priest: Shadow", "PRIEST", { SpellPower = 1, Hit = 1, SpellHit = 1, Crit = 0.6, SpellCrit = 0.6, Haste = 0.7, Intellect = 0.4, Spirit = 0.4, Stamina = 0.2 }),
	SHAMAN_ELE = Scale("Shaman: Elemental", "SHAMAN", { SpellPower = 1, Hit = 0.9, SpellHit = 0.9, Crit = 0.8, SpellCrit = 0.8, Haste = 0.7, Intellect = 0.5, Mp5 = 0.5, Stamina = 0.2 }),
	SHAMAN_ENH = Scale("Shaman: Enhancement", "SHAMAN", { Strength = 1, Agility = 0.7, AttackPower = 0.5, Crit = 0.9, Hit = 0.9, Haste = 0.7, Expertise = 0.6, Intellect = 0.2, Stamina = 0.2, Dps = 3 }),
	SHAMAN_RESTO = Scale("Shaman: Restoration", "SHAMAN", { Healing = 1, SpellPower = 1, Intellect = 1, Mp5 = 1.1, Crit = 0.6, SpellCrit = 0.6, Haste = 0.5, Spirit = 0.2, Stamina = 0.15 }),
	MAGE = Scale("Mage", "MAGE", { SpellPower = 1, Hit = 1, SpellHit = 1, Crit = 0.8, SpellCrit = 0.8, Haste = 0.7, Intellect = 0.5, Spirit = 0.2, Stamina = 0.2 }),
	WARLOCK = Scale("Warlock", "WARLOCK", { SpellPower = 1, Hit = 1, SpellHit = 1, Crit = 0.6, SpellCrit = 0.6, Haste = 0.7, Stamina = 0.4, Intellect = 0.4, Spirit = 0.2 }),
	DRUID_BALANCE = Scale("Druid: Balance", "DRUID", { SpellPower = 1, Hit = 0.9, SpellHit = 0.9, Crit = 0.7, SpellCrit = 0.7, Haste = 0.7, Intellect = 0.5, Spirit = 0.3, Stamina = 0.2 }),
	DRUID_FERAL = Scale("Druid: Feral (cat)", "DRUID", { Agility = 1, Strength = 0.9, AttackPower = 0.45, Crit = 0.9, Hit = 0.9, Haste = 0.5, Expertise = 0.6, Stamina = 0.2 }),
	DRUID_BEAR = Scale("Druid: Feral (bear)", "DRUID", { Stamina = 1, Armor = 0.12, Agility = 0.8, Defense = 0.8, Dodge = 0.9, Strength = 0.4, Hit = 0.3, Expertise = 0.4 }),
	DRUID_RESTO = Scale("Druid: Restoration", "DRUID", { Healing = 1, SpellPower = 1, Intellect = 0.8, Spirit = 0.7, Mp5 = 1, Crit = 0.4, SpellCrit = 0.4, Haste = 0.6, Stamina = 0.15 }),
	-- For any class without its own starter scale.
	GENERIC_STR = Scale("Strength melee", nil, { Strength = 1, AttackPower = 0.45, Crit = 0.8, Hit = 0.8, Haste = 0.7, Mastery = 0.6, Versatility = 0.6, Stamina = 0.2, Dps = 3 }),
	GENERIC_AGI = Scale("Agility damage", nil, { Agility = 1, AttackPower = 0.45, Crit = 0.8, Hit = 0.8, Haste = 0.7, Mastery = 0.6, Versatility = 0.6, Stamina = 0.2, Dps = 2.5 }),
	GENERIC_CASTER = Scale("Caster damage", nil, { Intellect = 1, SpellPower = 0.9, Crit = 0.7, Hit = 0.8, Haste = 0.8, Mastery = 0.6, Versatility = 0.6, Stamina = 0.2 }),
	GENERIC_HEALER = Scale("Healer", nil, { Intellect = 1, Healing = 0.9, SpellPower = 0.9, Mp5 = 0.9, Spirit = 0.5, Crit = 0.5, Haste = 0.7, Mastery = 0.5, Versatility = 0.5, Stamina = 0.15 }),
	GENERIC_TANK = Scale("Tank", nil, { Stamina = 1, Armor = 0.08, Defense = 0.8, Dodge = 0.7, Parry = 0.6, Block = 0.4, Strength = 0.4, Agility = 0.4, Versatility = 0.6, Mastery = 0.5 }),
}

-- The starter scale a class uses until the player picks another.
W.classDefault = {
	WARRIOR = "WARRIOR_DPS", PALADIN = "PALADIN_RET", HUNTER = "HUNTER", ROGUE = "ROGUE", PRIEST = "PRIEST_HEAL",
	SHAMAN = "SHAMAN_ENH", MAGE = "MAGE", WARLOCK = "WARLOCK", DRUID = "DRUID_BALANCE",
	DEATHKNIGHT = "GENERIC_STR", MONK = "GENERIC_AGI", DEMONHUNTER = "GENERIC_AGI", EVOKER = "GENERIC_CASTER",
}

---------------------------------------------------------------------------
-- Spec scales (spec model). Units: primary stats, attack power, spell power,
-- healing, armor, block value, mana and health per 5 per point; Crit, Hit,
-- Haste, Dodge, Parry, Block per 1 %; Defense per skill point; Expertise per
-- point; Dps per 1 weapon DPS in the main hand (the off hand counts half),
-- RangedDps per 1 DPS of the ranged weapon.
--
-- tab: the talent tree (1-3, the order of the talent window); role: DAMAGER,
-- TANK or HEALER; manual: never picked by detection, only by hand (healer
-- trees played for damage); form: which Feral form.
---------------------------------------------------------------------------
local function Spec(key, class, tab, role, name, note, weights, extra)
	local spec = { key = key, class = class, tab = tab, role = role, name = name, note = note, weights = weights }
	for k, v in pairs(extra or {}) do spec[k] = v end
	return spec
end

W.specs = {
	-- Warrior
	Spec("WARRIOR_ARMS", "WARRIOR", 1, "DAMAGER", "Arms",
		"Two-hander damage: Strength first, hit up to the cap, then crit; a slow weapon with high DPS matters most.",
		{ Strength = 1, Agility = 0.65, AttackPower = 0.5, Hit = 13, Crit = 14, Haste = 8, Expertise = 2, Stamina = 0.05, Dps = 7 }),
	Spec("WARRIOR_FURY", "WARRIOR", 2, "DAMAGER", "Fury",
		"Two weapons: hit is worth most until capped, then Strength and crit; the off hand counts at half.",
		{ Strength = 1, Agility = 0.6, AttackPower = 0.5, Hit = 16, Crit = 15, Haste = 9, Expertise = 2.5, Stamina = 0.05, Dps = 6 }),
	Spec("WARRIOR_PROT", "WARRIOR", 3, "TANK", "Protection",
		"Survive first (Stamina, armor, defense), then dodge, parry and block; Strength and hit keep threat up.",
		{ Stamina = 1, Armor = 0.06, Defense = 1.4, Dodge = 12, Parry = 10, Block = 5, BlockValue = 0.35, Strength = 0.5, Agility = 0.6, Hit = 6, Expertise = 1, Dps = 2 }),
	-- Paladin
	Spec("PALADIN_HOLY", "PALADIN", 1, "HEALER", "Holy",
		"Healing power first, Intellect for mana and spell crit (Illumination), mana per 5 for long fights.",
		{ Healing = 1, SpellPower = 0.1, Intellect = 0.7, SpellCrit = 11, Mp5 = 1.6, Spirit = 0.15, Stamina = 0.1 }),
	Spec("PALADIN_PROT", "PALADIN", 2, "TANK", "Protection",
		"Holy damage makes the threat, so spell power counts; Stamina and defense keep you up, block value with the shield.",
		{ Stamina = 1, Armor = 0.05, Defense = 1.3, Dodge = 11, Parry = 9, Block = 6, BlockValue = 0.4, SpellPower = 0.6, Intellect = 0.3, Strength = 0.3, Agility = 0.4, Hit = 5, SpellHit = 5, Dps = 1.5 }),
	Spec("PALADIN_RET", "PALADIN", 3, "DAMAGER", "Retribution",
		"Two-hander damage with Strength and crit; a little spell power for Seal and Judgement damage.",
		{ Strength = 1, Agility = 0.6, AttackPower = 0.5, Hit = 12, Crit = 13, Haste = 7, SpellPower = 0.25, Intellect = 0.1, Stamina = 0.05, Dps = 7 }),
	Spec("PALADIN_HOLY_DPS", "PALADIN", 1, "DAMAGER", "Holy (damage)",
		"Holy played for damage: spell power and spell crit for Holy Shock and Exorcism, Intellect for mana, some Strength.",
		{ SpellPower = 1, Healing = 0.2, Intellect = 0.6, SpellCrit = 11, SpellHit = 10, Strength = 0.3, Crit = 3, Mp5 = 0.8, Stamina = 0.05, Dps = 1 },
		{ manual = true }),
	-- Hunter
	Spec("HUNTER_BM", "HUNTER", 1, "DAMAGER", "Beast Mastery",
		"Agility above all, then hit up to the cap and crit; the ranged weapon's DPS counts far more than the melee one.",
		{ Agility = 1, AttackPower = 0.45, RangedAttackPower = 0.45, Hit = 14, Crit = 12, Haste = 8, Intellect = 0.15, Mp5 = 0.4, Stamina = 0.05, Dps = 0.3, RangedDps = 6 }),
	Spec("HUNTER_MM", "HUNTER", 2, "DAMAGER", "Marksmanship",
		"Like Beast Mastery with more weight on crit and on the ranged weapon itself.",
		{ Agility = 1, AttackPower = 0.5, RangedAttackPower = 0.5, Hit = 14, Crit = 14, Haste = 8, Intellect = 0.15, Mp5 = 0.4, Stamina = 0.05, Dps = 0.3, RangedDps = 7 }),
	Spec("HUNTER_SV", "HUNTER", 3, "DAMAGER", "Survival",
		"Survival turns Agility into extra attack power, so it is worth even more; then hit and crit.",
		{ Agility = 1, AttackPower = 0.4, RangedAttackPower = 0.4, Hit = 13, Crit = 11, Haste = 7, Intellect = 0.15, Mp5 = 0.4, Stamina = 0.05, Dps = 0.3, RangedDps = 6 }),
	-- Rogue
	Spec("ROGUE_ASSA", "ROGUE", 1, "DAMAGER", "Assassination",
		"Daggers and poisons: Agility, hit up to the cap, crit for Seal Fate; the main-hand dagger's DPS.",
		{ Agility = 1, Strength = 0.5, AttackPower = 0.5, Hit = 15, Crit = 15, Haste = 9, Expertise = 2.5, Stamina = 0.05, Dps = 5 }),
	Spec("ROGUE_COMBAT", "ROGUE", 2, "DAMAGER", "Combat",
		"Steady two-weapon damage: hit is king until capped, then Agility and crit; both weapons count.",
		{ Agility = 1, Strength = 0.5, AttackPower = 0.5, Hit = 17, Crit = 13, Haste = 10, Expertise = 3, Stamina = 0.05, Dps = 6 }),
	Spec("ROGUE_SUB", "ROGUE", 3, "DAMAGER", "Subtlety",
		"Burst from stealth: Agility and crit, with enough hit that openers land.",
		{ Agility = 1, Strength = 0.5, AttackPower = 0.5, Hit = 13, Crit = 14, Haste = 8, Expertise = 2, Stamina = 0.1, Dps = 5 }),
	-- Priest
	Spec("PRIEST_DISC", "PRIEST", 1, "HEALER", "Discipline",
		"Shields and heals: healing power and Intellect for a deep mana pool, Spirit and mana per 5 to keep going.",
		{ Healing = 1, SpellPower = 0.1, Intellect = 0.8, Spirit = 0.5, Mp5 = 1.5, SpellCrit = 7, Stamina = 0.1 }),
	Spec("PRIEST_HOLY", "PRIEST", 2, "HEALER", "Holy",
		"Pure healing: healing power, then Spirit (Holy turns it into healing and mana) and mana per 5.",
		{ Healing = 1, SpellPower = 0.1, Spirit = 0.7, Intellect = 0.6, Mp5 = 1.4, SpellCrit = 6, Stamina = 0.1 }),
	Spec("PRIEST_SHADOW", "PRIEST", 3, "DAMAGER", "Shadow",
		"Shadow damage: spell damage, spell hit up to the cap, then crit; Intellect and Spirit for mana.",
		{ SpellPower = 1, Healing = 0.05, SpellHit = 12, SpellCrit = 8, Intellect = 0.3, Spirit = 0.3, Mp5 = 0.6, Stamina = 0.1 }),
	Spec("PRIEST_DISC_DPS", "PRIEST", 1, "DAMAGER", "Discipline (damage)",
		"Discipline played for damage: Smite and holy spells want spell damage, hit and crit, with Intellect for mana.",
		{ SpellPower = 1, Healing = 0.1, SpellHit = 11, SpellCrit = 10, Intellect = 0.45, Spirit = 0.25, Mp5 = 0.7, Stamina = 0.1 },
		{ manual = true }),
	Spec("PRIEST_HOLY_DPS", "PRIEST", 2, "DAMAGER", "Holy (damage)",
		"Holy played for damage: Smite and Holy Fire, where Holy talents make crit worth more.",
		{ SpellPower = 1, Healing = 0.1, SpellHit = 11, SpellCrit = 11, Intellect = 0.4, Spirit = 0.35, Mp5 = 0.7, Stamina = 0.1 },
		{ manual = true }),
	-- Shaman
	Spec("SHAMAN_ELE", "SHAMAN", 1, "DAMAGER", "Elemental",
		"Caster damage: spell damage, spell hit and crit (Elemental Fury), Intellect and mana per 5 for mana.",
		{ SpellPower = 1, SpellHit = 11, SpellCrit = 11, Intellect = 0.4, Mp5 = 0.8, Spirit = 0.1, Stamina = 0.1 }),
	Spec("SHAMAN_ENH", "SHAMAN", 2, "DAMAGER", "Enhancement",
		"Melee with a slow weapon: Strength and Agility, hit and crit; the weapon's DPS matters a lot.",
		{ Strength = 1, Agility = 0.8, AttackPower = 0.5, Hit = 14, Crit = 13, Haste = 8, Intellect = 0.1, SpellPower = 0.1, Stamina = 0.05, Dps = 7 }),
	Spec("SHAMAN_RESTO", "SHAMAN", 3, "HEALER", "Restoration",
		"Chain Heal and mana: healing power, mana per 5 and Intellect lead.",
		{ Healing = 1, SpellPower = 0.1, Mp5 = 1.7, Intellect = 0.7, SpellCrit = 6, Spirit = 0.1, Stamina = 0.1 }),
	-- Mage
	Spec("MAGE_ARCANE", "MAGE", 1, "DAMAGER", "Arcane",
		"Spell damage and Intellect (Arcane Mind adds mana), then spell hit and crit.",
		{ SpellPower = 1, SpellHit = 12, SpellCrit = 9, Intellect = 0.55, Spirit = 0.35, Mp5 = 0.6, Stamina = 0.1 }),
	Spec("MAGE_FIRE", "MAGE", 2, "DAMAGER", "Fire",
		"Big crits feed Ignite: spell damage, then spell crit and hit.",
		{ SpellPower = 1, SpellCrit = 12, SpellHit = 12, Intellect = 0.35, Spirit = 0.2, Mp5 = 0.5, Stamina = 0.1 }),
	Spec("MAGE_FROST", "MAGE", 3, "DAMAGER", "Frost",
		"Steady Frostbolts: spell damage first, spell hit up to the cap, crit for Shatter.",
		{ SpellPower = 1, SpellHit = 12, SpellCrit = 8, Intellect = 0.3, Spirit = 0.2, Mp5 = 0.5, Stamina = 0.15 }),
	-- Warlock
	Spec("WARLOCK_AFF", "WARLOCK", 1, "DAMAGER", "Affliction",
		"Damage over time: spell damage and hit; crit matters less, Stamina feeds Life Tap.",
		{ SpellPower = 1, SpellHit = 12, SpellCrit = 4, Stamina = 0.25, Intellect = 0.3, Spirit = 0.2, Mp5 = 0.4 }),
	Spec("WARLOCK_DEMO", "WARLOCK", 2, "DAMAGER", "Demonology",
		"Spell damage and hit; Stamina and Intellect also strengthen the demon.",
		{ SpellPower = 1, SpellHit = 11, SpellCrit = 7, Stamina = 0.3, Intellect = 0.35, Spirit = 0.15, Mp5 = 0.4 }),
	Spec("WARLOCK_DESTRO", "WARLOCK", 3, "DAMAGER", "Destruction",
		"Shadow Bolt crits: spell damage, hit up to the cap, then crit.",
		{ SpellPower = 1, SpellHit = 12, SpellCrit = 10, Stamina = 0.2, Intellect = 0.3, Spirit = 0.15, Mp5 = 0.4 }),
	-- Druid
	Spec("DRUID_BALANCE", "DRUID", 1, "DAMAGER", "Balance",
		"Moonkin damage: spell damage, then crit and hit; Intellect for mana.",
		{ SpellPower = 1, SpellHit = 11, SpellCrit = 10, Intellect = 0.45, Spirit = 0.3, Mp5 = 0.7, Stamina = 0.1 }),
	Spec("DRUID_CAT", "DRUID", 2, "DAMAGER", "Feral (cat)",
		"Cat form: Strength and Agility both make attack power, feral attack power counts, the weapon's own DPS does not.",
		{ Agility = 1, Strength = 0.9, AttackPower = 0.45, Hit = 15, Crit = 13, Haste = 6, Expertise = 2, Stamina = 0.05 },
		{ form = "cat" }),
	Spec("DRUID_BEAR", "DRUID", 2, "TANK", "Feral (bear)",
		"Bear form: armor, Stamina and dodge first, Agility gives both; some Strength and hit for threat.",
		{ Stamina = 1, Armor = 0.1, Agility = 0.9, Dodge = 12, Defense = 1.1, Strength = 0.4, AttackPower = 0.2, Hit = 5, Expertise = 1, Crit = 3 },
		{ form = "bear" }),
	Spec("DRUID_RESTO", "DRUID", 3, "HEALER", "Restoration",
		"Healing power, then Spirit and Intellect for mana regeneration, then mana per 5.",
		{ Healing = 1, SpellPower = 0.1, Spirit = 0.6, Intellect = 0.65, Mp5 = 1.4, SpellCrit = 5, Stamina = 0.1 }),
}

-- How much of a stat a typical item carries, in the spec model's units.
-- Weight x typical amount orders a spec's stat priority (the BiS filter's
-- drag strip) and turns a priority order back into weights.
W.typical = {
	Strength = 10, Agility = 10, Stamina = 10, Intellect = 10, Spirit = 10, Armor = 100,
	AttackPower = 20, RangedAttackPower = 20, SpellPower = 12, Healing = 22,
	Crit = 1, SpellCrit = 1, Hit = 1, SpellHit = 1, Haste = 1, Expertise = 4, Mastery = 1, Versatility = 1,
	Mp5 = 4, Hp5 = 4, Defense = 7, Dodge = 1, Parry = 1, Block = 1, BlockValue = 15,
	Dps = 5, RangedDps = 5,
}

-- Rating needed for 1 % (Defense: per skill point, Expertise: per point) at
-- level 60, used only when the game can't convert a rating itself. Indexes
-- are the game's combat-rating ids (CR_* in PaperDollFrame).
W.ratingAt60 = {
	[2] = 1.5,   -- defense skill
	[3] = 12,    -- dodge
	[4] = 15,    -- parry
	[5] = 5,     -- block
	[6] = 10,    -- melee hit
	[7] = 10,    -- ranged hit
	[8] = 8,     -- spell hit
	[9] = 14,    -- melee crit
	[10] = 14,   -- ranged crit
	[11] = 14,   -- spell crit
	[18] = 10,   -- melee haste
	[19] = 10,   -- ranged haste
	[20] = 10,   -- spell haste
	[24] = 2.5,  -- expertise
}
