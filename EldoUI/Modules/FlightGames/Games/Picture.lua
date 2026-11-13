-- EldoUI Flight Games: Picture Logic. The numbers by each row and column
-- tell how long the runs of filled squares in it are, in order. Fill the
-- squares that fit every row and every column, and a little picture comes
-- out. Each picture has exactly one answer; the clock is the score.
-- Written from scratch for EldoUI, with its own pictures.
local _, E = ...
local M = E.FlightGames
local Key = E.Key
local L = E.L
local B = M.Board

local PICTURES = {
	small = {
		{ name = Key("A heart"), rows = { ".#.#.", "#####", "#####", ".###.", "..#.." } },
		{ name = Key("An arrow"), rows = { "..#..", ".###.", "#.#.#", "..#..", "..#.." } },
		{ name = Key("A cross"), rows = { "..#..", "..#..", "#####", "..#..", "..#.." } },
		{ name = Key("A smile"), rows = { ".....", ".#.#.", ".....", "#...#", ".###." } },
		{ name = Key("A gem"), rows = { "..#..", ".###.", "#####", ".###.", "..#.." } },
		{ name = Key("A moon"), rows = { ".###.", "##...", "#....", "##...", ".###." } },
		{ name = Key("A goblet"), rows = { "#####", "#####", ".###.", "..#..", ".###." } },
		{ name = Key("A house"), rows = { "..#..", ".###.", "#####", "#.#.#", "#.###" } },
	},
	large = {
		{ name = Key("A sword"), rows = { "........##", ".......###", "......###.", ".....###..", "#...###...", "##.###....", ".####.....", "..##......", ".##.#.....", "##........" } },
		{ name = Key("A potion"), rows = { "...####...", "....##....", "....##....", "...####...", "..######..", ".########.", ".########.", ".########.", "..######..", "...####..." } },
		{ name = Key("A shield"), rows = { ".########.", "##########", "##..##..##", "##..##..##", "##########", "##########", ".########.", "..######..", "...####...", "....##...." } },
		{ name = Key("A heart"), rows = { ".##....##.", "####..####", "##########", "##########", "##########", ".########.", "..######..", "...####...", "....##....", ".........." } },
		{ name = Key("A mushroom"), rows = { "...####...", ".########.", "###.##.###", "##########", "#.######.#", "...####...", "...#..#...", "...#..#...", "...####...", ".........." } },
		{ name = Key("A crown"), rows = { "..........", "#...##...#", "##..##..##", "###.##.###", "##########", "##########", "#.#.#.#.#.", "##########", "##########", ".........." } },
		{ name = Key("A tree"), rows = { "....##....", "...####...", "..######..", "...####...", "..######..", ".########.", "##########", "....##....", "....##....", "...####..." } },
		{ name = Key("A fish"), rows = { "..........", ".#....###.", ".##..#####", ".#########", ".##.######", ".#########", ".##..#####", ".#....###.", "..........", ".........." } },
		{ name = Key("A key"), rows = { ".###......", "##.##.....", "#...######", "##.##..#.#", ".###...###", "..........", "..........", "..........", "..........", ".........." } },
	},
}
local MODES = {
	{ key = "small", title = "5 x 5", n = 5, cell = 56, clue = 64 },
	{ key = "large", title = "10 x 10", n = 10, cell = 32, clue = 78 },
}
local DIRS = { UP = { 0, -1 }, W = { 0, -1 }, DOWN = { 0, 1 }, S = { 0, 1 }, LEFT = { -1, 0 }, A = { -1, 0 }, RIGHT = { 1, 0 }, D = { 1, 0 } }

local Picture = {}
Picture.__index = Picture
-- What a saved game keeps (the board, the score and the timers).
Picture.saveKeys = { "pick", "marks", "time", "cx", "cy" }

local function ModeOf(mode)
	return mode and mode.n and mode or MODES[1]
end

