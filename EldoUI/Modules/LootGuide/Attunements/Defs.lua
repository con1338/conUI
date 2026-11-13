-- EldoUI Attunements: what the generated data does not carry.
--
-- EldoUI_LootData's Attunements.lua (GPL, generated from CMaNGOS
-- classic-db by tools/lootdata from our own attunements.json) holds the
-- raids, keys and other chains: kind, side, instance, goal and every quest
-- the goal needs. This file adds our own words for them (a short line per
-- entry), the group order, and the WoW: Forever-only dungeons and chains
-- the classic data cannot know. Names come from the client: the instance
-- name for a raid, the key's item name for a key, the goal quest's title
-- otherwise; NAMES only covers entries whose live name would not say what
-- they are.
--
-- A:CollectEntries(LD) -> list of entries (see A:Get in Core.lua). Dungeon
-- quest chains (one entry per instance with quests) and class quest chains
-- (LD.classChains) are built here as well.
local _, E = ...
local L = E.L
local Key = E.Key
local A = E:GetModule("Attunements")

-- Groups in list order: key, title, which kinds belong.
A.GROUPS = {
	{ key = "raids", title = "Raids" },
	{ key = "keys", title = "Keys" },
	{ key = "dungeons", title = "Dungeon quests" },
	{ key = "class", title = "Class quests" },
	{ key = "misc", title = "Other chains" },
	{ key = "forever", title = "WoW: Forever" },
}
E:TranslateFields(A.GROUPS, "title")

A.KIND_TITLE = {
	raid = Key("Raid attunement"), key = Key("Key"), misc = Key("Quest chain"), dungeon = Key("Dungeon quests"),
	class = Key("Class quests"), forever = Key("Forever dungeon"),
}

