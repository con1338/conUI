-- EldoUI localization.
--
-- Every text a player reads goes through the locale table `E.L`. English is
-- the key, so a missing translation simply shows the English text:
--
--   local L = E.L
--   E:Print(L["Using profile %s."]:format(name))
--   { type = "toggle", key = "x", label = L["Show the clock"], desc = L["..."] }
--
-- Rules for module code (the pattern every module follows once its options
-- are rewritten):
--   * Wrap labels, descriptions, prints and tooltips in L["..."]. Keep the
--     English text short and complete; never build a sentence from pieces
--     (word order differs between languages). Use %s placeholders instead.
--   * Prefer the game's own global strings where one exists (ACCEPT, CANCEL,
--     DELETE, ITEM_LEVEL, DURABILITY, ...): they are already translated.
--   * Never parse chat or tooltip text against English: match the client's
--     own localized format strings (LOOT_ITEM_SELF, ...).
--   * A table built while the file loads runs before the saved language is
--     read, so it keeps its texts English: title = "...", desc = "..." and
--     label = "..." are keys as they are, any other text is Key("...").
--     The code that shows such a text translates it there (L[entry.title],
--     E:Translate(text)). Strings looked up later (prints, pages built at
--     login) follow the language override below.
--
-- Counts use E:Plural(n, "%d item", "%d items"):format(n) (Russian has
-- three forms for whole numbers, Chinese one); search fields compare
-- E:FoldText(text) (case and accents folded, Cyrillic too, CJK as it is).
--
-- Translators keep every %s / %d placeholder and every {token} (Fanfare
-- texts such as "LEVEL {level}!") exactly as they are; only the words
-- around them change.
--
-- Translations: a language registers its table with
--   E:RegisterLocale("deDE", { ["Using profile %s."] = "Profil %s wird verwendet.", ... })
-- or with a function returning that table, so the strings of languages
-- nobody uses are never built. A language comes as a language pack: a
-- load-on-demand addon named EldoUI_Locale_<code>, or one with
-- "## X-EldoUI-Locale: <code>" in its TOC (see E:LocalePacks). Danish ships
-- as EldoUI_Locale_daDK. Only the pack of the chosen language loads, so a
-- player who keeps English never loads a translation. A separate addon
-- named EldoUI_Locales is loaded too when it is installed and the language
-- is not English. A file in EldoUI's own TOC (after this one) can register
-- texts as well, as the Loot Guide's tables for the client language do.
-- tools/locale_keys.py lists every L["..."] key as a template, and
-- `tools/test/run.lua --pseudo` / tools/locale_scan.py find texts that skip L.
--
-- The language is the client's (GetLocale) unless the player picked one on
-- General > EldoUI language (account-wide, takes effect after a reload).
local _, E = ...

local ENGLISH = { enUS = true, enGB = true }
local LOCALES_ADDON = "EldoUI_Locales"

-- Names the language dropdown shows, in the language itself.
E.localeNames = {
	enUS = "English", deDE = "Deutsch", frFR = "Français", esES = "Español (EU)",
	esMX = "Español (AL)", itIT = "Italiano", ptBR = "Português", ruRU = "Русский",
	koKR = "한국어", zhCN = "简体中文", zhTW = "繁體中文", daDK = "Dansk",
}

-- The flag beside each language in the language dropdown: its cell on the
-- Twemoji sheets of the EldoUI_Emoji folder (sheet, then the cell's left and
-- top pixel on the 1024 px sheet; cells are 32 px). Only the picture is
-- read; the emoji list itself does not load for it.
E.localeFlags = {
	enUS = { 2, 448, 864 }, daDK = { 2, 864, 672 }, deDE = { 2, 768, 672 }, frFR = { 2, 416, 704 },
	esES = { 2, 160, 704 }, esMX = { 2, 0, 800 }, itIT = { 2, 544, 736 }, ptBR = { 2, 896, 640 },
	ruRU = { 2, 64, 832 }, koKR = { 2, 928, 736 }, zhCN = { 2, 416, 672 }, zhTW = { 2, 256, 864 },
}
local FLAG_ADDON = "EldoUI_Emoji"
local FLAG_SHEET = "Interface\\AddOns\\EldoUI_Emoji\\Sheets\\emoji%d"
local FLAG_SHEET_SIZE, FLAG_CELL = 1024, 32

