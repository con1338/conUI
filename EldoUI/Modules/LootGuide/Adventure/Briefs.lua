-- EldoUI My Adventure: arrival and dungeon briefs, "you missed one" and the
-- level-up page data.
--
-- Headless: this file builds the briefs and announces them; the moments
-- and the pages decide how they look. Each brief is data
-- with finished lines, built from the quest log, our quest and instance
-- data, your notes and your runs. Nothing is accepted or queued.
--
-- API (E.Journal):
--   J:ArrivalBrief([uiMapID]) -> { kind = "arrival", uiMapID, zone, level,
--                         inLog, ready, available, notes, quests, lines }
--   J:DoorBrief([instanceKey]) -> { kind = "door", key, name, quests,
--                         upgrades, attune, lastRun, lines, seconds = 20 }
--   J:MissedOne(instanceKey) -> { kind = "missed", key, name, quests, lines } or nil
--   J:LevelUpPage(level[, bare]) -> { kind = "levelup", level, dungeons,
--                         quests, attune, spells, lines } (bare: without the
--                         Talent Planner's checklist lines)
--   J:LastBrief(kind)    the last brief of a kind that was announced
-- Callbacks (J.RegisterCallback): "Brief"(kind, brief) when a brief is due
-- and its switch is on ("Arrival and dungeon briefs" for arrival, door and
-- missed; "What opens at the next level" for levelup); "BriefEnd"(kind)
-- when the door brief is over (20 seconds or the first boss pull).
-- Arrival and door briefs never start in combat: one that comes due in
-- combat waits for its end and is dropped if you moved on.
local _, E = ...
local L = E.L
local A = E.Adventure
local J = E.Journal
local LG = E.LootGuide
local N = A.Next

local Plain = A.Plain
local min = math.min

local B = {}
A.Briefs = B

B.DOOR_SECONDS = 20

local function Num(value)
	value = Plain(value)
	return type(value) == "number" and value or nil
end

local function Settings()
	return A.db or A.defaults
end

local function InPlace(name)
	return N.InPlace(name)
end

local function QuestTitle(id)
	local quest = LG:JourneyQuest(id)
	return (quest and quest.title) or LG:QuestTitle(id) or ("#" .. tostring(id))
end

local function HereMap()
	if Plain(IsInInstance and IsInInstance()) or not (C_Map and C_Map.GetBestMapForUnit) then return nil end
	local ok, map = pcall(C_Map.GetBestMapForUnit, "player")
	return ok and Num(map) or nil
end

local function HereInstance()
	if not Plain(IsInInstance and IsInInstance()) then return nil end
	local ok, _, _, _, _, _, _, _, instanceID = pcall(GetInstanceInfo)
	instanceID = ok and Num(instanceID)
	return instanceID and LG.InstanceForPlayer and LG:InstanceForPlayer(instanceID) or nil
end

---------------------------------------------------------------------------
-- Arrival brief
---------------------------------------------------------------------------
local function NotesHere(uiMapID, zone)
	local rec = J.Char and J:Char()
	local count = 0
	for _, note in ipairs(rec and type(rec.notes) == "table" and rec.notes or {}) do
		if type(note) == "table" and not note.archived and ((uiMapID and note.mapID == uiMapID) or (zone and note.zone == zone)) then
			count = count + 1
		end
	end
	return count
end

function J:ArrivalBrief(uiMapID)
	uiMapID = Num(uiMapID) or HereMap()
	if not uiMapID then return nil end
	local zone = N.ZoneName(uiMapID)
	if not zone then return nil end
	local brief = { kind = "arrival", uiMapID = uiMapID, zone = zone, inLog = 0, ready = 0, available = 0, quests = {}, lines = {} }
	local low, high = N.ZoneRange(uiMapID)
	if low then brief.level = { min = low, max = high } end
	local ctx = N:Context()
	for _, row in ipairs(ctx.log.list) do
		local quest = LG:JourneyQuest(row.id)
		if row.header == zone or N.QuestZone(quest) == uiMapID then
			brief.inLog = brief.inLog + 1
			if row.ready then brief.ready = brief.ready + 1 end
			brief.quests[#brief.quests + 1] = row.id
		end
	end
	for _, row in ipairs(N.Fitting(ctx)) do
		if N.QuestZone(row.quest) == uiMapID then brief.available = brief.available + 1 end
	end
	brief.notes = NotesHere(uiMapID, zone)
	local head = low and (L["%s (%d-%d)"]):format(zone, low, high) or zone
	brief.lines[1] = head
	if brief.inLog > 0 then
		brief.lines[#brief.lines + 1] = E:Plural(brief.inLog, "%d quest here in your log.", "%d quests here in your log."):format(brief.inLog)
	end
	if brief.ready > 0 then
		brief.lines[#brief.lines + 1] = E:Plural(brief.ready, "%d of them is ready to hand in.", "%d of them are ready to hand in."):format(brief.ready)
	end
	if brief.available > 0 then
		brief.lines[#brief.lines + 1] = E:Plural(brief.available, "%d quest you can pick up here.", "%d quests you can pick up here."):format(brief.available)
	end
	if brief.notes > 0 then
		brief.lines[#brief.lines + 1] = E:Plural(brief.notes, "%d of your notes is about this place.", "%d of your notes are about this place."):format(brief.notes)
	end
	if low and ctx.level < low - 2 then
		brief.lines[#brief.lines + 1] = (L["Careful: the zone is %d-%d and you are level %d."]):format(low, high, ctx.level)
	end
	brief.empty = #brief.lines <= 1
	return brief
end

---------------------------------------------------------------------------
-- Door brief, "you missed one"
---------------------------------------------------------------------------
local function InstanceLogQuests(key)
	local ids = {}
	for _, id in ipairs(LG:InstanceQuestIDs(key)) do ids[id] = true end
	local inLog, open = {}, {}
	for _, row in ipairs(N:Context().log.list) do
		if ids[row.id] then
			inLog[#inLog + 1] = row
			if not row.ready then open[#open + 1] = row end
		end
	end
	return inLog, open
end

local function LastRun(info)
	local runs = N.Runs(info, { level = Num(UnitLevel("player")) or 1 })
	if not runs or runs.total == 0 then return nil end
	local I = E.Instances
	local me = I.CharKey and I:CharKey()
	for _, run in ipairs(I:Store().runs) do
		-- The newest finished run (the open one is this visit).
		if run.char == me and run.instanceID == info.map and run.leave then
			return { at = run.enter, seconds = run.leave > run.enter and run.leave - run.enter or nil, runs = runs.total, median = runs.median }
		end
	end
	return { runs = runs.total, median = runs.median }
end

function J:DoorBrief(key)
	key = key or HereInstance()
	local info = key and LG:InstanceInfo(key)
	if not info then return nil end
	local brief = { kind = "door", key = key, name = info.name, quests = {}, upgrades = {}, lines = { info.name }, seconds = B.DOOR_SECONDS }
	local inLog = InstanceLogQuests(key)
	for _, row in ipairs(inLog) do brief.quests[#brief.quests + 1] = row.id end
	if #inLog > 0 then
		local names = {}
		for index = 1, min(3, #inLog) do names[index] = QuestTitle(inLog[index].id) end
		brief.lines[#brief.lines + 1] = E:Plural(#inLog, "Your quest here: %s.", "Your quests here: %s."):format(N.List(names))
	end
	local ok, best, _, items = pcall(LG.BestInstance, LG)
	if ok and best == key and type(items) == "table" then
		local names = {}
		for index, itemID in ipairs(items) do
			brief.upgrades[index] = itemID
			if index <= 2 then
				local record = LG:ItemRecord(itemID)
				names[#names + 1] = record and record.name or ("item:" .. itemID)
			end
		end
		brief.lines[#brief.lines + 1] = E:Plural(#items, "%d upgrade for you here: %s.", "%d upgrades for you here: %s."):format(#items, N.List(names))
	end
	local attuneKey, step = N.AttuneInside(key)
	if attuneKey then
		local AT = E.Attunements
		brief.attune = { key = attuneKey, step = step }
		brief.lines[#brief.lines + 1] = (L["A step of %s is here: %s."]):format(AT:Name(attuneKey), AT:StepTitle(step))
	end
	local last = LastRun(info)
	brief.lastRun = last
	if last and last.seconds then
		brief.lines[#brief.lines + 1] = (L["Your last run took %s."]):format(N.FormatDuration(last.seconds))
	elseif last and last.runs then
		brief.lines[#brief.lines + 1] = E:Plural(last.runs, "You have been here %d time.", "You have been here %d times."):format(last.runs)
	end
	brief.empty = #brief.lines <= 1
	return brief
end

function J:MissedOne(key)
	local info = key and LG:InstanceInfo(key)
	if not info then return nil end
	local _, open = InstanceLogQuests(key)
	if #open == 0 then return nil end
	local brief = { kind = "missed", key = key, name = info.name, quests = {}, lines = {} }
	local names = {}
	for index, row in ipairs(open) do
		brief.quests[index] = row.id
		if index <= 3 then names[#names + 1] = QuestTitle(row.id) end
	end
	brief.lines[1] = (L["You left %s with a quest unfinished."]):format(info.name)
	brief.lines[2] = (L["Still open: %s."]):format(N.List(names))
	return brief
end

---------------------------------------------------------------------------
-- What opens at a level
---------------------------------------------------------------------------
function J:LevelUpPage(level, bare)
	level = Num(level) or Num(UnitLevel("player")) or 1
	local page = { kind = "levelup", level = level, dungeons = {}, quests = 0, attune = {}, lines = {} }
	local faction = LG:Player().faction
	local window = tonumber(LG.db and LG.db.levelWindow) or 3
	for _, info in ipairs(LG:Catalog()) do
		local raidOK = info.kind ~= "raid" or Settings().nextRaids
		local side = N.CitySide(info)
		if raidOK and info.min and LG:OpenNow(info) and not info.world and not (side and faction and side ~= faction) then
			-- New in reach: fits now, did not one level ago.
			local before = LG:FitsLevel(info, level - 1)
			local now = LG:FitsLevel(info, level)
			if (now == "fit" or now == "near") and before ~= "fit" and before ~= "near" then
				page.dungeons[#page.dungeons + 1] = info.key
			elseif info.min == level then
				page.dungeons[#page.dungeons + 1] = info.key
			end
		end
	end
	for _, row in ipairs(LG:JourneyQuests({ level = level, above = 0, below = 0 })) do
		if row.quest.minLevel == level and row.status == "available" then page.quests = page.quests + 1 end
	end
	local AT = E.Attunements
	if AT and AT.Running and AT:Running() then
		for _, key in ipairs(AT:MainKeys()) do
			local entry = AT:Get(key)
			if entry and entry.minLevel == level then page.attune[#page.attune + 1] = key end
		end
	end
	-- The Talent Planner's level-up checklist: talent point, trainer, class
	-- quests and gear, one line each.
	local checklist = {}
	local TP = E.Talents
	if not bare and TP and TP.active and type(TP.LevelUpChecklist) == "function" then
		local ok, list = pcall(TP.LevelUpChecklist, TP, level)
		if ok and type(list) == "table" and type(list.items) == "table" then
			for _, item in ipairs(list.items) do
				-- Dungeons in reach have their own line on this page.
				if type(item) == "table" and type(item.text) == "string" and item.text ~= "" and item.kind ~= "dungeons" then
					checklist[#checklist + 1] = item.text
					if item.kind == "spells" then page.trainerListed = true end
				end
			end
		end
	end
	local T = E.Training
	if not page.trainerListed and T and T.active and type(T.Totals) == "function" then
		local ok, totals = pcall(T.Totals, T)
		if ok and type(totals) == "table" and tonumber(totals.count) then page.spells = totals.count end
	end
	page.lines[1] = (L["What opens at level %d"]):format(level)
	if #page.dungeons > 0 then
		local names = {}
		for _, key in ipairs(page.dungeons) do
			local info = LG:InstanceInfo(key)
			names[#names + 1] = info and info.name or key
		end
		page.lines[#page.lines + 1] = E:Plural(#page.dungeons, "Dungeon in reach: %s.", "Dungeons in reach: %s."):format(N.List(names))
	end
	if page.quests > 0 then
		page.lines[#page.lines + 1] = E:Plural(page.quests, "%d new quest for your level.", "%d new quests for your level."):format(page.quests)
	end
	for _, key in ipairs(page.attune) do
		page.lines[#page.lines + 1] = (L["%s attunement can start."]):format(AT:Name(key))
	end
	if page.spells and page.spells > 0 then
		page.lines[#page.lines + 1] = E:Plural(page.spells, "%d spell at your trainer.", "%d spells at your trainer."):format(page.spells)
	end
	for _, text in ipairs(checklist) do page.lines[#page.lines + 1] = text end
	page.empty = #page.lines <= 1
	page.window = window
	return page
end

---------------------------------------------------------------------------
-- When briefs come due
---------------------------------------------------------------------------
local last = {}        -- kind -> brief
local state = { map = nil, instance = nil, pending = nil, doorTimer = nil }
B.state = state

function J:LastBrief(kind)
	return last[kind]
end

local function Announce(kind, brief)
	if not brief or brief.empty then return end
	last[kind] = brief
	A:Fire("Brief", kind, brief)
end
B.Announce = Announce

local function EndDoor()
	if state.doorTimer then
		state.doorTimer:Cancel()
		state.doorTimer = nil
	end
	if last.door and not last.door.ended then
		last.door.ended = true
		A:Fire("BriefEnd", "door")
	end
end
B.EndDoor = EndDoor

local function Arrive(uiMapID)
	if not Settings().briefs then return end
	if InCombatLockdown() then
		state.pending = { kind = "arrival", map = uiMapID }
		return
	end
	Announce("arrival", J:ArrivalBrief(uiMapID))
end

local function Door(key)
	if not Settings().briefs then return end
	if InCombatLockdown() then
		state.pending = { kind = "door", key = key }
		return
	end
	EndDoor()
	local brief = J:DoorBrief(key)
	Announce("door", brief)
	if brief and not brief.empty then state.doorTimer = C_Timer.NewTimer(B.DOOR_SECONDS, EndDoor) end
end

-- Zone and instance changes: one brief per new place.
function B.Check()
	if not A.started then return end
	local key = HereInstance()
	if key then
		if key ~= state.instance then
			state.instance = key
			Door(key)
		end
		return
	end
	if state.instance then
		local left = state.instance
		state.instance = nil
		EndDoor()
		if Settings().briefs then Announce("missed", J:MissedOne(left)) end
	end
	local map = HereMap()
	if map and map ~= state.map then
		local first = not state.map
		state.map = map
		-- The zone you log in to is no arrival.
		if not first then Arrive(map) end
	end
end

local function AfterCombat()
	local pending = state.pending
	state.pending = nil
	if not pending then return end
	if pending.kind == "arrival" and pending.map == HereMap() then
		Arrive(pending.map)
	elseif pending.kind == "door" and pending.key == HereInstance() then
		Door(pending.key)
	end
end

local function LevelUp(_, level)
	if not (A.started and Settings().levelUpPage) then return end
	level = Num(level)
	if not level then return end
	local page = J:LevelUpPage(level)
	-- The Talent Planner's level-up reminder already shows this level; the
	-- page stays on the Moments page without a second toast.
	local TP = E.Talents
	if TP and type(TP.OwnsLevelUp) == "function" and TP:OwnsLevelUp() then
		if page and not page.empty then last.levelup = page end
		return
	end
	Announce("levelup", page)
end

A:AddPart("briefs", {
	order = 61,
	init = function()
		for _, event in ipairs({ "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD" }) do
			LG:Listen(event, "adventure-briefs", function() C_Timer.After(0.5, B.Check) end)
		end
		LG:Listen("PLAYER_REGEN_ENABLED", "adventure-briefs", function() if A.started then AfterCombat() end end)
		LG:Listen("ENCOUNTER_START", "adventure-briefs", function() if A.started then EndDoor() end end)
		LG:Listen("PLAYER_LEVEL_UP", "adventure-briefs", LevelUp)
	end,
	start = function()
		state.map, state.instance = HereMap(), HereInstance()
	end,
	stop = function()
		EndDoor()
		state.pending = nil
	end,
})

