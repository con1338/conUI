-- EldoUI Flight Games: Checkers. Pieces move one step forward on the dark
-- squares and capture by jumping over a Horde piece onto the empty square
-- behind it, again and again in one move when they can. A capture must be
-- taken when there is one. A piece that reaches the far row is crowned
-- and moves both ways. Take or block every Horde piece to win.
-- Written from scratch for EldoUI.
local _, E = ...
local M = E.FlightGames
local Key = E.Key
local L = E.L
local B = M.Board

local N, CELL = 8, 50
local TOP = 30
local WIDTH, HEIGHT = N * CELL, TOP + N * CELL
local THINK = 0.45
local QUIET = 80             -- moves in a row without a capture or a man moving: a draw
local MODES = {
	{ key = "easy", title = "Easy", depth = 2, noise = 30 },
	{ key = "normal", title = "Normal", depth = 4, noise = 6 },
	{ key = "hard", title = "Hard", depth = 5, noise = 0 },
}

local Checkers = {}
Checkers.__index = Checkers
-- What a saved game keeps (the board, the score and the timers).
Checkers.saveKeys = { "board", "turn", "result", "quiet", "taken", "last" }

local function ModeOf(mode)
	return mode and mode.depth and mode or MODES[2]
end

local function Index(x, y) return (y - 1) * N + x end
local function XY(i) return (i - 1) % N + 1, math.floor((i - 1) / N) + 1 end
local function Inside(x, y) return x >= 1 and y >= 1 and x <= N and y <= N end
local function Side(v) return v > 0 and 1 or v < 0 and -1 or 0 end

-- The ways a piece may go: you (1) move up the board, the Horde (-1) down;
-- a king (2 or -2) both ways.
local function Ways(v)
	if v == 2 or v == -2 then return { { 1, 1 }, { -1, 1 }, { 1, -1 }, { -1, -1 } } end
	local dy = v > 0 and -1 or 1
	return { { 1, dy }, { -1, dy } }
end

local function Crowns(v, y)
	return (v == 1 and y == 1) or (v == -1 and y == N)
end

