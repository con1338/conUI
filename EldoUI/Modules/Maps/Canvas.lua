-- An owned viewport foundation. Player activation and native pin integration
-- are deliberately separate; loading this file creates no frame or query.
local _, E = ...
local M = E:GetModule("Maps")
local Secret, Call = E.Secret, E.PlainCallAll
local create, children, tiles = CreateFrame, M.WorldMapChildren, M.WorldMapTiles
local generation = E.GetApplyGeneration
local project, refreshPins = M.ProjectMapRect, E.RefreshAllMapPins
local observe = M.ObserveWorldCanvasHost
local pinView, refreshHost
local view, busy
local MIN_ZOOM, MAX_ZOOM = .25, 32
local releaseQuestPins, redrawQuestPins

local function Number(value)
	return not Secret(value) and type(value) == "number" and value == value
		and value > -math.huge and value < math.huge
end

local function Same(a, b)
	return not Secret(a) and not Secret(b) and a == b
end

local function Functions(object, names)
	if Secret(object) or type(object) ~= "table" then return end
	local methods = {}
	for _, key in ipairs(names) do
		local value = Call(function() return object[key] end)
		if Secret(value) or type(value) ~= "function" then return end
		methods[key] = value
	end
	return methods
end

local function Methods(object, methods)
	for key, fn in pairs(methods) do
		if not Same(Call(function() return object[key] end), fn) then return false end
	end
	return true
end

local function Sources(current)
	if not Same(M.WorldMapChildren, children) or not Same(M.WorldMapTiles, tiles)
		or not Same(CreateFrame, create) or not Same(M.active, true)
		or not Same(M.PanWorldCanvas, current.pan) or not Same(M.ZoomWorldCanvas, current.zoomMethod)
		or not Same(M.ProjectMapRect, project)
		or not Same(M.ObserveWorldCanvasHost, observe) or not Same(M.WorldCanvasPinView, pinView)
		or not Same(M.RefreshWorldCanvasHost, refreshHost)
		or not Same(E.GetApplyGeneration, generation) or type(generation) ~= "function"
		or not Same(Call(generation, E, "profile"), current.generation) then return false end
	if current.mountCurrent and not Same(Call(current.mountCurrent), true) then return false end
	for _, map in ipairs(current.maps) do
		if not Same(map.current(), true) then return false end
	end
	return Same(E.GetApplyGeneration, generation)
end

local function Current(current, closed)
	if current.failed then return false end
	if view ~= current or not Sources(current) or not Methods(current.host, current.hostMethods) then return false end
	if not closed and not current.open then return false end
	local host, methods = current.host, current.hostMethods
	local parent = Call(methods.GetParent, host)
	local width, height = Call(methods.GetSize, host)
	local forbidden, protected = Call(methods.IsForbidden, host), Call(methods.IsProtected, host)
	if not Same(parent, current.parent) or not Same(width, current.width) or not Same(height, current.height)
		or not Same(forbidden, false) or not Same(protected, false)
		or not Same(Call(methods.IsVisible, host), true) then return false end
	if not Methods(current.frame, current.frameMethods) or not Methods(current.child, current.childMethods)
		or not Same(Call(current.frameMethods.GetParent, current.frame), host)
		or not Same(Call(current.childMethods.GetParent, current.child), current.frame) then return false end
	return Sources(current) and Methods(host, methods)
end

local function Owned(current)
	return Methods(current.frame, current.frameMethods) and Methods(current.child, current.childMethods)
		and Same(Call(current.frameMethods.GetParent, current.frame), current.host)
		and Same(Call(current.childMethods.GetParent, current.child), current.frame)
end

local function TextureParent(current, item)
	if current.pool[item.index] ~= item or item.transferred or not item.parentGetter then return false end
	local getter = Call(function() return item.object.GetParent end)
	if not Same(getter, item.parentGetter) then return false end
	local parent = Call(item.parentGetter, item.object)
	if not Same(parent, current.child) then
		item.transferred = true
		return false
	end
	return Same(Call(function() return item.object.GetParent end), item.parentGetter)
end

local function TextureOwned(current, item)
	return item.methods and TextureParent(current, item) and Methods(item.object, item.methods)
		and TextureParent(current, item)
end

local function PoolOwned(current)
	for _, item in ipairs(current.pool) do
		if not TextureOwned(current, item) then return false end
	end
	return true
end

local function AdmitTexture(current, item)
	if not Current(current) then return false end
	if not item.parentGetter then
		local parent = Functions(item.object, { "GetParent" })
		if not parent then return false end
		item.parentGetter = parent.GetParent
	end
	if not TextureParent(current, item) then return false end
	if not item.methods then
		local methods = Functions(item.object, { "GetParent", "SetTexture", "SetTexCoord", "ClearAllPoints", "SetPoint", "SetSize", "Show", "Hide" })
		if not methods or not Same(methods.GetParent, item.parentGetter) then return false end
		item.methods = methods
	end
	return Current(current) and TextureOwned(current, item) and Current(current)
end

local function TextureSet(current, item, key, ...)
	if not Current(current) or not TextureOwned(current, item) or not Current(current) then return false end
	local object, methods = item.object, item.methods
	local ok = pcall(methods[key], object, ...)
	return ok and Same(item.object, object) and item.methods == methods
		and Current(current) and TextureOwned(current, item) and Current(current)
end

local function Release()
	local current = view
	if not current then return true end
	if current.failed then return false end
	-- Cleanup never calls a replacement method or reparents a transferred frame.
	if not Owned(current) then return false end
	if releaseQuestPins and not releaseQuestPins(current) then return false end
	local poolOwned = PoolOwned(current)
	current.drag, current.open = nil, false
	local stopped = pcall(current.frameMethods.SetScript, current.frame, "OnUpdate", nil)
	if not Owned(current) then return false end
	local hidden = pcall(current.frameMethods.Hide, current.frame)
	return stopped and hidden and Owned(current) and PoolOwned(current) and poolOwned
end

local function Set(current, object, methods, key, ...)
	if not Current(current) or not Methods(object, methods) then return false end
	local ok = pcall(methods[key], object, ...)
	return ok and Current(current) and Methods(object, methods)
end

local function Camera(current, u, v)
	return current.offsetX + (u - current.left) * current.basisWidth * current.zoom,
		current.offsetY + (v - current.top) * current.basisHeight * current.zoom
end

local function RefreshPins()
	if redrawQuestPins and view and view.open and not redrawQuestPins(view) then
		view.refused = true
		return false
	end
	if not Secret(refreshPins) and type(refreshPins) == "function" and Same(E.RefreshAllMapPins, refreshPins) then
		Call(refreshPins, E)
	end
	return true
end

