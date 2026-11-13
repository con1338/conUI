-- EldoUI My Adventure: import from Forever Journal (its installed tables and FJ1: codes).
--
-- A player who switches from Forever Journal keeps every day of their
-- history. Forever Journal's saved data (FJ_Chars: every character's
-- journal, tagged with its GUID; FJ_Char: this character's; FJ_Backups:
-- its dated copies; FJ_DB: its settings) is there while that addon is
-- enabled, which is exactly when My Adventure stands back for the conflict.
-- So the import runs while the module is off too.
--
-- Read only: no Forever Journal table is ever written. Steps:
--   1. Scan: every journal tagged with its owner's GUID (FJ 1.3 and up).
--      Journals saved before 1.3 carry no tag and may belong to a namesake:
--      they are skipped and counted. A character whose journal is gone but
--      whose backup is there comes from its newest backup.
--   2. Each GUID finds its EldoUI character (this one, the Characters
--      records, or a journal tagged with it). Unknown GUIDs wait in
--      EldoUIDB.journalCache.pending and come in when that character logs in.
--   3. Map: every Forever Journal record gets its EldoUI home (I.Map): the
--      moments become packed rows of the same kinds (zone, dungeon, level,
--      death, goal, goalset, spell, recipe, profession, skill, rep, boss,
--      loot, mount, pet, respec, flight), the loot log becomes finds, and
--      levels, zones, dungeons, bosses, quests, quest starts, companions,
--      goals, notes, totals and named kills keep their numbers. Kills are
--      Forever Journal's own counts. Anything without a home is kept in
--      imported.extra / imported.unmapped, so nothing is lost. Its
--      dungeon history becomes runs in the journal's runs (Runs.lua),
--      which Undo takes out again.
--   4. Merge, never wipe (Backup.lua B.Merge). A backup of each journal is
--      taken first; "Undo the import" puts every touched journal back.
--      Running it twice adds nothing twice: rows match on what they say,
--      and everything up to the last import's newest moment is skipped.
--   5. Optionally its settings (I.TakeSettings). Then the player is told to
--      turn Forever Journal off in the AddOns list and reload (EldoUI never
--      turns another addon off).
--
-- FJ1: codes (Forever Journal's backup code) are read by I:ReadFJ1, adapted
-- from its data-only reader: no loadstring, at most 20 levels deep.
--
-- API (E.Adventure.Import):
--   I:Available()        Forever Journal's saved data is here
--   I:Loaded(), I:Version()
--   I:Scan() -> list, skipped     { guid, journal, from, charKey, name, level }
--   I:Preview() -> counts, text   what an import would bring
--   I:Run(opts) -> result         opts.settings = also take its settings
--   I:Start(opts, done)           the same as a sliced job (4 ms a frame)
--   I:Undo() -> ok, err           the last import, undone
--   I:CanUndo()
--   I:Offer()                     the login card (once)
--   I:Ask()                       the confirm with Import / Import with settings
--   I:AdoptPending()              journals waiting for this character
--   I.Map(fj, guid) -> journal    one Forever Journal journal in EldoUI's shape
--   I:ReadFJ1(text) -> payload | nil, err
--   I.DecodeFJ1(body) -> value | nil, err
--
-- Portions adapted from Forever Journal by Ugge Zen, MIT License (see
-- THIRD_PARTY_NOTICES.md): the saved-data layout and its GUID tags, the
-- untagged-journal rule, the line texts its moments carry, its settings
-- keys, and the data-only FJ1: reader (Kit.Decode).
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
local A = E.Adventure
local J = E.Journal
local S = A.Store
local B = A.Backup

local I = {}
A.Import = I

I.ADDON = "ForeverJournal"
I.TITLE = "Forever Journal" -- no-L (an addon's name)
I.MAX_DEPTH = 20
I.MAX_CODE = 4 * 1024 * 1024
I.CAP_PENDING = 10
I.CAP_UNMAPPED = 500
I.OFFER_DELAY = 6
I.ADOPT_DELAY = 3

local Copy = B.Copy

local function Now()
	return time()
end

local function Count(list)
	return type(list) == "table" and #list or 0
end

-- A plain, non-empty string (links and colors stripped when asked).
local function Str(value)
	if E:IsSecret(value) or type(value) ~= "string" or value == "" then return nil end
	return value
end

local function Unlink(text)
	text = Str(text)
	if not text then return nil end
	text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cnIQ%d:", ""):gsub("|r", ""):gsub("|H.-|h%[?(.-)%]?|h", "%1")
	text = strtrim(text)
	return text ~= "" and text or nil
end

local function Num(value)
	if E:IsSecret(value) then return nil end
	return tonumber(value)
end

local function Global(name)
	local value = rawget(_G, name)
	if E:IsSecret(value) then return nil end
	return value
end

---------------------------------------------------------------------------
-- Is it there?
---------------------------------------------------------------------------
function I:Loaded()
	local addons = C_AddOns
	if not (addons and addons.IsAddOnLoaded) then return false end
	local ok, loaded = pcall(addons.IsAddOnLoaded, I.ADDON)
	return ok and loaded and true or false
end

function I:Version()
	local addons = C_AddOns
	if not (addons and addons.GetAddOnMetadata) then return nil end
	local ok, version = pcall(addons.GetAddOnMetadata, I.ADDON, "Version")
	return ok and Str(version) or nil
end

function I:Available()
	return type(Global("FJ_Chars")) == "table" or type(Global("FJ_Char")) == "table" or type(Global("FJ_Backups")) == "table"
end

---------------------------------------------------------------------------
-- Scan: the tagged journals, by GUID
---------------------------------------------------------------------------
local function Tagged(journal, guid)
	if type(journal) ~= "table" or type(journal._owner) ~= "string" then return false end
	return guid == nil or journal._owner == guid
end

local function HasMoments(journal)
	return type(journal) == "table" and (Count(journal.events) > 0 or Count(journal.notes) > 0 or Count(journal.goals) > 0
		or Count(journal.quests) > 0 or Count(journal.loot) > 0)
end

local function Newer(a, b)
	return (tonumber(a and a._savedAt) or 0) > (tonumber(b and b._savedAt) or 0)
end

-- The EldoUI character a GUID belongs to.
local function CharKeyFor(guid)
	if type(guid) ~= "string" then return nil end
	if guid == S.MyGUID() then return E.charKey end
	local C = E.Characters
	for key, record in pairs(C and C.All and C:All() or {}) do
		if type(record) == "table" and record.guid == guid then return key end
	end
	for key, rec in pairs(S.Root() or {}) do
		if type(rec) == "table" and rec.guid == guid then return key end
	end
	return nil
end
I.CharKeyFor = CharKeyFor

local function TopLevel(journal)
	local top
	for level in pairs(type(journal.levels) == "table" and journal.levels or {}) do
		if type(level) == "number" and (not top or level > top) then top = level end
	end
	return top
end

function I:Scan()
	local byGuid, skipped = {}, 0
	local function Add(guid, journal, from)
		if not HasMoments(journal) then return end
		local have = byGuid[guid]
		if have and not Newer(journal, have.journal) then return end
		byGuid[guid] = { guid = guid, journal = journal, from = from }
	end
	local chars = Global("FJ_Chars")
	for key, journal in pairs(type(chars) == "table" and chars or {}) do
		if Tagged(journal, key) then
			Add(key, journal, "account")
		elseif type(journal) == "table" and next(journal) ~= nil and type(journal._owner) ~= "string" then
			skipped = skipped + 1   -- saved before 1.3: may belong to a namesake
		end
	end
	local char = Global("FJ_Char")
	if Tagged(char) then
		Add(char._owner, char, "character")
	elseif type(char) == "table" and next(char) ~= nil and type(char._owner) ~= "string" then
		skipped = skipped + 1
	end
	local backups = Global("FJ_Backups")
	for guid, list in pairs(type(backups) == "table" and backups or {}) do
		if type(guid) == "string" and not byGuid[guid] and type(list) == "table" then
			local newest = list[1]
			if type(newest) == "table" and HasMoments(newest.data) then
				byGuid[guid] = { guid = guid, journal = newest.data, from = "backup" }
			end
		end
	end
	local list = {}
	for guid, entry in pairs(byGuid) do
		entry.charKey = CharKeyFor(guid)
		local C = E.Characters
		local record = entry.charKey and C and C.Get and C:Get(entry.charKey)
		entry.name = type(record) == "table" and record.name or nil
		entry.level = TopLevel(entry.journal)
		list[#list + 1] = entry
	end
	table.sort(list, function(a, b)
		if (a.charKey == E.charKey) ~= (b.charKey == E.charKey) then return a.charKey == E.charKey end
		return tostring(a.guid) < tostring(b.guid)
	end)
	return list, skipped
end

-- counts = { characters, waiting, rows, quests, notes, goals, skipped }, text
function I:Preview()
	local list, skipped = self:Scan()
	local counts = { characters = #list, waiting = 0, rows = 0, quests = 0, notes = 0, goals = 0, skipped = skipped }
	for _, entry in ipairs(list) do
		local journal = entry.journal
		if not entry.charKey then counts.waiting = counts.waiting + 1 end
		counts.rows = counts.rows + Count(journal.events) + Count(journal.loot)
		counts.quests = counts.quests + Count(journal.quests)
		counts.notes = counts.notes + Count(journal.notes)
		counts.goals = counts.goals + Count(journal.goals)
	end
	local parts = {
		E:Plural(counts.characters, "%s character", "%s characters"):format(BreakUpLargeNumbers(counts.characters)),
		E:Plural(counts.rows, "%s moment", "%s moments"):format(BreakUpLargeNumbers(counts.rows)),
		E:Plural(counts.quests, "%s quest", "%s quests"):format(BreakUpLargeNumbers(counts.quests)),
		E:Plural(counts.notes, "%s note", "%s notes"):format(BreakUpLargeNumbers(counts.notes)),
		E:Plural(counts.goals, "%s goal", "%s goals"):format(BreakUpLargeNumbers(counts.goals)),
	}
	local text = table.concat(parts, ", ")
	if counts.waiting > 0 then
		text = text .. ". " .. E:Plural(counts.waiting, "%d character comes in when you next log it in", "%d characters come in when you next log them in"):format(counts.waiting)
	end
	if skipped > 0 then
		text = text .. ". " .. E:Plural(skipped, "%d journal from before Forever Journal 1.3 is left out (it may belong to a namesake)",
			"%d journals from before Forever Journal 1.3 are left out (they may belong to a namesake)"):format(skipped)
	end
	return counts, text .. "."
end

---------------------------------------------------------------------------
-- Map: one Forever Journal journal in EldoUI's shape
---------------------------------------------------------------------------
-- Standing labels (the game's, then English) -> 1..8.
local STANDING_EN = { Hated = 1, Hostile = 2, Unfriendly = 3, Neutral = 4, Friendly = 5, Honored = 6, Revered = 7, Exalted = 8 }
local function StandingIndex(label)
	label = Unlink(label)
	if not label then return nil end
	for index = 1, 8 do
		local game = Global("FACTION_STANDING_LABEL" .. index)
		if type(game) == "string" and game == label then return index end
	end
	return STANDING_EN[label]
end
I.StandingIndex = StandingIndex

local function ItemID(link)
	link = Str(link)
	return link and tonumber(link:match("|Hitem:(%d+)")) or nil
end

local function Key(name)
	name = Unlink(name)
	if not name then return nil end
	-- Older journals joined the first and last names with one hyphen.
	-- A name that already has a space may have a hyphenated last name.
	if not name:find(" ", 1, true) then name = name:gsub("%-", " ", 1) end
	return J:Key(name) or name
end

local function KeySet(set)
	if type(set) ~= "table" then return nil end
	local out, any = {}, false
	for name, on in pairs(set) do
		local key = on and Key(type(name) == "string" and name or nil)
		if key then
			out[key] = true
			any = true
		end
	end
	return any and out or nil
end

-- Each Forever Journal moment -> kind, fields (or nil: no home).
local EVENT = {}

EVENT.zone = function(e, text)
	local zone = Str(e.zone) or (text and (text:match("^The journal begins in (.+)$") or text:match("^New chapter: (.+)$")))
	return "zone", { zone = zone or false, begin = text and text:find("^The journal begins") and true or nil }
end
EVENT.dungeon = function(e, text)
	local name = text and text:match("^First time in (.+)$") or Str(e.zone)
	return "dungeon", { instance = name, zone = name or false }
end
EVENT.level = function(e, text, fj)
	local level = tonumber(text and text:match("level (%d+)")) or Num(e.level)
	local zone = text and text:match("^Reached level %d+ in (.+)$")
	if zone == "an unknown place" then zone = nil end
	local before = level and type(fj.levels) == "table" and fj.levels[level - 1]
	local took = type(before) == "table" and Num(before.time) or nil
	return "level", { level = level, zone = zone or Str(e.zone) or false, took = took and took > 0 and took or nil,
		ref = level and ("characters:level:" .. level) or nil }
end
EVENT.death = function()
	return "death", {}
end
EVENT.goal = function(e, text)
	return "goal", { name = text and text:match("^Goal reached: (.+)$") or text, keep = true }
end
EVENT.goalset = function(e, text)
	return "goalset", { name = text and text:match("^New goal: (.+)$") or text }
end
EVENT.spell = function(e, text)
	if not text then return nil end
	local name, rank = text:match("^Learned (.-) %((.-)%)$")
	if not name then name = text:match("^Learned (.+)$") end
	if not name then return nil end
	return "spell", { name = name, rank = rank }
end
EVENT.recipe = function(e, text)
	local name = text and text:match("^Recipe: (.+)$")
	if not name then return nil end
	return "recipe", { name = name }
end
EVENT.profession = function(e, text)
	local name = text and text:match("^Became a student of (.+)$")
	if not name then return nil end
	return "profession", { profession = name }
end
EVENT.skill = function(e, text)
	if not text then return nil end
	local mastered = text:match("^Mastered (.+)$")
	if mastered then
		local rank, max = (Str(e.sub) or ""):match("(%d+) of (%d+)")
		return "skill", { profession = mastered, rank = tonumber(rank), max = tonumber(max), mastered = true }
	end
	local trained = text:match("^Trained in (.+)$")
	if trained then return "skill", { profession = trained, rank = 1 } end
	local name, rank = text:match("^(.+) reached (%d+)$")
	if name then return "skill", { profession = name, rank = tonumber(rank), max = tonumber(rank) } end
	return nil
end
EVENT.rep = function(e, text)
	local faction, standing = Unlink(e.faction), e.standing
	if not faction and text then faction, standing = text:match("^(.+) now counts you as (.+)$") end
	if not faction then return nil end
	return "rep", { faction = faction, standing = StandingIndex(standing) }
end
EVENT.boss = function(e, text)
	local boss = Unlink(e.boss) or (text and text:match("^Defeated (.+)$"))
	if not boss then return nil end
	return "boss", { boss = boss, instance = Unlink(e.instance), first = e.first ~= false and true or nil, kills = Num(e.kills) or 1,
		keep = true }
end
EVENT.loot = function(e)
	local item = ItemID(e.link)
	if not item then return nil end
	return "loot", { item = item, quality = Num(e.quality), armor = Num(e.armor), from = Unlink(e.from) }
end
EVENT.mount = function(e, text)
	local name = text and text:match("^New mount: (.+)$")
	if not name then return nil end
	return "mount", { name = name }
end
EVENT.pet = function(e, text)
	local name = text and text:match("^New companion: (.+)$")
	if not name then return nil end
	return "pet", { name = name }
end
EVENT.respec = function(e, text)
	local points = tonumber(text and text:match("(%d+) talent"))
	if not points then return nil end
	return "respec", { points = points }
end
EVENT.flight = function(e, text)
	local place = text and text:match("^Flight path: (.+)$")
	return "flight", { place = place }
end
I.EVENT = EVENT

-- FJ goal kinds that count from the moment they were set: their progress
-- then, from FJ's totals.
local function GoalCount(goal, fj)
	local totals = type(fj.totals) == "table" and fj.totals or {}
	local base = Num(goal.base) or 0
	local kind = goal.kind
	local now
	if kind == "kills" or kind == "quests" or kind == "runs" or kind == "xp" then
		now = Num(totals[kind])
	elseif kind == "gold" then
		now = Num(totals.money)
	elseif kind == "dungeon" then
		local d = type(fj.dungeons) == "table" and fj.dungeons[goal.target]
		now = type(d) == "table" and Num(d.runs) or nil
	elseif kind == "creature" then
		now = type(fj.mobs) == "table" and Num(fj.mobs[goal.target]) or nil
	end
	if not now then return nil end
	return math.max(now - base, 0)
end

local function MapGoal(goal, fj)
	if type(goal) ~= "table" or type(goal.kind) ~= "string" then return nil end
	local out = { id = Num(goal.id), kind = goal.kind, need = math.max(Num(goal.need) or 1, 1), created = Num(goal.created) or Num(goal.t),
		done = goal.done and true or nil, doneAt = Num(goal.doneAt), archived = Num(goal.archived) or (goal.archived and Now()) or nil }
	local kind = goal.kind
	if kind == "item" then
		out.itemID, out.name = Num(goal.target), Unlink(goal.name)
	elseif kind == "dungeon" or kind == "creature" or kind == "zone" or kind == "skill" then
		out.target, out.name = Unlink(goal.target), Unlink(goal.target)
		if kind == "zone" then out.visited = goal.visited and true or nil end
	elseif kind == "todo" then
		out.name = Unlink(goal.label) or Unlink(goal.target)
	end
	local count = GoalCount(goal, fj)
	if count then out.count = count end
	return out
end

local function MapNote(note)
	if type(note) ~= "table" or not Str(note.text) then return nil end
	local x, y = Num(note.x), Num(note.y)
	local out = { id = Num(note.id), t = Num(note.t), text = note.text, zone = Str(note.zone), subzone = Str(note.subzone),
		level = Num(note.level), map = Num(note.mapID), x = x and x / 100 or nil, y = y and y / 100 or nil,
		pinned = note.pinned and true or nil, repeats = note.repeats and true or nil, done = note.done and true or nil,
		firedAt = Num(note.firedAt), archived = Num(note.archived) or (note.archived and Now()) or nil }
	if out.subzone == out.zone then out.subzone = nil end
	local trigger = note.trigger
	if type(trigger) == "table" and type(trigger.kind) == "string" then
		out.trigger = { kind = trigger.kind, target = Unlink(trigger.target), level = Num(trigger.level) }
		if not out.done then out.armedAt = out.t end
	end
	return out
end

local function MapQuest(quest)
	if type(quest) ~= "table" then return nil end
	local tag = Str(quest.kind)
	return {
		t = Num(quest.t), id = Num(quest.questID), title = Unlink(quest.title), tag = tag ~= "Normal" and tag or nil,
		z = Str(quest.zone), s = Str(quest.subzone), l = Num(quest.level), map = Num(quest.mapID), x = Num(quest.x), y = Num(quest.y),
		xp = Num(quest.xp), m = Num(quest.money), giver = Unlink(quest.giver), taker = Unlink(quest.taker),
		objective = Str(quest.objective), started = Num(quest.started), fromZone = Str(quest.fromZone), with = KeySet(quest.with),
		archived = Num(quest.archived) or (quest.archived and Now()) or nil,
	}
end

local function MapStart(start)
	if type(start) ~= "table" then return nil end
	return { t = Num(start.t), giver = Unlink(start.giver), z = Str(start.zone), s = Str(start.subzone), l = Num(start.level),
		x = Num(start.x), y = Num(start.y), objective = Str(start.objective), with = KeySet(start.with) }
end

local function MapFellow(name, fellow)
	if type(fellow) ~= "table" then return nil end
	local split = type(fellow.split) == "table" and fellow.split or {}
	return {
		name = Key(fellow.name) or name, class = Str(fellow.class), race = Str(fellow.race), level = Num(fellow.level),
		met = Num(fellow.met), metLevel = Num(fellow.metLevel), metZone = Str(fellow.metZone), metSub = Str(fellow.metSub),
		theirMetLevel = Num(fellow.theirMetLevel), time = Num(fellow.time) or 0, last = Num(fellow.last),
		lowLevel = Num(fellow.lowLevel), highLevel = Num(fellow.highLevel),
		split = { dungeon = Num(split.dungeon) or 0, fight = Num(split.fight) or 0, travel = Num(split.travel) or 0, town = Num(split.town) or 0 },
		steps = {}, runs = Copy(fellow.runs),
	}
end

-- Combine alias counters once within one imported journal. The ordinary
-- backup merge keeps later imports of the same journal idempotent.
local function AddFellowTime(a, b)
	local total = a + b
	if total ~= total or total == math.huge or total == -math.huge then
		error(L["A companion's recorded time is outside the supported range."], 0)
	end
	return total
end

local function MergeFellow(keep, alias)
	keep.time = AddFellowTime(keep.time, alias.time)
	for kind, seconds in pairs(alias.split) do keep.split[kind] = AddFellowTime(keep.split[kind], seconds) end
	if type(alias.runs) == "table" then
		if type(keep.runs) ~= "table" then keep.runs = {} end
		for key, run in pairs(alias.runs) do
			local current = keep.runs[key]
			if current == nil or (type(run) == "table" and type(current) ~= "table") then
				keep.runs[key] = Copy(run)
			elseif type(current) == "table" and type(run) == "table" then
				local seconds = AddFellowTime(Num(current.time) or 0, Num(run.time) or 0)
				B.MergeInto(current, run)
				current.time = seconds
			end
		end
	end
	if alias.met and (not keep.met or alias.met < keep.met) then
		for _, key in ipairs({ "met", "metLevel", "metZone", "metSub", "theirMetLevel" }) do keep[key] = alias[key] end
	end
	if alias.last and (not keep.last or alias.last > keep.last) then keep.last = alias.last end
	if alias.lowLevel then keep.lowLevel = math.min(keep.lowLevel or alias.lowLevel, alias.lowLevel) end
	if alias.highLevel then keep.highLevel = math.max(keep.highLevel or alias.highLevel, alias.highLevel) end
	for _, key in ipairs({ "class", "race", "level" }) do keep[key] = keep[key] or alias[key] end
end

-- Keys of a Forever Journal journal that have an EldoUI home below.
local HANDLED = { _owner = true, _legacy = true, _legacyAsked = true, _savedAt = true, _stamp = true, currentRun = true,
	lastRested = true, started = true, levels = true, zones = true, dungeons = true, events = true, loot = true, goals = true,
	notes = true, quests = true, questStart = true, questWith = true, subzones = true, totals = true, mobs = true, bosses = true,
	fellows = true, nextId = true }

-- fj: one Forever Journal journal. Returns the journal in EldoUI's shape
-- (Store.lua's record) and stats { rows, unmapped, newest }.
function I.Map(fj, guid)
	local rec = { v = S.SCHEMA, guid = guid, seq = 0, rev = 0, salt = 0, nextId = math.max(Num(fj.nextId) or 1, 1),
		started = Num(fj.started) }
	S.Migrate(rec)
	rec.started = Num(fj.started) or rec.started
	local stats = { rows = 0, unmapped = 0, newest = 0 }
	local imported = { from = "ForeverJournal", extra = {}, unmapped = {}, dungeons = {}, totals = {} }
	rec.imported = imported
	local function Seen(t)
		t = tonumber(t)
		if t and t > stats.newest then stats.newest = t end
	end
	local function Row(kind, fields, e)
		fields.kind = kind
		fields.t = Num(e.t)
		if not fields.t then return nil end
		if fields.level == nil then fields.level = Num(e.level) end
		if fields.zone == nil then fields.zone = Unlink(e.zone) end
		if fields.zone == false then fields.zone = nil end
		if fields.subzone == nil then fields.subzone = Unlink(e.subzone) end
		if fields.subzone == fields.zone then fields.subzone = nil end
		if e.keep then fields.keep = true end
		local ref = fields.ref
		fields.ref = nil
		rec.seq = rec.seq + 1
		fields.seq = rec.seq
		rec.events[#rec.events + 1] = S.Pack(rec, fields)
		if ref and rec.refs[ref] == nil then rec.refs[ref] = fields.seq end
		stats.rows = stats.rows + 1
		Seen(fields.t)
		return fields
	end

	-- Goals and notes (ids kept: rows name them).
	local goalByLabel = {}
	for _, goal in ipairs(type(fj.goals) == "table" and fj.goals or {}) do
		local mapped = MapGoal(goal, fj)
		if mapped then
			if not mapped.id then mapped.id = S.NewId(rec) end
			rec.goals[#rec.goals + 1] = mapped
			if Str(goal.label) then goalByLabel[goal.label] = mapped.id end
			Seen(mapped.created)
		end
		A.JobYield()
	end
	for _, note in ipairs(type(fj.notes) == "table" and fj.notes or {}) do
		local mapped = MapNote(note)
		if mapped then
			if not mapped.id then mapped.id = S.NewId(rec) end
			rec.notes[#rec.notes + 1] = mapped
			Seen(mapped.t)
		end
		A.JobYield()
	end

	-- The loot log: every find of uncommon and up.
	local lootSeen = {}
	for _, find in ipairs(type(fj.loot) == "table" and fj.loot or {}) do
		local item = type(find) == "table" and ItemID(find.link)
		if item and Num(find.t) then
			lootSeen[tostring(find.t) .. ":" .. item] = true
			Row("loot", { item = item, quality = Num(find.quality), armor = Num(find.armor), from = Unlink(find.from) }, find)
		end
		A.JobYield()
	end

	-- Moments.
	local bossFirst = {}
	for _, e in ipairs(type(fj.events) == "table" and fj.events or {}) do
		if type(e) == "table" and Num(e.t) then
			local map = EVENT[e.kind]
			local kind, fields
			if map then kind, fields = map(e, Unlink(e.text), fj) end
			if kind == "loot" and lootSeen[tostring(e.t) .. ":" .. tostring(fields.item)] then
				kind = "skip"
			end
			if kind == "goal" or kind == "goalset" then fields.goal = fields.name and goalByLabel[fields.name] end
			if kind == "boss" and fields.boss and not bossFirst[fields.boss] then
				bossFirst[fields.boss] = { t = Num(e.t), instance = fields.instance }
			end
			if kind and kind ~= "skip" then
				Row(kind, fields, e)
			elseif not kind then
				stats.unmapped = stats.unmapped + 1
				if #imported.unmapped < I.CAP_UNMAPPED then imported.unmapped[#imported.unmapped + 1] = Copy(e) end
				Seen(e.t)
			end
		end
		A.JobYield()
	end
	-- Pinned notes show on the Journey through a "note" row.
	for _, note in ipairs(rec.notes) do
		if note.pinned and note.t then
			local row = Row("note", { note = note.id, level = note.level, zone = note.zone or false, subzone = note.subzone, keep = true },
				{ t = note.t })
			note.row = row and row.seq or nil
		end
	end

	-- Levels, zones, dungeons.
	for level, info in pairs(type(fj.levels) == "table" and fj.levels or {}) do
		if type(level) == "number" and type(info) == "table" then
			rec.levels[level] = {
				time = Num(info.time) or 0, kills = Num(info.kills) or 0, quests = Num(info.quests) or 0, deaths = Num(info.deaths) or 0,
				earned = 0, zones = Copy(info.zones) or {}, deathZones = Copy(info.deathZones) or {},
				at = Num(info.reached), zone = Str(info.reachedZone),
			}
		end
	end
	local dungeons = type(fj.dungeons) == "table" and fj.dungeons or {}
	for name, info in pairs(type(fj.zones) == "table" and fj.zones or {}) do
		if type(name) == "string" and type(info) == "table" and not dungeons[name] then
			local subs = {}
			for sub, spot in pairs(type(info.subs) == "table" and info.subs or {}) do
				if type(sub) == "string" and type(spot) == "table" then
					subs[sub] = { t = Num(spot.time) or 0, first = Num(spot.first), level = Num(spot.level) }
				end
			end
			rec.zones[name] = { t = Num(info.time) or 0, first = Num(info.first), firstLevel = Num(info.firstLevel),
				kills = Num(info.kills) or 0, quests = Num(info.quests) or 0, deaths = Num(info.deaths) or 0, subs = subs }
		end
	end
	local seenInstances = {}
	for name, info in pairs(dungeons) do
		if type(name) == "string" and type(info) == "table" then
			if Num(info.first) then seenInstances[name] = Num(info.first) end
			imported.dungeons[name] = Copy(info)
		end
	end
	if next(seenInstances) then rec.instancesSeen = seenInstances end

	-- Bosses: Forever Journal kept them by name ("name:<boss>" here, until
	-- a kill with an encounter id adopts the entry, Chronicle.lua).
	for name, kills in pairs(type(fj.bosses) == "table" and fj.bosses or {}) do
		if type(name) == "string" then
			local first = bossFirst[name] or {}
			rec.bosses["name:" .. name] = { name = name, kills = Num(kills) or 1, first = first.t, instance = first.instance }
		end
	end

	-- Quests and where they came from.
	for _, quest in ipairs(type(fj.quests) == "table" and fj.quests or {}) do
		local mapped = MapQuest(quest)
		if mapped and mapped.t then
			rec.quests[#rec.quests + 1] = mapped
			Seen(mapped.t)
		end
		A.JobYield()
	end
	table.sort(rec.quests, function(a, b) return (a.t or 0) < (b.t or 0) end)
	while #rec.quests > S.CAP_QUESTS do table.remove(rec.quests, 1) end
	for questID, start in pairs(type(fj.questStart) == "table" and fj.questStart or {}) do
		local id = Num(questID)
		local mapped = id and MapStart(start)
		if mapped then rec.questStart[id] = mapped end
	end
	local leftWith = {}
	for questID, names in pairs(type(fj.questWith) == "table" and fj.questWith or {}) do
		local id, set = Num(questID), KeySet(names)
		if id and set then
			local start = rec.questStart[id]
			if start then
				start.with = start.with or {}
				for key in pairs(set) do start.with[key] = true end
			else
				leftWith[id] = set
			end
		end
	end
	if next(leftWith) then imported.extra.questWith = leftWith end

	-- Companions.
	local names = {}
	local fellows = type(fj.fellows) == "table" and fj.fellows or {}
	for name in pairs(fellows) do if Str(name) then names[#names + 1] = name end end
	-- Keep the current spelling's descriptive fields, then fold legacy aliases.
	table.sort(names, function(a, b)
		local aCurrent, bCurrent = a:find(" ", 1, true) ~= nil, b:find(" ", 1, true) ~= nil
		if aCurrent ~= bCurrent then return aCurrent end
		return a < b
	end)
	for _, name in ipairs(names) do
		local key = Key(name)
		local mapped = key and MapFellow(key, fellows[name])
		if mapped then
			if rec.fellows[key] then MergeFellow(rec.fellows[key], mapped) else rec.fellows[key] = mapped end
		end
	end

	-- Totals and named kills (Forever Journal's own counts).
	local totals = type(fj.totals) == "table" and fj.totals or {}
	rec.totals.deaths = Num(totals.deaths) or 0
	rec.totals.xp = Num(totals.xp) or 0
	rec.totals.earned = Num(totals.money) or 0
	rec.totals.time = Num(totals.time) or 0
	rec.totals.kills = Num(totals.kills) or 0
	imported.totals = { quests = Num(totals.quests), runs = Num(totals.runs) }
	local mobs = {}
	for name, kills in pairs(type(fj.mobs) == "table" and fj.mobs or {}) do
		if type(name) == "string" and Num(kills) then mobs[name] = Num(kills) end
	end
	if next(mobs) then rec.mobs = mobs end
	if type(fj.subzones) == "table" then imported.extra.subzones = Copy(fj.subzones) end

	-- Anything else: kept as it was.
	for key, value in pairs(fj) do
		if type(key) == "string" and not HANDLED[key] then imported.extra[key] = Copy(value) end
	end
	if not next(imported.extra) then imported.extra = nil end
	if not imported.unmapped[1] then imported.unmapped = nil end
	if not next(imported.dungeons) then imported.dungeons = nil end

	-- Rows in time order.
	local heads = {}
	for _, packed in ipairs(rec.events) do
		local t, seq = S.Head(packed)
		heads[packed] = { t or 0, seq or 0 }
	end
	table.sort(rec.events, function(a, b)
		local x, y = heads[a], heads[b]
		if x[1] ~= y[1] then return x[1] < y[1] end
		return x[2] < y[2]
	end)
	rec.nextId = math.max(rec.nextId, (Num(fj.nextId) or 1))
	return rec, stats
end

---------------------------------------------------------------------------
-- Settings (optional): Forever Journal's FJ_DB -> E.db.modules.Adventure.
-- Not taken: its page style, font, toast and tracker positions (EldoUI
-- owns looks and movers) and its sound picks (other sounds).
---------------------------------------------------------------------------
local MOMENT_KEYS = { momentZone = "zone", momentLevel = "level", momentDungeon = "dungeon", momentGoal = "goal", momentRested = "rested" }
I.SETTING_KEYS = { "detail", "show", "lootMin", "lootArmor", "fleetingMinutes", "questRewards", "foldChapters", "questGroup",
	"archiveReminders", "archiveGoals", "pinNewNotes", "moments", "momentKinds", "momentSeconds", "reminderSeconds",
	"trackerGoals", "trackerGoalsMax", "trackerReminders", "trackerRemindersMax", "minimap", "backupEvery", "backupKeep",
	"soundMaster", "sounds" }

function I.TakeSettings(fjdb, db)
	db = db or A.db
	if type(fjdb) ~= "table" or type(db) ~= "table" then return 0 end
	local taken = 0
	local function Set(key, value)
		if E:IsSecret(value) or type(value) == "nil" then return end
		db[key] = value
		taken = taken + 1
	end
	local function Bool(value) if type(value) == "boolean" then return value end end
	if fjdb.detail == "essentials" or fjdb.detail == "story" or fjdb.detail == "chronicler" or fjdb.detail == "custom" then Set("detail", fjdb.detail) end
	if type(fjdb.show) == "table" then
		local show = {}
		for key, value in pairs(fjdb.show) do
			if key == "lootMin" then Set("lootMin", Num(value))
			elseif key == "repMin" then Set("repMin", value == "honored" and "honored" or "all")
			elseif type(key) == "string" and type(value) == "boolean" then show[key] = value end
		end
		Set("show", show)
	end
	if type(fjdb.lootArmor) == "table" then
		local armor = {}
		for key, value in pairs(fjdb.lootArmor) do if Num(key) and value == false then armor[Num(key)] = false end end
		Set("lootArmor", armor)
	end
	Set("fleetingMinutes", Num(fjdb.fleetingMinutes))
	Set("questRewards", Bool(fjdb.questRewards))
	Set("foldChapters", Bool(fjdb.foldChapters))
	if fjdb.questGroup == "day" or fjdb.questGroup == "zone" or fjdb.questGroup == "level" then Set("questGroup", fjdb.questGroup) end
	Set("archiveReminders", Bool(fjdb.archiveReminders))
	Set("archiveGoals", Bool(fjdb.archiveGoals))
	Set("pinNewNotes", Bool(fjdb.autoPin))
	Set("moments", Bool(fjdb.moments))
	local kinds = CopyTable(type(db.momentKinds) == "table" and db.momentKinds or {})
	local any = false
	for fjKey, ours in pairs(MOMENT_KEYS) do
		if type(fjdb[fjKey]) == "boolean" then
			kinds[ours] = fjdb[fjKey]
			any = true
		end
	end
	if any then Set("momentKinds", kinds) end
	Set("momentSeconds", Num(fjdb.momentSeconds))
	Set("reminderSeconds", Num(fjdb.reminderSeconds))
	Set("trackerGoals", Bool(fjdb.tracker))
	Set("trackerGoalsMax", Num(fjdb.trackerMax))
	Set("trackerReminders", Bool(fjdb.trackerReminders))
	Set("trackerRemindersMax", Num(fjdb.trackerReminderMax))
	Set("minimap", Bool(fjdb.minimap))
	if fjdb.backupEvery == "off" then Set("backupEvery", "manual")
	elseif fjdb.backupEvery == "login" or fjdb.backupEvery == "day" or fjdb.backupEvery == "week" then Set("backupEvery", fjdb.backupEvery) end
	Set("backupKeep", Num(fjdb.backupKeep))
	Set("soundMaster", Bool(fjdb.soundMaster))
	if fjdb.sounds == false then
		local sounds = CopyTable(type(db.sounds) == "table" and db.sounds or {})
		for key in pairs(sounds) do sounds[key] = "none" end
		Set("sounds", sounds)
	end
	if A.Sanitize then A.Sanitize(db) end
	return taken
end

---------------------------------------------------------------------------
-- Run
---------------------------------------------------------------------------
local function Cache()
	return S.Cache()
end

local function NewRecord(guid)
	return S.Migrate({ v = S.SCHEMA, guid = guid, started = Now(), seq = 0, rev = 0, salt = 0, nextId = 1 })
end

local function HighWater(rec)
	local imported = type(rec.imported) == "table" and rec.imported or nil
	return imported and imported.from == "ForeverJournal" and tonumber(imported.lastT) or 0
end

-- The highest level a journal reached (for the roll-up of another character).
local function JournalLevel(rec)
	local top = 1
	for level in pairs(rec.levels or {}) do
		if type(level) == "number" and level > top then top = level end
	end
	return top
end

-- One journal into one character. Returns stats.
local function ImportInto(charKey, guid, fj, session)
	local root = S.Root()
	local before = root[charKey]
	if type(before) == "table" and B.HasData(before) then
		local entry = B:Take("before importing", charKey)
		session.chars[charKey] = entry and entry.at or false
	elseif type(before) == "table" then
		-- A journal with nothing in it yet: Undo gives back an empty one.
		session.chars[charKey] = "empty"
	else
		session.chars[charKey] = false
	end
	local theirs, mapStats = I.Map(fj, guid)
	local dst = charKey == E.charKey and S.Own() or root[charKey]
	if type(dst) ~= "table" then
		dst = NewRecord(guid)
		root[charKey] = dst
	end
	local mark = HighWater(dst)
	local function Old(t) return mark > 0 and (tonumber(t) or 0) <= mark end
	local stats = B.Merge(dst, theirs, {
		skip = function(row) return Old(row.t) end,
		skipEntry = function(kind, entry)
			if kind == "goals" then return Old(entry.created) end
			return Old(entry.t)
		end,
	})
	if #dst.events > S.CAP_EVENTS then
		S.Rollup(dst, A.JobYield, JournalLevel(dst))
		S.Trim(dst)
	end
	local imported = type(dst.imported) == "table" and dst.imported or {}
	dst.imported = imported
	imported.from = "ForeverJournal"
	imported.version = session.version
	imported.at = session.at
	imported.rows = (tonumber(imported.rows) or 0) + stats.rows
	imported.lastT = math.max(mark, mapStats.newest)
	S.Bump(dst)
	stats.unmapped = mapStats.unmapped
	-- Its dungeon history: runs in the journal's runs (Runs.lua).
	local Runs = A.Runs
	if Runs and Runs.ImportHistory then
		stats.runs = Runs:ImportHistory(charKey, fj.dungeons, session.at)
		session.runs = session.runs or {}
		if stats.runs > 0 then session.runs[charKey] = stats.runs end
	end
	return stats
end

-- result = { characters, waiting, rows, quests, notes, goals, skipped, settings }
function I:Run(opts)
	opts = opts or {}
	local list, skipped = self:Scan()
	local result = { characters = 0, waiting = 0, rows = 0, quests = 0, notes = 0, goals = 0, skipped = skipped, unmapped = 0 }
	if not list[1] then return nil, L["No Forever Journal journal to import. Its saved data loads only while Forever Journal is enabled."] end
	if not (S.Root() and E.charKey) then return nil, L["The journal is not ready yet. Try again in a moment."] end
	local cache = Cache()
	local session = { at = Now(), version = self:Version(), chars = {}, pending = {} }
	for _, entry in ipairs(list) do
		if entry.charKey then
			local stats = ImportInto(entry.charKey, entry.guid, entry.journal, session)
			result.characters = result.characters + 1
			result.rows = result.rows + stats.rows
			result.quests = result.quests + stats.quests
			result.notes = result.notes + stats.notes
			result.goals = result.goals + stats.goals
			result.unmapped = result.unmapped + (stats.unmapped or 0)
		else
			local waiting = 0
			for _ in pairs(cache.pending) do waiting = waiting + 1 end
			if cache.pending[entry.guid] or waiting < I.CAP_PENDING then
				local copy = {}
				for key, value in pairs(entry.journal) do
					if key ~= "_legacy" and key ~= "currentRun" then copy[key] = Copy(value) end
				end
				cache.pending[entry.guid] = { at = session.at, version = session.version, from = "ForeverJournal", journal = copy }
				session.pending[entry.guid] = true
				result.waiting = result.waiting + 1
			end
		end
		A.JobYield()
	end
	if opts.settings then
		local fjdb = Global("FJ_DB")
		if type(fjdb) == "table" and A.db then
			local old = {}
			for _, key in ipairs(I.SETTING_KEYS) do old[key] = Copy(A.db[key]) end
			session.settings = old
			result.settings = I.TakeSettings(fjdb, A.db)
		end
	end
	cache.lastImport = session
	cache.importOffered = true
	B.Changed()
	A:Fire("Imported", result)
	return result
end

-- The same as a sliced job (4 ms a frame, paused in combat).
function I:Start(opts, done)
	local result, err
	return A:RunJob("import", function()
		result, err = I:Run(opts)
	end, function(ok, why)
		if type(done) == "function" then done(ok and result or nil, ok and err or why) end
	end)
end

function I:CanUndo()
	return type(Cache().lastImport) == "table"
end

function I:Undo()
	local cache = Cache()
	local session = cache.lastImport
	if type(session) ~= "table" then return false, L["There is no import to undo."] end
	local root = S.Root()
	for charKey, at in pairs(session.chars or {}) do
		if at == false then
			if root then root[charKey] = nil end
		elseif at == "empty" then
			local had = root and root[charKey]
			if root then root[charKey] = NewRecord(type(had) == "table" and had.guid or nil) end
		else
			local found
			for _, entry in ipairs(B:List(charKey)) do
				if entry.at == at and entry.reason == "before importing" then found = entry break end
			end
			local data = found and B:Read(found.data)
			if data then B.ReplaceRecord(charKey, data.journal) end
		end
	end
	for guid in pairs(session.pending or {}) do cache.pending[guid] = nil end
	local Runs = A.Runs
	for charKey in pairs(type(session.runs) == "table" and session.runs or {}) do
		if Runs and Runs.RemoveImported then Runs:RemoveImported(charKey, session.at) end
	end
	if type(session.settings) == "table" and A.db then
		for _, key in ipairs(I.SETTING_KEYS) do A.db[key] = Copy(session.settings[key]) end
		if A.Sanitize then A.Sanitize(A.db) end
	end
	cache.lastImport = nil
	B.Changed()
	return true
end

-- Journals that waited for this character: in they come (backup first).
function I:AdoptPending()
	local guid = S.MyGUID()
	local cache = Cache()
	local waiting = guid and cache.pending[guid]
	if type(waiting) ~= "table" or type(waiting.journal) ~= "table" then return nil end
	if not (S.Root() and E.charKey and S.Own()) then return nil end
	local session = { at = Now(), version = waiting.version, chars = {}, pending = {} }
	local stats = ImportInto(E.charKey, guid, waiting.journal, session)
	cache.pending[guid] = nil
	B.Changed()
	E:Print((L["Your Forever Journal history for this character is now in My Adventure (%s)."]):format(
		E:Plural(stats.rows, "%s moment", "%s moments"):format(BreakUpLargeNumbers(stats.rows))))
	return stats
end

---------------------------------------------------------------------------
-- Asking: the login card (once) and the confirm on the options page
---------------------------------------------------------------------------
local function Done(result, err)
	if not result then
		E:Print(tostring(err))
		return
	end
	local parts = {
		E:Plural(result.characters, "%s character", "%s characters"):format(BreakUpLargeNumbers(result.characters)),
		E:Plural(result.rows, "%s moment", "%s moments"):format(BreakUpLargeNumbers(result.rows)),
		E:Plural(result.quests, "%s quest", "%s quests"):format(BreakUpLargeNumbers(result.quests)),
	}
	local text = (L["Imported from Forever Journal: %s."]):format(table.concat(parts, ", "))
	if result.waiting > 0 then
		text = text .. " " .. E:Plural(result.waiting, "%d more comes in when you log that character in.", "%d more come in when you log those characters in."):format(result.waiting)
	end
	E:Print(text)
	A:PushAlert({
		key = "adventure-import", icon = "Interface/Icons/INV_Misc_Book_09", title = L["Forever Journal imported"],
		text = text .. " " .. L["Turn Forever Journal off in the AddOns list and reload, so the two journals do not both write."],
		actions = { { label = L["Undo"], func = function() I:Undo() E:Print(L["The import is undone."]) end }, { label = L["OK"] } },
	})
end
I.Done = Done

function I:Ask()
	if not self:Available() then
		E:Print(L["No Forever Journal journal to import. Its saved data loads only while Forever Journal is enabled."])
		return nil
	end
	local _, preview = self:Preview()
	local text = L["Bring your Forever Journal history into My Adventure?"] .. "\n\n" .. preview .. "\n\n"
		.. L["Nothing is lost: it merges with what My Adventure has, a backup is taken first, and Undo puts it back. Forever Journal's own data is only read, never changed."]
	if Cache().lastImport then text = text .. "\n\n" .. L["You imported before: only what is new since then comes in."] end
	return E:ShowConfirm({ key = "ELDOUI_JOURNAL_IMPORT", title = L["My Adventure"], text = text, accept = L["Import"],
		extra = { L["Import with its settings"], function() I:Start({ settings = true }, Done) end },
		onAccept = function() I:Start({ settings = false }, Done) end })
end

function I:Offer()
	local cache = Cache()
	if cache.importOffered or not self:Available() then return nil end
	cache.importOffered = true
	local _, preview = self:Preview()
	return A:PushAlert({
		key = "adventure-import-offer", icon = "Interface/Icons/INV_Misc_Book_09", title = L["Forever Journal is loaded"],
		text = L["Bring its journals into EldoUI?"] .. " " .. preview,
		actions = {
			{ label = L["Import"], func = function() I:Start({ settings = false }, Done) end },
			{ label = L["Not now"] },
		},
	})
end

---------------------------------------------------------------------------
-- FJ1: codes. Adapted from Forever Journal's data-only reader: quoted
-- strings, numbers, true/false and tables, at most 20 levels deep. Nothing
-- in the text is ever run.
---------------------------------------------------------------------------
function I.DecodeFJ1(s)
	if type(s) ~= "string" then return nil, "nothing to read" end
	if #s > I.MAX_CODE then return nil, "too long" end
	local pos = 1
	local function Space() pos = s:find("[^%s]", pos) or #s + 1 end
	local value
	local function Text()
		local quote = s:sub(pos, pos)
		pos = pos + 1
		local out = {}
		while pos <= #s do
			local ch = s:sub(pos, pos)
			if ch == quote then
				pos = pos + 1
				return table.concat(out)
			end
			if ch == "\\" then
				local nextChar = s:sub(pos + 1, pos + 1)
				local digits = s:match("^%d%d?%d?", pos + 1)
				if digits then
					out[#out + 1] = string.char(tonumber(digits) % 256)
					pos = pos + 1 + #digits
				else
					out[#out + 1] = ({ n = "\n", t = "\t", r = "\r" })[nextChar] or nextChar
					pos = pos + 2
				end
			else
				out[#out + 1] = ch
				pos = pos + 1
			end
		end
		error("unfinished text")
	end
	function value(depth)
		if depth > I.MAX_DEPTH then error("too deep") end
		Space()
		local ch = s:sub(pos, pos)
		if ch == "{" then
			pos = pos + 1
			local t, index = {}, 1
			while true do
				Space()
				if pos > #s then error("unfinished table") end
				if s:sub(pos, pos) == "}" then
					pos = pos + 1
					return t
				end
				local key
				if s:sub(pos, pos) == "[" then
					pos = pos + 1
					key = value(depth + 1)
					Space()
					if s:sub(pos, pos) ~= "]" then error("expected ]") end
					pos = pos + 1
					Space()
					if s:sub(pos, pos) ~= "=" then error("expected =") end
					pos = pos + 1
					if type(key) ~= "string" and type(key) ~= "number" then error("bad key") end
				else
					local name = s:match("^[%a_][%w_]*", pos)
					if name and name ~= "true" and name ~= "false" and s:match("^%s*=", pos + #name) then
						key = name
						pos = s:find("=", pos + #name, true) + 1
					end
				end
				local item = value(depth + 1)
				if key == nil then
					t[index] = item
					index = index + 1
				else
					t[key] = item
				end
				Space()
				local sep = s:sub(pos, pos)
				if sep == "," or sep == ";" then
					pos = pos + 1
				elseif sep ~= "}" then
					error("expected , or }")
				end
			end
		elseif ch == "\"" or ch == "'" then
			return Text()
		elseif s:match("^true", pos) then
			pos = pos + 4
			return true
		elseif s:match("^false", pos) then
			pos = pos + 5
			return false
		end
		local number = s:match("^-?%d+%.?%d*[eE]?[-+]?%d*", pos)
		if number and number ~= "" and tonumber(number) then
			pos = pos + #number
			return tonumber(number)
		end
		error("unexpected " .. (ch ~= "" and ch or "end"))
	end
	local ok, result = pcall(value, 0)
	if not ok then return nil, tostring(result):gsub("^.-:%d+: ", "") end
	Space()
	if pos <= #s then return nil, "extra text after the end" end
	return result
end

-- A pasted FJ1: code -> { at, who, journal, fj = true } or nil and why.
function I:ReadFJ1(text)
	local body = type(text) == "string" and text:match("^%s*FJ1:(.-)%s*$")
	if not body then return nil, L["That is not a Forever Journal backup code (it starts with FJ1:)."] end
	local value = I.DecodeFJ1(body)
	if type(value) ~= "table" or type(value.data) ~= "table" or type(value.data.events) ~= "table" then
		return nil, L["The code is incomplete or damaged. Copy all of it, from FJ1: to the last }."]
	end
	local journal = I.Map(value.data, S.MyGUID())
	return {
		at = Num(value.at), fj = true, journal = journal,
		who = { name = Unlink(value.name), class = Str(value.class), race = Str(value.race), level = Num(value.level) },
	}
end

---------------------------------------------------------------------------
-- Part: at login (also while the module stands back for Forever Journal)
---------------------------------------------------------------------------
local login = CreateFrame("Frame")
login:SetScript("OnEvent", function(self)
	self:UnregisterAllEvents()
	C_Timer.After(I.ADOPT_DELAY, function()
		local ok, err = pcall(I.AdoptPending, I)
		if not ok then geterrorhandler()(err) end
	end)
	C_Timer.After(I.OFFER_DELAY, function()
		if not A.db then return end
		local ok, err = pcall(I.Offer, I)
		if not ok then geterrorhandler()(err) end
	end)
end)

-- Option rows on "Keeping it safe" (Options.lua places them). They show
-- only while there is something to import or undo.
A.ImportOptions = {
	{ type = "header", label = "Forever Journal", hidden = function() return not (I:Available() or I:CanUndo()) end },
	{ type = "execute", label = "Import from Forever Journal",
		desc = "Brings every Forever Journal journal into My Adventure: moments, goals, notes, quests and companions. It merges, takes a backup first and only reads Forever Journal's data.",
		hidden = function() return not I:Available() end, func = function() I:Ask() end },
	{ type = "execute", label = "Undo the import",
		desc = "Puts every journal the last import touched back as it was before, and its settings too.",
		hidden = function() return not I:CanUndo() end,
		func = function()
			local ok, err = I:Undo()
			E:Print(ok and L["The import is undone."] or tostring(err))
		end },
}

A:AddPart("import", {
	order = 95,
	init = function()
		if A.AddOptionRows then A:AddOptionRows("safe", A.ImportOptions) end
		if IsLoggedIn and IsLoggedIn() then
			login:GetScript("OnEvent")(login)
		else
			login:RegisterEvent("PLAYER_LOGIN")
		end
	end,
})
