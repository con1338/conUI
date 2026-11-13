-- Public world-map queries and parent-normalized rectangle math.
-- Native answers are read on demand; no static region axes or phase is assumed.
-- MapDocumentation and MapUtil define the rectangle's left/right/top/bottom
-- ordering. World vectors keep the API's coordinate order unchanged.
local _, E = ...
local M = E:GetModule("Maps")
local Secret, Call = E.Secret, E.PlainCallAll
local ReadEnabled = E.ModuleEnabledValue
local WORLD = "world-map-quest-log"

local function Plain(value)
	return not Secret(value) and type(value) == "table" and type(getmetatable(value)) == "nil"
end

local function Number(value)
	return not Secret(value) and type(value) == "number" and value == value
		and value > -math.huge and value < math.huge
end

local function ID(value, zero)
	return Number(value) and value >= (zero and 0 or 1) and value % 1 == 0
end

local function Same(a, b)
	return not Secret(a) and not Secret(b) and a == b
end

-- Only raw owned context is inspected here. In particular, acquiring a
-- metatable cannot turn an ownership check into a foreign lookup callback.
local function Context(method, vector)
	local modules, profile = rawget(E, "modules"), rawget(E, "db")
	if not Plain(modules) or not Plain(profile) or not Same(rawget(modules, "Maps"), M)
		or not Same(rawget(M, "name"), "Maps") or not Same(rawget(M, "active"), true) then return end
	local settings, moduleDB = rawget(profile, "modules"), rawget(M, "db")
	local switches, elements = rawget(profile, "blizzard"), rawget(E, "blizzardElements")
	if not Plain(settings) or Secret(moduleDB) or type(moduleDB) ~= "table"
		or not Same(rawget(settings, "Maps"), moduleDB) or not Plain(switches) or not Plain(elements)
		or Secret(ReadEnabled) or type(ReadEnabled) ~= "function" or not Same(rawget(E, "ModuleEnabledValue"), ReadEnabled) then return end
	-- The database owner authenticates its own redirected enabled channel.
	-- No settings __index is called here, including on the plain path.
	if not Same(ReadEnabled(E, M), true) then return end
	local world, state, element = rawget(moduleDB, "worldMap"), rawget(switches, WORLD), rawget(elements, WORLD)
	if not Plain(world) or not Plain(state) or not Plain(element) then return end
	local allowed = rawget(element, "allowed")
	if not Plain(allowed) or not Same(rawget(allowed, "improve"), true)
		or not Same(rawget(state, "enabled"), true) or not Same(rawget(state, "improve"), true) then return end
	local api = rawget(_G, "C_Map")
	local fn = Plain(api) and rawget(api, method)
	local forever, permits, readState = rawget(E, "IsForeverClient"), rawget(E, "BlizzardAllowed"), rawget(E, "BlizzardState")
	local project, camelot, named = rawget(_G, "WOW_PROJECT_ID"), rawget(_G, "WOW_PROJECT_CAMELOT"), rawget(_G, "WOW_PROJECT_FOREVER")
	if not ID(project) or (type(camelot) ~= "nil" and not ID(camelot))
		or (type(named) ~= "nil" and not ID(named)) or Secret(fn) or type(fn) ~= "function"
		or Secret(forever) or type(forever) ~= "function" or Secret(permits) or type(permits) ~= "function"
		or Secret(readState) or type(readState) ~= "function" then return end
	local create = vector and rawget(_G, "CreateVector2D") or false
	if vector and (Secret(create) or type(create) ~= "function") then return end
	local name = rawget(E, "profileName")
	if Secret(name) or type(name) ~= "string" then return end
	return { modules = modules, profile = profile, settings = settings, moduleDB = moduleDB, world = world,
		switches = switches, elements = elements, state = state, element = element, allowed = allowed,
		api = api, fn = fn, forever = forever, permits = permits, readState = readState, project = project,
		camelot = camelot, named = named, create = create, name = name, readEnabled = ReadEnabled,
		private = rawget(E, "private") }
end

local function Current(context, method, vector)
	local now = Context(method, vector)
	if not now then return false end
	for key, value in pairs(context) do
		if not Same(value, now[key]) then return false end
	end
	-- The optional project constants may be absent from the captured table.
	return Same(context.camelot, now.camelot) and Same(context.named, now.named)
end

local function Admit(method, vector)
	local context = Context(method, vector)
	if not context then return end
	local forever = Call(context.forever, E)
	if not Same(forever, true) or not Current(context, method, vector) then return end
	local allowed = Call(context.permits, E, WORLD, "improve")
	if not Same(allowed, true) or not Current(context, method, vector) then return end
	return context
end

local function XY(value)
	if not Plain(value) then return end
	local getter = rawget(value, "GetXY")
	if Secret(getter) or type(getter) ~= "function" then return end
	local x, y = Call(getter, value)
	if Number(x) and Number(y) and Same(rawget(value, "GetXY"), getter) then return x, y end
