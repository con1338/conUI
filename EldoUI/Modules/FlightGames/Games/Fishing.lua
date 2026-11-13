-- EldoUI Flight Games: Fishing Reflex. Cast your line and watch the
-- float. A nibble only shivers it; when a fish really bites, the float
-- goes under with a splash, and you have a moment to strike. The quicker
-- the strike, the more the catch is worth, and a rarer fish counts more.
-- Ten casts a round.
-- Written from scratch for EldoUI; you are your own character on the shore.
local _, E = ...
local M = E.FlightGames
local Key = E.Key
local L = E.L
local B = M.Board

local WIDTH, HEIGHT = 480, 340
local SHORE_W = 110
local WATER_Y = 70
local CASTS = 10
local FLOAT = 16
-- How the fish run: share in a hundred, worth, and the quality color.
local FISH = {
	{ chance = 55, worth = 1, quality = 1 },
	{ chance = 27, worth = 2, quality = 2 },
	{ chance = 13, worth = 3, quality = 3 },
	{ chance = 5, worth = 5, quality = 4 },
}
local QUALITY = { { 1, 1, 1 }, { 0.12, 1, 0 }, { 0, 0.44, 0.87 }, { 0.64, 0.21, 0.93 } }
local CATCH = "Interface\\Icons\\Trade_Fishing"

local Fishing = {}
Fishing.__index = Fishing
-- What a saved game keeps (the board, the score and the timers).
Fishing.saveKeys = { "casts", "phase", "timer", "bob", "score", "caught", "window", "nibbles", "fish", "log", "ending" }

local function New(host)
	local game = setmetatable({ host = host }, Fishing)
	local area = host.area
	game.water = B.Sprite(area, WIDTH - SHORE_W, HEIGHT - WATER_Y, "BACKGROUND")
	B.Place(game.water, SHORE_W, WATER_Y, area)
	game.shore = B.Sprite(area, SHORE_W, HEIGHT, "BACKGROUND")
	B.Place(game.shore, 0, 0, area)
	game.sky = B.Sprite(area, WIDTH - SHORE_W, WATER_Y, "BACKGROUND")
	B.Place(game.sky, SHORE_W, 0, area)
	game.angler = B.Actor(area, 70, "player", CATCH, { scale = 2.4, facing = -math.pi / 2, animation = B.ANIM.stand })
	game.angler:Place(20, 130)
	game.ripples = {}
	for i = 1, 3 do game.ripples[i] = B.Sprite(area, 40, 40, "BORDER") end
	game.floatTop = B.Dot(area, FLOAT, nil, "ARTWORK")
	game.floatBottom = B.Dot(area, FLOAT, nil, "ARTWORK")
	game.prompt = B.Label(area, E.tokens.size.cardTitle, "body")
	game.prompt:SetPoint("TOP", area, "TOPLEFT", SHORE_W + (WIDTH - SHORE_W) / 2, -16)
	game.creel = {}
	for i = 1, CASTS do
		local slot = { back = B.Sprite(area, 22, 22, "ARTWORK"), icon = B.Sprite(area, 18, 18, "OVERLAY") }
		B.Place(slot.back, 8 + ((i - 1) % 4) * 24, HEIGHT - 80 + math.floor((i - 1) / 4) * 24, area)
		B.Place(slot.icon, 10 + ((i - 1) % 4) * 24, HEIGHT - 78 + math.floor((i - 1) / 4) * 24, area)
		E:SetClientFile(slot.icon, CATCH, "Interface\\Icons\\INV_Misc_QuestionMark")
		E:TrimIcon(slot.icon)
		game.creel[i] = slot
	end
	game.fx = B.Effects(area)
	return game
end

function Fishing:Start()
	self.casts, self.score, self.caught = 0, 0, 0
	self.window = 0.9
	self.log = {}
	self.phase, self.timer = "ready", 0
	self.bob, self.ending = nil, nil
	self.host.Score(0)
	self:Draw()
end

function Fishing:Cast()
	self.casts = self.casts + 1
	local x = SHORE_W + 60 + self.host.Random(WIDTH - SHORE_W - 120)
	local y = WATER_Y + 40 + self.host.Random(HEIGHT - WATER_Y - 90)
	self.bob = { x = x, y = y }
	self.phase = "wait"
	self.timer = 1.4 + self.host.Random(30) / 10
	self.nibbles = self.host.Random(3) - 1
	local roll, fish = self.host.Random(100), 1
	for i, f in ipairs(FISH) do
		roll = roll - f.chance
		if roll <= 0 then
			fish = i
			break
		end
	end
	self.fish = fish
	self.fx:Burst(x, y, self.host.Color("body"), 50, 0.5)
	self.host.Sound("turn")
	self:Draw()
end

function Fishing:Strike()
	local phase = self.phase
	if phase == "ready" or phase == "gone" then
		if self.casts >= CASTS then return end
		self:Cast()
		return
	end
	local bob = self.bob
	if phase == "bite" then
		local quick = math.max(0, 1 - self.timer / self.window)
		local f = FISH[self.fish]
		local points = math.max(10, math.floor(100 * (0.25 + quick * 0.75))) * f.worth
		self.score = self.score + points
		self.caught = self.caught + 1
		self.log[self.casts] = self.fish
		self.host.Score(self.score)
		local color = QUALITY[f.quality]
		self.fx:Burst(bob.x, bob.y, color, 90, 0.6)
		self.fx:Sparks(bob.x, bob.y, color, 12, 160)
		self.fx:Float(bob.x, bob.y - 20, "+" .. points, color)
		self.host.Sound("point")
		self.window = math.max(0.45, self.window - 0.03)
		self.note = f.quality >= 3 and L["A rare catch!"] or (quick > 0.7 and L["Quick!"] or L["Caught."])
	else
		-- Too soon: the fish is gone.
		self.log[self.casts] = 0
		self.fx:Burst(bob.x, bob.y, self.host.Color("dim"), 40, 0.4)
		self.note = L["Too soon: it got away."]
		self.host.Sound("over")
	end
	self:Done()
