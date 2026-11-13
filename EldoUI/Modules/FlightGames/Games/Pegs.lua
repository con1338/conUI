-- EldoUI Flight Games: Peg Runes. Every hole but one holds a rune stone.
-- A rune jumps over its neighbor in a straight line into an empty hole,
-- and the rune it jumped over is taken. Leave as few runes as you can:
-- one is a win, and one in the goal hole is the best of all (the middle of
-- the cross, the starting hole of the triangle). Every rune taken is a
-- point. Two boards: the cross and the triangle.
-- Written from scratch for EldoUI.
local _, E = ...
local M = E.FlightGames
local Key = E.Key
local L = E.L
local B = M.Board

local TOP = 30
local RUNE = "Interface\\Icons\\INV_Misc_Rune_01"
local MODES = {
	{ key = "cross", title = "Cross", size = 7, cell = 54 },
	{ key = "triangle", title = "Triangle", size = 5, cell = 72 },
}
local CROSS_DIRS = { { 0, 1 }, { 0, -1 }, { 1, 0 }, { -1, 0 } }
-- The triangle as rows 1 to 5 with r columns each; a skewed grid has six
-- neighbors.
local TRIANGLE_DIRS = { { 0, 1 }, { 0, -1 }, { 1, 0 }, { -1, 0 }, { 1, 1 }, { -1, -1 } }
local KEY_DIRS = { UP = { -1, 0 }, W = { -1, 0 }, DOWN = { 1, 0 }, S = { 1, 0 }, LEFT = { 0, -1 }, A = { 0, -1 }, RIGHT = { 0, 1 }, D = { 0, 1 } }

local Pegs = {}
Pegs.__index = Pegs
-- What a saved board keeps.
Pegs.saveKeys = { "holes", "history", "pick", "cr", "cc", "start" }

local function ModeOf(mode)
	return mode and mode.size and mode or MODES[1]
end

-- Is (r, c) a hole on the board?
local function Hole(mode, r, c)
	local n = mode.size
	if r < 1 or c < 1 or r > n or c > n then return false end
	if mode.key == "triangle" then return c <= r end
	local edge = (r <= 2 or r >= 6) and (c <= 2 or c >= 6)
	return not edge
end
Pegs.Hole = Hole

local function Index(mode, r, c) return (r - 1) * mode.size + c end

-- Where a hole sits, in play-area units (its center).
local function Spot(mode, r, c)
	local cell = mode.cell
	if mode.key == "triangle" then
		return (c - 1) * cell + (mode.size - r) * cell / 2 + cell / 2, TOP + (r - 1) * cell * 0.87 + cell / 2
	end
	return (c - 1) * cell + cell / 2, TOP + (r - 1) * cell + cell / 2
end
Pegs.Spot = Spot

local function New(host, mode)
	mode = ModeOf(mode)
	local game = setmetatable({ host = host, mode = mode, views = {} }, Pegs)
	local area, cell = host.area, mode.cell
	game.plate = B.Sprite(area, 10, 10, "BACKGROUND")
	for r = 1, mode.size do
		for c = 1, mode.size do
			if Hole(mode, r, c) then
				local x, y = Spot(mode, r, c)
				local view = {
					hole = B.Dot(area, cell * 0.42, nil, "BORDER"),
					rune = B.Sprite(area, cell * 0.72, cell * 0.72, "ARTWORK"),
					ring = B.Sprite(area, cell * 0.86, cell * 0.86, "OVERLAY"),
				}
				B.Place(view.hole, x - cell * 0.21, y - cell * 0.21, area)
				E:SetClientFile(view.rune, RUNE, "Interface\\Icons\\INV_Misc_QuestionMark")
				E:TrimIcon(view.rune)
				if view.rune.SetMask then pcall(view.rune.SetMask, view.rune, "Interface\\CharacterFrame\\TempPortraitAlphaMask") end
				B.Place(view.rune, x - cell * 0.36, y - cell * 0.36, area)
				B.Place(view.ring, x - cell * 0.43, y - cell * 0.43, area)
				game.views[Index(mode, r, c)] = view
			end
		end
	end
	game.tally = B.Label(area, E.tokens.size.cardTitle, "body", "LEFT")
	game.tally:SetPoint("TOPLEFT", area, "TOPLEFT", 2, -6)
	game.prompt = B.Label(area, E.tokens.size.small, "secondary", "RIGHT")
	local width = mode.size * cell
	game.prompt:SetPoint("TOPRIGHT", area, "TOPLEFT", width - 2, -9)
	game.fx = B.Effects(area)
	return game