-- Our own one-line descriptions (never another addon's text).
A.DESC = {
	mc = Key("Bring Lothos Riftwaker a Core Fragment from deep in Blackrock Depths and he lets you step into Molten Core from then on."),
	onyxia_a = Key("The long chain through Stormwind and Blackrock Spire ends with the Drakefire Amulet you need for Onyxia's Lair."),
	onyxia_h = Key("The Warlord's Command chain through Blackrock Spire ends with the Drakefire Amulet you need for Onyxia's Lair."),
	bwl = Key("A letter from the Scarshield Quartermaster in Blackrock Spire sends you to the orb behind General Drakkisath, which opens Blackwing Lair."),
	naxx = Key("The Argent Dawn sends you to Naxxramas once you are Honored or better; each rank makes the way in cheaper."),
	ubrs_seal = Key("The Seal of Ascension opens the doors of Upper Blackrock Spire for your whole group."),
	brd_key = Key("The Shadowforge Key opens the gates deeper in Blackrock Depths."),
	scholo_key_a = Key("The Skeleton Key opens the gates of Scholomance."),
	scholo_key_h = Key("The Skeleton Key opens the gates of Scholomance."),
	dm_crescent = Key("The Crescent Key opens the doors of Dire Maul West and North; a boss in Dire Maul East drops it."),
	strat_city = Key("The Key to the City opens the service gate of Stratholme; a boss inside drops it."),
	aqual = Key("Duke Hydraxis gives the Aqual Quintessence that puts out the runes in Molten Core."),
	scepter = Key("The long chain of Anachronos and the three dragonflights that opens the gates of Ahn'Qiraj."),
}

-- Entries whose client name would not say what they are.
A.NAMES = {
	scepter = Key("Scepter of the Shifting Sands"),
	aqual = Key("Aqual Quintessence"),
}

-- WoW: Forever-only content (not in classic-db). Each instance is found in
-- the client's own dungeon list by name; until a chain is written for it
-- (attunements.json forever.dungeons -> LD.attuneForever) its page lists
-- the quests you took for it (the recorder, Core.lua), and it stays out of
-- the list while you have taken none.
A.FOREVER = {
	{ key = "hall_of_thanes", name = Key("The Hall of Thanes"), kind = "dungeon" },
	{ key = "ruins_of_lordaeron", name = Key("Ruins of Lordaeron"), kind = "dungeon" },
	{ key = "excavation_site", name = Key("Excavation Site"), kind = "dungeon" },
	{ key = "city_of_dalaran", name = Key("City of Dalaran"), kind = "dungeon" },
	{ key = "drowned_city", name = Key("The Drowned City"), kind = "dungeon" },
	{ key = "kroldok", name = Key("Krol'dok Stronghold"), kind = "dungeon" },
	{ key = "alcaz_prison", name = Key("Alcaz Prison"), kind = "dungeon" },
	{ key = "blackmaw_hold", name = Key("Blackmaw Hold"), kind = "dungeon" },
	{ key = "shapers_terrace", name = Key("The Shapers Terrace"), kind = "dungeon" },
	{ key = "sleeping_bag_a", name = Key("Sleeping Bag"), kind = "misc", side = "Alliance" },
	{ key = "sleeping_bag_h", name = Key("Sleeping Bag"), kind = "misc", side = "Horde" },
	{ key = "dalaran_sewer_key_h", name = Key("Dalaran Sewer Key"), kind = "key", side = "Horde",
		instanceName = Key("City of Dalaran"), goalItems = { 277507 },
		desc = "Tracks whether you have the Dalaran Sewer Key. One key holder can open the gate for the group; you do not need to finish the dungeon quest first." },
}

local function Split(text, sep)
	local LG = E.LootGuide
	return LG.Split(text or "", sep)
end

local function Ids(text)
	local out = {}
	for id in tostring(text or ""):gmatch("%d+") do out[#out + 1] = tonumber(id) end
	return out
end
A.Ids = Ids

-- "kind|group|side|instanceKey|min-max|goalQuests|goalItems|faction:standing|links|flags|doorQuest"
local function Decode(key, packed)
	local f = Split(packed, "|")
	local lo, hi = (f[5] or ""):match("^(%d+)%-(%d+)$")
	local faction, standing = (f[8] or ""):match("^(%d+):(%d+)$")
	local flags = f[10] or ""
	local links = {}
	for link in (f[9] or ""):gmatch("[^,]+") do links[#links + 1] = link end
	return {
		key = key, kind = f[1], group = f[2] ~= "" and f[2] or f[1], side = f[3] ~= "both" and f[3] ~= "" and f[3] or nil,
		instance = f[4] ~= "" and f[4] or nil, minLevel = tonumber(lo), maxLevel = tonumber(hi),
		goalQuests = Ids(f[6]), goalItems = Ids(f[7]),
		rep = faction and { faction = tonumber(faction), standing = tonumber(standing) } or nil,
		links = links, any = flags:find("a", 1, true) ~= nil, drop = flags:find("d", 1, true) ~= nil,
		flag = tonumber(f[11]),
	}
end

-- "questID[:after+after],..."
local function HandSteps(text)
	local list = {}
	for part in tostring(text or ""):gmatch("[^,]+") do
		local id, after = part:match("^(%d+):?(.*)$")
		if id then
			local follows = {}
			for prev in after:gmatch("%d+") do follows[#follows + 1] = tonumber(prev) end
			list[#list + 1] = { q = tonumber(id), follows = follows }
		end
	end
	return list
end

local function Fold(text)
	return (E:FoldText(tostring(text or "")):gsub("^the ", ""):gsub(" ", ""))
end
A.Fold = Fold

-- Instances the client lists, by folded name (Forever-only dungeons).
local function CatalogByName()
	local byName = {}
	for _, info in ipairs(E.LootGuide:Catalog()) do byName[Fold(info.name)] = info.key end
	return byName
end

-- The side a list of race IDs plays on, or nil for both or an unknown race.
local RACE_SIDE = { [1] = "Alliance", [3] = "Alliance", [4] = "Alliance", [7] = "Alliance",
	[2] = "Horde", [5] = "Horde", [6] = "Horde", [8] = "Horde" }
function A.RaceSide(races)
	local side
	for _, race in ipairs(races or {}) do
		local own = RACE_SIDE[race]
		if not own or (side and side ~= own) then return nil end
		side = own
	end
	return side
end

function A:CollectEntries(LD)
	local LG = E.LootGuide
	local list = {}
	local order = 0
	local function Add(entry)
		order = order + 1
		entry.order = order
		list[#list + 1] = entry
	end
	-- Raids, keys and other chains from the generated data.
	if LD and type(LD.attunes) == "table" then
		local keys = type(LD.attuneOrder) == "table" and LD.attuneOrder or {}
		for _, key in ipairs(keys) do
			local packed = LD.attunes[key]
			if type(packed) == "string" then
				local entry = Decode(key, packed)
				entry.quests = Ids(LD.attuneSteps and LD.attuneSteps[key])
				entry.desc = A.DESC[key]
				entry.fixedName = A.NAMES[key]
				Add(entry)
			end
		end
	end
	-- Dungeon quests: one entry per instance with quests in the data.
	if LD and type(LD.instances) == "table" then
		for _, info in ipairs(LG:Catalog()) do
			local inst = LD.instances[info.key]
			if inst and info.kind == "dungeon" and not info.world then
				local ids = LG:InstanceQuestIDs(info.key)
				if #ids > 0 then
					Add({ key = "dq:" .. info.key, kind = "dungeon", group = "dungeons", instance = info.key,
						minLevel = info.min, maxLevel = info.max, quests = ids, closure = true, goalQuests = {}, goalItems = {}, links = {} })
				end
			end
		end
	end
	-- Class quests (LD.classChains): every class, the page filters. Each
	-- chain that ends in a spell of EldoUI's class quest list
	-- (Data/Training/Shared.lua) is tagged with the races it is for.
	local questSpells = E.TrainingData and E.TrainingData.questSpells or {}
	local racesOf, classic = {}, {}
	for _, spells in pairs(questSpells) do
		for _, variants in pairs(spells) do
			for _, variant in ipairs(variants) do
				local races = {}
				for _, race in ipairs(variant.races or {}) do races[race] = true end
				for _, q in ipairs(variant.quests or {}) do racesOf[q] = races end
			end
		end
	end
	if LD and type(LD.classChains) == "table" then
		local tokens = {}
		for token in pairs(LD.classChains) do tokens[#tokens + 1] = token end
		table.sort(tokens)
		for _, token in ipairs(tokens) do
			for index, text in ipairs(LD.classChains[token]) do
				local ids = Ids(text)
				if #ids > 0 then
					-- The level the chain opens at: its lowest quest level requirement.
					local level
					for _, q in ipairs(ids) do
						local quest = LG:Quest(q)
						if quest and quest.minLevel and quest.minLevel > 0 then level = math.min(level or 99, quest.minLevel) end
					end
					local races
					for _, q in ipairs(ids) do
						classic[q] = true
						races = races or racesOf[q]
					end
					-- Its side: the first quest's (class quests differ per faction).
					Add({ key = ("cq:%s:%d"):format(token, index), kind = "class", group = "class", class = token,
						minLevel = level, maxLevel = level, side = LG:QuestSide(ids[1]), races = races,
						quests = ids, goalQuests = { ids[#ids] }, goalItems = {}, links = {} })
				end
			end
		end
	end
	-- WoW: Forever's own class quests (a new race and class pair, or a spell
	-- the trainer no longer teaches), from EldoUI's class quest list: one
	-- entry per spell and race group, done with any of its reward quests.
	local tokens = {}
	for token in pairs(questSpells) do tokens[#tokens + 1] = token end
	table.sort(tokens)
	for _, token in ipairs(tokens) do
		local spellIDs = {}
		for spellID in pairs(questSpells[token]) do spellIDs[#spellIDs + 1] = spellID end
		table.sort(spellIDs)
		for _, spellID in ipairs(spellIDs) do
			for index, variant in ipairs(questSpells[token][spellID]) do
				local quests, known = {}, false
				for _, q in ipairs(variant.quests or {}) do
					quests[#quests + 1] = q
					if classic[q] then known = true end
				end
				if #quests > 0 and not known then
					local hand = {}
					for _, q in ipairs(quests) do hand[#hand + 1] = { q = q, follows = {} } end
					local side = A.RaceSide(variant.races)
					Add({ key = ("cqf:%s:%d:%d"):format(token, spellID, index), kind = "class", group = "class", class = token,
						minLevel = variant.level, maxLevel = variant.level, side = side, races = racesOf[quests[1]],
						spell = spellID, area = variant.area or (variant.areas and variant.areas[1]),
						hand = hand, quests = {}, goalQuests = quests, any = #quests > 1, goalItems = {}, links = {} })
				end
			end
		end
	end
	-- WoW: Forever-only entries.
	local byName = CatalogByName()
	local hand = LD and type(LD.attuneForever) == "table" and LD.attuneForever or {}
	for _, def in ipairs(A.FOREVER) do
		local instance = (def.instanceName or def.kind == "dungeon") and byName[Fold(def.instanceName or def.name)] or nil
		Add({ key = def.key, kind = "forever", subKind = def.kind, group = "forever", side = def.side, fixedName = def.name,
			instance = instance, forever = true, hand = HandSteps(hand[def.key]), quests = {}, goalQuests = {}, goalItems = CopyTable(def.goalItems or {}),
			desc = def.desc,
			links = {}, inGame = instance ~= nil })
	end
	return list
end
