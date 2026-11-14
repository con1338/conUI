-- Offline test for /eui perf, EldoUI's timing per module (review
-- verbesserungen.md, E2).
-- Run from the repository root:
--   lua5.1 tools/perf/test_perf.lua
-- It cuts the event dispatcher's RunHandler out of EldoUI/Core/Init.lua
-- (between fixed markers, so a renamed part makes the test fail instead of
-- testing a stale copy) and loads EldoUI/Core/Ticker.lua and
-- EldoUI/Core/Perf.lua as they are, with a clock the test moves itself.
-- Checked: switched off nothing is booked; switched on every handler and
-- ticker call is booked to its owner (module, core, a name, a ticker key)
-- with its time, calls and slowest call; a failing handler is still timed
-- and its error still reported; stopping in the middle of a handler is safe;
-- the results (order, share, per second, "+N more", total), stop, reset and
-- copy.
local ROOT = (arg and arg[0] or ""):match("^(.-)tools/perf/") or "./"

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

local init = ReadFile("EldoUI/Core/Init.lua")
local dispatchChunk = assert(loadstring(table.concat({
	"local E = ...",
	Between(init, "-- While /eui perf runs (Core/Perf.lua), probe(owner, event, ms)", "-- PLAYER_LOGIN runs in three phases", "Init.lua"),
	"return RunHandler",
}, "\n"), "=Init.lua parts"))
local tickerChunk = assert(loadstring(ReadFile("EldoUI/Core/Ticker.lua"), "=Ticker.lua"))
local perfChunk = assert(loadstring(ReadFile("EldoUI/Core/Perf.lua"), "=Perf.lua"))

---------------------------------------------------------------------------
-- The game around it
---------------------------------------------------------------------------
local world

function debugprofilestop() return world.clock end
function GetTime() return world.time end
function strtrim(text) return (text:gsub("^%s+", ""):gsub("%s+$", "")) end
function geterrorhandler() return function(err) table.insert(world.errors, tostring(err)) end end
function CreateFrame()
	local frame = { scripts = {} }
	function frame:SetScript(name, fn) self.scripts[name] = fn end
	function frame:GetScript(name) return self.scripts[name] end
	table.insert(world.frames, frame)
	return frame
end

local function Setup()
	world = { clock = 0, time = 1000, errors = {}, frames = {}, printed = {}, chat = {} }
	DEFAULT_CHAT_FRAME = { AddMessage = function(_, line) table.insert(world.chat, line) end }
	local L = setmetatable({}, { __index = function(_, key) return key end })
	local E = { L = L, commands = {} }
	function E:Print(line) table.insert(world.printed, line) end
	function E:AddCommand(name, usage, fn, group) self.commands[name] = { usage = usage, fn = fn, group = group } end
	function E:ShowCopyBox(title, help, text) world.copy = { title = title, help = help, text = text } end
	local RunHandler = dispatchChunk(E)
	tickerChunk(nil, E)
	perfChunk(nil, E)
	local test = { E = E, Run = RunHandler, Perf = E.Perf, ticker = world.frames[1] }
	-- A handler that takes `cost` ms on the clock.
	function test.Handler(cost, fail)
		return function()
			world.clock = world.clock + cost
			if fail then error("boom") end
		end
	end
	function test.Fire(owner, event, handler)
		test.Run({ [event] = { [owner] = handler } }, event, owner)
	end
	function test.Tick(elapsed) test.ticker.scripts.OnUpdate(test.ticker, elapsed) end
	function test.Command(arg)
		world.printed, world.chat = {}, {}
		E.commands.perf.fn(arg)
	end
	return test
end

---------------------------------------------------------------------------
-- Checks
---------------------------------------------------------------------------
local passed, failed = 0, 0
local function Check(ok, what)
	if ok then passed = passed + 1 else failed = failed + 1; print("FAIL: " .. what) end
end
local function Find(lines, needle)
	for _, line in ipairs(lines) do if line:find(needle, 1, true) then return line end end
end

-- Off: nothing is booked, handlers and ticker calls run as before.
do
	local test = Setup()
	local ran = 0
	test.Fire({ name = "InfoBar" }, "BAG_UPDATE", function() ran = ran + 1 end)
	test.E.Ticker:Subscribe("Bags:refresh", 0, function() ran = ran + 1 end)
	test.Tick(0.1)
	Check(ran == 2, "off: handlers and ticker calls run")
	Check(next(test.Perf.stats) == nil, "off: nothing booked")
	Check(test.E.commands.perf and test.E.commands.perf.group == "Tools", "the /eui perf command is registered under Tools")
end

