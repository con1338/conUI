-- EldoUI Flight Games: Caravan Jam. The market is packed with carts and
-- wagons; the kodo cart has to leave through the gate on the right. Carts
-- slide only along their length. Click a cart, then where it goes in its
-- row or column (or move it with the arrow keys). Each board can be
-- solved, and the fewest moves are shown.
-- Written from scratch for EldoUI; the boards come from
-- tools/gen_puzzle_levels.py (PuzzleData.lua).
local _, E = ...
local M = E.FlightGames
local Key = E.Key
local L = E.L
local B = M.Board

local N, CELL = 6, 64
local TOP = 30
local GATE_ROW = 3
local WIDTH, HEIGHT = N * CELL + 16, TOP + N * CELL
local KODO = "Interface\\Icons\\Ability_Mount_Kodo_01"
local MODES = {
	{ key = "easy", title = "Easy" },
	{ key = "normal", title = "Normal" },
	{ key = "hard", title = "Hard" },
}
local DIRS = { UP = { 0, -1 }, W = { 0, -1 }, DOWN = { 0, 1 }, S = { 0, 1 }, LEFT = { -1, 0 }, A = { -1, 0 }, RIGHT = { 1, 0 }, D = { 1, 0 } }

local Caravan = {}
Caravan.__index = Caravan
-- What a saved market keeps.
Caravan.saveKeys = { "pick", "carts", "moves", "history", "sel", "lastMove" }

local function ModeOf(mode)
	return mode and mode.key and mode or MODES[2]
end

local function Boards(mode)
	local data = M.PuzzleData and M.PuzzleData.caravan
	return data and data[mode.key] or {}
end

