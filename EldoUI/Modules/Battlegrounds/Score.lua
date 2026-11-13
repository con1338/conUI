-- Battleground Timers: expected winner, match time left, flag back.
--
-- Source: the top-center widget set (C_UIWidgetManager
-- .GetTopCenterWidgetSetID / GetAllWidgetsBySetID), walked by widget type,
-- never by hard-coded widget IDs:
--   DoubleStatusBar  left = Alliance, right = Horde: value and max
--   IconAndText      "<value>/<max>" in the text: one per side, in widget
--                    order (Alliance first); "M:SS" in the text: a clock
-- Clocks tick without UPDATE_UI_WIDGET, so the widgets are also read once
-- a second while in a battleground.
--
-- Expected winner (maps with a score race): per side the last gain and
-- the time between gains give points per second; a gain far above the
-- last one (a flag or cart capture) moves the score but not the rate; a
-- drop starts that side over; a side with no gain for a long while holds
-- no bases. The side that reaches the limit first wins; the loser's final
-- score is its score at that moment. The bar shows nothing when it can't
-- be worked out. The score is public match information Blizzard shows at
-- the top of the screen; secret values hide the bar. The scoreboard
-- (C_PvP score info) is never read during a match.
-- Time left: a clock widget, else the map's time limit (MapData) minus
-- C_PvP.GetActiveMatchDuration. Hidden when neither is known.
-- Flag back: a side's capture count going up starts the map's flag
-- respawn time (MapData, Warsong Gulch). No chat text is read, so every
-- client language works.
local _, E = ...
local L = E.L
local M = E:GetModule("Battlegrounds")
local Read, IsSecret = M.Read, M.IsSecret

local S = M:AddPart({ name = "score" })
M.Score = S

local POLL = 1             -- seconds between widget reads in a battleground
local JUMP_FACTOR = 3      -- a gain this many times the last one is a jump
local JUMP_MIN = 30        -- ... and at least this many points
local STALE_TICKS = 3      -- no gain for this many tick lengths: no bases
local STALE_MIN = 30       -- ... and at least this many seconds
local END_SLACK = 2        -- seconds the predicted end may move before the bar restarts
local CLOCK_SLACK = 2

local sides = {}           -- "alliance"/"horde" -> { value, t, rate, gain, dt, seeded }
local flags = {}           -- "alliance"/"horde" -> capture count
local ticker

local function WidgetType(name)
	local enum = Enum and Enum.UIWidgetVisualizationType
	return enum and enum[name]
end

local function Number(value)
	if IsSecret(value) or type(value) ~= "number" then return nil end
	return value
end

-- true when a widget is shown, false when hidden, nil when unreadable.
local function Shown(info)
	local state = info.shownState
	if IsSecret(state) then return nil end
	return state ~= 0
end

---------------------------------------------------------------------------
-- Reading the widgets
---------------------------------------------------------------------------
-- { double = { alliance, horde, max }, pairs = { { value, max }, ... },
--   clock = seconds, secret = true when a score value was secret }
-- The answer and its parts are the same tables every time (filled again
-- on each read), so a match full of widget updates builds no new ones.
local readResult, readDouble, readTexts, textPool = { pairs = {} }, {}, {}, {}

local function ByOrder(a, b)
	if a.order ~= b.order then return a.order < b.order end
	return a.id < b.id
end

