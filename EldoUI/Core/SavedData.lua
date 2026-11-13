-- EldoUI Saved data: the Saved data options page and the words for
-- /eui data.
--
-- What the page shows comes from Core/Database.lua:
--   * Backups: the copies taken before an update changed a profile, the
--     journal or another saved part, each with Restore. A part put back
--     is held as it is; "Let go" lets the next update change it again.
--     What a restore replaced is listed under "Copies from before a
--     restore", where Restore undoes it. The journal of a character the
--     Alts window forgot is backed up first and listed here with Restore.
--   * Set aside: values the load checks could not read, with Put back;
--     journals saved under a character's name that belong to another
--     character (kept); leftover saved tables nothing reads any more, with
--     a Remove the player chooses.
--   * Checks: what each saved part's check found at this login.
-- Nothing on this page deletes data on its own. Restore, Put back and
-- the undo of a restore keep what they replace.
local _, E = ...
local L = E.L

local SD = {}
E.SavedData = SD

-- Rows of each list the page has room for; more are counted.
SD.SHOWN = { backups = 12, restored = 8, forgotten = 8, holds = 8, values = 20, orphans = 10, legacy = 3, report = 16 }

-- Names of the saved parts, as the player knows them: each store's
-- `title` in the saved data registry (Core/Database.lua and the modules
-- that register their stores).
-- The reasons a value was set aside (Core/Database.lua): L["Expected a table."],
-- L["Expected a number."], L["Expected a text."], L["Expected a creature entry."],
-- L["An older shape of this list."], L["An older copy of this contact."],
-- L["Set aside when an older value was put back."],
-- L["Not the kind of value expected here."]

-- "Profile EldoUI 1440p", "Journal of Name - Realm", "Instance log".
function SD.PartName(name, key)
	if name == "profile" then return (L["Profile %s"]):format(tostring(key)) end
	local info = E:StoreInfo(name)
	local title = info and info.title
	if title and title:find("%s", 1, true) then return (L[title]):format(tostring(key)) end
	if title then return L[title] end
	if key ~= nil then return ("%s (%s)"):format(tostring(name), tostring(key)) end
	return tostring(name)
end

-- The part an id names ("profile:Default", "journal:Name - Realm").
function SD.PartOfId(id)
	local name, key = tostring(id):match("^([^:]+):(.+)$")
	if name then return SD.PartName(name, key) end
	return SD.PartName(id)
end

local function When(at)
	return tonumber(at) and E:ShortDate(at) or L["an unknown date"]
end

local function Count(t)
	local n = 0
	for _ in pairs(type(t) == "table" and t or {}) do n = n + 1 end
	return n
end

-- A short look at a value that was set aside.
function SD.Preview(value)
	local kind = type(value)
	if kind == "table" then
		local n = Count(value)
		return E:Plural(n, "a list with %d entry", "a list with %d entries"):format(n)
	end
	if kind == "string" then
		if E:IsSecret(value) then return "?" end
		local text = value:gsub("|", "||")
		if #text > 40 then text = text:sub(1, 37) .. "..." end
		return ("\"%s\""):format(text)
	end
	return tostring(value)
end

