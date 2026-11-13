-- EldoUI Flight Games: Air Hockey. Knock a gold coin into the far goal
-- with your striker; the computer guards the other end. The mouse moves
-- your striker (the arrow keys too), and the first to seven goals wins.
-- Written from scratch for EldoUI; the puck is the game's own gold coin.
local _, E = ...
local M = E.FlightGames
local Key = E.Key
local L = E.L
local B = M.Board

local WIDTH, HEIGHT = 330, 470
local GOAL_W = 120
local PUCK_R, MALLET_R = 13, 22
local MAX_SPEED = 900
local FRICTION = 0.6        -- the share of speed the puck keeps a second
local WIN = 7
local KEY_SPEED = 380
local MODES = {
	{ key = "easy", title = "Easy", reach = 230, aim = 0.5 },
	{ key = "normal", title = "Normal", reach = 330, aim = 0.75 },
	{ key = "hard", title = "Hard", reach = 440, aim = 1 },
}
local COIN = "Interface\\Icons\\INV_Misc_Coin_01"
local MOVE = { UP = { 0, -1 }, W = { 0, -1 }, DOWN = { 0, 1 }, S = { 0, 1 }, LEFT = { -1, 0 }, A = { -1, 0 }, RIGHT = { 1, 0 }, D = { 1, 0 } }

local Hockey = {}
Hockey.__index = Hockey
-- What a saved game keeps (the board, the score and the timers).
Hockey.saveKeys = { "puck", "you", "them", "goals", "against", "wait", "useKeys" }

local function ModeOf(mode)
	return mode and mode.reach and mode or MODES[2]
end

local function New(host, mode)
	local game = setmetatable({ host = host, mode = ModeOf(mode), held = {} }, Hockey)
	local area = host.area
	game.rink = B.Sprite(area, WIDTH, HEIGHT, "BACKGROUND")
	B.Place(game.rink, 0, 0, area)
	game.line = B.Sprite(area, WIDTH, 2, "BORDER")
	B.Place(game.line, 0, HEIGHT / 2 - 1, area)
	game.circle = B.Sprite(area, 110, 110, "BORDER")
	B.Place(game.circle, WIDTH / 2 - 55, HEIGHT / 2 - 55, area)
	game.goalTop = B.Sprite(area, GOAL_W, 8, "ARTWORK")
	B.Place(game.goalTop, (WIDTH - GOAL_W) / 2, 0, area)
	game.goalBottom = B.Sprite(area, GOAL_W, 8, "ARTWORK")
	B.Place(game.goalBottom, (WIDTH - GOAL_W) / 2, HEIGHT - 8, area)
	local function Mallet()
		local m = {}
		m.body = B.Sprite(area, MALLET_R * 2, MALLET_R * 2, "ARTWORK")
		m.ring = B.Sprite(area, MALLET_R * 2 + 6, MALLET_R * 2 + 6, "OVERLAY")
		return m
	end
	game.youView, game.themView = Mallet(), Mallet()
	game.coin = B.Sprite(area, PUCK_R * 2, PUCK_R * 2, "OVERLAY")
	E:SetClientFile(game.coin, COIN, "Interface\\Icons\\INV_Misc_QuestionMark")
	game.coin:SetTexCoord(0.1, 0.9, 0.1, 0.9)
	game.tally = B.Label(area, E.tokens.size.hero, "title")
	game.tally:SetPoint("CENTER", area, "TOPLEFT", 40, -HEIGHT / 2)
	game.tally:SetAlpha(0.5)
	game.fx = B.Effects(area)
	return game
end

function Hockey:Serve(toYou)
	self.puck = { x = WIDTH / 2, y = HEIGHT / 2 + (toYou and 60 or -60), vx = 0, vy = 0 }
	self.you = self.you or {}
	self.you.x, self.you.y, self.you.vx, self.you.vy = WIDTH / 2, HEIGHT - 70, 0, 0
	self.them = { x = WIDTH / 2, y = 70, vx = 0, vy = 0 }
	self.wait = 0.8