function S:ReadWidgets()
	local api = C_UIWidgetManager
	local result = readResult
	result.double, result.clock, result.secret = nil, nil, nil
	wipe(readTexts)
	result.pairs = readTexts
	self.reads = (self.reads or 0) + 1
	local setID = Read(api and api.GetTopCenterWidgetSetID)
	local list = setID and Read(api.GetAllWidgetsBySetID, setID)
	if type(list) ~= "table" then return result end
	local DOUBLE, TEXT = WidgetType("DoubleStatusBar"), WidgetType("IconAndText")
	local texts = readTexts
	for _, widget in ipairs(list) do
		local id, kind = widget.widgetID, widget.widgetType
		if not IsSecret(id) and not IsSecret(kind) and type(id) == "number" then
			if kind == DOUBLE then
				local info = Read(api.GetDoubleStatusBarWidgetVisualizationInfo, id)
				local shown = type(info) == "table" and Shown(info)
				if shown == nil and type(info) == "table" then
					result.secret = true
				elseif shown then
					local a, h, max = Number(info.leftBarValue), Number(info.rightBarValue), Number(info.leftBarMax)
					if a and h and max and max > 0 then
						if not result.double then
							readDouble.alliance, readDouble.horde, readDouble.max = a, h, max
							result.double = readDouble
						end
					elseif IsSecret(info.leftBarValue) or IsSecret(info.rightBarValue) or IsSecret(info.leftBarMax) then
						result.secret = true
					end
				end
			elseif kind == TEXT then
				local info = Read(api.GetIconAndTextWidgetVisualizationInfo, id)
				local text = type(info) == "table" and info.text
				local shown = type(info) == "table" and Shown(info)
				if IsSecret(text) or (type(info) == "table" and shown == nil) then
					result.secret = true
				elseif type(text) == "string" and shown then
					local value, max = text:match("(%d+)%s*/%s*(%d+)")
					if value then
						local index = #texts + 1
						local entry = textPool[index] or {}
						textPool[index] = entry
						entry.value, entry.max, entry.order, entry.id = tonumber(value), tonumber(max), Number(info.orderIndex) or 0, id
						texts[index] = entry
					else
						local minutes, seconds = text:match("(%d+):(%d%d)")
						if minutes and not result.clock then result.clock = tonumber(minutes) * 60 + tonumber(seconds) end
					end
				end
			end
		end
	end
	table.sort(texts, ByOrder)
	return result
end

-- alliance, horde, max from the widgets, or nil.
local function Scores(read)
	if read.double then return read.double.alliance, read.double.horde, read.double.max end
	local list = read.pairs
	if #list >= 2 and list[1].max == list[2].max and list[1].max > 0 then
		return list[1].value, list[2].value, list[1].max
	end
end

---------------------------------------------------------------------------
-- Expected winner
---------------------------------------------------------------------------
function S:Sample(side, value, now)
	local s = sides[side]
	if not s or value < s.value then
		-- First look, or the score went down: start this side over.
		sides[side] = { value = value, t = now }
		return
	end
	if value == s.value then return end
	local gain = value - s.value
	local dt = now - s.t
	if s.gain and gain > s.gain * JUMP_FACTOR and gain >= JUMP_MIN then
		-- A flag or cart capture: the score moves, the rate stays. It
		-- lands between two ticks, so the next gap is not a whole tick.
		s.value, s.t, s.afterJump = value, now, true
		return
	end
	s.value, s.t = value, now
	if s.afterJump then
		s.afterJump = nil
		return
	end
	if not s.seeded then
		-- The first gain only marks a tick; the time since our first
		-- look is not a whole tick.
		s.seeded, s.gain = true, gain
		return
	end
	if dt > 0 then s.rate, s.gain, s.dt = gain / dt, gain, dt end
end

-- Seconds at which `side` reaches max (absolute GetTime), or nil.
local function EndTime(s, max, now)
	if not (s and s.rate and s.rate > 0) then return nil end
	local quiet = now - s.t
	if s.dt and quiet > math.max(s.dt * STALE_TICKS, STALE_MIN) then return nil end
	local finish = s.t + (max - s.value) / s.rate
	if finish ~= finish or finish == math.huge then return nil end
	return finish
end

-- The loser's score when the winner reaches max.
local function ScoreAt(s, at, max)
	if not s then return 0 end
	local value = s.value
	if s.rate and s.rate > 0 and at > s.t then
		if s.dt and s.dt > 0 and s.gain then
			value = value + math.floor((at - s.t) / s.dt) * s.gain
		else
			value = value + math.floor((at - s.t) * s.rate)
		end
	end
	return math.max(0, math.min(max - 1, value))
end

function S:Predicts()
	local map = M.map
	return map and M.db.predict and (map.predict or (not map.known and self.max and self.max >= 100))
end

function S:UpdatePrediction(now)
	local max = self.max
	if not (self:Predicts() and max) then
		M:Stop("predict")
		return
	end
	local endA = EndTime(sides.alliance, max, now)
	local endH = EndTime(sides.horde, max, now)
	local winner, finish
	if endA and (not endH or endA <= endH) then
		winner, finish = "alliance", endA
	elseif endH then
		winner, finish = "horde", endH
	end
	local seconds = finish and (finish - now)
	if not winner or not seconds or seconds ~= seconds or seconds <= 0 or seconds > 6 * 3600 then
		M:Stop("predict")
		return
	end
	local loser = winner == "alliance" and "horde" or "alliance"
	local final = ScoreAt(sides[loser], finish, max)
	local label = L["%s wins %d-%d"]:format(M:SideName(winner), max, final)
	local current = M:Get("predict")
	if current and current.label == label and M:BarNear("predict", seconds, END_SLACK) then return end
	M:Bar("predict", { kind = winner, side = winner, label = label, duration = seconds, icon = M:FactionIcon(winner),
		tooltip = L["Estimate from the current score: who reaches the limit first, and the final score."] })