---------------------------------------------------------------------------
-- The lists
---------------------------------------------------------------------------
function SD.Backups() return E:BackupList() end
function SD.Holds() return E:HeldParts() end
function SD.Values() return E:QuarantinedValues() end
-- Leftover saved tables the player may remove (a whole saved table that
-- nothing reads any more).
function SD.Legacy()
	local list = {}
	for _, entry in ipairs(E:LegacyStores()) do
		if entry.removable then list[#list + 1] = entry end
	end
	return list
end

-- Journals saved under a character's name that belong to another
-- character: kept (Adventure/Store.lua).
function SD.Orphans()
	local cache = type(EldoUIDB) == "table" and EldoUIDB.journalCache
	local list = {}
	for _, entry in ipairs(type(cache) == "table" and type(cache.orphans) == "table" and cache.orphans or {}) do
		if type(entry) == "table" then list[#list + 1] = entry end
	end
	return list
end

-- What a restore replaced: { id, at, eldoui }, newest first. The part as
-- it was just before the restore; Restore here puts it back.
function SD.Restored()
	local backups = type(EldoUIDB) == "table" and EldoUIDB.backups
	local list = {}
	for id, entry in pairs(type(backups) == "table" and type(backups.restored) == "table" and backups.restored or {}) do
		if type(entry) == "table" and type(entry.data) == "table" then
			list[#list + 1] = { id = id, at = entry.at, eldoui = entry.eldoui }
		end
	end
	table.sort(list, function(a, b)
		if (a.at or 0) ~= (b.at or 0) then return (a.at or 0) > (b.at or 0) end
		return tostring(a.id) < tostring(b.id)
	end)
	return list
end

-- Journals of characters the Alts window forgot: the backup taken before
-- the journal left (Adventure/Backup.lua), until it is put back.
function SD.Forgotten()
	local B = E.Adventure and E.Adventure.Backup
	return B and B.ForgottenList and B:ForgottenList() or {}
end

function SD.BackupText(entry)
	local part = SD.PartName(entry.kind, entry.key)
	if entry.eldoui then
		return (L["%s, kept %s before the update to EldoUI %s"]):format(part, When(entry.at), tostring(entry.eldoui))
	end
	return (L["%s, kept %s before an update"]):format(part, When(entry.at))
end

function SD.ValueText(entry)
	return (L["%s, %s: %s, set aside %s (%s)"]):format(SD.PartOfId(entry.id), tostring(entry.path), SD.Preview(entry.value),
		When(entry.at), L[tostring(entry.why or "Not the kind of value expected here.")])
end

function SD.OrphanText(entry)
	local journal = type(entry.journal) == "table" and entry.journal or {}
	local rows = type(journal.events) == "table" and #journal.events or 0
	return (L["%s, kept %s"]):format(tostring(entry.key or "?"), When(entry.at)) .. " · "
		.. E:Plural(rows, "%s moment", "%s moments"):format(BreakUpLargeNumbers(rows))
end

function SD.LegacyText(entry)
	local kb = math.max(1, math.floor((entry.bytes or 0) / 1024 + 0.5))
	return (L["%s: about %d KB, kept until you remove it"]):format(SD.PartName(entry.name), kb)
end

function SD.HoldText(entry)
	return (L["%s, held since %s"]):format(SD.PartOfId(entry.id), When(entry.at))
end

function SD.RestoredText(entry)
	return (L["%s, as it was just before you restored it %s"]):format(SD.PartOfId(entry.id), When(entry.at))
end

function SD.ForgottenText(entry)
	local counts = type(entry.counts) == "table" and entry.counts or {}
	local rows = tonumber(counts.rows) or 0
	return (L["%s, kept %s when you forgot the character"]):format(SD.PartName("journal", entry.key), When(entry.at)) .. " · "
		.. E:Plural(rows, "%s moment", "%s moments"):format(BreakUpLargeNumbers(rows))
end

-- The question before a restore: the journal has its own (a restore from
-- this page puts it back exactly, Merge lives in My Adventure).
function SD.ConfirmText(entry)
	if entry.forgotten then
		if SD.HasJournal(entry.key) then
			return (L["Put the journal of %s back? It is merged into the journal the character has now, so nothing from either is lost."])
				:format(tostring(entry.key))
		end
		return (L["Put the journal of %s back exactly as it was when you forgot the character?"]):format(tostring(entry.key))
	end
	if entry.kind == "journal" then
		return (L["Put the journal of %s back exactly as it was before the update? Your journal as it is now is backed up first, but moments written since the update leave it. To add back only what is missing, use Restore a backup with Merge in My Adventure instead."])
			:format(tostring(entry.key))
	end
	return (L["Put back %s as it was before the update? What it holds now is kept as a copy, and updates leave this part alone until you choose Let go on this page."])
		:format(SD.PartName(entry.kind, entry.key))
end

-- Does a character have a journal with something in it now?
function SD.HasJournal(charKey)
	local root = type(EldoUIDB) == "table" and EldoUIDB.journal
	local rec = type(root) == "table" and root[charKey]
	local B = E.Adventure and E.Adventure.Backup
	return type(rec) == "table" and (not (B and B.HasData) or B.HasData(rec))
end

-- One line per saved part whose check found something.
function SD.ReportLines()
	local lines = {}
	local ids = {}
	for id in pairs(E:SavedDataReport()) do ids[#ids + 1] = id end
	table.sort(ids)
	local report = E:SavedDataReport()
	for _, id in ipairs(ids) do
		local r = report[id]
		local parts = {}
		if (r.from or 0) ~= (r.to or 0) then parts[#parts + 1] = (L["updated from version %d to %d"]):format(r.from or 0, r.to or 0) end
		if r.repaired > 0 then parts[#parts + 1] = E:Plural(r.repaired, "%d value repaired", "%d values repaired"):format(r.repaired) end
		if r.quarantined > 0 then parts[#parts + 1] = E:Plural(r.quarantined, "%d value set aside", "%d values set aside"):format(r.quarantined) end
		if r.kept > 0 then parts[#parts + 1] = E:Plural(r.kept, "%d check could not run, the data is kept as it is", "%d checks could not run, the data is kept as it is"):format(r.kept) end
		if r.held then parts[#parts + 1] = L["held as you put it back"] end
		if r.newer then parts[#parts + 1] = L["saved by a newer EldoUI, kept as it is"] end
		if r.failed then parts[#parts + 1] = L["the update could not finish and runs again at your next login"] end
		if #parts > 0 then lines[#lines + 1] = ("%s: %s"):format(SD.PartOfId(id), table.concat(parts, "; ")) end
	end
	return lines
end

---------------------------------------------------------------------------
-- Actions (the page and /eui data)
---------------------------------------------------------------------------
local function Done(ok, err, text)
	if ok then
		E:Print(text)
		if E.RefreshConfig then E:RefreshConfig() end
	else
		E:Print((L["Nothing changed: %s"]):format(tostring(err)))
	end
	return ok
end

function SD.Restore(entry)
	if not entry then return false end
	if entry.forgotten then return SD.RestoreForgotten(entry) end
	local ok, err = E:RestoreBackup(entry.kind, entry.key)
	if entry.kind == "journal" then
		return Done(ok, err, L["Your journal is back as it was before the update. Your journal as it was a moment ago is kept as a backup in My Adventure."])
	end
	return Done(ok, err, (L["%s is back as it was before the update. What it held a moment ago is listed under Copies from before a restore. Type /reload so every part of EldoUI reads it again."])
		:format(SD.PartName(entry.kind, entry.key)))
end

-- The journal of a forgotten character back in place: exactly as it was
-- when the character has none now, else merged into the one it has.
function SD.RestoreForgotten(entry)
	if not entry then return false end
	if InCombatLockdown() then return Done(false, L["Backups can be put back out of combat only."]) end
	local B = E.Adventure and E.Adventure.Backup
	if not (B and B.RestoreForgotten) then return Done(false, L["there is no copy of that any more."]) end
	local ok, err = B:RestoreForgotten(entry.key)
	return Done(ok, err, (L["The journal of %s is back. It is on disk after your next logout or /reload."]):format(tostring(entry.key)))
end

-- Remove a forgotten character's journal for good (the page asks first).
function SD.RemoveForgotten(entry)
	if not entry then return false end
	local B = E.Adventure and E.Adventure.Backup
	if not (B and B.RemoveForgotten) then return Done(false, L["there is no copy of that any more."]) end
	local ok, err = B:RemoveForgotten(entry.key)
	return Done(ok, err, (L["The journal of %s is removed. It leaves your saved file at your next logout or /reload."]):format(tostring(entry.key)))
end

-- Undo a restore: the part goes back to how it was just before it, and
-- what it holds now takes that copy's place (the two swap, nothing is
-- dropped). Out of combat, as a restore.
function SD.UndoRestore(entry)
	if not entry then return false end
	local ok, err = E:UndoRestore(entry.id)
	return Done(ok, err, (L["%s is back as it was just before the restore. What it held a moment ago is kept in its place. Type /reload so every part of EldoUI reads it again."])
		:format(SD.PartOfId(tostring(entry.id))))
end

function SD.Release(entry)
	if not entry then return false end
	local ok = E:ReleaseHold(entry.id)
	return Done(ok, L["it is not held"], (L["%s is no longer held. At your next login or /reload it is brought up to date, and the copy from before stays."])
		:format(SD.PartOfId(entry.id)))
end

function SD.PutBack(entry)
	if not entry then return false end
	local ok, err = E:PutBack(entry.id, entry.path)
	return Done(ok, err, (L["Put back: %s. Type /reload so every part of EldoUI reads it again."]):format(tostring(entry.path)))
end

function SD.RemoveLegacy(entry)
	if not entry then return false end
	local ok = E:RemoveLegacyStore(entry.name)
	return Done(ok, L["it can't be removed here."], (L["Removed: %s. It leaves your saved file at your next logout or /reload."]):format(SD.PartName(entry.name)))
end

---------------------------------------------------------------------------
-- The page
---------------------------------------------------------------------------
local function Item(list, index)
	return function() return list()[index] end
end

-- One row per possible entry, hidden while there is none, with a button
-- per action.
local function Slots(rows, list, count, text, ...)
	local actions = { ... }
	for index = 1, count do
		local item = Item(list, index)
		rows[#rows + 1] = { type = "description", tone = "body", hidden = function() return item() == nil end,
			label = function() local entry = item() return entry and text(entry) or "" end }
		for _, action in ipairs(actions) do
			rows[#rows + 1] = { type = "execute", label = action.label, desc = action.desc, noUndo = true,
				confirm = action.confirm and function() local entry = item() return entry and action.confirm(entry) or "" end,
				confirmAccept = action.accept, confirmDanger = action.danger or false,
				hidden = function() return item() == nil end,
				func = function() action.run(item()) end }
		end
	end
	rows[#rows + 1] = { type = "description", hidden = function() return #list() <= count end,
		label = function()
			local more = #list() - count
			return E:Plural(more, "And %d more.", "And %d more."):format(more)
		end }
end

local function Empty(rows, list, text)
	rows[#rows + 1] = { type = "description", label = text, hidden = function() return #list() > 0 end }
end

function SD.BuildRows()
	local rows = {}
	rows[#rows + 1] = { type = "tab", label = "Backups" }
	rows[#rows + 1] = { type = "description", label = "Before an update changes a saved part, EldoUI keeps a copy of it. Restore puts a copy back and keeps what it replaces." }
	rows[#rows + 1] = { type = "header", label = "Copies from before an update" }
	Empty(rows, SD.Backups, E.Key("No copies yet. EldoUI keeps one the first time an update changes your saved data."))
	Slots(rows, SD.Backups, SD.SHOWN.backups, SD.BackupText, {
		label = "Restore", desc = "Puts this part back as it was before the update. What it holds now is kept as a copy first. Works out of combat. Afterwards updates leave this part alone until you choose Let go below.",
		accept = "Restore", confirm = SD.ConfirmText, run = SD.Restore,
	})
	rows[#rows + 1] = { type = "header", label = "Copies from before a restore" }
	Empty(rows, SD.Restored, E.Key("None. When you restore a copy, what it replaces is kept here."))
	Slots(rows, SD.Restored, SD.SHOWN.restored, SD.RestoredText, {
		label = "Restore", desc = "Puts this part back as it was just before your restore, to undo it. What it holds now is kept in its place.",
		accept = "Restore",
		confirm = function(entry)
			return (L["Undo the restore of %s? It goes back to how it was just before, and what it holds now is kept in its place."]):format(SD.PartOfId(entry.id))
		end,
		run = SD.UndoRestore,
	})
	rows[#rows + 1] = { type = "header", label = "Journals of forgotten characters" }
	rows[#rows + 1] = { type = "description", label = "When you forget a character in the Alts window, its journal is backed up first and kept here until you put it back or remove it." }
	Empty(rows, SD.Forgotten, E.Key("None."))
	Slots(rows, SD.Forgotten, SD.SHOWN.forgotten, SD.ForgottenText, {
		label = "Restore", desc = "Puts this journal back under its character. If the character has a journal again, the two are merged and nothing from either is lost. Works out of combat.",
		accept = "Restore", confirm = SD.ConfirmText, run = SD.RestoreForgotten,
	}, {
		label = "Remove", desc = "Removes this journal from your saved data for good. It can't be undone.",
		accept = "Remove", danger = true, run = SD.RemoveForgotten,
		confirm = function(entry)
			return (L["Remove the journal of %s for good? It can't be put back afterwards."]):format(tostring(entry.key))
		end,
	})
	rows[#rows + 1] = { type = "header", label = "Kept as you put it back" }
	rows[#rows + 1] = { type = "description", label = "Parts you restored stay as you put them back. Updates leave them alone until you choose Let go or a later EldoUI updates that part." }
	Empty(rows, SD.Holds, E.Key("Nothing is held. Every part of your saved data follows EldoUI's updates."))
	Slots(rows, SD.Holds, SD.SHOWN.holds, SD.HoldText, {
		label = "Let go", desc = "At your next login or /reload this part is brought up to date again. The copy from before the update stays.",
		run = SD.Release,
	})

	rows[#rows + 1] = { type = "tab", label = "Set aside" }
	rows[#rows + 1] = { type = "description", label = "A saved value EldoUI can't read is set aside here, never deleted. Put back returns it to its place and sets aside what sits there now." }
	rows[#rows + 1] = { type = "header", label = "Values set aside" }
	Empty(rows, SD.Values, E.Key("Nothing is set aside. Every saved value read as expected."))
	Slots(rows, SD.Values, SD.SHOWN.values, SD.ValueText, {
		label = "Put back", desc = "Returns this value to where it was saved. Whatever is there now is set aside in its place, so nothing is lost. Type /reload afterwards so every part of EldoUI reads it again.",
		run = SD.PutBack,
	})
	rows[#rows + 1] = { type = "header", label = "Journals of another character" }
	rows[#rows + 1] = { type = "description", label = "Journals under your character names that belong to another character, such as one deleted and made again. Kept apart, never mixed in." }
	Empty(rows, SD.Orphans, E.Key("None."))
	Slots(rows, SD.Orphans, SD.SHOWN.orphans, SD.OrphanText)
	rows[#rows + 1] = { type = "header", label = "Leftover data" }
	rows[#rows + 1] = { type = "description", label = "Saved tables from older versions that nothing in EldoUI reads any more. They stay until you remove them." }
	Empty(rows, SD.Legacy, E.Key("None. Nothing older is left in your saved files."))
	Slots(rows, SD.Legacy, SD.SHOWN.legacy, SD.LegacyText, {
		label = "Remove", desc = "Removes this leftover table from your saved files. EldoUI no longer uses it. This can't be undone.",
		accept = "Remove", danger = true,
		confirm = function(entry)
			return (L["Remove %s from your saved files? EldoUI no longer uses it. This can't be undone."]):format(SD.PartName(entry.name))
		end,
		run = SD.RemoveLegacy,
	})

	rows[#rows + 1] = { type = "tab", label = "Checks" }
	rows[#rows + 1] = { type = "description", label = "What EldoUI found in your saved data at this login. Repaired means a small fix that loses nothing, such as a gap in a list closed up." }
	rows[#rows + 1] = { type = "header", label = "This login" }
	Empty(rows, SD.ReportLines, E.Key("Every saved part read as expected."))
	Slots(rows, SD.ReportLines, SD.SHOWN.report, function(line) return line end)
	rows[#rows + 1] = { type = "description", label = function()
		local schema = type(EldoUIDB) == "table" and EldoUIDB.schema
		local version = type(schema) == "table" and tonumber(schema.version) or 0
		return (L["Saved data version %d, written by EldoUI %s."]):format(version, tostring(type(schema) == "table" and schema.eldoui or E.version))
	end }
	return rows
end

-- The Saved data page.
E:RegisterEvent("PLAYER_LOGIN", function()
	if not E.RegisterConfigPage then return end
	local page = E:RegisterConfigPage("saveddata", "Saved data", nil, function() return SD end, function() end, 60)
	if page then
		page.build = SD.BuildRows
		page.desc = L["Your safety net: copies kept before each update, values set aside instead of deleted, and what EldoUI checked at this login."]
	end
end, SD, "modules")

---------------------------------------------------------------------------
-- /eui data (Core/Commands.lua): the same lists in chat.
---------------------------------------------------------------------------
function SD.PrintSummary()
	local backups, values, orphans = #SD.Backups(), #SD.Values(), #SD.Orphans()
	E:Print(E:Plural(backups, "%d copy from before an update", "%d copies from before an update"):format(backups) .. ", "
		.. E:Plural(values, "%d value set aside", "%d values set aside"):format(values) .. ", "
		.. E:Plural(orphans, "%d journal of another character", "%d journals of another character"):format(orphans) .. ".")
end

local function Command(word, kind, key)
	local name = key ~= nil and (" " .. tostring(key)) or ""
	return E:Highlight(("/eui data %s %s%s"):format(word, tostring(kind), name))
end

-- The copies kept before an update, the journals of forgotten characters
-- and the parts held as they were put back, each with its command.
function SD.PrintBackups()
	local list = SD.Backups()
	if not list[1] then
		E:Print(L["No copies yet. EldoUI keeps one the first time an update changes your saved data."])
	else
		E:Print(L["Copies from before an update:"])
		for _, entry in ipairs(list) do
			print(("  %s  %s"):format(SD.BackupText(entry), Command("restore", entry.kind, entry.key)))
		end
	end
	local forgotten = SD.Forgotten()
	if forgotten[1] then
		E:Print(L["Journals of forgotten characters:"])
		for _, entry in ipairs(forgotten) do
			print(("  %s  %s"):format(SD.ForgottenText(entry), Command("restore", "journal", entry.key)))
		end
	end
	local holds = SD.Holds()
	if holds[1] then
		E:Print(L["Kept as you put it back:"])
		for _, entry in ipairs(holds) do
			local kind, key = tostring(entry.id):match("^([^:]+):(.+)$")
			print(("  %s  %s"):format(SD.HoldText(entry), Command("follow", kind or entry.id, key)))
		end
	end
end

-- The backup a "/eui data restore <kind> [<key>]" names: a copy from
-- before an update first, then the journal of a forgotten character.
function SD.FindBackup(kind, key)
	kind = tostring(kind or ""):lower()
	key = key ~= nil and strtrim(tostring(key)) or ""
	local function Match(entry)
		return tostring(entry.kind):lower() == kind and (key == "" or tostring(entry.key or ""):lower() == key:lower())
	end
	for _, entry in ipairs(SD.Backups()) do
		if Match(entry) then return entry end
	end
	for _, entry in ipairs(SD.Forgotten()) do
		if Match(entry) then return entry end
	end
end

function SD.FindHold(kind, key)
	kind = tostring(kind or ""):lower()
	key = key ~= nil and strtrim(tostring(key)) or ""
	local want = key ~= "" and (kind .. ":" .. key:lower()) or kind
	for _, entry in ipairs(SD.Holds()) do
		local id = tostring(entry.id):lower()
		if id == want or (key == "" and id:match("^([^:]+)") == kind) then return entry end
	end
end
