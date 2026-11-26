-- EldoUI My Adventure: the provider hub E.Journal, also
-- EldoUI.Journal for plugins.
--
-- EldoUI already records much of a character's story (levels, runs,
-- people, attunements, challenges, wishes), spread over its modules. The
-- journal reads those stores through sources instead of recording them a
-- second time, and keeps its own rows only for what nothing else keeps.
--
--   J:RegisterSource(id, {
--       title     = "Instance runs",      shown in "What the journal reads"
--       module    = "Instances",          live only while that module is on
--       scope     = "char" | "account",   account: "all your characters"
--       kinds     = { "run", ... }        kinds it produces; or a map
--                                         { kind = def } to add new kinds
--       since     = fn(charKey) -> time   how far back it goes (optional)
--       read      = fn(charKey, from, to, opts) -> rows
--                   a row: { t, kind, level, zone, subzone, keep, ref, ... }
--       summarize = fn(charKey) -> facts  numbers and names, never text
--       goals     = { [kind] = fn(charKey, target) -> have, need }
--       places    = fn(charKey) -> { { key, zone, ... } }
--       people    = fn(charKey) -> { { key, name, ... } }
--   })
--   J:UnregisterSource(id), J:Source(id), J:Sources()  ({ id, def, live })
--   J:SourceLive(id)
--   J:Emit(id, row)          a live source asks the journal to store a row
--                            (only a source that keeps no time stamp of its
--                            own); row.id makes the ref "<source>:<id>", so
--                            the same row is never stored twice
--   J:Log(kind, fields)      the journal's own recorders write a row
--   J:Recording()            the journal writes: module and Loot Guide on,
--                            "Write the journal" on, and the character not
--                            marked "Don't record this character"
--   J:Changed(id)            a source's data changed (one redraw later)
--   J:Timeline(charKey, from, to, filter) -> rows, partial
--                            own rows and every live source's rows, sorted
--                            by (t, seq); filter = fn(row) or a J:Shown ctx;
--                            partial = a source was skipped in combat
--   J:Facts(charKey)         { journal = {...}, [sourceID] = summarize() }
--   J:Progress(goal)         have, need, sourceID for { kind, target[, charKey] }
--   J:People(charKey), J:Places(charKey)  merged by key, per source facts
--   J:StoryInput(charKey)    the story engine's input (Story/Facts.lua)
--   J:Key(nameOrUnit)        the one name key ("First Surname", plus
--                            "-Realm" for another realm; verify on Forever)
--
-- Rules: a source answers `read` or calls `Emit`, never both for the same
-- thing (Timeline skips read rows whose ref the journal holds). `read` and
-- `summarize` are cached per revision and never run in combat without a
-- cache. A source whose module is off gives nothing, and the page shows
-- its designed empty state. Secret values never reach a row.
local _, E = ...
local L = E.L
local Key = E.Key
local A = E.Adventure
local J = E.Journal
local S = A.Store
local LG = E.LootGuide

local Plain = A.Plain

local sources, sourceList = {}, {}

local ValidLevel = S.ValidLevel

