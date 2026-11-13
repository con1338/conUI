-- EldoUI Flight Games: Four in a Row. The Alliance and the Horde drop
-- banners into a frame of seven columns; a banner falls to the lowest free
-- place. Four of yours in a row (across, up or slanting) wins.
-- Written from scratch for EldoUI.
local _, E = ...
local M = E.FlightGames
local Key = E.Key
local L = E.L
local B = M.Board

local COLS, ROWS, CELL = 7, 6, 60
local TOP = 34
local WIDTH, HEIGHT = COLS * CELL, TOP + ROWS * CELL
local THINK = 0.45
local MODES = {
	{ key = "easy", title = "Easy", depth = 2, noise = 40 },
	{ key = "normal", title = "Normal", depth = 3, noise = 8 },
	{ key = "hard", title = "Hard", depth = 5, noise = 0 },
}
local ALLIANCE, HORDE = "Interface\\Icons\\INV_BannerPVP_02", "Interface\\Icons\\INV_BannerPVP_01"
local ORDER = { 4, 3, 5, 2, 6, 1, 7 }  -- the computer looks at the middle first

local Four = {}
Four.__index = Four
-- What a saved game keeps (the board, the score and the timers).
Four.saveKeys = { "board", "turn", "moves", "col", "result", "line", "fall" }

local function ModeOf(mode)
	return mode and mode.depth and mode or MODES[2]
end

local function At(board, c, r) return board[(r - 1) * COLS + c] end

-- The lowest free row of a column, or nil when it is full.
local function Drop(board, c)
	for r = ROWS, 1, -1 do
		if At(board, c, r) == 0 then return r end
	end
end

