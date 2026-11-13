-- EldoUI Map Notes: pins on the world map and the minimap, their tooltip and
-- their right-click menu.
--
-- Like Waypoints and Gathering, the pins are EldoUI's own frames: on the
-- world map's canvas (a data provider only tells us when the map changes;
-- Blizzard's pin pools are never used) and on the minimap at each point's
-- offset from you, scaled by the minimap's view radius. The minimap shows
-- the points of the zone you are in, and nothing where the game hides your
-- position (dungeons, raids).
local _, E = ...
local L = E.L
local Key = E.Key
local M = E.MapNotes

local max = math.max
local Try, Clean = M.Try, M.Clean
local issecret = issecretvalue or function() return false end

local RING_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local SKULL = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8"
local CHEST = "Interface\\Icons\\INV_Box_02"
local GREY = { 0.7, 0.7, 0.75 }

-- Sizes in pixels before pinScale / minimapScale (design.md §2.1).
local SIZE = { rare = 16, elite = 18, treasure = 15, note = 16, service = 14 }

---------------------------------------------------------------------------
-- Items: quality and icon of a point's best drop
---------------------------------------------------------------------------
local function ItemQuality(itemID)
	if not (C_Item and itemID) then return end
	local quality = C_Item.GetItemQualityByID and Clean(Try(C_Item.GetItemQualityByID, itemID))
	if quality == nil and C_Item.RequestLoadItemDataByID then Try(C_Item.RequestLoadItemDataByID, itemID) end
	return quality
end

local function ItemIcon(itemID)
	if not (C_Item and itemID) then return end
	if C_Item.GetItemIconByID then
		local icon = Clean(Try(C_Item.GetItemIconByID, itemID))
		if icon then return icon end
	end
	if C_Item.GetItemInfoInstant then return Clean(select(5, Try(C_Item.GetItemInfoInstant, itemID))) end
end

local function QualityColor(quality)
	if not quality then return GREY end
	if C_Item and C_Item.GetItemQualityColor then
		local r, g, b = Try(C_Item.GetItemQualityColor, quality)
		if type(r) == "number" then return { r, g, b } end
	end
	local color = rawget(_G, "ITEM_QUALITY_COLORS") and ITEM_QUALITY_COLORS[quality]
	if color then return { color.r, color.g, color.b } end
	return GREY
end

-- itemID, quality of the best drop (highest quality, then highest chance).
function M.BestDrop(point)
	local best, bestQuality, bestChance
	for _, row in ipairs(point.loot or {}) do
		local quality = ItemQuality(row.itemID) or 1
		local chance = tonumber(row.chance) or 0
		if not best or quality > bestQuality or (quality == bestQuality and chance > bestChance) then
			best, bestQuality, bestChance = row.itemID, quality, chance
		end
	end
	return best, bestQuality
end

---------------------------------------------------------------------------
-- Pin look
---------------------------------------------------------------------------
local function KindAtlas(point)
	if point.kind == "rare" then return point.elite and "VignetteKillElite" or "VignetteKill", SKULL end
	if point.kind == "treasure" then return "VignetteLoot", CHEST end
	local icon = point.icon or {}
	return icon.atlas, icon.texture or CHEST
end

local function GroupColor(point)
	if point.kind == "note" or point.kind == "service" then
		local c = E.media.accentColor
		return { c[1], c[2], c[3] }
	end
	local _, quality = M.BestDrop(point)
	return QualityColor(quality and quality >= 2 and quality or nil)
end

