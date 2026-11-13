-- EldoUI Flight Games: Five Dice. Roll five dice up to three times a turn,
-- keeping the ones you like between rolls, then write the dice into one
-- of the fifteen boxes of the score card. Every box is filled once; 63 or
-- more in the top boxes earns 50 more. Fifteen turns, the highest total
-- wins.
-- Written from scratch for EldoUI; you are your own character.
local _, E = ...
local M = E.FlightGames
local Key = E.Key
local L = E.L
local B = M.Board

local WIDTH, HEIGHT = 560, 430
local DIE, GAP = 44, 8
local DICE_X, DICE_Y = 14, 54
local CARD_X, CARD_W, ROW_H = 300, 256, 22
local ROLL_TIME = 0.5
local BONUS_AT, BONUS = 63, 50
local BOXES = {
	{ key = "ones", name = Key("Ones"), face = 1 },
	{ key = "twos", name = Key("Twos"), face = 2 },
	{ key = "threes", name = Key("Threes"), face = 3 },
	{ key = "fours", name = Key("Fours"), face = 4 },
	{ key = "fives", name = Key("Fives"), face = 5 },
	{ key = "sixes", name = Key("Sixes"), face = 6 },
	{ key = "pair", name = Key("One pair") },
	{ key = "twopair", name = Key("Two pairs") },
	{ key = "three", name = Key("Three alike") },
	{ key = "four", name = Key("Four alike") },
	{ key = "small", name = Key("Small straight") },
	{ key = "large", name = Key("Large straight") },
	{ key = "house", name = Key("Full house") },
	{ key = "chance", name = Key("Chance") },
	{ key = "five", name = Key("Five alike") },
}
-- Where the pips of each face sit, on a 3 x 3 grid.
local PIPS = {
	{ 5 }, { 1, 9 }, { 1, 5, 9 }, { 1, 3, 7, 9 }, { 1, 3, 5, 7, 9 }, { 1, 3, 4, 6, 7, 9 },
}

local Dice = {}
Dice.__index = Dice
-- What a saved game keeps (the board, the score and the timers).
Dice.saveKeys = { "dice", "held", "rolls", "card", "turn" }

