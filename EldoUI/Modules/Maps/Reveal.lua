-- EldoUI Maps: unexplored areas dimmed instead of black.
--
-- World Map > "Show unexplored areas" (off by default). The game only says
-- which map overlays you have explored (C_MapExplorationInfo.
-- GetExploredMapTextures); it has no call that lists every overlay of a
-- map. So EldoUI remembers, account-wide, every overlay any of your
-- characters has explored (the same art the game shows them, read from the
-- game), and on a character that has not explored it yet draws that art
-- dimmed where the game leaves the map dark. Data/MapOverlays.lua lists
-- the overlays of every zone for one game build, built from Blizzard's own
-- client data, so areas show before anyone has explored them; what your
-- characters explore still wins over that list. Without the list, areas
-- none of your characters has seen stay dark until one of them goes there.
--
-- Drawn as EldoUI's own textures on the world map canvas, at the frame
-- level of the game's own exploration overlays, so pins stay on top.
-- Explored areas are left exactly as the game draws them. Follows the
-- world map's Improve switch (Blizzard UI page), like the coordinates.
--
-- Written from the documented UiMapExplorationInfo and
-- UiMapLayerInfo structures (tiles of tileWidth x tileHeight, row by row).
local _, E = ...
local L = E.L

local M = E:GetModule("Maps")
if not M then return end

local WORLD = "world-map-quest-log"
local R = {}
M.reveal = R

M.defaults.worldMap.reveal = false
M.defaults.worldMap.revealAlpha = 0.5
M.defaults.worldMap.revealTint = "gray"   -- gray | natural

