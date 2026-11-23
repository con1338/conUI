-- EldoUI My Adventure: dated compressed backups, restore by merge or replace, clearing the journal.
--
-- An addon cannot write files of its own. What it can do is keep copies in
-- its saved data, which the game writes to disk at logout or /reload. So:
--   * Backups: dated copies of a character's journal in
--     EldoUIDB.journalBackups[charKey] (newest first, keep N), each one a
--     compressed "!EUJ1!" code. Taken on a schedule (8 s after login, out
--     of combat), by hand, and before restoring, importing or clearing.
--     A long journal's scheduled backup and its copy before an update are
--     written by a job in slices (see "Backups written in slices").
--     The newest "before update" copy (taken before an EldoUI update
--     changes the journal, Store.lua) has a slot of its own: the other
--     backups never push it out.
--   * Forgetting a character in the Alts window (Core/CharacterStore.lua)
--     keeps one backup of its journal apart, in journalCache.forgotten; the
--     Saved data page puts it back or, when the player asks, removes it.
--   * Backup code: the same "!EUJ1!" code in a copy box, to paste back in
--     on this PC or another. It goes through E:DecodeShareData, which only
--     ever builds plain data (nothing pasted is run as code).
--   * Restore: Merge adds everything the backup has that the journal lacks
--     and keeps everything since; Replace puts the journal back exactly as
--     it was. The journal as it is now is backed up first either way.
-- Nothing is sent anywhere: the share kind "journal" has no `build`, so
-- E:SendShare cannot send a journal. Copy boxes only.
--
-- A backup entry: { at, level, reason, counts = { rows, quests, notes,
-- goals }, size, data = "!EUJ1!..." }. The code holds
-- { at, charKey, who = { name, class, race, level }, journal = <the record
-- without its trash> }: the goals, notes, keepNotes, quests (with
-- `archived`) and abandoned lists come along with every row.
--
-- API (E.Adventure.Backup):
--   B:List([charKey])                 the backups, newest first
--   B:Take(reason[, charKey])         a backup now -> entry (nil when empty)
--   B:TakeRecord(rec, reason[, charKey])  the same, of a record in hand
--   B:TakeSliced(rec, reason[, charKey]), B:TakeBeforeUpdate(rec[, charKey])
--                                     a long journal's backup, written by a
--                                     job in slices; B:EntryData(entry)
--                                     what a backup holds, also while pending
--   B:Due([charKey, now])             a scheduled backup is due
--   B:Restore(index, mode[, charKey]) mode "merge" or "replace" -> ok, err
--   B:KeepForgotten(rec, charKey)     the backup before a character is forgotten
--   B:ForgottenList(), B:RestoreForgotten(charKey), B:RemoveForgotten(charKey)
--                                     the Saved data page; B:ResumeForgotten()
--                                     writes a long journal's code at login
--   B:KeepOrphan(entry), B.OrphanJournal(entry), B.OrphanRows(entry)
--                                     journals of another character, packed;
--   B:RemoveOrphan(entry), B:GiveOrphan(entry)  the Saved data page
--   B:Delete(index[, charKey])
--   B:Code([charKey])                 the "!EUJ1!" code of the journal now
--   B:Read(text)                      a pasted code -> payload | nil, err
--                                     ("!EUJ1!" codes and Forever Journal
--                                     "FJ1:" and "FJ2:" codes, Import.lua)
--   B:ImportText(text, mode)          paste into this character -> ok, err
--   B:AskImportCode(), B:AskRestore(index), B:ShowRestoreMenu([owner])
--   B.Merge(dst, src[, opts]) -> stats, B.ReplaceRecord(charKey, journal)
--   B.Copy(value)                     a plain deep copy (no loops, no secrets)
--   A.BackupOptions                   the option rows (Options.lua places them)
--
-- Portions adapted from Forever Journal by Ugge Zen, MIT License (see
-- THIRD_PARTY_NOTICES.md): the backup schedules and their slack, the
-- backups kept apart from the live journal, the merge rules (lists by what
-- they say and when, numbers the higher, "first" numbers the earlier, ids
-- renumbered on a clash) and the restore wording.
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

local Plain = A.Plain

local B = {}
A.Backup = B

B.PREFIX = "!EUJ1!"
B.LOGIN_DELAY = 8
-- A little slack: the same time tomorrow counts as a day.
B.EVERY = { login = 0, day = 20 * 3600, week = 6 * 86400 + 20 * 3600 }
B.SCHEDULES = { "login", "day", "week", "manual" }
B.MAX_DEPTH = 30
-- A journal with more rows and quests than this is backed up by a job in
-- slices (the scheduled backup and the copy before an update), so a long
-- journal never stalls a frame; a smaller one is backed up at once.
B.SYNC_ROWS = 1000
B.SLICE = 400            -- values copied or written per slice
-- Work counters for the large-data checks: slices handed back to the frame.
B.stats = { slices = 0, sliced = 0 }

local function Now()
	return time()
end

---------------------------------------------------------------------------
-- Plain copies
---------------------------------------------------------------------------
local function Copy(value, seen, depth)
	if E:IsSecret(value) then return nil end
	local kind = type(value)
	if kind ~= "table" then
		if kind == "string" or kind == "number" or kind == "boolean" then return value end
		return nil
	end
	seen, depth = seen or {}, depth or 0
	if seen[value] or depth > B.MAX_DEPTH then return nil end   -- never a loop
	seen[value] = true
	local out = {}
	for key, item in pairs(value) do
		local keyKind = type(key)
		if (keyKind == "string" or keyKind == "number") and not E:IsSecret(key) then
			out[key] = Copy(item, seen, depth + 1)
		end
	end
	seen[value] = nil
	return out
end
B.Copy = function(value) return Copy(value) end

-- A job's yield: hands the frame back after every `size` calls, or at once
-- when called with true (the job runner then goes on in the same frame
-- while time is left).
local function Slicer(size)
	local count = 0
	return function(now)
		count = count + 1
		if now or count >= size then
			count = 0
			B.stats.slices = B.stats.slices + 1
			coroutine.yield()
		end
	end
end
B.Slicer = Slicer

-- Copy with yield() after every value, at every depth, so no slice copies
-- more than a few hundred values. A list is read by its numbers and the
-- other keys of a table are read first, its values after them, so a row
-- added meanwhile is simply not in the copy and a table is never read
-- with pairs across a yield (it may change while the job waits). Each part
-- of a record starts a frame of its own, and so does the copying after a
-- long table's keys were read.
local function CopySliced(value, yield, skip, seen, depth)
	if type(value) ~= "table" or E:IsSecret(value) then return Copy(value) end
	seen, depth = seen or {}, depth or 0
	if seen[value] or depth > B.MAX_DEPTH then return nil end   -- never a loop
	local listed = #value
	local keys, count = {}, 0
	for key in pairs(value) do
		local keyKind = type(key)
		if keyKind == "string" or (keyKind == "number" and not (key >= 1 and key <= listed and key % 1 == 0)) then
			count = count + 1
			keys[count] = key
		end
	end
	if listed + count >= B.SLICE then yield(true) end
	seen[value] = true
	local out = {}
	local function Put(key)
		if (skip and skip[key]) or E:IsSecret(key) then return end
		local item = value[key]
		if type(item) == "table" then
			if depth == 0 then yield(true) end
			out[key] = CopySliced(item, yield, nil, seen, depth + 1)
		else
			out[key] = Copy(item)
		end
		yield()
	end
	for index = 1, listed do Put(index) end
	for index = 1, count do Put(keys[index]) end
	seen[value] = nil
	return out
end

-- A record copied in slices, without the keys in `skip`.
local function CopyRecordSliced(rec, yield, skip)
	return CopySliced(rec, yield, skip)
end
B.CopyRecordSliced = CopyRecordSliced

