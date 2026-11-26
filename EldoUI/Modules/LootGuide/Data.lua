-- EldoUI Loot Guide: data access (the pieces the shell and
-- the tooltips need now).
--
-- Where loot knowledge comes from, in order of trust:
--   * live: the client (item info, quest titles, instance names)
--   * lootdata: EldoUI_LootData, a separate load-on-demand addon folder
--     (GPL-3.0 data generated from CMaNGOS classic-db by tools/lootdata).
--     Loaded out of combat a few seconds after login or on first use. Its
--     record formats are documented in tools/lootdata/README.md; every
--     record is a packed string that is decoded here on access and kept in
--     a small cache.
--   * observed: drops the player saw with Mob and Loot Info (MobInfo).
-- Pages and plugins add providers with LG:RegisterProvider(key, def); the
-- tooltips and pages ask this file, never a provider directly.
--
-- Also here:
--   * E:LootGuideKnows(itemID): MobInfo's "Dropped by" block steps aside for
--     items the Loot Guide shows a source for.
--   * a stats provider for E.ItemScore, so items the client has not cached
--     yet still get a score from the LootData record.
--   * the item loader: item data is requested only for rows on screen, at
--     most 8 requests in flight and 20 in any second (no query spam).
--   * vendors, crafts and trainers, tokens, world events and content phases
--     from LootData, and the source kinds built from them (vendor,
--     reputation vendor, PvP vendor, crafted, token).
--   * observed vendor costs: an open merchant's prices, read once per
--     vendor per session (read-only, never buys).
--   * live: the dungeon finder's list and finished quests, so the guide
--     works without LootData too.
local _, E = ...
local LG = E.LootGuide
local L = E.L

-- luacheck: read globals EldoUI_LootData

local ADDON = "EldoUI_LootData"
local FORMATS = { [1] = true }   -- LootData record formats this file reads
local LOGIN_DELAY = 5            -- seconds after login before loading LootData
local CACHE_SIZE = 2000          -- decoded records kept

local Secret = E.Secret

---------------------------------------------------------------------------
-- Providers
---------------------------------------------------------------------------
local providers, providerOrder = {}, {}

-- def: { title, available = function() return bool end, sources(itemID),
-- quests(itemID), instances() }; every function is optional.
function LG:RegisterProvider(key, def)
	assert(type(key) == "string" and type(def) == "table", "LootGuide:RegisterProvider(key, def)")
	def.key = key
	if not providers[key] then table.insert(providerOrder, key) end
	providers[key] = def
	self:Fire("data")
end

