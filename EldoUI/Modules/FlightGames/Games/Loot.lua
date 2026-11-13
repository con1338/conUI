-- EldoUI Flight Games: Loot Catch. A chest at the top bursts open again
-- and again, and loot flies out of it: catch it in your bag. Better loot
-- is worth more (gray to purple); a blue or purple piece that hits the
-- ground costs a life, and so does a bomb in the bag. Three lives; the
-- chest throws faster as you go.
-- Written from scratch for EldoUI; the loot wears the game's own item
-- icons and quality colors.
local _, E = ...
local M = E.FlightGames
local Key = E.Key
local L = E.L
local B = M.Board

local WIDTH, HEIGHT = 420, 380
local BAG_W, BAG_H = 64, 40
local BAG_Y = HEIGHT - BAG_H - 8
local ITEM = 26
local GRAVITY = 500
local BAG_SPEED = 380
local CHEST_X, CHEST_Y, CHEST = WIDTH / 2 - 20, 14, 40
local LIVES = 3
local BOMB = "Interface\\Icons\\INV_Misc_Bomb_04"
local CHEST_ICON = "Interface\\Icons\\INV_Box_02"
local BAG_ICON = "Interface\\Icons\\INV_Misc_Bag_10"
-- Loot by quality (0 poor to 4 epic): its points, how often it comes and
-- the icons it wears.
local QUALITY = {
	[0] = { points = 1, weight = 30 },
	[1] = { points = 5, weight = 30 },
	[2] = { points = 10, weight = 20 },
	[3] = { points = 25, weight = 10 },
	[4] = { points = 50, weight = 4 },
}
local ICONS = {
	"Interface\\Icons\\INV_Sword_04", "Interface\\Icons\\INV_Helmet_36", "Interface\\Icons\\INV_Chest_Chain",
	"Interface\\Icons\\INV_Chest_Plate06", "Interface\\Icons\\INV_Misc_Gem_Ruby_01", "Interface\\Icons\\INV_Misc_Coin_01",
	"Interface\\Icons\\INV_Chest_Cloth_17", "Interface\\Icons\\INV_Misc_Gem_Pearl_05",
}

local Loot = {}
Loot.__index = Loot
-- What a saved round keeps.
Loot.saveKeys = { "bag", "items", "lives", "score", "caught", "next", "time" }

local function New(host)
	local game = setmetatable({ host = host, views = {} }, Loot)
	local area = host.area
	game.floor = B.Sprite(area, WIDTH, 6, "BORDER")
	B.Place(game.floor, 0, HEIGHT - 6, area)
	game.chest = B.Sprite(area, CHEST, CHEST, "ARTWORK")
	E:SetClientFile(game.chest, CHEST_ICON, "Interface\\Icons\\INV_Misc_QuestionMark")
	E:TrimIcon(game.chest)
	B.Place(game.chest, CHEST_X, CHEST_Y, area)
	game.chestRing = B.Sprite(area, CHEST + 12, CHEST + 12, "OVERLAY")
	B.Place(game.chestRing, CHEST_X - 6, CHEST_Y - 6, area)
	game.bagBack = B.Sprite(area, BAG_W, BAG_H, "BORDER")
	game.bagArt = B.Sprite(area, BAG_H - 6, BAG_H - 6, "ARTWORK")
	E:SetClientFile(game.bagArt, BAG_ICON, "Interface\\Icons\\INV_Misc_QuestionMark")
	E:TrimIcon(game.bagArt)
	game.tally = B.Label(area, E.tokens.size.cardTitle, "body", "LEFT")
	game.tally:SetPoint("TOPLEFT", area, "TOPLEFT", 8, -8)
	game.hearts = {}
	for i = 1, LIVES do
		local heart = B.Sprite(area, 16, 16, "OVERLAY")
		B.Art(heart, "Heart")
		B.Place(heart, WIDTH - 8 - i * 20, 10, area)
		game.hearts[i] = heart
	end
	game.fx = B.Effects(area)
	game.keys = {}
	return game
end

