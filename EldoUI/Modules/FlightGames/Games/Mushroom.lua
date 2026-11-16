-- Gnome Dash: manual movement through ten original courses.
-- World rectangles use board coordinates, with y increasing downward.
local _, E = ...
local M = E.FlightGames
local B, L = M.Board, E.L
local levels = M.MushroomLevels
local appearance = M.MushroomAppearance

local WIDTH, HEIGHT = 640, 360
local LIVES, SPEED, GRAVITY, JUMP = 4, 232, 1700, 640
local MAX_STEP, MAX_FRAME = 1 / 90, 0.1
local COIN, STOMP, COURSE = 10, 25, 100
local CAPS = "Interface\\Icons\\INV_Mushroom_13"
local COINS = "Interface\\Icons\\INV_Misc_Coin_01"
local BANNER = "Interface\\Icons\\INV_Banner_01"
local SPIKES = "Interface\\Icons\\INV_Misc_Bomb_09"
local SPIDER = "Interface\\Icons\\Ability_Hunter_Pet_Spider"
local BOAR = "Interface\\Icons\\Ability_Hunter_Pet_Boar"
local GROVE_ART = {
	"Interface\\Icons\\INV_Mushroom_04", "Interface\\Icons\\INV_Mushroom_07", CAPS,
}
local HEROES = {
	small = { w = 21, h = 26, size = 35, icon = "Interface\\Icons\\Achievement_Character_Gnome_Male" },
	big = { w = 29, h = 39, size = 49, icon = "Interface\\Icons\\Achievement_Character_Dwarf_Male" },
}

local LEFT = { LEFT = true, A = true }
local RIGHT = { RIGHT = true, D = true }
local JUMPS = { SPACE = true, UP = true, W = true }
local VIEWS = {
	ground = 10, ledge = 12, block = 12, coin = 36, mushroom = 12,
	thorn = 12, checkpoint = 5, exit = 1, crawler = 10, spore = 10,
}
local ICONS = { block = CAPS, coin = COINS, mushroom = CAPS, thorn = SPIKES, checkpoint = BANNER, exit = BANNER, crawler = BOAR, spore = SPIDER }
local LANDSCAPES = {
	grove = { 7, 3, 5 }, quarry = { 1, 4, 3 }, cavern = { 2, 1, 5 },
	marsh = { 3, 7, 5 }, forge = { 6, 4, 2 }, ridge = { 2, 7, 5 },
}

local Game = {}
Game.__index = Game

local function Finite(value, min, max)
	return type(value) == "number" and value >= min and value <= max
end

local function Integer(value, min, max)
	return Finite(value, min, max) and value % 1 == 0
end

local function Overlap(a, b)
	return a.x < b.x + b.w and a.x + a.w > b.x and a.y < b.y + b.h and a.y + a.h > b.y
end

local function Clamp(value, low, high)
	return math.min(math.max(value, low), high)
end

local function Held(keys, group)
	for key in pairs(group) do if keys[key] then return true end end
	return false
end

local function Shape(player, big, x, feet)
	local shape = HEROES[big and "big" or "small"]
	player.x, player.y, player.w, player.h = x, feet - shape.h, shape.w, shape.h
	player.big = big
end

local function MakeHero(parent, role)
	local style = HEROES[role]
	if appearance and appearance.NewHero then
		local ok, actor = pcall(appearance.NewHero, parent, role, style.size)
		if ok and actor then return actor end
	end
	return B.Actor(parent, style.size, nil, style.icon)
end

