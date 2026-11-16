-- EldoUI Flight Games: Stone Pits. Six pits on each side, four stones in
-- each, and a store at either end. Take all the stones of one of your pits
-- and sow them one by one to the right and round the board, past your own
-- store but never into the opponent's. The last stone in your store gives you
-- another turn; the last in an empty pit of yours takes it and the stones
-- across from it. When one side runs out, the other keeps what is left;
-- the fuller store wins.
-- Written from scratch for EldoUI.
local _, E = ...
local M = E.FlightGames
local Key = E.Key
local L = E.L
local B = M.Board

local PIT, GAP = 60, 8
local TOP = 34
local STORE_W = 60
local WIDTH = STORE_W * 2 + 6 * (PIT + GAP) + GAP
local ROW_Y = { TOP + 10, TOP + 10 + PIT + 40 }
local HEIGHT = ROW_Y[2] + PIT + 40
local THINK = 0.6
local SOW = 0.12               -- seconds between two stones while sowing
local START = 4
local MODES = {
	{ key = "easy", title = "Easy", depth = 1, noise = 4 },
	{ key = "normal", title = "Normal", depth = 4, noise = 1 },
	{ key = "hard", title = "Hard", depth = 6, noise = 0 },
}
-- Pits 1 to 6 are yours (left to right), 7 your store, 8 to 13 the
-- opponent's (right to left along the top), 14 its store.
local YOURS, HORDE = 7, 14

local Pits = {}
Pits.__index = Pits
-- What a saved game keeps (the board, the score and the timers).
Pits.saveKeys = { "pits", "turn", "result", "last" }

local function ModeOf(mode)
	return mode and mode.depth and mode or MODES[2]
end

local function Own(i, side) return side == 1 and i >= 1 and i <= 6 or side == -1 and i >= 8 and i <= 13 end
local function Store(side) return side == 1 and YOURS or HORDE end

-- Plays pit i for side on a board (changed in place). Returns the pit the
-- last stone fell in, and whether that side goes again.
local function Sow(pits, i, side)
	local stones = pits[i]
	pits[i] = 0
	local at = i
	while stones > 0 do
		at = at % 14 + 1
		if at ~= Store(-side) then
			pits[at] = pits[at] + 1
			stones = stones - 1
		end
	end
	if Own(at, side) and pits[at] == 1 and pits[14 - at] > 0 then
		pits[Store(side)] = pits[Store(side)] + pits[14 - at] + 1
		pits[at], pits[14 - at] = 0, 0
	end
	-- One side out of stones: the other keeps what is left on its side.
	local mine, theirs = 0, 0
	for k = 1, 6 do mine = mine + pits[k] end
	for k = 8, 13 do theirs = theirs + pits[k] end
	if mine == 0 or theirs == 0 then
		for k = 1, 6 do pits[YOURS] = pits[YOURS] + pits[k] pits[k] = 0 end
		for k = 8, 13 do pits[HORDE] = pits[HORDE] + pits[k] pits[k] = 0 end
	end
	return at, at == Store(side)
end
Pits.Sow = Sow

local function Over(pits)
	for k = 1, 13 do
		if k ~= YOURS and pits[k] > 0 then return false end
	end
	return true
end
Pits.Over = Over

local function Copy(pits)
	local out = {}
	for k = 1, 14 do out[k] = pits[k] end
	return out
end

-- The opponent's view of a board: its store less yours, searched ahead.
-- Negamax with alpha-beta: a sowing that ends in your own store gives the
-- same side another turn (the same window, no sign change).
local function Search(pits, depth, side, alpha, beta)
	B.Tick()
	if depth == 0 or Over(pits) then return (pits[HORDE] - pits[YOURS]) * -side end
	alpha, beta = alpha or -math.huge, beta or math.huge
	local best = -math.huge
	for k = 1, 13 do
		if Own(k, side) and pits[k] > 0 then
			local next = Copy(pits)
			local _, again = Sow(next, k, side)
			local value
			if again and not Over(next) then
				value = Search(next, depth - 1, side, alpha, beta)
			else
				value = -Search(next, depth - 1, -side, -beta, -alpha)
			end
			if value > best then best = value end
			if best > alpha then alpha = best end
			if alpha >= beta then break end
		end
	end
	return best == -math.huge and 0 or best
