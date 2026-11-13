-- EldoUI Flight Games: Where Is It? The map of a continent and the name
-- of a zone or a city: click where it lies. A click inside it scores 100,
-- a near miss less, the further off the fewer. Ten places a round, one
-- continent or both.
-- The maps, places and names come from the game's own world map.
-- Written from scratch for EldoUI.
local _, E = ...
local M = E.FlightGames
local Key = E.Key
local L = E.L
local B = M.Board

local MAP_W, MAP_H = 560, 374
local TOP = 30
local WIDTH, HEIGHT = MAP_W, TOP + MAP_H
local ROUNDS = 10
local WAIT = 2.2
local REACH = 0.22             -- this far off (a share of the map width) scores nothing
local KALIMDOR, EASTERN = 1414, 1415
local MODES = {
	{ key = "both", title = "Both continents" },
	{ key = "east", title = "Eastern Kingdoms", only = EASTERN },
	{ key = "kalimdor", title = "Kalimdor", only = KALIMDOR },
}
-- The zones and cities of the original world, by map id, with the English
-- name for a client that gives none.
local PLACES = {
	[EASTERN] = {
		1429, "Elwynn Forest", 1426, "Dun Morogh", 1420, "Tirisfal Glades", 1436, "Westfall",
		1432, "Loch Modan", 1421, "Silverpine Forest", 1433, "Redridge Mountains", 1431, "Duskwood",
		1437, "Wetlands", 1424, "Hillsbrad Foothills", 1416, "Alterac Mountains", 1417, "Arathi Highlands",
		1434, "Stranglethorn Vale", 1418, "Badlands", 1435, "Swamp of Sorrows", 1425, "The Hinterlands",
		1427, "Searing Gorge", 1419, "Blasted Lands", 1428, "Burning Steppes", 1422, "Western Plaguelands",
		1423, "Eastern Plaguelands", 1430, "Deadwind Pass", 1453, "Stormwind City", 1455, "Ironforge",
		1458, "Undercity",
	},
	[KALIMDOR] = {
		1411, "Durotar", 1412, "Mulgore", 1438, "Teldrassil", 1439, "Darkshore", 1413, "The Barrens",
		1442, "Stonetalon Mountains", 1440, "Ashenvale", 1441, "Thousand Needles", 1443, "Desolace",
		1445, "Dustwallow Marsh", 1444, "Feralas", 1446, "Tanaris", 1447, "Azshara", 1448, "Felwood",
		1449, "Un'Goro Crater", 1452, "Winterspring", 1451, "Silithus", 1450, "Moonglade",
		1454, "Orgrimmar", 1456, "Thunder Bluff", 1457, "Darnassus",
	},
}

local Where = {}
Where.__index = Where
-- What a saved game keeps (the board, the score and the timers).
Where.saveKeys = { "round", "score", "place", "guess", "gain", "phase", "used", "wait" }

local function ModeOf(mode)
	return mode and mode.key and mode or MODES[1]
end

-- Where a place lies on its continent's map: { left, right, top, bottom }
-- as shares of the map, or nil.
local function Rect(id, continent)
	local map = C_Map
	if not (map and map.GetMapRectOnMap) then return nil end
	local ok, minX, maxX, minY, maxY = pcall(map.GetMapRectOnMap, id, continent)
	if not (ok and tonumber(minX) and tonumber(maxX) and tonumber(minY) and tonumber(maxY)) then return nil end
	if maxX <= minX or maxY <= minY or minX < -0.1 or maxX > 1.1 or minY < -0.1 or maxY > 1.1 then return nil end
	return { minX, maxX, minY, maxY }
end

local function PlaceName(id, english)
	local map = C_Map
	if map and map.GetMapInfo then
		local ok, info = pcall(map.GetMapInfo, id)
		if ok and type(info) == "table" and type(info.name) == "string" and info.name ~= "" then return info.name end
	end
	return english
end

