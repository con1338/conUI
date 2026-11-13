-- EldoUI import window: one paste box for every kind of layout string
-- (import strings from other UI addons).
--
--   * EldoUI's own share strings ("!EUI1!" and every prefix registered
--     with E:RegisterShareKind, such as "!EUW1!")  handed to Core/Share.lua
--   * EllesmereUI profile strings ("!EUI_")      mapped into a new profile
--   * ElvUI profile strings ("!E2!", "!E1!")     mapped into a new profile
--   * Blizzard Edit Mode layout text             added to Blizzard's Edit Mode
--   * Bundles (UI packs): several of the strings above in one paste, one per
--     line or block, plus strings for other addons. Each part is read on its
--     own and listed; the player ticks the parts EldoUI applies. Strings for
--     other addons are listed with a Copy button and never applied, and
--     parts nobody recognizes are skipped.
--
-- Nothing changes while you paste: the window reads the string, shows what
-- it would change (which keys map to which EldoUI frame or setting, which are
-- ignored and why) and waits for a click. A foreign profile is rebuilt as
-- an EldoUI layout preset for WoW: Forever (frame points, sizes, bar shapes,
-- which frames show and when) and applied either as a NEW profile ("Apply
-- as a new layout") or to the current profile ("Change my current
-- layout"). Both have Undo; applying is refused in combat.
--
-- Decoding uses the game's C_EncodingUtil (raw DEFLATE, Base64, CBOR) plus
-- three small readers written for EldoUI from the format descriptions only:
-- the "print" alphabet decoder, the EllesmereUI serializer and the
-- AceSerializer text format (legacy ElvUI strings). Strings are parsed as
-- data; nothing pasted is ever run as code, and ElvUI's "Table"/plugin export
-- variants (Lua source) are refused.
--
-- Blizzard Edit Mode: the layout text is read with
-- C_EditMode.ConvertStringToLayoutInfo for the preview. "Copy for Edit Mode"
-- hands it to Blizzard's own Import dialog (no Blizzard state touched).
-- "Add to Edit Mode" saves it as a new account layout through C_EditMode,
-- out of combat, and only while Blizzard UI > Edit Mode integration has its
-- Improve switch on. EditModeManagerFrame's tables are never written.
-- Written from scratch for EldoUI; no code from other addons.
local _, E = ...
local ReadAccountRoot = E.ReadAccountRoot
local L = E.L

local Import = {}
E.Import = Import

local MAX_STRING = 2 * 1024 * 1024
local MAX_DEPTH = 40
local Ingress = { plans = setmetatable({}, { __mode = "k" }), layouts = setmetatable({}, { __mode = "k" }) }

function Ingress.Plain(value)
	return not E.Secret(value) and type(value) == "table" and type(getmetatable(value)) == "nil"
end

function Ingress.Data(value, open, depth)
	if E.Secret(value) then return false end
	local kind = type(value)
	if kind == "number" then return value == value and value > -math.huge and value < math.huge end
	if kind ~= "table" then return kind == "nil" or kind == "string" or kind == "boolean" end
	if not Ingress.Plain(value) or open[value] or depth > MAX_DEPTH then return false end
	open[value] = true
	for key, inner in pairs(value) do
		if E.Secret(key) or (type(key) ~= "string" and type(key) ~= "number")
			or not Ingress.Data(key, open, depth + 1) or not Ingress.Data(inner, open, depth + 1) then open[value] = nil; return false end
	end
	open[value] = nil
	return true
end

function Ingress.Context(target)
	if E.Secret(E.Import) or E.Import ~= Import then return nil end
	if E.Secret(target) or (type(target) ~= "nil" and not Ingress.Plain(target)) then return nil end
	local root, profile, name = ReadAccountRoot(), E.db, E.profileName
	local admit, getter, active, loader = E.IsCurrentProfile, E.GetApplyGeneration, E.IsApplyGenerationCurrent, E.LoadDatabase
	if not Ingress.Plain(root) or not Ingress.Plain(profile) or E.Secret(name) or type(name) ~= "string"
		or E.Secret(admit) or type(admit) ~= "function" or E.Secret(getter) or type(getter) ~= "function"
		or E.Secret(active) or type(active) ~= "function" or E.Secret(loader) or type(loader) ~= "function" then return nil end
	local profiles, general = rawget(root, "profiles"), rawget(profile, "general")
	if not Ingress.Plain(profiles) or not Ingress.Plain(general) then return nil end
	-- Expected owner identity is checked before any captured-owner callback.
	if target and (root ~= target.root or profiles ~= target.profiles or profile ~= target.profile or general ~= target.general
		or name ~= target.name or admit ~= target.admit or getter ~= target.getter or active ~= target.active or loader ~= target.loader) then return nil end
	local read, generation = pcall(getter, E, "profile")
	if not read or E.Secret(generation) or type(generation) ~= "number" or generation ~= generation
		or generation < 1 or generation >= math.huge or generation % 1 ~= 0 then return nil end
	if target and (root ~= target.root or profiles ~= target.profiles or profile ~= target.profile or general ~= target.general
		or name ~= target.name or generation ~= target.generation or admit ~= target.admit or getter ~= target.getter
		or active ~= target.active or loader ~= target.loader) then return nil end
	local ok, current = pcall(admit, E, profile, name)
	if not ok or E.Secret(current) or current ~= true then return nil end
	local valid, live = pcall(active, E, generation, "profile")
	if not valid or E.Secret(live) or live ~= true or E.Secret(E.IsCurrentProfile) or E.IsCurrentProfile ~= admit
		or E.Secret(E.GetApplyGeneration) or E.GetApplyGeneration ~= getter or E.Secret(E.IsApplyGenerationCurrent) or E.IsApplyGenerationCurrent ~= active
		or E.Secret(E.LoadDatabase) or E.LoadDatabase ~= loader or E.Secret(ReadAccountRoot()) or ReadAccountRoot() ~= root
		or E.Secret(E.db) or E.db ~= profile or E.Secret(E.profileName) or E.profileName ~= name
		or E.Secret(rawget(root, "profiles")) or rawget(root, "profiles") ~= profiles
		or E.Secret(rawget(profile, "general")) or rawget(profile, "general") ~= general then return nil end
	return target or { root = root, profiles = profiles, profile = profile, general = general, name = name,
		generation = generation, admit = admit, getter = getter, active = active, loader = loader }
end

function Ingress.Source(data, target)
	local predicate = E.IsSupportedProfileData
	if E.Secret(predicate) or type(predicate) ~= "function" then return false end
	local ok, supported = pcall(predicate, E, data)
	return ok and not E.Secret(supported) and supported == true and not E.Secret(E.IsSupportedProfileData)
		and E.IsSupportedProfileData == predicate and Ingress.Context(target) ~= nil
end

local REF_SCALE = 768 / 1440     -- EldoUI's pixel-perfect scale on the 1440p reference screen
local HALF_W, HALF_H = 1280, 720 -- reference screen, half size
local EDGE_MARGIN, EDGE_MARGIN_Y = 60, 30

---------------------------------------------------------------------------
-- Settings (account-wide): EldoUIDB.importOptions, EldoUIDB.importedLayouts
---------------------------------------------------------------------------
local OPTION_DEFAULTS = {
	positions = true,  -- import frame positions as a layout preset
	settings = true,   -- import sizes, fonts and bar layout
	activate = true,   -- make an added Edit Mode layout the active one
}

local function Options()
	EldoUIDB.importOptions = E.ApplyDefaults(EldoUIDB.importOptions or {}, OPTION_DEFAULTS)
	return EldoUIDB.importOptions
end


local function Round(value)
	return math.floor(value + 0.5)
end

local function Clamp(value, low, high)
	if value < low then return low end
	if value > high then return high end
	return value
end

local GetPath = function(root, path) return E.GetPath(root, path) end

---------------------------------------------------------------------------
-- Decoding
---------------------------------------------------------------------------
-- The "print" alphabet: a-z A-Z 0-9 ( ), value 0..63, packed in
-- little-endian 6-bit groups (4 characters = 3 bytes). Not standard Base64.
local PRINT = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789()"
local PRINT_INDEX = {}
for i = 1, #PRINT do PRINT_INDEX[PRINT:byte(i)] = i - 1 end

function Import.DecodeForPrint(text)
	text = text:gsub("[%s%c]", "")
	local out, length, i = {}, #text, 1
	local char = string.char
	while i + 3 <= length do
		local a, b, c, d = PRINT_INDEX[text:byte(i)], PRINT_INDEX[text:byte(i + 1)], PRINT_INDEX[text:byte(i + 2)], PRINT_INDEX[text:byte(i + 3)]
		if not (a and b and c and d) then return nil end
		local v = a + b * 64 + c * 4096 + d * 262144
		out[#out + 1] = char(v % 256, math.floor(v / 256) % 256, math.floor(v / 65536))
		i = i + 4
	end
	local cache, bits = 0, 0
	while i <= length do
		local x = PRINT_INDEX[text:byte(i)]
		if not x then return nil end
		cache = cache + x * 2 ^ bits
		bits = bits + 6
		i = i + 1
	end
	while bits >= 8 do
		out[#out + 1] = char(cache % 256)
		cache = math.floor(cache / 256)
		bits = bits - 8
	end
	return table.concat(out)
end

local function Inflate(bytes)
	local util = C_EncodingUtil
	if not (util and util.DecompressString and Enum.CompressionMethod) then
		error(L["this game client can't unpack compressed strings"])
	end
	local ok, result = pcall(util.DecompressString, bytes, Enum.CompressionMethod.Deflate)
	if not ok or type(result) ~= "string" then error(L["the string is damaged or cut short"]) end
	-- The unpacked text gets the same limit as a pasted string.
	if #result > MAX_STRING then error(L["the string is too long"]) end
	return result
end

local function DecodeBase64(text)
	local util = C_EncodingUtil
	if not (util and util.DecodeBase64) then error(L["this game client can't read Base64 strings"]) end
	local ok, result = pcall(util.DecodeBase64, (text:gsub("[%s%c]", "")))
	if not ok or type(result) ~= "string" then error(L["the string is damaged or cut short"]) end
	return result
end

-- EllesmereUI serializer: s<len>:<bytes>  n<number>;  T  F  N  { ... }.
-- Inside a table the array items come first (untagged), then each hash
-- pair as K <key> <value>.
local function ReadEUI(text, pos, depth)
	local tag = text:sub(pos, pos)
	if tag == "s" then
		local length, after = text:match("^(%d+):()", pos + 1)
		length = tonumber(length)
		if not length then error(L["bad text"]) end
		local finish = after + length - 1
		if finish > #text then error(L["string cut short"]) end
		return text:sub(after, finish), finish + 1
	elseif tag == "n" then
		local number, after = text:match("^([^;]*);()", pos + 1)
		number = tonumber(number)
		if not number then error(L["bad number"]) end
		return number, after
	elseif tag == "T" then
		return true, pos + 1
	elseif tag == "F" then
		return false, pos + 1
	elseif tag == "N" then
		return nil, pos + 1
	elseif tag == "{" then
		if depth > MAX_DEPTH then error(L["nested too deep"]) end
		local result, index = {}, 0
		pos = pos + 1
		while true do
			local inner = text:sub(pos, pos)
			if inner == "}" then break end
			if inner == "" then error(L["table cut short"]) end
			if inner == "K" then
				local key, value
				key, pos = ReadEUI(text, pos + 1, depth + 1)
				if key == nil or type(key) == "table" then error(L["bad key"]) end
				value, pos = ReadEUI(text, pos, depth + 1)
				result[key] = value
			else
				local value
				index = index + 1
				value, pos = ReadEUI(text, pos, depth + 1)
				result[index] = value
			end
		end
		return result, pos + 1
	end
	error(L["unknown tag at %d"]:format(pos))
end

function Import.DeserializeEUI(text)
	local value, pos = ReadEUI(text, 1, 0)
	if pos <= #text then error(L["extra data"]) end
	return value
end

-- AceSerializer text format (legacy ElvUI "!E1!" strings): "^1" header,
-- "^^" end; ^S string, ^N number, ^F<mantissa>^f<exponent> float, ^B / ^b
-- booleans, ^Z nil, ^T ... ^t table of key/value pairs. Strings escape
-- control characters, "^" and "~" with "~".
local function AceUnescape(text)
	return (text:gsub("~(.)", function(c)
		if c == "z" then return "\030" end
		if c == "{" then return "\127" end
		if c == "|" then return "~" end
		if c == "}" then return "^" end
		local byte = c:byte() - 64
		if byte < 0 then return "" end
		return string.char(byte)
	end))
end

local function AceNumber(text)
	if text == "1.#INF" or text == "inf" then return math.huge end
	if text == "-1.#INF" or text == "-inf" then return -math.huge end
	return tonumber(text)
end

function Import.DeserializeAce(text)
	if text:sub(1, 2) ~= "^1" then error(L["not an AceSerializer string"]) end
	local tokens = {}
	for tag, data in text:sub(3):gmatch("%^(.)([^%^]*)") do
		tokens[#tokens + 1] = tag
		tokens[#tokens + 1] = data
	end
	local cursor = 1
	local function Next()
		local tag, data = tokens[cursor], tokens[cursor + 1]
		cursor = cursor + 2
		return tag, data
	end
	local Value
	Value = function(tag, data, depth)
		if tag == "S" then return AceUnescape(data)
		elseif tag == "N" then
			local number = AceNumber(data)
			if not number then error(L["bad number"]) end
			return number
		elseif tag == "F" then
			local expTag, expData = Next()
			if expTag ~= "f" then error(L["bad float"]) end
			local m, x = tonumber(data), tonumber(expData)
			if not (m and x) then error(L["bad float"]) end
			return m * 2 ^ x
		elseif tag == "B" then return true
		elseif tag == "b" then return false
		elseif tag == "Z" then return nil
		elseif tag == "T" then
			if depth > MAX_DEPTH then error(L["nested too deep"]) end
			local result = {}
			while true do
				local keyTag, keyData = Next()
				if keyTag == nil then error(L["table cut short"]) end
				if keyTag == "t" then break end
				local key = Value(keyTag, keyData, depth + 1)
				local valueTag, valueData = Next()
				if valueTag == nil or valueTag == "t" then error(L["table cut short"]) end
				local value = Value(valueTag, valueData, depth + 1)
				if key ~= nil then result[key] = value end
			end
			return result
		end
		error(L["unknown tag %s"]:format(tostring(tag)))
	end
	local tag, data = Next()
	if tag == nil or tag == "^" then error(L["empty string"]) end
	return Value(tag, data, 0)
end

-- The last "::<type>[::<profile key>]" tail ElvUI appends to its data.
local ELV_TYPES = { "profile", "private", "global", "filters", "styleFilters" }
local function SplitElvTail(text)
	local bestStart, bestType, bestKey
	for _, kind in ipairs(ELV_TYPES) do
		local marker = "::" .. kind
		local from = 1
		while true do
			local first, last = text:find(marker, from, true)
			if not first then break end
			local rest = text:sub(last + 1)
			local ok, key = false, nil
			if rest == "" then ok = true
			elseif rest:sub(1, 2) == "::" and not rest:find("::", 3, true) then ok, key = true, rest:sub(3) end
			if ok and (not bestStart or first > bestStart) then bestStart, bestType, bestKey = first, kind, key end
			from = first + 1
		end
	end
	if not bestStart then return nil end
	return text:sub(1, bestStart - 1), bestType, bestKey
end

---------------------------------------------------------------------------
-- Detection and parsing. Each parser returns a "source":
--   { kind, title, data, profileKey?, scale?, note? }   or raises an error.
---------------------------------------------------------------------------
local function ParseEUI(text)
	if text:sub(1, 8) == "!EUICDM_" then error(L["this is an old EllesmereUI cooldown-manager string, which EllesmereUI no longer reads either"]) end
	local bytes = Import.DecodeForPrint(text:sub(6))
	if not bytes then error(L["the string has characters an EllesmereUI string can't have"]) end
	local payload = Import.DeserializeEUI(Inflate(bytes))
	if type(payload) ~= "table" then error(L["the string is damaged"]) end
	if payload.version ~= 3 and payload.version ~= 4 then
		error(L["EllesmereUI string version %s; only versions 3 and 4 can be read"]:format(tostring(payload.version)))
	end
	if payload.type ~= "full" and payload.type ~= "profile" then
		error(L["this is an EllesmereUI %q string, not a profile"]:format(tostring(payload.type)))
	end
	local data = payload.data
	if type(data) ~= "table" then error(L["the string holds no profile"]) end
	local scale = type(data.uiScale) == "number" and data.uiScale > 0 and data.uiScale or nil
	return {
		kind = "eui", title = "EllesmereUI", data = data, scale = scale, version = payload.version,
		client = payload.client, meta = payload.meta,
	}
end

local function ParseElv(text)
	local version = text:sub(1, 4)
	local inflated, data
	if version == "!E2!" then
		inflated = Inflate(DecodeBase64(text:sub(5)))
	else
		local bytes = Import.DecodeForPrint(text:sub(5))
		if not bytes then error(L["the string has characters an ElvUI string can't have"]) end
		inflated = Inflate(bytes)
	end
	local body, kind, key = SplitElvTail(inflated)
	if not body then error(L["the string is damaged (no ElvUI type marker)"]) end
	if kind ~= "profile" then error(L["this is an ElvUI %q export; only profile exports hold a layout"]:format(kind)) end
	if version == "!E2!" then
		local util = C_EncodingUtil
		if not (util and util.DeserializeCBOR) then error(L["this game client can't read CBOR data"]) end
		local ok, result = pcall(util.DeserializeCBOR, body)
		if not ok then error(L["the string is damaged"]) end
		data = result
	else
		data = Import.DeserializeAce(body)
	end
	if type(data) ~= "table" then error(L["the string holds no profile"]) end
	return { kind = "elv", title = "ElvUI", data = data, profileKey = key }
end

local function ParseEditMode(text)
	if not (C_EditMode and C_EditMode.ConvertStringToLayoutInfo) then
		error(L["this game client has no Edit Mode import"])
	end
	local ok, info = pcall(C_EditMode.ConvertStringToLayoutInfo, text)
	if not ok or type(info) ~= "table" then
		error(L["Blizzard's Edit Mode doesn't accept this layout text on this client (it may come from a newer game version)"])
	end
	return { kind = "editmode", title = L["Blizzard Edit Mode"], info = info, text = text }
end

-- What a pasted string is, without decoding it.
function Import.Detect(text)
	if text:sub(1, 6) == "!EUI1!" or text:sub(1, 9) == "-- EldoUI" then return "eldoui" end
	-- Registered share kinds (wishlists, plans, routes: E:RegisterShareKind).
	if E.ShareKindFor and E:ShareKindFor(text) then return "eldoui" end
	if text:sub(1, 5) == "!EUI_" or text:sub(1, 8) == "!EUICDM_" then return "eui" end
	if text:sub(1, 4) == "!E2!" or text:sub(1, 4) == "!E1!" then return "elv" end
	if text:sub(1, 1) == "{" and text:find("::profile", 1, true) then return "elvtable" end
	if text:match("^%d+%s+%d+%s") then return "editmode" end
	return nil
end

---------------------------------------------------------------------------
-- Bundles: one paste holding several strings, one per line or block. A
-- short line like "Details:" or "# Plater" names the string under it.
-- Lines that start no new string belong to the string above (EldoUI's
-- readable export spans many lines).
---------------------------------------------------------------------------
local MAX_PARTS = 20
-- Prefixes of other addons' strings that have a well-known name.
local OTHER_ADDONS = { WA = "WeakAuras", PLATER = "Plater", OMNICD = "OmniCD" }
Import.APPLICABLE = { eldoui = true, eui = true, elv = true, editmode = true }

local function OtherAddon(line)
	local prefix = line:match("^!([%a][%w_]*)[:!]")
	if not prefix then return nil end
	return OTHER_ADDONS[prefix:upper()] or prefix
end

local function LabelLine(line)
	local label = line:match("^#+%s*(.-)%s*$")
	if not label and #line <= 40 and not line:find("^[!%-%d{]") then label = line:match("^(.-):$") end
	if label and label ~= "" and #label <= 40 then return label end
	return nil
end

-- { { kind, text, label, addon } } in paste order.
function Import.SplitBundle(text)
	local parts, label, current = {}, nil, nil
	for line in ((text or "") .. "\n"):gmatch("(.-)\r?\n") do
		local trimmed = strtrim(line)
		local kind = trimmed ~= "" and Import.Detect(trimmed)
		local addon = trimmed ~= "" and not kind and OtherAddon(trimmed)
		if kind or addon then
			if #parts >= MAX_PARTS then break end
			current = { kind = kind or "other", addon = addon or nil, label = label, lines = { trimmed } }
			parts[#parts + 1] = current
			label = nil
		elseif trimmed ~= "" and LabelLine(trimmed) and not (current and current.kind == "eldoui" and #current.lines > 1 and not trimmed:find("^#")) then
			label = LabelLine(trimmed)
			current = nil
		elseif current then
			table.insert(current.lines, line)
		elseif trimmed ~= "" then
			current = { kind = "unknown", label = label, lines = { trimmed } }
			parts[#parts + 1] = current
			label = nil
		end
	end
	for _, part in ipairs(parts) do
		part.text = strtrim(table.concat(part.lines, "\n"))
		part.lines = nil
	end
	return parts
end

local function ParseBundle(text)
	local parts = Import.SplitBundle(text)
	local known = 0
	for _, part in ipairs(parts) do
		if part.kind ~= "unknown" then known = known + 1 end
	end
	if #parts < 2 or known == 0 then return nil end
	for _, part in ipairs(parts) do
		if Import.APPLICABLE[part.kind] then
			part.source, part.error = Import.Parse(part.text)
			part.apply = part.source ~= nil
		end
	end
	return { kind = "bundle", title = L["Bundle"], parts = parts }
end

function Import.Parse(text)
	text = strtrim(text or "")
	if text == "" then return nil, L["Paste a string first."] end
	if #text > MAX_STRING then return nil, L["The string is too long."] end
	if text:find("\n", 1, true) then
		local bundle = ParseBundle(text)
		if bundle then return bundle end
	end
	local kind = Import.Detect(text)
	if kind == "eldoui" then return { kind = "eldoui", title = "EldoUI", text = text } end
	if kind == "elvtable" then
		return nil, L["This is ElvUI's \"Table\" export, which is Lua code. EldoUI never runs pasted code: export the profile again in ElvUI with the normal (compressed) format."]
	end
	if not kind and E.Talents and E.Talents.Calc and E.Talents.Calc.Recognize(text) then
		return nil, L["This is a talent build (a talent calculator link or a talent loadout string). The Talent Planner reads it: paste it in the planner's Import box, or type /eui talents import followed by it."]
	end
	if not kind then
		return nil, L["EldoUI doesn't recognize this string. It reads EldoUI (!EUI1!), EllesmereUI (!EUI_), ElvUI (!E1!, !E2!) and Blizzard Edit Mode layout strings."]
	end
	local parser = kind == "eui" and ParseEUI or kind == "elv" and ParseElv or ParseEditMode
	local ok, result = pcall(parser, text)
	if ok then return result end
	local message = tostring(result):gsub("^.-:%d+: ", "")
	return nil, L["Can't read this string: %s."]:format(message)
end

---------------------------------------------------------------------------
-- Mapping a foreign profile to an EldoUI plan
--   plan.points   = { [mover] = { point, "UIParent", relPoint, x, y } }
--   plan.settings = { { module, key, value, from, old } }
--   plan.mapped / plan.ignored / plan.notes = report lines
---------------------------------------------------------------------------
local function ClampPoint(point, relPoint, x, y)
	if relPoint == "CENTER" then
		x = Clamp(x, -HALF_W + EDGE_MARGIN, HALF_W - EDGE_MARGIN)
		y = Clamp(y, -HALF_H + EDGE_MARGIN_Y, HALF_H - EDGE_MARGIN_Y)
	else
		x = Clamp(x, -2 * HALF_W + EDGE_MARGIN, 2 * HALF_W - EDGE_MARGIN)
		y = Clamp(y, -2 * HALF_H + EDGE_MARGIN_Y, 2 * HALF_H - EDGE_MARGIN_Y)
	end
	return { point, "UIParent", relPoint, Round(x), Round(y) }
end

local VALID_POINT = {
	TOPLEFT = true, TOP = true, TOPRIGHT = true, LEFT = true, CENTER = true,
	RIGHT = true, BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
}

-- An EllesmereUI position: { point, relPoint, x, y } as named fields or a list.
local function ReadPosition(pos)
	if type(pos) ~= "table" then return nil end
	local point = pos.point or pos[1]
	local relPoint = pos.relPoint or pos[2] or point
	local x, y = pos.x or pos[3], pos.y or pos[4]
	if type(x) ~= "number" or type(y) ~= "number" then return nil end
	point = type(point) == "string" and point:upper() or "CENTER"
	relPoint = type(relPoint) == "string" and relPoint:upper() or point
	if not VALID_POINT[point] or not VALID_POINT[relPoint] then return nil end
	return point, relPoint, x, y
end

local function MoverTitle(name)
	local mover = E.movers and E.movers[name]
	if mover and mover.title then return mover.title end
	return (name:gsub("^EldoUI_", ""))
end

local function MoverSize(name)
	local mover = E.movers and E.movers[name]
	if not (mover and mover.GetWidth) then return nil end
	local width, height = mover:GetWidth(), mover:GetHeight()
	if type(width) ~= "number" or type(height) ~= "number" or width <= 0 or height <= 0 then return nil end
	return width, height
end

-- A position in words: "bottom of the screen, 210 left and 180 up".
local function Corner(point)
	local names = {
		TOPLEFT = L["top left"], TOP = L["top"], TOPRIGHT = L["top right"], LEFT = L["left"], CENTER = L["center"],
		RIGHT = L["right"], BOTTOMLEFT = L["bottom left"], BOTTOM = L["bottom"], BOTTOMRIGHT = L["bottom right"],
	}
	return names[point] or names.CENTER
end

local function FormatPoint(p)
	local point, relPoint, x, y = p[1], p[3], p[4] or 0, p[5] or 0
	local where
	if p[2] ~= "UIParent" then
		local target = type(p[2]) == "string" and p[2]:match("^(.+)Mover$") or p[2]
		where = L["its %s at the %s of %s"]:format(Corner(point), Corner(relPoint), L[MoverTitle(target)])
	elseif point == relPoint then
		where = L["%s of the screen"]:format(Corner(point))
	else
		where = L["its %s at the %s of the screen"]:format(Corner(point), Corner(relPoint))
	end
	local moves = {}
	if x < 0 then moves[#moves + 1] = L["%d left"]:format(-x) end -- no-plural: a distance
	if x > 0 then moves[#moves + 1] = L["%d right"]:format(x) end -- no-plural: a distance
	if y > 0 then moves[#moves + 1] = L["%d up"]:format(y) end -- no-plural: a distance
	if y < 0 then moves[#moves + 1] = L["%d down"]:format(-y) end -- no-plural: a distance
	if #moves == 0 then return where end
	return ("%s, %s"):format(where, table.concat(moves, L[" and "]))
end

-- The name another UI shows for one of its frames: the title in the import
-- map, else its key made readable ("ElvUF_TotemBarMover" -> "Totem Bar").
local function SourceTitle(key, title)
	if title then return L[title] end
	local name = tostring(key or ""):gsub("^ElvUF_", ""):gsub("^ElvUI_?", ""):gsub("Mover$", "")
	name = name:gsub("_", " "):gsub("(%l)(%u)", "%1 %2"):gsub("^%l", string.upper)
	return name
end

-- Range of a module option, from its declarative options table.
local function OptionRange(moduleName, key)
	local module = E.modules and E.modules[moduleName]
	local options = module and module.options
	if type(options) == "function" then return nil end
	for _, option in ipairs(type(options) == "table" and options or {}) do
		if option.key == key and option.type == "range" then return option.min, option.max end
	end
end

local function NormalizeFont(name)
	return (tostring(name or ""):lower():gsub("%b()", ""):gsub("[^%w]", ""))
end

local function MatchFont(name)
	local fonts = E.media and E.media.fonts
	if type(name) ~= "string" or type(fonts) ~= "table" then return nil end
	local wanted = NormalizeFont(name)
	if wanted == "" then return nil end
	for key in pairs(fonts) do
		if NormalizeFont(key) == wanted then return key end
	end
	for key in pairs(fonts) do
		local have = NormalizeFont(key)
		if have ~= "" and (wanted:find(have, 1, true) or have:find(wanted, 1, true)) then return key end
	end
end

local function CurrentSetting(moduleName, key)
	if moduleName == "general" then return E.db and GetPath(E.db.general, key) end
	local module = E.modules and E.modules[moduleName]
	return module and module.db and GetPath(module.db, key)
end

local function NewPlan(source, factor)
	return {
		source = source, factor = factor, points = {}, settings = {}, hidden = {}, shown = {},
		mapped = {}, ignored = {}, notes = {}, used = {},
	}
end

local function AddPoint(plan, mover, point, from)
	if plan.points[mover] then return end
	plan.points[mover] = point
	local line = L["%s to %s: %s"]:format(from, L[MoverTitle(mover)], FormatPoint(point))
	if E.movers and not E.movers[mover] then line = line .. " " .. E:TextHex("secondary") .. L["(frame not active now)"] .. "|r" end
	table.insert(plan.mapped, line)
end

local function ModuleTitle(moduleName)
	if moduleName == "general" then return L["General"] end
	local module = E.modules and E.modules[moduleName]
	return module and module.title and L[module.title] or moduleName
end

local DIRECTION_WORDS = { UP = "up", DOWN = "down", LEFT = "left", RIGHT = "right", AUTO = "automatic" }

local function ShowValue(value)
	if value == true then return L["on"] end
	if value == false then return L["off"] end
	if DIRECTION_WORDS[value] then return L[DIRECTION_WORDS[value]] end
	return tostring(value)
end

-- One EldoUI setting for the plan. `line` is the preview line: nil writes
-- "<title>: <value>", false writes none (the caller sums several up).
local function AddSetting(plan, moduleName, key, value, title, line)
	if moduleName ~= "general" and not (E.modules and E.modules[moduleName]) then
		table.insert(plan.ignored, L["%s: the %s module isn't installed"]:format(title, moduleName))
		return false
	end
	local old = CurrentSetting(moduleName, key)
	table.insert(plan.settings, { module = moduleName, key = key, value = value, from = title, old = old })
	if line == false then return true end
	if line == nil then
		line = L["%s: %s"]:format(title, ShowValue(value))
		if type(value) ~= "table" and old ~= nil and old ~= value then
			line = line .. " " .. E:TextHex("secondary") .. L["(now %s)"]:format(ShowValue(old)) .. "|r"
		end
	end
	table.insert(plan.mapped, line)
	return true
end

-- A frame the imported layout switches off (Core/Layout.lua `hidden`).
-- `line` replaces the "off" line (an action bar only steps out of sight).
local function AddHidden(plan, mover, title, line)
	if plan.hidden[mover] then return end
	plan.hidden[mover] = true
	table.insert(plan.mapped, line or L["%s: off"]:format(title))
end

-- One entry of a settings map applied to `data`.
local function MapSetting(plan, entry, data)
	local value
	if entry.get then value = entry.get(data) else value = GetPath(data, entry.path) end
	if value == nil then return end
	local from = entry.from or entry.path
	plan.used[from] = true
	local title = entry.title and L[entry.title]
	if entry.module ~= "general" and not (E.modules and E.modules[entry.module]) then
		table.insert(plan.ignored, L["%s: the %s module isn't installed"]:format(title or from, entry.module))
		return
	end
	local kind = entry.kind
	if kind == "size" then
		if type(value) ~= "number" then return end
		-- 0 is "the other UI's default size" unless the setting says otherwise.
		if value <= 0 and not entry.zero then return end
		value = Round(value * plan.factor)
	elseif kind == "number" then
		if type(value) ~= "number" then return end
		-- Below the option's range means a relative or "default" value.
		if value <= 0 and not entry.zero and entry.min and entry.min > 0 then return end
		value = Round(value)
	elseif kind == "bool" then
		value = value == true
	elseif kind == "font" then
		-- "__..." names are the other UI's own choices ("the global font").
		if type(value) == "string" and value:find("^__") then
			table.insert(plan.ignored, L["%s: the other UI's own font setting; EldoUI keeps its font"]:format(title or from))
			return
		end
		local font = MatchFont(value)
		if not font then
			table.insert(plan.ignored, L["%s: font %q isn't one of EldoUI's fonts"]:format(title or from, tostring(value)))
			return
		end
		value = font
	elseif type(value) ~= "string" then
		return
	end
	if type(value) == "number" then
		local low, high = entry.min, entry.max
		if not low then low, high = OptionRange(entry.module, entry.key) end
		if entry.module == "general" and entry.key == "fontSize" then low, high = 8, 32 end
		if low and high then value = Clamp(value, low, high) end
		if value <= 0 and kind == "size" and not entry.zero and not entry.key:find("powerHeight", 1, true) and not entry.key:find("spacing", 1, true) then return end
	end
	if title then
		AddSetting(plan, entry.module, entry.key, value, title)
		return
	end
	-- Untitled entries (ElvUI) show where the value goes.
	local old = CurrentSetting(entry.module, entry.key)
	table.insert(plan.settings, { module = entry.module, key = entry.key, value = value, from = from, old = old })
	table.insert(plan.mapped, ("%s -> %s: %s = %s%s"):format(from, ModuleTitle(entry.module), entry.key, tostring(value),
		old ~= nil and old ~= value and " " .. E:TextHex("secondary") .. L["(now %s)"]:format(tostring(old)) .. "|r" or ""))
end

local function CountLeaves(value, depth)
	if type(value) ~= "table" then return 1 end
	if depth > 12 then return 0 end
	local count = 0
	for _, inner in pairs(value) do count = count + CountLeaves(inner, depth + 1) end
	return count
end

-- EllesmereUI ---------------------------------------------------------------
local ANCHOR_EDGE = {
	-- side of the target -> point of the element that touches it
	TOP = "BOTTOM", BOTTOM = "TOP", LEFT = "RIGHT", RIGHT = "LEFT",
}

local function Lower(value) return type(value) == "string" and value:lower() or nil end
local function Number(value) return type(value) == "number" and value or nil end

-- When an EllesmereUI element shows, as an EldoUI Show rule. Returns nil
-- and the source's own word when EldoUI has no such rule.
local function EUIShow(element)
	if element.alwaysHidden == true or element.enabled == false then return "never" end
	local visibility = Lower(element.barVisibility) or Lower(element.visibility)
	if visibility == "never" then return "never" end
	if visibility == "mouseover" or ((visibility == nil or visibility == "always") and element.mouseoverEnabled == true) then
		return "mouseover"
	end
	if visibility == nil then return "always" end
	local rule = E.importMaps.euiShow[visibility]
	if rule then return rule end
	return nil, visibility
end

-- A visibility block (Core/Visibility.lua) for a Show rule: a preset's
-- values where one fits, so the options page shows that preset.
local function FadeBlock(show, fadedAlpha)
	local preset = E.VISIBILITY_PRESETS and E.VISIBILITY_PRESETS[show]
	if preset and not fadedAlpha then
		return { preset = show, show = preset.show, fadedAlpha = preset.fadedAlpha, fadeTime = preset.fadeTime, delay = preset.delay }
	end
	return { preset = "custom", show = show, fadedAlpha = fadedAlpha or 0 }
end

local SHOW_WORDS = {
	always = "always shown", mouseover = "shows on mouse over", combat = "shows in combat",
	nocombat = "shows out of combat", target = "shows with a target", combatOrTarget = "shows in combat or with a target",
	never = "off",
}
local function ShowWords(show) return L[SHOW_WORDS[show] or "always shown"] end

-- Action bar button shapes, width divided by height (Modules/ActionBars.lua).
local ASPECTS = { ["1:1"] = 1, ["5:4"] = 1.25, ["4:3"] = 4 / 3, ["3:2"] = 1.5, ["2:1"] = 2 }

-- Buttons, buttons per row and whether the bar stands upright.
-- override* values are the ones EllesmereUI uses when they are set.
local function BarShape(bar, maxButtons)
	local icons = Number(bar.overrideNumIcons) or Number(bar.numIcons) or maxButtons
	icons = Clamp(Round(icons), 1, maxButtons)
	local rows = Number(bar.overrideNumRows) or Number(bar.numRows) or 1
	rows = Clamp(Round(rows), 1, icons)
	local vertical = Lower(bar.orientation) == "vertical"
	-- An upright bar's "rows" are its columns.
	local perRow = vertical and rows or math.ceil(icons / rows)
	return icons, perRow, vertical
end

-- The corner the first button sits in (EldoUI's growth).
local function BarGrowth(bar)
	local direction = Lower(bar.growDirection)
	local right = direction == "left"
	if bar.reverseIconOrder == true then right = not right end
	return (direction == "up" and "BOTTOM" or "TOP") .. (right and "RIGHT" or "LEFT")
end

local GROWTH_WORDS = {
	TOPLEFT = "from the top left", TOPRIGHT = "from the top right",
	BOTTOMLEFT = "from the bottom left", BOTTOMRIGHT = "from the bottom right",
}

-- Size, spacing and shape of a bar's buttons, converted to EldoUI pixels.
-- Returns the settings to write and a note when EldoUI can't match the shape.
local function ButtonLook(plan, bar, title, maxSize, withAspect)
	local look, note = {}, nil
	local width, height = Number(bar.buttonWidth), Number(bar.buttonHeight)
	if width and width > 0 then
		look.size = Clamp(Round(width * plan.factor), 16, maxSize)
		if withAspect and height and height > 0 then
			local ratio, best, bestDiff = width / height, nil, nil
			for key, value in pairs(ASPECTS) do
				local diff = math.abs(value - ratio) / value
				if not bestDiff or diff < bestDiff then best, bestDiff = key, diff end
			end
			if bestDiff <= 0.04 then
				look.aspect = best
			else
				look.aspect = "1:1"
				note = L["%s: EldoUI has no %d x %d button shape, so its buttons are square."]:format(title,
					Round(width * plan.factor), Round(height * plan.factor))
			end
		end
	end
	local padding = Number(bar.buttonPadding)
	if padding and padding >= 0 then look.spacing = Clamp(Round(padding * plan.factor), 0, 20) end
	return look, note
end

-- One preview line for a bar: "12 buttons, 4 per row, 30 px, shows on mouse over".
local function BarLine(from, to, buttons, perRow, look, growth, vertical, show)
	local parts = {}
	if buttons then parts[#parts + 1] = E:Plural(buttons, "%d button", "%d buttons"):format(buttons) end
	parts[#parts + 1] = vertical and E:Plural(perRow, "upright, %d column", "upright, %d columns"):format(perRow)
		or L["%d per row"]:format(perRow) -- no-plural: a count after a number of buttons
	if look.size then parts[#parts + 1] = L["%d px"]:format(look.size) end
	if growth and growth ~= "TOPLEFT" then parts[#parts + 1] = L[GROWTH_WORDS[growth]] end
	parts[#parts + 1] = ShowWords(show)
	return L["%s to %s: %s"]:format(from, to, table.concat(parts, ", "))
end

-- Action bars, pet and stance bars, the micro and bag bars and the XP
-- bars: shape, size, direction and when they show.
local function EUIShownAnchor(plan, anchor)
	-- The known format map owns these identities, even before an optional
	-- frame is built. Unknown source bars must not unhide unrelated movers.
	for _, entry in ipairs(E.importMaps.euiPositions) do
		if entry.anchor == anchor then plan.shown[entry.mover] = true end
	end
end

local function MapEUIBars(plan, data)
	local maps = E.importMaps
	local bars = GetPath(data, "addons.EllesmereUIActionBars.bars")
	if type(bars) ~= "table" then return end
	local mouseover = false
	for _, info in ipairs(maps.euiBars) do
		local bar = bars[info.key]
		if type(bar) == "table" then
			plan.used["addons.EllesmereUIActionBars.bars." .. info.key] = true
			local title = L[info.title]
			local mover = "EldoUI_ActionBar" .. info.index
			local show, own = EUIShow(bar)
			if show == "never" then
				-- Never shown: the bar steps out of sight for good and keeps
				-- its keys (bars 1 and 2 always show).
				local name = L["%s to %s"]:format(title, L[MoverTitle(mover)])
				if info.index >= 3 then
					AddSetting(plan, "ActionBars", "bars." .. info.index .. ".hiddenMouseover", false, title, false)
					AddHidden(plan, mover, name, L["%s: hidden, its keys keep working"]:format(name))
				else
					AddHidden(plan, mover, name)
				end
			else
				if not show then
					show = "always"
					table.insert(plan.notes, L["%s shows only %q in EllesmereUI; EldoUI has no such rule, so it is always shown."]:format(title, own))
				end
				mouseover = mouseover or show == "mouseover"
				local prefix = "bars." .. info.index .. "."
				plan.shown[mover] = true
				local buttons, perRow, vertical = BarShape(bar, 12)
				local growth = BarGrowth(bar)
				local look, note = ButtonLook(plan, bar, title, 80, true)
				if note then table.insert(plan.notes, note) end
				AddSetting(plan, "ActionBars", prefix .. "enabled", true, title, false)
				AddSetting(plan, "ActionBars", prefix .. "buttons", buttons, title, false)
				AddSetting(plan, "ActionBars", prefix .. "perRow", perRow, title, false)
				AddSetting(plan, "ActionBars", prefix .. "growth", growth, title, false)
				-- An upright bar fills its buttons column by column.
				AddSetting(plan, "ActionBars", prefix .. "fillOrder", vertical and "columns" or "rows", title, false)
				for key, value in pairs(look) do AddSetting(plan, "ActionBars", prefix .. key, value, title, false) end
				if AddSetting(plan, "ActionBars", prefix .. "fade", FadeBlock(show), title, false) then
					table.insert(plan.mapped, BarLine(title, L[MoverTitle(mover)], buttons, perRow, look, growth, vertical, show))
				end
			end
		end
	end
	for _, info in ipairs(maps.euiSpecialBars) do
		local bar = bars[info.key]
		if type(bar) == "table" then
			plan.used["addons.EllesmereUIActionBars.bars." .. info.key] = true
			local title = L[info.title]
			local prefix = info.setting .. "."
			local show, own = EUIShow(bar)
			if not show then
				show = "always"
				table.insert(plan.notes, L["%s shows only %q in EllesmereUI; EldoUI has no such rule, so it is always shown."]:format(title, own))
			end
			-- EldoUI's own bar takes the buttons, also when it stays hidden,
			-- so the game's bar doesn't come back in its place.
			AddSetting(plan, "ActionBars", prefix .. "mode", "eldoui", title, false)
			if show == "never" then
				AddSetting(plan, "ActionBars", prefix .. "fade", FadeBlock("never"), title, L["%s: off"]:format(title))
			else
				mouseover = mouseover or show == "mouseover"
				EUIShownAnchor(plan, info.key)
				local buttons, perRow, vertical = BarShape(bar, info.max)
				local growth = BarGrowth(bar)
				local look = ButtonLook(plan, bar, title, 64, false)
				if info.buttons then AddSetting(plan, "ActionBars", prefix .. "buttons", buttons, title, false) end
				AddSetting(plan, "ActionBars", prefix .. "perRow", perRow, title, false)
				AddSetting(plan, "ActionBars", prefix .. "growth", growth, title, false)
				-- An upright bar fills its buttons column by column.
				AddSetting(plan, "ActionBars", prefix .. "fillOrder", vertical and "columns" or "rows", title, false)
				for key, value in pairs(look) do AddSetting(plan, "ActionBars", prefix .. key, value, title, false) end
				AddSetting(plan, "ActionBars", prefix .. "fade", FadeBlock(show), title,
					BarLine(title, title, info.buttons and buttons or nil, perRow, look, growth, vertical, show))
			end
		end
	end
	-- The micro menu, bag bar and XP bars: when they show.
	for _, info in ipairs(maps.euiOtherBars) do
		local bar = bars[info.key]
		if type(bar) == "table" and E.modules and E.modules[info.module] then
			plan.used["addons.EllesmereUIActionBars.bars." .. info.key] = true
			local title = L[info.title]
			local show, own = EUIShow(bar)
			if not show then
				show = "always"
				table.insert(plan.notes, L["%s shows only %q in EllesmereUI; EldoUI has no such rule, so it is always shown."]:format(title, own))
			end
			if show ~= "never" then EUIShownAnchor(plan, info.key) end
			if info.enabled then
				AddSetting(plan, info.module, info.enabled, show ~= "never", title, show == "never" and L["%s: off"]:format(title) or false)
			end
			if info.fade and (show ~= "never" or not info.enabled) then
				AddSetting(plan, info.module, info.fade, FadeBlock(show), title, L["%s: %s"]:format(title, ShowWords(show)))
			end
		end
	end
	-- Bars with no EldoUI counterpart that the string shows.
	for _, info in ipairs(maps.euiExtraBars) do
		local bar = bars[info.key]
		if type(bar) == "table" then
			plan.used["addons.EllesmereUIActionBars.bars." .. info.key] = true
			if EUIShow(bar) ~= "never" then
				if info.key:find("^Bar%d") then
					table.insert(plan.ignored, L["%s: EldoUI has eight action bars, so this one isn't imported"]:format(L[info.title]))
				else
					table.insert(plan.ignored, L["%s: no matching EldoUI part"]:format(L[info.title]))
				end
			end
		end
	end
	local extra = bars.ExtraActionButton
	if type(extra) == "table" and EUIShow(extra) == "never" then
		table.insert(plan.ignored, L["%s: its spot goes to the zone ability, which shows whenever the game offers one"]:format(L["Extra Action Button"]))
	end
	-- Hovering one mouse-over bar shows them all.
	local together = GetPath(data, "addons.EllesmereUIActionBars.mouseoverShowAll")
	if type(together) == "boolean" then
		plan.used["addons.EllesmereUIActionBars.mouseoverShowAll"] = true
		local line = false
		if together and mouseover then line = nil end
		AddSetting(plan, "ActionBars", "linkMouseover", together, L["Show mouse-over bars together"], line)
	end
end

-- EllesmereUI data bars as EldoUI datatext panels (Info Bar): the blocks
-- become the panel's datatexts, in their order from left to right, with
-- the bar's size, background, layer, place and when it shows. A bar along
-- the whole bottom or top edge fills the main Info Bar (and a second one
-- the second bar) instead.
local DATA_ALIGN = { LEFT = 1, CENTER = 2, RIGHT = 3 }
local DATA_STRATA = { BACKGROUND = true, LOW = true, MEDIUM = true, HIGH = true }
local MAX_DATA_PANELS, MAX_DATA_SLOTS = 8, 8
local SLOTS = 6 -- datatexts per section of a full-width Info Bar bar

-- The EldoUI datatext for one block (nil: EldoUI has none).
local function DataBlockName(block)
	local name = E.importMaps.euiDataBlocks[block.type]
	if type(name) == "function" then name = name(block.settings) end
	if name and E.dataTexts and E.dataTexts[name] then return name end
	return nil
end

-- The datatexts of one data bar, and the block types EldoUI has none for.
local function DataBarSlots(bar)
	local blocks = {}
	for index, block in ipairs(type(bar.blocks) == "table" and bar.blocks or {}) do
		if type(block) == "table" and type(block.type) == "string" then
			local side = type(block.align) == "string" and DATA_ALIGN[block.align:upper()] or 2
			blocks[#blocks + 1] = { block = block, side = side, index = index }
		end
	end
	table.sort(blocks, function(a, b)
		if a.side ~= b.side then return a.side < b.side end
		return a.index < b.index
	end)
	local slots, seen, missing, missingSeen = {}, {}, {}, {}
	for _, item in ipairs(blocks) do
		local block = item.block
		local name = DataBlockName(block)
		if name then
			-- One of each, except spacers.
			if (name == "Spacer" or not seen[name]) and #slots < MAX_DATA_SLOTS then
				slots[#slots + 1] = name
				seen[name] = true
			end
		elseif not missingSeen[block.type] then
			missingSeen[block.type] = true
			missing[#missing + 1] = block.type
		end
	end
	-- Spacers only at the ends would leave an empty slot.
	while slots[#slots] == "Spacer" do table.remove(slots) end
	while slots[1] == "Spacer" do table.remove(slots, 1) end
	return slots, missing
end

-- How see-through the bar's background is, in percent (nil: no background).
local function DataBarBackground(bar)
	local theme = type(bar.theme) == "table" and bar.theme or {}
	local alpha
	if Lower(theme.style) == "modern" then
		alpha = type(theme.modernColor) == "table" and Number(theme.modernColor.a)
	else
		alpha = Number(theme.euiAlpha)
	end
	if not alpha then return 60 end
	if alpha <= 0.01 then return nil end
	return Clamp(Round(alpha * 20) * 5, 5, 100)
end

-- A data bar along the whole bottom or top edge of the screen fills one of
-- the Info Bar's full-width bars (the main bar first, then the second bar)
-- instead of becoming a panel.
local FULL_EDGES = { bottom = "BOTTOM", top = "TOP" }
local FULL_BARS = {
	{ mover = "EldoUI_InfoBar", title = "Info Bar", prefix = "", fontSize = 14 },
	{ mover = "EldoUI_InfoBar2", title = "Second Info Bar", prefix = "bar2.", fontSize = 13, enable = true },
}
local FULL_SECTIONS = { "left", "center", "right" }
local SECTION_LINES = { left = "left: %s", center = "center: %s", right = "right: %s" }
local SECTION_FULL = {
	left = "%s: the left section holds six datatexts, so %s isn't imported",
	center = "%s: the center section holds six datatexts, so %s isn't imported",
	right = "%s: the right section holds six datatexts, so %s isn't imported",
}

-- The screen edge of a full-width bar, or nil for any other bar.
local function FullBarEdge(bar)
	local orientation = Lower(bar.orientation)
	if Lower(bar.lengthMode) ~= "full" or orientation == "v" or orientation == "vertical" then return nil end
	return FULL_EDGES[Lower(bar.snapEdge) or ""]
end

-- A spacer only between two datatexts, and never two in a row.
local function TidySpacers(list)
	local out = {}
	for _, name in ipairs(list) do
		if not (name == "Spacer" and (#out == 0 or out[#out] == "Spacer")) then out[#out + 1] = name end
	end
	while out[#out] == "Spacer" do table.remove(out) end
	return out
end

-- The blocks of a full-width bar in the Info Bar's three sections. LEFT
-- and RIGHT blocks sit at the screen edges; CENTER blocks gather around
-- the bar's center block: the ones before it end the left section, the
-- ones after it start the right section (with no center block they all go
-- to the center). Each section holds SLOTS datatexts, and the ones nearest
-- the middle of the screen stay out first. Returns the sections, the
-- datatexts left out per section and the block types EldoUI has none for.
local function FullBarSections(bar)
	local list = type(bar.blocks) == "table" and bar.blocks or {}
	local centerAt
	if bar.centerBlockId ~= nil then
		for index, block in ipairs(list) do
			if type(block) == "table" and block.id == bar.centerBlockId then
				centerAt = index
				break
			end
		end
	end
	local edgeLeft, nearLeft, center, nearRight, edgeRight = {}, {}, {}, {}, {}
	local seen, missing, missingSeen = {}, {}, {}
	for index, block in ipairs(list) do
		if type(block) == "table" and type(block.type) == "string" then
			local name = DataBlockName(block)
			if not name then
				if not missingSeen[block.type] then
					missingSeen[block.type] = true
					missing[#missing + 1] = block.type
				end
			elseif name == "Spacer" or not seen[name] then
				-- One of each, except spacers.
				seen[name] = true
				local align = type(block.align) == "string" and block.align:upper() or "CENTER"
				local into
				if index == centerAt then
					into = center
				elseif align == "LEFT" then
					into = edgeLeft
				elseif align == "RIGHT" then
					into = edgeRight
				elseif not centerAt then
					into = center
				elseif index < centerAt then
					into = nearLeft
				else
					into = nearRight
				end
				into[#into + 1] = name
			end
		end
	end
	for _, name in ipairs(nearLeft) do edgeLeft[#edgeLeft + 1] = name end
	for _, name in ipairs(edgeRight) do nearRight[#nearRight + 1] = name end
	local sections = { left = TidySpacers(edgeLeft), center = TidySpacers(center), right = TidySpacers(nearRight) }
	local dropped = {}
	for _, side in ipairs(FULL_SECTIONS) do
		local items, out = sections[side], {}
		-- The right section is read from its screen edge inward.
		local fromStart = side == "right"
		while #items > SLOTS do
			local name = table.remove(items, fromStart and 1 or #items)
			if name ~= "Spacer" then table.insert(out, fromStart and #out + 1 or 1, name) end
		end
		while items[1] == "Spacer" do table.remove(items, 1) end
		sections[side] = TidySpacers(items)
		dropped[side] = out
	end
	return sections, dropped, missing
end

local function DataTextTitle(name)
	local definition = E.dataTexts and E.dataTexts[name]
	return definition and definition.title and L[definition.title] or L[name]
end

-- One full-width data bar onto an Info Bar bar: its three sections, height,
-- text size, background and when it shows, plus its screen edge when
-- positions are imported (or, for `stackOn`, a place against that bar).
local function MapFullBar(plan, bar, name, target, edge, show, stackOn)
	plan.shown[target.mover] = true
	local sections, dropped = FullBarSections(bar)
	local prefix = target.prefix
	local barTitle = L[target.title]
	local defaults = E.modules.InfoBar.defaults or {}
	if prefix ~= "" then defaults = defaults.bar2 or {} end
	local replaces = false
	local parts = {}
	for _, side in ipairs(FULL_SECTIONS) do
		local slots = {}
		for i = 1, SLOTS do slots[i] = sections[side][i] or "" end
		-- A line warns when the import replaces datatexts the player chose.
		local current = CurrentSetting("InfoBar", prefix .. side)
		local default = defaults[side]
		if type(current) == "table" and type(default) == "table" then
			for i = 1, SLOTS do
				local now = current[i] or ""
				if now ~= (default[i] or "") and now ~= slots[i] then replaces = true end
			end
		end
		AddSetting(plan, "InfoBar", prefix .. side, slots, name, false)
		if #sections[side] > 0 then
			local titles = {}
			for _, slot in ipairs(sections[side]) do titles[#titles + 1] = DataTextTitle(slot) end
			parts[#parts + 1] = L[SECTION_LINES[side]]:format(table.concat(titles, ", "))
		end
		if #dropped[side] > 0 then
			local titles = {}
			for _, slot in ipairs(dropped[side]) do titles[#titles + 1] = DataTextTitle(slot) end
			table.insert(plan.ignored, L[SECTION_FULL[side]]:format(name, table.concat(titles, ", ")))
		end
	end
	if target.enable then AddSetting(plan, "InfoBar", prefix .. "enabled", true, name, false) end
	local height = Clamp(Round((Number(bar.thickness) or 28) * plan.factor), 16, 48)
	AddSetting(plan, "InfoBar", prefix .. "width", 0, name, false)
	AddSetting(plan, "InfoBar", prefix .. "height", height, name, false)
	AddSetting(plan, "InfoBar", prefix .. "fontSize",
		Clamp(Round(target.fontSize * (Number(bar.fontScale) or 100) / 100), 8, 20), name, false)
	local alpha = DataBarBackground(bar)
	AddSetting(plan, "InfoBar", prefix .. "backdrop", alpha ~= nil, name, false)
	if alpha then AddSetting(plan, "InfoBar", prefix .. "backdropAlpha", alpha, name, false) end
	AddSetting(plan, "InfoBar", prefix .. "visibility", FadeBlock(show), name, false)
	parts[#parts + 1] = L["%d px high"]:format(height)
	parts[#parts + 1] = ShowWords(show)
	table.insert(plan.mapped, L["%s to %s: %s"]:format(name, barTitle, table.concat(parts, "; ")))
	if replaces then
		table.insert(plan.mapped, L["%s: replace your datatexts on %s"]:format(name, barTitle))
	end
	if not Options().positions then return end
	if stackOn and not plan.points[target.mover] then
		-- A second bar on the same edge sits against the first one, as the
		-- two rows stack in EllesmereUI, instead of on top of it.
		local away = edge == "BOTTOM" and "TOP" or "BOTTOM"
		plan.points[target.mover] = { edge, stackOn.mover .. "Mover", away, 0, 0 }
		local line = edge == "BOTTOM" and L["%s to %s: just above %s"] or L["%s to %s: just below %s"]
		table.insert(plan.mapped, line:format(name, barTitle, L[stackOn.title]))
	else
		AddPoint(plan, target.mover, { edge, "UIParent", edge, 0, 0 }, name)
	end
end

local function MapEUIDataBars(plan, data)
	local bars = GetPath(data, "addons.EllesmereUIDataBars.bars")
	if type(bars) ~= "table" or not (E.modules and E.modules.InfoBar) then return end
	local panels, full, title = {}, {}, L["Data bars"]
	for _, bar in ipairs(bars) do
		if type(bar) == "table" then
			local name = type(bar.name) == "string" and strtrim(bar.name) ~= "" and strtrim(bar.name) or L["Data bar"]
			local slots, missing = DataBarSlots(bar)
			if #missing > 0 then
				table.insert(plan.ignored, L["%s: no matching EldoUI datatext for %s"]:format(name, table.concat(missing, ", ")))
			end
			local show, own = EUIShow(bar)
			if bar.visHideNoTarget == true and show == "always" then show = "target" end
			local edge = FullBarEdge(bar)
			if #slots == 0 then
				if type(bar.blocks) == "table" and #bar.blocks == 0 then
					table.insert(plan.ignored, L["%s: a background with no datatexts; EldoUI's panels always hold datatexts"]:format(name))
				end
			elseif show == "never" then
				table.insert(plan.ignored, L["%s: off in the string"]:format(name))
			elseif not (edge and #full < #FULL_BARS) and #panels >= MAX_DATA_PANELS then
				table.insert(plan.ignored, L["%s: EldoUI has eight datatext panels, so this one isn't imported"]:format(name))
			elseif edge and #full < #FULL_BARS then
				if not show then
					show = "always"
					table.insert(plan.notes, L["%s shows only %q in EllesmereUI; EldoUI has no such rule, so it is always shown."]:format(name, own))
				end
				full[#full + 1] = edge
				-- A full bar on an edge an earlier one already holds stacks on it.
				local stackOn
				for i = 1, #full - 1 do
					if full[i] == edge then stackOn = FULL_BARS[i] end
				end
				MapFullBar(plan, bar, name, FULL_BARS[#full], edge, show, stackOn)
			else
				if not show then
					show = "always"
					table.insert(plan.notes, L["%s shows only %q in EllesmereUI; EldoUI has no such rule, so it is always shown."]:format(name, own))
				end
				local vertical = Lower(bar.orientation) == "v"
				local length = Number(bar.length) or 300
				local thickness = Number(bar.thickness) or 24
				local panel = {
					name = name, enabled = true, slots = slots, numSlots = #slots,
					vertical = vertical, display = "text", attach = "none",
					border = bar.hideBorder ~= true,
					fontSize = Clamp(Round(13 * (Number(bar.fontScale) or 100) / 100), 8, 20),
					strata = type(bar.barStrata) == "string" and DATA_STRATA[bar.barStrata] and bar.barStrata or "LOW",
					visibility = FadeBlock(show),
				}
				if vertical then
					panel.width = Clamp(Round(thickness * plan.factor / 10) * 10, 100, 1200)
					panel.height = Clamp(Round(length * plan.factor / #slots), 14, 48)
				else
					panel.width = Clamp(Round(length * plan.factor / 10) * 10, 100, 1200)
					panel.height = Clamp(Round(thickness * plan.factor), 14, 48)
				end
				local alpha = DataBarBackground(bar)
				panel.backdrop = alpha ~= nil
				panel.backdropAlpha = alpha or 0
				panels[#panels + 1] = panel
				local mover = "EldoUI_DataPanel" .. #panels
				plan.shown[mover] = true
				local moverTitle = L["Datatext Panel %d"]:format(#panels)
				if Options().positions then
					local point, relPoint, x, y = ReadPosition(bar.savedPos)
					if point and not (point == "CENTER" and relPoint == "CENTER" and x == 0 and y == 0) then
						AddPoint(plan, mover, ClampPoint(point, relPoint, x * plan.factor, y * plan.factor), name)
					end
				end
				local list = {}
				for _, slot in ipairs(slots) do
					local definition = E.dataTexts[slot]
					list[#list + 1] = definition and definition.title and L[definition.title] or L[slot]
				end
				table.insert(plan.mapped, L["%s to %s: %s"]:format(name, moverTitle, table.concat({
					table.concat(list, ", "), L["%d x %d px"]:format(panel.width, vertical and panel.height * #slots or panel.height),
					ShowWords(show) }, "; ")))
			end
		end
	end
	if #panels == 0 and #full == 0 then return end
	plan.used["addons.EllesmereUIDataBars.bars"] = true
	-- The string's data bars replace the datatext panels.
	local current = CurrentSetting("InfoBar", "panels")
	local line = false
	if type(current) == "table" and #current > 0 then
		line = L["%s: replace your %s"]:format(title, E:Plural(#current, "%d datatext panel", "%d datatext panels"):format(#current))
	end
	AddSetting(plan, "InfoBar", "panels", panels, title, line)
	if E.modules.InfoBar.db and E.modules.InfoBar.db.enabled == false then
		table.insert(plan.notes, E:ModuleOffNote("InfoBar", L["The data bars go to it."]))
	end
end

-- Unit frames: which ones show, when, and their cast bars.
local function MapEUIUnits(plan, data)
	local maps = E.importMaps
	local units = GetPath(data, "addons.EllesmereUIUnitFrames")
	if type(units) ~= "table" then return end
	local enabled = type(units.enabledFrames) == "table" and units.enabledFrames or {}
	for _, unit in ipairs(maps.euiUnits) do
		local title = L[unit.title]
		if enabled[unit.key] == false then
			AddHidden(plan, unit.mover, title)
		elseif enabled[unit.key] == true then
			plan.shown[unit.mover] = true
			AddSetting(plan, "UnitFrames", "units." .. unit.key .. ".enabled", true, title, false)
			-- When the frame shows: only with a target, in combat, not mounted.
			local settings = units[unit.key]
			if type(settings) == "table" and (unit.key == "player" or unit.key == "focus" or unit.key == "pet") then
				local noTarget, outOfCombat = settings.visHideNoTarget == true, settings.oocFadeEnabled == true
				local show = noTarget and outOfCombat and "combatOrTarget" or noTarget and "target" or outOfCombat and "combat" or "always"
				local block = FadeBlock(show)
				block.hideMounted = settings.visHideMounted == true
				AddSetting(plan, "UnitFrames", "units." .. unit.key .. ".fader", block, title,
					show ~= "always" and L["%s: %s"]:format(title, ShowWords(show)) or false)
			end
		end
	end
	-- The player cast bar: the unit frames' own one (on the frame or on
	-- its own), else the resource bars' one, else the game's own.
	local player = type(units.player) == "table" and units.player or {}
	local resource = GetPath(data, "addons.EllesmereUIResourceBars.castBar")
	local title = L["Player cast bar"]
	local width, height, attached
	if player.showPlayerCastbar == true then
		width, height = Number(player.playerCastbarWidth), Number(player.playerCastbarHeight)
		local anchor = GetPath(data, "unlockLayout.anchors.playerCastbar")
		attached = type(anchor) == "table" and anchor.target == "player"
	elseif type(resource) == "table" and resource.enabled == true then
		width, height = Number(resource.width), Number(resource.height)
	elseif player.showPlayerCastbar == false then
		AddSetting(plan, "UnitFrames", "units.player.castbar.enabled", false, title,
			L["%s: off (the game's own cast bar shows)"]:format(title))
		return
	else
		return
	end
	AddSetting(plan, "UnitFrames", "units.player.castbar.enabled", true, title, false)
	AddSetting(plan, "UnitFrames", "units.player.castbar.detached", not attached, title, false)
	if not attached then AddSetting(plan, "UnitFrames", "units.player.castbar.anchor", "MOVER", title, false) end
	local parts = { attached and L["on the player frame"] or L["on its own"] }
	if width and width > 0 then
		local value = Clamp(Round(width * plan.factor), 60, 600)
		AddSetting(plan, "UnitFrames", "units.player.castbar.width", value, title, false)
		parts[#parts + 1] = L["%d px wide"]:format(value)
	end
	if height and height > 0 then
		local value = Clamp(Round(height * plan.factor), 8, 40)
		AddSetting(plan, "UnitFrames", "units.player.castbar.height", value, title, false)
		parts[#parts + 1] = L["%d px high"]:format(value)
	end
	table.insert(plan.mapped, L["%s: %s"]:format(title, table.concat(parts, ", ")))
end

-- Party and raid frames: the raid's growth directions.
local VALID_GROWTH = { UP = true, DOWN = true, LEFT = true, RIGHT = true }
local function MapEUIGroups(plan, data)
	local raid = GetPath(data, "addons.EllesmereUIRaidFrames")
	if type(raid) ~= "table" then return end
	local first = type(raid.unitGrowth) == "string" and raid.unitGrowth:upper()
	if not VALID_GROWTH[first] then return end
	local second = type(raid.groupGrowth) == "string" and raid.groupGrowth:upper()
	local vertical = first == "UP" or first == "DOWN"
	if not VALID_GROWTH[second] or ((second == "UP" or second == "DOWN") == vertical) then second = "AUTO" end
	local title = L["Raid frames grow"]
	AddSetting(plan, "GroupFrames", "raid.growth", first, title, false)
	AddSetting(plan, "GroupFrames", "raid.growth2", second, title,
		L["%s: %s"]:format(title, second == "AUTO" and ShowValue(first) or L["%s, then %s"]:format(ShowValue(first), ShowValue(second))))
end

-- Cooldown Manager: EldoUI's essential, utility and buff rows.
local CDM_GROWTH = { RIGHT = true, LEFT = true, CENTER = true }
local function MapEUICooldowns(plan, data)
	local maps = E.importMaps
	local list = GetPath(data, "addons.EllesmereUICooldownManager.cdmBars.bars")
	if type(list) ~= "table" then return end
	local others = {}
	for _, bar in ipairs(list) do
		local def = type(bar) == "table" and maps.euiCooldownBars[bar.key]
		if def then
			local title = L[def.title]
			local prefix = "viewers." .. def.viewer .. "."
			local show, own = EUIShow(bar)
			if not show then
				show = "always"
				table.insert(plan.notes, L["%s shows only %q in EllesmereUI; EldoUI has no such rule, so it is always shown."]:format(title, own))
			end
			local parts = {}
			local size = Number(bar.iconSize)
			if size and size > 0 then
				size = Clamp(Round(size * plan.factor), 16, 80)
				AddSetting(plan, "CooldownManager", prefix .. "size", size, title, false)
				parts[#parts + 1] = L["%d px"]:format(size)
			end
			local spacing = Number(bar.spacing)
			if spacing and spacing >= 0 then
				AddSetting(plan, "CooldownManager", prefix .. "spacing", Clamp(Round(spacing * plan.factor), 0, 20), title, false)
			end
			local count, rows = Number(bar.maxIcons), Number(bar.numRows) or 1
			if count and count > 0 then
				local perRow = Clamp(math.ceil(count / Clamp(Round(rows), 1, count)), 1, 24)
				AddSetting(plan, "CooldownManager", prefix .. "perRow", perRow, title, false)
				parts[#parts + 1] = L["%d per row"]:format(perRow) -- no-plural: a count of icons
			end
			local growth = type(bar.growDirection) == "string" and bar.growDirection:upper()
			if bar.verticalOrientation == true then
				growth = growth == "UP" and "UP" or "DOWN"
			elseif not CDM_GROWTH[growth] then
				growth = "CENTER"
			end
			AddSetting(plan, "CooldownManager", prefix .. "growth", growth, title, false)
			parts[#parts + 1] = ShowWords(show)
			AddSetting(plan, "CooldownManager", prefix .. "fade", FadeBlock(show), title, L["%s: %s"]:format(title, table.concat(parts, ", ")))
		elseif type(bar) == "table" and type(bar.name) == "string" and bar.enabled ~= false then
			others[#others + 1] = bar.name
		end
	end
	if #others > 0 then
		table.insert(plan.ignored, L["Cooldown Manager bars %s: EldoUI has the essential, utility and buff rows only"]:format(table.concat(others, ", ")))
	end
end

-- Resource bars: when EldoUI's Class Resources stack shows.
local function MapEUIResources(plan, data)
	local primary = GetPath(data, "addons.EllesmereUIResourceBars.primary")
	if type(primary) ~= "table" or primary.enabled == false then return end
	local show, own = EUIShow({ visibility = primary.visibility })
	local title = L["Resource bars"]
	if not show then
		show = "always"
		table.insert(plan.notes, L["%s shows only %q in EllesmereUI; EldoUI has no such rule, so it is always shown."]:format(title, own))
	end
	local faded
	if show == "always" and primary.oocFadeEnabled == true then
		show = "combat"
		faded = Clamp(Number(primary.oocAlpha) or 0, 0, 1)
	end
	AddSetting(plan, "ClassPower", "visibility", FadeBlock(show, faded), title, L["%s: %s"]:format(title, ShowWords(show)))
end

-- Version 4 links name explicit native edges. Their graph is imported as
-- mover-to-mover points; foreign texture insets and live animation offsets
-- are not transplanted into the native frames.
local function LinkNumber(value)
	return not E:IsSecret(value) and type(value) == "number" and value == value
		and value > -math.huge and value < math.huge
end

local function LinkOffsets(x, y, factor)
	return LinkNumber(x) and LinkNumber(y) and LinkNumber(x * factor) and LinkNumber(y * factor)
		and math.abs(x * factor) <= 2 * HALF_W - EDGE_MARGIN
		and math.abs(y * factor) <= 2 * HALF_H - EDGE_MARGIN_Y
end

local function LinkFailure(detail)
	return L["This point-linked layout cannot be imported: %s. Nothing was changed."]:format(detail)
end

local function PointLinks(source, byAnchor, factor)
	local links, movers, count = {}, {}, 0
	local anchors = GetPath(source.data, "unlockLayout.anchors")
	if type(anchors) ~= "table" or not LinkNumber(factor) or factor <= 0 then
		return nil, LinkFailure(L["invalid anchor data"])
	end
	local function Ambiguous(entry)
		for _, other in pairs(byAnchor) do
			if other ~= entry and other.mover == entry.mover
				and (GetPath(source.data, other.from) ~= nil or anchors[other.anchor] ~= nil) then return true end
		end
	end
	for key, anchor in pairs(anchors) do
		if type(key) ~= "string" or type(anchor) ~= "table" then return nil, LinkFailure(L["invalid anchor data"]) end
		if not byAnchor[key] then return nil, LinkFailure(L["an anchor has no supported native frame"]) end
		if anchor.mode == "POINT" then
			count = count + 1
			local entry = byAnchor[key]
			local target = type(anchor.target) == "string" and byAnchor[anchor.target]
			if not entry or not target then return nil, LinkFailure(L["an anchor has no supported native frame"]) end
			if not VALID_POINT[anchor.sourcePoint] or not VALID_POINT[anchor.targetPoint]
				or not LinkOffsets(anchor.offsetX, anchor.offsetY, factor) then
				return nil, LinkFailure(L["invalid anchor data"])
			end
			if entry.mover == target.mover or movers[entry.mover] or Ambiguous(entry) or Ambiguous(target) then return nil, LinkFailure(L["an anchor is ambiguous or points to itself"]) end
			for _, item in ipairs({ entry, target }) do
				local frame = E.movers[item.mover]
				if not frame or rawget(_G, item.mover .. "Mover") ~= frame then
					return nil, LinkFailure(L["an anchor has no supported native frame"])
				end
			end
			movers[entry.mover] = key
			links[key] = { anchor.sourcePoint, target.mover .. "Mover", anchor.targetPoint,
				anchor.offsetX * factor, anchor.offsetY * factor }
		elseif type(anchor) == "table" and anchor.mode ~= nil then
			return nil, LinkFailure(L["invalid anchor data"])
		end
	end
	if count == 0 then return nil, LinkFailure(L["no supported point links were found"]) end
	-- A legacy side link in the same export must retain its relationship
	-- when its target is now a point-linked native frame.
	for key, anchor in pairs(anchors) do
		if type(anchor) == "table" and anchor.mode == nil and byAnchor[key] then
			local entry, target = byAnchor[key], byAnchor[anchor.target]
			local side = type(anchor.side) == "string" and anchor.side:upper()
			if not target or not ANCHOR_EDGE[side] or movers[entry.mover] then
				return nil, LinkFailure(L["an anchor is ambiguous or points to itself"])
			end
			local x, y = anchor.offsetX, anchor.offsetY
			if x == nil then x = 0 end
			if y == nil then y = 0 end
			if not LinkOffsets(x, y, factor) then
				return nil, LinkFailure(L["invalid anchor data"])
			end
			for _, item in ipairs({ entry, target }) do
				if not E.movers[item.mover] or rawget(_G, item.mover .. "Mover") ~= E.movers[item.mover] then
					return nil, LinkFailure(L["an anchor has no supported native frame"])
				end
			end
			movers[entry.mover] = key
			links[key] = { ANCHOR_EDGE[side], target.mover .. "Mover", side, x * factor, y * factor }
		end
	end
	return links
end

-- Check the complete prospective native graph before any saved write. A
-- retained role or adaptive point can close a loop through an imported link.
local InheritedPoint, InheritedAdaptive
local function PointGraphProblem(plan, context)
	if plan.source.kind ~= "eui" or plan.source.version ~= 4 then return nil end
	for name, point in pairs(plan.points) do
		if type(name) ~= "string" or type(point) ~= "table" or not VALID_POINT[point[1]] or not VALID_POINT[point[3]]
			or type(point[2]) ~= "string" or not LinkOffsets(point[4], point[5], 1) then
			return LinkFailure(L["invalid anchor data"])
		end
		if not E.movers[name] or rawget(_G, name .. "Mover") ~= E.movers[name] then
			return LinkFailure(L["an anchor has no supported native frame"])
		end
	end
	local key = context and context.key or (E.EffectiveLayout and E:EffectiveLayout() or E.db.general.layout)
	local base = context and context.layout or E.layouts[key] or E.layouts[E.defaults.general.layout] or {}
	local function Check(role)
		local choices = {}
		for name, point in pairs(base.points or {}) do choices[name] = { point } end
		-- Native roles take precedence over adaptive layout points. Include
		-- every retained adaptive alternative, without assuming two different
		-- frames select their alternatives at the same threshold.
		for _, field in ipairs({ "narrowPoints", "widePoints" }) do
			for name, entry in pairs(InheritedAdaptive(base[field], field == "narrowPoints") or {}) do
				if not plan.points[name] and not role[name] then
					choices[name] = choices[name] or {}
					choices[name][#choices[name] + 1] = entry.point
					if entry.adaptive then choices[name][#choices[name] + 1] = entry.adaptive.point end
				end
			end
		end
		for name, point in pairs(role) do if not plan.points[name] then choices[name] = { point } end end
		for name, point in pairs(plan.points) do choices[name] = { point } end
		local visiting, done = {}, {}
		local function Visit(name)
			if visiting[name] then return LinkFailure(L["the frame links could form a loop"]) end
			if done[name] then return nil end
			if not choices[name] or #choices[name] == 0 then return LinkFailure(L["an anchor has no supported native frame"]) end
			visiting[name] = true
			for _, point in ipairs(choices[name]) do
				if type(point) ~= "table" or not VALID_POINT[point[1]] or not VALID_POINT[point[3]]
					or type(point[2]) ~= "string" or not LinkNumber(point[4]) or not LinkNumber(point[5]) then
					return LinkFailure(L["invalid anchor data"])
				end
				local relative = type(point) == "table" and point[2] or nil
				local link = type(point) == "table" and point.link
				local target = type(link) == "table" and link.to or nil
				if target == nil and relative ~= nil and relative ~= "UIParent" then
					target = type(relative) == "string" and relative:match("^(.+)Mover$")
					if not target then return LinkFailure(L["an anchor has no supported native frame"]) end
				end
				if target ~= nil then
					if type(target) ~= "string" or (not context and (not E.movers[target] or rawget(_G, target .. "Mover") ~= E.movers[target])) then
						return LinkFailure(L["an anchor has no supported native frame"])
					end
					local problem = Visit(target)
					if problem then return problem end
				end
			end
			visiting[name], done[name] = nil, true
		end
		for name in pairs(context and choices or plan.points) do
			local problem = Visit(name)
			if problem then return problem end
		end
	end
	local variants, roles = { {} }, {}
	if context then
		for role, points in pairs(context.roles or {}) do roles[role] = points; variants[#variants + 1] = points end
	else
	for role, profile in pairs(E.roleProfiles or {}) do
		if type(E.GetRolePoints) ~= "function" then return LinkFailure(L["an anchor has no supported native frame"]) end
		local ok, points = pcall(E.GetRolePoints, E, role, key)
		if not ok or type(points) ~= "table" then return LinkFailure(L["invalid anchor data"]) end
		roles[role] = {}
		for name, point in pairs(points) do roles[role][name] = InheritedPoint(point) end
		variants[#variants + 1] = roles[role]
		if role == "healer" then
			for spot in pairs(type(profile) == "table" and profile.spots or {}) do
				local worked, alternative = pcall(E.GetRolePoints, E, role, key, spot)
				if not worked or type(alternative) ~= "table" then return LinkFailure(L["invalid anchor data"]) end
				local normalized = {}
				for name, point in pairs(alternative) do normalized[name] = InheritedPoint(point) end
				variants[#variants + 1] = normalized
			end
		end
	end
	end
	for _, role in ipairs(variants) do
		local problem = Check(role)
		if problem then return problem end
	end
	if context then return nil end
	return nil, { key = key, layout = CopyTable(base), roles = roles }
end

local function MapEUI(source, factor)
	local plan = NewPlan(source, factor)
	local data = source.data
	local maps = E.importMaps
	local anchors = GetPath(data, "unlockLayout.anchors")
	anchors = type(anchors) == "table" and anchors or {}

	-- The entries EldoUI uses per anchor key: the first one the string
	-- shows (see `when` in the maps).
	local byAnchor = {}
	for _, entry in ipairs(maps.euiPositions) do
		if entry.anchor and not byAnchor[entry.anchor] and not (entry.when and not entry.when(data)) then byAnchor[entry.anchor] = entry end
	end

	local links
	if source.version == 4 then
		local problem
		links, problem = PointLinks(source, byAnchor, factor)
		if not links then plan.blocked = problem; return plan end
	end

	-- Place an element: anchored to another element when EllesmereUI does
	-- that and the target can be placed, else its stored absolute position
	-- (elements attached to a screen edge keep that position up to date).
	-- (0,0) CENTER means "never moved" and is skipped.
	local resolved, visiting = {}, {}
	local function Resolve(key)
		if links and links[key] then return CopyTable(links[key]) end
		if resolved[key] ~= nil then return resolved[key] or nil end
		local entry = byAnchor[key]
		local anchor = anchors[key]
		if type(anchor) == "table" and type(anchor.target) == "string" and not visiting[key] then
			visiting[key] = true
			local target = Resolve(anchor.target)
			visiting[key] = nil
			local targetEntry = byAnchor[anchor.target]
			local side = type(anchor.side) == "string" and anchor.side:upper()
			if target and targetEntry and target[1] == "CENTER" and target[3] == "CENTER" and ANCHOR_EDGE[side] then
				local width, height = MoverSize(targetEntry.mover)
				if width then
					local x, y = target[4], target[5]
					local offX = (type(anchor.offsetX) == "number" and anchor.offsetX or 0) * factor
					local offY = (type(anchor.offsetY) == "number" and anchor.offsetY or 0) * factor
					if side == "TOP" then y = y + height / 2
					elseif side == "BOTTOM" then y = y - height / 2
					elseif side == "LEFT" then x = x - width / 2
					else x = x + width / 2 end
					x, y = x + offX, y + offY
					local point = ANCHOR_EDGE[side]
					local ownWidth, ownHeight
					if entry then ownWidth, ownHeight = MoverSize(entry.mover) end
					if ownWidth then
						-- Store the center, so elements anchored to this one can follow.
						if point == "BOTTOM" then y = y + ownHeight / 2
						elseif point == "TOP" then y = y - ownHeight / 2
						elseif point == "RIGHT" then x = x - ownWidth / 2
						else x = x + ownWidth / 2 end
						point = "CENTER"
					end
					local result = ClampPoint(point, "CENTER", x, y)
					result.anchored = anchor.target
					resolved[key] = result
					return result
				end
			end
		end
		local point, relPoint, x, y
		if entry then point, relPoint, x, y = ReadPosition(GetPath(data, entry.from)) end
		if point and not (point == "CENTER" and relPoint == "CENTER" and x == 0 and y == 0) then
			resolved[key] = ClampPoint(point, relPoint, x * factor, y * factor)
		else
			resolved[key] = false
		end
		return resolved[key] or nil
	end

	if Options().positions then
		for _, entry in ipairs(maps.euiPositions) do
			if byAnchor[entry.anchor] == entry then
				if entry.from then plan.used[entry.from] = true end
				local result = Resolve(entry.anchor)
				local title = SourceTitle(entry.anchor, entry.title)
				if result then
					local from = title
					if result.anchored then
						local target = byAnchor[result.anchored]
						from = L["%s (attached to %s)"]:format(title, SourceTitle(result.anchored, target and target.title))
					end
					result.anchored = nil
					AddPoint(plan, entry.mover, result, from)
				elseif type(anchors[entry.anchor]) == "table" and GetPath(data, entry.from) then
					local targetKey = tostring(anchors[entry.anchor].target)
					local target = byAnchor[targetKey]
					table.insert(plan.notes, L["%s is attached to %s, which EldoUI can't place; EldoUI keeps its own position."]:format(title, SourceTitle(targetKey, target and target.title)))
				end
			end
		end
		-- EllesmereUI's damage meter windows: TOPLEFT corner from the screen's bottom left.
		local windows = GetPath(data, "addons.EllesmereUIDamageMeters.dm.windows")
		local first = type(windows) == "table" and windows[1]
		local pos = type(first) == "table" and first.position
		if type(pos) == "table" and type(pos.x) == "number" and type(pos.y) == "number" then
			AddPoint(plan, "EldoUI_Details", ClampPoint("TOPLEFT", "BOTTOMLEFT", pos.x * factor, pos.y * factor), L["damage meter window 1"])
		end
		local tooltip = data.tooltipFixedPos
		if type(tooltip) == "table" and type(tooltip.centerX) == "number" and type(tooltip.centerY) == "number" then
			AddPoint(plan, "EldoUI_Tooltip", ClampPoint("CENTER", "CENTER", tooltip.centerX * factor, tooltip.centerY * factor), L["Fixed tooltip position"])
		end
		table.insert(plan.notes, L["Buffs and the quest tracker are not in EllesmereUI strings (EllesmereUI leaves them to Blizzard's Edit Mode). Paste the matching Edit Mode string to place those."])
	end

	if Options().settings then
		for _, entry in ipairs(maps.euiSettings) do MapSetting(plan, entry, data) end
		MapEUIBars(plan, data)
		MapEUIDataBars(plan, data)
		MapEUIUnits(plan, data)
		MapEUIGroups(plan, data)
		MapEUICooldowns(plan, data)
		MapEUIResources(plan, data)
	end

	-- Report what wasn't used, in plain words.
	local skipped = {}
	for key, info in pairs(maps.euiSkipped) do
		if data[key] ~= nil and not (type(data[key]) == "table" and next(data[key]) == nil) then
			table.insert(plan.ignored, L["%s: not imported, %s"]:format(L[info.title], L[info.why]))
			skipped[#skipped + 1] = L[info.title]
		end
	end
	local folders = type(data.addons) == "table" and data.addons or {}
	local usedFolders = {}
	for path in pairs(plan.used) do
		local folder = path:match("^addons%.([^%.]+)%.")
		if folder then usedFolders[folder] = true end
	end
	local folderNames = {}
	for folder in pairs(folders) do table.insert(folderNames, folder) end
	table.sort(folderNames)
	for _, folder in ipairs(folderNames) do
		local info = maps.euiModules[folder]
		local title = info and L[info.title] or (folder:gsub("^EllesmereUI", ""))
		if folder == "EllesmereUIDataBars" then
			local names = {}
			for _, bar in ipairs(type(folders[folder].bars) == "table" and folders[folder].bars or {}) do
				if type(bar) == "table" and type(bar.name) == "string" then names[#names + 1] = bar.name end
			end
			if #names > 0 then title = ("%s (%s)"):format(title, table.concat(names, ", ")) end
		end
		if usedFolders[folder] then
			table.insert(plan.ignored, L["%s: positions, sizes and visibility read; the rest is EllesmereUI's own look"]:format(title))
		else
			table.insert(plan.ignored, L["%s: not imported, %s"]:format(title, info and info.why and L[info.why] or L["no matching EldoUI part"]))
			skipped[#skipped + 1] = title
		end
	end
	-- EldoUI is made for WoW: Forever: a string from another game version
	-- is read for what Forever has, and the note says what was left out.
	if source.client ~= "forever" then
		local list = #skipped > 0 and table.concat(skipped, ", ") or L["nothing else"]
		if source.client == nil then
			table.insert(plan.notes, 1, L["This string doesn't say which game it was made for. EldoUI reads it as a WoW: Forever layout: positions, sizes and visibility carry over. Skipped: %s."]:format(list))
		else
			table.insert(plan.notes, 1, L["This string was made for another version of the game (%s), not WoW: Forever. EldoUI imports what Forever has: positions, sizes and visibility. Skipped: %s."]:format(tostring(source.client), list))
		end
	end
	return plan
end

-- ElvUI ---------------------------------------------------------------------
local function MapElv(source, factor)
	local plan = NewPlan(source, factor)
	local data = source.data
	local maps = E.importMaps
	local movers = type(data.movers) == "table" and data.movers or {}

	local elvTitles = {}
	for _, pair in ipairs(maps.elvMovers) do elvTitles[pair[1]] = pair[3] end
	local function ElvTitle(key) return SourceTitle(key, elvTitles[key]) end
	if Options().positions then
		for _, pair in ipairs(maps.elvMovers) do
			local elvName, mover = pair[1], pair[2]
			local text = movers[elvName]
			if type(text) == "string" and not plan.points[mover] then
				local sep = text:find("\031", 1, true) and "\031" or ","
				local parts = {}
				for part in (text .. sep):gmatch("(.-)" .. sep) do parts[#parts + 1] = strtrim(part) end
				local point, relFrame, relPoint, x, y = parts[1], parts[2], parts[3], tonumber(parts[4]), tonumber(parts[5])
				point, relPoint = point and point:upper(), relPoint and relPoint:upper()
				if not (VALID_POINT[point] and VALID_POINT[relPoint] and x and y) then
					table.insert(plan.ignored, L["%s: position %q can't be read"]:format(ElvTitle(elvName), text))
				elseif not maps.elvScreen[relFrame] then
					table.insert(plan.notes, L["%s is attached to %s; EldoUI keeps its own position for %s."]:format(ElvTitle(elvName), SourceTitle(relFrame), L[MoverTitle(mover)]))
				else
					AddPoint(plan, mover, ClampPoint(point, relPoint, x * factor, y * factor), ElvTitle(elvName))
				end
			end
		end
		local known = {}
		for _, pair in ipairs(maps.elvMovers) do known[pair[1]] = true end
		local skipped = {}
		for name in pairs(movers) do
			if not known[name] then table.insert(skipped, ElvTitle(name)) end
		end
		table.sort(skipped)
		if #skipped > 0 then
			table.insert(plan.ignored, L["No EldoUI frame for: %s"]:format(table.concat(skipped, ", ")))
		end
		table.insert(plan.notes, L["ElvUI only exports frames you moved; every other EldoUI frame keeps its current layout position."])
	end

	if Options().settings then
		for _, entry in ipairs(maps.elvSettings) do MapSetting(plan, entry, data) end
	end

	local groups = {}
	for key in pairs(data) do
		if key ~= "movers" then table.insert(groups, key) end
	end
	table.sort(groups, function(a, b) return tostring(a) < tostring(b) end)
	for _, key in ipairs(groups) do
		local count = CountLeaves(data[key], 0)
		local read = false
		for path in pairs(plan.used) do
			if path:sub(1, #tostring(key) + 1) == tostring(key) .. "." then read = true break end
		end
		if read then
			table.insert(plan.ignored, L["%s: sizes and fonts read; its other %d settings are ElvUI's own"]:format(tostring(key), count))
		else
			table.insert(plan.ignored, L["%s: %d settings, no matching EldoUI part"]:format(tostring(key), count))
		end
	end
	return plan
end

-- The default factor that keeps physical pixel sizes: EllesmereUI stores
-- its UIParent scale; ElvUI's default scale is already pixel-perfect.
function Import.DefaultFactor(source)
	if source.kind == "eui" and source.scale then
		return math.floor(source.scale / REF_SCALE * 100 + 0.5) / 100
	end
	return 1
end

function Import.BuildPlan(source, factor)
	local target = Ingress.Context()
	factor = factor or Import.DefaultFactor(source)
	local plan
	if source.kind == "eui" then
		plan = MapEUI(source, factor)
		local problem = not plan.blocked and PointGraphProblem(plan)
		if problem then plan.points, plan.mapped, plan.blocked = {}, {}, problem end
	elseif source.kind == "elv" then plan = MapElv(source, factor) end
	if plan and target and Ingress.Context(target) and Ingress.Data(plan, {}, 0) then
		local copy = CopyTable(plan)
		if Ingress.Context(target) then Ingress.plans[plan] = { target = target, copy = copy } end
	end
	return plan
end

---------------------------------------------------------------------------
-- Imported layout presets: saved in EldoUIDB.importedLayouts, registered
-- into E.layouts as "Imported_<key>" so they fit any resolution like the
-- built-in presets (1440p reference units).
---------------------------------------------------------------------------
local function LayoutId(key) return "Imported_" .. key end

local function Finite(value)
	return type(value) == "number" and not E:IsSecret(value) and value == value and value > -math.huge and value < math.huge
end

InheritedPoint = function(point)
	if E:IsSecret(point) or type(point) ~= "table" or type(getmetatable(point)) ~= "nil" then return nil end
	for index = 1, 5 do if E:IsSecret(rawget(point, index)) then return nil end end
	if not VALID_POINT[point[1]] or not VALID_POINT[point[3]]
		or type(point[2]) ~= "string" or point[2] == "" or not Finite(point[4]) or not Finite(point[5]) then return nil end
	return { point[1], point[2], point[3], point[4], point[5] }
end

local function InheritedCondition(source)
	if E:IsSecret(source) or type(source) ~= "table" or type(getmetatable(source)) ~= "nil" then return nil end
	local out = {}
	for _, key in ipairs({ "width", "height" }) do
		if Finite(source[key]) and source[key] >= 0 then out[key] = source[key] end
	end
	if not E:IsSecret(source.of) and type(source.of) == "string" then out.of = source.of end
	if not E:IsSecret(source.style) and type(source.style) == "table" and type(getmetatable(source.style)) == "nil" then
		local style = {}
		for name, key in pairs(source.style) do
			if not E:IsSecret(name) and not E:IsSecret(key) and type(name) == "string" and type(key) == "string"
				and name:match("^%a[%w_]*$") and key:match("^%a[%w_]*$") then style[name] = key end
		end
		if next(style) then out.style = style end
	end
	return (out.width or out.height or out.style) and out or nil
end

local function InheritedDescriptor(entry, name)
	if E:IsSecret(entry) or type(entry) ~= "table" or type(getmetatable(entry)) ~= "nil" then return nil end
	local point = InheritedPoint(entry.point)
	if not point then return nil end
	local result = InheritedCondition(entry) or {}
	result.point = point
	local also = {}
	if not E:IsSecret(entry.also) and type(entry.also) == "table" and type(getmetatable(entry.also)) == "nil" then
		for _, condition in ipairs(entry.also) do
			local valid = InheritedCondition(condition)
			if valid then also[#also + 1] = valid end
		end
	end
	if #also > 0 then result.also = also end
	if not E:IsSecret(entry.cluster) and type(entry.cluster) == "boolean"
		and name == "EldoUI_WaypointArrow" and result.of == "EldoUI_Minimap" and point[2] == "UIParent" then
		result.cluster = entry.cluster
	end
	return (result.width or result.height or result.style or result.also) and result or nil
end

InheritedAdaptive = function(source, narrow)
	local out = {}
	if E:IsSecret(source) or type(source) ~= "table" or type(getmetatable(source)) ~= "nil" then return nil end
	for name, entry in pairs(type(source) == "table" and source or {}) do
		local point = not E:IsSecret(entry) and type(entry) == "table" and type(getmetatable(entry)) == "nil" and InheritedPoint(entry.point)
		if not E:IsSecret(name) and type(name) == "string" and point then
			if narrow then
				if Finite(entry.below) and entry.below > 0 then
					local result = { below = entry.below, point = point }
					result.adaptive = InheritedDescriptor(entry.adaptive, name)
					out[name] = result
				end
			else
				out[name] = InheritedDescriptor(entry, name)
			end
		end
	end
	return next(out) and out or nil
end

local function InheritedTextMap(source)
	local out = {}
	for key, value in pairs(type(source) == "table" and source or {}) do
		if type(key) == "string" and type(value) == "string" then out[key] = value end
	end
	return next(out) and out or nil
end

-- A saved snapshot keeps the native provider data, never a live reference
-- to a built-in layout. Older imports retain their original behavior.
local function InheritedMetadata(source)
	local out = { inheritanceVersion = 1 }
	for _, key in ipairs({ "baseLayout", "family", "skin", "windows", "retiredIn" }) do
		if type(source[key]) == "string" then out[key] = source[key] end
	end
	if not E:IsSecret(source.familyVersion) and type(source.familyVersion) == "boolean" then out.familyVersion = source.familyVersion end
	out.widePoints = InheritedAdaptive(source.widePoints)
	out.narrowPoints = InheritedAdaptive(source.narrowPoints, true)
	out.suggest = InheritedTextMap(source.suggest)
	local incompatible = {}
	for name, styles in pairs(type(source.incompatible) == "table" and source.incompatible or {}) do
		if type(name) == "string" then incompatible[name] = InheritedTextMap(styles) end
	end
	out.incompatible = next(incompatible) and incompatible or nil
	local art = {}
	for _, entry in ipairs(type(source.artOptions) == "table" and source.artOptions or {}) do
		if type(entry) == "table" and type(entry.skin) == "string" then
			art[#art + 1] = { skin = entry.skin, windows = type(entry.windows) == "string" and entry.windows or nil }
		end
	end
	out.artOptions = #art > 0 and art or nil
	local roles = {}
	for role, points in pairs(type(source.rolePoints) == "table" and source.rolePoints or {}) do
		if E.roleProfiles and E.roleProfiles[role] and type(points) == "table" then
			roles[role] = {}
			for name, point in pairs(points) do
				if type(name) == "string" then roles[role][name] = InheritedPoint(point) end
			end
		end
	end
	out.rolePoints = roles
	return out
end

function Ingress.Registry(root, store, registry, order)
	return Ingress.Plain(root) and Ingress.Plain(store) and not E.Secret(E.Import) and E.Import == Import
		and not E.Secret(ReadAccountRoot()) and ReadAccountRoot() == root
		and not E.Secret(rawget(root, "importedLayouts")) and rawget(root, "importedLayouts") == store
		and not E.Secret(registry) and type(registry) == "table" and not E.Secret(E.layouts) and E.layouts == registry
		and Ingress.Plain(order) and not E.Secret(E.layoutOrder) and E.layoutOrder == order
end

function Ingress.Builtin(key)
	if E.Secret(key) or type(key) ~= "string" or not Ingress.Plain(E.layoutFamilies) then return false end
	local resolve = E.FamilyLayoutKey
	if E.Secret(resolve) or type(resolve) ~= "function" then return false end
	for _, slot in ipairs(E.layoutFamilies) do
		if not Ingress.Plain(slot) or E.Secret(slot.key) or type(slot.key) ~= "string" then return false end
		local ok, current = pcall(resolve, E, slot.key)
		if not ok or E.Secret(current) then return false end
		if current == key and not E.Secret(E.FamilyLayoutKey) and E.FamilyLayoutKey == resolve then return true end
	end
	return false
end

function Ingress.Record(saved, store, key, visiting, dependencies)
	if not Ingress.Plain(saved) or not Ingress.Data(saved, {}, 0) or saved.profileBaseline ~= E.PROFILE_BASELINE
		or saved.recordVersion ~= 1 or type(saved.title) ~= "string" or type(saved.desc) ~= "string"
		or (saved.source ~= "eui" and saved.source ~= "elv") or saved.retiredIn ~= nil or not Ingress.Plain(saved.points) then return false end
	local fields = { profileBaseline = true, recordVersion = true, baseLayout = true, title = true, desc = true,
		accent = true, points = true, modules = true, hidden = true, source = true, inheritanceVersion = true,
		family = true, skin = true, windows = true, familyVersion = true, widePoints = true, narrowPoints = true,
		suggest = true, incompatible = true, artOptions = true, rolePoints = true }
	for field in pairs(saved) do if not fields[field] then return false end end
	if saved.accent ~= nil and type(saved.accent) ~= "string" then return false end
	if saved.modules ~= nil then
		if not Ingress.Plain(saved.modules) then return false end
		for name, values in pairs(saved.modules) do if type(name) ~= "string" or not Ingress.Plain(values) then return false end end
	end
	if saved.hidden ~= nil then
		if not Ingress.Plain(saved.hidden) then return false end
		local count, seen = 0, {}
		for index, name in pairs(saved.hidden) do
			if type(index) ~= "number" or index < 1 or index % 1 ~= 0 or type(name) ~= "string" or seen[name] then return false end
			seen[name], count = true, count + 1
		end
		for index = 1, count do if type(saved.hidden[index]) ~= "string" then return false end end
	end
	if saved.inheritanceVersion ~= nil and saved.inheritanceVersion ~= 1 then return false end
	local metadata = saved.inheritanceVersion == 1 and InheritedMetadata(saved) or {}
	for _, field in ipairs({ "family", "skin", "windows", "familyVersion", "widePoints", "narrowPoints", "suggest", "incompatible", "artOptions", "rolePoints" }) do
		if not E.DeepEqual(metadata[field], saved[field]) then return false end
	end
	if visiting[key] then return false end
	visiting[key], dependencies[key] = true, saved
	for name, point in pairs(saved.points) do
		if type(name) ~= "string" or not E.DeepEqual(InheritedPoint(point), point) then visiting[key] = nil; return false end
	end
	for _, field in ipairs({ "widePoints", "narrowPoints" }) do
		local value = saved[field]
		if value ~= nil and (not Ingress.Plain(value) or not E.DeepEqual(InheritedAdaptive(value, field == "narrowPoints"), value)) then visiting[key] = nil; return false end
	end
	local roles = saved.rolePoints or {}
	if not Ingress.Plain(roles) then visiting[key] = nil; return false end
	for role, points in pairs(roles) do
		if type(role) ~= "string" or not Ingress.Plain(points) then visiting[key] = nil; return false end
		for name, point in pairs(points) do
			if type(name) ~= "string" or not E.DeepEqual(InheritedPoint(point), point) then visiting[key] = nil; return false end
		end
	end
	if saved.baseLayout ~= nil and not Ingress.Builtin(saved.baseLayout) then
		local parent = type(saved.baseLayout) == "string" and saved.baseLayout:match("^Imported_(.+)$")
		local record = parent and rawget(store, parent)
		if not parent or not Ingress.Record(record, store, parent, visiting, dependencies) then visiting[key] = nil; return false end
	end
	local problem = PointGraphProblem({ source = { kind = "eui", version = 4 }, points = {} },
		{ key = LayoutId(key), layout = saved, roles = roles })
	visiting[key] = nil
	return problem == nil
end

function Ingress.Descriptor(saved)
	local layout = {
		title = saved.title, desc = saved.desc, accent = saved.accent,
		points = saved.points, refHeight = 1440, imported = true,
		-- Sizes, bar shapes and visibility the string sets, and the
		-- frames it switches off: applied like a built-in layout's.
		modules = type(saved.modules) == "table" and saved.modules or nil,
		hidden = type(saved.hidden) == "table" and saved.hidden or nil,
	}
	if saved.inheritanceVersion == 1 then
		for field, value in pairs(InheritedMetadata(saved)) do layout[field] = value end
	end
	return layout
end

-- A saved dependency and its registered view are separate owner bindings.
function Ingress.View(own, view, key, record)
	if not Ingress.Plain(view) then return false end
	local bound = Ingress.layouts[view]
	return bound and bound.root == own.root and bound.store == own.store and bound.registry == own.registry
		and bound.order == own.order and bound.key == key and bound.saved == record
		and not E.Secret(rawget(own.store, key)) and rawget(own.store, key) == record
		and E.DeepEqual(bound.copy, record) and E.DeepEqual(bound.layoutCopy, view)
end

function Ingress.BindViews(layout)
	local own = Ingress.layouts[layout]
	if not own or not Ingress.Registry(own.root, own.store, own.registry, own.order) then return false end
	local views = {}
	for key, record in pairs(own.dependencies) do
		local view = rawget(own.registry, LayoutId(key))
		if not Ingress.View(own, view, key, record) then return false end
		views[key] = view
	end
	if not Ingress.Registry(own.root, own.store, own.registry, own.order) then return false end
	for key, view in pairs(views) do
		if E.Secret(rawget(own.registry, LayoutId(key))) or rawget(own.registry, LayoutId(key)) ~= view then return false end
	end
	own.views = views
	return true
end

local function RegisterLayout(key, saved)
	if E.Secret(key) or E.Secret(saved) then return nil end
	local root = ReadAccountRoot()
	local store = Ingress.Plain(root) and rawget(root, "importedLayouts")
	if not Ingress.Plain(store) or type(key) ~= "string" or rawget(store, key) ~= saved then return nil end
	local registry, order = E.layouts, E.layoutOrder
	if not Ingress.Registry(root, store, registry, order) then return nil end
	local dependencies = {}
	if not Ingress.Record(saved, store, key, {}, dependencies) or not Ingress.Registry(root, store, registry, order) then return nil end
	local id = LayoutId(key)
	local priorView = rawget(E.layouts, id)
	if E.Secret(priorView) or (type(priorView) ~= "nil" and not Ingress.layouts[priorView]) then return nil end
	local layout = Ingress.Descriptor(saved)
	local copies = {}
	for dependency, record in pairs(dependencies) do copies[dependency] = CopyTable(record) end
	Ingress.layouts[layout] = { root = root, store = store, key = key, saved = saved, registry = E.layouts,
		order = E.layoutOrder, copy = CopyTable(saved), layoutCopy = CopyTable(layout), dependencies = dependencies, copies = copies }
	E.layouts[id] = layout
	Ingress.BindViews(layout)
	for _, existing in ipairs(E.layoutOrder) do
		if existing == id then return id end
	end
	table.insert(E.layoutOrder, id)
	return id
end

function Import.RegisterImportedLayouts()
	local root = ReadAccountRoot()
	if not Ingress.Plain(root) or E.Secret(root.profileBaseline) or root.profileBaseline ~= E.PROFILE_BASELINE then return 0 end
	local store = rawget(root, "importedLayouts")
	local registry, order = E.layouts, E.layoutOrder
	if not Ingress.Registry(root, store, registry, order) then return 0 end
	-- Drop only this owner's private views; foreign replacements stay untouched.
	for id, layout in pairs(E.layouts) do
		local own = not E.Secret(layout) and Ingress.layouts[layout]
		if own and not E.Secret(id) and type(id) == "string" and id == LayoutId(own.key) and own.registry == E.layouts then
			E.layouts[id] = nil
			for index = #E.layoutOrder, 1, -1 do if E.layoutOrder[index] == id then table.remove(E.layoutOrder, index) end end
		end
	end
	local count = 0
	for key, saved in pairs(store) do
		if not E.Secret(key) and type(key) == "string" and RegisterLayout(key, saved) then count = count + 1 end
		if not Ingress.Registry(root, store, registry, order) then return count end
	end
	-- Store iteration is unordered. Bind the completed registered dependency
	-- set only after every staged record has had its registration attempt.
	for _, layout in pairs(registry) do
		local own = not E.Secret(layout) and Ingress.layouts[layout]
		if own and own.registry == registry and own.root == root then Ingress.BindViews(layout) end
		if not Ingress.Registry(root, store, registry, order) then return count end
	end
	return count
end

function Ingress.CurrentLayout(id)
	if E.Secret(Import.CurrentLayout) or Import.CurrentLayout ~= Ingress.CurrentLayout then return nil end
	local target = Ingress.Context()
	if not target or E.Secret(id) or type(id) ~= "string" or E.Secret(E.layouts) or type(E.layouts) ~= "table" then return nil end
	local layout = rawget(E.layouts, id)
	local own = not E.Secret(layout) and Ingress.layouts[layout]
	if not own or own.root ~= target.root or E.layouts ~= own.registry or E.Secret(E.layoutOrder) or E.layoutOrder ~= own.order
		or E.Secret(rawget(target.root, "importedLayouts")) or rawget(target.root, "importedLayouts") ~= own.store
		or E.Secret(rawget(own.store, own.key)) or rawget(own.store, own.key) ~= own.saved or LayoutId(own.key) ~= id then return nil end
	local dependencies = {}
	if not Ingress.Record(own.saved, own.store, own.key, {}, dependencies) or not Ingress.Plain(layout)
		or not E.DeepEqual(own.copy, own.saved) or not E.DeepEqual(own.layoutCopy, layout) then return nil end
	if not own.views then return nil end
	for key, record in pairs(own.dependencies) do
		local view = rawget(own.registry, LayoutId(key))
		if E.Secret(view) or view ~= own.views[key] or not Ingress.View(own, view, key, record)
			or rawget(dependencies, key) ~= record or not E.DeepEqual(own.copies[key], record) then return nil end
	end
	for key, record in pairs(dependencies) do if rawget(own.dependencies, key) ~= record then return nil end end
	if not Ingress.Context(target) or E.Secret(Import.CurrentLayout) or Import.CurrentLayout ~= Ingress.CurrentLayout
		or E.Secret(rawget(E.layouts, id)) or rawget(E.layouts, id) ~= layout then return nil end
	for key, view in pairs(own.views) do
		if E.Secret(rawget(own.registry, LayoutId(key))) or rawget(own.registry, LayoutId(key)) ~= view then return nil end
	end
	return layout
end
Import.CurrentLayout = Ingress.CurrentLayout


-- Native strings carry only the selected saved layout and its base chain.
-- A detached description never becomes registered-layout authority.
function Ingress.Closure(envelope)
	if not Ingress.Plain(envelope) or not Ingress.Data(envelope, {}, 0) or envelope.version ~= 1
		or type(envelope.layout) ~= "string" or not Ingress.Plain(envelope.records) then return nil end
	for field in pairs(envelope) do if field ~= "version" and field ~= "layout" and field ~= "records" then return nil end end
	local key = envelope.layout:match("^Imported_(.+)$")
	if not key then return nil end
	local reached, visiting = {}, {}
	local function Walk(name, depth)
		if depth > MAX_DEPTH or visiting[name] then return false end
		if reached[name] then return true end
		local saved = rawget(envelope.records, name)
		if not Ingress.Plain(saved) then return false end
		visiting[name] = true
		local base = rawget(saved, "baseLayout")
		if type(base) ~= "nil" and not Ingress.Builtin(base) then
			local parent = type(base) == "string" and base:match("^Imported_(.+)$")
			if not parent or not Walk(parent, depth + 1) then return false end
		end
		visiting[name], reached[name] = nil, saved
		return true
	end
	if not Walk(key, 1) then return nil end
	for name in pairs(envelope.records) do if type(name) ~= "string" or not reached[name] then return nil end end
	if not Ingress.Record(reached[key], envelope.records, key, {}, {}) then return nil end
	return key, reached
end

function Import.CaptureLayoutDependencies(id)
	local target = Ingress.Context()
	if not target or E.Secret(id) or type(id) ~= "string" then return nil end
	if Ingress.Builtin(id) then return nil end
	local view = Ingress.CurrentLayout(id)
	local own = view and Ingress.layouts[view]
	if not own then return nil end
	local records = {}
	for key, saved in pairs(own.dependencies) do records[key] = CopyTable(saved) end
	local envelope = { version = 1, layout = id, records = records }
	if not Ingress.Closure(envelope) or not Ingress.Context(target) or Ingress.CurrentLayout(id) ~= view then return nil end
	return envelope
end

function Import.PrepareLayoutDependencies(envelope)
	local target = Ingress.Context()
	if not target or not Ingress.Plain(envelope) or not Ingress.Data(envelope, {}, 0) then return nil end
	local copy = CopyTable(envelope)
	local key = Ingress.Closure(copy)
	local store = rawget(target.root, "importedLayouts")
	if not key or E.Secret(store) or (type(store) ~= "nil" and not Ingress.Plain(store))
		or not Ingress.Context(target) or not E.DeepEqual(copy, envelope) then return nil end
	local plan = { layout = copy.layout, records = copy.records, layoutData = Ingress.Descriptor(copy.records[key]) }
	Ingress.plans[plan] = { kind = "layout-dependencies", target = target, copy = CopyTable(plan), source = envelope,
		sourceCopy = copy, store = store, registry = E.layouts, order = E.layoutOrder }
	return plan
end

function Import.ApplyLayoutDependencies(plan)
	if InCombatLockdown() or not Ingress.Plain(plan) then return false end
	local own = Ingress.plans[plan]
	if not own or own.kind ~= "layout-dependencies" or own.used or not Ingress.Context(own.target)
		or not Ingress.Data(plan, {}, 0) or not E.DeepEqual(plan, own.copy)
		or not Ingress.Data(own.source, {}, 0) or not E.DeepEqual(own.source, own.sourceCopy) then return false end
	local target = own.target
	local function Current()
		return Ingress.Context(target) and not E.Secret(E.layouts) and E.layouts == own.registry
			and not E.Secret(E.layoutOrder) and E.layoutOrder == own.order
			and not E.Secret(rawget(target.root, "importedLayouts")) and rawget(target.root, "importedLayouts") == own.store
	end
	if not Current() or not Ingress.Closure(own.sourceCopy) then return false end
	local store, keys, mapping, records = own.store or {}, {}, {}, {}
	for key in pairs(own.copy.records) do keys[#keys + 1] = key end
	table.sort(keys)
	for _, key in ipairs(keys) do
		local candidate, index = key, 2
		while true do
			local saved, view = rawget(store, candidate), rawget(own.registry, LayoutId(candidate))
			if E.Secret(saved) or E.Secret(view) then return false end
			if type(saved) == "nil" and type(view) == "nil" and not records[candidate] then break end
			candidate, index = key .. index, index + 1
		end
		mapping[key], records[candidate] = candidate, CopyTable(own.copy.records[key])
	end
	for _, record in pairs(records) do
		local base = type(record.baseLayout) == "string" and record.baseLayout:match("^Imported_(.+)$")
		if base then
			if not mapping[base] then return false end
			record.baseLayout = LayoutId(mapping[base])
		end
	end
	local rootKey = own.copy.layout:match("^Imported_(.+)$")
	local id = LayoutId(mapping[rootKey])
	if not Ingress.Closure({ version = 1, layout = id, records = records }) or not Current() then return false end
	for key in pairs(records) do
		if E.Secret(rawget(store, key)) or type(rawget(store, key)) ~= "nil"
			or E.Secret(rawget(own.registry, LayoutId(key))) or type(rawget(own.registry, LayoutId(key))) ~= "nil" then return false end
	end
	own.used = true
	if not own.store then target.root.importedLayouts = store; own.store = store end
	for key, record in pairs(records) do
		if not Current() then return false end
		store[key] = record
	end
	for key, record in pairs(records) do
		if not Current() or not RegisterLayout(key, record) then return false end
	end
	for key in pairs(records) do
		if not Current() or not Ingress.BindViews(rawget(own.registry, LayoutId(key))) then return false end
	end
	local view = Ingress.CurrentLayout(id)
	if not view or not Current() then return false end
	return true, id, view
end

local function LayoutInUse(id)
	for _, profile in pairs(EldoUIDB.profiles or {}) do
		if not Ingress.Plain(profile) then return true end
		local general = rawget(profile, "general")
		if E.Secret(general) or (type(general) ~= "nil" and not Ingress.Plain(general)) then return true end
		if general then
			local key = rawget(general, "layout")
			if E.Secret(key) then return true end
			if key == id then return true end
		end
	end
	local store = rawget(EldoUIDB, "importedLayouts")
	if not Ingress.Plain(store) then return true end
	for _, saved in pairs(store) do
		if not Ingress.Plain(saved) or E.Secret(rawget(saved, "baseLayout")) then return true end
		if rawget(saved, "baseLayout") == id then return true end
	end
	local function History(records)
		if type(records) == "nil" then return false end
		if not Ingress.Plain(records) or not Ingress.Data(records, {}, 0) then return true end
		for _, record in pairs(records) do
			if not Ingress.Plain(record) then return true end
			if record.layout == id then return true end
			for _, field in ipairs({ "before", "after" }) do
				local side = record[field]
				if not Ingress.Plain(side) or not Ingress.Plain(side.general) then return true end
				if side.general.layout == id then return true end
			end
		end
		return false
	end
	if History(E.setupHistory) then return true end
	local history = rawget(EldoUIDB, "setupHistory")
	if E.Secret(history) or (type(history) ~= "nil" and not Ingress.Plain(history)) then return true end
	for _, part in pairs(history or {}) do
		if not Ingress.Plain(part) or History(part.records) then return true end
	end
	return false
end

function Ingress.Remove(target, id, saved)
	if not Ingress.Context(target) or E.Secret(id) or type(id) ~= "string" then return false end
	local layout = Ingress.CurrentLayout(id)
	local own = layout and Ingress.layouts[layout]
	if not own or own.saved ~= saved or LayoutInUse(id) or not Ingress.Context(target) then return false end
	own.store[own.key], E.layouts[id] = nil, nil
	Ingress.layouts[layout] = nil
	for index = #E.layoutOrder, 1, -1 do if E.layoutOrder[index] == id then table.remove(E.layoutOrder, index) end end
	return true
end

-- Removes only current, unused layouts this owner registered. Unknown data stays.
function E:ForgetUnusedImportedLayouts()
	local target = Ingress.Context()
	if not target then return 0 end
	local store = rawget(target.root, "importedLayouts")
	if not Ingress.Plain(store) then return 0 end
	local removed = 0
	for key, saved in pairs(store) do
		if not E.Secret(key) and type(key) == "string" and Ingress.Remove(target, LayoutId(key), saved) then removed = removed + 1 end
		if not Ingress.Context(target) then return removed end
	end
	return removed
end

-- Layouts must exist before the profile that uses them positions frames,
-- so register them right after the saved variables load.
E:OnDatabaseLoad(function() Import.RegisterImportedLayouts() end, "before")

---------------------------------------------------------------------------
-- Applying a plan. The plan becomes an imported layout preset (frame
-- points, the module settings it sets and the frames it switches off),
-- applied like a built-in layout. Two ways, both with Undo:
--   "new"      a NEW profile that uses the layout; the current profile
--              stays as it is (Undo removes the new profile)
--   "current"  the current profile takes the layout (Undo puts back the
--              copy of the profile saved just before)
---------------------------------------------------------------------------
local function UniqueProfileName(name)
	name = strtrim(name or "")
	if name == "" then name = L["Imported"] end
	if not EldoUIDB.profiles[name] then return name end
	local index = 2
	while EldoUIDB.profiles[("%s (%d)"):format(name, index)] do index = index + 1 end
	return ("%s (%d)"):format(name, index)
end

local function UniqueLayoutKey(name, store)
	local base = name:gsub("[^%w]", "")
	if base == "" then base = "Layout" end
	local key, index = base, 2
	while rawget(store, key) or rawget(E.layouts, LayoutId(key)) do
		key = base .. index
		index = index + 1
	end
	return key
end

-- Saves and registers the imported layout of `plan`, built on the
-- current layout (frames the string doesn't place keep its points).
-- Returns the layout id, the General settings (they belong to the
-- profile, not the layout) and the counts for the alert.
local function SaveLayout(plan, name, inheritance, store, target)
	local currentKey = inheritance and inheritance.key or (E.EffectiveLayout and E:EffectiveLayout() or E.db.general.layout)
	if not Ingress.Builtin(currentKey) and not Ingress.CurrentLayout(currentKey) then return nil end
	local current = inheritance and inheritance.layout or E.layouts[currentKey]
	local inherit = plan.source.kind == "eui"
	local points, positions = CopyTable(current and current.points or {}), 0
	for mover, point in pairs(plan.points) do
		points[mover] = CopyTable(point)
		positions = positions + 1
	end
	local modules = inherit and CopyTable(current and current.modules or {}) or {}
	local explicit, general, settings = {}, {}, 0
	for _, entry in ipairs(plan.settings) do
		if entry.module == "general" then
			general[#general + 1] = entry
		else
			modules[entry.module] = modules[entry.module] or {}
			E.SetPath(modules[entry.module], entry.key, type(entry.value) == "table" and CopyTable(entry.value) or entry.value)
			explicit[entry.module] = explicit[entry.module] or {}
			E.SetPath(explicit[entry.module], entry.key, entry.value)
		end
		settings = settings + 1
	end
	local hiddenSet = {}
	for _, mover in ipairs(inherit and current and current.hidden or {}) do
		local holder = E.movers[mover]
		local path = holder and holder.enabledPath
		local shown = plan.shown and plan.shown[mover]
		if not shown and path and explicit[holder.module] then
			shown = GetPath(explicit[holder.module], table.concat(path, ".")) == true
			-- An action bar's Shown switch: turning the bar On shows it too.
			if not shown and path[#path] == "shown" then
				local on = { unpack(path) }
				on[#on] = "enabled"
				shown = GetPath(explicit[holder.module], table.concat(on, ".")) == true
			end
		end
		if not shown then hiddenSet[mover] = true end
	end
	for mover in pairs(plan.hidden or {}) do hiddenSet[mover] = true end
	local hidden = {}
	for mover in pairs(hiddenSet) do hidden[#hidden + 1] = mover end
	table.sort(hidden)
	settings = settings + #hidden
	local key = UniqueLayoutKey(name, store)
	local saved = {
		profileBaseline = target.profile.profileBaseline, recordVersion = 1, baseLayout = currentKey,
		title = L["%s (imported)"]:format(name),
		desc = L["Imported from %s on %s. Frames the string didn't place keep the %s positions."]:format(
			plan.source.title, E:ShortDay(time(), true), current and current.title or L["layout"]),
		accent = current and current.accent or "33AAFF",
		points = points,
		modules = next(modules) and modules or nil,
		hidden = #hidden > 0 and hidden or nil,
		source = plan.source.kind,
	}
	if inherit then
		local metadata = InheritedMetadata(current or {})
		metadata.baseLayout = currentKey
		metadata.family = E.LayoutFamily and E:LayoutFamily(currentKey) or metadata.family
		metadata.rolePoints = {}
		for role in pairs(inheritance and inheritance.roles or E.roleProfiles or {}) do
			local inherited = inheritance and inheritance.roles[role] or E:GetRolePoints(role, currentKey)
			metadata.rolePoints[role] = {}
			for mover, point in pairs(inherited) do
				if not plan.points[mover] then metadata.rolePoints[role][mover] = InheritedPoint(point) end
			end
		end
		for mover in pairs(plan.points) do
			if metadata.narrowPoints then metadata.narrowPoints[mover] = nil end
			if metadata.widePoints then metadata.widePoints[mover] = nil end
		end
		for field, value in pairs(metadata) do saved[field] = value end
	end
	return saved, key, general, positions, settings
end

local function RefreshAll(target)
	for _, name in ipairs({ "UpdateAccent", "RefreshTheme", "RefreshMovers", "RefreshConfig" }) do
		if not Ingress.Context(target) then return false end
		local fn = E[name]
		if E.Secret(fn) or (type(fn) ~= "nil" and type(fn) ~= "function") then return false end
		if fn then fn(E) end
		if not Ingress.Context(target) or E.Secret(E[name]) or E[name] ~= fn then return false end
	end
	return true
end

-- One wording for every import refused in combat.
function Import.CombatText()
	return L["Imports wait until you leave combat. Nothing was changed."]
end

-- Where a result goes: the window's toast when `notify` is given (a click
-- in the import window), else the chat (slash commands).
local function Tell(notify, text, warn)
	if notify then notify(text, warn) else E:Print(text) end
end

-- `mode` is "new" (the default) or "current". Refused in combat: every
-- module moves, shows and hides protected frames when a layout applies.
-- Returns false and the reason when nothing was applied.
function Import.ApplyPlan(plan, profileName, mode, notify)
	if InCombatLockdown() then Tell(notify, Import.CombatText(), true); return false, Import.CombatText() end
	if not Ingress.Plain(plan) then return false, "no plan" end
	local binding = Ingress.plans[plan]
	if not binding or binding.kind ~= nil or not Ingress.Context(binding.target) or not Ingress.Data(plan, {}, 0)
		or not E.DeepEqual(plan, binding.copy) then return false, "no profile" end
	local target = binding.target
	if E.Secret(profileName) or (type(profileName) ~= "nil" and type(profileName) ~= "string") then return false, "no profile" end
	if E.Secret(mode) or (mode ~= nil and mode ~= "new" and mode ~= "current") then return false, "no profile" end
	plan = CopyTable(binding.copy)
	if not Ingress.Plain(plan.mapped) or #plan.mapped == 0 then return false, L["nothing in it maps to EldoUI"] end
	local problem, inheritance
	if plan.blocked then problem = plan.blocked else problem, inheritance = PointGraphProblem(plan) end
	if not Ingress.Context(target) then return false, "no profile" end
	if problem then Tell(notify, problem, true); return false, problem end
	local previous, source = target.name, target.profile
	local copy = E.CopyProfileTable
	if E.Secret(copy) or type(copy) ~= "function" then return false, "no profile" end
	local snapshot = copy(E, previous)
	if not Ingress.Context(target) or E.Secret(E.CopyProfileTable) or E.CopyProfileTable ~= copy or not Ingress.Snapshot(snapshot, target) then return false, "no profile" end
	local name, profile = previous, nil
	local setter = E.SetProfile
	if mode ~= "current" then
		local check = E.CheckProfileName
		if E.Secret(check) or type(check) ~= "function" or E.Secret(setter) or type(setter) ~= "function" then return false, "no profile" end
		local asked = check(E, profileName)
		if not Ingress.Context(target) or E.Secret(asked) or (type(asked) ~= "nil" and type(asked) ~= "string")
			or E.Secret(E.CheckProfileName) or E.CheckProfileName ~= check then return false, "no profile" end
		name = UniqueProfileName(asked or L["Imported"])
		profile = CopyTable(snapshot)
		profile.movers = {}
	end
	local layoutName = name
	if mode == "current" then layoutName = strtrim(profileName or "") ~= "" and strtrim(profileName) or plan.source.title end
	local originalStore = rawget(target.root, "importedLayouts")
	if E.Secret(originalStore) or (type(originalStore) ~= "nil" and not Ingress.Plain(originalStore)) then return false, "no profile" end
	local store = originalStore or {}
	local saved, key, general, positions, settings = SaveLayout(plan, layoutName, inheritance, store, target)
	if not Ingress.Context(target) or not Ingress.Record(saved, store, key, {}, {}) then return false, "no profile" end
	if profile then
		if E.Secret(E.SetProfile) or E.SetProfile ~= setter or rawget(target.profiles, name) ~= nil or InCombatLockdown() then return false, "no profile" end
		target.profiles[name] = profile
		local changed = setter(E, name, true)
		local nextTarget = Ingress.Context()
		if E.Secret(changed) or changed ~= true or not nextTarget or nextTarget.root ~= target.root or nextTarget.profiles ~= target.profiles
			or nextTarget.name ~= name or nextTarget.profile ~= profile or E.Secret(E.SetProfile) or E.SetProfile ~= setter then return false, "no profile" end
		target = nextTarget
	end
	if not Ingress.Context(target) or E.Secret(rawget(target.root, "importedLayouts"))
		or rawget(target.root, "importedLayouts") ~= originalStore or rawget(store, key) ~= nil or InCombatLockdown() then return false, "no profile" end
	if not originalStore then target.root.importedLayouts = store end
	store[key] = saved
	local id = RegisterLayout(key, saved)
	local layout = id and Ingress.CurrentLayout(id)
	if not layout or not Ingress.Context(target) then return false, "no profile" end
	local apply = E.ApplySetup
	if E.Secret(apply) or type(apply) ~= "function" then return false, "no profile" end
	local applied, status = apply(E, { layout = id, look = "keep", resetPositions = true, source = "import", silent = true, undo = false })
	if E.Secret(applied) or applied ~= true or not Ingress.Context(target) or E.Secret(E.ApplySetup) or E.ApplySetup ~= apply
		or Ingress.CurrentLayout(id) ~= layout or E.Secret(E.db.general.layout) or E.db.general.layout ~= id then return false, status end
	local setPath = E.SetPath
	if E.Secret(setPath) or type(setPath) ~= "function" then return false, "no profile" end
	for _, entry in ipairs(general) do
		if not Ingress.Context(target) or Ingress.CurrentLayout(id) ~= layout or E.Secret(E.SetPath) or E.SetPath ~= setPath then return false, "no profile" end
		setPath(target.general, entry.key, entry.value)
	end
	if not Ingress.Context(target) or not RefreshAll(target) then return false, "no profile" end
	local alert = { key = "import-undo", title = L["Import"], options = { page = "share" } }
	local counts = E:Plural(positions, "%d position", "%d positions"):format(positions) .. ", "
		.. E:Plural(settings, "%d setting", "%d settings"):format(settings)
	if mode == "current" then
		alert.text = L["Your profile %s now uses the layout %s from %s: %s."]:format(
			E:Highlight(name), E:Highlight(layout.title), plan.source.title, counts)
		alert.actions = {
			{ label = L["Undo"], tip = L["Put your profile %s back the way it was before the import."]:format(name),
				func = function() E:RunOutOfCombat(function() Import.UndoChange(name, snapshot, target, id, saved) end, "Import:undo") end },
			{ label = L["Keep"] },
		}
	else
		alert.text = L["Imported %s into the new profile %s: %d positions, %d settings. Your profile %s is unchanged."]:format(
			plan.source.title, E:Highlight(name), positions, settings, E:Highlight(previous))
		alert.actions = {
			{ label = L["Undo"], tip = L["Go back to your profile %s and remove the imported profile."]:format(previous),
				func = function() E:RunOutOfCombat(function() Import.Undo(name, previous, target, id, saved, source) end, "Import:undo") end },
			{ label = L["Keep"] },
		}
	end
	if not Ingress.Context(target) then return false, "no profile" end
	E:PushAlert(alert)
	if not Ingress.Context(target) then return false, "no profile" end
	E:ShowReloadPrompt(L["Imported %s into profile %s. A reload applies everything."]:format(plan.source.title, name))
	return Ingress.Context(target) ~= nil, name, id
end

-- Undo of "new": back to the profile used before, the imported profile
-- removed, and its layout too once no profile uses it.
function Ingress.Snapshot(data, target)
	if not Ingress.Source(data, target) or not Ingress.Data(data, {}, 0) then return false end
	local general = rawget(data, "general")
	if type(general) ~= "nil" and not Ingress.Plain(general) then return false end
	local key = general and rawget(general, "layout")
	if type(key) == "nil" then key = E.defaults.general.layout end
	return Ingress.Builtin(key) or Ingress.CurrentLayout(key) ~= nil
end

function Ingress.Rebind(target, data)
	if not Ingress.Context(target) or not Ingress.Snapshot(data, target) then return nil end
	local copy = CopyTable(data)
	if not Ingress.Context(target) then return nil end
	local root, profiles, name, loader = target.root, target.profiles, target.name, target.loader
	local keys, private, character, mine = rawget(root, "profileKeys"), rawget(root, "private"), E.charKey, E.private
	profiles[name] = copy
	-- This owner has intentionally replaced its exact active slot. Rebind
	-- through the real database loader before any profile or store operation.
	if E.Secret(ReadAccountRoot()) or ReadAccountRoot() ~= root or E.Secret(E.db) or E.db ~= target.profile
		or E.Secret(E.profileName) or E.profileName ~= name or E.Secret(rawget(root, "profiles")) or rawget(root, "profiles") ~= profiles
		or E.Secret(rawget(profiles, name)) or rawget(profiles, name) ~= copy or E.Secret(E.LoadDatabase) or E.LoadDatabase ~= loader
		or E.Secret(rawget(root, "profileKeys")) or rawget(root, "profileKeys") ~= keys or E.Secret(rawget(root, "private")) or rawget(root, "private") ~= private
		or E.Secret(E.charKey) or E.charKey ~= character or E.Secret(E.private) or E.private ~= mine then return nil end
	local loaded = loader(E)
	local current = Ingress.Context()
	if E.Secret(loaded) or loaded ~= true or not current or current.root ~= root or current.profiles ~= profiles
		or current.profile ~= copy or current.name ~= name or current.loader ~= loader then return nil end
	return current
end

function Import.Undo(name, previous, target, id, saved, source)
	if InCombatLockdown() then return false end
	target = Ingress.Context(target)
	if not target or E.Secret(name) or name ~= target.name or E.Secret(previous) or type(previous) ~= "string"
		or E.Secret(source) or E.Secret(id) or E.Secret(saved) then return false end
	local before = rawget(target.profiles, previous)
	if E.Secret(before) or (source and before ~= source) then return false end
	local ok, supported = pcall(target.admit, E, before, previous)
	if not ok or E.Secret(supported) or supported ~= true or not Ingress.Context(target) then return false end
	local setter = E.SetProfile
	if E.Secret(setter) or type(setter) ~= "function" then return false end
	local changed = setter(E, previous, true)
	local current = Ingress.Context()
	if E.Secret(changed) or changed ~= true or not current or current.root ~= target.root or current.profiles ~= target.profiles
		or current.name ~= previous or current.profile ~= before or E.Secret(E.SetProfile) or E.SetProfile ~= setter
		or E.Secret(rawget(current.profiles, name)) or rawget(current.profiles, name) ~= target.profile then return false end
	if not E:DeleteProfile(name) or not Ingress.Context(current) then return false end
	if id then Ingress.Remove(current, id, saved) end
	return RefreshAll(current)
end

-- Undo restores a supported current snapshot through the actual load owner.
function Import.UndoChange(name, snapshot, target, id, saved)
	if InCombatLockdown() then return false end
	target = Ingress.Context(target)
	if not target or E.Secret(name) or name ~= target.name or E.Secret(id) or E.Secret(saved) then return false end
	local current = Ingress.Rebind(target, snapshot)
	if not current then return false end
	if id then Ingress.Remove(current, id, saved) end
	return RefreshAll(current)
end

---------------------------------------------------------------------------
-- Blizzard Edit Mode
---------------------------------------------------------------------------
local systemNames
local function SystemName(system, index)
	if not systemNames then
		systemNames = {}
		for name, value in pairs(Enum.EditModeSystem or {}) do systemNames[value] = name end
	end
	local name = systemNames[system] or L["System %s"]:format(tostring(system))
	if type(index) == "number" and index > 0 then name = ("%s %d"):format(name, index) end
	return name
end

local POINT_NAMES = { [0] = "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }

local function NumPresets()
	return Enum.EditModePresetLayoutsMeta and Enum.EditModePresetLayoutsMeta.NumValues or 2
end

local function MaxLayouts()
	return Constants and Constants.EditModeConsts and Constants.EditModeConsts.EditModeMaxLayoutsPerType or 5
end

-- Why EldoUI can't add a layout to Edit Mode right now, or nil.
function Import.EditModeBlocker(name)
	if InCombatLockdown() then return L["you are in combat"] end
	if not E:BlizzardAllowed("edit-mode", "improve") then
		return L["Blizzard UI > Edit Mode integration needs \"Let EldoUI change this\" and Improve switched on (or use Copy for Edit Mode)"]
	end
	if not (C_EditMode and C_EditMode.GetLayouts and C_EditMode.SaveLayouts and C_EditMode.ConvertStringToLayoutInfo) then
		return L["this game client has no Edit Mode layouts"]
	end
	if C_GameRules and C_GameRules.IsGameRuleActive and Enum.GameRule and Enum.GameRule.EditModeDisabled
		and C_GameRules.IsGameRuleActive(Enum.GameRule.EditModeDisabled) then
		return L["Edit Mode is switched off on this realm"]
	end
	local manager = _G.EditModeManagerFrame
	if manager and manager.IsShown and manager:IsShown() then return L["Edit Mode is open; close it first"] end
	if not (_G.EditModePresetLayoutManager and _G.EditModePresetLayoutManager.GetCopyOfPresetLayouts) then
		return L["Blizzard's Edit Mode isn't loaded yet"]
	end
	if name then
		if strtrim(name) == "" then return L["the layout needs a name"] end
		if C_EditMode.IsValidLayoutName and not C_EditMode.IsValidLayoutName(name) then return L["that name isn't allowed in Edit Mode"] end
	end
	return nil
end

-- Add `text` as a new account-wide Edit Mode layout named `name`.
function Import.AddEditModeLayout(text, name)
	name = strtrim(name or "")
	local blocker = Import.EditModeBlocker(name)
	if blocker then return false, blocker end
	local ok, info = pcall(C_EditMode.ConvertStringToLayoutInfo, text)
	if not ok or type(info) ~= "table" then return false, L["Edit Mode doesn't accept this layout text"] end
	local okLayouts, data = pcall(C_EditMode.GetLayouts)
	if not okLayouts or type(data) ~= "table" or type(data.layouts) ~= "table" then return false, L["Edit Mode layouts aren't loaded yet"] end
	local account = Enum.EditModeLayoutType and Enum.EditModeLayoutType.Account or 1
	local saved, accountCount, lastAccount = data.layouts, 0, 0
	for index, layout in ipairs(saved) do
		if layout.layoutName == name then return false, L["Edit Mode already has a layout named %q"]:format(name) end
		if layout.layoutType == account then
			accountCount = accountCount + 1
			lastAccount = index
		end
	end
	if accountCount >= MaxLayouts() then
		return false, L["Edit Mode already has %d account layouts, the most it allows; delete one in Edit Mode first"]:format(accountCount)
	end
	info.layoutName = name
	info.layoutType = account
	local slot = lastAccount + 1
	table.insert(saved, slot, info)
	local all = _G.EditModePresetLayoutManager:GetCopyOfPresetLayouts()
	for _, layout in ipairs(saved) do table.insert(all, layout) end
	local active = data.activeLayout
	if type(active) == "number" and active > NumPresets() + lastAccount then active = active + 1 end
	if Options().activate then active = NumPresets() + slot end
	local saveInfo = { layouts = all, activeLayout = active }
	local okSave = pcall(C_EditMode.SaveLayouts, saveInfo)
	if not okSave then return false, L["Edit Mode refused the layout"] end
	if Options().activate and C_EditMode.SetActiveLayout then pcall(C_EditMode.SetActiveLayout, active) end
	return true
end

-- The active Edit Mode layout as Blizzard's own export text.
function Import.EditModeExport()
	if not (C_EditMode and C_EditMode.GetLayouts and C_EditMode.ConvertLayoutInfoToString) then
		return nil, L["this game client has no Edit Mode layouts"]
	end
	local ok, data = pcall(C_EditMode.GetLayouts)
	if not ok or type(data) ~= "table" or type(data.activeLayout) ~= "number" then return nil, L["Edit Mode layouts aren't loaded yet"] end
	local info
	local presets = NumPresets()
	if data.activeLayout > presets then
		info = data.layouts and data.layouts[data.activeLayout - presets]
	elseif _G.EditModePresetLayoutManager and _G.EditModePresetLayoutManager.GetCopyOfPresetLayouts then
		local okPresets, layouts = pcall(_G.EditModePresetLayoutManager.GetCopyOfPresetLayouts, _G.EditModePresetLayoutManager)
		info = okPresets and type(layouts) == "table" and layouts[data.activeLayout] or nil
	end
	if type(info) ~= "table" then return nil, L["can't find the active Edit Mode layout"] end
	local okText, text = pcall(C_EditMode.ConvertLayoutInfoToString, info)
	if not okText or type(text) ~= "string" then return nil, L["Edit Mode couldn't write the layout"] end
	return text, info.layoutName
end

function E:ShowEditModeExport()
	local text, name = Import.EditModeExport()
	if not text then
		self:Print(L["Can't copy the Edit Mode layout: %s."]:format(tostring(name)))
		return
	end
	self:ShowCopyBox(L["Edit Mode layout: %s"]:format(tostring(name or "?")),
		L["Blizzard's own layout text, selected. Press Ctrl+C. It imports in Edit Mode > Layouts > Import, or in EldoUI's import window."], text)
end

---------------------------------------------------------------------------
-- Report text for the preview
---------------------------------------------------------------------------
local function Section(lines, title, list, limit)
	if #list == 0 then return end
	table.insert(lines, "")
	table.insert(lines, (E:TextHex("accent") .. "%s (%d)|r"):format(title, #list))
	for index, line in ipairs(list) do
		if limit and index > limit then
			table.insert(lines, L["   ... and %d more"]:format(#list - limit))
			break
		end
		table.insert(lines, "   " .. line)
	end
end

-- One line per bundle part: what it is and what happens to it.
function Import.PartLine(part)
	local name = part.label and (E:Highlight(part.label) .. ": ") or ""
	if part.kind == "other" then
		return name .. L["a string for %s. Copy it into that addon's own import; EldoUI doesn't apply it."]:format(part.addon or "?")
	elseif part.kind == "unknown" then
		return name .. E:TextHex("warn") .. L["not recognized, skipped."] .. "|r"
	elseif not part.source then
		return name .. E:TokenHex(E.tokens.text.bad) .. tostring(part.error or L["can't be read, skipped."]) .. "|r"
	end
	local source = part.source
	if source.kind == "eldoui" then return name .. L["EldoUI string (asks once more before it changes anything)."] end
	if source.kind == "editmode" then
		local systems = type(source.info.systems) == "table" and #source.info.systems or 0
		return name .. E:Plural(systems, "Blizzard Edit Mode layout with %d frame, added as a new Edit Mode layout.", "Blizzard Edit Mode layout with %d frames, added as a new Edit Mode layout."):format(systems)
	end
	local plan = Import.BuildPlan(source, Import.DefaultFactor(source))
	part.plan = plan
	if plan.blocked then return name .. plan.blocked end
	return name .. E:Plural(#plan.mapped, "%s profile: %d value maps to EldoUI, made into a new profile.", "%s profile: %d values map to EldoUI, made into a new profile."):format(source.title, #plan.mapped)
end

function Import.Report(source, plan)
	local lines = {}
	if source.kind == "bundle" then
		table.insert(lines, E:TextHex("accent") .. E:Plural(#source.parts, "A bundle with %d part.", "A bundle with %d parts."):format(#source.parts) .. "|r "
			.. L["Check the parts EldoUI applies. Your current profile stays as it is."])
		for index, part in ipairs(source.parts) do
			table.insert(lines, ("%d. %s"):format(index, Import.PartLine(part)))
		end
		return table.concat(lines, "\n")
	end
	if source.kind == "eldoui" then
		local described, err
		if E.DescribeShareString then described, err = E:DescribeShareString(source.text) end
		if described then
			for _, line in ipairs(described) do table.insert(lines, line) end
			table.insert(lines, "")
			table.insert(lines, E.L["Click Import: EldoUI asks once more before anything changes."])
		elseif err then
			table.insert(lines, ("%s%s|r"):format(E:TokenHex(E.tokens.text.bad), E.L["Can't read this string: %s."]:format(err)))
		else
			table.insert(lines, E:TextHex("accent") .. L["EldoUI share string."] .. "|r")
			table.insert(lines, L["Click Import: EldoUI shows what it contains and asks before anything changes."])
		end
		return table.concat(lines, "\n")
	end
	if source.kind == "editmode" then
		local info = source.info
		local systems = type(info.systems) == "table" and info.systems or {}
		table.insert(lines, L["%s with %d frames."]:format(E:Highlight(L["Blizzard Edit Mode layout"]), #systems))
		table.insert(lines, L["Copy for Edit Mode: shows the text for Blizzard's own Edit Mode > Layouts > Import (nothing is changed by EldoUI)."])
		table.insert(lines, L["Add to Edit Mode: EldoUI saves it as a new account layout for you, out of combat."])
		local blocker = Import.EditModeBlocker()
		if blocker then table.insert(lines, E:TextHex("warn") .. L["Add to Edit Mode is off: %s."]:format(blocker) .. "|r") end
		local list = {}
		for _, system in ipairs(systems) do
			local anchor = type(system.anchorInfo) == "table" and system.anchorInfo or {}
			local where
			if system.isInDefaultPosition then
				where = L["Blizzard's default place"]
			else
				local point = type(anchor.point) == "number" and POINT_NAMES[anchor.point] or tostring(anchor.point)
				where = L["%s of %s, %.0f, %.0f"]:format(tostring(point), tostring(anchor.relativeTo), tonumber(anchor.offsetX) or 0, tonumber(anchor.offsetY) or 0)
			end
			table.insert(list, ("%s: %s"):format(SystemName(system.system, system.systemIndex), where))
		end
		Section(lines, L["Frames"], list)
		return table.concat(lines, "\n")
	end
	local heading = source.profileKey and L["%s profile \"%s\"."]:format(source.title, source.profileKey)
		or L["%s profile."]:format(source.title)
	table.insert(lines, E:TextHex("accent") .. heading .. "|r " .. L["Scale factor %.2f."]:format(plan.factor))
	table.insert(lines, L["EldoUI rebuilds it as a WoW: Forever layout. Apply as a new layout: a NEW profile uses it and your current profile stays as it is. Change my current layout: your current profile takes it. Both can be undone."])
	if plan.blocked then return plan.blocked end
	Section(lines, L["Mapped to EldoUI"], plan.mapped)
	Section(lines, L["Notes"], plan.notes)
	Section(lines, L["Not imported"], plan.ignored, 40)
	if #plan.mapped == 0 then
		table.insert(lines, "")
		table.insert(lines, E:TextHex("warn") .. L["Nothing in this string maps to EldoUI with the current choices."] .. "|r")
	end
	return table.concat(lines, "\n")
end

-- Apply the ticked parts of a bundle in paste order. Returns the number
-- applied and a list of failures. Other addons' strings and unknown parts
-- are never applied.
-- Each part that failed keeps its reason in `part.failed` for the list.
function Import.ApplyBundle(bundle, notify, onProgress)
	if InCombatLockdown() then Tell(notify, Import.CombatText(), true); return 0, {}, 0 end
	if not Ingress.Plain(bundle) or not Ingress.Plain(bundle.parts) then return 0, {}, 0 end
	local applied, failures, pending = 0, {}, 0
	local function Progress()
		if not E.Secret(onProgress) and type(onProgress) == "function" then onProgress() end
	end
	for _, part in ipairs(bundle.parts) do
		if not Ingress.Plain(part) or E.Secret(part.applied) or E.Secret(part.pending) or E.Secret(part.apply) then return applied, failures, pending end
		if part.applied then applied = applied + 1 end
	end
	for index, part in ipairs(bundle.parts) do
		if part.pending then pending = pending + 1; break end
		local source = part.apply and not part.applied and part.source
		if E.Secret(source) then
			part.failed = L["the string is damaged or cut short. Copy it again in full."]
			failures[#failures + 1] = L["Part %d not applied: %s."]:format(index, part.failed)
			break
		end
		if source and Ingress.Plain(source) and not E.Secret(source.kind) and Import.APPLICABLE[source.kind] then
			part.failed = nil
			if source.kind == "eldoui" then
				local read, text = E.ImportString, source.text
				if E.Secret(read) or type(read) ~= "function" or E.Secret(text) or type(text) ~= "string" then break end
				part.pending = true
				local function Complete(ok, status)
					if E.Secret(ok) or E.Secret(status) or type(status) ~= "string" or E.Secret(E.ImportString) or E.ImportString ~= read
						or E.Secret(rawget(bundle.parts, index)) or rawget(bundle.parts, index) ~= part
						or E.Secret(part.source) or part.source ~= source or E.Secret(source.text) or source.text ~= text or part.applied then return end
					part.pending = status == "queued"
					if ok == true and status == "applied" then part.applied, part.apply, part.failed = true, false, nil
					elseif status ~= "cancelled" and status ~= "queued" then part.failed = L["the string is damaged or cut short. Copy it again in full."] end
					Progress()
				end
				local offered, status = read(E, text, Complete)
				if E.Secret(offered) or E.Secret(status) or (offered ~= true and status ~= "queued") then
					part.pending = false
					part.failed = L["the string is damaged or cut short. Copy it again in full."]
				end
				if part.applied then applied = applied + 1 end
				if part.pending then pending = pending + 1 end
				if part.failed then failures[#failures + 1] = L["Part %d not applied: %s."]:format(index, part.failed) end
				-- One explicit question at a time. Later selected parts stay selected.
				break
			end
			local ok, err
			local name = part.label or source.profileKey and (source.title .. " " .. source.profileKey) or source.title
			if source.kind == "editmode" then ok, err = Import.AddEditModeLayout(source.text, part.label or L["EldoUI import"])
			else ok, err = Import.ApplyPlan(Import.BuildPlan(source, Import.DefaultFactor(source)), name, nil, notify) end
			if ok then part.applied, part.apply = true, false; applied = applied + 1
			else
				part.failed = tostring(err or L["nothing in it maps to EldoUI"])
				failures[#failures + 1] = L["Part %d not applied: %s."]:format(index, part.failed)
			end
		end
	end
	local remaining = 0
	for _, part in ipairs(bundle.parts) do if part.apply and not part.applied then remaining = remaining + 1 end end
	return applied, failures, pending, remaining
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------
local window

-- The window's parts are the shared kit's (E.UIKit).
local function Button(parent, text, width)
	return E.UIKit.Button(parent, text, { width = width or 140, large = true })
end

local function Input(parent, width)
	return E.UIKit.Input(parent, { width = width })
end

local function Check(parent, label, key, desc)
	local check = E.UIKit.Check(parent, label, desc, function(on)
		Options()[key] = on
		if window and window.Refresh then window:Refresh() end
	end)
	check.key = key
	return check
end

-- A boxed scroll area: holder.area (E.UIKit.ScrollArea), holder.child.
local function ScrollArea(parent)
	local holder = CreateFrame("Frame", nil, parent)
	E:SetTemplate(holder, true)
	holder.area = E.UIKit.ScrollArea(holder)
	holder.area:SetPoint("TOPLEFT", 6, -6)
	holder.area:SetPoint("BOTTOMRIGHT", -6, 6)
	holder.child = holder.area.child
	return holder
end

local function CreateWindow()
	local frame = E.UIKit.CreateToolWindow("EldoUIImportWindow", { title = L["Import a string"], width = 760,
		height = 600, strata = "DIALOG" })
	frame.help = E.UIKit.Text(frame, E.tokens.size.label, "LEFT", "secondary")
	frame.help:SetPoint("TOPLEFT", 12, -36)
	frame.help:SetWidth(760 - 24)
	frame.help:SetWordWrap(true)
	frame.help:SetText(L["Paste any string (Ctrl+V): an EldoUI profile, part, layout or list, an EllesmereUI (!EUI_) or ElvUI (!E1!, !E2!) profile, a Blizzard Edit Mode layout, or a bundle of several strings, one per line. EldoUI tells which kind it is and shows what it imports before anything happens."])

	-- Paste box, under the help text however many lines it takes; the
	-- report below gives up the room.
	local paste = ScrollArea(frame)
	paste:SetPoint("TOPLEFT", frame.help, "BOTTOMLEFT", 0, -4)
	paste:SetPoint("TOPRIGHT", frame.help, "BOTTOMRIGHT", 0, -4)
	paste:SetHeight(110)
	local box = CreateFrame("EditBox", nil, paste.child)
	box:SetMultiLine(true)
	box:SetAutoFocus(false)
	box:SetMaxLetters(0)
	box:SetPoint("TOPLEFT")
	box:SetPoint("TOPRIGHT")
	E:SetFont(box, E.tokens.size.label)
	box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	box:HookScript("OnTextChanged", function(self)
		paste.child:SetHeight(math.max(self:GetHeight() or 0, paste.area:GetHeight() or 0))
		paste.area:Update()
	end)
	box:HookScript("OnTextChanged", function(_, userInput)
		if not userInput then return end
		frame.pending = (frame.pending or 0) + 1
		local token = frame.pending
		C_Timer.After(0.3, function()
			if frame.pending == token then frame:Analyze() end
		end)
	end)
	paste:SetScript("OnMouseDown", function() box:SetFocus() end)
	paste:EnableMouse(true)
	frame.box = box

	-- Choices
	local nameLabel = E.UIKit.Text(frame, E.tokens.size.body, "LEFT")
	nameLabel:SetPoint("TOPLEFT", paste, "BOTTOMLEFT", 0, -14)
	nameLabel:SetText(L["Name"])
	frame.name = Input(frame, 200)
	frame.name:SetPoint("LEFT", nameLabel, "RIGHT", 10, 0)

	local factorLabel = E.UIKit.Text(frame, E.tokens.size.body, "LEFT")
	factorLabel:SetPoint("LEFT", frame.name, "RIGHT", 18, 0)
	factorLabel:SetText(L["Scale"])
	frame.factor = Input(frame, 52)
	frame.factor:SetPoint("LEFT", factorLabel, "RIGHT", 10, 0)
	frame.factor:SetScript("OnEnterPressed", function(self)
		self:ClearFocus()
		frame:Refresh()
	end)
	-- Tab walks the form: the pasted string, the name, the scale.
	E.UIKit.TabOrder(box, frame.name, frame.factor)
	E.UIKit.Tooltip(frame.factor, L["Scale"], L["Positions and sizes are multiplied by this so frames keep their size on screen. EllesmereUI strings set it from their own UI scale; ElvUI uses 1 (its default pixel-perfect scale). Press Enter to update the preview."])

	frame.checks = {
		Check(frame, L["Positions"], "positions", L["Import frame positions into the imported layout."]),
		Check(frame, L["Sizes and fonts"], "settings", L["Import frame sizes, action bar shapes, which bars and frames show and when, fonts and the accent color."]),
		Check(frame, L["Activate"], "activate", L["Make a layout added to Edit Mode the active Edit Mode layout."]),
	}
	frame.checks[1]:SetPoint("LEFT", frame.factor, "RIGHT", 16, 0)
	frame.checks[2]:SetPoint("LEFT", frame.checks[1].label, "RIGHT", 12, 0)
	frame.checks[3]:SetPoint("LEFT", frame.checks[2].label, "RIGHT", 12, 0)

	-- Report
	local report = ScrollArea(frame)
	report:SetPoint("TOPLEFT", paste, "BOTTOMLEFT", 0, -44)
	report:SetPoint("BOTTOMRIGHT", -12, 48)
	local content = report.child
	content:SetHeight(10)
	frame.report = E.UIKit.Text(content, E.tokens.size.label, "LEFT")
	frame.report:SetPoint("TOPLEFT", 4, -4)
	frame.report:SetPoint("TOPRIGHT", -4, -4)
	frame.partRows = {}
	frame.report:SetWordWrap(true)
	frame.report:SetJustifyV("TOP")
	frame.reportContent = content
	frame.reportArea = report.area

	-- Buttons
	frame.apply = Button(frame, L["Apply as a new layout"], 180)
	frame.apply:SetPoint("BOTTOMRIGHT", -12, 12)
	frame.second = Button(frame, L["Change my current layout"], 190)
	frame.second:SetPoint("RIGHT", frame.apply, "LEFT", -8, 0)
	frame.export = Button(frame, L["Copy my Edit Mode layout"], 190)
	frame.export:SetPoint("BOTTOMLEFT", 12, 12)
	frame.export:SetScript("OnClick", function() E:ShowEditModeExport() end)

	frame.apply:SetScript("OnClick", function() frame:Apply() end)
	frame.second:SetScript("OnClick", function()
		local source = frame.source
		if source and source.kind == "editmode" then
			E:ShowCopyBox(L["Copy for Edit Mode"],
				L["Press Ctrl+C. Then Esc > Edit Mode > Layouts dropdown > Import, paste with Ctrl+V, name it and click Import."], source.text)
		elseif source and frame.plan and (source.kind == "eui" or source.kind == "elv") then
			if Import.ApplyPlan(frame.plan, frame.name:GetText(), "current", function(text, warn) frame:Notify(text, warn) end) then frame:Hide() end
		end
	end)

	frame:RegisterEvent("PLAYER_REGEN_DISABLED")
	frame:RegisterEvent("PLAYER_REGEN_ENABLED")
	frame:SetScript("OnEvent", function(self) if self:IsShown() then self:UpdateButtons() end end)

	function frame:SetReport(text)
		self.report:SetText(text or "")
		local rows = 0
		for _, row in ipairs(self.partRows) do
			if row:IsShown() then rows = rows + 1 end
		end
		local top = rows > 0 and (rows * (E.tokens.height.button + 2) + 8) or 0
		self.report:ClearAllPoints()
		self.report:SetPoint("TOPLEFT", 4, -4 - top)
		self.report:SetPoint("TOPRIGHT", -4, -4 - top)
		self.reportContent:SetHeight(math.max(10, top + (self.report:GetStringHeight() or 0) + 12))
		self.reportArea:Update()
	end

	-- A bundle: one row per part, a tick for the parts EldoUI can apply and
	-- a Copy button for strings meant for another addon.
	function frame:PartRow(index)
		local row = self.partRows[index]
		if row then return row end
		row = CreateFrame("Frame", nil, self.reportContent)
		row:SetHeight(E.tokens.height.button)
		row:SetPoint("TOPLEFT", 4, -4 - (index - 1) * (E.tokens.height.button + 2))
		row:SetPoint("TOPRIGHT", self.reportContent, "TOPRIGHT", -4, -4 - (index - 1) * (E.tokens.height.button + 2))
		row.check = E.UIKit.Check(row, "", nil, function(on)
			if row.part then row.part.apply = on and true or false end
			self:UpdateButtons()
		end)
		row.check:SetPoint("LEFT", 0, 0)
		row.copy = E.UIKit.Button(row, L["Copy"], 70)
		row.copy:SetPoint("LEFT", 0, 0)
		row.copy:SetScript("OnClick", function()
			local part = row.part
			if part then
				E:ShowCopyBox(L["Copy for %s"]:format(part.addon or "?"),
					L["Press Ctrl+C, then paste it into that addon's own import."], part.text)
			end
		end)
		row.text = E.UIKit.Text(row, E.tokens.size.label, "LEFT")
		row.text:SetPoint("LEFT", 80, 0)
		row.text:SetPoint("RIGHT", 0, 0)
		row.text:SetWordWrap(false)
		self.partRows[index] = row
		return row
	end

	function frame:ShowParts(parts)
		parts = parts or {}
		for index, part in ipairs(parts) do
			local row = self:PartRow(index)
			row.part = part
			local applicable = part.source ~= nil and Import.APPLICABLE[part.source.kind]
			row.check:SetShown(applicable and true or false)
			row.check:SetChecked(part.apply and true or false)
			row.copy:SetShown(part.kind == "other")
			local title = part.label or (part.source and part.source.title) or part.addon or L["Not recognized"]
			local text = ("%d. %s"):format(index, title)
			if part.pending then text = text .. "  " .. L["EldoUI string (asks once more before it changes anything)."] end
			if part.failed then
				text = text .. "  " .. E:StatusText("bad", L["not applied"] .. ": " .. part.failed)
			end
			row.text:SetText(text)
			row:Show()
		end
		for index = #parts + 1, #self.partRows do
			self.partRows[index]:Hide()
			self.partRows[index].part = nil
		end
	end

	function frame:UpdateButtons()
		local source = self.source
		local kind = source and source.kind
		local inCombat = InCombatLockdown()
		self.second:SetShown(kind == "editmode" or kind == "eui" or kind == "elv")
		self.second:SetText(kind == "editmode" and L["Copy for Edit Mode"] or L["Change my current layout"])
		self.second:SetEnabled(true)
		self.checks[3]:SetShown(kind == "editmode")
		self.checks[1]:SetShown(kind ~= "editmode")
		self.checks[2]:SetShown(kind ~= "editmode")
		self.factor:SetEnabled(kind == "eui" or kind == "elv")
		self.name:SetEnabled(kind == "eui" or kind == "elv" or kind == "editmode")
		if kind == "bundle" then
			local ticked, pending = 0, false
			for _, part in ipairs(source.parts) do
				if part.apply and not part.applied then ticked = ticked + 1 end
				if part.pending then pending = true end
			end
			self.apply:SetText(L["Apply checked parts"])
			self.apply:SetEnabled(not inCombat and not pending and ticked > 0)
		elseif kind == "eldoui" then
			self.apply:SetText(L["Import"])
			self.apply:SetEnabled(true)
		elseif kind == "editmode" then
			self.apply:SetText(L["Add to Edit Mode"])
			self.apply:SetEnabled(Import.EditModeBlocker() == nil)
		elseif kind == "eui" or kind == "elv" then
			local binding = Ingress.Plain(self.plan) and Ingress.plans[self.plan]
			local ready = not inCombat and binding and Ingress.Context(binding.target) ~= nil
				and not self.plan.blocked and #self.plan.mapped > 0
			self.apply:SetText(L["Apply as a new layout"])
			self.apply:SetEnabled(ready)
			self.second:SetEnabled(ready)
		else
			self.apply:SetText(L["Apply as a new layout"])
			self.apply:SetEnabled(false)
		end
	end

	-- Rebuild the plan and preview from the parsed source (choices changed).
	function frame:Refresh()
		for _, check in ipairs(self.checks) do check:SetChecked(Options()[check.key]) end
		local source = self.source
		self.plan = nil
		self:ShowParts(source and source.kind == "bundle" and source.parts or nil)
		if not source then
			self:SetReport(self.errorText or "")
		else
			if source.kind == "eui" or source.kind == "elv" then
				local factor = tonumber(self.factor:GetText())
				if not factor or factor <= 0 or factor > 4 then
					factor = Import.DefaultFactor(source)
					self.factor:SetText(("%.2f"):format(factor))
				end
				self.plan = Import.BuildPlan(source, factor)
			end
			self:SetReport(Import.Report(source, self.plan))
		end
		self:UpdateButtons()
	end

	-- Read the pasted text (no changes anywhere).
	function frame:Analyze()
		local text = self.box:GetText() or ""
		self.source, self.errorText = nil, nil
		if strtrim(text) == "" then
			self.errorText = ""
		else
			local source, err = Import.Parse(text)
			self.source = source
			self.errorText = err and ("%s%s|r"):format(E:TokenHex(E.tokens.text.bad), err)
			if source then
				if source.kind == "eui" or source.kind == "elv" then
					self.factor:SetText(("%.2f"):format(Import.DefaultFactor(source)))
					self.name:SetText(source.profileKey and (source.title .. " " .. source.profileKey) or source.title)
				elseif source.kind == "editmode" then
					self.name:SetText(L["EldoUI import"])
				else
					self.name:SetText("")
				end
			end
		end
		self:Refresh()
	end

	-- A result of a click shows in the window itself. A success that
	-- closes the window shows on the options window when it is open, else
	-- as one chat line.
	function frame:Notify(text, warn)
		if self:IsShown() and E.UIKit.Toast then
			E.UIKit.Toast(self, text, { warn = warn and true or nil })
		else
			E:Print(text)
		end
	end
	local function Done(text)
		frame:Hide()
		if E.ConfigNotice then E:ConfigNotice(text) else E:Print(text) end
	end
	local function Notify(text, warn) frame:Notify(text, warn) end

	function frame:Apply()
		local source = self.source
		if not source then return end
		if InCombatLockdown() and source.kind ~= "eldoui" then
			self:Notify(Import.CombatText(), true)
			return
		end
		if source.kind == "bundle" then
			local applied, failures, pending, remaining = Import.ApplyBundle(source, Notify, function()
				if self.source == source then self:ShowParts(source.parts); self:UpdateButtons() end
			end)
			local done = E:Plural(applied, "Applied %d part of the bundle.", "Applied %d parts of the bundle."):format(applied)
			if #failures == 0 and applied > 0 and pending == 0 and remaining == 0 then
				Done(done)
			else
				self:ShowParts(source.parts)
				self:SetReport(Import.Report(source, self.plan))
				if #failures == 0 then self:Notify(L["Import it? Nothing changes until you accept."])
				else self:Notify(E:Plural(#failures, "%d part not applied. The list shows why.", "%d parts not applied. The list shows why."):format(#failures), true) end
				self:UpdateButtons()
			end
		elseif source.kind == "eldoui" then
			E:ImportString(strtrim(self.box:GetText() or ""))
			self:Hide()
		elseif source.kind == "editmode" then
			local ok, err = Import.AddEditModeLayout(source.text, self.name:GetText())
			if ok then
				Done((Options().activate and L["Added the Edit Mode layout %s and made it active."]
					or L["Added the Edit Mode layout %s."]):format(E:Highlight(strtrim(self.name:GetText() or ""))))
			else
				self:Notify(L["Edit Mode layout not added: %s."]:format(tostring(err)), true)
				self:UpdateButtons()
			end
		elseif self.plan then
			if Import.ApplyPlan(self.plan, self.name:GetText(), nil, Notify) then self:Hide() end
		end
	end

	-- A profile switch repaints the existing window after the new profile is
	-- admitted. Rebuild its preview only through the same captured owners.
	E:RegisterThemed(frame, function(self)
		if not self:IsShown() or not Ingress.Plain(self.plan) then return end
		local binding = Ingress.plans[self.plan]
		if binding and Ingress.Context(binding.target) then return end
		self.plan = nil
		local target = binding and binding.target
		if target and not E.Secret(E.IsCurrentProfile) and E.IsCurrentProfile == target.admit
			and not E.Secret(E.GetApplyGeneration) and E.GetApplyGeneration == target.getter
			and not E.Secret(E.IsApplyGenerationCurrent) and E.IsApplyGenerationCurrent == target.active
			and not E.Secret(E.LoadDatabase) and E.LoadDatabase == target.loader and Ingress.Context() then
			self:Refresh()
		else self:UpdateButtons() end
	end)
	frame:Hide()
	return frame
end

function E:ShowImportWindow(text)
	window = window or CreateWindow()
	-- The help text keeps its whole height at every text size.
	window.help:SetHeight(math.max(1, window.help:GetStringHeight() or 0))
	window:Show()
	window:Raise()
	if text and text ~= "" then
		window.box:SetText(text)
		window:Analyze()
	else
		window:Refresh()
		window.box:SetFocus()
	end
end

---------------------------------------------------------------------------
-- Commands and options
---------------------------------------------------------------------------
-- Replaces Core/Share.lua's "import" (the window also takes EldoUI strings).
E:AddCommand("import", "open the import window: EldoUI, EllesmereUI, ElvUI and Edit Mode strings", function()
	E:ShowImportWindow()
end, "Profiles & sharing")

E:AddCommand("editlayout", "[copy]  copy Blizzard's active Edit Mode layout as text, or open the import window", function(arg)
	arg = strtrim(arg or ""):lower()
	if arg == "copy" or arg == "export" then
		E:ShowEditModeExport()
	else
		E:ShowImportWindow()
	end
end, "Profiles & sharing")

-- The Import and export page (Core/Share.lua) is the one place to paste a
-- string: the window above reads every kind. These are
-- its rows for strings from other UIs; their keys live in the import
-- options (E:ImportPageTarget).
function E:ImportPageRows(part)
	if part == "layouts" then
		return {
			{ type = "header", label = "Imported layouts" },
			{ type = "description", label = "Layouts imported from other UIs show up under Layouts like the built-in ones, named after the profile they were imported into." },
			{ type = "execute", label = "Remove unused imported layouts", desc = "Delete imported layout presets that no profile uses.", func = function()
				E:ConfigNotice(L["Removed %d unused imported layouts."]:format(E:ForgetUnusedImportedLayouts()))
				if E.RefreshConfig then E:RefreshConfig() end
			end },
		}
	end
	return {
		{ type = "header", label = "Strings from other UIs" },
		{ type = "description", label = "An EllesmereUI or ElvUI profile becomes an EldoUI layout. After the preview, apply it as a new profile or to this one; both can be undone." },
		{ type = "toggle", key = "positions", label = "Frame positions", keywords = "ElvUI EllesmereUI",
			desc = "Import positions as an imported layout preset used by the new profile. Frames the string doesn't place keep your current layout's positions." },
		{ type = "toggle", key = "settings", label = "Sizes and fonts", keywords = "ElvUI EllesmereUI",
			desc = "Imports frame and bar sizes, which bars and frames show and when, chat, minimap and resource bar sizes, the font and the accent color, where EldoUI has the same setting." },
		{ type = "toggle", key = "activate", label = "Activate added Edit Mode layouts", keywords = "Edit Mode",
			desc = "When EldoUI adds a layout to Blizzard's Edit Mode, make it the active one." },
	}
end

function E:ImportPageTarget()
	return Options()
end

function E:ImportPageRefresh()
	if window and window:IsShown() then window:Refresh() end
end
