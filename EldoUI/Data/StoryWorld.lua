-- EldoUI story world: the noun table the journal story engine writes with
-- (Modules/LootGuide/Adventure/Story/Grammar.lua, Voice.lua).
--
-- Written by us (Apache-2.0) from public game knowledge of the Classic-era
-- world. English only: the names are the enUS strings the game returns, and
-- every epithet, scene and mood word below is our own text (no quest, lore,
-- item or zone description from the game is copied).
--
-- E.StoryWorld fields:
--   places[name]   one row per zone, city, subzone, instance, battleground
--                  and continent the story can name:
--     type        "zone" | "city" | "subzone" | "instance" | "raid" | "battleground" | "continent"
--     the         true when English prose says "the X" although the game
--                 string has no "The " (the Wetlands, the Scarlet Monastery)
--     bare        true when the head-noun rule would add "the" but must not
--                 (Blackfathom Deeps, Thousand Needles)
--     plural      true for plural names (possessive "the Barrens'")
--     at          true for places that take "at" (towns, inns, cemeteries, harbors)
--     short       the declared short form for later mentions
--     continent   "Eastern Kingdoms" | "Kalimdor"
--     faction     "Alliance" | "Horde" | "contested" | "sanctuary"
--     epithet     the one setting phrase Chronicle may use (geography only)
--     scene       the Bard image of the place (geography only)
--     mood        the mood words, for review and the voice checks
--     entrance    instances: the noun for "the {entrance} of {instance}"
--     hall        instances: the reference noun ("those halls", "those caves")
--   factions[name] { the = true, plural = true }
--   npcs[name]     { plural = true } for plural encounters
--   ports[subzone] { vehicle = "ship"|"zeppelin"|"boat", faction = ... }
--   starts[race]   the race's starting zone (only for "Home ground" titles)
--   pluralHeads, atHeads, ofHeads, silentH, abbreviations: grammar rule data
-- The folded lookup sets (the, bare, plural, at, short, known) are built at
-- the bottom of the file.
local _, E = ...

local W = {}
E.StoryWorld = W

local EK, KAL = "Eastern Kingdoms", "Kalimdor"

