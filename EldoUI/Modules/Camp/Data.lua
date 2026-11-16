-- EldoUI Camp Helper: game facts for WoW: Forever camping (client 1.60.1).
-- Spell, aura and object ids are game data (Wowhead Forever and the client's
-- DB2 tables), not anyone's code; the cooldowns were checked against the
-- client tables of build 1.60.1.70938. Effects are level 60 base values; the aura
-- itself is the truth when it can be read.
local _, E = ...

local L = E.L
local Key = E.Key
local D = {}
E.CampData = D

-- Auras every camp gives
D.BENEFITS = 1229741   -- Camp Benefits (1 h, after sitting by the fire)
D.WELCOMING = 1289723  -- Welcoming Campfire (1 min countdown to Camp Benefits)
D.NEARBY = 1283391     -- Campfire Nearby (passive, 100 yd)
D.BOOSTED = 1229451    -- Boosted Rest (tent lockout, 1 h)

-- Fires: kit spell and game object entry give the tier and its slots.
D.FIRES = {
	{ tier = 1, name = "Basic", slots = 3, kit = 1307227, entry = 529161 },
	{ tier = 2, name = "Journeyman", slots = 5, kit = 1307252, entry = 630660 },
	{ tier = 3, name = "Expert", slots = 10, kit = 1307237, entry = 650137 },
}
D.fireByEntry, D.fireByKit = {}, {}
for _, fire in ipairs(D.FIRES) do
	D.fireByEntry[fire.entry] = fire
	D.fireByKit[fire.kit] = fire
end

-- Features: the objects (tier 1, 2, 3) that give one buff, the buff's aura,
-- its effect and the class buffs it cannot stack with (spell ids, any rank;
-- the name is read from the game so it is in the player's language).
-- An object is a name (its tier is its place in the list) or a record
-- `{ name = ..., tier = n, entry = n }`: `tier` when several objects share a
-- tier, `entry` (its game object entry) once it is known. `spells`
-- are the placing spells; `spellTiers` gives each spell's tier when it is
-- not the spell's place in the list. Each entry is the object the placing
-- spell summons in the client's spell effect data (build 1.60.1.70938, the
-- spell's first summon-object effect), the same way the three fires above
-- match the game.
D.FEATURES = {
	{ key = "mana", aura = 1230587, effect = Key("29 mana every 5 sec"),
		objects = {
			{ name = "Mana Well", entry = 651948 },
			{ name = "Fermenter", entry = 612120 },
			{ name = "Alchemy Laboratory", entry = 612139 },
		}, spells = { 1307259, 1307242, 1307172 },
		clash = { { 19742, "Blessing of Wisdom" }, { 25894, "Greater Blessing of Wisdom" } } },
	{ key = "strength", aura = 1230172, effect = Key("+34 Strength"),
		objects = {
			{ name = "Sharpening Wheel", entry = 651950 },
			{ name = "Anvil", entry = 612125 },
			{ name = "Master Forge", entry = 612136 },
		}, spells = { 1307392, 1307175, 1307261 },
		clash = { { 8076, "Strength of Earth" } } },
	{ key = "wild", aura = 1230653, effect = Key("+308 armor, +13 all stats, +22 resistances"),
		objects = {
			{ name = "Enchanted Lute", entry = 651952 },
			{ name = "Arcane Salvager", entry = 612130 },
			{ name = "Arcane Forge", entry = 612143 },
		}, spells = { 1307234, 1307223, 1307176 },
		clash = { { 1126, "Mark of the Wild" }, { 21849, "Gift of the Wild" } } },
	{ key = "stamina", aura = 1230124, effect = Key("+56 Stamina"),
		objects = {
			{ name = "First Aid Kit", entry = 651953 },
			{ name = "Toxin Study", entry = 612091 },
			{ name = "Plague Doctor's Lab", entry = 612110 },
		}, spells = { 1307244, 1307396, 1307265 },
		clash = { { 1243, "Power Word: Fortitude" }, { 21562, "Prayer of Fortitude" } } },
	{ key = "kings", aura = 1230098, effect = Key("+8% all stats"),
		objects = {
			{ name = "Fish Bowl", entry = 651954 },
			{ name = "Fishing Rack", entry = 612090 },
			{ name = "Fishing Hut", entry = 612092 },
		}, spells = { 1307245, 1307247, 1307246 },
		clash = { { 20217, "Blessing of Kings" }, { 25898, "Greater Blessing of Kings" } } },
	{ key = "intellect", aura = 1229513, effect = Key("+25 Intellect"),
		objects = {
			{ name = "Incense Candle", entry = 651955 },
			{ name = "Greenhouse", entry = 612087 },
		}, spells = { 1307251, 1307248 },
		clash = { { 1459, "Arcane Intellect" }, { 23028, "Arcane Brilliance" } } },
	{ key = "might", aura = 1230164, effect = Key("+90 melee attack power"),
		objects = {
			{ name = "Lodestone", entry = 651956 },
			{ name = "Rock Garden", entry = 654285 },
			{ name = "Molten Foundry", entry = 612134 },
		}, spells = { 1307254, 1307386, 1307264 },
		clash = { { 19740, "Blessing of Might" }, { 25782, "Greater Blessing of Might" } } },
	{ key = "crit", aura = 1229519, effect = Key("+2% critical strike"),
		objects = {
			{ name = "Camp Chair", entry = 612275 },
			{ name = "Field Guide", entry = 612088 },
			{ name = "Trapper's Workbench", entry = 612082 },
		}, spells = { 1307229, 1307243, 1307397 },
		clash = { { 24907, "Moonkin Aura" }, { 24932, "Leader of the Pack" } } },
	{ key = "spirit", aura = 1229718, effect = Key("+32 Spirit"),
		-- Both banner spells place a tier 1 Faction Banner (one entry each);
		-- which entry is the Alliance and which the Horde banner is not in
		-- the client data, so both keep the plain name.
		objects = {
			{ name = "Faction Banner", tier = 1, entry = 612351 }, { name = "Faction Banner", tier = 1, entry = 612350 },
			{ name = "Alliance Banner", tier = 1 }, { name = "Horde Banner", tier = 1 },
			{ name = "Spinning Wheel", tier = 2, entry = 612123 }, { name = "Loom", tier = 3, entry = 612142 },
		},
		spells = { 1307239, 1307240, 1307393, 1307255 }, spellTiers = { 1, 1, 2, 3 },
		clash = { { 14752, "Divine Spirit" }, { 27681, "Prayer of Spirit" } } },
	{ key = "rest", aura = D.BOOSTED, effect = Key("5% of a level as rested XP"),
		objects = {
			{ name = "Camp Tent", entry = 528996 },
			{ name = "Tanning Rack", entry = 612122 },
			{ name = "Sewing Machine", entry = 612140 },
		}, spells = { 1307230, 1307395, 1307391 },
		clash = {}, rest = true },
}
-- The effect lines are read in the language shown at the time.
E:TranslateFields(D.FEATURES, "effect")
-- Bump when a saved entry row may be wrong for the data above. RELEARN
-- names a feature whose rows were wrong before a version: rows saved under
-- an older version are dropped and learned again, newer ones are kept.
-- Version 2: the Spirit tiers were corrected.
-- Version 3: rows also keep the object's name.
-- Version 4: the Spirit spells' tiers follow the client data (two banner
-- spells, then Spinning Wheel and Loom).
D.OBJECTS_VERSION = 4
D.RELEARN = { spirit = 4 }

