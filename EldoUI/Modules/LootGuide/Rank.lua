-- EldoUI Loot Guide: your loot list and item ranking.
--
--   LG:SourceChip(entry)             which list source a source counts as
--   LG:ListKey(), LG:SetListSource(), LG:ResetList(), LG:IsRealisticList()
--   LG:Obtainable(itemID)            ok, reason, chips
--   LG:MissingProfession(itemID)     skillLineID, rank
--   LG:RankAll(fn, opts)             best items per slot group, built a chunk
--                                    per frame and cached by spec, level, list,
--                                    priority and gear; a gear change only
--                                    rates again the items that passed the
--                                    checks gear does not change
--   LG:ResolveBiS(rank)              one item per slot
--   LG:UpgradeTargets(itemID)        the slots an item beats
--   LG:NextUpgrades(n)               the next items worth chasing
--   LG:BestInstance()                where those come from
--   LG:InstanceGroups()              instances under their group
--   LG:IsObsolete(itemID)            you already own better
--
-- Scores come from the shared engine (E.ItemScore), the same numbers the
-- Upgrades arrows and tooltips show. Nothing here acts for the player.
local _, E = ...
local LG = E.LootGuide

local CHUNK = 150          -- items rated per frame while ranking
local QUEST_GREY = 10      -- a quest this many levels below you leaves your list
local KEEP_PER_SLOT = 25   -- ranked items kept per slot group

local Secret = E.Secret

---------------------------------------------------------------------------
-- List sources (chips)
---------------------------------------------------------------------------
LG.SOURCE_CHIPS = { "quests", "dungeons", "rares", "crafted", "world", "vendor", "reputation", "pvp" }

-- A source entry from LG:ItemSources -> chip key.
function LG:SourceChip(entry)
	local kind = entry and entry.kind
	if kind == "quest" or kind == "choice" then return "quests" end
	if kind == "crafted" then return "crafted" end
	if kind == "vendor" then return "vendor" end
	if kind == "repvendor" then return "reputation" end
	if kind == "pvpvendor" then return "pvp" end
	if kind == "world" then return "world" end
	if kind == "token" then return "dungeons" end
	if kind == "npc" then
		if entry.instance then return "dungeons" end
		-- Creature rank 2 = rare elite, 4 = rare.
		if entry.rank == 2 or entry.rank == 4 then return "rares" end
		return "world"
	end
	if kind == "object" then return "world" end
end

-- The player's list settings (window state, saved silently per character).
function LG:List()
	local data = self:Char()
	return data and data.list or { sources = CopyTable(self.LIST_PRESETS.realistic), minChance = 0 }
end

