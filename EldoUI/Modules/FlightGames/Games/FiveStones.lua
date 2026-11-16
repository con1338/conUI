-- EldoUI Flight Games: Five Stones. You and the opponent take turns placing
-- a stone on a board of 15 by 15. Five of yours in a row (across, down or
-- slanting) wins; a full board is a draw.
-- Written from scratch for EldoUI.
local _, E = ...
local M = E.FlightGames
local Key = E.Key
local L = E.L
local B = M.Board

local N, CELL = 15, 26
local TOP = 30
local WIDTH, HEIGHT = N * CELL, TOP + N * CELL
local THINK = 0.4
local MODES = {
	{ key = "easy", title = "Easy", defend = 0.5, noise = 400 },
	{ key = "normal", title = "Normal", defend = 0.85, noise = 40 },
	{ key = "hard", title = "Hard", defend = 1.0, noise = 0 },
}
local DIRS = { { 1, 0 }, { 0, 1 }, { 1, 1 }, { 1, -1 } }

local Stones = {}
Stones.__index = Stones
-- What a saved game keeps (the board, the score and the timers).
Stones.saveKeys = { "board", "turn", "moves", "result", "line", "last" }

local function ModeOf(mode)
	return mode and mode.defend and mode or MODES[2]
end

local function Index(x, y) return (y - 1) * N + x end
local function Inside(x, y) return x >= 1 and y >= 1 and x <= N and y <= N end