function LG:Providers()
	local list = {}
	for _, key in ipairs(providerOrder) do
		local def = providers[key]
		local ok, available = true, true
		if def.available then ok, available = pcall(def.available) end
		if ok and available then list[#list + 1] = def end
	end
	return list
end

---------------------------------------------------------------------------
-- EldoUI_LootData: loading
-- status: "pending" (not tried yet), "loaded", "missing" (not installed),
-- "disabled" (switched off in the addon list), "old" (a record format this
-- version cannot read), "failed" (the game refused, reason in loadReason).
---------------------------------------------------------------------------
local status = "pending"
local loadReason
local LD               -- the EldoUI_LootData table once it is usable

local function Adopt()
	local data = rawget(_G, ADDON)
	if type(data) ~= "table" then return false end
	if not FORMATS[tonumber(data.format) or 1] then
		status = "old"
		return false
	end
	LD = data
	status = "loaded"
	if E.ItemScore and E.ItemScore.Bump then E.ItemScore:Bump() end
	LG:ClearDataCaches()
	LG:Fire("data")
	return true
end

-- Load EldoUI_LootData now if we may. Never in combat (a large file would
-- stall a frame); a combat attempt waits for the end of combat.
function LG:LoadData()
	if LD then return true end
	-- Already there (loaded by another addon, or by the game at login).
	if Adopt() then return true end
	if status == "missing" or status == "disabled" or status == "old" then return false end
	if InCombatLockdown() then
		self.loadAfterCombat = true
		return false
	end
	local name, _, _, loadable, reason = C_AddOns.GetAddOnInfo(ADDON)
	if not name then
		status = "missing"
		return false
	end
	if reason == "DISABLED" or reason == "DEP_DISABLED" then
		status = "disabled"
		return false
	end
	local loaded, why = C_AddOns.LoadAddOn(ADDON)
	if loaded and Adopt() then return true end
	if not loaded then
		status = "failed"
		loadReason = why or reason or (loadable == false and "NOT_LOADABLE") or nil
	end
	return false
end

function LG:HasData()
	return LD ~= nil
end

function LG:DataStatus()
	return status, loadReason, LD
end

-- Short text for the footer, the datatext and /lg data.
function LG:DataStatusText(short)
	if LD then
		if short then return ("EldoUI_LootData %s"):format(tostring(LD.version or "?")) end
		return (L["Classic values (EldoUI_LootData %s)"]):format(tostring(LD.version or "?"))
	elseif status == "missing" then
		return short and L["not installed"] or L["EldoUI_LootData is not installed"]
	elseif status == "disabled" then
		return short and L["switched off"] or L["EldoUI_LootData is switched off in the addon list"]
	elseif status == "old" then
		return short and L["needs an update"] or L["EldoUI_LootData is too new or too old for this EldoUI"]
	elseif status == "failed" then
		local text = short and L["could not load"] or L["EldoUI_LootData could not load"]
		if loadReason and not short then text = text .. " (" .. tostring(loadReason) .. ")" end
		return text
	end
	return short and L["loads soon"] or L["EldoUI_LootData loads a few seconds after login"]
end

function LG:PrintDataStatus()
	E:Print(L["Loot Guide data:"])
	print("  " .. L["Loot tables:"] .. " " .. self:DataStatusText())
	if LD then
		local counts = type(LD.counts) == "table" and LD.counts or {}
		print(("  %s %s, %s %s"):format(L["Source:"], tostring(LD.source or "?"), L["commit"], tostring(LD.commit or "?")))
		print(("  " .. L["Items: %d · creatures: %d · instances: %d · quests: %d"]):format(tonumber(counts.items) or 0,
			tonumber(counts.mobs) or 0, tonumber(counts.instances) or 0, tonumber(counts.quests) or 0))
		local tokens = 0
		for _ in pairs(type(LD.tokens) == "table" and LD.tokens or {}) do tokens = tokens + 1 end
		print(("  " .. L["Vendors: %d · crafts: %d · tokens: %d · world events: %d"]):format(tonumber(counts.vendors) or 0,
			tonumber(counts.crafts) or 0, tokens, tonumber(counts.events) or 0))
		local memory = self:DataMemory()
		if memory then print(("  " .. L["Memory: %.1f MB"]):format(memory / 1024)) end
		print("  " .. L["Classic values; WoW: Forever may differ."])
	end
	local costs = self:SeenVendorCount()
	print(("  " .. E:Plural(costs, "Vendor prices you saw: %d item", "Vendor prices you saw: %d items")):format(costs))
	local live = self:LiveInstances()
	if live and #live > 0 then print(("  " .. E:Plural(#live, "Dungeon finder: %d dungeon", "Dungeon finder: %d dungeons")):format(#live)) end
	local seen = self:ObservedAvailable()
	print("  " .. L["Drops seen by you:"] .. " " .. (seen and L["on (Mob and Loot Info)"] or L["off (turn on Mob and Loot Info)"]))
	local names = {}
	for _, def in ipairs(self:Providers()) do names[#names + 1] = E:Translate(def.title) or def.key end
	if #names > 0 then print("  " .. L["Providers:"] .. " " .. table.concat(names, ", ")) end
end

---------------------------------------------------------------------------
-- Decoding with a small cache
---------------------------------------------------------------------------
local cache, cacheCount = {}, 0

local function Cached(kind, id, build)
	local bucket = cache[kind]
	if not bucket then
		bucket = {}
		cache[kind] = bucket
	end
	local value = bucket[id]
	if value == nil then
		if cacheCount >= CACHE_SIZE then
			wipe(cache)
			cacheCount = 0
			bucket = {}
			cache[kind] = bucket
		end
		value = build(id) or false
		bucket[id] = value
		cacheCount = cacheCount + 1
	end
	return value or nil
end

function LG:ClearDataCaches()
	wipe(cache)
	cacheCount = 0
	self.neededFor = nil
	self.eventIndex = nil
	self.mapIndex = nil
	self.sharedMaps = nil
	if self.ClearCatalogIndexes then self:ClearCatalogIndexes() end
end

-- Drop one kind of decoded record (after new observed data).
function LG:ClearDataCache(kind)
	cache[kind] = nil
end

local function Split(text, sep)
	local out = {}
	if type(text) ~= "string" or text == "" then return out end
	local start = 1
	while true do
		local stop = text:find(sep, start, true)
		if not stop then
			out[#out + 1] = text:sub(start)
			break
		end
		out[#out + 1] = text:sub(start, stop - 1)
		start = stop + 1
	end
	return out
end
LG.Split = Split

-- "12.5" / "-3" (quest-only drop) / "0.05" -> chance, questOnly
local function Chance(text)
	if type(text) ~= "string" or text == "" then return nil, false end
	local quest = text:sub(1, 1) == "-"
	return tonumber(quest and text:sub(2) or text), quest
end
LG.ParseChance = Chance

---------------------------------------------------------------------------
-- Data names in the player's language
--
-- LG:DataName(kind, id, english, bulk) is the one place a page, the search
-- or a tooltip gets the name of an item, creature, object, quest, zone or
-- instance. In order:
--   1. live from the client, when it already knows the name (never a
--      server request): item (C_Item.GetItemNameByID, cached items only),
--      quest (C_QuestLog.GetTitleForQuestID), zone (C_Map.GetMapInfo of a
--      uiMapID) and instance (GetRealZoneText of the instance map);
--   2. EldoUI_LootData's names in the client language (LD.L: items, mobs,
--      objects, quests; only built for the client's own language);
--   3. `english`, the name in the data.
-- Creature and object names have no live source without the unit itself.
-- The data is English, so on an English client items keep the data's
-- name, and `bulk` lookups (the search index, thousands of names) skip
-- the client for quests too.
---------------------------------------------------------------------------
local LOCALE_NAMES -- LD.L, only when it matches the client language

local function LocalName(kind, id)
	LOCALE_NAMES = LOCALE_NAMES or (LD and type(LD.L) == "table" and LD.L) or false
	local list = LOCALE_NAMES and LOCALE_NAMES[kind]
	return list and list[id]
end

local function EnglishClient()
	local code = GetLocale and GetLocale()
	return code == nil or code == "enUS" or code == "enGB"
end

local LIVE_NAME = {
	item = function(id)
		if EnglishClient() then return end
		if C_Item and C_Item.IsItemDataCachedByID and not C_Item.IsItemDataCachedByID(id) then return end
		return C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
	end,
	quest = function(id)
		return C_QuestLog and C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(id)
	end,
	zone = function(id)
		local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(id)
		return type(info) == "table" and info.name or nil
	end,
	instance = function(map)
		return GetRealZoneText and GetRealZoneText(map)
	end,
}
local LOCALE_KIND = { item = "items", mob = "mobs", object = "objects", quest = "quests" }

function LG:DataName(kind, id, english, bulk)
	if Secret(id) or type(id) == "nil" then return english end
	local live = LIVE_NAME[kind]
	if live and not (bulk and kind == "quest" and EnglishClient()) then
		local ok, name = pcall(live, id)
		if ok and type(name) == "string" and not Secret(name) and name ~= "" then return name end
	end
	local localKind = LOCALE_KIND[kind]
	local name = localKind and LocalName(localKind, id)
	if type(name) == "string" and name ~= "" then return name end
	return english
end

-- Loading EldoUI_LootData more than once (in tests) needs a reset: this
-- puts the module back to "not loaded yet". Never called by the addon.
function LG:ForgetData()
	LD, LOCALE_NAMES = nil, nil
	status, loadReason = "pending", nil
	self:ClearDataCaches()
	self:Fire("data")
end

-- Item record (Items.lua):
-- "name|quality|class|subclass|slot|itemLevel|reqLevel|classMask|raceMask|bind|skill:rank|stats|weapon|set|
--  spells|flags|startsQuest|faction:rank|honorRank|teaches"
-- flags: U unique, M mount, P companion pet, B<n> a bag with n slots.
-- WoW: Forever's PvP rank rewards (Data/PvPRewards.lua, client tables):
-- "name|quality|class|subclass|slot|itemLevel|reqLevel|classMask|side|set|faction:standing".
-- The loot data has none of them. The rank each needs comes from the game
-- (LG:PvPRewardRank), never from the item; a battleground reputation reward
-- names its faction and standing. WoW: Forever's own factions' rewards
-- (Data/ForeverFactions.lua, client tables) use the same record.
local function BuildPvPReward(itemID)
	local list = E.pvpRewards and E.pvpRewards.items
	local packed = list and list[itemID]
	local pvp = type(packed) == "string"
	if not pvp then
		list = E.foreverFactions and E.foreverFactions.items
		packed = list and list[itemID]
		if type(packed) ~= "string" then return end
	end
	local f = Split(packed, "|")
	local faction, standing = (f[11] or ""):match("^(%d+):(%d+)$")
	return {
		id = itemID, name = LG:DataName("item", itemID, f[1]), quality = tonumber(f[2]), class = tonumber(f[3]),
		subclass = tonumber(f[4]), invType = tonumber(f[5]), itemLevel = tonumber(f[6]), reqLevel = tonumber(f[7]),
		classMask = tonumber(f[8]), side = f[9] ~= "" and f[9] or nil, set = tonumber(f[10]), stats = {}, pvpReward = pvp or nil,
		repFaction = tonumber(faction), repStanding = tonumber(standing),
	}
end

-- WoW: Forever's own values over the Classic record (Data/ItemOverlay.lua,
-- generated from the client's item tables): name, quality, item level,
-- required level, bind, set, slot, weapon speed. An item whose primary
-- stats changed keeps none of its Classic stats, so nothing is scored on
-- stats it no longer has; the game's own numbers come once it caches the
-- item. A weapon with another speed keeps its Classic damage per second.
local function ApplyOverlay(record)
	local overlay = E.ItemOverlay
	local packed = overlay and overlay.items and overlay.items[record.id]
	if type(packed) ~= "string" then return record end
	local f = Split(packed, "|")
	if (f[1] or "") ~= "" then record.name = LG:DataName("item", record.id, f[1]) end
	record.quality = tonumber(f[2]) or record.quality
	record.itemLevel = tonumber(f[3]) or record.itemLevel
	record.reqLevel = tonumber(f[4]) or record.reqLevel
	record.bind = tonumber(f[5]) or record.bind
	local set = tonumber(f[6])
	if set then record.set = set > 0 and set or nil end
	record.invType = tonumber(f[7]) or record.invType
	if (f[8] or "") ~= "" then
		record.stats = {}
		record.foreverStats = f[8] ~= "-" and Split(f[8], ",") or {}
	end
	local speed = tonumber(f[9])
	local old = record.weapon and tonumber(record.weapon:match("@(%d+)$"))
	if speed and old and old > 0 then
		local ratio = speed / old
		record.weapon = record.weapon:gsub("(%d+)%-(%d+)", function(lo, hi)
			return ("%d-%d"):format(math.floor(tonumber(lo) * ratio + 0.5), math.floor(tonumber(hi) * ratio + 0.5))
		end):gsub("@%d+$", "@" .. speed)
	end
	return record
end

-- Published hotfixes can precede the client's exported item tables.
local function ApplyItemHotfix(record, itemID)
	local items = E.foreverData and E.foreverData.items
	local hotfix = items and items[itemID]
	if not hotfix then return record end
	record = record or { id = itemID, stats = {} }
	for _, field in ipairs({ "quality", "class", "subclass", "invType", "itemLevel", "reqLevel", "bind", "bagSlots" }) do
		if hotfix[field] ~= nil then record[field] = hotfix[field] end
	end
	if hotfix.name then record.name = LG:DataName("item", itemID, hotfix.name) end
	return record
end

local function BuildItem(itemID)
	local packed = LD and LD.items and LD.items[itemID]
	if type(packed) ~= "string" then return ApplyItemHotfix(BuildPvPReward(itemID), itemID) end
	-- An item the WoW: Forever client does not have is left out everywhere.
	local overlay = E.ItemOverlay
	if overlay and overlay.missing and overlay.missing[itemID] then return end
	local f = Split(packed, "|")
	local flags = f[16] or ""
	local record = {
		id = itemID, name = LG:DataName("item", itemID, f[1]), quality = tonumber(f[2]), class = tonumber(f[3]),
		subclass = tonumber(f[4]), invType = tonumber(f[5]), itemLevel = tonumber(f[6]), reqLevel = tonumber(f[7]),
		classMask = tonumber(f[8]), raceMask = tonumber(f[9]), bind = tonumber(f[10]),
		weapon = f[13] ~= "" and f[13] or nil, set = tonumber(f[14]), unique = flags:find("U", 1, true) ~= nil,
		mount = flags:find("M", 1, true) ~= nil, pet = flags:find("P", 1, true) ~= nil,
		bagSlots = tonumber(flags:match("B(%d+)")), startsQuest = tonumber(f[17]),
		honorRank = tonumber(f[19]), teaches = tonumber(f[20]),
	}
	-- The database counts PvP ranks from 5 (Private, rank 1) to 18 (Grand
	-- Marshal / High Warlord, rank 14); players know the rank number.
	if record.honorRank and record.honorRank >= 5 then record.honorRank = record.honorRank - 4 end
	local faction, standing = (f[18] or ""):match("^(%d+):(%d+)$")
	if not faction then
		-- A Classic item a WoW: Forever faction now sells (client tables).
		local forever = E.foreverFactions and E.foreverFactions.items and E.foreverFactions.items[itemID]
		faction, standing = (type(forever) == "string" and Split(forever, "|")[11] or ""):match("^(%d+):(%d+)$")
	end
	if faction then record.repFaction, record.repStanding = tonumber(faction), tonumber(standing) end
	local skill, rank = (f[11] or ""):match("^(%d+):(%d+)$")
	if skill then record.skill, record.skillRank = tonumber(skill), tonumber(rank) end
	local stats = {}
	for _, pair in ipairs(Split(f[12], ",")) do
		local key, value = pair:match("^([%w_]+)=(%-?%d+)$")
		if key then stats[key] = tonumber(value) end
	end
	record.stats = stats
	return ApplyItemHotfix(ApplyOverlay(record), itemID)
end

function LG:ItemRecord(itemID)
	itemID = tonumber(itemID)
	if not itemID or not LD then return end
	return Cached("item", itemID, BuildItem)
end

function LG:ItemNote(itemID)
	local notes = LD and LD.itemNotes
	return notes and notes[tonumber(itemID)]
end

-- Creature record (Creatures.lua):
-- "name|minLevel|maxLevel|rank|instanceKey|displayID|spawnCount|creatureType|tameFamily"
-- tameFamily: the pet family of a beast a Hunter can tame (none on others).
-- A WoW: Forever creature the loot data lacks, from the Forever overlay's
-- rares (name, level and the map it was seen on).
local function OverlayMob(npc)
	local rares = E.foreverData and E.foreverData.rares
	local rare = type(rares) == "table" and rares[npc]
	if type(rare) ~= "table" or type(rare.name) ~= "string" then return end
	local level = tonumber(rare.level)
	return { id = npc, name = rare.name, minLevel = level, maxLevel = level, rank = 0, spawns = 0, forever = true,
		map = tonumber(rare.map), x = tonumber(rare.x), y = tonumber(rare.y) }
end

local function BuildMob(npc)
	local packed = LD and LD.mobs and LD.mobs[npc]
	if type(packed) ~= "string" then return OverlayMob(npc) end
	local f = Split(packed, "|")
	local family = tonumber(f[9])
	return {
		id = npc, name = LG:DataName("mob", npc, f[1]), minLevel = tonumber(f[2]), maxLevel = tonumber(f[3]),
		rank = tonumber(f[4]) or 0, instance = f[5] ~= "" and f[5] or nil, display = tonumber(f[6]),
		spawns = tonumber(f[7]) or 0, creatureType = tonumber(f[8]),
		family = family and family > 0 and family or nil, tameable = family ~= nil and family > 0,
	}
end

-- The name of a pet family: the game's own, else the name it has in
-- WoW: Forever.
local FAMILY_NAMES = {
	[1] = E.Key("Wolf"), [2] = E.Key("Cat"), [3] = E.Key("Spider"), [4] = E.Key("Bear"), [5] = E.Key("Boar"),
	[6] = E.Key("Crocolisk"), [7] = E.Key("Carrion Bird"), [8] = E.Key("Crab"), [9] = E.Key("Gorilla"),
	[11] = E.Key("Raptor"), [12] = E.Key("Tallstrider"), [20] = E.Key("Scorpid"), [21] = E.Key("Turtle"),
	[24] = E.Key("Bat"), [25] = E.Key("Hyena"), [26] = E.Key("Owl"), [27] = E.Key("Wind Serpent"),
}
function LG:FamilyName(family)
	family = tonumber(family)
	if not family then return nil end
	local api = rawget(_G, "C_CreatureInfo")
	local info = type(api) == "table" and api.GetCreatureFamilyInfo
	if type(info) == "function" then
		local ok, data = pcall(info, family)
		local name = ok and type(data) == "table" and data.name
		if type(name) == "string" and not Secret(name) and name ~= "" then return name end
	end
	return FAMILY_NAMES[family] and L[FAMILY_NAMES[family]] or nil
end

function LG:Mob(npc)
	npc = tonumber(npc)
	if not npc or not LD then return end
	return Cached("mob", npc, BuildMob)
end

-- Object record: "name|type"
function LG:ObjectName(objectID)
	objectID = tonumber(objectID)
	local packed = objectID and LD and LD.objects and LD.objects[objectID]
	if type(packed) ~= "string" then return end
	return LG:DataName("object", objectID, Split(packed, "|")[1])
end

-- Instance names: the client's own (localized) zone name when it knows the
-- map, else the LootData name. Where several records share one map (the
-- wings of Dire Maul, Scarlet Monastery, Blackrock Spire and Stratholme),
-- the client knows only the whole place, so the record's own name keeps
-- the wing.
function LG:Instance(key)
	local list = LD and LD.instances
	return list and list[key]
end

function LG:MapShared(map)
	if not (LD and LD.instances and map) then return false end
	local shared = self.sharedMaps
	if not shared then
		local count = {}
		for _, inst in pairs(LD.instances) do
			if inst.map then count[inst.map] = (count[inst.map] or 0) + 1 end
		end
		shared = {}
		for id, n in pairs(count) do
			if n > 1 then shared[id] = true end
		end
		self.sharedMaps = shared
	end
	return shared[map] or false
end

function LG:InstanceName(key)
	local inst = self:Instance(key)
	if not inst then return end
	if inst.name and self:MapShared(inst.map) then return inst.name end
	return self:DataName("instance", inst.map, inst.name)
end

-- The instance a map ID belongs to (GetInstanceInfo's instanceID).
function LG:InstanceForMap(mapID)
	if not (LD and LD.instances and mapID) then return end
	local index = self.mapIndex
	if not index then
		index = {}
		for key, inst in pairs(LD.instances) do
			if inst.map and not index[inst.map] then index[inst.map] = key end
		end
		self.mapIndex = index
	end
	return index[mapID]
end

-- Dungeons (and raids with `raids`) whose level range fits `level`, best
-- fit first: { { key, name, min, max }, ... } up to `limit`.
function LG:InstancesForLevel(level, limit, raids)
	if Secret(level) or not level then return {} end
	local list = {}
	if not (LD and LD.instances) then
		-- Without EldoUI_LootData: the dungeon finder's list (live).
		for _, inst in ipairs(self:LiveInstances()) do
			local fits = raids or not (inst.size and inst.size > 5)
			if fits and inst.min and inst.max and level >= inst.min - 2 and level <= inst.max + 3 then
				list[#list + 1] = { key = "lfg:" .. inst.id, name = inst.name, min = inst.min, max = inst.max }
			end
		end
	end
	for key, inst in pairs(LD and LD.instances or {}) do
		local fits = raids or inst.kind ~= "raid"
		if fits and inst.min and inst.max and level >= inst.min - 2 and level <= inst.max + 3 then
			list[#list + 1] = { key = key, name = self:InstanceName(key) or key, min = inst.min, max = inst.max }
		end
	end
	table.sort(list, function(a, b)
		local da = math.abs((a.min + a.max) / 2 - level)
		local db = math.abs((b.min + b.max) / 2 - level)
		if da ~= db then return da < db end
		return a.name < b.name
	end)
	while limit and #list > limit do table.remove(list) end
	return list
end

-- Quest title: the client's (localized) when it has it, else LootData's.
function LG:QuestTitle(questID)
	questID = tonumber(questID)
	if not questID then return end
	local packed = LD and LD.quests and LD.quests[questID]
	return self:DataName("quest", questID, type(packed) == "string" and Split(packed, "|")[1] or nil)
end

function LG:QuestLevel(questID)
	local packed = LD and LD.quests and LD.quests[tonumber(questID)]
	if type(packed) ~= "string" then return end
	local f = Split(packed, "|")
	return tonumber(f[2]), tonumber(f[3])
end

---------------------------------------------------------------------------
-- Vendors, crafts, tokens, world events and phases (Vendors.lua,
-- Recipes.lua, Quests.lua's tokens, Events.lua). Every reader returns nil
-- when EldoUI_LootData is not loaded.
---------------------------------------------------------------------------
local function IdList(text)
	local list, more = {}, 0
	for _, part in ipairs(Split(text, ",")) do
		if part:sub(1, 1) == "+" then
			more = tonumber(part:sub(2)) or 0
		else
			local id = tonumber((part:gsub("%*$", "")))
			if id then list[#list + 1] = id end
		end
	end
	return list, more
end

-- Vendors that sell an item: { npcID, ... }, more (LootData lists 8 at most).
function LG:Vendors(itemID)
	itemID = tonumber(itemID)
	local packed = itemID and LD and LD.vendorByItem and LD.vendorByItem[itemID]
	if type(packed) ~= "string" then return end
	return IdList(packed)
end

-- What a vendor sells: { [itemID] = limited (true when supply is limited) }.
function LG:VendorItems(npc)
	npc = tonumber(npc)
	if not npc or not LD then return end
	return Cached("vendorItems", npc, function(id)
		local packed = LD.vendors and LD.vendors[id]
		if type(packed) ~= "string" then return false end
		local items = {}
		for _, part in ipairs(Split(packed, ",")) do
			local item, star = part:match("^(%d+)(%*?)$")
			if item then items[tonumber(item)] = star == "*" end
		end
		return items
	end)
end

-- Vendor price in copper: the one you saw at a vendor, else LootData's.
function LG:Price(itemID)
	itemID = tonumber(itemID)
	if not itemID then return end
	local seen = self:SeenVendorCost(itemID)
	if seen and seen.gold then return seen.gold, true end
	local price = LD and LD.price and LD.price[itemID]
	return tonumber(price), false
end

-- Craft spell: { id, result, count, reagents = { { id, count } }, skill,
-- rank, recipes = { itemID, ... }, trainer = { skill, value, cost, level,
-- npcs = { npcID, ... } } or nil }. result 0 = an enchant.
local function CraftNumber(value, minimum)
	if type(value) == "number" and not Secret(value) and value == value
		and value >= minimum and value <= 2147483647 and value % 1 == 0 then return value end
end

local CRAFT_FIELDS = { count = 0, skill = 1, rank = 0, numSkillUps = 1 }

local function NewCraft(spellID, facts)
	if type(facts) ~= "table" or type(facts.source) ~= "string" or facts.source == "" then return end
	local craft = { id = spellID, result = CraftNumber(facts.result, 0), reagents = {}, recipes = {} }
	if not craft.result or type(facts.reagents) ~= "table" then return end
	for field, minimum in pairs(CRAFT_FIELDS) do
		craft[field] = CraftNumber(facts[field], minimum)
		if craft[field] == nil then return end
	end
	if craft.result ~= 0 and craft.count == 0 then return end
	if craft.result == 0 and craft.count ~= 0 then return end
	craft.learnConfirmed = true
	craft.yellow, craft.grey = CraftNumber(facts.yellow, 0), CraftNumber(facts.grey, 0)
	if not (craft.yellow and craft.grey and craft.yellow < craft.grey) then return end
	for item, count in pairs(facts.reagents) do
		if not CraftNumber(item, 1) or not CraftNumber(count, 1) then return end
		craft.reagents[#craft.reagents + 1] = { id = item, count = count }
	end
	if #craft.reagents == 0 and not (craft.result == 0 and craft.count == 0) then return end
	table.sort(craft.reagents, function(a, b) return a.id < b.id end)
	return craft
end

local function DecodeCraft(spellID)
	local packed = LD and LD.crafts and LD.crafts[spellID]
	local hotfix = E.foreverData and E.foreverData.crafts and E.foreverData.crafts[spellID]
	if type(packed) ~= "string" then return NewCraft(spellID, hotfix) end
	local f = Split(packed, "|")
	local result, count = (f[1] or ""):match("^(%d+):(%d+)$")
	local craft = { id = spellID, result = tonumber(result) or 0, count = tonumber(count) or 1, reagents = {}, recipes = {} }
	for _, pair in ipairs(Split(f[2], ",")) do
		local item, n = pair:match("^(%d+):(%d+)$")
		if item then craft.reagents[#craft.reagents + 1] = { id = tonumber(item), count = tonumber(n) } end
	end
	local skill, rank = (f[3] or ""):match("^(%d+):(%d+)$")
	craft.skill, craft.rank = tonumber(skill), tonumber(rank)
	craft.recipes = IdList(f[4])
	local train = LD.trainer and LD.trainer[spellID]
	if type(train) == "string" then
		local t = Split(train, "|")
		local tskill, value = (t[1] or ""):match("^(%d+):(%d+)$")
		local set = LD.trainerSets and LD.trainerSets[tonumber(t[4])]
		craft.trainer = { skill = tonumber(tskill), value = tonumber(value), cost = tonumber(t[2]), level = tonumber(t[3]),
			npcs = IdList(set) }
		craft.skill = craft.skill or craft.trainer.skill
		craft.rank = craft.rank or craft.trainer.value
	end
	if hotfix and hotfix.result == craft.result then
		if hotfix.reagentsComplete == true then
			local replacement = NewCraft(spellID, hotfix)
			if not replacement then return craft end
			replacement.recipes, replacement.trainer = craft.recipes, craft.trainer
			return replacement
		end
		if type(hotfix.reagents) == "table" then
			for _, reagent in ipairs(craft.reagents) do
				reagent.count = CraftNumber(hotfix.reagents[reagent.id], 1) or reagent.count
			end
		end
		for field, minimum in pairs(CRAFT_FIELDS) do
			local value = CraftNumber(hotfix[field], minimum)
			if field == "count" then
				if value and ((craft.result == 0 and value == 0) or (craft.result ~= 0 and value > 0)) then craft.count = value end
			else
				craft[field] = value or craft[field]
			end
		end
		if CraftNumber(hotfix.rank, 0) and type(hotfix.source) == "string" and hotfix.source ~= "" then
			craft.learnConfirmed = true
		end
		local yellow, grey = CraftNumber(hotfix.yellow, 0), CraftNumber(hotfix.grey, 0)
		if yellow and grey and yellow < grey then
			craft.yellow, craft.grey = yellow, grey
		end
	end
	return craft
end

function LG:ApplyCraftLearnRank(craft)
	if not craft then return end
	local source = E.recipeThresholds and E.recipeThresholds[craft.id]
	if source and source[1] == craft.skill and source[4] > 0 then
		craft.rank, craft.learnConfirmed = source[4], true
	end
	return craft
end

local function BuildCraft(spellID)
	return LG:ApplyCraftLearnRank(DecodeCraft(spellID))
end

function LG:Craft(spellID)
	spellID = tonumber(spellID)
	if not spellID then return end
	return Cached("craft", spellID, BuildCraft)
end

-- The craft a recipe item teaches.
function LG:Recipe(itemID)
	local record = self:ItemRecord(itemID)
	return record and record.teaches and self:Craft(record.teaches)
end

-- Gear a quest gives for a token item: { { classMask, itemID }, ... }
-- (classMask 0 = any class).
function LG:TokenRewards(tokenItemID)
	tokenItemID = tonumber(tokenItemID)
	local packed = tokenItemID and LD and LD.tokens and LD.tokens[tokenItemID]
	if type(packed) ~= "string" then return end
	local list = {}
	for _, pair in ipairs(Split(packed, ",")) do
		local mask, item = pair:match("^(%d+):(%d+)$")
		if item then list[#list + 1] = { classMask = tonumber(mask), itemID = tonumber(item) } end
	end
	return list
end

-- World events (Classic schedule): { id, name, every, length (minutes),
-- holiday, phase, vendors = {npcID...}, quests = {questID...}, mobs = {npcID...} }.
local function BuildEvent(eventID)
	local raw = LD and LD.events and LD.events[eventID]
	if type(raw) ~= "table" then return end
	return {
		id = eventID, name = raw.name, every = raw.every, length = raw.length, holiday = raw.holiday, phase = raw.phase,
		vendors = (IdList(raw.vendors)), quests = (IdList(raw.quests)), mobs = (IdList(raw.mobs)),
	}
end

function LG:Event(eventID)
	eventID = tonumber(eventID)
	if not eventID or not LD then return end
	return Cached("event", eventID, BuildEvent)
end

function LG:Events()
	local list = {}
	local skip = self.EVENTS_NOT_ON_FOREVER or {}
	if LD and type(LD.events) == "table" then
		for eventID in pairs(LD.events) do
			if not skip[eventID] then list[#list + 1] = self:Event(eventID) end
		end
	end
	table.sort(list, function(a, b) return (a.name or "") < (b.name or "") end)
	return list
end

-- The world event a vendor, quest or mob belongs to ("npc" or "quest").
function LG:EventFor(kind, id)
	if not LD then return end
	local index = self.eventIndex
	if not index then
		index = { npc = {}, quest = {} }
		for _, event in ipairs(self:Events()) do
			for _, npc in ipairs(event.vendors) do index.npc[npc] = index.npc[npc] or event.id end
			for _, npc in ipairs(event.mobs) do index.npc[npc] = index.npc[npc] or event.id end
			for _, quest in ipairs(event.quests) do index.quest[quest] = index.quest[quest] or event.id end
		end
		self.eventIndex = index
	end
	return index[kind] and index[kind][tonumber(id)]
end

-- Content phases (Classic release order; WoW: Forever may differ):
-- { [phase] = { name, note } } or nil.
function LG:Phases()
	return LD and type(LD.phases) == "table" and LD.phases or nil
end

function LG:RoleNote(role)
	return LD and type(LD.roleNotes) == "table" and LD.roleNotes[role] or nil
end

-- Quest record fields 26/27: reputation the quest needs ("faction:value").
function LG:QuestReputation(questID)
	local packed = LD and LD.quests and LD.quests[tonumber(questID)]
	if type(packed) ~= "string" then return end
	local f = Split(packed, "|")
	local faction, value = (f[26] or ""):match("^(%d+):(%-?%d+)$")
	return tonumber(faction), tonumber(value)
end

function LG:QuestInstance(questID)
	local packed = LD and LD.quests and LD.quests[tonumber(questID)]
	if type(packed) ~= "string" then return end
	local key = Split(packed, "|")[7]
	return key ~= "" and key or nil
end

---------------------------------------------------------------------------
-- Item sources
-- LG:ItemSources(itemID) -> list, more
--   { kind = "npc" | "object", id, chance, questOnly, name, instance (key),
--     rank, minLevel, maxLevel }   drops, best chance first
--   { kind = "world", minLevel, maxLevel, chance }   random world drop
--   { kind = "quest" | "choice", id }   quest rewards
--   { kind = "vendor" | "repvendor" | "pvpvendor", id = npcID, name, price,
--     limited, faction, standing (repvendor), honorRank (pvpvendor), seen,
--     cost = { { id, amount, currency } } (seen extended costs) }
--   { kind = "crafted", id = craft spellID, skill, rank, learn = "trainer" | "recipe" }
--   { kind = "token", id = token itemID, classMask }
--   more = number of drop sources LootData left out
-- Every entry may carry `event` (a world event id) and `phase`.
---------------------------------------------------------------------------
local function VendorEntry(itemID, npc, record)
	local entry = { kind = "vendor", id = npc }
	local mob = LG:Mob(npc)
	entry.name = mob and mob.name
	if record and record.repFaction then
		entry.kind, entry.faction, entry.standing = "repvendor", record.repFaction, record.repStanding
	elseif record and record.honorRank and record.honorRank > 0 then
		entry.kind, entry.honorRank = "pvpvendor", record.honorRank
	end
	local sold = LG:VendorItems(npc)
	entry.limited = sold and sold[itemID] or nil
	entry.price = LG:Price(itemID)
	entry.event = LG:EventFor("npc", npc)
	return entry
end

local function BuildSources(itemID)
	local list, more = {}, 0
	local packed = LD and LD.sources and LD.sources[itemID]
	local record = LD and LG:ItemRecord(itemID)
	local vendorsDone
	for _, part in ipairs(Split(type(packed) == "string" and packed or "", ",")) do
		local kind, ident, chance = part:match("^([no])(%d+):(.+)$")
		if kind then
			local value, questOnly = Chance(chance)
			local entry = { kind = kind == "n" and "npc" or "object", id = tonumber(ident), chance = value, questOnly = questOnly }
			if kind == "n" then
				local mob = LG:Mob(entry.id)
				if mob then
					entry.name, entry.instance, entry.rank = mob.name, mob.instance, mob.rank
					entry.minLevel, entry.maxLevel = mob.minLevel, mob.maxLevel
				end
				entry.event = LG:EventFor("npc", entry.id)
			else
				entry.name = LG:ObjectName(entry.id)
			end
			list[#list + 1] = entry
		elseif part:sub(1, 1) == "+" then
			more = tonumber(part:sub(2)) or 0
		elseif part == "w" then
			local band = LD.worldDrops and LD.worldDrops[itemID]
			local lo, hi, chanceText
			if type(band) == "string" then lo, hi, chanceText = band:match("^(%d+)%-(%d+):(.+)$") end
			list[#list + 1] = { kind = "world", minLevel = tonumber(lo), maxLevel = tonumber(hi), chance = tonumber(chanceText) }
		elseif part == "v" then
			vendorsDone = true
			local npcs = LG:Vendors(itemID) or {}
			for _, npc in ipairs(npcs) do list[#list + 1] = VendorEntry(itemID, npc, record) end
		else
			local letter, number = part:match("^([qckt])(%d+)$")
			number = tonumber(number)
			if letter == "q" or letter == "c" then
				list[#list + 1] = { kind = letter == "q" and "quest" or "choice", id = number, event = LG:EventFor("quest", number) }
			elseif letter == "k" then
				local craft = LG:Craft(number)
				list[#list + 1] = { kind = "crafted", id = number, skill = craft and craft.skill, rank = craft and craft.rank,
					learn = craft and (craft.trainer and "trainer" or "recipe") or nil }
			elseif letter == "t" then
				local mask = 0
				for _, reward in ipairs(LG:TokenRewards(number) or {}) do
					if reward.itemID == itemID then mask = reward.classMask break end
				end
				list[#list + 1] = { kind = "token", id = number, classMask = mask }
			end
		end
	end
	-- Prices you saw at a vendor LootData does not know (or with no LootData).
	local seen = LG:SeenVendorCost(itemID)
	if seen and seen.npc then
		local found
		for _, entry in ipairs(list) do
			if entry.id == seen.npc and (entry.kind == "vendor" or entry.kind == "repvendor" or entry.kind == "pvpvendor") then
				entry.seen, entry.cost, found = true, seen.cost, true
			end
		end
		if not found then
			local entry = LD and VendorEntry(itemID, seen.npc, record) or { kind = "vendor", id = seen.npc }
			entry.name = entry.name or seen.name
			entry.price, entry.cost, entry.seen = seen.gold, seen.cost, true
			list[#list + 1] = entry
		end
	end
	if #list == 0 and not vendorsDone then return end
	for _, entry in ipairs(list) do entry.phase = LG:SourcePhase(entry) end
	return { list = list, more = more }
end

function LG:ItemSources(itemID)
	itemID = tonumber(itemID)
	if not itemID then return end
	local entry = Cached("sources", itemID, BuildSources)
	if entry then return entry.list, entry.more end
end

-- The step of WoW: Forever's schedule a source opens with (Phases.lua):
-- its instance's, or a quest's instance's; a token follows its own
-- sources; anything else is open since launch (1).
function LG:SourcePhase(entry, depth)
	if not LD or type(entry) ~= "table" or not self.InstanceStep then return end
	depth = depth or 0
	local phase = 1
	local function Max(value) if tonumber(value) and value > phase then phase = value end end
	if entry.instance then Max(self:InstanceStep(entry.instance)) end
	if (entry.kind == "quest" or entry.kind == "choice") and entry.id then
		local key = self:QuestInstance(entry.id)
		if key then Max(self:InstanceStep(key)) end
	elseif entry.kind == "token" and depth < 2 then
		Max(self:ItemPhase(entry.id, depth + 1))
	end
	return phase
end

-- The earliest step any source of an item opens with.
function LG:ItemPhase(itemID, depth)
	if not LD then return end
	if (depth or 0) > 0 then
		-- Inside a token: read its sources without the cache (no loops).
		local best
		local packed = LD.sources and LD.sources[tonumber(itemID)]
		for _, part in ipairs(Split(packed, ",")) do
			local npc = tonumber(part:match("^n(%d+):"))
			local mob = npc and self:Mob(npc)
			local phase = self:SourcePhase({ instance = mob and mob.instance, event = npc and self:EventFor("npc", npc) }, depth)
			if phase and (not best or phase < best) then best = phase end
		end
		return best
	end
	local list = self:ItemSources(itemID)
	local best
	for _, entry in ipairs(list or {}) do
		if entry.phase and (not best or entry.phase < best) then best = entry.phase end
	end
	return best
end

-- Quests that ask for an item (built once, the first time it is needed).
local function NeededIndex()
	if LG.neededFor then return LG.neededFor end
	local index = {}
	if LD and LD.quests then
		for questID, packed in pairs(LD.quests) do
			if type(packed) == "string" then
				-- field 15: "itemID:count,..."
				local f = Split(packed, "|")
				for _, pair in ipairs(Split(f[15], ",")) do
					local item = tonumber(pair:match("^(%d+)"))
					if item then
						index[item] = index[item] or {}
						table.insert(index[item], questID)
					end
				end
			end
		end
	end
	LG.neededFor = index
	return index
end

-- { rewards = { questID, ... }, needed = { questID, ... }, starts = questID }
function LG:ItemQuests(itemID)
	itemID = tonumber(itemID)
	if not itemID or not LD then return end
	return Cached("quests", itemID, function(id)
		local result = { rewards = {}, needed = {} }
		local rewards = LD.questByItem and LD.questByItem[id]
		for _, questID in ipairs(Split(rewards, ",")) do
			result.rewards[#result.rewards + 1] = tonumber(questID)
		end
		for _, questID in ipairs(NeededIndex()[id] or {}) do result.needed[#result.needed + 1] = questID end
		table.sort(result.needed)
		local record = LG:ItemRecord(id)
		result.starts = record and record.startsQuest
		if #result.rewards == 0 and #result.needed == 0 and not result.starts then return false end
		return result
	end)
end

-- Does the Loot Guide show where this item comes from? MobInfo asks this
-- (through E:LootGuideKnows) so a tooltip never shows the same drops twice.
function LG:KnowsItem(itemID)
	if not self.active or not LD then return false end
	local list = self:ItemSources(itemID)
	return list ~= nil and #list > 0
end

function E:LootGuideKnows(itemID)
	if Secret(itemID) then return false end
	if not LG:KnowsItem(itemID) then return false end
	return not E.TooltipSectionShown or E:TooltipSectionShown("lootSource")
end

---------------------------------------------------------------------------
-- Observed drops (Mob and Loot Info)
---------------------------------------------------------------------------
-- MobInfo stores what the player looted; its reader
-- MobInfo:GetItemDrops(itemID) lists the creatures that dropped the item.
-- A creature you looted without that drop is read from the saved store
-- (format 1: mobs[npc] = { n = name, k = kills, i = { [itemID] = drops } }),
-- never written.
function LG:ObservedAvailable()
	local mobInfo = E:GetModule("MobInfo")
	return mobInfo and mobInfo:IsEnabled() and true or false
end

-- drops, kills for one creature and item, or nil when never seen.
function LG:Seen(npc, itemID)
	npc, itemID = tonumber(npc), tonumber(itemID)
	if not npc or not itemID then return end
	local mobInfo = E:GetModule("MobInfo")
	if mobInfo and type(mobInfo.GetItemDrops) == "function" then
		local ok, list = pcall(mobInfo.GetItemDrops, mobInfo, itemID)
		if ok and type(list) == "table" then
			for _, row in ipairs(list) do
				if row.npc == npc then return row.drops, row.kills end
			end
		end
	end
	local store = type(EldoUIDB) == "table" and EldoUIDB.mobInfo
	if type(store) ~= "table" or store.v ~= 1 or type(store.mobs) ~= "table" then return end
	local mob = store.mobs[npc]
	local kills = type(mob) == "table" and tonumber(mob.k)
	if not kills or kills <= 0 then return end
	local drops = type(mob.i) == "table" and tonumber(mob.i[itemID]) or 0
	return drops, kills
end

---------------------------------------------------------------------------
-- Stats for E.ItemScore from a LootData record (items the client has not
-- cached yet). Only stats whose meaning is the same in both worlds are
-- handed over. Percent bonuses (crit, hit, dodge, parry, block) go to the
-- item score's percent keys, the same ones its tooltip reading fills.
---------------------------------------------------------------------------
local STAT_KEYS = {
	str = "ITEM_MOD_STRENGTH_SHORT", agi = "ITEM_MOD_AGILITY_SHORT", sta = "ITEM_MOD_STAMINA_SHORT",
	int = "ITEM_MOD_INTELLECT_SHORT", spi = "ITEM_MOD_SPIRIT_SHORT", arm = "RESISTANCE0_NAME",
	ap = "ITEM_MOD_ATTACK_POWER_SHORT", rap = "ITEM_MOD_RANGED_ATTACK_POWER_SHORT",
	spd = "ITEM_MOD_SPELL_POWER_SHORT", heal = "ITEM_MOD_SPELL_HEALING_DONE_SHORT",
	mp5 = "ITEM_MOD_MANA_REGENERATION_SHORT", hp5 = "ITEM_MOD_HEALTH_REGEN_SHORT",
	blk = "ITEM_MOD_BLOCK_VALUE_SHORT",
	crit = "PCT_CRIT", hit = "PCT_HIT", scrit = "PCT_SPELL_CRIT", shit = "PCT_SPELL_HIT",
	dodge = "PCT_DODGE", parry = "PCT_PARRY", block = "PCT_BLOCK",
}

local function RecordStats(itemID)
	if not LG.active then return end
	local record = LG:ItemRecord(itemID)
	if not record then return end
	local stats = {}
	for key, value in pairs(record.stats) do
		local name = STAT_KEYS[key]
		if name and value ~= 0 then stats[name] = (stats[name] or 0) + value end
	end
	-- Weapon DPS: "min-max[+min-max:school...]@delay" (delay in ms).
	local weapon = record.weapon
	if weapon then
		local delay = tonumber(weapon:match("@(%d+)$"))
		if delay and delay > 0 then
			local total = 0
			for lo, hi in weapon:gmatch("(%d+)%-(%d+)") do total = total + (tonumber(lo) + tonumber(hi)) / 2 end
			if total > 0 then stats.ITEM_MOD_DAMAGE_PER_SECOND_SHORT = total / (delay / 1000) end
		end
	end
	return next(stats) and stats or nil
end

if E.ItemScore and E.ItemScore.RegisterStatsProvider then
	E.ItemScore:RegisterStatsProvider(RecordStats)
end

---------------------------------------------------------------------------
-- Item loader: rows on screen ask for item data they lack.
-- LG:RequestItem(itemID, fn) -> true when the data is already there.
---------------------------------------------------------------------------
local MAX_IN_FLIGHT = 8
local PER_SECOND = 20
local queue, queued, inFlight, waiting = {}, {}, {}, {}
local inFlightCount = 0
local sentTimes = {}   -- when the requests of the last second went out (a sliding window)
local pumpQueued = false

local function IsCached(itemID)
	if C_Item.IsItemDataCachedByID then
		local ok, cached = pcall(C_Item.IsItemDataCachedByID, itemID)
		if ok then return cached and true or false end
	end
	return C_Item.GetItemInfo(itemID) ~= nil
end

local Pump

local function Done(itemID)
	if inFlight[itemID] then
		inFlight[itemID] = nil
		inFlightCount = math.max(inFlightCount - 1, 0)
	end
	local callbacks = waiting[itemID]
	waiting[itemID] = nil
	if callbacks then
		for _, fn in ipairs(callbacks) do
			local ok, err = pcall(fn, itemID)
			if not ok then geterrorhandler()(err) end
		end
	end
	LG:Fire("items")
	if not pumpQueued then
		pumpQueued = true
		C_Timer.After(0, Pump)
	end
end

function Pump()
	pumpQueued = false
	local now = GetTime()
	while sentTimes[1] and now - sentTimes[1] >= 1 do table.remove(sentTimes, 1) end
	while #queue > 0 and inFlightCount < MAX_IN_FLIGHT and #sentTimes < PER_SECOND do
		local itemID = table.remove(queue, 1)
		queued[itemID] = nil
		if IsCached(itemID) then
			Done(itemID)
		else
			inFlight[itemID] = now
			inFlightCount = inFlightCount + 1
			sentTimes[#sentTimes + 1] = now
			if C_Item.RequestLoadItemDataByID then
				pcall(C_Item.RequestLoadItemDataByID, itemID)
			else
				C_Item.GetItemInfo(itemID)
			end
		end
	end
	-- Requests the server never answers free their slot after 10 s.
	for itemID, sent in pairs(inFlight) do
		if now - sent > 10 then Done(itemID) end
	end
	if (#queue > 0 or inFlightCount > 0) and not pumpQueued then
		pumpQueued = true
		C_Timer.After(0.25, Pump)
	end
end

function LG:RequestItem(itemID, fn)
	itemID = tonumber(itemID)
	if Secret(itemID) or not itemID then return false end
	if IsCached(itemID) then return true end
	if fn then
		waiting[itemID] = waiting[itemID] or {}
		table.insert(waiting[itemID], fn)
	end
	if not queued[itemID] and not inFlight[itemID] then
		queued[itemID] = true
		queue[#queue + 1] = itemID
	end
	if not pumpQueued then
		pumpQueued = true
		C_Timer.After(0, Pump)
	end
	return false
end

-- Drop requests for rows that left the screen (a page calls this when it
-- redraws with a new list).
function LG:CancelItemRequests()
	for _, itemID in ipairs(queue) do queued[itemID] = nil; waiting[itemID] = nil end
	wipe(queue)
end

function LG:LoaderStats()
	local now = GetTime()
	local recent = 0
	for _, sent in ipairs(sentTimes) do
		if now - sent < 1 then recent = recent + 1 end
	end
	return inFlightCount, #queue, recent
end

local function OnItemData(_, itemID, success)
	itemID = tonumber(itemID)
	if Secret(itemID) or not itemID then return end
	if inFlight[itemID] or waiting[itemID] then
		if success == false then waiting[itemID] = nil end
		Done(itemID)
	end
end
LG:Listen("GET_ITEM_INFO_RECEIVED", "loader", OnItemData)
LG:Listen("ITEM_DATA_LOAD_RESULT", "loader", OnItemData)

-- A non-English client that caches an item learns its name: a decoded
-- record built before that keeps the data's name, so it is dropped and
-- built again with LG:DataName. Never asks the server for anything.
-- Pages that keep their own rows take the new names with
-- LG:TakeRenamedItems() (the "itemnames" message says there are some).
-- A renamed item's name is also kept apart from the record cache, so a
-- later rename is still noticed after a long browse cleared the cache.
local renamedItems = {}
local givenNames = {}   -- itemID -> the name the last rename handed out

local function OnItemName(_, itemID, success)
	itemID = tonumber(itemID)
	if Secret(itemID) or not itemID or success == false or EnglishClient() then return end
	local bucket = cache.item
	local record = bucket and bucket[itemID]
	local shown = record and record.name or givenNames[itemID]
	if not shown then return end
	local name = LG:DataName("item", itemID, shown)
	if type(name) ~= "string" or name == shown then return end
	if record then
		bucket[itemID] = nil
		cacheCount = math.max(0, cacheCount - 1)
	end
	renamedItems[itemID] = name
	givenNames[itemID] = name
	LG:Fire("itemnames")
end
LG:Listen("GET_ITEM_INFO_RECEIVED", "itemnames", OnItemName)
LG:Listen("ITEM_DATA_LOAD_RESULT", "itemnames", OnItemName)

-- { [itemID] = new name } since the last call, or nil.
function LG:TakeRenamedItems()
	if not next(renamedItems) then return nil end
	local out = renamedItems
	renamedItems = {}
	return out
end

---------------------------------------------------------------------------
-- Observed vendor costs: what an open merchant asks for its items,
-- read once per vendor per session on MERCHANT_SHOW. Read-only: nothing
-- here buys, sells or clicks.
-- EldoUIDB.lootGuideCache.vendorCost[itemID] =
--   { npc, name, gold (copper per purchase), stack, cost = { { id, amount, currency } } }
-- (currency true: a currency id; false: an item id). The cache starts over
-- with a new game build or client language, like every Loot Guide cache.
---------------------------------------------------------------------------
local scannedVendors = {}

local function NpcFromGUID(guid)
	if type(guid) ~= "string" or Secret(guid) then return end
	local unitType, _, _, _, _, npcID = strsplit("-", guid)
	if unitType == "Creature" or unitType == "Vehicle" then return tonumber(npcID) end
end
LG.NpcFromGUID = NpcFromGUID

local function VendorStore(create)
	local store = LG:Cache()
	if type(store.vendorCost) ~= "table" then
		if not create then return end
		store.vendorCost = {}
	end
	return store.vendorCost
end

function LG:SeenVendorCost(itemID)
	itemID = tonumber(itemID)
	local store = itemID and VendorStore(false)
	local entry = store and store[itemID]
	return type(entry) == "table" and entry or nil
end

function LG:SeenVendorCount()
	local store, count = VendorStore(false), 0
	if store then for _ in pairs(store) do count = count + 1 end end
	return count
end

-- price, stack, extended for one merchant slot (nil when the client hides it).
local function MerchantSlot(index)
	local merchant = C_MerchantFrame
	if merchant and merchant.GetItemInfo then
		local ok, info = pcall(merchant.GetItemInfo, index)
		if ok and type(info) == "table" then
			local price, stack = info.price, info.stackCount
			if Secret(price) or Secret(stack) then return end
			return tonumber(price), tonumber(stack), not Secret(info.hasExtendedCost) and info.hasExtendedCost
		end
	end
end

local function ExtendedCost(index)
	if not (GetMerchantItemCostInfo and GetMerchantItemCostItem) then return end
	local count = GetMerchantItemCostInfo(index)
	if Secret(count) or type(count) ~= "number" then return end
	local cost = {}
	for slot = 1, count do
		local _, amount, link = GetMerchantItemCostItem(index, slot)
		if type(link) == "string" and not Secret(link) and not Secret(amount) then
			local kind, id = link:match("|H(%a+):(%d+)")
			if not kind then kind, id = link:match("^(%a+):(%d+)") end
			if id and (kind == "item" or kind == "currency") then
				cost[#cost + 1] = { id = tonumber(id), amount = tonumber(amount) or 1, currency = kind == "currency" }
			end
		end
	end
	return #cost > 0 and cost or nil
end

-- Reads the open merchant (MERCHANT_SHOW). Returns the number of items
-- stored, or false when this vendor was read already this session.
function LG:ScanMerchant()
	local npc = NpcFromGUID(UnitGUID and UnitGUID("npc"))
	if not npc or scannedVendors[npc] then return false end
	local count = GetMerchantNumItems and GetMerchantNumItems()
	if Secret(count) or type(count) ~= "number" or count <= 0 then return false end
	scannedVendors[npc] = true
	local name = UnitName("npc")
	if Secret(name) then name = nil end
	local store = VendorStore(true)
	local stored = 0
	for index = 1, count do
		local itemID = GetMerchantItemID and GetMerchantItemID(index)
		if type(itemID) == "number" and not Secret(itemID) then
			local price, stack, extended = MerchantSlot(index)
			local entry = { npc = npc, name = name, gold = price and price > 0 and price or nil,
				stack = stack and stack > 1 and stack or nil, cost = extended and ExtendedCost(index) or nil }
			if entry.gold or entry.cost then
				store[itemID] = entry
				stored = stored + 1
			end
		end
	end
	self:ClearDataCache("sources")
	self:Fire("data")
	return stored
end

LG:Listen("MERCHANT_SHOW", "vendorcost", function()
	-- The merchant list fills a moment after the window opens.
	C_Timer.After(0.3, function()
		if LG.active then LG:ScanMerchant() end
	end)
end)

---------------------------------------------------------------------------
-- Live: what the client itself knows (dungeon finder list, finished quests).
-- Used with and without EldoUI_LootData.
---------------------------------------------------------------------------
local liveInstances

-- { { id, name, min, max, size, mapID }, ... } from the dungeon finder, or {}.
function LG:LiveInstances()
	if liveInstances then return liveInstances end
	local list = {}
	if GetLFDChoiceOrder and GetLFGDungeonInfo then
		local ok, order = pcall(GetLFDChoiceOrder)
		if ok and type(order) == "table" then
			for _, id in ipairs(order) do
				-- name, typeID, subtypeID, minLevel, maxLevel, ... maxPlayers (13) ... lfgMapID (22)
				local r = { pcall(GetLFGDungeonInfo, id) }
				local name = r[2]
				if r[1] and type(name) == "string" and not Secret(name) and not Secret(r[5]) and not Secret(r[6]) then
					local entry = { id = id, name = name, min = tonumber(r[5]), max = tonumber(r[6]), size = not Secret(r[14]) and tonumber(r[14]) or nil }
					if not Secret(r[23]) then entry.mapID = tonumber(r[23]) end
					list[#list + 1] = entry
				end
			end
		end
	end
	liveInstances = list
	return list
end

-- Has the character finished a quest (the client's own flag)?
function LG:QuestDone(questID)
	questID = tonumber(questID)
	if not questID then return false end
	local log = C_QuestLog
	if log and log.IsQuestFlaggedCompleted then
		local ok, done = pcall(log.IsQuestFlaggedCompleted, questID)
		if ok and not Secret(done) then return done and true or false end
	end
	return false
end

LG:Listen("QUEST_TURNED_IN", "live", function() LG:Fire("quests") end)
LG:Listen("LFG_UPDATE_RANDOM_INFO", "live", function() liveInstances = nil end)

-- Memory EldoUI_LootData uses in KB (nil when it is not loaded).
function LG:DataMemory()
	if not LD or not (UpdateAddOnMemoryUsage and GetAddOnMemoryUsage) then return end
	pcall(UpdateAddOnMemoryUsage)
	local ok, kb = pcall(GetAddOnMemoryUsage, ADDON)
	if ok and type(kb) == "number" and not Secret(kb) then return kb end
end

---------------------------------------------------------------------------
-- Load timing
---------------------------------------------------------------------------
LG:Listen("PLAYER_REGEN_ENABLED", "data", function()
	if LG.loadAfterCombat then
		LG.loadAfterCombat = nil
		LG:LoadData()
	end
end)

function LG:OnEnableData()
	if LD or self.loadScheduled then return end
	if Adopt() then return end
	self.loadScheduled = true
	C_Timer.After(LOGIN_DELAY, function()
		if LG.active then LG:LoadData() end
	end)
end

-- Built-in providers: what the shell knows how to read.
LG:RegisterProvider("lootdata", {
	title = "EldoUI_LootData",
	available = function() return LD ~= nil end,
	sources = function(itemID) return LG:ItemSources(itemID) end,
	quests = function(itemID) return LG:ItemQuests(itemID) end,
})
LG:RegisterProvider("live", {
	title = "This client",
	available = function() return true end,
	instances = function() return LG:LiveInstances() end,
})
LG:RegisterProvider("observed", {
	title = "Drops seen by you",
	available = function() return LG:ObservedAvailable() end,
})
