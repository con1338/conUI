-- EldoUI Loot Guide: the dungeon map window.
--
--   +--------------------------------------------------------+
--   | Scholomance   [Floor 1] [Floor 2]   [Schematic]      x |
--   |--------------------------------------------------------|
--   |                                                        |   +-----------+
--   |        the client's dungeon map art, numbered          |   | boss loot |
--   |        boss markers (or a designed list when the       |   | (the side |
--   |        client has no art)                              |   |  with     |
--   |                                                        |   |  room)    |
--   |--------------------------------------------------------|   +-----------+
--   | Click a boss for its loot · positions are Classic data |
--   +--------------------------------------------------------+
--
-- Drawn through E.DungeonMaps (Core/DungeonMaps.lua): the art is the
-- client's own (Interface\WorldMap\<dungeon>\...), never fan-made maps or
-- another addon's data. Boss markers come from EldoUI_LootData spawn
-- positions; there is no player position inside instances on WoW: Forever
-- and nothing here tries to find one. Markers on the art need the floor's
-- edges (from the client's map API, learned when you pick the floor while
-- inside). Without them the "Schematic" view places the markers by where the
-- creatures stand (approximate, said so).
--
-- Movable and resizable; size and place in the cache, the last floor per
-- dungeon in E.DungeonMaps. Settings: "Boss markers on dungeon maps"
-- (mapBosses). Presentation only.
local _, E = ...
local LG = E.LootGuide
local Kit = LG.Kit
local P = LG.PageKit
local L = E.L

local WIDTH, HEIGHT = 760, 540
local MIN_W, MIN_H = 520, 380
local MAX_W, MAX_H = 1500, 1100
local TOPBAR = E.UIKit.TOOL_HEADER
local FOOTER = 26
local SIDE = 270

local DM = E.DungeonMaps
local window

local Secret = E.Secret

---------------------------------------------------------------------------
-- Layout source: where the creatures of an instance stand (LootData spawns)
---------------------------------------------------------------------------
local spawnIndex  -- instance map -> { { x, y }, ... }

LG:On("dungeonmap-data", function(changed)
	if changed.data then
		spawnIndex = nil
		if DM then DM:Reset() end
	end
end)

local function SpawnIndex()
	if spawnIndex then return spawnIndex end
	spawnIndex = {}
	local data = select(3, LG:DataStatus())
	if not (data and type(data.spawns) == "table" and DM) then return spawnIndex end
	local wanted = {}
	for _, key in ipairs(DM:List()) do
		local def = DM:Get(key)
		if def and def.map then wanted[def.map] = true end
	end
	for _, packed in pairs(data.spawns) do
		local map, rest = tostring(packed):match("^(%d+)|(.*)$")
		map = tonumber(map)
		if map and wanted[map] then
			local list = spawnIndex[map] or {}
			spawnIndex[map] = list
			for x, y in rest:gmatch("(%-?[%d%.]+),(%-?[%d%.]+),") do
				if #list < 600 then list[#list + 1] = { x = tonumber(x), y = tonumber(y) } end
			end
		end
	end
	return spawnIndex
end

if DM then
	DM:RegisterLayoutSource("lootguide", function(_, instanceMap)
		if not LG:HasData() then return end
		return SpawnIndex()[instanceMap]
	end)
end