-- The flag of a language: the texture path, then its left, right, top and
-- bottom texture coordinates. Nil when the language has no flag or the
-- EldoUI_Emoji folder is not installed; the dropdown then shows names only.
function E:LocaleFlag(code)
	local cell = self.localeFlags[code]
	if not cell or not (C_AddOns and C_AddOns.GetAddOnInfo) then return nil end
	local ok, name, _, _, _, reason = pcall(C_AddOns.GetAddOnInfo, FLAG_ADDON)
	if not ok or not name or reason == "MISSING" then return nil end
	local left, top, size = cell[2] / FLAG_SHEET_SIZE, cell[3] / FLAG_SHEET_SIZE, FLAG_CELL / FLAG_SHEET_SIZE
	return FLAG_SHEET:format(cell[1]), left, left + size, top, top + size
end

local registered = {}  -- code -> table or function returning a table
local active          -- translation table in use, or nil for English
local activeCode = "enUS"
local missing = {}    -- key -> true, filled only while tracking
local tracking = false

local function Resolve(code)
	local entry = registered[code]
	if type(entry) == "function" then
		local ok, result = pcall(entry)
		entry = ok and type(result) == "table" and result or {}
		registered[code] = entry
	end
	return entry
end

-- Texts L has handed out in the current language. Looking one of them up
-- again returns it unchanged, so a text translated by its caller and again
-- where it is shown (mover titles, command help, option rows) stays right.
local produced = {}

-- Every key looked up while recording (for the key check of the test tools).
local recorded

E.L = setmetatable({}, {
	__index = function(_, key)
		if recorded and type(key) == "string" then recorded[key] = true end
		if active then
			if produced[key] then return key end
			local text = active[key]
			-- A plural translation (a table of forms, see E:Plural) read
			-- through L directly gives its "other" form.
			if type(text) == "table" then text = text.other end
			if type(text) == "string" and text ~= "" then
				produced[text] = true
				return text
			end
			if tracking and type(key) == "string" then missing[key] = true end
		end
		return key
	end,
	-- Nothing writes into L; translations come through RegisterLocale.
	__newindex = function() end,
})

-- Add (or extend) a language. Later tables for the same code add keys.
function E:RegisterLocale(code, strings)
	if type(code) ~= "string" or (type(strings) ~= "table" and type(strings) ~= "function") then return end
	local existing = registered[code]
	if type(strings) == "table" and type(existing) == "table" then
		for key, text in pairs(strings) do existing[key] = text end
	elseif type(strings) == "function" and existing ~= nil then
		local previous = existing
		registered[code] = function()
			local base = type(previous) == "function" and previous() or previous
			local extra = strings()
			if type(base) ~= "table" then base = {} end
			for key, text in pairs(type(extra) == "table" and extra or {}) do base[key] = text end
			return base
		end
	else
		registered[code] = strings
	end
	if code == activeCode then active = Resolve(code) end
end

-- The code of the language in use ("enUS" when English).
function E:GetLanguage()
	return activeCode
end

-- A word set into a sentence in lower case ("it would cover the minimap",
-- "New herb node"). German writes nouns with a capital, so there the word
-- keeps its case.
local KEEP_CASE = { deDE = true }
function E:InSentence(text)
	if type(text) ~= "string" or KEEP_CASE[activeCode] then return text end
	return text:lower()
end

-- The decimal mark of the language in use: "," for the languages listed in
-- E.decimalCommas (each language folder adds its own code), "." otherwise.
E.decimalCommas = E.decimalCommas or {}
function E:DecimalMark()
	return self.decimalCommas[activeCode] and "," or "."
end

-- A number text with its decimal point in the language's own mark.
function E:LocalDecimals(text)
	if type(text) ~= "string" or not self.decimalCommas[activeCode] then return text end
	return (text:gsub("(%d)%.(%d)", "%1,%2"))
end

-- A word the game shows too (Yes, Cancel, Bank, Dead): the game's own
-- wording while EldoUI speaks the client's language, else EldoUI's text, so
-- a window never mixes two languages (Danish text with English buttons, or
-- English text with German ones).
--   button:SetText(E:GameText(CANCEL, L["Cancel"]))
function E:GameText(gameText, ownText)
	local client = GetLocale()
	local same = activeCode == client or (ENGLISH[activeCode] and ENGLISH[client])
	if same and type(gameText) == "string" and not (issecretvalue and issecretvalue(gameText)) and gameText ~= "" then
		return gameText
	end
	return ownText
end

