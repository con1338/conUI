-- EldoUI Flight Games: Sliding Map. A map of a zone is cut into pieces
-- and shuffled, with one piece left out. Slide the pieces into the gap
-- until the map is whole again, in as few moves as you can.
-- Written from scratch for EldoUI; the maps are the game's own zone maps
-- (numbered stones when the client has no map art).
local _, E = ...
local M = E.FlightGames
local Key = E.Key
local L = E.L
local B = M.Board

local BOARD = 420
local MODES = {
	{ key = "three", title = "3 x 3", size = 3 },
	{ key = "four", title = "4 x 4", size = 4 },
	{ key = "five", title = "5 x 5", size = 5 },
}
-- Zones of the old world (uiMapID).
local ZONES = { 1429, 1436, 1411, 1412, 1426, 1438, 1420, 1434, 1413, 1440, 1431, 1437, 1446, 1444, 1433, 1432 }
local SLIDE = 0.1
local DIRS = { UP = { 0, 1 }, W = { 0, 1 }, DOWN = { 0, -1 }, S = { 0, -1 }, LEFT = { 1, 0 }, A = { 1, 0 }, RIGHT = { -1, 0 }, D = { -1, 0 } }

local Slide = {}
Slide.__index = Slide
-- What a saved game keeps (the board, the score and the timers).
Slide.saveKeys = { "cells", "moves", "zone" }

local function ModeOf(mode)
	return mode and mode.size and mode or MODES[1]
end

local function New(host, mode)
	mode = ModeOf(mode)
	local game = setmetatable({ host = host, mode = mode, pieces = {} }, Slide)
	local area = host.area
	game.back = B.Sprite(area, BOARD, BOARD, "BACKGROUND")
	B.Place(game.back, 0, 0, area)
	game.name = B.Label(area, E.tokens.size.small, "secondary")
	game.name:SetPoint("TOP", area, "TOPLEFT", BOARD / 2, -(BOARD + 6))
	game.fx = B.Effects(area)
	return game
end

-- The pieces for a zone: each a clipped window onto the whole map. Built
-- once per zone and board size, then kept for the next game.
local sets = {}
function Slide:Build()
	local area, n = self.host.area, self.mode.size
	local piece = BOARD / n
	for _, p in pairs(self.pieces) do p.frame:Hide() end
	local id = self.zone .. ":" .. n
	local set = sets[id]
	if not (set and set.area == area) then
		set = { area = area, pieces = {}, mapped = false }
		for k = 1, n * n - 1 do
			local p = {}
			p.frame = CreateFrame("Frame", nil, area)
			p.frame:SetSize(piece - 2, piece - 2)
			if p.frame.SetClipsChildren then p.frame:SetClipsChildren(true) end
			local col, row = (k - 1) % n, math.floor((k - 1) / n)
			p.map = B.MapArt(p.frame, self.zone, BOARD, BOARD)
			if p.map then
				set.mapped = true
				p.map:SetPoint("TOPLEFT", p.frame, "TOPLEFT", -col * piece - 1, row * piece + 1)
			else
				p.stone = B.Sprite(p.frame, piece - 2, piece - 2, "BORDER")
				B.Place(p.stone, 0, 0, p.frame)
			end
			p.edge = B.Sprite(p.frame, piece - 2, piece - 2, "OVERLAY")
			B.Place(p.edge, 0, 0, p.frame)
			-- On a map the number is a small help in the corner; on a plain
			-- stone it is the stone's face.
			if p.map then
				p.number = B.Label(p.frame, E.tokens.size.small, "body")
				p.number:SetPoint("TOPLEFT", p.frame, "TOPLEFT", 6, -5)
			else
				p.number = B.Label(p.frame, E.tokens.size.hero, "body")
				p.number:SetPoint("CENTER", p.frame, "CENTER", 0, 0)
			end
			p.number:SetText(k)
			set.pieces[k] = p
		end
		sets[id] = set
	end
	self.pieces, self.mapped = set.pieces, set.mapped
end

function Slide:Stop()
	for _, p in pairs(self.pieces) do p.frame:Hide() end
end

