-- EldoUI Flight Games: the question bank of the WoW trivia game.
--
-- Every question is about the original game as WoW: Forever plays it:
-- nothing from a later expansion. The questions are written from scratch
-- for EldoUI from public game knowledge; no question or answer text is
-- taken from another addon or a wiki. Each set names where its facts
-- were checked (`source`). Every question has
-- four different answers of which exactly one is right.
--
-- Kinds of sets:
--   ask    facts = { { subject, answer }, ... }: "In which zone is the
--          entrance to <subject>?" The wrong answers come from `pool` (the
--          set's own answers when there is no pool), never one that is also
--          right for that subject. `near` picks numbers close to the answer.
--   which  groups = { { ask, members, against } }: "Which of these races
--          can play a Druid?" One question per member; the wrong answers
--          come from `against`.
--   fixed  list = { { question, right, wrong, wrong, wrong } }.
--
-- Answers that are game names (zones, spells, bosses, races, classes)
-- stay as the client shows them; answers written as S(Key("...")) are
-- EldoUI's own words and are translated.
local _, E = ...
local M = E.FlightGames
local Key = E.Key

local D = { sets = {}, say = {} }
M.TriviaData = D

-- An answer in EldoUI's own words: translated where it is shown.
local function S(text)
	D.say[text] = true
	return text
end