-- Every place the client can show: { id, name, continent, rect }.
local places
local function Places()
	if places then return places end
	places = {}
	for _, continent in ipairs({ EASTERN, KALIMDOR }) do
		local list = PLACES[continent]
		for k = 1, #list, 2 do
			local rect = Rect(list[k], continent)
			if rect then
				places[#places + 1] = { id = list[k], name = PlaceName(list[k], list[k + 1]), continent = continent, rect = rect }
			end
		end
	end
	return places
end
Where.Places = function() places = nil return Places() end

local function Find(id)
	for _, place in ipairs(Places()) do
		if place.id == id then return place end
	end
end

-- The place the client draws at (x, y) on a continent: its map id, or nil.
local function MapAt(continent, x, y)
	local map = C_Map
	if not (map and map.GetMapInfoAtPosition and continent) then return nil end
	local ok, info = pcall(map.GetMapInfoAtPosition, continent, x, y)
	if not (ok and type(info) == "table" and tonumber(info.mapID)) then return nil end
	if info.mapID == continent then return nil end
	return info.mapID, tonumber(info.parentMapID)
end

-- Points for a guess at (x, y), shares of the map: 100 inside the place,
-- then fewer the further from its edge. A zone's map box overlaps its
-- neighbors, so inside the box the client says which zone was hit; a
-- neighbor's land counts as just next to it.
local NEIGHBOR = 80
local function Points(place, x, y)
	local r = place.rect
	local dx = x < r[1] and r[1] - x or x > r[2] and x - r[2] or 0
	local dy = y < r[3] and r[3] - y or y > r[4] and y - r[4] or 0
	if dx == 0 and dy == 0 then
		local hit, parent = MapAt(place.continent, x, y)
		if hit and hit ~= place.id and parent ~= place.id then return NEIGHBOR end
		return 100
	end
	local off = math.sqrt(dx * dx + (dy * MAP_H / MAP_W) ^ 2)
	return math.max(0, math.floor(90 * (1 - off / REACH) + 0.5))
end
Where.Points = Points

local function New(host, mode)
	local game = setmetatable({ host = host, mode = ModeOf(mode), maps = {} }, Where)
	local area = host.area
	game.paper = B.Sprite(area, MAP_W, MAP_H, "BACKGROUND")
	B.Place(game.paper, 0, TOP, area)
	game.zones = {}
	-- Marks and effects sit on a layer above the map art.
	local top = CreateFrame("Frame", nil, area)
	top:SetAllPoints(area)
	top:SetFrameLevel(area:GetFrameLevel() + 10)
	game.top = top
	game.spot = B.Sprite(top, 10, 10, "OVERLAY")
	game.zone = B.Sprite(top, 10, 10, "ARTWORK")
	game.pin = B.Sprite(top, 22, 22, "OVERLAY")
	game.trail = {}
	for i = 1, 9 do game.trail[i] = B.Dot(top, 5, nil, "OVERLAY") end
	game.progress = B.Label(area, E.tokens.size.small, "secondary", "LEFT")
	game.progress:SetPoint("TOPLEFT", area, "TOPLEFT", 4, -8)
	game.ask = B.Label(area, E.tokens.size.cardTitle, "body")
	game.ask:SetPoint("TOP", area, "TOPLEFT", WIDTH / 2, -5)
	game.note = B.Label(area, E.tokens.size.small, "body", "RIGHT")
	game.note:SetPoint("TOPRIGHT", area, "TOPLEFT", WIDTH - 4, -8)
	game.empty = B.Label(area, E.tokens.size.body, "secondary")
	game.empty:SetWidth(MAP_W - 60)
	game.empty:SetPoint("CENTER", area, "TOPLEFT", WIDTH / 2, -(TOP + MAP_H / 2))
	game.fx = B.Effects(top)
	return game
end

-- The map of a continent: the game's own art, or (without it) every place
-- drawn as a soft tile so the land still takes shape.
function Where:Map(continent)
	local map = self.maps[continent]
	if map == nil then
		map = B.MapArt(self.host.area, continent, MAP_W, MAP_H, "BORDER")
		if map then
			map:SetPoint("TOPLEFT", self.host.area, "TOPLEFT", 0, -TOP)
		else
			map = false
		end
		self.maps[continent] = map
	end
	return map
end

function Where:Start()
	self.round, self.score, self.used = 0, 0, {}
	self.place, self.guess, self.gain = nil, nil, nil
	self.host.Score(0)
	self.fx:Clear()
	local count = 0
	for _, place in ipairs(Places()) do
		if not self.mode.only or place.continent == self.mode.only then count = count + 1 end
	end
	if count < ROUNDS then
		self.phase = "none"
		self:Draw()
		return
	end
	self:Next()
end

function Where:Next()
	local open = {}
	for _, place in ipairs(Places()) do
		if (not self.mode.only or place.continent == self.mode.only) and not self.used[place.id] then open[#open + 1] = place end
	end
	if #open == 0 then return end
	local place = open[self.host.Random(#open)]
	self.used[place.id] = true
	self.round = self.round + 1
	self.place, self.guess, self.gain, self.phase = place.id, nil, nil, "ask"
	self:Draw()
end

function Where:Guess(x, y)
	if self.phase ~= "ask" then return end
	local place = Find(self.place)
	if not place then return end
	self.guess = { x, y }
	self.gain = Points(place, x, y)
	self.score = self.score + self.gain
	self.host.Score(self.score)
	self.phase, self.wait = "show", WAIT
	local r = place.rect
	local cx, cy = (r[1] + r[2]) / 2 * MAP_W, TOP + (r[3] + r[4]) / 2 * MAP_H
	local color = self.host.Color
	if self.gain >= 100 then
		self.host.Sound("point")
		self.fx:Burst(cx, cy, color("good"), 70, 0.5)
		self.fx:Sparks(cx, cy, color("gold"), 16, 160)
	elseif self.gain > 0 then
		self.host.Sound("point")
		self.fx:Burst(cx, cy, color("warn"), 50, 0.4)
	else
		self.host.Sound("turn")
		self.fx:Burst(x * MAP_W, TOP + y * MAP_H, color("bad"), 40, 0.4)
	end
	self.fx:Float(cx, cy - 16, "+" .. self.gain, self.gain > 0 and color("gold") or color("dim"), E.tokens.size.cardTitle)
	self:Draw()
end

function Where:Advance()
	if self.phase ~= "show" then return end
	if self.round >= ROUNDS then
		self.phase = "done"
		self:Draw()
		self.host.Over(true)
		return
	end
	self:Next()
end

function Where:Loaded()
	self.used = type(self.used) == "table" and self.used or {}
	if self.phase ~= "none" and not Find(self.place) then
		self.round = math.max(0, (tonumber(self.round) or 1) - 1)
		self:Next()
	end
end

function Where:Update(dt)
	self.fx:Update(dt)
	if self.phase == "show" then
		self.wait = (self.wait or 0) - dt
		if self.wait <= 0 then self:Advance() end
	end
end

function Where:Key(key)
	if (key == "SPACE" or key == "ENTER") and self.phase == "show" then
		self:Advance()
		return true
	end
	return false
end

function Where:Press(button, x, y)
	if button ~= "LeftButton" then return end
	if self.phase == "show" then
		self:Advance()
		return
	end
	if not (x and y) or y < TOP or y > TOP + MAP_H or x < 0 or x > MAP_W then return end
	self:Guess(x / MAP_W, (y - TOP) / MAP_H)
end

function Where:Summary()
	if not self.round or self.round == 0 then return nil end
	return L["Place %d of %d"]:format(self.round, ROUNDS)
end

-- A soft tile for each place of the continent, for a client without map art.
function Where:DrawTiles(continent, shown)
	local n = 0
	for _, place in ipairs(Places()) do
		if shown and place.continent == continent then
			n = n + 1
			local tile = self.zones[n]
			if not tile then
				tile = B.Sprite(self.host.area, 10, 10, "BORDER")
				self.zones[n] = tile
			end
			local r = place.rect
			tile:SetSize(math.max(4, (r[2] - r[1]) * MAP_W - 2), math.max(4, (r[4] - r[3]) * MAP_H - 2))
			B.Place(tile, r[1] * MAP_W + 1, TOP + r[3] * MAP_H + 1, self.host.area)
			B.Tile(tile, E.tokens.palette.bronze, 0.6)
			tile:Show()
		end
	end
	for i = n + 1, #self.zones do self.zones[i]:Hide() end
end

function Where:Draw()
	local color, area = self.host.Color, self.host.area
	local place = self.place and Find(self.place)
	local continent = place and place.continent or self.mode.only or EASTERN
	B.Fill(self.paper, self.host.Palette()[7], 0.22)
	for id, map in pairs(self.maps) do
		if map then map:SetShown(id == continent and self.phase ~= "none") end
	end
	local map = self.phase ~= "none" and self:Map(continent)
	if map then map:Show() end
	self:DrawTiles(continent, self.phase ~= "none" and not map)
	self.empty:SetText(self.phase == "none" and L["The world map is not available here."] or "")
	if self.phase == "none" or not place then
		self.progress:SetText("")
		self.ask:SetText("")
		self.note:SetText("")
		self.spot:Hide()
		self.zone:Hide()
		self.pin:Hide()
		for _, dot in ipairs(self.trail) do dot:Hide() end
		return
	end
	self.progress:SetText(L["Place %d of %d"]:format(self.round, ROUNDS))
	self.ask:SetText(L["Where is %s?"]:format(place.name))
	local showing = self.phase ~= "ask" and self.guess
	self.note:SetText(showing and (self.gain >= 100 and L["Spot on!"] or E:Plural(self.gain, "+%d point", "+%d points"):format(self.gain)) or "")
	self.note:SetTextColor(unpack(showing and (self.gain >= 100 and color("good") or self.gain > 0 and color("warn") or color("bad")) or color("body")))
	self.zone:SetShown(showing and true or false)
	self.spot:SetShown(showing and true or false)
	self.pin:SetShown(showing and true or false)
	for _, dot in ipairs(self.trail) do dot:Hide() end
	if not showing then return end
	local r = place.rect
	local w, h = (r[2] - r[1]) * MAP_W, (r[4] - r[3]) * MAP_H
	self.zone:SetSize(math.max(6, w), math.max(6, h))
	B.Tile(self.zone, color("good"), 0.35)
	B.Place(self.zone, r[1] * MAP_W, TOP + r[3] * MAP_H, area)
	local cx, cy = (r[1] + r[2]) / 2 * MAP_W, TOP + (r[3] + r[4]) / 2 * MAP_H
	local size = math.max(18, math.min(46, math.min(w, h)))
	self.spot:SetSize(size, size)
	B.Art(self.spot, "Ring", color("gold"), 0.95)
	B.Place(self.spot, cx - size / 2, cy - size / 2, area)
	local gx, gy = self.guess[1] * MAP_W, TOP + self.guess[2] * MAP_H
	B.Art(self.pin, "Ring", self.gain > 0 and color("warn") or color("bad"), 1)
	B.Place(self.pin, gx - 11, gy - 11, area)
	if self.gain < 100 then
		local c = color("body")
		for i, dot in ipairs(self.trail) do
			local t = i / (#self.trail + 1)
			dot:SetVertexColor(c[1], c[2], c[3], 0.75)
			B.Place(dot, gx + (cx - gx) * t - 2.5, gy + (cy - gy) * t - 2.5, area)
			dot:Show()
		end
	end
end

M:RegisterGame({
	key = "whereis", order = 230, group = "quiz",
	title = "Where Is It?", desc = "A zone or a city and the map of its continent: click where it lies.",
	controls = Key("Click the map where the place lies. P: pause."),
	icon = "Interface\\Icons\\INV_Misc_Map02",
	modes = MODES,
	width = WIDTH, height = HEIGHT,
	New = New,
})
