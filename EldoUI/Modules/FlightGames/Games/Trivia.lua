-- EldoUI Flight Games: WoW trivia. A question about the world of the
-- original game and four answers, one of them right. Click an answer or
-- press 1 to 4. A right answer scores 100 points and up to 50 more for a
-- quick one; a wrong answer or the end of the time shows the right one.
-- Rounds of 10 or 25 questions, sudden death (the first miss ends the run)
-- and a daily round that is the same for everyone on the same date. No
-- question comes back before the whole bank has been asked.
-- Written from scratch for EldoUI; the questions are in TriviaData.lua.
local _, E = ...
local M = E.FlightGames
local Key = E.Key
local L = E.L
local B = M.Board

local WIDTH, HEIGHT = 560, 360
local LIMIT = 20              -- seconds per question at normal pace
local RIGHT_WAIT, WRONG_WAIT = 1.1, 2.2
local BOX_W, BOX_H, GAP = 268, 74, 12
local BOX_TOP = 150
local MODES = {
	{ key = "ten", title = "10 questions", count = 10 },
	{ key = "long", title = "25 questions", count = 25 },
	{ key = "sudden", title = "Sudden death", sudden = true },
	{ key = "daily", title = "Daily round", count = 10, daily = true },
}
local KEYS = { ["1"] = 1, ["2"] = 2, ["3"] = 3, ["4"] = 4, NUMPAD1 = 1, NUMPAD2 = 2, NUMPAD3 = 3, NUMPAD4 = 4 }

local Trivia = {}
Trivia.__index = Trivia

local function ModeOf(mode)
	return mode and mode.key and mode or MODES[1]
end

-- A game name stays as it is; EldoUI's own answer words are translated.
local function Say(value)
	local D = M.TriviaData
	if D.say[value] then return L[value] end
	return tostring(value)
end

-- The text of a question in the chosen language.
local function Question(entry)
	local text = L[entry.ask]
	if entry.arg ~= nil then text = text:format(Say(entry.arg)) end
	return text
end

-- A small seeded random source, for the daily round.
local function Seeded(seed)
	local state = seed % 2147483647
	if state <= 0 then state = state + 2147483646 end
	return function(n)
		state = (state * 16807) % 2147483647
		return (state % n) + 1
	end
end

local function Today()
	local stamp = date and date("%Y%m%d")
	return tonumber(stamp) or 0
end

-- The daily round of a date: its question ids and the random source that
-- deals their answers, stepped past the first `asked` questions.
local function Daily(day, count, asked)
	local random = Seeded(day)
	local bank = M.TriviaData:Build()
	local order = {}
	for i = 1, #bank do order[i] = i end
	for i = #order, 2, -1 do
		local j = random(i)
		order[i], order[j] = order[j], order[i]
	end
	local list, ids = {}, {}
	for i = 1, count do
		list[i], ids[i] = bank[order[i]], order[i]
	end
	for i = 1, asked or 0 do
		if list[i] then M.TriviaData:Answers(list[i], random) end
	end
	return list, ids, random
end

-- The day the daily round was last played to its end, and how it went.
local function DailyRecord()
	local store = E:GetGlobal("FlightGames")
	if type(store) ~= "table" then return nil end
	if type(store.trivia) ~= "table" then store.trivia = {} end
	return store.trivia
end

-- One deck for every round: each question once before any comes back.
local deck = { order = nil, at = 0 }
local function Draw(random)
	local bank = M.TriviaData:Build()
	if not deck.order or deck.at >= #deck.order then
		local order = {}
		for i = 1, #bank do order[i] = i end
		for i = #order, 2, -1 do
			local j = random(i)
			order[i], order[j] = order[j], order[i]
		end
		deck.order, deck.at = order, 0
	end
	deck.at = deck.at + 1
	local id = deck.order[deck.at]
	return bank[id], id
end
M.TriviaDeck = deck

