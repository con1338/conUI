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
	if not (minimap and minimap.GetWidth and type(north) == "number" and type(west) == "number") then return nil end
	local radius = C_Minimap and C_Minimap.GetViewRadius and E.Plain(Try(C_Minimap.GetViewRadius))
	if type(radius) ~= "number" or radius <= 0 then return nil end
	local rotate = GetCVar and GetCVar("rotateMinimap") == "1"
	local facing = rotate and E.Plain(GetPlayerFacing and Try(GetPlayerFacing)) or 0
	if type(facing) ~= "number" then facing = 0 end
	local half, square = minimap:GetWidth() / 2, self:MinimapShape() == "SQUARE"
	-- Turn the world by -facing so ahead is up.
	local turned, co, si = rotate and facing ~= 0, cos(facing), -sin(facing)
	local view = into or {}
	view.same = into ~= nil and view.minimap == minimap and view.half == half and view.radius == radius
		and view.square == square and view.rotate == turned and view.co == co and view.si == si
		and view.north == north and view.west == west
	view.minimap, view.half, view.radius, view.square = minimap, half, radius, square
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
