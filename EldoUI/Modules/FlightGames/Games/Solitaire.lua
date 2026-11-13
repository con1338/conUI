-- EldoUI Flight Games: Solitaire (Klondike). Seven piles are dealt, the
-- top card of each face up. Build the piles down in alternating colors
-- (a red 9 on a black 10), move whole runs of face-up cards, and fill an
-- empty pile only with a king. Draw from the stock to the waste, one card
-- or three at a time. Build the four foundations up by suit from ace to
-- king to win; the faster, the better.
-- Click a card, then where it goes; a right-click or a double-click sends
-- a card home to its foundation. Space draws, U takes back the last move,
-- A sends every card that can go home.
-- Written from scratch for EldoUI; the cards are EldoUI's own art on the
-- parchment colors of the design tokens.
local _, E = ...
local M = E.FlightGames
local Key = E.Key
local L = E.L
local B = M.Board

local WIDTH, HEIGHT = 640, 560
local CW, CH, GAP = 74, 104, 14
local LEFT = math.floor((WIDTH - (CW * 7 + GAP * 6)) / 2)
local TOP, TAB_Y = 10, 130
local DOWN_STEP, UP_STEP = 12, 27
local FAN = 18                 -- the spread of the drawn cards (draw three)
local DOUBLE = 0.4             -- seconds between the clicks of a double-click
local HOME_STEP = 0.07         -- the cards fly home one by one at the end
local UNDO_MAX = 200
local MODES = {
	{ key = "one", title = "Draw one", draw = 1 },
	{ key = "three", title = "Draw three", draw = 3 },
}
local SUITS = { "Spade", "Heart", "Diamond", "Club" }
local RED = { false, true, true, false }
local RANKS = { "A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K" }

local Solitaire = {}
Solitaire.__index = Solitaire
-- What a saved game keeps (the board, the score and the timers).
Solitaire.saveKeys = { "tab", "found", "waste", "stock", "moves", "time", "clock", "homing" }

local function ModeOf(mode)
	return mode and mode.draw and mode or MODES[1]
end

local function SuitOf(id) return math.floor((id - 1) / 13) + 1 end
local function RankOf(id) return (id - 1) % 13 + 1 end
local function IsRed(id) return RED[SuitOf(id)] end

local function ColumnX(column) return LEFT + (column - 1) * (CW + GAP) end

-- One card: a frame with the card art, the rank and the suits.
local function MakeCard(area, id)
	local card = { id = id }
	local frame = CreateFrame("Frame", nil, area)
	frame:SetSize(CW, CH)
	card.frame = frame
	card.face = frame:CreateTexture(nil, "BACKGROUND")
	card.face:SetAllPoints()
	B.Art(card.face, "Card")
	card.back = frame:CreateTexture(nil, "BORDER")
	card.back:SetPoint("TOPLEFT", 3, -3)
	card.back:SetPoint("BOTTOMRIGHT", -3, 3)
	B.Art(card.back, "CardBack")
	card.rank = B.Label(frame, E.tokens.size.cardTitle, "body", "LEFT")
	card.rank:SetPoint("TOPLEFT", 6, -5)
	card.rank:SetShadowOffset(0, 0)
	card.small = frame:CreateTexture(nil, "ARTWORK")
	card.small:SetSize(13, 13)
	card.small:SetPoint("TOPRIGHT", -6, -6)
	card.foot = frame:CreateTexture(nil, "ARTWORK")
	card.foot:SetSize(13, 13)
	card.foot:SetPoint("BOTTOMRIGHT", -6, 6)
	card.footRank = B.Label(frame, E.tokens.size.small, "body", "LEFT")
	card.footRank:SetPoint("BOTTOMLEFT", 6, 5)
	card.footRank:SetShadowOffset(0, 0)
	card.big = frame:CreateTexture(nil, "ARTWORK")
	card.big:SetSize(34, 34)
	card.big:SetPoint("CENTER", 0, -6)
	-- The court cards carry their letter large, over a faint suit.
	card.letter = B.Label(frame, E.tokens.size.hero, "body")
	card.letter:SetPoint("CENTER", 0, -4)
	card.letter:SetShadowOffset(0, 0)
	card.mark = frame:CreateTexture(nil, "OVERLAY")
	card.mark:SetPoint("TOPLEFT", -3, 3)
	card.mark:SetPoint("BOTTOMRIGHT", 3, -3)
	card.mark:Hide()
	local suit = SUITS[SuitOf(id)]
	B.Art(card.small, suit)
	B.Art(card.foot, suit)
	B.Art(card.big, suit)
	card.rank:SetText(RANKS[RankOf(id)])
	card.footRank:SetText(RANKS[RankOf(id)])
	card.court = RankOf(id) > 10
	card.letter:SetText(card.court and RANKS[RankOf(id)] or "")
	return card
