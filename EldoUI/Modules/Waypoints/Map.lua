-- EldoUI Waypoints: pins on the world map and the minimap.
--
-- World map pins are EldoUI's own frames on the map canvas, placed from the
-- map's size; the module only listens to the map through a data provider
-- (map changed, canvas scale) and never uses Blizzard's pin pools, so the
-- map's own pins stay untouched. Minimap pins sit on the minimap at the
-- waypoint's offset from the player, scaled by the minimap's view radius;
-- ones out of range sit on the edge. Both need the player's position for the
-- minimap and hide where the game hides it.
local _, E = ...
local L = E.L
local M = E.Waypoints
local maps = E:GetModule("Maps")
local canvasView = maps and maps.WorldCanvasPinView
local Secret, Call = E.Secret, E.PlainCallAll
local readEnabled = E.ModuleEnabledValue

local function Same(a, b)
	return not Secret(a) and not Secret(b) and a == b
end

local sqrt, max, abs, cos, sin = math.sqrt, math.max, math.abs, math.cos, math.sin

local function Try(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a, b, c = pcall(fn, ...)
	if ok then return a, b, c end
end

local Clean = E.Plain

---------------------------------------------------------------------------
-- Pin look (shared by both maps): a small accent shape with a dark edge
-- (diamond, square or round: the Pin shape option); the arrow's waypoint is
-- bigger and brighter.
---------------------------------------------------------------------------
local ROUND = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local SHAPES = {
	diamond = { texture = "flat", rotation = math.pi / 4, scale = 0.72 },
	square = { texture = "flat", rotation = 0, scale = 0.62 },
	round = { texture = ROUND, rotation = 0, scale = 0.8 },
}

local function Shape()
	return SHAPES[M.db.pinStyle] or SHAPES.diamond
end
M.PinShape = Shape

local function Write(check, object, key, ...)
	if check then
		local valid, method = check(object, key)
		if not valid then return false end
		method(object, ...)
		return check(object, key)
	end
	object[key](object, ...)
	return true
end

local function ApplyShape(pin, check)
	if check and not check() then return false end
	local shape = Shape()
	if pin.shape == shape then return true end
	pin.shape = shape
	local texture = shape.texture == "flat" and E.media.flat or shape.texture
	for _, layer in ipairs({ pin.edge, pin.dot }) do
		if not Write(check, layer, "SetTexture", texture) or not Write(check, layer, "SetRotation", shape.rotation) then return false end
	end
	local w = pin:GetWidth()
	if check and not check() then return false end
	if w and w > 0 then pin:GetScript("OnSizeChanged")(pin, w) end
	return not check or check()
end

local function StylePin(pin, size, current, check)
	if not ApplyShape(pin, check) then return false end
	local s = current and size * 1.25 or size
	if not Write(check, pin, "SetSize", s, s) then return false end
	local r, g, b = unpack(E.media.accentColor)
	return Write(check, pin.dot, "SetVertexColor", r, g, b, current and 1 or 0.8)
end

local function CreatePin(parent, row)
	local pin = CreateFrame("Button", nil, parent)
	if row then row.parent, row.pin = parent, pin end
	if row and row.buildCheck and (Secret(pin) or type(pin) ~= "table") then row.failed = true return end
	local objects = {}
	local function build(object, key)
		if not row.buildCheck() or Secret(object) or type(object) ~= "table" then return false end
		local record = objects[object]
		if not record then
			local getter = Call(function() return object.GetParent end)
			if Secret(getter) or type(getter) ~= "function" then return false end
			record = { getter = getter, parent = object == pin and parent or pin, methods = {} }
			objects[object] = record
		end
		local method = Call(function() return object[key] end)
		if Secret(method) or type(method) ~= "function" then return false end
		if record.methods[key] and not Same(record.methods[key], method) then return false end
		record.methods[key] = method
		if not Same(Call(function() return object.GetParent end), record.getter)
			or not Same(Call(record.getter, object), record.parent) or not row.buildCheck() then return false end
		return true, method
	end
	local check = row and row.buildCheck and build
	local function failed()
		row.failed = true
		if check then
			local valid, hide = check(pin, "Hide")
			if valid then hide(pin) end
		end
	end
	local function paint(object, key, ...)
		if not Write(check, object, key, ...) then failed() return false end
		return true
	end
	local function texture(layer)
		local method = pin.CreateTexture
		if check then
			local valid
			valid, method = check(pin, "CreateTexture")
			if not valid then failed() return end
		end
		local result = method(pin, nil, layer)
		if check and (Secret(result) or type(result) ~= "table") then failed() return end
		if check and not check(pin, "CreateTexture") then failed() return end
		return result
	end
	if not paint(pin, "RegisterForClicks", "RightButtonUp") then return pin end
	pin.edge = texture("BACKGROUND")
	if not pin.edge then failed() return pin end
	if not paint(pin.edge, "SetPoint", "CENTER") or not paint(pin.edge, "SetTexture", E.media.flat)
		or not paint(pin.edge, "SetVertexColor", 0, 0, 0, 0.9) or not paint(pin.edge, "SetRotation", math.pi / 4) then return pin end
	pin.dot = texture("ARTWORK")
	if not pin.dot then failed() return pin end
	if not paint(pin.dot, "SetPoint", "CENTER") or not paint(pin.dot, "SetTexture", E.media.flat)
		or not paint(pin.dot, "SetRotation", math.pi / 4) then return pin end
	if row then row.edge, row.dot = pin.edge, pin.dot end
	if not paint(pin, "SetScript", "OnSizeChanged", function(p, w)
		local liveCheck = row and row.check
		if liveCheck and not liveCheck() then return end
		local k = (p.shape or SHAPES.diamond).scale
		if not Write(liveCheck, p.edge, "SetSize", w * k, w * k) then return end
		Write(liveCheck, p.dot, "SetSize", w * k - 2, w * k - 2)
	end) or not paint(pin, "SetScript", "OnEnter", function(p) M:PinTooltip(p) end)
		or not paint(pin, "SetScript", "OnLeave", GameTooltip_Hide)
		or not paint(pin, "SetScript", "OnClick", function(p, button) if button == "RightButton" then M:PinMenu(p) end end) then return pin end
	return pin
end

function M:PinTooltip(pin)
	local wp = pin.uid and self.points[pin.uid]
	if not wp then return end
	GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
	local r, g, b = M.Shade("SECONDARY")
	local dr, dg, db = M.Shade("DIM")
	E.UIKit.TipTitle(GameTooltip, wp.title or L["Waypoint"])
	GameTooltip:AddLine(("%s %s"):format(M.MapName(wp.mapID), M.FormatCoords(wp.x, wp.y)), r, g, b)
	local distance = self:Distance(wp)
	if distance then GameTooltip:AddLine(M.FormatDistance(distance), r, g, b) end
	if pin.uid == self.arrowUid then GameTooltip:AddLine(L["The arrow points here."], dr, dg, db) end
	E:TooltipHint(GameTooltip, { L["Right-click"], L["options"] })
	GameTooltip:Show()
end

function M:PinMenu(pin)
	local uid = pin.uid
	local wp = uid and self.points[uid]
	if not wp then return end
	E.UIKit.ContextMenu(pin, function(_, root)
		root:CreateTitle(wp.title or L["Waypoint"])
		root:CreateButton(L["Point the arrow here"], function() M:SetArrow(uid) end)
		root:CreateButton(L["Remove"], function() M:Remove(uid) end)
		root:CreateButton(L["Remove all on this map"], function() M:AskRemoveAll(wp.mapID) end)
		-- Puts the waypoint line in the chat box; the player decides to send it.
		root:CreateButton(L["Share in chat"], function()
			local chat = rawget(_G, "ChatFrameUtil")
			if chat and chat.OpenChat then
				chat.OpenChat(M:ShareText(wp))
			elseif ChatFrame_OpenChat then
				ChatFrame_OpenChat(M:ShareText(wp))
			end
		end)
	end)
end

---------------------------------------------------------------------------
-- World map
---------------------------------------------------------------------------
local worldPins = {}
local worldOwners = {}
local worldFailed
local worldRefreshing
local provider

local function Number(value)
	return not Secret(value) and type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function PlainTable(value)
	if Secret(value) or type(value) ~= "table" then return false end
	local meta = getmetatable(value)
	return not Secret(meta) and type(meta) == "nil"
end

local function PinOwned(pin, row, target)
	if not row or row.failed or row.transferred or not Same(worldOwners[pin], row) then return false end
	if not Same(pin, row.pin) or not Same(pin.edge, row.edge) or not Same(pin.dot, row.dot) then return false end
	for object, record in pairs(row.objects) do
		for key, method in pairs(record.methods) do
			if not Same(Call(function() return object[key] end), method) then return false end
		end
		local parent = Call(record.methods.GetParent, object)
		if not Same(parent, record.parent) then row.transferred = true return false end
	end
	if target then
		local record = row.objects[target]
		if not record or not Same(Call(record.methods.GetParent, target), record.parent) then row.transferred = true return false end
	end
	return true
end

local function PinCheck(pin, row, current)
	return function(object, key)
		if not current() or not PinOwned(pin, row, object) or not current() then return false end
		local method = object and row.objects[object].methods[key]
		return true, method
	end
end

local function CapturePin(pin, row, parent)
	row.objects = {}
	for _, entry in ipairs({ { pin, parent, { "GetParent", "SetParent", "Hide", "Show", "SetFrameStrata", "SetScale", "ClearAllPoints", "SetPoint", "SetSize", "GetWidth", "GetScript" } },
		{ pin.edge, pin, { "GetParent", "SetTexture", "SetRotation", "SetSize" } },
		{ pin.dot, pin, { "GetParent", "SetTexture", "SetRotation", "SetSize", "SetVertexColor" } } }) do
		local object, methods = entry[1], {}
		if Secret(object) or type(object) ~= "table" then return false end
		for _, key in ipairs(entry[3]) do
			local fn = Call(function() return object[key] end)
			if Secret(fn) or type(fn) ~= "function" then return false end
			methods[key] = fn
		end
		row.objects[object] = { parent = entry[2], methods = methods }
	end
	return PinOwned(pin, row)
end

local function MovePin(pin, row, parent, check)
	if not check() or not PinOwned(pin, row) or not check() then return false end
	local record = row.objects[pin]
	if Same(record.parent, parent) then return true end
	local ok = pcall(record.methods.SetParent, pin, parent)
	-- Only this exact successful setter authorizes a new expected parent.
	if not ok or not Same(Call(record.methods.GetParent, pin), parent) or not check() then row.transferred = true return false end
	record.parent = parent
	return PinOwned(pin, row) and check()
end

local function HideWorldPins()
	for _, pin in ipairs(worldPins) do
		local row = worldOwners[pin]
		if row.objects then
			if not PinOwned(pin, row) then return false end
			if not pcall(row.objects[pin].methods.Hide, pin) or not PinOwned(pin, row) then return false end
		else
			pin:Hide()
		end
	end
	return true
end

local function WorldMap()
	local map = _G.WorldMapFrame
	return (type(map) == "table" and map.GetCanvas) and map or nil
end

-- Where a waypoint falls on the shown map (0-1), or nil.
local function OnShownMap(wp, shownMap)
	if wp.mapID == shownMap then return wp.x, wp.y end
	if not (wp.continent and C_Map and C_Map.GetMapPosFromWorldPos and CreateVector2D) then return nil end
	local _, position = Try(C_Map.GetMapPosFromWorldPos, wp.continent, CreateVector2D(wp.north, wp.west), shownMap)
	if type(position) ~= "table" or not position.GetXY then return nil end
	local x, y = position:GetXY()
	x, y = Clean(x), Clean(y)
	if not x or not y or x < 0 or x > 1 or y < 0 or y > 1 then return nil end
	return x, y
end

local function StandardWorldPins(self)
	local map = WorldMap()
	for _, pin in ipairs(worldPins) do
		local row = worldOwners[pin]
		if row and (row.bridge or row.objects or row.failed or row.buildCheck) then
			if not PinOwned(pin, row) then return end
			local canvas = map and map:GetCanvas()
			if not canvas or not MovePin(pin, row, canvas, function() return Same(WorldMap(), map) end) then return end
			row.check, row.bridge = nil, false
		end
	end
	for _, pin in ipairs(worldPins) do pin:Hide() pin.uid = nil end
	self.worldPinCount = 0
	if not (map and self.active and self.db.worldPins and E:MapPinGroupShown("waypoints", "world")) then return end
	local canvas = map:GetCanvas()
	local shownMap = map.GetMapID and map:GetMapID()
	if not (canvas and shownMap) then return end
	-- Continent and world maps: only when "Also on continent maps" is ticked.
	if not E:MapPinGroupOnMap("waypoints", shownMap) then return end
	local width, height = canvas:GetSize()
	if not width or width <= 0 then return end
	local scale = map.GetCanvasScale and Try(map.GetCanvasScale, map) or 1
	local i = 0
	for uid, wp in self:Iterate() do
		local x, y = OnShownMap(wp, shownMap)
		if x then
			i = i + 1
			local pin = worldPins[i]
			if not pin then
				local row = {}
				pin = CreatePin(canvas, row)
				worldPins[i] = pin
				worldOwners[pin] = row
			end
			pin.uid = uid
			pin:SetFrameStrata("HIGH")
			pin:SetScale(1 / max(scale or 1, 0.01))
			StylePin(pin, self.db.pinSize, uid == self.arrowUid)
			pin:ClearAllPoints()
			pin:SetPoint("CENTER", canvas, "TOPLEFT", x * width * (scale or 1), -y * height * (scale or 1))
			pin:Show()
		end
	end
	self.worldPinCount = i
end

local function RefreshWorldPins(self)
	if worldFailed then return end
	if maps and not Same(maps.WorldCanvasPinView, canvasView) then return end
	local binding, status
	if canvasView then binding, status = Call(canvasView, maps) end
	if not binding then
		if canvasView and not Same(status, "closed") then return end
		return StandardWorldPins(self)
	end
	if Secret(self.db) or type(self.db) ~= "table" or not PlainTable(E.media)
		or not PlainTable(rawget(E.media, "accentColor")) or not Same(E.ModuleEnabledValue, readEnabled) then return end
	local enabled = Call(readEnabled, E, self)
	if Secret(enabled) or type(enabled) ~= "boolean" then return end
	local db, profile, media, points, order = self.db, E.db, E.media, self.points, self.order
	if not PlainTable(points) or not PlainTable(order) then return end
	local orderLength = #order
	local colors, flat = rawget(media, "accentColor"), rawget(media, "flat")
	local r, g, b = rawget(colors, 1), rawget(colors, 2), rawget(colors, 3)
	if Secret(flat) or (type(flat) ~= "string" and not Number(flat))
		or not Number(r) or not Number(g) or not Number(b) or r < 0 or r > 1 or g < 0 or g > 1 or b < 0 or b > 1 then return end
	local active, size, shape, arrow = self.active, rawget(db, "pinSize"), rawget(db, "pinStyle"), self.arrowUid
	local worldPinsOn = rawget(db, "worldPins")
	local iterate, group = self.Iterate, E.MapPinGroupShown
	local function current()
		return Same(self, M) and Same(E.Waypoints, M) and Same(maps.WorldCanvasPinView, canvasView)
			and Same(E.ModuleEnabledValue, readEnabled) and Same(Call(readEnabled, E, M), enabled)
			and Same(self.db, db) and Same(E.db, profile) and Same(E.media, media)
			and Same(rawget(media, "accentColor"), colors) and Same(rawget(media, "flat"), flat)
			and Same(rawget(colors, 1), r) and Same(rawget(colors, 2), g) and Same(rawget(colors, 3), b)
			and PlainTable(points) and PlainTable(order) and Same(self.points, points) and Same(self.order, order)
			and #order == orderLength and Same(self.active, active)
			and Same(rawget(db, "pinSize"), size) and Same(rawget(db, "pinStyle"), shape)
			and Same(rawget(db, "worldPins"), worldPinsOn) and Same(self.arrowUid, arrow)
			and Same(self.Iterate, iterate) and Same(E.MapPinGroupShown, group) and Same(Call(binding.current), true)
	end
	if not current() then return end
	for _, pin in ipairs(worldPins) do
		local row = worldOwners[pin]
		if not row.objects and not CapturePin(pin, row, row.parent) then return end
		if not current() or not PinOwned(pin, row) or not current() then return end
		row.check = PinCheck(pin, row, current)
		if not Write(row.check, pin, "Hide") then return end
		pin.uid = nil
	end
	if not Same(active, true) or not enabled or not Same(worldPinsOn, true) then return end
	local shown = Call(group, E, "waypoints", "world")
	if not Same(shown, true) or not current() or not Number(size) or size <= 0 then return end
	local iterator, state, initial = iterate(self)
	if not current() then return end
	local i = 0
	for uid, wp in iterator, state, initial do
		if not current() or not Number(uid) or uid < 1 or uid % 1 ~= 0 or not PlainTable(wp) then return end
		local point, id, wx, wy = wp, rawget(wp, "mapID"), rawget(wp, "x"), rawget(wp, "y")
		local function pointCurrent()
			return current() and Same(rawget(points, uid), point) and PlainTable(point)
				and Same(rawget(point, "mapID"), id) and Same(rawget(point, "x"), wx) and Same(rawget(point, "y"), wy)
		end
		local x, y, inside = binding.projectMap(id, wx, wy)
		if not pointCurrent() then return end
		if Number(x) and Number(y) and Same(inside, true) then
			i = i + 1
			local pin = worldPins[i]
			local row = pin and worldOwners[pin] or {}
			if not pin then
				row.buildCheck = pointCurrent
				pin = CreatePin(binding.frame, row)
				if Secret(pin) or type(pin) ~= "table" then worldFailed = true return end
				worldPins[i], worldOwners[pin] = pin, row
				if not pointCurrent() or not CapturePin(pin, row, binding.frame) then return end
				row.buildCheck = nil
			end
			row.check = PinCheck(pin, row, pointCurrent)
			if not MovePin(pin, row, binding.frame, pointCurrent) then return end
			row.bridge = true
			if not row.check() then return end
			pin.uid = uid
			if not Write(row.check, pin, "SetFrameStrata", "HIGH") or not Write(row.check, pin, "SetScale", 1)
				or not StylePin(pin, size, uid == arrow, row.check) or not Write(row.check, pin, "ClearAllPoints")
				or not Write(row.check, pin, "SetPoint", "CENTER", binding.frame, "TOPLEFT", x, -y)
				or not Write(row.check, pin, "Show") then return end
		end
	end
end

local function Packed(ok, ...)
	return ok, select("#", ...), { ... }
end

function M:RefreshWorldPins()
	if worldRefreshing or not Same(self, M) then return end
	worldRefreshing = true
	local ok, count, values = Packed(pcall(RefreshWorldPins, self))
	worldRefreshing = nil
	if not ok then error(values[1], 0) end
	return unpack(values, 1, count)
end

-- A data provider only for its callbacks (map changed, zoom, refresh).
local function CreateProvider()
	local base = _G.MapCanvasDataProviderMixin
	local p = base and CreateFromMixins and CreateFromMixins(base) or {}
	function p:OnAdded(owningMap) self.owningMap = owningMap end
	function p:OnRemoved() self.owningMap = nil end
	function p:RemoveAllData() HideWorldPins() end
	function p:RefreshAllData() M:RefreshWorldPins() end
	function p:OnMapChanged() M:RefreshWorldPins() end
	function p:OnCanvasScaleChanged() M:RefreshWorldPins() end
	function p:OnCanvasSizeChanged() M:RefreshWorldPins() end
	function p:OnShow() M:RefreshWorldPins() end
	return p
end

-- Ctrl+right-click on the map adds a waypoint there (the shared map click
-- frame takes the click, so the map keeps its zone and zoom).
E:RegisterMapRightClick("waypoints", {
	modifier = "ctrl",
	wants = function() return M.active and M.db.mapClick and true or false end,
	click = function(uiMapID, x, y) M:Add(uiMapID, x, y) end,
})

function M:HookWorldMap()
	local map = WorldMap()
	if not map or self.worldHooked then return end
	self.worldHooked = true
	if map.AddDataProvider then
		provider = provider or CreateProvider()
		map:AddDataProvider(provider)
	end
end

---------------------------------------------------------------------------
-- Minimap
---------------------------------------------------------------------------
local miniPins = {}
-- The ticker's view: while nothing that places a pin changed (and the
-- arrow points at the same waypoint), the ticker leaves the pins alone. A
-- pin is restyled only for another waypoint, a new arrow target, other
-- colors or after a refresh from outside the ticker.
local tickView = {}
local styleEpoch, tickArrow = 0, nil

