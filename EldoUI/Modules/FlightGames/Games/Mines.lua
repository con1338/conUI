-- EldoUI Flight Games: Mines. Open every field that hides no mine. A
-- number tells how many of the eight fields around it hide one; a flag
-- marks a field you think is mined. The first field you open is always
-- safe. The time is the score: the faster, the better.
-- Written from scratch for EldoUI.
local _, E = ...
local M = E.FlightGames
local Key = E.Key
local B = M.Board

local MODES = {
	{ key = "small", title = "9 x 9, 10 mines", cols = 9, rows = 9, mines = 10, cell = 30 },
	{ key = "medium", title = "16 x 16, 40 mines", cols = 16, rows = 16, mines = 40, cell = 22 },
	{ key = "large", title = "30 x 16, 99 mines", cols = 30, rows = 16, mines = 99, cell = 19 },
}
local MINE = "Interface\\Icons\\INV_Misc_Bomb_04"
local FLAG = "Interface\\Icons\\INV_BannerPVP_02"
-- Number colors: 1 to 8 from the palette, in the order the counts rise.
local NUMBER = { 1, 3, 6, 7, 2, 4, 5, 1 }

local Mines = {}
Mines.__index = Mines
-- What a saved game keeps (the board, the score and the timers).
Mines.saveKeys = { "mine", "open", "flag", "count", "placed", "opened", "time", "over", "cx", "cy", "lost" }

local function ModeOf(mode)
	return mode and mode.cols and mode or MODES[1]
end

local function New(host, mode)
	mode = ModeOf(mode)
	local game = setmetatable({ host = host, mode = mode }, Mines)
	game.grid = B.Grid(host.area, mode.cols, mode.rows, mode.cell, { gap = 1 })
	game.grid.frame:SetPoint("TOPLEFT")
	game.labels = {}
	game.cursor = B.Sprite(game.grid.frame, mode.cell, mode.cell, "OVERLAY")
	game.cursor:SetDrawLayer("OVERLAY", 7)
	game.cursor:Hide()
	return game
end

function Mines:Index(x, y) return (y - 1) * self.mode.cols + x end

function Mines:Label(x, y)
	local index = self:Index(x, y)
	local label = self.labels[index]
	if not label then
		label = B.Label(self.grid.frame, math.min(E.tokens.size.section, self.mode.cell - 6), "body")
		local cell = self.mode.cell
		label:SetPoint("CENTER", self.grid.frame, "TOPLEFT", (x - 0.5) * cell, -(y - 0.5) * cell)
		self.labels[index] = label
	end
	return label
end

function Mines:Start()
	self.mine, self.open, self.flag, self.count = {}, {}, {}, {}
	self.placed = false
	self.opened = 0
	self.time = 0
	self.over = false
	self.cx, self.cy = math.ceil(self.mode.cols / 2), math.ceil(self.mode.rows / 2)
	self.host.Score(0)
	self:Draw()
end

function Mines:Around(x, y, fn)
	for dy = -1, 1 do
		for dx = -1, 1 do
			local nx, ny = x + dx, y + dy
			if (dx ~= 0 or dy ~= 0) and nx >= 1 and ny >= 1 and nx <= self.mode.cols and ny <= self.mode.rows then fn(nx, ny) end
		end
	end
end

