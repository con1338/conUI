-- EldoUI Flight Games: Kodo Run. A kodo charges across the Barrens: jump
-- the cacti and the rocks, duck under the vultures and pick up the gold
-- on the way. The run gets faster the farther it goes; one hit ends it.
-- Distance and gold make the score.
-- Written from scratch for EldoUI; the kodo is the game's own model (an
-- icon when models are off).
local _, E = ...
local M = E.FlightGames
local Key = E.Key
local L = E.L
local B = M.Board

local WIDTH, HEIGHT = 500, 280
local GROUND = 232            -- the top of the ground
local KODO, X = 46, 60        -- the kodo's box and where it runs
local STAND_H, DUCK_H = 40, 22
local GRAVITY, JUMP, DIVE = 1900, 640, 700
local START_SPEED, TOP_SPEED, SPEED_UP = 230, 520, 0.04
local DUCK_MIN = 0.45         -- a duck by a click lasts this long
local GOLD = 25               -- points for a piece of gold
local ICON = "Interface\\Icons\\Ability_Mount_Kodo_01"
local VULTURE = "Interface\\Icons\\Ability_Hunter_Pet_Vulture"
local COIN = "Interface\\Icons\\INV_Misc_Coin_01"
-- What stands in the way: its box, and where it stands.
local KINDS = {
	cactus = { w = 20, h = 38 },
	rocks = { w = 36, h = 22 },
	vulture = { w = 34, h = 24, air = 30 },  -- at head height: duck under it
}

local Run = {}
Run.__index = Run
-- What a saved run keeps.
Run.saveKeys = { "y", "vy", "speed", "dist", "gold", "obs", "coins", "next", "coinNext", "hills", "duck", "duckTime" }

local function New(host)
	local game = setmetatable({ host = host, views = {}, coinViews = {}, hillViews = {} }, Run)
	local area = host.area
	game.ground = B.Sprite(area, WIDTH, HEIGHT - GROUND, "BORDER")
	B.Place(game.ground, 0, GROUND, area)
	game.edge = B.Sprite(area, WIDTH, 3, "BORDER")
	B.Place(game.edge, 0, GROUND, area)
	game.kodo = B.Actor(area, KODO, B.DISPLAY.kodo, ICON, { facing = math.pi / 2, animation = B.ANIM.run, scale = 2.2 })
	game.shadow = B.Dot(area, KODO, nil, "BORDER")
	game.tally = B.Label(area, E.tokens.size.cardTitle, "body", "LEFT")
	game.tally:SetPoint("TOPLEFT", area, "TOPLEFT", 8, -8)
	game.fx = B.Effects(area)
	return game
end

function Run:Start()
	self.y, self.vy = GROUND - STAND_H, 0
	self.speed, self.dist, self.gold = START_SPEED, 0, 0
	self.obs, self.coins = {}, {}
	self.next, self.coinNext = 420, 260
	self.hills = {}
	for i = 1, 5 do
		self.hills[i] = { x = (i - 1) * 130 + self.host.Random(0, 40), h = self.host.Random(26, 70), w = self.host.Random(70, 120) }
	end
	self.duck, self.duckTime, self.held = false, 0, false
	self.fx:Clear()
	self.host.Score(0)
	self:Draw()
end

-- A run saved while ducking under a vulture resumes ducking, so the
-- restored position stays safe; the held key does not carry over, so the
-- kodo rises after a short duck unless the key is pressed again.
function Run:Loaded()
	self.held = false
	self.duck = self.duck == true
	local left = tonumber(self.duckTime) or 0
	self.duckTime = self.duck and math.max(left, DUCK_MIN) or 0
end

function Run:OnGround()
	return self.y >= GROUND - STAND_H - 0.5
end

function Run:Jump()
	if not self:OnGround() then return end
	self.duck, self.held, self.duckTime = false, false, 0
	self.vy = -JUMP
	self.host.Sound("turn")
end

-- Ducks while held (or for a moment after a click); in the air it dives.
function Run:Duck(held)
	if not self:OnGround() then
		self.vy = math.max(self.vy, DIVE)
		return
	end
	self.duck = true
	self.held = held and true or false
	self.duckTime = DUCK_MIN
end

function Run:Key(key)
	if key == "SPACE" or key == "UP" or key == "W" then
		self:Jump()
		return true
	elseif key == "DOWN" or key == "S" then
		self:Duck(true)
		return true
	end
	return false
end

