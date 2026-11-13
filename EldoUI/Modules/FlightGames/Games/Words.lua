-- EldoUI Flight Games: Daily Word. Find the hidden five-letter word in six
-- guesses. After each guess the tiles turn: green is the right letter in
-- the right place, gold is a letter of the word in another place, and gray
-- is a letter the word does not have. One daily word a day, the same for
-- everyone, in US English or in Danish; free play deals a new word every
-- game. Any five letters count as a guess.
-- Written from scratch for EldoUI, with its own word lists (WordsData.lua).
local _, E = ...
local M = E.FlightGames
local Key = E.Key
local L = E.L
local B = M.Board

local LETTERS, GUESSES = 5, 6
local CELL, GAP = 54, 6
local WIDTH, HEIGHT = 470, 548
local GRID_W = LETTERS * CELL + (LETTERS - 1) * GAP
local GRID_X, GRID_Y = (WIDTH - GRID_W) / 2, 10
local KEY_W, KEY_H, KEY_GAP, WIDE_W = 36, 40, 5, 60
local KEYS_Y = GRID_Y + GUESSES * CELL + (GUESSES - 1) * GAP + 40
local FLIP = 0.16           -- one tile turns this long
local SHAKE = 0.4           -- a short guess shakes the row this long
local NEXT_WAIT = 1.6       -- the end shows this long before the game ends

local MODES = {
	{ key = "daily", title = "English", lang = "en", daily = true },
	{ key = "free", title = "English free play", lang = "en" },
	{ key = "dadaily", title = "Danish", lang = "da", daily = true },
	{ key = "dafree", title = "Danish free play", lang = "da" },
}
local ROWS = {
	en = { "QWERTYUIOP", "ASDFGHJKL", "ZXCVBNM" },
	da = { "QWERTYUIOPÅ", "ASDFGHJKLÆØ", "ZXCVBNM" },
}
-- The Danish letters, both ways (string.upper leaves them as they are).
local UPPER = { ["æ"] = "Æ", ["ø"] = "Ø", ["å"] = "Å" }
local LOWER = { ["Æ"] = "æ", ["Ø"] = "ø", ["Å"] = "å" }

local Words = {}
Words.__index = Words

local function ModeOf(mode)
	return mode and mode.lang and mode or MODES[1]
end

