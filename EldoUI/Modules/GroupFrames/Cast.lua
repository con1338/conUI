-- EldoUI Party and Raid: cast bars on the group frames.
--
-- A thin bar at the bottom of a member's frame shows what they cast while
-- it runs: casts fill, channels empty, a cast that can't be interrupted is
-- gray. Per section (party, the raid sizes, main tanks), on the Bars rows:
-- "Cast bar", its height and the spell name on it. Off by default; while no
-- section has it on, nothing here listens to the game.
--
-- How it reads the game: one frame hears the UNIT_SPELLCAST_* events of
-- your group (you on your own party frame, party1-4, raid1-40) and finds
-- the frames that show that unit. GroupFrames' SetUnit tells this file
-- when a frame gets another unit (M.CastUnitChanged), so the index stays
-- right when the roster changes in combat. Every event reads the unit's
-- cast again (UnitCastingInfo, then UnitChannelInfo): a start shows it, an
-- end with nothing left hides it, and a failed attempt at another spell
-- during a cast leaves the bar as it is.
--
-- Secret values: in combat the game may hand the name, the times and the
-- "can't interrupt" flag as secret values. The bar then runs on the game's
-- duration object (SetTimerDuration), the color comes from
-- C_CurveUtil.EvaluateColorFromBoolean, and nothing secret is tested,
-- compared or used in math. Only without a duration object does the bar run
-- on plain start and end times, from the shared ticker.
-- Pets and the main tanks' targets show no cast bar (their units hear no
-- cast events of their own).
local _, E = ...
local M = E:GetModule("GroupFrames")
if not M then return end

local Cast = {
	byUnit = {},                                     -- unit -> { [button] = true }
	unitOf = setmetatable({}, { __mode = "k" }),     -- button -> the unit it is indexed under
	running = setmetatable({}, { __mode = "k" }),    -- bar -> true while it runs on plain times
	listening = false,
}
M.Cast = Cast

local issecret = _G.issecretvalue or function() return false end
local function Present(value) return issecret(value) or value ~= nil end
local function Plain(value) if issecret(value) then return nil end return value end

Cast.COLORS = { cast = { 1, 0.7, 0 }, channel = { 0.3, 0.8, 0.35 }, locked = { 0.55, 0.55, 0.55 } }
local TICK_KEY = "GroupFrames:cast"

local EVENTS = {
	"UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED",
	"UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_UPDATE",
	"UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_INTERRUPTIBLE", "UNIT_SPELLCAST_NOT_INTERRUPTIBLE",
}
Cast.EVENTS = EVENTS

-- The units whose casts can show: you, the party, the raid.
local GROUP_UNITS = { player = true }
for index = 1, 4 do GROUP_UNITS["party" .. index] = true end
for index = 1, 40 do GROUP_UNITS["raid" .. index] = true end

-- The section settings of a frame's cast bar when it is on, else nil.
function Cast.Settings(button)
	local key = button.headerKey
	if not key or key == "pets" or key == "tanktargets" then return nil end
	local db = M:SettingsFor(key)
	local cast = type(db) == "table" and type(db.castbar) == "table" and db.castbar
	if cast and cast.enabled then return cast end
	return nil
end

-- Is the cast bar on in any section?
function Cast.AnyEnabled()
	local db = M.db
	if not db then return false end
	for _, key in ipairs({ "party", "raid", "raid25", "raid40", "tanks" }) do
		local section = db[key]
		if type(section) == "table" and type(section.castbar) == "table" and section.castbar.enabled then return true end
	end
	return false
end

-- A frame's bar, made the first time it is needed.
function Cast.Bar(button)
	local bar = button.eldoCast
	if bar then return bar end
	-- EldoUI's bar: the chosen bar texture (it follows a change) on a box.
	bar = E:CreateStatusBar(button)
	bar:SetMinMaxValues(0, 1)
	bar:SetValue(0)
	bar:SetFrameLevel(button:GetFrameLevel() + 6)
	bar.text = E:CreateText(bar, 9, "LEFT")
	bar.text:SetPoint("LEFT", 2, 0)
	bar.text:SetPoint("RIGHT", -2, 0)
	bar.normalColor, bar.lockedColor = CreateColor(1, 1, 1), CreateColor(1, 1, 1)
	bar.button = button
	bar:Hide()
	button.eldoCast = bar
	return bar
end

-- Size and place from the section settings: along the bottom of the
-- health bar, inside the frame (the frame keeps its size).
function Cast.Layout(bar, cast)
	local button = bar.button
	local height = math.max(1, math.min(tonumber(cast.height) or 4, 20))
	local anchor = button.health or button
	bar:ClearAllPoints()
	bar:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", 0, 0)
	bar:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", 0, 0)
	bar:SetHeight(height)
	bar.showName = cast.name and height >= 8 or false
	bar.text:SetShown(bar.showName)
	if bar.showName then E:SetFont(bar.text, math.max(7, math.min(height - 1, 12))) end
end