end

local function Vector(context, method, x, y)
	local value = Call(context.create, x, y)
	if not Current(context, method, true) then return end
	local vx, vy = XY(value)
	if Same(vx, x) and Same(vy, y) and Current(context, method, true) then return value end
end

function M:WorldMapRect(uiMapID, parentUiMapID)
	if not Same(self, M) or not ID(uiMapID) or not ID(parentUiMapID) then return nil, "input" end
	local context = Admit("GetMapRectOnMap")
	if not context then return nil, "context" end
	local left, right, top, bottom = Call(context.fn, uiMapID, parentUiMapID)
	if not Current(context, "GetMapRectOnMap") then return nil, "context" end
	if not Number(left) or not Number(right) or not Number(top) or not Number(bottom)
		or right <= left or bottom <= top or not Number(right - left) or not Number(bottom - top) then return nil, "rectangle" end
	return { uiMapID = uiMapID, parentUiMapID = parentUiMapID, left = left, right = right, top = top, bottom = bottom }
end

function M:WorldMapSize(uiMapID)
	if not Same(self, M) or not ID(uiMapID) then return nil, "input" end
	local context = Admit("GetMapWorldSize")
	if not context then return nil, "context" end
	local width, height = Call(context.fn, uiMapID)
	if not Current(context, "GetMapWorldSize") then return nil, "context" end
	if not Number(width) or not Number(height) or width <= 0 or height <= 0 then return nil, "size" end
	return { uiMapID = uiMapID, width = width, height = height }
end

function M:WorldFromMap(uiMapID, x, y)
	if not Same(self, M) or not ID(uiMapID) or not Number(x) or not Number(y)
		or x < 0 or x > 1 or y < 0 or y > 1 then return nil, "input" end
	local method = "GetWorldPosFromMapPos"
	local context = Admit(method, true)
	if not context then return nil, "context" end
	local input = Vector(context, method, x, y)
	if not input then return nil, "vector" end
	local continent, position = Call(context.fn, uiMapID, input)
	if not Current(context, method, true) then return nil, "context" end
	local wx, wy = XY(position)
	if not ID(continent, true) or not Number(wx) or not Number(wy) then return nil, "position" end
	if not Current(context, method, true) then return nil, "context" end
	return { continentID = continent, x = wx, y = wy }
end

function M:MapFromWorld(continentID, x, y, uiMapID)
	if not Same(self, M) or not ID(continentID, true) or not Number(x) or not Number(y) or not ID(uiMapID) then return nil, "input" end
	local method = "GetMapPosFromWorldPos"
	local context = Admit(method, true)
	if not context then return nil, "context" end
	local input = Vector(context, method, x, y)
	if not input then return nil, "vector" end
	local returnedMap, position = Call(context.fn, continentID, input, uiMapID)
	if not Current(context, method, true) then return nil, "context" end
	local u, v = XY(position)
	if not Same(returnedMap, uiMapID) or not Number(u) or not Number(v) then return nil, "position" end
	if not Current(context, method, true) then return nil, "context" end
	return { uiMapID = uiMapID, x = u, y = v }
end

local function Dense(values, limit)
	if not Plain(values) then return end
	local count, maximum = 0, 0
	for key in pairs(values) do
		if not ID(key) or key > limit then return end
		count, maximum = count + 1, math.max(maximum, key)
	end
	if count == maximum then return count end
end

-- MapDocumentation: native child IDs and Lua (one-based) art layers.
-- These queries do not derive a phase, rectangle or art choice from DB2 rows.
function M:WorldMapChildren(parentUiMapID)
	if not Same(self, M) or not ID(parentUiMapID) then return nil, "input" end
	local method = "GetMapChildrenInfo"
	local context = Admit(method)
	if not context then return nil, "context" end
	local children = Call(context.fn, parentUiMapID, nil, false)
	if not Current(context, method) then return nil, "context" end
	local count = Dense(children, 64)
	if not count then return nil, "children" end
	local result, seen = {}, {}
	for index = 1, count do
		local child = children[index]
		if not Plain(child) then return nil, "children" end
		local id, parent = rawget(child, "mapID"), rawget(child, "parentMapID")
		if not ID(id) or not Same(parent, parentUiMapID) or seen[id] then return nil, "children" end
		seen[id], result[index] = true, id
	end
	return result
end