end

function Hockey:Start()
	self.held = {}
	self.goals, self.against = 0, 0
	self.useKeys = nil
	self:Serve(true)
	self.host.Score(0)
	self:Draw()
end

function Hockey:Key(key)
	if MOVE[key] then
		self.held[key] = true
		self.useKeys = true
		return true
	end
	return false
end

function Hockey:KeyUp(key)
	self.held[key] = nil
end

local function Clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

-- Moves a striker toward a point, no faster than `speed`, inside its half.
local function Steer(m, tx, ty, speed, dt, top)
	local dx, dy = tx - m.x, ty - m.y
	local dist = math.sqrt(dx * dx + dy * dy)
	local step = speed * dt
	local nx, ny
	if dist <= step or dist == 0 then
		nx, ny = tx, ty
	else
		nx, ny = m.x + dx / dist * step, m.y + dy / dist * step
	end
	nx = Clamp(nx, MALLET_R, WIDTH - MALLET_R)
	if top then
		ny = Clamp(ny, MALLET_R, HEIGHT / 2 - MALLET_R)
	else
		ny = Clamp(ny, HEIGHT / 2 + MALLET_R, HEIGHT - MALLET_R)
	end
	m.vx, m.vy = (nx - m.x) / math.max(dt, 0.001), (ny - m.y) / math.max(dt, 0.001)
	m.x, m.y = nx, ny
end

-- A striker hits the puck: the puck leaves along the line between them,
-- with the striker's own speed added.
function Hockey:Hit(m)
	local p = self.puck
	local dx, dy = p.x - m.x, p.y - m.y
	local dist = math.sqrt(dx * dx + dy * dy)
	local reach = PUCK_R + MALLET_R
	if dist >= reach or dist == 0 then return end
	local nx, ny = dx / dist, dy / dist
	p.x, p.y = m.x + nx * reach, m.y + ny * reach
	local rel = (p.vx - m.vx) * nx + (p.vy - m.vy) * ny
	if rel < 0 then
		p.vx = p.vx - 1.9 * rel * nx
		p.vy = p.vy - 1.9 * rel * ny
	end
	p.vx, p.vy = p.vx + m.vx * 0.35, p.vy + m.vy * 0.35
	local speed = math.sqrt(p.vx * p.vx + p.vy * p.vy)
	if speed > MAX_SPEED then
		p.vx, p.vy = p.vx / speed * MAX_SPEED, p.vy / speed * MAX_SPEED
	end
	self.host.Sound("turn")
	self.fx:Sparks(p.x - nx * PUCK_R, p.y - ny * PUCK_R, self.host.Color("gold"), 5, 90)
end

function Hockey:Goal(mine)
	local y = mine and 10 or HEIGHT - 10
	local color = self.host.Color(mine and "good" or "bad")
	self.fx:Burst(WIDTH / 2, y, color, GOAL_W * 1.4, 0.7)
	self.fx:Sparks(WIDTH / 2, y, color, 14, 160)
	if mine then
		self.goals = self.goals + 1
		self.host.Score(self.goals)
		self.host.Sound("point")
	else
		self.against = self.against + 1
		self.host.Sound("over")
	end
	self.fx:Float(WIDTH / 2, HEIGHT / 2, ("%d - %d"):format(self.goals, self.against), color, E.tokens.size.display)
	if self.goals >= WIN or self.against >= WIN then
		self:Draw()
		self.host.Over(self.goals >= WIN)
		return
	end
	self:Serve(mine)
end

