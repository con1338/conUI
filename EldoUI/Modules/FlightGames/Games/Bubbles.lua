-- EldoUI Flight Games: Mana Bubbles. Colored mana bubbles hang from the
-- ceiling. Aim the launcher and shoot one: it bounces off the walls and
-- sticks where it touches. Three or more of one color pop, and every
-- bubble no longer held to the ceiling falls. Every few shots the ceiling
-- comes down a row; clear the board before the bubbles reach you.
-- Written from scratch for EldoUI.
local _, E = ...
local M = E.FlightGames
local Key = E.Key
local L = E.L
local B = M.Board

local COLS, ROWS = 11, 14       -- a bubble in row ROWS ends the game
local R = 14                    -- a bubble's radius
local D = R * 2
local ROW_H = D * 0.866
local TOP = 34
local WIDTH = COLS * D + R
local HEIGHT = 440
local LX, LY = WIDTH / 2, HEIGHT - 34   -- the launcher
local SPEED, AIM_TURN, AIM_MAX = 620, 1.7, 1.35
local MODES = {
	{ key = "easy", title = "Easy", colors = 4, rows = 5, drop = 8 },
	{ key = "normal", title = "Normal", colors = 5, rows = 6, drop = 7 },
	{ key = "hard", title = "Hard", colors = 5, rows = 7, drop = 5 },
}
-- The palette entries the bubbles use, in order.
local HUES = { 6, 4, 3, 7, 5 }

local Bubbles = {}
Bubbles.__index = Bubbles
-- What a saved board keeps.
Bubbles.saveKeys = { "grid", "shift", "shots", "cur", "nxt", "angle", "shot", "score" }

local function ModeOf(mode)
	return mode and mode.colors and mode or MODES[2]
end

local function Index(r, c) return (r - 1) * COLS + c end

-- Is row r pushed half a bubble to the right?
local function Offset(shift, r) return (r + shift) % 2 == 1 end

local function Width(shift, r) return Offset(shift, r) and COLS - 1 or COLS end

local function Center(shift, r, c)
	return R + (c - 1) * D + (Offset(shift, r) and R or 0), TOP + R + (r - 1) * ROW_H
end
Bubbles.Center = Center

