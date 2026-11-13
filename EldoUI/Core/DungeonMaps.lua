-- EldoUI dungeon map layer (E.DungeonMaps). Module-independent: the
-- Loot Guide's dungeon map window, the world-map entrance pins and other
-- modules or plugins (such as Dungeon Routes) all draw through it.
--
-- WoW: Forever ships the classic dungeon map art in its files
-- (Interface\WorldMap\<folder>\<folder><floor>_<1-12>, 4 x 3 tiles of 256
-- px covering 1002 x 668) but the game's own map does not show it. This
-- layer draws those tiles itself, keeps the floors, turns world positions
-- into map positions and gives every caller one pin pool and overlay layers.
--
-- There is no player position inside instances on Forever. Nothing here
-- tries to work one out: pins come only from data (where creatures stand,
-- what a plugin knows). The current floor is what the client says (the map
-- it reports for the player, or the sub-zone name), else the floor last
-- shown.
--
-- API (stable, used by Dungeon Routes):
--   E.DungeonMaps:Register(key, def)   def = { name, map (instance map id),
--       art = { folder, ... }, wings = { otherKey, ... },
--       floors = { { name, bounds = { left, right, top, bottom }, uiMapID, zones = { subzone, ... } }, ... } }
--       Data/DungeonFloors.lua registers the Classic list, with the floor
--       edges of Data/DungeonFloorEdges.lua (by art floor number) as
--       def.edges; a plugin may add or extend one (fields it gives win).
--   E.DungeonMaps:Get(key), :List(), :KeyForMap(instanceMapID), :KeyFor(anyKey) (wings -> map key)
--   E.DungeonMaps:Floors(key) -> { { index, name, tiles = { path x12 } or nil, bounds, boundsSource } }
--       boundsSource: "map" (the client's map API), "data" (registered),
--       "layout" (worked out from creature positions; approximate) or nil.
--   E.DungeonMaps:WorldToMap(key, floor, worldX, worldY) -> x, y (0-1) or nil
--   E.DungeonMaps:MapToWorld(key, floor, x, y) -> worldX, worldY or nil
--   E.DungeonMaps:CurrentDungeon() -> key or nil (the instance you are in)
--   E.DungeonMaps:CurrentFloor(key) -> floor, source ("map", "zone", "last")
--   E.DungeonMaps:LastFloor(key), :SetLastFloor(key, floor)  (saved)
--   E.DungeonMaps:LearnFloorMap(key)  inside the dungeon: keep the uiMapIDs
--       of its floors (the client's map group), so floors get real edges
--   E.DungeonMaps:Bounds(key, floor, view), :HasArt(key), :Reset([key])
--   E.DungeonMaps:RegisterLayoutSource(id, fn(key, instanceMap) -> { { x, y }, ... })
--   E.DungeonMaps:CreateCanvas(parent) -> canvas (see Canvas below)
--   E:AddMapPinProvider(id, provider), E:RemoveMapPinProvider(id), E:RefreshMapPins()
--
-- Pin providers:
--   provider = {
--     order = 50,                                  -- lower draws first
--     pins = function(provider, ctx) return { pin, ... } end,
--     draw = function(provider, layer, ctx) end,   -- optional own drawing on
--                                                   -- the provider's layer frame
--     clear = function(provider, layer) end,       -- optional
--     group = "entrances",                         -- optional: the map switch
--                                                   -- group (Core/MapPins.lua);
--                                                   -- defaults to the id
--   }
--   ctx = { kind = "dungeon", key, floor, map, view ("art" | "layout"),
--           bounds, boundsSource, canvas }
--      or { kind = "world", uiMapID, canvas }
--   pin = { x, y (0-1) or world = { x, y } (dungeon only), id, label (a
--     number or short text), icon (texture or file id), atlas, size,
--     color = { r, g, b }, ring (true: accent ring), tooltip = text or
--     fn(tooltip, pin), onClick = fn(pin, mouseButton), highlight }
-- Pins are plain frames from a Lua pool on the canvas (no AcquirePin on
-- Blizzard's map, so nothing taints it).
--
-- Canvas (a frame from :CreateCanvas):
--   canvas:SetMap(key, floor, view)  view "art" (the client's tiles) or "layout"
--   canvas:Context(), canvas:MapArea() (the 3:2 drawing area),
--   canvas:Layer(name[, level]) -> an overlay frame over the map area (one per
--   name, sized with it), canvas:RefreshPins(), canvas:SetHighlight(id),
--   canvas:PinAt(id) -> the pin frame, canvas.onPinClick = fn(pin, button)
local _, E = ...

local DM = {}
E.DungeonMaps = DM

local TILE = 256
local MAP_W, MAP_H = 1002, 668
local MAX_FLOORS = 8
local MAX_ART_NUMBER = 24 -- highest floor number looked for in the art files
local LAYOUT_PAD = 0.12

local Secret = E.Secret

local defs = {}        -- key -> def
local byMap = {}       -- instance map id -> key
local wingOf = {}      -- wing key -> map key
local floorCache = {}  -- key -> floors
local layoutSources = {}
local providers, providerOrder = {}, {}
local canvases = setmetatable({}, { __mode = "k" })

---------------------------------------------------------------------------
-- Saved: last floor per dungeon and the uiMapIDs the client reported per
-- floor (EldoUIDB.dungeonMaps).
---------------------------------------------------------------------------
local function Store()
	if type(EldoUIDB) ~= "table" then return {} end
	local store = EldoUIDB.dungeonMaps
	if type(store) ~= "table" then
		store = {}
		EldoUIDB.dungeonMaps = store
	end
	if type(store.last) ~= "table" then store.last = {} end
	if type(store.uiMaps) ~= "table" then store.uiMaps = {} end
	return store
end

---------------------------------------------------------------------------
-- Registry
---------------------------------------------------------------------------
function DM:Register(key, def)
	assert(type(key) == "string" and type(def) == "table", "E.DungeonMaps:Register(key, def)")
	local old = defs[key]
	if old then
		for field, value in pairs(def) do old[field] = value end
		def = old
	else
		def.key = key
		defs[key] = def
	end
	if def.map then byMap[def.map] = key end
	for _, wing in ipairs(def.wings or {}) do wingOf[wing] = key end
	floorCache[key] = nil
	return def
end

function DM:Get(key)
	return defs[self:KeyFor(key) or ""]
end

-- A wing key ("sm_lib") or a map key ("scarlet") -> the map key.
function DM:KeyFor(key)
	if not key then return end
	if defs[key] then return key end
	return wingOf[key]
end

function DM:KeyForMap(instanceMap)
	return byMap[tonumber(instanceMap) or -1]
end

function DM:List()
	local list = {}
	for key in pairs(defs) do list[#list + 1] = key end
	table.sort(list)
	return list
end

-- The instance the player stands in (GetInstanceInfo), when it has a map.
function DM:CurrentDungeon()
	if not GetInstanceInfo then return end
	local _, instanceType, _, _, _, _, _, instanceID = GetInstanceInfo()
	if Secret(instanceType) or Secret(instanceID) then return end
	if instanceType ~= "party" and instanceType ~= "raid" then return end
	return byMap[tonumber(instanceID) or -1]
end

---------------------------------------------------------------------------
-- Art: which tile files the client has
---------------------------------------------------------------------------
local function FileExists(path)
	if not GetFileIDFromPath then return false end
	local ok, id = pcall(GetFileIDFromPath, path)
	return ok and not Secret(id) and type(id) == "number" and id > 0
end

-- The twelve tiles of one art floor. floor false: the one-floor form
-- without a floor number (<folder><tile>, as Zul'Farrak ships it).
local function TilePaths(folder, floor)
	local paths = {}
	for index = 1, 12 do
		if floor then
			paths[index] = ("Interface\\WorldMap\\%s\\%s%d_%d"):format(folder, folder, floor, index)
		else
			paths[index] = ("Interface\\WorldMap\\%s\\%s%d"):format(folder, folder, index)
		end
	end
	return paths
end

-- folder and the art floor numbers it has, in order: every numbered floor
-- the client ships (numbers can skip, as Uldaman's 1, 2 and 18 do), else
-- the one-floor form ({ false }). The first candidate folder with art wins.
local function FindArt(def)
	for _, folder in ipairs(def.art or {}) do
		local numbers = {}
		for floor = 1, MAX_ART_NUMBER do
			if FileExists(TilePaths(folder, floor)[1]) then numbers[#numbers + 1] = floor end
			if #numbers >= MAX_FLOORS then break end
		end
		if #numbers == 0 and FileExists(TilePaths(folder, false)[1]) then numbers[1] = false end
		if #numbers > 0 then return folder, numbers end
	end
end

---------------------------------------------------------------------------
-- Bounds
---------------------------------------------------------------------------
-- From the client's map API for a uiMapID: { left, right, top, bottom }.
local function MapBounds(uiMapID)
	if not (uiMapID and C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return end
	local ok1, _, topLeft = pcall(C_Map.GetWorldPosFromMapPos, uiMapID, CreateVector2D(0, 0))
	local ok2, _, bottomRight = pcall(C_Map.GetWorldPosFromMapPos, uiMapID, CreateVector2D(1, 1))
	if not (ok1 and ok2 and type(topLeft) == "table" and type(bottomRight) == "table") then return end
	local top, left, bottom, right = topLeft.x, topLeft.y, bottomRight.x, bottomRight.y
	for _, value in ipairs({ top, left, bottom, right }) do
		if type(value) ~= "number" or Secret(value) then return end
	end
	if top == bottom or left == right then return end
	return { left = left, right = right, top = top, bottom = bottom }
end

-- From where the creatures stand: a box around every point, padded, with
-- the art's 3:2 shape. Approximate by design.
local function LayoutBounds(def)
	local minX, maxX, minY, maxY
	for _, source in pairs(layoutSources) do
		local ok, points = pcall(source, def.key, def.map)
		if ok and type(points) == "table" then
			for _, p in ipairs(points) do
				local x, y = tonumber(p.x or p[1]), tonumber(p.y or p[2])
				if x and y then
					minX, maxX = math.min(minX or x, x), math.max(maxX or x, x)
					minY, maxY = math.min(minY or y, y), math.max(maxY or y, y)
				end
			end
		elseif not ok then
			geterrorhandler()(points)
		end
	end
	if not minX then return end
	local height, width = math.max(maxX - minX, 40), math.max(maxY - minY, 40)
	local cx, cy = (minX + maxX) / 2, (minY + maxY) / 2
	height, width = height * (1 + 2 * LAYOUT_PAD), width * (1 + 2 * LAYOUT_PAD)
	-- width : height = 3 : 2 (1002 x 668)
	if width / height < MAP_W / MAP_H then width = height * MAP_W / MAP_H else height = width * MAP_H / MAP_W end
	return { left = cy + width / 2, right = cy - width / 2, top = cx + height / 2, bottom = cx - height / 2 }
end

function DM:RegisterLayoutSource(id, fn)
	assert(type(fn) == "function", "E.DungeonMaps:RegisterLayoutSource(id, fn)")
	layoutSources[id] = fn
	wipe(floorCache)
end

---------------------------------------------------------------------------
-- Floors
---------------------------------------------------------------------------
-- The kept edges of one art floor (Data/DungeonFloorEdges.lua): number, or
-- false for the one-floor form.
local englishClient = (GetLocale and GetLocale() or "enUS"):sub(1, 2) == "en"

local function EdgesFor(def, art)
	if art == nil then return end
	for _, floor in ipairs(def.edges or {}) do
		if floor.art == art then return floor end
	end
end

local function BuildFloors(key)
	local def = defs[key]
	if not def then return {} end
	local folder, artFloors = FindArt(def)
	artFloors = artFloors or {}
	local listed = def.floors or {}
	local count = math.max(#artFloors, #listed, 1)
	local store = Store().uiMaps[key] or {}
	local floors = {}
	local layout
	for index = 1, count do
		-- A registered floor wins; else the edges kept for this art floor.
		local given = listed[index] or EdgesFor(def, artFloors[index]) or {}
		local name = given.name
		-- Kept floor names are the English client's; other clients number them.
		if not listed[index] and not englishClient then name = nil end
		local floor = { index = index, name = name, zones = given.zones, uiMapID = given.uiMapID or store[index] }
		if not floor.name and floor.uiMapID and C_Map and C_Map.GetMapInfo then
			local ok, info = pcall(C_Map.GetMapInfo, floor.uiMapID)
			if ok and type(info) == "table" and type(info.name) == "string" and not Secret(info.name) and info.name ~= "" then floor.name = info.name end
		end
		if folder and index <= #artFloors then
			floor.art = artFloors[index]
			floor.tiles = TilePaths(folder, artFloors[index])
		end
		if given.bounds then
			floor.bounds, floor.boundsSource = given.bounds, "data"
		else
			local bounds = MapBounds(floor.uiMapID)
			if bounds then
				floor.bounds, floor.boundsSource = bounds, "map"
			end
		end
		if not floor.bounds then
			layout = layout or LayoutBounds(def) or false
			if layout then floor.layout = layout end
		end
		floors[index] = floor
	end
	return floors
end

function DM:Floors(key)
	key = self:KeyFor(key)
	if not key then return {} end
	floorCache[key] = floorCache[key] or BuildFloors(key)
	return floorCache[key]
end

-- Forget what was worked out (new data, a new layout source).
function DM:Reset(key)
	if key then floorCache[self:KeyFor(key) or key] = nil else wipe(floorCache) end
end

function DM:HasArt(key)
	for _, floor in ipairs(self:Floors(key)) do
		if floor.tiles then return true end
	end
	return false
end

-- The bounds a view draws with: art needs real edges, layout takes the
-- worked-out box when there are none.
function DM:Bounds(key, floor, view)
	local entry = self:Floors(key)[floor or 1]
	if not entry then return end
	if entry.bounds then return entry.bounds, entry.boundsSource end
	if view ~= "art" and entry.layout then return entry.layout, "layout" end
end

local function ToMap(bounds, worldX, worldY)
	if not (bounds and worldX and worldY) then return end
	local x = (bounds.left - worldY) / (bounds.left - bounds.right)
	local y = (bounds.top - worldX) / (bounds.top - bounds.bottom)
	return x, y
end
DM.ToMap = ToMap

function DM:WorldToMap(key, floor, worldX, worldY, view)
	local bounds = self:Bounds(key, floor, view or "layout")
	local x, y = ToMap(bounds, tonumber(worldX), tonumber(worldY))
	if not x then return end
	return x, y
end

function DM:MapToWorld(key, floor, x, y, view)
	local bounds = self:Bounds(key, floor, view or "layout")
	if not (bounds and x and y) then return end
	return bounds.top - y * (bounds.top - bounds.bottom), bounds.left - x * (bounds.left - bounds.right)
end

---------------------------------------------------------------------------
-- Current floor (no position: what the client reports, else the last one)
---------------------------------------------------------------------------
function DM:LastFloor(key)
	key = self:KeyFor(key)
	return key and tonumber(Store().last[key]) or 1
end

function DM:SetLastFloor(key, floor)
	key = self:KeyFor(key)
	if key and tonumber(floor) then Store().last[key] = tonumber(floor) end
end

local function Fold(text)
	return tostring(text or ""):lower():gsub("[^%w]", "")
end

function DM:CurrentFloor(key)
	key = self:KeyFor(key) or self:CurrentDungeon()
	if not key then return 1 end
	local floors = self:Floors(key)
	if key == self:CurrentDungeon() then
		-- The map the client says the player is on (no position is read).
		if C_Map and C_Map.GetBestMapForUnit then
			local ok, uiMapID = pcall(C_Map.GetBestMapForUnit, "player")
			if ok and type(uiMapID) == "number" and not Secret(uiMapID) then
				for _, floor in ipairs(floors) do
					if floor.uiMapID == uiMapID then return floor.index, "map" end
				end
				local info = C_Map.GetMapInfo and C_Map.GetMapInfo(uiMapID)
				local name = type(info) == "table" and not Secret(info.name) and info.name
				if name then
					for _, floor in ipairs(floors) do
						if floor.name and Fold(floor.name) == Fold(name) then return floor.index, "map" end
					end
				end
			end
		end
		local sub = GetSubZoneText and GetSubZoneText()
		if type(sub) == "string" and not Secret(sub) and sub ~= "" then
			local folded = Fold(sub)
			for _, floor in ipairs(floors) do
				for _, zone in ipairs(floor.zones or {}) do
					if Fold(zone) == folded then return floor.index, "zone" end
				end
			end
		end
	end
	local last = self:LastFloor(key)
	if not floors[last] then last = 1 end
	return last, "last"
end

-- While the player is inside: ask the client which maps make up this
-- dungeon (the map it reports and that map's group, floor by floor) and
-- keep their uiMapIDs, so the map API can give each floor real edges.
-- Only the map ids are read, never a position. A dungeon with several
-- floors and no map group is not guessed. Returns true when something new
-- was learned.
function DM:LearnFloorMap(key)
	key = self:KeyFor(key)
	if not key or key ~= self:CurrentDungeon() or not (C_Map and C_Map.GetBestMapForUnit) then return end
	local ok, uiMapID = pcall(C_Map.GetBestMapForUnit, "player")
	if not ok or type(uiMapID) ~= "number" or Secret(uiMapID) then return end
	local found = {}
	local group = C_Map.GetMapGroupID and select(2, pcall(C_Map.GetMapGroupID, uiMapID))
	if type(group) == "number" and not Secret(group) and C_Map.GetMapGroupMembersInfo then
		local fine, members = pcall(C_Map.GetMapGroupMembersInfo, group)
		if fine and type(members) == "table" then
			table.sort(members, function(a, b) return (a.relativeHeightIndex or 0) < (b.relativeHeightIndex or 0) end)
			for index, member in ipairs(members) do
				if type(member.mapID) == "number" and not Secret(member.mapID) then found[index] = member.mapID end
			end
		end
	end
	if not found[1] then
		local floors = self:Floors(key)
		if #floors > 1 then return end
		found[1] = uiMapID
	end
	local store = Store().uiMaps
	store[key] = store[key] or {}
	local changed = false
	for index, mapID in pairs(found) do
		if store[key][index] ~= mapID and MapBounds(mapID) then
			store[key][index] = mapID
			changed = true
		end
	end
	if changed then floorCache[key] = nil end
	return changed
end

---------------------------------------------------------------------------
-- Pin providers
---------------------------------------------------------------------------
local function SortProviders()
	table.sort(providerOrder, function(a, b)
		local pa, pb = providers[a], providers[b]
		if (pa.order or 50) ~= (pb.order or 50) then return (pa.order or 50) < (pb.order or 50) end
		return a < b
	end)
end

function E:AddMapPinProvider(id, provider)
	assert(type(id) == "string" and type(provider) == "table", "EldoUI:AddMapPinProvider(id, provider)")
	if not providers[id] then table.insert(providerOrder, id) end
	providers[id] = provider
	provider.id = id
	SortProviders()
	self:RefreshMapPins()
	return provider
end

function E:RemoveMapPinProvider(id)
	if not providers[id] then return end
	for canvas in pairs(canvases) do
		local layer = canvas.layers and canvas.layers["provider:" .. id]
		if layer then
			if providers[id].clear then pcall(providers[id].clear, providers[id], layer) end
			layer:Hide()
		end
	end
	providers[id] = nil
	for index, other in ipairs(providerOrder) do
		if other == id then table.remove(providerOrder, index) break end
	end
	self:RefreshMapPins()
end

function E:MapPinProviders()
	local list = {}
	for _, id in ipairs(providerOrder) do list[#list + 1] = providers[id] end
	return list
end

-- Redraw pins on every canvas that shows a map (dungeon windows, the
-- world-map overlay).
function E:RefreshMapPins()
	for canvas in pairs(canvases) do
		if canvas:IsShown() and canvas.ctx then canvas:RefreshPins() end
	end
end

---------------------------------------------------------------------------
-- Pins (Lua pool per canvas)
---------------------------------------------------------------------------
local RING_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

local function Accent()
	local c = E.media and E.media.accentColor or { 0.2, 0.6, 1 }
	return c[1], c[2], c[3]
end

-- Pin discs and the canvas take the panel color of the art style,
-- read when drawn, so WoW: Forever's warm palette reaches the map too.
local function Surface(texture, alpha)
	local c = E.media and E.media.backdropColor or { 0, 0, 0 }
	texture:SetColorTexture(c[1], c[2], c[3], alpha)
end
DM.Surface = Surface

local function CreatePin(parent)
	local pin = CreateFrame("Button", nil, parent)
	pin:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	pin.ring = pin:CreateTexture(nil, "BORDER")
	pin.ring:SetAllPoints()
	pin.ring:SetColorTexture(Accent())
	pin.disc = pin:CreateTexture(nil, "ARTWORK")
	pin.disc:SetPoint("TOPLEFT", 1, -1)
	pin.disc:SetPoint("BOTTOMRIGHT", -1, 1)
	Surface(pin.disc, 0.95)
	pin.icon = pin:CreateTexture(nil, "OVERLAY")
	pin.icon:SetPoint("TOPLEFT", 2, -2)
	pin.icon:SetPoint("BOTTOMRIGHT", -2, 2)
	pin.mask = pin:CreateMaskTexture()
	pin.mask:SetTexture(RING_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	pin.mask:SetAllPoints()
	pin.ring:AddMaskTexture(pin.mask)
	pin.disc:AddMaskTexture(pin.mask)
	pin.icon:AddMaskTexture(pin.mask)
	pin.label = E:CreateText(pin, E.tokens.size.small, "CENTER")
	pin.label:SetPoint("CENTER", 0, 0)
	pin.label:SetTextColor(1, 1, 1)
	pin.badge = E:CreateText(pin, E.tokens.size.tiny, "CENTER")
	pin.badge:SetPoint("BOTTOMRIGHT", 3, -3)
	pin.badge:SetTextColor(1, 1, 1)
	pin.glow = pin:CreateTexture(nil, "BACKGROUND")
	pin.glow:SetPoint("TOPLEFT", -4, 4)
	pin.glow:SetPoint("BOTTOMRIGHT", 4, -4)
	pin.glow:SetColorTexture(1, 1, 1, 0.25)
	pin.glow:AddMaskTexture(pin.mask)
	pin.glow:Hide()
	-- pin.pulse: the glow breathes (a lit pin, e.g. the entrance you opened).
	pin.pulseAnim = pin.glow:CreateAnimationGroup()
	pin.pulseAnim:SetLooping("BOUNCE")
	local fade = pin.pulseAnim:CreateAnimation("Alpha")
	fade:SetFromAlpha(0.2)
	fade:SetToAlpha(1)
	fade:SetDuration(0.8)
	pin:SetScript("OnEnter", function(self)
		local data = self.data
		self.glow:Show()
		if not data or not data.tooltip then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		if type(data.tooltip) == "function" then
			local ok, err = pcall(data.tooltip, GameTooltip, data)
			if not ok then geterrorhandler()(err) end
		else
			E.UIKit.TipTitle(GameTooltip, data.tooltip, true)
		end
		GameTooltip:Show()
	end)
	pin:SetScript("OnLeave", function(self)
		if not (self.data and (self.data.highlight or self.data.pulse)) then self.glow:Hide() end
		GameTooltip:Hide()
	end)
	pin:SetScript("OnClick", function(self, button)
		local data = self.data
		if not data then return end
		if data.onClick then
			local ok, err = pcall(data.onClick, data, button, self)
			if not ok then geterrorhandler()(err) end
		end
		local canvas = self.canvas
		if canvas and canvas.onPinClick then canvas.onPinClick(data, button, self) end
	end)
	return pin
end

-- scale: the zoom of the canvas the area sits on (the world map's canvas
-- scale; 1 elsewhere). The pin is counter-scaled so it keeps its size on
-- screen while the map zooms, and its offsets are scaled to match.
local function PlacePin(pin, data, area, scale)
	scale = scale or 1
	pin:SetScale(1 / scale)
	pin:ClearAllPoints()
	pin:SetPoint("CENTER", area, "TOPLEFT", data.x * area:GetWidth() * scale, -data.y * area:GetHeight() * scale)
end

local function SetPin(pin, data, area, scale)
	pin.data = data
	local size = data.size or 20
	pin:SetSize(size, size)
	PlacePin(pin, data, area, scale)
	Surface(pin.disc, 0.95)
	if data.ring == false then
		pin.ring:SetColorTexture(0, 0, 0, 0.9)
	elseif data.color then
		pin.ring:SetColorTexture(data.color[1], data.color[2], data.color[3], 1)
	else
		pin.ring:SetColorTexture(Accent())
	end
	if data.atlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(data.atlas) then
		pin.icon:SetAtlas(data.atlas)
		pin.icon:Show()
	elseif data.icon then
		pin.icon:SetTexture(data.icon)
		pin.icon:Show()
	else
		pin.icon:Hide()
	end
	local hasIcon = pin.icon:IsShown()
	pin.label:SetShown(not hasIcon and data.label ~= nil)
	pin.badge:SetShown(hasIcon and data.label ~= nil)
	pin.label:SetText(data.label and tostring(data.label) or "")
	pin.badge:SetText(data.label and tostring(data.label) or "")
	pin.glow:SetShown((data.highlight or data.pulse) and true or false)
	-- With motion reduced the lit pin keeps a steady glow.
	if data.pulse and (not E.MotionOn or E:MotionOn()) then
		if not pin.pulseAnim:IsPlaying() then pin.pulseAnim:Play() end
	elseif pin.pulseAnim:IsPlaying() then
		pin.pulseAnim:Stop()
	end
	pin:Show()
end
DM.CreatePin, DM.SetPin = CreatePin, SetPin

---------------------------------------------------------------------------
-- Canvas
---------------------------------------------------------------------------
local Canvas = {}

function Canvas:MapArea()
	return self.area
end

function Canvas:Context()
	return self.ctx
end

-- An overlay frame over the map area; one per name.
function Canvas:Layer(name, level)
	self.layers = self.layers or {}
	local layer = self.layers[name]
	if not layer then
		layer = CreateFrame("Frame", nil, self.area)
		layer:SetAllPoints(self.area)
		layer.name = name
		self.layers[name] = layer
	end
	layer:SetFrameLevel(self.area:GetFrameLevel() + (level or 5))
	layer:Show()
	return layer
end

-- Keep the drawing area at 3:2 inside the canvas.
function Canvas:Fit()
	local width, height = self:GetWidth() or 0, self:GetHeight() or 0
	if width <= 0 or height <= 0 then return end
	local w, h = width, width * MAP_H / MAP_W
	if h > height then h, w = height, height * MAP_W / MAP_H end
	self.area:SetSize(w, h)
	local scale = w / MAP_W
	for index, tile in ipairs(self.tiles) do
		local col, row = (index - 1) % 4, math.floor((index - 1) / 4)
		tile:SetSize(TILE * scale, TILE * scale)
		tile:ClearAllPoints()
		tile:SetPoint("TOPLEFT", self.area, "TOPLEFT", col * TILE * scale, -row * TILE * scale)
	end
end

function Canvas:SetMap(key, floor, view)
	key = DM:KeyFor(key)
	local floors = key and DM:Floors(key) or {}
	floor = floors[tonumber(floor) or 0] and tonumber(floor) or 1
	local entry = floors[floor]
	if view ~= "layout" and not (entry and entry.tiles) then view = "layout" end
	local bounds, source = DM:Bounds(key, floor, view)
	self.ctx = { kind = "dungeon", key = key, floor = floor, map = key and defs[key] and defs[key].map, view = view,
		bounds = bounds, boundsSource = source, canvas = self, floors = #floors }
	for index, tile in ipairs(self.tiles) do
		if view == "art" and entry and entry.tiles then
			tile:SetTexture(entry.tiles[index])
			tile:Show()
		else
			tile:Hide()
		end
	end
	self.grid:SetShown(view ~= "art")
	Surface(self.bg, 0.9)
	self:Fit()
	self:RefreshPins()
	return self.ctx
end

-- For overlays on another map (the world map): a fixed context.
function Canvas:SetContext(ctx)
	ctx.canvas = self
	self.ctx = ctx
	for _, tile in ipairs(self.tiles) do tile:Hide() end
	self.grid:Hide()
	self:RefreshPins()
end

-- The zoom of the canvas this one sits on (an overlay sets PinScale).
function Canvas:CurrentPinScale()
	local scale = self.PinScale and self:PinScale()
	if type(scale) ~= "number" or scale <= 0.01 then return 1 end
	return scale
end

-- Only the zoom changed: keep the pins, fix their scale and place.
function Canvas:RescalePins()
	local scale = self:CurrentPinScale()
	for _, pin in ipairs(self.pins) do
		if pin.data and pin:IsShown() then PlacePin(pin, pin.data, self.area, scale) end
	end
end

function Canvas:RefreshPins()
	local ctx = self.ctx
	local scale = self:CurrentPinScale()
	for _, pin in ipairs(self.pins) do
		pin:Hide()
		pin.data = nil
		if pin.pulseAnim:IsPlaying() then pin.pulseAnim:Stop() end
	end
	self.byID = {}
	if not ctx then return end
	local used = 0
	for _, id in ipairs(providerOrder) do
		local provider = providers[id]
		-- On the world map the EldoUI map switch (Core/MapPins.lua) can hide a
		-- provider's group; the Loot Guide's own dungeon window shows all.
		-- On a continent or world map the map level rule can hide it too.
		local hidden = ctx.kind == "world" and E.MapPinGroupShown and not E:MapPinGroupShown(provider.group or id, "world", ctx.uiMapID)
		if hidden then
			local layer = self.layers and self.layers["provider:" .. id]
			if layer then
				if provider.clear then pcall(provider.clear, provider, layer) end
				layer:Hide()
			end
		end
		local layer = not hidden and self:Layer("provider:" .. id, 10 + used % 5)
		if not hidden and provider.draw then
			local ok, err = pcall(provider.draw, provider, layer, ctx)
			if not ok then geterrorhandler()(err) end
		end
		if provider.pins and not hidden then
			local ok, list = pcall(provider.pins, provider, ctx)
			if not ok then
				geterrorhandler()(list)
			elseif type(list) == "table" then
				for _, data in ipairs(list) do
					if data.world and ctx.kind == "dungeon" and ctx.bounds then
						data.x, data.y = ToMap(ctx.bounds, data.world.x or data.world[1], data.world.y or data.world[2])
					end
					local x, y = tonumber(data.x), tonumber(data.y)
					if x and y and x >= -0.02 and x <= 1.02 and y >= -0.02 and y <= 1.02 then
						used = used + 1
						local pin = self.pins[used]
						if not pin then
							pin = CreatePin(self.pinLayer)
							pin.canvas = self
							self.pins[used] = pin
						end
						pin:SetFrameLevel(self.pinLayer:GetFrameLevel() + 2)
						data.provider = id
						SetPin(pin, data, self.area, scale)
						if data.id then self.byID[data.id] = pin end
					end
				end
			end
		end
	end
	self.pinCount = used
end

function Canvas:PinAt(id)
	return self.byID and self.byID[id]
end

function Canvas:SetHighlight(id)
	for _, pin in ipairs(self.pins) do
		if pin.data then
			pin.data.highlight = (id ~= nil and pin.data.id == id) or nil
			pin.glow:SetShown((pin.data.highlight or pin.data.pulse) and true or false)
		end
	end
end

function DM:CreateCanvas(parent)
	local canvas = CreateFrame("Frame", nil, parent)
	for name, fn in pairs(Canvas) do canvas[name] = fn end
	canvas.area = CreateFrame("Frame", nil, canvas)
	canvas.area:SetPoint("CENTER")
	canvas.area:SetSize(MAP_W / 2, MAP_H / 2)
	canvas.area:SetClipsChildren(true)
	canvas.bg = canvas.area:CreateTexture(nil, "BACKGROUND")
	canvas.bg:SetAllPoints()
	Surface(canvas.bg, 0.9)
	-- The layout view: a quiet grid every tenth of the map.
	canvas.grid = CreateFrame("Frame", nil, canvas.area)
	canvas.grid:SetAllPoints()
	for index = 1, 9 do
		local v = canvas.grid:CreateTexture(nil, "BORDER")
		v:SetColorTexture(unpack(E.tokens.track))
		v:SetWidth(E.pixel or 1)
		v:SetPoint("TOP", canvas.grid, "TOPLEFT", 0, 0)
		v:SetPoint("BOTTOM", canvas.grid, "BOTTOMLEFT", 0, 0)
		v.fraction = index / 10
		local h = canvas.grid:CreateTexture(nil, "BORDER")
		h:SetColorTexture(unpack(E.tokens.track))
		h:SetHeight(E.pixel or 1)
		h:SetPoint("LEFT", canvas.grid, "TOPLEFT", 0, 0)
		h:SetPoint("RIGHT", canvas.grid, "TOPRIGHT", 0, 0)
		h.fraction = index / 10
		canvas.grid[index] = { v = v, h = h }
	end
	canvas.tiles = {}
	for index = 1, 12 do
		local tile = canvas.area:CreateTexture(nil, "ARTWORK")
		tile:Hide()
		canvas.tiles[index] = tile
	end
	canvas.pinLayer = CreateFrame("Frame", nil, canvas.area)
	canvas.pinLayer:SetAllPoints()
	canvas.pinLayer:SetFrameLevel(canvas.area:GetFrameLevel() + 30)
	canvas.pins = {}
	canvas:SetScript("OnSizeChanged", function(frame)
		frame:Fit()
		local w, h = frame.area:GetWidth(), frame.area:GetHeight()
		for _, line in ipairs(frame.grid) do
			line.v:SetPoint("TOP", frame.grid, "TOPLEFT", w * line.v.fraction, 0)
			line.v:SetPoint("BOTTOM", frame.grid, "BOTTOMLEFT", w * line.v.fraction, 0)
			line.h:SetPoint("LEFT", frame.grid, "TOPLEFT", 0, -h * line.h.fraction)
			line.h:SetPoint("RIGHT", frame.grid, "TOPRIGHT", 0, -h * line.h.fraction)
		end
		if frame.ctx then frame:RefreshPins() end
	end)
	canvases[canvas] = true
	return canvas
end

---------------------------------------------------------------------------
-- The world map: one overlay canvas on Blizzard's map canvas for pins of
-- kind "world". Attached the first time a caller asks (no own pins on the
-- Blizzard map otherwise). Pins are our own frames; Blizzard's pin pools
-- are never used.
---------------------------------------------------------------------------
local worldCanvas

local function WorldContext()
	local frame = _G.WorldMapFrame
	local uiMapID = frame and frame.GetMapID and frame:GetMapID()
	if Secret(uiMapID) then return end
	return uiMapID and { kind = "world", uiMapID = uiMapID } or nil
end

local function SyncWorld()
	if not worldCanvas then return end
	local child = worldCanvas:GetParent()
	worldCanvas.area:SetSize(child:GetWidth() or 1, child:GetHeight() or 1)
	local ctx = WorldContext()
	if ctx then worldCanvas:SetContext(ctx) end
end

function DM:AttachWorldMap()
	if worldCanvas then return worldCanvas end
	local frame = _G.WorldMapFrame
	local child = frame and frame.ScrollContainer and frame.ScrollContainer.Child
	if not child then return end
	worldCanvas = DM:CreateCanvas(child)
	worldCanvas:SetAllPoints(child)
	worldCanvas:SetFrameLevel((child:GetFrameLevel() or 1) + 50)
	worldCanvas.bg:Hide()
	worldCanvas.area:ClearAllPoints()
	worldCanvas.area:SetPoint("TOPLEFT")
	worldCanvas.area:SetClipsChildren(false)
	worldCanvas.Fit = function(overlay)
		local parent = overlay:GetParent()
		overlay.area:SetSize(parent:GetWidth() or 1, parent:GetHeight() or 1)
	end
	-- Pins sit on the zooming canvas: counter-scale them like Blizzard's
	-- own pins so zooming in doesn't blow them up.
	worldCanvas.PinScale = function()
		local ok, scale = pcall(frame.GetCanvasScale, frame)
		if ok and type(scale) == "number" and not Secret(scale) then return scale end
	end
	worldCanvas:SetScript("OnSizeChanged", function(overlay)
		overlay:Fit()
		if overlay.ctx then overlay:RefreshPins() end
	end)
	frame:HookScript("OnShow", SyncWorld)
	if frame.OnMapChanged then hooksecurefunc(frame, "OnMapChanged", SyncWorld) end
	if type(frame.OnCanvasScaleChanged) == "function" then
		hooksecurefunc(frame, "OnCanvasScaleChanged", function()
			if worldCanvas.ctx then worldCanvas:RescalePins() end
		end)
	end
	SyncWorld()
	return worldCanvas
end

function DM:WorldCanvas()
	return worldCanvas
end

---------------------------------------------------------------------------
-- The Classic list (Data/DungeonFloors.lua)
---------------------------------------------------------------------------
for key, def in pairs(E.DungeonFloorData or {}) do
	def = CopyTable(def)
	def.edges = E.DungeonFloorEdges and E.DungeonFloorEdges[key]
	DM:Register(key, def)
end
