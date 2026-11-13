-- EldoUI Flight Games: Coin Merge. Slide every coin one way; two coins of
-- the same worth that meet become one coin of their sum, worth that sum in
-- points. After each move a 2 (or now and then a 4) appears. A coin worth
-- 2048 wins, and play goes on as long as a move is left.
-- Written from scratch for EldoUI.
local _, E = ...
local M = E.FlightGames
local Key = E.Key
local B = M.Board

local SIZE, CELL, GOAL = 4, 80, 2048
local DIRS = {
	UP = { 0, -1 }, W = { 0, -1 }, DOWN = { 0, 1 }, S = { 0, 1 },
	LEFT = { -1, 0 }, A = { -1, 0 }, RIGHT = { 1, 0 }, D = { 1, 0 },
}

local Merge = {}
Merge.__index = Merge
-- What a saved game keeps (the board, the score and the timers).
Merge.saveKeys = { "tiles", "score", "won" }

local function New(host)
	local game = setmetatable({ host = host }, Merge)
	game.grid = B.Grid(host.area, SIZE, SIZE, CELL, { gap = 6 })
	game.grid.frame:SetPoint("TOPLEFT")
	game.labels = {}
	for y = 1, SIZE do
		for x = 1, SIZE do
			local label = B.Label(game.grid.frame, E.tokens.size.display, "title")
			label:SetPoint("CENTER", game.grid.frame, "TOPLEFT", (x - 0.5) * CELL, -(y - 0.5) * CELL)
			game.labels[(y - 1) * SIZE + x] = label
		end
	end
	return game
end

function Merge:Add()
	local free = {}
	for y = 1, SIZE do
		for x = 1, SIZE do
			if not self.tiles[y][x] then free[#free + 1] = { x, y } end
		end
	end
	if #free == 0 then return end
	local spot = free[self.host.Random(#free)]
	self.tiles[spot[2]][spot[1]] = self.host.Random(10) == 1 and 4 or 2
end

function Merge:Start()
	self.tiles = {}
	for y = 1, SIZE do self.tiles[y] = {} end
	self.score, self.won = 0, false
	self:Add()
	self:Add()
	self:Draw()
end

-- One move; true when anything moved.
function Merge:Slide(dx, dy)
	local moved = false
	local tiles = self.tiles
	-- Walk from the side the tiles move to.
	local xs, ys = {}, {}
	for i = 1, SIZE do
		xs[i] = dx == 1 and SIZE + 1 - i or i
		ys[i] = dy == 1 and SIZE + 1 - i or i
	end
	local merged = {}
	for _, y in ipairs(ys) do
		for _, x in ipairs(xs) do
			local value = tiles[y][x]
			if value then
				local cx, cy = x, y
				while true do
					local nx, ny = cx + dx, cy + dy
					if nx < 1 or ny < 1 or nx > SIZE or ny > SIZE then break end
					local other = tiles[ny][nx]
					if not other then
						cx, cy = nx, ny
					elseif other == value and not merged[ny * 10 + nx] then
						cx, cy = nx, ny
						break
					else
						break
					end
				end
				if cx ~= x or cy ~= y then
					tiles[y][x] = nil
					if tiles[cy][cx] then
						tiles[cy][cx] = value * 2
						merged[cy * 10 + cx] = true
						self.score = self.score + value * 2
						if value * 2 >= GOAL then self.won = true end
					else
						tiles[cy][cx] = value
					end
					moved = true
				end
			end
		end
	end
	return moved
end

-- Nothing runs between moves.
function Merge:Update() end

function Merge:CanMove()
	for y = 1, SIZE do
		for x = 1, SIZE do
			local value = self.tiles[y][x]
			if not value then return true end
			if x < SIZE and self.tiles[y][x + 1] == value then return true end
			if y < SIZE and self.tiles[y + 1][x] == value then return true end
		end
	end
	return false
end

function Merge:Move(dx, dy)
	local before = self.won
	if not self:Slide(dx, dy) then return end
	self:Add()
	self.host.Score(self.score)
	self.host.Sound(self.won and not before and "best" or "turn")
	self:Draw()
	if not self:CanMove() then self.host.Over(self.won) end
end

function Merge:Key(key)
	local dir = DIRS[key]
	if not dir then return false end
	self:Move(dir[1], dir[2])
	return true
end

-- A click on a side of the board slides the tiles that way.
function Merge:Press(button, x, y)
	if button ~= "LeftButton" then return end
	local half = SIZE * CELL / 2
	local dx, dy = x - half, y - half
	if math.abs(dx) > math.abs(dy) then self:Move(dx > 0 and 1 or -1, 0) else self:Move(0, dy > 0 and 1 or -1) end
end

-- Each doubling a step brighter in the palette.
function Merge:Draw()
	local grid, palette = self.grid, self.host.Palette()
	for y = 1, SIZE do
		for x = 1, SIZE do
			local value = self.tiles and self.tiles[y][x]
			local label = self.labels[(y - 1) * SIZE + x]
			if value then
				local step = math.floor(math.log(value) / math.log(2) + 0.5)
				grid:Paint(x, y, palette[(step - 1) % #palette + 1], math.min(1, 0.45 + step * 0.05))
				label:SetText(value)
			else
				grid:Paint(x, y, self.host.Color("dim"), 0.25)
				label:SetText("")
			end
		end
	end
end

M:RegisterGame({
	key = "merge", order = 60, group = "puzzle",
	title = "Coin Merge", desc = "Slide the coins and merge equal ones until one is worth 2048.",
	controls = Key("Arrow keys or WASD, or click a side of the board: slide. P: pause."),
	icon = "Interface\\Icons\\INV_Misc_Coin_01",
	width = SIZE * CELL, height = SIZE * CELL,
	New = New,
})