function M:WorldMapTiles(uiMapID, parentUiMapID, layerIndex)
	if not Same(self, M) or not ID(uiMapID) or not ID(parentUiMapID)
		or not ID(layerIndex) or layerIndex > 8 then return nil, "input" end
	local methods = { "GetMapRectOnMap", "GetMapArtID", "GetMapArtLayers", "GetMapArtLayerTextures" }
	local contexts = {}
	for index, method in ipairs(methods) do
		contexts[index] = Admit(method)
		if not contexts[index] then return nil, "context" end
	end
	local function current()
		for index, method in ipairs(methods) do
			if not Current(contexts[index], method) then return false end
		end
		return true
	end
	local function query(index, ...)
		if not current() then return end
		return Call(contexts[index].fn, ...)
	end
	local left, right, top, bottom = query(1, uiMapID, parentUiMapID)
	if not Number(left) or not Number(right) or not Number(top) or not Number(bottom)
		or right <= left or bottom <= top or not Number(right - left) or not Number(bottom - top) then return nil, "rectangle" end
	local artID = query(2, uiMapID)
	if not ID(artID) then return nil, "art" end
	local parentArtID = query(2, parentUiMapID)
	local parentLayers = query(3, parentUiMapID)
	if not ID(parentArtID) or not Dense(parentLayers, 8) or not Plain(parentLayers[1]) then return nil, "parent" end
	local parentWidth, parentHeight = rawget(parentLayers[1], "layerWidth"), rawget(parentLayers[1], "layerHeight")
	if not Number(parentWidth) or not Number(parentHeight) or parentWidth <= 0 or parentHeight <= 0 then return nil, "parent" end
	local layers = query(3, uiMapID)
	local count = Dense(layers, 8)
	if not count or layerIndex > count or not Plain(layers[layerIndex]) then return nil, "layer" end
	local layer, source = {}, layers[layerIndex]
	for _, key in ipairs({ "layerWidth", "layerHeight", "tileWidth", "tileHeight", "minScale", "maxScale", "additionalZoomSteps" }) do
		local value = rawget(source, key)
		if not Number(value) or value < 0 then return nil, "layer" end
		layer[key] = value
	end
	if layer.layerWidth <= 0 or layer.layerHeight <= 0 or layer.tileWidth <= 0 or layer.tileHeight <= 0
		or layer.minScale <= 0 or layer.maxScale < layer.minScale
		or layer.additionalZoomSteps % 1 ~= 0 then return nil, "layer" end
	local columns, rows = math.ceil(layer.layerWidth / layer.tileWidth), math.ceil(layer.layerHeight / layer.tileHeight)
	if not Number(columns * rows) or columns * rows > 512 then return nil, "capacity" end
	local textures = query(4, uiMapID, layerIndex)
	if Dense(textures, 512) ~= columns * rows then return nil, "textures" end
	local copy = {}
	for index = 1, columns * rows do
		if not ID(textures[index]) then return nil, "textures" end
		copy[index] = textures[index]
	end
	if not Same(query(2, uiMapID), artID) or not Same(query(2, parentUiMapID), parentArtID)
		or not current() then return nil, "context" end
	return { uiMapID = uiMapID, parentUiMapID = parentUiMapID, artID = artID, layerIndex = layerIndex,
		left = left, right = right, top = top, bottom = bottom, layer = layer, textures = copy,
		parentArtID = parentArtID, parentWidth = parentWidth, parentHeight = parentHeight,
		-- Read-only context custody; this does not promise the phase cannot
		-- change between native refresh events or authenticate a modeled API.
		current = current }
end

local function Rect(rect)
	if not Plain(rect) then return end
	local left, right, top, bottom = rawget(rect, "left"), rawget(rect, "right"), rawget(rect, "top"), rawget(rect, "bottom")
	if Number(left) and Number(right) and Number(top) and Number(bottom) and right > left and bottom > top
		and Number(right - left) and Number(bottom - top) then return left, right, top, bottom end
end

-- These functions only transform the caller's rectangle; they do not check
-- its origin, the current phase, the game's art, or whether it can be drawn.
function M.ProjectMapRect(rect, x, y)
	local left, right, top, bottom = Rect(rect)
	if not left or not Number(x) or not Number(y) then return end
	local u, v = left + x * (right - left), top + y * (bottom - top)
	if Number(u) and Number(v) then return u, v end
end

function M.UnprojectMapRect(rect, u, v)
	local left, right, top, bottom = Rect(rect)
	if not left or not Number(u) or not Number(v) then return end
	local x, y = (u - left) / (right - left), (v - top) / (bottom - top)
	if Number(x) and Number(y) then return x, y end
end

