-- EldoUI movers: every EldoUI frame sits on a "mover" that the player can
-- drag in move mode (/eui move). Positions are saved per profile.
--
--   E:CreateMover(frame, "EldoUI_InfoBar", "Info Bar", { "BOTTOM", "UIParent", "BOTTOM", 0, 0 })
--
-- The default point comes from the module; Core/Layout.lua can override it
-- with the active layout preset. Plugins can call CreateMover for their own frames.
--
-- Optional fifth argument:
--   E:CreateMover(frame, name, title, defaultPoint, {
--       onMoved = function(mover, point, rel, relPoint, x, y) end, -- after every placement
--       layoutAlias = "EldoUI_Details", -- preset point to use when the layout has none for `name`
--       enabledPath = { "bars", 3, "enabled" }, -- switch in the module's settings that
--                                                -- turns the frame on (a layout's `hidden`)
--       followShown = true, -- the mover (and its move-mode box) shows and hides with
--                           -- the frame, for frames a setting can switch off
--       group = "Unit frames", -- move-mode group (E.moverGroups); default from the module
--       combat = true, -- part of combat mode (the everyday fight screen); default from
--                      -- the core list in this file
--       sizeKeys = { width = "width", height = { key = "height", min = 4, max = 64 } },
--                  -- settings in the module's db (dots for nested keys) that set the
--                  -- frame's width/height, for "Match size" in move mode. An axis
--                  -- may also be function(mover) returning such a key or table, or
--                  -- nil while no setting sets that side (a growth direction or a
--                  -- mode decides it)
--       sample = { kind = "bar" }, -- the stand-in "Show test frames" draws while the
--                                  -- frame shows nothing (Core/MoverSamples.lua);
--                                  -- false for a window opened on demand
--       options = { page = "module:Auras", key = "enchants.enabled" },
--                  -- where the box's Options… goes (page, and the row by its
--                  -- option key or a tab by its label); default: the module's page
--       menu = function(root, mover) end, -- the frame's own entries in its box menu,
--                                         -- after Lock
--   })
-- Move mode only shows movers that are shown and whose module is on; a
-- module can also hide a mover itself (mover:Hide()) while its frame is off.
-- Other code can listen too: E:RegisterMoverCallback(name, fn), same arguments.
-- E:SaveMoverPosition(name, point, rel, relPoint, x, y) and
-- E:SaveMoverFromRect(name, left, bottom) save and apply a position from code;
-- E:ApplyMover(name) re-places one mover; E:GetMoverDefaultPoint(name) is the
-- point it uses when the player hasn't moved it, and
-- E:RegisterMoverPointHook(name, fn) lets a module pick that point itself;
-- E:RegisterMoverEdgeShift(anchor, fn) keeps the frames placed against a
-- frame that draws narrower than its layout spot where the layout put them;
-- E:RegisterMoverTopReach(anchor, fn) moves the frames placed on top of a
-- frame that draws above its own top edge up by as much.
--
-- Move mode: a session that "Undo changes" can roll back, a
-- group filter and a title search, alignment guides while dragging, a
-- per-mover lock (E:SetMoverLocked), boxes hidden for the session and
-- "Attach to" links (E:LinkMover(name, target, side)) saved with the position,
-- "Match size" (E:MatchMoverSize(name, target, axis)) for movers with sizeKeys,
-- "Show test frames" (E:SetMoveModeTest(state)) for every module's samples,
-- and "Find a frame" (E:LocateMover(name)), which shows, selects and flashes
-- one frame's box and offers to bring a box outside the screen back.
--
-- Positions are offsets from UIParent, or from the centered safe area
-- (Core/Scale.lua) when the player limits the UI to 16:9 on an
-- ultrawide screen. Saved positions always say "UIParent"; E:GetMoverAnchor()
-- turns that into the frame they are measured from.
local _, E = ...
local L = E.L

E.defaults.movers = {}
E.movers = {}

local callbacks = {} -- mover name -> list of functions
local ObserveAnchor

-- relPoint: the anchor point a position uses, if known (corner frames may
-- stay at the screen corners, see Core/Scale.lua).
local function MoverAnchor(relPoint)
	local anchor = E.GetMoverAnchor and E:GetMoverAnchor(relPoint) or UIParent
	if ObserveAnchor then ObserveAnchor(anchor) end
	return anchor
end

-- Calls the mover's own onMoved and every registered callback. Errors go to
-- the error handler, so one broken listener can't stop a layout apply.
local function FireMoved(mover, pos)
	local point, rel, relPoint, x, y = pos[1], pos[2], pos[3], pos[4], pos[5]
	if mover.onMoved then
		local ok, err = pcall(mover.onMoved, mover, point, rel, relPoint, x, y)
		if not ok then geterrorhandler()(err) end
	end
	for _, fn in ipairs(callbacks[mover.name] or {}) do
		local ok, err = pcall(fn, mover, point, rel, relPoint, x, y)
		if not ok then geterrorhandler()(err) end
	end
end

function E:RegisterMoverCallback(name, fn)
	assert(type(name) == "string" and type(fn) == "function", "EldoUI:RegisterMoverCallback(name, fn)")
	callbacks[name] = callbacks[name] or {}
	table.insert(callbacks[name], fn)
end

-- Point hooks: a module may place one of its own movers by a rule of its
-- own while the player hasn't dragged it, such as an action bar the layout
-- hides, which steps aside into a corner. fn(name) returns a point, or nil
-- for the usual one.
local pointHooks = {}
local authorityEpoch = {}
local authorityEqual = rawequal
local geometrySelect = select
local geometrySecret = E.Secret
local rootGeometry = false
local NATIVE_READS = { "GetParent", "GetNumPoints", "GetPoint", "GetRect", "GetSize", "GetWidth", "GetHeight", "GetEffectiveScale", "IsShown", "IsVisible", "GetLeft", "GetBottom", "GetRight", "GetTop" }
local nativeFrameReads, nativeTextureReads
local nativeFrameWrites, nativeTextureWrites
local MUTATION_METHODS = { "SetPoint", "ClearAllPoints", "SetAllPoints", "SetParent", "SetScale", "SetSize", "SetWidth", "SetHeight", "Show", "Hide", "SetShown" }
local mutationRecords = setmetatable({}, { __mode = "k" })
local ownedMutationMethods = setmetatable({}, { __mode = "k" })
local geometryEnvironment = _G
local geometryMetaRead, geometryRawRead, geometryType = getmetatable, rawget, type
local geometryEnvironmentMeta = geometryMetaRead(geometryEnvironment)
local geometryEnvironmentIndex = geometryType(geometryEnvironmentMeta) == "table" and geometryRawRead(geometryEnvironmentMeta, "__index") or nil
-- Resolve the loader-selected API once during trusted setup. Later source
-- checks never consult an environment resolver, including a missing raw slot.
local geometryHookSlot = geometryRawRead(geometryEnvironment, "hooksecurefunc")
local geometryHook = geometryHookSlot or hooksecurefunc
local NativeReadBinding, AdmitGeometry, HookOwnedGeometry, TagMoverGeometry, OwnedPositionWrite
local constructorMovers = setmetatable({}, { __mode = "k" })
local admittedGeometry = setmetatable({}, { __mode = "k" })
local ownedWritePermits = setmetatable({}, { __mode = "k" })
local function GeometrySame(value, saved) return not geometrySecret(value) and authorityEqual(value, saved) end
-- These prototypes come from the mover's own native constructors.
local function SeedNativeReads(object, texture)
	local saved = texture and nativeTextureReads or nativeFrameReads
	local methods = {}
	for _, name in ipairs(NATIVE_READS) do
		local fn = object[name]
		if geometrySecret(fn) or type(fn) ~= "function" then return false end
		methods[name] = fn
		if saved and not GeometrySame(saved[name], fn) then return false end
	end
	local writes, prior = {}, texture and nativeTextureWrites or nativeFrameWrites
	for _, name in ipairs(MUTATION_METHODS) do
		local fn = object[name]
		if geometrySecret(fn) or type(fn) ~= "function" or (prior and not GeometrySame(prior[name], fn)) then return false end
		writes[name] = fn
	end
	if texture then nativeTextureReads = saved or methods;nativeTextureWrites = prior or writes
	else nativeFrameReads = saved or methods;nativeFrameWrites = prior or writes end
	if not rootGeometry and AdmitGeometry then rootGeometry = AdmitGeometry(UIParent) end
	return true
