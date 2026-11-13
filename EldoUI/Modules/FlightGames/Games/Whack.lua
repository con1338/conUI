-- EldoUI Flight Games: Whack-a-Gnoll. Gnolls pop out of nine burrows; hit
-- each one before it ducks back down. A golden gnoll is worth five, a hit
-- in a row raises the bonus, and the gnome who peeks out now and then
-- must be left alone. Forty-five seconds a round.
-- Written from scratch for EldoUI; the burrows show the game's own icons.
local _, E = ...
local M = E.FlightGames
local Key = E.Key
local L = E.L
local B = M.Board

local SIZE, GAP = 104, 18
local WIDTH = SIZE * 3 + GAP * 4
local TOP = 34
local HEIGHT = TOP + SIZE * 3 + GAP * 3
local ROUND = 45
local RISE = 0.12            -- a head comes up or goes down this long
local GNOLL = "Interface\\Icons\\Ability_Hunter_Pet_Hyena"
local GNOME = "Interface\\Icons\\INV_Misc_Head_Gnome_01"
-- Number keys as on a number pad: 7 8 9 on top.
local KEYS = {
	["7"] = 1, ["8"] = 2, ["9"] = 3, ["4"] = 4, ["5"] = 5, ["6"] = 6, ["1"] = 7, ["2"] = 8, ["3"] = 9,
	NUMPAD7 = 1, NUMPAD8 = 2, NUMPAD9 = 3, NUMPAD4 = 4, NUMPAD5 = 5, NUMPAD6 = 6, NUMPAD1 = 7, NUMPAD2 = 8, NUMPAD3 = 9,
}

local Whack = {}
Whack.__index = Whack
-- What a saved game keeps (the board, the score and the timers).
Whack.saveKeys = { "holes", "score", "time", "combo", "next", "hits" }

local function New(host)
	local game = setmetatable({ host = host }, Whack)
	local area = host.area
	game.views = {}
	for i = 1, 9 do
		local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
		local x, y = GAP + col * (SIZE + GAP), TOP + row * (SIZE + GAP)
		local view = { x = x, y = y }
		view.mound = B.Sprite(area, SIZE, SIZE, "BORDER")
		B.Place(view.mound, x, y, area)
		view.hole = B.Sprite(area, SIZE - 30, 22, "ARTWORK")
		B.Place(view.hole, x + 15, y + SIZE - 34, area)
		view.head = B.Sprite(area, SIZE - 36, SIZE - 36, "OVERLAY")
		view.ring = B.Sprite(area, SIZE - 26, SIZE - 26, "OVERLAY")
		view.number = B.Label(area, E.tokens.size.tiny, "dim")
		view.number:SetPoint("TOPLEFT", area, "TOPLEFT", x + 6, -(y + 5))
		local digit = { 7, 8, 9, 4, 5, 6, 1, 2, 3 }
		view.number:SetText(digit[i])
		game.views[i] = view
	end
	game.clock = B.Label(area, E.tokens.size.cardTitle, "body", "LEFT")
	game.clock:SetPoint("TOPLEFT", area, "TOPLEFT", GAP, -8)
	game.comboText = B.Label(area, E.tokens.size.cardTitle, "secondary", "RIGHT")
	game.comboText:SetPoint("TOPRIGHT", area, "TOPLEFT", WIDTH - GAP, -8)
	game.fx = B.Effects(area)
	return game
end

function Whack:Start()
	self.holes = {}
	for i = 1, 9 do self.holes[i] = { kind = nil, up = 0, stay = 0 } end
	self.score, self.time, self.combo, self.hits = 0, ROUND, 0, 0
	self.next = 0.6
	self.host.Score(0)
	self:Draw()
end

