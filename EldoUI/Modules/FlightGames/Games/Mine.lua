-- EldoUI Flight Games: Candle Mine. Walk the tunnels of an old mine and
-- pick up every candle while the bats hunt you in the dark. A big candle
-- lights the mine for a while: the bats flee, and catching one is worth
-- 200. Clear the mine for the next, faster one. A bat that catches you
-- costs one of three lives.
-- Written from scratch for EldoUI; you are your own character and the bats
-- are the game's own models (icons when models are off).
local _, E = ...
local M = E.FlightGames
local Key = E.Key
local L = E.L
local B = M.Board

local MAZE = {
	"###################",
	"#........#........#",
	"#o##.###.#.###.##o#",
	"#.................#",
	"#.##.#.#####.#.##.#",
	"#....#...#...#....#",
	"####.###.#.###.####",
	"####.#..GGG..#.####",
	"####.#.#####.#.####",
	"#........#........#",
	"#.##.###.#.###.##.#",
	"#o.#.....P.....#.o#",
	"#..#.#.#####.#.#..#",
	"#....#.......#....#",
	"###################",
}
local COLS, ROWS, CELL = #MAZE[1], #MAZE, 24
local HUD = 28
local WIDTH, HEIGHT = COLS * CELL, ROWS * CELL + HUD
local LIVES, BATS = 3, 3
local SPEED, BAT_SPEED, SCARED_SPEED = 5.2, 4.2, 2.6
local FRIGHT = 6
local DIRS = { { 0, -1 }, { 1, 0 }, { 0, 1 }, { -1, 0 } }  -- up, right, down, left
local KEYS = { UP = 1, W = 1, RIGHT = 2, D = 2, DOWN = 3, S = 3, LEFT = 4, A = 4 }
local FACING = { 0, -math.pi / 2, math.pi, math.pi / 2 }
local MINER = "Interface\\Icons\\Trade_Mining"
local BAT = "Interface\\Icons\\Ability_Hunter_Pet_Bat"

local Mine = {}
Mine.__index = Mine
-- What a saved game keeps (the board, the score and the timers).
Mine.saveKeys = { "dots", "left", "you", "bats", "score", "lives", "level", "fright", "hurt", "want" }

local function Wall(x, y)
	local row = MAZE[y]
	return not row or x < 1 or x > COLS or row:sub(x, x) == "#"
end

local function Spot(x, y) return y * 100 + x end

local function New(host)
	local game = setmetatable({ host = host }, Mine)
	local area = host.area
	game.grid = B.Grid(area, COLS, ROWS, CELL, { gap = 2 })
	game.grid.frame:SetPoint("TOPLEFT")
	game.candles = {}
	for y = 1, ROWS do
		for x = 1, COLS do
			local c = MAZE[y]:sub(x, x)
			if c == "." or c == "o" then
				local big = c == "o"
				local size = big and 14 or 6
				local dot = B.Dot(area, size, nil, "ARTWORK")
				B.Place(dot, (x - 0.5) * CELL - size / 2, (y - 0.5) * CELL - size / 2, area)
				local glow
				if big then
					glow = B.Sprite(area, CELL, CELL, "ARTWORK")
					B.Place(glow, (x - 1) * CELL, (y - 1) * CELL, area)
				end
				game.candles[Spot(x, y)] = { dot = dot, glow = glow, big = big }
			end
		end
	end
	game.miner = B.Actor(area, CELL, "player", MINER, { scale = 2.2, facing = 0, animation = B.ANIM.run })
	game.batActors = {}
	for i = 1, BATS do
		game.batActors[i] = {
			actor = B.Actor(area, CELL, B.DISPLAY.bat, BAT, { scale = 2.2, animation = B.ANIM.fly }),
			ring = B.Sprite(area, CELL + 10, CELL + 10, "OVERLAY"),
		}
	end
	game.fx = B.Effects(area)
	game.hearts = {}
	for i = 1, LIVES do
		local heart = B.Sprite(area, 18, 18, "ARTWORK")
		B.Place(heart, 8 + (i - 1) * 22, ROWS * CELL + 6, area)
		game.hearts[i] = heart
	end
	game.levelText = B.Label(area, E.tokens.size.small, "secondary", "RIGHT")
	game.levelText:SetPoint("RIGHT", area, "TOPLEFT", WIDTH - 8, -(ROWS * CELL + 15))
	game:PaintWalls()
	return game
end

-- The rock walls (they never change).
function Mine:PaintWalls()
	local grid, rock = self.grid, E.tokens.palette.bronze
	for y = 1, ROWS do
		for x = 1, COLS do
			if Wall(x, y) then
				grid:Paint(x, y, rock, 0.55 + ((x + y) % 3) * 0.08)
			else
				grid:Clear(x, y)
			end
		end
	end
