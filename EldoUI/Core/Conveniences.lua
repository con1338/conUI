-- EldoUI conveniences: one list of every helper that acts for the player
-- (repairs, selling gray items, the quest helpers, declining strangers'
-- invites and so on). Each module registers its own rows next to the
-- setting they name, so the list follows the modules. The setup's
-- Convenience step and the Conveniences page under Modules both show it.
-- A row never changes a module's default: every helper stays off until
-- the player ticks it, on the setup step, on the Conveniences page or on
-- its module's own page (the same setting in all three places).
--
--   E:RegisterConvenience({
--       id        = "sellJunk",   -- one word, unique: the setup keeps its tick under it
--       module    = "Merchant",   -- the module whose settings hold it; nil: the profile
--       setting   = "sellJunk",   -- the key in those settings (a dotted path works); a
--                                 -- row whose setting is missing is not listed
--       root      = function() return table end, -- optional, without a module: the
--                                 -- table that holds the setting (default the profile)
--       value     = true,         -- what "on" writes (default true); a function gets the
--                                 -- setup's picks, or nil on the options page
--       off       = false,        -- what "off" writes (default false)
--       on        = function(value) return value == "auto" end, -- optional: whether a
--                                 -- stored value counts as on (default: anything but
--                                 -- nil, false and `off`), for a setting with more choices
--       apply     = function(on) end, -- optional: turns it on or off through the
--                                 -- owner's own call instead of writing the setting
--       label     = the row's text, an English key
--       desc      = its tooltip, an English key: starts with "Acts for you:" and
--                   ends with where to change it later (its module's page)
--       suits     = function() return true end, -- the characters "Recommended for me"
--                                 -- ticks it for (class, level, role); nil: never recommended
--       available = function() return true end, -- optional: listed only when true
--       blocked   = function() return reason end, -- optional: what else it waits for
--                                 -- (grays the Conveniences page switch, named on the setup step)
--       order     = 20,           -- the place in the list
--       group     = "keys",       -- optional: lives on the Keys and spells step, which the
--                                 -- Convenience step only links to
--   })
--   E:Conveniences(all)            the rows this character can use, in order
--                                  (all: also the rows for other classes)
--   E:ConvenienceOn(row)           whether it is on now
--   E:ConvenienceOnValue(row, pick) what turning it on writes
--   E:SetConvenience(row, on, pick) turns it on or off in its module's settings
--   E:ConvenienceOffReason(row, states) why its module can't run it, nil when it can
--   E:ConvenienceBlocked(row)      what else it waits for (row.blocked), nil when nothing
--   E:ConvenienceSuits(row)        whether it suits this character
--   E.ConvenienceRules             shared "suits" rules for the rows
--
-- Presentation and settings only: a row is the module's own switch, and
-- each module keeps its own rules (out of combat, never picks a reward,
-- always asks before buying). Written from scratch for EldoUI.
local _, E = ...

local rows, byId = {}, {}
local sorted

-- Picks the setup keeps next to the ticks: no row may take these names.
local RESERVED = { state = true, set = true, repairMode = true }

---------------------------------------------------------------------------
-- Settings by dotted path ("cinematics.skipSeen")
---------------------------------------------------------------------------
local function GetPath(root, path)
	local value = root
	for part in path:gmatch("[^%.]+") do
		if type(value) ~= "table" then return nil end
		value = value[part]
	end
	return value
end

local function SetPath(root, path, value)
	local parts = {}
	for part in path:gmatch("[^%.]+") do parts[#parts + 1] = part end
	local node = root
	for index = 1, #parts - 1 do
		if type(node[parts[index]]) ~= "table" then node[parts[index]] = {} end
		node = node[parts[index]]
	end
	node[parts[#parts]] = value
end

---------------------------------------------------------------------------
-- Registry
---------------------------------------------------------------------------
function E:RegisterConvenience(info)
	assert(type(info) == "table", "EldoUI:RegisterConvenience(info): info must be a table")
	local id = info.id
	assert(type(id) == "string" and id:match("^[%a][%w]*$"), "EldoUI:RegisterConvenience: id must be one word")
	assert(not RESERVED[id], ("EldoUI:RegisterConvenience: %q is a reserved name"):format(id))
	assert(not byId[id], ("EldoUI:RegisterConvenience: %q is already registered"):format(id))
	assert(type(info.setting) == "string" and (info.module == nil or type(info.module) == "string"),
		"EldoUI:RegisterConvenience: setting is required, module is a module name")
	assert(type(info.label) == "string" and type(info.desc) == "string", "EldoUI:RegisterConvenience: label and desc are required")
	local row = {}
	for key, value in pairs(info) do row[key] = value end
	if row.value == nil then row.value = true end
	if row.off == nil then row.off = false end
	row.order = tonumber(row.order) or 100
	rows[#rows + 1] = row
	byId[id] = row
	sorted = nil
	return row
end

-- A row by its id (nil when no module registered it).
function E:Convenience(id)
	return byId[id]
end

local function ModuleDB(row)
	if not row.module then
		if type(row.root) == "function" then
			local ok, root = pcall(row.root)
			return ok and type(root) == "table" and root or nil, nil
		end
		return E.db, nil
	end
	local module = E.modules and E.modules[row.module]
	return module and module.db, module
end

-- The row's module is loaded (or it needs none) and its setting exists.
local function Present(row)
	if row.module and not (E.modules and E.modules[row.module]) then return false end
	local db = ModuleDB(row)
	return type(db) == "table" and GetPath(db, row.setting) ~= nil
end

local function Available(row)
	if not Present(row) then return false end
	if type(row.available) == "function" then
		local ok, shown = pcall(row.available)
		return ok and shown and true or false
	end
	return true
end

-- The rows this character can use, in order (a row whose module or
-- setting is missing, or that is for another class, is left out). `all`
-- keeps the rows for other classes too.
function E:Conveniences(all)
	if not sorted then
		sorted = {}
		for _, row in ipairs(rows) do sorted[#sorted + 1] = row end
		table.sort(sorted, function(a, b)
			if a.order ~= b.order then return a.order < b.order end
			return a.id < b.id
		end)
	end
	local list = {}
	for _, row in ipairs(sorted) do
		if (all and Present(row)) or Available(row) then list[#list + 1] = row end
	end
	return list
end

---------------------------------------------------------------------------
-- Reading and writing a row's setting
---------------------------------------------------------------------------
-- The saved value of the row's setting.
function E:ConvenienceValue(row)
	local db = ModuleDB(row)
	return db and GetPath(db, row.setting)
end

-- Whether a value of the setting means "on".
function E:ConvenienceValueOn(row, value)
	if type(row.on) == "function" then
		local ok, on = pcall(row.on, value)
		return ok and on and true or false
	end
	return value ~= nil and value ~= false and value ~= row.off
end

function E:ConvenienceOn(row)
	return self:ConvenienceValueOn(row, self:ConvenienceValue(row))
end

-- Whether the module's own default has it on (never, for a row: every
-- helper that acts for the player starts off).
function E:ConvenienceDefaultOn(row)
	local defaults
	if row.module then
		local module = self.modules and self.modules[row.module]
		defaults = module and module.defaults
	elseif not row.root then
		defaults = self.defaults
	end
	return type(defaults) == "table" and self:ConvenienceValueOn(row, GetPath(defaults, row.setting)) or false
end

function E:ConvenienceOnValue(row, pick)
	if type(row.value) == "function" then return row.value(pick) end
	return row.value
end

-- Writes `value` as it is, without a refresh (the setup collects them).
function E:WriteConvenienceValue(row, value)
	local db = ModuleDB(row)
	if not db then return false end
	SetPath(db, row.setting, value)
	return true
end

-- Turns a row on or off in its module's settings; the module applies it
-- out of combat. Nothing is written when it already is that way.
function E:SetConvenience(row, on, pick)
	if type(row) == "string" then row = byId[row] end
	if not row then return false end
	if (on and true or false) == self:ConvenienceOn(row) then return false end
	if row.apply then
		row.apply(on and true or false)
		return true
	end
	local value = on and self:ConvenienceOnValue(row, pick) or row.off
	local _, module = ModuleDB(row)
	if not self:WriteConvenienceValue(row, value) then return false end
	if module then self:RefreshModule(module, true) end
	return true
end

-- Why the row's module can't run it now, as one line for a tooltip or a
-- grayed row (nil while it can). `states` (optional) holds module on/off
-- picks that count instead of the saved switch (the setup's Modules step).
function E:ConvenienceOffReason(row, states)
	local module = row.module and self.modules and self.modules[row.module]
	if not module then return nil end
	local _, conflict = self:GetModuleConflict(module)
	local on
	if type(states) == "table" and states[row.module] ~= nil then
		on = states[row.module] and true or false
	else
		on = module:IsEnabled() and true or false
	end
	if on and not conflict then return nil end
	return self:ModuleOffNote(row.module)
end

-- What else the row waits for (another addon does the job, a Blizzard UI
-- switch is off), from the row's own `blocked`; nil when nothing.
function E:ConvenienceBlocked(row)
	if type(row.blocked) ~= "function" then return nil end
	local ok, reason = pcall(row.blocked)
	return ok and type(reason) == "string" and reason or nil
end

function E:ConvenienceSuits(row)
	if type(row.suits) ~= "function" then return false end
	local ok, suits = pcall(row.suits)
	return ok and suits and true or false
end

---------------------------------------------------------------------------
-- Shared "suits the character" rules
---------------------------------------------------------------------------
local Rules = {}
E.ConvenienceRules = Rules

local function PlayerClass()
	local _, class = UnitClass("player")
	if type(class) ~= "string" or (E.Secret and E.Secret(class)) then return nil end
	return class
end

local function Read(name)
	local fn = rawget(_G, name)
	if type(fn) ~= "function" then return nil end
	local ok, value = pcall(fn)
	return ok and type(value) == "number" and value > 0 and value or nil
end

-- Every character.
function Rules.Everyone()
	return true
end

-- The characters of the classes listed: Rules.Class("HUNTER").
function Rules.Class(...)
	local classes = {}
	for index = 1, select("#", ...) do classes[select(index, ...)] = true end
	return function()
		local class = PlayerClass()
		return class ~= nil and classes[class] == true
	end
end

-- Classes whose spells use reagents a vendor sells (powders, candles,
-- symbols, an ankh, seeds and berries, stones).
Rules.Reagents = Rules.Class("MAGE", "PRIEST", "PALADIN", "SHAMAN", "DRUID", "WARLOCK", "ROGUE")

-- Characters still leveling: below the highest level the game allows.
function Rules.BelowLevelCap()
	local level = UnitLevel("player")
	local cap = Read("GetMaxLevelForPlayerExpansion") or Read("GetMaxPlayerLevel") or 60
	return type(level) == "number" and not (E.Secret and E.Secret(level)) and level > 0 and level < cap
end

---------------------------------------------------------------------------
-- The Conveniences page under Modules: a view over the same rows. Each
-- switch is the module's own setting, so the module page, this page and
-- the setup always agree.
---------------------------------------------------------------------------
local proxy = setmetatable({}, {
	__index = function(_, id)
		local row = byId[id]
		return row and E:ConvenienceOn(row) or false
	end,
	__newindex = function(_, id, on)
		local row = byId[id]
		if row then E:SetConvenience(row, on) end
	end,
})

-- The link under a group: its module's page, or the Keys and spells window.
-- `shown` tells whether any row of the group is listed now.
local function GroupLink(group, shown)
	if group == "keys" then
		return { type = "execute", label = "%s settings", labelFill = "Keys and spells",
			desc = "Opens the Keys and spells window, where these are set too.", hidden = function() return not shown() end,
			func = function() if E.OpenKeysAndSpells then E:OpenKeysAndSpells() end end }
	end
	local module = E.modules[group]
	return { type = "execute", label = "%s settings", labelFill = module and module.title or group,
		desc = "Open the settings of the module that does this.", hidden = function() return not (shown() and module and module.options) end,
		func = function() E:ToggleConfig("module:" .. group, true) end }
end

-- Every registered row gets its switch, hidden while the row is not
-- listed (another class, a module or setting that is missing), so the
-- page follows the character and the modules without being built again.
local function BuildOptions()
	local options = {
		{ type = "description", label = "Every helper that acts for you, in one place. Each switch is the same setting as on its module's own page." },
	}
	E:Conveniences()
	-- One group per module; the Keys and spells rows together, last.
	local list, keys = {}, {}
	for _, row in ipairs(sorted) do
		if row.group == "keys" then keys[#keys + 1] = row else list[#list + 1] = row end
	end
	for _, row in ipairs(keys) do list[#list + 1] = row end
	local index = 1
	while list[index] do
		local first = list[index]
		local group = first.group == "keys" and "keys" or first.module or "keys"
		local members = {}
		while list[index] and (list[index].group == "keys" and "keys" or list[index].module or "keys") == group do
			members[#members + 1] = list[index]
			index = index + 1
		end
		local function Shown()
			for _, row in ipairs(members) do
				if Available(row) then return true end
			end
			return false
		end
		local module = E.modules[group]
		options[#options + 1] = { type = "header", label = group == "keys" and "Keys and spells" or (module and module.title or group),
			hidden = function() return not Shown() end }
		for _, row in ipairs(members) do
			options[#options + 1] = { type = "toggle", key = row.id, label = row.label, desc = row.desc,
				hidden = function() return not Available(row) end,
				disabled = function() return E:ConvenienceOffReason(row) or E:ConvenienceBlocked(row) end }
		end
		options[#options + 1] = GroupLink(group, Shown)
	end
	return options
end

E:RegisterEvent("PLAYER_LOGIN", function()
	if not E.RegisterConfigPage then return end
	local page = E:RegisterConfigPage("conveniences", "Conveniences", nil, function() return proxy end, function() end, 1.85)
	if not page.build then
		page.build = BuildOptions
		page.desc = E.Key("Every helper that acts for you, from repairs to quest helpers. Each stays off until you turn it on.")
		page.defaults = function()
			local defaults = {}
			for _, row in ipairs(E:Conveniences()) do defaults[row.id] = E:ConvenienceDefaultOn(row) end
			return defaults
		end
	end
end, rows, "pages")
-- Shown translated: L["Conveniences"]

---------------------------------------------------------------------------
-- Rows of the Keys and spells step: set there, and only named on the
-- Convenience step. Each is listed once its setting exists.
---------------------------------------------------------------------------
E:RegisterConvenience({ id = "autoRanks", module = "ActionBars", setting = "ranks.auto", group = "keys", order = 900,
	label = "Upgrade spell ranks automatically",
	desc = "Acts for you: when you learn a higher rank of a spell, your buttons with a lower rank get the new one, out of combat." })
-- The key map's choice for a new spell: "offer" (ask, the default), "auto"
-- or "off". Only "auto" acts for the player, so the switch is on for it
-- alone, and turning it off goes back to asking.
E:RegisterConvenience({ id = "newSpellKeys", setting = "keymap.newSpells", group = "keys", order = 910,
	value = "auto", off = "offer", on = function(value) return value == "auto" end,
	label = "Put new spells on their key",
	desc = "Acts for you: a spell you learn goes on an empty button with its key, out of combat." })
-- Fill bars 4 and 5: its own call fills the buttons when it is turned on.
E:RegisterConvenience({ id = "fillBars", setting = "keymap.quietFill", group = "keys", order = 920,
	available = function() return E.SetQuietFill ~= nil and (not E.QuietFillAvailable or E:QuietFillAvailable()) end,
	apply = function(on) E:SetQuietFill(on) end,
	label = "Fill bars 4 and 5",
	desc = "Acts for you: your class's out-of-combat spells (travel, tracking, poisons, pet care) go on the empty buttons of bars 4 and 5, out of combat." })
