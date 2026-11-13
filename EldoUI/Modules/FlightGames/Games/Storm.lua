-- EldoUI Flight Games: Elemental Storm. Elementals drift across the sky.
-- Turn and fly your little ship and break them with bolts: a large one
-- breaks into two smaller ones, and the smallest are gone. Keep clear of
-- them; a touch costs one of three lives. A wave is over when every piece
-- is gone, and the next one brings more.
-- Written from scratch for EldoUI; the elementals wear the game's own
-- spell icons.
local _, E = ...
local M = E.FlightGames
local Key = E.Key
local L = E.L
local B = M.Board

local WIDTH, HEIGHT = 480, 360
local SHIP = 22                 -- the ship's size
local TURN = 4.2                -- radians a second
local THRUST, DRAG, MAX_SPEED = 260, 0.6, 300
local BOLT_SPEED, BOLT_LIFE, BOLT_MAX, COOL = 420, 0.9, 6, 0.18
local RADIUS = { 27, 17, 10 }   -- by size: large, middle, small
local SPEED = { 45, 75, 110 }
local POINTS = { 20, 50, 100 }
local LIVES, SAFE = 3, 2.2
local SHIP_ART = "Interface\\AddOns\\EldoUI\\Media\\Textures\\EldoPlay.tga"
local MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
-- The four kinds, each with its icon and its palette color.
local KINDS = {
	{ icon = "Interface\\Icons\\Spell_Fire_FireBolt02", color = 2 },
	{ icon = "Interface\\Icons\\Spell_Frost_FrostBolt02", color = 1 },
	{ icon = "Interface\\Icons\\Spell_Nature_Lightning", color = 5 },
	{ icon = "Interface\\Icons\\Spell_Nature_EarthShock", color = 4 },
}

local Storm = {}
Storm.__index = Storm
-- What a saved storm keeps.
Storm.saveKeys = { "ship", "rocks", "bolts", "lives", "wave", "score", "safe", "cool" }

local function New(host)
	local game = setmetatable({ host = host, rockViews = {}, boltViews = {} }, Storm)
	local area = host.area
	game.stars = {}
	for i = 1, 40 do
		local star = B.Dot(area, (i % 3) + 1, nil, "BACKGROUND")
		B.Place(star, host.Random(0, WIDTH - 3), host.Random(0, HEIGHT - 3), area)
		game.stars[i] = star
	end
	game.flame = B.Dot(area, 10, nil, "ARTWORK")
	game.shipArt = B.Sprite(area, SHIP, SHIP, "OVERLAY")
	game.shipArt:SetTexture(SHIP_ART)
	game.ring = B.Sprite(area, SHIP + 16, SHIP + 16, "OVERLAY")
	game.tally = B.Label(area, E.tokens.size.cardTitle, "body", "LEFT")
	game.tally:SetPoint("TOPLEFT", area, "TOPLEFT", 8, -8)
	game.fx = B.Effects(area)
	game.keys = {}
	return game
end

local function Wrap(v, size)
	if v < 0 then return v + size end
	if v >= size then return v - size end
	return v
end

-- A new elemental of a size, away from the ship.
-- True when the path from (x, y) moving (mx, my) comes within r of (cx, cy).
function Storm.Crosses(x, y, mx, my, cx, cy, r)
	local length = mx * mx + my * my
	local t = 0
	if length > 0 then t = math.max(0, math.min(1, ((cx - x) * mx + (cy - y) * my) / length)) end
	local dx, dy = x + mx * t - cx, y + my * t - cy
	return dx * dx + dy * dy <= r * r
end