end

function Mine:Fill()
	self.dots, self.left = {}, 0
	for y = 1, ROWS do
		for x = 1, COLS do
			local c = MAZE[y]:sub(x, x)
			if c == "." or c == "o" then
				self.dots[Spot(x, y)] = c == "o" and 2 or 1
				self.left = self.left + 1
			end
		end
	end
end

function Mine:Places()
	for y = 1, ROWS do
		for x = 1, COLS do
			local c = MAZE[y]:sub(x, x)
			if c == "P" then
				self.you = { x = x, y = y, dir = 4, t = 0 }
			end
		end
	end
	self.bats = {}
	local n = 0
	for y = 1, ROWS do
		for x = 1, COLS do
			if MAZE[y]:sub(x, x) == "G" then
				n = n + 1
				self.bats[n] = { x = x, y = y, dir = 1, t = 0, home = { x, y }, wait = n - 1 }
			end
		end
	end
	self.want = nil
	self.fright = 0
end

function Mine:Start()
	self.score, self.lives, self.level = 0, LIVES, 1
	self.hurt = nil
	self:PaintWalls()
	self:Fill()
	self:Places()
	self.host.Score(0)
	self:Draw()
end

function Mine:Key(key)
	local dir = KEYS[key]
	if not dir then return false end
	self.want = dir
	local you = self.you
	-- A turn straight back happens at once.
	if you.t > 0 and (dir + 1) % 4 + 1 == you.dir then
		local d = DIRS[you.dir]
		you.x, you.y, you.t, you.dir = you.x + d[1], you.y + d[2], 1 - you.t, dir
	end
	return true
end

-- Where a walker stands, in cells (fractions while it walks).
local function Pos(w)
	local d = DIRS[w.dir]
	return w.x + d[1] * w.t, w.y + d[2] * w.t
end

-- Walks a walker on; at each cell `choose` picks the next way (or nil to
-- stop).
local function Walk(w, distance, choose)
	while distance > 0 do
		if w.t == 0 then
			local dir = choose(w)
			if not dir then return end
			w.dir = dir
		end
		local step = math.min(distance, 1 - w.t)
		w.t = w.t + step
		distance = distance - step
		if w.t >= 1 then
			local d = DIRS[w.dir]
			w.x, w.y, w.t = w.x + d[1], w.y + d[2], 0
		end
	end
end

local function Open(x, y, dir)
	local d = DIRS[dir]
	return not Wall(x + d[1], y + d[2])
end

