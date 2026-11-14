-- Offline test for the cast bars on the party and raid frames (review
-- verbesserungen.md, B2).
-- Run from the repository root:
--   lua5.1 tools/groupframes/test_cast.lua
-- It loads EldoUI/Modules/GroupFrames/Cast.lua as it is, with stand-ins for
-- the game's cast API (plain or secret values, with or without the duration
-- object), the group frames' buttons and the module.
-- Checked: off by default and then deaf to the game; casts fill and
-- channels empty on plain times; with the duration object the client runs
-- the bar and nothing secret is compared or counted; the color for casts,
-- channels and casts that can't be interrupted (also secret, through the
-- client's color pick); a failed attempt at another spell leaves the bar;
-- the end hides it; a frame that gets another unit follows it; units
-- outside the group, pets and the tanks' targets are ignored; height and
-- spell name; the module off and a setting change.
local ROOT = (arg and arg[0] or ""):match("^(.-)tools/groupframes/") or "./"

local function ReadFile(path)
	local file = assert(io.open(ROOT .. path, "rb"), "can't open " .. path)
	local text = file:read("*a")
	file:close()
	return (text:gsub("\r\n", "\n"))
end
local castChunk = assert(loadstring(ReadFile("EldoUI/Modules/GroupFrames/Cast.lua"), "=GroupFrames/Cast.lua"))

---------------------------------------------------------------------------
-- The game
---------------------------------------------------------------------------
-- A secret value: any comparison or arithmetic on it fails, as in the game.
local SECRET_META = {
	__lt = function() error("compared a secret value") end, __le = function() error("compared a secret value") end,
	__eq = function() error("compared a secret value") end,
	__add = function() error("math on a secret value") end, __sub = function() error("math on a secret value") end,
	__div = function() error("math on a secret value") end, __mul = function() error("math on a secret value") end,
	__concat = function() error("joined a secret value") end,
}
local function Secret(name) return setmetatable({ secret = name }, SECRET_META) end
local function IsSecret(value) return getmetatable(value) == SECRET_META end

local world

function issecretvalue(value) return IsSecret(value) end
function GetTime() return world.now end
function UnitCastingInfo(unit)
	local cast = world.casts[unit]
	if not cast or cast.channel then return nil end
	return cast.name, nil, "icon", cast.startMS, cast.endMS, false, "castID", cast.locked, 123, 1
end
function UnitChannelInfo(unit)
	local cast = world.casts[unit]
	if not cast or not cast.channel then return nil end
	return cast.name, nil, "icon", cast.startMS, cast.endMS, false, cast.locked, 456, nil, nil, 1
end
Enum = { StatusBarTimerDirection = { RemainingTime = 1 } }

function CreateColor(r, g, b)
	local color = { r = r, g = g, b = b }
	function color:SetRGB(nr, ng, nb) self.r, self.g, self.b = nr, ng, nb end
	function color:GetRGB() return self.r, self.g, self.b end
	return color
end

local function NewRegion()
	local region = { shown = true }
	function region:SetPoint() end
	function region:ClearAllPoints() end
	function region:SetText(text) self.text = text end
	function region:SetShown(shown) self.shown = shown and true or false end
	return region
end

local function NewFrame()
	local frame = { shown = true, events = {} }
	function frame:SetScript(_, fn) self.onEvent = fn end
	function frame:RegisterEvent(event) self.events[event] = true end
	function frame:UnregisterAllEvents() self.events = {} end
	return frame
end
function CreateFrame() return NewFrame() end

function hooksecurefunc(target, name, hook)
	local original = target[name]
	target[name] = function(...)
		local results = { original(...) }
		hook(...)
		return unpack(results)
	end
end

local function NewBar()
	local bar = { shown = true, min = 0, max = 1, value = 0, level = 0 }
	function bar:SetMinMaxValues(low, high) self.min, self.max = low, high end
	function bar:SetValue(value) self.value = value end
	function bar:SetFrameLevel(level) self.level = level end
	function bar:SetStatusBarColor(r, g, b) self.color = { r, g, b } end
	function bar:ClearAllPoints() self.points = 0 end
	function bar:SetPoint() self.points = (self.points or 0) + 1 end
	function bar:SetHeight(height) self.height = height end
	function bar:Show() self.shown = true end
	function bar:Hide() self.shown = false end
	function bar:IsShown() return self.shown end
	if world.timer then
		function bar:SetTimerDuration(duration, interpolation, direction)
			self.timer = { duration = duration, direction = direction }
		end
	end
	return bar
end

local function NewButton(key, unit)
	local button = { headerKey = key, unit = unit, health = NewRegion() }
	function button:GetFrameLevel() return 5 end
	return button
end

local function Section(on, height, name)
	return { castbar = { enabled = on or false, height = height or 4, name = name or false } }
end