-- Language packs: separate (usually load-on-demand) addons that bring one
-- or more languages. A pack is found by its folder name
-- (EldoUI_Locale_<code>, e.g. EldoUI_Locale_daDK) or by a line in its TOC:
--   ## X-EldoUI-Locale: daDK
-- (several codes separated by commas or spaces). Found packs show in the
-- language dropdown before they are loaded; the one for the chosen
-- language loads when the language is set.
local packs              -- code -> addon name, filled on first use

local function AddPack(code, addon)
	if type(code) == "string" and code:match("^%a%a%a%a$") and not ENGLISH[code] and not packs[code] then
		packs[code] = addon
	end
end

local function DiscoverPacks()
	if packs then return packs end
	packs = {}
	local addons = C_AddOns
	if not (addons and addons.GetNumAddOns and addons.GetAddOnInfo) then return packs end
	local okCount, count = pcall(addons.GetNumAddOns)
	if not okCount or type(count) ~= "number" then return packs end
	for index = 1, count do
		-- A pack switched off in the addon list is not offered: picking it
		-- would show English.
		local ok, name, _, _, _, reason = pcall(addons.GetAddOnInfo, index)
		if ok and type(name) == "string" and reason ~= "DISABLED" then
			AddPack(name:match("^EldoUI_Locale_(%a%a%a%a)$"), name)
			local okMeta, codes = pcall(addons.GetAddOnMetadata, index, "X-EldoUI-Locale")
			if okMeta and type(codes) == "string" then
				for code in codes:gmatch("%a%a%a%a") do AddPack(code, name) end
			end
		end
	end
	return packs
end

-- Code -> addon name of every pack found (scans again with `rescan`).
function E:LocalePacks(rescan)
	if rescan then packs = nil end
	return DiscoverPacks()
end

