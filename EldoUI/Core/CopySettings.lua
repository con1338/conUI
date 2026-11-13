-- EldoUI "Copy settings from": one control for every page that edits
-- several frames of one kind (unit frames, group frame sections, name
-- plate types, action bars, scrolling text areas, info bar panels, aura
-- groups). The options window draws it as a `copyFrom` row: a menu of the
-- siblings, then a confirm that previews what will change before anything
-- is copied, plus "Apply to all".
--
--   E:CopySettingsOptions(spec)  -> { row }, put it at the top of the page
--     spec.path    "units.target" or a function: the settings table the page
--                  edits now (dotted path under the page's settings)
--     spec.values  { [path] = label } or a function, the page's own path
--                  included (it is left out of the menu)
--     spec.keep    keys (dotted paths allowed) that stay as they are on the
--                  frame copied into; default { "enabled" }. Positions live
--                  in the movers and are never touched.
--     spec.existingOnly  true: only keys the frame copied into already has
--                  are written, and none of its own keys are removed
--     spec.copy    optional function(root, from, to, keep) -> copied, for a
--                  module with its own copy rules
--     spec.after   optional function(root, from, to) after a copy (fix-ups)
--     spec.label, spec.desc, spec.hidden  as on any row
--
--   E:CopySettingsApply(root, from, to, keep[, existingOnly])  the copy
--   E:CopySettingsChanges(root, from, to, keep[, existingOnly])  sorted
--                                  dotted keys under `to` that a copy changes
--   E:RunCopySettings(row, root, from, to)       the row's copy and after
local _, E = ...
local L = E.L

local DEFAULT_KEEP = { "enabled" }

local function Get(root, path)
	local value = root
	for part in tostring(path):gmatch("[^%.]+") do
		if type(value) ~= "table" then return nil end
		value = value[tonumber(part) or part]
	end
	return value
end

local function Set(root, path, newValue)
	local parts = {}
	for part in tostring(path):gmatch("[^%.]+") do parts[#parts + 1] = tonumber(part) or part end
	if #parts == 0 then return end
	local ref = root
	for index = 1, #parts - 1 do
		if type(ref[parts[index]]) ~= "table" then
			if newValue == nil then return end
			ref[parts[index]] = {}
		end
		ref = ref[parts[index]]
	end
	ref[parts[#parts]] = newValue
end

local function Copy(value)
	if type(value) == "table" then return CopyTable(value) end
	return value
end

function E:CopySettingsOptions(spec)
	spec = spec or {}
	return { {
		type = "copyFrom",
		label = spec.label or "Copy settings from",
		desc = spec.desc or "Copy every setting of another frame of this kind onto this one. A preview lists what changes before anything is copied. The on/off switch and the position stay as they are.",
		path = spec.path,
		values = spec.values,
		keep = spec.keep,
		copy = spec.copy,
		existingOnly = spec.existingOnly,
		after = spec.after,
		hidden = spec.hidden,
	} }
end

-- Copy `from` into `to` in place (code holding the table keeps seeing it),
-- keeping the `keep` keys of `to`.
function E:CopySettingsApply(root, from, to, keep, existingOnly)
	if type(from) ~= "string" or type(to) ~= "string" or from == to then return false end
	local source = Get(root, from)
	if type(source) ~= "table" then return false end
	keep = keep or DEFAULT_KEEP
	local target = Get(root, to)
	if type(target) ~= "table" then
		if existingOnly then return false end
		target = {}
		Set(root, to, target)
	end
	local kept = {}
	for index, key in ipairs(keep) do kept[index] = Copy(Get(target, key)) end
	local fresh = CopyTable(source)
	if existingOnly then
		for key, value in pairs(fresh) do
			if target[key] ~= nil then target[key] = value end
		end
	else
		wipe(target)
		for key, value in pairs(fresh) do target[key] = value end
	end
	for index, key in ipairs(keep) do Set(target, key, kept[index]) end
	return true
end

-- Every leaf that differs between two values, as dotted keys.
local function Diff(a, b, prefix, out)
	if type(a) == "table" and type(b) == "table" then
		local seen = {}
		for key, value in pairs(a) do
			seen[key] = true
			Diff(value, b[key], prefix .. tostring(key) .. ".", out)
		end
		for key, value in pairs(b) do
			if not seen[key] then Diff(nil, value, prefix .. tostring(key) .. ".", out) end
		end
	elseif a ~= b then
		out[#out + 1] = prefix:sub(1, -2)
	end
end

local function Kept(key, keep)
	for _, kept in ipairs(keep) do
		if key == kept or key:sub(1, #kept + 1) == kept .. "." then return true end
	end
	return false
end

function E:CopySettingsChanges(root, from, to, keep, existingOnly)
	local source, target = Get(root, from), Get(root, to)
	if type(source) ~= "table" or from == to then return {} end
	if type(target) ~= "table" then
		if existingOnly then return {} end
		target = {}
	end
	keep = keep or DEFAULT_KEEP
	local all, out = {}, {}
	if existingOnly then
		for key, value in pairs(source) do
			if target[key] ~= nil then Diff(value, target[key], tostring(key) .. ".", all) end
		end
	else
		Diff(source, target, "", all)
	end
	for _, key in ipairs(all) do
		if key ~= "" and not Kept(key, keep) then out[#out + 1] = key end
	end
	table.sort(out)
	return out
end

-- The copy a row asks for: its own `copy` or the default, then `after`.
function E:RunCopySettings(row, root, from, to)
	if type(row) ~= "table" then return false end
	local keep = row.keep or DEFAULT_KEEP
	local copied
	if type(row.copy) == "function" then
		copied = row.copy(root, from, to, keep)
	else
		copied = self:CopySettingsApply(root, from, to, keep, row.existingOnly)
	end
	if copied and type(row.after) == "function" then row.after(root, from, to) end
	return copied and true or false
end

-- The keys a row's copy changes (see E:CopySettingsChanges).
function E:CopySettingsRowChanges(row, root, from, to)
	return self:CopySettingsChanges(root, from, to, row.keep or DEFAULT_KEEP, row.existingOnly)
end

-- What a copy changes, in words for the confirm: the labels of the page's
-- rows that edit the changed keys (first `limit`), and how many are left.
-- `labelOf(key)` maps a full dotted key to a row label or nil.
function E:CopySettingsPreview(changes, to, labelOf, limit)
	limit = limit or 8
	local names, seen, unnamed = {}, {}, 0
	for _, key in ipairs(changes) do
		local full, label = to .. "." .. key, nil
		-- The row of the key itself, else of the table it sits in.
		while full and not label do
			label = labelOf(full)
			if not label then
				local shorter = full:match("^(.+)%.[^%.]+$")
				if not shorter or #shorter <= #to then full = nil else full = shorter end
			end
		end
		if label then
			if not seen[label] then
				seen[label] = true
				names[#names + 1] = label
			end
		else
			unnamed = unnamed + 1
		end
	end
	local shown = {}
	for index = 1, math.min(limit, #names) do shown[index] = names[index] end
	local more = #names - #shown
	local text = table.concat(shown, ", ")
	if more > 0 and unnamed > 0 then
		text = L["%s, %d more settings and %d other values"]:format(text, more, unnamed)
	elseif more > 0 then
		text = L["%s and %d more settings"]:format(text, more)
	elseif unnamed > 0 and #shown > 0 then
		text = L["%s and %d other values"]:format(text, unnamed)
	elseif unnamed > 0 then
		text = L["%d values without a row on this page"]:format(unnamed)
	end
	return text, #names, unnamed
end
