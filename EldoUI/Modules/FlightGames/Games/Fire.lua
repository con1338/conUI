-- EldoUI Flight Games: Don't Stand in the Fire. The floor of the arena
-- keeps catching fire: a ring marks where the flames will come, and a line
-- across the floor marks a beam about to sweep it. Step out in time,
-- pick up the gold, grab a healing orb when you are hurt, and last as long
-- as you can.
-- Written from scratch for EldoUI; you are your own character.
local _, E = ...
local M = E.FlightGames
local Key = E.Key
local L = E.L
local B = M.Board

local WIDTH, HEIGHT = 470, 400
local BAR_H = 22
local TOP = BAR_H + 10
local SIZE = 30
local SPEED = 175
local WARN = 1.1             -- a fire ring or a beam line shows this long first
local BURN = 35              -- health a second in the flames
local BEAM_HIT = 35
local GOLD, HEAL = "Interface\\Icons\\INV_Misc_Coin_02", "Interface\\Icons\\Spell_Holy_FlashHeal"
local MOVE = { UP = { 0, -1 }, W = { 0, -1 }, DOWN = { 0, 1 }, S = { 0, 1 }, LEFT = { -1, 0 }, A = { -1, 0 }, RIGHT = { 1, 0 }, D = { 1, 0 } }

local Fire = {}
Fire.__index = Fire
-- What a saved game keeps (the board, the score and the timers).
Fire.saveKeys = { "px", "py", "tx", "ty", "hp", "time", "hazards", "items", "score", "next", "nextItem", "gold" }

local function New(host)
	local game = setmetatable({ host = host, held = {}, pools = {}, beams = {}, itemViews = {} }, Fire)
	local area = host.area
	game.floor = B.Sprite(area, WIDTH, HEIGHT - TOP, "BACKGROUND")
	B.Place(game.floor, 0, TOP, area)
	game.barBack = B.Slab(area, WIDTH - 16, BAR_H - 6, "BORDER")
	game.barBack:Place(8, 4)
	game.bar = B.Sprite(area, WIDTH - 20, BAR_H - 10, "ARTWORK")
	B.Place(game.bar, 10, 6, area)
	game.barText = B.Label(area, E.tokens.size.small, "body")
	game.barText:SetPoint("CENTER", area, "TOPLEFT", WIDTH / 2, -(4 + (BAR_H - 6) / 2))
	game.hero = B.Actor(area, SIZE, "player", "Interface\\Icons\\Ability_Rogue_Sprint", { scale = 2.4, animation = B.ANIM.stand })
	game.marker = B.Sprite(area, SIZE + 12, SIZE + 12, "BORDER")
	game.fx = B.Effects(area)
	return game
end

function Fire:Start()
	self.held = {}
	self.px, self.py = WIDTH / 2, TOP + (HEIGHT - TOP) / 2
	self.tx, self.ty = nil, nil
	self.hp, self.time, self.score, self.gold = 100, 0, 0, 0
	self.hazards, self.items = {}, {}
	self.next, self.nextItem = 1.0, 3
	self.host.Score(0)
	self:Draw()
end

function Fire:Key(key)
	if MOVE[key] then
		self.held[key] = true
		self.tx, self.ty = nil, nil
		return true
	end
	return false
end

function Fire:KeyUp(key)
	self.held[key] = nil
end

-- A click: walk there.
function Fire:Press(button, x, y)
	if (button == "LeftButton" or button == "RightButton") and x and y then
		self.tx, self.ty = x, math.max(TOP + SIZE / 2, y)
	end
end

