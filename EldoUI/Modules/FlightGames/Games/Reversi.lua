-- EldoUI Flight Games: Reversi. Place a stone so that it closes one or
-- more lines of the Horde's stones between it and another of yours; the
-- closed stones turn to your side. No move, no turn. When the board is
-- full or nobody can move, the side with more stones wins.
-- Written from scratch for EldoUI.
local _, E = ...
local M = E.FlightGames
local Key = E.Key
local L = E.L
local B = M.Board

local N, CELL = 8, 50
local TOP = 30
local WIDTH, HEIGHT = N * CELL, TOP + N * CELL
local THINK = 0.5
local MODES = {
	{ key = "easy", title = "Easy", depth = 1, noise = 30 },
	{ key = "normal", title = "Normal", depth = 2, noise = 6 },
	{ key = "hard", title = "Hard", depth = 4, noise = 0 },
}
-- How much each square is worth to hold: corners most, the squares next
-- to a corner least.
local WEIGHT = {
	100, -20, 10, 5, 5, 10, -20, 100,
	-20, -40, -2, -2, -2, -2, -40, -20,
	10, -2, 1, 1, 1, 1, -2, 10,
	5, -2, 1, 0, 0, 1, -2, 5,
	5, -2, 1, 0, 0, 1, -2, 5,
	10, -2, 1, 1, 1, 1, -2, 10,
	-20, -40, -2, -2, -2, -2, -40, -20,
	100, -20, 10, 5, 5, 10, -20, 100,
}
local DIRS8 = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 }, { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }

local Reversi = {}
Reversi.__index = Reversi
-- What a saved game keeps (the board, the score and the timers).
Reversi.saveKeys = { "board", "turn", "result", "last" }

local function ModeOf(mode)
	return mode and mode.depth and mode or MODES[2]
end

local function Index(x, y) return (y - 1) * N + x end

