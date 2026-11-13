-- EldoUI Flight Games: Defend the Flight Master. Murlocs, boars and kodos
-- walk the road to the flight master; build archers, bombardiers and frost
-- casters beside the road to stop them. Every creature that gets through
-- costs a life. Gold comes from each one you stop; click a tower to train
-- it up, right-click to sell it. Hold out for fifteen waves.
-- Written from scratch for EldoUI.
local _, E = ...
local M = E.FlightGames
local Key = E.Key
local L = E.L
local B = M.Board

local COLS, ROWS, CELL = 14, 9, 40
local TOP, BAR = 30, 46
local WIDTH, HEIGHT = COLS * CELL, TOP + ROWS * CELL + BAR
local WAVES = 15
local GAP = 0.8                -- seconds between two creatures of a wave
local MASTER = "Interface\\Icons\\Ability_Mount_Gryphon_01"
local GOLD = "Interface\\Icons\\INV_Misc_Coin_01"
local MODES = {
	{ key = "easy", title = "Easy", gold = 140, lives = 25, hp = 0.8 },
	{ key = "normal", title = "Normal", gold = 110, lives = 20, hp = 1 },
	{ key = "hard", title = "Hard", gold = 100, lives = 15, hp = 1.3 },
}
-- The road, corner by corner, in cells (it enters from the left edge).
local ROAD = { { 0, 2 }, { 4, 2 }, { 4, 7 }, { 8, 7 }, { 8, 2 }, { 11, 2 }, { 11, 7 }, { 14, 7 } }
-- The towers, level by level: cost, damage, reach (cells), time between
-- shots; bombs hurt all round where they land, frost slows.
local TOWERS = {
	{ key = "archer", name = Key("Archer"), icon = "Interface\\Icons\\Ability_Hunter_SniperShot",
		cost = { 50, 40, 70 }, damage = { 9, 15, 24 }, reach = 2.6, rate = 0.6 },
	{ key = "bomb", name = Key("Bombardier"), icon = "Interface\\Icons\\INV_Misc_Bomb_04",
		cost = { 80, 60, 100 }, damage = { 22, 36, 56 }, reach = 2.2, rate = 1.6, splash = 0.9 },
	{ key = "frost", name = Key("Frost caster"), icon = "Interface\\Icons\\Spell_Frost_FrostBolt02",
		cost = { 70, 50, 80 }, damage = { 4, 7, 11 }, reach = 2.2, rate = 1.0, slow = 1.6 },
}
-- The creatures: life, speed (cells a second), gold, and their look.
local KINDS = {
	murloc = { hp = 22, speed = 1.6, gold = 5, display = B.DISPLAY.murloc, icon = "Interface\\Icons\\INV_Misc_Head_Murloc_01", scale = 1.3 },
	boar = { hp = 40, speed = 1.1, gold = 7, display = B.DISPLAY.boar, icon = "Interface\\Icons\\Ability_Hunter_Pet_Boar", scale = 1.2 },
	kodo = { hp = 160, speed = 0.7, gold = 25, display = B.DISPLAY.kodo, icon = "Interface\\Icons\\Ability_Mount_Kodo_01", scale = 1.5 },
}

local Defense = {}
Defense.__index = Defense
-- What a saved game keeps (the board, the score and the timers).
Defense.saveKeys = { "towers", "foes", "queue", "wave", "lives", "gold", "score", "phase", "pick", "spawn", "kills", "ending" }

local function ModeOf(mode)
	return mode and mode.gold and mode or MODES[2]
end

