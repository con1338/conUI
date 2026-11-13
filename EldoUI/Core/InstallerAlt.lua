local _, E = ...
local L = E.L

---------------------------------------------------------------------------
-- Alt setup: one short page instead of the setup's steps, for a character
-- that never ran the setup on an account where another character did. It
-- puts the character on a profile that is set up already, as it is, and
-- sets up only what belongs to the character: its chat tabs, game
-- settings, other addons' profiles, click-casting and class spells.
--
--   * it opens on such a character's first login (and on /eui install);
--     /eui attach [<profile>] and the Profiles page open it for any
--     character, also one that is set up
--   * every set-up profile is listed: the profile the class profile rule
--     gives the class first, then one a character of the same class and
--     role uses, then the most used one
--   * the character's own parts are copied from another character on the
--     profile: its record of what it picked in its own setup (this
--     file's per-character "setupParts" record, written whenever a setup
--     applies one of those parts); without a record EldoUI's suggestions
--     are shown, and the page says so
--   * class spells and macros are planned for this character's class on
--     empty buttons (the Keys and spells plan without the keys), never
--     copied slot by slot; the key map comes with the profile
--   * Attach: out of combat only. A backup is kept first, the profile is
--     switched (or copied for another role), and each ticked part goes
--     through the setup's own step code. The profile itself does not
--     change: of it only the click-cast list of this class is written,
--     and only when the class has none. The last page lists each part
--     with Revert this; Undo the whole setup (and /eui install undo) puts
--     the character back on the profile it used before, with its parts
--   * a profile set up for another role gets a note: attach anyway, make
--     a copy for this character's role (the original stays as it is), or
--     pick another profile
--
-- The step's short name is kept English and shown as L[step.short]:
-- L["Alt setup"].
---------------------------------------------------------------------------
local Key = E.Key
local Kit = E.WindowKit
local Installer = E.Installer

local Alt = {}
E.InstallerAlt = Alt

-- The character's own picks of its last setup. v: record version; at,
-- version: when and by which EldoUI; class, role; then per part a value
-- or false (kept as it was):
--   chat      { mode, whispers, loot, channels, classColors, fontSize }
--   cvars     { [game setting key] = true }
--   addons    { [addon setup name] = true }
--   clickCast true when the role step set click-cast bindings
--   keys      { spells = bool, macros = bool } (class spells and macros
--             on empty buttons)
E:RegisterPrivate("setupParts", {})
Alt.RECORD_VERSION = 1
Alt.PARTS = { "chat", "cvars", "addons", "clickCast", "keys" }
-- Why the profile row of the last page has no Revert this.
Alt.PROFILE_NOTE = Key("Undo the whole setup puts it back")

local function HL(text) return E:Highlight(text) end
local function Tinted(token, text) return E:TokenHex(E.tokens.text[token]) .. tostring(text) .. "|r" end
local function Warn(text) return Tinted("warn", text) end
local function Muted(text) return Tinted("secondary", text) end

local function PlayerClass()
	local _, class = UnitClass("player")
	if E.Secret and E.Secret(class) then return nil end
	return class
end

local function Session() return Installer.GetSession() end

local function State()
	local s = Session()
	return s and type(s.alt) == "table" and s.alt or nil
end

-- The setup marks of every character (read only).
local function Marks()
	return type(EldoUIDB) == "table" and type(EldoUIDB.installed) == "table" and EldoUIDB.installed or {}
end

local function SetUp(name)
	local profile = E:GetProfileTable(name)
	return profile ~= nil and not profile.needsSetup
end
Alt.IsSetUp = SetUp

-- A value of a saved profile, with the default where it holds none (a
-- profile not used in this session keeps only what differs).
local function Value(profile, section, key)
	local part = profile and profile[section]
	local value
	if type(part) == "table" then value = part[key] end
	if value == nil then
		local defaults = E.defaults[section]
		if type(defaults) == "table" then value = defaults[key] end
	end
	return value
end

local function ModuleValue(profile, name, key)
	local modules = profile and profile.modules
	local settings = type(modules) == "table" and modules[name]
	local value
	if type(settings) == "table" then value = settings[key] end
	if value == nil then
		local module = E.modules[name]
		if module and type(module.defaults) == "table" then value = module.defaults[key] end
	end
	return value
end

local function RoleTitle(role)
	local info = role and E.roleProfiles[role]
	return info and L[info.title] or tostring(role)
end

-- The role layer a profile uses ("none" without one).
local function ProfileRole(name)
	return E:ResolveRoleKey(Value(E:GetProfileTable(name), "general", "role")) or "none"
end