function Run:KeyUp(key)
	if key == "DOWN" or key == "S" then self.held = false end
end

function Run:Press(button)
	if button == "LeftButton" then self:Jump() elseif button == "RightButton" then self:Duck(false) end
end

function Run:Score()
	return math.floor(self.dist / 10) + self.gold * GOLD
end

-- The kodo's box: lower and flatter while it ducks.
function Run:Box()
	local h = self.duck and DUCK_H or STAND_H
	local top = self.duck and GROUND - DUCK_H or self.y
	return X + 8, top + 2, KODO - 16, h - 2
end

local function Hits(ax, ay, aw, ah, bx, by, bw, bh)
	return ax < bx + bw and ax + aw > bx and ay < by + bh and ay + ah > by
end
Run.Hits = Hits

-- Something new comes in from the right edge.
function Run:Spawn()
	local roll = self.host.Random(1, 10)
	local kind = roll <= 4 and "cactus" or roll <= 7 and "rocks" or "vulture"
	if kind == "vulture" and self.dist < 1500 then kind = "rocks" end
	local size = KINDS[kind]
	local y = GROUND - size.h - (size.air or 0)
	self.obs[#self.obs + 1] = { kind = kind, x = WIDTH + 4, y = y, w = size.w, h = size.h }
end

function Run:Update(dt)
	self.fx:Update(dt)
	local pace = self.host.Pace()
	local move = self.speed * pace * dt
	self.dist = self.dist + move
	self.speed = math.min(TOP_SPEED, START_SPEED + self.dist * SPEED_UP)
	-- The jump.
	local was = self:OnGround()
	self.vy = self.vy + GRAVITY * dt
	self.y = self.y + self.vy * dt
	if self.y >= GROUND - STAND_H then
		self.y, self.vy = GROUND - STAND_H, 0
		if not was then self.fx:Burst(X + KODO / 2, GROUND, self.host.Color("secondary"), 50, 0.35) end
	end
	if self.duck and not self.held then
		self.duckTime = self.duckTime - dt
		if self.duckTime <= 0 then self.duck = false end
	end
	-- What comes next.
	self.next = self.next - move
	if self.next <= 0 then
		self:Spawn()
		local gap = self.host.Random(240, 400) * math.sqrt(self.speed / START_SPEED)
		self.next = gap
	end
	self.coinNext = self.coinNext - move
	if self.coinNext <= 0 then
		local high = self.host.Random(1, 3) == 1
		self.coins[#self.coins + 1] = { x = WIDTH + 4, y = high and GROUND - 128 or GROUND - 34 }
		self.coinNext = self.host.Random(180, 380)
	end
	-- The hills drift slowly behind.
	for _, hill in ipairs(self.hills) do
		hill.x = hill.x - move * 0.25
		if hill.x + hill.w < 0 then
			hill.x = WIDTH + self.host.Random(0, 60)
			hill.h, hill.w = self.host.Random(26, 70), self.host.Random(70, 120)
		end
	end
	local bx, by, bw, bh = self:Box()
	local crashed = false
	local keep = {}
	for _, ob in ipairs(self.obs) do
		ob.x = ob.x - move * (ob.kind == "vulture" and 1.15 or 1)
		if Hits(bx, by, bw, bh, ob.x + 3, ob.y + 3, ob.w - 6, ob.h - 6) then crashed = true end
		if ob.x + ob.w > 0 then keep[#keep + 1] = ob end
	end
	self.obs = keep
	keep = {}
	for _, coin in ipairs(self.coins) do
		coin.x = coin.x - move
		if Hits(bx, by, bw, bh, coin.x, coin.y, 18, 18) then
			self.gold = self.gold + 1
			self.fx:Sparks(coin.x + 9, coin.y + 9, self.host.Color("gold"), 8, 90)
			self.fx:Float(coin.x + 9, coin.y - 6, "+" .. GOLD, self.host.Color("gold"), E.tokens.size.small)
			self.host.Sound("point")
		elseif coin.x + 18 > 0 then
			keep[#keep + 1] = coin
		end
	end
	self.coins = keep
	local score = self:Score()
	if score ~= self.shown then
		self.shown = score
		self.host.Score(score)
	end
	self:Draw()
	if crashed then
		self.fx:Burst(X + KODO / 2, by + bh / 2, self.host.Palette()[6], 90, 0.5)
		self.host.Over(false)
	end
end

local function View(game, index)
	local view = game.views[index]
	if view then return view end
	local area = game.host.area
	view = {
		body = B.Sprite(area, 10, 10, "ARTWORK"),
		arm = B.Sprite(area, 10, 10, "ARTWORK"),
		icon = B.Sprite(area, 10, 10, "ARTWORK"),
	}
	E:SetClientFile(view.icon, VULTURE, "Interface\\Icons\\INV_Misc_QuestionMark")
	E:TrimIcon(view.icon)
	game.views[index] = view
	return view
end

function Run:Draw()
	local area = self.host.area
	local palette, color = self.host.Palette(), self.host.Color
	local bronze = E.tokens.palette.bronze
	B.Fill(self.ground, bronze, 0.28)
	B.Fill(self.edge, bronze, 0.7)
	-- The hills on the horizon.
	for i, hill in ipairs(self.hills or {}) do
		local tex = self.hillViews[i]
		if not tex then
			tex = B.Sprite(area, 10, 10, "BACKGROUND")
			self.hillViews[i] = tex
		end
		tex:SetSize(hill.w, hill.h)
		B.Place(tex, hill.x, GROUND - hill.h + 6, area)
		B.Tile(tex, bronze, 0.22)
		tex:Show()
	end
	local t = (self.dist or 0) / 40
	for i, ob in ipairs(self.obs or {}) do
		local view = View(self, i)
		view.body:Hide()
		view.arm:Hide()
		view.icon:Hide()
		if ob.kind == "vulture" then
			view.icon:SetSize(ob.w, ob.w)
			B.Place(view.icon, ob.x, ob.y - (ob.w - ob.h) / 2 + math.sin(t + i) * 3, area)
			view.icon:Show()
		elseif ob.kind == "cactus" then
			view.body:SetSize(ob.w - 6, ob.h)
			B.Place(view.body, ob.x + 3, ob.y, area)
			B.Tile(view.body, palette[3], 1)
			view.arm:SetSize(10, 16)
			B.Place(view.arm, ob.x + (i % 2 == 0 and ob.w - 6 or -4), ob.y + 8, area)
			B.Tile(view.arm, palette[3], 1)
			view.body:Show()
			view.arm:Show()
		else
			view.body:SetSize(ob.w, ob.h)
			B.Place(view.body, ob.x, ob.y, area)
			B.Tile(view.body, color("secondary"), 0.95)
			view.body:Show()
		end
	end
	for i = #(self.obs or {}) + 1, #self.views do
		local view = self.views[i]
		view.body:Hide()
		view.arm:Hide()
		view.icon:Hide()
	end
	for i, coin in ipairs(self.coins or {}) do
		local tex = self.coinViews[i]
		if not tex then
			tex = B.Sprite(area, 18, 18, "ARTWORK")
			E:SetClientFile(tex, COIN, "Interface\\Icons\\INV_Misc_QuestionMark")
			E:TrimIcon(tex)
			self.coinViews[i] = tex
		end
		B.Place(tex, coin.x, coin.y + math.sin(t * 1.5 + i) * 2, area)
		tex:Show()
	end
	for i = #(self.coins or {}) + 1, #self.coinViews do self.coinViews[i]:Hide() end
	-- The kodo, a little lower while it ducks.
	local y = self.y or GROUND - STAND_H
	local drop = self.duck and (STAND_H - DUCK_H) or 0
	self.kodo:Place(X, y - (KODO - STAND_H) + drop)
	self.kodo:SetShown(true)
	self.shadow:SetSize(KODO - 6, 8)
	B.Place(self.shadow, X + 3, GROUND - 4, area)
	local shade = E.tokens.shade
	self.shadow:SetVertexColor(shade[1], shade[2], shade[3], 0.5 * (1 - math.min(1, (GROUND - STAND_H - y) / 160)))
	self.tally:SetText(L["Distance %d, gold %d"]:format(math.floor((self.dist or 0) / 10), self.gold or 0))
end

function Run:Summary()
	if not self.dist then return nil end
	return L["Distance %d, gold %d"]:format(math.floor(self.dist / 10), self.gold or 0)
end

M:RegisterGame({
	key = "kodorun", order = 32, group = "arcade",
	title = "Kodo Run", desc = "Charge across the Barrens: jump, duck and grab the gold.",
	controls = Key("Space, Up or a click: jump. Down or right-click: duck. P: pause."),
	icon = ICON,
	width = WIDTH, height = HEIGHT,
	New = New,
})
