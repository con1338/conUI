-- Load all of EldoUI offline and run its start, with a stand-in for the game
-- (tools/harness/wow.lua). Run from the repository root:
--   lua5.1 tools/harness/load_eldoui.lua [--all]
--
-- 1. Every file of EldoUI/EldoUI.toc, in its order, as the game loads them:
--    each with the addon's name and the shared private table.
-- 2. ADDON_LOADED, PLAYER_LOGIN (the modules start) and
--    PLAYER_ENTERING_WORLD, as on a first log-in with no saved settings.
-- 3. The C_Timer callbacks that start (a few rounds deep).
-- Every error is collected: at load (with the file), in an event handler or
-- a timer (EldoUI reports those through geterrorhandler, as in the game).
-- The same error is listed once with its count. Exit code 1 when there is
-- any. --all lists every error instead of the first 60.
--
-- What this finds: code that fails in a fresh install's start, a module
-- that breaks the others, calls into names that don't exist. What it can't:
-- anything that depends on the game's real answers or on drawing.
local ROOT = (arg and arg[0] or ""):match("^(.-)tools/harness/") or "./"
local SHOW_ALL = false
for _, value in ipairs(arg or {}) do if value == "--all" then SHOW_ALL = true end end

local function ReadFile(path)
	local file = assert(io.open(ROOT .. path, "rb"), "can't open " .. path)
	local text = file:read("*a")
	file:close()
	return (text:gsub("\r\n", "\n"))
end

local World = dofile(ROOT .. "tools/harness/wow.lua")
World.globalNames = dofile(ROOT .. "tools/ci/globals.lua")
World.Install()

-- The TOC's files, in order.
local files = {}
for line in ReadFile("EldoUI/EldoUI.toc"):gmatch("[^\n]+") do
	line = line:gsub("^%s+", ""):gsub("%s+$", "")
	if line ~= "" and not line:find("^#") then files[#files + 1] = (line:gsub("\\", "/")) end
end

local started = os.clock()
local ns = {}
World.phase = "load"
for _, file in ipairs(files) do
	local chunk, err = loadfile(ROOT .. "EldoUI/" .. file)
	if not chunk then
		World.Record(err)
	else
		local ok, runErr = pcall(chunk, "EldoUI", ns)
		if not ok then World.Record(runErr) end
	end
end
local loadErrors = #World.errors

World.phase = "ADDON_LOADED"
World.Fire("ADDON_LOADED", "EldoUI")
World.phase = "PLAYER_LOGIN"
World.loggedIn = true
World.Fire("PLAYER_LOGIN")
World.phase = "PLAYER_ENTERING_WORLD"
World.Fire("PLAYER_ENTERING_WORLD", true, false)
World.phase = "timers"
World.RunTimers(5)

---------------------------------------------------------------------------
-- Report
---------------------------------------------------------------------------
local modules, active = 0, 0
for _, module in pairs(type(ns.modules) == "table" and ns.modules or {}) do
	if type(module) == "table" then
		modules = modules + 1
		if rawget(module, "active") then active = active + 1 end
	end
end

-- The same error (phase and message, without the repository path) once.
local unique, order = {}, {}
for _, entry in ipairs(World.errors) do
	local message = entry.message:gsub(ROOT:gsub("%p", "%%%0"), "")
	local key = entry.phase .. "\1" .. message
	if not unique[key] then
		unique[key] = { phase = entry.phase, message = message, count = 0 }
		order[#order + 1] = key
	end
	unique[key].count = unique[key].count + 1
end

print(("EldoUI offline start: %d files, %d modules (%d on), %.1f s"):format(#files, modules, active, os.clock() - started))
print(("errors: %d at load, %d after (%d different)"):format(loadErrors, #World.errors - loadErrors, #order))
local shown = SHOW_ALL and #order or math.min(#order, 60)
for index = 1, shown do
	local entry = unique[order[index]]
	local first = entry.message:match("^[^\n]*")
	print(("  [%s] %s%s"):format(entry.phase, first, entry.count > 1 and (" (x%d)"):format(entry.count) or ""))
end
if shown < #order then print(("  ... %d more (--all lists them)"):format(#order - shown)) end
os.exit(#World.errors == 0 and 0 or 1)