local function Setup(options)
	options = options or {}
	world = { now = 100, casts = {}, timer = options.timer, buttons = {}, ticker = {} }
	_G.UnitCastingDuration = options.timer and function(unit)
		local cast = world.casts[unit]
		return cast and not cast.channel and (cast.duration or "duration-" .. unit) or nil
	end or nil
	_G.UnitChannelDuration = options.timer and function(unit)
		local cast = world.casts[unit]
		return cast and cast.channel and (cast.duration or "channel-" .. unit) or nil
	end or nil
	C_CurveUtil = options.curve and { EvaluateColorFromBoolean = function(flag, yes, no)
		world.curveFlag = flag
		if IsSecret(flag) then return world.secretLocked and yes or no end
		return flag and yes or no
	end } or nil
	local M = { active = true, db = {
		party = Section(options.party), raid = Section(options.raid, options.height, options.name),
		raid25 = Section(), raid40 = Section(), tanks = Section(), pets = Section(true),
	} }
	function M:SettingsFor(key)
		if key == "tanktargets" then return self.db.tanks end
		return self.db[key]
	end
	function M.IterateButtons() return ipairs(world.buttons) end
	function M:OnEnable() end
	function M:OnDisable() end
	function M:OnProfileChanged() end
	local E = {
		media = { statusbar = "bar", flat = "flat" },
		Ticker = {
			Subscribe = function(_, key, period, fn) world.ticker[key] = fn end,
			Unsubscribe = function(_, key) world.ticker[key] = nil end,
			IsSubscribed = function(_, key) return world.ticker[key] ~= nil end,
		},
	}
	function E:GetModule(name) if name == "GroupFrames" then return M end end
	function E:CreateStatusBar() return NewBar() end
	function E:CreateText() return NewRegion() end
	function E:SetFont(text, size) text.fontSize = size end
	castChunk(nil, E)
	return { M = M, Cast = M.Cast }
end

local function Add(test, key, unit)
	local button = NewButton(key, unit)
	table.insert(world.buttons, button)
	test.M.CastUnitChanged(button)
	return button
end
local function Fire(test, event, unit)
	local listener = test.Cast.listener
	if listener.events[event] then listener.onEvent(listener, event, unit) end
end
local function Tick(seconds)
	world.now = world.now + seconds
	local fn = world.ticker["GroupFrames:cast"]
	if fn then fn(seconds) end
end
local function Shown(button) return button.eldoCast ~= nil and button.eldoCast.shown end
local function Near(a, b) return math.abs(a - b) < 1e-6 end

---------------------------------------------------------------------------
-- Checks
---------------------------------------------------------------------------
local passed, failed = 0, 0
local function Check(ok, what)
	if ok then passed = passed + 1 else failed = failed + 1; print("FAIL: " .. what) end
end

-- Off by default: deaf to the game, no bars.
do
	local test = Setup()
	local button = Add(test, "party", "party1")
	test.M:OnEnable()
	Check(not test.Cast.listening and next(test.Cast.listener.events) == nil, "off: nothing listens")
	world.casts.party1 = { name = "Heal", startMS = 100000, endMS = 102000 }
	test.Cast.OnEvent(nil, "UNIT_SPELLCAST_START", "party1")
	Check(button.eldoCast == nil, "off: no bar is made")
	Check(not test.Cast.AnyEnabled(), "off: no section wants cast bars (pets don't count)")
end

