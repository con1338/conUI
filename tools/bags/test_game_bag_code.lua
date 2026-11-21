-- Offline test: EldoUI's bag window never runs the game's bag code (F24).
-- Run from the repository root:
--   lua5.1 tools/bags/test_game_bag_code.lua
-- Seen in the game (15.-21.11.2026, 157 times in the error log): "Forbidden:
-- EldoUI tried to call the protected function UNKNOWN() at
-- Blizzard_UIPanels_Game/Mainline/ContainerFrame.lua:1611", every
-- right-click use from the bags (hearthstone, keys, recipes, putting an
-- item into the trade window) blocked until a reload. A check in the game
-- found BankFrame.BankPanel.bankType tainted by EldoUI. The game's bank
-- window calls OpenAllBags(self) before it picks its tab, so a bag value
-- EldoUI had written (CloseAllBags() writes FRAME_THAT_OPENED_BAGS, an open
-- from EldoUI builds the game's bag frames) tainted the tab, and every
-- right-click hands that tab to UseContainerItem.
-- This cuts the real helpers, CloseWindow, SyncOpen and the ToggleAllBags
-- and CloseAllBags hooks out of EldoUI/Modules/Bags/Core.lua (between fixed
-- markers, so a renamed part makes the test fail instead of testing a stale
-- copy) and runs them against a model of the game's bag frames on EldoUI's
-- hidden parent. Checked: while the frames are parked EldoUI calls none of
-- the game's bag functions (open, close, toggle); its window opens alone,
-- stays through a bank visit and closes on its close button, the info bar
-- block, the game's B and the backpack key; with the game's frames shown
-- the game's functions are used as before. A text check makes sure no other place in Core.lua,
-- InfoBar.lua or FlightView.lua calls them directly.
local ROOT = (arg and arg[0] or ""):match("^(.-)tools/bags/") or "./"

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

local core = ReadFile("EldoUI/Modules/Bags/Core.lua")
local helpers = Between(core, "function M:GameBagsParked()", "-- Tour help: the bag window explains itself once", "Core.lua helpers")
local syncing = Between(core, "function M:CloseWindow(window)", "-- Bank window anywhere: the selected character's saved bank.", "Core.lua SyncOpen")
-- The two post-hooks at the end of HookBagFrames (ToggleAllBags and
-- CloseAllBags), run as they are against a hooksecurefunc that keeps them.
local hooks = Between(core, 'if ToggleAllBags then\n\t\thooksecurefunc("ToggleAllBags", function()',
	"\nend\nM.HookBagFrames = HookBagFrames", "Core.lua HookBagFrames hooks")

---------------------------------------------------------------------------
-- Model of the game's bag frames and EldoUI's window
---------------------------------------------------------------------------
local world
local hider = { name = "EldoUI's hidden parent" }
local UIPARENT = { name = "UIParent" }

local function NewFrame(id, parent)
	local frame = { id = id, shown = false, parent = parent }
	function frame:GetParent() return self.parent end
	function frame:IsShown() return self.shown end
	function frame:Show() self.shown = true end
	function frame:Hide() self.shown = false end
	function frame:EnumerateValidItems() return pairs({}) end
	return frame
end

local frames = {}
local function BlizzardBagFrames() return frames end

local window = { kind = "bags", shown = false, search = { ClearFocus = function() end } }
function window:IsShown() return self.shown end
function window:Hide() self.shown = false; self.eldoOnly = nil end
local windows = { bags = window }

local function NewWorld(parked, own)
	world = { own = own ~= false, game = {}, newItems = 0, forgot = 0, opens = 0 }
	for i = 1, 3 do frames[i] = NewFrame(i - 1, parked and hider or UIPARENT) end
	window.shown, window.eldoOnly, window.viewChar = false, nil, nil
end

-- What the game's functions would do; every call is counted, since one
-- made from EldoUI's code is what tainted the bank.
local function GameOpen() for _, frame in ipairs(frames) do frame:Show() end end
local function GameClose() for _, frame in ipairs(frames) do frame:Hide() end end
local function AnyShown()
	for _, frame in ipairs(frames) do
		if frame:IsShown() then return true end
	end
	return false
end
function OpenAllBags() world.game[#world.game + 1] = "OpenAllBags"; GameOpen() end
function CloseAllBags(frame) world.game[#world.game + 1] = "CloseAllBags(" .. tostring(frame and frame.name) .. ")"; GameClose() end
function ToggleAllBags()
	world.game[#world.game + 1] = "ToggleAllBags"
	if AnyShown() then GameClose() else GameOpen() end
end
function UpdateNewItemList() world.newItems = world.newItems + 1 end

local E = { charKey = "Hermano-Doomhowl" }
function E:SlideOut(frame) frame:Hide() end

local M = {}
function M:OwnBags() return world.own end
function M:AnyBagOpen() return AnyShown() end
function M:WindowSide() return "RIGHT" end
function M:OpenWindow(frame) frame.shown = true; world.opens = world.opens + 1 end
function M:ForgetAutoOpen() world.forgot = world.forgot + 1 end

local posthooks = {}
function hooksecurefunc(name, fn)
	assert(type(name) == "string" and type(fn) == "function", "hooksecurefunc(name, fn)")
	posthooks[name] = fn
end

local env = "local M, E, windows, hider, BlizzardBagFrames = ...\n"
for _, part in ipairs({ { helpers, "helpers" }, { syncing, "SyncOpen" }, { hooks, "HookBagFrames hooks" } }) do
	local chunk = assert(loadstring(env .. part[1], "=Core.lua " .. part[2]))
	chunk(M, E, windows, hider, BlizzardBagFrames)
end
assert(posthooks.ToggleAllBags and posthooks.CloseAllBags, "HookBagFrames: the ToggleAllBags or CloseAllBags hook is missing")

-- The player's own toggles (not EldoUI's calls): the game's function,
-- then EldoUI's post-hook.
local function PlayerCall(name, fn)
	local calls = #world.game
	fn()
	table.remove(world.game, calls + 1)
	posthooks[name]()
end
-- B: ToggleAllBags.
local function PressB() PlayerCall("ToggleAllBags", ToggleAllBags) end
-- The backpack key on a closed backpack opens it; on an open one the game
-- closes all bags (ToggleBackpack -> CloseAllBags()).
local function PressBackpack()
	if AnyShown() then
		PlayerCall("CloseAllBags", CloseAllBags)
	else
		GameOpen()
	end
end
-- A bank or vendor closes: the game's CloseAllBags(frame).
local function WindowCloses(frame)
	local calls = #world.game
	CloseAllBags(frame)
	table.remove(world.game, calls + 1)
	posthooks.CloseAllBags(frame)
end

local failures, passed = 0, 0
local function Check(ok, message)
	if ok then
		passed = passed + 1
	else
		failures = failures + 1
		print("FAIL: " .. message)
	end
end

local function NoGameCalls()
	return #world.game == 0
end

---------------------------------------------------------------------------
-- The game's frames on EldoUI's hidden parent (EldoUI's window replaces them)
---------------------------------------------------------------------------
do
	NewWorld(true)
	Check(M:GameBagsParked(), "the frames on the hidden parent count as parked")
	M:OpenBags()
	Check(window:IsShown() and window.eldoOnly and window.viewChar == E.charKey, "OpenBags shows EldoUI's window alone")
	Check(not AnyShown(), "OpenBags leaves the game's frames closed")
	Check(NoGameCalls(), "OpenBags calls none of the game's bag functions")
	M:ToggleBags()
	Check(not window:IsShown() and not window.eldoOnly, "the info bar block closes the window again")
	Check(NoGameCalls(), "the info bar block calls none of the game's bag functions")
	M:ToggleBags()
	Check(window:IsShown() and NoGameCalls(), "the info bar block opens it without the game's code")
end

do
	-- The bags opened by the game (B, a bank): the window follows them.
	NewWorld(true)
	GameOpen()
	M:SyncOpen()
	Check(window:IsShown() and not window.eldoOnly, "the window follows the game's bags")
	M:CloseWindow(window)
	Check(not AnyShown(), "the close button closes the game's frames")
	Check(world.newItems == 3, "the items of each closed frame lose their new mark, as in the game's close")
	Check(world.forgot == 1, "a close without a window forgets who opened the bags, as the game's CloseAllBags() hook does")
	Check(NoGameCalls(), "the close button calls none of the game's bag functions (no FRAME_THAT_OPENED_BAGS)")
	M:SyncOpen()
	Check(not window:IsShown(), "the window stays closed")
end

do
	NewWorld(true)
	local bank = { name = "BankFrame" }
	GameOpen()
	M:CloseGameBags(bank)
	Check(not AnyShown() and world.forgot == 0 and NoGameCalls(),
		"closing for a window (auto-open off) hides the frames and keeps who opened them")
end

do
	-- Opened alone, then a bank opens and closes the game's bags.
	NewWorld(true)
	M:OpenBags()
	GameOpen()
	M:SyncOpen()
	WindowCloses({ name = "BankFrame" })
	M:SyncOpen()
	Check(window:IsShown() and window.eldoOnly, "a window opened alone stays when the bank closes the game's bags")
	PressB()
	M:SyncOpen()
	Check(not window:IsShown() and not AnyShown(), "B closes a window opened alone (the game had opened its frames)")
	Check(NoGameCalls(), "closing after B calls none of the game's bag functions")
end

do
	-- Opened alone, at the bank (the game's bags open): B closes them.
	NewWorld(true)
	M:OpenBags()
	GameOpen()
	M:SyncOpen()
	PressB()
	M:SyncOpen()
	Check(not window:IsShown() and not AnyShown(), "B at the bank closes a window opened alone")
end

do
	-- Opened alone: the backpack key opens the game's backpack first (no
	-- change on screen), then closes all bags, and the window goes too.
	NewWorld(true)
	M:OpenBags()
	PressBackpack()
	M:SyncOpen()
	Check(window:IsShown(), "the backpack key on the closed backpack leaves a window opened alone open")
	PressBackpack()
	M:SyncOpen()
	Check(not window:IsShown() and not AnyShown(), "the backpack key on the open backpack closes a window opened alone")
	Check(NoGameCalls(), "the backpack key needs no call of EldoUI's")
end

do
	-- The normal case is unchanged: B opens, B closes.
	NewWorld(true)
	PressB()
	M:SyncOpen()
	Check(window:IsShown() and not window.eldoOnly, "B opens the bags and the window follows")
	PressB()
	M:SyncOpen()
	Check(not window:IsShown(), "B closes them and the window follows")
	Check(NoGameCalls(), "the normal B toggle needs no call of EldoUI's")
end

do
	NewWorld(true)
	M:OpenBags()
	M:CloseBags()
	Check(not window:IsShown() and NoGameCalls(), "CloseBags (a window's close event) closes a window opened alone")
	GameOpen()
	M:SyncOpen()
	M:CloseBags()
	Check(not AnyShown() and NoGameCalls(), "CloseBags closes the game's frames quietly")
end

do
	NewWorld(true, false)
	M:ToggleBags()
	Check(world.game[1] == "ToggleAllBags", "without EldoUI's window the info bar block uses the game's toggle")
end

---------------------------------------------------------------------------
-- The game's frames shown (Blizzard's bags in use): the game's functions
---------------------------------------------------------------------------
do
	NewWorld(false)
	Check(not M:GameBagsParked(), "frames on UIParent are not parked")
	M:OpenBags()
	Check(world.game[1] == "OpenAllBags" and not window.eldoOnly, "OpenBags uses the game's OpenAllBags")
	M:CloseGameBags()
	Check(world.game[2] == "CloseAllBags(nil)", "CloseGameBags uses the game's CloseAllBags()")
	M:CloseGameBags({ name = "MerchantFrame" })
	Check(world.game[3] == "CloseAllBags(MerchantFrame)", "CloseGameBags hands the window on to CloseAllBags(frame)")
	M:ToggleBags()
	Check(world.game[4] == "ToggleAllBags", "ToggleBags uses the game's ToggleAllBags")
end

---------------------------------------------------------------------------
-- No other direct call of the game's bag functions
---------------------------------------------------------------------------
local CALLS = { "OpenAllBags%(", "CloseAllBags%(", "ToggleAllBags%(", "OpenBackpack%(", "ToggleBackpack%(",
	"CloseBackpack%(", "OpenBag%(", "ToggleBag%(", "CloseBag%(" }

-- Lines that call one, outside comments and outside `allowed`.
local function DirectCalls(text, allowed)
	local found = {}
	if allowed then
		local from = assert(text:find(allowed, 1, true), "allowed part not found")
		text = text:sub(1, from - 1) .. text:sub(from + #allowed)
	end
	for line in text:gmatch("[^\n]+") do
		local code = line:gsub("%-%-.*$", "")
		for _, call in ipairs(CALLS) do
			if code:find("[^%w_.:\"]" .. call) or code:find("^" .. call) then found[#found + 1] = line end
		end
	end
	return found
end

do
	local list = DirectCalls(core, helpers)
	Check(#list == 0, "Core.lua calls the game's bag functions only in its helpers: " .. table.concat(list, " | "))
	local infobar = ReadFile("EldoUI/Modules/InfoBar.lua")
	local fallback = Between(infobar, "function M.ToggleBags()", "local function Hex(", "InfoBar.lua ToggleBags")
	list = DirectCalls(infobar, fallback)
	Check(#list == 0, "InfoBar.lua toggles the bags only through M.ToggleBags: " .. table.concat(list, " | "))
	local flight = ReadFile("EldoUI/Modules/QoL/FlightView.lua")
	local button = Between(flight, 'M:CloseFlightView("bags")', "end })", "FlightView.lua Bags button")
	list = DirectCalls(flight, button)
	Check(#list == 0, "FlightView.lua toggles the bags only through the Bags module: " .. table.concat(list, " | "))
	-- Counter-check: the check finds a direct call.
	Check(#DirectCalls("\tif x then CloseAllBags() end\n") == 1, "counter-check: a direct CloseAllBags() is found")
end

print(("%d checks passed, %d failed"):format(passed, failures))
os.exit(failures == 0 and 0 or 1)
