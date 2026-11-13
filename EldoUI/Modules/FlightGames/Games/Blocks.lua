-- EldoUI Flight Games: Rune Stack. Shapes of four blocks fall into a well;
-- turn and slide them so they fill whole rows, which clear. Every ten rows
-- the level goes up and the shapes fall faster. The run ends when a new
-- shape has no room.
--
-- Scoring: 100, 300, 500 or 800 points for one to four rows at once, times
-- the level; a soft drop gives 1 point a row, a hard drop 2.
-- Written from scratch for EldoUI, with its own well size and look.
local _, E = ...
local L = E.L
local M = E.FlightGames
local Key = E.Key
local B = M.Board

local COLS, ROWS, CELL = 10, 18, 20
local SIDE = 120
local LINE_POINTS = { 100, 300, 500, 800 }

-- The seven shapes, as block offsets; the first is the turning point.
local SHAPES = {
	{ { 0, 0 }, { -1, 0 }, { 1, 0 }, { 2, 0 } },   -- bar
	{ { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } },    -- square
	{ { 0, 0 }, { -1, 0 }, { 1, 0 }, { 0, 1 } },   -- tee
	{ { 0, 0 }, { -1, 0 }, { 1, 0 }, { 1, 1 } },   -- hook right
	{ { 0, 0 }, { -1, 0 }, { 1, 0 }, { -1, 1 } },  -- hook left
	{ { 0, 0 }, { 1, 0 }, { 0, 1 }, { -1, 1 } },   -- step right
	{ { 0, 0 }, { -1, 0 }, { 0, 1 }, { 1, 1 } },   -- step left
}

local Blocks = {}
Blocks.__index = Blocks
-- What a saved game keeps (the board, the score and the timers).
Blocks.saveKeys = { "well", "score", "lines", "level", "since", "upcoming", "piece" }

local function New(host)
	local game = setmetatable({ host = host }, Blocks)
	game.grid = B.Grid(host.area, COLS, ROWS, CELL)
	game.grid.frame:SetPoint("TOPLEFT")
	game.next = B.Grid(host.area, 4, 2, CELL, { gap = 1 })
	game.next.frame:SetPoint("TOPLEFT", COLS * CELL + 20, -28)
	game.next.frame.bg:Hide()
	game.nextLabel = B.Label(host.area, E.tokens.size.small, "secondary", "LEFT")
	game.nextLabel:SetPoint("TOPLEFT", COLS * CELL + 20, -8)
	game.nextLabel:SetText(L["Next"])
	game.info = B.Label(host.area, E.tokens.size.label, "body", "LEFT")
	game.info:SetPoint("TOPLEFT", COLS * CELL + 20, -90)
	game.info:SetWidth(SIDE - 24)
	game.info:SetJustifyV("TOP")
	return game
end

function Blocks:Fall()
	local level = self.level or 1
	return math.max(0.1, 0.8 - (level - 1) * 0.07) / self.host.Pace()
end