local function ObjectOf(object, index)
	if type(object) == "table" then return object.name, math.min(object.tier or index, 3), object.entry end
	return object, math.min(index, 3)
end

-- The name of a feature's first object of that tier (nil when there is none).
function D.ObjectName(feature, tier)
	for index, object in ipairs(feature and feature.objects or {}) do
		local name, objectTier = ObjectOf(object, index)
		if objectTier == tier then return name end
	end
end

-- How many of a feature's objects have that tier.
function D.ObjectCount(feature, tier)
	local count = 0
	for index, object in ipairs(feature and feature.objects or {}) do
		if select(2, ObjectOf(object, index)) == tier then count = count + 1 end
	end
	return count
end

-- The tier a placing spell gives (its place in `spells` unless `spellTiers` says).
function D.SpellTier(feature, index)
	local tier = feature.spellTiers and feature.spellTiers[index] or index
	return math.min(tier, 3)
end

D.featureByAura, D.featureByObject, D.featureByKey = {}, {}, {}
for _, feature in ipairs(D.FEATURES) do
	D.featureByAura[feature.aura] = feature
	D.featureByKey[feature.key] = feature
	for index, object in ipairs(feature.objects) do
		local name, tier = ObjectOf(object, index)
		D.featureByObject[name:lower()] = { feature = feature, tier = tier, name = name }
	end
end

-- Utility objects take a slot but give no buff. `entry` is the object's
-- game object entry once it is known (from the placing spell, as above).
-- The two bots are summoned creatures, not objects: `creature` is their
-- creature ID (the same on every client language), read from the unit
-- when the game shows it; the English name is the fallback.
D.UTILITY = {
	{ name = "Reagent Bot", creature = 242498 },        -- spell 1307266
	{ name = "Repair Bot", creature = 254695 },         -- spell 1307385
	{ name = "Anarchist's Workbench", entry = 612145 }, -- spell 1307174
	{ name = "Cookie's Feast", entry = 612073 },        -- spell 1307257
	{ name = "Iron Oven", entry = 612132 },             -- spell 1307226
}
D.utilityByObject = {}
D.utilityByCreature = {}
for _, object in ipairs(D.UTILITY) do
	D.utilityByObject[object.name:lower()] = object.name
	if object.creature then D.utilityByCreature[object.creature] = object.name end
end

-- Game object entries (the number in a GameObject GUID, the same on every
-- client language). Each feature and utility object record holds its own as
-- `entry = n`, so objects that share a tier (the Spirit banners) each keep
-- theirs; the client also remembers each entry the first time it recognizes
-- the object by name, so every language works after that.
function D.IndexEntries()
	D.featureByEntry, D.utilityByEntry = {}, {}
	for _, feature in ipairs(D.FEATURES) do
		for index, object in ipairs(feature.objects) do
			local name, tier, entry = ObjectOf(object, index)
			if entry then D.featureByEntry[entry] = { feature = feature, tier = tier, name = name } end
		end
	end
	for _, object in ipairs(D.UTILITY) do
		if object.entry then D.utilityByEntry[object.entry] = object.name end
	end
end
D.IndexEntries()

-- Every spell that places a feature (they share one cooldown).
D.PLACE_SPELLS = {}
for _, feature in ipairs(D.FEATURES) do
	for _, id in ipairs(feature.spells) do D.PLACE_SPELLS[#D.PLACE_SPELLS + 1] = id end
end

-- Cooldowns in the client data: every feature spell is in the "Camping
-- Feature" category and shares one hour; the fire kits share five minutes.
-- Placing a feature is a 10 second cast (the Hearthstone's cast time), and
-- the rest features reach the players around them (an area effect).
D.FEATURE_CATEGORY = 97
D.FEATURE_COOLDOWN = 3600
D.FIRE_CATEGORY = 2511
D.FIRE_COOLDOWN = 300

D.FEATURE_LIFETIME = 15 * 60 -- a placed feature lasts 15 minutes
D.FIRE_LIFETIME = 10 * 60
