-- EldoUI map pins: one switch for every EldoUI pin on the world map and the
-- minimap, and one minimap projection for every module that draws pins.
--
-- Several modules draw their own pins (Map Notes, Waypoints, Gathering, the
-- Loot Guide's entrances on the DungeonMaps overlay). Each one registers a
-- pin layer here and asks before it draws:
--
--   E:RegisterMapPinLayer(id, {
--     title = "Waypoints",            -- menu label
--     order = 50,                     -- menu order
--     available = fn() -> bool,       -- the module is on (menu lists it)
--     count = fn(uiMapID) -> number,  -- pins on that map (menu count), optional
--     refresh = fn(),                 -- redraw now
--     continent = true,               -- map level, see below (optional)
--   })
--   E:MapPinsShown()                    all EldoUI pins on?
--   E:SetMapPinsShown(on)               flip all of them (map button, keybind)
--   E:MapPinGroupShown(id[, where[, uiMapID]])
--                                       where = "world" | "minimap"; with
--                                       uiMapID the map level rule counts too
--   E:SetMapPinGroupShown(id, on)
--   E:RefreshAllMapPins()               every layer redraws
--   E:MapPinLayers()                    { layer, ... } in menu order
--   E:RescaleMapPins(map, pins[, count]) world map zoom: drawn pins keep
--                                       their place and size (pin.mapX/mapY)
--   E:FollowMap(map, follower)          a layer follows a map's changes,
--                                       zoom, show and hide (see below)
--
-- Map level: every group shows on zone, city and dungeon maps. On a
-- continent, world or cosmic map (E:IsWideMap) only some do, so the big
-- maps stay readable. A layer's `continent` field says how:
--   true / false   the default of the player's "Also on continent maps" tick for
--                  the group (Map Notes' continentGroups[id] holds the tick)
--   "never"        zone and city maps only, with no tick (City services)
--   "own"          the pins are not drawn by EldoUI, so no rule applies
--   nil            shown, as before the rule existed
-- A layer whose module keeps the setting itself gives
-- `continentSetting = { get = fn() -> bool, set = fn(on) }` instead.
-- Like the switch, the rule lives in Map Notes: with Map Notes off every
-- group shows on every map.
--   E:IsWideMap(uiMapID)                continent, world or cosmic map?
--   E:MapPinGroupOnMap(id, uiMapID)     the map level rule alone
--   E:MapPinGroupOnWideMaps(id)         does the group show on wide maps?
--   E:MapPinGroupWideTick(id)           can the player choose it (bool)?
--   E:SetMapPinGroupOnWideMaps(id, on)
-- The state lives in Map Notes' settings (the module that owns the map
-- button). With Map Notes off, everything shows, which is how EldoUI
-- behaved before the switch existed.
--
-- E:MinimapShape() -> "SQUARE" | "ROUND": EldoUI's own minimap is square by
-- default, and nothing defined GetMinimapShape for it, so pin clamping used
-- to treat it as round.
--
-- Minimap projection (shared by Map Notes, Gathering and the Loot Guide):
--   local view = E:MinimapView(north, west)
--     the player's world position in, a view out (nil when the minimap
--     gives no view radius): its half width, the view radius (the zoom),
--     the shape and the turn when "Rotate minimap" is on
--   local px, py, outside = E:MinimapOffset(view, north, west[, clamp])
--     a world position as an offset from the minimap's center in its own
--     pixels (east right, north up); outside is true past the round or
--     square edge, and clamp = true moves such a point onto the edge
--   local x, y = E:MinimapEdgePoint(angle, squarePad, roundPad)
--     a point on the minimap's edge at angle degrees (buttons around it)
local _, E = ...

local sqrt, max, abs, cos, sin = math.sqrt, math.max, math.abs, math.cos, math.sin

local layers, layerOrder = {}, {}

local function Source()
	local module = E.GetModule and E:GetModule("MapNotes")
	if module and module.active and module.db then return module.db end