-- The road as points in window units, its legs and its length, and the
-- cells it covers.
local path, legs, length, onRoad = {}, {}, 0, {}
for i, p in ipairs(ROAD) do
	path[i] = { (p[1] - 0.5) * CELL, TOP + (p[2] - 0.5) * CELL }
	if i > 1 then
		local a = path[i - 1]
		local dx, dy = path[i][1] - a[1], path[i][2] - a[2]
		local d = math.sqrt(dx * dx + dy * dy)
		legs[#legs + 1] = { x = a[1], y = a[2], dx = dx / d, dy = dy / d, from = length, d = d }
		length = length + d
		local q = ROAD[i - 1]
		local sx, sy = p[1] > q[1] and 1 or p[1] < q[1] and -1 or 0, p[2] > q[2] and 1 or p[2] < q[2] and -1 or 0
		local cx, cy = q[1], q[2]
		while true do
			onRoad[cy * 100 + cx] = true
			if cx == p[1] and cy == p[2] then break end
			cx, cy = cx + sx, cy + sy
		end
	end
end
Defense.length = length

-- Where on the road a creature that has walked d is, and which way it faces.
local function Along(d)
	for _, leg in ipairs(legs) do
		if d <= leg.from + leg.d then
			local t = math.max(0, d - leg.from)
			return leg.x + leg.dx * t, leg.y + leg.dy * t, leg
		end
	end
	local last = legs[#legs]
	return last.x + last.dx * last.d, last.y + last.dy * last.d, last
end
Defense.Along = Along

local function Facing(leg)
	if leg.dx > 0 then return -math.pi / 2 elseif leg.dx < 0 then return math.pi / 2 end
	return leg.dy > 0 and math.pi or 0
end

-- The creatures of wave n, in the order they come.
local function Wave(n)
	local out = {}
	local count = 6 + n
	for i = 1, count do
		local kind = "boar"
		if n % 5 == 0 and i > count - math.floor(n / 5) then
			kind = "kodo"
		elseif (n >= 2 and i % 3 == 0) or (n >= 7 and i % 2 == 0) then
			kind = "murloc"
		end
		out[i] = kind
	end
	return out
end
Defense.Wave = Wave

local function Free(cx, cy) return cx >= 1 and cy >= 1 and cx <= COLS and cy <= ROWS and not onRoad[cy * 100 + cx] end
Defense.Free = Free

local function New(host, mode)
	local game = setmetatable({ host = host, mode = ModeOf(mode) }, Defense)
	local area = host.area
	game.grid = B.Grid(area, COLS, ROWS, CELL, { gap = 2 })
	game.grid.frame:SetPoint("TOPLEFT", area, "TOPLEFT", 0, -TOP)
	game.master = B.Actor(area, CELL, B.DISPLAY.gryphon, MASTER, { scale = 1.9, facing = math.pi / 2, animation = B.ANIM.stand })
	game.master:Place((COLS - 1) * CELL, TOP + (ROWS - 3) * CELL)
	game.views = { murloc = {}, boar = {}, kodo = {} }
	-- Bars, shots and effects sit on a layer above the creatures' models.
	local top = CreateFrame("Frame", nil, area)
	top:SetAllPoints(area)
	top:SetFrameLevel(area:GetFrameLevel() + 20)
	game.top = top
	game.bars, game.bolts = {}, {}
	game.levels = {}
	game.buttons = {}
	local y = TOP + ROWS * CELL + 8
	for i, tower in ipairs(TOWERS) do
		local x = 4 + (i - 1) * 132
		local button = { x = x, y = y, w = 126, h = BAR - 12 }
		button.fill = B.Slab(area, button.w, button.h, "BORDER")
		button.fill:Place(x, y)
		button.icon = B.Sprite(area, button.h - 8, button.h - 8, "ARTWORK")
		E:SetClientFile(button.icon, tower.icon, "Interface\\Icons\\INV_Misc_QuestionMark")
		E:TrimIcon(button.icon)
		B.Place(button.icon, x + 6, y + 4, area)
		button.text = B.Label(area, E.tokens.size.small, "body", "LEFT")
		button.text:SetPoint("LEFT", area, "TOPLEFT", x + button.h + 2, -(y + button.h / 2))
		game.buttons[i] = button
	end
	game.send = { x = WIDTH - 154, y = y, w = 150, h = BAR - 12 }
	game.send.fill = B.Slab(area, game.send.w, game.send.h, "BORDER")
	game.send.fill:Place(game.send.x, y)
	game.send.text = B.Label(area, E.tokens.size.small, "body")
	game.send.text:SetPoint("CENTER", area, "TOPLEFT", game.send.x + game.send.w / 2, -(y + game.send.h / 2))
	game.coin = B.Sprite(area, 18, 18, "ARTWORK")
	E:SetClientFile(game.coin, GOLD, "Interface\\Icons\\INV_Misc_QuestionMark")
	E:TrimIcon(game.coin)
	B.Place(game.coin, 4, 6, area)
	game.status = B.Label(area, E.tokens.size.cardTitle, "body", "LEFT")
	game.status:SetPoint("TOPLEFT", area, "TOPLEFT", 28, -6)
	game.prompt = B.Label(area, E.tokens.size.small, "secondary", "RIGHT")
	game.prompt:SetPoint("TOPRIGHT", area, "TOPLEFT", WIDTH - 4, -9)
	game.fx = B.Effects(top)
	return game
end

function Defense:Start()
	local mode = self.mode
	self.towers, self.foes, self.queue = {}, {}, {}
	self.wave, self.lives, self.gold, self.score, self.kills = 0, mode.lives, mode.gold, 0, 0
	self.phase, self.pick, self.spawn = "build", 1, 0
	self.shots, self.ending = {}, nil
	self.fx:Clear()
	self.host.Score(0)
	self:Draw()
end

function Defense:Loaded()
	self.shots = {}
	self.foes = type(self.foes) == "table" and self.foes or {}
	self.queue = type(self.queue) == "table" and self.queue or {}
	for _, tower in ipairs(self.towers or {}) do tower.wait = 0 end
	self:Draw()
end

function Defense:TowerAt(cx, cy)
	for i, tower in ipairs(self.towers) do
		if tower.x == cx and tower.y == cy then return tower, i end
	end
end

-- Builds the picked tower on a free cell, or trains the one there.
function Defense:Build(cx, cy)
	if not Free(cx, cy) then return false end
	local tower = self:TowerAt(cx, cy)
	local px, py = (cx - 0.5) * CELL, TOP + (cy - 0.5) * CELL
	if tower then
		local def = TOWERS[tower.kind]
		local cost = def.cost[tower.level + 1]
		if not cost or self.gold < cost then
			if cost then self.fx:Float(px, py - 12, L["Not enough gold"], self.host.Color("bad"), E.tokens.size.small) end
			return false
		end
		self.gold = self.gold - cost
		tower.level = tower.level + 1
		tower.spent = tower.spent + cost
		self.fx:Burst(px, py, self.host.Color("gold"), CELL * 1.6, 0.5)
		self.fx:Sparks(px, py, self.host.Color("gold"), 10, 90)
		self.host.Sound("point")
	else
		local def = TOWERS[self.pick or 1]
		if self.gold < def.cost[1] then
			self.fx:Float(px, py - 12, L["Not enough gold"], self.host.Color("bad"), E.tokens.size.small)
			return false
		end
		self.gold = self.gold - def.cost[1]
		self.towers[#self.towers + 1] = { kind = self.pick or 1, level = 1, x = cx, y = cy, wait = 0, spent = def.cost[1] }
		self.fx:Burst(px, py, self.host.Color("accent"), CELL * 1.4, 0.4)
		self.host.Sound("turn")
	end
	self:Draw()
	return true
end

-- Sells a tower for half of what it cost.
function Defense:Sell(cx, cy)
	local tower, i = self:TowerAt(cx, cy)
	if not tower then return false end
	local back = math.floor(tower.spent / 2)
	self.gold = self.gold + back
	table.remove(self.towers, i)
	self.fx:Float((cx - 0.5) * CELL, TOP + (cy - 0.5) * CELL - 12, "+" .. back, self.host.Color("gold"), E.tokens.size.small)
	self.host.Sound("turn")
	self:Draw()
	return true
end

-- Sends the next wave (only between waves).
function Defense:Send()
	if self.phase ~= "build" or self.wave >= WAVES then return false end
	self.wave = self.wave + 1
	self.queue = Wave(self.wave)
	self.phase, self.spawn = "wave", 0
	self.host.Sound("start")
	self.fx:Float(WIDTH / 2, TOP + ROWS * CELL / 2, L["Wave %d"]:format(self.wave), self.host.Color("warn"), E.tokens.size.cardTitle)
	self:Draw()
	return true
end

-- A creature's life on this wave and level.
function Defense:Life(kind)
	return math.floor(KINDS[kind].hp * (1.17 ^ (self.wave - 1)) * self.mode.hp + 0.5)
end

function Defense:Hurt(foe, damage)
	foe.hp = foe.hp - damage
	if foe.hp > 0 then return end
	local kind = KINDS[foe.kind]
	local x, y = Along(foe.d)
	self.gold = self.gold + kind.gold
	self.kills = self.kills + 1
	self.score = self.score + kind.gold * 2
	self.host.Score(self.score)
	self.fx:Sparks(x, y, self.host.Color("gold"), 8, 80)
	self.fx:Float(x, y - 14, "+" .. kind.gold, self.host.Color("gold"), E.tokens.size.small)
	self.host.Sound("point")
end

function Defense:Update(dt)
	self.fx:Update(dt)
	if self.phase ~= "wave" then
		if self.ending then
			self.ending = self.ending - dt
			if self.ending <= 0 then
				self.ending = nil
				self.host.Over(self.phase == "won")
			end
		end
		return
	end
	-- New creatures onto the road.
	self.spawn = self.spawn - dt
	if self.spawn <= 0 and #self.queue > 0 then
		local kind = table.remove(self.queue, 1)
		local life = self:Life(kind)
		self.foes[#self.foes + 1] = { kind = kind, hp = life, max = life, d = 0, slow = 0 }
		self.spawn = GAP
	end
	-- Walking.
	for i = #self.foes, 1, -1 do
		local foe = self.foes[i]
		local speed = KINDS[foe.kind].speed * CELL * (foe.slow > 0 and 0.5 or 1)
		foe.slow = math.max(0, foe.slow - dt)
		foe.d = foe.d + speed * dt
		if foe.d >= length then
			table.remove(self.foes, i)
			-- Through: shots on their way to it fly on to nothing.
			foe.gone = true
			local cost = foe.kind == "kodo" and 3 or 1
			self.lives = math.max(0, self.lives - cost)
			local x, y = Along(length)
			self.fx:Burst(x, y, self.host.Color("bad"), CELL * 1.8, 0.5)
			self.host.Sound("over")
		end
	end
	-- Shooting.
	for _, tower in ipairs(self.towers) do
		tower.wait = (tower.wait or 0) - dt
		if tower.wait <= 0 then
			local def = TOWERS[tower.kind]
			local tx, ty = (tower.x - 0.5) * CELL, TOP + (tower.y - 0.5) * CELL
			local reach = def.reach * CELL
			local target, best
			for _, foe in ipairs(self.foes) do
				local fx, fy = Along(foe.d)
				if (fx - tx) ^ 2 + (fy - ty) ^ 2 <= reach * reach and (not best or foe.d > best) then target, best = foe, foe.d end
			end
			if target then
				tower.wait = def.rate
				self.shots[#self.shots + 1] = { x = tx, y = ty, foe = target, kind = tower.kind, damage = def.damage[tower.level], level = tower.level }
			end
		end
	end
	-- Shots in flight.
	for i = #self.shots, 1, -1 do
		local shot = self.shots[i]
		local foe = shot.foe
		local fx, fy = Along(foe.d)
		local dx, dy = fx - shot.x, fy - shot.y
		local d = math.sqrt(dx * dx + dy * dy)
		local step = 360 * dt
		if d <= step or foe.hp <= 0 or foe.gone then
			table.remove(self.shots, i)
			if foe.hp > 0 and not foe.gone then
				local def = TOWERS[shot.kind]
				if def.splash then
					local r = def.splash * CELL
					for _, other in ipairs(self.foes) do
						local ox, oy = Along(other.d)
						if other.hp > 0 and (ox - fx) ^ 2 + (oy - fy) ^ 2 <= r * r then self:Hurt(other, shot.damage) end
					end
					self.fx:Burst(fx, fy, self.host.Palette()[2], r * 2, 0.35)
				else
					if def.slow then
						foe.slow = def.slow
						self.fx:Burst(fx, fy, self.host.Palette()[1], CELL, 0.3)
					end
					self:Hurt(foe, shot.damage)
				end
			end
		else
			shot.x, shot.y = shot.x + dx / d * step, shot.y + dy / d * step
		end
	end
	for i = #self.foes, 1, -1 do
		if self.foes[i].hp <= 0 then table.remove(self.foes, i) end
	end
	-- The wave and the game.
	if self.lives <= 0 then
		self.phase, self.ending = "lost", 1.2
		self.foes, self.queue, self.shots = {}, {}, {}
	elseif #self.queue == 0 and #self.foes == 0 then
		self.score = self.score + 20 * self.wave
		self.host.Score(self.score)
		if self.wave >= WAVES then
			self.score = self.score + self.lives * 25
			self.host.Score(self.score)
			self.phase, self.ending = "won", 1.4
			self.host.Sound("best")
		else
			self.phase = "build"
			self.fx:Float(WIDTH / 2, TOP + ROWS * CELL / 2, L["Wave cleared!"], self.host.Color("good"), E.tokens.size.cardTitle)
		end
	end
	self:DrawLive()
end

function Defense:Key(key)
	local n = tonumber(key)
	if n and TOWERS[n] then
		self.pick = n
		self:DrawLive()
		return true
	end
	if key == "SPACE" or key == "ENTER" then return self:Send() end
	return false
end

local function Inside(box, x, y) return x >= box.x and x <= box.x + box.w and y >= box.y and y <= box.y + box.h end

function Defense:Press(button, x, y)
	if not (x and y) or self.phase == "won" or self.phase == "lost" then return end
	for i, b in ipairs(self.buttons) do
		if Inside(b, x, y) then
			self.pick = i
			self:DrawLive()
			return
		end
	end
	if Inside(self.send, x, y) then
		self:Send()
		return
	end
	local cx, cy = self.grid:CellAt(x, y, 0, TOP)
	if not cx then return end
	if button == "RightButton" then
		self:Sell(cx, cy)
	else
		self:Build(cx, cy)
	end
end

function Defense:Summary()
	if not self.wave then return nil end
	return L["Wave %d of %d"]:format(self.wave, WAVES)
end

-- One view for each creature on the road, by kind.
function Defense:View(kind, n)
	local list = self.views[kind]
	local view = list[n]
	if not view then
		local def = KINDS[kind]
		view = B.Actor(self.host.area, CELL * 0.8, def.display, def.icon, { scale = def.scale, animation = B.ANIM.run })
		list[n] = view
	end
	return view
end

function Defense:Bar(n)
	local bar = self.bars[n]
	if not bar then
		bar = { back = B.Sprite(self.top, CELL * 0.7, 4, "ARTWORK"), fill = B.Sprite(self.top, CELL * 0.7, 4, "OVERLAY") }
		self.bars[n] = bar
	end
	return bar
end

-- The field: road, grass, towers and their levels (when they change).
function Defense:DrawField()
	local grid, palette, color, area = self.grid, self.host.Palette(), self.host.Color, self.host.area
	local bronze = E.tokens.palette.bronze
	for cy = 1, ROWS do
		for cx = 1, COLS do
			local tower = self:TowerAt(cx, cy)
			if tower then
				local icon = grid:Icon(cx, cy, TOWERS[tower.kind].icon, color("secondary"))
				if icon then icon:SetAlpha(1) end
			elseif onRoad[cy * 100 + cx] then
				grid:Paint(cx, cy, bronze, 0.5)
			else
				grid:Paint(cx, cy, palette[3], (cx + cy) % 2 == 0 and 0.34 or 0.28)
			end
		end
	end
	-- Tower levels as small pips.
	for i, tower in ipairs(self.towers) do
		local pips = self.levels[i]
		if not pips then
			pips = {}
			for k = 1, 3 do pips[k] = B.Dot(self.top, 6, nil, "OVERLAY") end
			self.levels[i] = pips
		end
		local gold = color("gold")
		for k, pip in ipairs(pips) do
			pip:SetShown(k <= tower.level)
			pip:SetVertexColor(gold[1], gold[2], gold[3], 1)
			B.Place(pip, (tower.x - 1) * CELL + 4 + (k - 1) * 8, TOP + tower.y * CELL - 10, area)
		end
	end
	for i = #self.towers + 1, #self.levels do
		for _, pip in ipairs(self.levels[i]) do pip:Hide() end
	end
end

-- What moves: creatures and their life bars, shots, gold and the bar.
function Defense:DrawLive()
	local palette, color, area = self.host.Palette(), self.host.Color, self.host.area
	-- Creatures and their life bars.
	local used = { murloc = 0, boar = 0, kodo = 0 }
	for n, foe in ipairs(self.foes) do
		used[foe.kind] = used[foe.kind] + 1
		local view = self:View(foe.kind, used[foe.kind])
		local x, y, leg = Along(foe.d)
		view:Place(x - CELL * 0.4, y - CELL * 0.4)
		view:Face(Facing(leg))
		view:SetShown(true)
		view:SetAlpha(foe.slow > 0 and 0.7 or 1)
		local bar = self:Bar(n)
		local share = math.max(0, foe.hp / foe.max)
		B.Fill(bar.back, color("dim"), 0.6)
		B.Fill(bar.fill, share > 0.5 and color("good") or share > 0.25 and color("warn") or color("bad"), 0.95)
		bar.fill:SetWidth(math.max(1, CELL * 0.7 * share))
		B.Place(bar.back, x - CELL * 0.35, y - CELL * 0.55, area)
		B.Place(bar.fill, x - CELL * 0.35, y - CELL * 0.55, area)
		bar.back:Show()
		bar.fill:Show()
	end
	for kind, list in pairs(self.views) do
		for k = used[kind] + 1, #list do list[k]:SetShown(false) end
	end
	for n = #self.foes + 1, #self.bars do
		self.bars[n].back:Hide()
		self.bars[n].fill:Hide()
	end
	-- Shots.
	for n, shot in ipairs(self.shots or {}) do
		local bolt = self.bolts[n]
		if not bolt then
			bolt = B.Dot(self.top, 7, nil, "OVERLAY")
			self.bolts[n] = bolt
		end
		local c = shot.kind == 3 and palette[1] or shot.kind == 2 and palette[2] or color("gold")
		bolt:SetVertexColor(c[1], c[2], c[3], 1)
		B.Place(bolt, shot.x - 3.5, shot.y - 3.5, area)
		bolt:Show()
	end
	for n = #(self.shots or {}) + 1, #self.bolts do self.bolts[n]:Hide() end
	-- The tower bar and the wave button.
	for i, b in ipairs(self.buttons) do
		local def = TOWERS[i]
		local picked = self.pick == i
		local afford = (self.gold or 0) >= def.cost[1]
		b.fill:Paint(picked and color("accent") or color("secondary"), picked and 0.55 or 0.25)
		b.text:SetText(("%s  %d"):format(L[def.name], def.cost[1]))
		b.text:SetTextColor(unpack(afford and color("body") or color("dim")))
	end
	local can = self.phase == "build" and (self.wave or 0) < WAVES
	self.send.fill:Paint(can and color("good") or color("dim"), can and 0.5 or 0.2)
	self.send.text:SetText(can and L["Send wave %d"]:format((self.wave or 0) + 1) or L["Wave %d of %d"]:format(self.wave or 0, WAVES))
	self.status:SetText(L["Gold %d, lives %d"]:format(self.gold or 0, self.lives or 0))
	local text
	if self.phase == "won" then
		text = L["The flight master is safe!"]
	elseif self.phase == "lost" then
		text = L["The flight master is overrun."]
	elseif self.phase == "build" and (self.wave or 0) == 0 then
		text = L["Build beside the road, then send the first wave."]
	elseif self.phase == "build" then
		text = L["Train or build, then send the next wave."]
	else
		text = L["Wave %d of %d"]:format(self.wave, WAVES)
	end
	self.prompt:SetText(text)
end

function Defense:Draw()
	self:DrawField()
	self:DrawLive()
end

M:RegisterGame({
	key = "defense", order = 35, group = "arcade",
	title = "Defend the Flight Master", desc = "Build towers beside the road and stop every creature before it reaches the flight master.",
	controls = Key("1 to 3 or the bar: pick a tower. Click: build or train. Right-click: sell. Space: next wave. P: pause."),
	icon = MASTER,
	modes = MODES,
	width = WIDTH, height = HEIGHT,
	New = New,
})