local function New(host, mode)
	mode = ModeOf(mode)
	local game = setmetatable({ host = host, mode = mode, boxes = {} }, Trivia)
	local area = host.area
	game.category = B.Label(area, E.tokens.size.small, "dim", "LEFT")
	game.category:SetPoint("TOPLEFT", area, "TOPLEFT", 12, -10)
	game.progress = B.Label(area, E.tokens.size.small, "dim", "RIGHT")
	game.progress:SetPoint("TOPRIGHT", area, "TOPRIGHT", -12, -10)
	game.track = B.Sprite(area, WIDTH - 24, 6, "BORDER")
	B.Place(game.track, 12, 30, area)
	game.bar = B.Sprite(area, WIDTH - 24, 6, "ARTWORK")
	B.Place(game.bar, 12, 30, area)
	game.question = B.Label(area, E.tokens.size.cardTitle, "title")
	game.question:SetWidth(WIDTH - 48)
	game.question:SetPoint("TOP", area, "TOPLEFT", WIDTH / 2, -54)
	for i = 1, 4 do
		local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
		local x = (WIDTH - BOX_W * 2 - GAP) / 2 + col * (BOX_W + GAP)
		local y = BOX_TOP + row * (BOX_H + GAP)
		local box = { x = x, y = y }
		box.fill = B.Slab(area, BOX_W, BOX_H, "BORDER")
		box.fill:Place(x, y)
		box.number = B.Label(area, E.tokens.size.small, "dim", "LEFT")
		box.number:SetPoint("TOPLEFT", area, "TOPLEFT", x + 8, -(y + 6))
		box.number:SetText(i)
		box.text = B.Label(area, E.tokens.size.body, "body")
		box.text:SetWidth(BOX_W - 36)
		box.text:SetPoint("CENTER", area, "TOPLEFT", x + BOX_W / 2 + 6, -(y + BOX_H / 2))
		game.boxes[i] = box
	end
	game.note = B.Label(area, E.tokens.size.body, "body")
	game.note:SetWidth(WIDTH - 24)
	game.note:SetPoint("BOTTOM", area, "TOPLEFT", WIDTH / 2, -(HEIGHT - 8))
	return game
end

function Trivia:Start()
	local mode = self.mode
	self.random = self.host.Random
	self.list, self.ids, self.day = nil, nil, nil
	if mode.daily then
		-- The same ten questions, in the same order with the same answers,
		-- for every player on a date, once a day.
		local record = DailyRecord()
		if record and record.day == Today() then
			self.index, self.right, self.score = 0, 0, 0
			self.entry, self.entryId, self.phase = nil, nil, "played"
			self.host.Score(0)
			self:Draw()
			return
		end
		self.list, self.ids, self.random = Daily(Today(), mode.count, 0)
		self.day = Today()
	end
	self.index, self.right, self.score = 0, 0, 0
	self.host.Score(0)
	self:Next()
end

function Trivia:Limit()
	return LIMIT / math.max(0.5, self.host.Pace())
end

function Trivia:Next()
	self.index = self.index + 1
	local entry, id
	if self.list then
		entry, id = self.list[self.index], self.ids[self.index]
	else
		entry, id = Draw(self.host.Random)
	end
	self.entry, self.entryId = entry, id
	self.answers, self.at = M.TriviaData:Answers(entry, self.random)
	self.picked = nil
	self.phase = "ask"
	self.left = self:Limit()
	self:Draw()
end

-- The player's answer (nil when the time ran out).
function Trivia:Answer(choice)
	if self.phase ~= "ask" then return end
	self.picked = choice or 0
	self.phase = "show"
	if choice == self.at then
		self.right = self.right + 1
		local gain = 100 + math.floor(50 * math.max(0, self.left) / self:Limit() + 0.5)
		self.score = self.score + gain
		self.gain = gain
		self.host.Score(self.score)
		self.host.Sound("point")
		self.wait = RIGHT_WAIT
	else
		self.gain = nil
		self.host.Sound("turn")
		self.wait = WRONG_WAIT
	end
	self:Draw()
end

function Trivia:Done()
	if self.mode.sudden then return self.picked ~= self.at end
	return self.index >= (self.mode.count or 10)
end

function Trivia:Advance()
	if self.phase ~= "show" then return end
	if self:Done() then
		self.phase = "done"
		local record = self.mode.daily and DailyRecord()
		if record then record.day, record.right = self.day, self.right end
		self:Draw()
		self.host.Over(not self.mode.sudden)
		return
	end
	self:Next()
end

function Trivia:Update(dt)
	if self.phase == "ask" then
		self.left = self.left - dt
		if self.left <= 0 then
			self.left = 0
			self:Answer(nil)
		else
			self:DrawTimer()
		end
	elseif self.phase == "show" then
		self.wait = self.wait - dt
		if self.wait <= 0 then self:Advance() end
	end
end

function Trivia:Key(key)
	local choice = KEYS[key]
	if choice then
		self:Answer(choice)
		return true
	end
	if (key == "SPACE" or key == "ENTER") and self.phase == "show" then
		self:Advance()
		return true
	end
	return false
end

function Trivia:BoxAt(x, y)
	for i, box in ipairs(self.boxes) do
		if x >= box.x and x <= box.x + BOX_W and y >= box.y and y <= box.y + BOX_H then return i end
	end
end

function Trivia:Press(button, x, y)
	if button ~= "LeftButton" then return end
	if self.phase == "show" then
		self:Advance()
		return
	end
	local choice = x and y and self:BoxAt(x, y)
	if choice then self:Answer(choice) end
end

