-- Offline test for the Mail address book's alts (EldoUI/Modules/Mail.lua,
-- MailName and Alts). Run from the repository root:
--   lua5.1 tools/mail/test_alt_recipient.lua
-- Seen in the game (26.11.2026): picking one of your characters under
-- Alts in the address book put only the first name into To:, and the
-- letter failed: on Forever a letter needs the first name and the surname.
-- The character store's record keeps the first name only; its key keeps
-- both ("First Surname - <realm key>").
-- This starts all of EldoUI in the offline game (tools/harness/wow.lua).
-- Checked: an alt with a surname in its key gets "First Surname" in the
-- list, in the menu's label and in To:; an alt whose key has no surname
-- (an older key) keeps its first name; a key whose name part is another
-- name entirely gives the record's name; the game's surname separator is
-- used; alts of the other faction or ruleset and this character stay out;
-- no errors.
local ROOT = (arg and arg[0] or ""):match("^(.-)tools/mail/") or "./"

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

local M = E.modules.Mail
Check(M and M.active, "the Mail module runs")
Check(type(M.Alts) == "function", "Mail has its alts list")

-- Your characters in the store, as EldoUI saved them at their logins.
local store = E.Characters
local me = store:Me()
local all = store:All()
local function Alt(key, name, class, level, faction, realmKey)
	all[key] = { name = name, class = class, level = level, faction = faction or me.faction,
		realmKey = realmKey or me.realmKey, realm = me.realm }
end
local realmKey = me.realmKey or "PvE"
me.realmKey = realmKey
Alt("Brakka Steinfaust - " .. realmKey, "Brakka", "WARRIOR", 34)
Alt("Old - " .. realmKey, "Old", "MAGE", 12)
Alt("Someone Else - " .. realmKey, "Other", "PRIEST", 20)
Alt("Enemy Side - " .. realmKey, "Enemy", "ROGUE", 50, me.faction == "Horde" and "Alliance" or "Horde")
Alt("Faraway Name - RP", "Faraway", "DRUID", 40, nil, realmKey == "RP" and "PvP" or "RP")
if store.InvalidateKeys then store:InvalidateKeys() end

-- The game's constants: no surname separator given (a space then).
local GameConstants = rawget(_G, "Constants")
local constants = {}
rawset(_G, "Constants", constants)

local function Names()
	local names = {}
	for _, alt in ipairs(M.Alts()) do names[alt.name] = alt end
	return names
end
local names = Names()
Check(names["Brakka Steinfaust"] ~= nil, "an alt with a surname: the list has \"Brakka Steinfaust\"")
Check(names.Brakka == nil, "an alt with a surname: not the first name alone")
Check(names["Brakka Steinfaust"] and names["Brakka Steinfaust"].level == 34
	and names["Brakka Steinfaust"].class == "WARRIOR", "an alt with a surname: class and level stay")
Check(names.Old ~= nil, "an older key without a surname: the first name, as before")
Check(names.Other ~= nil and names["Someone Else"] == nil, "a key that names someone else: the record's name")
Check(names.Enemy == nil and names["Enemy Side"] == nil, "the other faction stays out")
Check(names.Faraway == nil and names["Faraway Name"] == nil, "another ruleset stays out")
local myName = me.name
local mine = false
for _, alt in ipairs(M.Alts()) do
	if alt.name == myName or (E.charKey and alt.name == E.charKey:match("^(.-) %- ")) then mine = true end
end
Check(not mine, "this character is not in its own list")

-- The game's own separator between first name and surname.
constants.CharacterNameSeparatorConsts = { CHARACTERNAME_SURNAME_SEPARATOR = "\194\160" }
names = Names()
Check(names["Brakka\194\160Steinfaust"] ~= nil, "the game's surname separator joins the two")
constants.CharacterNameSeparatorConsts = { CHARACTERNAME_SURNAME_SEPARATOR = false }
names = Names()
Check(names["Brakka Steinfaust"] ~= nil, "a separator that is not text: a space")
constants.CharacterNameSeparatorConsts = nil

---------------------------------------------------------------------------
-- The address book: pick the alt, To: gets the full name
---------------------------------------------------------------------------
local menu = {}
local function MenuNode(into)
	local node = { entries = into }
	function node:CreateButton(label, fn)
		local entry = { label = label, fn = fn, entries = {} }
		into[#into + 1] = entry
		return MenuNode(entry.entries)
	end
	function node:CreateDivider() end
	return node
end
local ContextMenu = E.UIKit.ContextMenu
E.UIKit.ContextMenu = function(_, build) wipe(menu) build(nil, MenuNode(menu)) end

local box = _G.SendMailNameEditBox
Check(box ~= nil, "the game's To: box is there")
local typed
if box then
	rawset(box, "SetText", function(_, text) typed = text end)
	rawset(box, "GetText", function() return typed or "" end)
end
M.addressBook = nil
M:CreateAddressBook()
local button = M.addressBook
Check(button ~= nil, "the address book button is made")
if button then
	button:GetScript("OnClick")(button)
	local altsMenu
	for _, entry in ipairs(menu) do
		if entry.label == "Alts" then altsMenu = entry end
	end
	Check(altsMenu ~= nil, "the address book has Alts")
	local pick
	for _, entry in ipairs(altsMenu and altsMenu.entries or {}) do
		if tostring(entry.label):find("Brakka Steinfaust", 1, true) then pick = entry end
	end
	Check(pick ~= nil, "the Alts menu names \"Brakka Steinfaust\"")
	if pick then
		pick.fn()
		Check(typed == "Brakka Steinfaust", "picking the alt puts \"Brakka Steinfaust\" into To: (got " .. tostring(typed) .. ")")
	end
end
E.UIKit.ContextMenu = ContextMenu
rawset(_G, "Constants", GameConstants)

local errors = {}
for _, entry in ipairs(World.errors) do errors[#errors + 1] = ("[%s] %s"):format(entry.phase, entry.message:match("^[^\n]*")) end
Check(#errors == 0, "no errors (" .. #errors .. ")")
for index = 1, math.min(#errors, 20) do print("  " .. errors[index]) end

print(("%d checks passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