-- fromTick: the shared ticker (the only caller that may skip work).
function M:RefreshMinimapPins(fromTick)
	local minimap = _G.Minimap
	local _, _, _, continent, north, west = (fromTick and M.SharedPlayerPos or M.PlayerPos)()
	local view = continent and E:MinimapView(north, west, minimap, tickView)
	local show = self.active and self.db.minimapPins and E:MapPinGroupShown("waypoints", "minimap") and view
	if fromTick and show and view.same and tickArrow == self.arrowUid then
		self.minimapSkips = (self.minimapSkips or 0) + 1
		return
	end
	tickArrow = self.arrowUid
	if not fromTick then styleEpoch = styleEpoch + 1 end
	local i = 0
	if show then
		for uid, wp in self:Iterate() do
			if wp.continent == continent then
				local px, py, edge = E:MinimapOffset(view, wp.north, wp.west, true)
				i = i + 1
				local pin = miniPins[i]
				if not pin then
					pin = CreatePin(minimap)
					pin:SetFrameLevel(minimap:GetFrameLevel() + 5)
					miniPins[i] = pin
				end
				local arrow = uid == self.arrowUid
				if pin.uid ~= uid or pin.arrow ~= arrow or pin.epoch ~= styleEpoch or pin.colors ~= E.colorsVersion then
					pin.uid, pin.arrow, pin.epoch, pin.colors = uid, arrow, styleEpoch, E.colorsVersion
					StylePin(pin, self.db.pinSize * 0.8, arrow)
					self.minimapStyles = (self.minimapStyles or 0) + 1
				end
				pin:SetAlpha(edge and 0.6 or 1)
				pin:ClearAllPoints()
				pin:SetPoint("CENTER", minimap, "CENTER", px, py)
				pin:Show()
			end
		end
	end
	for j = i + 1, #miniPins do miniPins[j]:Hide() miniPins[j].uid = nil end