-- Languages the player can pick: English plus every registered one and
-- every installed language pack.
function E:AvailableLanguages()
	local list, seen = { "enUS" }, { enUS = true }
	for code in pairs(registered) do
		if not ENGLISH[code] and not seen[code] then
			list[#list + 1] = code
			seen[code] = true
		end
	end
	for code in pairs(DiscoverPacks()) do
		if not seen[code] then
			list[#list + 1] = code
			seen[code] = true
		end
	end
	table.sort(list, function(a, b) return a == "enUS" or (b ~= "enUS" and a < b) end)
	return list
end

local function LoadAddon(name)
	if C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(name) then return end
	local exists = C_AddOns.DoesAddOnExist and C_AddOns.DoesAddOnExist(name)
	if exists then pcall(C_AddOns.LoadAddOn, name) end
end

local function LoadPack(code)
	if ENGLISH[code] or not (C_AddOns and C_AddOns.LoadAddOn) then return end
	local pack = DiscoverPacks()[code]
	if pack then LoadAddon(pack) end
	LoadAddon(LOCALES_ADDON)
end

-- Switch the table L reads from. "auto" (or nil) = the client language.
function E:SetLanguage(code)
	if code == nil or code == "" or code == "auto" then code = GetLocale() end
	if ENGLISH[code] then code = "enUS" end
	LoadPack(code)
	activeCode = code
	active = code ~= "enUS" and Resolve(code) or nil
	wipe(produced)
end

-- Select lists whose names must never be translated (font, texture and
-- sound names, profile names): Core/Config.lua leaves a table marked with
-- E:RawValues(tbl) as it is. Returns the table.
local RAW = {}
function E:RawValues(values)
	if type(values) == "table" and getmetatable(values) == nil then setmetatable(values, RAW) end
	return values
end
function E:IsRawValues(values)
	return type(values) == "table" and getmetatable(values) == RAW
end

-- For text that was stored in English and is shown later. A text that is
-- no key (already translated, a name, a secret value) comes back as it is.
-- It may get names as well as keys, so it neither records the text for the
-- key check nor lists it as a missing translation.
function E:Translate(text)
	if type(text) ~= "string" or (issecretvalue and issecretvalue(text)) then return text end
	local keepRecorded, keepTracking = recorded, tracking
	recorded, tracking = nil, false
	local out = self.L[text]
	recorded, tracking = keepRecorded, keepTracking
	return out
end

-- A list of entries built while the files load whose texts are English keys
-- (names of professions, factions, groups): after E:TranslateFields(list,
-- "name"), reading entry.name gives the text in the current language, so
-- every reader gets it without translating it itself. Returns the list.
local fieldKeys = setmetatable({}, { __mode = "k" })
local TRANSLATED = {
	__index = function(entry, field)
		local keys = fieldKeys[entry]
		local key = keys and keys[field]
		if key ~= nil then return E:Translate(key) end
	end,
}
function E:TranslateFields(list, ...)
	for _, entry in pairs(list) do
		if type(entry) == "table" and getmetatable(entry) == nil then
			local keys = {}
			for index = 1, select("#", ...) do
				local field = select(index, ...)
				keys[field] = rawget(entry, field)
				entry[field] = nil
			end
			fieldKeys[entry] = keys
			setmetatable(entry, TRANSLATED)
		end
	end
	return list
end

-- The same for a table of texts by key (state or kind names):
-- after E:TranslateValues(map), map[key] gives the text in the current
-- language. Read it by key; pairs() no longer lists the texts.
function E:TranslateValues(map)
	if type(map) ~= "table" or getmetatable(map) ~= nil then return map end
	local keys = {}
	for key, text in pairs(map) do keys[key] = text end
	for key in pairs(keys) do map[key] = nil end
	return setmetatable(map, { __index = function(_, key) return E:Translate(keys[key]) end })
end

-- A text in a table built while the files load, before the saved language
-- is read: it stays English, and tools/locale_keys.py lists it as a key.
-- The code that shows it translates it then, with L[text] or E:Translate.
--   local Key = E.Key
--   local SORTS = { { "name", Key("Name") }, { "level", Key("Level") } }
--   button:SetText(L[sort[2]])
function E.Key(text)
	return text
end

-- Key binding names and headers that modules add while the files load,
-- kept in English (with what fills a %d or %s: a value, or a function that
-- returns the text in the language shown) and named again, in the language
-- shown, whenever the binding names are set:
--   E:NameBinding("BINDING_NAME_ELDOUI_FISHING_TOGGLE", E.Key("Fishing mode on or off"))
local moduleBindings = {}
local function NameBinding(name, entry)
	local text = E.L[entry[1]]
	if #entry > 1 then
		local args = {}
		for index = 2, #entry do
			local value = entry[index]
			if type(value) == "function" then value = value() end
			args[index - 1] = value
		end
		text = text:format(unpack(args))
	end
	_G[name] = text
end
function E:NameBinding(name, text, ...)
	moduleBindings[name] = { text, ... }
	NameBinding(name, moduleBindings[name])
end
function E:NameModuleBindings()
	for name, entry in pairs(moduleBindings) do NameBinding(name, entry) end
end

-- Missing translations: record keys looked up without a translation
-- (debug; /eui locale missing).
function E:TrackMissingTranslations(on)
	tracking = on and true or false
	if not tracking then wipe(missing) end
end

function E:MissingTranslations()
	local list = {}
	for key in pairs(missing) do list[#list + 1] = key end
	table.sort(list)
	return list
end

-- One line for /eui diag and bug reports.
function E:LocaleReport()
	local count = 0
	if active then for _ in pairs(active) do count = count + 1 end end
	return ("Language %s (client %s), %d translated strings%s"):format(activeCode, tostring(GetLocale()), count,
		tracking and (", %d missing so far"):format(#self:MissingTranslations()) or "")
end

-- Plurals. Languages count differently: English has one form for 1
-- and one for the rest, Russian has four (1 предмет, 2 предмета,
-- 5 предметов, 1,5 предмета), Chinese and Korean have one. Code passes
-- both English forms and formats the result itself:
--   E:Plural(count, "%d item", "%d items"):format(count)
-- The English plural ("%d items") is the key. Its translation is a plain
-- string (one form for every number) or a table of CLDR forms:
--   ["%d items"] = { one = "%d предмет", few = "%d предмета", many = "%d предметов", other = "%d предмета" },
-- A translation of the singular key ("%d item") is used for "one".
-- The rules below are the CLDR cardinal rules of the languages EldoUI
-- offers; another language uses C_Intl.SelectPlural when it is the
-- client's own, else the English rule.
local PLURAL_RULES = {}
local function OneIfOne(n) return n == 1 and "one" or "other" end
local function OneIfBelowTwo(n) return n < 2 and "one" or "other" end
local function OnlyOther() return "other" end
local function Russian(n)
	if n ~= math.floor(n) then return "other" end
	local ten, hundred = n % 10, n % 100
	if ten == 1 and hundred ~= 11 then return "one" end
	if ten >= 2 and ten <= 4 and (hundred < 12 or hundred > 14) then return "few" end
	return "many"
end
for _, code in ipairs({ "enUS", "enGB", "deDE", "esES", "esMX", "itIT", "daDK" }) do PLURAL_RULES[code] = OneIfOne end
PLURAL_RULES.frFR, PLURAL_RULES.ptBR = OneIfBelowTwo, OneIfBelowTwo
PLURAL_RULES.ruRU = Russian
PLURAL_RULES.koKR, PLURAL_RULES.zhCN, PLURAL_RULES.zhTW = OnlyOther, OnlyOther, OnlyOther

-- The CLDR plural form ("one", "few", "many", "other", ...) of a count in
-- a language (default: the language in use).
function E:PluralCategory(n, code)
	code = code or activeCode
	if type(n) ~= "number" or (issecretvalue and issecretvalue(n)) then return "other" end
	n = math.abs(n)
	local rule = PLURAL_RULES[code]
	if rule then return rule(n) end
	if C_Intl and C_Intl.SelectPlural and code == GetLocale() then
		local cardinal = Enum and Enum.PluralType and Enum.PluralType.Cardinal or 0
		local ok, form = pcall(C_Intl.SelectPlural, n, cardinal)
		if ok and type(form) == "string" and form ~= "" then return form end
	end
	return OneIfOne(n)
end

-- The text for `n` things in the language in use (format it yourself).
function E:Plural(n, one, other)
	if recorded then recorded[other] = true end
	local form = self:PluralCategory(n)
	if active then
		local entry = active[other]
		if type(entry) == "table" then
			local text = entry[form]
			if type(text) ~= "string" or text == "" then text = entry.other end
			if type(text) == "string" and text ~= "" then return text end
		end
		local single = active[one]
		if form == "one" and type(single) == "string" and single ~= "" then return single end
		if type(entry) == "string" and entry ~= "" then return entry end
	end
	-- English, or not translated yet: the English rule.
	return self:PluralCategory(n, "enUS") == "one" and one or other
end

-- Search folding: the key search fields compare.
--   * ASCII and Latin-1 lower case, accents removed ("Hache à deux mains"
--     matches "hache a deux"; ß -> ss);
--   * Cyrillic lower case: А-Я, Ѐ-Џ, and Ё/ё fold to е (Russian players
--     type е for ё);
--   * every other script (Chinese, Korean, ...) has no case and stays as
--     it is, byte for byte, so folded text is still valid UTF-8;
--   * punctuation becomes one space, apostrophes go away.
local LATIN = {}
do
	local function Map(from, to, value)
		for byte = from, to do LATIN[string.char(byte)] = value end
	end
	Map(0x80, 0x85, "a") Map(0x86, 0x86, "ae") Map(0x87, 0x87, "c") Map(0x88, 0x8B, "e") Map(0x8C, 0x8F, "i")
	Map(0x90, 0x90, "d") Map(0x91, 0x91, "n") Map(0x92, 0x96, "o") Map(0x98, 0x98, "o") Map(0x99, 0x9C, "u")
	Map(0x9D, 0x9D, "y") Map(0x9E, 0x9E, "th") Map(0x9F, 0x9F, "ss")
	Map(0xA0, 0xA5, "a") Map(0xA6, 0xA6, "ae") Map(0xA7, 0xA7, "c") Map(0xA8, 0xAB, "e") Map(0xAC, 0xAF, "i")
	Map(0xB0, 0xB0, "d") Map(0xB1, 0xB1, "n") Map(0xB2, 0xB6, "o") Map(0xB8, 0xB8, "o") Map(0xB9, 0xBC, "u")
	Map(0xBD, 0xBD, "y") Map(0xBE, 0xBE, "th") Map(0xBF, 0xBF, "y")
end

-- Cyrillic capitals after the 0xD0 lead byte: U+0400-040F (D0 80-8F) ->
-- U+0450-045F (D1 90-9F), U+0410-041F (D0 90-9F) -> U+0430-043F (D0 B0-BF),
-- U+0420-042F (D0 A0-AF) -> U+0440-044F (D1 80-8F); Ё -> е.
local function Cyrillic(second)
	local byte = second:byte()
	if byte == 0x81 then return "\208\181" end
	if byte <= 0x8F then return "\209" .. string.char(byte + 0x10) end
	if byte <= 0x9F then return "\208" .. string.char(byte + 0x20) end
	if byte <= 0xAF then return "\209" .. string.char(byte - 0x20) end
	return "\208" .. second
end

function E:FoldText(text)
	if type(text) ~= "string" or (issecretvalue and issecretvalue(text)) or text == "" then return "" end
	-- Plain ASCII (most names on English clients) skips the UTF-8 passes.
	if text:find("[\128-\255]") then
		text = text:gsub("\226\128[\152\153]", "") -- ‘ ’
		text = text:gsub("\195([\128-\191])", function(second) return LATIN[second] or ("\195" .. second) end)
		text = text:gsub("\208([\128-\191])", Cyrillic)
		text = text:gsub("\209\145", "\208\181") -- ё -> е
	end
	text = text:lower()
	text = text:gsub("['`]", "")
	text = text:gsub("[%p%s]+", " ")
	return strtrim(text)
end

-- Captions in capitals in every language. string.upper only changes
-- A to Z, so "Demnächst" came out "DEMNäCHST" and Russian stayed lower
-- case. This also capitalizes Latin-1 (à-þ to À-Þ, ÿ to Ÿ, ß to SS) and
-- Cyrillic (а-я to А-Я, ѐ-џ to Ѐ-Џ); scripts without case (Chinese, Korean)
-- stay as they are. Color, texture, link and atlas codes, and format
-- placeholders (%s, %d), are kept as written.
local CAPTION_CODES = {
	"^|c%x%x%x%x%x%x%x%x", "^|r", "^|n", "^||", "^|T.-|t", "^|A.-|a", "^|H.-|h", "^|K.-|k",
	"^%%%%", "^%%[%-%+ #0]*%d*%.?%d*%a",
}

local function UpperPlain(text)
	text = text:upper()
	text = text:gsub("\195\159", "SS") -- ß
	text = text:gsub("\195\191", "\197\184") -- ÿ -> Ÿ
	text = text:gsub("\195([\160-\190])", function(second)
		if second == "\183" then return "\195\183" end -- ÷ has no capital
		return "\195" .. string.char(second:byte() - 0x20)
	end)
	text = text:gsub("\208([\176-\191])", function(second) return "\208" .. string.char(second:byte() - 0x20) end) -- а-п
	text = text:gsub("\209([\128-\159])", function(second)
		local byte = second:byte()
		if byte <= 0x8F then return "\208" .. string.char(byte + 0x20) end -- р-я
		return "\208" .. string.char(byte - 0x10) -- ѐ-џ
	end)
	return text
end

function E:CaptionText(text)
	if type(text) ~= "string" or (issecretvalue and issecretvalue(text)) then return text end
	-- A caption may come as an English key from a table built at load time.
	text = self:Translate(text)
	local out, pos, length = {}, 1, #text
	while pos <= length do
		local stop
		for _, pattern in ipairs(CAPTION_CODES) do
			local first, last = text:find(pattern, pos)
			if first then
				stop = last
				break
			end
		end
		if stop then
			out[#out + 1] = text:sub(pos, stop)
		else
			stop = (text:find("[|%%]", pos + 1) or (length + 1)) - 1
			out[#out + 1] = UpperPlain(text:sub(pos, stop))
		end
		pos = stop + 1
	end
	return table.concat(out)
end

-- Key recording for the key check: every key looked up through L or
-- E:Plural between the two calls, in any language.
function E:RecordLocaleKeys(on)
	recorded = on and {} or nil
end

function E:RecordedLocaleKeys()
	local list = {}
	for key in pairs(recorded or {}) do list[#list + 1] = key end
	table.sort(list)
	return list
end

-- Client language until the saved choice is read (E:InitializeDatabase).
E:SetLanguage(GetLocale())

-- /eui locale [track | missing]: language info, and the missing-translation
-- report for translators (also summed up in /eui diag).
local commandOwner = {}
E:RegisterEvent("PLAYER_LOGIN", function()
	E:UnregisterEvent("PLAYER_LOGIN", commandOwner)
	if not E.AddCommand then return end
	E:AddCommand("locale", "[track | missing]  language info; record and list texts that have no translation yet", function(arg)
		arg = strtrim(arg or ""):lower()
		if arg == "track" then
			E:TrackMissingTranslations(not tracking)
			E:Print(tracking and E.L["Recording texts without a translation. Open the pages you want to check, then type /eui locale missing."]
				or E.L["Stopped recording missing translations."])
		elseif arg == "missing" then
			local list = E:MissingTranslations()
			if #list == 0 then
				E:Print(tracking and E.L["No missing translations recorded so far."] or E.L["Type /eui locale track first, then open the pages you want to check."])
			elseif E.ShowCopyBox then
				E:ShowCopyBox(E.L["Missing translations"], E.L["Texts shown without a translation, one per line, ready for a translation file."], table.concat(list, "\n"))
			end
		else
			E:Print(E:LocaleReport())
		end
	end, "Troubleshooting")
end, commandOwner, "modules")
