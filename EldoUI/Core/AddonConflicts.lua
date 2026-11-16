-- Other addons that do the same job as EldoUI: the registry.
--
-- One place knows which addon does which EldoUI job, so a module can
-- stand back fully (scope "replace": the whole module stays off while the
-- addon is loaded, for addons that own the same frames) or only for one
-- part (scope "overlap": the module asks E:StandsBack(module, feature)),
-- and remember who the player picked for each job. Scope "alongside" is
-- an addon that does the same job without touching the same frames: both
-- run, nothing stands back, and the Other addons page only says that
-- EldoUI does this job too.
--
--   E:RegisterCompetitor({
--       addon   = "Leatrix_Plus",       -- the addon's folder name
--       module  = "Merchant",           -- the EldoUI module (name)
--       feature = "selljunk",           -- nil: the whole module
--       scope   = "overlap",            -- "replace" (default without a
--                                       -- feature), "overlap" or
--                                       -- "alongside"
--       covers  = "part",               -- how much of the addon's job
--                                       -- EldoUI does: "full" or "part"
--                                       -- (default: "full" for replace,
--                                       -- "part" otherwise)
--       label   = "Selling gray items", -- what overlaps, in player words
--       active  = function() ... end,   -- optional: false when the other
--                                       -- addon has this job switched off
--                                       -- (an error or nil counts as on)
--       setting = { "Characters", "countsWithBagAddons" }, -- optional:
--                                       -- a module switch meaning "show
--                                       -- both"; a choice writes it
--       exclusive = true,               -- optional: both can't run on the
--                                       -- same frames, so EldoUI's part
--                                       -- only runs once the addon is off
--       note    = "...",                -- what overlaps; never shown
--   })
--   E:NoKnownCompetitor("Streamer", "why")  -- no other addon does this
--   E:MarkCompanion("Integrations")         -- works with other addons and
--                                           -- never stands back
--
-- Short forms that keep working: `conflicts = { ... }` on E:NewModule
-- (replace entries) and E:RegisterFeatureConflicts(feature, { ... })
-- (overlap entries on that feature key).
--
-- Rules: an addon is found only through C_AddOns, and an `active` check
-- only reads the other addon's own saved settings, never writes them.
-- EldoUI never turns another addon on or off by itself: DisableAddOn runs
-- only from the player's "Use EldoUI's" click and from the setup's
-- Finish, and EnableAddOn only from "Keep" on an addon EldoUI turned off
-- this session, or from "Undo the setup" for an addon that setup turned
-- off (Core/OtherAddons.lua, Core/Installer.lua).
local _, E = ...
local L = E.L

local Key = E.Key
local EMPTY = {}

local C = {
	list = {},      -- every entry, in the order registered
	keys = {},      -- "addon|module|feature" -> entry
	byAddon = {},   -- addon -> { entries }
	byModule = {},  -- module name -> { entries }
	byFeature = {}, -- feature key -> { entries }
	none = {},      -- module name -> reason (E:NoKnownCompetitor)
	companion = {}, -- module name -> true (E:MarkCompanion)
	disabled = {},  -- addons turned off by the player's click this session
}
E.competitors = C

-- The global feature keys of E:RegisterFeatureConflicts and the module
-- each belongs to. A key a plugin adds has no module.
local FEATURE_MODULE = {
	combattext = "CombatText", bgtimers = "Battlegrounds", instances = "Instances", characters = "Characters",
	talents = "Talents", camera = "Camera", encountertimeline = "EncounterTimeline", mapnotes = "MapNotes",
	spellranks = "ActionBars", spellrankupgrade = "ActionBars", rarealert = "RareScanner", totemcoverage = "ShamanTotems",
	totemreminders = "ShamanTotems", totemgroup = "ShamanTotems", totemplates = "ShamanTotems",
}
C.featureModule = FEATURE_MODULE

