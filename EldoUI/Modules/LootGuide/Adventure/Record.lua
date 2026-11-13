-- EldoUI My Adventure: the recorder: time per level, zone and
-- subzone (AFK skipped), deaths, places and first dungeons, the level
-- rows nothing else keeps, XP and money earned, kills, sessions, rested
-- gained while away and explored zones.
--
-- What it keeps (EldoUIDB.journal[charKey], Store.lua):
--   levels[n]  = { time, zones = { [zone] = seconds }, deaths, deathZones,
--                  kills, quests, earned, at, zone }   (at/zone only when the
--                  Characters level log is not recording)
--   zones[z]   = { t, first, firstLevel, map, kills, quests, deaths,
--                  subs = { [subzone] = { t, first, level } } }   open world only
--   instancesSeen = { [instance] = time }   first visits (the fallback row)
--   totals     = { deaths, xp, earned, time, kills }
--   sessions   = { { login, logout, level, playedIn, playedOut } }
--   mobs       = { [creature] = kills }  named XP kills, for creature goals
--   off        = { [source] = { [level] = true } }  levels a store was off
--   lastRested, startedZone, questsBefore, playedBefore
--
-- What it reads instead of keeping (no second copies, plan 2.7):
--   * the level log of E.Characters (CS-1): with "Use the Characters and
--     Instances records" on, C:Recording() is true while the journal
--     records, so Characters writes the level rows; the journal only writes
--     its own "level" row (same ref) when that log is not recording;
--   * dungeon runs from E.Instances: with the option on, M:EnsureRecorder()
--     records runs while the Instances window is off. The journal's own
--     "dungeon" row is written only when no instance source is live.
--
-- Honesty (Midnight rules): kills come only from the game's "Creatures
-- killed" statistic (read out of combat) or from XP lines that name the
-- creature (E.ChatParse "xpkill", secret lines skipped). Never the combat
-- log, PARTY_KILL, UNIT_DIED, XP timing or your target. A secret value is
-- dropped, never compared: AFK that is secret counts as not AFK.
--
-- API (E.Journal):
--   J:Explore(zone)     the zone's corners from its "Explore" achievement,
--                       { { name, done } } or nil (Places page)
--   J:KillStat()        the statistic id the kills come from, or nil
--   J:MobKills(name)    named XP kills of a creature (creature goals)
--
-- Portions adapted from Forever Journal by Ugge Zen, MIT License (see
-- THIRD_PARTY_NOTICES.md): the time ticker with its AFK skip, the
-- "was alive" death guard, first visits per zone and subzone, XP and
-- money totals across a level-up, the rested-while-away share, the kill
-- statistic lookup and the explore corners.
--
-- MIT License
--
-- Copyright (c) 2026 Ugge Zen
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in all
-- copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
-- SOFTWARE.
local _, E = ...
local A = E.Adventure
local J = E.Journal
local S = A.Store

local Plain = A.Plain
local floor = math.floor

-- Shared helpers for Record, Chronicle and Fellowship.
local R = {}
A.Record = R

function R.Now()
	return time()
end