end
-- Resolve table fields without calling an object or class resolver.
local function NativeField(object, name, valueOnly)
	if geometrySecret(object) or (type(object) ~= "table" and type(object) ~= "userdata") then return end
	local tables, value = not valueOnly and {} or nil, type(object) == "table" and rawget(object, name) or nil
	local current = object
	for depth = 1, 16 do
		local meta = getmetatable(current)
		if geometrySecret(meta) then return end
		local index = type(meta) == "table" and rawget(meta, "__index") or nil
		if geometrySecret(index) then return end
		if tables then tables[#tables + 1] = { current, meta, index, value } end
		if value ~= nil then return value, tables end
		if type(index) ~= "table" then return end
		current, value = index, rawget(index, name)
	end
end
local function HookSourceCurrent()
	local meta = geometryMetaRead(geometryEnvironment)
	if not GeometrySame(meta, geometryEnvironmentMeta)
		or (geometryType(meta) == "table" and not GeometrySame(geometryRawRead(meta, "__index"), geometryEnvironmentIndex)) then return false end
	local hook = geometryRawRead(geometryEnvironment, "hooksecurefunc")
	return GeometrySame(hook, geometryHookSlot) and not geometrySecret(geometryHook) and geometryType(geometryHook) == "function"
end
-- Admission is owned by constructors or an explicitly supplied owner capability.
-- Read bindings below never install hooks or expose these mutable records.
local function MutationCurrent(object, record, full, hookChecked)
	local owned = ownedMutationMethods[object]
	if not record or record.installing or not record.ready or (owned and owned.ordinary) or (not hookChecked and not HookSourceCurrent()) then return false end
	if not full then return true end
	for _, name in ipairs(MUTATION_METHODS) do
		local fn
		if record.direct[name] then fn = rawget(object, name) else fn = NativeField(object, name, true) end
		if not GeometrySame(fn, record.methods[name]) then return false end
	end
	return true
end
HookOwnedGeometry = function(object, name, callback)
	if not HookSourceCurrent() then return false end
	if geometrySecret(object) or geometrySecret(name) or type(name) ~= "string" or geometrySecret(callback) or type(callback) ~= "function" then return false end
	local fn = NativeField(object, name, true)
	if geometrySecret(fn) or type(fn) ~= "function" then return false end
	local owned = ownedMutationMethods[object]
	local expected = owned and owned[name]
	local native = nativeFrameWrites and nativeFrameWrites[name]
	local texture = nativeTextureWrites and nativeTextureWrites[name]
	if type(native) ~= "function" and type(texture) ~= "function" then return false end
	local qualified = not (owned and owned.ordinary) and (GeometrySame(fn, expected or native) or (texture and GeometrySame(fn, texture)))
	local record = mutationRecords[object]
	if not qualified then
		-- Ordinary constructor resize-follow may wrap a callable custom setter.
		-- It grants no native mutation source, even if the old method returns.
		owned = owned or {};ownedMutationMethods[object] = owned
		owned.ordinary, owned[name] = true, nil
		if record then record.epoch = {} end
	end
	local ok = pcall(geometryHook, object, name, callback)
	if not ok then return false end
	if not qualified then return true end
	local hooked = NativeField(object, name, true)
	if geometrySecret(hooked) or type(hooked) ~= "function" then return false end
	owned = owned or {};ownedMutationMethods[object] = owned;owned[name] = hooked
	if record and record.methods[name] then
		record.methods[name] = hooked
		record.direct[name] = type(object) == "table" and rawget(object, name) ~= nil
	end
	return true
end

-- A permit covers one exact native write, never the rest of a delivery or
-- any callbacks it triggers. A nested identical write consumes it first and
-- leaves the outer write observable, so reentry refuses conservatively.
local function ObserveMutation(object, record, method, ...)
	local permit = ownedWritePermits[object]
	local matches = permit and not permit.used and permit.method == method and permit.count == geometrySelect("#", ...)
	if matches then
		for index = 1, permit.count do
			local value = geometrySelect(index, ...)
			if geometrySecret(value) or not GeometrySame(value, permit[index]) then matches = false;break end
		end
	end
	if matches then permit.used = true else record.epoch = {} end
end
OwnedPositionWrite = function(object, method, ...)
	if geometrySecret(object) or geometrySecret(method) or (method ~= "ClearAllPoints" and method ~= "SetPoint") then error("Unsupported mover write", 2) end
	local permit = { method = method, count = geometrySelect("#", ...), used = false }
	for index = 1, permit.count do
		local value = geometrySelect(index, ...)
		if geometrySecret(value) then error("Mover write argument unavailable", 2) end
		permit[index] = value
	end
	local record, owner = mutationRecords[object], constructorMovers[object]
	local qualified = owner and not geometrySecret(E.movers) and type(E.movers) == "table"
		and GeometrySame(rawget(E.movers, owner.name), object) and GeometrySame(rawget(object, "frame"), owner.frame)
		and MutationCurrent(object, record, true)
	local fn = qualified and NativeField(object, method, true) or nil
	qualified = qualified and GeometrySame(fn, record.methods[method])
	local previous = ownedWritePermits[object]
	if qualified then
		-- A write already running keeps its own permit; a nested write gets none.
		if not previous then ownedWritePermits[object] = permit end
	else
		-- A mover EldoUI cannot verify is still placed through its own setter,
		-- just without a write permit.
		ownedWritePermits[object] = nil
		if record then record.epoch = {} end
		fn = object[method]
		if geometrySecret(fn) or type(fn) ~= "function" then error("Mover write method unavailable", 2) end
	end
	local function Pack(...) return { n = geometrySelect("#", ...), ... } end
	local result = Pack(pcall(fn, object, ...))
	if qualified and not previous then ownedWritePermits[object] = nil end
	if not result[1] then
		if geometrySecret(result[2]) then error("Mover write failure unavailable", 2) end
		error(result[2], 0)
	end
	return unpack(result, 2, result.n)
end

AdmitGeometry = function(object, generic)
	if geometrySecret(object) or not nativeFrameWrites or not HookSourceCurrent() then return end
	local ownedSource = ownedMutationMethods[object]
	if ownedSource and ownedSource.ordinary then return end
	if not NativeReadBinding(object, generic) then return end
	local record = mutationRecords[object]
	if record and record.installing then record.reentered = true;return end
	if not record then
		-- Validate every source before installing any callback. Unknown setters
		-- are refused without invocation, including a late failing method.
		local methods, owned = {}, ownedMutationMethods[object]
		for _, name in ipairs(MUTATION_METHODS) do
			local fn = NativeField(object, name, true)
			local expected = owned and owned[name]
			if not GeometrySame(fn, expected or nativeFrameWrites[name])
				and not (nativeTextureWrites and GeometrySame(fn, nativeTextureWrites[name])) then return end
			methods[name] = fn
		end
		record = { epoch = {}, methods = methods, installed = {}, direct = {} };mutationRecords[object] = record
	end
	record.installing, record.reentered = true, false
	for _, name in ipairs(MUTATION_METHODS) do
		if not record.installed[name] then
			local fn = NativeField(object, name, true)
			if not GeometrySame(fn, record.methods[name]) then record.installing = nil;return end
			local ok = pcall(geometryHook, object, name, function(actual, ...)
				if not geometrySecret(actual) and authorityEqual(actual, object) then ObserveMutation(object, record, name, ...)
				else record.epoch = {} end
			end)
			if not ok then record.installing = nil;return end
			local hooked = NativeField(object, name, true)
			if geometrySecret(hooked) or type(hooked) ~= "function" then record.installing = nil;return end
			record.methods[name], record.installed[name] = hooked, true
			record.direct[name] = type(object) == "table" and rawget(object, name) ~= nil
			local owned = ownedMutationMethods[object] or {};ownedMutationMethods[object] = owned;owned[name] = hooked
		end
	end
	record.installing, record.ready = nil, not record.reentered
	if not MutationCurrent(object, record, true) then return end
	local read = NativeReadBinding(object, generic)
	if not read or not read.source() then return end
	admittedGeometry[object] = read
	return read
end
NativeReadBinding = function(object, generic)
	if not HookSourceCurrent() then return end
	if not nativeFrameReads or geometrySecret(object) then return end
	local getters, paths, native = {}, {}, true
	for _, name in ipairs(NATIVE_READS) do
		local fn, path = NativeField(object, name)
		if geometrySecret(fn) or type(fn) ~= "function" or not path then return end
		local intrinsic = GeometrySame(fn, nativeFrameReads[name]) or (nativeTextureReads and GeometrySame(fn, nativeTextureReads[name]))
		if not intrinsic and not generic then return end
		native = native and intrinsic == true
		getters[name], paths[name] = fn, path
	end
	local record = { object = object, getters = getters, native = native }
	local observation = mutationRecords[object]
	-- Source reseals invoke no object/class resolvers or geometry callbacks.
	-- Shared path metadata can be checked once within this pure block; every
	-- getter's own raw field is still checked before the seal succeeds.
	local metadata, seen = {}, {}
	for _, name in ipairs(NATIVE_READS) do
		for _, part in ipairs(paths[name]) do
			if not seen[part[1]] then seen[part[1]] = true;metadata[#metadata + 1] = part end
		end
	end
	local function MetadataCurrent()
		for _, part in ipairs(metadata) do
			if not GeometrySame(getmetatable(part[1]), part[2])
				or (type(part[2]) == "table" and not GeometrySame(rawget(part[2], "__index"), part[3])) then return false end
		end
		return true
	end
	local function Method(name, metadataChecked)
		local path = paths[name]
		if not path then return false end
		for i, part in ipairs(path) do
			if not metadataChecked and (not GeometrySame(getmetatable(part[1]), part[2])
				or (type(part[2]) == "table" and not GeometrySame(rawget(part[2], "__index"), part[3]))) then return false end
			local value = type(part[1]) == "table" and rawget(part[1], name) or nil
			if not GeometrySame(value, part[4]) and not (i == 1 and part[4] == nil and GeometrySame(value, getters[name])) then return false end
		end
		return true
	end
	local function GetterSource(selected)
		if selected then return getters[selected] ~= nil and Method(selected) end
		if not MetadataCurrent() then return false end
		for _, name in ipairs(NATIVE_READS) do if not Method(name, true) then return false end end
		return true
	end
	function record.source(selected)
		if not HookSourceCurrent() or not authorityEqual(mutationRecords[object], observation)
			or (observation and not MutationCurrent(object, observation, not selected, true)) then return false end
		return GetterSource(selected)
	end
	function record.capture(full)
		if geometrySecret(full) then return function() return false end end
		full = not not full
		local expected = observation and observation.epoch
		local meta = getmetatable(object)
		local index = type(meta) == "table" and rawget(meta, "__index") or nil
		return function()
			return HookSourceCurrent() and authorityEqual(mutationRecords[object], observation)
				and (not observation or (GeometrySame(observation.epoch, expected) and MutationCurrent(object, observation, full, true)))
				and GeometrySame(getmetatable(object), meta) and (type(meta) ~= "table" or GeometrySame(rawget(meta, "__index"), index))
				-- No arbitrary callback occurs between the mutation preseal and
				-- these raw getter-field checks. Reuse only this call's preseal.
				and (not full or GetterSource())
		end
	end
	return record
end
local function ObserveReadGeometry(object) return AdmitGeometry(object) end

TagMoverGeometry = function(name, mover, frame)
	if geometrySecret(name) or type(name) ~= "string" or geometrySecret(mover) or geometrySecret(frame)
		or geometrySecret(E.movers) or type(E.movers) ~= "table" or not GeometrySame(rawget(E.movers, name), mover)
		or type(mover) ~= "table" or not GeometrySame(rawget(mover, "frame"), frame) then return false end
	local frameGeometry
	for _, entry in pairs(callbacks) do
		local origin = rawget(entry, "geometry")
		if origin and authorityEqual(origin.frame.object, frame) then frameGeometry = origin.frame;break end
	end
	frameGeometry = frameGeometry or ObserveReadGeometry(frame)
	-- Constructor origin and delivery authority are admitted together: a
	-- frame that fails its read never admits its mover alone.
	if not frameGeometry then return false end
	local moverGeometry = ObserveReadGeometry(mover)
	if not moverGeometry then return false end
	callbacks[name] = callbacks[name] or {}
	callbacks[name].geometry = { frame = frameGeometry, mover = moverGeometry }
	constructorMovers[mover] = { name = name, frame = frame }
	return true
end

ObserveAnchor = function(anchor)
	if not rootGeometry or geometrySecret(anchor) then return false end
	if authorityEqual(anchor, rootGeometry.object) then return rootGeometry.source() end
	rootGeometry.anchors = rootGeometry.anchors or {}
	for _, record in ipairs(rootGeometry.anchors) do if authorityEqual(record.object, anchor) then return record.source() end end
	local record = ObserveReadGeometry(anchor)
	if not record then return false end
	record.rootTransform = true
	rootGeometry.anchors[#rootGeometry.anchors + 1] = record
	return true
end
local function RootGeometryCurrent()
	if not rootGeometry or not rootGeometry.source() then return false end
	if rootGeometry.anchors then
		for _, record in ipairs(rootGeometry.anchors) do if not record.source() then return false end end
	end
	return true
end

function E:RegisterMoverPointHook(name, fn)
	assert(type(name) == "string" and type(fn) == "function", "EldoUI:RegisterMoverPointHook(name, fn)")
	pointHooks[name] = fn;authorityEpoch = {}
end

-- Edge shifts: a frame that draws narrower than the layout lays it out
-- (bar 3 shows nine of its twelve buttons) lets the frames placed against
-- its side edges keep their layout spot. fn(relativePoint) returns how far
-- a point on that edge moves across, or nil.
local edgeShifts = {}
function E:RegisterMoverEdgeShift(anchorName, fn)
	assert(type(anchorName) == "string" and type(fn) == "function", "EldoUI:RegisterMoverEdgeShift(anchorName, fn)")
	edgeShifts[anchorName] = fn;authorityEpoch = {}
end

-- Top reaches: a frame that draws above its own top edge (a unit frame's
-- name set above its bars) moves a frame placed on that edge (its bottom
-- on the anchor's top) up by as much, so the layout's gap is kept above
-- what the anchor draws there. fn() returns that height in UIParent units,
-- or nil.
local topReaches = {}
function E:RegisterMoverTopReach(anchorName, fn)
	assert(type(anchorName) == "string" and type(fn) == "function", "EldoUI:RegisterMoverTopReach(anchorName, fn)")
	topReaches[anchorName] = fn;authorityEpoch = {}
end

local function Ask(fn, ...)
	local ok, value = pcall(fn, ...)
	if not ok then
		geterrorhandler()(value)
		return nil
	end
	if type(value) ~= "number" or math.abs(value) < 0.5 then return nil end
	return value
end

local function OnTopOf(point)
	local own, relative = tostring(point[1] or ""), tostring(point[3] or point[1] or "")
	return own:find("BOTTOM") ~= nil and relative:find("TOP") ~= nil
end

local function ShiftPoint(point)
	if type(point) ~= "table" or type(point[2]) ~= "string" then return point end
	local edge, reach = edgeShifts[point[2]], topReaches[point[2]]
	local dx = edge and Ask(edge, point[3] or point[1])
	local dy = reach and OnTopOf(point) and Ask(reach) or nil
	if not (dx or dy) then return point end
	local shifted = CopyTable(point)
	if dx then shifted[4] = (tonumber(shifted[4]) or 0) + dx end
	if dy then shifted[5] = (tonumber(shifted[5]) or 0) + dy end
	return shifted
end

-- The point a mover uses when the player hasn't dragged it: a point hook's,
-- Gamepad Mode UI's while it is on (Core/GamepadMode.lua), the role's
-- (Core/Roles.lua), the layout preset's, then the preset's point for its
-- alias, then the module default. Role, layout and gamepad points are
-- scaled to the screen the same way (Core/Layout.lua).
function E:GetMoverDefaultPoint(name)
	local mover = self.movers[name]
	local hook = pointHooks[name]
	if hook then
		local ok, hooked = pcall(hook, name)
		if not ok then geterrorhandler()(hooked) elseif type(hooked) == "table" then return hooked end
	end
	local gamepad = self.GetGamepadMoverPoint and self:GetGamepadMoverPoint(name)
	if gamepad then return ShiftPoint(gamepad) end
	local point = self.GetRoleMoverPoint and self:GetRoleMoverPoint(name) or self:GetLayoutPoint(name)
	if not point and mover and mover.layoutAlias then point = self:GetLayoutPoint(mover.layoutAlias) end
	return ShiftPoint(point or (mover and mover.defaultPoint))
end

---------------------------------------------------------------------------
-- Mover families: one mover per group, panel or bar of a module, or per
-- window of another addon a module places. They all follow one rule:
--   * Name: a fixed base plus the slot, "EldoUI_AuraGroup" .. 3. The slot
--     is the group's place in the module's own saved list (1 to `slots`)
--     or one of a fixed list of `keys`. With `bareFirst`, slot 1 is the
--     bare base: the family started as a single frame, and that name stays.
--   * Declared once, when the module's file loads:
--       E:RegisterMoverFamily("EldoUI_AuraGroup", { module = "AuraGroups", slots = 6 })
--     and every name is in the module's `movers` description
--     (E:MoverFamilyNames gives the list).
--   * Saved like every other mover: under its full name in the profile's
--     positions, kept while the group, panel or window is off or not made
--     yet. Only the player changes a saved position: a reset puts it back
--     on the layout, and deleting a slot (E:ShiftMoverSlots) moves the
--     later slots up one place with their positions. Nothing else renames
--     or drops one.
--   * Owned by the module that declares it, also when the mover is made
--     outside that module's start (a window opened later).
---------------------------------------------------------------------------
E.moverFamilies = {}

local function FamilyName(family, slot)
	if family.keys then
		return tContains(family.keys, slot) and family.base .. slot or nil
	end
	slot = tonumber(slot)
	if not slot or slot < 1 or slot > family.slots or slot % 1 ~= 0 then return nil end
	if slot == 1 and family.bareFirst then return family.base end
	return family.base .. slot
end

-- info: module (its name), and slots (a count) or keys (a list of
-- strings); bareFirst (optional). Returns the family.
function E:RegisterMoverFamily(base, info)
	assert(type(base) == "string" and type(info) == "table" and type(info.module) == "string",
		"EldoUI:RegisterMoverFamily(base, { module = name, slots = count or keys = list })")
	assert(type(info.slots) == "number" or type(info.keys) == "table", "EldoUI:RegisterMoverFamily: slots or keys")
	local family = { base = base, module = info.module, slots = info.slots, keys = info.keys,
		bareFirst = info.bareFirst and true or nil }
	self.moverFamilies[base] = family
	return family
end

-- The mover name of a family's slot (nil for a slot it doesn't have).
function E:MoverFamilyName(base, slot)
	local family = self.moverFamilies[base]
	return family and FamilyName(family, slot) or nil
end

-- Every name of a family, in slot order.
function E:MoverFamilyNames(base)
	local family, names = self.moverFamilies[base], {}
	if not family then return names end
	for index = 1, family.keys and #family.keys or family.slots do
		names[#names + 1] = FamilyName(family, family.keys and family.keys[index] or index)
	end
	return names
end

-- The family a mover name belongs to, and its slot; nil when none.
function E:MoverFamilyOf(name)
	if type(name) ~= "string" then return nil end
	for base, family in pairs(self.moverFamilies) do
		if name == base and family.bareFirst then return family, 1 end
		if name:sub(1, #base) == base then
			local rest = name:sub(#base + 1)
			local slot = family.keys and rest or tonumber(rest:match("^%d+$") or "")
			if slot and FamilyName(family, slot) == name then return family, slot end
		end
	end
end

-- The module that declares a mover: by its family, else by the `movers`
-- list of a module's description.
function E:MoverOwner(name)
	local family = self:MoverFamilyOf(name)
	if family then return family.module end
	for moduleName, module in self:IterateModules() do
		local declared = module.descriptor and module.descriptor.movers
		if declared and tContains(declared, name) then return moduleName end
	end
end

-- The player deleted slot `from` of a family: every later slot's saved
-- position moves up one place, and the last slot has none left.
function E:ShiftMoverSlots(base, from)
	local family = self.moverFamilies[base]
	local saved = self.db and self.db.movers
	if not (family and family.slots and saved) then return end
	from = math.max(1, tonumber(from) or 1)
	local gamepad = type(self.db.gamepadUI) == "table" and self.db.gamepadUI.movers
	for _, store in ipairs({ saved, type(gamepad) == "table" and gamepad or nil }) do
		for slot = from, family.slots - 1 do
			store[FamilyName(family, slot)] = store[FamilyName(family, slot + 1)]
		end
		store[FamilyName(family, family.slots)] = nil
	end
	for slot = from, family.slots do
		local name = FamilyName(family, slot)
		if self.movers[name] then self:ApplyMover(name) end
	end
end

local moveMode = false

function E:IsMoveMode()
	return moveMode
end

E.defaults.general.gridSize = 32
E.defaults.general.snap = true
E.defaults.general.gridColor = "black"   -- "black", "white" or "accent"
E.defaults.general.gridAlpha = 0.5
E.defaults.general.gridThickness = 1     -- in screen pixels
E.defaults.general.moverGuides = true    -- alignment lines while dragging
E.defaults.moverLocks = {}               -- mover name = true: can't be dragged

local SNAP_DISTANCE = 10
local LINK_GAP = 4 -- default gap of a new "Attach to" link
local selected -- the mover the nudge panel works on
local UpdateOverlay -- defined with move mode below
local UpdatePanel -- defined with the nudge panel below
local RepaintBoxes -- defined with the test frames below
-- "Hide boxes" (until clicked again) and "peek" (while held): the boxes,
-- grid and panels go away and the real UI shows; move mode stays on.
local overlayHidden, peeking = false, false
local ApplyOverlayLook -- defined with the nudge panel below

-- Undo last move (Ctrl+Z in move mode): what each change of this move
-- session replaced, newest last. { store, name, pos } for one frame (pos is
-- a copy of the stored value, false, or NO_POSITION for none) or
-- { store, all = copy of the whole store } for Reset all.
local undoMoves = {}
local UNDO_LIMIT = 40
local NO_POSITION = {}

local function RememberMove(name)
	if not moveMode or type(name) ~= "string" then return end
	local store = E:MoverStore()
	local last = undoMoves[#undoMoves]
	-- One change can pass through two writers in the same frame (detach,
	-- then place): it is one step.
	local now = GetTime()
	if last and last.name == name and last.store == store and last.at == now then return end
	local before = store[name]
	if type(before) == "table" then before = CopyTable(before) elseif before == nil then before = NO_POSITION end
	undoMoves[#undoMoves + 1] = { store = store, name = name, pos = before, at = now }
	if #undoMoves > UNDO_LIMIT then table.remove(undoMoves, 1) end
end

---------------------------------------------------------------------------
-- Groups: every mover belongs to one group, from its module.
---------------------------------------------------------------------------
E.moverGroups = { "Unit frames", "Action bars", "Group frames", "Combat", "Chat and info", "Maps", "Other" }
-- Shown translated: L["Unit frames"], L["Action bars"], L["Group frames"],
-- L["Combat"], L["Chat and info"], L["Maps"], L["Other"]
local MODULE_GROUP = {
	UnitFrames = "Unit frames", ClassPower = "Unit frames", Auras = "Unit frames", AuraGroups = "Unit frames",
	ActionBars = "Action bars", MicroMenu = "Action bars", ConsumableBar = "Action bars",
	GroupFrames = "Group frames", RaidTools = "Group frames",
	DBM = "Combat",
	Chat = "Chat and info", Messages = "Chat and info", ChatBubbles = "Chat and info", InfoBar = "Chat and info",
	Counters = "Chat and info", StatusBars = "Chat and info", Tooltip = "Chat and info", Notifications = "Chat and info",
	Minimap = "Maps", Maps = "Maps", Waypoints = "Maps",
}
local CATEGORY_GROUP = { Combat = "Combat", Group = "Group frames", ["Chat & Social"] = "Chat and info" }
-- Movers made outside their module's setup, whose name names no module.
local MOVER_GROUP = {
	EldoUI_PlayerPowerBar1 = "Unit frames", EldoUI_PlayerPowerBar2 = "Unit frames",
	EldoUI_PlayerPowerBar3 = "Unit frames", EldoUI_PlayerPowerBar4 = "Unit frames",
	EldoUI_ProcOverlay = "Combat", EldoUI_BossEmote = "Combat", EldoUI_StartCountdown = "Combat",
	EldoUI_BigWigsBars = "Combat", EldoUI_BigWigsEmphasize = "Combat", EldoUI_BigWigsMessages = "Combat",
	EldoUI_BigWigsCountdown = "Combat", EldoUI_Details1 = "Combat", EldoUI_Details2 = "Combat",
	EldoUI_BagBar = "Action bars",
}

-- Combat mode: the frames of the everyday screen a player fights with,
-- so move mode opens on the main UI instead of every window and toast.
-- A mover can also say so itself (CreateMover opts.combat = true or false).
local COMBAT_MOVERS = {}
for _, name in ipairs({
	-- unit frames, cast bar, resources, auras
	"Player", "Target", "ToT", "Focus", "FocusTarget", "Pet", "PetTarget", "Boss", "PartyPets", "PartyTargets",
	"PlayerCastbar", "PlayerPower", "PlayerFramePower", "Totems", "Buffs", "Debuffs", "TempEnchants",
	-- group frames
	"Party", "Raid", "Tanks", "GroupPets", "RaidTools",
	-- bars
	"PetBar", "StanceBar", "PossessBar", "TotemBar", "ExtraAbility", "VehicleExit", "VehicleSeat",
	"ConsumableBar", "ProcOverlay", "MicroMenu", "BagBar", "XPBar",
	-- combat HUD
	"CooldownPulse", "SwingMainHand", "SwingOffHand", "SwingRanged", "LossOfControl", "Details",
	"Details1", "Details2", "TrackingBars", "EnemySpotter", "CombatTimer", "ThreatMeter",
	-- encounters and alerts
	"EncounterTimeline", "EncounterBar", "BossEmote", "StartCountdown", "BGTimers",
	"AlertLane", "RaidWarning", "Errors",
	-- the rest of the main screen
	"Minimap", "Chat", "ChatRight", "InfoBar", "InfoBar2", "Quests", "QuestItem", "Reminders", "SplitTimer",
	-- boss mods and what the game shows in a fight
	"BossWarnings", "BossInfo", "MirrorTimers", "TopWidgets", "ReadyCheck", "GamepadBar",
}) do COMBAT_MOVERS["EldoUI_" .. name] = true end
local COMBAT_PREFIXES = { "EldoUI_ActionBar", "EldoUI_Cooldown", "EldoUI_SCT", "EldoUI_AuraGroup",
	"EldoUI_PlayerPowerBar", "EldoUI_BigWigs", "EldoUI_TrackingBar", "EldoUI_DataPanel" }

-- Is this mover part of combat mode?
function E:IsCombatMover(name)
	local mover = type(name) == "table" and name or self.movers[name]
	if not mover then return false end
	if mover.combat ~= nil then return mover.combat and true or false end
	if COMBAT_MOVERS[mover.name] then return true end
	for _, prefix in ipairs(COMBAT_PREFIXES) do
		if mover.name:sub(1, #prefix) == prefix then return true end
	end
	return false
end

-- The move-mode group of a mover: its own `group` (CreateMover opts),
-- else from its module, else Other.
function E:GetMoverGroup(name)
	local mover = type(name) == "table" and name or self.movers[name]
	if not mover then return nil end
	if mover.group then return mover.group end
	if MOVER_GROUP[mover.name] then return MOVER_GROUP[mover.name] end
	local module = mover.module and self.modules[mover.module]
	if not module then
		-- A mover made outside its module's setup: the longest module name
		-- inside the mover name ("EldoUI_Minimap" -> Minimap).
		local best
		for moduleName, candidate in pairs(self.modules) do
			if mover.name:find(moduleName, 1, true) and (not best or #moduleName > #best.name) then best = candidate end
		end
		module = best
	end
	if not module then return "Other" end
	if MODULE_GROUP[module.name] then return MODULE_GROUP[module.name] end
	local category = self.GetModuleCategory and self:GetModuleCategory(module)
	return CATEGORY_GROUP[category] or "Other"
end

-- What move mode shows right now (this session only): combat mode or all
-- frames, one group, a title search and the movers hidden for the session.
-- Move mode opens in combat mode; a group picked in the panel shows all of
-- that group.
local view = { mode = "combat", group = nil, search = "", hidden = {} }

-- The view mode alone (combat, all or hidden). Test frames follow it, so a peek
-- shows the fight screen with its stand-ins and nothing else.
-- A piece the player hid (Core/Hideable.lua) leaves both views; the
-- "hidden" view shows only those, dimmed, to bring them back.
local function PieceHidden(mover)
	return E.IsHidden ~= nil and E:IsHidden(mover.name)
end

local function InMode(mover)
	if view.mode == "hidden" then return PieceHidden(mover) end
	if PieceHidden(mover) then return false end
	return view.mode ~= "combat" or E:IsCombatMover(mover)
end

local function InView(mover)
	if view.hidden[mover.name] then return false end
	if not InMode(mover) then return false end
	if view.group and E:GetMoverGroup(mover) ~= view.group then return false end
	if view.search ~= "" then
		local title = E:FoldText(tostring(L[mover.title] or mover.title or ""))
		if not title:find(view.search, 1, true) then return false end
	end
	return true
end

---------------------------------------------------------------------------
-- Measuring and placing
---------------------------------------------------------------------------
-- Save a mover by its left/bottom edge. The anchor follows the screen third
-- the frame sits in, so positions keep their side on other resolutions.
local function Measure(mover, anchor, left, bottom)
	-- Measure from the anchor (UIParent, or the safe area inside it).
	left, bottom = left - (anchor:GetLeft() or 0), bottom - (anchor:GetBottom() or 0)
	local screenW, screenH = anchor:GetSize()
	local width, height = mover:GetSize()
	local cx, cy = left + width / 2, bottom + height / 2
	local h, x
	if cx < screenW / 3 then
		h, x = "LEFT", left
	elseif cx > screenW * 2 / 3 then
		h, x = "RIGHT", left + width - screenW
	else
		h, x = "", cx - screenW / 2
	end
	local v, y
	if cy < screenH / 3 then
		v, y = "BOTTOM", bottom
	elseif cy > screenH * 2 / 3 then
		v, y = "TOP", bottom + height - screenH
	else
		v, y = "", cy - screenH / 2
	end
	local point = (v .. h ~= "") and (v .. h) or "CENTER"
	return point, math.floor(x + 0.5), math.floor(y + 0.5)
end

-- The position a rect would be saved as: anchor frame, point, x, y.
local function MeasureRect(mover, left, bottom)
	local anchor = MoverAnchor()
	local point, x, y = Measure(mover, anchor, left, bottom)
	-- A corner frame may stay at the true screen corner (safe area option).
	local pointAnchor = MoverAnchor(point)
	if pointAnchor ~= anchor then
		local point2, x2, y2 = Measure(mover, pointAnchor, left, bottom)
		-- Keep the screen measurement only if it still lands on a corner.
		if MoverAnchor(point2) == pointAnchor then
			anchor, point, x, y = pointAnchor, point2, x2, y2
		end
	end
	return anchor, point, x, y
end

---------------------------------------------------------------------------
-- Links: "Attach to <mover>". A link is part of the mover's saved
-- position, so it goes wherever positions go (profile copy, export):
--   E.db.movers[name] = { point, "UIParent", relPoint, x, y,
--                         link = { to = "EldoUI_Other", side = "below", x = 0, y = -4 } }
-- The first five values are where the frame last sat on screen; they are
-- used when the target is missing. Links are placed out of combat only
-- and never form a loop.
---------------------------------------------------------------------------
local LINK_SIDES = {
	below = { "TOP", "BOTTOM", 0, -1 },
	above = { "BOTTOM", "TOP", 0, 1 },
	left = { "RIGHT", "LEFT", -1, 0 },
	right = { "LEFT", "RIGHT", 1, 0 },
}
E.moverLinkSides = { "below", "above", "left", "right" }
local LINK_LABEL = { below = "Below", above = "Above", left = "Left of", right = "Right of" }
-- Shown translated: L["Below"], L["Above"], L["Left of"], L["Right of"]

-- Saved drags. E.db.movers holds the player's own drags. While Gamepad
-- Mode UI is on, drags go to a table of its own (E.db.gamepadUI.movers),
-- so the normal layout and its drags stay as they were: a frame Gamepad
-- Mode UI places ignores the normal drags meanwhile, every other frame
-- keeps them. Other files read E.db.movers as "the player's own drags",
-- which is right in both modes.
function E:MoverStore(readOnly)
	local gamepad = self.GamepadModeActive and self:GamepadModeActive() and self.db.gamepadUI
	if type(gamepad) == "table" then
		if type(gamepad.movers) ~= "table" then
			if readOnly == true then return nil end
			gamepad.movers = {}
		end
		return gamepad.movers
	end
	return self.db.movers
end

-- The saved position of mover `name`, or nil: it uses its default point.
function E:SavedMoverPosition(name, readOnly)
	local store = self:MoverStore(readOnly)
	local pos = store and store[name]
	-- A mode-specific reset keeps the normal drag saved without inheriting it.
	if pos == false then return nil end
	if pos ~= nil or store == self.db.movers then return pos end
	if self.GamepadOverlayOwns and self:GamepadOverlayOwns(name) then return nil end
	return self.db.movers[name]
end

-- Layout-owned sizing follows the same precedence as the mover's point.
function E:LayoutOwnsMover(name)
	if not self.movers[name] or pointHooks[name] or self:SavedMoverPosition(name, true) ~= nil then return false end
	if self.GetGamepadMoverPoint and self:GetGamepadMoverPoint(name) then return false end
	if self.GetRoleMoverPoint and self:GetRoleMoverPoint(name) then return false end
	return true
end

-- A projected default chain cannot adopt a saved point or an edge callback.
function E:LayoutClusterOwnsMover(name)
	return self:LayoutOwnsMover(name) and not edgeShifts[name .. "Mover"]
end

local function PositionOf(name)
	return E:SavedMoverPosition(name) or E:GetMoverDefaultPoint(name)
end

-- A read can retain hook ownership without invoking a placement callback.
-- The token stays private and every registration invalidates earlier reads.

function E.MoverAuthoritySource()
	if type(geometrySecret) ~= "function" or type(authorityEpoch) ~= "table" or type(callbacks) ~= "table" or type(ObserveReadGeometry) ~= "function" then return nil end
	if type(ObserveAnchor) ~= "function" or type(SeedNativeReads) ~= "function"
		or type(TagMoverGeometry) ~= "function" or type(OwnedPositionWrite) ~= "function"
		or type(HookOwnedGeometry) ~= "function" then return nil end
	local expected = authorityEpoch
	local function CaptureRead()
		return function(full) return rootGeometry and (not full or RootGeometryCurrent()) end
	end
	local function Domain(name, mover, frame, full)
		if geometrySecret(name) or geometrySecret(mover) or geometrySecret(frame) then return false end
		local entry = rawget(callbacks, name)
		local origin = entry and rawget(entry, "geometry")
		return origin and origin.mover and origin.frame and GeometrySame(mover, origin.mover.object) and GeometrySame(frame, origin.frame.object)
			and (not full or (origin.mover.source() and origin.frame.source())) or false
	end
	local function Existing(object)
		if geometrySecret(object) then return end
		if rootGeometry and authorityEqual(rootGeometry.object, object) then return rootGeometry.capture, rootGeometry.source end
		if rootGeometry and rootGeometry.anchors then
			for _, record in ipairs(rootGeometry.anchors) do
				if authorityEqual(record.object, object) then return record.capture, record.source end
			end
		end
		for _, entry in pairs(callbacks) do
			local origin = rawget(entry, "geometry")
			if origin then
				if authorityEqual(origin.mover.object, object) then return origin.mover.capture, origin.mover.source end
				if authorityEqual(origin.frame.object, object) then return origin.frame.capture, origin.frame.source end
			end
		end
		local admitted = admittedGeometry[object]
		if admitted and admitted.source() then return admitted.capture, admitted.source end
	end
	return function() return authorityEqual(authorityEpoch, expected) end, CaptureRead,
		function() return type(nativeFrameReads) == "table" and rootGeometry ~= false end, Domain, Existing, NativeReadBinding, AdmitGeometry
end

-- Hand the mover position source to the layout reader. Without its read
-- record the screen's own geometry is not read.
do
	local source, bind = E.MoverAuthoritySource, E.RegisterWideMoverReadSource
	if type(authorityEpoch) == "table" and type(ObserveReadGeometry) == "function" and not rootGeometry then rootGeometry = ObserveReadGeometry(UIParent);if rootGeometry then rootGeometry.rootTransform = true end end
	if type(bind) == "function" then bind(E, source, E.LayoutClusterOwnsMover) end
end

-- The mover a mover's position hangs from: its link target, or the mover a
-- layout chains it to ("EldoUI_ActionBar1Mover").
local function ParentOf(name)
	local pos = PositionOf(name)
	if type(pos) ~= "table" then return nil end
	if type(pos.link) == "table" and LINK_SIDES[pos.link.side] and E.movers[pos.link.to] then return pos.link.to end
	local rel = pos[2]
	if type(rel) == "string" and rel ~= "UIParent" then
		local base = rel:match("^(.+)Mover$")
		if base and E.movers[base] then return base end
	end
	return nil
end

-- Would attaching `child` to `target` make a loop (target already hangs,
-- directly or through others, from child)?
function E:WouldMoverLinkLoop(child, target)
	local seen = {}
	local current = target
	while current do
		if current == child or seen[current] then return true end
		seen[current] = true
		current = ParentOf(current)
	end
	return false
end

-- The target mover and side of a saved link, or nil when the link can't be
-- used (target gone, unknown side, a loop from an imported profile).
local function UsableLink(mover, pos)
	local link = type(pos) == "table" and pos.link
	if type(link) ~= "table" then return nil end
	local target, side = E.movers[link.to], LINK_SIDES[link.side]
	if not target or not side or target == mover then return nil end
	if E:WouldMoverLinkLoop(mover.name, link.to) then return nil end
	return target, side, link
end

function E:GetMoverLink(name)
	local mover = self.movers[name]
	local pos = self:SavedMoverPosition(name)
	if not mover or not UsableLink(mover, pos) then return nil end
	return pos.link.to, pos.link.side
end

local ApplyPosition, ApplyChildren -- defined below

-- Write where a mover sits on screen into its position's first five values
-- (the fallback of a link), keeping the link.
local function RememberScreen(mover, pos)
	if not mover:GetLeft() then return end
	local _, point, x, y = MeasureRect(mover, mover:GetLeft(), mover:GetBottom())
	pos[1], pos[2], pos[3], pos[4], pos[5] = point, "UIParent", point, x, y
end

local function SetMoverPosition(mover, left, bottom)
	local anchor, point, x, y = MeasureRect(mover, left, bottom)
	local pos = { point, "UIParent", point, x, y }
	RememberMove(mover.name)
	E:MoverStore()[mover.name] = pos
	mover:ClearAllPoints()
	mover:SetPoint(point, anchor, point, x, y)
	FireMoved(mover, pos)
	ApplyChildren(mover)
end

-- Two movers that trade places (the group pets and the main tanks: the one
-- in use keeps a shared spot, the other goes beside it) can still hang on
-- each other from before: the other one is pinned where it is on screen
-- first, so the new chain never closes a loop. Its own placement follows.
local function Unhook(mover, pos)
	local name = type(pos.link) == "table" and pos.link.to or pos[2]
	local other = name ~= "UIParent" and _G[name]
	if not (other and other ~= mover and other.GetNumPoints) then return end
	for index = 1, other:GetNumPoints() do
		local _, to = other:GetPoint(index)
		if to == mover then
			local left, bottom = other:GetLeft(), other:GetBottom()
			other:ClearAllPoints()
			if left then other:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, bottom) end
			return
		end
	end
end

-- A saved point SetPoint can take: an anchor point (the relative point
-- may be left out), finite offsets (or none), and a relative that is the
-- screen, a frame, or a name not loaded (handled below). A damaged or
-- hand-made import, or an old save, gets the mover's default point instead
-- of an error that would stop the placement of every mover after it.
local ANCHOR_POINTS = { TOPLEFT = true, TOP = true, TOPRIGHT = true, LEFT = true, CENTER = true,
	RIGHT = true, BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true }
local function CheckPoint(pos)
	if type(pos) ~= "table" or not ANCHOR_POINTS[pos[1]] then return false end
	if pos[3] ~= nil and not ANCHOR_POINTS[pos[3]] then return false end
	for index = 4, 5 do
		local n = pos[index]
		if n ~= nil and (type(n) ~= "number" or n ~= n or n == math.huge or n == -math.huge) then return false end
	end
	if type(pos[2]) ~= "string" then return false end
	local rel = rawget(_G, pos[2])
	return rel == nil or (type(rel) == "table" and type(rel.GetPoint) == "function")
end
-- A point that can't be read (a secret layout value) is left as it was.
local function PlaceablePoint(pos)
	local ok, placeable = pcall(CheckPoint, pos)
	return not ok or placeable
end

function ApplyPosition(mover)
	local pos = PositionOf(mover.name)
	if not UsableLink(mover, pos) and not PlaceablePoint(pos) then
		local fallback = E:GetMoverDefaultPoint(mover.name) or mover.defaultPoint
		pos = PlaceablePoint(fallback) and fallback or { "CENTER", "UIParent", "CENTER", 0, 0 }
	end
	Unhook(mover, pos)
	OwnedPositionWrite(mover, "ClearAllPoints")
	local target, side, link = UsableLink(mover, pos)
	if target then
		OwnedPositionWrite(mover, "SetPoint", side[1], target, side[2], tonumber(link.x) or 0, tonumber(link.y) or 0)
	else
		-- A point chained to a mover that doesn't exist (its module is off or
		-- not loaded) would put the frame at the chain's offsets from the
		-- screen: the module's own default point is used instead.
		if pos[2] ~= "UIParent" and not _G[pos[2]] then
			local fallback = mover.defaultPoint
			if type(fallback) == "table" and (fallback[2] == "UIParent" or _G[fallback[2]]) then pos = fallback end
		end
		local rel = (pos[2] == "UIParent" or not _G[pos[2]]) and MoverAnchor(pos[3]) or _G[pos[2]]
		OwnedPositionWrite(mover, "SetPoint", pos[1], rel, pos[3], pos[4], pos[5])
	end
	FireMoved(mover, pos)
end

-- Movers attached to `mover` follow it on their own (they are anchored to
-- it); this refreshes their saved fallback and tells their listeners.
function ApplyChildren(mover, depth)
	depth = depth or 0
	if depth > 20 then return end
	for name, other in pairs(E.movers) do
		local pos = E:SavedMoverPosition(name)
		if other ~= mover and type(pos) == "table" and type(pos.link) == "table" and pos.link.to == mover.name and UsableLink(other, pos) then
			RememberScreen(other, pos)
			FireMoved(other, pos)
			ApplyChildren(other, depth + 1)
		end
	end
end

-- Attach mover `name` to mover `target` on `side` ("below", "above",
-- "left", "right"), LINK_GAP apart. Returns true, or false and why:
-- "unknown", "loop" or "combat".
function E:LinkMover(name, target, side)
	local mover, other = self.movers[name], self.movers[target]
	if not mover or not other or mover == other or not LINK_SIDES[side] then return false, "unknown" end
	if self:WouldMoverLinkLoop(name, target) then return false, "loop" end
	if InCombatLockdown() then return false, "combat" end
	local d = LINK_SIDES[side]
	local pos = { "CENTER", "UIParent", "CENTER", 0, 0, link = { to = target, side = side, x = d[3] * LINK_GAP, y = d[4] * LINK_GAP } }
	RememberMove(name)
	self:MoverStore()[name] = pos
	ApplyPosition(mover)
	RememberScreen(mover, pos)
	ApplyChildren(mover)
	if mover == selected then self:SelectMover(mover) end
	return true
end

-- Detach a mover; it stays where it is on screen.
function E:UnlinkMover(name)
	local mover = self.movers[name]
	local pos = self:SavedMoverPosition(name)
	if not mover or type(pos) ~= "table" or not pos.link then return false end
	if InCombatLockdown() then return false end
	RememberMove(name)
	-- A normal drag read in Gamepad Mode UI is copied first, so it stays.
	local store = self:MoverStore()
	if store[name] ~= pos then
		pos = CopyTable(pos)
		store[name] = pos
	end
	if mover:GetLeft() then
		SetMoverPosition(mover, mover:GetLeft(), mover:GetBottom())
	else
		pos.link = nil
		ApplyPosition(mover)
	end
	if mover == selected then self:SelectMover(mover) end
	return true
end

-- Does any usable link hang from mover `name`?
function E:HasMoverChildren(name)
	for otherName, other in pairs(self.movers) do
		local pos = self:SavedMoverPosition(otherName)
		if otherName ~= name and type(pos) == "table" and type(pos.link) == "table" and pos.link.to == name
			and UsableLink(other, pos) then
			return true
		end
	end
	return false
end

---------------------------------------------------------------------------
-- Size matching: "Match size" takes another frame's width or height
-- into this frame's own setting (a mover's sizeKeys, see the top of this
-- file), so the module draws it at that size and keeps it.
---------------------------------------------------------------------------
E.moverSizeAxes = { "width", "height" }

local function SizeSpec(mover, axis)
	local spec = mover and type(mover.sizeKeys) == "table" and mover.sizeKeys[axis]
	if type(spec) == "function" then
		local ok, result = pcall(spec, mover)
		spec = ok and result or nil
	end
	if type(spec) == "string" then spec = { key = spec } end
	if type(spec) ~= "table" or type(spec.key) ~= "string" then return nil end
	return spec
end

-- The table holding the setting and its last key, for "a.b.c" paths.
local function SettingSlot(db, path)
	local parts = { strsplit(".", path) }
	for i = 1, #parts - 1 do
		local key = tonumber(parts[i]) or parts[i]
		if type(db) ~= "table" or type(db[key]) ~= "table" then return nil end
		db = db[key]
	end
	return type(db) == "table" and db or nil, tonumber(parts[#parts]) or parts[#parts]
end

-- Can this mover's width or height be matched (axis nil: either)?
function E:CanMatchMoverSize(name, axis)
	local mover = self.movers[name]
	if not mover then return false end
	local module = mover.module and self.modules[mover.module]
	if not (module and module.db) then return false end
	for _, which in ipairs(axis and { axis } or self.moverSizeAxes) do
		local spec = SizeSpec(mover, which)
		if spec and SettingSlot(module.db, spec.key) then return true end
	end
	return false
end

-- Give mover `name` the width or height of mover `target`. Returns the
-- value written, or false and why: "unknown", "nokey" or "combat".
function E:MatchMoverSize(name, target, axis)
	local mover, other = self.movers[name], self.movers[target]
	if not mover or not other or mover == other or (axis ~= "width" and axis ~= "height") then return false, "unknown" end
	local spec = SizeSpec(mover, axis)
	local module = mover.module and self.modules[mover.module]
	local slot, key
	if spec and module and module.db then slot, key = SettingSlot(module.db, spec.key) end
	if not slot then return false, "nokey" end
	if InCombatLockdown() then return false, "combat" end
	local size = axis == "width" and other:GetWidth() or other:GetHeight()
	if not size or size <= 0 then return false, "unknown" end
	local value = math.floor(size + 0.5)
	if tonumber(spec.min) then value = math.max(spec.min, value) end
	if tonumber(spec.max) then value = math.min(spec.max, value) end
	slot[key] = value
	if module.active and module.OnProfileChanged then
		self:RunOutOfCombat(function() module:OnProfileChanged() end, "Movers:size:" .. module.name)
	end
	if mover == selected then self:SelectMover(mover) end
	return value
end

---------------------------------------------------------------------------
-- Snapping and alignment guides
---------------------------------------------------------------------------
-- Lines a dragged mover can line up with: the edges and centers of the
-- other movers on screen, the screen edges and the screen center.
-- { value, "edge"|"center" }. A drag measures them once when it starts (the
-- other boxes stay put while one moves) and reuses them until it ends.
local function AlignTargets(mover)
	local cached = mover.alignTargets
	if cached then return cached[1], cached[2] end
	local xs, ys = {}, {}
	for _, other in pairs(E.movers) do
		if other ~= mover and other:IsShown() and other.frame:IsShown() and other:GetLeft()
			and (not moveMode or E:IsMoverActive(other)) then
			local l, r, b, t = other:GetLeft(), other:GetRight(), other:GetBottom(), other:GetTop()
			xs[#xs + 1] = { l, "edge" }
			xs[#xs + 1] = { r, "edge" }
			xs[#xs + 1] = { (l + r) / 2, "centre" }
			ys[#ys + 1] = { b, "edge" }
			ys[#ys + 1] = { t, "edge" }
			ys[#ys + 1] = { (b + t) / 2, "centre" }
		end
	end
	local w, h = UIParent:GetSize()
	xs[#xs + 1] = { w / 2, "centre" }
	ys[#ys + 1] = { h / 2, "centre" }
	-- The screen edges: a box pushed against one sits flush, not a grid
	-- step away from it.
	xs[#xs + 1] = { 0, "edge" }
	xs[#xs + 1] = { w, "edge" }
	ys[#ys + 1] = { 0, "edge" }
	ys[#ys + 1] = { h, "edge" }
	return xs, ys
end

-- One axis: the mover's two edges and center (low, size) against the
-- targets, edges to edges and center to centers. Calls fn(target value,
-- distance, shift) for every pair closer than `limit`.
local function EachAlignment(low, size, targets, limit, fn)
	local own = { { low, "edge" }, { low + size, "edge" }, { low + size / 2, "centre" } }
	for _, o in ipairs(own) do
		for _, t in ipairs(targets) do
			if o[2] == t[2] then
				local d = math.abs(o[1] - t[1])
				if d < limit then fn(t[1], d, t[1] - o[1]) end
			end
		end
	end
end

-- Pull the mover onto the nearest edge or center of another mover (or the
-- screen's edges and center), else onto the grid.
local function Snap(mover, left, bottom)
	if not E.db.general.snap or IsAltKeyDown() then return left, bottom end
	local width, height = mover:GetSize()
	local xs, ys = AlignTargets(mover)
	local shiftX, shiftY
	local distX, distY = SNAP_DISTANCE, SNAP_DISTANCE
	EachAlignment(left, width, xs, SNAP_DISTANCE, function(_, d, shift)
		if d < distX then distX, shiftX = d, shift end
	end)
	EachAlignment(bottom, height, ys, SNAP_DISTANCE, function(_, d, shift)
		if d < distY then distY, shiftY = d, shift end
	end)
	local grid = E:GetMoveGridSize()
	local screenW, screenH = UIParent:GetSize()
	local bestX, bestY
	if shiftX then
		bestX = left + shiftX
	else
		local cx = screenW / 2
		bestX = cx + math.floor((left - cx) / grid + 0.5) * grid
	end
	if shiftY then
		bestY = bottom + shiftY
	else
		local cy = screenH / 2
		bestY = cy + math.floor((bottom - cy) / grid + 0.5) * grid
	end
	return bestX, bestY
end

local function SavePosition(mover)
	local left, bottom = Snap(mover, mover:GetLeft(), mover:GetBottom())
	SetMoverPosition(mover, left, bottom)
end

local DropGuides -- defined with the guides below

-- End a drag where the box is now and keep that place. Combat that starts
-- during a drag ends it the same way: the box stops following the cursor,
-- and in the lockdown the place is saved once combat is over.
function E:EndMoverDrag(mover)
	mover:SetScript("OnUpdate", nil)
	if DropGuides then DropGuides() end
	if not mover.dragging then
		mover.alignTargets = nil
		return false
	end
	mover.dragging = nil
	mover:StopMovingOrSizing()
	if mover:GetLeft() then
		if InCombatLockdown() then
			local left, bottom = Snap(mover, mover:GetLeft(), mover:GetBottom())
			self:SaveMoverFromRect(mover, left, bottom)
		else
			SavePosition(mover)
		end
	end
	mover.alignTargets = nil
	return true
end

-- Guides: one line across the screen for each edge or center the dragged
-- mover lines up with where it would land now (after snapping).
local guideFrame
local guides = {} -- { vertical = true|false, pos = number }

local function DrawGuides()
	if not guideFrame then
		if #guides == 0 then return end
		guideFrame = CreateFrame("Frame", "EldoUI_MoverGuides", UIParent)
		guideFrame:SetAllPoints(UIParent)
		guideFrame:SetFrameStrata("FULLSCREEN")
		guideFrame.lines = {}
	end
	local r, g, b = unpack(E.media.accentColor)
	for index, guide in ipairs(guides) do
		local line = guideFrame.lines[index]
		if not line then
			line = guideFrame:CreateTexture(nil, "OVERLAY")
			guideFrame.lines[index] = line
		end
		line:SetColorTexture(r, g, b, 0.9)
		line:ClearAllPoints()
		if guide.vertical then
			line:SetPoint("TOP", guideFrame, "TOPLEFT", guide.pos, 0)
			line:SetPoint("BOTTOM", guideFrame, "BOTTOMLEFT", guide.pos, 0)
			line:SetWidth(E.pixel * 2)
		else
			line:SetPoint("LEFT", guideFrame, "BOTTOMLEFT", 0, guide.pos)
			line:SetPoint("RIGHT", guideFrame, "BOTTOMRIGHT", 0, guide.pos)
			line:SetHeight(E.pixel * 2)
		end
		line:Show()
	end
	for index = #guides + 1, #guideFrame.lines do guideFrame.lines[index]:Hide() end
	guideFrame:SetShown(#guides > 0)
end

-- Work out (and draw) the guides for `mover` at its current place; nil
-- clears them. Returns the list.
function E:UpdateMoverGuides(mover)
	wipe(guides)
	if mover and moveMode and self.db.general.moverGuides and mover:GetLeft() then
		local left, bottom = Snap(mover, mover:GetLeft(), mover:GetBottom())
		-- Snapped positions line up exactly; free placement within a pixel.
		local limit = (self.db.general.snap and not IsAltKeyDown()) and 0.5 or 1.5
		local width, height = mover:GetSize()
		local xs, ys = AlignTargets(mover)
		local seen = {}
		local function Add(vertical)
			return function(value)
				local key = (vertical and "x" or "y") .. math.floor(value + 0.5)
				if not seen[key] then
					seen[key] = true
					guides[#guides + 1] = { vertical = vertical, pos = value }
				end
			end
		end
		EachAlignment(left, width, xs, limit, Add(true))
		EachAlignment(bottom, height, ys, limit, Add(false))
	end
	DrawGuides()
	return guides
end

function DropGuides() E:UpdateMoverGuides(nil) end

local function GuideUpdate(mover, elapsed)
	mover.guideWait = (mover.guideWait or 0) - elapsed
	if mover.guideWait > 0 then return end
	mover.guideWait = 0.03
	E:UpdateMoverGuides(mover)
end

---------------------------------------------------------------------------
-- Positions from code
---------------------------------------------------------------------------
-- Save a position for a mover from code (Edit Mode, integrations, plugins)
-- and move it there. Values as in E.db.movers: point, "UIParent", relPoint, x, y.
function E:SaveMoverPosition(name, point, rel, relPoint, x, y)
	if type(point) ~= "string" or type(x) ~= "number" or type(y) ~= "number" then return false end
	self:MoverStore()[name] = { point, rel or "UIParent", relPoint or point, math.floor(x + 0.5), math.floor(y + 0.5) }
	local mover = self.movers[name]
	if mover then
		self:RunOutOfCombat(function()
			ApplyPosition(mover)
			ApplyChildren(mover)
		end)
	end
	return true
end

-- Save a mover by its left/bottom edge in UIParent units, with the same
-- screen-third anchoring a drag uses (not snapped). `name` may be the mover.
function E:SaveMoverFromRect(name, left, bottom)
	local mover = type(name) == "table" and name or self.movers[name]
	if not mover or type(left) ~= "number" or type(bottom) ~= "number" then return false end
	return self:RunOutOfCombat(function() SetMoverPosition(mover, left, bottom) end)
end

-- The offsets that keep a mover where it sits on screen when it is
-- measured from `point` instead (the Positions page's Anchor row).
local POINT_SHARE = { LEFT = 0, RIGHT = 1, BOTTOM = 0, TOP = 1 }
function E:MoverOffsetsFor(name, point)
	local mover = self.movers[name]
	local left, bottom = mover and mover:GetLeft(), mover and mover:GetBottom()
	if not (left and bottom and type(point) == "string") then return nil end
	local anchor = MoverAnchor(point)
	left, bottom = left - (anchor:GetLeft() or 0), bottom - (anchor:GetBottom() or 0)
	local screenW, screenH = anchor:GetSize()
	local width, height = mover:GetSize()
	local h = POINT_SHARE[point:match("LEFT") or point:match("RIGHT") or ""] or 0.5
	local v = POINT_SHARE[point:match("BOTTOM") or point:match("TOP") or ""] or 0.5
	return math.floor(left + h * (width - screenW) + 0.5), math.floor(bottom + v * (height - screenH) + 0.5)
end

-- Put one mover back where its saved or default position says.
function E:ApplyMover(name)
	local mover = self.movers[name]
	if mover then self:RunOutOfCombat(function() ApplyPosition(mover) end) end
end

---------------------------------------------------------------------------
-- Box names. A box names its frame in its middle. With test frames on, a
-- frame that shows something (its module's sample, a stand-in or real
-- content) names itself, so the box name moves to a small tab outside the
-- box, shown while the box is hovered or selected (design decision: one name
-- per frame, and nothing written over the sample's icons). Content that
-- writes no name of its own (an icon row stand-in) keeps the tab shown.
-- Core/MoverSamples.lua sets mover.contentShown and mover.contentNamed.
---------------------------------------------------------------------------
local testing -- { [module name] = true } while test frames are on (below)
local TAB_PAD = 4

local function TabMode(mover)
	return testing ~= nil and mover.contentShown and true or false
end

local function PlaceTab(mover)
	local tab = mover.overlay.tab
	local height = tab:GetHeight()
	local top, screenTop = mover:GetTop(), UIParent:GetTop()
	tab:ClearAllPoints()
	-- Above the box, or below it when the box touches the top of the screen.
	if type(top) == "number" and type(screenTop) == "number" and top + height > screenTop then
		tab:SetPoint("TOPLEFT", mover.overlay, "BOTTOMLEFT", 0, -1)
	else
		tab:SetPoint("BOTTOMLEFT", mover.overlay, "TOPLEFT", 0, 1)
	end
end

local function CreateTab(mover)
	local tab = CreateFrame("Frame", nil, mover.overlay)
	tab:SetFrameLevel(mover.overlay:GetFrameLevel() + 5)
	E:SetTemplate(tab)
	tab.text = E.UIKit.Text(tab, E.tokens.size.small, "LEFT")
	tab.text:SetPoint("LEFT", TAB_PAD, 0)
	tab.text:SetWordWrap(false)
	tab:Hide()
	mover.overlay.tab = tab
	return tab
end

-- Boxes that share one spot: several frames placed on the same rect (the
-- mail, merchant and bank windows open at one point, and never at the same
-- time) draw one box. The first of the group draws the fill, the border and
-- one label with every name; the others draw nothing and let the clicks
-- through to it. Its menu lists the others, and picking one makes it the
-- box that answers the mouse, so each can still be moved alone. A frame
-- dragged off the spot gets its own box again.
local shared = {}     -- [mover] = its group (2 or more), the first one draws
local sharedPick = {} -- [spot] = the mover picked from the box's menu

local function SharedLead(mover)
	local group = shared[mover]
	return not group or group[1] == mover
end

-- A label wider than its box wraps to the box, two lines at most, when its
-- longest word fits; otherwise it sits on the tab just outside the box.
-- Returns "line", "wrap" or "outside".
local LABEL_PAD = 4
function E:FitBoxLabel(fontString, text, boxWidth, lines)
	fontString:SetWidth(0)
	fontString:SetWordWrap(false)
	fontString:SetText(text)
	local room = (boxWidth or 0) - LABEL_PAD * 2
	local width = fontString:GetStringWidth() or 0
	if width <= room then return "line" end
	local plain = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	local longest = 0
	for word in plain:gmatch("%S+") do longest = math.max(longest, #word) end
	if room > 0 and #plain > 0 and longest * width / #plain <= room and width <= room * (lines or 2) then
		fontString:SetWidth(room)
		fontString:SetWordWrap(true)
		fontString:SetMaxLines(lines or 2)
		return "wrap"
	end
	return "outside"
end

-- The label of a shared box: every name, cut to "A, B +3" while it is too
-- long for two lines of the box.
local function SharedTitle(group, fontString, boxWidth)
	local names = {}
	for _, member in ipairs(group) do names[#names + 1] = L[member.title] end
	for count = #names, 1, -1 do
		local text = table.concat(names, ", ", 1, count)
		if count < #names then text = ("%s +%d"):format(text, #names - count) end
		if count == 1 or E:FitBoxLabel(fontString, text, boxWidth) ~= "outside" then return text end
	end
end

local function PaintOverlayText(mover)
	local locked = E.db.moverLocks and E.db.moverLocks[mover.name]
	local title = L[mover.title]
	local overlay = mover.overlay
	if not SharedLead(mover) then
		overlay.text:SetText("")
		overlay.text:Hide()
		if overlay.tab then overlay.tab:Hide() end
		return
	end
	local group = shared[mover]
	if group then title = SharedTitle(group, overlay.text, mover:GetWidth()) or title end
	local fit = not TabMode(mover) and E:FitBoxLabel(overlay.text, title, mover:GetWidth(), locked and 3 or 2) or nil
	if TabMode(mover) or fit == "outside" then
		overlay.text:SetText("")
		overlay.text:Hide()
		local tab = overlay.tab or CreateTab(mover)
		local text = title
		if locked then text = text .. " " .. E:TokenHex(E.media.text.secondary) .. L["(locked)"] .. "|r" end
		tab.text:SetText(text)
		tab:SetSize(math.ceil((tab.text:GetStringWidth() or 40) + TAB_PAD * 2), math.ceil((tab.text:GetStringHeight() or 10) + TAB_PAD))
		PlaceTab(mover)
		-- A label outside its box always shows; over test content only
		-- when the box is picked or under the mouse.
		tab:SetShown(fit == "outside" or mover == selected or overlay.hover:IsShown() or not mover.contentNamed)
	else
		if overlay.tab then overlay.tab:Hide() end
		local text = title
		if locked then text = text .. "\n" .. E:TokenHex(E.media.text.secondary) .. L["(locked)"] .. "|r" end
		overlay.text:SetText(text)
		overlay.text:Show()
	end
end

-- The box fill: lighter over content shown by test frames, so the samples
-- read clearly through it.
local function PaintOverlayFill(mover)
	local r, g, b = unpack(E.media.accentColor)
	if not SharedLead(mover) then
		-- The group's first box draws for it.
		mover.overlay:SetBackdropColor(r, g, b, 0)
		mover.overlay:SetBackdropBorderColor(0, 0, 0, 0)
		return
	end
	mover.overlay:SetBackdropColor(r, g, b, TabMode(mover) and 0.2 or 0.45)
end

-- Groups the shown boxes by their rect on screen (whole units), so the
-- spot counts after edge shifts and attached frames too.
local function SpotOf(mover)
	local left, bottom, width, height = mover:GetRect()
	if not (left and width) then return nil end
	local function Round(value) return math.floor(value + 0.5) end
	return ("%d:%d:%d:%d"):format(Round(left), Round(bottom), Round(width), Round(height))
end

local function ShareBoxes()
	wipe(shared)
	if not moveMode then return end
	local spots = {}
	for _, mover in pairs(E.movers) do
		if mover.overlay:IsShown() then
			local spot = SpotOf(mover)
			if spot then
				spots[spot] = spots[spot] or {}
				table.insert(spots[spot], mover)
			end
		end
	end
	for spot, group in pairs(spots) do
		if #group > 1 then
			table.sort(group, function(a, b)
				local ta, tb = L[a.title], L[b.title]
				if ta ~= tb then return ta < tb end
				return a.name < b.name
			end)
			-- The box picked from the menu (or selected) answers the mouse.
			local pick = sharedPick[spot] and E.movers[sharedPick[spot]]
			for index, member in ipairs(group) do
				if member == pick or (not pick and member == selected) then
					table.remove(group, index)
					table.insert(group, 1, member)
					break
				end
			end
			group.spot = spot
			for _, member in ipairs(group) do shared[member] = group end
		end
	end
	for _, mover in pairs(E.movers) do
		if mover.overlay:IsShown() then
			if mover ~= selected then mover.overlay:SetBackdropBorderColor(unpack(E.media.borderColor)) end
			PaintOverlayFill(mover)
			PaintOverlayText(mover)
			mover:EnableMouse(not (overlayHidden or peeking) and SharedLead(mover))
		end
	end
end

local function QueueShare()
	if moveMode then E:Debounce("Movers:share", 0, ShareBoxes) end
end

-- The boxes on this mover's spot, the box itself first, or nil.
function E:SharedMoverBoxes(mover)
	if type(mover) == "string" then mover = self.movers[mover] end
	local group = mover and shared[mover]
	if not group then return nil end
	local list = {}
	for _, member in ipairs(group) do list[#list + 1] = member end
	return list
end

-- Core/MoverSamples.lua says whether a frame shows something now (shown)
-- and whether that content writes the frame's name (named).
function E:SetMoverContent(mover, shown, named)
	shown, named = shown and true or false, named and true or false
	if mover.contentShown == shown and mover.contentNamed == named then return end
	mover.contentShown, mover.contentNamed = shown, named
	if moveMode and mover.overlay:IsShown() then
		PaintOverlayFill(mover)
		PaintOverlayText(mover)
	end
end

---------------------------------------------------------------------------
-- Locks: a locked mover can't be dragged (arrows and boxes still work).
---------------------------------------------------------------------------

function E:IsMoverLocked(name)
	local locks = self.db and self.db.moverLocks
	return locks and locks[name] and true or false
end

function E:SetMoverLocked(name, locked)
	local mover = self.movers[name]
	if not mover then return false end
	self.db.moverLocks = self.db.moverLocks or {}
	self.db.moverLocks[name] = locked and true or nil
	PaintOverlayText(mover)
	if mover == selected then self:SelectMover(mover) end
	return true
end

-- Renames a mover box (its move-mode tab and locked note follow).
function E:SetMoverTitle(name, title)
	local mover = self.movers[name]
	if not mover or not title then return false end
	if mover.title ~= title then
		mover.title = title
		PaintOverlayText(mover)
	end
	return true
end

function E:CreateMover(frame, name, title, defaultPoint, opts)
	local mover = CreateFrame("Frame", name .. "Mover", UIParent)
	SeedNativeReads(mover, false)
	mover.name = name
	mover.title = title
	mover.frame = frame
	mover.defaultPoint = defaultPoint
	mover.onMoved = opts and opts.onMoved
	mover.layoutAlias = opts and opts.layoutAlias
	mover.enabledPath = opts and opts.enabledPath
	mover.group = opts and opts.group
	if opts and opts.combat ~= nil then mover.combat = opts.combat and true or false end
	mover.sizeKeys = opts and opts.sizeKeys
	if opts then mover.sample, mover.options, mover.menu = opts.sample, opts.options, opts.menu end
	-- The module starting right now, or the one that declares the mover
	-- (a window opened later, a group made on demand).
	mover.module = self.currentModule and self.currentModule.name or self:MoverOwner(name)
	-- opts.scaled: the frame has a scale of its own (a bar at 70 %), so the
	-- box takes the size the frame shows on screen, and drags and snaps
	-- with the edges the player sees.
	mover.scaled = opts and opts.scaled and true or nil
	local function FrameSize(f)
		local width, height = f:GetSize()
		if not mover.scaled then return width, height end
		local scale = f:GetScale() or 1
		return width * scale, height * scale
	end
	mover:SetSize(FrameSize(frame))
	mover:SetClampedToScreen(true)
	mover:SetMovable(true)
	mover:EnableMouse(false)
	mover:RegisterForDrag("LeftButton")
	mover:SetFrameStrata("DIALOG")

	-- Overlay shown only in move mode.
	mover.overlay = CreateFrame("Frame", nil, mover)
	mover.overlay:SetAllPoints()
	self:SetTemplate(mover.overlay)
	local r, g, b = unpack(self.media.accentColor)
	mover.overlay:SetBackdropColor(r, g, b, 0.45)
	-- Hover (DESIGN.md 3a): the white `hover.control` overlay; the accent
	-- border is for the selected mover only.
	mover.overlay.hover = mover.overlay:CreateTexture(nil, "ARTWORK")
	SeedNativeReads(mover.overlay.hover, true)
	mover.overlay.hover:SetAllPoints()
	mover.overlay.hover:SetColorTexture(1, 1, 1, self.tokens.hover.control)
	mover.overlay.hover:Hide()
	mover.overlay.text = self:CreateText(mover.overlay, self.tokens.size.label)
	mover.overlay.text:SetPoint("CENTER")
	PaintOverlayText(mover)
	mover.overlay:Hide()
	-- A module showing or hiding the mover with its frame updates move mode.
	mover:SetScript("OnShow", function(m) if moveMode then E:RestoreMoverOverlay(m) end end)
	mover:SetScript("OnHide", function(m) if moveMode then E:DropMoverOverlay(m) end end)

	mover:SetScript("OnDragStart", function(m)
		if InCombatLockdown() then return end
		-- A locked frame stays put; a click still selects it.
		if E:IsMoverLocked(m.name) then return end
		m.dragging = true
		m.alignTargets = nil
		m.alignTargets = { AlignTargets(m) }
		m:StartMoving()
		m.guideWait = 0
		m:SetScript("OnUpdate", GuideUpdate)
	end)
	mover:SetScript("OnDragStop", function(m)
		E:EndMoverDrag(m)
		E:SelectMover(m)
		QueueShare()
	end)
	-- Right-click opens the box's menu, titled with its name; Shift-right-
	-- click resets it to its layout position at once.
	mover:SetScript("OnMouseUp", function(m, button)
		if button == "RightButton" and IsShiftKeyDown() then
			if E:IsMoverLocked(m.name) then
				E:Print(L["%s is locked. Unlock it in the move panel to reset it."]:format(L[m.title]))
			else
				E:ResetMover(m.name)
			end
		end
		E:SelectMover(m)
		if button == "RightButton" and not IsShiftKeyDown() then E:OpenMoverMenu(m) end
	end)
	mover:SetScript("OnEnter", function(m)
		if not moveMode then return end
		m.overlay.hover:Show()
		PaintOverlayText(m)
		GameTooltip:SetOwner(m, "ANCHOR_TOP")
		E.UIKit.TipTitle(GameTooltip, L[m.title])
		local group = shared[m]
		if group then
			local others = {}
			for _, member in ipairs(group) do
				if member ~= m then others[#others + 1] = L[member.title] end
			end
			E.UIKit.TipText(GameTooltip, L["Also on this spot: %s. Right-click to pick one."]:format(table.concat(others, ", ")))
		end
		local tr, tg, tb = unpack(E.tokens.text.secondary)
		E:TooltipHint(GameTooltip, { L["Drag"], L["move: it snaps to the grid and to other frames, hold Alt to place it freely"] }, { L["Click"], L["select it, then nudge it with the arrows or the arrow keys (Shift: 10)"] })
		E:TooltipHint(GameTooltip, { L["Right-click"], L["hide, lock or reset it"] }, { L["Shift-right-click"], L["back to its layout position"] })
		GameTooltip:Show()
	end)
	mover:SetScript("OnLeave", function(m)
		m.overlay.hover:Hide()
		if moveMode then PaintOverlayText(m) end
		GameTooltip_Hide()
	end)
	-- A target that changes size moves the frames attached to it (they hang
	-- from its edge): their saved fallback and listeners follow, out of
	-- combat, once per mover however often it resizes in combat.
	mover:SetScript("OnSizeChanged", function(m)
		if moveMode and m.overlay:IsShown() then
			PaintOverlayText(m)
			QueueShare()
		end
		-- Sizes can change before the profile is loaded or while the game
		-- shuts down; without saved positions nothing hangs from it.
		if not (E.db and E.db.movers) or not E:HasMoverChildren(m.name) then return end
		E:RunOutOfCombat(function() ApplyChildren(m) end, "Movers:resize:" .. m.name)
	end)
	-- Setting a mouse script turns the mouse on again. Outside move mode the
	-- mover sits over its frame at DIALOG strata and would eat its clicks
	-- (unit frame right-click menus, Blizzard windows on top).
	mover:EnableMouse(false)

	-- Keep the mover the same size as its frame. Hooked before the first
	-- placement, so an onMoved callback that resizes the frame is seen.
	HookOwnedGeometry(frame, "SetSize", function(f) mover:SetSize(FrameSize(f)) end)
	HookOwnedGeometry(frame, "SetWidth", function(f) mover:SetSize(FrameSize(f)) end)
	HookOwnedGeometry(frame, "SetHeight", function(f) mover:SetSize(FrameSize(f)) end)
	if mover.scaled then HookOwnedGeometry(frame, "SetScale", function(f) mover:SetSize(FrameSize(f)) end) end
	-- Registered before the first placement, so E:GetMoverDefaultPoint and
	-- the callbacks can find it.
	self.movers[name] = mover
	mover.followShown = opts and opts.followShown and true or nil
	if opts and opts.followShown then
		frame:HookScript("OnShow", function() mover:Show() end)
		frame:HookScript("OnHide", function() mover:Hide() end)
		mover:SetShown(frame:IsShown())
	end
	-- Constructor origin and delivery authority are admitted together.
	TagMoverGeometry(name, mover, frame)

	ApplyPosition(mover)
	frame:ClearAllPoints()
	frame:SetPoint("CENTER", mover, "CENTER")
	-- Movers attached or chained to this one that were created first (and
	-- used their fallback point) hang from it now.
	local moverName = name .. "Mover"
	for otherName, other in pairs(self.movers) do
		local pos = self:SavedMoverPosition(otherName)
		local linked = type(pos) == "table" and type(pos.link) == "table" and pos.link.to == name
		local chained = false
		if not linked and other ~= mover then
			local point = PositionOf(otherName)
			chained = type(point) == "table" and point[2] == moverName
		end
		if other ~= mover and (linked or chained) then
			self:RunOutOfCombat(function() ApplyPosition(other) end)
		end
	end
	-- A frame created while move mode is on (a bar just switched on) shows its box at once.
	if moveMode then UpdateOverlay(mover) end
	-- A frame the layout keeps off, made after the layout was applied (its
	-- module was off then): switched off once the module has finished
	-- building it (Core/Layout.lua).
	local pending = self.db.general.layoutPending
	if pending and pending[name] then
		C_Timer.After(0, function() E:ApplyPendingLayoutHidden(name) end)
	end
	-- A piece hidden in the profile stays hidden from the start (Core/Hideable.lua).
	if self.ApplyHidden then self:ApplyHidden(name) end

	return mover
end

-- The box menu in move mode, titled with the box's name so the player sees
-- what they hit: Hide (the piece itself, saved in the profile), Hide this
-- box (until move mode ends), Lock, Layout (Horizontal, Vertical, Grid or
-- Blizzard default, for frames that offer them: Core/MoveSetup.lua), Size
-- and Spacing where the frame has them, Reset position and Options. A unit or group frame's box has no Hide: those
-- stay switches on their pages.
function E:OpenMoverMenu(mover)
	if type(mover) == "string" then mover = self.movers[mover] end
	if not mover then return end
	local name = mover.name
	self.moverMenuOpen = true
	return self.UIKit.ContextMenu(mover, function(_, root)
		root:CreateTitle(L[mover.title])
		-- The other frames on this spot: picking one makes its box the one
		-- that drags.
		local group = shared[mover]
		if group then
			root:CreateTitle(L["Also on this spot"])
			for _, member in ipairs(group) do
				if member ~= mover then
					root:CreateButton(L[member.title], function() E:SelectMover(member) end)
				end
			end
			root:CreateDivider()
		end
		if self.CanHide and self:CanHide(name) then
			root:CreateCheckbox(L["Hide"], function() return E:IsHidden(name) end,
				function() E:SetHidden(name, not E:IsHidden(name)) end)
		end
		root:CreateButton(L["Hide this box"], function() E:HideMoverForSession(name) end)
		root:CreateCheckbox(L["Lock"], function() return E:IsMoverLocked(name) end,
			function() E:SetMoverLocked(name, not E:IsMoverLocked(name)) end)
		if type(mover.menu) == "function" then mover.menu(root, mover) end
		if E.AddMoverLayoutEntries then E:AddMoverLayoutEntries(root, mover) end
		if E.AddMoverStepEntries then E:AddMoverStepEntries(root, mover) end
		root:CreateButton(L["Reset position"], function()
			E:ResetMover(name)
			if selected == mover then E:SelectMover(mover) end
		end)
		local options = root:CreateButton(L["Options…"], function() E:OpenMoverOptions(name) end)
		options:SetEnabled(self.MoverOptionsTarget ~= nil and self:MoverOptionsTarget(name) ~= nil)
	end)
end

-- Every mover is cleared before any is placed again: a layout may chain
-- mover A to B where the previous one chained B to A, and placing A while B
-- still hangs from it errors ("Cannot anchor to a region dependent on it").
local function PlaceAll()
	for _, mover in pairs(E.movers) do mover:ClearAllPoints() end
	-- One mover that can't be placed (an anchor loop from an import) is
	-- reported and the rest still get their points: before, the error
	-- stopped the loop and left every later mover off screen.
	for _, mover in pairs(E.movers) do
		local ok, err = pcall(ApplyPosition, mover)
		if not ok then
			geterrorhandler()(err)
			-- Left without any point the box and its frame stay off screen:
			-- the screen's center keeps them in sight, to be dragged back.
			local okCount, count = pcall(mover.GetNumPoints, mover)
			if okCount and count == 0 then
				pcall(OwnedPositionWrite, mover, "SetPoint", "CENTER", UIParent, "CENTER", 0, 0)
			end
		end
	end
end

-- Put one mover back on its layout (or default) position.
function E:ResetMover(name)
	local mover = self.movers[name]
	if not mover then return false end
	RememberMove(name)
	local store = self:MoverStore()
	if store ~= self.db.movers and self.db.movers[name] ~= nil
		and not (self.GamepadOverlayOwns and self:GamepadOverlayOwns(name)) then
		store[name] = false
	else
		store[name] = nil
	end
	self:RunOutOfCombat(function()
		ApplyPosition(mover)
		ApplyChildren(mover)
	end)
	QueueShare()
	return true
end

-- skipLocked: frames the player locked keep their place (the confirmed
-- Reset all of move mode, the Layouts page and /eui resetlayout).
function E:ResetMovers(skipLocked)
	local store = self:MoverStore()
	if moveMode then
		undoMoves[#undoMoves + 1] = { store = store, all = CopyTable(store), at = GetTime() }
		if #undoMoves > UNDO_LIMIT then table.remove(undoMoves, 1) end
	end
	local kept = {}
	if skipLocked then
		for name in pairs(self.db.moverLocks or {}) do
			if self:IsMoverLocked(name) and store[name] ~= nil then kept[name] = store[name] end
		end
	end
	wipe(store)
	if store ~= self.db.movers then
		for name in pairs(self.db.movers) do
			if not (self.GamepadOverlayOwns and self:GamepadOverlayOwns(name)) then store[name] = false end
		end
	end
	for name, pos in pairs(kept) do store[name] = pos end
	self:RunOutOfCombat(PlaceAll)
end

-- Locked frames with a place of their own, which a confirmed reset keeps.
local function CountLockedDrags(store)
	local count = 0
	for name in pairs(E.db.moverLocks or {}) do
		if E:IsMoverLocked(name) and store[name] ~= nil then count = count + 1 end
	end
	return count
end

-- The Layouts page and /eui resetlayout ask first; with nothing dragged
-- there is nothing to reset.
function E:ConfirmResetMovers()
	local function HasDrags(store)
		for name in pairs(store) do
			if self:SavedMoverPosition(name) ~= nil then return true end
		end
	end
	if not HasDrags(self:MoverStore()) and not HasDrags(self.db.movers) then
		self:ConfigNotice(L["No frame was dragged: every frame is where the layout puts it."])
		return
	end
	local text = L["Put every frame you dragged back where the current layout puts it?"]
	local locked = CountLockedDrags(self:MoverStore())
	if locked > 0 then
		text = text .. "\n\n" .. (locked == 1 and L["1 locked frame stays where it is."] or L["%d locked frames stay where they are."]:format(locked))
	end
	if moveMode then text = text .. "\n\n" .. L["Undo last (Ctrl+Z) brings them back."] end
	self:ShowConfirm({ title = L["Reset dragged frames"], accept = L["Reset"], danger = true,
		text = text,
		onAccept = function()
			E:ResetMovers(true)
			if moveMode then
				for _, mover in pairs(E.movers) do PaintOverlayText(mover) end
				E:SelectMover(selected)
			else
				E:ConfigNotice(L["All frames reset to the current layout."])
			end
		end })
end

function E:RefreshMovers()
	self:RunOutOfCombat(PlaceAll)
end

---------------------------------------------------------------------------
-- Move mode
---------------------------------------------------------------------------
-- A mover takes part in move mode while it is shown (modules hide the
-- mover together with a frame that is switched off), its module is on and
-- it passes the move-mode filters (group, search, hidden for the session).
-- Optional move-mode filter: only movers it accepts take part (/eui sct move).
local moveFilter

local function MoverActive(mover)
	-- The hidden view shows a hidden piece's box even while its frame (and
	-- a mover that follows it) is hidden.
	local hiddenView = moveMode and view.mode == "hidden" and not moveFilter
	if not mover:IsShown() and not (hiddenView and PieceHidden(mover)) then return false end
	if moveFilter and not moveFilter(mover) then return false end
	if moveMode and not InView(mover) then return false end
	local module = mover.module and E.modules[mover.module]
	return not module or module.active and true or false
end

-- Show or hide one mover's move-mode overlay, in the profile's accent color.
-- The box's alpha: gone while hidden or peeking, dimmed in the hidden view.
local function OverlayAlpha()
	if moveMode and (overlayHidden or peeking) then return 0 end
	return (moveMode and view.mode == "hidden") and 0.5 or 1
end

-- A mover shown only for the hidden view goes back to how it was.
local function EndPeekShown(mover)
	if not mover.peekShown then return end
	mover.peekShown = nil
	mover:SetShown(mover.followShown and mover.frame:IsShown() or false)
end

function UpdateOverlay(mover)
	local on = moveMode and MoverActive(mover)
	if on and not mover:IsShown() then
		mover.peekShown = true
		mover:Show()
	elseif not on then
		EndPeekShown(mover)
	end
	if not on then shared[mover] = nil end
	mover:EnableMouse(on and not (overlayHidden or peeking) and SharedLead(mover))
	mover.overlay:SetAlpha(OverlayAlpha())
	if on then
		if mover ~= selected then mover.overlay:SetBackdropBorderColor(unpack(E.media.borderColor)) end
		PaintOverlayFill(mover)
		PaintOverlayText(mover)
	end
	mover.overlay:SetShown(on)
	if not on then mover.overlay.hover:Hide() end
	QueueShare()
	-- Off for now (frame hidden, module off): it comes back once shown.
	mover.dropped = (moveMode and not on) or nil
	if not on and mover == selected then E:SelectMover(nil) end
end

-- A new accent while move mode is open repaints the boxes.
E:OnThemeChanged("movers", function()
	if not moveMode then return end
	for _, mover in pairs(E.movers) do
		if mover.overlay:IsShown() then UpdateOverlay(mover) end
	end
	if selected then selected.overlay:SetBackdropBorderColor(unpack(E.media.accentColor)) end
end)

-- While move mode is on, a mover whose frame or module switches off loses
-- its box, and gets it back when it comes back on. Only boxes taken away
-- here come back: modules that hide their own boxes after ToggleMoveMode
-- (action bars that are off, windows EldoUI may not move) keep them hidden.
function E:DropMoverOverlay(mover)
	if not moveMode or not mover.overlay:IsShown() then return end
	mover.dropped = true
	mover.overlay:Hide()
	mover:EnableMouse(false)
	if mover == selected then self:SelectMover(nil) end
	QueueShare()
end

function E:RestoreMoverOverlay(mover)
	if not moveMode or not mover.dropped or mover.peekShown then return end
	if MoverActive(mover) then
		mover.dropped = nil
		UpdateOverlay(mover)
	end
end

-- A module was switched on or off (Core/Modules.lua): its movers follow.
-- Without a module every mover is checked (a move-mode filter changed).
function E:RefreshMoveMode(module)
	if not moveMode then return end
	for _, mover in pairs(self.movers) do
		if not module or mover.module == module.name then
			if MoverActive(mover) then
				if not mover:IsShown() then
					-- A hidden piece whose mover hides with its frame: the
					-- hidden view shows its box.
					mover.dropped = nil
					UpdateOverlay(mover)
				else
					self:RestoreMoverOverlay(mover)
					mover.overlay:SetAlpha(OverlayAlpha())
				end
			else
				self:DropMoverOverlay(mover)
				EndPeekShown(mover)
			end
		end
	end
	ShareBoxes()
	if UpdatePanel then UpdatePanel() end
end

-- Does the current move-mode filter (if any) let this mover take part?
-- For modules that show their own movers' overlays.
function E:MoveModeAccepts(mover)
	return not moveFilter or (mover ~= nil and moveFilter(mover) and true or false)
end

-- Is this mover part of move mode right now? (shown, its module on, and
-- not filtered out)
function E:IsMoverActive(name)
	local mover = type(name) == "table" and name or self.movers[name]
	return mover and MoverActive(mover) or false
end

-- Move-mode filters. They last until move mode ends.
-- group: one of E.moverGroups, or nil for all.
function E:SetMoverGroupFilter(group)
	if group ~= nil and not tContains(self.moverGroups, group) then group = nil end
	view.group = group
	local modeChanged = group and view.mode ~= "all"
	if group then view.mode = "all" end
	self:RefreshMoveMode()
	-- Test frames of the group's modules start when the group leaves Combat mode.
	if modeChanged and moveMode and self:IsMoveModeTest() then
		self:SetMoveModeTest(false)
		self:SetMoveModeTest(true)
	end
end

-- Open move mode on one frame, for a module's own "Move" button: a frame
-- outside Combat mode shows with its group, and it is selected.
function E:MoveFrame(name)
	if not moveMode then self:ToggleMoveMode(true) end
	if not moveMode then return end
	local mover = self.movers[name]
	if not mover then return end
	if not InMode(mover) then self:SetMoverGroupFilter(self:GetMoverGroup(mover)) end
	if self.SelectMover and MoverActive(mover) then self:SelectMover(mover) end
end

-- view: "combat" (the everyday fight screen) or "all" (every frame).
-- Module test frames that only belong to the other view start or stop.
function E:SetMoveView(mode)
	mode = (mode == "all" or mode == "hidden") and mode or "combat"
	if view.mode == mode and not view.group then return end
	view.mode, view.group = mode, nil
	self:RefreshMoveMode()
	if moveMode and self:IsMoveModeTest() then
		self:SetMoveModeTest(false)
		self:SetMoveModeTest(true)
	end
end

function E:GetMoveView()
	return view.mode
end

-- Does the view mode (combat or all) take this mover? Ignores the group,
-- search and session-hidden filters, which only tidy the boxes.
function E:MoverInMoveView(mover)
	return mover ~= nil and InMode(mover)
end

function E:GetMoverGroupFilter()
	return view.group
end

-- Show only movers whose title contains `text` (any case or accent).
function E:SetMoverSearch(text)
	view.search = self:FoldText(tostring(text or ""))
	self:RefreshMoveMode()
end

-- Hide one mover's box until move mode ends; its frame stays where it is.
function E:HideMoverForSession(name)
	if not moveMode or not self.movers[name] then return false end
	view.hidden[name] = true
	self:RefreshMoveMode()
	return true
end

function E:ShowHiddenMovers()
	wipe(view.hidden)
	self:RefreshMoveMode()
end

function E:MoverBoxHidden(name)
	return view.hidden[name] == true
end

function E:CountHiddenMovers()
	local count = 0
	for _ in pairs(view.hidden) do count = count + 1 end
	return count
end

-- Movers of each group taking part in move mode, ignoring the group and
-- search filters (for the group menu).
function E:CountMoversByGroup()
	local counts, group, search, mode = {}, view.group, view.search, view.mode
	view.group, view.search, view.mode = nil, "", "all"
	local combat, all = 0, 0
	for _, mover in pairs(self.movers) do
		if mover.overlay and (mover.overlay:IsShown() or mover.dropped) and MoverActive(mover) then
			local key = self:GetMoverGroup(mover)
			counts[key] = (counts[key] or 0) + 1
			all = all + 1
			if self:IsCombatMover(mover) then combat = combat + 1 end
		end
	end
	view.group, view.search, view.mode = group, search, mode
	return counts, combat, all
end

---------------------------------------------------------------------------
-- Move session: what move mode started from, so "Undo changes"
-- can put every frame back and leaving can return to the options window.
---------------------------------------------------------------------------
local session -- { db, movers, locks, layouts, returnToConfig }
-- Combat closed move mode: { session, filter, undo } to open it again with
-- when combat ends, so Undo changes and Undo last move still reach back.
local paused
local pausing -- set while combat closes move mode

-- Did anything change since move mode started (positions, links, locks,
-- the layout choices of the box menus)?
function E:MoveSessionChanged()
	if not session or session.db ~= self.db then return false end
	if self.MoverLayoutsChanged and self:MoverLayoutsChanged(session.layouts) then return true end
	return not (E.DeepEqual(session.movers, session.store) and E.DeepEqual(session.locks, self.db.moverLocks or {}))
end

-- Put every position, link, lock and layout choice back to how they were
-- when move mode started. Move mode stays on.
function E:UndoMoveSession()
	if not session or session.db ~= self.db or InCombatLockdown() then return false end
	-- Layout choices first: they size the frames the positions measure.
	if self.RestoreMoverLayouts then self:RestoreMoverLayouts(session.layouts) end
	wipe(session.store)
	for name, pos in pairs(CopyTable(session.movers)) do session.store[name] = pos end
	self.db.moverLocks = self.db.moverLocks or {}
	wipe(self.db.moverLocks)
	for name, on in pairs(session.locks) do self.db.moverLocks[name] = on end
	PlaceAll()
	undoMoves = {}
	for _, mover in pairs(self.movers) do PaintOverlayText(mover) end
	self:SelectMover(selected)
	return true
end

-- Take back the newest change of this move session: one drag, nudge,
-- typed position, attach, reset or Reset all. Ctrl+Z in move mode.
function E:UndoLastMove()
	if not moveMode or InCombatLockdown() then return false end
	local entry = table.remove(undoMoves)
	if not entry then return false end
	if entry.store ~= self:MoverStore() then
		-- Gamepad Mode UI switched the positions: the old steps are another set.
		undoMoves = {}
		return false
	end
	if entry.all then
		wipe(entry.store)
		for name, pos in pairs(entry.all) do entry.store[name] = pos end
		PlaceAll()
		for _, mover in pairs(self.movers) do PaintOverlayText(mover) end
		self:SelectMover(selected)
	else
		local pos = entry.pos
		if pos == NO_POSITION then pos = nil end
		entry.store[entry.name] = pos
		local mover = self.movers[entry.name]
		if mover then
			ApplyPosition(mover)
			ApplyChildren(mover)
			PaintOverlayText(mover)
		end
		self:SelectMover(mover or selected)
	end
	QueueShare()
	return true
end

-- How many steps Undo last move can take back.
function E:CountMoveUndo()
	return moveMode and #undoMoves or 0
end

---------------------------------------------------------------------------
-- Test frames: one switch in move mode shows every module's sample
-- frames at once (unit frames, party and raid, loot rolls, alerts,
-- battleground and encounter timer bars), so the whole layout can be
-- placed. Only modules that are on take part. It ends with move mode, and
-- move mode ends when combat starts; samples never start in combat.
---------------------------------------------------------------------------
-- testing (declared with the box names above): { [module name] = true } for
-- the samples this switch started.

-- Run fn(module) with the module's chat line muted: the panel's switch is
-- the feedback, so the "Showing test frames" line of a module is noise here.
local function Quiet(module, fn)
	local own = rawget(module, "Print")
	module.Print = function() end
	local ok, err = pcall(fn, module)
	module.Print = own
	if not ok then geterrorhandler()(err) end
	return ok
end

E.moveModeTests = {
	{ module = "UnitFrames",
		on = function(m) m:SetTestMode(true) return m.testMode end,
		off = function(m) if m.testMode then m:SetTestMode(false) end end },
	{ module = "GroupFrames",
		on = function(m) m:ShowTest(true, true) return m.testing end,
		off = function(m) if m.testing then m:ShowTest(false) end end },
	{ module = "Loot",
		on = function(m)
			local shown = false
			if E:BlizzardAllowed("group-loot-rolls", "replace") then
				m:TestRolls()
				shown = true
			end
			-- The loot toasts or feed, one sample per source that is on.
			if m.db.toasts and type(m.ShowSamples) == "function" then
				m:ShowSamples()
				shown = true
			end
			return shown
		end },
	{ module = "Notifications",
		on = function(m)
			if not (m.tests and m.tests.lane) or not E:BlizzardAllowed("alert-toasts", "replace") then return false end
			m.tests.lane()
			return true
		end },
	{ module = "Battlegrounds",
		on = function(m) m:ShowTestBars() return true end,
		off = function(m) m:HideTestBars() end },
	{ module = "EncounterTimeline",
		on = function(m) if m.testing then return false end return m:StartTest("dungeon") end,
		off = function(m) if m.testing then m:StopTest() end end },
	{ module = "Reminders",
		on = function(m)
			if type(m.SetPreview) ~= "function" then return false end
			m:SetPreview(true)
			return m.preview and true or false
		end,
		off = function(m) if type(m.SetPreview) == "function" then m:SetPreview(false) end end },
	{ module = "RaidTools",
		on = function(m)
			if type(m.Preview) ~= "function" or m.preview then return false end
			m:Preview()
			return m.preview and true or false
		end,
		off = function(m)
			if m.previewTimer then m.previewTimer:Cancel() end
			m.preview, m.previewTimer = nil, nil
			if type(m.UpdateVisibility) == "function" then m:UpdateVisibility() end
		end },
}

-- Every box on screen, after test frames start or stop.
function RepaintBoxes()
	for _, mover in pairs(E.movers) do
		if mover.overlay:IsShown() then
			PaintOverlayFill(mover)
			PaintOverlayText(mover)
		end
	end
end

function E:IsMoveModeTest()
	return testing ~= nil
end

-- Has this module a mover the view mode takes? (Its test frames only
-- start then: combat mode skips loot rolls and toasts.)
function E:ModuleInMoveView(moduleName)
	if view.mode == "all" then return true end
	for _, mover in pairs(self.movers) do
		if mover.module == moduleName and InMode(mover) then return true end
	end
	return false
end

-- state true: start the samples (move mode on, out of combat); false: stop
-- the ones this switch started. Returns how many modules show samples.
function E:SetMoveModeTest(state)
	if state then
		if testing or not moveMode or InCombatLockdown() then return 0 end
		testing = {}
		local count = 0
		for _, test in ipairs(self.moveModeTests) do
			local module = self.modules[test.module]
			if module and module.active and self:ModuleInMoveView(test.module) then
				local started = false
				Quiet(module, function(m) started = test.on(m) and true or false end)
				if started then
					testing[test.module] = true
					count = count + 1
				end
			end
		end
		-- Every frame still empty gets a stand-in (Core/MoverSamples.lua).
		if self.ShowMoverSamples then self:ShowMoverSamples(true) end
		RepaintBoxes()
		if UpdatePanel then UpdatePanel() end
		return count
	end
	if not testing then return 0 end
	local started = testing
	testing = nil
	if self.ShowMoverSamples then self:ShowMoverSamples(false) end
	RepaintBoxes()
	for _, test in ipairs(self.moveModeTests) do
		local module = self.modules[test.module]
		if started[test.module] and module and test.off then
			-- At combat start (PLAYER_REGEN_DISABLED) the lockdown has not
			-- begun yet, so this runs at once; later it waits for combat's end.
			self:RunOutOfCombat(function() Quiet(module, test.off) end, "Movers:testOff:" .. test.module)
		end
	end
	if UpdatePanel then UpdatePanel() end
	return 0
end

-- filter (optional): function(mover) -> true for the movers to show, so a
-- module can unlock only its own frames. It lasts until move mode ends.
-- Toggling (state nil: the Move mode buttons, /eui move, the Done button)
-- off shows the options window again if move mode hid it; an explicit
-- false (combat, keybind mode, Edit Mode) doesn't.
function E:ToggleMoveMode(state, filter)
	if InCombatLockdown() then
		self:Print(L["Frames can't be moved in combat."])
		return
	end
	local toggled = state == nil
	if state == nil then state = not moveMode end
	local wasOn = moveMode
	local oldFilter = moveFilter
	if state and not wasOn then
		undoMoves = {}
		paused = nil
		session = {
			db = self.db,
			-- The drags of the mode move mode started in (Gamepad Mode UI's own
			-- while it is on).
			store = self:MoverStore(),
			movers = CopyTable(self:MoverStore()),
			locks = CopyTable(self.db.moverLocks or {}),
			layouts = self.MoverLayoutsSnapshot and self:MoverLayoutsSnapshot() or nil,
			-- The options window gets out of the way and comes back after.
			returnToConfig = self.CloseConfigForMoveMode and self:CloseConfigForMoveMode() and true or nil,
		}
	end
	moveMode = state
	moveFilter = state and filter or nil
	-- A caller's own filter picks the frames, whatever the view.
	if moveFilter then view.mode = "all" end
	if not state then
		-- A box's menu goes away with its box.
		if self.moverMenuOpen and self.UIKit.MenuShown() then self.UIKit.CloseMenu() end
		self.moverMenuOpen = nil
		self:SetMoveModeTest(false)
		-- Find a frame's bring-back question goes with move mode.
		if self.CancelConfirm then self:CancelConfirm("moverBringBack") end
		overlayHidden, peeking = false, false
		selected = nil
		view.mode, view.group, view.search = "combat", nil, ""
		wipe(view.hidden)
		self:UpdateMoverGuides(nil)
	end
	if not state then wipe(sharedPick) end
	for _, mover in pairs(self.movers) do UpdateOverlay(mover) end
	ShareBoxes()
	self:ShowGrid(state)
	if self.ShowSafeArea then self:ShowSafeArea(state) end
	self:ShowNudge(state)
	-- No chat line either way: the move panel and the frames'
	-- tooltips carry the help, and the grid going away says "locked".
	if not state then
		local back = session and session.returnToConfig
		if pausing and wasOn and session then
			paused = { session = session, filter = oldFilter, undo = undoMoves }
		elseif wasOn then
			paused = nil
		end
		undoMoves = {}
		session = nil
		if toggled and back and self.ReopenConfigAfterMoveMode then self:ReopenConfigAfterMoveMode() end
	end
end

-- Leaving move mode when combat starts keeps protected frames safe. At
-- PLAYER_REGEN_DISABLED the lockdown has not begun, so a drag in progress
-- ends and saves at once. The session is kept and move mode opens again
-- when combat ends, with Undo changes still reaching back to its start.
E:RegisterEvent("PLAYER_REGEN_DISABLED", function()
	if not moveMode then return end
	for _, mover in pairs(E.movers) do
		if mover.dragging then E:EndMoverDrag(mover) end
	end
	pausing = true
	local ok, err = pcall(E.ToggleMoveMode, E, false)
	pausing = nil
	if not ok then geterrorhandler()(err) end
	if paused then E:Print(L["Move mode closed: combat started. It opens again after combat."]) end
end, {})

E:RegisterEvent("PLAYER_REGEN_ENABLED", function()
	local back = paused
	paused = nil
	if not back or moveMode or back.session.db ~= E.db then return end
	E:ToggleMoveMode(true, back.filter)
	if not moveMode then return end
	back.session.returnToConfig = back.session.returnToConfig or (session and session.returnToConfig)
	session = back.session
	undoMoves = back.undo or {}
	if UpdatePanel then UpdatePanel() end
end, {})

-- Did combat close move mode, and will it open again when combat ends?
function E:IsMoveModePaused()
	return paused ~= nil
end

---------------------------------------------------------------------------
-- Grid
---------------------------------------------------------------------------
local grid
-- Set while another tool draws the grid (Blizzard's Edit Mode with its
-- grid on): { size = spacing to snap to, hidden = true to draw no grid }.
local gridOverride

-- Another tool's grid for move mode, or nil for EldoUI's own.
function E:SetMoveGridOverride(over)
	gridOverride = over
	if moveMode then self:ShowGrid(true) end
end

-- The spacing move mode snaps to.
function E:GetMoveGridSize()
	local size = gridOverride and tonumber(gridOverride.size)
	return math.max(4, size or tonumber(self.db.general.gridSize) or 32)
end

-- Color of the grid lines and of the two center lines (General > Move mode).
local function GridColors()
	local general = E.db.general
	local alpha = tonumber(general.gridAlpha) or 0.5
	local ar, ag, ab = unpack(E.media.accentColor)
	if general.gridColor == "white" then
		return { 1, 1, 1, alpha }, { ar, ag, ab, 0.9 }
	elseif general.gridColor == "accent" then
		return { ar, ag, ab, alpha }, { 1, 1, 1, 0.9 }
	end
	return { 0, 0, 0, alpha }, { ar, ag, ab, 0.9 }
end

function E:ShowGrid(state)
	if grid then
		grid:Hide()
		if not state then return end
	end
	if not state or (gridOverride and gridOverride.hidden) then return end
	grid = grid or CreateFrame("Frame", "EldoUI_Grid", UIParent)
	grid:SetAllPoints(UIParent)
	grid:SetFrameStrata("BACKGROUND")
	grid.lines = grid.lines or {}
	for _, line in ipairs(grid.lines) do line:Hide() end
	local size = self:GetMoveGridSize()
	local thickness = self.pixel * math.max(1, math.min(4, tonumber(self.db.general.gridThickness) or 1))
	local color, centerColor = GridColors()
	local w, h = UIParent:GetSize()
	local used = 0
	local function Line(horizontal, offset, center)
		used = used + 1
		local line = grid.lines[used]
		if not line then
			line = grid:CreateTexture(nil, "BACKGROUND")
			grid.lines[used] = line
		end
		line:SetColorTexture(unpack(center and centerColor or color))
		line:ClearAllPoints()
		if horizontal then
			line:SetPoint("LEFT", grid, "LEFT", 0, offset)
			line:SetPoint("RIGHT", grid, "RIGHT", 0, offset)
			line:SetHeight(thickness)
		else
			line:SetPoint("TOP", grid, "TOP", offset, 0)
			line:SetPoint("BOTTOM", grid, "BOTTOM", offset, 0)
			line:SetWidth(thickness)
		end
		line:Show()
	end
	for i = 0, math.ceil(w / 2 / size) do
		Line(false, i * size, i == 0)
		if i > 0 then Line(false, -i * size) end
	end
	for i = 0, math.ceil(h / 2 / size) do
		Line(true, i * size, i == 0)
		if i > 0 then Line(true, -i * size) end
	end
	grid:Show()
end

-- A new UI scale or window size while move mode is open: draw the grid
-- for the new screen (after the scale code has run).
local function RedrawForScreen()
	if moveMode then C_Timer.After(0, function() E:RefreshMoveModeLook() end) end
end
E:RegisterPixelCallback(RedrawForScreen)
E:RegisterEvent("UI_SCALE_CHANGED", RedrawForScreen, {})
E:RegisterEvent("DISPLAY_SIZE_CHANGED", RedrawForScreen, {})


---------------------------------------------------------------------------
-- Move panel: filters, exact X/Y, 1-pixel arrows, the selected frame's
-- actions (reset, options, hide, lock, attach) and the session buttons.
---------------------------------------------------------------------------
local nudge
local SetMeasured -- defined below

local NUDGE_KEYS = { UP = { 0, 1 }, DOWN = { 0, -1 }, LEFT = { -1, 0 }, RIGHT = { 1, 0 } }

local function Nudge(dx, dy)
	if not selected or InCombatLockdown() then return end
	if IsShiftKeyDown() then dx, dy = dx * 10, dy * 10 end
	local pos = E:SavedMoverPosition(selected.name)
	if UsableLink(selected, pos) then
		RememberMove(selected.name)
		local store = E:MoverStore()
		if store[selected.name] ~= pos then
			pos = CopyTable(pos)
			store[selected.name] = pos
		end
		-- An attached frame keeps its link; the arrows move its offset.
		pos.link.x = (tonumber(pos.link.x) or 0) + dx
		pos.link.y = (tonumber(pos.link.y) or 0) + dy
		ApplyPosition(selected)
		RememberScreen(selected, pos)
		ApplyChildren(selected)
	else
		SetMoverPosition(selected, selected:GetLeft() + dx, selected:GetBottom() + dy)
	end
	E:SelectMover(selected)
end
E.NudgeMover = function(_, dx, dy) Nudge(dx, dy) end

-- Where the selected mover sits now, measured from the screen the way a
-- drag saves it (a layout may chain it to another frame; the boxes always
-- show and edit the screen position, never the raw layout offsets).
-- The measured point, as the move panel's title names it.
local POINT_LABEL = { TOPLEFT = "Top left", TOP = "Top", TOPRIGHT = "Top right", LEFT = "Left", CENTER = "Center",
	RIGHT = "Right", BOTTOMLEFT = "Bottom left", BOTTOM = "Bottom", BOTTOMRIGHT = "Bottom right" }
-- Shown translated: L["Top left"], L["Top"], L["Top right"], L["Left"], L["Center"],
-- L["Right"], L["Bottom left"], L["Bottom"], L["Bottom right"]

local function MeasureSelected()
	if not selected or not selected:GetLeft() then return end
	local _, point, x, y = MeasureRect(selected, selected:GetLeft(), selected:GetBottom())
	return point, x, y
end

-- An X or Y box: keep the measured point and the other axis, unsnapped.
-- (This places the frame on the screen, so an attached frame is detached.)
function SetMeasured(index, value)
	if not selected or not value or InCombatLockdown() then return end
	local point, x, y = MeasureSelected()
	if not point then return end
	local pos = { point, "UIParent", point, x, y }
	pos[index] = math.floor(value + 0.5)
	RememberMove(selected.name)
	E:MoverStore()[selected.name] = pos
	ApplyPosition(selected)
	ApplyChildren(selected)
	E:SelectMover(selected)
end

---------------------------------------------------------------------------
-- Find a frame (the group menu): every frame EldoUI can place, also the
-- ones this view, the search or a session hide leaves out. Picking one
-- shows its box, selects it and flashes it. A box outside the screen asks
-- before it comes back to the nearest edge; nothing is saved without that
-- click. Out of combat only, like every move-mode change.
---------------------------------------------------------------------------
local BRING_BACK = "moverBringBack" -- the key of the bring-back question

-- A short accent flash over a box, so the eye finds it (shorter with
-- General > Animations off).
local function FlashMover(mover)
	local overlay = mover.overlay
	if not overlay.flash then
		local flash = overlay:CreateTexture(nil, "OVERLAY")
		flash:SetAllPoints()
		flash:SetColorTexture(1, 1, 1, 1)
		flash:SetAlpha(0)
		local anim = flash:CreateAnimationGroup()
		overlay.flashFade = anim:CreateAnimation("Alpha")
		overlay.flashFade:SetFromAlpha(0.7)
		overlay.flashFade:SetToAlpha(0)
		anim:SetToFinalAlpha(true)
		overlay.flash, overlay.flashAnim = flash, anim
	end
	overlay.flash:SetVertexColor(unpack(E.media.accentColor))
	overlay.flashFade:SetDuration(E.db.general.animations and 1.6 or 0.4)
	overlay.flashAnim:Stop()
	overlay.flashAnim:Play()
	mover.flashedAt = GetTime() -- when it last flashed
end

-- Where a box outside the screen comes back to: its left and bottom edge
-- moved just inside the nearest screen edges. nil while it is on screen.
function E:MoverOutsideScreen(name)
	local mover = type(name) == "table" and name or self.movers[name]
	local left, bottom = mover and mover:GetLeft(), mover and mover:GetBottom()
	if not (left and bottom) then return nil end
	local width, height = mover:GetSize()
	local screenW, screenH = UIParent:GetSize()
	local x = math.min(math.max(left, 0), math.max(0, screenW - width))
	local y = math.min(math.max(bottom, 0), math.max(0, screenH - height))
	if math.abs(x - left) < 0.5 and math.abs(y - bottom) < 0.5 then return nil end
	return x, y
end

-- The mover the move panel works on, or nil.
function E:GetSelectedMover()
	return moveMode and selected or nil
end

-- Bring one frame's box into view, select it and flash it. Returns true,
-- or false and why: "combat", "unknown" or "off" (its frame or module is
-- off, so there is no box to show).
function E:LocateMover(name)
	local mover = type(name) == "table" and name or self.movers[name]
	if not mover then return false, "unknown" end
	if InCombatLockdown() then return false, "combat" end
	if not moveMode then self:ToggleMoveMode(true) end
	if not moveMode then return false, "combat" end
	local module = mover.module and self.modules[mover.module]
	if (module and not module.active) or not (mover:IsShown() or PieceHidden(mover)) then return false, "off" end
	-- What tidies its box away for now gives way: a session hide, the
	-- search text, another group or view.
	view.hidden[mover.name] = nil
	view.search = ""
	local mode = PieceHidden(mover) and "hidden" or (InMode(mover) and view.mode) or "all"
	if mode ~= view.mode or (view.group and self:GetMoverGroup(mover) ~= view.group) then self:SetMoveView(mode) end
	self:RefreshMoveMode()
	if not (MoverActive(mover) and mover.overlay:IsShown()) then return false, "off" end
	self:SelectMover(mover)
	FlashMover(mover)
	if self:MoverOutsideScreen(mover) then
		self:ShowConfirm({ key = BRING_BACK, title = L["Find a frame"], accept = L["Bring it back"],
			text = L["%s is outside the screen. Bring it back to the nearest edge?"]:format(L[mover.title]),
			onAccept = function()
				-- Only the click saves, and only while move mode is still open.
				if not moveMode or InCombatLockdown() then return end
				local left, bottom = E:MoverOutsideScreen(mover)
				if not left then return end
				E:SaveMoverFromRect(mover, left, bottom)
				E:SelectMover(mover)
				FlashMover(mover)
			end })
	end
	return true
end

local function AddFindMenu(root)
	local sub = root:CreateButton(L["Find a frame"])
	sub:SetScrollMode(360)
	for _, row in ipairs(E:MoverCoverage()) do
		local mover = E.movers[row.name]
		local outside = row.state ~= "off" and E:MoverOutsideScreen(row.name)
		local text = row.title
		if outside then text = ("%s %s%s|r"):format(text, E:TokenHex(E.tokens.text.secondary), L["(outside the screen)"]) end
		local entry = sub:CreateRadio(text, function() return mover ~= nil and mover == selected end,
			function() E:LocateMover(row.name) end)
		local off = row.state == "off"
		if off then entry:SetEnabled(false) end
		entry:SetTooltip(function(tooltip)
			E.UIKit.TipTitle(tooltip, row.title)
			E.UIKit.TipText(tooltip, off and L["Its frame or module is off right now, so it has no box to show."]
				or L["Shows its box, selects it and flashes it."])
			if outside then E.UIKit.TipText(tooltip, L["Its box is outside the screen: picking it asks to bring it back to the nearest edge."]) end
		end)
	end
end

-- The group, attach and size menus are kit menus under their button.
local function OpenGroupMenu(owner)
	local counts, combat, all = E:CountMoversByGroup()
	E.UIKit.ContextMenu(owner, function(_, root)
		root:CreateRadio(("%s (%d)"):format(L["Combat mode"], combat),
			function() return view.mode == "combat" and view.group == nil end, function() E:SetMoveView("combat") end)
		root:CreateRadio(("%s (%d)"):format(L["All frames"], all),
			function() return view.mode == "all" and view.group == nil end, function() E:SetMoveView("all") end)
		-- The pieces hidden in the profile, dimmed, to bring them back.
		local hidden = E.CountHiddenPieces and E:CountHiddenPieces() or 0
		if hidden > 0 or view.mode == "hidden" then
			root:CreateRadio(("%s (%d)"):format(L["Hidden"], hidden),
				function() return view.mode == "hidden" and view.group == nil end, function() E:SetMoveView("hidden") end)
		end
		for _, group in ipairs(E.moverGroups) do
			if counts[group] then
				root:CreateRadio(("%s (%d)"):format(L[group], counts[group]),
					function() return view.group == group end,
					function() E:SetMoverGroupFilter(group) end)
			end
		end
		root:CreateDivider()
		AddFindMenu(root)
	end, { at = "owner" })
end

-- Movers the selected one can be attached to, sorted by title.
local function AttachTargets(name)
	local list = {}
	for otherName, other in pairs(E.movers) do
		if otherName ~= name and other.overlay:IsShown() then list[#list + 1] = other end
	end
	table.sort(list, function(a, b) return tostring(L[a.title]) < tostring(L[b.title]) end)
	return list
end

local function OpenAttachMenu(owner)
	if not selected then return end
	local name = selected.name
	E.UIKit.ContextMenu(owner, function(_, root)
		root:SetScrollMode(360)
		for _, side in ipairs(E.moverLinkSides) do
			local sub = root:CreateButton(L[LINK_LABEL[side]])
			for _, other in ipairs(AttachTargets(name)) do
				local button = sub:CreateButton(L[other.title], function() E:LinkMover(name, other.name, side) end)
				-- A frame that already hangs from this one can't be its anchor.
				if E:WouldMoverLinkLoop(name, other.name) then button:SetEnabled(false) end
			end
			sub:SetScrollMode(360)
		end
	end, { at = "owner" })
end

local SIZE_LABEL = { width = "Width of", height = "Height of" }
-- Shown translated: L["Width of"], L["Height of"]

local function OpenSizeMenu(owner)
	if not selected then return end
	local name = selected.name
	E.UIKit.ContextMenu(owner, function(_, root)
		root:SetScrollMode(360)
		for _, axis in ipairs(E.moverSizeAxes) do
			if E:CanMatchMoverSize(name, axis) then
				local sub = root:CreateButton(L[SIZE_LABEL[axis]])
				for _, other in ipairs(AttachTargets(name)) do
					sub:CreateButton(L[other.title], function() E:MatchMoverSize(name, other.name, axis) end)
				end
				sub:SetScrollMode(360)
			end
		end
	end, { at = "owner" })
end

-- The panel's controls start under the title and the help line, which grow
-- with the text size and wrap to a second line; the panel grows with them.
-- The setup strip above the bottom row adds its own height.
local NUDGE_HEIGHT, NUDGE_TOP, NUDGE_GAP = 270, 46, 7
local function LayoutNudge()
	if not nudge then return end
	nudge.title:SetHeight(math.max(1, nudge.title:GetStringHeight() or 0))
	nudge.status:SetHeight(math.max(1, nudge.status:GetStringHeight() or 0))
	local header = 10 + (nudge.title:GetHeight() or 0) + 2 + (nudge.status:GetStringHeight() or 0) + NUDGE_GAP
	local setup = math.ceil(nudge.setup:GetStringHeight() or 0)
	nudge.setup:SetHeight(math.max(1, setup))
	nudge:SetHeight(math.ceil(NUDGE_HEIGHT + math.max(0, header - NUDGE_TOP) + setup + 8))
end

-- The setup on screen, two lines (Core/MoveSetup.lua): readable in a
-- screenshot of move mode.
local function UpdateSetupStrip()
	if not (nudge and E.MoveSetupLines) then return end
	local ok, first, second = pcall(E.MoveSetupLines, E)
	nudge.setup:SetText(ok and (first .. "\n" .. second) or "")
	LayoutNudge()
end

local function CreateNudge()
	local Kit = E.UIKit
	nudge = CreateFrame("Frame", "EldoUI_Nudge", UIParent)
	nudge:SetSize(380, NUDGE_HEIGHT)
	nudge:SetPoint("TOP", 0, -60)
	nudge:SetFrameStrata("FULLSCREEN_DIALOG")
	nudge:SetMovable(true)
	nudge:EnableMouse(true)
	nudge:RegisterForDrag("LeftButton")
	nudge:SetScript("OnDragStart", nudge.StartMoving)
	nudge:SetScript("OnDragStop", nudge.StopMovingOrSizing)
	nudge:SetClampedToScreen(true)
	-- Opaque: the test frames' sample text never shows through it.
	E:SetPanelTemplate(nudge, false, 1)
	-- Escape leaves move mode like Done, and the arrow keys nudge the
	-- selected frame (10 units with Shift). Docked beside Blizzard's Edit
	-- Mode they go to that window instead; an open menu or question takes
	-- them first, Ctrl and Alt arrows and every other key reach the game.
	nudge.keys = Kit.KeyHandler(nudge, function(name, key)
		if nudge.docked or Kit.MenuShown() then return false end
		if name == "CTRL-Z" then
			if GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus() then return false end
			E:PeekMoveMode(false)
			E:UndoLastMove()
			return true
		end
		local arrow = NUDGE_KEYS[name:match("^SHIFT%-(.+)$") or name]
		if arrow then
			if not selected or (GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()) then return false end
			Nudge(arrow[1], arrow[2])
			return true
		end
		if key ~= "ESCAPE" then return false end
		local confirm = E.GetConfirm and E:GetConfirm()
		if confirm and confirm:IsShown() then return false end
		E:ToggleMoveMode(false)
		return true
	end)

	nudge.title = E:CreateText(nudge, E.tokens.size.dialogTitle)
	E:SetHeaderFont(nudge.title, E.tokens.size.dialogTitle)
	nudge.title:SetPoint("TOPLEFT", 12, -10)
	nudge.title:SetPoint("TOPRIGHT", -12, -10)
	nudge.title:SetWordWrap(false)
	-- The help line wraps inside the panel; the controls start under it.
	nudge.status = Kit.Text(nudge, E.tokens.size.small, "CENTER", "secondary")
	nudge.status:SetPoint("TOPLEFT", nudge.title, "BOTTOMLEFT", 0, -2)
	nudge.status:SetWidth(380 - 24)
	nudge.status:SetWordWrap(true)
	nudge.status:SetMaxLines(2)
	local body = CreateFrame("Frame", nil, nudge)
	body:SetPoint("TOPLEFT", nudge.status, "BOTTOMLEFT", -12, -NUDGE_GAP)
	body:SetPoint("TOPRIGHT", nudge.status, "BOTTOMRIGHT", 12, -NUDGE_GAP)
	body:SetHeight(1)
	nudge.body = body

	-- Row 1: group filter and search.
	nudge.group = Kit.Button(nudge, L["Combat mode"], 170, E.tokens.height.button, function(b) OpenGroupMenu(b) end,
		L["Frames shown"], L["Combat mode shows the frames of your everyday fight screen: unit and group frames, bars, cooldowns, combat text, boss timers, alerts, minimap and chat. All frames adds windows, toasts and the rest; a group shows only that group. Find a frame, at the end of the list, shows the box of any frame, also one outside the screen."])
	nudge.group:SetPoint("TOPLEFT", body, "TOPLEFT", 12, 0)
	local search = CreateFrame("EditBox", nil, nudge, "InputBoxTemplate")
	search:SetSize(170, 20)
	search:SetPoint("TOPRIGHT", body, "TOPRIGHT", -12, -1)
	search:SetAutoFocus(false)
	search:SetScript("OnTextChanged", function(b)
		if nudge.settingSearch then return end
		E:SetMoverSearch(b:GetText())
	end)
	search:SetScript("OnEnterPressed", function(b) b:ClearFocus() end)
	search:SetScript("OnEscapePressed", function(b)
		b:SetText("")
		b:ClearFocus()
	end)
	E:SkinEditBox(search)
	search.hint = Kit.Text(search, E.tokens.size.label, "LEFT", "dim")
	search.hint:SetPoint("LEFT", 4, 0)
	search.hint:SetText(L["Find a frame"])
	search:HookScript("OnEditFocusGained", function() search.hint:Hide() end)
	search:HookScript("OnEditFocusLost", function(b) search.hint:SetShown(b:GetText() == "") end)
	Kit.Tooltip(search, L["Find a frame"], L["Show only the frames whose name contains this text."])
	nudge.search = search

	-- Row 2: exact position and grid size. A box shows its current value
	-- again when Enter finds no number in it.
	local function Box(label, x, y, onEnter, tip)
		local text = E:CreateText(nudge, E.tokens.size.body, "RIGHT")
		text:SetPoint("TOPRIGHT", body, "TOPLEFT", x, y - 4)
		text:SetText(label)
		local box = CreateFrame("EditBox", nil, nudge, "InputBoxTemplate")
		box:SetSize(60, 20)
		box:SetPoint("TOPLEFT", body, "TOPLEFT", x + 10, y)
		box:SetAutoFocus(false)
		box:SetScript("OnEnterPressed", function(b)
			local value = tonumber(b:GetText())
			if value then onEnter(value) end
			b:ClearFocus()
			if not value then E:SelectMover(selected) end
		end)
		box:SetScript("OnEscapePressed", function(b)
			b:ClearFocus()
			E:SelectMover(selected)
		end)
		E:SkinEditBox(box)
		Kit.Tooltip(box, label, tip)
		return box
	end
	nudge.x = Box("X", 40, -32, function(value) SetMeasured(4, value) end,
		L["Across from the screen point in the title to the same point of the frame: a higher number moves it right, a lower one left. Press Enter to apply."])
	nudge.y = Box("Y", 160, -32, function(value) SetMeasured(5, value) end,
		L["Up from the screen point in the title to the same point of the frame: a higher number moves it up, a lower one down. Press Enter to apply."])
	nudge.grid = Box(L["Grid"], 290, -32, function(value)
		-- The same steps and limits as the Grid size slider on the General page.
		local size = math.min(math.max(math.floor(value / 4 + 0.5) * 4, 4), 128)
		E.db.general.gridSize = size
		nudge.grid:SetText(size)
		E:ShowGrid(true)
	end, L["The grid frames snap to, in steps of 4 from 4 to 128. Press Enter to apply."])

	-- Arrows in the middle: the kit chevrons in a flat box, like the Edit
	-- Mode panel.
	nudge.arrows = {}
	local function Arrow(dir, x, y, dx, dy)
		local b = Kit.IconButton(nudge, E.tokens.height.button, "chevron-" .. dir, function() Nudge(dx, dy) end)
		b:SetSize(32, E.tokens.height.button)
		E:SetTemplate(b, true)
		b:SetPoint("TOP", body, "TOP", x, y)
		Kit.Tooltip(b, L["Nudge"], L["One pixel per click. Hold Shift for 10."])
		nudge.arrows[dir] = b
		return b
	end
	Arrow("up", 0, -60, 0, 1)
	Arrow("left", -36, -84, -1, 0)
	Arrow("right", 36, -84, 1, 0)
	Arrow("down", 0, -108, 0, -1)

	-- Left column: reset, hide for the session, show the hidden ones.
	nudge.resetOne = Kit.Button(nudge, L["Reset"], 110, E.tokens.height.button, function()
		if selected then
			E:ResetMover(selected.name)
			E:SelectMover(selected)
		end
	end, L["Reset"], L["Back to its layout position (also Shift-right-click on the frame)."])
	nudge.resetOne:SetPoint("TOPLEFT", body, "TOPLEFT", 12, -60)
	-- Hide / Unhide: the selected piece itself, saved in the profile (the
	-- same setting as the right-click Hide). "Hide this box" for the
	-- session is in the box's right-click menu.
	nudge.hide = Kit.Button(nudge, L["Hide"], 110, E.tokens.height.button, function()
		if selected and E.CanHide and E:CanHide(selected.name) then
			E:SetHidden(selected.name, not E:IsHidden(selected.name))
			if selected then E:SelectMover(selected) end
		end
	end, L["Hide"], L["Hide this frame. It stays hidden, also after a reload, until you show it again under Hidden in this menu's view list or on the Hidden boxes page."])
	nudge.hide:SetPoint("TOPLEFT", body, "TOPLEFT", 12, -86)
	nudge.undoLast = Kit.Button(nudge, L["Undo last"], 110, E.tokens.height.button, function() E:UndoLastMove() end,
		L["Undo last"], L["Take back your last change: a drag, a nudge, a typed position, an attach or a reset. Each click goes one step further back. Ctrl+Z does the same."])
	nudge.undoLast:SetPoint("TOPLEFT", body, "TOPLEFT", 12, -112)
	nudge.showHidden = Kit.Button(nudge, L["Show hidden"], 110, E.tokens.height.button, function() E:ShowHiddenMovers() end,
		L["Show hidden"], L["Bring back the boxes you hid with Hide this box in this move session."])
	nudge.showHidden:SetPoint("TOPLEFT", body, "TOPLEFT", 12, -138)

	-- Right column: lock and attach.
	local lock = CreateFrame("CheckButton", nil, nudge, "UICheckButtonTemplate")
	lock:SetSize(22, 22)
	lock:SetPoint("TOPRIGHT", body, "TOPRIGHT", -100, -61)
	lock.text = E:CreateText(lock, E.tokens.size.body, "LEFT")
	lock.text:SetPoint("LEFT", lock, "RIGHT", 2, 0)
	lock.text:SetText(L["Locked"])
	lock:SetScript("OnClick", function(b)
		if selected then E:SetMoverLocked(selected.name, b:GetChecked()) end
	end)
	E:SkinCheckBox(lock)
	Kit.Tooltip(lock, L["Locked"], L["A locked frame can't be dragged by accident. The arrows and the X and Y boxes still move it."])
	nudge.lock = lock
	-- The right-click lock, for every box at once, under the frame lock.
	local rightLock = CreateFrame("CheckButton", nil, nudge, "UICheckButtonTemplate")
	rightLock:SetSize(22, 22)
	rightLock:SetPoint("TOPRIGHT", body, "TOPRIGHT", -100, -86)
	rightLock.text = E:CreateText(rightLock, E.tokens.size.body, "LEFT")
	rightLock.text:SetPoint("LEFT", rightLock, "RIGHT", 2, 0)
	rightLock.text:SetText(L["Lock right-click"])
	rightLock:SetScript("OnClick", function(b) if E.SetRightClickLocked then E:SetRightClickLocked(b:GetChecked()) end end)
	E:SkinCheckBox(rightLock)
	Kit.Tooltip(rightLock, L["Lock right-click"], L["EldoUI's boxes ignore right-click, so nothing is hidden by accident. Unit and group frames always keep the game's own right-click menu. Boxes here in move mode keep their menu."])
	nudge.rightLock = rightLock
	nudge.attach = Kit.Button(nudge, L["Attach to"], 110, E.tokens.height.button, function(b)
		if not selected then return end
		if E:GetMoverLink(selected.name) then
			E:UnlinkMover(selected.name)
		else
			OpenAttachMenu(b)
		end
	end, L["Attach to"], L["Hang this frame below, above or beside another frame, so it follows when that frame moves. Dragging it or typing X or Y detaches it again."])
	nudge.attach:SetPoint("TOPRIGHT", body, "TOPRIGHT", -12, -112)
	nudge.size = Kit.Button(nudge, L["Match size"], 110, E.tokens.height.button, function(b) OpenSizeMenu(b) end,
		L["Match size"], L["Give this frame the width or height of another frame. It is saved in this frame's own size setting."])
	nudge.size:SetPoint("TOPRIGHT", body, "TOPRIGHT", -12, -138)

	-- Test frames: every module's samples at once.
	local test = CreateFrame("CheckButton", nil, nudge, "UICheckButtonTemplate")
	test:SetSize(22, 22)
	test:SetPoint("TOPLEFT", body, "TOPLEFT", 10, -166)
	test.text = E:CreateText(test, E.tokens.size.body, "LEFT")
	test.text:SetPoint("LEFT", test, "RIGHT", 2, 0)
	test.text:SetText(L["Show test frames"])
	test:SetScript("OnClick", function(b) E:SetMoveModeTest(b:GetChecked()) end)
	E:SkinCheckBox(test)
	-- Right of it: hide the boxes until clicked again, or peek while held.
	nudge.hideAll = Kit.Button(nudge, L["Hide boxes"], 96, E.tokens.height.button, function() E:SetMoveOverlayHidden(true) end,
		L["Hide boxes"], L["Hide every box, name, the grid and this panel to see the real UI with its test frames. A small bar brings them back."])
	nudge.hideAll:SetPoint("TOPRIGHT", body, "TOPRIGHT", -12, -165)
	nudge.peek = Kit.Button(nudge, L["Peek"], 70, E.tokens.height.button, function() end,
		L["Peek"], L["Hold the mouse button (or hold Ctrl) to see the real UI for as long as you hold it."])
	nudge.peek:SetPoint("RIGHT", nudge.hideAll, "LEFT", -6, 0)
	nudge.peek:HookScript("OnMouseDown", function() E:PeekMoveMode(true) end)
	nudge.peek:HookScript("OnMouseUp", function() E:PeekMoveMode(false) end)
	Kit.Tooltip(test, L["Show test frames"], L["Fill every frame with sample content at once: unit, boss, party and raid frames, cast bars, cooldown rows, timers, loot and alert toasts and the rest, so the whole layout can be judged. Frames with no sample of their own show a stand-in until they have something real to show. Windows that open on demand keep only their box. Everything goes away when you leave move mode or combat starts."])
	nudge.test = test

	-- Bottom row: snap, then the session buttons.
	local snap = CreateFrame("CheckButton", nil, nudge, "UICheckButtonTemplate")
	snap:SetSize(22, 22)
	snap:SetPoint("BOTTOMLEFT", 10, 9)
	snap.text = E:CreateText(snap, E.tokens.size.body, "LEFT")
	snap.text:SetPoint("LEFT", snap, "RIGHT", 2, 0)
	snap.text:SetText(L["Snap"])
	snap:SetScript("OnClick", function(b) E.db.general.snap = b:GetChecked() end)
	E:SkinCheckBox(snap)
	Kit.Tooltip(snap, L["Snap"], L["Frames snap to the grid, to each other's edges and centers, and to the screen center. Hold Alt while dragging to place freely."])
	nudge.snap = snap

	nudge.done = Kit.Button(nudge, L["Done"], 70, E.tokens.height.button, function() E:ToggleMoveMode() end,
		L["Done"], L["Keep the changes and leave move mode. Escape does the same."])
	nudge.done:SetPoint("BOTTOMRIGHT", -10, 8)
	Kit.SetButtonKind(nudge.done, "primary") -- the panel's one primary button
	nudge.resetAll = Kit.Button(nudge, L["Reset all"], 80, E.tokens.height.button, function()
		E:ConfirmResetMovers()
	end, L["Reset all"], L["Every frame back to where the current layout puts it. It asks first, and locked frames stay where they are."])
	nudge.resetAll:SetPoint("RIGHT", nudge.done, "LEFT", -6, 0)
	nudge.undo = Kit.Button(nudge, L["Undo changes"], 110, E.tokens.height.button, function() E:UndoMoveSession() end,
		L["Undo changes"], L["Put every frame back where it was when move mode started."])
	nudge.undo:SetPoint("RIGHT", nudge.resetAll, "LEFT", -6, 0)

	-- The setup strip: version, layout, skin, role and UI amount, above
	-- the bottom row, with a button that copies the full summary.
	nudge.copySetup = Kit.IconButton(nudge, 16, "copy", function() E:ShowMoveSetupCopy() end,
		L["Copy setup"], L["Shows your setup in full (version, layout, skin, role, UI amount, screen and text size, and which frames have no box right now) to copy into a bug report."])
	nudge.copySetup:SetPoint("BOTTOMRIGHT", -10, 38)
	-- Change layout: the same layout picker as the Layouts page (Core/Overview.lua).
	if E.ShowLayoutPicker then
		nudge.pickLayout = Kit.IconButton(nudge, 16, "chevron-down", function(self) E:ShowLayoutPicker(self) end,
			L["Change layout"], L["Pick another layout: the families, a legacy layout you still use, or one of My layouts. It asks first."])
		nudge.pickLayout:SetPoint("RIGHT", nudge.copySetup, "LEFT", -6, 0)
	end
	nudge.setup = Kit.Text(nudge, E.tokens.size.small, "LEFT", "secondary")
	nudge.setup:SetPoint("BOTTOMLEFT", 12, 38)
	nudge.setup:SetWidth(380 - 24 - (nudge.pickLayout and 44 or 22))
	nudge.setup:SetWordWrap(true)
end

-- Buttons that depend on the session and the filters.
function UpdatePanel()
	if not nudge then return end
	UpdateSetupStrip()
	nudge.undo:SetEnabled(E:MoveSessionChanged())
	nudge.undoLast:SetEnabled(#undoMoves > 0)
	local hidden = E:CountHiddenMovers()
	nudge.showHidden:SetShown(hidden > 0)
	nudge.showHidden:SetText(("%s (%d)"):format(L["Show hidden"], hidden))
	local viewName = view.mode == "combat" and L["Combat mode"] or view.mode == "hidden" and L["Hidden"] or L["All frames"]
	nudge.group:SetText(view.group and L[view.group] or viewName)
	nudge.test:SetChecked(testing ~= nil)
	nudge.size:SetShown(selected ~= nil and E:CanMatchMoverSize(selected.name))
	local hideable = selected ~= nil and E.CanHide ~= nil and E:CanHide(selected.name)
	local isHidden = hideable and E:IsHidden(selected.name)
	nudge.hide:SetText(isHidden and L["Unhide"] or L["Hide"])
	nudge.hide:SetEnabled(hideable and true or false)
	nudge.hide.kitTipTitle = hideable and (isHidden and L["Show %s"] or L["Hide %s"]):format(L[selected.title]) or L["Hide"]
	nudge.hide.kitTipText = hideable
		and (isHidden and L["Show this frame again."] or L["Hide this frame. It stays hidden, also after a reload, until you show it again under Hidden in this menu's view list or on the Hidden boxes page."])
		or L["Unit frames, group frames, action bars, chat and windows keep their own switches on their pages."]
	nudge.rightLock:SetChecked(E.IsRightClickLocked ~= nil and E:IsRightClickLocked())
	if nudge.search:GetText() ~= view.search and view.search == "" then
		nudge.settingSearch = true
		nudge.search:SetText("")
		nudge.settingSearch = false
		nudge.search.hint:Show()
	end
end

function E:SelectMover(mover)
	if not nudge then return end
	-- A frame picked on a shared spot answers the mouse there from now on.
	local group = mover and shared[mover]
	local regroup = group and group[1] ~= mover
	if group then sharedPick[group.spot] = mover.name end
	local previous = selected
	if selected and selected.overlay then
		selected.overlay:SetBackdropBorderColor(unpack(self.media.borderColor))
	end
	selected = mover
	-- The tab of a box with test content follows the selection.
	if previous and previous ~= mover and previous.overlay:IsShown() then PaintOverlayText(previous) end
	if mover and mover.overlay:IsShown() then PaintOverlayText(mover) end
	local on = mover and true or false
	for _, button in ipairs({ nudge.resetOne, nudge.lock, nudge.attach }) do
		button:SetEnabled(on)
	end
	if mover then
		mover.overlay:SetBackdropBorderColor(unpack(self.media.accentColor))
		local point, x, y = MeasureSelected()
		nudge.title:SetText(point and ("%s %s(%s)|r"):format(L[mover.title], E:TokenHex(E.tokens.text.secondary),
			L[POINT_LABEL[point] or point]) or L[mover.title])
		nudge.x:SetText(x and tostring(x) or "")
		nudge.y:SetText(y and tostring(y) or "")
		nudge.lock:SetChecked(self:IsMoverLocked(mover.name))
		local to, side = self:GetMoverLink(mover.name)
		local target = to and self.movers[to]
		if target then
			nudge.status:SetText(L["Attached to %s (%s)"]:format(L[target.title], L[LINK_LABEL[side]]))
			nudge.attach:SetText(L["Detach"])
		else
			nudge.status:SetText(L[self:GetMoverGroup(mover)])
			nudge.attach:SetText(L["Attach to"])
		end
	else
		nudge.title:SetText(L["Click a frame to nudge it"])
		nudge.status:SetText(L["Drag frames to move them. Ctrl+Z takes back the last change, Undo changes puts everything back."])
		nudge.x:SetText("")
		nudge.y:SetText("")
		nudge.lock:SetChecked(false)
		nudge.attach:SetText(L["Attach to"])
	end
	LayoutNudge()
	UpdatePanel()
	if regroup then ShareBoxes() end
end

function E:ShowNudge(state)
	if state and not nudge then CreateNudge() end
	if not nudge then return end
	nudge:SetShown(state and not overlayHidden)
	ApplyOverlayLook()
	if state then
		nudge.grid:SetText(tostring(self.db.general.gridSize))
		nudge.snap:SetChecked(self.db.general.snap)
		self:SelectMover(selected)
	end
end

-- Dock the move panel beside `anchor` (Blizzard's Edit Mode window), to
-- its left ("RIGHT" docks it on the anchor's right), or put it back at the
-- top of the screen (nil).
function E:DockMovePanel(anchor, side)
	if not nudge then return end
	-- Docked, Escape belongs to Edit Mode: it closes that window, and move
	-- mode ends with it.
	nudge.docked = anchor ~= nil
	nudge:ClearAllPoints()
	if anchor and side == "RIGHT" then
		nudge:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 6, 0)
	elseif anchor then
		nudge:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -6, 0)
	else
		nudge:SetPoint("TOP", 0, -60)
	end
end

---------------------------------------------------------------------------
-- Hide boxes and peek: the real UI, test frames included, without leaving
-- move mode. Hidden boxes take no clicks; a small bar brings them back.
-- Peek lasts while the panel's Peek button or Ctrl is held.
---------------------------------------------------------------------------
local bar -- the small "boxes hidden" bar
local overlayListeners = {}

-- fn(gone): called whenever the boxes go away or come back (Edit Mode's
-- EldoUI panel goes with them).
function E:RegisterMoveOverlayListener(fn)
	if type(fn) == "function" then overlayListeners[#overlayListeners + 1] = fn end
end

local function CreateBar()
	local Kit = E.UIKit
	bar = CreateFrame("Frame", "EldoUI_MoveBar", UIParent)
	bar:SetFrameStrata("FULLSCREEN_DIALOG")
	bar:SetClampedToScreen(true)
	bar:EnableMouse(true)
	E:SetPanelTemplate(bar, false, 1)
	bar.text = Kit.Text(bar, E.tokens.size.small, "LEFT", "secondary")
	bar.text:SetPoint("LEFT", 12, 0)
	bar.text:SetText(L["Move mode: boxes hidden"])
	bar.show = Kit.Button(bar, L["Show boxes"], 100, E.tokens.height.button, function() E:SetMoveOverlayHidden(false) end,
		L["Show boxes"], L["Bring back the boxes, the grid and the move panel."])
	bar.show:SetPoint("RIGHT", -8, 0)
	Kit.SetButtonKind(bar.show, "primary")
	bar:SetSize(math.ceil((bar.text:GetStringWidth() or 150) + 12 + 12 + 100 + 8), E.tokens.height.button + 16)
	-- Escape brings the boxes back first; the next one leaves move mode.
	bar.keys = Kit.KeyHandler(bar, function(_, key)
		if key ~= "ESCAPE" then return false end
		E:SetMoveOverlayHidden(false)
		return true
	end)
	bar:Hide()
end

function ApplyOverlayLook()
	local gone = moveMode and (overlayHidden or peeking)
	for _, mover in pairs(E.movers) do
		mover.overlay:SetAlpha(OverlayAlpha())
		if gone then
			mover:EnableMouse(false)
			mover.overlay.hover:Hide()
		elseif moveMode then
			mover:EnableMouse(mover.overlay:IsShown())
		end
	end
	if grid then grid:SetAlpha(gone and 0 or 1) end
	if moveMode and E.ShowSafeArea then E:ShowSafeArea(not gone) end
	if gone then E:UpdateMoverGuides(nil) end
	if nudge then
		nudge:SetAlpha(peeking and 0 or 1)
		if moveMode then nudge:SetShown(not overlayHidden) end
	end
	if moveMode and overlayHidden and not bar then CreateBar() end
	if bar then
		bar:ClearAllPoints()
		if nudge then bar:SetPoint("TOP", nudge, "TOP", 0, 0) else bar:SetPoint("TOP", 0, -60) end
		bar:SetShown(moveMode and overlayHidden)
		bar:SetAlpha(peeking and 0 or 1)
	end
	for _, fn in ipairs(overlayListeners) do
		local ok, err = pcall(fn, gone)
		if not ok then geterrorhandler()(err) end
	end
end

-- Are the boxes away right now (hidden or peeking)?
function E:IsMoveOverlayHidden()
	return moveMode and (overlayHidden or peeking) or false
end

-- state true: hide the boxes, grid and panels until called with false.
function E:SetMoveOverlayHidden(state)
	if not moveMode then return false end
	overlayHidden = state and true or false
	if overlayHidden and GameTooltip:IsOwned(nudge or UIParent) then GameTooltip:Hide() end
	ApplyOverlayLook()
	return true
end

-- Peek: state true while held, false on release. Never while dragging.
function E:PeekMoveMode(state)
	state = state and moveMode or false
	if state then
		for _, mover in pairs(self.movers) do
			if mover.dragging then return false end
		end
	end
	if peeking == state then return peeking end
	peeking = state
	ApplyOverlayLook()
	return peeking
end

-- Hold Ctrl to peek, unless a text box has the keyboard.
E:RegisterEvent("MODIFIER_STATE_CHANGED", function(_, _, key, down)
	if not moveMode or (key ~= "LCTRL" and key ~= "RCTRL") then return end
	if down == 1 then
		local focus = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
		if focus then return end
		E:PeekMoveMode(true)
	elseif not IsControlKeyDown() then
		E:PeekMoveMode(false)
	end
end, {})

-- The General page's Move mode options changed: redraw what is on screen.
function E:RefreshMoveModeLook()
	if not moveMode then return end
	self:ShowGrid(true)
	if nudge then
		nudge.grid:SetText(tostring(self.db.general.gridSize))
		nudge.snap:SetChecked(self.db.general.snap)
	end
end
