-- EldoUI Flight Games: Mill. You and the opponent each have nine pieces.
-- First place them one by one on the 24 points of the board, then move
-- them along the lines to a free neighbor. Three of yours in a row on one
-- line make a mill and take one of the other side's pieces (a piece in a
-- mill only when all of them are). With three pieces left a side may jump
-- anywhere. A side with two pieces, or with no move, loses.
-- Written from scratch for EldoUI.
local _, E = ...
local M = E.FlightGames
local Key = E.Key
local L = E.L
local B = M.Board

local STEP, MARGIN = 58, 30
local TOP = 34
local WIDTH = MARGIN * 2 + 6 * STEP
local HEIGHT = TOP + MARGIN * 2 + 6 * STEP
local THINK = 0.5
local QUIET = 60               -- moves in a row without a mill once all are placed: a draw
local MODES = {
	{ key = "easy", title = "Easy", depth = 1, noise = 40 },
	{ key = "normal", title = "Normal", depth = 2, noise = 8 },
	{ key = "hard", title = "Hard", depth = 3, noise = 0 },
}
-- The points, ring by ring (outer, middle, inner), clockwise from the top
-- left corner, as places on a 7 x 7 grid.
local POINTS = {}
for ring, d in ipairs({ 0, 1, 2 }) do
	local lo, hi, mid = d, 6 - d, 3
	for _, p in ipairs({ { lo, lo }, { mid, lo }, { hi, lo }, { hi, mid }, { hi, hi }, { mid, hi }, { lo, hi }, { lo, mid } }) do
		POINTS[#POINTS + 1] = { x = p[1], y = p[2], ring = ring }
	end
end
local function P(ring, k) return (ring - 1) * 8 + ((k - 1) % 8) + 1 end
local NEXT, MILLS = {}, {}
for ring = 1, 3 do
	for k = 1, 8 do
		local i = P(ring, k)
		NEXT[i] = { P(ring, k - 1 + 8), P(ring, k + 1) }
		if k % 2 == 0 then
			if ring > 1 then table.insert(NEXT[i], P(ring - 1, k)) end
			if ring < 3 then table.insert(NEXT[i], P(ring + 1, k)) end
		end
	end
	for _, k in ipairs({ 1, 3, 5, 7 }) do MILLS[#MILLS + 1] = { P(ring, k), P(ring, k + 1), P(ring, k + 2) } end
end
for _, k in ipairs({ 2, 4, 6, 8 }) do MILLS[#MILLS + 1] = { P(1, k), P(2, k), P(3, k) } end
local MILLS_AT = {}
for _, mill in ipairs(MILLS) do
	for _, i in ipairs(mill) do
		MILLS_AT[i] = MILLS_AT[i] or {}
		table.insert(MILLS_AT[i], mill)
	end
end

local Mill = {}
Mill.__index = Mill
-- What a saved game keeps (the board, the score and the timers).
Mill.saveKeys = { "board", "hand", "turn", "result", "taking", "quiet", "last", "taken" }
Mill.NEXT, Mill.MILLS = NEXT, MILLS

local function ModeOf(mode)
	return mode and mode.depth and mode or MODES[2]
end

local function InMill(board, i)
	local v = board[i]
	if v == 0 then return false end
	for _, mill in ipairs(MILLS_AT[i]) do
		if board[mill[1]] == v and board[mill[2]] == v and board[mill[3]] == v then return true end
	end
	return false
end
Mill.InMill = InMill

local function Count(board, v)
	local n = 0
	for i = 1, 24 do if board[i] == v then n = n + 1 end end
	return n
end

-- The pieces of side v that may be taken.
local function Takeable(board, v)
	local free, all = {}, {}
	for i = 1, 24 do
		if board[i] == v then
			all[#all + 1] = i
			if not InMill(board, i) then free[#free + 1] = i end
		end
	end
	return #free > 0 and free or all
end
Mill.Takeable = Takeable

-- Every move of side v: { from (nil while placing), to, take (or nil) }.
local function Moves(board, hand, v)
	local steps = {}
	if hand[v] > 0 then
		for i = 1, 24 do
			if board[i] == 0 then steps[#steps + 1] = { to = i } end
		end
	else
		local flying = Count(board, v) == 3
		for i = 1, 24 do
			if board[i] == v then
				if flying then
					for j = 1, 24 do
						if board[j] == 0 then steps[#steps + 1] = { from = i, to = j } end
					end
				else
					for _, j in ipairs(NEXT[i]) do
						if board[j] == 0 then steps[#steps + 1] = { from = i, to = j } end
					end
				end
			end
		end
	end
	local out = {}
	for _, step in ipairs(steps) do
		if step.from then board[step.from] = 0 end
		board[step.to] = v
		if InMill(board, step.to) then
			for _, t in ipairs(Takeable(board, -v)) do out[#out + 1] = { from = step.from, to = step.to, take = t } end
		else
			out[#out + 1] = step
		end
		board[step.to] = 0
		if step.from then board[step.from] = v end
	end
	return out
end
Mill.Moves = Moves

local function Apply(board, hand, m, v)
	if m.from then board[m.from] = 0 else hand[v] = hand[v] - 1 end
	board[m.to] = v
	if m.take then board[m.take] = 0 end
end

local function Undo(board, hand, m, v)
	if m.take then board[m.take] = -v end
	board[m.to] = 0
	if m.from then board[m.from] = v else hand[v] = hand[v] + 1 end
end

-- Lost for side v: fewer than three pieces in all, or no move.
local function Lost(board, hand, v)
	if Count(board, v) + hand[v] < 3 then return true end
	return #Moves(board, hand, v) == 0
end
Mill.Lost = Lost

local function Value(board, hand, v)
	local mine, theirs = Count(board, v) + hand[v], Count(board, -v) + hand[-v]
	local open = 0
	for _, mill in ipairs(MILLS) do
		local a, b = 0, 0
		for _, i in ipairs(mill) do
			if board[i] == v then a = a + 1 elseif board[i] == -v then b = b + 1 end
		end
		if a == 2 and b == 0 then open = open + 1 elseif b == 2 and a == 0 then open = open - 1 end
	end
	return (mine - theirs) * 100 + open * 12
end

local function Search(board, hand, depth, alpha, beta, v)
	B.Tick()
	if Lost(board, hand, v) then return -10000 - depth end
	if depth == 0 then return Value(board, hand, v) end
	local best = -math.huge
	for _, m in ipairs(Moves(board, hand, v)) do
		Apply(board, hand, m, v)
		local value = -Search(board, hand, depth - 1, -beta, -alpha, -v)
		Undo(board, hand, m, v)
		if value > best then best = value end
		if best > alpha then alpha = best end
		if alpha >= beta then break end
	end
	return best
end

local function Spot(i)
	local p = POINTS[i]
	return MARGIN + p.x * STEP, TOP + MARGIN + p.y * STEP
end

local function New(host, mode)
	local game = setmetatable({ host = host, mode = ModeOf(mode) }, Mill)
	local area = host.area
	game.back = B.Slab(area, WIDTH, HEIGHT - TOP, "BACKGROUND")
	game.back:Place(0, TOP)
	game.lines = {}
	local function Line(x1, y1, x2, y2)
		local tex = B.Sprite(area, math.max(4, x2 - x1 + 4), math.max(4, y2 - y1 + 4), "BORDER")
		B.Place(tex, x1 - 2, y1 - 2, area)
		game.lines[#game.lines + 1] = tex
	end
	for ring = 1, 3 do
		local x1, y1 = Spot(P(ring, 1))
		local x2, y2 = Spot(P(ring, 5))
		Line(x1, y1, x2, y1)
		Line(x1, y2, x2, y2)
		Line(x1, y1, x1, y2)
		Line(x2, y1, x2, y2)
	end
	for _, k in ipairs({ 2, 4, 6, 8 }) do
		local x1, y1 = Spot(P(1, k))
		local x2, y2 = Spot(P(3, k))
		Line(math.min(x1, x2), math.min(y1, y2), math.max(x1, x2), math.max(y1, y2))
	end
	game.holes, game.pieces, game.rings = {}, {}, {}
	for i = 1, 24 do
		local x, y = Spot(i)
		local hole = B.Dot(area, 14, nil, "ARTWORK")
		B.Place(hole, x - 7, y - 7, area)
		game.holes[i] = hole
		local piece = B.Dot(area, 34, nil, "ARTWORK")
		B.Place(piece, x - 17, y - 17, area)
		game.pieces[i] = piece
		local ring = B.Sprite(area, 44, 44, "OVERLAY")
		B.Place(ring, x - 22, y - 22, area)
		game.rings[i] = ring
	end
	game.tally = B.Label(area, E.tokens.size.cardTitle, "body", "LEFT")
	game.tally:SetPoint("TOPLEFT", area, "TOPLEFT", 2, -6)
	game.prompt = B.Label(area, E.tokens.size.small, "secondary", "RIGHT")
	game.prompt:SetPoint("TOPRIGHT", area, "TOPLEFT", WIDTH - 2, -9)
	game.fx = B.Effects(area)
	return game
end

function Mill:Start()
	self.board = {}
	for i = 1, 24 do self.board[i] = 0 end
	self.hand = { [1] = 9, [-1] = 9 }
	self.turn, self.result, self.taking, self.quiet, self.last, self.taken = 1, nil, nil, 0, nil, 0
	self.picked, self.think, self.ending, self.thread = nil, nil, nil, nil
	self.fx:Clear()
	self.host.Score(0)
	self:Draw()
end

function Mill:Loaded()
	-- The saved hand has string keys after a copy; read them back as sides.
	local hand = self.hand or {}
	self.hand = { [1] = tonumber(hand[1] or hand["1"]) or 0, [-1] = tonumber(hand[-1] or hand["-1"]) or 0 }
	self.picked, self.thread = nil, nil
	self.think = (self.turn == -1 and not self.result) and THINK or nil
	-- Saved inside the end delay: the result is decided, so it ends.
	if self.result then self.ending = 0.3 end
end

-- Plays a move for side v (the take may follow later for you).
function Mill:Play(m, v)
	local board = self.board
	Apply(board, self.hand, { from = m.from, to = m.to }, v)
	self.last = m.to
	local x, y = Spot(m.to)
	self.fx:Burst(x, y, self.host.FactionColor(v), 50, 0.35)
	self.host.Sound("turn")
	if InMill(board, m.to) then
		self.quiet = 0
		self.fx:Sparks(x, y, self.host.Color("gold"), 10, 90)
		self.fx:Float(x, y - 30, L["Mill!"], self.host.Color("gold"), E.tokens.size.cardTitle)
		if v == 1 and #Takeable(board, -1) > 0 then
			self.taking = true
			self:Draw()
			return
		end
		if m.take then self:Take(m.take, v) return end
	elseif self.hand[1] == 0 and self.hand[-1] == 0 then
		self.quiet = self.quiet + 1
	end
	self:Pass(v)
end

function Mill:Take(i, v)
	self.board[i] = 0
	local x, y = Spot(i)
	self.fx:Burst(x, y, self.host.Color(v == 1 and "good" or "bad"), 70, 0.45)
	self.host.Sound("point")
	if v == 1 then
		self.taken = self.taken + 1
		self.host.Score(self.taken)
	end
	self.taking = nil
	self:Pass(v)
end

-- Hands the turn over, or ends the game.
function Mill:Pass(v)
	if Lost(self.board, self.hand, -v) then
		self.result = v == 1 and "won" or "lost"
		self.host.Sound(v == 1 and "best" or "over")
		self.ending = 1.4
	elseif self.quiet >= QUIET then
		self.result = "draw"
		self.ending = 1.0
	else
		self.turn = -v
		if self.turn == -1 then self.think = THINK end
	end
	self:Draw()
end

-- The opponent's move, searched on a copy of the board and the hands.
function Mill:Choose()
	local board, hand = B.Copy(self.board), { [1] = self.hand[1], [-1] = self.hand[-1] }
	local best, bestValue
	for _, m in ipairs(Moves(board, hand, -1)) do
		Apply(board, hand, m, -1)
		local value = -Search(board, hand, self.mode.depth - 1, -math.huge, math.huge, 1)
		Undo(board, hand, m, -1)
		if self.mode.noise > 0 then value = value + self.host.Random(self.mode.noise) end
		if not bestValue or value > bestValue then best, bestValue = m, value end
	end
	return best
end

function Mill:PointAt(x, y)
	for i = 1, 24 do
		local px, py = Spot(i)
		if (x - px) ^ 2 + (y - py) ^ 2 <= 22 * 22 then return i end
	end
end

function Mill:Press(button, x, y)
	if button ~= "LeftButton" or not (x and y) or self.turn ~= 1 or self.result then return end
	local i = self:PointAt(x, y)
	if not i then return end
	local board = self.board
	if self.taking then
		for _, t in ipairs(Takeable(board, -1)) do
			if t == i then return self:Take(i, 1) end
		end
		return
	end
	if self.hand[1] > 0 then
		if board[i] == 0 then self:Play({ to = i }, 1) end
		return
	end
	if board[i] == 1 then
		self.picked = i
		self:Draw()
		return
	end
	if self.picked and board[i] == 0 then
		for _, m in ipairs(Moves(board, self.hand, 1)) do
			if m.from == self.picked and m.to == i then
				self.picked = nil
				self:Play({ from = m.from, to = i }, 1)
				return
			end
		end
	end
end

function Mill:Update(dt)
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
				if m then self:Play(m, -1) end
			end
		end
	end
end

function Mill:Summary()
	if not self.taken then return nil end
	return E:Plural(self.taken, "%d %s piece taken", "%d %s pieces taken"):format(self.taken, self.host.FactionName(-1))
end

function Mill:Draw()
	local palette, color = self.host.Palette(), self.host.Color
	local bronze = E.tokens.palette.bronze
	self.back:Paint(bronze, 0.16)
	for _, tex in ipairs(self.lines) do B.Fill(tex, bronze, 0.75) end
	local targets = {}
	if self.turn == 1 and not self.result then
		if self.taking then
			for _, t in ipairs(Takeable(self.board, -1)) do targets[t] = "take" end
		elseif self.picked then
			for _, m in ipairs(Moves(self.board, self.hand, 1)) do
				if m.from == self.picked then targets[m.to] = "move" end
			end
		end
	end
	for i = 1, 24 do
		local v = self.board[i]
		local hole = self.holes[i]
		local c = color("dim")
		hole:SetVertexColor(c[1], c[2], c[3], 0.8)
		local piece = self.pieces[i]
		piece:SetShown(v ~= 0)
		if v ~= 0 then
			local pc = self.host.FactionColor(v, palette)
			piece:SetVertexColor(pc[1], pc[2], pc[3], 1)
		end
		local ring = self.rings[i]
		local mark = targets[i] or (self.picked == i and "picked") or (self.last == i and "last")
		ring:SetShown(mark and true or false)
		if mark == "take" then
			B.Art(ring, "Ring", color("bad"), 0.9)
		elseif mark == "move" then
			B.Art(ring, "Ring", color("accent"), 0.7)
		elseif mark == "picked" then
			B.Art(ring, "Ring", color("good"), 0.9)
		elseif mark == "last" then
			B.Art(ring, "Ring", color("gold"), 0.7)
		end
	end
	self.tally:SetText(L["In hand: you %d, the %s %d"]:format(self.hand[1], self.host.FactionName(-1), self.hand[-1]))
	local text
	if self.result == "won" then
		text = L["You win!"]
	elseif self.result == "lost" then
		text = L["The %s wins."]:format(self.host.FactionName(-1))
	elseif self.result == "draw" then
		text = L["A draw."]
	elseif self.turn ~= 1 then
		text = L["The %s is thinking..."]:format(self.host.FactionName(-1))
	elseif self.taking then
		text = L["A mill: take one of the %s's pieces."]:format(self.host.FactionName(-1))
	elseif self.hand[1] > 0 then
		text = L["Place a piece on a free point."]
	else
		text = L["Move a piece along a line."]
	end
	self.prompt:SetText(text)
end

M:RegisterGame({
	key = "mill", order = 168, group = "board",
	title = "Mill", desc = "Place and move nine pieces; three in a row takes an opposing piece.",
	controls = Key("Click a point to place; click a piece, then where it goes. P: pause."),
	icon = "Interface\\Icons\\INV_Stone_04",
	modes = MODES,
	width = WIDTH, height = HEIGHT,
	New = New,
})
