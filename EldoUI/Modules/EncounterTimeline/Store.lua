-- Encounter Timeline: the event store and its one driver frame.
--
-- One row per published timer (plan 2.3):
--   key       "dbm:<id>", "bw:<module>:<text>" or "bw:e<eventId>", "pull",
--             "ready", "test:<n>", "sample:<n>"
--   source    dbm | bigwigs | blizzard | test | sample
--   kind      boss | pull | break | ready | other | test
--   text      display text; may be secret: it only ever reaches SetText
--   icon      file id or path (a secret icon became the question mark)
--   spellId   plain positive number or nil
--   start, duration  plain numbers (a secret duration never makes a row)
--   pausedAt  GetTime() while paused
--   color     { r, g, b } from the boss mod, or nil
--   colorType DBM color type 1-7 (tooltip line), count, keep, from
--   prev      remaining time at the previous driver tick (crossings)
--
-- The driver frame is shown only while the store holds a row, so an empty
-- timeline costs nothing. While it is shown, the timeline rides on the
-- shared ticker (E.Ticker): icons glide every frame, and ten times a
-- second one full step checks the thresholds, ends the timers that ran out
-- and redraws numbers and colors. A threshold fires when the remaining
-- time crosses it (previous step above, this step at or below), so a step
-- can come a little late but never skips one.
local _, E = ...
local M = E:GetModule("EncounterTimeline")

local FADE = 0.2        -- stop and end fade
local KEEP_HOLD = 3     -- DBM "keep" rows wait at 0 this long
local STEP = 0.1        -- thresholds, endings, numbers and colors: this often
local DRIVE = "EldoUI.EncounterTimeline.drive" -- the shared ticker key

local issecret = issecretvalue or function() return false end

M.rows = {}
M.secretDrops = 0
M.received = {}
-- Counters for diagnostics (/eui probe timeline): how often each
-- threshold fired.
M.stats = { tick = 0, soon = 0, warn = 0, bad = 0, glow = 0, sound = 0, final = 0 }

function M:ResetStats()
	for key in pairs(self.stats) do self.stats[key] = 0 end
end

function M:CountRows()
	local count = 0
	for _ in pairs(self.rows) do count = count + 1 end
	return count
end

function M:CountShown()
	local count = 0
	for _, row in pairs(self.rows) do
		if self:Wanted(row) then count = count + 1 end
	end
	return count
end

-- Seconds left, frozen while paused; never below 0.
function M:Remaining(row, now)
	local at = row.pausedAt or now or GetTime()
	local left = row.start + row.duration - at
	if left < 0 then return 0 end
	return left
end

