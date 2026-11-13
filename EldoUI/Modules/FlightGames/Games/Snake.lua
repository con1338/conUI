-- EldoUI Flight Games: Snake. Steer a growing line to the food; the walls
-- and your own tail end the run. Each meal is worth 10 points and makes
-- the next step a little quicker.
-- Written from scratch for EldoUI.
local _, E = ...
local M = E.FlightGames
local Key = E.Key
local B = M.Board

local COLS, ROWS, CELL = 22, 16, 18
local START_STEP, MIN_STEP, FASTER = 0.14, 0.06, 0.003
local FOOD = "Interface\\Icons\\INV_Misc_Food_15"
local DIRS = {
	UP = { 0, -1 }, W = { 0, -1 }, DOWN = { 0, 1 }, S = { 0, 1 },
	LEFT = { -1, 0 }, A = { -1, 0 }, RIGHT = { 1, 0 }, D = { 1, 0 },
}

local Snake = {}
Snake.__index = Snake
-- What a saved game keeps (the board, the score and the timers).
Snake.saveKeys = { "body", "taken", "dir", "queue", "wait", "since", "score", "food" }

local function New(host)
	local game = setmetatable({ host = host }, Snake)
	game.grid = B.Grid(host.area, COLS, ROWS, CELL)
	game.grid.frame:SetPoint("TOPLEFT")
	return game
end

local function Spot(x, y) return y * 100 + x end

function Snake:PlaceFood()
	local free = {}
	for y = 1, ROWS do
		for x = 1, COLS do
			if not self.taken[Spot(x, y)] then free[#free + 1] = { x, y } end
		end
	end
	if #free == 0 then
		self.food = nil
		return
	end
	local spot = free[self.host.Random(#free)]
	self.food = { spot[1], spot[2] }
end

function Snake:Start()
	local mx, my = math.floor(COLS / 2), math.floor(ROWS / 2)
	self.body = { { mx, my }, { mx - 1, my }, { mx - 2, my } }
	self.taken = {}
	for _, part in ipairs(self.body) do self.taken[Spot(part[1], part[2])] = true end
	self.dir = { 1, 0 }
	self.queue = {}
	self.wait = START_STEP
	self.since = 0
	self.score = 0
	self:PlaceFood()
	self:Draw()
end

function Snake:Draw()
	local grid, palette = self.grid, self.host.Palette()
	grid:ClearAll()
	for index, part in ipairs(self.body) do
		if index == 1 then
			grid:Paint(part[1], part[2], self.host.Color("accent"))
		else
			grid:Paint(part[1], part[2], palette[3], index % 2 == 0 and 1 or 0.85)
		end
	end
	if self.food then grid:Icon(self.food[1], self.food[2], FOOD) end
end

function Snake:Key(key)
	local dir = DIRS[key]
	if not dir then return false end
	-- At most two turns wait; a turn straight back is ignored.
	local last = self.queue[#self.queue] or self.dir
	if (dir[1] ~= -last[1] or dir[2] ~= -last[2]) and #self.queue < 2 and (dir[1] ~= last[1] or dir[2] ~= last[2]) then
		self.queue[#self.queue + 1] = dir
	end
	return true
end

function Snake:Move()
	if #self.queue > 0 then self.dir = table.remove(self.queue, 1) end
	local head = self.body[1]
	local x, y = head[1] + self.dir[1], head[2] + self.dir[2]
	local eats = self.food and x == self.food[1] and y == self.food[2]
	if not eats then
		local tail = table.remove(self.body)
		self.taken[Spot(tail[1], tail[2])] = nil
	end
	if x < 1 or y < 1 or x > COLS or y > ROWS or self.taken[Spot(x, y)] then
		self:Draw()
		self.host.Over(false)
		return
	end
	table.insert(self.body, 1, { x, y })
	self.taken[Spot(x, y)] = true
	if eats then
		self.score = self.score + 10
		self.host.Score(self.score)
		self.host.Sound("point")
		self.wait = math.max(MIN_STEP, self.wait - FASTER)
		self:PlaceFood()
		if not self.food then
			self:Draw()
			self.host.Over(true)
			return
		end
	end
	self:Draw()
end

function Snake:Update(dt)
	self.since = self.since + dt * self.host.Pace()
	if self.since < self.wait then return end
	-- One cell per frame at most, and no backlog after a slow frame.
	self.since = math.min(self.since - self.wait, self.wait)
	self:Move()
end

M:RegisterGame({
	key = "snake", order = 10, group = "arcade",
	title = "Snake", desc = "Eat, grow and keep clear of the walls and your tail.",
	controls = Key("Arrow keys or WASD: turn. P: pause."),
	icon = "Interface\\Icons\\Ability_Hunter_BeastTaming",
	width = COLS * CELL, height = ROWS * CELL,
	New = New,
})