end

local function New(host, mode)
	mode = ModeOf(mode)
	local game = setmetatable({ host = host, mode = mode, cards = {}, slots = {} }, Solitaire)
	local area = host.area
	-- Empty places: the stock, the four foundations and the seven piles.
	local function Slot(x, y, suit)
		local slot = B.Sprite(area, CW, CH, "BORDER")
		B.Place(slot, x, y, area)
		local glyph
		if suit then
			glyph = B.Sprite(area, 28, 28, "ARTWORK")
			B.Place(glyph, x + (CW - 28) / 2, y + (CH - 28) / 2, area)
			B.Art(glyph, SUITS[suit])
		end
		return { tex = slot, glyph = glyph, suit = suit }
	end
	game.slots.stock = Slot(ColumnX(1), TOP)
	for f = 1, 4 do game.slots["found" .. f] = Slot(ColumnX(3 + f), TOP, f) end
	for t = 1, 7 do game.slots["tab" .. t] = Slot(ColumnX(t), TAB_Y) end
	game.recycle = B.Label(area, E.tokens.size.small, "secondary")
	game.recycle:SetPoint("CENTER", area, "TOPLEFT", ColumnX(1) + CW / 2, -(TOP + CH / 2))
	game.info = B.Label(area, E.tokens.size.small, "secondary", "LEFT")
	game.info:SetPoint("TOPLEFT", area, "TOPLEFT", ColumnX(2) + CW + FAN * 2 + 8, -(TOP + 4))
	game.info:SetWidth(ColumnX(4) - (ColumnX(2) + CW + FAN * 2 + 8) - 4)
	for id = 1, 52 do game.cards[id] = MakeCard(area, id) end
	return game
end

