-- EldoUI core: namespace, event handling, combat-safe queue and chat output.
-- Every other file receives the same private table `E` through the addon vararg.
local addonName, E = ...

-- Public API: other addons and plugins talk to EldoUI through this global.
_G.EldoUI = E

E.name = addonName
E.version = C_AddOns.GetAddOnMetadata(addonName, "Version") or "dev"
E.color = "" -- the accent as a |cff escape, set by Core/Media.lua
E.debug = false

-- Version of the API that plugins and (after the split) the EldoUI_*
-- module addons rely on. Raise it when E:NewModule, the options format or
-- another documented call changes in a way older module code can't handle;
-- module files check it before they register:
--   local E = EldoUI
--   if not (E and E.apiVersion and E.apiVersion >= 1) then return end
E.apiVersion = 1

---------------------------------------------------------------------------
-- Chat output
---------------------------------------------------------------------------
-- Writes straight to the default chat frame instead of print(): print()
-- runs through a replaceable global handler, and addon text sent that way
-- can taint the chat path that whispers use.
local function ChatLine(prefix, ...)
	local parts = { prefix }
	for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
	local line = table.concat(parts, " ")
	local frame = _G.DEFAULT_CHAT_FRAME
	if frame and frame.AddMessage then frame:AddMessage(line) else print(line) end
end

function E:Print(...)
	ChatLine(self.color .. "EldoUI|r:", ...)
end

-- UTF-8 safe "first count characters" (names with accents or Cyrillic).
-- Never pass a secret value: callers check issecretvalue first.
function E:Utf8Sub(text, count)
	if type(text) ~= "string" or not count or count <= 0 then return text end
	local result, n = {}, 0
	for char in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
		n = n + 1
		if n > count then break end
		result[n] = char
	end
	return table.concat(result)
end

-- Letters (not bytes) in a UTF-8 text.
function E:Utf8Len(text)
	if type(text) ~= "string" then return 0 end
	local _, count = text:gsub("[^\128-\191]", "")
	return count
end

-- At most `maxBytes` bytes, ending on a whole letter: for limits the game
-- counts in bytes (chat lines, addon messages, link data).
function E:Utf8Clip(text, maxBytes)
	if type(text) ~= "string" or not maxBytes or #text <= maxBytes then return text end
	local stop = math.max(0, maxBytes)
	-- While the next byte continues a letter, that letter would be split.
	while stop > 0 do
		local byte = text:byte(stop + 1)
		if not byte or byte < 0x80 or byte >= 0xC0 then break end
		stop = stop - 1
	end
	return text:sub(1, stop)
end

function E:Debug(...)
	if self.debug then
		ChatLine(self.color .. "EldoUI|r " .. (self.TextHex and self:TextHex("secondary") or "") .. "[debug]|r", ...)
	end
end

---------------------------------------------------------------------------
-- Events: E:RegisterEvent("EVENT", handler) where handler is a function or
-- a method name on E. Several handlers may listen to the same event.
---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
local handlers = {}
local lastHandlers = {} -- event -> list of functions run after every other handler
local databaseLoaded = false

-- The handler lists are copy-on-write: registering or unregistering builds
-- a new table, so a handler that (un)registers handlers for the event that
-- is being dispatched never changes the table the loop walks (that would
-- end in "invalid key to 'next'" whenever the table rehashes). A handler
-- removed during the dispatch is skipped; one added starts with the next.
-- Each handler runs protected: one error (a module that breaks on this
-- client) must not skip the handlers after it, which are walked in no
-- fixed order. The core's own handler (owner E) always runs first, so at
-- PLAYER_LOGIN the scale and the modules are ready for everyone else.
-- While /eui perf runs (Core/Perf.lua), probe(owner, event, ms) hears how
-- long each handler took; otherwise it is nil and costs one check.
local probe

function E:SetEventProbe(fn)
	probe = fn
end

local function RunHandler(map, event, owner, ...)
	local current = map[event]
	local handler = current and current[owner]
	if not handler then return end
	local measure = probe
	local started = measure and debugprofilestop()
	local ok, err
	if type(handler) == "string" then
		ok, err = pcall(owner[handler], owner, event, ...)
	else
		ok, err = pcall(handler, owner, event, ...)
	end
	if measure then measure(owner, event, debugprofilestop() - started) end
	if not ok then geterrorhandler()(err) end