-- A complete public quest query bounds this refresh's allocation; it is not a
-- client quest limit. Native providers still perform their own original query.
function M:WorldQuestSnapshot(uiMapID)
	if not Same(self, M) or not ID(uiMapID) then return nil, "input" end
	local context = Admit("GetMapInfo")
	if not context then return nil, "context" end
	local queries, sources = {}, {}
	local specs = {
		{ false, "GetQuestsOnMapCached" }, { false, "QuestMapFrame_GetFocusedQuestID" },
		{ "C_SuperTrack", "GetSuperTrackedQuestID" }, { "C_QuestLog", "GetNextWaypointForMap" },
	}
	for index, spec in ipairs(specs) do
		local namespace = spec[1] and rawget(_G, spec[1]) or _G
		local fn = (not spec[1] or Plain(namespace)) and rawget(namespace, spec[2])
		if Secret(fn) or type(fn) ~= "function" then return nil, "source" end
		sources[index], queries[index] = namespace, fn
	end
	local function owned()
		if not Current(context, "GetMapInfo") then return false end
		for index, spec in ipairs(specs) do
			local namespace = spec[1] and rawget(_G, spec[1]) or _G
			if not Same(namespace, sources[index]) or (spec[1] and not Plain(namespace))
				or not Same(rawget(namespace, spec[2]), queries[index]) then return false end
		end
		return true
	end
	-- Unlike PlainCallAll, this boundary retains protected-call success and
	-- exact return arity. A thrown/opaque/secret result is never absence.
	local function collect(ok, ...)
		if not ok then return end
		local count = select("#", ...)
		for index = 1, count do if Secret((select(index, ...))) then return end end
		return { n = count, ... }
	end
	local function query(index, ...)
		if not owned() then return end
		local results = collect(pcall(queries[index], ...))
		if not results or not owned() then return end
		return results
	end
	local function read()
		if not owned() then return end
		local rowsResult = query(1, uiMapID)
		if not rowsResult or rowsResult.n > 1 then return end
		local rows = rowsResult[1]
		local absent = type(rows) == "nil"
		if not absent and not Plain(rows) then return end
		local result, count = {}, 0
		-- MayReturnNothing is distinct from an observed empty array. Both take
		-- the original provider's no-row branch, without fabricated records.
		for index, row in pairs(rows or {}) do
			if not ID(index) or not Plain(row) then return end
			local id, x, y, indicator = rawget(row, "questID"), rawget(row, "x"), rawget(row, "y"), rawget(row, "isMapIndicatorQuest")
			if not ID(id) or not Number(x) or not Number(y) or x < 0 or x > 1 or y < 0 or y > 1
				or Secret(indicator) or type(indicator) ~= "boolean" then return end
			result[index], count = { id, x, y, indicator }, count + 1
		end
		for index = 1, count do if not result[index] then return end end
		local focusedResult = query(2)
		if not focusedResult or focusedResult.n > 1 then return end
		local focused = focusedResult[1]
		if type(focused) ~= "nil" and not ID(focused, true) then return end
		local trackedResult = query(3)
		if not trackedResult or trackedResult.n > 1 then return end
		local tracked = trackedResult[1]
		if type(tracked) ~= "nil" and not ID(tracked, true) then return end
		local candidate = focused or tracked
		local x, y, waypointArity
		if candidate then
			local waypoint = query(4, candidate, uiMapID)
			if not waypoint or waypoint.n > 2 then return end
			x, y, waypointArity = waypoint[1], waypoint[2], waypoint.n
			if (type(x) ~= "nil" and not Number(x)) or (type(y) ~= "nil" and not Number(y)) then return end
			if (type(x) == "nil") ~= (type(y) == "nil") then return end
			if x and y and (x < 0 or x > 1 or y < 0 or y > 1) then return end
		end
		if not owned() then return end
		return { rows = result, absent = absent, count = count, focused = focused, tracked = tracked, x = x, y = y,
			rowsArity = rowsResult.n, focusedArity = focusedResult.n, trackedArity = trackedResult.n, waypointArity = waypointArity,
			capacity = count + (x and y and 1 or 0) }
	end
	local snapshot = read()
	if not snapshot then return nil, "query" end
	local function current()
		local now = read()
		if not now or not Same(snapshot.rowsArity, now.rowsArity) or not Same(snapshot.focusedArity, now.focusedArity)
			or not Same(snapshot.trackedArity, now.trackedArity) or not Same(snapshot.waypointArity, now.waypointArity)
			or not Same(snapshot.absent, now.absent) or not Same(snapshot.count, now.count) or not Same(snapshot.focused, now.focused)
			or not Same(snapshot.tracked, now.tracked) or not Same(snapshot.x, now.x) or not Same(snapshot.y, now.y) then return false end
		for index, row in ipairs(snapshot.rows) do
			for key = 1, 4 do if not Same(row[key], now.rows[index][key]) then return false end end
		end
		return true
	end
	return { uiMapID = uiMapID, capacity = snapshot.capacity, count = snapshot.count, current = current, owned = owned,
		row = function(index)
			if not ID(index) or index > snapshot.count then return end
			local row = snapshot.rows[index]
			return row[1], row[2], row[3], row[4]
		end,
		waypoint = function() return snapshot.focused or snapshot.tracked, snapshot.x, snapshot.y end }
end
