-- Offline test for the Info Bar's memory block ("Mem").
-- Run from the repository root:
--   lua5.1 tools/infobar/test_memory_poll.lua
-- Seen with /eui perf (15.11.2026): the slowest Info Bar call took 130 ms.
-- The memory block read every addon's memory (UpdateAddOnMemoryUsage) every
-- 30 seconds, and with Questie, AtlasLoot, Details and DBM loaded that
-- reading alone stops the game for about 130 ms: a stutter every 30 seconds.
-- Now the bar reads as rarely as the reading is slow (3 s per ms it took,
-- between 30 s and 10 minutes), the tooltip reads afresh when it opens on a
-- copy older than 10 s, its redraws show the kept copy, and a click reads
-- right away.
-- This cuts the real part out of EldoUI/Modules/InfoBar.lua (between fixed
-- markers, so a renamed part makes the test fail instead of testing a stale
-- copy): the memory and CPU helpers, the tooltip redraw timer, the shared
-- reading and the "Memory" block. Around them: a clock, the game's memory
-- counters with a reading that takes a set time, the bar's 30-second poll,
-- the tooltip and the combat state.
-- Checked: how often a slow, a light and a very slow setup read in 30
-- minutes; opening the tooltip reads afresh only on an old copy and the bar
-- then shows the same total; redraws never read; nothing reads on its own in
-- combat, a click does; without the game's timer the bar keeps 30 seconds.
local ROOT = (arg and arg[0] or ""):match("^(.-)tools/infobar/") or "./"

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

local infobar = ReadFile("EldoUI/Modules/InfoBar.lua")
local block = Between(infobar, "-- Performance: memory and CPU of addons", 'E:RegisterDataText("CPU", {', "InfoBar.lua memory")
local function Load()
	return assert(loadstring("local E, L, M, Value = ...\n" .. block, "=InfoBar.lua memory"))
end

---------------------------------------------------------------------------
-- Model of the game and EldoUI's core
---------------------------------------------------------------------------
local world
local NAMES = { "EldoUI", "Questie", "Details" }

function GetTime() return world.now end
function InCombatLockdown() return world.combat end
function UpdateAddOnMemoryUsage()
	world.reads = world.reads + 1
	world.ms = world.ms + world.cost
end
function GetAddOnMemoryUsage(index) return world.memory[index] end
C_AddOns = {
	GetNumAddOns = function() return #NAMES end,
	GetAddOnInfo = function(index) return NAMES[index] end,
	IsAddOnLoaded = function() return true end,
}
C_Timer = { After = function(seconds, fn) table.insert(world.timers, { at = world.now + seconds, fn = fn }) end }
function geterrorhandler() return function(err) error(err, 0) end end

local L = setmetatable({}, { __index = function(_, key) return key end })

local function NewTooltip(owner)
	local tooltip = { owner = owner, pairs = {}, rows = 0 }
	function tooltip:AddLine() end
	function tooltip:AddDoubleLine() self.rows = self.rows + 1 end
	function tooltip:IsShown() return world.hovering end
	function tooltip:GetOwner() return self.owner end
	return tooltip
end

-- cost: milliseconds one reading of all addons takes. clock = false: the
-- game has no debugprofilestop.
local function NewWorld(cost, clock)
	world = {
		now = 1000, ms = 0, cost = cost, reads = 0, combat = false, timers = {}, hovering = false,
		memory = { 20480, 51200, 10240 }, redraws = 0, shows = 0,
	}
	if clock == false then
		debugprofilestop = nil
	else
		debugprofilestop = function() return world.ms end
	end
	local E = { name = "EldoUI", dataTexts = {}, UIKit = {} }
	function E:RegisterDataText(name, definition) self.dataTexts[name] = definition end
	function E.UIKit.TipPair(tooltip, label, value) tooltip.pairs[label] = value end
	function E.UIKit.TipText() end
	function E:TooltipHint() end
	local M = {}
	local button = { dataName = "Memory" }
	function button:IsMouseOver() return world.hovering end
	function M.UpdateButton(target) target.text = E.dataTexts[target.dataName].text() end
	function M.ShowTooltip(owner)
		world.shows = world.shows + 1
		local tooltip = NewTooltip(owner)
		E.dataTexts[owner.dataName].tooltip(tooltip)
		world.tooltip = tooltip
	end
	Load()(E, L, M, function(text) return text end)
	world.E, world.M, world.button = E, M, button
	return E.dataTexts.Memory, M, button
end

-- The bar's poll: every `interval` seconds the block's text updates.
local function RunBar(definition, M, button, seconds)
	local stop = world.now + seconds
	while world.now + definition.interval <= stop do
		world.now = world.now + definition.interval
		M.UpdateButton(button)
	end
end

-- The tooltip's redraw timers while the mouse stays on the block.
local function Hover(seconds)
	local stop = world.now + seconds
	while true do
		table.sort(world.timers, function(a, b) return a.at < b.at end)
		local timer = world.timers[1]
		if not timer or timer.at > stop then break end
		table.remove(world.timers, 1)
		world.now = timer.at
		local before = world.shows
		timer.fn()
		if world.shows > before then world.redraws = world.redraws + 1 end
	end
	world.now = stop
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

