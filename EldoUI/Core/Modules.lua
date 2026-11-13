-- EldoUI module and plugin system.
--
-- Built-in modules and external plugins use the same API:
--
--   local M = EldoUI:NewModule("InfoBar", {
--       title    = "Info Bar",                 -- shown in options
--       desc     = "A bar with gold, FPS ...", -- shown in options
--       defaults = { enabled = true, height = 22 },
--       conflicts = { "OtherUIAddon" },       -- stays off while these load
--                                             -- (Core/AddonConflicts.lua)
--       aliases  = { "Old Title" },           -- earlier names: the settings
--                                             -- search and /eui still find it
--       -- plugins only (Core/Plugins.lua, docs/PLUGINS.md):
--       plugin    = "MyAddon",                -- the plugin's addon folder
--       version   = "1.2.0",                  -- else the .toc's Version
--       minEldoUI = "0.6.0",                  -- warn on an older EldoUI
--   })
--
-- The info table may also describe what the module owns. These fields are
-- kept on the module (E:GetModuleDescriptor) for the checks that read them;
-- nothing changes in how the module runs:
--       frames      = { "EldoUI_InfoBar" },   -- frames it creates and owns
--       movers      = { "EldoUI_InfoBar" },   -- movers it creates
--       blizzard    = { "micro-menu" },       -- Blizzard element ids it handles
--                                             -- (Core/Blizzard.lua)
--       savedKeys   = { "height", "font" },   -- keys of its settings it owns
--       optionsPage = "module:InfoBar",       -- its options page, false for none
--       presets     = { "Compact" },          -- presets it registers
--       uiAmount    = "moderate",             -- the first UI amount it is on in:
--                                             -- essential, moderate or full
--       reload      = false,                  -- true (or a list of reasons)
--                                             -- when turning it off needs /reload
--       themed      = "OnThemeChanged",       -- what repaints it on a new look:
--                                             -- a function or a method name
--   (`conflicts` above is part of the same description.)
--
--   function M:OnInitialize() end  -- once, after settings are loaded
--   function M:OnEnable() end      -- at login, or when switched on
--   function M:OnDisable() end     -- when switched off; the event
--                                     -- handlers it registered while on
--                                     -- (M:RegisterEvent, E:RegisterEvent
--                                     -- with M as owner) are dropped for it
--   function M:OnProfileChanged() end
--   M.refreshWhenOff = function(M) end  -- options page changes while off
--
-- Plugins (separate addons) list `## Dependencies: EldoUI` in their .toc,
-- then call EldoUI:NewModule(...) the same way. Plugins that load after
-- EldoUI has started are initialized and enabled straight away. A module
-- with `plugin` is listed on the Plugins page; the full guide for plugin
-- authors is docs/PLUGINS.md.
local _, E = ...

E.modules = {}
E.moduleOrder = {}

local started = false   -- InitializeModules has run
local loggedIn = false  -- EnableModules has run

local Module = {}

-- The description fields E:NewModule keeps (see the header), in order,
-- with the kinds of value each may hold.
E.MODULE_DESCRIPTOR = {
	{ key = "frames", kinds = { table = true } },
	{ key = "movers", kinds = { table = true } },
	{ key = "blizzard", kinds = { table = true } },
	{ key = "savedKeys", kinds = { table = true } },
	{ key = "optionsPage", kinds = { string = true, boolean = true } },
	{ key = "presets", kinds = { table = true } },
	{ key = "uiAmount", kinds = { string = true } },
	{ key = "conflicts", kinds = { table = true } },
	{ key = "reload", kinds = { boolean = true, table = true } },
	{ key = "themed", kinds = { ["function"] = true, string = true } },
}

