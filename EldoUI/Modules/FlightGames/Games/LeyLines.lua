-- EldoUI Flight Games: Ley Lines. Pairs of runes of one color lie on the
-- grid. Join each pair with a line through the cells; lines may not cross,
-- and the board is done when every pair is joined and every cell is in a
-- line. Click a rune and move the pointer to draw (click again to stop),
-- or use the arrow keys. Every board has one answer.
-- Written from scratch for EldoUI; the boards come from
-- tools/gen_puzzle_levels.py (PuzzleData.lua).
local _, E = ...
local M = E.FlightGames
local Key = E.Key
local L = E.L
local B = M.Board

local TOP = 30
local MODES = {
	{ key = "five", title = "5 x 5", size = 5, cell = 72 },
	{ key = "six", title = "6 x 6", size = 6, cell = 62 },
	{ key = "seven", title = "7 x 7", size = 7, cell = 54 },
	{ key = "eight", title = "8 x 8", size = 8, cell = 48 },
}
local LETTERS = "ABCDEFG"
local DIRS = { UP = { 0, -1 }, W = { 0, -1 }, DOWN = { 0, 1 }, S = { 0, 1 }, LEFT = { -1, 0 }, A = { -1, 0 }, RIGHT = { 1, 0 }, D = { 1, 0 } }

local Ley = {}
Ley.__index = Ley
-- What a saved board keeps.
Ley.saveKeys = { "pick", "paths", "moves", "sel", "cx", "cy" }

local function ModeOf(mode)
	return mode and mode.size and mode or MODES[2]
end

local function Boards(size)
	local data = M.PuzzleData and M.PuzzleData.ley
	return data and data[size] or {}
end

local function New(host, mode)
	mode = ModeOf(mode)
	local game = setmetatable({ host = host, mode = mode }, Ley)
	local area, n, cell = host.area, mode.size, mode.cell
	game.grid = B.Grid(area, n, n, cell, { gap = 2 })
	game.grid.frame:SetPoint("TOPLEFT", area, "TOPLEFT", 0, -TOP)
	local frame = game.grid.frame
	local thick = math.floor(cell * 0.3)
	game.across, game.down, game.dots, game.runes, game.glow = {}, {}, {}, {}, {}
	for i = 1, n * n do
		local x, y = (i - 1) % n, math.floor((i - 1) / n)
		local across = B.Sprite(frame, cell, thick, "ARTWORK")
		B.Place(across, x * cell + cell / 2, y * cell + cell / 2 - thick / 2, frame)
		local down = B.Sprite(frame, thick, cell, "ARTWORK")
		B.Place(down, x * cell + cell / 2 - thick / 2, y * cell + cell / 2, frame)
		local dot = B.Dot(frame, thick, nil, "ARTWORK")
		B.Place(dot, x * cell + cell / 2 - thick / 2, y * cell + cell / 2 - thick / 2, frame)
		local size = math.floor(cell * 0.68)
		local rune = B.Dot(frame, size, nil, "OVERLAY")
		B.Place(rune, x * cell + (cell - size) / 2, y * cell + (cell - size) / 2, frame)
		local glow = B.Sprite(frame, size + 10, size + 10, "OVERLAY")
		B.Art(glow, "Ring")
		B.Place(glow, x * cell + (cell - size) / 2 - 5, y * cell + (cell - size) / 2 - 5, frame)
		game.across[i], game.down[i], game.dots[i], game.runes[i], game.glow[i] = across, down, dot, rune, glow
	end
	game.cursor = B.Sprite(frame, cell, cell, "OVERLAY")
	game.cursor:SetDrawLayer("OVERLAY", 7)
	game.tally = B.Label(area, E.tokens.size.cardTitle, "body", "LEFT")
	game.tally:SetPoint("TOPLEFT", area, "TOPLEFT", 2, -6)
	game.prompt = B.Label(area, E.tokens.size.small, "secondary", "RIGHT")
	game.prompt:SetPoint("TOPRIGHT", area, "TOPLEFT", n * cell - 2, -9)
	game.fx = B.Effects(area)
	return game
end

-- The board's ends: color -> { cell, cell }, and cell -> color.
function Ley:Ends()
	local board = self:Board()
	if self.endsFor == board then return self.ends, self.endAt end
	local ends, at = {}, {}
	for i = 1, #board do
		local letter = board:sub(i, i)
		local color = LETTERS:find(letter, 1, true)
		if color then
			ends[color] = ends[color] or {}
			table.insert(ends[color], i)
			at[i] = color
		end
	end
	self.ends, self.endAt, self.endsFor = ends, at, board
	return ends, at
end

function Ley:Board()
	local list = Boards(self.mode.size)
	local entry = list[self.pick or 1] or list[1]
	return entry and entry[1] or string.rep(".", self.mode.size ^ 2)
end