W.places = {
	-- Continents
	["Eastern Kingdoms"] = { type = "continent", the = true, plural = true },
	["Kalimdor"] = { type = "continent" },
	["Azeroth"] = { type = "continent" },

	-- Eastern Kingdoms zones
	["Elwynn Forest"] = { type = "zone", continent = EK, faction = "Alliance", short = "Elwynn",
		epithet = "the green fields of Elwynn", scene = "the gentle farmland of Elwynn Forest", mood = { "green", "gentle", "farmland", "forest roads" } },
	["Dun Morogh"] = { type = "zone", continent = EK, faction = "Alliance",
		epithet = "the snows of Dun Morogh", scene = "the cold pine passes of Dun Morogh", mood = { "snow", "cold", "pine", "mountain pass" } },
	["Tirisfal Glades"] = { type = "zone", continent = EK, faction = "Horde", bare = true, short = "Tirisfal",
		epithet = "the gray glades of Tirisfal", scene = "the withered gray glades of Tirisfal", mood = { "gray", "withered", "quiet", "dead trees" } },
	["Westfall"] = { type = "zone", continent = EK, faction = "Alliance",
		epithet = "the farmlands of Westfall", scene = "the golden fields of Westfall", mood = { "golden fields", "windswept", "empty farms", "dust" } },
	["Loch Modan"] = { type = "zone", continent = EK, faction = "Alliance",
		epithet = "the hills of Loch Modan", scene = "the green hills of Loch Modan", mood = { "green hills", "the loch", "the great dam" } },
	["Silverpine Forest"] = { type = "zone", continent = EK, faction = "Horde", short = "Silverpine",
		epithet = "the pine woods of Silverpine", scene = "the misty pines of Silverpine Forest", mood = { "mist", "pine", "gray coast" } },
	["Redridge Mountains"] = { type = "zone", continent = EK, faction = "contested", the = true, plural = true, short = "Redridge",
		epithet = "the red hills of Redridge", scene = "the red stone ridges of Redridge", mood = { "red stone", "lake", "ridgeline" } },
	["Duskwood"] = { type = "zone", continent = EK, faction = "contested",
		epithet = "the dark woods of Duskwood", scene = "the endless dusk of Duskwood", mood = { "gloom", "endless dusk", "lantern-lit Darkshire", "graveyards" } },
	["Wetlands"] = { type = "zone", continent = EK, faction = "contested", the = true, plural = true,
		epithet = "the marshes of the Wetlands", scene = "the reeds and mud of the Wetlands", mood = { "mud", "reeds", "damp", "harbor" } },
	["Hillsbrad Foothills"] = { type = "zone", continent = EK, faction = "contested", the = true, plural = true, short = "Hillsbrad",
		epithet = "the green foothills of Hillsbrad", scene = "the rolling orchards of Hillsbrad", mood = { "rolling hills", "orchards", "contested fields" } },
	["Alterac Mountains"] = { type = "zone", continent = EK, faction = "contested", the = true, plural = true, short = "Alterac",
		epithet = "the snowy passes of Alterac", scene = "the high snowy passes of Alterac", mood = { "snow", "ruins", "high passes" } },
	["Arathi Highlands"] = { type = "zone", continent = EK, faction = "contested", the = true, plural = true, short = "Arathi",
		epithet = "the open highlands of Arathi", scene = "the windswept stone circles of Arathi", mood = { "wind", "stone circles", "old ruins" } },
	["Stranglethorn Vale"] = { type = "zone", continent = EK, faction = "contested", short = "Stranglethorn",
		epithet = "the jungle of Stranglethorn", scene = "the hot green jungle of Stranglethorn", mood = { "heat", "vines", "jungle", "pirate coast" } },
	["Badlands"] = { type = "zone", continent = EK, faction = "contested", the = true, plural = true,
		epithet = "the dry canyons of the Badlands", scene = "the sun-baked red rock of the Badlands", mood = { "dust", "red rock", "sun", "canyon" } },
	["Swamp of Sorrows"] = { type = "zone", continent = EK, faction = "contested", the = true,
		epithet = "the misty Swamp of Sorrows", scene = "the still, misty water of the Swamp of Sorrows", mood = { "still water", "mist", "sunken stone" } },
	["The Hinterlands"] = { type = "zone", continent = EK, faction = "contested", plural = true,
		epithet = "the wild hills of the Hinterlands", scene = "the high wild aeries of the Hinterlands", mood = { "wild", "high aeries", "troll ruins" } },
	["Searing Gorge"] = { type = "zone", continent = EK, faction = "contested", the = true,
		epithet = "the ash and slag of the Searing Gorge", scene = "the ash and molten slag of the Searing Gorge", mood = { "heat", "ash", "slag", "molten" } },
	["Blasted Lands"] = { type = "zone", continent = EK, faction = "contested", the = true, plural = true,
		epithet = "the scorched Blasted Lands", scene = "the scorched red earth of the Blasted Lands", mood = { "scorched", "red earth", "the Dark Portal" } },
	["Burning Steppes"] = { type = "zone", continent = EK, faction = "contested", the = true, plural = true,
		epithet = "the black hills of the Burning Steppes", scene = "the smoke and black rock of the Burning Steppes", mood = { "smoke", "fire", "black rock" } },
	["Western Plaguelands"] = { type = "zone", continent = EK, faction = "contested", the = true, plural = true, short = "the Plaguelands",
		epithet = "the blighted fields of the Western Plaguelands", scene = "the blighted, ruined farms of the Western Plaguelands", mood = { "blight", "ruined farms", "plague" } },
	["Eastern Plaguelands"] = { type = "zone", continent = EK, faction = "contested", the = true, plural = true, short = "the Plaguelands",
		epithet = "the rotting east of the Plaguelands", scene = "the rot and ruined towns of the Eastern Plaguelands", mood = { "rot", "blight", "ruined towns" } },
	["Deadwind Pass"] = { type = "zone", continent = EK, faction = "contested",
		epithet = "the silent Deadwind Pass", scene = "the bare, silent trees of Deadwind Pass", mood = { "bare", "silent", "dead trees" } },
	["Stormwind City"] = { type = "city", continent = EK, faction = "Alliance", short = "Stormwind",
		epithet = "the white walls of Stormwind", scene = "the white stone and canals of Stormwind", mood = { "white stone", "canals", "the city" } },
	["Ironforge"] = { type = "city", continent = EK, faction = "Alliance",
		epithet = "the forge-lit halls of Ironforge", scene = "the forge-lit halls of Ironforge", mood = { "forge", "stone halls", "warmth" } },
	["Undercity"] = { type = "city", continent = EK, faction = "Horde", the = true,
		epithet = "the halls beneath Lordaeron", scene = "the green-lit halls beneath Lordaeron", mood = { "sewers", "green light", "underground" } },

	-- Kalimdor zones
	["Durotar"] = { type = "zone", continent = KAL, faction = "Horde",
		epithet = "the red dust of Durotar", scene = "the hot red earth of Durotar", mood = { "red earth", "heat", "dry coast" } },
	["Mulgore"] = { type = "zone", continent = KAL, faction = "Horde",
		epithet = "the open grasslands of Mulgore", scene = "the wind and grass of Mulgore", mood = { "grass", "wind", "mesas" } },
	["Teldrassil"] = { type = "zone", continent = KAL, faction = "Alliance",
		epithet = "the woods of Teldrassil", scene = "the quiet moonlit woods of Teldrassil", mood = { "moonlight", "the great tree", "quiet woods" } },
	["Darkshore"] = { type = "zone", continent = KAL, faction = "Alliance",
		epithet = "the dark coast of Darkshore", scene = "the moonlit shore of Darkshore", mood = { "moonlit shore", "ruins", "sea mist" } },
	["The Barrens"] = { type = "zone", continent = KAL, faction = "Horde", plural = true,
		epithet = "the dusty Barrens", scene = "the long, dusty roads of the Barrens", mood = { "dust", "heat", "savanna", "long roads" } },
	["Stonetalon Mountains"] = { type = "zone", continent = KAL, faction = "contested", the = true, plural = true, short = "Stonetalon",
		epithet = "the high peaks of Stonetalon", scene = "the cliffs and high peaks of Stonetalon", mood = { "peaks", "cliffs", "logging scars" } },
	["Ashenvale"] = { type = "zone", continent = KAL, faction = "contested",
		epithet = "the old forests of Ashenvale", scene = "the ancient shade of Ashenvale", mood = { "ancient trees", "shade", "contested woods" } },
	["Thousand Needles"] = { type = "zone", continent = KAL, faction = "contested", bare = true, plural = true,
		epithet = "the stone spires of Thousand Needles", scene = "the stone spires and salt flats of Thousand Needles", mood = { "spires", "canyons", "salt flats" } },
	["Desolace"] = { type = "zone", continent = KAL, faction = "contested",
		epithet = "the gray waste of Desolace", scene = "the gray, bone-strewn waste of Desolace", mood = { "gray", "bones", "waste", "centaur country" } },
	["Dustwallow Marsh"] = { type = "zone", continent = KAL, faction = "contested", bare = true, short = "Dustwallow",
		epithet = "the humid marsh of Dustwallow", scene = "the hot mud of Dustwallow Marsh", mood = { "swamp", "mud", "heat" } },
	["Feralas"] = { type = "zone", continent = KAL, faction = "contested",
		epithet = "the green forests of Feralas", scene = "the giant green forests of Feralas", mood = { "rain forest", "giant trees", "green" } },
	["Tanaris"] = { type = "zone", continent = KAL, faction = "contested",
		epithet = "the sands of Tanaris", scene = "the hot sands of Tanaris", mood = { "sand", "heat", "desert" } },
	["Azshara"] = { type = "zone", continent = KAL, faction = "contested",
		epithet = "the red-leaved coast of Azshara", scene = "the autumn-red coast of Azshara", mood = { "autumn red", "ruins", "coast" } },
	["Felwood"] = { type = "zone", continent = KAL, faction = "contested",
		epithet = "the corrupted woods of Felwood", scene = "the sickly green woods of Felwood", mood = { "sickly green", "corrupted", "fel" } },
	["Un'Goro Crater"] = { type = "zone", continent = KAL, faction = "contested", short = "Un'Goro",
		epithet = "the steaming jungle of Un'Goro", scene = "the steaming, primal jungle of Un'Goro", mood = { "steam", "primal jungle", "crater walls" } },
	["Winterspring"] = { type = "zone", continent = KAL, faction = "contested",
		epithet = "the snowfields of Winterspring", scene = "the quiet snowfields of Winterspring", mood = { "snow", "frozen", "quiet", "the far north" } },
	["Silithus"] = { type = "zone", continent = KAL, faction = "contested",
		epithet = "the hive-scarred sands of Silithus", scene = "the hive-scarred sands of Silithus", mood = { "sand", "hives", "heat" } },
	["Moonglade"] = { type = "zone", continent = KAL, faction = "sanctuary",
		epithet = "the quiet glade of Moonglade", scene = "the peaceful, moonlit glade of Moonglade", mood = { "moonlit", "peaceful", "sacred" } },
	["Orgrimmar"] = { type = "city", continent = KAL, faction = "Horde",
		epithet = "the red stone of Orgrimmar", scene = "the smoke and red stone of Orgrimmar", mood = { "red stone", "smoke", "the city" } },
	["Thunder Bluff"] = { type = "city", continent = KAL, faction = "Horde",
		epithet = "the high bluffs of Thunder Bluff", scene = "the windy mesas of Thunder Bluff", mood = { "mesas", "wind", "height" } },
	["Darnassus"] = { type = "city", continent = KAL, faction = "Alliance",
		epithet = "the moonlit city of Darnassus", scene = "the moonlit temple city of Darnassus", mood = { "moonlight", "temple", "tree city" } },

	-- Battlegrounds
	["Warsong Gulch"] = { type = "battleground", continent = KAL, scene = "the forest gulch of Warsong", mood = { "forest gulch", "flags" } },
	["Arathi Basin"] = { type = "battleground", continent = EK, scene = "the farmland bases of Arathi Basin", mood = { "farmland", "bases" } },
	["Alterac Valley"] = { type = "battleground", continent = EK, scene = "the long snowy valley of Alterac", mood = { "snow", "the long valley" } },

	-- Dungeons and raids (entrance continent)
	["Ragefire Chasm"] = { type = "instance", continent = KAL, entrance = "cave mouth", hall = "tunnels", scene = "the fiery tunnels beneath Orgrimmar", mood = { "fire", "tunnels beneath Orgrimmar" } },
	["Wailing Caverns"] = { type = "instance", continent = KAL, the = true, plural = true, entrance = "cave mouth", hall = "caves", scene = "the moaning green caves of the Wailing Caverns", mood = { "caves", "moaning wind", "green water" } },
	["The Deadmines"] = { type = "instance", continent = EK, plural = true, entrance = "tunnels", hall = "tunnels", scene = "the mine tunnels of the Deadmines", mood = { "mine", "tunnels", "a hidden cove", "the ship" } },
	["Shadowfang Keep"] = { type = "instance", continent = EK, entrance = "gates", hall = "halls", scene = "the gloomy battlements of Shadowfang Keep", mood = { "gloomy keep", "battlements" } },
	["Blackfathom Deeps"] = { type = "instance", continent = KAL, bare = true, plural = true, entrance = "flooded steps", hall = "halls", scene = "the dark water of Blackfathom Deeps", mood = { "flooded ruins", "dark water" } },
	["The Stockade"] = { type = "instance", continent = EK, entrance = "cell doors", hall = "halls", scene = "the cells of the Stockade", mood = { "prison", "cells", "riot" } },
	["Gnomeregan"] = { type = "instance", continent = EK, entrance = "gates", hall = "halls", scene = "the gears and machines of Gnomeregan", mood = { "machines", "gears", "poisoned air" } },
	["Razorfen Kraul"] = { type = "instance", continent = KAL, entrance = "thorn tunnels", hall = "tunnels", scene = "the thorny warrens of Razorfen Kraul", mood = { "thorns", "warrens" } },
	["Razorfen Downs"] = { type = "instance", continent = KAL, bare = true, plural = true, entrance = "thorn barrows", hall = "barrows", scene = "the thorns and barrows of Razorfen Downs", mood = { "thorns", "bones", "barrows" } },
	["Scarlet Monastery"] = { type = "instance", continent = EK, the = true, entrance = "gates", hall = "halls", scene = "the crimson halls of the Scarlet Monastery", mood = { "crimson halls", "banners", "crusade" } },
	["Uldaman"] = { type = "instance", continent = EK, entrance = "stone doors", hall = "vaults", scene = "the old stone vaults of Uldaman", mood = { "stone vaults", "excavation", "old titan halls" } },
	["Zul'Farrak"] = { type = "instance", continent = KAL, entrance = "city gates", hall = "streets", scene = "the sandstone walls of Zul'Farrak", mood = { "sandstone", "troll city", "desert heat" } },
	["Maraudon"] = { type = "instance", continent = KAL, entrance = "cave mouth", hall = "caves", scene = "the crystal caverns of Maraudon", mood = { "caverns", "crystal", "poisoned water" } },
	["Sunken Temple"] = { type = "instance", continent = EK, the = true, entrance = "drowned steps", hall = "halls", scene = "the drowned green halls of the Sunken Temple", mood = { "drowned temple", "green water" } },
	["The Temple of Atal'Hakkar"] = { type = "instance", continent = EK, entrance = "drowned steps", hall = "halls", scene = "the drowned green halls of the Temple of Atal'Hakkar", mood = { "drowned temple", "green water" } },
	["Blackrock Depths"] = { type = "instance", continent = EK, bare = true, plural = true, entrance = "deep halls", hall = "halls", scene = "the Dark Iron halls of Blackrock Depths", mood = { "Dark Iron halls", "lava", "deep" } },
	["Blackrock Spire"] = { type = "instance", continent = EK, entrance = "spire gate", hall = "halls", scene = "the towering heights of Blackrock Spire", mood = { "towering spire", "dragonkin" } },
	["Lower Blackrock Spire"] = { type = "instance", continent = EK, entrance = "spire gate", hall = "halls", scene = "the towering heights of Blackrock Spire", mood = { "towering spire", "dragonkin" } },
	["Upper Blackrock Spire"] = { type = "instance", continent = EK, entrance = "spire gate", hall = "halls", scene = "the towering heights of Blackrock Spire", mood = { "towering spire", "dragonkin" } },
	["Dire Maul"] = { type = "instance", continent = KAL, entrance = "broken gates", hall = "ruins", scene = "the broken elven halls of Dire Maul", mood = { "broken elven city", "ruins" } },
	["Scholomance"] = { type = "instance", continent = EK, entrance = "crypt doors", hall = "halls", scene = "the cold crypts of Scholomance", mood = { "cold crypt", "school of dark arts" } },
	["Stratholme"] = { type = "instance", continent = EK, entrance = "city gates", hall = "streets", scene = "the haunted streets of Stratholme", mood = { "burning city", "haunted streets" } },
	["Molten Core"] = { type = "raid", continent = EK, entrance = "fiery depths", hall = "depths", scene = "the fiery depths of Molten Core", mood = { "molten", "fire", "the deep core" } },
	["Onyxia's Lair"] = { type = "raid", continent = KAL, entrance = "lair mouth", hall = "caves", scene = "the scorched cave of Onyxia's Lair", mood = { "dragon's lair", "scorched cave" } },
	["Blackwing Lair"] = { type = "raid", continent = EK, entrance = "black gates", hall = "halls", scene = "the black halls of Blackwing Lair", mood = { "black dragonflight", "halls" } },
	["Zul'Gurub"] = { type = "raid", continent = EK, entrance = "jungle gates", hall = "temples", scene = "the jungle temples of Zul'Gurub", mood = { "jungle temple", "blood" } },
	["Ruins of Ahn'Qiraj"] = { type = "raid", continent = KAL, the = true, plural = true, entrance = "ruined gates", hall = "ruins", scene = "the sand-choked ruins of Ahn'Qiraj", mood = { "ruins", "sand", "insects" } },
	["Temple of Ahn'Qiraj"] = { type = "raid", continent = KAL, the = true, entrance = "temple gates", hall = "halls", scene = "the carapace halls of the Temple of Ahn'Qiraj", mood = { "temple", "insects", "carapace" } },
	["Naxxramas"] = { type = "raid", continent = EK, entrance = "necropolis gates", hall = "halls", scene = "the cold, floating necropolis of Naxxramas", mood = { "cold", "floating necropolis" } },

	-- Subzones the story names often (towns, flight points, inns, cemeteries,
	-- harbors take "at"; everything else defaults to "in")
	["Goldshire"] = { type = "subzone", at = true }, ["Sentinel Hill"] = { type = "subzone", at = true },
	["Moonbrook"] = { type = "subzone", at = true }, ["Lakeshire"] = { type = "subzone", at = true },
	["Darkshire"] = { type = "subzone", at = true }, ["Raven Hill"] = { type = "subzone", at = true },
	["Raven Hill Cemetery"] = { type = "subzone", at = true }, ["Thelsamar"] = { type = "subzone", at = true },
	["Kharanos"] = { type = "subzone", at = true }, ["Menethil Harbor"] = { type = "subzone", at = true },
	["Southshore"] = { type = "subzone", at = true }, ["Tarren Mill"] = { type = "subzone", at = true },
	["Refuge Pointe"] = { type = "subzone", at = true }, ["Hammerfall"] = { type = "subzone", at = true },
	["Booty Bay"] = { type = "subzone", at = true }, ["Grom'gol Base Camp"] = { type = "subzone", at = true },
	["Kargath"] = { type = "subzone", at = true }, ["Thorium Point"] = { type = "subzone", at = true },
	["Aerie Peak"] = { type = "subzone", at = true }, ["Revantusk Village"] = { type = "subzone", at = true },
	["Stonard"] = { type = "subzone", at = true }, ["Nethergarde Keep"] = { type = "subzone", at = true },
	["Morgan's Vigil"] = { type = "subzone", at = true }, ["Flame Crest"] = { type = "subzone", at = true },
	["Chillwind Camp"] = { type = "subzone", at = true }, ["Light's Hope Chapel"] = { type = "subzone", at = true },
	["Brill"] = { type = "subzone", at = true }, ["The Sepulcher"] = { type = "subzone", at = true },
	["Razor Hill"] = { type = "subzone", at = true }, ["The Crossroads"] = { type = "subzone", at = true },
	["Camp Taurajo"] = { type = "subzone", at = true }, ["Ratchet"] = { type = "subzone", at = true },
	["Bloodhoof Village"] = { type = "subzone", at = true }, ["Sun Rock Retreat"] = { type = "subzone", at = true },
	["Splintertree Post"] = { type = "subzone", at = true }, ["Astranaar"] = { type = "subzone", at = true },
	["Auberdine"] = { type = "subzone", at = true }, ["Dolanaar"] = { type = "subzone", at = true },
	["Stonetalon Peak"] = { type = "subzone", at = true }, ["Nijel's Point"] = { type = "subzone", at = true },
	["Shadowprey Village"] = { type = "subzone", at = true }, ["Theramore Isle"] = { type = "subzone", at = true },
	["Brackenwall Village"] = { type = "subzone", at = true }, ["Feathermoon Stronghold"] = { type = "subzone", at = true },
	["Camp Mojache"] = { type = "subzone", at = true }, ["Freewind Post"] = { type = "subzone", at = true },
	["Gadgetzan"] = { type = "subzone", at = true }, ["Marshal's Refuge"] = { type = "subzone", at = true },
	["Bloodvenom Post"] = { type = "subzone", at = true }, ["Talonbranch Glade"] = { type = "subzone", at = true },
	["Everlook"] = { type = "subzone", at = true }, ["Cenarion Hold"] = { type = "subzone", at = true },
	["Valormok"] = { type = "subzone", at = true }, ["Talrendis Point"] = { type = "subzone", at = true },
	["Thalanaar"] = { type = "subzone", at = true }, ["Nighthaven"] = { type = "subzone", at = true },
	["Stonesplinter Valley"] = { type = "subzone" }, ["Kurzen's Compound"] = { type = "subzone" }, ["Dreadmaul Rock"] = { type = "subzone", at = true }, ["Ironclad Cove"] = { type = "subzone" },
	["The Great Forge"] = { type = "subzone" }, ["Trade District"] = { type = "subzone", the = true },
	["Valley of Strength"] = { type = "subzone", the = true }, ["Valley of Trials"] = { type = "subzone", the = true },
	["Northshire Valley"] = { type = "subzone" }, ["Coldridge Valley"] = { type = "subzone" },
	["Shadowglen"] = { type = "subzone" }, ["Camp Narache"] = { type = "subzone", at = true },
	["Deathknell"] = { type = "subzone", at = true }, ["The Merchant Coast"] = { type = "subzone" },
}

