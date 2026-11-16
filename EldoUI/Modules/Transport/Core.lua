-- EldoUI Transport Maps: how to get somewhere. Flight masters,
-- boats, zeppelins, the tram and fixed portals on the world map, per
-- faction, with their destinations.
--
--   * Flight masters come from the game: C_TaxiMap.GetTaxiNodesForMap (with
--     the game's own "not discovered yet" state and faction). Where a
--     flight master flies is learned when you open its flight map
--     (C_TaxiMap.GetAllTaxiNodes, account-wide), and the flight time from
--     the QoL flight timer when you flew that route before.
--   * Boats, zeppelins, the tram and portals come from Data/Transport.lua,
--     a small hand-entered table; a stop not checked in game says so.
--   * Right-click a pin: Set a waypoint (Waypoints, or the game's map pin).
--   * The Routes tab lists the stops of a zone, where each one goes, and the
--     stops elsewhere that arrive there (a plain list, no path finding).
--
-- The pins are EldoUI's own frames on the world map canvas, one layer of
-- the shared map pin switch (Core/MapPins.lua). Each kind has its own
-- shape as well as its own color, so color alone never tells them apart.
-- Nothing is clicked or flown for the player: taking a flight stays the
-- player's own click at the flight master.
local _, E = ...
local L = E.L


local M = E:NewModule("Transport", {
	title = "Transport Maps",
	category = "Quality of Life",
	desc = "Flight masters, boats, zeppelins, the tram and portals on the world map, with where each one goes.",
	movers = {},
	savedKeys = { "profile.modules.Transport" },
	optionsPage = "module:Transport",
	presets = { "Bronze", "Contrast", "Dots", "Icons", "Minimal" },
	reload = false,
	defaults = {
		kinds = { flight = true, boat = true, zeppelin = true, tram = true, portal = true },
		myFaction = true,        -- only your side's (and neutral) stops
		showUnknown = true,      -- flight masters you have not found yet
		continentPins = true,    -- the stops on continent maps too
		pinStyle = "icons",      -- icons | dots | contrast | bronze | minimal
		pinScale = 1,
		pinAlpha = 1,
		tooltipTimes = true,     -- learned flight times in the tooltip
		routeZone = 0,           -- the Routes tab's zone (uiMapID, 0 = where you are)
	},
})
E.Transport = M

local KINDS = { "flight", "boat", "zeppelin", "tram", "portal" }
M.KINDS = KINDS
-- Shown translated: L["Flight master"], L["Boat"], L["Zeppelin"], L["Tram"], L["Portal"]
local KIND_TITLE = { flight = "Flight master", boat = "Boat", zeppelin = "Zeppelin", tram = "Tram", portal = "Portal" }
M.KIND_TITLE = KIND_TITLE
-- One shape and one safe color per kind (E.tokens.palette.safe).
local KIND_SHAPE = { flight = "diamond", boat = "square", zeppelin = "circle", tram = "bar", portal = "ring" }
local KIND_COLOR = { flight = "sky", boat = "blue", zeppelin = "orange", tram = "yellow", portal = "purple" }
M.KIND_SHAPE = KIND_SHAPE
-- The Icons look's symbol per kind (white, tinted with the kind's color);
-- flight masters use the game's own art instead.
local SYMBOLS = "Interface\\AddOns\\EldoUI\\Media\\Textures\\"
M.KIND_SYMBOL = {
	boat = SYMBOLS .. "EldoBoat.tga",
	zeppelin = SYMBOLS .. "EldoZeppelin.tga",
	tram = SYMBOLS .. "EldoTram.tga",
	portal = SYMBOLS .. "EldoPortal.tga",
}
local RING_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local SIZE = 14

local function Try(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a, b, c, d = pcall(fn, ...)
	if ok then return a, b, c, d end
end

local Clean = E.Plain

function M.MapName(uiMapID)
	local info = uiMapID and C_Map and C_Map.GetMapInfo and Try(C_Map.GetMapInfo, uiMapID)
	local name = type(info) == "table" and Clean(info.name)
	return (type(name) == "string" and name ~= "") and name or ("#" .. tostring(uiMapID))
end

local function PlayerFaction()
	local faction = Clean(UnitFactionGroup("player"))
	return (faction == "Alliance" or faction == "Horde") and faction or nil
end

---------------------------------------------------------------------------
-- Saved data
--   E.global.Transport.routes[from][to] = true   flight destinations seen
--                                               on a flight map (account)
--   E.private.Transport.known[nodeID] = true     flight masters this
--                                               character knows
---------------------------------------------------------------------------
local function Routes()
	local store = E:GetGlobal("Transport")
	if type(store) ~= "table" then return {} end
	if type(store.routes) ~= "table" then store.routes = {} end
	return store.routes
end

local function Known()
	local store = E:GetPrivate("Transport")
	if type(store) ~= "table" then return {} end
	if type(store.known) ~= "table" then store.known = {} end
	return store.known
end

local REACHABLE = Enum and Enum.FlightPathState and Enum.FlightPathState.Reachable or 1
local CURRENT = Enum and Enum.FlightPathState and Enum.FlightPathState.Current or 0

-- The flight map is open: remember where this flight master flies.
function M:LearnFlightMap()
	if not (C_TaxiMap and C_TaxiMap.GetAllTaxiNodes) then return end
	local mapID = Clean(Try(rawget(_G, "GetTaxiMapID"))) or (C_Map and Clean(Try(C_Map.GetBestMapForUnit, "player")))
	local nodes = type(mapID) == "number" and Try(C_TaxiMap.GetAllTaxiNodes, mapID)
	if type(nodes) ~= "table" then return end
	local from
	for _, node in ipairs(nodes) do
		if Clean(node.state) == CURRENT then from = Clean(node.name) end
	end
	local known = Known()
	for _, node in ipairs(nodes) do
		local id, state = Clean(node.nodeID), Clean(node.state)
		if id and (state == CURRENT or state == REACHABLE) then known[id] = true end
	end
	if type(from) ~= "string" then return end
	local routes = Routes()
	routes[from] = routes[from] or {}
	for _, node in ipairs(nodes) do
		local name = Clean(node.name)
		if Clean(node.state) == REACHABLE and type(name) == "string" then routes[from][name] = true end
	end
	self:RefreshPins()
end

-- Destinations learned for a flight master, sorted.
function M:FlightDestinations(name)
	local list = {}
	for to in pairs(Routes()[name] or {}) do list[#list + 1] = to end
	table.sort(list)
	return list
end

-- The flight time the QoL flight timer learned, in seconds, or nil.
function M:FlightTime(from, to)
	local qol = E:GetModule("QoL")
	if qol and qol.GetFlightTime then return Try(qol.GetFlightTime, qol, from, to) end
end

---------------------------------------------------------------------------
-- Points
--   { key, kind, uiMapID, x, y, name, faction, destinations = { { name,
--     uiMapID } }, unknown, checked, nodeID }
---------------------------------------------------------------------------
local function FactionShown(self, faction)
	if not self.db.myFaction or not faction then return true end
	local mine = PlayerFaction()
	return not mine or faction == mine
end

local NODE_FACTION = { [1] = "Horde", [2] = "Alliance" }

local function FlightPoints(self, uiMapID, out)
	if not self.db.kinds.flight or not (C_TaxiMap and C_TaxiMap.GetTaxiNodesForMap) then return end
	local nodes = Try(C_TaxiMap.GetTaxiNodesForMap, uiMapID)
	for _, node in ipairs(type(nodes) == "table" and nodes or {}) do
		local id, name = Clean(node.nodeID), Clean(node.name)
		local pos = node.position
		local x, y
		if type(pos) == "table" then
			if pos.GetXY then x, y = Try(pos.GetXY, pos) else x, y = pos.x, pos.y end
		end
		x, y = Clean(x), Clean(y)
		local faction = NODE_FACTION[Clean(node.faction) or 0]
		local undiscovered = Clean(node.isUndiscovered) == true and not (id and Known()[id])
		if id and type(x) == "number" and type(y) == "number" and FactionShown(self, faction)
			and (self.db.showUnknown or not undiscovered) then
			out[#out + 1] = {
				key = "f:" .. id, kind = "flight", uiMapID = uiMapID, x = x, y = y, nodeID = id,
				name = type(name) == "string" and name or L["Flight master"], faction = faction,
				unknown = undiscovered, checked = true, atlas = Clean(node.atlasName),
			}
		end
	end
end

-- Zone rectangle of a child map on a parent map (continent pins).
local function ChildRect(child, parent)
	if not (C_Map and C_Map.GetMapRectOnMap) then return end
	local minX, maxX, minY, maxY = Try(C_Map.GetMapRectOnMap, child, parent)
	minX, maxX, minY, maxY = Clean(minX), Clean(maxX), Clean(minY), Clean(maxY)
	if not (minX and maxX and minY and maxY) or maxX <= minX or maxY <= minY then return end
	return { minX = minX, maxX = maxX, minY = minY, maxY = maxY }
end

local function IsContinent(uiMapID)
	local info = C_Map and C_Map.GetMapInfo and Try(C_Map.GetMapInfo, uiMapID)
	local kind = type(info) == "table" and Clean(info.mapType)
	local continentType = Enum and Enum.UIMapType and Enum.UIMapType.Continent or 2
	return kind == continentType
end

-- Every stop of the data table, with its destinations. The table is the
-- same for the whole session, so it is built once; callers only read it.
local dataStops
function M:DataStops()
	if dataStops then return dataStops end
	local list = {}
	for index, route in ipairs(E.transportData and E.transportData.routes or {}) do
		local stops = route.stops or {}
		for side = 1, 2 do
			local stop, other = stops[side], stops[3 - side]
			if stop and other and not (route.oneWay and side == 2) then
				list[#list + 1] = {
					key = ("d:%d:%d"):format(index, side), kind = route.kind, uiMapID = stop.map, x = stop.x, y = stop.y,
					name = L[stop.name], faction = route.faction, checked = route.checked == true,
					destinations = { { name = L[other.name], uiMapID = other.map } }, route = index,
				}
			elseif stop and other and route.oneWay and side == 2 then
				-- The arrival end of a one-way portal: a pin without destinations.
				list[#list + 1] = {
					key = ("d:%d:%d"):format(index, side), kind = route.kind, uiMapID = stop.map, x = stop.x, y = stop.y,
					name = L[stop.name], faction = route.faction, checked = route.checked == true, arrival = true,
					destinations = {}, route = index,
				}
			end
		end
	end
	dataStops = list
	return list
end

-- Stops at the same spot merge into one pin with every destination.
local function Merge(list)
	local out = {}
	for _, point in ipairs(list) do
		local same
		for _, other in ipairs(out) do
			if other.kind == point.kind and other.uiMapID == point.uiMapID and math.abs(other.x - point.x) < 0.004 and math.abs(other.y - point.y) < 0.004 then
				same = other
				break
			end
		end
		if same then
			for _, dest in ipairs(point.destinations or {}) do same.destinations[#same.destinations + 1] = dest end
			same.checked = same.checked and point.checked
		else
			local copy = {}
			for key, value in pairs(point) do copy[key] = value end
			copy.destinations = {}
			for _, dest in ipairs(point.destinations or {}) do copy.destinations[#copy.destinations + 1] = dest end
			out[#out + 1] = copy
		end
	end
	return out
end

local function DataPoints(self, uiMapID, out, rect)
	for _, stop in ipairs(self:DataStops()) do
		if stop.uiMapID == uiMapID and self.db.kinds[stop.kind] and FactionShown(self, stop.faction) then
			local point = stop
			if rect then
				point = {}
				for key, value in pairs(stop) do point[key] = value end
				point.zoneX, point.zoneY = stop.x, stop.y
				point.x = rect.minX + stop.x * (rect.maxX - rect.minX)
				point.y = rect.minY + stop.y * (rect.maxY - rect.minY)
			end
			out[#out + 1] = point
		end
	end
end

-- Every pin on a map, after the kind and faction settings.
function M:Points(uiMapID)
	local out = {}
	if type(uiMapID) ~= "number" then return out end
	FlightPoints(self, uiMapID, out)
	DataPoints(self, uiMapID, out)
	if self.db.continentPins and IsContinent(uiMapID) and C_Map.GetMapChildrenInfo then
		local zoneType = Enum and Enum.UIMapType and Enum.UIMapType.Zone or 3
		local children = Try(C_Map.GetMapChildrenInfo, uiMapID, zoneType)
		for _, child in ipairs(type(children) == "table" and children or {}) do
			local childID = Clean(child.mapID)
			local rect = childID and ChildRect(childID, uiMapID)
			if rect then DataPoints(self, childID, out, rect) end
		end
	end
	return Merge(out)
end

---------------------------------------------------------------------------
-- Pins
---------------------------------------------------------------------------
local function KindColor(kind)
	return E.tokens.palette.safe[KIND_COLOR[kind]] or E.tokens.text.body
end

local function CreatePin(parent)
	local pin = CreateFrame("Button", nil, parent)
	pin:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	pin.edge = pin:CreateTexture(nil, "BORDER")
	pin.edge:SetTexture(E.media.flat)
	pin.fill = pin:CreateTexture(nil, "ARTWORK")
	pin.fill:SetTexture(E.media.flat)
	pin.icon = pin:CreateTexture(nil, "OVERLAY")
	pin.mask = pin:CreateMaskTexture()
	pin.mask:SetTexture(RING_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	pin.mask:SetAllPoints()
	pin.hole = pin:CreateTexture(nil, "OVERLAY", nil, 1)
	pin.hole:SetTexture(E.media.flat)
	pin.hover = pin:CreateTexture(nil, "HIGHLIGHT")
	pin.hover:SetAllPoints()
	pin.hover:SetTexture(E.media.flat)
	pin.hover:SetVertexColor(1, 1, 1, E.tokens.hover.control)
	pin:SetScript("OnEnter", function(self) M:PinTooltip(self) end)
	pin:SetScript("OnLeave", function() GameTooltip:Hide() end)
	pin:SetScript("OnClick", function(self, button)
		if button == "RightButton" then M:PinMenu(self) end
	end)
	return pin
end

local function SetMasked(pin, on)
	if pin.masked == on then return end
	pin.masked = on
	for _, region in ipairs({ pin.edge, pin.fill }) do
		if on then region:AddMaskTexture(pin.mask) else region:RemoveMaskTexture(pin.mask) end
	end
end

-- The look of each pin style: edge color, fill, size factor and alpha.
-- Edges are the HUD edge token (black) or white for High contrast; fills
-- are the color-blind safe palette.
local function Edge(alpha)
	local c = E.tokens.edge.hud
	return { c[1], c[2], c[3], alpha or c[4] or 1 }
end

local function StyleLook(style, kind, unknown)
	local color = KindColor(kind)
	if unknown then color = E.tokens.palette.safe.gray end
	if style == "contrast" then
		return { edge = { 1, 1, 1, 1 }, fill = color, scale = 1.35, alpha = 1, icon = false, edgeSize = 2 }
	elseif style == "bronze" then
		local border = E.media.borderColor
		return { edge = { border[1], border[2], border[3], 1 }, fill = color, scale = 1.1, alpha = 1, icon = false, edgeSize = 2,
			bronze = true }
	elseif style == "minimal" then
		return { edge = Edge(0.8), fill = color, scale = 0.7, alpha = 0.75, icon = false, edgeSize = 1 }
	elseif style == "dots" then
		return { edge = Edge(0.9), fill = color, scale = 0.85, alpha = 1, icon = false, edgeSize = 1 }
	end
	return { edge = Edge(), fill = color, scale = 1, alpha = 1, icon = true, edgeSize = 1 }
end

function M:StylePin(pin, point)
	pin.point = point
	local look = StyleLook(self.db.pinStyle, point.kind, point.unknown)
	local size = math.max(6, SIZE * look.scale * (tonumber(self.db.pinScale) or 1))
	local shape = KIND_SHAPE[point.kind] or "square"
	if self.db.pinStyle == "dots" or self.db.pinStyle == "minimal" then shape = "circle" end
	-- Icons look: the kind's symbol on a round dark backing, full height for
	-- the tram too. A symbol the client cannot load leaves the plain shape.
	local symbol = look.icon and self.KIND_SYMBOL[point.kind]
	pin.icon:SetTexCoord(0, 1, 0, 1)
	pin.icon:SetVertexColor(1, 1, 1, 1)
	pin.icon:SetDesaturated(false)
	if symbol and pin.icon:SetTexture(symbol) == false then symbol = nil end
	if symbol then shape = "circle" end
	pin:SetSize(size, size)
	pin:SetAlpha((tonumber(self.db.pinAlpha) or 1) * look.alpha * (point.unknown and 0.6 or 1))
	local px = (E.pixel or 1) * look.edgeSize
	for _, region in ipairs({ pin.edge, pin.fill, pin.hole, pin.icon }) do
		region:ClearAllPoints()
		region:SetRotation(0)
		region:Show()
	end
	pin.icon:Hide()
	pin.hole:Hide()
	SetMasked(pin, shape == "circle" or shape == "ring")
	pin.edge:SetVertexColor(look.edge[1], look.edge[2], look.edge[3], look.edge[4] or 1)
	pin.fill:SetVertexColor(look.fill[1], look.fill[2], look.fill[3], 1)
	if symbol then
		local back = E.media.backdropColor
		pin.fill:SetVertexColor(back[1], back[2], back[3], 1)
		pin.icon:SetPoint("CENTER")
		pin.icon:SetSize(size * 0.8, size * 0.8)
		pin.icon:SetVertexColor(look.fill[1], look.fill[2], look.fill[3], 1)
		pin.icon:Show()
	end
	if shape == "bar" then
		pin.edge:SetPoint("LEFT")
		pin.edge:SetPoint("RIGHT")
		pin.edge:SetHeight(size * 0.5)
	else
		pin.edge:SetAllPoints()
	end
	pin.fill:SetPoint("TOPLEFT", pin.edge, "TOPLEFT", px, -px)
	pin.fill:SetPoint("BOTTOMRIGHT", pin.edge, "BOTTOMRIGHT", -px, px)
	if shape == "diamond" then
		pin.edge:ClearAllPoints()
		pin.edge:SetPoint("CENTER")
		pin.edge:SetSize(size * 0.72, size * 0.72)
		pin.edge:SetRotation(math.pi / 4)
		pin.fill:SetRotation(math.pi / 4)
	elseif shape == "ring" then
		-- A ring: the fill with a hole in the backdrop color.
		local back = E.media.backdropColor
		pin.hole:SetPoint("CENTER")
		pin.hole:SetSize(size * 0.42, size * 0.42)
		pin.hole:SetVertexColor(back[1], back[2], back[3], 1)
		pin.hole:AddMaskTexture(pin.mask)
		pin.hole:Show()
	end
	-- Icons style: the game's own flight master art where the game names it.
	if look.icon and point.kind == "flight" and point.atlas then
		local _, found = E:ClientAtlas(point.atlas)
		if found then
			pin.edge:Hide()
			pin.fill:Hide()
			pin.icon:SetAllPoints()
			E:SetClientAtlas(pin.icon, point.atlas)
			pin.icon:SetDesaturated(point.unknown and true or false)
			pin.icon:Show()
		end
	end
end

local worldPins = {}
local provider

local function WorldMap()
	local map = _G.WorldMapFrame
	return (type(map) == "table" and map.GetCanvas) and map or nil
end

function M:HidePins()
	for _, pin in ipairs(worldPins) do pin:Hide() pin.point = nil end
	self.pinCount = 0
end

function M:RefreshPins()
	local map = WorldMap()
	self:HidePins()
	if not (self.active and map and map.IsShown and map:IsShown()) then return end
	if not E:MapPinGroupShown("transport", "world") then return end
	local canvas = map:GetCanvas()
	local shownMap = map.GetMapID and Clean(map:GetMapID())
	if not (canvas and shownMap) then return end
	if not E:MapPinGroupOnMap("transport", shownMap) then return end
	local width, height = canvas:GetSize()
	if not width or width <= 0 then return end
	local scale = map.GetCanvasScale and Try(map.GetCanvasScale, map) or 1
	local count = 0
	for _, point in ipairs(self:Points(shownMap)) do
		count = count + 1
		local pin = worldPins[count]
		if not pin then
			pin = CreatePin(canvas)
			worldPins[count] = pin
		end
		E:PlaceMapPin(pin, "transport", map, canvas)
		pin:SetScale(1 / math.max(scale or 1, 0.01))
		self:StylePin(pin, point)
		pin.mapX, pin.mapY = point.x, point.y
		pin:ClearAllPoints()
		pin:SetPoint("CENTER", canvas, "TOPLEFT", point.x * width * (scale or 1), -point.y * height * (scale or 1))
		pin:Show()
	end
	self.pinCount = count
end

local function CreateProvider()
	local p = {}
	function p:RemoveAllData() M:HidePins() end
	function p:RefreshAllData() M:RefreshPins() end
	function p:OnMapChanged() M:RefreshPins() end
	function p:OnCanvasScaleChanged()
		if not E:RescaleMapPins(WorldMap(), worldPins, M.pinCount) then M:RefreshPins() end
	end
	function p:OnCanvasSizeChanged() M:RefreshPins() end
	function p:OnShow() M:RefreshPins() end
	function p:OnHide() M:HidePins() end
	return p
end

function M:HookWorldMap()
	local map = WorldMap()
	if not map or self.worldHooked then return end
	self.worldHooked = true
	provider = provider or CreateProvider()
	E:FollowMap(map, provider)
end

---------------------------------------------------------------------------
-- Tooltip and menu
---------------------------------------------------------------------------
local function Secondary() return unpack(E.tokens.text.secondary) end

local function FormatTime(seconds)
	seconds = math.floor((tonumber(seconds) or 0) + 0.5)
	return ("%d:%02d"):format(math.floor(seconds / 60), seconds % 60)
end

function M:PinTooltip(pin)
	local point = pin.point
	if not point then return end
	local tooltip = GameTooltip
	tooltip:SetOwner(pin, point.x > 0.66 and "ANCHOR_LEFT" or "ANCHOR_RIGHT")
	E.UIKit.TipTitle(tooltip, point.name)
	local kind = L[KIND_TITLE[point.kind] or "Boat"]
	if point.faction then kind = kind .. " · " .. (point.faction == "Alliance" and L["Alliance"] or L["Horde"]) end
	tooltip:AddLine(kind, Secondary())
	if point.kind == "flight" then
		if point.unknown then
			local warn = E.tokens.text.warn
			tooltip:AddLine(L["Not learned yet: talk to this flight master to learn it."], warn[1], warn[2], warn[3], true)
		end
		local destinations = self:FlightDestinations(point.name)
		if #destinations > 0 then
			tooltip:AddLine(" ")
			tooltip:AddLine(L["Flies to"], Secondary())
			for index, to in ipairs(destinations) do
				if index > 12 and not (IsShiftKeyDown and IsShiftKeyDown()) then
					tooltip:AddLine(L["%d more (hold Shift)"]:format(#destinations - 12), Secondary())
					break
				end
				local time = self.db.tooltipTimes and self:FlightTime(point.name, to)
				local body = E.tokens.text.body
				if time then
					tooltip:AddDoubleLine(to, FormatTime(time), body[1], body[2], body[3], Secondary())
				else
					tooltip:AddLine(to, body[1], body[2], body[3])
				end
			end
		elseif not point.unknown then
			tooltip:AddLine(L["Open its flight map once to list where it flies."], Secondary())
		end
	else
		local body = E.tokens.text.body
		if point.arrival then tooltip:AddLine(L["Arrival only"], Secondary()) end
		for _, dest in ipairs(point.destinations or {}) do
			tooltip:AddLine(L["To %s (%s)"]:format(dest.name, M.MapName(dest.uiMapID)), body[1], body[2], body[3])
		end
		if not point.checked then
			tooltip:AddLine(L["Position from EldoUI's own list, not checked in WoW: Forever yet."], Secondary())
		end
	end
	E:TooltipHint(tooltip, { L["Right-click"], L["a waypoint"] })
	tooltip:Show()
end

function M:SetWaypoint(point)
	local x, y = point.zoneX or point.x, point.zoneY or point.y
	local WP = E.Waypoints
	if WP and WP.active and WP.Add then
		WP:Add(point.uiMapID, x, y, { title = point.name, source = "Transport" })
		return true
	end
	local mapPoint = rawget(_G, "UiMapPoint")
	if C_Map and C_Map.SetUserWaypoint and mapPoint and mapPoint.CreateFromCoordinates then
		local pinPoint = Try(mapPoint.CreateFromCoordinates, point.uiMapID, x, y)
		if pinPoint then
			Try(C_Map.SetUserWaypoint, pinPoint)
			return true
		end
	end
	return false
end

function M:PinMenu(pin)
	local point = pin.point
	if not point then return end
	E.UIKit.ContextMenu(pin, function(_, root)
		root:CreateTitle(point.name)
		root:CreateButton(L["Set a waypoint"], function() M:SetWaypoint(point) end)
		-- The Routes tab opens from /eui (config gate); this picks the zone for it.
		root:CreateButton(L["Pick this zone on the Routes tab"], function()
			M.db.routeZone = point.uiMapID
			E:Print(L["Transport Maps: the Routes tab (/eui > Transport Maps) now lists %s."]:format(M.MapName(point.uiMapID)))
		end)
	end)
end

---------------------------------------------------------------------------
-- Routes tab: the stops of one zone and where they go
---------------------------------------------------------------------------
function M:RouteZone()
	local zone = tonumber(self.db.routeZone) or 0
	if zone == 0 and C_Map and C_Map.GetBestMapForUnit then zone = Clean(Try(C_Map.GetBestMapForUnit, "player")) or 0 end
	return zone
end

-- Zones that have a stop in the data table, for the Routes tab.
function M:RouteZoneValues()
	local values = { [0] = L["Where you are"] }
	for _, stop in ipairs(self:DataStops()) do values[stop.uiMapID] = M.MapName(stop.uiMapID) end
	return values
end

-- Plain lines: "Boat: Menethil Harbor > Auberdine (Darkshore)".
function M:RouteLines(uiMapID)
	local lines = {}
	for _, point in ipairs(self:Points(uiMapID)) do
		local kind = L[KIND_TITLE[point.kind] or "Boat"]
		if point.kind == "flight" then
			local count = #self:FlightDestinations(point.name)
			lines[#lines + 1] = point.unknown and L["%s: %s (not learned yet)"]:format(kind, point.name)
				or L["%s: %s, %d destinations known"]:format(kind, point.name, count)
		else
			for _, dest in ipairs(point.destinations) do
				lines[#lines + 1] = L["%s: %s to %s (%s)"]:format(kind, point.name, dest.name, M.MapName(dest.uiMapID))
			end
		end
	end
	-- The ways in: stops elsewhere whose boat, zeppelin, tram or portal
	-- arrives in this zone.
	for _, stop in ipairs(self:DataStops()) do
		local dest = stop.destinations[1]
		if dest and dest.uiMapID == uiMapID and stop.uiMapID ~= uiMapID and self.db.kinds[stop.kind] and FactionShown(self, stop.faction) then
			local kind = L[KIND_TITLE[stop.kind] or "Boat"]
			lines[#lines + 1] = L["%s from %s (%s) to %s"]:format(kind, stop.name, M.MapName(stop.uiMapID), dest.name)
		end
	end
	return lines
end

local function CreateRoutes(frame)
	if not frame then return end
	frame.text = E:CreateText(frame, E.tokens.size.body, "LEFT")
	frame.text:SetPoint("TOPLEFT", 4, -4)
	frame.text:SetPoint("BOTTOMRIGHT", -4, 4)
	frame.text:SetJustifyV("TOP")
	frame.text:SetWordWrap(true)
end

local function UpdateRoutes(frame)
	if not (frame and frame.text) then return end
	local zone = M:RouteZone()
	local lines = M.db and M:RouteLines(zone) or {}
	if #lines == 0 then
		frame.text:SetText(L["No transport stops known in %s."]:format(M.MapName(zone)))
	else
		frame.text:SetText(M.MapName(zone) .. "\n" .. table.concat(lines, "\n"))
	end
end

---------------------------------------------------------------------------
-- Map pin layer (the one switch) and the module
---------------------------------------------------------------------------
E:RegisterMapPinLayer("transport", {
	title = "Transport", order = 45, continent = true,
	available = function() return M.active end,
	count = function(uiMapID) return M.active and #M:Points(uiMapID) or 0 end,
	refresh = function() if M.active then M:RefreshPins() end end,
})

local EVENTS = { "TAXIMAP_OPENED", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA" }

local function OnEvent(_, event)
	if not M.active then return end
	if event == "TAXIMAP_OPENED" then
		M:LearnFlightMap()
	else
		M:RefreshPins()
	end
end

function M:OnInitialize()
	E:RegisterGlobal("Transport", { routes = {} }, { title = "Transport routes", desc = "Where each flight master flies, learned from your flight maps." })
	E:RegisterPrivate("Transport", { known = {} })
end

function M:OnEnable()
	for _, event in ipairs(EVENTS) do E:RegisterEvent(event, OnEvent, M) end
	self:HookWorldMap()
	self:RefreshPins()
end

function M:OnDisable()
	for _, event in ipairs(EVENTS) do E:UnregisterEvent(event, M) end
	self:HidePins()
end

function M:OnProfileChanged()
	if not self.active then return end
	self:RefreshPins()
end

---------------------------------------------------------------------------
-- Options and styles
---------------------------------------------------------------------------
M.options = {
	{ type = "description", label = "Flight masters, boats, zeppelins, the tram and portals on the map, shown with the other EldoUI pins. Right-click a pin for a waypoint." },
	{ type = "tab", label = "Pins" },
	{ type = "header", label = "Show" },
	{ type = "toggle", key = "kinds.flight", label = "Flight masters", desc = "Flight masters on the world map, from the game. The tooltip lists where each flies once you opened its flight map." },
	{ type = "toggle", key = "showUnknown", label = "Flight masters you don't know yet", dependsOn = "kinds.flight", desc = "Also show flight masters you have not talked to, grayed, so you can go and learn them." },
	{ type = "toggle", key = "kinds.boat", label = "Boats", desc = "Docks and where their boats sail." },
	{ type = "toggle", key = "kinds.zeppelin", label = "Zeppelins", desc = "Zeppelin towers and where they fly." },
	{ type = "toggle", key = "kinds.tram", label = "Tram", desc = "Both ends of the Deeprun Tram." },
	{ type = "toggle", key = "kinds.portal", label = "Portals", desc = "Portals that always stand in the same place." },
	{ type = "toggle", key = "myFaction", label = "Only your faction", desc = "Hide the other faction's flight masters, docks and towers. Neutral ones always show." },
	{ type = "toggle", key = "continentPins", label = "Show on continent maps", desc = "Boats, zeppelins, the tram and portals also show on Kalimdor and the Eastern Kingdoms." },
	{ type = "header", label = "Look" },
	{ type = "select", key = "pinStyle", label = "Pin look", order = { "icons", "dots", "contrast", "bronze", "minimal" },
		values = { icons = "Icons", dots = "Colored dots", contrast = "High contrast", bronze = "Forever bronze", minimal = "Minimal" },
		desc = "Icons: the game's flight master art and a shape per kind. Colored dots: small dots. High contrast: large outlined shapes. Forever bronze: bronze shapes. Minimal: faint dots." },
	{ type = "range", percent = true, key = "pinScale", label = "Pin scale", min = 0.5, max = 2, step = 0.05, desc = "Size of the transport pins." },
	{ type = "range", percent = true, key = "pinAlpha", label = "Pin opacity", min = 0.3, max = 1, step = 0.05, desc = "How see-through the transport pins are." },
	{ type = "toggle", key = "tooltipTimes", label = "Flight times in tooltips", desc = "Show how long a flight took when you flew that route before (from the QoL flight timer)." },
	{ type = "tab", label = "Routes" },
	{ type = "select", key = "routeZone", label = "Zone", values = function() return M:RouteZoneValues() end,
		desc = "A zone to travel to or from: below are its transport stops with where each goes, and the boats, zeppelins, tram and portals that arrive there." },
	{ type = "preview", label = "Routes", height = 220, create = CreateRoutes, update = UpdateRoutes },
}

E:RegisterStyles("Transport", {
	{ key = "Icons", title = "Icons", desc = "The game's flight master art and a shape per kind.",
		settings = { pinStyle = "icons", pinScale = 1, pinAlpha = 1 } },
	{ key = "Dots", title = "Colored dots", desc = "Small dots in a color per kind, for a calm map.",
		settings = { pinStyle = "dots", pinScale = 0.9, pinAlpha = 0.9 } },
	{ key = "Contrast", title = "High contrast", desc = "Large shapes with a white border, easy to see.",
		settings = { pinStyle = "contrast", pinScale = 1.2, pinAlpha = 1 } },
	{ key = "Bronze", title = "Forever bronze", desc = "Shapes framed in the art style's border color.",
		settings = { pinStyle = "bronze", pinScale = 1, pinAlpha = 1 } },
	{ key = "Minimal", title = "Minimal", desc = "Small faint dots; flight masters you don't know stay hidden.",
		settings = { pinStyle = "minimal", pinScale = 0.8, pinAlpha = 0.7, showUnknown = false } },
})
