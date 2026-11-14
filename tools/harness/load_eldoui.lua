-- Load all of EldoUI offline and run its start, with a stand-in for the game
-- (tools/harness/wow.lua). Run from the repository root:
--   lua5.1 tools/harness/load_eldoui.lua [--locale deDE] [--extra FILE] [--all]
--
-- 1. EldoUI as the game loads it: every file of EldoUI/EldoUI.toc in order,
--    each with the addon's name and the shared private table, then
--    ADDON_LOADED. Then the add-ons that load with it (EldoUI_GroupBoard),
--    each the same way. Add-ons that load on demand (the language packs,
--    the Loot Guide's data) load when EldoUI asks for them
--    (C_AddOns.LoadAddOn), from their own TOC files.
-- 2. PLAYER_LOGIN (the modules start) and PLAYER_ENTERING_WORLD, as on a
--    first log-in with no saved settings.
-- 3. The C_Timer callbacks that start (a few rounds deep).
-- Every error is collected: at load, in an event handler or a timer (EldoUI
-- reports those through geterrorhandler, as in the game). The same error is
-- listed once with its count. Exit code 1 when there is any.
--
--   --locale deDE  the client's language (default enUS): EldoUI then loads
--                  that language pack itself
--   --extra FILE   one more file loaded as part of EldoUI, after its own
--                  (tools/harness/test_harness.lua uses it)
--   --all          list every error, not the first 60
--
-- What this finds: code that fails in a fresh install's start, a module
-- that breaks the others, calls into names that don't exist, a language pack
-- that doesn't load. What it can't: anything that depends on the game's real
-- answers or on drawing.
local ROOT = (arg and arg[0] or ""):match("^(.-)tools/harness/") or "./"
local options = { all = false, locale = "enUS" }
do
	local index = 1
	while arg and arg[index] do
		local value = arg[index]
		if value == "--all" then
			options.all = true
		elseif value == "--locale" then
			index = index + 1
			options.locale = arg[index]
		elseif value == "--extra" then
			index = index + 1
			options.extra = arg[index]
		end
		index = index + 1
	end
end

local World = dofile(ROOT .. "tools/harness/wow.lua")
World.root = ROOT
World.locale = options.locale
World.globalNames = dofile(ROOT .. "tools/ci/globals.lua")

-- The add-on folders: EldoUI and every EldoUI_* next to it.
assert(World.AddAddon("EldoUI"), "EldoUI/EldoUI.toc not found")
local listing = io.popen and io.popen('ls -d "' .. ROOT .. '"EldoUI_*/ 2>/dev/null')
if listing then
	for line in listing:lines() do
		local name = line:match("(EldoUI_[%w_]+)/?$")
		if name then World.AddAddon(name) end
	end
	listing:close()
end

-- --extra: one more file, run as part of EldoUI after its own files.
if options.extra then
	World.afterFiles = function(name, ns)
		if name ~= "EldoUI" then return end
		local chunk, err = loadfile(options.extra)
		if not chunk then World.Record(err) return end
		local ok, runErr = pcall(chunk, name, ns)
		if not ok then World.Record(runErr) end
	end
end

World.Install()

local started = os.clock()
World.phase = "load"
World.LoadAddOn("EldoUI")
for _, name in ipairs(World.addonList) do
	local addon = World.addons[name]
	if not addon.demand and (addon.meta.Dependencies or ""):find("EldoUI", 1, true) then World.LoadAddOn(name) end
end
local loadErrors = #World.errors

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
local ns = World.addons.EldoUI.ns or {}
local modules, active = 0, 0
for _, module in pairs(type(ns.modules) == "table" and ns.modules or {}) do
	if type(module) == "table" then
		modules = modules + 1
		if rawget(module, "active") then active = active + 1 end
	end
end
local loaded = {}
for _, name in ipairs(World.addonList) do
	if World.loaded[name] then loaded[#loaded + 1] = name end
end
local language = type(ns.GetLanguage) == "function" and ns:GetLanguage() or "?"

-- The same error (phase and message, without the repository path) once.
local unique, order = {}, {}
for _, entry in ipairs(World.errors) do
	local message = ROOT ~= "" and entry.message:gsub(ROOT:gsub("%p", "%%%0"), "") or entry.message
	local key = entry.phase .. "\1" .. message
	if not unique[key] then
		unique[key] = { phase = entry.phase, message = message, count = 0 }
		order[#order + 1] = key
	end
	unique[key].count = unique[key].count + 1
end

print(("EldoUI offline start (client %s, EldoUI language %s): %d files (%d for other text languages left out), %d modules (%d on), %.1f s")
	:format(World.locale, tostring(language), World.files, World.skipped, modules, active, os.clock() - started))
print("add-ons loaded: " .. table.concat(loaded, ", "))
print(("errors: %d at load, %d after (%d different)"):format(loadErrors, #World.errors - loadErrors, #order))
local shown = options.all and #order or math.min(#order, 60)
for index = 1, shown do
	local entry = unique[order[index]]
	local first = entry.message:match("^[^\n]*")
	print(("  [%s] %s%s"):format(entry.phase, first, entry.count > 1 and (" (x%d)"):format(entry.count) or ""))
end
if shown < #order then print(("  ... %d more (--all lists them)"):format(#order - shown)) end
os.exit(#World.errors == 0 and 0 or 1)
