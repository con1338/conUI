-- EldoUI Shaman Totems data: the shaman's totems per element, the calls
-- that drop a whole set, shields, weapon imbues and the spells the cooldown
-- bar can show, default loadouts per role, the totem buffs group members
-- can wear, and the enemy spells a totem counters.
--
-- Every spell is the rank 1 ID of a WoW: Forever trainer or talent spell,
-- checked against the game's own spell data of client 1.60.1 (build
-- 1.60.1.70938) and the shaman
-- trainer table in Data/Training/Shaman.lua.
-- Higher ranks are found at run time from the spell's name, so nothing
-- here needs a rank list. A spell the character doesn't know never shows,
-- so a spell missing on this client costs nothing.
-- Written from scratch for EldoUI: public game knowledge, no data tables
-- from other addons.
local _, E = ...

local D = {}
E.ShamanData = D

-- Bar order: earth, fire, water, air, the order the game's own calls use.
D.ELEMENTS = { "EARTH", "FIRE", "WATER", "AIR" }

-- The game's totem slot of each element (FIRE_TOTEM_SLOT and friends when
-- the client defines them). Forever fills slots in cast order, so a slot
-- number never says which element is in it: totems are matched by spell.
D.SLOT = {
	FIRE = rawget(_G, "FIRE_TOTEM_SLOT") or 1,
	EARTH = rawget(_G, "EARTH_TOTEM_SLOT") or 2,
	WATER = rawget(_G, "WATER_TOTEM_SLOT") or 3,
	AIR = rawget(_G, "AIR_TOTEM_SLOT") or 4,
}
D.MAX_SLOTS = 4

-- The totem items a shaman carries for each element (bags), shown in the
-- Ready Check Report's shaman column.
D.TOTEM_ITEMS = { EARTH = 5175, FIRE = 5176, WATER = 5177, AIR = 5178 }

-- Element colors: the color-blind safe set, and never the only cue (each
-- element button also carries its totem's icon and the element's name).
local safe = E.tokens.palette.safe
E.tokens.element = E.tokens.element or {
	EARTH = safe.green, FIRE = safe.vermilion, WATER = safe.blue, AIR = safe.sky,
}

-- Totems: id = rank 1 spell; buff = the aura it puts on group members
-- (its name, plus the totem's own name, counts as covered; on WoW: Forever
-- Windfury and Flametongue Totem are party buffs too); role = the
-- roles a default loadout picks it for; counter = the enemy spell kind it
-- answers; resist = the school a resistance totem covers.
D.TOTEMS = {
	EARTH = {
		{ id = 8075, key = "strength", buff = 8076 },          -- Strength of Earth Totem
		{ id = 8071, key = "stoneskin", buff = 8072 },         -- Stoneskin Totem
		{ id = 8143, key = "tremor", counter = "fear" },      -- Tremor Totem
		{ id = 2484, key = "earthbind" },                      -- Earthbind Totem
		{ id = 5730, key = "stoneclaw" },                      -- Stoneclaw Totem
	},
	FIRE = {
		{ id = 3599, key = "searing" },                        -- Searing Totem
		{ id = 8190, key = "magma" },                          -- Magma Totem
		{ id = 8227, key = "flametongue", buff = 8230 },       -- Flametongue Totem
		{ id = 8181, key = "frostres", buff = 8182, resist = "FROST" }, -- Frost Resistance Totem
	},
	WATER = {
		{ id = 5675, key = "manaspring", buff = 5677 },        -- Mana Spring Totem
		{ id = 5394, key = "healingstream", buff = 5672 },     -- Healing Stream Totem
		{ id = 16190, key = "manatide" },                      -- Mana Tide Totem (talent)
		{ id = 8166, key = "poison", counter = "poison" },    -- Poison Cleansing Totem
		{ id = 8170, key = "disease", counter = "disease" },  -- Disease Cleansing Totem
		{ id = 8184, key = "fireres", buff = 8185, resist = "FIRE" }, -- Fire Resistance Totem
	},
	AIR = {
		{ id = 8512, key = "windfury", buff = 8515 },          -- Windfury Totem
		{ id = 8835, key = "graceofair", buff = 8836 },        -- Grace of Air Totem
		{ id = 8177, key = "grounding" },                      -- Grounding Totem
		{ id = 10595, key = "natureres", buff = 10596, resist = "NATURE" }, -- Nature Resistance Totem
		{ id = 15107, key = "windwall", buff = 15108 },        -- Windwall Totem
		{ id = 6495, key = "sentry" },                         -- Sentry Totem
	},
}

-- Lookups: spell ID -> { element, entry }, totem key -> entry.
D.byId, D.byKey = {}, {}
for element, list in pairs(D.TOTEMS) do
	for index, entry in ipairs(list) do
		entry.element = element
		entry.order = index
		D.byId[entry.id] = entry
		D.byKey[entry.key] = entry
	end
end

