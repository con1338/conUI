-- EldoUI My Adventure: the where-next engine, trip plans and the prep
-- checklist.
--
-- A pure ranking over what the game says and what our data knows. It
-- suggests where to go next and why; it never acts. Every action a card
-- carries is navigation (a map pin, a page, the objective tracker for a
-- quest already in your log, the group finder window, the chat box filled
-- but not sent) and runs only on a click (N:Act).
--
-- API (E.Journal, also EldoUI.Journal for plugins):
--   J:Next(opts) -> result
--       opts (all optional):
--         kinds    { dungeon = true, ... }   only these kinds
--         group    "solo" | "small" | "full" | "raid"   the Group chip
--                  (default: your party right now)
--         minutes  the time chip: how long you want to play
--         limit    cards to return (default all)
--         hidden   true: keep cards you put away with "Not now"
--         fresh    true: rebuild now (out of combat) instead of the cache
--       result = { cards = { card, ... }, level, at, partial, hidden = n,
--                  data = "classic" | "live" | "none" }
--       card = {
--         id         "dungeon:shadowfang", "zone:1431", "attune:mc", ...
--         kind       dungeon, attune, turnin, logzone, zone, chain (and the
--                    kinds plugins add: goal, rare, rep, event, train)
--         title, subtitle   finished text
--         score      0-100 (one decimal)
--         factors    { kindWeight, levelFit, groupFit, readiness, proximity, freshness }
--         bonuses    { { key, value }, ... }
--         reasons    up to three finished "why" lines, biggest first
--         why        every reason line; whyNot: the factors below 1.0
--         provenance "classic" | "forever" | "seen" | "live" | "game"
--         dataLabel  "Classic values; Forever may differ." and the like
--         level      { min, max } of the place or quests
--         uiMapID, zone, point (a map point for the Map action)
--         quests     quest ids the card is about
--         actions    { { key, label, ... }, ... }  see N:Act
--       }
--   J:NextTop(opts)           the first card, or nil
--   J:NextCard(id)            a card of the last result by id
--   J:TripPlan(card)          before you go, on the way, access, inside,
--                             getting there, afterwards (dungeon cards)
--   J:PrepChecklist()         bag space, repairs, food and water, ammo and
--                             the hearthstone: what you have, never bought
--   J:NotNow(id), J:ClearNotNow(id), J:IsNotNow(id)
--                             put a card away until your next level or 24 h
--   J:MuteNextKind(kind[, on]) a kind stays out for this session
--   J:NextAct(card, key)      run one of the card's actions (a click)
--   J:RegisterNextSource(kind, fn)  plugins and other files add candidates:
--                             fn(ctx, N) returns cards built with N.Card
--                             (scored with N.Score unless they carry a score);
--                             J:UnregisterNextSource(kind, fn) removes one
--   J:NextWeights()           the kind weights of the current preset
--
-- Inputs, all game-provided or our own static data: level, XP and rested
-- XP; the party size and plain party levels; the quest log; quest data
-- (LG:JourneyQuests and LG:JourneyQuest: EldoUI_LootData <- the Forever
-- overlay <- what you saw); dungeons (LG:Catalog, LG:FitsLevel, access);
-- upgrades (LG:BestInstance, only when the Loot Guide already ranked your
-- gear); your runs (E.Instances); attunements (EldoUI.Attunements); zone
-- ranges (C_Map.GetMapLevels, else Data/Zones.lua); where you are
-- (C_Map.GetBestMapForUnit: nil inside instances, so distance is neutral
-- there). Never: the combat log, secret values, other players' data beyond
-- the plain party roster.
--
-- Score = 100 x kindWeight x levelFit x groupFit x readiness x proximity
-- x freshness + bonuses, capped at 100. Ties break on
-- fewer travel steps (nearer first), then the lower level, then the name.
-- It runs out of combat, at most once a second, when its inputs change,
-- and only when a page or the tracker asks.
local _, E = ...
local L = E.L
local Key = E.Key
local A = E.Adventure
local J = E.Journal
local LG = E.LootGuide

local Plain = A.Plain
local floor, max, min, abs = math.floor, math.max, math.min, math.abs

local N = {}
A.Next = N

