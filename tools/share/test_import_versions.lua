-- Offline test for share strings from other EldoUI versions (review F07).
-- Run from the repository root:
--   lua5.1 tools/share/test_import_versions.lua
-- It cuts the real functions out of EldoUI/Core/Share.lua and
-- EldoUI/Core/Database.lua (between fixed markers, so a renamed function
-- makes the test fail instead of testing a stale copy) and runs them with
-- small stand-ins for the rest of EldoUI:
--   * Stamps: which migration stamps of a string count;
--   * MigratePart: a part of a profile (module, general, positions) gets the
--     default changes and the migrations it missed, keyed migrations only
--     with the sender's stamps, and the receiver's own settings stay as
--     they are.
-- Since EldoUI 0.7.3000 the message for a string from a newer or an
-- unreadable EldoUI is EldoUI's own (PayloadAdmit in Share.lua); the fork's
-- version messages and their checks are gone.
local ROOT = (arg and arg[0] or ""):match("^(.-)tools/share/") or "./"

local function ReadFile(path)
	local file = assert(io.open(ROOT .. path, "rb"), "can't open " .. path)
	local text = file:read("*a")
	file:close()
	return (text:gsub("\r\n", "\n"))
end

-- The text from `first` up to (not including) `last`.
local function Between(text, first, last, where)
	local from = text:find(first, 1, true)
	assert(from, where .. ": marker not found: " .. first)
	local to = text:find(last, from + #first, true)
	assert(to, where .. ": end marker not found after " .. first .. ": " .. last)
	return text:sub(from, to - 1)
end

local share = ReadFile("EldoUI/Core/Share.lua")
local database = ReadFile("EldoUI/Core/Database.lua")

local PROFILE_SCHEMA = tonumber(database:match("\nE%.PROFILE_SCHEMA = (%d+)"))
local PROFILE_BASELINE = tonumber(database:match("\nE%.PROFILE_BASELINE = (%d+)"))
local FIRST_SCHEMA = tonumber(database:match("local firstProfileSchema = (%d+)"))
assert(PROFILE_SCHEMA and PROFILE_BASELINE and FIRST_SCHEMA, "Database.lua: version constants not found")

---------------------------------------------------------------------------
-- Stand-ins
---------------------------------------------------------------------------
function CopyTable(source)
	local copy = {}
	for key, value in pairs(source) do copy[key] = type(value) == "table" and CopyTable(value) or value end
	return copy
end
local reported = {}
function geterrorhandler() return function(err) reported[#reported + 1] = tostring(err) end end

local E = {
	PROFILE_SCHEMA = PROFILE_SCHEMA,
	PROFILE_BASELINE = PROFILE_BASELINE,
	defaultChanges = {},
	db = { general = { layout = "EldoCenter1000", fontSize = 14 }, movers = {} },
}
function E.Secret() return false end
local L = setmetatable({}, { __index = function(_, key) return key end })

local source = table.concat({
	"local E, L, firstProfileSchema = ...",
	Between(share, "local function Plain(value)", "local function Completion(", "Share.lua"),
	Between(share, "local function ProfileKind(kind)", "local function SourceAdmit(", "Share.lua"),
	Between(database, "\tlocal function Integer(value)", "\tlocal function Same(a, b)", "Database.lua"),
	Between(database, "local function ProfileSchema(profile)", "local CheckProfile", "Database.lua"),
	Between(database, "E.profileMigrations = {}", "function E:RefreshModule(", "Database.lua"),
	Between(share, "local function Stamps(value)", "local function Finish(kind)", "Share.lua"),
	"return { Stamps = Stamps, MigratePart = MigratePart, MigratedPart = MigratedPart }",
}, "\n")
local chunk = assert(loadstring(source, "=extracted"))
local api = chunk(E, L, FIRST_SCHEMA)

---------------------------------------------------------------------------
-- Checks
---------------------------------------------------------------------------
local passed, failed = 0, 0
local function Check(ok, what)
	if ok then passed = passed + 1 else failed = failed + 1; print("FAIL: " .. what) end
end
local function Same(a, b)
	if type(a) ~= "table" or type(b) ~= "table" then return a == b end
	for key, value in pairs(a) do if not Same(value, b[key]) then return false end end
	for key in pairs(b) do if a[key] == nil then return false end end
	return true
end

local function Payload(kind, baseline, version)
	return { kind = kind, data = {}, profileBaseline = baseline, schema = { unit = "profile", version = version } }
end

-- Stamps
Check(Same(api.Stamps({ a = 1, b = 2 }), { a = 1, b = 2 }), "stamps kept")
Check(api.Stamps({}) == nil, "empty stamps count as none")
Check(api.Stamps(nil) == nil, "no stamps")
Check(api.Stamps({ a = "1" }) == nil, "stamp that is no number")
Check(api.Stamps({ [1] = 1 }) == nil, "stamp key that is no name")
Check(api.Stamps({ a = 0 / 0 }) == nil, "NaN stamp")
Check(api.Stamps({ a = math.huge }) == nil, "endless stamp")

---------------------------------------------------------------------------
-- MigratePart
---------------------------------------------------------------------------
-- Default changes: one the player keeps (the old default is written in
-- when the part has no value), one everybody gets.
E.defaultChanges = {
	{ schema = PROFILE_SCHEMA, path = "modules.Messages.size", from = 10, to = 12, keep = true },
	{ schema = PROFILE_SCHEMA, path = "modules.Messages.color", from = "red", to = "blue", keep = false },
	{ schema = PROFILE_SCHEMA, path = "general.fontSize", from = 12, to = 14, keep = true },
}
-- Runs every time: a renamed key.
E:RegisterProfileMigration(function(profile)
	local own = type(profile.modules) == "table" and profile.modules.Messages
	if type(own) == "table" and own.oldKey ~= nil then own.newKey, own.oldKey = own.oldKey, nil end
end)
-- Keyed, value based (like Messages:popup): it can't tell an old value from a new choice.
E:RegisterProfileMigration(function(profile)
	local own = type(profile.modules) == "table" and profile.modules.Messages
	if type(own) == "table" and own.openOnReceive == "dock" then own.openOnReceive = nil end
end, "test:popup", 1)
-- Keyed, reads the layout and writes into general (which a module import never takes).
E:RegisterProfileMigration(function(profile)
	local own = type(profile.modules) == "table" and profile.modules.Messages
	if type(own) == "table" then own.seenLayout = profile.general and profile.general.layout end
	if type(profile.general) == "table" then profile.general.touched = true end
end, "test:layout", 2)

local function Module(version, data, stamps, movers)
	local payload = Payload("module:Messages", PROFILE_BASELINE, version)
	payload.data, payload.migrations, payload.movers = data, stamps, movers
	return payload
end
local receiverGeneral = CopyTable(E.db.general)

-- No stamps, current version: only the migration that runs every time.
do
	local data = { openOnReceive = "dock", oldKey = 3 }
	local part, movers = api.MigratePart(Module(PROFILE_SCHEMA, data), CopyTable(data), nil)
	Check(Same(part, { openOnReceive = "dock", newKey = 3 }), "no stamps: keyed migrations stay off, renamed key moves")
	Check(movers == nil, "no movers in, none out")
end

-- No stamps, older version: the default changes it missed, still no keyed migration.
do
	local part = api.MigratePart(Module(PROFILE_SCHEMA - 1, {}), {}, nil)
	Check(Same(part, { size = 10 }), "older string: kept default written in, a correction is not")
	local own = { size = 11 }
	part = api.MigratePart(Module(PROFILE_SCHEMA - 1, own), CopyTable(own), nil)
	Check(Same(part, { size = 11 }), "older string: the sender's own value stays")
end

-- Stamps from a sender whose EldoUI didn't know test:popup and had test:layout at 1.
do
	local data = { openOnReceive = "dock" }
	local stamps = { ["test:layout"] = 1, ["unknown:here"] = 4 }
	local movers = { EldoUI_Messages = { "CENTER", "UIParent", "CENTER", 10, 20 } }
	local part, outMovers = api.MigratePart(Module(PROFILE_SCHEMA, data, stamps, movers), CopyTable(data), CopyTable(movers))
	Check(Same(part, { seenLayout = "EldoCenter1000" }), "stamps: missing keyed migrations run, with the receiver's layout")
	Check(Same(outMovers, movers), "module frames come back")
	Check(Same(E.db.general, receiverGeneral), "the receiver's general settings stay as they are")
end

-- Stamps that say everything ran: nothing keyed runs.
do
	local data = { openOnReceive = "dock" }
	local stamps = { ["test:popup"] = 1, ["test:layout"] = 2 }
	local part = api.MigratePart(Module(PROFILE_SCHEMA, data, stamps), CopyTable(data), nil)
	Check(Same(part, { openOnReceive = "dock" }), "stamps up to date: the sender's choice stays")
end

-- General: the part itself is the general table.
do
	local payload = Payload("general", PROFILE_BASELINE, PROFILE_SCHEMA - 1)
	payload.data = { accent = "FF0000" }
	payload.migrations = { ["test:popup"] = 1 }
	local part = api.MigratePart(payload, CopyTable(payload.data))
	Check(Same(part, { accent = "FF0000", fontSize = 12, touched = true }), "general: default change and keyed migration")
	Check(Same(E.db.general, receiverGeneral), "general: the receiver's table is not touched")
end

-- Positions
do
	local payload = Payload("positions", PROFILE_BASELINE, PROFILE_SCHEMA)
	payload.data = { EldoUI_Player = { "BOTTOM", "UIParent", "BOTTOM", 0, 200 } }
	local part = api.MigratePart(payload, CopyTable(payload.data))
	Check(Same(part, payload.data), "positions come back as they were")
end

-- A failing migration goes to the error log; the import goes on.
do
	E:RegisterProfileMigration(function() error("broken migration") end, "test:broken", 1)
	local before = #reported
	local part = api.MigratedPart(Module(PROFILE_SCHEMA, {}, { ["test:popup"] = 1, ["test:layout"] = 2 }), {}, nil)
	Check(Same(part, {}), "a broken migration doesn't stop the part")
	Check(#reported == before + 1 and reported[#reported]:find("broken migration", 1, true) ~= nil, "a broken migration is reported")
	table.remove(E.profileMigrations)
end

-- A payload without a usable version, and an error inside: no part, no Lua error.
do
	local payload = Module(PROFILE_SCHEMA, {})
	payload.schema = nil
	Check(api.MigratedPart(payload, {}, nil) == nil, "no version: nothing applied")
	local apply = E.ApplyDefaultChanges
	E.ApplyDefaultChanges = function() error("boom") end
	local before = #reported
	Check(api.MigratedPart(Module(PROFILE_SCHEMA - 1, {}), {}, nil) == nil, "an error inside stops the import")
	Check(#reported == before + 1, "an error inside is reported")
	E.ApplyDefaultChanges = apply
end

print(("%d checks passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