function Hockey:Update(dt)
	self.fx:Update(dt)
	local pace = self.host.Pace()
	-- Your striker: the keys, or the mouse.
	local you = self.you
	local tx, ty = you.x, you.y
	local kx, ky = 0, 0
	for key in pairs(self.held) do
		kx, ky = kx + MOVE[key][1], ky + MOVE[key][2]
	end
	if kx ~= 0 or ky ~= 0 then
		tx, ty = you.x + kx * KEY_SPEED * dt, you.y + ky * KEY_SPEED * dt
	elseif not self.useKeys then
		local cx, cy = self.host.Cursor()
		if cx and cy then tx, ty = cx, cy end
	end
	Steer(you, tx, ty, 1400, dt, false)
	-- The computer: to the puck when it is in its half, else home.
	local p, them, mode = self.puck, self.them, self.mode
	local hx, hy
	if p.y < HEIGHT / 2 + 30 then
		hx = p.x + (WIDTH / 2 - p.x) * (1 - mode.aim) * 0.3
		hy = p.y - PUCK_R
	else
		hx, hy = WIDTH / 2 + (p.x - WIDTH / 2) * 0.4, 50
	end
	Steer(them, hx, hy, mode.reach * pace, dt, true)
	if self.wait then
		self.wait = self.wait - dt
		if self.wait <= 0 then self.wait = nil end
		self:Draw()
		return
	end
	-- The puck.
	local keep = FRICTION ^ dt
	p.vx, p.vy = p.vx * keep, p.vy * keep
	local steps = 3
	for _ = 1, steps do
		p.x = p.x + p.vx * dt / steps * pace
		p.y = p.y + p.vy * dt / steps * pace
		if p.x < PUCK_R then p.x, p.vx = PUCK_R, math.abs(p.vx) end
		if p.x > WIDTH - PUCK_R then p.x, p.vx = WIDTH - PUCK_R, -math.abs(p.vx) end
		local inGoal = math.abs(p.x - WIDTH / 2) < GOAL_W / 2 - PUCK_R / 2
		if p.y < PUCK_R then
			if inGoal then self:Goal(true) return end
			p.y, p.vy = PUCK_R, math.abs(p.vy)
		end
		if p.y > HEIGHT - PUCK_R then
			if inGoal then self:Goal(false) return end
			p.y, p.vy = HEIGHT - PUCK_R, -math.abs(p.vy)
		end
		self:Hit(you)
		self:Hit(them)
	end
	self:Draw()
end

function Hockey:Summary()
	if not self.goals then return nil end
	return E:Plural(self.goals, "%d goal to %d", "%d goals to %d"):format(self.goals, self.against)
end

function Hockey:Draw()
	local color, palette = self.host.Color, self.host.Palette()
	B.Fill(self.rink, palette[1], 0.1)
	B.Fill(self.line, color("secondary"), 0.35)
	B.Art(self.circle, "Ring", color("secondary"), 0.3)
	B.Tile(self.goalTop, color("good"), 0.8)
	B.Tile(self.goalBottom, color("bad"), 0.8)
	local function Mallet(view, m, tint)
		B.Tile(view.body, tint, 0.95)
		B.Place(view.body, m.x - MALLET_R, m.y - MALLET_R, self.host.area)
		B.Art(view.ring, "Ring", color("body"), 0.55)
		B.Place(view.ring, m.x - MALLET_R - 3, m.y - MALLET_R - 3, self.host.area)
	end
	Mallet(self.youView, self.you, color("accent"))
	Mallet(self.themView, self.them, palette[6])
	local p = self.puck
	B.Place(self.coin, p.x - PUCK_R, p.y - PUCK_R, self.host.area)
	self.tally:SetText(("%d\n\n%d"):format(self.against, self.goals))
end

M:RegisterGame({
	key = "hockey", order = 17, group = "arcade",
	title = "Air Hockey", desc = "Strike a gold coin into the far goal; first to seven wins.",
	controls = Key("Mouse or arrow keys: move your striker. P: pause."),
	icon = COIN,
	modes = MODES,
	width = WIDTH, height = HEIGHT,
	New = New,
})