---------------------------------------------------------------------------
-- Static facts (EldoUI's own, public game knowledge; Classic values)
---------------------------------------------------------------------------
-- Zones of the original game: uiMapID -> { area (the quest data's zone id),
-- name (English, only when the client gives none), continent uiMapID }.
local EK, KALIMDOR = 1415, 1414
local ZONES = {
	[1429] = { 12, "Elwynn Forest", EK }, [1426] = { 1, "Dun Morogh", EK }, [1420] = { 85, "Tirisfal Glades", EK },
	[1436] = { 40, "Westfall", EK }, [1432] = { 38, "Loch Modan", EK }, [1421] = { 130, "Silverpine Forest", EK },
	[1433] = { 44, "Redridge Mountains", EK }, [1431] = { 10, "Duskwood", EK }, [1437] = { 11, "Wetlands", EK },
	[1424] = { 267, "Hillsbrad Foothills", EK }, [1416] = { 36, "Alterac Mountains", EK }, [1417] = { 45, "Arathi Highlands", EK },
	[1434] = { 33, "Stranglethorn Vale", EK }, [1418] = { 3, "Badlands", EK }, [1435] = { 8, "Swamp of Sorrows", EK },
	[1425] = { 47, "The Hinterlands", EK }, [1427] = { 51, "Searing Gorge", EK }, [1419] = { 4, "Blasted Lands", EK },
	[1428] = { 46, "Burning Steppes", EK }, [1422] = { 28, "Western Plaguelands", EK }, [1423] = { 139, "Eastern Plaguelands", EK },
	[1430] = { 41, "Deadwind Pass", EK }, [1453] = { 1519, "Stormwind City", EK }, [1455] = { 1537, "Ironforge", EK },
	[1458] = { 1497, "Undercity", EK },
	[1411] = { 14, "Durotar", KALIMDOR }, [1412] = { 215, "Mulgore", KALIMDOR }, [1438] = { 141, "Teldrassil", KALIMDOR },
	[1439] = { 148, "Darkshore", KALIMDOR }, [1413] = { 17, "The Barrens", KALIMDOR }, [1442] = { 406, "Stonetalon Mountains", KALIMDOR },
	[1440] = { 331, "Ashenvale", KALIMDOR }, [1441] = { 400, "Thousand Needles", KALIMDOR }, [1443] = { 405, "Desolace", KALIMDOR },
	[1445] = { 15, "Dustwallow Marsh", KALIMDOR }, [1444] = { 357, "Feralas", KALIMDOR }, [1446] = { 440, "Tanaris", KALIMDOR },
	[1447] = { 16, "Azshara", KALIMDOR }, [1448] = { 361, "Felwood", KALIMDOR }, [1449] = { 490, "Un'Goro Crater", KALIMDOR },
	[1452] = { 618, "Winterspring", KALIMDOR }, [1451] = { 1377, "Silithus", KALIMDOR }, [1450] = { 493, "Moonglade", KALIMDOR },
	[1454] = { 1637, "Orgrimmar", KALIMDOR }, [1456] = { 1638, "Thunder Bluff", KALIMDOR }, [1457] = { 1657, "Darnassus", KALIMDOR },
}
-- Starting areas the quest data files under their own id.
local SUBAREAS = { [9] = 1429, [132] = 1426, [154] = 1420, [363] = 1411, [220] = 1412, [188] = 1438 }
local AREA_TO_MAP = {}
for uiMapID, row in pairs(ZONES) do AREA_TO_MAP[row[1]] = uiMapID end
for area, uiMapID in pairs(SUBAREAS) do AREA_TO_MAP[area] = uiMapID end
N.ZONES, N.AREA_TO_MAP = ZONES, AREA_TO_MAP

-- Kind weights and the "Suggestions lean to" presets.
local KIND_WEIGHT = {
	turnin = 1.0, attune = 0.9, dungeon = 0.85, chain = 0.8, logzone = 0.75, zone = 0.6, goal = 0.6,
	train = 0.7, rep = 0.5, rare = 0.5, event = 0.5,
}
local PRESET_SCALE = {
	balanced = {},
	leveling = { zone = 1.3, chain = 1.2, logzone = 1.2, dungeon = 0.85, attune = 0.85 },
	dungeons = { dungeon = 1.15, attune = 1.1, zone = 0.8, chain = 0.9 },
	collecting = { rep = 1.5, rare = 1.5, goal = 1.4, zone = 0.85, dungeon = 0.9 },
}
N.KIND_WEIGHT, N.PRESET_SCALE = KIND_WEIGHT, PRESET_SCALE

-- How a quest of each color counts for you (the game's color bands).
local FIT_FACTOR = { gray = 0.2, green = 0.8, yellow = 1.0, orange = 0.7, red = 0.3 }
N.FIT_FACTOR = FIT_FACTOR

local KIND_ORDER = { "turnin", "attune", "dungeon", "chain", "logzone", "zone", "goal", "train", "rep", "rare", "event" }
N.KINDS = KIND_ORDER

local NOT_NOW_SECONDS = 86400
local THROTTLE = 1
local HEARTHSTONE = 6948

---------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------
local function Num(value)
	value = Plain(value)
	return type(value) == "number" and value or nil
end

local function Results(ok, ...)
	if not ok then return nil end
	return ...
end

local function Call(fn, ...)
	if type(fn) ~= "function" then return nil end
	return Results(pcall(fn, ...))
end

local function Grammar()
	return E.Story and E.Story.Grammar or nil
end

-- "in Duskwood", "in the Barrens": the grammar layer when it is there.
local function InPlace(name)
	local G = Grammar()
	if G and G.Place then
		local text = G.Place(name, "in", true)
		if type(text) == "string" and text ~= "" then return text end
	end
	if E:GetLanguage() == "enUS" then return ("in %s"):format(name) end
	return (L["in %s (place)"]):format(name)
end
N.InPlace = InPlace

-- "A, B, and C" (serial comma).
local function List(items)
	local G = Grammar()
	if G and G.List then
		local text = G.List(items)
		if type(text) == "string" then return text end
	end
	local n = #items
	if n == 0 then return "" end
	if n == 1 then return items[1] end
	if n == 2 then return (L["%s and %s"]):format(items[1], items[2]) end
	return (L["%s, and %s"]):format(table.concat(items, ", ", 1, n - 1), items[n])
end
N.List = List

local function Settings()
	return A.db or A.defaults
end

local function ZoneName(uiMapID)
	if not uiMapID then return nil end
	local name = LG.MapName and LG:MapName(uiMapID)
	if type(name) == "string" and name ~= "" then return name end
	local row = ZONES[uiMapID]
	return row and row[2] or nil
end
N.ZoneName = ZoneName

-- The continent of a zone map: our table, else the game's parent chain.
local function Continent(uiMapID)
	if not uiMapID then return nil end
	local row = ZONES[uiMapID]
	if row then return row[3] end
	local cursor = uiMapID
	for _ = 1, 6 do
		local info = C_Map and Call(C_Map.GetMapInfo, cursor)
		if type(info) ~= "table" then return nil end
		local kind, parent = Num(info.mapType), Num(info.parentMapID)
		if kind == 2 then return cursor end
		if not parent or parent == 0 then return nil end
		cursor = parent
	end
	return nil
end
N.Continent = Continent

-- A zone's level range: the game's first, else Data/Zones.lua (one reader
-- for the world map, Zone Info and this page).
local function ZoneRange(uiMapID)
	return E:ZoneLevelRange(uiMapID)
end
N.ZoneRange = ZoneRange

local function ZoneFaction(uiMapID)
	local zone = E.zoneData and E.zoneData.zones and E.zoneData.zones[uiMapID]
	return zone and zone.faction or nil
end

-- The zone a quest belongs to (uiMapID): what you saw, the overlay, the
-- data's zone id.
local function QuestZone(quest)
	if type(quest) ~= "table" then return nil end
	if quest.giver and quest.giver.map then return quest.giver.map end
	if quest.map then return quest.map end
	return quest.zoneOrSort and AREA_TO_MAP[quest.zoneOrSort] or nil
end
N.QuestZone = QuestZone

-- A map point for a quest's giver (or ender): seen or overlay position,
-- else the data's spawn camp. Out of combat only (map math).
local function PlacePoint(place, list)
	if type(place) == "table" and place.map and place.x and place.y then
		return { uiMapID = place.map, x = place.x, y = place.y }
	end
	local first = type(list) == "table" and list[1]
	if not first or first.kind == "item" or InCombatLockdown() then return nil end
	local camps = LG:SpawnPoints(first.kind, first.id)
	return camps[1] and LG:PointFor(camps[1]) or nil
end
function N.GiverPoint(quest) return quest and PlacePoint(quest.giver, quest.starts) or nil end
function N.EnderPoint(quest) return quest and PlacePoint(quest.ender, quest.ends) or nil end

local function NpcName(place)
	if type(place) ~= "table" then return nil end
	if place.name then return place.name end
	local mob = place.npc and LG.Mob and LG:Mob(place.npc)
	return mob and mob.name or nil
end

local function QuestTitle(id, quest)
	return (quest and quest.title) or LG:QuestTitle(id) or ("#" .. tostring(id))
end

local DATA_LABEL = {
	classic = Key("Classic values; Forever may differ."),
	forever = Key("New in Forever."),
	seen = Key("Seen by you."),
	live = Key("From the game's dungeon finder."),
	game = Key("From the game."),
}
N.DATA_LABEL = DATA_LABEL

---------------------------------------------------------------------------
-- Context: everything one ranking reads, built once per rebuild
---------------------------------------------------------------------------
local GROUP_CHIP = { solo = 1, small = 3, full = 5, raid = 20 }
N.GROUP_CHIP = GROUP_CHIP

local function ReadLog()
	local log = { list = {}, byID = {}, byHeader = {}, headers = {} }
	local QL = C_QuestLog
	if not (QL and QL.GetNumQuestLogEntries and QL.GetInfo) then return log end
	local count = Num(Call(QL.GetNumQuestLogEntries)) or 0
	local header
	for index = 1, count do
		local info = Call(QL.GetInfo, index)
		if type(info) == "table" then
			local title = Plain(info.title)
			if Plain(info.isHeader) then
				header = type(title) == "string" and title or nil
				if header and not log.byHeader[header] then
					log.byHeader[header] = {}
					log.headers[#log.headers + 1] = header
				end
			else
				local id = Num(info.questID)
				if id and id > 0 then
					local ready = Call(QL.ReadyForTurnIn, id) or Call(QL.IsComplete, id)
					local row = { id = id, title = type(title) == "string" and title or nil, header = header,
						level = Num(info.level), ready = Plain(ready) and true or false, index = index }
					log.list[#log.list + 1] = row
					log.byID[id] = row
					if header then table.insert(log.byHeader[header], row) end
				end
			end
		end
	end
	return log
end

local function PartyLevels()
	local levels, total, count = {}, 0, 0
	local mine = Num(UnitLevel("player"))
	if mine then total, count = mine, 1 end
	for index = 1, 4 do
		local unit = "party" .. index
		if Plain(UnitExists(unit)) then
			local level = Num(UnitLevel(unit))
			if level and level > 0 then
				levels[#levels + 1] = level
				total, count = total + level, count + 1
			end
		end
	end
	return levels, count > 0 and floor(total / count + 0.5) or nil
end

function N:Context(opts)
	opts = opts or {}
	local player = LG:Player()
	local db = Settings()
	local ctx = { opts = opts, db = db, player = player, now = time(), charKey = E.charKey }
	ctx.level = Num(UnitLevel("player")) or player.level or 1
	ctx.faction = player.faction
	ctx.xp, ctx.xpMax = Num(UnitXP("player")), Num(UnitXPMax("player"))
	ctx.rested = Num(GetXPExhaustion and GetXPExhaustion()) or 0
	ctx.maxLevel = Num(GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion()) or 60
	-- The group: the chip when set, else the party right now.
	local inGroup = Plain(IsInGroup and IsInGroup())
	local size = inGroup and Num(GetNumGroupMembers and GetNumGroupMembers()) or 1
	ctx.liveGroup = max(size or 1, 1)
	ctx.chip = GROUP_CHIP[opts.group] and opts.group or nil
	ctx.groupSize = ctx.chip and GROUP_CHIP[ctx.chip] or ctx.liveGroup
	ctx.inRaid = ctx.chip == "raid" or (not ctx.chip and Plain(IsInRaid and IsInRaid()) and true or false)
	ctx.partyLevels, ctx.groupLevel = PartyLevels()
	if ctx.chip or ctx.liveGroup <= 1 then ctx.groupLevel = ctx.level end
	ctx.minutes = tonumber(opts.minutes)
	-- Where you are: nil inside an instance (distance is neutral there).
	local inside = Plain(IsInInstance and IsInInstance())
	ctx.inInstance = inside and true or false
	if inside then
		local _, _, _, _, _, _, _, instanceID = Call(GetInstanceInfo)
		instanceID = Num(instanceID)
		ctx.instanceKey = instanceID and LG.InstanceForPlayer and LG:InstanceForPlayer(instanceID) or nil
	else
		ctx.map = Num(C_Map and C_Map.GetBestMapForUnit and Call(C_Map.GetBestMapForUnit, "player"))
		ctx.continent = Continent(ctx.map)
	end
	ctx.log = ReadLog()
	ctx.hasData = LG:HasData()
	ctx.pickupCap = tonumber(db.pickupCap) or 2
	ctx.weights = N:Weights(db.nextWeights)
	return ctx
end

function N:Weights(preset)
	local scale = PRESET_SCALE[preset or Settings().nextWeights] or PRESET_SCALE.balanced
	local out = {}
	for kind, weight in pairs(KIND_WEIGHT) do out[kind] = weight * (scale[kind] or 1) end
	return out
end

---------------------------------------------------------------------------
-- Factors
---------------------------------------------------------------------------
-- 1.0 inside the band, 0.2 less per level outside, 0 past the window + 1.
function N.LevelFit(low, high, level)
	if not (low and high and level) then return 0.7 end
	if level >= low and level <= high then return 1 end
	local distance = level < low and (low - level) or (level - high)
	local window = tonumber(LG.db and LG.db.levelWindow) or 3
	if distance > window then return 0 end
	return max(0, 1 - 0.2 * distance)
end

-- Players a trip needs against the group you have.
function N.GroupFit(need, ctx, elite)
	need = need or 1
	local have = ctx.groupSize or 1
	if need <= 1 then
		if elite and have <= 1 then return 0.6 end
		return 1
	end
	if need <= 5 then
		if have >= 3 then return 1 end
		if have == 2 then return 0.8 end
		return 0.55
	end
	if ctx.inRaid or have >= 10 then return 1 end
	return 0.25
end

function N.Proximity(uiMapID, ctx, instanceKey)
	if ctx.inInstance then
		if instanceKey and instanceKey == ctx.instanceKey then return 1 end
		return 0.7
	end
	if not (uiMapID and ctx.map) then return 0.7 end
	if uiMapID == ctx.map then return 1 end
	local continent = Continent(uiMapID)
	if not (continent and ctx.continent) then return 0.7 end
	if continent == ctx.continent then return 0.75 end
	return 0.5
end

-- Your recorded runs of an instance: total, at this level, median minutes.
local function Runs(info, ctx)
	local I = E.Instances
	if not (I and I.Store and info and info.map) then return nil end
	local records = I.active or (Settings().useStores and true) or false
	if not records then return nil end
	local ok, store = pcall(I.Store, I)
	if not ok or type(store) ~= "table" or type(store.runs) ~= "table" then return nil end
	local me = I.CharKey and I:CharKey()
	local total, atLevel, times = 0, 0, {}
	for _, run in ipairs(store.runs) do
		if run.char == me and run.instanceID == info.map then
			total = total + 1
			if run.enterLevel == ctx.level then atLevel = atLevel + 1 end
			if run.enter and run.leave and run.leave > run.enter then times[#times + 1] = run.leave - run.enter end
		end
	end
	table.sort(times)
	local median = times[1] and times[floor((#times + 1) / 2)] or nil
	return { total = total, atLevel = atLevel, median = median }
end
N.Runs = Runs

---------------------------------------------------------------------------
-- Cards and the score
---------------------------------------------------------------------------
function N.Card(kind, id, title)
	return {
		id = kind .. ":" .. tostring(id), kind = kind, key = id, title = title,
		factors = { kindWeight = 1, levelFit = 1, groupFit = 1, readiness = 1, proximity = 1, freshness = 1 },
		bonuses = {}, why = {}, whyNot = {}, reasons = {}, actions = {}, quests = {}, provenance = "classic",
	}
end

-- A reason line: weight orders them (the biggest first).
function N.Reason(card, key, text, weight)
	if type(text) ~= "string" or text == "" then return end
	card.why[#card.why + 1] = { key = key, text = text, weight = weight or 1 }
end

-- A factor below 1.0 (for "Why not higher?").
function N.Penalty(card, key, text)
	if type(text) ~= "string" or text == "" then return end
	card.whyNot[#card.whyNot + 1] = { key = key, text = text }
end

function N.Bonus(card, key, value, text, weight)
	if not value or value <= 0 then return end
	card.bonuses[#card.bonuses + 1] = { key = key, value = value }
	if text then N.Reason(card, key, text, weight or value) end
end

-- Can something run this action now? "Set as goal" needs the goals file.
function N.Runnable(action)
	if action.key == "goal" then return type(J.AddGoal) == "function" end
	if action.key == "map" then return type(action.point) == "table" end
	return true
end

function N.Action(card, key, fields)
	local action = fields or {}
	action.key = key
	card.actions[#card.actions + 1] = action
	return action
end

local ACTION_LABEL = {
	map = Key("Map"), open = Key("Open"), track = Key("Track"), group = Key("Find a group"), copy = Key("Copy group line"),
	goal = Key("Set as goal"), notnow = Key("Not now"),
}
N.ACTION_LABEL = ACTION_LABEL

function N.Score(card, ctx)
	local f = card.factors
	f.kindWeight = (ctx.weights and ctx.weights[card.kind]) or KIND_WEIGHT[card.kind] or 0.5
	local product = 100 * f.kindWeight * f.levelFit * f.groupFit * f.readiness * f.proximity * f.freshness
	local bonus = 0
	for _, b in ipairs(card.bonuses) do bonus = bonus + b.value end
	if f.readiness <= 0 or f.levelFit <= 0 then
		card.score = 0
	else
		card.score = floor(min(100, product + bonus) * 10 + 0.5) / 10
	end
	table.sort(card.why, function(a, b)
		if a.weight ~= b.weight then return a.weight > b.weight end
		return a.text < b.text
	end)
	wipe(card.reasons)
	for index = 1, min(3, #card.why) do card.reasons[index] = card.why[index].text end
	card.dataLabel = DATA_LABEL[card.provenance]
	-- No dead buttons: an action only while something can run it.
	for index = #card.actions, 1, -1 do
		if not N.Runnable(card.actions[index]) then table.remove(card.actions, index) end
	end
	if not card.actions[1] or card.actions[#card.actions].key ~= "notnow" then N.Action(card, "notnow") end
	for _, action in ipairs(card.actions) do action.label = action.label or ACTION_LABEL[action.key] end
	return card.score
end

---------------------------------------------------------------------------
-- Candidates: turn-ins and the quest log
---------------------------------------------------------------------------
local builders = {}
N.builders = builders

local function LogRecord(row)
	return LG:JourneyQuest(row.id)
end

builders.turnin = function(ctx)
	local groups, order = {}, {}
	for _, row in ipairs(ctx.log.list) do
		if row.ready then
			local quest = LogRecord(row)
			local point = quest and N.EnderPoint(quest)
			local where = (point and ZoneName(point.uiMapID)) or row.header or L["your quest log"]
			local group = groups[where]
			if not group then
				group = { where = where, uiMapID = point and point.uiMapID, rows = {}, point = point,
					ender = quest and NpcName(quest.ender), provenance = quest and quest.provenance or "game" }
				groups[where] = group
				order[#order + 1] = where
			end
			group.rows[#group.rows + 1] = row
		end
	end
	local cards = {}
	for _, where in ipairs(order) do
		local group = groups[where]
		local n = #group.rows
		local card = N.Card("turnin", where, E:Plural(n, "%d quest to hand in", "%d quests to hand in"):format(n))
		card.subtitle = group.uiMapID and InPlace(where) or where
		card.uiMapID, card.zone, card.point, card.provenance = group.uiMapID, group.uiMapID and where or nil, group.point, group.provenance
		for _, row in ipairs(group.rows) do card.quests[#card.quests + 1] = row.id end
		card.factors.proximity = N.Proximity(group.uiMapID, ctx)
		local names = {}
		for index = 1, min(3, n) do names[index] = group.rows[index].title or QuestTitle(group.rows[index].id) end
		if group.uiMapID then
			N.Reason(card, "turnin", E:Plural(n, "Ready to hand in: %d quest %s.", "Ready to hand in: %d quests %s."):format(n, InPlace(where)), 60)
		else
			N.Reason(card, "turnin", E:Plural(n, "Ready to hand in: %d quest.", "Ready to hand in: %d quests."):format(n), 60)
		end
		N.Reason(card, "names", List(names) .. ".", 20)
		if card.factors.proximity < 1 and group.uiMapID then
			N.Penalty(card, "proximity", (L["The quest givers are %s."]):format(InPlace(where)))
		end
		if group.point then N.Action(card, "map", { point = group.point, title = group.ender or card.title }) end
		N.Action(card, "open", { address = J:Address("section", "quests") })
		cards[#cards + 1] = card
	end
	return cards
end

builders.logzone = function(ctx)
	local cards = {}
	for _, header in ipairs(ctx.log.headers) do
		local open, fitSum = {}, 0
		local uiMapID, point
		for _, row in ipairs(ctx.log.byHeader[header]) do
			if not row.ready then
				open[#open + 1] = row
				local quest = LogRecord(row)
				local level = row.level or (quest and quest.level)
				fitSum = fitSum + FIT_FACTOR[LG:QuestFit(level, ctx.level)]
				uiMapID = uiMapID or QuestZone(quest)
				point = point or (quest and N.GiverPoint(quest))
			end
		end
		local n = #open
		if n > 0 then
			-- The log header names the zone; our zone table finds its map.
			if not uiMapID then
				for id, row in pairs(ZONES) do
					if row[2] == header or ZoneName(id) == header then uiMapID = id break end
				end
			end
			local card = N.Card("logzone", header, (L["Quests %s"]):format(InPlace(header)))
			card.subtitle = E:Plural(n, "%d quest in your log", "%d quests in your log"):format(n)
			card.uiMapID, card.zone, card.provenance = uiMapID, header, "game"
			for _, row in ipairs(open) do card.quests[#card.quests + 1] = row.id end
			card.factors.levelFit = fitSum / n
			card.factors.proximity = N.Proximity(uiMapID, ctx)
			N.Reason(card, "logzone", E:Plural(n, "You have %d quest %s in your log.", "You have %d quests %s in your log."):format(n, InPlace(header)), 30 + n)
			if card.factors.levelFit < 0.75 then N.Penalty(card, "levelFit", L["Some of these quests are far from your level."]) end
			if card.factors.proximity < 1 and uiMapID then N.Penalty(card, "proximity", (L["You are not %s."]):format(InPlace(header))) end
			if point then N.Action(card, "map", { point = point, title = card.title }) end
			N.Action(card, "track", { quests = card.quests })
			cards[#cards + 1] = card
		end
	end
	return cards
end

---------------------------------------------------------------------------
-- Candidates: zones and chains (from the quests that fit you)
---------------------------------------------------------------------------
local function Fitting(ctx)
	if ctx.fitting then return ctx.fitting end
	local list = LG:JourneyQuests({ above = ctx.pickupCap })
	local out = {}
	for _, row in ipairs(list) do
		if row.status == "available" and not ctx.log.byID[row.id] then out[#out + 1] = row end
	end
	ctx.fitting = out
	return out
end
N.Fitting = Fitting

builders.zone = function(ctx)
	local zones, order = {}, {}
	for _, row in ipairs(Fitting(ctx)) do
		local uiMapID = QuestZone(row.quest)
		if uiMapID then
			local zone = zones[uiMapID]
			if not zone then
				zone = { uiMapID = uiMapID, rows = {}, new = 0, fit = 0 }
				zones[uiMapID] = zone
				order[#order + 1] = uiMapID
			end
			zone.rows[#zone.rows + 1] = row
			zone.fit = zone.fit + FIT_FACTOR[row.fit]
			if row.quest.provenance == "forever" then zone.new = zone.new + 1 end
		end
	end
	local cards = {}
	for _, uiMapID in ipairs(order) do
		local zone = zones[uiMapID]
		local faction = ZoneFaction(uiMapID)
		local hostile = faction and faction ~= "contested" and faction ~= "sanctuary" and ctx.faction and faction ~= ctx.faction
		local n = #zone.rows
		local name = ZoneName(uiMapID)
		-- One quest is worth a card only where you stand.
		if name and not hostile and (n >= 2 or uiMapID == ctx.map) then
			local card = N.Card("zone", uiMapID, name)
			card.uiMapID, card.zone = uiMapID, name
			card.subtitle = E:Plural(n, "%d quest for you", "%d quests for you"):format(n)
			card.provenance = zone.new > 0 and "forever" or "classic"
			local low, high, rangeFrom = ZoneRange(uiMapID)
			card.level = low and { min = low, max = high } or nil
			-- A city has no level range: its quests alone decide, a little lower.
			local bandFit = low and N.LevelFit(low, high, ctx.level) or 0.8
			card.factors.levelFit = (zone.fit / n) * 0.5 + bandFit * 0.5
			card.factors.proximity = N.Proximity(uiMapID, ctx)
			if rangeFrom == "game" then card.provenance = zone.new > 0 and "forever" or "game" end
			for index = 1, min(n, 10) do card.quests[index] = zone.rows[index].id end
			N.Reason(card, "zone", E:Plural(n, "%d quest you can pick up %s.", "%d quests you can pick up %s."):format(n, InPlace(name)), 20 + min(n, 20))
			if low then
				if bandFit >= 1 then
					N.Reason(card, "levelFit", (L["Fits your level (%d; the zone is %d-%d)."]):format(ctx.level, low, high), 25)
				else
					N.Penalty(card, "levelFit", (L["The zone is %d-%d; you are level %d."]):format(low, high, ctx.level))
				end
			end
			-- More to do there counts: up to +12 for a dozen quests.
			N.Bonus(card, "quests", min(12, n))
			if zone.new > 0 then N.Reason(card, "forever", E:Plural(zone.new, "%d of them is new in Forever.", "%d of them are new in Forever."):format(zone.new), 5) end
			if card.factors.proximity < 1 then
				N.Penalty(card, "proximity", card.factors.proximity <= 0.5 and L["It is on another continent."] or L["It is a trip from here."])
			else
				N.Reason(card, "here", L["You are here."], 12)
			end
			local rest = ctx.xpMax and ctx.xpMax > 0 and ctx.rested / ctx.xpMax or 0
			if rest > 0.3 then N.Bonus(card, "rested", 5, (L["Rested (%d%%): a good time for questing."]):format(floor(rest * 100)), 5) end
			local giver = N.GiverPoint(zone.rows[1].quest)
			if giver then N.Action(card, "map", { point = giver, title = QuestTitle(zone.rows[1].id, zone.rows[1].quest) }) end
			N.Action(card, "open", { address = J:Address("place", uiMapID) })
			N.Action(card, "goal", { goal = { kind = "zone", target = uiMapID } })
			cards[#cards + 1] = card
		end
	end
	return cards
end

builders.chain = function(ctx)
	local cards, seenRoot = {}, {}
	for _, row in ipairs(Fitting(ctx)) do
		local quest = row.quest
		local prev = quest.allOf and quest.allOf[1]
		if quest.full and prev and prev > 0 and LG:QuestDone(prev) then
			local chain = LG:QuestChain(row.id)
			local root = chain[1] and chain[1].id or row.id
			if not seenRoot[root] and #chain >= 2 then
				seenRoot[root] = true
				local part
				for index, step in ipairs(chain) do if step.id == row.id then part = index end end
				local rootTitle = QuestTitle(root)
				local card = N.Card("chain", root, (L["Continue: %s"]):format(rootTitle))
				card.subtitle = (L["Part %d of %d: %s"]):format(part or 1, #chain, QuestTitle(row.id, quest))
				card.quests = { row.id }
				card.provenance = quest.provenance
				local uiMapID = QuestZone(quest)
				card.uiMapID, card.zone = uiMapID, ZoneName(uiMapID)
				card.level = quest.level and { min = quest.level, max = quest.level } or nil
				card.factors.levelFit = FIT_FACTOR[row.fit]
				card.factors.proximity = N.Proximity(uiMapID, ctx)
				N.Reason(card, "chain", (L["You finished %s; the next part is waiting."]):format(QuestTitle(prev)), 35)
				if row.fit == "yellow" or row.fit == "green" then
					N.Reason(card, "levelFit", (L["Fits your level (quest level %d)."]):format(quest.level or ctx.level), 15)
				else
					N.Penalty(card, "levelFit", (L["A little high for you: a level %d quest."]):format(quest.level or ctx.level))
				end
				if card.factors.proximity < 1 and card.zone then N.Penalty(card, "proximity", (L["The quest giver is %s."]):format(InPlace(card.zone))) end
				local giver = N.GiverPoint(quest)
				if giver then N.Action(card, "map", { point = giver, title = QuestTitle(row.id, quest) }) end
				N.Action(card, "open", { address = J:Address("quest", row.id) })
				N.Action(card, "goal", { goal = { kind = "chain", target = root } })
				cards[#cards + 1] = card
			end
		end
	end
	return cards
end

---------------------------------------------------------------------------
-- Candidates: dungeons (with their prep quests)
---------------------------------------------------------------------------
-- The instances behind a hostile capital's gate (the Stockade, Ragefire
-- Chasm): from Data/Zones.lua, the entrance zones that are cities.
local citySide
local function CitySide(info)
	if not citySide then
		citySide = {}
		local Z = E.zoneData
		for _, zone in pairs(Z and Z.zones or {}) do
			if not zone.min and (zone.faction == "Alliance" or zone.faction == "Horde") then
				for _, key in ipairs(zone.instances or {}) do
					local inst = Z.instances[key]
					if inst and inst.map then citySide[inst.map] = zone.faction end
				end
			end
		end
	end
	return info and info.map and citySide[info.map] or nil
end

-- The entrance zone of an instance (uiMapID): Data/Zones.lua, else the
-- client's entrance list.
local entranceZone
local function InstanceZone(info)
	if not entranceZone then
		entranceZone = {}
		local Z = E.zoneData
		for uiMapID, zone in pairs(Z and Z.zones or {}) do
			for _, key in ipairs(zone.instances or {}) do
				local inst = Z.instances[key]
				if inst and inst.map and not entranceZone[inst.map] then entranceZone[inst.map] = uiMapID end
			end
		end
	end
	local uiMapID = info and info.map and entranceZone[info.map]
	if uiMapID then return uiMapID end
	local point = info and not InCombatLockdown() and LG:EntrancePoint(info.key)
	return point and point.uiMapID or nil
end
N.InstanceZone = InstanceZone
N.CitySide = CitySide

-- Raid lockouts the game reports (plain values only).
local function LockedOut(info)
	if not (GetNumSavedInstances and GetSavedInstanceInfo and info and info.kind == "raid") then return false end
	local count = Num(Call(GetNumSavedInstances)) or 0
	for index = 1, count do
		local name, _, reset, _, locked = Call(GetSavedInstanceInfo, index)
		name, reset, locked = Plain(name), Num(reset), Plain(locked)
		if locked and type(name) == "string" and (name == info.name or name == info.groupName) and (reset or 1) > 0 then return true end
	end
	return false
end

local function InstanceUpgrades(ctx)
	if ctx.upgrades ~= nil then return ctx.upgrades end
	ctx.upgrades = false
	if LG.BestInstance then
		local ok, key, _, items = pcall(LG.BestInstance, LG)
		if ok and key and type(items) == "table" then ctx.upgrades = { key = key, items = items } end
	end
	return ctx.upgrades
end

-- The first open attunement step inside each instance: { [key] = { entry, step } },
-- built once per ranking.
local function AttuneSteps()
	local out = {}
	local AT = E.Attunements
	if not (AT and AT.Running and AT:Running()) then return out end
	for _, entryKey in ipairs(AT:List()) do
		for _, step in ipairs(AT:NextSteps(entryKey)) do
			local place = AT:StepPlace(step)
			if place and place.instance and not out[place.instance] then out[place.instance] = { entryKey, step } end
		end
	end
	return out
end

local function AttuneInside(key, ctx)
	local steps
	if ctx then
		ctx.attuneSteps = ctx.attuneSteps or AttuneSteps()
		steps = ctx.attuneSteps
	else
		steps = AttuneSteps()
	end
	local hit = steps[key]
	if hit then return hit[1], hit[2] end
	return nil
end
N.AttuneInside = AttuneInside

-- Prep quests of a dungeon: to pick up first, already in your log, done.
function N.Prep(key)
	local prep = { pickup = {}, inLog = {}, ready = {} }
	if not LG.InstanceQuests then return prep end
	for _, row in ipairs(LG:InstanceQuests(key)) do
		if not LG:IsQuestRemoved(row.id) then
			if row.status == "available" then
				prep.pickup[#prep.pickup + 1] = row
			elseif row.status == "active" then
				prep.inLog[#prep.inLog + 1] = row
			elseif row.status == "turnin" then
				prep.ready[#prep.ready + 1] = row
			end
		end
	end
	return prep
end

builders.dungeon = function(ctx)
	local cards = {}
	local raids = Settings().nextRaids
	local level = ctx.groupLevel or ctx.level
	for _, info in ipairs(LG:Catalog()) do
		local raid = info.kind == "raid"
		local side = CitySide(info)
		local usable = info.min and info.max and not info.world and LG:OpenNow(info)
			and (raids or not raid) and not (side and ctx.faction and side ~= ctx.faction)
		local fit = usable and LG:FitsLevel(info, level)
		if fit == "fit" or fit == "near" then
			local card = N.Card("dungeon", info.key, info.name)
			local size = info.size or 5
			card.level = { min = info.min, max = info.max }
			if raid then
				card.subtitle = (L["%d-%d, raid of %d"]):format(info.min, info.max, size) -- no-plural: a raid size, no noun
			else
				card.subtitle = E:Plural(size, "%d-%d, %d player", "%d-%d, %d players"):format(info.min, info.max, size)
			end
			card.provenance = (info.status == "forever" or info.status == "live") and (ctx.hasData and "forever" or "live") or "classic"
			local uiMapID = InstanceZone(info)
			card.uiMapID, card.zone = uiMapID, ZoneName(uiMapID)
			local f = card.factors
			f.levelFit = N.LevelFit(info.min, info.max, level)
			f.groupFit = N.GroupFit(size, ctx)
			f.proximity = N.Proximity(uiMapID, ctx, info.key)
			if f.levelFit >= 1 then
				N.Reason(card, "levelFit", (L["Fits your level (%d; the dungeon is %d-%d)."]):format(level, info.min, info.max), 30)
			elseif level < info.min then
				N.Penalty(card, "levelFit", (L["A little high for you: it starts at level %d."]):format(info.min))
			else
				N.Penalty(card, "levelFit", (L["A little low for you: it is %d-%d."]):format(info.min, info.max))
			end
			if f.groupFit < 1 then
				if raid then
					N.Penalty(card, "groupFit", (L["You are not in a raid group; this is a raid of %d."]):format(size))
				elseif (ctx.groupSize or 1) <= 1 then
					N.Penalty(card, "groupFit", (L["You are on your own; this is a %d-player dungeon."]):format(size))
				else
					N.Penalty(card, "groupFit", (L["Your group is small for a %d-player dungeon."]):format(size))
				end
			end
			if f.proximity < 1 and card.zone then N.Penalty(card, "proximity", (L["The entrance is %s."]):format(InPlace(card.zone))) end
			-- Readiness: the level the door asks, a lockout, prep quests.
			local enter = info.enterLevel or (info.access and info.access.level)
			local data = LG:Instance(info.key)
			enter = enter or (data and data.access and data.access.level)
			local prep = N.Prep(info.key)
			card.prep = prep
			if LockedOut(info) then
				f.readiness = 0
				N.Penalty(card, "readiness", L["You are saved to it until the reset."])
			elseif enter and ctx.level < enter then
				f.readiness = 0.3
				N.Penalty(card, "readiness", (L["The door opens at level %d."]):format(enter))
			elseif #prep.pickup > 0 then
				f.readiness = 0.8
				local first = prep.pickup[1]
				local quest = LG:JourneyQuest(first.id)
				local giver = quest and NpcName(quest.giver or (quest.starts[1] and quest.starts[1].kind == "npc" and { npc = quest.starts[1].id }))
				local where = quest and ZoneName(QuestZone(quest))
				local detail = QuestTitle(first.id, quest)
				if giver and where then
					detail = (L["%s (%s, %s)"]):format(detail, giver, where)
				elseif giver or where then
					detail = (L["%s (%s)"]):format(detail, giver or where)
				end
				N.Reason(card, "prep", E:Plural(#prep.pickup, "%d quest to pick up first: %s.", "%d quests to pick up first: %s."):format(#prep.pickup, detail), 15 + #prep.pickup)
				N.Penalty(card, "readiness", L["Pick up its quests before you go."])
			end
			for _, row in ipairs(prep.pickup) do card.quests[#card.quests + 1] = row.id end
			for _, row in ipairs(prep.inLog) do card.quests[#card.quests + 1] = row.id end
			if #prep.inLog > 0 then
				N.Reason(card, "inLog", E:Plural(#prep.inLog, "%d of its quests is in your log.", "%d of its quests are in your log."):format(#prep.inLog), 20 + #prep.inLog)
			end
			-- Freshness and the first visit (only with run records).
			local runs = Runs(info, ctx)
			card.runs = runs
			if runs then
				if runs.atLevel > 0 then
					f.freshness = 0.7 ^ runs.atLevel
					N.Penalty(card, "freshness", E:Plural(runs.atLevel, "You ran it once at this level.", "You ran it %d times at this level."):format(runs.atLevel))
				end
				if runs.total == 0 then N.Bonus(card, "first", 10, L["No run of yours here on record yet."], 10) end
			end
			-- Upgrades (the Loot Guide's own ranking, when it has one).
			local upgrades = InstanceUpgrades(ctx)
			if upgrades and upgrades.key == info.key then
				local n = #upgrades.items
				local names = {}
				for index = 1, min(2, n) do
					local record = LG:ItemRecord(upgrades.items[index])
					names[#names + 1] = record and record.name or ("item:" .. upgrades.items[index])
				end
				N.Bonus(card, "upgrades", min(16, 4 * n),
					E:Plural(n, "%d upgrade for you: %s.", "%d upgrades for you: %s."):format(n, List(names)), 4 * n)
			end
			-- Prep quest XP the game showed you (only numbers you saw).
			local prepXP = 0
			for _, row in ipairs(prep.pickup) do prepXP = prepXP + (Num((LG:QuestReward(row.id))) or 0) end
			for _, row in ipairs(prep.inLog) do prepXP = prepXP + (Num((LG:QuestReward(row.id))) or 0) end
			if ctx.xpMax and ctx.xpMax > 0 and prepXP > ctx.xpMax * 0.5 then
				N.Bonus(card, "prepXP", 8, (L["Its quests give %s XP."]):format(BreakUpLargeNumbers and BreakUpLargeNumbers(prepXP) or prepXP), 8)
			end
			local attuneKey, attuneStep = AttuneInside(info.key, ctx)
			if attuneKey then
				local AT = E.Attunements
				N.Bonus(card, "attune", 6, (L["A step of %s is inside: %s."]):format(AT:Name(attuneKey), AT:StepTitle(attuneStep)), 6)
				card.attune = { key = attuneKey, step = attuneStep }
			end
			local rest = ctx.xpMax and ctx.xpMax > 0 and ctx.rested / ctx.xpMax or 0
			if rest > 0.3 then N.Bonus(card, "rested", 5, (L["Rested (%d%%): a good night for a dungeon."]):format(floor(rest * 100)), 5) end
			if ctx.minutes then
				local need = (runs and runs.median and runs.median / 60) or (raid and 120 or 45)
				if need <= ctx.minutes then
					local minutes = floor(need + 0.5)
					N.Bonus(card, "time", 5, E:Plural(minutes, "Fits your time: about %d minute.", "Fits your time: about %d minutes."):format(minutes), 5)
				else
					local minutes = floor(need + 0.5)
					N.Penalty(card, "time", E:Plural(minutes, "Takes about %d minute.", "Takes about %d minutes."):format(minutes))
				end
			end
			-- Actions.
			N.Action(card, "open", { page = "journal", arg = info.key })
			local entrance = not InCombatLockdown() and LG:EntrancePoint(info.key)
			if entrance then
				card.point = entrance
				N.Action(card, "map", { point = entrance, title = info.name, label = L["Entrance"] })
			end
			if size > 1 and (ctx.groupSize or 1) < size then
				N.Action(card, "group")
				N.Action(card, "copy", { text = N.GroupLine(info, card, ctx) })
			end
			N.Action(card, "goal", { goal = { kind = "dungeon", target = info.key } })
			-- Near your level with runs on record: every card says why it is
			-- there, so the level window is the reason.
			if #card.why == 0 then
				N.Reason(card, "levelFit", (L["Near your level: the dungeon is %d-%d."]):format(info.min, info.max), 1)
			end
			cards[#cards + 1] = card
		end
	end
	return cards
end

-- "LF2M Shadowfang Keep, have quests": filled into the chat box only.
function N.GroupLine(info, card, ctx)
	local need = max(1, (info.size or 5) - (ctx and ctx.groupSize or 1))
	local text = (L["LF%dM %s"]):format(need, info.name)
	if card and card.prep and (#card.prep.inLog + #card.prep.pickup) > 0 then text = text .. L[", have quests"] end
	return text
end

---------------------------------------------------------------------------
-- Candidates: attunements and keys (EldoUI.Attunements)
---------------------------------------------------------------------------
local OPEN_READY = { available = 1, active = 1, turnin = 1, unknown = 0.5, low = 0.3 }

builders.attune = function(ctx)
	local AT = E.Attunements
	if not (AT and AT.Running and AT:Running()) then return {} end
	local cards = {}
	-- Attunements and keys, then the class quest chains of your class.
	local keys, seen = {}, {}
	for _, list in ipairs({ AT:MainKeys(), type(AT.ClassKeys) == "function" and AT:ClassKeys() or {} }) do
		for _, key in ipairs(list) do
			if not seen[key] then
				seen[key] = true
				keys[#keys + 1] = key
			end
		end
	end
	for _, key in ipairs(keys) do
		local entry = AT:Get(key)
		local done, total, _, state = AT:Progress(key)
		local step = state ~= "done" and AT:NextSteps(key)[1]
		local minLevel = entry and entry.minLevel
		if entry and entry.kind == "class" and type(AT.StartLevel) == "function" then minLevel = AT:StartLevel(key) or minLevel end
		local reachable = not minLevel or ctx.level >= minLevel - (tonumber(LG.db and LG.db.levelWindow) or 3)
		if entry and step and reachable and AT:FactionFits(entry, "mine") then
			local stepState = AT:StepState(key, step.id) or "unknown"
			local name = AT:Name(key)
			local card = N.Card("attune", key, entry.kind == "raid" and (L["%s attunement"]):format(name) or name)
			card.subtitle = (L["Step %d of %d: %s"]):format(min(done + 1, max(total, 1)), max(total, 1), AT:StepTitle(step))
			card.provenance = entry.forever and "forever" or "classic"
			card.level = minLevel and { min = minLevel, max = entry.maxLevel or ctx.maxLevel } or nil
			card.step = step
			if step.quest then card.quests = { step.quest } end
			local place = AT:StepPlace(step)
			card.point = place and place.uiMapID and place or nil
			card.uiMapID, card.zone = place and place.uiMapID, place and place.zone
			local f = card.factors
			f.levelFit = minLevel and N.LevelFit(minLevel, entry.maxLevel or ctx.maxLevel, ctx.level) or 1
			f.readiness = OPEN_READY[stepState] or 0.5
			f.proximity = N.Proximity(card.uiMapID, ctx, place and place.instance)
			if done > 0 then
				N.Reason(card, "attune", E:Plural(total, "You are %d of %d step in.", "You are %d of %d steps in."):format(done, total), 30)
			else
				N.Reason(card, "attune", (L["The first step is open: %s."]):format(AT:StepTitle(step)), 25)
			end
			if stepState == "turnin" then
				N.Reason(card, "turnin", L["The step is ready to hand in."], 35)
			elseif stepState == "low" then
				N.Penalty(card, "readiness", (L["It opens at level %d."]):format(minLevel or ctx.level + 1))
			elseif stepState == "unknown" then
				N.Penalty(card, "readiness", L["The game does not report this step; it counts once the next one is done."])
			end
			if f.proximity < 1 and card.zone then N.Penalty(card, "proximity", (L["The step is %s."]):format(InPlace(card.zone))) end
			if place and place.uiMapID then N.Action(card, "map", { point = place, title = AT:StepTitle(step) }) end
			N.Action(card, "open", { attune = key })
			N.Action(card, "goal", { goal = { kind = "attune", target = key } })
			cards[#cards + 1] = card
		end
	end
	return cards
end

---------------------------------------------------------------------------
-- Candidates from other files and plugins
---------------------------------------------------------------------------
local extra = {}   -- kind -> { fn, ... }

function J:RegisterNextSource(kind, fn)
	if type(kind) ~= "string" or type(fn) ~= "function" then return false end
	extra[kind] = extra[kind] or {}
	table.insert(extra[kind], fn)
	if not KIND_WEIGHT[kind] then
		KIND_WEIGHT[kind] = 0.5
		KIND_ORDER[#KIND_ORDER + 1] = kind
	end
	N:Invalidate()
	return true
end

function J:UnregisterNextSource(kind, fn)
	local list = extra[kind]
	if not list then return end
	for index = #list, 1, -1 do
		if list[index] == fn then table.remove(list, index) end
	end
	N:Invalidate()
end

function J:NextWeights()
	return N:Weights()
end

---------------------------------------------------------------------------
-- Not now and muted kinds
---------------------------------------------------------------------------
local muted = {}

local function NotNowStore()
	local rec = J.Char and J:Char()
	local ui = rec and rec.ui
	if type(ui) ~= "table" then return nil end
	if type(ui.notNow) ~= "table" then ui.notNow = {} end
	return ui.notNow
end

function J:NotNow(id)
	local store = NotNowStore()
	if not (store and type(id) == "string") then return false end
	store[id] = { t = time(), level = Num(UnitLevel("player")) or 1 }
	N:Invalidate()
	A:MarkDirty("next")
	return true
end

function J:ClearNotNow(id)
	local store = NotNowStore()
	if not store then return end
	if id then store[id] = nil else wipe(store) end
	N:Invalidate()
	A:MarkDirty("next")
end

-- Hidden until the next level or 24 hours later.
function J:IsNotNow(id, level, now)
	local store = NotNowStore()
	local mark = store and store[id]
	if type(mark) ~= "table" then return false end
	level = level or Num(UnitLevel("player")) or 1
	now = now or time()
	if (mark.level or 0) < level or now - (mark.t or 0) >= NOT_NOW_SECONDS then
		store[id] = nil
		return false
	end
	return true
end

function J:MuteNextKind(kind, on)
	if type(kind) ~= "string" then return end
	muted[kind] = on ~= false or nil
	N:Invalidate()
	A:MarkDirty("next")
end

function J:NextKindMuted(kind)
	return muted[kind] and true or false
end

---------------------------------------------------------------------------
-- The ranking
---------------------------------------------------------------------------
local function Compare(a, b)
	if a.score ~= b.score then return a.score > b.score end
	local pa, pb = a.factors.proximity, b.factors.proximity
	if pa ~= pb then return pa > pb end
	local la = a.level and a.level.min or 0
	local lb = b.level and b.level.min or 0
	if la ~= lb then return la < lb end
	if a.title ~= b.title then return tostring(a.title) < tostring(b.title) end
	return a.id < b.id
end
N.Compare = Compare

function N:Build(opts)
	opts = opts or {}
	local ctx = self:Context(opts)
	local cards = {}
	local function Take(list)
		for _, card in ipairs(list or {}) do
			if type(card) == "table" and card.kind and card.id then
				if not card.score then N.Score(card, ctx) end
				if card.score > 0 then cards[#cards + 1] = card end
			end
		end
	end
	for _, kind in ipairs(KIND_ORDER) do
		if not muted[kind] and (not opts.kinds or opts.kinds[kind]) then
			local build = builders[kind]
			if build then
				local ok, list = pcall(build, ctx)
				if ok then Take(list) else geterrorhandler()(("EldoUI My Adventure next (%s): %s"):format(kind, tostring(list))) end
			end
			for _, fn in ipairs(extra[kind] or {}) do
				local ok, list = pcall(fn, ctx, N)
				if ok then Take(list) else geterrorhandler()(("EldoUI My Adventure next source (%s): %s"):format(kind, tostring(list))) end
			end
		end
	end
	table.sort(cards, Compare)
	local hiddenCount = 0
	local out = {}
	for _, card in ipairs(cards) do
		if not opts.hidden and J:IsNotNow(card.id, ctx.level, ctx.now) then
			hiddenCount = hiddenCount + 1
		else
			out[#out + 1] = card
		end
	end
	local limit = tonumber(opts.limit)
	if limit then for index = #out, limit + 1, -1 do out[index] = nil end end
	local data = ctx.hasData and "classic" or (#LG:LiveInstances() > 0 and "live" or "none")
	return { cards = out, level = ctx.level, at = GetTime(), hidden = hiddenCount, data = data, group = ctx.groupSize,
		chip = ctx.chip }
end

-- Cached by the options, rebuilt at most once a second when an input
-- changed, never in combat (the last result comes back, marked partial).
local cache = {}     -- option key -> result
local dirty = true
N.builds = 0

local function OptKey(opts)
	if not opts then return "" end
	local kinds = {}
	for kind in pairs(opts.kinds or {}) do kinds[#kinds + 1] = kind end
	table.sort(kinds)
	return ("%s|%s|%s|%s|%s"):format(tostring(opts.group), tostring(opts.minutes), table.concat(kinds, ","),
		tostring(opts.hidden), tostring(opts.limit))
end

function N:Invalidate()
	dirty = true
	wipe(cache)
end

function J:Next(opts)
	local key = OptKey(opts)
	local last = cache[key]
	if InCombatLockdown() then
		if last then last.partial = true end
		return last or { cards = {}, level = Num(UnitLevel("player")) or 1, at = GetTime(), hidden = 0, partial = true, data = "none" }
	end
	local now = GetTime()
	local wanted = (opts and opts.fresh) or not last or (dirty and now - last.at >= THROTTLE)
	if wanted then
		if dirty then wipe(cache) end
		dirty = false
		N.builds = N.builds + 1
		last = N:Build(opts)
		cache[key] = last
		N.last = last
	end
	last.partial = nil
	return last
end

function J:NextTop(opts)
	local result = self:Next(opts)
	return result.cards[1]
end

function J:NextCard(id)
	for _, result in pairs(cache) do
		for _, card in ipairs(result.cards) do
			if card.id == id then return card end
		end
	end
	return nil
end

---------------------------------------------------------------------------
-- The trip plan (a dungeon card opened as a plan)
---------------------------------------------------------------------------
local function QuestLine(id, status)
	local quest = LG:JourneyQuest(id)
	local giver = quest and NpcName(quest.giver or (quest.starts[1] and quest.starts[1].kind == "npc" and { npc = quest.starts[1].id }))
	local uiMapID = QuestZone(quest)
	return { id = id, title = QuestTitle(id, quest), status = status, giver = giver, zone = ZoneName(uiMapID), uiMapID = uiMapID,
		point = quest and N.GiverPoint(quest), breadcrumb = quest and quest.breadcrumbFor or nil, provenance = quest and quest.provenance }
end

function J:TripPlan(card)
	if type(card) == "string" then card = self:NextCard(card) end
	if not (card and card.kind == "dungeon") then return nil end
	local key = card.key
	local info = LG:InstanceInfo(key)
	if not info then return nil end
	local ctx = N:Context()
	local plan = { card = card, key = key, name = info.name, before = {}, onTheWay = {}, access = {}, inside = {}, gettingThere = {},
		afterwards = {} }
	-- Before you go: quests to pick up, in travel order (zone, then name).
	local prep = card.prep or N.Prep(key)
	for _, row in ipairs(prep.pickup) do plan.before[#plan.before + 1] = QuestLine(row.id, "available") end
	for _, row in ipairs(prep.inLog) do plan.before[#plan.before + 1] = QuestLine(row.id, "active") end
	table.sort(plan.before, function(a, b)
		local ha, hb = a.uiMapID == ctx.map and 0 or 1, b.uiMapID == ctx.map and 0 or 1
		if ha ~= hb then return ha < hb end
		if (a.zone or "") ~= (b.zone or "") then return (a.zone or "") < (b.zone or "") end
		return a.title < b.title
	end)
	for _, line in ipairs(plan.before) do
		if line.breadcrumb then line.note = (L["Optional: leads to %s."]):format(QuestTitle(line.breadcrumb)) end
	end
	-- On the way: your log in the entrance zone.
	local zoneName = card.zone
	if zoneName then
		local rows = ctx.log.byHeader[zoneName]
		if rows and #rows > 0 then
			plan.onTheWay[#plan.onTheWay + 1] = { text = E:Plural(#rows, "%d quest %s in your log.", "%d quests %s in your log."):format(#rows, InPlace(zoneName)),
				quests = rows }
		end
	end
	-- Access: the door's level, keys and quests (attunement link).
	local data = LG:Instance(key)
	local access = data and data.access
	if access then
		if access.level then
			plan.access[#plan.access + 1] = { text = (L["The door opens at level %d."]):format(access.level), done = ctx.level >= access.level }
		end
		for _, item in ipairs(type(access.items) == "table" and access.items or {}) do
			local record = LG:ItemRecord(item)
			local have = Num(C_Item and C_Item.GetItemCount and Call(C_Item.GetItemCount, item, true)) or 0
			plan.access[#plan.access + 1] = { text = (L["Needs %s."]):format(record and record.name or ("item:" .. item)), done = have > 0, item = item }
		end
		for _, quest in ipairs(type(access.quests) == "table" and access.quests or {}) do
			plan.access[#plan.access + 1] = { text = (L["Needs the quest %s."]):format(QuestTitle(quest)), done = LG:QuestDone(quest), quest = quest }
		end
	end
	local AT = E.Attunements
	if AT and AT.Running and AT:Running() then
		for _, entryKey in ipairs(AT:ForInstance(key)) do
			local _, _, percent, state = AT:Progress(entryKey)
			plan.access[#plan.access + 1] = { text = (L["%s: %d%% done."]):format(AT:Name(entryKey), percent), done = state == "done", attune = entryKey }
		end
	end
	-- Inside: your quests there, bosses with upgrades, attunement steps.
	for _, row in ipairs(prep.inLog) do plan.inside[#plan.inside + 1] = { text = (L["Finish %s."]):format(QuestTitle(row.id)), quest = row.id } end
	local upgrades = InstanceUpgrades(ctx)
	if upgrades and upgrades.key == key then
		for _, itemID in ipairs(upgrades.items) do
			local record = LG:ItemRecord(itemID)
			plan.inside[#plan.inside + 1] = { text = (L["Upgrade: %s."]):format(record and record.name or ("item:" .. itemID)), item = itemID }
		end
	end
	if card.attune then
		plan.inside[#plan.inside + 1] = { text = (L["%s: %s."]):format(AT:Name(card.attune.key), AT:StepTitle(card.attune.step)), attune = card.attune.key }
	end
	-- Getting there: the entrance, your hearth, the zone.
	local entrance = card.point or (not InCombatLockdown() and LG:EntrancePoint(key))
	if entrance then
		plan.gettingThere[#plan.gettingThere + 1] = { text = (L["Entrance %s."]):format(InPlace(entrance.zone or zoneName or info.name)), point = entrance }
	elseif zoneName then
		plan.gettingThere[#plan.gettingThere + 1] = { text = (L["The entrance is %s."]):format(InPlace(zoneName)) }
	end
	local bind = Plain(GetBindLocation and GetBindLocation())
	if type(bind) == "string" and bind ~= "" then
		plan.gettingThere[#plan.gettingThere + 1] = { text = (L["Your hearthstone is set to %s."]):format(bind) }
	end
	-- Afterwards: where to hand in, the next trip a level up.
	for _, row in ipairs(prep.inLog) do
		local quest = LG:JourneyQuest(row.id)
		local ender = quest and NpcName(quest.ender or (quest.ends[1] and quest.ends[1].kind == "npc" and { npc = quest.ends[1].id }))
		if ender then
			plan.afterwards[#plan.afterwards + 1] = { text = (L["Hand in %s to %s."]):format(QuestTitle(row.id, quest), ender), point = N.EnderPoint(quest),
				quest = row.id }
		end
	end
	local nextLevel = min(ctx.level + 1, ctx.maxLevel)
	for _, other in ipairs(LG:Catalog()) do
		if other.key ~= key and other.kind == card.kind and other.min and other.min == nextLevel and LG:OpenNow(other) then
			local side = CitySide(other)
			if not (side and ctx.faction and side ~= ctx.faction) then
				plan.afterwards[#plan.afterwards + 1] = { text = (L["At level %d: %s opens."]):format(nextLevel, other.name), instance = other.key }
			end
		end
	end
	if Settings().prepChecklist then plan.checklist = J:PrepChecklist() end
	return plan
end

---------------------------------------------------------------------------
-- The prep checklist: what you have; nothing is bought or used
---------------------------------------------------------------------------
local FOOD_CLASS, FOOD_SUBCLASS = 0, 5   -- Consumable: Food & Drink

function J:PrepChecklist()
	local list = {}
	-- Bag space.
	local free = 0
	local C = C_Container
	if C and C.GetContainerNumFreeSlots then
		for bag = 0, 4 do
			local slots, family = Call(C.GetContainerNumFreeSlots, bag)
			slots, family = Num(slots), Num(family)
			if slots and (family or 0) == 0 then free = free + slots end
		end
		list[#list + 1] = { key = "bags", ok = free >= 6, value = free,
			text = E:Plural(free, "%d free bag slot.", "%d free bag slots."):format(free) }
	end
	-- Repairs: the lowest durability of what you wear.
	if GetInventoryItemDurability then
		local lowest
		for slot = 1, 18 do
			local now, most = Call(GetInventoryItemDurability, slot)
			now, most = Num(now), Num(most)
			if now and most and most > 0 then
				local pct = now / most
				if not lowest or pct < lowest then lowest = pct end
			end
		end
		if lowest then
			local pct = floor(lowest * 100 + 0.5)
			list[#list + 1] = { key = "repair", ok = pct >= 50, value = pct, text = (L["Gear at %d%% durability (lowest piece)."]):format(pct) }
		end
	end
	-- Food and water, ammo, the hearthstone.
	local food = 0
	if C and C.GetContainerNumSlots and C.GetContainerItemID and C_Item and C_Item.GetItemInfoInstant then
		for bag = 0, 4 do
			for slot = 1, Num(Call(C.GetContainerNumSlots, bag)) or 0 do
				local itemID = Num(Call(C.GetContainerItemID, bag, slot))
				if itemID then
					local _, _, _, _, _, classID, subClassID = Call(C_Item.GetItemInfoInstant, itemID)
					if Num(classID) == FOOD_CLASS and Num(subClassID) == FOOD_SUBCLASS then
						local info = C.GetContainerItemInfo and Call(C.GetContainerItemInfo, bag, slot)
						food = food + (type(info) == "table" and Num(info.stackCount) or 1)
					end
				end
			end
		end
		list[#list + 1] = { key = "food", ok = food >= 10, value = food, text = E:Plural(food, "%d food or drink item.", "%d food and drink items."):format(food) }
	end
	local _, class = UnitClass("player")
	if Plain(class) == "HUNTER" and GetInventoryItemCount then
		local ammo = Num(Call(GetInventoryItemCount, "player", 0)) or 0
		list[#list + 1] = { key = "ammo", ok = ammo >= 400, value = ammo, text = E:Plural(ammo, "%d arrow or bullet.", "%d arrows or bullets."):format(ammo) }
	end
	if C_Item and C_Item.GetItemCount then
		local stones = Num(Call(C_Item.GetItemCount, HEARTHSTONE)) or 0
		local bind = Plain(GetBindLocation and GetBindLocation())
		local text = stones > 0 and L["Hearthstone in your bags."] or L["No hearthstone in your bags."]
		if stones > 0 and type(bind) == "string" and bind ~= "" then text = (L["Hearthstone in your bags (set to %s)."]):format(bind) end
		list[#list + 1] = { key = "hearth", ok = stones > 0, text = text }
	end
	return list
end

---------------------------------------------------------------------------
-- Actions: navigation only, each one a click
---------------------------------------------------------------------------
local function OpenGroupFinder()
	if InCombatLockdown() then
		E:Print(L["The group finder opens after combat."])
		return false
	end
	if not rawget(_G, "LFGParentFrame") and C_AddOns and C_AddOns.LoadAddOn then pcall(C_AddOns.LoadAddOn, "Blizzard_GroupFinder_VanillaStyle") end
	local frame = rawget(_G, "LFGParentFrame")
	if not frame then
		E:Print(L["This client has no group finder window."])
		return false
	end
	if frame:IsShown() then return true end
	local toggle = rawget(_G, "LFGVanilla_ToggleFrame")
	if type(toggle) == "function" then
		pcall(toggle)
	elseif ShowUIPanel then
		pcall(ShowUIPanel, frame)
	end
	return true
end
N.OpenGroupFinder = OpenGroupFinder

local function Track(quests)
	local QL = C_QuestLog
	if not (QL and QL.AddQuestWatch) then return false end
	local count = 0
	for _, id in ipairs(quests or {}) do
		-- Only quests already in your log; nothing is accepted.
		if LG:OnQuest(id) and pcall(QL.AddQuestWatch, id) then count = count + 1 end
	end
	return count > 0
end

function J:NextAct(card, key)
	if type(card) == "string" then card = self:NextCard(card) end
	if type(card) ~= "table" then return false end
	local action
	for _, a in ipairs(card.actions or {}) do
		if a.key == key then action = a break end
	end
	if not action then return false end
	if key == "map" then
		return action.point and LG:SetWaypoint(action.point, action.title or card.title) or false
	elseif key == "open" then
		if action.attune and E.Attunements then
			E.Attunements:Open(action.attune)
			return true
		elseif action.page then
			LG:Open(action.page, action.arg)
			return true
		elseif action.address then
			return J:Open(action.address)
		end
		return false
	elseif key == "track" then
		return Track(action.quests or card.quests)
	elseif key == "group" then
		return OpenGroupFinder()
	elseif key == "copy" then
		local util = rawget(_G, "ChatFrameUtil")
		if type(action.text) ~= "string" then return false end
		if util and util.OpenChat then
			util.OpenChat(action.text)
			return true
		elseif ChatFrame_OpenChat then
			ChatFrame_OpenChat(action.text)
			return true
		end
		return false
	elseif key == "goal" then
		if type(J.AddGoal) == "function" and action.goal then return J:AddGoal(action.goal) and true or false end
		return false
	elseif key == "notnow" then
		return J:NotNow(card.id)
	end
	return false
end


---------------------------------------------------------------------------
-- Inputs that change the ranking
---------------------------------------------------------------------------
-- The quest log comes through the Loot Guide's "quests" message below, sent
-- only when the log really changed; the raw quest log events fire far more
-- often.
local EVENTS = { "QUEST_TURNED_IN", "PLAYER_LEVEL_UP", "PLAYER_XP_UPDATE",
	"ZONE_CHANGED_NEW_AREA", "GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD", "UPDATE_INSTANCE_INFO", "PLAYER_UPDATE_RESTING" }

local function Changed()
	if not A.started then return end
	N:Invalidate()
	A:MarkDirty("next")
end
N.Changed = Changed

A:AddPart("next", {
	order = 60,
	init = function()
		for _, event in ipairs(EVENTS) do
			LG:Listen(event, "adventure-next", function() Changed() end)
		end
		LG:On("adventure-next", function(changed)
			if changed.data then
				citySide, entranceZone = nil, nil
			end
			-- Gear reaches the ranking only through the Loot Guide's upgrade
			-- ranking, so a gear change waits for its "rank" message instead of
			-- ranking twice.
			if changed.data or changed.quests or changed.attune or changed.journey or changed.player or changed.rank
				or changed.settings then
				Changed()
			end
		end)
	end,
	start = function() N:Invalidate() end,
	stop = function() N:Invalidate() end,
})