end

---------------------------------------------------------------------------
-- Time left and flag back
---------------------------------------------------------------------------
function S:UpdateClock(read)
	local map = M.map
	if not (map and M.db.matchTime) then
		M:Stop("matchtime")
		return
	end
	local left = read.clock
	if not left and map.timeLimit then
		local elapsed = Number(Read(C_PvP.GetActiveMatchDuration))
		if elapsed and elapsed > 0 then left = map.timeLimit - elapsed end
	end
	if not left or left <= 0 then
		M:Stop("matchtime")
		return
	end
	if M:BarNear("matchtime", left, CLOCK_SLACK) then return end
	M:Bar("matchtime", { kind = "other", label = L["Time left"], duration = left,
		tooltip = L["Time left in this match, as the game shows it."] })
end

local SIDES = { "alliance", "horde" }

function S:UpdateFlags(read)
	local map = M.map
	if not (map and map.flags) then return end
	local list = read.pairs
	if #list < 2 then return end
	for index, side in ipairs(SIDES) do
		local value = list[index].value
		local before = flags[side]
		flags[side] = value
		if before and value > before and M.db.flagRespawn and map.flagRespawn then
			M:Bar("flag", { kind = "other", label = L["Flag back"], duration = map.flagRespawn,
				tooltip = L["Time until the flags return after a capture."] })
		end
	end
end

---------------------------------------------------------------------------
-- Update loop
---------------------------------------------------------------------------
function S:Active()
	return M.map ~= nil and not M:StandBack()
end

function S:Update()
	if not self:Active() then return end
	local now = GetTime()
	local read = self:ReadWidgets()
	local a, h, max = Scores(read)
	if read.secret and not a then
		self.max = nil
		wipe(sides)
		M:Stop("predict")
	elseif a then
		if self.max ~= max then wipe(sides) end
		self.max = max
		self:Sample("alliance", a, now)
		self:Sample("horde", h, now)
	end
	self:UpdatePrediction(now)
	self:UpdateClock(read)
	self:UpdateFlags(read)
end

-- Widget events come in bursts (two per tick when both sides hold
-- bases): every event of a frame shares one read on the next frame.
local function UpdateNow()
	if M.map then S:Update() end
end
function S:UpdateSoon()
	E:Debounce("Battlegrounds:score", 0, UpdateNow)
end

local function StopBars()
	M:Stop("predict")
	M:Stop("matchtime")
	M:Stop("flag")
end

function S:Enable()
	M:RegisterEvent("UPDATE_UI_WIDGET", function(_, _, info)
		if not M.map then return end
		local setID = type(info) == "table" and info.widgetSetID
		if not IsSecret(setID) and setID then
			local top = Read(C_UIWidgetManager.GetTopCenterWidgetSetID)
			if top and setID ~= top then return end
		end
		S:UpdateSoon()
	end)
	M:RegisterEvent("UPDATE_ALL_UI_WIDGETS", function() if M.map then S:UpdateSoon() end end)
end

function S:Disable()
	M:UnregisterEvent("UPDATE_UI_WIDGET")
	M:UnregisterEvent("UPDATE_ALL_UI_WIDGETS")
	self:Leave()
end

function S:Enter()
	wipe(sides)
	wipe(flags)
	self.max = nil
	if ticker then ticker:Cancel() end
	ticker = C_Timer.NewTicker(POLL, function() S:Update() end)
	self:Update()
end

function S:Leave()
	if ticker then ticker:Cancel() end
	ticker = nil
	wipe(sides)
	wipe(flags)
	self.max = nil
	StopBars()
end

function S:Refresh()
	if not self:Active() then
		StopBars()
		return
	end
	if not M.db.predict then M:Stop("predict") end
	if not M.db.matchTime then M:Stop("matchtime") end
	if not M.db.flagRespawn then M:Stop("flag") end
	self:Update()
end