end

-- Minimap pins follow you ten times a second on the shared ticker, only
-- while there are waypoints to show there.
local MINIMAP_TICK = "Waypoints:minimapPins"
local function MinimapTick()
	M:RefreshMinimapPins(true)
end

---------------------------------------------------------------------------
-- Hooks into Core.lua
---------------------------------------------------------------------------
function M:RefreshPins()
	if not self.active then return end
	self:RefreshWorldPins()
	self:RefreshMinimapPins()
	if self.db.minimapPins and #self.order > 0 then
		if not E.Ticker:IsSubscribed(MINIMAP_TICK) then E.Ticker:Subscribe(MINIMAP_TICK, 0.1, MinimapTick, M) end
	else
		E.Ticker:Unsubscribe(MINIMAP_TICK)
	end
end

function M:LayoutPins()
	self:RefreshPins()
end

function M:EnableMap()
	self:HookWorldMap()
	if not self.worldHooked then
		E:OnBlizzardAddOn("Blizzard_WorldMap", function() if M.active then M:HookWorldMap() M:RefreshWorldPins() end end)
	end
	self:RefreshPins()
end

function M:DisableMap()
	E.Ticker:Unsubscribe(MINIMAP_TICK)
	HideWorldPins()
	for _, pin in ipairs(miniPins) do pin:Hide() end
end

-- The map switch (Core/MapPins.lua): the Map Notes button and keybind hide
-- these pins with every other EldoUI pin.
E:RegisterMapPinLayer("waypoints", {
	title = "Waypoints", order = 60, continent = false,
	available = function() return M.active and (M.db.worldPins or M.db.minimapPins) and true or false end,
	count = function(uiMapID)
		local n = 0
		for _, wp in M:Iterate() do if wp.mapID == uiMapID then n = n + 1 end end
		return n
	end,
	refresh = function() if M.active then M:RefreshPins() end end,
})