-- Four in a row through (c, r) for side v: the four places, or nil.
local LINES = { { 1, 0 }, { 0, 1 }, { 1, 1 }, { 1, -1 } }
local function Wins(board, c, r, v)
	for _, d in ipairs(LINES) do
		local line = { { c, r } }
		for s = -1, 1, 2 do
			local x, y = c + d[1] * s, r + d[2] * s
			while x >= 1 and x <= COLS and y >= 1 and y <= ROWS and At(board, x, y) == v do
				line[#line + 1] = { x, y }
				x, y = x + d[1] * s, y + d[2] * s
			end
		end
		if #line >= 4 then return line end
	end
end
Four.Wins = Wins

-- How good the board looks for side v: windows of four with only v in
-- them count, the more the better.
local function Score(board, v)
	local total = 0
	for r = 1, ROWS do
		for c = 1, COLS do
			for _, d in ipairs(LINES) do
				local ec, er = c + d[1] * 3, r + d[2] * 3
				if ec >= 1 and ec <= COLS and er >= 1 and er <= ROWS then
					local mine, theirs = 0, 0
					for k = 0, 3 do
						local x = At(board, c + d[1] * k, r + d[2] * k)
						if x == v then mine = mine + 1 elseif x == -v then theirs = theirs + 1 end
					end
					if theirs == 0 then total = total + (mine == 3 and 12 or mine == 2 and 3 or 0) end
					if mine == 0 then total = total - (theirs == 3 and 14 or theirs == 2 and 3 or 0) end
				end
			end
		end
	end
	for r = 1, ROWS do
		if At(board, 4, r) == v then total = total + 2 end
	end
	return total
end

local function Negamax(board, depth, alpha, beta, v)
	B.Tick()
	local any = false
	for _, c in ipairs(ORDER) do
		local r = Drop(board, c)
		if r then
			any = true
			board[(r - 1) * COLS + c] = v
			local win = Wins(board, c, r, v)
			board[(r - 1) * COLS + c] = 0
			if win then return 1000 + depth end
		end
	end
	if not any then return 0 end
	if depth == 0 then return Score(board, v) end
	local best = -math.huge
	for _, c in ipairs(ORDER) do
		local r = Drop(board, c)
		if r then
			board[(r - 1) * COLS + c] = v
			local value = -Negamax(board, depth - 1, -beta, -alpha, -v)
			board[(r - 1) * COLS + c] = 0
			if value > best then best = value end
			if best > alpha then alpha = best end
			if alpha >= beta then break end
		end
	end
	return best
end

-- The computer's column for side v.
-- The Horde's column, searched on a copy of the board.
function Four:Choose(v)
	local mode, board = self.mode, B.Copy(self.board)
	local best, bestValue = nil, -math.huge
	for _, c in ipairs(ORDER) do
		local r = Drop(board, c)
		if r then
			board[(r - 1) * COLS + c] = v
			local value
			if Wins(board, c, r, v) then
				value = 100000
			else
				value = -Negamax(board, mode.depth - 1, -math.huge, math.huge, -v)
			end
			board[(r - 1) * COLS + c] = 0
			if mode.noise > 0 and value < 1000 then value = value + self.host.Random(mode.noise) end
			if value > bestValue then best, bestValue = c, value end
		end
	end
	return best
end

local function New(host, mode)
	local game = setmetatable({ host = host, mode = ModeOf(mode) }, Four)
	local area = host.area
	game.frame = B.Sprite(area, WIDTH, ROWS * CELL, "BACKGROUND")
	B.Place(game.frame, 0, TOP, area)
	game.holes, game.tokens = {}, {}
	for r = 1, ROWS do
		for c = 1, COLS do
			local i = (r - 1) * COLS + c
			local hole = B.Dot(area, CELL - 10, nil, "BORDER")
			B.Place(hole, (c - 1) * CELL + 5, TOP + (r - 1) * CELL + 5, area)
			game.holes[i] = hole
			local token = { disc = B.Dot(area, CELL - 12, nil, "ARTWORK"), icon = B.Sprite(area, CELL - 30, CELL - 30, "OVERLAY"),
				ring = B.Sprite(area, CELL - 4, CELL - 4, "OVERLAY") }
			game.tokens[i] = token
		end
	end
	game.hover = { disc = B.Dot(area, CELL - 16, nil, "ARTWORK"), icon = B.Sprite(area, CELL - 34, CELL - 34, "OVERLAY") }
	E:SetClientFile(game.hover.icon, ALLIANCE, "Interface\\Icons\\INV_Misc_QuestionMark")
	E:TrimIcon(game.hover.icon)
	game.falling = { disc = B.Dot(area, CELL - 12, nil, "ARTWORK"), icon = B.Sprite(area, CELL - 30, CELL - 30, "OVERLAY") }
	game.prompt = B.Label(area, E.tokens.size.small, "secondary", "RIGHT")
	game.prompt:SetPoint("TOPRIGHT", area, "TOPLEFT", WIDTH - 4, -10)
	game.fx = B.Effects(area)
	return game
end

function Four:Start()
	self.ending, self.thread = nil, nil
	self.board = {}
	for i = 1, COLS * ROWS do self.board[i] = 0 end
	self.turn, self.moves, self.col, self.result, self.line = 1, 0, 4, nil, nil
	self.fall, self.think = nil, nil
	self.host.Score(0)
	self:Draw()
end

-- A banner saved in mid-fall lands; a game saved in the Horde's turn
-- has the Horde move.
function Four:Loaded()
	self.thread = nil
	self.think = (self.turn == -1 and not self.result and not self.fall) and THINK or nil
	-- Saved inside the end delay: the result is decided, so it ends.
	if self.result then self.ending = 0.3 end
end

-- Starts a banner falling into column c for side v.
function Four:Play(c, v)
	local r = Drop(self.board, c)
	if not r then return false end
	self.fall = { c = c, r = r, v = v, y = 0, vy = 0 }
	self.host.Sound("turn")
	return true
end

function Four:Land()
	local f = self.fall
	self.fall = nil
	self.board[(f.r - 1) * COLS + f.c] = f.v
	if f.v == 1 then self.moves = self.moves + 1 end
	local x, y = (f.c - 0.5) * CELL, TOP + (f.r - 0.5) * CELL
	self.fx:Burst(x, y, self.host.Color("body"), CELL, 0.3)
	local line = Wins(self.board, f.c, f.r, f.v)
	if line then
		self.line = line
		self.result = f.v == 1 and "won" or "lost"
		local color = self.host.Color(f.v == 1 and "good" or "bad")
		for _, p in ipairs(line) do
			self.fx:Sparks((p[1] - 0.5) * CELL, TOP + (p[2] - 0.5) * CELL, color, 6, 120)
		end
		if f.v == 1 then self.host.Score(math.max(1, 25 - self.moves)) end
		self.host.Sound(f.v == 1 and "point" or "over")
		self.ending = 1.2
	elseif not self:AnyFree() then
		self.result = "draw"
		self.ending = 1.0
	else
		self.turn = -f.v
		if self.turn == -1 then self.think = THINK end
	end
	self:Draw()
end

function Four:AnyFree()
	for c = 1, COLS do if Drop(self.board, c) then return true end end
	return false
end

function Four:Key(key)
	if self.result or self.fall or self.turn ~= 1 then return key == "LEFT" or key == "RIGHT" or key == "SPACE" end
	if key == "LEFT" or key == "A" then
		self.col = math.max(1, self.col - 1)
	elseif key == "RIGHT" or key == "D" then
		self.col = math.min(COLS, self.col + 1)
	elseif key == "SPACE" or key == "DOWN" or key == "ENTER" or key == "S" then
		self:Play(self.col, 1)
	else
		local n = tonumber(key)
		if not (n and n >= 1 and n <= COLS) then return false end
		self.col = n
		self:Play(n, 1)
	end
	self:Draw()
	return true
end

function Four:Press(button, x)
	if button ~= "LeftButton" or not x then return end
	if self.result or self.fall or self.turn ~= 1 then return end
	local c = math.floor(x / CELL) + 1
	if c >= 1 and c <= COLS then
		self.col = c
		self:Play(c, 1)
		self:Draw()
	end
end

function Four:Update(dt)
	self.fx:Update(dt)
	if self.ending then
		self.ending = self.ending - dt
		if self.ending <= 0 then
			self.ending = nil
			self.host.Over(self.result == "won")
		end
		return
	end
	local f = self.fall
	if f then
		f.vy = f.vy + 2400 * dt
		f.y = f.y + f.vy * dt
		if f.y >= (f.r - 1) * CELL then self:Land() else self:Draw() end
		return
	end
	if self.think then
		self.think = self.think - dt
		if self.think <= 0 then
			-- The search runs a few milliseconds a frame until it is done.
			self.thread = self.thread or B.Think(function() return self:Choose(-1) end)
			local done, c = B.Pump(self.thread)
			if done then
				self.think, self.thread = nil, nil
				if c then self:Play(c, -1) end
			end
		end
	end
	-- The banner over the board follows the pointer on your turn.
	if self.turn == 1 and not self.result then
		local cx = self.host.Cursor()
		if cx and cx >= 0 and cx <= WIDTH and cx ~= self.lastX then
			self.lastX = cx
			self.col = math.max(1, math.min(COLS, math.floor(cx / CELL) + 1))
			self:Draw()
		end
	end
end

function Four:Summary()
	if self.result == "won" then return E:Plural(self.moves, "Four in a row in %d move", "Four in a row in %d moves"):format(self.moves) end
	if self.result == "draw" then return L["The frame is full: a draw."] end
	return L["The Horde got four in a row."]
end

local function Paint(view, v, palette, size)
	local color = v == 1 and palette[7] or palette[6]
	view.disc:SetVertexColor(color[1], color[2], color[3], 1)
	if view.file ~= v then
		view.file = v
		E:SetClientFile(view.icon, v == 1 and ALLIANCE or HORDE, "Interface\\Icons\\INV_Misc_QuestionMark")
		E:TrimIcon(view.icon)
	end
	view.disc:SetSize(size, size)
end

function Four:Draw()
	local area, color, palette = self.host.area, self.host.Color, self.host.Palette()
	B.Fill(self.frame, palette[1], 0.16)
	local winning = {}
	for _, p in ipairs(self.line or {}) do winning[(p[2] - 1) * COLS + p[1]] = true end
	for i = 1, COLS * ROWS do
		local v = self.board[i]
		local hole, token = self.holes[i], self.tokens[i]
		hole:SetVertexColor(0.02, 0.02, 0.03, 0.85)
		local on = v ~= 0
		token.disc:SetShown(on)
		token.icon:SetShown(on)
		token.ring:SetShown(on and winning[i] or false)
		if on then
			local c, r = (i - 1) % COLS + 1, math.floor((i - 1) / COLS) + 1
			Paint(token, v, palette, CELL - 12)
			B.Place(token.disc, (c - 1) * CELL + 6, TOP + (r - 1) * CELL + 6, area)
			B.Place(token.icon, (c - 1) * CELL + 15, TOP + (r - 1) * CELL + 15, area)
			if winning[i] then
				B.Art(token.ring, "Ring", v == 1 and color("good") or color("bad"), 1)
				B.Place(token.ring, (c - 1) * CELL + 2, TOP + (r - 1) * CELL + 2, area)
			end
		end
	end
	local f = self.fall
	self.falling.disc:SetShown(f ~= nil)
	self.falling.icon:SetShown(f ~= nil)
	if f then
		Paint(self.falling, f.v, palette, CELL - 12)
		B.Place(self.falling.disc, (f.c - 1) * CELL + 6, TOP + f.y + 6, area)
		B.Place(self.falling.icon, (f.c - 1) * CELL + 15, TOP + f.y + 15, area)
	end
	local yours = self.turn == 1 and not self.result and not f
	self.hover.disc:SetShown(yours)
	self.hover.icon:SetShown(yours)
	if yours then
		local blue = palette[7]
		self.hover.disc:SetVertexColor(blue[1], blue[2], blue[3], 0.7)
		B.Place(self.hover.disc, (self.col - 1) * CELL + 8, 2, area)
		B.Place(self.hover.icon, (self.col - 1) * CELL + 17, 11, area)
	end
	local text
	if self.result == "won" then
		text = L["Four in a row: you win!"]
	elseif self.result == "lost" then
		text = L["The Horde got four in a row."]
	elseif self.result == "draw" then
		text = L["The frame is full: a draw."]
	elseif self.turn == 1 then
		text = L["Your move."]
	else
		text = L["The Horde is thinking..."]
	end
	self.prompt:SetText(text)
end

M:RegisterGame({
	key = "four", order = 140, group = "board",
	title = "Four in a Row", desc = "Drop Alliance banners against the Horde; four in a row wins.",
	controls = Key("Click a column, or Left, Right and Space (or 1 to 7). P: pause."),
	icon = ALLIANCE,
	modes = MODES,
	width = WIDTH, height = HEIGHT,
	New = New,
})
