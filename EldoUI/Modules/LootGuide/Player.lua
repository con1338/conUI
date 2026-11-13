-- EldoUI Loot Guide: the player model and ownership.
--
-- LG:Player() -> {
--     class, classID, classMask, race, raceID, raceMask, faction, level,
--     professions = { [skillLineID] = rank },
--     armor   = { [armor subclass] = true }   (what the class wears at this level)
--     weapons = { [weapon subclass] = true }   (what the class can train)
--     dualWield, equipped = { [slot] = itemID },
-- }
-- Rebuilt when the level, professions or gear change; the bus messages
-- "player", "gear", "bags" and "spec" tell pages what moved.
--
-- LG:Owns(itemID) -> where, detail: "worn", "bags", "bank", "set" (one of the
-- game's equipment sets, detail = set name) or "alt" (detail = character
-- name, from the Bags module's inventory cache), else nil.
--
-- Everything here reads what the client shows the player; nothing acts.
local _, E = ...
local LG = E.LootGuide

local Secret = E.Secret

local Plain = E.Plain

---------------------------------------------------------------------------
-- Class rules (Classic). Armor (item class 4) subclasses: 1 cloth,
-- 2 leather, 3 mail, 4 plate, 6 shield, 7 libram, 8 idol, 9 totem; the value
-- is the level the class learns it (mail and plate at 40). Weapons (item
-- class 2) are what the class can train.
---------------------------------------------------------------------------
local ARMOR = {
	WARRIOR = { [1] = 1, [2] = 1, [3] = 1, [4] = 40, [6] = 1 },
	PALADIN = { [1] = 1, [2] = 1, [3] = 1, [4] = 40, [6] = 1, [7] = 1 },
	HUNTER = { [1] = 1, [2] = 1, [3] = 40 },
	ROGUE = { [1] = 1, [2] = 1 },
	PRIEST = { [1] = 1 },
	SHAMAN = { [1] = 1, [2] = 1, [3] = 40, [6] = 1, [9] = 1 },
	MAGE = { [1] = 1 },
	WARLOCK = { [1] = 1 },
	DRUID = { [1] = 1, [2] = 1, [8] = 1 },
}
LG.ARMOR_RULES = ARMOR

-- 0 1H axe, 1 2H axe, 2 bow, 3 gun, 4 1H mace, 5 2H mace, 6 polearm,
-- 7 1H sword, 8 2H sword, 10 staff, 13 fist, 15 dagger, 16 thrown,
-- 18 crossbow, 19 wand (14 misc and 20 fishing pole: everyone).
local WEAPONS = {
	WARRIOR = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 15, 16, 18 },
	PALADIN = { 0, 1, 4, 5, 6, 7, 8 },
	HUNTER = { 0, 1, 2, 3, 6, 7, 8, 10, 13, 15, 16, 18 },
	ROGUE = { 2, 3, 4, 7, 13, 15, 16, 18 },
	PRIEST = { 4, 10, 15, 19 },
	SHAMAN = { 0, 1, 4, 5, 10, 13, 15 },
	MAGE = { 7, 10, 15, 19 },
	WARLOCK = { 7, 10, 15, 19 },
	DRUID = { 4, 5, 10, 13, 15 },
}

-- Dual wield arrives at these levels.
local DUAL_WIELD = { WARRIOR = 20, ROGUE = 10, HUNTER = 20 }

-- The class that may put a relic (libram, idol, totem) in the ranged slot.
local RELIC = { PALADIN = 7, DRUID = 8, SHAMAN = 9 }
LG.RELIC_SUBCLASS = RELIC

local EQUIP_SLOTS = 19

