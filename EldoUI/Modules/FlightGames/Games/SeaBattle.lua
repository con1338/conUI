-- EldoUI Flight Games: Sea Battle. Your fleet and the opponent's lie hidden
-- on two seas of ten by ten. Take turns firing at a square of the other
-- sea; a hit shows fire, a ship whose every square is hit sinks. Sink the
-- whole opposing fleet first, in as few shots as you can.
-- Written from scratch for EldoUI.
local _, E = ...
local M = E.FlightGames
local Key = E.Key
local L = E.L
local B = M.Board

local N, CELL = 10, 26
local TOP, SPLIT = 34, 290
local WIDTH, HEIGHT = SPLIT + N * CELL, TOP + N * CELL + 50
local THINK = 0.55
local MODES = {
	{ key = "easy", title = "Easy", aim = "random" },
	{ key = "normal", title = "Normal", aim = "parity" },
	{ key = "hard", title = "Hard", aim = "density" },
}
local SHIPS = {
	{ size = 5, name = Key("Galleon") },
	{ size = 4, name = Key("Frigate") },
	{ size = 3, name = Key("Brig") },
	{ size = 3, name = Key("Sloop") },
	{ size = 2, name = Key("Skiff") },
}
-- What a shot found: open water, fire on a ship, or water next to a sunk
-- ship (no two ships touch, so it is known to be empty).
local MISS, HIT, CLEAR = 1, 2, 3

local Sea = {}
Sea.__index = Sea
-- What a saved game keeps (the board, the score and the timers).
Sea.saveKeys = { "mine", "theirs", "myShots", "theirShots", "turn", "shots", "result", "last", "lastYou" }

local function ModeOf(mode)
	return mode and mode.aim and mode or MODES[2]
end

local function Index(x, y) return (y - 1) * N + x end
local function XY(i) return (i - 1) % N + 1, math.floor((i - 1) / N) + 1 end
local function Inside(x, y) return x >= 1 and y >= 1 and x <= N and y <= N end