-- The other characters on profile `name`.
local function Users(name)
	local list = {}
	for _, char in ipairs(E:ProfileUsers(name)) do
		if char ~= E.charKey then list[#list + 1] = char end
	end
	return list
end

local function CharName(key)
	local info = E.Characters and E.Characters:Get(key)
	if info and type(info.name) == "string" and info.name ~= "" then return info.name end
	return tostring(key):match("^(.-) %- ") or tostring(key)
end

---------------------------------------------------------------------------
-- The record
---------------------------------------------------------------------------
-- A character's record, or nil (no setup applied one of its parts yet).
function Alt.RecordOf(charKey)
	local record
	if charKey == E.charKey then record = E:GetPrivate("setupParts") else record = E:GetPrivateOf(charKey, "setupParts") end
	if type(record) == "table" and record.v then return record end
end

local function ClassOf(charKey)
	local record = Alt.RecordOf(charKey)
	if record and record.class then return record.class end
	local info = E.Characters and E.Characters:Get(charKey)
	return info and info.class or nil
end

-- This character's record, stamped for a write.
local function OwnRecord()
	local record = E:GetPrivate("setupParts")
	if type(record) ~= "table" then return nil end
	record.v = Alt.RECORD_VERSION
	record.at = time()
	record.version = E.version
	record.class = PlayerClass() or record.class
	record.role = E:GetRole()
	return record
end

local function Picked(list)
	local out = {}
	for key, on in pairs(type(list) == "table" and list or {}) do
		if on then out[key] = true end
	end
	return next(out) and out or false
end

local function ChatRecord(c)
	if type(c) ~= "table" or c.mode == "keep" then return false end
	return { mode = c.mode, whispers = c.whispers and true or nil, loot = c.loot and true or nil, channels = c.channels and true or nil,
		classColors = c.classColors and true or nil, fontSize = tonumber(c.fontSize) }
end

-- A setup step applied (Core/Installer.lua SafeApply): keep this
-- character's pick of it.
function Alt.NoteStep(key, s)
	if type(s) ~= "table" then return end
	if key == "chat" then
		local record = OwnRecord()
		if record then record.chat = ChatRecord(s.chat) end
	elseif key == "cvars" then
		local record = OwnRecord()
		if record then record.cvars = Picked(s.cvars and s.cvars.picks) end
	elseif key == "addons" then
		local record = OwnRecord()
		if record then record.addons = Picked(s.addons and s.addons.selected) end
	elseif key == "role" then
		local record = OwnRecord()
		if record then
			if s.role and s.role.clickCastBound then
				record.clickCast = true
			elseif record.clickCast == nil then
				record.clickCast = false
			end
		end
	elseif key == "keys" then
		local record = OwnRecord()
		local k = s.keys
		if record and type(k) == "table" then record.keys = { spells = k.spells and true or false, macros = k.macros and true or false } end
	end
end

-- The setup finished: a full setup's steps that changed nothing count as
-- "kept as it was". attach: the alt setup wrote its own parts already.
function Alt.NoteFinish(s, attach)
	if type(s) ~= "table" then return end
	local record = OwnRecord()
	if not record or attach or s.focus ~= nil then return end
	for _, key in ipairs({ "chat", "cvars", "addons", "keys" }) do
		local data = s[key]
		if type(data) == "table" and data.state ~= "applied" and record[key] == nil then record[key] = false end
	end
	if record.clickCast == nil then record.clickCast = false end
end

---------------------------------------------------------------------------
-- Which characters get the page, and the profiles it offers
---------------------------------------------------------------------------
-- A character that never ran the setup, while another character finished
-- (or skipped) it on a profile that is set up.
function Alt.Qualifies()
	if type(EldoUIDB) ~= "table" or type(EldoUIDB.profiles) ~= "table" then return false end
	local marks = Marks()
	if marks[E.charKey] then return false end
	for _, name in ipairs(E:GetProfileList()) do
		if SetUp(name) then
			for _, char in ipairs(Users(name)) do
				if marks[char] then return true end
			end
		end
	end
	return false
end

-- Every set-up profile, best first: { name, users, rank, rule }.
-- rank 1: the class profile rule's profile; 2: a character of this class
-- and role uses it; 3: one of this class; 4: the rest. Then the most
-- used, then by name.
function Alt.Candidates()
	local class, role = PlayerClass(), E:DetectRole()
	local rule = E.GetClassProfile and E:GetClassProfile(class) or nil
	local list = {}
	for _, name in ipairs(E:GetProfileList()) do
		if SetUp(name) then
			local entry = { name = name, users = Users(name), rank = 4 }
			for _, char in ipairs(entry.users) do
				if class and ClassOf(char) == class then
					local record = Alt.RecordOf(char)
					local charRole = record and record.role or ProfileRole(name)
					entry.rank = math.min(entry.rank, (role and charRole == role) and 2 or 3)
				end
			end
			if name == rule then entry.rank, entry.rule = 1, true end
			list[#list + 1] = entry
		end
	end
	table.sort(list, function(a, b)
		if a.rank ~= b.rank then return a.rank < b.rank end
		if #a.users ~= #b.users then return #a.users > #b.users end
		return a.name < b.name
	end)
	return list
end

-- The character on `name` to copy from first: the one played last.
function Alt.DefaultSource(name)
	local best, seen = "", -1
	for _, char in ipairs(name and Users(name) or {}) do
		local info = E.Characters and E.Characters:Get(char)
		local when = info and tonumber(info.seen) or 0
		if when > seen then best, seen = char, when end
	end
	return best
end

-- The page's picks (kept with the run): profile, source (a character
-- key, "" for EldoUI's suggestions), ticks ({ [part] = bool } where the
-- player changed one), roleChoice ("attach", "copy" or "other").
function Alt.Start(s)
	local a = type(s.alt) == "table" and s.alt or {}
	s.alt = a
	a.state = a.state or "none"
	a.ticks = type(a.ticks) == "table" and a.ticks or {}
	if not (a.profile and SetUp(a.profile)) then
		local first = Alt.Candidates()[1]
		a.profile = first and first.name or nil
		a.source = nil
		a.roleChoice = nil
		wipe(a.ticks)
	end
	local known = a.source == ""
	for _, char in ipairs(a.profile and Users(a.profile) or {}) do
		if char == a.source then known = true end
	end
	if not known then a.source = Alt.DefaultSource(a.profile) end
	a.roleChoice = a.roleChoice or "attach"
	return a
end

-- Pick profile `name` on the page. Returns false when it can't be picked.
function Alt.Pick(name)
	local a = State()
	if not a or a.state == "applied" or not (name and SetUp(name)) then return false end
	if a.profile ~= name or a.roleChoice == "other" then
		a.profile = name
		a.source = Alt.DefaultSource(name)
		a.roleChoice = "attach"
		wipe(a.ticks)
	end
	return true
end

-- The picked profile's role layer when it is not this character's role:
-- the profile's role and the detected one, else nil.
function Alt.RoleMismatch()
	local a = State()
	if not (a and a.profile) then return nil end
	local detected = E:DetectRole()
	local role = ProfileRole(a.profile)
	if not detected or detected == "none" or role == "none" or detected == role then return nil end
	return role, detected
end

-- The name of a copy of `name` for `role`, not taken yet.
function Alt.CopyName(name, role)
	local base = ("%s (%s)"):format(name, RoleTitle(role))
	local candidate, count = base, 1
	while E:GetProfileTable(candidate) do
		count = count + 1
		candidate = ("%s %d"):format(base, count)
	end
	return candidate
end

function Alt.CanAttach()
	local a = State()
	return a ~= nil and a.state ~= "applied" and not Alt.pending and a.profile ~= nil and SetUp(a.profile)
		and a.roleChoice ~= "other"
end

---------------------------------------------------------------------------
-- What the page shows
---------------------------------------------------------------------------
-- EldoUI's suggestions for a character's own parts (as on a first run).
local function Suggested()
	local parts = { chat = false, cvars = {}, addons = {}, clickCast = false, keys = { spells = true, macros = true } }
	if Installer.ChatAvailable() then
		parts.chat = { mode = "tabs", whispers = true, loot = true, channels = true, classColors = true }
	end
	for _, info in ipairs(Installer.GAME_SETTINGS) do parts.cvars[info.key] = true end
	for _, name in ipairs(E.addonSetupOrder or {}) do
		local setup = E.addonSetups[name]
		if setup and setup.preselect ~= false then parts.addons[name] = true end
	end
	return parts
end

-- The parts to copy from character `source`: its record, else (and for a
-- part its record lacks) the suggestions. Returns the parts and whether
-- they come from a record.
function Alt.PartsFrom(source)
	local suggested = Suggested()
	local record = source and source ~= "" and Alt.RecordOf(source)
	if not record then return suggested, false end
	local parts = {}
	for _, key in ipairs(Alt.PARTS) do
		local value = record[key]
		if value == nil then value = suggested[key] end
		parts[key] = value
	end
	return parts, true
end

-- The click-cast suggestions this character can still get, when the
-- picked profile has Click Casting on and no bindings for this class: a
-- list, else nil and why ("profile": the profile has some already).
local function ClickCastOffer(a, role)
	local clickCast = E.modules.ClickCast
	local profile = E:GetProfileTable(a.profile)
	if not (clickCast and clickCast.SetBinding and profile) or not ModuleValue(profile, "ClickCast", "enabled") then return nil end
	local class = PlayerClass()
	local sets = ModuleValue(profile, "ClickCast", "sets")
	if class and type(sets) == "table" then
		for setKey, list in pairs(sets) do
			if (setKey == class or setKey:match("^(.-)%-%d+$") == class) and type(list) == "table" and #list > 0 then return nil, "profile", #list end
		end
	end
	if role ~= "healer" then return nil end
	local list = {}
	for _, item in ipairs(E:GetRoleClickCast()) do
		if not item.conflict and not item.bound then list[#list + 1] = item end
	end
	return #list > 0 and list or nil
end

-- The role this character will have on the picked profile.
local function RoleAfter(a)
	local role, detected = Alt.RoleMismatch()
	if role and a.roleChoice == "copy" then return detected end
	return ProfileRole(a.profile)
end

-- The key set a profile's key map names, or nil (none chosen, or the
-- player's own keys: the plan then uses the first set's spell homes).
local function ProfileKeySet(name)
	local profile = name and E:GetProfileTable(name)
	local keymap = profile and type(profile.keymap) == "table" and profile.keymap
	local preset = keymap and keymap.preset
	if type(preset) ~= "string" or preset == "" or preset == "none" or not E.KeybindPresetKey then return nil end
	return E:KeybindPresetKey(preset)
end

local function SpellsPlan(keys, profileName)
	if not (E.KeysAndSpellsPlan and type(keys) == "table" and (keys.spells or keys.macros)) then return nil end
	local ok, plan = pcall(E.KeysAndSpellsPlan, E, { id = ProfileKeySet(profileName), keys = false, upgrades = false,
		spells = keys.spells and true or false, macros = keys.macros and true or false })
	return ok and plan or nil
end

local function SpellsText(plan)
	local c = plan.counts
	local placed = c.spells + c.premade
	local parts = {}
	if placed > 0 then parts[#parts + 1] = E:Plural(placed, "%d class spell on an empty button", "%d class spells on empty buttons"):format(placed) end
	if c.macros > 0 then parts[#parts + 1] = E:Plural(c.macros, "%d class macro", "%d class macros"):format(c.macros) end
	return table.concat(parts, ", ")
end

-- The rows of "This character gets": { key, label, value, enabled, on,
-- tip, data }. A row with nothing to set up shows why, unticked.
function Alt.Rows()
	local a = State()
	if not a then return {} end
	local parts = Alt.PartsFrom(a.source)
	local rows = {}
	local function Row(key, label, tip, value, data)
		local row = { key = key, label = label, tip = tip, value = value, enabled = data ~= nil, data = data }
		local tick = a.ticks[key]
		if tick == nil then tick = data ~= nil and (key ~= "clickCast" or parts.clickCast) end
		row.on = row.enabled and tick and true or false
		rows[#rows + 1] = row
	end
	-- Chat tabs
	if Installer.ChatAvailable() then
		local c = parts.chat
		local words = {}
		if type(c) == "table" then
			for _, tab in ipairs(Installer.CHAT_TABS) do
				if c[tab.key] then words[#words + 1] = L[tab.title] end
			end
			if c.classColors then words[#words + 1] = L["class-colored names"] end
			if tonumber(c.fontSize) then words[#words + 1] = L["font size %d"]:format(c.fontSize) end
		end
		local tip = L["This character's own chat windows: the tabs are made and filled the way the setup's Chat step does it."]
		if #words > 0 then
			local data = { mode = "tabs", whispers = c.whispers and true or false, loot = c.loot and true or false,
				channels = c.channels and true or false, classColors = c.classColors and true or false, fontSize = tonumber(c.fontSize) }
			Row("chat", L["Chat tabs"], tip, table.concat(words, ", "), data)
		else
			Row("chat", L["Chat tabs"], tip, L["Kept as they are"])
		end
	end
	-- Game settings
	do
		local list, picks, labels = {}, parts.cvars, {}
		for _, info in ipairs(Installer.GAME_SETTINGS) do
			if type(picks) == "table" and picks[info.key] and Installer.GameSettingStatus(info) == "ready" then
				list[info.key] = true
				labels[#labels + 1] = L[info.label]
			end
		end
		local tip = L["Game settings are kept per character: the ones checked here are set the way the setup's Game settings step does it."]
		if #labels > 0 then
			Row("cvars", L["Game settings"], tip, table.concat(labels, ", "), list)
		elseif type(picks) == "table" and next(picks) then
			Row("cvars", L["Game settings"], tip, L["Already set on this character"])
		else
			Row("cvars", L["Game settings"], tip, L["Kept as they are"])
		end
	end
	-- Other addons' profiles: only when one of them is loaded.
	do
		local any, list, titles = false, {}, {}
		for _, name in ipairs(E.addonSetupOrder or {}) do
			if E:GetAddonSetupStatus(name) == "ready" then
				any = true
				if type(parts.addons) == "table" and parts.addons[name] then
					list[name] = true
					titles[#titles + 1] = E.addonSetups[name].title
				end
			end
		end
		if any then
			local tip = L["Other addons keep a profile per character: EldoUI's profile for each one checked is imported with that addon's own import function."]
			if #titles > 0 then
				Row("addons", L["Other addons' profiles"], tip, table.concat(titles, ", "), list)
			else
				Row("addons", L["Other addons' profiles"], tip, L["Kept as they are"])
			end
		end
	end
	-- Click-casting: only a class without bindings on the profile.
	do
		local list, why, count = ClickCastOffer(a, RoleAfter(a))
		local tip = L["Click-cast bindings are kept per class in the profile. A class that has none there yet gets the healer suggestions for its spells; another class's bindings stay as they are."]
		if list then
			local labels = {}
			for _, item in ipairs(list) do labels[#labels + 1] = ("%s: %s"):format(item.label or item.key, item.spell) end
			Row("clickCast", L["Click-casting"], tip, table.concat(labels, ", "), list)
		elseif why == "profile" then
			Row("clickCast", L["Click-casting"], tip, E:Plural(count, "Comes with the profile: %d binding for your class", "Comes with the profile: %d bindings for your class"):format(count))
		end
	end
	-- Class spells and macros on empty buttons.
	do
		local tip = L["Planned for this character's class: spells and macros go on empty buttons only, and nothing you placed moves. Your keys stay as the profile's key map has them."]
		local plan = SpellsPlan(parts.keys, a.profile)
		if plan and plan.counts.spells + plan.counts.premade + plan.counts.macros > 0 then
			Row("keys", L["Class spells and macros"], tip, SpellsText(plan), { spells = parts.keys.spells and true or false, macros = parts.keys.macros and true or false })
		elseif plan then
			Row("keys", L["Class spells and macros"], tip, L["Nothing to place: your buttons hold them already"])
		else
			Row("keys", L["Class spells and macros"], tip, L["Kept as they are"])
		end
	end
	return rows
end

local function OnOff(on) return on and L["On"] or L["Off"] end

-- "From the profile (unchanged)": { label, value } per part of the profile.
function Alt.ProfileLines(name)
	local profile = E:GetProfileTable(name)
	local lines = {}
	if not profile then return lines end
	local function Add(label, value) lines[#lines + 1] = { label, value } end
	Add(L["Layout"], E:LayoutTitle(Value(profile, "general", "layout")))
	local art = Value(profile, "general", "artStyle")
	local info = E.artStyleInfo[art]
	Add(L["Skin"], info and L[info.title] or tostring(art))
	local styled, total = 0, 0
	for moduleName in pairs(E.styles or {}) do
		if E.modules[moduleName] then
			total = total + 1
			local style = ModuleValue(profile, moduleName, "style")
			if type(style) == "string" and style ~= "" then styled = styled + 1 end
		end
	end
	Add(L["Styles"], styled > 0 and L["%d of %d parts of the UI have a style picked"]:format(styled, total) or L["EldoUI's own look for every part"]) -- no-plural: the count of all parts, never 1
	local role = ProfileRole(name)
	Add(L["Role"], role ~= "none" and RoleTitle(role) or L["None"])
	local on, all = 0, 0
	for moduleName in E:IterateModules() do
		if not Installer.notInSetup[moduleName] then
			all = all + 1
			if ModuleValue(profile, moduleName, "enabled") then on = on + 1 end
		end
	end
	Add(L["Modules"], L["%d of %d on"]:format(on, all))
	local replaced, count = 0, 0
	local blizzard = profile.blizzard
	for _, id in ipairs(E.blizzardElementOrder or {}) do
		count = count + 1
		local state = type(blizzard) == "table" and blizzard[id]
		local enabled
		if type(state) == "table" then enabled = state.enabled end
		if enabled == nil then
			local default = E.defaults.blizzard and E.defaults.blizzard[id]
			enabled = type(default) == "table" and default.enabled
		end
		if enabled then replaced = replaced + 1 end
	end
	Add(L["Blizzard UI"], L["EldoUI changes %d of %d Blizzard frames"]:format(replaced, count))
	local convenience = {}
	local repair = ModuleValue(profile, "Merchant", "autoRepair")
	if repair and repair ~= "off" then convenience[#convenience + 1] = L["Repair automatically at vendors"] end
	if ModuleValue(profile, "Merchant", "sellJunk") then convenience[#convenience + 1] = L["Sell gray items at vendors"] end
	if ModuleValue(profile, "Loot", "fastLoot") then convenience[#convenience + 1] = L["Faster auto loot"] end
	Add(L["Convenience"], #convenience > 0 and table.concat(convenience, ", ") or OnOff(false))
	-- Where the layout places other addons that are loaded.
	local fit = {}
	for _, entry in ipairs(E.addonPlacements or {}) do
		if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(entry.addon) then
			local placed = true
			for _, path in ipairs(entry.switches or {}) do
				local first, rest = path:match("^([^.]+)%.(.+)$")
				local value
				if first then
					local part = ModuleValue(profile, entry.module, first)
					if type(part) == "table" then value = part[rest] end
				else
					value = ModuleValue(profile, entry.module, path)
				end
				if not value then placed = false end
			end
			fit[#fit + 1] = (placed and L["%s placed by the layout"] or L["%s left in its own spot"]):format(entry.title)
		end
	end
	if #fit > 0 then Add(L["Other addons"], table.concat(fit, ", ")) end
	-- The key set of the profile's key map (E.db.keymap): none chosen yet
	-- when the profile has no choice saved.
	if E.KeymapRecord then
		local keymap = type(profile.keymap) == "table" and profile.keymap or {}
		local preset, text = keymap.preset
		if preset == nil or preset == "" then
			text = L["Not chosen yet"]
		elseif preset == "none" then
			text = L["You manage your own keys"]
		elseif preset == "custom" then
			text = L["Your own key map"]
		else
			local id = E.KeybindPresetKey and E:KeybindPresetKey(preset)
			local known = id and E.keybindPresets[id]
			text = known and L[known.title] or tostring(preset)
		end
		Add(L["Key set"], text)
	end
	return lines
end

---------------------------------------------------------------------------
-- Attach
---------------------------------------------------------------------------
-- The click-cast list of this class, kept for Revert this.
Installer.AddPart("clickcast", {
	capture = function()
		local clickCast = E.modules.ClickCast
		if not (clickCast and clickCast.db and clickCast.GetBindings) then return false end
		local set, key = clickCast:GetBindings()
		return { key = key, set = CopyTable(set) }
	end,
	restore = function(data)
		local clickCast = E.modules.ClickCast
		if not (clickCast and clickCast.db and data.key) then return end
		clickCast.db.sets[data.key] = CopyTable(data.set or {})
		if clickCast.Changed then clickCast:Changed() end
	end,
	changed = function(data)
		local clickCast = E.modules.ClickCast
		if not (clickCast and clickCast.db and data.key) then return false end
		return not E.DeepEqual(clickCast.db.sets[data.key] or {}, data.set or {})
	end,
})

local function FrameID(frame)
	return type(frame) == "table" and frame.GetID and frame:GetID() or nil
end

-- A chat record of the run (frames) as saved data (window numbers).
local function SaveChat(data)
	if type(data) ~= "table" then return nil end
	local out = { opened = {}, added = {}, moved = {}, joined = {}, channels = {}, sizes = {}, colors = CopyTable(data.colors or {}) }
	for _, frame in ipairs(data.opened or {}) do out.opened[#out.opened + 1] = FrameID(frame) end
	for _, pair in ipairs(data.added or {}) do out.added[#out.added + 1] = { FrameID(pair[1]), pair[2] } end
	for _, group in ipairs(data.moved or {}) do out.moved[#out.moved + 1] = group end
	for _, pair in ipairs(data.joined or {}) do out.joined[#out.joined + 1] = { FrameID(pair[1]), pair[2] } end
	for _, name in ipairs(data.channels or {}) do out.channels[#out.channels + 1] = name end
	for _, pair in ipairs(data.sizes or {}) do out.sizes[#out.sizes + 1] = { FrameID(pair[1]), pair[2] } end
	out.reset = data.reset
	return out
end

-- And back to frames (a window that is gone is left out).
local function LoadChat(saved)
	local function Frame(id) return id and _G["ChatFrame" .. id] or nil end
	local data = { opened = {}, added = {}, moved = {}, joined = {}, channels = {}, sizes = {}, colors = saved.colors or {}, reset = saved.reset }
	for _, id in ipairs(saved.opened or {}) do
		local frame = Frame(id)
		if frame then data.opened[#data.opened + 1] = frame end
	end
	for _, pair in ipairs(saved.added or {}) do
		local frame = Frame(pair[1])
		if frame then data.added[#data.added + 1] = { frame, pair[2] } end
	end
	for _, group in ipairs(saved.moved or {}) do data.moved[#data.moved + 1] = group end
	for _, pair in ipairs(saved.joined or {}) do
		local frame = Frame(pair[1])
		if frame then data.joined[#data.joined + 1] = { frame, pair[2] } end
	end
	for _, name in ipairs(saved.channels or {}) do data.channels[#data.channels + 1] = name end
	for _, pair in ipairs(saved.sizes or {}) do
		local frame = Frame(pair[1])
		if frame then data.sizes[#data.sizes + 1] = { frame, pair[2] } end
	end
	return data
end

local function GameCVar(name)
	return C_CVar and C_CVar.GetCVar and C_CVar.GetCVar(name)
end

-- The ticked parts and their data, from the rows the page shows, and
-- the parts the page showed (a part not shown is left out of the record).
function Alt.Wanted()
	local want, shown = {}, {}
	for _, row in ipairs(Alt.Rows()) do
		shown[row.key] = true
		if row.on and row.data then want[row.key] = row.data end
	end
	return want, shown
end

-- One part, protected: an error skips it, the rest goes on.
local function Part(key, title, failed, fn)
	local ok, err = pcall(fn)
	if ok then return true end
	geterrorhandler()(err)
	local s = Session()
	local group = s and s.undo.groups[key]
	if group then group.failed = true end
	failed[#failed + 1] = { key = key, title = title }
	return false
end

-- The attach itself (out of combat).
function Alt.DoAttach(s)
	local a = s.alt
	local failed = {}
	local want, shown = Alt.Wanted()
	local role, detected = Alt.RoleMismatch()
	local copy = role ~= nil and a.roleChoice == "copy"
	local previous = E.profileName
	local source = a.profile
	local target = copy and Alt.CopyName(source, detected) or source
	-- A backup first: Undo puts this character back on `previous`.
	Installer.Backup(target, previous)
	local backup = Installer.GetBackup()
	if backup then
		-- The profile is not changed, so its copy is not needed.
		backup.data = false
		backup.attach = true
		backup.copy = copy or nil
		backup.parts = {}
	end
	local parts = backup and backup.parts or {}
	if copy then
		E:SetProfile(target, true)
		E:CopyProfile(source)
	elseif target ~= previous then
		E:SetProfile(target, true)
	end
	E:UpdateAccent()
	E:ApplyScale()
	if E.RefreshTheme then E:RefreshTheme() end
	s.needsReload = target ~= previous
	s.profile.mode, s.profile.fresh = "attach", false
	Installer.ProfileDone()
	local group = Installer.ChangeGroup("profile")
	group.note = Alt.PROFILE_NOTE
	group.texts = group.texts or {}
	group.texts.alt = copy and L["Profile: %s, a copy of %s for the %s role"]:format(HL(target), HL(source), RoleTitle(detected))
		or L["Profile: %s, as it is"]:format(HL(target))
	-- The copy gets this character's role through the Role step.
	if copy then
		s.role = { choice = detected, classLayer = E.db.general.roleClass and true or false, clickCast = false, picks = {}, state = "none" }
		local step = Installer.BaseStep("role")
		if step then Installer.SafeApply(step, failed) end
	end
	local record = OwnRecord()
	-- Chat tabs, through the Chat step.
	if want.chat then
		local c = want.chat
		s.chat = { mode = "tabs", whispers = c.whispers, loot = c.loot, channels = c.channels, classColors = c.classColors,
			fontSize = c.fontSize, state = "none" }
		local step = Installer.BaseStep("chat")
		if step and step.HasChoice() then
			Installer.SafeApply(step, failed)
			local chatGroup = s.undo.groups.chat
			parts.chat = SaveChat(chatGroup and chatGroup.parts.chat)
		end
	elseif record and shown.chat then
		record.chat = false
	end
	-- Game settings, through the Game settings step.
	if want.cvars then
		s.cvars = { picks = CopyTable(want.cvars), state = "none" }
		local step = Installer.BaseStep("cvars")
		if step and step.HasChoice() then
			local values = {}
			for _, info in ipairs(Installer.GAME_SETTINGS) do
				if want.cvars[info.key] and Installer.GameSettingStatus(info) == "ready" then
					for _, pair in ipairs(info.values) do
						local before = GameCVar(pair[1])
						if before ~= nil and tostring(before) ~= pair[2] then values[pair[1]] = { tostring(before), pair[2] } end
					end
				end
			end
			Installer.SafeApply(step, failed)
			parts.cvars = values
		end
	elseif record and shown.cvars then
		record.cvars = false
	end
	-- Other addons' profiles, through the Other addons step.
	if want.addons then
		s.addons = { selected = CopyTable(want.addons), place = {}, guide = nil, state = "none" }
		local step = Installer.BaseStep("addons")
		if step and step.HasChoice() then Installer.SafeApply(step, failed) end
	elseif record and shown.addons then
		record.addons = false
	end
	-- Click-casting: the suggestions for this class (the module is on).
	if want.clickCast then
		Part("clickcast", L["Click-casting"], failed, function()
			local kept = Installer.Remember("clickcast", "clickcast")
			local clickGroup = Installer.ChangeGroup("clickcast")
			local made = E:BindRoleClickCast(want.clickCast)
			local labels = {}
			for _, item in ipairs(want.clickCast) do labels[#labels + 1] = ("%s: %s"):format(item.label or item.key, item.spell) end
			clickGroup.texts = clickGroup.texts or {}
			clickGroup.texts.alt = L["Click-casting: %s"]:format(table.concat(labels, ", "))
			local clickCast = E.modules.ClickCast
			if made > 0 and kept and clickCast and clickCast.GetBindings then
				local set, setKey = clickCast:GetBindings()
				parts.clickcast = { key = setKey, before = CopyTable(kept.set or {}), after = CopyTable(set) }
			end
			if record then record.clickCast = made > 0 end
		end)
	elseif record and shown.clickCast then
		record.clickCast = false
	end
	-- Class spells and macros on empty buttons: planned for this class now,
	-- on the profile in use, without the keys.
	if want.keys then
		Part("keys", L["Class spells and macros"], failed, function()
			local plan = SpellsPlan(want.keys, E.profileName)
			if not (plan and plan.counts.total > 0) then return end
			Installer.Remember("keys", "keys")
			local keysGroup = Installer.ChangeGroup("keys")
			Installer.NotePremade(plan)
			local before = E:KeysAndSpellsRecord()
			-- Spells and macros only: the profile's key map choice and this
			-- character's key map record (the key set applied, the keys set
			-- by hand) stay exactly as they were.
			local keymap = type(E.db.keymap) == "table" and E.db.keymap or nil
			local private = E:GetPrivate("keymap")
			private = type(private) == "table" and private or nil
			local keymapBefore = keymap and CopyTable(keymap)
			local privateBefore = private and CopyTable(private)
			E:ApplyKeysAndSpells(plan, false)
			for _, pair in ipairs({ { keymap, keymapBefore }, { private, privateBefore } }) do
				local store, saved = pair[1], pair[2]
				if store then
					wipe(store)
					for key, value in pairs(saved) do store[key] = value end
				end
			end
			local after = E:KeysAndSpellsRecord()
			if after and after ~= before then parts.keys = { time = after.time } end
			keysGroup.texts = keysGroup.texts or {}
			keysGroup.texts.alt = L["Class spells and macros: %s"]:format(SpellsText(plan))
			if record then record.keys = { spells = want.keys.spells, macros = want.keys.macros } end
		end)
	elseif record and shown.keys then
		record.keys = false
	end
	a.state = "applied"
	-- The key map of the profile now in use, for this character.
	if E.KeymapCheck then
		local ok, err = pcall(E.KeymapCheck, E, "attach")
		if not ok then geterrorhandler()(err) end
	end
	E:Print(L["This character uses profile %s now."]:format(HL(target)))
	Installer.CompleteAttach(failed)
end

-- The Attach button: waits for the end of combat (the profile switch
-- moves protected frames).
function Alt.Attach()
	local s = Session()
	if not (s and Alt.CanAttach()) then return false end
	local ran = E:RunOutOfCombat(function()
		Alt.pending = nil
		local now = Session()
		if now ~= s or s.finished or not (s.alt and s.alt.state ~= "applied") then return end
		Alt.DoAttach(s)
	end, "installer-attach")
	if not ran then
		Alt.pending = true
		Installer.ShowToast(L["In combat: this character is attached when combat ends."], true)
		Installer.Update()
	end
	return ran
end

-- E:UndoInstall of an attach: the character's own parts go back where
-- they still hold what the attach wrote, then the character goes back on
-- the profile it used before; a copy made for it is deleted. Returns the
-- profile in use afterwards.
function Alt.UndoAttach(backup)
	local parts = type(backup.parts) == "table" and backup.parts or {}
	if parts.chat and not parts.chat.reset then Installer.RestorePart("chat", LoadChat(parts.chat)) end
	if type(parts.cvars) == "table" then
		local data = {}
		for name, pair in pairs(parts.cvars) do
			if tostring(GameCVar(name)) == pair[2] then data[name] = pair[1] end
		end
		if next(data) then Installer.RestorePart("cvars", data) end
	end
	if type(parts.keys) == "table" and E.KeysAndSpellsRecord then
		local record = E:KeysAndSpellsRecord()
		if record and record.time == parts.keys.time then E:RestoreKeysAndSpells(false, { spells = true, premade = true }) end
	end
	local clickCast = E.modules.ClickCast
	if type(parts.clickcast) == "table" and clickCast and clickCast.db and E.profileName == backup.profile then
		local data = parts.clickcast
		if E.DeepEqual(clickCast.db.sets[data.key] or {}, data.after or {}) then
			Installer.RestorePart("clickcast", { key = data.key, set = data.before })
		end
	end
	local name = backup.previous or backup.profile
	if name ~= E.profileName then E:SetProfile(name, true) end
	if backup.copy and backup.profile ~= name then E:DeleteProfile(backup.profile) end
	return name
end

---------------------------------------------------------------------------
-- The page
---------------------------------------------------------------------------
local Secondary, Paragraph, Tooltip, Button, Check, Choice =
	Kit.Secondary, Kit.Paragraph, Kit.Tooltip, Kit.Button, Kit.Check, Kit.Choice

local function Width() return Installer.CONTENT_W - 22 end

-- The profile row's text: what it is and who uses it.
local function ProfileDesc(entry)
	local profile = E:GetProfileTable(entry.name)
	local layout = E:LayoutTitle(Value(profile, "general", "layout"))
	local art = E.artStyleInfo[Value(profile, "general", "artStyle")]
	local names = {}
	for _, char in ipairs(entry.users) do names[#names + 1] = CharName(char) end
	local who = #names > 0 and table.concat(names, ", ") or L["no character yet"]
	return L["Layout: %s. Skin: %s. Used by: %s."]:format(layout, art and L[art.title] or "?", who)
end

local function SourceValues()
	local a = State()
	local list = {}
	for _, char in ipairs(a and a.profile and Users(a.profile) or {}) do
		local record = Alt.RecordOf(char)
		list[#list + 1] = { char, record and CharName(char) or L["%s (no saved setup)"]:format(CharName(char)) }
	end
	list[#list + 1] = { "", L["EldoUI's suggestions"] }
	return list
end

local STEP = {
	key = "alt", short = "Alt setup", title = "Set up this character",
	desc = "Another character set up EldoUI on this account. Put this one on a profile you already have, as it is: only this character's own parts are set up.",
	help = Key("A profile holds the layout, skin, styles, modules and the Blizzard UI switches, and characters can share one. This page puts this character on a profile that is set up already and changes nothing in it.\n\nWhat belongs to the character is set up for it: chat tabs, game settings, other addons' profiles, click-casting for a class that has none on the profile yet, and class spells and macros on empty buttons. Each comes from what the character you copy from picked in its own setup, or from EldoUI's suggestions when it has no saved setup. Uncheck a part to leave it as it is.\n\nA profile set up for another role can be copied for this character's role: the copy gets the role, and the original stays as it is.\n\nAttach keeps a backup first. The last page lists every change with Revert this, and Undo the whole setup (or /eui install undo) puts this character back on the profile it used before. Full setup instead goes through every step on its own."),
	owns = Installer.STEP_OWNS.alt,
}
Alt.STEP = STEP

function STEP.Build(frame)
	local holder = CreateFrame("Frame", nil, frame)
	holder:SetPoint("TOPLEFT", 0, 0)
	holder:SetPoint("BOTTOMRIGHT", 0, E.tokens.height.button + 10)
	local scroll, child = Installer.ScrollArea(holder)
	frame.scroll, frame.child = scroll, child
	local width = Width()
	frame.intro = Paragraph(child, E.tokens.size.body)
	frame.intro:SetWidth(width)
	frame.pickHeader = E:CreateText(child, E.tokens.size.cardTitle, "LEFT")
	frame.pickHeader:SetText(L["Pick a profile"])
	frame.rows = {}
	-- The role note and its three answers.
	frame.roleNote = Paragraph(child, E.tokens.size.label)
	frame.roleNote:SetWidth(width)
	frame.roleChoices = {}
	for index, choiceKey in ipairs({ "attach", "copy", "other" }) do
		local choice = Choice(child, 200, 64, "", "", function()
			local a = State()
			if not a or a.state == "applied" then return end
			a.roleChoice = choiceKey
			Installer.Update()
		end)
		choice.choiceKey = choiceKey
		frame.roleChoices[index] = choice
	end
	-- The character to copy from.
	frame.sourceLabel = E:CreateText(child, E.tokens.size.body, "LEFT")
	frame.sourceLabel:SetText(L["Copy this character's own parts from"])
	frame.source = Kit.Dropdown(child, {
		values = SourceValues,
		get = function()
			local a = State()
			return a and a.source or ""
		end,
		set = function(value)
			local a = State()
			if not a or a.state == "applied" then return end
			a.source = value
			wipe(a.ticks)
			Installer.Update()
		end,
		width = 300,
		tipTitle = L["Copy this character's own parts from"],
		tip = L["A character on the picked profile. Its own picks from its setup are checked below; a character without a saved setup gets EldoUI's suggestions."],
	})
	frame.sourceNote = Secondary(Paragraph(child, E.tokens.size.label))
	frame.sourceNote:SetWidth(width)
	-- What comes with the profile, and what this character gets.
	frame.profileCard = E.UIKit.SectionCard(child, { label = L["From the profile (unchanged)"] })
	frame.profileCard:SetWidth(width)
	frame.profileCard.text = Paragraph(frame.profileCard.body, E.tokens.size.label)
	frame.profileCard.text:SetPoint("TOPLEFT", 12, -10)
	frame.profileCard.text:SetWidth(width - 24)
	frame.partsCard = E.UIKit.SectionCard(child, { label = L["This character gets"] })
	frame.partsCard:SetWidth(width)
	frame.partsCard.rows = {}
	frame.partsCard.empty = Secondary(Paragraph(frame.partsCard.body, E.tokens.size.label))
	frame.partsCard.empty:SetPoint("TOPLEFT", 12, -10)
	frame.partsCard.empty:SetWidth(width - 24)
	frame.partsCard.empty:SetText(L["Nothing of this character's own needs setting up."])
	-- At the bottom: the full setup, skip and undo.
	frame.full = Button(frame, { text = L["Full setup instead"], minWidth = 160, onClick = function() Installer.SwitchRun(nil) end })
	frame.full:SetPoint("BOTTOMRIGHT", 0, 0)
	Tooltip(frame.full, L["Full setup instead"], L["Goes through every step of the setup on its own, from the Welcome step, as on a first character."])
	frame.skipAll = Button(frame, { text = L["Skip the setup"], minWidth = 140, onClick = function() Installer.SkipForGood() end })
	frame.skipAll:SetPoint("RIGHT", frame.full, "LEFT", -8, 0)
	Tooltip(frame.skipAll, L["Skip the setup"], L["Close the setup for good: it doesn't open at login again. Closing the window instead pauses it, and /eui install goes on where you stopped."])
	frame.undo = Button(frame, { text = L["Undo the last setup"], minWidth = 160, onClick = function() E:UndoInstall() end })
	frame.undo:SetPoint("BOTTOMLEFT", 0, 0)
end

-- A row of "This character gets": a check and its value under it.
local function PartRow(frame, index)
	local card = frame.partsCard
	local row = card.rows[index]
	if row then return row end
	row = {}
	row.check = Check(card.body, "", nil, function(on)
		local a = State()
		if not (a and row.key) or a.state == "applied" then return end
		a.ticks[row.key] = on and true or false
		Installer.Update()
	end)
	row.value = Secondary(Paragraph(card.body, E.tokens.size.label))
	card.rows[index] = row
	return row
end

function STEP.Refresh(frame)
	local s = Session()
	local a = s and Alt.Start(s)
	if not a then return end
	local width = Width()
	local applied = a.state == "applied"
	local y = 0
	frame.intro:SetText(L["Another character set up EldoUI on this account already. Pick the profile this character should use: the profile stays as it is, and only this character's own parts are set up. Attach keeps a backup first."])
	frame.intro:ClearAllPoints()
	frame.intro:SetPoint("TOPLEFT", 0, -y)
	y = y + math.ceil(frame.intro:GetStringHeight()) + 14
	frame.pickHeader:ClearAllPoints()
	frame.pickHeader:SetPoint("TOPLEFT", 0, -y)
	y = y + math.ceil(frame.pickHeader:GetStringHeight()) + 8
	-- One card per set-up profile.
	local list = Alt.Candidates()
	for index, entry in ipairs(list) do
		local row = frame.rows[index]
		if not row then
			row = Choice(frame.child, width, 52, "", "", function(self)
				if Alt.Pick(self.profile) then Installer.Update() end
			end)
			frame.rows[index] = row
		end
		row.profile = entry.name
		local tag = entry.rule and L["the profile for your class"] or (index == 1 and L["suggested"]) or nil
		row.title:SetText(tag and ("%s  %s"):format(entry.name, Muted(tag)) or entry.name)
		row.desc:SetText(ProfileDesc(entry))
		row:SetWidth(width)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", 0, -y)
		row:SetSelected(entry.name == a.profile and a.roleChoice ~= "other")
		row:SetEnabledLook(not applied)
		row:Show()
		y = y + math.ceil(row:FitHeight()) + 6
	end
	for index = #list + 1, #frame.rows do frame.rows[index]:Hide() end
	y = y + 8
	-- A profile set up for another role.
	local role, detected = Alt.RoleMismatch()
	frame.roleNote:SetShown(role ~= nil)
	for _, choice in ipairs(frame.roleChoices) do choice:SetShown(role ~= nil) end
	if role then
		frame.roleNote:SetText(Warn(L["%s is set up for the %s role, and this character looks like %s."]:format(a.profile, RoleTitle(role), RoleTitle(detected))))
		frame.roleNote:ClearAllPoints()
		frame.roleNote:SetPoint("TOPLEFT", 0, -y)
		y = y + math.ceil(frame.roleNote:GetStringHeight()) + 8
		local texts = {
			attach = { L["Attach anyway"], L["This character uses %s with its %s role layer, like the other characters on it."]:format(a.profile, RoleTitle(role)) },
			copy = { L["Make a copy for %s"]:format(RoleTitle(detected)), L["A new profile %s, a copy with the %s role. %s stays as it is."]:format(Alt.CopyName(a.profile, detected), RoleTitle(detected), a.profile) },
			other = { L["Pick another profile"], L["Choose another profile in the list above."] },
		}
		local gap = 8
		local choiceW = math.floor((width - 2 * gap) / 3)
		local height = 0
		for _, choice in ipairs(frame.roleChoices) do
			local text = texts[choice.choiceKey]
			choice.title:SetText(text[1])
			choice.desc:SetText(text[2])
			choice:SetWidth(choiceW)
			choice.minHeight = 64
			height = math.max(height, choice:FitHeight())
		end
		for index, choice in ipairs(frame.roleChoices) do
			choice.minHeight = height
			choice:FitHeight()
			choice:ClearAllPoints()
			choice:SetPoint("TOPLEFT", (index - 1) * (choiceW + gap), -y)
			choice:SetSelected(a.roleChoice == choice.choiceKey)
			choice:SetEnabledLook(not applied)
		end
		y = y + height + 14
	end
	-- The character to copy from.
	frame.sourceLabel:ClearAllPoints()
	frame.sourceLabel:SetPoint("TOPLEFT", 0, -y)
	y = y + math.ceil(frame.sourceLabel:GetStringHeight()) + 6
	local scale = E:TextScale()
	frame.source:SetSize(math.min(width, math.floor(300 * scale + 0.5)), math.max(E.tokens.height.button, math.ceil(E.tokens.size.label * scale + 8)))
	frame.source:ClearAllPoints()
	frame.source:SetPoint("TOPLEFT", 0, -y)
	frame.source:Refresh()
	frame.source:SetEnabled(not applied)
	y = y + math.ceil(frame.source:GetHeight()) + 6
	local _, fromRecord = Alt.PartsFrom(a.source)
	local sourceName = a.source ~= "" and CharName(a.source) or nil
	if fromRecord then
		frame.sourceNote:SetText(L["Checked below: what %s picked in its own setup."]:format(HL(sourceName)))
	elseif sourceName then
		frame.sourceNote:SetText(L["%s has no saved setup yet, so EldoUI's suggestions are checked below."]:format(HL(sourceName)))
	else
		frame.sourceNote:SetText(L["EldoUI's suggestions are checked below."])
	end
	frame.sourceNote:ClearAllPoints()
	frame.sourceNote:SetPoint("TOPLEFT", 0, -y)
	y = y + math.ceil(frame.sourceNote:GetStringHeight()) + 16
	-- From the profile (unchanged).
	local lines = {}
	for _, line in ipairs(a.profile and Alt.ProfileLines(a.profile) or {}) do
		lines[#lines + 1] = ("%s: %s"):format(Muted(line[1]), line[2])
	end
	local card = frame.profileCard
	card.text:SetText(table.concat(lines, "\n"))
	card:SetBodyHeight(10 + math.ceil(card.text:GetStringHeight()) + 10)
	card:ClearAllPoints()
	card:SetPoint("TOPLEFT", 0, -y)
	y = y + math.ceil(card:GetHeight()) + 16
	-- This character gets.
	local parts = frame.partsCard
	local rows = Alt.Rows()
	local inner = 10
	for index, data in ipairs(rows) do
		local row = PartRow(frame, index)
		row.key = data.key
		row.check:SetLabel(data.label)
		Tooltip(row.check, data.label, data.tip)
		row.check:SetChecked(data.on)
		row.check:SetEnabledLook(data.enabled and not applied)
		row.check:ClearAllPoints()
		row.check:SetPoint("TOPLEFT", 10, -inner)
		row.value:SetText(data.value or "")
		row.value:SetWidth(width - 24 - 28)
		row.value:ClearAllPoints()
		row.value:SetPoint("TOPLEFT", row.check, "BOTTOMLEFT", 28, 0)
		row.check:Show()
		row.value:Show()
		inner = inner + 24 + math.ceil(row.value:GetStringHeight()) + 8
	end
	for index = #rows + 1, #parts.rows do
		parts.rows[index].check:Hide()
		parts.rows[index].value:Hide()
	end
	parts.empty:SetShown(#rows == 0)
	if #rows == 0 then inner = inner + math.ceil(parts.empty:GetStringHeight()) + 10 end
	parts:SetBodyHeight(inner + 2)
	parts:ClearAllPoints()
	parts:SetPoint("TOPLEFT", 0, -y)
	y = y + math.ceil(parts:GetHeight()) + 12
	frame.child:SetHeight(y)
	-- The buttons at the bottom.
	frame.full:SetShown(not applied)
	frame.skipAll:SetShown(not applied and not Marks()[E.charKey])
	local backup = Installer.GetBackup()
	frame.undo:SetShown(backup ~= nil and not applied)
	if backup then
		local when = backup.time and E:ShortDate(backup.time) or "?"
		Tooltip(frame.undo, L["Undo the last setup"], backup.attach and L["Puts this character back on %s, as before the alt setup of %s."]:format(HL(backup.previous or backup.profile), when)
			or L["Puts %s back as it was on %s."]:format(HL(backup.profile), when))
	end
end

function STEP.HasChoice() return Alt.CanAttach() end

function STEP.Summary()
	local a = State()
	if a and a.profile then return L["Profile %s (as it is)"]:format(HL(a.profile)) end
	return L["Alt setup"]
end
