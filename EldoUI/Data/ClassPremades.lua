-- EldoUI class premades: a full setup per class in one click (setup or
-- the class page), read by Core/Premades.lua. The Role step's "Class
-- details" (E.roleClassLayers) is a view of the same table, so a class has
-- one place for what EldoUI suggests.
--
-- Shape of a premade:
--   version     raise when the premade changes (the record keeps it)
--   text        one line for the Role step and the setup page
--   modules     modules it turns on
--   styles      module -> style key, applied when it turns the module on
--   settings    module -> nested settings (the class layer; every key must
--               be one the module's defaults name)
--   roles       role key ("healer", "damage", "tank", "none") -> { loadout,
--               settings }: the totem loadout and extra settings per role
--   bars        key spells for the action bars: { spells (first known
--               wins, so list the highest rank first), category (its
--               keybind category, Data/KeybindCategories.lua: the button
--               of bars 1 to 3 that category's key presses, the same on
--               every class), stance (optional: the page of bar 1 it goes
--               on, see stances; on bars 2 and 3, which never page, it
--               only waits for that stance), roles }. Only empty buttons
--               are filled; a button holding your own action is kept
--               unless you opt in
--   stances     page -> spell ID (or a list, first known wins): the
--               stance, form or stealth that shows that page of bar 1 (the
--               game's bonus bars 1 to 4). A bar entry with a stance is
--               planned once that spell is known
--   counters    entries added to the Counters list: { kind ("item" or
--               "currency"), id, name (shown until the game has the
--               item's own name), goal (optional), minLevel, maxLevel,
--               roles }. One you already have is kept; a revert takes out
--               only what is still there
--   restock     items added to the Merchant restock list: { id, name,
--               amount, minLevel, maxLevel, roles }. An item already on
--               your list keeps your amount; a revert takes out only what
--               it added, while it is still there
--   macros      character macros: { name (16 letters at most), casts (lists
--               of spell IDs, first known wins, one /cast line each), self
--               (cast on yourself), uses (lists of item IDs, the first one
--               in your bags, one /use line each), pet (pet commands:
--               "attack", "follow", "stay", "passive", "defensive",
--               "aggressive"), click (a button's name for /click), needs
--               (spell IDs: only once you know one), minLevel, maxLevel,
--               roles }. Existing macro names are never touched
--   roles       on an entry: "all" (or left out), one role key, or a list
--               of role keys
-- Written from scratch for EldoUI.
-- The spell IDs here are checked against the WoW: Forever client tables of
-- build 1.60.1.70938.
local _, E = ...
local L = E.L

local Key = E.Key
E.classPremades = E.classPremades or {}

E.classPremades.SHAMAN = {
	version = 5,
	-- One line on the Role step; the full list is its tooltip.
	text = Key("Totem bar for your role, reminders and an Ankh counter"),
	detail = Key("The totem bar with a loadout for your role, the cooldown bar, shield and imbue reminders, totem squares on party frames for healers, and an Ankh counter and restock"),
	modules = { "ShamanTotems", "Reminders", "Counters" },
	styles = { ShamanTotems = "Standard" },
	settings = {
		ClassPower = { blizzard = { totemAttach = "TOTEMBAR" } },
		ShamanTotems = { hideBlizzard = true, cooldowns = { enabled = true, shield = true, imbueMain = true, imbueOff = true } },
		Reminders = { buffs = true, classBuffs = { SHAMAN_SHIELD = true, SHAMAN_IMBUE = true, SHAMAN_IMBUE_OFF = true } },
	},
	roles = {
		healer = { loadout = "healer", settings = { ShamanTotems = { squares = true, coverageTip = true } } },
		damage = { loadout = "damage" },
		tank = { loadout = "tank" },
		none = { loadout = "solo" },
	},
	bars = {
		{ category = "defensive", spells = { 408510, 324 }, roles = "all" }, -- Water Shield (talent), else Lightning Shield
		{ category = "utility1", spells = { 8232, 8024, 8017 }, roles = "all" }, -- Windfury, Flametongue or Rockbiter Weapon
		{ category = "roleUtility", spells = { 36936 }, roles = "all" },            -- Totemic Recall
		{ category = "cooldown", spells = { 16188 }, roles = "healer" },          -- Nature's Swiftness
		{ category = "cooldown", spells = { 16166, 425336 }, roles = "damage" }, -- Lightning Mastery, Rage of the Farseer
	},
	counters = {
		{ kind = "item", id = 17030, name = Key("Ankh"), minLevel = 30, roles = "all" }, -- for Reincarnation
	},
	restock = {
		{ id = 17030, name = Key("Ankh"), amount = 5, minLevel = 30, roles = "all" },
	},
	macros = {
		{ name = "EUI Totems", click = "EldoUI_TotemDropAll", maxLevel = 29, roles = "all" },
		{ name = "EUI Shield", casts = { { 408510, 324 } }, self = true, roles = "all" }, -- Water Shield, else Lightning Shield
		{ name = "EUI Swift Heal", casts = { { 16188 }, { 331 } }, roles = "healer" }, -- Nature's Swiftness, then Healing Wave
	},
}

E.classPremades.HUNTER = {
	version = 5,
	-- One line on the Role step; the full list is its tooltip.
	text = Key("Pet frames, Feed Pet warnings, aspects and key spells"),
	detail = Key("Pet and pet target frames, the Feed Pet button with happiness and food warnings, aspect and pet reminders, your aspect, Mend Pet, Hunter's Mark and Feign Death on empty action slots, and a pet attack macro. The class bar shows your buffs, key cooldowns and reagents"),
	modules = { "PetCare", "Reminders", "ClassBar" },
	styles = { ClassBar = "Standard" },
	settings = {
		UnitFrames = { units = { pet = { enabled = true }, pettarget = { enabled = true } } },
		PetCare = { feedButton = true, warnUnhappy = true, warnLowFood = true },
		Reminders = { buffs = true, pets = true, petPassive = true, classBuffs = { HUNTER_ASPECT = true, HUNTER_TRUESHOT = true } },
	},
	bars = {
		{ category = "buff", spells = { 25296, 14322, 14321, 14320, 14319, 14318, 13165 }, roles = "all" }, -- Aspect of the Hawk
		{ category = "support", spells = { 13544, 13543, 13542, 3662, 3661, 3111, 136 }, roles = "all" },        -- Mend Pet
		{ category = "interrupt", spells = { 14325, 14324, 14323, 1130 }, roles = "all" },                           -- Hunter's Mark
		{ category = "defensive", spells = { 5384 }, roles = "all" },                                               -- Feign Death
	},
	macros = {
		{ name = "EUI Feed Pet", click = "EldoUI_PetFeedButton", roles = "all" }, -- the Pet Care button, for a key binding
		{ name = "EUI Pet Attack", pet = { "attack" }, needs = { 883 }, roles = "all" },  -- once you know Call Pet
	},
}

-- Healthstones from the biggest down, the talented versions first.
local HEALTHSTONES = { 19013, 19012, 9421, 19011, 19010, 5510, 19009, 19008, 5509, 19007, 19006, 5511, 19005, 19004, 5512 }

E.classPremades.WARLOCK = {
	version = 5,
	-- One line on the Role step; the full list is its tooltip.
	text = Key("Pet frames, the Soul Shard count, reminders and key spells"),
	detail = Key("Pet and pet target frames, armor, demon and Healthstone reminders, the Soul Shard count next to your mana and a Soul Shard counter, your armor, Life Tap, Create Healthstone and Health Funnel on empty action slots, and Healthstone and pet attack macros. The class bar shows your buffs, key cooldowns and reagents"),
	modules = { "Reminders", "Counters", "ClassBar" },
	styles = { ClassBar = "Standard" },
	settings = {
		UnitFrames = { units = { pet = { enabled = true }, pettarget = { enabled = true } } },
		Reminders = { buffs = true, pets = true, petPassive = true, healthstone = true, classBuffs = { WARLOCK_ARMOR = true } },
		ClassPower = { soulShards = { enabled = true } },
	},
	counters = {
		{ kind = "item", id = 6265, name = Key("Soul Shard"), roles = "all" },
	},
	macros = {
		{ name = "EUI Healthstone", uses = { HEALTHSTONES }, roles = "all" },   -- the biggest one in your bags
		{ name = "EUI Pet Attack", pet = { "attack" }, needs = { 688 }, roles = "all" }, -- once you know Summon Imp
	},
	bars = {
		{ category = "buff", spells = { 11735, 11734, 11733, 1086, 706, 696, 687 }, roles = "all" }, -- Demon Armor, else Demon Skin
		{ category = "sustain", spells = { 11689, 11688, 11687, 1456, 1455, 1454 }, roles = "all" },    -- Life Tap
		{ category = "roleUtility", spells = { 11730, 11729, 5699, 6202, 6201 }, roles = "all" },           -- Create Healthstone
		{ category = "support", spells = { 11695, 11694, 11693, 3700, 3699, 3698, 755 }, roles = "all" }, -- Health Funnel
	},
}

E.classPremades.ROGUE = {
	version = 4,
	-- One line on the Role step; the full list is its tooltip.
	text = Key("Combo points, energy ticks, poison reminders and openers"),
	detail = Key("Combo points on your target's nameplate, red when full, energy ticks on the power bar, a poison reminder for each weapon, Flash Powder and Blinding Powder counters with a Flash Powder restock, your escapes and Kick on empty action slots, and your openers on the stealth page. The class bar shows your buffs, key cooldowns and reagents"),
	modules = { "ClassPower", "Counters", "Reminders", "ClassBar" },
	styles = { ClassBar = "Standard" },
	settings = {
		ClassPower = { combo = { onPlate = true, fullColorEnabled = true }, power = { ticks = { enabled = true } } },
		Reminders = { buffs = true, classBuffs = { ROGUE_POISON = true, ROGUE_POISON_OFF = true } },
	},
	stances = { [1] = 1784 }, -- Stealth
	counters = {
		{ kind = "item", id = 5140, name = Key("Flash Powder"), minLevel = 22, roles = "all" },   -- for Vanish
		{ kind = "item", id = 5530, name = Key("Blinding Powder"), minLevel = 34, roles = "all" }, -- for Blind
	},
	restock = {
		{ id = 5140, name = Key("Flash Powder"), amount = 20, minLevel = 22, roles = "all" },
	},
	bars = {
		{ category = "movement", spells = { 11305, 8696, 2983 }, roles = "all" },                           -- Sprint
		{ category = "defensive", spells = { 5277 }, roles = "all" },                                        -- Evasion
		{ category = "emergency", spells = { 1857, 1856 }, roles = "all" },                                  -- Vanish
		{ category = "interrupt", spells = { 1769, 1768, 1767, 1766 }, roles = "all" },                       -- Kick
		{ stance = 1, category = "control", spells = { 11297, 2070, 6770 }, roles = "all" },               -- Sap
		{ stance = 1, category = "core3", spells = { 1833 }, roles = "all" },                            -- Cheap Shot
		{ stance = 1, category = "core2", spells = { 11290, 11289, 8633, 8632, 8631, 703 }, roles = "all" }, -- Garrote
		{ stance = 1, category = "core1", spells = { 11269, 11268, 11267, 8725, 8724, 8676 }, roles = "all" }, -- Ambush
	},
}

-- Warriors are always in a stance, so bar 1 shows a stance page: the key
-- spells go on the page of the stance they are used in.
local SHOUT = { 25289, 11551, 11550, 11549, 6192, 5242, 6673 } -- Battle Shout
local EXECUTE = { 20662, 20661, 20660, 20658, 5308 }    -- Execute

E.classPremades.WARRIOR = {
	version = 5,
	-- One line on the Role step; the full list is its tooltip.
	text = Key("Rage ticks, the Battle Shout reminder and spells per stance"),
	detail = Key("Rage ticks on the power bar, the Battle Shout reminder, and your key spells on the bar of each stance (Defensive Stance spells and Taunt for tanks). The class bar shows your buffs, key cooldowns and reagents"),
	modules = { "ClassPower", "Reminders", "ClassBar" },
	styles = { ClassBar = "Standard" },
	settings = {
		ClassPower = { power = { ticks = { enabled = true } } },
		Reminders = { buffs = true, classBuffs = { WARRIOR_SHOUT = true } },
	},
	stances = { [1] = 2457, [2] = 71, [3] = 2458 }, -- Battle, Defensive and Berserker Stance
	bars = {
		{ category = "movement2", spells = SHOUT, roles = "all" },
		{ stance = 1, category = "movement", spells = { 11578, 6178, 100 }, roles = "all" },               -- Charge
		{ stance = 1, category = "core2", spells = { 11585, 11584, 7887, 7384 }, roles = "all" },       -- Overpower
		{ stance = 1, category = "core3", spells = EXECUTE, roles = "all" },
		{ stance = 2, category = "defensive", spells = { 2565 }, roles = "tank" },                          -- Shield Block
		{ stance = 2, category = "core3", spells = { 11597, 11596, 8380, 7405, 7386 }, roles = "tank" }, -- Sunder Armor
		{ stance = 2, category = "core2", spells = { 25288, 11601, 11600, 7379, 6574, 6572 }, roles = "tank" }, -- Revenge
		{ stance = 2, category = "movement", spells = { 355 }, roles = "tank" },                                -- Taunt
		{ stance = 3, category = "movement", spells = { 20617, 20616, 20252 }, roles = "all" },            -- Intercept
		{ stance = 3, category = "defensive", spells = { 18499 }, roles = "all" },                          -- Berserker Rage
		{ stance = 3, category = "core3", spells = EXECUTE, roles = "all" },
	},
}

E.classPremades.MAGE = {
	version = 5,
	-- One line on the Role step; the full list is its tooltip.
	text = Key("Buff reminders, conjured food first and the travel button"),
	detail = Key("Arcane Intellect and armor reminders you click to cast, the consumable bar with conjured food and water first and your mana gem, the travel button for your teleports and portals, rune and powder counters with a restock, conjuring, Evocation and Blink on empty action slots, and a mana gem macro. The class bar shows your buffs, key cooldowns and reagents"),
	modules = { "Reminders", "ConsumableBar", "Counters", "MageTravel", "ClassBar" },
	styles = { ClassBar = "Standard" },
	settings = {
		Reminders = { buffs = true, clickCast = true, classBuffs = { MAGE_INT = true, MAGE_ARMOR = true } },
		ConsumableBar = { food = true, drink = true, manaGem = true, conjuredFirst = true },
	},
	counters = {
		{ kind = "item", id = 17031, name = Key("Rune of Teleportation"), minLevel = 20, roles = "all" },
		{ kind = "item", id = 17032, name = Key("Rune of Portals"), minLevel = 40, roles = "all" },
		{ kind = "item", id = 17020, name = Key("Arcane Powder"), minLevel = 56, roles = "all" }, -- for Arcane Brilliance
	},
	restock = {
		{ id = 17031, name = Key("Rune of Teleportation"), amount = 10, minLevel = 20, roles = "all" },
		{ id = 17032, name = Key("Rune of Portals"), amount = 10, minLevel = 40, roles = "all" },
		{ id = 17020, name = Key("Arcane Powder"), amount = 20, minLevel = 56, roles = "all" },
	},
	-- Ranks from the highest down: the first one you know goes on the bar.
	bars = {
		{ category = "utility5", spells = { 10140, 10139, 10138, 6127, 5506, 5505, 5504 }, roles = "all" }, -- Conjure Water
		{ category = "resurrect", spells = { 28612, 10145, 10144, 6129, 990, 597, 587 }, roles = "all" }, -- Conjure Food
		{ category = "sustain", spells = { 12051 }, roles = "all" },                                 -- Evocation
		{ category = "movement", spells = { 1953 }, roles = "all" },                                   -- Blink
	},
	macros = {
		{ name = "EUI Intellect", casts = { { 10157, 10156, 1461, 1460, 1459 } }, self = true, roles = "all" }, -- Arcane Intellect on yourself
		{ name = "EUI Mana Gem", uses = { { 8008, 8007, 5513, 5514 } }, minLevel = 28, roles = "all" }, -- Ruby, Citrine, Jade, Agate
	},
}

E.classPremades.PRIEST = {
	version = 4,
	-- One line on the Role step; the full list is its tooltip.
	text = Key("Buff reminders, the five-second rule and spells for your role"),
	detail = Key("Fortitude, Inner Fire and Divine Spirit reminders you click to cast, the five-second rule on your mana bar, a candle counter and restock, and Power Word: Shield, Fade and spells for your role on empty action slots. The class bar shows your buffs, key cooldowns and reagents"),
	modules = { "Reminders", "Counters", "ClassBar" },
	styles = { ClassBar = "Standard" },
	settings = {
		Reminders = { buffs = true, clickCast = true, classBuffs = { PRIEST_FORT = true, PRIEST_INNER = true, PRIEST_SPIRIT = true } },
		ClassPower = { power = { fiveSecond = true } },
	},
	-- Candles for the group buffs: Holy Candles, then Sacred Candles at 60.
	counters = {
		{ kind = "item", id = 17028, name = Key("Holy Candle"), minLevel = 48, maxLevel = 59, roles = "all" },
		{ kind = "item", id = 17029, name = Key("Sacred Candle"), minLevel = 60, roles = "all" },
	},
	restock = {
		{ id = 17028, name = Key("Holy Candle"), amount = 20, minLevel = 48, maxLevel = 59, roles = "all" },
		{ id = 17029, name = Key("Sacred Candle"), amount = 20, minLevel = 60, roles = "all" },
	},
	bars = {
		{ category = "defensive", spells = { 10901, 10900, 10899, 10898, 6066, 6065, 3747, 600, 592, 17 }, roles = "all" }, -- Power Word: Shield
		{ category = "emergency", spells = { 10942, 10941, 9592, 9579, 9578, 586 }, roles = "all" },                     -- Fade
		{ category = "control", spells = { 10890, 10888, 8124, 8122 }, roles = "all" },                                 -- Psychic Scream
		{ category = "core2", spells = { 25315, 10929, 10928, 10927, 6078, 6077, 6076, 6075, 6074, 139 }, roles = "healer" }, -- Renew
		{ category = "core2", spells = { 10894, 10893, 10892, 2767, 992, 970, 594, 589 }, roles = "damage" },          -- Shadow Word: Pain
	},
	macros = {
		{ name = "EUI Shield", casts = { { 10901, 10900, 10899, 10898, 6066, 6065, 3747, 600, 592, 17 } }, self = true, roles = "all" }, -- Power Word: Shield on yourself
	},
}

E.classPremades.DRUID = {
	version = 5,
	-- One line on the Role step; the full list is its tooltip.
	text = Key("Buff reminders, combo points and spells on the form bars"),
	detail = Key("Mark of the Wild, Thorns and Omen of Clarity reminders you click to cast, combo points on your target's nameplate, red when full, seed and berry counters with a restock, Innervate, Rebirth and spells for your role on empty action slots, and bear and cat spells on the form bars. The class bar shows your buffs, key cooldowns and reagents"),
	modules = { "Reminders", "Counters", "ClassBar" },
	styles = { ClassBar = "Standard" },
	settings = {
		Reminders = { buffs = true, clickCast = true, classBuffs = { DRUID_MOTW = true, DRUID_THORNS = true, DRUID_OMEN = true } },
		-- Form mana stays inside the power bar, in the band every layout keeps.
		ClassPower = { combo = { onPlate = true, fullColorEnabled = true }, druidMana = { attach = "INSET" } },
	},
	-- Cat Form shows page 1 of bar 1, Bear Form page 3.
	stances = { [1] = 768, [3] = { 9634, 5487 } }, -- Cat Form; Dire Bear Form, else Bear Form
	-- The seed for your Rebirth rank, and the reagent of Gift of the Wild.
	counters = {
		{ kind = "item", id = 17034, name = Key("Maple Seed"), minLevel = 20, maxLevel = 29, roles = "all" },
		{ kind = "item", id = 17035, name = Key("Stranglethorn Seed"), minLevel = 30, maxLevel = 39, roles = "all" },
		{ kind = "item", id = 17036, name = Key("Ashwood Seed"), minLevel = 40, maxLevel = 49, roles = "all" },
		{ kind = "item", id = 17037, name = Key("Hornbeam Seed"), minLevel = 50, maxLevel = 59, roles = "all" },
		{ kind = "item", id = 17038, name = Key("Ironwood Seed"), minLevel = 60, roles = "all" },
		{ kind = "item", id = 17021, name = Key("Wild Berries"), minLevel = 50, maxLevel = 59, roles = "all" },
		{ kind = "item", id = 17026, name = Key("Wild Thornroot"), minLevel = 60, roles = "all" },
	},
	restock = {
		{ id = 17034, name = Key("Maple Seed"), amount = 5, minLevel = 20, maxLevel = 29, roles = "all" },
		{ id = 17035, name = Key("Stranglethorn Seed"), amount = 5, minLevel = 30, maxLevel = 39, roles = "all" },
		{ id = 17036, name = Key("Ashwood Seed"), amount = 5, minLevel = 40, maxLevel = 49, roles = "all" },
		{ id = 17037, name = Key("Hornbeam Seed"), amount = 5, minLevel = 50, maxLevel = 59, roles = "all" },
		{ id = 17038, name = Key("Ironwood Seed"), amount = 5, minLevel = 60, roles = "all" },
		{ id = 17021, name = Key("Wild Berries"), amount = 20, minLevel = 50, maxLevel = 59, roles = "all" },
		{ id = 17026, name = Key("Wild Thornroot"), amount = 20, minLevel = 60, roles = "all" },
	},
	-- Caster form slots, then the cat page (damage and solo) and the bear
	-- page (tanks and solo).
	bars = {
		{ stance = 1, category = "core1", spells = { 9850, 9849, 5201, 3029, 16942 }, roles = { "damage", "none" } },       -- Claw
		{ stance = 1, category = "core2", spells = { 9896, 9894, 9752, 9493, 9492, 1079 }, roles = { "damage", "none" } },  -- Rip
		{ stance = 1, category = "interrupt", spells = { 9913, 6783, 5215 }, roles = { "damage", "none" } },                   -- Prowl
		{ stance = 1, category = "movement", spells = { 9821, 1850 }, roles = { "damage", "none" } },                           -- Dash
		{ stance = 3, category = "interrupt", spells = { 6795 }, roles = { "tank", "none" } },                                    -- Growl
		{ stance = 3, category = "core1", spells = { 9881, 9880, 9745, 8972, 6809, 6808, 6807 }, roles = { "tank", "none" } }, -- Maul
		{ stance = 3, category = "core3", spells = { 9898, 9747, 9490, 1735, 99 }, roles = { "tank", "none" } },            -- Demoralizing Roar
		{ stance = 3, category = "control", spells = { 8983, 6798, 5211 }, roles = { "tank", "none" } },                       -- Bash
		{ category = "cooldown", spells = { 29166 }, roles = "all" },                                                       -- Innervate
		{ category = "resurrect", spells = { 20748, 20747, 20742, 20739, 20484 }, roles = "all" },                          -- Rebirth
		{ category = "core2", spells = { 25299, 9841, 9840, 9839, 8910, 3627, 2091, 2090, 1430, 1058, 774 }, roles = "healer" }, -- Rejuvenation
		{ category = "groupDefensive", spells = { 9863, 9862, 8918, 740 }, roles = "healer" },                                     -- Tranquility
		{ category = "core5", spells = { 9907, 9749, 778, 770 }, roles = "damage" },                                     -- Faerie Fire
		{ category = "second1", spells = { 17402, 17401, 16914 }, roles = "damage" },                                       -- Hurricane
		{ category = "core5", spells = { 9907, 9749, 778, 770 }, roles = "tank" },                                       -- Faerie Fire
	},
	macros = {
		{ name = "EUI Innervate", casts = { { 29166 } }, self = true, roles = "all" }, -- Innervate on yourself
	},
}

E.classPremades.PALADIN = {
	version = 5,
	-- One line on the Role step; the full list is its tooltip.
	text = Key("Blessing and aura reminders and spells for your role"),
	detail = Key("Blessing and aura reminders you click to cast, Righteous Fury for tanks, symbol counters with a restock, and Judgement, your defensive spells and a spell for your role on empty action slots. The class bar shows your buffs, key cooldowns and reagents"),
	modules = { "Reminders", "Counters", "ClassBar" },
	styles = { ClassBar = "Standard" },
	settings = {
		Reminders = { buffs = true, clickCast = true, classBuffs = { PALADIN_BLESSING = true, PALADIN_AURA = true, PALADIN_RF = true } },
	},
	counters = {
		{ kind = "item", id = 17033, name = Key("Symbol of Divinity"), minLevel = 30, roles = "all" }, -- for Divine Intervention
		{ kind = "item", id = 21177, name = Key("Symbol of Kings"), minLevel = 52, roles = "all" },    -- for the greater blessings
	},
	restock = {
		{ id = 17033, name = Key("Symbol of Divinity"), amount = 5, minLevel = 30, roles = "all" },
		{ id = 21177, name = Key("Symbol of Kings"), amount = 40, minLevel = 52, roles = "all" },
	},
	bars = {
		{ category = "core1", spells = { 20271 }, roles = "all" },                                       -- Judgement
		{ category = "emergency", spells = { 1020, 642 }, roles = "all" },                                 -- Divine Shield
		{ category = "sustain", spells = { 10310, 2800, 633 }, roles = "all" },                           -- Lay on Hands
		{ category = "interrupt", spells = { 4987, 1152 }, roles = "healer" },                             -- Cleanse, else Purify
		{ category = "roleUtility", spells = { 25780 }, roles = "tank" },                                      -- Righteous Fury
		{ category = "core2", spells = { 20308, 20307, 20306, 20305, 20162, 21082 }, roles = "damage" }, -- Seal of the Crusader
	},
	macros = {
		{ name = "EUI Freedom", casts = { { 1044 } }, self = true, roles = "all" }, -- Blessing of Freedom on yourself
	},
}

-- The class layer of the Role step: the premade's one-line text, its full
-- list (the tooltip), settings and the modules it turns on.
for class, premade in pairs(E.classPremades) do
	E.roleClassLayers = E.roleClassLayers or {}
	E.roleClassLayers[class] = { text = premade.text, detail = premade.detail, settings = premade.settings, modules = premade.modules, premade = true }
end