-- The description a module gave, and the fields that held the wrong kind
-- of value (left out of the description, listed for the checks).
local function Describe(info)
	local descriptor, wrong = {}, {}
	for _, field in ipairs(E.MODULE_DESCRIPTOR) do
		local value = info[field.key]
		if value ~= nil then
			if field.kinds[type(value)] then
				descriptor[field.key] = value
			else
				wrong[#wrong + 1] = field.key
			end
		end
	end
	return descriptor, wrong
end

function Module:IsEnabled()
	return self.db and self.db.enabled
end

function Module:RegisterEvent(event, handler)
	E:RegisterEvent(event, handler, self)
end

function Module:UnregisterEvent(event)
	E:UnregisterEvent(event, self)
end

-- The event only for `units` ("player", or a list of at most two): the
-- game filters the units, so other units never wake the handler.
-- Switching the module off drops it with its other events.
function Module:RegisterUnitEvent(event, units, handler)
	return E:RegisterUnitEvent(event, units, handler, self)
end

function Module:UnregisterUnitEvent(event, units)
	E:UnregisterUnitEvent(event, units, self)
end

-- An alert from this module (E:PushAlert): Ctrl-click on its card opens
-- this module's own options page unless data.options names another row.
function Module:PushAlert(data)
	if type(data) == "table" and data.options == nil and self.options ~= nil then
		data.options = { page = ("module:%s"):format(self.name) }
	end
	return E:PushAlert(data)
end

function Module:Print(...)
	E:Print((E:TextHex("accent") .. "[%s]|r"):format(E.L[self.title]), ...)
end

function E:GetModuleDB(module)
	local all = self.db.modules
	all[module.name] = self.ApplyDefaults(all[module.name] or {}, module.defaults)
	return all[module.name]
end

-- A failed method is kept on the module (`module.failed`), so the options
-- window can say so; a later run that works clears it.
local function SafeCall(module, method)
	if module[method] then
		local ok, err = pcall(module[method], module)
		if not ok then
			module.failed = method
			geterrorhandler()(("EldoUI module %s:%s failed: %s"):format(module.name, method, err))
		elseif module.failed == method then
			module.failed = nil
		end
	end
end

-- What failed in a module: "OnInitialize", "OnEnable", "OnDisable" or
-- "options" (its options did not build); nil when nothing did. A module
-- whose start failed still counts as on: it may be half set up, and
-- switching it off runs its OnDisable.
function E:ModuleFailed(module)
	if type(module) == "string" then module = self.modules[module] end
	if not module then return nil end
	return module.failed or (module.optionsError and "options") or nil
end

local function InitializeModule(module)
	if module.initialized then return end
	module.db = E:GetModuleDB(module)
	SafeCall(module, "OnInitialize")
	module.initialized = true
end

-- Other addons that do the same job as a module or a part of it (the
-- `conflicts` list above, E:RegisterFeatureConflicts and
-- E:RegisterCompetitor) live in the registry, Core/AddonConflicts.lua.

local function EnableModule(module)
	if module.active or not module:IsEnabled() then return end
	local conflict, title = E:GetModuleConflict(module)
	if conflict then
		E:Debug(("%s stays off because %s is loaded."):format(module.name, title or conflict))
		return
	end
	module.active = true
	-- Movers created while a module enables are tagged with it, so a
	-- module's export string can carry its frame positions.
	E.currentModule = module
	SafeCall(module, "OnEnable")
	E.currentModule = nil
	if E.RefreshMoveMode then E:RefreshMoveMode(module) end
end

local function DisableModule(module)
	if not module.active then return end
	module.active = false
	SafeCall(module, "OnDisable")
	-- Every event handler the module registered while it was on goes with
	-- it (OnEnable registers them again); ones from OnInitialize stay.
	E:UnregisterOwnerEvents(module, true)
	-- Move mode drops the movers of a module switched off.
	if E.RefreshMoveMode then E:RefreshMoveMode(module) end
end

-- Stand a module back while it stays switched on in its settings: a
-- competing addon loaded after login (Core/AddonConflicts.lua). The same
-- as switching it off, except module.db.enabled is left as it is, so it
-- runs again once the other addon is gone. Out of combat only.
function E:HoldModule(module)
	if type(module) == "string" then module = self.modules[module] end
	if not (module and module.active) then return false end
	DisableModule(module)
	return true
end

function E:NewModule(name, info)
	assert(type(name) == "string", "EldoUI:NewModule(name, info): name must be a string")
	assert(not self.modules[name], ("EldoUI module %q is already registered"):format(name))
	info = info or {}

	local module = setmetatable({
		name = name,
		title = info.title or name,
		desc = info.desc or "",
		plugin = info.plugin, -- name of the external addon, if any
		-- The addon folder the module lives in. EldoUI's own modules leave it
		-- out today; after the split each module addon passes its folder
		-- ("EldoUI_ActionBars"), and E:IsFirstPartyModule tells them apart
		-- from third-party plugins.
		addon = info.addon,
		defaults = info.defaults or {},
		conflicts = info.conflicts or {},
		aliases = info.aliases or {},
		category = info.category, -- config sidebar group, see E.moduleCategories
		version = info.version,
		minEldoUI = info.minEldoUI,
	}, { __index = Module })
	if module.defaults.enabled == nil then module.defaults.enabled = true end
	module.descriptor, module.descriptorErrors = Describe(info)
	-- One list: the description's `conflicts` is the module's own table.
	module.descriptor.conflicts = module.conflicts

	self.modules[name] = module
	table.insert(self.moduleOrder, name)
	-- `conflicts` is the short form of whole-module registry entries.
	if self.RegisterCompetitor then
		for _, addon in ipairs(self:ModuleConflictList(module)) do
			self:RegisterCompetitor({ addon = addon, module = name, scope = "replace" })
		end
	end
	-- Third-party plugins go on the Plugins page (Core/Plugins.lua).
	if module.plugin and self.AttachPluginModule then self:AttachPluginModule(module, info) end

	-- Late registration (plugins loading after EldoUI).
	if started then InitializeModule(module) end
	if loggedIn then EnableModule(module) end
	return module
end

-- EldoUI's own modules: built in, or a module addon named EldoUI_<Name>
-- (the planned split). Everything else is a plugin.
function E:IsFirstPartyModule(module)
	if type(module) == "string" then module = self.modules[module] end
	if not module then return false end
	local addon = module.addon
	if type(addon) == "string" and (addon == "EldoUI" or addon:sub(1, 7) == "EldoUI_") then return true end
	return not module.plugin
end

function E:GetModule(name)
	return self.modules[name]
end

-- The other addons a module stays off for: the `conflicts` list of its
-- description. The engine that reads it is Core/AddonConflicts.lua.
function E:ModuleConflictList(module)
	if type(module) == "string" then module = self.modules[module] end
	local descriptor = module and module.descriptor
	return descriptor and descriptor.conflicts or {}
end

-- What a module says it owns (the description fields of E:NewModule), or
-- nil for a module that is not registered.
function E:GetModuleDescriptor(module)
	if type(module) == "string" then module = self.modules[module] end
	return module and module.descriptor or nil
end

-- A module by an earlier name: its own name, or one of its `aliases`
-- (a module merged into another lists the old module's name there).
function E:ModuleByAlias(name)
	if type(name) ~= "string" then return nil end
	if self.modules[name] then return self.modules[name] end
	for _, module in self:IterateModules() do
		for _, alias in ipairs(module.aliases) do
			if alias == name then return module end
		end
	end
end

function E:IterateModules()
	local i = 0
	return function()
		i = i + 1
		local name = self.moduleOrder[i]
		if name then return name, self.modules[name] end
	end
end

function E:InitializeModules()
	started = true
	for _, module in self:IterateModules() do InitializeModule(module) end
end

function E:EnableModules()
	loggedIn = true
	for _, module in self:IterateModules() do EnableModule(module) end
end

-- After a profile switch: turn on the modules the new profile has on and
-- turn off the ones it has off. Runs out of combat; a switch
-- in combat is queued and reads the setting when it runs. Returns the
-- modules switched off now (E:ShowReloadPrompt asks for a reload only for
-- the ones whose Blizzard frames need one) and a set of the modules
-- switched on now (already applied).
function E:SyncModuleStates()
	local switchedOff, switchedOn = {}, {}
	if not loggedIn then return switchedOff, switchedOn end
	for _, module in self:IterateModules() do
		if module.initialized and (module.db.enabled and true or false) ~= (module.active and true or false) then
			local ran = self:RunOutOfCombat(function()
				if module.db.enabled then EnableModule(module) else DisableModule(module) end
			end, "module:" .. module.name)
			if ran then
				if module.active then
					switchedOn[module] = true
				elseif not module.db.enabled then
					table.insert(switchedOff, module)
				end
			end
		end
	end
	return switchedOff, switchedOn
end

-- Switch a module on or off from options or slash commands.
function E:SetModuleEnabled(name, enabled)
	local module = self.modules[name]
	if not module then return false end
	module.db.enabled = enabled and true or false
	-- Read the setting when the call runs, so toggling several times in
	-- combat ends in the state the user picked last, with one switch.
	self:RunOutOfCombat(function()
		if module.db.enabled then EnableModule(module) else DisableModule(module) end
	end, "module:" .. name)
	return true
end
