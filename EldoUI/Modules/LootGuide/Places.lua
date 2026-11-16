-- EldoUI Loot Guide: instances, places and waypoints for the pages.
--
--   LG:Catalog()                every dungeon and raid the guide knows:
--                               EldoUI_LootData's list (wings under their
--                               group), the World Bosses group, and the
--                               dungeon finder's own list for anything the
--                               data does not have (WoW: Forever instances,
--                               or everything when LootData is missing)
--   LG:InstanceInfo(key)        one entry of that list
--   LG:InstanceLoot(key)        { bosses = { { npc, name, rare, loot = { { itemID, chance, questOnly } } } },
--                                 trash = { { itemID, chance, npc } } }
--   LG:Confidence(key)          "classic", "seen", "none", "announced",
--                               "notforever" + label
--   LG:ItemOffForever(itemID)   every source is a raid or world boss not in
--                               WoW: Forever yet
--   LG:InstanceArt(key)         icon and background: the dungeon finder's
--                               art, else the client's own art for that
--                               instance, else a generic dungeon or raid icon
--   LG:FitsLevel(info, level)   right for you / coming up / far off
--   LG:SpawnPoints(kind, id)    camps of a creature or object (world yards)
--   LG:EntrancePoint(key)       the instance entrance from the client's map data
--   LG:SetWaypoint(point, title) an EldoUI waypoint (Waypoints module on), or
--                               the game's own map pin and arrow
--   LG:CycleCamps(npc, title)   each click the next camp, the last clears the pin
--   LG:SeenItems(npc)           items you saw drop from a creature (Mob and Loot Info)
--
-- Everything here reads the client or EldoUI_LootData; nothing acts for the
-- player. Waypoints are set on a click: through EldoUI's Waypoints module
-- when it is on (one arrow for everything), else the game's user waypoint.
local _, E = ...
local LG = E.LootGuide
local L = E.L

local Secret = E.Secret

local function Data()
	return select(3, LG:DataStatus())
end

-- Classic world bosses: Azuregos, Lord Kazzak and the four dragons
-- of nightmare. Their loot comes from EldoUI_LootData's creature tables.
local WORLD_BOSSES = { 6109, 12397, 14887, 14888, 14889, 14890 }
LG.WORLD_BOSS_KEY = "worldbosses"
local worldBossSet = {}
for _, npc in ipairs(WORLD_BOSSES) do worldBossSet[npc] = true end

---------------------------------------------------------------------------
-- The dungeon finder (live): levels to enter and art, by instance map
---------------------------------------------------------------------------
local lfgByMap      -- instance map -> { id, name, min, max, size, texture }

local function LfgIndex()
	if lfgByMap then return lfgByMap end
	lfgByMap = {}
	if not (GetLFDChoiceOrder and GetLFGDungeonInfo) then return lfgByMap end
	local ok, order = pcall(GetLFDChoiceOrder)
	if not ok or type(order) ~= "table" then return lfgByMap end
	for _, id in ipairs(order) do
		local r = { pcall(GetLFGDungeonInfo, id) }
		local name, texture, mapID = r[2], r[12], r[23]
		if r[1] and type(name) == "string" and not Secret(name) and not Secret(mapID) and tonumber(mapID) then
			local entry = { id = id, name = name, min = not Secret(r[5]) and tonumber(r[5]) or nil,
				max = not Secret(r[6]) and tonumber(r[6]) or nil, size = not Secret(r[14]) and tonumber(r[14]) or nil,
				texture = type(texture) == "string" and not Secret(texture) and texture ~= "" and texture or nil }
			lfgByMap[tonumber(mapID)] = lfgByMap[tonumber(mapID)] or entry
		end
	end
	return lfgByMap
end

LG:Listen("LFG_UPDATE_RANDOM_INFO", "places", function() lfgByMap = nil; LG.catalog = nil end)