function LG:ListKey()
	local list = self:List()
	local parts = {}
	for _, chip in ipairs(self.SOURCE_CHIPS) do parts[#parts + 1] = list.sources[chip] and "1" or "0" end
	parts[#parts + 1] = tostring(tonumber(list.minChance) or 0)
	local armor = {}
	for subclass, on in pairs(type(list.armor) == "table" and list.armor or {}) do
		if on == false then armor[#armor + 1] = tostring(subclass) end
	end
	table.sort(armor)
	parts[#parts + 1] = table.concat(armor, ".")
	return table.concat(parts, ":")
end

function LG:SetListSource(chip, on)
	local list = self:List()
	list.sources[chip] = on and true or false
	list.preset = nil
	for key, preset in pairs(self.LIST_PRESETS) do
		local same = true
		for _, name in ipairs(self.SOURCE_CHIPS) do
			if (preset[name] and true or false) ~= (list.sources[name] and true or false) then same = false break end
		end
		if same then list.preset = key end
	end
	self:Fire("list")
end

function LG:SetListMinChance(value)
	self:List().minChance = math.max(0, math.min(100, tonumber(value) or 0))
	self:Fire("list")
end

-- Armor kinds to leave out (subclass -> false); nil shows it again.
function LG:SetListArmor(subclass, shown)
	local list = self:List()
	list.armor = type(list.armor) == "table" and list.armor or {}
	list.armor[subclass] = (not shown) and false or nil
	self:Fire("list")
end

function LG:IsRealisticList()
	local list = self:List()
	if (tonumber(list.minChance) or 0) ~= 0 then return false end
	if type(list.armor) == "table" and next(list.armor) then return false end
	for _, chip in ipairs(self.SOURCE_CHIPS) do
		if (self.LIST_PRESETS.realistic[chip] and true or false) ~= (list.sources[chip] and true or false) then return false end
	end
	return true
end

-- "Back to realistic".
function LG:ResetList()
	local list = self:List()
	list.sources = CopyTable(self.LIST_PRESETS.realistic)
	list.preset = "realistic"
	list.minChance = 0
	list.armor = nil
	self:Fire("list")
end

---------------------------------------------------------------------------
-- Obtainability
---------------------------------------------------------------------------
-- Quest checks: done, class/race, and the gray-quest rule.
local function QuestOpen(questID, player)
	if LG:QuestDone(questID) then return false, "done" end
	local level = LG:QuestLevel(questID)
	if level and level > 0 and level + QUEST_GREY <= player.level then return false, "grey" end
	return true
end
LG.QUEST_GREY = QUEST_GREY

-- Is one source usable for the list? ok, reason
function LG:SourceOpen(entry, list, player)
	list = list or self:List()
	player = player or self:Player()
	local chip = self:SourceChip(entry)
	if not chip or not list.sources[chip] then return false, "list" end
	if entry.kind == "npc" or entry.kind == "object" or entry.kind == "world" then
		local minChance = tonumber(list.minChance) or 0
		if minChance > 0 and entry.chance and entry.chance < minChance then return false, "chance" end
	elseif entry.kind == "quest" or entry.kind == "choice" then
		return QuestOpen(entry.id, player)
	end
	return true
end

-- ok, reason, chips. reason: "class", "race", "armor", "weapon", "skill"
-- (from LG:CanUseRecord), "hidden" (an armor kind you left out), "done"
-- (every quest for it is done), "gray" (only quests far below you), "list"
-- (no source on your list), "unknown" (no source known).
function LG:Obtainable(itemID)
	itemID = tonumber(itemID)
	if not itemID then return false, "unknown" end
	local player = self:Player()
	local list = self:List()
	local record = self:ItemRecord(itemID)
	if record then
		local ok, reason = self:CanUseRecord(record, true)
		if not ok and reason ~= "skill" then return false, reason end
		if record.class == 4 and type(list.armor) == "table" and list.armor[record.subclass] == false then
			return false, "hidden"
		end
	end
	local sources = self:ItemSources(itemID)
	if not sources or #sources == 0 then return false, "unknown" end
	local chips, firstReason = {}, nil
	for _, entry in ipairs(sources) do
		local ok, reason = self:SourceOpen(entry, list, player)
		if ok then
			chips[self:SourceChip(entry)] = true
		elseif not firstReason or reason ~= "list" then
			firstReason = reason
		end
	end
	if next(chips) then return true, nil, chips end
	return false, firstReason or "list"
end

-- The profession a crafted item (or one that needs a skill to use)
-- asks for when the player lacks it: skillLineID, rank.
function LG:MissingProfession(itemID)
	local player = self:Player()
	local record = self:ItemRecord(itemID)
	if record and record.skill and record.skillRank and record.skillRank > 0 then
		local rank = player.professions[record.skill]
		if not rank or rank < record.skillRank then return record.skill, record.skillRank end
	end
	local craftOnly, missing, missingRank = true, nil, nil
	for _, entry in ipairs(self:ItemSources(itemID) or {}) do
		if entry.kind == "crafted" then
			local craft = self:Craft(entry.id)
			local skill, need = craft and craft.skill, craft and craft.rank or 0
			if skill then
				local rank = player.professions[skill]
				if rank and rank >= need then return end
				missing, missingRank = missing or skill, missingRank or need
			end
		else
			craftOnly = false
		end
	end
	if missing and craftOnly then return missing, missingRank end
end

---------------------------------------------------------------------------
-- Slot groups
---------------------------------------------------------------------------
-- LootData inventory types -> slot group.
local GROUP_BY_INVTYPE = {
	[1] = "head", [2] = "neck", [3] = "shoulder", [5] = "chest", [20] = "chest", [6] = "waist", [7] = "legs",
	[8] = "feet", [9] = "wrist", [10] = "hands", [11] = "finger", [12] = "trinket", [16] = "back",
	[13] = "onehand", [21] = "mainhand", [17] = "twohand", [14] = "offhand", [22] = "offhand", [23] = "offhand",
	[15] = "ranged", [25] = "ranged", [26] = "ranged", [28] = "relic",
}
local GROUP_BY_EQUIPLOC = {
	INVTYPE_HEAD = "head", INVTYPE_NECK = "neck", INVTYPE_SHOULDER = "shoulder", INVTYPE_CHEST = "chest",
	INVTYPE_ROBE = "chest", INVTYPE_WAIST = "waist", INVTYPE_LEGS = "legs", INVTYPE_FEET = "feet",
	INVTYPE_WRIST = "wrist", INVTYPE_HAND = "hands", INVTYPE_FINGER = "finger", INVTYPE_TRINKET = "trinket",
	INVTYPE_CLOAK = "back", INVTYPE_WEAPON = "onehand", INVTYPE_WEAPONMAINHAND = "mainhand",
	INVTYPE_2HWEAPON = "twohand", INVTYPE_SHIELD = "offhand", INVTYPE_WEAPONOFFHAND = "offhand",
	INVTYPE_HOLDABLE = "offhand", INVTYPE_RANGED = "ranged", INVTYPE_RANGEDRIGHT = "ranged",
	INVTYPE_THROWN = "ranged", INVTYPE_RELIC = "relic",
}
LG.SLOT_GROUPS = { "head", "neck", "shoulder", "back", "chest", "wrist", "hands", "waist", "legs", "feet",
	"finger", "trinket", "mainhand", "offhand", "twohand", "onehand", "ranged", "relic" }
-- Equipment slots per group.
LG.GROUP_SLOTS = {
	head = { 1 }, neck = { 2 }, shoulder = { 3 }, back = { 15 }, chest = { 5 }, wrist = { 9 }, hands = { 10 },
	waist = { 6 }, legs = { 7 }, feet = { 8 }, finger = { 11, 12 }, trinket = { 13, 14 }, mainhand = { 16 },
	onehand = { 16, 17 }, twohand = { 16 }, offhand = { 17 }, ranged = { 18 }, relic = { 18 },
}
local BODY_ARMOR = { head = true, shoulder = true, chest = true, wrist = true, hands = true, waist = true, legs = true, feet = true }

function LG:SlotGroup(itemID)
	local record = self:ItemRecord(itemID)
	if record and record.invType then return GROUP_BY_INVTYPE[record.invType] end
	local equipLoc = select(4, C_Item.GetItemInfoInstant(itemID))
	if Secret(equipLoc) then return end
	return GROUP_BY_EQUIPLOC[equipLoc or ""]
end

---------------------------------------------------------------------------
-- Scores (the shared engine)
---------------------------------------------------------------------------
-- score for the player's spec, or nil when the engine cannot rate the item.
-- Kept as a field so a rating mode (or a test) can stand in.
function LG:ScoreItem(itemID)
	local engine = E.ItemScore
	if not (engine and itemID) then return end
	local result = engine:Rate("item:" .. itemID, "player")
	if result and type(result.score) == "number" and not Secret(result.score) then return result.score, result end
end

local function SpecKey()
	local engine = E.ItemScore
	return engine and engine.PlayerSpec and engine:PlayerSpec() or "none"
end

-- Changes when the spec's weights (stat priority) or the rating mode change.
local function PriorityKey(spec)
	local engine = E.ItemScore
	if not engine then return "" end
	local weights = engine.SpecWeights and engine:SpecWeights(spec) or {}
	local keys = {}
	for stat in pairs(weights) do keys[#keys + 1] = stat end
	table.sort(keys)
	local parts = { engine.GetRating and engine:GetRating() or "weights" }
	for _, stat in ipairs(keys) do parts[#parts + 1] = stat .. "=" .. tostring(weights[stat]) end
	return table.concat(parts, ",")
end

-- What the item checks before rating depend on: spec, level, list,
-- priority, data and the content phase (loot from a later phase is left
-- out). Everything but the gear the player wears.
local function BaseKey(level, phase)
	local spec = SpecKey()
	phase = phase or (LG.CurrentPhase and LG:CurrentPhase())
	return table.concat({ spec, tostring(level or LG:Player().level), LG:ListKey(), PriorityKey(spec),
		LG:HasData() and "data" or "live", tostring(phase or "all") }, "|")
end

-- The cache key for RankAll: the base key and the gear (scores compare
-- with the worn items).
function LG:RankKey(level, phase)
	return BaseKey(level, phase) .. "|" .. tostring(self.gearVersion or 0)
end

---------------------------------------------------------------------------
-- RankAll
---------------------------------------------------------------------------
local rankCache      -- { key, groups = { [group] = { { itemID, score, useLevel }, ... } } }
local job            -- the ranking under way
local rankOther      -- the result before (another phase or level)
-- The items that passed the checks gear does not change, per base key (the
-- last two, like the results): a gear change rates only these again
-- instead of reading every item of the database.
local passed = {}    -- { { key, items = { { itemID, group, useLevel, unique, subclass }, ... } }, ... }
local checking       -- the checks under way: { base, ids, next, items }

local function Passed(key)
	for _, entry in ipairs(passed) do
		if entry.key == key then return entry.items end
	end
end

local function KeepPassed(key, items)
	for index = #passed, 1, -1 do
		if passed[index].key == key then table.remove(passed, index) end
	end
	table.insert(passed, 1, { key = key, items = items })
	passed[3] = nil
end

-- Items to rank: every LootData item, or without it the ones the player
-- put on the wishlist or in a plan set and the ones seen at a vendor.
local function Candidates()
	local ids = {}
	local data = LG:HasData() and select(3, LG:DataStatus())
	if data and type(data.items) == "table" then
		for itemID in pairs(data.items) do ids[#ids + 1] = itemID end
	else
		local seen = {}
		local char = LG:Char()
		if char then
			for itemID in pairs(char.wishlist) do seen[itemID] = true end
			for index = 1, 2 do
				for _, itemID in pairs(char.sets[index].slots) do seen[itemID] = true end
			end
		end
		local store = LG:Cache().vendorCost
		for itemID in pairs(type(store) == "table" and store or {}) do seen[itemID] = true end
		for itemID in pairs(seen) do ids[#ids + 1] = tonumber(itemID) end
	end
	table.sort(ids)
	return ids
end

-- Changes that leave the checks as they are: the gear itself (that is the
-- point of keeping them), the bags, the money and the pages around them,
-- and item info arriving while the loot data gives every record. Anything
-- else (a quest turned in, a new skill or standing, an item on the wishlist
-- or in a plan set, new data) can add or remove an item: check every item
-- again. A ranking already under way then finishes with the checks it had
-- and is done again with new ones instead of being kept (see Step).
local KEEPS_CHECKS = {
	gear = true, rank = true, bags = true, wallet = true, pages = true, sim = true, pvpplan = true,
	searchindex = true, itemnames = true, world = true, events = true, vignettes = true,
	adventure = true, journey = true,
}
local generation = 0   -- goes up each time the kept checks are dropped
LG:On("rank-passed", function(changed)
	for what in pairs(changed) do
		if not (KEEPS_CHECKS[what] or (what == "items" and LG:HasData())) then
			wipe(passed)
			if checking then checking.stale = true end
			checking = nil
			generation = generation + 1
			return
		end
	end
end)
-- The checks the worn gear does not change: slot, level, phase, class and
-- the list's sources. The item's entry, or nil when it is left out.
local function Check(itemID, level, phase)
	local group = LG:SlotGroup(itemID)
	if not group then return end
	local useLevel = LG:UseLevel(itemID) or 1
	if useLevel > level then return end
	if phase and LG.IsFuturePhase and LG:IsFuturePhase(itemID, phase) then return end
	local record = LG:ItemRecord(itemID)
	if record then
		local ok = LG:CanUseRecord(record)
		if not ok then return end
	end
	if not LG:Obtainable(itemID) then return end
	return { itemID = itemID, group = group, useLevel = useLevel, unique = record and record.unique or false,
		subclass = record and record.subclass }
end

-- Rate one item that passed the checks into its slot group.
local function Rate(item, groups)
	local score = LG:ScoreItem(item.itemID)
	if not score or score <= 0 then return end
	local list = groups[item.group]
	if not list then
		list = {}
		groups[item.group] = list
	end
	list[#list + 1] = { itemID = item.itemID, score = score, useLevel = item.useLevel, unique = item.unique,
		subclass = item.subclass }
end

local function Finish(result)
	for _, list in pairs(result.groups) do
		table.sort(list, function(a, b)
			if a.score ~= b.score then return a.score > b.score end
			return a.itemID < b.itemID
		end)
		for index = #list, KEEP_PER_SLOT + 1, -1 do list[index] = nil end
	end
	return result
end

-- One frame of work: first the checks (shared by every ranking with the
-- same base key, so a gear change during them does not start them over),
-- then the rating of the items that passed.
local function Step()
	local current = job
	if not current then return end
	local budget = CHUNK
	local check = current.check
	if check then
		local stop = math.min(check.next + budget - 1, #check.ids)
		for index = check.next, stop do
			local ok, item = pcall(Check, check.ids[index], current.level, current.phase)
			if not ok then
				check.failed = true
				geterrorhandler()(item)
			elseif item then
				check.items[#check.items + 1] = item
			end
		end
		budget = budget - (stop - check.next + 1)
		check.next = stop + 1
		if check.next > #check.ids then
			if checking == check then checking = nil end
			if not (check.failed or check.stale) then KeepPassed(check.base, check.items) end
			current.items, current.check = check.items, nil
		end
	end
	if not current.check and budget > 0 then
		local items = current.items
		local stop = math.min(current.next + budget - 1, #items)
		for index = current.next, stop do
			local ok, err = pcall(Rate, items[index], current.result.groups)
			if not ok then geterrorhandler()(err) end
		end
		current.next = stop + 1
		if current.next > #items then
			job = nil
			-- The checks changed while this ranking ran: rank again once with
			-- new ones, for the same callers. If they changed again by then,
			-- the callers get this result, marked stale, and the next request
			-- ranks again (a steady stream of changes never holds them up).
			local stale = current.generation ~= generation
			if stale and current.reruns == 0 then
				LG:RankAll(nil, { level = current.result.planned and current.level or nil, phase = current.phase })
				if job then
					job.reruns = 1
					for _, fn in ipairs(current.callbacks) do table.insert(job.callbacks, fn) end
					return
				end
			end
			if rankCache and rankCache.key ~= current.key then rankOther = rankCache end
			rankCache = Finish(current.result)
			rankCache.stale = stale or nil
			LG:Fire("rank")
			for _, fn in ipairs(current.callbacks) do
				local ok, err = pcall(fn, rankCache)
				if not ok then geterrorhandler()(err) end
			end
			return
		end
	end
	C_Timer.After(0, Step)
end

-- fn(result) runs when the ranking is ready (at once when it is cached).
-- opts.level ranks for another level (planning); opts.phase for another
-- content phase (Best in Slot's phase chip; default the current phase).
-- Returns the result when it is cached, else nil (and starts the work).
-- The last two results stay cached, so For You (current phase) and a Best
-- in Slot plan for a later phase do not push each other out.
function LG:RankAll(fn, opts)
	local level = opts and tonumber(opts.level) or self:Player().level
	local phase = opts and tonumber(opts.phase) or (self.CurrentPhase and self:CurrentPhase())
	local base = BaseKey(level, phase)
	local key = base .. "|" .. tostring(self.gearVersion or 0)
	if rankOther and rankOther.key == key and not rankOther.stale then
		rankCache, rankOther = rankOther, rankCache
	end
	if rankCache and rankCache.key == key and not rankCache.stale then
		if fn then fn(rankCache) end
		return rankCache
	end
	if job and job.key == key then
		if fn then table.insert(job.callbacks, fn) end
		return
	end
	local items, check = Passed(base), nil
	if not items then
		if not (checking and checking.base == base) then
			checking = { base = base, ids = Candidates(), next = 1, items = {} }
		end
		check = checking
	end
	job = { key = key, base = base, level = level, phase = phase, items = items, check = check, next = 1, callbacks = {},
		generation = generation, reruns = 0,
		result = { key = key, level = level, phase = phase, planned = opts and opts.level ~= nil or nil, groups = {} } }
	if fn then table.insert(job.callbacks, fn) end
	C_Timer.After(0, Step)
end

function LG:RankStatus()
	if job and job.check then return "working", job.check.next - 1, #job.check.ids end
	if job then return "working", job.next - 1, #job.items end
	if rankCache and not rankCache.stale and rankCache.key == self:RankKey(rankCache.planned and rankCache.level or nil, rankCache.phase) then return "ready" end
	return rankCache and "stale" or "none"
end

function LG:ClearRanking()
	rankCache, rankOther, job, checking = nil, nil, nil, nil
	wipe(passed)
end

---------------------------------------------------------------------------
-- BiS resolver
---------------------------------------------------------------------------
local function Role()
	local engine = E.ItemScore
	local spec = engine and engine.PlayerSpec and engine:PlayerSpec()
	local info = spec and engine:SpecInfo(spec)
	return info and info.role or "DAMAGER"
end

local function LimitGroup(itemID) return E:ItemLimitGroup(itemID) end

local function Free(used, entry)
	if used[entry.itemID] and (entry.unique or used[entry.itemID] >= 2) then return false end
	local group, count = LimitGroup(entry.itemID)
	return not (group and (used.groups[group] or 0) >= count)
end

-- Pick from a ranked list: the first entry not in `used` (unique items
-- only once, one item of a shared group as often as the group allows),
-- and for tanks the heaviest armor kind when one is there.
local function Pick(list, used, heaviest)
	if not list then return end
	if heaviest then
		for _, entry in ipairs(list) do
			if entry.subclass == heaviest and Free(used, entry) then return entry end
		end
	end
	for _, entry in ipairs(list) do
		if Free(used, entry) then return entry end
	end
end

local function Use(used, entry)
	if not entry then return end
	used[entry.itemID] = (used[entry.itemID] or 0) + 1
	local group = LimitGroup(entry.itemID)
	if group then used.groups[group] = (used.groups[group] or 0) + 1 end
end

-- rank: a RankAll result. Returns { [slot] = itemID }, total score.
function LG:ResolveBiS(rank)
	local groups = rank and rank.groups or {}
	local player = self:Player()
	local tank = Role() == "TANK"
	local heaviest = tank and self:HeaviestArmor() or nil
	local set, used, total = {}, { groups = {} }, 0
	local function Put(slot, entry)
		if not entry then return end
		set[slot] = entry.itemID
		total = total + entry.score
		Use(used, entry)
	end
	for group, slots in pairs(self.GROUP_SLOTS) do
		if not (group == "mainhand" or group == "onehand" or group == "twohand" or group == "offhand"
			or group == "ranged" or group == "relic" or group == "finger" or group == "trinket") then
			Put(slots[1], Pick(groups[group], used, BODY_ARMOR[group] and heaviest or nil))
		end
	end
	-- Two rings and two trinkets: a unique one only once.
	for _, group in ipairs({ "finger", "trinket" }) do
		local slots = self.GROUP_SLOTS[group]
		Put(slots[1], Pick(groups[group], used))
		Put(slots[2], Pick(groups[group], used))
	end
	-- Weapons: the best two-hander against the best main hand plus off hand.
	local mainList = {}
	for _, group in ipairs({ "mainhand", "onehand" }) do
		for _, entry in ipairs(groups[group] or {}) do mainList[#mainList + 1] = entry end
	end
	table.sort(mainList, function(a, b) return a.score > b.score end)
	local probe = { groups = {} }
	for id, n in pairs(used) do if id ~= "groups" then probe[id] = n end end
	for group, n in pairs(used.groups) do probe.groups[group] = n end
	local main = Pick(mainList, probe)
	Use(probe, main)
	local offList = {}
	for _, entry in ipairs(groups.offhand or {}) do offList[#offList + 1] = entry end
	if player.dualWield then
		for _, entry in ipairs(groups.onehand or {}) do offList[#offList + 1] = entry end
	end
	table.sort(offList, function(a, b) return a.score > b.score end)
	local off = Pick(offList, probe)
	local two = Pick(groups.twohand, used)
	local pair = (main and main.score or 0) + (off and off.score or 0)
	if two and two.score >= pair then
		Put(16, two)
	else
		Put(16, main)
		Put(17, off)
	end
	-- Ranged slot: a relic for paladins, druids and shamans, else a ranged weapon.
	if player.relic then
		Put(18, Pick(groups.relic, used))
	else
		Put(18, Pick(groups.ranged, used))
	end
	return set, total
end

---------------------------------------------------------------------------
-- Upgrades, best instance
---------------------------------------------------------------------------
-- Score of what the player wears in a slot (nil when empty).
function LG:WornScore(slot)
	local id = self:Player().equipped[slot]
	return id and (self:ScoreItem(id) or 0) or nil
end

-- The equipment slots an item beats: { { slot, gain, worn } }, best first.
function LG:UpgradeTargets(itemID)
	local group = self:SlotGroup(itemID)
	local score = group and self:ScoreItem(itemID)
	if not score then return {} end
	local targets = {}
	for _, slot in ipairs(self.GROUP_SLOTS[group] or {}) do
		local worn = self:WornScore(slot)
		local gain = score - (worn or 0)
		if gain > 0 then targets[#targets + 1] = { slot = slot, gain = gain, worn = worn } end
	end
	table.sort(targets, function(a, b) return a.gain > b.gain end)
	return targets
end

-- From a RankAll result: the items that beat what you wear, biggest gain
-- first: { { itemID, gain, slot, useLevel } } (n at most).
function LG:NextUpgrades(n, rank)
	rank = rank or rankCache
	if not rank then return {} end
	local list, seen = {}, {}
	for _, entries in pairs(rank.groups) do
		for _, entry in ipairs(entries) do
			if not seen[entry.itemID] and not self:Owns(entry.itemID) then
				seen[entry.itemID] = true
				local target = self:UpgradeTargets(entry.itemID)[1]
				if target then
					list[#list + 1] = { itemID = entry.itemID, gain = target.gain, slot = target.slot, useLevel = entry.useLevel }
				end
			end
		end
	end
	table.sort(list, function(a, b)
		if a.gain ~= b.gain then return a.gain > b.gain end
		return a.itemID < b.itemID
	end)
	for index = #list, (n or 10) + 1, -1 do list[index] = nil end
	return list
end

-- The instance (fit for your level) whose drops add the most: key, gain, items.
function LG:BestInstance(rank)
	local upgrades = self:NextUpgrades(50, rank)
	local fits = {}
	for _, inst in ipairs(self:InstancesForLevel(self:Player().level, nil, true)) do fits[inst.key] = true end
	local sums, items = {}, {}
	for _, upgrade in ipairs(upgrades) do
		local counted = {}
		for _, entry in ipairs(self:ItemSources(upgrade.itemID) or {}) do
			local key = entry.instance
			if key and fits[key] and not counted[key] then
				counted[key] = true
				sums[key] = (sums[key] or 0) + upgrade.gain
				items[key] = items[key] or {}
				table.insert(items[key], upgrade.itemID)
			end
		end
	end
	local best, bestGain
	for key, gain in pairs(sums) do
		if not bestGain or gain > bestGain or (gain == bestGain and key < best) then best, bestGain = key, gain end
	end
	return best, bestGain, best and items[best] or nil
end

-- Instances under their group (Dire Maul wings under Dire Maul):
-- { { key, name, children = { key, ... } }, ... } in LootData order.
function LG:InstanceGroups()
	local data = select(3, self:DataStatus())
	if not (data and type(data.instances) == "table") then return {} end
	local order = type(data.instanceOrder) == "table" and data.instanceOrder or {}
	local groups, byKey = {}, {}
	for _, key in ipairs(order) do
		local inst = data.instances[key]
		if inst then
			local parent = inst.parent or key
			local group = byKey[parent]
			if not group then
				group = { key = parent, name = (data.instances[parent] and self:InstanceName(parent)) or parent, children = {} }
				byKey[parent] = group
				groups[#groups + 1] = group
			end
			if parent ~= key then table.insert(group.children, key) end
		end
	end
	return groups
end

---------------------------------------------------------------------------
-- Obsolete: you already own something better for that slot
---------------------------------------------------------------------------
-- true, betterItemID when owned items fill every slot of the item's group
-- with a higher score.
function LG:IsObsolete(itemID)
	itemID = tonumber(itemID)
	local group = itemID and self:SlotGroup(itemID)
	local score = group and self:ScoreItem(itemID)
	if not score then return false end
	local need = #(self.GROUP_SLOTS[group] or { 1 })
	if group == "onehand" then need = 1 end
	local better, best = 0, nil
	for owned in pairs(self:OwnedGear()) do
		if owned ~= itemID then
			local ownedGroup = self:SlotGroup(owned)
			local fits = ownedGroup == group
				or (group == "onehand" and (ownedGroup == "mainhand" or ownedGroup == "twohand"))
				or (group == "mainhand" and (ownedGroup == "onehand" or ownedGroup == "twohand"))
			if fits then
				local ownedScore = self:ScoreItem(owned)
				if ownedScore and ownedScore >= score then
					better = better + 1
					best = best or owned
				end
			end
		end
	end
	if better >= need then return true, best end
	return false
end
