-- EldoUI share strings: export any category (one module with its frame
-- positions, the general theme, all positions, account-wide lists such as
-- aura filters) or the whole profile as one text string, import strings
-- other players share, and send a string straight to a group, guild or
-- friend.
--
--   E:ExportString(key[, "lua"])  key = "all", "general", "positions",
--                                 "module:<Name>", "global" or "global:<namespace>"
--   E:ShowExport(key[, "lua"])    copy box with the string selected
--   E:ShowImport()                paste box; shows what's inside before applying
--   E:SendShare(key, target)      target = "PARTY", "RAID", "GUILD" or a player name
--   /eui export [key]   /eui exportlua [key]   /eui import   /eui send <who> [key]
--
-- Format: "!EUI1!" + flag + payload. Flag "z" = deflate + base64 through the
-- game's C_EncodingUtil; flag "p" = plain base64 when that is missing.
-- The readable export is a Lua table literal (for bug reports and diffs);
-- the importer reads it back with its own parser. Strings are parsed by our
-- own readers: nothing is ever run as code.
local _, E = ...
local ReadAccountRoot = E.ReadAccountRoot
local L = E.L

local PREFIX = "!EUI1!"
local LUA_HEADER = "-- EldoUI"
local MAX_STRING = 1024 * 1024
local MAX_DEPTH = 20

local function Plain(value)
	return not E.Secret(value) and type(value) == "table" and type(getmetatable(value)) == "nil"
end

local function Completion(callback, ok, status)
	if not E.Secret(callback) and type(callback) == "function" then callback(ok, status) end
end

local function ProfileKind(kind)
	return not E.Secret(kind) and type(kind) == "string"
		and (kind == "all" or kind == "general" or kind == "positions" or kind:match("^module:.+$") ~= nil)
end

local function SourceAdmit(profile)
	local predicate = E.IsSupportedProfileData
	if E.Secret(predicate) or type(predicate) ~= "function" then return false end
	local ok, supported = pcall(predicate, E, profile)
	return ok and not E.Secret(supported) and supported == true and E.IsSupportedProfileData == predicate
end

local function ProfileAdmit(profile, name)
	local predicate = E.IsCurrentProfile
	if E.Secret(predicate) or type(predicate) ~= "function" then return false end
	local ok, current = pcall(predicate, E, profile, name)
	return ok and not E.Secret(current) and current == true and E.IsCurrentProfile == predicate
end

local function TargetAdmit(target)
	local root, profile, name = ReadAccountRoot(), E.db, E.profileName
	local getter, active, admit = E.GetApplyGeneration, E.IsApplyGenerationCurrent, E.IsCurrentProfile
	if E.Secret(root) or E.Secret(profile) or E.Secret(name) or E.Secret(getter) or E.Secret(active) or E.Secret(admit)
		or type(getter) ~= "function" or type(active) ~= "function" or type(admit) ~= "function" then return nil end
	if target and (root ~= target.root or profile ~= target.profile or name ~= target.name or getter ~= target.getter
		or active ~= target.active or admit ~= target.admit) then return nil end
	local ok, generation = pcall(getter, E, "profile")
	if not ok or E.Secret(generation) or type(generation) ~= "number" or generation < 1 or generation >= math.huge
		or generation % 1 ~= 0 or (target and generation ~= target.generation) then return nil end
	if not ProfileAdmit(profile, name) then return nil end
	local valid, current = pcall(active, E, generation, "profile")
	if not valid or E.Secret(current) or current ~= true or E.Secret(E.GetApplyGeneration) or E.GetApplyGeneration ~= getter
		or E.Secret(E.IsApplyGenerationCurrent) or E.IsApplyGenerationCurrent ~= active or E.Secret(E.IsCurrentProfile) or E.IsCurrentProfile ~= admit
		or E.Secret(ReadAccountRoot()) or ReadAccountRoot() ~= root or E.Secret(E.db) or E.db ~= profile
		or E.Secret(E.profileName) or E.profileName ~= name then return nil end
	return target or { root = root, profile = profile, name = name, getter = getter, active = active, admit = admit, generation = generation }
end

local function CurrentLayout(key)
	if E.Secret(key) or type(key) ~= "string" or not Plain(E.layoutFamilies) then return nil end
	local resolve = E.FamilyLayoutKey
	if E.Secret(resolve) or type(resolve) ~= "function" then return nil end
	for _, slot in ipairs(E.layoutFamilies) do
		if not Plain(slot) then return nil end
		local family = rawget(slot, "key")
		if E.Secret(family) or type(family) ~= "string" then return nil end
		local ok, current = pcall(resolve, E, family)
		if ok and not E.Secret(current) and type(current) == "string" and key == current then return current end
	end
end

local function DependencyOwner(name)
	local owner = E.Import
	if not Plain(owner) then return nil end
	local fn = rawget(owner, name)
	if E.Secret(fn) or type(fn) ~= "function" then return nil end
	return owner, fn
end

local function DependencyCurrent(owner, fn, name)
	return not E.Secret(E.Import) and E.Import == owner and not E.Secret(rawget(owner, name)) and rawget(owner, name) == fn
end

local function DependencyPlan(key, envelope)
	if E.Secret(key) or type(key) ~= "string" or not Plain(envelope) then return nil end
	local owner, prepare = DependencyOwner("PrepareLayoutDependencies")
	if not owner then return nil end
	local ok, plan = pcall(prepare, envelope)
	if not ok or not Plain(plan) or E.Secret(plan.layout) or plan.layout ~= key or not Plain(plan.layoutData)
		or not DependencyCurrent(owner, prepare, "PrepareLayoutDependencies") then return nil end
	return plan
end

local function CaptureDependencies(key)
	if CurrentLayout(key) then return nil, true end
	local owner, capture = DependencyOwner("CaptureLayoutDependencies")
	if not owner then return nil end
	local ok, envelope = pcall(capture, key)
	if not ok or not Plain(envelope) or not DependencyCurrent(owner, capture, "CaptureLayoutDependencies")
		or not DependencyPlan(key, envelope) then return nil end
	return envelope, true
end

local function MaterializeDependencies(payload, data, target)
	local envelope = rawget(payload, "layoutDependencies")
	if type(envelope) == "nil" then return data end
	local general = payload.kind == "all" and data.general or data
	local plan = Plain(general) and DependencyPlan(general.layout, envelope)
	local owner, apply = DependencyOwner("ApplyLayoutDependencies")
	if not plan or not owner or not TargetAdmit(target) then return nil end
	local ok, applied, key = pcall(apply, plan)
	if not ok or E.Secret(applied) or applied ~= true or E.Secret(key) or type(key) ~= "string"
		or not DependencyCurrent(owner, apply, "ApplyLayoutDependencies") or not TargetAdmit(target) then return nil end
	general.layout = key
	return data
end

-- The EldoUI version a string names, for a message (only digits and dots).
local function StringVersion(payload)
	local version = rawget(payload, "version")
	if type(version) == "string" and not E.Secret(version) and version:match("^[%d%.]+$") and #version <= 16 then return version end
	return "?"
end

-- true, or false and (when it is not simply damaged) why the player can't
-- import the string.
local function PayloadAdmit(payload)
	if not Plain(payload) or not Plain(payload.data) then return false end
	local kind = payload.kind
	if not ProfileKind(kind) then return true end
	if kind ~= "all" and kind ~= "general" and type(rawget(payload, "layoutDependencies")) ~= "nil" then return false end
	local schema = payload.schema
	if not Plain(schema) or E.Secret(schema.unit) or schema.unit ~= "profile" then return false end
	if not SourceAdmit({ profileBaseline = payload.profileBaseline, schema = schema.version }) then
		local version = schema.version
		if type(version) == "number" and not E.Secret(version) and version > E.PROFILE_SCHEMA then
			return false, L["it was made with a newer EldoUI (%s). Update EldoUI to import it."]:format(StringVersion(payload))
		end
		return false, L["it was made with an EldoUI version this one can't read (%s)."]:format(StringVersion(payload))
	end
	if kind == "all" and (not SourceAdmit(payload.data)
		or payload.data.profileBaseline ~= payload.profileBaseline or payload.data.schema ~= schema.version) then return false end
	local general
	if kind == "general" then general = payload.data
	elseif kind == "all" then general = rawget(payload.data, "general") end
	if type(general) ~= "nil" then
		if not Plain(general) then return false end
		local key = rawget(general, "layout")
		if type(key) ~= "nil" then
			local envelope = rawget(payload, "layoutDependencies")
			if type(envelope) ~= "nil" then
				if not DependencyPlan(key, envelope) then return false end
			elseif not CurrentLayout(key) then
				local name = type(key) == "string" and not E.Secret(key) and #key <= 64 and key:gsub("|", "||") or "?"
				return false, L["it uses the layout %s, which you don't have."]:format(name)
			end
		end
	end
	if type(rawget(payload, "layoutDependencies")) ~= "nil" and (not general or type(rawget(general, "layout")) == "nil") then return false end
	return true
end

local function PackData(data)
	local clean = E.CleanPack
	if E.Secret(clean) or type(clean) ~= "function" then return nil end
	local ok, pack = pcall(clean, data)
	return ok and Plain(pack) and E.CleanPack == clean and pack or nil
end

