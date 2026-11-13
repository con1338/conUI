-- EldoUI Dungeon Routes: the dungeon view on the world map.
--
-- Inside a dungeon the game's world map has no dungeon map on WoW: Forever.
-- When the map opens there (M, the minimap's map button, any map button),
-- this view lies over the map's canvas instead ("Dungeon map on the world
-- map", on by default):
--
--   +-------------------------------------------------------------------+
--   | The Deadmines  [Floor 1][Floor 2]   [Route v]  [Game map][Window] |
--   |-------------------------------------------------------------------|
--   |   the game's painted map of the floor,         | Bosses           |
--   |   the bosses as skulls where their spots are   | 1 Rhahk'Zor   v  |
--   |   known, and your dot when the game gives a    | 2 Sneed          |
--   |   position                                     | ...              |
--   |-------------------------------------------------------------------|
--   | Floor from the sub-zone name  ·  Bosses ticked: killed this lockout|
--   +-------------------------------------------------------------------+
--
--   * "Packs and route" (off by default) also draws every pack, patrol and
--     the picked route; the Dungeons window always has them for planning.
--     A floor without known edges then falls back to the schematic.
--   * The boss list is always there, also where no boss spot is known: a
--     tick marks a boss the game lists as killed in your lockout or that
--     died in this session.
--   * Floor: the map the game reports for you (C_Map.GetBestMapForUnit),
--     else the sub-zone name, else the floor shown last; the floor buttons
--     switch by hand.
--   * Your dot: only when the game itself returns a map position for you
--     (C_Map.GetPlayerMapPosition, turned into world yards with
--     C_Map.GetWorldPosFromMapPos); secret values and 0,0 count as none.
--     Nothing works a position out. "Your position" turns the dot off.
--   * "Game map" shows Blizzard's map until the map closes; picking another
--     map in Blizzard's own map controls does the same. A small "Dungeon map"
--     button on Blizzard's map brings the view back.
--   * Live shows the game's own minimap large in the view, with your arrow,
--     your group and the rooms as the client draws them; the mouse wheel
--     zooms. On a wide map the painted floor and Live sit side by side.
--     WoW: Forever's own dungeons have no painted map: they open in Live
--     with their boss list from the game's encounter table. The minimap
--     moves only out of combat and goes back to its place when the map
--     closes (Core/MinimapHost.lua).
--   * Outside dungeons Blizzard's map is not touched.
-- The view is EldoUI's own frame, parented to the world map and laid over
-- its canvas. Nothing is added to Blizzard's tables and none of its frames
-- are moved, hidden or changed. Read-only: the editor stays in the Dungeons
-- window.
local _, E = ...
local L = E.L
local M = E.DungeonRoutes
local Kit = E.UIKit
local DM = E.DungeonMaps

local BAR_H = 30
local FOOT_H = 18
local LIST_W = 190
local LIST_ROWS = 16
local DOT_EVERY = 1          -- seconds between two looks at your position
local YOU = "dungeonroutes-you"
local HOST = "dungeonview"
local SPLIT_MIN = 900        -- view width from which Live sits beside the floor
local FOREVER = "forever:"   -- key prefix of WoW: Forever's own dungeons

local view, back
local shown = { key = nil, floor = nil, picked = false, gameMap = false, openMapID = nil, live = false }
M.worldView = shown

local Secret = E.Secret

-- WoW: Forever's own dungeon for a key, from Data/ForeverDungeons.lua.
local function ForeverDungeon(key)
	local id = type(key) == "string" and tonumber(key:match("^" .. FOREVER .. "(%d+)$"))
	return id and E.ForeverDungeons and E.ForeverDungeons[id]
end


local function WorldMap()
	return rawget(_G, "WorldMapFrame")
end

local function Container(map)
	return map and (map.ScrollContainer or (map.GetCanvasContainer and map:GetCanvasContainer()))
end

local function ShownMapID(map)
	local id = map and map.GetMapID and map:GetMapID()
	if Secret(id) then return nil end
	return id
end

---------------------------------------------------------------------------
-- Your position, only as the game gives it
---------------------------------------------------------------------------
-- World yards (x, y) of the player, or nil when the game gives no map
-- position here (inside most instances on Forever).
function M:PlayerWorldPosition()
	if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition and C_Map.GetWorldPosFromMapPos) then return nil end
	local ok, uiMapID = pcall(C_Map.GetBestMapForUnit, "player")
	if not ok or type(uiMapID) ~= "number" or Secret(uiMapID) then return nil end
	local fine, pos = pcall(C_Map.GetPlayerMapPosition, uiMapID, "player")
	if not fine or type(pos) ~= "table" or Secret(pos) then return nil end
	local x, y = pos.x, pos.y
	if pos.GetXY then
		local got, px, py = pcall(pos.GetXY, pos)
		if got then x, y = px, py end
	end
	if Secret(x) or Secret(y) or type(x) ~= "number" or type(y) ~= "number" then return nil end
	if x == 0 and y == 0 then return nil end
	local good, _, world = pcall(C_Map.GetWorldPosFromMapPos, uiMapID, pos)
	if not good or type(world) ~= "table" then return nil end
	local wx, wy = world.x, world.y
	if Secret(wx) or Secret(wy) or type(wx) ~= "number" or type(wy) ~= "number" then return nil end
	return wx, wy
