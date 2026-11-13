-- EldoUI Loot Guide: the dungeons WoW: Forever added.
--
-- The loot data has none of these dungeons, and the client's dungeon
-- finder lists one only once it is open to you. So the Journal always
-- knows them from this list: name, level range and zone. Live data wins: a
-- dungeon the dungeon finder lists takes its name, levels and art from the
-- client.
--
-- The level ranges and zones are the ones the game gave when it announced
-- the nine dungeons. The bosses and their loot are not listed here: each
-- boss is added when you defeat it, with the items you see it drop.
--
--   key      the Journal's key for the dungeon
--   name     its English name, as the client writes it
--   min/max  the level range given at launch
--   zone     the zone's map ID (the client names it in your language)
--   zoneName the zone's English name, where the map lookup can fail
--   aliases  the short forms and name words players type for it
local _, E = ...
local LG = E.LootGuide
if not LG then return end

LG.FOREVER = {
	{ key = "forever:thanes", name = "The Hall of Thanes", min = 13, max = 18, zone = 1426, aliases = { "hot", "thanes" } },
	{ key = "forever:lordaeron", name = "Ruins of Lordaeron", min = 15, max = 20, zone = 1420, aliases = { "rol", "ruins", "lordaeron" } },
	{ key = "forever:excavation", name = "Excavation Site", min = 24, max = 29, zone = 1437, aliases = { "excavation" } },
	{ key = "forever:dalaran", name = "City of Dalaran", min = 28, max = 33, zone = 1416, aliases = { "dalaran" } },
	{ key = "forever:drowned", name = "The Drowned City", min = 35, max = 40, zone = 1434, aliases = { "drowned" } },
	{ key = "forever:kroldok", name = "Krol'dok Stronghold", min = 40, max = 45, zone = 2548, zoneName = "Riverglades", aliases = { "krol", "kroldok" } },
	{ key = "forever:alcaz", name = "Alcaz Prison", min = 48, max = 53, zone = 1445, aliases = { "alcaz" } },
	{ key = "forever:blackmaw", name = "Blackmaw Hold", min = 55, max = 60, zone = 1447, aliases = { "blackmaw" } },
	{ key = "forever:shaper", name = "The Shapers Terrace", min = 58, max = 60, zone = 1449, aliases = { "st", "shaper", "terrace" } },
}

-- WoW: Forever's first raid tier, announced to open on December 9, 2026,
-- together with Onyxia's Lair. Bosses and loot are added from the game once
-- the raids open, like the dungeons above.
LG.FOREVER_RAIDS = {
	{ key = "forever:barrow", name = "Barrow Deeps", min = 60, max = 60, size = 10, zoneName = "Mount Hyjal", aliases = { "bd", "barrow", "deeps" } },
	{ key = "forever:hyjal", name = "Hyjal Summit", min = 60, max = 60, size = 20, zoneName = "Mount Hyjal", aliases = { "hs", "hyjal" } },
}

-- WoW: Forever's schedule, as Blizzard announced it. It has no numbered
-- content phases: content opens in steps on announced days. Each step
-- lists the instances that open with it; everything else is open since
-- launch. A step counts as open from its day (UTC; the raids open
-- worldwide at one moment that day).
--   key        the step's key
--   name       what the guide calls it
--   opens      { year, month, day } the announced day (none: open at launch)
--   instances  the Journal keys that open with it
LG.FOREVER_SCHEDULE = {
	{ key = "launch", name = E.Key("Launch content") },
	{ key = "raids1", name = E.Key("December raids"), opens = { year = 2026, month = 12, day = 9 },
		instances = { onyxia = true, ["forever:barrow"] = true, ["forever:hyjal"] = true } },
}
E:TranslateFields(LG.FOREVER_SCHEDULE, "name")

