-- EldoUI My Adventure: every dungeon and raid run, with who was in it.
--
-- The Instances log keeps its runs for the hourly instance limit and lets
-- old ones go past "Runs kept". The journal keeps its own copy of every
-- run, with the group members the game showed during it, and never lets
-- one go by itself:
--
--   EldoUIDB.journalRuns[charKey] = {
--     v = 3, seq, rev, lastSrc, pk,
--     strings = { "The Deadmines", "Ann Bell", ... },  names kept once
--     list = {                        in the order they came in; ids grow
--       { id, src, t, leave, inst, imp,
--         p = "kind:instID:diff:lvl:lvlOut:bosses:xp:kills:money:wing:enc",
--         m = "n:c:l:role:g:first:last:r;n:c:l:...",  one per member
--         loot = { { k, t, i, w, wm, pass, r = { "n:state:roll:class:flags",
--                  ... } }, ... }, lootMore },
--     },
--     idx = { rev, inst = { [inst] = { index, ... } }, with = { [key] =
--             { index, ... } }, won = { [key] = { index, ... } } (one
--             place per drop won),
--             src = { [src] = index },
--             agg = { [inst] = { n, inside, fast, d = { seconds, ... },
--             ppl } } },             rebuilt whenever it is out of date
--     lootWatch = { [k] = { src, at, st, link, done } },  drops the game is still
--                                    rolling, and which run they belong to
--     lootPend = { [src] = { loot, lootMore } },  results of a run that is
--                                    still open
--   }
--
-- src is the Instances run the record was copied from, imp the import a
-- run came in with. n, r, inst, wing and g are numbers in `strings`. A
-- member's n is the companions' key (rec.fellows): the name as the game
-- showed it, "First Surname" on Forever, "Name-Realm" for a name given
-- with another realm. r is the realm only when the game showed another
-- one; c the class, l the level at last sight, role the role the game
-- assigned (never guessed from the class), g the guild, first and last
-- when the member was seen. Each companion counts its runs
-- (fellows[key].runs) and knows its newest one (fellows[key].lastRun).
--
-- Packed runs (version 3): a run keeps its members in one text (m) and
-- what else it knows in another (p), so a run is one small table instead
-- of a table per member. Numbers are written as digits, the class as the
-- game's token, the role as one letter (T, H, D, N; any other text after
-- "~"), kind "r" for a raid (empty: a dungeon), enc the encounter ids
-- joined by ","; empty fields at the end are left out, and "%", ":", ";",
-- "," and "~" in a text are written as %XX so a text never splits a field.
-- Nothing reads the texts itself: R.Members, R.MemberKeys and R.Facts do.
-- A run saved before version 3 (members as tables in `with`, the rest as
-- fields) reads the same through them; the update packs those runs in
-- slices (pk: some may still be unpacked), and a run holding a value the
-- texts could not keep exactly stays as it was.
--
-- What the game shows only: the group roster and unit information, read
-- when the Instances recorder takes its roster snapshots, never the
-- combat log. Battlegrounds and arenas are not kept here: their group is a
-- raid of strangers. Raids keep every member.
--
-- Nothing here goes by itself: no cap, no trim, no eviction. Deleting one
-- run or one name is the player's own choice: it asks first, works out of
-- combat, goes to the journal's trash for 7 days and Undo puts it back
-- exactly, and nothing else changes. The first time a character's runs are
-- read, the runs the Instances log still has (and the companions the
-- journal noted for them) are copied in once; the companions of runs the
-- log no longer has stay where they were.
--
-- Loot rolls (version 2): when a roll in the group ends while a run is
-- open, the run keeps what the game's loot history shows for it: the item
-- (i, a link in `strings`), the winner (w, a companion key; wm when it was
-- you) or that everyone passed (pass), each roll as the game listed it
-- (name, roll type, the number when there is one, class; m for you, w
-- for the winner) and when it ended (t). k is the game's own key of that
-- drop (encounter and drop), so the same drop is kept once and two drops
-- of the same item stay two. Only a finished roll is kept: a leader or a
-- tie while players still roll is not a result. A value the game hides is
-- left out, never guessed. The rolls are read, never made: rolling stays
-- yours. Battlegrounds and arenas record nothing. A run keeps at most
-- R.LOOT_CAP drops; past that it counts the drops it did not keep
-- (lootMore). Runs saved before version 2 simply have no loot.
--
-- Backups: "!EUJR1!" codes, in their own copy box and in
-- EldoUIDB.journalRunsBackups[charKey] (the newest few), taken before a
-- restore, an import or clearing the journal. Restore by Replace puts the
-- runs back exactly as they were; Merge adds the runs the journal lacks and
-- never adds one twice.
--
-- API (E.Adventure.Runs, also E.Journal.Runs):
--   R:Store([charKey])                the store (nil before saved data loads)
--   R:Runs([charKey])                 the list, oldest first (read only)
--   R:Find(id[, charKey])             a run and its place in the list
--   R:BySource(src[, charKey])        the run copied from an Instances run
--   R:RunsWith(key[, charKey])        places of a companion's runs, oldest first
--   R:RunsOf(name[, charKey])         places of one instance's runs
--   R.Members(unit, run)              the members, readable: { key, realm,
--                                     class, level, role, guild, first, last }
--   R.MemberKeys(unit, run)           the members' companion keys
--   R.Facts(unit, run)                the rest, readable: { kind, instanceID,
--                                     difficulty, level, levelOut, bosses,
--                                     xp, kills, money, wing, encounters }
--   R:Append(run, members[, charKey]) a run in hand: { t, leave, instance,
--                                     instanceID, wing, kind, level, levelOut,
--                                     bosses, xp, kills, money, src } and
--                                     members { key | name (+ realm), class,
--                                     level, role, guild, first, last }
--   R:Index([charKey])                the index, rebuilt first when needed
--   R:Updating([charKey])             the index is being rebuilt in slices
--   R:Packing([charKey])              the update is packing runs in slices
--   R:Newest(places, count)           the newest `count` places of a list
--                                     of places (an index entry), newest first
--   R:Get(index[, charKey])           the run at a place (counted in R.stats)
--   R:PlacesOf(name[, charKey]), R:Totals(name[, charKey])
--                                     an instance's places and its tally
--                                     { n, inside, fast, median, ppl }
--   R:WonBy(key[, charKey])           places of the runs a companion won
--                                     loot in, once per drop (#: drops won)
--   R:Loot(run[, charKey])            the run's drops, readable: { item, t,
--                                     key, me, pass, rolls = { { key, me,
--                                     state, roll, class, won } } }
--   R:Delete(id), R:DeletePerson(key)  -> trash id (J:Undo puts it back)
--   R:AskDelete(id), R:AskDeletePerson(key)
--   R:Code([charKey]), R:Read(text), R:Restore(data, mode[, charKey])
--   R:TakeBackup(reason[, charKey]), R:Backups([charKey])
local _, E = ...
local L = E.L
local Key = E.Key
local A = E.Adventure
local J = E.Journal
local S = A.Store

local R = {}
A.Runs = R
J.Runs = R

R.SCHEMA = 3
R.PREFIX = "!EUJR1!"
R.TAIL = 64             -- how far back a closing run looks for its own record
R.SYNC_REBUILD = 2000   -- up to this many runs the index is rebuilt at once
R.REBUILD_SLICE = 250   -- runs per slice of a rebuild in slices
R.SYNC_PACK = 500       -- up to this many runs the update packs them at once
R.PACK_SLICE = 100      -- runs per slice of packing in slices
R.PAGE = 100            -- runs per page of a list
R.BACKUP_KEEP = 2
R.LOOT_CAP = 40         -- drops kept per run
R.LOOT_ROLLS = 40       -- rolls kept per drop (a full raid)
R.LOOT_LATE = 900       -- a roll may end this long after its run closed
R.LOOT_OLD = 900        -- a drop first seen this long after it dropped is older history
R.WATCH_SECONDS = 3600  -- how long a drop's run is remembered
R.WATCH_CAP = 200
-- Work counters (the large-data checks read them): runs added, updated,
-- rebuilt and copied in, slices of rebuilds, runs read by pages, loot
-- results kept, enriched, past the cap or not this run's, and drops read;
-- runs packed by the update, kept as they were, and slices of packing.
R.stats = { appended = 0, updated = 0, rebuilt = 0, folded = 0, slices = 0, touched = 0, lootSaved = 0,
	lootEnriched = 0, lootOver = 0, lootSkipped = 0, lootReads = 0, packed = 0, packKept = 0, packSlices = 0 }

local floor, tremove, tinsert = math.floor, table.remove, table.insert
local StartPack
local ResumeBackup   -- the backup before an update a reload left unwritten

local function Now()
	return time()
end

local function Text(value)
	if E:IsSecret(value) or type(value) ~= "string" or value == "" then return nil end
	return value
end

local function Number(value)
	if E:IsSecret(value) or type(value) ~= "number" then return nil end
	return value
end

---------------------------------------------------------------------------
-- The saved store
---------------------------------------------------------------------------
local function Root(create)
	if type(EldoUIDB) ~= "table" then return nil end
	local root = EldoUIDB.journalRuns
	if type(root) ~= "table" then
		if not create then return nil end
		root = E:KeepInNewTable(root, "journalRuns")
		EldoUIDB.journalRuns = root
	end
	return root
end
R.Root = Root

local function Fill(unit)
	if type(unit.strings) ~= "table" then unit.strings = {} end
	if type(unit.list) ~= "table" then unit.list = {} end
	if type(unit.idx) ~= "table" then unit.idx = { rev = -1 } end
	unit.seq = tonumber(unit.seq) or 0
	unit.rev = tonumber(unit.rev) or 0
	unit.lastSrc = tonumber(unit.lastSrc) or 0
	return unit
end
R.Fill = Fill

-- The load check: the list closes up a gap, a run that is not a table is
-- set aside, a member that is not a table too, and a run's packed members
-- or facts that are not a text; numbers saved as text are read back. The
-- index is derived and simply rebuilt.
local function Check(unit, C)
	-- The saved index stays valid unless this check repairs or sets aside
	-- something; then it is rebuilt when next read.
	local report = type(C.report) == "table" and C.report or nil
	local function Fixes()
		return report and ((tonumber(report.repaired) or 0) + (tonumber(report.quarantined) or 0)) or -1
	end
	local fixes = Fixes()
	C.Table(unit, "strings")
	local list = C.List(unit, "list")
	for index = #list, 1, -1 do
		local run = list[index]
		if type(run) ~= "table" then
			C.Keep("list." .. index, run, "Expected a table.")
			tremove(list, index)
		else
			for _, part in ipairs({ "m", "p" }) do
				if run[part] ~= nil and type(run[part]) ~= "string" then
					C.Keep(("list.%d.%s"):format(index, part), run[part], "Expected a text.")
					run[part] = nil
				end
			end
			for _, part in ipairs({ "with", "loot" }) do
				if run[part] ~= nil then
					local entries = C.List(run, part, ("list.%d.%s"):format(index, part))
					for position = #entries, 1, -1 do
						if type(entries[position]) ~= "table" then
							C.Keep(("list.%d.%s.%d"):format(index, part, position), entries[position], "Expected a table.")
							tremove(entries, position)
						end
					end
				end
			end
		end
	end
	for _, key in ipairs({ "lootWatch", "lootPend" }) do
		if unit[key] ~= nil then C.Table(unit, key) end
	end
	for _, key in ipairs({ "seq", "rev", "lastSrc", "pk" }) do C.Number(unit, key) end
	if unit.idx ~= nil and type(unit.idx) ~= "table" then
		C.Keep("idx", unit.idx, "Expected a table.")
		unit.idx = nil
	end
	if type(unit.idx) == "table" and (fixes < 0 or Fixes() ~= fixes) then unit.idx.rev = -1 end
