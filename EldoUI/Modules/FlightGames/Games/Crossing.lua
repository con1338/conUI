-- EldoUI Flight Games: Murloc Crossing. Hop a murloc from the shore over
-- a road of kodos and boars, then over the river on drifting logs, into
-- one of the five nests on the far bank. Fill all five for the next, faster
-- level. A hit on the road, a fall in the river or a miss of the nests
-- costs one of three lives.
-- Written from scratch for EldoUI; the murloc, the kodos and the boars are
-- the game's own models (icons when models are off).
local _, E = ...
local M = E.FlightGames
local Key = E.Key
local L = E.L
local B = M.Board

local COLS, ROWS, CELL = 11, 11, 40
local HUD = 28
local WIDTH, HEIGHT = COLS * CELL, ROWS * CELL + HUD
local WRAP = COLS + 4          -- an object leaves one side and comes back
local LIVES = 3
local NESTS = { [2] = true, [4] = true, [6] = true, [8] = true, [10] = true }
local MURLOC = "Interface\\Icons\\INV_Misc_Head_Murloc_01"
local KODO = "Interface\\Icons\\Ability_Mount_Kodo_01"
local BOAR = "Interface\\Icons\\Ability_Hunter_Pet_Boar"
-- The lanes, top row first: logs on the river, creatures on the road.
-- speed is in cells a second (minus: to the left).
local LANES = {
	{ row = 2, kind = "log", speed = 1.2, objects = { { 0, 3 }, { 6, 3 }, { 11, 2 } } },
	{ row = 3, kind = "log", speed = -1.6, objects = { { 0, 2 }, { 5, 2 }, { 10, 2 } } },
	{ row = 4, kind = "log", speed = 0.9, objects = { { 0, 4 }, { 8, 4 } } },
	{ row = 5, kind = "log", speed = -1.3, objects = { { 1, 3 }, { 8, 3 } } },
	{ row = 7, kind = "kodo", speed = -0.9, objects = { { 0, 2 }, { 7, 2 } } },
	{ row = 8, kind = "boar", speed = 2.2, objects = { { 0, 1 }, { 5, 1 }, { 10, 1 } } },
	{ row = 9, kind = "kodo", speed = 1.1, objects = { { 2, 2 }, { 9, 2 } } },
	{ row = 10, kind = "boar", speed = -1.8, objects = { { 0, 1 }, { 6, 1 }, { 11, 1 } } },
}
local MOVES = {
	UP = { 0, -1 }, W = { 0, -1 }, DOWN = { 0, 1 }, S = { 0, 1 },
	LEFT = { -1, 0 }, A = { -1, 0 }, RIGHT = { 1, 0 }, D = { 1, 0 },
}

local Crossing = {}
Crossing.__index = Crossing
-- What a saved game keeps (the board, the score and the timers).
Crossing.saveKeys = { "px", "py", "lives", "score", "level", "homes", "shift", "furthest", "hurt" }

