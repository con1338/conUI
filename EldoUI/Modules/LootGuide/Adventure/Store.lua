-- EldoUI My Adventure: the saved journal.
--
-- EldoUIDB.journal[charKey] (the account file, so the alts views can read
-- any character; never another saved table):
--   {
--     v = 1, guid, started, startedLevel, seq, rev, salt, nextId,
--     playedBefore, questsBefore, startedZone, lastGuild, lastRested,
--     titles, mobs,
--     strings = { "Westfall", ... },          names kept once (rows hold ids)
--     events  = { "t|seq|kind|lvl|z|s|a|b|c|keep[|d|...]", ... }   sorted by (t, seq)
--     refs    = { ["instances:88"] = seq },   rows a source asked for (J:Emit)
--     levels  = { [n] = { zones = { [z] = s }, deaths, deathZones, stat, earned, sessions } },
--               (keyed by level; levels 1 to n in a row are saved as a list,
--               which reads back as the same table)
--     zones   = { [z] = { t, first, firstLevel, map, kills, quests, deaths, subs } },
--     bosses  = { [encounterID] = { name, first, kills, instance } },
--     quests  = { { t, id, z, s, l, xp, m, map, x, y, giver, taker, objective, started, with } },
--     questStart = { [id] = { ... } }, fellows = { [key] = { ... } },
--     runExtras = { [runID] = { bosses, with } }, goals = { }, notes = { },
--     totals  = { deaths, xp, earned, time }, sessions = { { login, logout, level, playedIn, playedOut } },
--     trash   = { { id, at, kind, data } },   soft deletes, kept 7 days
--     ui      = { section, collapsed, journeyBy, filter, trackerHidden, notNow, lastOpen, ... },
--     abandoned = { { t, id, title, z, s, l, started, giver } },  quests
--               that left the log without a hand-in (Chronicle.lua)
--     keepNotes = { [keepKey] = text },        your notes on keepsakes
--     imported = { from, version, at, rows, lastT, lastRows, characters,
--                  dungeons, totals, extra, unmapped }   (Import.lua)
--     rollupNone, trimSkip   what the last roll-up and trim already read
--               (so a full journal does not read every row for each new
--               one); checked against the rows before use, rebuilt freely
--     _quarantine = { [path] = { value, at, why } }   values of the wrong
--               kind the load check set aside (Core/Database.lua); the
--               Saved data page puts them back
--   }
-- Other files add keys of their own on demand; the load check keeps every
-- key it does not know.
-- Backups and exports (Backup.lua, Export.lua) carry the whole record:
-- goals, notes, keepNotes, quests (with `archived`) and abandoned too.
-- Account tables: EldoUIDB.journalBackups[charKey] (Backup.lua; kept
-- when a character is forgotten or its journal cleared),
-- EldoUIDB.journalSeen (observed content, cap 600) and
-- EldoUIDB.journalCache = { pending, orphans, forgotten, writing, importOffered }
-- (forgotten: the backups of the journals of characters the Alts window
-- forgot, Backup.lua; kept until the player puts one back, and after;
-- writing: the copy a backup waits with while a job writes its code).
--
-- A journal is tagged with the character's GUID. One whose tag differs
-- (a namesake, or untagged data) is never adopted: it moves to
-- journalCache.orphans. A character without a journal takes its own back
-- from the orphans, matched by GUID (characters that shared a first name
-- set each other's journal aside on every switch): the fullest one, with
-- the places and dungeons the others knew, so a place you have been to
-- is never a first visit again. Otherwise it starts a new one. Orphans are
-- kept packed, the newest ten (Backup.lua); the Saved data page lists
-- them, gives one back to its own character or removes it.
--
-- The record is a registered saved store (E:MigrateStore): the first time
-- a session reads it, a "before update" backup is taken when an update
-- will change it, the update steps run, and the load check repairs what it
-- can and sets aside what it cannot read. Nothing is reset.
--
-- Rows are packed strings (about 60 bytes); zones, subzones and names are
-- kept once in `strings`. Every row gets a growing `seq`, so rows of the
-- same second keep their order. The cap is 8,000 rows: past it, ordinary
-- rows (spells, plain finds, flights ...) of chapters two or more levels
-- behind roll up into one summary row per chapter, oldest first. Levels,
-- deaths, places, dungeons, goals, notes and keepsakes never roll up. Only
-- when that is not enough do the least worth rows go (Kinds.lua).
--
-- API (E.Journal):
--   J:Char([charKey])            the record (this character: created and
--                                tagged on first use; others: nil if none)
--   J:Log(kind, fields)          Sources.lua (the recording gate) -> S.Write
--   J:Rows(charKey[, from, to])  decoded own rows, oldest first; with a
--                                time window only the rows inside it are
--                                decoded (a binary search on the packed
--                                times, a few windows kept per revision)
--   J:RowsOfKind(charKey, kinds) decoded rows of some kinds ({ [kind] = true }),
--                                read from the packed heads, kept per revision
--   J:ZoneCount(charKey, zone)   how many rows name a zone, from the heads
--   J:RowsWhere(charKey, kinds, field, value)  decoded rows of some kinds
--                                whose field holds a value (compared packed)
--   J:Row(charKey, seq)          one decoded row
--   J:DeleteRow(seq), J:Undo(trashID), J:Trash([charKey])
--   J:SetArchived(list, id, on)  goals or notes
--   J:Rev([charKey])             revision counter for caches
--   J:Clear([charKey])           "Clear this character's journal"
--   J:Seen(), J:AddSeen(list, id, fields)  observed content (Observe.lua)
--   J:Size([charKey])            saved size estimate in bytes
--   J:Rollup([charKey])          roll up now (normally a job past the cap)
local _, E = ...
local A = E.Adventure
local J = E.Journal

local S = {}
A.Store = S

S.SCHEMA = 1
S.CAP_EVENTS = 8000
S.CAP_QUESTS = 2000
S.CAP_SESSIONS = 400
S.CAP_FELLOWS = 400
S.CAP_SEEN = 600
S.CAP_PENDING = 50
S.TRASH_SECONDS = 7 * 86400
S.ROLLUP_BEHIND = 2
S.ROLLUP_TARGET = 0.95      -- roll up until the journal is this full
S.HARD_SLACK = 500          -- past cap + slack the store trims at once
S.BUDGET_BYTES = 1.5 * 1024 * 1024
S.WINDOWS_KEPT = 8          -- decoded time windows kept per character
-- Work counters for the large-data checks: rows decoded, windows read and
-- windows served from what was kept.
S.stats = { decoded = 0, windows = 0, windowHits = 0 }

local Plain = A.Plain

local function Now()
	return time()
end

---------------------------------------------------------------------------
-- Tables
---------------------------------------------------------------------------
local function Root()
	if type(EldoUIDB) ~= "table" then return nil end
	if type(EldoUIDB.journal) ~= "table" then EldoUIDB.journal = {} end
	return EldoUIDB.journal
end
S.Root = Root

function S.Cache()
	if type(EldoUIDB) ~= "table" then return {} end
	local cache = EldoUIDB.journalCache
	if type(cache) ~= "table" then
		cache = {}
		EldoUIDB.journalCache = cache
	end
	if type(cache.pending) ~= "table" then cache.pending = {} end
	if type(cache.orphans) ~= "table" then cache.orphans = {} end
	if type(cache.forgotten) ~= "table" then cache.forgotten = {} end
	return cache
end

local function MyGUID()
	local guid = Plain(UnitGUID("player"))
	if type(guid) ~= "string" or guid == "" then return nil end
	return guid
end
S.MyGUID = MyGUID

local LISTS = { "strings", "events", "quests", "goals", "notes", "sessions", "trash" }
local MAPS = { "refs", "levels", "zones", "bosses", "questStart", "fellows", "runExtras", "totals", "ui" }

-- Lists whose numbered entries stand on their own: a gap closes up. The
-- `strings` list is never renumbered (rows name its entries by number).
local CLOSE_UP = { events = true, quests = true, goals = true, notes = true, sessions = true, trash = true }
local NUMBERS = { "seq", "rev", "salt", "nextId", "started" }
local TOTALS = { "deaths", "xp", "earned", "time" }

-- The load check of a saved record (Core/Database.lua, E:MigrateStore):
-- every shape a release wrote is accepted, unknown keys are kept, a value
-- of the wrong kind is set aside with its place in the record.
local function Check(rec, C)
	for _, name in ipairs(LISTS) do
		if CLOSE_UP[name] then C.List(rec, name) else C.Table(rec, name) end
	end
	for _, name in ipairs(MAPS) do C.Table(rec, name) end
	if rec.abandoned ~= nil then C.List(rec, "abandoned") end
	for _, key in ipairs(TOTALS) do C.Number(rec.totals, key, "totals." .. key) end
	C.Table(rec.ui, "collapsed", "ui.collapsed")
	C.Table(rec.ui, "notNow", "ui.notNow")
	for _, key in ipairs(NUMBERS) do C.Number(rec, key) end
end

-- Update steps of the record: A:AddMigration(version, fn) with
-- fn(rec, from); S.SCHEMA is the version this EldoUI writes.
function A:AddMigration(version, fn)
	return E:RegisterStoreStep("journal", version, fn)
end

-- Fill in what a record lacks (an older one, a new one, a copy read from
-- a backup code). Values of the wrong kind in a saved record were set
-- aside by the load check before this runs.
local function Fill(rec)
	for _, name in ipairs(LISTS) do
		if type(rec[name]) ~= "table" then rec[name] = {} end
	end
	for _, name in ipairs(MAPS) do
		if type(rec[name]) ~= "table" then rec[name] = {} end
	end
	local totals = rec.totals
	for _, key in ipairs(TOTALS) do totals[key] = tonumber(totals[key]) or 0 end
	if type(rec.ui.collapsed) ~= "table" then rec.ui.collapsed = {} end
	if type(rec.ui.notNow) ~= "table" then rec.ui.notNow = {} end
	rec.seq = tonumber(rec.seq) or #rec.events
	rec.rev = tonumber(rec.rev) or 0
	rec.salt = tonumber(rec.salt) or 0
	rec.nextId = tonumber(rec.nextId) or 1
	rec.started = tonumber(rec.started) or Now()
	return rec
end
S.Fill = Fill

-- A record that is not saved under a character (a copy from a backup
-- code or an import): its steps run, nothing is backed up or reported.
local function Migrate(rec)
	Fill(rec)
	local from = tonumber(rec.v) or 0
	local info = E:StoreInfo("journal")
	for _, step in ipairs(info and info.steps or {}) do
		if step.version > from and step.version <= S.SCHEMA then
			local ok, err = pcall(step.fn, rec, from)
			if not ok then geterrorhandler()(("EldoUI My Adventure migration %d: %s"):format(step.version, tostring(err))) end
		end
	end
	rec.v = math.max(from, S.SCHEMA)
	return rec
end
S.Migrate = Migrate

-- A record saved under a character: through the saved data registry
-- (backup before an update, the steps, the load check), then filled in.
local function MigrateSaved(rec, charKey)
	E:MigrateStore("journal", rec, charKey)
	return Fill(rec)
end
S.MigrateSaved = MigrateSaved

E:RegisterStore("journal", {
	perKey = true,
	title = "Journal of %s",
	version = S.SCHEMA,
	validate = Check,
	-- The "before update" copy is the journal's own backup code (Backup.lua),
	-- written in slices for a long journal.
	backup = function(rec, charKey)
		local B = A.Backup
		return B and B.TakeBeforeUpdate and B:TakeBeforeUpdate(rec, charKey) or nil
	end,
})

local function New(guid)
	local level = Plain(UnitLevel("player"))
	return Migrate({ v = S.SCHEMA, guid = guid, started = Now(), startedLevel = type(level) == "number" and level or nil,
		seq = 0, rev = 0, salt = 0, nextId = 1 })
end

-- Set aside, packed, the newest few kept (Backup.lua); the Saved data page
-- lists them.
local function Orphan(key, rec)
	local entry = { key = key, guid = rec.guid, at = Now(), journal = rec }
	local B = A.Backup
	if B and B.KeepOrphan then return B:KeepOrphan(entry) end
	local orphans = S.Cache().orphans
	orphans[#orphans + 1] = entry
	return entry
end

local migrated = setmetatable({}, { __mode = "k" })
local pending = {}   -- rows written before the character's GUID was known
S.pendingRows = pending

-- This character's record. nil until the saved variables and the GUID
-- are there.
-- A level a row may carry: a whole number from 1 to the level cap. Rows
-- outside it ("Reached level 0", "Chapter 61" from a bad import or an old
-- store) are never written or shown (Sources.lua J:Timeline drops them).
local function LevelCap()
	local cap = type(GetMaxLevelForPlayerExpansion) == "function" and Plain(GetMaxLevelForPlayerExpansion()) or nil
	return type(cap) == "number" and cap >= 1 and cap or 60
end
S.LevelCap = LevelCap
J.LevelCap = LevelCap

local function ValidLevel(level)
	return type(level) == "number" and level >= 1 and level == math.floor(level) and level <= LevelCap()
end
S.ValidLevel = ValidLevel
J.ValidLevel = ValidLevel

-- The places and dungeons of an older copy of the same journal: a place
-- the copy knew is known, with the earlier first visit.
local function MergePlaces(into, from)
	if type(from.zones) == "table" then
		if type(into.zones) ~= "table" then into.zones = {} end
		for zone, info in pairs(from.zones) do
			if type(zone) == "string" and type(info) == "table" then
				local own = into.zones[zone]
				if type(own) ~= "table" then
					into.zones[zone] = CopyTable(info)
				else
					local first, mine = tonumber(info.first), tonumber(own.first)
					if first and (not mine or first < mine) then
						own.first, own.firstLevel = first, info.firstLevel
					elseif mine then
						own.first = mine
					end
					if type(info.subs) == "table" then
						if type(own.subs) ~= "table" then own.subs = {} end
						for sub, spot in pairs(info.subs) do
							if own.subs[sub] == nil and type(spot) == "table" then own.subs[sub] = CopyTable(spot) end
						end
					end
				end
			end
		end
	end
	if type(from.instancesSeen) == "table" then
		if type(into.instancesSeen) ~= "table" then into.instancesSeen = {} end
		for name, at in pairs(from.instancesSeen) do
			local mine, seen = tonumber(into.instancesSeen[name]), tonumber(at)
			if type(name) == "string" and seen then into.instancesSeen[name] = mine and math.min(mine, seen) or seen end
		end
	end
end
S.MergePlaces = MergePlaces

-- This character's own journal from the orphans (same GUID), or nil. The
-- fullest copy comes back, and every other copy with the same GUID is
-- folded into it, oldest first: moments, goals, notes and places. A folded
-- copy leaves the orphans, so it never comes back on its own later (after
-- "Clear this character's journal", say). A copy that can't be folded stays
-- set aside on the Saved data page.
local function OrphanGUID(entry)
	if type(entry) ~= "table" then return nil end
	if entry.guid ~= nil then return entry.guid end
	return type(entry.journal) == "table" and entry.journal.guid or nil
end

-- The journal an entry holds: in hand, or read from its packed code.
local function OrphanJournal(entry)
	local B = A.Backup
	if B and B.OrphanJournal then return B.OrphanJournal(entry) end
	return type(entry.journal) == "table" and entry.journal or nil
end

local function Adopt(guid)
	local orphans = S.Cache().orphans
	local B = A.Backup
	local function Rows(entry)
		if B and B.OrphanRows then return B.OrphanRows(entry) end
		return type(entry.journal) == "table" and type(entry.journal.events) == "table" and #entry.journal.events or 0
	end
	local mine = {}
	for _, entry in ipairs(orphans) do
		if OrphanGUID(entry) == guid then mine[#mine + 1] = entry end
	end
	-- The fullest copy that can be read comes back.
	table.sort(mine, function(a, b) return Rows(a) > Rows(b) end)
	local best, bestEntry
	for _, entry in ipairs(mine) do
		local journal = OrphanJournal(entry)
		if type(journal) == "table" and type(journal.events) == "table" then
			best, bestEntry = journal, entry
			break
		end
	end
	if not best then return nil end
	if best.guid == nil then best.guid = guid end
	local others = {}
	for _, entry in ipairs(mine) do
		if entry ~= bestEntry then others[#others + 1] = entry end
	end
	table.sort(others, function(a, b) return (tonumber(a.at) or 0) < (tonumber(b.at) or 0) end)
	local gone = { [bestEntry] = true }
	for _, entry in ipairs(others) do
		local ok, err = pcall(function()
			local journal = OrphanJournal(entry)
			if type(journal) ~= "table" then error("it can't be read") end
			if B and B.Merge then B.Merge(best, journal) end
			MergePlaces(best, journal)
		end)
		if ok then
			gone[entry] = true
		else
			geterrorhandler()(("EldoUI My Adventure: an older copy of this journal stays set aside: %s"):format(tostring(err)))
		end
	end
	for index = #orphans, 1, -1 do
		if gone[orphans[index]] then table.remove(orphans, index) end
	end
	return best
end

-- A renamed character's journal: a record on this realm under another
-- key with this character's GUID moves to its new key, with its backups.
local function Renamed(root, key, guid)
	local realm = type(key) == "string" and key:match(" %- (.+)$")
	if not realm then return nil end
	local suffix = " - " .. realm
	for other, rec in pairs(root) do
		if other ~= key and type(other) == "string" and type(rec) == "table" and rec.guid == guid
			and other:sub(-#suffix) == suffix then
			root[other] = nil
			local B = A.Backup
			if B and B.Claim then
				local ok, err = pcall(B.Claim, other, key, guid)
				if not ok then geterrorhandler()(err) end
			end
			return rec
		end
	end
	return nil
end

local function Own()
	local root = Root()
	local key = E.charKey
	if not (root and key) then return nil end
	local guid = MyGUID()
	if not guid then return nil end
	local rec = root[key]
	if type(rec) == "table" and rec.guid ~= guid then
		Orphan(key, rec)
		rec = nil
	end
	if type(rec) ~= "table" then
		rec = Renamed(root, key, guid) or Adopt(guid) or New(guid)
		root[key] = rec
	end
	if not migrated[rec] then
		migrated[rec] = true
		MigrateSaved(rec, key)
	end
	if pending[1] then
		local list = { unpack(pending) }
		wipe(pending)
		for _, item in ipairs(list) do S.Write(item[1], item[2]) end
	end
	return rec
end
S.Own = Own

function J:Char(charKey)
	if charKey == nil or charKey == E.charKey then return Own() end
	local root = Root()
	local rec = root and root[charKey]
	if type(rec) ~= "table" then return nil end
	if not migrated[rec] then
		migrated[rec] = true
		MigrateSaved(rec, charKey)
	end
	return rec
end

function J:Rev(charKey)
	local rec = self:Char(charKey)
	return rec and rec.rev or 0
end

local function Bump(rec)
	rec.rev = (rec.rev or 0) + 1
end
S.Bump = Bump

function S.NewId(rec)
	local id = rec.nextId or 1
	rec.nextId = id + 1
	return id
end

---------------------------------------------------------------------------
-- Strings: zones and names kept once per character
---------------------------------------------------------------------------
local index = setmetatable({}, { __mode = "k" })

local function Index(rec)
	local map = index[rec]
	if not map then
		map = {}
		for id, text in ipairs(rec.strings) do map[text] = id end
		index[rec] = map
	end
	return map
end

function S.Intern(rec, text)
	if type(text) ~= "string" or E:IsSecret(text) or text == "" then return nil end
	local map = Index(rec)
	local id = map[text]
	if not id then
		id = #rec.strings + 1
		rec.strings[id] = text
		map[text] = id
	end
	return id
end

function S.String(rec, id)
	id = tonumber(id)
	return id and rec.strings[id] or nil
end

-- The number of a name already kept (nil when it is not there; nothing
-- is added).
function S.StringId(rec, text)
	if type(text) ~= "string" or E:IsSecret(text) or text == "" then return nil end
	return Index(rec)[text]
end

---------------------------------------------------------------------------
-- Packed rows: "t|seq|kind|lvl|z|s|a|b|c|keep|d|e...". The kind's fields
-- (Kinds.lua) fill a, b, c and then d onward. "%" and "|" in values are
-- escaped, so a link or a color code never splits a row.
---------------------------------------------------------------------------
local function Escape(text)
	return (text:gsub("%%", "%%25"):gsub("|", "%%7C"))
end

local function Unescape(text)
	if not text:find("%", 1, true) then return text end
	return (text:gsub("%%7C", "|"):gsub("%%25", "%%"))
end

local function Split(packed)
	local out, start = {}, 1
	while true do
		local stop = packed:find("|", start, true)
		if not stop then
			out[#out + 1] = packed:sub(start)
			return out
		end
		out[#out + 1] = packed:sub(start, stop - 1)
		start = stop + 1
	end
end
S.Split = Split

local function Number(text)
	if text == nil or text == "" then return nil end
	return tonumber(text)
end

local function EncodeValue(rec, kindOf, value, inlineStrings)
	if E:IsSecret(value) or type(value) == "nil" then return "" end
	if kindOf == "n" then
		value = tonumber(value)
		if not value then return "" end
		if value == math.floor(value) and math.abs(value) < 1e15 then return ("%d"):format(value) end
		return tostring(value)
	elseif kindOf == "b" then
		return value and "1" or ""
	elseif kindOf == "i" and not inlineStrings then
		local id = S.Intern(rec, tostring(value))
		return id and tostring(id) or ""
	end
	return Escape(tostring(value))
end

local function DecodeValue(rec, kindOf, text)
	if text == nil or text == "" then return nil end
	if kindOf == "n" then return tonumber(text) end
	if kindOf == "b" then return true end
	if kindOf == "i" then return S.String(rec, text) end
	return Unescape(text)
end

-- Slot of the n-th kind field: a, b, c are 7..9, keep is 10, d onward 11+.
local function Slot(position)
	if position <= 3 then return 6 + position end
	return 7 + position
end

-- Inline strings are for content comparisons across journals, never storage.
function S.Pack(rec, row, inlineStrings)
	local def = J:Kind(row.kind)
	local fields = def and def.fields or {}
	local parts = {
		EncodeValue(rec, "n", row.t), EncodeValue(rec, "n", row.seq), Escape(tostring(row.kind)),
		EncodeValue(rec, "n", row.level), EncodeValue(rec, "i", row.zone, inlineStrings), EncodeValue(rec, "i", row.subzone, inlineStrings),
		"", "", "", row.keep and "1" or "",
	}
	for position, field in ipairs(fields) do
		parts[Slot(position)] = EncodeValue(rec, field[2], row[field[1]], inlineStrings)
	end
	for slot = 1, #parts do parts[slot] = parts[slot] or "" end
	local last = #parts
	while last > 10 and parts[last] == "" do last = last - 1 end
	return table.concat(parts, "|", 1, last)
end

function S.Unpack(rec, packed)
	if type(packed) ~= "string" then return nil end
	S.stats.decoded = S.stats.decoded + 1
	local parts = Split(packed)
	local kind = Unescape(parts[3] or "")
	local row = {
		t = Number(parts[1]), seq = Number(parts[2]), kind = kind, level = Number(parts[4]),
		zone = S.String(rec, parts[5]), subzone = S.String(rec, parts[6]), keep = parts[10] == "1" or nil,
	}
	local def = J:Kind(kind)
	if def then
		for position, field in ipairs(def.fields) do
			row[field[1]] = DecodeValue(rec, field[2], parts[Slot(position)])
		end
	else
		-- A kind no file registered this session (a plugin that is off):
		-- its values stay as plain text in f1, f2, ...
		local position = 1
		while parts[Slot(position)] do
			local text = parts[Slot(position)]
			if text ~= "" then row["f" .. position] = Unescape(text) end
			position = position + 1
		end
	end
	return row
end

-- The four fields at the front of a packed row, without decoding the rest.
function S.Head(packed)
	local t, seq, kind, level = packed:match("^([^|]*)|([^|]*)|([^|]*)|([^|]*)")
	return Number(t), Number(seq), kind and Unescape(kind), Number(level)
end

-- Position for (t, seq) in the sorted list (after every row before it).
local function InsertAt(events, t, seq)
	local count = #events
	if count == 0 then return 1 end
	local lastT, lastSeq = S.Head(events[count])
	if (lastT or 0) < t or ((lastT or 0) == t and (lastSeq or 0) <= seq) then return count + 1 end
	local low, high = 1, count
	while low <= high do
		local mid = math.floor((low + high) / 2)
		local midT, midSeq = S.Head(events[mid])
		midT, midSeq = midT or 0, midSeq or 0
		if midT < t or (midT == t and midSeq <= seq) then low = mid + 1 else high = mid - 1 end
	end
	return low
end

-- A roll-up pass that found nothing to fold is remembered (rec.rollupNone
-- = { u = up to level, n = rows, a = first seq, z = last seq }): the next
-- pass waits until you level up or the rows change another way than by a
-- new row past those levels, so a full journal does not read every row
-- again for each new one.
local function Edges(rec)
	local events = rec.events
	local first, last = events[1], events[#events]
	local _, a = S.Head(type(first) == "string" and first or "")
	local _, z = S.Head(type(last) == "string" and last or "")
	return a, z
end

local function NothingToRoll(rec, upTo)
	local memo = rec.rollupNone
	if type(memo) ~= "table" or (upTo and memo.u ~= upTo) or memo.n ~= #rec.events then return false end
	local a, z = Edges(rec)
	return memo.a == a and memo.z == z
end

local function RememberNothing(rec, upTo)
	local a, z = Edges(rec)
	rec.rollupNone = { u = upTo, n = #rec.events, a = a, z = z }
end

---------------------------------------------------------------------------
-- Writing
---------------------------------------------------------------------------
local function ZoneNow()
	local zone = Plain(GetRealZoneText and GetRealZoneText())
	local sub = Plain(GetSubZoneText and GetSubZoneText())
	if type(zone) ~= "string" or zone == "" then zone = nil end
	if type(sub) ~= "string" or sub == "" or sub == zone then sub = nil end
	return zone, sub
end

-- fields: the kind's named fields plus t, level, zone, subzone, keep and
-- ref ("<source>:<id>"). zone = false leaves the place out; level and
-- place default to where you are. Secret values are dropped. Returns the
-- decoded row (with seq), or nil.
function S.Write(kind, fields)
	if type(kind) ~= "string" or not kind:match("^[%w_]+$") then return nil end
	local def = J:Kind(kind)
	if not def or def.derived then return nil end
	fields = type(fields) == "table" and fields or {}
	local rec = Own()
	if not rec then
		if #pending < S.CAP_PENDING then pending[#pending + 1] = { kind, fields } end
		return nil
	end
	local ref = Plain(fields.ref)
	if type(ref) == "string" and rec.refs[ref] then return J:Row(nil, rec.refs[ref]) end
	local row = {}
	for key, value in pairs(fields) do
		if not E:IsSecret(value) then row[key] = value end
	end
	row.kind = kind
	row.t = tonumber(row.t) or Now()
	if row.level == nil then
		local level = Plain(UnitLevel("player"))
		row.level = type(level) == "number" and level or nil
	end
	if row.level ~= nil and not ValidLevel(row.level) then
		if kind == "level" then return nil end
		row.level = nil
	end
	-- A zone that was given but secret stays unknown.
	if rawequal(fields.zone, nil) then
		row.zone, row.subzone = ZoneNow()
	elseif row.zone == nil or row.zone == false then
		row.zone, row.subzone = nil, nil
	end
	rec.seq = (rec.seq or 0) + 1
	row.seq = rec.seq
	local packed = S.Pack(rec, row)
	local memo = NothingToRoll(rec) and rec.rollupNone
	table.insert(rec.events, InsertAt(rec.events, row.t, row.seq), packed)
	if memo and (type(row.level) ~= "number" or row.level > memo.u) then
		RememberNothing(rec, memo.u)
	else
		rec.rollupNone = nil
	end
	if type(ref) == "string" then rec.refs[ref] = row.seq end
	Bump(rec)
	S.CheckCap(rec)
	local decoded = S.Unpack(rec, packed)
	A:Fire("Logged", E.charKey, decoded)
	A:MarkDirty("journal")
	return decoded
end

-- A quest handed in (Chronicle.lua), oldest dropped past the cap.
function S.AddQuest(rec, entry)
	if type(rec) ~= "table" or type(entry) ~= "table" then return end
	rec.quests[#rec.quests + 1] = entry
	while #rec.quests > S.CAP_QUESTS do table.remove(rec.quests, 1) end
	Bump(rec)
end

-- A finished session (Record.lua). Past the cap the oldest fold into a
-- count on their level.
function S.AddSession(rec, entry)
	if type(rec) ~= "table" or type(entry) ~= "table" then return end
	rec.sessions[#rec.sessions + 1] = entry
	while #rec.sessions > S.CAP_SESSIONS do
		local old = table.remove(rec.sessions, 1)
		local level = tonumber(old.level)
		if level then
			rec.levels[level] = type(rec.levels[level]) == "table" and rec.levels[level] or {}
			rec.levels[level].sessions = (tonumber(rec.levels[level].sessions) or 0) + 1
		end
	end
	Bump(rec)
end

---------------------------------------------------------------------------
-- Reading
---------------------------------------------------------------------------
local decodedCache = setmetatable({}, { __mode = "k" })   -- rec -> { rev, rows }
local windowCache = setmetatable({}, { __mode = "k" })    -- rec -> { rev, list = { { from, to, rows } } }
local kindCache = setmetatable({}, { __mode = "k" })      -- rec -> { [kinds] = { rev, rows } }
local zoneCounts = setmetatable({}, { __mode = "k" })     -- rec -> { rev, by = { [zone id] = n } }

local function AllRows(rec)
	local cached = decodedCache[rec]
	if cached and cached.rev == rec.rev and cached.count == #rec.events then return cached.rows end
	local rows = {}
	for position, packed in ipairs(rec.events) do rows[position] = S.Unpack(rec, packed) end
	decodedCache[rec] = { rev = rec.rev, count = #rec.events, rows = rows }
	return rows
end
S.AllRows = AllRows

-- The first place whose row is at or after time t (#events + 1 when none).
local function FirstAt(events, t)
	local low, high = 1, #events
	while low <= high do
		local mid = math.floor((low + high) / 2)
		local midT = S.Head(events[mid]) or 0
		if midT < t then low = mid + 1 else high = mid - 1 end
	end
	return low
end
S.FirstAt = FirstAt

-- Only the rows from `from` to `to`: two binary searches on the packed
-- times, then the rows between them decoded. When every row is decoded
-- already, the window is cut from those.
local function WindowRows(rec, from, to)
	local events = rec.events
	local first, last = FirstAt(events, from), FirstAt(events, to + 1) - 1
	local whole = decodedCache[rec]
	if whole and whole.rev == rec.rev and whole.count == #events then
		local out = {}
		for position = first, last do out[#out + 1] = whole.rows[position] end
		return out
	end
	local kept = windowCache[rec]
	if not kept or kept.rev ~= rec.rev then
		kept = { rev = rec.rev, list = {} }
		windowCache[rec] = kept
	end
	S.stats.windows = S.stats.windows + 1
	for position, window in ipairs(kept.list) do
		if window.from == from and window.to == to then
			-- The newest use moves to the front.
			table.remove(kept.list, position)
			table.insert(kept.list, 1, window)
			S.stats.windowHits = S.stats.windowHits + 1
			return window.rows
		end
	end
	local rows = {}
	for position = first, last do rows[#rows + 1] = S.Unpack(rec, events[position]) end
	local window = { from = from, to = to, rows = rows }
	table.insert(kept.list, 1, window)
	while #kept.list > S.WINDOWS_KEPT do table.remove(kept.list) end
	return rows
end

-- Decoded rows from `from` to `to` (times, inclusive), oldest first. The
-- list is shared: copy before changing it.
function J:Rows(charKey, from, to)
	local rec = self:Char(charKey)
	if not rec then return {} end
	from, to = tonumber(from), tonumber(to)
	if (not from or from <= 0) and (not to or to == math.huge) then return AllRows(rec) end
	return WindowRows(rec, from or 0, to or math.huge)
end

-- The rows of some kinds only ({ dungeon = true, raid = true }): the kind
-- is read from each packed head and only those rows are decoded.
function J:RowsOfKind(charKey, kinds)
	local rec = self:Char(charKey)
	if not (rec and type(kinds) == "table") then return {} end
	local names = {}
	for kind in pairs(kinds) do names[#names + 1] = tostring(kind) end
	table.sort(names)
	local key = table.concat(names, ",")
	local byKind = kindCache[rec]
	if not byKind then
		byKind = {}
		kindCache[rec] = byKind
	end
	local cached = byKind[key]
	if cached and cached.rev == rec.rev then return cached.rows end
	local rows = {}
	for _, packed in ipairs(rec.events) do
		local kind = packed:match("^[^|]*|[^|]*|([^|]*)")
		if kind and kinds[kind] then rows[#rows + 1] = S.Unpack(rec, packed) end
	end
	byKind[key] = { rev = rec.rev, rows = rows }
	return rows
end

-- The n-th part of a packed row, without splitting the rest.
local function Part(packed, n)
	local start = 1
	for _ = 2, n do
		local stop = packed:find("|", start, true)
		if not stop then return nil end
		start = stop + 1
	end
	local stop = packed:find("|", start, true)
	return packed:sub(start, (stop or 0) - 1)
end

-- Rows of some kinds whose own field `name` holds `value`: the value is
-- compared in the packed text and only the rows that hold it are decoded.
function J:RowsWhere(charKey, kinds, name, value)
	local rec = self:Char(charKey)
	if not (rec and type(kinds) == "table" and value ~= nil) then return {} end
	local wanted = {}
	for kind in pairs(kinds) do
		local def = J:Kind(kind)
		for position, field in ipairs(def and def.fields or {}) do
			if field[1] == name then
				local text
				if field[2] == "i" then
					local id = S.StringId(rec, tostring(value))
					text = id and tostring(id) or nil
				elseif field[2] == "n" then
					text = tonumber(value) and EncodeValue(rec, "n", value) or nil
				else
					text = Escape(tostring(value))
				end
				if text then wanted[kind] = { Slot(position), text } end
			end
		end
	end
	local rows = {}
	if not next(wanted) then return rows end
	for _, packed in ipairs(rec.events) do
		local kind = packed:match("^[^|]*|[^|]*|([^|]*)")
		local want = kind and wanted[kind]
		if want and Part(packed, want[1]) == want[2] then rows[#rows + 1] = S.Unpack(rec, packed) end
	end
	return rows
end

-- How many rows name a zone: the zone's number is compared in the packed
-- heads, nothing is decoded. Counted once per revision.
function J:ZoneCount(charKey, zone)
	local rec = self:Char(charKey)
	local id = rec and S.StringId(rec, zone)
	if not id then return 0 end
	local counts = zoneCounts[rec]
	if not counts or counts.rev ~= rec.rev then
		counts = { rev = rec.rev, by = {} }
		for _, packed in ipairs(rec.events) do
			local z = tonumber(packed:match("^[^|]*|[^|]*|[^|]*|[^|]*|([^|]*)") or "")
			if z then counts.by[z] = (counts.by[z] or 0) + 1 end
		end
		zoneCounts[rec] = counts
	end
	return counts.by[id] or 0
end

function J:Row(charKey, seq)
	local rec = self:Char(charKey)
	seq = tonumber(seq)
	if not (rec and seq) then return nil end
	for position = #rec.events, 1, -1 do
		local _, rowSeq = S.Head(rec.events[position])
		if rowSeq == seq then return S.Unpack(rec, rec.events[position]), position end
	end
	return nil
end

---------------------------------------------------------------------------
-- Cap, roll-up and trim
---------------------------------------------------------------------------
local function CurrentLevel(rec)
	local level = Plain(UnitLevel("player"))
	if type(level) == "number" then return level end
	local last = rec.events[#rec.events]
	if not last then return 1 end
	local _, _, _, rowLevel = S.Head(last)
	return rowLevel or 1
end

-- Fold the ordinary rows of chapters at least ROLLUP_BEHIND levels back
-- into one summary row per chapter, oldest chapter first, until the
-- journal is under the target. yield (optional) is called between rows
-- while the rows are read; the list itself changes in one step at the
-- end, so rows written meanwhile are kept.
local function Summarize(rec, rows)
	local counts, order = {}, {}
	local summary, first, last, best, bestQuality
	for _, row in ipairs(rows) do
		if row.kind == "rollup" then
			summary = summary or row
			for name, count in (row.counts or ""):gmatch("([%w_]+):(%d+)") do
				if not counts[name] then order[#order + 1] = name end
				counts[name] = (counts[name] or 0) + tonumber(count)
			end
			if row.best and (row.bestQuality or 0) > (bestQuality or -1) then best, bestQuality = row.best, row.bestQuality end
		else
			if not counts[row.kind] then order[#order + 1] = row.kind end
			counts[row.kind] = (counts[row.kind] or 0) + 1
			if row.kind == "loot" and row.item and (row.quality or 0) > (bestQuality or -1) then
				best, bestQuality = row.item, row.quality
			end
		end
		if not first or (row.t or 0) < (first.t or 0) then first = row end
		last = math.max(last or 0, row.to or row.t or 0)
	end
	local parts = {}
	for _, name in ipairs(order) do parts[#parts + 1] = ("%s:%d"):format(name, counts[name]) end
	return { kind = "rollup", t = first.t, seq = (summary or first).seq, level = first.level, zone = first.zone,
		counts = table.concat(parts, ","), best = best, bestQuality = bestQuality, to = last }
end
S.Summarize = Summarize

function S.Rollup(rec, yield, behindLevel)
	if type(rec) ~= "table" then return 0 end
	local target = math.floor(S.CAP_EVENTS * S.ROLLUP_TARGET)
	if #rec.events <= target then return 0 end
	local upTo = (behindLevel or CurrentLevel(rec)) - S.ROLLUP_BEHIND
	if NothingToRoll(rec, upTo) then return 0 end
	-- Read: the rows that may roll, by chapter.
	local byLevel, levels = {}, {}
	for _, packed in ipairs(rec.events) do
		local _, _, kind, level = S.Head(packed)
		if level and level <= upTo then
			local row = S.Unpack(rec, packed)
			if kind == "rollup" or J:Rollable(row) then
				if not byLevel[level] then
					byLevel[level] = {}
					levels[#levels + 1] = level
				end
				local list = byLevel[level]
				list[#list + 1] = row
			end
		end
		if yield then yield() end
	end
	table.sort(levels)
	-- Plan: oldest chapters first, until the count is under the target.
	local count, drop, adds, folded = #rec.events, {}, {}, 0
	local stopped = false
	for _, level in ipairs(levels) do
		if count <= target then
			stopped = true
			break
		end
		local rows = byLevel[level]
		local plain = 0
		for _, row in ipairs(rows) do
			if row.kind ~= "rollup" then plain = plain + 1 end
		end
		if plain > 0 and #rows > 1 or plain > 1 then
			for _, row in ipairs(rows) do drop[row.seq] = true end
			adds[#adds + 1] = S.Pack(rec, Summarize(rec, rows))
			count = count - #rows + 1
			folded = folded + plain
		end
		if yield then yield() end
	end
	if not adds[1] then
		RememberNothing(rec, upTo)
		return 0
	end
	rec.rollupNone = nil
	-- Write, in one step.
	local keep = {}
	for _, packed in ipairs(rec.events) do
		local _, seq = S.Head(packed)
		if not drop[seq] then keep[#keep + 1] = packed end
	end
	for _, packed in ipairs(adds) do
		local t, seq = S.Head(packed)
		table.insert(keep, InsertAt(keep, t or 0, seq or 0), packed)
	end
	rec.events = keep
	-- Every chapter that may roll is one summary now: nothing more to roll.
	if not stopped then RememberNothing(rec, upTo) end
	Bump(rec)
	return folded
end

-- A row's worth (J:Worth) from its packed head when its kind alone says
-- it; nil when the row must be read (a kind with keepsakes).
local function HeadWorth(packed)
	if Part(packed, 10) == "1" then return 3 end
	local kind = packed:match("^[^|]*|[^|]*|([^|]*)")
	local def = kind and J:Kind(Unescape(kind))
	if not def then return 1 end
	local worth = def.worth or 1
	if worth >= 3 then return 3 end
	if type(def.keepsake) == "function" and not (A.db and A.db.keepsakes == false) then return nil end
	return math.max(worth, 1)
end

-- How many of the oldest rows a trim already found worth keeping
-- (rec.trimSkip = { x = rows, s = seq of the last of them, a = seq of the
-- first, k = keepsakes on }), while those rows are still the same.
local function KeepsakesOn()
	return not (A.db and A.db.keepsakes == false)
end

local function TrimSkip(rec)
	local memo = rec.trimSkip
	if type(memo) ~= "table" or memo.k ~= KeepsakesOn() then return 0 end
	local x, events = tonumber(memo.x) or 0, rec.events
	if x < 1 or x > #events then return 0 end
	local _, a = S.Head(events[1])
	local _, last = S.Head(events[x])
	if a ~= memo.a or last ~= memo.s then return 0 end
	return x
end

-- Drop the least worth rows, oldest first, until the journal fits. Rows
-- are read oldest first only until enough of the least worth are found,
-- only when their kind alone does not tell their worth, and the oldest
-- rows a trim found worth keeping are not read again.
function S.Trim(rec)
	local over = #rec.events - S.CAP_EVENTS
	if over <= 0 then return 0 end
	local memo = NothingToRoll(rec)
	local events = rec.events
	local worthAt, drop = {}, {}
	local skip = TrimSkip(rec)
	local lead = skip
	for worth = 1, 3 do
		for position = worth == 1 and skip + 1 or 1, #events do
			if over <= 0 then break end
			if not drop[position] then
				local value = worthAt[position]
				if not value then
					value = HeadWorth(events[position]) or J:Worth(S.Unpack(rec, events[position]))
					value = math.min(math.max(value, 1), 3)
					worthAt[position] = value
				end
				if value == worth then
					drop[position] = true
					over = over - 1
				elseif worth == 1 and position == lead + 1 then
					lead = position
				end
			end
		end
	end
	local keep = {}
	for position, packed in ipairs(rec.events) do
		if not drop[position] then keep[#keep + 1] = packed end
	end
	local dropped = #rec.events - #keep
	rec.events = keep
	-- The oldest rows read and kept stay where they were.
	if lead > 0 and lead <= #keep then
		local _, a = S.Head(keep[1])
		local _, last = S.Head(keep[lead])
		rec.trimSkip = { x = lead, s = last, a = a, k = KeepsakesOn() }
	else
		rec.trimSkip = nil
	end
	-- Fewer rows fold no better: nothing to roll stays true.
	if memo then RememberNothing(rec, rec.rollupNone.u) else rec.rollupNone = nil end
	Bump(rec)
	return dropped
end

function S.MakeRoom(rec, yield)
	S.Rollup(rec, yield)
	return S.Trim(rec)
end

-- Past the cap: a roll-up job (out of combat, in slices). Far past it
-- (the job cannot run, a big import): trim now.
function S.CheckCap(rec)
	local count = #rec.events
	if count <= S.CAP_EVENTS then return end
	if count > S.CAP_EVENTS + S.HARD_SLACK then
		S.MakeRoom(rec)
		return
	end
	A:RunJob("rollup", function() S.MakeRoom(rec, A.JobYield) end, function() A:MarkDirty("journal") end)
end

function J:Rollup(charKey)
	local rec = self:Char(charKey)
	if not rec then return 0 end
	local folded = S.Rollup(rec)
	S.Trim(rec)
	A:MarkDirty("journal")
	return folded
end

---------------------------------------------------------------------------
-- Soft delete and undo (7 days), archive
---------------------------------------------------------------------------
local restorers = {}

-- A file that trashes its own things says how to put them back:
-- A:AddRestorer(kind, function(rec, data) end).
function A:AddRestorer(kind, fn)
	if type(kind) == "string" then restorers[kind] = type(fn) == "function" and fn or nil end
end

function S.TrashItem(rec, kind, data)
	local id = S.NewId(rec)
	rec.trash[#rec.trash + 1] = { id = id, at = Now(), kind = kind, data = data }
	Bump(rec)
	return id
end

function S.PurgeTrash(rec, now)
	now = now or Now()
	for position = #rec.trash, 1, -1 do
		local item = rec.trash[position]
		if type(item) ~= "table" or (tonumber(item.at) or 0) + S.TRASH_SECONDS < now then table.remove(rec.trash, position) end
	end
end

A:AddRestorer("row", function(rec, packed)
	local t, seq = S.Head(packed)
	table.insert(rec.events, InsertAt(rec.events, t or 0, seq or 0), packed)
	rec.rollupNone = nil
end)

-- Delete one of this character's rows; returns the trash id for Undo.
function J:DeleteRow(seq)
	local rec = Own()
	local row, position = self:Row(nil, seq)
	if not (rec and row) then return nil end
	local packed = table.remove(rec.events, position)
	for ref, refSeq in pairs(rec.refs) do
		if refSeq == row.seq then rec.refs[ref] = nil end
	end
	local id = S.TrashItem(rec, "row", packed)
	A:MarkDirty("journal")
	return id
end

function J:Undo(trashID)
	local rec = Own()
	trashID = tonumber(trashID)
	if not (rec and trashID) then return false end
	for position, item in ipairs(rec.trash) do
		if item.id == trashID then
			local restore = restorers[item.kind]
			if not restore then return false end
			table.remove(rec.trash, position)
			local ok, err = pcall(restore, rec, item.data)
			if not ok then geterrorhandler()(err) end
			Bump(rec)
			A:MarkDirty("journal")
			return ok
		end
	end
	return false
end

function J:Trash(charKey)
	local rec = self:Char(charKey)
	return rec and rec.trash or {}
end

function J:SetArchived(list, id, on)
	local rec = Own()
	if not rec or (list ~= "goals" and list ~= "notes") then return false end
	for _, entry in ipairs(rec[list]) do
		if type(entry) == "table" and entry.id == id then
			entry.archived = on and Now() or nil
			Bump(rec)
			A:MarkDirty(list)
			return true
		end
	end
	return false
end

---------------------------------------------------------------------------
-- Clear and forget
---------------------------------------------------------------------------
function J:Clear(charKey)
	local root = Root()
	charKey = charKey or E.charKey
	if not (root and charKey) then return false end
	-- An empty journal with the same GUID, so no older copy comes back.
	local old = root[charKey]
	local guid = type(old) == "table" and type(old.guid) == "string" and old.guid
		or (charKey == E.charKey and MyGUID()) or nil
	if guid then
		local rec = New(guid)
		if charKey ~= E.charKey then rec.startedLevel = nil end
		root[charKey] = rec
	else
		root[charKey] = nil
	end
	decodedCache = setmetatable({}, { __mode = "k" })
	windowCache = setmetatable({}, { __mode = "k" })
	kindCache = setmetatable({}, { __mode = "k" })
	zoneCounts = setmetatable({}, { __mode = "k" })
	A:Fire("Cleared", charKey)
	A:MarkDirty("all")
	return true
end

-- The Alts window forgot a character: Core/CharacterStore.lua kept a
-- backup and let the journal go (its dated backups stay too). Here the
-- pages let go of what they showed.
local function Forgotten(_, key)
	if type(key) ~= "string" or key == E.charKey then return end
	decodedCache = setmetatable({}, { __mode = "k" })
	windowCache = setmetatable({}, { __mode = "k" })
	kindCache = setmetatable({}, { __mode = "k" })
	zoneCounts = setmetatable({}, { __mode = "k" })
	A:Fire("Cleared", key)
	A:MarkDirty("all")
end
S.Forgotten = Forgotten

---------------------------------------------------------------------------
-- Observed content (Observe.lua): account-wide, in the shape the Loot
-- Guide's quest data reads (top of Modules/LootGuide/Quests.lua):
--   journalSeen = { v = 1, rev = n,
--     quests = { [questID] = { t, title, level, minLevel, giver, giverName, map, x, y,
--                              header, plevel, faction, ender, enderName, xp, money } },
--     instances = { [instanceMapID] = { t, name, size, min, max } },
--     zones = { [uiMapID] = { t, name, min, max } } }
-- At most 600 entries over the three lists; past that the oldest go.
--   J:Seen()                     the table (made on first use)
--   J:AddSeen(list, id, fields)  merge fields into one entry; false when
--                                nothing changed. The caller then calls
--                                LG:JourneyChanged() (Observe.lua does).
---------------------------------------------------------------------------
S.SEEN_LISTS = { "quests", "instances", "zones" }

-- The load check: the first data shape's `rows` list and values of the
-- wrong kind are set aside, never reset.
local function CheckSeen(seen, C)
	-- An empty placeholder holds nothing to keep.
	if type(seen.rows) == "table" and next(seen.rows) == nil then
		seen.rows = nil
	elseif seen.rows ~= nil then
		C.Keep("rows", seen.rows, "An older shape of this list.")
		seen.rows = nil
	end
	C.Number(seen, "rev", nil, 0)
	for _, list in ipairs(S.SEEN_LISTS) do C.Table(seen, list) end
end
E:RegisterStore("journalSeen", { title = "Journal: places and quests seen", validate = CheckSeen })

local seenChecked = setmetatable({}, { __mode = "k" })

function J:Seen()
	if type(EldoUIDB) ~= "table" then return { v = 1, rev = 0, quests = {}, instances = {}, zones = {} } end
	local seen = EldoUIDB.journalSeen
	if type(seen) ~= "table" then
		-- First use (anything else saved here is kept inside the new table).
		seen = E:KeepInNewTable(seen, "journalSeen")
		seen.v, seen.rev = 1, 0
		EldoUIDB.journalSeen = seen
	end
	if not seenChecked[seen] then
		seenChecked[seen] = true
		E:MigrateStore("journalSeen", seen)
	end
	seen.rev = tonumber(seen.rev) or 0
	for _, list in ipairs(S.SEEN_LISTS) do
		if type(seen[list]) ~= "table" then seen[list] = {} end
	end
	return seen
end

-- Entries over the three lists, and the oldest one.
local function SeenCount(seen)
	local count, oldest, oldestList, oldestID = 0, nil, nil, nil
	for _, list in ipairs(S.SEEN_LISTS) do
		for id, row in pairs(seen[list]) do
			count = count + 1
			local t = type(row) == "table" and tonumber(row.t) or 0
			if not oldest or t < oldest then oldest, oldestList, oldestID = t, list, id end
		end
	end
	return count, oldestList, oldestID
end

function J:AddSeen(list, id, fields)
	if not tContains(S.SEEN_LISTS, list) or type(id) ~= "number" or type(fields) ~= "table" then return false end
	local seen = self:Seen()
	local row = seen[list][id]
	local fresh = type(row) ~= "table"
	if fresh then row = {} end
	local changed = fresh
	for key, value in pairs(fields) do
		local kind = type(value)
		if key ~= "t" and not E:IsSecret(value) and (kind == "string" or kind == "number" or kind == "boolean")
			and row[key] ~= value then
			row[key] = value
			changed = true
		end
	end
	if not changed then return false end
	row.t = tonumber(fields.t) or Now()
	seen[list][id] = row
	seen.rev = seen.rev + 1
	local count, oldList, oldID = SeenCount(seen)
	while count > S.CAP_SEEN and oldList do
		seen[oldList][oldID] = nil
		count, oldList, oldID = SeenCount(seen)
	end
	return true
end

---------------------------------------------------------------------------
-- Size: the length of the record as SavedVariables would write it.
---------------------------------------------------------------------------
local function Bytes(value, depth)
	local kind = type(value)
	if kind == "string" then return #value + 4 end
	if kind == "number" then return #tostring(value) + 2 end
	if kind == "boolean" then return 6 end
	if kind ~= "table" or depth > 12 then return 4 end
	local total = 4
	for key, item in pairs(value) do
		total = total + Bytes(key, depth + 1) + Bytes(item, depth + 1) + 4
	end
	return total
end

function J:Size(charKey)
	local rec = self:Char(charKey)
	return rec and Bytes(rec, 0) or 0
end

---------------------------------------------------------------------------
-- Part: the Forget hook (always), trash purge and the tag check on start
---------------------------------------------------------------------------
A:AddPart("store", {
	order = 1,
	init = function()
		local C = E.Characters
		if C and C.RegisterCallback then C.RegisterCallback(A, "Forgotten", Forgotten) end
	end,
	start = function()
		local rec = Own()
		if rec then S.PurgeTrash(rec) end
	end,
})
