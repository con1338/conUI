-- EldoUI Flight Games: Icon Mahjong. A stack of tiles in four layers, each
-- tile showing a spell or an item icon. Take away two tiles with the same
-- icon when both are free: nothing lies on them, and the left or the
-- right side is open. Clear the whole stack. Every deal can be cleared,
-- and if you get stuck the tiles left are dealt again.
-- Written from scratch for EldoUI; the tiles show the game's own icons.
local _, E = ...
local M = E.FlightGames
local Key = E.Key
local L = E.L
local B = M.Board

local TILE_W, TILE_H, DEPTH = 40, 48, 5
local LEFT, TOP = 20, 22
local WIDTH, HEIGHT = LEFT * 2 + 8 * TILE_W + 4, TOP + 6 * TILE_H + 40
-- The stack: each layer a block of tiles, x and y in tile steps.
local LAYERS = {
	{ x1 = 1, x2 = 8, y1 = 1, y2 = 6 },
	{ x1 = 2, x2 = 7, y1 = 2, y2 = 5 },
	{ x1 = 3, x2 = 6, y1 = 3, y2 = 4 },
	{ x1 = 4, x2 = 5, y1 = 3, y2 = 4 },
}
local ICONS = {
	"Interface\\Icons\\Spell_Fire_FireBolt02", "Interface\\Icons\\Spell_Frost_FrostBolt02", "Interface\\Icons\\Spell_Holy_FlashHeal",
	"Interface\\Icons\\Ability_Warrior_Charge", "Interface\\Icons\\Ability_Rogue_Sprint", "Interface\\Icons\\Spell_Frost_FrostNova",
	"Interface\\Icons\\Spell_Holy_PowerWordShield", "Interface\\Icons\\Ability_Hunter_SniperShot", "Interface\\Icons\\Spell_Fire_Immolation",
	"Interface\\Icons\\Ability_Warrior_Cleave", "Interface\\Icons\\Spell_Arcane_TeleportStormwind", "Interface\\Icons\\Ability_Seal",
	"Interface\\Icons\\Spell_Holy_PrayerOfHealing", "Interface\\Icons\\Ability_Warrior_DefensiveStance", "Interface\\Icons\\Ability_Druid_ChallangingRoar",
	"Interface\\Icons\\Ability_DualWield", "Interface\\Icons\\Ability_Rogue_FeignDeath", "Interface\\Icons\\Spell_Fire_SealOfFire",
	"Interface\\Icons\\INV_Misc_Gem_Ruby_01", "Interface\\Icons\\INV_Misc_Gem_Amethyst_02", "Interface\\Icons\\INV_Misc_Coin_01",
}

local Mahjong = {}
Mahjong.__index = Mahjong
-- What a saved game keeps (the board, the score and the timers).
Mahjong.saveKeys = { "tiles", "pairs", "deals" }