-- Short forms that need more than the instance's own list. Each instance
-- keeps its short forms in `aliases`; these say how to read the hard ones.
--   ambiguous    one short form for several instances: a search lists
--                every match, a reader of chat lines looks at the other
--                words and the poster's level
--   contextOnly  an instance only right after its group word ("sm cath",
--                "strat live"); alone, in a chat line, it means something else
--   moved        a short form WoW: Forever players use for another instance
--                than the loot data does
LG.SHORT_FORMS = {
	ambiguous = { dm = true, st = true, bd = true, hot = true },
	contextOnly = { gy = true, lib = true, arm = true, cath = true, live = true, ud = true },
	moved = { ruins = "forever:lordaeron" },
}

-- The instance's short forms without the ones moved to another instance.
function LG:InstanceAliases(key, aliases)
	local moved = self.SHORT_FORMS.moved
	local list = {}
	for _, alias in ipairs(aliases or {}) do
		if not moved[alias] or moved[alias] == key then list[#list + 1] = alias end
	end
	return list
end

-- Classic raids WoW: Forever has neither opened nor announced, and the
-- Classic world bosses it has not released. Their data stays for the day
-- a version of them opens; until then the guide marks them and leaves them
-- out of suggestions, entrance pins and Best in Slot plans.
LG.NOT_ON_FOREVER = { mc = true, bwl = true, zg = true, aq20 = true, aq40 = true, naxx = true, worldbosses = true }

-- World events of the loot data that WoW: Forever does not run: the
-- Ahn'Qiraj war effort and the Scourge invasion with their stages (tied to
-- raids it has not opened), and the timing steps of other events (the
-- fishing contest's announce and turn-in, the Faire's building stage, the
-- Winter Veil gifts, night time), whose quests the main event lists.
LG.EVENTS_NOT_ON_FOREVER = {
	[14] = true, [17] = true, [21] = true, [22] = true, [27] = true, [28] = true, [34] = true, [89] = true, [99] = true,
	[120] = true, [121] = true, [122] = true, [123] = true, [124] = true, [125] = true, [126] = true, [127] = true,
}

-- What WoW: Forever added to an event, by the loot data's event ID. The
-- fishing contest pays in Extravagant Extravaganza Coins, which Jang in
-- Booty Bay trades for a prize.
LG.FOREVER_EVENT_EXTRAS = {
	[15] = { npc = 15078, items = { 274026, 276272, 276273, 276275 } },
}

-- True when the player can go there now: not announced only, not missing
-- from WoW: Forever.
function LG:Playable(info)
	return type(info) == "table" and info.status ~= "announced" and info.status ~= "notforever"
end

-- The zone's name in the player's language, or the English one from the
-- list; nil when the place is not known yet.
function LG:ForeverZone(def)
	if def.zone and C_Map and C_Map.GetMapInfo then
		local ok, info = pcall(C_Map.GetMapInfo, def.zone)
		local name = ok and type(info) == "table" and info.name
		if type(name) == "string" and not E.Secret(name) and name ~= "" then return name end
	end
	return def.zoneName
end

---------------------------------------------------------------------------
-- What you see: bosses and their loot, from the game
---------------------------------------------------------------------------
-- The game names each boss you defeat (ENCOUNTER_END) and each item a boss
-- drops for your group (ENCOUNTER_LOOT_RECEIVED). Kept per character in
-- the Loot Guide's own saved data, by dungeon key:
--   forever[key] = { bosses = { [encounterID] = { name, order, kills } },
--                    loot = { [encounterID] = { [itemID] = drops } } }
local Secret = E.Secret

local function Fold(text)
	return (E:FoldText(tostring(text or "")):gsub("^the ", ""):gsub(" ", ""))
end

local function Store()
	local char = LG:Char()
	if not char then return nil end
	if type(char.forever) ~= "table" then char.forever = {} end
	return char.forever
end

function LG:ForeverLearned(key)
	local store = Store()
	local entry = store and store[key]
	return type(entry) == "table" and entry or nil
end

