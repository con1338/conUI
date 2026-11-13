-- EldoUI Attunements: attunements, keys and quest chains as a tab in the
-- Loot Guide's Journal.
--
-- Where the chains come from: EldoUI_LootData (GPL, generated from CMaNGOS
-- classic-db: every quest a goal needs, with its prerequisites) plus our
-- own Defs.lua. Where progress comes from: the game only. The quest log
-- (C_QuestLog: completed, in the log, ready to turn in, objectives), your
-- bags and bank (C_Item.GetItemCount), reputation (C_Reputation), your
-- level, and BOSS_KILL or the saved-instance list for a boss that drops a
-- key. The combat log is never read and nothing is guessed: a step the
-- game cannot report is "not tracked" until a later step is done.
-- Nothing here accepts, turns in or skips a quest, and nothing is sent to
-- other players without a click (Guild.lua).
--
-- Read API (other pages and plugins; also EldoUI.Attunements):
--   A:List(opts)                    entry keys for the current filters
--                                   (opts.all: every entry, opts.group)
--   A:Get(key)                      { key, kind, group, side, instance, minLevel,
--                                     maxLevel, name, desc, forever, ... }
--   A:Steps(key)                    the step graph: { list, byId, sideList }
--   A:Progress(key[, charKey])      done, total, percent, state
--   A:StepState(key, stepId[, charKey])
--   A:NextSteps(key[, charKey])     steps you can do now (or are on), in order
--   A:StepPlace(step)               { uiMapID, x, y, instance, kind, id, name } or nil
--   A:StepTitle(step), A:StepCaption(step[, charKey])
--   A:ForQuest(questID), A:ForItem(itemID), A:ForNpc(npcID)
--                                   { { key, step, index, total }, ... }
--   A:ForInstance(instanceKey)      entry keys of raids, keys and chains for it
--   A:Unwritten(key)                a Forever entry with no chain written yet
--   A:Summary([charKey])            { { key, name, done, total, percent, state, next }, ... }
--   A:InProgressCount()             the number on the tab and the data text
-- Changes reach the Loot Guide bus as LG:Fire("attune").
--
-- Where the page lives: while My Adventure runs it is the section
-- "attune" in the Atlas group of the hub (LG:RegisterHubSection), and
-- LG:Open("attune", arg) opens the hub there; otherwise it is its own tab
-- (order 25). A:PlaceHome() moves it when either module starts or stops.
local _, E = ...
local L = E.L
local LG = E.LootGuide

local A = E:NewModule("Attunements", {
	title = "Attunements",
	desc = "Attunements, keys and dungeon quest chains as a tab in the Loot Guide: every step, what you have done, what comes next, and which of your characters are ready.",
	category = LG and LG.category,
	conflicts = { "Attune" },
	frames = {},
	movers = {},
	blizzard = {},
	savedKeys = { "profile.modules.Attunements", "EldoUIDB.attuneSeen", "EldoUIDB.attunePeers" },
	optionsPage = "module:Attunements",
	presets = { "EldoUI", "Explorer", "Leveller", "Quiet", "Raider", "Steps" },
	reload = false,
	defaults = {
		style = "EldoUI",
		view = "chain",          -- chain (flowchart) or list (one step per row)
		overview = "mine",       -- mine (My characters) or guild
		showFaction = "mine",    -- mine, Alliance, Horde, all
		hideDone = false,
		showExpansions = "forever", -- forever (instances the game has) or all
		classQuests = "mine",    -- mine or all
		alerts = true,
		alertSound = "eldo:Tada",
		guildButton = true,
		mapPins = false,
		instanceLine = true,
		guildShare = false,
		guildAnswer = "ask",     -- ask or never; nothing answers by itself
		guildKeepDays = 60,
		guildMaxNames = 10,
		record = true,
	},
})
E.Attunements = A

local Secret = E.Secret
A.Secret = Secret

-- A value the game gave, or nil when it is secret.
local Plain = E.Plain
A.Plain = Plain

local function Data()
	return select(3, LG:DataStatus())
end
A.Data = Data

-- Reputation thresholds (quest_template values) -> standing (reaction 1-8).
local REP_STANDING = { { 42000, 8 }, { 21000, 7 }, { 9000, 6 }, { 3000, 5 }, { 0, 4 } }
local function StandingForValue(value)
	for _, pair in ipairs(REP_STANDING) do
		if (value or 0) >= pair[1] then return pair[2] end
	end
	return 4
end

-- Kinds of step that count toward progress.
local COUNTS = { level = true, pickup = true, quest = true, turnin = true, item = true, kill = true, interact = true,
	rep = true, goal = true, drop = true }
A.COUNTS = COUNTS
-- The groups whose steps make toasts (not dungeon quest lists).
local ALERT_GROUPS = { raids = true, keys = true, misc = true, class = true, forever = true }

---------------------------------------------------------------------------
-- Entries
---------------------------------------------------------------------------
local entries, byKey = {}, {}
local lookup = { quest = {}, item = {}, npc = {}, faction = {}, linkedBy = {} }
local built = false

local function AddIndex(list, id, key, step)
	if not id then return end
	list[id] = list[id] or {}
	table.insert(list[id], { key = key, step = step })
end