function Storm:Rock(size, x, y)
	local angle = self.host.Random(0, 628) / 100
	local speed = SPEED[size] * (0.8 + self.host.Random(0, 40) / 100)
	local rock = { x = x, y = y, vx = math.cos(angle) * speed, vy = math.sin(angle) * speed,
		size = size, kind = self.host.Random(1, #KINDS) }
	self.rocks[#self.rocks + 1] = rock
	return rock
end

function Storm:Wave()
	self.wave = (self.wave or 0) + 1
	local count = math.min(2 + self.wave, 8)
	for i = 1, count do
		-- On the edges, never on the ship.
		local x, y
		if i % 2 == 0 then
			x, y = self.host.Random(0, WIDTH), self.host.Random(0, 1) * (HEIGHT - 1)
		else
			x, y = self.host.Random(0, 1) * (WIDTH - 1), self.host.Random(0, HEIGHT)
		end
		self:Rock(1, x, y)
	end
	self.safe = SAFE
	self.fx:Float(WIDTH / 2, HEIGHT / 2 - 40, L["Wave %d"]:format(self.wave), self.host.Color("gold"), E.tokens.size.display)
end

function Storm:Start()
	self.ship = { x = WIDTH / 2, y = HEIGHT / 2, a = -math.pi / 2, vx = 0, vy = 0 }
	self.rocks, self.bolts = {}, {}
	self.lives, self.score, self.wave, self.cool = LIVES, 0, 0, 0
	self.keys = {}
	self.fx:Clear()
	self:Wave()
	self.host.Score(0)
	self:Draw()
end

function Storm:Loaded()
	self.keys = {}
end

function Storm:Fire()
	if (self.cool or 0) > 0 or #self.bolts >= BOLT_MAX then return end
	local ship = self.ship
	local cx, cy = math.cos(ship.a), math.sin(ship.a)
	self.bolts[#self.bolts + 1] = { x = ship.x + cx * SHIP / 2, y = ship.y + cy * SHIP / 2,
		vx = cx * BOLT_SPEED + ship.vx, vy = cy * BOLT_SPEED + ship.vy, life = BOLT_LIFE }
	self.cool = COOL
	self.host.Sound("turn")
end

local TURN_LEFT = { LEFT = true, A = true }
local TURN_RIGHT = { RIGHT = true, D = true }
local THRUSTS = { UP = true, W = true }

function Storm:Key(key)
	if TURN_LEFT[key] or TURN_RIGHT[key] or THRUSTS[key] then
		self.keys[key] = true
		return true
	elseif key == "SPACE" then
		self:Fire()
		return true
	end
	return false
end

function Storm:KeyUp(key)
	self.keys[key] = nil
end

-- A click turns the ship toward the point and fires.
function Storm:Press(button, x, y)
	if button ~= "LeftButton" or not (x and y) then return end
	self.ship.a = math.atan2(y - self.ship.y, x - self.ship.x)
	self:Fire()
end

local function Held(keys, set)
	for name in pairs(set) do
		if keys[name] then return true end
	end
	return false
end

-- Breaks an elemental: two smaller ones, or gone.
function Storm:Break(index)
	local rock = table.remove(self.rocks, index)
	local color = self.host.Palette()[KINDS[rock.kind].color]
	self.score = self.score + POINTS[rock.size]
	self.host.Score(self.score)
	self.fx:Sparks(rock.x, rock.y, color, 6 + (3 - rock.size) * 2, 110)
	self.fx:Burst(rock.x, rock.y, color, RADIUS[rock.size] * 2.6, 0.35)
	self.host.Sound("point")
	if rock.size < 3 then
		for _ = 1, 2 do
			local piece = self:Rock(rock.size + 1, rock.x, rock.y)
			piece.kind = rock.kind
		end
	end
end
Storm.RADIUS = RADIUS

function Storm:Update(dt)
	self.fx:Update(dt)
	local pace = self.host.Pace()
	dt = dt * pace
	local ship, keys = self.ship, self.keys
	if Held(keys, TURN_LEFT) then ship.a = ship.a - TURN * dt end
	if Held(keys, TURN_RIGHT) then ship.a = ship.a + TURN * dt end
	self.thrusting = Held(keys, THRUSTS)
	if self.thrusting then
		ship.vx = ship.vx + math.cos(ship.a) * THRUST * dt
		ship.vy = ship.vy + math.sin(ship.a) * THRUST * dt
	end
	local speed = math.sqrt(ship.vx * ship.vx + ship.vy * ship.vy)
	if speed > MAX_SPEED then ship.vx, ship.vy = ship.vx / speed * MAX_SPEED, ship.vy / speed * MAX_SPEED end
	ship.vx, ship.vy = ship.vx * (1 - DRAG * dt), ship.vy * (1 - DRAG * dt)
	ship.x, ship.y = Wrap(ship.x + ship.vx * dt, WIDTH), Wrap(ship.y + ship.vy * dt, HEIGHT)
	self.cool = math.max(0, (self.cool or 0) - dt)
	self.safe = math.max(0, (self.safe or 0) - dt)
	for _, rock in ipairs(self.rocks) do
		rock.x, rock.y = Wrap(rock.x + rock.vx * dt, WIDTH), Wrap(rock.y + rock.vy * dt, HEIGHT)
	end
	-- Bolts: each breaks the first elemental it touches.
	local keep = {}
	for _, bolt in ipairs(self.bolts) do
		-- The whole path of this frame counts, so a fast bolt never skips
		-- over a small elemental.
		local sx, sy = bolt.x, bolt.y
		local mx, my = bolt.vx * dt, bolt.vy * dt
		bolt.x, bolt.y = Wrap(sx + mx, WIDTH), Wrap(sy + my, HEIGHT)
		bolt.life = bolt.life - dt
		local hit = false
		for index, rock in ipairs(self.rocks) do
			if Storm.Crosses(sx, sy, mx, my, rock.x, rock.y, RADIUS[rock.size]) then
				self:Break(index)
				hit = true
				break
			end
		end
		if not hit and bolt.life > 0 then keep[#keep + 1] = bolt end
	end
	self.bolts = keep
	-- The ship against the elementals.
	if self.safe <= 0 then
		for _, rock in ipairs(self.rocks) do
			local dx, dy = ship.x - rock.x, ship.y - rock.y
			local reach = RADIUS[rock.size] + SHIP * 0.35
			if dx * dx + dy * dy <= reach * reach then
				self.lives = self.lives - 1
				self.fx:Burst(ship.x, ship.y, self.host.Palette()[6], 80, 0.5)
				self.fx:Sparks(ship.x, ship.y, self.host.Palette()[6], 12, 140)
				self.host.Sound("over")
				if self.lives <= 0 then
					self:Draw()
					self.host.Over(false)
					return
				end
				ship.x, ship.y, ship.vx, ship.vy = WIDTH / 2, HEIGHT / 2, 0, 0
				self.safe = SAFE
				break
			end
		end
	end
	if #self.rocks == 0 then self:Wave() end
	self:Draw()
end

function Storm:Draw()
	local area = self.host.area
	local palette, color = self.host.Palette(), self.host.Color
	local paper = color("body")
	for i, star in ipairs(self.stars) do star:SetVertexColor(paper[1], paper[2], paper[3], 0.15 + (i % 4) * 0.08) end
	for i, rock in ipairs(self.rocks or {}) do
		local view = self.rockViews[i]
		if not view then
			view = { icon = B.Sprite(area, 10, 10, "ARTWORK"), ring = B.Sprite(area, 10, 10, "OVERLAY") }
			if view.icon.SetMask then pcall(view.icon.SetMask, view.icon, MASK) end
			self.rockViews[i] = view
		end
		local r = RADIUS[rock.size]
		local kind = KINDS[rock.kind] or KINDS[1]
		if view.kind ~= rock.kind then
			view.kind = rock.kind
			E:SetClientFile(view.icon, kind.icon, "Interface\\Icons\\INV_Misc_QuestionMark")
			E:TrimIcon(view.icon)
		end
		view.icon:SetSize(r * 2, r * 2)
		B.Place(view.icon, rock.x - r, rock.y - r, area)
		view.ring:SetSize(r * 2 + 8, r * 2 + 8)
		B.Place(view.ring, rock.x - r - 4, rock.y - r - 4, area)
		B.Art(view.ring, "Ring", palette[kind.color], 0.9)
		view.icon:Show()
		view.ring:Show()
	end
	for i = #(self.rocks or {}) + 1, #self.rockViews do
		self.rockViews[i].icon:Hide()
		self.rockViews[i].ring:Hide()
	end
	for i, bolt in ipairs(self.bolts or {}) do
		local dot = self.boltViews[i]
		if not dot then
			dot = B.Dot(area, 6, nil, "OVERLAY")
			self.boltViews[i] = dot
		end
		local gold = color("gold")
		dot:SetVertexColor(gold[1], gold[2], gold[3], 1)
		B.Place(dot, bolt.x - 3, bolt.y - 3, area)
		dot:Show()
	end
	for i = #(self.bolts or {}) + 1, #self.boltViews do self.boltViews[i]:Hide() end
	local ship = self.ship
	if not ship then return end
	local blink = (self.safe or 0) > 0 and math.floor((self.safe or 0) * 8) % 2 == 0
	local own = palette[7]
	local art = self.shipArt
	art:SetVertexColor(own[1], own[2], own[3], blink and 0.35 or 1)
	if art.SetRotation then art:SetRotation(-ship.a) end
	B.Place(art, ship.x - SHIP / 2, ship.y - SHIP / 2, area)
	B.Art(self.ring, "Ring", own, (self.safe or 0) > 0 and 0.7 or 0.25)
	B.Place(self.ring, ship.x - SHIP / 2 - 8, ship.y - SHIP / 2 - 8, area)
	self.flame:SetShown(self.thrusting and true or false)
	if self.thrusting then
		local fire = palette[2]
		self.flame:SetVertexColor(fire[1], fire[2], fire[3], 0.9)
		B.Place(self.flame, ship.x - math.cos(ship.a) * SHIP * 0.7 - 5, ship.y - math.sin(ship.a) * SHIP * 0.7 - 5, area)
	end
	self.tally:SetText(L["Wave %d, lives %d"]:format(self.wave or 1, self.lives or 0))
end

function Storm:Summary()
	if not self.wave then return nil end
	return L["Wave %d reached"]:format(self.wave)
end

M:RegisterGame({
	key = "storm", order = 42, group = "arcade",
	title = "Elemental Storm", desc = "Fly a little ship and break the drifting elementals into pieces.",
	controls = Key("Left and Right: turn. Up: fly. Space or a click: fire. P: pause."),
	icon = "Interface\\Icons\\Spell_Nature_Lightning",
	width = WIDTH, height = HEIGHT,
	New = New,
})