---------------------------------------------------------------------------
-- Reading the client
---------------------------------------------------------------------------
local function ReadProfessions()
	local list = {}
	local info = C_SkillInfo
	if info and info.GetNumSkillLines and info.GetSkillLineInfo then
		local ok, count = pcall(info.GetNumSkillLines)
		count = ok and Plain(count) or 0
		for index = 1, tonumber(count) or 0 do
			local fine, line = pcall(info.GetSkillLineInfo, index)
			if fine and type(line) == "table" and not line.isHeader then
				local id, rank = Plain(line.skillID or line.skillLineID), Plain(line.rank or line.skillRank)
				if tonumber(id) and tonumber(rank) then list[tonumber(id)] = tonumber(rank) end
			end
		end
	end
	if next(list) == nil and GetProfessions and GetProfessionInfo then
		local professions = { pcall(GetProfessions) }
		if professions[1] then
			for index = 2, 6 do -- after pcall's flag: five slots, any may be empty
				local slot = professions[index]
				if slot then
					local ok, _, _, rank, _, _, _, skillLine = pcall(GetProfessionInfo, slot)
					rank, skillLine = Plain(rank), Plain(skillLine)
					if ok and tonumber(skillLine) and tonumber(rank) then list[tonumber(skillLine)] = tonumber(rank) end
				end
			end
		end
	end
	return list
end

local function ReadEquipped()
	local equipped = {}
	for slot = 1, EQUIP_SLOTS do
		local id = Plain(GetInventoryItemID("player", slot))
		if tonumber(id) then equipped[slot] = tonumber(id) end
	end
	return equipped
end

local model

-- The race masks of the open data know the eight classic races. A race
-- of WoW: Forever's own (the Skyborne, 95 and 96) has no bit there and
-- counts as every race of its side.
local SIDE_MASK = { Alliance = 77, Horde = 178 }
local function RaceMask(raceID, faction)
	if raceID and raceID >= 1 and raceID <= 8 then return bit.lshift(1, raceID - 1) end
	return SIDE_MASK[faction or ""] or 0
end
LG.RaceMask = RaceMask

function LG:Player()
	if model then return model end
	local _, classFile, classID = UnitClass("player")
	local _, raceFile, raceID = UnitRace("player")
	classID, raceID = tonumber(Plain(classID)), tonumber(Plain(raceID))
	local level = tonumber(Plain(UnitLevel("player"))) or 1
	local faction = Plain(UnitFactionGroup("player"))
	classFile = Plain(classFile) or "WARRIOR"
	local player = {
		class = classFile, classID = classID, classMask = classID and bit.lshift(1, classID - 1) or 0,
		race = Plain(raceFile), raceID = raceID, raceMask = RaceMask(raceID, faction),
		faction = faction, level = level, professions = ReadProfessions(), armor = { [0] = true }, weapons = { [14] = true, [20] = true },
		equipped = ReadEquipped(),
	}
	for subclass, from in pairs(ARMOR[classFile] or {}) do
		if level >= from then player.armor[subclass] = true end
	end
	for _, subclass in ipairs(WEAPONS[classFile] or {}) do player.weapons[subclass] = true end
	local dual
	if CanDualWield then
		local ok, value = pcall(CanDualWield)
		if ok and not Secret(value) then dual = value and true or false end
	end
	if dual == nil then dual = DUAL_WIELD[classFile] ~= nil and level >= DUAL_WIELD[classFile] end
	player.dualWield = dual
	player.relic = RELIC[classFile]
	model = player
	return player
end

---------------------------------------------------------------------------
-- Talents the player has learned, read from the game's talent tree
-- (C_ClassTalents / C_Traits) with the old talent-tab functions as a first
-- try on clients that have them. Read on every call (the callers keep
-- their own copies).
--
-- LG:TalentRanks() -> nil when the client tells nothing, else {
--     list = { { spellID, name, rank, maxRank, tree }, ... },
--     points = { [tree index] = points spent },  trees = number of trees,
--     key = text that changes when any rank changes,
-- }
---------------------------------------------------------------------------
local function PlainNumber(value)
	value = Plain(value)
	return type(value) == "number" and value or nil
end

local function PCallPlain(fn, ...)
	if type(fn) ~= "function" then return end
	local results = { pcall(fn, ...) }
	if not results[1] then return end
	for index = 2, table.maxn(results) do results[index] = Plain(results[index]) end
	return unpack(results, 2, table.maxn(results))
end