function Whack:Pop()
	local free = {}
	for i, hole in ipairs(self.holes) do
		if not hole.kind then free[#free + 1] = i end
	end
	if #free == 0 then return end
	local hole = self.holes[free[self.host.Random(#free)]]
	local roll = self.host.Random(100)
	hole.kind = roll <= 12 and "gnome" or roll <= 22 and "gold" or "gnoll"
	-- Heads stay up for less time as the round goes on.
	local elapsed = ROUND - self.time
	hole.stay = math.max(0.45, 1.25 - elapsed * 0.017) * (hole.kind == "gold" and 0.75 or 1)
	hole.up, hole.rising = 0, true
end

function Whack:Hit(i)
	local hole = self.holes[i]
	if not hole then return end
	local view = self.views[i]
	local cx, cy = view.x + SIZE / 2, view.y + SIZE / 2
	if not hole.kind or hole.up < 0.4 or hole.hit then
		self.combo = 0
		self.fx:Burst(cx, cy + 20, self.host.Color("dim"), 50, 0.3)
		self:Draw()
		return
	end
	hole.hit = true
	hole.stay = 0.12
	if hole.kind == "gnome" then
		self.combo = 0
		self.score = math.max(0, self.score - 20)
		self.fx:Burst(cx, cy, self.host.Color("bad"), SIZE * 1.2)
		self.fx:Float(cx, cy - 20, "-20", self.host.Color("bad"))
		self.host.Sound("over")
	else
		self.combo = self.combo + 1
		self.hits = self.hits + 1
		local points = (hole.kind == "gold" and 50 or 10) * (1 + math.floor(self.combo / 5))
		self.score = self.score + points
		local color = hole.kind == "gold" and self.host.Color("gold") or self.host.Color("good")
		self.fx:Burst(cx, cy, color, SIZE * 1.3)
		self.fx:Sparks(cx, cy, color, hole.kind == "gold" and 14 or 7, 150)
		self.fx:Float(cx, cy - 24, "+" .. points, color)
		self.host.Sound("point")
	end
	self.host.Score(self.score)
	self:Draw()
end

function Whack:Key(key)
	local i = KEYS[key]
	if i then
		self:Hit(i)
		return true
	end
	return false
end

function Whack:Press(button, x, y)
	if button ~= "LeftButton" or not (x and y) then return end
	for i, view in ipairs(self.views) do
		if x >= view.x and x <= view.x + SIZE and y >= view.y and y <= view.y + SIZE then
			self:Hit(i)
			return
		end
	end
end

function Whack:Update(dt)
	self.fx:Update(dt)
	self.time = self.time - dt
	if self.time <= 0 then
		self.time = 0
		self:Draw()
		self.host.Over(true)
		return
	end
	self.next = self.next - dt * self.host.Pace()
	if self.next <= 0 then
		local elapsed = ROUND - self.time
		self.next = math.max(0.28, 0.85 - elapsed * 0.012) * (0.7 + self.host.Random(60) / 100)
		self:Pop()
	end
	for _, hole in ipairs(self.holes) do
		if hole.kind then
			if hole.rising then
				hole.up = math.min(1, hole.up + dt / RISE)
				if hole.up >= 1 then hole.rising = false end
			elseif hole.stay > 0 then
				hole.stay = hole.stay - dt
			else
				hole.up = hole.up - dt / RISE
				if hole.up <= 0 then
					-- A gnoll that got away breaks the run.
					if hole.kind ~= "gnome" and not hole.hit then self.combo = 0 end
					hole.kind, hole.up, hole.hit = nil, 0, nil
				end
			end
		end
	end
	self:Draw()
end

function Whack:Summary()
	if not self.hits then return nil end
	return E:Plural(self.hits, "%d gnoll hit", "%d gnolls hit"):format(self.hits)
end

function Whack:Draw()
	local area, color, palette = self.host.area, self.host.Color, self.host.Palette()
	local bronze = E.tokens.palette.bronze
	for i, view in ipairs(self.views) do
		local hole = self.holes[i]
		B.Tile(view.mound, palette[3], 0.35)
		B.Tile(view.hole, { 0.05, 0.04, 0.03 }, 0.9)
		local up = hole.kind and hole.up or 0
		local head = view.head
		if up > 0 then
			local full = SIZE - 36
			local shown = math.max(1, full * up)
			head:SetSize(full, shown)
			B.Place(head, view.x + 18, view.y + SIZE - 30 - shown, area)
			if view.kind ~= hole.kind then
				view.kind = hole.kind
				E:SetClientFile(head, hole.kind == "gnome" and GNOME or GNOLL, "Interface\\Icons\\INV_Misc_QuestionMark")
			end
			-- Only the part above the burrow shows.
			head:SetTexCoord(0.08, 0.92, 0.08, 0.08 + 0.84 * up)
			head:SetVertexColor(1, 1, 1, hole.hit and 0.5 or 1)
			head:Show()
			view.ring:SetShown(hole.kind == "gold")
			if hole.kind == "gold" then
				B.Art(view.ring, "Ring", color("gold"), up)
				B.Place(view.ring, view.x + 13, view.y + SIZE - 25 - (SIZE - 26) * up, area)
			end
		else
			head:Hide()
			view.ring:Hide()
		end
	end
	self.clock:SetText(L["Time: %s"]:format(E:FormatDuration(math.ceil(self.time or 0), "clock")))
	self.clock:SetTextColor(unpack((self.time or 0) < 10 and color("warn") or color("body")))
	if (self.combo or 0) >= 5 then
		self.comboText:SetText(L["Bonus x%d"]:format(1 + math.floor(self.combo / 5)))
		self.comboText:SetTextColor(bronze[1], bronze[2], bronze[3])
	else
		self.comboText:SetText(self.combo and self.combo > 0 and L["%d in a row"]:format(self.combo) or "")
		self.comboText:SetTextColor(unpack(color("secondary")))
	end
end

M:RegisterGame({
	key = "whack", order = 27, group = "arcade",
	title = "Whack-a-Gnoll", desc = "Hit the gnolls as they pop up, and leave the gnome alone.",
	controls = Key("Click a burrow, or the number keys as on a number pad. P: pause."),
	icon = GNOLL,
	width = WIDTH, height = HEIGHT,
	New = New,
})