-- What the dice are worth in a box.
local function Worth(box, dice)
	local count, sum = {}, 0
	for f = 1, 6 do count[f] = 0 end
	for _, d in ipairs(dice) do
		count[d] = count[d] + 1
		sum = sum + d
	end
	if box.face then return count[box.face] * box.face end
	local key = box.key
	local function Kind(n)
		for f = 6, 1, -1 do if count[f] >= n then return f end end
	end
	if key == "pair" then
		local f = Kind(2)
		return f and f * 2 or 0
	elseif key == "twopair" then
		local found = {}
		for f = 6, 1, -1 do if count[f] >= 2 then found[#found + 1] = f end end
		return #found >= 2 and (found[1] + found[2]) * 2 or 0
	elseif key == "three" then
		local f = Kind(3)
		return f and f * 3 or 0
	elseif key == "four" then
		local f = Kind(4)
		return f and f * 4 or 0
	elseif key == "small" then
		return (count[1] == 1 and count[2] == 1 and count[3] == 1 and count[4] == 1 and count[5] == 1) and 15 or 0
	elseif key == "large" then
		return (count[2] == 1 and count[3] == 1 and count[4] == 1 and count[5] == 1 and count[6] == 1) and 20 or 0
	elseif key == "house" then
		local three, two
		for f = 1, 6 do
			if count[f] == 3 then three = f elseif count[f] == 2 then two = f end
		end
		return (three and two) and sum or 0
	elseif key == "chance" then
		return sum
	elseif key == "five" then
		return Kind(5) and 50 or 0
	end
	return 0
end
Dice.Worth = Worth
Dice.BOXES = BOXES

local function New(host)
	local game = setmetatable({ host = host }, Dice)
	local area = host.area
	game.views = {}
	for i = 1, 5 do
		local x = DICE_X + (i - 1) * (DIE + GAP)
		local view = { x = x }
		view.back = B.Sprite(area, DIE, DIE, "BORDER")
		B.Place(view.back, x, DICE_Y, area)
		view.ring = B.Sprite(area, DIE + 8, DIE + 8, "OVERLAY")
		B.Place(view.ring, x - 4, DICE_Y - 4, area)
		view.pips = {}
		for p = 1, 9 do
			local pip = B.Dot(area, 8, nil, "ARTWORK")
			local px, py = (p - 1) % 3, math.floor((p - 1) / 3)
			B.Place(pip, x + 8 + px * 10.5, DICE_Y + 8 + py * 10.5, area)
			view.pips[p] = pip
		end
		view.held = B.Label(area, E.tokens.size.tiny, "secondary")
		view.held:SetPoint("TOP", area, "TOPLEFT", x + DIE / 2, -(DICE_Y + DIE + 8))
		view.key = B.Label(area, E.tokens.size.tiny, "dim")
		view.key:SetPoint("BOTTOM", area, "TOPLEFT", x + DIE / 2, -(DICE_Y - 6))
		view.key:SetText(i)
		game.views[i] = view
	end
	game.rollButton = B.Slab(area, 5 * DIE + 4 * GAP, 34, "BORDER")
	game.rollButton:Place(DICE_X, DICE_Y + DIE + 34)
	game.rollText = B.Label(area, E.tokens.size.cardTitle, "body")
	game.rollText:SetPoint("CENTER", area, "TOPLEFT", DICE_X + (5 * DIE + 4 * GAP) / 2, -(DICE_Y + DIE + 51))
	game.prompt = B.Label(area, E.tokens.size.small, "secondary")
	game.prompt:SetPoint("TOP", area, "TOPLEFT", DICE_X + (5 * DIE + 4 * GAP) / 2, -(DICE_Y + DIE + 78))
	game.hero = B.Actor(area, 120, "player", "Interface\\Icons\\INV_Misc_Dice_01", { scale = 1.6, facing = 0.4, animation = B.ANIM.stand })
	game.hero:Place(70, HEIGHT - 150)
	game.rows = {}
	for i = 1, #BOXES + 3 do
		local y = 6 + (i - 1) * ROW_H + (i > 6 and 4 or 0) + (i > 7 and 4 or 0) + (i > #BOXES + 1 and 4 or 0)
		local row = { y = y }
		row.back = B.Sprite(area, CARD_W, ROW_H - 2, "BORDER")
		B.Place(row.back, CARD_X, y, area)
		row.name = B.Label(area, E.tokens.size.small, "body", "LEFT")
		row.name:SetPoint("LEFT", area, "TOPLEFT", CARD_X + 8, -(y + ROW_H / 2 - 1))
		row.value = B.Label(area, E.tokens.size.small, "body", "RIGHT")
		row.value:SetPoint("RIGHT", area, "TOPLEFT", CARD_X + CARD_W - 8, -(y + ROW_H / 2 - 1))
		game.rows[i] = row
	end
	game.fx = B.Effects(area)
	return game
end

function Dice:Start()
	self.dice, self.held = { 1, 2, 3, 4, 5 }, {}
	self.rolls, self.card, self.turn = 0, {}, 1
	self.rolling = nil
	self.host.Score(0)
	self:Draw()
end

function Dice:Loaded()
	self.rolling = nil
	self.host.Score(self:Total())
end

function Dice:Upper()
	local sum = 0
	for i = 1, 6 do sum = sum + (self.card[BOXES[i].key] or 0) end
	return sum
end

function Dice:Total()
	local sum = 0
	for _, box in ipairs(BOXES) do sum = sum + (self.card[box.key] or 0) end
	if self:Upper() >= BONUS_AT then sum = sum + BONUS end
	return sum
end

function Dice:Roll()
	if self.rolling or self.rolls >= 3 then return end
	self.rolls = self.rolls + 1
	for i = 1, 5 do
		if not self.held[i] then self.dice[i] = self.host.Random(6) end
	end
	self.rolling = { left = ROLL_TIME, tick = 0, shown = { unpack(self.dice) } }
	self.host.Sound("turn")
	self:Draw()
end

function Dice:Hold(i)
	if self.rolls == 0 or self.rolling or not self.dice[i] then return end
	self.held[i] = not self.held[i] or nil
	self:Draw()
end

function Dice:Write(index)
	local box = BOXES[index]
	if not box or self.rolls == 0 or self.rolling or self.card[box.key] then return end
	local value = Worth(box, self.dice)
	local bonusBefore = self:Upper() >= BONUS_AT
	self.card[box.key] = value
	local row = self.rows[index]
	local color = value > 0 and self.host.Color("good") or self.host.Color("dim")
	self.fx:Burst(CARD_X + CARD_W - 30, row.y + ROW_H / 2, color, 50, 0.4)
	if value > 0 then self.fx:Float(CARD_X + CARD_W - 30, row.y, "+" .. value, color, E.tokens.size.small) end
	if box.key == "five" and value > 0 then
		self.fx:Sparks(DICE_X + 120, DICE_Y + DIE / 2, self.host.Color("gold"), 18, 220)
		self.hero:Animate(B.ANIM.cheer)
	end
	if not bonusBefore and self:Upper() >= BONUS_AT then
		self.fx:Float(CARD_X + CARD_W / 2, self.rows[#BOXES + 1].y, L["Bonus +50"], self.host.Color("gold"))
	end
	self.host.Sound(value > 0 and "point" or "turn")
	self.host.Score(self:Total())
	self.turn = self.turn + 1
	self.rolls, self.held = 0, {}
	if self.turn > #BOXES then
		self:Draw()
		self.host.Over(true)
		return
	end
	self:Draw()
end

function Dice:Key(key)
	if key == "SPACE" or key == "R" then
		self:Roll()
		return true
	end
	local n = tonumber(key)
	if n and n >= 1 and n <= 5 then
		self:Hold(n)
		return true
	end
	return false
end

function Dice:Press(button, x, y)
	if button ~= "LeftButton" or not (x and y) then return end
	for i, view in ipairs(self.views) do
		if x >= view.x and x <= view.x + DIE and y >= DICE_Y and y <= DICE_Y + DIE then
			self:Hold(i)
			return
		end
	end
	local w = 5 * DIE + 4 * GAP
	if x >= DICE_X and x <= DICE_X + w and y >= DICE_Y + DIE + 34 and y <= DICE_Y + DIE + 68 then
		self:Roll()
		return
	end
	if x >= CARD_X and x <= CARD_X + CARD_W then
		for i = 1, #BOXES do
			local row = self.rows[i]
			if y >= row.y and y <= row.y + ROW_H then
				self:Write(i)
				return
			end
		end
	end
end

function Dice:Update(dt)
	self.fx:Update(dt)
	local roll = self.rolling
	if roll then
		roll.left = roll.left - dt
		roll.tick = roll.tick - dt
		if roll.left <= 0 then
			self.rolling = nil
			self.hero:Animate(B.ANIM.stand)
			self:Draw()
		elseif roll.tick <= 0 then
			roll.tick = 0.06
			for i = 1, 5 do
				if not self.held[i] then roll.shown[i] = self.host.Random(6) end
			end
			self:Draw()
		end
	end
end

function Dice:Summary()
	if not self.card then return nil end
	return L["Score card total: %d"]:format(self:Total())
end

function Dice:Draw()
	local color, palette = self.host.Color, self.host.Palette()
	local paper = E.tokens.paper and E.tokens.paper.fill or { 0.92, 0.88, 0.78 }
	local shown = self.rolling and self.rolling.shown or self.dice
	local fresh = self.rolls == 0
	for i, view in ipairs(self.views) do
		local held = self.held[i]
		B.Art(view.back, "Card", paper, fresh and 0.45 or 1)
		local face = shown[i]
		local on = {}
		for _, p in ipairs(PIPS[face] or {}) do on[p] = true end
		for p, pip in ipairs(view.pips) do
			pip:SetShown(on[p] or false)
			pip:SetVertexColor(0.1, 0.08, 0.06, fresh and 0.4 or 1)
		end
		view.ring:SetShown(held or false)
		if held then B.Art(view.ring, "Ring", color("gold"), 1) end
		view.held:SetText(held and L["Kept"] or "")
	end
	local can = self.rolls < 3 and not self.rolling
	self.rollButton:Paint(can and color("accent") or color("dim"), can and 0.8 or 0.35)
	self.rollText:SetText(L["Roll (%d left)"]:format(3 - self.rolls))
	if fresh then
		self.prompt:SetText(L["Turn %d of %d: roll the dice."]:format(self.turn, #BOXES))
	elseif self.rolls < 3 then
		self.prompt:SetText(L["Click dice to keep them, roll again, or pick a box."])
	else
		self.prompt:SetText(L["Pick a box on the card."])
	end
	for i = 1, #BOXES + 3 do
		local row = self.rows[i]
		local box = BOXES[i]
		local name
		local value, kind, fill = "", "body", 0.12
		if box then
			name = L[box.name]
			local done = self.card[box.key]
			if done then
				value, kind, fill = tostring(done), done > 0 and "body" or "dim", 0.2
			elseif not fresh and not self.rolling then
				local w = Worth(box, self.dice)
				value, kind, fill = tostring(w), w > 0 and "good" or "dim", 0.08
			end
		elseif i == #BOXES + 1 then
			name = L["Top boxes (%d needed for the bonus)"]:format(BONUS_AT)
			value = tostring(self:Upper())
		elseif i == #BOXES + 2 then
			name = L["Bonus"]
			value = self:Upper() >= BONUS_AT and tostring(BONUS) or "-"
			kind = self:Upper() >= BONUS_AT and "gold" or "dim"
		else
			name = L["Total"]
			value = tostring(self:Total())
			kind, fill = "gold", 0.3
		end
		B.Fill(row.back, i > #BOXES and palette[4] or color("dim"), fill)
		row.name:SetText(name)
		row.value:SetText(value)
		row.value:SetTextColor(unpack(color(kind)))
	end
end

M:RegisterGame({
	key = "fivedice", order = 135, group = "board",
	title = "Five Dice", desc = "Three rolls a turn, fifteen boxes to fill; chase the highest total.",
	controls = Key("Space: roll. 1 to 5 or a click: keep a die. Click a box to write the dice in it. P: pause."),
	icon = "Interface\\Icons\\INV_Misc_Dice_01",
	Size = function() return WIDTH, HEIGHT end,
	New = New,
})
