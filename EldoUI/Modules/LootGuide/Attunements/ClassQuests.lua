-- EldoUI Attunements: class quest chains for the class guide.
--
-- The chains themselves come from EldoUI_LootData (LD.classChains) and
-- EldoUI's own class quest list for WoW: Forever (Data/Training/Shared.lua),
-- built into entries by Defs.lua, and show in the Attunements tab under
-- Class quests. This file adds what the class guide needs on top:
--
--   A:ClassKeys([class])         the class's chains for your faction (and,
--                                for your own class, your race), by the
--                                level they open at
--   A:RaceFits(entry)            the chain is for your race (or for every race)
--   A:SpellName(entry)           the spell a WoW: Forever class quest teaches
--   A:NearestClassQuest(keys)    the chain whose next step is on your map
--   A:StartLevel(key)            the level a chain opens at (from the quest data)
--   A:ChainRewards(key)          item IDs the last quest of the chain gives
--   A:ClassChainLine(key)        our own one-line summary: where it starts,
--                                at which level, and what it ends with
--   A:ClassQuestsAt(level[, class])  chains that open at exactly that level
--                                and that you haven't done
--   A:NextClassStep(key)         the step to do next and where: step, place
--   A:ClassWaypoint(key)         a map pin on that step, on your click
--
-- Everything is read from the data and the game's quest log; nothing is
-- accepted, turned in or skipped.
local _, E = ...
local L = E.L
local LG = E.LootGuide
local A = E:GetModule("Attunements")

local function Player()
	return LG:Player() or {}
end

function A:StartLevel(key)
	local entry = self:Get(key)
	if not entry then return nil end
	local steps = entry.steps
	local lvl = steps and steps.byId and steps.byId.lvl
	if lvl and tonumber(lvl.ref) then return lvl.ref end
	return entry.minLevel
end

-- Is a class quest chain for your race? A chain with no race list is.
function A:RaceFits(entry)
	local race = Player().raceID
	return not (entry.races and race and not entry.races[race])
end

function A:ClassKeys(class)
	local own = Player().class
	class = class or own
	self:EnsureBuilt()
	local out, order, level = {}, {}, {}
	for index, entry in ipairs(self:AllEntries()) do
		if entry.kind == "class" and entry.class == class and self:FactionFits(entry, "mine")
			and (class ~= own or self:RaceFits(entry)) then
			out[#out + 1] = entry.key
			order[entry.key], level[entry.key] = entry.order or index, self:StartLevel(entry.key) or 0
		end
	end
	table.sort(out, function(a, b)
		if level[a] ~= level[b] then return level[a] < level[b] end
		return order[a] < order[b]
	end)
	return out
end

function A:ChainRewards(key)
	local entry = self:Get(key)
	local out, seen = {}, {}
	for _, questID in ipairs(entry and entry.goalQuests or {}) do
		local quest = LG:Quest(questID)
		for _, list in ipairs(quest and { quest.rewards or {}, quest.choice or {} } or {}) do
			for _, reward in ipairs(list) do
				if reward.id and not seen[reward.id] then
					seen[reward.id] = true
					out[#out + 1] = reward.id
				end
			end
		end
	end
	return out
end

local function ItemName(itemID)
	local record = LG:ItemRecord(itemID)
	return record and record.name or nil
end

-- The name of an area (AreaTable), from the client.
local function AreaName(area)
	local name = area and C_Map and C_Map.GetAreaInfo and C_Map.GetAreaInfo(area)
	if type(name) ~= "string" or E.Secret(name) or name == "" then return nil end
	return name
end

-- The spell a WoW: Forever class quest teaches, by name.
function A:SpellName(entry)
	local id = entry and entry.spell
	local name = id and C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
	if type(name) ~= "string" or E.Secret(name) or name == "" then return nil end
	return name
end

-- "Opens at level 10 with Kaltunk in Durotar. It ends with Earth Totem."
function A:ClassChainLine(key)
	local entry = self:Get(key)
	if not entry then return nil end
	local parts = {}
	local level = self:StartLevel(key)
	local first = entry.quests and entry.quests[1]
	local place = first and self:StepPlace({ kind = "pickup", quest = first })
	local area = AreaName(entry.area)
	if level and place and place.name and place.zone then
		parts[#parts + 1] = L["Opens at level %d with %s in %s."]:format(level, place.name, place.zone)
	elseif level and area then
		parts[#parts + 1] = L["Opens at level %d in %s."]:format(level, area)
	elseif level then
		parts[#parts + 1] = L["Opens at level %d."]:format(level)
	end
	local names = {}
	for _, itemID in ipairs(self:ChainRewards(key)) do
		local name = ItemName(itemID)
		if name then names[#names + 1] = name end
		if #names >= 3 then break end
	end
	local spell = self:SpellName(entry)
	if spell then names = { spell } end
	if #names > 0 then
		parts[#parts + 1] = L["It ends with %s."]:format(table.concat(names, ", "))
	end
	if #parts == 0 then return nil end
	return table.concat(parts, " ")
end

function A:ClassQuestsAt(level, class)
	local out = {}
	if not tonumber(level) then return out end
	for _, key in ipairs(self:ClassKeys(class)) do
		if self:StartLevel(key) == level then
			local _, _, _, state = self:Progress(key)
			if state ~= "done" then out[#out + 1] = key end
		end
	end
	return out
end

function A:NextClassStep(key)
	local step = self:NextSteps(key)[1]
	if not step then return nil end
	return step, self:StepPlace(step)
end

-- Of several chains, the one whose next step is on your map, else the
-- first: { key, place }.
function A:NearestClassQuest(keys)
	local map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
	if E.Secret(map) then map = nil end
	local firstPlace
	for index, key in ipairs(keys or {}) do
		local _, place = self:NextClassStep(key)
		if index == 1 then firstPlace = place end
		if map and place and place.uiMapID == map then return key, place end
	end
	return keys and keys[1], firstPlace
end

function A:ClassWaypoint(key)
	local step, place = self:NextClassStep(key)
	if not (step and place and place.uiMapID) then return false end
	return LG:SetWaypoint(place, self:StepTitle(step)) and true or false
end