function Mine:BatWay(bat)
	local options = {}
	local back = (bat.dir + 1) % 4 + 1
	for dir = 1, 4 do
		if dir ~= back and Open(bat.x, bat.y, dir) then options[#options + 1] = dir end
	end
	if #options == 0 then return back end
	if #options == 1 then return options[1] end
	local you = self.you
	local scared = self.fright > 0
	if self.host.Random(10) <= 3 then return options[self.host.Random(#options)] end
	local best, bestScore
	for _, dir in ipairs(options) do
		local d = DIRS[dir]
		local dx, dy = bat.x + d[1] - you.x, bat.y + d[2] - you.y
		local score = dx * dx + dy * dy
		if scared then score = -score end
		if not bestScore or score < bestScore then best, bestScore = dir, score end
	end
	return best
end

function Mine:Lose()
	local x, y = Pos(self.you)
	self.fx:Burst((x - 0.5) * CELL, (y - 0.5) * CELL, self.host.Color("bad"), CELL * 3)
	self.fx:Sparks((x - 0.5) * CELL, (y - 0.5) * CELL, self.host.Color("bad"), 10)
	self.host.Sound("over")
	self.lives = self.lives - 1
	if self.lives <= 0 then
		self:Draw()
		self.host.Over(false)
		return
	end
	self.hurt = 1.0
	self:Places()
end

function Mine:Eat(x, y)
	local spot = Spot(x, y)
	local kind = self.dots[spot]
	if not kind then return end
	self.dots[spot] = nil
	self.left = self.left - 1
	local points = kind == 2 and 50 or 10
	self.score = self.score + points
	self.host.Score(self.score)
	if kind == 2 then
		self.fright = FRIGHT
		self.fx:Burst((x - 0.5) * CELL, (y - 0.5) * CELL, self.host.Color("gold"), CELL * 4, 0.6)
		self.host.Sound("point")
	end
	if self.left <= 0 then
		self.level = self.level + 1
		self.score = self.score + 500
		self.host.Score(self.score)
		self.fx:Float(WIDTH / 2, ROWS * CELL / 2, "+500", self.host.Color("good"), E.tokens.size.display)
		self:Fill()
		self:Places()
		self.hurt = 1.0
	end
end

function Mine:Update(dt)
	self.fx:Update(dt)
	if self.hurt then
		self.hurt = self.hurt - dt
		if self.hurt <= 0 then self.hurt = nil end
		self:Draw()
		return
	end
	local pace = self.host.Pace() * (1 + (self.level - 1) * 0.08)
	local you = self.you
	Walk(you, SPEED * pace * dt, function(w)
		if self.want and Open(w.x, w.y, self.want) then return self.want end
		if Open(w.x, w.y, w.dir) then return w.dir end
		return nil
	end)
	if you.t == 0 or you.t > 0.5 then
		local x, y = you.x, you.y
		if you.t > 0.5 then
			local d = DIRS[you.dir]
			x, y = x + d[1], y + d[2]
		end
		self:Eat(x, y)
		if self.hurt then return end
	end
	if self.fright > 0 then self.fright = math.max(0, self.fright - dt) end
	local yx, yy = Pos(you)
	for _, bat in ipairs(self.bats) do
		if bat.wait and bat.wait > 0 then
			bat.wait = bat.wait - dt
		else
			local speed = (self.fright > 0 and SCARED_SPEED or BAT_SPEED + (self.level - 1) * 0.3) * self.host.Pace()
			Walk(bat, speed * dt, function(w) return self:BatWay(w) end)
		end
		local bx, by = Pos(bat)
		if math.abs(bx - yx) < 0.6 and math.abs(by - yy) < 0.6 then
			if self.fright > 0 then
				self.score = self.score + 200
				self.host.Score(self.score)
				self.fx:Burst((bx - 0.5) * CELL, (by - 0.5) * CELL, self.host.Color("good"), CELL * 2.5)
				self.fx:Float((bx - 0.5) * CELL, (by - 0.5) * CELL, "+200", self.host.Color("good"))
				self.host.Sound("point")
				bat.x, bat.y, bat.t, bat.wait = bat.home[1], bat.home[2], 0, 2
			else
				self:Lose()
				return
			end
		end
	end
	self:Draw()
end

function Mine:Summary()
	return L["Reached level %d"]:format(self.level)
end

function Mine:Draw()
	local palette, color = self.host.Palette(), self.host.Color
	local pulse = 0.55 + 0.45 * math.abs(math.sin((GetTime and GetTime() or 0) * 3))
	local gold = color("gold")
	for spot, candle in pairs(self.candles) do
		local on = self.dots[spot] ~= nil
		candle.dot:SetShown(on)
		candle.dot:SetVertexColor(gold[1], gold[2], gold[3], 1)
		if candle.glow then
			candle.glow:SetShown(on)
			if on then B.Art(candle.glow, "Ring", gold, pulse) end
		end
	end
	local you = self.you
	local x, y = Pos(you)
	self.miner:Place((x - 1) * CELL, (y - 1) * CELL)
	self.miner:Face(FACING[you.dir])
	self.miner:SetAlpha(self.hurt and 0.5 or 1)
	for i, view in ipairs(self.batActors) do
		local bat = self.bats[i]
		if bat then
			local bx, by = Pos(bat)
			view.actor:Place((bx - 1) * CELL, (by - 1) * CELL)
			view.actor:Face(FACING[bat.dir])
			view.actor:SetShown(true)
			local scared = self.fright > 0
			view.ring:SetShown(scared)
			if scared then
				local blink = self.fright < 1.5 and math.floor(self.fright * 6) % 2 == 0
				B.Art(view.ring, "Ring", blink and color("body") or palette[1], 0.9)
				B.Place(view.ring, (bx - 1) * CELL - 5, (by - 1) * CELL - 5, self.host.area)
			end
			view.actor:Tint(scared and palette[1] or { 1, 1, 1 })
		else
			view.actor:SetShown(false)
			view.ring:Hide()
		end
	end
	for i, heart in ipairs(self.hearts) do
		B.Art(heart, "Heart", i <= self.lives and color("bad") or color("dim"), i <= self.lives and 1 or 0.4)
	end
	self.levelText:SetText(L["Level %d"]:format(self.level))
end

M:RegisterGame({
	key = "mine", order = 16, group = "arcade",
	title = "Candle Mine", desc = "Pick up every candle in the mine while the bats hunt you.",
	controls = Key("Arrow keys or WASD: walk. P: pause."),
	icon = "Interface\\Icons\\Trade_Mining",
	width = WIDTH, height = HEIGHT,
	New = New,
})