end

-- PLAYER_LOGIN runs in three phases, in this order: "engines" (shared
-- services the rest builds on), "pages" (option pages and setup steps),
-- then "modules" (everything else, the default). Each handler names its
-- phase when it registers: E:RegisterEvent("PLAYER_LOGIN", fn, owner,
-- phase). The core starts the modules itself at the head of the modules
-- phase, so every handler there sees them on. Inside a phase the order is
-- not fixed, and no handler may rely on it.
local LOGIN_PHASES = { "engines", "pages", "modules" }
local LOGIN_PHASE = { engines = true, pages = true, modules = true }
local DEFAULT_PHASE = "modules"
local loginPhases = setmetatable({}, { __mode = "k" }) -- owner -> phase
local loginStart = {} -- phase -> the core's own step, run first in that phase

E.LOGIN_PHASES = LOGIN_PHASES

function E:LoginPhase(owner)
	return loginPhases[owner or self] or DEFAULT_PHASE
end

-- The owners whose PLAYER_LOGIN handlers run in `phase`, in the order they
-- run (the core's own handler is not listed: it always runs first).
function E:LoginOrder(phase)
	local order = {}
	for owner in pairs(handlers.PLAYER_LOGIN or {}) do
		if owner ~= E and (loginPhases[owner] or DEFAULT_PHASE) == phase then order[#order + 1] = owner end
	end
	return order
end

local function DispatchLogin(...)
	for _, phase in ipairs(LOGIN_PHASES) do
		local list = handlers.PLAYER_LOGIN
		if list and list[E] and (loginPhases[E] or DEFAULT_PHASE) == phase then RunHandler(handlers, "PLAYER_LOGIN", E, ...) end
		if loginStart[phase] then
			local ok, err = pcall(loginStart[phase], E)
			if not ok then geterrorhandler()(err) end
		end
		for _, owner in ipairs(E:LoginOrder(phase)) do RunHandler(handlers, "PLAYER_LOGIN", owner, ...) end
	end
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
	if event == "PLAYER_LOGIN" and not databaseLoaded then return end
	local list = handlers[event]
	if event == "PLAYER_LOGIN" then
		DispatchLogin(...)
	elseif list then
		if list[E] then RunHandler(handlers, event, E, ...) end
		for owner in pairs(list) do
			if owner ~= E then RunHandler(handlers, event, owner, ...) end
		end
	end
	local last = lastHandlers[event]
	if last then
		for _, fn in ipairs(last) do
			local ok, err = pcall(fn, event, ...)
			if not ok then geterrorhandler()(err) end
		end
	end
end)

local function CopyList(list)
	local copy = {}
	for owner, handler in pairs(list or {}) do copy[owner] = handler end
	return copy
end

-- What each owner has registered, so a module switched off can drop all
-- of its handlers at once (E:UnregisterOwnerEvents). The value is true for
-- a handler registered while the owner was on (`owner.active`), false for
-- one registered while it was off (in OnInitialize, kept while off).
local owned = setmetatable({}, { __mode = "k" }) -- owner -> { [key] = { event, units, whileOn } }

local function Own(owner, key, event, units)
	local list = owned[owner]
	if not list then
		list = {}
		owned[owner] = list
	end
	list[key] = { event = event, units = units, whileOn = type(owner) == "table" and rawget(owner, "active") and true or false }
end

local function Disown(owner, key)
	local list = owned[owner]
	if list then list[key] = nil end
end

-- `owner` lets modules register their own handlers without clobbering others.
-- `phase` is for PLAYER_LOGIN only: "engines", "pages" or "modules" (the
-- default; see above).
function E:RegisterEvent(event, handler, owner, phase)
	owner = owner or self
	if event == "PLAYER_LOGIN" then
		loginPhases[owner] = LOGIN_PHASE[phase] and phase or nil
	end
	local list = CopyList(handlers[event])
	list[owner] = handler or event
	handlers[event] = list
	eventFrame:RegisterEvent(event)
	Own(owner, event, event)
end

function E:UnregisterEvent(event, owner)
	owner = owner or self
	local list = handlers[event]
	if not list or list[owner] == nil then return end
	Disown(owner, event)
	if event == "PLAYER_LOGIN" then loginPhases[owner] = nil end
	list = CopyList(list)
	list[owner] = nil
	if next(list) == nil then
		handlers[event] = nil
		if not lastHandlers[event] then eventFrame:UnregisterEvent(event) end
	else
		handlers[event] = list
	end
end

-- Unit events: E:RegisterUnitEvent(event, units, handler, owner) hears the
-- event only for `units` ("player", or a list of at most two, the game's
-- own limit). The game filters the units, so a raid's casts never wake
-- Lua for a "player" listener. Each unit set has its own frame and
-- handler lists (same rules as above: one handler per owner, copy on
-- write, each run protected, owner E first); the shared dispatcher above
-- stays as it is.
local unitGroups = {} -- "player" / "player,pet" -> { frame, handlers, units }

local function UnitGroup(units, create)
	if type(units) == "string" then units = { units } end
	local key = table.concat(units, ",", 1, math.min(#units, 2))
	local group = unitGroups[key]
	if not group and create and key ~= "" then
		group = { frame = CreateFrame("Frame"), handlers = {}, units = { units[1], units[2] } }
		group.frame:SetScript("OnEvent", function(_, event, ...)
			local list = group.handlers[event]
			if not list then return end
			if list[E] then RunHandler(group.handlers, event, E, ...) end
			for owner in pairs(list) do
				if owner ~= E then RunHandler(group.handlers, event, owner, ...) end
			end
		end)
		unitGroups[key] = group
	end
	return group
end

function E:RegisterUnitEvent(event, units, handler, owner)
	owner = owner or self
	local group = UnitGroup(units, true)
	if not group then return false end
	local list = CopyList(group.handlers[event])
	list[owner] = handler or event
	group.handlers[event] = list
	group.frame:RegisterUnitEvent(event, group.units[1], group.units[2])
	Own(owner, event .. "\1" .. table.concat(group.units, ","), event, group.units)
	return true
end

function E:UnregisterUnitEvent(event, units, owner)
	owner = owner or self
	local group = UnitGroup(units, false)
	local list = group and group.handlers[event]
	if not list or list[owner] == nil then return end
	Disown(owner, event .. "\1" .. table.concat(group.units, ","))
	list = CopyList(list)
	list[owner] = nil
	if next(list) == nil then
		group.handlers[event] = nil
		group.frame:UnregisterEvent(event)
	else
		group.handlers[event] = list
	end
end

-- Drop every handler `owner` registered (events and unit events). With
-- `onlyWhileOn`, only the ones registered while the owner was on: the
-- module system calls it this way when a module is switched off, so a
-- module's OnDisable never has to repeat its event list, and OnEnable
-- registers them again. Returns how many were dropped.
function E:UnregisterOwnerEvents(owner, onlyWhileOn)
	local list = owner and owned[owner]
	if not list then return 0 end
	local drop = {}
	for _, entry in pairs(list) do
		if not onlyWhileOn or entry.whileOn then drop[#drop + 1] = entry end
	end
	for _, entry in ipairs(drop) do
		if entry.units then
			self:UnregisterUnitEvent(entry.event, entry.units, owner)
		else
			self:UnregisterEvent(entry.event, owner)
		end
	end
	return #drop
end

-- Core only: fn(event, ...) runs after every E:RegisterEvent handler of
-- the event, in the order added. PLAYER_LOGOUT uses it to compact the saved
-- settings once every module has written its own.
function E:RegisterLastHandler(event, fn)
	lastHandlers[event] = lastHandlers[event] or {}
	table.insert(lastHandlers[event], fn)
	eventFrame:RegisterEvent(event)
end

---------------------------------------------------------------------------
-- Combat safety: protected frames cannot be moved, shown or hidden during
-- combat. Anything that touches them goes through E:RunOutOfCombat(fn).
--
--   E:RunOutOfCombat(fn[, key[, opts]])
--     Out of combat fn runs now and the call returns true. In combat it
--     waits for the end of combat and the call returns false.
--     key: one queued call per key. A later call with the same key takes
--       the queued call's place, so a refresh asked for on every event or
--       option change runs once after combat, not once per ask.
--     opts.generation: a number from E:NewApplyGeneration(). When a newer
--       one has been made by the time the call would run (a profile switch
--       or another apply came after it), the call is dropped, so an old
--       apply never lands on settings it was not meant for. opts.lane picks
--       the counter ("apply" when left out).
--   E:CancelOutOfCombat(key)      drops the queued call; true when one was
--   E:PendingOutOfCombat([key])   with a key: true while it waits; without:
--                                 how many calls wait
--   E:NewApplyGeneration([lane])  a new generation; every earlier one of
--                                 the lane is stale from now on
--   E:IsApplyGenerationCurrent(generation[, lane])
---------------------------------------------------------------------------
local combatQueue, combatKeys = {}, {} -- queued { fn, key, generation, lane }; key -> index
local generations = {} -- lane -> the newest generation

function E:NewApplyGeneration(lane)
	lane = lane or "apply"
	generations[lane] = (generations[lane] or 0) + 1
	return generations[lane]
end

function E:GetApplyGeneration(lane)
	return generations[lane or "apply"]
end

function E:IsApplyGenerationCurrent(generation, lane)
	if generation == nil then return true end
	return generation == (generations[lane or "apply"] or 0)
end

local function Stale(job)
	return job.generation ~= nil and not E:IsApplyGenerationCurrent(job.generation, job.lane)
end

function E:RunOutOfCombat(fn, key, opts)
	local job = { fn = fn, key = key }
	if type(opts) == "table" then job.generation, job.lane = opts.generation, opts.lane end
	if InCombatLockdown() then
		local index = key ~= nil and combatKeys[key]
		if index then
			combatQueue[index] = job
		else
			table.insert(combatQueue, job)
			if key ~= nil then combatKeys[key] = #combatQueue end
		end
		return false
	end
	if Stale(job) then return false end
	fn()
	return true
end

function E:CancelOutOfCombat(key)
	local index = key ~= nil and combatKeys[key]
	if not index then return false end
	combatKeys[key] = nil
	combatQueue[index] = false
	return true
end

function E:PendingOutOfCombat(key)
	if key ~= nil then return combatKeys[key] ~= nil end
	local count = 0
	for _, job in ipairs(combatQueue) do
		if job then count = count + 1 end
	end
	return count
end

-- Sliced work (E:RunSliced below) that waits for the end of combat.
local parkedSlices = {}
local SliceStep

E:RegisterEvent("PLAYER_REGEN_ENABLED", function()
	local queue = combatQueue
	combatQueue, combatKeys = {}, {}
	for _, job in ipairs(queue) do
		if job and not Stale(job) then
			local ok, err = pcall(job.fn)
			if not ok then geterrorhandler()(err) end
		end
	end
	local parked = parkedSlices
	parkedSlices = {}
	for _, handle in ipairs(parked) do
		handle.parked = nil
		if not handle.done then C_Timer.After(0, function() SliceStep(handle) end) end
	end
end)

---------------------------------------------------------------------------
-- E:Debounce(key, delay, fn): the first call schedules
-- fn after `delay` seconds; calls with the same key before it runs are
-- dropped, so a burst of events makes one refresh. The key is free again
-- just before fn runs. Returns true when this call scheduled fn.
---------------------------------------------------------------------------
local debounced = {}

function E:Debounce(key, delay, fn)
	if debounced[key] or not C_Timer then return false end
	debounced[key] = true
	C_Timer.After(delay or 0, function()
		debounced[key] = nil
		fn()
	end)
	return true
end

---------------------------------------------------------------------------
-- E:RunSliced(fn, budgetMs, done): heavy work spread over frames, so the
-- game never stalls. fn runs in a coroutine and calls E.SliceYield()
-- between steps; it pauses there once this frame's budget (budgetMs,
-- default 4) is spent and goes on next frame. Never yield inside pcall.
-- Sliced work never runs in combat: it waits and goes on after the fight.
-- done(ok, err) runs when fn ends. Returns a handle:
--   handle.done            true once fn has ended (or was canceled)
--   handle.slices          how many frames it has used so far
--   handle:Finish()        runs the rest now (when the result is needed)
--   handle:Cancel()        stops it; done is not called
---------------------------------------------------------------------------
local slicing -- the handle running right now, or nil

function E.SliceYield()
	local handle = slicing
	if not handle or handle.unlimited then return end
	if debugprofilestop() - handle.sliceStart >= handle.budget then coroutine.yield() end
end

SliceStep = function(handle)
	if handle.done or slicing == handle then return end
	-- In combat the work waits for the end of the fight (handle:Finish()
	-- still runs it at once, for a caller that needs the result now).
	if not handle.unlimited and InCombatLockdown() then
		if not handle.parked then
			handle.parked = true
			parkedSlices[#parkedSlices + 1] = handle
		end
		return
	end
	handle.slices = handle.slices + 1
	handle.sliceStart = debugprofilestop()
	local outer = slicing
	slicing = handle
	local ok, err = coroutine.resume(handle.co)
	slicing = outer
	if not ok or coroutine.status(handle.co) == "dead" then
		handle.done = true
		if not ok then geterrorhandler()(err) end
		if type(handle.onDone) == "function" then
			local fine, why = pcall(handle.onDone, ok, not ok and err or nil)
			if not fine then geterrorhandler()(why) end
		end
		return
	end
	C_Timer.After(0, function() SliceStep(handle) end)
end

local Sliced = {}
Sliced.__index = Sliced

function Sliced:Cancel()
	self.done = true
end

function Sliced:Finish()
	if slicing == self then return end
	self.unlimited = true
	while not self.done do SliceStep(self) end
end

function E:RunSliced(fn, budgetMs, done)
	local handle = setmetatable({ co = coroutine.create(fn), budget = tonumber(budgetMs) or 4,
		onDone = done, slices = 0, done = false }, Sliced)
	SliceStep(handle)
	return handle
end

---------------------------------------------------------------------------
-- Saved settings start: E:OnDatabaseLoad(fn, when) runs fn(E) around the
-- moment the saved settings load at ADDON_LOADED. "before": the saved
-- tables are there (EldoUIDB may still be nil on a fresh install) but no
-- profile is chosen yet, for what the profile needs to find when it loads
-- (imported layouts). "after" (the default): the profile is loaded. Hooks
-- run in the order they were added, each one protected. Returns true; an
-- "after" hook added once the settings have loaded runs at once, and a
-- "before" hook added that late can no longer run and returns false.
---------------------------------------------------------------------------
local databaseHooks = { before = {}, after = {} }

function E:OnDatabaseLoad(fn, when)
	assert(type(fn) == "function", "EldoUI:OnDatabaseLoad(fn, when): fn must be a function")
	when = when or "after"
	assert(databaseHooks[when], 'EldoUI:OnDatabaseLoad(fn, when): when is "before" or "after"')
	if databaseLoaded then
		if when == "before" then return false end
		local ok, err = pcall(fn, self)
		if not ok then geterrorhandler()(err) end
		return true
	end
	table.insert(databaseHooks[when], fn)
	return true
end

local function RunDatabaseHooks(when)
	for _, fn in ipairs(databaseHooks[when]) do
		local ok, err = pcall(fn, E)
		if not ok then geterrorhandler()(err) end
	end
end

function E:InvalidateDatabase()
	databaseLoaded = false
end

function E:LoadDatabase()
	databaseLoaded = false
	if not self:PrepareProfileBaseline() then
		self:Print(E.L["EldoUI could not load these settings. Check that you are using the latest version of EldoUI."])
		return false
	end
	RunDatabaseHooks("before")
	if not self:InitializeDatabase() then
		self:Print(E.L["EldoUI could not load these settings. Check that you are using the latest version of EldoUI."])
		return false
	end
	databaseLoaded = true
	RunDatabaseHooks("after")
	return true
end

---------------------------------------------------------------------------
-- Startup
---------------------------------------------------------------------------
E:RegisterEvent("ADDON_LOADED", function(self, _, loaded)
	if loaded ~= addonName then return end
	self:UnregisterEvent("ADDON_LOADED")
	if not self:LoadDatabase() then return end
	-- E.pixel for the scale EldoUI sets at PLAYER_LOGIN, so the borders of
	-- frames modules build now are one screen pixel from the start.
	self:UpdatePixel(self:GetTargetScale())
	self:UpdateAccent()
	self:InitializeModules()
	self:InitializeOptions()
end)

-- The scale comes first, before any other login handler.
E:RegisterEvent("PLAYER_LOGIN", function(self)
	self:ApplyScale()
end, E, "engines")

-- Then, at the head of the modules phase, the modules start and the setup
-- check runs.
loginStart.modules = function(self)
	self:EnableModules()
	self:CheckInstall(true)
	if not self.db.general.welcome then return end
	self:Print(self.L["v%s loaded. Type %s for options."]:format(self.version, E:Highlight("/eui")))
end
