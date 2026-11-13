-- EldoUI Flight Games: Dice Duel. You and a murloc roll in turn, each
-- from 1 up to the number the other one rolled last; the first duel starts
-- at 100, 1,000 or 1,000,000. Whoever rolls a 1 loses the duel. Every duel
-- you win adds one to your run of wins; a lost duel ends the run.
-- Everything stays in this window: nothing is rolled in chat, and there is
-- nothing at stake but the run.
-- Written from scratch for EldoUI; the players are the game's own models
-- (icons when models are off).
local _, E = ...
local M = E.FlightGames
local Key = E.Key
local L = E.L
local B = M.Board

local WIDTH, HEIGHT = 560, 340
local SIDE_W = 150
local DIE = 116
local ROLL_TIME = 0.7       -- the number spins this long
local THEIR_WAIT = 0.6      -- the murloc thinks this long before its roll
local NEXT_WAIT = 1.6       -- the next duel starts after this
local HISTORY = 6
local MODES = {
	{ key = "hundred", title = "From 100", from = 100 },
	{ key = "thousand", title = "From 1,000", from = 1000 },
	{ key = "million", title = "From 1,000,000", from = 1000000 },
}
local YOU_ICON = "Interface\\Icons\\INV_Misc_Dice_01"
local THEM_ICON = "Interface\\Icons\\INV_Misc_Head_Murloc_01"

local Dice = {}
Dice.__index = Dice
-- What a saved game keeps (the board, the score and the timers).
Dice.saveKeys = { "streak", "limit", "turnOf", "lastYou", "lastThem", "history", "done", "shown", "wait", "rolling" }

local function ModeOf(mode)
	return mode and mode.from and mode or MODES[1]
end

local function Number(value)
	return BreakUpLargeNumbers and BreakUpLargeNumbers(value) or tostring(value)
end

-- One side: a model (or an icon), a name and a label for its last roll.
local function Side(area, x, display, icon, name)
	local side = {}
	side.plate = B.Slab(area, SIDE_W, 48, "BORDER")
	side.plate:Place(x, HEIGHT - 70)
	-- An actor, so the Creature models option switches it at once: the
	-- model fills the side's column, the icon sits in its middle.
	side.figure = B.Actor(area, 64, display, icon, { modelW = SIDE_W, modelH = 190, layer = "ARTWORK",
		facing = display == "player" and 0.4 or -0.4, animation = B.ANIM.stand })
	side.figure:Place(x + (SIDE_W - 64) / 2, 103)
	side.name = B.Label(area, E.tokens.size.cardTitle, "title")
	side.name:SetPoint("TOP", area, "TOPLEFT", x + SIDE_W / 2, -(HEIGHT - 64))
	side.name:SetText(name)
	side.last = B.Label(area, E.tokens.size.small, "secondary")
	side.last:SetPoint("TOP", side.name, "BOTTOM", 0, -4)
	return side
end

local function New(host, mode)
	mode = ModeOf(mode)
	local game = setmetatable({ host = host, mode = mode, history = {} }, Dice)
	local area = host.area
	game.you = Side(area, 16, "player", YOU_ICON, L["You"])
	game.them = Side(area, WIDTH - SIDE_W - 16, B.DISPLAY.murloc, THEM_ICON, L["Murloc"])
	local center = WIDTH / 2
	game.range = B.Label(area, E.tokens.size.section, "secondary")
	game.range:SetPoint("TOP", area, "TOPLEFT", center, -18)
	game.die = B.Sprite(area, DIE, DIE, "BORDER")
	B.Place(game.die, center - DIE / 2, 44, area)
	game.ring = B.Sprite(area, DIE + 8, DIE + 8, "ARTWORK")
	B.Place(game.ring, center - DIE / 2 - 4, 40, area)
	game.number = B.Label(area, E.tokens.size.hero, "title")
	game.number:SetPoint("CENTER", area, "TOPLEFT", center, -(44 + DIE / 2))
	game.turn = B.Label(area, E.tokens.size.body, "body")
	game.turn:SetPoint("TOP", area, "TOPLEFT", center, -(44 + DIE + 12))
	game.lines = {}
	for i = 1, HISTORY do
		local line = B.Label(area, E.tokens.size.small, "secondary")
		line:SetPoint("TOP", area, "TOPLEFT", center, -(44 + DIE + 36 + (i - 1) * 15))
		game.lines[i] = line
	end
	return game
end

function Dice:Start()
	self.streak = 0
	self.host.Score(0)
	self:NewDuel()
end

function Dice:NewDuel()
	self.limit = self.mode.from
	self.turnOf = "you"
	self.rolling, self.wait = nil, nil
	self.shown = nil
	self.lastYou, self.lastThem = nil, nil
	self.history = {}
	self.done = nil
	self:Draw()
end

-- A roll starts: the number spins, then lands.
function Dice:Roll(who)
	if self.rolling or self.done or self.turnOf ~= who then return end
	self.rolling = { who = who, left = ROLL_TIME, result = self.host.Random(self.limit), tick = 0 }
	self.host.Sound("turn")
	self:Draw()
end

