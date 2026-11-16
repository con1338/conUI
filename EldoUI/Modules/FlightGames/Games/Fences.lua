-- EldoUI Flight Games: Fence the Pens. Posts stand in a grid; you and the
-- opponent take turns setting one fence between two neighboring posts. The
-- side that closes the fourth fence round a pen claims it and sets another
-- fence. When every pen is claimed, the side with more pens wins.
-- Written from scratch for EldoUI.
local _, E = ...
local M = E.FlightGames
local Key = E.Key
local L = E.L
local B = M.Board

local SPACE = 66
local LEFT, TOP = 20, 44
local THINK = 0.45
local MODES = {
	{ key = "small", title = "Small field", size = 4, aim = "greedy" },
	{ key = "normal", title = "Normal", size = 5, aim = "safe" },
	{ key = "hard", title = "Hard", size = 5, aim = "chains" },
}

local Fences = {}
Fences.__index = Fences
-- What a saved game keeps (the board, the score and the timers).
Fences.saveKeys = { "lines", "pens", "turn", "result", "last", "mine", "theirs" }

local function ModeOf(mode)
	return mode and mode.size and mode or MODES[2]
end

-- The fences of an n x n field of pens: across (h) and down (v) ones,
-- numbered 1 to 2n(n+1); the four fences of every pen; and the pens on
-- either side of every fence.
local shapes = {}
local function Shape(n)
	if shapes[n] then return shapes[n] end
	local shape = { n = n, edges = {}, sides = {}, touch = {} }
	local H = (n + 1) * n
	local function HId(r, c) return r * n + c end                 -- r 0..n, c 1..n
	local function VId(r, c) return H + (r - 1) * (n + 1) + c + 1 end -- r 1..n, c 0..n
	for r = 0, n do
		for c = 1, n do shape.edges[HId(r, c)] = { across = true, r = r, c = c } end
	end
	for r = 1, n do
		for c = 0, n do shape.edges[VId(r, c)] = { across = false, r = r, c = c } end
	end
	for r = 1, n do
		for c = 1, n do
			local pen = (r - 1) * n + c
			local list = { HId(r - 1, c), HId(r, c), VId(r, c - 1), VId(r, c) }
			shape.sides[pen] = list
			for _, e in ipairs(list) do
				shape.touch[e] = shape.touch[e] or {}
				table.insert(shape.touch[e], pen)
			end
		end
	end
	shape.count = H + n * (n + 1)
	shapes[n] = shape
	return shape
end
Fences.Shape = Shape

-- How many fences of a pen are set.
local function Sides(shape, lines, pen)
	local count = 0
	for _, e in ipairs(shape.sides[pen]) do
		if lines[e] then count = count + 1 end
	end
	return count
end

-- Sets fence e for side on a board (lines and pens changed in place) and
-- returns how many pens it closed.
local function Set(shape, lines, pens, e, side)
	lines[e] = side
	local closed = 0
	for _, pen in ipairs(shape.touch[e]) do
		if not pens[pen] and Sides(shape, lines, pen) == 4 then
			pens[pen] = side
			closed = closed + 1
		end
	end
	return closed
end
Fences.Set = Set

-- How many pens the other side could take in a row after fence e is set.
local function Gift(shape, lines, pens, e)
	local l, p = {}, {}
	for k, v in pairs(lines) do l[k] = v end
	for k, v in pairs(pens) do p[k] = v end
	l[e] = -1
	local taken = 0
	local again = true
	while again do
		again = false
		for pen = 1, shape.n * shape.n do
			if not p[pen] and Sides(shape, l, pen) == 3 then
				for _, side in ipairs(shape.sides[pen]) do
					if not l[side] then
						taken = taken + Set(shape, l, p, side, 1)
						again = true
						break
					end
				end
			end
		end
	end
	return taken
end
Fences.Gift = Gift

