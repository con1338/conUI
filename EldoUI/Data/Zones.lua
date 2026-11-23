-- EldoUI zone facts for Zone Info (Modules/ZoneInfo.lua).
--
-- Hand-written from public game knowledge of the original zones (level
-- ranges, faction territory, the herbs and ore veins that grow there, the
-- fishing skill a zone asks for and the dungeons and raids whose entrance
-- lies in it). No other addon's data is used. Original zones use Classic
-- reference values; Forever dungeon names and map IDs follow client 70938,
-- with level ranges from Blizzard's dungeon overview, and Forever's new
-- zones carry reported ranges marked checked = false. The module prefers what the game
-- says (C_Map.GetMapLevels, C_EncounterJournal.GetDungeonEntrancesForMap,
-- your own Gathering finds) and falls back to this table. Zone maps,
-- territory and instance maps are checked against the client tables of
-- build 1.60.1.70862.
--
-- Keys are uiMapIDs. Fields, all optional:
--   min, max   level range
--   faction    "Alliance", "Horde", "contested" or "sanctuary"
--   herbs      herb node keys (E.zoneData.herbs), easiest first
--   ore        ore node keys (E.zoneData.ore), easiest first
--   fish       fishing skill from which no fish get away in the zone
--   checked    false for a WoW: Forever zone whose range and territory are
--              reported, not yet seen in the game (herbs, ore and fishing
--              are left out there rather than guessed)
--   new        true for a map WoW: Forever added; guide points written in
--              the original game's map frame have no match there
--   instances  instance keys (E.zoneData.instances) with an entrance here
local _, E = ...

local Z = {}
E.zoneData = Z

-- Herbs and veins: English name and the skill needed to gather them.
Z.herbs = {
	peacebloom = { name = "Peacebloom", skill = 1 },
	silverleaf = { name = "Silverleaf", skill = 1 },
	earthroot = { name = "Earthroot", skill = 15 },
	mageroyal = { name = "Mageroyal", skill = 50 },
	briarthorn = { name = "Briarthorn", skill = 70 },
	stranglekelp = { name = "Stranglekelp", skill = 85 },
	bruiseweed = { name = "Bruiseweed", skill = 100 },
	steelbloom = { name = "Wild Steelbloom", skill = 115 },
	gravemoss = { name = "Grave Moss", skill = 120 },
	kingsblood = { name = "Kingsblood", skill = 125 },
	liferoot = { name = "Liferoot", skill = 150 },
	fadeleaf = { name = "Fadeleaf", skill = 160 },
	goldthorn = { name = "Goldthorn", skill = 170 },
	khadgar = { name = "Khadgar's Whisker", skill = 185 },
	wintersbite = { name = "Wintersbite", skill = 195 },
	firebloom = { name = "Firebloom", skill = 205 },
	purplelotus = { name = "Purple Lotus", skill = 210 },
	arthas = { name = "Arthas' Tears", skill = 220 },
	sungrass = { name = "Sungrass", skill = 230 },
	blindweed = { name = "Blindweed", skill = 235 },
	ghostmushroom = { name = "Ghost Mushroom", skill = 245 },
	gromsblood = { name = "Gromsblood", skill = 250 },
	sansam = { name = "Golden Sansam", skill = 260 },
	dreamfoil = { name = "Dreamfoil", skill = 270 },
	silversage = { name = "Mountain Silversage", skill = 280 },
	plaguebloom = { name = "Plaguebloom", skill = 285 },
	icecap = { name = "Icecap", skill = 290 },
	blacklotus = { name = "Black Lotus", skill = 300 },
}

Z.ore = {
	copper = { name = "Copper Vein", skill = 1 },
	tin = { name = "Tin Vein", skill = 65 },
	incendicite = { name = "Incendicite Mineral Vein", skill = 65 },
	silver = { name = "Silver Vein", skill = 75 },
	bloodstone = { name = "Lesser Bloodstone Deposit", skill = 75 },
	iron = { name = "Iron Deposit", skill = 125 },
	indurium = { name = "Indurium Mineral Vein", skill = 150 },
	gold = { name = "Gold Vein", skill = 155 },
	mithril = { name = "Mithril Deposit", skill = 175 },
	truesilver = { name = "Truesilver Deposit", skill = 230 },
	darkiron = { name = "Dark Iron Deposit", skill = 230 },
	thorium = { name = "Small Thorium Vein", skill = 245 },
	richthorium = { name = "Rich Thorium Vein", skill = 275 },
}