-- The letters of a word, one string each (a Danish letter is two bytes).
local function Split(word)
	local out = {}
	for ch in word:gmatch("[%z\1-\127\194-\244][\128-\191]*") do out[#out + 1] = ch end
	return out
end

local function Upper(ch) return UPPER[ch] or ch:upper() end
local function Lower(ch) return LOWER[ch] or ch:lower() end

local function Today()
	local stamp = date and date("%Y%m%d")
	return tonumber(stamp) or 0
end

-- Days counted from 1970 for a date written 20261108, so that two days in
-- a row are one apart across a month's end.
local function DayNumber(stamp)
	local y, m, d = math.floor(stamp / 10000), math.floor(stamp / 100) % 100, stamp % 100
	if m <= 2 then y = y - 1 end
	local era = math.floor(y / 400)
	local yoe = y - era * 400
	local doy = math.floor((153 * (m + (m > 2 and -3 or 9)) + 2) / 5) + d - 1
	local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
	return era * 146097 + doe - 719468
end
Words.DayNumber = DayNumber

-- The word list of a language, read once.
local lists = {}
local function List(lang)
	if not lists[lang] then
		local out = {}
		for word in ((M.WordsData or {})[lang] or ""):gmatch("%S+") do out[#out + 1] = word end
		lists[lang] = out
	end
	return lists[lang]
end

-- The same word for everyone on a day: a hash of the date and the language.
local function DailyIndex(day, lang, count)
	local h = day % 2147483647
	for i = 1, #lang do h = (h * 31 + lang:byte(i)) % 2147483647 end
	for _ = 1, 4 do h = (h * 16807) % 2147483647 end
	return h % count + 1
end

-- How each letter of a guess scores: "good", "near" or "miss". A letter
-- that is in the word fewer times than in the guess is "near" only as many
-- times as the word has it left over.
local function Mark(guess, answer)
	local g, a = Split(guess), Split(answer)
	local marks, left = {}, {}
	for i = 1, LETTERS do
		if g[i] == a[i] then
			marks[i] = "good"
		else
			left[a[i]] = (left[a[i]] or 0) + 1
		end
	end
	for i = 1, LETTERS do
		if not marks[i] then
			if (left[g[i]] or 0) > 0 then
				marks[i] = "near"
				left[g[i]] = left[g[i]] - 1
			else
				marks[i] = "miss"
			end
		end
	end
	return marks
end
Words.Mark = Mark

-- The account's daily results, per language.
local function Stats(lang)
	local store = E:GetGlobal("FlightGames")
	if type(store) ~= "table" then return nil end
	if type(store.words) ~= "table" then store.words = {} end
	local stats = store.words[lang]
	if type(stats) ~= "table" then
		stats = { played = 0, won = 0, streak = 0, best = 0 }
		store.words[lang] = stats
	end
	return stats
end

local function New(host, mode)
	mode = ModeOf(mode)
	local game = setmetatable({ host = host, mode = mode }, Words)
	local area = host.area
	game.tiles = {}
	for r = 1, GUESSES do
		local row = {}
		for c = 1, LETTERS do
			local tile = {}
			tile.x = GRID_X + (c - 1) * (CELL + GAP)
			tile.y = GRID_Y + (r - 1) * (CELL + GAP)
			tile.back = B.Sprite(area, CELL, CELL, "BORDER")
			tile.ring = B.Sprite(area, CELL + 6, CELL + 6, "ARTWORK")
			tile.text = B.Label(area, E.tokens.size.hero, "title")
			row[c] = tile
		end
		game.tiles[r] = row
	end
	game.message = B.Label(area, E.tokens.size.body, "secondary")
	game.message:SetPoint("TOP", area, "TOPLEFT", WIDTH / 2, -(KEYS_Y - 30))
	game.keys = {}
	local rows = ROWS[mode.lang] or ROWS.en
	for r, letters in ipairs(rows) do
		local list = Split(letters)
		local count = #list
		local width = count * KEY_W + (count - 1) * KEY_GAP
		if r == 3 then width = width + 2 * (WIDE_W + KEY_GAP) end
		local x = (WIDTH - width) / 2
		local y = KEYS_Y + (r - 1) * (KEY_H + KEY_GAP)
		local function Add(name, label, w)
			local key = { name = name, x = x, y = y, w = w }
			key.slab = B.Slab(area, w, KEY_H, "BORDER")
			key.slab:Place(x, y)
			key.text = B.Label(area, name:len() > 2 and E.tokens.size.small or E.tokens.size.cardTitle, "body")
			key.text:SetPoint("CENTER", area, "TOPLEFT", x + w / 2, -(y + KEY_H / 2))
			key.text:SetText(label)
			game.keys[#game.keys + 1] = key
			x = x + w + KEY_GAP
		end
		if r == 3 then Add("ENTER", L["Enter"], WIDE_W) end
		for _, ch in ipairs(list) do Add(ch, ch, KEY_W) end
		if r == 3 then Add("BACKSPACE", L["Delete"], WIDE_W) end
	end
	return game
end

function Words:Start()
	local list = List(self.mode.lang)
	self.rows, self.typed, self.done, self.wait = {}, {}, nil, nil
	self.reveal, self.shake, self.bounce = nil, nil, nil
	self.day = Today()
	if #list == 0 then
		self.answer = "-----"
	elseif self.mode.daily then
		self.answer = list[DailyIndex(self.day, self.mode.lang, #list)]
		local stats = Stats(self.mode.lang)
		-- Today's word is already played: show how it went.
		if stats and stats.last == self.day and type(stats.rows) == "table" then
			for i, word in ipairs(stats.rows) do self.rows[i] = word end
			self.done = stats.solved and "won" or "lost"
			self.seen = true
		end
	else
		self.answer = list[self.host.Random(#list)]
	end
	self.host.Score(#self.rows)
	self:Draw()
end

-- A finished daily word is kept in the results, not as a game in progress.
function Words:Save()
	if self.done then return nil end
	return { rows = B.Copy(self.rows), typed = B.Copy(self.typed), answer = self.answer, day = self.day }
end

function Words:Load(data)
	if type(data.answer) ~= "string" or type(data.rows) ~= "table" then return false end
	-- A daily word belongs to its own day.
	if self.mode.daily and data.day ~= Today() then return false end
	self.answer, self.day = data.answer, data.day
	self.rows = B.Copy(data.rows)
	self.typed = type(data.typed) == "table" and B.Copy(data.typed) or {}
	self.done, self.wait, self.reveal, self.shake, self.bounce, self.seen = nil, nil, nil, nil, nil, nil
	self.host.Score(#self.rows)
	-- Saved while the last row turned: that guess counts now.
	local count = #self.rows
	if count > 0 and (self.rows[count] == self.answer or count >= GUESSES) then
		self:Turned()
	else
		self:Draw()
	end
	return true
end

function Words:Busy()
	return self.done or self.reveal or self.wait
end

function Words:Type(ch)
	if self:Busy() or #self.typed >= LETTERS then return end
	self.typed[#self.typed + 1] = Lower(ch)
	self.host.Sound("turn")
	self:Draw()
end

function Words:Erase()
	if self:Busy() or #self.typed == 0 then return end
	table.remove(self.typed)
	self:Draw()
end

function Words:Submit()
	if self:Busy() then return end
	if #self.typed < LETTERS then
		self.shake = { left = SHAKE }
		self.note = L["Five letters, please."]
		self:Draw()
		return
	end
	local guess = table.concat(self.typed)
	self.rows[#self.rows + 1] = guess
	self.typed = {}
	self.note = nil
	self.reveal = { row = #self.rows, t = 0 }
	self.host.Score(#self.rows)
	self:Draw()
end

-- The row has turned: the word is found, the guesses are used up, or the
-- next guess waits.
function Words:Turned()
	local count = #self.rows
	local won = self.rows[count] == self.answer
	if won or count >= GUESSES then
		self.done = won and "won" or "lost"
		self.host.Sound(won and "point" or "over")
		if won then self.bounce = { t = 0, row = count } end
		if self.mode.daily then
			local stats = Stats(self.mode.lang)
			if stats and stats.last ~= self.day then
				local yesterday = type(stats.last) == "number" and DayNumber(stats.last) == DayNumber(self.day) - 1
				stats.played = stats.played + 1
				if won then
					stats.won = stats.won + 1
					stats.streak = (stats.solved and yesterday and stats.streak or 0) + 1
					if stats.streak > stats.best then stats.best = stats.streak end
				else
					stats.streak = 0
				end
				stats.last, stats.solved, stats.rows = self.day, won, B.Copy(self.rows)
			end
		end
		self.wait = { left = NEXT_WAIT }
	end
	self:Draw()
end

function Words:Update(dt)
	if self.reveal then
		self.reveal.t = self.reveal.t + dt
		if self.reveal.t >= FLIP * LETTERS + FLIP then
			self.reveal = nil
			self:Turned()
		else
			self:Draw()
		end
	end
	if self.shake then
		self.shake.left = self.shake.left - dt
		if self.shake.left <= 0 then self.shake = nil end
		self:Draw()
	end
	if self.bounce then
		self.bounce.t = self.bounce.t + dt
		if self.bounce.t > 1.2 then self.bounce = nil end
		self:Draw()
	end
	if self.wait then
		self.wait.left = self.wait.left - dt
		if self.wait.left <= 0 then
			self.wait = nil
			self.host.Over(self.done == "won")
		end
	end
end

local function Letter(key)
	if type(key) ~= "string" then return nil end
	if key:match("^%a$") then return key:upper() end
	if UPPER[key] then return UPPER[key] end
	if LOWER[key] then return key end
	return nil
end

function Words:Key(key)
	if key == "ENTER" or key == "NUMPADENTER" then
		self:Submit()
		return true
	elseif key == "BACKSPACE" or key == "DELETE" then
		self:Erase()
		return true
	end
	local ch = Letter(key)
	if ch then
		-- Danish letters only in the Danish modes.
		if LOWER[ch] and self.mode.lang ~= "da" then return false end
		self:Type(ch)
		return true
	end
	return false
end

function Words:Press(button, x, y)
	if button ~= "LeftButton" or not (x and y) then return end
	for _, key in ipairs(self.keys) do
		if x >= key.x and x <= key.x + key.w and y >= key.y and y <= key.y + KEY_H then
			if key.name == "ENTER" then
				self:Submit()
			elseif key.name == "BACKSPACE" then
				self:Erase()
			else
				self:Type(key.name)
			end
			return
		end
	end
end

-- "Found in 4 guesses" or "The word was CRANE", for the end of the game.
function Words:Summary()
	if not self.done then return nil end
	if self.done == "won" then
		return E:Plural(#self.rows, "Found in %d guess", "Found in %d guesses"):format(#self.rows)
	end
	return L["The word was %s."]:format(self:Shown(self.answer))
end

function Words:Shown(word)
	local out = {}
	for i, ch in ipairs(Split(word or "")) do out[i] = Upper(ch) end
	return table.concat(out)
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------
function Words:Colors()
	local host = self.host
	return {
		good = host.Color("good"),
		near = host.Color("warn"),
		miss = host.Color("dim"),
		empty = host.Color("secondary"),
		accent = host.Color("accent"),
	}
end

function Words:Draw()
	local colors = self:Colors()
	local reveal, shake, bounce = self.reveal, self.shake, self.bounce
	local best = {}  -- the best mark each letter has had, for the keys
	local rank = { miss = 1, near = 2, good = 3 }
	for r = 1, GUESSES do
		local word = self.rows[r]
		local letters = word and Split(word) or (r == #self.rows + 1 and self.typed) or {}
		local marks = word and Mark(word, self.answer) or nil
		local dx = 0
		if shake and r == #self.rows + 1 then
			dx = math.sin(shake.left * 50) * 7 * (shake.left / SHAKE)
		end
		for c = 1, LETTERS do
			local tile = self.tiles[r][c]
			local ch = letters[c]
			local mark = marks and marks[c]
			local height, shown = 1, mark
			if reveal and reveal.row == r then
				local t = reveal.t - (c - 1) * FLIP
				if t < 0 then
					shown = nil
				elseif t < FLIP then
					height = math.abs(math.cos(t / FLIP * math.pi))
					if t < FLIP / 2 then shown = nil end
				end
			end
			if shown and not (reveal and reveal.row == r and not shown) then
				if not best[ch] or rank[shown] > rank[best[ch]] then best[ch] = shown end
			end
			local dy = 0
			if bounce and bounce.row == r then
				local t = bounce.t - (c - 1) * 0.1
				if t > 0 and t < 0.35 then dy = -math.sin(t / 0.35 * math.pi) * 14 end
			end
			local size = math.max(2, CELL * height)
			tile.back:SetSize(CELL, size)
			B.Place(tile.back, tile.x + dx, tile.y + (CELL - size) / 2 + dy)
			if shown then
				B.Tile(tile.back, colors[shown], shown == "miss" and 0.6 or 0.9)
			elseif ch then
				B.Tile(tile.back, colors.empty, 0.3)
			else
				B.Tile(tile.back, colors.empty, 0.12)
			end
			-- The cursor: a ring round the next free tile; typed letters
			-- get a soft ring until the guess turns.
			local cursor = not self.done and not reveal and r == #self.rows + 1 and c == #self.typed + 1
			local typed = not shown and ch ~= nil
			tile.ring:SetShown(cursor or typed)
			if cursor or typed then
				B.Art(tile.ring, "Ring", cursor and colors.accent or colors.empty, cursor and 0.8 or 0.45)
				B.Place(tile.ring, tile.x + dx - 3, tile.y - 3)
			end
			tile.text:ClearAllPoints()
			tile.text:SetPoint("CENTER", self.host.area, "TOPLEFT", tile.x + dx + CELL / 2, -(tile.y + CELL / 2 + dy))
			tile.text:SetText(ch and height > 0.3 and Upper(ch) or "")
			if shown then
				tile.text:SetTextColor(0.06, 0.06, 0.08)
			else
				tile.text:SetTextColor(unpack(self.host.Color("body")))
			end
		end
	end
	for _, key in ipairs(self.keys) do
		local mark = best[Lower(key.name)]
		if mark then
			key.slab:Paint(colors[mark], mark == "miss" and 0.45 or 0.85)
			key.text:SetTextColor(unpack(mark == "miss" and self.host.Color("secondary") or { 0.06, 0.06, 0.08 }))
		else
			key.slab:Paint(colors.empty, 0.3)
			key.text:SetTextColor(unpack(self.host.Color("body")))
		end
	end
	self:DrawMessage()
end

function Words:DrawMessage()
	local text
	local kind = "secondary"
	if self.seen then
		text = L["Today's word is played. A new one comes tomorrow."]
	elseif self.done == "won" then
		text, kind = self:Summary(), "good"
	elseif self.done == "lost" then
		text, kind = self:Summary(), "bad"
	elseif self.note then
		text, kind = self.note, "warn"
	elseif self.mode.daily then
		local stats = Stats(self.mode.lang)
		if stats and stats.played > 0 then
			text = L["Played %d, found %d, run %d"]:format(stats.played, stats.won, stats.streak)
		else
			text = L["Type a word and press Enter."]
		end
	else
		text = L["Type a word and press Enter."]
	end
	self.message:SetText(text)
	self.message:SetTextColor(unpack(self.host.Color(kind)))
end

M:RegisterGame({
	key = "words", order = 210, group = "quiz",
	title = "Daily Word", desc = "Find the hidden five-letter word in six guesses, in English or in Danish.",
	controls = Key("Type letters, Enter guesses, Backspace erases; the keys below work with a click."),
	icon = "Interface\\Icons\\INV_Misc_Book_09",
	modes = MODES, lower = true, unit = "guesses", typing = true,
	Size = function() return WIDTH, HEIGHT end,
	New = New,
})