-- Plain times: a cast fills, ends on time.
do
	local test = Setup({ party = true })
	local button = Add(test, "party", "party1")
	test.M:OnEnable()
	Check(test.Cast.listening, "on: listening")
	local count = 0
	for _ in pairs(test.Cast.listener.events) do count = count + 1 end
	Check(count == #test.Cast.EVENTS and count == 10, "on: the ten cast events")
	world.casts.party1 = { name = "Heal", startMS = 100000, endMS = 102000, locked = false }
	Fire(test, "UNIT_SPELLCAST_START", "party1")
	local bar = button.eldoCast
	Check(Shown(button) and bar.height == 4 and bar.level == 11, "a cast shows a 4 px bar over the frame")
	Check(Near(bar.max, 2) and bar.value == 0, "plain times: 2 s, from empty")
	Check(bar.color[1] == 1 and bar.color[2] == 0.7, "cast color")
	Check(not bar.text.shown, "no name on a 4 px bar")
	Check(world.ticker["GroupFrames:cast"] ~= nil, "plain times: the ticker runs")
	Tick(0.5)
	Check(Near(bar.value, 0.5), "the cast fills with time")
	-- A failed attempt at another spell: the cast still runs.
	Fire(test, "UNIT_SPELLCAST_FAILED", "party1")
	Check(Shown(button), "a failed attempt at another spell leaves the bar")
	Tick(1.6)
	Check(not Shown(button) and world.ticker["GroupFrames:cast"] == nil, "the time is up: hidden, ticker stopped")
	-- Stop before the end.
	world.now = 200
	world.casts.party1 = { name = "Heal", startMS = 200000, endMS = 203000 }
	Fire(test, "UNIT_SPELLCAST_START", "party1")
	world.casts.party1 = nil
	Fire(test, "UNIT_SPELLCAST_STOP", "party1")
	Check(not Shown(button), "the cast ended: hidden")
	-- Channels empty.
	world.casts.party1 = { name = "Drain", channel = true, startMS = 200000, endMS = 204000 }
	Fire(test, "UNIT_SPELLCAST_CHANNEL_START", "party1")
	Check(Shown(button) and Near(bar.value, 4) and bar.color[2] == 0.8, "a channel starts full, in the channel color")
	Tick(1)
	Check(Near(bar.value, 3), "a channel empties")
	-- Can't be interrupted: gray (plain flag, no color pick from the client).
	world.casts.party1 = { name = "Shield", startMS = 201000, endMS = 203000, locked = true }
	Fire(test, "UNIT_SPELLCAST_START", "party1")
	Check(bar.color[1] == 0.55, "a cast that can't be interrupted is gray")
	Fire(test, "UNIT_SPELLCAST_INTERRUPTIBLE", "party1")
	Check(Shown(button), "an interruptible change reads the cast again")
	-- Secret times without the duration object: no bar (nothing to count with).
	world.casts.party1 = { name = Secret("name"), startMS = Secret("start"), endMS = Secret("end"), locked = false }
	local ok = pcall(Fire, test, "UNIT_SPELLCAST_START", "party1")
	Check(ok and not Shown(button), "secret times and no duration object: hidden, no error")
end

-- The duration object: the client runs the bar, secrets stay untouched.
do
	local test = Setup({ party = true, timer = true, curve = true })
	local button = Add(test, "party", "party2")
	test.M:OnEnable()
	local duration = Secret("duration")
	world.casts.party2 = { name = Secret("name"), startMS = Secret("start"), endMS = Secret("end"), locked = Secret("locked"),
		duration = duration }
	world.secretLocked = true
	local ok, err = pcall(Fire, test, "UNIT_SPELLCAST_START", "party2")
	Check(ok, "secret cast: no error (" .. tostring(err) .. ")")
	local bar = button.eldoCast
	Check(Shown(button) and bar.timer and rawequal(bar.timer.duration, duration), "secret cast: the client runs the bar on the duration object")
	Check(world.ticker["GroupFrames:cast"] == nil, "secret cast: no ticker")
	Check(IsSecret(world.curveFlag) and bar.color[1] == 0.55, "secret flag: the client picks the gray")
	world.casts.party2 = { name = "Drain", channel = true, startMS = 1, endMS = 2, locked = false, duration = "channel" }
	Fire(test, "UNIT_SPELLCAST_CHANNEL_START", "party2")
	Check(bar.timer.direction == 1 and bar.color[2] == 0.8, "a channel runs down (remaining time)")
end

-- Units and frames.
do
	local test = Setup({ party = true, raid = true, height = 10, name = true })
	local party = Add(test, "party", "party1")
	local raid = Add(test, "raid", "raid7")
	local pet = Add(test, "pets", "raid7pet")
	local target = Add(test, "tanktargets", "raid7target")
	test.M:OnEnable()
	world.casts.raid7 = { name = "Fireball", startMS = 100000, endMS = 103000 }
	Fire(test, "UNIT_SPELLCAST_START", "raid7")
	local bar = raid.eldoCast
	Check(Shown(raid) and bar.height == 10 and bar.text.shown and bar.text.text == "Fireball", "raid frame: 10 px with the spell name")
	Check(bar.text.fontSize == 9, "the name fits the bar")
	Check(pet.eldoCast == nil and target.eldoCast == nil, "pets and the tanks' targets: no bar")
	world.casts.target = { name = "Frostbolt", startMS = 100000, endMS = 103000 }
	Fire(test, "UNIT_SPELLCAST_START", "target")
	Fire(test, "UNIT_SPELLCAST_START", "nameplate1")
	Fire(test, "UNIT_SPELLCAST_START", Secret("unit"))
	Check(not Shown(party), "units outside the group are ignored")
	-- The header gives the party frame another unit (roster change in combat).
	world.casts.party2 = { name = "Smite", startMS = 100000, endMS = 101000 }
	party.unit = "party2"
	test.M.CastUnitChanged(party)
	Check(Shown(party) and party.eldoCast.unit == "party2", "another unit: its cast shows at once")
	world.casts.party1 = { name = "Old", startMS = 100000, endMS = 109000 }
	Fire(test, "UNIT_SPELLCAST_START", "party1")
	Check(party.eldoCast.unit == "party2", "the old unit's events no longer reach the frame")
	world.casts.party2 = nil
	party.unit = nil
	test.M.CastUnitChanged(party)
	Check(not Shown(party), "no unit: hidden")
	-- A setting change and the module off.
	test.M.db.raid.castbar.name = false
	test.M:OnProfileChanged()
	Check(Shown(raid) and not raid.eldoCast.text.shown, "setting change: the name goes at once")
	test.M.db.party.castbar.enabled, test.M.db.raid.castbar.enabled = false, false
	test.M:OnProfileChanged()
	Check(not test.Cast.listening and not Shown(raid), "all sections off: hidden and deaf again")
	test.M.db.raid.castbar.enabled = true
	test.M:OnProfileChanged()
	Check(test.Cast.listening and Shown(raid), "back on: the running cast shows again")
	test.M.active = false
	test.M:OnDisable()
	Check(not test.Cast.listening and not Shown(raid) and next(test.Cast.listener.events) == nil, "module off: hidden and deaf")
end

print(("%d checks passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