end

local youProvider = { order = 90, group = "dungeonroutes" }
function youProvider.pins(_, ctx)
	local canvas = ctx and ctx.canvas
	if not (M.active and canvas and canvas.routesYou and M.db.worldMapPlayer and ctx.kind == "dungeon" and ctx.bounds) then return nil end
	local x, y = M:PlayerWorldPosition()
	canvas.youSeen = x ~= nil
	if not x then return nil end
	return { { world = { x, y }, id = "ryou", size = 14, pulse = true, tooltip = L["You (the position the game gives for you)"] } }
end
M.youProvider = youProvider

---------------------------------------------------------------------------
-- The view
---------------------------------------------------------------------------
local function Hint()
	local parts = {}
	if ForeverDungeon(shown.key) then
		return L["No painted map for this dungeon: the game's minimap shows it live."]
	end
	if shown.live then parts[#parts + 1] = L["Live: the game's minimap"] end
	local _, source = DM:CurrentFloor(M:MapKey(shown.key))
	if shown.picked then
		parts[#parts + 1] = L["Floor picked by you"]
	elseif source == "map" then
		parts[#parts + 1] = L["Floor from the map the game reports"]
	elseif source == "zone" then
		parts[#parts + 1] = L["Floor from the sub-zone name"]
	else
		parts[#parts + 1] = L["Floor shown last; pick another above"]
	end
	if M.db.worldMapPlayer then
		parts[#parts + 1] = view and view.canvas.youSeen and L["Your dot: the game's position"] or L["The game gives no position here"]
	end
	if M.db.worldMapPacks then
		parts[#parts + 1] = L["Packs from the Classic data"]
	else
		parts[#parts + 1] = L["Bosses checked: killed in your lockout"]
	end
	return table.concat(parts, "  ·  ")
end

function M:WorldHint() return Hint() end

local function UpdateFloors(floors, floor)
	local anchor = view.title
	for index = 1, math.max(#floors, #view.floorButtons) do
		local entry = floors[index]
		local button = view.floorButtons[index]
		if entry and #floors > 1 then
			if not button then
				button = Kit.Button(view.bar, "", 70, 20, function(self) M:ShowWorldFloor(self.floor, true) end,
					L["Floor"], L["Shows this floor of the dungeon."])
				view.floorButtons[index] = button
			end
			button.floor = index
			button:SetText(entry.name or (L["Floor %d"]):format(index))
			Kit.FitButton(button, 60)
			local text = button:GetFontString()
			if text then
				if index == floor then text:SetTextColor(E:TokenColor("accent")) else text:SetTextColor(unpack(Kit.TEXT)) end
			end
			button:ClearAllPoints()
			button:SetPoint("LEFT", anchor, "RIGHT", anchor == view.title and 12 or 4, 0)
			anchor = button
			button:Show()
		elseif button then
			button:Hide()
		end
	end
end

function M:ShowWorldFloor(floor, picked)
	if not (view and shown.key) then return false end
	local mapKey = self:MapKey(shown.key)
	if not mapKey then return false end
	local floors = DM:Floors(mapKey)
	if picked then shown.picked = true end
	floor = floors[floor or 0] and floor or DM:CurrentFloor(mapKey) or 1
	shown.floor = floor
	local entry = floors[floor]
	local packs = self.db.worldMapPacks
	local view3 = "layout"
	-- The game's painted floor whenever the client has one. Packs need the
	-- floor's edges to land on it; without them they use the schematic.
	if self.db.view ~= "layout" and entry and entry.tiles and (not packs or DM:Bounds(mapKey, floor, "art")) then view3 = "art" end
	view.canvas.routesKey = packs and shown.key or nil
	view.canvas.routesBossKey = not packs and shown.key or nil
	view.canvas.routesYou = true
	view.canvas:SetMap(mapKey, floor, view3)
	UpdateFloors(floors, floor)
	local route = self:ActiveRoute(shown.key)
	view.routeButton:SetText(route and route.name or L["No route"])
	Kit.FitButton(view.routeButton, 120)
	view.hint:SetText(Hint())
	self:UpdateBossList()
	return true
end

-- The bosses of the shown dungeon in kill order: { { index, name, killed } }.
function M:WorldBossList(key)
	local list, seen = {}, {}
	local killed = E.Attunements and E.Attunements.KilledNames and E.Attunements:KilledNames() or {}
	local forever = ForeverDungeon(key)
	if forever then
		for index, boss in ipairs(forever.bosses or {}) do
			list[#list + 1] = { index = index, name = boss.name, killed = killed[boss.name] and true or false }
		end
		return list
	end
	for _, pack in ipairs(key and self:Packs(key) or {}) do
		if pack.boss and not seen[pack.boss] then
			seen[pack.boss] = true
			local name = self:BossName(key, pack.boss)
			list[#list + 1] = { index = pack.boss, name = name, killed = killed[name] and true or false }
		end
	end
	table.sort(list, function(a, b) return a.index < b.index end)
	return list
end

function M:UpdateBossList()
	if not (view and view.bossRows) then return end
	local list = self:WorldBossList(shown.key)
	local done = 0
	for index = 1, LIST_ROWS do
		local row, boss = view.bossRows[index], list[index]
		if boss then
			row:SetText(("%d  %s"):format(boss.index, boss.name or "?"))
			if boss.killed then
				done = done + 1
				row:SetTextColor(unpack(Kit.SECONDARY))
				row.tick:Show()
			else
				row:SetTextColor(unpack(Kit.TEXT))
				row.tick:Hide()
			end
			row:Show()
		else
			row:Hide()
			row.tick:Hide()
		end
	end
	if #list == 0 then
		view.bossTitle:SetText(L["Bosses"])
		view.bossEmpty:Show()
	else
		view.bossTitle:SetText(("%s  %d/%d"):format(L["Bosses"], done, #list))
		view.bossEmpty:Hide()
	end
end

---------------------------------------------------------------------------
-- Live: the game's minimap, large
---------------------------------------------------------------------------
local function LiveStore()
	if type(M.db.worldMapLive) ~= "table" then M.db.worldMapLive = {} end
	return M.db.worldMapLive
end

-- Live on or off for this character (a dungeon without a painted map is
-- always Live).
function M:LiveWanted()
	if ForeverDungeon(shown.key) then return true end
	return LiveStore()[E.charKey or "?"] == true
end

local function StopLive()
	if E:MinimapHostOwner() == HOST then E:ReleaseMinimap(HOST) end
	if view and view.live then view.live:Hide() end
end

-- Lays the floor and Live out: side by side on a wide map, else one of
-- them; moves the minimap in (after the fight when in combat).
function M:LayoutLive()
	if not view then return end
	local live, forever = shown.live, ForeverDungeon(shown.key) ~= nil
	local split = live and not forever and (view:GetWidth() or 0) >= SPLIT_MIN
	local canvas, area = view.canvas, view.live
	canvas:ClearAllPoints()
	area:ClearAllPoints()
	if split then
		canvas:SetPoint("TOPLEFT", 6, -(BAR_H + 4))
		canvas:SetPoint("BOTTOMRIGHT", view.middle, "BOTTOMLEFT", -3, 0)
		area:SetPoint("TOPLEFT", view.middle, "TOPRIGHT", 3, 0)
		area:SetPoint("BOTTOMRIGHT", view.bossList, "BOTTOMLEFT", -6, 0)
	else
		canvas:SetPoint("TOPLEFT", 6, -(BAR_H + 4))
		canvas:SetPoint("BOTTOMRIGHT", view.bossList, "BOTTOMLEFT", -6, 0)
		area:SetAllPoints(canvas)
	end
	canvas:SetShown(not live or split)
	view.liveButton:SetShown(not forever)
	local text = view.liveButton:GetFontString()
	if text then
		if live then text:SetTextColor(E:TokenColor("accent")) else text:SetTextColor(unpack(Kit.TEXT)) end
	end
	if not live then
		StopLive()
		return
	end
	area:Show()
	if E:HostMinimap(HOST, area) then
		area.wait:Hide()
	else
		area.wait:SetText(InCombatLockdown() and L["The minimap moves here after the fight."] or L["The minimap is in use elsewhere."])
		area.wait:Show()
		E:RunOutOfCombat(function()
			if view and view:IsShown() and shown.live then M:LayoutLive() end
		end)
	end
end

function M:SetLive(on)
	if ForeverDungeon(shown.key) then on = true end
	LiveStore()[E.charKey or "?"] = on and true or nil
	shown.live = on and true or false
	self:LayoutLive()
	if view and view.hint then view.hint:SetText(self:WorldHint()) end
end

local function RouteMenu(owner)
	if not shown.key then return end
	local key = shown.key
	E.UIKit.ContextMenu(owner, function(_, root)
		root:CreateTitle(L["Routes"])
		local active = M:ActiveRoute(key)
		for _, route in ipairs(M:Routes(key)) do
			local label = route.name or "?"
			if route == active then label = Kit.AccentHex() .. label .. "|r" end
			root:CreateButton(label, function() M:SetActiveRoute(key, route.shipped and "shipped" or route) end)
		end
	end, { at = "owner" })
end

local function Build(map)
	if view then return view end
	local container = Container(map)
	if not container then return nil end
	view = CreateFrame("Frame", "EldoUI_DungeonRoutesWorldView", map)
	view:SetAllPoints(container)
	view:SetFrameLevel((container:GetFrameLevel() or 1) + 40)
	view:EnableMouse(true)
	view:EnableMouseWheel(true)
	view:SetScript("OnMouseWheel", function() end)
	E:SetTemplate(view)
	view:Hide()

	local bar = CreateFrame("Frame", nil, view)
	bar:SetPoint("TOPLEFT", 6, -4)
	bar:SetPoint("TOPRIGHT", -6, -4)
	bar:SetHeight(BAR_H - 6)
	view.bar = bar
	view.title = Kit.Text(bar, 14, "LEFT", "header")
	view.title:SetPoint("LEFT", 2, 0)
	view.floorButtons = {}
	view.window = Kit.Button(bar, L["Dungeons window"], 120, 20, function()
		if InCombatLockdown() then return end
		local key = shown.key
		M:OpenBrowser(key)
	end, L["Dungeons window"], L["Opens the Dungeons window on this dungeon, to pick, edit and share routes. Out of combat."])
	Kit.FitButton(view.window, 110)
	view.window:SetPoint("RIGHT", 0, 0)
	view.gameMap = Kit.Button(bar, L["Game map"], 90, 20, function() M:ShowGameMap() end,
		L["Game map"], L["Shows the game's own map until you close the map. The Dungeon map button on it brings this view back."])
	Kit.FitButton(view.gameMap, 80)
	view.gameMap:SetPoint("RIGHT", view.window, "LEFT", -6, 0)
	view.routeButton = Kit.Button(bar, L["Route"], 140, 20, function(self) RouteMenu(self) end,
		L["Route"], L["Pick the route to show: the suggested one or one of yours."])
	view.routeButton:SetPoint("RIGHT", view.gameMap, "LEFT", -12, 0)
	view.liveButton = Kit.Button(bar, L["Live"], 60, 20, function() M:SetLive(not shown.live) end,
		L["Live"], L["Shows the game's minimap large here, with your arrow and your group as the game draws them. The mouse wheel zooms. Out of combat."])
	Kit.FitButton(view.liveButton, 50)
	view.liveButton:SetPoint("RIGHT", view.routeButton, "LEFT", -6, 0)
	local line = Kit.Divider(view)
	line:SetPoint("TOPLEFT", 1, -BAR_H)
	line:SetPoint("TOPRIGHT", -1, -BAR_H)

	-- The boss list on the right, beside the map.
	local list = CreateFrame("Frame", nil, view)
	list:SetPoint("TOPRIGHT", -6, -(BAR_H + 4))
	list:SetPoint("BOTTOMRIGHT", -6, FOOT_H + 4)
	list:SetWidth(LIST_W)
	view.bossList = list
	view.bossTitle = Kit.Text(list, 13, "LEFT", "header")
	view.bossTitle:SetPoint("TOPLEFT", 8, -6)
	view.bossEmpty = Kit.Text(list, 11, "LEFT", "secondary")
	view.bossEmpty:SetPoint("TOPLEFT", view.bossTitle, "BOTTOMLEFT", 0, -6)
	view.bossEmpty:SetWidth(LIST_W - 16)
	view.bossEmpty:SetText(L["No boss list for this dungeon yet."])
	view.bossRows = {}
	for index = 1, LIST_ROWS do
		local row = Kit.Text(list, 12, "LEFT")
		row:SetPoint("TOPLEFT", view.bossTitle, "BOTTOMLEFT", 0, -6 - (index - 1) * 18)
		row:SetWidth(LIST_W - 34)
		row:SetWordWrap(false)
		row.tick = list:CreateTexture(nil, "OVERLAY")
		row.tick:SetSize(12, 12)
		row.tick:SetPoint("LEFT", row, "RIGHT", 4, 0)
		Kit.SetGlyph(row.tick, "check")
		row.tick:SetVertexColor(E:TokenColor("good"))
		row.tick:Hide()
		view.bossRows[index] = row
	end
	local split = view:CreateTexture(nil, "ARTWORK")
	split:SetColorTexture(unpack(E.tokens.edge.divider))
	split:SetPoint("TOPRIGHT", list, "TOPLEFT", 0, 0)
	split:SetPoint("BOTTOMRIGHT", list, "BOTTOMLEFT", 0, 0)
	split:SetWidth(E.pixel or 1)

	view.canvas = DM:CreateCanvas(view)
	view.canvas:SetPoint("TOPLEFT", 6, -(BAR_H + 4))
	view.canvas:SetPoint("BOTTOMRIGHT", list, "BOTTOMLEFT", -6, 0)
	-- The middle of the map area, for the side by side layout.
	view.middle = CreateFrame("Frame", nil, view)
	view.middle:SetWidth(1)
	local function PlaceMiddle(self)
		local x = math.floor(((self:GetWidth() or 0) - LIST_W - 12) / 2) + 6
		view.middle:ClearAllPoints()
		view.middle:SetPoint("TOPLEFT", self, "TOPLEFT", x, -(BAR_H + 4))
		view.middle:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", x, FOOT_H + 4)
	end
	PlaceMiddle(view)
	view:HookScript("OnSizeChanged", function(self)
		PlaceMiddle(self)
		if self:IsShown() and shown.live then M:LayoutLive() end
	end)
	view.live = CreateFrame("Frame", nil, view)
	view.live:SetAllPoints(view.canvas)
	view.live:Hide()
	view.live.wait = Kit.Text(view.live, 12, "CENTER", "secondary")
	view.live.wait:SetPoint("CENTER")
	view.live.wait:Hide()
	view.live:SetScript("OnSizeChanged", function() E:FitHostedMinimap(HOST) end)
	view.hint = Kit.Text(view, 11, "LEFT", "secondary")
	view.hint:SetPoint("BOTTOMLEFT", 8, 5)
	view.hint:SetPoint("BOTTOMRIGHT", -8, 5)
	view.hint:SetWordWrap(false)

	-- Your dot: a look at the game's position now and then while shown.
	local elapsed = 0
	view:SetScript("OnUpdate", function(_, delta)
		elapsed = elapsed + delta
		if elapsed < DOT_EVERY then return end
		elapsed = 0
		if not (M.db.worldMapPlayer and view.canvas.ctx) then return end
		local x, y = M:PlayerWorldPosition()
		local key = x and ("%d:%d"):format(x, y) or "none"
		if key ~= view.lastDot then
			view.lastDot = key
			view.canvas:RefreshPins()
			view.hint:SetText(Hint())
		end
	end)

	-- On Blizzard's map: the way back to the dungeon view.
	back = Kit.Button(map, L["Dungeon map"], 110, 22, function() M:ShowDungeonView() end,
		L["Dungeon map"], L["Shows EldoUI's map of this dungeon with its packs and your route again."])
	Kit.FitButton(back, 100)
	back:SetFrameLevel((container:GetFrameLevel() or 1) + 45)
	back:SetPoint("TOPLEFT", container, "TOPLEFT", 6, -6)
	back:Hide()
	return view
end

-- The dungeon the view should show now, or nil (then Blizzard's map stays).
function M:WorldViewKey()
	if not (self.active and self.db.worldMap) then return nil end
	local key = self:CurrentDungeon()
	if key and self:MapKey(key) then return key end
	-- WoW: Forever's own dungeons: Live with the boss list.
	if GetInstanceInfo and E.ForeverDungeons then
		local ok, _, kind, _, _, _, _, _, instanceID = pcall(GetInstanceInfo)
		if ok and kind == "party" and not Secret(instanceID) and E.ForeverDungeons[instanceID] then return FOREVER .. instanceID end
	end
	return nil
end

function M:UpdateWorldView()
	local map = WorldMap()
	if not (map and map:IsShown()) then
		if view then view:Hide() end
		if back then back:Hide() end
		return false
	end
	local key = self:WorldViewKey()
	local forever = ForeverDungeon(key)
	if key and not forever and not self:Data() then key = nil end
	if not key then
		StopLive()
		if view then view:Hide() end
		if back then back:Hide() end
		return false
	end
	if not Build(map) then return false end
	if shown.gameMap then
		StopLive()
		view:Hide()
		back:Show()
		return false
	end
	back:Hide()
	if key ~= shown.key then
		shown.key, shown.floor, shown.picked = key, nil, false
	end
	shown.live = self:LiveWanted()
	view.title:SetText(forever and forever.name or self:DungeonName(key))
	view:Show()
	if forever then
		UpdateFloors({}, 1)
		view.routeButton:Hide()
		view.hint:SetText(Hint())
		self:UpdateBossList()
	else
		view.routeButton:Show()
		local mapKey = self:MapKey(key)
		if mapKey then DM:LearnFloorMap(mapKey) end
		self:ShowWorldFloor(shown.picked and shown.floor or nil)
	end
	self:LayoutLive()
	return true
end

function M:ShowGameMap()
	shown.gameMap = true
	return self:UpdateWorldView()
end

function M:ShowDungeonView()
	shown.gameMap = false
	local map = WorldMap()
	shown.openMapID = ShownMapID(map)
	return self:UpdateWorldView()
end

function M:WorldView()
	return view, back
end

local hooked
local function OnMapShow()
	shown.gameMap, shown.picked = false, false
	shown.openMapID = ShownMapID(WorldMap())
	M:UpdateWorldView()
end

local function OnMapHide()
	shown.gameMap, shown.picked = false, false
	StopLive()
	if view then view:Hide() end
	if back then back:Hide() end
end

-- Another map picked in Blizzard's own map controls: show that map.
local function OnMapChanged()
	if not (view and view:IsShown()) then return end
	local id = ShownMapID(WorldMap())
	if shown.openMapID and id and id ~= shown.openMapID then
		M:ShowGameMap()
	end
end

function M:HookWorldMap()
	local map = WorldMap()
	if hooked or not map then return end
	hooked = true
	map:HookScript("OnShow", OnMapShow)
	map:HookScript("OnHide", OnMapHide)
	if type(map.OnMapChanged) == "function" then hooksecurefunc(map, "OnMapChanged", OnMapChanged) end
	if map:IsShown() then OnMapShow() end
end

M:Hook("enable", function()
	if E.AddMapPinProvider then E:AddMapPinProvider(YOU, youProvider) end
	if WorldMap() then
		M:HookWorldMap()
	elseif E.OnBlizzardAddOn then
		E:OnBlizzardAddOn("Blizzard_WorldMap", function() if M.active then M:HookWorldMap() end end)
	end
end)
M:Hook("disable", function()
	if E.RemoveMapPinProvider then E:RemoveMapPinProvider(YOU) end
	StopLive()
	if view then view:Hide() end
	if back then back:Hide() end
end)
M:Hook("profile", function() M:UpdateWorldView() end)
-- Zoning while the map is open, or a new floor: follow.
M:Hook("zone", function()
	if not (view and view:IsShown()) then
		M:UpdateWorldView()
		return
	end
	if not shown.picked then M:UpdateWorldView() end
end)
M:Hook("changed", function(what)
	if view and view:IsShown() and (what == "route" or what == "routes" or what == "data") then M:ShowWorldFloor(shown.floor) end
end)
