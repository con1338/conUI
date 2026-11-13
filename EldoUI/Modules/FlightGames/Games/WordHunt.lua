-- EldoUI Flight Games: Word Hunt. Words of the game's world hide in a
-- grid of letters: across, down or slanting, and some backwards. Click the
-- first letter of a word and then its last (or use the arrow keys and
-- Space). Find them all as fast as you can; English and Danish lists.
-- Written from scratch for EldoUI; the Danish list keeps the game's own
-- names of places in English, the way Danish players say them.
local _, E = ...
local M = E.FlightGames
local Key = E.Key
local L = E.L
local B = M.Board

local TOP = 30
local SIDE = 168                -- the word list beside the grid
local MODES = {
	{ key = "en", title = "English", lang = "en", size = 10, cell = 34, words = 8 },
	{ key = "enbig", title = "English, large", lang = "en", size = 13, cell = 30, words = 11 },
	{ key = "da", title = "Danish", lang = "da", size = 10, cell = 34, words = 8 },
	{ key = "dabig", title = "Danish, large", lang = "da", size = 13, cell = 30, words = 11 },
}
local WORDS = {
	en = "STORMWIND IRONFORGE DARNASSUS ORGRIMMAR UNDERCITY GADGETZAN ASHENVALE DUSKWOOD WESTFALL REDRIDGE "
		.. "TANARIS FERALAS DARKSHORE TELDRASSIL MULGORE DUROTAR BARRENS SILITHUS AZSHARA FELWOOD BADLANDS "
		.. "ELWYNN MOONGLADE DESOLACE WARRIOR PALADIN HUNTER ROGUE PRIEST SHAMAN MAGE WARLOCK DRUID MURLOC "
		.. "KOBOLD GNOLL HARPY KODO RAPTOR DRAGON WHELP OGRE TROLL CENTAUR QUILBOAR TAUREN GNOME DWARF UNDEAD "
		.. "NAGA SATYR FURBOLG TROGG BASILISK SCORPID WYVERN GRYPHON SWORD SHIELD MANA RAGE ENERGY TOTEM POTION "
		.. "ELIXIR RUNE GOLD COPPER SILVER TALENT QUEST DUNGEON RAID LOOT AUCTION TAVERN DEADMINES STOCKADE "
		.. "GNOMEREGAN MARAUDON STRATHOLME ULDAMAN RAGEFIRE HEARTH FLIGHT ZEPPELIN",
	da = "STORMWIND IRONFORGE DARNASSUS ORGRIMMAR UNDERCITY TANARIS FERALAS MULGORE DUROTAR BARRENS AZSHARA "
		.. "FELWOOD DUSKWOOD WESTFALL SVÆRD SKJOLD HJELM STAV ØKSE BUE PIL GULD SØLV KOBBER DRAGE ULV BJØRN "
		.. "EDDERKOP ROTTE SLANGE ØRN GRIF HEST VILDSVIN FLAGERMUS SKORPION KRO KISTE TASKE RUNE TOTEM ELIKSIR "
		.. "SKAT SKOV BJERG HULE BRO TÅRN BÅD SKIB HAVN ØRKEN SUMP STRAND MØLLE SMEDJE VAGT RIDDER HEKS "
		.. "TROLDMAND KONGE DRONNING BYTTE FÆSTNING GRAV KLOSTER KRYPT TEMPEL LANTERNE",
}
-- The filler letters: the whole alphabet, common letters more often, so
-- no letter gives a word away by being rare.
local ALPHABET = {
	en = "EEEEEAAAARRRIIIOOOTTTNNNSSSLLLCCUUDDPPMMHHGGBBFFYYWWKKVXZJQ",
	da = "EEEEERRRRNNNTTTAAADDDIIISSSLLLGGOOKKMMVVUUBBFFHHPPJYÆÆØØÅÅCWZQX",
}
local DIRS8 = { { 1, 0 }, { 0, 1 }, { 1, 1 }, { 1, -1 }, { -1, 0 }, { 0, -1 }, { -1, -1 }, { -1, 1 } }
local KEY_DIRS = { UP = { 0, -1 }, W = { 0, -1 }, DOWN = { 0, 1 }, S = { 0, 1 }, LEFT = { -1, 0 }, A = { -1, 0 }, RIGHT = { 1, 0 }, D = { 1, 0 } }
local CHAR = "[%z\1-\127\194-\244][\128-\191]*"

local Hunt = {}
Hunt.__index = Hunt
-- What a saved grid keeps.
Hunt.saveKeys = { "letters", "words", "found", "time", "first", "cx", "cy" }

local function ModeOf(mode)
	return mode and mode.lang and mode or MODES[1]
end