---------------------------------------------------------------------------
-- Serializer: s<len>:<text>  n<number>;  T / F  { key value ... }
---------------------------------------------------------------------------
-- yield (optional): called after each table entry, so a long job can
-- hand the frame back between entries (see Serialize). yield(true) asks
-- for the frame to be handed back at once.
local function Write(value, out, depth, yield)
	local kind = type(value)
	if kind == "string" then
		table.insert(out, "s" .. #value .. ":" .. value)
	elseif kind == "number" then
		table.insert(out, "n" .. ("%.17g"):format(value) .. ";")
	elseif kind == "boolean" then
		table.insert(out, value and "T" or "F")
	elseif kind == "table" then
		if depth > MAX_DEPTH then error("settings nested too deep") end
		table.insert(out, "{")
		for key, inner in pairs(value) do
			local keyKind, innerKind = type(key), type(inner)
			if (keyKind == "string" or keyKind == "number") and (innerKind == "string" or innerKind == "number" or innerKind == "boolean" or innerKind == "table") then
				Write(key, out, depth + 1, yield)
				Write(inner, out, depth + 1, yield)
			end
			if yield then yield() end
		end
		table.insert(out, "}")
	end
end

-- With yield, the text is joined in pieces as it grows and yield runs
-- after each table entry: a job calls it from its coroutine (outside any
-- pcall, which cannot be yielded across) and spreads the work over frames.
-- The text is the same either way.
local PIECES = 4096
local function Serialize(value, yield)
	local out = {}
	if not yield then
		Write(value, out, 0)
		return table.concat(out)
	end
	local done = {}
	Write(value, out, 0, function()
		if #out >= PIECES then
			done[#done + 1] = table.concat(out)
			wipe(out)
		end
		yield()
	end)
	-- The join is one pass over the whole text: it gets a frame of its own.
	yield(true)
	done[#done + 1] = table.concat(out)
	return table.concat(done)
end

local function Read(text, pos, depth)
	local tag = text:sub(pos, pos)
	if tag == "s" then
		local length, after = text:match("^(%d+):()", pos + 1)
		length = tonumber(length)
		if not length then error("bad text") end
		local finish = after + length - 1
		if finish > #text then error("string cut short") end
		return text:sub(after, finish), finish + 1
	elseif tag == "n" then
		local number, after = text:match("^([^;]+);()", pos + 1)
		number = tonumber(number)
		if not number then error("bad number") end
		return number, after
	elseif tag == "T" then
		return true, pos + 1
	elseif tag == "F" then
		return false, pos + 1
	elseif tag == "{" then
		if depth > MAX_DEPTH then error("nested too deep") end
		local result = {}
		pos = pos + 1
		while text:sub(pos, pos) ~= "}" do
			if pos > #text then error("table cut short") end
			local key, value
			key, pos = Read(text, pos, depth + 1)
			if type(key) == "table" or type(key) == "boolean" then error("bad key") end
			value, pos = Read(text, pos, depth + 1)
			result[key] = value
		end
		return result, pos + 1
	end
	error("unknown tag at " .. pos)
end

local function Deserialize(text)
	local value, pos = Read(text, 1, 0)
	if pos <= #text then error("extra data") end
	return value
end

---------------------------------------------------------------------------
-- Readable Lua table: written with sorted keys so two exports diff well,
-- read back by a small parser that accepts only table literals with
-- [key] = value pairs, quoted strings, numbers and true/false.
---------------------------------------------------------------------------
local function SortKeys(a, b)
	local ta, tb = type(a), type(b)
	if ta ~= tb then return ta == "number" end
	return a < b
end

local function WriteLua(value, out, indent, depth)
	local kind = type(value)
	if kind == "string" then
		out[#out + 1] = ("%q"):format(value):gsub("\\\n", "\\n")
	elseif kind == "number" then
		out[#out + 1] = value == math.floor(value) and ("%d"):format(value) or ("%.17g"):format(value)
	elseif kind == "boolean" then
		out[#out + 1] = value and "true" or "false"
	elseif kind == "table" then
		if depth > MAX_DEPTH then error("settings nested too deep") end
		local keys = {}
		for key, inner in pairs(value) do
			local innerKind = type(inner)
			if (type(key) == "string" or type(key) == "number")
				and (innerKind == "string" or innerKind == "number" or innerKind == "boolean" or innerKind == "table") then
				keys[#keys + 1] = key
			end
		end
		if #keys == 0 then
			out[#out + 1] = "{}"
			return
		end
		table.sort(keys, SortKeys)
		out[#out + 1] = "{\n"
		for _, key in ipairs(keys) do
			out[#out + 1] = indent .. "\t["
			WriteLua(key, out, "", depth + 1)
			out[#out + 1] = "] = "
			WriteLua(value[key], out, indent .. "\t", depth + 1)
			out[#out + 1] = ",\n"
		end
		out[#out + 1] = indent .. "}"
	end
end

local ESCAPES = { n = "\n", t = "\t", r = "\r", ["\\"] = "\\", ['"'] = '"', ["'"] = "'", ["\n"] = "\n", a = "\a", b = "\b", f = "\f", v = "\v" }

local LuaReader = {}

function LuaReader.Skip(text, pos)
	while true do
		local after = text:match("^%s*()", pos)
		pos = after
		if text:sub(pos, pos + 1) == "--" then
			local lineEnd = text:find("\n", pos, true)
			if not lineEnd then return #text + 1 end
			pos = lineEnd + 1
		else
			return pos
		end
	end
end

function LuaReader.String(text, pos)
	local quote = text:sub(pos, pos)
	local out, i = {}, pos + 1
	while true do
		local char = text:sub(i, i)
		if char == "" then error("text cut short") end
		if char == quote then return table.concat(out), i + 1 end
		if char == "\\" then
			local nextChar = text:sub(i + 1, i + 1)
			local digits = text:match("^%d%d?%d?", i + 1)
			if digits then
				local code = tonumber(digits)
				if code > 255 then error("bad escape") end
				out[#out + 1] = string.char(code)
				i = i + 1 + #digits
			elseif ESCAPES[nextChar] then
				out[#out + 1] = ESCAPES[nextChar]
				i = i + 2
			else
				error("bad escape")
			end
		elseif char == "\n" then
			error("line break inside text")
		else
			out[#out + 1] = char
			i = i + 1
		end
	end
end

function LuaReader.Value(text, pos, depth)
	pos = LuaReader.Skip(text, pos)
	local char = text:sub(pos, pos)
	if char == '"' or char == "'" then return LuaReader.String(text, pos) end
	if char == "{" then return LuaReader.Table(text, pos, depth) end
	if text:sub(pos, pos + 3) == "true" then return true, pos + 4 end
	if text:sub(pos, pos + 4) == "false" then return false, pos + 5 end
	local number, after = text:match("^(%-?[%d%.]+[eE]?[%-+]?%d*)()", pos)
	if number and tonumber(number) then return tonumber(number), after end
	error("unexpected text at " .. pos)
end

function LuaReader.Table(text, pos, depth)
	if depth > MAX_DEPTH then error("nested too deep") end
	local result, index = {}, 1
	pos = LuaReader.Skip(text, pos + 1)
	while text:sub(pos, pos) ~= "}" do
		if pos > #text then error("table cut short") end
		local key, value
		if text:sub(pos, pos) == "[" then
			key, pos = LuaReader.Value(text, pos + 1, depth + 1)
			if type(key) ~= "string" and type(key) ~= "number" then error("bad key") end
			pos = LuaReader.Skip(text, pos)
			if text:sub(pos, pos) ~= "]" then error("expected ]") end
			pos = LuaReader.Skip(text, pos + 1)
			if text:sub(pos, pos) ~= "=" then error("expected =") end
			value, pos = LuaReader.Value(text, pos + 1, depth + 1)
		else
			local name, after = text:match("^([%a_][%w_]*)%s*=()", pos)
			if name and name ~= "true" and name ~= "false" then
				key = name
				value, pos = LuaReader.Value(text, after, depth + 1)
			else
				key = index
				index = index + 1
				value, pos = LuaReader.Value(text, pos, depth + 1)
			end
		end
		result[key] = value
		pos = LuaReader.Skip(text, pos)
		local sep = text:sub(pos, pos)
		if sep == "," or sep == ";" then
			pos = LuaReader.Skip(text, pos + 1)
		elseif sep ~= "}" then
			error("expected , or }")
		end
	end
	return result, pos + 1
end

local function ReadLua(text)
	local pos = LuaReader.Skip(text, 1)
	if text:sub(pos, pos) ~= "{" then error("this is not an EldoUI string") end
	local value
	value, pos = LuaReader.Table(text, pos, 0)
	pos = LuaReader.Skip(text, pos)
	if pos <= #text then error("extra data") end
	return value
end

---------------------------------------------------------------------------
-- Encoding
---------------------------------------------------------------------------
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64_INDEX = {}
for i = 1, 64 do B64_INDEX[B64:sub(i, i)] = i - 1 end

local function Base64Encode(data)
	local out = {}
	for i = 1, #data, 3 do
		local a, b, c = data:byte(i, i + 2)
		local n = a * 65536 + (b or 0) * 256 + (c or 0)
		local c1, c2, c3, c4 = math.floor(n / 262144), math.floor(n / 4096) % 64, math.floor(n / 64) % 64, n % 64
		out[#out + 1] = B64:sub(c1 + 1, c1 + 1) .. B64:sub(c2 + 1, c2 + 1)
			.. (b and B64:sub(c3 + 1, c3 + 1) or "=") .. (c and B64:sub(c4 + 1, c4 + 1) or "=")
	end
	return table.concat(out)
end

local function Base64Decode(data)
	data = data:gsub("[^%w%+/=]", "")
	local out = {}
	for i = 1, #data, 4 do
		local chunk = data:sub(i, i + 3)
		local n, pad = 0, 0
		for j = 1, 4 do
			local char = chunk:sub(j, j)
			if char == "=" or char == "" then pad = pad + 1; n = n * 64
			else
				local value = B64_INDEX[char]
				if not value then error("bad base64") end
				n = n * 64 + value
			end
		end
		local bytes = string.char(math.floor(n / 65536) % 256, math.floor(n / 256) % 256, n % 256)
		out[#out + 1] = bytes:sub(1, 3 - pad)
	end
	return table.concat(out)
end

---------------------------------------------------------------------------
-- Unpacking with a size limit. C_EncodingUtil.DecompressString builds the
-- whole result before anyone can look at its length, and DEFLATE packs up
-- to about 1000:1: a string inside the 1 MB limit could unpack to a
-- gigabyte. Inflate.Size walks the raw DEFLATE stream (RFC 1951) and adds
-- up the bytes it would write, without writing them, and stops as soon as
-- the sum passes the limit; such a string costs a few thousand steps. It
-- reads every code the way zlib does and refuses what zlib refuses.
-- Core/Import.lua uses it for ElvUI and EllesmereUI strings too.
--
--   E:Inflate(bytes, limit) -> text, or nil and "long", "damaged" or "client"
---------------------------------------------------------------------------
local Inflate = {
	-- Lengths 3..258 (codes 257..285) and distances 1..32768 (codes 0..29):
	-- base value and extra bits.
	LENGTH_BASE = { 3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163,
		195, 227, 258 },
	LENGTH_EXTRA = { 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0 },
	DISTANCE_BASE = { 1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049,
		3073, 4097, 6145, 8193, 12289, 16385, 24577 },
	DISTANCE_EXTRA = { 0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13 },
	-- The order in which a dynamic block lists the lengths of its code length code.
	ORDER = { 16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15 },
	POW2 = {},
}
for i = 0, 24 do Inflate.POW2[i] = 2 ^ i end

-- The canonical Huffman code for the code lengths lengths[first .. first+n-1]
-- (symbols 0 .. n-1): how many codes each length has, and the symbols in
-- code order. Nil when the lengths ask for more codes than there are; the
-- second value is above 0 when codes are left over (an incomplete set).
function Inflate.Code(lengths, first, n)
	local count, offset, symbol = {}, {}, {}
	for length = 0, 15 do count[length] = 0 end
	for i = first, first + n - 1 do
		local length = lengths[i]
		count[length] = count[length] + 1
	end
	if count[0] == n then return { count = count, symbol = symbol }, 0 end
	local left = 1
	for length = 1, 15 do
		left = left * 2 - count[length]
		if left < 0 then return nil, left end
	end
	offset[1] = 0
	for length = 1, 14 do offset[length + 1] = offset[length] + count[length] end
	for i = first, first + n - 1 do
		local length = lengths[i]
		if length ~= 0 then
			symbol[offset[length] + 1] = i - first
			offset[length] = offset[length] + 1
		end
	end
	return { count = count, symbol = symbol }, left
end

function Inflate.Fixed()
	if not Inflate.fixedLengths then
		local lengths = {}
		for symbol = 0, 287 do
			lengths[symbol + 1] = symbol < 144 and 8 or symbol < 256 and 9 or symbol < 280 and 7 or 8
		end
		for symbol = 0, 29 do lengths[289 + symbol] = 5 end
		Inflate.fixedLengths = Inflate.Code(lengths, 1, 288)
		Inflate.fixedDistances = Inflate.Code(lengths, 289, 30)
	end
	return Inflate.fixedLengths, Inflate.fixedDistances
end

-- The two codes of a dynamic block, from its header. An incomplete code is
-- only allowed when it has a single code, as in zlib.
function Inflate.Dynamic(Bits, Symbol)
	local nlen = Bits(5) + 257
	local ndist = Bits(5) + 1
	local ncode = Bits(4) + 4
	if nlen > 286 or ndist > 30 then error("damaged", 0) end
	local lengths = {}
	for i = 1, 19 do lengths[i] = 0 end
	for i = 1, ncode do lengths[Inflate.ORDER[i] + 1] = Bits(3) end
	local code, left = Inflate.Code(lengths, 1, 19)
	if not code or left ~= 0 then error("damaged", 0) end
	-- The lengths of both codes in one list; 16 repeats the last length,
	-- 17 and 18 write runs of zeros.
	local total, index = nlen + ndist, 0
	lengths = {}
	while index < total do
		local symbol = Symbol(code)
		if symbol < 16 then
			index = index + 1
			lengths[index] = symbol
		else
			local value, times = 0, nil
			if symbol == 16 then
				if index == 0 then error("damaged", 0) end
				value, times = lengths[index], 3 + Bits(2)
			elseif symbol == 17 then
				times = 3 + Bits(3)
			else
				times = 11 + Bits(7)
			end
			if index + times > total then error("damaged", 0) end
			for _ = 1, times do
				index = index + 1
				lengths[index] = value
			end
		end
	end
	if lengths[257] == 0 then error("damaged", 0) end -- no end-of-block code
	local literals, leftLiterals = Inflate.Code(lengths, 1, nlen)
	if not literals or (leftLiterals ~= 0 and nlen ~= literals.count[0] + literals.count[1]) then error("damaged", 0) end
	local distances, leftDistances = Inflate.Code(lengths, nlen + 1, ndist)
	if not distances or (leftDistances ~= 0 and ndist ~= distances.count[0] + distances.count[1]) then
		error("damaged", 0)
	end
	return literals, distances
end

-- How many bytes the raw DEFLATE stream `data` unpacks to. Errors with
-- "long" as soon as that passes `limit`, and with "damaged" where zlib
-- stops. Bytes after the last block are ignored, as zlib does.
function Inflate.Size(data, limit)
	local byte, POW2 = string.byte, Inflate.POW2
	local LENGTH_BASE, LENGTH_EXTRA = Inflate.LENGTH_BASE, Inflate.LENGTH_EXTRA
	local DISTANCE_BASE, DISTANCE_EXTRA = Inflate.DISTANCE_BASE, Inflate.DISTANCE_EXTRA
	-- pos: the next byte; held: the bits read from the bytes before it but
	-- not used yet (fewer than 8), the next one lowest.
	local pos, held, bits = 1, 0, 0

	local function Bits(need)
		while bits < need do
			local value = byte(data, pos)
			if not value then error("damaged", 0) end
			held = held + value * POW2[bits]
			pos, bits = pos + 1, bits + 8
		end
		local value = held % POW2[need]
		held = (held - value) / POW2[need]
		bits = bits - need
		return value
	end

	-- One symbol of a Huffman code. A code is packed starting with its
	-- first (most significant) bit, so it is read one bit at a time.
	local function Symbol(code)
		local count = code.count
		local value, first, index = 0, 0, 0
		for length = 1, 15 do
			if bits == 0 then
				held = byte(data, pos)
				if not held then error("damaged", 0) end
				pos, bits = pos + 1, 8
			end
			local bit = held % 2
			held, bits = (held - bit) / 2, bits - 1
			value = value + bit
			local n = count[length]
			if value - n < first then return code.symbol[index + value - first + 1] end
			index = index + n
			first = (first + n) * 2
			value = value * 2
		end
		error("damaged", 0)
	end

	local size, blocks, final = 0, 0, 0
	while final == 0 do
		-- Encoders write a block per hundreds of bytes or more. A stream of
		-- tiny blocks would only make this walk slow.
		blocks = blocks + 1
		if blocks > 256 + size / 64 then error("damaged", 0) end
		final = Bits(1)
		local kind = Bits(2)
		local literals, distances
		if kind == 0 then
			-- Stored: from the next whole byte, LEN, its complement, LEN bytes.
			held, bits = 0, 0
			local a, b, c, d = byte(data, pos, pos + 3)
			if not d or c + d * 256 ~= 65535 - (a + b * 256) then error("damaged", 0) end
			local length = a + b * 256
			pos = pos + 4 + length
			if pos - 1 > #data then error("damaged", 0) end
			size = size + length
		elseif kind == 1 then
			literals, distances = Inflate.Fixed()
		elseif kind == 2 then
			literals, distances = Inflate.Dynamic(Bits, Symbol)
		else
			error("damaged", 0)
		end
		while literals do
			local symbol = Symbol(literals)
			if symbol < 256 then
				size = size + 1
			elseif symbol == 256 then
				break
			else
				symbol = symbol - 256 -- 1 .. 29 for the lengths; 286 and 287 are not used
				if symbol > 29 then error("damaged", 0) end
				local length = LENGTH_BASE[symbol] + Bits(LENGTH_EXTRA[symbol])
				local code = Symbol(distances) + 1
				if code > 30 then error("damaged", 0) end
				-- A copy from before the start of the stream.
				if DISTANCE_BASE[code] + Bits(DISTANCE_EXTRA[code]) > size then error("damaged", 0) end
				size = size + length
			end
			if size > limit then error("long", 0) end
		end
		if size > limit then error("long", 0) end
	end
	return size
end

function E:Inflate(bytes, limit)
	local util, methods = C_EncodingUtil, Enum and Enum.CompressionMethod
	if not (util and util.DecompressString and methods) then return nil, "client" end
	if type(bytes) ~= "string" or type(limit) ~= "number" then return nil, "damaged" end
	local ok, problem = pcall(Inflate.Size, bytes, limit)
	if not ok then return nil, problem == "long" and "long" or "damaged" end
	local unpacked, text = pcall(util.DecompressString, bytes, methods.Deflate)
	if not unpacked or type(text) ~= "string" then return nil, "damaged" end
	if #text > limit then return nil, "long" end
	return text
end

-- prefix: "!EUI1!" for settings, a share kind's own prefix for the rest
-- (E:RegisterShareKind below).
local function Encode(text, prefix)
	prefix = prefix or PREFIX
	local util = C_EncodingUtil
	if util and util.CompressString and util.EncodeBase64 and Enum.CompressionMethod then
		local ok, packed = pcall(util.CompressString, text, Enum.CompressionMethod.Deflate)
		if ok and packed then
			local okB64, encoded = pcall(util.EncodeBase64, packed)
			if okB64 and encoded then return prefix .. "z" .. encoded end
		end
	end
	return prefix .. "p" .. Base64Encode(text)
end

local function Decode(text, prefix)
	prefix = prefix or PREFIX
	text = strtrim(text or "")
	if #text > MAX_STRING then error("the string is too long") end
	if text:sub(1, #prefix) ~= prefix then error("this is not an EldoUI string") end
	local flag, body = text:sub(#prefix + 1, #prefix + 1), text:sub(#prefix + 2)
	if flag == "z" then
		local util = C_EncodingUtil
		if not (util and util.DecodeBase64 and util.DecompressString) then error("this game client can't unpack compressed strings") end
		-- The unpacked text gets the same limit as a pasted one. E:Inflate
		-- checks it before the game unpacks anything.
		local out, problem = E:Inflate(util.DecodeBase64(body), MAX_STRING)
		if problem == "long" then error("the string is too long") end
		if problem == "client" then error("this game client can't unpack compressed strings") end
		if not out then error("the string is damaged") end
		return out
	elseif flag == "p" then
		return Base64Decode(body)
	end
	error("unknown string format")
end

---------------------------------------------------------------------------
-- Share kinds: data that is not a settings category (a wishlist, a talent
-- plan, a route, a character export) travels in its own string with its
-- own prefix, through the same encoder, import box and "Send to" path.
--
--   E:RegisterShareKind(kind, {
--       prefix   = "!EUW1!",                 -- "!EU" + letters/digits + "!", unique
--       title    = "Loot Guide wishlist",    -- or function(data) -> text
--       build    = function(arg) return tbl end,       -- for E:ExportShareKind / Send
--       describe = function(data) return text or { lines } end,  -- what the import shows
--       apply    = function(data) end,       -- after the player confirms
--       version  = 1,                        -- optional, stored in the string
--   })
--   E:EncodeShareData(kind, tbl[, yield])  -> string (or nil, err); yield
--                                 spreads the writing over a job's frames
--   E:DecodeShareData(text)       -> kind, tbl, version, schema (or nil, err);
--                                    schema = { unit, version } of the saved data, nil in older strings
--   E:ShareKindFor(text)          -> kind, def for a pasted string's prefix (no decoding)
--   E:ExportShareKind(kind, arg)  -> string from def.build(arg)
--   E:ImportShareData(text)       -> shows what the string holds and asks before def.apply
-- E:SendShare("share:<kind>[:<arg>]", target) offers one to a group, guild or
-- player (the receiver gets the normal confirmation). The payload holds only
-- what build returns: no character name is added. Strings are read by our
-- own deserializer: nothing pasted is ever run as code.
---------------------------------------------------------------------------
local shareKinds = {}

function E:RegisterShareKind(kind, def)
	assert(type(kind) == "string" and kind:match("^[%w_]+$"), "E:RegisterShareKind(kind, def): kind is letters, digits and _")
	assert(type(def) == "table" and type(def.prefix) == "string" and def.prefix:match("^!EU%w+!$") and def.prefix ~= PREFIX,
		"E:RegisterShareKind: prefix must look like \"!EUW1!\" and differ from \"!EUI1!\"")
	for other, otherDef in pairs(shareKinds) do
		assert(other == kind or otherDef.prefix ~= def.prefix, "E:RegisterShareKind: prefix " .. def.prefix .. " is taken by " .. other)
	end
	def.kind = kind
	shareKinds[kind] = def
end

function E:ShareKind(kind)
	return shareKinds[kind]
end

local function KindTitle(def, data)
	if type(def.title) == "function" then
		local ok, title = pcall(def.title, data)
		if ok and title then return tostring(title) end
	elseif def.title then
		return E:Translate(def.title)
	end
	return def.kind
end

-- The registered kind whose prefix starts a pasted string.
function E:ShareKindFor(text)
	if type(text) ~= "string" then return end
	text = strtrim(text)
	for kind, def in pairs(shareKinds) do
		if text:sub(1, #def.prefix) == def.prefix then return kind, def end
	end
end

-- yield (optional): Serialize's hook, for a job that writes a large code
-- over several frames. The job's own error path then catches a failure,
-- since a coroutine cannot yield across pcall.
function E:EncodeShareData(kind, data, yield)
	local def = shareKinds[kind]
	if not def then return nil, "unknown share kind " .. tostring(kind) end
	if type(data) ~= "table" then return nil, "nothing to share" end
	-- schema: which saved data version the data has, for the importer.
	local schema = { unit = kind, version = E:SchemaVersionFor(kind) }
	local payload = { kind = kind, v = def.version or 1, schema = schema, data = data }
	if kind == "pack" then
		data = PackData(data)
		if not data then return nil, L["the string is damaged or cut short. Copy it again in full."] end
		payload.data, payload.profileBaseline = data, data.profileBaseline
	end
	if yield then
		local text = Serialize(payload, yield)
		yield(true)   -- the packing gets a frame of its own too
		return Encode(text, def.prefix)
	end
	local ok, text = pcall(Serialize, payload)
	if not ok then return nil, tostring(text) end
	return Encode(text, def.prefix)
end

function E:DecodeShareData(text)
	local kind, def = self:ShareKindFor(text)
	if not kind then return nil, "this is not an EldoUI string" end
	local ok, payload = pcall(function()
		local value = Deserialize(Decode(text, def.prefix))
		if type(value) ~= "table" or value.kind ~= kind or type(value.data) ~= "table" then error("the string is damaged") end
		if kind == "pack" then
			local pack = PackData(value.data)
			if not pack or E.Secret(value.profileBaseline) or value.profileBaseline ~= pack.profileBaseline then error("the string is damaged") end
			value.data = pack
		end
		return value
	end)
	if not ok then
		local message = tostring(payload):gsub("^.-:%d+: ", "")
		if not (message:find("too long", 1, true) or message:find("client", 1, true)) then
			message = L["the string is damaged or cut short. Copy it again in full."]
		end
		-- The errors kept are English (they are matched above); shown
		-- translated: L["the string is too long"],
		-- L["this game client can't unpack compressed strings"], L["this is not an EldoUI string"]
		return nil, L[message]
	end
	return kind, payload.data, payload.v, payload.schema
end

function E:ExportShareKind(kind, arg)
	local def = shareKinds[kind]
	if not (def and def.build) then return nil end
	local ok, data = pcall(def.build, arg)
	if not ok then
		geterrorhandler()(data)
		return nil
	end
	if type(data) ~= "table" then return nil end
	return self:EncodeShareData(kind, data)
end

-- Lines that say what a share-kind string holds (for the import window).
local function DescribeKind(text)
	local kind, data = E:DecodeShareData(text)
	if not kind then return nil, data end
	local target = kind == "pack" and TargetAdmit()
	if kind == "pack" and not target then return nil, L["the string is damaged or cut short. Copy it again in full."] end
	local def = shareKinds[kind]
	local lines = { E:Highlight(L["EldoUI string:"]) .. " " .. KindTitle(def, data) }
	if def.describe then
		local ok, described = pcall(def.describe, data)
		if ok and type(described) == "table" then
			for _, line in ipairs(described) do lines[#lines + 1] = tostring(line) end
		elseif ok and described then
			lines[#lines + 1] = tostring(described)
		end
	end
	if kind == "pack" and not TargetAdmit(target) then return nil, L["the string is damaged or cut short. Copy it again in full."] end
	return lines, data, kind
end

local function ApplyKind(data, target, callback, definition)
	local def = data and shareKinds[data.kind]
	if not (def and def.apply) or def ~= definition then Completion(callback, false, "rejected"); return false end
	if data.kind == "pack" then
		if not TargetAdmit(target) or not PackData(data.data) then Completion(callback, false, "rejected"); return false end
		local ok, result, status = pcall(def.apply, data.data, callback)
		if not ok then geterrorhandler()(result); Completion(callback, false, "rejected"); return false end
		return result, status
	end
	local ok, result = pcall(def.apply, data.data)
	if not ok then geterrorhandler()(result) end
	Completion(callback, ok and result ~= false, ok and result ~= false and "applied" or "rejected")
	return ok and result ~= false, ok and result ~= false and "applied" or "rejected"
end

function E:ImportShareData(text, callback)
	local lines, data, kind = DescribeKind(text)
	if not lines then
		self:Print(L["Import failed: %s"]:format(tostring(data)))
		return false
	end
	local def = shareKinds[kind]
	if not def.apply then return false end
	local target = kind == "pack" and TargetAdmit()
	if kind == "pack" and not target then return false end
	local message = table.concat(lines, "\n") .. "\n\n" .. L["Import it? Nothing changes until you accept."]
	self:ShowConfirm({ key = "ELDOUI_IMPORT_KIND", title = L["Import"], text = message, accept = ACCEPT,
		data = { kind = kind, data = data }, onAccept = function(value)
			if not Plain(value) or E.Secret(value.kind) or value.kind ~= kind or E.Secret(value.data) or value.data ~= data then return false end
			return ApplyKind(value, target, callback, def)
		end, onCancel = function() Completion(callback, false, "cancelled") end })
	return true, "pending"
end

-- True for anything the importer reads (compressed or readable).
function E:IsShareString(text)
	text = strtrim(text or "")
	return text:sub(1, #PREFIX) == PREFIX or text:sub(1, #LUA_HEADER) == LUA_HEADER or self:ShareKindFor(text) ~= nil
end

---------------------------------------------------------------------------
-- Categories
---------------------------------------------------------------------------
local function MoversOf(moduleName)
	local positions = {}
	for _, name in ipairs(E:ModuleMoverNames(moduleName)) do
		if E.db.movers[name] then positions[name] = CopyTable(E.db.movers[name]) end
	end
	return positions
end

function E:GetShareCategories()
	local list = {
		{ key = "all", title = L["Everything (whole profile)"] },
		{ key = "general", title = L["General (theme, fonts, scale)"] },
		{ key = "positions", title = L["All frame positions"] },
	}
	for name, module in self:IterateModules() do
		table.insert(list, { key = "module:" .. name, title = module.title })
	end
	local globals = self.SharedGlobals and self:SharedGlobals() or {}
	if #globals > 0 then
		table.insert(list, { key = "global", title = L["Account-wide lists (all)"] })
		for _, entry in ipairs(globals) do
			table.insert(list, { key = "global:" .. entry.key, title = entry.title, global = true })
		end
	end
	return list
end

local function CategoryTitle(key)
	local shareKind = type(key) == "string" and key:match("^share:([%w_]+)")
	if shareKind and shareKinds[shareKind] then return KindTitle(shareKinds[shareKind]) end
	for _, entry in ipairs(E:GetShareCategories()) do
		if entry.key == key then return entry.title end
	end
	local namespace = type(key) == "string" and key:match("^global:(.+)$")
	if namespace then return namespace end
	return tostring(key)
end

local function GlobalDefaults(namespace)
	local spec = E.globalSpecs and E.globalSpecs[namespace]
	return spec and spec.defaults
end

-- Strings carry only values that differ from the defaults: they stay
-- short, and importing one never overwrites the receiver's defaults with
-- the sender's older ones. The importer fills the defaults back in.
local function BuildPayload(key)
	local target = ProfileKind(key) and TargetAdmit()
	if ProfileKind(key) and not target then return nil end
	local payload = { kind = key, version = E.version, author = UnitName("player"), schema = { unit = "profile", version = E.PROFILE_SCHEMA } }
	if target then
		payload.profileBaseline, payload.schema.version = target.profile.profileBaseline, target.profile.schema
		-- A part of a profile carries the profile's migration stamps (a whole
		-- profile has them inside): the importer then runs exactly the
		-- migrations the sender's profile has not had (MigratePart below).
		local stamps = key ~= "all" and rawget(target.profile, "migrations")
		if stamps and Plain(stamps) then payload.migrations = CopyTable(stamps) end
	end
	if key == "all" then
		payload.data = E:CompactProfile(E:CopyProfileTable())
	elseif key == "general" then
		payload.data = E:CopyWithoutDefaults(E.db.general, E.defaults.general)
	elseif key == "positions" then
		payload.data = CopyTable(E.db.movers or {})
		-- The dragged game windows travel beside the frames.
		payload.windows = E.WindowPlaces and E:WindowPlaces(E.db.windowMover and E.db.windowMover.windows) or nil
	elseif key == "global" then
		payload.data = {}
		for _, entry in ipairs(E:SharedGlobals()) do
			payload.data[entry.key] = E:CopyWithoutDefaults(E:GetGlobal(entry.key), GlobalDefaults(entry.key))
		end
	elseif key:match("^global:") then
		local namespace = key:match("^global:(.+)$")
		local data = E:GetGlobal(namespace)
		if type(data) ~= "table" then return nil end
		payload.data = E:CopyWithoutDefaults(data, GlobalDefaults(namespace))
	else
		local name = key:match("^module:(.+)$")
		local module = name and E.modules[name]
		if not module then return nil end
		payload.data = E:CopyWithoutDefaults(module.db, module.defaults)
		payload.movers = MoversOf(name)
	end
	if target and (key == "all" or key == "general") and Plain(payload.data) then
		local general = key == "all" and payload.data.general or payload.data
		if Plain(general) and type(rawget(general, "layout")) ~= "nil" then
			local envelope, supported = CaptureDependencies(general.layout)
			if not supported then return nil, "layout" end
			payload.layoutDependencies = envelope
		end
	end
	if target and (not PayloadAdmit(payload) or not TargetAdmit(target)) then return nil end
	return payload
end

local function LuaText(payload)
	local out = { ("%s %s export: %s\n-- Readable copy of the settings. Paste it into /eui import to load it.\n"):format(
		LUA_HEADER, tostring(payload.version), CategoryTitle(payload.kind)) }
	WriteLua(payload, out, "", 0)
	out[#out + 1] = "\n"
	return table.concat(out)
end

-- format: nil (compact string) or "lua" (readable table).
function E:ExportString(key, format)
	-- "share:<kind>[:<arg>]": a registered share kind (always the compact string).
	local shareKind, arg = (type(key) == "string" and key or ""):match("^share:([%w_]+):?(.*)$")
	if shareKind then return self:ExportShareKind(shareKind, arg ~= "" and arg or nil) end
	local payload, why = BuildPayload(key or "all")
	if not payload then return nil, why end
	if format == "lua" then return LuaText(payload) end
	return Encode(Serialize(payload))
end

function E:ShowExport(key, format)
	key = key or "all"
	local text, why = self:ExportString(key, format)
	if not text then
		if why == "layout" then
			self:Print(L["%s uses a layout that can't be put in a string, so it can't be exported."]:format(CategoryTitle(key)))
		else
			self:Print(L["Nothing to export for %s."]:format(CategoryTitle(key)))
		end
		return
	end
	if format == "lua" then
		self:ShowCopyBox(L["Readable export: %s"]:format(CategoryTitle(key)),
			L["Everything is selected. Press Ctrl+C. Good for bug reports and comparing setups; /eui import reads it back too."], text)
	else
		self:ShowCopyBox(L["Export: %s"]:format(CategoryTitle(key)),
			L["Everything is selected. Press Ctrl+C and share it. Others paste it under Import."], text)
	end
end

---------------------------------------------------------------------------
-- Import
---------------------------------------------------------------------------
local function ParseString(text)
	local ok, result = pcall(function()
		text = strtrim(text or "")
		if #text > MAX_STRING then error("the string is too long") end
		local payload
		if text:sub(1, #LUA_HEADER) == LUA_HEADER or text:sub(1, 1) == "{" then
			payload = ReadLua(text)
		else
			payload = Deserialize(Decode(text))
		end
		if type(payload) ~= "table" or type(payload.kind) ~= "string" or type(payload.data) ~= "table" then
			error("the string is damaged")
		end
		-- Mover positions travel as a table of tables; anything else stops
		-- here, before a setting changes.
		local movers = payload.kind == "positions" and payload.data or payload.movers
		for _, set in ipairs({ movers, payload.kind == "positions" and payload.windows or nil }) do
			if type(set) ~= "table" then error("the string is damaged") end
			for name, position in pairs(set) do
				if type(name) ~= "string" or type(position) ~= "table" then error("the string is damaged") end
			end
		end
		local admitted, why = PayloadAdmit(payload)
		if not admitted then error(why and { reason = why } or "the string is damaged") end
		return payload
	end)
	if ok then return result end
	if type(result) == "table" and type(result.reason) == "string" then return nil, result.reason end
	local message = tostring(result):gsub("^.-:%d+: ", "")
	if not (message:find("EldoUI string", 1, true) or message:find("too long", 1, true) or message:find("client", 1, true)) then
		message = L["the string is damaged or cut short. Copy it again in full."]
	end
	return nil, L[message]
end
E.ParseShareString = function(_, text) return ParseString(text) end

-- Modules (with titles) a whole-profile payload carries settings for.
local function PayloadModules(payload)
	local list = {}
	local modules = payload.kind == "all" and type(payload.data.modules) == "table" and payload.data.modules or {}
	for name in pairs(modules) do
		local module = E.modules[name]
		list[#list + 1] = { name = name, title = module and module.title or name, installed = module ~= nil }
	end
	table.sort(list, function(a, b) return tostring(a.title) < tostring(b.title) end)
	return list
end

-- Lines describing a string, for the import window (Core/Import.lua).
function E:DescribeShareString(text)
	if self:ShareKindFor(text) then return DescribeKind(text) end
	local payload, err = ParseString(text)
	if not payload then return nil, err end
	local target = ProfileKind(payload.kind) and TargetAdmit()
	if ProfileKind(payload.kind) and not target then return nil, L["the string is damaged or cut short. Copy it again in full."] end
	local lines = {
		E:Highlight(L["EldoUI string:"]) .. " " .. CategoryTitle(payload.kind),
		L["From %s, EldoUI %s, %.1f KB."]:format(type(payload.author) == "string" and payload.author or L["someone"],
			tostring(payload.version), #strtrim(text) / 1024),
	}
	local modules = PayloadModules(payload)
	if #modules > 0 then
		local names = {}
		for _, entry in ipairs(modules) do names[#names + 1] = entry.installed and entry.title or (entry.title .. L[" (not installed)"]) end
		lines[#lines + 1] = L["Changed modules: %s."]:format(table.concat(names, ", "))
	end
	if payload.kind == "all" then
		lines[#lines + 1] = L["Import makes it a new profile, or pick the parts you want in your current profile."]
	else
		lines[#lines + 1] = L["Import replaces your current settings for this part."]
	end
	if target and not TargetAdmit(target) then return nil, L["the string is damaged or cut short. Copy it again in full."] end
	return lines, payload
end

-- Only the lists Export offers (registered with share = true) come back in.
-- Every other account-wide store (notes, ledgers, bar snapshots, the
-- character list) is never replaced by a string.
local function ApplyGlobal(namespace, data)
	local spec = E.globalSpecs and E.globalSpecs[namespace]
	if not (spec and spec.share) or type(data) ~= "table" then return false end
	E.global[namespace] = E.ApplyDefaults(CopyTable(data), spec.defaults or {})
	return true
end

-- Migration stamps from a string (migration key = version reached), or nil
-- when there are none or they are not in that shape.
local function Stamps(value)
	if not Plain(value) then return nil end
	local stamps = {}
	for key, version in pairs(value) do
		if type(key) ~= "string" or type(version) ~= "number" or version ~= version or version < 0 or version >= math.huge then return nil end
		stamps[key] = version
	end
	if next(stamps) == nil then return nil end
	return stamps
end

local function Table(value)
	return Plain(value) and value or {}
end

-- A part of a profile (one module with its frames, the general settings,
-- all frame positions) gets the updates a whole profile gets when it loads:
-- the default changes of the versions after the one that wrote the string
-- (Data/DefaultChanges.lua), then the profile migrations. They run on a
-- stand-in profile that holds only this part, next to a copy of the
-- receiver's general settings (some migrations read the layout); only the
-- part comes back out. A whole profile goes through E:SetProfile or
-- E:ApplyProfileParts, which do this themselves.
-- With the sender's migration stamps (strings this fork writes after
-- 0.7.2001-p1), the keyed migrations their profile has not had run.
-- Without stamps (EldoUI itself, older strings) only the migrations that
-- run every time do: a keyed migration can't tell an old value from a
-- choice the sender made later, and could undo it.
-- data and movers are the caller's copies; they may be changed.
local function MigratePart(payload, data, movers)
	local kind, schema = payload.kind, payload.schema
	local from = Plain(schema) and schema.version
	if E.Secret(from) or type(from) ~= "number" then return nil end
	local stamps = Stamps(rawget(payload, "migrations"))
	local shell = { profileBaseline = payload.profileBaseline, schema = from, migrations = stamps }
	local name
	if kind == "general" then
		shell.general = data
	else
		shell.general = CopyTable(Table(E.db.general))
		if kind == "positions" then
			shell.movers = data
		else
			name = kind:match("^module:(.+)$")
			if not name then return nil end
			shell.modules = { [name] = data }
			shell.movers = movers
		end
	end
	if from < E.PROFILE_SCHEMA then E:ApplyDefaultChanges(shell, from) end
	E:RunProfileMigrations(shell, nil, stamps == nil)
	if kind == "general" then return Table(shell.general) end
	if kind == "positions" then return Table(shell.movers) end
	local modules = Table(shell.modules)
	return Table(modules[name]), type(movers) ~= "nil" and Table(shell.movers) or nil
end

-- MigratePart in a pcall: a failure goes to the error log and stops the import.
local function MigratedPart(payload, data, movers)
	local ok, part, partMovers = pcall(MigratePart, payload, data, movers)
	if not ok then geterrorhandler()(part); return nil end
	return part, partMovers
end

local function Finish(kind)
	E:Print(L["Imported %s."]:format(E:Highlight(CategoryTitle(kind))))
	E:ShowReloadPrompt(L["Imported %s. Some parts take full effect after a reload."]:format(CategoryTitle(kind)))
	if E.RefreshConfig then E:RefreshConfig() end
end

local function UniqueProfileName(name)
	if not EldoUIDB.profiles[name] then return name end
	local index = 2
	while EldoUIDB.profiles[("%s (%d)"):format(name, index)] do index = index + 1 end
	return ("%s (%d)"):format(name, index)
end

local function ApplyPayload(payload, profileName, target)
	local kind = payload.kind
	if ProfileKind(kind) then
		target = TargetAdmit(target)
		if not target or not PayloadAdmit(payload) or not TargetAdmit(target) then return false end
	end
	if kind == "all" then
		-- Never overwrite a profile (not even the active one) with the
		-- fallback name, and say why a typed name was not used.
		local check, data = E.CheckProfileName, payload.data
		if E.Secret(check) or type(check) ~= "function" then return false end
		local name, why = check(E, profileName)
		if E.Secret(name) or E.Secret(why) or (type(name) ~= "nil" and type(name) ~= "string")
			or (type(why) ~= "nil" and type(why) ~= "string") or E.Secret(E.CheckProfileName) or E.CheckProfileName ~= check
			or not TargetAdmit(target) or not PayloadAdmit(payload) or E.Secret(payload.kind) or payload.kind ~= kind
			or E.Secret(payload.data) or payload.data ~= data or not TargetAdmit(target) then return false end
		name = UniqueProfileName(name or L["Imported"])
		if why and profileName ~= nil and strtrim(tostring(profileName)) ~= "" then
			E:Print(L["%s The profile is called %s instead."]:format(why, name))
		end
		if not TargetAdmit(target) or not PayloadAdmit(payload) or E.Secret(E.CheckProfileName) or E.CheckProfileName ~= check
			or E.Secret(payload.kind) or payload.kind ~= kind or E.Secret(payload.data) or payload.data ~= data or not TargetAdmit(target) then return false end
		local setter, root = E.SetProfile, target.root
		local profiles = rawget(root, "profiles")
		if E.Secret(setter) or type(setter) ~= "function" or not Plain(profiles) then return false end
		local working = MaterializeDependencies(payload, CopyTable(data), target)
		if not working or not PayloadAdmit(payload) or E.Secret(payload.data) or payload.data ~= data
			or not TargetAdmit(target) or E.Secret(E.SetProfile) or E.SetProfile ~= setter
			or rawget(root, "profiles") ~= profiles or rawget(profiles, name) ~= nil then return false end
		profiles[name] = working
		local changed = setter(E, name)
		local current = TargetAdmit()
		if E.Secret(changed) or changed ~= true or not current or current.root ~= root or current.profile ~= working or current.name ~= name
			or E.Secret(E.SetProfile) or E.SetProfile ~= setter then return false end
	elseif kind == "general" then
		local working = MaterializeDependencies(payload, CopyTable(payload.data), target)
		if not working or not TargetAdmit(target) then return false end
		working = MigratedPart(payload, working)
		if not working or not TargetAdmit(target) then return false end
		-- The look only: the layout stays (a whole profile brings its own).
		for _, key in ipairs(E.LAYOUT_KEYS) do
			local value = E.db.general[key]
			working[key] = type(value) == "table" and CopyTable(value) or value
		end
		E.db.general = working
		E.ApplyDefaults(E.db.general, E.defaults.general)
		E:RefreshTheme()
		E:RunOutOfCombat(function() if TargetAdmit(target) then E:ApplyScale() end end)
	elseif kind == "positions" then
		local working = MigratedPart(payload, CopyTable(payload.data))
		if not working or not TargetAdmit(target) then return false end
		E.db.movers = working
		E:RefreshMovers()
		-- Strings made before the game windows traveled carry none: theirs stay.
		if type(payload.windows) == "table" and E.SetWindowPlaces then E:SetWindowPlaces(payload.windows) end
	elseif kind == "global" then
		local count = 0
		for namespace, data in pairs(payload.data) do
			if ApplyGlobal(namespace, data) then count = count + 1 end
		end
		if count == 0 then
			E:Print(L["None of these lists exist in your EldoUI."])
			return
		end
		E:RefreshTheme()
	elseif kind:match("^global:") then
		local namespace = kind:match("^global:(.+)$")
		if not ApplyGlobal(namespace, payload.data) then
			local shown = (namespace:gsub("|", "||"))
			if E.globalSpecs and E.globalSpecs[namespace] then
				E:Print(L["This list can't be imported from a string (%s)."]:format(shown))
			else
				E:Print(L["This string holds a list your EldoUI doesn't have (%s)."]:format(shown))
			end
			return
		end
		E:RefreshTheme()
	else
		local name = kind:match("^module:(.+)$")
		local module = name and E.modules[name]
		if not module then
			E:Print(L["This string is for the %s module, which isn't installed."]:format(tostring(name)))
			return
		end
		local migrated, movers = MigratedPart(payload, CopyTable(payload.data), Plain(payload.movers) and CopyTable(payload.movers) or nil)
		if not migrated or not TargetAdmit(target) then return false end
		local enabled = module.db.enabled
		E:ReplaceModuleSettings(module, migrated)
		if not E:ModuleStatesPerCharacter() then module.db.enabled = enabled end
		for moverName, position in pairs(movers or {}) do E.db.movers[moverName] = position end
		if module.active and module.OnProfileChanged then
			local settings = module.db
			E:RunOutOfCombat(function()
				if not TargetAdmit(target) then return end
				local bound, current = E.modules[name], module.db
				if not E.Secret(bound) and bound == module and not E.Secret(current) and current == settings then module:OnProfileChanged() end
			end)
		end
		E:RefreshMovers()
	end
	if ProfileKind(kind) and kind ~= "all" and not TargetAdmit(target) then return false end
	Finish(kind)
	return true, "applied"
end

---------------------------------------------------------------------------
-- Checklist window: pick parts (modules) from a list. Used by "Copy parts
-- from a profile" and by importing parts of a whole-profile string.
--   E:ShowChecklist({ title, text, accept, items = { { key, label, desc, checked } },
--                     extras = { { key, label, desc, checked } }, onAccept = function(picked, extras) end })
---------------------------------------------------------------------------
local checklist
local CHECK_ROW = 24

-- The checklist on the shared tool window shell (E.UIKit):
-- header-font title, accent line, kit checks, buttons and scroll area.
local function ChecklistButton(parent, text, width, large, kind)
	return E.UIKit.Button(parent, text, { width = width or 110, large = large, kind = kind })
end

local function MakeCheck(parent, onClick)
	return E.UIKit.Check(parent, "", nil, onClick)
end

local function CreateChecklist()
	local Kit = E.UIKit
	local frame = Kit.CreateToolWindow("EldoUIChecklist", { width = 440, height = 520, strata = "DIALOG",
		footer = Kit.TOOL_FOOTER + 8 })
	frame.text = Kit.Text(frame.content, E.tokens.size.label, "LEFT", "secondary")
	frame.text:SetPoint("TOPLEFT", 4, -4)
	frame.text:SetPoint("TOPRIGHT", -4, -4)
	frame.text:SetWordWrap(true)
	frame.text:SetJustifyV("TOP")

	local holder = CreateFrame("Frame", nil, frame.content)
	holder:SetPoint("TOPLEFT", 0, -44)
	holder:SetPoint("BOTTOMRIGHT", 0, 64)
	E:SetTemplate(holder, true)
	frame.area = Kit.ScrollArea(holder)
	frame.area:SetPoint("TOPLEFT", 6, -6)
	frame.area:SetPoint("BOTTOMRIGHT", -6, 6)
	frame.list = frame.area.child
	frame.checks, frame.extraChecks = {}, {}

	frame.all = ChecklistButton(frame.content, L["Select all"], 100)
	frame.all:SetPoint("TOPLEFT", holder, "BOTTOMLEFT", 0, -8)
	frame.none = ChecklistButton(frame.content, L["Select none"], 100)
	frame.none:SetPoint("LEFT", frame.all, "RIGHT", 8, 0)
	local function SetAll(value)
		for _, check in ipairs(frame.checks) do
			if check:IsShown() then check:SetChecked(value) end
		end
		frame:Update()
	end
	frame.all:SetScript("OnClick", function() SetAll(true) end)
	frame.none:SetScript("OnClick", function() SetAll(false) end)

	frame.accept = ChecklistButton(frame.footer, ACCEPT, 120, true, "primary")
	frame.accept:SetPoint("RIGHT", -8, 0)
	frame.cancel = ChecklistButton(frame.footer, CANCEL, 120, true)
	frame.cancel:SetPoint("RIGHT", frame.accept, "LEFT", -8, 0)
	frame.cancel:SetScript("OnClick", function() frame:Close() end)
	frame.accept:SetScript("OnClick", function()
		local picked, extras = {}, {}
		for _, check in ipairs(frame.checks) do
			if check:IsShown() and check:GetChecked() then picked[check.key] = true end
		end
		for _, check in ipairs(frame.extraChecks) do
			if check:IsShown() and check:GetChecked() then extras[check.key] = true end
		end
		local onAccept = frame.onAccept
		frame.onAccept, frame.onCancel = nil, nil
		frame:Hide()
		if onAccept then onAccept(picked, extras) end
	end)

	function frame:Update()
		local any = false
		for _, check in ipairs(self.checks) do
			if check:IsShown() and check:GetChecked() then any = true end
		end
		self.accept:SetEnabled(any)
	end

	frame:HookScript("OnHide", function()
		local cancel = frame.onCancel
		frame.onAccept, frame.onCancel = nil, nil
		if not E.Secret(cancel) and type(cancel) == "function" then cancel() end
	end)
	frame:Hide()
	return frame
end

function E:ShowChecklist(spec)
	checklist = checklist or CreateChecklist()
	local frame = checklist
	frame:SetTitle(spec.title or "")
	frame.text:SetText(spec.text or "")
	frame.accept:SetText(spec.accept or ACCEPT)
	local cancel = frame.onCancel
	frame.onCancel = nil
	if not E.Secret(cancel) and type(cancel) == "function" then cancel() end
	frame.onAccept, frame.onCancel = spec.onAccept, spec.onCancel
	for _, check in ipairs(frame.checks) do check:Hide() end
	for _, check in ipairs(frame.extraChecks) do check:Hide() end
	for index, item in ipairs(spec.items or {}) do
		local check = frame.checks[index]
		if not check then
			check = MakeCheck(frame.list, function() frame:Update() end)
			frame.checks[index] = check
		end
		check.key = item.key
		check:SetLabel(item.label)
		check:SetChecked(item.checked and true or false)
		check:ClearAllPoints()
		check:SetPoint("TOPLEFT", 4, -4 - (index - 1) * CHECK_ROW)
		E.UIKit.Tooltip(check, item.desc and item.label or nil, item.desc)
		check:Show()
	end
	frame.list:SetHeight(math.max(10, #(spec.items or {}) * CHECK_ROW + 8))
	for index, item in ipairs(spec.extras or {}) do
		local check = frame.extraChecks[index]
		if not check then
			check = MakeCheck(frame.content)
			frame.extraChecks[index] = check
		end
		check.key = item.key
		check:SetLabel(item.label)
		check:SetChecked(item.checked and true or false)
		check:ClearAllPoints()
		check:SetPoint("TOPLEFT", frame.all, "BOTTOMLEFT", 0, -6 - (index - 1) * CHECK_ROW)
		E.UIKit.Tooltip(check, item.desc and item.label or nil, item.desc)
		check:Show()
	end
	frame:Update()
	frame:Show()
	frame:Raise()
	frame.area:Update()
	frame.area:ScrollToTop()
	return frame
end

-- The parts of a profile as checklist items.
local function PartItems(source, onlyChanged)
	local items = {
		{ key = "general", label = L["General (theme, fonts, scale)"], desc = L["Accent color, art style, fonts, bar texture, colors and the other General settings. Your layout stays; check Layout to take that too."] },
		{ key = "layout", label = L["Layout"], desc = L["The layout that places your frames: applied as when you pick it on the Layouts page, with its frame sizes."] },
		{ key = "blizzard", label = L["Blizzard UI switches"], desc = L["Which parts of Blizzard's UI EldoUI may change (Blizzard UI page)."] },
	}
	local modules = type(source.modules) == "table" and source.modules or {}
	for name, module in E:IterateModules() do
		if not onlyChanged or modules[name] then
			items[#items + 1] = { key = "module:" .. name, label = module.title, desc = module.desc ~= "" and module.desc or nil }
		end
	end
	table.sort(items, function(a, b)
		local ma, mb = a.key:find("^module:") ~= nil, b.key:find("^module:") ~= nil
		if ma ~= mb then return mb end
		return a.label < b.label
	end)
	return items
end

local function PartsFrom(picked, extras)
	local parts = { modules = {}, general = picked.general, layout = picked.layout, blizzard = picked.blizzard, positions = extras.positions }
	for key in pairs(picked) do
		local name = key:match("^module:(.+)$")
		if name then parts.modules[name] = true end
	end
	return parts
end

local function ReportCopied(ok, copied, from)
	if ok and copied and #copied > 0 then
		E:Print(L["Copied from %s: %s."]:format(from, table.concat(copied, ", ")))
		E:ShowReloadPrompt(L["Copied settings from %s. Some parts take full effect after a reload."]:format(from))
	elseif ok then
		E:Print(L["Nothing was copied."])
	end
	if E.RefreshConfig then E:RefreshConfig() end
end

-- Profiles page: pick modules to pull from another profile.
function E:ShowCopyParts(from)
	if E.Secret(from) or type(from) ~= "string" then return end
	local target = TargetAdmit()
	if not target or from == self.profileName then return end
	local source = rawget(target.root.profiles, from)
	if not ProfileAdmit(source, from) then return end
	local copy = self:CopyProfileTable(from)
	if not SourceAdmit(copy) or not TargetAdmit(target) or not ProfileAdmit(source, from) then return end
	self:ShowChecklist({
		title = L["Copy from %s"]:format(from),
		text = L["Check what to copy into your profile %s. Everything else stays as it is; modules keep their own on/off state."]:format(self.profileName),
		accept = L["Copy"],
		items = PartItems(copy),
		extras = { { key = "positions", label = L["Include frame positions"], checked = true,
			desc = L["Move the chosen modules' frames to where they are in the other profile."] } },
		onAccept = function(picked, extras)
			if not TargetAdmit(target) or not ProfileAdmit(source, from) then return false end
			self:RunOutOfCombat(function()
				if not TargetAdmit(target) or not ProfileAdmit(source, from) then return end
				local ok, copied
				self:ChangeProfileWithUndo(self.profileName, "parts", function()
					ok, copied = self:CopyProfileParts(from, PartsFrom(picked, extras))
					return ok
				end)
				ReportCopied(ok, copied, from)
			end)
		end,
	})
end

-- Import: pick parts of a whole-profile string into the current profile.
local function ShowImportParts(payload, target, callback)
	if not PayloadAdmit(payload) or not TargetAdmit(target) then return false end
	local source = payload.data
	local apply = E.ApplyProfileParts
	if E.Secret(apply) or type(apply) ~= "function" then return false end
	E:ShowChecklist({
		title = L["Import parts"],
		text = L["Check what to take from this string into your profile %s. Unchecked parts stay as they are."]:format(E.profileName),
		accept = L["Import"],
		items = PartItems(source, true),
		extras = { { key = "positions", label = L["Include frame positions"], checked = true,
			desc = L["Move the chosen modules' frames to where the string has them."] } },
		onAccept = function(picked, extras)
			if not PayloadAdmit(payload) or payload.data ~= source or not TargetAdmit(target)
				or E.Secret(E.ApplyProfileParts) or E.ApplyProfileParts ~= apply then Completion(callback, false, "rejected"); return false end
			E:RunOutOfCombat(function()
				if not PayloadAdmit(payload) or payload.data ~= source or not TargetAdmit(target)
					or E.Secret(E.ApplyProfileParts) or E.ApplyProfileParts ~= apply then Completion(callback, false, "rejected"); return end
				local parts = PartsFrom(picked, extras)
				local working = CopyTable(source)
				if parts.general or parts.layout then working = MaterializeDependencies(payload, working, target) end
				if not working or not TargetAdmit(target) or E.Secret(E.ApplyProfileParts)
					or E.ApplyProfileParts ~= apply then Completion(callback, false, "rejected"); return end
				local ok, copied
				E:ChangeProfileWithUndo(E.profileName, "import", function()
					ok, copied = apply(E, working, parts)
					return ok
				end)
				local from = type(payload.author) == "string" and payload.author or L["the string"]
				if not TargetAdmit(target) or E.Secret(E.ApplyProfileParts)
					or E.ApplyProfileParts ~= apply then Completion(callback, false, "rejected"); return end
				ReportCopied(ok, copied, from)
				Completion(callback, ok == true, ok == true and "applied" or "rejected")
			end)
		end,
		onCancel = function() Completion(callback, false, "cancelled") end,
	})
end



local function AcceptImport(payload, text, target, callback)
	if not Plain(payload) or E.Secret(payload.kind) then Completion(callback, false, "rejected"); return false end
	if ProfileKind(payload.kind) then
		if not TargetAdmit(target) or not PayloadAdmit(payload) or not TargetAdmit(target) then Completion(callback, false, "rejected"); return false end
		if E.Secret(text) or (type(text) ~= "nil" and type(text) ~= "string") then Completion(callback, false, "rejected"); return false end
	end
	if payload.kind == "all" or payload.kind == "general" then
		local result, status, ran
		E:RunOutOfCombat(function()
			ran = true
			if not TargetAdmit(target) or not PayloadAdmit(payload) or not TargetAdmit(target) then Completion(callback, false, "rejected"); return end
			if payload.kind == "general" then
				E:ChangeProfileWithUndo(E.profileName, "import", function()
					result, status = ApplyPayload(payload, text, target)
					return result
				end)
			else
				result, status = ApplyPayload(payload, text, target)
			end
			Completion(callback, result == true, status or "rejected")
		end, "Share:import")
		if not ran then return false, "queued" end
		return result, status
	end
	local result, status
	if ProfileKind(payload.kind) then
		E:ChangeProfileWithUndo(E.profileName, "import", function()
			result, status = ApplyPayload(payload, text, target)
			return result
		end)
	else
		result, status = ApplyPayload(payload, text, target)
	end
	Completion(callback, result == true, status or "rejected")
	return result, status
end

function E:ImportString(text, callback)
	if E.Secret(callback) or (type(callback) ~= "nil" and type(callback) ~= "function") then return false, "rejected" end
	if self:ShareKindFor(text) then return self:ImportShareData(text, callback) end
	local payload, err = ParseString(text)
	if not payload then
		self:Print(L["Import failed: %s"]:format(err))
		return false, "rejected"
	end
	local what = CategoryTitle(payload.kind)
	local from = type(payload.author) == "string" and payload.author or L["someone"]
	local message = L["Import %s from %s (EldoUI %s)?"]:format(E:Highlight(what), from, tostring(payload.version))
	if payload.kind == "all" then message = message .. "\n\n" .. L["It becomes a new profile with this name (or choose parts for your current profile):"]
	else message = message .. "\n\n" .. L["Your current settings for this part are replaced."] end
	local whole = payload.kind == "all"
	local originalKind, originalData = payload.kind, payload.data
	local target = ProfileKind(payload.kind) and TargetAdmit()
	if ProfileKind(payload.kind) and not target then return false, "rejected" end
	self:ShowConfirm({ key = "ELDOUI_IMPORT", title = L["Import"], text = message, accept = ACCEPT, data = payload,
		onAccept = function(data, name)
			if not Plain(data) or data ~= payload or E.Secret(data.kind) or data.kind ~= originalKind or E.Secret(data.data) or data.data ~= originalData then Completion(callback, false, "rejected"); return false end
			return AcceptImport(data, name, target, callback)
		end,
		onCancel = function() Completion(callback, false, "cancelled") end,
		edit = whole and { text = UniqueProfileName(type(payload.author) == "string" and L["From %s"]:format(payload.author) or L["Imported"]) } or nil,
		extra = whole and { L["Choose parts..."], function(data)
			if not Plain(data) or data ~= payload or E.Secret(data.kind) or data.kind ~= originalKind or E.Secret(data.data) or data.data ~= originalData then return false end
			return ShowImportParts(data, target, callback)
		end } or nil })
	return true, "pending"
end

-- The import window (Core/Import.lua) takes EldoUI strings too and shows
-- what a string changes before it is applied; the paste box is the
-- fallback when that file isn't loaded.
function E:ShowImport()
	if self.ShowImportWindow then
		self:ShowImportWindow()
		return
	end
	self:ShowPasteBox(L["Import an EldoUI string"], L["Paste a string (Ctrl+V) and click Save. You see what it contains before anything changes."],
		function(text) self:ImportString(text) end)
end

---------------------------------------------------------------------------
-- Send to a player (addon messages)
--
--   sender                          receiver
--   O <id> <kind> <bytes> <chunks>  -> popup: accept / decline
--                                   <- A <id>  (or N <id>)
--   D <id> <index> <text>  ...      -> collects; when complete, the normal
--                                      import confirmation shows
-- The receiver only listens to group members, guild members and friends,
-- and nothing is applied without its clicks. Sending waits while addon
-- messages are restricted (boss encounters, PvP matches, chat
-- lockdown) and resumes when the restriction lifts.
---------------------------------------------------------------------------
local COMM = "EldoUI"
local CHUNK = 220
local SEND_INTERVAL = 0.2   -- between chunks; the shared queue keeps to the game rate
local OFFER_TIMEOUT = 90    -- seconds an offer waits for an answer
local OFFER_COOLDOWN = 30   -- seconds before the same sender's next offer shows
local RECEIVE_TIMEOUT = 120 -- seconds without a chunk before a transfer is dropped
local MAX_CHUNKS = math.ceil(MAX_STRING / CHUNK)

local outgoing = {}  -- id -> { text, kind, target, channel, started }
local transfers = {} -- queue of { id, target, next = 1, chunks = {} }
local incoming = {}  -- sender -> { id, kind, bytes, total, parts = {}, got = 0, accepted, last }
local offerTimes = {} -- sender -> GetTime() of their last offer (OFFER_COOLDOWN)
local sending = false
local prefixReady = false
local commOwner = {}

local function RegisterPrefix()
	if prefixReady then return true end
	if not (C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix) then return false end
	pcall(C_ChatInfo.RegisterAddonMessagePrefix, COMM)
	prefixReady = true
	return true
end

-- True while addon messages can't go out (encounters, keys, PvP, lockdown).
function E:AddonCommsRestricted()
	if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown then
		local ok, locked = pcall(C_ChatInfo.InChatMessagingLockdown)
		if ok and locked then return true end
	end
	local restricted, types = C_RestrictedActions, Enum.AddOnRestrictionType
	if restricted and restricted.IsAddOnRestrictionActive and types then
		for _, key in ipairs({ "Chat", "Encounter", "ChallengeMode", "PvPMatch" }) do
			if types[key] then
				local ok, active = pcall(restricted.IsAddOnRestrictionActive, types[key])
				if ok and active then return true end
			end
		end
	end
	return false
end

-- Queue one message on EldoUI's shared addon message queue (E:SendComm),
-- which keeps to the game's rate per prefix and waits while addon messages
-- are restricted. done(status) hears "ok" once it left or "fail" when the
-- game refused it (the player is offline). Returns false when it could not
-- be queued at all.
local function SendRaw(message, channel, target, done)
	if not (E.SendComm and RegisterPrefix()) then return false end
	return E:SendComm(COMM, message, channel, target, { raw = true, done = done }) and true or false
end

local function ShortName(name)
	if Ambiguate then return Ambiguate(name, "none") end
	return (name:gsub("%-.*$", ""))
end

local function NewId()
	return ("%x"):format(math.floor((GetTime() * 1000) % 0xFFFFF))
end

local Pump
local function Schedule(delay)
	if sending then return end
	sending = true
	C_Timer.After(delay, function()
		sending = false
		Pump()
	end)
end

-- Work through the transfer queue one chunk at a time: the next chunk is
-- queued once the one before it has left.
Pump = function()
	local transfer = transfers[1]
	if not transfer or transfer.inFlight then return end
	local chunk = transfer.chunks[transfer.next]
	if not transfer.waitNoted and E:AddonCommsRestricted() then
		transfer.waitNoted = true
		E:Print(L["Addon messages are restricted right now. Sending continues when the restriction ends."])
	end
	local function ChunkDone(status)
		transfer.inFlight = nil
		if transfers[1] ~= transfer then return end
		if status == "ok" then
			transfer.next = transfer.next + 1
			if transfer.next > #transfer.chunks then
				table.remove(transfers, 1)
				E:Print(L["Sent %s to %s."]:format(CategoryTitle(transfer.kind), ShortName(transfer.target)))
			elseif transfer.next % 10 == 0 then
				E:Debug(("Sending to %s: %d/%d"):format(transfer.target, transfer.next, #transfer.chunks))
			end
		else
			table.remove(transfers, 1)
			E:Print(L["Couldn't send to %s (the player is offline or can't be reached)."]:format(ShortName(transfer.target)))
		end
		if transfers[1] then Schedule(SEND_INTERVAL) end
	end
	transfer.inFlight = true
	if not SendRaw(("D\t%s\t%d\t%s"):format(transfer.id, transfer.next, chunk), "WHISPER", transfer.target, ChunkDone) then
		-- The shared queue is full: try this chunk again in a moment, but
		-- not for ever.
		transfer.inFlight = nil
		transfer.retries = (transfer.retries or 0) + 1
		if transfer.retries > 30 then
			ChunkDone("fail")
		else
			Schedule(1.2)
		end
	end
end

local function StartTransfer(offer, target)
	local chunks = {}
	for i = 1, #offer.text, CHUNK do chunks[#chunks + 1] = offer.text:sub(i, i + CHUNK - 1) end
	for _, queued in ipairs(transfers) do
		if queued.id == offer.id and queued.target == target then return end
	end
	transfers[#transfers + 1] = { id = offer.id, kind = offer.kind, target = target, next = 1, chunks = chunks }
	E:Print(L["%s accepted. Sending %s (%d parts)..."]:format(ShortName(target), CategoryTitle(offer.kind), #chunks))
	Schedule(0.05)
end

-- Offer a share string. target: "PARTY", "RAID", "GUILD" or a player name.
function E:SendShare(key, target)
	key = key or "all"
	target = strtrim(tostring(target or ""))
	if target == "" then
		self:Print(L["Send to whom? Party, raid, guild or a player name."])
		return false
	end
	local channel, whisper = target:upper(), nil
	if channel == "GROUP" then channel = IsInRaid() and "RAID" or "PARTY" end
	if channel ~= "PARTY" and channel ~= "RAID" and channel ~= "GUILD" then
		channel, whisper = "WHISPER", target
	end
	if channel == "PARTY" and not IsInGroup() then self:Print(L["You are not in a group."]); return false end
	if channel == "RAID" and not IsInRaid() then self:Print(L["You are not in a raid."]); return false end
	if channel == "GUILD" and not IsInGuild() then self:Print(L["You are not in a guild."]); return false end
	local text = self:ExportString(key)
	if not text then
		self:Print(L["Nothing to export for %s."]:format(CategoryTitle(key)))
		return false
	end
	local chunks = math.ceil(#text / CHUNK)
	local id = NewId()
	outgoing[id] = { id = id, text = text, kind = key, channel = channel, target = whisper, started = GetTime() }
	local message = ("O\t%s\t%s\t%d\t%d"):format(id, key, #text, chunks)
	local queued = SendRaw(message, channel, whisper, function(status)
		if status ~= "ok" and outgoing[id] then
			outgoing[id] = nil
			E:Print(L["Couldn't send the offer."])
		end
	end)
	if not queued then
		outgoing[id] = nil
		self:Print(L["Couldn't send the offer."])
		return false
	end
	-- A restricted offer waits on the shared queue until the restriction lifts.
	if self:AddonCommsRestricted() then
		self:Print(L["Addon messages are restricted right now. The offer goes out when the restriction ends."])
	end
	self:Print(L["Offered %s to %s. It is sent when they accept."]:format(CategoryTitle(key), whisper and ShortName(whisper) or channel:lower()))
	-- Offers expire.
	C_Timer.After(OFFER_TIMEOUT + 30, function() outgoing[id] = nil end)
	return true
end

-- A group the game put together (a battleground raid, an instance group)
-- is full of strangers: there being in the group is no trust.
local function StrangerGroup()
	local instance = _G.LE_PARTY_CATEGORY_INSTANCE
	if instance and IsInGroup(instance) then return true end
	local _, kind = IsInInstance()
	return kind == "pvp" or kind == "arena"
end

-- Only people the player knows may offer settings: the guild, friends,
-- and a group the player made (not a battleground's).
function E:IsTrustedSender(sender, channel)
	if type(sender) ~= "string" or sender == "" then return false end
	local short = ShortName(sender)
	if E:IsMe(short) then return false end
	if channel == "GUILD" then return true end
	local strangers = StrangerGroup()
	if not strangers and (channel == "PARTY" or channel == "RAID") then return true end
	if not strangers and (UnitInParty(short) or UnitInRaid(short)) then return true end
	if IsInGuild() and C_GuildInfo and C_GuildInfo.MemberExistsByName then
		local ok, member = pcall(C_GuildInfo.MemberExistsByName, sender)
		if ok and member then return true end
		ok, member = pcall(C_GuildInfo.MemberExistsByName, short)
		if ok and member then return true end
	end
	if C_FriendList and C_FriendList.GetFriendInfo then
		local ok, info = pcall(C_FriendList.GetFriendInfo, short)
		if ok and info then return true end
	end
	return false
end

local function AcceptOffer(data)
	local entry = data and incoming[data.sender]
	if not entry or entry.id ~= data.id then return end
	entry.accepted = true
	entry.last = GetTime()
	-- An accepted offer doesn't count against the cooldown: the sender's
	-- next part ("positions" after "general") shows at once.
	offerTimes[data.sender] = nil
	SendRaw(("A\t%s"):format(entry.id), "WHISPER", data.sender)
end

-- Declined (the button or Escape) tells the sender; an offer that ran out
-- is dropped quietly.
local function DeclineOffer(data)
	local entry = data and incoming[data.sender]
	if entry and entry.id == data.id then
		incoming[data.sender] = nil
		if not data.expired then SendRaw(("N\t%s"):format(data.id), "WHISPER", data.sender) end
	end
end

local function OnOffer(sender, id, kind, bytes, total)
	bytes, total = tonumber(bytes), tonumber(total)
	if not (id and kind and bytes and total) then return end
	-- Only plain category keys; never show escape codes someone sent.
	if not kind:match("^[%w:_]+$") or #kind > 64 or not id:match("^%x+$") then return end
	if bytes > MAX_STRING or total > MAX_CHUNKS or total < 1 then return end
	local current = incoming[sender]
	if current and current.accepted then return end -- one transfer per sender
	-- One offer per sender every OFFER_COOLDOWN seconds, and never in place
	-- of a question the player has open (a reset, an import, another
	-- offer): the confirm window is shared, and showing an offer would
	-- cancel that question.
	local now = GetTime()
	for name, at in pairs(offerTimes) do
		if now - at >= OFFER_COOLDOWN then offerTimes[name] = nil end
	end
	if offerTimes[sender] then return end
	offerTimes[sender] = now
	local asking = E:GetConfirm()
	if asking and asking:IsShown() then
		E:Print(L["%s wants to send you EldoUI settings. Answer your open question first; they can offer again in %d seconds."]
			:format(ShortName(sender), OFFER_COOLDOWN))
		-- The sender hears "declined" instead of waiting out the offer.
		SendRaw(("N\t%s"):format(id), "WHISPER", sender)
		return
	end
	incoming[sender] = { id = id, kind = kind, bytes = bytes, total = total, parts = {}, got = 0, last = now }
	local message = L["%s wants to send you EldoUI settings:\n%s (%.1f KB)\n\nAccept to receive them. You see what they change before anything is applied."]
		:format(ShortName(sender), E:Highlight(CategoryTitle(kind)), bytes / 1024)
	local data = { sender = sender, id = id }
	E:ShowConfirm({ key = "ELDOUI_RECEIVE", title = L["Profiles"], text = message, accept = ACCEPT, cancel = DECLINE,
		data = data, onAccept = AcceptOffer, onCancel = DeclineOffer })
	if C_Timer and C_Timer.After then
		C_Timer.After(OFFER_TIMEOUT, function()
			local open = E:GetConfirm()
			if open and open:IsShown() and open.data == data then
				data.expired = true
				E:CancelConfirm("ELDOUI_RECEIVE")
			end
		end)
	end
end

local function OnChunk(sender, id, index, text)
	local entry = incoming[sender]
	index = tonumber(index)
	if not (entry and entry.accepted and entry.id == id and index and text) then return end
	if index < 1 or index > entry.total or entry.parts[index] then return end
	entry.parts[index] = text
	entry.got = entry.got + 1
	entry.last = GetTime()
	if entry.got < entry.total then return end
	incoming[sender] = nil
	local whole = table.concat(entry.parts)
	if #whole > MAX_STRING then return end
	E:Print(L["Received %s from %s."]:format(CategoryTitle(entry.kind), ShortName(sender)))
	E:ImportString(whole)
end

local function OnAddonMessage(_, _, prefix, message, channel, sender)
	if prefix ~= COMM or type(message) ~= "string" then return end
	local kind, rest = message:match("^(%u)\t(.*)$")
	if not kind then return end
	if kind == "O" then
		if not E:IsTrustedSender(sender, channel) then return end
		OnOffer(sender, rest:match("^([^\t]+)\t([^\t]+)\t(%d+)\t(%d+)$"))
	elseif kind == "D" then
		local id, index, text = rest:match("^([^\t]+)\t(%d+)\t(.*)$")
		OnChunk(sender, id, index, text)
	elseif kind == "A" then
		local offer = outgoing[rest]
		if offer then StartTransfer(offer, sender) end
	elseif kind == "N" then
		if outgoing[rest] then E:Print(L["%s declined the settings."]:format(ShortName(sender))) end
	end
end

-- Drop transfers that stopped arriving.
local function SweepIncoming()
	local now = GetTime()
	for sender, entry in pairs(incoming) do
		if entry.accepted and now - entry.last > RECEIVE_TIMEOUT then
			incoming[sender] = nil
			E:Print(L["The settings from %s stopped arriving and were dropped."]:format(ShortName(sender)))
		end
	end
end

E:RegisterEvent("PLAYER_LOGIN", function()
	RegisterPrefix()
	E:RegisterEvent("CHAT_MSG_ADDON", OnAddonMessage, commOwner)
	if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(30, SweepIncoming) end
end, commOwner, "engines")

---------------------------------------------------------------------------
-- Profiles page (replaces the simple one in Core/Config.lua: registered
-- first, at ADDON_LOADED, so the later registration finds it)
---------------------------------------------------------------------------
local profileProxy = { send = { what = "all", to = "group" } }

-- Accept / Cancel on the shared dialog shell (E:ShowConfirm).
local function Confirm(text, func, danger)
	E:ShowConfirm({ title = L["Profiles"], text = text, accept = ACCEPT, onAccept = func, danger = danger })
end

local function ProfileValues(exceptCurrent)
	return function()
		local values = {}
		for _, name in ipairs(E:GetProfileList()) do
			if not (exceptCurrent and name == E.profileName) then values[name] = name end
		end
		return E:RawValues(values)
	end
end

local function SendTargets()
	local values = { group = L["My group"], guild = L["My guild"], player = L["A player (by name)"] }
	return values
end

local function SendWhatValues()
	local values = {}
	for _, entry in ipairs(E:GetShareCategories()) do values[entry.key] = entry.title end
	return values
end

local function DoSend()
	local send = profileProxy.send
	local to = send.to
	local target
	if to == "group" then target = IsInRaid() and "RAID" or "PARTY"
	elseif to == "guild" then target = "GUILD"
	else target = strtrim(send.player or "") end
	E:SendShare(send.what, target)
end

-- The lines a profile question adds: which other characters use
-- the profile, and what happens to them. why: "reset", "copy" or "delete".
function E:ProfileConfirmText(text, name, why)
	local others = {}
	for _, key in ipairs(self:ProfileUsers(name)) do
		if key ~= self.charKey then others[#others + 1] = key end
	end
	local lines = { text }
	if why == "delete" then
		if #others > 0 then
			if EldoUIDB.profiles.Default and name ~= "Default" then
				lines[#lines + 1] = L["Also used by %s. They go back to the profile Default."]:format(table.concat(others, ", "))
			else
				lines[#lines + 1] = L["Also used by %s. They get a new, empty profile Default, and the setup opens at their next login."]:format(table.concat(others, ", "))
			end
		end
	elseif #others > 0 then
		lines[#lines + 1] = L["Also used by %s. The change is theirs too."]:format(table.concat(others, ", "))
	end
	if why == "reset" and name == self.profileName then lines[#lines + 1] = L["The setup opens again after the reset."] end
	lines[#lines + 1] = L["A copy is kept first: Undo in the alert or the Saved data page puts it back."]
	return table.concat(lines, "\n\n")
end

local function PrintUsers()
	local users = E:ProfileUsers(E.profileName)
	for index, key in ipairs(users) do users[index] = key == E.charKey and (key .. L[" (this character)"]) or key end
	E:Print(L["Characters using %s: %s"]:format(E.profileName, table.concat(users, ", ")))
end

local profileOptions = {
	{ type = "header", label = L["This character"] },
	{ type = "description", tone = "body", hidden = function() return not (E.ProfileRulesOn and E:ProfileRulesOn()) end,
		label = L["Profile rules are on: the profile follows your content or talent group. A pick here holds until one of them changes."] },
	{ type = "select", key = "current", label = L["Profile for this character"], values = ProfileValues(),
		desc = L["The profile this character uses. Every character can use any profile."] },
	{ type = "input", key = "new", label = L["New profile"], noUndo = true,
		desc = L["Type a name and press Enter: a new profile with default settings, used by this character from now on."] },
	{ type = "toggle", key = "perCharacter", label = L["Module on/off per character"],
		desc = L["Keep which modules are on for this character only, instead of in the profile. Handy when several characters share a profile but use different modules."] },
	{ type = "execute", label = L["Attach this character to..."],
		desc = L["Opens the alt setup: put this character on a profile you already set up, as it is, with its own chat tabs, game settings, click-casting and class spells. A backup is kept first."],
		func = function()
			if E.Installer and E.Installer.ShowAlt then E.Installer.ShowAlt() end
		end },
	{ type = "header", label = L["This profile"] },
	{ type = "input", key = "rename", label = L["Rename"], noUndo = true,
		desc = L["Type a new name for this profile and press Enter. Characters, profile rules and class defaults follow the new name."] },
	{ type = "select", key = "copyParts", label = L["Copy parts from"], noUndo = true, values = ProfileValues(true),
		desc = L["Pick another profile, then check the modules (and frame positions) to copy into this one."] },
	{ type = "select", key = "copyFrom", label = L["Copy everything from"], noUndo = true, values = ProfileValues(true),
		desc = L["Replace this whole profile with a copy of another one (asks first)."] },
	{ type = "execute", label = L["Reset this profile"], desc = L["Every setting of this profile back to its default (asks first)."],
		func = function()
			local name = E.profileName
			Confirm(E:ProfileConfirmText(L["Reset the profile %s to defaults?"]:format(E:Highlight(name)), name, "reset"), function()
				E:RunOutOfCombat(function()
					if E.profileName ~= name then return end
					E:ChangeProfileWithUndo(name, "reset", function() return E:ResetProfile() end)
					E:RefreshConfig()
				end)
			end, true)
		end },
	{ type = "execute", label = L["Who uses it?"], desc = L["Lists the characters that use this profile in chat."], func = PrintUsers, testSafe = true },
	{ type = "header", label = L["Other profiles"] },
	{ type = "select", key = "delete", label = L["Delete a profile"], noUndo = true, values = ProfileValues(true),
		desc = L["Delete a profile you don't use any more (asks first). Characters that used it go back to Default. A copy stays on the Saved data page."] },
	{ type = "header", label = L["Send to a player"] },
	{ type = "description", label = L["Send settings to a group member, guild member or friend. They see what changes before anything is applied."] },
	{ type = "select", key = "send.what", label = L["What"], values = SendWhatValues,
		desc = L["The whole profile or one part of it."] },
	{ type = "select", key = "send.to", label = L["To"], values = SendTargets,
		desc = L["Everyone in your group or guild gets the offer; each one decides."] },
	{ type = "input", key = "send.player", label = L["Player name"], hidden = function() return profileProxy.send.to ~= "player" end,
		desc = L["Name of the player (Name or Name-Realm). Group members, guild members and friends can receive."] },
	{ type = "execute", label = L["Send"], desc = L["Offer the settings now."], func = DoSend },
}

local function ProfileTarget()
	profileProxy.current = E.profileName
	profileProxy.perCharacter = E:ModuleStatesPerCharacter()
	profileProxy.new, profileProxy.rename, profileProxy.copyFrom, profileProxy.copyParts, profileProxy.delete = nil, nil, nil, nil, nil
	return profileProxy
end

local function ProfileRefresh()
	local p = profileProxy
	if p.new and p.new ~= "" then
		local name, err = E:CheckProfileName(p.new)
		p.new = nil
		if not name then
			E:Print(err)
		elseif EldoUIDB.profiles[name] then
			E:Print(L["A profile with that name already exists."])
		else
			E:RunOutOfCombat(function() E:SetProfile(name) end)
		end
	elseif p.rename and p.rename ~= "" then
		local new = p.rename
		p.rename = nil
		local old = E.profileName
		local ok, err = E:RenameProfile(old, new)
		if ok then E:Print(L["Renamed %s to %s."]:format(old, E.profileName)) else E:Print(err) end
	elseif p.copyParts then
		local from = p.copyParts
		p.copyParts = nil
		E:ShowCopyParts(from)
	elseif p.copyFrom then
		local from = p.copyFrom
		p.copyFrom = nil
		local name = E.profileName
		Confirm(E:ProfileConfirmText(L["Replace every setting of %s with a copy of %s?"]:format(E:Highlight(name), E:Highlight(from)), name, "copy"), function()
			E:RunOutOfCombat(function()
				if E.profileName ~= name then return end
				E:ChangeProfileWithUndo(name, "copy", function()
					local ok = E:CopyProfile(from)
					if ok then E:Print(L["Copied %s into %s."]:format(from, name)) end
					return ok
				end)
				E:RefreshConfig()
			end)
		end)
	elseif p.delete then
		local name = p.delete
		p.delete = nil
		Confirm(E:ProfileConfirmText(L["Delete the profile %s?"]:format(E:Highlight(name)), name, "delete"), function()
			E:ChangeProfileWithUndo(name, "delete", function()
				local ok = E:DeleteProfile(name)
				if ok then E:Print(L["Deleted profile %s."]:format(name)) end
				return ok
			end)
			E:RefreshConfig()
		end, true)
	elseif p.current and p.current ~= E.profileName then
		local name = p.current
		E:RunOutOfCombat(function() E:SetProfile(name) end)
	elseif p.perCharacter ~= nil and p.perCharacter ~= E:ModuleStatesPerCharacter() then
		local on = p.perCharacter
		E:RunOutOfCombat(function() E:SetModuleStatesPerCharacter(on) end)
	end
	E:RefreshConfig()
end

E:RegisterEvent("ADDON_LOADED", function(_, _, addon)
	if addon ~= E.name then return end
	E:UnregisterEvent("ADDON_LOADED", profileProxy)
	if E.RegisterConfigPage then
		E:RegisterConfigPage("profiles", L["Profiles"], profileOptions, ProfileTarget, ProfileRefresh, 99)
	end
end, profileProxy)

---------------------------------------------------------------------------
-- Commands and the Import / Export page
---------------------------------------------------------------------------
local function ExportKeyFrom(arg)
	arg = strtrim(arg or "")
	if arg == "" then return "all" end
	if arg == "all" or arg == "general" or arg == "positions" or arg == "global" then return arg end
	for name in E:IterateModules() do
		if name:lower() == arg:lower() then return "module:" .. name end
	end
	for _, entry in ipairs(E:SharedGlobals()) do
		if entry.key:lower() == arg:lower() then return "global:" .. entry.key end
	end
	return nil
end

-- The refusal names every word the export takes, the shared lists too.
local function UnknownCategory()
	local lists = {}
	for _, entry in ipairs(E:SharedGlobals()) do lists[#lists + 1] = entry.key:lower() end
	E:Print(L["Unknown category. Try all, general, positions, global, a module name from /eui modules, or one of these lists: %s."]:format(table.concat(lists, ", ")))
end

E:AddCommand("export", "[all | general | positions | global | <module> | <list>]  export settings as a share string", function(arg)
	local key = ExportKeyFrom(arg)
	if key then E:ShowExport(key) else UnknownCategory() end
end, "Profiles & sharing")

E:AddCommand("exportlua", "[all | general | positions | global | <module> | <list>]  export settings as a readable Lua table", function(arg)
	local key = ExportKeyFrom(arg)
	if key then E:ShowExport(key, "lua") else UnknownCategory() end
end, "Profiles & sharing")

E:AddCommand("import", "open the import window: EldoUI, EllesmereUI, ElvUI and Edit Mode strings", function() E:ShowImport() end, "Profiles & sharing")

E:AddCommand("send", "<party | raid | guild | player> [all | general | positions | global | <module> | <list>]  offer settings to a group, guild or player", function(arg)
	local target, what = (arg or ""):match("^(%S*)%s*(.-)$")
	if target == "" then
		E:Print(L["Usage: /eui send <party | raid | guild | player> [what]"])
		return
	end
	local key = ExportKeyFrom(what)
	if not key then
		UnknownCategory()
		return
	end
	E:SendShare(key, target)
end, "Profiles & sharing")

E:AddCommand("renameprofile", "<new name>  rename the profile this character uses", function(arg)
	local old = E.profileName
	local ok, err = E:RenameProfile(old, arg)
	if ok then E:Print(L["Renamed %s to %s."]:format(old, E.profileName)) else E:Print(err) end
end, "Profiles & sharing")

E:AddCommand("copyparts", "<profile>  copy chosen modules from another profile", function(arg)
	arg = strtrim(arg or "")
	if not EldoUIDB.profiles[arg] or arg == E.profileName then
		E:Print(L["Name another existing profile. /eui profile list shows them."])
		return
	end
	E:ShowCopyParts(arg)
end, "Profiles & sharing")

-- Config page: the one place to import any string (Core/Import.lua's window
-- reads every kind), then one export button per category and readable
-- exports.
E:RegisterEvent("PLAYER_LOGIN", function()
	local options = {
		{ type = "description", label = L["Share any part of your setup, or the whole profile, as a text string. One paste box takes EldoUI, EllesmereUI, ElvUI and Edit Mode strings."] },
		{ type = "header", label = L["Import"] },
		{ type = "execute", label = L["Import a string"], keywords = "ElvUI EllesmereUI Edit Mode layout profile paste",
			desc = L["Opens the paste box. It recognizes EldoUI, EllesmereUI, ElvUI and Edit Mode strings and shows what each imports before you click Import."],
			func = function() E:ShowImport() end },
	}
	for _, row in ipairs(E.ImportPageRows and E:ImportPageRows("import") or {}) do table.insert(options, row) end
	for _, row in ipairs({
		{ type = "header", label = L["Export"] },
		{ type = "execute", label = L["Export everything"], desc = L["The whole profile as one string."], func = function() E:ShowExport("all") end },
		{ type = "execute", label = L["Readable export"], desc = L["The whole profile as a readable Lua table, for bug reports and comparing setups."],
			func = function() E:ShowExport("all", "lua") end },
		{ type = "execute", label = L["Copy my Edit Mode layout"], desc = L["Blizzard's active Edit Mode layout as text, to share or keep."],
			hidden = function() return not E.ShowEditModeExport end, func = function() E:ShowEditModeExport() end },
		{ type = "header", label = L["Export one part"] },
	}) do table.insert(options, row) end
	for _, entry in ipairs(E:GetShareCategories()) do
		if entry.key ~= "all" and not entry.global and entry.key ~= "global" then
			table.insert(options, { type = "execute", label = entry.title, desc = L["Export this part as a share string."],
				func = function() E:ShowExport(entry.key) end })
		end
	end
	local globals = E:SharedGlobals()
	if #globals > 0 then
		table.insert(options, { type = "header", label = L["Account-wide lists"] })
		table.insert(options, { type = "description", label = L["Lists every character on your account shares (filters and the like). They don't change with the profile and are exported on their own."] })
		table.insert(options, { type = "execute", label = L["All lists"], desc = L["Every account-wide list in one string."], func = function() E:ShowExport("global") end })
		for _, entry in ipairs(globals) do
			table.insert(options, { type = "execute", label = entry.title, desc = entry.desc or L["Export this list as a share string."],
				func = function() E:ShowExport("global:" .. entry.key) end })
		end
	end
	for _, row in ipairs(E.ImportPageRows and E:ImportPageRows("layouts") or {}) do table.insert(options, row) end
	-- The only keyed rows are the import choices (Core/Import.lua).
	E:RegisterConfigPage("share", L["Import and export"], options, function()
		return E.ImportPageTarget and E:ImportPageTarget() or E.db
	end, function()
		if E.ImportPageRefresh then E:ImportPageRefresh() end
	end, 98)
end, E.GetShareCategories, "modules")