-- The stones a move at (x, y) by side v turns, or an empty list.
local function Flips(board, x, y, v)
	local out = {}
	if board[Index(x, y)] ~= 0 then return out end
	for _, d in ipairs(DIRS8) do
		local run = {}
		local cx, cy = x + d[1], y + d[2]
		while cx >= 1 and cy >= 1 and cx <= N and cy <= N and board[Index(cx, cy)] == -v do
			run[#run + 1] = Index(cx, cy)
			cx, cy = cx + d[1], cy + d[2]
		end
		if #run > 0 and cx >= 1 and cy >= 1 and cx <= N and cy <= N and board[Index(cx, cy)] == v then
			for _, i in ipairs(run) do out[#out + 1] = i end
		end
	end
	return out
end
Reversi.Flips = Flips

local function Moves(board, v)
	local out = {}
	for y = 1, N do
		for x = 1, N do
			local flips = Flips(board, x, y, v)
			if #flips > 0 then out[#out + 1] = { x = x, y = y, flips = flips } end
		end
	end
	return out
end
Reversi.Moves = Moves

local function Apply(board, move, v)
	board[Index(move.x, move.y)] = v
	for _, i in ipairs(move.flips) do board[i] = v end
end

local function Undo(board, move, v)
	board[Index(move.x, move.y)] = 0
	for _, i in ipairs(move.flips) do board[i] = -v end
end

local function Value(board, v)
	local total = 0
	for i = 1, N * N do
		local s = board[i]
		if s ~= 0 then total = total + WEIGHT[i] * s * v end
	end
	return total
end

local function Search(board, depth, alpha, beta, v)
	B.Tick()
	if depth == 0 then return Value(board, v) end
	local moves = Moves(board, v)
	if #moves == 0 then
		if #Moves(board, -v) == 0 then
			local count = 0
			for i = 1, N * N do count = count + board[i] * v end
			return count * 1000
		end
		return -Search(board, depth - 1, -beta, -alpha, -v)
	end
	local best = -math.huge
	for _, move in ipairs(moves) do
		Apply(board, move, v)
		local value = -Search(board, depth - 1, -beta, -alpha, -v)
		Undo(board, move, v)
		if value > best then best = value end
		if best > alpha then alpha = best end
		if alpha >= beta then break end
	end
	return best
end

local function New(host, mode)
	local game = setmetatable({ host = host, mode = ModeOf(mode) }, Reversi)
	local area = host.area
	game.grid = B.Grid(area, N, N, CELL, { gap = 2 })
	game.grid.frame:SetPoint("TOPLEFT", area, "TOPLEFT", 0, -TOP)
	game.stones, game.hints = {}, {}
	for i = 1, N * N do
		local x, y = (i - 1) % N, math.floor((i - 1) / N)
		local stone = B.Dot(area, CELL - 12, nil, "ARTWORK")
		B.Place(stone, x * CELL + 6, TOP + y * CELL + 6, area)
		game.stones[i] = stone
		local hint = B.Dot(area, 12, nil, "ARTWORK")
		B.Place(hint, x * CELL + CELL / 2 - 6, TOP + y * CELL + CELL / 2 - 6, area)
		game.hints[i] = hint
	end
	game.lastRing = B.Sprite(area, CELL - 4, CELL - 4, "OVERLAY")
	game.tally = B.Label(area, E.tokens.size.cardTitle, "body", "LEFT")
	game.tally:SetPoint("TOPLEFT", area, "TOPLEFT", 2, -6)
	game.prompt = B.Label(area, E.tokens.size.small, "secondary", "RIGHT")
	game.prompt:SetPoint("TOPRIGHT", area, "TOPLEFT", WIDTH - 2, -8)
	game.fx = B.Effects(area)
	return game
end

function Reversi:Start()
	self.board = {}
	for i = 1, N * N do self.board[i] = 0 end
	self.board[Index(4, 4)], self.board[Index(5, 5)] = -1, -1
	self.board[Index(5, 4)], self.board[Index(4, 5)] = 1, 1
	self.turn, self.result, self.last, self.think, self.ending, self.thread = 1, nil, nil, nil, nil, nil
	self.host.Score(2)
	self:Draw()
end

function Reversi:Loaded()
	self.thread = nil
	self.think = (self.turn == -1 and not self.result) and THINK or nil
	-- Saved inside the end delay: the result is decided, so it ends.
	if self.result then self.ending = 0.3 end
end

function Reversi:Count()
	local you, them = 0, 0
	for i = 1, N * N do
		if self.board[i] == 1 then you = you + 1 elseif self.board[i] == -1 then them = them + 1 end
	end
	return you, them
end

function Reversi:Play(move, v)
	Apply(self.board, move, v)
	self.last = Index(move.x, move.y)
	local color = v == 1 and self.host.Palette()[7] or self.host.Palette()[6]
	for _, i in ipairs(move.flips) do
		local x, y = (i - 1) % N, math.floor((i - 1) / N)
		self.fx:Burst((x + 0.5) * CELL, TOP + (y + 0.5) * CELL, color, CELL, 0.35)
	end
	self.host.Sound("turn")
	local you = self:Count()
	self.host.Score(you)
	self:NextTurn(-v)
end

-- Whose turn it is now: a side with no move passes; nobody moving ends it.
function Reversi:NextTurn(v)
	if #Moves(self.board, v) > 0 then
		self.turn = v
	elseif #Moves(self.board, -v) > 0 then
		self.turn = -v
		self.fx:Float(WIDTH / 2, TOP + N * CELL / 2, v == 1 and L["You have no move: the Horde goes again."] or L["The Horde has no move."],
			self.host.Color("warn"), E.tokens.size.small)
	else
		local you, them = self:Count()
		self.result = you > them and "won" or you < them and "lost" or "draw"
		self.host.Sound(self.result == "won" and "point" or "over")
		self.ending = 1.2
		self:Draw()
		return
	end
	if self.turn == -1 then self.think = THINK end
	self:Draw()
end

-- The Horde's move, searched on a copy of the board.
function Reversi:Choose()
	local board = B.Copy(self.board)
	local moves = Moves(board, -1)
	local best, bestValue
	for _, move in ipairs(moves) do
		Apply(board, move, -1)
		local value = -Search(board, self.mode.depth - 1, -math.huge, math.huge, 1)
		Undo(board, move, -1)
		if self.mode.noise > 0 then value = value + self.host.Random(self.mode.noise) end
		if not bestValue or value > bestValue then best, bestValue = move, value end
	end
	return best
end

function Reversi:Press(button, x, y)
	if button ~= "LeftButton" or not (x and y) or self.turn ~= 1 or self.result then return end
	local cx, cy = self.grid:CellAt(x, y, 0, TOP)
	if not cx then return end
	local flips = Flips(self.board, cx, cy, 1)
	if #flips == 0 then return end
	self:Play({ x = cx, y = cy, flips = flips }, 1)
end

function Reversi:Update(dt)
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
			-- The search runs a few milliseconds a frame until it is done.
			self.thread = self.thread or B.Think(function() return self:Choose() end)
			local done, move = B.Pump(self.thread)
			if done then
				self.think, self.thread = nil, nil
				if move then self:Play(move, -1) end
			end
		end
	end
end

function Reversi:Summary()
	if not self.board then return nil end
	local you, them = self:Count()
	return E:Plural(you, "%d stone to %d", "%d stones to %d"):format(you, them)
end

function Reversi:Draw()
	local grid, palette, color = self.grid, self.host.Palette(), self.host.Color
	local yours = self.turn == 1 and not self.result
	local legal = {}
	if yours then
		for _, move in ipairs(Moves(self.board, 1)) do legal[Index(move.x, move.y)] = true end
	end
	for y = 1, N do
		for x = 1, N do
			local i = Index(x, y)
			grid:Paint(x, y, palette[3], (x + y) % 2 == 0 and 0.4 or 0.34)
			local v = self.board[i]
			local stone = self.stones[i]
			stone:SetShown(v ~= 0)
			if v ~= 0 then
				local c = v == 1 and palette[7] or palette[6]
				stone:SetVertexColor(c[1], c[2], c[3], 1)
			end
			local hint = self.hints[i]
			hint:SetShown(legal[i] or false)
			if legal[i] then
				local c = palette[7]
				hint:SetVertexColor(c[1], c[2], c[3], 0.55)
			end
		end
	end
	self.lastRing:SetShown(self.last ~= nil)
	if self.last then
		local x, y = (self.last - 1) % N, math.floor((self.last - 1) / N)
		B.Art(self.lastRing, "Ring", color("gold"), 0.8)
		B.Place(self.lastRing, x * CELL + 2, TOP + y * CELL + 2, self.host.area)
	end
	local you, them = self:Count()
	self.tally:SetText(L["Alliance %d, Horde %d"]:format(you, them))
	local text
	if self.result == "won" then
		text = L["You win!"]
	elseif self.result == "lost" then
		text = L["The Horde wins."]
	elseif self.result == "draw" then
		text = L["A draw."]
	elseif yours then
		text = L["Your move."]
	else
		text = L["The Horde is thinking..."]
	end
	self.prompt:SetText(text)
end

M:RegisterGame({
	key = "reversi", order = 150, group = "board",
	title = "Reversi", desc = "Close lines of Horde stones between yours to turn them; most stones wins.",
	controls = Key("Click a square with a dot. P: pause."),
	icon = "Interface\\Icons\\INV_Misc_Gem_Pearl_04",
	modes = MODES,
	width = WIDTH, height = HEIGHT,
	New = New,
})