end

function E:RegisterMapPinLayer(id, info)
	if type(id) ~= "string" or type(info) ~= "table" then return end
	if not layers[id] then layerOrder[#layerOrder + 1] = id end
	info.id = id
	layers[id] = info
	table.sort(layerOrder, function(a, b)
		local oa, ob = layers[a].order or 50, layers[b].order or 50
		if oa ~= ob then return oa < ob end
		return a < b
	end)
	return info
end

function E:MapPinLayer(id)
	return layers[id]
end

---------------------------------------------------------------------------
-- Draw order: one fixed order for EldoUI's pins on the world map and the
-- minimap, lowest first, the way the game layers its own map:
--   1 gathering nodes
--   2 rares, treasures, attunements, notes from the note addon bridge
--   3 city services, note packs, transport, instance entrances
--   4 quest givers
--   5 your own notes
--   6 waypoints
-- The game's quest objectives, group members and the player arrow stay on
-- top. A pin keeps the strata of the map it is drawn on.
--   E:MapPinTier(id)                    the tier of a layer (1-6)
--   E:PlaceMapPin(pin, id, map, canvas)  world map: the layer's frame level
--   E:PlaceMinimapPin(pin, id, minimap)  minimap: the layer's frame level
---------------------------------------------------------------------------
local TIERS = {
	gathering = 1,
	classicRares = 2, metRares = 2, attunements = 2, handynotes = 2,
	services = 3, transport = 3, entrances = 3,
	zonequests = 4,
	user = 5,
	waypoints = 6,
}
local TOP_TIER = 6
-- The game's pins EldoUI's stay under, lowest first.
local GAME_ABOVE = { "PIN_FRAME_LEVEL_ACTIVE_QUEST", "PIN_FRAME_LEVEL_GROUP_MEMBER" }

function E:MapPinTier(id)
	return TIERS[id] or 3
end

local function Read(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, value = pcall(fn, ...)
	if ok then return value end
end

local function Plain(value)
	return not (issecretvalue and issecretvalue(value)) and type(value) == "number" and value == value
end

-- The lowest start of the game's top pins on this map, read from the
-- map's pin level manager (read only), or nil where there is none.
local function GameTop(map)
	local getManager = map and map.GetPinFrameLevelsManager
	local manager = getManager and Read(getManager, map)
	local start = type(manager) == "table" and manager.GetFrameLevelStart
	if type(start) ~= "function" then return nil end
	local top
	for _, kind in ipairs(GAME_ABOVE) do
		local level = Read(start, manager, kind)
		if Plain(level) and level > TOP_TIER and (not top or level < top) then top = level end
	end
	return top
end

function E:MapPinLevel(id, map, canvas)
	local tier = self:MapPinTier(id)
	local top = GameTop(map)
	if top then return top - (TOP_TIER + 1 - tier) end
	-- No level manager (another map window): high above the map's own
	-- art, in the same order.
	local base = canvas and Read(canvas.GetFrameLevel, canvas)
	return (Plain(base) and base or 1) + 500 + tier
end

function E:PlaceMapPin(pin, id, map, canvas)
	local level = self:MapPinLevel(id, map, canvas)
	if pin.eldoLevel ~= level then
		pin.eldoLevel = level
		pin:SetFrameLevel(level)
	end
end

local minimapPins = setmetatable({}, { __mode = "k" })
local minimapPinClicks

-- Minimap pins stay drawn while the large map lets world clicks through.
-- Only these EldoUI buttons are tracked, including ones allocated later.
local function ClearPinClicks(pin)
	if not minimapPinClicks or minimapPinClicks[pin] ~= nil or E.FrameCheck(pin, "IsProtected") then return end
	local enabled = E.FrameMouse(pin, "IsMouseClickEnabled")
	if enabled == nil then return end
	minimapPinClicks[pin] = enabled
	if enabled then pin:SetMouseClickEnabled(false) end
end

function E:SetMinimapPinClickThrough(on)
	if on then
		if minimapPinClicks then return end
		minimapPinClicks = setmetatable({}, { __mode = "k" })
		for pin in pairs(minimapPins) do ClearPinClicks(pin) end
	elseif minimapPinClicks then
		local saved = minimapPinClicks
		minimapPinClicks = nil
		for pin, enabled in pairs(saved) do
			if enabled and not E.FrameCheck(pin, "IsProtected") then pin:SetMouseClickEnabled(true) end
		end
	end
end

function E:PlaceMinimapPin(pin, id, minimap)
	minimapPins[pin] = true
	ClearPinClicks(pin)
	local level = minimap:GetFrameLevel() + 2 + self:MapPinTier(id)
	if pin.eldoLevel ~= level then
		pin.eldoLevel = level
		pin:SetFrameLevel(level)
	end
end

function E:MapPinLayers()
	local list = {}
	for _, id in ipairs(layerOrder) do list[#list + 1] = layers[id] end
	return list
end

function E:MapPinsShown()
	local db = Source()
	if not db then return true end
	return db.shown ~= false
end

function E:MapPinGroupShown(id, where, uiMapID)
	local db = Source()
	if not db then return true end
	if db.shown == false then return false end
	if where == "world" and db.worldPins == false then return false end
	if where == "minimap" and db.minimapPins == false then return false end
	local groups = db.groups
	if type(groups) == "table" and id and groups[id] == false then return false end
	if where ~= "minimap" and not self:MapPinGroupOnMap(id, uiMapID) then return false end
	return true
end

---------------------------------------------------------------------------
-- Map level: zone maps show every group, continent and world maps only some
---------------------------------------------------------------------------
-- The game's own map type decides: a continent, world or cosmic map is
-- wide; a zone, city, dungeon or micro map is not. A map the game gives no
-- type for counts as a zone map.
function E:IsWideMap(uiMapID)
	uiMapID = E.Plain(uiMapID)
	if type(uiMapID) ~= "number" or not (C_Map and C_Map.GetMapInfo) then return false end
	local ok, info = pcall(C_Map.GetMapInfo, uiMapID)
	local kind = ok and type(info) == "table" and E.Plain(info.mapType)
	if type(kind) ~= "number" then return false end
	local types = Enum and Enum.UIMapType
	local cosmic, world, continent = types and types.Cosmic or 0, types and types.World or 1, types and types.Continent or 2
	return kind == cosmic or kind == world or kind == continent
end

-- Can the player choose whether this group shows on continent maps?
function E:MapPinGroupWideTick(id)
	local layer = layers[id]
	if not layer then return false end
	if layer.continentSetting then return true end
	local rule = layer.continent
	return rule == true or rule == false
end

function E:MapPinGroupOnWideMaps(id)
	local layer = layers[id]
	if not layer then return true end
	local setting = layer.continentSetting
	if type(setting) == "table" and type(setting.get) == "function" then
		local ok, on = pcall(setting.get)
		return ok and on and true or false
	end
	local rule = layer.continent
	if rule == "never" then return false end
	if rule ~= true and rule ~= false then return true end
	local db = Source()
	if not db then return true end
	local ticks, on = db.continentGroups, nil
	if type(ticks) == "table" then on = ticks[id] end
	if on == nil then return rule end
	return on and true or false
end

function E:MapPinGroupOnMap(id, uiMapID)
	if uiMapID == nil or not Source() or not self:IsWideMap(uiMapID) then return true end
	return self:MapPinGroupOnWideMaps(id)
end

function E:SetMapPinGroupOnWideMaps(id, on)
	if not self:MapPinGroupWideTick(id) then return end
	local layer = layers[id]
	local setting = layer.continentSetting
	if type(setting) == "table" and type(setting.set) == "function" then
		local ok, err = pcall(setting.set, on and true or false)
		if not ok then geterrorhandler()(err) end
	else
		local db = Source()
		if not db then return end
		if type(db.continentGroups) ~= "table" then db.continentGroups = {} end
		db.continentGroups[id] = on and true or false
	end
	self:RefreshAllMapPins()
end

function E:RefreshAllMapPins()
	for _, id in ipairs(layerOrder) do
		local layer = layers[id]
		if layer.refresh then
			local ok, err = pcall(layer.refresh)
			if not ok then geterrorhandler()(err) end
		end
	end
	if self.RefreshMapPins then self:RefreshMapPins() end
end

-- World map zoom: the pins already drawn keep their place and size on the
-- new canvas scale, without reading their lists again. Each pin keeps the
-- map position it was drawn at in pin.mapX, pin.mapY (0-1). False when the
-- canvas cannot be read; the caller then draws the pins again.
function E:RescaleMapPins(map, pins, count)
	local canvas = map and map.GetCanvas and map:GetCanvas()
	if not canvas then return false end
	local width, height = canvas:GetSize()
	if not width or width <= 0 or not height then return false end
	local ok, scale = true, 1
	if map.GetCanvasScale then ok, scale = pcall(map.GetCanvasScale, map) end
	scale = ok and type(scale) == "number" and scale > 0 and scale or 1
	local size = 1 / max(scale, 0.01)
	for index = 1, count or #pins do
		local pin = pins[index]
		if pin and pin.mapX and pin:IsShown() then
			pin:SetScale(size)
			pin:ClearAllPoints()
			pin:SetPoint("CENTER", canvas, "TOPLEFT", pin.mapX * width * scale, -pin.mapY * height * scale)
		end
	end
	return true
end

-- Map followers: a layer that draws its own frames on a map canvas follows
-- the map through post-hooks on the map's own methods and scripts, and never
-- joins the map's data provider list. The map calls every data provider in
-- one loop, so an EldoUI function in that list would leave the rest of the
-- loop, and the game's quest and area pins after it, running as addon code.
-- A follower is a table with any of these handlers (all optional):
--   RefreshAllData, OnMapChanged, OnCanvasScaleChanged, OnCanvasSizeChanged,
--   OnGlobalAlphaChanged, OnShow, OnHide
-- follower.owningMap is the map. E:FollowMap(map, follower) adds it and
-- refreshes it once; adding it again does nothing.
local mapFollowers = {}
local FOLLOWED = {
	RefreshAllDataProviders = "RefreshAllData",
	OnMapChanged = "OnMapChanged",
	OnCanvasScaleChanged = "OnCanvasScaleChanged",
	OnCanvasSizeChanged = "OnCanvasSizeChanged",
	SetGlobalAlpha = "OnGlobalAlphaChanged",
}

local function NotifyFollowers(list, handler)
	for _, follower in ipairs(list) do
		local fn = follower[handler]
		if type(fn) == "function" then
			local ok, err = pcall(fn, follower)
			if not ok then geterrorhandler()(err) end
		end
	end
end

function E:FollowMap(map, follower)
	if type(map) ~= "table" or type(follower) ~= "table" then return false end
	local list = mapFollowers[map]
	if not list then
		list = {}
		mapFollowers[map] = list
		for method, handler in pairs(FOLLOWED) do
			if type(map[method]) == "function" then
				hooksecurefunc(map, method, function() NotifyFollowers(list, handler) end)
			end
		end
		if map.HookScript then
			map:HookScript("OnShow", function() NotifyFollowers(list, "OnShow") end)
			map:HookScript("OnHide", function() NotifyFollowers(list, "OnHide") end)
		end
	end
	for _, known in ipairs(list) do
		if known == follower then return true end
	end
	list[#list + 1] = follower
	follower.owningMap = map
	if type(follower.RefreshAllData) == "function" then
		local ok, err = pcall(follower.RefreshAllData, follower)
		if not ok then geterrorhandler()(err) end
	end
	return true
end

function E:SetMapPinsShown(on)
	local db = Source()
	if not db then return end
	db.shown = on and true or false
	self:RefreshAllMapPins()
end

function E:SetMapPinGroupShown(id, on)
	local db = Source()
	if not (db and id) then return end
	if type(db.groups) ~= "table" then db.groups = {} end
	db.groups[id] = on and true or false
	self:RefreshAllMapPins()
end

function E:MinimapShape()
	local minimap = self.GetModule and self:GetModule("Minimap")
	if minimap and minimap.active and minimap.db then
		return minimap.db.shape == "round" and "ROUND" or "SQUARE"
	end
	local fn = rawget(_G, "GetMinimapShape")
	if type(fn) == "function" then
		local ok, shape = pcall(fn)
		if ok and shape == "SQUARE" then return "SQUARE" end
	end
	return "ROUND"
end

---------------------------------------------------------------------------
-- Minimap projection
---------------------------------------------------------------------------
local function Try(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, value = pcall(fn, ...)
	if ok then return value end
end

-- into (optional): a table of the caller's own, filled and returned
-- instead of a new one; its `same` is true when nothing that places a pin
-- changed since the last fill (position, facing, zoom, size, shape).
function E:MinimapView(north, west, minimap, into)
	minimap = minimap or _G.Minimap
	if not (minimap and minimap.GetWidth and type(north) == "number" and type(west) == "number") or E.Secret(north) or E.Secret(west) then return nil end
	local radius = C_Minimap and C_Minimap.GetViewRadius and E.Plain(Try(C_Minimap.GetViewRadius))
	if type(radius) ~= "number" or radius <= 0 then return nil end
	local rotate = E.PlainCall(GetCVar, "rotateMinimap") == "1"
	local facing = rotate and E.Plain(GetPlayerFacing and Try(GetPlayerFacing)) or 0
	if type(facing) ~= "number" then facing = 0 end
	local width = E.PlainCall(minimap.GetWidth, minimap)
	local height = E.PlainCall(minimap.GetHeight, minimap)
	if type(width) ~= "number" or width <= 0 or type(height) ~= "number" or height <= 0 then return end
	local half, square = width / 2, self:MinimapShape() == "SQUARE"
	-- Turn the world by -facing so ahead is up.
	local turned, co, si = rotate and facing ~= 0, cos(facing), -sin(facing)
	local view = into or {}
	view.same = into ~= nil and view.minimap == minimap and view.half == half and view.height == height and view.radius == radius
		and view.square == square and view.rotate == turned and view.co == co and view.si == si
		and view.north == north and view.west == west
	view.minimap, view.half, view.radius, view.square, view.height = minimap, half, radius, square, height
	view.rotate, view.co, view.si, view.north, view.west = turned, co, si, north, west
	return view
end

function E:MinimapOffset(view, north, west, clamp)
	local east, up = view.west - west, north - view.north
	if view.rotate then
		east, up = east * view.co - up * view.si, east * view.si + up * view.co
	end
	local half = view.half
	local px, py = east / view.radius * half, up / view.radius * half
	local m = view.square and max(abs(px), abs(py)) or sqrt(px * px + py * py)
	local outside = m > half
	if outside and clamp then px, py = px * half / m, py * half / m end
	return px, py, outside
end

function E:MinimapEdgePoint(angle, squarePad, roundPad, minimap)
	minimap = minimap or _G.Minimap
	if not minimap then return 0, 0 end
	local rad = math.rad(tonumber(angle) or 0)
	local x, y = cos(rad), sin(rad)
	local w, h = minimap:GetWidth() / 2, minimap:GetHeight() / 2
	if self:MinimapShape() == "SQUARE" then
		local edge = max(abs(x), abs(y))
		return x / edge * (w + (squarePad or 0)), y / edge * (h + (squarePad or 0))
	end
	return x * (w + (roundPad or 0)), y * (h + (roundPad or 0))
end

---------------------------------------------------------------------------
-- Modifier right-clicks on the world map
---------------------------------------------------------------------------
-- A module that acts on Ctrl+ or Alt+right-click on the world map
-- registers here:
--
--   E:RegisterMapRightClick(id, {
--     modifier = "ctrl" | "alt",      -- held alone (Shift never)
--     wants = fn() -> bool,           -- the module wants the click now
--     click = fn(uiMapID, x, y),      -- x, y: 0..1 on that map
--   })
--
-- While a wanted modifier is held, out of combat, one EldoUI frame lies
-- over the map's scroll area and takes only the right button: the map never
-- sees that click, so it keeps its zone and zoom. Every other button and a
-- plain right-click reach the map as before; in combat the frame is hidden
-- and nothing changes.
local clickHandlers, clickOrder = {}, {}
local catcher

local function KeyDown(fn) return type(fn) == "function" and fn() == true end

local function HeldModifier()
	if KeyDown(IsShiftKeyDown) then return nil end
	local ctrl, alt = KeyDown(IsControlKeyDown), KeyDown(IsAltKeyDown)
	if ctrl and not alt then return "ctrl" end
	if alt and not ctrl then return "alt" end
end

local function ClickHandler(modifier)
	if not modifier then return nil end
	for _, id in ipairs(clickOrder) do
		local handler = clickHandlers[id]
		if handler.modifier == modifier then
			local ok, wants = pcall(handler.wants or function() return true end)
			if ok and wants then return handler end
		end
	end
end

local function MapContainer()
	local map = rawget(_G, "WorldMapFrame")
	return map, map and map.ScrollContainer
end

local function OnCatcherMouseUp(_, button)
	if button ~= "RightButton" then return end
	local handler = ClickHandler(HeldModifier())
	local map, container = MapContainer()
	if not (handler and container and container.GetNormalizedCursorPosition and map.GetMapID) then return end
	local x, y = container:GetNormalizedCursorPosition()
	local uiMapID = map:GetMapID()
	if E.Secret(x) or E.Secret(y) or E.Secret(uiMapID) then return end
	if type(x) == "number" and type(y) == "number" and type(uiMapID) == "number" and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
		local ok, err = pcall(handler.click, uiMapID, x, y)
		if not ok then geterrorhandler()(err) end
	end
end

-- The frame is made out of combat, the first time a modifier is held.
local function Catcher()
	if catcher or InCombatLockdown() then return catcher end
	local _, container = MapContainer()
	if not (container and container.GetFrameLevel) then return nil end
	catcher = CreateFrame("Frame", nil, container)
	catcher:SetAllPoints(container)
	catcher:SetFrameLevel(math.min(container:GetFrameLevel() + 1000, 9000))
	catcher:EnableMouse(true)
	if catcher.SetPassThroughButtons then
		pcall(catcher.SetPassThroughButtons, catcher, "LeftButton", "MiddleButton", "Button4", "Button5")
	end
	catcher:SetScript("OnMouseUp", OnCatcherMouseUp)
	catcher:Hide()
	E.mapClickCatcher = catcher
	return catcher
end

local function UpdateCatcher()
	local wanted = not InCombatLockdown() and ClickHandler(HeldModifier()) ~= nil
	local frame = wanted and Catcher() or catcher
	if frame then frame:SetShown(wanted) end
end
E.UpdateMapClickCatcher = UpdateCatcher

function E:RegisterMapRightClick(id, info)
	if type(id) ~= "string" or type(info) ~= "table" or type(info.click) ~= "function" then return end
	if not clickHandlers[id] then clickOrder[#clickOrder + 1] = id end
	clickHandlers[id] = info
	if #clickOrder == 1 then
		E:RegisterEvent("MODIFIER_STATE_CHANGED", UpdateCatcher, clickHandlers)
		E:RegisterEvent("PLAYER_REGEN_DISABLED", UpdateCatcher, clickHandlers)
		E:RegisterEvent("PLAYER_REGEN_ENABLED", UpdateCatcher, clickHandlers)
	end
end

-- One visible-map clock serves the layers that currently have pins.
local minimapUpdates, minimapView = {}, {}
local minimapTick = "MapPins:minimap"
local minimapHooks, minimapUpdating
local minimapMap, minimapValid, minimapHybrid

function E:ReadMinimapHybrid()
	local reader = C_Minimap and C_Minimap.ShouldUseHybridMinimap
	if type(reader) ~= "function" then return false end
	local hybrid = E.PlainCall(reader)
	if type(hybrid) == "boolean" then return hybrid end
end

local function UpdateMinimapLayers(force)
	if minimapUpdating or not next(minimapUpdates) then return end
	local map = _G.Minimap
	if not map or not map:IsVisible() then return end
	local waypoint = E.Waypoints
	if not waypoint or not waypoint.SharedPlayerPos then return end
	local mapID, _, _, continent, north, west = waypoint.SharedPlayerPos()
	local view = continent and E:MinimapView(north, west, map, minimapView)
	local valid = view ~= nil and view ~= false
	local hybrid = E:ReadMinimapHybrid()
	local refresh = force or minimapMap ~= mapID or minimapValid ~= valid or minimapHybrid ~= hybrid
	local changed = refresh or (view and not view.same)
	minimapMap, minimapValid, minimapHybrid = mapID, valid, hybrid
	if not view then wipe(minimapView) end
	if not changed then return end
	local sample = { mapID = mapID, continent = continent, north = north, west = west, view = view, hybrid = hybrid, force = refresh }
	minimapUpdating = true
	for _, update in pairs(minimapUpdates) do
		local ok, problem = pcall(update, sample)
		if not ok then geterrorhandler()(problem) end
	end
	minimapUpdating = nil
end

local function WatchMinimapLayers()
	local map = _G.Minimap
	if not map then return end
	if not minimapHooks then
		minimapHooks = true
		map:HookScript("OnHide", function() E.Ticker:Unsubscribe(minimapTick) end)
		map:HookScript("OnShow", function()
			WatchMinimapLayers()
			UpdateMinimapLayers(true)
		end)
	end
	if next(minimapUpdates) and map:IsVisible() then
		if not E.Ticker:IsSubscribed(minimapTick) then
			E.Ticker:Subscribe(minimapTick, 0.1, function() UpdateMinimapLayers(false) end, E)
		end
	else
		E.Ticker:Unsubscribe(minimapTick)
	end
end

function E:SetMinimapUpdater(key, enabled, update)
	if enabled then minimapUpdates[key] = update else minimapUpdates[key] = nil end
	WatchMinimapLayers()
end

function E:HasMinimapUpdater(key)
	return minimapUpdates[key] ~= nil
end

-- During a shared pass every layer reuses the same native view reading.
function E:CurrentMinimapView(north, west, map, into, sample)
	if not sample then return self:MinimapView(north, west, map, into) end
	local source = sample.view
	if not source then return end
	local same = into ~= nil and not sample.force
	for key, value in pairs(source) do
		if key ~= "same" and (not into or into[key] ~= value) then same = false end
	end
	local view = into or {}
	for key, value in pairs(source) do view[key] = value end
	view.same = same
	return view
end

E:RegisterEvent("MINIMAP_UPDATE_ZOOM", function()
	if next(minimapUpdates) then UpdateMinimapLayers(true) end
end, minimapUpdates)
E:RegisterEvent("CVAR_UPDATE", function(_, _, name)
	if E.Plain(name) == "rotateMinimap" and next(minimapUpdates) then UpdateMinimapLayers(true) end
end, minimapUpdates)