---------------------------------------------------------------------------
-- Catalog
---------------------------------------------------------------------------
-- Names compared without case, accents, spaces, punctuation and a leading
-- "the"; Cyrillic and CJK letters stay (E:FoldText), so a Russian or
-- Chinese name still matches itself.
local function Fold(text)
	return (E:FoldText(tostring(text or "")):gsub("^the ", ""):gsub(" ", ""))
end

local function BuildCatalog()
	local list, byKey = {}, {}
	local LD = Data()
	local mapsKnown = {}
	local function Add(entry)
		if byKey[entry.key] then return end
		byKey[entry.key] = entry
		list[#list + 1] = entry
	end
	if LD and type(LD.instances) == "table" then
		local order = type(LD.instanceOrder) == "table" and LD.instanceOrder or {}
		for index, key in ipairs(order) do
			local inst = LD.instances[key]
			if inst then
				local lfg = inst.map and LfgIndex()[inst.map]
				local group = inst.parent and LD.groups and LD.groups[inst.parent]
				local status = inst.status or "classic"
				if LG.NOT_ON_FOREVER and LG.NOT_ON_FOREVER[key] then status = "notforever" end
				Add({ key = key, name = LG:InstanceName(key) or inst.name or key, kind = inst.kind == "raid" and "raid" or "dungeon",
					min = inst.min, max = inst.max, size = inst.size, map = inst.map, status = status,
					parent = inst.parent, groupName = group and group.name, aliases = LG:InstanceAliases(key, inst.aliases), order = index,
					phase = LG:InstanceStep(key), enterLevel = lfg and lfg.min, lfg = lfg, bosses = #(inst.bosses or {}) })
				if inst.map then mapsKnown[inst.map] = true end
			end
		end
		-- World bosses as one group under Raids.
		local bosses = {}
		for _, npc in ipairs(WORLD_BOSSES) do
			if LD.mobs and LD.mobs[npc] and LD.loot and LD.loot[npc] then bosses[#bosses + 1] = npc end
		end
		if #bosses > 0 then
			Add({ key = LG.WORLD_BOSS_KEY, name = L["World Bosses"], kind = "raid", min = 60, max = 60, size = 40, status = "notforever",
				aliases = { "wb", "worldboss" }, order = #order + 1, world = true, bossList = bosses, bosses = #bosses })
		end
	end
	-- WoW: Forever's own dungeons (Forever.lua), with or without the data.
	local foreverByMap = {}
	for index, def in ipairs(LG.FOREVER or {}) do
		local entry = { key = def.key, name = def.name, kind = "dungeon", min = def.min, max = def.max, size = 5,
			status = "forever", forever = def, zoneName = LG:ForeverZone(def), aliases = def.aliases,
			order = 2000 + index, bosses = 0 }
		Add(entry)
		if def.map then foreverByMap[def.map] = entry end
	end
	-- Its announced raids: listed, never suggested before they open.
	local current = LG:CurrentPhase() or 1
	for index, def in ipairs(LG.FOREVER_RAIDS or {}) do
		local step = LG:InstanceStep(def.key)
		Add({ key = def.key, name = def.name, kind = "raid", min = def.min, max = def.max, size = def.size,
			status = step > current and "announced" or "forever", forever = def, zoneName = LG:ForeverZone(def), aliases = def.aliases,
			order = 2100 + index, bosses = 0, phase = step })
	end
	-- The dungeon finder's own dungeons that the data does not have. One
	-- the data knows by name (the same raid on another map) lends its art
	-- and entry level to that instance instead of showing up a second time.
	local byName = {}
	local function NameKey(kind, name) return kind .. ":" .. Fold(name) end
	for _, entry in ipairs(list) do
		local own = NameKey(entry.kind, entry.name)
		byName[own] = byName[own] or entry
		local inst = LD and LD.instances and LD.instances[entry.key]
		if inst and inst.name then
			local data = NameKey(entry.kind, inst.name)
			byName[data] = byName[data] or entry
		end
	end
	for mapID, lfg in pairs(LfgIndex()) do
		local kind = (lfg.size and lfg.size > 5) and "raid" or "dungeon"
		-- A Forever dungeon is matched by its map first, in any client language.
		local same = not mapsKnown[mapID] and (foreverByMap[mapID] or byName[NameKey(kind, lfg.name)])
		if same then
			same.lfg = same.lfg or lfg
			same.enterLevel = same.enterLevel or lfg.min
			-- A Forever dungeon the finder lists: the client's own name, levels and map.
			if same.forever then
				same.map, same.name = same.map or mapID, lfg.name
				same.min, same.max = lfg.min or same.min, lfg.max or same.max
			end
		elseif not mapsKnown[mapID] then
			Add({ key = "lfg:" .. lfg.id, name = lfg.name, kind = kind,
				min = lfg.min, max = lfg.max, size = lfg.size or 5, map = mapID, status = LD and "forever" or "live",
				lfg = lfg, enterLevel = lfg.min, order = 1000 + (lfg.min or 0), bosses = 0 })
		end
	end
	table.sort(list, function(a, b)
		if a.order ~= b.order then return a.order < b.order end
		return a.name < b.name
	end)
	return list, byKey
end

function LG:Catalog()
	-- A list built before the loot data loaded (or after it went) is built
	-- again, whichever order the loading and the readers came in.
	if not self.catalog or self.catalog.data ~= self:HasData() then
		-- A new list asks the client about its art again.
		if LG.ForgetArt then LG.ForgetArt() end
		local list, byKey = BuildCatalog()
		self.catalog = { list = list, byKey = byKey, data = self:HasData() }
	end
	return self.catalog.list
end

function LG:InstanceInfo(key)
	self:Catalog()
	return key and self.catalog.byKey[key]
end

LG:On("places", function(changed)
	if changed.data then LG.catalog = nil end
end)

-- Instance keys that share a map (Scarlet Monastery's wings): the one whose
-- name has the current sub-zone, else the first.
function LG:InstanceForPlayer(mapID)
	local matches = {}
	for _, info in ipairs(self:Catalog()) do
		if info.map == mapID then matches[#matches + 1] = info end
	end
	if #matches <= 1 then return matches[1] and matches[1].key end
	local sub = GetSubZoneText and GetSubZoneText()
	if type(sub) == "string" and not Secret(sub) and sub ~= "" then
		local folded = Fold(sub)
		for _, info in ipairs(matches) do
			if folded ~= "" and Fold(info.name):find(folded, 1, true) then return info.key end
		end
	end
	return matches[1].key
end

-- Every instance whose key or short form is `text`, in catalog order
-- ("dm": The Deadmines and Dire Maul; "st": Sunken Temple and The Shapers
-- Terrace).
function LG:FindInstances(text)
	local word = Fold(text)
	local keys = {}
	if word == "" then return keys end
	for _, info in ipairs(self:Catalog()) do
		local hit = Fold(info.key) == word
		for _, alias in ipairs(info.aliases or {}) do
			if Fold(alias) == word then hit = true end
		end
		if hit then keys[#keys + 1] = info.key end
	end
	return keys
end

-- Instances by alias or name start ("dm", "scholo", "strat"). A short form
-- several instances share opens the first one you can go to now.
function LG:FindInstance(text)
	local word = Fold(text)
	if word == "" then return end
	local LD = Data()
	local exact = self:FindInstances(text)
	for _, key in ipairs(exact) do
		if self:OpenNow(self:InstanceInfo(key)) then return key end
	end
	if exact[1] then return exact[1] end
	-- A group alias ("sm", "diremaul") opens its first wing.
	for groupKey, group in pairs(LD and LD.groups or {}) do
		local hit = Fold(groupKey) == word
		for _, alias in ipairs(group.aliases or {}) do if Fold(alias) == word then hit = true end end
		if hit and group.wings and group.wings[1] then return group.wings[1] end
	end
	if #word < 3 then return end
	for _, info in ipairs(self:Catalog()) do
		if Fold(info.name):sub(1, #word) == word then return info.key end
	end
	for _, info in ipairs(self:Catalog()) do
		if Fold(info.name):find(word, 1, true) then return info.key end
	end
end

---------------------------------------------------------------------------
-- Loot of an instance (decoded once per key)
---------------------------------------------------------------------------
local lootCache = {}
LG:On("placesloot", function(changed)
	if changed.data then wipe(lootCache) end
end)

local function ParseLoot(text)
	local out = {}
	for item, chance in (text or ""):gmatch("(%d+):(%-?[%d%.]+)") do
		local value, questOnly = LG.ParseChance(chance)
		out[#out + 1] = { itemID = tonumber(item), chance = value, questOnly = questOnly }
	end
	return out
end

function LG:InstanceLoot(key)
	local forever = self:InstanceInfo(key)
	if forever and forever.forever then return self:ForeverLoot(key) end
	if lootCache[key] then return lootCache[key] end
	local LD = Data()
	local result = { bosses = {}, trash = {} }
	local info = self:InstanceInfo(key)
	if info and info.world and LD then
		for _, npc in ipairs(info.bossList or {}) do
			local mob = self:Mob(npc)
			result.bosses[#result.bosses + 1] = { npc = npc, name = mob and mob.name or L["NPC %s"]:format(npc), display = mob and mob.display,
				level = mob and mob.maxLevel, loot = ParseLoot(LD.loot[npc]), world = true }
		end
	else
		local inst = LD and LD.instances and LD.instances[key]
		for _, boss in ipairs(inst and inst.bosses or {}) do
			local mob = self:Mob(boss.npc)
			local name = mob and mob.name
			if not name and boss.object then name = self:ObjectName(boss.object) end
			result.bosses[#result.bosses + 1] = { npc = boss.npc, name = name or L["NPC %s"]:format(tostring(boss.npc)), display = mob and mob.display,
				level = mob and mob.maxLevel, rare = boss.rare or false, also = boss.also, object = boss.object, loot = ParseLoot(boss.loot) }
		end
		for item, chance, npc in ((inst and inst.trash) or ""):gmatch("(%d+):(%-?[%d%.]+):(%d+)") do
			local value, questOnly = self.ParseChance(chance)
			result.trash[#result.trash + 1] = { itemID = tonumber(item), chance = value, questOnly = questOnly, npc = tonumber(npc) }
		end
	end
	lootCache[key] = result
	return result
end

-- Items you saw drop from a creature that the data does not list:
-- { itemID = drops }, kills. Read-only from Mob and Loot Info's store.
function LG:SeenItems(npc)
	npc = tonumber(npc)
	if not npc or not self:ObservedAvailable() then return end
	local store = type(EldoUIDB) == "table" and EldoUIDB.mobInfo
	if type(store) ~= "table" or store.v ~= 1 or type(store.mobs) ~= "table" then return end
	local mob = store.mobs[npc]
	if type(mob) ~= "table" or type(mob.i) ~= "table" then return end
	return mob.i, tonumber(mob.k) or 0
end

-- True when every source of an item is a raid or world boss WoW: Forever
-- has not opened (LG.NOT_ON_FOREVER). An item with any other source, or
-- none known, stays in.
local function SourceOff(entry, depth)
	local off = LG.NOT_ON_FOREVER or {}
	if entry.kind == "npc" then
		return (entry.instance and off[entry.instance]) or worldBossSet[tonumber(entry.id) or 0] or false
	elseif (entry.kind == "quest" or entry.kind == "choice") and entry.id then
		local key = LG:QuestInstance(entry.id)
		return key and off[key] or false
	elseif entry.kind == "token" and entry.id and depth < 2 then
		return LG:ItemOffForever(entry.id, depth + 1)
	end
	return false
end

function LG:ItemOffForever(itemID, depth)
	local list = self:ItemSources(itemID)
	if type(list) ~= "table" or #list == 0 then return false end
	for _, entry in ipairs(list) do
		if not SourceOff(entry, depth or 0) then return false end
	end
	return true
end

-- How much the guide knows about an instance's loot: key, label.
function LG:Confidence(key)
	local info = self:InstanceInfo(key)
	if not info then return "none", L["No drops known yet"] end
	if info.status == "classic" and self:HasData() then return "classic", L["Classic data"] end
	if info.status == "announced" then return "announced", L["Announced"] end
	if info.status == "notforever" then return "notforever", L["Not in WoW: Forever yet"] end
	if info.status == "forever" or info.status == "live" then return "none", L["No drops known yet"] end
	return "none", L["No drops known yet"]
end

---------------------------------------------------------------------------
-- Art: the dungeon finder's own pictures, else none (pages draw a panel)
---------------------------------------------------------------------------
-- The client's own dungeon finder art for each instance of the data, used
-- when the dungeon finder does not list it (raids, or a closed finder).
-- Every name is a file of the game client, checked before it is used.
local CLIENT_ART = {
	ragefire = "RagefireChasm", wailing = "WailingCaverns", deadmines = "Deadmines", shadowfang = "ShadowFangKeep",
	blackfathom = "BlackFathomDeeps", stockade = "StormwindStockades", gnomeregan = "Gnomeregan", kraul = "RazorfenKraul",
	sm_gy = "ScarletMonastery", sm_lib = "ScarletMonastery", sm_arm = "ScarletMonastery", sm_cath = "ScarletMonastery",
	downs = "RazorfenDowns", uldaman = "Uldaman", zulfarrak = "ZulFarak", maraudon = "Maraudon", sunken = "SunkenTemple",
	brd = "BlackrockDepths", lbrs = "BlackrockSpire", ubrs = "BlackrockSpire", dm_east = "DireMaul", dm_west = "DireMaul",
	dm_north = "DireMaul", scholomance = "Scholomance", strat_live = "Stratholme", strat_ud = "Stratholme",
	mc = "MoltenCore", onyxia = "OnyxiaEncounter", bwl = "BlackwingLair", zg = "ZulGurub", aq20 = "AQRuins",
	aq40 = "AQTemple", naxx = "Naxxramas",
}
LG.CLIENT_ART = CLIENT_ART
LG.GENERIC_ART = { dungeon = "Interface\\Icons\\INV_Misc_Bone_Skull_01", raid = "Interface\\Icons\\INV_Misc_Head_Dragon_01" }

local artKnown = {}
function LG.ForgetArt() wipe(artKnown) end
-- True when the client has the file (unknown when it cannot tell).
local function ClientHas(path)
	if artKnown[path] ~= nil then return artKnown[path] end
	local has = true
	if GetFileIDFromPath then
		local ok, id = pcall(GetFileIDFromPath, path)
		has = not (ok and type(id) == "nil")
	end
	artKnown[path] = has
	return has
end

local function ArtPair(name)
	return "Interface\\LFGFrame\\LFGIcon-" .. name, "Interface\\LFGFrame\\UI-LFG-BACKGROUND-" .. name
end

function LG:InstanceArt(key)
	local info = self:InstanceInfo(key)
	local lfg = info and info.lfg
	if lfg and lfg.texture then return ArtPair(lfg.texture) end
	local name = info and (CLIENT_ART[info.key] or (info.parent and CLIENT_ART[info.parent]))
	if name then
		local icon, background = ArtPair(name)
		if ClientHas(icon) then return icon, ClientHas(background) and background or nil end
	end
	if info and info.kind == "raid" then return LG.GENERIC_ART.raid end
	return LG.GENERIC_ART.dungeon
end

-- "fit" (in range), "near" (within levelWindow), "up" (coming up), "below".
function LG:FitsLevel(info, level)
	level = level or self:Player().level
	if not (info and info.min and info.max) then return "below" end
	local window = tonumber(self.db and self.db.levelWindow) or 3
	if level >= info.min and level <= info.max then return "fit" end
	if level >= info.min - window and level <= info.max + window then return "near" end
	if level < info.min then return "up" end
	return "below"
end

---------------------------------------------------------------------------
-- Spawns and waypoints
---------------------------------------------------------------------------
-- { { map, x, y, z, count }, ... } largest camp first.
function LG:SpawnPoints(kind, id)
	local LD = Data()
	id = tonumber(id)
	if not (LD and id) then return {} end
	local packed = kind == "object" and LD.objectSpawns and LD.objectSpawns[id] or (kind ~= "object" and LD.spawns and LD.spawns[id])
	if type(packed) ~= "string" then return {} end
	local mapText, rest = packed:match("^(%d+)|(.*)$")
	local map = tonumber(mapText)
	local out = {}
	for camp in (rest or ""):gmatch("[^;]+") do
		local x, y, z, count = camp:match("^(%-?[%d%.]+),(%-?[%d%.]+),(%-?[%d%.]+),?(%d*)$")
		if x then out[#out + 1] = { map = map, x = tonumber(x), y = tonumber(y), z = tonumber(z), count = tonumber(count) or 1 } end
	end
	return out
end

-- Continent ids where a world position can become a zone map point.
local CONTINENTS = { [0] = true, [1] = true }

-- uiMapID, x, y (0-1) for a world position on a continent. Spawn points
-- never move, so each answer is kept (up to MAP_CACHE_MAX points, then the
-- list starts over) and one vector is reused for the question: the guide
-- asks for the same camps every time it picks the next step.
local MAP_CACHE_MAX = 4096
local mapCache, mapCacheSize, mapCacheData = {}, 0, nil
local scratchVector

function LG:MapPosition(point)
	if not (point and CONTINENTS[point.map] and C_Map and C_Map.GetMapPosFromWorldPos and CreateVector2D) then return end
	if type(point.x) ~= "number" or type(point.y) ~= "number" then return end
	-- New guide data starts the list over.
	local data = Data()
	if data ~= mapCacheData then
		wipe(mapCache)
		mapCacheSize, mapCacheData = 0, data
	end
	local key = point.map .. ":" .. point.x .. ":" .. point.y
	local hit = mapCache[key]
	if hit then return hit[1], hit[2], hit[3] end
	if scratchVector and scratchVector.SetXY then
		scratchVector:SetXY(point.x, point.y)
	else
		scratchVector = CreateVector2D(point.x, point.y)
	end
	local ok, uiMapID, pos = pcall(C_Map.GetMapPosFromWorldPos, point.map, scratchVector)
	-- Only a full answer is kept: a lookup that fails or is hidden for a
	-- moment is asked again later.
	if not ok or Secret(uiMapID) or not uiMapID or type(pos) ~= "table" then return end
	local x, y = pos.x, pos.y
	if type(x) ~= "number" or type(y) ~= "number" or Secret(x) or Secret(y) then return end
	if mapCacheSize >= MAP_CACHE_MAX then
		wipe(mapCache)
		mapCacheSize = 0
	end
	mapCache[key] = { uiMapID, x, y }
	mapCacheSize = mapCacheSize + 1
	return uiMapID, x, y
end

-- Zone name for a uiMapID (the client's, LG:DataName).
function LG:MapName(uiMapID)
	return self:DataName("zone", uiMapID)
end

-- The zone a world spawn is in (name), when the client can tell.
function LG:SpawnZone(point)
	local uiMapID = self:MapPosition(point)
	return uiMapID and self:MapName(uiMapID)
end

-- Entrances from the client's map data, by folded instance name.
local entrances
local CONTINENT_MAPS = { 1414, 1415 }

local function BuildEntrances()
	entrances = {}
	local journal = C_EncounterJournal
	if not (journal and journal.GetDungeonEntrancesForMap and C_Map and C_Map.GetMapChildrenInfo) then return end
	local zoneType = Enum and Enum.UIMapType and Enum.UIMapType.Zone or 3
	for _, continent in ipairs(CONTINENT_MAPS) do
		local ok, children = pcall(C_Map.GetMapChildrenInfo, continent, zoneType, true)
		if ok and type(children) == "table" then
			for _, child in ipairs(children) do
				local fine, list = pcall(journal.GetDungeonEntrancesForMap, child.mapID)
				if fine and type(list) == "table" then
					for _, entrance in ipairs(list) do
						local name, pos = entrance.name, entrance.position
						if type(name) == "string" and not Secret(name) and type(pos) == "table" and type(pos.x) == "number" and not Secret(pos.x) then
							entrances[Fold(name)] = entrances[Fold(name)] or { uiMapID = child.mapID, x = pos.x, y = pos.y, zone = child.name, name = name }
						end
					end
				end
			end
		end
	end
end

-- New data brings new instance names: the entrances are matched again.
LG:On("places-entrances", function(changed)
	if changed.data then entrances = nil end
end)

-- { uiMapID, x, y, zone, name } or nil when the client does not know it.
function LG:EntrancePoint(key)
	local info = self:InstanceInfo(key)
	if not info or info.world then return end
	if not entrances then
		if InCombatLockdown() then return end
		BuildEntrances()
	end
	-- The entrances carry the client's names; a wing's own name is the
	-- data's, so the client's name of its map is tried as well.
	local live = info.map and GetRealZoneText and GetRealZoneText(info.map)
	if type(live) ~= "string" or Secret(live) or live == "" then live = nil end
	local names = { info.name, info.groupName, info.lfg and info.lfg.name, live }
	for index = 1, 4 do
		local name = names[index]
		local hit = name and entrances[Fold(name)]
		if hit then return hit end
	end
	-- "Scarlet Monastery: Library" -> "Scarlet Monastery"
	local base = info.name and info.name:match("^(.-)%s*:")
	return base and entrances[Fold(base)]
end

function LG:InstanceZone(key)
	local entrance = self:EntrancePoint(key)
	if entrance and entrance.zone then return entrance.zone end
	local info = self:InstanceInfo(key)
	return info and info.zoneName
end

-- EldoUI's Waypoints module, when it runs (it stands back for another
-- waypoint addon).
local function Waypoints()
	local WP = E.Waypoints
	if not (WP and WP.active and WP.Add) then return end
	return WP
end

-- Camp cycling state, reset when the mark is cleared.
local campStep = {}

-- point: { uiMapID, x, y } (0-1). Through the Waypoints module when it is
-- on (a session-only waypoint with the Loot Guide's title, replacing the
-- Loot Guide's previous one); otherwise the game's own map pin and arrow.
function LG:SetWaypoint(point, title)
	local WP = point and point.uiMapID and type(point.x) == "number" and type(point.y) == "number" and Waypoints()
	if WP then
		local old = LG.ownWaypoint
		if type(old) == "table" and old.uid and old.created and WP:Get(old.uid) then WP:Remove(old.uid, true) end
		local before = #WP.order
		local uid = WP:Add(point.uiMapID, point.x, point.y, { title = title, persistent = false, silent = true, source = "lootguide" })
		if uid then
			local zone = point.zone or self:MapName(point.uiMapID) or ""
			E:Print((L["Map pin set: %s, %s (%.1f, %.1f)."]):format(title or "?", zone, point.x * 100, point.y * 100))
			-- created: a new waypoint (not one of yours on the same spot), so
			-- clearing the mark may remove it.
			LG.ownWaypoint = { uiMapID = point.uiMapID, x = point.x, y = point.y, title = title, zone = zone,
				uid = uid, created = #WP.order > before or nil }
			if self.MarkChanged then self:MarkChanged(true) end
			return true
		end
	end
	if not (point and point.uiMapID and C_Map and C_Map.SetUserWaypoint and CreateVector2D) then
		E:Print(L["This client cannot set a map pin."])
		return false
	end
	if C_Map.CanSetUserWaypointOnMap then
		local ok, can = pcall(C_Map.CanSetUserWaypointOnMap, point.uiMapID)
		if ok and can == false then
			E:Print((L["%s: the map there does not take pins."]):format(title or "?"))
			return false
		end
	end
	-- The UiMapPoint structure: { uiMapID, position = Vector2D }.
	local ok = pcall(C_Map.SetUserWaypoint, { uiMapID = point.uiMapID, position = CreateVector2D(point.x, point.y) })
	if not ok then return false end
	if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true) end
	local zone = point.zone or self:MapName(point.uiMapID) or ""
	E:Print((L["Map pin set: %s, %s (%.1f, %.1f)."]):format(title or "?", zone, point.x * 100, point.y * 100))
	LG.ownWaypoint = { uiMapID = point.uiMapID, x = point.x, y = point.y, title = title, zone = zone }
	if self.MarkChanged then self:MarkChanged(true) end
	return true
end

-- Is the game's map pin still the one we set (the player may have set
-- another one since)?
function LG:IsOwnWaypoint()
	local own = LG.ownWaypoint
	if type(own) ~= "table" then return false end
	if own.uid then
		local WP = E.Waypoints
		return (own.created and WP and WP.active and WP:Get(own.uid) ~= nil) and true or false
	end
	if not (C_Map and C_Map.GetUserWaypoint) then return true end
	local ok, point = pcall(C_Map.GetUserWaypoint)
	if not ok or type(point) ~= "table" then return false end
	local pos = point.position
	if Secret(point.uiMapID) or type(pos) ~= "table" or Secret(pos.x) then return false end
	return point.uiMapID == own.uiMapID and math.abs((pos.x or -1) - own.x) < 0.001 and math.abs((pos.y or -1) - own.y) < 0.001
end

-- Is the thing our mark stands for still there? A Waypoints entry (even
-- one we reused) until it is removed or reached; a game pin while it is ours.
function LG:MarkAlive()
	local own = LG.ownWaypoint
	if type(own) ~= "table" then return false end
	if own.uid then
		local WP = E.Waypoints
		return (WP and WP.active and WP:Get(own.uid) ~= nil) and true or false
	end
	return self:IsOwnWaypoint()
end

-- Clears the map pin (or our waypoint) only when it is still ours.
function LG:ClearWaypoint()
	local own = LG.ownWaypoint
	if own and self:IsOwnWaypoint() then
		if own.uid then
			E.Waypoints:Remove(own.uid, true)
		elseif C_Map and C_Map.ClearUserWaypoint then
			pcall(C_Map.ClearUserWaypoint)
		end
	end
	LG.ownWaypoint = nil
	-- The next camp click starts at the first camp again.
	wipe(campStep)
	if self.MarkChanged then self:MarkChanged(false) end
end

-- A spawn point (world yards) or, inside an instance, its entrance.
function LG:PointFor(spawn)
	if not spawn then return end
	if CONTINENTS[spawn.map] then
		local uiMapID, x, y = self:MapPosition(spawn)
		if uiMapID then return { uiMapID = uiMapID, x = x, y = y } end
		return
	end
	for _, info in ipairs(self:Catalog()) do
		if info.map == spawn.map then
			local entrance = self:EntrancePoint(info.key)
			if entrance then return entrance, info.key end
		end
	end
end

-- Camp cycling: each call pins the next camp; after the last one
-- the pin is cleared. Returns the camp index (0 = cleared), camps.
function LG:CycleCamps(kind, id, title)
	local camps = self:SpawnPoints(kind, id)
	if #camps == 0 then return 0, 0 end
	local key = kind .. id
	-- Another creature's camps, or a mark that is gone (replaced, reached,
	-- cleared): start this creature at its first camp.
	local own = LG.ownWaypoint
	if not (type(own) == "table" and own.campKey == key and self:MarkAlive()) then wipe(campStep) end
	local step = (campStep[key] or 0) + 1
	if step > #camps or (#camps == 1 and campStep[key] == 1) then
		campStep[key] = 0
		self:ClearWaypoint()
		E:Print(L["Map pin cleared."])
		return 0, #camps
	end
	campStep[key] = step
	local point = self:PointFor(camps[step])
	if point then
		if self:SetWaypoint(point, #camps > 1 and ("%s (%d/%d)"):format(title or "?", step, #camps) or title) then
			if type(LG.ownWaypoint) == "table" then LG.ownWaypoint.campKey = key end
			if self.ShowMark then self:ShowMark() end
		end
	else
		E:Print(L["This place cannot be shown on your map."])
	end
	return step, #camps
end
