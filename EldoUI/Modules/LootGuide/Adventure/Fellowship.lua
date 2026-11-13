-- EldoUI My Adventure: the people you travel with.
--
-- Every five seconds you share a group the journal adds the time to each
-- member: when, where and at which levels you met, time together split
-- into dungeons, fighting, travel and town, the levels you gained side by
-- side, and the milestones of time together (1 h, 3 h, 10 h: the story's
-- "together" beats). Quests done together and runs together are joined
-- from the quest hand-ins and the Instances runs.
--
--   fellows[key] = { name, class, race, level, met, metLevel, metZone,
--                    metSub, theirMetLevel, time, split = { dungeon, fight,
--                    travel, town }, last, lowLevel, highLevel,
--                    steps = { { t, l, secs } }, runs, lastRun }
--                    (runs: how many of your journal's runs they were in,
--                    lastRun: the newest one's id; Runs.lua keeps both)
--   runExtras[runID].with = { [key] = true }   noted inside an Instances run;
--                    the journal's runs (Runs.lua) copy it when the run ends
--   questStart[questID].with = { [key] = true }   members on the quest while
--                    one of its objectives moved forward
-- Keys are J:Key(unit): "First Surname" on Forever, "-Realm" for another
-- realm. The source "fellowship" gives the Fellowship page and the
-- timeline its people and rows ("met", "together"); nothing is stored
-- twice.
--
-- Group members are told apart from you by UnitGUID, never by a raw
-- UnitIsUnit test; a name, class or GUID that is secret skips that member
-- for the tick.
--
-- Portions adapted from Forever Journal by Ugge Zen, MIT License (see
-- THIRD_PARTY_NOTICES.md): the companion record and its time split, the
-- quest partners and the progress watch.
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
local L = E.L
local Key = E.Key
local A = E.Adventure
local J = E.Journal
local S = A.Store
local R = A.Record

local Call, Text, Number = R.Call, R.Text, R.Number

local F = {}
A.Fellowship = F

F.TICK = 5
F.STEPS = { 3600, 3 * 3600, 10 * 3600 }   -- fallback when the story's Tuning is not loaded
F.WATCH_THROTTLE = 0.5

local function Steps()
	local tuning = E.Story and E.Story.Tuning
	return tuning and type(tuning.companionSteps) == "table" and tuning.companionSteps or F.STEPS
end

-- The group's other members as unit tokens, without you.
function F.Units()
	local out = {}
	local mine = Text(Call(UnitGUID, "player"))
	local raid = Call(IsInRaid)
	if not E:IsSecret(raid) and raid then
		for index = 1, Number(Call(GetNumGroupMembers)) or 0 do
			local unit = "raid" .. index
			local guid = Call(UnitGUID, unit)
			if not E:IsSecret(guid) and type(guid) == "string" and guid ~= mine then out[#out + 1] = unit end
		end
		return out
	end
	local group = Call(IsInGroup)
	if E:IsSecret(group) or not group then return out end
	for index = 1, 4 do
		local unit = "party" .. index
		local exists = Call(UnitExists, unit)
		if not E:IsSecret(exists) and exists then out[#out + 1] = unit end
	end
	return out
end

-- What this second is spent on.
function F.Activity()
	if R.Instance() then return "dungeon" end
	local fighting = Call(UnitAffectingCombat, "player")
	if not E:IsSecret(fighting) and fighting then return "fight" end
	local resting = Call(IsResting)
	if not E:IsSecret(resting) and resting then return "town" end
	return "travel"
end

function F.QuestPartners(questID)
	local out = {}
	local check = C_QuestLog and C_QuestLog.IsUnitOnQuest
	for _, unit in ipairs(F.Units()) do
		local key = J:Key(unit)
		if key then
			local on = true
			if check then on = Call(check, unit, questID) end
			if not E:IsSecret(on) and on then out[#out + 1] = key end
		end
	end
	return out
end

function F.GroupKeys()
	local out = {}
	for _, unit in ipairs(F.Units()) do
		local key = J:Key(unit)
		if key then out[#out + 1] = key end
	end
	return out
end

-- Companions are never let go by themselves, however many there are: a
-- name leaves only when you forget it (Runs.lua, with Undo). This only
-- counts them; S.CAP_FELLOWS no longer limits anything.
local function MakeRoom(rec)
	local count = 0
	for _ in pairs(type(rec) == "table" and type(rec.fellows) == "table" and rec.fellows or {}) do count = count + 1 end
	return count
end
F.MakeRoom = MakeRoom

local function Fellow(rec, key, unit, now, level)
	local fellow = rec.fellows[key]
	if type(fellow) ~= "table" then
		local zone, sub = R.Zone()
		fellow = { name = key, met = now, metLevel = level, metZone = R.Instance() or zone, metSub = sub, time = 0,
			split = { dungeon = 0, fight = 0, travel = 0, town = 0 }, steps = {}, theirMetLevel = Number(Call(UnitLevel, unit)) }
		rec.fellows[key] = fellow
		S.Bump(rec)
		J:Changed("fellowship")
	end
	if type(fellow.split) ~= "table" then fellow.split = { dungeon = 0, fight = 0, travel = 0, town = 0 } end
	if type(fellow.steps) ~= "table" then fellow.steps = {} end
	return fellow
end

function F.Tick(seconds)
	seconds = seconds or F.TICK
	local rec = R.Rec()
	if not rec then return end
	local units = F.Units()
	if not units[1] then return end
	local afk = Call(UnitIsAFK, "player")
	if not E:IsSecret(afk) and afk then return end
	local now, level, act = R.Now(), R.Level(), F.Activity()
	local M = E.Instances
	local run = M and M.current
	for _, unit in ipairs(units) do
		local key = J:Key(unit)
		if key then
			local fellow = Fellow(rec, key, unit, now, level)
			local _, class = Call(UnitClass, unit)
			class = Text(class)
			local race = Text((Call(UnitRace, unit)))
			local theirs = Number(Call(UnitLevel, unit))
			if class then fellow.class = class end
			if race then fellow.race = race end
			if theirs and theirs > 0 then fellow.level = theirs end
			local before = tonumber(fellow.time) or 0
			fellow.time = before + seconds
			fellow.split[act] = (tonumber(fellow.split[act]) or 0) + seconds
			fellow.last = now
			if level then
				fellow.lowLevel = math.min(fellow.lowLevel or level, level)
				fellow.highLevel = math.max(fellow.highLevel or level, level)
			end
			for _, step in ipairs(Steps()) do
				if before < step and fellow.time >= step then
					fellow.steps[#fellow.steps + 1] = { t = now, l = level, secs = step }
					S.Bump(rec)
					J:Changed("fellowship")
				end
			end
			if run and run.id and act == "dungeon" then
				local extras = rec.runExtras[run.id]
				if type(extras) ~= "table" then
					extras = {}
					rec.runExtras[run.id] = extras
				end
				extras.with = type(extras.with) == "table" and extras.with or {}
				extras.with[key] = true
			end
		end
	end
end

---------------------------------------------------------------------------
-- Quest progress: when a count goes up while you are grouped, everyone in
-- the group on that quest too did it with you. Throttled, never in combat.
---------------------------------------------------------------------------
local progress = {}
local watchQueued = false

function F.WatchProgress()
	watchQueued = false
	if InCombatLockdown() then return end
	local rec = R.Rec()
	if not rec or not F.Units()[1] then
		wipe(progress)
		return
	end
	local seen = {}
	for _, quest in ipairs(J:OpenQuests()) do
		local id = quest.questID
		seen[id] = true
		local now = quest.ready and math.max(quest.have, quest.need) + 1 or quest.have
		local before = progress[id]
		if before and now > before then
			local partners = F.QuestPartners(id)
			if partners[1] then
				local start = rec.questStart[id]
				if type(start) ~= "table" then
					start = {}
					rec.questStart[id] = start
				end
				start.with = type(start.with) == "table" and start.with or {}
				for _, key in ipairs(partners) do start.with[key] = true end
			end
		end
		progress[id] = now
	end
	for id in pairs(progress) do
		if not seen[id] then progress[id] = nil end
	end
end

local function QueueWatch()
	if watchQueued then return end
	watchQueued = true
	C_Timer.After(F.WATCH_THROTTLE, F.WatchProgress)
end

---------------------------------------------------------------------------
-- The source: people and rows for the pages and the timeline
---------------------------------------------------------------------------
local function Fellows(charKey)
	local rec = J:Char(charKey)
	return rec and rec.fellows or {}
end

J:RegisterSource("fellowship", {
	title = "Companions",
	scope = "char",
	kinds = { "met", "together" },
	live = function() return A:Running() end,
	read = function(charKey, from, to)
		local rows = {}
		for key, fellow in pairs(Fellows(charKey)) do
			if type(fellow) == "table" then
				local met = tonumber(fellow.met)
				if met and met >= from and met <= to then
					rows[#rows + 1] = { t = met, kind = "met", level = fellow.metLevel, zone = fellow.metZone, subzone = fellow.metSub,
						name = fellow.name or key, class = fellow.class, key = key, ref = "fellowship:met:" .. key }
				end
				for _, step in ipairs(type(fellow.steps) == "table" and fellow.steps or {}) do
					local t = tonumber(step.t)
					if t and t >= from and t <= to then
						rows[#rows + 1] = { t = t, kind = "together", level = step.l, zone = false, name = fellow.name or key,
							seconds = step.secs, key = key, ref = ("fellowship:together:%s:%s"):format(key, tostring(step.secs)) }
					end
				end
			end
		end
		return rows
	end,
	summarize = function(charKey)
		local count, top, topTime = 0, nil, 0
		for key, fellow in pairs(Fellows(charKey)) do
			if type(fellow) == "table" then
				count = count + 1
				local spent = tonumber(fellow.time) or 0
				if spent > topTime or (spent == topTime and top and key < top) then top, topTime = key, spent end
			end
		end
		return { fellows = count, topFellow = top, topFellowTime = topTime > 0 and topTime or nil }
	end,
	people = function(charKey)
		local list = {}
		for key, fellow in pairs(Fellows(charKey)) do
			if type(fellow) == "table" then
				list[#list + 1] = { key = key, name = fellow.name or key, class = fellow.class, race = fellow.race, level = fellow.level,
					met = fellow.met, metLevel = fellow.metLevel, metZone = fellow.metZone, time = fellow.time, last = fellow.last,
					split = fellow.split }
			end
		end
		return list
	end,
})

---------------------------------------------------------------------------
-- Part
---------------------------------------------------------------------------
local events = R.Events({
	QUEST_LOG_UPDATE = function() QueueWatch() end,
	UNIT_QUEST_LOG_CHANGED = function(unit) if unit == "player" then QueueWatch() end end,
	GROUP_ROSTER_UPDATE = function() QueueWatch() end,
})
F.events = events

local ticker

A:AddPart("fellowship", {
	order = 12,
	start = function()
		events.Start()
		if not ticker then ticker = C_Timer.NewTicker(F.TICK, function() F.Tick(F.TICK) end) end
	end,
	stop = function()
		events.Stop()
		if ticker then
			ticker:Cancel()
			ticker = nil
		end
		wipe(progress)
	end,
})