-- Every place in the stack, bottom layer first.
local PLACES = {}
for z, layer in ipairs(LAYERS) do
	for y = layer.y1, layer.y2 do
		for x = layer.x1, layer.x2 do PLACES[#PLACES + 1] = { x = x, y = y, z = z } end
	end
end
local function Spot(x, y, z) return z * 10000 + y * 100 + x end

local function New(host)
	local game = setmetatable({ host = host, views = {} }, Mahjong)
	local area = host.area
	game.layers = {}
	for z = 1, #LAYERS do
		local frame = CreateFrame("Frame", nil, area)
		frame:SetAllPoints()
		frame:SetFrameLevel(area:GetFrameLevel() + z * 2)
		game.layers[z] = frame
	end
	for i, place in ipairs(PLACES) do
		local frame = game.layers[place.z]
		local x = LEFT + (place.x - 1) * TILE_W - (place.z - 1) * DEPTH
		local y = TOP + (place.y - 1) * TILE_H - (place.z - 1) * DEPTH
		local view = { x = x, y = y }
		view.shade = B.Sprite(frame, TILE_W, TILE_H, "BACKGROUND")
		B.Place(view.shade, x + 3, y + 3, frame)
		view.back = B.Sprite(frame, TILE_W, TILE_H, "BORDER")
		B.Place(view.back, x, y, frame)
		view.icon = B.Sprite(frame, TILE_W - 12, TILE_W - 12, "ARTWORK")
		B.Place(view.icon, x + 6, y + (TILE_H - TILE_W) / 2 + 6, frame)
		view.ring = B.Sprite(frame, TILE_W + 6, TILE_H + 6, "OVERLAY")
		B.Place(view.ring, x - 3, y - 3, frame)
		game.views[i] = view
	end
	game.info = B.Label(area, E.tokens.size.small, "secondary")
	game.info:SetPoint("BOTTOM", area, "BOTTOMLEFT", WIDTH / 2, 8)
	game.fx = B.Effects(game.layers[#LAYERS])
	return game
end

-- Which places hold a tile, by spot.
function Mahjong:Taken()
	local taken = {}
	for i, place in ipairs(PLACES) do
		if self.tiles[i] and self.tiles[i] > 0 then taken[Spot(place.x, place.y, place.z)] = true end
	end
	return taken
end

local function Free(place, taken)
	if taken[Spot(place.x, place.y, place.z + 1)] then return false end
	return not taken[Spot(place.x - 1, place.y, place.z)] or not taken[Spot(place.x + 1, place.y, place.z)]
end

-- Deals icons onto the given places so the stack can be cleared: pairs are
-- taken away in a pretend game, and each pair gets one icon.
function Mahjong:Deal(places)
	for _ = 1, 50 do
		local taken, left = {}, {}
		for _, i in ipairs(places) do
			local p = PLACES[i]
			taken[Spot(p.x, p.y, p.z)] = true
			left[#left + 1] = i
		end
		local icons = {}
		for k = 1, #places / 2 do icons[k] = (k - 1) % #ICONS + 1 end
		for k = #icons, 2, -1 do
			local j = self.host.Random(k)
			icons[k], icons[j] = icons[j], icons[k]
		end
		local deal, ok = {}, true
		for k = 1, #places / 2 do
			local free = {}
			for n, i in ipairs(left) do
				if Free(PLACES[i], taken) then free[#free + 1] = n end
			end
			if #free < 2 then
				ok = false
				break
			end
			local a = table.remove(free, self.host.Random(#free))
			local b = free[self.host.Random(#free)]
			local ia, ib = left[a], left[b]
			deal[ia], deal[ib] = icons[k], icons[k]
			for _, i in ipairs({ ia, ib }) do
				local p = PLACES[i]
				taken[Spot(p.x, p.y, p.z)] = nil
			end
			table.remove(left, math.max(a, b))
			table.remove(left, math.min(a, b))
		end
		if ok then
			for i, icon in pairs(deal) do self.tiles[i] = icon end
			return true
		end
	end
	return false
end

function Mahjong:Start()
	self.tiles = {}
	for i = 1, #PLACES do self.tiles[i] = 0 end
	local all = {}
	for i = 1, #PLACES do all[i] = i end
	self:Deal(all)
	self.pairs, self.deals, self.picked, self.hint, self.stuck = 0, 0, nil, nil, nil
	self.host.Score(0)
	self:Draw()
end

function Mahjong:Loaded()
	self.picked, self.hint = nil, nil
end

function Mahjong:FreeTiles()
	local taken, out = self:Taken(), {}
	for i, place in ipairs(PLACES) do
		if self.tiles[i] > 0 and Free(place, taken) then out[#out + 1] = i end
	end
	return out
end

-- A pair you can take now, or nil.
function Mahjong:FindPair()
	local seen = {}
	for _, i in ipairs(self:FreeTiles()) do
		local icon = self.tiles[i]
		if seen[icon] then return seen[icon], i end
		seen[icon] = i
	end
end

function Mahjong:Left()
	local n = 0
	for i = 1, #PLACES do if self.tiles[i] > 0 then n = n + 1 end end
	return n
end

function Mahjong:Pick(i)
	if self.tiles[i] == 0 then return end
	local taken = self:Taken()
	if not Free(PLACES[i], taken) then
		self.host.Sound("over")
		return
	end
	self.hint = nil
	if not self.picked or self.picked == i then
		self.picked = self.picked ~= i and i or nil
		self.host.Sound("turn")
	elseif self.tiles[self.picked] == self.tiles[i] then
		for _, k in ipairs({ self.picked, i }) do
			local view = self.views[k]
			self.fx:Burst(view.x + TILE_W / 2, view.y + TILE_H / 2, self.host.Color("gold"), TILE_H * 1.6, 0.4)
			self.tiles[k] = 0
		end
		self.picked = nil
		self.pairs = self.pairs + 1
		self.host.Score(self.pairs * 10)
		self.host.Sound("point")
		if self:Left() == 0 then
			self:Draw()
			self.host.Over(true)
			return
		end
		if not self:FindPair() and not self:Reshuffle() then
			self:Draw()
			self.host.Over(false)
			return
		end
	else
		self.picked = i
		self.host.Sound("turn")
	end
	self:Draw()
end

-- Stuck: the tiles left are dealt again so they can be cleared. When no
-- deal can clear them (say two tiles left, one on the other), the game
-- ends there.
function Mahjong:Reshuffle()
	local places, old = {}, {}
	for i = 1, #PLACES do
		if self.tiles[i] > 0 then
			places[#places + 1] = i
			old[i] = self.tiles[i]
			self.tiles[i] = 0
		end
	end
	if not self:Deal(places) then
		for i, icon in pairs(old) do self.tiles[i] = icon end
		self.stuck = true
		return false
	end
	self.deals = self.deals + 1
	self.fx:Float(WIDTH / 2, HEIGHT / 2, L["No pairs left: dealt again."], self.host.Color("warn"), E.tokens.size.cardTitle)
	return true
end

function Mahjong:Key(key)
	if key == "H" then
		local a, b = self:FindPair()
		self.hint = a and { a, b } or nil
		self:Draw()
		return true
	end
	return false
end

function Mahjong:Press(button, x, y)
	if button ~= "LeftButton" or not (x and y) then return end
	-- The top tile under the pointer wins.
	for i = #PLACES, 1, -1 do
		local view = self.views[i]
		if self.tiles[i] > 0 and x >= view.x and x <= view.x + TILE_W and y >= view.y and y <= view.y + TILE_H then
			self:Pick(i)
			return
		end
	end
end

function Mahjong:Update(dt)
	self.fx:Update(dt)
end

function Mahjong:Summary()
	if not self.pairs then return nil end
	if self.stuck then return L["No pairs left to take."] end
	return E:Plural(self.pairs, "%d pair taken", "%d pairs taken"):format(self.pairs)
end

function Mahjong:Draw()
	local color = self.host.Color
	local taken = self:Taken()
	local paper = E.tokens.paper and E.tokens.paper.fill or { 0.92, 0.88, 0.78 }
	for i, place in ipairs(PLACES) do
		local view, icon = self.views[i], self.tiles[i]
		local on = icon > 0
		view.shade:SetShown(on)
		view.back:SetShown(on)
		view.icon:SetShown(on)
		if on then
			local free = Free(place, taken)
			B.Fill(view.shade, { 0, 0, 0 }, 0.35)
			B.Art(view.back, "Card", paper, 1)
			local tone = free and 1 or 0.72
			view.back:SetVertexColor(paper[1] * tone, paper[2] * tone, paper[3] * tone, 1)
			if view.file ~= icon then
				view.file = icon
				E:SetClientFile(view.icon, ICONS[icon], "Interface\\Icons\\INV_Misc_QuestionMark")
				E:TrimIcon(view.icon)
			end
			view.icon:SetVertexColor(tone, tone, tone, 1)
		end
		local mark = on and (self.picked == i and color("gold") or (self.hint and (self.hint[1] == i or self.hint[2] == i)) and color("good"))
		view.ring:SetShown(mark and true or false)
		if mark then B.Art(view.ring, "Ring", mark, 1) end
	end
	local left = self:Left()
	self.info:SetText(E:Plural(left, "%d tile left. H: a hint.", "%d tiles left. H: a hint."):format(left))
end

M:RegisterGame({
	key = "mahjong", order = 81, group = "puzzle",
	title = "Icon Mahjong", desc = "Take away free pairs of matching icon tiles until the stack is gone.",
	controls = Key("Click two free tiles with the same icon. H: a hint. P: pause."),
	actions = { { key = "H", label = "Hint" } },
	icon = "Interface\\Icons\\INV_Misc_Gem_Amethyst_02",
	width = WIDTH, height = HEIGHT,
	New = New,
})