function Fire:Spawn()
	local elapsed = self.time
	local r = self.host.Random
	if elapsed > 12 and r(100) <= 30 then
		local vertical = r(2) == 1
		local span = vertical and WIDTH or (HEIGHT - TOP)
		local width = 46 + r(30)
		self.hazards[#self.hazards + 1] = { kind = "beam", vertical = vertical, at = r(math.floor(span - width)), w = width, warn = WARN, life = 0.35 }
	else
		local radius = 26 + r(24) + math.min(30, elapsed * 0.4)
		-- Now and then the fire comes right under you.
		local x, y
		if r(100) <= (elapsed < 15 and 15 or 35) then
			x, y = self.px, self.py
		else
			x, y = radius + r(math.floor(WIDTH - radius * 2)), TOP + radius + r(math.floor(HEIGHT - TOP - radius * 2))
		end
		self.hazards[#self.hazards + 1] = { kind = "pool", x = x, y = y, r = radius, warn = WARN, life = 3 + r(30) / 10 }
	end
end

function Fire:Update(dt)
	self.fx:Update(dt)
	local pace = self.host.Pace()
	self.time = self.time + dt
	-- Walking.
	local mx, my = 0, 0
	for key in pairs(self.held) do mx, my = mx + MOVE[key][1], my + MOVE[key][2] end
	if (mx ~= 0 or my ~= 0) then
		local len = math.sqrt(mx * mx + my * my)
		mx, my = mx / len, my / len
	elseif self.tx then
		local dx, dy = self.tx - self.px, self.ty - self.py
		local dist = math.sqrt(dx * dx + dy * dy)
		if dist < 3 then
			self.tx, self.ty = nil, nil
		else
			mx, my = dx / dist, dy / dist
		end
	end
	self.moving = mx ~= 0 or my ~= 0
	self.px = math.max(SIZE / 2, math.min(WIDTH - SIZE / 2, self.px + mx * SPEED * dt))
	self.py = math.max(TOP + SIZE / 2, math.min(HEIGHT - SIZE / 2, self.py + my * SPEED * dt))
	if self.moving then self.hero:Face(math.atan2(-mx, -my)) end
	-- New fire, faster as time goes on.
	self.next = self.next - dt * pace
	if self.next <= 0 then
		self.next = math.max(0.35, 1.5 - self.time * 0.018)
		self:Spawn()
	end
	self.nextItem = self.nextItem - dt
	if self.nextItem <= 0 then
		self.nextItem = 2.5 + self.host.Random(20) / 10
		local heal = self.hp < 70 and self.host.Random(100) <= 40
		self.items[#self.items + 1] = { kind = heal and "heal" or "gold", x = 24 + self.host.Random(WIDTH - 48),
			y = TOP + 24 + self.host.Random(HEIGHT - TOP - 48), life = 6 }
	end
	-- The flames.
	local keep = {}
	local burning = false
	for _, h in ipairs(self.hazards) do
		if h.warn > 0 then
			h.warn = h.warn - dt * pace
			if h.warn <= 0 and h.kind == "beam" then
				self.host.Sound("over")
				if self:InBeam(h) then
					self.hp = self.hp - BEAM_HIT
					self.fx:Burst(self.px, self.py, self.host.Color("bad"), 70)
				end
			end
			keep[#keep + 1] = h
		else
			h.life = h.life - dt
			if h.kind == "pool" then
				local dx, dy = self.px - h.x, self.py - h.y
				if dx * dx + dy * dy < (h.r + SIZE * 0.25) ^ 2 then burning = true end
			end
			if h.life > 0 then keep[#keep + 1] = h end
		end
	end
	self.hazards = keep
	if burning then
		self.hp = self.hp - BURN * dt
		self.burnFx = (self.burnFx or 0) - dt
		if self.burnFx <= 0 then
			self.burnFx = 0.15
			self.fx:Sparks(self.px, self.py + SIZE / 2, self.host.Palette()[6], 3, 80)
		end
	end
	-- Pick-ups.
	keep = {}
	for _, item in ipairs(self.items) do
		item.life = item.life - dt
		local dx, dy = self.px - item.x, self.py - item.y
		if dx * dx + dy * dy < (SIZE * 0.8) ^ 2 then
			if item.kind == "gold" then
				self.gold = self.gold + 1
				self.fx:Float(item.x, item.y, "+50", self.host.Color("gold"))
				self.fx:Sparks(item.x, item.y, self.host.Color("gold"), 8)
			else
				self.hp = math.min(100, self.hp + 30)
				self.fx:Float(item.x, item.y, "+30", self.host.Color("good"))
				self.fx:Burst(item.x, item.y, self.host.Color("good"), 60)
			end
			self.host.Sound("point")
		elseif item.life > 0 then
			keep[#keep + 1] = item
		end
	end
	self.items = keep
	local score = math.floor(self.time * 10) + self.gold * 50
	if score ~= self.score then
		self.score = score
		self.host.Score(score)
	end
	if self.hp <= 0 then
		self.hp = 0
		self:Draw()
		self.host.Over(false)
		return
	end
	self:Draw()
end

function Fire:InBeam(h)
	if h.vertical then
		return self.px > h.at - SIZE * 0.3 and self.px < h.at + h.w + SIZE * 0.3
	end
	local y = self.py - TOP
	return y > h.at - SIZE * 0.3 and y < h.at + h.w + SIZE * 0.3
end

function Fire:Summary()
	if not self.time then return nil end
	return L["Lasted %s"]:format(E:FormatDuration(math.floor(self.time), "clock"))
end

local function Take(list, i, make)
	local view = list[i]
	if not view then
		view = make()
		list[i] = view
	end
	return view
end

function Fire:Draw()
	local area, color, palette = self.host.area, self.host.Color, self.host.Palette()
	local fire, warn = palette[6], color("warn")
	B.Fill(self.floor, E.tokens.palette.bronze, 0.12)
	local t = GetTime and GetTime() or 0
	local pools, beams = 0, 0
	for _, h in ipairs(self.hazards) do
		if h.kind == "pool" then
			pools = pools + 1
			local view = Take(self.pools, pools, function()
				return { fill = B.Dot(area, 10, nil, "BORDER"), ring = B.Sprite(area, 10, 10, "ARTWORK") }
			end)
			local d = h.r * 2
			view.fill:SetSize(d, d)
			view.ring:SetSize(d + 6, d + 6)
			B.Place(view.fill, h.x - h.r, h.y - h.r, area)
			B.Place(view.ring, h.x - h.r - 3, h.y - h.r - 3, area)
			if h.warn > 0 then
				local f = 1 - h.warn / WARN
				view.fill:SetVertexColor(warn[1], warn[2], warn[3], 0.12 + f * 0.15)
				B.Art(view.ring, "Ring", warn, 0.5 + 0.5 * math.abs(math.sin(t * 10)))
			else
				local flicker = 0.75 + 0.2 * math.sin(t * 13 + h.x)
				view.fill:SetVertexColor(fire[1], fire[2], fire[3], flicker * math.min(1, h.life))
				B.Art(view.ring, "Ring", color("warn"), 0.8 * math.min(1, h.life))
			end
			view.fill:Show()
			view.ring:Show()
		else
			beams = beams + 1
			local view = Take(self.beams, beams, function() return B.Sprite(area, 10, 10, "BORDER") end)
			if h.vertical then
				view:SetSize(h.w, HEIGHT - TOP)
				B.Place(view, h.at, TOP, area)
			else
				view:SetSize(WIDTH, h.w)
				B.Place(view, 0, TOP + h.at, area)
			end
			if h.warn > 0 then
				B.Fill(view, warn, 0.12 + 0.12 * math.abs(math.sin(t * 9)))
			else
				B.Fill(view, palette[5], 0.7 * h.life / 0.35)
			end
			view:Show()
		end
	end
	for i = pools + 1, #self.pools do
		self.pools[i].fill:Hide()
		self.pools[i].ring:Hide()
	end
	for i = beams + 1, #self.beams do self.beams[i]:Hide() end
	for i, item in ipairs(self.items) do
		local view = Take(self.itemViews, i, function()
			local icon = B.Sprite(area, 22, 22, "ARTWORK")
			return { icon = icon, ring = B.Sprite(area, 30, 30, "ARTWORK") }
		end)
		if view.kind ~= item.kind then
			view.kind = item.kind
			E:SetClientFile(view.icon, item.kind == "gold" and GOLD or HEAL, "Interface\\Icons\\INV_Misc_QuestionMark")
			E:TrimIcon(view.icon)
		end
		local bob = math.sin(t * 4 + i) * 2
		B.Place(view.icon, item.x - 11, item.y - 11 + bob, area)
		B.Art(view.ring, "Ring", item.kind == "gold" and color("gold") or color("good"), item.life < 1.5 and 0.4 or 0.8)
		B.Place(view.ring, item.x - 15, item.y - 15 + bob, area)
		view.icon:Show()
		view.ring:Show()
	end
	for i = #self.items + 1, #self.itemViews do
		self.itemViews[i].icon:Hide()
		self.itemViews[i].ring:Hide()
	end
	self.hero:Place(self.px - SIZE / 2, self.py - SIZE / 2)
	self.hero:Animate(self.moving and B.ANIM.run or B.ANIM.stand)
	B.Art(self.marker, "Ring", color("accent"), 0.5)
	B.Place(self.marker, self.px - SIZE / 2 - 6, self.py - SIZE / 2 - 6, area)
	self.barBack:Paint(color("dim"), 0.5)
	local share = math.max(0, self.hp / 100)
	self.bar:SetWidth(math.max(1, (WIDTH - 20) * share))
	B.Tile(self.bar, share > 0.5 and color("good") or share > 0.25 and color("warn") or color("bad"), 0.9)
	self.barText:SetText(L["Health %d"]:format(math.ceil(self.hp)))
end

M:RegisterGame({
	key = "fire", order = 29, group = "arcade",
	title = "Don't Stand in the Fire", desc = "Step out of the flames and the beams, and last as long as you can.",
	controls = Key("Arrow keys, WASD or a click: move. P: pause."),
	icon = "Interface\\Icons\\Spell_Fire_Immolation",
	width = WIDTH, height = HEIGHT,
	New = New,
})
