-- EldoUI Flight Games: Dwarven Crates. Push every crate onto a marked
-- spot in the storeroom. You can push a crate but never pull it, and only
-- one at a time, so think before you push it into a corner. Ten rooms,
-- each a little harder; U takes a step back, R starts the room again.
-- Written from scratch for EldoUI, with its own rooms; you are your own
-- character.
local _, E = ...
local M = E.FlightGames
local Key = E.Key
local L = E.L
local B = M.Board

-- # wall, . spot, $ crate, * crate on a spot, @ you, + you on a spot.
local ROOMS = {
	{ "#####", "#@  #", "# $ #", "#  .#", "#####" },
	{ "  #### ", "###  # ", "#  $ ##", "# #.$.#", "#  @  #", "#######" },
	{ " #####", "##   #", "#  $ #", "# #. ##", "# . $@#", "#     #", "#######" },
	{ "######", "#    #", "# #$ #", "# .@ #", "#  $.#", "######" },
	{ "########", "#  .   #", "# $$#  #", "#  .@ ##", "######  " },
	{ "#######", "#.  ..#", "# $ $ #", "##$#  #", " #  @ #", " ######" },
	{ " ######", " #    #", "##$## #", "#  .  #", "# $.$ ##", "## .@  #", " #######" },
	{ "########", "#   #  #", "# $   $#", "#.##.# #", "#  $  .#", "## @ ###", " #####  " },
	{ "#########", "#   #   #", "# $ . $ #", "## # # ##", " #.@ .#  ", " # $$ #  ", " #  . #  ", " ######  " },
	{ "#######", "#  .  #", "# $#$ #", "#. @ .#", "# $#$ #", "#  .  #", "#######" },
}
local COLS, ROWS, CELL = 9, 8, 44
local HUD = 26
local DIRS = { UP = { 0, -1 }, W = { 0, -1 }, DOWN = { 0, 1 }, S = { 0, 1 }, LEFT = { -1, 0 }, A = { -1, 0 }, RIGHT = { 1, 0 }, D = { 1, 0 } }
local FACING = { [0] = { [-1] = 0, [1] = math.pi }, [-1] = { [0] = math.pi / 2 }, [1] = { [0] = -math.pi / 2 } }
local CRATE = "Interface\\Icons\\INV_Box_02"
local UNDO = 100

local Crates = {}
Crates.__index = Crates
-- What a saved game keeps (the board, the score and the timers).
Crates.saveKeys = { "room", "px", "py", "crates", "moves", "done", "undo", "total" }
Crates.ROOMS = ROOMS

local function Spot(x, y) return y * 100 + x end

local function New(host)
	local game = setmetatable({ host = host }, Crates)
	local area = host.area
	game.grid = B.Grid(area, COLS, ROWS, CELL, { gap = 3 })
	game.grid.frame:SetPoint("TOPLEFT")
	game.rings = {}
	game.boxes = {}
	game.hero = B.Actor(area, CELL, "player", "Interface\\Icons\\INV_Misc_Bag_08", { scale = 1.9, animation = B.ANIM.stand })
	game.info = B.Label(area, E.tokens.size.small, "secondary", "LEFT")
	game.info:SetPoint("TOPLEFT", area, "TOPLEFT", 4, -(ROWS * CELL + 6))
	game.fx = B.Effects(area)
	return game
end

