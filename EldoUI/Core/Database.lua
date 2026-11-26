-- EldoUI saved settings and profiles.
-- EldoUIDB = {
--   profileKeys = { ["Name - Realm"] = "Default" },
--   profiles    = { Default = { general = {...}, modules = { [name] = {...} } } },
--   global      = { [namespace] = {...} },                 -- account-wide tier
--   private     = { ["Name - Realm"] = { [namespace] = {...} } }, -- per character
-- }
--
-- Three tiers:
--   profile    E.db       look and layout; shared by every character that
--                         uses the profile, exported and imported.
--   global     E.global   account-wide data that must not change with the
--                         profile: aura filter lists, nameplate filters,
--                         custom datatext panels, keyword lists, the
--                         language. Register a namespace with
--                           local data = E:RegisterGlobal("auraFilters", defaults, { title = "Aura filters", share = true })
--                         (in OnInitialize or later; earlier calls return
--                         nil and the table appears in E.global at login).
--                         `share = true` adds it to Import / Export.
--   private    E.private  per character: engine choices that need a reload,
--                         and module on/off when the player keeps it per
--                         character. E:RegisterPrivate(namespace, defaults).
-- Both tiers save only changes, like profiles.
--
-- Only changes are saved. While the game runs, every profile
-- in use is filled with the defaults (E.defaults for the core, each
-- module's `defaults` for its table), so code reads plain tables. At
-- PLAYER_LOGOUT, after every other logout handler, values equal to their
-- default are stripped again. A default changed in a later EldoUI version
-- therefore reaches every player who never changed that setting, share
-- strings carry only real changes, and the saved file stays small.
local _, E = ...

-- Identity readers must not initialize saved data or run admission callbacks.
-- Consumers retain this reader from the normal file load order.
do
	local environment, read = _G, rawget
	function E:ReadAccountRoot()
		return read(environment, "EldoUIDB")
	end
end
local profileLoadBlocked = true
local CurrentAccount, CurrentProfile, ProfileData, QueueProfileWork, RestoreProfileData, FinishProfilePreparation, InitialProfileSelection, ProfileTable, RebindProfileWrite
local AccountSnapshot, AccountRecord, RestoreAccount, AccountRecovery, InvalidateProfileAdmission, InitializeAccountOwner

E.defaults = {
	general = {
		welcome = true,
		-- The game's Lua error window (scriptErrors): hidden by default,
		-- since EldoUI keeps every error in /eui errors (Core/Errors.lua).
		errorPopup = "HIDE",
	},
	-- The key map (Core/KeybindPresets.lua): the key set this profile uses
	-- ("" not chosen yet; "none": you manage your own keys and EldoUI never
	-- writes one), its options, and what follows the keys (spells, new
	-- spells, other characters, key text on the bars, the quiet bar fill).
	-- homes: your own button for a spell, homes[CLASS][role][spellID] = "b<bar>s<button>".
	keymap = {
		version = 1,
		preset = "",
		custom = "",
		thumb = false,
		pageKeys = "off",
		spells = true,
		newSpells = "offer",
		alts = "offer",
		showKeys = false,
		quietFill = false,
		homes = {},
	},
	-- Gamepad Mode UI (Core/GamepadMode.lua): ask once when the player
	-- starts using a controller; always: place EldoUI's frames for
	-- controller play whenever the game's gamepad interface is on.
	-- movers: the frames dragged while it is on (Core/Movers.lua).
	gamepadUI = {
		ask = true,
		always = false,
		movers = {},
	},
	modules = {},
}

-- Fill in missing keys from `defaults` without overwriting the user's values.
-- A list default ({ "Friends", "Guild" }) is one value, as in StripDefaults:
-- a saved list stays exactly as long as the player left it. Entries
-- that are keyed tables (unit frame extra texts) still get missing fields.
local ApplyDefaults
local function ApplyListDefaults(target, defaults)
	for index, entry in ipairs(target) do
		local default = defaults[index]
		if type(entry) == "table" and type(default) == "table" and default[1] == nil then
			ApplyDefaults(entry, default)
		end
	end
end
function ApplyDefaults(target, defaults)
	for key, value in pairs(defaults) do
		if type(value) == "table" then
			if type(target[key]) ~= "table" then
				target[key] = value[1] ~= nil and CopyTable(value) or {}
			end
			if value[1] ~= nil then
				ApplyListDefaults(target[key], value)
			else
				ApplyDefaults(target[key], value)
			end
		elseif target[key] == nil then
			target[key] = value
		end
	end
	return target
end
E.ApplyDefaults = ApplyDefaults

local function DeepEqual(a, b)
	if a == b then return true end
	if type(a) ~= "table" or type(b) ~= "table" then return false end
	for key, value in pairs(a) do
		if not DeepEqual(value, b[key]) then return false end
	end
	for key in pairs(b) do
		if a[key] == nil then return false end
	end
	return true
end
E.DeepEqual = DeepEqual

-- A list default ({ "Friends", "Guild" }, a color { r, g, b }) is one
-- value: kept whole when any entry differs, so stripping never leaves half
-- a list for ApplyDefaults to refill.
local function IsList(t)
	return t[1] ~= nil
end

-- Remove from `target` every value equal to its default; tables left empty
-- are removed too. Keys without a default (data a module keeps, settings
-- of a newer version) are never touched. Returns true when `target` is now
-- empty. Undone by ApplyDefaults(target, defaults).
local function StripDefaults(target, defaults)
	for key, default in pairs(defaults) do
		local value = target[key]
		if value ~= nil then
			if type(value) == "table" and type(default) == "table" then
				if IsList(default) or IsList(value) then
					if DeepEqual(value, default) then target[key] = nil end
				elseif StripDefaults(value, default) then
					target[key] = nil
				end
			elseif value == default then
				target[key] = nil
			end
		end
	end
	return next(target) == nil
end
E.StripDefaults = StripDefaults

-- Strip one raw profile table in place: the core settings against
-- E.defaults, each module's table against that module's defaults. Settings
-- of modules that aren't loaded (a plugin switched off) are kept as they
-- are, because their defaults are unknown.
function E:CompactProfile(profile)
	if type(profile) ~= "table" then return profile end
	local modules = profile.modules
	for key, default in pairs(self.defaults) do
		if key ~= "modules" and type(profile[key]) == "table" and type(default) == "table" then
			if StripDefaults(profile[key], default) then profile[key] = nil end
		elseif key ~= "modules" and profile[key] == default then
			profile[key] = nil
		end
	end
	if type(modules) == "table" then
		for name, settings in pairs(modules) do
			local module = self.modules and self.modules[name]
			if module and type(settings) == "table" and StripDefaults(settings, module.defaults) then
				modules[name] = nil
			end
		end
		if next(modules) == nil then profile.modules = nil end
	end
	return profile
end

-- The reverse: fill a raw profile with every default it lacks (core and
-- the modules that are loaded).
function E:ExpandProfile(profile)
	ApplyDefaults(profile, self.defaults)
	for name, module in pairs(self.modules or {}) do
		profile.modules[name] = ApplyDefaults(profile.modules[name] or {}, module.defaults)
	end
	return profile
end

-- A copy of `settings` without the values equal to `defaults`, for share
-- strings (the importer fills the defaults back in).
function E:CopyWithoutDefaults(settings, defaults)
	local copy = CopyTable(settings or {})
	if defaults then StripDefaults(copy, defaults) end
	return copy
end

---------------------------------------------------------------------------
-- Account-wide and per-character tiers
---------------------------------------------------------------------------
local globalSpecs = {}   -- namespace -> { defaults, title, share, desc }
local privateSpecs = {}  -- namespace -> { defaults }
E.globalSpecs = globalSpecs

-- Core namespaces. "locale": the language override (Fonts and Text page).
globalSpecs.locale = { defaults = { language = "auto" } }
-- "profiles": module on/off per character instead of per profile.
privateSpecs.profiles = { defaults = { moduleStatesPerCharacter = false, moduleStates = {} } }

local function FillGlobal(namespace)
	local spec = globalSpecs[namespace]
	local store = EldoUIDB.global
	store[namespace] = ApplyDefaults(type(store[namespace]) == "table" and store[namespace] or {}, spec.defaults)
	return store[namespace]
end

local function FillPrivate(namespace)
	local spec = privateSpecs[namespace]
	E.private[namespace] = ApplyDefaults(type(E.private[namespace]) == "table" and E.private[namespace] or {}, spec.defaults)
	return E.private[namespace]
end

-- info: { title = "Aura filters", desc = "...", share = true }. Returns the
-- account-wide table once the saved settings are loaded, else nil.
function E:RegisterGlobal(namespace, defaults, info)
	if type(namespace) ~= "string" then return nil end
	info = info or {}
	globalSpecs[namespace] = { defaults = defaults or {}, title = info.title or namespace, desc = info.desc, share = info.share }
	if self.global then return FillGlobal(namespace) end
end

-- More defaults for a namespace another file registers: a module's own
-- account-wide setting next to the core ones. Call after E:RegisterGlobal;
-- keys the namespace already has keep their default.
function E:AddGlobalDefaults(namespace, defaults)
	local spec = globalSpecs[namespace]
	if not spec or type(defaults) ~= "table" then return nil end
	for key, value in pairs(defaults) do
		if spec.defaults[key] == nil then spec.defaults[key] = value end
	end
	if self.global then return FillGlobal(namespace) end
end

function E:GetGlobal(namespace)
	if not (self.global and globalSpecs[namespace]) then return self.global and self.global[namespace] end
	return FillGlobal(namespace)
end

function E:RegisterPrivate(namespace, defaults)
	if type(namespace) ~= "string" then return nil end
	privateSpecs[namespace] = { defaults = defaults or {} }
	if self.private then return FillPrivate(namespace) end
end

function E:GetPrivate(namespace)
	if not (self.private and privateSpecs[namespace]) then return self.private and self.private[namespace] end
	return FillPrivate(namespace)
end

-- Another character's store of a per-character namespace, read-only, or
-- nil (the alt setup reads the setup picks of the account's characters).
function E:GetPrivateOf(charKey, namespace)
	local all = type(EldoUIDB) == "table" and EldoUIDB.private
	local mine = type(all) == "table" and all[charKey]
	local store = type(mine) == "table" and mine[namespace]
	return type(store) == "table" and store or nil
end

-- Namespaces that can be exported on their own (Import / Export).
function E:SharedGlobals()
	local list = {}
	for namespace, spec in pairs(globalSpecs) do
		if spec.share then list[#list + 1] = { key = namespace, title = E:Translate(spec.title), desc = E:Translate(spec.desc) } end
	end
	table.sort(list, function(a, b) return a.title < b.title end)
	return list
end

local function CompactTier(store, specs)
	if type(store) ~= "table" then return end
	for namespace, spec in pairs(specs) do
		if type(store[namespace]) == "table" and StripDefaults(store[namespace], spec.defaults) then
			store[namespace] = nil
		end
	end
end

---------------------------------------------------------------------------
-- Module on/off per character (Profiles page)
--
-- When the player keeps module on/off per character, the `enabled` value
-- of each module table in the active profile is redirected to
-- E.private.profiles.moduleStates: reads and writes of module.db.enabled
-- (Module:IsEnabled, the Modules page, /eui module) go there, and the
-- profile keeps its own value untouched for the other characters. The
-- profile's value is put back before anything saves or copies the profile.
---------------------------------------------------------------------------
local redirected = setmetatable({}, { __mode = "k" })  -- module db -> { name, value }

local function CharacterStates()
	return E:GetPrivate("profiles").moduleStates
end

local function PerCharacter()
	local private = E.private and E:GetPrivate("profiles")
	return private and private.moduleStatesPerCharacter
end

local function Redirect(name, db)
	if redirected[db] or getmetatable(db) then return end
	local own = rawget(db, "enabled")
	redirected[db] = { name = name, value = own }
	local states = CharacterStates()
	redirected[db].states = states
	if states[name] == nil then
		if own == nil then
			local module = E.modules and E.modules[name]
			own = not (module and module.defaults.enabled == false)
		end
		states[name] = own and true or false
	end
	rawset(db, "enabled", nil)
	setmetatable(db, {
		__index = function(_, key)
			if key == "enabled" then return CharacterStates()[name] end
		end,
		__newindex = function(t, key, value)
			if key == "enabled" then
				-- Stripping defaults writes nil; the character's choice stays.
				if value ~= nil then CharacterStates()[name] = value and true or false end
			else
				rawset(t, key, value)
			end
		end,
	})
	local meta = getmetatable(db)
	local info = redirected[db]
	info.metatable, info.read, info.write = meta, meta.__index, meta.__newindex
end

local function Restore(db)
	local info = redirected[db]
	if not info then return end
	setmetatable(db, nil)
	rawset(db, "enabled", info.value)
	redirected[db] = nil
end

local function RestoreAll()
	local list = {}
	for db in pairs(redirected) do list[#list + 1] = db end
	for _, db in ipairs(list) do Restore(db) end
end
E.RestoreProfileModuleStates = RestoreAll

-- Wrap E:GetModuleDB (Core/Modules.lua) once the core is loaded.
local function HookModuleDB()
	if E.moduleDBHooked or not E.GetModuleDB then return end
	E.moduleDBHooked = true
	local GetModuleDB = E.GetModuleDB
	function E:GetModuleDB(module)
		local db = GetModuleDB(self, module)
		if PerCharacter() then Redirect(module.name, db) end
		return db
	end
end

-- Switch the tier for module on/off. The modules change state at once
-- when the two tiers disagree.
function E:SetModuleStatesPerCharacter(on)
	local private = self:GetPrivate("profiles")
	on = on and true or false
	if private.moduleStatesPerCharacter == on then return end
	if on then
		-- Start from what this character has now.
		local states = CharacterStates()
		for name, module in self:IterateModules() do
			states[name] = module.db and module.db.enabled and true or false
		end
		private.moduleStatesPerCharacter = true
		for name, module in self:IterateModules() do
			if self.db.modules[name] then Redirect(name, self.db.modules[name]); module.db = self.db.modules[name] end
		end
	else
		private.moduleStatesPerCharacter = false
		RestoreAll()
	end
	if self.SyncModuleStates then
		local switchedOff = self:SyncModuleStates()
		-- Asks only when one of them needs a reload to give Blizzard's frames back.
		if #switchedOff > 0 and self.ShowReloadPrompt then self:ShowReloadPrompt(switchedOff) end
	end
end

function E:ModuleStatesPerCharacter()
	return PerCharacter() and true or false
end

-- Read enabled state without invoking an unknown settings metatable or
-- filling defaults. Only this owner's exact per-character redirect is valid.
function E:ModuleEnabledValue(module)
	local Secret = E.Secret
	local function Plain(value)
		return not Secret(value) and type(value) == "table" and type(getmetatable(value)) == "nil"
	end
	local function Same(a, b)
		return not Secret(a) and not Secret(b) and a == b
	end
	if not Same(self, E) or Secret(module) or type(module) ~= "table" then return end
	local name, db = rawget(module, "name"), rawget(module, "db")
	local modules, profile = rawget(self, "modules"), rawget(self, "db")
	if Secret(name) or type(name) ~= "string" or not Plain(modules) or not Plain(profile)
		or not Same(rawget(modules, name), module) or Secret(db) or type(db) ~= "table" then return end
	local settings = rawget(profile, "modules")
	if not Plain(settings) or not Same(rawget(settings, name), db) then return end
	local info, value = redirected[db], rawget(db, "enabled")
	if type(info) == "nil" then
		if not Plain(db) then return end
	else
		local meta = getmetatable(db)
		if not Plain(meta) or not Same(meta, info.metatable) or not Same(info.name, name)
			or not Same(rawget(meta, "__index"), info.read) or not Same(rawget(meta, "__newindex"), info.write)
			or type(value) ~= "nil" then return end
		local saved, private, key = rawget(_G, "EldoUIDB"), rawget(self, "private"), rawget(self, "charKey")
		if not Plain(saved) or not Plain(private) or Secret(key) or type(key) ~= "string" then return end
		local characters, profiles = rawget(saved, "private"), rawget(private, "profiles")
		if not Plain(characters) or not Plain(profiles) or not Same(rawget(characters, key), private)
			or not Same(rawget(profiles, "moduleStatesPerCharacter"), true) then return end
		local states = rawget(profiles, "moduleStates")
		if not Plain(states) or not Same(states, info.states) then return end
		value = rawget(states, name)
	end
	if not Secret(value) and type(value) == "boolean" then return value end
end

-- A plain copy of a profile with every module's own on/off value, also
-- while module on/off is kept per character.
function E:CopyProfileTable(name)
	if type(name) == "nil" then name = self.profileName end
	if not CurrentAccount() or E.Secret(name) or type(name) ~= "string" then return nil end
	local profile = EldoUIDB.profiles[name or self.profileName]
	if not CurrentProfile(profile, name) then return nil end
	local copy = CopyTable(profile)
	if profile == self.db and type(profile.modules) == "table" then
		for moduleName, settings in pairs(profile.modules) do
			local info = redirected[settings]
			if info and copy.modules[moduleName] then copy.modules[moduleName].enabled = info.value end
		end
	end
	return copy
end

---------------------------------------------------------------------------
-- Saving
---------------------------------------------------------------------------
-- Every profile, not only the active one: SetProfile and copies filled the
-- others with defaults in earlier sessions (and before this fix). The
-- account-wide and per-character tiers are compacted the same way.
--
-- The saved file gets compacted copies; the tables in use keep every
-- default. The game still runs events after logout (nameplates going away,
-- frames resizing), and the code they reach reads its settings as usual.
-- What this login's saved data update found and did (section "Saved
-- data versions" below). notices: the chat lines for the player;
-- failedRoots: tables an update step failed on; stores: what the checks
-- of each saved part found (section "Backups, checks and restore");
-- backups: copies taken before an update; trimmed: old copies let go to
-- keep the file small.
local schemaRun = { notices = {}, failedRoots = {}, stores = {}, backups = 0, trimmed = 0 }

local function CompactCopy(value, compact)
	if type(value) ~= "table" then return value end
	local copy = CopyTable(value)
	compact(copy)
	return copy
end

function E:CompactSavedSettings()
	if profileLoadBlocked or not CurrentAccount() or not CurrentProfile(self.db, self.profileName) then return end
	if type(EldoUIDB) ~= "table" then return end
	RestoreAll()
	-- A table an update step failed on stays exactly as it is.
	local failed = schemaRun.failedRoots
	if type(EldoUIDB.profiles) == "table" and not failed.profiles then
		local profiles = {}
		for name, profile in pairs(EldoUIDB.profiles) do
			-- A profile a newer EldoUI wrote stays exactly as it is: a value
			-- that equals this version's default may not equal that one's.
			if not CurrentProfile(profile, name) then
				profiles[name] = profile
			else
				profiles[name] = CompactCopy(profile, function(copy) self:CompactProfile(copy) end)
			end
		end
		EldoUIDB.profiles = profiles
	end
	if not failed.global then
		EldoUIDB.global = CompactCopy(EldoUIDB.global, function(copy) CompactTier(copy, globalSpecs) end)
	end
	if type(EldoUIDB.private) == "table" and not failed.private then
		local private = {}
		for key, store in pairs(EldoUIDB.private) do
			private[key] = CompactCopy(store, function(copy) CompactTier(copy, privateSpecs) end)
		end
		EldoUIDB.private = private
	end
end

-- Last of all logout work, while the live profile still owns its saved slot.
-- History uses that admission too; compact copies detach it afterward.
do
	local serializer, getter, active, admit, ready
	local compact = E.CompactSavedSettings
	E:OnDatabaseLoad(function()
		if ready then return end
		local save, read, current, supported = rawget(E, "SaveSetupHistory"), rawget(E, "GetApplyGeneration"),
			rawget(E, "IsApplyGenerationCurrent"), rawget(E, "IsCurrentProfile")
		if E.Secret(save) or (type(save) ~= "nil" and type(save) ~= "function")
			or E.Secret(read) or type(read) ~= "function" or E.Secret(current) or type(current) ~= "function"
			or E.Secret(supported) or type(supported) ~= "function" then return end
		serializer, getter, active, admit, ready = save, read, current, supported, true
	end)
	local function Same(name, expected)
		local value = rawget(E, name)
		return not E.Secret(value) and value == expected
	end
	local function OwnersCurrent()
		return ready and Same("SaveSetupHistory", serializer) and Same("GetApplyGeneration", getter)
			and Same("IsApplyGenerationCurrent", active) and Same("IsCurrentProfile", admit)
			and Same("CompactSavedSettings", compact)
	end
	E:RegisterLastHandler("PLAYER_LOGOUT", function()
		if not OwnersCurrent() or not CurrentAccount() or not CurrentProfile(E.db, E.profileName) then return end
		local profile, name, character = E.db, E.profileName, E.charKey
		local general = rawget(profile, "general")
		local read, generation = pcall(getter, E, "profile")
		if not read or E.Secret(generation) or type(generation) ~= "number" or generation ~= generation
			or generation < 1 or generation >= math.huge or generation % 1 ~= 0 then return end
		local function Current()
			if not OwnersCurrent() or not CurrentAccount() or not CurrentProfile(profile, name)
				or E.Secret(E.db) or E.db ~= profile or E.Secret(E.profileName) or E.profileName ~= name
				or E.Secret(E.charKey) or E.charKey ~= character or not ProfileTable(general)
				or E.Secret(rawget(profile, "general")) or rawget(profile, "general") ~= general then return false end
			local ok, now = pcall(getter, E, "profile")
			return ok and not E.Secret(now) and now == generation and OwnersCurrent() and CurrentAccount()
				and CurrentProfile(profile, name) and not E.Secret(E.db) and E.db == profile
				and not E.Secret(E.profileName) and E.profileName == name and not E.Secret(E.charKey) and E.charKey == character
				and not E.Secret(rawget(profile, "general")) and rawget(profile, "general") == general
		end
		if not Current() then return end
		if serializer then
			local saved = serializer(E)
			if E.Secret(saved) or saved ~= true or not Current() then return end
		end
		if Current() then compact(E) end
	end)
end

---------------------------------------------------------------------------
-- Saved data versions
--
-- Every part of the saved file that can travel on its own has a version
-- number, so an update knows what it reads:
--   EldoUIDB.schema   the account file: { version, eldoui (the EldoUI
--                     version that wrote it), at, history = the last ten
--                     moves { from, to, eldoui, at } }
--   profile.schema    one profile (next to its profile.migrations stamps)
--   a store's marker  the store's own number (journal records keep `v`,
--                     the Instances store `version`), declared below
--   payload.schema    share strings: { unit, version } (Core/Share.lua)
-- A file without a number is version 0. Numbers only ever go up.
--
-- Rules for every update step: it only adds (a new key next to the old
-- one, a missing table filled in); it never removes a key, shortens a
-- list or renames a table in place; running it twice gives the same
-- result; it works on one part (one profile, one store), never on the
-- whole file; it never applies a layout or calls the game for anything a
-- loading screen does not know yet.
--
-- When the saved file is newer than this EldoUI (an older version was
-- installed again), nothing is updated and settings this version does
-- not know stay as they are.
---------------------------------------------------------------------------
E.SCHEMA_VERSION = 1   -- the account file this EldoUI writes
E.PROFILE_SCHEMA = 6   -- one profile this EldoUI writes
E.PROFILE_BASELINE = 1000 -- first supported profile generation
local TakeProfilePreparation, CharacterIdentity
do
	local prepared, admitted, pendingRebind
	-- The first supported generation writes schema 4. Later schema updates
	-- may still read that shape; older shapes are not supported profiles.
	local firstProfileSchema = 4
	local roots = { "profiles", "profileKeys", "profileRules", "classProfiles", "importedLayouts", "setupHistory",
		"installed", "installerRun", "installerBackup", "installerLogin" }
	local function Plain(value)
		return not E.Secret(value) and type(value) == "table" and type(getmetatable(value)) == "nil"
	end
	ProfileTable = Plain
	local function Integer(value)
		return not E.Secret(value) and type(value) == "number" and value >= 0 and value < math.huge and value % 1 == 0
	end
	local function Same(a, b)
		return not E.Secret(a) and not E.Secret(b) and a == b
	end
	local function AccountVersion(root)
		local schema = rawget(root, "schema")
		if type(schema) == "nil" then return true end
		if not Plain(schema) then return false end
		local version = rawget(schema, "version")
		if type(version) ~= "nil" and (not Integer(version) or version > E.SCHEMA_VERSION) then return false end
		return true, schema, version
	end
	local function ProfileHold(key)
		if E.Secret(key) or type(key) ~= "string" then return false end
		if key:sub(1, 8) == "profile:" then return true end
		for _, name in ipairs(roots) do
			if key == name or key:sub(1, #name + 1) == name .. ":" then return true end
		end
		return false
	end
	ProfileData = function(profile)
		if not Plain(profile) or not Same(rawget(profile, "profileBaseline"), E.PROFILE_BASELINE) then return false end
		local version = rawget(profile, "schema")
		return Integer(version) and version >= firstProfileSchema and version <= E.PROFILE_SCHEMA, version
	end
	CurrentAccount = function(initializing)
		local root = rawget(_G, "EldoUIDB")
		if not admitted or (not admitted.ready and not initializing) or not Plain(root) or not Same(root, admitted.root)
			or not Same(rawget(root, "profileBaseline"), E.PROFILE_BASELINE) then return false end
		local profiles = rawget(root, "profiles")
		if not Plain(profiles) or not Same(profiles, admitted.profiles) or not AccountVersion(root) then return false end
		if admitted.ready then
			local private, keys = rawget(root, "private"), rawget(root, "profileKeys")
			if E.Secret(E.charKey) or type(E.charKey) ~= "string" or not Same(E.charKey, admitted.character)
				or not Plain(private) or not Plain(keys) or not Same(private, admitted.private)
				or not Same(keys, admitted.keys) or not Same(rawget(private, E.charKey), E.private) then return false end
		end
		return true
	end
	CurrentProfile = function(profile, name, initializing)
		if not CurrentAccount(initializing) or E.Secret(name) or type(name) ~= "string" or not ProfileData(profile)
			or not Same(rawget(admitted.profiles, name), profile) then return false end
		if admitted.ready and Same(name, E.profileName) then
			return Same(E.db, profile) and Same(rawget(admitted.keys, E.charKey), name)
		end
		return true
	end
	function E:IsCurrentProfile(profile, name)
		if type(profile) == "nil" then profile = self.db end
		if type(name) == "nil" then name = self.profileName end
		return CurrentProfile(profile, name)
	end
	-- Detached source shape only; this does not establish slot membership
	-- or ownership of the active destination.
	function E:IsSupportedProfileData(profile)
		return CurrentAccount() and ProfileData(profile)
	end
	RebindProfileWrite = function(self, root, profiles, active, name, expected)
		if not CurrentAccount() or not Same(EldoUIDB, root) or not Same(admitted.profiles, profiles)
			or not Same(self.db, active) or not Same(self.profileName, name)
			or not Same(rawget(profiles, name), expected) or not Same(rawget(admitted.keys, E.charKey), name) then return false end
		-- A quick profile rebuild stays with this admitted character even
		-- while live identity is temporarily unavailable.
		pendingRebind = { root = root, key = admitted.character, aliases = {} }
		local ok, loaded, reason = pcall(self.LoadDatabase, self)
		pendingRebind = nil
		if not ok then error(loaded, 0) end
		return loaded, reason
	end
	InitialProfileSelection = function(name, grant)
		if not CurrentAccount(true) or admitted.ready then return false end
		if grant then admitted.initialName = name; return true end
		local allowed = Same(admitted.initialName, name)
		admitted.initialName = nil
		return allowed
	end
	-- Existing combat work keeps its original source and destination; a
	-- replaced profile or account cannot turn an old request into a new one.
	QueueProfileWork = function(self, fn, target, source)
		if not InCombatLockdown() then return false end
		local root, profiles, active, name, character = admitted.root, admitted.profiles, self.db, self.profileName, self.charKey
		local previous = target and rawget(profiles, target)
		local generation = self:NewApplyGeneration("profile")
		self:Print(self.L["The profile changes after combat."])
		self:RunOutOfCombat(function()
			if not CurrentProfile(active, name) or not Same(EldoUIDB, root) or not Same(E.db, active)
				or not Same(E.profileName, name) or not Same(E.charKey, character)
				or (target and not Same(rawget(profiles, target), previous))
				or (source and not CurrentProfile(source.profile, source.name)) then return end
			fn()
		end, "profile:switch", { generation = generation, lane = "profile" })
		return true
	end
	RestoreProfileData = function(kind, key, data, envelope)
		if not CurrentAccount() then return false end
		local relevant = kind == "profile" or kind == "private" or kind == "schema" or kind == "EldoUIDB"
		for _, name in ipairs(roots) do if kind == name then relevant = true end end
		if not relevant then return true, false end
		-- A whole account file is never restored here: it would also replace
		-- what holds the settings while the game runs.
		if kind == "EldoUIDB" then return false end
		if not Plain(envelope) or not Same(rawget(envelope, "profileBaseline"), E.PROFILE_BASELINE) or not Plain(data) then return false end
		if kind == "profile" then
			if E.Secret(key) or type(key) ~= "string" then return false end
			local previous = rawget(admitted.profiles, key)
			return ProfileData(data) and (type(previous) == "nil" or CurrentProfile(previous, key))
		end
		if kind == "profiles" then
			for name, profile in pairs(data) do
				if E.Secret(name) or type(name) ~= "string" or not ProfileData(profile) then return false end
			end
		elseif kind == "profileKeys" then
			for character, name in pairs(data) do
				if E.Secret(character) or type(character) ~= "string" or E.Secret(name) or type(name) ~= "string"
					or not CurrentProfile(rawget(admitted.profiles, name), name) then return false end
			end
		elseif kind == "private" then
			for _, character in pairs(data) do if not Plain(character) then return false end end
		elseif kind == "schema" then
			local version = rawget(data, "version")
			if not Integer(version) or version > E.SCHEMA_VERSION then return false end
		end
		return true, true
	end
	FinishProfilePreparation = function()
		if not CurrentProfile(E.db, E.profileName, true) then return false end
		admitted.private, admitted.keys = rawget(EldoUIDB, "private"), rawget(EldoUIDB, "profileKeys")
		admitted.character = E.charKey
		if not Plain(admitted.private) or not Plain(admitted.keys) then return false end
		admitted.ready = true
		if not CurrentProfile(E.db, E.profileName) or (AccountRecovery and not AccountRecovery(EldoUIDB, true)) then
			admitted = nil
			return false
		end
		return true
	end
	InvalidateProfileAdmission = function()
		prepared, admitted, profileLoadBlocked = nil, nil, true
	end
	-- This runs before saved-layout and profile-binding load hooks. Account
	-- data and other characters' non-profile namespaces remain in place.
	function E:PrepareProfileBaseline()
		local root = rawget(_G, "EldoUIDB")
		local rebind = pendingRebind
		pendingRebind = nil
		local identity = rebind and Same(rebind.root, root) and CurrentAccount() and rebind or CharacterIdentity()
		if not identity then return false, "identity" end
		prepared, admitted, profileLoadBlocked = nil, nil, true
		if AccountRecovery and not AccountRecovery(root, false) then return false end
		local cold = type(root) == "nil"
		if not cold and not Plain(root) then return false end
		if cold then root = {} end
		local allowed, schema, version = AccountVersion(root)
		if not allowed then return false end
		local baseline = rawget(root, "profileBaseline")
		if E.Secret(baseline) or (type(baseline) ~= "nil" and (not Integer(baseline) or baseline > self.PROFILE_BASELINE)) then return false end
		if not Same(baseline, self.PROFILE_BASELINE) then
			local private = rawget(root, "private")
			if type(private) ~= "nil" and not Plain(private) then return false end
			for _, character in pairs(private or {}) do
				if E.Secret(character) or (type(character) == "table" and not Plain(character)) then return false end
			end
			local hold = schema and rawget(schema, "hold")
			if type(hold) ~= "nil" and not Plain(hold) then return false end
			for key in pairs(hold or {}) do
				if E.Secret(key) then return false end
			end
			-- Admission above is complete before the first saved-data write.
			for _, name in ipairs(roots) do rawset(root, name, {}) end
			for _, character in pairs(private or {}) do
				if type(character) == "table" then
					rawset(character, "profiles", nil)
					rawset(character, "setupParts", nil)
				end
			end
			for key in pairs(hold or {}) do if ProfileHold(key) then rawset(hold, key, nil) end end
			rawset(root, "profileBaseline", self.PROFILE_BASELINE)
		end
		if cold then EldoUIDB = root end
		prepared = { root = root, cold = cold, schema = schema, version = version, identity = identity }
		return true
	end
	TakeProfilePreparation = function()
		local saved = prepared
		prepared = nil
		if not saved or not Plain(EldoUIDB) or not Same(EldoUIDB, saved.root)
			or not Same(rawget(EldoUIDB, "profileBaseline"), E.PROFILE_BASELINE) then return false end
		local allowed, schema, version = AccountVersion(EldoUIDB)
		if not allowed or not Same(schema, saved.schema) or not Same(version, saved.version) then return false end
		local profiles, private, keys = rawget(EldoUIDB, "profiles"), rawget(EldoUIDB, "private"), rawget(EldoUIDB, "profileKeys")
		if not Plain(profiles) or not Plain(keys) or (type(private) ~= "nil" and not Plain(private)) then return false end
		admitted = { root = EldoUIDB, profiles = profiles, ready = false }
		return true, saved.cold, saved.identity
	end
end
local HISTORY_KEEP = 10
-- Seconds after login before the other profiles are brought up to date,
-- so the login itself stays light.
local PROFILE_PASS_DELAY = 3

local function Now()
	return time and time() or 0
end

---------------------------------------------------------------------------
-- The saved data registry: every table EldoUI keeps in its saved files,
-- who owns it, how it is keyed and where its version number sits.
--
--   E:RegisterStore(name, {
--       root = "journal",        -- the EldoUIDB key (default: name)
--       savedVariable = "...",   -- a whole saved table instead of a root key
--       owner = "Adventure",     -- the module or core part that writes it
--       key = "charKey",         -- how per-character parts are keyed (below)
--       version = 1,             -- the number this EldoUI writes
--       versionKey = "v",        -- where that number sits in each part
--       legacy = true,           -- kept as it is: nothing writes it any more
--       shape = "...",           -- what it holds, in a few words
--       title = "Instance log",  -- its name on the Saved data page
--       perKey = true,           -- one part per key (a journal per character)
--       validate = fn,           -- the load check (section "Backups, checks
--                                -- and restore")
--       backup = fn,             -- takes its own copy before an update
--   })
-- Shown translated: L["Messages"], L["Characters (an older EldoUI addon, no longer used)"],
-- L["Characters (an older list, no longer used)"], L["Instance log"], L["Journal of %s"],
-- L["Loot Guide of %s"], L["Journal: places and quests seen"], L["Mob info"],
-- L["Setup changes to undo on %s"]
-- A second call for the same name adds to the first (a module can add
-- its own details to a table the core declared). E:StoreInfo(name) finds
-- one by name or root key; E.stores lists them all.
--
-- Keys (per-character parts are never re-keyed by an update):
--   charKey   "<name> - <realm name>" (E.charKey)
--   ruleset   "<name> - <ruleset>" (E:RealmKey() on Forever)
--   account, profile, realm, guild, item, class, layout, cvar, window,
--   quest   one table for the account, or keyed by that thing
---------------------------------------------------------------------------
E.stores = {}

function E:RegisterStore(name, spec)
	if type(name) ~= "string" or name == "" then return nil end
	spec = type(spec) == "table" and spec or {}
	local info = self.stores[name] or { name = name, owner = "Core", key = "account", legacy = false }
	for field, value in pairs(spec) do info[field] = value end
	if not info.savedVariable then info.root = info.root or name end
	info.version = tonumber(info.version)
	info.legacy = info.legacy and true or false
	self.stores[name] = info
	return info
end

function E:StoreInfo(name)
	if type(name) ~= "string" then return nil end
	if self.stores[name] then return self.stores[name] end
	for _, info in pairs(self.stores) do
		if info.root == name or info.savedVariable == name then return info end
	end
	return nil
end

-- The version a share string or backup of `unit` carries: a profile's,
-- a registered store's, else the account file's.
function E:SchemaVersionFor(unit)
	if unit == "profile" or unit == "all" or unit == "general" or unit == "positions"
		or (type(unit) == "string" and unit:match("^module:")) then
		return self.PROFILE_SCHEMA
	end
	local info = self:StoreInfo(unit)
	if info and info.version then return info.version end
	return self.SCHEMA_VERSION
end

-- The saved tables themselves.
E:RegisterStore("EldoUIDB", { savedVariable = "EldoUIDB", owner = "Core", version = E.SCHEMA_VERSION, versionKey = "schema" })
E:RegisterStore("EldoUIErrorsDB", { savedVariable = "EldoUIErrorsDB", owner = "Errors" })
E:RegisterStore("EldoUIMessagesDB", { savedVariable = "EldoUIMessagesDB", owner = "ChatMessages", key = "character", version = 2, versionKey = "version",
	title = "Messages" })

-- EldoUIDB root keys. Core: profiles, tiers, setup and windows.
E:RegisterStore("schema", { owner = "Core" })
E:RegisterStore("profileKeys", { owner = "Core", key = "charKey" })
E:RegisterStore("profiles", { owner = "Core", key = "profile", version = E.PROFILE_SCHEMA, versionKey = "schema" })
E:RegisterStore("global", { owner = "Core" })
E:RegisterStore("private", { owner = "Core", key = "charKey" })
-- Answers to "bring over your data" after a ruleset move: "<old key>\n<new
-- key>" -> "moved" or "fresh" (section "A character that moved").
E:RegisterStore("rulesetMoves", { owner = "Core" })
E:RegisterStore("installed", { owner = "Installer", key = "charKey" })
E:RegisterStore("installerRun", { owner = "Installer", key = "charKey" })
E:RegisterStore("installerBackup", { owner = "Installer", key = "charKey" })
E:RegisterStore("installerLogin", { owner = "Installer", key = "charKey" })
-- The setup undo history, outside the profiles so a share string or a
-- profile copy never carries it (Core/Layout.lua).
E:RegisterStore("setupHistory", { owner = "Layout", key = "profile", version = 1, versionKey = "v", perKey = true,
	title = "Setup changes to undo on %s", shape = "the newest setup changes of each profile, before and after" })

function E:SavedSetupHistory()
	return type(EldoUIDB) == "table" and EldoUIDB.setupHistory or nil
end

function E:WriteSetupHistory(saved)
	if type(EldoUIDB) == "table" then EldoUIDB.setupHistory = saved end
end
E:RegisterStore("importOptions", { owner = "Import" })
E:RegisterStore("importedLayouts", { owner = "Import", key = "layout" })
E:RegisterStore("profileRules", { owner = "ProfileRules", key = "charKey" })
E:RegisterStore("classProfiles", { owner = "ProfileRules", key = "class" })
E:RegisterStore("keybindBackup", { owner = "KeybindPresets", key = "charKey" })
E:RegisterStore("cvarSnapshot", { owner = "Blizzard", key = "cvar" })
E:RegisterStore("captures", { owner = "AddonSetup" })
E:RegisterStore("addonProfiles", { owner = "AddonSetup" })
E:RegisterStore("configWindow", { owner = "Config" })
E:RegisterStore("errorWindow", { owner = "Errors" })
E:RegisterStore("windowSizes", { owner = "UIKit", key = "window" })
E:RegisterStore("auraFilters", { owner = "Filters" })
E:RegisterStore("dungeonMaps", { owner = "DungeonMaps" })
-- Written by the character store (Core/CharacterStore.lua); the Alts
-- window, the bags and the tooltips read them.
E:RegisterStore("inventory", { owner = "CharacterStore", key = "charKey" })
E:RegisterStore("guildBanks", { owner = "CharacterStore", key = "guild" })
-- Nothing writes it any more; only "forget this character" clears it.
E:RegisterStore("chars", { owner = "Characters", key = "charKey", legacy = true, title = "Characters (an older list, no longer used)" })
-- Modules. The Loot Guide family: the Journal (Adventure) keeps one record
-- per character, its backups as codes, a cache of pending rows and kept
-- orphans, and the quests it has seen; the Loot Guide keeps per-character
-- lists and choices, an account cache keyed by game build and language,
-- the shared wish lists and the tours already shown; Attunements keeps the
-- quests it has seen and what guild members reported.
E:RegisterStore("journal", { owner = "Adventure", key = "charKey", version = 1, versionKey = "v" })
E:RegisterStore("journalBackups", { owner = "Adventure", key = "charKey" })
E:RegisterStore("journalCache", { owner = "Adventure" })
E:RegisterStore("journalSeen", { owner = "Adventure", key = "quest", version = 1, versionKey = "v" })
E:RegisterStore("instances", { owner = "Instances", key = "ruleset", version = 2, versionKey = "version" })
E:RegisterStore("lootGuide", { owner = "LootGuide", key = "charKey", version = 1, versionKey = "schema" })
E:RegisterStore("lootGuideCache", { owner = "LootGuide", version = 1, versionKey = "schema" })
E:RegisterStore("lootGuideLists", { owner = "LootGuide" })
E:RegisterStore("lootGuideTours", { owner = "LootGuide" })
E:RegisterStore("attuneSeen", { owner = "Attunements", key = "quest" })
E:RegisterStore("attunePeers", { owner = "Attunements" })
E:RegisterStore("auction", { owner = "Auction" })
E:RegisterStore("vendorBuy", { owner = "Merchant", key = "item" })
E:RegisterStore("mailRecent", { owner = "Mail", key = "realm" })
E:RegisterStore("mailSent", { owner = "Mail", key = "realm" })
E:RegisterStore("trades", { owner = "Trade" })
E:RegisterStore("mobInfo", { owner = "MobInfo", version = 1, versionKey = "v" })
E:RegisterStore("qol", { owner = "QoL" })
E:RegisterStore("notifications", { owner = "Notifications" })
E:RegisterStore("screenFade", { owner = "AFK" })
E:RegisterStore("detailsPreviousProfile", { owner = "Setups" })
E:RegisterStore("bgProbe", { owner = "Battlegrounds", version = 1, versionKey = "version" })
E:RegisterStore("talentProbe", { owner = "Talents" })

---------------------------------------------------------------------------
-- Account file update steps: E:RegisterSchemaStep(version, root, fn[, name])
-- adds a step that brings EldoUIDB[root] up to `version`. fn(unit, from)
-- gets that table (nil when the file has none; a table it returns is
-- kept) and the version the file had. Steps run at load in version order,
-- each protected. When one fails, the file keeps the last version that
-- finished, the failure is noted in EldoUIDB.schema.failed, nothing after
-- it runs, the table it worked on is not compacted at logout, and the
-- next login tries again.
---------------------------------------------------------------------------
E.schemaSteps = {}

function E:RegisterSchemaStep(version, root, fn, name)
	version = tonumber(version)
	if not version or type(root) ~= "string" or type(fn) ~= "function" then return nil end
	local step = { version = version, root = root, fn = fn, name = name or root }
	table.insert(self.schemaSteps, step)
	return step
end

local SetAsideCount, MovedText, SetAsideText   -- section "Backups, checks and restore"

-- The chat lines of this login, at most one about the update itself.
function E:SavedDataNotices()
	local list = {}
	local setAside = SetAsideCount()
	for index, text in ipairs(schemaRun.notices) do
		if index == schemaRun.movedNotice then
			text = MovedText(setAside)
			setAside = 0
		end
		list[#list + 1] = text
	end
	if setAside > 0 then list[#list + 1] = SetAsideText(setAside) end
	if schemaRun.trimmed > 0 then
		list[#list + 1] = E:Plural(schemaRun.trimmed, "To keep your saved file small, EldoUI let go of its oldest backup copy. Your journal's newest copy from before an update is always kept.",
			"To keep your saved file small, EldoUI let go of its %d oldest backup copies. Your journal's newest copy from before an update is always kept."):format(schemaRun.trimmed)
	end
	return list
end

-- "newer" when the saved file comes from a newer EldoUI, "moved" when
-- this login updated it, "failed" when a step failed, else "current".
function E:SavedDataState()
	if profileLoadBlocked then return "failed" end
	return schemaRun.state or "current"
end

local function Notice(text)
	table.insert(schemaRun.notices, text)
end

local function StepsUpTo(target, from)
	local list = {}
	for index, step in ipairs(E.schemaSteps) do
		if step.version > from and step.version <= target then list[#list + 1] = { step = step, index = index } end
	end
	table.sort(list, function(a, b)
		if a.step.version ~= b.step.version then return a.step.version < b.step.version end
		return a.index < b.index
	end)
	return list
end

local function RunRootChain(db, fresh)
	local target = tonumber(E.SCHEMA_VERSION) or 0
	local schema = db.schema
	if schema ~= nil and type(schema) ~= "table" then
		-- Not ours to read: kept inside the new record.
		schema = { previous = schema }
		db.schema = schema
	end
	local from = schema and tonumber(schema.version) or 0
	if from > target then
		schemaRun.state = "newer"
		Notice(E.L["Your EldoUI settings were saved by a newer version of EldoUI. They are kept exactly as they are, including what this version doesn't know."])
		return
	end
	if fresh then
		-- A new install starts at the current version: nothing to update.
		db.schema = { version = target, eldoui = E.version, at = Now(), history = {} }
		schemaRun.state = "current"
		return
	end
	if from == target then
		schemaRun.state = "current"
		return
	end
	schema = schema or {}
	db.schema = schema
	if type(schema.history) ~= "table" then schema.history = {} end
	local reached, failed = from, nil
	local steps = StepsUpTo(target, from)
	local position = 1
	for version = from + 1, target do
		while steps[position] and steps[position].step.version == version do
			local step = steps[position].step
			local ok, result = pcall(step.fn, db[step.root], from)
			if not ok then
				failed = { version = version, step = step.name, err = tostring(result), at = Now() }
				schemaRun.failedRoots[step.root] = true
				break
			end
			if type(result) == "table" and db[step.root] == nil then db[step.root] = result end
			position = position + 1
		end
		if failed then break end
		reached = version
	end
	schema.version = reached
	schema.eldoui = E.version
	schema.at = Now()
	if reached > from then
		table.insert(schema.history, { from = from, to = reached, eldoui = E.version, at = Now() })
		while #schema.history > HISTORY_KEEP do table.remove(schema.history, 1) end
	end
	if failed then
		schema.failed = failed
		schemaRun.state = "failed"
		geterrorhandler()(("EldoUI saved data update to version %d (%s): %s"):format(failed.version, failed.step, failed.err))
		Notice(E.L["Some EldoUI settings could not be updated this time. They are kept as they were, and the update runs again at your next login."])
	else
		schema.failed = nil
		schemaRun.state = "moved"
		-- The words are chosen when the line is shown: they name the
		-- backup copies and what the checks set aside by then.
		Notice(E.L["Your EldoUI settings were updated for this version. Nothing was removed."])
		schemaRun.movedNotice = #schemaRun.notices
	end
end

---------------------------------------------------------------------------
-- Profile versions. A profile below E.PROFILE_SCHEMA first gets the
-- default changes it missed (Data/DefaultChanges.lua): where a default
-- changed and the profile holds no value of its own, the old default is
-- written in, so the player keeps what they saw. Then its migrations run
-- and, when they all passed, profile.schema is set. The active profile
-- goes through this when it loads; every other profile a few seconds
-- after login, in small steps and never in combat.
---------------------------------------------------------------------------
local function ProfileSchema(profile)
	return type(profile) == "table" and tonumber(profile.schema) or 0
end

local function PathKeys(path)
	local keys = {}
	for part in tostring(path):gmatch("[^%.]+") do keys[#keys + 1] = tonumber(part) or part end
	return keys
end

-- Write `value` at `path` only when nothing is there; tables on the way
-- are created when missing, never replaced.
local function FillPath(target, path, value)
	local keys = PathKeys(path)
	if #keys == 0 then return false end
	for index = 1, #keys - 1 do
		local key = keys[index]
		if target[key] == nil then target[key] = {} end
		if type(target[key]) ~= "table" then return false end
		target = target[key]
	end
	local last = keys[#keys]
	if target[last] ~= nil then return false end
	target[last] = type(value) == "table" and CopyTable(value) or value
	return true
end

function E:ApplyDefaultChanges(profile, from, path)
	if type(profile) ~= "table" then return 0 end
	if path ~= nil and type(path) ~= "string" then return 0 end
	from = tonumber(from) or ProfileSchema(profile)
	local written = 0
	for _, row in ipairs(self.defaultChanges or {}) do
		local version = type(row) == "table" and tonumber(row.schema)
		if version and row.keep and version > from and version <= self.PROFILE_SCHEMA and type(row.path) == "string"
			and row.from ~= nil and (path == nil or row.path == path) then
			if FillPath(profile, row.path, row.from) then written = written + 1 end
		end
	end
	return written
end

local CheckProfile   -- section "Backups, checks and restore"

-- Bring one profile that is not in use up to date. name: its name in
-- EldoUIDB.profiles, for the backup copy and the hold. Returns true when
-- it needed it.
function E:UpdateProfileTable(profile, name)
	if not CurrentProfile(profile, name) then return false end
	if type(profile) ~= "table" then return false end
	local from = ProfileSchema(profile)
	if from >= self.PROFILE_SCHEMA then return false end
	if name ~= nil then
		-- Put back by the player: it stays as it is until they say otherwise.
		if self:IsHeld("profile:" .. tostring(name), self.PROFILE_SCHEMA) then return false end
		self:BackupUnit("profile", name, profile, from, self.PROFILE_SCHEMA)
		CheckProfile(profile, name)
	end
	self:ApplyDefaultChanges(profile, from)
	if self:RunProfileMigrations(profile) then profile.schema = self.PROFILE_SCHEMA end
	return true
end

-- Every saved profile except the active one, sliced. Returns the sliced
-- handle (handle:Finish() completes it at once).
function E:UpdateAllProfiles()
	if profileLoadBlocked or not CurrentAccount() then return nil end
	if schemaRun.state == "newer" or type(EldoUIDB) ~= "table" or type(EldoUIDB.profiles) ~= "table" then return nil end
	local db = EldoUIDB
	local names = {}
	for name in pairs(db.profiles) do names[#names + 1] = name end
	table.sort(names, function(a, b) return tostring(a) < tostring(b) end)
	return self:RunSliced(function()
		for _, name in ipairs(names) do
			-- A new login with other saved tables ends this pass.
			if profileLoadBlocked or EldoUIDB ~= db then return end
			local profile = db.profiles[name]
			if CurrentProfile(profile, name) and profile ~= self.db and ProfileSchema(profile) < self.PROFILE_SCHEMA then self:UpdateProfileTable(profile, name) end
			self.SliceYield()
		end
	end)
end

-- The chat lines, once per set of saved tables. They wait until the
-- saved parts a login reads have been checked, so one line can say all.
local function ShowNotices()
	if schemaRun.shown then return end
	schemaRun.shown = true
	for _, text in ipairs(E:SavedDataNotices()) do E:Print(text) end
end

-- A few seconds after login: the chat lines, then the other profiles.
local pendingProfilePass
local function StartProfilePass()
	if profileLoadBlocked then return end
	local db, pass = EldoUIDB, {}
	pendingProfilePass = pass
	C_Timer.After(PROFILE_PASS_DELAY, function()
		if pendingProfilePass ~= pass then return end
		pendingProfilePass = nil
		if profileLoadBlocked or EldoUIDB ~= db then return end
		ShowNotices()
		E:UpdateAllProfiles()
	end)
end

local SavedData = {}
E:RegisterEvent("PLAYER_LOGIN", function()
	StartProfilePass()
end, SavedData, "modules")

---------------------------------------------------------------------------
-- Backups, checks and restore
--
-- Before an update changes a saved part, a copy of it as it was is kept
-- in the same saved file (an addon cannot write files of its own):
--   EldoUIDB.backups.profiles[name]  one profile: { at, fromSchema,
--                                    toSchema, eldoui, data }
--   EldoUIDB.backups.stores[id]      one saved store (id: its name, or
--                                    "<name>:<character>"): { at, store,
--                                    key, fromVersion, toVersion, eldoui,
--                                    data }
--   EldoUIDB.backups.restored[id]    the part as it was just before the
--                                    player put a backup back
--   EldoUIDB.journalBackups          the journal's own "before update"
--                                    copy (Adventure/Backup.lua)
-- The newest copy per part is kept; a later update of the same part
-- replaces it, a retry of the same update keeps the first one. All copies
-- together stay under E.BACKUP_CAP: past it the oldest go first, except the
-- newest "before update" copy of each journal.
--
-- Every saved store is checked when it is first read (E:MigrateStore):
-- a missing table is made, a number saved as text becomes a number, a list
-- with a gap closes up in its order, and a value of the wrong kind is set
-- aside in the part's own _quarantine table (never deleted), where the
-- Saved data page can put it back. Nothing is reset.
--
-- Restoring (E:RestoreBackup) puts a copy back out of combat, keeps the
-- copy, and holds that part (EldoUIDB.schema.hold) so no update changes it
-- again until the player lets go or a newer EldoUI brings a newer version
-- of it.
---------------------------------------------------------------------------
E.BACKUP_CAP = 4 * 1024 * 1024
E:RegisterStore("backups", { owner = "Core" })

-- The length of a value as the saved file would write it (an estimate).
local function Bytes(value, depth)
	local kind = type(value)
	if kind == "string" then return #value + 4 end
	if kind == "number" then return #tostring(value) + 2 end
	if kind == "boolean" then return 6 end
	depth = depth or 0
	if kind ~= "table" or depth > 40 then return 4 end
	local total = 4
	for key, item in pairs(value) do
		total = total + Bytes(key, depth + 1) + Bytes(item, depth + 1) + 4
	end
	return total
end
E.SavedBytes = function(_, value) return Bytes(value) end

local function Backups()
	if type(EldoUIDB) ~= "table" then return nil end
	local backups = EldoUIDB.backups
	if type(backups) ~= "table" then
		-- Not ours to read: kept inside the new table.
		backups = backups ~= nil and { previous = backups } or {}
		EldoUIDB.backups = backups
	end
	for _, list in ipairs({ "profiles", "stores", "restored" }) do
		if type(backups[list]) ~= "table" then backups[list] = backups[list] ~= nil and { previous = backups[list] } or {} end
	end
	return backups
end

-- Part ids: "profile:<name>" for a profile, "<store>" or "<store>:<key>"
-- for a saved store (the journal of one character: "journal:<character>").
local function UnitId(name, key)
	if key == nil then return tostring(name) end
	return ("%s:%s"):format(tostring(name), tostring(key))
end
E.SavedUnitId = function(_, name, key) return UnitId(name, key) end

local function HoldTable(create)
	local schema = type(EldoUIDB) == "table" and EldoUIDB.schema
	if type(schema) ~= "table" then return nil end
	if type(schema.hold) ~= "table" then
		if not create then return nil end
		schema.hold = {}
	end
	return schema.hold
end

-- Is this part held as the player put it back? version: the number this
-- EldoUI has for it; a hold set by an older EldoUI with a lower number
-- lets go by itself.
function E:IsHeld(id, version)
	local hold = HoldTable()
	local entry = hold and hold[id]
	if not entry then return false end
	local below = type(entry) == "table" and tonumber(entry.below)
	if below and tonumber(version) and tonumber(version) > below then
		hold[id] = nil
		return false
	end
	return true
end

function E:SetHold(id, version)
	local hold = HoldTable(true)
	if not hold then return false end
	hold[id] = { at = Now(), below = tonumber(version) or 0, eldoui = self.version }
	return true
end

function E:ReleaseHold(id)
	local hold = HoldTable()
	if not (hold and hold[id]) then return false end
	hold[id] = nil
	return true
end

function E:HeldParts()
	local list = {}
	for id, entry in pairs(HoldTable() or {}) do
		list[#list + 1] = { id = id, at = type(entry) == "table" and entry.at or nil }
	end
	table.sort(list, function(a, b) return tostring(a.id) < tostring(b.id) end)
	return list
end

-- The journal's newest "before update" copy of each character is the one
-- copy the size cap never lets go.
local function ReservedJournal(list)
	for _, entry in ipairs(type(list) == "table" and list or {}) do
		if type(entry) == "table" and entry.reason == "before update" then return entry end
	end
end
E.ReservedJournalBackup = function(_, list) return ReservedJournal(list) end

-- Keep every backup copy together under E.BACKUP_CAP. Returns how many
-- copies went.
function E:TrimBackups(cap)
	cap = tonumber(cap) or self.BACKUP_CAP
	if type(EldoUIDB) ~= "table" then return 0 end
	local entries, total = {}, 0
	local function Add(holder, key, entry, reserved)
		local size = Bytes(entry)
		total = total + size
		if not reserved then
			entries[#entries + 1] = { holder = holder, key = key, entry = entry, size = size,
				at = type(entry) == "table" and tonumber(entry.at) or 0 }
		end
	end
	local backups = type(EldoUIDB.backups) == "table" and EldoUIDB.backups or {}
	for _, list in ipairs({ "profiles", "stores", "restored" }) do
		if type(backups[list]) == "table" then
			for key, entry in pairs(backups[list]) do Add(backups[list], key, entry) end
		end
	end
	if type(EldoUIDB.journalBackups) == "table" then
		for _, list in pairs(EldoUIDB.journalBackups) do
			if type(list) == "table" then
				local reserved = ReservedJournal(list)
				for _, entry in ipairs(list) do Add(list, nil, entry, entry == reserved) end
			end
		end
	end
	if total <= cap then return 0 end
	table.sort(entries, function(a, b) return a.at < b.at end)
	local removed = 0
	for _, item in ipairs(entries) do
		if total <= cap then break end
		if item.key ~= nil then
			item.holder[item.key] = nil
		else
			for index, entry in ipairs(item.holder) do
				if entry == item.entry then
					table.remove(item.holder, index)
					break
				end
			end
		end
		total = total - item.size
		removed = removed + 1
	end
	schemaRun.trimmed = schemaRun.trimmed + removed
	return removed
end

-- A copy of one part before an update changes it. kind: "profile" or a
-- registered store name (a store may take its own copy: spec.backup).
-- Returns the backup entry, or nil when there was nothing to copy.
function E:BackupUnit(kind, key, unit, from, to)
	local whole
	if kind == "EldoUIDB" then
		if type(key) ~= "nil" then return nil end
		whole = AccountSnapshot(self, unit, true)
		if not whole or E.Secret(from) or E.Secret(to) then return nil end
	end
	if kind == "profile" then
		local supported, version = ProfileData(unit)
		if not CurrentProfile(unit, key, true) or not supported or E.Secret(from) or from ~= version or E.Secret(to)
			or not ProfileData({ profileBaseline = self.PROFILE_BASELINE, schema = to }) or to < version then return nil end
	end
	if type(unit) ~= "table" or next(unit) == nil then return nil end
	local backups = Backups()
	if not backups then return nil end
	from, to = tonumber(from) or 0, tonumber(to) or 0
	local entry
	if kind == "profile" then
		local old = backups.profiles[key]
		-- The same update tried again keeps the copy from before its first try.
		if type(old) == "table" and old.profileBaseline == self.PROFILE_BASELINE and ProfileData(old.data)
			and old.fromSchema == from and old.toSchema == to then return old end
		local data = CopyTable(unit)
		self:CompactProfile(data)
		entry = { at = Now(), fromSchema = from, toSchema = to, eldoui = self.version, data = data,
			profileBaseline = self.PROFILE_BASELINE }
		backups.profiles[key] = entry
	else
		local info = self.stores[kind]
		if not info then return nil end
		if type(info.backup) == "function" then
			local ok, result = pcall(info.backup, unit, key, from, to)
			if not ok then
				geterrorhandler()(("EldoUI backup of %s: %s"):format(UnitId(kind, key), tostring(result)))
				return nil
			end
			entry = result
		else
			local id = UnitId(kind, key)
			local old = backups.stores[id]
			if type(old) == "table" and old.fromVersion == from and old.toVersion == to
				and (not whole or AccountRecord(old, false)) then return old end
			entry = { at = Now(), store = kind, key = key, fromVersion = from, toVersion = to, eldoui = self.version,
				profileBaseline = CurrentAccount(true) and self.PROFILE_BASELINE or nil,
				data = whole or CopyTable(unit), accountSnapshot = whole and 1 or nil,
				previous = whole and old or nil }
			backups.stores[id] = entry
		end
	end
	if entry then
		schemaRun.backups = schemaRun.backups + 1
		self:TrimBackups()
	end
	return entry
end

---------------------------------------------------------------------------
-- Checks (validate and keep)
---------------------------------------------------------------------------
-- Set a value aside in a part's _quarantine: { [path] = { value, at,
-- why } }. A second value for the same path gets "<path> (2)".
local function Quarantine(unit, path, value, why)
	local box = unit._quarantine
	if type(box) ~= "table" then
		box = box ~= nil and { _quarantine = { value = box, at = Now(), why = "Expected a table." } } or {}
		unit._quarantine = box
	end
	path = tostring(path)
	local slot, n = path, 1
	while box[slot] ~= nil do
		n = n + 1
		slot = ("%s (%d)"):format(path, n)
	end
	box[slot] = { value = value, at = Now(), why = why, profileBaseline = CurrentAccount(true) and E.PROFILE_BASELINE or nil }
	return slot
end

local function NewReport(name, key)
	return { name = name, key = key, id = UnitId(name, key), repaired = 0, quarantined = 0, kept = 0 }
end

-- The helpers a store's check gets, bound to one part and its report:
--   C.Table(parent, key, path)            a table at parent[key] (made
--                                         when missing; anything else is
--                                         set aside)
--   C.List(parent, key, path)             the same, and a gap in its
--                                         numbered entries closes up in
--                                         their order
--   C.Number(parent, key, path, default)  a number (text that reads as one
--                                         is converted; anything else is
--                                         set aside and `default` put in)
--   C.Keep(path, value, why)              set a value aside by hand
-- path: where the value sits in the part, for the page ("totals.deaths").
local function Checker(unit, report)
	local C = { unit = unit, report = report }
	function C.Keep(path, value, why)
		report.quarantined = report.quarantined + 1
		return Quarantine(unit, path, value, why or "Not the kind of value expected here.")
	end
	function C.Table(parent, key, path)
		local value = parent[key]
		if type(value) == "table" then return value end
		if value ~= nil then C.Keep(path or key, value, "Expected a table.") end
		value = {}
		parent[key] = value
		return value
	end
	function C.List(parent, key, path)
		local list = C.Table(parent, key, path)
		local order = {}
		for index in pairs(list) do
			if type(index) == "number" and index >= 1 and index % 1 == 0 then order[#order + 1] = index end
		end
		table.sort(order)
		if order[#order] and order[#order] > #order then
			local items = {}
			for position, index in ipairs(order) do items[position] = list[index] end
			for _, index in ipairs(order) do list[index] = nil end
			for position, item in ipairs(items) do list[position] = item end
			report.repaired = report.repaired + 1
		end
		return list
	end
	function C.Number(parent, key, path, default)
		local value = parent[key]
		if type(value) == "number" then return value end
		if value ~= nil then
			local number = type(value) == "string" and tonumber(value)
			if number then
				parent[key] = number
				report.repaired = report.repaired + 1
				return number
			end
			C.Keep(path or key, value, "Expected a number.")
			parent[key] = nil
		end
		if default ~= nil then parent[key] = default end
		return parent[key]
	end
	return C
end
E.SavedDataChecker = function(_, unit, report) return Checker(unit, report or NewReport("check")) end

local function RunCheck(check, unit, report)
	if type(check) ~= "function" then return end
	local ok, err = pcall(check, unit, Checker(unit, report))
	if not ok then
		-- What the check could not look at stays as it is.
		report.kept = report.kept + 1
		geterrorhandler()(("EldoUI saved data check of %s: %s"):format(report.id, tostring(err)))
	end
end

-- Steps of a store: E:RegisterStoreStep(name, version, fn) adds one that
-- brings a part of the store up to `version`; fn(unit, from) changes it
-- in place and follows the rules for update steps above.
function E:RegisterStoreStep(name, version, fn)
	version = tonumber(version)
	local info = self.stores[name]
	if not (info and version and type(fn) == "function") then return nil end
	info.steps = info.steps or {}
	table.insert(info.steps, { version = version, fn = fn })
	table.sort(info.steps, function(a, b) return a.version < b.version end)
	return true
end

-- Bring one part of a registered store up to date and check it: a copy
-- first (when an update will change it), then the steps in order, the new
-- version, the check (spec.validate(unit, C), C as above). Call it the
-- first time a session reads the part. key: the character (or other key)
-- for a store kept per character. A part from a newer EldoUI, or one the
-- player put back, is only checked. Returns the part.
function E:MigrateStore(name, unit, key)
	local info = self.stores[name]
	if type(unit) ~= "table" or not info or info.legacy then return unit end
	local report = NewReport(name, key)
	schemaRun.stores[report.id] = report
	local versionKey = info.versionKey
	local target = tonumber(info.version)
	if versionKey and target then
		local raw = unit[versionKey]
		local from = tonumber(raw) or 0
		if raw ~= nil and type(raw) ~= "number" then
			if tonumber(raw) then
				unit[versionKey] = from
				report.repaired = report.repaired + 1
			else
				report.quarantined = report.quarantined + 1
				Quarantine(unit, versionKey, raw, "Expected a number.")
				unit[versionKey] = nil
			end
		end
		report.from, report.to = from, from
		if from > target then
			report.newer = true
		elseif from < target then
			if self:IsHeld(report.id, target) then
				report.held = true
			else
				self:BackupUnit(name, key, unit, from, target)
				local reached = from
				for _, step in ipairs(info.steps or {}) do
					if step.version > from and step.version <= target then
						local ok, err = pcall(step.fn, unit, from)
						if not ok then
							report.failed = { version = step.version, err = tostring(err), at = Now() }
							geterrorhandler()(("EldoUI saved data update of %s to version %d: %s"):format(report.id, step.version, tostring(err)))
							break
						end
						reached = step.version
					end
				end
				-- Versions without a step of their own pass with the last one.
				if not report.failed then reached = target end
				if reached > from then unit[versionKey] = reached end
				report.to = reached
			end
		end
	end
	RunCheck(info.validate, unit, report)
	return unit
end

-- A fresh table for a part whose saved value is not a table: that value
-- is set aside in the new table, never dropped.
function E:KeepInNewTable(old, path)
	local unit = {}
	if old ~= nil then Quarantine(unit, path or "value", old, "Expected a table.") end
	return unit
end

-- Profiles: a value of the wrong kind where the defaults have a table is
-- set aside (ApplyDefaults would otherwise put the defaults in its place).
local checkedProfiles = setmetatable({}, { __mode = "k" })
local function KeepTables(C, target, defaults, path)
	for key, default in pairs(defaults) do
		if type(default) == "table" then
			local value = target[key]
			if value ~= nil and type(value) ~= "table" then
				C.Keep(path .. tostring(key), value, "Expected a table.")
				target[key] = nil
			elseif type(value) == "table" and default[1] == nil then
				KeepTables(C, value, default, path .. tostring(key) .. ".")
			end
		end
	end
end

local function CheckProfileTables(unit, C)
	for key, default in pairs(E.defaults) do
		local value = unit[key]
		if key ~= "modules" and type(default) == "table" then
			if value ~= nil and type(value) ~= "table" then
				C.Keep(key, value, "Expected a table.")
				unit[key] = nil
			elseif type(value) == "table" then
				KeepTables(C, value, default, key .. ".")
			end
		end
	end
	for _, key in ipairs({ "modules", "movers" }) do
		if unit[key] ~= nil and type(unit[key]) ~= "table" then
			C.Keep(key, unit[key], "Expected a table.")
			unit[key] = nil
		end
	end
	if type(unit.modules) ~= "table" then return end
	for moduleName, module in pairs(E.modules or {}) do
		local settings = unit.modules[moduleName]
		if settings ~= nil and type(settings) ~= "table" then
			C.Keep("modules." .. moduleName, settings, "Expected a table.")
			unit.modules[moduleName] = nil
		elseif type(settings) == "table" and type(module.defaults) == "table" then
			KeepTables(C, settings, module.defaults, "modules." .. moduleName .. ".")
		end
	end
end

function CheckProfile(profile, name)
	if type(profile) ~= "table" or checkedProfiles[profile] then return end
	checkedProfiles[profile] = true
	local report = NewReport("profile", name)
	schemaRun.stores[report.id] = report
	RunCheck(CheckProfileTables, profile, report)
end

-- What the checks of this session found: { [id] = { name, key, from, to,
-- repaired, quarantined, kept, held, newer, failed } }.
function E:SavedDataReport()
	local list = {}
	for id, report in pairs(schemaRun.stores) do list[id] = report end
	return list
end

function SetAsideCount()
	local count = 0
	for _, report in pairs(schemaRun.stores) do count = count + report.quarantined end
	return count
end

function SetAsideText(count)
	return E:Plural(count, "EldoUI set aside %d saved value it could not read. Nothing was deleted: type /eui data to see it.",
		"EldoUI set aside %d saved values it could not read. Nothing was deleted: type /eui data to see them."):format(count)
end

function MovedText(setAside)
	local L = E.L
	if setAside > 0 and schemaRun.backups == 0 then
		return E:Plural(setAside, "Your EldoUI settings were updated for this version. Nothing was removed, and %d saved value EldoUI could not read is set aside. Type /eui data to see it.",
			"Your EldoUI settings were updated for this version. Nothing was removed, and %d saved values EldoUI could not read are set aside. Type /eui data to see them."):format(setAside)
	end
	if setAside > 0 then
		return E:Plural(setAside, "Your EldoUI settings were updated for this version. Nothing was removed: a copy from before the update is kept, and %d saved value EldoUI could not read is set aside. Type /eui data to see them.",
			"Your EldoUI settings were updated for this version. Nothing was removed: a copy from before the update is kept, and %d saved values EldoUI could not read are set aside. Type /eui data to see them."):format(setAside)
	end
	if schemaRun.backups > 0 then
		return L["Your EldoUI settings were updated for this version. Nothing was removed, and a copy from before the update is kept: type /eui data to see it."]
	end
	return L["Your EldoUI settings were updated for this version. Nothing was removed."]
end

---------------------------------------------------------------------------
-- Finding parts, backups and set-aside values (the Saved data page)
---------------------------------------------------------------------------
-- Every saved part that exists now: { id, name, key, unit }. A store kept
-- per character (spec.perKey) lists one part per key; every profile is
-- one part.
function E:SavedUnits()
	local list = {}
	if type(EldoUIDB) ~= "table" then return list end
	for name, info in pairs(self.stores) do
		local root
		if info.savedVariable then root = _G[info.savedVariable] elseif info.root then root = EldoUIDB[info.root] end
		if type(root) == "table" and not info.legacy and name ~= "EldoUIDB" and name ~= "profiles" then
			if info.perKey then
				for key, unit in pairs(root) do
					if type(unit) == "table" then list[#list + 1] = { id = UnitId(name, key), name = name, key = key, unit = unit } end
				end
			else
				list[#list + 1] = { id = UnitId(name), name = name, unit = root }
			end
		end
	end
	if type(EldoUIDB.profiles) == "table" then
		for profileName, profile in pairs(EldoUIDB.profiles) do
			if type(profile) == "table" then
				list[#list + 1] = { id = UnitId("profile", profileName), name = "profile", key = profileName, unit = profile }
			end
		end
	end
	table.sort(list, function(a, b) return a.id < b.id end)
	return list
end

local function FindUnit(id)
	for _, entry in ipairs(E:SavedUnits()) do
		if entry.id == id then return entry end
	end
end

-- Every value set aside: { id (the part), path, value, at, why }.
function E:QuarantinedValues()
	local list = {}
	for _, entry in ipairs(self:SavedUnits()) do
		local box = entry.unit._quarantine
		if type(box) == "table" then
			for path, item in pairs(box) do
				if type(item) == "table" then
					list[#list + 1] = { id = entry.id, path = path, value = item.value, at = item.at, why = item.why }
				end
			end
		end
	end
	table.sort(list, function(a, b)
		if a.id ~= b.id then return a.id < b.id end
		return tostring(a.path) < tostring(b.path)
	end)
	return list
end

local function PathKeysOf(path)
	local keys = {}
	for part in (tostring(path):gsub(" %(%d+%)$", "")):gmatch("[^%.]+") do keys[#keys + 1] = tonumber(part) or part end
	return keys
end

-- Put a set-aside value back where it was. What sits there now (other
-- than an empty table) is set aside in its place, so nothing is lost.
-- Returns true, or false and the reason. Out of combat, as a restore.
function E:PutBack(id, path)
	local L = self.L
	if InCombatLockdown() then return false, L["Backups can be put back out of combat only."] end
	if not CurrentAccount() or E.Secret(id) or type(id) ~= "string" or E.Secret(path) or type(path) ~= "string" then return false end
	local entry = FindUnit(id)
	if not entry or not ProfileTable(entry.unit) then return false end
	local box = rawget(entry.unit, "_quarantine")
	local item = ProfileTable(box) and rawget(box, path)
	if not ProfileTable(item) then return false, L["That value is no longer set aside."] end
	local keys = PathKeysOf(path)
	if #keys == 0 then return false, L["That value is no longer set aside."] end
	local allowed, profileStore = RestoreProfileData(entry.name, entry.key, entry.unit, item)
	if not allowed then return false, L["EldoUI could not load these settings. Check that you are using the latest version of EldoUI."] end
	if entry.name == "profile" then
		if not CurrentProfile(entry.unit, entry.key) or E.Secret(item.value) then return false end
		if keys[1] == "profileBaseline" and item.value ~= self.PROFILE_BASELINE then return false end
		if keys[1] == "schema" then
			local candidate = { profileBaseline = entry.unit.profileBaseline, schema = item.value }
			if #keys ~= 1 or not ProfileData(candidate) then return false end
		end
	elseif profileStore and E.Secret(item.value) then return false end
	local parent = entry.unit
	for index = 1, #keys - 1 do
		local key = keys[index]
		if parent[key] == nil then parent[key] = {} end
		if type(parent[key]) ~= "table" then return false, L["The place this value came from holds something else now. Nothing was changed."] end
		parent = parent[key]
	end
	local last = keys[#keys]
	local current = parent[last]
	box[path] = nil
	if current ~= nil and not (type(current) == "table" and next(current) == nil) then
		Quarantine(entry.unit, path, current, "Set aside when an older value was put back.")
	end
	parent[last] = item.value
	if next(box) == nil then entry.unit._quarantine = nil end
	if profileStore then return self:LoadDatabase() end
	return true
end

-- The backups an update made: { kind, key, id, at, from, to, eldoui }.
-- kind: "profile" or a store name; the journal lists the newest "before
-- update" copy of each character.
function E:BackupList()
	local list = {}
	local db = type(EldoUIDB) == "table" and EldoUIDB or {}
	local backups = type(db.backups) == "table" and db.backups or {}
	for name, entry in pairs(type(backups.profiles) == "table" and backups.profiles or {}) do
		if type(entry) == "table" and type(entry.data) == "table" then
			list[#list + 1] = { kind = "profile", key = name, id = UnitId("profile", name), at = entry.at, from = entry.fromSchema,
				to = entry.toSchema, eldoui = entry.eldoui }
		end
	end
	for id, entry in pairs(type(backups.stores) == "table" and backups.stores or {}) do
		if type(entry) == "table" and type(entry.data) == "table" and entry.store then
			list[#list + 1] = { kind = entry.store, key = entry.key, id = id, at = entry.at, from = entry.fromVersion,
				to = entry.toVersion, eldoui = entry.eldoui }
		end
	end
	for charKey, entries in pairs(type(db.journalBackups) == "table" and db.journalBackups or {}) do
		local entry = ReservedJournal(entries)
		if entry then
			list[#list + 1] = { kind = "journal", key = charKey, id = UnitId("journal", charKey), at = entry.at, eldoui = entry.eldoui }
		end
	end
	table.sort(list, function(a, b)
		if (a.at or 0) ~= (b.at or 0) then return (a.at or 0) > (b.at or 0) end
		return a.id < b.id
	end)
	return list
end

---------------------------------------------------------------------------
-- Restore
---------------------------------------------------------------------------
-- The part as it is now, kept before a backup takes its place.
local function KeepReplaced(id, data)
	local backups = Backups()
	if backups and type(data) == "table" and next(data) ~= nil then
		backups.restored[id] = { at = Now(), eldoui = E.version, data = data,
			profileBaseline = CurrentAccount() and E.PROFILE_BASELINE or nil }
	end
end

do
	local required, transition
	local methods = { "LoadDatabase", "PrepareProfileBaseline", "InitializeDatabase", "SetProfile", "InvalidateDatabase",
		"CopyProfileTable", "CompactProfile", "ModuleEnabledValue" }
	local function Same(a, b)
		return not E.Secret(a) and not E.Secret(b) and a == b
	end
	local function MethodsCurrent()
		if not required or type(getmetatable(E)) ~= "nil" then return false end
		for _, name in ipairs(methods) do if not Same(rawget(E, name), required[name]) then return false end end
		return true
	end
	InitializeAccountOwner = function()
		required = {}
		for _, name in ipairs(methods) do required[name] = rawget(E, name) end
	end
	local function Supported(root)
		if not ProfileTable(root) or not Same(rawget(root, "profileBaseline"), E.PROFILE_BASELINE) then return false end
		local schema, profiles, keys, private = rawget(root, "schema"), rawget(root, "profiles"), rawget(root, "profileKeys"), rawget(root, "private")
		if not ProfileTable(schema) or not ProfileTable(profiles) or not ProfileTable(keys) or not ProfileTable(private) or not next(profiles) then return false end
		local version = rawget(schema, "version")
		if E.Secret(version) or type(version) ~= "number" or version < 0 or version > E.SCHEMA_VERSION or version % 1 ~= 0 then return false end
		for name, profile in pairs(profiles) do
			if E.Secret(name) or type(name) ~= "string" or name == "" or not ProfileData(profile) then return false end
		end
		local function Reference(name, nonempty)
			if E.Secret(name) or type(name) ~= "string" then return false end
			if name == "" then return not nonempty end
			return ProfileData(rawget(profiles, name))
		end
		for character, name in pairs(keys) do
			if E.Secret(character) or type(character) ~= "string" or not Reference(name, true) then return false end
		end
		for character, namespaces in pairs(private) do
			if E.Secret(character) or type(character) ~= "string" or not ProfileTable(namespaces) then return false end
			local state = rawget(namespaces, "profiles")
			if type(state) ~= "nil" then
				if not ProfileTable(state) then return false end
				local flag, values = rawget(state, "moduleStatesPerCharacter"), rawget(state, "moduleStates")
				if E.Secret(flag) or (type(flag) ~= "nil" and type(flag) ~= "boolean") then return false end
				if type(values) ~= "nil" then
					if not ProfileTable(values) then return false end
					for name, on in pairs(values) do
						if E.Secret(name) or type(name) ~= "string" or E.Secret(on) or type(on) ~= "boolean" then return false end
					end
				end
			end
		end
		for _, field in ipairs({ "classProfiles", "profileRules", "importedLayouts", "setupHistory", "installed", "installerRun", "installerBackup", "installerLogin" }) do
			local value = rawget(root, field)
			if type(value) ~= "nil" and not ProfileTable(value) then return false end
		end
		for _, name in pairs(rawget(root, "classProfiles") or {}) do if not Reference(name) then return false end end
		for _, rule in pairs(rawget(root, "profileRules") or {}) do
			if not ProfileTable(rule) then return false end
			local enabled = rawget(rule, "enabled")
			if E.Secret(enabled) or (type(enabled) ~= "nil" and type(enabled) ~= "boolean") then return false end
			for _, field in ipairs({ "spec", "content" }) do
				local refs = rawget(rule, field)
				if type(refs) ~= "nil" then
					if not ProfileTable(refs) then return false end
					for _, name in pairs(refs) do if not Reference(name) then return false end end
				end
			end
		end
		return true
	end
	local function Graph(root, live)
		local remaining, stack = E.BACKUP_CAP, {}
		if E.Secret(remaining) or type(remaining) ~= "number" or remaining <= 0 or remaining >= math.huge then return false end
		local active, activeName = E.db, E.profileName
		local function Visit(value, depth, scope, moduleName)
			if E.Secret(value) or depth > 40 then return false end
			local kind = type(value)
			remaining = remaining - (kind == "string" and #value + 4 or 16)
			if remaining < 0 then return false end
			if kind == "number" then return value == value and value > -math.huge and value < math.huge end
			if kind == "string" or kind == "boolean" then return true end
			if kind ~= "table" or stack[value] then return false end
			if type(getmetatable(value)) ~= "nil" then
				if not live or scope ~= "settings" or not ProfileTable(E.modules) then return false end
				local module = rawget(E.modules, moduleName)
				if E.Secret(module) or type(module) ~= "table" or not Same(rawget(module, "db"), value) then return false end
				local enabled = E:ModuleEnabledValue(module)
				if E.Secret(enabled) or type(enabled) ~= "boolean" then return false end
			end
			stack[value] = true
			for key, item in next, value do
				if E.Secret(key) or (type(key) ~= "string" and type(key) ~= "number" and type(key) ~= "boolean") or not Visit(key, depth + 1) then return false end
				local child
				if scope == "root" and key == "profiles" then child = "profiles"
				elseif scope == "profiles" and Same(key, activeName) and Same(item, active) then child = "active"
				elseif scope == "active" and key == "modules" then child = "modules"
				elseif scope == "modules" and type(key) == "string" then child = "settings" end
				if not Visit(item, depth + 1, child, child == "settings" and key or nil) then return false end
			end
			stack[value] = nil
			return true
		end
		return Visit(root, 0, "root")
	end
	AccountRecord = function(record, undo)
		if not ProfileTable(record) or not Same(rawget(record, "accountSnapshot"), 1)
			or not Same(rawget(record, "profileBaseline"), E.PROFILE_BASELINE) then return false end
		local at, held = rawget(record, "at"), rawget(record, "held")
		if E.Secret(at) or type(at) ~= "number" or at < 0 or at >= math.huge or at % 1 ~= 0
			or E.Secret(held) or (type(held) ~= "nil" and type(held) ~= "boolean") then return false end
		if not undo and (not Same(rawget(record, "store"), "EldoUIDB") or type(rawget(record, "key")) ~= "nil") then return false end
		local data = rawget(record, "data")
		if not Supported(data) then return false end
		local backups = rawget(data, "backups")
		if not ProfileTable(backups) then return false end
		for _, bucket in ipairs({ "profiles", "stores", "restored" }) do
			local values = rawget(backups, bucket)
			if not ProfileTable(values) then return false end
			if bucket ~= "profiles" and type(rawget(values, "EldoUIDB")) ~= "nil" then return false end
		end
		return Graph(record, false)
	end
	local function Shallow(value)
		local copy = {}
		for key, item in next, value do copy[key] = item end
		return copy
	end
	AccountSnapshot = function(self, root, live)
		if not MethodsCurrent() or not Supported(root) then return nil end
		if live and (not CurrentProfile(self.db, self.profileName) or not Same(rawget(_G, "EldoUIDB"), root)) then return nil end
		local view = Shallow(root)
		local saved = rawget(root, "backups")
		if type(saved) ~= "nil" and not ProfileTable(saved) then return nil end
		view.backups = saved and Shallow(saved) or {}
		for _, bucket in ipairs({ "profiles", "stores", "restored" }) do
			local values = saved and rawget(saved, bucket)
			if type(values) ~= "nil" and not ProfileTable(values) then return nil end
			view.backups[bucket] = values and Shallow(values) or {}
			if bucket ~= "profiles" then
				local old = rawget(view.backups[bucket], "EldoUIDB")
				if type(old) ~= "nil" and (not ProfileTable(old) or not Graph(old, false)) then return nil end
				view.backups[bucket].EldoUIDB = nil
			end
		end
		if not Graph(view, live) then return nil end
		local copy = CopyTable(view)
		if live then
			for name in pairs(root.profiles) do
				local profile = self:CopyProfileTable(name)
				if not profile then return nil end
				self:CompactProfile(profile)
				copy.profiles[name] = profile
			end
			if not CurrentProfile(self.db, self.profileName) or not Same(rawget(_G, "EldoUIDB"), root) then return nil end
		end
		if not MethodsCurrent() or not Supported(copy) or not Graph(copy, false) then return nil end
		return copy
	end
	local function Invalidate(lease)
		InvalidateProfileAdmission()
		lease.invalidate(E)
	end
	AccountRecovery = function(root, complete)
		if not transition or transition.state ~= "blocked" then return true end
		if not MethodsCurrent() or (not Same(root, transition.previousRoot) and not Same(root, transition.candidate)) then return false end
		if complete then transition = nil end
		return true
	end
	local function AccountFits(root, source, previous)
		local total = (source and Bytes(source) or 0) + Bytes(previous)
		for _, bucket in ipairs({ "profiles", "stores", "restored" }) do
			for key, entry in pairs(root.backups[bucket]) do
				if bucket == "profiles" or key ~= "EldoUIDB" then total = total + Bytes(entry) end
			end
		end
		if type(root.journalBackups) == "table" then
			for _, list in pairs(root.journalBackups) do
				if type(list) == "table" then for _, entry in ipairs(list) do total = total + Bytes(entry) end end
			end
		end
		return total <= E.BACKUP_CAP
	end
	RestoreAccount = function(self, undo)
		if transition or not MethodsCurrent() or not CurrentProfile(self.db, self.profileName) then return false end
		local held, setHold, releaseHold, trim = rawget(self, "IsHeld"), rawget(self, "SetHold"), rawget(self, "ReleaseHold"), rawget(self, "TrimBackups")
		local function Callable(fn) return not E.Secret(fn) and type(fn) == "function" end
		if not Callable(held) or not Callable(setHold) or not Callable(releaseHold) or not Callable(trim) then return false end
		local function FunctionsCurrent()
			return MethodsCurrent() and Same(rawget(self, "IsHeld"), held) and Same(rawget(self, "SetHold"), setHold)
				and Same(rawget(self, "ReleaseHold"), releaseHold) and Same(rawget(self, "TrimBackups"), trim)
		end
		local root = rawget(_G, "EldoUIDB")
		local profile, name, character, private = self.db, self.profileName, self.charKey, self.private
		local function CurrentSource()
			return FunctionsCurrent() and Same(rawget(_G, "EldoUIDB"), root)
				and Same(self.db, profile) and Same(self.profileName, name) and Same(self.charKey, character)
				and Same(self.private, private) and CurrentProfile(profile, name)
		end
		local archives = rawget(root, "backups")
		local bucket = undo and "restored" or "stores"
		local values = ProfileTable(archives) and rawget(archives, bucket)
		local record = ProfileTable(values) and rawget(values, "EldoUIDB")
		if not AccountRecord(record, undo) then return false end
		local stores = rawget(archives, "stores")
		if not ProfileTable(stores) then return false end
		local source = rawget(stores, "EldoUIDB")
		local lease = { previousRoot = root, state = "staging", invalidate = required.InvalidateDatabase }
		transition = lease
		local ok, result = pcall(function()
			lease.source = rawget(record, "data")
			lease.record = CopyTable(record)
			local function SourceCurrent()
				return ProfileTable(root) and Same(rawget(root, "backups"), archives) and ProfileTable(archives)
					and Same(rawget(archives, bucket), values) and ProfileTable(values)
					and Same(rawget(values, "EldoUIDB"), record) and Same(rawget(record, "data"), lease.source)
					and AccountRecord(record, undo) and DeepEqual(record, lease.record)
			end
			lease.candidate = AccountSnapshot(self, rawget(lease.record, "data"), false)
			lease.previous = AccountSnapshot(self, root, true)
			if not lease.candidate or not lease.previous or not CurrentSource() or not SourceCurrent() then return false end
			if type(source) ~= "nil" and not Graph(source, false) then return false end
			local sourceCopy = source and CopyTable(source)
			local function ArchiveCurrent()
				return SourceCurrent() and Same(rawget(archives, "stores"), stores) and Same(rawget(stores, "EldoUIDB"), source)
					and (type(source) == "nil" or (Graph(source, false) and DeepEqual(source, sourceCopy)))
			end
			local wasHeld = held(self, "EldoUIDB")
			if E.Secret(wasHeld) or type(wasHeld) ~= "boolean" or not CurrentSource() or not ArchiveCurrent() then return false end
			local at = Now()
			if E.Secret(at) or type(at) ~= "number" or at < 0 or at >= math.huge or at % 1 ~= 0
				or not CurrentSource() or not ArchiveCurrent() then return false end
			local previous = { at = at, eldoui = self.version, data = lease.previous,
				profileBaseline = self.PROFILE_BASELINE, accountSnapshot = 1, held = wasHeld or nil }
			if not AccountFits(lease.candidate, source, previous) then lease.capacity = true; return false end
			if not CurrentSource() or not ArchiveCurrent() then return false end
			local backups = rawget(lease.candidate, "backups")
			local profiles, destination, restored = rawget(backups, "profiles"), rawget(backups, "stores"), rawget(backups, "restored")
			local function DestinationCurrent()
				return ProfileTable(backups) and Same(rawget(lease.candidate, "backups"), backups)
					and ProfileTable(profiles) and Same(rawget(backups, "profiles"), profiles)
					and ProfileTable(destination) and Same(rawget(backups, "stores"), destination)
					and ProfileTable(restored) and Same(rawget(backups, "restored"), restored)
			end
			Invalidate(lease)
			lease.state = "loading"
			rawset(_G, "EldoUIDB", lease.candidate)
			if not required.LoadDatabase(self) or not FunctionsCurrent() or not Same(rawget(_G, "EldoUIDB"), lease.candidate)
				or not CurrentProfile(self.db, self.profileName) or not ArchiveCurrent() or not DestinationCurrent() then return false end
			if not Graph(lease.candidate, true) then return false end
			if not AccountFits(lease.candidate, source, previous) then lease.capacity = true; return false end
			local active, activeName, activeCharacter, activePrivate = self.db, self.profileName, self.charKey, self.private
			local function InstalledCurrent()
				return FunctionsCurrent() and Same(rawget(_G, "EldoUIDB"), lease.candidate) and CurrentProfile(active, activeName)
					and Same(self.db, active) and Same(self.profileName, activeName) and Same(self.charKey, activeCharacter)
					and Same(self.private, activePrivate) and ArchiveCurrent() and DestinationCurrent()
			end
			-- Keep the selected source archive; neither data snapshot nests
			-- these two transaction records within itself.
			destination.EldoUIDB, restored.EldoUIDB = source, previous
			if undo then
				if record.held then setHold(self, "EldoUIDB", self.SCHEMA_VERSION) else releaseHold(self, "EldoUIDB") end
			else setHold(self, "EldoUIDB", self.SCHEMA_VERSION) end
			if not InstalledCurrent() or not Same(rawget(destination, "EldoUIDB"), source)
				or not Same(rawget(restored, "EldoUIDB"), previous) then return false end
			trim(self)
			return InstalledCurrent() and Same(rawget(destination, "EldoUIDB"), source) and Same(rawget(restored, "EldoUIDB"), previous)
		end)
		if ok and result then transition = nil; return true end
		if lease.state == "staging" and Same(rawget(_G, "EldoUIDB"), root) and MethodsCurrent() and CurrentProfile(self.db, self.profileName) then
			transition = nil
		else
			Invalidate(lease)
			if Same(rawget(_G, "EldoUIDB"), lease.candidate) then
				rawset(_G, "EldoUIDB", root)
				if FunctionsCurrent() then
					lease.state = "rollback"
					local restored, ready = pcall(required.LoadDatabase, self)
					if restored and ready and MethodsCurrent() and Same(rawget(_G, "EldoUIDB"), root) and CurrentProfile(self.db, self.profileName) then
						transition = nil
					elseif ok and not restored then ok, result = false, ready end
				end
			end
			if transition then lease.state = "blocked"; Invalidate(lease) end
		end
		if not ok then error(result, 0) end
		if lease.capacity then return false, E.L["The copies needed for this restore exceed the backup size limit. Nothing changed."] end
		return false
	end
end

-- Undo a restore: the copy kept in backups.restored[id] (what a restore
-- replaced) goes back, what is there now takes its place, and the part
-- gets the hold it had. Returns true, or false and the reason.
function E:UndoRestore(id)
	if not CurrentAccount() or E.Secret(id) or type(id) ~= "string" then return false end
	local ownerRoot, ownerProfiles, ownerActive, ownerName = EldoUIDB, EldoUIDB.profiles, self.db, self.profileName
	if id == nil then return false end
	local L = self.L
	if InCombatLockdown() then return false, L["Backups can be put back out of combat only."] end
	if id == "EldoUIDB" then return RestoreAccount(self, true) end
	local backups = type(EldoUIDB) == "table" and EldoUIDB.backups
	local kept = ProfileTable(backups) and ProfileTable(rawget(backups, "restored")) and rawget(backups.restored, id)
	if not ProfileTable(kept) or not ProfileTable(rawget(kept, "data")) then return false, L["there is no copy of that any more."] end
	id = tostring(id)
	local name, key = id:match("^([^:]+):(.+)$")
	name = name or id
	local allowed, profileStore = RestoreProfileData(name, key, kept.data, kept)
	if not allowed then return false, L["EldoUI could not load these settings. Check that you are using the latest version of EldoUI."] end
	local wasHeld = E:IsHeld(id)
	local current, version, replacedProfile
	if name == "profile" then
		if E.RestoreProfileModuleStates then E.RestoreProfileModuleStates() end
		if EldoUIDB.profiles[key] then
			current = E:CopyProfileTable(key)
			E:CompactProfile(current)
		end
		replacedProfile = CopyTable(kept.data)
		EldoUIDB.profiles[key] = replacedProfile
		version = E.PROFILE_SCHEMA
	else
		local info = E.stores[name]
		if not info then return false, L["there is no copy of that any more."] end
		local data = CopyTable(kept.data)
		if info.savedVariable then
			current = _G[info.savedVariable]
			_G[info.savedVariable] = data
		elseif info.perKey and key then
			if type(EldoUIDB[info.root]) ~= "table" then EldoUIDB[info.root] = {} end
			current = EldoUIDB[info.root][key]
			EldoUIDB[info.root][key] = data
		else
			current = EldoUIDB[info.root]
			EldoUIDB[info.root] = data
		end
		version = info.version
	end
	-- What it held a moment ago takes the copy's place, with the hold it had.
	if type(current) == "table" and next(current) ~= nil then
		backups.restored[id] = { at = Now(), eldoui = E.version, data = current, held = wasHeld or nil,
			profileBaseline = self.PROFILE_BASELINE }
	else
		backups.restored[id] = nil
	end
	if kept.held then E:SetHold(id, version) else E:ReleaseHold(id) end
	if name == "profile" and key == ownerName then return RebindProfileWrite(self, ownerRoot, ownerProfiles, ownerActive, ownerName, replacedProfile) end
	if profileStore then
		if not ProfileTable(EldoUIDB) or EldoUIDB ~= ownerRoot then return false end
		return self:LoadDatabase()
	end
	return true
end

-- Put a backup back: kind "profile" (key: the profile name), "journal"
-- (key: the character) or a store name (key: the character for a store
-- kept per character). Out of combat only. The backup stays. Returns true,
-- or false and the reason.
function E:RestoreBackup(kind, key)
	local L = self.L
	if InCombatLockdown() then return false, L["Backups can be put back out of combat only."] end
	if not CurrentAccount() or E.Secret(kind) or type(kind) ~= "string" or E.Secret(key) then return false end
	if kind == "EldoUIDB" then
		if type(key) ~= "nil" then return false end
		return RestoreAccount(self, false)
	end
	local ownerRoot, ownerProfiles, ownerActive, ownerName = EldoUIDB, EldoUIDB.profiles, self.db, self.profileName
	local saved = EldoUIDB.backups
	local collection = ProfileTable(saved) and rawget(saved, kind == "profile" and "profiles" or "stores")
	local proposed = ProfileTable(collection) and rawget(collection, kind == "profile" and key or UnitId(kind, key))
	local allowed, profileStore = RestoreProfileData(kind, key, ProfileTable(proposed) and rawget(proposed, "data"), proposed)
	if kind ~= "journal" and not allowed then
		return false, L["EldoUI could not load these settings. Check that you are using the latest version of EldoUI."]
	end
	if kind == "profile" and not ProfileData({ profileBaseline = self.PROFILE_BASELINE, schema = rawget(proposed, "fromSchema") }) then return false end
	local backups = Backups()
	if not backups then return false, L["there is no copy of that any more."] end
	if kind == "profile" then
		local entry = backups.profiles[key]
		if type(entry) ~= "table" or type(entry.data) ~= "table" then return false, L["there is no copy of that any more."] end
		RestoreAll()
		if EldoUIDB.profiles[key] then
			local current = self:CopyProfileTable(key)
			self:CompactProfile(current)
			KeepReplaced(UnitId("profile", key), current)
		end
		local data = CopyTable(entry.data)
		data.schema = (tonumber(entry.fromSchema) or 0) > 0 and entry.fromSchema or nil
		EldoUIDB.profiles[key] = data
		self:SetHold(UnitId("profile", key), self.PROFILE_SCHEMA)
		if key == ownerName then return RebindProfileWrite(self, ownerRoot, ownerProfiles, ownerActive, ownerName, data) end
		return true
	end
	local info = self.stores[kind]
	if not info then return false, L["there is no copy of that any more."] end
	local id = UnitId(kind, key)
	if kind == "journal" then
		local B = self.Adventure and self.Adventure.Backup
		local list = type(EldoUIDB.journalBackups) == "table" and EldoUIDB.journalBackups[key]
		local reserved = ReservedJournal(list)
		if not (B and reserved) then return false, L["there is no copy of that any more."] end
		local index
		for position, entry in ipairs(list) do
			if entry == reserved then index = position end
		end
		local schema = rawget(ownerRoot, "schema")
		if not ProfileTable(schema) then return false end
		local previousTable = rawget(schema, "hold")
		if E.Secret(previousTable) or (type(previousTable) == "table" and not ProfileTable(previousTable)) then return false end
		local previous
		if type(previousTable) == "table" then previous = rawget(previousTable, id) end
		if E.Secret(previous) then return false end
		local secret = E.Secret
		local function SameValue(value, expected)
			return not secret(value) and not secret(expected) and rawequal(value, expected)
		end
		if not self:SetHold(id, info.version) then return false end
		local installedRoot = EldoUIDB
		local installedSchema = ProfileTable(installedRoot) and rawget(installedRoot, "schema")
		local installedTable = ProfileTable(installedSchema) and rawget(installedSchema, "hold")
		local installed = ProfileTable(installedTable) and rawget(installedTable, id)
		if not SameValue(installedRoot, ownerRoot) or not SameValue(installedSchema, schema)
			or not ProfileTable(installed) or not CurrentAccount() then return false end
		local at, below, version = rawget(installed, "at"), rawget(installed, "below"), rawget(installed, "eldoui")
		local ok, err = B:Restore(index, "replace", key)
		if not ok then
			-- Undo only this attempt's hold. A later owner can replace either
			-- the account, its hold table, this entry, or the entry's fields.
			local unchanged = ProfileTable(installed) and SameValue(rawget(installed, "at"), at)
				and SameValue(rawget(installed, "below"), below) and SameValue(rawget(installed, "eldoui"), version)
			if unchanged then
				for field in next, installed do
					if E.Secret(field) or (field ~= "at" and field ~= "below" and field ~= "eldoui") then unchanged = false; break end
				end
			end
			local currentRoot = EldoUIDB
			local currentSchema = ProfileTable(currentRoot) and rawget(currentRoot, "schema")
			local currentTable = ProfileTable(currentSchema) and rawget(currentSchema, "hold")
			local current = ProfileTable(currentTable) and rawget(currentTable, id)
			if unchanged and SameValue(currentRoot, ownerRoot) and SameValue(currentSchema, schema)
				and SameValue(currentTable, installedTable) and SameValue(current, installed) then
				rawset(installedTable, id, previous)
				if installedTable ~= previousTable and next(installedTable) == nil then rawset(schema, "hold", previousTable) end
			end
			return false, err
		end
		return true
	end
	local entry = backups.stores[id]
	if type(entry) ~= "table" or type(entry.data) ~= "table" then return false, L["there is no copy of that any more."] end
	local data = CopyTable(entry.data)
	if info.savedVariable then
		KeepReplaced(id, type(_G[info.savedVariable]) == "table" and CopyTable(_G[info.savedVariable]) or nil)
		_G[info.savedVariable] = data
	elseif info.perKey then
		if type(EldoUIDB[info.root]) ~= "table" then EldoUIDB[info.root] = {} end
		KeepReplaced(id, type(EldoUIDB[info.root][key]) == "table" and CopyTable(EldoUIDB[info.root][key]) or nil)
		EldoUIDB[info.root][key] = data
	else
		KeepReplaced(id, type(EldoUIDB[info.root]) == "table" and CopyTable(EldoUIDB[info.root]) or nil)
		EldoUIDB[info.root] = data
	end
	self:SetHold(id, info.version)
	if profileStore then
		if not ProfileTable(EldoUIDB) or EldoUIDB ~= ownerRoot then return false end
		return self:LoadDatabase()
	end
	return true
end

---------------------------------------------------------------------------
-- Legacy tables: kept as they are; only the player removes one.
---------------------------------------------------------------------------
-- Legacy saved tables that hold data: { name, bytes, removable }.
function E:LegacyStores()
	local list = {}
	for name, info in pairs(self.stores) do
		if info.legacy then
			local value
			if info.savedVariable then value = _G[info.savedVariable]
			elseif info.root and type(EldoUIDB) == "table" then value = EldoUIDB[info.root] end
			if type(value) == "table" and next(value) ~= nil then
				list[#list + 1] = { name = name, bytes = Bytes(value), removable = info.savedVariable ~= nil }
			end
		end
	end
	table.sort(list, function(a, b) return a.name < b.name end)
	return list
end

-- Remove a legacy saved table the player chose to remove.
function E:RemoveLegacyStore(name)
	local info = self.stores[name]
	if not (info and info.legacy and info.savedVariable) then return false end
	_G[info.savedVariable] = nil
	return true
end

-- The player's own name without the Forever surname. UnitName can
-- include the surname on some builds, which would split one character
-- into two keys; UnitNameUnmodified gives the base name.
function E:PlayerName()
	local name = UnitNameUnmodified and UnitNameUnmodified("player")
	if type(name) ~= "string" or (issecretvalue and issecretvalue(name)) or name == "" then
		name = UnitName("player")
	end
	return name
end

-- The active talent group (dual talents: 1 or 2). Forever has one spec
-- per class and two talent groups; GetActiveTalentGroup does not exist.
function E:TalentGroup()
	local fn = C_SpecializationInfo and C_SpecializationInfo.GetActiveSpecGroup
	if type(fn) ~= "function" then fn = _G.GetActiveSpecGroup end
	if type(fn) == "function" then
		local ok, group = pcall(fn)
		if ok and type(group) == "number" and not (issecretvalue and issecretvalue(group)) and group >= 1 then
			return group
		end
	end
	return 1
end

-- Forever groups its realms by ruleset: characters, auction houses and
-- the hourly instance cap are shared per ruleset. The ruleset's short
-- name: "PvE", "PvP", "RP", "RP-PvP" or "HC". Which client this is comes from the
-- one shared check, E:IsForeverClient (Core/Media.lua).

-- A saved-data scope requires the complete set of readable flags.
function E:KnownRulesetName()
	local active, rules = C_GameRules and C_GameRules.IsGameRuleActive, Enum and Enum.GameRule
	if type(active) ~= "function" or not rules then return nil end
	local pvpRule, rpRule, hardcoreRule = rules.PvPRuleset, rules.RPRuleset, rules.HardcoreRuleset
	if type(pvpRule) ~= "number" or type(rpRule) ~= "number" or type(hardcoreRule) ~= "number" then return nil end
	local pvp = E.PlainCall(active, pvpRule)
	local rp = E.PlainCall(active, rpRule)
	local hardcore = E.PlainCall(active, hardcoreRule)
	if type(pvp) ~= "boolean" or type(rp) ~= "boolean" or type(hardcore) ~= "boolean" then return nil end
	if hardcore then return not pvp and not rp and "HC" or nil end
	if pvp and rp then return "RP-PvP" end
	if pvp then return "PvP" end
	if rp then return "RP" end
	return "PvE"
end

function E:RulesetName()
	return self:KnownRulesetName() or "PvE"
end

function E:ReadableRealmName()
	local realm = E.PlainCall(GetRealmName)
	return type(realm) == "string" and realm ~= "" and realm or nil
end

-- The "realm" new per-character data is keyed by (with E:PlayerName():
-- "<name> - <realm key>"): the ruleset on Forever, the realm elsewhere.
-- Existing saved data keeps its old keys.
function E:RealmKey()
	if self:IsForeverClient() then return self:RulesetName() end
	return GetRealmName()
end

function E:KnownRealmKey()
	if self.IsForeverClient and self:IsForeverClient() then return self:KnownRulesetName() end
	return self:ReadableRealmName()
end

-- The character's name as its saved data knows it. On Forever a first
-- name is unique only together with the surname ("First Surname", unique
-- per region), so two characters of one account can share a first name;
-- the full name keeps their data apart. Without a readable surname (other
-- clients, or a name the game keeps secret) the first name, as before.
-- The surname is read as the game stores it, not as it is shown: the
-- game's option to show only your first name changes no key.
function E:CharacterName()
	local function Plain(value)
		return type(value) == "string" and not (issecretvalue and issecretvalue(value)) and value ~= "" and value or nil
	end
	local first, last = Plain(self:PlayerName()), nil
	if type(UnitNameUnmodified) == "function" then last = Plain(select(2, UnitNameUnmodified("player"))) end
	if not last and self.NameParts then last = Plain(select(2, self:NameParts("player"))) end
	if first and last then return first .. " " .. last end
	return self:PlayerName()
end

local function ReadableText(value)
	value = E.Plain(value)
	return type(value) == "string" and value ~= "" and value or nil
end

local function SavedTable(root, key)
	if E.Secret(root) or type(root) ~= "table" or getmetatable(root) ~= nil then return nil end
	local value = rawget(root, key)
	if not E.Secret(value) and type(value) == "table" and getmetatable(value) == nil then return value end
end

-- Saved variables may be absent until this character's first load.
local function SavedCharacterStore(store)
	return SavedTable(rawget(_G, "EldoUIDB"), store)
end

local function MyGuid()
	return ReadableText(E.PlainCall(UnitGUID, "player"))
end

local function RecordGuid(store, key)
	local record = SavedTable(SavedCharacterStore(store), key)
	local guid = record and rawget(record, "guid")
	return ReadableText(guid), E.Secret(guid)
end

-- The character data and journal both track the owner of a saved key.
local function RecordOwner(key)
	local inventory, inventoryHidden = RecordGuid("inventory", key)
	local journal, journalHidden = RecordGuid("journal", key)
	local conflict = inventoryHidden or journalHidden or (inventory and journal and inventory ~= journal)
	return inventory or journal, conflict
end

local function RecordScope(record)
	return record and ReadableText(rawget(record, "realmKey"))
end

local RULESET_NAMES = { PvE = true, PvP = true, RP = true, ["RP-PvP"] = true, HC = true }

local function ScopeCompatible(record, scope)
	local saved = record and rawget(record, "realmKey")
	return not E.Secret(saved) and (type(saved) == "nil" or (scope and ReadableText(saved) == scope))
end

-- Older named-realm records may predate realmKey entirely. When the
-- physical realm is unavailable, the GUID can still identify their key.
local function LegacyPhysicalKey(realm, record, journal)
	return realm and not RULESET_NAMES[realm] and ScopeCompatible(record, nil) and ScopeCompatible(journal, nil)
end

local function KnownScopeCharacterKey(scope, guid, realm, includeLegacy)
	if not scope or not guid then return nil end
	local inventory = SavedCharacterStore("inventory")
	local journal = SavedCharacterStore("journal")
	local stores = { inventory or {} }
	if includeLegacy then stores[2] = journal end
	local found, scopeSuffix = nil, " - " .. scope
	for _, store in ipairs(stores) do
		for key in pairs(store) do
			local savedKey = ReadableText(key)
			if savedKey and savedKey ~= found and SavedTable(store, savedKey)
				and (not realm or savedKey:sub(-3) == " - " or savedKey:sub(-#scopeSuffix) == scopeSuffix) then
				local record, note = SavedTable(inventory, savedKey), SavedTable(journal, savedKey)
				local savedRealm = includeLegacy and savedKey:match("^.+ %- (.+)$")
				local confirmed = RecordScope(record) == scope and ScopeCompatible(note, scope)
					and (not RULESET_NAMES[savedRealm] or savedRealm == scope)
				if confirmed or LegacyPhysicalKey(savedRealm, record, note) then
					local owner, conflict = RecordOwner(savedKey)
					if owner == guid and not conflict then
						if found then return nil end
						found = savedKey
					end
				end
			end
		end
	end
	return found
end

-- The older keys this character's data could sit under: the first-name
-- key ("First - Realm", 0.7.1001 and earlier) and the key built from
-- UnitName.
local function OldCharacterKeys(newKey, realm, first, unitName)
	if not newKey or not realm then return {} end
	local olds, seen = {}, { [newKey] = true }
	local function Candidate(name)
		if type(name) ~= "string" or (issecretvalue and issecretvalue(name)) or name == "" then return end
		local key = ("%s - %s"):format(name, realm)
		if not seen[key] then seen[key] = true olds[#olds + 1] = key end
	end
	Candidate(first)
	Candidate(unitName)
	return olds
end

local function HasCharacterRecord(key)
	for _, store in ipairs({ "inventory", "journal", "profileKeys", "private" }) do
		local list = SavedCharacterStore(store)
		if list and type(rawget(list, key)) ~= "nil" then return true end
	end
	return false
end

-- Preserve a verified existing key when the game withholds the realm.
-- Fresh keys with no physical realm need the full name, GUID, and scope.
local function ResolveCharacterKey(identity)
	local realm, name, first = identity.realm, identity.name, identity.first
	local guid, scope = identity.guid, identity.scope
	local full = name and first and name ~= first
	local owned = KnownScopeCharacterKey(scope, guid, realm, not realm)
	if owned then return owned end

	if not realm then
		if not full or not scope or not guid then return nil end
		local key = ("%s - %s"):format(name, scope)
		local owner, conflict = RecordOwner(key)
		local record = SavedTable(SavedCharacterStore("inventory"), key)
		local journal = SavedTable(SavedCharacterStore("journal"), key)
		if conflict or (owner and owner ~= guid) or not ScopeCompatible(record, scope)
			or not ScopeCompatible(journal, scope) then return nil end
		return key
	end
	if not name then return nil end
	local key = ("%s - %s"):format(name, realm)
	local inventory = SavedCharacterStore("inventory")
	if not full and first and guid and inventory then
		local suffix, prefix = " - " .. realm, first .. " "
		local fullKey
		for saved in pairs(inventory) do
			local savedKey = ReadableText(saved)
			if savedKey and savedKey ~= key and savedKey:sub(-#suffix) == suffix
				and savedKey:sub(1, #prefix) == prefix then
				local owner, conflict = RecordOwner(savedKey)
				if owner == guid and not conflict then
					if fullKey then return nil end
					fullKey = savedKey
				end
			end
		end
		if fullKey then return fullKey, OldCharacterKeys(fullKey, realm, first, identity.unitName) end
	end

	local owner, conflict = RecordOwner(key)
	local aliases = OldCharacterKeys(key, realm, first, identity.unitName)
	local vacant = not HasCharacterRecord(key)
	local admit = not conflict and (not owner or owner == guid)
	for _, alias in ipairs(aliases) do
		if not guid and vacant and HasCharacterRecord(alias) then return nil end
		local oldOwner, oldConflict = RecordOwner(alias)
		if guid and oldOwner == guid and not oldConflict then
			if admit then return key, aliases end
			-- Keep the verified older key when the destination belongs
			-- to someone else.
			return alias
		end
	end
	if admit and not vacant then return key, aliases end
	-- A physical realm name can change while identity and scope stay
	-- the same. Keep its unique old key when no exact key is bound.
	local verified = KnownScopeCharacterKey(scope, guid)
	if verified then return verified end
	if admit then return key, aliases end
end

CharacterIdentity = function()
	local identity = {
		realm = E:ReadableRealmName(),
		name = ReadableText(E:CharacterName()),
		first = ReadableText(E:PlayerName()),
		unitName = ReadableText(E.PlainCall(UnitName, "player")),
		guid = MyGuid(),
		scope = E.IsForeverClient and E:IsForeverClient() and E:KnownRulesetName(),
	}
	local key, aliases = ResolveCharacterKey(identity)
	if key then
		identity.key, identity.aliases = key, aliases or {}
		return identity
	end
end

-- Read before the database loads (E.charKey is set only then).
function E:CurrentCharacterKey()
	local identity = CharacterIdentity()
	return identity and identity.key
end

-- Per-character settings: the profile choice and the character's own
-- options. They come along only for the character whose GUID owns the old
-- key's records. A new character that only shares the first name starts
-- fresh, and so does a character that was forgotten after it moved.
local SHARED_SETTINGS = { profileKeys = true, private = true, profileRules = true, keybindBackup = true,
	installed = true, installerRun = true, installerLogin = true }

-- The older keys of this character's name (other than its own key).
function E:OlderCharacterKeys()
	local identity = CharacterIdentity()
	return identity and identity.aliases or {}
end

-- True when the current character owns an older key under a readable realm.
function E:OwnsOlderCharacterKey()
	local identity = CharacterIdentity()
	if not identity or not identity.guid then return false end
	for _, oldKey in ipairs(identity.aliases) do
		local owner, conflict = RecordOwner(oldKey)
		if owner == identity.guid and not conflict then return true end
	end
	return false
end

-- Per-character entries the move below cannot reach: tables deeper in
-- the account-wide data or in the profiles, and rows that hold the key as
-- a value. Each module names its own with E:RegisterCharacterKeyMove(fn);
-- fn(db, oldKey, newKey) runs once, with the raw saved data, when this
-- character's records move from oldKey.
local keyMoves = {}

function E:RegisterCharacterKeyMove(fn)
	if type(fn) == "function" then keyMoves[#keyMoves + 1] = fn end
end

-- Moves t[oldKey] to t[newKey]. An entry already under newKey is never
-- replaced. True when something moved.
function E.MoveCharacterEntry(t, oldKey, newKey)
	if type(t) ~= "table" or oldKey == newKey or t[oldKey] == nil or t[newKey] ~= nil then return false end
	t[newKey], t[oldKey] = t[oldKey], nil
	return true
end

-- Every saved profile's settings of one module (profile.modules.<name>).
function E.EachProfileModule(db, name)
	local list = {}
	local profiles = type(db) == "table" and db.profiles
	if type(profiles) ~= "table" then return list end
	for _, profile in pairs(profiles) do
		local modules = type(profile) == "table" and profile.modules
		local settings = type(modules) == "table" and modules[name]
		if type(settings) == "table" then list[#list + 1] = settings end
	end
	return list
end

-- The same for Forget: fn(db, key) runs when a character is forgotten and
-- removes what the module keeps for it beyond the tables Forget clears.
local forgets = {}

function E:RegisterCharacterForget(fn)
	if type(fn) == "function" then forgets[#forgets + 1] = fn end
end

function E:RunCharacterForgets(key)
	for _, fn in ipairs(forgets) do
		local ok, err = pcall(fn, EldoUIDB, key)
		if not ok then geterrorhandler()(("EldoUI forgetting a character: %s"):format(tostring(err))) end
	end
end

local function RunKeyMoves(oldKey, newKey)
	for _, fn in ipairs(keyMoves) do
		local ok, err = pcall(fn, EldoUIDB, oldKey, newKey)
		if not ok then geterrorhandler()(("EldoUI moving saved data to the character's new key: %s"):format(tostring(err))) end
	end
end

-- Data saved under an older key of this character moves to its key once.
-- Records and settings move only to the character the old records' GUID
-- names: records move, settings are copied and then leave the old key
-- once nothing there names another owner. A record that already exists
-- under the new key is never replaced. Looks two levels into EldoUIDB,
-- where per-character tables live (profileKeys, private, inventory,
-- auction.chars and so on); the modules move what lies deeper.
-- Returns the old key whose records moved here, or nil.
local function MigrateCharacterKey(identity)
	local newKey, myGuid = identity.key, identity.guid
	if not myGuid or #identity.aliases == 0 then return nil end
	local destinationOwner, destinationConflict = RecordOwner(newKey)
	if destinationConflict or (destinationOwner and destinationOwner ~= myGuid) then return nil end
	local claimed
	for _, oldKey in ipairs(identity.aliases) do
		local owner, conflict = RecordOwner(oldKey)
		if owner == myGuid and not conflict then
			local copied = {}
			local function Carry(t, settings)
				if t[oldKey] == nil then return end
				if settings then
					if t[newKey] == nil then t[newKey] = type(t[oldKey]) == "table" and CopyTable(t[oldKey]) or t[oldKey] end
					copied[#copied + 1] = t
				elseif t[newKey] == nil then
					t[newKey], t[oldKey] = t[oldKey], nil
				end
			end
			for key, value in pairs(EldoUIDB) do
				if type(value) == "table" and key ~= "profiles" and key ~= "global" then
					local settings = SHARED_SETTINGS[key] or false
					Carry(value, settings)
					for _, inner in pairs(value) do
						if type(inner) == "table" then Carry(inner, settings) end
					end
				end
			end
			RunKeyMoves(oldKey, newKey)
			-- The old key's settings go once no record there names an owner,
			-- so no later character with this first name finds them.
			if RecordOwner(oldKey) == nil then
				for _, t in ipairs(copied) do t[oldKey] = nil end
			end
			claimed = claimed or oldKey
		end
	end
	return claimed
end

---------------------------------------------------------------------------
-- A character that moved to another ruleset. On WoW: Forever a character
-- can change ruleset (the paid transfer's destination ruleset, or a fallen
-- Hardcore character's move), and its key ("<name> - <realm>") changes
-- with the realm. Its old records are found by its GUID or, as a full
-- name is unique per region across every ruleset, by its full name. The
-- player is asked once, at login: Bring over moves every per-character
-- entry from the old key to this one, Start fresh leaves the old record
-- alone and never asks again for that pair, Later asks at the next login.
-- Nothing moves without the click. Ruleset data (auction prices, the
-- instance limit) is keyed by ruleset, not by character, and stays.
---------------------------------------------------------------------------
local RULESET_STORES = { "inventory", "journal" }

local function MoveAnswers()
	if type(EldoUIDB) ~= "table" then return {} end
	if type(EldoUIDB.rulesetMoves) ~= "table" then EldoUIDB.rulesetMoves = {} end
	return EldoUIDB.rulesetMoves
end

local function PairKey(oldKey, newKey) return oldKey .. "\n" .. newKey end

-- The old key of this character under another realm, and that realm, or
-- nil. Only on WoW: Forever, and a name match needs the full name.
function E:RulesetMoveCandidate(newKey)
	if type(EldoUIDB) ~= "table" or not (self.IsForeverClient and self:IsForeverClient()) then return nil end
	newKey = newKey or self.charKey or self:CurrentCharacterKey()
	if not newKey then return nil end
	local guid, full, first = MyGuid(), ReadableText(self:CharacterName()), ReadableText(self:PlayerName())
	local byName = full and first and full ~= first
	local realm, scope = self:ReadableRealmName(), self:KnownRulesetName()
	local answers = SavedTable(EldoUIDB, "rulesetMoves") or {}
	local inventory = SavedTable(EldoUIDB, "inventory")
	local found, from
	for _, store in ipairs(RULESET_STORES) do
		local list = SavedTable(EldoUIDB, store)
		for key in pairs(list or {}) do
			local savedKey = ReadableText(key)
			local cut = savedKey and savedKey:find(" - ", 1, true)
			if cut and savedKey ~= newKey and SavedTable(list, savedKey) and answers[PairKey(savedKey, newKey)] == nil then
				local name, oldRealm = savedKey:sub(1, cut - 1), savedKey:sub(cut + 3)
				local owner, conflict = RecordOwner(savedKey)
				local record = SavedTable(inventory, savedKey)
				local oldScope = RecordScope(record)
				local mine = not conflict and ((guid and owner == guid) or (byName and name == full))
				local different
				if scope and oldScope then
					different = scope ~= oldScope
				else
					different = realm and oldRealm ~= "" and realm ~= oldRealm
				end
				if mine and different and (not found or savedKey < found) then
					found, from = savedKey, oldRealm ~= "" and oldRealm or oldScope
				end
			end
		end
	end
	return found, from
end

-- Bring over: every per-character entry two levels into EldoUIDB moves
-- from oldKey to newKey and replaces what this character saved since the
-- move; the modules move what lies deeper. Takes effect after a reload.
-- A move to another realm can give the character a new GUID; its moved
-- records then still name the old one. The character data and journal
-- records take the new GUID here, and a module that keeps more records by
-- GUID re-stamps them in its own handler: fn(db, oldKey, newKey, oldGuid,
-- newGuid), called before the key moves run.
local rulesetGuidMoves = {}
function E:RegisterRulesetGuidMove(fn)
	if type(fn) == "function" then rulesetGuidMoves[#rulesetGuidMoves + 1] = fn end
end

function E:BringOverCharacter(oldKey, newKey)
	newKey = newKey or self.charKey
	if type(EldoUIDB) ~= "table" or type(oldKey) ~= "string" or type(newKey) ~= "string" or oldKey == newKey then
		return false
	end
	local realm, scope
	if newKey == self.charKey then
		realm, scope = self:ReadableRealmName(), self:KnownRealmKey()
		if not realm and not scope then return false end
	end
	local oldGuid, sourceConflict = RecordOwner(oldKey)
	local destinationOwner, destinationConflict = RecordOwner(newKey)
	local newGuid = MyGuid()
	if not newGuid or sourceConflict or destinationConflict or (destinationOwner and destinationOwner ~= newGuid) then
		return false
	end
	local function Take(t)
		if t[oldKey] ~= nil then t[newKey], t[oldKey] = t[oldKey], nil end
	end
	for key, value in pairs(EldoUIDB) do
		if type(value) == "table" and key ~= "profiles" and key ~= "global" and key ~= "rulesetMoves" then
			Take(value)
			for _, inner in pairs(value) do
				if type(inner) == "table" then Take(inner) end
			end
		end
	end
	if oldGuid and oldGuid ~= newGuid then
		for _, store in ipairs(RULESET_STORES) do
			local list = EldoUIDB[store]
			local record = type(list) == "table" and list[newKey]
			if type(record) == "table" and record.guid == oldGuid then record.guid = newGuid end
		end
		for _, fn in ipairs(rulesetGuidMoves) do
			local ok, err = pcall(fn, EldoUIDB, oldKey, newKey, oldGuid, newGuid)
			if not ok then geterrorhandler()(("EldoUI bringing over a moved character: %s"):format(tostring(err))) end
		end
	end
	local record = SavedTable(SavedTable(EldoUIDB, "inventory"), newKey)
	if record then
		-- The next login needs the confirmed destination scope before it
		-- can open the transferred profile and refresh the character record.
		if realm then record.realm = realm end
		if scope then record.realmKey = scope end
	end
	RunKeyMoves(oldKey, newKey)
	MoveAnswers()[PairKey(oldKey, newKey)] = "moved"
	return true
end

function E:StartFreshCharacter(oldKey, newKey)
	if type(oldKey) ~= "string" then return end
	MoveAnswers()[PairKey(oldKey, newKey or self.charKey)] = "fresh"
end

-- The question, once per login.
function E:OfferRulesetMove()
	local oldKey, oldRealm = self:RulesetMoveCandidate()
	if not oldKey or not self.ShowConfirm then return nil end
	local L, newKey = self.L, self.charKey
	return self:ShowConfirm({
		title = L["Bring over your EldoUI data?"],
		text = L["This character's EldoUI data is saved under %s. Bring over its settings, profile, Journal, bags and history from there? What EldoUI saved here since the move is replaced. The change shows after a reload."]
			:format(oldRealm),
		accept = L["Bring over"],
		extra = { L["Start fresh"], function() E:StartFreshCharacter(oldKey, newKey) end },
		cancel = L["Later"],
		key = "rulesetMove",
		onAccept = function()
			if E:BringOverCharacter(oldKey, newKey) and E.ShowReloadPrompt then
				E:ShowReloadPrompt(L["Your EldoUI data from %s is here after a reload."]:format(oldRealm))
			end
		end,
	})
end

local RulesetMove = {}
E:RegisterEvent("PLAYER_LOGIN", function()
	if C_Timer and C_Timer.After then
		C_Timer.After(4, function() E:OfferRulesetMove() end)
	else
		E:OfferRulesetMove()
	end
end, RulesetMove)

function E:InitializeDatabase()
	-- Use the identity chosen before profile preparation made any writes.
	local allowed, fresh, identity = TakeProfilePreparation()
	if not allowed then return false end
	EldoUIDB = type(EldoUIDB) == "table" and EldoUIDB or {}
	-- A profile list of the wrong kind is set aside in the file's own
	-- _quarantine, never read or dropped.
	for _, key in ipairs({ "profileKeys", "profiles" }) do
		local value = EldoUIDB[key]
		if value ~= nil and type(value) ~= "table" then
			Quarantine(EldoUIDB, key, value, "Expected a table.")
			EldoUIDB[key] = nil
		end
	end
	EldoUIDB.profileKeys = EldoUIDB.profileKeys or {}
	EldoUIDB.profiles = EldoUIDB.profiles or {}
	EldoUIDB.global = type(EldoUIDB.global) == "table" and EldoUIDB.global or {}
	EldoUIDB.private = type(EldoUIDB.private) == "table" and EldoUIDB.private or {}

	-- The account file's version first, before anything reads it.
	schemaRun.state, schemaRun.notices, schemaRun.failedRoots = nil, {}, {}
	schemaRun.stores, schemaRun.backups, schemaRun.trimmed, schemaRun.shown, schemaRun.movedNotice = {}, 0, 0, nil, nil
	RunRootChain(EldoUIDB, fresh)

	self.charKey = identity.key
	-- The older key whose records became this character's (modules that
	-- keep their own per-character keys move theirs with it).
	self.charKeyMovedFrom = MigrateCharacterKey(identity)

	self.global = EldoUIDB.global
	EldoUIDB.private[self.charKey] = type(EldoUIDB.private[self.charKey]) == "table" and EldoUIDB.private[self.charKey] or {}
	self.private = EldoUIDB.private[self.charKey]
	for namespace in pairs(globalSpecs) do FillGlobal(namespace) end
	for namespace in pairs(privateSpecs) do FillPrivate(namespace) end
	if self.SetLanguage then self:SetLanguage(self.global.locale.language) end
	HookModuleDB()

	local profileName = ReadableText(EldoUIDB.profileKeys[self.charKey])
	local hadProfile = profileName ~= nil
	profileName = profileName or "Default"
	InitialProfileSelection(profileName, true)
	if self:SetProfile(profileName, true) == false or not FinishProfilePreparation() then return false end

	-- Loaded again after login (a new set of saved tables): the chat lines
	-- and the other profiles follow as after PLAYER_LOGIN.
	profileLoadBlocked = false
	if IsLoggedIn and IsLoggedIn() then
		StartProfilePass()
	end
	return true, hadProfile
end

---------------------------------------------------------------------------
-- Profiles
---------------------------------------------------------------------------
local MAX_NAME = 48

-- A usable profile name from player input, or nil and the reason.
function E:CheckProfileName(name)
	name = strtrim(tostring(name or ""))
	if name == "" then return nil, self.L["Type a name first."] end
	if #name > MAX_NAME then return nil, self.L["That name is too long."] end
	if name:find("[|\n]") then return nil, self.L["Names can't contain | or line breaks."] end
	return name
end

---------------------------------------------------------------------------
-- Profile migrations: settings that moved (a module merged into another,
-- a renamed key). Each function gets a profile table and changes it in
-- place. They run on a profile when it is used (login, switch, copy,
-- reset) and on a profile table before parts of it are copied in.
--
--   E:RegisterProfileMigration(fn)               runs every time, so it must
--                                                do nothing once the old data
--                                                is gone
--   E:RegisterProfileMigration(fn, key, version) runs once per profile: the
--                                                profile keeps the version it
--                                                reached in profile.migrations
--                                                [key], and the function runs
--                                                again only for a higher one
---------------------------------------------------------------------------
E.profileMigrations = {}

function E:RegisterProfileMigration(fn, key, version)
	if type(fn) ~= "function" then return end
	if key ~= nil then
		table.insert(self.profileMigrations, { fn = fn, key = tostring(key), version = tonumber(version) or 1 })
	else
		table.insert(self.profileMigrations, { fn = fn })
	end
end

-- The version a profile reached for a keyed migration (0 before the first run).
function E:ProfileMigrationVersion(profile, key)
	local stamps = type(profile) == "table" and profile.migrations
	return type(stamps) == "table" and tonumber(stamps[key]) or 0
end

-- only: run just the migration with this key. unkeyedOnly: skip the
-- stamped ones (a profile put back from a backup). Returns true when every
-- keyed migration that ran passed.
function E:RunProfileMigrations(profile, only, unkeyedOnly)
	if type(profile) ~= "table" then return false end
	local passed = true
	for _, migration in ipairs(self.profileMigrations) do
		local key = migration.key
		if (only == nil or key == only) and not (unkeyedOnly and key ~= nil) then
			if key == nil then
				local ok, err = pcall(migration.fn, profile)
				if not ok then geterrorhandler()(err) end
			elseif self:ProfileMigrationVersion(profile, key) < migration.version then
				local ok, err = pcall(migration.fn, profile)
				if ok then
					if type(profile.migrations) ~= "table" then profile.migrations = {} end
					profile.migrations[key] = migration.version
				else
					-- Not stamped: it runs again the next time the profile is used.
					passed = false
					geterrorhandler()(err)
				end
			end
		end
	end
	return passed
end

---------------------------------------------------------------------------
-- Modules re-read their settings: OnProfileChanged once per module, each in
-- its own pcall, so one module that errors never stops the others (the
-- error goes to the error log). Used by the profile switch, the parts copy,
-- the theme refresh, the style presets and the options window.
--   filter(module)  optional; only modules it returns true for
--   queued          true: through E:RunOutOfCombat with one queued call per
--                   module, so a burst in combat refreshes each module once
---------------------------------------------------------------------------
function E:RefreshModule(module, queued)
	if not (module and module.active and module.OnProfileChanged) then return end
	local function call()
		local ok, err = pcall(module.OnProfileChanged, module)
		if not ok then geterrorhandler()(err) end
	end
	if queued then
		self:RunOutOfCombat(call, "Refresh:" .. tostring(module.name))
	else
		call()
	end
end

function E:RefreshModules(filter, queued)
	if not self.modules then return end
	for _, module in self:IterateModules() do
		if module.active and module.OnProfileChanged and (not filter or filter(module)) then
			self:RefreshModule(module, queued)
		end
	end
end

-- Switch the current character to a profile, creating it if needed.
function E:SetProfile(name, silent)
	if not CurrentAccount(true) or E.Secret(name) or type(name) ~= "string" or name == "" then return false end
	if not CurrentAccount() and not InitialProfileSelection(name, false) then return false end
	local saved = rawget(EldoUIDB.profiles, name)
	if type(saved) ~= "nil" and not ProfileData(saved) then return false end
	if CurrentAccount() and not CurrentProfile(self.db, self.profileName) then return false end
	-- Every module re-applies on a switch, and modules move, show and hide
	-- secure frames: in combat the switch waits for the end of the fight
	-- (the first load of the settings at login always runs).
	if self.db and InCombatLockdown() then
		if not CurrentAccount() then return false end
		QueueProfileWork(self, function() self:SetProfile(name, silent) end, name)
		return false
	end
	-- The profile we leave gets its own on/off values back.
	RestoreAll()
	-- A profile made here starts empty: the installer opens on it (design
	-- decision: the setup always runs on a fresh profile). Finish or
	-- "Skip the setup" clears the mark (Core/Installer.lua).
	-- A saved profile that is not a table is set aside and the name starts
	-- over as a new profile.
	local fresh = EldoUIDB.profiles[name] == nil
	if fresh then EldoUIDB.profiles[name] = { needsSetup = true, schema = self.PROFILE_SCHEMA, profileBaseline = self.PROFILE_BASELINE } end
	local profile, root = EldoUIDB.profiles[name], EldoUIDB
	local generation = self:NewApplyGeneration("profile")
	local function Current()
		return self:IsApplyGenerationCurrent(generation, "profile") and CurrentAccount(true)
			and EldoUIDB == root and rawget(root.profiles, name) == profile and ProfileData(profile)
	end
	if not Current() then return false end
	local profileFrom = ProfileSchema(EldoUIDB.profiles[name])
	-- A profile restored from a backup keeps its version and migrations.
	-- Only its historical missing layout default is retained before filling defaults.
	local held = not fresh and self:IsHeld("profile:" .. tostring(name), self.PROFILE_SCHEMA)
	local moving = not fresh and not held and profileFrom < self.PROFILE_SCHEMA
	-- A copy of the profile as it was, before anything below changes it.
	if moving then self:BackupUnit("profile", name, EldoUIDB.profiles[name], profileFrom, self.PROFILE_SCHEMA) end
	if not Current() then return false end
	-- A value of the wrong kind where a table belongs is set aside, never
	-- replaced by the defaults.
	if not fresh then CheckProfile(EldoUIDB.profiles[name], name) end
	if not Current() then return false end
	-- A profile saved before keeps its look when the client's default look differs (Core/Media.lua).
	if self.PinClientLook then self:PinClientLook(EldoUIDB.profiles[name], fresh) end
	if not Current() then return false end
	-- Profiles from before skins keep their skin and Blizzard windows (Core/Skins.lua).
	if self.PinSkinLook then self:PinSkinLook(EldoUIDB.profiles[name], fresh) end
	if not Current() then return false end
	-- Default changes this profile missed, before the defaults fill it.
	if moving or held then self:ApplyDefaultChanges(EldoUIDB.profiles[name], profileFrom, held and "general.layout" or nil) end
	if not Current() then return false end
	EldoUIDB.profiles[name] = ApplyDefaults(EldoUIDB.profiles[name], self.defaults)
	EldoUIDB.profileKeys[self.charKey] = name
	self.db = EldoUIDB.profiles[name]
	self.profileName = name
	-- Window places the old per-module movers saved move to the window mover.
	if self.MigrateWindowPositions then self:MigrateWindowPositions(self.db) end
	if held then
		self:RunProfileMigrations(self.db, nil, true)
	elseif self:RunProfileMigrations(self.db) and profileFrom < self.PROFILE_SCHEMA then
		if not Current() then return false end
		self.db.schema = self.PROFILE_SCHEMA
	end
	if not Current() then return false end

	-- Modules re-read their settings from the new profile. A module whose
	-- on/off switch differs in the new profile is switched on or off;
	-- only the ones that stay on re-apply their settings.
	if self.modules then
		for _, module in self:IterateModules() do
			module.db = self:GetModuleDB(module)
			if not Current() then return false end
		end
		local switchedOff, justEnabled = {}, {}
		if self.SyncModuleStates then switchedOff, justEnabled = self:SyncModuleStates() end
		if not Current() then return false end
		-- One module that errors must not stop the others or the movers.
		self:RefreshModules(function(module)
			return module.initialized and module.db.enabled and not justEnabled[module]
		end)
		if not Current() then return false end
		-- Only the modules whose Blizzard frames need a reload are named.
		local reloadTitles = {}
		for _, module in ipairs(switchedOff) do
			if not self.ModuleNeedsReload or self:ModuleNeedsReload(module) then reloadTitles[#reloadTitles + 1] = self.L[module.title] end
		end
		if #reloadTitles > 0 and self.ShowReloadPrompt then
			self:ShowReloadPrompt(self.L["Profile %s switched off: %s. Blizzard's own versions come fully back after a reload."]
				:format(name, table.concat(reloadTitles, ", ")))
		end
	end
	if self.RefreshMovers and self.movers and next(self.movers) then
		self:RefreshMovers()
	end
	if not Current() then return false end
	if self.windowMoverReady then self:WindowMoverProfileChanged() end
	if not Current() then return false end
	-- The new profile's art style and accent: palette, fonts and repaint.
	-- Modules without their own repaint were re-applied above already.
	if self.RefreshTheme then self:RefreshTheme(true) end
	if not Current() then return false end
	if not silent then
		self:Print(self.L["Using profile %s."]:format(E:Highlight(name)))
	end
	return Current()
end

-- In combat a copy or a reset waits, like a switch: both rewrite the
-- profile and then switch to it again.
function E:CopyProfile(from)
	if not CurrentProfile(self.db, self.profileName) or E.Secret(from) or type(from) ~= "string" then return false end
	local source = EldoUIDB.profiles[from]
	if not CurrentProfile(source, from) or from == self.profileName then return false end
	if QueueProfileWork(self, function() self:CopyProfile(from) end, self.profileName, { profile = source, name = from }) then return false end
	local root, profiles, active, name = EldoUIDB, EldoUIDB.profiles, self.db, self.profileName
	local data = self:CopyProfileTable(from)
	EldoUIDB.profiles[name] = data
	-- The setup changes of the profile copied into no longer apply.
	if self.DropSetupHistory then self:DropSetupHistory(self.profileName) end
	return RebindProfileWrite(self, root, profiles, active, name, data)
end

function E:ResetProfile()
	if not CurrentProfile(self.db, self.profileName) then return false end
	if QueueProfileWork(self, function() self:ResetProfile() end, self.profileName) then return false end
	local root, profiles, active, name = EldoUIDB, EldoUIDB.profiles, self.db, self.profileName
	RestoreAll()
	EldoUIDB.profiles[self.profileName] = nil
	if self.DropSetupHistory then self:DropSetupHistory(self.profileName) end
	return RebindProfileWrite(self, root, profiles, active, name, nil)
end

-- Profile names other EldoUI data points at (rules, class defaults).
local function ForEachProfileReference(fn)
	for _, rules in pairs(EldoUIDB.profileRules or {}) do
		if type(rules) == "table" then
			for _, list in ipairs({ rules.spec, rules.content }) do
				if type(list) == "table" then
					for key, value in pairs(list) do fn(list, key, value) end
				end
			end
			-- "Otherwise use" and the profile picked by hand.
			for _, key in ipairs({ "otherwise", "home" }) do
				if type(rules[key]) == "string" then fn(rules, key, rules[key]) end
			end
		end
	end
	if type(EldoUIDB.classProfiles) == "table" then
		for key, value in pairs(EldoUIDB.classProfiles) do fn(EldoUIDB.classProfiles, key, value) end
	end
	-- Each character's setup backup: the profile the setup wrote and the
	-- one the character used before, so Undo setup follows a rename.
	local backups = rawget(EldoUIDB, "installerBackup")
	if not E.Secret(backups) and type(backups) == "table" then
		for _, backup in pairs(backups) do
			if not E.Secret(backup) and type(backup) == "table" then
				for _, field in ipairs({ "profile", "previous" }) do
					local value = rawget(backup, field)
					if type(value) == "string" then fn(backup, field, value) end
				end
			end
		end
	end
end

function E:DeleteProfile(name)
	if not CurrentAccount() or E.Secret(name) or type(name) ~= "string"
		or not CurrentProfile(rawget(EldoUIDB.profiles, name), name) then return false end
	if name == self.profileName or not EldoUIDB.profiles[name] then return false end
	EldoUIDB.profiles[name] = nil
	for char, profile in pairs(EldoUIDB.profileKeys) do
		if profile == name then EldoUIDB.profileKeys[char] = nil end
	end
	ForEachProfileReference(function(list, key, value)
		if value == name then list[key] = nil end
	end)
	-- A setup backup of the deleted profile has nothing left to undo.
	local backups = rawget(EldoUIDB, "installerBackup")
	if not E.Secret(backups) and type(backups) == "table" then
		for char, backup in pairs(backups) do
			if not E.Secret(backup) and type(backup) == "table" and rawget(backup, "profile") == nil then backups[char] = nil end
		end
	end
	if self.DropSetupHistory then self:DropSetupHistory(name) end
	return true
end

---------------------------------------------------------------------------
-- A copy before a reset, a copy over, a delete or an import: the
-- profile as it was, kept beside what a restore replaced
-- (backups.restored["profile:<name>"], one per profile), so the alert can
-- undo it now and the Saved data page can put it back later. `why` names
-- the change: "reset", "copy", "parts", "import" or "delete". The
-- characters, profile rules and class defaults that pointed at it are kept
-- with it, for a deleted profile.
---------------------------------------------------------------------------
E.PROFILE_CHANGES = { reset = true, copy = true, parts = true, import = true, delete = true }

function E:SnapshotBeforeChange(name, why)
	if not CurrentAccount() or E.Secret(name) or type(name) ~= "string" or not E.PROFILE_CHANGES[why] then return nil end
	if not CurrentProfile(rawget(EldoUIDB.profiles, name), name) or type(EldoUIDB.profiles[name]) ~= "table" then return nil end
	local backups = Backups()
	if not backups then return nil end
	local ok, data = pcall(self.CopyProfileTable, self, name)
	if not ok or type(data) ~= "table" then return nil end
	self:CompactProfile(data)
	local refs = { users = {}, classes = {}, rules = {} }
	for char, profile in pairs(EldoUIDB.profileKeys or {}) do
		if profile == name then refs.users[#refs.users + 1] = char end
	end
	if type(EldoUIDB.classProfiles) == "table" then
		for key, value in pairs(EldoUIDB.classProfiles) do
			if value == name then refs.classes[#refs.classes + 1] = key end
		end
	end
	for char, rules in pairs(EldoUIDB.profileRules or {}) do
		if type(rules) == "table" then
			for _, field in ipairs({ "spec", "content" }) do
				if type(rules[field]) == "table" then
					for key, value in pairs(rules[field]) do
						if value == name then refs.rules[#refs.rules + 1] = { char, field, key } end
					end
				end
			end
			for _, field in ipairs({ "otherwise", "home" }) do
				if rules[field] == name then refs.rules[#refs.rules + 1] = { char, field } end
			end
		end
	end
	local id = UnitId("profile", name)
	backups.restored[id] = { at = Now(), eldoui = self.version, data = data, why = why, refs = refs,
		profileBaseline = self.PROFILE_BASELINE }
	return id
end

-- The copy SnapshotBeforeChange kept for this profile, or nil.
function E:ProfileChangeCopy(name)
	local backups = type(EldoUIDB) == "table" and EldoUIDB.backups
	local kept = type(name) == "string" and type(backups) == "table" and type(backups.restored) == "table"
		and backups.restored[UnitId("profile", name)]
	if type(kept) == "table" and kept.why and type(kept.data) == "table" then return kept end
end

-- Puts the profile back as the copy has it. A deleted profile comes back
-- with the characters, rules and class defaults that used it, where
-- nothing else took their place. Returns true, or false and the reason.
function E:UndoProfileChange(name)
	local kept = self:ProfileChangeCopy(name)
	if not kept then return false, self.L["there is no copy of that any more."] end
	local refs = type(kept.refs) == "table" and kept.refs or {}
	local ok, err = self:UndoRestore(UnitId("profile", name))
	if not ok then return false, err end
	if kept.why == "delete" and EldoUIDB.profiles[name] then
		for _, char in ipairs(refs.users or {}) do
			if EldoUIDB.profileKeys[char] == nil then EldoUIDB.profileKeys[char] = name end
		end
		if #(refs.classes or {}) > 0 and type(EldoUIDB.classProfiles) ~= "table" then EldoUIDB.classProfiles = {} end
		for _, key in ipairs(refs.classes or {}) do
			if EldoUIDB.classProfiles[key] == nil then EldoUIDB.classProfiles[key] = name end
		end
		for _, rule in ipairs(refs.rules or {}) do
			local char, field, key = rule[1], rule[2], rule[3]
			local rules = type(EldoUIDB.profileRules) == "table" and EldoUIDB.profileRules[char]
			if type(rules) == "table" then
				if key == nil then
					if (field == "otherwise" or field == "home") and rules[field] == nil then rules[field] = name end
				else
					if type(rules[field]) ~= "table" then rules[field] = {} end
					if rules[field][key] == nil then rules[field][key] = name end
				end
			end
		end
	end
	return true
end

-- Runs fn (a reset, copy, delete or import of the profile `name`) with a
-- copy kept first, then offers Undo / Keep in an alert. fn returns true
-- when it changed the profile.
local PROFILE_CHANGE_TEXT = {
	reset = E.Key("Your profile %s was reset to its defaults."),
	copy = E.Key("Your profile %s now holds a copy of another profile."),
	parts = E.Key("Parts of another profile were copied into your profile %s."),
	import = E.Key("Settings from a string were imported into your profile %s."),
	delete = E.Key("The profile %s was deleted."),
}
function E:ChangeProfileWithUndo(name, why, fn)
	local id = self:SnapshotBeforeChange(name, why)
	local changed = fn()
	if changed ~= true then
		-- Nothing changed: the copy is not offered.
		local backups = id and EldoUIDB.backups
		if backups and backups.restored[id] and backups.restored[id].why == why then backups.restored[id] = nil end
		return changed
	end
	if id and self.PushAlert then
		local L = self.L
		self:PushAlert({ key = "profile-undo", title = L["Profiles"], options = { page = "profiles" },
			text = L[PROFILE_CHANGE_TEXT[why]]:format(self:Highlight(name)) .. " " .. L["A copy from before is on the Saved data page."],
			actions = {
				{ label = L["Undo"], tip = L["Put the profile %s back the way it was."]:format(name),
					func = function()
						self:RunOutOfCombat(function()
							local ok, err = self:UndoProfileChange(name)
							if ok then
								self:Print(L["Profile %s is back the way it was."]:format(name))
								if self.RefreshConfig then self:RefreshConfig() end
							elseif err then
								self:Print(err)
							end
						end, "Profiles:undo")
					end },
				{ label = L["Keep"] },
			} })
	end
	return changed
end

-- Rename a profile everywhere: characters using it, profile rules and
-- class defaults follow. Returns true, or false and the reason.
function E:RenameProfile(old, new)
	if not CurrentAccount() or E.Secret(old) or type(old) ~= "string"
		or not CurrentProfile(rawget(EldoUIDB.profiles, old), old) then return false end
	local name, err = self:CheckProfileName(new)
	if not name then return false, err end
	if not EldoUIDB.profiles[old] then return false, self.L["There is no profile with that name."] end
	if name == old then return true end
	if EldoUIDB.profiles[name] then return false, self.L["A profile with that name already exists."] end
	EldoUIDB.profiles[name] = EldoUIDB.profiles[old]
	EldoUIDB.profiles[old] = nil
	for char, profile in pairs(EldoUIDB.profileKeys) do
		if profile == old then EldoUIDB.profileKeys[char] = name end
	end
	ForEachProfileReference(function(list, key, value)
		if value == old then list[key] = name end
	end)
	if self.RenameSetupHistory then self:RenameSetupHistory(old, name) end
	if self.profileName == old then self.profileName = name end
	return true
end

-- Frame positions that belong to a module (movers it created).
function E:ModuleMoverNames(moduleName)
	local list = {}
	for name, mover in pairs(self.movers or {}) do
		local owner = mover.module or (name:find(moduleName, 1, true) and moduleName)
		if owner == moduleName then list[#list + 1] = name end
	end
	return list
end

-- Copy parts of a profile table (another profile, or one from a share
-- string) into the current profile.
-- parts: { modules = { Name = true, ... }, general = true, blizzard = true,
-- positions = true (the chosen modules' frames), allPositions = true }. A module keeps its own on/off state; with
-- `positions` its frames move to where the source has them (or back to
-- the layout's place when the source never moved them).
-- Returns true and the list of titles copied.
-- Put `settings` in place of a module's table in the active profile, keeping
-- the profile's own on/off value exactly (false included) while on/off is
-- kept per character, so the other characters' state never changes.
function E:ReplaceModuleSettings(module, settings)
	if not CurrentProfile(self.db, self.profileName) or E.Secret(module) or type(module) ~= "table" or not ProfileTable(settings) then return false end
	local name = rawget(module, "name")
	if E.Secret(name) or type(name) ~= "string" or self.modules[name] ~= module then return false end
	local active, profileName = self.db, self.profileName
	local current = self.db.modules[name]
	local own
	if current and redirected[current] then
		own = redirected[current].value
	elseif current then
		own = rawget(current, "enabled")
	end
	settings.enabled = own
	if current then Restore(current) end
	self.db.modules[name] = settings
	local db = self:GetModuleDB(module)
	if not CurrentProfile(active, profileName) or self.db ~= active or self.profileName ~= profileName or self.modules[name] ~= module then return false end
	module.db = db
	return true
end

function E:ApplyProfileParts(source, parts)
	if not CurrentProfile(self.db, self.profileName) or not ProfileData(source) or not ProfileTable(parts) then return false end
	if QueueProfileWork(self, function() self:ApplyProfileParts(source, parts) end, self.profileName) then return false end
	local active, profileName = self.db, self.profileName
	local function Current()
		return CurrentProfile(active, profileName) and self.db == active and self.profileName == profileName and ProfileData(source)
	end
	-- An older profile or share string: its settings move where they live now.
	self:RunProfileMigrations(source)
	if not Current() then return false end
	if type(parts.modules) == "table" then
		local renamed = {}
		for name in pairs(parts.modules) do
			local module = not self.modules[name] and self.ModuleByAlias and self:ModuleByAlias(name)
			if module then renamed[name] = module.name end
		end
		for old, new in pairs(renamed) do
			parts.modules[old] = nil
			parts.modules[new] = true
		end
	end
	local copied = {}
	local movers = self.db.movers
	-- A part missing from the source means "all defaults" (compact strings).
	-- General keeps this profile's layout (where frames sit and what the
	-- layout hides); the Layout part brings the other one through the
	-- normal layout apply, so places and module sizes match again.
	local sourceGeneral = type(source.general) == "table" and source.general or {}
	if parts.general then
		local general = CopyTable(sourceGeneral)
		for _, key in ipairs(self.LAYOUT_KEYS) do
			local value = self.db.general[key]
			general[key] = type(value) == "table" and CopyTable(value) or value
		end
		self.db.general = ApplyDefaults(general, self.defaults.general)
		copied[#copied + 1] = self.L["General"]
	end
	if parts.layout then
		local key = sourceGeneral.layout or self.defaults.general.layout
		if self.layouts and self.layouts[key] then
			if key ~= self.db.general.layout then
				self:RunOutOfCombat(function()
					if Current() then self:ApplyLayout(key, true) end
				end)
			end
			copied[#copied + 1] = self.L["Layout"]
		end
	end
	if parts.blizzard then
		self.db.blizzard = ApplyDefaults(CopyTable(type(source.blizzard) == "table" and source.blizzard or {}), self.defaults.blizzard or {})
		copied[#copied + 1] = self.L["Blizzard UI switches"]
	end
	if parts.allPositions then
		self.db.movers = CopyTable(type(source.movers) == "table" and source.movers or {})
		movers = self.db.movers
		if self.SetWindowPlaces then
			local mover = type(source.windowMover) == "table" and source.windowMover
			self:SetWindowPlaces(self:WindowPlaces(mover and mover.windows))
		end
		copied[#copied + 1] = self.L["All frame positions"]
	end
	for name in pairs(parts.modules or {}) do
		local module = self.modules[name]
		if module then
			local enabled = module.db and module.db.enabled
			local settings = CopyTable(type(source.modules) == "table" and source.modules[name] or {})
			self:ReplaceModuleSettings(module, settings)
			if not Current() then return false end
			if not PerCharacter() then module.db.enabled = enabled end
			if parts.positions then
				for _, moverName in ipairs(self:ModuleMoverNames(name)) do
					local position = type(source.movers) == "table" and source.movers[moverName]
					movers[moverName] = position and CopyTable(position) or nil
				end
			end
			copied[#copied + 1] = module.title
		end
	end
	if parts.modules then
		self:RefreshModules(function(module) return parts.modules[module.name] end, true)
	end
	if parts.general or parts.blizzard then
		if self.RefreshTheme then self:RefreshTheme() end
		if self.ApplyScale then self:RunOutOfCombat(function() self:ApplyScale() end) end
		if parts.blizzard and self.ApplyBlizzardElements then self:ApplyBlizzardElements() end
	end
	if self.RefreshMovers and self.movers and next(self.movers) then self:RefreshMovers() end
	return true, copied
end

-- The General settings that belong to the layout, not to the look.
E.LAYOUT_KEYS = { "layout", "layoutHidden", "layoutPending", "layoutFit" }

function E:CopyProfileParts(from, parts)
	if not CurrentProfile(self.db, self.profileName) or E.Secret(from) or type(from) ~= "string"
		or not CurrentProfile(rawget(EldoUIDB.profiles, from), from) or from == self.profileName then return false end
	if QueueProfileWork(self, function() self:CopyProfileParts(from, parts) end, self.profileName,
		{ profile = rawget(EldoUIDB.profiles, from), name = from }) then return false end
	return self:ApplyProfileParts(self:CopyProfileTable(from), parts)
end

function E:GetProfileList()
	local list = {}
	if not CurrentAccount() then return list end
	for name, profile in pairs(EldoUIDB.profiles) do if CurrentProfile(profile, name) then table.insert(list, name) end end
	table.sort(list)
	return list
end

-- A saved profile's own table, to read from (nil when there is none). A
-- profile not used in this session holds only what differs from the
-- defaults.
function E:GetProfileTable(name)
	if not CurrentAccount() or E.Secret(name) or type(name) ~= "string" then return nil end
	local profile = rawget(EldoUIDB.profiles, name)
	return CurrentProfile(profile, name) and profile or nil
end

-- Characters (keys) that use a profile.
function E:ProfileUsers(name)
	local list = {}
	if not CurrentAccount() or E.Secret(name) or type(name) ~= "string"
		or not CurrentProfile(rawget(EldoUIDB.profiles, name), name) then return list end
	for char, profile in pairs(EldoUIDB.profileKeys) do
		if profile == name then list[#list + 1] = char end
	end
	table.sort(list)
	return list
end

InitializeAccountOwner()
