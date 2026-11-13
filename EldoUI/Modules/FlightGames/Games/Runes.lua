-- EldoUI Flight Games: Rune Memory. The runes light up one after another;
-- light them again in the same order. Each round adds one rune to the
-- end and plays a little faster. One wrong rune ends the game.
-- Written from scratch for EldoUI; the runes show the game's own spell
-- icons.
local _, E = ...
local M = E.FlightGames
local Key = E.Key
local L = E.L
local B = M.Board

local SIZE, GAP = 120, 16
local TOP = 40
local MODES = {
	{ key = "four", title = "4 runes", count = 4, cols = 2 },
	{ key = "six", title = "6 runes", count = 6, cols = 3 },
}
local RUNES = {
	{ icon = "Interface\\Icons\\Spell_Fire_FireBolt02", color = 6 },
	{ icon = "Interface\\Icons\\Spell_Frost_FrostBolt02", color = 1 },
	{ icon = "Interface\\Icons\\Spell_Nature_Poisoncleansingtotem", color = 3 },
	{ icon = "Interface\\Icons\\Spell_Holy_SurgeOfLight", color = 4 },
	{ icon = "Interface\\Icons\\Spell_Holy_PowerWordShield", color = 5 },
	{ icon = "Interface\\Icons\\Spell_Fire_SealOfFire", color = 2 },
}

local Runes = {}
Runes.__index = Runes
-- What a saved game keeps (the board, the score and the timers).
Runes.saveKeys = { "order", "at", "phase", "timer", "lit", "round" }

local function ModeOf(mode)
	return mode and mode.count and mode or MODES[1]
end

local function Size(mode)
	mode = ModeOf(mode)
	local rows = math.ceil(mode.count / mode.cols)
	return mode.cols * SIZE + (mode.cols + 1) * GAP, TOP + rows * SIZE + (rows + 1) * GAP
end

local function New(host, mode)
	mode = ModeOf(mode)
	local game = setmetatable({ host = host, mode = mode }, Runes)
	local area = host.area
	local width = Size(mode)
	game.views = {}
	for i = 1, mode.count do
		local col, row = (i - 1) % mode.cols, math.floor((i - 1) / mode.cols)
		local x, y = GAP + col * (SIZE + GAP), TOP + GAP + row * (SIZE + GAP)
		local view = { x = x, y = y }
		view.back = B.Sprite(area, SIZE, SIZE, "BORDER")
		B.Place(view.back, x, y, area)
		view.icon = B.Sprite(area, SIZE - 40, SIZE - 40, "ARTWORK")
		B.Place(view.icon, x + 20, y + 20, area)
		E:SetClientFile(view.icon, RUNES[i].icon, "Interface\\Icons\\INV_Misc_QuestionMark")
		E:TrimIcon(view.icon)
		view.ring = B.Sprite(area, SIZE + 10, SIZE + 10, "OVERLAY")
		B.Place(view.ring, x - 5, y - 5, area)
		view.key = B.Label(area, E.tokens.size.small, "dim")
		view.key:SetPoint("TOPLEFT", area, "TOPLEFT", x + 8, -(y + 6))
		view.key:SetText(i)
		game.views[i] = view
	end
	game.prompt = B.Label(area, E.tokens.size.cardTitle, "body")
	game.prompt:SetPoint("TOP", area, "TOPLEFT", width / 2, -12)
	game.fx = B.Effects(area)
	return game
end

function Runes:Start()
	self.order, self.round = {}, 0
	self:NextRound()
	self.host.Score(0)
	self:Draw()
end

-- One more rune, then the whole order plays.
function Runes:NextRound()
	self.round = self.round + 1
	self.order[#self.order + 1] = self.host.Random(self.mode.count)
	self.phase, self.at, self.timer, self.lit = "show", 0, 0.7, nil
end

function Runes:Beat()
	return math.max(0.22, 0.55 - #self.order * 0.02)
end

function Runes:Light(i)
	self.lit = i
	local view = self.views[i]
	local color = self.host.Palette()[RUNES[i].color]
	self.fx:Burst(view.x + SIZE / 2, view.y + SIZE / 2, color, SIZE * 1.4, 0.4)
	self.host.Sound("turn")
end

function Runes:Choose(i)
	if self.phase ~= "repeat" or not self.views[i] then return end
	self:Light(i)
	self.timer = 0.2
	self.at = self.at + 1
	if self.order[self.at] ~= i then
		local view = self.views[i]
		self.fx:Sparks(view.x + SIZE / 2, view.y + SIZE / 2, self.host.Color("bad"), 12)
		self.phase = "wrong"
		self.timer = 0.9
		self.host.Sound("over")
		self:Draw()
		return
	end
	if self.at >= #self.order then
		self.host.Score(#self.order)
		self.host.Sound("point")
		self.phase, self.timer = "done", 0.8
	end
	self:Draw()
end

function Runes:Key(key)
	local n = tonumber(key) or tonumber((key or ""):match("^NUMPAD(%d)$"))
	if n and n >= 1 and n <= self.mode.count then
		self:Choose(n)
		return true
	end
	return false
end

function Runes:Press(button, x, y)
	if button ~= "LeftButton" or not (x and y) then return end
	for i, view in ipairs(self.views) do
		if x >= view.x and x <= view.x + SIZE and y >= view.y and y <= view.y + SIZE then
			self:Choose(i)
			return
		end
	end
end

function Runes:Update(dt)
	self.fx:Update(dt)
	self.timer = self.timer - dt
	if self.timer > 0 then
		if self.phase == "repeat" and self.lit and self.timer <= 0.05 then self.lit = nil end
		self:Draw()
		return
	end
	local phase = self.phase
	if phase == "show" then
		if self.lit then
			self.lit = nil
			self.timer = self:Beat() * 0.4
		else
			self.at = self.at + 1
			if self.at > #self.order then
				self.phase, self.at = "repeat", 0
			else
				self:Light(self.order[self.at])
				self.timer = self:Beat()
			end
		end
	elseif phase == "repeat" then
		self.lit = nil
	elseif phase == "done" then
		self:NextRound()
	elseif phase == "wrong" then
		self:Draw()
		self.host.Over(false)
		return
	end
	self:Draw()
end

function Runes:Summary()
	local best = math.max(0, #(self.order or {}) - 1)
	return E:Plural(best, "%d rune remembered", "%d runes remembered"):format(best)
end

function Runes:Draw()
	local palette, color = self.host.Palette(), self.host.Color
	for i, view in ipairs(self.views) do
		local tint = palette[RUNES[i].color]
		local on = self.lit == i
		B.Tile(view.back, tint, on and 0.95 or 0.3)
		view.icon:SetAlpha(on and 1 or 0.55)
		view.icon:SetDesaturated(not on and self.phase == "show")
		view.ring:SetShown(on)
		if on then B.Art(view.ring, "Ring", self.phase == "wrong" and color("bad") or color("body"), 0.9) end
	end
	local text
	if self.phase == "show" then
		text = L["Watch the runes..."]
	elseif self.phase == "repeat" then
		text = L["Your turn: %d of %d"]:format(self.at, #self.order)
	elseif self.phase == "done" then
		text = L["Right! One more."]
	else
		text = L["Wrong rune."]
	end
	self.prompt:SetText(text)
end

M:RegisterGame({
	key = "runes", order = 75, group = "puzzle", wins = false,
	title = "Rune Memory", desc = "Light the runes again in the order they lit; one more each round.",
	controls = Key("Click the runes, or their number keys. P: pause."),
	icon = "Interface\\Icons\\INV_Misc_Rune_01",
	modes = MODES,
	Size = Size,
	New = New,
})