end

-- The goal hole: the middle of the cross; on the triangle, where the last
-- rune can end, the hole that was empty at the start.
function Pegs:Middle()
	if self.mode.key == "triangle" then return 1, 1 end
	return 4, 4
end

function Pegs:Start()
	local mode = self.mode
	self.holes = {}
	for r = 1, mode.size do
		for c = 1, mode.size do
			if Hole(mode, r, c) then self.holes[Index(mode, r, c)] = true end
		end
	end
	-- The empty hole at the start is the goal hole.
	local er, ec = self:Middle()
	self.holes[Index(mode, er, ec)] = false
	self.start = self:Left()
	self.history, self.pick = {}, nil
	self.cr, self.cc = er, ec
	self.fx:Clear()
	self.host.Score(self:Taken())
	self:Draw()
end

function Pegs:Left()
	local count = 0
	for _, full in pairs(self.holes) do
		if full then count = count + 1 end
	end
	return count
end

-- The score: the runes taken so far.
function Pegs:Taken()
	return math.max(0, (self.start or 0) - self:Left())
end

function Pegs:Dirs()
	return self.mode.key == "triangle" and TRIANGLE_DIRS or CROSS_DIRS
end

-- The rune at (r, c) jumps to (tr, tc) when that is a legal jump.
function Pegs:CanJump(r, c, tr, tc)
	local mode = self.mode
	if not (Hole(mode, r, c) and Hole(mode, tr, tc)) then return false end
	if not self.holes[Index(mode, r, c)] or self.holes[Index(mode, tr, tc)] then return false end
	for _, d in ipairs(self:Dirs()) do
		if r + d[1] * 2 == tr and c + d[2] * 2 == tc then
			return self.holes[Index(mode, r + d[1], c + d[2])] and true or false
		end
	end
	return false
end

function Pegs:AnyMove()
	local mode = self.mode
	for r = 1, mode.size do
		for c = 1, mode.size do
			if Hole(mode, r, c) and self.holes[Index(mode, r, c)] then
				for _, d in ipairs(self:Dirs()) do
					if self:CanJump(r, c, r + d[1] * 2, c + d[2] * 2) then return true end
				end
			end
		end
	end
	return false
end