-- Five in a row through (x, y) for side v: the places, or nil.
local function Wins(board, x, y, v)
	for _, d in ipairs(DIRS) do
		local line = { Index(x, y) }
		for s = -1, 1, 2 do
			local cx, cy = x + d[1] * s, y + d[2] * s
			while Inside(cx, cy) and board[Index(cx, cy)] == v do
				line[#line + 1] = Index(cx, cy)
				cx, cy = cx + d[1] * s, cy + d[2] * s
			end
		end
		if #line >= 5 then return line end
	end
end
Stones.Wins = Wins

-- What a stone of side v at (x, y) would make, summed over the four lines:
-- longer runs and runs open at both ends weigh the most.
local WEIGHT = {
	[5] = { 1000000, 1000000, 1000000 },
	[4] = { 0, 2000, 50000 },
	[3] = { 0, 200, 3000 },
	[2] = { 0, 20, 200 },
	[1] = { 0, 2, 10 },
}
local function Worth(board, x, y, v)
	local total = 0
	for _, d in ipairs(DIRS) do
		local run, open = 1, 0
		for s = -1, 1, 2 do
			local cx, cy = x + d[1] * s, y + d[2] * s
			while Inside(cx, cy) and board[Index(cx, cy)] == v do
				run = run + 1
				cx, cy = cx + d[1] * s, cy + d[2] * s
			end
			if Inside(cx, cy) and board[Index(cx, cy)] == 0 then open = open + 1 end
		end
		total = total + WEIGHT[math.min(run, 5)][open + 1]
	end
	return total
end
Stones.Worth = Worth

local function New(host, mode)
	local game = setmetatable({ host = host, mode = ModeOf(mode) }, Stones)
	local area = host.area
	game.grid = B.Grid(area, N, N, CELL, { gap = 1 })
	game.grid.frame:SetPoint("TOPLEFT", area, "TOPLEFT", 0, -TOP)
	game.stones = {}
	for i = 1, N * N do
		local x, y = (i - 1) % N, math.floor((i - 1) / N)
		local stone = B.Dot(area, CELL - 6, nil, "ARTWORK")
		B.Place(stone, x * CELL + 3, TOP + y * CELL + 3, area)
		game.stones[i] = stone
	end
	game.rings = {}
	for i = 1, 5 do game.rings[i] = B.Sprite(area, CELL, CELL, "OVERLAY") end
	game.lastRing = B.Sprite(area, CELL, CELL, "OVERLAY")
	game.tally = B.Label(area, E.tokens.size.cardTitle, "body", "LEFT")
	game.tally:SetPoint("TOPLEFT", area, "TOPLEFT", 2, -6)
	game.prompt = B.Label(area, E.tokens.size.small, "secondary", "RIGHT")
	game.prompt:SetPoint("TOPRIGHT", area, "TOPLEFT", WIDTH - 2, -8)
	game.fx = B.Effects(area)
	return game
end

function Stones:Start()
	self.board = {}
	for i = 1, N * N do self.board[i] = 0 end
	self.turn, self.moves, self.result, self.line, self.last = 1, 0, nil, nil, nil
	self.think, self.ending = nil, nil
	self.fx:Clear()
	self.host.Score(0)
	self:Draw()
end

function Stones:Loaded()
	self.think = (self.turn == -1 and not self.result) and THINK or nil
	-- Saved inside the end delay: the result is decided, so it ends.
	if self.result then self.ending = 0.3 end
end

function Stones:Place(x, y, v)
	local i = Index(x, y)
	if self.result or self.board[i] ~= 0 then return false end
	self.board[i] = v
	self.last = i
	if v == 1 then
		self.moves = self.moves + 1
		self.host.Score(self.moves)
	end
	local color = self.host.FactionColor(v)
	self.fx:Burst((x - 0.5) * CELL, TOP + (y - 0.5) * CELL, color, CELL * 1.4, 0.35)
	self.host.Sound("turn")
	local line = Wins(self.board, x, y, v)
	local full = true
	for k = 1, N * N do
		if self.board[k] == 0 then full = false break end
	end
	if line then
		self.line = line
		self.result = v == 1 and "won" or "lost"
		for _, k in ipairs(line) do
			local lx, ly = (k - 1) % N, math.floor((k - 1) / N)
			self.fx:Sparks((lx + 0.5) * CELL, TOP + (ly + 0.5) * CELL, self.host.Color("gold"), 5, 70)
		end
		self.host.Sound(v == 1 and "best" or "over")
		self.ending = 1.4
	elseif full then
		self.result = "draw"
		self.ending = 1.0
	else
		self.turn = -v
		if self.turn == -1 then self.think = THINK end
	end
	self:Draw()
	return true
end

-- The opponent's stone: the empty square near the stones in play that does
-- the most for its own lines and against yours.
function Stones:Choose()
	local board, mode = self.board, self.mode
	local best, bestValue
	local any = false
	for y = 1, N do
		for x = 1, N do
			local i = Index(x, y)
			if board[i] ~= 0 then
				any = true
			else
				local near = false
				for dy = -2, 2 do
					for dx = -2, 2 do
						if Inside(x + dx, y + dy) and board[Index(x + dx, y + dy)] ~= 0 then near = true end
					end
				end
				if near then
					local value = Worth(board, x, y, -1) * 1.1 + Worth(board, x, y, 1) * mode.defend
					if mode.noise > 0 then value = value + self.host.Random(mode.noise) end
					if not bestValue or value > bestValue then best, bestValue = { x, y }, value end
				end
			end
		end
	end
	if not any or not best then return { (N + 1) / 2, (N + 1) / 2 } end
	return best
end

function Stones:Press(button, x, y)
	if button ~= "LeftButton" or not (x and y) or self.turn ~= 1 or self.result then return end
	local cx, cy = self.grid:CellAt(x, y, 0, TOP)
	if cx then self:Place(cx, cy, 1) end
end

function Stones:Update(dt)
	self.fx:Update(dt)
	if self.ending then
		self.ending = self.ending - dt
		if self.ending <= 0 then
			self.ending = nil
			self.host.Over(self.result == "won")
		end
		return
	end
	if self.think then
		self.think = self.think - dt
		if self.think <= 0 then
			self.think = nil
			local move = self:Choose()
			self:Place(move[1], move[2], -1)
		end
	end
end

function Stones:Summary()
	if not self.moves then return nil end
	return E:Plural(self.moves, "%d stone placed", "%d stones placed"):format(self.moves)
end

function Stones:Draw()
	local grid, palette, color = self.grid, self.host.Palette(), self.host.Color
	local bronze = E.tokens.palette.bronze
	for y = 1, N do
		for x = 1, N do
			local i = Index(x, y)
			local mid = (x == 8 and y == 8) or ((x == 4 or x == 12) and (y == 4 or y == 12))
			grid:Paint(x, y, bronze, mid and 0.42 or ((x + y) % 2 == 0 and 0.3 or 0.26))
			local v = self.board[i]
			local stone = self.stones[i]
			stone:SetShown(v ~= 0)
			if v ~= 0 then
				local c = self.host.FactionColor(v, palette)
				stone:SetVertexColor(c[1], c[2], c[3], 1)
			end
		end
	end
	for k, ring in ipairs(self.rings) do
		local i = self.line and self.line[k]
		ring:SetShown(i ~= nil)
		if i then
			B.Art(ring, "Ring", color("gold"), 1)
			B.Place(ring, (i - 1) % N * CELL, TOP + math.floor((i - 1) / N) * CELL, self.host.area)
		end
	end
	self.lastRing:SetShown(self.last ~= nil and not self.line)
	if self.last then
		B.Art(self.lastRing, "Ring", color("body"), 0.6)
		B.Place(self.lastRing, (self.last - 1) % N * CELL, TOP + math.floor((self.last - 1) / N) * CELL, self.host.area)
	end
	self.tally:SetText(L["Five in a row wins"])
	local text
	if self.result == "won" then
		text = L["Five in a row: you win!"]
	elseif self.result == "lost" then
		text = L["The %s got five in a row."]:format(self.host.FactionName(-1))
	elseif self.result == "draw" then
		text = L["The board is full: a draw."]
	elseif self.turn == 1 then
		text = L["Your move."]
	else
		text = L["The %s is thinking..."]:format(self.host.FactionName(-1))
	end
	self.prompt:SetText(text)
end

M:RegisterGame({
	key = "fivestones", order = 155, group = "board",
	title = "Five Stones", desc = "Place stones in turn against the other faction; five in a row wins.",
	controls = Key("Click an empty square. P: pause."),
	icon = "Interface\\Icons\\INV_Misc_Gem_Amethyst_02",
	modes = MODES, lower = true, unit = "moves",
	width = WIDTH, height = HEIGHT,
	New = New,
})