-- The calls that drop a whole set (they also set the game's totem bar):
-- Call of the Elements, of the Ancestors, of the Spirits. Totemic Recall
-- takes your totems back.
D.CALLS = { 66842, 66843, 66844 }
D.RECALL = 36936

-- Default loadouts per role (totem keys per element). The first known
-- totem of an element fills in when the picked one isn't known yet.
D.DEFAULT_LOADOUTS = {
	healer = { name = "Healing", EARTH = "strength", FIRE = "flametongue", WATER = "manaspring", AIR = "graceofair" },
	damage = { name = "Damage", EARTH = "strength", FIRE = "searing", WATER = "manaspring", AIR = "windfury" },
	tank = { name = "Tanking", EARTH = "stoneskin", FIRE = "searing", WATER = "healingstream", AIR = "graceofair" },
	solo = { name = "Leveling", EARTH = "strength", FIRE = "searing", WATER = "healingstream", AIR = "windfury" },
}

---------------------------------------------------------------------------
-- Cooldown bar items. kind: "shield" (an aura on you, with charges),
-- "imbue" (a weapon enchant per hand), "spell" (a cooldown). roles: the
-- role set that shows it until the player picks their own ("healer",
-- "melee", "caster", or "all" for every set). passive: a spell the game
-- uses on its own (no click); item: the reagent it uses, whose count
-- shows on the icon; auras: more spell IDs the shield's aura can carry.
---------------------------------------------------------------------------
D.SHIELDS = {
	{ id = 324, key = "lightning" },                      -- Lightning Shield
	{ id = 408510, key = "water", auras = { 408511 } },   -- Water Shield (Restoration talent)
}
D.IMBUES = {
	{ id = 8017, key = "rockbiter" },    -- Rockbiter Weapon
	{ id = 8024, key = "flametongue" },  -- Flametongue Weapon
	{ id = 8033, key = "frostbrand" },   -- Frostbrand Weapon
	{ id = 8232, key = "windfury" },     -- Windfury Weapon
}
D.SPELLS = {
	{ id = 36936, key = "recall", roles = "all" },           -- Totemic Recall
	{ id = 20608, key = "reincarnation", roles = "all", passive = true, item = 17030 }, -- Reincarnation (uses an Ankh)
	{ id = 16188, key = "swiftness", roles = "healer" },     -- Nature's Swiftness
	{ id = 16190, key = "manatide", roles = "healer" },      -- Mana Tide Totem
	{ id = 16166, key = "mastery", roles = "caster" },       -- Lightning Mastery (talent)
	{ id = 425336, key = "rage", roles = "melee" },          -- Rage of the Farseer (talent)
}
-- Ready icons: key spells lit while they are off cooldown (off by default).
D.READY = {
	{ id = 8042, key = "earthshock", roles = "all" },      -- Earth Shock
	{ id = 17364, key = "stormstrike", roles = "melee" },   -- Stormstrike (talent)
	{ id = 408521, key = "riptide", roles = "healer" },     -- Riptide (talent)
	{ id = 408341, key = "firenova", roles = "all" },       -- Fire Nova (goes off at your Fire totem)
}

-- The role sets of the cooldown bar, in menu order.
D.ROLE_SETS = { "healer", "melee", "caster" }
-- Talent spells that tell which way a character went, for the automatic
-- set when the Role page doesn't say: the first one known decides.
D.ROLE_TALENTS = {
	{ id = 17364, role = "melee" },   -- Stormstrike
	{ id = 425336, role = "melee" },  -- Rage of the Farseer
	{ id = 16166, role = "caster" },  -- Lightning Mastery
	{ id = 16190, role = "healer" },  -- Mana Tide Totem
	{ id = 408521, role = "healer" }, -- Riptide
}

---------------------------------------------------------------------------
-- Counter hints: enemy spells (as the Mob Abilities log saw them cast)
-- that a totem answers. fear: Tremor Totem; poison: Poison Cleansing
-- Totem; disease: Disease Cleansing Totem. Rank 1 and the common NPC
-- versions; a missing ID only means no hint for that mob.
---------------------------------------------------------------------------
D.COUNTER_TOTEM = { fear = "tremor", poison = "poison", disease = "disease" }
D.COUNTERS = {
	fear = {
		5782, 6213, 6215,            -- Fear
		8122, 8124, 10888, 10890,    -- Psychic Scream
		5246,                        -- Intimidating Shout
		5484, 17928,                 -- Howl of Terror
		7399,                        -- Terrify
		12096,                       -- Fear (creature)
		18431,                       -- Bellowing Roar
		19408,                       -- Panic
	},
	poison = {
		744,                         -- Poison
		3583,                        -- Deadly Poison
		6917,                        -- Venom Spit
		21067,                       -- Poison Bolt
	},
	disease = {
		3427,                        -- Infected Wound
		3436,                        -- Wandering Plague
	},
}
D.counterOf = {}
for kind, ids in pairs(D.COUNTERS) do
	for _, id in ipairs(ids) do D.counterOf[id] = kind end
end