-- The look a pin takes: "tile" (Modern), "atlas" (game icons), "ring"
-- (Classic and WoW Forever; the skin's pinShape flag decides), "dot" or "item".
local function PinShape()
	local style = M.db.iconStyle
	if style == "game" then return "atlas" end
	if style == "dots" then return "dot" end
	if style == "icons" then return "item" end
	local shape = E.SkinFlag and E:SkinFlag("pinShape")
	if shape then return shape end
	return "tile"
end

local function CreatePin(parent)
	local pin = CreateFrame("Button", nil, parent)
	pin:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	pin.edge = pin:CreateTexture(nil, "BACKGROUND")
	pin.edge:SetAllPoints()
	pin.edge:SetTexture(E.media.flat)
	pin.fill = pin:CreateTexture(nil, "BORDER")
	pin.fill:SetTexture(E.media.flat)
	pin.icon = pin:CreateTexture(nil, "ARTWORK")
	pin.mask = pin:CreateMaskTexture()
	pin.mask:SetTexture(RING_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	pin.mask:SetAllPoints()
	pin.tick = pin:CreateTexture(nil, "OVERLAY")
	pin.tick:SetSize(8, 8)
	pin.tick:SetPoint("BOTTOMRIGHT", 2, -2)
	E:SetClientAtlas(pin.tick, "common-icon-checkmark", "Interface\\RaidFrame\\ReadyCheck-Ready")
	pin.tick:Hide()
	pin.glow = pin:CreateTexture(nil, "BACKGROUND", nil, -1)
	pin.glow:SetPoint("TOPLEFT", -3, 3)
	pin.glow:SetPoint("BOTTOMRIGHT", 3, -3)
	pin.glow:SetTexture(E.media.flat)
	pin.glow:SetVertexColor(1, 1, 1, 0.25)
	pin.glow:Hide()
	pin:SetScript("OnEnter", function(self)
		self.glow:Show()
		M:PinTooltip(self)
	end)
	pin:SetScript("OnLeave", function(self)
		self.glow:Hide()
		GameTooltip:Hide()
	end)
	pin:SetScript("OnClick", function(self, button)
		if button == "RightButton" then M:PinMenu(self) end
	end)
	return pin
end

local function SetMasked(pin, on)
	if pin.masked == on then return end
	pin.masked = on
	for _, region in ipairs({ pin.edge, pin.fill, pin.icon, pin.glow }) do
		if on then region:AddMaskTexture(pin.mask) else region:RemoveMaskTexture(pin.mask) end
	end
end

local function StylePin(pin, point, size)
	pin.point = point
	local shape = PinShape()
	local color = GroupColor(point)
	pin:SetSize(size, size)
	pin:SetAlpha(M.db.pinAlpha)
	pin.icon:SetVertexColor(1, 1, 1)
	pin.icon:SetDesaturated(false)
	pin.icon:SetTexCoord(0, 1, 0, 1)
	pin.icon:ClearAllPoints()
	pin.fill:ClearAllPoints()
	pin.edge:Show()
	pin.fill:Show()
	pin.icon:Show()
	local atlas, texture = KindAtlas(point)
	local px = E.pixel or 1
	if shape == "atlas" then
		SetMasked(pin, false)
		pin.edge:Hide()
		pin.fill:Hide()
		pin.icon:SetAllPoints()
		E:SetClientAtlas(pin.icon, atlas, texture)
	elseif shape == "dot" then
		SetMasked(pin, true)
		pin.icon:Hide()
		local dot = size * 0.55
		pin.edge:ClearAllPoints()
		pin.edge:SetPoint("CENTER")
		pin.edge:SetSize(dot + 2, dot + 2)
		pin.edge:SetVertexColor(0, 0, 0, 0.9)
		pin.fill:SetPoint("CENTER")
		pin.fill:SetSize(dot, dot)
		pin.fill:SetVertexColor(color[1], color[2], color[3], 1)
	else
		local ring = shape == "ring"
		SetMasked(pin, ring)
		pin.edge:ClearAllPoints()
		pin.edge:SetAllPoints()
		if ring then
			local r, g, b = 0.85, 0.70, 0.40
			if point.kind == "note" or point.kind == "service" then r, g, b = color[1], color[2], color[3] end
			pin.edge:SetVertexColor(r, g, b, 1)
		else
			pin.edge:SetVertexColor(color[1], color[2], color[3], 1)
		end
		local back = E.media.backdropColor or { 0.06, 0.06, 0.07 }
		pin.fill:SetPoint("TOPLEFT", px, -px)
		pin.fill:SetPoint("BOTTOMRIGHT", -px, px)
		pin.fill:SetVertexColor(back[1], back[2], back[3], 0.92)
		pin.icon:SetPoint("TOPLEFT", 2 * px, -2 * px)
		pin.icon:SetPoint("BOTTOMRIGHT", -2 * px, 2 * px)
		local itemIcon = shape == "item" and point.kind ~= "note" and ItemIcon((M.BestDrop(point)))
		if itemIcon then
			pin.icon:SetTexture(itemIcon)
			E:TrimIcon(pin.icon)
		else
			E:SetClientAtlas(pin.icon, atlas, texture)
		end
	end
	local done = M:IsDone(point)
	pin.tick:SetShown(done)
	if done then
		pin.icon:SetDesaturated(true)
		pin:SetAlpha(M.db.pinAlpha * 0.45)
	end
end

local function PinSize(point, scale)
	local base = point.kind == "rare" and (point.elite and SIZE.elite or SIZE.rare) or SIZE[point.kind] or SIZE.treasure
	return max(8, base * (scale or 1))
end

---------------------------------------------------------------------------
-- Tooltip
---------------------------------------------------------------------------
local STATUS_TEXT = {
	mount = { Key("Mount"), Key("Collected"), Key("Not collected") },
	pet = { Key("Pet"), Key("Collected"), Key("Not collected") },
	toy = { Key("Toy"), Key("Collected"), Key("Not collected") },
	appearance = { Key("Appearance"), Key("Collected"), Key("Not collected") },
}
local MAX_LOOT = 6

function M:PinTooltip(pin)
	local point = pin.point
	if not point then return end
	local tooltip = GameTooltip
	local mapFrame = _G.WorldMapFrame
	local right = mapFrame and pin:GetParent() ~= _G.Minimap and point.x > 0.66
	tooltip:SetOwner(pin, right and "ANCHOR_LEFT" or "ANCHOR_RIGHT")
	local title = point.title
	if point.kind == "note" and not title then title = point.note and point.note:match("^[^\n]+") end
	E.UIKit.TipTitle(tooltip, title or (point.kind == "rare" and L["Rare"]) or L["Map note"])
	local kind
	if point.kind == "rare" then
		local levels = point.level and (point.minLevel and point.minLevel ~= point.level and (point.minLevel .. "-" .. point.level) or point.level)
		if point.worldBoss then
			kind = levels and (L["World boss · Level %s"]):format(levels) or L["World boss"]
		else
			kind = levels and (L["Rare · Level %s"]):format(levels) or L["Rare"]
			if point.elite then kind = kind .. " " .. L["(Elite)"] end
		end
	elseif point.kind == "treasure" then
		kind = L["Treasure"]
	elseif point.kind == "service" then
		kind = point.service or L["City service"]
	else
		kind = L["Your note"]
	end
	E.UIKit.TipText(tooltip, kind)
	if point.note and point.note ~= title then tooltip:AddLine(point.note, E.tokens.text.body[1], E.tokens.text.body[2], E.tokens.text.body[3], true) end
	if self.db.tooltipLoot and point.loot and #point.loot > 0 then
		tooltip:AddLine(" ")
		local shift = IsShiftKeyDown and IsShiftKeyDown()
		local shown = 0
		-- Collectibles first, then by quality.
		local rows = {}
		for _, row in ipairs(point.loot) do rows[#rows + 1] = row end
		table.sort(rows, function(a, b)
			local ka, kb = M.ItemStatus(a.itemID) and 1 or 0, M.ItemStatus(b.itemID) and 1 or 0
			if ka ~= kb then return ka > kb end
			local qa, qb = ItemQuality(a.itemID) or 0, ItemQuality(b.itemID) or 0
			if qa ~= qb then return qa > qb end
			return (tonumber(a.chance) or 0) > (tonumber(b.chance) or 0)
		end)
		for _, row in ipairs(rows) do
			if shown >= MAX_LOOT and not shift then
				E.UIKit.TipText(tooltip, (L["%d more (hold Shift)"]):format(#rows - shown))
				break
			end
			shown = shown + 1
			local name = C_Item and C_Item.GetItemNameByID and Clean(Try(C_Item.GetItemNameByID, row.itemID))
			if not name and C_Item and C_Item.RequestLoadItemDataByID then Try(C_Item.RequestLoadItemDataByID, row.itemID) end
			local icon = ItemIcon(row.itemID)
			local color = QualityColor(ItemQuality(row.itemID))
			local left = (icon and ("|T%s:14:14:0:0:64:64:5:59:5:59|t "):format(icon) or "") .. (name or L["Loading..."])
			local rightText, rr, rg, rb = "", 0.65, 0.65, 0.7
			local kindKey, known = M.ItemStatus(row.itemID)
			if self.db.tooltipKnown and kindKey and STATUS_TEXT[kindKey] then
				local texts = STATUS_TEXT[kindKey]
				rightText = L[texts[1]] .. ": " .. L[known and texts[2] or texts[3]]
				if known then rr, rg, rb = 0.3, 0.85, 0.35 end
			elseif tonumber(row.chance) and row.chance > 0 then
				rightText = ("%s%%"):format(row.chance >= 10 and ("%d"):format(row.chance) or ("%.1f"):format(row.chance))
			end
			tooltip:AddDoubleLine(left, rightText, color[1], color[2], color[3], rr, rg, rb)
		end
	end
	if point.quest and M.QuestDone(point.quest) then tooltip:AddLine(L["Done"], E:TokenColor("good")) end
	if point.met then
		E.UIKit.TipText(tooltip, (L["You met it here on %s."]):format(E:ShortDay(point.met)))
	elseif point.source == "classic" then
		E.UIKit.TipText(tooltip, L["Loot Guide data (Classic values; WoW: Forever may differ)"])
	elseif point.source and point.source ~= "user" and point.source ~= "met" then
		E.UIKit.TipText(tooltip, point.source)
	end
	if IsShiftKeyDown and IsShiftKeyDown() then
		E.UIKit.TipText(tooltip, ("%s %s"):format(M.MapName(point.uiMapID), M.FormatCoords(point.zoneX or point.x, point.zoneY or point.y)))
		if point.quest then E.UIKit.TipText(tooltip, (L["Quest %d"]):format(point.quest)) end
	end
	E:TooltipHint(tooltip, { L["Right-click"], L["options"] })
	tooltip:Show()
end

---------------------------------------------------------------------------
-- Right-click menu
---------------------------------------------------------------------------
local function PointName(point)
	return point.title or (point.kind == "rare" and L["Rare"]) or L["Map note"]
end

local function ZoneXY(point)
	return point.zoneX or point.x, point.zoneY or point.y
end

-- The game's own map pin (and its tracking) on a point.
local function SetGamePin(point)
	local mapPoint = rawget(_G, "UiMapPoint")
	if not (C_Map and C_Map.SetUserWaypoint and mapPoint and mapPoint.CreateFromCoordinates) then return false end
	if C_Map.CanSetUserWaypointOnMap and Try(C_Map.CanSetUserWaypointOnMap, point.uiMapID) == false then return false end
	local x, y = ZoneXY(point)
	local pinPoint = Try(mapPoint.CreateFromCoordinates, point.uiMapID, x, y)
	if not pinPoint then return false end
	Try(C_Map.SetUserWaypoint, pinPoint)
	if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then Try(C_SuperTrack.SetSuperTrackedUserWaypoint, true) end
	return true
end

function M:SetWaypoint(point)
	local x, y = ZoneXY(point)
	local WP = E.Waypoints
	if WP and WP.active then
		WP:Add(point.uiMapID, x, y, { title = PointName(point), source = "MapNotes" })
		return true
	end
	if SetGamePin(point) then
		E:Print((L["Map pin set: %s, %s (%s)."]):format(PointName(point), M.MapName(point.uiMapID), M.FormatCoords(x, y)))
		return true
	end
	E:Print(L["The map there does not take pins."])
	return false
end

-- Puts a map link in the chat box; the player presses Enter to send it.
function M:LinkInChat(point)
	local link
	if SetGamePin(point) and C_Map.GetUserWaypointHyperlink then link = Clean(Try(C_Map.GetUserWaypointHyperlink)) end
	local x, y = ZoneXY(point)
	local text = ("%s (%s %s)"):format(PointName(point), M.MapName(point.uiMapID), M.FormatCoords(x, y))
	if link then text = PointName(point) .. " " .. link end
	local chat = rawget(_G, "ChatFrameUtil")
	if chat and chat.InsertLink and chat.GetActiveWindow and chat.GetActiveWindow() then
		chat.InsertLink(text)
	elseif chat and chat.OpenChat then
		chat.OpenChat(text)
	elseif ChatFrame_OpenChat then
		ChatFrame_OpenChat(text)
	end
end

function M:PinMenu(pin)
	local point = pin.point
	if not point then return end
	E.UIKit.ContextMenu(pin, function(_, root)
		root:CreateTitle(PointName(point))
		root:CreateButton(L["Set a waypoint"], function() M:SetWaypoint(point) end)
		root:CreateButton(L["Link in chat (sets your map pin)"], function() M:LinkInChat(point) end)
		root:CreateButton(L["Hide this point"], function() M:HidePoint(point.key) end)
		if point.metKey then
			root:CreateButton(L["Forget this rare"], function() M:ForgetMet(point.metKey) end)
		end
		if point.kind ~= "note" and point.kind ~= "service" then
			root:CreateCheckbox(L["Hide completed"], function() return M.db.hideDone end, function()
				M.db.hideDone = not M.db.hideDone
				M:Refresh()
			end)
		end
		if point.kind == "note" and point.noteID then
			root:CreateDivider()
			root:CreateButton(L["Edit..."], function() M:OpenEditor(point.uiMapID, nil, nil, point.noteID) end)
			root:CreateButton(L["Delete"], function() M:DeleteNote(point.uiMapID, point.noteID) end)
		end
	end)
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
M.WorldMap = WorldMap

function M:RefreshWorldPins()
	local map = WorldMap()
	for _, pin in ipairs(worldPins) do pin:Hide() pin.point = nil end
	self.worldPinCount = 0
	if not (map and self.active and self.db.worldPins and map.IsShown and map:IsShown()) then return end
	local canvas = map:GetCanvas()
	local shownMap = map.GetMapID and Clean(map:GetMapID())
	if not (canvas and shownMap) then return end
	local width, height = canvas:GetSize()
	if not width or width <= 0 then return end
	local scale = map.GetCanvasScale and Try(map.GetCanvasScale, map) or 1
	local i = 0
	for _, point in ipairs(self:Points(shownMap, "world")) do
		i = i + 1
		local pin = worldPins[i]
		if not pin then
			pin = CreatePin(canvas)
			worldPins[i] = pin
		end
		pin:SetFrameStrata("HIGH")
		pin:SetScale(1 / max(scale or 1, 0.01))
		StylePin(pin, point, PinSize(point, self.db.pinScale))
		pin:ClearAllPoints()
		pin:SetPoint("CENTER", canvas, "TOPLEFT", point.x * width * (scale or 1), -point.y * height * (scale or 1))
		pin:Show()
	end
	self.worldPinCount = i
	if self.UpdateButton then self:UpdateButton() end
end

local function CreateProvider()
	local base = _G.MapCanvasDataProviderMixin
	local p = base and CreateFromMixins and CreateFromMixins(base) or {}
	function p:OnAdded(owningMap) self.owningMap = owningMap end
	function p:OnRemoved() self.owningMap = nil end
	function p:RemoveAllData() for _, pin in ipairs(worldPins) do pin:Hide() end end
	function p:RefreshAllData() M:RefreshWorldPins() end
	function p:OnMapChanged() M:RefreshWorldPins() end
	function p:OnCanvasScaleChanged() M:RefreshWorldPins() end
	function p:OnCanvasSizeChanged() M:RefreshWorldPins() end
	function p:OnShow() M:RefreshWorldPins() end
	function p:OnHide()
		-- Let go of the pins while the map is closed.
		for _, pin in ipairs(worldPins) do pin:Hide() pin.point = nil end
	end
	return p
end

function M:HookWorldMap()
	local map = WorldMap()
	if not map or self.worldHooked then return end
	self.worldHooked = true
	if map.AddDataProvider then
		provider = provider or CreateProvider()
		map:AddDataProvider(provider)
	end
	if self.CreateButton then self:CreateButton(map) end
end

---------------------------------------------------------------------------
-- Minimap
---------------------------------------------------------------------------
local miniPins = {}
local worldCache = setmetatable({}, { __mode = "k" }) -- point -> { continent, north, west }

local function PointWorld(point)
	local cached = worldCache[point]
	if cached then return cached[1], cached[2], cached[3] end
	local WP = E.Waypoints
	local x, y = ZoneXY(point)
	local continent, north, west
	if WP and WP.WorldPos then continent, north, west = WP.WorldPos(point.uiMapID, x, y) end
	worldCache[point] = { continent, north, west }
	return continent, north, west
end

-- Points per zone for the minimap (rebuilt on every refresh, not per tick).
local miniList, miniMap

-- The ticker's view, refilled each tick: while nothing that places a pin
-- changed, the ticker leaves the pins alone.
local tickView = {}

-- fromTick: the shared ticker (the only caller that may skip work).
function M:RefreshMinimapPins(rebuild, fromTick)
	local minimap = _G.Minimap
	local WP = E.Waypoints
	local mapID, _, _, continent, north, west
	if WP and WP.PlayerPos then
		mapID, _, _, continent, north, west = (fromTick and WP.SharedPlayerPos or WP.PlayerPos)()
	end
	local sameMap = miniMap == mapID
	if rebuild or not sameMap then
		miniMap = mapID
		miniList = (mapID and self.active and self.db.minimapPins) and self:Points(mapID, "minimap") or nil
	end
	local hybrid = C_Minimap and C_Minimap.ShouldUseHybridMinimap and Try(C_Minimap.ShouldUseHybridMinimap)
	local i = 0
	local view = self.active and miniList and #miniList > 0 and minimap and continent and not hybrid
		and E:MinimapView(north, west, minimap, tickView)
	if fromTick and sameMap and view and view.same then
		self.minimapSkips = (self.minimapSkips or 0) + 1
		return
	end
	if view then
		local edge = self.db.minimapEdge
		for _, point in ipairs(miniList) do
			local c, n, w = PointWorld(point)
			if c == continent and n then
				local px, py, outside = E:MinimapOffset(view, n, w, true)
				if not outside or edge then
					i = i + 1
					local pin = miniPins[i]
					if not pin then
						pin = CreatePin(minimap)
						-- Under Gathering (+4) and Waypoints (+5) pins.
						pin:SetFrameLevel(minimap:GetFrameLevel() + 3)
						miniPins[i] = pin
					end
					if pin.point ~= point then StylePin(pin, point, PinSize(point, self.db.minimapScale)) end
					if outside then pin:SetAlpha(self.db.pinAlpha * 0.5) elseif not M:IsDone(point) then pin:SetAlpha(self.db.pinAlpha) end
					pin:ClearAllPoints()
					pin:SetPoint("CENTER", minimap, "CENTER", px, py)
					pin:Show()
				end
			end
		end
	end
	for j = i + 1, #miniPins do miniPins[j]:Hide() miniPins[j].point = nil end
	self.miniPinCount = i
end

-- Minimap pins keep their place while you move: every 0.2 s on the shared
-- ticker, and only while the map you are on has notes for the minimap. A
-- change to another map (a sub-zone with its own map, a cave, a city) comes
-- with a zone event, which looks again, and so does stopping to move.
local MINIMAP_TICK = "MapNotes:minimapPins"
local zoneEvents = CreateFrame("Frame")

local function MinimapWanted()
	return M.active and M.db.minimapPins and E:MapPinsShown() and true or false
end

local function MinimapTick()
	M:RefreshMinimapPins(nil, true)
	if not (MinimapWanted() and miniList and #miniList > 0) then E.Ticker:Unsubscribe(MINIMAP_TICK) end
end

function M:WatchMinimapPins()
	local wanted = MinimapWanted()
	if wanted and miniList and #miniList > 0 then
		if not E.Ticker:IsSubscribed(MINIMAP_TICK) then E.Ticker:Subscribe(MINIMAP_TICK, 0.2, MinimapTick, self) end
	else
		E.Ticker:Unsubscribe(MINIMAP_TICK)
	end
	if wanted then
		zoneEvents:RegisterEvent("ZONE_CHANGED")
		zoneEvents:RegisterEvent("ZONE_CHANGED_INDOORS")
		zoneEvents:RegisterEvent("ZONE_CHANGED_NEW_AREA")
		-- A backstop for a map change that comes with no zone event.
		zoneEvents:RegisterEvent("PLAYER_STOPPED_MOVING")
	else
		zoneEvents:UnregisterAllEvents()
	end
end

zoneEvents:SetScript("OnEvent", function()
	if not M.active then return end
	M:RefreshMinimapPins()
	M:WatchMinimapPins()
end)

---------------------------------------------------------------------------
-- Hooks into Core.lua
---------------------------------------------------------------------------
function M:RefreshPins()
	if not self.active then return end
	self:RefreshWorldPins()
	self:RefreshMinimapPins(true)
	self:WatchMinimapPins()
end

function M:StylePins()
	for _, pin in ipairs(miniPins) do pin.point = nil end
end

function M:EnablePins()
	self:HookWorldMap()
	if not self.worldHooked then
		E:OnBlizzardAddOn("Blizzard_WorldMap", function() if M.active then M:HookWorldMap() M:RefreshPins() end end)
	end
	self:RefreshPins()
end

function M:DisablePins()
	E.Ticker:Unsubscribe(MINIMAP_TICK)
	zoneEvents:UnregisterAllEvents()
	for _, pin in ipairs(worldPins) do pin:Hide() pin.point = nil end
	for _, pin in ipairs(miniPins) do pin:Hide() pin.point = nil end
end