end

local function New(host, mode)
	local game = setmetatable({ host = host, mode = ModeOf(mode) }, Pits)
	local area = host.area
	game.board = B.Slab(area, WIDTH, HEIGHT - TOP - 4, "BACKGROUND")
	game.board:Place(0, TOP - 4)
	game.views = {}
	for k = 1, 14 do
		local view = {}
		local x, y, w, h
		if k == YOURS then
			x, y, w, h = WIDTH - STORE_W - 2, ROW_Y[1], STORE_W - 6, ROW_Y[2] + PIT - ROW_Y[1]
		elseif k == HORDE then
			x, y, w, h = 8, ROW_Y[1], STORE_W - 6, ROW_Y[2] + PIT - ROW_Y[1]
		elseif k < YOURS then
			x, y, w, h = STORE_W + GAP + (k - 1) * (PIT + GAP), ROW_Y[2], PIT, PIT
		else
			x, y, w, h = STORE_W + GAP + (13 - k) * (PIT + GAP), ROW_Y[1], PIT, PIT
		end
		view.x, view.y, view.w, view.h = x, y, w, h
		view.hole = B.Sprite(area, w, h, "BORDER")
		B.Place(view.hole, x, y, area)
		view.ring = B.Sprite(area, w + 8, h + 8, "OVERLAY")
		B.Place(view.ring, x - 4, y - 4, area)
		view.gems = {}
		for g = 1, 12 do
			local gem = B.Dot(area, 11, nil, "ARTWORK")
			local col, row = (g - 1) % 4, math.floor((g - 1) / 4)
			local gx = x + w / 2 - 22 + col * 12 + (row % 2) * 4
			local gy = y + h / 2 - 16 + row * 11
			if k == YOURS or k == HORDE then gx, gy = x + w / 2 - 22 + col * 12, y + 24 + row * 11 end
			B.Place(gem, gx, gy, area)
			view.gems[g] = gem
		end
		view.count = B.Label(area, E.tokens.size.cardTitle, "body")
		if k == YOURS or k == HORDE then
			view.count:SetPoint("BOTTOM", area, "TOPLEFT", x + w / 2, -(y + h - 8))
		else
			view.count:SetPoint("TOP", area, "TOPLEFT", x + w / 2, -(k < YOURS and y + h + 4 or y - 18))
		end
		game.views[k] = view
	end
	game.tally = B.Label(area, E.tokens.size.cardTitle, "body", "LEFT")
	game.tally:SetPoint("TOPLEFT", area, "TOPLEFT", 2, -6)
	game.prompt = B.Label(area, E.tokens.size.small, "secondary", "RIGHT")
	game.prompt:SetPoint("TOPRIGHT", area, "TOPLEFT", WIDTH - 2, -9)
	game.fx = B.Effects(area)
	return game
end

function Pits:Start()
	self.pits = {}
	for k = 1, 14 do self.pits[k] = (k == YOURS or k == HORDE) and 0 or START end
	self.turn, self.result, self.last = 1, nil, nil
	self.think, self.ending, self.thread = nil, nil, nil
	self.fx:Clear()
	self.host.Score(0)
	self:Draw()
end

function Pits:Loaded()
	self.thread = nil
	self.think = (self.turn == -1 and not self.result) and THINK or nil
	-- Saved inside the end delay: the result is decided, so it ends.
	if self.result then self.ending = 0.3 end
end

function Pits:Middle(k)
	local view = self.views[k]
	return view.x + view.w / 2, view.y + view.h / 2
end

-- Plays pit k for side.
function Pits:Play(k, side)
	if self.result or not Own(k, side) or self.pits[k] == 0 then return false end
	local before = self.pits[Store(side)]
	local at, again = Sow(self.pits, k, side)
	self.last = at
	local x, y = self:Middle(at)
	local color = self.host.FactionColor(side)
	self.fx:Burst(x, y, color, 70, 0.4)
	local gained = self.pits[Store(side)] - before
	if gained > 1 then
		local sx, sy = self:Middle(Store(side))
		self.fx:Sparks(sx, sy, self.host.Color("gold"), 10, 90)
		self.fx:Float(sx, sy - 20, "+" .. gained, self.host.Color("gold"), E.tokens.size.cardTitle)
		self.host.Sound("point")
	else
		self.host.Sound("turn")
	end
	self.host.Score(self.pits[YOURS])
	if Over(self.pits) then
		local mine, theirs = self.pits[YOURS], self.pits[HORDE]
		self.result = mine > theirs and "won" or mine < theirs and "lost" or "draw"
		self.host.Sound(self.result == "won" and "best" or "over")
		self.ending = 1.4
	elseif again then
		self.turn = side
		self.fx:Float(x, y - 30, L["Again!"], self.host.Color("good"), E.tokens.size.small)
	else
		self.turn = -side
	end
	if self.turn == -1 and not self.result then self.think = THINK + SOW * 4 end
	self:Draw()
	return true