local function Neighbors(shift, r, c)
	local out = { { r, c - 1 }, { r, c + 1 } }
	local a, b = c - 1, c
	if Offset(shift, r) then a, b = c, c + 1 end
	for _, rr in ipairs({ r - 1, r + 1 }) do
		out[#out + 1] = { rr, a }
		out[#out + 1] = { rr, b }
	end
	local valid = {}
	for _, n in ipairs(out) do
		if n[1] >= 1 and n[1] <= ROWS and n[2] >= 1 and n[2] <= Width(shift, n[1]) then valid[#valid + 1] = n end
	end
	return valid
end
Bubbles.Neighbors = Neighbors

-- The bubbles of one color joined to (r, c).
local function Group(grid, shift, r, c)
	local hue = grid[Index(r, c)]
	local seen, out, stack = { [Index(r, c)] = true }, {}, { { r, c } }
	while #stack > 0 do
		local at = table.remove(stack)
		out[#out + 1] = at
		for _, n in ipairs(Neighbors(shift, at[1], at[2])) do
			local i = Index(n[1], n[2])
			if not seen[i] and grid[i] == hue then
				seen[i] = true
				stack[#stack + 1] = n
			end
		end
	end
	return out
end
Bubbles.Group = Group

-- The bubbles no longer held to the ceiling.
local function Loose(grid, shift)
	local held, stack = {}, {}
	for c = 1, Width(shift, 1) do
		if grid[Index(1, c)] ~= 0 then
			held[Index(1, c)] = true
			stack[#stack + 1] = { 1, c }
		end
	end
	while #stack > 0 do
		local at = table.remove(stack)
		for _, n in ipairs(Neighbors(shift, at[1], at[2])) do
			local i = Index(n[1], n[2])
			if not held[i] and grid[i] ~= 0 then
				held[i] = true
				stack[#stack + 1] = n
			end
		end
	end
	local out = {}
	for r = 1, ROWS do
		for c = 1, Width(shift, r) do
			local i = Index(r, c)
			if grid[i] ~= 0 and not held[i] then out[#out + 1] = { r, c } end
		end
	end
	return out
end
Bubbles.Loose = Loose

local function New(host, mode)
	local game = setmetatable({ host = host, mode = ModeOf(mode) }, Bubbles)
	local area = host.area
	game.ceiling = B.Sprite(area, WIDTH, 4, "BORDER")
	B.Place(game.ceiling, 0, TOP - 4, area)
	game.line = B.Sprite(area, WIDTH, 2, "BORDER")
	B.Place(game.line, 0, TOP + R + (ROWS - 1) * ROW_H - R, area)
	game.balls, game.gloss = {}, {}
	for i = 1, ROWS * COLS do
		game.balls[i] = B.Dot(area, D - 2, nil, "ARTWORK")
		game.gloss[i] = B.Sprite(area, D - 2, D - 2, "OVERLAY")
		B.Art(game.gloss[i], "Ring")
	end
	game.aim = {}
	for i = 1, 14 do game.aim[i] = B.Dot(area, 5, nil, "ARTWORK") end
	game.base = B.Sprite(area, 56, 20, "BORDER")
	B.Place(game.base, LX - 28, LY + 4, area)
	game.ball = B.Dot(area, D - 2, nil, "OVERLAY")
	game.next = B.Dot(area, R + 2, nil, "OVERLAY")
	B.Place(game.next, LX + 46, LY - (R + 2) / 2 + 6, area)
	game.nextLabel = B.Label(area, E.tokens.size.small, "secondary", "LEFT")
	game.nextLabel:SetPoint("LEFT", area, "TOPLEFT", LX + 46 + R + 8, -(LY + 6))
	game.flying = B.Dot(area, D - 2, nil, "OVERLAY")
	game.tally = B.Label(area, E.tokens.size.cardTitle, "body", "LEFT")
	game.tally:SetPoint("TOPLEFT", area, "TOPLEFT", 6, -8)
	game.prompt = B.Label(area, E.tokens.size.small, "secondary", "RIGHT")
	game.prompt:SetPoint("TOPRIGHT", area, "TOPLEFT", WIDTH - 6, -10)
	game.fx = B.Effects(area)
	game.keys = {}
	return game
end

-- A color for the launcher: one still on the board when there is one.
function Bubbles:Pick()
	local present, list = {}, {}
	for _, hue in ipairs(self.grid or {}) do
		if hue ~= 0 and not present[hue] then
			present[hue] = true
			list[#list + 1] = hue
		end
	end
	if #list == 0 then return self.host.Random(1, self.mode.colors) end
	table.sort(list)
	return list[self.host.Random(1, #list)]
end

function Bubbles:Start()
	self.grid = {}
	for i = 1, ROWS * COLS do self.grid[i] = 0 end
	self.shift, self.shots, self.score, self.angle, self.shot = 0, 0, 0, 0, nil
	for r = 1, self.mode.rows do
		for c = 1, Width(self.shift, r) do self.grid[Index(r, c)] = self.host.Random(1, self.mode.colors) end
	end
	self.cur, self.nxt = self:Pick(), self:Pick()
	self.keys, self.lastCursor = {}, nil
	self.fx:Clear()
	self.host.Score(0)
	self:Draw()
end

function Bubbles:Loaded()
	self.keys, self.lastCursor = {}, nil
end

function Bubbles:Fire()
	if self.shot then return end
	self.shot = { x = LX, y = LY, vx = math.sin(self.angle) * SPEED, vy = -math.cos(self.angle) * SPEED, hue = self.cur }
	self.cur, self.nxt = self.nxt, self:Pick()
	self.host.Sound("turn")
end

function Bubbles:Aim(x, y)
	local angle = math.atan2(x - LX, LY - y)
	self.angle = math.max(-AIM_MAX, math.min(AIM_MAX, angle))
end

local LEFTS, RIGHTS = { LEFT = true, A = true }, { RIGHT = true, D = true }

function Bubbles:Key(key)
	if LEFTS[key] or RIGHTS[key] then
		self.keys[key] = true
		return true
	elseif key == "SPACE" or key == "UP" or key == "W" then
		self:Fire()
		return true
	end
	return false
end

function Bubbles:KeyUp(key)
	self.keys[key] = nil
end

function Bubbles:Press(button, x, y)
	if button ~= "LeftButton" or not (x and y) then return end
	if y < LY then self:Aim(x, y) end
	self:Fire()
end

-- The empty cell nearest to a point, next to the ceiling or a bubble.
function Bubbles:Snap(x, y)
	local best, bestD
	local row = math.floor((y - TOP - R) / ROW_H + 0.5) + 1
	for r = math.max(1, row - 1), math.min(ROWS, row + 1) do
		for c = 1, Width(self.shift, r) do
			if self.grid[Index(r, c)] == 0 then
				local cx, cy = Center(self.shift, r, c)
				local d = (cx - x) ^ 2 + (cy - y) ^ 2
				if not bestD or d < bestD then best, bestD = { r, c }, d end
			end
		end
	end
	return best
end

-- Puts a bubble in a cell, pops its group and drops what hangs loose.
-- Returns how many popped and how many fell.
function Bubbles:Stick(r, c, hue)
	local grid = self.grid
	grid[Index(r, c)] = hue
	local popped, fell = 0, 0
	local group = Group(grid, self.shift, r, c)
	local palette = self.host.Palette()
	if #group >= 3 then
		for _, at in ipairs(group) do
			grid[Index(at[1], at[2])] = 0
			local x, y = Center(self.shift, at[1], at[2])
			self.fx:Sparks(x, y, palette[HUES[hue]], 4, 90)
		end
		popped = #group
		for _, at in ipairs(Loose(grid, self.shift)) do
			local x, y = Center(self.shift, at[1], at[2])
			self.fx:Burst(x, y, palette[HUES[grid[Index(at[1], at[2])]]] or palette[1], D * 1.5, 0.4)
			grid[Index(at[1], at[2])] = 0
			fell = fell + 1
		end
		local gained = popped * 10 + fell * 20
		self.score = self.score + gained
		self.host.Score(self.score)
		local x, y = Center(self.shift, r, c)
		self.fx:Float(x, y - 10, "+" .. gained, self.host.Color("gold"), E.tokens.size.cardTitle)
		self.host.Sound("point")
	end
	return popped, fell
end

-- The ceiling comes down a row: a new row of bubbles at the top.
function Bubbles:Lower()
	local grid = self.grid
	for r = ROWS, 2, -1 do
		for c = 1, COLS do grid[Index(r, c)] = grid[Index(r - 1, c)] end
	end
	self.shift = self.shift + 1
	for c = 1, COLS do grid[Index(1, c)] = 0 end
	for c = 1, Width(self.shift, 1) do grid[Index(1, c)] = self:Pick() end
	self.fx:Burst(WIDTH / 2, TOP, self.host.Color("secondary"), WIDTH * 0.6, 0.5)
end

function Bubbles:Empty()
	for _, hue in ipairs(self.grid) do
		if hue ~= 0 then return false end
	end
	return true
end

function Bubbles:Reached()
	for c = 1, COLS do
		if self.grid[Index(ROWS, c)] ~= 0 then return true end
	end
	return false
end

-- Moves the shot; true when it stuck.
function Bubbles:Fly(dt)
	local shot = self.shot
	local steps = math.max(1, math.ceil(SPEED * dt / 6))
	local step = dt / steps
	for _ = 1, steps do
		shot.x, shot.y = shot.x + shot.vx * step, shot.y + shot.vy * step
		if shot.x < R then shot.x, shot.vx = R, -shot.vx end
		if shot.x > WIDTH - R then shot.x, shot.vx = WIDTH - R, -shot.vx end
		local touch = shot.y - R <= TOP
		if not touch then
			for r = 1, ROWS do
				for c = 1, Width(self.shift, r) do
					if self.grid[Index(r, c)] ~= 0 then
						local cx, cy = Center(self.shift, r, c)
						if (cx - shot.x) ^ 2 + (cy - shot.y) ^ 2 < (D * 0.86) ^ 2 then
							touch = true
							break
						end
					end
				end
				if touch then break end
			end
		end
		if touch then return true end
	end
	return false
end

function Bubbles:Update(dt)
	self.fx:Update(dt)
	dt = dt * self.host.Pace()
	if self.keys and (self.keys.LEFT or self.keys.A) then self.angle = math.max(-AIM_MAX, self.angle - AIM_TURN * dt) end
	if self.keys and (self.keys.RIGHT or self.keys.D) then self.angle = math.min(AIM_MAX, self.angle + AIM_TURN * dt) end
	local x, y = self.host.Cursor()
	if x and y and x >= 0 and x <= WIDTH and y >= TOP and y < LY and (x .. ":" .. y) ~= self.lastCursor then
		self.lastCursor = x .. ":" .. y
		self:Aim(x, y)
	end
	if self.shot and self:Fly(dt) then
		local shot = self.shot
		self.shot = nil
		local cell = self:Snap(shot.x, shot.y)
		if cell then self:Stick(cell[1], cell[2], shot.hue) end
		self.shots = self.shots + 1
		if self:Empty() then
			self.score = self.score + 500
			self.host.Score(self.score)
			self.fx:Sparks(WIDTH / 2, HEIGHT / 2, self.host.Color("gold"), 16, 160)
			self:Draw()
			self.host.Over(true)
			return
		end
		if self.shots % self.mode.drop == 0 then self:Lower() end
		if self:Reached() then
			self:Draw()
			self.host.Over(false)
			return
		end
	end
	self:Draw()
end

function Bubbles:Draw()
	local area = self.host.area
	local palette, color = self.host.Palette(), self.host.Color
	B.Fill(self.ceiling, E.tokens.palette.bronze, 0.8)
	B.Fill(self.line, palette[6], 0.35)
	local shift = self.shift or 0
	local dim = color("body")
	for r = 1, ROWS do
		for c = 1, COLS do
			local i = Index(r, c)
			local hue = self.grid and self.grid[i] or 0
			local ball, gloss = self.balls[i], self.gloss[i]
			local shown = hue ~= 0 and c <= Width(shift, r)
			ball:SetShown(shown)
			gloss:SetShown(shown)
			if shown then
				local x, y = Center(shift, r, c)
				local tint = palette[HUES[hue]] or palette[1]
				ball:SetVertexColor(tint[1], tint[2], tint[3], 1)
				B.Place(ball, x - R + 1, y - R + 1, area)
				gloss:SetVertexColor(dim[1], dim[2], dim[3], 0.35)
				B.Place(gloss, x - R + 1, y - R + 1, area)
			end
		end
	end
	-- The aim line, with one bounce off a wall.
	local ax, ay = LX, LY
	local vx, vy = math.sin(self.angle or 0), -math.cos(self.angle or 0)
	for i, dot in ipairs(self.aim) do
		for _ = 1, 22 do
			ax, ay = ax + vx, ay + vy
			if ax < R or ax > WIDTH - R then vx = -vx end
		end
		dot:SetShown(ay > TOP and not self.shot)
		dot:SetVertexColor(dim[1], dim[2], dim[3], 0.6 - i * 0.03)
		B.Place(dot, ax - 2.5, ay - 2.5, area)
	end
	B.Tile(self.base, E.tokens.palette.bronze, 0.7)
	local cur = palette[HUES[self.cur or 1]] or palette[1]
	self.ball:SetVertexColor(cur[1], cur[2], cur[3], 1)
	B.Place(self.ball, LX - R + 1, LY - R + 1, area)
	local nxt = palette[HUES[self.nxt or 1]] or palette[1]
	self.next:SetVertexColor(nxt[1], nxt[2], nxt[3], 1)
	self.nextLabel:SetText(L["Next"])
	self.flying:SetShown(self.shot ~= nil)
	if self.shot then
		local tint = palette[HUES[self.shot.hue]] or palette[1]
		self.flying:SetVertexColor(tint[1], tint[2], tint[3], 1)
		B.Place(self.flying, self.shot.x - R + 1, self.shot.y - R + 1, area)
	end
	local left = self.mode.drop - (self.shots or 0) % self.mode.drop
	self.tally:SetText(L["Score %d"]:format(self.score or 0))
	self.prompt:SetText(E:Plural(left, "The ceiling drops in %d shot", "The ceiling drops in %d shots"):format(left))
end

function Bubbles:Summary()
	if not self.shots then return nil end
	return E:Plural(self.shots, "%d shot", "%d shots"):format(self.shots)
end

M:RegisterGame({
	key = "bubbles", order = 46, group = "arcade", wins = true,
	title = "Mana Bubbles", desc = "Shoot mana bubbles; three of a color pop. Clear the ceiling.",
	controls = Key("Aim with the mouse or Left and Right. Click, Space or Up: shoot. P: pause."),
	icon = "Interface\\Icons\\Spell_Frost_FrostNova",
	modes = MODES,
	width = WIDTH, height = HEIGHT,
	New = New,
})