-- Cast or channel color, gray when the cast can't be interrupted. The flag
-- may be secret: the client picks the color, or a protected test does.
function Cast.Color(bar, channel, notInterruptible)
	local normal, locked = channel and Cast.COLORS.channel or Cast.COLORS.cast, Cast.COLORS.locked
	bar.normalColor:SetRGB(normal[1], normal[2], normal[3])
	bar.lockedColor:SetRGB(locked[1], locked[2], locked[3])
	local curve = _G.C_CurveUtil
	if curve and curve.EvaluateColorFromBoolean then
		local ok, color = pcall(curve.EvaluateColorFromBoolean, notInterruptible, bar.lockedColor, bar.normalColor)
		if ok and color then
			pcall(bar.SetStatusBarColor, bar, color:GetRGB())
			return
		end
	end
	local isLocked = false
	pcall(function() isLocked = notInterruptible and true or false end)
	bar:SetStatusBarColor((isLocked and bar.lockedColor or bar.normalColor):GetRGB())
end

function Cast.Hide(bar)
	Cast.running[bar] = nil
	bar.startTime, bar.endTime = nil, nil
	bar:Hide()
	if not next(Cast.running) then E.Ticker:Unsubscribe(TICK_KEY) end
end

-- Plain times: the bar's value from the clock; done when the time is up.
function Cast.Step(bar)
	local now = GetTime()
	if not bar.endTime or now >= bar.endTime then
		Cast.Hide(bar)
		return
	end
	local total, spent = bar.endTime - bar.startTime, now - bar.startTime
	bar:SetValue(bar.channel and (total - spent) or spent)
end

function Cast.Tick()
	for bar in pairs(Cast.running) do Cast.Step(bar) end
end

-- Read the unit's cast and show it on the frame, or hide the bar.
function Cast.Update(button)
	local bar = button.eldoCast
	local cast = M.active and Cast.listening and button.unit and Cast.Settings(button)
	if not cast then
		if bar then Cast.Hide(bar) end
		return
	end
	local unit = button.unit
	-- UnitCastingInfo: notInterruptible 8th; UnitChannelInfo: 7th.
	local channel, notInterruptible = false, nil
	local ok, name, _, _, startMS, endMS, _, _, eighth = pcall(UnitCastingInfo, unit)
	if ok and Present(name) then
		notInterruptible = eighth
	else
		local seventh
		ok, name, _, _, startMS, endMS, _, seventh = pcall(UnitChannelInfo, unit)
		if not (ok and Present(name)) then
			if bar then Cast.Hide(bar) end
			return
		end
		channel, notInterruptible = true, seventh
	end
	bar = Cast.Bar(button)
	Cast.Layout(bar, cast)
	bar.unit, bar.channel = unit, channel
	bar.text:SetText(bar.showName and name or "")
	Cast.Color(bar, channel, notInterruptible)
	-- The game's duration object first: it runs with secret times.
	local durationFn = channel and _G.UnitChannelDuration or _G.UnitCastingDuration
	if durationFn and bar.SetTimerDuration then
		local okDuration, duration = pcall(durationFn, unit)
		if okDuration and Present(duration) then
			local direction = channel and Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.RemainingTime
			if not pcall(bar.SetTimerDuration, bar, duration, nil, direction) then pcall(bar.SetTimerDuration, bar, duration) end
			Cast.running[bar] = nil
			bar.startTime, bar.endTime = nil, nil
			bar:Show()
			return
		end
	end
	local start, stop = Plain(startMS), Plain(endMS)
	if type(start) ~= "number" or type(stop) ~= "number" or stop <= start then
		Cast.Hide(bar)
		return
	end
	bar.startTime, bar.endTime = start / 1000, stop / 1000
	bar:SetMinMaxValues(0, bar.endTime - bar.startTime)
	bar:Show()
	Cast.running[bar] = true
	if not E.Ticker:IsSubscribed(TICK_KEY) then E.Ticker:Subscribe(TICK_KEY, 0, Cast.Tick, M) end
	Cast.Step(bar)
end

-- Keep the index of which frame shows which unit (from GroupFrames' SetUnit).
function M.CastUnitChanged(button)
	local old = Cast.unitOf[button]
	if old and Cast.byUnit[old] then Cast.byUnit[old][button] = nil end
	local unit = button.unit
	Cast.unitOf[button] = unit
	if unit then
		Cast.byUnit[unit] = Cast.byUnit[unit] or setmetatable({}, { __mode = "k" })
		Cast.byUnit[unit][button] = true
	end
	if Cast.listening or button.eldoCast then Cast.Update(button) end
end

function Cast.OnEvent(_, _, unit)
	unit = Plain(unit)
	if type(unit) ~= "string" or not GROUP_UNITS[unit] then return end
	for button in pairs(Cast.byUnit[unit] or {}) do
		if button.unit == unit then Cast.Update(button) end
	end
end

local listener = CreateFrame("Frame")
listener:SetScript("OnEvent", Cast.OnEvent)
Cast.listener = listener

-- Listen while the module is on and a section wants cast bars; redraw
-- every frame (settings may have changed).
function Cast.Sync()
	local want = M.active and Cast.AnyEnabled() or false
	if want ~= Cast.listening then
		Cast.listening = want
		if want then
			for _, event in ipairs(EVENTS) do pcall(listener.RegisterEvent, listener, event) end
		else
			listener:UnregisterAllEvents()
		end
	end
	for _, button in M.IterateButtons() do
		if Cast.unitOf[button] ~= button.unit then M.CastUnitChanged(button) else Cast.Update(button) end
	end
end

hooksecurefunc(M, "OnEnable", function() Cast.Sync() end)
hooksecurefunc(M, "OnDisable", function() Cast.Sync() end)
hooksecurefunc(M, "OnProfileChanged", function() Cast.Sync() end)
