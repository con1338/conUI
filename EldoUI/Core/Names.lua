-- EldoUI character names: Forever characters have a surname. One
-- "Name format" choice (as the game shows it / first / last / first and
-- last) for every EldoUI text that draws a character's name, plus a
-- per-module override for modules that register as name users. The
-- settings live in the profile's General settings (E.db.general.names) and
-- the rows sit on the General page.
--
--   E:NameParts(unit, shown)          first name, surname (or nil); with
--                                     `shown`, your own surname only when
--                                     the game shows it
--   E:FormatName(first, last, mode)   the text for a mode (cached)
--   E:DisplayName(unit, key, length)  a unit's name in the format of `key`
--                                     (a registered user, or nil for the
--                                     general setting), cut to `length`
--                                     letters after formatting
--   E:NameFormat(key)                 the mode in effect for `key`
--   E:FormatNameString(name, key)     a name given as text, in the format of `key`
--                                     ("First Surname-Realm", friends lists)
--   E:RegisterNameFormatUser(key, { title, desc, order, default,
--                                   refresh = function() end })
--                                     a module that draws names: it gets an
--                                     override row (default "general", or
--                                     `default`, a mode) and `refresh` runs
--                                     when either changes
--   E:RefreshNames()                  tags re-render, every user redraws
--   E:NameOptionRows()                the rows for the General page
--   E:SetNameAliasProvider(fn)        one provider (Streamer Mode)
--                                     that may give a unit another name:
--                                     fn(unit, key) -> text or nil (key: the
--                                     name user drawing it, or nil)
--   E:NameAlias(unit, key)            the provider's text for a unit, or nil
--   E:UnitNameRealm(unit, full)       name without surname, realm or nil
--   E:UnitNameKey(unit, full)         "Name" or "Name-Realm", one key per player
--   E:UnitWhisperName(unit)           the name a whisper to the unit goes to
--   E:IsMe(name)                      a sender, link or roster name is you
--
-- The tag engine (Core/Tags.lua) draws [name] through E:DisplayName with
-- the name user the text was bound for (E:BindTag's 4th argument), so a
-- module's override reaches every [name] in its texts.
--
-- Names come from UnitName: on Forever its second value is the surname.
-- Your own surname follows the game's "show surname" setting
-- (C_PlayerInfo.ShouldDisplaySurname). A secret name (instances, enemies)
-- is returned as it came: never split, cut or joined.
-- Written from scratch for EldoUI.
local _, E = ...
local L = E.L

local Key = E.Key
-- Secret test first: comparing a secret, even with nil, errors in the
-- client. E:IsSecret is in Core/Safe.lua.
local Secret = E.Secret

E.NAME_MODES = {
	blizzard = Key("As the game shows it"),
	first = Key("First name"),
	last = Key("Surname (first name if none)"),
	full = Key("First name and surname"),
}
local NAME_MODES = E.NAME_MODES

E.defaults.general.names = {
	format = "blizzard", -- blizzard | first | last | full
	modules = {},        -- [registered user] = "general" or a mode
}

local nameUsers, nameUserOrder = {}, {}
local nameCache, nameCacheSize = {}, 0

local function Separator()
	local consts = Constants and Constants.CharacterNameSeparatorConsts
	return consts and consts.CHARACTERNAME_SURNAME_SEPARATOR or " "
end

-- Older profiles kept these under Quality of Life; move them once.
local function Migrate(names)
	local modules = E.db.modules
	local qol = type(modules) == "table" and rawget(modules, "QoL")
	local old = type(qol) == "table" and rawget(qol, "names")
	if type(old) ~= "table" then return end
	if NAME_MODES[old.format] and old.format ~= "blizzard" and names.format == "blizzard" then names.format = old.format end
	if type(old.modules) == "table" then
		for key, value in pairs(old.modules) do
			if value ~= "general" and (names.modules[key] == nil or names.modules[key] == "general") then
				names.modules[key] = value
			end
		end
	end
	qol.names = nil
end

local function NamesDB()
	local general = E.db and E.db.general
	if type(general) ~= "table" then return nil end
	local names = general.names
	if type(names) ~= "table" then
		names = CopyTable(E.defaults.general.names)
		general.names = names
	end
	if type(names.modules) ~= "table" then names.modules = {} end
	Migrate(names)
	return names
end

-- The override of a user: saved value, else its default.
local function UserMode(db, key)
	local own = db.modules[key]
	if own == nil then
		local info = nameUsers[key]
		own = info and info.default or "general"
	end
	return own
end

-- Your own surname shows only when the game is set to show it.
local function OwnSurnameHidden(unit)
	if not (UnitIsUnit and C_PlayerInfo and C_PlayerInfo.ShouldDisplaySurname) then return false end
	local ok, own = pcall(UnitIsUnit, unit, "player")
	return ok and not Secret(own) and own and not C_PlayerInfo.ShouldDisplaySurname() or false
end

function E:NameFormat(key)
	local db = NamesDB()
	if not db then return "blizzard" end
	if key then
		local own = UserMode(db, key)
		if own ~= "general" and NAME_MODES[own] then return own end
	end
	return NAME_MODES[db.format] and db.format or "blizzard"
end

-- Name aliases: Streamer Mode puts "Party 2" or a chosen alias in
-- place of a real name. Every shown name ([name] and the other name tags,
-- E:DisplayName, E:NameParts with `shown`) asks the provider first. The
-- provider returns its own plain text, never a game value.
local aliasProvider

function E:SetNameAliasProvider(fn)
	aliasProvider = type(fn) == "function" and fn or nil
end

function E:NameAlias(unit, key)
	if not aliasProvider or type(unit) ~= "string" then return nil end
	local ok, alias = pcall(aliasProvider, unit, key)
	if not ok or Secret(alias) or type(alias) ~= "string" or alias == "" then return nil end
	return alias
end

function E:NameParts(unit, shown)
	if not unit then return nil end
	if shown then
		local alias = self:NameAlias(unit)
		if alias then return alias, nil end
		local first, last = self:NameParts(unit)
		if last and OwnSurnameHidden(unit) then last = nil end
		return first, last
	end
	local name, second = UnitName(unit)
	if Secret(name) or type(name) ~= "string" then return name, nil end
	local first, last = name, nil
	if not Secret(second) and type(second) == "string" and second ~= "" and UnitIsPlayer(unit) then last = second end
	-- Some units carry the surname inside the first value.
	if not last and RegionalUniqueNamesEnabled and RegionalUniqueNamesEnabled() then
		local sep = Separator():gsub("%p", "%%%0")
		local a, b = name:match("^(.-)" .. sep .. "(.+)$")
		if a and a ~= "" and b and b ~= "" then first, last = a, b end
	end
	return first, last
end

---------------------------------------------------------------------------
-- Names that identify a player: keys, whispers and "is this
-- me?" checks. On a client with regionally unique names (Forever),
-- UnitName and UnitNameUnmodified return the surname as their second
-- value, not a realm, and the first value of UnitName may hold
-- "First Surname". The game's own menus read it the same way: the first
-- value of UnitNameUnmodified is the name, the second the surname, and a
-- whisper goes to "First Surname". On other clients the second value is
-- the realm (nil on your own realm).
---------------------------------------------------------------------------
local function Plain(value)
	if Secret(value) or type(value) ~= "string" or value == "" then return nil end
	return value
end

-- True when the second value of UnitName is a surname.
local function SurnameClient()
	if type(RegionalUniqueNamesEnabled) ~= "function" then return false end
	local ok, on = pcall(RegionalUniqueNamesEnabled)
	return ok and not Secret(on) and on == true
end
E.SurnameClient = SurnameClient

-- The unmodified name of a unit: first value, second value (both plain
-- strings or nil; nil for a secret name).
local function RawName(unit)
	local name, second
	if type(UnitNameUnmodified) == "function" then name, second = UnitNameUnmodified(unit) end
	if not Plain(name) then name, second = UnitName(unit) end
	return Plain(name), Plain(second)
end

-- A unit's name without the surname, and its realm or nil. With `full`,
-- the realm comes from UnitFullName (also your own realm) as long as that
-- value is not the unit's surname; without it only a realm UnitName gives
-- (another realm on clients without surnames, never on Forever).
function E:UnitNameRealm(unit, full)
	if type(unit) ~= "string" then return nil end
	local name, second = RawName(unit)
	if not name then return nil end
	local surnames = SurnameClient()
	local surname
	if surnames then
		surname = second
		local sep = Separator():gsub("%p", "%%%0")
		local a, b = name:match("^(.-)" .. sep .. "(.+)$")
		if a and a ~= "" and b and b ~= "" then name, surname = a, surname or b end
	end
	local realm
	if full and type(UnitFullName) == "function" then
		local ok, _, r = pcall(UnitFullName, unit)
		r = ok and Plain(r) or nil
		if r and not (surnames and r == surname) then realm = r end
	end
	if not realm and not full and not surnames then realm = second end
	return name, realm
end

-- "Name" or "Name-Realm" for keys that must not split one player in two.
function E:UnitNameKey(unit, full)
	local name, realm = self:UnitNameRealm(unit, full)
	if not name then return nil end
	return realm and (name .. "-" .. realm) or name
end

-- The name a whisper to a unit goes to, as the game's own Whisper button
-- builds it: "First Surname" on Forever, "Name-Realm" elsewhere.
function E:UnitWhisperName(unit)
	if type(unit) ~= "string" then return nil end
	if SurnameClient() then
		local name, surname = RawName(unit)
		if not name then return nil end
		if name:find(Separator(), 1, true) then return name end
		return surname and (name .. Separator() .. surname) or name
	end
	return self:UnitNameKey(unit)
end

-- True when a name (a chat or addon-message sender, a link, a roster
-- name; with or without "-Realm", with or without the surname) is you.
-- Compared with your name without the surname (E:PlayerName), never the
-- display name UnitName may give.
function E:IsMe(name)
	name = Plain(name)
	if not name then return false end
	local short = Plain(name:match("^([^%-]+)")) or name
	local me = Plain(self:PlayerName())
	if not me then return false end
	if short == me then return true end
	if SurnameClient() then
		local base = me:match("^(.-)" .. Separator():gsub("%p", "%%%0") .. ".+$")
		if base and base ~= "" and short == base then return true end
	end
	local _, surname = RawName("player")
	if surname and short == me .. Separator() .. surname then return true end
	local shown = Plain((UnitName("player")))
	return shown ~= nil and short == shown
end

function E:FormatName(first, last, mode)
	if Secret(first) or type(first) == "nil" then return first end
	if Secret(last) then return first end
	mode = NAME_MODES[mode] and mode or "blizzard"
	if not last or last == "" then return first end
	if mode == "first" then return first end
	if mode == "last" then return last end
	local cacheKey = first .. "\001" .. last .. "\001" .. mode
	local text = nameCache[cacheKey]
	if not text then
		text = first .. Separator() .. last
		if nameCacheSize > 500 then
			wipe(nameCache)
			nameCacheSize = 0
		end
		nameCache[cacheKey] = text
		nameCacheSize = nameCacheSize + 1
	end
	return text
end

function E:DisplayName(unit, key, length)
	local alias = self:NameAlias(unit, key)
	if alias then
		if length and length > 0 then alias = self:Utf8Sub(alias, length) end
		return alias
	end
	local first, last = self:NameParts(unit)
	if Secret(first) or type(first) == "nil" then return first end
	local mode = self:NameFormat(key)
	-- "As the game shows it" and "both" hide your own surname when the game does.
	if last and mode ~= "last" and OwnSurnameHidden(unit) then last = nil end
	local text = self:FormatName(first, last, mode)
	if length and length > 0 then text = self:Utf8Sub(text, length) end
	return text
end

function E:RegisterNameFormatUser(key, info)
	assert(type(key) == "string" and key ~= "", "EldoUI:RegisterNameFormatUser(key, info): key must be a string")
	info = info or {}
	info.key = key
	info.order = info.order or 50
	if info.default ~= nil and not NAME_MODES[info.default] then info.default = nil end
	if not nameUsers[key] then table.insert(nameUserOrder, key) end
	nameUsers[key] = info
	-- The override's default, so profiles save only real changes.
	E.defaults.general.names.modules[key] = info.default or "general"
	local db = E.db and NamesDB()
	if db and db.modules[key] == nil then db.modules[key] = info.default or "general" end
	table.sort(nameUserOrder, function(a, b)
		if nameUsers[a].order ~= nameUsers[b].order then return nameUsers[a].order < nameUsers[b].order end
		return a < b
	end)
end

-- After a change: tags re-render and every registered user redraws.
function E:RefreshNames()
	if self.UpdateTags then self:UpdateTags() end
	for _, key in ipairs(nameUserOrder) do
		local refresh = nameUsers[key].refresh
		if refresh then
			local ok, err = pcall(refresh)
			if not ok then geterrorhandler()(err) end
		end
	end
end

-- A name that came as text, not as a unit (friends list, other lists):
-- "First<separator>Surname", maybe with "-Realm" after it. Only a name the
-- separator splits cleanly is changed; anything else (and secret text)
-- comes back as it was. The realm part stays on.
function E:FormatNameString(name, key)
	if type(name) ~= "string" or Secret(name) or name == "" then return name end
	local mode = self:NameFormat(key)
	if mode == "blizzard" then return name end
	local sep = Separator()
	local realm = ""
	if sep ~= "-" then
		local base, suffix = name:match("^(.-)(%-[^%s%-]+)$")
		if base and base ~= "" then name, realm = base, suffix end
	end
	local first, last = name:match("^(.-)" .. sep:gsub("%p", "%%%0") .. "(.+)$")
	if not (first and first ~= "" and last and last ~= "") then return name .. realm end
	return self:FormatName(first, last, mode) .. realm
end

-- Rows for the General page (built at login, after every user registered):
-- the general choice, then one override per registered user. Keys are
-- relative to E.db.general.
function E:NameOptionRows()
	local rows = {
		{ type = "header", label = "Character names" },
		{ type = "select", key = "names.format", label = "Name format", values = NAME_MODES,
			desc = "First name, surname or both for every character name EldoUI draws, and each place below set to \"Use general setting\". Your own surname shows only while the game's surname setting is on." },
	}
	local modes = { general = L["Use general setting"] }
	for key, label in pairs(NAME_MODES) do modes[key] = label end
	for _, key in ipairs(nameUserOrder) do
		local info = nameUsers[key]
		rows[#rows + 1] = { type = "select", key = "names.modules." .. key, label = info.title or key, values = modes,
			desc = info.desc or L["Name format for %s. \"Use general setting\" follows the Name format above."]:format(info.title and L[info.title] or key) }
	end
	return rows
end