function Slide:Start()
	local n = self.mode.size
	self.zone = ZONES[self.host.Random(#ZONES)]
	self.cells = {}
	for i = 1, n * n - 1 do self.cells[i] = i end
	self.cells[n * n] = 0
	-- Random slides from the solved board: always solvable.
	local blank = n * n
	local last
	local count = 0
	-- A walk that came back to the solved board slides on; a swap of two
	-- tiles could make it unsolvable.
	while count < n * n * 30 or self:Solved() do
		count = count + 1
		local bx, by = (blank - 1) % n + 1, math.floor((blank - 1) / n) + 1
		local options = {}
		for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
			local x, y = bx + d[1], by + d[2]
			local i = (y - 1) * n + x
			if x >= 1 and y >= 1 and x <= n and y <= n and i ~= last then options[#options + 1] = i end
		end
		local pick = options[self.host.Random(#options)]
		self.cells[blank], self.cells[pick] = self.cells[pick], 0
		last, blank = blank, pick
	end
	self.moves = 0
	self:Build()
	self.host.Score(0)
	self:Draw()
end

function Slide:Loaded()
	self:Build()
end

function Slide:Solved()
	local n = self.mode.size
	for i = 1, n * n - 1 do
		if self.cells[i] ~= i then return false end
	end
	return true
end

function Slide:Blank()
	for i, v in ipairs(self.cells) do
		if v == 0 then return i end
	end
end

-- Moves the piece at x, y into the gap when they share a row or column
-- (a whole run of pieces slides together).
function Slide:Push(x, y)
	local n = self.mode.size
	local blank = self:Blank()
	local bx, by = (blank - 1) % n + 1, math.floor((blank - 1) / n) + 1
	if x ~= bx and y ~= by then return end
	if x == bx and y == by then return end
	local sx, sy = x > bx and 1 or x < bx and -1 or 0, y > by and 1 or y < by and -1 or 0
	while bx ~= x or by ~= y do
		local nx, ny = bx + sx, by + sy
		local from, to = (ny - 1) * n + nx, (by - 1) * n + bx
		self.cells[to], self.cells[from] = self.cells[from], 0
		bx, by = nx, ny
		self.moves = self.moves + 1
	end
	self.host.Score(self.moves)
	self.host.Sound("turn")
	self:Draw()
	if self:Solved() then
		self.fx:Burst(BOARD / 2, BOARD / 2, self.host.Color("good"), BOARD, 0.8)
		self.fx:Sparks(BOARD / 2, BOARD / 2, self.host.Color("gold"), 16, 220)
		self.host.Sound("point")
		self.host.Over(true)
	end
end

function Slide:Key(key)
	local d = DIRS[key]
	if not d then return false end
	local n = self.mode.size
	local blank = self:Blank()
	local x, y = (blank - 1) % n + 1 + d[1], math.floor((blank - 1) / n) + 1 + d[2]
	if x >= 1 and y >= 1 and x <= n and y <= n then self:Push(x, y) end
	return true
end

function Slide:Press(button, x, y)
	if button ~= "LeftButton" or not (x and y) then return end
	local piece = BOARD / self.mode.size
	local cx, cy = math.floor(x / piece) + 1, math.floor(y / piece) + 1
	if cx >= 1 and cy >= 1 and cx <= self.mode.size and cy <= self.mode.size then self:Push(cx, cy) end
end

function Slide:Update(dt)
	self.fx:Update(dt)
end

function Slide:Summary()
	if not self.moves then return nil end
	return E:Plural(self.moves, "Whole in %d move", "Whole in %d moves"):format(self.moves)
end

function Slide:Draw()
	local area, n = self.host.area, self.mode.size
	local piece = BOARD / n
	local palette, color = self.host.Palette(), self.host.Color
	B.Fill(self.back, color("dim"), 0.25)
	for i, id in ipairs(self.cells) do
		local p = self.pieces[id]
		if p then
			local col, row = (i - 1) % n, math.floor((i - 1) / n)
			p.frame:ClearAllPoints()
			p.frame:SetPoint("TOPLEFT", area, "TOPLEFT", col * piece + 1, -(row * piece + 1))
			p.frame:Show()
			local home = id == i
			if p.stone then B.Tile(p.stone, palette[(id - 1) % 7 + 1], 0.85) end
			B.Art(p.edge, "Ring", home and color("good") or color("body"), home and 0.55 or 0.25)
			p.number:SetShown(not self.mapped or not home)
		end
	end
	local name
	if C_Map and C_Map.GetMapInfo then
		local ok, info = pcall(C_Map.GetMapInfo, self.zone)
		name = ok and type(info) == "table" and info.name
	end
	self.name:SetText(type(name) == "string" and name or "")
end

M:RegisterGame({
	key = "slide", order = 77, group = "puzzle",
	title = "Sliding Map", desc = "Slide the pieces of a zone map back into place.",
	controls = Key("Click a piece in line with the gap, or the arrow keys. P: pause."),
	icon = "Interface\\Icons\\INV_Misc_Map02",
	modes = MODES, lower = true, unit = "moves",
	Size = function() return BOARD, BOARD + 22 end,
	New = New,
})