local function Count(list)
	return type(list) == "table" and #list or 0
end

-- The character a journal belongs to (its GUID tag), or nil.
local function Owner(rec)
	local guid = type(rec) == "table" and rec.guid
	return type(guid) == "string" and guid ~= "" and guid or nil
end

local function HasData(rec)
	return type(rec) == "table" and (Count(rec.events) > 0 or Count(rec.goals) > 0 or Count(rec.notes) > 0
		or Count(rec.quests) > 0)
end
B.HasData = HasData

---------------------------------------------------------------------------
-- Where backups live
---------------------------------------------------------------------------
-- create = "drop" lets the character's list go (it was forgotten).
local function Store(charKey, create)
	charKey = charKey or E.charKey
	if type(EldoUIDB) ~= "table" or not charKey then return nil end
	local all = EldoUIDB.journalBackups
	if create == "drop" then
		if type(all) == "table" then all[charKey] = nil end
		return nil
	end
	if type(all) ~= "table" then
		if not create then return nil end
		all = {}
		EldoUIDB.journalBackups = all
	end
	local list = all[charKey]
	if type(list) ~= "table" then
		if not create then return nil end
		list = {}
		all[charKey] = list
	end
	return list
end

function B:List(charKey)
	return Store(charKey) or {}
end

-- Who the journal belongs to (the Characters record for another character).
local function Who(charKey)
	if charKey == nil or charKey == E.charKey then
		local _, class = UnitClass("player")
		local level = Plain(UnitLevel("player"))
		return { name = Plain(E:PlayerName()), class = Plain(class), race = Plain((UnitRace("player"))),
			level = type(level) == "number" and level or nil }
	end
	local C = E.Characters
	local record = C and C.Get and C:Get(charKey)
	if type(record) ~= "table" then return { name = tostring(charKey):match("^(.-)%-") or tostring(charKey) } end
	return { name = record.name, class = record.class, race = record.race, level = tonumber(record.level) }
end
B.Who = Who

