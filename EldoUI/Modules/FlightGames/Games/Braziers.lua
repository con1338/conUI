-- EldoUI Flight Games: Light the Braziers. A touch on a brazier turns it
-- and the braziers beside it (up, down, left and right) on or off. Light
-- every one in as few touches as you can. Every board can be solved.
-- Written from scratch for EldoUI; the flames are the game's own icons.
local _, E = ...
local M = E.FlightGames
local Key = E.Key
local L = E.L
local B = M.Board

local MODES = {
	{ key = "four", title = "4 x 4", size = 4, cell = 84 },
	{ key = "five", title = "5 x 5", size = 5, cell = 72 },
	{ key = "six", title = "6 x 6", size = 6, cell = 62 },
}
local FLAME = "Interface\\Icons\\Spell_Fire_Immolation"
local DIRS = { UP = { 0, -1 }, W = { 0, -1 }, DOWN = { 0, 1 }, S = { 0, 1 }, LEFT = { -1, 0 }, A = { -1, 0 }, RIGHT = { 1, 0 }, D = { 1, 0 } }

local Braziers = {}
Braziers.__index = Braziers
-- What a saved game keeps (the board, the score and the timers).
Braziers.saveKeys = { "lit", "moves", "cx", "cy" }

local function ModeOf(mode)
	return mode and mode.size and mode or MODES[2]
end

local function New(host, mode)
	mode = ModeOf(mode)
	local game = setmetatable({ host = host, mode = mode }, Braziers)
	game.grid = B.Grid(host.area, mode.size, mode.size, mode.cell, { gap = 8 })
	game.grid.frame:SetPoint("TOPLEFT")
	game.cursor = B.Sprite(game.grid.frame, mode.cell, mode.cell, "OVERLAY")
	game.cursor:SetDrawLayer("OVERLAY", 7)
	game.fx = B.Effects(host.area)
	return game
end

function Braziers:Index(x, y) return (y - 1) * self.mode.size + x end

function Braziers:Flip(x, y)
	local n = self.mode.size
	for _, d in ipairs({ { 0, 0 }, { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
		local nx, ny = x + d[1], y + d[2]
		if nx >= 1 and ny >= 1 and nx <= n and ny <= n then
			local i = self:Index(nx, ny)
			self.lit[i] = not self.lit[i]
		end
	end
end

function Braziers:Start()
	local n = self.mode.size
	self.lit = {}
	for i = 1, n * n do self.lit[i] = true end
	-- Touches from the solved board: the board can always be solved.
	repeat
		for _ = 1, n * n do self:Flip(self.host.Random(n), self.host.Random(n)) end
	until not self:Solved()
	self.moves, self.cx, self.cy = 0, math.ceil(n / 2), math.ceil(n / 2)
	self.host.Score(0)
	self:Draw()
end

function Braziers:Solved()
	for i = 1, self.mode.size ^ 2 do
		if not self.lit[i] then return false end
	end
	return true
end

function Braziers:Touch(x, y)
	self:Flip(x, y)
	self.moves = self.moves + 1
	self.host.Score(self.moves)
	local cell = self.mode.cell
	self.fx:Burst((x - 0.5) * cell, (y - 0.5) * cell, self.host.Color("gold"), cell * 1.6, 0.35)
	self.host.Sound("turn")
	self:Draw()
	if self:Solved() then
		local n = self.mode.size
		for i = 1, n do
			self.fx:Sparks((i - 0.5) * cell, (i - 0.5) * cell, self.host.Color("gold"), 8, 150)
		end
		self.host.Sound("point")
		self.host.Over(true)
	end
end

function Braziers:Key(key)
	local d = DIRS[key]
	if d then
		local n = self.mode.size
		self.cx = math.max(1, math.min(n, self.cx + d[1]))
		self.cy = math.max(1, math.min(n, self.cy + d[2]))
		self:Draw()
		return true
	end
	if key == "SPACE" or key == "ENTER" then
		self:Touch(self.cx, self.cy)
		return true
	end
	return false
end

function Braziers:Press(button, x, y)
	if button ~= "LeftButton" or not (x and y) then return end
	local cx, cy = self.grid:CellAt(x, y)
	if cx then
		self.cx, self.cy = cx, cy
		self:Touch(cx, cy)
	end
end

function Braziers:Update(dt)
	self.fx:Update(dt)
end

function Braziers:Summary()
	if not self.moves then return nil end
	return E:Plural(self.moves, "Lit in %d touch", "Lit in %d touches"):format(self.moves)
end

function Braziers:Draw()
	local grid, n = self.grid, self.mode.size
	local warm, cold = self.host.Palette()[2], self.host.Color("dim")
	for y = 1, n do
		for x = 1, n do
			local on = self.lit[self:Index(x, y)]
			local icon = grid:Icon(x, y, FLAME, on and warm or cold)
			icon:SetDesaturated(not on)
			icon:SetAlpha(on and 1 or 0.35)
		end
	end
	local cell = self.mode.cell
	B.Art(self.cursor, "Ring", self.host.Color("accent"), 0.9)
	B.Place(self.cursor, (self.cx - 1) * cell, (self.cy - 1) * cell, grid.frame)
end

M:RegisterGame({
	key = "braziers", order = 76, group = "puzzle",
	title = "Light the Braziers", desc = "Each touch turns a brazier and its neighbors; light them all.",
	controls = Key("Click a brazier, or arrow keys and Space. P: pause."),
	icon = FLAME,
	modes = MODES, lower = true, unit = "moves",
	Size = function(mode) mode = ModeOf(mode) return mode.size * mode.cell, mode.size * mode.cell end,
	New = New,
})
