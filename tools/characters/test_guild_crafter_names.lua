-- Offline test for the guild crafters' names (EldoUI/Modules/Characters/
-- GuildCrafters.lua). Run from the repository root:
--   lua5.1 tools/characters/test_guild_crafter_names.lua
-- Found with F27 (26.11.2026, the mail alts): the recipe lists named each
-- character by the first name alone (the character store's record.name),
-- so "Whisper" on the Crafters tab went to a name Forever turns down (a
-- whisper needs the first name and the surname), and the online mark,
-- read from the guild roster, did not match.
-- This starts all of EldoUI in the offline game (tools/harness/wow.lua).
-- Checked: your list names your characters with their surname (and one
-- without a surname in its key by the first name, as before) and comes
-- through the wire format whole; a crafter named in full is online when the
-- roster has them, also with the game's surname separator, and also when the
-- roster names members without their surname; a first name alone (a list
-- from an older EldoUI) is online by the roster's first names; Whisper goes
-- to the full name, a first name alone becomes the one online member's full
-- name, and stays as it is when two online members share it or none has
-- it, or when a member online has exactly that name; a first name alone
-- from an older list yields to a full row with that first name and class
-- (one character, sent twice), but not to one of another class; the names
-- show in the player's name format; no errors.
local ROOT = (arg and arg[0] or ""):match("^(.-)tools/characters/") or "./"

local passed, failed = 0, 0
local function Check(ok, what)
	if ok then passed = passed + 1 else failed = failed + 1; print("FAIL: " .. what) end
end

local World = dofile(ROOT .. "tools/harness/wow.lua")
World.root = ROOT
World.locale = "enUS"
World.globalNames = dofile(ROOT .. "tools/ci/globals.lua")
assert(World.AddAddon("EldoUI"), "EldoUI/EldoUI.toc not found")
for _, name in ipairs({ "EldoUI_Locale_daDK", "EldoUI_Locale_deDE" }) do World.AddAddon(name) end
World.Install()

World.phase = "load"
World.LoadAddOn("EldoUI")
local E = World.addons.EldoUI.ns

World.phase = "PLAYER_LOGIN"
World.loggedIn = true
World.Fire("PLAYER_LOGIN")
World.phase = "PLAYER_ENTERING_WORLD"
World.Fire("PLAYER_ENTERING_WORLD", true, false)
World.phase = "timers"
World.RunTimers(5)
World.phase = "test"

E:SetModuleEnabled("Characters", true)
World.RunTimers(3)
local M = E.modules.Characters
Check(M and M.active, "the Characters module runs")
M.db.crafterShare = true

-- The game's constants: no surname separator given (a space then).
local GameConstants = rawget(_G, "Constants")
local constants = {}
rawset(_G, "Constants", constants)

---------------------------------------------------------------------------
-- Your list names your characters in full
---------------------------------------------------------------------------
local store = E.Characters
local me = store:Me()
local all = store:All()
local realmKey = me.realmKey or "PvE"
me.realmKey = realmKey
local tailoring = { rank = 150, recipes = "2389" }
me.profs = { Tailoring = tailoring }
all["Brakka Steinfaust - " .. realmKey] = { name = "Brakka", class = "WARRIOR", level = 34, faction = me.faction,
	realmKey = realmKey, realm = me.realm, profs = { Blacksmithing = { rank = 90, recipes = "2662" } } }
all["Old - " .. realmKey] = { name = "Old", class = "MAGE", level = 12, faction = me.faction,
	realmKey = realmKey, realm = me.realm, profs = { Alchemy = { rank = 60, recipes = "2330" } } }
store:ForgetKeys()

local mine = {}
for _, char in ipairs(M:MyRecipeList()) do mine[char.name] = char end
Check(mine["Brakka Steinfaust"] ~= nil, "your list names \"Brakka Steinfaust\"")
Check(mine.Brakka == nil, "not the first name alone")
Check(mine.Old ~= nil, "a key without a surname: the first name, as before")
local chars = M.DecodeCrafters(M.EncodeCrafters(M:MyRecipeList()))
local through = false
for _, char in ipairs(chars) do
	if char.name == "Brakka Steinfaust" and char.class == "WARRIOR" and char.profs.Blacksmithing then through = true end
end
Check(through, "the full name comes through the wire format whole")

---------------------------------------------------------------------------
-- The guild: two lists, one from an older EldoUI with first names only
---------------------------------------------------------------------------
local roster = {}
rawset(_G, "IsInGuild", function() return true end)
rawset(_G, "GetNumGuildMembers", function() return #roster end)
rawset(_G, "GetGuildRosterInfo", function(index)
	local member = roster[index]
	if member then return member[1], "", 0, 60, "", "", "", "", member[2] end
end)
local function Roster(list)
	roster = list
	M:MarkGuildOnline()
end

local function List(lines) return "R" .. table.concat(lines, "\n") end
M.OnCrafterMessage(List({ "C\tMira Stone\tPRIEST", "P\tTailoring\t200\t2389" }), "Mira Stone-Realm")
M.OnCrafterMessage(List({ "C\tJoe\tROGUE", "P\tTailoring\t120\t2389" }), "Joe-Realm")

Roster({ { "Mira Stone-Realm", true }, { "Joe Cutter-Realm", true } })
Check(M:CrafterOnline("Mira Stone"), "a crafter named in full is online when the roster has them")
Check(M:CrafterOnline("Joe"), "a first name alone (an older list) is online by the roster's first name")
Check(not M:CrafterOnline("Mira Other"), "another surname is someone else")
Roster({ { "Mira Stone-Realm", false }, { "Joe Cutter-Realm", false } })
Check(not M:CrafterOnline("Mira Stone") and not M:CrafterOnline("Joe"), "offline in the roster: offline")
Roster({ { "Mira-Realm", true } })
Check(M:CrafterOnline("Mira Stone"), "a roster without surnames: the full name is online by the first name")
constants.CharacterNameSeparatorConsts = { CHARACTERNAME_SURNAME_SEPARATOR = "\194\160" }
Roster({ { "Mira\194\160Stone-Realm", true }, { "Joe\194\160Cutter-Realm", true } })
Check(M:CrafterOnline("Mira\194\160Stone"), "the game's separator: the full name is online")
Check(M:CrafterOnline("Joe"), "the game's separator: a first name alone is online")
Check(type(M.CrafterWhisperName) == "function" and M:CrafterWhisperName("Joe") == "Joe\194\160Cutter",
	"the game's separator: Whisper gets the roster's full name")
constants.CharacterNameSeparatorConsts = nil

---------------------------------------------------------------------------
-- Whisper
---------------------------------------------------------------------------
local told
local ChatUtil = rawget(_G, "ChatFrameUtil")
rawset(_G, "ChatFrameUtil", { SendTellWithMessage = function(name) told = name end })
Roster({ { "Mira Stone-Realm", true }, { "Joe Cutter-Realm", true } })
local rows = M.CrafterSearchRows("")
local function Row(name)
	for _, row in ipairs(rows) do
		if row.name == name and not row.asked then return row end
	end
end
local mira, joe = Row("Mira Stone"), Row("Joe")
Check(mira ~= nil and mira.online, "the Crafters tab lists \"Mira Stone\", online")
Check(joe ~= nil and joe.online, "the Crafters tab lists \"Joe\" from the older list, online")
if mira then
	told = nil
	M:WhisperCrafter(mira)
	Check(told == "Mira Stone", "Whisper goes to \"Mira Stone\" (got " .. tostring(told) .. ")")
end
if joe then
	told = nil
	M:WhisperCrafter(joe)
	Check(told == "Joe Cutter", "Whisper to a first name alone goes to the online member's full name (got " .. tostring(told) .. ")")
	Roster({ { "Joe Cutter-Realm", true }, { "Joe Miller-Realm", true } })
	told = nil
	M:WhisperCrafter(joe)
	Check(told == "Joe", "two online members share the first name: it stays as it is")
	Roster({})
	told = nil
	M:WhisperCrafter(joe)
	Check(told == "Joe", "nobody online has it: it stays as it is")
end
Roster({ { "Mira-Realm", true }, { "Mira Stone-Realm", true } })
Check(type(M.CrafterWhisperName) == "function" and M:CrafterWhisperName("Mira") == "Mira",
	"a member online by exactly the first name: Whisper goes to them")

---------------------------------------------------------------------------
-- One character in an old list and a new one
---------------------------------------------------------------------------
M.OnCrafterMessage(List({ "C\tJoe Cutter\tROGUE", "P\tTailoring\t120\t2389" }), "Joeshard Cutter-Realm")
M.OnCrafterMessage(List({ "C\tJoe\tPRIEST", "P\tTailoring\t80\t2389" }), "Joe Priest-Realm")
Roster({ { "Joe Cutter-Realm", true } })
rows = M.CrafterSearchRows("")
local names = {}
for _, row in ipairs(rows) do
	if not row.asked then names[#names + 1] = row.name .. "/" .. tostring(row.class) end
end
local joined = table.concat(names, ",")
Check(joined:find("Joe Cutter/ROGUE", 1, true) and not joined:find("Joe/ROGUE", 1, true),
	"the Crafters tab: the old \"Joe\" yields to \"Joe Cutter\" of the same class (got " .. joined .. ")")
Check(joined:find("Joe/PRIEST", 1, true) ~= nil, "the Crafters tab: a \"Joe\" of another class stays")
-- The recipe's ID as the packed list gives it.
local recipeID
for _, row in ipairs(rows) do recipeID = recipeID or row.id end
local tipRows = M:CraftersOf({ recipeID })
local tipNames = {}
for _, row in ipairs(tipRows) do tipNames[#tipNames + 1] = row.name .. "/" .. tostring(row.class) end
local tipJoined = table.concat(tipNames, ",")
Check(tipJoined:find("Joe Cutter/ROGUE", 1, true) and not tipJoined:find("Joe/ROGUE", 1, true) and tipJoined:find("Joe/PRIEST", 1, true),
	"the tooltip line's crafters: the same (got " .. tipJoined .. ")")

-- The player's name format.
local names_db = E.db.general.names
local format = names_db.format
names_db.format = "first"
local line = M:CrafterLineText(tipRows, "names") or ""
Check(line:find("Mira", 1, true) and not line:find("Mira Stone", 1, true), "name format First name: the line names \"Mira\" (got " .. line .. ")")
names_db.format = format
line = M:CrafterLineText(tipRows, "names") or ""
Check(line:find("Mira Stone", 1, true) ~= nil, "name format as the game shows it: \"Mira Stone\"")
rawset(_G, "ChatFrameUtil", ChatUtil)
rawset(_G, "Constants", GameConstants)

local errors = {}
for _, entry in ipairs(World.errors) do errors[#errors + 1] = ("[%s] %s"):format(entry.phase, entry.message:match("^[^\n]*")) end
Check(#errors == 0, "no errors (" .. #errors .. ")")
for index = 1, math.min(#errors, 20) do print("  " .. errors[index]) end

print(("%d checks passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