-- Factions that English prose writes with "the" (the game string has none).
-- A faction string that starts with "The " uses the game rule.
W.factions = {
	["Alliance"] = { the = true }, ["Horde"] = { the = true },
	["Gnomeregan Exiles"] = { the = true, plural = true }, ["Darkspear Trolls"] = { the = true, plural = true },
	["Argent Dawn"] = { the = true }, ["Thorium Brotherhood"] = { the = true }, ["Cenarion Circle"] = { the = true },
	["Hydraxian Waterlords"] = { the = true, plural = true }, ["Brood of Nozdormu"] = { the = true },
	["Zandalar Tribe"] = { the = true }, ["Bloodsail Buccaneers"] = { the = true, plural = true },
	["Steamwheedle Cartel"] = { the = true }, ["Wintersaber Trainers"] = { the = true, plural = true },
	["Frostwolf Clan"] = { the = true }, ["Stormpike Guard"] = { the = true },
	["Silverwing Sentinels"] = { the = true, plural = true }, ["Warsong Outriders"] = { the = true, plural = true },
	["League of Arathor"] = { the = true }, ["Shen'dralar"] = { the = true }, ["Syndicate"] = { the = true },
	["Wildhammer Clan"] = { the = true }, ["Darkmoon Faire"] = { the = true },
	["Gelkis Clan Centaur"] = { the = true }, ["Magram Clan Centaur"] = { the = true },
	["Undercity"] = { the = true }, ["The Defilers"] = { plural = true },
	["Stormwind"] = {}, ["Ironforge"] = {}, ["Darnassus"] = {}, ["Orgrimmar"] = {}, ["Thunder Bluff"] = {},
	["Timbermaw Hold"] = {}, ["Booty Bay"] = {}, ["Gadgetzan"] = {}, ["Ratchet"] = {}, ["Everlook"] = {}, ["Ravenholdt"] = {},
}