-- On: every call booked to its owner.
do
	local test = Setup()
	local E, Perf = test.E, test.Perf
	test.Command("")
	Check(Perf.running and world.printed[1]:find("Timing each module now", 1, true), "/eui perf starts timing")
	local infobar, raidloot = { name = "InfoBar" }, { name = "RaidLoot" }
	test.Fire(infobar, "BAG_UPDATE", test.Handler(3))
	test.Fire(infobar, "PLAYER_MONEY", test.Handler(1))
	test.Fire(E, "PLAYER_ENTERING_WORLD", test.Handler(2))
	test.Fire("RaidLootPoints", "GUILD_ROSTER_UPDATE", test.Handler(0.5))
	-- A method name as the handler.
	raidloot.OnRoll = test.Handler(4)
	test.Run({ START_LOOT_ROLL = { [raidloot] = "OnRoll" } }, "START_LOOT_ROLL", raidloot)
	-- Ticker calls: with an owner, and without one (booked by the key's start).
	E.Ticker:Subscribe("InfoBar:holders", 0, test.Handler(0.25), infobar)
	E.Ticker:Subscribe("Bags:refresh", 0, test.Handler(0.75))
	test.Tick(0.1)
	test.Tick(0.1)
	local stats = Perf.stats
	Check(stats.InfoBar and math.abs(stats.InfoBar.ms - 4.5) < 1e-9 and stats.InfoBar.calls == 4, "module: events and ticker calls added up")
	Check(stats.InfoBar.peak == 3 and stats.InfoBar.peakLabel == "BAG_UPDATE", "module: slowest call and what it was")
	Check(stats.Core and stats.Core.ms == 2, "the core is booked as Core")
	Check(stats.RaidLootPoints and stats.RaidLootPoints.ms == 0.5, "a name an owner registered under")
	Check(stats.RaidLoot and stats.RaidLoot.ms == 4, "a method-name handler is timed")
	Check(stats.Bags and stats.Bags.ms == 1.5 and stats.Bags.peakLabel == "Bags:refresh", "a ticker call without owner: booked by its key")

	-- A failing handler is still timed; the error still goes to the error handler.
	test.Fire(raidloot, "LOOT_OPENED", test.Handler(1, true))
	Check(stats.RaidLoot.ms == 5 and stats.RaidLoot.calls == 2, "a failing handler is timed")
	Check(#world.errors == 1 and world.errors[1]:find("boom", 1, true), "its error is still reported")
	-- Stopping inside a handler is safe (the probe it started with books it).
	test.Fire(infobar, "PLAYER_LOGOUT", function()
		world.clock = world.clock + 1
		Perf.Stop()
	end)
	Check(not Perf.running and stats.InfoBar.calls == 5, "stopping inside a handler: that call is still booked, no error")
	test.Fire(infobar, "BAG_UPDATE", test.Handler(10))
	test.Tick(0.1)
	Check(stats.InfoBar.calls == 5 and stats.Bags.calls == 2, "stopped: nothing more is booked")
end

-- The results.
do
	local test = Setup()
	local Perf = test.Perf
	test.Command("")
	test.Fire({ name = "InfoBar" }, "BAG_UPDATE", test.Handler(30))
	test.Fire({ name = "InfoBar" }, "BAG_UPDATE", test.Handler(30))
	test.Fire({ name = "Chat" }, "CHAT_MSG_SAY", test.Handler(20))
	test.Fire(test.E, "PLAYER_REGEN_ENABLED", test.Handler(20))
	world.time = world.time + 125
	test.Command("")
	Check(world.printed[1] == "EldoUI timing, 2m measured (running):", "while running: heading (got " .. tostring(world.printed[1]) .. ")")
	local lines = world.chat
	Check(lines[1] == "   1. InfoBar: 0.48 ms/s (60%), 2 calls, slowest 30.00 ms (BAG_UPDATE)", "first row (got " .. tostring(lines[1]) .. ")")
	Check(lines[2] and lines[2]:find("2. Chat: 0.16 ms/s (20%)", 1, true) and lines[3]:find("3. Core: 0.16 ms/s (20%)", 1, true),
		"equal time: by name")
	Check(lines[#lines] == "   Total: 0.80 ms/s over 4 calls.", "total (got " .. tostring(lines[#lines]) .. ")")
	Check(Perf.running, "showing the results keeps timing")
	test.Command("copy")
	Check(world.copy and world.copy.title == "EldoUI timing" and world.copy.text:find("1. InfoBar", 1, true)
		and world.copy.text:find("Total:", 1, true), "copy: the results in the copy box")
	test.Command("stop")
	Check(not Perf.running and world.printed[1] == "EldoUI timing, 2m measured (stopped):", "stop: stops and shows the results")
	test.Command("stop")
	Check(world.printed[1] == "Timing is not running. /eui perf starts it.", "stop when not running: says so")
	test.Command("reset")
	Check(Perf.running and next(Perf.stats) == nil and world.printed[1] == "Timing started again from zero.", "reset: from zero")
	test.Command("")
	Check(world.chat[1] == "   Nothing measured yet.", "nothing measured: says so")
	Check(test.E.commands.perf.usage:find("stop | reset | copy", 1, true), "usage names the words")
end

-- Many owners: the twelve slowest and "+N more".
do
	local test = Setup()
	test.Command("")
	for index = 1, 15 do test.Fire({ name = ("Module%02d"):format(index) }, "EVENT", test.Handler(index)) end
	world.time = world.time + 10
	test.Command("")
	local lines = world.chat
	Check(lines[1]:find("1. Module15", 1, true) and lines[12]:find("12. Module04", 1, true), "the twelve slowest, slowest first")
	Check(lines[13] == "   +3 more", "+N more (got " .. tostring(lines[13]) .. ")")
	Check(Find(lines, "Total: 12.00 ms/s over 15 calls."), "the total counts every owner")
	Check(world.printed[1]:find("10s", 1, true), "seconds in the heading")
end

-- Owner names.
do
	local test = Setup()
	local Name = test.Perf.OwnerName
	Check(Name(test.E, "X") == "Core" and Name("Owner", "X") == "Owner" and Name({ name = "Bags" }, "X") == "Bags", "owner names")
	Check(Name(nil, "InfoBar:holders") == "InfoBar" and Name(nil, "plain") == "plain" and Name(nil, {}) == "?" and Name({}, nil) == "?",
		"names from ticker keys, else ?")
end

print(("%d checks passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