local function New(host)
	local game = setmetatable({ host = host }, Crossing)
	local area = host.area
	game.rows = {}
	for r = 1, ROWS do
		local tex = B.Sprite(area, WIDTH, CELL, "BACKGROUND")
		B.Place(tex, 0, (r - 1) * CELL, area)
		game.rows[r] = tex
	end
	game.nests = {}
	for col in pairs(NESTS) do
		local pad = B.Sprite(area, CELL - 6, CELL - 6, "BORDER")
		B.Place(pad, (col - 1) * CELL + 3, 3, area)
		local ring = B.Sprite(area, CELL - 2, CELL - 2, "ARTWORK")
		B.Place(ring, (col - 1) * CELL + 1, 1, area)
		local icon = B.Sprite(area, CELL - 14, CELL - 14, "OVERLAY")
		B.Place(icon, (col - 1) * CELL + 7, 7, area)
		E:SetClientFile(icon, MURLOC, "Interface\\Icons\\INV_Misc_QuestionMark")
		E:TrimIcon(icon)
		game.nests[col] = { pad = pad, ring = ring, icon = icon }
	end
	game.things = {}
	for li, lane in ipairs(LANES) do
		game.things[li] = {}
		for oi, object in ipairs(lane.objects) do
			local thing = {}
			if lane.kind == "log" then
				thing.slab = B.Slab(area, object[2] * CELL - 6, CELL - 10, "BORDER")
			else
				local display = lane.kind == "kodo" and B.DISPLAY.kodo or B.DISPLAY.boar
				local icon = lane.kind == "kodo" and KODO or BOAR
				thing.actor = B.Actor(area, CELL, display, icon, { scale = lane.kind == "kodo" and 1.7 or 1.3,
					facing = lane.speed > 0 and -math.pi / 2 or math.pi / 2, animation = B.ANIM.run })
			end
			game.things[li][oi] = thing
		end
	end
	game.murloc = B.Actor(area, CELL, B.DISPLAY.murloc, MURLOC, { scale = 1.4, facing = 0, animation = B.ANIM.stand })
	game.fx = B.Effects(area)
	game.hearts = {}
	for i = 1, LIVES do
		local heart = B.Sprite(area, 18, 18, "ARTWORK")
		B.Place(heart, 8 + (i - 1) * 22, ROWS * CELL + 6, area)
		game.hearts[i] = heart
	end
	game.levelText = B.Label(area, E.tokens.size.small, "secondary", "RIGHT")
	game.levelText:SetPoint("RIGHT", area, "TOPLEFT", WIDTH - 8, -(ROWS * CELL + 15))
	return game
end

function Crossing:Start()
	self.lives, self.score, self.level = LIVES, 0, 1
	self.homes, self.shift = {}, {}
	for i = 1, #LANES do self.shift[i] = 0 end
	self.hurt = nil
	self:Respawn()
	self.host.Score(0)
	self:Draw()
end

function Crossing:Respawn()
	self.px, self.py = math.ceil(COLS / 2), ROWS
	self.furthest = ROWS
end

function Crossing:Speed()
	return 1 + (self.level - 1) * 0.15
end

-- Where an object of a lane is now: its left edge in cells, from 0.
function Crossing:ObjectAt(li, oi)
	local object = LANES[li].objects[oi]
	return (object[1] + self.shift[li]) % WRAP - 2, object[2]
end

function Crossing:Lose()
	local x, y = (self.px - 0.5) * CELL, (self.py - 0.5) * CELL
	self.fx:Burst(x, y, self.host.Color("bad"), CELL * 1.6)
	self.fx:Sparks(x, y, self.host.Color("bad"), 10)
	self.host.Sound("over")
	self.lives = self.lives - 1
	self.hurt = 0.5
	if self.lives <= 0 then
		self:Draw()
		self.host.Over(false)
		return
	end
	self:Respawn()
end

function Crossing:Gain(points, x, y)
	self.score = self.score + points
	self.host.Score(self.score)
	self.fx:Float(x, y, "+" .. points, self.host.Color("good"))
end

function Crossing:Key(key)
	local move = MOVES[key]
	if not move then return false end
	if self.hurt then return true end
	local nx, ny = self.px + move[1], self.py + move[2]
	-- A hop up or down keeps the x a log carried the murloc to.
	if ny < 1 or ny > ROWS or (move[1] ~= 0 and (nx < 1 or nx > COLS)) then return true end
	self.px, self.py = nx, ny
	self.murloc:Face(move[1] == 1 and -math.pi / 2 or move[1] == -1 and math.pi / 2 or move[2] == 1 and math.pi or 0)
	self.host.Sound("turn")
	if ny < self.furthest then
		self.furthest = ny
		self:Gain(10, (nx - 0.5) * CELL, (ny - 0.5) * CELL)
	end
	if ny == 1 then
		local col = math.floor(nx + 0.5)
		if NESTS[col] and not self.homes[col] then
			self.homes[col] = true
			self.fx:Burst((col - 0.5) * CELL, CELL / 2, self.host.Color("good"), CELL * 2)
			self.fx:Sparks((col - 0.5) * CELL, CELL / 2, self.host.Color("good"), 12)
			self.host.Sound("point")
			self:Gain(50, (col - 0.5) * CELL, CELL)
			local full = true
			for c in pairs(NESTS) do if not self.homes[c] then full = false end end
			if full then
				self.level = self.level + 1
				self.homes = {}
				self:Gain(200, WIDTH / 2, ROWS * CELL / 2)
			end
			self:Respawn()
		else
			self:Lose()
		end
	end
	self:Draw()
	return true