-- The room's walls and spots, and where it sits on the board.
function Crates:Layout()
	local rows = ROOMS[self.room] or ROOMS[1]
	local width = 0
	for _, r in ipairs(rows) do width = math.max(width, #r) end
	local ox, oy = math.floor((COLS - width) / 2), math.floor((ROWS - #rows) / 2)
	local walls, spots = {}, {}
	local start
	for y, r in ipairs(rows) do
		for x = 1, #r do
			local c = r:sub(x, x)
			local X, Y = x + ox, y + oy
			if c == "#" then walls[Spot(X, Y)] = true end
			if c == "." or c == "*" or c == "+" then spots[Spot(X, Y)] = true end
			if c == "@" or c == "+" then start = { X, Y } end
		end
	end
	-- The floor: every square you can reach from the start.
	local floor, queue = {}, { start }
	floor[Spot(start[1], start[2])] = true
	while #queue > 0 do
		local p = table.remove(queue)
		for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
			local X, Y = p[1] + d[1], p[2] + d[2]
			local s = Spot(X, Y)
			if not walls[s] and not floor[s] and X >= 1 and Y >= 1 and X <= COLS and Y <= ROWS then
				floor[s] = true
				queue[#queue + 1] = { X, Y }
			end
		end
	end
	self.walls, self.spots, self.floor, self.ox, self.oy = walls, spots, floor, ox, oy
	return rows, ox, oy
end

function Crates:Enter(room)
	self.room = room
	local rows, ox, oy = self:Layout()
	self.crates = {}
	for y, r in ipairs(rows) do
		for x = 1, #r do
			local c = r:sub(x, x)
			if c == "$" or c == "*" then self.crates[#self.crates + 1] = { x + ox, y + oy } end
			if c == "@" or c == "+" then self.px, self.py = x + ox, y + oy end
		end
	end
	self.moves, self.undo, self.done = 0, {}, nil
end

function Crates:Start()
	self.total = 0
	self:Enter(1)
	self.host.Score(0)
	self:Draw()
end

function Crates:Loaded()
	self:Layout()
end

function Crates:CrateAt(x, y)
	for i, c in ipairs(self.crates) do
		if c[1] == x and c[2] == y then return i end
	end
end

function Crates:Solved()
	for _, c in ipairs(self.crates) do
		if not self.spots[Spot(c[1], c[2])] then return false end
	end
	return true
end

function Crates:Step(dx, dy)
	if self.done then return end
	local nx, ny = self.px + dx, self.py + dy
	if self.walls[Spot(nx, ny)] then return end
	local crate = self:CrateAt(nx, ny)
	if crate then
		local cx, cy = nx + dx, ny + dy
		if self.walls[Spot(cx, cy)] or self:CrateAt(cx, cy) then return end
	end
	local before = { px = self.px, py = self.py, crates = B.Copy(self.crates) }
	table.insert(self.undo, before)
	if #self.undo > UNDO then table.remove(self.undo, 1) end
	if crate then
		local c = self.crates[crate]
		c[1], c[2] = nx + dx, ny + dy
		if self.spots[Spot(c[1], c[2])] then
			self.fx:Burst((c[1] - 0.5) * CELL, (c[2] - 0.5) * CELL, self.host.Color("good"), CELL * 1.5, 0.4)
		end
	end
	self.px, self.py = nx, ny
	self.facing = FACING[dx] and FACING[dx][dy]
	self.moves = self.moves + 1
	self.host.Sound("turn")
	if self:Solved() then
		self.total = self.total + 1
		self.host.Score(self.total)
		self.host.Sound("point")
		self.fx:Sparks((self.px - 0.5) * CELL, (self.py - 0.5) * CELL, self.host.Color("gold"), 14, 180)
		self.done = 1.2
	end
	self:Draw()
end

function Crates:Back()
	local last = table.remove(self.undo)
	if not last or self.done then return end
	self.px, self.py, self.crates = last.px, last.py, last.crates
	self.moves = self.moves + 1
	self:Draw()
end

function Crates:Key(key)
	local d = DIRS[key]
	if d then
		self:Step(d[1], d[2])
		return true
	elseif key == "U" or key == "BACKSPACE" then
		self:Back()
		return true
	elseif key == "R" then
		if not self.done then self:Enter(self.room) self:Draw() end
		return true
	end
	return false
end

-- A click next to you steps that way.
function Crates:Press(button, x, y)
	if button ~= "LeftButton" or not (x and y) then return end
	local cx, cy = math.floor(x / CELL) + 1, math.floor(y / CELL) + 1
	local dx, dy = cx - self.px, cy - self.py
	if math.abs(dx) + math.abs(dy) == 1 then self:Step(dx, dy) end
end

function Crates:Update(dt)
	self.fx:Update(dt)
	if self.done then
		self.done = self.done - dt
		if self.done <= 0 then
			self.done = nil
			if self.room >= #ROOMS then
				self.host.Over(true)
				return
			end
			self:Enter(self.room + 1)
			self:Draw()
		end
	end
end

function Crates:Summary()
	if not self.total then return nil end
	return E:Plural(self.total, "%d room cleared", "%d rooms cleared"):format(self.total)
end

function Crates:Draw()
	local grid, color, area = self.grid, self.host.Color, self.host.area
	local palette = self.host.Palette()
	local stone = E.tokens.palette.bronze
	local rings = 0
	for y = 1, ROWS do
		for x = 1, COLS do
			local s = Spot(x, y)
			if self.walls[s] then
				grid:Paint(x, y, stone, 0.6 + ((x * 3 + y) % 3) * 0.08)
			elseif self.floor[s] then
				grid:Paint(x, y, color("dim"), 0.22)
				if self.spots[s] then
					rings = rings + 1
					local ring = self.rings[rings]
					if not ring then
						ring = B.Sprite(area, CELL - 14, CELL - 14, "ARTWORK")
						self.rings[rings] = ring
					end
					B.Art(ring, "Ring", color("gold"), 0.8)
					B.Place(ring, (x - 1) * CELL + 7, (y - 1) * CELL + 7, area)
					ring:Show()
				end
			else
				grid:Clear(x, y)
			end
		end
	end
	for i = rings + 1, #self.rings do self.rings[i]:Hide() end
	for i, c in ipairs(self.crates) do
		local box = self.boxes[i]
		if not box then
			box = { back = B.Sprite(area, CELL - 6, CELL - 6, "ARTWORK"), icon = B.Sprite(area, CELL - 14, CELL - 14, "OVERLAY") }
			E:SetClientFile(box.icon, CRATE, "Interface\\Icons\\INV_Misc_QuestionMark")
			E:TrimIcon(box.icon)
			self.boxes[i] = box
		end
		local home = self.spots[Spot(c[1], c[2])]
		B.Tile(box.back, home and color("good") or palette[2], 0.9)
		B.Place(box.back, (c[1] - 1) * CELL + 3, (c[2] - 1) * CELL + 3, area)
		B.Place(box.icon, (c[1] - 1) * CELL + 7, (c[2] - 1) * CELL + 7, area)
		box.back:Show()
		box.icon:Show()
	end
	for i = #self.crates + 1, #self.boxes do
		self.boxes[i].back:Hide()
		self.boxes[i].icon:Hide()
	end
	self.hero:Place((self.px - 1) * CELL, (self.py - 1) * CELL)
	if self.facing then self.hero:Face(self.facing) end
	self.info:SetText(L["Room %d of %d"]:format(self.room, #ROOMS) .. "   " ..
		E:Plural(self.moves, "%d step", "%d steps"):format(self.moves) .. "   " .. L["U: back. R: again."])
end

M:RegisterGame({
	key = "crates", order = 82, group = "puzzle",
	title = "Dwarven Crates", desc = "Push every crate onto its spot; ten storerooms, each harder.",
	controls = Key("Arrow keys, WASD or a click beside you: walk and push. U: back. R: again. P: pause."),
	actions = { { key = "U", label = "Undo" }, { key = "R", label = "Start over" } },
	icon = CRATE,
	width = COLS * CELL, height = ROWS * CELL + HUD,
	New = New,
})
