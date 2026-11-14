-- Offline test for the hook on Blizzard's nameplate driver (review F17,
-- second open part).
-- Run from the repository root:
--   lua5.1 tools/nameplates/test_driver_hook.lua
-- It cuts the real block out of EldoUI/Modules/Nameplates.lua (between fixed
-- markers, so a renamed part makes the test fail instead of testing a stale
-- copy) and runs it with a model of hooksecurefunc and E:OnBlizzardAddOn.
-- Checked: the driver is hooked exactly once, whether it exists when the
-- file loads (with or without Blizzard_NamePlates counted as loaded) or only
-- after Blizzard_NamePlates loads; no hook and no error without a driver.
local ROOT = (arg and arg[0] or ""):match("^(.-)tools/nameplates/") or "./"

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

local nameplates = ReadFile("EldoUI/Modules/Nameplates.lua")
local block = Between(nameplates, "-- Blizzard's plate code (Blizzard_NamePlates) may load after this file:",
	"-- Settings or switches changed: quiet frames", "Nameplates.lua")
local chunk = assert(loadstring("local E, OnBlizzardAdded = ...\n" .. block, "=extracted"))

---------------------------------------------------------------------------
-- Model
---------------------------------------------------------------------------
local world

function hooksecurefunc(target, method, fn)
	assert(type(target) == "table" and type(method) == "string" and type(fn) == "function", "hooksecurefunc arguments")
	local original = target[method]
	assert(type(original) == "function", "hooking a missing method")
	world.hooks = world.hooks + 1
	target[method] = function(...)
		local result = original(...)
		fn(...)
		return result
	end
end

local function NewDriver()
	local driver = { calls = 0 }
	function driver:OnNamePlateAdded() self.calls = self.calls + 1 end
	return driver
end

-- options.driver: NamePlateDriverFrame when the file loads; options.loaded:
-- whether Blizzard_NamePlates counts as loaded then.
local function Load(options)
	world = { hooks = 0, added = {}, waiting = {} }
	_G.NamePlateDriverFrame = options.driver
	local E = {}
	function E:OnBlizzardAddOn(addon, fn)
		if options.loaded then fn() return end
		world.waiting[addon] = world.waiting[addon] or {}
		table.insert(world.waiting[addon], fn)
	end
	chunk(E, function(unit) world.added[#world.added + 1] = unit end)
end

-- Blizzard_NamePlates loads (ADDON_LOADED), maybe creating the driver.
local function AddOnLoaded(driver)
	if driver then _G.NamePlateDriverFrame = driver end
	for _, fn in ipairs(world.waiting.Blizzard_NamePlates or {}) do fn() end
	world.waiting.Blizzard_NamePlates = nil
end

---------------------------------------------------------------------------
-- Checks
---------------------------------------------------------------------------
local passed, failed = 0, 0
local function Check(ok, what)
	if ok then passed = passed + 1 else failed = failed + 1; print("FAIL: " .. what) end
end

-- Driver there and addon loaded when the file loads.
do
	local driver = NewDriver()
	Load({ driver = driver, loaded = true })
	Check(world.hooks == 1, "driver at load, addon loaded: hooked once")
	driver:OnNamePlateAdded("nameplate1")
	Check(driver.calls == 1, "Blizzard's own OnNamePlateAdded still runs")
	Check(world.added[1] == "nameplate1" and #world.added == 1, "the hook gets the unit")
end

-- Driver there, but the addon not counted as loaded (the driver is part of
-- the game's base UI): hooked at load, not again when the addon shows up.
do
	local driver = NewDriver()
	Load({ driver = driver, loaded = false })
	Check(world.hooks == 1, "driver at load, addon not loaded: hooked at once")
	AddOnLoaded()
	Check(world.hooks == 1, "driver at load: not hooked again when the addon loads")
	driver:OnNamePlateAdded("nameplate2")
	Check(#world.added == 1 and world.added[1] == "nameplate2", "one call per plate, not two")
end

-- The addon loads after this file and brings the driver.
do
	Load({ driver = nil, loaded = false })
	Check(world.hooks == 0, "no driver at load: not hooked yet")
	local driver = NewDriver()
	AddOnLoaded(driver)
	Check(world.hooks == 1, "driver from the addon: hooked when it loads")
	driver:OnNamePlateAdded("nameplate3")
	Check(world.added[1] == "nameplate3", "late hook gets the unit")
end

-- No driver at all, or one without OnNamePlateAdded.
do
	Load({ driver = nil, loaded = true })
	Check(world.hooks == 0, "no driver, addon loaded: no hook, no error")
	Load({ driver = nil, loaded = false })
	AddOnLoaded()
	Check(world.hooks == 0, "addon loads without a driver: no hook, no error")
	Load({ driver = {}, loaded = true })
	Check(world.hooks == 0, "driver without OnNamePlateAdded: no hook")
end

_G.NamePlateDriverFrame = nil
print(("%d checks passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