-- Mines go down after the first field is opened, never on it or around it.
function Mines:Place(sx, sy)
	local spots = {}
	for y = 1, self.mode.rows do
		for x = 1, self.mode.cols do
			if math.abs(x - sx) > 1 or math.abs(y - sy) > 1 then spots[#spots + 1] = self:Index(x, y) end
		end
	end
	for n = 1, math.min(self.mode.mines, #spots) do
		local pick = self.host.Random(n, #spots)
		spots[n], spots[pick] = spots[pick], spots[n]
		self.mine[spots[n]] = true
	end
	for y = 1, self.mode.rows do
		for x = 1, self.mode.cols do
			local count = 0
			self:Around(x, y, function(nx, ny) if self.mine[self:Index(nx, ny)] then count = count + 1 end end)
			self.count[self:Index(x, y)] = count
		end
	end
	self.placed = true
end

function Mines:Reveal(x, y)
	if self.over then return end
	local index = self:Index(x, y)
	if self.open[index] or self.flag[index] then return end
	if not self.placed then self:Place(x, y) end
	if self.mine[index] then
		self.open[index] = true
		self.over = true
		self.lost = index
		self:Draw()
		self.host.Over(false)
		return
	end
	-- Open the field, and the fields around every empty one.
	local queue = { { x, y } }
	while #queue > 0 do
		local spot = table.remove(queue)
		local i = self:Index(spot[1], spot[2])
		if not self.open[i] and not self.flag[i] then
			self.open[i] = true
			self.opened = self.opened + 1
			if self.count[i] == 0 then
				self:Around(spot[1], spot[2], function(nx, ny) queue[#queue + 1] = { nx, ny } end)
			end
		end
	end
	self.host.Sound("turn")
	self:Draw()
	if self.opened >= self.mode.cols * self.mode.rows - self.mode.mines then
		self.over = true
		self.host.Score(math.max(1, math.floor(self.time + 0.5)))
		self.host.Over(true)
	end
end

function Mines:Flag(x, y)
	if self.over then return end
	local index = self:Index(x, y)
	if self.open[index] then return end
	self.flag[index] = not self.flag[index] or nil
	self:Draw()
end

function Mines:Press(button, x, y)
	local cx, cy = self.grid:CellAt(x, y)
	if not cx then return end
	self.cx, self.cy = cx, cy
	if button == "RightButton" then self:Flag(cx, cy) else self:Reveal(cx, cy) end
end

local MOVE = { UP = { 0, -1 }, W = { 0, -1 }, DOWN = { 0, 1 }, S = { 0, 1 }, LEFT = { -1, 0 }, A = { -1, 0 }, RIGHT = { 1, 0 }, D = { 1, 0 } }

function Mines:Key(key)
	local move = MOVE[key]
	if move then
		self.cx = math.max(1, math.min(self.mode.cols, self.cx + move[1]))
		self.cy = math.max(1, math.min(self.mode.rows, self.cy + move[2]))
		self.showCursor = true
		self:Draw()
		return true
	end
	if key == "SPACE" or key == "ENTER" then
		self:Reveal(self.cx, self.cy)
		return true
	end
	if key == "F" then
		self:Flag(self.cx, self.cy)
		return true
	end
	return false
end

function Mines:Update(dt)
	if not self.placed or self.over then return end
	local before = math.floor(self.time)
	self.time = self.time + dt
	if math.floor(self.time) ~= before then self.host.Score(math.floor(self.time)) end
end

function Mines:Draw()
	local grid, palette = self.grid, self.host.Palette()
	for y = 1, self.mode.rows do
		for x = 1, self.mode.cols do
			local index = self:Index(x, y)
			local label = self.labels[index]
			if label then label:SetText("") end
			if self.open and self.open[index] then
				if self.mine[index] then
					grid:Icon(x, y, MINE, index == self.lost and self.host.Color("bad") or nil)
				else
					grid:Paint(x, y, self.host.Color("dim"), 0.18)
					local count = self.count[index]
					if count and count > 0 then
						label = self:Label(x, y)
						label:SetText(count)
						local c = palette[NUMBER[count]]
						label:SetTextColor(c[1], c[2], c[3])
					end
				end
			elseif self.flag and self.flag[index] then
				grid:Icon(x, y, FLAG, self.host.Color("secondary"))
			elseif self.over and self.mine and self.mine[index] then
				grid:Icon(x, y, MINE)
				local icon = grid:IconAt(x, y)
				if icon then icon:SetAlpha(0.6) end
			else
				grid:Paint(x, y, self.host.Color("secondary"), 0.55)
			end
		end
	end
	if self.showCursor and self.cx then
		B.Place(self.cursor, (self.cx - 1) * self.mode.cell, (self.cy - 1) * self.mode.cell, self.grid.frame)
		B.Art(self.cursor, "Ring", self.host.Color("accent"), 0.95)
		self.cursor:Show()
	else
		self.cursor:Hide()
	end
end

M:RegisterGame({
	key = "mines", order = 70, group = "puzzle",
	title = "Mines", desc = "Open every safe field; the numbers count the mines around.",
	controls = Key("Click: open. Right-click or F: flag. Arrow keys and Space work too."),
	icon = "Interface\\Icons\\INV_Misc_Bomb_04",
	lower = true, unit = "seconds",
	modes = MODES,
	Size = function(mode)
		mode = ModeOf(mode)
		return mode.cols * mode.cell, mode.rows * mode.cell
	end,
	New = New,
})