local function Try(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a = pcall(fn, ...)
	if ok then return a end
end

local Clean = E.Plain

local function On()
	return M.active and E:BlizzardAllowed(WORLD, "improve") and M.db.worldMap.reveal and true or false
end

---------------------------------------------------------------------------
-- What your characters have explored, per map (account-wide)
--   E.global.MapReveal.maps[uiMapID][key] = { w, h, x, y, top, "id,id,..." }
--   key = the overlay's first file id
---------------------------------------------------------------------------
local function Store()
	local store = E:GetGlobal("MapReveal")
	if type(store) ~= "table" then return nil end
	if type(store.maps) ~= "table" then store.maps = {} end
	return store.maps
end

-- The overlays the game reports explored on a map, cleaned: { key = info }.
local function Explored(uiMapID)
	local out = {}
	local api = C_MapExplorationInfo
	local list = api and api.GetExploredMapTextures and Try(api.GetExploredMapTextures, uiMapID)
	for _, info in ipairs(type(list) == "table" and list or {}) do
		local ids = type(info) == "table" and info.fileDataIDs
		local first = type(ids) == "table" and Clean(ids[1])
		local w, h = Clean(info.textureWidth), Clean(info.textureHeight)
		local x, y = Clean(info.offsetX), Clean(info.offsetY)
		if type(first) == "number" and type(w) == "number" and type(h) == "number" and type(x) == "number" and type(y) == "number" then
			local parts = {}
			for index, id in ipairs(ids) do
				id = Clean(id)
				if type(id) ~= "number" then parts = nil break end
				parts[index] = id
			end
			if parts then
				out[first] = {
					w = w, h = h, x = x, y = y, ids = parts,
					top = Clean(info.isDrawOnTopLayer) == true, mouseOver = Clean(info.isShownByMouseOver) == true,
				}
			end
		end
	end
	return out
end
R.Explored = Explored

-- Remember what this character has explored on a map. Returns the explored set.
function R:Learn(uiMapID)
	if type(uiMapID) ~= "number" then return {} end
	local explored = Explored(uiMapID)
	local maps = Store()
	if not maps then return explored end
	for key, info in pairs(explored) do
		-- Mouse-over highlights (cities on continent maps) are not fog.
		if not info.mouseOver then
			maps[uiMapID] = maps[uiMapID] or {}
			if not maps[uiMapID][key] then
				maps[uiMapID][key] = { info.w, info.h, info.x, info.y, info.top and 1 or 0, table.concat(info.ids, ",") }
			end
		end
	end
	return explored
end

-- The shipped overlay list of a map (Data/MapOverlays.lua), when there is one.
local function Shipped(uiMapID)
	local data = E.MapOverlayData
	local maps = type(data) == "table" and type(data.maps) == "table" and data.maps
	local rows = maps and maps[uiMapID]
	return type(rows) == "table" and rows or nil
end

local function Valid(row)
	return type(row) == "table" and type(row[1]) == "number" and type(row[2]) == "number"
		and type(row[3]) == "number" and type(row[4]) == "number" and type(row[6]) == "string"
end

local function Place(w, h, x, y) return ("%s:%s:%s:%s"):format(w, h, x, y) end

-- Every overlay known for a map: what your characters explored, then the
-- shipped list under it (learned rows win on the same key). A shipped row
-- in the same place and size as an explored or learned overlay with other
-- files is art from another game build, so the game's answer is kept.
local function Known(uiMapID, explored)
	local out, taken = {}, {}
	local maps = Store()
	for key, row in pairs(maps and maps[uiMapID] or {}) do
		if Valid(row) then
			out[key] = row
			taken[Place(row[1], row[2], row[3], row[4])] = true
		end
	end
	for _, info in pairs(explored or {}) do
		if not info.mouseOver then taken[Place(info.w, info.h, info.x, info.y)] = true end
	end
	for key, row in pairs(Shipped(uiMapID) or {}) do
		if out[key] == nil and type(key) == "number" and Valid(row) and not taken[Place(row[1], row[2], row[3], row[4])] then
			out[key] = row
		end
	end
	return out
end

-- Overlays known for a map that this character has not explored.
function R:Missing(uiMapID)
	local explored = self:Learn(uiMapID)
	local out = {}
	for key, row in pairs(Known(uiMapID, explored)) do
		if not explored[key] then
			local ids = {}
			for id in row[6]:gmatch("%d+") do ids[#ids + 1] = tonumber(id) end
			out[#out + 1] = { key = key, w = row[1], h = row[2], x = row[3], y = row[4], top = row[5] == 1, ids = ids }
		end
	end
	table.sort(out, function(a, b) return a.key < b.key end)
	return out
end

-- How many overlays are known for a map, and how many this character lacks.
function R:Counts(uiMapID)
	local missing = #self:Missing(uiMapID)
	local known = 0
	for _ in pairs(Known(uiMapID, Explored(uiMapID))) do known = known + 1 end
	return known, missing
end

---------------------------------------------------------------------------
-- Tiles: an overlay is cut in tiles of the map's tile size, row by row;
-- the last row and column are what is left, in a power-of-two file.
---------------------------------------------------------------------------
local function PowerOfTwo(size)
	local n = 1
	while n < size do n = n * 2 end
	return n
end

-- { { id, left, top, width, height, u, v } } in map art pixels.
function R.Tiles(overlay, tileWidth, tileHeight)
	tileWidth, tileHeight = tileWidth or 256, tileHeight or 256
	local wide = math.max(1, math.ceil(overlay.w / tileWidth))
	local tall = math.max(1, math.ceil(overlay.h / tileHeight))
	local tiles = {}
	for row = 1, tall do
		local height, fileHeight = tileHeight, tileHeight
		if row == tall then
			height = overlay.h - tileHeight * (row - 1)
			if height <= 0 then height = tileHeight end
			fileHeight = PowerOfTwo(height)
		end
		for col = 1, wide do
			local width, fileWidth = tileWidth, tileWidth
			if col == wide then
				width = overlay.w - tileWidth * (col - 1)
				if width <= 0 then width = tileWidth end
				fileWidth = PowerOfTwo(width)
			end
			local id = overlay.ids[(row - 1) * wide + col]
			if id then
				tiles[#tiles + 1] = {
					id = id, left = overlay.x + tileWidth * (col - 1), top = overlay.y + tileHeight * (row - 1),
					width = width, height = height, u = width / fileWidth, v = height / fileHeight,
				}
			end
		end
	end
	return tiles
end

---------------------------------------------------------------------------
-- Drawing on the world map canvas
---------------------------------------------------------------------------
local frame
local textures = {}
R.textures = textures

local function WorldMap()
	local map = _G.WorldMapFrame
	return (type(map) == "table" and map.GetCanvas and E:SkinUsable(map)) and map or nil
end

-- The frame level of the game's own exploration overlays, so ours sit
-- with them: over the map art, under every pin.
local function OverlayLevel(map, canvas)
	if map.EnumeratePinsByTemplate then
		local ok, level = pcall(function()
			for pin in map:EnumeratePinsByTemplate("MapExplorationPinTemplate") do
				if type(pin) == "table" and pin.GetFrameLevel then return pin:GetFrameLevel() end
			end
		end)
		if ok and type(level) == "number" then return level end
	end
	return canvas:GetFrameLevel() + 1
end

function R:Hide()
	for _, texture in ipairs(textures) do texture:Hide() end
	self.drawn = 0
	if frame then frame:Hide() end
end

function R:Refresh()
	self:Hide()
	local map = WorldMap()
	if not (map and map.IsShown and map:IsShown()) then return end
	local uiMapID = map.GetMapID and Clean(map:GetMapID())
	if type(uiMapID) ~= "number" then return end
	if not On() then
		self:Learn(uiMapID) -- remember even while the option is off
		return
	end
	local canvas = map:GetCanvas()
	if not canvas then return end
	local layers = C_Map and C_Map.GetMapArtLayers and Try(C_Map.GetMapArtLayers, uiMapID)
	local layer = type(layers) == "table" and layers[1]
	local layerWidth = layer and Clean(layer.layerWidth)
	local width, height = canvas:GetSize()
	if not (width and width > 0 and height and height > 0) then return end
	local scale = (type(layerWidth) == "number" and layerWidth > 0) and width / layerWidth or 1
	local tileWidth = layer and Clean(layer.tileWidth) or 256
	local tileHeight = layer and Clean(layer.tileHeight) or 256
	frame = frame or CreateFrame("Frame", nil, canvas)
	frame:SetParent(canvas)
	frame:ClearAllPoints()
	frame:SetAllPoints(canvas)
	frame:SetFrameLevel(OverlayLevel(map, canvas))
	frame:Show()
	local db = M.db.worldMap
	local alpha = math.min(1, math.max(0.1, tonumber(db.revealAlpha) or 0.5))
	local tint = db.revealTint == "natural" and { 1, 1, 1 } or E.tokens.map.unexplored
	local count = 0
	for _, overlay in ipairs(self:Missing(uiMapID)) do
		for _, tile in ipairs(R.Tiles(overlay, tileWidth, tileHeight)) do
			count = count + 1
			local texture = textures[count]
			if not texture then
				texture = frame:CreateTexture(nil, "ARTWORK")
				textures[count] = texture
			end
			texture:SetDrawLayer(overlay.top and "OVERLAY" or "ARTWORK")
			texture:SetTexture(tile.id, nil, nil, "TRILINEAR")
			texture:SetTexCoord(0, tile.u, 0, tile.v)
			texture:ClearAllPoints()
			texture:SetPoint("TOPLEFT", frame, "TOPLEFT", tile.left * scale, -tile.top * scale)
			texture:SetSize(tile.width * scale, tile.height * scale)
			texture:SetDesaturated(db.revealTint ~= "natural")
			texture:SetVertexColor(tint[1], tint[2], tint[3], alpha)
			texture:Show()
		end
	end
	self.drawn = count
end

local provider
local function CreateProvider()
	local base = _G.MapCanvasDataProviderMixin
	local p = base and CreateFromMixins and CreateFromMixins(base) or {}
	function p:OnAdded(owningMap) self.owningMap = owningMap end
	function p:OnRemoved() self.owningMap = nil end
	function p:RemoveAllData() R:Hide() end
	function p:RefreshAllData() R:Refresh() end
	function p:OnMapChanged() R:Refresh() end
	function p:OnCanvasSizeChanged() R:Refresh() end
	function p:OnShow() R:Refresh() end
	function p:OnHide() R:Hide() end
	return p
end

function R:Hook()
	local map = WorldMap()
	if not map then
		if not self.waiting and E.OnBlizzardAddOn then
			self.waiting = true
			E:OnBlizzardAddOn("Blizzard_WorldMap", function() R.waiting = nil R:Hook() end)
		end
		return
	end
	if not self.hooked and map.AddDataProvider then
		self.hooked = true
		provider = provider or CreateProvider()
		map:AddDataProvider(provider)
	end
	self:Refresh()
end

-- Remember the zone you stand in as you explore it, map open or not.
local function LearnHere()
	local uiMapID = C_Map and C_Map.GetBestMapForUnit and Clean(Try(C_Map.GetBestMapForUnit, "player"))
	if type(uiMapID) == "number" then R:Learn(uiMapID) end
	if R.drawn and R.drawn > 0 or On() then R:Refresh() end
end

-- Called by the Maps module (Modules/Maps/Core.lua). The events use R as their
-- owner: Maps keeps its own PLAYER_ENTERING_WORLD handler.
local EVENTS = { "MAP_EXPLORATION_UPDATED", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD" }

function R:Initialize()
	E:RegisterGlobal("MapReveal", { maps = {} }, { title = "Explored map areas", desc = "The map areas your characters have explored, so the others' maps can show them dimmed." })
end

function R:Enable()
	for _, event in ipairs(EVENTS) do E:RegisterEvent(event, LearnHere, R) end
	self:Hook()
end

function R:Disable()
	for _, event in ipairs(EVENTS) do E:UnregisterEvent(event, R) end
	self:Hide()
end

---------------------------------------------------------------------------
-- Options: World map tab, after the coordinates
---------------------------------------------------------------------------
local function NoImprove() return not E:BlizzardAllowed(WORLD, "improve") end
local rows = {
	{ type = "header", label = "Unexplored areas (Improve)" },
	{ type = "toggle", key = "worldMap.reveal", label = "Show unexplored areas",
		desc = "Parts of a zone you haven't found yet show dimmed instead of dark, in every zone from your first login. The game's own art for what your characters explore is remembered too and always wins.",
		hidden = NoImprove },
	{ type = "range", percent = true, key = "worldMap.revealAlpha", label = "Dimness", min = 0.1, max = 1, step = 0.05,
		desc = "How strongly the unexplored areas show: low values are faint.", dependsOn = "worldMap.reveal", hidden = NoImprove },
	{ type = "select", key = "worldMap.revealTint", label = "Look", order = { "gray", "natural" },
		values = { gray = "Gray", natural = "Map colors" },
		desc = "Gray: the unexplored areas in gray, so they stand apart from the explored map. Map colors: the map's own colors, only fainter.",
		dependsOn = "worldMap.reveal", hidden = NoImprove },
}
local at
for index, row in ipairs(M.options) do
	if row.type == "header" and row.label == "Fading (Improve)" then at = index break end
end
at = at or (#M.options + 1)
for offset, row in ipairs(rows) do table.insert(M.options, at + offset - 1, row) end