end

function Fishing:Done()
	self.phase, self.bob = "gone", nil
	self.timer = 0.8
	if self.casts >= CASTS then
		self:Draw()
		self.ending = 1.0
		return
	end
	self:Draw()
end

function Fishing:Key(key)
	if key == "SPACE" or key == "ENTER" then
		self:Strike()
		return true
	end
	return false
end

function Fishing:Press(button)
	if button == "LeftButton" then self:Strike() end
end

function Fishing:Update(dt)
	self.fx:Update(dt)
	if self.ending then
		self.ending = self.ending - dt
		if self.ending <= 0 then
			self.ending = nil
			self.host.Over(true)
		end
		return
	end
	local phase = self.phase
	if phase == "wait" then
		self.timer = self.timer - dt * self.host.Pace()
		if self.timer <= 0 then
			if (self.nibbles or 0) > 0 then
				self.nibbles = self.nibbles - 1
				self.phase, self.timer = "nibble", 0.35
				self.fx:Burst(self.bob.x, self.bob.y, self.host.Palette()[1], 30, 0.35)
			else
				self.phase, self.timer = "bite", 0
				self.fx:Burst(self.bob.x, self.bob.y, self.host.Color("body"), 80, 0.5)
				self.fx:Sparks(self.bob.x, self.bob.y, self.host.Palette()[1], 10, 140)
				self.host.Sound("start")
			end
		end
	elseif phase == "nibble" then
		self.timer = self.timer - dt
		if self.timer <= 0 then
			self.phase, self.timer = "wait", 0.8 + self.host.Random(15) / 10
		end
	elseif phase == "bite" then
		self.timer = self.timer + dt
		if self.timer > self.window then
			self.log[self.casts] = 0
			self.note = L["Too slow: it got away."]
			self.fx:Burst(self.bob.x, self.bob.y, self.host.Color("dim"), 40, 0.4)
			self:Done()
		end
	end
	self:Draw()
end

function Fishing:Summary()
	if not self.caught then return nil end
	return L["%d fish caught"]:format(self.caught)
end

function Fishing:Draw()
	local area, color, palette = self.host.area, self.host.Color, self.host.Palette()
	B.Fill(self.water, palette[7], 0.3)
	B.Fill(self.sky, palette[1], 0.08)
	B.Fill(self.shore, palette[3], 0.25)
	local t = GetTime and GetTime() or 0
	local bob = self.bob
	local shown = bob ~= nil
	self.floatTop:SetShown(shown)
	self.floatBottom:SetShown(shown)
	for i, ripple in ipairs(self.ripples) do
		ripple:SetShown(shown)
		if shown then
			local f = ((t * 0.6 + i / 3) % 1)
			local size = 20 + f * 50
			ripple:SetSize(size, size * 0.45)
			B.Place(ripple, bob.x - size / 2, bob.y - size * 0.225 + 6, area)
			B.Art(ripple, "Ring", color("body"), (1 - f) * 0.35)
		end
	end
	if shown then
		local dip = 0
		if self.phase == "nibble" then dip = math.sin(self.timer * 40) * 3 end
		if self.phase == "bite" then dip = 9 end
		local bad = color("bad")
		self.floatTop:SetVertexColor(bad[1], bad[2], bad[3], self.phase == "bite" and 0.4 or 1)
		local white = color("body")
		self.floatBottom:SetVertexColor(white[1], white[2], white[3], self.phase == "bite" and 0.3 or 1)
		B.Place(self.floatTop, bob.x - FLOAT / 2, bob.y - FLOAT + dip + math.sin(t * 2) * 1.5, area)
		B.Place(self.floatBottom, bob.x - FLOAT / 2, bob.y - FLOAT / 2 + dip + math.sin(t * 2) * 1.5, area)
	end
	local text
	if self.phase == "ready" then
		text = L["Space or a click: cast."]
	elseif self.phase == "gone" then
		text = (self.note or "") .. "  " .. (self.casts < CASTS and L["Cast again."] or "")
	elseif self.phase == "bite" then
		text = L["Strike!"]
	else
		text = L["Watch the float..."]
	end
	self.prompt:SetText(text)
	self.prompt:SetTextColor(unpack(self.phase == "bite" and color("warn") or color("body")))
	for i, slot in ipairs(self.creel) do
		local got = self.log and self.log[i]
		if got and got > 0 then
			B.Tile(slot.back, QUALITY[FISH[got].quality], 0.9)
			slot.icon:Show()
		else
			B.Tile(slot.back, color("dim"), got == 0 and 0.5 or 0.2)
			slot.icon:Hide()
		end
	end
end

M:RegisterGame({
	key = "fishing", order = 28, group = "arcade",
	title = "Fishing Reflex", desc = "Strike the moment the float goes under; ten casts a round.",
	controls = Key("Space or a click: cast, then strike. P: pause."),
	icon = CATCH,
	width = WIDTH, height = HEIGHT,
	New = New,
})