---------------------------------------------------------------------------
-- Bosses of the shown instance and their places
---------------------------------------------------------------------------
-- { { index, npc, name, level, loot, world = { x, y } or nil } }
local function Bosses(key)
	local list = {}
	local info = LG:InstanceInfo(key)
	if not info then return list end
	for index, boss in ipairs(LG:InstanceLoot(key).bosses) do
		local entry = { index = index, npc = boss.npc, name = boss.name, level = boss.level, loot = boss.loot, rare = boss.rare }
		local kind, id = boss.npc and "npc" or "object", boss.npc or boss.object
		for _, point in ipairs(id and LG:SpawnPoints(kind, id) or {}) do
			if point.map == info.map then
				entry.world = { x = point.x, y = point.y }
				break
			end
		end
		list[#list + 1] = entry
	end
	return list
end

local bossProvider = {
	order = 50,
	pins = function(_, ctx)
		if ctx.kind ~= "dungeon" or not (LG.active and LG.db.mapBosses) then return end
		local canvas = ctx.canvas
		local key = canvas and canvas.lgKey
		if not key or not ctx.bounds then return end
		local pins = {}
		for _, boss in ipairs(Bosses(key)) do
			if boss.world then
				pins[#pins + 1] = { world = boss.world, id = "boss:" .. boss.index, label = boss.index, size = 22,
					highlight = canvas.selected == boss.index, boss = boss,
					tooltip = function(tooltip)
						E.UIKit.TipTitle(tooltip, ("%d. %s"):format(boss.index, boss.name or "?"))
						if boss.level then E.UIKit.TipText(tooltip, (L["Level %d"]):format(boss.level)) end
						E.UIKit.TipText(tooltip, E:Plural(#(boss.loot or {}), "%d known drop", "%d known drops"):format(#(boss.loot or {})))
						E:TooltipHint(tooltip, { L["Click"], L["its loot; click again to close it"] })
					end }
			end
		end
		return pins
	end,
}
if E.AddMapPinProvider then E:AddMapPinProvider("lootguide-bosses", bossProvider) end

---------------------------------------------------------------------------
-- Geometry
---------------------------------------------------------------------------
-- Place and size in the cache as x, y, w, h: the window shell keeps the
-- place there, its grip the size.
local function Geometry()
	local cache = LG:Cache()
	if type(cache.dungeonMap) ~= "table" then cache.dungeonMap = {} end
	return cache.dungeonMap
end

function LG:ResetDungeonMap()
	self:Cache().dungeonMap = nil
	if window then window:ResetPosition() end
end

---------------------------------------------------------------------------
-- Side loot panel (on the side of the window with more room)
---------------------------------------------------------------------------
local function PlaceSide()
	local side = window.side
	side:ClearAllPoints()
	local left = window:GetLeft() or 0
	local right = UIParent:GetWidth() - (window:GetRight() or 0)
	if right >= left then
		side:SetPoint("TOPLEFT", window, "TOPRIGHT", 4, 0)
		side:SetPoint("BOTTOMLEFT", window, "BOTTOMRIGHT", 4, 0)
	else
		side:SetPoint("TOPRIGHT", window, "TOPLEFT", -4, 0)
		side:SetPoint("BOTTOMRIGHT", window, "BOTTOMLEFT", -4, 0)
	end
end

local function DrawSide(boss)
	local side = window.side
	local flow = side.flow
	flow:Begin()
	P.FlowCaption(flow, ("%d. %s"):format(boss.index, boss.name or "?"), boss.level and ((L["Level %d"]):format(boss.level)) or nil)
	local minQuality = tonumber(LG.db.minQuality) or 0
	local shown = 0
	local rows = {}
	for _, drop in ipairs(boss.loot or {}) do
		local record = LG:ItemRecord(drop.itemID)
		if not record or (record.quality or 0) >= minQuality then rows[#rows + 1] = drop end
	end
	table.sort(rows, function(a, b)
		local ua, ub = P.IsUpgrade(a.itemID), P.IsUpgrade(b.itemID)
		if ua ~= ub then return ua end
		return (a.chance or 0) > (b.chance or 0)
	end)
	for _, drop in ipairs(rows) do
		local data = P.ChanceData(drop.chance, boss.npc, drop.itemID)
		P.FlowItem(flow, { itemID = drop.itemID, chance = data.chance, seen = data.seen, badge = LG:PhaseBadge(drop.itemID),
			onClick = function() P.OpenItem(drop.itemID) end })
		shown = shown + 1
	end
	if shown == 0 then P.FlowText(flow, L["No known drops at your quality setting."], 11, "secondary") end
	flow:Space(6)
	P.FlowLine(flow, L["Open in the Journal"], function() LG:Open("journal", window.key) end, nil,
		L["Open in the Journal"], L["The instance page with every boss, its quests and its trash loot."])
	flow:Finish()
	PlaceSide()
	side:Show()
end

local function Select(index)
	local canvas = window.canvas
	if canvas.selected == index then index = nil end
	canvas.selected = index
	canvas:SetHighlight(index and ("boss:" .. index) or nil)
	if index then
		for _, boss in ipairs(Bosses(window.key)) do
			if boss.index == index then DrawSide(boss) end
		end
	else
		window.side:Hide()
	end
	if window.noMap:IsShown() then window.noMap.draw() end
end

---------------------------------------------------------------------------
-- The designed "no map" view: bosses in order and the entrance
---------------------------------------------------------------------------
local function DrawNoMap()
	local flow = window.noMap.flow
	local key = window.key
	local info = LG:InstanceInfo(key)
	flow:Begin()
	P.FlowCaption(flow, L["No map art for this instance"])
	P.FlowText(flow, L["The game has no map picture for this place. Here are its bosses in order; click one for its loot."], 11, "secondary")
	flow:Space(4)
	P.FlowCaption(flow, L["Bosses"])
	local bosses = Bosses(key)
	for _, boss in ipairs(bosses) do
		local text = ("%d.  %s%s"):format(boss.index, boss.name or "?", boss.level and ("  " .. E:TextHex("secondary") .. boss.level .. "|r") or "")
		if window.canvas.selected == boss.index then text = E:TextHex("accent") .. ("%d.  %s"):format(boss.index, boss.name or "?") .. "|r" end
		P.FlowLine(flow, text, function() Select(boss.index) end, nil, boss.name, function(tip) Kit.TooltipHint(tip, { L["Click"], L["its loot; click again to close it"] }) end)
	end
	if #bosses == 0 then P.FlowText(flow, L["The loot data lists no bosses here."], 11, "secondary") end
	P.FlowCaption(flow, L["Entrance"])
	local point = info and LG:EntrancePoint(key)
	if point then
		P.FlowLine(flow, (point.zone or LG:MapName(point.uiMapID) or "?") .. ("  " .. E:TextHex("secondary") .. "%.1f, %.1f|r"):format(point.x * 100, point.y * 100), nil,
			{ L["Map"], function() LG:ShowEntrance(key) end, L["Map"], L["Pins the entrance on your map and opens the map there (out of combat)."] })
	else
		P.FlowText(flow, L["The client does not know where this entrance is."], 11, "secondary")
	end
	flow:Finish(true)
end

---------------------------------------------------------------------------
-- Floors and views
---------------------------------------------------------------------------
local function HintText(ctx, hasArt)
	local parts = {}
	if window.noMap:IsShown() then
		parts[#parts + 1] = L["Click a boss for its loot."]
	elseif ctx and ctx.view == "layout" then
		parts[#parts + 1] = L["Schematic: markers placed by where the creatures stand (Classic data, approximate)."]
	elseif ctx and not ctx.bounds then
		parts[#parts + 1] = L["Boss markers show once this floor's edges are known: pick the floor while you are inside, or use Schematic."]
	else
		parts[#parts + 1] = L["Click a numbered marker for the boss's loot."]
	end
	if not LG.db.mapBosses and not window.noMap:IsShown() then parts[#parts + 1] = L["Boss markers are off in the settings."] end
	if hasArt == false and not window.noMap:IsShown() then parts[#parts + 1] = L["No map art here."] end
	parts[#parts + 1] = L["There is no live position inside dungeons."]
	return table.concat(parts, "  ·  ")
end

local function UpdateFloorButtons(floors, floor)
	local buttons = window.floorButtons
	local anchor
	for index = 1, math.max(#floors, #buttons) do
		local entry = floors[index]
		local button = buttons[index]
		if entry and #floors > 1 and window.view ~= "nomap" then
			if not button then
				button = P.Toggle(window.topBar, "", function(self)
					DM:SetLastFloor(window.mapKey, self.floor)
					DM:LearnFloorMap(window.mapKey, self.floor)
					LG:ShowDungeonMapFloor(self.floor)
				end, L["Floor"], L["Shows this floor. Your pick is remembered for this dungeon."])
				buttons[index] = button
			end
			button.floor = index
			button:SetLabel(entry.name or ((L["Floor %d"]):format(index)))
			button:SetOn(index == floor)
			button:ClearAllPoints()
			if anchor then button:SetPoint("LEFT", anchor, "RIGHT", 4, 0) else button:SetPoint("LEFT", window.title, "RIGHT", 14, 0) end
			anchor = button
			button:Show()
		elseif button then
			button:Hide()
		end
	end
end

function LG:ShowDungeonMapFloor(floor)
	if not window or not window.key then return end
	local mapKey = window.mapKey
	local floors = mapKey and DM:Floors(mapKey) or {}
	local hasArt = mapKey and DM:HasArt(mapKey) or false
	floor = floors[floor or 0] and floor or (mapKey and DM:CurrentFloor(mapKey)) or 1
	window.floor = floor
	local view = window.view
	if view ~= "layout" then view = hasArt and "art" or "nomap" end
	window.view = view
	local noMap = view == "nomap"
	window.noMap:SetShown(noMap)
	window.canvas:SetShown(not noMap)
	local ctx
	if not noMap then
		window.canvas.lgKey = window.key
		ctx = window.canvas:SetMap(mapKey, floor, view)
	else
		DrawNoMap()
	end
	UpdateFloorButtons(floors, floor)
	-- Schematic toggle: there when creature positions give a box.
	local layout = mapKey and DM:Bounds(mapKey, floor, "layout")
	window.schematic:SetShown(layout ~= nil)
	window.schematic:SetOn(view == "layout")
	window.hint:SetText(HintText(ctx, hasArt))
end

function LG:DungeonMapWindow()
	return window
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------
local function Build()
	if window then return window end
	-- The tool window shell: header with title and close X, accent line,
	-- Escape, the kit's grip, and its place and size kept in the cache.
	local frame = E.UIKit.CreateToolWindow("EldoUILootGuideMap", { width = WIDTH, height = HEIGHT, strata = "HIGH",
		resizable = { minWidth = MIN_W, minHeight = MIN_H, maxWidth = MAX_W, maxHeight = MAX_H,
			tipTitle = L["Size"], tip = L["Drag to make the map bigger or smaller."] },
		store = Geometry, point = { "CENTER", UIParent, "CENTER", 0, 40 } })
	window = frame
	local bar = frame.header
	bar:HookScript("OnDragStop", function()
		if frame.side:IsShown() then PlaceSide() end
	end)
	frame.topBar = bar
	-- The title takes the width of its text; the floor buttons follow it.
	frame.title:ClearAllPoints()
	frame.title:SetPoint("LEFT", 12, 0)
	frame.title:SetWordWrap(false)
	frame.schematic = P.Toggle(bar, L["Schematic"], function()
		frame.view = frame.view == "layout" and nil or "layout"
		LG:ShowDungeonMapFloor(frame.floor)
	end, L["Schematic"], L["Places the boss markers by where the creatures stand in the Classic data, on a plain grid. Approximate: walls and floors are not drawn."])
	frame.schematic:SetPoint("RIGHT", frame.close, "LEFT", -8, 0)
	frame.floorButtons = {}

	frame.canvas = DM:CreateCanvas(frame)
	frame.canvas:SetPoint("TOPLEFT", 8, -(TOPBAR + 6))
	frame.canvas:SetPoint("BOTTOMRIGHT", -8, FOOTER + 4)
	frame.canvas.onPinClick = function(pin, button)
		if button == "LeftButton" and pin.boss then Select(pin.boss.index) end
	end

	frame.noMap = CreateFrame("Frame", nil, frame)
	frame.noMap:SetPoint("TOPLEFT", 16, -(TOPBAR + 10))
	frame.noMap:SetPoint("BOTTOMRIGHT", -16, FOOTER + 6)
	frame.noMap.flow = P.Flow(frame.noMap)
	frame.noMap.flow:SetAllPoints()
	frame.noMap.draw = DrawNoMap
	frame.noMap:Hide()

	frame.hint = Kit.Text(frame, 11, "LEFT", "secondary")
	frame.hint:SetPoint("BOTTOMLEFT", 12, 8)
	frame.hint:SetPoint("BOTTOMRIGHT", -28, 8)
	frame.hint:SetWordWrap(false)

	-- Side loot panel.
	local side = CreateFrame("Frame", nil, frame)
	side:SetWidth(SIDE)
	E:SetTemplate(side)
	side:Hide()
	side.flow = P.Flow(side)
	side.flow:SetPoint("TOPLEFT", 8, -6)
	side.flow:SetPoint("BOTTOMRIGHT", -4, 6)
	frame.side = side

	frame:HookScript("OnHide", function()
		frame.side:Hide()
		frame.canvas.selected = nil
	end)
	return frame
end

-- Opens the map of an instance (an EldoUI_LootData key; wings share the
-- map of their dungeon). boss: a boss index to open with its loot.
function LG:OpenDungeonMap(key, boss)
	if not self.active then return end
	local info = key and self:InstanceInfo(key)
	if not info or info.world then
		E:Print(L["This place has no dungeon map."])
		return
	end
	if self.LoadData then self:LoadData() end
	Build()
	window.key = key
	window.mapKey = DM:KeyFor(key) or DM:KeyForMap(info.map)
	if window.mapKey and not DM:Get(window.mapKey) then window.mapKey = nil end
	window.view = nil
	window.canvas.selected = nil
	window.side:Hide()
	window.title:SetText(info.name)
	if window.mapKey then DM:LearnFloorMap(window.mapKey) end
	window:Show()
	self:ShowDungeonMapFloor(window.mapKey and DM:CurrentFloor(window.mapKey) or 1)
	if boss then Select(boss) end
	Kit.Tour("dungeonmap", {
		{ target = window.floorButtons[1] and window.floorButtons[1]:IsShown() and window.floorButtons[1] or window.title,
			text = L["Floors: each button shows one floor. The map remembers the one you picked last."] },
		{ target = window.canvas:IsShown() and window.canvas or window.noMap,
			text = L["Numbered markers are the bosses, from the Classic data. Click one for its loot; click it again to close the list."] },
		{ target = window.hint, text = L["Hints show here: where the markers come from and what the map can't know (there is no live position inside dungeons)."] },
	})
end

LG:On("dungeonmap", function(changed)
	if not (window and window:IsShown()) then return end
	if changed.settings or changed.data or changed.gear then LG:ShowDungeonMapFloor(window.floor) end
	if window.side:IsShown() and window.canvas.selected and (changed.wishlist or changed.gear or changed.items) then
		for _, boss in ipairs(Bosses(window.key)) do
			if boss.index == window.canvas.selected then DrawSide(boss) end
		end
	end
end)

-- Entering a dungeon: the floor the client reports may give that floor
-- real edges (no position is read).
LG:Listen("ZONE_CHANGED_NEW_AREA", "dungeonmap", function()
	if window and window:IsShown() and window.mapKey and DM:LearnFloorMap(window.mapKey, window.floor) then
		LG:ShowDungeonMapFloor(window.floor)
	end
end)
