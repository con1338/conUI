-- EldoUI Flight Games: Pairs. Every card hides a spell icon, and each
-- icon is there twice. Turn two cards: a pair stays open, two different
-- cards turn back. Find every pair in as few turns as you can.
-- Written from scratch for EldoUI; the cards show the game's own icons.
local _, E = ...
local M = E.FlightGames
local Key = E.Key
local B = M.Board

local MODES = {
	{ key = "small", title = "16 cards", cols = 4, rows = 4, cell = 76 },
	{ key = "large", title = "24 cards", cols = 6, rows = 4, cell = 76 },
	{ key = "huge", title = "36 cards", cols = 6, rows = 6, cell = 62 },
}
local SHOW = 0.8 -- how long two different cards stay open
local BACK = "Interface\\Icons\\INV_Misc_QuestionMark"
local ICONS = {
	"Interface\\Icons\\Spell_Fire_FireBolt02", "Interface\\Icons\\Spell_Frost_FrostBolt02", "Interface\\Icons\\Spell_Holy_FlashHeal",
	"Interface\\Icons\\Ability_Warrior_Charge", "Interface\\Icons\\Ability_Rogue_Sprint", "Interface\\Icons\\Spell_Frost_FrostNova",
	"Interface\\Icons\\Spell_Holy_PowerWordShield", "Interface\\Icons\\Ability_Hunter_SniperShot", "Interface\\Icons\\Spell_Fire_Immolation",
	"Interface\\Icons\\Ability_Warrior_Cleave", "Interface\\Icons\\Spell_Arcane_TeleportStormwind", "Interface\\Icons\\Ability_Seal",
	"Interface\\Icons\\Spell_Holy_PrayerOfHealing", "Interface\\Icons\\Ability_Warrior_DefensiveStance", "Interface\\Icons\\Ability_Druid_ChallangingRoar",
	"Interface\\Icons\\Ability_DualWield", "Interface\\Icons\\Ability_Rogue_FeignDeath", "Interface\\Icons\\Spell_Fire_SealOfFire",
}

local Pairs = {}
Pairs.__index = Pairs
-- What a saved game keeps (the board, the score and the timers).
Pairs.saveKeys = { "deck", "found", "turns", "pairs", "cx", "cy" }

local function ModeOf(mode)
	return mode and mode.cols and mode or MODES[1]
end

local function New(host, mode)
	mode = ModeOf(mode)
	local game = setmetatable({ host = host, mode = mode }, Pairs)
	game.grid = B.Grid(host.area, mode.cols, mode.rows, mode.cell, { gap = 8 })
	game.grid.frame:SetPoint("TOPLEFT")
	game.cursor = B.Sprite(game.grid.frame, mode.cell, mode.cell, "OVERLAY")
	game.cursor:SetDrawLayer("OVERLAY", 7)
	game.cursor:Hide()
	return game
end

function Pairs:Start()
	local count = self.mode.cols * self.mode.rows
	local deck = {}
	for n = 1, count / 2 do
		deck[#deck + 1] = n
		deck[#deck + 1] = n
	end
	for i = #deck, 2, -1 do
		local j = self.host.Random(i)
		deck[i], deck[j] = deck[j], deck[i]
	end
	self.deck, self.found, self.up = deck, {}, {}
	self.turns, self.pairs, self.wait = 0, 0, nil
	self.cx, self.cy = 1, 1
	self.host.Score(0)
	self:Draw()
end

function Pairs:Flip(x, y)
	if self.wait then
		-- Two different cards are still open: a click turns them back now.
		self:Hide()
	end
	local index = (y - 1) * self.mode.cols + x
	if self.found[index] or self.up[1] == index then return end
	self.up[#self.up + 1] = index
	self.host.Sound("turn")
	if #self.up == 2 then
		self.turns = self.turns + 1
		self.host.Score(self.turns)
		local a, b = self.up[1], self.up[2]
		if self.deck[a] == self.deck[b] then
			self.found[a], self.found[b] = true, true
			self.up = {}
			self.pairs = self.pairs + 1
			self.host.Sound("point")
			if self.pairs * 2 >= #self.deck then
				self:Draw()
				self.host.Over(true)
				return
			end
		else
			self.wait = SHOW
		end
	end
	self:Draw()
end

function Pairs:Hide()
	self.up = {}
	self.wait = nil
	self:Draw()
end

function Pairs:Update(dt)
	if not self.wait then return end
	self.wait = self.wait - dt
	if self.wait <= 0 then self:Hide() end
end

function Pairs:Press(button, x, y)
	if button ~= "LeftButton" then return end
	local cx, cy = self.grid:CellAt(x, y)
	if cx then
		self.cx, self.cy = cx, cy
		self:Flip(cx, cy)
	end
end

local MOVE = { UP = { 0, -1 }, W = { 0, -1 }, DOWN = { 0, 1 }, S = { 0, 1 }, LEFT = { -1, 0 }, A = { -1, 0 }, RIGHT = { 1, 0 }, D = { 1, 0 } }

function Pairs:Key(key)
	local move = MOVE[key]
	if move then
		self.cx = math.max(1, math.min(self.mode.cols, self.cx + move[1]))
		self.cy = math.max(1, math.min(self.mode.rows, self.cy + move[2]))
		self.showCursor = true
		self:Draw()
		return true
	end
	if key == "SPACE" or key == "ENTER" then
		self:Flip(self.cx, self.cy)
		return true
	end
	return false
end

function Pairs:IsUp(index)
	return self.up[1] == index or self.up[2] == index
end

function Pairs:Draw()
	local grid = self.grid
	for y = 1, self.mode.rows do
		for x = 1, self.mode.cols do
			local index = (y - 1) * self.mode.cols + x
			if self.deck and (self.found[index] or self:IsUp(index)) then
				local icon = grid:Icon(x, y, ICONS[self.deck[index]], self.host.Color("dim"))
				if icon then icon:SetAlpha(self.found[index] and 0.55 or 1) end
			else
				local icon = grid:Icon(x, y, BACK, self.host.Color("accent"))
				if icon then icon:SetAlpha(0.35) end
			end
		end
	end
	if self.showCursor and self.cx then
		B.Place(self.cursor, (self.cx - 1) * self.mode.cell, (self.cy - 1) * self.mode.cell, grid.frame)
		B.Art(self.cursor, "Ring", self.host.Color("accent"), 0.95)
		self.cursor:Show()
	else
		self.cursor:Hide()
	end
end

function Pairs:Loaded()
	self.up, self.wait = {}, nil
end

M:RegisterGame({
	key = "pairs", order = 80, group = "puzzle",
	title = "Pairs", desc = "Turn two cards at a time and find every pair.",
	controls = Key("Click a card to turn it. Arrow keys and Space work too."),
	icon = "Interface\\Icons\\INV_Misc_Book_09",
	lower = true, unit = "moves",
	modes = MODES,
	Size = function(mode)
		mode = ModeOf(mode)
		return mode.cols * mode.cell, mode.rows * mode.cell
	end,
	New = New,
})
