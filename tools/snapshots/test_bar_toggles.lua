-- Offline test: Bar Snapshots keep which of action bars 2 to 8 are on.
-- Run from the repository root:
--   lua5.1 tools/snapshots/test_bar_toggles.lua
-- WoW: Forever turned the options' "Show Action Bar n" boxes back at every logout for players with dual
-- specialization until the hotfix of 13 November 2026. A snapshot held the bars' slots, but not which bars are on.
-- It starts EldoUI offline (tools/harness/wow.lua, as `load` does), turns Bar Snapshots on and answers
-- GetActionBarToggles / SetActionBarToggles like the game (seven values, bars 2 to 8).
-- Checked: a snapshot keeps the seven values, never an unclear answer; the fingerprint sees a change; the plan and
-- the restore window list the bars that differ; a restore sets all seven in one call and asks for a reload only
-- when something changed; an unticked part, an old snapshot without the values or a client without the function
-- change nothing and raise no error; the login check calls two or more bars turned off a reset, one bar or a bar
-- turned on not; a shared string keeps the values, drops broken ones, and its checksum stays the one older versions
-- compute.
local ROOT = (arg and arg[0] or ""):match("^(.-)tools/snapshots/") or "./"

local passed, failed = 0, 0
local function Check(ok, what)
	if ok then
		passed = passed + 1
	else
		failed = failed + 1
		print("FAIL: " .. what)
	end
end

---------------------------------------------------------------------------
-- EldoUI offline, Bar Snapshots on
---------------------------------------------------------------------------
local World = dofile(ROOT .. "tools/harness/wow.lua")
World.root = ROOT
World.locale = "enUS"
World.globalNames = dofile(ROOT .. "tools/ci/globals.lua")
assert(World.AddAddon("EldoUI"), "EldoUI/EldoUI.toc not found")
World.Install()
World.phase = "load"
World.LoadAddOn("EldoUI")
World.loggedIn = true
World.phase = "PLAYER_LOGIN"
World.Fire("PLAYER_LOGIN")
World.phase = "PLAYER_ENTERING_WORLD"
World.Fire("PLAYER_ENTERING_WORLD", true, false)
World.RunTimers(5)

