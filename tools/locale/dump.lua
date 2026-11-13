-- Reads EldoUI locale files the way the game does and prints their tables
-- as JSON: { "<file>": { "<code>": { "<English key>": "<text>" | { "one": ..., "other": ... } } } }
--
--   lua5.1 tools/locale/dump.lua <file.lua> [<file.lua> ...]
--
-- A file may get EldoUI from its global (language packs) or from the addon
-- vararg (files in EldoUI's own TOC). GetLocale() answers "deDE" so the Loot
-- Guide's client-only tables register too.

local function JsonString(s)
	s = s:gsub('[%c"\\]', function(c)
		if c == '"' then return '\\"' end
		if c == "\\" then return "\\\\" end
		if c == "\n" then return "\\n" end
		if c == "\r" then return "\\r" end
		if c == "\t" then return "\\t" end
		return string.format("\\u%04x", c:byte())
	end)
	return '"' .. s .. '"'
end

local function Json(value)
	local kind = type(value)
	if kind == "string" then return JsonString(value) end
	if kind == "number" or kind == "boolean" then return tostring(value) end
	if kind ~= "table" then return "null" end
	local keys = {}
	for key in pairs(value) do keys[#keys + 1] = key end
	table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
	local parts = {}
	for _, key in ipairs(keys) do parts[#parts + 1] = JsonString(tostring(key)) .. ":" .. Json(value[key]) end
	return "{" .. table.concat(parts, ",") .. "}"
end

local out = {}
for _, path in ipairs(arg) do
	local registered = {}
	local E = {}
	function E:RegisterLocale(code, strings)
		if type(strings) == "function" then strings = strings() end
		registered[code] = registered[code] or {}
		for key, text in pairs(strings or {}) do registered[code][key] = text end
	end
	_G.EldoUI = E
	_G.GetLocale = function() return "deDE" end
	local chunk = assert(loadfile(path))
	chunk("EldoUI", E)
	out[path] = registered
end
io.write(Json(out), "\n")
