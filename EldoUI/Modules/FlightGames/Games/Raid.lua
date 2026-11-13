-- EldoUI Flight Games: Gryphon Raid. A flock of wild beasts sweeps over
-- the sky, a little lower at every turn. Fly your gryphon along the bottom
-- and shoot them down before they reach you; their fireballs cost one of
-- three lives. Each cleared flock brings a faster one.
-- Written from scratch for EldoUI; your gryphon is the game's own model and
-- the flock wears the game's own icons.
local _, E = ...
local M = E.FlightGames
local Key = E.Key
local L = E.L
local B = M.Board

local WIDTH, HEIGHT = 460, 420
local COLS, ROWS = 8, 4
local SIZE, GAP_X, GAP_Y = 30, 18, 14
local PLAYER_Y, PLAYER_W = HEIGHT - 52, 40
local SPEED = 230               -- your gryphon, units a second
local SHOT_SPEED, DROP_SPEED = 520, 210
local COOLDOWN = 0.35
local LIVES = 3
local ROW_ICONS = {
	"Interface\\Icons\\Ability_Hunter_Pet_WindSerpent",
	"Interface\\Icons\\Ability_Hunter_Pet_Vulture",
	"Interface\\Icons\\Ability_Hunter_Pet_Owl",
	"Interface\\Icons\\Ability_Hunter_Pet_Bat",
}
local ROW_POINTS = { 40, 30, 20, 10 }
local GRYPHON = "Interface\\Icons\\Ability_Mount_Gryphon_01"

local Raid = {}
Raid.__index = Raid
-- What a saved game keeps (the board, the score and the timers).
Raid.saveKeys = { "alive", "ox", "oy", "dir", "shots", "drops", "px", "lives", "score", "wave", "cool", "hurt", "fireIn" }

local function New(host)
	local game = setmetatable({ host = host, held = {}, shotViews = {}, dropViews = {} }, Raid)
	local area = host.area
	game.sky = B.Sprite(area, WIDTH, HEIGHT, "BACKGROUND")
	B.Place(game.sky, 0, 0, area)
	game.ground = B.Sprite(area, WIDTH, 4, "BORDER")
	B.Place(game.ground, 0, HEIGHT - 8, area)
	game.foes = {}
	for r = 1, ROWS do
		for c = 1, COLS do
			local foe = {}
			foe.back = B.Sprite(area, SIZE + 4, SIZE + 4, "BORDER")
			foe.icon = B.Sprite(area, SIZE, SIZE, "ARTWORK")
			E:SetClientFile(foe.icon, ROW_ICONS[r], "Interface\\Icons\\INV_Misc_QuestionMark")
			E:TrimIcon(foe.icon)
			game.foes[(r - 1) * COLS + c] = foe
		end
	end
	game.gryphon = B.Actor(area, PLAYER_W, B.DISPLAY.gryphon, GRYPHON, { scale = 2.2, facing = math.pi, animation = B.ANIM.fly })
	game.fx = B.Effects(area)
	game.hearts = {}
	for i = 1, LIVES do
		local heart = B.Sprite(area, 16, 16, "OVERLAY")
		B.Place(heart, 8 + (i - 1) * 20, 8, area)
		game.hearts[i] = heart
	end
	game.waveText = B.Label(area, E.tokens.size.small, "secondary", "RIGHT")
	game.waveText:SetPoint("TOPRIGHT", area, "TOPLEFT", WIDTH - 8, -10)
	return game
end

function Raid:NewWave()
	self.alive = {}
	for i = 1, ROWS * COLS do self.alive[i] = true end
	self.ox, self.oy, self.dir = 30, 40, 1
	self.shots, self.drops = {}, {}
	self.fireIn = 1.2
end

function Raid:Start()
	self.held = {}
	self.lives, self.score, self.wave = LIVES, 0, 1
	self.px = WIDTH / 2
	self.cool, self.hurt = 0, nil
	self:NewWave()
	self.host.Score(0)
	self:Draw()
end

function Raid:Key(key)
	if key == "LEFT" or key == "A" or key == "RIGHT" or key == "D" then
		self.held[key] = true
		return true
	elseif key == "SPACE" or key == "UP" or key == "W" then
		self:Fire()
		return true
	end
	return false
end

