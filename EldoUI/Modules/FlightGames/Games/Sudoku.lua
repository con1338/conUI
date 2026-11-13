-- EldoUI Flight Games: Rune Sudoku. Fill the board so each row, each
-- column and each boxed block holds every rune once. The runes are the
-- numbers 1 to 4, 6 or 9 on colored stones. Every board has exactly one
-- answer, and the clock is the score.
-- Written from scratch for EldoUI.
local _, E = ...
local M = E.FlightGames
local Key = E.Key
local L = E.L
local B = M.Board

local MODES = {
	{ key = "four", title = "4 x 4", n = 4, br = 2, bc = 2, cell = 84, clues = 6 },
	{ key = "six", title = "6 x 6", n = 6, br = 2, bc = 3, cell = 60, clues = 13 },
	{ key = "nine", title = "9 x 9", n = 9, br = 3, bc = 3, cell = 44, clues = 30 },
}
local PAD_H = 46
local DIRS = { UP = { 0, -1 }, W = { 0, -1 }, DOWN = { 0, 1 }, S = { 0, 1 }, LEFT = { -1, 0 }, A = { -1, 0 }, RIGHT = { 1, 0 }, D = { 1, 0 } }

local Sudoku = {}
Sudoku.__index = Sudoku
-- What a saved game keeps (the board, the score and the timers).
Sudoku.saveKeys = { "given", "cells", "answer", "time", "cx", "cy" }

local function ModeOf(mode)
	return mode and mode.n and mode or MODES[2]
end

local function Size(mode)
	mode = ModeOf(mode)
	return mode.n * mode.cell, mode.n * mode.cell + PAD_H
end

-- Can value v go at index i of a board?
local function Fits(board, mode, i, v)
	local n = mode.n
	local r, c = math.floor((i - 1) / n), (i - 1) % n
	for k = 0, n - 1 do
		if board[r * n + k + 1] == v or board[k * n + c + 1] == v then return false end
	end
	local r0, c0 = r - r % mode.br, c - c % mode.bc
	for dr = 0, mode.br - 1 do
		for dc = 0, mode.bc - 1 do
			if board[(r0 + dr) * n + c0 + dc + 1] == v then return false end
		end
	end
	return true
end

-- Counts the answers of a board, stopping at `limit`.
local function Count(board, mode, limit)
	local n = mode.n
	local best, bestCount
	for i = 1, n * n do
		if board[i] == 0 then
			local count = 0
			for v = 1, n do if Fits(board, mode, i, v) then count = count + 1 end end
			if count == 0 then return 0 end
			if not bestCount or count < bestCount then best, bestCount = i, count end
			if count == 1 then break end
		end
	end
	if not best then return 1 end
	local total = 0
	for v = 1, n do
		if Fits(board, mode, best, v) then
			board[best] = v
			total = total + Count(board, mode, limit - total)
			board[best] = 0
			if total >= limit then return total end
		end
	end
	return total
end
Sudoku.Count = Count