local function Call(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a, b, c, d, e, f, g, h, i, j, k, l = pcall(fn, ...)
	if not ok then return nil end
	return a, b, c, d, e, f, g, h, i, j, k, l
end
R.Call = Call

-- A plain string the game gave, or nil (secret, empty, not a string).
local function Text(value)
	if E:IsSecret(value) or type(value) ~= "string" or value == "" then return nil end
	return value
end
R.Text = Text

local function Number(value)
	if E:IsSecret(value) then return nil end
	return tonumber(value)
end
R.Number = Number

function R.Level()
	local level = Number(UnitLevel("player"))
	return level and level > 0 and level or nil
end

function R.Zone()
	local zone = Text(Call(GetRealZoneText))
	local sub = Text(Call(GetSubZoneText))
	if sub == zone then sub = nil end
	return zone, sub
end

-- Inside a dungeon or raid: the instance's name, id and kind.
function R.Instance()
	local inside, kind = Call(IsInInstance)
	if E:IsSecret(inside) or E:IsSecret(kind) or not inside then return nil end
	if kind ~= "party" and kind ~= "raid" then return nil end
	local name, _, _, _, _, _, _, instanceID = Call(GetInstanceInfo)
	name = Text(name)
	if not name then return nil end
	return name, Number(instanceID), kind
end

-- Map and position (nil inside instances, where the game gives none).
function R.Position()
	local mapID = C_Map and Number(Call(C_Map.GetBestMapForUnit, "player"))
	if not mapID then return nil end
	local pos = Call(C_Map.GetPlayerMapPosition, mapID, "player")
	if type(pos) == "table" and pos.GetXY then
		local x, y = Call(pos.GetXY, pos)
		x, y = Number(x), Number(y)
		if x and y and x > 0 then return mapID, floor(x * 1000 + 0.5) / 10, floor(y * 1000 + 0.5) / 10 end
	end
	return mapID
end

-- The record this character writes to, or nil while the journal does not
-- write (off, Loot Guide off, "Don't record this character").
function R.Rec()
	if not J:Recording() then return nil end
	return S.Own()
end

function R.UseStores()
	return A.db and A.db.useStores ~= false
end

function R.LevelRec(rec, level)
	level = tonumber(level)
	if not level then return nil end
	local row = rec.levels[level]
	if type(row) ~= "table" then
		row = {}
		rec.levels[level] = row
	end
	row.time = tonumber(row.time) or 0
	row.deaths = tonumber(row.deaths) or 0
	row.kills = tonumber(row.kills) or 0
	row.quests = tonumber(row.quests) or 0
	row.earned = tonumber(row.earned) or 0
	if type(row.zones) ~= "table" then row.zones = {} end
	if type(row.deathZones) ~= "table" then row.deathZones = {} end
	return row
end

function R.ZoneRec(rec, zone)
	local row = zone and rec.zones[zone]
	if type(row) ~= "table" then return nil end
	if type(row.subs) ~= "table" then row.subs = {} end
	return row
end

-- A lazily made table on the record.
function R.Map(rec, key)
	if type(rec[key]) ~= "table" then rec[key] = {} end
	return rec[key]
end

-- A private event frame for a recorder file: R.Events(handlers) returns
-- { Start = fn, Stop = fn }. handlers[event] = fn(...). Each handler runs
-- in a pcall, so one broken game value never stops the rest.
function R.Events(handlers, units)
	local frame = CreateFrame("Frame")
	frame:SetScript("OnEvent", function(_, event, ...)
		local fn = handlers[event]
		if not fn then return end
		local ok, err = pcall(fn, ...)
		if not ok then geterrorhandler()(("EldoUI My Adventure %s: %s"):format(event, tostring(err))) end
	end)
	local box = { frame = frame }
	function box.Start()
		for event in pairs(handlers) do
			if units and units[event] then
				pcall(frame.RegisterUnitEvent, frame, event, units[event])
			else
				pcall(frame.RegisterEvent, frame, event)
			end
		end
	end
	function box.Stop()
		frame:UnregisterAllEvents()
	end
	return box
end

-- Mark the current level as one where a store did not record (the story
-- says "the journal does not know" for those levels).
function R.MarkOff(rec, source, level)
	level = level or R.Level()
	if not level then return end
	local off = R.Map(rec, "off")
	off[source] = type(off[source]) == "table" and off[source] or {}
	off[source][level] = true
end

---------------------------------------------------------------------------
-- State of this session
---------------------------------------------------------------------------
local st = {
	dead = false, loggedIn = false,
	xp = nil, xpMax = nil, xpLevel = nil, money = nil,
	killStat = nil, statKills = nil,
	login = nil, playedIn = nil,
}
R.state = st

local function CharactersRecording()
	local C = E.Characters
	return C and C.Recording and C:Recording() or false
end
R.CharactersRecording = CharactersRecording

local function InstancesRecording()
	local M = E.Instances
	if not M then return false end
	if M.active then return true end
	return M.Recording and M:Recording() or false
end
R.InstancesRecording = InstancesRecording

local function NoteOff(rec, level)
	if not CharactersRecording() then R.MarkOff(rec, "levels", level) end
	if not InstancesRecording() then R.MarkOff(rec, "instances", level) end
end

---------------------------------------------------------------------------
-- Time ticker: one second, plain counters only (safe in combat).
---------------------------------------------------------------------------
local function Afk()
	local afk = Call(UnitIsAFK, "player")
	if E:IsSecret(afk) then return false end
	return afk and true or false
end

function R.Tick()
	-- "Use the Characters and Instances records" changed: follow it.
	local stores = R.UseStores()
	if st.stores ~= nil and st.stores ~= stores then R.Bridges(true) end
	st.stores = stores
	if not st.loggedIn then return end
	local rec = R.Rec()
	if not rec or Afk() then return end
	local level = R.Level()
	local zone, sub = R.Zone()
	rec.totals.time = (rec.totals.time or 0) + 1
	local row = R.LevelRec(rec, level)
	if row then
		row.time = row.time + 1
		if zone then row.zones[zone] = (row.zones[zone] or 0) + 1 end
	end
	if zone and not R.Instance() then
		local place = R.ZoneRec(rec, zone)
		if place then
			place.t = (tonumber(place.t) or 0) + 1
			local spot = sub and place.subs[sub]
			if type(spot) == "table" then spot.t = (tonumber(spot.t) or 0) + 1 end
		end
	end
end

---------------------------------------------------------------------------
-- Places: the first visit of each zone and subzone, first dungeons
---------------------------------------------------------------------------
function R.EnterZone()
	local rec = R.Rec()
	if not rec then return end
	local now, level = R.Now(), R.Level()
	local name, instanceID, kind = R.Instance()
	if name then
		local seen = R.Map(rec, "instancesSeen")
		if not seen[name] then
			seen[name] = now
			-- With an instance source live, its first run is the row.
			if not J:SourceLive("instances") then
				J:Log(kind == "raid" and "raid" or "dungeon", { instance = name, instanceID = instanceID, zone = name })
			end
		end
		return
	end
	local zone, sub = R.Zone()
	if not zone then return end
	local place = R.ZoneRec(rec, zone)
	if not place then
		local first = next(rec.zones) == nil
		local mapID = R.Position()
		rec.zones[zone] = { t = 0, first = now, firstLevel = level, map = mapID, kills = 0, quests = 0, deaths = 0,
			subs = sub and { [sub] = { t = 0, first = now, level = level } } or {} }
		if first and not rec.startedZone then rec.startedZone = zone end
		J:Log("zone", { begin = first or nil, zone = zone, subzone = sub })
		return
	end
	if sub and not place.subs[sub] then
		place.subs[sub] = { t = 0, first = now, level = level }
		J:Log("subzone", { zone = zone, subzone = sub })
	end
end

---------------------------------------------------------------------------
-- Deaths: PLAYER_DEAD also fires when you log in or reload while dead, so a
-- death counts only while you were alive.
---------------------------------------------------------------------------
local function DeadNow()
	local dead = Call(UnitIsDeadOrGhost, "player")
	if E:IsSecret(dead) then return st.dead end
	return dead and true or false
end

function R.OnDead()
	if st.dead then return end
	st.dead = true
	local rec = R.Rec()
	if not rec then return end
	local level = R.Level()
	local zone = R.Zone()
	rec.totals.deaths = (rec.totals.deaths or 0) + 1
	local row = R.LevelRec(rec, level)
	if row then
		row.deaths = row.deaths + 1
		if zone then row.deathZones[zone] = (row.deathZones[zone] or 0) + 1 end
	end
	local place = R.ZoneRec(rec, zone)
	if place then place.deaths = (tonumber(place.deaths) or 0) + 1 end
	J:Log("death", {})
end

---------------------------------------------------------------------------
-- Levels, XP and money
---------------------------------------------------------------------------
function R.OnLevelUp(level)
	level = Number(level)
	local rec = R.Rec()
	if not (rec and level) then return end
	st.lastLevelUp = GetTime()
	local zone = R.Zone()
	local now = R.Now()
	NoteOff(rec, level)
	if CharactersRecording() then return end
	-- The Characters level log is not recording: the journal keeps the row,
	-- with the ref the characters source uses, so the two never show twice.
	local row = R.LevelRec(rec, level)
	row.at, row.zone = now, zone
	local before = rec.levels[level - 1]
	local took = type(before) == "table" and tonumber(before.time) or nil
	J:Log("level", { level = level, took = took, zone = zone, ref = "characters:level:" .. level })
end

local function ReadXP()
	return Number(Call(UnitXP, "player")), Number(Call(UnitXPMax, "player")), R.Level()
end

function R.OnXP(unit)
	if unit ~= nil and unit ~= "player" then return end
	local xp, xpMax, level = ReadXP()
	if not (xp and xpMax and level) then return end
	local gained = 0
	if st.xpLevel and level > st.xpLevel and st.xpMax and st.xp then
		gained = (st.xpMax - st.xp) + xp
	elseif st.xp and level == st.xpLevel and xp > st.xp then
		gained = xp - st.xp
	elseif st.xp and level == st.xpLevel and xp < st.xp then
		return   -- the XP reset arrived before the level number
	end
	st.xp, st.xpMax, st.xpLevel = xp, xpMax, level
	if gained <= 0 then return end
	local rec = R.Rec()
	if rec then rec.totals.xp = (rec.totals.xp or 0) + gained end
end

-- Earned money: every gain, never the net (spending is not a loss here).
function R.OnMoney()
	local money = Number(Call(GetMoney))
	if not money then return end
	local before = st.money
	st.money = money
	if not before or money <= before then return end
	local rec = R.Rec()
	if not rec then return end
	local gained = money - before
	rec.totals.earned = (rec.totals.earned or 0) + gained
	local row = R.LevelRec(rec, R.Level())
	if row then row.earned = row.earned + gained end
end

---------------------------------------------------------------------------
-- Kills: the game's "Creatures killed" statistic, read out of combat. When
-- the client has none, the XP lines that name a creature count instead.
-- Creature names always come from those lines (creature goals).
---------------------------------------------------------------------------
local KILL_STAT_IDS = { 107, 1197 }

local function StatValue(id)
	local value = Call(GetStatistic, id)
	if E:IsSecret(value) then return nil end
	if type(value) == "number" then return value end
	if type(value) ~= "string" then return nil end
	return tonumber((value:gsub("%D", ""))) or 0   -- "--" before the first kill
end
R.StatValue = StatValue

-- The statistic's name comes in the client's language, so the known ids
-- are trusted whenever the client has them and they hold a value. The
-- English name is only the fallback for the scan of every category.
local function HasStat(id)
	local _, name = Call(GetAchievementInfo, id)
	return Text(name) ~= nil and StatValue(id) ~= nil
end

local function IsKillStat(id)
	local _, name = Call(GetAchievementInfo, id)
	name = Text(name)
	return name and name:lower():find("creatures killed", 1, true) and StatValue(id) ~= nil
end

function R.FindKillStat()
	if type(GetStatistic) ~= "function" then return nil end
	for _, id in ipairs(KILL_STAT_IDS) do
		if HasStat(id) then return id end
	end
	local categories = Call(GetStatisticsCategoryList)
	for _, category in ipairs(type(categories) == "table" and categories or {}) do
		for index = 1, Number(Call(GetCategoryNumAchievements, category)) or 0 do
			local id = Number((Call(GetAchievementInfo, category, index)))
			if id and IsKillStat(id) then return id end
		end
	end
	return nil
end

function J:KillStat()
	return st.killStat
end

local function AddKills(rec, count)
	if count <= 0 then return end
	rec.totals.kills = (tonumber(rec.totals.kills) or 0) + count
	local row = R.LevelRec(rec, R.Level())
	if row then row.kills = row.kills + count end
	local place = R.ZoneRec(rec, (R.Zone()))
	if place then place.kills = (tonumber(place.kills) or 0) + count end
	A:Fire("Kills", count)
end

function R.ReadKillStat()
	if not st.killStat or InCombatLockdown() then return end
	local now = StatValue(st.killStat)
	if not now then return end
	local before = st.statKills
	st.statKills = now
	local rec = R.Rec()
	-- A jump of a hundred or more is a statistic catching up, not kills.
	if rec and before and now > before and now - before < 100 then AddKills(rec, now - before) end
end

function R.OnXPLine(text)
	local fields = E.ChatParse and E.ChatParse:Parse("xpkill", text)
	local mob = fields and Text(fields.mob)
	if not mob then return end
	local rec = R.Rec()
	if not rec then return end
	local mobs = R.Map(rec, "mobs")
	mobs[mob] = (tonumber(mobs[mob]) or 0) + 1
	if not st.killStat then AddKills(rec, 1) end
end

function J:MobKills(name)
	local rec = S.Own()
	if not (rec and type(name) == "string") then return 0 end
	local mobs = type(rec.mobs) == "table" and rec.mobs or {}
	if mobs[name] then return mobs[name] end
	local folded = E:FoldText(name)
	for mob, count in pairs(mobs) do
		if E:FoldText(mob) == folded then return count end
	end
	return 0
end

---------------------------------------------------------------------------
-- Rested gained while you were away (shown when it is at least 5 % of a
-- level), sessions and the login catch-up
---------------------------------------------------------------------------
local function Rested()
	return Number(Call(GetXPExhaustion)) or 0
end

function R.CheckRested()
	local rec = R.Rec()
	if not rec then return end
	local now, max = Rested(), Number(Call(UnitXPMax, "player")) or 0
	local before = tonumber(rec.lastRested)
	rec.lastRested = now
	if not before or max <= 0 then return end
	if (now - before) / max * 100 >= 5 then
		J:Log("rested", { pct = floor(now / max * 100 + 0.5) })
	end
end

local function Played()
	local C = E.Characters
	local me = C and C.Get and C:Get(E.charKey)
	if not (me and C.Played) then return nil end
	local played = C:Played(me)
	return type(played) == "number" and floor(played) or nil
end

local function CompletedQuests()
	local list = C_QuestLog and Call(C_QuestLog.GetAllCompletedQuestIDs)
	if type(list) ~= "table" then return nil end
	return #list
end

-- What the game knew before the journal began (the story's "before").
local function Before(rec)
	if rec.questsBefore == nil and #rec.events <= 1 then rec.questsBefore = CompletedQuests() end
	if rec.playedBefore == nil and #rec.events <= 1 then rec.playedBefore = Played() end
end

function R.Login()
	local rec = R.Rec()
	st.loggedIn = true
	st.login = R.Now()
	st.playedIn = Played()
	st.dead = DeadNow()
	st.xp, st.xpMax, st.xpLevel = ReadXP()
	st.money = Number(Call(GetMoney))
	if rec then
		if not rec.startedZone then rec.startedZone = (R.Zone()) end
		Before(rec)
		NoteOff(rec)
	end
	R.EnterZone()
	C_Timer.After(3, function()
		st.killStat = R.FindKillStat()
		st.statKills = st.killStat and StatValue(st.killStat) or nil
	end)
	C_Timer.After(4, R.CheckRested)
end

function R.Logout()
	local rec = R.Rec()
	if not rec then return end
	rec.lastRested = Rested()
	if st.login then
		S.AddSession(rec, { login = st.login, logout = R.Now(), level = R.Level(), playedIn = st.playedIn, playedOut = Played() })
		st.login = nil
	end
end

---------------------------------------------------------------------------
-- Explored zones: the "Explore <zone>" achievements (English names are the
-- fallback; the achievement ids are looked up once, out of combat).
---------------------------------------------------------------------------
local exploreIDs

local function ExploreZone(name)
	return type(name) == "string" and name:match("^Explore (.+)$") or nil
end

function J:Explore(zone)
	if type(zone) ~= "string" or InCombatLockdown() then return nil end
	if type(GetCategoryList) ~= "function" or type(GetAchievementCriteriaInfo) ~= "function" then return nil end
	if not exploreIDs then
		exploreIDs = {}
		for _, category in ipairs(Call(GetCategoryList) or {}) do
			for index = 1, Number(Call(GetCategoryNumAchievements, category, true)) or 0 do
				local id, name = Call(GetAchievementInfo, category, index)
				local place = ExploreZone(Text(name))
				if place and Number(id) then exploreIDs[place] = Number(id) end
			end
		end
	end
	local id = exploreIDs[zone]
	if not id then return nil end
	local out = {}
	for index = 1, Number(Call(GetAchievementNumCriteria, id)) or 0 do
		local name, _, done = Call(GetAchievementCriteriaInfo, id, index)
		name = Text(name)
		if name then out[#out + 1] = { name = name, done = (not E:IsSecret(done) and done) and true or false } end
	end
	return out[1] and out or nil
end

function R.OnAchievement(id)
	id = Number(id)
	if not id then return end
	local _, name = Call(GetAchievementInfo, id)
	local zone = ExploreZone(Text(name))
	if not zone then return end
	if exploreIDs then exploreIDs[zone] = id end
	J:Log("explored", { zone = zone, subzone = false })
end

---------------------------------------------------------------------------
-- The bridges: Characters and Instances record while the journal does
---------------------------------------------------------------------------
-- The instances source reads the run store whenever runs are recorded,
-- also by the recorder alone (the Instances window off).
local function WidenInstancesSource()
	local source = J:Source("instances")
	if not source or source.widened then return end
	source.widened = true
	source.module = nil
	source.live = function() return InstancesRecording() end
end

function R.Bridges(on)
	local M = E.Instances
	if M and M.EnsureRecorder then M:EnsureRecorder("adventure", on and R.UseStores()) end
	local C = E.Characters
	-- Characters already caught up when its own module is on.
	if on and R.UseStores() and C and C.OnCharactersEnabled and not (C.Full and C:Full()) then C:OnCharactersEnabled() end
	J:Changed("characters")
	J:Changed("instances")
end

-- Options.lua may call this when "Use the Characters and Instances
-- records" changes (the ticker also notices within a second).
function A:StoresChanged()
	st.stores = R.UseStores()
	if self.started then R.Bridges(true) end
end

---------------------------------------------------------------------------
-- Part
---------------------------------------------------------------------------
local events = R.Events({
	PLAYER_ENTERING_WORLD = function() R.EnterZone() end,
	ZONE_CHANGED_NEW_AREA = function() R.EnterZone() end,
	ZONE_CHANGED = function() R.EnterZone() end,
	ZONE_CHANGED_INDOORS = function() R.EnterZone() end,
	PLAYER_DEAD = function() R.OnDead() end,
	PLAYER_ALIVE = function() st.dead = DeadNow() end,
	PLAYER_UNGHOST = function() st.dead = DeadNow() end,
	PLAYER_LEVEL_UP = function(level) R.OnLevelUp(level) end,
	PLAYER_XP_UPDATE = function(unit) R.OnXP(unit) end,
	PLAYER_MONEY = function() R.OnMoney() end,
	PLAYER_REGEN_ENABLED = function() R.ReadKillStat() end,
	CHAT_MSG_COMBAT_XP_GAIN = function(text) R.OnXPLine(text) end,
	ACHIEVEMENT_EARNED = function(id) R.OnAchievement(id) end,
	PLAYER_LOGOUT = function() R.Logout() end,
	PLAYER_LOGIN = function() if not st.loggedIn then R.Login() end end,
})
R.events = events

local ticker

A:AddPart("record", {
	order = 10,
	init = function()
		WidenInstancesSource()
	end,
	start = function()
		WidenInstancesSource()
		events.Start()
		-- Start from the current setting, so the first tick sees no change.
		st.stores = R.UseStores()
		if not ticker then ticker = C_Timer.NewTicker(1, R.Tick) end
		R.Bridges(true)
		if IsLoggedIn and IsLoggedIn() then R.Login() end
	end,
	stop = function()
		events.Stop()
		if ticker then
			ticker:Cancel()
			ticker = nil
		end
		st.loggedIn = false
		st.stores = nil
		R.Bridges(false)
	end,
})