-- What those parts are called on the Other addons page.
local FEATURE_LABEL = {
	combattext = Key("Scrolling combat text"), bgtimers = Key("Capture and score bars"), instances = Key("Instance limit and run log"),
	characters = Key("Alt overview"), talents = Key("Talent planner"), camera = Key("Camera settings"),
	encountertimeline = Key("Encounter timeline"), mapnotes = Key("Note editor"), spellranks = Key("Spell rank check"),
	spellrankupgrade = Key("Spell rank upgrade"),
	rarealert = Key("Rare alerts"), totemcoverage = Key("Totem range"), totemreminders = Key("Totem and shield reminders"),
	totemgroup = Key("Raid cooldowns"), totemplates = Key("Totem nameplates"),
}

-- The settings that stay across characters and profiles: the player's
-- picks (choices[addon][job] = "eldoui"; no entry is "auto"), the addons
-- the login line already named, and whether that line shows.
local STORE = { choices = {}, announced = {}, loginNotes = true }
E:RegisterGlobal("competitors", STORE, { title = "Other addons" })

local function Store()
	return E.GetGlobal and E:GetGlobal("competitors") or nil
end

---------------------------------------------------------------------------
-- Entries
---------------------------------------------------------------------------
local function ModuleName(module)
	if type(module) == "table" then return module.name end
	return module
end

-- The job of an entry: "Bags" (whole module) or "Merchant.selljunk".
local function JobOf(module, feature)
	if feature then return (module or "") .. "." .. feature end
	return module
end
C.JobOf = JobOf

