-- EldoUI Flight Games: Crest Match. Swap two crests side by side to line
-- up three or more of a kind; they clear, the crests above fall and new
-- ones drop in, and each chain that follows counts double. A game has 30
-- swaps; a swap that makes no line is taken back and costs nothing.
--
-- Points: 10 per crest cleared, times the chain step (1, 2, 3, ...), plus
-- 20 for each crest past three in one line.
-- Written from scratch for EldoUI; the crests are the game's class icons.
local _, E = ...
local L = E.L
local M = E.FlightGames
local Key = E.Key
local B = M.Board

local SIZE, CELL, TOP = 8, 44, 24
local KINDS = 6
local SWAPS = 30
local STEP = 0.18 -- the pause between two steps of a chain
local ICONS = {
	"Interface\\Icons\\ClassIcon_Mage", "Interface\\Icons\\ClassIcon_Druid", "Interface\\Icons\\ClassIcon_Hunter",
	"Interface\\Icons\\ClassIcon_Rogue", "Interface\\Icons\\ClassIcon_Paladin", "Interface\\Icons\\ClassIcon_Warrior",
}

local Gems = {}
Gems.__index = Gems
-- What a saved game keeps (the board, the score and the timers).
Gems.saveKeys = { "board", "score", "swaps", "chain", "cx", "cy" }

local function New(host)
	local game = setmetatable({ host = host }, Gems)
	game.grid = B.Grid(host.area, SIZE, SIZE, CELL, { gap = 4 })
	game.grid.frame:SetPoint("TOPLEFT", 0, -TOP)
	game.info = B.Label(host.area, E.tokens.size.label, "secondary", "LEFT")
	game.info:SetPoint("TOPLEFT", 0, -4)
	game.select = B.Sprite(game.grid.frame, CELL, CELL, "OVERLAY")
	game.select:SetDrawLayer("OVERLAY", 7)
	game.select:Hide()
	game.cursor = B.Sprite(game.grid.frame, CELL, CELL, "OVERLAY")
	game.cursor:SetDrawLayer("OVERLAY", 6)
	game.cursor:Hide()
	return game
end

function Gems:At(x, y) return self.board[y] and self.board[y][x] end

-- Would `kind` at x, y finish a line of three with the crests left or above?
function Gems:MakesLine(x, y, kind)
	return (x > 2 and self.board[y][x - 1] == kind and self.board[y][x - 2] == kind)
		or (y > 2 and self.board[y - 1][x] == kind and self.board[y - 2][x] == kind)
end

function Gems:Fill()
	self.board = {}
	for y = 1, SIZE do
		self.board[y] = {}
		for x = 1, SIZE do
			local kind
			repeat kind = self.host.Random(KINDS) until not self:MakesLine(x, y, kind)
			self.board[y][x] = kind
		end
	end
	if not self:HasMove() then self:Fill() end
end