-- A merged row with a level outside 1..cap: a level row is dropped, any
-- other row keeps its moment and loses the level (it files under "Before
-- the journal knew your level"). Returns the row or nil.
local function LevelChecked(row)
	local level = row.level
	if level == nil or ValidLevel(level) then return row end
	if row.kind == "level" then return nil end
	row.level = nil
	return row
end
local sourceRev = {}       -- id -> number, bumped by J:Changed
local changedSet, changedQueued = {}, false

---------------------------------------------------------------------------
-- Registry
---------------------------------------------------------------------------
local function Check(fn)
	return type(fn) == "function" and fn or nil
end

function J:RegisterSource(id, def)
	if type(id) ~= "string" or not id:match("^[%w_]+$") or id == "journal" then return false, "bad id" end
	if type(def) ~= "table" then return false, "no definition" end
	local source = {
		id = id,
		title = type(def.title) == "string" and def.title or id,
		module = type(def.module) == "string" and def.module or nil,
		scope = def.scope == "account" and "account" or "char",
		kinds = {},
		since = Check(def.since), read = Check(def.read), summarize = Check(def.summarize),
		places = Check(def.places), people = Check(def.people), live = Check(def.live),
		goals = {},
	}
	if type(def.kinds) == "table" then
		for key, value in pairs(def.kinds) do
			if type(key) == "number" and type(value) == "string" then
				source.kinds[value] = true
			elseif type(key) == "string" then
				if J:RegisterKind(key, type(value) == "table" and value or {}) then source.kinds[key] = true end
			end
		end
	end
	if type(def.goals) == "table" then
		for kind, fn in pairs(def.goals) do
			if type(kind) == "string" and type(fn) == "function" then source.goals[kind] = fn end
		end
	end
	-- The title may be an English key: reading it gives the language shown.
	E:TranslateFields({ source }, "title")
	if not sources[id] then sourceList[#sourceList + 1] = id end
	sources[id] = source
	sourceRev[id] = (sourceRev[id] or 0) + 1
	return true
end

function J:UnregisterSource(id)
	if not sources[id] then return false end
	sources[id] = nil
	for position, name in ipairs(sourceList) do
		if name == id then
			table.remove(sourceList, position)
			break
		end
	end
	sourceRev[id] = (sourceRev[id] or 0) + 1
	return true
end

function J:Source(id)
	return sources[id]
end

function J:SourceLive(id)
	local source = sources[id]
	if not source then return false end
	if source.module then
		local module = E.modules[source.module]
		if not (module and module.active) then return false end
	end
	if source.live then
		local ok, live = pcall(source.live)
		if not ok or not live then return false end
	end
	return true
end

function J:Sources()
	local list = {}
	for _, id in ipairs(sourceList) do
		list[#list + 1] = { id = id, def = sources[id], live = self:SourceLive(id) }
	end
	return list
end

---------------------------------------------------------------------------
-- Writing
---------------------------------------------------------------------------
function J:Recording()
	if not (A:Running() and A.db and A.db.record) then return false end
	local C = E.Characters
	if C and C.IsSkipped and C:IsSkipped() then return false end
	return true
end

function J:Log(kind, fields)
	if not self:Recording() then return nil end
	return S.Write(kind, fields)
end

function J:Emit(id, row)
	local source = sources[id]
	if not (source and type(row) == "table" and type(row.kind) == "string") then return nil end
	if not source.kinds[row.kind] then return nil end
	if not (self:Recording() and self:SourceLive(id)) then return nil end
	local fields = {}
	for key, value in pairs(row) do
		if key ~= "id" and key ~= "kind" then fields[key] = value end
	end
	local rowID = Plain(row.id)
	if rowID ~= nil then fields.ref = ("%s:%s"):format(id, tostring(rowID)) end
	return S.Write(row.kind, fields)
end

local function FlushChanged()
	changedQueued = false
	local set = changedSet
	changedSet = {}
	A:Fire("Changed", set)
	A:MarkDirty("sources")
end

function J:Changed(id)
	if type(id) ~= "string" then return end
	sourceRev[id] = (sourceRev[id] or 0) + 1
	changedSet[id] = true
	if changedQueued then return end
	changedQueued = true
	C_Timer.After(0.1, FlushChanged)
end

---------------------------------------------------------------------------
-- Reading: one cache per source call, keyed by the revisions it depends on
---------------------------------------------------------------------------
local cache = {}   -- "<what>|<source>|<charKey>|..." -> { sig, value }

local function Signature(id, charKey)
	return ("%d:%d"):format(sourceRev[id] or 0, J:Rev(charKey))
end

-- Calls a source function through the cache. In combat a missing cache
-- entry is not filled (nil, true: skipped).
local function Cached(what, id, charKey, extra, fn, ...)
	local key = ("%s|%s|%s|%s"):format(what, id, tostring(charKey), tostring(extra))
	local sig = Signature(id, charKey)
	local entry = cache[key]
	if entry and entry.sig == sig then return entry.value end
	if InCombatLockdown() then return entry and entry.value, true end
	local ok, value = pcall(fn, ...)
	if not ok then
		geterrorhandler()(("EldoUI My Adventure source %s (%s): %s"):format(id, what, tostring(value)))
		value = nil
	end
	cache[key] = { sig = sig, value = value }
	return value
end

function J:ClearCache()
	wipe(cache)
end

local function CleanRow(row, id, refs)
	if type(row) ~= "table" or type(row.kind) ~= "string" then return nil end
	local t = Plain(row.t)
	if type(t) ~= "number" then return nil end
	if type(row.ref) == "string" and refs and refs[row.ref] then return nil end
	local out = {}
	for key, value in pairs(row) do
		if not E:IsSecret(value) then out[key] = value end
	end
	out.src = id
	out.seq = tonumber(out.seq) or 0
	return out
end

local function Order(a, b)
	if a.t ~= b.t then return a.t < b.t end
	if a.src ~= b.src then
		if a.src == "journal" then return false end
		if b.src == "journal" then return true end
		return a.src < b.src
	end
	return (a.seq or 0) < (b.seq or 0)
end

-- Merged timelines kept per character: the whole one and a few time
-- windows (a page that asks for one day or one chapter), newest use first.
local timelineCache = {}
local TIMELINES_KEPT = 6

local function KeptTimeline(charKey, sig)
	local list = timelineCache[charKey]
	if not list then return nil end
	for index, entry in ipairs(list) do
		if entry.sig == sig then
			if index > 1 then
				table.remove(list, index)
				table.insert(list, 1, entry)
			end
			return entry
		end
	end
end

local function KeepTimeline(charKey, entry)
	local list = timelineCache[charKey]
	if not list then
		list = {}
		timelineCache[charKey] = list
	end
	table.insert(list, 1, entry)
	while #list > TIMELINES_KEPT do table.remove(list) end
end

function J:Timeline(charKey, from, to, filter)
	charKey = charKey or E.charKey
	from, to = tonumber(from) or 0, tonumber(to) or math.huge
	local sig = { tostring(charKey), from, to, J:Rev(charKey) }
	for _, id in ipairs(sourceList) do
		sig[#sig + 1] = id .. "=" .. (sourceRev[id] or 0) .. (self:SourceLive(id) and "+" or "-")
	end
	sig = table.concat(sig, "|")
	local merged, partial
	local entry = KeptTimeline(charKey, sig)
	if entry then
		merged, partial = entry.rows, entry.partial
	else
		merged, partial = {}, false
		local rec = self:Char(charKey)
		for _, row in ipairs(self:Rows(charKey, from, to)) do
			local copy = {}
			for key, value in pairs(row) do copy[key] = value end
			copy.src = "journal"
			merged[#merged + 1] = LevelChecked(copy)
		end
		local refs = rec and rec.refs
		for _, id in ipairs(sourceList) do
			local source = sources[id]
			if source.read and self:SourceLive(id) then
				local rows, skipped = Cached("read", id, charKey, from .. "-" .. to, source.read, charKey, from, to, {})
				if skipped then partial = true end
				for _, row in ipairs(type(rows) == "table" and rows or {}) do
					local clean = CleanRow(row, id, refs)
					if clean and clean.t >= from and clean.t <= to then merged[#merged + 1] = LevelChecked(clean) end
				end
			end
		end
		table.sort(merged, Order)
		-- A partial list is not kept: the next call out of combat fills it.
		if not partial then KeepTimeline(charKey, { sig = sig, rows = merged, partial = partial }) end
	end
	if filter == nil then return merged, partial end
	local out = {}
	for _, row in ipairs(merged) do
		local keep
		if type(filter) == "function" then
			local ok, yes = pcall(filter, row)
			keep = ok and yes
		else
			keep = self:Shown(row, filter)
		end
		if keep then out[#out + 1] = row end
	end
	return out, partial
end

local function Count(map)
	local count = 0
	for _ in pairs(type(map) == "table" and map or {}) do count = count + 1 end
	return count
end

local function OwnFacts(rec)
	if not rec then return {} end
	local open = 0
	for _, goal in ipairs(rec.goals) do
		if type(goal) == "table" and not goal.done and not goal.archived then open = open + 1 end
	end
	return {
		started = rec.started, startedLevel = rec.startedLevel, rows = #rec.events, quests = #rec.quests,
		deaths = rec.totals.deaths, xp = rec.totals.xp, earned = rec.totals.earned, time = rec.totals.time,
		zones = Count(rec.zones), bosses = Count(rec.bosses), fellows = Count(rec.fellows),
		goals = #rec.goals, openGoals = open, notes = #rec.notes, sessions = #rec.sessions,
	}
end

function J:Facts(charKey)
	charKey = charKey or E.charKey
	local out = { journal = OwnFacts(self:Char(charKey)) }
	for _, id in ipairs(sourceList) do
		local source = sources[id]
		if source.summarize and self:SourceLive(id) then
			local facts = Cached("facts", id, charKey, "", source.summarize, charKey)
			if type(facts) == "table" then out[id] = facts end
		end
	end
	return out
end

function J:Progress(goal)
	if type(goal) ~= "table" or type(goal.kind) ~= "string" then return nil end
	local charKey = goal.charKey or E.charKey
	for _, id in ipairs(sourceList) do
		local source = sources[id]
		local fn = source.goals[goal.kind]
		if fn and self:SourceLive(id) then
			local ok, have, need = pcall(fn, charKey, goal.target)
			if ok then return tonumber(have), tonumber(need), id end
			geterrorhandler()(have)
			return nil
		end
	end
	return nil
end

-- Lists merged by key: { key, name or zone, sources = { [id] = item } }.
local function Merge(self, what, charKey, field)
	charKey = charKey or E.charKey
	local byKey, list = {}, {}
	for _, id in ipairs(sourceList) do
		local source = sources[id]
		if source[what] and self:SourceLive(id) then
			local items = Cached(what, id, charKey, "", source[what], charKey)
			for _, item in ipairs(type(items) == "table" and items or {}) do
				local key = type(item) == "table" and Plain(item.key)
				if type(key) == "string" and key ~= "" then
					local entry = byKey[key]
					if not entry then
						entry = { key = key, sources = {} }
						byKey[key] = entry
						list[#list + 1] = entry
					end
					if entry[field] == nil and type(item[field]) == "string" then entry[field] = item[field] end
					entry.sources[id] = item
				end
			end
		end
	end
	table.sort(list, function(a, b) return tostring(a[field] or a.key) < tostring(b[field] or b.key) end)
	return list
end

function J:People(charKey)
	return Merge(self, "people", charKey, "name")
end

function J:Places(charKey)
	return Merge(self, "places", charKey, "zone")
end

---------------------------------------------------------------------------
-- Names: one key for a person, whoever wrote it down. Forever names are
-- "First Surname"; UnitName's second value is the surname there, so a
-- unit's key is built from E:NameParts. A realm suffix that is your own
-- realm is dropped.
---------------------------------------------------------------------------
local function OwnRealms()
	local set = {}
	local normalized = Plain(GetNormalizedRealmName and GetNormalizedRealmName())
	local realm = Plain(GetRealmName and GetRealmName())
	if type(normalized) == "string" and normalized ~= "" then set[normalized] = true end
	if type(realm) == "string" and realm ~= "" then
		set[realm] = true
		set[(realm:gsub("[%s%-]", ""))] = true
	end
	return set
end

function J:Key(nameOrUnit)
	if E:IsSecret(nameOrUnit) or type(nameOrUnit) ~= "string" then return nil end
	local text = strtrim(nameOrUnit)
	if text == "" then return nil end
	if not text:find("[%s%-]") and UnitExists and not E:IsSecret(UnitExists(text)) and UnitExists(text) then
		local isPlayer = UnitIsPlayer and UnitIsPlayer(text)
		if E:IsSecret(isPlayer) or not isPlayer then return nil end
		local first, last = E:NameParts(text)
		if E:IsSecret(first) or type(first) ~= "string" or first == "" then return nil end
		if type(last) == "string" and not E:IsSecret(last) and last ~= "" then return first .. " " .. last end
		return first
	end
	local name, realm = text:match("^(.-)%-([^%-]+)$")
	if not name or name == "" then return text end
	if OwnRealms()[realm] then return name end
	return name .. "-" .. realm
end

---------------------------------------------------------------------------
-- First-party sources
---------------------------------------------------------------------------
local function Characters()
	return E.Characters
end

local function Record(charKey)
	local C = Characters()
	return C and C.Get and C:Get(charKey) or nil
end

-- characters: the level log, played time and the completed-quest list
-- (Core/CharacterStore.lua). Its level log fills while Characters records.
J:RegisterSource("characters", {
	title = "Character records",
	scope = "char",
	kinds = { "level" },
	since = function(charKey)
		local record = Record(charKey)
		local first
		for _, row in pairs(type(record) == "table" and type(record.levels) == "table" and record.levels or {}) do
			if type(row) == "table" and type(row.at) == "number" and (not first or row.at < first) then first = row.at end
		end
		return first
	end,
	read = function(charKey, from, to)
		local record = Record(charKey)
		local rows = {}
		if type(record) ~= "table" or type(record.levels) ~= "table" then return rows end
		for level, row in pairs(record.levels) do
			if ValidLevel(level) and type(row) == "table" and type(row.at) == "number" and row.at >= from and row.at <= to then
				rows[#rows + 1] = { t = row.at, kind = "level", level = level, zone = row.zone, took = row.took,
					kills = row.kills, quests = row.quests, money = row.money, played = row.played, ref = "characters:level:" .. level }
			end
		end
		return rows
	end,
	summarize = function(charKey)
		local record = Record(charKey)
		if type(record) ~= "table" then return {} end
		local C = Characters()
		local completed
		local history = type(record.quests) == "table" and record.quests.history
		if type(history) == "string" and C.UnpackIDs then completed = Count(C.UnpackIDs(history)) end
		local levels = 0
		for _ in pairs(type(record.levels) == "table" and record.levels or {}) do levels = levels + 1 end
		return {
			name = record.name, class = record.class, race = record.race, faction = record.faction, level = record.level,
			played = C.Played and C:Played(record) or record.played, completedQuests = completed, levelsLogged = levels,
			guild = type(record.guild) == "table" and record.guild.name or nil, money = record.money,
		}
	end,
	goals = {
		level = function(charKey, target)
			local record = Record(charKey)
			return type(record) == "table" and tonumber(record.level) or 0, tonumber(target) or 60
		end,
	},
})

-- instances: dungeon, raid and battleground runs (Modules/Instances).
local function InstanceKey(charKey)
	local M = E.Instances
	return M and M.KeyFor and M:KeyFor(charKey) or nil
end

local function Runs(charKey)
	local M = E.Instances
	local key = InstanceKey(charKey)
	local out = {}
	if not (M and M.Runs and key) then return out end
	local runs = M:Runs()
	for position = #runs, 1, -1 do   -- the store is newest first
		local run = runs[position]
		if type(run) == "table" and run.char == key and type(run.enter) == "number" then out[#out + 1] = run end
	end
	return out
end

J:RegisterSource("instances", {
	title = "Instance runs",
	module = "Instances",
	scope = "char",
	kinds = { "dungeon", "raid", "run", "pvpwin", "pvploss" },
	since = function(charKey)
		local first = Runs(charKey)[1]
		return first and first.enter or nil
	end,
	read = function(charKey, from, to)
		local rows, seen = {}, {}
		for _, run in ipairs(Runs(charKey)) do
			local place = run.instanceID and run.instanceID ~= 0 and run.instanceID or run.instance
			local kind
			if run.kind == "pvp" then
				kind = run.result == "won" and "pvpwin" or run.result == "lost" and "pvploss" or nil
			elseif not seen[place] then
				kind = run.kind == "raid" and "raid" or "dungeon"
			else
				kind = "run"
			end
			if place ~= nil then seen[place] = true end
			if kind and run.enter >= from and run.enter <= to then
				local duration = type(run.leave) == "number" and run.leave - run.enter or nil
				rows[#rows + 1] = { t = run.enter, kind = kind, level = ValidLevel(run.enterLevel) and run.enterLevel or nil, zone = run.instance,
					instance = run.instance, instanceID = run.instanceID, battleground = run.instance, run = run.id,
					duration = duration, xp = run.xp, kills = run.kills, money = run.money, ref = "instances:" .. tostring(run.id) }
			end
		end
		return rows
	end,
	summarize = function(charKey)
		local counts, total, wins, losses = {}, 0, 0, 0
		for _, run in ipairs(Runs(charKey)) do
			if run.kind == "pvp" then
				if run.result == "won" then wins = wins + 1 elseif run.result == "lost" then losses = losses + 1 end
			elseif type(run.instance) == "string" then
				total = total + 1
				counts[run.instance] = (counts[run.instance] or 0) + 1
			end
		end
		local most, mostCount = nil, 0
		for name, count in pairs(counts) do
			if count > mostCount or (count == mostCount and most and name < most) then most, mostCount = name, count end
		end
		return { runs = total, instances = Count(counts), mostRun = most, mostRunCount = mostCount, pvpWins = wins, pvpLosses = losses }
	end,
	places = function(charKey)
		local byName, list = {}, {}
		for _, run in ipairs(Runs(charKey)) do
			if type(run.instance) == "string" and run.kind ~= "pvp" then
				local item = byName[run.instance]
				if not item then
					item = { key = run.instance, zone = run.instance, instanceID = run.instanceID, runs = 0, first = run.enter }
					byName[run.instance] = item
					list[#list + 1] = item
				end
				item.runs = item.runs + 1
				item.last = run.enter
			end
		end
		return list
	end,
	people = function(charKey)
		local byKey, list = {}, {}
		for _, run in ipairs(Runs(charKey)) do
			for name, member in pairs(type(run.group) == "table" and run.group or {}) do
				local key = J:Key(name)
				if key then
					local item = byKey[key]
					if not item then
						item = { key = key, name = key, runs = 0, first = run.enter }
						byKey[key] = item
						list[#list + 1] = item
					end
					item.runs = item.runs + 1
					item.last = run.enter
					if type(member) == "table" then
						item.class = item.class or member.class
						item.level = member.level or item.level
					end
				end
			end
		end
		return list
	end,
	goals = {
		run = function(charKey, target)
			local count = 0
			for _, run in ipairs(Runs(charKey)) do
				if run.kind ~= "pvp" and (target == nil or run.instance == target or run.instanceID == target) then count = count + 1 end
			end
			return count, 1
		end,
	},
})

-- playernotes: the people you grouped with and your notes on them,
-- account-wide (Modules/PlayerNotes.lua). Note texts stay there.
J:RegisterSource("playernotes", {
	title = "Player notes",
	module = "PlayerNotes",
	scope = "account",
	people = function()
		local M = E.PlayerNotes
		local list = {}
		if not (M and M.Store) then return list end
		for noteKey, entry in pairs(M:Store()) do
			local key = type(entry) == "table" and J:Key(M:JournalName(noteKey))
			if key then
				list[#list + 1] = { key = key, name = key, grouped = tonumber(entry.grouped), last = tonumber(entry.last),
					class = entry.class, mark = entry.mark, hasNote = type(entry.note) == "string" and entry.note ~= "" or nil }
			end
		end
		return list
	end,
})

-- attunements: progress of every attunement and key (read through
-- EldoUI.Attunements; the journal never works out a step itself).
J:RegisterSource("attunements", {
	title = "Attunements",
	module = "Attunements",
	scope = "char",
	live = function() return E.Attunements and E.Attunements.Running and E.Attunements:Running() end,
	summarize = function(charKey)
		local At = E.Attunements
		local done, started, total = 0, 0, 0
		for _, item in ipairs(At:Summary(charKey) or {}) do
			total = total + 1
			if item.state == "done" then
				done = done + 1
			elseif (item.done or 0) > 0 then
				started = started + 1
			end
		end
		return { attuned = done, started = started, total = total }
	end,
	goals = {
		attune = function(charKey, key)
			local done, total = E.Attunements:Progress(key, charKey)
			return done, total
		end,
	},
})

-- legacy: completed Legacy challenges with the game's own date (this
-- character only: the game answers for the character you play).
local function ChallengeTime(text)
	if type(text) ~= "string" then return nil end
	local year, month, day = text:match("^(%d%d)%-(%d%d)%-(%d%d)$")
	if not year then return nil end
	return time({ year = 2000 + tonumber(year), month = tonumber(month), day = tonumber(day), hour = 12 })
end

J:RegisterSource("legacy", {
	title = "Legacy challenges",
	module = "Legacy",
	scope = "char",
	kinds = { "challenge" },
	read = function(charKey, from, to)
		local rows = {}
		local M = E.Legacy
		if charKey ~= E.charKey or not (M and M.Challenges) then return rows end
		for _, item in ipairs(M:Challenges() or {}) do
			local t = item.done and ChallengeTime(item.date)
			if t and t >= from and t <= to then
				rows[#rows + 1] = { t = t, kind = "challenge", challenge = item.id, name = item.name, zone = false,
					ref = "legacy:" .. tostring(item.id) }
			end
		end
		return rows
	end,
	summarize = function(charKey)
		local M = E.Legacy
		if charKey ~= E.charKey or not (M and M.Challenges) then return {} end
		local done = 0
		for _, item in ipairs(M:Challenges() or {}) do
			if item.done then done = done + 1 end
		end
		return { challenges = done }
	end,
})

-- lootguide: the wishlist (this character's wishes and whether you own them).
J:RegisterSource("lootguide", {
	title = "Wishlist",
	module = "LootGuide",
	scope = "char",
	summarize = function(charKey)
		local data = type(EldoUIDB) == "table" and type(EldoUIDB.lootGuide) == "table" and EldoUIDB.lootGuide[charKey]
		local wishes = type(data) == "table" and Count(data.wishlist) or 0
		return { wishes = wishes }
	end,
	goals = {
		wish = function(charKey, itemID)
			if charKey ~= E.charKey or not LG.Owns then return 0, 1 end
			return LG:Owns(tonumber(itemID)) and 1 or 0, 1
		end,
	},
})

---------------------------------------------------------------------------
-- Story input: J:StoryInput(charKey) gives the story engine
-- (Story/Facts.lua) one plain table in its documented shape, built from
-- the journal and the stores it reads: the Characters level log, the
-- Instances runs, the quest hand-ins, the companions, the sessions and
-- the game's own counts. Ids become names here (items, mounts, titles,
-- standings), because the story speaks names; nothing is saved.
---------------------------------------------------------------------------
local function ItemName(itemID)
	itemID = tonumber(itemID)
	if not (itemID and C_Item) then return nil end
	local name = Plain(C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID))
	if type(name) ~= "string" or name == "" then
		name = Plain(C_Item.GetItemInfo and (C_Item.GetItemInfo(itemID)))
	end
	return type(name) == "string" and name ~= "" and name or nil
end

local function StandingLabel(standing)
	standing = tonumber(standing)
	local label = standing and Plain(rawget(_G, "FACTION_STANDING_LABEL" .. standing))
	return type(label) == "string" and label or nil
end

local function RestedText(pct)
	pct = tonumber(pct)
	if not pct then return nil end
	if pct >= 100 then return ("%.1f levels"):format(pct / 100) end
	return ("%d%% of a level"):format(pct)
end

local ROW_META = { t = true, seq = true, kind = true, level = true, zone = true, subzone = true, keep = true, ref = true, src = true }

-- One journal row in the story's event shape.
local function StoryEvent(rec, row)
	local v = {}
	for key, value in pairs(row) do
		if not ROW_META[key] then v[key] = value end
	end
	local kind = row.kind
	if kind == "spell" then
		v.spell, v.rank = row.name, tonumber(type(row.rank) == "string" and row.rank:match("%d+") or row.rank)
	elseif kind == "recipe" then
		v.recipe = row.name
	elseif kind == "skill" then
		v.skill = row.rank
	elseif kind == "rep" then
		v.standing, v.standingID = StandingLabel(row.standing), row.standing
	elseif kind == "boss" or kind == "raidboss" or kind == "bossagain" then
		v.raid = kind == "raidboss" or nil
		v.first = kind ~= "bossagain" and row.first or nil
		kind = "boss"
	elseif kind == "loot" or kind == "gear" or kind == "wish" then
		v.item = ItemName(row.item)
		v.boss = row.from
	elseif kind == "mount" then
		v.mount = row.name
	elseif kind == "pet" then
		v.pet = row.name
	elseif kind == "title" then
		v.title = row.name
	elseif kind == "respec" then
		v.n = row.points
	elseif kind == "rested" then
		v.pct = RestedText(row.pct)
	elseif kind == "explored" or kind == "cinematic" then
		v.zone = row.zone
	elseif kind == "subzone" then
		v.subzone = row.subzone
	elseif kind == "goal" or kind == "goalset" then
		v.goal = row.name
	elseif kind == "attunestep" or kind == "attuned" then
		v.attunement = row.attune
	elseif kind == "note" then
		for _, note in ipairs(rec.notes) do
			if type(note) == "table" and note.id == row.note then
				v.note = note.text
				break
			end
		end
	elseif kind == "challenge" then
		v.challenge = row.name
	end
	return { seq = row.seq, t = row.t, kind = kind, l = row.level, z = row.zone, s = row.subzone, keep = row.keep, v = v }
end

local function SortedNames(set)
	local list = {}
	for name in pairs(type(set) == "table" and set or {}) do
		if type(name) == "string" then list[#list + 1] = name end
	end
	table.sort(list)
	return list
end

-- Level ranges from a set of levels ({ [12] = true, [13] = true } -> { { 12, 13 } }).
local function Ranges(levels)
	local list = {}
	for level in pairs(type(levels) == "table" and levels or {}) do
		if type(level) == "number" then list[#list + 1] = level end
	end
	table.sort(list)
	local out = {}
	for _, level in ipairs(list) do
		local last = out[#out]
		if last and last[2] + 1 == level then last[2] = level else out[#out + 1] = { level, level } end
	end
	return out
end

local function StoryMe(charKey, record)
	if charKey == E.charKey then
		local first, last = E:NameParts("player")
		first, last = Plain(first), Plain(last)
		local name = type(first) == "string" and first or E:PlayerName()
		if type(last) == "string" and last ~= "" then name = name .. " " .. last end
		local race = Plain(UnitRace("player"))
		local _, class = UnitClass("player")
		return { name = name, race = race or (record and record.race), class = Plain(class) or (record and record.class),
			faction = Plain(UnitFactionGroup("player")) or (record and record.faction) }
	end
	record = record or {}
	return { name = record.name, race = record.race, class = record.class, faction = record.faction }
end

local function Positive(value)
	value = tonumber(value)
	return value and value > 0 and value or nil
end

local function StoryLevels(rec, record)
	local out = {}
	local logged = type(record) == "table" and type(record.levels) == "table" and record.levels or {}
	local keys = {}
	for n in pairs(rec.levels) do
		if ValidLevel(n) then keys[n] = true end
	end
	for n in pairs(logged) do
		if ValidLevel(n) then keys[n] = true end
	end
	for n in pairs(keys) do
		local own = type(rec.levels[n]) == "table" and rec.levels[n] or {}
		local cs = type(logged[n]) == "table" and logged[n] or {}
		-- The level log's row n + 1 holds how level n went (took, kills, quests).
		local nextRow = type(logged[n + 1]) == "table" and logged[n + 1] or {}
		out[n] = {
			at = cs.at or own.at, zone = cs.zone or own.zone, played = cs.played,
			time = Positive(own.time) or nextRow.took,
			kills = Positive(own.kills) or nextRow.kills, quests = Positive(own.quests) or nextRow.quests,
			deaths = own.deaths, deathZones = own.deathZones, zones = own.zones, earned = own.earned,
		}
	end
	return out
end

local function StoryRuns(rec, charKey)
	local out = {}
	local M = E.Instances
	if not (M and M.RunsFor) then return out end
	local mine = J:Key("player")
	local plainName = E:PlayerName()
	for _, run in ipairs(M:RunsFor(charKey)) do
		if type(run) == "table" and type(run.enter) == "number" then
			local extras = type(rec.runExtras[run.id]) == "table" and rec.runExtras[run.id] or {}
			local with = {}
			if type(extras.with) == "table" then
				with = SortedNames(extras.with)
			else
				for name in pairs(type(run.group) == "table" and run.group or {}) do
					local key = J:Key(name)
					if key and key ~= mine and name ~= plainName then with[#with + 1] = key end
				end
				table.sort(with)
			end
			local kind = run.kind == "raid" and "raid" or run.kind == "pvp" and "pvp" or "dungeon"
			local extra = 0
			if tonumber(run.groupSize) then extra = math.max(run.groupSize - 1 - #with, 0) end
			out[#out + 1] = { id = run.id, instance = run.instance, kind = kind, enter = run.enter, leave = run.leave,
				level = run.enterLevel, with = with, extra = extra,
				bosses = run.bosses or (type(extras.bosses) == "table" and #extras.bosses or nil),
				result = run.result == "won" and "win" or run.result == "lost" and "loss" or nil, honor = run.honor, z = run.instance }
		end
	end
	return out
end

local function StoryGame(rec, charKey, record)
	local game = { questsBefore = rec.questsBefore, playedBefore = rec.playedBefore, challenges = {} }
	if charKey == E.charKey and C_QuestLog and C_QuestLog.GetAllCompletedQuestIDs then
		local list = C_QuestLog.GetAllCompletedQuestIDs()
		if type(list) == "table" then game.questsDone = #list end
	end
	local C = Characters()
	if type(record) == "table" and C then
		local quests = record.quests
		if not game.questsDone and type(quests) == "table" and type(quests.history) == "string" and C.UnpackIDs then
			game.questsDone = Count(C.UnpackIDs(quests.history))
		end
		game.played = C.Played and C:Played(record) or record.played
	end
	local Legacy = E.Legacy
	if charKey == E.charKey and Legacy and Legacy.Challenges and Legacy.active then
		for _, item in ipairs(Legacy:Challenges() or {}) do
			local t = item.done and ChallengeTime(item.date)
			if t then game.challenges[#game.challenges + 1] = { name = item.name, t = t } end
		end
	end
	return game
end

function J:StoryInput(charKey)
	charKey = charKey or E.charKey
	local rec = self:Char(charKey)
	if not rec then return nil end
	local record = Record(charKey)
	local input = {
		charKey = charKey, salt = rec.salt or 0, now = time(), rev = rec.rev,
		started = rec.started, startedLevel = rec.startedLevel or 1, startedZone = rec.startedZone,
		me = StoryMe(charKey, record), levels = StoryLevels(rec, record), runs = StoryRuns(rec, charKey),
		events = {}, quests = {}, zones = {}, fellows = {}, sessions = {}, sources = {}, rolled = {},
		totals = { earned = rec.totals.earned }, game = StoryGame(rec, charKey, record),
	}
	local level = charKey == E.charKey and Plain(UnitLevel("player")) or (type(record) == "table" and record.level)
	input.level = type(level) == "number" and level or input.startedLevel
	for _, row in ipairs(self:Rows(charKey)) do
		if row.kind == "rollup" then
			local counts = {}
			for name, count in (row.counts or ""):gmatch("([%w_]+):(%d+)") do counts[name] = tonumber(count) end
			input.rolled[#input.rolled + 1] = { a = row.level, b = row.level, spells = (counts.spell or 0) + (counts.recipe or 0),
				finds = counts.loot or 0 }
		else
			input.events[#input.events + 1] = StoryEvent(rec, row)
		end
	end
	for _, q in ipairs(rec.quests) do
		if type(q) == "table" then
			input.quests[#input.quests + 1] = { id = q.id, t = q.t, title = q.title, z = q.z, s = q.s, l = q.l, xp = q.xp, money = q.m,
				giver = q.giver, with = SortedNames(q.with), instance = q.instance, chain = q.chain }
		end
	end
	for name, zone in pairs(rec.zones) do
		if type(zone) == "table" then
			input.zones[name] = { first = zone.first, firstLevel = zone.firstLevel, t = zone.t, deaths = zone.deaths, quests = zone.quests }
		end
	end
	for key, fellow in pairs(rec.fellows) do
		if type(fellow) == "table" then
			input.fellows[key] = { name = fellow.name or key, race = fellow.race, class = fellow.class, met = fellow.met,
				metLevel = fellow.metLevel, metZone = fellow.metZone, metSub = fellow.metSub, time = fellow.time,
				steps = type(fellow.steps) == "table" and fellow.steps or {} }
		end
	end
	for index, session in ipairs(rec.sessions) do input.sessions[index] = session end
	for source, levels in pairs(type(rec.off) == "table" and rec.off or {}) do
		local ranges = Ranges(levels)
		if ranges[1] then input.sources[source] = { off = ranges } end
	end
	return input
end

---------------------------------------------------------------------------
-- Part: listen to the stores while the journal runs
---------------------------------------------------------------------------
local CHARACTER_SECTIONS = { levels = true, played = true, quests = true, login = true, guild = true, skip = true }

A:AddPart("sources", {
	order = 2,
	start = function()
		local C = Characters()
		if C and C.RegisterCallback then
			C.RegisterCallback(J, "Updated", function(_, _, section)
				if section == nil or CHARACTER_SECTIONS[section] then J:Changed("characters") end
			end)
		end
		if E.Instances and E.Instances.OnChange then
			E.Instances:OnChange("adventure", function() J:Changed("instances") end)
		end
		LG:On("adventure_sources", function(changed)
			if changed.attune then J:Changed("attunements") end
			if changed.wishlist then J:Changed("lootguide") end
		end)
	end,
	stop = function()
		local C = Characters()
		if C and C.UnregisterCallback then C.UnregisterCallback(J, "Updated") end
		if E.Instances and E.Instances.OnChange then E.Instances:OnChange("adventure", nil) end
		LG:Off("adventure_sources")
		wipe(cache)
		wipe(timelineCache)
	end,
})