local function Paint(current)
	if not Current(current) then return false end
	local index = 0
	for _, map in ipairs(current.maps) do
		local layer = map.layer
		local columns = math.ceil(layer.layerWidth / layer.tileWidth)
		local rows = math.ceil(layer.layerHeight / layer.tileHeight)
		for row = 1, rows do
			for column = 1, columns do
				index = index + 1
				local item = current.pool[index]
				if not item then
					local texture = Call(current.childMethods.CreateTexture, current.child, nil, "BACKGROUND")
					-- Retain the exact result before optional capability reads. A
					-- failed admission can retry this slot, never allocate an orphan.
					item = { object = texture, index = index }
					current.pool[index] = item
				end
				if not AdmitTexture(current, item) then return false end
				local x = (column - 1) * layer.tileWidth
				local y = (row - 1) * layer.tileHeight
				local w, h = math.min(layer.tileWidth, layer.layerWidth - x), math.min(layer.tileHeight, layer.layerHeight - y)
				local u, v = map.left + x / layer.layerWidth * (map.right - map.left), map.top + y / layer.layerHeight * (map.bottom - map.top)
				local px, py = Camera(current, u, v)
				local pw = w / layer.layerWidth * (map.right - map.left) * current.basisWidth * current.zoom
				local ph = h / layer.layerHeight * (map.bottom - map.top) * current.basisHeight * current.zoom
				if not Number(px) or not Number(py) or not Number(pw) or not Number(ph) then return false end
				for _, command in ipairs({ { "SetTexture", map.textures[(row - 1) * columns + column], nil, nil, "TRILINEAR" },
					{ "SetTexCoord", 0, w / layer.tileWidth, 0, h / layer.tileHeight }, { "ClearAllPoints" },
					{ "SetPoint", "TOPLEFT", current.child, "TOPLEFT", px, -py }, { "SetSize", pw, ph }, { "Show" } }) do
					if not TextureSet(current, item, command[1], unpack(command, 2, command[1] == "SetTexture" and 5 or #command)) then return false end
				end
			end
		end
	end
	for i = index + 1, #current.pool do
		local item = current.pool[i]
		if not TextureSet(current, item, "Hide") then return false end
	end
	current.tileCount = index
	return Set(current, current.frame, current.frameMethods, "Show")
end

local function Operation(fn)
	if busy then return nil, "busy" end
	busy = true
	local ok, answer = pcall(fn)
	if not ok or not answer then
		if view then view.refused = true end
		pcall(Release)
		busy = nil
		return nil, "unavailable"
	end
	local current, opened = view, view and view.opened
	if not RefreshPins() then
		pcall(Release)
		busy = nil
		return nil, "presentation"
	end
	busy = nil
	if not current or view ~= current or not Same(current.opened, opened) or not Sources(current) then
		if view == current and current then current.refused = true pcall(Release) end
		return nil, "context"
	end
	return answer
end

local function Cursor(current)
	if not Current(current) or not Same(GetCursorPosition, current.cursor) then return end
	local x, y = Call(current.cursor)
	local scale = Call(current.hostMethods.GetEffectiveScale, current.host)
	local left, top = Call(current.hostMethods.GetLeft, current.host), Call(current.hostMethods.GetTop, current.host)
	if not Number(x) or not Number(y) or not Number(scale) or scale <= 0
		or not Number(left) or not Number(top) or not Current(current) then return end
	return (x / scale - left) / current.width, (top - y / scale) / current.height
end

local function Input(current)
	local function wheel(_, delta)
		if not Number(delta) then return end
		local x, y = Cursor(current)
		if x then current.zoomMethod(M, 2 ^ (delta / 4), x, y) end
	end
	local function stop()
		if Current(current) then
			current.drag = nil
			current.frameMethods.SetScript(current.frame, "OnUpdate", nil)
		end
	end
	local function start(_, button)
		if not Same(button, "LeftButton") then return end
		local x, y = Cursor(current)
		if not x then return end
		current.drag = { x, y }
		current.frameMethods.SetScript(current.frame, "OnUpdate", function()
			local u, v = Cursor(current)
			if not u or not current.drag then Release() return end
			local previous = current.drag
			current.drag = { u, v }
			current.pan(M, (u - previous[1]) * current.width, (v - previous[2]) * current.height)
		end)
	end
	return Set(current, current.frame, current.frameMethods, "EnableMouse", true)
		and Set(current, current.frame, current.frameMethods, "EnableMouseWheel", true)
		and Set(current, current.frame, current.frameMethods, "SetScript", "OnMouseWheel", wheel)
		and Set(current, current.frame, current.frameMethods, "SetScript", "OnMouseDown", start)
		and Set(current, current.frame, current.frameMethods, "SetScript", "OnMouseUp", stop)
end

function M:CreateWorldCanvas(host, parentUiMapID, mapIDs, layerIndex)
	if self ~= M then return nil, "owner" end
	return Operation(function()
		if not Secret(observe) and type(observe) == "function" and Same(Call(observe, M, host, true), false) then return end
		if Secret(mapIDs) or type(mapIDs) ~= "table" then return end
		local meta = getmetatable(mapIDs)
		if Secret(meta) or type(meta) ~= "nil" then return end
		local count = 0
		for key in pairs(mapIDs) do
			if not Number(key) or key % 1 ~= 0 or key < 1 or key > 16 then return end
			count = count + 1
		end
		if count == 0 or count > 16 then return end
		local available = Call(children, M, parentUiMapID)
		if not available then return end
		local allowed, seen, maps, total = {}, {}, {}, 0
		for _, id in ipairs(available) do allowed[id] = true end
		for index = 1, count do
			local id = mapIDs[index]
			if not Number(id) or not allowed[id] or seen[id] then return end
			local map = Call(tiles, M, id, parentUiMapID, layerIndex)
			if not map then return end
			maps[index], seen[id], total = map, true, total + #map.textures
		end
		if total > 512 then return end
		for _, map in ipairs(maps) do
			if not Same(map.parentArtID, maps[1].parentArtID) or not Same(map.parentWidth, maps[1].parentWidth)
				or not Same(map.parentHeight, maps[1].parentHeight) then return end
		end
		local methods = Functions(host, { "GetParent", "GetSize", "IsForbidden", "IsProtected", "IsVisible", "GetEffectiveScale", "GetLeft", "GetTop" })
		if not methods then return end
		if not Same(E.GetApplyGeneration, generation) or type(generation) ~= "function" then return end
		local token = Call(generation, E, "profile")
		if not Number(token) or token < 1 or token % 1 ~= 0 then return end
		local cursor = GetCursorPosition
		if Secret(cursor) or type(cursor) ~= "function" then return end
		local parent = Call(methods.GetParent, host)
		local width, height = Call(methods.GetSize, host)
		if Secret(parent) or type(parent) ~= "table" or not Number(width) or not Number(height) or width <= 0 or height <= 0
			or not Same(Call(methods.IsForbidden, host), false) or not Same(Call(methods.IsProtected, host), false)
			or not Same(Call(methods.IsVisible, host), true) then return end
		local current = view
		if current and current.failed then return end
		if current and (not Same(current.host, host) or not Owned(current)) then return end
		for _, map in ipairs(maps) do if not Same(map.current(), true) then return end end
		if not Methods(host, methods) or not Same(E.GetApplyGeneration, generation)
			or not Same(Call(generation, E, "profile"), token) then return end
		if not current then
			local frame = Call(create, "Frame", nil, host)
			local fm = Functions(frame, { "GetParent", "SetClipsChildren", "SetSize", "SetPoint", "Show", "Hide", "SetScript", "EnableMouse", "EnableMouseWheel" })
			local child = fm and Call(create, "Frame", nil, frame)
			local cm = Functions(child, { "GetParent", "SetSize", "SetPoint", "CreateTexture" })
			if not fm or not cm then
				-- Frames cannot be destroyed. Retain one failed construction so
				-- missing client capabilities cannot allocate again on refresh.
				local cleanup = Functions(frame, { "GetParent", "Hide" })
				if cleanup and Same(Call(cleanup.GetParent, frame), host) then pcall(cleanup.Hide, frame) end
				view = { failed = true, frame = frame, child = child }
				return
			end
			current = { host = host, frame = frame, child = child, frameMethods = fm, childMethods = cm, pool = {} }
			view = current
		end
		current.hostMethods, current.parent, current.width, current.height = methods, parent, width, height
		current.maps, current.left, current.top, current.zoom = maps, 0, 0, 1
		current.parentUiMapID = parentUiMapID
		current.generation, current.open, current.cursor = token, true, cursor
		current.refused = nil
		current.opened = {}
		current.pan, current.zoomMethod = M.PanWorldCanvas, M.ZoomWorldCanvas
		local fit = math.min(width / maps[1].parentWidth, height / maps[1].parentHeight)
		current.basisWidth, current.basisHeight = maps[1].parentWidth * fit, maps[1].parentHeight * fit
		current.offsetX, current.offsetY = (width - current.basisWidth) / 2, (height - current.basisHeight) / 2
		if not Number(current.basisWidth) or not Number(current.basisHeight)
			or current.basisWidth <= 0 or current.basisHeight <= 0 then return end
		-- Observation joins only an explicitly constructed native viewport.
		if not Secret(observe) and type(observe) == "function" then
			local observed, mountCurrent = Call(observe, M, host)
			if Same(observed, false) then return end
			if Same(observed, true) then
				if Secret(mountCurrent) or type(mountCurrent) ~= "function" then return end
				current.mountCurrent = mountCurrent
			end
		end
		if not Set(current, current.frame, current.frameMethods, "SetClipsChildren", true)
			or not Set(current, current.frame, current.frameMethods, "SetSize", width, height)
			or not Set(current, current.frame, current.frameMethods, "SetPoint", "TOPLEFT", host, "TOPLEFT", 0, 0)
			or not Set(current, current.child, current.childMethods, "SetSize", width, height)
			or not Set(current, current.child, current.childMethods, "SetPoint", "TOPLEFT", current.frame, "TOPLEFT", 0, 0)
			or not Input(current) or not Paint(current) then return end
		if not Current(current) then return end
		return current.frame
	end)
end

function M:ReleaseWorldCanvas()
	if self ~= M or busy then return false end
	busy = true
	local ok, released = pcall(Release)
	if ok and released and view then view.refused = nil end
	if ok and released then RefreshPins() end
	busy = nil
	return ok and released
end

-- Every binding owns one exact view. A later open cannot revive its closures.
function M:WorldCanvasPinView()
	local current = view
	if self ~= M then return nil, "owner" end
	if current and current.refused then return nil, "unavailable" end
	if not current or Same(current.open, false) then return nil, "closed" end
	if not Current(current) or not PoolOwned(current) or not Current(current) then return nil, "unavailable" end
	local opened = current.opened
	local function valid()
		return Same(current.opened, opened) and Current(current) and PoolOwned(current) and Current(current)
	end
	return { frame = current.frame, host = current.host, parentUiMapID = current.parentUiMapID,
		current = valid,
		zoom = function()
			if valid() then return current.zoom, MIN_ZOOM, MAX_ZOOM end
		end,
		projectMap = function(uiMapID, x, y)
			if not Number(uiMapID) or not Number(x) or not Number(y) or not valid() then return end
			for _, map in ipairs(current.maps) do
				if Same(map.uiMapID, uiMapID) then
					local u, v = Call(project, map, x, y)
					if not Number(u) or not Number(v) or not valid() then return end
					local px, py = Camera(current, u, v)
					if not Number(px) or not Number(py) or not valid() then return end
					return px, py, px >= 0 and px <= current.width and py >= 0 and py <= current.height
				end
			end
		end }
end

function M:RefreshWorldCanvasHost()
	if self ~= M then return end
	return Operation(function()
		local current = view
		if not current or not current.open or current.failed or not Sources(current)
			or not Owned(current) or not PoolOwned(current) or not Methods(current.host, current.hostMethods) then return end
		local host, methods = current.host, current.hostMethods
		local parent = Call(methods.GetParent, host)
		local width, height = Call(methods.GetSize, host)
		local visible = Call(methods.IsVisible, host)
		if not Same(parent, current.parent) or not Number(width) or not Number(height) or width <= 0 or height <= 0
			or not Same(Call(methods.IsForbidden, host), false) or not Same(Call(methods.IsProtected, host), false)
			or Secret(visible) or type(visible) ~= "boolean" or not Sources(current)
			or not Methods(host, methods) or not Owned(current) or not PoolOwned(current) then return end
		if not visible then
			local ok = pcall(current.frameMethods.Hide, current.frame)
			return ok and Owned(current) and Sources(current)
		end
		local maps, total = {}, 0
		for index, old in ipairs(current.maps) do
			local map = Call(tiles, M, old.uiMapID, current.parentUiMapID, old.layerIndex)
			if not map or not Sources(current) or not Owned(current) or not PoolOwned(current) then return end
			maps[index], total = map, total + #map.textures
			if total > 512 or not Same(map.parentArtID, maps[1].parentArtID)
				or not Same(map.parentWidth, maps[1].parentWidth) or not Same(map.parentHeight, maps[1].parentHeight) then return end
		end
		if not Same(Call(methods.GetParent, host), parent) then return end
		local closingWidth, closingHeight = Call(methods.GetSize, host)
		if not Same(closingWidth, width) or not Same(closingHeight, height) or not Sources(current)
			or not Methods(host, methods) or not Owned(current) or not PoolOwned(current) then return end
		local centerX, centerY = current.left + (.5 * current.width - current.offsetX) / (current.basisWidth * current.zoom),
			current.top + (.5 * current.height - current.offsetY) / (current.basisHeight * current.zoom)
		local fit = math.min(width / maps[1].parentWidth, height / maps[1].parentHeight)
		local bw, bh = maps[1].parentWidth * fit, maps[1].parentHeight * fit
		if not Number(bw) or not Number(bh) or bw <= 0 or bh <= 0 then return end
		current.width, current.height = width, height
		current.maps = maps
		current.basisWidth, current.basisHeight = bw, bh
		current.offsetX, current.offsetY = (width - bw) / 2, (height - bh) / 2
		current.left = centerX - (.5 * width - current.offsetX) / (bw * current.zoom)
		current.top = centerY - (.5 * height - current.offsetY) / (bh * current.zoom)
		return Set(current, current.frame, current.frameMethods, "SetSize", width, height)
			and Set(current, current.child, current.childMethods, "SetSize", width, height) and Paint(current)
	end)
end

function M:WorldCanvasPosition(x, y)
	if self ~= M or not view or not Current(view) or not Number(x) or not Number(y) then return end
	return view.left + (x * view.width - view.offsetX) / (view.basisWidth * view.zoom),
		view.top + (y * view.height - view.offsetY) / (view.basisHeight * view.zoom)
end

function M:ZoomWorldCanvas(factor, x, y)
	if self ~= M or not Number(factor) or factor <= 0 or not Number(x) or not Number(y) then return end
	return Operation(function()
		local current = view
		if not current or not Current(current) then return end
		local zoom = current.zoom * factor
		if not Number(zoom) or zoom < MIN_ZOOM or zoom > MAX_ZOOM then return end
		local xUnit = (x * current.width - current.offsetX) / current.basisWidth
		local yUnit = (y * current.height - current.offsetY) / current.basisHeight
		local u, v = current.left + xUnit / current.zoom, current.top + yUnit / current.zoom
		current.left, current.top, current.zoom = u - xUnit / zoom, v - yUnit / zoom, zoom
		return Paint(current)
	end)
end

function M:PanWorldCanvas(x, y)
	if self ~= M or not Number(x) or not Number(y) then return end
	return Operation(function()
		local current = view
		if not current or not Current(current) then return end
		current.left = current.left - x / (current.basisWidth * current.zoom)
		current.top = current.top - y / (current.basisHeight * current.zoom)
		return Paint(current)
	end)
end

function M:WorldCanvasState()
	if self ~= M or not view or not Current(view) or not PoolOwned(view) or not Current(view) then return end
	return { frame = view.frame, child = view.child, maps = #view.maps, tiles = view.tileCount,
		basisWidth = view.basisWidth, basisHeight = view.basisHeight }
end

pinView, refreshHost = M.WorldCanvasPinView, M.RefreshWorldCanvasHost

-- One explicitly selected source map, on this same camera and clipping owner.
local function QuestSame(a, b)
	return not Secret(a) and not Secret(b) and rawequal(a, b)
end

-- This is an opt-in presentation slice; loading it does not create a provider.
-- Always-published intrinsics are captured at module load, after trusted
-- client publication, before a later substituted getter can be invoked.
local INTRINSIC_SPECS = {
	{ false, "GetCVarBool" }, { false, "HaveQuestData" },
	{ "C_Map", "GetMapInfo" }, { "C_TaskQuest", "DoesMapShowTaskQuestObjectives" },
	{ "C_QuestLog", "IsWorldQuest" }, { "C_QuestLog", "IsQuestTask" },
	{ "C_QuestLog", "GetQuestsOnMap" }, { "C_QuestLog", "GetNextWaypointForMap" },
	{ "C_SuperTrack", "GetSuperTrackedQuestID" },
}
local questIntrinsics = {}
for index, spec in ipairs(INTRINSIC_SPECS) do
	local namespace = spec[1] and rawget(_G, spec[1]) or _G
	if not Secret(namespace) and type(namespace) == "table" then
		local fn = rawget(namespace, spec[2])
		if not Secret(fn) and type(fn) == "function" then questIntrinsics[index] = { namespace, fn } end
	end
end
local questEnum = rawget(_G, "Enum")
local questMapTypes = not Secret(questEnum) and type(questEnum) == "table" and rawget(questEnum, "UIMapType")
local questTypeValues = {}
if not Secret(questMapTypes) and type(questMapTypes) == "table" then
	for _, key in ipairs({ "World", "Continent", "Cosmic" }) do questTypeValues[key] = rawget(questMapTypes, key) end
end
local questBridge
local CaptureCallbacks
local QUEST_TEMPLATE = "QuestPinTemplate"
local QUEST_EVENTS = { "QUEST_LOG_UPDATE", "QUEST_WATCH_LIST_CHANGED", "QUEST_POI_UPDATE", "CVAR_UPDATE" }
local QUEST_CALLBACKS = { "MapCanvas.PingQuestID", "SetHighlightedQuestPOI", "ClearHighlightedQuestPOI", "Supertracking.OnChanged" }

local function Plain(value)
	return not Secret(value) and type(value) == "table" and type(getmetatable(value)) == "nil"
end

-- Plain source/registry/pool objects need no resolver callback. Widget methods
-- retain the separate captured resolver/metadata checks below.
local function RawMethods(object, methods)
	if not Plain(object) then return false end
	for key, fn in pairs(methods) do if not QuestSame(rawget(object, key), fn) then return false end end
	return true
end

local function IntrinsicsCurrent()
	for index, spec in ipairs(INTRINSIC_SPECS) do
		local old = questIntrinsics[index]
		local namespace = spec[1] and rawget(_G, spec[1]) or _G
		if not old or not QuestSame(namespace, old[1]) or (spec[1] and not Plain(namespace))
			or not QuestSame(rawget(namespace, spec[2]), old[2]) then return false end
	end
	if not QuestSame(rawget(_G, "Enum"), questEnum) or not Plain(questEnum)
		or not QuestSame(rawget(questEnum, "UIMapType"), questMapTypes) or not Plain(questMapTypes) then return false end
	for _, key in ipairs({ "World", "Continent", "Cosmic" }) do
		if not Number(questTypeValues[key]) or not QuestSame(rawget(questMapTypes, key), questTypeValues[key]) then return false end
	end
	return true
end

local function NativeResult(fn, ...)
	local function collect(ok, ...)
		if not ok then return end
		local count = select("#", ...)
		for index = 1, count do if Secret((select(index, ...))) then return end end
		return { n = count, ... }
	end
	return collect(pcall(fn, ...))
end

local function Class(value)
	if not Plain(value) then return end
	local methods = {}
	for key, item in pairs(value) do
		if Secret(key) or type(key) ~= "string" or Secret(item) then return end
		if type(item) == "function" then methods[key] = item end
	end
	if next(methods) then return methods end
end

-- Initial publication is trusted to the client's FrameXML loader. Capturing
-- these globals is not byte provenance or proof against a preexisting forgery;
-- the seals below detect transfers after that explicit loader boundary.
local function NativeSources()
	local result = {}
	for _, name in ipairs({ "QuestDataProviderMixin", "MapCanvasDataProviderMixin", "MapCanvasPinMixin",
		"QuestPinMixin", "MapUtil", "POIButtonMixin", "POIButtonDisplayLayerMixin", "LegendHighlightablePoiPinMixin", "MapCanvasMixin", "CallbackRegistryMixin", "MapCanvasPinFrameLevelsManagerMixin", "WorldMapPOIQuantizerMixin", "SparseGridMixin" }) do
		local object = rawget(_G, name)
		local methods = Class(object)
		if not methods then return end
		result[name] = { object = object, methods = methods }
	end
	for _, name in ipairs({ "CreateFromMixins", "CreateUnsecuredFramePool", "Pool_HideAndClearAnchors", "InCombatLockdown",
		"QuestMapFrame_GetFocusedQuestID", "QuestUtils_IsQuestWorldQuest", "QuestUtils_IsQuestBonusObjective" }) do
		local fn = rawget(_G, name)
		if Secret(fn) or type(fn) ~= "function" then return end
		result[name] = fn
	end
	return result
end

local function NativeCurrent(record)
	for name, item in pairs(record.sources) do
		if type(item) == "function" then
			if not QuestSame(rawget(_G, name), item) then return false end
		elseif not QuestSame(rawget(_G, name), item.object) or not Plain(item.object)
			or not RawMethods(item.object, item.methods) then return false end
	end
	return IntrinsicsCurrent() and QuestSame(rawget(_G, "EnumUtil"), record.enumUtil) and Plain(record.enumUtil)
		and QuestSame(rawget(record.enumUtil, "MakeEnum"), record.makeEnum)
		and QuestSame(M.WorldQuestSnapshot, record.snapshotMethod)
		and QuestSame(E.RegisterEvent, record.registerEvent) and QuestSame(E.UnregisterEvent, record.unregisterEvent)
end

-- Public typed registry layout, including deferred membership. Never search for
-- or remove a callback belonging to any other provider instance.
local function RegistryEntry(record, event, owner, private)
	owner = owner or record.provider
	local registry = private and record.host or record.registry
	local methods = private and record.privateRegistryMethods or record.registryMethods
	local expectedTables = private and record.privateTables or record.registryTables
	local expectedDeferred = private and record.privateDeferred or record.deferred
	local expectedExecuting = private and record.privateExecuting or record.executing
	if (not private and not QuestSame(rawget(_G, "EventRegistry"), registry)) or not Plain(registry)
		or not RawMethods(registry, methods) then return nil, false end
	local tables = Call(methods.GetCallbackTables, registry)
	local deferred, executing = rawget(registry, "deferredCallbacks"), rawget(registry, "executingEvents")
	if not QuestSame(tables, expectedTables) or not Plain(tables) or not Plain(deferred) or not Plain(executing)
		or not QuestSame(deferred, expectedDeferred) or not QuestSame(executing, expectedExecuting)
		or not QuestSame(rawget(executing, event), nil) then return nil, false end
	local function callbacksShape(callbacks)
		if not Plain(callbacks) then return false end
		for ownerKey, callback in pairs(callbacks) do
			if Secret(ownerKey) or Secret(callback) or type(callback) ~= "function" then return false end
		end
		return true
	end
	local found, kind, kinds = nil, nil, 0
	for callbackType, events in pairs(tables) do
		kinds = kinds + 1
		if Secret(callbackType) or (not QuestSame(callbackType, record.callbackTypes.Closure)
			and not QuestSame(callbackType, record.callbackTypes.Function)) or not Plain(events) then return nil, false end
		local callbacks = rawget(events, event)
		if type(callbacks) ~= "nil" then
			if not callbacksShape(callbacks) then return nil, false end
			local fn = rawget(callbacks, owner)
			if Secret(fn) then return nil, false end
			if type(fn) ~= "nil" then
				if type(fn) ~= "function" or found then return nil, false end
				found, kind = fn, callbackType
			end
		end
	end
	if kinds ~= 2 then return nil, false end
	local waiting = rawget(deferred, event)
	if type(waiting) ~= "nil" then
		if not Plain(waiting) then return nil, false end
		for callbackType, callbacks in pairs(waiting) do
			if Secret(callbackType) or (not QuestSame(callbackType, record.callbackTypes.Closure)
				and not QuestSame(callbackType, record.callbackTypes.Function)) then return nil, false end
			if not callbacksShape(callbacks) or not QuestSame(rawget(callbacks, owner), nil) then return nil, false end
		end
	end
	return found, true, kind
end

local function BridgeOwned(record)
	return QuestSame(questBridge, record) and QuestSame(view, record.view) and QuestSame(record.view.opened, record.opened)
		and Owned(record.view) and NativeCurrent(record) and Plain(record.provider) and RawMethods(record.provider, record.providerMethods)
		and Plain(record.host) and record.hostMethods and RawMethods(record.host, record.hostMethods)
		and (QuestSame(rawget(record.provider, "owningMap"), record.host)
			or (not record.added and QuestSame(rawget(record.provider, "owningMap"), nil)))
end

-- Validate acquisition order with the actual native filter. The declared
-- synchronous native getters are pure over this complete refresh state; no
-- copied filter algorithm or replacement environment is installed.
local function FilterState(record, snapshot)
	if not NativeCurrent(record) or not Plain(snapshot) or not Number(snapshot.count)
		or snapshot.count < 0 or snapshot.count % 1 ~= 0 or Secret(snapshot.row) or type(snapshot.row) ~= "function"
		or Secret(snapshot.waypoint) or type(snapshot.waypoint) ~= "function" then return end
	local function one(index, ...)
		local result = NativeResult(questIntrinsics[index][2], ...)
		if not result or result.n ~= 1 or not IntrinsicsCurrent() then return end
		return result
	end
	local cvar = one(1, "questPOI")
	if not cvar or type(cvar[1]) ~= "boolean" then return end
	local state = { enabled = cvar[1], flags = {}, rows = {} }
	if not state.enabled then if NativeCurrent(record) then return state end return end
	local map, task = one(3, record.sourceMapID), one(4, record.sourceMapID)
	if not map or not Plain(map[1]) or not task or type(task[1]) ~= "boolean" then return end
	local mapType = rawget(map[1], "mapType")
	if not Number(mapType) or mapType % 1 ~= 0 then return end
	state.mapType, state.task = mapType, task[1]
	local function flags(id)
		local world, taskQuest, have = one(5, id), one(6, id), one(2, id)
		if not world or not taskQuest or not have or type(world[1]) ~= "boolean"
			or type(taskQuest[1]) ~= "boolean" or type(have[1]) ~= "boolean" then return false end
		local previous = state.flags[id]
		if previous and (not QuestSame(previous[1], world[1]) or not QuestSame(previous[2], taskQuest[1])
			or not QuestSame(previous[3], have[1])) then return false end
		state.flags[id] = { world[1], taskQuest[1], have[1] }
		return true
	end
	for index = 1, snapshot.count do
		local row = NativeResult(snapshot.row, index)
		if not row or row.n ~= 4 or not Number(row[1]) or row[1] < 1 or row[1] % 1 ~= 0
			or not Number(row[2]) or not Number(row[3]) or type(row[4]) ~= "boolean" or not flags(row[1]) then return end
		state.rows[index] = row
	end
	local waypoint = NativeResult(snapshot.waypoint)
	if not waypoint or waypoint.n ~= 3 then return end
	if waypoint[2] and waypoint[3] then
		if not Number(waypoint[1]) or waypoint[1] < 1 or waypoint[1] % 1 ~= 0
			or not Number(waypoint[2]) or not Number(waypoint[3]) or not flags(waypoint[1]) then return end
		state.waypoint = waypoint
	elseif type(waypoint[2]) ~= "nil" or type(waypoint[3]) ~= "nil" then return end
	if not NativeCurrent(record) then return end
	return state
end

local function FilterSame(a, b)
	if not b or not QuestSame(a.enabled, b.enabled) or not QuestSame(a.mapType, b.mapType) or not QuestSame(a.task, b.task) then return false end
	for id, values in pairs(a.flags) do
		local other = b.flags[id]
		if not other then return false end
		for index = 1, 3 do if not QuestSame(values[index], other[index]) then return false end end
	end
	return true
end

local function PrepareFilter(record, snapshot)
	local state = FilterState(record, snapshot)
	if not state or not QuestSame(Call(snapshot.current), true) then return end
	local sequence = {}
	local function consider(row, indicator)
		local result = NativeResult(record.providerMethods.ShouldShowQuest, record.provider, row[1], state.mapType, state.task, indicator)
		if not result or result.n ~= 1 or type(result[1]) ~= "boolean" or not NativeCurrent(record) then return false end
		if result[1] then sequence[#sequence + 1] = row[1] end
		return true
	end
	if state.enabled then
		for _, row in ipairs(state.rows) do if not consider(row, row[4]) then return end end
		if state.waypoint and not consider(state.waypoint, false) then return end
	end
	local function current()
		return NativeCurrent(record) and QuestSame(Call(snapshot.current), true) and FilterSame(state, FilterState(record, snapshot))
	end
	if not current() then return end
	return { sequence = sequence, next = 1, current = current }
end

local function QuantizerCapture(record)
	local quantizer = rawget(record.provider, "poiQuantizer")
	if not Plain(quantizer) or not RawMethods(quantizer, record.sources.WorldMapPOIQuantizerMixin.methods) then return false end
	local grid, size = rawget(quantizer, "grid"), rawget(quantizer, "size")
	local width, height = rawget(quantizer, "numCellsWide"), rawget(quantizer, "numCellsHigh")
	if not Plain(grid) or not RawMethods(grid, record.sources.SparseGridMixin.methods)
		or not Number(size) or size <= 0 or not Number(width) or width < 1 or width % 1 ~= 0
		or not Number(height) or height < 1 or height % 1 ~= 0 or not Number(width * height)
		or not QuestSame(rawget(grid, "width"), width) or not QuestSame(rawget(grid, "height"), height)
		or not Plain(rawget(grid, "cells")) then return false end
	if record.quantizer and not QuestSame(record.quantizer, quantizer) then return false end
	record.quantizer, record.grid, record.cells = quantizer, grid, rawget(grid, "cells")
	record.quantizerSize, record.gridWidth, record.gridHeight = size, width, height
	return true
end

local function QuantizerCurrent(record)
	if not record.quantizer then return true end
	local quantizer = rawget(record.provider, "poiQuantizer")
	if not QuestSame(quantizer, record.quantizer) or not Plain(quantizer)
		or not RawMethods(quantizer, record.sources.WorldMapPOIQuantizerMixin.methods)
		or not QuestSame(rawget(quantizer, "size"), record.quantizerSize) then return false end
	if record.resizingGrid then return true end
	local grid = rawget(quantizer, "grid")
	if not QuestSame(grid, record.grid) or not Plain(grid) or not RawMethods(grid, record.sources.SparseGridMixin.methods)
		or not QuestSame(rawget(grid, "cells"), record.cells) or not Plain(record.cells)
		or not QuestSame(rawget(grid, "width"), record.gridWidth) or not QuestSame(rawget(grid, "height"), record.gridHeight)
		or not QuestSame(rawget(quantizer, "numCellsWide"), record.gridWidth)
		or not QuestSame(rawget(quantizer, "numCellsHigh"), record.gridHeight) then return false end
	for index, pin in pairs(record.cells) do
		if not Number(index) or index < 1 or index > record.gridWidth * record.gridHeight or index % 1 ~= 0
			or Secret(pin) or type(pin) ~= "table" or not record.pins[pin] then return false end
	end
	return true
end

local function BridgeCurrent(record)
	return not record.failed and BridgeOwned(record) and Current(record.view) and PoolOwned(record.view)
		and Methods(record.view.frame, record.parentMethods) and Methods(record.view.child, record.tileMethods)
		and QuestSame(Call(record.parentMethods.GetFrameLevel, record.view.frame), record.parentLevel)
		and QuestSame(Call(record.tileMethods.GetFrameLevel, record.view.child), record.tileLevel)
		and QuantizerCurrent(record) and (not record.refreshing or not record.filter or QuestSame(Call(record.filter.current), true))
		and (not record.leased or CaptureCallbacks(record, true))
		and QuestSame(Call(record.snapshot.owned), true)
		and QuestSame(Call(record.sources.InCombatLockdown), false) and BridgeOwned(record)
end

local function Require(record)
	if not BridgeCurrent(record) then error("quest view unavailable", 0) end
end

local WIDGET_META = { "__index", "__newindex", "__eq", "__call", "__metatable" }
local function WidgetSeal(object)
	local meta = getmetatable(object)
	if Secret(meta) then return end
	local kind, values = type(meta), {}
	if kind ~= "nil" and kind ~= "table" and kind ~= "string" then return end
	if kind == "table" then
		for _, key in ipairs(WIDGET_META) do
			local value = rawget(meta, key)
			if Secret(value) then return end
			values[key] = value
		end
	end
	return { meta = meta, values = values }
end

local function WidgetCurrent(object, seal)
	if not seal or not QuestSame(getmetatable(object), seal.meta) then return false end
	if type(seal.meta) == "table" then
		for _, key in ipairs(WIDGET_META) do
			if not QuestSame(rawget(seal.meta, key), seal.values[key]) then return false end
		end
	end
	return true
end

local PIN_SCRIPTS = { "OnShow", "OnHide", "OnMouseUp", "OnMouseDown", "OnClick", "OnEnter", "OnLeave" }

local function PinOwned(record, pin)
	local item = record.pins[pin]
	if item then
		if not WidgetCurrent(pin, item.widget) then return false end
		local selected, questID = rawget(pin, "selected"), rawget(pin, "questID")
		if Secret(selected) or (type(selected) ~= "nil" and type(selected) ~= "boolean") or Secret(questID) then return false end
		if not item.acquiring and item.expectedQuestID and not QuestSame(questID, item.expectedQuestID) then return false end
		if not QuestSame(rawget(pin, "widgetContainer"), nil) or not QuestSame(rawget(pin, "iconWidgetSet"), nil)
			or not QuestSame(rawget(pin, "pinSuppressor"), nil) then return false end
		if item.loaded and (not QuestSame(rawget(pin, "scaleFactor"), 1) or not QuestSame(rawget(pin, "startScale"), 1)
			or not QuestSame(rawget(pin, "endScale"), 1)) then return false end
		for _, key in ipairs(PIN_SCRIPTS) do
			if not QuestSame(Call(item.methods.GetScript, pin, key), item.scripts[key]) then return false end
		end
		for _, child in ipairs(item.children) do
			if not QuestSame(rawget(child.owner, child.key), child.object) or not WidgetCurrent(child.object, child.widget) or not Methods(child.object, child.methods)
				or not QuestSame(Call(child.methods.GetParent, child.object), child.owner)
				or not Methods(child.object, child.methods) then return false end
		end
	end
	if item and item.callback then
		local fn, ok, kind = RegistryEntry(record, "Supertracking.OnChanged", pin)
		if not ok or not QuestSame(fn, item.callback.fn) or not QuestSame(kind, item.callback.kind) then return false end
	end
	return item and Methods(pin, item.methods) and QuestSame(Call(item.methods.GetParent, pin), record.view.frame)
		and QuestSame(rawget(pin, "owningMap"), record.host) and QuestSame(rawget(pin, "pinTemplate"), QUEST_TEMPLATE)
		and (QuestSame(rawget(pin, "dataProvider"), nil) or QuestSame(rawget(pin, "dataProvider"), record.provider))
end

local function WritePin(record, pin, key, ...)
	Require(record)
	if not PinOwned(record, pin) then error("quest pin transferred", 0) end
	local item = record.pins[pin]
	item.methods[key](pin, ...)
	if key == "SetScript" then
		local script, handler = ...
		item.scripts[script] = handler
	end
	Require(record)
	if not PinOwned(record, pin) then error("quest pin transferred", 0) end
end

CaptureCallbacks = function(record, expected, partial)
	local named = { ["MapCanvas.PingQuestID"] = record.providerMethods.OnPingQuestID,
		SetHighlightedQuestPOI = record.providerMethods.OnHighlightedQuestPOIChange,
		ClearHighlightedQuestPOI = record.providerMethods.OnHighlightedQuestPOIChange }
	local private = { SetFocusedQuestID = record.providerMethods.RefreshAllData,
		ClearFocusedQuestID = record.providerMethods.RefreshAllData, SetBounty = record.providerMethods.SetBounty }
	local function capture(event, methods, leases, localRegistry)
		local fn, ok, kind = RegistryEntry(record, event, nil, localRegistry)
		if not ok then return false end
		if expected then
			local old = leases[event]
			return old and QuestSame(old.fn, fn) and QuestSame(old.kind, kind)
		end
		local known = methods[event]
		if partial and not known then
			-- OnShow's final anonymous registration cannot be adopted from a
			-- failed prefix. Any present entry remains unknown and untouched.
			if not QuestSame(fn, nil) then return false end
		elseif not (partial and QuestSame(fn, nil)) then
			if type(fn) ~= "function" or (known and not QuestSame(fn, known))
				or not QuestSame(kind, record.callbackTypes.Function) then return false end
		end
		leases[event] = { fn = fn, kind = kind }
		return true
	end
	for _, event in ipairs(QUEST_CALLBACKS) do
		if not capture(event, named, record.callbacks, false) then return false end
	end
	for event in pairs(private) do
		if not capture(event, private, record.privateCallbacks, true) then return false end
	end
	return true
end

-- A failed registration prefix can leave an unknown anonymous slot. Dispose
-- only independently authenticated named/core leases; retain that slot and the
-- failed provider explicitly, without calling broad native OnHide/OnRemoved.
local function KnownInitCleanup(record)
	if record.busy or not BridgeOwned(record) or next(record.active) then return false end
	record.busy, record.releasing = true, true
	local ok = pcall(function()
		for event in pairs(record.events) do
			if not BridgeOwned(record) or not Plain(record.registeredTable)
				or not QuestSame(rawget(record.provider, "registeredEvents"), record.registeredTable)
				or not QuestSame(rawget(record.registeredTable, event), true) then error("quest event lease unavailable", 0) end
			record.providerMethods.UnregisterEvent(record.provider, event)
			if not BridgeOwned(record) or not QuestSame(rawget(record.registeredTable, event), nil) then error("quest event lease retained", 0) end
		end
		local named = { ["MapCanvas.PingQuestID"] = record.providerMethods.OnPingQuestID,
			SetHighlightedQuestPOI = record.providerMethods.OnHighlightedQuestPOIChange,
			ClearHighlightedQuestPOI = record.providerMethods.OnHighlightedQuestPOIChange }
		local private = { SetFocusedQuestID = record.providerMethods.RefreshAllData,
			ClearFocusedQuestID = record.providerMethods.RefreshAllData, SetBounty = record.providerMethods.SetBounty }
		local function removeKnown(event, expected, localRegistry)
			if not BridgeOwned(record) then error("quest registration owner transferred", 0) end
			local fn, valid, kind = RegistryEntry(record, event, nil, localRegistry)
			if valid and QuestSame(fn, expected) and QuestSame(kind, record.callbackTypes.Function) then
				local registry = localRegistry and record.host or record.registry
				local methods = localRegistry and record.privateRegistryMethods or record.registryMethods
				methods.UnregisterCallback(registry, event, record.provider)
				local remaining, admitted = RegistryEntry(record, event, nil, localRegistry)
				if not admitted or not QuestSame(remaining, nil) or not BridgeOwned(record) then error("quest named lease retained", 0) end
			end
		end
		for event, expected in pairs(private) do removeKnown(event, expected, true) end
		for event, expected in pairs(named) do removeKnown(event, expected, false) end
	end)
	record.busy, record.releasing = nil, nil
	return ok
end

releaseQuestPins = function(current)
	local record = questBridge
	if not record or record.view ~= current then return true end
	if record.initUnknown then
		if not record.busy and BridgeOwned(record) and CaptureCallbacks(record, false, true) then
			record.leased, record.initUnknown = true, nil
		else KnownInitCleanup(record) return false end
	end
	if record.busy or not BridgeOwned(record) or not CaptureCallbacks(record, true) then return false end
	for pin in pairs(record.active) do if not PinOwned(record, pin) then return false end end
	record.busy, record.releasing = true, true
	local ok = pcall(function()
		-- The original OnHide still omits Supertracking; this exact owned entry
		-- is removed afterward, while the real provider still has its GetMap.
		if QuestSame(rawget(record.provider, "owningMap"), record.host) then record.providerMethods.OnHide(record.provider) end
		if not BridgeOwned(record) then error("quest hide transferred", 0) end
		local fn, valid, kind = RegistryEntry(record, "Supertracking.OnChanged")
		local old = record.callbacks["Supertracking.OnChanged"]
		if not valid or not QuestSame(fn, old.fn) or not QuestSame(kind, old.kind) then error("quest callback transferred", 0) end
		if old.fn then record.registryMethods.UnregisterCallback(record.registry, "Supertracking.OnChanged", record.provider) end
		for _, event in ipairs(QUEST_CALLBACKS) do
			local remaining, admitted = RegistryEntry(record, event)
			if not admitted or not QuestSame(remaining, nil) then error("quest callback retained", 0) end
		end
		for event in pairs(record.privateCallbacks) do
			local remaining, admitted = RegistryEntry(record, event, nil, true)
			if not admitted or not QuestSame(remaining, nil) then error("quest private callback retained", 0) end
		end
		if not BridgeOwned(record) then error("quest cleanup transferred", 0) end
		record.host:RemoveAllPinsByTemplate(QUEST_TEMPLATE)
		if QuestSame(rawget(record.provider, "owningMap"), record.host) then record.providerMethods.OnRemoved(record.provider, record.host) end
		if not NativeCurrent(record) or not QuestSame(rawget(record.provider, "owningMap"), nil)
			or next(record.active) or next(record.events) then error("quest cleanup incomplete", 0) end
	end)
	record.busy, record.releasing = nil, nil
	if not ok then record.failed = true return false end
	questBridge = nil
	return true
end

redrawQuestPins = function(current)
	local record = questBridge
	if not record or record.view ~= current then return true end
	if record.busy or not BridgeCurrent(record) then return false end
	record.busy = true
	local ok = pcall(function()
		record.host:GetPinFrameLevelsManager()
		for pin in pairs(record.active) do
			Require(record)
			if not PinOwned(record, pin) then error("quest pin transferred", 0) end
			pin:ApplyCurrentScale()
			Require(record)
			if not PinOwned(record, pin) then error("quest pin transferred", 0) end
			pin:ApplyFrameLevel()
			Require(record)
		end
	end)
	record.busy = nil
	if not ok then record.failed = true end
	return ok and BridgeCurrent(record)
end

function M.CreateWorldQuestPins(moduleOwner, sourceMapID)
	if not QuestSame(moduleOwner, M) or not Number(sourceMapID) or sourceMapID < 1 or sourceMapID % 1 ~= 0 then return nil, "input" end
	if busy or questBridge then return nil, "busy" end
	local current = view
	if not current or not Current(current) or not PoolOwned(current) then return nil, "view" end
	local found
	for _, map in ipairs(current.maps) do if QuestSame(map.uiMapID, sourceMapID) then found = true end end
	if not found then return nil, "map" end
	local sources = NativeSources()
	if not sources or not IntrinsicsCurrent() or not QuestSame(Call(sources.InCombatLockdown), false) then return nil, "source" end
	local snapshotMethod = M.WorldQuestSnapshot
	if Secret(snapshotMethod) or type(snapshotMethod) ~= "function" then return nil, "source" end
	local snapshot = Call(snapshotMethod, M, sourceMapID)
	if not Plain(snapshot) or not Number(snapshot.capacity) or snapshot.capacity < 0 or snapshot.capacity % 1 ~= 0
		or not QuestSame(Call(snapshot.current), true) then return nil, "query" end
	local binding = Call(pinView, M)
	if not Plain(binding) or not QuestSame(Call(binding.current), true) then return nil, "view" end
	local enumUtil = rawget(_G, "EnumUtil")
	local makeEnum = Plain(enumUtil) and rawget(enumUtil, "MakeEnum")
	if Secret(makeEnum) or type(makeEnum) ~= "function" then return nil, "registry" end
	local callbackTypes = Call(makeEnum, "Closure", "Function")
	if not Plain(callbackTypes) or not Number(rawget(callbackTypes, "Closure"))
		or not Number(rawget(callbackTypes, "Function")) then return nil, "registry" end
	local registry = rawget(_G, "EventRegistry")
	if not Plain(registry) then return nil, "registry" end
	local registryMethods = Functions(registry, { "GetCallbackTables", "RegisterCallback", "UnregisterCallback" })
	if not registryMethods then return nil, "registry" end
	for name, fn in pairs(registryMethods) do
		if not QuestSame(fn, sources.CallbackRegistryMixin.methods[name]) then return nil, "registry" end
	end
	local tables = Call(registryMethods.GetCallbackTables, registry)
	local deferred, executing = rawget(registry, "deferredCallbacks"), rawget(registry, "executingEvents")
	if not Plain(tables) or not Plain(deferred) or not Plain(executing) then return nil, "registry" end
	local parentMethods = Functions(current.frame, { "GetScale", "GetFrameLevel", "GetParent" })
	if not parentMethods then return nil, "parent" end
	local tileMethods = Functions(current.child, { "GetFrameLevel", "GetParent" })
	if not tileMethods then return nil, "layer" end
	local parentLevel = Call(parentMethods.GetFrameLevel, current.frame)
	local tileLevel = Call(tileMethods.GetFrameLevel, current.child)
	if not Number(parentLevel) or parentLevel < 0 or parentLevel % 1 ~= 0
		or not Number(tileLevel) or tileLevel < 0 or tileLevel % 1 ~= 0
		or not QuestSame(Call(tileMethods.GetParent, current.child), current.frame) then return nil, "layer" end
	local firstLevel = math.max(parentLevel, tileLevel)
	local record = { view = current, opened = current.opened, sources = sources, snapshot = snapshot,
		snapshotMethod = snapshotMethod, binding = binding, sourceMapID = sourceMapID, pins = {}, active = {},
		events = {}, callbacks = {}, privateCallbacks = {}, capacity = snapshot.capacity, allocated = 0, globalPinScale = 1,
		registry = registry, registryMethods = registryMethods, registryTables = tables, deferred = deferred,
		callbackTypes = callbackTypes, enumUtil = enumUtil, makeEnum = makeEnum,
		executing = executing, parentMethods = parentMethods, tileMethods = tileMethods,
		parentLevel = parentLevel, tileLevel = tileLevel, registerEvent = E.RegisterEvent, unregisterEvent = E.UnregisterEvent }
	if Secret(record.registerEvent) or type(record.registerEvent) ~= "function"
		or Secret(record.unregisterEvent) or type(record.unregisterEvent) ~= "function" then return nil, "events" end
	local host = sources.CreateFromMixins(sources.CallbackRegistryMixin.object)
	record.host = host
	host:OnLoad()
	host:SetUndefinedEventsAllowed(true)
	record.privateRegistryMethods = Functions(host, { "GetCallbackTables", "RegisterCallback", "UnregisterCallback" })
	record.privateTables, record.privateDeferred, record.privateExecuting = rawget(host, "callbackTables"), rawget(host, "deferredCallbacks"), rawget(host, "executingEvents")
	local hostRegistryMethods = Class(host)
	local provider = sources.CreateFromMixins(sources.QuestDataProviderMixin.object)
	record.provider, record.providerMethods = provider, Class(provider)
	if not record.providerMethods or not hostRegistryMethods then return nil, "factory" end
	local manager = sources.CreateFromMixins(sources.MapCanvasPinFrameLevelsManagerMixin.object)
	manager:Initialize()
	local range = math.max(1, record.capacity)
	local activeType, trackedType, pingType = "PIN_FRAME_LEVEL_ACTIVE_QUEST", "PIN_FRAME_LEVEL_SUPER_TRACKED_QUEST", "PIN_FRAME_LEVEL_QUEST_PING"
	-- DEFAULT remains unused. These explicit intervals belong only to this
	-- clipped view and derive from its complete admitted allocation snapshot.
	local start = firstLevel + 1
	local nativeDefault = Call(manager.GetFrameLevelStart, manager, "PIN_FRAME_LEVEL_DEFAULT")
	if not Number(nativeDefault) or start + range * 2 >= nativeDefault then return nil, "layer" end
	-- AddDefinition shifts lower intervals below DEFAULT. Descending insertion
	-- keeps these three explicit owned starts stable; the unused DEFAULT stays.
	if not QuestSame(Call(manager.AddDefinition, manager, pingType, 1, start + range * 2, 0), true)
		or not QuestSame(Call(manager.AddDefinition, manager, trackedType, range, start + range, 0), true)
		or not QuestSame(Call(manager.AddDefinition, manager, activeType, range, start, 0), true) then return nil, "layer" end
	record.manager, record.managerMethods = manager, Class(manager)
	record.levels = { [activeType] = { start, range }, [trackedType] = { start + range, range }, [pingType] = { start + range * 2, 1 } }
	for kind, interval in pairs(record.levels) do
		if not QuestSame(Call(manager.GetValidFrameLevel, manager, kind, 1), interval[1])
			or not QuestSame(Call(manager.GetValidFrameLevel, manager, kind, interval[2]), interval[1] + interval[2] - 1) then return nil, "layer" end
	end
	local function requireHost()
		if record.releasing then
			if not BridgeOwned(record) then error("quest release owner unavailable", 0) end
		else Require(record) end
	end
	local function reset(pool, pin)
		requireHost()
		local item = record.pins[pin]
		if not item then
			local names, seen = {}, {}
			for _, name in ipairs({ "GetParent", "Hide", "ClearAllPoints", "SetPoint", "SetScale", "GetScale",
				"SetFrameLevel", "SetScript", "GetScript", "Show", "IsMouseClickEnabled", "IsMouseMotionEnabled" }) do
				names[#names + 1], seen[name] = name, true
			end
			for _, source in ipairs({ sources.MapCanvasPinMixin, sources.QuestPinMixin, sources.POIButtonMixin, sources.LegendHighlightablePoiPinMixin }) do
				for name in pairs(source.methods) do
					if not seen[name] then names[#names + 1], seen[name] = name, true end
				end
			end
			local methods = Functions(pin, names)
			local expected = {}
			for _, source in ipairs({ sources.POIButtonMixin, sources.QuestPinMixin }) do
				for name, fn in pairs(source.methods) do expected[name] = fn end
			end
			if not methods or not Methods(pin, expected) then error("quest template methods unavailable", 0) end
			if not methods or not QuestSame(Call(methods.GetParent, pin), current.frame) then error("quest pool parent unavailable", 0) end
			item = { methods = methods, scripts = {}, children = {}, widget = WidgetSeal(pin) }
			if not item.widget then error("quest pin metadata unavailable", 0) end
			for _, key in ipairs(PIN_SCRIPTS) do
				local script = Call(methods.GetScript, pin, key)
				if Secret(script) or (type(script) ~= "nil" and type(script) ~= "function") then error("quest script unavailable", 0) end
				item.scripts[key] = script
			end
			for _, key in ipairs({ "Display", "NormalTexture", "PushedTexture", "HighlightTexture", "Glow", "LinkGlow", "Icon" }) do
				local owner = key == "Icon" and rawget(pin, "Display") or pin
				if Secret(owner) or type(owner) ~= "table" then error("quest child owner unavailable", 0) end
				local object = rawget(owner, key)
				local childMethods = Functions(object, { "GetParent", "ClearAllPoints", "SetPoint", "SetSize", "Show", "Hide", "SetAlpha", "SetShown" })
				if not childMethods or not QuestSame(Call(childMethods.GetParent, object), owner) then error("quest template child unavailable", 0) end
				if key == "Display" then
					if not Methods(object, sources.POIButtonDisplayLayerMixin.methods) then error("quest display source unavailable", 0) end
					for name, fn in pairs(sources.POIButtonDisplayLayerMixin.methods) do childMethods[name] = fn end
				else
					local textures = Functions(object, { "SetTexture", "SetAtlas", "SetTexCoord" })
					if not textures then error("quest texture methods unavailable", 0) end
					for name, fn in pairs(textures) do childMethods[name] = fn end
				end
				local widget = WidgetSeal(object)
				if not widget then error("quest child metadata unavailable", 0) end
				item.children[#item.children + 1] = { owner = owner, key = key, object = object, methods = childMethods, widget = widget }
			end
			record.pins[pin] = item
		else
			if not Methods(pin, item.methods) or not QuestSame(Call(item.methods.GetParent, pin), current.frame) then error("quest pin transferred", 0) end
		end
		if record.active[pin] and not PinOwned(record, pin) then error("quest pin transferred", 0) end
		record.active[pin] = nil
		sources.Pool_HideAndClearAnchors(pool, pin)
		requireHost()
		local callback, callbackValid = RegistryEntry(record, "Supertracking.OnChanged", pin)
		if not callbackValid or not QuestSame(callback, nil) then error("quest pin callback retained", 0) end
		item.callback = nil
		if not Methods(pin, item.methods) or not QuestSame(Call(item.methods.GetParent, pin), current.frame) then error("quest reset transferred", 0) end
		item.methods.OnReleased(pin)
		requireHost()
		pin.pinTemplate = nil
		item.methods.SetOwningMap(pin, nil)
		requireHost()
	end
	function host:GetMapID() requireHost() return sourceMapID end
	function host:GetCanvas() requireHost() return current.frame end
	function host:GetCanvasScale()
		requireHost()
		if not Methods(current.frame, parentMethods) then error("quest scale owner transferred", 0) end
		local scale = Call(parentMethods.GetScale, current.frame)
		if not Number(scale) or scale <= 0 then error("quest scale unavailable", 0) end
		requireHost()
		return scale
	end
	function host:GetGlobalPinScale() requireHost() return record.globalPinScale end
	function host:GetCanvasZoomPercent()
		requireHost()
		local zoom, low, high = binding.zoom()
		if not Number(zoom) or not Number(low) or not Number(high) or high <= low then error("quest zoom unavailable", 0) end
		requireHost()
		return math.max(0, math.min(1, (zoom - low) / (high - low)))
	end
	function host:GetPinFrameLevelsManager()
		requireHost()
		if not Plain(manager) or not RawMethods(manager, record.managerMethods) then error("quest layers transferred", 0) end
		local definitions = rawget(manager, "definitions")
		if not Plain(definitions) then error("quest layer definitions unavailable", 0) end
		for kind, interval in pairs(record.levels) do
			local definition = rawget(definitions, kind)
			if not Plain(definition) or not QuestSame(rawget(definition, "startLevel"), interval[1])
				or not QuestSame(rawget(definition, "range"), interval[2]) or not QuestSame(rawget(definition, "overrideType"), nil) then error("quest layer interval transferred", 0) end
		end
		for pin in pairs(record.active) do
			local kind, index = rawget(pin, "pinFrameLevelType"), rawget(pin, "pinFrameLevelIndex")
			if Secret(kind) or type(kind) ~= "string" or not record.levels[kind] then error("quest layer unavailable", 0) end
			if Secret(index) or (type(index) ~= "nil" and (not Number(index) or index < 0 or index % 1 ~= 0 or index > record.levels[kind][2])) then error("quest layer index unavailable", 0) end
		end
		return manager
	end
	local function span(horizontal, value)
		requireHost()
		if not Number(value) then error("quest span input unavailable", 0) end
		local x, y = binding.projectMap(sourceMapID, 0, 0)
		local right, bottom = binding.projectMap(sourceMapID, 1, 1)
		if not Number(x) or not Number(y) or not Number(right) or not Number(bottom) then error("quest span unavailable", 0) end
		local length = horizontal and right - x or bottom - y
		if not Number(length) or length <= 0 then error("quest span unavailable", 0) end
		requireHost()
		return value * length
	end
	function host:DenormalizeHorizontalSize(value) return span(true, value) end
	function host:DenormalizeVerticalSize(value) return span(false, value) end
	function host:ApplyPinPosition(pin, x, y, inset)
		requireHost()
		if Secret(inset) or type(inset) ~= "nil" or not Number(x) or not Number(y) then error("quest position unavailable", 0) end
		local admitted = record.pins[pin]
		if not admitted or not QuestSame(rawget(pin, "questID"), admitted.expectedQuestID) then error("quest identity transferred", 0) end
		admitted.acquiring = nil
		host:GetPinFrameLevelsManager()
		local px, py = binding.projectMap(sourceMapID, x, y)
		local item = record.pins[pin]
		if not item or not PinOwned(record, pin) or not Number(px) or not Number(py) then error("quest projection unavailable", 0) end
		local scale = Call(item.methods.GetScale, pin)
		if not Number(scale) or scale <= 0 then error("quest pin scale unavailable", 0) end
		WritePin(record, pin, "ClearAllPoints")
		WritePin(record, pin, "SetPoint", "TOPLEFT", current.frame, "TOPLEFT", px / scale, -py / scale)
	end
	function host:SetPinPosition(pin, x, y, inset) self:ApplyPinPosition(pin, x, y, inset) end
	function host:GetGlobalPosition() error("quest inset unavailable", 0) end
	function host:ProcessGlobalPinMouseActionHandlers()
		requireHost()
		-- This private host has no registered global mouse interceptors. Native
		-- QuestPin actions continue through their actual inherited handlers.
		return false
	end
	function host:PanTo(x, y)
		Require(record)
		local px, py = binding.projectMap(sourceMapID, x, y)
		if not Number(px) or not Number(py) then error("quest pan unavailable", 0) end
		if not M:PanWorldCanvas(current.width / 2 - px, current.height / 2 - py) then error("quest pan refused", 0) end
	end
	function host:PanAndZoomTo(x, y, percent)
		Require(record)
		if not Number(percent) or percent < 0 or percent > 1 then error("quest zoom input unavailable", 0) end
		local zoom, low, high = binding.zoom()
		if not Number(zoom) or not Number(low) or not Number(high) then error("quest zoom unavailable", 0) end
		if not M:ZoomWorldCanvas((low + percent * (high - low)) / zoom, .5, .5) then error("quest zoom refused", 0) end
		self:PanTo(x, y)
	end
	function host:AddDataProviderEvent(event)
		Require(record)
		local admitted
		for _, name in ipairs(QUEST_EVENTS) do if QuestSame(name, event) then admitted = true end end
		if not admitted or record.events[event] then error("quest event unavailable", 0) end
		local registered = rawget(provider, "registeredEvents")
		if not Plain(registered) or not QuestSame(rawget(registered, event), true)
			or (record.registeredTable and not QuestSame(record.registeredTable, registered)) then error("quest event registration transferred", 0) end
		record.registeredTable = registered
		local handler = function(_, incoming, ...)
			if record.busy or not BridgeCurrent(record) or not QuestSame(event, incoming) then record.failed = true return end
			for index = 1, select("#", ...) do
				if Secret((select(index, ...))) then record.failed = true return end
			end
			record.busy, record.refreshing, record.didRefresh = true, true, nil
			record.filter = nil
			local ok = pcall(record.providerMethods.SignalEvent, provider, incoming, ...)
			if record.didRefresh and (not record.filter or record.filter.next ~= #record.filter.sequence + 1) then ok = false end
			record.busy, record.refreshing = nil, nil
			if not ok or not BridgeCurrent(record) then record.failed = true return end
			if not redrawQuestPins(current) then record.failed = true end
		end
		record.events[event] = handler
		record.registerEvent(E, event, handler, record)
		Require(record)
	end
	function host:RemoveDataProviderEvent(event)
		requireHost()
		if not record.events[event] then error("quest event not owned", 0) end
		record.unregisterEvent(E, event, record)
		requireHost()
		record.events[event] = nil
	end
	function host:UnregisterEvent(event) return self:RemoveDataProviderEvent(event) end
	function host:EnumeratePinsByTemplate(template)
		requireHost()
		if not QuestSame(template, QUEST_TEMPLATE) then error("quest template unavailable", 0) end
		return function(_, previous)
			requireHost()
			return next(record.active, previous)
		end, nil, nil
	end
	function host:RemoveAllPinsByTemplate(template)
		requireHost()
		if not QuestSame(template, QUEST_TEMPLATE) then error("quest template unavailable", 0) end
		if not record.releasing then
			if not record.refreshing then error("quest refresh owner unavailable", 0) end
			local nextSnapshot = Call(snapshotMethod, M, sourceMapID)
			if not Plain(nextSnapshot) or not Number(nextSnapshot.capacity) or nextSnapshot.capacity > record.capacity
				or not QuestSame(Call(nextSnapshot.current), true) then error("quest allocation unavailable", 0) end
			record.filter = PrepareFilter(record, nextSnapshot)
			if not record.filter then error("quest filter state unavailable", 0) end
			record.snapshot, record.didRefresh = nextSnapshot, true
		end
		for pin in pairs(record.active) do
			if not PinOwned(record, pin) then error("quest release pin transferred", 0) end
			if not Plain(record.pool) or not RawMethods(record.pool, record.poolMethods) then error("quest pool transferred", 0) end
			record.poolMethods.Release(record.pool, pin)
			requireHost()
			if not Plain(record.pool) or not RawMethods(record.pool, record.poolMethods) then error("quest pool transferred", 0) end
		end
	end
	function host:AcquirePin(template)
		Require(record)
		if not QuestSame(template, QUEST_TEMPLATE) then error("quest template unavailable", 0) end
		local active = 0
		for _ in pairs(record.active) do active = active + 1 end
		if active >= record.capacity then error("quest snapshot allocation exceeded", 0) end
		local filter = record.filter
		local expectedID = filter and filter.sequence[filter.next]
		if not record.refreshing or not Number(expectedID) then error("quest acquisition sequence exceeded", 0) end
		filter.next = filter.next + 1
		if not Plain(record.pool) or not RawMethods(record.pool, record.poolMethods) then error("quest pool transferred", 0) end
		local pin, fresh = record.poolMethods.Acquire(record.pool)
		Require(record)
		if not Plain(record.pool) or not RawMethods(record.pool, record.poolMethods) then error("quest pool transferred", 0) end
		local item = record.pins[pin]
		if not item or not Methods(pin, item.methods) or not QuestSame(Call(item.methods.GetParent, pin), current.frame) then error("quest acquisition transferred", 0) end
		item.expectedQuestID, item.acquiring = expectedID, true
		pin.pinTemplate = QUEST_TEMPLATE
		item.methods.SetOwningMap(pin, host)
		Require(record)
		record.active[pin] = true
		if fresh then
			local click, motion = item.methods.IsMouseClickEnabled(pin), item.methods.IsMouseMotionEnabled(pin)
			if Secret(click) or type(click) ~= "boolean" or Secret(motion) or type(motion) ~= "boolean" then error("quest input unavailable", 0) end
			local function invokeNative(handler, button, ...)
				Require(record)
				if not QuestSame(button, pin) or item.acquiring or not PinOwned(record, pin)
					or not QuestSame(rawget(pin, "questID"), item.expectedQuestID) then error("quest input owner unavailable", 0) end
				for index = 1, select("#", ...) do
					local value = select(index, ...)
					if Secret(value) then error("quest input unavailable", 0) end
				end
				handler(pin, ...)
				Require(record)
				if not PinOwned(record, pin) then error("quest input transferred", 0) end
			end
			local function runNative(handler, button, ...)
				local ok = pcall(invokeNative, handler, button, ...)
				if not ok then record.failed = true error("quest native input refused", 0) end
			end
			if click then
				local onUp, onDown, onClick = item.methods.OnMouseUp, item.methods.OnMouseDown, item.methods.OnClick
				WritePin(record, pin, "SetScript", "OnMouseUp", function(button, mouse, inside)
					if Secret(inside) or (type(inside) ~= "nil" and type(inside) ~= "boolean") then record.failed = true error("quest click input unavailable", 0) end
					runNative(onUp, button, mouse, inside)
					if inside then runNative(onClick, button, mouse) end
				end)
				WritePin(record, pin, "SetScript", "OnMouseDown", function(button, ...) runNative(onDown, button, ...) end)
				WritePin(record, pin, "SetScript", "OnClick", nil)
			end
			if motion then
				local onEnter, onLeave = item.methods.OnMouseEnter, item.methods.OnMouseLeave
				WritePin(record, pin, "SetScript", "OnEnter", function(button, ...) runNative(onEnter, button, ...) end)
				WritePin(record, pin, "SetScript", "OnLeave", function(button, ...) runNative(onLeave, button, ...) end)
			end
			item.methods.OnLoad(pin)
			item.loaded = true
			Require(record)
		end
		WritePin(record, pin, "Show")
		local callback, callbackValid, callbackKind = RegistryEntry(record, "Supertracking.OnChanged", pin)
		if not callbackValid or not QuestSame(callback, sources.POIButtonMixin.methods.OnSuperTrackingChanged) then error("quest pin callback unavailable", 0) end
		item.callback = { fn = callback, kind = callbackKind }
		item.methods.OnAcquired(pin)
		Require(record)
		item.methods.CheckMouseButtonPassthrough(pin, "RightButton")
		Require(record)
		if not PinOwned(record, pin) then error("quest acquired pin transferred", 0) end
		return pin
	end
	record.hostMethods = Class(host)
	if not record.hostMethods then return nil, "host" end
	questBridge = record
	local ok = pcall(function()
		Require(record)
		for _, event in ipairs(QUEST_CALLBACKS) do
			local fn, valid = RegistryEntry(record, event)
			if not valid or not QuestSame(fn, nil) then error("quest initial callback slot unavailable", 0) end
		end
		record.pool = sources.CreateUnsecuredFramePool("Button", current.frame, QUEST_TEMPLATE, reset)
		record.poolMethods = Class(record.pool)
		if not record.poolMethods then error("quest pool unavailable", 0) end
		Require(record)
		record.providerMethods.OnAdded(provider, host)
		record.added = true
		if not QuantizerCapture(record) then error("quest quantizer unavailable", 0) end
		Require(record)
		record.providerMethods.OnShow(provider)
		Require(record)
		if not CaptureCallbacks(record, false) then error("quest callbacks unavailable", 0) end
		record.leased = true
		Require(record)
		-- Actual Resize constructs a new SparseGrid using only admitted plain
		-- Lua mixins. No widget setter/callback occurs inside this read group.
		record.resizingGrid = true
		record.providerMethods.OnCanvasSizeChanged(provider)
		record.resizingGrid = nil
		if not QuantizerCapture(record) then error("quest resized quantizer unavailable", 0) end
		Require(record)
	end)
	if not ok then
		record.failed, record.resizingGrid = true, nil
		-- Only known named registrations may become staged leases after a
		-- failed OnShow prefix. An anonymous entry is never inferred as ours.
		if not record.leased and BridgeOwned(record) and CaptureCallbacks(record, false, true) then record.leased = true end
		if record.leased then
			releaseQuestPins(current)
		else
			record.initUnknown = true
			KnownInitCleanup(record)
		end
		return nil, "initialization"
	end
	local refreshed, reason = M:RefreshWorldQuestPins()
	if not refreshed then
		releaseQuestPins(current)
		return nil, reason
	end
	return true
end

function M:RefreshWorldQuestPins()
	if not QuestSame(self, M) then return nil, "owner" end
	local record = questBridge
	if not record then return nil, "context" end
	if record.busy then return nil, "busy" end
	if not BridgeCurrent(record) or not CaptureCallbacks(record, true) then
		record.failed = true
		return nil, "context"
	end
	local snapshot = Call(record.snapshotMethod, M, record.sourceMapID)
	if not Plain(snapshot) or not Number(snapshot.capacity) or snapshot.capacity > record.capacity
		or not QuestSame(Call(snapshot.current), true) then return nil, "allocation" end
	record.snapshot, record.busy, record.refreshing, record.didRefresh = snapshot, true, true, nil
	record.filter = nil
	local ok = pcall(function()
		record.providerMethods.RefreshAllData(record.provider)
		Require(record)
		if not QuestSame(Call(snapshot.current), true) then error("quest query changed", 0) end
		if not record.didRefresh or not record.filter or record.filter.next ~= #record.filter.sequence + 1 then error("quest acquisition sequence incomplete", 0) end
	end)
	record.busy, record.refreshing = nil, nil
	if not ok then record.failed = true return nil, "refresh" end
	if not redrawQuestPins(record.view) then return nil, "presentation" end
	return true
end

function M:ReleaseWorldQuestPins()
	if not QuestSame(self, M) or busy then return nil, "owner" end
	return releaseQuestPins(view)
end