local function Runs(line)
	local out, n = {}, 0
	for i = 1, #line do
		if line:sub(i, i) == "#" then
			n = n + 1
		elseif n > 0 then
			out[#out + 1] = n
			n = 0
		end
	end
	if n > 0 then out[#out + 1] = n end
	return out
end

local function New(host, mode)
	mode = ModeOf(mode)
	local game = setmetatable({ host = host, mode = mode }, Picture)
	local area = host.area
	local n, cell, clue = mode.n, mode.cell, mode.clue
	game.grid = B.Grid(area, n, n, cell, { gap = 3 })
	game.grid.frame:SetPoint("TOPLEFT", area, "TOPLEFT", clue, -clue)
	game.rowText, game.colText = {}, {}
	for i = 1, n do
		local r = B.Label(area, E.tokens.size.small, "body", "RIGHT")
		r:SetPoint("RIGHT", area, "TOPLEFT", clue - 6, -(clue + (i - 0.5) * cell))
		game.rowText[i] = r
		local c = B.Label(area, E.tokens.size.small, "body")
		c:SetPoint("BOTTOM", area, "TOPLEFT", clue + (i - 0.5) * cell, -(clue - 4))
		c:SetJustifyV("BOTTOM")
		game.colText[i] = c
	end
	game.lines = {}
	for k = 5, n - 1, 5 do
		local v = B.Sprite(area, 2, n * cell, "OVERLAY")
		B.Place(v, clue + k * cell - 1, clue, area)
		local h = B.Sprite(area, n * cell, 2, "OVERLAY")
		B.Place(h, clue, clue + k * cell - 1, area)
		game.lines[#game.lines + 1] = v
		game.lines[#game.lines + 1] = h
	end
	game.cursor = B.Sprite(area, cell + 4, cell + 4, "OVERLAY")
	game.crosses = {}
	game.fx = B.Effects(area)
	return game
end

function Picture:Rows()
	local set = PICTURES[self.mode.key] or PICTURES.small
	return (set[self.pick] or set[1]).rows
end

function Picture:Start()
	local set = PICTURES[self.mode.key] or PICTURES.small
	local pick = self.host.Random(#set)
	if pick == self.pick and #set > 1 then pick = pick % #set + 1 end
	self.pick = pick
	self.marks = {}
	local n = self.mode.n
	for i = 1, n * n do self.marks[i] = 0 end
	self.time, self.cx, self.cy = 0, 1, 1
	self.host.Score(0)
	self:Draw()
end

-- The runs of a row or column as you have filled it.
function Picture:Line(index, isCol)
	local n, out = self.mode.n, {}
	for k = 1, n do
		local i = isCol and ((k - 1) * n + index) or ((index - 1) * n + k)
		out[k] = self.marks[i] == 1 and "#" or "."
	end
	return table.concat(out)
end

function Picture:Matches(index, isCol)
	local rows, n = self:Rows(), self.mode.n
	local want
	if isCol then
		local col = {}
		for r = 1, n do col[r] = rows[r]:sub(index, index) end
		want = Runs(table.concat(col))
	else
		want = Runs(rows[index])
	end
	local got = Runs(self:Line(index, isCol))
	if #got ~= #want then return false end
	for k = 1, #got do if got[k] ~= want[k] then return false end end
	return true
end

function Picture:Solved()
	for i = 1, self.mode.n do
		if not (self:Matches(i, false) and self:Matches(i, true)) then return false end
	end
	return true
end

-- Fill (1) or cross out (2) a square; the same again clears it.
function Picture:Mark(x, y, kind)
	local i = (y - 1) * self.mode.n + x
	self.marks[i] = self.marks[i] == kind and 0 or kind
	self.host.Sound("turn")
	self:Draw()
	if self:Solved() then
		local size = self.mode.n * self.mode.cell
		local clue = self.mode.clue
		self.fx:Burst(clue + size / 2, clue + size / 2, self.host.Color("good"), size * 1.2, 0.8)
		self.fx:Sparks(clue + size / 2, clue + size / 2, self.host.Color("gold"), 16, 200)
		self.host.Sound("point")
		self.host.Score(math.floor(self.time))
		self.host.Over(true)
	end
end

function Picture:Key(key)
	local d = DIRS[key]
	local n = self.mode.n
	if d then
		self.cx = math.max(1, math.min(n, self.cx + d[1]))
		self.cy = math.max(1, math.min(n, self.cy + d[2]))
		self:Draw()
		return true
	elseif key == "SPACE" or key == "ENTER" then
		self:Mark(self.cx, self.cy, 1)
		return true
	elseif key == "X" then
		self:Mark(self.cx, self.cy, 2)
		return true
	end
	return false
end

function Picture:Press(button, x, y)
	if not (x and y) then return end
	local cx, cy = self.grid:CellAt(x, y, self.mode.clue, self.mode.clue)
	if not cx then return end
	self.cx, self.cy = cx, cy
	self:Mark(cx, cy, button == "RightButton" and 2 or 1)
end

function Picture:Update(dt)
	self.fx:Update(dt)
	local before = math.floor(self.time)
	self.time = self.time + dt
	if math.floor(self.time) ~= before then self.host.Score(math.floor(self.time)) end
end

function Picture:Summary()
	local set = PICTURES[self.mode.key] or PICTURES.small
	local picture = set[self.pick or 1]
	if not picture then return nil end
	return L["The picture: %s"]:format(L[picture.name])
end

function Picture:Draw()
	local n, cell, clue = self.mode.n, self.mode.cell, self.mode.clue
	local grid, color, area = self.grid, self.host.Color, self.host.area
	local rows = self:Rows()
	local crosses = 0
	for y = 1, n do
		for x = 1, n do
			local mark = self.marks[(y - 1) * n + x]
			if mark == 1 then
				grid:Paint(x, y, color("accent"), 0.95)
			else
				grid:Paint(x, y, color("dim"), (x == self.cx or y == self.cy) and 0.24 or 0.14)
			end
			if mark == 2 then
				crosses = crosses + 1
				local tex = self.crosses[crosses]
				if not tex then
					tex = B.Label(area, E.tokens.size.small, "dim")
					self.crosses[crosses] = tex
				end
				tex:SetText("x")
				tex:ClearAllPoints()
				tex:SetPoint("CENTER", area, "TOPLEFT", clue + (x - 0.5) * cell, -(clue + (y - 0.5) * cell))
				tex:Show()
			end
		end
	end
	for i = crosses + 1, #self.crosses do self.crosses[i]:Hide() end
	for i = 1, n do
		local runs = Runs(rows[i])
		self.rowText[i]:SetText(#runs > 0 and table.concat(runs, " ") or "0")
		self.rowText[i]:SetTextColor(unpack(self:Matches(i, false) and color("good") or color("body")))
		local col = {}
		for r = 1, n do col[r] = rows[r]:sub(i, i) end
		local colRuns = Runs(table.concat(col))
		self.colText[i]:SetText(#colRuns > 0 and table.concat(colRuns, "\n") or "0")
		self.colText[i]:SetTextColor(unpack(self:Matches(i, true) and color("good") or color("body")))
	end
	for _, line in ipairs(self.lines) do B.Fill(line, color("secondary"), 0.8) end
	B.Art(self.cursor, "Ring", color("gold"), 0.9)
	B.Place(self.cursor, clue + (self.cx - 1) * cell - 2, clue + (self.cy - 1) * cell - 2, area)
end

M:RegisterGame({
	key = "picture", order = 79, group = "puzzle",
	title = "Picture Logic", desc = "Fill the squares the numbers ask for, and a picture comes out.",
	controls = Key("Click: fill. Right-click or X: cross out. Arrow keys and Space work too. P: pause."),
	icon = "Interface\\Icons\\INV_Misc_Book_11",
	modes = MODES, lower = true, unit = "seconds",
	Size = function(mode) mode = ModeOf(mode) return mode.clue + mode.n * mode.cell, mode.clue + mode.n * mode.cell end,
	New = New,
})