function Pegs:Jump(r, c, tr, tc)
	if not self:CanJump(r, c, tr, tc) then return false end
	local mode = self.mode
	local mr, mc = (r + tr) / 2, (c + tc) / 2
	self.holes[Index(mode, r, c)] = false
	self.holes[Index(mode, mr, mc)] = false
	self.holes[Index(mode, tr, tc)] = true
	self.history[#self.history + 1] = { r, c, tr, tc }
	local x, y = Spot(mode, mr, mc)
	self.fx:Sparks(x, y, self.host.Palette()[7], 6, 90)
	self.host.Sound("turn")
	self.pick = nil
	self.cr, self.cc = tr, tc
	self.host.Score(self:Taken())
	self:Draw()
	if not self:AnyMove() then self:Finish() end
	return true
end

function Pegs:Finish()
	local left = self:Left()
	local mr, mc = self:Middle()
	if left == 1 then
		local x, y = Spot(self.mode, self.cr, self.cc)
		self.fx:Sparks(x, y, self.host.Color("gold"), 16, 160)
		self.middle = self.holes[Index(self.mode, mr, mc)] and true or false
	end
	self.host.Sound(left == 1 and "point" or "over")
	self.host.Over(left == 1)
end

function Pegs:Undo()
	local last = table.remove(self.history)
	if not last then return end
	local mode = self.mode
	local r, c, tr, tc = last[1], last[2], last[3], last[4]
	self.holes[Index(mode, r, c)] = true
	self.holes[Index(mode, (r + tr) / 2, (c + tc) / 2)] = true
	self.holes[Index(mode, tr, tc)] = false
	self.pick, self.cr, self.cc = nil, r, c
	self.host.Score(self:Taken())
	self:Draw()
end

-- A click on a rune picks it; a click on an empty hole jumps the picked
-- rune there (or the only rune that can).
function Pegs:Choose(r, c)
	local mode = self.mode
	if not Hole(mode, r, c) then return end
	self.cr, self.cc = r, c
	if self.holes[Index(mode, r, c)] then
		self.pick = { r, c }
		self:Draw()
		return
	end
	if self.pick and self:Jump(self.pick[1], self.pick[2], r, c) then return end
	local from
	for _, d in ipairs(self:Dirs()) do
		local fr, fc = r - d[1] * 2, c - d[2] * 2
		if self:CanJump(fr, fc, r, c) then
			if from then from = nil break end
			from = { fr, fc }
		end
	end
	if from then self:Jump(from[1], from[2], r, c) else self:Draw() end
end

function Pegs:At(x, y)
	local mode = self.mode
	local best, bestD
	for r = 1, mode.size do
		for c = 1, mode.size do
			if Hole(mode, r, c) then
				local sx, sy = Spot(mode, r, c)
				local d = (sx - x) ^ 2 + (sy - y) ^ 2
				if d < (mode.cell * 0.5) ^ 2 and (not bestD or d < bestD) then best, bestD = { r, c }, d end
			end
		end
	end
	return best
end

function Pegs:Press(button, x, y)
	if button ~= "LeftButton" or not (x and y) then return end
	local spot = self:At(x, y)
	if spot then self:Choose(spot[1], spot[2]) end
end

function Pegs:Key(key)
	local d = KEY_DIRS[key]
	local mode = self.mode
	if d then
		local r, c = self.cr + d[1], self.cc + d[2]
		if mode.key == "triangle" then c = math.min(c, r) end
		if Hole(mode, r, c) then self.cr, self.cc = r, c end
		self:Draw()
		return true
	end
	if key == "SPACE" or key == "ENTER" then
		self:Choose(self.cr, self.cc)
		return true
	end
	if key == "U" or key == "BACKSPACE" then
		self:Undo()
		return true
	end
	return false
end

function Pegs:Update(dt)
	self.fx:Update(dt)
end

function Pegs:Summary()
	if not self.holes then return nil end
	local left = self:Left()
	if left == 1 and self.middle then
		return self.mode.key == "triangle" and L["One rune left, back in the starting hole!"] or L["One rune left, in the middle!"]
	end
	return E:Plural(left, "%d rune left", "%d runes left"):format(left)
end

function Pegs:Draw()
	local mode, area = self.mode, self.host.area
	local color = self.host.Color
	local width = mode.size * mode.cell
	local height = mode.key == "triangle" and (mode.size - 1) * mode.cell * 0.87 + mode.cell or mode.size * mode.cell
	self.plate:SetSize(width, height)
	B.Place(self.plate, 0, TOP, area)
	B.Tile(self.plate, color("dim"), 0.25)
	local mr, mc = self:Middle()
	for r = 1, mode.size do
		for c = 1, mode.size do
			local view = self.views[Index(mode, r, c)]
			if view then
				local full = self.holes and self.holes[Index(mode, r, c)]
				local shade = color("dim")
				view.hole:SetVertexColor(shade[1], shade[2], shade[3], r == mr and c == mc and 0.9 or 0.6)
				view.rune:SetShown(full and true or false)
				local picked = self.pick and self.pick[1] == r and self.pick[2] == c
				local here = self.cr == r and self.cc == c
				view.ring:SetShown(picked or here or false)
				if picked then
					B.Art(view.ring, "Ring", color("gold"), 1)
				elseif here then
					B.Art(view.ring, "Ring", color("accent"), 0.8)
				end
			end
		end
	end
	self.tally:SetText(E:Plural(self:Left(), "%d rune left", "%d runes left"):format(self:Left()))
	self.prompt:SetText(L["Jump a rune over its neighbor into an empty hole."])
end

M:RegisterGame({
	key = "pegs", order = 86, group = "puzzle",
	title = "Peg Runes", desc = "Jump runes over each other until one is left.",
	controls = Key("Click a rune, then the empty hole it jumps to. Arrow keys and Space work too. U: undo. P: pause."),
	icon = RUNE,
	modes = MODES, wins = true,
	actions = { { key = "U", label = "Undo" } },
	Size = function(mode)
		mode = ModeOf(mode)
		local height = mode.key == "triangle" and (mode.size - 1) * mode.cell * 0.87 + mode.cell or mode.size * mode.cell
		return mode.size * mode.cell, TOP + height
	end,
	New = New,
})