-- "7 of 10 right", for the end of the round.
function Trivia:Summary()
	if not self.index or self.index == 0 then return nil end
	return L["%d of %d right"]:format(self.right or 0, self.index)
end

function Trivia:DrawTimer()
	local share = math.max(0, math.min(1, (self.left or 0) / self:Limit()))
	self.bar:SetWidth(math.max(1, (WIDTH - 24) * share))
	local color = share > 0.5 and self.host.Color("accent") or (share > 0.2 and self.host.Color("warn") or self.host.Color("bad"))
	B.Fill(self.bar, color, 0.9)
end

function Trivia:Draw()
	local entry = self.entry
	B.Fill(self.track, self.host.Color("dim"), 0.25)
	if not entry then
		local record = self.phase == "played" and DailyRecord()
		self.question:SetText(record and L["Today's round is played: %d of %d right. A new one comes tomorrow."]:format(
			tonumber(record.right) or 0, self.mode.count or 10) or "")
		self.category:SetText("")
		self.progress:SetText("")
		self.note:SetText("")
		for _, box in ipairs(self.boxes) do
			box.text:SetText("")
			box.fill:Paint(self.host.Color("secondary"), 0.25)
		end
		return
	end
	self.category:SetText(L[entry.set.category])
	if self.mode.sudden then
		self.progress:SetText(L["Question %d"]:format(self.index))
	else
		self.progress:SetText(L["Question %d of %d"]:format(self.index, self.mode.count or 10))
	end
	self.question:SetText(Question(entry))
	local showing = self.phase ~= "ask"
	for i, box in ipairs(self.boxes) do
		box.text:SetText(Say(self.answers[i] or ""))
		local color, alpha = self.host.Color("secondary"), 0.3
		if showing and i == self.at then
			color, alpha = self.host.Color("good"), 0.55
		elseif showing and i == self.picked then
			color, alpha = self.host.Color("bad"), 0.55
		end
		box.fill:Paint(color, alpha)
	end
	if not showing then
		self.note:SetText("")
	elseif self.picked == self.at then
		self.note:SetText(L["Right! +%d"]:format(self.gain or 0))
		self.note:SetTextColor(unpack(self.host.Color("good")))
	else
		local text = self.picked == 0 and L["Time is up. The answer was %s."] or L["Not quite. The answer was %s."]
		self.note:SetText(text:format(Say(entry.right)))
		self.note:SetTextColor(unpack(self.host.Color("bad")))
	end
	self:DrawTimer()
end

-- A saved round: where it is, the question in front of you with its
-- answers in the same order, and the time left.
function Trivia:Save()
	return { index = self.index, right = self.right, score = self.score, entryId = self.entryId,
		answers = { unpack(self.answers or {}) }, at = self.at, left = self.left, phase = self.phase,
		picked = self.picked, gain = self.gain, wait = self.wait, ids = self.ids and { unpack(self.ids) } or nil, day = self.day }
end

function Trivia:Load(data)
	local bank = M.TriviaData:Build()
	local entry = bank[tonumber(data.entryId) or 0]
	local answers = data.answers
	if not entry or type(answers) ~= "table" or #answers ~= 4 or answers[tonumber(data.at) or 0] ~= entry.right then return false end
	-- A daily round belongs to its own day.
	if self.mode.daily and data.day ~= Today() then return false end
	self.random = self.host.Random
	self.list, self.ids, self.day = nil, nil, nil
	if type(data.ids) == "table" then
		self.ids, self.list = {}, {}
		for i, id in ipairs(data.ids) do
			if not bank[id] then return false end
			self.ids[i], self.list[i] = id, bank[id]
		end
		self.day = data.day
		-- The daily answers go on dealing as everyone else's do.
		if self.mode.daily then
			local _, _, random = Daily(self.day, self.mode.count, tonumber(data.index) or 1)
			self.random = random
		end
	end
	self.index, self.right, self.score = tonumber(data.index) or 1, tonumber(data.right) or 0, tonumber(data.score) or 0
	self.entry, self.entryId = entry, data.entryId
	self.answers, self.at = { unpack(answers) }, data.at
	self.left = tonumber(data.left) or self:Limit()
	self.phase = data.phase == "show" and "show" or "ask"
	self.picked, self.gain = data.picked, data.gain
	self.wait = tonumber(data.wait) or 0
	self:Draw()
	return true
end

M:RegisterGame({
	key = "trivia", order = 200, group = "quiz",
	saveVersion = 2, -- Saved question indices belong to this question bank.
	title = "WoW Trivia", desc = "Four answers, one is right: how well do you know Azeroth?",
	controls = Key("Click an answer or press 1 to 4. P: pause."),
	icon = "Interface\\Icons\\INV_Misc_Book_11",
	modes = MODES,
	Size = function() return WIDTH, HEIGHT end,
	New = New,
})