-- A word as a list of letters (Danish letters are two bytes).
local function Chars(text)
	local out = {}
	for ch in text:gmatch(CHAR) do out[#out + 1] = ch end
	return out
end
Hunt.Chars = Chars

local function New(host, mode)
	mode = ModeOf(mode)
	local game = setmetatable({ host = host, mode = mode }, Hunt)
	local area, n, cell = host.area, mode.size, mode.cell
	game.grid = B.Grid(area, n, n, cell, { gap = 2 })
	game.grid.frame:SetPoint("TOPLEFT", area, "TOPLEFT", 0, -TOP)
	game.labels = {}
	for i = 1, n * n do
		local x, y = (i - 1) % n, math.floor((i - 1) / n)
		local label = B.Label(game.grid.frame, cell >= 34 and E.tokens.size.section or E.tokens.size.body, "body")
		label:SetPoint("CENTER", game.grid.frame, "TOPLEFT", x * cell + cell / 2, -(y * cell + cell / 2))
		game.labels[i] = label
	end
	game.cursor = B.Sprite(game.grid.frame, cell, cell, "OVERLAY")
	game.cursor:SetDrawLayer("OVERLAY", 7)
	game.list = {}
	for i = 1, MODES[#MODES].words do
		local line = B.Label(area, E.tokens.size.body, "body", "LEFT")
		line:SetPoint("TOPLEFT", area, "TOPLEFT", n * cell + 18, -(TOP + 6 + (i - 1) * 24))
		game.list[i] = line
	end
	game.tally = B.Label(area, E.tokens.size.cardTitle, "body", "LEFT")
	game.tally:SetPoint("TOPLEFT", area, "TOPLEFT", 2, -6)
	game.prompt = B.Label(area, E.tokens.size.small, "secondary", "RIGHT")
	game.prompt:SetPoint("TOPRIGHT", area, "TOPLEFT", n * cell + SIDE - 2, -9)
	game.fx = B.Effects(area)
	return game
end

function Hunt:Index(x, y) return (y - 1) * self.mode.size + x end

-- Tries to lay a word in the grid; true when it fits.
function Hunt:Lay(word)
	local n = self.mode.size
	local chars = Chars(word)
	for _ = 1, 200 do
		local d = DIRS8[self.host.Random(1, #DIRS8)]
		local x, y = self.host.Random(1, n), self.host.Random(1, n)
		local ex, ey = x + d[1] * (#chars - 1), y + d[2] * (#chars - 1)
		if ex >= 1 and ey >= 1 and ex <= n and ey <= n then
			local fits = true
			for k, ch in ipairs(chars) do
				local at = self.letters[self:Index(x + d[1] * (k - 1), y + d[2] * (k - 1))]
				if at ~= "" and at ~= ch then fits = false break end
			end
			if fits then
				for k, ch in ipairs(chars) do self.letters[self:Index(x + d[1] * (k - 1), y + d[2] * (k - 1))] = ch end
				return true
			end
		end
	end
	return false
end

function Hunt:Start()
	local mode, n = self.mode, self.mode.size
	self.letters = {}
	for i = 1, n * n do self.letters[i] = "" end
	local pool = {}
	for word in WORDS[mode.lang]:gmatch("%S+") do
		local length = #Chars(word)
		if length >= 3 and length <= n then pool[#pool + 1] = word end
	end
	self.words, self.found = {}, {}
	while #self.words < mode.words and #pool > 0 do
		local word = table.remove(pool, self.host.Random(1, #pool))
		if self:Lay(word) then
			self.words[#self.words + 1] = word
			self.found[#self.words] = false
		end
	end
	table.sort(self.words)
	local alphabet = Chars(ALPHABET[mode.lang])
	for i = 1, n * n do
		if self.letters[i] == "" then self.letters[i] = alphabet[self.host.Random(1, #alphabet)] end
	end
	self.time, self.first = 0, nil
	self.cx, self.cy = math.ceil(n / 2), math.ceil(n / 2)
	self.fx:Clear()
	self.host.Score(0)
	self:Draw()
end

function Hunt:Loaded()
	self.shownTime = nil
end

-- The cells from one cell to another in a straight line, or nil.
function Hunt:Line(a, b)
	local n = self.mode.size
	local ax, ay = (a - 1) % n + 1, math.floor((a - 1) / n) + 1
	local bx, by = (b - 1) % n + 1, math.floor((b - 1) / n) + 1
	local dx, dy = bx - ax, by - ay
	if not (dx == 0 or dy == 0 or math.abs(dx) == math.abs(dy)) then return nil end
	local steps = math.max(math.abs(dx), math.abs(dy))
	local sx, sy = steps > 0 and dx / steps or 0, steps > 0 and dy / steps or 0
	local out = {}
	for k = 0, steps do out[#out + 1] = self:Index(ax + sx * k, ay + sy * k) end
	return out
end

-- The second letter of a pick: a word along the line, either way round.
function Hunt:Mark(a, b)
	local line = self:Line(a, b)
	if not line or #line < 2 then return false end
	local forward, backward = {}, {}
	for k, i in ipairs(line) do
		forward[k] = self.letters[i]
		backward[#line - k + 1] = self.letters[i]
	end
	local f, r = table.concat(forward), table.concat(backward)
	for k, word in ipairs(self.words) do
		if not self.found[k] and (word == f or word == r) then
			self.found[k] = line
			local n, cell = self.mode.size, self.mode.cell
			local tint = self.host.Palette()[(k - 1) % 7 + 1]
			for _, i in ipairs(line) do
				self.fx:Sparks(((i - 1) % n + 0.5) * cell, TOP + (math.floor((i - 1) / n) + 0.5) * cell, tint, 3, 70)
			end
			self.host.Sound("point")
			self:Draw()
			if self:All() then
				self.host.Over(true)
			end
			return true
		end
	end
	return false
end

function Hunt:All()
	for k = 1, #self.words do
		if not self.found[k] then return false end
	end
	return true
end

function Hunt:Pick(i)
	if not self.first then
		self.first = i
		self.host.Sound("turn")
	elseif self.first == i then
		self.first = nil
	else
		local first = self.first
		self.first = nil
		if not self:Mark(first, i) then
			self.fx:Burst(((i - 1) % self.mode.size + 0.5) * self.mode.cell, TOP + (math.floor((i - 1) / self.mode.size) + 0.5) * self.mode.cell,
				self.host.Color("secondary"), self.mode.cell * 1.4, 0.3)
		end
	end
	self:Draw()
end

function Hunt:Press(button, x, y)
	if button ~= "LeftButton" or not (x and y) then return end
	local cx, cy = self.grid:CellAt(x, y, 0, TOP)
	if not cx then return end
	self.cx, self.cy = cx, cy
	self:Pick(self:Index(cx, cy))
end

function Hunt:Key(key)
	local d = KEY_DIRS[key]
	local n = self.mode.size
	if d then
		self.cx = math.max(1, math.min(n, self.cx + d[1]))
		self.cy = math.max(1, math.min(n, self.cy + d[2]))
		self:Draw()
		return true
	end
	if key == "SPACE" or key == "ENTER" then
		self:Pick(self:Index(self.cx, self.cy))
		return true
	end
	return false
end

function Hunt:Update(dt)
	self.fx:Update(dt)
	self.time = (self.time or 0) + dt
	local whole = math.floor(self.time)
	if whole ~= self.shownTime then
		self.shownTime = whole
		self.host.Score(whole)
	end
	-- While a first letter is picked, the line to the pointer shows.
	if self.first then
		local x, y = self.host.Cursor()
		local cx, cy = self.grid:CellAt(x or -1, y or -1, 0, TOP)
		local at = cx and self:Index(cx, cy)
		if at and at ~= self.hover then
			self.hover = at
			self:Draw()
		end
	end
end

function Hunt:Summary()
	if not self.words then return nil end
	local count = 0
	for k = 1, #self.words do
		if self.found[k] then count = count + 1 end
	end
	return L["Found %d of %d"]:format(count, #self.words)
end

function Hunt:Draw()
	local n, cell = self.mode.size, self.mode.cell
	local palette, color = self.host.Palette(), self.host.Color
	local tints = {}
	for k, line in ipairs(self.found or {}) do
		if type(line) == "table" then
			for _, i in ipairs(line) do tints[i] = palette[(k - 1) % 7 + 1] end
		end
	end
	local preview = {}
	if self.first then
		for _, i in ipairs(self:Line(self.first, self.hover or self.first) or { self.first }) do preview[i] = true end
	end
	local paper = E.tokens.palette.bronze
	for y = 1, n do
		for x = 1, n do
			local i = self:Index(x, y)
			local tint = tints[i]
			if preview[i] then
				self.grid:Paint(x, y, color("accent"), 0.55)
			elseif tint then
				self.grid:Paint(x, y, tint, 0.6)
			else
				self.grid:Paint(x, y, paper, 0.22)
			end
			self.labels[i]:SetText(self.letters and self.letters[i] or "")
		end
	end
	B.Art(self.cursor, "Ring", color("accent"), 0.9)
	B.Place(self.cursor, (self.cx - 1) * cell, (self.cy - 1) * cell, self.grid.frame)
	local found = 0
	for k, line in ipairs(self.list) do
		local word = self.words and self.words[k]
		line:SetShown(word ~= nil)
		if word then
			local done = self.found[k]
			if done then found = found + 1 end
			local tint = done and palette[(k - 1) % 7 + 1] or color("body")
			line:SetText(word)
			line:SetTextColor(tint[1], tint[2], tint[3], done and 0.75 or 1)
		end
	end
	self.tally:SetText(L["Found %d of %d"]:format(found, self.words and #self.words or 0))
	self.prompt:SetText(self.first and L["Now click the last letter."] or L["Click a word's first letter."])
end

M:RegisterGame({
	key = "wordhunt", order = 87, group = "puzzle",
	title = "Word Hunt", desc = "Find the hidden words of the game's world in the letters.",
	controls = Key("Click the first and the last letter of a word. Arrow keys and Space work too. P: pause."),
	icon = "Interface\\Icons\\INV_Misc_Book_09",
	modes = MODES, lower = true, unit = "seconds",
	Size = function(mode) mode = ModeOf(mode) return mode.size * mode.cell + SIDE, TOP + mode.size * mode.cell end,
	New = New,
})