---------------------------------------------------------------------------
-- How often the bar reads
---------------------------------------------------------------------------
do
	-- The setup from the game: 130 ms per reading.
	local definition, M, button = NewWorld(130)
	Check(definition.interval == 30, "the block's text still updates every 30 seconds")
	M.UpdateButton(button)
	Check(world.reads == 1, "the first text reads once")
	Check(button.text == "80.0 MB", "the bar shows the total of all addons (" .. tostring(button.text) .. ")")
	RunBar(definition, M, button, 30 * 60)
	-- 130 ms -> every 390 s: readings at 0, 390, 780, 1170 and 1560 s.
	Check(world.reads == 5, "a 130 ms reading runs 5 times in 30 minutes, not 61 (" .. world.reads .. ")")
end

do
	-- A light setup keeps the old 30 seconds.
	local definition, M, button = NewWorld(5)
	M.UpdateButton(button)
	RunBar(definition, M, button, 30 * 60)
	Check(world.reads == 61, "a 5 ms reading still runs every 30 seconds (" .. world.reads .. ")")
end

do
	-- A very slow setup waits at most 10 minutes.
	local definition, M, button = NewWorld(1000)
	M.UpdateButton(button)
	RunBar(definition, M, button, 30 * 60)
	Check(world.reads == 4, "a 1 s reading runs every 10 minutes at most (" .. world.reads .. ")")
end

do
	-- Without the game's timer nothing changes: every 30 seconds.
	local definition, M, button = NewWorld(130, false)
	M.UpdateButton(button)
	RunBar(definition, M, button, 10 * 60)
	Check(world.reads == 21, "without debugprofilestop the bar keeps reading every 30 seconds (" .. world.reads .. ")")
end

---------------------------------------------------------------------------
-- The tooltip
---------------------------------------------------------------------------
do
	local definition, M, button = NewWorld(130)
	M.UpdateButton(button) -- reads at 1000
	Check(world.reads == 1, "tooltip setup: one reading")

	-- Opened on a young copy: no new reading.
	world.now = 1005
	world.hovering = true
	M.ShowTooltip(button)
	Check(world.reads == 1, "the tooltip opened on a 5 s old copy does not read")
	Check(world.tooltip.pairs["All addons"] == "80.0 MB", "the tooltip shows the kept total")
	world.hovering = false
	Hover(5) -- its redraw timer runs out with the mouse gone

	-- Opened on an older copy: reads afresh, and the bar follows.
	world.memory[2] = 61440
	world.now = 1060
	world.hovering = true
	M.ShowTooltip(button)
	Check(world.reads == 2, "the tooltip opened on a 60 s old copy reads afresh")
	Check(world.tooltip.pairs["All addons"] == "90.0 MB", "the tooltip shows the fresh total")
	Check(button.text == "90.0 MB", "the bar shows the same fresh total as the tooltip (" .. tostring(button.text) .. ")")
	Check(world.tooltip.rows == 3, "the tooltip lists every addon")

	-- The mouse stays: the tooltip redraws every 5 seconds from the kept copy.
	Hover(100)
	Check(world.redraws >= 15, "the tooltip redraws while the mouse stays (" .. world.redraws .. ")")
	Check(world.reads == 2, "redraws never read (" .. world.reads .. ")")
	world.hovering = false
	Hover(10)
	Check(#world.timers == 0, "no redraw is left once the mouse is gone")

	-- The bar waits its full time after the fresh reading (390 s for 130 ms).
	world.now = 1060 + 330
	RunBar(definition, M, button, 30) -- 360 s after the tooltip's reading
	Check(world.reads == 2, "after a fresh tooltip reading the bar waits its full time")
	RunBar(definition, M, button, 30) -- 390 s after it
	Check(world.reads == 3, "then the bar reads again")
end

---------------------------------------------------------------------------
-- Combat
---------------------------------------------------------------------------
do
	local definition, M, button = NewWorld(130)
	M.UpdateButton(button)
	world.combat = true
	RunBar(definition, M, button, 600)
	Check(world.reads == 1, "the bar never reads on its own in combat")
	world.hovering = true
	M.ShowTooltip(button)
	Check(world.reads == 1, "opening the tooltip in combat does not read")
	world.hovering = false
	world.timers = {}
	definition.onClick(button)
	Check(world.reads == 2, "a click reads, in combat too")
	world.combat = false
	world.now = world.now + 400
	RunBar(definition, M, button, 30)
	Check(world.reads == 3, "after combat the bar reads once its time is up")
end

-- A click frees memory: collectgarbage runs first. The block keeps it.
Check(block:find('collectgarbage("collect")', 1, true) ~= nil, "a click still frees unused memory")

print(("%d checks passed, %d failed"):format(passed, failures))
os.exit(failures == 0 and 0 or 1)