-- Every crest that sits in a line of three or more: { [index] = true },
-- and the extra crests past three.
function Gems:Lines()
	local hit, extra = {}, 0
	local function Run(cells)
		if #cells >= 3 then
			for _, c in ipairs(cells) do hit[(c[2] - 1) * SIZE + c[1]] = true end
			extra = extra + #cells - 3
		end
	end
	for y = 1, SIZE do
		local run = {}
		for x = 1, SIZE + 1 do
			local kind = x <= SIZE and self.board[y][x]
			if kind and run[1] and self.board[y][run[1][1]] == kind then
				run[#run + 1] = { x, y }
			else
				Run(run)
				run = kind and { { x, y } } or {}
			end
		end
	end
	for x = 1, SIZE do
		local run = {}
		for y = 1, SIZE + 1 do
			local kind = y <= SIZE and self.board[y][x]
			if kind and run[1] and self.board[run[1][2]][x] == kind then
				run[#run + 1] = { x, y }
			else
				Run(run)
				run = kind and { { x, y } } or {}
			end
		end
	end
	return hit, extra
end

function Gems:Swap(ax, ay, bx, by)
	self.board[ay][ax], self.board[by][bx] = self.board[by][bx], self.board[ay][ax]
end

function Gems:HasMove()
	for y = 1, SIZE do
		for x = 1, SIZE do
			for _, d in ipairs({ { 1, 0 }, { 0, 1 } }) do
				local nx, ny = x + d[1], y + d[2]
				if nx <= SIZE and ny <= SIZE then
					self:Swap(x, y, nx, ny)
					local hit = self:Lines()
					self:Swap(x, y, nx, ny)
					if next(hit) then return true end
				end
			end
		end
	end
	return false
end

function Gems:Start()
	self.score, self.swaps, self.chain = 0, SWAPS, 0
	self.picked = nil
	self.busy = nil
	self.cx, self.cy = 1, 1
	self:Fill()
	self:Draw()
end

-- One step of a chain: clear the lines, let the crests fall, drop new ones.
function Gems:Clear()
	local hit, extra = self:Lines()
	if not next(hit) then return false end
	self.chain = self.chain + 1
	local count = 0
	for index in pairs(hit) do
		local x, y = (index - 1) % SIZE + 1, math.floor((index - 1) / SIZE) + 1
		self.board[y][x] = nil
		count = count + 1
	end
	self.score = self.score + (count * 10 + extra * 20) * self.chain
	self.host.Score(self.score)
	self.host.Sound("point")
	for x = 1, SIZE do
		local write = SIZE
		for y = SIZE, 1, -1 do
			if self.board[y][x] then
				self.board[write][x] = self.board[y][x]
				if write ~= y then self.board[y][x] = nil end
				write = write - 1
			end
		end
		for y = write, 1, -1 do self.board[y][x] = self.host.Random(KINDS) end
	end
	return true
end

function Gems:Try(ax, ay, bx, by)
	if math.abs(ax - bx) + math.abs(ay - by) ~= 1 then return false end
	self:Swap(ax, ay, bx, by)
	if not next((self:Lines())) then
		self:Swap(ax, ay, bx, by)
		self.host.Sound("turn")
		return false
	end
	self.swaps = self.swaps - 1
	self.chain = 0
	self.busy = 0
	self:Clear()
	return true
end

-- The chain runs one step at a time so the player sees it.
function Gems:Update(dt)
	if not self.busy then return end
	self.busy = self.busy + dt
	if self.busy < STEP then return end
	self.busy = 0
	if self:Clear() then
		self:Draw()
		return
	end
	self.busy = nil
	if self.swaps <= 0 then
		self:Draw()
		self.host.Over(true)
		return
	end
	if not self:HasMove() then
		-- No swap left on the board: a fresh board, the score stays.
		self:Fill()
	end
	self:Draw()
end

function Gems:Pick(x, y)
	if self.busy then return end
	local picked = self.picked
	if picked and (picked[1] ~= x or picked[2] ~= y) and math.abs(picked[1] - x) + math.abs(picked[2] - y) == 1 then
		self.picked = nil
		self:Try(picked[1], picked[2], x, y)
	elseif picked and picked[1] == x and picked[2] == y then
		self.picked = nil
	else
		self.picked = { x, y }
	end
	self:Draw()
end

function Gems:Press(button, x, y)
	if button ~= "LeftButton" then
		self.picked = nil
		self:Draw()
		return
	end
	local cx, cy = self.grid:CellAt(x, y, 0, TOP)
	if cx then
		self.cx, self.cy = cx, cy
		self:Pick(cx, cy)
	end
end

local MOVE = { UP = { 0, -1 }, W = { 0, -1 }, DOWN = { 0, 1 }, S = { 0, 1 }, LEFT = { -1, 0 }, A = { -1, 0 }, RIGHT = { 1, 0 }, D = { 1, 0 } }

function Gems:Key(key)
	local move = MOVE[key]
	if move then
		self.cx = math.max(1, math.min(SIZE, self.cx + move[1]))
		self.cy = math.max(1, math.min(SIZE, self.cy + move[2]))
		self.showCursor = true
		self:Draw()
		return true
	end
	if key == "SPACE" or key == "ENTER" then
		self:Pick(self.cx, self.cy)
		return true
	end
	return false
end

function Gems:Draw()
	local grid, palette = self.grid, self.host.Palette()
	for y = 1, SIZE do
		for x = 1, SIZE do
			local kind = self.board and self.board[y][x]
			if kind then
				local fill = palette[kind]
				grid:Icon(x, y, ICONS[kind], { fill[1], fill[2], fill[3], 0.35 })
			else
				grid:Clear(x, y)
			end
		end
	end
	local function Mark(tex, spot, alpha)
		if spot then
			B.Place(tex, (spot[1] - 1) * CELL, (spot[2] - 1) * CELL, self.grid.frame)
			B.Art(tex, "Ring", self.host.Color("accent"), math.min(1, alpha + 0.4))
			tex:Show()
		else
			tex:Hide()
		end
	end
	Mark(self.select, self.picked, 0.8)
	Mark(self.cursor, self.showCursor and { self.cx, self.cy } or nil, 0.35)
	self.info:SetText(L["Swaps left: %d"]:format(self.swaps or SWAPS))
end

-- A save inside a falling chain: the chain runs on, and a game whose last
-- swap was played ends.
function Gems:Loaded()
	self.picked, self.busy = nil, nil
	if type(self.board) == "table" and (next((self:Lines())) or (self.swaps or 1) <= 0) then self.busy = 0 end
end

M:RegisterGame({
	key = "gems", order = 50, group = "puzzle", wins = false,
	title = "Crest Match", desc = "Swap crests to line up three or more; chains count double.",
	controls = Key("Click two crests side by side to swap them. Arrow keys and Space work too."),
	icon = "Interface\\Icons\\INV_Misc_Gem_Amethyst_02",
	width = SIZE * CELL, height = SIZE * CELL + TOP,
	New = New,
})