local function Insert(map, key, entry)
	if key == nil then return end
	local list = map[key]
	if not list then
		list = {}
		map[key] = list
	end
	list[#list + 1] = entry
end

-- Register (or add to) one entry. The same addon, module and feature
-- again merges the new fields into the entry already there.
function E:RegisterCompetitor(info)
	if type(info) ~= "table" or type(info.addon) ~= "string" or info.addon == "" then return nil end
	local module = ModuleName(info.module)
	local feature = info.feature
	if module == nil and feature == nil then return nil end
	if type(feature) == "string" and module == nil then module = FEATURE_MODULE[feature] end
	local key = info.addon .. "|" .. (module or "") .. "|" .. (feature or "")
	local entry = C.keys[key]
	if not entry then
		entry = { addon = info.addon, module = module, feature = feature }
		entry.job = JobOf(module, feature)
		C.keys[key] = entry
		C.list[#C.list + 1] = entry
		Insert(C.byAddon, entry.addon, entry)
		Insert(C.byModule, module or "", entry)
		Insert(C.byFeature, feature, entry)
	end
	for field, value in pairs(info) do
		if field ~= "addon" and field ~= "module" and field ~= "feature" then entry[field] = value end
	end
	if entry.scope ~= "replace" and entry.scope ~= "overlap" and entry.scope ~= "alongside" then entry.scope = feature and "overlap" or "replace" end
	if entry.covers ~= "full" and entry.covers ~= "part" then entry.covers = entry.scope == "replace" and "full" or "part" end
	if feature and entry.label == nil then entry.label = FEATURE_LABEL[feature] end
	return entry
end

function E:NoKnownCompetitor(module, reason)
	module = ModuleName(module)
	if type(module) == "string" then C.none[module] = reason or true end
end

function E:MarkCompanion(module)
	module = ModuleName(module)
	if type(module) == "string" then C.companion[module] = true end
end

-- The entries of an addon, of a module, or every entry.
function E:CompetitorEntries(addon, module)
	if addon then return C.byAddon[addon] or EMPTY end
	if module then return C.byModule[ModuleName(module)] or EMPTY end
	return C.list
end

-- Legacy feature lists: E.featureConflicts[feature] is the list of addon
-- folders, as before (old plugins read it). It stays in step with the
-- registry; a list a plugin edits in place still counts.
E.featureConflicts = {
	combattext = { "MikScrollingBattleText", "xCT+", "Parrot", "NameplateSCT", "PlateSCT" },
	bgtimers = { "Capping", "DBM-PvP" },
	instances = { "NovaInstanceTracker", "SavedInstances" },
	characters = { "Altoholic", "DataStore" },
	talents = { "Talented" },
}
for feature, list in pairs(E.featureConflicts) do
	for _, addon in ipairs(list) do E:RegisterCompetitor({ addon = addon, feature = feature, scope = "overlap" }) end
end

function E:RegisterFeatureConflicts(feature, addons)
	if type(feature) ~= "string" or type(addons) ~= "table" then return end
	local list = self.featureConflicts[feature] or {}
	self.featureConflicts[feature] = list
	local known = {}
	for _, name in ipairs(list) do known[name] = true end
	for _, name in ipairs(addons) do
		if type(name) == "string" and not known[name] then
			list[#list + 1] = name
			known[name] = true
			self:RegisterCompetitor({ addon = name, feature = feature, scope = "overlap" })
		end
	end
end

---------------------------------------------------------------------------
-- Checks
---------------------------------------------------------------------------
local function Loaded(addon)
	return C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(addon) and true or false
end

-- This character as the game's addon list names it: by its GUID (a name
-- can be shared, or hold a surname), the name only when there is no GUID.
local function Me()
	local guid = UnitGUID("player")
	if type(guid) == "string" and not E:IsSecret(guid) and guid ~= "" then return guid end
	return UnitName("player")
end

-- Enabled for this character and load-on-demand, but not loaded yet.
local function Waiting(addon)
	if not (C_AddOns and C_AddOns.IsAddOnLoadOnDemand and C_AddOns.GetAddOnEnableState) then return false end
	if Loaded(addon) or not C_AddOns.IsAddOnLoadOnDemand(addon) then return false end
	local ok, state = pcall(C_AddOns.GetAddOnEnableState, addon, Me())
	return ok and type(state) == "number" and state > 0
end

-- The addon's title as its list shows it, without color codes; the
-- folder name when there is none.
local function StripCodes(text)
	text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("|A.-|a", "")
	return strtrim(text)
end

function E:AddonTitle(addon)
	if type(addon) ~= "string" then return tostring(addon) end
	local title
	if C_AddOns and C_AddOns.GetAddOnTitle then
		local ok, value = pcall(C_AddOns.GetAddOnTitle, addon)
		if ok and type(value) == "string" then title = value end
	end
	if (not title or title == "") and C_AddOns and C_AddOns.GetAddOnInfo then
		local ok, _, value = pcall(C_AddOns.GetAddOnInfo, addon)
		if ok and type(value) == "string" then title = value end
	end
	title = title and StripCodes(title) or ""
	if title == "" then return addon end
	return title
end

-- The `active` check: false only when it says so.
local function Overlaps(entry)
	if not entry.active then return true end
	local ok, result = pcall(entry.active, entry)
	if not ok then return true end
	return result ~= false
end

local function SettingOn(entry)
	local setting = entry.setting
	if type(setting) ~= "table" then return false end
	local module = E.modules[setting[1]]
	return module and module.db and module.db[setting[2]] and true or false
end

local function Choice(entry)
	if entry.setting then return SettingOn(entry) and "eldoui" or "auto" end
	local store = Store()
	local picks = store and type(store.choices) == "table" and store.choices[entry.addon]
	return type(picks) == "table" and picks[entry.job] == "eldoui" and "eldoui" or "auto"
end

-- Does EldoUI stand back for this entry right now? Never for an addon
-- that runs alongside.
local function Holds(entry)
	if entry.scope == "alongside" then return false end
	if not (Loaded(entry.addon) and Overlaps(entry)) then return false end
	-- Frame owners never run together: a pick of EldoUI waits until the
	-- other addon is off.
	if entry.scope == "replace" or entry.exclusive then return true end
	return Choice(entry) ~= "eldoui"
end

-- The addon that keeps a whole module off: folder and title, or nil.
function E:GetModuleConflict(module)
	if type(module) == "string" then module = self.modules[module] end
	if not module then return nil end
	for _, entry in ipairs(C.byModule[module.name] or EMPTY) do
		if entry.scope == "replace" and not entry.feature and Holds(entry) then
			return entry.addon, self:AddonTitle(entry.addon)
		end
	end
	-- A `conflicts` list changed after the module registered.
	for _, addon in ipairs(module.conflicts or EMPTY) do
		if not C.keys[addon .. "|" .. module.name .. "|"] and Loaded(addon) then return addon, self:AddonTitle(addon) end
	end
	return nil
end

-- Does a part of a module stand back? true, folder, title; else false.
-- Without a feature it is the same as E:GetModuleConflict.
function E:StandsBack(module, feature)
	local name = ModuleName(module)
	if feature == nil then
		local addon, title = self:GetModuleConflict(name)
		return addon ~= nil, addon, title
	end
	for _, entry in ipairs(C.byModule[name or ""] or EMPTY) do
		if entry.feature == feature and Holds(entry) then return true, entry.addon, self:AddonTitle(entry.addon) end
	end
	return false
end

-- Does EldoUI stand back for this addon's entry on a job right now? The
-- addon fit (Core/AddonFit.lua) places a kept addon only then. A job with
-- no entry for the addon counts as no.
function E:CompetitorHolds(addon, module, feature)
	for _, entry in ipairs(C.byAddon[addon] or EMPTY) do
		if entry.module == ModuleName(module) and entry.feature == feature and Holds(entry) then return true end
	end
	return false
end

-- A loaded addon that does this part's job, whatever the player picked
-- (the "show both" switches use it to know whether to show themselves).
function E:CompetitorLoaded(module, feature)
	for _, entry in ipairs(C.byModule[ModuleName(module) or ""] or EMPTY) do
		if entry.feature == feature and entry.scope ~= "alongside" and Loaded(entry.addon) and Overlaps(entry) then
			return entry.addon, self:AddonTitle(entry.addon)
		end
	end
	return nil
end

-- The legacy feature check: folder and title of the first loaded addon
-- on a feature key EldoUI should leave the job to, or nil.
function E:FeatureConflict(feature)
	if type(feature) ~= "string" then return nil end
	local entries = C.byFeature[feature] or EMPTY
	for _, entry in ipairs(entries) do
		if Holds(entry) then return entry.addon, self:AddonTitle(entry.addon) end
	end
	-- An addon a plugin put into the list itself.
	for _, addon in ipairs(self.featureConflicts[feature] or EMPTY) do
		local known = false
		for _, entry in ipairs(entries) do known = known or entry.addon == addon end
		if not known and Loaded(addon) then return addon, self:AddonTitle(addon) end
	end
	return nil
end

---------------------------------------------------------------------------
-- What was found: the rows the Other addons page, the setup step and
-- /eui addons show (addons that run alongside are E:CoveredAddons).
--   state  standing  EldoUI leaves the job to the other addon
--          eldoui    EldoUI's part runs (the player picked it)
--          fallback  EldoUI was picked, but the addon is still on
--          reload    the addon is off for this character after a reload
--          waiting   enabled and load-on-demand, not loaded yet
---------------------------------------------------------------------------
local function ModuleTitle(name)
	local module = name and E.modules[name]
	return module and L[module.title] or name or ""
end

function E:DetectedAddons()
	local rows = {}
	for _, entry in ipairs(C.list) do
		local module = entry.module and self.modules[entry.module]
		-- A plugin's module that isn't installed has nothing to stand back.
		if entry.scope ~= "alongside" and (module or not entry.module) then
			local loaded, state = Loaded(entry.addon), nil
			if loaded then
				if Overlaps(entry) then
					local choice = Choice(entry)
					if C.disabled[entry.addon] then
						state = "reload"
					elseif choice == "eldoui" then
						state = (entry.scope == "replace" or entry.exclusive) and "fallback" or "eldoui"
					else
						state = "standing"
					end
				end
			elseif Waiting(entry.addon) then
				state = "waiting"
			end
			if state then
				rows[#rows + 1] = { addon = entry.addon, title = self:AddonTitle(entry.addon), module = entry.module,
					moduleTitle = ModuleTitle(entry.module), feature = entry.feature, scope = entry.scope,
					label = entry.label and L[entry.label] or nil, exclusive = entry.exclusive and true or false,
					job = entry.job, loaded = loaded, state = state, entry = entry }
			end
		end
	end
	table.sort(rows, function(a, b)
		if a.moduleTitle ~= b.moduleTitle then return a.moduleTitle < b.moduleTitle end
		if a.title ~= b.title then return a.title < b.title end
		return (a.label or "") < (b.label or "")
	end)
	return rows
end

-- Loaded addons that run alongside an EldoUI module (switched on) doing
-- the same job: one group per addon, { addon, title, jobs = { names }, covers }, where
-- covers is "full" when every one of them does the addon's whole job. Sorted
-- by title.
function E:CoveredAddons()
	local groups, index = {}, {}
	for _, entry in ipairs(C.list) do
		local module = entry.module and self.modules[entry.module]
		-- A module the player switched off does no job.
		if entry.scope == "alongside" and (module or not entry.module) and not (module and not module:IsEnabled())
			and Loaded(entry.addon) then
			local group = index[entry.addon]
			if not group then
				group = { addon = entry.addon, title = self:AddonTitle(entry.addon), jobs = {}, covers = "full" }
				index[entry.addon] = group
				groups[#groups + 1] = group
			end
			local job = module and ModuleTitle(entry.module) or (entry.label and L[entry.label]) or entry.job
			if not tContains(group.jobs, job) then group.jobs[#group.jobs + 1] = job end
			if entry.covers ~= "full" then group.covers = "part" end
		end
	end
	for _, group in ipairs(groups) do table.sort(group.jobs) end
	table.sort(groups, function(a, b) return a.title < b.title end)
	return groups
end

-- What a job is called: the module's title, or "<module>: <feature label>".
function E:CompetitorJobText(row)
	if row.feature and row.label then
		return row.module and L["%s: %s"]:format(row.moduleTitle, row.label) or row.label
	end
	return row.moduleTitle ~= "" and row.moduleTitle or row.job
end

-- Does picking EldoUI for this row turn the other addon off?
function E:CompetitorNeedsDisable(row)
	local entry = row.entry or row
	return (entry.scope == "replace" or entry.exclusive) and Overlaps(entry) and true or false
end

---------------------------------------------------------------------------
-- Choices
---------------------------------------------------------------------------
local function Entry(addon, job)
	for _, entry in ipairs(C.byAddon[addon] or EMPTY) do
		if entry.job == job then return entry end
	end
end

function E:GetCompetitorChoice(addon, job)
	local entry = Entry(addon, job)
	if not entry then return "auto" end
	return Choice(entry)
end

local listeners = {}
-- fn() runs after a choice or a newly loaded addon (the page rebuilds).
function E:OnCompetitorsChanged(fn)
	listeners[#listeners + 1] = fn
end

local function Changed()
	for _, fn in ipairs(listeners) do
		local ok, err = pcall(fn)
		if not ok then geterrorhandler()(err) end
	end
end

-- A module that gates a part on E:StandsBack hears about the change.
local function Tell(entry)
	local module = entry.module and E.modules[entry.module]
	if not (module and module.active and module.OnStandBack) then return end
	local ok, err = pcall(module.OnStandBack, module, entry.feature, (E:StandsBack(module, entry.feature)))
	if not ok then geterrorhandler()(err) end
end

local function SetChoice(entry, value)
	if entry.setting then
		local module = E.modules[entry.setting[1]]
		if module and module.db then module.db[entry.setting[2]] = value == "eldoui" end
		return
	end
	local store = Store()
	if not store then return end
	store.choices = type(store.choices) == "table" and store.choices or {}
	local picks = store.choices[entry.addon]
	if value == "eldoui" then
		if type(picks) ~= "table" then
			picks = {}
			store.choices[entry.addon] = picks
		end
		picks[entry.job] = "eldoui"
	elseif type(picks) == "table" then
		picks[entry.job] = nil
		if next(picks) == nil then store.choices[entry.addon] = nil end
	end
end

function E:SetCompetitorChoice(addon, job, value)
	local entry = Entry(addon, job)
	if not entry then return false end
	SetChoice(entry, value == "eldoui" and "eldoui" or "auto")
	Tell(entry)
	Changed()
	return true
end

-- The only place EldoUI turns another addon off or on again: on the
-- player's own click (or the setup's Finish they confirmed). For this
-- character, from the next reload.
local function DisableCompetitor(addon)
	if not (C_AddOns and C_AddOns.DisableAddOn) then return false end
	C_AddOns.DisableAddOn(addon, Me())
	C.disabled[addon] = true
	return true
end

local function EnableCompetitor(addon)
	if not (C_AddOns and C_AddOns.EnableAddOn) then return false end
	C_AddOns.EnableAddOn(addon, Me())
	C.disabled[addon] = nil
	return true
end

local function Jobs(addon, job)
	local list = {}
	for _, entry in ipairs(C.byAddon[addon] or EMPTY) do
		if job == nil or entry.job == job then list[#list + 1] = entry end
	end
	return list
end

-- "Use EldoUI's" (a click): EldoUI takes the job. A whole module, or a
-- part both can't run on, turns the addon off for this character (after
-- a reload); a part both can run on turns EldoUI's part on now.
-- `disable`: turn the addon off even for parts both can run on.
-- Returns "reload" or "live", or nil when nothing matched.
function E:UseEldoUIFor(addon, job, disable)
	local entries = Jobs(addon, job)
	if #entries == 0 then return nil end
	local off = disable and true or false
	-- A frame owner whose own option is off right now (its `active` check)
	-- holds nothing, so it turns nothing off.
	for _, entry in ipairs(entries) do
		if (entry.scope == "replace" or entry.exclusive) and Overlaps(entry) then off = true end
	end
	if off then
		if not C.disabled[addon] then DisableCompetitor(addon) end
		-- Off for this character: EldoUI does all of its jobs. A "show
		-- both" switch stays as the player set it.
		for _, entry in ipairs(C.byAddon[addon]) do
			if not entry.setting then SetChoice(entry, "eldoui") end
		end
		Changed()
		return "reload"
	end
	for _, entry in ipairs(entries) do
		SetChoice(entry, "eldoui")
		Tell(entry)
	end
	Changed()
	return "live"
end

-- "Keep <Addon>" (a click): the other addon keeps the job and EldoUI
-- stands back again. An addon EldoUI turned off this session (no reload
-- yet) is turned back on, still on this click, and keeps all its jobs.
-- Returns "restored" when it was, else "live"; nil when nothing matched.
function E:KeepCompetitor(addon, job)
	local entries = Jobs(addon, job)
	if #entries == 0 then return nil end
	local restored = false
	if C.disabled[addon] then
		EnableCompetitor(addon)
		restored = true
		entries = C.byAddon[addon]
	end
	for _, entry in ipairs(entries) do
		SetChoice(entry, "auto")
		Tell(entry)
	end
	Changed()
	return restored and "restored" or "live"
end

-- Undo the setup (the player's own click, also after a reload): an addon
-- the setup turned off is on again for this character from the next
-- reload, and its jobs go back to "auto".
function E:TurnCompetitorBackOn(addon)
	if E.Secret(addon) or type(addon) ~= "string" then return false end
	if not EnableCompetitor(addon) then return false end
	for _, entry in ipairs(C.byAddon[addon] or EMPTY) do SetChoice(entry, "auto") end
	Changed()
	return true
end

-- Turned off by the player's click this session (waits for a reload).
function E:CompetitorDisabledNow(addon)
	return C.disabled[addon] and true or false
end

---------------------------------------------------------------------------
-- An addon loaded after login (load on demand): its modules stand back
-- out of combat, with an offer to reload; its parts stand back now.
---------------------------------------------------------------------------
local Late = {}
C.late = Late

function Late.Loaded(name)
	local entries = C.byAddon[name]
	if not entries then return end
	local held = {}
	for _, entry in ipairs(entries) do
		local module = entry.module and E.modules[entry.module]
		if module and entry.scope ~= "alongside" and Overlaps(entry) then
			if entry.scope == "replace" and not entry.feature then
				if module.active then held[#held + 1] = module end
			else
				Tell(entry)
			end
		end
	end
	if #held > 0 then
		E:RunOutOfCombat(function()
			local names = {}
			for _, module in ipairs(held) do
				if module.active and E:GetModuleConflict(module) and E:HoldModule(module) then names[#names + 1] = L[module.title] end
			end
			if #names == 0 then return end
			E:ShowReloadPrompt(L["%s loaded, so EldoUI's %s stepped back. Reload to clear it fully?"]:format(E:AddonTitle(name), table.concat(names, ", ")))
			if E.RefreshConfig then E:RefreshConfig() end
		end)
	end
	Changed()
	if Late.OnLoaded then Late.OnLoaded(name) end
end

E:RegisterEvent("PLAYER_LOGIN", function()
	E:RegisterEvent("ADDON_LOADED", function(_, _, name)
		if type(name) == "string" then Late.Loaded(name) end
	end, C)
end, C, "engines")