-- The Forever dungeon you are in, or nil.
function LG:ForeverHere()
	local ok, name, kind, _, _, _, _, _, instanceID = pcall(GetInstanceInfo)
	if not ok or Secret(name) or Secret(kind) or Secret(instanceID) or kind ~= "party" then return nil end
	local folded = Fold(name)
	for _, def in ipairs(LG.FOREVER) do
		local info = self:InstanceInfo(def.key)
		if (info and info.map and info.map == instanceID) or Fold(def.name) == folded
			or (info and Fold(info.name) == folded) then
			return def.key
		end
	end
end

local currentBoss = {} -- encounterID -> name, while you are inside

local function Entry(key)
	local store = Store()
	if not store then return nil end
	local entry = store[key]
	if type(entry) ~= "table" then
		entry = {}
		store[key] = entry
	end
	if type(entry.bosses) ~= "table" then entry.bosses = {} end
	if type(entry.loot) ~= "table" then entry.loot = {} end
	return entry
end

function LG:LearnForeverBoss(encounterID, name)
	encounterID = not Secret(encounterID) and tonumber(encounterID)
	if not encounterID or Secret(name) or type(name) ~= "string" or name == "" then return end
	local key = self:ForeverHere()
	local entry = key and Entry(key)
	if not entry then return end
	local boss = entry.bosses[encounterID]
	if type(boss) ~= "table" then
		local count = 0
		for _ in pairs(entry.bosses) do count = count + 1 end
		boss = { name = name, order = count + 1 }
		entry.bosses[encounterID] = boss
	end
	boss.kills = (tonumber(boss.kills) or 0) + 1
	currentBoss[encounterID] = key
	self:Fire("forever")
end

function LG:LearnForeverLoot(encounterID, itemID)
	encounterID = not Secret(encounterID) and tonumber(encounterID)
	itemID = not Secret(itemID) and tonumber(itemID)
	if not (encounterID and itemID) then return end
	local key = currentBoss[encounterID] or self:ForeverHere()
	local entry = key and Entry(key)
	if not entry or type(entry.bosses[encounterID]) ~= "table" then return end
	local drops = entry.loot[encounterID]
	if type(drops) ~= "table" then
		drops = {}
		entry.loot[encounterID] = drops
	end
	drops[itemID] = (tonumber(drops[itemID]) or 0) + 1
	self:Fire("forever")
end

LG:Listen("ENCOUNTER_END", "forever", function(_, encounterID, name, _, _, success)
	if Secret(success) or not (success == 1 or success == true) then return end
	LG:LearnForeverBoss(encounterID, name)
end)
LG:Listen("ENCOUNTER_LOOT_RECEIVED", "forever", function(_, encounterID, itemID)
	LG:LearnForeverLoot(encounterID, itemID)
end)

-- The Journal's loot for a Forever dungeon: the bosses you defeated there,
-- in the order you first met them, each with what you saw it drop.
function LG:ForeverLoot(key)
	local result = { bosses = {}, trash = {} }
	local entry = self:ForeverLearned(key)
	if not entry or type(entry.bosses) ~= "table" then return result end
	local list = {}
	for encounterID, boss in pairs(entry.bosses) do
		if type(boss) == "table" and type(boss.name) == "string" then
			list[#list + 1] = { encounter = tonumber(encounterID), name = boss.name, order = tonumber(boss.order) or 99,
				kills = tonumber(boss.kills) or 0 }
		end
	end
	table.sort(list, function(a, b)
		if a.order ~= b.order then return a.order < b.order end
		return a.name < b.name
	end)
	for _, boss in ipairs(list) do
		local seen = type(entry.loot) == "table" and entry.loot[boss.encounter]
		result.bosses[#result.bosses + 1] = { name = boss.name, encounter = boss.encounter, loot = {},
			seenLoot = type(seen) == "table" and seen or {}, kills = boss.kills, learned = true }
	end
	return result
end