-- Dungeons and raids. `map` is the instance's map ID from GetInstanceInfo.
Z.instances = {
	ragefire = { name = "Ragefire Chasm", kind = "dungeon", min = 13, max = 18, map = 389 },
	wailing = { name = "Wailing Caverns", kind = "dungeon", min = 17, max = 24, map = 43 },
	deadmines = { name = "The Deadmines", kind = "dungeon", min = 17, max = 26, map = 36 },
	shadowfang = { name = "Shadowfang Keep", kind = "dungeon", min = 22, max = 30, map = 33 },
	blackfathom = { name = "Blackfathom Deeps", kind = "dungeon", min = 24, max = 32, map = 48 },
	stockade = { name = "The Stockade", kind = "dungeon", min = 24, max = 32, map = 34 },
	gnomeregan = { name = "Gnomeregan", kind = "dungeon", min = 29, max = 38, map = 90 },
	kraul = { name = "Razorfen Kraul", kind = "dungeon", min = 29, max = 38, map = 47 },
	scarlet = { name = "Scarlet Monastery", kind = "dungeon", min = 26, max = 45, map = 189 },
	downs = { name = "Razorfen Downs", kind = "dungeon", min = 37, max = 46, map = 129 },
	uldaman = { name = "Uldaman", kind = "dungeon", min = 41, max = 51, map = 70 },
	zulfarrak = { name = "Zul'Farrak", kind = "dungeon", min = 44, max = 54, map = 209 },
	maraudon = { name = "Maraudon", kind = "dungeon", min = 46, max = 55, map = 349 },
	sunken = { name = "Sunken Temple", kind = "dungeon", min = 50, max = 60, map = 109 },
	brd = { name = "Blackrock Depths", kind = "dungeon", min = 52, max = 60, map = 230 },
	brs = { name = "Blackrock Spire", kind = "dungeon", min = 55, max = 60, map = 229 },
	diremaul = { name = "Dire Maul", kind = "dungeon", min = 55, max = 60, map = 429 },
	scholomance = { name = "Scholomance", kind = "dungeon", min = 58, max = 60, map = 289 },
	stratholme = { name = "Stratholme", kind = "dungeon", min = 58, max = 60, map = 329 },
	mc = { name = "Molten Core", kind = "raid", min = 60, max = 60, map = 409 },
	onyxia = { name = "Onyxia's Lair", kind = "raid", min = 60, max = 60, map = 249 },
	bwl = { name = "Blackwing Lair", kind = "raid", min = 60, max = 60, map = 469 },
	zg = { name = "Zul'Gurub", kind = "raid", min = 60, max = 60, map = 309 },
	aq20 = { name = "Ruins of Ahn'Qiraj", kind = "raid", min = 60, max = 60, map = 509 },
	aq40 = { name = "Temple of Ahn'Qiraj", kind = "raid", min = 60, max = 60, map = 531 },
	naxx = { name = "Naxxramas", kind = "raid", min = 60, max = 60, map = 533 },
	thanes = { name = E.Key("The Hall of Thanes"), kind = "dungeon", min = 13, max = 18, map = 3065, new = true },
	lordaeron = { name = E.Key("Ruins of Lordaeron"), kind = "dungeon", min = 15, max = 20, map = 2999, new = true },
	excavation = { name = E.Key("Excavation Site: Wetlands"), kind = "dungeon", min = 24, max = 29, map = 2998, new = true },
	dalaran = { name = E.Key("City of Dalaran"), kind = "dungeon", min = 28, max = 33, map = 2959, new = true },
	drownedcity = { name = E.Key("The Drowned City"), kind = "dungeon", min = 35, max = 40, map = 2970, new = true },
	alcaz = { name = E.Key("Alcaz Prison"), kind = "dungeon", min = 48, max = 53, map = 2994, new = true },
	blackmaw = { name = E.Key("Blackmaw Hold"), kind = "dungeon", min = 55, max = 60, map = 2974, new = true },
	shapersterrace = { name = E.Key("The Shaper's Terrace"), kind = "dungeon", min = 58, max = 60, map = 3001, new = true },
	kroldok = { name = E.Key("Krol'dok Stronghold"), kind = "dungeon", min = 40, max = 45, map = 3039, new = true },
}

local STARTER_HERBS = { "peacebloom", "silverleaf", "earthroot" }
local BLACKROCK = { "brd", "brs", "mc", "bwl" }