function Raid:KeyUp(key)
	self.held[key] = nil
end

function Raid:Press(button)
	if button == "LeftButton" then self:Fire() end
end

function Raid:Fire()
	if self.cool > 0 or self.hurt then return end
	self.cool = COOLDOWN
	self.shots[#self.shots + 1] = { x = self.px, y = PLAYER_Y - 6 }
	self.host.Sound("turn")
end

function Raid:FoeBox(i)
	local r, c = math.floor((i - 1) / COLS) + 1, (i - 1) % COLS + 1
	return self.ox + (c - 1) * (SIZE + GAP_X), self.oy + (r - 1) * (SIZE + GAP_Y), r, c
end

function Raid:Left()
	local n = 0
	for i = 1, ROWS * COLS do if self.alive[i] then n = n + 1 end end
	return n
end

function Raid:Hurt()
	self.fx:Burst(self.px, PLAYER_Y + 10, self.host.Color("bad"), 70)
	self.fx:Sparks(self.px, PLAYER_Y + 10, self.host.Color("bad"), 12)
	self.host.Sound("over")
	self.lives = self.lives - 1
	self.drops = {}
	if self.lives <= 0 then
		self:Draw()
		self.host.Over(false)
		return true
	end
	self.hurt = 1.2
	return false
end

function Raid:Update(dt)
	self.fx:Update(dt)
	local pace = self.host.Pace()
	self.cool = math.max(0, self.cool - dt)
	if self.hurt then
		self.hurt = self.hurt - dt
		if self.hurt <= 0 then self.hurt = nil end
	end
	local move = 0
	if self.held.LEFT or self.held.A then move = move - 1 end
	if self.held.RIGHT or self.held.D then move = move + 1 end
	-- The mouse steers only once it moves inside the play area; a still
	-- pointer leaves the keys in charge.
	if move == 0 then
		local cx, cy = self.host.Cursor()
		if cx and cy and cx >= 0 and cx <= WIDTH and cy >= 0 and cy <= HEIGHT and self.mouse and cx ~= self.mouse then
			self.goal = cx
		end
		self.mouse = cx
		if self.goal and math.abs(self.goal - self.px) > 4 then
			move = self.goal > self.px and 1 or -1
		else
			self.goal = nil
		end
	else
		self.goal = nil
	end
	self.px = math.max(PLAYER_W / 2, math.min(WIDTH - PLAYER_W / 2, self.px + move * SPEED * dt))
	-- The flock: across, and a step down at each edge.
	local left = self:Left()
	local speed = (24 + (ROWS * COLS - left) * 2.2 + (self.wave - 1) * 10) * pace
	self.ox = self.ox + self.dir * speed * dt
	local minX, maxX, maxY = WIDTH, 0, 0
	for i = 1, ROWS * COLS do
		if self.alive[i] then
			local x, y = self:FoeBox(i)
			minX, maxX, maxY = math.min(minX, x), math.max(maxX, x + SIZE), math.max(maxY, y + SIZE)
		end
	end
	if (self.dir > 0 and maxX >= WIDTH - 8) or (self.dir < 0 and minX <= 8) then
		self.dir = -self.dir
		self.oy = self.oy + 16
	end
	if maxY >= PLAYER_Y - 4 then
		self.lives = 1
		self:Hurt()
		return
	end
	-- Your shots.
	local keep = {}
	for _, shot in ipairs(self.shots) do
		shot.y = shot.y - SHOT_SPEED * dt
		local hit = false
		for i = 1, ROWS * COLS do
			if self.alive[i] then
				local x, y, r = self:FoeBox(i)
				if shot.x > x - 2 and shot.x < x + SIZE + 2 and shot.y > y and shot.y < y + SIZE then
					self.alive[i] = false
					hit = true
					local points = ROW_POINTS[r] * self.wave
					self.score = self.score + points
					self.host.Score(self.score)
					local color = self.host.Palette()[r]
					self.fx:Burst(x + SIZE / 2, y + SIZE / 2, color, SIZE * 1.8)
					self.fx:Sparks(x + SIZE / 2, y + SIZE / 2, color, 6)
					self.fx:Float(x + SIZE / 2, y, "+" .. points, self.host.Color("gold"), E.tokens.size.small)
					self.host.Sound("point")
					break
				end
			end
		end
		if not hit and shot.y > -10 then keep[#keep + 1] = shot end
	end
	self.shots = keep
	if self:Left() == 0 then
		self.wave = self.wave + 1
		self.fx:Float(WIDTH / 2, HEIGHT / 2, L["Wave %d"]:format(self.wave), self.host.Color("good"), E.tokens.size.display)
		self:NewWave()
		self:Draw()
		return
	end
	-- Their fireballs, from the lowest beast of a column.
	self.fireIn = self.fireIn - dt * pace
	if self.fireIn <= 0 then
		self.fireIn = math.max(0.35, 1.3 - self.wave * 0.12) * (0.6 + self.host.Random(80) / 100)
		local columns = {}
		for c = 1, COLS do
			for r = ROWS, 1, -1 do
				local i = (r - 1) * COLS + c
				if self.alive[i] then
					columns[#columns + 1] = i
					break
				end
			end
		end
		if #columns > 0 then
			local x, y = self:FoeBox(columns[self.host.Random(#columns)])
			self.drops[#self.drops + 1] = { x = x + SIZE / 2, y = y + SIZE }
		end
	end
	keep = {}
	for _, drop in ipairs(self.drops) do
		drop.y = drop.y + DROP_SPEED * pace * dt
		if not self.hurt and math.abs(drop.x - self.px) < PLAYER_W / 2 - 4 and drop.y > PLAYER_Y and drop.y < PLAYER_Y + 30 then
			if self:Hurt() then return end
			keep = {}
			break
		elseif drop.y < HEIGHT then
			keep[#keep + 1] = drop
		end
	end
	self.drops = keep
	self:Draw()
end

function Raid:Summary()
	return L["Reached wave %d"]:format(self.wave or 1)
end

local function Dot(views, i, parent, size)
	local dot = views[i]
	if not dot then
		dot = B.Dot(parent, size, nil, "OVERLAY")
		views[i] = dot
	end
	dot:Show()
	return dot
end

function Raid:Draw()
	local area, color, palette = self.host.area, self.host.Color, self.host.Palette()
	B.Fill(self.sky, palette[1], 0.08)
	B.Fill(self.ground, color("secondary"), 0.4)
	for i, foe in ipairs(self.foes) do
		local on = self.alive[i]
		foe.back:SetShown(on)
		foe.icon:SetShown(on)
		if on then
			local x, y, r = self:FoeBox(i)
			B.Tile(foe.back, palette[r], 0.8)
			B.Place(foe.back, x - 2, y - 2, area)
			B.Place(foe.icon, x, y, area)
		end
	end
	self.gryphon:Place(self.px - PLAYER_W / 2, PLAYER_Y - 6)
	self.gryphon:SetAlpha(self.hurt and (math.floor(self.hurt * 8) % 2 == 0 and 0.3 or 0.8) or 1)
	local gold, bad = color("gold"), color("bad")
	for i, shot in ipairs(self.shots) do
		local dot = Dot(self.shotViews, i, area, 7)
		dot:SetVertexColor(gold[1], gold[2], gold[3])
		B.Place(dot, shot.x - 3.5, shot.y - 3.5, area)
	end
	for i = #self.shots + 1, #self.shotViews do self.shotViews[i]:Hide() end
	for i, drop in ipairs(self.drops) do
		local dot = Dot(self.dropViews, i, area, 9)
		dot:SetVertexColor(bad[1], bad[2], bad[3])
		B.Place(dot, drop.x - 4.5, drop.y - 4.5, area)
	end
	for i = #self.drops + 1, #self.dropViews do self.dropViews[i]:Hide() end
	for i, heart in ipairs(self.hearts) do
		B.Art(heart, "Heart", i <= self.lives and bad or color("dim"), i <= self.lives and 1 or 0.4)
	end
	self.waveText:SetText(L["Wave %d"]:format(self.wave))
end

M:RegisterGame({
	key = "raid", order = 25, group = "arcade",
	title = "Gryphon Raid", desc = "Shoot down the sweeping flock before it reaches your gryphon.",
	controls = Key("Left and right or the mouse: fly. Space, Up or a click: shoot. P: pause."),
	icon = GRYPHON,
	width = WIDTH, height = HEIGHT,
	New = New,
})