---------------------------------------------------------------------------
-- The code: "!EUJ1!" + flag + payload (Core/Share.lua's encoder)
---------------------------------------------------------------------------
local SKIP_KEYS = { trash = true }

-- The record as plain data, without its trash (soft deletes stay local).
local function Snapshot(rec)
	local out = {}
	for key, value in pairs(rec) do
		if not SKIP_KEYS[key] then out[key] = Copy(value) end
	end
	return out
end
B.Snapshot = Snapshot

function B.Encode(rec, charKey)
	if type(rec) ~= "table" then return nil, L["There is no journal to back up yet."] end
	local payload = { at = Now(), charKey = charKey or E.charKey, who = Who(charKey), journal = Snapshot(rec) }
	return E:EncodeShareData("journal", payload)
end

function B:Code(charKey)
	return B.Encode(J:Char(charKey), charKey)
end

local function Valid(journal)
	return type(journal) == "table" and type(journal.events) == "table" and type(journal.strings) == "table"
end

-- A pasted code -> { at, who, journal, fj } or nil and a clear message.
function B:Read(text)
	if type(text) ~= "string" or E:IsSecret(text) then return nil, L["Nothing to read. Paste a journal code first."] end
	text = strtrim(text)
	if text == "" then return nil, L["Nothing to read. Paste a journal code first."] end
	local I = A.Import
	if text:match("^FJ[12]:") and I and I.ReadCode then return I:ReadCode(text) end
	if text:sub(1, #B.PREFIX) ~= B.PREFIX then
		return nil, L["That is not a journal code. Look for !EUJ1!, FJ2: or FJ1: at the start."]
	end
	local kind, data = E:DecodeShareData(text)
	if not kind then return nil, (L["The code is incomplete or damaged (%s). Copy all of it and paste it again."]):format(tostring(data)) end
	if kind ~= "journal" or type(data) ~= "table" or not Valid(data.journal) then
		return nil, L["The code is incomplete or damaged. Copy all of it and paste it again."]
	end
	return data
end

---------------------------------------------------------------------------
-- Merging: a backup and the live journal become one journal, with nothing
-- lost from either.
--   * Rows: every row of the backup that the journal does not have is
--     added (rows match on what they say and when, not on their seq,
--     which two copies hand out on their own). Rows a chapter summary of
--     the journal already covers are not added again.
--   * Lists (goals, notes, quests, sessions, abandoned): entries match on
--     what they say and when; an added goal or note whose id is taken
--     gets a new one, and the rows and pins that name it follow.
--   * Numbers (time, kills, deaths per level and zone, totals): the
--     higher of the two. "When it first happened" numbers take the
--     earlier of the two instead.
--   * Everything else (text, flags): the journal's, filled in from the
--     backup where it has nothing.
---------------------------------------------------------------------------
local EARLIEST = { first = true, started = true, firstLevel = true, reached = true, at = true, met = true, metLevel = true,
	theirMetLevel = true, lowLevel = true, startedLevel = true }
-- Top-level keys the merge handles itself (or leaves alone).
local OWN = { events = true, strings = true, goals = true, notes = true, quests = true, sessions = true, abandoned = true,
	trash = true, refs = true, keepNotes = true, ui = true, guid = true, v = true, seq = true, rev = true, salt = true,
	nextId = true, imported = true }

local function IsList(t)
	if type(t) ~= "table" then return false end
	local n = #t
	if n == 0 then return false end
	local count = 0
	for _ in pairs(t) do count = count + 1 end
	return count == n
end

local function ShallowKey(value)
	if type(value) ~= "table" then return tostring(value) end
	local keys = {}
	for key, item in pairs(value) do
		if type(item) ~= "table" then keys[#keys + 1] = tostring(key) .. "=" .. tostring(item) end
	end
	table.sort(keys)
	return table.concat(keys, "\31")
end

local MergeInto
local function MergeList(mine, theirs)
	local have = {}
	for _, item in ipairs(mine) do have[ShallowKey(item)] = true end
	for _, item in ipairs(theirs) do
		local key = ShallowKey(item)
		if not have[key] then
			mine[#mine + 1] = Copy(item)
			have[key] = true
		end
	end
end

function MergeInto(mine, theirs)
	for key, value in pairs(theirs) do
		local current = mine[key]
		if current == nil then
			mine[key] = Copy(value)
		elseif type(current) == "table" and type(value) == "table" then
			if IsList(current) and IsList(value) then MergeList(current, value) else MergeInto(current, value) end
		elseif type(current) == "number" and type(value) == "number" then
			if EARLIEST[key] then mine[key] = math.min(current, value) else mine[key] = math.max(current, value) end
		end
	end
end
B.MergeInto = MergeInto

-- A row's content, without its seq and keep slots.
local function RowKey(packed)
	local parts = S.Split(packed)
	parts[2] = ""
	parts[10] = ""
	return table.concat(parts, "|")
end
B.RowKey = RowKey

local function GoalKey(goal)
	return table.concat({ tostring(goal.kind), tostring(goal.created), tostring(goal.itemID or goal.target or goal.name),
		tostring(goal.need) }, "\31")
end

local function NoteKey(note)
	return tostring(note.t) .. "\31" .. tostring(note.text)
end

local function QuestKey(quest)
	return table.concat({ tostring(quest.t), tostring(quest.id), tostring(quest.title) }, "\31")
end

local function ByTime(a, b)
	local x, y = type(a) == "table" and tonumber(a.t) or 0, type(b) == "table" and tonumber(b.t) or 0
	return x < y
end

-- Entries of `theirs` that `mine` lacks, by key. ids: an id map for goals
-- and notes (ids taken in `mine` are renumbered). skip(entry) leaves one out.
local function MergeEntries(dst, mine, theirs, keyOf, ids, skip)
	local have, taken, added = {}, {}, 0
	for _, entry in ipairs(mine) do
		if type(entry) == "table" then
			have[keyOf(entry)] = entry
			if ids and entry.id then taken[entry.id] = true end
		end
	end
	for _, entry in ipairs(theirs) do
		if type(entry) == "table" then
			local same = have[keyOf(entry)]
			if same then
				if ids and entry.id then ids[entry.id] = same.id end
			elseif not (skip and skip(entry)) then
				local copy = Copy(entry)
				if ids and copy.id ~= nil then
					local old = copy.id
					if taken[copy.id] or type(copy.id) ~= "number" then copy.id = S.NewId(dst) end
					taken[copy.id] = true
					ids[old] = copy.id
				end
				mine[#mine + 1] = copy
				have[keyOf(copy)] = copy
				added = added + 1
			end
		end
		A.JobYield()
	end
	if added > 0 then table.sort(mine, ByTime) end
	return added
end

local function MaxId(rec)
	local top = 0
	for _, list in ipairs({ rec.goals, rec.notes, rec.quests, rec.trash }) do
		for _, entry in ipairs(type(list) == "table" and list or {}) do
			local id = type(entry) == "table" and tonumber(entry.id)
			if id and id > top then top = id end
		end
	end
	return top
end

-- opts: skip(row) leaves an incoming row out (Import.lua's high-water
-- mark), skipEntry(kind, entry) leaves a list entry out.
function B.Merge(dst, src, opts)
	opts = opts or {}
	local stats = { rows = 0, goals = 0, notes = 0, quests = 0 }
	if type(dst) ~= "table" or type(src) ~= "table" then return stats end
	S.Fill(dst)
	src = Copy(src)
	S.Migrate(src)
	dst.nextId = math.max(tonumber(dst.nextId) or 1, tonumber(src.nextId) or 1, MaxId(dst) + 1)
	local function Skip(kind)
		if not opts.skipEntry then return nil end
		return function(entry) return opts.skipEntry(kind, entry) end
	end

	-- Goals and notes first: rows and pins name them by id.
	local goalIds, noteIds = {}, {}
	stats.goals = MergeEntries(dst, dst.goals, src.goals, GoalKey, goalIds, Skip("goals"))
	local notesBefore = #dst.notes
	stats.notes = MergeEntries(dst, dst.notes, src.notes, NoteKey, noteIds, Skip("notes"))
	stats.quests = MergeEntries(dst, dst.quests, src.quests, QuestKey, nil, Skip("quests"))
	while #dst.quests > S.CAP_QUESTS do table.remove(dst.quests, 1) end
	MergeEntries(dst, dst.sessions, src.sessions, function(entry) return tostring(entry.login) end, nil, Skip("sessions"))
	if type(src.abandoned) == "table" then
		if type(dst.abandoned) ~= "table" then dst.abandoned = {} end
		MergeEntries(dst, dst.abandoned, src.abandoned, function(entry) return tostring(entry.t) .. "\31" .. tostring(entry.id) end,
			nil, Skip("abandoned"))
	end

	-- Rows.
	local keys, covered = {}, {}
	for _, packed in ipairs(dst.events) do
		local _, seq, kind = S.Head(packed)
		keys[RowKey(packed)] = seq
		if kind == "rollup" then
			local row = S.Unpack(dst, packed)
			if row and row.level then covered[row.level] = math.max(covered[row.level] or 0, tonumber(row.to) or tonumber(row.t) or 0) end
		end
		A.JobYield()
	end
	local rowMap, added = {}, {}
	for _, packed in ipairs(src.events) do
		local row = S.Unpack(src, packed)
		if row and J:Kind(row.kind) then
			local old = row.seq
			if (row.kind == "goal" or row.kind == "goalset") and row.goal ~= nil then row.goal = goalIds[row.goal] or row.goal end
			if row.kind == "note" and row.note ~= nil then row.note = noteIds[row.note] or row.note end
			local skip = opts.skip and opts.skip(row)
			local cover = row.level and covered[row.level]
			if cover and (row.kind == "rollup" or (J:Rollable(row) and (row.t or 0) <= cover)) then skip = true end
			row.seq = nil
			local key = not skip and RowKey(S.Pack(dst, row))
			if key and keys[key] then
				if old then rowMap[old] = keys[key] end
			elseif key then
				dst.seq = (tonumber(dst.seq) or 0) + 1
				row.seq = dst.seq
				local repacked = S.Pack(dst, row)
				added[#added + 1] = repacked
				keys[key] = row.seq
				if old then rowMap[old] = row.seq end
			end
		end
		A.JobYield()
	end
	if added[1] then
		local list = {}
		for _, packed in ipairs(dst.events) do list[#list + 1] = packed end
		for _, packed in ipairs(added) do list[#list + 1] = packed end
		local heads = {}
		for _, packed in ipairs(list) do
			local t, seq = S.Head(packed)
			heads[packed] = { t or 0, seq or 0 }
		end
		table.sort(list, function(a, b)
			local x, y = heads[a], heads[b]
			if x[1] ~= y[1] then return x[1] < y[1] end
			return x[2] < y[2]
		end)
		dst.events = list
	end
	stats.rows = #added

	-- What names a row by seq: refs, pinned notes, keepsake notes.
	for ref, seq in pairs(src.refs) do
		if dst.refs[ref] == nil and rowMap[seq] then dst.refs[ref] = rowMap[seq] end
	end
	for index = notesBefore + 1, #dst.notes do
		local note = dst.notes[index]
		if type(note) == "table" and note.row ~= nil then note.row = rowMap[note.row] end
	end
	if type(src.keepNotes) == "table" then
		if type(dst.keepNotes) ~= "table" then dst.keepNotes = {} end
		for key, text in pairs(src.keepNotes) do
			local seq = type(key) == "string" and tonumber(key:match("^seq:(%d+)$"))
			local newKey = seq and (rowMap[seq] and ("seq:" .. rowMap[seq]) or nil) or key
			if newKey and dst.keepNotes[newKey] == nil then dst.keepNotes[newKey] = Copy(text) end
		end
	end

	-- Maps and numbers.
	for key, value in pairs(src) do
		if not OWN[key] then
			local current = dst[key]
			if current == nil then
				dst[key] = Copy(value)
			elseif type(current) == "table" and type(value) == "table" then
				MergeInto(current, value)
			elseif type(current) == "number" and type(value) == "number" then
				if EARLIEST[key] then dst[key] = math.min(current, value) else dst[key] = math.max(current, value) end
			end
		end
	end
	if type(src.imported) == "table" then
		if type(dst.imported) ~= "table" then dst.imported = Copy(src.imported) else MergeInto(dst.imported, src.imported) end
	end
	dst.nextId = math.max(tonumber(dst.nextId) or 1, MaxId(dst) + 1)
	S.Bump(dst)
	return stats
end

-- Put a journal in place of a character's, exactly as it was: a new table,
-- so every cache of the old one lets go. The GUID tag stays the
-- character's own.
function B.ReplaceRecord(charKey, journal)
	charKey = charKey or E.charKey
	local root = S.Root()
	if not (root and charKey and type(journal) == "table") then return nil end
	local old = root[charKey]
	local rec = Copy(journal)
	rec.trash = nil
	rec.guid = type(old) == "table" and old.guid or rec.guid
	if charKey == E.charKey then rec.guid = S.MyGUID() or rec.guid end
	rec.rev = (type(old) == "table" and tonumber(old.rev) or 0) + 1
	-- Saved under the character: through the saved data registry, which
	-- leaves a journal the player put back as it is.
	S.MigrateSaved(rec, charKey)
	root[charKey] = rec
	return rec
end

local function Changed(charKey)
	if J.ClearCache then J:ClearCache() end
	A:Fire("Restored", charKey or E.charKey)
	A:MarkDirty("all")
end
B.Changed = Changed

---------------------------------------------------------------------------
-- Taking, restoring, deleting
---------------------------------------------------------------------------
local function Keep()
	local keep = A.db and tonumber(A.db.backupKeep) or 3
	return math.max(1, math.floor(keep))
end

local function Counts(rec)
	return { rows = Count(rec.events), quests = Count(rec.quests), notes = Count(rec.notes), goals = Count(rec.goals) }
end

local function TopLevel(rec)
	local top
	for level in pairs(type(rec.levels) == "table" and rec.levels or {}) do
		if type(level) == "number" and (not top or level > top) then top = level end
	end
	return top
end

-- The oldest backups go past "Backups to keep", except the newest "before
-- update" copy, which has a slot of its own.
local function TrimList(list)
	local reserved = E:ReservedJournalBackup(list)
	local keep = Keep() + (reserved and 1 or 0)
	local index = #list
	while #list > keep and index >= 1 do
		if list[index] ~= reserved then table.remove(list, index) end
		index = index - 1
	end
end
B.TrimList = TrimList

function B:TakeRecord(rec, reason, charKey)
	charKey = charKey or E.charKey
	if not HasData(rec) then return nil end
	local data, err = B.Encode(rec, charKey)
	if not data then
		geterrorhandler()(("EldoUI My Adventure backup: %s"):format(tostring(err)))
		return nil
	end
	local list = Store(charKey, true)
	if not list then return nil end
	local who = Who(charKey)
	local entry = { at = Now(), level = who.level or TopLevel(rec), reason = reason or "hand", counts = Counts(rec),
		size = #data, data = data, eldoui = E.version, v = tonumber(rec.v) or 0, guid = Owner(rec) }
	table.insert(list, 1, entry)
	TrimList(list)
	A:Fire("BackedUp", charKey, entry)
	A:MarkDirty("backups")
	return entry
end

function B:Take(reason, charKey)
	charKey = charKey or E.charKey
	return self:TakeRecord(J:Char(charKey), reason, charKey)
end

---------------------------------------------------------------------------
-- Backups written in slices (a long journal): the scheduled backup and the
-- copy before an update. A job writes the code a little at a time and
-- pauses in combat, so neither stalls a frame at login.
--   * Scheduled: the record is copied in slices, then written; the backup
--     joins the list when its code is done.
--   * Before an update: the update steps run right after, so the record is
--     copied at once and the backup joins the list at once, marked
--     `pending`. The copy waits in journalCache.writing (saved with the
--     rest, so a logout before the code is done keeps it, and the next
--     start writes it) until the code is done.
---------------------------------------------------------------------------
local function Rows(rec)
	return Count(rec.events) + Count(rec.quests)
end

local function Writing()
	local cache = S.Cache()
	if type(cache.writing) ~= "table" then cache.writing = {} end
	return cache.writing
end

-- The copy a pending backup waits with.
local function WaitingCopy(entry, charKey)
	for _, item in ipairs(Writing()) do
		if type(item) == "table" and item.charKey == charKey and item.at == entry.at then return item end
	end
end

local function DropWaitingCopy(item)
	local list = Writing()
	for index = #list, 1, -1 do
		if list[index] == item then table.remove(list, index) end
	end
end

local function Finish(entry, data, charKey)
	entry.data, entry.size, entry.pending = data, #data, nil
	B.stats.sliced = B.stats.sliced + 1
	A:Fire("BackedUp", charKey, entry)
	A:MarkDirty("backups")
end

-- The job that writes a backup's code: of `journal` (a copy in hand) or of
-- the record, copied in slices first. place(entry) puts it in its list.
local queuedCopies = setmetatable({}, { __mode = "k" })   -- waiting copies a job of this session writes

local function WriteLater(key, entry, charKey, who, journal, rec, place)
	if journal then queuedCopies[journal] = true end
	return A:RunJob(key, function()
		local yield = B.Slicer(B.SLICE)
		journal = journal or CopyRecordSliced(rec, yield, SKIP_KEYS)
		local data = E:EncodeShareData("journal", { at = entry.at, charKey = charKey, who = who, journal = journal }, yield)
		if type(data) ~= "string" then error("the backup code could not be written") end
		if place then place(entry) end
		Finish(entry, data, charKey)
	end)
end

-- A scheduled backup of a long journal, written by a job. Returns the
-- entry it will add, or nil (nothing to back up, or one is being written).
function B:TakeSliced(rec, reason, charKey)
	charKey = charKey or E.charKey
	if not HasData(rec) then return nil end
	local who = Who(charKey)
	local entry = { at = Now(), level = who.level or TopLevel(rec), reason = reason or "scheduled", counts = Counts(rec),
		eldoui = E.version, v = tonumber(rec.v) or 0, guid = Owner(rec) }
	local queued = WriteLater(("backup:%s:%s"):format(entry.reason, tostring(charKey)), entry, charKey, who, nil, rec, function(done)
		local list = Store(charKey, true)
		if not list then return end
		table.insert(list, 1, done)
		TrimList(list)
	end)
	return queued and entry or nil
end

-- The copy before an update changes a saved record (Store.lua): at once
-- for a short journal; for a long one the record is copied now and its
-- code written by a job.
function B:TakeBeforeUpdate(rec, charKey)
	charKey = charKey or E.charKey
	if not HasData(rec) then return nil end
	if Rows(rec) <= B.SYNC_ROWS then return self:TakeRecord(rec, "before update", charKey) end
	local list = Store(charKey, true)
	if not list then return nil end
	local who = Who(charKey)
	local entry = { at = Now(), level = who.level or TopLevel(rec), reason = "before update", counts = Counts(rec),
		eldoui = E.version, v = tonumber(rec.v) or 0, pending = true, guid = Owner(rec) }
	local waiting = { charKey = charKey, at = entry.at, who = who, journal = Snapshot(rec) }
	local writing = Writing()
	writing[#writing + 1] = waiting
	table.insert(list, 1, entry)
	TrimList(list)
	if not WriteLater(("backup:update:%s"):format(tostring(charKey)), entry, charKey, who, waiting.journal, nil,
		function() DropWaitingCopy(waiting) end) then
		-- One is being written already: this one waits for the next start.
		A:MarkDirty("backups")
	end
	return entry
end

-- Write the backups a logout or a reload left pending.
function B:ResumePending()
	local count = 0
	for _, waiting in ipairs({ unpack(Writing()) }) do
		local entry
		for _, item in ipairs(type(waiting) == "table" and self:List(waiting.charKey) or {}) do
			if item.pending and item.at == waiting.at then entry = item end
		end
		if not entry then
			-- Its backup is gone (deleted by the player): the copy goes too.
			DropWaitingCopy(waiting)
		elseif not queuedCopies[waiting.journal] -- else a job of this session writes it already
			and WriteLater(("backup:resume:%s:%s"):format(tostring(waiting.charKey), tostring(waiting.at)), entry, waiting.charKey,
			waiting.who or Who(waiting.charKey), waiting.journal, nil, function() DropWaitingCopy(waiting) end) then
			count = count + 1
		end
	end
	return count
end

-- What a backup holds: its code read back, or the copy a pending one waits
-- with. -> { at, who, journal } or nil and why.
function B:EntryData(entry, charKey)
	if type(entry) ~= "table" then return nil, L["That backup is gone."] end
	if type(entry.data) == "string" then return self:Read(entry.data) end
	local waiting = entry.pending and WaitingCopy(entry, charKey or E.charKey)
	if waiting and type(waiting.journal) == "table" then return { at = entry.at, who = waiting.who, journal = waiting.journal } end
	return nil, L["This backup is still being written. Try again in a moment."]
end

function B:Due(charKey, now)
	local every = B.EVERY[A.db and A.db.backupEvery or "day"]
	if not every then return false end
	local last = self:List(charKey)[1]
	return (now or Now()) - (last and tonumber(last.at) or 0) >= every
end

-- The character a backup belongs to: its GUID, read from the backed-up
-- journal for a backup taken before backups carried it (and noted on it).
-- nil while a backup is being written or can't be read.
function B.EntryGUID(entry, charKey)
	if type(entry) ~= "table" then return nil end
	if entry.guid ~= nil or entry.pending then return Owner(entry) end
	local data = B:EntryData(entry, charKey)
	local guid = data and Owner(data.journal)
	entry.guid = guid
	return guid
end

-- Moves the backups under fromKey that belong to guid into toKey's list,
-- newest first. One still being written stays where it is. Returns how
-- many moved.
function B.Claim(fromKey, toKey, guid)
	local all = type(EldoUIDB) == "table" and EldoUIDB.journalBackups
	local from = type(all) == "table" and all[fromKey]
	if type(from) ~= "table" or not guid or fromKey == toKey then return 0 end
	local moved = {}
	for index = #from, 1, -1 do
		local entry = from[index]
		if type(entry) == "table" and not entry.pending and B.EntryGUID(entry, fromKey) == guid then
			moved[#moved + 1] = table.remove(from, index)
		end
	end
	if not moved[1] then return 0 end
	if from[1] == nil then all[fromKey] = nil end
	local to = all[toKey]
	if type(to) ~= "table" then
		to = {}
		all[toKey] = to
	end
	for _, entry in ipairs(moved) do to[#to + 1] = entry end
	table.sort(to, function(a, b) return (tonumber(a.at) or 0) > (tonumber(b.at) or 0) end)
	A:MarkDirty("backups")
	return #moved
end

-- The GUID of the journal a restore would go into, or nil.
local function TargetGUID(charKey)
	if charKey == E.charKey then return S.MyGUID() end
	local root = S.Root()
	return root and Owner(root[charKey])
end

-- mode: "merge" (keep both) or "replace". The journal as it is now is
-- backed up first. A backup of another character's journal is refused.
function B:Restore(index, mode, charKey)
	charKey = charKey or E.charKey
	local entry = self:List(charKey)[tonumber(index) or 0]
	if type(entry) ~= "table" then return false, L["That backup is gone."] end
	local data, err = self:EntryData(entry, charKey)
	if not data then return false, err end
	local theirs, mine = Owner(data.journal), TargetGUID(charKey)
	if theirs and entry.guid == nil and not entry.pending then entry.guid = theirs end
	-- A backup made before the character moved to another ruleset names its
	-- GUID from then; the journal inside takes the one it has now.
	if theirs and mine and theirs == entry.formerGuid and Owner(entry) == mine then
		data.journal.guid, theirs = mine, mine
	end
	if theirs and mine and theirs ~= mine then
		return false, L["This backup is of another character's journal, so it can't be restored into this one."]
	end
	self:Take("before restoring", charKey)
	return self:Apply(data.journal, mode, charKey)
end

-- Put a journal into a character's: merge or replace.
function B:Apply(journal, mode, charKey)
	charKey = charKey or E.charKey
	if not Valid(journal) then return false, L["The code is incomplete or damaged. Copy all of it and paste it again."] end
	if mode == "replace" then
		B.ReplaceRecord(charKey, journal)
		Changed(charKey)
		return true
	end
	local rec = J:Char(charKey)
	if not rec then return false, L["The journal is not ready yet. Try again in a moment."] end
	local stats = B.Merge(rec, journal)
	Changed(charKey)
	return true, stats
end

function B:Delete(index, charKey)
	local list = Store(charKey)
	if not (list and list[tonumber(index) or 0]) then return false end
	table.remove(list, tonumber(index))
	A:MarkDirty("backups")
	return true
end

---------------------------------------------------------------------------
-- Forgetting a character (the Alts window): its journal leaves only after
-- a backup of it is taken. That backup is kept apart from the dated ones
-- (EldoUIDB.journalCache.forgotten, like the journals of another
-- character), one per character: no number of backups and no size cap lets
-- it go. The Saved data page lists it with Restore and Remove; putting it
-- back or removing it is what lets it go.
--   * A long journal is copied at once and its code written by a job in
--     slices, so forgetting it never stalls a frame. Until the code is
--     done the entry holds the copy (`journal`), saved with the rest, and
--     the next login writes it.
--   * A journal with nothing in it keeps the newest of its dated backups
--     instead, so forgetting never drops the last copy of anything.
---------------------------------------------------------------------------
local function Forgotten()
	return S.Cache().forgotten
end

-- The entries of one character leave the list (all of them, or all but `keep`).
local function DropForgotten(charKey, keep)
	local list = Forgotten()
	local dropped = false
	for index = #list, 1, -1 do
		local entry = list[index]
		if type(entry) == "table" and entry.charKey == charKey and entry ~= keep then
			table.remove(list, index)
			dropped = true
		end
	end
	return dropped
end

local function WriteForgotten(entry)
	local charKey = entry.charKey
	local queued = A:RunJob(("backup:forgotten:%s:%s"):format(tostring(charKey), tostring(entry.at)), function()
		local yield = B.Slicer(B.SLICE)
		local data = E:EncodeShareData("journal", { at = entry.at, charKey = charKey, who = entry.who or Who(charKey),
			journal = entry.journal }, yield)
		if type(data) ~= "string" then error("the backup code could not be written") end
		entry.data, entry.size, entry.journal, entry.who = data, #data, nil, nil
		A:MarkDirty("backups")
	end)
	if queued then queuedCopies[entry.journal] = true end
	return queued
end

-- true when the journal may leave: its backup is kept, or there is nothing
-- in it or in its dated backups to keep. The dated backups then go too.
function B:KeepForgotten(rec, charKey)
	local who = Who(charKey)
	local entry
	if type(rec) == "table" and HasData(rec) then
		entry = { charKey = charKey, at = Now(), level = who.level or TopLevel(rec), reason = "before forgetting",
			counts = Counts(rec), eldoui = E.version, v = tonumber(rec.v) or 0, guid = Owner(rec) }
		if Rows(rec) > B.SYNC_ROWS then
			entry.journal, entry.who = Snapshot(rec), who
		else
			local data, err = B.Encode(rec, charKey)
			if not data then
				geterrorhandler()(("EldoUI My Adventure backup: %s"):format(tostring(err)))
				return false
			end
			entry.data, entry.size = data, #data
		end
	else
		for _, dated in ipairs(self:List(charKey)) do
			local held = type(dated) == "table" and type(dated.data) ~= "string" and self:EntryData(dated, charKey) or nil
			if type(dated) == "table" and (type(dated.data) == "string" or (held and type(held.journal) == "table")) then
				entry = { charKey = charKey, at = dated.at, level = dated.level, reason = "before forgetting", counts = dated.counts,
					size = dated.size, data = dated.data, eldoui = dated.eldoui, v = dated.v }
				if held then entry.journal, entry.who = held.journal, held.who or who end
				break
			end
		end
		if not entry then
			Store(charKey, "drop")
			return true
		end
	end
	local list = Forgotten()
	list[#list + 1] = entry
	DropForgotten(charKey, entry)
	Store(charKey, "drop")
	if entry.journal then WriteForgotten(entry) end
	A:MarkDirty("backups")
	return true
end

-- Write the codes a logout or a reload left unwritten.
function B:ResumeForgotten()
	local count = 0
	for _, entry in ipairs(Forgotten()) do
		if type(entry) == "table" and type(entry.journal) == "table" and type(entry.data) ~= "string"
			and not queuedCopies[entry.journal] then
			if WriteForgotten(entry) then count = count + 1 end
		end
	end
	return count
end

-- The backup of each forgotten character:
-- { kind = "journal", key, id, at, level, counts, forgotten = true }, newest first.
function B:ForgottenList()
	local newest = {}
	for _, entry in ipairs(Forgotten()) do
		if type(entry) == "table" and entry.charKey ~= nil then
			local have = newest[entry.charKey]
			if not have or (tonumber(entry.at) or 0) >= (tonumber(have.at) or 0) then newest[entry.charKey] = entry end
		end
	end
	local list = {}
	for charKey, entry in pairs(newest) do
		list[#list + 1] = { kind = "journal", key = charKey, id = "journal:" .. tostring(charKey), at = entry.at, level = entry.level,
			counts = entry.counts, eldoui = entry.eldoui, forgotten = true, entry = entry }
	end
	table.sort(list, function(a, b)
		if (a.at or 0) ~= (b.at or 0) then return (a.at or 0) > (b.at or 0) end
		return tostring(a.key) < tostring(b.key)
	end)
	return list
end

-- What a forgotten character's backup holds: its code read back, or the
-- copy it holds while the code is written.
local function ForgottenData(entry)
	if type(entry.data) == "string" then return B:Read(entry.data) end
	if type(entry.journal) == "table" then return { at = entry.at, who = entry.who, journal = entry.journal } end
	return nil, L["That backup is gone."]
end

-- Put a forgotten character's journal back: exactly as it was when the
-- character has no journal now, else merged into the one it has (backed
-- up first; nothing from either is lost). The journal is in place again,
-- so its backup leaves the list.
function B:RestoreForgotten(charKey)
	local item
	for _, entry in ipairs(self:ForgottenList()) do
		if entry.key == charKey then item = entry.entry end
	end
	if not item then return false, L["That backup is gone."] end
	local data, err = ForgottenData(item)
	if not data then return false, err end
	local mode = HasData(J:Char(charKey)) and "merge" or "replace"
	if mode == "merge" then self:Take("before restoring", charKey) end
	local ok, why = self:Apply(data.journal, mode, charKey)
	if ok then
		DropForgotten(charKey)
		A:MarkDirty("backups")
	end
	return ok, why
end

-- The player removes a forgotten character's journal for good (the Saved
-- data page asks first).
function B:RemoveForgotten(charKey)
	if not DropForgotten(charKey) then return false, L["That backup is gone."] end
	A:MarkDirty("backups")
	return true
end

---------------------------------------------------------------------------
-- Journals of another character (journalCache.orphans, Store.lua): a
-- journal under this character's name that carries another character's
-- GUID. Each one is kept packed, as a "!EUJ1!" code like a dated backup:
-- { key, guid, at, rows, counts, size, data }. A long journal is packed by
-- a job in slices; until its code is done the entry holds the journal
-- (`journal`), saved with the rest, and the next login packs it. The
-- newest ORPHANS_KEEP stay; its own character takes one back by GUID
-- (Store.lua), and the Saved data page gives one to this character or
-- removes it.
---------------------------------------------------------------------------
B.ORPHANS_KEEP = 10

local orphanJobs = setmetatable({}, { __mode = "k" })   -- entry -> the job packing it

local function Orphans()
	return S.Cache().orphans
end

-- The moments of a set-aside journal, packed or not.
function B.OrphanRows(entry)
	if type(entry) ~= "table" then return 0 end
	if tonumber(entry.rows) then return tonumber(entry.rows) end
	return type(entry.journal) == "table" and Count(entry.journal.events) or 0
end

local function OrphanPacked(entry, data)
	entry.data, entry.size, entry.journal = data, #data, nil
	orphanJobs[entry] = nil
	A:MarkDirty("backups")
end

-- Pack one set-aside journal: at once when it is short, by a job when it
-- is long. true when it is packed or being packed.
function B:PackOrphan(entry)
	if type(entry) ~= "table" then return false end
	if type(entry.data) == "string" then return true end
	local journal = entry.journal
	if type(journal) ~= "table" then return false end
	if orphanJobs[entry] and A:JobRunning(orphanJobs[entry]) then return true end
	entry.guid = entry.guid or Owner(journal)
	entry.rows, entry.counts = Count(journal.events), Counts(journal)
	local payload = { at = entry.at, charKey = entry.key, journal = journal }
	if Rows(journal) <= B.SYNC_ROWS then
		payload.journal = Snapshot(journal)
		local data = E:EncodeShareData("journal", payload)
		if type(data) ~= "string" then return false end
		OrphanPacked(entry, data)
		return true
	end
	local key = ("backup:orphan:%s:%s"):format(tostring(entry.key), tostring(entry.at))
	local queued = A:RunJob(key, function()
		local yield = B.Slicer(B.SLICE)
		payload.journal = CopyRecordSliced(journal, yield, SKIP_KEYS)
		local data = E:EncodeShareData("journal", payload, yield)
		if type(data) ~= "string" then error("the journal could not be packed") end
		OrphanPacked(entry, data)
	end)
	if queued then orphanJobs[entry] = key end
	return queued
end

-- The newest ORPHANS_KEEP stay; older ones leave, the oldest first.
function B:TrimOrphans()
	local list = Orphans()
	local removed = 0
	while #list > B.ORPHANS_KEEP do
		local oldest, at
		for index, entry in ipairs(list) do
			local when = type(entry) == "table" and tonumber(entry.at) or 0
			if not oldest or when < at then oldest, at = index, when end
		end
		local entry = table.remove(list, oldest)
		if orphanJobs[entry] then A:CancelJob(orphanJobs[entry]) end
		removed = removed + 1
	end
	if removed > 0 then A:MarkDirty("backups") end
	return removed
end

-- A journal set aside now (Store.lua): packed, and the list trimmed.
function B:KeepOrphan(entry)
	local list = Orphans()
	list[#list + 1] = entry
	local ok, err = pcall(self.PackOrphan, self, entry)
	if not ok then geterrorhandler()(("EldoUI My Adventure: a set-aside journal stays unpacked: %s"):format(tostring(err))) end
	self:TrimOrphans()
	A:MarkDirty("backups")
	return entry
end

-- At login: pack what an older version or a logout left unpacked.
function B:ResumeOrphans()
	local count = 0
	for _, entry in ipairs(Orphans()) do
		if type(entry) == "table" and type(entry.data) ~= "string" and type(entry.journal) == "table" then
			local ok, queued = pcall(self.PackOrphan, self, entry)
			if ok and queued then count = count + 1 end
		end
	end
	self:TrimOrphans()
	return count
end

-- The journal a set-aside entry holds (read from its code), or nil and why.
-- A journal still waiting to be packed comes out as it is, and its job
-- stops: the caller takes it.
function B.OrphanJournal(entry)
	if type(entry) ~= "table" then return nil, L["That journal is gone."] end
	if type(entry.journal) == "table" then
		if orphanJobs[entry] then
			A:CancelJob(orphanJobs[entry])
			orphanJobs[entry] = nil
		end
		return entry.journal
	end
	if type(entry.data) ~= "string" then return nil, L["That journal is gone."] end
	local data, err = B:Read(entry.data)
	if not data then return nil, err end
	return data.journal
end

local function DropOrphan(entry)
	local list = Orphans()
	for index = #list, 1, -1 do
		if list[index] == entry then
			table.remove(list, index)
			if orphanJobs[entry] then A:CancelJob(orphanJobs[entry]) end
			orphanJobs[entry] = nil
			A:MarkDirty("backups")
			return true
		end
	end
	return false
end

-- The player removes a set-aside journal for good (the Saved data page
-- asks first).
function B:RemoveOrphan(entry)
	if not DropOrphan(entry) then return false, L["That journal is gone."] end
	return true
end

-- A set-aside copy of this character's own journal goes into the journal
-- it has now: merged, after a backup, so nothing from either is lost.
function B:GiveOrphan(entry)
	local mine = S.MyGUID and S.MyGUID()
	if not (type(entry) == "table" and mine and (entry.guid or Owner(entry.journal)) == mine) then
		return false, L["This journal belongs to another character."]
	end
	local journal, err = B.OrphanJournal(entry)
	if not journal then return false, err end
	if not J:Char() then return false, L["The journal is not ready yet. Try again in a moment."] end
	self:Take("before restoring")
	local ok, stats = self:Apply(journal, "merge")
	if not ok then return false, stats end
	if S.MergePlaces then S.MergePlaces(J:Char(), journal) end
	DropOrphan(entry)
	return true, stats
end

-- A pasted code into this character's journal (a backup is taken first).
function B:ImportText(text, mode)
	local data, err = self:Read(text)
	if not data then return false, err end
	if not J:Char() then return false, L["The journal is not ready yet. Try again in a moment."] end
	self:Take("before importing")
	return self:Apply(data.journal, data.mergeOnly and "merge" or mode)
end

---------------------------------------------------------------------------
-- Words for the pages and dialogs
---------------------------------------------------------------------------
local REASONS = E:TranslateValues({
	scheduled = E.Key("scheduled"), hand = E.Key("by hand"), ["before restoring"] = E.Key("before restoring"),
	["before importing"] = E.Key("before importing"), ["before clearing"] = E.Key("before clearing"),
	["before update"] = E.Key("before an EldoUI update"),
})

function B.ReasonText(reason)
	return REASONS[reason] or tostring(reason or "")
end

function B.When(t)
	return tonumber(t) and E:ShortDate(t) or "?"
end

-- "Oct 12, 18:40 · level 23 · 1,204 moments, 88 quests, 4 notes (scheduled)"
function B.Describe(entry)
	if type(entry) ~= "table" then return "" end
	local counts = type(entry.counts) == "table" and entry.counts or {}
	local rows, quests, notes = tonumber(counts.rows) or 0, tonumber(counts.quests) or 0, tonumber(counts.notes) or 0
	local parts = {
		E:Plural(rows, "%s moment", "%s moments"):format(BreakUpLargeNumbers(rows)),
		E:Plural(quests, "%s quest", "%s quests"):format(BreakUpLargeNumbers(quests)),
		E:Plural(notes, "%s note", "%s notes"):format(BreakUpLargeNumbers(notes)),
	}
	local level = tonumber(entry.level) and (" · " .. (L["level %d"]):format(entry.level)) or ""
	return ("%s%s · %s (%s)"):format(B.When(entry.at), level, table.concat(parts, ", "), B.ReasonText(entry.reason))
end

function B:LastText(charKey)
	local last = self:List(charKey)[1]
	if not last then return L["No backup yet."] end
	return (L["Last backup: %s."]):format(B.Describe(last))
end

local function Run(data, how)
	if type(data) ~= "table" then return end
	local ok, err = data.run(how)
	E:Print(ok and data.done[how] or (L["Nothing changed: %s"]):format(tostring(err)))
end

local function Ask(text, data, mergeOnly)
	return E:ShowConfirm({ key = "ELDOUI_JOURNAL_RESTORE", title = L["My Adventure"], text = text, accept = L["Merge"],
		data = data, extra = not mergeOnly and { L["Replace"], function(own) Run(own, "replace") end } or nil,
		onAccept = function(own) Run(own, "merge") end })
end

function B:AskRestore(index)
	local entry = self:List()[tonumber(index) or 0]
	if not entry then return nil end
	local text = (L["Restore the backup from %s?"]):format(B.When(entry.at)) .. "\n\n"
		.. L["Merge adds everything in the backup that your journal is missing, and keeps everything since. Replace puts the journal back exactly as it was then."]
		.. "\n\n" .. L["Your journal as it is now is backed up first either way."]
	return Ask(text, {
		run = function(mode) return B:Restore(index, mode) end,
		done = { merge = L["The backup is merged into your journal."], replace = L["Your journal is back as it was then."] },
	})
end

-- Backups are the way back after a bad import, so deleting one asks first.
function B:AskDelete(index)
	local entry = self:List()[tonumber(index) or 0]
	if not entry then return nil end
	return E:ShowConfirm({ key = "ELDOUI_JOURNAL_BACKUP_DELETE", title = L["Delete this backup?"],
		text = B.Describe(entry), accept = L["Delete"], danger = true,
		onAccept = function()
			-- A backup taken while the question was open moves the list down.
			for i, other in ipairs(B:List()) do
				if other == entry then return B:Delete(i) end
			end
		end })
end

-- The code a player pasted: what it holds, then Merge / Replace / Cancel.
function B:AskImportText(text)
	local data, err = self:Read(text)
	if not data then
		E:Print(err)
		return nil, err
	end
	local who = type(data.who) == "table" and data.who or {}
	local journal = data.journal
	local rows = Count(journal.events)
	local from = data.fj and L["Forever Journal"] or "EldoUI"
	local text1 = (L["Load the journal of %s (level %s, saved %s by %s) into this character?"]):format(tostring(who.name or "?"),
		tostring(who.level or "?"), B.When(data.at), from)
		.. "\n" .. E:Plural(rows, "%s moment", "%s moments"):format(BreakUpLargeNumbers(rows))
		.. ", " .. E:Plural(Count(journal.quests), "%s quest", "%s quests"):format(BreakUpLargeNumbers(Count(journal.quests)))
		.. ", " .. E:Plural(Count(journal.notes), "%s note", "%s notes"):format(BreakUpLargeNumbers(Count(journal.notes)))
		.. ", " .. E:Plural(Count(journal.goals), "%s goal", "%s goals"):format(BreakUpLargeNumbers(Count(journal.goals)))
	if data.mergeOnly then
		text1 = text1 .. "\n\n" .. L["This code contains only recent changes. Merge adds them to your journal and keeps your existing entries."]
			.. "\n\n" .. L["Your journal as it is now is backed up first."]
	else
		text1 = text1 .. "\n\n" .. L["Merge combines it with your journal: nothing from either is lost. Replace uses only the pasted one."]
			.. "\n\n" .. L["Your journal as it is now is backed up first either way."]
	end
	return Ask(text1, {
		run = function(mode)
			if not J:Char() then return false, L["The journal is not ready yet. Try again in a moment."] end
			B:Take("before importing")
			return B:Apply(journal, data.mergeOnly and "merge" or mode)
		end,
		done = { merge = L["Merged into your journal."], replace = L["Imported. Your journal is now the pasted one."] },
	}, data.mergeOnly)
end

function B:AskImportCode()
	E:ShowPasteBox(L["Paste a journal code"],
		L["Paste a journal backup code starting with !EUJ1!, FJ2: or FJ1:. You see what it holds before anything changes."],
		function(text) B:AskImportText(text) end)
end

-- The backups as a menu: each one with Restore and Delete.
function B:ShowRestoreMenu(owner)
	local list = self:List()
	if not list[1] then
		E:Print(L["No backup yet."])
		return false
	end
	E.UIKit.ContextMenu(owner or UIParent, function(_, root)
		root:CreateTitle(L["Backups of this journal"])
		for index, entry in ipairs(list) do
			local sub = root:CreateButton(B.Describe(entry))
			sub:CreateButton(L["Restore..."], function() B:AskRestore(index) end)
			sub:CreateButton(L["Copy its code"], function()
				if type(entry.data) ~= "string" then
					E:Print(L["This backup is still being written. Try again in a moment."])
					return
				end
				E:ShowCopyBox(L["Journal backup code"], L["Press Ctrl+C to copy. Paste it back in with Paste a journal code, on this PC or another. Nothing is sent anywhere."],
					entry.data)
			end)
			sub:CreateButton(L["Delete"], function() B:AskDelete(index) end)
		end
	end)
	return true
end

function B:BackUpNow()
	local entry = self:Take("hand")
	if entry then
		E:Print((L["Backed up: %s. It is on disk after your next logout or /reload."]):format(B.Describe(entry)))
	else
		E:Print(L["There is no journal to back up yet."])
	end
	return entry
end

---------------------------------------------------------------------------
-- The share kind: /eui import takes a journal code too (it merges, after
-- showing what the code holds). No `build`: nothing can send a journal.
---------------------------------------------------------------------------
E:RegisterShareKind("journal", {
	prefix = B.PREFIX,
	title = "Journal backup",
	version = 1,
	describe = function(data)
		local journal = type(data.journal) == "table" and data.journal or {}
		local who = type(data.who) == "table" and data.who or {}
		local rows = Count(journal.events)
		return {
			(L["The journal of %s, saved %s."]):format(tostring(who.name or "?"), B.When(data.at)),
			E:Plural(rows, "%s moment", "%s moments"):format(BreakUpLargeNumbers(rows)),
			L["Accept merges it into this character's journal: nothing is lost, and a backup is taken first."],
		}
	end,
	apply = function(data)
		if not (type(data) == "table" and Valid(data.journal)) then
			E:Print(L["The code is incomplete or damaged. Copy all of it and paste it again."])
			return
		end
		if not J:Char() then
			E:Print(L["The journal is not ready yet. Try again in a moment."])
			return
		end
		B:Take("before importing")
		local ok, err = B:Apply(data.journal, "merge")
		E:Print(ok and L["Merged into your journal."] or tostring(err))
	end,
})

---------------------------------------------------------------------------
-- "Clear this character's journal" takes a backup first.
---------------------------------------------------------------------------
local clear = J.Clear
function J:Clear(charKey)
	charKey = charKey or E.charKey
	if HasData(self:Char(charKey)) then B:Take("before clearing", charKey) end
	return clear(self, charKey)
end

---------------------------------------------------------------------------
-- Options (Options.lua places them on the "Keeping it safe" tab)
---------------------------------------------------------------------------
local function NoBackups() return B:List()[1] == nil end
local function X() return A.Export end

A.BackupOptions = {
	{ type = "header", label = "Backups" },
	{ type = "description", label = "Backups are copies of this journal in your saved data. The game writes them to disk when you log out or /reload." },
	{ type = "select", key = "backupEvery", label = "Back up", desc = "When a backup is taken by itself, 8 seconds after you log in and out of combat.",
		values = { login = "Every login", day = "Once a day", week = "Once a week", manual = "Only by hand" } },
	{ type = "range", key = "backupKeep", label = "Backups to keep", desc = "The oldest goes when a new one would pass this. The newest copy from before an EldoUI update has a slot of its own and is always kept.", min = 1, max = 10, step = 1 },
	{ type = "execute", label = "Back up now", desc = "Takes a backup of this journal now.", func = function() B:BackUpNow() end },
	{ type = "execute", label = "Restore a backup", desc = "Pick a backup, then Merge (keeps everything since) or Replace (exactly as it was). Your journal is backed up first.",
		disabled = NoBackups, func = function() B:ShowRestoreMenu() end },
	{ type = "execute", label = "Copy a backup code", desc = "The whole journal as one code, to keep or to paste in on another PC. Nothing is sent anywhere.",
		func = function() if X() then X():Show("code") end end },
	{ type = "execute", label = "Paste a journal code", desc = "Previews a code starting with !EUJ1!, FJ2: or FJ1:. A full backup can be merged or used to replace your journal. Recent changes are merged.",
		func = function() B:AskImportCode() end },
	{ type = "header", label = "Export" },
	{ type = "execute", label = "Export as Markdown", desc = "The journal as a readable document, by chapter, with goals, notes and quests. Companion names are left out.",
		func = function() if X() then X():Show("markdown") end end },
	{ type = "execute", label = "Export a printable page", desc = "The journal as a web page (HTML). Save it as a .html file, open it in a browser and print it to PDF. Opened outside the game it loads its fonts from Google Fonts.",
		func = function() if X() then X():Show("html") end end },
	{ type = "execute", label = "Export as plain text", desc = "The journal as plain text, by chapter.",
		func = function() if X() then X():Show("text") end end },
}

---------------------------------------------------------------------------
-- Part: the scheduled backup, 8 s after login, out of combat
---------------------------------------------------------------------------
local timer
local waiter = CreateFrame("Frame")
waiter:SetScript("OnEvent", function(self)
	self:UnregisterAllEvents()
	B:Scheduled()
end)

function B:Scheduled()
	if not A.started then return nil end
	if InCombatLockdown() then
		waiter:RegisterEvent("PLAYER_REGEN_ENABLED")
		return nil
	end
	local rec = J:Char()
	if not HasData(rec) or not self:Due() then return nil end
	if Rows(rec) > B.SYNC_ROWS then return self:TakeSliced(rec, "scheduled") end
	return self:Take("scheduled")
end

---------------------------------------------------------------------------
-- Backups follow their owner. Characters that shared a first name kept
-- their backups under one key; when a character's data moves to its own
-- key, only its own backups come along, and the rest stay under the old
-- key until their owner logs in and takes them. A renamed character takes
-- its backups with its journal (Store.lua).
---------------------------------------------------------------------------
function B.SortOnKeyMove(db, oldKey, newKey)
	local all = db.journalBackups
	local mine = S.MyGUID()
	if type(all) ~= "table" or not mine then return end
	local here = all[newKey]
	if type(here) == "table" then
		local away = {}
		for index = #here, 1, -1 do
			local entry = here[index]
			local guid = type(entry) == "table" and not entry.pending and B.EntryGUID(entry, newKey)
			if guid and guid ~= mine then table.insert(away, 1, table.remove(here, index)) end
		end
		if away[1] then
			local there = all[oldKey]
			if type(there) ~= "table" then
				there = {}
				all[oldKey] = there
			end
			for _, entry in ipairs(away) do there[#there + 1] = entry end
			if here[1] == nil then all[newKey] = nil end
		end
	end
	B.Claim(oldKey, newKey, mine)
end
E:RegisterCharacterKeyMove(B.SortOnKeyMove)

-- A character brought over from another ruleset with a new GUID: its
-- backups, moved to its new key, take the new GUID (so they stay with it)
-- and keep the old one for a restore.
function B.TakeNewGuid(db, oldKey, newKey, oldGuid, newGuid)
	local all = db.journalBackups
	local list = type(all) == "table" and all[newKey]
	if type(list) ~= "table" then return end
	for _, entry in ipairs(list) do
		if type(entry) == "table" and not entry.pending and B.EntryGUID(entry, newKey) == oldGuid then
			entry.guid, entry.formerGuid = newGuid, oldGuid
		end
	end
end
if E.RegisterRulesetGuidMove then E:RegisterRulesetGuidMove(B.TakeNewGuid) end

-- At login: this character's backups left under an older key of its name.
function B.ClaimOlder()
	local mine = S.MyGUID()
	if not (mine and E.charKey and E.OlderCharacterKeys) then return 0 end
	local moved = 0
	for _, oldKey in ipairs(E:OlderCharacterKeys()) do moved = moved + B.Claim(oldKey, E.charKey, mine) end
	return moved
end

A:AddPart("backup", {
	order = 90,
	-- Options.lua loads after this file: the rows go in once every file is in.
	init = function()
		if A.AddOptionRows then A:AddOptionRows("safe", A.BackupOptions) end
	end,
	start = function()
		local ok, err = pcall(B.ClaimOlder)
		if not ok then geterrorhandler()(err) end
		B:ResumePending()
		B:ResumeForgotten()
		B:ResumeOrphans()
		if timer then timer:Cancel() end
		timer = C_Timer.NewTimer(B.LOGIN_DELAY, function()
			timer = nil
			B:Scheduled()
		end)
	end,
	stop = function()
		if timer then
			timer:Cancel()
			timer = nil
		end
		waiter:UnregisterAllEvents()
	end,
})