local function New(host, mode)
	local game = setmetatable({ host = host, mode = ModeOf(mode) }, Fences)
	local area = host.area
	local n = game.mode.size
	game.shape = Shape(n)
	game.penViews, game.lineViews, game.posts = {}, {}, {}
	for pen = 1, n * n do
		local r, c = math.floor((pen - 1) / n), (pen - 1) % n
		local tex = B.Sprite(area, SPACE - 10, SPACE - 10, "BORDER")
		B.Place(tex, LEFT + c * SPACE + 5, TOP + r * SPACE + 5, area)
		local mark = B.Sprite(area, SPACE - 30, SPACE - 30, "ARTWORK")
		B.Place(mark, LEFT + c * SPACE + 15, TOP + r * SPACE + 15, area)
		game.penViews[pen] = { tex = tex, mark = mark }
	end
	for e, edge in pairs(game.shape.edges) do
		local tex
		if edge.across then
			tex = B.Sprite(area, SPACE - 10, 6, "ARTWORK")
			B.Place(tex, LEFT + (edge.c - 1) * SPACE + 5, TOP + edge.r * SPACE - 3, area)
		else
			tex = B.Sprite(area, 6, SPACE - 10, "ARTWORK")
			B.Place(tex, LEFT + edge.c * SPACE - 3, TOP + (edge.r - 1) * SPACE + 5, area)
		end
		game.lineViews[e] = tex
	end
	for r = 0, n do
		for c = 0, n do
			local post = B.Dot(area, 10, nil, "OVERLAY")
			B.Place(post, LEFT + c * SPACE - 5, TOP + r * SPACE - 5, area)
			game.posts[#game.posts + 1] = post
		end
	end
	game.tally = B.Label(area, E.tokens.size.cardTitle, "body", "LEFT")
	game.tally:SetPoint("TOPLEFT", area, "TOPLEFT", 2, -6)
	game.prompt = B.Label(area, E.tokens.size.small, "secondary", "RIGHT")
	game.prompt:SetPoint("TOPRIGHT", area, "TOPLEFT", LEFT * 2 + n * SPACE - 2, -9)
	game.fx = B.Effects(area)
	return game
end

function Fences:Start()
	self.lines, self.pens = {}, {}
	self.turn, self.result, self.last, self.mine, self.theirs = 1, nil, nil, 0, 0
	self.think, self.ending = nil, nil
	self.fx:Clear()
	self.host.Score(0)
	self:Draw()
end

function Fences:Loaded()
	self.think = (self.turn == -1 and not self.result) and THINK or nil
	-- Saved inside the end delay: the result is decided, so it ends.
	if self.result then self.ending = 0.3 end
end

function Fences:Play(e, side)
	if self.result or self.lines[e] or not self.shape.edges[e] then return false end
	local before = {}
	for k, v in pairs(self.pens) do before[k] = v end
	local closed = Set(self.shape, self.lines, self.pens, e, side)
	self.last = e
	local n = self.shape.n
	if closed > 0 then
		for pen, owner in pairs(self.pens) do
			if not before[pen] then
				local r, c = math.floor((pen - 1) / n), (pen - 1) % n
				local x, y = LEFT + (c + 0.5) * SPACE, TOP + (r + 0.5) * SPACE
				self.fx:Burst(x, y, self.host.FactionColor(owner), SPACE * 1.2, 0.45)
				self.fx:Sparks(x, y, self.host.Color("gold"), 6, 70)
			end
		end
		if side == 1 then self.mine = self.mine + closed else self.theirs = self.theirs + closed end
		self.host.Score(self.mine)
		self.host.Sound("point")
	else
		self.host.Sound("turn")
		self.turn = -side
	end
	if self.mine + self.theirs == n * n then
		self.result = self.mine > self.theirs and "won" or self.mine < self.theirs and "lost" or "draw"
		self.host.Sound(self.result == "won" and "best" or "over")
		self.ending = 1.4
	elseif self.turn == -1 then
		self.think = THINK
	end
	self:Draw()
	return true
end

-- The opponent's fence: a pen to close if there is one, else a fence that
-- gives nothing away, else (on the hard level) the one that gives least.
function Fences:Choose()
	local shape, lines, pens, random = self.shape, self.lines, self.pens, self.host.Random
	local open, closing, safe = {}, {}, {}
	for e = 1, shape.count do
		if not lines[e] then
			open[#open + 1] = e
			local closes, gives = false, false
			for _, pen in ipairs(shape.touch[e]) do
				local s = Sides(shape, lines, pen)
				if s == 3 then closes = true elseif s == 2 then gives = true end
			end
			if closes then closing[#closing + 1] = e elseif not gives then safe[#safe + 1] = e end
		end
	end
	if #closing > 0 and (self.mode.aim ~= "greedy" or random(10) <= 8) then return closing[random(#closing)] end
	if #safe > 0 and self.mode.aim ~= "greedy" then return safe[random(#safe)] end
	if self.mode.aim == "chains" and #open > 0 then
		local best, least = {}, nil
		for _, e in ipairs(open) do
			local gift = Gift(shape, lines, pens, e)
			if not least or gift < least then best, least = { e }, gift elseif gift == least then best[#best + 1] = e end
		end
		return best[random(#best)]
	end
	if #safe > 0 and random(2) == 1 then return safe[random(#safe)] end
	return open[random(#open)]
end

-- The fence nearest a click, when it is close enough to one.
function Fences:EdgeAt(x, y)
	local n = self.shape.n
	local fx, fy = (x - LEFT) / SPACE, (y - TOP) / SPACE
	local best, dist
	for e, edge in pairs(self.shape.edges) do
		local d
		if edge.across then
			if fx >= edge.c - 1 and fx <= edge.c then d = math.abs(fy - edge.r) end
		else
			if fy >= edge.r - 1 and fy <= edge.r then d = math.abs(fx - edge.c) end
		end
		if d and d < 0.3 and (not dist or d < dist) then best, dist = e, d end
	end
	if best and fx >= -0.3 and fy >= -0.3 and fx <= n + 0.3 and fy <= n + 0.3 then return best end
end

function Fences:Press(button, x, y)
	if button ~= "LeftButton" or not (x and y) or self.turn ~= 1 or self.result then return end
	local e = self:EdgeAt(x, y)
	if e then self:Play(e, 1) end
end

function Fences:Update(dt)
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
			self.think = nil
			local e = self:Choose()
			if e then self:Play(e, -1) end
		end
	end
end

function Fences:Summary()
	if not self.mine then return nil end
	return L["%s %d, %s %d"]:format(self.host.FactionName(1), self.mine, self.host.FactionName(-1), self.theirs)
end

function Fences:Draw()
	local palette, color = self.host.Palette(), self.host.Color
	local bronze = E.tokens.palette.bronze
	for pen, view in ipairs(self.penViews) do
		local owner = self.pens[pen]
		B.Tile(view.tex, owner == 1 and self.host.FactionColor(1, palette) or owner == -1 and self.host.FactionColor(-1, palette) or palette[3], owner and 0.5 or 0.16)
		view.mark:SetShown(owner ~= nil)
		if owner then
			E:SetClientFile(view.mark, self.host.FactionIcon(owner),
				"Interface\\Icons\\INV_Misc_QuestionMark")
			E:TrimIcon(view.mark)
		end
	end
	for e, tex in pairs(self.lineViews) do
		local side = self.lines[e]
		if side then
			local c = e == self.last and color("gold") or bronze
			B.Fill(tex, c, 1)
		else
			B.Fill(tex, color("dim"), 0.18)
		end
	end
	local post = color("body")
	for _, dot in ipairs(self.posts) do dot:SetVertexColor(post[1], post[2], post[3], 0.9) end
	self.tally:SetText(L["%s %d, %s %d"]:format(self.host.FactionName(1), self.mine, self.host.FactionName(-1), self.theirs))
	local text
	if self.result == "won" then
		text = L["You win!"]
	elseif self.result == "lost" then
		text = L["The %s wins."]:format(self.host.FactionName(-1))
	elseif self.result == "draw" then
		text = L["A draw."]
	elseif self.turn == 1 then
		text = L["Click between two posts to set a fence."]
	else
		text = L["The %s is thinking..."]:format(self.host.FactionName(-1))
	end
	self.prompt:SetText(text)
end

M:RegisterGame({
	key = "fences", order = 175, group = "board",
	title = "Fence the Pens", desc = "Set fences in turn; close a pen to claim it and set another. Most pens wins.",
	controls = Key("Click between two posts. P: pause."),
	icon = "Interface\\Icons\\INV_Misc_Note_02",
	modes = MODES,
	Size = function(mode)
		local n = ModeOf(mode).size
		return LEFT * 2 + n * SPACE, TOP + n * SPACE + 20
	end,
	New = New,
})