end

function Crossing:Update(dt)
	self.fx:Update(dt)
	local pace = self.host.Pace() * self:Speed()
	for li, lane in ipairs(LANES) do
		self.shift[li] = (self.shift[li] + lane.speed * pace * dt) % WRAP
	end
	if self.hurt then
		self.hurt = self.hurt - dt
		if self.hurt <= 0 then self.hurt = nil end
		self:Draw()
		return
	end
	local row = self.py
	for li, lane in ipairs(LANES) do
		if lane.row == row then
			if lane.kind == "log" then
				local riding = false
				for oi in ipairs(lane.objects) do
					local left, len = self:ObjectAt(li, oi)
					local center = self.px - 0.5
					if center >= left - 0.1 and center <= left + len + 0.1 then riding = true end
				end
				if riding then
					self.px = self.px + lane.speed * pace * dt
					if self.px - 0.5 < 0 or self.px - 0.5 > COLS then self:Lose() end
				else
					self:Lose()
				end
			else
				for oi in ipairs(lane.objects) do
					local left, len = self:ObjectAt(li, oi)
					if self.px - 0.8 < left + len and self.px - 0.2 > left then
						self:Lose()
						break
					end
				end
			end
		end
	end
	-- Off a log onto the bank: the murloc lands on a whole cell.
	if row == 6 or row == ROWS then self.px = math.max(1, math.min(COLS, math.floor(self.px + 0.5))) end
	self:Draw()
end

function Crossing:Summary()
	return L["Reached level %d"]:format(self.level)
end

function Crossing:Draw()
	local palette, color = self.host.Palette(), self.host.Color
	for r = 1, ROWS do
		local tex = self.rows[r]
		if r == 1 then
			B.Fill(tex, palette[3], 0.35)
		elseif r <= 5 then
			B.Fill(tex, palette[7], r % 2 == 0 and 0.42 or 0.36)
		elseif r == 6 or r == ROWS then
			B.Fill(tex, palette[3], 0.22)
		else
			B.Fill(tex, color("dim"), r % 2 == 0 and 0.22 or 0.16)
		end
	end
	for col, nest in pairs(self.nests) do
		B.Tile(nest.pad, palette[3], 0.8)
		B.Art(nest.ring, "Ring", self.homes[col] and color("good") or color("secondary"), self.homes[col] and 0.9 or 0.35)
		nest.icon:SetShown(self.homes[col] and true or false)
	end
	for li, lane in ipairs(LANES) do
		for oi in ipairs(lane.objects) do
			local left, len = self:ObjectAt(li, oi)
			local thing = self.things[li][oi]
			local y = (lane.row - 1) * CELL
			local visible = left + len > -0.5 and left < COLS + 0.5
			if thing.slab then
				thing.slab:Paint(E.tokens.palette.bronze, 0.95)
				thing.slab:Place(left * CELL + 3, y + 5)
				thing.slab:SetShown(visible)
			else
				thing.actor:Place((left + (len - 1) / 2) * CELL, y)
				thing.actor:SetShown(visible)
			end
		end
	end
	self.murloc:Place((self.px - 1) * CELL, (self.py - 1) * CELL)
	self.murloc:SetAlpha(self.hurt and 0.4 or 1)
	for i, heart in ipairs(self.hearts) do
		B.Art(heart, "Heart", i <= self.lives and color("bad") or color("dim"), i <= self.lives and 1 or 0.4)
	end
	self.levelText:SetText(L["Level %d"]:format(self.level))
end

M:RegisterGame({
	key = "crossing", order = 15, group = "arcade",
	title = "Murloc Crossing", desc = "Hop a murloc over the road and the river into the five nests.",
	controls = Key("Arrow keys or WASD: hop. P: pause."),
	icon = MURLOC,
	width = WIDTH, height = HEIGHT,
	New = New,
})