end

-- The character whose store the update step works on (the step gets the
-- store only).
local folding

E:RegisterStore("journalRuns", {
	owner = "Adventure", key = "charKey", perKey = true, version = R.SCHEMA, versionKey = "v",
	title = "Journal runs of %s", shape = "runs with their group members and loot rolls, oldest first", validate = Check,
	-- The copy before an update is a runs code in the runs' own backups.
	backup = function(unit, charKey)
		return R.TakeBackupOf and R.TakeBackupOf(unit, "before update", charKey) or nil
	end,
})
E:RegisterStore("journalRunsBackups", { owner = "Adventure", key = "charKey", title = "Journal run backups of %s" })
-- Shown translated: L["Journal runs of %s"], L["Journal run backups of %s"]

local migrated = setmetatable({}, { __mode = "k" })

-- A character's store: made and brought up to date the first time a
-- session reads it. create: make it for a character that has none yet
-- (always for you).
function R:Store(charKey, create)
	charKey = charKey or E.charKey
	if not charKey then return nil end
	local mine = charKey == E.charKey
	local root = Root(create or mine)
	if not root then return nil end
	local unit = root[charKey]
	if type(unit) ~= "table" then
		if not (create or mine) then return nil end
		unit = E:KeepInNewTable(unit, "value")
		root[charKey] = unit
	end
	if not migrated[unit] then
		migrated[unit] = true
		Fill(unit)
		folding = charKey
		E:MigrateStore("journalRuns", unit, charKey)
		folding = nil
		Fill(unit)
		if unit.pk then StartPack(unit, charKey) end
	end
	return unit
end

function R:Runs(charKey)
	local unit = self:Store(charKey)
	return unit and unit.list or {}
end

local function Bump(unit)
	unit.rev = (unit.rev or 0) + 1
end

local function Intern(unit, text)
	return S.Intern(unit, text)
end

local function Str(unit, id)
	return id and unit.strings[id] or nil
end
R.Str = Str

-- "Name-Realm" -> "Name", "Realm"; "First Surname" -> itself, nil.
local function SplitKey(key)
	local name, realm = key:match("^(.-)%-([^%-]+)$")
	if name and name ~= "" then return name, realm end
	return key, nil
end

---------------------------------------------------------------------------
-- Packed members and facts (see the top of the file). Inside this file a
-- member is a table { n, r, c, l, role, g, first, last } while it is
-- worked on, and facts are { kind, instID, diff, lvl, lvlOut, bosses, xp,
-- kills, money, wing, enc }; a run keeps them as the texts m and p.
---------------------------------------------------------------------------
local MEMBER_FIELDS = { "n", "c", "l", "role", "g", "first", "last", "r" }
local MEMBER_KNOWN = {}
for _, field in ipairs(MEMBER_FIELDS) do MEMBER_KNOWN[field] = true end
local FACT_FIELDS = { "kind", "instID", "diff", "lvl", "lvlOut", "bosses", "xp", "kills", "money", "wing", "enc" }
local ROLE_CODE = { TANK = "T", HEALER = "H", DAMAGER = "D", NONE = "N" }
local ROLE_NAME = { T = "TANK", H = "HEALER", D = "DAMAGER", N = "NONE" }