---------------------------------------------------------------------------
-- The deal and the moves
---------------------------------------------------------------------------
function Solitaire:Start()
	local deck = {}
	for id = 1, 52 do deck[id] = id end
	for i = #deck, 2, -1 do
		local j = self.host.Random(i)
		deck[i], deck[j] = deck[j], deck[i]
	end
	self.tab, self.found, self.waste, self.stock = {}, { {}, {}, {}, {} }, {}, {}
	local at = 1
	for t = 1, 7 do
		self.tab[t] = {}
		for n = 1, t do
			self.tab[t][n] = { id = deck[at], up = n == t }
			at = at + 1
		end
	end
	for i = at, 52 do self.stock[#self.stock + 1] = deck[i] end
	self.moves, self.time, self.clock = 0, 0, 0
	self.history = {}
	self.picked, self.lastClick = nil, nil
	self.homing, self.homeWait = false, 0
	self.won = false
	self.host.Score(0)
	self:Draw()
end

-- A copy of the table, for Undo.
function Solitaire:Snapshot()
	local copy = { tab = {}, found = {}, waste = {}, stock = {}, moves = self.moves }
	for t = 1, 7 do
		copy.tab[t] = {}
		for n, c in ipairs(self.tab[t]) do copy.tab[t][n] = { id = c.id, up = c.up } end
	end
	for f = 1, 4 do copy.found[f] = { unpack(self.found[f]) } end
	copy.waste = { unpack(self.waste) }
	copy.stock = { unpack(self.stock) }
	return copy
end

function Solitaire:Remember()
	table.insert(self.history, self:Snapshot())
	if #self.history > UNDO_MAX then table.remove(self.history, 1) end
end

function Solitaire:Undo()
	local last = table.remove(self.history)
	if not last or self.homing then return false end
	self.tab, self.found, self.waste, self.stock = last.tab, last.found, last.waste, last.stock
	self.moves = last.moves
	self.picked = nil
	self.host.Sound("turn")
	self:Draw()
	return true
end

-- Draws from the stock, or turns the waste over when the stock is empty.
function Solitaire:DrawStock()
	if self.homing then return end
	if #self.stock == 0 and #self.waste == 0 then return end
	self:Remember()
	if #self.stock == 0 then
		for i = #self.waste, 1, -1 do self.stock[#self.stock + 1] = self.waste[i] end
		self.waste = {}
	else
		for _ = 1, self.mode.draw do
			local id = table.remove(self.stock)
			if not id then break end
			self.waste[#self.waste + 1] = id
		end
	end
	self.moves = self.moves + 1
	self.picked = nil
	self.host.Sound("turn")
	self:Draw()
end

-- The cards a pick holds: { from = "waste" | "found" | "tab", pile, index }.
function Solitaire:Held(pick)
	if pick.from == "waste" then return { self.waste[#self.waste] } end
	if pick.from == "found" then
		local pile = self.found[pick.pile]
		return { pile[#pile] }
	end
	local out = {}
	for n = pick.index, #self.tab[pick.pile] do out[#out + 1] = self.tab[pick.pile][n].id end
	return out
end

function Solitaire:CanFound(id, f)
	local pile = self.found[f]
	if SuitOf(id) ~= f then return false end
	if #pile == 0 then return RankOf(id) == 1 end
	return RankOf(id) == RankOf(pile[#pile]) + 1
end

function Solitaire:CanTab(id, t)
	local pile = self.tab[t]
	if #pile == 0 then return RankOf(id) == 13 end
	local top = pile[#pile]
	return top.up and IsRed(top.id) ~= IsRed(id) and RankOf(top.id) == RankOf(id) + 1
end

-- Takes the picked cards off their pile and turns up the card under them.
function Solitaire:Lift(pick)
	if pick.from == "waste" then
		table.remove(self.waste)
	elseif pick.from == "found" then
		table.remove(self.found[pick.pile])
	else
		local pile = self.tab[pick.pile]
		for n = #pile, pick.index, -1 do pile[n] = nil end
		local top = pile[#pile]
		if top and not top.up then top.up = true end
	end
end

-- Moves a pick to a place ("found" or "tab", pile). True when it went.
function Solitaire:Move(pick, to, pile)
	local held = self:Held(pick)
	if #held == 0 or (pick.from == to and pick.pile == pile) then return false end
	if to == "found" then
		if #held ~= 1 or not self:CanFound(held[1], pile) then return false end
	elseif not self:CanTab(held[1], pile) then
		return false
	end
	self:Remember()
	self:Lift(pick)
	for _, id in ipairs(held) do
		if to == "found" then
			table.insert(self.found[pile], id)
		else
			table.insert(self.tab[pile], { id = id, up = true })
		end
	end
	self.moves = self.moves + 1
	self.picked = nil
	self.host.Sound(to == "found" and "point" or "turn")
	self:AfterMove()
	return true
end

-- Sends one card home when it can go; true when it went.
function Solitaire:Home(pick)
	local held = self:Held(pick)
	if #held ~= 1 then return false end
	return self:Move(pick, "found", SuitOf(held[1]))
end

-- Every card that can go home goes, until none can. True when any went.
function Solitaire:HomeAll()
	local any = false
	local again = true
	while again do
		again = false
		if #self.waste > 0 and self:Home({ from = "waste" }) then again, any = true, true end
		for t = 1, 7 do
			local n = #self.tab[t]
			if n > 0 and self.tab[t][n].up and self:Home({ from = "tab", pile = t, index = n }) then again, any = true, true end
		end
	end
	return any
end

function Solitaire:Count()
	local n = 0
	for f = 1, 4 do n = n + #self.found[f] end
	return n
end

-- Every card is in sight: the game finishes itself.
function Solitaire:AllUp()
	if #self.stock > 0 or #self.waste > 0 then return false end
	for t = 1, 7 do
		for _, c in ipairs(self.tab[t]) do
			if not c.up then return false end
		end
	end
	return true
end

function Solitaire:AfterMove()
	if self:Count() == 52 then
		self:Win()
		return
	end
	if self:AllUp() then self.homing = true end
	self:Draw()
end

function Solitaire:Win()
	if self.won then return end
	self.won = true
	self.homing = false
	self:Draw()
	self.host.Score(math.max(1, math.floor(self.time + 0.5)))
	self.host.Over(true)
end

---------------------------------------------------------------------------
-- Time, keys and clicks
---------------------------------------------------------------------------
function Solitaire:Update(dt)
	self.clock = self.clock + dt
	if self.won then return end
	self.time = self.time + dt
	local whole = math.floor(self.time)
	if whole ~= self.shownTime then
		self.shownTime = whole
		self.host.Score(whole)
	end
	if self.homing then
		self.homeWait = self.homeWait - dt
		if self.homeWait <= 0 then
			self.homeWait = HOME_STEP
			local before = self:Count()
			for t = 1, 7 do
				local n = #self.tab[t]
				if n > 0 and self:Home({ from = "tab", pile = t, index = n }) then break end
			end
			if self:Count() == before and not self.won then self.homing = false end
		end
	end
end

function Solitaire:Key(key)
	if key == "SPACE" or key == "ENTER" then
		self:DrawStock()
		return true
	end
	if key == "U" or key == "BACKSPACE" then
		self:Undo()
		return true
	end
	if key == "A" then
		if self:HomeAll() then self:Draw() end
		return true
	end
	return false
end

-- What is under a point: a card pick, a place, or the stock.
function Solitaire:At(x, y)
	local function In(rx, ry, w, h) return x >= rx and x <= rx + w and y >= ry and y <= ry + h end
	if In(ColumnX(1), TOP, CW, CH) then return { stock = true } end
	if #self.waste > 0 then
		local wx = self.wasteX or ColumnX(2)
		if In(wx, TOP, CW, CH) then return { pick = { from = "waste" } } end
	end
	for f = 1, 4 do
		if In(ColumnX(3 + f), TOP, CW, CH) then
			return { place = { "found", f }, pick = #self.found[f] > 0 and { from = "found", pile = f } or nil }
		end
	end
	for t = 1, 7 do
		local pile, offsets = self.tab[t], self.offsets and self.offsets[t]
		local left = ColumnX(t)
		if x >= left and x <= left + CW then
			local bottom = TAB_Y + CH + (offsets and offsets[#pile] or 0)
			if y >= TAB_Y and y <= math.max(bottom, TAB_Y + CH) then
				for n = #pile, 1, -1 do
					local top = TAB_Y + (offsets and offsets[n] or 0)
					if y >= top and pile[n].up then
						return { place = { "tab", t }, pick = { from = "tab", pile = t, index = n } }
					elseif y >= top then
						break
					end
				end
				return { place = { "tab", t } }
			end
		end
	end
	return nil
end

local function SamePick(a, b)
	return a and b and a.from == b.from and a.pile == b.pile and a.index == b.index
end

function Solitaire:Press(button, x, y)
	if self.won or self.homing or not (x and y) then return end
	local hit = self:At(x, y)
	if button == "RightButton" then
		if hit and hit.pick and self:Home(hit.pick) then return end
		self.picked = nil
		self:Draw()
		return
	end
	if button ~= "LeftButton" then return end
	if not hit then
		self.picked = nil
		self:Draw()
		return
	end
	if hit.stock then
		self:DrawStock()
		return
	end
	-- A double-click on a card sends it home.
	local last = self.lastClick
	self.lastClick = { pick = hit.pick, at = self.clock }
	if hit.pick and last and SamePick(last.pick, hit.pick) and self.clock - last.at <= DOUBLE then
		self.lastClick = nil
		if self:Home(hit.pick) then return end
	end
	if self.picked and hit.place and self:Move(self.picked, hit.place[1], hit.place[2]) then return end
	if hit.pick and not SamePick(self.picked, hit.pick) then
		self.picked = hit.pick
	else
		self.picked = nil
	end
	self:Draw()
end

-- "84 moves", for the end of the game.
function Solitaire:Summary()
	if not self.moves then return nil end
	return E:Plural(self.moves, "%d move", "%d moves"):format(self.moves)
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------
-- The face-up steps of a pile, squeezed when it would run off the board.
local function Offsets(pile)
	local out, y = {}, 0
	local downs, ups = 0, 0
	for _, c in ipairs(pile) do
		if c.up then ups = ups + 1 else downs = downs + 1 end
	end
	local room = HEIGHT - 6 - TAB_Y - CH
	local upStep = UP_STEP
	local need = downs * DOWN_STEP + math.max(0, ups - 1) * UP_STEP
	if need > room and ups > 1 then upStep = math.max(12, (room - downs * DOWN_STEP) / (ups - 1)) end
	for n, c in ipairs(pile) do
		out[n] = y
		y = y + (c.up and upStep or DOWN_STEP)
	end
	return out
end

function Solitaire:PlaceCard(id, x, y, z, up, picked)
	local card = self.cards[id]
	local frame = card.frame
	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", self.host.area, "TOPLEFT", x, -y)
	frame:SetFrameLevel(self.host.area:GetFrameLevel() + 2 + z)
	local paper = E.tokens.paper
	if up then
		B.Art(card.face, "Card", paper.fill, 1)
		card.back:Hide()
		local ink = IsRed(id) and paper.bad or paper.body
		card.rank:SetTextColor(ink[1], ink[2], ink[3])
		card.footRank:SetTextColor(ink[1], ink[2], ink[3])
		card.letter:SetTextColor(ink[1], ink[2], ink[3])
		card.small:SetVertexColor(ink[1], ink[2], ink[3])
		card.foot:SetVertexColor(ink[1], ink[2], ink[3])
		card.big:SetVertexColor(ink[1], ink[2], ink[3], card.court and 0.18 or 1)
		card.big:SetSize(card.court and 52 or 34, card.court and 52 or 34)
		card.rank:Show()
		card.footRank:Show()
		card.letter:Show()
		card.small:Show()
		card.foot:Show()
		card.big:Show()
	else
		local accent = self.host.Color("accent")
		B.Art(card.face, "Card", { accent[1] * 0.35, accent[2] * 0.35, accent[3] * 0.35 }, 1)
		B.Art(card.back, "CardBack", accent, 0.9)
		card.back:Show()
		card.rank:Hide()
		card.footRank:Hide()
		card.letter:Hide()
		card.small:Hide()
		card.foot:Hide()
		card.big:Hide()
	end
	if picked then
		B.Art(card.mark, "Ring", self.host.Color("accent"), 1)
		card.mark:Show()
	else
		card.mark:Hide()
	end
	frame:Show()
end

function Solitaire:IsPicked(from, pile, index)
	local p = self.picked
	if not p or p.from ~= from then return false end
	if from == "waste" then return true end
	if from == "found" then return p.pile == pile end
	return p.pile == pile and index >= p.index
end

function Solitaire:Draw()
	local dim = self.host.Color("dim")
	for _, slot in pairs(self.slots) do
		B.Art(slot.tex, "Card", dim, 0.18)
		if slot.glyph then B.Art(slot.glyph, SUITS[slot.suit], dim, 0.35) end
	end
	if not self.tab then
		for _, card in ipairs(self.cards) do card.frame:Hide() end
		return
	end
	local shown = {}
	-- The stock: one back while any card is left.
	if #self.stock > 0 then
		local id = self.stock[#self.stock]
		self:PlaceCard(id, ColumnX(1), TOP, 1, false)
		shown[id] = true
		self.recycle:SetText("")
	else
		self.recycle:SetText(#self.waste > 0 and L["Turn over"] or "")
	end
	-- The waste: the last one (or three) fanned out.
	local count = #self.waste
	local fan = self.mode.draw > 1 and math.min(3, count) or math.min(1, count)
	self.wasteX = ColumnX(2)
	for i = 1, fan do
		local index = count - fan + i
		local id = self.waste[index]
		local x = ColumnX(2) + (i - 1) * FAN
		self:PlaceCard(id, x, TOP, i, true, i == fan and self:IsPicked("waste"))
		shown[id] = true
		if i == fan then self.wasteX = x end
	end
	for f = 1, 4 do
		local pile = self.found[f]
		if #pile > 0 then
			local id = pile[#pile]
			self:PlaceCard(id, ColumnX(3 + f), TOP, 1, true, self:IsPicked("found", f))
			shown[id] = true
		end
	end
	self.offsets = {}
	for t = 1, 7 do
		local pile = self.tab[t]
		local offsets = Offsets(pile)
		self.offsets[t] = offsets
		for n, c in ipairs(pile) do
			self:PlaceCard(c.id, ColumnX(t), TAB_Y + offsets[n], n, c.up, c.up and self:IsPicked("tab", t, n))
			shown[c.id] = true
		end
	end
	for id, card in ipairs(self.cards) do
		if not shown[id] then card.frame:Hide() end
	end
	self.info:SetText(L["Stock: %d"]:format(#self.stock) .. "\n" .. E:Plural(self.moves, "%d move", "%d moves"):format(self.moves))
end

function Solitaire:Loaded()
	self.history, self.picked, self.lastClick = {}, nil, nil
	self.won, self.homeWait = false, 0
end

M:RegisterGame({
	key = "solitaire", order = 110, group = "board",
	title = "Solitaire", desc = "Build four suits from ace to king; the piles go down in alternating colors.",
	controls = Key("Click a card, then where it goes. Right-click or double-click: send home. Space: draw. U: undo. A: all home."),
	actions = { { key = "U", label = "Undo" }, { key = "A", label = "All home" } },
	icon = "Interface\\Icons\\INV_Misc_Ticket_Tarot_Stack_01",
	lower = true, unit = "seconds",
	modes = MODES,
	Size = function() return WIDTH, HEIGHT end,
	New = New,
})