function Dice:Land()
	local roll = self.rolling
	self.rolling = nil
	local who, result = roll.who, roll.result
	self.shown = result
	local from = self.limit
	if who == "you" then self.lastYou = result else self.lastThem = result end
	table.insert(self.history, 1, { who = who, result = result, from = from })
	while #self.history > HISTORY do table.remove(self.history) end
	if result == 1 then
		self.done = who == "you" and "lost" or "won"
		if self.done == "won" then
			self.streak = self.streak + 1
			self.host.Score(self.streak)
			self.host.Sound("point")
			self.wait = { left = NEXT_WAIT, what = "duel" }
		else
			self.wait = { left = 1.0, what = "over" }
		end
	else
		self.limit = result
		self.turnOf = who == "you" and "them" or "you"
		if self.turnOf == "them" then self.wait = { left = THEIR_WAIT, what = "them" } end
	end
	self:Draw()
end

function Dice:Update(dt)
	local roll = self.rolling
	if roll then
		roll.left = roll.left - dt
		roll.tick = roll.tick - dt
		if roll.left <= 0 then
			self:Land()
		elseif roll.tick <= 0 then
			roll.tick = 0.05
			self.shown = self.host.Random(self.limit)
			self:DrawNumber()
		end
		return
	end
	local wait = self.wait
	if wait then
		wait.left = wait.left - dt
		if wait.left > 0 then return end
		self.wait = nil
		if wait.what == "them" then
			self:Roll("them")
		elseif wait.what == "duel" then
			self:NewDuel()
		elseif wait.what == "over" then
			self.host.Over(false)
		end
	end
end

function Dice:Key(key)
	if key == "SPACE" or key == "ENTER" or key == "R" then
		self:Roll("you")
		return true
	end
	return false
end

function Dice:Press(button)
	if button == "LeftButton" then self:Roll("you") end
end

-- "3 duels won in a row", for the end of the run.
function Dice:Summary()
	if not self.streak then return nil end
	return E:Plural(self.streak, "%d duel won in a row", "%d duels won in a row"):format(self.streak)
end

function Dice:DrawNumber()
	self.number:SetText(self.shown and Number(self.shown) or "?")
end

function Dice:Draw()
	local accent, other = self.host.Color("accent"), self.host.Palette()[1]
	local turn = self.turnOf
	local color = turn == "you" and accent or other
	if self.done then color = self.host.Color(self.done == "won" and "good" or "bad") end
	B.Tile(self.die, color, 0.55)
	B.Art(self.ring, "Ring", color, self.rolling and 1 or 0.6)
	self:DrawNumber()
	self.range:SetText(L["Roll 1 to %s"]:format(Number(self.limit or self.mode.from)))
	if self.done == "won" then
		self.turn:SetText(L["The murloc rolled a 1: you win this duel!"])
		self.turn:SetTextColor(unpack(self.host.Color("good")))
	elseif self.done == "lost" then
		self.turn:SetText(L["You rolled a 1: the murloc wins."])
		self.turn:SetTextColor(unpack(self.host.Color("bad")))
	elseif self.rolling then
		self.turn:SetText(self.rolling.who == "you" and L["You roll..."] or L["The murloc rolls..."])
		self.turn:SetTextColor(unpack(self.host.Color("body")))
	elseif turn == "you" then
		self.turn:SetText(L["Your roll: Space or a click."])
		self.turn:SetTextColor(unpack(accent))
	else
		self.turn:SetText(L["The murloc's roll."])
		self.turn:SetTextColor(unpack(self.host.Color("body")))
	end
	for i, line in ipairs(self.lines) do
		local entry = self.history[i]
		if entry then
			local text = entry.who == "you" and L["You: %s (1 to %s)"] or L["Murloc: %s (1 to %s)"]
			line:SetText(text:format(Number(entry.result), Number(entry.from)))
			line:SetAlpha(1 - (i - 1) * 0.13)
		else
			line:SetText("")
		end
	end
	local you, them = self.you, self.them
	you.plate:Paint(turn == "you" and accent or self.host.Color("secondary"), turn == "you" and 0.45 or 0.18)
	them.plate:Paint(turn == "them" and other or self.host.Color("secondary"), turn == "them" and 0.45 or 0.18)
	you.last:SetText(self.lastYou and L["Last roll: %s"]:format(Number(self.lastYou)) or "")
	them.last:SetText(self.lastThem and L["Last roll: %s"]:format(Number(self.lastThem)) or "")
end

-- A roll saved while it spun lands; a murloc that was about to roll rolls.
function Dice:Loaded()
	if type(self.rolling) ~= "table" then self.rolling = nil end
	if self.turnOf == "them" and not (self.wait or self.done or self.rolling) then
		self.wait = { left = THEIR_WAIT, what = "them" }
	end
end

M:RegisterGame({
	key = "dice", order = 130, group = "board",
	title = "Dice Duel", desc = "Roll against a murloc, each from 1 to the last roll; whoever rolls a 1 loses.",
	controls = Key("Space or a click: roll. P: pause."),
	icon = "Interface\\Icons\\INV_Misc_Dice_02",
	modes = MODES,
	Size = function() return WIDTH, HEIGHT end,
	New = New,
})