-- Remember the last timers for /eui probe timeline (what was secret).
function M:NoteReceived(info)
	local list = self.received
	list[#list + 1] = info
	if #list > 10 then table.remove(list, 1) end
end

function M:CountSecretDrop()
	self.secretDrops = (self.secretDrops or 0) + 1
end

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------
-- Add or replace a row. data.duration must be plain; data.elapsed (plain,
-- optional) starts it part-way. Returns the row or nil.
function M:Add(data)
	if type(data) ~= "table" or type(data.key) ~= "string" then return nil end
	if issecret(data.duration) or issecret(data.elapsed) then
		self:CountSecretDrop()
		return nil
	end
	local duration = M.Number(data.duration)
	if not duration or duration <= 0 then return nil end
	local now = GetTime()
	local elapsed = M.Number(data.elapsed) or 0
	if elapsed < 0 then elapsed = 0 end
	local finish = now - elapsed + duration
	-- "Both" sources: the second copy of one timer (same spell, end within
	-- half a second) is dropped.
	if data.spellId then
		for _, other in pairs(self.rows) do
			if other.key ~= data.key and other.spellId == data.spellId and other.source ~= data.source
				and not other.stopping and math.abs(other.start + other.duration - finish) <= 0.5 then
				return nil
			end
		end
	end
	local row = self.rows[data.key]
	if row then
		row.stopping, row.ending, row.pausedAt = nil, nil, nil
	else
		row = { key = data.key, lane = 0 }
		self.rows[data.key] = row
	end
	row.source = data.source
	row.kind = data.kind
	row.text = data.text
	row.icon = data.icon
	row.spellId = data.spellId
	row.color = data.color
	row.colorType = data.colorType
	row.count = data.count
	row.keep = data.keep and true or false
	row.from = data.from
	row.module = data.module
	row.sample = data.sample
	row.start = now - elapsed
	row.duration = duration
	row.prev = self:Remaining(row, now)
	row.stage = nil
	if data.paused then row.pausedAt = now end
	self:UpdateDriver()
	return row
end

function M:Get(key)
	return self.rows[key]
end

-- elapsed and total: DBM's DBM_TimerUpdate (total is the new total).
function M:UpdateRow(key, elapsed, total)
	local row = self.rows[key]
	if not row then return nil end
	if issecret(elapsed) or issecret(total) then
		self:CountSecretDrop()
		return nil
	end
	elapsed, total = M.Number(elapsed), M.Number(total)
	if not (elapsed and total) or total <= 0 then return nil end
	local now = GetTime()
	row.start = (row.pausedAt or now) - elapsed
	row.duration = total
	row.prev = self:Remaining(row, now)
	row.ending = nil
	return row
end

function M:Pause(key)
	local row = self.rows[key]
	if row and not row.pausedAt and not row.stopping then row.pausedAt = GetTime() end
	return row
end

function M:Resume(key)
	local row = self.rows[key]
	if row and row.pausedAt then
		local now = GetTime()
		row.start = row.start + (now - row.pausedAt)
		row.pausedAt = nil
		row.prev = self:Remaining(row, now)
	end
	return row
end

local function Motion()
	return not (E.db and E.db.general and E.db.general.animations == false)
end

-- Stopped early: fades out where it is (or goes at once without motion).
function M:Stop(key)
	local row = self.rows[key]
	if not row or row.stopping then return end
	if Motion() and self.active then
		row.stopping = GetTime()
	else
		self:Remove(row)
	end
end

function M:Remove(row)
	if self.rows[row.key] ~= row then return end
	self.rows[row.key] = nil
	self:ReleaseRow(row)
	self:UpdateDriver()
end

-- Rows matching fn(row), removed at once.
function M:RemoveWhere(fn)
	local list = {}
	for _, row in pairs(self.rows) do
		if fn(row) then list[#list + 1] = row end
	end
	for _, row in ipairs(list) do self:Remove(row) end
	return #list
end

-- Stop the matching rows now (with the fade).
function M:StopWhere(fn)
	local list = {}
	for key, row in pairs(self.rows) do
		if fn(row) then list[#list + 1] = key end
	end
	for _, key in ipairs(list) do self:Stop(key) end
	return #list
end

function M:ClearKind(kind)
	return self:StopWhere(function(row) return row.kind == kind end)
end

-- After a wipe, kill or the end of an encounter: the boss rows of that
-- moment go one second later (a new pull in that second stays).
function M:ClearSoon(fn)
	local snapshot = {}
	for key, row in pairs(self.rows) do
		if fn(row) then snapshot[key] = row end
	end
	C_Timer.After(1, function()
		for key, row in pairs(snapshot) do
			if M.rows[key] == row then M:Stop(key) end
		end
	end)
end

-- Everything (but the test rows, unless withTests).
function M:ClearAll(withTests)
	self:RemoveWhere(function(row)
		return withTests or (row.source ~= "test" and row.source ~= "sample")
	end)
end

---------------------------------------------------------------------------
-- The driver
---------------------------------------------------------------------------
local driver = CreateFrame("Frame")
driver:Hide()
M.driver = driver
local lastStep = 0
local gone = {}

-- The next driver frame runs a full step.
function M:StepNext()
	lastStep = 0
end

function M:UpdateDriver()
	local want = self.active and next(self.rows) ~= nil
	driver:SetShown(want and true or false)
	if self.bar then self:ShowContent() end
end

local function Crossed(prev, now, t)
	return prev > t and now <= t
end
M.Crossed = Crossed

-- The row the countdown sound follows: the soonest shown, still running.
local function SoundRows(self, s)
	if not s.sound then return nil end
	local best, bestLeft
	for _, row in pairs(self.rows) do
		if not row.stopping and not row.ending and not row.pausedAt and not row.sample and self:Wanted(row) and row.prev > 0 then
			if not s.onlySoon then return true end
			if not bestLeft or row.prev < bestLeft then best, bestLeft = row, row.prev end
		end
	end
	return best
end

function M:Crossings(row, prev, left, s, soundRow)
	if row.sample or prev <= left then return end
	if not self:Wanted(row) then return end
	-- Tick highlight: the icon's center passed a tick mark.
	if s.ticks then
		local count = self:TickCount(s)
		for index = 1, count do
			if Crossed(prev, left, index * s.tickEvery) then
				self.stats.tick = self.stats.tick + 1
				self:FlashTick(index)
			end
		end
	end
	-- Countdown sound: whole seconds from `from` to 1, then the final one.
	if soundRow == true or soundRow == row then
		for second = s.soundFrom, 1, -1 do
			if Crossed(prev, left, second) then self:PlayCountdown(false) end
		end
		if Crossed(prev, left, 0) then self:PlayCountdown(true) end
	end
end

-- One full step: crossings, expiry, fades, then the bar and the Soon slot
-- with their numbers and colors. It runs ten times a second while the
-- timeline holds a row, and at once after a change.
function M:Tick()
	if not self.active then return end
	local s = self.cache or self:Settings()
	local now = GetTime()
	lastStep = now
	self.steps = (self.steps or 0) + 1
	local soundRow = SoundRows(self, s)
	wipe(gone)
	for _, row in pairs(self.rows) do
		if row.stopping then
			if now - row.stopping >= FADE then gone[#gone + 1] = row end
		elseif not row.pausedAt then
			local left = row.start + row.duration - now
			self:Crossings(row, row.prev, math.max(left, 0), s, soundRow)
			if left <= 0 then
				-- A "keep" row waits at 0 until DBM stops it (at most KEEP_HOLD).
				local held = row.keep and -left < KEEP_HOLD
				if held then
					row.held = true
				elseif not row.ending then
					if s.motion then row.ending = now else gone[#gone + 1] = row end
				elseif now - row.ending >= FADE then
					gone[#gone + 1] = row
				end
			end
			row.prev = math.max(left, 0)
		end
	end
	for _, row in ipairs(gone) do self:Remove(row) end
	wipe(gone)
	self:LayoutBar(now, true)
	self:LayoutSoon(now, true)
end

-- Between two steps: the icons only move (glide, fades, pop-in); numbers,
-- colors and thresholds wait for the next step.
function M:Place()
	if not self.active then return end
	if not self.cache then self:Settings() end
	local now = GetTime()
	self:LayoutBar(now, false)
	self:LayoutSoon(now, false)
end

-- Every frame while the driver is shown.
local function Drive()
	if GetTime() - lastStep >= STEP - 1e-6 then
		M:Tick()
	else
		M:Place()
	end
end

-- The driver frame switches the shared ticker subscription on and off.
driver:SetScript("OnShow", function() E.Ticker:Subscribe(DRIVE, 0, Drive, M) end)
driver:SetScript("OnHide", function() E.Ticker:Unsubscribe(DRIVE) end)

-- How far a fade has come (0 .. 1) for a stopping or ending row.
function M:FadeProgress(row, now)
	local since = row.stopping or row.ending
	if not since then return 0 end
	local t = (now - since) / FADE
	if t < 0 then return 0 end
	if t > 1 then return 1 end
	return t
end

-- Stage of a remaining time: "bad", "warn" or nil.
function M:Stage(left, s)
	if left <= s.bad then return "bad" end
	if left <= s.warn then return "warn" end
	return nil
end

-- The color token of a stage.
function M:StageColor(stage)
	local text = E.tokens.text
	if stage == "bad" then return text.bad end
	if stage == "warn" then return text.warn end
	return text.body
end

-- Seconds as the icons show them: minutes from a minute up ("2m"), one
-- decimal under a second with tenths on, else whole seconds rounded up.
function M:FormatSeconds(left, tenths)
	if left >= 60 then return ("%dm"):format(math.ceil(left / 60)) end
	if tenths and left < 1 then return ("%.1f"):format(left) end
	return ("%d"):format(math.ceil(left))
end

-- Rows the bar and the Soon slot draw: shown, sorted by time left.
function M:ShownRows(now)
	local list = self.shownList or {}
	self.shownList = list
	wipe(list)
	for _, row in pairs(self.rows) do
		if self:Wanted(row) then
			row.left = self:Remaining(row, now)
			list[#list + 1] = row
		end
	end
	-- Ties (two timers at 0, or due together): the one that ended first
	-- stays first, so the order on screen never flips.
	table.sort(list, function(a, b)
		if a.left ~= b.left then return a.left < b.left end
		local aEnd, bEnd = a.start + a.duration, b.start + b.duration
		if aEnd ~= bEnd then return aEnd < bEnd end
		return a.key < b.key
	end)
	return list
end

-- A row is about to go: its frames go back to the pools.
function M:ReleaseRow(row)
	if self.ReleaseBarIcon then self:ReleaseBarIcon(row) end
	if self.ReleaseSoonSlot then self:ReleaseSoonSlot(row) end
end