local function New(host)
	local game = setmetatable({ host = host, views = {}, counts = {}, keys = {}, hills = {}, grove = {}, heldMouse = 0 }, Game)
	local area = host.area
	local viewport = CreateFrame("Frame", nil, area)
	viewport:SetAllPoints()
	viewport:SetClipsChildren(true)
	game.viewport = viewport
	game.sky = B.Sprite(viewport, WIDTH, HEIGHT, "BACKGROUND")
	B.Place(game.sky, 0, 0, viewport)
	for index = 1, 12 do game.hills[index] = B.Sprite(viewport, 1, 1, "BACKGROUND") end
	for index = 1, 8 do
		local cap = B.Sprite(viewport, 1, 1, "BACKGROUND")
		E:SetClientFile(cap, GROVE_ART[(index - 1) % #GROVE_ART + 1], CAPS)
		E:TrimIcon(cap)
		game.grove[index] = cap
	end
	game.hero = { small = MakeHero(viewport, "small"), big = MakeHero(viewport, "big") }
	for _, actor in pairs(game.hero) do actor:SetShown(false) end
	game.fx = B.Effects(viewport)

	local hud = CreateFrame("Frame", nil, area)
	hud:SetSize(WIDTH, 42)
	hud:SetPoint("TOP")
	hud:SetFrameLevel(viewport:GetFrameLevel() + 5)
	local shade = B.Sprite(hud, WIDTH, 42, "BACKGROUND")
	B.Place(shade, 0, 0, hud)
	B.Fill(shade, E.media.backdropColor, 0.88)
	game.stageText = B.Label(hud, E.tokens.size.body, "body", "LEFT")
	game.stageText:SetPoint("TOPLEFT", 10, -1)
	game.nameText = B.Label(hud, E.tokens.size.small, "secondary", "LEFT")
	game.nameText:SetPoint("BOTTOMLEFT", 10, 1)
	game.nameText:SetPoint("BOTTOMRIGHT", hud, "BOTTOM", -20, 1)
	game.nameText:SetWordWrap(false)
	game.coinsText = B.Label(hud, E.tokens.size.body, "body", "RIGHT")
	game.coinsText:SetPoint("TOPRIGHT", -10, -1)
	game.noticeText = B.Label(hud, E.tokens.size.small, "body", "RIGHT")
	game.noticeText:SetPoint("BOTTOMRIGHT", -10, 1)
	hud:EnableMouse(false)
	hud:Hide()
	game.hud = hud
	return game
end

function Game:Tell(text)
	self.notice, self.noticeTime = text, 1.65
end

function Game:Score(points)
	self.score = self.score + points
	self.host.Score(self.score)
	self.host.Sound("point")
end

function Game:Spawn(big, hurt)
	local mark = self.course.checkpoints[self.checkpoint] or self.course.start
	local player = { vx = 0, vy = 0, face = 1, grounded = true, hurt = hurt or 0, coyote = 0, buffer = 0 }
	Shape(player, big, mark.x, mark.y)
	self.player = player
	self.camera = Clamp(player.x - WIDTH * 0.33, 0, self.course.width - WIDTH)
end

function Game:SetLevel(number, big)
	self.level, self.course = number, levels[number]
	self.taken, self.used, self.defeated = {}, {}, {}
	self.caps = {}
	self.clock, self.checkpoint, self.notice, self.noticeTime = 0, 0, nil, 0
	self:Spawn(big, 0)
	self.fx:Clear()
end

function Game:Start()
	self:ReleaseKeys()
	self.lives, self.score, self.coins, self.ended = LIVES, 0, 0, false
	self:SetLevel(1, false)
	self.host.Score(self.score)
	self:Draw()
end

function Game:Loaded()
	wipe(self.keys)
	self.heldMouse = 0
	self:SetRunning(false)
	self.fx:Clear()
	self.notice, self.noticeTime, self.ended = nil, 0, false
	self.camera = Clamp(self.player.x - WIDTH * 0.33, 0, self.course.width - WIDTH)
	self:Draw()
end

local function CopyFlags(flags)
	local out = {}
	for index in pairs(flags) do out[index] = true end
	return out
end

function Game:Save()
	local player = self.player
	if not player or self.ended then return nil end
	return {
		level = self.level, lives = self.lives, score = self.score, coins = self.coins,
		checkpoint = self.checkpoint, clock = self.clock,
		taken = CopyFlags(self.taken), used = CopyFlags(self.used), defeated = CopyFlags(self.defeated), caps = CopyFlags(self.caps),
		player = { x = player.x, y = player.y, vx = player.vx, vy = player.vy,
			big = player.big, grounded = player.grounded, face = player.face, hurt = player.hurt },
	}
end

local function FlagSet(value, length)
	if type(value) ~= "table" then return nil end
	local out = {}
	for index, flag in pairs(value) do
		if not Integer(index, 1, length) or flag ~= true then return nil end
		out[index] = true
	end
	return out
end

function Game:Load(data)
	if type(data) ~= "table" or not Integer(data.level, 1, #levels) then return false end
	local course, state = levels[data.level], data.player
	if not Integer(data.lives, 1, LIVES) or not Integer(data.score, 0, 1000000)
		or not Integer(data.coins, 0, 10000) or not Integer(data.checkpoint, 0, #course.checkpoints)
		or not Finite(data.clock, 0, 18000) or type(state) ~= "table" or type(state.big) ~= "boolean" then return false end
	local shape = HEROES[state.big and "big" or "small"]
	if not Finite(state.x, 0, course.width - shape.w) or not Finite(state.y, 29, HEIGHT + 66)
		or not Finite(state.vx, -2 * SPEED, 2 * SPEED) or not Finite(state.vy, -JUMP, 710)
		or not Finite(state.hurt, 0, 2) or (state.face ~= 1 and state.face ~= -1)
		or type(state.grounded) ~= "boolean" then return false end
	local taken = FlagSet(data.taken, #course.coins)
	local used = FlagSet(data.used, #course.blocks)
	local defeated = FlagSet(data.defeated, #course.enemies)
	local caps = FlagSet(data.caps, #course.blocks)
	if not (taken and used and defeated and caps) then return false end
	for index in pairs(caps) do
		if not used[index] or course.blocks[index].kind ~= "mushroom" then return false end
	end
	local body = { x = state.x, y = state.y, w = shape.w, h = shape.h }
	for _, solid in ipairs(course.terrain) do if Overlap(body, solid) then return false end end
	for index, solid in ipairs(course.blocks) do
		if (solid.kind ~= "secret" or used[index]) and Overlap(body, solid) then return false end
	end
	self.level, self.course, self.lives, self.score, self.coins = data.level, course, data.lives, data.score, data.coins
	self.checkpoint, self.clock = data.checkpoint, data.clock
	self.taken, self.used, self.defeated, self.caps = taken, used, defeated, caps
	self.player = { x = body.x, y = body.y, w = body.w, h = body.h, vx = state.vx, vy = state.vy, hurt = state.hurt,
		big = state.big, face = state.face, grounded = state.grounded, coyote = 0, buffer = 0 }
	self:Loaded()
	return true
end

function Game:SetRunning(running)
	if self.running == running then return end
	self.running = running
	for _, actor in pairs(self.hero) do
		if actor.SetRunning then actor:SetRunning(running) end
	end
end

function Game:ReleaseKeys()
	wipe(self.keys)
	self.heldMouse = 0
	if self.player then self.player.vx, self.player.buffer = 0, 0 end
	self:SetRunning(false)
end

function Game:Stop()
	self:ReleaseKeys()
	for _, actor in pairs(self.hero) do actor:SetShown(false) end
	self.fx:Clear()
	self.hud:Hide()
	self.player = nil
end

function Game:Jump()
	local player = self.player
	if not player then return end
	player.buffer = 0.12
end

function Game:Key(key)
	if not (LEFT[key] or RIGHT[key] or JUMPS[key]) then return false end
	if self.keys[key] then return true end
	self.keys[key] = true
	if JUMPS[key] then self:Jump() end
	return true
end

function Game:KeyUp(key)
	self.keys[key] = nil
	if JUMPS[key] and self.player and self.player.vy < -230 and not Held(self.keys, JUMPS) then
		self.player.vy = -230
	end
end

function Game:Press(button)
	if button == "LeftButton" then
		self.heldMouse = 0.18
		self:Jump()
	end
end

function Game:TryGrow()
	local player = self.player
	if player.big then return true end
	local big = HEROES.big
	local feet = player.y + player.h
	local middle = player.x + player.w / 2
	local x = Clamp(middle - big.w / 2, 0, self.course.width - big.w)
	local larger = { x = x, y = feet - big.h, w = big.w, h = big.h }
	for _, solid in ipairs(self.course.terrain) do if Overlap(larger, solid) then return false end end
	for index, solid in ipairs(self.course.blocks) do
		if (solid.kind ~= "secret" or self.used[index]) and Overlap(larger, solid) then return false end
	end
	Shape(player, true, x, feet)
	return true
end

function Game:Bump(block, index)
	if self.used[index] then return end
	self.used[index] = true
	if block.kind == "coin" then
		self.coins = self.coins + 1
		self:Score(COIN)
	elseif block.kind == "secret" then
		self.coins = self.coins + 3
		self.lives = math.min(self.lives + 1, LIVES)
		self:Score(3 * COIN)
		self:Tell(L["Secret cache"])
	end
	self.fx:Sparks(block.x - self.camera + block.w / 2, block.y, self.host.Color("gold"), 6, 70)
end

function Game:Hurt(fall, from)
	local player = self.player
	if not fall and player.hurt > 0 then return end
	if not fall and player.big then
		local form = HEROES.small
		Shape(player, false, player.x + (player.w - form.w) / 2, player.y + player.h)
		player.hurt = 1.35
		player.vx = (from and player.x < from and -1 or 1) * 148
		player.vy, player.grounded, player.coyote = -260, false, 0
		self.host.Sound("over")
		return
	end
	self.lives = self.lives - 1
	if self.lives <= 0 then
		self.ended = true
		self:ReleaseKeys()
	else
		self:Spawn(false, 1.35)
		self:Tell(L["Try again"])
		self.host.Sound("over")
	end
end

-- Check the nearest crossed face along one axis. Fixed substeps and the
-- previous leading edge keep tall solid blocks from being tunneled through.
local function Sweep(game, distance, horizontal)
	local player = game.player
	if distance == 0 then return nil end
	local axis, length = horizontal and "x" or "y", horizontal and "w" or "h"
	local other, otherLength = horizontal and "y" or "x", horizontal and "h" or "w"
	local start = player[axis]
	local edge = distance > 0 and start + player[length] or start
	local nearest, hit = distance, nil
	local function Against(solid, index)
		if player[other] >= solid[other] + solid[otherLength] or player[other] + player[otherLength] <= solid[other] then return end
		local face = distance > 0 and solid[axis] or solid[axis] + solid[length]
		local step = face - edge
		if (distance > 0 and step >= -0.0001 and step <= nearest) or (distance < 0 and step <= 0.0001 and step >= nearest) then
			nearest, hit = step, index or false
		end
	end
	for _, solid in ipairs(game.course.terrain) do Against(solid) end
	for index, block in ipairs(game.course.blocks) do
		if block.kind ~= "secret" or game.used[index] or (not horizontal and distance < 0) then Against(block, index) end
	end
	player[axis] = start + nearest
	return hit
end

local function MushroomBall(block)
	return { x = block.x + (block.w - 22) / 2, y = block.y - 23, w = 22, h = 23 }
end

local function EnemyBox(enemy, clock, level)
	local span = enemy.right - enemy.left
	local speed = (enemy.kind == "spore" and 41 or 53) + (level - 1) * 4
	local travel = (enemy.x - enemy.left + clock * speed) % (2 * span)
	local x = enemy.left + (travel < span and travel or 2 * span - travel)
	local air = enemy.kind == "spore" and math.max(0, math.sin(clock * 3.3 + enemy.x / 64)) * 24 or 0
	return { x = x, y = enemy.y - air, w = enemy.w, h = enemy.h, kind = enemy.kind }
end

function Game:Contacts(oldFeet)
	local player, course = self.player, self.course
	for index, block in ipairs(course.blocks) do
		if block.kind == "mushroom" and self.used[index] and not self.caps[index]
			and Overlap(player, MushroomBall(block)) and self:TryGrow() then
			self.caps[index] = true
			self:Tell(L["Mushroom power"])
			self:Score(STOMP)
			self.fx:Sparks(block.x - self.camera + block.w / 2, block.y - 10, self.host.Color("good"), 8, 75)
		end
	end
	for index, coin in ipairs(course.coins) do
		if not self.taken[index] and Overlap(player, coin) then
			self.taken[index] = true
			self.coins = self.coins + 1
			self:Score(COIN)
			self.fx:Sparks(coin.x - self.camera + 7, coin.y + 7, self.host.Color("gold"), 4, 60)
		end
	end
	for index, mark in ipairs(course.checkpoints) do
		if index > self.checkpoint and player.x + player.w > mark.x and player.x < mark.x + 23
			and player.y < mark.y and player.y + player.h > mark.y - 46 then
			self.checkpoint = index
			self:Tell(L["Checkpoint reached"])
			self.host.Sound("point")
		end
	end
	for _, hazard in ipairs(course.hazards) do
		if Overlap(player, hazard) then
			self:Hurt(false, hazard.x + hazard.w / 2)
			if self.player ~= player or self.ended then return end
		end
	end
	for index, enemy in ipairs(course.enemies) do
		if not self.defeated[index] and player.x + player.w > enemy.left and player.x < enemy.right + enemy.w then
			local body = EnemyBox(enemy, self.clock, self.level)
			if Overlap(player, body) then
				if player.vy >= 0 and oldFeet <= body.y + 7 then
					self.defeated[index] = true
					player.vy, player.grounded = -315, false
					self:Score(STOMP)
					self.fx:Sparks(body.x - self.camera + 12, body.y + 6, self.host.Color("good"), 7, 70)
				else
					self:Hurt(false, body.x + body.w / 2)
					if self.player ~= player or self.ended then return end
				end
			end
		end
	end
	if not Overlap(player, course.exit) then return end
	self:Score(COURSE)
	if self.level == #levels then
		self.ended = true
		self:ReleaseKeys()
	else
		self:SetLevel(self.level + 1, player.big)
	end
end

function Game:Physics(dt)
	local player = self.player
	self.clock = (self.clock + dt) % 18000
	player.hurt = math.max(0, player.hurt - dt)
	self.heldMouse = math.max(0, self.heldMouse - dt)
	if player.grounded then player.coyote = 0.09 else player.coyote = math.max(0, player.coyote - dt) end
	player.buffer = math.max(0, player.buffer - dt)
	local direction = (Held(self.keys, RIGHT) and 1 or 0) - (Held(self.keys, LEFT) and 1 or 0)
	if direction ~= 0 then player.face = direction end
	local target = direction * SPEED
	local change = (direction == 0 and 2200 or 1700) * dt
	player.vx = player.vx + Clamp(target - player.vx, -change, change)
	if player.buffer > 0 and player.coyote > 0 then
		player.vy, player.grounded, player.coyote, player.buffer = -JUMP, false, 0, 0
		self.host.Sound("turn")
	end
	local side = Sweep(self, player.vx * dt, true)
	if side ~= nil then player.vx = 0 end
	player.x = Clamp(player.x, 0, self.course.width - player.w)
	local oldFeet = player.y + player.h
	local held = self.heldMouse > 0 or Held(self.keys, JUMPS)
	local gravity = player.vy < -210 and not held and 1.7 * GRAVITY or GRAVITY
	player.vy = math.min(player.vy + gravity * dt, 710)
	local face = Sweep(self, player.vy * dt, false)
	player.grounded = face ~= nil and player.vy >= 0
	if face ~= nil then
		if face and player.vy < 0 then self:Bump(self.course.blocks[face], face) end
		player.vy = 0
	end
	if player.y < 42 then
		player.y = 42
		player.vy = math.max(0, player.vy)
	end
	if player.y >= HEIGHT + 66 then
		self:Hurt(true)
		return
	end
	self.camera = Clamp(player.x - WIDTH * 0.33, 0, self.course.width - WIDTH)
	self:Contacts(oldFeet)
end

function Game:Update(dt)
	if not self.player or self.ended or not Finite(dt, 0, 3600) then return end
	local total = math.min(dt, MAX_FRAME)
	if total == 0 then return end
	self:SetRunning(true)
	if self.noticeTime > 0 then self.noticeTime = math.max(0, self.noticeTime - total) end
	local steps = math.ceil(total / MAX_STEP)
	for _ = 1, steps do
		self:Physics(total / steps)
		if self.ended then break end
	end
	self.fx:Update(total)
	self:Draw()
	if self.ended then self.host.Over(self.lives > 0) end
end

local function NewSprite(game, kind)
	local view = { body = B.Sprite(game.viewport, 1, 1, "BORDER") }
	local icon = ICONS[kind]
	if icon then
		view.icon = B.Sprite(game.viewport, 1, 1, "ARTWORK")
		E:SetClientFile(view.icon, icon, CAPS)
		E:TrimIcon(view.icon)
	end
	return view
end

-- Only objects intersecting the camera have actual regions. Pools cap
-- allocations even when a long course is loaded at its farthest edge.
function Game:View(kind, object, color, alpha, showIcon)
	local x, y = object.x - self.camera, object.y
	if x >= WIDTH or x + object.w <= 0 or y >= HEIGHT or y + object.h <= 42 then return end
	local index = (self.counts[kind] or 0) + 1
	if index > VIEWS[kind] then return end
	self.counts[kind] = index
	local list = self.views[kind]
	if not list then
		list = {}
		self.views[kind] = list
	end
	local view = list[index]
	if not view then
		view = NewSprite(self, kind)
		list[index] = view
	end
	view.body:SetSize(object.w, object.h)
	B.Place(view.body, x, y, self.viewport)
	if kind == "block" or kind == "ground" or kind == "ledge" then
		B.Tile(view.body, color, alpha)
	else
		B.Fill(view.body, color, alpha)
	end
	view.body:Show()
	if view.icon then
		local size = math.max(1, math.min(object.w - 2, object.h - 2))
		view.icon:SetSize(size, size)
		B.Place(view.icon, x + (object.w - size) / 2, y + (object.h - size) / 2, self.viewport)
		view.icon:SetShown(showIcon)
	end
end

function Game:DrawWorld(palette)
	local world = LANDSCAPES[self.course.landscape]
	B.Fill(self.sky, palette[world[1]], 0.2)
	for index, hill in ipairs(self.hills) do
		local back = index <= 6
		local column = (index - 1) % 6
		local width = back and 125 or 93
		local height = 65 + (column * 47 + (back and 20 or 70)) % 99
		local x = (column * 151 + (back and 0 or 85) - self.camera * (back and 0.15 or 0.29)) % 906 - width
		hill:SetSize(width, height)
		B.Place(hill, x, 304 - height + (back and 10 or 28), self.viewport)
		B.Fill(hill, palette[world[back and 1 or 2]], back and 0.23 or 0.36)
	end
	for index, texture in ipairs(self.grove) do
		local size = 30 + index * 17 % 35
		local x = (index * 102 - self.camera * 0.54) % 816 - size
		texture:SetSize(size, size)
		texture:SetVertexColor(1, 1, 1, self.course.landscape == "grove" and 0.34 or 0.20)
		B.Place(texture, x, 305 - size - index * 23 % 61, self.viewport)
	end
	for _, solid in ipairs(self.course.terrain) do
		local color = palette[world[solid.kind == "ground" and 2 or 3]]
		self:View(solid.kind, solid, color, solid.kind == "ground" and 0.74 or 0.92)
	end
	for index, block in ipairs(self.course.blocks) do
		local used = self.used[index]
		if used or block.kind ~= "secret" then
			self:View("block", block, used and self.host.Color("dim") or self.host.Color("gold"), used and 0.68 or 0.95, not used and block.kind == "mushroom")
		end
		if used and block.kind == "mushroom" and not self.caps[index] then
			self:View("mushroom", MushroomBall(block), self.host.Color("good"), 0.7, true)
		end
	end
	for index, coin in ipairs(self.course.coins) do
		if not self.taken[index] then self:View("coin", coin, self.host.Color("gold"), 0.8, true) end
	end
	for _, hazard in ipairs(self.course.hazards) do self:View("thorn", hazard, self.host.Color("bad"), 0.88, true) end
	for index, mark in ipairs(self.course.checkpoints) do
		local active = self.checkpoint == index
		self:View("checkpoint", { x = mark.x, y = mark.y - 48, w = 22, h = 48 },
			self.host.Color(active and "good" or "secondary"), active and 0.95 or 0.52, true)
	end
	self:View("exit", self.course.exit, self.host.Color("good"), 0.8, true)
	for index, enemy in ipairs(self.course.enemies) do
		if not self.defeated[index] and enemy.left < self.camera + WIDTH and enemy.right + enemy.w > self.camera then
			self:View(enemy.kind, EnemyBox(enemy, self.clock, self.level), palette[6], 0.68, true)
		end
	end
end

function Game:Draw()
	if not self.player then return end
	local player, role = self.player, self.player.big and "big" or "small"
	wipe(self.counts)
	self:DrawWorld(self.host.Palette())
	for kind, list in pairs(self.views) do
		for index = (self.counts[kind] or 0) + 1, #list do
			local view = list[index]
			view.body:Hide()
			if view.icon then view.icon:Hide() end
		end
	end
	for name, actor in pairs(self.hero) do
		actor:SetShown(name == role)
		if name == role then
			local size = HEROES[role].size
			actor:Place(player.x - self.camera + (player.w - size) / 2, player.y + player.h - size)
			actor:Face(player.face * -math.pi / 2)
			local animation = player.grounded and (math.abs(player.vx) > 20 and B.ANIM.run or B.ANIM.stand)
			actor:Animate(animation or (appearance and appearance.jumpAnimation) or B.ANIM.stand)
			actor:SetAlpha(player.hurt > 0 and math.floor(player.hurt * 12) % 2 == 0 and 0.53 or 1)
		end
	end
	self.stageText:SetText(L["Course %d"]:format(self.level))
	self.nameText:SetText(L[self.course.title])
	self.coinsText:SetText(L["Lives %d  ·  Coins %d"]:format(self.lives, self.coins))
	self.noticeText:SetText(self.noticeTime > 0 and self.notice or "")
	self.hud:Show()
end

function Game:Summary()
	if not self.level then return nil end
	return L["Course %d"]:format(self.level) .. " · " .. L["Lives %d  ·  Coins %d"]:format(self.lives, self.coins)
end

M:RegisterGame({
	key = "mushroom", order = 48, group = "arcade", wins = true, saveVersion = 1,
	title = "Gnome Dash", desc = "Cross ten courses, collect coins and grow from a gnome into a dwarf with a mushroom.",
	controls = E.Key("Left / Right or A / D: move. Space, Up, W or click: jump. P: pause."),
	icon = CAPS, width = WIDTH, height = HEIGHT,
	New = New,
})
