-- EldoUI Gathering: node pins on the world map and the minimap.
--
-- Like the Waypoints pins these are EldoUI's own frames: on the world map's
-- canvas (a data provider only tells us when the map changes) and on the
-- minimap at each node's offset from you, scaled by the minimap's view
-- radius. The minimap shows the nodes of the zone you are in.
local _, E = ...
local L = E.L
local M = E.Gathering
local WP = E.Waypoints
local Kit = E.UIKit

local max, abs = math.max, math.abs

local function Try(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a, b, c = pcall(fn, ...)
	if ok then return a, b, c end
end

local Clean = E.Plain

---------------------------------------------------------------------------
-- Pins
---------------------------------------------------------------------------
local function StylePin(pin, node)
	local kind = M.kindByKey[node.k]
	local size = M.db.pinSize
	pin:SetSize(size, size)
	pin:SetAlpha(M.db.pinAlpha)
	local style = M.db.iconStyle
	if style == "dots" or style == "contrast" then
		-- Contrast: a larger dot on a white ring (dots: a thin dark edge).
		local dot = style == "contrast" and size * 0.75 or size * 0.6
		local ring = style == "contrast" and 3 or 2
		pin.icon:SetTexture(E.media.flat)
		pin.icon:SetVertexColor(unpack(kind.color))
		pin.icon:SetSize(dot, dot)
		pin.icon:SetTexCoord(0, 1, 0, 1)
		pin.edge:SetSize(dot + ring, dot + ring)
		if style == "contrast" then
			pin.edge:SetVertexColor(1, 1, 1, 1)
		else
			pin.edge:SetVertexColor(0, 0, 0, 0.9)
		end
		pin.edge:Show()
	else
		pin.icon:SetTexture(M.KindIcon(kind))
		pin.icon:SetVertexColor(1, 1, 1)
		pin.icon:SetSize(size, size)
		E:TrimIcon(pin.icon)
		pin.edge:Hide()
	end
end

local function PinTooltip(pin)
	local node = pin.node
	if not node then return end
	local kind = M.kindByKey[node.k]
	local sr, sg, sb = unpack(Kit.SECONDARY)
	GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
	Kit.TipTitle(GameTooltip, node.n)
	if kind then
		GameTooltip:AddLine(L[kind.label], unpack(kind.color))
	end
	local skill, r, g, b = M:SkillLine(node)
	if skill then GameTooltip:AddLine(skill, r, g, b) end
	GameTooltip:AddDoubleLine(L["Gathered"], tostring(node.c or 1), sr, sg, sb, 1, 1, 1)
	if node.t then GameTooltip:AddDoubleLine(L["Last"], E:ShortDate(node.t), sr, sg, sb, 1, 1, 1) end
	if node.s then GameTooltip:AddLine(L["From an import"], sr, sg, sb) end
	if pin.mapID and pin.mapID ~= pin.hereMapID and WP.MapName then
		GameTooltip:AddLine(WP.MapName(pin.mapID), sr, sg, sb)
	end
	E:TooltipHint(GameTooltip, { L["Right-click"], L["options"] })
	GameTooltip:Show()
end

local function PinMenu(pin)
	local node, mapID = pin.node, pin.mapID
	if not node then return end
	E.UIKit.ContextMenu(pin, function(_, root)
		root:CreateTitle(node.n)
		if E.Waypoints and E.Waypoints.active then
			root:CreateButton(L["Set a waypoint here"], function() E.Waypoints:Add(mapID, node.x, node.y, { title = node.n }) end)
		end
		root:CreateButton(L["Hide every %s"]:format(node.n), function() M:HideName(node.n) end)
		root:CreateButton(L["Forget this node"], function() M:RemoveNode(mapID, node) end)
	end)
end

local function CreatePin(parent)
	local pin = CreateFrame("Button", nil, parent)
	pin:RegisterForClicks("RightButtonUp")
	pin.edge = pin:CreateTexture(nil, "BACKGROUND")
	pin.edge:SetPoint("CENTER")
	pin.edge:SetTexture(E.media.flat)
	pin.edge:SetVertexColor(0, 0, 0, 0.9)
	pin.icon = pin:CreateTexture(nil, "ARTWORK")
	pin.icon:SetPoint("CENTER")
	pin:SetScript("OnEnter", PinTooltip)
	pin:SetScript("OnLeave", GameTooltip_Hide)
	pin:SetScript("OnClick", function(p, button) if button == "RightButton" then PinMenu(p) end end)
	return pin
end

---------------------------------------------------------------------------
-- World map
---------------------------------------------------------------------------
local worldPins = {}
local provider

local function WorldMap()
	local map = _G.WorldMapFrame
	return (type(map) == "table" and map.GetCanvas) and map or nil
end

function M:RefreshWorldPins()
	local map = WorldMap()
	for _, pin in ipairs(worldPins) do pin:Hide() pin.node = nil end
	self.worldPinCount = 0
	-- Nothing to draw while the map is closed: opening it redraws.
	if not (map and map:IsShown() and self.active and self.db.worldPins and E:MapPinGroupShown("gathering", "world")) then return end
	local canvas = map:GetCanvas()
	local shownMap = map.GetMapID and map:GetMapID()
	if not (canvas and shownMap) then return end
	-- Continent and world maps: only when "Also on continent maps" is ticked.
	if not E:MapPinGroupOnMap("gathering", shownMap) then return end
	local width, height = canvas:GetSize()
	if not width or width <= 0 then return end
	local scale = map.GetCanvasScale and Try(map.GetCanvasScale, map) or 1
	local list = self:Store().maps[shownMap]
	if not list then return end
	local i = 0
	for _, node in ipairs(list) do
		if self:Shows(node) then
			i = i + 1
			local pin = worldPins[i]
			if not pin then
				pin = CreatePin(canvas)
				worldPins[i] = pin
			end
			pin.node, pin.mapID, pin.hereMapID = node, shownMap, shownMap
			E:PlaceMapPin(pin, "gathering", map, canvas)
			pin:SetScale(1 / max(scale or 1, 0.01))
			StylePin(pin, node)
			pin.mapX, pin.mapY = node.x, node.y
			pin:ClearAllPoints()
			pin:SetPoint("CENTER", canvas, "TOPLEFT", node.x * width * (scale or 1), -node.y * height * (scale or 1))
			pin:Show()
		end
	end
	self.worldPinCount = i
end

local function CreateProvider()
	local p = {}
	function p:RemoveAllData() for _, pin in ipairs(worldPins) do pin:Hide() end end
	function p:RefreshAllData() M:RefreshWorldPins() end
	function p:OnMapChanged() M:RefreshWorldPins() end
	function p:OnCanvasScaleChanged()
		if not E:RescaleMapPins(WorldMap(), worldPins, M.worldPinCount) then M:RefreshWorldPins() end
	end
	function p:OnCanvasSizeChanged() M:RefreshWorldPins() end
	function p:OnShow() M:RefreshWorldPins() end
	function p:OnHide() for _, pin in ipairs(worldPins) do pin:Hide() pin.node = nil end end
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
-- Minimap
---------------------------------------------------------------------------
local miniPins = {}
local worldCache = setmetatable({}, { __mode = "k" }) -- node -> { continent, north, west }

local function NodeWorld(mapID, node)
	local cached = worldCache[node]
	if cached and cached.x == node.x and cached.y == node.y then return cached[1], cached[2], cached[3] end
	local continent, north, west = WP.WorldPos(mapID, node.x, node.y)
	worldCache[node] = { continent, north, west, x = node.x, y = node.y }
	return continent, north, west
end

-- The continent of a map's nodes (from its first node), cached.
local mapContinent = {}
local function MapContinent(mapID, list)
	local continent = mapContinent[mapID]
	if continent == nil and list[1] then
		continent = NodeWorld(mapID, list[1])
		if continent then mapContinent[mapID] = continent end
	end
	return continent
end

-- The minimap shows the nodes of the zone you are in (far ones on the edge
-- when minimapEdge is on) and, near a border, the nodes of the zones next
-- door that are in range (never on the edge).
--
-- The nodes that can show are picked once into a candidate list: the
-- zone's own and those within twice the minimap's reach. The list is
-- picked again on every refresh from outside the ticker (new nodes,
-- filters, options), on another zone or a wider zoom, and once you have
-- moved further than the reach from where it was picked, so every node in
-- reach is always on it. The ticker leaves the pins alone while nothing
-- that places them changed, and a pin is restyled only for another node
-- or after a refresh from outside.
local tickView = {}
local minimapDirty
local candidates = {}
local picked = { reach = 0 }
local styleEpoch = 0

local function PickCandidates(mapID, continent, north, west, reach)
	wipe(candidates)
	picked.mapID, picked.continent, picked.north, picked.west, picked.reach = mapID, continent, north, west, reach
	local edge, wide = M.db.minimapEdge, reach * 2
	for listMap, list in pairs(M:Store().maps) do
		local here = listMap == mapID
		if here or MapContinent(listMap, list) == continent then
			local onEdge = here and edge
			for _, node in ipairs(list) do
				local c, n, w = NodeWorld(listMap, node)
				if c == continent and (onEdge or (abs(w - west) <= wide and abs(n - north) <= wide)) and M:Shows(node) then
					candidates[#candidates + 1] = { node = node, mapID = listMap, n = n, w = w, edge = onEdge }
				end
			end
		end
	end
	M.candidatePicks = (M.candidatePicks or 0) + 1
end

-- fromTick: the shared ticker (the only caller that may skip work).
function M:RefreshMinimapPins(fromTick, sample)
	local minimap = _G.Minimap
	if not minimap or not minimap:IsVisible() then
		minimapDirty = true
		for _, pin in ipairs(miniPins) do pin:Hide() pin.node = nil end
		self.miniPinCount = 0
		return
	end
	if minimapDirty then fromTick, minimapDirty = nil, nil end
	local mapID, _, _, continent, north, west
	if sample then
		mapID, continent, north, west = sample.mapID, sample.continent, sample.north, sample.west
	elseif fromTick then
		mapID, _, _, continent, north, west = WP.SharedPlayerPos()
	else
		mapID, _, _, continent, north, west = WP.PlayerPos()
	end
	local view = self.active and self.db.minimapPins and E:MapPinGroupShown("gathering", "minimap") and minimap and continent
		and E:CurrentMinimapView(north, west, minimap, tickView, sample)
	-- A tick that hid the pins forgets the view, so the next one shows them.
	if not view then wipe(tickView) end
	if fromTick and view and view.same and picked.mapID == mapID then
		self.minimapSkips = (self.minimapSkips or 0) + 1
		return
	end
	if not fromTick then styleEpoch = styleEpoch + 1 end
	local i = 0
	if view then
		local reach = view.radius * 1.5
		if not fromTick or picked.mapID ~= mapID or picked.continent ~= continent or reach > picked.reach
			or abs(north - picked.north) > picked.reach or abs(west - picked.west) > picked.reach then
			PickCandidates(mapID, continent, north, west, reach)
		end
		local alpha = self.db.pinAlpha
		for _, entry in ipairs(candidates) do
			local n, w = entry.n, entry.w
			if entry.edge or (abs(w - west) <= reach and abs(n - north) <= reach) then
				local px, py, outside = E:MinimapOffset(view, n, w, true)
				if not outside or entry.edge then
					i = i + 1
					local pin = miniPins[i]
					if not pin then
						pin = CreatePin(minimap)
						miniPins[i] = pin
					end
					E:PlaceMinimapPin(pin, "gathering", minimap)
					if pin.node ~= entry.node or pin.epoch ~= styleEpoch or pin.colors ~= E.colorsVersion then
						pin.node, pin.mapID, pin.colors = entry.node, entry.mapID, E.colorsVersion
						StylePin(pin, entry.node)
						pin:SetSize(self.db.pinSize * 0.85, self.db.pinSize * 0.85)
						pin.epoch, pin.outside = styleEpoch, nil
						self.minimapStyles = (self.minimapStyles or 0) + 1
					end
					pin.hereMapID = mapID
					outside = outside and true or false
					if pin.outside ~= outside then
						pin.outside = outside
						pin:SetAlpha(outside and alpha * 0.5 or alpha)
					end
					pin:ClearAllPoints()
					pin:SetPoint("CENTER", minimap, "CENTER", px, py)
					pin:Show()
				end
			end
		end
	else
		picked.mapID = nil
	end
	for j = i + 1, #miniPins do miniPins[j]:Hide() miniPins[j].node = nil end
	self.miniPinCount = i
end

-- The shared minimap driver calls this layer while known nodes can show.
local MINIMAP_TICK = "EldoUI.Gathering.minimap"

local function MinimapTick(sample)
	M:RefreshMinimapPins(true, sample)
end

function M:WatchMinimap()
	local want = self.active and self.db.minimapPins and _G.Minimap and next(self:Store().maps) ~= nil
	E:SetMinimapUpdater(MINIMAP_TICK, want, MinimapTick)
end

---------------------------------------------------------------------------
-- Hooks into Core.lua
---------------------------------------------------------------------------
function M:RefreshPins()
	if not self.active then return end
	self:RefreshWorldPins()
	self:RefreshMinimapPins()
	self:WatchMinimap()
end

function M:EnableMap()
	self:HookWorldMap()
	if not self.worldHooked then
		E:OnBlizzardAddOn("Blizzard_WorldMap", function() if M.active then M:HookWorldMap() M:RefreshWorldPins() end end)
	end
	self:RefreshPins()
end

function M:DisableMap()
	E:SetMinimapUpdater(MINIMAP_TICK, false)
	E.Ticker:UnsubscribeOwner(self)
	for _, pin in ipairs(worldPins) do pin:Hide() end
	for _, pin in ipairs(miniPins) do pin:Hide() end
end

-- The map switch (Core/MapPins.lua): the Map Notes button and keybind hide
-- these pins with every other EldoUI pin.
E:RegisterMapPinLayer("gathering", {
	title = "Gathering nodes", order = 70, continent = false,
	available = function() return M.active and (M.db.worldPins or M.db.minimapPins) and true or false end,
	count = function(uiMapID)
		local n = 0
		for _, node in ipairs(M:Store().maps[uiMapID] or {}) do
			if M:Shows(node) then n = n + 1 end
		end
		return n
	end,
	refresh = function() if M.active then M:RefreshPins() end end,
})