-- Encounters whose name is plural ("The Four Horsemen fell").
W.npcs = {
	["The Four Horsemen"] = { plural = true }, ["Twin Emperors"] = { the = true, plural = true },
	["Silithid Royalty"] = { plural = true }, ["The Seven"] = { plural = true },
}

-- Ports: the subzone a crossing between continents leaves from.
W.ports = {
	["Menethil Harbor"] = { vehicle = "ship", faction = "Alliance" },
	["Auberdine"] = { vehicle = "ship", faction = "Alliance" },
	["Theramore Isle"] = { vehicle = "ship", faction = "Alliance" },
	["Grom'gol Base Camp"] = { vehicle = "zeppelin", faction = "Horde" },
	["Booty Bay"] = { vehicle = "boat" },
	["Ratchet"] = { vehicle = "boat" },
}

-- A race's starting zone, used only to allow the "Home ground" title when the
-- first era's main zone is that zone (never to guess where a road began).
W.starts = {
	Human = "Elwynn Forest", Dwarf = "Dun Morogh", Gnome = "Dun Morogh", ["Night Elf"] = "Teldrassil",
	Orc = "Durotar", Troll = "Durotar", Tauren = "Mulgore", Undead = "Tirisfal Glades",
}

-- Grammar rule data (Story/Grammar.lua).
W.pluralHeads = {
	"Barrens", "Caverns", "Deeps", "Downs", "Fields", "Flats", "Foothills", "Halls", "Highlands", "Isles",
	"Lands", "Mountains", "Plaguelands", "Ruins", "Steppes", "Wastes", "Wetlands", "Hinterlands", "Deadmines",
}
W.ofHeads = { "Temple", "Ruins", "Halls", "Vault", "Swamp", "Isle", "Cave", "Tomb" }
W.atHeads = {
	"Cemetery", "Graveyard", "Inn", "Harbor", "Post", "Camp", "Village", "Outpost", "Point", "Refuge",
	"Landing", "Lodge", "Stead", "Farm", "Farmstead", "Retreat", "Pointe", "Chapel", "Vigil",
}
W.silentH = { "hour", "hours", "hourly", "honor", "honors", "honored", "honorable", "honest", "honestly", "heir", "heirs", "heirloom", "herb", "herbs", "herbal" }
W.abbreviations = { "Mr.", "Mrs.", "Ms.", "Co.", "Dr.", "St." }