function Ley:Start()
	local list = Boards(self.mode.size)
	self.pick = #list > 0 and self.host.Random(1, #list) or 1
	self.paths, self.moves, self.sel = {}, 0, nil
	local n = self.mode.size
	self.cx, self.cy = math.ceil(n / 2), math.ceil(n / 2)
	self.fx:Clear()
	self.host.Score(0)
	self:Draw()
end

function Ley:Loaded()
	self.endsFor = nil
	self.lastCell = nil
end

-- cell -> color for every cell in a line (the ends too).
function Ley:Owners()
	local own = {}
	local _, at = self:Ends()
	for i, color in pairs(at) do own[i] = color end
	for color, path in pairs(self.paths) do
		for _, i in ipairs(path) do own[i] = tonumber(color) end
	end
	return own
end

function Ley:Done(color)
	local path = self.paths[color]
	local ends = self:Ends()[color]
	if not (path and ends and #path >= 2) then return false end
	local last = path[#path]
	return last ~= path[1] and (last == ends[1] or last == ends[2])
end

function Ley:Solved()
	local ends = self:Ends()
	for color in pairs(ends) do
		if not self:Done(color) then return false end
	end
	local own = self:Owners()
	for i = 1, self.mode.size ^ 2 do
		if not own[i] then return false end
	end
	return true
end

local function Find(path, cell)
	for k, i in ipairs(path or {}) do
		if i == cell then return k end
	end
end

-- A click (or Space) on a cell: a rune starts its line again, a cell of a
-- line goes back to it; anywhere else stops drawing.
function Ley:Select(cell)
	local _, at = self:Ends()
	local color = at[cell]
	if color then
		self.paths[color] = { cell }
	else
		for c, path in pairs(self.paths) do
			local k = Find(path, cell)
			if k then
				color = c
				for j = #path, k + 1, -1 do path[j] = nil end
				break
			end
		end
	end
	if color and not self:Done(color) then
		self.sel = color
		self.moves = self.moves + 1
		self.host.Score(self.moves)
		self.host.Sound("turn")
	else
		self.sel = nil
	end
	self:Draw()
end

local function Adjacent(n, a, b)
	local ax, ay = (a - 1) % n, math.floor((a - 1) / n)
	local bx, by = (b - 1) % n, math.floor((b - 1) / n)
	return math.abs(ax - bx) + math.abs(ay - by) == 1
end
Ley.Adjacent = Adjacent

-- The line being drawn goes one cell on. True when the line changed.
function Ley:Extend(cell)
	local color = self.sel
	local path = color and self.paths[color]
	if not path then return false end
	local head = path[#path]
	if cell == head then return false end
	local back = Find(path, cell)
	if back then
		for j = #path, back + 1, -1 do path[j] = nil end
		self:Draw()
		return true
	end
	if self:Done(color) or not Adjacent(self.mode.size, head, cell) then return false end
	local _, at = self:Ends()
	if at[cell] then
		if at[cell] ~= color or cell == path[1] then return false end
		path[#path + 1] = cell
		self.sel = nil
		local n, size = self.mode.size, self.mode.cell
		local x, y = ((cell - 1) % n + 0.5) * size, TOP + (math.floor((cell - 1) / n) + 0.5) * size
		self.fx:Burst(x, y, self.host.Palette()[color], size * 1.6, 0.4)
		self.host.Sound("point")
		self:Draw()
		if self:Solved() then self:Win() end
		return true
	end
	-- Through another line: that line is cut back.
	for other, line in pairs(self.paths) do
		if other ~= color then
			local k = Find(line, cell)
			if k then
				for j = #line, k, -1 do line[j] = nil end
			end
		end
	end
	path[#path + 1] = cell
	self:Draw()
	return true
end

function Ley:Win()
	local n, size = self.mode.size, self.mode.cell
	for i = 1, n do
		self.fx:Sparks((i - 0.5) * size, TOP + (i - 0.5) * size, self.host.Color("gold"), 8, 140)
	end
	self.host.Over(true)
end

-- Draws toward a cell one step at a time (the pointer can jump cells).
function Ley:Toward(cell)
	local n = self.mode.size
	for _ = 1, n * 2 do
		local path = self.sel and self.paths[self.sel]
		if not path then return end
		local head = path[#path]
		if head == cell then return end
		local hx, hy = (head - 1) % n, math.floor((head - 1) / n)
		local tx, ty = (cell - 1) % n, math.floor((cell - 1) / n)
		if Find(path, cell) then
			self:Extend(cell)
			return
		end
		local stepX = tx ~= hx and { hx + (tx > hx and 1 or -1), hy } or nil
		local stepY = ty ~= hy and { hx, hy + (ty > hy and 1 or -1) } or nil
		local first, second = stepX, stepY
		if math.abs(ty - hy) > math.abs(tx - hx) then first, second = stepY, stepX end
		local moved = false
		for _, step in ipairs({ first or false, second or false }) do
			if step and self:Extend(step[2] * n + step[1] + 1) then
				moved = true
				break
			end
		end
		if not moved then return end
	end
end

function Ley:Key(key)
	local d = DIRS[key]
	local n = self.mode.size
	if d then
		local x = math.max(1, math.min(n, self.cx + d[1]))
		local y = math.max(1, math.min(n, self.cy + d[2]))
		if self.sel then
			self:Extend((y - 1) * n + x)
			local path = self.sel and self.paths[self.sel]
			local head = path and path[#path] or ((y - 1) * n + x)
			self.cx, self.cy = (head - 1) % n + 1, math.floor((head - 1) / n) + 1
		else
			self.cx, self.cy = x, y
		end
		self:Draw()
		return true
	end
	if key == "SPACE" or key == "ENTER" then
		if self.sel then
			self.sel = nil
			self:Draw()
		else
			self:Select((self.cy - 1) * n + self.cx)
		end
		return true
	end
	return false
end

function Ley:Press(button, x, y)
	if button ~= "LeftButton" or not (x and y) then return end
	local cx, cy = self.grid:CellAt(x, y, 0, TOP)
	if not cx then
		self.sel = nil
		self:Draw()
		return
	end
	local cell = (cy - 1) * self.mode.size + cx
	self.cx, self.cy = cx, cy
	local path = self.sel and self.paths[self.sel]
	if path and path[#path] == cell then
		self.sel = nil
		self:Draw()
		return
	end
	self:Select(cell)
	self.lastCell = cell
end

function Ley:Update(dt)
	self.fx:Update(dt)
	if not self.sel then return end
	local x, y = self.host.Cursor()
	local cx, cy = self.grid:CellAt(x or -1, y or -1, 0, TOP)
	if not cx then return end
	local cell = (cy - 1) * self.mode.size + cx
	if cell == self.lastCell then return end
	self.lastCell = cell
	self:Toward(cell)
end

function Ley:Summary()
	if not self.moves then return nil end
	return E:Plural(self.moves, "Joined in %d stroke", "Joined in %d strokes"):format(self.moves)
end

function Ley:Draw()
	local n, size = self.mode.size, self.mode.cell
	local palette, color = self.host.Palette(), self.host.Color
	local grid = self.grid
	local own = self:Owners()
	local _, at = self:Ends()
	local next = {}
	for _, path in pairs(self.paths or {}) do
		for k = 1, #path - 1 do
			next[path[k] .. ":" .. path[k + 1]] = true
			next[path[k + 1] .. ":" .. path[k]] = true
		end
	end
	local filled, total = 0, n * n
	for i = 1, total do
		local x, y = (i - 1) % n + 1, math.floor((i - 1) / n) + 1
		local c = own[i]
		local tint = c and palette[c]
		if c then filled = filled + 1 end
		grid:Paint(x, y, tint or color("dim"), tint and 0.22 or 0.3)
		local lineColor = tint or palette[1]
		local across = x < n and c and next[i .. ":" .. (i + 1)]
		self.across[i]:SetShown(across and true or false)
		if across then B.Fill(self.across[i], lineColor, 0.95) end
		local down = y < n and c and next[i .. ":" .. (i + n)]
		self.down[i]:SetShown(down and true or false)
		if down then B.Fill(self.down[i], lineColor, 0.95) end
		local onLine = c and not at[i]
		self.dots[i]:SetShown(onLine and true or false)
		if onLine then self.dots[i]:SetVertexColor(lineColor[1], lineColor[2], lineColor[3], 0.95) end
		local rune = at[i]
		self.runes[i]:SetShown(rune ~= nil)
		self.glow[i]:SetShown(rune ~= nil)
		if rune then
			local tone = palette[rune]
			self.runes[i]:SetVertexColor(tone[1], tone[2], tone[3], 1)
			local lit = self:Done(rune) or self.sel == rune
			self.glow[i]:SetVertexColor(tone[1], tone[2], tone[3], lit and 1 or 0.35)
		end
	end
	B.Art(self.cursor, "Ring", color("accent"), self.sel and 0.4 or 0.9)
	B.Place(self.cursor, (self.cx - 1) * size, (self.cy - 1) * size, grid.frame)
	local joined, count = 0, 0
	for c in pairs(self:Ends()) do
		count = count + 1
		if self:Done(c) then joined = joined + 1 end
	end
	self.tally:SetText(L["Joined %d of %d"]:format(joined, count))
	self.prompt:SetText(L["Filled %d%%"]:format(math.floor(filled / total * 100 + 0.5)))
end

M:RegisterGame({
	key = "leylines", order = 84, group = "puzzle",
	title = "Ley Lines", desc = "Join each pair of runes with a line and fill every cell.",
	controls = Key("Click a rune, then move the pointer to draw. Arrow keys and Space work too. P: pause."),
	icon = "Interface\\Icons\\Spell_Arcane_TeleportStormwind",
	modes = MODES, lower = true, unit = "moves",
	Size = function(mode) mode = ModeOf(mode) return mode.size * mode.cell, TOP + mode.size * mode.cell end,
	New = New,
})