local E = World.addons.EldoUI.ns
assert(type(E) == "table" and type(E.SetModuleEnabled) == "function", "EldoUI did not start")
E:SetModuleEnabled("Snapshots", true)
World.RunTimers(3)
local M = E.modules.Snapshots
assert(M and M.active, "Bar Snapshots did not start")
Check(#World.errors == 0, "EldoUI starts with Bar Snapshots on without errors (" .. #World.errors .. ")")
for _, err in ipairs(World.errors) do print("  " .. err.phase .. ": " .. err.message) end

---------------------------------------------------------------------------
-- The game's answers
---------------------------------------------------------------------------
local game = { calls = {} }
local function SetBars(...)
	game.toggles = { ... }
end
local function InstallGame()
	rawset(_G, "GetActionBarToggles", function() return unpack(game.toggles, 1, 7) end)
	rawset(_G, "SetActionBarToggles", function(...)
		game.calls[#game.calls + 1] = { n = select("#", ...), ... }
		game.toggles = { ... }
	end)
end
InstallGame()

local reloads = {}
E.ShowReloadPrompt = function(_, text) reloads[#reloads + 1] = text end
local notes = {}
local function Notify(text, warn) notes[#notes + 1] = { text = text, warn = warn } end

local function Same(a, b)
	if type(a) ~= "table" or type(b) ~= "table" then return false end
	for index = 1, 7 do
		if a[index] ~= b[index] then return false end
	end
	return true
end

local PALADIN = { true, false, false, false, true, true, true } -- bars 2, 6, 7 and 8 on (the Paladin planner's)

---------------------------------------------------------------------------
-- Reading
---------------------------------------------------------------------------
SetBars(unpack(PALADIN))
local snapshot = M:Capture("test")
Check(Same(snapshot.toggles, PALADIN), "a snapshot keeps the seven values")
SetBars(1, nil, nil, nil, 1, 1, 1)
Check(M:Capture("old style").toggles == nil, "1 / nil (an unclear answer) is not saved")
SetBars(true, false, false)
Check(M:Capture("short").toggles == nil, "fewer than seven values are not saved")
rawset(_G, "GetActionBarToggles", function() error("not yet") end)
Check(M:Capture("error").toggles == nil, "an error from the game is not saved")
InstallGame()

SetBars(unpack(PALADIN))
local same = M:Capture("same")
SetBars(true, false, false, false, false, true, true)
local other = M:Capture("other")
Check(same.sig ~= other.sig, "the fingerprint changes when a bar is turned off")

---------------------------------------------------------------------------
-- Plan, restore window and the login check
---------------------------------------------------------------------------
SetBars(true, false, false, false, false, false, false) -- the reset: only bar 2 left on
local plan = M:Plan(snapshot)
plan.toggles = plan.toggles or {}
Check(#plan.toggles == 3 and plan.toggles[1].bar == 6 and plan.toggles[3].bar == 8 and plan.toggles[1].on,
	"the plan lists bars 6, 7 and 8 to turn on")
local window = M:ShowPreview(snapshot)
local part = window and window.parts and window.parts.toggles
Check(part ~= nil, "the restore window has the part \"Which bars are on\"")
if part then
	Check(part:GetChecked() == true, "the part starts checked")
	Check(part.detail and #part.detail == 3 and part.detail[1] == "Action Bar 6: on", "its tooltip lists the bars")
end
if window then window:Hide() end

local signs = M:ResetSigns(snapshot)
local found
for _, sign in ipairs(signs) do
	if sign:find("action bars 6, 7 and 8 are turned off", 1, true) then found = true end
end
Check(found, "the login check names bars 6, 7 and 8 as turned off")
SetBars(true, false, false, false, false, true, true)
Check(#M:ResetSigns(snapshot) == 0, "one bar turned off is no reset")
SetBars(true, true, false, false, false, false, false)
Check(#M:ResetSigns(snapshot) == 0, "bars off while another is turned on is no reset")
SetBars(unpack(PALADIN))
Check(#M:ResetSigns(snapshot) == 0, "the same bars on: no sign")

---------------------------------------------------------------------------
-- Restoring
---------------------------------------------------------------------------
SetBars(true, false, false, false, false, false, false)
game.calls, reloads, notes = {}, {}, {}
Check(M:Restore(snapshot, { toggles = true }, Notify) == true, "the restore runs")
Check(#game.calls == 1, "SetActionBarToggles is called once (" .. #game.calls .. ")")
Check(game.calls[1] and game.calls[1].n == 7 and Same(game.calls[1], PALADIN), "with the snapshot's seven values")
Check(#reloads == 1, "the restore asks for a reload")
Check(notes[1] and notes[1].text:find("3 action bars turned on or off", 1, true) ~= nil, "the summary counts 3 bars")

game.calls, reloads = {}, {}
M:Restore(snapshot, { toggles = true }, Notify)
Check(#game.calls == 0 and #reloads == 0, "nothing to change: no call and no reload")

SetBars(true, false, false, false, false, false, false)
game.calls, reloads = {}, {}
M:Restore(snapshot, { actions = true, toggles = false }, Notify)
Check(#game.calls == 0 and #reloads == 0, "the part unticked: the bars stay as they are")

local old = M:Capture("old")
old.toggles = nil
game.calls = {}
Check(#(M:Plan(old).toggles or {}) == 0, "an old snapshot without the values plans nothing for the bars")
M:Restore(old, { toggles = true }, Notify)
Check(#game.calls == 0, "an old snapshot changes no bar")

rawset(_G, "SetActionBarToggles", nil)
local before = #World.errors
notes, reloads = {}, {}
M:Restore(snapshot, { toggles = true }, Notify)
Check(#World.errors == before, "a client without SetActionBarToggles raises no error")
Check(notes[1] and notes[1].text:find("not turned on or off", 1, true) ~= nil and #reloads == 0,
	"it says the bars were not turned on or off and asks for no reload")
InstallGame()

---------------------------------------------------------------------------
-- Shared strings
---------------------------------------------------------------------------
local raw = { actions = { [1] = { "spell", 635 } }, macros = {}, bindings = {}, toggles = PALADIN }
local clean = M.CleanImport(raw)
Check(clean and Same(clean.toggles, PALADIN), "an imported string keeps the seven values")
raw.toggles = { true, false, "yes", false, true, true, true }
Check(M.CleanImport(raw).toggles == nil, "a value that is not true or false drops them all")
raw.toggles = { true, false }
Check(M.CleanImport(raw).toggles == nil, "fewer than seven values are dropped")
local withBars = M.CleanImport({ actions = { [1] = { "spell", 635 } }, macros = {}, bindings = {}, toggles = PALADIN })
local without = M.CleanImport({ actions = { [1] = { "spell", 635 } }, macros = {}, bindings = {} })
Check(M.Checksum(withBars) == M.Checksum(without), "the checksum stays the one older versions compute")
raw = { actions = { [1] = { "spell", 635 } }, macros = {}, bindings = {}, toggles = PALADIN }
raw.sum = M.Checksum(without)
Check(M.CleanImport(raw) ~= nil, "a string with the values and the old checksum is accepted")

Check(#World.errors == 0, "no errors after all checks (" .. #World.errors .. ")")
for _, err in ipairs(World.errors) do print("  " .. err.phase .. ": " .. err.message) end

print(("%d checks passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
