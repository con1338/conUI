-- EldoUI timing per module (/eui perf).
--
--   /eui perf          start timing; while it runs, show what it measured so far
--   /eui perf stop     stop and show the results
--   /eui perf reset    start again from zero
--   /eui perf copy     the results in a box to copy (for a bug report)
--
-- While it runs, each event handler EldoUI's dispatcher calls (E:RegisterEvent,
-- E:RegisterUnitEvent and every module's events, Core/Init.lua) and each call
-- of the shared ticker (E.Ticker, Core/Ticker.lua) is timed with
-- debugprofilestop() and booked to its owner: a module by its name, "Core"
-- for EldoUI's core, or the name a part registered under (a ticker call
-- without an owner goes to the start of its key, "InfoBar:holders" ->
-- "InfoBar"). The list shows the owners that took the most time: time per
-- second of play, share, calls and the slowest call with what it was.
--
-- Off by default; switched off, the dispatcher and the ticker check one value
-- per call and nothing else. Times are inclusive: a handler that makes the
-- game fire another event pays for that event's handlers too. Not measured:
-- frame scripts a module sets on its own frames (OnUpdate, OnEvent), hooks on
-- the game's functions, secure snippets, and the game's own drawing.
local _, E = ...
local L = E.L

local MAX_ROWS = 12

local Perf = { stats = {}, running = false }
E.Perf = Perf

-- The name an owner is booked under.
function Perf.OwnerName(owner, label)
	if owner == E then return "Core" end
	if type(owner) == "string" and owner ~= "" then return owner end
	if type(owner) == "table" then
		local name = rawget(owner, "name")
		if type(name) == "string" and name ~= "" then return name end
	end
	if type(label) == "string" and label ~= "" then return label:match("^([^:]+)") or label end
	return "?"
end

-- The probe the dispatcher and the ticker call: one handler or call took ms.
function Perf.Record(owner, label, ms)
	if type(ms) ~= "number" or ms ~= ms then return end
	local name = Perf.OwnerName(owner, label)
	local entry = Perf.stats[name]
	if not entry then
		entry = { ms = 0, calls = 0, peak = -1 }
		Perf.stats[name] = entry
	end
	entry.ms = entry.ms + ms
	entry.calls = entry.calls + 1
	if ms > entry.peak then entry.peak, entry.peakLabel = ms, label end
end

function Perf.Start()
	Perf.stats, Perf.started, Perf.stopped, Perf.running = {}, GetTime(), nil, true
	E:SetEventProbe(Perf.Record)
	E.Ticker:SetProbe(Perf.Record)
end

function Perf.Stop()
	if not Perf.running then return false end
	E:SetEventProbe(nil)
	E.Ticker:SetProbe(nil)
	Perf.running, Perf.stopped = false, GetTime()
	return true
end

-- Seconds measured: up to now while running, else up to the stop.
function Perf.Seconds()
	if not Perf.started then return 0 end
	return math.max(0, (Perf.running and GetTime() or Perf.stopped or GetTime()) - Perf.started)
end

local function Duration(seconds)
	seconds = math.floor(seconds)
	if seconds < 60 then return L["%ds"]:format(seconds) end
	if seconds < 3600 then return L["%dm"]:format(math.floor(seconds / 60)) end
	return L["%dh %dm"]:format(math.floor(seconds / 3600), math.floor(seconds % 3600 / 60))
end

-- The results as lines: a heading, the owners that took the most time, a total.
function Perf.Lines()
	local rows, total, calls = {}, 0, 0
	for name, entry in pairs(Perf.stats) do
		rows[#rows + 1] = { name = name, entry = entry }
		total, calls = total + entry.ms, calls + entry.calls
	end
	table.sort(rows, function(a, b)
		if a.entry.ms ~= b.entry.ms then return a.entry.ms > b.entry.ms end
		return a.name < b.name
	end)
	local seconds = Perf.Seconds()
	local lines = { L["EldoUI timing, %s measured (%s):"]:format(Duration(seconds), Perf.running and L["running"] or L["stopped"]) }
	if #rows == 0 then
		lines[2] = L["Nothing measured yet."]
		return lines
	end
	local per = math.max(seconds, 1)
	for index = 1, math.min(#rows, MAX_ROWS) do
		local row = rows[index]
		local entry = row.entry
		local share = total > 0 and math.floor(entry.ms / total * 100 + 0.5) or 0
		lines[#lines + 1] = L["%d. %s: %.2f ms/s (%d%%), %d calls, slowest %.2f ms (%s)"]:format(index, row.name, entry.ms / per,
			share, entry.calls, math.max(entry.peak, 0), tostring(entry.peakLabel or "?"))
	end
	if #rows > MAX_ROWS then lines[#lines + 1] = L["+%d more"]:format(#rows - MAX_ROWS) end
	lines[#lines + 1] = L["Total: %.2f ms/s over %d calls."]:format(total / per, calls)
	return lines
end

function Perf.Print()
	local lines = Perf.Lines()
	E:Print(lines[1])
	local frame = _G.DEFAULT_CHAT_FRAME
	if not (frame and frame.AddMessage) then return end
	for index = 2, #lines do frame:AddMessage("   " .. lines[index]) end
end

E:AddCommand("perf", "[stop | reset | copy]  time each module's events and timers; once started, /eui perf shows what it measured", function(arg)
	arg = strtrim(arg or ""):lower()
	if arg == "stop" then
		if not Perf.Stop() then
			E:Print(L["Timing is not running. /eui perf starts it."])
			return
		end
		Perf.Print()
	elseif arg == "reset" then
		Perf.Start()
		E:Print(L["Timing started again from zero."])
	elseif arg == "copy" then
		E:ShowCopyBox(L["EldoUI timing"], L["Selected: press Ctrl+C and paste it into your bug report."], table.concat(Perf.Lines(), "\n"))
	elseif Perf.running then
		Perf.Print()
	else
		Perf.Start()
		E:Print(L["Timing each module now. /eui perf shows the results, /eui perf stop ends it."])
	end
end, "Tools")