local function TalentTabs()
	local numTabs = rawget(_G, "GetNumTalentTabs")
	local numTalents, info = rawget(_G, "GetNumTalents"), rawget(_G, "GetTalentInfo")
	if not (numTabs and numTalents and info) then return end
	local out = { list = {}, points = {}, trees = tonumber(PCallPlain(numTabs)) or 0 }
	local keys = {}
	for tab = 1, out.trees do
		out.points[tab] = 0
		for index = 1, tonumber(PCallPlain(numTalents, tab)) or 0 do
			local name, _, _, _, rank, maxRank = PCallPlain(info, tab, index)
			rank = tonumber(rank) or 0
			keys[#keys + 1] = tostring(rank)
			if type(name) == "string" and rank > 0 then
				out.list[#out.list + 1] = { name = name, rank = rank, maxRank = tonumber(maxRank) or rank, tree = tab }
				out.points[tab] = out.points[tab] + rank
			end
		end
	end
	out.key = table.concat(keys, "")
	return out
end

local function TalentTree()
	local traits, classTalents = C_Traits, C_ClassTalents
	if not (traits and classTalents and traits.GetTreeNodes and traits.GetNodeInfo) then return end
	local config = PlainNumber(PCallPlain(classTalents.GetActiveConfigID))
	if not config then return end
	local util = rawget(_G, "PlayerUtil")
	local specID = util and PlainNumber(PCallPlain(util.GetCurrentSpecID))
	local treeID = specID and PlainNumber(PCallPlain(classTalents.GetTraitTreeForSpec, specID))
	if not treeID then
		local info = PCallPlain(traits.GetConfigInfo, config)
		treeID = type(info) == "table" and type(info.treeIDs) == "table" and PlainNumber(info.treeIDs[1])
	end
	local nodeIDs = treeID and PCallPlain(traits.GetTreeNodes, treeID)
	if type(nodeIDs) ~= "table" then return end
	-- A node names several node groups; its talent tree is the one the
	-- tree's display list names (the order there is the tree order).
	local treeIndex, count = {}, 0
	local display = PCallPlain(traits.GetGroupDisplayInfoByTreeID, treeID)
	if type(display) == "table" then
		local groups = {}
		for _, info in ipairs(display) do
			if type(info) == "table" and PlainNumber(info.groupID) then groups[#groups + 1] = info end
		end
		table.sort(groups, function(a, b) return (PlainNumber(a.orderIndex) or 0) < (PlainNumber(b.orderIndex) or 0) end)
		for index, info in ipairs(groups) do treeIndex[info.groupID] = index end
		count = #groups
	end
	local out = { list = {}, points = {}, trees = math.max(count, 1) }
	for index = 1, out.trees do out.points[index] = 0 end
	local keys = {}
	for _, nodeID in ipairs(nodeIDs) do
		local info = PCallPlain(traits.GetNodeInfo, config, nodeID)
		local rank = type(info) == "table" and PlainNumber(info.ranksPurchased) or 0
		if rank > 0 then
			local tree = 1
			for _, id in ipairs(info.groupIDs or {}) do
				if treeIndex[id] then tree = treeIndex[id] break end
			end
			local entryID = type(info.entryIDs) == "table" and info.entryIDs[1]
			local entry = entryID and PCallPlain(traits.GetEntryInfo, config, entryID)
			local def = type(entry) == "table" and entry.definitionID and PCallPlain(traits.GetDefinitionInfo, entry.definitionID)
			local spellID = type(def) == "table" and (PlainNumber(def.spellID) or PlainNumber(def.overriddenSpellID)) or nil
			local name = type(def) == "table" and Plain(def.overrideName) or nil
			if type(name) ~= "string" or name == "" then
				name = spellID and C_Spell and PCallPlain(C_Spell.GetSpellName, spellID)
			end
			out.list[#out.list + 1] = { spellID = spellID, name = type(name) == "string" and name or nil, rank = rank,
				maxRank = math.max(PlainNumber(info.maxRanks) or rank, rank), tree = tree }
			out.points[tree] = (out.points[tree] or 0) + rank
			keys[#keys + 1] = nodeID .. "=" .. rank
		end
	end
	out.key = table.concat(keys, ",")
	return out
end

function LG:TalentRanks()
	return TalentTabs() or TalentTree()
end

-- The level a class learns an armor kind (nil: never).
function LG:ArmorLevel(class, subclass)
	local rules = ARMOR[class or self:Player().class]
	if subclass == 0 then return 1 end
	return rules and rules[subclass]
end

-- Heaviest body armor the player wears now (1 cloth .. 4 plate).
function LG:HeaviestArmor()
	local player = self:Player()
	for subclass = 4, 1, -1 do
		if player.armor[subclass] then return subclass end
	end
	return 1
end

-- Standing with a faction: 0 hated .. 7 exalted (nil when unknown).
function LG:Standing(factionID)
	local rep = C_Reputation
	if not (rep and rep.GetFactionDataByID and tonumber(factionID)) then return end
	local ok, data = pcall(rep.GetFactionDataByID, tonumber(factionID))
	if not ok or type(data) ~= "table" then return end
	local reaction = Plain(data.reaction)
	return tonumber(reaction) and tonumber(reaction) - 1 or nil
end

-- Can the player use an item record (class, race, armor, weapon, skill)?
-- ignoreLevel: proficiency the class learns later still counts.
-- Returns ok, reason ("class", "race", "armor", "weapon", "skill", "reputation").
function LG:CanUseRecord(record, ignoreLevel)
	if type(record) ~= "table" then return true end
	local player = self:Player()
	local classMask = tonumber(record.classMask)
	if classMask and classMask > 0 and player.classMask > 0 and bit.band(classMask, player.classMask) == 0 then
		return false, "class"
	end
	local raceMask = tonumber(record.raceMask)
	if raceMask and raceMask > 0 and player.raceMask > 0 and bit.band(raceMask, player.raceMask) == 0 then
		return false, "race"
	end
	if record.class == 4 and record.subclass and record.subclass > 0 then
		local from = self:ArmorLevel(player.class, record.subclass)
		if not from or (not ignoreLevel and from > player.level) then return false, "armor" end
	elseif record.class == 2 and record.subclass and not player.weapons[record.subclass] then
		return false, "weapon"
	end
	if record.skill and record.skillRank and record.skillRank > 0 then
		local rank = player.professions[record.skill]
		if not rank or rank < record.skillRank then return false, "skill" end
	end
	return true
end

-- Item facts from LootData or, without it, from the client:
-- { quality, class, subclass, equipLoc, reqLevel, record }.
function LG:ItemFacts(itemID)
	itemID = tonumber(itemID)
	if not itemID then return end
	local record = self:ItemRecord(itemID)
	local _, _, _, equipLoc, _, classID, subclassID = C_Item.GetItemInfoInstant(itemID)
	if Secret(equipLoc) then equipLoc, classID, subclassID = nil, nil, nil end
	local facts = { record = record, equipLoc = equipLoc ~= "" and equipLoc or nil }
	if record then
		facts.quality, facts.class, facts.subclass, facts.reqLevel = record.quality, record.class, record.subclass, record.reqLevel
	else
		facts.class, facts.subclass = tonumber(classID), tonumber(subclassID)
		local _, _, quality, _, minLevel = C_Item.GetItemInfo(itemID)
		if not Secret(quality) then facts.quality = tonumber(quality) end
		if not Secret(minLevel) then facts.reqLevel = tonumber(minLevel) end
	end
	return facts
end

-- The level the player can use an item at: its required level, or
-- later when the class learns the armor kind later (mail and plate at 40).
function LG:UseLevel(itemID)
	local facts = self:ItemFacts(itemID)
	if not facts then return end
	local level = tonumber(facts.reqLevel) or 1
	if facts.class == 4 and facts.subclass and facts.subclass > 0 then
		local from = self:ArmorLevel(self:Player().class, facts.subclass)
		if from and from > level then level = from end
	end
	return level
end

---------------------------------------------------------------------------
-- Ownership
---------------------------------------------------------------------------
local setIndex   -- itemID -> set name, from the game's equipment sets
local altIndex   -- itemID -> character name (other characters)

local function BuildSetIndex()
	local index = {}
	local sets = C_EquipmentSet
	if sets and sets.GetEquipmentSetIDs and sets.GetItemIDs then
		local ok, ids = pcall(sets.GetEquipmentSetIDs)
		if ok and type(ids) == "table" then
			for _, setID in ipairs(ids) do
				local name = sets.GetEquipmentSetInfo and Plain((sets.GetEquipmentSetInfo(setID))) or nil
				local fine, items = pcall(sets.GetItemIDs, setID)
				if fine and type(items) == "table" then
					for _, itemID in pairs(items) do
						itemID = tonumber(Plain(itemID))
						if itemID and itemID > 0 then index[itemID] = index[itemID] or name or true end
					end
				end
			end
		end
	end
	return index
end

local function BuildAltIndex()
	local index = {}
	local inventory = type(EldoUIDB) == "table" and type(EldoUIDB.inventory) == "table" and EldoUIDB.inventory
	if not inventory then return index end
	for charKey, char in pairs(inventory) do
		if charKey ~= E.charKey and type(char) == "table" and type(char.counts) == "table" then
			for itemID, counts in pairs(char.counts) do
				local total = 0
				if type(counts) == "table" then
					for _, n in pairs(counts) do total = total + (tonumber(n) or 0) end
				else
					total = tonumber(counts) or 0
				end
				if total > 0 and tonumber(itemID) then index[tonumber(itemID)] = index[tonumber(itemID)] or char.name or charKey end
			end
		end
	end
	return index
end

function LG:Owns(itemID)
	itemID = tonumber(itemID)
	if not itemID then return end
	local player = self:Player()
	for _, id in pairs(player.equipped) do
		if id == itemID then return "worn" end
	end
	local bags = C_Item.GetItemCount and C_Item.GetItemCount(itemID, false) or 0
	local all = C_Item.GetItemCount and C_Item.GetItemCount(itemID, true) or 0
	if Secret(bags) or Secret(all) then bags, all = 0, 0 end
	if (tonumber(bags) or 0) > 0 then return "bags" end
	if (tonumber(all) or 0) > 0 then return "bank" end
	setIndex = setIndex or BuildSetIndex()
	if setIndex[itemID] then return "set", setIndex[itemID] ~= true and setIndex[itemID] or nil end
	altIndex = altIndex or BuildAltIndex()
	if altIndex[itemID] then return "alt", altIndex[itemID] end
end

-- Items the player has for gear comparison: worn, bags, equipment sets.
-- { itemID = true }
local ownedGear
function LG:OwnedGear()
	if ownedGear then return ownedGear end
	local list = {}
	for _, id in pairs(self:Player().equipped) do list[id] = true end
	setIndex = setIndex or BuildSetIndex()
	for id in pairs(setIndex) do list[id] = true end
	local container = C_Container
	if container and container.GetContainerNumSlots and container.GetContainerItemID then
		for bag = 0, (NUM_BAG_SLOTS or 4) do
			local ok, slots = pcall(container.GetContainerNumSlots, bag)
			slots = ok and tonumber(Plain(slots)) or 0
			for slot = 1, slots do
				local id = tonumber(Plain(container.GetContainerItemID(bag, slot)))
				if id then list[id] = true end
			end
		end
	end
	ownedGear = list
	return list
end

---------------------------------------------------------------------------
-- Events -> model updates and bus messages
---------------------------------------------------------------------------
LG.gearVersion = 0

local function PlayerChanged()
	model = nil
	ownedGear = nil
	LG:Fire("player")
end

LG:Listen("PLAYER_LEVEL_UP", "player", PlayerChanged)
LG:Listen("SKILL_LINES_CHANGED", "player", PlayerChanged)
LG:Listen("PLAYER_EQUIPMENT_CHANGED", "player", function()
	if model then model.equipped = ReadEquipped() end
	ownedGear = nil
	LG.gearVersion = LG.gearVersion + 1
	LG:Fire("gear")
end)
LG:Listen("BAG_UPDATE_DELAYED", "player", function()
	ownedGear = nil
	LG:Fire("bags")
end)
LG:Listen("EQUIPMENT_SETS_CHANGED", "player", function()
	setIndex, ownedGear = nil, nil
	LG:Fire("bags")
end)
for _, event in ipairs({ "PLAYER_TALENT_UPDATE", "CHARACTER_POINTS_CHANGED", "ACTIVE_TALENT_GROUP_CHANGED", "PLAYER_ROLES_ASSIGNED" }) do
	LG:Listen(event, "player", function() LG:Fire("spec") end)
end
LG:Listen("PLAYER_ENTERING_WORLD", "player", function()
	altIndex = nil
	PlayerChanged()
end)

-- Tests and /reload-free refreshes.
function LG:ResetPlayer()
	model, setIndex, altIndex, ownedGear = nil, nil, nil, nil
end
