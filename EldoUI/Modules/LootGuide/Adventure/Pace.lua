-- EldoUI My Adventure: pace and time to level, the rested planner and the
-- milestone countdown.
--
-- Honest by design: every number comes from what was tracked. Level times
-- come from the Characters level log (played time at each ding, the XP
-- kills and quests the game reported for that level), the session pace
-- from the XP the game reported this session (E.PlayRates, the count the
-- XP bar and the Info Bar read too). Nothing is guessed from a
-- target or a fight: there is no "kills to level" from XP per kill. The
-- counts shown are what you did, labeled as such.
--
-- API (E.Journal):
--   J:Pace() -> {
--       level, maxLevel, atMax, xp, xpMax, toLevel, percent (0-100),
--       rested, restedPercent (of a level),
--       atLevel   seconds played at this level (nil when unknown)
--       levels    { { level, took, kills, quests }, ... } your last levels, newest
--                 first (level: the level that took that long)
--       median    median seconds per level over those (two or more), or nil
--       eta       { seconds, from = "session" | "levels", basis } or nil
--       session   { gained, elapsed, perHour } or nil (after 10 minutes with
--                 some XP gained; before that the eta uses your levels)
--       now       { kills, quests } this level so far (the game's own lines)
--       last      { kills, quests, took } of the level before
--       text      "~1h 20m to 25" or nil
--   }
--   J:PaceText()             the short line (Today's header, the tracker)
--   J:RestedPlan() -> { rested, xpMax, percent, state, resting, fullIn, lines }
--       state: "none", "some", "well" (30 % and up) or "full"
--   J:Milestones([limit]) -> { { level, kind, label, levels, eta, far }, ... }
--       eta only up to 5 levels ahead; far = true past that (level count only)
--       kinds: dungeon (the next one that opens), attune (an attunement's
--       first level), ten (the next tenth level), max (the level cap)
--   N.FormatDuration(seconds) "1h 05m", "14m", "2d 4h"
local _, E = ...
local L = E.L
local A = E.Adventure
local J = E.Journal
local LG = E.LootGuide
local N = A.Next

local Plain = A.Plain
local floor, max, min = math.floor, math.max, math.min

local P = {}
A.Pace = P

local LEVELS_BACK = 5
-- A session pace counts only after this long and some XP gained: a minute
-- and one turn-in would give a wild estimate.
local SESSION_MIN_SECONDS = 600
-- Milestone times reach this many levels ahead. Later levels take longer
-- than your recent ones, so further rows show only the level count.
local MILESTONE_HORIZON = 5

local function Num(value)
	value = Plain(value)
	return type(value) == "number" and value or nil
end

-- "1h 05m", "14m", "2d 4h" (the grammar layer's Ledger form when it is there).
local function FormatDuration(seconds)
	seconds = tonumber(seconds)
	if not seconds or seconds < 0 then return nil end
	local G = E.Story and E.Story.Grammar
	if G and G.Duration then
		local text = G.Duration(seconds, "ledger")
		if type(text) == "string" and text ~= "" then return text end
	end
	if seconds < 60 then return L["<1m"] end
	if seconds < 3600 then return (L["%dm"]):format(floor(seconds / 60)) end
	if seconds < 86400 then return (L["%dh %02dm"]):format(floor(seconds / 3600), floor(seconds % 3600 / 60)) end
	return (L["%dd %dh"]):format(floor(seconds / 86400), floor(seconds % 86400 / 3600))
end
P.FormatDuration = FormatDuration
if N then N.FormatDuration = FormatDuration end

-- The Characters record of this character (read only; nil when the store
-- has nothing yet).
local function Record()
	local C = E.Characters
	return C and C.Get and C:Get(E.charKey) or nil
end

-- The session pace: the core's session count (E.PlayRates), the same one
-- the XP bar and the Info Bar read.
local function Session()
	local rates = E.PlayRates
	return { gained = rates.session and rates.session.xp or 0, elapsed = rates:Elapsed(), perHour = rates:Rate("xp") }
end

local function Median(list)
	if #list == 0 then return nil end
	local copy = {}
	for index, value in ipairs(list) do copy[index] = value end
	table.sort(copy)
	local middle = floor((#copy + 1) / 2)
	if #copy % 2 == 0 then return (copy[middle] + copy[middle + 1]) / 2 end
	return copy[middle]
end
P.Median = Median

function J:Pace()
	local level = Num(UnitLevel("player")) or 1
	local maxLevel = Num(GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion()) or 60
	local xp, xpMax = Num(UnitXP("player")), Num(UnitXPMax("player"))
	local rested = Num(GetXPExhaustion and GetXPExhaustion()) or 0
	local out = { level = level, maxLevel = maxLevel, atMax = level >= maxLevel, xp = xp, xpMax = xpMax, rested = rested, levels = {} }
	if xp and xpMax and xpMax > 0 then
		out.toLevel = max(0, xpMax - xp)
		out.percent = floor(xp / xpMax * 1000 + 0.5) / 10
		out.restedPercent = floor(rested / xpMax * 100 + 0.5)
	end
	-- Your level log (Characters).
	local rec = Record()
	local log = rec and type(rec.levels) == "table" and rec.levels or {}
	local took = {}
	for back = 0, LEVELS_BACK - 1 do
		local row = log[level - back]
		if type(row) == "table" and tonumber(row.took) and row.took > 0 then
			out.levels[#out.levels + 1] = { level = level - back - 1, took = row.took, kills = row.kills, quests = row.quests }
			took[#took + 1] = row.took
		end
	end
	if #took >= 2 then out.median = Median(took) end
	local current = log[level]
	if type(current) == "table" then out.last = { kills = current.kills, quests = current.quests, took = current.took } end
	local now = rec and type(rec.levelNow) == "table" and rec.levelNow
	if now and now.level == level then out.now = { kills = now.kills or 0, quests = now.quests or 0 } end
	-- Played time at this level.
	local C = E.Characters
	local played = rec and C and C.Played and C:Played(rec)
	if played and type(current) == "table" and current.played then
		out.atLevel = max(0, played - current.played)
	elseif rec and rec.playedLevel and rec.playedAt and not rec.loggedOut then
		out.atLevel = rec.playedLevel + max(0, time() - rec.playedAt)
	end
	-- Time to the next level: this session's pace first, else your levels.
	local s = Session()
	local steady = s.perHour and s.perHour > 0 and (tonumber(s.elapsed) or 0) >= SESSION_MIN_SECONDS and (tonumber(s.gained) or 0) > 0
	if steady then out.session = { gained = s.gained, elapsed = s.elapsed, perHour = s.perHour } end
	if not out.atMax and out.toLevel then
		if steady then
			out.eta = { seconds = out.toLevel / s.perHour * 3600, from = "session" }
		elseif out.median and xpMax and xpMax > 0 then
			out.eta = { seconds = out.median * out.toLevel / xpMax, from = "levels", basis = #took }
		end
	end
	if out.eta then out.text = (L["~%s to %d"]):format(FormatDuration(out.eta.seconds), level + 1) end
	return out
end

function J:PaceText()
	local pace = self:Pace()
	return pace.text
end

---------------------------------------------------------------------------
-- The rested planner
---------------------------------------------------------------------------
function J:RestedPlan()
	local level = Num(UnitLevel("player")) or 1
	local maxLevel = Num(GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion()) or 60
	local rested = Num(GetXPExhaustion and GetXPExhaustion()) or 0
	local xpMax = Num(UnitXPMax("player"))
	local resting = Plain(IsResting and IsResting()) and true or false
	local out = { rested = rested, xpMax = xpMax, resting = resting, lines = {} }
	if level >= maxLevel or not xpMax or xpMax <= 0 then
		out.state = "none"
		out.percent = 0
		return out
	end
	local percent = floor(rested / xpMax * 100 + 0.5)
	out.percent = percent
	local C = E.Characters
	local rec = Record()
	-- 150 %, or what the Legacy talent Well Rested lets the bar hold.
	local cap = C and C.RestCap and floor(C:RestCap(rec) * 100 + 0.5) or 150
	if percent >= cap then
		out.state = "full"
	elseif percent >= 30 then
		out.state = "well"
	elseif percent > 0 then
		out.state = "some"
	else
		out.state = "none"
	end
	if C and C.FullyRestedIn and rec then out.fullIn = C:FullyRestedIn(rec) end
	if out.state == "full" then
		out.lines[#out.lines + 1] = (L["Fully rested (%d%% of a level): a good time for a dungeon or a long quest run."]):format(percent)
	elseif out.state == "well" then
		out.lines[#out.lines + 1] = (L["Well rested (%d%% of a level): a good time for a dungeon."]):format(percent)
	elseif out.state == "some" then
		out.lines[#out.lines + 1] = (L["Rested %d%% of a level."]):format(percent)
	else
		out.lines[#out.lines + 1] = L["No rested XP right now."]
	end
	if resting then
		out.lines[#out.lines + 1] = L["You are resting: rested XP builds four times as fast here."]
	elseif out.state ~= "full" then
		out.lines[#out.lines + 1] = L["Log out in an inn or a city to rest faster."]
	end
	return out
end

---------------------------------------------------------------------------
-- Milestones: the next things that open by level
---------------------------------------------------------------------------
function J:Milestones(limit)
	local pace = self:Pace()
	local level, maxLevel = pace.level, pace.maxLevel
	local list = {}
	local function Add(target, kind, label)
		if target <= level or target > maxLevel then return end
		local item = { level = target, kind = kind, label = label, levels = target - level }
		if target - level > MILESTONE_HORIZON then
			item.far = true
		elseif pace.median and pace.median > 0 then
			-- Your recent median per level; this level counts what is left.
			local rest = (pace.toLevel and pace.xpMax and pace.xpMax > 0) and pace.toLevel / pace.xpMax or 1
			item.eta = pace.median * (target - level - 1 + rest)
		end
		list[#list + 1] = item
	end
	-- The next dungeon that opens (the lowest level above yours).
	local faction = LG:Player().faction
	local nextDungeon
	for _, info in ipairs(LG:Catalog()) do
		if info.kind == "dungeon" and info.min and info.min > level and LG:Playable(info) then
			local side = N and N.CitySide and N.CitySide(info)
			if not (side and faction and side ~= faction) and (not nextDungeon or info.min < nextDungeon.min) then nextDungeon = info end
		end
	end
	if nextDungeon then Add(nextDungeon.min, "dungeon", (L["%s opens"]):format(nextDungeon.name)) end
	-- Attunements that start above your level.
	local AT = E.Attunements
	if AT and AT.Running and AT:Running() then
		for _, key in ipairs(AT:MainKeys()) do
			local entry = AT:Get(key)
			if entry and entry.minLevel and entry.minLevel > level then
				Add(entry.minLevel, "attune", (L["%s attunement starts"]):format(AT:Name(key)))
			end
		end
	end
	local ten = (floor(level / 10) + 1) * 10
	if ten < maxLevel then Add(ten, "ten", (L["Level %d"]):format(ten)) end
	Add(maxLevel, "max", (L["Level %d, the level cap"]):format(maxLevel))
	table.sort(list, function(a, b)
		if a.level ~= b.level then return a.level < b.level end
		if (a.kind == "max") ~= (b.kind == "max") then return b.kind == "max" end
		return a.label < b.label
	end)
	-- One row per kind (the nearest), the cap always last.
	local out, seen = {}, {}
	for _, item in ipairs(list) do
		local kindKey = item.kind == "attune" and ("attune" .. item.label) or item.kind
		if not seen[kindKey] then
			seen[kindKey] = true
			out[#out + 1] = item
		end
	end
	limit = tonumber(limit)
	if limit and #out > limit then
		local cap = out[#out]
		for index = #out, limit, -1 do out[index] = nil end
		if cap.kind == "max" then out[#out + 1] = cap end
	end
	return out
end

P.Session = Session
P.Num = Num