function Loot:Start()
	self.bag = WIDTH / 2
	self.items = {}
	self.lives, self.score, self.caught = LIVES, 0, 0
	self.next, self.time = 1.0, 0
	self.keys, self.mouse = {}, nil
	self.fx:Clear()
	self.host.Score(0)
	self:Draw()
end

function Loot:Loaded()
	self.keys, self.mouse = {}, nil
end

-- One piece out of the chest: a quality, or a bomb now and then.
function Loot:Throw()
	local item = { x = CHEST_X + CHEST / 2 - ITEM / 2, y = CHEST_Y + 10 }
	local bombs = math.min(18, 6 + math.floor(self.time / 10))
	local roll = self.host.Random(1, 100)
	if roll <= bombs then
		item.bomb = true
	else
		local total = 0
		for q = 0, 4 do total = total + QUALITY[q].weight end
		local pick = self.host.Random(1, total)
		for q = 0, 4 do
			pick = pick - QUALITY[q].weight
			if pick <= 0 then item.q = q break end
		end
		item.icon = self.host.Random(1, #ICONS)
	end
	-- Up and out to one side; where it lands is spread over the floor.
	local land = self.host.Random(ITEM, WIDTH - ITEM * 2)
	local flight = 1.5 - math.min(0.6, self.time / 120)
	local drop = HEIGHT - 6 - ITEM - item.y
	item.vx = (land - item.x) / flight
	item.vy = (drop - GRAVITY * flight * flight / 2) / flight
	self.items[#self.items + 1] = item
	self.fx:Burst(CHEST_X + CHEST / 2, CHEST_Y + CHEST / 2, self.host.Color("gold"), 60, 0.3)
end

local LEFTS, RIGHTS = { LEFT = true, A = true }, { RIGHT = true, D = true }

function Loot:Key(key)
	if LEFTS[key] or RIGHTS[key] then
		self.keys[key] = true
		self.mouse = nil
		return true
	end
	return false
end

function Loot:KeyUp(key)
	self.keys[key] = nil
end

function Loot:Press(button, x)
	if button == "LeftButton" and x then self.mouse = x end
end

local function Held(keys, set)
	for name in pairs(set) do
		if keys[name] then return true end
	end
	return false
end

-- True when the item passed the bag's mouth this frame: its bottom
-- crossed the mouth (however far it fell in one frame) over the bag.
function Loot:Catches(item, before)
	local half = BAG_W / 2
	local mid = item.x + ITEM / 2
	local bottom = item.y + ITEM
	before = before or bottom
	return bottom >= BAG_Y and before <= BAG_Y + BAG_H * 0.6 and mid >= self.bag - half and mid <= self.bag + half
end

function Loot:Lose(x, y)
	self.lives = self.lives - 1
	self.fx:Burst(x, y, self.host.Palette()[6], 70, 0.45)
	self.host.Sound("over")
end

function Loot:Update(dt)
	self.fx:Update(dt)
	dt = dt * self.host.Pace()
	self.time = self.time + dt
	-- The bag: the keys, else it follows the pointer over the play area.
	local left, right = Held(self.keys, LEFTS), Held(self.keys, RIGHTS)
	if left then self.bag = self.bag - BAG_SPEED * dt end
	if right then self.bag = self.bag + BAG_SPEED * dt end
	if not (left or right) then
		local x, y = self.host.Cursor()
		if x and y and x >= 0 and x <= WIDTH and y >= 0 and y <= HEIGHT and x ~= self.lastCursor then
			self.mouse, self.lastCursor = x, x
		end
		if self.mouse then
			local step = BAG_SPEED * 1.6 * dt
			self.bag = self.bag + math.max(-step, math.min(step, self.mouse - self.bag))
		end
	end
	self.bag = math.max(BAG_W / 2, math.min(WIDTH - BAG_W / 2, self.bag))
	self.next = self.next - dt
	if self.next <= 0 then
		self:Throw()
		self.next = math.max(0.45, 1.25 - self.time / 90) * (0.7 + self.host.Random(0, 60) / 100)
	end
	local keep = {}
	for _, item in ipairs(self.items) do
		item.vy = item.vy + GRAVITY * dt
		local before = item.y + ITEM
		item.x, item.y = item.x + item.vx * dt, item.y + item.vy * dt
		if item.x < 0 then item.x, item.vx = 0, -item.vx end
		if item.x > WIDTH - ITEM then item.x, item.vx = WIDTH - ITEM, -item.vx end
		local cx, cy = item.x + ITEM / 2, item.y + ITEM / 2
		if item.vy > 0 and self:Catches(item, before) then
			if item.bomb then
				self:Lose(cx, cy)
			else
				local quality = QUALITY[item.q]
				self.score = self.score + quality.points
				self.caught = self.caught + 1
				self.host.Score(self.score)
				local r, g, b = E.UIKit.QualityColor(item.q)
				local tint = r and { r, g, b } or self.host.Color("gold")
				self.fx:Sparks(cx, BAG_Y, tint, 4 + item.q * 2, 90)
				self.fx:Float(cx, BAG_Y - 10, "+" .. quality.points, tint, E.tokens.size.small)
				self.host.Sound("point")
			end
		elseif item.y >= HEIGHT - 6 - ITEM then
			if item.bomb then
				self.fx:Burst(cx, HEIGHT - 10, self.host.Color("secondary"), 40, 0.3)
			elseif item.q >= 3 then
				self:Lose(cx, HEIGHT - 10)
				self.fx:Float(cx, HEIGHT - 30, L["Lost!"], self.host.Palette()[6], E.tokens.size.small)
			end
		else
			keep[#keep + 1] = item
		end
	end
	self.items = keep
	self:Draw()
	if self.lives <= 0 then self.host.Over(false) end
end

function Loot:Draw()
	local area = self.host.area
	local color = self.host.Color
	B.Fill(self.floor, E.tokens.palette.bronze, 0.5)
	B.Art(self.chestRing, "Ring", color("gold"), 0.7)
	local bag = self.bag or WIDTH / 2
	B.Place(self.bagBack, bag - BAG_W / 2, BAG_Y, area)
	B.Tile(self.bagBack, E.tokens.palette.bronze, 0.6)
	B.Place(self.bagArt, bag - (BAG_H - 6) / 2, BAG_Y + 3, area)
	for i, heart in ipairs(self.hearts) do
		heart:SetVertexColor(unpack(i <= (self.lives or LIVES) and self.host.Palette()[6] or color("dim")))
	end
	for i, item in ipairs(self.items or {}) do
		local view = self.views[i]
		if not view then
			view = { icon = B.Sprite(area, ITEM, ITEM, "ARTWORK"), ring = B.Sprite(area, ITEM + 6, ITEM + 6, "OVERLAY") }
			self.views[i] = view
		end
		local art = item.bomb and BOMB or ICONS[item.icon] or ICONS[1]
		if view.art ~= art then
			view.art = art
			E:SetClientFile(view.icon, art, "Interface\\Icons\\INV_Misc_QuestionMark")
			E:TrimIcon(view.icon)
		end
		B.Place(view.icon, item.x, item.y, area)
		B.Place(view.ring, item.x - 3, item.y - 3, area)
		local r, g, b = E.UIKit.QualityColor(item.q)
		local tint = item.bomb and self.host.Palette()[6] or (r and { r, g, b }) or color("secondary")
		B.Art(view.ring, "Ring", tint, item.bomb and 1 or 0.4 + (item.q or 0) * 0.15)
		view.icon:Show()
		view.ring:Show()
	end
	for i = #(self.items or {}) + 1, #self.views do
		self.views[i].icon:Hide()
		self.views[i].ring:Hide()
	end
	self.tally:SetText(E:Plural(self.caught or 0, "%d piece caught", "%d pieces caught"):format(self.caught or 0))
end

function Loot:Summary()
	if not self.caught then return nil end
	return E:Plural(self.caught, "%d piece caught", "%d pieces caught"):format(self.caught)
end

M:RegisterGame({
	key = "loot", order = 44, group = "arcade",
	title = "Loot Catch", desc = "Catch the loot from the chest in your bag; let the bombs fall.",
	controls = Key("Move the mouse, Left and Right, or click where the bag goes. P: pause."),
	icon = CHEST_ICON,
	width = WIDTH, height = HEIGHT,
	New = New,
})
