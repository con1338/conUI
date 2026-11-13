-- EldoUI Flight Games: Brick Breaker. Keep the ball in play with the
-- paddle and break every brick. Where the ball meets the paddle sets the
-- angle it flies off at. Three balls a game; a cleared wall brings a new
-- one, a little faster.
--
-- Points: 10 for a brick in the bottom row up to 60 in the top row.
-- Written from scratch for EldoUI.
local _, E = ...
local L = E.L
local M = E.FlightGames
local Key = E.Key
local B = M.Board

local WIDTH, HEIGHT = 440, 360
local COLS, ROWS = 10, 6
local BRICK_W, BRICK_H, BRICK_GAP, TOP = 42, 14, 2, 40
local PADDLE_W, PADDLE_H, PADDLE_Y = 72, 10, HEIGHT - 26
local BALL = 10
local BALL_SPEED, KEY_SPEED = 250, 420
local LIVES = 3

local Breakout = {}
Breakout.__index = Breakout

local function New(host)
	local game = setmetatable({ host = host }, Breakout)
	local area = host.area
	game.bricks = {}
	for row = 1, ROWS do
		for col = 1, COLS do
			local tex = B.Sprite(area, BRICK_W - BRICK_GAP, BRICK_H - BRICK_GAP)
			B.Place(tex, 1 + (col - 1) * BRICK_W, TOP + (row - 1) * BRICK_H, area)
			game.bricks[#game.bricks + 1] = { tex = tex, col = col, row = row }
		end
	end
	game.paddle = B.Sprite(area, PADDLE_W, PADDLE_H, "OVERLAY")
	game.ball = B.Dot(area, BALL, nil, "OVERLAY")
	game.info = B.Label(area, E.tokens.size.label, "secondary", "LEFT")
	game.info:SetPoint("TOPLEFT", 4, -10)
	return game
end

function Breakout:Wall()
	for _, brick in ipairs(self.bricks) do brick.alive = true end
	self.left = #self.bricks
end

function Breakout:Serve()
	self.bx, self.by = self.px + PADDLE_W / 2 - BALL / 2, PADDLE_Y - BALL - 2
	self.held = true
	local angle = math.rad(self.host.Random(-35, 35))
	self.vx, self.vy = math.sin(angle), -math.cos(angle)
end

function Breakout:Start()
	self.score, self.lives, self.speed = 0, LIVES, BALL_SPEED
	self.px = WIDTH / 2 - PADDLE_W / 2
	self.keys = {}
	self.mouse = nil
	self:Wall()
	self:Serve()
	self.host.Score(0)
	self:Draw()
end

function Breakout:Launch()
	self.held = false
end

function Breakout:Key(key)
	if key == "LEFT" or key == "A" then
		self.keys.left = true
		self.mouse = false
	elseif key == "RIGHT" or key == "D" then
		self.keys.right = true
		self.mouse = false
	elseif key == "SPACE" or key == "UP" or key == "W" then
		self:Launch()
	else
		return false
	end
	return true
end

function Breakout:KeyUp(key)
	if key == "LEFT" or key == "A" then self.keys.left = nil end
	if key == "RIGHT" or key == "D" then self.keys.right = nil end
end

function Breakout:Press(button)
	if button == "LeftButton" then
		self.mouse = true
		self:Launch()
	end
end

function Breakout:Update(dt)
	-- The paddle follows the pointer over the board, or the keys held down
	-- (a key moves it until the key is let go).
	local area = self.host.area
	local dir = (self.keys.left and -1 or 0) + (self.keys.right and 1 or 0)
	if dir ~= 0 then
		self.px = self.px + dir * KEY_SPEED * dt
	elseif self.mouse ~= false and area:IsMouseOver() then
		local x = self.host.Cursor()
		self.px = x - PADDLE_W / 2
	end
	self.px = math.max(0, math.min(WIDTH - PADDLE_W, self.px))
	if self.held then
		self.bx = self.px + PADDLE_W / 2 - BALL / 2
		self:Draw()
		return
	end
	local speed = self.speed * self.host.Pace()
	-- Small steps so a fast ball never passes through a brick.
	local steps = math.max(1, math.ceil(speed * dt / 4))
	for _ = 1, steps do
		if self:Advance(speed * dt / steps) then break end
	end
	self:Draw()
end

-- Moves the ball one small step; true when the ball was lost.
function Breakout:Advance(dist)
	local nx, ny = self.bx + self.vx * dist, self.by + self.vy * dist
	if nx < 0 then nx, self.vx = 0, math.abs(self.vx) end
	if nx + BALL > WIDTH then nx, self.vx = WIDTH - BALL, -math.abs(self.vx) end
	if ny < 0 then ny, self.vy = 0, math.abs(self.vy) end
	-- The paddle: the angle comes from where the ball lands on it.
	if self.vy > 0 and ny + BALL >= PADDLE_Y and ny + BALL <= PADDLE_Y + PADDLE_H + 4
		and nx + BALL >= self.px and nx <= self.px + PADDLE_W then
		local hit = ((nx + BALL / 2) - (self.px + PADDLE_W / 2)) / (PADDLE_W / 2)
		local angle = math.rad(math.max(-1, math.min(1, hit)) * 60)
		self.vx, self.vy = math.sin(angle), -math.cos(angle)
		ny = PADDLE_Y - BALL
		self.host.Sound("turn")
	end
	for _, brick in ipairs(self.bricks) do
		if brick.alive then
			local x, y = 1 + (brick.col - 1) * BRICK_W, TOP + (brick.row - 1) * BRICK_H
			if nx < x + BRICK_W - BRICK_GAP and nx + BALL > x and ny < y + BRICK_H - BRICK_GAP and ny + BALL > y then
				brick.alive = false
				self.left = self.left - 1
				self.score = self.score + (ROWS - brick.row + 1) * 10
				self.host.Score(self.score)
				self.host.Sound("point")
				-- Bounce off the side it came through.
				local fromSide = (self.bx + BALL <= x) or (self.bx >= x + BRICK_W - BRICK_GAP)
				if fromSide then self.vx = -self.vx else self.vy = -self.vy end
				nx, ny = self.bx, self.by
				break
			end
		end
	end
	self.bx, self.by = nx, ny
	if self.left <= 0 then
		self.speed = self.speed * 1.1
		self:Wall()
		self:Serve()
		return true
	end
	if self.by > HEIGHT then
		self.lives = self.lives - 1
		if self.lives <= 0 then
			self:Draw()
			self.host.Over(false)
			return true
		end
		self:Serve()
		return true
	end
	return false
end

function Breakout:Draw()
	local palette = self.host.Palette()
	for _, brick in ipairs(self.bricks) do
		if brick.alive then
			B.Tile(brick.tex, palette[(brick.row - 1) % #palette + 1])
			brick.tex:Show()
		else
			brick.tex:Hide()
		end
	end
	local area = self.host.area
	B.Tile(self.paddle, self.host.Color("accent"))
	B.Place(self.paddle, self.px or 0, PADDLE_Y, area)
	local body = self.host.Color("body")
	self.ball:SetVertexColor(body[1], body[2], body[3])
	B.Place(self.ball, self.bx or 0, self.by or 0, area)
	self.info:SetText(L["Balls: %d"]:format(self.lives or LIVES))
end

-- A saved wall: which bricks stand, the paddle, the ball and the lives.
function Breakout:Save()
	local alive = {}
	for i, brick in ipairs(self.bricks) do alive[i] = brick.alive and true or false end
	return { alive = alive, score = self.score, lives = self.lives, speed = self.speed, px = self.px,
		bx = self.bx, by = self.by, vx = self.vx, vy = self.vy, held = self.held }
end

function Breakout:Load(data)
	if type(data.alive) ~= "table" then return false end
	self:Start()
	self.left = 0
	for i, brick in ipairs(self.bricks) do
		brick.alive = data.alive[i] and true or false
		if brick.alive then self.left = self.left + 1 end
	end
	for _, key in ipairs({ "score", "lives", "speed", "px", "bx", "by", "vx", "vy" }) do
		if tonumber(data[key]) then self[key] = tonumber(data[key]) end
	end
	self.held = data.held and true or false
	self:Draw()
	return true
end

M:RegisterGame({
	key = "breakout", order = 40, group = "arcade",
	title = "Brick Breaker", desc = "Bounce the ball off the paddle and break every brick.",
	controls = Key("Mouse or Left and Right: move. Space or a click: launch. P: pause."),
	icon = "Interface\\Icons\\INV_Hammer_Unique_Sulfuras",
	width = WIDTH, height = HEIGHT,
	New = New,
})