-- Every jump chain from square i (board as it is, the piece lifted).
local function Jumps(board, i, v, path, caps, out)
	local x, y = XY(i)
	local any = false
	for _, d in ipairs(Ways(v)) do
		local mx, my, tx, ty = x + d[1], y + d[2], x + d[1] * 2, y + d[2] * 2
		if Inside(tx, ty) then
			local mid, to = Index(mx, my), Index(tx, ty)
			if Side(board[mid]) == -Side(v) and board[to] == 0 and not caps[mid] then
				any = true
				caps[mid] = true
				local p2 = { unpack(path) }
				p2[#p2 + 1] = to
				local list = {}
				for k in pairs(caps) do list[#list + 1] = k end
				if Crowns(v, ty) then
					out[#out + 1] = { from = path[1], to = to, path = p2, caps = list }
				else
					local saved = board[mid]
					board[mid] = 0
					local before = #out
					Jumps(board, to, v, p2, caps, out)
					board[mid] = saved
					if #out == before then out[#out + 1] = { from = path[1], to = to, path = p2, caps = list } end
				end
				caps[mid] = nil
			end
		end
	end
	return any
end

-- True when a move's path starts with the landing squares picked so far.
local function Follows(m, route)
	for k, square in ipairs(route) do
		if m.path[k + 1] ~= square then return false end
	end
	return true
end

-- Every legal move for side s: captures when there are any, else steps.
local function Moves(board, s)
	local captures, steps = {}, {}
	for i = 1, N * N do
		local v = board[i]
		if Side(v) == s then
			board[i] = 0
			Jumps(board, i, v, { i }, {}, captures)
			board[i] = v
			if #captures == 0 then
				local x, y = XY(i)
				for _, d in ipairs(Ways(v)) do
					local tx, ty = x + d[1], y + d[2]
					if Inside(tx, ty) and board[Index(tx, ty)] == 0 then
						steps[#steps + 1] = { from = i, to = Index(tx, ty), path = { i, Index(tx, ty) }, caps = {} }
					end
				end
			end
		end
	end
	return #captures > 0 and captures or steps
end
Checkers.Moves = Moves

-- Plays a move; returns what undoes it.
local function Apply(board, m)
	local v = board[m.from]
	local undo = { from = m.from, to = m.to, v = v, caps = {} }
	for _, c in ipairs(m.caps) do
		undo.caps[#undo.caps + 1] = { c, board[c] }
		board[c] = 0
	end
	board[m.from] = 0
	local _, ty = XY(m.to)
	if Crowns(v, ty) then v = v * 2 end
	board[m.to] = v
	return undo
end

local function Undo(board, undo)
	board[undo.to] = 0
	board[undo.from] = undo.v
	for _, c in ipairs(undo.caps) do board[c[1]] = c[2] end
end

local function Value(board, s)
	local total = 0
	for i = 1, N * N do
		local v = board[i]
		if v ~= 0 then
			local _, y = XY(i)
			local worth = (v == 2 or v == -2) and 175 or 100 + (v > 0 and (N - y) or (y - 1)) * 3
			total = total + worth * Side(v) * s
		end
	end
	return total
end

local function Search(board, depth, alpha, beta, s)
	B.Tick()
	local moves = Moves(board, s)
	if #moves == 0 then return -10000 - depth end
	if depth == 0 then return Value(board, s) end
	local best = -math.huge
	for _, m in ipairs(moves) do
		local undo = Apply(board, m)
		local value = -Search(board, depth - 1, -beta, -alpha, -s)
		Undo(board, undo)
		if value > best then best = value end
		if best > alpha then alpha = best end
		if alpha >= beta then break end
	end
	return best
end

local function New(host, mode)
	local game = setmetatable({ host = host, mode = ModeOf(mode) }, Checkers)
	local area = host.area
	game.grid = B.Grid(area, N, N, CELL, { gap = 0, flat = true })
	game.grid.frame:SetPoint("TOPLEFT", area, "TOPLEFT", 0, -TOP)
	game.pieces = {}
	for i = 1, N * N do
		local x, y = XY(i)
		local piece = { disc = B.Dot(area, CELL - 10, nil, "ARTWORK"), ring = B.Sprite(area, CELL - 2, CELL - 2, "OVERLAY"),
			crown = B.Sprite(area, CELL - 22, CELL - 22, "OVERLAY") }
		B.Place(piece.disc, (x - 1) * CELL + 5, TOP + (y - 1) * CELL + 5, area)
		B.Place(piece.ring, (x - 1) * CELL + 1, TOP + (y - 1) * CELL + 1, area)
		B.Place(piece.crown, (x - 1) * CELL + 11, TOP + (y - 1) * CELL + 11, area)
		piece.target = B.Dot(area, 14, nil, "OVERLAY")
		B.Place(piece.target, (x - 1) * CELL + CELL / 2 - 7, TOP + (y - 1) * CELL + CELL / 2 - 7, area)
		game.pieces[i] = piece
	end
	game.tally = B.Label(area, E.tokens.size.cardTitle, "body", "LEFT")
	game.tally:SetPoint("TOPLEFT", area, "TOPLEFT", 2, -6)
	game.prompt = B.Label(area, E.tokens.size.small, "secondary", "RIGHT")
	game.prompt:SetPoint("TOPRIGHT", area, "TOPLEFT", WIDTH - 2, -8)
	game.fx = B.Effects(area)
	return game
end

function Checkers:Start()
	self.board = {}
	for i = 1, N * N do
		local x, y = XY(i)
		local dark = (x + y) % 2 == 1
		self.board[i] = (dark and y <= 3) and -1 or (dark and y >= 6) and 1 or 0
	end
	self.turn, self.result, self.quiet, self.taken, self.last = 1, nil, 0, 0, nil
	self.picked, self.route, self.think, self.ending, self.thread = nil, nil, nil, nil, nil
	self.host.Score(0)
	self:Draw()
end

function Checkers:Loaded()
	self.picked, self.route, self.thread = nil, nil, nil
	self.think = (self.turn == -1 and not self.result) and THINK or nil
	-- Saved inside the end delay: the result is decided, so it ends.
	if self.result then self.ending = 0.3 end
end

function Checkers:Play(m)
	local v = self.board[m.from]
	local man = v == 1 or v == -1
	Apply(self.board, m)
	self.last = m.to
	for _, c in ipairs(m.caps) do
		local x, y = XY(c)
		self.fx:Burst((x - 0.5) * CELL, TOP + (y - 0.5) * CELL, self.host.Color(v > 0 and "good" or "bad"), CELL * 1.4, 0.4)
		self.fx:Sparks((x - 0.5) * CELL, TOP + (y - 0.5) * CELL, self.host.Color("gold"), 6)
	end
	if v > 0 then
		self.taken = self.taken + #m.caps
		self.host.Score(self.taken)
	end
	self.quiet = (#m.caps > 0 or man) and 0 or self.quiet + 1
	self.host.Sound(#m.caps > 0 and "point" or "turn")
	self.picked, self.route = nil, nil
	local next = -Side(v)
	if #Moves(self.board, next) == 0 then
		self.result = next == -1 and "won" or "lost"
		self.ending = 1.2
	elseif self.quiet >= QUIET then
		self.result = "draw"
		self.ending = 1.0
	else
		self.turn = next
		if next == -1 then self.think = THINK end
	end
	self:Draw()
end

-- The Horde's move, searched on a copy of the board.
function Checkers:Choose()
	local best, bestValue
	local board = B.Copy(self.board)
	for _, m in ipairs(Moves(board, -1)) do
		local undo = Apply(board, m)
		local value = -Search(board, self.mode.depth - 1, -math.huge, math.huge, 1)
		Undo(board, undo)
		if self.mode.noise > 0 then value = value + self.host.Random(self.mode.noise) end
		if not bestValue or value > bestValue then best, bestValue = m, value end
	end
	return best
end

function Checkers:Press(button, x, y)
	if button ~= "LeftButton" or not (x and y) or self.turn ~= 1 or self.result then return end
	local cx, cy = self.grid:CellAt(x, y, 0, TOP)
	if not cx then return end
	local i = Index(cx, cy)
	local moves = Moves(self.board, 1)
	if self.picked then
		-- Two capture routes can end on the same square: then a click on
		-- the next landing square picks the way, one jump at a time.
		local route = self.route or {}
		local finals, hops = {}, {}
		for _, m in ipairs(moves) do
			if m.from == self.picked and Follows(m, route) then
				if m.to == i then finals[#finals + 1] = m end
				if m.path[#route + 2] == i then hops[#hops + 1] = m end
			end
		end
		if #finals == 1 then
			self:Play(finals[1])
			return
		end
		for _, m in ipairs(hops) do
			if #m.path == #route + 2 then
				self:Play(m)
				return
			end
		end
		if #hops > 0 or #finals > 1 then
			if #hops > 0 then
				route[#route + 1] = i
				self.route = route
			end
			self:Draw()
			return
		end
	end
	local can = false
	for _, m in ipairs(moves) do if m.from == i then can = true end end
	self.picked = can and i ~= self.picked and i or nil
	self.route = nil
	if not can and Side(self.board[i]) == 1 and #moves > 0 and #moves[1].caps > 0 then
		self.fx:Float((cx - 0.5) * CELL, TOP + (cy - 0.5) * CELL, L["A capture must be taken."], self.host.Color("warn"), E.tokens.size.small)
	end
	self:Draw()
end

function Checkers:Update(dt)
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
			local done, m = B.Pump(self.thread)
			if done then
				self.think, self.thread = nil, nil
				if m then self:Play(m) end
			end
		end
	end
end

function Checkers:Summary()
	if not self.taken then return nil end
	return E:Plural(self.taken, "%d Horde piece taken", "%d Horde pieces taken"):format(self.taken)
end

function Checkers:Draw()
	local grid, palette, color = self.grid, self.host.Palette(), self.host.Color
	local bronze = E.tokens.palette.bronze
	local targets, movable = {}, {}
	if self.turn == 1 and not self.result then
		for _, m in ipairs(Moves(self.board, 1)) do
			movable[m.from] = true
			if m.from == self.picked and Follows(m, self.route or {}) then
				targets[m.to] = true
				local hop = m.path[#(self.route or {}) + 2]
				if hop then targets[hop] = true end
			end
		end
	end
	local you, them = 0, 0
	for i = 1, N * N do
		local x, y = XY(i)
		local dark = (x + y) % 2 == 1
		grid:Paint(x, y, dark and bronze or color("body"), dark and 0.45 or 0.12)
		local v = self.board[i]
		local piece = self.pieces[i]
		local on = v ~= 0
		piece.disc:SetShown(on)
		piece.crown:SetShown(v == 2 or v == -2)
		if on then
			local c = v > 0 and palette[7] or palette[6]
			piece.disc:SetVertexColor(c[1], c[2], c[3], 1)
			if v == 2 or v == -2 then B.Art(piece.crown, "ChessKing", color("gold"), 1) end
			if v > 0 then you = you + 1 else them = them + 1 end
		end
		local ring = (self.picked == i and color("gold")) or (movable[i] and not self.picked and color("good")) or (self.last == i and color("secondary"))
		piece.ring:SetShown(ring and true or false)
		if ring then B.Art(piece.ring, "Ring", ring, self.picked == i and 1 or 0.55) end
		piece.target:SetShown(targets[i] or false)
		if targets[i] then
			local g = color("gold")
			piece.target:SetVertexColor(g[1], g[2], g[3], 0.85)
		end
	end
	self.tally:SetText(L["Alliance %d, Horde %d"]:format(you, them))
	local text
	if self.result == "won" then
		text = L["You win!"]
	elseif self.result == "lost" then
		text = L["The Horde wins."]
	elseif self.result == "draw" then
		text = L["A draw."]
	elseif self.turn == 1 then
		text = L["Your move."]
	else
		text = L["The Horde is thinking..."]
	end
	self.prompt:SetText(text)
end

M:RegisterGame({
	key = "checkers", order = 160, group = "board",
	title = "Checkers", desc = "Jump and take the Horde's pieces; crown yours on the far row.",
	controls = Key("Click a piece, then where it goes. P: pause."),
	icon = "Interface\\Icons\\INV_Misc_Gem_Pearl_05",
	modes = MODES,
	width = WIDTH, height = HEIGHT,
	New = New,
})
