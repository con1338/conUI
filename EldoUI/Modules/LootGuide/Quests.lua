-- EldoUI Loot Guide: the quest engine.
--
--   LG:Quest(questID)            the decoded EldoUI_LootData record
--   LG:QuestStatus(questID)      status, detail (see STATUS_ORDER)
--   LG:QuestSide(questID)        "Alliance", "Horde" or nil (both)
--   LG:QuestForFaction(id, f)    does the quest belong to "mine", "Alliance", "Horde", "all"
--   LG:QuestChain(questID)       the whole chain, each step before / current / after
--   LG:ClientQuestLine(questID)  the client's quest line of a quest the data does not know
--   LG:QuestGraph(questID, f)    the chain with its branches, for a flowchart
--   LG:InstanceQuests(key, opts) quests of an instance, sorted by status, one per chain
--   LG:InstanceQuestCounts(key)  total, open, done
--   LG:QuestReward(questID)      xp, money, live: the game's own numbers when you saw
--                                the quest (cached account-wide), else the data's money
--   LG:QuestObjectives(questID)  live progress while it is in your log, else what the data asks
--   LG:IsKeyQuest(questID)       rewards a key (access quest)
--   (records also carry minRep = { faction, value } and breadcrumbFor, data 1.3.0)
--
-- The Journal's quest data (end of this file):
--   LG:JourneyQuest(questID)     one merged record: data <- Forever overlay <- seen by you
--   LG:JourneyQuests(opts)       quests that fit a level, side and class (the where-next input)
--   LG:QuestFit(level[, player]) "red", "orange", "yellow", "green" or "gray" for a quest level
--   LG:IsQuestRemoved(questID)   the overlay says the quest is gone from WoW: Forever
--   LG:JourneyDataStatus()       versions and counts; LG:JourneyDataText() the footer line
--   LG:JourneyReport()           the "!EUJD1!" block of what you saw, for a journal-data issue
--   LG:JourneyChanged()          the seen store changed (Observe.lua calls it)
--   LG:JourneyCheck(opts, fn)    after a Forever patch: which data quests the game no longer knows
--   LG:JourneyZoneCheck()        zones whose level range in the game differs from Data/Zones.lua
--
-- Status comes from the game (C_QuestLog: flagged completed, on quest,
-- ready for turn-in, objectives). Nothing here accepts, turns in or skips a
-- quest. Prerequisites: all-of (every one done), any-of (one done), and
-- "must be active" quests (CMaNGOS's negative PrevQuestId).
local _, E = ...
local LG = E.LootGuide
local L = E.L

local Key = E.Key
local Secret = E.Secret

local function Data()
	return select(3, LG:DataStatus())
end

-- Status keys in list order.
LG.QUEST_STATUS = { "turnin", "active", "available", "locked", "low", "done", "notforyou" }
LG.QUEST_STATUS_TITLE = E:TranslateValues({
	turnin = E.Key("Ready to turn in"), active = E.Key("In your quest log"), available = E.Key("Available"), locked = E.Key("Locked"),
	low = E.Key("Level too low"), done = E.Key("Completed"), notforyou = E.Key("Not for you"),
})
local STATUS_RANK = {}
for index, key in ipairs(LG.QUEST_STATUS) do STATUS_RANK[key] = index end
LG.QUEST_STATUS_RANK = STATUS_RANK

-- Race masks per side (Classic races: 1 Human, 3 Dwarf, 4 Night Elf,
-- 7 Gnome / 2 Orc, 5 Undead, 6 Tauren, 8 Troll).
local ALLIANCE = 1 + 4 + 8 + 64
local HORDE = 2 + 16 + 32 + 128

---------------------------------------------------------------------------
-- Records
---------------------------------------------------------------------------
local function IdList(text)
	local out = {}
	for id in tostring(text or ""):gmatch("%-?%d+") do out[#out + 1] = tonumber(id) end
	return out
end

local function Pairs(text)
	local out = {}
	for id, count in tostring(text or ""):gmatch("(%d+):(%-?%d+)") do out[#out + 1] = { id = tonumber(id), count = tonumber(count) } end
	return out
end

local function Places(text)
	local out = {}
	for kind, id in tostring(text or ""):gmatch("([noi])(%d+)") do
		out[#out + 1] = { kind = kind == "n" and "npc" or kind == "o" and "object" or "item", id = tonumber(id) }
	end
	return out
end

local function Targets(text)
	local out = {}
	for kind, id, count in tostring(text or ""):gmatch("([no])(%d+):(%d+)") do
		out[#out + 1] = { kind = kind == "n" and "npc" or "object", id = tonumber(id), count = tonumber(count) }
	end
	return out
end

local cache = {}
LG:On("quests-engine", function(changed)
	if changed.data then wipe(cache) end
end)

local function Build(questID)
	local LD = Data()
	local packed = LD and LD.quests and LD.quests[questID]
	if type(packed) ~= "string" then return false end
	local f = LG.Split(packed, "|")
	local skill, skillValue = (f[24] or ""):match("^(%d+):(%d+)$")
	local rep = {}
	for faction, value in (f[21] or ""):gmatch("(%d+):(%-?%d+)") do rep[#rep + 1] = { faction = tonumber(faction), value = tonumber(value) } end
	local minRepFaction, minRepValue = (f[26] or ""):match("^(%d+):(%-?%d+)$")
	return {
		minRep = minRepFaction and { faction = tonumber(minRepFaction), value = tonumber(minRepValue) } or nil,
		breadcrumbFor = tonumber(f[28]),
		id = questID, title = LG:QuestTitle(questID) or f[1], level = tonumber(f[2]), minLevel = tonumber(f[3]),
		raceMask = tonumber(f[4]), classMask = tonumber(f[5]), zoneOrSort = tonumber(f[6]),
		instance = f[7] ~= "" and f[7] or nil, allOf = IdList(f[8]), anyOf = IdList(f[9]), activeQuest = tonumber(f[10]),
		exclusiveGroup = tonumber(f[11]), nextInChain = tonumber(f[12]), starts = Places(f[13]), ends = Places(f[14]),
		reqItems = Pairs(f[15]), reqTargets = Targets(f[16]), choice = Pairs(f[17]), rewards = Pairs(f[18]),
		money = tonumber(f[19]), moneyAtMax = tonumber(f[20]), reputation = rep, type = tonumber(f[22]),
		suggested = tonumber(f[23]), skill = tonumber(skill), skillValue = tonumber(skillValue), providedItem = tonumber(f[25]),
		-- The objective text in the client language when EldoUI_LootData has
		-- it (LD.L is built for the client's own language only), else English.
		text = (type(LD.L) == "table" and type(LD.L.questText) == "table" and LD.L.questText[questID])
			or (LD.questText and LD.questText[questID]) or nil,
	}
end

function LG:Quest(questID)
	questID = tonumber(questID)
	if not questID then return end
	local value = cache[questID]
	if value == nil then
		value = Build(questID)
		cache[questID] = value
	end
	return value or nil
end

-- "Alliance", "Horde" or nil (open to both).
function LG:QuestSide(questID)
	local quest = self:Quest(questID)
	local mask = quest and quest.raceMask
	if not mask or mask == 0 then return end
	if bit.band(mask, HORDE) == 0 and bit.band(mask, ALLIANCE) ~= 0 then return "Alliance" end
	if bit.band(mask, ALLIANCE) == 0 and bit.band(mask, HORDE) ~= 0 then return "Horde" end
end

-- filter: "mine" (default), "Alliance", "Horde", "all".
function LG:QuestForFaction(questID, filter)
	filter = filter or "mine"
	if filter == "all" then return true end
	local side = self:QuestSide(questID)
	if not side then return true end
	if filter == "mine" then filter = self:Player().faction or side end
	return side == filter
end

-- Rewards a key item (item class 13): an access quest.
function LG:IsKeyQuest(questID)
	local quest = self:Quest(questID)
	if not quest then return false end
	for _, list in ipairs({ quest.rewards, quest.choice }) do
		for _, reward in ipairs(list) do
			local record = self:ItemRecord(reward.id)
			if record and record.class == 13 then return true end
		end
	end
	return false
end

---------------------------------------------------------------------------
-- Status
---------------------------------------------------------------------------
local function Log(name, questID)
	local log = C_QuestLog
	if not (log and log[name]) then return false end
	local ok, value = pcall(log[name], questID)
	if not ok or Secret(value) then return false end
	return value and true or false
end

function LG:OnQuest(questID)
	return Log("IsOnQuest", questID)
end

-- status, detail. detail: the missing quest (locked), the level (low).
function LG:QuestStatus(questID)
	questID = tonumber(questID)
	local quest = self:Quest(questID)
	if not quest then
		if self:QuestDone(questID) then return "done" end
		if self:OnQuest(questID) then return "active" end
		return "available"
	end
	if self:QuestDone(questID) then return "done" end
	local player = self:Player()
	if quest.raceMask and quest.raceMask > 0 and player.raceMask > 0 and bit.band(quest.raceMask, player.raceMask) == 0 then
		return "notforyou", "race"
	end
	if quest.classMask and quest.classMask > 0 and player.classMask > 0 and bit.band(quest.classMask, player.classMask) == 0 then
		return "notforyou", "class"
	end
	if self:OnQuest(questID) then
		if Log("ReadyForTurnIn", questID) or Log("IsComplete", questID) then return "turnin" end
		return "active"
	end
	if quest.skill and quest.skill > 0 then
		local rank = player.professions[quest.skill]
		if not rank then return "notforyou", "skill" end
	end
	for _, id in ipairs(quest.allOf) do
		if id > 0 and not self:QuestDone(id) then return "locked", id end
	end
	if #quest.anyOf > 0 then
		local any = false
		for _, id in ipairs(quest.anyOf) do
			if self:QuestDone(id) then any = true break end
		end
		if not any then return "locked", quest.anyOf[1] end
	end
	if quest.activeQuest and quest.activeQuest > 0 and not self:OnQuest(quest.activeQuest) then
		return "locked", quest.activeQuest
	end
	if quest.minLevel and quest.minLevel > player.level then return "low", quest.minLevel end
	return "available"
end

function LG:QuestOpen(status)
	return status == "turnin" or status == "active" or status == "available"
end

---------------------------------------------------------------------------
-- Chains
---------------------------------------------------------------------------
local nextIndex   -- questID -> { quests that list it as a prerequisite }
local prevIndex   -- questID -> quest whose nextInChain is this one

local function Indexes()
	if nextIndex then return end
	nextIndex, prevIndex = {}, {}
	local LD = Data()
	for questID in pairs(LD and LD.quests or {}) do
		local quest = LG:Quest(questID)
		if quest then
			for _, list in ipairs({ quest.allOf, quest.anyOf }) do
				for _, prev in ipairs(list) do
					if prev > 0 then
						nextIndex[prev] = nextIndex[prev] or {}
						table.insert(nextIndex[prev], questID)
					end
				end
			end
			if quest.nextInChain and quest.nextInChain > 0 then prevIndex[quest.nextInChain] = prevIndex[quest.nextInChain] or questID end
		end
	end
	for _, list in pairs(nextIndex) do table.sort(list) end
end

LG:On("quests-chain", function(changed)
	if changed.data then nextIndex, prevIndex = nil, nil end
end)

local function Previous(quest)
	if quest.allOf[1] and quest.allOf[1] > 0 then return quest.allOf[1] end
	if quest.anyOf[1] then return quest.anyOf[1] end
	return prevIndex[quest.id]
end

local function Following(quest, side)
	if quest.nextInChain and quest.nextInChain > 0 then return quest.nextInChain end
	local list = nextIndex[quest.id]
	if not list then return end
	-- Prefer a follow-up of the same side and instance.
	for _, id in ipairs(list) do
		local other = LG:Quest(id)
		if other and other.instance == quest.instance and (not side or LG:QuestForFaction(id, side)) then return id end
	end
	for _, id in ipairs(list) do
		if not side or LG:QuestForFaction(id, side) then return id end
	end
end

-- The client's quest line that holds a quest: line id, its quests in order
-- and its English name, from Data/QuestLines.lua. The game's own list
-- (C_QuestLine.GetQuestLineQuests) wins when it gives one that holds the
-- quest. nil for a quest in no line.
local lineOf
function LG:ClientQuestLine(questID)
	local lines = E.QuestLines
	questID = tonumber(questID)
	if type(lines) ~= "table" or not questID then return end
	if not lineOf then
		lineOf = {}
		for lineID, line in pairs(lines) do
			for _, id in ipairs(line.quests or {}) do lineOf[id] = lineID end
		end
	end
	local lineID = lineOf[questID]
	if not lineID then return end
	local quests = lines[lineID].quests
	local api = C_QuestLine and C_QuestLine.GetQuestLineQuests
	if api then
		local ok, list = pcall(api, lineID)
		if ok and type(list) == "table" and #list > 0 then
			local live, holds = {}, false
			for index, id in ipairs(list) do
				if Secret(id) or type(id) ~= "number" then live = nil break end
				live[index] = id
				if id == questID then holds = true end
			end
			if live and holds then quests = live end
		end
	end
	return lineID, quests, lines[lineID].name
end

-- A chain from the client's quest line, for a quest the data does not
-- know; titles the game has not sent yet are asked for.
local function LineChain(questID)
	local _, quests = LG:ClientQuestLine(questID)
	if not quests or #quests < 2 then return end
	local chain, step = {}, "before"
	for index, id in ipairs(quests) do
		if id == questID then step = "current" end
		chain[index] = { id = id, step = step, part = index, line = true }
		if step == "current" then step = "after" end
		if C_QuestLog and C_QuestLog.RequestLoadQuestByID and not LG:QuestTitle(id) then
			pcall(C_QuestLog.RequestLoadQuestByID, id)
		end
	end
	return chain
end

-- { { id, step = "before" | "current" | "after", part = n, instance }, ... }
-- (a single quest: one step). A quest the data does not know takes its
-- chain from the client's quest line (step.line = true), else stands alone.
function LG:QuestChain(questID)
	questID = tonumber(questID)
	local quest = self:Quest(questID)
	if not quest then return LineChain(questID) or { { id = questID, step = "current", part = 1 } } end
	Indexes()
	local side = self:QuestSide(questID)
	local before, seen = {}, { [questID] = true }
	local cursor = quest
	for _ = 1, 25 do
		local prev = Previous(cursor)
		local prevQuest = prev and not seen[prev] and self:Quest(prev)
		if not prevQuest then break end
		seen[prev] = true
		table.insert(before, 1, prev)
		cursor = prevQuest
	end
	local after = {}
	cursor = quest
	for _ = 1, 25 do
		local nextID = Following(cursor, side)
		local nextQuest = nextID and not seen[nextID] and self:Quest(nextID)
		if not nextQuest then break end
		seen[nextID] = true
		after[#after + 1] = nextID
		cursor = nextQuest
	end
	local chain = {}
	for _, id in ipairs(before) do chain[#chain + 1] = { id = id, step = "before" } end
	chain[#chain + 1] = { id = questID, step = "current" }
	for _, id in ipairs(after) do chain[#chain + 1] = { id = id, step = "after" } end
	for index, step in ipairs(chain) do
		step.part = index
		local q = self:Quest(step.id)
		step.instance = q and q.instance
	end
	return chain
end

-- The chain with every branch, for a flowchart: each quest reached through
-- a prerequisite (all-of, any-of, must be active) or a follow-up, one node
-- per quest. faction: "mine" (default), "Alliance", "Horde" or "all";
-- another side's quests are left out, the quest asked for always shows.
-- The nearest quests come first, up to QUEST_GRAPH_MAX (capped = true when
-- more were left out). A loop in the data is cut where it closes.
-- { list, byId, sideList = {}, capped, line } with steps
-- { id = "q<questID>", kind = "quest", ref, quest, follows, next, any, faction, layer, index };
-- line: no quest has more than one before or after it.
LG.QUEST_GRAPH_MAX = 40

function LG:QuestGraph(questID, faction)
	questID = tonumber(questID)
	if not (questID and self:Quest(questID)) then return end
	Indexes()
	faction = faction or "mine"
	local keep, order, capped = { [questID] = true }, { questID }, false
	local function Visit(id)
		id = tonumber(id)
		if not id or id <= 0 or keep[id] then return end
		if not self:Quest(id) or not self:QuestForFaction(id, faction) then return end
		if #order >= self.QUEST_GRAPH_MAX then
			capped = true
			return
		end
		keep[id] = true
		order[#order + 1] = id
	end
	local head = 1
	while head <= #order do
		local quest = self:Quest(order[head])
		head = head + 1
		for _, list in ipairs({ quest.allOf, quest.anyOf }) do
			for _, prev in ipairs(list) do Visit(prev) end
		end
		Visit(quest.activeQuest)
		Visit(prevIndex[quest.id])
		Visit(quest.nextInChain)
		for _, nextID in ipairs(nextIndex[quest.id] or {}) do Visit(nextID) end
	end
	local graph = { list = {}, byId = {}, sideList = {}, capped = capped }
	for position, id in ipairs(order) do
		local step = { id = "q" .. id, kind = "quest", ref = id, quest = id, follows = {}, position = position,
			faction = self:QuestSide(id) }
		graph.list[#graph.list + 1] = step
		graph.byId[step.id] = step
	end
	-- Edges: what a quest needs first. A lone any-of counts as needed; only
	-- a join of any-of quests alone is "one of these".
	local function Link(step, from, set)
		if keep[from] and from ~= step.quest and not set[from] then
			set[from] = true
			step.follows[#step.follows + 1] = "q" .. from
			return true
		end
	end
	local sets = {}
	for _, step in ipairs(graph.list) do
		local quest = self:Quest(step.quest)
		local set = {}
		sets[step.id] = set
		for _, prev in ipairs(quest.allOf) do Link(step, prev, set) end
		Link(step, quest.activeQuest, set)
		step.needed = #step.follows
		for _, prev in ipairs(quest.anyOf) do Link(step, prev, set) end
		step.anyOf = #step.follows - step.needed
	end
	for _, step in ipairs(graph.list) do
		local nextID = self:Quest(step.quest).nextInChain
		local target = nextID and graph.byId["q" .. nextID]
		if target and Link(target, step.quest, sets[target.id]) then target.needed = target.needed + 1 end
	end
	for _, step in ipairs(graph.list) do
		step.any = step.needed == 0 and step.anyOf > 1
		step.needed, step.anyOf = nil, nil
	end
	-- Layers: the longest path from a first quest; an edge back into the
	-- path being walked closes a loop and is dropped.
	local depth, walking = {}, {}
	local function Depth(step)
		if depth[step.id] then return depth[step.id] end
		walking[step.id] = true
		local best, kept = 0, {}
		for _, from in ipairs(step.follows) do
			if not walking[from] then
				kept[#kept + 1] = from
				best = math.max(best, Depth(graph.byId[from]))
			end
		end
		step.follows = kept
		walking[step.id] = nil
		depth[step.id] = best + 1
		return best + 1
	end
	for _, step in ipairs(graph.list) do step.layer = Depth(step) end
	table.sort(graph.list, function(a, b)
		if a.layer ~= b.layer then return a.layer < b.layer end
		return a.position < b.position
	end)
	for index, step in ipairs(graph.list) do
		step.index = index
		step.next = {}
	end
	for _, step in ipairs(graph.list) do
		for _, from in ipairs(step.follows) do
			local up = graph.byId[from].next
			up[#up + 1] = step.id
		end
	end
	local line = true
	for _, step in ipairs(graph.list) do
		if #step.follows > 1 or #step.next > 1 then line = false end
	end
	graph.line = line
	return graph
end

-- The first quest of a chain (its key for "one row per chain").
function LG:ChainRoot(questID)
	local chain = self:QuestChain(questID)
	return chain[1] and chain[1].id or questID
end

---------------------------------------------------------------------------
-- Instance quests
---------------------------------------------------------------------------
function LG:InstanceQuestIDs(key)
	local LD = Data()
	local inst = LD and LD.instances and LD.instances[key]
	local ids, seen = {}, {}
	local function Add(text)
		for _, id in ipairs(IdList(text)) do
			if id > 0 and not seen[id] then
				seen[id] = true
				ids[#ids + 1] = id
			end
		end
	end
	if inst then
		Add(inst.quests)
		local group = inst.parent and LD.groups and LD.groups[inst.parent]
		if group then Add(group.quests) end
	end
	return ids
end

-- opts: faction ("mine"), chains (one row per chain, default true).
-- { { id, status, detail, key = bool, chainLength }, ... } in status order.
function LG:InstanceQuests(key, opts)
	opts = opts or {}
	local faction = opts.faction or "mine"
	local rows, byRoot = {}, {}
	for _, id in ipairs(self:InstanceQuestIDs(key)) do
		if self:Quest(id) and self:QuestForFaction(id, faction) then
			local status, detail = self:QuestStatus(id)
			local row = { id = id, status = status, detail = detail, key = self:IsKeyQuest(id) }
			if opts.chains ~= false then
				local chain = self:QuestChain(id)
				row.chainLength = #chain
				local root = chain[1].id
				local other = byRoot[root]
				if not other then
					byRoot[root] = row
					rows[#rows + 1] = row
				elseif STATUS_RANK[status] < STATUS_RANK[other.status] then
					-- The step that needs you now stands for the chain.
					for field, value in pairs(row) do other[field] = value end
				end
			else
				rows[#rows + 1] = row
			end
		end
	end
	local level = self:Player().level
	table.sort(rows, function(a, b)
		if a.status ~= b.status then return STATUS_RANK[a.status] < STATUS_RANK[b.status] end
		local qa, qb = self:Quest(a.id), self:Quest(b.id)
		local la, lb = qa.level or level, qb.level or level
		if la ~= lb then return la < lb end
		return (qa.title or "") < (qb.title or "")
	end)
	return rows
end

-- total, open, done (your side, every quest, not one per chain).
function LG:InstanceQuestCounts(key)
	local total, open, done = 0, 0, 0
	for _, row in ipairs(self:InstanceQuests(key, { chains = false })) do
		if row.status ~= "notforyou" then
			total = total + 1
			if row.status == "done" then done = done + 1 elseif self:QuestOpen(row.status) then open = open + 1 end
		end
	end
	return total, open, done
end

---------------------------------------------------------------------------
-- Rewards: live XP and money
---------------------------------------------------------------------------
local function RewardCache(create)
	local cacheTable = LG:Cache()
	if type(cacheTable.questReward) ~= "table" then
		if not create then return end
		cacheTable.questReward = {}
	end
	return cacheTable.questReward
end

-- xp, money, live
function LG:QuestReward(questID)
	questID = tonumber(questID)
	local store = RewardCache(false)
	local seen = store and store[questID]
	if type(seen) == "table" then return seen.xp, seen.money, true end
	local quest = self:Quest(questID)
	if not quest then return end
	local maxLevel = GetMaxPlayerLevel and GetMaxPlayerLevel() or 60
	if Secret(maxLevel) then maxLevel = 60 end
	local money = (self:Player().level >= maxLevel and quest.moneyAtMax and quest.moneyAtMax > 0) and quest.moneyAtMax or quest.money
	return nil, money, false
end

-- Read the quest frame's own numbers (QUEST_DETAIL, QUEST_COMPLETE): only
-- below the level cap and within 5 levels of the quest, so the XP is a
-- full-value number.
function LG:CaptureQuestReward()
	local questID = GetQuestID and GetQuestID()
	if Secret(questID) or not questID or questID == 0 then return end
	local level = self:Player().level
	local maxLevel = GetMaxPlayerLevel and GetMaxPlayerLevel() or 60
	if Secret(maxLevel) or level >= maxLevel then return end
	local quest = self:Quest(questID)
	if quest and quest.level and quest.level > 0 and math.abs(quest.level - level) > 5 then return end
	local xp = GetRewardXP and GetRewardXP()
	local money = GetRewardMoney and GetRewardMoney()
	if Secret(xp) or Secret(money) then return end
	xp, money = tonumber(xp), tonumber(money)
	if not xp and not money then return end
	RewardCache(true)[questID] = { xp = xp, money = money }
	self:Fire("questRewards")
	return xp, money
end

LG:Listen("QUEST_DETAIL", "quests", function() LG:CaptureQuestReward() end)
LG:Listen("QUEST_COMPLETE", "quests", function() LG:CaptureQuestReward() end)

---------------------------------------------------------------------------
-- Objectives
---------------------------------------------------------------------------
-- { live = bool, rows = { { text, done, have, need, itemID, npc, object } } }
function LG:QuestObjectives(questID)
	questID = tonumber(questID)
	local out = { live = false, rows = {} }
	if self:OnQuest(questID) and C_QuestLog and C_QuestLog.GetQuestObjectives then
		local ok, list = pcall(C_QuestLog.GetQuestObjectives, questID)
		if ok and type(list) == "table" and #list > 0 then
			out.live = true
			for _, objective in ipairs(list) do
				local text = objective.text
				if type(text) == "string" and not Secret(text) then
					local done = objective.finished
					out.rows[#out.rows + 1] = { text = text, done = not Secret(done) and done and true or false,
						have = not Secret(objective.numFulfilled) and objective.numFulfilled or nil,
						need = not Secret(objective.numRequired) and objective.numRequired or nil }
				end
			end
			return out
		end
	end
	local quest = self:Quest(questID)
	if not quest then return out end
	for _, item in ipairs(quest.reqItems) do
		out.rows[#out.rows + 1] = { itemID = item.id, need = item.count }
	end
	for _, target in ipairs(quest.reqTargets) do
		out.rows[#out.rows + 1] = { npc = target.kind == "npc" and target.id or nil, object = target.kind == "object" and target.id or nil,
			need = target.count }
	end
	return out
end

---------------------------------------------------------------------------
-- Refresh on real changes only: the set of quests in the log and their
-- completion, compared each QUEST_LOG_UPDATE.
---------------------------------------------------------------------------
local logSignature

local function Signature()
	local log = C_QuestLog
	if not (log and log.GetNumQuestLogEntries and log.GetInfo) then return "" end
	local ok, count = pcall(log.GetNumQuestLogEntries)
	if not ok or Secret(count) or type(count) ~= "number" then return "" end
	local parts = {}
	for index = 1, count do
		local fine, info = pcall(log.GetInfo, index)
		if fine and type(info) == "table" and not info.isHeader and type(info.questID) == "number" and not Secret(info.questID) then
			local complete = Log("IsComplete", info.questID)
			parts[#parts + 1] = info.questID .. (complete and "c" or "")
		end
	end
	table.sort(parts)
	return table.concat(parts, ",")
end

local function LogChanged()
	local signature = Signature()
	if signature ~= logSignature then
		logSignature = signature
		LG:Fire("quests")
	end
end

LG:Listen("QUEST_LOG_UPDATE", "quests", LogChanged)
LG:Listen("QUEST_ACCEPTED", "quests", LogChanged)
LG:Listen("QUEST_REMOVED", "quests", LogChanged)

---------------------------------------------------------------------------
-- The Journal's quest data (plan section 11)
--
-- Three layers, merged per quest in this order (a later one wins):
--   1. data: EldoUI_LootData's Quests.lua (dungeon and reward quests, full
--      records) and Journey.lua (every other quest, lean records). Classic
--      values (GPL-3.0, generated from classic-db).
--   2. overlay: E.foreverData from Data/Forever.lua (our own facts about
--      WoW: Forever, Apache-2.0, generated from tools/lootdata/overrides/
--      forever.json; it loads without EldoUI_LootData): "new" quests the
--      data lacks, "changed" fields and "removed" quests.
--   3. seen: what the game showed you, EldoUIDB.journalSeen (kept by the
--      Journal's Observe.lua):
--        journalSeen = { v = 1, rev = n,
--          quests = { [questID] = { t, title, level, minLevel, giver, giverName, map, x, y,
--                                   header, plevel, faction, ender, enderName, xp, money } },
--          instances = { [instanceMapID] = { t, name, size, min, max } },
--          zones = { [uiMapID] = { t, name, min, max } } }
--      giver and ender are npc ids; x and y are map fractions on the map
--      uiMapID. Observe.lua calls LG:JourneyChanged() after a write.
-- Every record says where its facts came from (provenance "classic",
-- "forever" or "seen", plus changed = { field = true }), so a page can show
-- "Classic values", "New in Forever" or "Seen by you". Nothing here reads
-- combat data or acts on a quest.
---------------------------------------------------------------------------
local CLASS_BITS = { WARRIOR = 1, PALADIN = 2, HUNTER = 4, ROGUE = 8, PRIEST = 16, SHAMAN = 64, MAGE = 128, WARLOCK = 256, DRUID = 1024 }
local SEEN_QUEST_FIELDS = { "title", "level", "minLevel", "giver", "giverName", "map", "x", "y", "header", "plevel", "faction",
	"ender", "enderName", "xp", "money" }
local SEEN_INSTANCE_FIELDS = { "name", "size", "min", "max" }
local SEEN_ZONE_FIELDS = { "name", "min", "max" }

local journeyCache, journeyIndex = {}, nil

local function Overlay()
	local data = E.foreverData
	return type(data) == "table" and data or nil
end

local function Seen()
	local db = rawget(_G, "EldoUIDB")
	local seen = type(db) == "table" and db.journalSeen
	return type(seen) == "table" and seen or nil
end

local function SeenQuest(questID)
	local seen = Seen()
	local quests = seen and seen.quests
	local row = type(quests) == "table" and quests[questID]
	return type(row) == "table" and row or nil
end

function LG:JourneyChanged()
	wipe(journeyCache)
	journeyIndex = nil
	self:Fire("journey")
end

LG:On("quests-journey", function(changed)
	if changed.data then
		wipe(journeyCache)
		journeyIndex = nil
	end
end)

local function Number(value)
	if Secret(value) then return nil end
	if type(value) == "number" then return value end
	return tonumber(value)
end

local function Text(value)
	if Secret(value) or type(value) ~= "string" or value == "" then return nil end
	return value
end

-- Journey.lua: "title|level|minLevel|raceMask|classMask|zoneOrSort|starts|ends|allOf|anyOf|activeQuest|
-- nextInChain|breadcrumbFor|suggestedPlayers|type|skill:value|flags" (flags: r repeatable, u no spawned giver)
local function JourneyRecord(questID)
	local LD = Data()
	local packed = LD and LD.journey and LD.journey[questID]
	if type(packed) ~= "string" then return nil end
	local f = LG.Split(packed, "|")
	local skill, skillValue = (f[16] or ""):match("^(%d+):(%d+)$")
	local flags = f[17] or ""
	return {
		id = questID, title = LG:DataName("quest", questID, f[1]), level = tonumber(f[2]), minLevel = tonumber(f[3]),
		raceMask = tonumber(f[4]), classMask = tonumber(f[5]), zoneOrSort = tonumber(f[6]), starts = Places(f[7]), ends = Places(f[8]),
		allOf = IdList(f[9]), anyOf = IdList(f[10]), activeQuest = tonumber(f[11]), nextInChain = tonumber(f[12]),
		breadcrumbFor = tonumber(f[13]), suggested = tonumber(f[14]), type = tonumber(f[15]),
		skill = tonumber(skill), skillValue = tonumber(skillValue),
		repeatable = flags:find("r", 1, true) and true or nil, giverUnknown = flags:find("u", 1, true) and true or nil,
	}
end

local function FromLootData(questID)
	local quest = LG:Quest(questID)
	if quest then
		local copy = {}
		for key, value in pairs(quest) do copy[key] = value end
		copy.full = true
		return copy
	end
	return JourneyRecord(questID)
end

local function Place(place)
	if type(place) ~= "table" then return nil end
	return { npc = Number(place.npc), object = Number(place.object), name = Text(place.name), map = Number(place.map),
		x = Number(place.x), y = Number(place.y) }
end

local function ApplyOverlay(record, entry)
	record.changed = record.changed or {}
	local function Set(field, value)
		if type(value) == "nil" then return end
		if record[field] ~= value then record.changed[field] = true end
		record[field] = value
	end
	Set("title", Text(entry.title))
	Set("level", Number(entry.level))
	Set("minLevel", Number(entry.minLevel))
	Set("map", Number(entry.map))
	Set("header", Text(entry.header))
	Set("instance", Text(entry.instance))
	Set("suggested", Number(entry.group))
	Set("nextInChain", Number(entry.next))
	if entry.side == "Alliance" then
		Set("raceMask", ALLIANCE)
	elseif entry.side == "Horde" then
		Set("raceMask", HORDE)
	elseif entry.side == "both" then
		Set("raceMask", 0)
	end
	if type(entry.classes) == "table" then
		local mask = 0
		for _, class in ipairs(entry.classes) do mask = mask + (CLASS_BITS[class] or 0) end
		Set("classMask", mask)
	end
	if type(entry.prev) == "table" then
		local list = {}
		for _, id in ipairs(entry.prev) do list[#list + 1] = Number(id) end
		record.allOf, record.anyOf, record.changed.allOf = list, {}, true
	end
	if type(entry.giver) == "table" then
		record.giver, record.changed.giver = Place(entry.giver), true
		if record.giver.npc then record.starts = { { kind = "npc", id = record.giver.npc } } end
		record.giverUnknown = nil
	elseif entry.giverUnknown then
		record.giverUnknown = true
	end
	if type(entry.ender) == "table" then
		record.ender, record.changed.ender = Place(entry.ender), true
		if record.ender.npc then record.ends = { { kind = "npc", id = record.ender.npc } } end
	end
	record.overlaySource = Text(entry.source)
	record.note = Text(entry.note)
	if entry.confirmed == false then record.confirmed = false end
	if entry.status == "removed" then record.removed = true end
end

local function ApplySeen(record, row)
	record.seen = true
	record.seenAt = Number(row.t)
	local function Fill(field, value)
		if type(value) == "nil" then return end
		if type(record[field]) ~= "nil" and record[field] ~= value then
			record.changed = record.changed or {}
			record.changed[field] = true
		end
		record[field] = value
	end
	Fill("title", Text(row.title))
	Fill("level", Number(row.level))
	Fill("minLevel", Number(row.minLevel))
	Fill("header", Text(row.header))
	local giver = Number(row.giver)
	local map, x, y = Number(row.map), Number(row.x), Number(row.y)
	if giver or map then
		local old = record.giver or {}
		record.giver = { npc = giver or old.npc, name = Text(row.giverName) or old.name, map = map or old.map,
			x = map and x or old.x, y = map and y or old.y }
		if giver then record.starts = { { kind = "npc", id = giver } } end
		record.giverUnknown = nil
		if map and type(record.map) == "nil" then record.map = map end
	end
	local ender = Number(row.ender)
	if ender then
		record.ender = { npc = ender, name = Text(row.enderName) }
		record.ends = { { kind = "npc", id = ender } }
	end
	record.seenXP, record.seenMoney = Number(row.xp), Number(row.money)
	-- You saw it in the game, so it is there.
	record.removed, record.confirmed = nil, true
end

local function BuildJourney(questID)
	local record = FromLootData(questID)
	local provenance = record and "classic" or nil
	local overlay = Overlay()
	local entry = overlay and type(overlay.quests) == "table" and overlay.quests[questID]
	if type(entry) == "table" then
		if not record then
			-- A "changed" or "removed" entry while EldoUI_LootData is not
			-- loaded still says what it knows.
			record = { id = questID }
			provenance = entry.status == "new" and "forever" or "classic"
		end
		ApplyOverlay(record, entry)
		if entry.status == "new" then provenance = "forever" end
	end
	local row = SeenQuest(questID)
	if row then
		if not record then
			record = { id = questID }
			provenance = "seen"
		end
		ApplySeen(record, row)
	end
	if not record then return false end
	record.id = questID
	record.provenance = provenance
	record.allOf, record.anyOf = record.allOf or {}, record.anyOf or {}
	record.starts, record.ends = record.starts or {}, record.ends or {}
	record.changed = record.changed or {}
	if record.confirmed ~= false then record.confirmed = true end
	record.title = record.title or LG:DataName("quest", questID, nil)
	return record
end

function LG:JourneyQuest(questID)
	questID = Number(questID)
	if not questID then return nil end
	local value = journeyCache[questID]
	if type(value) == "nil" then
		value = BuildJourney(questID)
		journeyCache[questID] = value
	end
	return value or nil
end

function LG:IsQuestRemoved(questID)
	local record = self:JourneyQuest(questID)
	return record and record.removed and true or false
end

-- Every quest id the three layers know, with its level from the packed
-- record (string matches only, no full decode), built once per change.
local function Index()
	if journeyIndex then return journeyIndex end
	local rows = {}
	local LD = Data()
	for _, field in ipairs({ "quests", "journey" }) do
		local tbl = LD and type(LD[field]) == "table" and LD[field]
		if tbl then
			for questID, packed in pairs(tbl) do
				if type(questID) == "number" and type(packed) == "string" and not rows[questID] then
					local level = packed:match("^[^|]*|(%-?%d*)")
					rows[questID] = { id = questID, level = tonumber(level) }
				end
			end
		end
	end
	-- The overlay and what you saw can change the level: no quick level test.
	local overlay = Overlay()
	for questID in pairs(overlay and type(overlay.quests) == "table" and overlay.quests or {}) do
		if type(questID) == "number" then rows[questID] = { id = questID } end
	end
	local seen = Seen()
	for questID in pairs(seen and type(seen.quests) == "table" and seen.quests or {}) do
		if type(questID) == "number" then rows[questID] = { id = questID } end
	end
	local out = {}
	for _, row in pairs(rows) do out[#out + 1] = row end
	table.sort(out, function(a, b) return a.id < b.id end)
	journeyIndex = out
	return out
end

-- How many levels below yours a quest still gives XP: the game's own number
-- (UnitQuestTrivialLevelRange), else Classic's gray rule.
local function GreenRange(level)
	if UnitQuestTrivialLevelRange then
		local ok, range = pcall(UnitQuestTrivialLevelRange, "player")
		if ok and not Secret(range) and type(range) == "number" and range ~= 0 then return math.abs(range) end
	end
	if level <= 5 then return 5 end
	if level <= 39 then return math.floor(level / 10) + 5 end
	if level <= 59 then return math.floor(level / 5) + 1 end
	return 9
end

-- How a quest of questLevel looks to you: red (far above), orange, yellow
-- (about your level), green (still worth XP) or gray (trivial).
function LG:QuestFit(questLevel, playerLevel)
	questLevel = Number(questLevel)
	playerLevel = Number(playerLevel) or self:Player().level or 1
	if not questLevel or questLevel <= 0 then return "yellow" end
	local diff = questLevel - playerLevel
	if diff >= 5 then return "red" end
	if diff >= 3 then return "orange" end
	if diff >= -2 then return "yellow" end
	if -diff <= GreenRange(playerLevel) then return "green" end
	return "gray"
end

local FIT_RANK = { yellow = 1, orange = 2, green = 3, red = 4, gray = 5 }
LG.QUEST_FIT_RANK = FIT_RANK

local function SimpleStatus(quest, level)
	local id = quest.id
	if LG:QuestDone(id) then return "done" end
	if LG:OnQuest(id) then
		if Log("ReadyForTurnIn", id) or Log("IsComplete", id) then return "turnin" end
		return "active"
	end
	for _, prev in ipairs(quest.allOf) do
		if prev > 0 and not LG:QuestDone(prev) then return "locked", prev end
	end
	if quest.minLevel and quest.minLevel > level then return "low", quest.minLevel end
	return "available"
end

-- Quests that fit a character: the where-next engine's and Today's input.
-- opts (all optional): level (default yours), faction ("mine", "Alliance",
-- "Horde" or "all"), raceMask and classMask (default yours; 0 = any),
-- below and above (levels under and over the level; default the green range
-- and 4), fits ({ yellow = true, ... }: only these), done (keep completed
-- quests), unconfirmed (keep overlay entries nobody confirmed), repeatable
-- (keep repeatable quests), limit.
-- Returns { { id, level, fit, status, detail, quest }, ... }: best fit
-- first, then the level closest to yours, then id. Removed quests and quests
-- for another side, race or class never come back.
function LG:JourneyQuests(opts)
	opts = opts or {}
	local player = self:Player()
	local level = Number(opts.level) or player.level or 1
	local below = Number(opts.below) or GreenRange(level)
	local above = Number(opts.above) or 4
	local own = not (opts.level or opts.raceMask or opts.classMask)
	local raceMask = Number(opts.raceMask) or player.raceMask or 0
	local classMask = Number(opts.classMask) or player.classMask or 0
	local faction = opts.faction or "mine"
	if faction == "mine" then faction = player.faction end
	local sideMask = (faction == "Alliance" and ALLIANCE) or (faction == "Horde" and HORDE) or nil
	local low, high = level - below, level + above
	local out = {}
	for _, row in ipairs(Index()) do
		if not row.level or row.level <= 0 or (row.level >= low and row.level <= high) then
			local quest = self:JourneyQuest(row.id)
			local qLevel = quest and quest.level
			local keep = quest and not quest.removed
				and (opts.unconfirmed or quest.confirmed ~= false)
				and (opts.repeatable or not quest.repeatable)
				and (not qLevel or qLevel <= 0 or (qLevel >= low and qLevel <= high))
				and (not quest.minLevel or quest.minLevel <= high)
			local rMask, cMask = quest and quest.raceMask, quest and quest.classMask
			if keep and rMask and rMask > 0 then
				if raceMask > 0 and bit.band(rMask, raceMask) == 0 then keep = false end
				if sideMask and bit.band(rMask, sideMask) == 0 then keep = false end
			end
			if keep and cMask and cMask > 0 and classMask > 0 and bit.band(cMask, classMask) == 0 then keep = false end
			if keep and not opts.done and self:QuestDone(row.id) then keep = false end
			if keep then
				local fit = self:QuestFit((qLevel and qLevel > 0) and qLevel or level, level)
				if not opts.fits or opts.fits[fit] then
					local status, detail
					if quest.full and own then
						status, detail = self:QuestStatus(row.id)
					else
						status, detail = SimpleStatus(quest, level)
					end
					if status ~= "notforyou" then
						out[#out + 1] = { id = row.id, level = qLevel, fit = fit, status = status, detail = detail, quest = quest }
					end
				end
			end
		end
	end
	table.sort(out, function(a, b)
		if a.fit ~= b.fit then return FIT_RANK[a.fit] < FIT_RANK[b.fit] end
		local da, dbl = math.abs((a.level or level) - level), math.abs((b.level or level) - level)
		if da ~= dbl then return da < dbl end
		return a.id < b.id
	end)
	local limit = Number(opts.limit)
	if limit then
		for index = #out, limit + 1, -1 do out[index] = nil end
	end
	return out
end

-- { journey = { version, commit, build, count } or nil, overlay = { version,
-- entries, new, changed, removed } or nil, seen = n }
function LG:JourneyDataStatus()
	local LD = Data()
	local out = { seen = 0 }
	if LD then
		local counts = type(LD.counts) == "table" and LD.counts or {}
		out.journey = { version = tostring(LD.version or "?"), commit = tostring(LD.commit or ""), build = tostring(LD.build or "?"),
			count = (tonumber(counts.quests) or 0) + (tonumber(counts.journey) or 0) }
	end
	local overlay = Overlay()
	if overlay then
		local counts = type(overlay.counts) == "table" and overlay.counts or {}
		out.overlay = { version = tostring(overlay.version or "?"), entries = tonumber(overlay.entries) or 0,
			new = tonumber(counts.new) or 0, changed = tonumber(counts.changed) or 0, removed = tonumber(counts.removed) or 0 }
	end
	local seen = Seen()
	for _, field in ipairs({ "quests", "instances", "zones" }) do
		for _ in pairs(seen and type(seen[field]) == "table" and seen[field] or {}) do out.seen = out.seen + 1 end
	end
	return out
end

-- "Journey data 1.5.0-ec4f596 (classic-db 2026-09-22) · Forever overlay
-- 2026-10-12, 41 entries · 12 seen by you"
function LG:JourneyDataText()
	local status = self:JourneyDataStatus()
	local parts = {}
	if status.journey then
		parts[#parts + 1] = L["Journey data %s (classic-db %s)"]:format(status.journey.version .. "-" .. status.journey.commit:sub(1, 7),
			status.journey.build)
	else
		parts[#parts + 1] = L["Journey data: %s"]:format(self:DataStatusText(true))
	end
	if status.overlay then
		parts[#parts + 1] = E:Plural(status.overlay.entries, "Forever overlay %s, %d entry", "Forever overlay %s, %d entries")
			:format(status.overlay.version, status.overlay.entries)
	end
	parts[#parts + 1] = L["%d seen by you"]:format(status.seen)
	return table.concat(parts, " · ")
end

---------------------------------------------------------------------------
-- "Report new content": the !EUJD1! block (share kind "journaldata"). It
-- holds only what the game showed you (the seen store), your faction and
-- the versions, never your character's name. A report sent this way
-- adds the new content to the guide's data in a later version.
---------------------------------------------------------------------------
LG.JOURNAL_DATA_PREFIX = "!EUJD1!"
LG.JOURNAL_DATA_ISSUE_URL = "https://github.com/Eldodeldo/EldoUI/issues/new?template=journal-data.yml"

local function Copy(row, fields)
	local out, any = {}, false
	for _, field in ipairs(fields) do
		local value = row[field]
		if not Secret(value) and (type(value) == "number" or type(value) == "string" or type(value) == "boolean") then
			out[field] = value
			any = true
		end
	end
	return any and out or nil
end

local function ReportTable(source, fields)
	local out, count = {}, 0
	for id, row in pairs(type(source) == "table" and source or {}) do
		if type(id) == "number" and type(row) == "table" then
			local copy = Copy(row, fields)
			if copy then
				out[id] = copy
				count = count + 1
			end
		end
	end
	return out, count
end

-- The report table, or nil while you have seen nothing the data lacks.
function LG:JourneyReportData()
	local seen = Seen() or {}
	local quests, nq = ReportTable(seen.quests, SEEN_QUEST_FIELDS)
	local instances, ni = ReportTable(seen.instances, SEEN_INSTANCE_FIELDS)
	local zones, nz = ReportTable(seen.zones, SEEN_ZONE_FIELDS)
	if nq + ni + nz == 0 then return nil end
	local version, build, interface
	if GetBuildInfo then
		local _
		version, build, _, interface = GetBuildInfo()
	end
	local status = self:JourneyDataStatus()
	return {
		v = 1,
		game = { version = Text(version), build = Text(build), interface = Number(interface) },
		eldoui = tostring(E.version or "dev"),
		journey = status.journey and (status.journey.version .. "-" .. status.journey.commit:sub(1, 7)) or nil,
		overlay = status.overlay and status.overlay.version or nil,
		faction = Text(self:Player().faction),
		-- intake.py takes titles and names only from English clients.
		locale = GetLocale and Text(GetLocale()) or nil,
		quests = quests, instances = instances, zones = zones,
	}
end

-- The block, or nil and the reason.
function LG:JourneyReport()
	local data = self:JourneyReportData()
	if not data then
		return nil, L["Nothing new to report yet. The Journal notes the quests, dungeons, and zones the data does not know as you meet them."]
	end
	return E:EncodeShareData("journaldata", data)
end

-- The copy box with the block and where to paste it.
function LG:ShowJourneyReport()
	local text, err = self:JourneyReport()
	if not text then
		E:Print(err)
		return false
	end
	E:ShowCopyBox(L["Report new content"],
		L["Copy this block into a new journal-data issue: %s. Nothing is sent from the game."]:format(LG.JOURNAL_DATA_ISSUE_URL), text)
	return true
end

local function CountOf(tbl)
	local n = 0
	for _ in pairs(type(tbl) == "table" and tbl or {}) do n = n + 1 end
	return n
end

if E.RegisterShareKind then
	E:RegisterShareKind("journaldata", {
		prefix = LG.JOURNAL_DATA_PREFIX,
		title = "Journal data report",
		version = 1,
		build = function() return LG:JourneyReportData() end,
		describe = function(data)
			local quests, instances, zones = CountOf(data.quests), CountOf(data.instances), CountOf(data.zones)
			return {
				E:Plural(quests, "%d quest", "%d quests"):format(quests),
				E:Plural(instances, "%d dungeon or raid", "%d dungeons and raids"):format(instances),
				E:Plural(zones, "%d zone", "%d zones"):format(zones),
				L["Paste it into a journal-data issue. It changes nothing in your game."],
			}
		end,
	})
end

---------------------------------------------------------------------------
-- After a WoW: Forever patch: does the game still know the data's quests,
-- and do its zone ranges match ours? (the forever-patch checklist,
-- docs/CROSS-REPO.md). Read-only questions to the game:
--   LG:JourneyCheck(opts, onDone)   asks C_QuestLog.RequestLoadQuestByID for
--       each data quest, a few per second and never in combat, and collects
--       the ids the game answers "no such quest" for (QUEST_DATA_LOAD_RESULT
--       success false). opts: from, to (quest levels, default all), rate
--       (asks per second, default 4, at most 10). onDone(result) with result
--       = { checked, missing = { ids }, unanswered = { ids } }.
--   LG:JourneyCheckRunning()        progress: asked, total (nil when idle)
--   LG:JourneyStopCheck()
--   LG:JourneyZoneCheck()           { { map, name, ours = { min, max }, game = { min, max } }, ... }
--       where C_Map.GetMapLevels differs from Data/Zones.lua
--   LG:JourneyCheckText(result, zones)  the lines to paste into the patch issue
-- Nothing is accepted or changed; a quest the game does not know goes into
-- a "Quest gone" journal-data issue, where a person decides.
---------------------------------------------------------------------------
local CHECK_TIMEOUT = 10   -- seconds without an answer before an id counts as unanswered
local check                -- the running check

local function FinishCheck()
	local running = check
	if not running then return end
	check = nil
	local unanswered = {}
	for id in pairs(running.waiting) do unanswered[#unanswered + 1] = id end
	for id in pairs(running.timedOut) do unanswered[#unanswered + 1] = id end
	table.sort(unanswered)
	table.sort(running.missing)
	local result = { checked = running.answered, missing = running.missing, unanswered = unanswered }
	LG.lastJourneyCheck = result
	if running.onDone then
		local ok, err = pcall(running.onDone, result)
		if not ok then geterrorhandler()(err) end
	end
	LG:Fire("journeyCheck")
end

local function CheckStep()
	local running = check
	if not running then return end
	if InCombatLockdown() then
		C_Timer.After(1, CheckStep)
		return
	end
	local now = GetTime()
	for id, asked in pairs(running.waiting) do
		if now - asked > CHECK_TIMEOUT then
			running.waiting[id] = nil
			running.timedOut[id] = true
		end
	end
	for _ = 1, running.rate do
		local id = running.queue[running.next]
		if not id then break end
		running.next = running.next + 1
		running.waiting[id] = now
		local ok = pcall(C_QuestLog.RequestLoadQuestByID, id)
		if not ok then running.waiting[id] = nil end
	end
	if running.next > #running.queue and not next(running.waiting) then
		FinishCheck()
		return
	end
	C_Timer.After(1, CheckStep)
end

LG:Listen("QUEST_DATA_LOAD_RESULT", "journey-check", function(_, questID, success)
	local running = check
	if not running or Secret(questID) or Secret(success) then return end
	if not (running.waiting[questID] or running.timedOut[questID]) then return end
	running.waiting[questID], running.timedOut[questID] = nil, nil
	running.answered = running.answered + 1
	if success == false then running.missing[#running.missing + 1] = questID end
end)

function LG:JourneyCheck(opts, onDone)
	if check then return false, L["A check is already running."] end
	if not (C_QuestLog and C_QuestLog.RequestLoadQuestByID) then return false, L["This game client cannot answer quest questions."] end
	if not self:HasData() then return false, self:DataStatusText() end
	opts = opts or {}
	local from, to = Number(opts.from), Number(opts.to)
	local queue = {}
	local LD = Data()
	for _, field in ipairs({ "quests", "journey" }) do
		for questID, packed in pairs(LD and type(LD[field]) == "table" and LD[field] or {}) do
			local level = type(packed) == "string" and tonumber(packed:match("^[^|]*|(%-?%d*)"))
			if type(questID) == "number" and (not from or (level and level >= from)) and (not to or (level and level <= to)) then
				queue[#queue + 1] = questID
			end
		end
	end
	table.sort(queue)
	local rate = math.max(1, math.min(10, Number(opts.rate) or 4))
	check = { queue = queue, next = 1, rate = rate, waiting = {}, timedOut = {}, missing = {}, answered = 0,
		onDone = onDone }
	C_Timer.After(0, CheckStep)
	return true, #queue
end

function LG:JourneyCheckRunning()
	if not check then return nil end
	return check.next - 1, #check.queue
end

function LG:JourneyStopCheck()
	if check then FinishCheck() end
end

function LG:JourneyZoneCheck()
	local out = {}
	local zones = E.zoneData and E.zoneData.zones
	if type(zones) ~= "table" or not (C_Map and C_Map.GetMapLevels) then return out end
	for map, zone in pairs(zones) do
		if type(zone) == "table" and zone.min and zone.max then
			local ok, low, high = pcall(C_Map.GetMapLevels, map)
			if ok and not Secret(low) and not Secret(high) and type(low) == "number" and type(high) == "number" and low > 0
				and (low ~= zone.min or high ~= zone.max) then
				local info = C_Map.GetMapInfo and C_Map.GetMapInfo(map)
				out[#out + 1] = { map = map, name = type(info) == "table" and Text(info.name) or nil,
					ours = { min = zone.min, max = zone.max }, game = { min = low, max = high } }
			end
		end
	end
	table.sort(out, function(a, b) return a.map < b.map end)
	return out
end

local function IdLine(list)
	local parts = {}
	for index, id in ipairs(list) do
		if index > 200 then
			parts[#parts + 1] = "..."
			break
		end
		parts[#parts + 1] = tostring(id)
	end
	return table.concat(parts, ", ")
end

-- Plain lines (English, for a GitHub issue).
function LG:JourneyCheckText(result, zones)
	local lines = { "Journal data check, " .. self:JourneyDataText() }
	local version, build
	if GetBuildInfo then version, build = GetBuildInfo() end
	if Text(version) then lines[#lines + 1] = ("Client %s %s"):format(version, Text(build) or "") end
	if result then
		lines[#lines + 1] = ("Quests checked: %d. The game does not know %d: %s"):format(result.checked, #result.missing,
			#result.missing > 0 and IdLine(result.missing) or "none")
		if #result.unanswered > 0 then
			lines[#lines + 1] = ("No answer for %d: %s"):format(#result.unanswered, IdLine(result.unanswered))
		end
	end
	zones = zones or self:JourneyZoneCheck()
	if #zones == 0 then
		lines[#lines + 1] = "Zone levels: all match Data/Zones.lua."
	else
		for _, zone in ipairs(zones) do
			lines[#lines + 1] = ("Zone %d %s: ours %d-%d, the game %d-%d"):format(zone.map, zone.name or "", zone.ours.min, zone.ours.max,
				zone.game.min, zone.game.max)
		end
	end
	return table.concat(lines, "\n")
end