local function New(host, mode)
	mode = ModeOf(mode)
	local game = setmetatable({ host = host, mode = mode }, Sudoku)
	local area = host.area
	local n, cell = mode.n, mode.cell
	game.grid = B.Grid(area, n, n, cell, { gap = 4 })
	game.grid.frame:SetPoint("TOPLEFT")
	game.texts = {}
	for i = 1, n * n do
		local r, c = math.floor((i - 1) / n), (i - 1) % n
		local text = B.Label(area, cell >= 60 and E.tokens.size.hero or E.tokens.size.display, "body")
		text:SetPoint("CENTER", area, "TOPLEFT", (c + 0.5) * cell, -(r + 0.5) * cell)
		game.texts[i] = text
	end
	game.lines = {}
	for k = 1, n - 1 do
		if k % mode.bc == 0 then
			local line = B.Sprite(area, 2, n * cell, "OVERLAY")
			B.Place(line, k * cell - 1, 0, area)
			game.lines[#game.lines + 1] = line
		end
		if k % mode.br == 0 then
			local line = B.Sprite(area, n * cell, 2, "OVERLAY")
			B.Place(line, 0, k * cell - 1, area)
			game.lines[#game.lines + 1] = line
		end
	end
	game.cursor = B.Sprite(area, cell + 4, cell + 4, "OVERLAY")
	game.pad = {}
	local w = math.min(44, (n * cell - (n + 1) * 4) / (n + 1))
	local x = (n * cell - ((n + 1) * w + n * 4)) / 2
	for v = 0, n do
		local key = { v = v, x = x, w = w }
		key.slab = B.Slab(area, w, 34, "BORDER")
		key.slab:Place(x, n * cell + 8)
		key.text = B.Label(area, E.tokens.size.cardTitle, "body")
		key.text:SetPoint("CENTER", area, "TOPLEFT", x + w / 2, -(n * cell + 25))
		key.text:SetText(v == 0 and "x" or v)
		game.pad[#game.pad + 1] = key
		x = x + w + 4
	end
	game.fx = B.Effects(area)
	return game
end

function Sudoku:Start()
	local mode, n = self.mode, self.mode.n
	local R = self.host.Random
	local function Shuffled(count)
		local out = {}
		for i = 1, count do out[i] = i end
		for i = count, 2, -1 do
			local j = R(i)
			out[i], out[j] = out[j], out[i]
		end
		return out
	end
	-- A whole board from a pattern, with its rows, columns and runes mixed.
	local bandOrder, stackOrder = Shuffled(n / mode.br), Shuffled(n / mode.bc)
	local rows, cols = {}, {}
	for _, band in ipairs(bandOrder) do
		for _, r in ipairs(Shuffled(mode.br)) do rows[#rows + 1] = (band - 1) * mode.br + r - 1 end
	end
	for _, stack in ipairs(stackOrder) do
		for _, c in ipairs(Shuffled(mode.bc)) do cols[#cols + 1] = (stack - 1) * mode.bc + c - 1 end
	end
	local symbols = Shuffled(n)
	local answer = {}
	for r = 1, n do
		for c = 1, n do
			local rr, cc = rows[r], cols[c]
			local base = (mode.bc * (rr % mode.br) + math.floor(rr / mode.br) + cc) % n
			answer[(r - 1) * n + c] = symbols[base + 1]
		end
	end
	-- Take runes away while the answer stays the only one.
	local board = {}
	for i = 1, n * n do board[i] = answer[i] end
	local left = n * n
	for _, i in ipairs(Shuffled(n * n)) do
		if left <= mode.clues then break end
		local keep = board[i]
		board[i] = 0
		if Count(board, mode, 2) == 1 then
			left = left - 1
		else
			board[i] = keep
		end
	end
	self.answer, self.given, self.cells = answer, {}, {}
	for i = 1, n * n do
		self.given[i] = board[i] ~= 0
		self.cells[i] = board[i]
	end
	self.time, self.cx, self.cy = 0, 1, 1
	self.host.Score(0)
	self:Draw()
end

function Sudoku:Put(v)
	local i = (self.cy - 1) * self.mode.n + self.cx
	if self.given[i] then return end
	self.cells[i] = v
	self.host.Sound("turn")
	self:Draw()
	for k = 1, self.mode.n ^ 2 do
		if self.cells[k] ~= self.answer[k] then return end
	end
	local size = self.mode.n * self.mode.cell
	self.fx:Burst(size / 2, size / 2, self.host.Color("good"), size, 0.8)
	self.fx:Sparks(size / 2, size / 2, self.host.Color("gold"), 18, 200)
	self.host.Sound("point")
	self.host.Score(math.floor(self.time))
	self.host.Over(true)
end

function Sudoku:Key(key)
	local d = DIRS[key]
	local n = self.mode.n
	if d then
		self.cx = math.max(1, math.min(n, self.cx + d[1]))
		self.cy = math.max(1, math.min(n, self.cy + d[2]))
		self:Draw()
		return true
	end
	if key == "BACKSPACE" or key == "DELETE" or key == "0" or key == "NUMPAD0" then
		self:Put(0)
		return true
	end
	local v = tonumber(key) or tonumber((key or ""):match("^NUMPAD(%d)$"))
	if v and v >= 1 and v <= n then
		self:Put(v)
		return true
	end
	return false
end

function Sudoku:Press(button, x, y)
	if not (x and y) then return end
	local n, cell = self.mode.n, self.mode.cell
	if y > n * cell then
		for _, key in ipairs(self.pad) do
			if x >= key.x and x <= key.x + key.w then
				self:Put(key.v)
				return
			end
		end
		return
	end
	local cx, cy = self.grid:CellAt(x, y)
	if not cx then return end
	self.cx, self.cy = cx, cy
	if button == "RightButton" then
		self:Put(0)
	else
		self:Draw()
	end
end

function Sudoku:Update(dt)
	self.fx:Update(dt)
	local before = math.floor(self.time)
	self.time = self.time + dt
	if math.floor(self.time) ~= before then self.host.Score(math.floor(self.time)) end
end

-- The runes that clash with another in their row, column or block.
function Sudoku:Clashes()
	local out, n = {}, self.mode.n
	for i = 1, n * n do
		local v = self.cells[i]
		if v ~= 0 then
			self.cells[i] = 0
			if not Fits(self.cells, self.mode, i, v) then out[i] = true end
			self.cells[i] = v
		end
	end
	return out
end

function Sudoku:Draw()
	local n, cell, grid = self.mode.n, self.mode.cell, self.grid
	local palette, color = self.host.Palette(), self.host.Color
	local clashes = self:Clashes()
	local sel = (self.cy - 1) * n + self.cx
	local selValue = self.cells[sel]
	for i = 1, n * n do
		local x, y = (i - 1) % n + 1, math.floor((i - 1) / n) + 1
		local v = self.cells[i]
		local same = v ~= 0 and v == selValue
		if v ~= 0 then
			grid:Paint(x, y, palette[(v - 1) % 7 + 1], self.given[i] and 0.5 or 0.3)
		else
			grid:Paint(x, y, color("dim"), (x == self.cx or y == self.cy) and 0.22 or 0.12)
		end
		local text = self.texts[i]
		text:SetText(v ~= 0 and v or "")
		if clashes[i] then
			text:SetTextColor(unpack(color("bad")))
		elseif self.given[i] then
			text:SetTextColor(unpack(color("body")))
		else
			text:SetTextColor(unpack(same and color("gold") or color("accent")))
		end
	end
	local line = color("secondary")
	for _, tex in ipairs(self.lines) do B.Fill(tex, line, 0.7) end
	B.Art(self.cursor, "Ring", color("accent"), 0.95)
	B.Place(self.cursor, (self.cx - 1) * cell - 2, (self.cy - 1) * cell - 2, self.host.area)
	for _, key in ipairs(self.pad) do
		key.slab:Paint(key.v == 0 and color("dim") or palette[(key.v - 1) % 7 + 1], key.v == 0 and 0.4 or 0.55)
	end
end

M:RegisterGame({
	key = "sudoku", order = 78, group = "puzzle",
	title = "Rune Sudoku", desc = "Every rune once in each row, column and block.",
	controls = Key("Click a stone, then a number key or the runes below. Backspace clears. P: pause."),
	icon = "Interface\\Icons\\INV_Scroll_03",
	modes = MODES, lower = true, unit = "seconds",
	Size = Size,
	New = New,
})