-- Folded lookup sets ---------------------------------------------------------
local function Fold(text)
	text = tostring(text or ""):lower():gsub("'", ""):gsub("[%p%s]+", " ")
	return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end
W.Fold = Fold

W.the, W.bare, W.plural, W.at, W.short, W.known, W.byFold = {}, {}, {}, {}, {}, {}, {}
for name, row in pairs(W.places) do
	local key = Fold(name)
	W.known[key] = true
	W.byFold[key] = row
	row.name = name
	if row.the then W.the[key] = true end
	if row.bare then W.bare[key] = true end
	if row.plural then W.plural[key] = true end
	if row.at then W.at[key] = true end
	if row.short then W.short[key] = row.short end
	if name:find("^The ") then
		-- "The Barrens" is also known by its core ("Barrens").
		W.known[Fold(name:sub(5))] = true
	end
end
W.factionThe, W.factionPlural = {}, {}
for name, row in pairs(W.factions) do
	local key = Fold(name)
	W.known[key] = true
	if row.the then W.factionThe[key] = true end
	if row.plural then W.factionPlural[key] = true; W.plural[key] = true end
end
for name, row in pairs(W.npcs) do
	local key = Fold(name)
	if row.plural then W.plural[key] = true end
	if row.the then W.the[key] = true end
end
W.silentHSet = {}
for _, word in ipairs(W.silentH) do W.silentHSet[word] = true end