-- A fleet laid out at random: for each ship its squares, and a sea of 100
-- squares that names the ship on each (0 for water). Ships never touch,
-- not even at a corner.
local function Fleet(random)
	for _ = 1, 200 do
		local sea, ships, ok = {}, {}, true
		for i = 1, N * N do sea[i] = 0 end
		for s, ship in ipairs(SHIPS) do
			local placed
			for _ = 1, 300 do
				local across = random(2) == 1
				local x = random(across and N - ship.size + 1 or N)
				local y = random(across and N or N - ship.size + 1)
				local squares, free = {}, true
				for k = 0, ship.size - 1 do
					local cx, cy = x + (across and k or 0), y + (across and 0 or k)
					for dy = -1, 1 do
						for dx = -1, 1 do
							local nx, ny = cx + dx, cy + dy
							if Inside(nx, ny) and sea[Index(nx, ny)] ~= 0 then free = false end
						end
					end
					squares[#squares + 1] = Index(cx, cy)
				end
				if free then
					for _, i in ipairs(squares) do sea[i] = s end
					ships[s] = squares
					placed = true
					break
				end
			end
			if not placed then ok = false break end
		end
		if ok then return { sea = sea, ships = ships } end
	end
end
Sea.Fleet = Fleet

-- True when every square of ship s has been hit.
local function Sunk(fleet, shots, s)
	for _, i in ipairs(fleet.ships[s]) do
		if shots[i] ~= HIT then return false end
	end
	return true
end
Sea.Sunk = Sunk

local function AllSunk(fleet, shots)
	for s = 1, #SHIPS do
		if not Sunk(fleet, shots, s) then return false end
	end
	return true
end

-- Fires at square i of a fleet: marks the shot, and the water around a
-- ship it sinks. Returns "miss", "hit" or "sunk", and the ship.
local function Fire(fleet, shots, i)
	local s = fleet.sea[i]
	if s == 0 then
		shots[i] = MISS
		return "miss"
	end
	shots[i] = HIT
	if not Sunk(fleet, shots, s) then return "hit", s end
	for _, square in ipairs(fleet.ships[s]) do
		local x, y = XY(square)
		for dy = -1, 1 do
			for dx = -1, 1 do
				local nx, ny = x + dx, y + dy
				if Inside(nx, ny) and not shots[Index(nx, ny)] then shots[Index(nx, ny)] = CLEAR end
			end
		end
	end
	return "sunk", s
end
Sea.Fire = Fire

-- The opponent's aim. Hits on a ship not yet sunk come first: along their
-- line when there are two, else next to the one. Otherwise it searches:
-- at random (easy), on every other square (normal), or where the ships
-- still afloat fit in the most ways (hard).
local function Aim(fleet, shots, aim, random)
	local open = {}
	local function Unknown(x, y) return Inside(x, y) and not shots[Index(x, y)] end
	local wounded = {}
	for i = 1, N * N do
		if shots[i] == HIT and not Sunk(fleet, shots, fleet.sea[i]) then wounded[#wounded + 1] = i end
	end
	if #wounded > 0 then
		local x1, y1 = XY(wounded[1])
		local x2, y2 = XY(wounded[#wounded])
		if #wounded >= 2 and aim ~= "random" then
			local across = y1 == y2
			if across then
				if Unknown(x1 - 1, y1) then open[#open + 1] = Index(x1 - 1, y1) end
				if Unknown(x2 + 1, y2) then open[#open + 1] = Index(x2 + 1, y2) end
			else
				if Unknown(x1, y1 - 1) then open[#open + 1] = Index(x1, y1 - 1) end
				if Unknown(x2, y2 + 1) then open[#open + 1] = Index(x2, y2 + 1) end
			end
		end
		if #open == 0 then
			for _, i in ipairs(wounded) do
				local x, y = XY(i)
				for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
					if Unknown(x + d[1], y + d[2]) then open[#open + 1] = Index(x + d[1], y + d[2]) end
				end
			end
		end
		if #open > 0 then return open[random(#open)] end
	end
	if aim == "density" then
		local heat, best = {}, 0
		for s, ship in ipairs(SHIPS) do
			if not Sunk(fleet, shots, s) then
				for y = 1, N do
					for x = 1, N do
						for _, across in ipairs({ true, false }) do
							local fits = true
							for k = 0, ship.size - 1 do
								if not Unknown(x + (across and k or 0), y + (across and 0 or k)) then fits = false break end
							end
							if fits then
								for k = 0, ship.size - 1 do
									local i = Index(x + (across and k or 0), y + (across and 0 or k))
									heat[i] = (heat[i] or 0) + 1
								end
							end
						end
					end
				end
			end
		end
		for i, h in pairs(heat) do
			if h > best then best, open = h, { i } elseif h == best then open[#open + 1] = i end
		end
		if #open > 0 then return open[random(#open)] end
	end
	for i = 1, N * N do
		local x, y = XY(i)
		if not shots[i] and (aim ~= "parity" or (x + y) % 2 == 0) then open[#open + 1] = i end
	end
	if #open == 0 then
		for i = 1, N * N do
			if not shots[i] then open[#open + 1] = i end
		end
	end
	return open[random(#open)]
end
Sea.Aim = Aim

local function New(host, mode)
	local game = setmetatable({ host = host, mode = ModeOf(mode) }, Sea)
	local area = host.area
	game.enemy = B.Grid(area, N, N, CELL, { gap = 2 })
	game.enemy.frame:SetPoint("TOPLEFT", area, "TOPLEFT", 0, -TOP)
	game.home = B.Grid(area, N, N, CELL, { gap = 2 })
	game.home.frame:SetPoint("TOPLEFT", area, "TOPLEFT", SPLIT, -TOP)
	game.marks = { enemy = {}, home = {} }
	for side, left in pairs({ enemy = 0, home = SPLIT }) do
		for i = 1, N * N do
			local x, y = XY(i)
			local dot = B.Dot(area, 8, nil, "OVERLAY")
			B.Place(dot, left + (x - 1) * CELL + CELL / 2 - 4, TOP + (y - 1) * CELL + CELL / 2 - 4, area)
			game.marks[side][i] = dot
		end
	end
	game.lastRing = B.Sprite(area, CELL + 2, CELL + 2, "OVERLAY")
	game.enemyTitle = B.Label(area, E.tokens.size.cardTitle, "body", "LEFT")
	game.enemyTitle:SetPoint("TOPLEFT", area, "TOPLEFT", 2, -6)
	game.homeTitle = B.Label(area, E.tokens.size.cardTitle, "body", "LEFT")
	game.homeTitle:SetPoint("TOPLEFT", area, "TOPLEFT", SPLIT + 2, -6)
	game.shotText = B.Label(area, E.tokens.size.small, "secondary", "RIGHT")
	game.shotText:SetPoint("TOPRIGHT", area, "TOPLEFT", N * CELL - 2, -9)
	game.bars = { enemy = {}, home = {} }
	for side, left in pairs({ enemy = 0, home = SPLIT }) do
		local x = left
		for s, ship in ipairs(SHIPS) do
			local bar = B.Sprite(area, ship.size * 9, 8, "ARTWORK")
			B.Place(bar, x, TOP + N * CELL + 10, area)
			game.bars[side][s] = bar
			x = x + ship.size * 9 + 8
		end
	end
	game.prompt = B.Label(area, E.tokens.size.small, "secondary")
	game.prompt:SetPoint("TOP", area, "TOPLEFT", WIDTH / 2, -(TOP + N * CELL + 28))
	game.fx = B.Effects(area)
	return game
end

function Sea:Start()
	local random = self.host.Random
	self.mine, self.theirs = Fleet(random), Fleet(random)
	self.myShots, self.theirShots = {}, {}
	self.turn, self.shots, self.result, self.last, self.lastYou = 1, 0, nil, nil, nil
	self.think, self.ending = nil, nil
	self.fx:Clear()
	self.host.Score(0)
	self:Draw()
end

function Sea:Loaded()
	self.think = (self.turn == -1 and not self.result) and THINK or nil
	-- Saved inside the end delay: the result is decided, so it ends.
	if self.result then self.ending = 0.3 end
end

-- Lays out your fleet again; only before your first shot.
function Sea:Reroll()
	if self.shots > 0 or self.result or next(self.theirShots) then return false end
	self.mine = Fleet(self.host.Random)
	self.host.Sound("turn")
	self:Draw()
	return true
end

function Sea:Key(key)
	if key == "R" then return self:Reroll() end
	return false
end

-- Where on the area a square of a side's sea sits (its middle).
local function Middle(i, left)
	local x, y = XY(i)
	return left + (x - 0.5) * CELL, TOP + (y - 0.5) * CELL
end

function Sea:Shoot(i)
	local result, s = Fire(self.theirs, self.myShots, i)
	self.shots = self.shots + 1
	self.last, self.lastYou = i, true
	self.host.Score(self.shots)
	local palette, color = self.host.Palette(), self.host.Color
	local x, y = Middle(i, 0)
	if result == "miss" then
		self.fx:Burst(x, y, palette[1], CELL, 0.3)
		self.host.Sound("turn")
	else
		self.fx:Burst(x, y, palette[2], CELL * 1.4, 0.4)
		self.fx:Sparks(x, y, palette[2], 10, 70)
		if result == "sunk" then
			self.host.Sound("best")
			self.fx:Float(x, y - 10, L["Sunk: %s!"]:format(L[SHIPS[s].name]), color("gold"), E.tokens.size.cardTitle)
		else
			self.host.Sound("point")
		end
	end
	if AllSunk(self.theirs, self.myShots) then return self:End("won") end
	self.turn, self.think = -1, THINK
	self:Draw()
end

function Sea:Answer()
	local i = Aim(self.mine, self.theirShots, self.mode.aim, self.host.Random)
	if not i then return end
	local result, s = Fire(self.mine, self.theirShots, i)
	self.last, self.lastYou = i, false
	local palette, color = self.host.Palette(), self.host.Color
	local x, y = Middle(i, SPLIT)
	if result == "miss" then
		self.fx:Burst(x, y, palette[1], CELL, 0.3)
	else
		self.fx:Burst(x, y, self.host.FactionColor(-1, palette), CELL * 1.4, 0.4)
		self.fx:Sparks(x, y, self.host.FactionColor(-1, palette), 8, 60)
		if result == "sunk" then
			self.fx:Float(x, y - 10, L["The %s sank your %s."]:format(self.host.FactionName(-1), L[SHIPS[s].name]), color("bad"), E.tokens.size.small)
			self.host.Sound("over")
		end
	end
	if AllSunk(self.mine, self.theirShots) then return self:End("lost") end
	self.turn = 1
	self:Draw()
end

function Sea:End(result)
	self.result, self.turn, self.think = result, 0, nil
	self.host.Sound(result == "won" and "best" or "over")
	self.ending = 1.4
	self:Draw()
end

function Sea:Press(button, x, y)
	if button ~= "LeftButton" or not (x and y) or self.turn ~= 1 or self.result then return end
	local cx, cy = self.enemy:CellAt(x, y, 0, TOP)
	if not cx then return end
	local i = Index(cx, cy)
	if self.myShots[i] then return end
	self:Shoot(i)
end

function Sea:Update(dt)
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
			self:Answer()
		end
	end
end

-- Ships still afloat.
local function Afloat(fleet, shots)
	local count = 0
	for s = 1, #SHIPS do
		if not Sunk(fleet, shots, s) then count = count + 1 end
	end
	return count
end

function Sea:Summary()
	if not self.theirs then return nil end
	return L["%s ships sunk: %d of %d"]:format(self.host.FactionName(-1), #SHIPS - Afloat(self.theirs, self.myShots), #SHIPS)
end

-- One sea: what is known of it, and (for your own) where your ships lie.
function Sea:DrawSea(grid, marks, fleet, shots, own)
	local palette, color = self.host.Palette(), self.host.Color
	local water, fire = palette[7], palette[2]
	for y = 1, N do
		for x = 1, N do
			local i = Index(x, y)
			local shot = shots[i]
			local s = fleet.sea[i]
			local dot = marks[i]
			dot:Hide()
			if shot == HIT then
				if Sunk(fleet, shots, s) then
					grid:Paint(x, y, own and self.host.FactionColor(-1, palette) or fire, 0.95)
				else
					grid:Paint(x, y, own and self.host.FactionColor(-1, palette) or fire, 0.6)
					local c = color("gold")
					dot:SetVertexColor(c[1], c[2], c[3], 1)
					dot:Show()
				end
			elseif own and s ~= 0 then
				grid:Paint(x, y, self.host.FactionColor(1, palette), 0.85)
			elseif shot == MISS then
				grid:Paint(x, y, water, 0.22)
				local c = color("body")
				dot:SetVertexColor(c[1], c[2], c[3], 0.7)
				dot:Show()
			elseif shot == CLEAR then
				grid:Paint(x, y, water, 0.16)
			else
				grid:Paint(x, y, water, (x + y) % 2 == 0 and 0.42 or 0.36)
			end
		end
	end
end

function Sea:Draw()
	local color = self.host.Color
	local palette = self.host.Palette()
	self:DrawSea(self.enemy, self.marks.enemy, self.theirs, self.myShots, false)
	self:DrawSea(self.home, self.marks.home, self.mine, self.theirShots, true)
	self.lastRing:SetShown(self.last ~= nil)
	if self.last then
		local x, y = XY(self.last)
		B.Art(self.lastRing, "Ring", color("gold"), 0.85)
		B.Place(self.lastRing, (self.lastYou and 0 or SPLIT) + (x - 1) * CELL - 1, TOP + (y - 1) * CELL - 1, self.host.area)
	end
	for side, pair in pairs({ enemy = { self.theirs, self.myShots }, home = { self.mine, self.theirShots } }) do
		for s, bar in ipairs(self.bars[side]) do
			local sunk = Sunk(pair[1], pair[2], s)
			B.Fill(bar, sunk and color("dim") or self.host.FactionColor(side == "home" and 1 or -1, palette), sunk and 0.35 or 0.9)
		end
	end
	self.enemyTitle:SetText(L["%s waters"]:format(self.host.FactionName(-1)))
	self.homeTitle:SetText(L["Your fleet"])
	self.shotText:SetText(E:Plural(self.shots, "%d shot", "%d shots"):format(self.shots))
	local text
	if self.result == "won" then
		text = L["The %s fleet is sunk: you win!"]:format(self.host.FactionName(-1))
	elseif self.result == "lost" then
		text = L["Your fleet is sunk."]
	elseif self.turn == 1 then
		text = self.shots == 0 and not next(self.theirShots) and L["Fire at a square of the %s's waters, or R for a new fleet."]:format(self.host.FactionName(-1))
			or L["Your shot."]
	else
		text = L["The %s takes aim..."]:format(self.host.FactionName(-1))
	end
	self.prompt:SetText(text)
end

M:RegisterGame({
	key = "seabattle", order = 170, group = "board",
	title = "Sea Battle", desc = "Find and sink the opposing fleet before it sinks yours.",
	controls = Key("Click a square of enemy waters. R: new fleet before the first shot. P: pause."),
	icon = "Interface\\Icons\\INV_Misc_Spyglass_03",
	modes = MODES, lower = true, unit = "shots",
	width = WIDTH, height = HEIGHT,
	New = New,
})