-- A text cut at every `sep`, empty pieces kept.
local function Split(text, sep)
	local out, start = {}, 1
	while true do
		local stop = text:find(sep, start, true)
		if not stop then
			out[#out + 1] = text:sub(start)
			return out
		end
		out[#out + 1] = text:sub(start, stop - 1)
		start = stop + 1
	end
end

local function Escape(text)
	return (text:gsub("[%%:;,~]", function(char) return ("%%%02X"):format(char:byte()) end))
end

local function Unescape(text)
	if not text:find("%", 1, true) then return text end
	return (text:gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end))
end

-- Each field as text: "" for none, nil for a value the text cannot keep
-- exactly (then the run keeps its tables and fields as they are).
local function NumberField(value)
	if value == nil then return "" end
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then return nil end
	if value == floor(value) and math.abs(value) < 1e14 then return ("%.14g"):format(value) end
	return ("%.17g"):format(value)
end

local function TextField(value)
	if value == nil then return "" end
	if type(value) ~= "string" or value == "" then return nil end
	return Escape(value)
end

local function RoleField(value)
	if value == nil then return "" end
	if type(value) ~= "string" or value == "" then return nil end
	return ROLE_CODE[value] or ("~" .. Escape(value))
end

-- kind: a run that is not a raid is a dungeon (also one saved without it).
local function KindField(value)
	if value == nil or value == "party" then return "" end
	if value == "raid" then return "r" end
	if type(value) ~= "string" or value == "" then return nil end
	return "~" .. Escape(value)
end

local function ListField(value)
	if value == nil then return "" end
	if type(value) ~= "table" or not value[1] then return nil end
	local parts, count = {}, 0
	for _ in pairs(value) do count = count + 1 end
	if count ~= #value then return nil end
	for position, id in ipairs(value) do
		local text = NumberField(id)
		if not text or text == "" then return nil end
		parts[position] = text
	end
	return table.concat(parts, ",")
end

local function ReadNumber(text)
	if text == nil or text == "" then return nil end
	return tonumber(text)
end

local function ReadText(text)
	if text == nil or text == "" then return nil end
	return Unescape(text)
end

local function ReadRole(text)
	if text == nil or text == "" then return nil end
	if text:sub(1, 1) == "~" then return Unescape(text:sub(2)) end
	return ROLE_NAME[text] or Unescape(text)
end

local function ReadKind(text)
	if text == nil or text == "" then return "party" end
	if text == "r" then return "raid" end
	if text:sub(1, 1) == "~" then return Unescape(text:sub(2)) end
	return Unescape(text)
end

local function ReadList(text)
	if text == nil or text == "" then return nil end
	local out = {}
	for _, part in ipairs(Split(text, ",")) do out[#out + 1] = tonumber(part) end
	return out
end

-- Fields joined by `sep`, the empty ones at the end left out.
local function Join(parts, count, sep)
	while count > 0 and parts[count] == "" do count = count - 1 end
	return table.concat(parts, sep, 1, count)
end

local function EncodeMember(member)
	if type(member) ~= "table" then return nil end
	for key in pairs(member) do
		if not MEMBER_KNOWN[key] then return nil end
	end
	local parts = {}
	for position, field in ipairs(MEMBER_FIELDS) do
		local value, text = member[field]
		if field == "c" then
			text = TextField(value)
		elseif field == "role" then
			text = RoleField(value)
		else
			text = NumberField(value)
		end
		if not text then return nil end
		parts[position] = text
	end
	return Join(parts, #MEMBER_FIELDS, ":")
end

-- The members as one text: nil for none, false when one of them holds a
-- value the text cannot keep exactly.
local function EncodeMembers(list)
	local parts = {}
	for position, member in ipairs(list) do
		local text = EncodeMember(member)
		if not text then return false end
		parts[position] = text
	end
	if not parts[1] then return nil end
	return table.concat(parts, ";")
end

local function DecodeMember(text)
	local f = Split(text, ":")
	return { n = ReadNumber(f[1]), c = ReadText(f[2]), l = ReadNumber(f[3]), role = ReadRole(f[4]), g = ReadNumber(f[5]),
		first = ReadNumber(f[6]), last = ReadNumber(f[7]), r = ReadNumber(f[8]) }
end

-- The facts as one text: nil for none, false as above.
local function EncodeFacts(facts)
	local parts = {}
	for position, field in ipairs(FACT_FIELDS) do
		local value, text = facts[field]
		if field == "kind" then
			text = KindField(value)
		elseif field == "enc" then
			text = ListField(value)
		else
			text = NumberField(value)
		end
		if not text then return false end
		parts[position] = text
	end
	local packed = Join(parts, #FACT_FIELDS, ":")
	return packed ~= "" and packed or nil
end

-- A run's members to work on: the packed ones, then any still kept as
-- tables (a run saved before version 3; those are the saved tables).
local function RunMembers(run)
	local out = {}
	if type(run.m) == "string" then
		for _, text in ipairs(Split(run.m, ";")) do out[#out + 1] = DecodeMember(text) end
	end
	if type(run.with) == "table" then
		for _, member in ipairs(run.with) do
			if type(member) == "table" then out[#out + 1] = member end
		end
	end
	return out
end

-- A run's facts to work on: the packed ones, and any field still kept
-- on the run (saved before version 3, or by an older EldoUI) over them.
local function RunFacts(run)
	local facts
	if type(run.p) == "string" then
		local f = Split(run.p, ":")
		facts = { kind = ReadKind(f[1]), instID = ReadNumber(f[2]), diff = ReadNumber(f[3]), lvl = ReadNumber(f[4]),
			lvlOut = ReadNumber(f[5]), bosses = ReadNumber(f[6]), xp = ReadNumber(f[7]), kills = ReadNumber(f[8]),
			money = ReadNumber(f[9]), wing = ReadNumber(f[10]), enc = ReadList(f[11]) }
	else
		facts = { kind = "party" }
	end
	for _, field in ipairs(FACT_FIELDS) do
		if run[field] ~= nil then facts[field] = run[field] end
	end
	return facts
end

-- Members back onto a run: packed, or as tables when one of them holds a
-- value the text cannot keep exactly.
local function SetMembers(run, list)
	local text = EncodeMembers(list)
	if text == false then
		run.m, run.with = nil, list
		return false
	end
	run.m, run.with = text, nil
	return true
end

local function SetFacts(run, facts)
	local text = EncodeFacts(facts)
	if text == false then
		run.p = nil
		for _, field in ipairs(FACT_FIELDS) do run[field] = facts[field] end
		return false
	end
	run.p = text
	for _, field in ipairs(FACT_FIELDS) do run[field] = nil end
	return true
end

-- The members' companion keys, in the run's order (members without one
-- left out). out: a list to add to.
local function MemberKeys(unit, run, out)
	out = out or {}
	local m = run.m
	if type(m) == "string" then
		local start = 1
		while true do
			local id = m:match("^(%d+)", start)
			local key = id and unit.strings[tonumber(id)]
			if key then out[#out + 1] = key end
			local stop = m:find(";", start, true)
			if not stop then break end
			start = stop + 1
		end
	end
	if type(run.with) == "table" then
		for _, member in ipairs(run.with) do
			local key = type(member) == "table" and Str(unit, member.n)
			if key then out[#out + 1] = key end
		end
	end
	return out
end
R.MemberKeys = function(unit, run) return MemberKeys(unit, run) end

function R.Members(unit, run)
	local out = {}
	if not (type(unit) == "table" and type(run) == "table") then return out end
	for _, member in ipairs(RunMembers(run)) do
		out[#out + 1] = { key = Str(unit, member.n), realm = Str(unit, member.r), class = member.c, level = member.l,
			role = member.role, guild = Str(unit, member.g), first = member.first, last = member.last }
	end
	return out
end

function R.Facts(unit, run)
	if type(run) ~= "table" then return {} end
	local f = RunFacts(run)
	local encounters
	if type(f.enc) == "table" then
		encounters = {}
		for position, id in ipairs(f.enc) do encounters[position] = id end
	end
	return { kind = f.kind, instanceID = tonumber(f.instID), difficulty = tonumber(f.diff), level = tonumber(f.lvl),
		levelOut = tonumber(f.lvlOut), bosses = tonumber(f.bosses), xp = tonumber(f.xp), kills = tonumber(f.kills),
		money = tonumber(f.money), wing = type(unit) == "table" and Str(unit, f.wing) or nil, encounters = encounters }
end

local function NeedsPack(run)
	if run.with ~= nil then return true end
	for _, field in ipairs(FACT_FIELDS) do
		if run[field] ~= nil then return true end
	end
	return false
end
R.NeedsPack = NeedsPack

local function SameList(a, b)
	if a == nil or b == nil then return a == b end
	if #a ~= #b then return false end
	for position = 1, #a do
		if a[position] ~= b[position] then return false end
	end
	return true
end

-- One run saved before version 3, packed in place, only when the texts
-- read back exactly what it holds; otherwise it stays as it is.
local function PackRun(run)
	if type(run) ~= "table" or not NeedsPack(run) then return true end
	local entries = run.with
	if entries ~= nil then
		local count = 0
		for key, member in pairs(type(entries) == "table" and entries or {}) do
			if type(key) ~= "number" or type(member) ~= "table" then count = -1 break end
			count = count + 1
		end
		if type(entries) ~= "table" or count ~= #entries then
			R.stats.packKept = R.stats.packKept + 1
			return false
		end
	end
	local facts, members = RunFacts(run), RunMembers(run)
	local p, m = EncodeFacts(facts), EncodeMembers(members)
	local same = p ~= false and m ~= false
	if same then
		local back = { p = p, m = m }
		local backFacts, backMembers = RunFacts(back), RunMembers(back)
		for _, field in ipairs(FACT_FIELDS) do
			if field == "enc" then
				same = same and SameList(backFacts.enc, facts.enc)
			elseif field == "kind" then
				same = same and backFacts.kind == (facts.kind or "party")
			else
				same = same and backFacts[field] == facts[field]
			end
		end
		same = same and #backMembers == #members
		for position = 1, same and #members or 0 do
			for _, field in ipairs(MEMBER_FIELDS) do
				same = same and backMembers[position][field] == members[position][field]
			end
		end
	end
	if not same then
		R.stats.packKept = R.stats.packKept + 1
		return false
	end
	run.p, run.m, run.with = p, m, nil
	for _, field in ipairs(FACT_FIELDS) do run[field] = nil end
	R.stats.packed = R.stats.packed + 1
	return true
end
R.PackRun = PackRun

-- The place of run `id` (ids grow along the list).
local function Locate(list, id)
	local low, high = 1, #list
	while low <= high do
		local mid = floor((low + high) / 2)
		local other = list[mid].id or 0
		if other == id then return mid end
		if other < id then low = mid + 1 else high = mid - 1 end
	end
	return nil, low
end

function R:Find(id, charKey)
	local unit = self:Store(charKey)
	id = tonumber(id)
	if not (unit and id) then return nil end
	local index = Locate(unit.list, id)
	if index then return unit.list[index], index end
end

---------------------------------------------------------------------------
-- The index (derived: rebuilt when the store changed without it)
---------------------------------------------------------------------------
local function Append(map, key, index)
	local list = map[key]
	if not list then
		list = {}
		map[key] = list
	end
	if list[#list] ~= index then list[#list + 1] = index end
	return list
end

-- A number into a list kept in order.
local function InsertValue(list, value)
	local low, high = 1, #list
	while low <= high do
		local mid = floor((low + high) / 2)
		if list[mid] <= value then low = mid + 1 else high = mid - 1 end
	end
	tinsert(list, low, value)
end

-- The tally of one instance: runs, time inside, the fastest run, every
-- run's length in order (for the median) and how many companions came.
local function Tally(idx, inst)
	local agg = idx.agg[inst]
	if not agg then
		agg = { n = 0, inside = 0, d = {}, ppl = 0 }
		idx.agg[inst] = agg
	end
	return agg
end

-- Did this companion come to this instance in an earlier run? Rebuilds
-- keep a set per instance; a single append looks through the companion's
-- own runs.
local function CameBefore(unit, idx, key, inst, index, seen)
	if seen then
		local set = seen[inst]
		if not set then
			set = {}
			seen[inst] = set
		end
		if set[key] then return true end
		set[key] = true
		return false
	end
	for _, place in ipairs(idx.with[key] or {}) do
		local other = place ~= index and unit.list[place]
		if other and other.inst == inst then return true end
	end
	return false
end

-- The winners of a run's drops, as companion keys.
local function Winners(unit, run, out)
	out = out or {}
	for _, drop in ipairs(type(run.loot) == "table" and run.loot or {}) do
		local key = type(drop) == "table" and drop.w and unit.strings[drop.w]
		if key then out[#out + 1] = key end
	end
	return out
end

-- seen: the per-instance companion sets of a rebuild (nil for one append;
-- a rebuild sorts the run lengths once at the end).
local function AddToIndex(unit, idx, index, run, seen)
	local agg
	if run.inst then
		Append(idx.inst, run.inst, index)
		agg = Tally(idx, run.inst)
		agg.n = agg.n + 1
		local t, leave = tonumber(run.t), tonumber(run.leave)
		if t and leave and leave > t then
			local seconds = leave - t
			agg.inside = agg.inside + seconds
			if not agg.fast or seconds < agg.fast then agg.fast = seconds end
			if seen then agg.d[#agg.d + 1] = seconds else InsertValue(agg.d, seconds) end
		end
	end
	for _, key in ipairs(MemberKeys(unit, run)) do
		if agg and not CameBefore(unit, idx, key, run.inst, index, seen) then agg.ppl = agg.ppl + 1 end
		Append(idx.with, key, index)
	end
	-- One place per drop won: a run where they won two items is there twice.
	for _, key in ipairs(Winners(unit, run)) do
		idx.won[key] = idx.won[key] or {}
		local list = idx.won[key]
		list[#list + 1] = index
	end
	if run.src then idx.src[run.src] = index end
end

-- The whole index again. yield: called every R.REBUILD_SLICE runs (a job
-- in slices). Runs added meanwhile leave the result out of date, so the
-- next read rebuilds again.
local function Rebuild(unit, yield)
	local rev = unit.rev
	local idx = { inst = {}, with = {}, src = {}, won = {}, agg = {} }
	local seen = {}
	local index = 1
	while unit.list[index] do
		AddToIndex(unit, idx, index, unit.list[index], seen)
		if yield and index % R.REBUILD_SLICE == 0 then
			R.stats.slices = R.stats.slices + 1
			yield()
		end
		index = index + 1
	end
	for _, agg in pairs(idx.agg) do table.sort(agg.d) end
	idx.rev = rev
	unit.idx = idx
	R.stats.rebuilt = R.stats.rebuilt + 1
	return idx
end
R.Rebuild = Rebuild

local function Fresh(unit)
	local idx = unit.idx
	return type(idx) == "table" and idx.rev == unit.rev and type(idx.with) == "table" and type(idx.inst) == "table"
		and type(idx.src) == "table" and type(idx.won) == "table" and type(idx.agg) == "table" and idx.day == nil
end
R.Fresh = Fresh

local function JobKey(charKey)
	return "runsindex:" .. tostring(charKey or E.charKey)
end

-- The index of a store, up to date: rebuilt at once for a store of up to
-- R.SYNC_REBUILD runs out of combat, else in slices that wait for the end
-- of combat while the old one (or none) serves. force: rebuild now
-- whatever the size.
function R:Index(charKey, force)
	local unit = self:Store(charKey)
	if not unit then return nil end
	if Fresh(unit) then return unit.idx end
	if force or (#unit.list <= R.SYNC_REBUILD and not InCombatLockdown()) then return Rebuild(unit) end
	A:RunJob(JobKey(charKey), function()
		Rebuild(unit, coroutine.yield)
	end, function()
		J:Changed("runs")
		A:MarkDirty("runs")
	end)
	local idx = unit.idx
	if type(idx) == "table" and type(idx.with) == "table" and type(idx.inst) == "table" and type(idx.won) == "table"
		and type(idx.agg) == "table" then
		return idx
	end
	return nil
end

function R:Updating(charKey)
	return A:JobRunning(JobKey(charKey))
end

-- An index entry that keeps its places in order.
local function InsertSorted(list, index)
	local position = #list + 1
	while position > 1 and list[position - 1] > index do position = position - 1 end
	if list[position - 1] == index then return end
	tinsert(list, position, index)
end

-- While a large index is rebuilt in slices and no older one is there, a
-- list shows what the newest two pages of runs hold (oldest first, like
-- the index), and the page says it is still filling in.
local function Tail(unit, match)
	local out = {}
	local list = unit and unit.list or {}
	for index = math.max(1, #list - 2 * R.PAGE + 1), #list do
		local run = list[index]
		R.stats.touched = R.stats.touched + 1
		for _ = 1, match(run) or 0 do out[#out + 1] = index end
	end
	return out
end
R.Tail = Tail

local function HasMember(unit, run, key)
	for _, other in ipairs(MemberKeys(unit, run)) do
		if other == key then return 1 end
	end
end

function R:RunsWith(key, charKey)
	local idx = self:Index(charKey)
	if idx then return idx.with[key] or {} end
	local unit = self:Store(charKey)
	if not unit then return {} end
	return Tail(unit, function(run) return HasMember(unit, run, key) end)
end

function R:WonBy(key, charKey)
	local idx = self:Index(charKey)
	if idx then return idx.won[key] or {} end
	local unit = self:Store(charKey)
	if not unit then return {} end
	return Tail(unit, function(run)
		local count = 0
		for _, winner in ipairs(Winners(unit, run)) do
			if winner == key then count = count + 1 end
		end
		return count
	end)
end

function R:PlacesOf(name, charKey)
	local unit = self:Store(charKey)
	local id = unit and S.StringId(unit, name)
	if not id then return {} end
	local idx = self:Index(charKey)
	if idx then return idx.inst[id] or {} end
	return Tail(unit, function(run) return run.inst == id and 1 or nil end)
end
R.RunsOf = R.PlacesOf

-- An instance's tally from the index: runs, time inside, the fastest and
-- the median run, and how many companions came along.
function R:Totals(name, charKey)
	local unit = self:Store(charKey)
	local id = unit and S.StringId(unit, name)
	local idx = id and self:Index(charKey)
	local agg = idx and idx.agg[id]
	if not agg then return nil end
	local d, median = agg.d, nil
	if #d > 0 then
		local middle = floor((#d + 1) / 2)
		median = #d % 2 == 0 and floor((d[middle] + d[middle + 1]) / 2) or d[middle]
	end
	return { n = agg.n, inside = agg.inside, fast = agg.fast, median = median, ppl = agg.ppl }
end

-- The newest `count` places of a list of places, newest first.
function R:Newest(places, count)
	local out = {}
	places = type(places) == "table" and places or {}
	for position = #places, math.max(1, #places - (count or R.PAGE) + 1), -1 do out[#out + 1] = places[position] end
	return out
end

-- The run at a place; pages read runs only through this (R.stats.touched).
function R:Get(index, charKey)
	local unit = self:Store(charKey)
	local run = unit and index and unit.list[index]
	if run then R.stats.touched = R.stats.touched + 1 end
	return run
end

-- The place of the run copied from Instances run `src`.
local function PlaceOf(unit, src)
	local idx = Fresh(unit) and unit.idx
	if idx then return idx.src[src] end
	for index = #unit.list, 1, -1 do
		if unit.list[index].src == src then return index end
	end
end

function R:BySource(src, charKey)
	local unit = self:Store(charKey)
	src = tonumber(src)
	if not (unit and src) then return nil end
	local index = PlaceOf(unit, src)
	if index then return unit.list[index], index end
end

---------------------------------------------------------------------------
-- Writing runs
---------------------------------------------------------------------------
local function Journal(charKey)
	local root = S.Root()
	local rec = root and root[charKey or E.charKey]
	return type(rec) == "table" and rec or nil
end

local function Fellows(charKey)
	local rec = Journal(charKey)
	return rec and type(rec.fellows) == "table" and rec.fellows or nil
end

-- A companion counts the runs it was in and knows its newest one. Only
-- companions the journal already knows are counted.
local function CountRun(fellows, key, id, delta)
	local fellow = fellows and fellows[key]
	if type(fellow) ~= "table" then return end
	if fellow.runs ~= nil and type(fellow.runs) ~= "number" then return end
	fellow.runs = math.max(0, (fellow.runs or 0) + delta)
	if delta > 0 and (tonumber(fellow.lastRun) or 0) < id then fellow.lastRun = id end
end

local function NewMember(unit, member)
	local key = Text(member.key)
	if not key then
		local name = Text(member.name)
		if not name then return nil end
		local realm = Text(member.realm)
		key = realm and (name .. "-" .. realm) or name
	end
	local realm = Text(member.realm)
	if not realm then
		local _, keyRealm = SplitKey(key)
		realm = keyRealm
	end
	return {
		n = Intern(unit, key), r = realm and Intern(unit, realm) or nil,
		c = Text(member.class), l = Number(member.level), role = Text(member.role),
		g = Text(member.guild) and Intern(unit, member.guild) or nil,
		first = Number(member.first), last = Number(member.last),
	}, key
end

-- Fold a member seen again into its entry: newer values win, a value the
-- game did not give leaves the old one.
local function UpdateMember(unit, entry, member)
	local class, level, role = Text(member.class), Number(member.level), Text(member.role)
	if class then entry.c = class end
	if level then entry.l = level end
	if role then entry.role = role end
	if Text(member.guild) then entry.g = Intern(unit, member.guild) end
	local first, last = Number(member.first), Number(member.last)
	if first and (not entry.first or first < entry.first) then entry.first = first end
	if last and (not entry.last or last > entry.last) then entry.last = last end
end

local RUN_NUMBERS = { "bosses", "xp", "kills", "money" }

local function SetFields(unit, record, run)
	record.t = Number(run.t) or record.t
	record.leave = Number(run.leave) or record.leave
	local inst = Text(run.instance)
	if inst then record.inst = Intern(unit, inst) end
	local facts = RunFacts(record)
	local instID = Number(run.instanceID)
	if instID and instID ~= 0 then facts.instID = instID end
	local wing = Text(run.wing)
	if wing then facts.wing = Intern(unit, wing) end
	facts.kind = (run.kind == "raid" and "raid") or "party"
	local diff = Number(run.difficulty)
	if diff and diff > 1 then facts.diff = diff end
	facts.lvl = Number(run.level) or facts.lvl
	facts.lvlOut = Number(run.levelOut) or facts.lvlOut
	for _, key in ipairs(RUN_NUMBERS) do
		local value = Number(run[key])
		if value and value > 0 then facts[key] = value end
	end
	if type(run.encounters) == "table" and run.encounters[1] then
		local enc = {}
		for _, id in ipairs(run.encounters) do
			if Number(id) then enc[#enc + 1] = id end
		end
		if enc[1] then facts.enc = enc end
	end
	SetFacts(record, facts)
	if run.imp then record.imp = run.imp end
end

-- Was a run copied from this Instances run deleted by the player? Then a
-- later close leaves it deleted.
local function Deleted(charKey, src)
	local rec = Journal(charKey)
	for _, item in ipairs(rec and type(rec.trash) == "table" and rec.trash or {}) do
		if type(item) == "table" and item.kind == "run" and type(item.data) == "table" and type(item.data.run) == "table"
			and item.data.run.src == src and item.data.charKey == (charKey or E.charKey) then
			return true
		end
	end
	return false
end

-- A finished drop into a run (or a run still open): the same drop again
-- adds nothing, except rolls the game listed since (more of them); its
-- winner never changes. Past R.LOOT_CAP drops the run only counts them.
-- Returns "added", "same" or "over".
local function AddDrop(holder, drop)
	holder.loot = type(holder.loot) == "table" and holder.loot or {}
	for _, old in ipairs(holder.loot) do
		if type(old) == "table" and old.k == drop.k then
			if type(drop.r) == "table" and (type(old.r) ~= "table" or #drop.r > #old.r) then
				old.r = drop.r
				R.stats.lootEnriched = R.stats.lootEnriched + 1
			end
			if not old.i and drop.i then old.i = drop.i end
			return "same"
		end
	end
	if #holder.loot >= R.LOOT_CAP then
		holder.lootMore = (tonumber(holder.lootMore) or 0) + 1
		R.stats.lootOver = R.stats.lootOver + 1
		return "over"
	end
	holder.loot[#holder.loot + 1] = drop
	R.stats.lootSaved = R.stats.lootSaved + 1
	return "added"
end
R.AddDrop = AddDrop

-- The drops kept while the run was open move onto its record.
local function FoldPending(unit, record, src)
	local pend = src and type(unit.lootPend) == "table" and unit.lootPend[src]
	if type(pend) ~= "table" then return false end
	unit.lootPend[src] = nil
	for _, drop in ipairs(type(pend.loot) == "table" and pend.loot or {}) do
		if type(drop) == "table" then AddDrop(record, drop) end
	end
	local more = tonumber(pend.lootMore)
	if more and more > 0 then record.lootMore = (tonumber(record.lootMore) or 0) + more end
	return true
end

-- Add a run, or update the one copied from the same Instances run (a run
-- closed again after a reload or a merge). Returns the record.
local function Write(unit, charKey, run, members)
	local src = Number(run.src)
	local list = unit.list
	local record
	if src then
		for position = #list, math.max(1, #list - R.TAIL + 1), -1 do
			if list[position].src == src then
				record = list[position]
				break
			end
		end
		if not record and Deleted(charKey, src) then return nil end
	end
	local fellows = Fellows(charKey)
	local fresh = Fresh(unit)
	local idx = unit.idx
	if record then
		local with = RunMembers(record)
		local have = {}
		for position, entry in ipairs(with) do
			local key = Str(unit, entry.n)
			if key then have[key] = position end
		end
		local t, leave, inst = record.t, record.leave, record.inst
		SetFields(unit, record, run)
		-- The index stays as it is unless the run moved, changed place or
		-- gained a member or a drop; then it is rebuilt when next read.
		local moved = record.t ~= t or record.leave ~= leave or record.inst ~= inst
		for _, member in ipairs(members or {}) do
			local entry, key = NewMember(unit, member)
			if entry then
				if have[key] then
					UpdateMember(unit, with[have[key]], member)
				else
					with[#with + 1] = entry
					have[key] = #with
					CountRun(fellows, key, record.id, 1)
					moved = true
				end
			end
		end
		SetMembers(record, with)
		if FoldPending(unit, record, src) then moved = true end
		Bump(unit)
		if fresh and not moved then idx.rev = unit.rev end
		R.stats.updated = R.stats.updated + 1
		return record
	end
	unit.seq = unit.seq + 1
	record = { id = unit.seq, src = src }
	SetFields(unit, record, run)
	local seen, with = {}, {}
	for _, member in ipairs(members or {}) do
		local entry, key = NewMember(unit, member)
		if entry then
			if seen[key] then
				UpdateMember(unit, with[seen[key]], member)
			else
				with[#with + 1] = entry
				seen[key] = #with
			end
		end
	end
	SetMembers(record, with)
	FoldPending(unit, record, src)
	list[#list + 1] = record
	for key in pairs(seen) do CountRun(fellows, key, record.id, 1) end
	if src and src > unit.lastSrc then unit.lastSrc = src end
	Bump(unit)
	if fresh then
		AddToIndex(unit, idx, #list, record)
		idx.rev = unit.rev
	end
	R.stats.appended = R.stats.appended + 1
	return record
end

function R:Append(run, members, charKey)
	if type(run) ~= "table" or run.kind == "pvp" then return nil end
	local unit = self:Store(charKey, true)
	if not unit then return nil end
	return Write(unit, charKey or E.charKey, run, members)
end

---------------------------------------------------------------------------
-- From the Instances log
---------------------------------------------------------------------------
local function SortedKeys(set)
	local keys = {}
	for key in pairs(set) do
		if type(key) == "string" then keys[#keys + 1] = key end
	end
	table.sort(keys)
	return keys
end

-- The members of an Instances run: the roster it saw (run.group) and the
-- companions the journal noted inside (runExtras[id].with). An older
-- roster names a member without the surname: it joins the noted companion
-- whose first name and realm it shares.
local function MembersOf(run, extras, fellows)
	local members, byKey = {}, {}
	local function Add(key)
		local member = byKey[key]
		if not member then
			member = { key = key }
			local fellow = fellows and fellows[key]
			if type(fellow) == "table" then
				member.class, member.level = fellow.class, fellow.level
			end
			byKey[key] = member
			members[#members + 1] = member
		end
		return member
	end
	local with = type(extras) == "table" and type(extras.with) == "table" and extras.with or {}
	local firstNames = {}
	for _, key in ipairs(SortedKeys(with)) do
		Add(key)
		local name, realm = SplitKey(key)
		local first = name:match("^(%S+)")
		if first then firstNames[first .. "\31" .. tostring(realm)] = key end
	end
	local group = type(run.group) == "table" and run.group or {}
	local me = type(run.name) == "string" and run.name or nil
	for _, name in ipairs(SortedKeys(group)) do
		local info = type(group[name]) == "table" and group[name] or {}
		if not info.me and name ~= me then
			local key = Text(info.key)
			if not key then
				local base, realm = SplitKey(name)
				key = firstNames[base .. "\31" .. tostring(realm)] or (J.Key and J:Key(name)) or name
			end
			local member = Add(key)
			if Text(info.class) then member.class = info.class end
			if Number(info.level) then member.level = info.level end
			member.role, member.guild, member.realm = Text(info.role), Text(info.guild), Text(info.realm)
			member.first, member.last = Number(info.first), Number(info.last)
		end
	end
	return members
end
R.MembersOf = MembersOf

local function FromInstances(run, extras)
	local encounters = type(extras) == "table" and type(extras.bosses) == "table" and extras.bosses or nil
	local bosses = Number(run.bosses) or (encounters and #encounters) or (type(extras) == "table" and Number(extras.bosses)) or nil
	return {
		src = run.id, t = run.enter, leave = run.leave, instance = run.instance, instanceID = run.instanceID,
		kind = run.kind, difficulty = run.difficulty, level = run.enterLevel, levelOut = run.leaveLevel,
		bosses = bosses, encounters = encounters, xp = run.xp, kills = run.kills, money = run.money,
	}
end

local function Copyable(run)
	return type(run) == "table" and run.kind ~= "pvp" and type(run.enter) == "number" and type(run.leave) == "number"
		and type(run.id) == "number"
end

-- Copy the closed runs of a character from the Instances log; since: only
-- runs with a higher id. Returns how many were added.
local function CopyFromLog(unit, charKey, since)
	local M = E.Instances
	if not (M and M.RunsFor) then return 0 end
	local ok, runs = pcall(M.RunsFor, M, charKey)
	if not ok or type(runs) ~= "table" then return 0 end
	local rec = Journal(charKey)
	local extras = rec and type(rec.runExtras) == "table" and rec.runExtras or {}
	local fellows = rec and type(rec.fellows) == "table" and rec.fellows or nil
	local added = 0
	for position = #runs, 1, -1 do   -- the log is newest first
		local run = runs[position]
		if Copyable(run) and run.id > (since or 0) then
			if Write(unit, charKey, FromInstances(run, extras[run.id]), MembersOf(run, extras[run.id], fellows)) then
				added = added + 1
			end
		end
	end
	return added
end

-- Update step 1: the runs the Instances log still has, with the
-- companions the journal noted for them. Runs before a copy already in
-- the store are not copied twice; the journal's own notes stay as they are.
E:RegisterStoreStep("journalRuns", 1, function(unit)
	if not folding then return end
	Fill(unit)
	local copied = CopyFromLog(unit, folding, unit.lastSrc)
	R.stats.folded = R.stats.folded + copied
end)

-- Update step 2: runs may now keep the loot rolls that ended during them.
-- Runs saved before stay exactly as they are (they have no loot); nothing
-- is added, changed or removed.
E:RegisterStoreStep("journalRuns", 2, function()
end)

-- Update step 3: each run keeps its members and facts packed in two texts
-- (see the top of the file). The runs read the same either way, so the
-- step only marks the store (pk) and the runs are packed after it: at once
-- for a store of up to R.SYNC_PACK runs out of combat, else in slices of
-- R.PACK_SLICE runs that wait for the end of combat; a reload in between
-- picks it up again. Nothing is added or removed, and a run holding a
-- value the texts could not keep exactly stays as it is.
E:RegisterStoreStep("journalRuns", 3, function(unit)
	Fill(unit)
	if unit.list[1] then unit.pk = 1 end
end)

local function PackJobKey(charKey)
	return "runspack:" .. tostring(charKey or E.charKey)
end

-- Every run of a store packed; a pass that met a change (a run added or
-- deleted meanwhile) is followed by another.
local function PackAll(unit, yield)
	repeat
		local rev, index = unit.rev, 1
		while unit.list[index] do
			PackRun(unit.list[index])
			if yield and index % R.PACK_SLICE == 0 then
				R.stats.packSlices = R.stats.packSlices + 1
				yield()
			end
			index = index + 1
		end
	until unit.rev == rev
	unit.pk = nil
end
R.PackAll = PackAll

StartPack = function(unit, charKey)
	local backingUp = ResumeBackup(unit, charKey)
	if not (unit and unit.pk) then return end
	if not unit.list[1] then
		unit.pk = nil
		return
	end
	if #unit.list <= R.SYNC_PACK and not InCombatLockdown() and not backingUp then
		PackAll(unit)
		return
	end
	A:RunJob(PackJobKey(charKey), function()
		PackAll(unit, coroutine.yield)
	end, function()
		-- The store was put back or cleared meanwhile: its runs next.
		local root = Root()
		local now = root and root[charKey or E.charKey]
		if type(now) == "table" and now ~= unit and now.pk and migrated[now] then StartPack(now, charKey) end
	end)
end

-- Is the update still packing a store's runs?
function R:Packing(charKey)
	return A:JobRunning(PackJobKey(charKey))
end

-- Runs closed while the journal was not running (or the module was off).
function R:CatchUp(charKey)
	local unit = self:Store(charKey)
	if not unit then return 0 end
	return CopyFromLog(unit, charKey or E.charKey, unit.lastSrc)
end

-- The Instances module closed a run.
local function OnRunClosed(run)
	if not (J:Recording() and Copyable(run)) then return end
	local unit = R:Store()
	if not unit then return end
	local rec = Journal()
	local extras = rec and type(rec.runExtras) == "table" and rec.runExtras[run.id] or nil
	local written = Write(unit, E.charKey, FromInstances(run, extras), MembersOf(run, extras, rec and rec.fellows))
	if written then
		J:Changed("runs")
		A:MarkDirty("runs")
	end
end
R.OnRunClosed = OnRunClosed

---------------------------------------------------------------------------
-- Loot rolls: what the game's loot history shows once a roll has ended.
-- Read from the history the game keeps for the group (C_LootHistory) on
-- its own events, so it works while the game's loot history window stays
-- closed; nothing opens a window and nothing rolls. A drop belongs to the
-- run that was open when it first showed up, also when its roll ends
-- after you left (up to R.LOOT_LATE later) or after a reload, and never to
-- a run that started later.
---------------------------------------------------------------------------
local function Flag(value)
	return not E:IsSecret(value) and value == true
end

-- The Instances run open now, when it is one the journal keeps: a dungeon
-- or a raid (never a battleground or an arena) while the journal records.
local function OpenRun()
	if not J:Recording() then return nil end
	local M = E.Instances
	if not (M and M.Recording and M:Recording()) then return nil end
	local run = M.current
	if type(run) ~= "table" or run.leave or type(run.id) ~= "number" then return nil end
	if run.kind ~= "party" and run.kind ~= "raid" then return nil end
	local inside, kind = IsInInstance()
	if E:IsSecret(inside) or E:IsSecret(kind) or not inside or (kind ~= "party" and kind ~= "raid") then return nil end
	return run
end

local function History()
	local api = C_LootHistory
	return type(api) == "table" and api or nil
end

local function ReadableLootTable(value)
	return type(value) == "table" and not E.Secret(value) and (not canaccesstable or canaccesstable(value))
end

local function ReadDrop(encounter, key)
	local api = History()
	if not (api and api.GetSortedInfoForDrop) then return nil end
	R.stats.lootReads = R.stats.lootReads + 1
	local ok, info = pcall(api.GetSortedInfoForDrop, encounter, key)
	if ok and ReadableLootTable(info) then return info end
	return nil
end

-- How long ago the game says the drop dropped (its own loot history clock,
-- as its loot history window counts it), when it says.
local function Age(info)
	local api = History()
	if not (api and api.GetLootHistoryTime) then return nil end
	local now, start = E.PlainCall(api.GetLootHistoryTime), Number(info.startTime)
	if type(now) == "number" and start and now >= start then return now - start end
	return nil
end

-- A name from the loot history as a companion key: the key the game gives
-- (with the surname on Forever), else the run's member with that first
-- name, else the name as shown.
local function NameKey(unit, name, src)
	local key = J.Key and J:Key(name) or name
	if type(key) ~= "string" or key == "" then return nil end
	if key:find("[%s%-]") then return key end
	local M = E.Instances
	local open = M and M.current
	if type(open) == "table" and open.id == src and type(open.group) == "table" and type(open.group[key]) == "table" then
		local known = Text(open.group[key].key)
		if known then return known end
	end
	local index = PlaceOf(unit, src)
	local record = index and unit.list[index]
	local found
	for _, other in ipairs(record and MemberKeys(unit, record) or {}) do
		if other == key or other:match("^(%S+)") == key then
			if found and found ~= other then return key end
			found = other
		end
	end
	return found or key
end

local function Field(value)
	if value == nil then return "" end
	return tostring(value)
end

-- One roll as the game listed it: "name:state:roll:class:flags". The name
-- is a number in `strings`, state the game's roll type, roll the number it
-- showed (empty when it showed none), class the class token; flags m (you)
-- and w (the winner).
local function PackRoll(unit, roll, src)
	local me = Flag(roll.isSelf)
	local nameId
	if not me then
		local name = Text(roll.playerName)
		local key = name and NameKey(unit, name, src)
		nameId = key and Intern(unit, key) or nil
	end
	local class = Text(roll.playerClass)
	if class and class:find(":", 1, true) then class = nil end
	local flags = (me and "m" or "") .. (Flag(roll.isWinner) and "w" or "")
	return table.concat({ Field(nameId), Field(Number(roll.state)), Field(Number(roll.roll)), Field(class), flags }, ":")
end

-- A finished drop as the run keeps it, or nil while the roll goes on: only
-- a winner or "everyone passed" ends it (a leader or a tie does not).
local function Result(unit, info, key, src)
	local passed = Flag(info.allPassed)
	local winner = not passed and type(info.winner) == "table" and info.winner or nil
	if not (passed or winner) then return nil end
	local drop = { k = key, t = Now() }
	local link = Text(info.itemHyperlink)
	if link then drop.i = Intern(unit, link) end
	if passed then drop.pass = true end
	if winner then
		if Flag(winner.isSelf) then
			drop.wm = true
		else
			local name = Text(winner.playerName)
			local winnerKey = name and NameKey(unit, name, src)
			if winnerKey then drop.w = Intern(unit, winnerKey) end
		end
	end
	local rolls = {}
	for _, roll in ipairs(type(info.rollInfos) == "table" and info.rollInfos or {}) do
		if #rolls >= R.LOOT_ROLLS then break end
		if type(roll) == "table" then rolls[#rolls + 1] = PackRoll(unit, roll, src) end
	end
	if rolls[1] then drop.r = rolls end
	return drop
end
R.Result = Result

local function Changed()
	J:Changed("runs")
	A:MarkDirty("runs")
end

-- A finished drop to its run: the journal's record when the run has one
-- (also after it closed, up to R.LOOT_LATE later), else kept with the run
-- that is still open until it closes.
local function KeepDrop(unit, src, drop)
	local index = PlaceOf(unit, src)
	local record = index and unit.list[index]
	local M = E.Instances
	local open = M and M.current
	local stillOpen = type(open) == "table" and open.id == src and not open.leave
	if record then
		if not stillOpen and tonumber(record.leave) and drop.t > record.leave + R.LOOT_LATE then
			R.stats.lootSkipped = R.stats.lootSkipped + 1
			return false
		end
		local fresh = Fresh(unit)
		local how = AddDrop(record, drop)
		Bump(unit)
		if fresh then
			if how == "added" and drop.w and unit.strings[drop.w] then
				local key = unit.strings[drop.w]
				unit.idx.won[key] = unit.idx.won[key] or {}
				local list = unit.idx.won[key]
				local position = #list + 1
				while position > 1 and list[position - 1] > index do position = position - 1 end
				tinsert(list, position, index)
			end
			unit.idx.rev = unit.rev
		end
		Changed()
		return true
	end
	if stillOpen then
		unit.lootPend = type(unit.lootPend) == "table" and unit.lootPend or {}
		local pend = type(unit.lootPend[src]) == "table" and unit.lootPend[src] or { loot = {} }
		unit.lootPend[src] = pend
		AddDrop(pend, drop)
		return true
	end
	R.stats.lootSkipped = R.stats.lootSkipped + 1
	return false
end

local function Watch(unit)
	if type(unit.lootWatch) ~= "table" then unit.lootWatch = {} end
	return unit.lootWatch
end

-- Old entries go: drops long done or never finished. Returns how many stay.
local function PruneWatch(watch)
	local cutoff = Now() - R.WATCH_SECONDS
	local count = 0
	for key, seen in pairs(watch) do
		if type(seen) ~= "table" or (tonumber(seen.at) or 0) < cutoff then
			watch[key] = nil
		else
			count = count + 1
		end
	end
	return count
end

-- A drop the game updated: which run it belongs to (the open one when it
-- first shows up), then its result once the roll has ended.
local function Observe(encounter, key, info)
	encounter, key = Number(encounter), Number(key)
	if not (encounter and key) or not J:Recording() then return end
	local unit = R:Store()
	if not unit then return end
	local id = ("%d:%d"):format(encounter, key)
	local watch = Watch(unit)
	local seen = type(watch[id]) == "table" and watch[id] or nil
	if not ReadableLootTable(info) then info = ReadDrop(encounter, key) end
	-- The game numbers its drops again after its history starts over: the
	-- same key with another drop time or item is a new drop, never the old one.
	local start = type(info) == "table" and Number(info.startTime) or nil
	local link = type(info) == "table" and Text(info.itemHyperlink) or nil
	if seen and ((start and seen.st and start ~= seen.st) or (link and seen.link and link ~= seen.link)) then
		watch[id] = nil
		seen = nil
	end
	if not seen then
		local run = OpenRun()
		if not run then return end
		local age = type(info) == "table" and Age(info)
		if age and age > R.LOOT_OLD then return end
		if PruneWatch(watch) >= R.WATCH_CAP then return end
		seen = { src = run.id, at = Now() }
		watch[id] = seen
	end
	if start then seen.st = start end
	if link then seen.link = link end
	-- Nothing to read yet (or no more): keep waiting, decide nothing.
	if type(info) ~= "table" then return end
	local drop = Result(unit, info, id, seen.src)
	if not drop then return end
	KeepDrop(unit, seen.src, drop)
	seen.done, seen.at = true, Now()
end
R.Observe = Observe
R.KeepDrop = KeepDrop

-- After a reload or a loading screen: the drops still rolling are read
-- once more (no timer: the game's next update reads them again).
local function Recover()
	local unit = R:Store()
	if not unit or type(unit.lootWatch) ~= "table" then return end
	PruneWatch(unit.lootWatch)
	local open = {}
	for id, seen in pairs(unit.lootWatch) do
		if not seen.done then open[#open + 1] = id end
	end
	table.sort(open)
	for _, id in ipairs(open) do
		local encounter, key = id:match("^(%d+):(%d+)$")
		if encounter then Observe(tonumber(encounter), tonumber(key)) end
	end
end
R.Recover = Recover

-- Drops kept for a run that is no longer open and that the journal did
-- not keep (it was not recording when the run closed) are let go.
local function PrunePending(unit)
	if type(unit.lootPend) ~= "table" then return end
	local M = E.Instances
	local open = M and M.current
	for src in pairs(unit.lootPend) do
		if not (type(open) == "table" and open.id == src) and not PlaceOf(unit, src) then unit.lootPend[src] = nil end
	end
end

local encounterQueued = {}
local lootEvents = CreateFrame("Frame")
lootEvents:SetScript("OnEvent", function(_, event, encounter, key)
	if event == "LOOT_HISTORY_UPDATE_DROP" then
		Observe(E.Plain(encounter), E.Plain(key))
	elseif event == "LOOT_HISTORY_UPDATE_ENCOUNTER" then
		-- Several updates of one encounter at once read it once.
		encounter = Number(encounter)
		if not encounter or encounterQueued[encounter] then return end
		encounterQueued[encounter] = true
		C_Timer.After(0.2, function()
			encounterQueued[encounter] = nil
			local api = History()
			if not (R.lootOn and api and api.GetSortedDropsForEncounter) then return end
			local ok, drops = pcall(api.GetSortedDropsForEncounter, encounter)
			if not ok or not ReadableLootTable(drops) then return end
			for position, drop in ipairs(drops) do
				if position > R.LOOT_CAP then break end
				if ReadableLootTable(drop) then Observe(encounter, drop.lootListKey, drop) end
			end
		end)
	elseif event == "LOOT_HISTORY_CLEAR_HISTORY" then
		-- The game starts its history over: which run a drop belongs to is
		-- forgotten; the loot the runs keep stays.
		local unit = R:Store()
		if unit then unit.lootWatch = nil end
	elseif event == "PLAYER_ENTERING_WORLD" then
		Recover()
	end
end)
R.LOOT_EVENTS = { "LOOT_HISTORY_UPDATE_DROP", "LOOT_HISTORY_UPDATE_ENCOUNTER", "LOOT_HISTORY_CLEAR_HISTORY",
	"PLAYER_ENTERING_WORLD" }

local function StartLoot()
	R.lootOn = true
	for _, event in ipairs(R.LOOT_EVENTS) do pcall(lootEvents.RegisterEvent, lootEvents, event) end
	local unit = R:Store()
	if unit then PrunePending(unit) end
	Recover()
end

local function StopLoot()
	R.lootOn = nil
	lootEvents:UnregisterAllEvents()
	wipe(encounterQueued)
end

-- A run's drops, readable (R:Loot). Names are companion keys; key is nil
-- for you (me) and when the game did not show the name.
local function ReadRoll(unit, packed)
	if type(packed) ~= "string" then return nil end
	local name, state, roll, class, flags = packed:match("^([^:]*):([^:]*):([^:]*):([^:]*):(.*)$")
	if not name then return nil end
	return { key = unit.strings[tonumber(name) or 0], state = tonumber(state), roll = tonumber(roll),
		class = class ~= "" and class or nil, me = flags:find("m", 1, true) ~= nil, won = flags:find("w", 1, true) ~= nil }
end
R.ReadRoll = ReadRoll

function R:Loot(run, charKey)
	local unit = self:Store(charKey)
	local out = {}
	if not (unit and type(run) == "table" and type(run.loot) == "table") then return out, 0 end
	for _, drop in ipairs(run.loot) do
		if type(drop) == "table" then
			local rolls = {}
			for _, packed in ipairs(type(drop.r) == "table" and drop.r or {}) do
				rolls[#rolls + 1] = ReadRoll(unit, packed)
			end
			out[#out + 1] = { item = drop.i and unit.strings[drop.i] or nil, t = tonumber(drop.t),
				key = drop.w and unit.strings[drop.w] or nil, me = drop.wm == true, pass = drop.pass == true, rolls = rolls }
		end
	end
	return out, tonumber(run.lootMore) or 0
end

---------------------------------------------------------------------------
-- Imported journals: their dungeon history (when and how long, no
-- members) becomes runs tagged with the import, so Undo of that import
-- takes exactly those runs out again. A run already here (same time and
-- place) is not added twice.
---------------------------------------------------------------------------
function R:ImportHistory(charKey, dungeons, at)
	if type(dungeons) ~= "table" then return 0 end
	local unit = self:Store(charKey, true)
	if not unit then return 0 end
	local have = {}
	for _, run in ipairs(unit.list) do have[tostring(run.t) .. "\31" .. tostring(Str(unit, run.inst))] = true end
	local found = {}
	for name, info in pairs(dungeons) do
		local history = type(name) == "string" and type(info) == "table" and type(info.history) == "table" and info.history or {}
		for _, entry in ipairs(history) do
			local t = type(entry) == "table" and tonumber(entry.t)
			if t and not have[tostring(t) .. "\31" .. name] then
				have[tostring(t) .. "\31" .. name] = true
				local secs = tonumber(entry.secs)
				found[#found + 1] = { t = t, leave = secs and secs > 0 and (t + secs) or nil, instance = name, kind = "party",
					level = tonumber(entry.level), imp = at }
			end
		end
	end
	table.sort(found, function(a, b) return a.t < b.t end)
	for _, run in ipairs(found) do Write(unit, charKey or E.charKey, run, nil) end
	if found[1] then
		unit.idx = nil
		Fill(unit)
	end
	return #found
end

function R:RemoveImported(charKey, at)
	local unit = self:Store(charKey)
	if not (unit and at) then return 0 end
	local removed = 0
	for index = #unit.list, 1, -1 do
		if unit.list[index].imp == at then
			tremove(unit.list, index)
			removed = removed + 1
		end
	end
	if removed > 0 then
		Bump(unit)
		unit.idx = nil
		Fill(unit)
	end
	return removed
end

---------------------------------------------------------------------------
-- Deleting one run or one name, and Undo (the journal's trash)
---------------------------------------------------------------------------
local function OwnJournal()
	return S.Own and S.Own() or nil
end

-- After a change that moved runs in the list: the index is rebuilt and
-- each companion named knows its newest run again.
local function Reindex(unit, keys)
	local idx = R:Index(nil, true)
	local fellows = Fellows()
	for key in pairs(keys or {}) do
		local fellow = fellows and fellows[key]
		if type(fellow) == "table" then
			local places = idx and idx.with[key]
			local newest = places and places[#places] and unit.list[places[#places]]
			fellow.lastRun = newest and newest.id or nil
		end
	end
end

function R:Delete(id)
	if InCombatLockdown() then return nil, L["This can be done out of combat only."] end
	local unit, rec = self:Store(), OwnJournal()
	if not (unit and rec) then return nil end
	local run, index = self:Find(id)
	if not run then return nil end
	tremove(unit.list, index)
	local keys, fellows = {}, rec.fellows
	for _, key in ipairs(MemberKeys(unit, run)) do
		if not keys[key] then
			keys[key] = true
			CountRun(fellows, key, run.id, -1)
		end
	end
	Bump(unit)
	Reindex(unit, keys)
	local trashId = S.TrashItem(rec, "run", { charKey = E.charKey, run = run })
	J:Changed("runs")
	A:MarkDirty("runs")
	return trashId
end

A:AddRestorer("run", function(rec, data)
	local unit = R:Store(type(data) == "table" and data.charKey or nil)
	local run = type(data) == "table" and data.run
	if not (unit and type(run) == "table") then return end
	local _, position = Locate(unit.list, run.id)
	if not position then return end   -- already back
	-- A run deleted before version 3 comes back packed (the same run).
	PackRun(run)
	tinsert(unit.list, position, run)
	local keys = {}
	for _, key in ipairs(MemberKeys(unit, run)) do
		if not keys[key] then
			keys[key] = true
			CountRun(rec.fellows, key, run.id, 1)
		end
	end
	Bump(unit)
	Reindex(unit, keys)
	J:Changed("runs")
	A:MarkDirty("runs")
end)

-- One name, from every run and from the journal's companions: the runs,
-- the other members and every other row stay.
function R:DeletePerson(key)
	if InCombatLockdown() then return nil, L["This can be done out of combat only."] end
	local unit, rec = self:Store(), OwnJournal()
	if not (unit and rec and type(key) == "string") then return nil end
	local idx = self:Index(nil, true)
	local item = { charKey = E.charKey, key = key, members = {}, quests = {}, runExtras = {}, loot = {} }
	local places = {}
	for _, index in ipairs(idx and idx.with[key] or {}) do
		places[index] = true
		local run = unit.list[index]
		local with, taken = RunMembers(run), false
		for position = #with, 1, -1 do
			if Str(unit, with[position].n) == key then
				item.members[#item.members + 1] = { run = run.id, position = position, entry = tremove(with, position) }
				taken = true
			end
		end
		if taken then SetMembers(run, with) end
	end
	-- The name also leaves the loot of those runs: as a winner and its rolls.
	for _, index in ipairs(idx and idx.won[key] or {}) do places[index] = true end
	local nameId = S.StringId(unit, key)
	local order = {}
	for index in pairs(places) do order[#order + 1] = index end
	table.sort(order)
	for _, index in ipairs(nameId and order or {}) do
		local run = unit.list[index]
		for position, drop in ipairs(type(run.loot) == "table" and run.loot or {}) do
			if type(drop) == "table" then
				if drop.w == nameId then
					item.loot[#item.loot + 1] = { run = run.id, position = position, w = nameId }
					drop.w = nil
				end
				local rolls = type(drop.r) == "table" and drop.r or {}
				for place = #rolls, 1, -1 do
					local packed = rolls[place]
					if type(packed) == "string" and tonumber(packed:match("^([^:]*)")) == nameId then
						item.loot[#item.loot + 1] = { run = run.id, position = position, roll = place, packed = tremove(rolls, place) }
					end
				end
			end
		end
	end
	if type(rec.fellows) == "table" and rec.fellows[key] ~= nil then
		item.fellow = rec.fellows[key]
		rec.fellows[key] = nil
	end
	for questID, start in pairs(type(rec.questStart) == "table" and rec.questStart or {}) do
		if type(start) == "table" and type(start.with) == "table" and start.with[key] ~= nil then
			item.quests[#item.quests + 1] = { id = questID, value = start.with[key] }
			start.with[key] = nil
		end
	end
	for runID, extras in pairs(type(rec.runExtras) == "table" and rec.runExtras or {}) do
		if type(extras) == "table" and type(extras.with) == "table" and extras.with[key] ~= nil then
			item.runExtras[#item.runExtras + 1] = { id = runID, value = extras.with[key] }
			extras.with[key] = nil
		end
	end
	if not (item.members[1] or item.fellow or item.quests[1] or item.runExtras[1] or item.loot[1]) then return nil end
	Bump(unit)
	Reindex(unit)
	S.Bump(rec)
	local trashId = S.TrashItem(rec, "person", item)
	J:Changed("runs")
	J:Changed("fellowship")
	A:MarkDirty("runs")
	return trashId
end

A:AddRestorer("person", function(rec, item)
	if type(item) ~= "table" or type(item.key) ~= "string" then return end
	local unit = R:Store(item.charKey)
	if unit then
		-- Back in the order they were taken out (last place first).
		for position = #item.members, 1, -1 do
			local taken = item.members[position]
			local index = Locate(unit.list, taken.run)
			local run = index and unit.list[index]
			if run and type(taken.entry) == "table" then
				local with = RunMembers(run)
				tinsert(with, math.min(taken.position, #with + 1), taken.entry)
				SetMembers(run, with)
			end
		end
		local loot = type(item.loot) == "table" and item.loot or {}
		for position = #loot, 1, -1 do
			local taken = loot[position]
			local index = Locate(unit.list, taken.run)
			local run = index and unit.list[index]
			local drop = run and type(run.loot) == "table" and run.loot[taken.position]
			if type(drop) == "table" then
				if taken.w then drop.w = taken.w end
				if taken.packed then
					drop.r = type(drop.r) == "table" and drop.r or {}
					tinsert(drop.r, math.min(taken.roll, #drop.r + 1), taken.packed)
				end
			end
		end
		Bump(unit)
	end
	if item.fellow ~= nil then rec.fellows[item.key] = item.fellow end
	for _, quest in ipairs(item.quests or {}) do
		local start = rec.questStart[quest.id]
		if type(start) == "table" then
			if type(start.with) ~= "table" then start.with = {} end
			start.with[item.key] = quest.value
		end
	end
	for _, extra in ipairs(item.runExtras or {}) do
		local extras = rec.runExtras[extra.id]
		if type(extras) == "table" then
			if type(extras.with) ~= "table" then extras.with = {} end
			extras.with[item.key] = extra.value
		end
	end
	if unit then Reindex(unit) end
	J:Changed("runs")
	J:Changed("fellowship")
	A:MarkDirty("runs")
end)

local function RunTitle(run)
	local unit = R:Store()
	local name = unit and Str(unit, run.inst) or "?"
	return ("%s, %s"):format(name, E:ShortDate(run.t or 0))
end

function R:AskDelete(id)
	local run = self:Find(id)
	if not run then return nil end
	return E:ShowConfirm({ key = "ELDOUI_JOURNAL_RUN_DELETE", title = L["Delete this run?"],
		text = RunTitle(run) .. "\n\n" .. L["The run leaves your journal; everything else stays. Undo brings it back for 7 days."],
		accept = L["Delete"], danger = true,
		onAccept = function()
			local trashId, err = R:Delete(id)
			if not trashId and err then E:Print(err) end
		end })
end

function R:AskDeletePerson(key)
	if type(key) ~= "string" then return nil end
	return E:ShowConfirm({ key = "ELDOUI_JOURNAL_PERSON_DELETE", title = L["Forget this name?"],
		text = key .. "\n\n" .. L["The name leaves every run and your companions; the runs and everyone else stay. Undo brings it back for 7 days."],
		accept = L["Forget"], danger = true,
		onAccept = function()
			local trashId, err = R:DeletePerson(key)
			if not trashId and err then E:Print(err) end
		end })
end

---------------------------------------------------------------------------
-- Codes, backups and restore ("!EUJR1!")
---------------------------------------------------------------------------
local function Copy(value, depth)
	if E:IsSecret(value) then return nil end
	local kind = type(value)
	if kind == "string" or kind == "number" or kind == "boolean" then return value end
	if kind ~= "table" or (depth or 0) > 12 then return nil end
	local out = {}
	for key, item in pairs(value) do
		local keyKind = type(key)
		if (keyKind == "string" or keyKind == "number") and not E:IsSecret(key) then out[key] = Copy(item, (depth or 0) + 1) end
	end
	return out
end
R.Copy = function(value) return Copy(value) end

-- The store as plain data, without its index (rebuilt from the list),
-- without the drops the game is still rolling (they belong to this PC's
-- session) and without the packing mark (the store that reads it in
-- packs what it needs).
local SKIP = { idx = true, lootWatch = true, pk = true }
local function Snapshot(unit)
	local out = {}
	for key, value in pairs(unit) do
		if not SKIP[key] then out[key] = Copy(value) end
	end
	return out
end
R.Snapshot = Snapshot

local function Who(charKey)
	local B = A.Backup
	return B and B.Who and B.Who(charKey) or {}
end

local function CodeOf(unit, charKey)
	if not (unit and type(unit.list) == "table" and unit.list[1]) then return nil, L["There are no runs to back up yet."] end
	return E:EncodeShareData("journalRuns", { at = Now(), charKey = charKey or E.charKey, who = Who(charKey), runs = Snapshot(unit) })
end

function R:Code(charKey)
	return CodeOf(self:Store(charKey), charKey)
end

local function Valid(runs)
	return type(runs) == "table" and type(runs.list) == "table" and type(runs.strings) == "table"
end

function R:Read(text)
	if type(text) ~= "string" or E:IsSecret(text) or strtrim(text) == "" then return nil, L["Nothing to read. Paste a runs code first."] end
	text = strtrim(text)
	if text:sub(1, #R.PREFIX) ~= R.PREFIX then return nil, L["That is not a runs code. A runs code starts with !EUJR1!."] end
	local kind, data = E:DecodeShareData(text)
	if not kind then return nil, (L["The code is incomplete or damaged (%s). Copy all of it and paste it again."]):format(tostring(data)) end
	if kind ~= "journalRuns" or type(data) ~= "table" or not Valid(data.runs) then
		return nil, L["The code is incomplete or damaged. Copy all of it and paste it again."]
	end
	return data
end

local function BackupList(charKey, create)
	if type(EldoUIDB) ~= "table" then return nil end
	local all = EldoUIDB.journalRunsBackups
	if type(all) ~= "table" then
		if not create then return nil end
		all = E:KeepInNewTable(all, "journalRunsBackups")
		EldoUIDB.journalRunsBackups = all
	end
	charKey = charKey or E.charKey
	if type(all[charKey]) ~= "table" then
		if not create then return nil end
		all[charKey] = {}
	end
	return all[charKey]
end

function R:Backups(charKey)
	return BackupList(charKey) or {}
end

-- A new backup goes first. The newest "before update" copy has a slot of
-- its own: later restores and imports never push it out.
local function AddBackup(list, entry)
	tinsert(list, 1, entry)
	local reserved = E:ReservedJournalBackup(list)
	local keep = R.BACKUP_KEEP + (reserved and 1 or 0)
	local index = #list
	while #list > keep and index >= 1 do
		if list[index] ~= reserved then tremove(list, index) end
		index = index - 1
	end
end

local function BackupJobKey(charKey)
	return "runsbackup:" .. tostring(charKey or E.charKey)
end

-- The "before update" backup of a long store, written by a job in slices.
-- It is queued ahead of the packing job and jobs run in turn, so the runs
-- are packed only once the backup holds them as they were. Until then the
-- entry is marked `pending`.
local function QueueBackup(unit, entry, charKey)
	local B = A.Backup
	if not (B and B.Slicer and B.CopyRecordSliced) then return false end
	return A:RunJob(BackupJobKey(charKey), function()
		local yield = B.Slicer(B.SLICE)
		local runs = B.CopyRecordSliced(unit, yield, SKIP)
		runs.v = entry.v
		local code = E:EncodeShareData("journalRuns", { at = entry.at, charKey = charKey or E.charKey, who = Who(charKey), runs = runs }, yield)
		if type(code) ~= "string" then error("the runs backup code could not be written") end
		entry.data, entry.size, entry.pending = code, #code, nil
	end)
end

-- A "before update" backup a reload left unwritten is written before the
-- runs are packed. true while one is waiting for its job. One that lost
-- its runs (they were packed or put back meanwhile) holds nothing and goes.
ResumeBackup = function(unit, charKey)
	local list = BackupList(charKey)
	local waiting = false
	for index = #(list or {}), 1, -1 do
		local entry = list[index]
		if type(entry) == "table" and entry.pending and entry.data == nil then
			if not (unit and unit.pk) then
				tremove(list, index)
			elseif A:JobRunning(BackupJobKey(charKey)) or QueueBackup(unit, entry, charKey) then
				waiting = true
			end
		end
	end
	return waiting
end

-- A backup of a character's runs now (nil when there are none); the copy
-- before an update of a long store is written by a job (QueueBackup).
local function TakeBackupOf(unit, reason, charKey)
	if not (unit and type(unit.list) == "table" and unit.list[1]) then return nil end
	if reason == "before update" and #unit.list > R.SYNC_PACK then
		local list = BackupList(charKey, true)
		if not list then return nil end
		local entry = { at = Now(), reason = reason, runs = #unit.list, v = unit.v, pending = true }
		if QueueBackup(unit, entry, charKey) then
			AddBackup(list, entry)
			return entry
		end
	end
	local code = CodeOf(unit, charKey)
	if type(code) ~= "string" then return nil end
	local list = BackupList(charKey, true)
	if not list then return nil end
	local entry = { at = Now(), reason = reason or "hand", runs = #unit.list, size = #code, data = code, v = unit.v }
	AddBackup(list, entry)
	return entry
end
R.TakeBackupOf = TakeBackupOf

-- Forget: the runs leave the account file after one backup of them is
-- kept with the character's run backups (the Saved data page lists them).
-- Runs that could not be backed up stay.
E:RegisterCharacterForget(function(db, key)
	local root = type(db.journalRuns) == "table" and db.journalRuns
	local unit = root and root[key]
	if type(unit) ~= "table" then return end
	if type(unit.list) == "table" and unit.list[1] and not TakeBackupOf(unit, "before forgetting", key) then return end
	root[key] = nil
end)

function R:TakeBackup(reason, charKey)
	return TakeBackupOf(self:Store(charKey), reason, charKey)
end

-- What makes two runs the same run: when, where and who.
local function SameKey(unit, run)
	local names = {}
	for _, member in ipairs(RunMembers(run)) do
		names[#names + 1] = Str(unit, member.n) or "?"
	end
	table.sort(names)
	return table.concat({ tostring(run.t), tostring(Str(unit, run.inst)), table.concat(names, "\30") }, "\31")
end

-- A run of another store (its own strings) in this one's numbers, packed
-- (a code from before version 3 has its members as tables).
local function Remap(dst, srcUnit, run)
	local copy = Copy(run)
	copy.inst = run.inst and Intern(dst, Str(srcUnit, run.inst)) or nil
	local facts, with = RunFacts(copy), RunMembers(copy)
	facts.wing = facts.wing and Intern(dst, Str(srcUnit, facts.wing)) or nil
	for _, member in ipairs(with) do
		member.n = member.n and Intern(dst, Str(srcUnit, member.n)) or nil
		member.r = member.r and Intern(dst, Str(srcUnit, member.r)) or nil
		member.g = member.g and Intern(dst, Str(srcUnit, member.g)) or nil
	end
	SetFacts(copy, facts)
	SetMembers(copy, with)
	for _, drop in ipairs(type(copy.loot) == "table" and copy.loot or {}) do
		if type(drop) == "table" then
			drop.i = drop.i and Intern(dst, Str(srcUnit, drop.i)) or nil
			drop.w = drop.w and Intern(dst, Str(srcUnit, drop.w)) or nil
			for place, packed in ipairs(type(drop.r) == "table" and drop.r or {}) do
				local name, rest = tostring(packed):match("^([^:]*)(:.*)$")
				if name then
					local id = name ~= "" and Intern(dst, Str(srcUnit, tonumber(name))) or nil
					drop.r[place] = (id and tostring(id) or "") .. rest
				end
			end
		end
	end
	return copy
end

-- Put runs from a code or a backup in: "replace" (exactly as they were) or
-- "merge" (the runs this store lacks, never one twice). The runs as they
-- are now are backed up first. Out of combat only.
function R:Restore(data, mode, charKey)
	if InCombatLockdown() then return false, L["This can be done out of combat only."] end
	local runs = type(data) == "table" and data.runs
	if not Valid(runs) then return false, L["The code is incomplete or damaged. Copy all of it and paste it again."] end
	charKey = charKey or E.charKey
	local unit = self:Store(charKey, true)
	local root = Root(true)
	if not (unit and root) then return false, L["The journal is not ready yet. Try again in a moment."] end
	self:TakeBackup("before restoring", charKey)
	if mode == "replace" then
		local fresh = Fill(Copy(runs))
		fresh.idx = nil
		Fill(fresh)
		fresh.rev = (unit.rev or 0) + 1
		-- Runs from a code made before version 3 are packed like the update
		-- does (they read the same meanwhile).
		fresh.pk = 1
		migrated[fresh] = true
		root[charKey] = fresh
		E:SetHold(E:SavedUnitId("journalRuns", charKey), R.SCHEMA)
		self:Index(charKey, true)
		StartPack(fresh, charKey)
		J:Changed("runs")
		A:MarkDirty("runs")
		return true, { runs = #fresh.list }
	end
	local have, srcs = {}, {}
	for _, run in ipairs(unit.list) do
		have[SameKey(unit, run)] = true
		if run.src then srcs[run.src] = true end
	end
	local added = {}
	for _, run in ipairs(runs.list) do
		if type(run) == "table" and not have[SameKey(runs, run)] then
			local copy = Remap(unit, runs, run)
			if copy.src and srcs[copy.src] then copy.src = nil end
			have[SameKey(runs, run)] = true
			added[#added + 1] = copy
		end
	end
	if added[1] then
		-- New ids after the store's own, in time order.
		table.sort(added, function(a, b) return (tonumber(a.t) or 0) < (tonumber(b.t) or 0) end)
		local fellows = charKey == E.charKey and Fellows(charKey) or nil
		for _, copy in ipairs(added) do
			unit.seq = unit.seq + 1
			copy.id = unit.seq
			unit.list[#unit.list + 1] = copy
			for _, key in ipairs(MemberKeys(unit, copy)) do CountRun(fellows, key, copy.id, 1) end
		end
		Bump(unit)
		self:Index(charKey)
	end
	J:Changed("runs")
	A:MarkDirty("runs")
	return true, { runs = #added }
end

local function Count(list)
	return type(list) == "table" and #list or 0
end

E:RegisterShareKind("journalRuns", {
	prefix = R.PREFIX,
	title = "Journal runs backup",
	version = 1,
	describe = function(data)
		local runs = type(data.runs) == "table" and data.runs or {}
		local who = type(data.who) == "table" and data.who or {}
		local count = Count(runs.list)
		return {
			(L["The runs of %s, saved %s."]):format(tostring(who.name or "?"), tonumber(data.at) and E:ShortDate(data.at) or "?"),
			E:Plural(count, "%s run", "%s runs"):format(BreakUpLargeNumbers(count)),
			L["Accept merges them into this character's runs: nothing is lost, and a backup is taken first."],
		}
	end,
	apply = function(data)
		local ok, result = R:Restore(data, "merge")
		if ok then
			E:Print(E:Plural(result.runs, "%s run added to your journal.", "%s runs added to your journal."):format(result.runs))
		else
			E:Print(tostring(result))
		end
	end,
})

-- Restore: Merge or Replace, asked first.
local function AskRestore(data, text)
	local function Run(mode)
		local ok, result = R:Restore(data, mode)
		if not ok then
			E:Print((L["Nothing changed: %s"]):format(tostring(result)))
		elseif mode == "replace" then
			E:Print(L["Your runs are back as they were then."])
		else
			E:Print(E:Plural(result.runs, "%s run added to your journal.", "%s runs added to your journal."):format(result.runs))
		end
	end
	return E:ShowConfirm({ key = "ELDOUI_JOURNAL_RUNS_RESTORE", title = L["My Adventure"],
		text = text .. "\n\n" .. L["Merge adds the runs your journal is missing and never adds one twice. Replace puts your runs back exactly as they were then."]
			.. "\n\n" .. L["Your runs as they are now are backed up first either way."],
		accept = L["Merge"], extra = { L["Replace"], function() Run("replace") end },
		onAccept = function() Run("merge") end })
end

function R:AskImportText(text)
	local data, err = self:Read(text)
	if not data then
		E:Print(err)
		return nil, err
	end
	local who = type(data.who) == "table" and data.who or {}
	local count = Count(data.runs.list)
	return AskRestore(data, (L["Load the runs of %s (saved %s) into this character?"]):format(tostring(who.name or "?"),
		tonumber(data.at) and E:ShortDate(data.at) or "?") .. "\n" .. E:Plural(count, "%s run", "%s runs"):format(BreakUpLargeNumbers(count)))
end

local REASONS = E:TranslateValues({
	hand = E.Key("by hand"), ["before restoring"] = E.Key("before restoring"), ["before importing"] = E.Key("before importing"),
	["before clearing"] = E.Key("before clearing"), ["before update"] = E.Key("before an EldoUI update"),
	["before forgetting"] = E.Key("before forgetting"),
})

function R.Describe(entry)
	local count = tonumber(entry.runs) or 0
	return ("%s · %s (%s)"):format(tonumber(entry.at) and E:ShortDate(entry.at) or "?",
		E:Plural(count, "%s run", "%s runs"):format(BreakUpLargeNumbers(count)), REASONS[entry.reason] or tostring(entry.reason or ""))
end

function R:ShowBackupMenu(owner)
	local list = self:Backups()
	if not list[1] then
		E:Print(L["No backup of your runs yet."])
		return false
	end
	E.UIKit.ContextMenu(owner or UIParent, function(_, root)
		root:CreateTitle(L["Backups of your runs"])
		for _, entry in ipairs(list) do
			root:CreateButton(R.Describe(entry), function()
				if entry.pending then
					E:Print(L["This backup is still being written. Try again in a moment."])
					return
				end
				local data, err = R:Read(entry.data)
				if not data then
					E:Print(err)
					return
				end
				AskRestore(data, (L["Restore your runs from %s?"]):format(E:ShortDate(entry.at or 0)))
			end)
		end
	end)
	return true
end

R.Options = {
	{ type = "header", label = "Runs" },
	{ type = "description", label = "Every dungeon and raid run stays in your journal with who was in it. Its own code keeps them safe or moves them to another PC." },
	{ type = "execute", label = "Copy a runs code", desc = "Your runs as one code, to keep or to paste in on another PC. Nothing is sent anywhere.",
		func = function() if A.Export then A.Export:Show("runs") end end },
	{ type = "execute", label = "Paste a runs code", desc = "Loads a runs code (!EUJR1!). You see what it holds, then Merge or Replace.",
		func = function()
			E:ShowPasteBox(L["Paste a runs code"], L["Paste a runs code from EldoUI (!EUJR1!). You see what it holds before anything changes."],
				function(text) R:AskImportText(text) end)
		end },
	{ type = "execute", label = "Restore your runs", desc = "Pick a backup of your runs, then Merge or Replace. Your runs are backed up first.",
		disabled = function() return R:Backups()[1] == nil end, func = function() R:ShowBackupMenu() end },
}

A:AddPart("runsoptions", {
	order = 91,
	init = function()
		if A.AddOptionRows then A:AddOptionRows("safe", R.Options) end
	end,
})

---------------------------------------------------------------------------
-- Clearing the whole journal clears its runs too, after a backup. The
-- Instances log's runs up to now are not copied in again.
---------------------------------------------------------------------------
local clear = J.Clear
function J:Clear(charKey)
	if charKey == nil or charKey == E.charKey then
		local unit = R:Store()
		if unit and unit.list[1] then
			R:TakeBackup("before clearing")
			-- A new table, so the name lookups of the old one let go.
			local last = unit.lastSrc
			unit = Fill({ v = R.SCHEMA })
			unit.lastSrc = last
			migrated[unit] = true
			Root(true)[E.charKey] = unit
			local M = E.Instances
			local ok, runs = false, nil
			if M and M.RunsFor then ok, runs = pcall(M.RunsFor, M, E.charKey) end
			if ok and type(runs) == "table" and type(runs[1]) == "table" and tonumber(runs[1].id) then
				unit.lastSrc = math.max(unit.lastSrc, runs[1].id)
			end
		end
	end
	return clear(self, charKey)
end

---------------------------------------------------------------------------
-- Part: copy what the log has, then follow every closed run
---------------------------------------------------------------------------
local function OtherCharacters()
	local root = S.Root()
	local keys = {}
	for key in pairs(root or {}) do
		if type(key) == "string" and key ~= E.charKey then keys[#keys + 1] = key end
	end
	table.sort(keys)
	return keys
end

A:AddPart("runs", {
	order = 13,
	start = function()
		local M = E.Instances
		if M and M.RegisterCallback then M:RegisterCallback("RunClosed", "journal", OnRunClosed) end
		if J:Recording() then R:CatchUp() end
		-- Packing the update left unfinished (the journal was turned off).
		StartPack(R:Store(), E.charKey)
		StartLoot()
		-- Your other characters' runs the log still has, in slices.
		A:RunJob("runs:others", function()
			for _, key in ipairs(OtherCharacters()) do
				R:Store(key, true)
				A.JobYield()
			end
		end)
	end,
	stop = function()
		local M = E.Instances
		if M and M.UnregisterCallback then M:UnregisterCallback("RunClosed", "journal") end
		StopLoot()
	end,
})