end

function Pits:Choose()
	local best, bestValue
	for k = 8, 13 do
		if self.pits[k] > 0 then
			local next = Copy(self.pits)
			local _, again = Sow(next, k, -1)
			local value
			if again and not Over(next) then
				value = Search(next, self.mode.depth - 1, -1)
			else
				value = -Search(next, self.mode.depth - 1, 1)
			end
			if self.mode.noise > 0 then value = value + self.host.Random(self.mode.noise) end
			if not bestValue or value > bestValue then best, bestValue = k, value end
		end
	end
	return best
end

function Pits:Key(key)
	local n = tonumber(key)
	if n and n >= 1 and n <= 6 and self.turn == 1 then
		self:Play(n, 1)
		return true
	end
	return false
end

function Pits:Press(button, x, y)
	if button ~= "LeftButton" or not (x and y) or self.turn ~= 1 or self.result then return end
	for k = 1, 6 do
		local view = self.views[k]
		if x >= view.x and x <= view.x + view.w and y >= view.y and y <= view.y + view.h then
			self:Play(k, 1)
			return
		end
	end
end

function Pits:Update(dt)
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
			local done, k = B.Pump(self.thread)
			if done then
				self.think, self.thread = nil, nil
				if k then self:Play(k, -1) end
			end
		end
	end
end

function Pits:Summary()
	if not self.pits then return nil end
	return L["Your store %d, the %s's %d"]:format(self.pits[YOURS], self.host.FactionName(-1), self.pits[HORDE])
end

function Pits:Draw()
	local palette, color = self.host.Palette(), self.host.Color
	self.board:Paint(E.tokens.palette.bronze, 0.22)
	local playable = self.turn == 1 and not self.result
	for k, view in ipairs(self.views) do
		local n = self.pits[k] or 0
		local store = k == YOURS or k == HORDE
		B.Tile(view.hole, store and self.host.FactionColor(k == YOURS and 1 or -1, palette) or color("dim"), store and 0.3 or 0.45)
		local gem = self.host.FactionColor(k >= 8 and -1 or 1, palette)
		for g, dot in ipairs(view.gems) do
			dot:SetShown(g <= n)
			dot:SetVertexColor(gem[1], gem[2], gem[3], 0.95)
		end
		view.count:SetText(n)
		local mark = playable and k <= 6 and n > 0
		view.ring:SetShown(mark or self.last == k)
		if mark then
			B.Art(view.ring, "Ring", color("accent"), 0.55)
		elseif self.last == k then
			B.Art(view.ring, "Ring", color("gold"), 0.8)
		end
	end
	self.tally:SetText(L["%s %d, %s %d"]:format(self.host.FactionName(1), self.pits[YOURS], self.host.FactionName(-1), self.pits[HORDE]))
	local text
	if self.result == "won" then
		text = L["You win!"]
	elseif self.result == "lost" then
		text = L["The %s wins."]:format(self.host.FactionName(-1))
	elseif self.result == "draw" then
		text = L["A draw."]
	elseif self.turn == 1 then
		text = L["Pick one of your pits."]
	else
		text = L["The %s is thinking..."]:format(self.host.FactionName(-1))
	end
	self.prompt:SetText(text)
end

M:RegisterGame({
	key = "stonepits", order = 165, group = "board",
	title = "Stone Pits", desc = "Sow stones round the board and fill your store before your opponent fills theirs.",
	controls = Key("Click one of your pits, or 1 to 6. P: pause."),
	icon = "Interface\\Icons\\INV_Misc_Gem_Ruby_01",
	modes = MODES,
	width = WIDTH, height = HEIGHT,
	New = New,
})