local function Add(set) D.sets[#D.sets + 1] = set end

local function Copy(list)
	local out = {}
	for i, v in ipairs(list) do out[i] = v end
	return out
end

local function Join(...)
	local out = {}
	for _, list in ipairs({ ... }) do
		for _, v in ipairs(list) do out[#out + 1] = v end
	end
	return out
end

---------------------------------------------------------------------------
-- Shared lists
---------------------------------------------------------------------------
local EK = {
	"Elwynn Forest", "Dun Morogh", "Tirisfal Glades", "Westfall", "Loch Modan", "Silverpine Forest",
	"Redridge Mountains", "Duskwood", "Wetlands", "Hillsbrad Foothills", "Alterac Mountains",
	"Arathi Highlands", "Stranglethorn Vale", "Badlands", "Swamp of Sorrows", "The Hinterlands",
	"Searing Gorge", "Blasted Lands", "Burning Steppes", "Western Plaguelands", "Eastern Plaguelands",
	"Deadwind Pass", "Stormwind City", "Ironforge", "Undercity",
}
local KALIMDOR = {
	"Durotar", "Mulgore", "Teldrassil", "Darkshore", "The Barrens", "Stonetalon Mountains", "Ashenvale",
	"Thousand Needles", "Desolace", "Dustwallow Marsh", "Feralas", "Tanaris", "Azshara", "Felwood",
	"Un'Goro Crater", "Winterspring", "Silithus", "Moonglade", "Orgrimmar", "Thunder Bluff", "Darnassus",
}
local ZONES = Join(EK, KALIMDOR)
local CAPITALS = { "Stormwind City", "Ironforge", "Darnassus", "Orgrimmar", "Thunder Bluff", "Undercity" }
local CLASSES = { "Warrior", "Paladin", "Hunter", "Rogue", "Priest", "Shaman", "Mage", "Warlock", "Druid" }
local RACES = { "Human", "Dwarf", "Gnome", "Night Elf", "Orc", "Troll", "Tauren", "Undead" }
local ALLIANCE_RACES = { "Human", "Dwarf", "Gnome", "Night Elf" }
local HORDE_RACES = { "Orc", "Troll", "Tauren", "Undead" }

---------------------------------------------------------------------------
-- Places
---------------------------------------------------------------------------
Add({
	key = "entrance", kind = "ask", category = Key("Dungeons and raids"),
	source = "EldoUI zone data (Data/Zones.lua, instances per zone); warcraft.wiki.gg instance pages",
	ask = Key("In which zone is the entrance to %s?"), pool = ZONES,
	facts = {
		{ "Ragefire Chasm", "Orgrimmar", { "Durotar" } }, { "Wailing Caverns", "The Barrens" }, { "The Deadmines", "Westfall" },
		{ "Shadowfang Keep", "Silverpine Forest" }, { "Blackfathom Deeps", "Ashenvale" }, { "The Stockade", "Stormwind City", { "Elwynn Forest" } },
		{ "Gnomeregan", "Dun Morogh" }, { "Razorfen Kraul", "The Barrens" }, { "Scarlet Monastery", "Tirisfal Glades" },
		{ "Razorfen Downs", "The Barrens" }, { "Uldaman", "Badlands" }, { "Zul'Farrak", "Tanaris" },
		{ "Maraudon", "Desolace" }, { "Sunken Temple", "Swamp of Sorrows" }, { "Dire Maul", "Feralas" },
		{ "Scholomance", "Western Plaguelands" }, { "Stratholme", "Eastern Plaguelands" },
		{ "Onyxia's Lair", "Dustwallow Marsh" }, { "Zul'Gurub", "Stranglethorn Vale" },
		{ "Ruins of Ahn'Qiraj", "Silithus" }, { "Temple of Ahn'Qiraj", "Silithus" },
		{ "Naxxramas", "Eastern Plaguelands" },
	},
})

local DUNGEONS = {
	"Ragefire Chasm", "Wailing Caverns", "The Deadmines", "Shadowfang Keep", "Blackfathom Deeps", "The Stockade",
	"Gnomeregan", "Razorfen Kraul", "Scarlet Monastery", "Razorfen Downs", "Uldaman", "Zul'Farrak", "Maraudon",
	"Sunken Temple", "Blackrock Depths", "Dire Maul", "Scholomance", "Stratholme",
}
local RAIDS = {
	"Molten Core", "Onyxia's Lair", "Blackwing Lair", "Zul'Gurub", "Ruins of Ahn'Qiraj", "Temple of Ahn'Qiraj", "Naxxramas",
}
Add({
	key = "raid", kind = "which", category = Key("Dungeons and raids"),
	source = "EldoUI zone data (Data/Zones.lua, kind of each instance)",
	groups = {
		{ ask = Key("Which of these is a raid?"), members = RAIDS, against = DUNGEONS },
		{ ask = Key("Which of these is a dungeon, not a raid?"), members = DUNGEONS, against = RAIDS },
	},
})

local TOWNS = {
	["Elwynn Forest"] = { "Northshire Abbey", "Goldshire", "Eastvale Logging Camp" },
	["Dun Morogh"] = { "Coldridge Valley", "Kharanos", "Anvilmar", "Gol'Bolar Quarry" },
	["Tirisfal Glades"] = { "Deathknell", "Brill" },
	["Durotar"] = { "Valley of Trials", "Razor Hill", "Sen'jin Village", "Tiragarde Keep" },
	["Mulgore"] = { "Camp Narache", "Bloodhoof Village", "Red Rocks" },
	["Teldrassil"] = { "Shadowglen", "Dolanaar", "Rut'theran Village", "Starbreeze Village" },
	["Westfall"] = { "Sentinel Hill", "Moonbrook", "Jangolode Mine", "Saldean's Farm" },
	["Loch Modan"] = { "Thelsamar", "Stonewrought Dam", "Algaz Station" },
	["Silverpine Forest"] = { "The Sepulcher", "Pyrewood Village", "Ambermill" },
	["Redridge Mountains"] = { "Lakeshire", "Stonewatch Keep" },
	["Duskwood"] = { "Darkshire", "Raven Hill" },
	["Wetlands"] = { "Menethil Harbor", "Dun Modr", "Grim Batol" },
	["Hillsbrad Foothills"] = { "Southshore", "Tarren Mill", "Durnholde Keep" },
	["Alterac Mountains"] = { "Strahnbrad", "Ruins of Alterac" },
	["Arathi Highlands"] = { "Refuge Pointe", "Hammerfall", "Stromgarde Keep" },
	["Stranglethorn Vale"] = { "Booty Bay", "Grom'gol Base Camp", "Rebel Camp", "Nesingwary's Expedition", "Kurzen's Compound", "Gurubashi Arena" },
	["Badlands"] = { "Kargath" },
	["Swamp of Sorrows"] = { "Stonard" },
	["The Hinterlands"] = { "Aerie Peak", "Revantusk Village", "Jintha'Alor", "Quel'Danil Lodge" },
	["Searing Gorge"] = { "Thorium Point", "The Cauldron" },
	["Burning Steppes"] = { "Morgan's Vigil", "Flame Crest", "Dreadmaul Rock" },
	["Blasted Lands"] = { "Nethergarde Keep", "The Dark Portal" },
	["Deadwind Pass"] = { "Karazhan" },
	["Western Plaguelands"] = { "Chillwind Camp", "Caer Darrow", "Andorhal", "Hearthglen" },
	["Eastern Plaguelands"] = { "Light's Hope Chapel", "Tyr's Hand", "Corin's Crossing", "Darrowshire" },
	["Darkshore"] = { "Auberdine" },
	["The Barrens"] = { "The Crossroads", "Camp Taurajo", "Ratchet", "Lushwater Oasis", "Mor'shan Rampart", "Bael Modan" },
	["Ashenvale"] = { "Astranaar", "Splintertree Post", "Zoram'gar Outpost", "Forest Song", "Maestra's Post" },
	["Stonetalon Mountains"] = { "Sun Rock Retreat", "Stonetalon Peak" },
	["Thousand Needles"] = { "Freewind Post", "The Shimmering Flats", "Whitereach Post" },
	["Desolace"] = { "Nijel's Point", "Shadowprey Village", "Ghost Walker Post", "Thunder Axe Fortress", "Kodo Graveyard" },
	["Dustwallow Marsh"] = { "Theramore Isle", "Brackenwall Village" },
	["Feralas"] = { "Feathermoon Stronghold", "Camp Mojache", "Thalanaar" },
	["Tanaris"] = { "Gadgetzan", "Steamwheedle Port", "Lost Rigger Cove" },
	["Azshara"] = { "Talrendis Point", "Valormok", "Ruins of Eldarath" },
	["Felwood"] = { "Bloodvenom Post", "Talonbranch Glade", "Jaedenar", "Irontree Woods" },
	["Un'Goro Crater"] = { "Marshal's Refuge", "Fire Plume Ridge" },
	["Winterspring"] = { "Everlook", "Starfall Village", "Frostsaber Rock" },
	["Silithus"] = { "Cenarion Hold", "Hive'Zora" },
	["Moonglade"] = { "Nighthaven" },
}
do
	local facts, pool = {}, {}
	for zone in pairs(TOWNS) do pool[#pool + 1] = zone end
	table.sort(pool)
	for _, zone in ipairs(pool) do
		for _, place in ipairs(TOWNS[zone]) do facts[#facts + 1] = { place, zone } end
	end
	Add({
		key = "town", kind = "ask", category = Key("Zones and towns"),
		source = "EldoUI story world and transport data (Data/StoryWorld.lua, Data/Transport.lua); warcraft.wiki.gg zone pages (original game)",
		ask = Key("In which zone is %s?"), pool = pool, facts = facts,
	})
end

local DISTRICTS = {
	["Stormwind City"] = { "Trade District", "Cathedral Square", "Mage Quarter", "Old Town", "Dwarven District", "Valley of Heroes", "Stormwind Keep" },
	["Ironforge"] = { "The Great Forge", "The Commons", "Military Ward", "Mystic Ward", "Hall of Explorers", "Tinker Town" },
	["Orgrimmar"] = { "Valley of Strength", "Valley of Spirits", "Valley of Honor", "Valley of Wisdom", "The Drag", "Cleft of Shadow" },
	["Thunder Bluff"] = { "Elder Rise", "Spirit Rise", "Hunter Rise" },
	["Undercity"] = { "Trade Quarter", "Magic Quarter", "War Quarter", "Rogues' Quarter", "The Apothecarium", "Royal Quarter" },
	["Darnassus"] = { "Temple of the Moon", "Cenarion Enclave", "Craftsmen's Terrace", "Warrior's Terrace", "Tradesmen's Terrace" },
}
do
	local facts = {}
	for _, city in ipairs(CAPITALS) do
		for _, place in ipairs(DISTRICTS[city]) do facts[#facts + 1] = { place, city } end
	end
	Add({
		key = "district", kind = "ask", category = Key("Capital cities"),
		source = "warcraft.wiki.gg capital city pages (original game)",
		ask = Key("%s: in which capital city is it?"), pool = CAPITALS, facts = facts,
	})
end

Add({
	key = "inn", kind = "ask", category = Key("Zones and towns"),
	source = "warcraft.wiki.gg inn pages (original game)",
	ask = Key("Where is the %s?"),
	pool = { "Goldshire", "Darkshire", "Thelsamar", "Stormwind City", "Brill", "Menethil Harbor", "Booty Bay", "Kharanos", "Lakeshire", "Southshore" },
	facts = {
		{ "Lion's Pride Inn", "Goldshire" }, { "Scarlet Raven Tavern", "Darkshire" }, { "Stoutlager Inn", "Thelsamar" },
		{ "Pig and Whistle Tavern", "Stormwind City" }, { "Gallows' End Tavern", "Brill" }, { "Deepwater Tavern", "Menethil Harbor" },
		{ "Salty Sailor Tavern", "Booty Bay" }, { "Thunderbrew Distillery", "Kharanos" },
	},
})

do
	local groups = {
		{ ask = Key("Which of these lies in Kalimdor?"), members = KALIMDOR, against = EK },
		{ ask = Key("Which of these lies in the Eastern Kingdoms?"), members = EK, against = KALIMDOR },
	}
	Add({
		key = "continent", kind = "which", category = Key("Zones and towns"),
		source = "EldoUI story world (Data/StoryWorld.lua, continent of each place)",
		groups = groups,
	})
end

Add({
	key = "territory", kind = "which", category = Key("Zones and towns"),
	source = "EldoUI zone data (Data/Zones.lua, faction of each zone)",
	groups = {
		{ ask = Key("Which of these zones is Horde territory?"),
			members = { "Tirisfal Glades", "Silverpine Forest", "Durotar", "Mulgore", "The Barrens" },
			against = { "Elwynn Forest", "Dun Morogh", "Westfall", "Loch Modan", "Teldrassil", "Darkshore" } },
		{ ask = Key("Which of these zones is Alliance territory?"),
			members = { "Elwynn Forest", "Dun Morogh", "Westfall", "Loch Modan", "Teldrassil", "Darkshore" },
			against = { "Tirisfal Glades", "Silverpine Forest", "Durotar", "Mulgore", "The Barrens" } },
	},
})

Add({
	key = "npc", kind = "ask", category = Key("People of Azeroth"),
	source = "warcraft.wiki.gg character pages (original game locations)",
	ask = Key("Where can you find %s?"),
	pool = Join(CAPITALS, { "Theramore Isle", "Dustwallow Marsh", "Stranglethorn Vale", "The Barrens", "Moonglade" }),
	facts = {
		{ "Highlord Bolvar Fordragon", "Stormwind City" }, { "Lady Katrana Prestor", "Stormwind City" },
		{ "Archbishop Benedictus", "Stormwind City" }, { "King Magni Bronzebeard", "Ironforge" },
		{ "High Tinker Mekkatorque", "Ironforge" }, { "Thrall", "Orgrimmar" }, { "Vol'jin", "Orgrimmar" },
		{ "Cairne Bloodhoof", "Thunder Bluff" }, { "Magatha Grimtotem", "Thunder Bluff" },
		{ "Lady Sylvanas Windrunner", "Undercity" }, { "Varimathras", "Undercity" },
		{ "Tyrande Whisperwind", "Darnassus" }, { "Fandral Staghelm", "Darnassus" },
		{ "Jaina Proudmoore", "Theramore Isle", { "Dustwallow Marsh" } }, { "Nat Pagle", "Dustwallow Marsh", { "Theramore Isle" } },
		{ "Hemet Nesingwary", "Stranglethorn Vale" }, { "Mankrik", "The Barrens" }, { "Keeper Remulos", "Moonglade" },
	},
})

---------------------------------------------------------------------------
-- Bosses
---------------------------------------------------------------------------
local BOSSES = {
	{ "Ragefire Chasm", { "Oggleflint", "Taragaman the Hungerer", "Jergosh the Invoker", "Bazzalan" } },
	{ "Wailing Caverns", { "Lady Anacondra", "Lord Cobrahn", "Kresh", "Lord Pythas", "Skum", "Lord Serpentis", "Verdan the Everliving", "Mutanus the Devourer" } },
	{ "The Deadmines", { "Rhahk'Zor", "Sneed", "Gilnid", "Mr. Smite", "Captain Greenskin", "Edwin VanCleef" } },
	{ "Shadowfang Keep", { "Rethilgore", "Razorclaw the Butcher", "Baron Silverlaine", "Commander Springvale", "Odo the Blindwatcher", "Fenrus the Devourer", "Wolf Master Nandos", "Archmage Arugal" } },
	{ "Blackfathom Deeps", { "Ghamoo-ra", "Lady Sarevess", "Gelihast", "Lorgus Jett", "Baron Aquanis", "Twilight Lord Kelris", "Old Serra'kis", "Aku'mai" } },
	{ "The Stockade", { "Targorr the Dread", "Kam Deepfury", "Hamhock", "Bazil Thredd", "Dextren Ward" } },
	{ "Gnomeregan", { "Grubbis", "Viscous Fallout", "Electrocutioner 6000", "Crowd Pummeler 9-60", "Mekgineer Thermaplugg" } },
	{ "Razorfen Kraul", { "Roogug", "Aggem Thorncurse", "Death Speaker Jargba", "Overlord Ramtusk", "Agathelos the Raging", "Charlga Razorflank" } },
	{ "Scarlet Monastery", { "Interrogator Vishas", "Bloodmage Thalnos", "Houndmaster Loksey", "Arcanist Doan", "Herod", "High Inquisitor Fairbanks", "Scarlet Commander Mograine", "High Inquisitor Whitemane" } },
	{ "Razorfen Downs", { "Tuten'kash", "Mordresh Fire Eye", "Glutton", "Amnennar the Coldbringer" } },
	{ "Uldaman", { "Revelosh", "Baelog", "Ironaya", "Obsidian Sentinel", "Ancient Stone Keeper", "Galgann Firehammer", "Grimlok", "Archaedas" } },
	{ "Zul'Farrak", { "Antu'sul", "Theka the Martyr", "Witch Doctor Zum'rah", "Nekrum Gutchewer", "Shadowpriest Sezz'ziz", "Sergeant Bly", "Hydromancer Velratha", "Ruuzlu", "Chief Ukorz Sandscalp", "Gahz'rilla" } },
	{ "Maraudon", { "Noxxion", "Razorlash", "Lord Vyletongue", "Celebras the Cursed", "Landslide", "Tinkerer Gizlock", "Rotgrip", "Princess Theradras" } },
	{ "Sunken Temple", { "Atal'alarion", "Jammal'an the Prophet", "Ogom the Wretched", "Dreamscythe", "Weaver", "Hazzas", "Morphaz", "Shade of Eranikus", "Avatar of Hakkar" } },
	{ "Blackrock Depths", { "Lord Roccor", "High Interrogator Gerstahn", "Houndmaster Grebmar", "Bael'Gar", "Lord Incendius", "Fineous Darkvire", "General Angerforge", "Golem Lord Argelmach", "Hurley Blackbreath", "Phalanx", "Plugger Spazzring", "Ambassador Flamelash", "Magmus", "Pyromancer Loregrain", "Warder Stilgiss", "Emperor Dagran Thaurissan" } },
	{ "Blackrock Spire", { "Highlord Omokk", "Shadow Hunter Vosh'gajin", "War Master Voone", "Mother Smolderweb", "Urok Doomhowl", "Quartermaster Zigris", "Halycon", "Gizrul the Slavener", "Overlord Wyrmthalak", "Pyroguard Emberseer", "Solakar Flamewreath", "Warchief Rend Blackhand", "Gyth", "The Beast", "General Drakkisath" } },
	{ "Dire Maul", { "Zevrim Thornhoof", "Hydrospawn", "Lethtendris", "Alzzin the Wildshaper", "Tendris Warpwood", "Illyanna Ravenoak", "Magister Kalendris", "Immol'thar", "Prince Tortheldrin", "Guard Mol'dar", "Stomper Kreeg", "Guard Fengus", "Guard Slip'kik", "Captain Kromcrush", "Cho'Rush the Observer", "King Gordok" } },
	{ "Scholomance", { "Kirtonos the Herald", "Jandice Barov", "Rattlegore", "Marduk Blackpool", "Vectus", "Ras Frostwhisper", "Instructor Malicia", "Doctor Theolen Krastinov", "Lorekeeper Polkelt", "The Ravenian", "Lord Alexei Barov", "Lady Illucia Barov", "Darkmaster Gandling" } },
	{ "Stratholme", { "Timmy the Cruel", "Archivist Galford", "Hearthsinger Forresten", "The Unforgiven", "Cannon Master Willey", "Malor the Zealous", "Balnazzar", "Magistrate Barthilas", "Nerub'enkan", "Baroness Anastari", "Maleki the Pallid", "Ramstein the Gorger", "Baron Rivendare" } },
	{ "Molten Core", { "Lucifron", "Magmadar", "Gehennas", "Garr", "Shazzrah", "Baron Geddon", "Sulfuron Harbinger", "Golemagg the Incinerator", "Majordomo Executus", "Ragnaros" } },
	{ "Onyxia's Lair", { "Onyxia" } },
	{ "Blackwing Lair", { "Razorgore the Untamed", "Vaelastrasz the Corrupt", "Broodlord Lashlayer", "Firemaw", "Ebonroc", "Flamegor", "Chromaggus", "Nefarian" } },
	{ "Zul'Gurub", { "High Priestess Jeklik", "High Priest Venoxis", "High Priestess Mar'li", "High Priest Thekal", "High Priestess Arlokk", "Bloodlord Mandokir", "Jin'do the Hexxer", "Gahz'ranka", "Hakkar" } },
	{ "Ruins of Ahn'Qiraj", { "Kurinnaxx", "General Rajaxx", "Moam", "Buru the Gorger", "Ayamiss the Hunter", "Ossirian the Unscarred" } },
	{ "Temple of Ahn'Qiraj", { "The Prophet Skeram", "Battleguard Sartura", "Fankriss the Unyielding", "Princess Huhuran", "Viscidus", "Ouro", "The Twin Emperors", "C'Thun" } },
	{ "Naxxramas", { "Anub'Rekhan", "Grand Widow Faerlina", "Maexxna", "Noth the Plaguebringer", "Heigan the Unclean", "Loatheb", "Instructor Razuvious", "Gothik the Harvester", "The Four Horsemen", "Patchwerk", "Grobbulus", "Gluth", "Thaddius", "Sapphiron", "Kel'Thuzad" } },
}
do
	local facts, pool = {}, {}
	for _, row in ipairs(BOSSES) do
		pool[#pool + 1] = row[1]
		for _, boss in ipairs(row[2]) do facts[#facts + 1] = { boss, row[1] } end
	end
	Add({
		key = "boss", kind = "ask", category = Key("Bosses"),
		source = "warcraft.wiki.gg dungeon and raid pages, encounters of the original game; wowhead.com classic NPC database",
		ask = Key("In which dungeon or raid do you face %s?"), pool = pool, facts = facts,
	})
end

---------------------------------------------------------------------------
-- Classes
---------------------------------------------------------------------------
-- Abilities only one class learns (no pet ability or racial trait of the
-- same name).
local SPELLS = {
	Warrior = {
		"Intercept", "Mortal Strike", "Bloodthirst", "Shield Wall", "Recklessness", "Retaliation", "Sunder Armor",
		"Thunder Clap", "Overpower", "Execute", "Whirlwind", "Taunt", "Shield Slam", "Berserker Rage",
		"Intimidating Shout", "Pummel", "Heroic Strike", "Cleave", "Hamstring", "Rend", "Revenge", "Last Stand",
		"Sweeping Strikes", "Death Wish", "Piercing Howl", "Shield Bash", "Mocking Blow", "Challenging Shout",
		"Disarm", "Slam", "Bloodrage", "Battle Shout", "Shield Block", "Concussion Blow", "Berserker Stance",
		"Defensive Stance", "Demoralizing Shout",
	},
	Paladin = {
		"Divine Shield", "Divine Protection", "Blessing of Protection", "Lay on Hands", "Hammer of Justice",
		"Consecration", "Holy Light", "Flash of Light", "Seal of Righteousness", "Seal of the Crusader",
		"Seal of Command", "Seal of Light", "Seal of Wisdom", "Seal of Justice", "Judgement", "Blessing of Kings",
		"Blessing of Might", "Blessing of Wisdom", "Blessing of Freedom", "Blessing of Sacrifice",
		"Devotion Aura", "Retribution Aura",
		"Concentration Aura", "Sanctity Aura", "Exorcism", "Hammer of Wrath", "Holy Wrath", "Holy Shock",
		"Holy Shield", "Repentance", "Turn Undead", "Divine Intervention", "Redemption", "Cleanse", "Purify",
		"Divine Favor", "Righteous Fury", "Sense Undead", "Summon Warhorse", "Summon Charger",
	},
	Hunter = {
		"Aimed Shot", "Multi-Shot", "Arcane Shot", "Serpent Sting", "Viper Sting", "Scorpid Sting", "Hunter's Mark",
		"Feign Death", "Freezing Trap", "Frost Trap", "Immolation Trap", "Explosive Trap", "Aspect of the Hawk",
		"Aspect of the Monkey", "Aspect of the Cheetah", "Aspect of the Pack", "Aspect of the Wild",
		"Aspect of the Beast", "Tame Beast", "Call Pet", "Dismiss Pet", "Revive Pet", "Mend Pet", "Feed Pet",
		"Bestial Wrath", "Intimidation", "Scatter Shot", "Tranquilizing Shot", "Volley",
		"Rapid Fire", "Concussive Shot", "Distracting Shot", "Eyes of the Beast", "Eagle Eye", "Disengage",
		"Wing Clip", "Raptor Strike", "Mongoose Bite", "Counterattack", "Deterrence", "Trueshot Aura", "Flare",
		"Scare Beast", "Beast Lore", "Track Beasts", "Track Undead", "Track Demons", "Track Dragonkin",
		"Track Giants", "Track Elementals", "Track Hidden",
	},
	Rogue = {
		"Sinister Strike", "Backstab", "Eviscerate", "Slice and Dice", "Kidney Shot", "Cheap Shot", "Sap",
		"Gouge", "Blind", "Vanish", "Sprint", "Evasion", "Stealth", "Kick", "Ambush", "Garrote", "Rupture",
		"Expose Armor", "Pick Pocket", "Pick Lock", "Distract", "Feint", "Adrenaline Rush", "Blade Flurry",
		"Cold Blood", "Preparation", "Premeditation", "Ghostly Strike", "Hemorrhage", "Riposte", "Detect Traps",
		"Disarm Trap", "Crippling Poison", "Instant Poison", "Deadly Poison", "Mind-numbing Poison", "Wound Poison",
	},
	Priest = {
		"Power Word: Shield", "Power Word: Fortitude", "Prayer of Fortitude", "Renew", "Flash Heal", "Greater Heal",
		"Lesser Heal", "Prayer of Healing", "Psychic Scream", "Mind Blast", "Mind Flay", "Shadow Word: Pain",
		"Vampiric Embrace", "Shadowform", "Silence", "Mind Control", "Fade", "Levitate", "Resurrection",
		"Holy Nova", "Inner Fire", "Divine Spirit", "Power Infusion", "Lightwell", "Spirit of Redemption",
		"Dispel Magic", "Abolish Disease", "Mana Burn", "Shackle Undead", "Mind Soothe", "Mind Vision",
		"Inner Focus", "Smite", "Holy Fire", "Shadow Protection",
	},
	Shaman = {
		"Lightning Bolt", "Chain Lightning", "Earth Shock", "Flame Shock", "Frost Shock", "Healing Wave",
		"Lesser Healing Wave", "Chain Heal", "Ghost Wolf", "Reincarnation", "Ancestral Spirit", "Windfury Weapon",
		"Rockbiter Weapon", "Flametongue Weapon", "Frostbrand Weapon", "Lightning Shield", "Purge", "Stormstrike",
		"Lightning Mastery", "Water Walking", "Water Breathing", "Astral Recall", "Far Sight", "Mana Tide Totem",
		"Windfury Totem", "Tremor Totem", "Searing Totem", "Healing Stream Totem",
	},
	Mage = {
		"Fireball", "Frostbolt", "Arcane Missiles", "Arcane Explosion", "Blizzard", "Flamestrike", "Pyroblast",
		"Fire Blast", "Frost Nova", "Cone of Cold", "Ice Block", "Ice Barrier", "Polymorph", "Counterspell", "Blink",
		"Arcane Intellect", "Arcane Brilliance", "Conjure Water", "Conjure Food", "Conjure Mana Agate",
		"Evocation", "Mana Shield", "Ice Armor", "Frost Armor", "Mage Armor", "Slow Fall", "Remove Lesser Curse",
		"Combustion", "Scorch", "Blast Wave", "Presence of Mind", "Arcane Power", "Cold Snap",
		"Teleport: Stormwind", "Teleport: Orgrimmar", "Portal: Ironforge", "Portal: Undercity", "Dampen Magic",
		"Amplify Magic", "Detect Magic", "Fire Ward", "Frost Ward",
	},
	Warlock = {
		"Shadow Bolt", "Corruption", "Bane of Agony", "Bane of Doom", "Curse of Tongues", "Curse of Weakness",
		"Curse of Recklessness", "Curse of the Elements", "Curse of Exhaustion", "Immolate",
		"Rain of Fire", "Hellfire", "Searing Pain", "Soul Fire", "Drain Life", "Drain Mana", "Drain Soul",
		"Life Tap", "Death Coil", "Howl of Terror", "Fear", "Banish", "Subjugate Demon", "Summon Imp",
		"Summon Voidwalker", "Summon Succubus", "Summon Felhunter", "Summon Felsteed", "Summon Dreadsteed",
		"Inferno", "Ritual of Doom", "Ritual of Summoning", "Create Healthstone", "Create Soulstone",
		"Create Spellstone", "Create Firestone", "Demon Armor", "Demon Skin", "Shadow Ward", "Eye of Kilrogg",
		"Unending Breath", "Detect Invisibility", "Siphon Life", "Conflagrate", "Shadowburn",
		"Amplify Curse", "Fel Domination", "Soul Link", "Health Funnel",
	},
	Druid = {
		"Moonfire", "Starfire", "Wrath", "Insect Swarm", "Hurricane", "Entangling Roots", "Faerie Fire",
		"Hibernate", "Healing Touch", "Rejuvenation", "Regrowth", "Tranquility", "Rebirth", "Innervate",
		"Mark of the Wild", "Gift of the Wild", "Thorns", "Barkskin", "Bear Form", "Dire Bear Form", "Cat Form",
		"Aquatic Form", "Travel Form", "Moonkin Form", "Shred", "Rake", "Rip", "Ferocious Bite", "Ravage",
		"Pounce", "Maul", "Swipe", "Bash", "Feral Charge", "Frenzied Regeneration", "Swiftmend",
		"Remove Curse", "Abolish Poison", "Teleport: Moonglade", "Omen of Clarity", "Nature's Grasp",
		"Demoralizing Roar", "Challenging Roar", "Soothe Animal",
	},
}
do
	local facts = {}
	for _, class in ipairs(CLASSES) do
		for _, spell in ipairs(SPELLS[class]) do facts[#facts + 1] = { spell, class } end
	end
	Add({
		key = "spell", kind = "ask", category = Key("Classes"),
		source = "EldoUI class trainer data (Data/Training) and the game's own spell names; warcraft.wiki.gg class ability lists (original game)",
		ask = Key("Which class can learn %s?"), pool = CLASSES, facts = facts,
	})
end

-- Which of the original races can play each class in WoW: Forever.
local CLASS_RACES = {
	Paladin = { "Human", "Dwarf", "Undead" },
	Shaman = { "Dwarf", "Orc", "Troll", "Tauren" },
	Druid = { "Night Elf", "Tauren" },
	Hunter = { "Human", "Dwarf", "Night Elf", "Orc", "Tauren", "Troll" },
	Mage = { "Human", "Gnome", "Orc", "Troll", "Undead" },
	Warlock = { "Human", "Gnome", "Orc", "Troll", "Undead" },
	Priest = { "Human", "Dwarf", "Gnome", "Night Elf", "Troll", "Undead" },
}
do
	local groups = {}
	for _, class in ipairs(CLASSES) do
		local can = CLASS_RACES[class]
		if can then
			local yes = {}
			for _, race in ipairs(can) do yes[race] = true end
			local cannot = {}
			for _, race in ipairs(RACES) do
				if not yes[race] then cannot[#cannot + 1] = race end
			end
			if #cannot >= 3 then
				groups[#groups + 1] = { ask = Key("Which of these races can play a %s?"), arg = class, members = can, against = cannot }
			end
			if #can >= 3 then
				groups[#groups + 1] = { ask = Key("Which of these races cannot play a %s?"), arg = class, members = cannot, against = can }
			end
		end
	end
	Add({
		key = "classrace", kind = "which", category = Key("Classes"),
		source = "Blizzard: Return to Azeroth in World of Warcraft: Forever (race and class combinations)",
		groups = groups,
	})
end

Add({
	key = "classtrait", kind = "which", category = Key("Classes"),
	source = "warcraft.wiki.gg class pages: armor, shields, pets and abilities of the original game",
	groups = {
		{ ask = Key("Which of these classes can learn to wear plate armor?"), members = { "Warrior", "Paladin" },
			against = { "Mage", "Priest", "Warlock", "Rogue", "Druid", "Hunter", "Shaman" } },
		{ ask = Key("Which of these classes can learn to wear mail armor?"), members = { "Warrior", "Paladin", "Hunter", "Shaman" },
			against = { "Mage", "Priest", "Warlock", "Rogue", "Druid" } },
		{ ask = Key("Which of these classes wears only cloth armor?"), members = { "Mage", "Priest", "Warlock" },
			against = { "Warrior", "Paladin", "Hunter", "Shaman", "Rogue", "Druid" } },
		{ ask = Key("Which of these classes can carry a shield?"), members = { "Warrior", "Paladin", "Shaman" },
			against = { "Mage", "Priest", "Warlock", "Rogue", "Druid", "Hunter" } },
		{ ask = Key("Which of these classes fights with a pet of its own?"), members = { "Hunter", "Warlock" },
			against = { "Warrior", "Paladin", "Rogue", "Priest", "Shaman", "Mage", "Druid" } },
		{ ask = Key("Which of these classes can move unseen in stealth?"), members = { "Rogue", "Druid" },
			against = { "Warrior", "Paladin", "Hunter", "Priest", "Shaman", "Mage", "Warlock" } },
		{ ask = Key("Which of these classes can bring a dead player back to life?"), members = { "Priest", "Paladin", "Shaman", "Druid" },
			against = { "Warrior", "Rogue", "Mage", "Hunter" } },
		{ ask = Key("Which of these classes can fight with a weapon in each hand?"), members = { "Warrior", "Rogue", "Hunter" },
			against = { "Mage", "Priest", "Warlock", "Paladin", "Druid", "Shaman" } },
		{ ask = Key("Which of these classes can take the shape of a bear?"), members = { "Druid" },
			against = { "Warrior", "Paladin", "Hunter", "Rogue", "Shaman", "Warlock" } },
	},
})

Add({
	key = "totem", kind = "ask", category = Key("Classes"),
	source = "EldoUI shaman data (Data/ShamanTotems.lua), checked against the client's spell data",
	ask = Key("To which element does the %s belong?"),
	pool = { S(Key("Earth")), S(Key("Fire")), S(Key("Water")), S(Key("Air")) },
	facts = {
		{ "Strength of Earth Totem", "Earth" }, { "Stoneskin Totem", "Earth" }, { "Tremor Totem", "Earth" },
		{ "Earthbind Totem", "Earth" }, { "Stoneclaw Totem", "Earth" },
		{ "Searing Totem", "Fire" }, { "Magma Totem", "Fire" }, { "Fire Nova Totem", "Fire" },
		{ "Flametongue Totem", "Fire" }, { "Frost Resistance Totem", "Fire" },
		{ "Mana Spring Totem", "Water" }, { "Healing Stream Totem", "Water" }, { "Mana Tide Totem", "Water" },
		{ "Poison Cleansing Totem", "Water" }, { "Disease Cleansing Totem", "Water" }, { "Fire Resistance Totem", "Water" },
		{ "Windfury Totem", "Air" }, { "Grace of Air Totem", "Air" }, { "Grounding Totem", "Air" },
		{ "Nature Resistance Totem", "Air" }, { "Windwall Totem", "Air" }, { "Sentry Totem", "Air" },
	},
})

Add({
	key = "demon", kind = "ask", category = Key("Classes"),
	source = "warcraft.wiki.gg warlock demon pages (original game)",
	ask = Key("Which warlock demon has %s?"),
	pool = { "Imp", "Voidwalker", "Succubus", "Felhunter" },
	facts = {
		{ "Firebolt", "Imp" }, { "Blood Pact", "Imp" }, { "Phase Shift", "Imp" }, { "Fire Shield", "Imp" },
		{ "Torment", "Voidwalker" }, { "Sacrifice", "Voidwalker" }, { "Consume Shadows", "Voidwalker" }, { "Suffering", "Voidwalker" },
		{ "Lash of Pain", "Succubus" }, { "Seduction", "Succubus" }, { "Soothing Kiss", "Succubus" }, { "Lesser Invisibility", "Succubus" },
		{ "Devour Magic", "Felhunter" }, { "Spell Lock", "Felhunter" }, { "Tainted Blood", "Felhunter" }, { "Paranoia", "Felhunter" },
	},
})

local PET_FAMILIES = {
	"Bat", "Bear", "Boar", "Carrion Bird", "Cat", "Crab", "Crocolisk", "Gorilla", "Hyena", "Owl", "Raptor",
	"Scorpid", "Spider", "Tallstrider", "Turtle", "Wind Serpent", "Wolf",
}
Add({
	key = "tame", kind = "which", category = Key("Classes"),
	source = "EldoUI hunter pet data (Data/Training/Pets.lua); warcraft.wiki.gg pet family list (original game)",
	groups = {
		{ ask = Key("Which of these beasts can a hunter tame?"), members = PET_FAMILIES,
			against = { "Murloc", "Kodo", "Ogre", "Gnoll", "Harpy", "Centaur", "Basilisk", "Silithid", "Treant", "Satyr", "Furbolg", "Kobold" } },
	},
})
Add({
	key = "petskill", kind = "ask", category = Key("Classes"),
	source = "warcraft.wiki.gg hunter pet ability pages (original game)",
	ask = Key("Which hunter pet family can learn %s?"), pool = PET_FAMILIES,
	facts = {
		{ "Charge", "Boar" }, { "Prowl", "Cat" }, { "Lightning Breath", "Wind Serpent" }, { "Scorpid Poison", "Scorpid" },
		{ "Thunderstomp", "Gorilla" }, { "Shell Shield", "Turtle" }, { "Furious Howl", "Wolf" },
	},
})

---------------------------------------------------------------------------
-- Races
---------------------------------------------------------------------------
Add({
	key = "start", kind = "ask", category = Key("Races"),
	source = "EldoUI story world (Data/StoryWorld.lua, starting zone of each race)",
	ask = Key("In which zone does a new %s begin?"),
	pool = { "Elwynn Forest", "Dun Morogh", "Teldrassil", "Durotar", "Mulgore", "Tirisfal Glades", "Westfall", "The Barrens" },
	facts = {
		{ "Human", "Elwynn Forest" }, { "Dwarf", "Dun Morogh" }, { "Gnome", "Dun Morogh" }, { "Night Elf", "Teldrassil" },
		{ "Orc", "Durotar" }, { "Troll", "Durotar" }, { "Tauren", "Mulgore" }, { "Undead", "Tirisfal Glades" },
	},
})
Add({
	key = "valley", kind = "ask", category = Key("Races"),
	source = "warcraft.wiki.gg starting area pages (original game)",
	ask = Key("In which starting area does a new %s wake up?"),
	pool = { "Northshire Valley", "Coldridge Valley", "Shadowglen", "Valley of Trials", "Camp Narache", "Deathknell" },
	facts = {
		{ "Human", "Northshire Valley" }, { "Dwarf", "Coldridge Valley" }, { "Gnome", "Coldridge Valley" },
		{ "Night Elf", "Shadowglen" }, { "Orc", "Valley of Trials" }, { "Troll", "Valley of Trials" },
		{ "Tauren", "Camp Narache" }, { "Undead", "Deathknell" },
	},
})
Add({
	key = "capital", kind = "ask", category = Key("Races"),
	source = "warcraft.wiki.gg race pages (original game capitals)",
	ask = Key("Which capital city is home to the %s race?"), pool = CAPITALS,
	facts = {
		{ "Human", "Stormwind City" }, { "Dwarf", "Ironforge" }, { "Gnome", "Ironforge" }, { "Night Elf", "Darnassus" },
		{ "Orc", "Orgrimmar" }, { "Troll", "Orgrimmar" }, { "Tauren", "Thunder Bluff" }, { "Undead", "Undercity" },
	},
})
Add({
	key = "side", kind = "which", category = Key("Races"),
	source = "warcraft.wiki.gg race pages",
	groups = {
		{ ask = Key("Which of these races fights for the Horde?"), members = HORDE_RACES, against = ALLIANCE_RACES },
		{ ask = Key("Which of these races fights for the Alliance?"), members = ALLIANCE_RACES, against = HORDE_RACES },
	},
})

local MOUNTS = {
	{ "Human", S(Key("Horse")) }, { "Dwarf", S(Key("Ram")) }, { "Gnome", S(Key("Mechanostrider")) },
	{ "Night Elf", S(Key("Nightsaber")) }, { "Orc", S(Key("Wolf")) }, { "Troll", S(Key("Raptor")) },
	{ "Tauren", S(Key("Kodo")) }, { "Undead", S(Key("Skeletal horse")) },
}
do
	local back, pool = {}, {}
	for _, row in ipairs(MOUNTS) do
		back[#back + 1] = { row[2], row[1] }
		pool[#pool + 1] = row[2]
	end
	Add({
		key = "mount", kind = "ask", category = Key("Races"),
		source = "warcraft.wiki.gg racial mount pages (original game)",
		ask = Key("Which mount does the %s race ride?"), pool = pool, facts = MOUNTS,
	})
	Add({
		key = "mountrace", kind = "ask", category = Key("Races"),
		source = "warcraft.wiki.gg racial mount pages (original game)",
		ask = Key("%s: which race rides it as its own mount?"), pool = RACES, facts = back,
	})
end

Add({
	key = "racial", kind = "ask", category = Key("Races"),
	source = "WoW: Forever racial traits from the game client",
	ask = Key("Which race has the racial trait %s?"), pool = RACES,
	facts = {
		{ "Perception", "Human" }, { "The Human Spirit", "Human" },
		{ "Stoneform", "Dwarf" }, { "Find Treasure", "Dwarf" }, { "Big Game Hunter", "Dwarf" },
		{ "Escape Artist", "Gnome" }, { "Expansive Mind", "Gnome" }, { "Engineering Specialization", "Gnome" },
		{ "Shadowmeld", "Night Elf" }, { "Quickness", "Night Elf" }, { "Wisp Spirit", "Night Elf" },
		{ "Blood Fury", "Orc" }, { "Hardiness", "Orc" }, { "Command", "Orc" },
		{ "Berserking", "Troll" }, { "Regeneration", "Troll" }, { "Beast Slaying", "Troll" },
		{ "War Stomp", "Tauren" }, { "Endurance", "Tauren" }, { "Cultivation", "Tauren" },
		{ "Will of the Forsaken", "Undead" }, { "Cannibalize", "Undead" }, { "Underwater Breathing", "Undead" },
	},
})

---------------------------------------------------------------------------
-- Professions
---------------------------------------------------------------------------
-- Gathering skills: from EldoUI's own zone data, so the game and the quiz
-- read the same numbers.
do
	local zone = E.zoneData
	local herbs, ore = {}, {}
	for _, row in pairs(zone and zone.herbs or {}) do herbs[#herbs + 1] = { row.name, row.skill } end
	for _, row in pairs(zone and zone.ore or {}) do ore[#ore + 1] = { row.name, row.skill } end
	table.sort(herbs, function(a, b) return a[1] < b[1] end)
	table.sort(ore, function(a, b) return a[1] < b[1] end)
	Add({
		key = "herb", kind = "ask", category = Key("Professions"), near = true,
		source = "EldoUI zone data (Data/Zones.lua, herb skill levels)",
		ask = Key("What Herbalism skill do you need to pick %s?"), facts = herbs,
	})
	Add({
		key = "ore", kind = "ask", category = Key("Professions"), near = true,
		source = "EldoUI zone data (Data/Zones.lua, ore skill levels)",
		ask = Key("What Mining skill is needed for %s?"), facts = ore,
	})
end

local CRAFTS = { "Alchemy", "Blacksmithing", "Enchanting", "Engineering", "Leatherworking", "Tailoring", "Cooking", "First Aid", "Mining" }
Add({
	key = "craft", kind = "ask", category = Key("Professions"),
	source = "warcraft.wiki.gg and wowhead.com classic recipe pages",
	ask = Key("Which profession makes %s?"), pool = CRAFTS,
	facts = {
		{ "Linen Bandage", "First Aid" }, { "Heavy Wool Bandage", "First Aid" }, { "Silk Bandage", "First Aid" },
		{ "Mageweave Bandage", "First Aid" }, { "Heavy Runecloth Bandage", "First Aid" }, { "Anti-Venom", "First Aid" },
		{ "Bolt of Linen Cloth", "Tailoring" }, { "Bolt of Silk Cloth", "Tailoring" }, { "Bolt of Mageweave", "Tailoring" },
		{ "Bolt of Runecloth", "Tailoring" }, { "Mooncloth", "Tailoring" }, { "Robe of the Archmage", "Tailoring" },
		{ "Truefaith Vestments", "Tailoring" }, { "Runecloth Bag", "Tailoring" },
		{ "Arcanite Reaper", "Blacksmithing" }, { "Lionheart Helm", "Blacksmithing" }, { "Elemental Sharpening Stone", "Blacksmithing" },
		{ "Dense Weightstone", "Blacksmithing" }, { "Arcanite Champion", "Blacksmithing" }, { "Truesilver Champion", "Blacksmithing" },
		{ "Thorium Grenade", "Engineering" }, { "Arclight Spanner", "Engineering" }, { "Gnomish Cloaking Device", "Engineering" },
		{ "Goblin Sapper Charge", "Engineering" }, { "Target Dummy", "Engineering" }, { "Field Repair Bot 74A", "Engineering" },
		{ "Goblin Jumper Cables", "Engineering" }, { "Gnomish Mind Control Cap", "Engineering" }, { "Mechanical Squirrel Box", "Engineering" },
		{ "Rough Dynamite", "Engineering" },
		{ "Flask of the Titans", "Alchemy" }, { "Elixir of the Mongoose", "Alchemy" }, { "Major Healing Potion", "Alchemy" },
		{ "Free Action Potion", "Alchemy" }, { "Limited Invulnerability Potion", "Alchemy" }, { "Greater Fire Protection Potion", "Alchemy" },
		{ "Arcanite Bar", "Alchemy" }, { "Swiftness Potion", "Alchemy" }, { "Philosopher's Stone", "Alchemy" }, { "Elixir of Giants", "Alchemy" },
		{ "Rugged Armor Kit", "Leatherworking" }, { "Thick Armor Kit", "Leatherworking" }, { "Devilsaur Gauntlets", "Leatherworking" },
		{ "Onyxia Scale Cloak", "Leatherworking" }, { "Cured Rugged Hide", "Leatherworking" }, { "Black Dragonscale Breastplate", "Leatherworking" },
		{ "Core Armor Kit", "Leatherworking" },
		{ "Runed Arcanite Rod", "Enchanting" }, { "Runed Copper Rod", "Enchanting" }, { "Lesser Magic Wand", "Enchanting" },
		{ "Greater Mystic Wand", "Enchanting" }, { "Enchant Weapon - Crusader", "Enchanting" }, { "Enchant Boots - Minor Speed", "Enchanting" },
		{ "Spiced Wolf Meat", "Cooking" }, { "Smoked Desert Dumplings", "Cooking" }, { "Runn Tum Tuber Surprise", "Cooking" },
		{ "Nightfin Soup", "Cooking" }, { "Grilled Squid", "Cooking" }, { "Dirge's Kickin' Chimaerok Chops", "Cooking" },
		{ "Herb Baked Egg", "Cooking" }, { "Goretusk Liver Pie", "Cooking" }, { "Westfall Stew", "Cooking" },
		{ "Copper Bar", "Mining" }, { "Tin Bar", "Mining" }, { "Bronze Bar", "Mining" }, { "Thorium Bar", "Mining" },
		{ "Dark Iron Bar", "Mining" }, { "Truesilver Bar", "Mining" },
	},
})

---------------------------------------------------------------------------
-- Lore
---------------------------------------------------------------------------
local BLACK, RED, BLUE, GREEN, BRONZE = S(Key("Black")), S(Key("Red")), S(Key("Blue")), S(Key("Green")), S(Key("Bronze"))
Add({
	key = "dragon", kind = "ask", category = Key("Lore"),
	source = "warcraft.wiki.gg dragon pages (original game lore)",
	ask = Key("To which dragonflight does %s belong?"), pool = { BLACK, RED, BLUE, GREEN, BRONZE },
	facts = {
		{ "Deathwing", BLACK }, { "Onyxia", BLACK }, { "Nefarian", BLACK }, { "Firemaw", BLACK }, { "Ebonroc", BLACK },
		{ "Flamegor", BLACK }, { "Broodlord Lashlayer", BLACK }, { "General Drakkisath", BLACK },
		{ "Alexstrasza", RED }, { "Vaelastrasz the Corrupt", RED },
		{ "Malygos", BLUE }, { "Azuregos", BLUE },
		{ "Ysera", GREEN }, { "Ysondre", GREEN }, { "Emeriss", GREEN }, { "Lethon", GREEN }, { "Taerar", GREEN },
		{ "Shade of Eranikus", GREEN },
		{ "Nozdormu", BRONZE },
	},
})

Add({
	key = "quality", kind = "ask", category = Key("Items"),
	source = "the game's item quality colors",
	ask = Key("What color is the name of an item of %s quality?"),
	pool = { S(Key("Gray")), S(Key("White")), S(Key("Green")), S(Key("Blue")), S(Key("Purple")), S(Key("Orange")) },
	facts = {
		{ S(Key("poor")), "Gray" }, { S(Key("common")), "White" }, { S(Key("uncommon")), "Green" },
		{ S(Key("rare")), "Blue" }, { S(Key("epic")), "Purple" }, { S(Key("legendary")), "Orange" },
	},
})

Add({
	key = "lore", kind = "fixed", category = Key("Lore"),
	source = "warcraft.wiki.gg lore pages for the original game; questions and wording written for EldoUI",
	list = {
		{ Key("Who is the Firelord that waits in the Molten Core?"), "Ragnaros", "Nefarian", "Onyxia", "Baron Geddon" },
		{ Key("Which black dragon hides in Stormwind as Lady Katrana Prestor?"), "Onyxia", "Nefarian", "Deathwing", "Vaelastrasz" },
		{ Key("Who is the master of Blackwing Lair?"), "Nefarian", "Ragnaros", "General Drakkisath", "Onyxia" },
		{ Key("Who is the father of Onyxia and Nefarian?"), "Deathwing", "Malygos", "Nozdormu", "Ragnaros" },
		{ Key("Which blood god do the Zandalari want stopped in Zul'Gurub?"), "Hakkar", "C'Thun", "Ragnaros", "Kel'Thuzad" },
		{ Key("Which Old God waits deep in the Temple of Ahn'Qiraj?"), "C'Thun", "Hakkar", "Kel'Thuzad", "Ragnaros" },
		{ Key("Who rules Naxxramas for the Scourge?"), "Kel'Thuzad", "Baron Rivendare", "Darkmaster Gandling", "Balnazzar" },
		{ Key("In which battleground do you capture the enemy's flag?"), "Warsong Gulch", "Arathi Basin", "Alterac Valley", "Gurubashi Arena" },
		{ Key("In which battleground do you hold the Stables, the Farm and the Lumber Mill?"), "Arathi Basin", "Warsong Gulch", "Alterac Valley", "Gurubashi Arena" },
		{ Key("In which battleground do the Stormpike Guard and the Frostwolf Clan fight?"), "Alterac Valley", "Arathi Basin", "Warsong Gulch", "Gurubashi Arena" },
		{ Key("Who leads the Frostwolf Clan in Alterac Valley?"), "Drek'Thar", "Vanndar Stormpike", "Thrall", "Cairne Bloodhoof" },
		{ Key("Who leads the Stormpike Guard in Alterac Valley?"), "Vanndar Stormpike", "Drek'Thar", "King Magni Bronzebeard", "Falstad Wildhammer" },
		{ Key("Which Alliance force fights in Warsong Gulch?"), "Silverwing Sentinels", "Warsong Outriders", "League of Arathor", "Stormpike Guard" },
		{ Key("Which Horde force fights in Warsong Gulch?"), "Warsong Outriders", "Silverwing Sentinels", "The Defilers", "Frostwolf Clan" },
		{ Key("Which Horde force fights in Arathi Basin?"), "The Defilers", "League of Arathor", "Warsong Outriders", "Frostwolf Clan" },
		{ Key("Which Alliance force fights in Arathi Basin?"), "League of Arathor", "The Defilers", "Silverwing Sentinels", "Stormpike Guard" },
		{ Key("Which legendary sword is the Blessed Blade of the Windseeker?"), "Thunderfury", "Sulfuras", "Quel'Serrar", "Ashkandi" },
		{ Key("Which legendary hammer is named after Ragnaros?"), "Sulfuras", "Thunderfury", "Atiesh", "Ashkandi" },
		{ Key("Which legendary staff is made from splinters found in Naxxramas?"), "Atiesh", "Benediction", "Sulfuras", "Thunderfury" },
		{ Key("Which faction has its base at Thorium Point?"), "Thorium Brotherhood", "Argent Dawn", "Timbermaw Hold", "Cenarion Circle" },
		{ Key("Which faction keeps Cenarion Hold in Silithus?"), "Cenarion Circle", "Argent Dawn", "Brood of Nozdormu", "Thorium Brotherhood" },
		{ Key("Which faction fights the Scourge from Light's Hope Chapel?"), "Argent Dawn", "Scarlet Crusade", "Cenarion Circle", "Hydraxian Waterlords" },
		{ Key("Which furbolg faction guards the tunnel between Felwood and Winterspring?"), "Timbermaw Hold", "Cenarion Circle", "Argent Dawn", "Thorium Brotherhood" },
		{ Key("Which faction asks you to douse the runes in the Molten Core?"), "Hydraxian Waterlords", "Thorium Brotherhood", "Argent Dawn", "Brood of Nozdormu" },
		{ Key("Which troll faction wants Hakkar stopped?"), "Zandalar Tribe", "Darkspear Trolls", "Bloodsail Buccaneers", "Thorium Brotherhood" },
		{ Key("Which faction serves the bronze dragons of the Caverns of Time?"), "Brood of Nozdormu", "Cenarion Circle", "Argent Dawn", "Timbermaw Hold" },
		{ Key("Which goblin trade group runs Booty Bay, Gadgetzan, Ratchet and Everlook?"), "Steamwheedle Cartel", "Venture Company", "Bloodsail Buccaneers", "Thorium Brotherhood" },
		{ Key("Which goblin company cuts down the forests of Stonetalon?"), "Venture Company", "Steamwheedle Cartel", "Defias Brotherhood", "The Syndicate" },
		{ Key("Which pirates raid Booty Bay?"), "Bloodsail Buccaneers", "Venture Company", "Defias Brotherhood", "The Syndicate" },
		{ Key("Who leads the Defias Brotherhood?"), "Edwin VanCleef", "Bazil Thredd", "Captain Greenskin", "Mr. Smite" },
		{ Key("Which band of thieves operates in Alterac and Hillsbrad?"), "The Syndicate", "Defias Brotherhood", "Bloodsail Buccaneers", "Venture Company" },
		{ Key("Which zealous order holds the Scarlet Monastery?"), "Scarlet Crusade", "Argent Dawn", "Cult of the Damned", "The Syndicate" },
		{ Key("Which cult serves the Scourge in the Plaguelands?"), "Cult of the Damned", "Scarlet Crusade", "Twilight's Hammer", "Burning Blade" },
		{ Key("Which cult gathers in the Twilight camps of Silithus?"), "Twilight's Hammer", "Cult of the Damned", "Burning Blade", "Scarlet Crusade" },
		{ Key("Which orc cult hides in Thunder Axe Fortress in Desolace?"), "Burning Blade", "Twilight's Hammer", "Cult of the Damned", "Defias Brotherhood" },
		{ Key("Who is the warchief of the Horde?"), "Thrall", "Cairne Bloodhoof", "Vol'jin", "Drek'Thar" },
		{ Key("Who leads the Forsaken?"), "Lady Sylvanas Windrunner", "Varimathras", "Thrall", "Kel'Thuzad" },
		{ Key("Who leads the tauren of Thunder Bluff?"), "Cairne Bloodhoof", "Magatha Grimtotem", "Thrall", "Drek'Thar" },
		{ Key("Who leads the Darkspear trolls?"), "Vol'jin", "Jin'do the Hexxer", "Witch Doctor Zum'rah", "Chief Ukorz Sandscalp" },
		{ Key("Who is the king of the dwarves in Ironforge?"), "King Magni Bronzebeard", "Falstad Wildhammer", "Emperor Dagran Thaurissan", "Vanndar Stormpike" },
		{ Key("Who leads the gnomes from their exile in Ironforge?"), "High Tinker Mekkatorque", "Mekgineer Thermaplugg", "Tinkerer Gizlock", "King Magni Bronzebeard" },
		{ Key("Who betrayed the gnomes and holds Gnomeregan?"), "Mekgineer Thermaplugg", "High Tinker Mekkatorque", "Crowd Pummeler 9-60", "Electrocutioner 6000" },
		{ Key("Who leads the night elves from Darnassus?"), "Tyrande Whisperwind", "Fandral Staghelm", "Jaina Proudmoore", "Lady Sylvanas Windrunner" },
		{ Key("Who is the arch druid of Darnassus?"), "Fandral Staghelm", "Tyrande Whisperwind", "Keeper Remulos", "Celebras the Cursed" },
		{ Key("Who rules Theramore Isle?"), "Jaina Proudmoore", "Highlord Bolvar Fordragon", "Tyrande Whisperwind", "Lady Katrana Prestor" },
		{ Key("Who is the regent of Stormwind while its king is missing?"), "Highlord Bolvar Fordragon", "Lady Katrana Prestor", "Archbishop Benedictus", "King Magni Bronzebeard" },
		{ Key("Who is the boy king of Stormwind?"), "Anduin Wrynn", "Highlord Bolvar Fordragon", "Edwin VanCleef", "King Magni Bronzebeard" },
		{ Key("Which dreadlord leads the Scarlet Crusade in Stratholme in disguise?"), "Balnazzar", "Varimathras", "Lord Kazzak", "Jandice Barov" },
		{ Key("Who leads the Scourge in the dead half of Stratholme?"), "Baron Rivendare", "Balnazzar", "Darkmaster Gandling", "Kel'Thuzad" },
		{ Key("Who is the headmaster of Scholomance?"), "Darkmaster Gandling", "Kel'Thuzad", "Baron Rivendare", "Ras Frostwhisper" },
		{ Key("Which demon lord roams the Blasted Lands as a world boss?"), "Lord Kazzak", "Azuregos", "Emeriss", "Balnazzar" },
		{ Key("Which blue dragon roams Azshara as a world boss?"), "Azuregos", "Lord Kazzak", "Ysondre", "Onyxia" },
		{ Key("On which great tree is Darnassus built?"), "Teldrassil", "Nordrassil", "Moonglade", "Ashenvale" },
		{ Key("Undercity lies under the ruins of which city?"), "Lordaeron", "Stratholme", "Dalaran", "Gilneas" },
		{ Key("Which human kingdom closed itself off behind the Greymane Wall?"), "Gilneas", "Stromgarde", "Alterac", "Kul Tiras" },
		{ Key("In which zone is Dalaran sealed under a magic dome?"), "Alterac Mountains", "Hillsbrad Foothills", "Silverpine Forest", "Arathi Highlands" },
		{ Key("Which was the first great human empire, born in the Arathi Highlands?"), "Arathor", "Lordaeron", "Gilneas", "Kul Tiras" },
		{ Key("After which queen of the ancient night elves is Azshara named?"), "Queen Azshara", "Tyrande Whisperwind", "Lady Sylvanas Windrunner", "Jaina Proudmoore" },
		{ Key("Which goddess do the night elves worship?"), "Elune", S(Key("the Holy Light")), S(Key("the Earth Mother")), S(Key("the Loa")) },
		{ Key("Whom do the tauren honor above all?"), S(Key("the Earth Mother")), "Elune", S(Key("the Holy Light")), S(Key("the Loa")) },
		{ Key("Which power do the paladins of Stormwind and Ironforge serve?"), S(Key("the Holy Light")), "Elune", S(Key("the Earth Mother")), S(Key("the Loa")) },
		{ Key("Which spirits do the trolls worship?"), S(Key("the Loa")), "Elune", S(Key("the Holy Light")), S(Key("the Earth Mother")) },
		{ Key("Which world did the orcs come from through the Dark Portal?"), "Draenor", "Northrend", "Kalimdor", "Lordaeron" },
		{ Key("Which land in the far north is the seat of the Lich King?"), "Northrend", "Draenor", "Kalimdor", "Lordaeron" },
		{ Key("Orgrimmar is named after which orc?"), "Orgrim Doomhammer", "Grom Hellscream", "Durotan", "Blackhand" },
		{ Key("Durotar is named after which orc?"), "Durotan", "Orgrim Doomhammer", "Grom Hellscream", "Blackhand" },
		{ Key("Grommash Hold in Orgrimmar honors which orc?"), "Grom Hellscream", "Orgrim Doomhammer", "Durotan", "Blackhand" },
		{ Key("Who was Thrall's father?"), "Durotan", "Orgrim Doomhammer", "Grom Hellscream", "Blackhand" },
		{ Key("What do the playable undead call themselves?"), "Forsaken", "Scourge", "Cult of the Damned", "Argent Dawn" },
		{ Key("Which army of the undead obeys the Lich King?"), "Scourge", "Forsaken", "Burning Legion", "Argent Dawn" },
		{ Key("Which demon army was beaten at Mount Hyjal?"), "Burning Legion", "Scourge", "Qiraji", "Twilight's Hammer" },
		{ Key("Which wall keeps Ahn'Qiraj sealed off from Silithus?"), "Scarab Wall", "Greymane Wall", "Thandol Span", "The Dark Portal" },
		{ Key("Which dwarf clan summoned Ragnaros?"), "Dark Iron", "Wildhammer", "Bronzebeard", "Stormpike" },
		{ Key("Which dwarf clan lives at Aerie Peak?"), "Wildhammer", "Bronzebeard", "Dark Iron", "Stormpike" },
		{ Key("Which element does Ragnaros rule?"), S(Key("Fire")), S(Key("Earth")), S(Key("Water")), S(Key("Air")) },
		{ Key("Princess Theradras is the daughter of which elemental lord?"), "Therazane", "Ragnaros", "Neptulon", "Al'Akir" },
		{ Key("Who built the vaults of Uldaman?"), S(Key("the titans")), S(Key("the trolls")), S(Key("the night elves")), S(Key("the gnomes")) },
		{ Key("Which troll empire built Zul'Gurub?"), "Gurubashi", "Amani", "Darkspear", "Sandfury" },
		{ Key("Which troll tribe holds Zul'Farrak?"), "Sandfury", "Gurubashi", "Darkspear", "Witherbark" },
		{ Key("Which troll tribe is part of the Horde?"), "Darkspear", "Gurubashi", "Sandfury", "Witherbark" },
		{ Key("Which ogre clan rules the north wing of Dire Maul?"), "Gordok", "Dunemaul", "Boulderfist", "Stonemaul" },
		{ Key("What kind of creature is Hogger of Elwynn Forest?"), S(Key("a gnoll")), S(Key("a kobold")), S(Key("a murloc")), S(Key("a harpy")) },
		{ Key("Which creatures in the mines of Elwynn Forest are famous for guarding their candles?"), S(Key("Kobolds")), S(Key("Gnolls")), S(Key("Murlocs")), S(Key("Troggs")) },
		{ Key("What kind of beast is Gahz'rilla?"), S(Key("a hydra")), S(Key("a dragon")), S(Key("a basilisk")), S(Key("a crocolisk")) },
		{ Key("Deep under which place does the Molten Core lie?"), "Blackrock Mountain", "Uldaman", "Gnomeregan", "Dire Maul" },
		{ Key("Blackrock Mountain lies between which two zones?"), S(Key("Searing Gorge and Burning Steppes")), S(Key("Badlands and Searing Gorge")), S(Key("Burning Steppes and Redridge Mountains")), S(Key("Deadwind Pass and Swamp of Sorrows")) },
		{ Key("Which tram runs between Stormwind and Ironforge?"), "Deeprun Tram", "Thandol Span", "The Dark Portal", "Scarab Wall" },
		{ Key("Which bridge joins the Wetlands and the Arathi Highlands?"), "Thandol Span", "Deeprun Tram", "Greymane Wall", "Stonewrought Dam" },
		{ Key("Where does the boat from Booty Bay sail to?"), "Ratchet", "Menethil Harbor", "Theramore Isle", "Auberdine" },
		{ Key("From Menethil Harbor, a boat sails to Auberdine and to which other port?"), "Theramore Isle", "Ratchet", "Booty Bay", "Rut'theran Village" },
		{ Key("From Auberdine, which port does the boat to Teldrassil reach?"), "Rut'theran Village", "Theramore Isle", "Menethil Harbor", "Ratchet" },
		{ Key("From Orgrimmar, a zeppelin flies to Undercity and to which camp?"), "Grom'gol Base Camp", "Kargath", "Stonard", "Hammerfall" },
		{ Key("Which mount carries Alliance travelers on flight paths in the Eastern Kingdoms?"), S(Key("Gryphon")), S(Key("Hippogryph")), S(Key("Wind rider")), S(Key("Drake")) },
		{ Key("Which mount carries Alliance travelers on flight paths in Kalimdor?"), S(Key("Hippogryph")), S(Key("Gryphon")), S(Key("Wind rider")), S(Key("Drake")) },
		{ Key("Which mount carries Horde travelers on flight paths in Kalimdor?"), S(Key("Wind rider")), S(Key("Gryphon")), S(Key("Hippogryph")), S(Key("Drake")) },
		{ Key("Which item takes you back to the inn you made your home?"), "Hearthstone", "Soulstone", "Healthstone", "Spellstone" },
		{ Key("Which reagent does a mage use for the Teleport spells?"), "Rune of Teleportation", "Soul Shard", "Ankh", "Symbol of Divinity" },
		{ Key("Which reagent does a mage use for Arcane Brilliance?"), "Arcane Powder", "Rune of Teleportation", "Flash Powder", "Soul Shard" },
		{ Key("What does a warlock gather with Drain Soul?"), "Soul Shard", "Ankh", "Rune of Teleportation", "Arcane Powder" },
		{ Key("Which reagent does a shaman need for Reincarnation?"), "Ankh", "Soul Shard", "Symbol of Divinity", "Flash Powder" },
		{ Key("Which reagent does a paladin use for Divine Intervention?"), "Symbol of Divinity", "Ankh", "Soul Shard", "Rune of Teleportation" },
		{ Key("Which reagent does a rogue use for Vanish?"), "Flash Powder", "Blinding Powder", "Soul Shard", "Ankh" },
		{ Key("Which reagent does a rogue use for Blind?"), "Blinding Powder", "Flash Powder", "Arcane Powder", "Soul Shard" },
		{ Key("Which ammunition does a bow fire?"), S(Key("Arrows")), S(Key("Bullets")), S(Key("Throwing knives")), S(Key("Darts")) },
		{ Key("Which ammunition does a gun fire?"), S(Key("Bullets")), S(Key("Arrows")), S(Key("Throwing knives")), S(Key("Darts")) },
		{ Key("Which bag holds a hunter's arrows?"), "Quiver", "Ammo Pouch", "Soul Pouch", "Herb Pouch" },
		{ Key("Which bag holds a hunter's bullets?"), "Ammo Pouch", "Quiver", "Soul Pouch", "Herb Pouch" },
		{ Key("Which profession splits into Gnomish and Goblin?"), "Engineering", "Blacksmithing", "Alchemy", "Tailoring" },
		{ Key("Which profession splits into Armorsmith and Weaponsmith?"), "Blacksmithing", "Engineering", "Leatherworking", "Tailoring" },
		{ Key("Which profession chooses between Dragonscale, Elemental and Tribal?"), "Leatherworking", "Blacksmithing", "Tailoring", "Engineering" },
		{ Key("Which profession makes bandages?"), "First Aid", "Cooking", "Alchemy", "Tailoring" },
		{ Key("Which profession takes leather from slain beasts?"), "Skinning", "Mining", "Herbalism", "Leatherworking" },
		{ Key("Which profession breaks magic items into dust and essences?"), "Enchanting", "Alchemy", "Tailoring", "Engineering" },
		{ Key("Which gathering profession goes best with Alchemy?"), "Herbalism", "Mining", "Skinning", "Fishing" },
		{ Key("Which gathering profession goes best with Blacksmithing?"), "Mining", "Herbalism", "Skinning", "Fishing" },
		{ Key("Which gathering profession goes best with Leatherworking?"), "Skinning", "Mining", "Herbalism", "Fishing" },
		{ Key("Which fishing contest is held in Stranglethorn Vale?"), "Stranglethorn Fishing Extravaganza", "Darkmoon Faire", "Midsummer Fire Festival", "Harvest Festival" },
		{ Key("During which festival do the innkeepers hand out treats?"), "Hallow's End", "Feast of Winter Veil", "Lunar Festival", "Harvest Festival" },
		{ Key("During which festival does Greatfather Winter visit?"), "Feast of Winter Veil", "Lunar Festival", "Hallow's End", "Love is in the Air" },
		{ Key("During which festival do you honor the elders with coins of ancestry?"), "Lunar Festival", "Feast of Winter Veil", "Children's Week", "Harvest Festival" },
		{ Key("How many copper coins make one silver?"), "100", "10", "50", "1000" },
		{ Key("How many silver coins make one gold?"), "100", "10", "50", "1000" },
		{ Key("What is the highest level a character can reach?"), "60", "50", "55", "70" },
		{ Key("How many classes can a new character choose from?"), "9", "8", "10", "12" },
		{ Key("How many races can a new character choose from?"), "8", "6", "10", "12" },
		{ Key("What does Bind on Pickup mean?"), S(Key("The item is yours the moment you loot it")), S(Key("The item binds when you first wear it")), S(Key("The item can be traded once")), S(Key("The item can be mailed to your other characters")) },
		{ Key("Where do you set your hearthstone's home?"), S(Key("With an innkeeper")), S(Key("At a flight master")), S(Key("At a class trainer")), S(Key("At the bank")) },
	},
})

---------------------------------------------------------------------------
-- The bank: built once, the first time a round starts
---------------------------------------------------------------------------
-- One entry per question: { set, ask, arg, right, from, skip, near }.
-- `from` is the list the wrong answers are drawn from and `skip` the
-- answers that must never be offered as wrong ones.
function D:Build()
	if self.bank then return self.bank end
	local bank = {}
	for _, set in ipairs(self.sets) do
		if set.kind == "ask" then
			local rights, answers, seen = {}, {}, {}
			for _, fact in ipairs(set.facts) do
				local subject, answer = fact[1], fact[2]
				rights[subject] = rights[subject] or {}
				rights[subject][answer] = true
				-- Answers that are not wrong either (the zone a city lies in).
				for _, near in ipairs(fact[3] or {}) do rights[subject][near] = true end
				if not seen[answer] then
					seen[answer] = true
					answers[#answers + 1] = answer
				end
			end
			local from = set.pool or answers
			for _, fact in ipairs(set.facts) do
				bank[#bank + 1] = { set = set, ask = set.ask, arg = fact[1], right = fact[2], from = from, skip = rights[fact[1]], near = set.near }
			end
		elseif set.kind == "which" then
			for _, group in ipairs(set.groups) do
				local skip = {}
				for _, member in ipairs(group.members) do skip[member] = true end
				for _, member in ipairs(group.members) do
					bank[#bank + 1] = { set = set, ask = group.ask, arg = group.arg, right = member, from = group.against, skip = skip }
				end
			end
		elseif set.kind == "fixed" then
			for _, row in ipairs(set.list) do
				bank[#bank + 1] = { set = set, ask = row[1], right = row[2], from = { row[3], row[4], row[5] }, skip = {}, fixed = true }
			end
		end
	end
	self.bank = bank
	return bank
end

function D:Count()
	return #self:Build()
end

-- The answers the wrong ones may come from, for one question.
function D:Candidates(entry)
	local out, seen = {}, { [entry.right] = true }
	for _, value in ipairs(entry.from) do
		if not seen[value] and not entry.skip[value] then
			seen[value] = true
			out[#out + 1] = value
		end
	end
	return out
end

-- Four answers in a random order and the place of the right one.
-- `random(n)` gives 1..n.
function D:Answers(entry, random)
	local wrong = self:Candidates(entry)
	local picked = {}
	if entry.near and tonumber(entry.right) then
		local target = tonumber(entry.right)
		table.sort(wrong, function(a, b)
			local da, db = math.abs(tonumber(a) - target), math.abs(tonumber(b) - target)
			if da == db then return tonumber(a) < tonumber(b) end
			return da < db
		end)
		-- Three of the five closest, so the numbers stay close but vary.
		local close = {}
		for i = 1, math.min(5, #wrong) do close[i] = wrong[i] end
		wrong = close
	end
	wrong = Copy(wrong)
	for _ = 1, 3 do
		if #wrong == 0 then break end
		picked[#picked + 1] = table.remove(wrong, random(#wrong))
	end
	local answers = { entry.right }
	for _, value in ipairs(picked) do answers[#answers + 1] = value end
	for i = #answers, 2, -1 do
		local j = random(i)
		answers[i], answers[j] = answers[j], answers[i]
	end
	local at
	for i, value in ipairs(answers) do
		if value == entry.right then at = i end
	end
	return answers, at
end