function Blocks:Spawn()
	local kind = self.upcoming or self.host.Random(#SHAPES)
	self.upcoming = self.host.Random(#SHAPES)
	local cells = {}
	for index, offset in ipairs(SHAPES[kind]) do cells[index] = { offset[1], offset[2] } end
	self.piece = { kind = kind, cells = cells, x = math.floor(COLS / 2), y = 1 }
	if not self:Fits(self.piece.cells, self.piece.x, self.piece.y) then
		self.piece = nil
		self:Draw()
		self.host.Over(false)
		return false
	end
	return true
end

function Blocks:Fits(cells, px, py)
	for _, c in ipairs(cells) do
		local x, y = px + c[1], py + c[2]
		if x < 1 or x > COLS or y > ROWS then return false end
		if y >= 1 and self.well[y][x] then return false end
	end
	return true
end

function Blocks:Start()
	self.well = {}
	for y = 1, ROWS do self.well[y] = {} end
	self.score, self.lines, self.level = 0, 0, 1
	self.since = 0
	self.upcoming = nil
	self:Spawn()
	self:Draw()
end

function Blocks:Lock()
	local piece = self.piece
	local over = false
	for _, c in ipairs(piece.cells) do
		local x, y = piece.x + c[1], piece.y + c[2]
		if y >= 1 then self.well[y][x] = piece.kind else over = true end
	end
	-- A piece that locks above the top of the well ends the game.
	if over then
		self:Draw()
		self.host.Over(false)
		return
	end
	-- Full rows clear; the rows above move down.
	local cleared = 0
	local y = ROWS
	while y >= 1 do
		local full = true
		for x = 1, COLS do
			if not self.well[y][x] then full = false break end
		end
		if full then
			table.remove(self.well, y)
			table.insert(self.well, 1, {})
			cleared = cleared + 1
		else
			y = y - 1
		end
	end
	if cleared > 0 then
		self.score = self.score + LINE_POINTS[math.min(cleared, 4)] * self.level
		self.lines = self.lines + cleared
		self.level = math.floor(self.lines / 10) + 1
		self.host.Sound("point")
	end
	self.host.Score(self.score)
	self.piece = nil
	self:Spawn()
end

function Blocks:Shift(dx, dy)
	local piece = self.piece
	if not piece then return false end
	if self:Fits(piece.cells, piece.x + dx, piece.y + dy) then
		piece.x, piece.y = piece.x + dx, piece.y + dy
		return true
	end
	return false
end

function Blocks:Turn()
	local piece = self.piece
	if not piece or piece.kind == 2 then return end
	local turned = {}
	for index, c in ipairs(piece.cells) do turned[index] = { -c[2], c[1] } end
	-- A turn against a wall or a block tries one step aside first.
	for _, kick in ipairs({ 0, -1, 1, -2, 2 }) do
		if self:Fits(turned, piece.x + kick, piece.y) then
			piece.cells, piece.x = turned, piece.x + kick
			self.host.Sound("turn")
			return
		end
	end
end

function Blocks:Key(key)
	if not self.piece then return false end
	if key == "LEFT" or key == "A" then
		self:Shift(-1, 0)
	elseif key == "RIGHT" or key == "D" then
		self:Shift(1, 0)
	elseif key == "UP" or key == "W" or key == "X" then
		self:Turn()
	elseif key == "DOWN" or key == "S" then
		if self:Shift(0, 1) then
			self.score = self.score + 1
			self.host.Score(self.score)
			self.since = 0
		else
			self:Lock()
		end
	elseif key == "SPACE" then
		local rows = 0
		while self:Shift(0, 1) do rows = rows + 1 end
		self.score = self.score + rows * 2
		self:Lock()
	else
		return false
	end
	self:Draw()
	return true
end

function Blocks:Update(dt)
	if not self.piece then return end
	self.since = self.since + dt
	if self.since < self:Fall() then return end
	self.since = 0
	if not self:Shift(0, 1) then self:Lock() end
	self:Draw()
end

function Blocks:Draw()
	local grid, palette = self.grid, self.host.Palette()
	grid:ClearAll()
	for y = 1, ROWS do
		for x = 1, COLS do
			local kind = self.well and self.well[y][x]
			if kind then grid:Paint(x, y, palette[kind], 0.85) end
		end
	end
	local piece = self.piece
	if piece then
		for _, c in ipairs(piece.cells) do grid:Paint(piece.x + c[1], piece.y + c[2], palette[piece.kind]) end
	end
	self.next:ClearAll()
	if self.upcoming then
		for _, c in ipairs(SHAPES[self.upcoming]) do self.next:Paint(c[1] + 2, c[2] + 1, palette[self.upcoming]) end
	end
	self.info:SetText(L["Level %d"]:format(self.level or 1) .. "\n" .. L["Rows %d"]:format(self.lines or 0))
end

M:RegisterGame({
	key = "blocks", order = 20, group = "arcade",
	title = "Rune Stack", desc = "Turn the falling shapes and fill whole rows.",
	controls = Key("Left and right: move. Up: turn. Down: drop faster. Space: drop. P: pause."),
	icon = "Interface\\Icons\\INV_Misc_Rune_01",
	width = COLS * CELL + SIDE, height = ROWS * CELL,
	New = New,
})