-- The carts of a board text: { r, c, length, across }, the kodo cart first.
local function Parse(text)
	local seen, carts = {}, {}
	for i = 1, #text do
		local mark = text:sub(i, i)
		if mark ~= "." and not seen[mark] then
			seen[mark] = true
			local r, c = math.floor((i - 1) / N) + 1, (i - 1) % N + 1
			local across = c < N and text:sub(i + 1, i + 1) == mark
			local length = 0
			local step = across and 1 or N
			local j = i
			while j <= #text and text:sub(j, j) == mark do
				length = length + 1
				j = j + step
				if across and (j - 1) % N == 0 then break end
			end
			local cart = { r = r, c = c, len = length, across = across }
			if mark == "x" then table.insert(carts, 1, cart) else carts[#carts + 1] = cart end
		end
	end
	return carts
end
Caravan.Parse = Parse

local function New(host, mode)
	local game = setmetatable({ host = host, mode = ModeOf(mode), views = {} }, Caravan)
	local area = host.area
	game.grid = B.Grid(area, N, N, CELL, { gap = 2 })
	game.grid.frame:SetPoint("TOPLEFT", area, "TOPLEFT", 0, -TOP)
	game.gate = B.Sprite(area, 14, CELL - 8, "ARTWORK")
	B.Place(game.gate, N * CELL + 2, TOP + (GATE_ROW - 1) * CELL + 4, area)
	game.picked = B.Sprite(area, CELL, CELL, "OVERLAY")
	game.picked:SetDrawLayer("OVERLAY", 7)
	game.tally = B.Label(area, E.tokens.size.cardTitle, "body", "LEFT")
	game.tally:SetPoint("TOPLEFT", area, "TOPLEFT", 2, -6)
	game.prompt = B.Label(area, E.tokens.size.small, "secondary", "RIGHT")
	game.prompt:SetPoint("TOPRIGHT", area, "TOPLEFT", WIDTH - 2, -9)
	game.fx = B.Effects(area)
	return game
end

function Caravan:Entry()
	local list = Boards(self.mode)
	return list[self.pick or 1] or list[1]
end

function Caravan:Start()
	local list = Boards(self.mode)
	self.pick = #list > 0 and self.host.Random(1, #list) or 1
	local entry = self:Entry()
	self.carts = Parse(entry and entry[1] or "")
	self.moves, self.history, self.sel, self.lastMove = 0, {}, 1, nil
	self.fx:Clear()
	self.host.Score(0)
	self:Draw()
end

-- Which cart stands on a cell, or nil.
function Caravan:At(r, c)
	for index, cart in ipairs(self.carts) do
		if cart.across then
			if cart.r == r and c >= cart.c and c < cart.c + cart.len then return index end
		elseif cart.c == c and r >= cart.r and r < cart.r + cart.len then
			return index
		end
	end
end

-- Slides a cart by `by` cells along its length when the way is clear.
function Caravan:Slide(index, by)
	local cart = self.carts[index]
	if not cart or by == 0 then return false end
	local step = by > 0 and 1 or -1
	for k = 1, math.abs(by) do
		local r, c
		if cart.across then
			r, c = cart.r, step > 0 and cart.c + cart.len - 1 + k or cart.c - k
		else
			r, c = step > 0 and cart.r + cart.len - 1 + k or cart.r - k, cart.c
		end
		if r < 1 or c < 1 or r > N or c > N or self:At(r, c) then return false end
	end
	self.history[#self.history + 1] = { index, cart.r, cart.c, self.moves, self.lastMove }
	if cart.across then cart.c = cart.c + by else cart.r = cart.r + by end
	-- One slide is one move; nudging the same cart the same way again
	-- with the keys does not count twice.
	local mark = index .. (step > 0 and "+" or "-")
	if self.lastMove ~= mark then
		self.moves = self.moves + 1
		self.host.Score(self.moves)
	end
	self.lastMove = mark
	self.host.Sound("turn")
	self:Draw()
	local kodo = self.carts[1]
	if index == 1 and kodo.c + kodo.len - 1 == N then
		self.fx:Sparks(N * CELL, TOP + (GATE_ROW - 0.5) * CELL, self.host.Color("gold"), 14, 150)
		self.fx:Burst(N * CELL, TOP + (GATE_ROW - 0.5) * CELL, self.host.Color("gold"), CELL * 2, 0.5)
		self.host.Sound("point")
		self.host.Over(true)
	end
	return true
end

function Caravan:Undo()
	local last = table.remove(self.history)
	if not last then return end
	local cart = self.carts[last[1]]
	cart.r, cart.c = last[2], last[3]
	self.moves, self.lastMove = last[4], last[5]
	self.sel = last[1]
	self.host.Score(self.moves)
	self:Draw()
end

function Caravan:Restart()
	local entry = self:Entry()
	self.carts = Parse(entry and entry[1] or "")
	self.moves, self.history, self.sel, self.lastMove = 0, {}, 1, nil
	self.host.Score(0)
	self:Draw()
end

function Caravan:Key(key)
	local d = DIRS[key]
	if d then
		local cart = self.carts[self.sel or 1]
		if cart then
			local by = cart.across and d[1] or d[2]
			if by ~= 0 then self:Slide(self.sel or 1, by) end
		end
		return true
	end
	if key == "SPACE" or key == "TAB" then
		self.sel = (self.sel or 0) % #self.carts + 1
		self.lastMove = nil
		self:Draw()
		return true
	end
	if key == "U" or key == "BACKSPACE" then
		self:Undo()
		return true
	end
	if key == "R" then
		self:Restart()
		return true
	end
	return false
end

-- A click on a cart picks it; a click in its row or column slides it there.
function Caravan:Press(button, x, y)
	if button ~= "LeftButton" or not (x and y) then return end
	local c, r = self.grid:CellAt(x, y, 0, TOP)
	if not c and self.sel == 1 and y >= TOP + (GATE_ROW - 1) * CELL and y < TOP + GATE_ROW * CELL and x >= N * CELL then
		c, r = N, GATE_ROW
	end
	if not c then return end
	local index = self:At(r, c)
	if index and index ~= self.sel then
		self.sel = index
		self.lastMove = nil
		self:Draw()
		return
	end
	local cart = self.carts[self.sel or 0]
	if not cart then return end
	local by
	if cart.across and r == cart.r then
		if c < cart.c then by = c - cart.c elseif c >= cart.c + cart.len then by = c - (cart.c + cart.len - 1) end
	elseif not cart.across and c == cart.c then
		if r < cart.r then by = r - cart.r elseif r >= cart.r + cart.len then by = r - (cart.r + cart.len - 1) end
	end
	if by then
		self.lastMove = nil
		self:Slide(self.sel, by)
	end
end

function Caravan:Update(dt)
	self.fx:Update(dt)
end

function Caravan:Summary()
	if not self.moves then return nil end
	local entry = self:Entry()
	return L["Moves %d, fewest %d"]:format(self.moves, entry and entry[2] or 0)
end

function Caravan:Draw()
	local area, grid = self.host.area, self.grid
	local color = self.host.Color
	local bronze = E.tokens.palette.bronze
	for r = 1, N do
		for c = 1, N do grid:Paint(c, r, bronze, (r + c) % 2 == 0 and 0.16 or 0.12) end
	end
	B.Tile(self.gate, color("gold"), 0.8)
	for index, cart in ipairs(self.carts or {}) do
		local view = self.views[index]
		if not view then
			view = { body = B.Sprite(area, CELL, CELL, "ARTWORK"), icon = B.Sprite(area, CELL - 24, CELL - 24, "OVERLAY") }
			E:SetClientFile(view.icon, KODO, "Interface\\Icons\\INV_Misc_QuestionMark")
			E:TrimIcon(view.icon)
			self.views[index] = view
		end
		local w = cart.across and cart.len * CELL or CELL
		local h = cart.across and CELL or cart.len * CELL
		view.body:SetSize(w - 8, h - 8)
		local x, y = (cart.c - 1) * CELL + 4, TOP + (cart.r - 1) * CELL + 4
		B.Place(view.body, x, y, area)
		if index == 1 then
			B.Tile(view.body, color("gold"), 1)
			view.icon:Show()
			B.Place(view.icon, x + (w - 8) / 2 - (CELL - 24) / 2, y + (h - 8) / 2 - (CELL - 24) / 2, area)
		else
			B.Tile(view.body, bronze, 0.55 + (index % 3) * 0.12)
			view.icon:Hide()
		end
		view.body:Show()
	end
	for index = #(self.carts or {}) + 1, #self.views do
		self.views[index].body:Hide()
		self.views[index].icon:Hide()
	end
	local cart = self.carts and self.carts[self.sel or 0]
	self.picked:SetShown(cart ~= nil)
	if cart then
		local w = cart.across and cart.len * CELL or CELL
		local h = cart.across and CELL or cart.len * CELL
		self.picked:SetSize(w, h)
		B.Art(self.picked, "Ring", color("accent"), 0.9)
		B.Place(self.picked, (cart.c - 1) * CELL, TOP + (cart.r - 1) * CELL, area)
	end
	local entry = self:Entry()
	self.tally:SetText(E:Plural(self.moves or 0, "%d move", "%d moves"):format(self.moves or 0))
	self.prompt:SetText(L["Fewest moves: %d"]:format(entry and entry[2] or 0))
end

M:RegisterGame({
	key = "caravan", order = 85, group = "puzzle", theme = "wood",
	title = "Caravan Jam", desc = "Slide the carts until the kodo cart can leave the market.",
	controls = Key("Click a cart, then where it goes. Arrow keys slide it, Space picks the next. U: undo. R: start over."),
	icon = KODO,
	modes = MODES, lower = true, unit = "moves",
	actions = { { key = "U", label = "Undo" }, { key = "R", label = "Start over" } },
	width = WIDTH, height = HEIGHT,
	New = New,
})
