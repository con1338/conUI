-- EldoUI Flight Games: Gryphon Glide. Keep a gryphon in the air: each
-- flap lifts it, and between flaps it sinks. Fly through the gaps between
-- the towers; each tower you pass is a point, and touching a tower, the
-- ground or the sky ends the flight.
-- Written from scratch for EldoUI; the gryphon is the game's own model
-- (an icon when models are off).
local _, E = ...
local M = E.FlightGames
local Key = E.Key
local B = M.Board

local WIDTH, HEIGHT = 440, 320
local SIZE = 30              -- the gryphon's box
local X = 90                 -- where the gryphon flies
local GRAVITY, FLAP = 900, -300
local TOWER_W, GAP = 46, 112
local SPEED, EVERY = 130, 1.55
local ICON = "Interface\\Icons\\Ability_Mount_Gryphon_01"

local Glide = {}
Glide.__index = Glide

local function New(host)
	local game = setmetatable({ host = host, towers = {}, pool = {} }, Glide)
	local area = host.area
	game.ground = B.Sprite(area, WIDTH, 6, "BORDER")
	B.Place(game.ground, 0, HEIGHT - 6, area)
	-- An actor, so the Creature models option switches it at once.
	game.gryphon = B.Actor(area, SIZE, B.DISPLAY.gryphon, ICON, { scale = 2.4, facing = math.pi / 2, animation = B.ANIM.fly })
	return game
end

function Glide:Tower()
	local tower = table.remove(self.pool)
	if not tower then
		tower = { top = B.Sprite(self.host.area, TOWER_W, 10), bottom = B.Sprite(self.host.area, TOWER_W, 10) }
	end
	local margin = 36
	tower.gapTop = self.host.Random(margin, HEIGHT - 6 - GAP - margin)
	tower.x = WIDTH
	tower.passed = false
	self.towers[#self.towers + 1] = tower
	return tower
end

function Glide:Start()
	for _, tower in ipairs(self.towers) do
		tower.top:Hide()
		tower.bottom:Hide()
		self.pool[#self.pool + 1] = tower
	end
	self.towers = {}
	self.y, self.vy = HEIGHT / 2 - SIZE / 2, 0
	self.score, self.since = 0, EVERY - 0.6
	self.host.Score(0)
	self:Draw()
end

function Glide:Flap()
	self.vy = FLAP
	self.host.Sound("turn")
end

function Glide:Key(key)
	if key == "SPACE" or key == "UP" or key == "W" then
		self:Flap()
		return true
	end
	return false
end

function Glide:Press(button)
	if button == "LeftButton" then self:Flap() end
end

local function Hits(ax, ay, aw, ah, bx, by, bw, bh)
	return ax < bx + bw and ax + aw > bx and ay < by + bh and ay + ah > by
end

function Glide:Update(dt)
	local pace = self.host.Pace()
	self.vy = self.vy + GRAVITY * dt
	self.y = self.y + self.vy * dt
	self.since = self.since + dt * pace
	if self.since >= EVERY then
		self.since = 0
		self:Tower()
	end
	local keep = {}
	local inset = 5 -- a little room so a graze is not a crash
	local bx, by, bs = X + inset, self.y + inset, SIZE - inset * 2
	local crashed = self.y < 0 or self.y + SIZE > HEIGHT - 6
	for _, tower in ipairs(self.towers) do
		tower.x = tower.x - SPEED * pace * dt
		if not tower.passed and tower.x + TOWER_W < X then
			tower.passed = true
			self.score = self.score + 1
			self.host.Score(self.score)
			self.host.Sound("point")
		end
		if Hits(bx, by, bs, bs, tower.x, 0, TOWER_W, tower.gapTop)
			or Hits(bx, by, bs, bs, tower.x, tower.gapTop + GAP, TOWER_W, HEIGHT) then
			crashed = true
		end
		if tower.x + TOWER_W > 0 then
			keep[#keep + 1] = tower
		else
			tower.top:Hide()
			tower.bottom:Hide()
			self.pool[#self.pool + 1] = tower
		end
	end
	self.towers = keep
	self:Draw()
	if crashed then self.host.Over(false) end
end

function Glide:Draw()
	local area = self.host.area
	local palette = self.host.Palette()
	B.Fill(self.ground, self.host.Color("secondary"), 0.6)
	for _, tower in ipairs(self.towers) do
		local color = palette[3]
		tower.top:SetSize(TOWER_W, math.max(1, tower.gapTop))
		B.Place(tower.top, tower.x, 0, area)
		B.Tile(tower.top, color, 0.85)
		tower.top:Show()
		local bottomY = tower.gapTop + GAP
		tower.bottom:SetSize(TOWER_W, math.max(1, HEIGHT - 6 - bottomY))
		B.Place(tower.bottom, tower.x, bottomY, area)
		B.Tile(tower.bottom, color, 0.85)
		tower.bottom:Show()
	end
	self.gryphon:Place(X, self.y or HEIGHT / 2)
	self.gryphon:SetShown(true)
end

-- A saved flight: the gryphon, the towers in the air and the score.
function Glide:Save()
	local towers = {}
	for i, tower in ipairs(self.towers) do towers[i] = { x = tower.x, gapTop = tower.gapTop, passed = tower.passed } end
	return { y = self.y, vy = self.vy, score = self.score, since = self.since, towers = towers }
end

function Glide:Load(data)
	if type(data.towers) ~= "table" then return false end
	self:Start()
	self.y, self.vy = tonumber(data.y) or self.y, tonumber(data.vy) or 0
	self.score, self.since = tonumber(data.score) or 0, tonumber(data.since) or 0
	for _, saved in ipairs(data.towers) do
		local tower = self:Tower()
		tower.x, tower.gapTop, tower.passed = tonumber(saved.x) or tower.x, tonumber(saved.gapTop) or tower.gapTop, saved.passed and true or false
	end
	self:Draw()
	return true
end

M:RegisterGame({
	key = "glide", order = 30, group = "arcade",
	title = "Gryphon Glide", desc = "Flap through the gaps between the towers.",
	controls = Key("Space, Up or a click: flap. P: pause."),
	icon = ICON,
	width = WIDTH, height = HEIGHT,
	New = New,
})