---------------------------------------------------------------------------
-- Steps: from each quest record a pickup, its items, targets and a turn-in
-- (or one quest node), a level root, reputation, links, goal items and the
-- end. Layers are the longest path from a root.
---------------------------------------------------------------------------
local function BuildSteps(entry)
	local graph = { list = {}, byId = {}, sideList = {} }
	local function Add(step)
		if graph.byId[step.id] then return graph.byId[step.id] end
		step.follows = step.follows or {}
		graph.byId[step.id] = step
		if step.side then
			graph.sideList[#graph.sideList + 1] = step
		else
			graph.list[#graph.list + 1] = step
		end
		return step
	end
	local inSet = {}
	for _, q in ipairs(entry.quests or {}) do inSet[q] = true end
	-- Dungeon quest pages: the instance's quests and every quest they need.
	if entry.closure then
		local todo = {}
		for _, q in ipairs(entry.quests) do todo[#todo + 1] = q end
		while #todo > 0 do
			local quest = LG:Quest(table.remove(todo))
			if quest then
				for _, list in ipairs({ quest.allOf, quest.anyOf }) do
					for _, prev in ipairs(list) do
						if prev > 0 and not inSet[prev] and LG:Quest(prev) then
							inSet[prev] = true
							todo[#todo + 1] = prev
						end
					end
				end
			end
		end
		local ids = {}
		for q in pairs(inSet) do ids[#ids + 1] = q end
		table.sort(ids, function(a, b)
			local qa, qb = LG:Quest(a), LG:Quest(b)
			local la, lb = qa and qa.level or 0, qb and qb.level or 0
			if la ~= lb then return la < lb end
			return a < b
		end)
		entry.quests = ids
	end
	local roots = {}
	local level = entry.minLevel
	if not level then
		for _, q in ipairs(entry.quests or {}) do
			local quest = LG:Quest(q)
			if quest and quest.minLevel and quest.minLevel > 0 then level = math.min(level or 99, quest.minLevel) end
		end
	end
	if level and level > 1 then
		Add({ id = "lvl", kind = "level", ref = level })
		roots[#roots + 1] = "lvl"
	end
	if entry.rep then
		Add({ id = "rep", kind = "rep", ref = entry.rep.faction, standing = entry.rep.standing })
		roots[#roots + 1] = "rep"
	end
	for _, link in ipairs(entry.links or {}) do
		Add({ id = "link:" .. link, kind = "link", ref = link })
		roots[#roots + 1] = "link:" .. link
	end
	local endOf = {}
	local function Ends(list)
		local out = {}
		for _, q in ipairs(list) do
			if endOf[q] then out[#out + 1] = endOf[q] end
		end
		return out
	end
	-- Quests are listed in stage order, so a quest's prerequisites come first.
	for _, q in ipairs(entry.quests or {}) do
		local quest = LG:Quest(q)
		if quest then
			local all, any = {}, {}
			for _, prev in ipairs(quest.allOf) do if inSet[prev] then all[#all + 1] = prev end end
			for _, prev in ipairs(quest.anyOf) do if inSet[prev] then any[#any + 1] = prev end end
			if quest.activeQuest and inSet[quest.activeQuest] then all[#all + 1] = quest.activeQuest end
			if #any == 1 then
				all[#all + 1] = any[1]
				any = {}
			end
			local follows, anyJoin
			if #any > 0 and #all == 0 then
				follows, anyJoin = Ends(any), true
			else
				follows = Ends(all)
				-- all-of plus an any-of group: the any-of part is one node's worth
				-- here (the first branch), the rest show as side branches.
				if #any > 0 then follows[#follows + 1] = Ends(any)[1] end
			end
			if #follows == 0 then
				for _, root in ipairs(roots) do follows[#follows + 1] = root end
				anyJoin = false
			end
			local faction = LG:QuestSide(q)
			-- A reputation the quest asks for, unless the entry already has it.
			if quest.minRep and not (entry.rep and entry.rep.faction == quest.minRep.faction) then
				local rep = Add({ id = "r" .. q, kind = "rep", ref = quest.minRep.faction, standing = StandingForValue(quest.minRep.value),
					follows = follows, any = anyJoin, faction = faction })
				follows, anyJoin = { rep.id }, false
			end
			local subs = {}
			for _, item in ipairs(quest.reqItems) do subs[#subs + 1] = { kind = "item", ref = item.id, count = item.count } end
			local npcIndex, objectIndex = 0, 0
			for _, target in ipairs(quest.reqTargets) do
				if target.kind == "npc" then
					npcIndex = npcIndex + 1
					subs[#subs + 1] = { kind = "kill", ref = target.id, count = target.count, objective = npcIndex }
				else
					objectIndex = objectIndex + 1
					subs[#subs + 1] = { kind = "interact", ref = target.id, count = target.count, objective = objectIndex }
				end
			end
			if #subs > 0 then
				local pickup = Add({ id = "p" .. q, kind = "pickup", ref = q, quest = q, follows = follows, any = anyJoin, faction = faction })
				local into = {}
				for itemIndex, sub in ipairs(subs) do
					sub.id = ("%s%d:%d"):format(sub.kind == "item" and "i" or sub.kind == "kill" and "k" or "o", q, sub.ref)
					sub.quest, sub.follows, sub.faction, sub.slot = q, { pickup.id }, faction, itemIndex
					Add(sub)
					into[#into + 1] = sub.id
				end
				Add({ id = "t" .. q, kind = "turnin", ref = q, quest = q, follows = into, faction = faction })
				endOf[q] = "t" .. q
			else
				Add({ id = "q" .. q, kind = "quest", ref = q, quest = q, follows = follows, any = anyJoin, faction = faction })
				endOf[q] = "q" .. q
			end
		end
	end
	-- Hand-written Forever chains: quest nodes in the given order.
	for _, hand in ipairs(entry.hand or {}) do
		local follows = {}
		for _, prev in ipairs(hand.follows) do follows[#follows + 1] = "q" .. prev end
		if #follows == 0 then for _, root in ipairs(roots) do follows[#follows + 1] = root end end
		Add({ id = "q" .. hand.q, kind = "quest", ref = hand.q, quest = hand.q, follows = follows })
		endOf[hand.q] = "q" .. hand.q
	end
	-- Goal items: after the quest that rewards them, a boss that drops them,
	-- or the goal quests.
	local goalEnds = {}
	for _, item in ipairs(entry.goalItems or {}) do
		local after
		for _, q in ipairs(entry.quests or {}) do
			local quest = LG:Quest(q)
			for _, list in ipairs(quest and { quest.rewards, quest.choice } or {}) do
				for _, reward in ipairs(list) do
					if reward.id == item and endOf[q] then after = after or endOf[q] end
				end
			end
		end
		local follows = after and { after } or nil
		if not follows and entry.drop then
			local best
			for _, source in ipairs(LG:ItemSources(item) or {}) do
				if source.kind == "npc" and (not best or (source.chance or 0) > (best.chance or 0)) then best = source end
			end
			if best then
				local drop = Add({ id = "d" .. best.id, kind = "drop", ref = best.id, item = item, follows = CopyTable(roots) })
				follows = { drop.id }
			end
		end
		if not follows then
			follows = Ends(entry.goalQuests or {})
			if #follows == 0 then follows = CopyTable(roots) end
		end
		local goal = Add({ id = "g" .. item, kind = "goal", ref = item, count = 1, follows = follows })
		goalEnds[#goalEnds + 1] = goal.id
	end
	-- The end: every goal quest (or one of them), the goal items, and the
	-- door's flag quest; dungeon and class pages end when every quest that
	-- nothing else follows is done.
	local endFollows, endAny = {}, entry.any and true or false
	for _, id in ipairs(Ends(entry.goalQuests or {})) do endFollows[#endFollows + 1] = id end
	if endAny and #endFollows > 1 and #goalEnds > 0 then endAny = false end
	for _, id in ipairs(goalEnds) do endFollows[#endFollows + 1] = id end
	if #endFollows == 0 then
		local followed = {}
		for _, step in ipairs(graph.list) do
			for _, f in ipairs(step.follows) do followed[f] = true end
		end
		for _, step in ipairs(graph.list) do
			if not followed[step.id] and step.quest then endFollows[#endFollows + 1] = step.id end
		end
	end
	if #graph.list > #roots or #endFollows > 0 then
		Add({ id = "end", kind = "end", ref = entry.key, follows = endFollows, any = endAny, flag = entry.flag })
	end
	-- Inside the dungeon: the instance's other quests (side box, not counted).
	if entry.instance and (entry.kind == "raid" or entry.kind == "key") then
		local count = 0
		for _, q in ipairs(LG:InstanceQuestIDs(entry.instance)) do
			if not inSet[q] and count < 8 and LG:Quest(q) then
				count = count + 1
				Add({ id = "s" .. q, kind = "quest", ref = q, quest = q, side = true, faction = LG:QuestSide(q) })
			end
		end
	end
	-- Layers: the longest path from a root.
	local depth = {}
	local function Depth(step, guard)
		if depth[step.id] then return depth[step.id] end
		if guard > 200 then return 1 end
		local best = 0
		for _, f in ipairs(step.follows) do
			local up = graph.byId[f]
			if up then best = math.max(best, Depth(up, guard + 1)) end
		end
		depth[step.id] = best + 1
		return best + 1
	end
	for _, step in ipairs(graph.list) do step.layer = Depth(step, 0) end
	for _, step in ipairs(graph.sideList) do step.layer = 1 end
	-- Stable order: layer, then the order the steps were added.
	for position, step in ipairs(graph.list) do step.position = position end
	table.sort(graph.list, function(a, b)
		if a.layer ~= b.layer then return a.layer < b.layer end
		return a.position < b.position
	end)
	for position, step in ipairs(graph.list) do step.index = position end
	-- Who follows whom (for back-fill and the chart).
	for _, step in ipairs(graph.list) do step.next = {} end
	for _, step in ipairs(graph.list) do
		for _, f in ipairs(step.follows) do
			local up = graph.byId[f]
			if up and up.next then up.next[#up.next + 1] = step.id end
		end
	end
	return graph
end

local function IndexEntry(entry)
	local key = entry.key
	for _, step in ipairs(entry.steps.list) do
		if step.quest then AddIndex(lookup.quest, step.quest, key, step.id) end
		if step.kind == "item" or step.kind == "goal" then AddIndex(lookup.item, step.ref, key, step.id) end
		if step.kind == "kill" or step.kind == "drop" then AddIndex(lookup.npc, step.ref, key, step.id) end
		if step.kind == "rep" then AddIndex(lookup.faction, step.ref, key, step.id) end
		if step.kind == "link" then AddIndex(lookup.linkedBy, step.ref, key, step.id) end
		if step.kind == "pickup" or step.kind == "quest" or step.kind == "turnin" then
			local quest = LG:Quest(step.quest)
			if quest then
				local places = step.kind == "turnin" and quest.ends or step.kind == "pickup" and quest.starts or quest.starts
				for _, place in ipairs(places) do
					if place.kind == "npc" then AddIndex(lookup.npc, place.id, key, step.id) end
				end
				if step.kind == "quest" then
					for _, place in ipairs(quest.ends) do
						if place.kind == "npc" then AddIndex(lookup.npc, place.id, key, step.id) end
					end
				end
			end
		end
	end
end

local function Build()
	built = true
	wipe(entries)
	wipe(byKey)
	for _, list in pairs(lookup) do wipe(list) end
	local list = A:CollectEntries(Data())
	for _, entry in ipairs(list) do
		entry.steps = BuildSteps(entry)
		byKey[entry.key] = entry
		entries[#entries + 1] = entry
		IndexEntry(entry)
	end
end

function A:EnsureBuilt()
	if not built then Build() end
end

-- Forget the entries (new data, new instance list); the next read rebuilds.
function A:Reset()
	built = false
	self:ClearProgress()
end

function A:Get(key)
	self:EnsureBuilt()
	return byKey[key]
end

function A:AllEntries()
	self:EnsureBuilt()
	return entries
end

function A:Steps(key)
	local entry = self:Get(key)
	return entry and entry.steps
end

function A:Name(entry)
	if type(entry) == "string" then entry = self:Get(entry) end
	if not entry then return "?" end
	if entry.fixedName then return E:Translate(entry.fixedName) end
	local kind = entry.kind
	if (kind == "raid" or kind == "dungeon") and entry.instance then
		return LG:InstanceName(entry.instance) or (LG:InstanceInfo(entry.instance) or {}).name or entry.key
	end
	if entry.spell and self.SpellName then
		local name = self:SpellName(entry)
		if name then return name end
	end
	if entry.goalItems and entry.goalItems[1] then
		local record = LG:ItemRecord(entry.goalItems[1])
		if record and record.name then return record.name end
	end
	local q = entry.goalQuests and entry.goalQuests[1]
	local title = q and LG:QuestTitle(q)
	if title then return title end
	-- A class quest whose spell and quest names are not known yet.
	if entry.kind == "class" then return L["Class quest"] end
	return entry.key
end

function A:Desc(entry)
	if type(entry) == "string" then entry = self:Get(entry) end
	if not entry then return nil end
	if entry.desc then return E:Translate(entry.desc) end
	if entry.kind == "class" and self.ClassChainLine then return self:ClassChainLine(entry.key) end
end

---------------------------------------------------------------------------
-- Readers: what one character has done. The live reader asks the game;
-- a record reader reads the Characters store (as of that character's
-- last login).
---------------------------------------------------------------------------
local function Call(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, value = pcall(fn, ...)
	if not ok then return nil end
	return Plain(value)
end

local killedNames = {}   -- boss names killed (BOSS_KILL this session, the lockout list)

local function LiveReader()
	local player = LG:Player()
	local reader = { key = E.charKey, live = true, faction = player.faction, level = player.level, cache = {} }
	local cache = reader.cache
	function reader:Done(q)
		local key = "d" .. q
		if cache[key] == nil then cache[key] = LG:QuestDone(q) end
		return cache[key]
	end
	function reader:OnQuest(q)
		local key = "o" .. q
		if cache[key] == nil then cache[key] = LG:OnQuest(q) end
		return cache[key]
	end
	function reader:Ready(q)
		local key = "r" .. q
		if cache[key] == nil then
			local log = C_QuestLog
			cache[key] = (Call(log and log.ReadyForTurnIn, q) or Call(log and log.IsComplete, q)) and true or false
		end
		return cache[key]
	end
	function reader:Count(item)
		local key = "c" .. item
		if cache[key] == nil then
			local count = C_Item and Call(C_Item.GetItemCount, item, true)
			cache[key] = tonumber(count) or 0
		end
		return cache[key]
	end
	function reader:Reaction(faction)
		local standing = LG:Standing(faction)
		return standing and standing + 1 or nil
	end
	function reader:RepValue(faction)
		local rep = C_Reputation
		if not (rep and rep.GetFactionDataByID) then return end
		local ok, data = pcall(rep.GetFactionDataByID, faction)
		if not ok or type(data) ~= "table" then return end
		local value, low, high = Plain(data.currentStanding), Plain(data.currentReactionThreshold), Plain(data.nextReactionThreshold)
		if type(value) == "number" and type(low) == "number" and type(high) == "number" then return value - low, high - low end
	end
	-- kind: "monster" / "object" / "item"; n: the n-th objective of that kind.
	function reader:Objective(q, kind, n)
		local key = "j" .. q
		if cache[key] == nil then
			cache[key] = false
			local log = C_QuestLog
			if log and log.GetQuestObjectives and self:OnQuest(q) then
				local ok, list = pcall(log.GetQuestObjectives, q)
				if ok and type(list) == "table" then cache[key] = list end
			end
		end
		local list = cache[key]
		if not list then return end
		local seen = 0
		for _, objective in ipairs(list) do
			local kindOf = Plain(objective.type)
			if kindOf == kind then
				seen = seen + 1
				if seen == n then
					local finished = Plain(objective.finished)
					return finished and true or false, Plain(objective.numFulfilled), Plain(objective.numRequired)
				end
			end
		end
	end
	function reader:Killed(npc)
		local mob = LG:Mob(npc)
		return mob and mob.name and killedNames[mob.name] or false
	end
	return reader
end

local function RecordReader(charKey)
	local store = E.Characters
	local record = store and store:Get(charKey)
	if not record then return end
	local quests = type(record.quests) == "table" and record.quests or {}
	local done = store.UnpackIDs(quests.history)
	local log = {}
	for _, row in ipairs(type(quests.log) == "table" and quests.log or {}) do
		if type(row) == "table" and row.id then log[row.id] = row end
	end
	local reader = { key = charKey, faction = record.faction, level = tonumber(record.level) or 1, record = record }
	function reader:Done(q) return done[q] == true and not log[q] end
	function reader:OnQuest(q) return log[q] ~= nil end
	function reader:Ready(q) return log[q] ~= nil and log[q].done == true end
	function reader:Count(item)
		local counts = type(record.counts) == "table" and record.counts[item]
		if type(counts) ~= "table" then return 0 end
		return (counts[1] or 0) + (counts[2] or 0) + (counts[4] or 0)
	end
	function reader:Reaction(faction)
		local rep = type(record.reps) == "table" and record.reps[faction]
		return type(rep) == "table" and tonumber(rep.reaction) or nil
	end
	function reader:RepValue(faction)
		local rep = type(record.reps) == "table" and record.reps[faction]
		if type(rep) == "table" and rep.value and rep.min and rep.max then return rep.value - rep.min, rep.max - rep.min end
	end
	function reader:Objective() return nil end
	function reader:Killed() return false end
	return reader
end

-- charKey (nil: the character you play) or a Characters record.
function A:Reader(charKey)
	if type(charKey) == "table" then charKey = self:KeyOfRecord(charKey) end
	if not charKey or charKey == E.charKey then return LiveReader() end
	return RecordReader(charKey)
end

function A:KeyOfRecord(record)
	local store = E.Characters
	if not (store and type(EldoUIDB) == "table") then return end
	for key, other in pairs(store:All()) do
		if other == record then return key end
	end
end

---------------------------------------------------------------------------
-- Step states (see the table in the plan, 2.5)
---------------------------------------------------------------------------
local OBJECTIVE_KIND = { kill = "monster", interact = "object", item = "item" }

local function OtherFaction(step, reader)
	return step.faction ~= nil and reader.faction ~= nil and step.faction ~= reader.faction
end

-- What the game says about a step by itself (before back-fill).
local function Observe(entry, step, reader)
	local kind = step.kind
	if kind == "level" then
		return reader.level >= step.ref and "done" or nil
	elseif kind == "rep" then
		local reaction = reader:Reaction(step.ref)
		return reaction and reaction >= step.standing and "done" or nil
	elseif kind == "link" then
		local _, _, _, state = A:Progress(step.ref, reader.key, reader)
		return state == "done" and "done" or nil
	elseif kind == "pickup" then
		if reader:OnQuest(step.quest) or reader:Done(step.quest) then return "done" end
	elseif kind == "quest" then
		if reader:OnQuest(step.quest) then return reader:Ready(step.quest) and "turnin" or "active" end
		if reader:Done(step.quest) then return "done" end
	elseif kind == "turnin" then
		if reader:OnQuest(step.quest) then return reader:Ready(step.quest) and "turnin" or nil end
		if reader:Done(step.quest) then return "done" end
	elseif kind == "item" or kind == "kill" or kind == "interact" then
		if reader:Done(step.quest) and not reader:OnQuest(step.quest) then return "done" end
		if kind == "item" and reader:Count(step.ref) >= (step.count or 1) then return "done" end
		if reader:OnQuest(step.quest) then
			local finished, have = reader:Objective(step.quest, OBJECTIVE_KIND[kind], kind == "item" and step.slot or step.objective)
			if finished then return "done" end
			if kind == "kill" and reader:Killed(step.ref) then return "done" end
			if (kind == "item" and reader:Count(step.ref) > 0) or (type(have) == "number" and have > 0) then return "partial" end
		end
	elseif kind == "goal" then
		if reader:Count(step.ref) >= (step.count or 1) then return "done" end
	elseif kind == "drop" then
		if reader:Killed(step.ref) then return "done" end
	elseif kind == "end" then
		if step.flag and reader:Done(step.flag) then return "done" end
	end
end

-- Are a step's prerequisites done? Other-faction steps do not count; an
-- any-of join needs one of its own side.
local function Ready(graph, step, states, reader)
	local own, done = 0, 0
	for _, f in ipairs(step.follows) do
		local up = graph.byId[f]
		if up and not OtherFaction(up, reader) then
			own = own + 1
			if states[f] == "done" then done = done + 1 end
		end
	end
	if own == 0 then return true end
	if step.any then return done > 0 end
	return done == own
end

local function Compute(entry, reader)
	local graph = entry.steps
	local states, partial = {}, {}
	for _, step in ipairs(graph.list) do
		if OtherFaction(step, reader) then
			states[step.id] = "otherfaction"
		else
			local seen = Observe(entry, step, reader)
			if seen == "partial" then partial[step.id] = true elseif seen then states[step.id] = seen end
		end
	end
	-- Back-fill: a later step done means every step before it is done too
	-- (through an any-of join only when it has one branch of your side).
	for position = #graph.list, 1, -1 do
		local step = graph.list[position]
		if states[step.id] == "done" or states[step.id] == "turnin" or states[step.id] == "active" then
			local fill = states[step.id] == "done" or step.kind ~= "turnin"
			local own = {}
			for _, f in ipairs(step.follows) do
				local up = graph.byId[f]
				if up and not OtherFaction(up, reader) then own[#own + 1] = f end
			end
			if fill and (not step.any or #own == 1) then
				for _, f in ipairs(own) do
					local up = graph.byId[f]
					-- A quest in the log is not done yet, even with a stale flag.
					if states[f] ~= "done" and not (up.kind == "turnin" and states[f] == "turnin") then
						if states[step.id] == "done" or up.kind ~= "turnin" then states[f] = "done" end
					end
				end
			end
		end
	end
	-- The rest: what you can do now, what is locked, what waits on a level.
	for _, step in ipairs(graph.list) do
		local id = step.id
		if not states[id] then
			if Ready(graph, step, states, reader) then
				local kind = step.kind
				if kind == "end" then
					states[id] = "done"
				elseif kind == "level" then
					states[id] = "low"
				elseif kind == "pickup" or kind == "quest" then
					local quest = LG:Quest(step.quest)
					states[id] = (quest and quest.minLevel and quest.minLevel > reader.level) and "low" or "available"
				elseif kind == "turnin" then
					local all = true
					for _, f in ipairs(step.follows) do
						if states[f] ~= "done" then all = false end
					end
					states[id] = all and reader:OnQuest(step.quest) and "turnin" or "active"
				elseif kind == "kill" or kind == "interact" or kind == "item" then
					states[id] = (partial[id] or reader:OnQuest(step.quest)) and "active" or "unknown"
				elseif kind == "drop" then
					states[id] = "unknown"
				else
					states[id] = "available"
				end
			else
				states[id] = "locked"
			end
		end
	end
	-- Side quests: their own status.
	for _, step in ipairs(graph.sideList) do
		if OtherFaction(step, reader) then
			states[step.id] = "otherfaction"
		elseif reader:OnQuest(step.quest) then
			states[step.id] = reader:Ready(step.quest) and "turnin" or "active"
		elseif reader:Done(step.quest) then
			states[step.id] = "done"
		elseif reader.live then
			local status = LG:QuestStatus(step.quest)
			states[step.id] = (status == "notforyou" and "otherfaction") or status
		else
			states[step.id] = "available"
		end
	end
	-- Totals: own-side steps that count.
	local done, total = 0, 0
	for _, step in ipairs(graph.list) do
		if COUNTS[step.kind] and states[step.id] ~= "otherfaction" then
			total = total + 1
			if states[step.id] == "done" then done = done + 1 end
		end
	end
	local finished = states["end"] == "done" or (total > 0 and done == total and not graph.byId["end"])
	local percent = total > 0 and math.floor(done * 100 / total) or 0
	if finished then percent = 100 end
	local state
	if finished then
		state = "done"
	elseif total == 0 then
		state = "unknown"
	else
		local any = {}
		for _, s in pairs(states) do any[s] = true end
		if any.turnin or any.active or done > 0 then
			state = "active"
		elseif any.available then
			state = "available"
		elseif any.low then
			state = "low"
		else
			state = "locked"
		end
	end
	return { states = states, done = done, total = total, percent = percent, state = state, at = GetTime and GetTime() or 0 }
end
A.Compute = Compute

---------------------------------------------------------------------------
-- Progress cache: the current character is rebuilt by events (one rebuild
-- a frame, only the entries an event touches); other characters are read
-- from the Characters store on demand.
---------------------------------------------------------------------------
local progress = {}  -- charKey -> entryKey -> result

function A:ClearProgress(charKey)
	if charKey then progress[charKey] = nil else wipe(progress) end
end

local function Result(key, charKey, reader)
	if type(charKey) == "table" then charKey = A:KeyOfRecord(charKey) end
	charKey = charKey or E.charKey
	local entry = A:Get(key)
	if not entry then return end
	progress[charKey] = progress[charKey] or {}
	local result = progress[charKey][key]
	if result then return result end
	reader = reader or A:Reader(charKey)
	if not reader then return end
	-- Guard against a link loop (an entry linking itself through others).
	progress[charKey][key] = { states = {}, done = 0, total = 0, percent = 0, state = "unknown", pending = true }
	result = Compute(entry, reader)
	progress[charKey][key] = result
	return result
end
A.Result = Result

function A:Progress(key, charKey, reader)
	local result = Result(key, charKey, reader)
	if not result then return 0, 0, 0, "unknown" end
	return result.done, result.total, result.percent, result.state
end

function A:StepState(key, stepId, charKey)
	local result = Result(key, charKey)
	return result and result.states[stepId] or nil
end

local OPEN = { turnin = 1, active = 2, available = 3, unknown = 4, low = 5 }
A.OPEN_RANK = OPEN

function A:NextSteps(key, charKey)
	local entry = self:Get(key)
	local result = Result(key, charKey)
	local list = {}
	if not (entry and result) then return list end
	for _, step in ipairs(entry.steps.list) do
		local state = result.states[step.id]
		if OPEN[state] and step.kind ~= "end" then list[#list + 1] = step end
	end
	table.sort(list, function(a, b)
		local ra, rb = OPEN[result.states[a.id]], OPEN[result.states[b.id]]
		if ra ~= rb then return ra < rb end
		return a.index < b.index
	end)
	return list
end

---------------------------------------------------------------------------
-- Names, captions and places of steps
---------------------------------------------------------------------------
local function FactionName(faction)
	local rep = C_Reputation
	if rep and rep.GetFactionDataByID then
		local ok, data = pcall(rep.GetFactionDataByID, faction)
		local name = ok and type(data) == "table" and Plain(data.name)
		if type(name) == "string" and name ~= "" then return name end
	end
	return (L["Faction %d"]):format(faction)
end
A.FactionName = FactionName

local function StandingName(standing)
	local label = rawget(_G, "FACTION_STANDING_LABEL" .. tostring(standing))
	if type(label) == "string" then return label end
	return tostring(standing)
end
A.StandingName = StandingName

local function ItemName(item)
	local record = LG:ItemRecord(item)
	if record and record.name then return record.name end
	local name = C_Item and C_Item.GetItemNameByID and Call(C_Item.GetItemNameByID, item)
	return type(name) == "string" and name or ("item:" .. item)
end
A.ItemName = ItemName

local function MobName(npc)
	local mob = LG:Mob(npc)
	return mob and mob.name or (L["NPC %s"]):format(tostring(npc))
end

local function QuestName(q)
	if not q then return "?" end
	local title = LG:QuestTitle(q)
	if title then return title end
	local seen = A.SeenQuest and A:SeenQuest(q)
	return seen and seen.title or ("#" .. q)
end
A.QuestName = QuestName

function A:StepTitle(step)
	local kind = step.kind
	if kind == "level" then return (L["Reach level %d"]):format(step.ref) end
	if kind == "rep" then return ("%s: %s"):format(FactionName(step.ref), StandingName(step.standing)) end
	if kind == "link" then return self:Name(step.ref) end
	if kind == "pickup" then return (L["Pick up: %s"]):format(QuestName(step.quest)) end
	if kind == "turnin" then return (L["Turn in: %s"]):format(QuestName(step.quest)) end
	if kind == "quest" then return QuestName(step.quest) end
	if kind == "item" or kind == "goal" then return ItemName(step.ref) end
	if kind == "kill" then return (L["Defeat %s"]):format(MobName(step.ref)) end
	if kind == "drop" then return (L["Defeat %s"]):format(MobName(step.ref)) end
	if kind == "interact" then return LG:ObjectName(step.ref) or (L["Object %d"]):format(step.ref) end
	if kind == "end" then
		local entry = self:Get(step.ref)
		local entryKind = entry and (entry.subKind or entry.kind)
		if entryKind == "raid" then return L["Attuned"] end
		if entryKind == "key" then return L["Key in your bags"] end
		return L["Chain done"]
	end
	return "?"
end

local STATE_CAPTION = E:TranslateValues({
	active = E.Key("In your quest log"), turnin = E.Key("Ready to turn in"), available = E.Key("Available"), locked = E.Key("Locked"),
	low = E.Key("Level too low"), done = E.Key("Done"), otherfaction = E.Key("Other faction"),
	unknown = E.Key("Not tracked: marked done when the next step is done"),
})
A.STATE_TITLE = STATE_CAPTION

function A:SizeText(size)
	if not size or size <= 1 then return L["Solo"] end
	if size <= 5 then return (L["Party %d"]):format(size) end
	return (L["Raid %d"]):format(size)
end

-- The gray line under a step's title.
function A:StepCaption(step, charKey, state)
	local kind = step.kind
	local reader = A:Reader(charKey)
	if kind == "pickup" or kind == "quest" or kind == "turnin" then
		local quest = LG:Quest(step.quest)
		local bits = { kind == "turnin" and L["Turn-in"] or L["Quest"] }
		if quest and quest.level and quest.level > 0 then bits[#bits + 1] = (L["Lvl %d"]):format(quest.level) end
		if quest and quest.suggested and quest.suggested > 1 then bits[#bits + 1] = self:SizeText(quest.suggested) end
		if state == "active" or state == "turnin" or state == "locked" or state == "low" then bits[#bits + 1] = STATE_CAPTION[state] end
		return table.concat(bits, " · ")
	elseif kind == "item" or kind == "goal" then
		local have = reader and reader:Count(step.ref) or 0
		return (L["%d of %d in bags"]):format(math.min(have, step.count or 1), step.count or 1) -- no-plural: no noun to inflect
	elseif kind == "kill" or kind == "interact" then
		if reader and reader.live and reader:OnQuest(step.quest) then
			local _, have, need = reader:Objective(step.quest, OBJECTIVE_KIND[kind], step.objective)
			if have and need then return ("%d / %d"):format(have, need) end
		end
		return state == "unknown" and L["Not tracked: marked done when the next step is done"] or (L["%d needed"]):format(step.count or 1)
	elseif kind == "drop" then
		return (L["Drops %s"]):format(ItemName(step.item))
	elseif kind == "level" then
		return reader and (L["You are level %d"]):format(reader.level) or ""
	elseif kind == "rep" then
		local value, max = nil, nil
		if reader then value, max = reader:RepValue(step.ref) end
		if value and max then
			return ("%s %s / %s"):format(StandingName(step.standing), BreakUpLargeNumbers and BreakUpLargeNumbers(value) or value,
				BreakUpLargeNumbers and BreakUpLargeNumbers(max) or max)
		end
		return (L["Reach %s"]):format(StandingName(step.standing))
	elseif kind == "link" then
		local done, total = self:Progress(step.ref, charKey)
		return E:Plural(total, "Attunement · %d of %d step", "Attunement · %d of %d steps"):format(done, total)
	elseif kind == "end" then
		return state == "done" and L["Done"] or L["All steps above"]
	end
	return ""
end

-- Where a step happens: the giver, the ender, the target or the dropper.
function A:StepPlace(step)
	local kind, place = step.kind, nil
	local quest = step.quest and LG:Quest(step.quest)
	if kind == "pickup" or kind == "quest" then
		place = quest and quest.starts[1]
	elseif kind == "turnin" then
		place = quest and quest.ends[1]
	elseif kind == "kill" or kind == "drop" then
		place = { kind = "npc", id = step.ref }
	elseif kind == "interact" then
		place = { kind = "object", id = step.ref }
	elseif kind == "item" or kind == "goal" then
		local best
		for _, source in ipairs(LG:ItemSources(step.ref) or {}) do
			if (source.kind == "npc" or source.kind == "object") and (not best or (source.chance or 0) > (best.chance or 0)) then best = source end
		end
		place = best and { kind = best.kind, id = best.id } or (quest and quest.starts[1])
	end
	if not place or place.kind == "item" then return end
	local camps = LG:SpawnPoints(place.kind, place.id)
	if not camps[1] then return end
	local point, instance = LG:PointFor(camps[1])
	if not point then return end
	local name = place.kind == "object" and LG:ObjectName(place.id) or MobName(place.id)
	return { uiMapID = point.uiMapID, x = point.x, y = point.y, zone = point.zone, instance = instance,
		kind = place.kind, id = place.id, name = name }
end

---------------------------------------------------------------------------
-- Lookups
---------------------------------------------------------------------------
local function Lookup(list, id)
	A:EnsureBuilt()
	local out = {}
	for _, hit in ipairs(list[tonumber(id) or id] or {}) do
		local entry = byKey[hit.key]
		local step = entry and entry.steps.byId[hit.step]
		if step then out[#out + 1] = { key = hit.key, step = step, index = step.index, total = #entry.steps.list } end
	end
	return out
end

function A:ForQuest(q) return Lookup(lookup.quest, q) end
function A:ForItem(item) return Lookup(lookup.item, item) end
function A:ForNpc(npc) return Lookup(lookup.npc, npc) end

function A:ForInstance(instance)
	self:EnsureBuilt()
	local out = {}
	for _, entry in ipairs(entries) do
		if entry.instance == instance and entry.kind ~= "dungeon" and entry.kind ~= "class" and self:FactionFits(entry) then
			out[#out + 1] = entry.key
		end
	end
	return out
end

---------------------------------------------------------------------------
-- The list for the current filters
---------------------------------------------------------------------------
function A:FactionFits(entry, filter)
	filter = filter or (self.db and self.db.showFaction) or "mine"
	if filter == "all" or not entry.side then return true end
	if filter == "mine" then filter = LG:Player().faction or entry.side end
	return entry.side == filter
end

function A:Shown(entry)
	local db = self.db
	if not self:FactionFits(entry) then return false end
	if entry.kind == "class" and db.classQuests ~= "all" and (entry.class ~= LG:Player().class or (self.RaceFits and not self:RaceFits(entry))) then return false end
	if entry.forever and db.showExpansions ~= "all" and not entry.inGame then return false end
	if entry.instance and not entry.forever and db.showExpansions ~= "all" then
		local info = LG:InstanceInfo(entry.instance)
		if info and not LG:Playable(info) then return false end
	end
	if db.hideDone then
		local _, _, _, state = self:Progress(entry.key)
		if state == "done" then return false end
	end
	return true
end

-- A Forever entry with no chain written for it: its page can only list the
-- quests you recorded for it, so with none recorded it has nothing to show
-- and stays out of the list (even with every filter off).
function A:Unwritten(entry)
	if type(entry) == "string" then entry = self:Get(entry) end
	return entry ~= nil and entry.forever == true and #entry.steps.list <= 1
end

function A:NothingToShow(entry)
	return self:Unwritten(entry) and not self:HasSeenFor(entry)
end

-- opts: all (no filters), group (one group key).
function A:List(opts)
	opts = opts or {}
	self:EnsureBuilt()
	local out = {}
	for _, entry in ipairs(entries) do
		if (not opts.group or entry.group == opts.group) and (opts.all or self:Shown(entry)) and not self:NothingToShow(entry) then
			out[#out + 1] = entry.key
		end
	end
	return out
end

-- Raids, keys and other chains (what the data text, the guild survey and
-- the Characters grid show).
function A:MainKeys(all)
	self:EnsureBuilt()
	local out = {}
	for _, entry in ipairs(entries) do
		local main = entry.kind == "raid" or entry.kind == "key" or entry.kind == "misc"
		if main and (all or self:FactionFits(entry, "mine")) then out[#out + 1] = entry.key end
	end
	return out
end

function A:InProgressCount()
	if not self:Running() then return 0 end
	local count = 0
	for _, key in ipairs(self:List()) do
		local entry = byKey[key]
		if entry and ALERT_GROUPS[entry.group] then
			local done, _, _, state = self:Progress(key)
			if state ~= "done" and done > 0 then count = count + 1 end
		end
	end
	return count
end

function A:Summary(charKey)
	local out = {}
	for _, key in ipairs(self:MainKeys()) do
		local done, total, percent, state = self:Progress(key, charKey)
		out[#out + 1] = { key = key, name = self:Name(key), done = done, total = total, percent = percent, state = state,
			next = self:NextSteps(key, charKey)[1] }
	end
	return out
end

---------------------------------------------------------------------------
-- Events: mark what changed, rebuild once a frame
---------------------------------------------------------------------------
local dirty, dirtyAll, queued = {}, false, false
local alertQueue, alertTimer = {}, nil
A.rebuilds = 0

local function Flush()
	queued = false
	if not A:Running() then return end
	A.rebuilds = A.rebuilds + 1
	A:EnsureBuilt()
	local mine = progress[E.charKey] or {}
	local before = {}
	local keys = {}
	if dirtyAll then
		for _, entry in ipairs(entries) do keys[#keys + 1] = entry.key end
	else
		for key in pairs(dirty) do keys[#keys + 1] = key end
	end
	-- Entries that link a changed entry change with it.
	local seen = {}
	for _, key in ipairs(keys) do seen[key] = true end
	local cursor = 1
	while cursor <= #keys do
		for _, hit in ipairs(lookup.linkedBy[keys[cursor]] or {}) do
			if not seen[hit.key] then
				seen[hit.key] = true
				keys[#keys + 1] = hit.key
			end
		end
		cursor = cursor + 1
	end
	for _, key in ipairs(keys) do
		before[key] = mine[key]
		mine[key] = nil
	end
	progress[E.charKey] = mine
	wipe(dirty)
	dirtyAll = false
	local reader = LiveReader()
	local changed = false
	for _, key in ipairs(keys) do
		local old = before[key]
		local new = Result(key, E.charKey, reader)
		if new and (not old or old.done ~= new.done or old.state ~= new.state or old.percent ~= new.percent) then changed = true end
		if new and old and not old.pending and A.primed then A:CompareForAlerts(byKey[key], old, new) end
	end
	A.primed = true
	if changed then LG:Fire("attune") end
end

function A:MarkDirty(what)
	if what == "all" or what == nil then
		dirtyAll = true
	elseif type(what) == "table" then
		for _, hit in ipairs(what) do dirty[hit.key or hit] = true end
	else
		dirty[what] = true
	end
	if queued then return end
	queued = true
	C_Timer.After(0, Flush)
end

-- Rebuild now (tests, the probe).
function A:FlushNow()
	if queued or dirtyAll or next(dirty) then Flush() end
end

local function EntriesWith(list)
	local out = {}
	for _, hits in pairs(list) do
		for _, hit in ipairs(hits) do out[#out + 1] = hit.key end
	end
	return out
end

-- Bag changes: only the entries whose item count changed are rebuilt. The
-- last count of each attunement item is kept; an item seen for the first
-- time counts as changed.
local itemCounts = {}

local function ChangedItemEntries()
	local out = {}
	for item, hits in pairs(lookup.item) do
		local count = C_Item and Call(C_Item.GetItemCount, item, true)
		count = tonumber(count) or 0
		if itemCounts[item] ~= count then
			itemCounts[item] = count
			for _, hit in ipairs(hits) do out[#out + 1] = hit.key end
		end
	end
	return out
end

local function BagsChanged()
	local changed = ChangedItemEntries()
	if #changed > 0 then A:MarkDirty(changed) end
end

local function QuestEvent(_, event, a, b)
	-- QUEST_ACCEPTED sends (questID) here, (logIndex, questID) on older
	-- clients; QUEST_TURNED_IN and QUEST_REMOVED send the quest first.
	local q
	if event == "QUEST_ACCEPTED" then
		q = tonumber(Plain(b)) or tonumber(Plain(a))
		A:RecordAccepted(q)
	else
		q = tonumber(Plain(a))
		if event == "QUEST_TURNED_IN" then A:RecordTurnedIn(q) end
	end
	if q then
		A:MarkDirty(lookup.quest[q] or {})
	else
		A:MarkDirty("all")
	end
end

-- Quest progress (objectives, ready to turn in): the entries of quests in the log.
local function LogEvent(_, event, unit)
	if event == "UNIT_QUEST_LOG_CHANGED" and unit ~= "player" then return end
	local hits = {}
	for q, list in pairs(lookup.quest) do
		if LG:OnQuest(q) then
			for _, hit in ipairs(list) do hits[#hits + 1] = hit end
		end
	end
	if #hits > 0 then A:MarkDirty(hits) end
end

local function ScanLockouts()
	if not (GetNumSavedInstances and GetSavedInstanceInfo and GetSavedInstanceEncounterInfo) then return end
	local count = Call(GetNumSavedInstances) or 0
	for i = 1, count do
		local r = { pcall(GetSavedInstanceInfo, i) }
		local reset, locked, encounters = Plain(r[4]), Plain(r[6]), Plain(r[12])
		if r[1] and locked and type(reset) == "number" and reset > 0 and type(encounters) == "number" then
			for e = 1, encounters do
				local ok, name, _, killed = pcall(GetSavedInstanceEncounterInfo, i, e)
				name, killed = Plain(name), Plain(killed)
				if ok and killed and type(name) == "string" then killedNames[name] = true end
			end
		end
	end
end

local EVENTS = {
	QUEST_ACCEPTED = QuestEvent,
	QUEST_TURNED_IN = QuestEvent,
	QUEST_REMOVED = QuestEvent,
	QUEST_LOG_UPDATE = LogEvent,
	UNIT_QUEST_LOG_CHANGED = LogEvent,
	QUEST_DATA_LOAD_RESULT = function() LG:Fire("attune") end,
	BAG_UPDATE_DELAYED = BagsChanged,
	UPDATE_FACTION = function() A:MarkDirty(EntriesWith(lookup.faction)) end,
	PLAYER_LEVEL_UP = function() A:MarkDirty("all") end,
	-- Only the encounter's name, and only when the game shows it.
	BOSS_KILL = function(_, _, _, name)
		name = Plain(name)
		if type(name) == "string" and name ~= "" then
			killedNames[name] = true
			A:MarkDirty(EntriesWith(lookup.npc))
		end
	end,
	UPDATE_INSTANCE_INFO = function()
		ScanLockouts()
		A:MarkDirty(EntriesWith(lookup.npc))
	end,
}
A.EVENTS = EVENTS

-- Tests: what BOSS_KILL and the lockouts gave.
function A:KilledNames()
	return killedNames
end

---------------------------------------------------------------------------
-- Alerts: one toast per step (merged within a second), and one with a
-- sound and "Tell the guild" for a finished attunement. Nothing in chat.
---------------------------------------------------------------------------
local ALERT_ICON = "Interface\\Icons\\INV_Misc_Key_04"

local function FlushAlerts()
	alertTimer = nil
	local queue = alertQueue
	alertQueue = {}
	for key, item in pairs(queue) do
		local name = A:Name(key)
		if item.finished then
			local actions = {
				{ label = L["Open"], func = function() A:Open(key) end, tip = L["Opens the Attunements tab on it."] },
			}
			if A.db.guildButton and IsInGuild and Call(IsInGuild) then
				actions[#actions + 1] = { label = L["Tell the guild"], tip = L["Posts one line in guild chat."], func = function()
					A:TellGuild(key)
				end }
			end
			A:PushAlert({ key = "attune:" .. key, title = L["Attunement complete"], text = name, icon = ALERT_ICON,
				sound = A.db.alertSound ~= "" and A.db.alertSound or nil, actions = actions })
		elseif #item.steps > 0 then
			local text
			if #item.steps == 1 then
				text = (L["%s: %s (%d of %d)"]):format(name, A:StepTitle(item.steps[1]), item.done, item.total)
			else
				text = E:Plural(#item.steps, "%s: %d step done (%d of %d)", "%s: %d steps done (%d of %d)"):format(name, #item.steps, item.done, item.total)
			end
			A:PushAlert({ key = "attunestep:" .. key, title = L["Step done"], text = text, icon = ALERT_ICON,
				actions = { { label = L["Open"], func = function() A:Open(key) end, tip = L["Opens the Attunements tab on it."] } } })
		end
	end
end

function A:CompareForAlerts(entry, old, new)
	if not (entry and self.db.alerts and ALERT_GROUPS[entry.group]) then return end
	local item = alertQueue[entry.key] or { steps = {} }
	local any = false
	for _, step in ipairs(entry.steps.list) do
		if COUNTS[step.kind] and new.states[step.id] == "done" and old.states[step.id] ~= "done" then
			item.steps[#item.steps + 1] = step
			any = true
		end
	end
	if new.state == "done" and old.state ~= "done" then
		item.finished = true
		any = true
	end
	if not any then return end
	item.done, item.total = new.done, new.total
	alertQueue[entry.key] = item
	if not alertTimer then alertTimer = C_Timer.After(1, FlushAlerts) or true end
end

-- Tests and the Test alert button.
function A:FlushAlerts()
	FlushAlerts()
end

local told = {}
-- One line in guild chat, on the player's click only (the toast button).
function A:TellGuild(key)
	if told[key] then return false end
	local text = (L["%s is now attuned: %s"]):format(UnitName("player") or "?", self:Name(key))
	-- Marked as told only once the line went out, so a refused one can be
	-- tried again.
	if not E:TryChatPost(text, "GUILD") then
		E:Print(E:ChatRefusedText())
		return false
	end
	told[key] = true
	return true
end

function A:TestAlert()
	local key = self:MainKeys()[1]
	if not key then
		A:PushAlert({ title = L["Step done"], text = L["A sample step"], icon = ALERT_ICON })
		return
	end
	A:PushAlert({ key = "attune:test", title = L["Attunement complete"], text = self:Name(key), icon = ALERT_ICON,
		sound = self.db.alertSound ~= "" and self.db.alertSound or nil,
		actions = { { label = L["Open"], func = function() A:Open(key) end, tip = L["Opens the Attunements tab on it."] } } })
end

---------------------------------------------------------------------------
-- Opening the tab, the command and the data text
---------------------------------------------------------------------------
function A:Running()
	return self.active and LG and LG.active and true or false
end

function A:Open(arg)
	if not self:Running() then return end
	LG:Open("attune", arg)
end

-- Entry whose name starts with the text (or holds it).
function A:Find(text)
	local word = E:FoldText(tostring(text or ""))
	if word == "" then return end
	local contains
	for _, key in ipairs(self:List({ all = true })) do
		local name = E:FoldText(self:Name(key))
		if name:sub(1, #word) == word or key == word then return key end
		if not contains and name:find(word, 1, true) then contains = key end
	end
	return contains
end

local function Command(arg)
	arg = strtrim(arg or "")
	local word = arg:lower()
	if not A.active then
		E:Print(E:ModuleOffHint("Attunements"))
		return
	end
	if not LG.active then
		E:Print(L["The Attunements tab lives in the Loot Guide. Turn the Loot Guide on first."])
		return
	end
	if word == "probe" then
		A:Probe()
	elseif word == "check" then
		A:Check()
	elseif word == "" then
		A:Open()
	else
		local key = A:Find(arg)
		if key then A:Open(key) else E:Print((L["No attunement matches %q."]):format(arg)) end
	end
end

E:AddCommand("attune", "[name | probe | check]  the Loot Guide on the Attunements tab; probe and check are for testers", Command, "Tools")

local dataTextDone
local function RegisterDataText()
	if dataTextDone or not E.RegisterDataText then return end
	dataTextDone = true
	E:RegisterDataText("Attunements", {
		title = L["Attunements"],
		events = { "QUEST_TURNED_IN", "BAG_UPDATE_DELAYED", "PLAYER_LEVEL_UP" },
		poll = true,
		interval = 10,
		text = function()
			if not A:Running() then return E:TokenHex(E.tokens.text.secondary) .. L["Attunements"] .. "|r" end
			local done, total = 0, 0
			for _, key in ipairs(A:MainKeys()) do
				total = total + 1
				local _, _, _, state = A:Progress(key)
				if state == "done" then done = done + 1 end
			end
			return ("%s %d/%d"):format(L["Attunements"], done, total)
		end,
		tooltip = function(tooltip)
			local sr, sg, sb = unpack(E.tokens.text.secondary)
			E.UIKit.TipTitle(tooltip, L["Attunements"])
			if not A:Running() then
				tooltip:AddLine(L["Switched off."], sr, sg, sb)
				return
			end
			local any = false
			for _, row in ipairs(A:Summary()) do
				if row.state ~= "done" and row.done > 0 then
					any = true
					tooltip:AddDoubleLine(row.name, ("%d%%"):format(row.percent), sr, sg, sb, 1, 1, 1)
				end
			end
			if not any then tooltip:AddLine(L["Nothing in progress."], sr, sg, sb) end
			tooltip:AddLine(" ")
			E:TooltipHint(tooltip, { L["Click"], L["open the Attunements tab"] })
		end,
		onClick = function() A:Open() end,
	})
end

---------------------------------------------------------------------------
-- WoW: Forever-only quests. The classic data cannot know them, so
-- with "Remember Forever quests" on, a quest you accept that the data does
-- not have (or with an id of 90000 and up) is kept in
-- EldoUIDB.attuneSeen[questID] = { t, title, npc, ender, map, x, y, lvl,
-- hdr, prev, done }: only what the game showed you, account-wide, at most
-- 400 (the oldest go first). Their dungeon pages list them; "Copy the list"
-- hands them to EldoUI's authors to write the chain.
---------------------------------------------------------------------------
local SEEN_CAP = 400
local FOREVER_IDS = 90000
local recentTurnIns = {}

local function SeenStore(create)
	if type(EldoUIDB) ~= "table" then return create and {} or nil end
	if type(EldoUIDB.attuneSeen) ~= "table" then
		if not create then return end
		EldoUIDB.attuneSeen = {}
	end
	return EldoUIDB.attuneSeen
end

function A:SeenQuest(q)
	local store = SeenStore(false)
	local record = store and store[tonumber(q) or q]
	return type(record) == "table" and record or nil
end

-- Recorded quests, newest first.
function A:SeenList()
	local list = {}
	for q, record in pairs(SeenStore(false) or {}) do
		if type(q) == "number" and type(record) == "table" then list[#list + 1] = { q = q, record = record } end
	end
	table.sort(list, function(a, b)
		local ta, tb = tonumber(a.record.t) or 0, tonumber(b.record.t) or 0
		if ta ~= tb then return ta > tb end
		return a.q > b.q
	end)
	return list
end

function A:Recordable(q)
	if type(q) ~= "number" then return false end
	if q >= FOREVER_IDS then return true end
	return LG:Quest(q) == nil
end

local function NpcNow()
	local guid = UnitGUID and Plain(UnitGUID("npc"))
	return LG.NpcFromGUID and LG.NpcFromGUID(guid) or nil
end

-- The quest log header above a quest (the zone or dungeon it is filed under).
local function LogHeader(q)
	local log = C_QuestLog
	if not (log and log.GetLogIndexForQuestID and log.GetInfo) then return end
	local index = Call(log.GetLogIndexForQuestID, q)
	if type(index) ~= "number" then return end
	for i = index - 1, 1, -1 do
		local ok, info = pcall(log.GetInfo, i)
		if ok and type(info) == "table" and Plain(info.isHeader) then
			local title = Plain(info.title)
			return type(title) == "string" and title or nil
		end
	end
end

local function Prune(store)
	local count, oldest, oldestAt = 0, nil, nil
	for q, record in pairs(store) do
		count = count + 1
		local at = type(record) == "table" and tonumber(record.t) or 0
		if not oldestAt or at < oldestAt then oldest, oldestAt = q, at end
	end
	while count > SEEN_CAP and oldest do
		store[oldest] = nil
		count = count - 1
		oldest, oldestAt = nil, nil
		for q, record in pairs(store) do
			local at = type(record) == "table" and tonumber(record.t) or 0
			if not oldestAt or at < oldestAt then oldest, oldestAt = q, at end
		end
	end
end

function A:RecordAccepted(q)
	if not (self.db and self.db.record) or not self:Recordable(q) then return end
	local store = SeenStore(true)
	local record = type(store[q]) == "table" and store[q] or {}
	record.t = time and time() or 0
	local log = C_QuestLog
	local title = log and Call(log.GetTitleForQuestID, q)
	if type(title) == "string" and title ~= "" then record.title = title end
	record.npc = NpcNow() or record.npc
	local map = C_Map and Call(C_Map.GetBestMapForUnit, "player")
	if type(map) == "number" then
		record.map = map
		local position = C_Map.GetPlayerMapPosition and Call(C_Map.GetPlayerMapPosition, map, "player")
		if type(position) == "table" and position.GetXY then
			local ok, x, y = pcall(position.GetXY, position)
			x, y = Plain(x), Plain(y)
			if ok and type(x) == "number" and type(y) == "number" then
				record.x, record.y = math.floor(x * 1000 + 0.5) / 1000, math.floor(y * 1000 + 0.5) / 1000
			end
		end
	end
	local level = UnitLevel and Plain(UnitLevel("player"))
	if type(level) == "number" then record.lvl = level end
	record.hdr = LogHeader(q) or record.hdr
	if #recentTurnIns > 0 then
		record.prev = {}
		for index, id in ipairs(recentTurnIns) do record.prev[index] = id end
	end
	store[q] = record
	Prune(store)
end

function A:RecordTurnedIn(q)
	if type(q) ~= "number" then return end
	table.insert(recentTurnIns, q)
	while #recentTurnIns > 3 do table.remove(recentTurnIns, 1) end
	local record = self:SeenQuest(q)
	if record then
		record.ender = NpcNow() or record.ender
		record.done = time and time() or 0
	end
end

-- Recorded quests filed under a dungeon (the log header or the title names it).
local function FiledUnder(record, name)
	local hdr, title = A.Fold(record.hdr), A.Fold(record.title)
	if hdr ~= "" and (hdr:find(name, 1, true) or name:find(hdr, 1, true)) then return true end
	return title ~= "" and title:find(name, 1, true) ~= nil
end

function A:SeenFor(entry)
	if type(entry) == "string" then entry = self:Get(entry) end
	local out = {}
	if not entry then return out end
	local name = A.Fold(entry.fixedName or self:Name(entry))
	if name == "" then return out end
	for _, row in ipairs(self:SeenList()) do
		if FiledUnder(row.record, name) then out[#out + 1] = row end
	end
	return out
end

-- Whether any recorded quest is filed under the entry (no sorting; the list
-- asks this for every Forever entry on each draw).
function A:HasSeenFor(entry)
	if type(entry) == "string" then entry = self:Get(entry) end
	if not entry then return false end
	local name = A.Fold(entry.fixedName or self:Name(entry))
	if name == "" then return false end
	for q, record in pairs(SeenStore(false) or {}) do
		if type(q) == "number" and type(record) == "table" and FiledUnder(record, name) then return true end
	end
	return false
end

local function JsonString(text)
	text = tostring(text or "")
	text = text:gsub("\\", "\\\\"):gsub("\"", "\\\""):gsub("[%c]", function(c) return ("\\u%04x"):format(c:byte()) end)
	return "\"" .. text .. "\""
end

-- One JSON object per line, newest first.
function A:SeenText()
	local lines = {}
	for _, row in ipairs(self:SeenList()) do
		local r = row.record
		local parts = { ("\"q\":%d"):format(row.q) }
		if r.title then parts[#parts + 1] = "\"title\":" .. JsonString(r.title) end
		for _, field in ipairs({ "npc", "ender", "map", "lvl", "t", "done" }) do
			if type(r[field]) == "number" then parts[#parts + 1] = ("\"%s\":%d"):format(field, r[field]) end
		end
		if type(r.x) == "number" and type(r.y) == "number" then parts[#parts + 1] = ("\"x\":%.3f,\"y\":%.3f"):format(r.x, r.y) end
		if r.hdr then parts[#parts + 1] = "\"hdr\":" .. JsonString(r.hdr) end
		if type(r.prev) == "table" and #r.prev > 0 then
			local ids = {}
			for index, id in ipairs(r.prev) do ids[index] = tostring(tonumber(id) or 0) end
			parts[#parts + 1] = "\"prev\":[" .. table.concat(ids, ",") .. "]"
		end
		lines[#lines + 1] = "{" .. table.concat(parts, ",") .. "}"
	end
	return table.concat(lines, "\n")
end

function A:CopySeen()
	local list = self:SeenList()
	local help = #list > 0 and E:Plural(#list, "%d Forever quest you took. Copy it (Ctrl+C) and send it to EldoUI's authors so the dungeon gets a full chain.",
		"%d Forever quests you took. Copy them (Ctrl+C) and send them to EldoUI's authors so the dungeons get full chains."):format(#list)
		or L["No Forever quests recorded yet. Take a quest for a Forever dungeon and it shows here."]
	E:ShowCopyBox(L["Forever quests"], help, self:SeenText())
end

function A:ClearSeen()
	if type(EldoUIDB) == "table" then EldoUIDB.attuneSeen = nil end
	LG:Fire("attune")
end

---------------------------------------------------------------------------
-- Tester tools: /eui attune probe (what the game's quest lines report on
-- this map) and /eui attune check (step quests the game has no title for).
-- Both only read and open a copy box.
---------------------------------------------------------------------------
function A:ProbeText()
	local lines = {}
	local map = C_Map and Call(C_Map.GetBestMapForUnit, "player")
	local info = type(map) == "number" and C_Map.GetMapInfo and Call(C_Map.GetMapInfo, map)
	lines[#lines + 1] = ("map %s %s"):format(tostring(map or "?"), type(info) == "table" and tostring(Plain(info.name) or "") or "")
	local questLine = C_QuestLine
	if not (questLine and questLine.GetAvailableQuestLines) then
		lines[#lines + 1] = "C_QuestLine.GetAvailableQuestLines: not in this client"
	elseif type(map) == "number" then
		if questLine.RequestQuestLinesForMap then pcall(questLine.RequestQuestLinesForMap, map) end
		local ok, list = pcall(questLine.GetAvailableQuestLines, map)
		if ok and type(list) == "table" then
			lines[#lines + 1] = ("available quest lines: %d"):format(#list)
			for _, line in ipairs(list) do
				local id, name, quest = Plain(line.questLineID), Plain(line.questLineName), Plain(line.questID)
				local quests = {}
				if questLine.GetQuestLineQuests and type(id) == "number" then
					local fine, ids = pcall(questLine.GetQuestLineQuests, id)
					if fine and type(ids) == "table" then
						for index, q in ipairs(ids) do quests[index] = tostring(Plain(q) or "?") end
					end
				end
				lines[#lines + 1] = ("  line %s %s quest %s: %s"):format(tostring(id or "?"), tostring(name or ""), tostring(quest or "?"), table.concat(quests, ","))
			end
		else
			lines[#lines + 1] = "available quest lines: none"
		end
	end
	local log = C_QuestLog
	if questLine and questLine.GetQuestLineInfo and log and log.GetNumQuestLogEntries and log.GetInfo then
		local count = Call(log.GetNumQuestLogEntries) or 0
		for i = 1, count do
			local ok, row = pcall(log.GetInfo, i)
			local q = ok and type(row) == "table" and not Plain(row.isHeader) and Plain(row.questID)
			if type(q) == "number" then
				local fine, line = pcall(questLine.GetQuestLineInfo, q, map)
				if fine and type(line) == "table" then
					lines[#lines + 1] = ("log quest %d: line %s %s"):format(q, tostring(Plain(line.questLineID) or "?"), tostring(Plain(line.questLineName) or ""))
				else
					lines[#lines + 1] = ("log quest %d: no line"):format(q)
				end
			end
		end
	end
	return table.concat(lines, "\n")
end

function A:Probe()
	E:ShowCopyBox(L["Attunements probe"], L["What the game's quest lines report on this map. Copy it (Ctrl+C) and send it to EldoUI's authors."], self:ProbeText())
end

-- Every quest id a step names, once.
function A:StepQuestIDs()
	local ids, seen = {}, {}
	for _, entry in ipairs(self:AllEntries()) do
		for _, step in ipairs(entry.steps.list) do
			local q = step.quest
			if q and not seen[q] then
				seen[q] = true
				ids[#ids + 1] = { q = q, key = entry.key }
			end
		end
	end
	return ids
end

function A:CheckText()
	local log = C_QuestLog
	local missing = {}
	local ids = self:StepQuestIDs()
	for _, row in ipairs(ids) do
		local title = log and Call(log.GetTitleForQuestID, row.q)
		if type(title) ~= "string" or title == "" then
			missing[#missing + 1] = ("%d  %s  (%s)"):format(row.q, tostring(LG:QuestTitle(row.q) or "?"), row.key)
		end
	end
	local head = (E:Plural(#ids, "%d step quest checked", "%d step quests checked")):format(#ids)
		.. "; " .. (E:Plural(#missing, "%d has no title in this client", "%d have no title in this client")):format(#missing)
	return head .. (#missing > 0 and ("\n" .. table.concat(missing, "\n")) or ""), #missing
end

function A:Check()
	local log = C_QuestLog
	local ids = self:StepQuestIDs()
	if log and log.RequestLoadQuestByID then
		for _, row in ipairs(ids) do pcall(log.RequestLoadQuestByID, row.q) end
	end
	E:Print((E:Plural(#ids, "Checking %d quest; the list opens in a few seconds.", "Checking %d quests; the list opens in a few seconds.")):format(#ids))
	C_Timer.After(4, function()
		E:ShowCopyBox(L["Attunements check"], L["Step quests the game has no title for (removed or renumbered on WoW: Forever). Copy it (Ctrl+C) and send it to EldoUI's authors."],
			(A:CheckText()))
	end)
end

-- What the tab knows, as label / value lines (the data status view).
function A:DataStatusLines()
	local LD = Data()
	local steps, quests = 0, {}
	local count = 0
	for _, entry in ipairs(self:AllEntries()) do
		count = count + 1
		for _, step in ipairs(entry.steps.list) do
			if COUNTS[step.kind] then steps = steps + 1 end
			if step.quest then quests[step.quest] = true end
		end
	end
	local questCount = 0
	for _ in pairs(quests) do questCount = questCount + 1 end
	return {
		{ L["Loot data"], LG:DataStatusText(true) },
		{ L["Chain data"], LD and LD.attuneVersion and tostring(LD.attuneVersion) or L["not loaded"] },
		{ L["Entries"], tostring(count) },
		{ L["Steps"], tostring(steps) },
		{ L["Quests"], tostring(questCount) },
		{ L["Forever quests seen"], tostring(#self:SeenList()) },
	}
end

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------
-- Stored values the options no longer offer go back to the default.
local function Sanitize(db)
	if db.guildAnswer ~= "ask" and db.guildAnswer ~= "never" then db.guildAnswer = "ask" end
	if db.view ~= "chain" and db.view ~= "list" then db.view = "chain" end
	if db.overview ~= "mine" and db.overview ~= "guild" then db.overview = "mine" end
	db.guildKeepDays = math.min(math.max(tonumber(db.guildKeepDays) or 60, 7), 180)
	db.guildMaxNames = math.min(math.max(tonumber(db.guildMaxNames) or 10, 0), 25)
end
A.Sanitize = Sanitize

---------------------------------------------------------------------------
-- Tab or hub section
---------------------------------------------------------------------------
local HUB = "adventure"
local hubSection

function A:InHub()
	local hub = E.Adventure
	return (hub and hub.started and LG.RegisterHubSection and LG:GetPage(HUB)) and true or false
end

-- The page frame is built once; it moves between the window's page area
-- and the hub's section area.
local function Reparent(parent)
	local frame = A.pageFrame
	if frame and parent and frame:GetParent() ~= parent then
		frame:SetParent(parent)
		frame:ClearAllPoints()
		frame:SetAllPoints(parent)
	end
	return frame
end

local function HubSection()
	if hubSection then return hubSection end
	local page = A.PAGE
	hubSection = {
		title = page.title, desc = page.desc, icon = "Interface\\Icons\\INV_Misc_Key_14", group = "atlas",
		words = { "attune", "attunements" },
		count = page.count,
		build = function(parent) return Reparent(parent) or page.create(parent) end,
		show = function(frame, arg)
			Reparent(LG.HubContent and LG:HubContent(HUB))
			if page.show then page.show(frame, arg) end
		end,
		hide = page.hide,
		refresh = page.refresh,
	}
	return hubSection
end

function A:PlaceHome()
	local unregister = LG.UnregisterHubSection
	if not (self.started and self.PAGE) then
		if unregister then LG:UnregisterHubSection(HUB, "attune") end
		return
	end
	if self:InHub() then
		if self.StopPage and LG:GetPage("attune") then self:StopPage() end
		local section = HubSection()
		if self.pageFrame then section.frame = self.pageFrame end
		LG:RegisterHubSection(HUB, "attune", section)
	else
		if unregister then LG:UnregisterHubSection(HUB, "attune") end
		local window = LG.WindowFrame and LG:WindowFrame()
		if self.pageFrame and window then
			self.PAGE.frame = Reparent(window.content)
		end
		if self.StartPage then self:StartPage() end
	end
end

function A:Start()
	if self.started or not self:Running() then return end
	self.started = true
	for event, fn in pairs(EVENTS) do self:RegisterEvent(event, fn) end
	LG:On("attunements", function(changed)
		if changed.data then
			A:Reset()
			A:MarkDirty("all")
		elseif changed.quests or changed.player then
			A:MarkDirty("all")
		end
	end)
	RegisterDataText()
	self:PlaceHome()
	if self.StartTooltips then self:StartTooltips() end
	if self.StartGuild then self:StartGuild() end
	if self.StartGrid then self:StartGrid() end
	ScanLockouts()
	self.primed = false
	self:MarkDirty("all")
end

function A:Stop()
	if not self.started then return end
	self.started = false
	for event in pairs(EVENTS) do self:UnregisterEvent(event) end
	LG:Off("attunements")
	if self.StopPage then self:StopPage() end
	self:PlaceHome()
	if self.StopTooltips then self:StopTooltips() end
	if self.StopGuild then self:StopGuild() end
	if self.StopGrid then self:StopGrid() end
	wipe(alertQueue)
end

function A:OnInitialize()
	Sanitize(self.db)
	-- Start and stop with the Loot Guide.
	if LG then
		hooksecurefunc(LG, "OnEnable", function() if A.active then A:Start() end end)
		hooksecurefunc(LG, "OnDisable", function() A:Stop() end)
	end
end

function A:OnEnable()
	Sanitize(self.db)
	self:Start()
end

function A:OnDisable()
	self:Stop()
	LG:Fire("pages")
end

function A:OnProfileChanged()
	Sanitize(self.db)
	if not self:Running() then return end
	self:ClearProgress()
	self:MarkDirty("all")
	LG:Fire("attune")
	if self.RefreshPins then self:RefreshPins() end
end