Z.zones = {
	-- Eastern Kingdoms
	[1429] = { min = 1, max = 10, faction = "Alliance", herbs = STARTER_HERBS, ore = { "copper" }, fish = 25 }, -- Elwynn Forest
	[1426] = { min = 1, max = 10, faction = "Alliance", herbs = STARTER_HERBS, ore = { "copper" }, fish = 25, instances = { "gnomeregan", "thanes" } }, -- Dun Morogh
	[1420] = { min = 1, max = 10, faction = "Horde", herbs = STARTER_HERBS, ore = { "copper" }, fish = 25, instances = { "scarlet", "lordaeron" } }, -- Tirisfal Glades
	[1436] = { min = 10, max = 20, faction = "Alliance", herbs = { "peacebloom", "silverleaf", "earthroot", "mageroyal", "briarthorn" }, ore = { "copper", "tin", "silver" }, fish = 75, instances = { "deadmines" } }, -- Westfall
	[1432] = { min = 10, max = 20, faction = "Alliance", herbs = { "peacebloom", "silverleaf", "earthroot", "mageroyal", "briarthorn" }, ore = { "copper", "tin", "silver" }, fish = 75 }, -- Loch Modan
	[1421] = { min = 10, max = 20, faction = "Horde", herbs = { "peacebloom", "silverleaf", "earthroot", "mageroyal", "briarthorn", "stranglekelp" }, ore = { "copper", "tin", "silver" }, fish = 75, instances = { "shadowfang" } }, -- Silverpine Forest
	[1433] = { min = 15, max = 25, faction = "contested", herbs = { "peacebloom", "silverleaf", "earthroot", "mageroyal", "briarthorn", "stranglekelp", "bruiseweed" }, ore = { "copper", "tin", "silver" }, fish = 150 }, -- Redridge Mountains
	[1431] = { min = 18, max = 30, faction = "contested", herbs = { "mageroyal", "briarthorn", "bruiseweed", "gravemoss", "kingsblood" }, ore = { "copper", "tin", "silver", "iron", "gold" }, fish = 150 }, -- Duskwood
	[1437] = { min = 20, max = 30, faction = "contested", herbs = { "briarthorn", "stranglekelp", "bruiseweed", "steelbloom", "gravemoss", "kingsblood" }, ore = { "copper", "tin", "silver", "iron", "gold" }, fish = 150, instances = { "excavation" } }, -- Wetlands
	[1424] = { min = 20, max = 30, faction = "contested", herbs = { "briarthorn", "stranglekelp", "bruiseweed", "steelbloom", "kingsblood", "liferoot", "fadeleaf" }, ore = { "tin", "silver", "iron", "gold" }, fish = 150 }, -- Hillsbrad Foothills
	[1416] = { min = 30, max = 40, faction = "contested", herbs = { "bruiseweed", "steelbloom", "kingsblood", "liferoot", "fadeleaf", "khadgar", "wintersbite" }, ore = { "silver", "iron", "gold", "mithril" }, fish = 225, instances = { "dalaran" } }, -- Alterac Mountains
	[1417] = { min = 30, max = 40, faction = "contested", herbs = { "bruiseweed", "steelbloom", "kingsblood", "liferoot", "fadeleaf", "goldthorn", "khadgar" }, ore = { "tin", "silver", "iron", "gold", "mithril" }, fish = 225 }, -- Arathi Highlands
	[1434] = { min = 30, max = 45, faction = "contested", herbs = { "steelbloom", "kingsblood", "liferoot", "fadeleaf", "goldthorn", "khadgar", "purplelotus" }, ore = { "tin", "silver", "iron", "gold", "mithril", "truesilver" }, fish = 225, instances = { "zg", "drownedcity" } }, -- Stranglethorn Vale
	[1418] = { min = 35, max = 45, faction = "contested", herbs = { "steelbloom", "kingsblood", "fadeleaf", "goldthorn", "khadgar", "firebloom" }, ore = { "iron", "gold", "mithril", "truesilver" }, instances = { "uldaman" } }, -- Badlands
	[1435] = { min = 35, max = 45, faction = "contested", herbs = { "kingsblood", "liferoot", "fadeleaf", "goldthorn", "khadgar", "blindweed" }, ore = { "iron", "gold", "mithril" }, fish = 225, instances = { "sunken" } }, -- Swamp of Sorrows
	[1425] = { min = 40, max = 50, faction = "contested", herbs = { "liferoot", "fadeleaf", "goldthorn", "khadgar", "purplelotus", "sungrass" }, ore = { "iron", "gold", "mithril", "truesilver" }, fish = 300 }, -- The Hinterlands
	[1427] = { min = 43, max = 50, faction = "contested", herbs = { "firebloom" }, ore = { "iron", "gold", "mithril", "truesilver", "darkiron", "thorium" }, instances = BLACKROCK }, -- Searing Gorge
	[1419] = { min = 45, max = 55, faction = "contested", herbs = { "firebloom", "sungrass" }, ore = { "gold", "mithril", "truesilver", "thorium" } }, -- Blasted Lands
	[1428] = { min = 50, max = 58, faction = "contested", herbs = { "firebloom", "sungrass", "sansam", "dreamfoil", "silversage", "blacklotus" }, ore = { "mithril", "truesilver", "darkiron", "thorium", "richthorium" }, instances = BLACKROCK }, -- Burning Steppes
	[1422] = { min = 51, max = 58, faction = "contested", herbs = { "arthas", "sungrass", "sansam", "dreamfoil", "plaguebloom" }, ore = { "mithril", "truesilver", "thorium" }, fish = 300, instances = { "scholomance" } }, -- Western Plaguelands
	[1423] = { min = 53, max = 60, faction = "contested", herbs = { "arthas", "sansam", "dreamfoil", "silversage", "plaguebloom", "blacklotus" }, ore = { "mithril", "truesilver", "thorium", "richthorium" }, fish = 425, instances = { "stratholme", "naxx" } }, -- Eastern Plaguelands
	[1430] = { min = 55, max = 60, faction = "contested", herbs = { "sansam", "dreamfoil", "silversage" }, ore = { "thorium" } }, -- Deadwind Pass
	[1453] = { faction = "Alliance", fish = 25, instances = { "stockade" } }, -- Stormwind City
	[1455] = { faction = "Alliance", instances = { "thanes" } }, -- Ironforge
	[1458] = { faction = "Horde", fish = 25, instances = { "lordaeron" } }, -- Undercity
	-- New in WoW: Forever (zone maps from client 70862; ranges and territory
	-- as reported, until seen in the game).
	[2548] = { min = 36, max = 44, faction = "contested", checked = false, new = true, instances = { "kroldok" } }, -- Riverglades: Alliance, Horde and neutral towns

	-- Kalimdor
	[1411] = { min = 1, max = 10, faction = "Horde", herbs = STARTER_HERBS, ore = { "copper" }, fish = 25 }, -- Durotar
	[1412] = { min = 1, max = 10, faction = "Horde", herbs = STARTER_HERBS, ore = { "copper" }, fish = 25 }, -- Mulgore
	[1438] = { min = 1, max = 10, faction = "Alliance", herbs = STARTER_HERBS, fish = 25 }, -- Teldrassil
	[1439] = { min = 10, max = 20, faction = "Alliance", herbs = { "peacebloom", "silverleaf", "earthroot", "mageroyal", "briarthorn", "stranglekelp", "bruiseweed" }, ore = { "copper", "tin", "silver" }, fish = 75 }, -- Darkshore
	[1413] = { min = 10, max = 25, faction = "Horde", herbs = { "peacebloom", "silverleaf", "earthroot", "mageroyal", "briarthorn", "stranglekelp", "bruiseweed" }, ore = { "copper", "tin", "silver" }, fish = 75, instances = { "wailing", "kraul", "downs" } }, -- The Barrens
	[1442] = { min = 15, max = 27, faction = "contested", herbs = { "mageroyal", "briarthorn", "stranglekelp", "bruiseweed", "steelbloom" }, ore = { "copper", "tin", "silver" }, fish = 150 }, -- Stonetalon Mountains
	[1440] = { min = 18, max = 30, faction = "contested", herbs = { "mageroyal", "briarthorn", "stranglekelp", "bruiseweed", "steelbloom", "kingsblood", "liferoot" }, ore = { "copper", "tin", "silver", "iron", "gold" }, fish = 150, instances = { "blackfathom" } }, -- Ashenvale
	[1441] = { min = 25, max = 35, faction = "contested", herbs = { "bruiseweed", "steelbloom", "kingsblood", "liferoot", "fadeleaf" }, ore = { "tin", "silver", "iron", "gold" }, fish = 225 }, -- Thousand Needles
	[1443] = { min = 30, max = 40, faction = "contested", herbs = { "steelbloom", "kingsblood", "liferoot", "fadeleaf", "goldthorn", "khadgar" }, ore = { "tin", "silver", "iron", "gold", "mithril" }, fish = 225, instances = { "maraudon" } }, -- Desolace
	[1445] = { min = 35, max = 45, faction = "contested", herbs = { "kingsblood", "liferoot", "fadeleaf", "goldthorn", "khadgar" }, ore = { "silver", "iron", "gold", "mithril" }, fish = 225, instances = { "onyxia", "alcaz" } }, -- Dustwallow Marsh
	[1444] = { min = 40, max = 50, faction = "contested", herbs = { "liferoot", "fadeleaf", "goldthorn", "khadgar", "purplelotus", "sungrass" }, ore = { "iron", "gold", "mithril", "truesilver" }, fish = 300, instances = { "diremaul" } }, -- Feralas
	[1446] = { min = 40, max = 50, faction = "contested", herbs = { "goldthorn", "firebloom", "purplelotus", "sungrass" }, ore = { "silver", "iron", "gold", "mithril", "truesilver" }, fish = 300, instances = { "zulfarrak" } }, -- Tanaris
	[1447] = { min = 45, max = 55, faction = "contested", herbs = { "goldthorn", "purplelotus", "sungrass", "sansam", "dreamfoil", "silversage" }, ore = { "gold", "mithril", "truesilver", "thorium" }, fish = 300, instances = { "blackmaw" } }, -- Azshara
	[1448] = { min = 48, max = 55, faction = "contested", herbs = { "arthas", "sungrass", "gromsblood", "sansam", "dreamfoil", "plaguebloom" }, ore = { "gold", "mithril", "truesilver", "thorium" }, fish = 300 }, -- Felwood
	[1449] = { min = 48, max = 55, faction = "contested", herbs = { "sungrass", "blindweed", "gromsblood", "sansam", "dreamfoil", "silversage" }, ore = { "mithril", "truesilver", "thorium", "richthorium" }, fish = 300, instances = { "shapersterrace" } }, -- Un'Goro Crater
	[1452] = { min = 55, max = 60, faction = "contested", herbs = { "sansam", "dreamfoil", "silversage", "icecap", "blacklotus" }, ore = { "mithril", "truesilver", "thorium", "richthorium" }, fish = 425 }, -- Winterspring
	[1451] = { min = 55, max = 60, faction = "contested", herbs = { "sansam", "dreamfoil", "silversage", "blacklotus" }, ore = { "truesilver", "thorium", "richthorium" }, instances = { "aq20", "aq40" } }, -- Silithus
	[1450] = { faction = "contested", fish = 300 }, -- Moonglade
	[1454] = { faction = "Horde", fish = 25, instances = { "ragefire" } }, -- Orgrimmar
	[1456] = { faction = "Horde" }, -- Thunder Bluff
	[1457] = { faction = "Alliance", fish = 25 }, -- Darnassus
	-- New in WoW: Forever (zone maps from client 70862; ranges and territory
	-- as reported, until seen in the game).
	[2652] = { min = 35, max = 45, faction = "contested", checked = false, new = true }, -- Shen'dralas, through Desolace's Valley of Bones
	[2482] = { min = 55, max = 60, faction = "contested", checked = false, new = true }, -- Mount Hyjal, between Felwood and Winterspring

	-- Zephras Isle (its own continent, the Skyborne starting zone; checked = false)
	[2521] = { min = 1, max = 10, faction = "contested", checked = false, new = true }, -- Zephras Isle
}

-- The original game's instance map IDs and folded names: a dungeon entrance
-- the game shows that is in neither list is new in WoW: Forever.
Z.originalInstanceMaps = {}
Z.originalInstanceNames = {}
local function Fold(text)
	return (tostring(text or ""):lower():gsub("^the ", ""):gsub("[^%w]", ""))
end
Z.Fold = Fold
for _, inst in pairs(Z.instances) do
	if not inst.new then
		Z.originalInstanceMaps[inst.map] = true
		Z.originalInstanceNames[Fold(inst.name)] = true
	end
end
-- Wings and parts the game may list as their own entrance.
for _, name in ipairs({ "Lower Blackrock Spire", "Upper Blackrock Spire", "Dire Maul East", "Dire Maul North", "Dire Maul West",
	"Scarlet Monastery Graveyard", "Scarlet Monastery Library", "Scarlet Monastery Armory", "Scarlet Monastery Cathedral",
	"Stratholme Main Gate", "Stratholme Service Entrance", "Blackrock Mountain" }) do
	Z.originalInstanceNames[Fold(name)] = true
end
