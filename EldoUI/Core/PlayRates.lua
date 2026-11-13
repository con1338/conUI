-- EldoUI play rates: one session count of the player's own gold and XP,
-- read by every place that shows a rate or a time to level (the XP bar
-- tooltip, the Info Bar's Gold per hour, XP per hour and Time to level
-- blocks, and My Adventure's pace), so they always agree.
--
-- The rate is the session's average for its first hour, then the last 60
-- minutes (one count per minute). For the first two minutes there is no
-- rate, so a single kill or sale never reads as a huge one. Only online
-- time counts. The session is kept per character over a reload, and starts
-- again after a log-out longer than the Info Bar's "New session after a
-- log-out of" setting.
--
--   E.PlayRates:Rate("xp" | "money")  per hour, or nil before two minutes
--   E.PlayRates:TimeToLevel()         seconds to the next level, or nil
--   E.PlayRates:Elapsed()             online seconds in the session
--   E.PlayRates:Basis()               "hour" (the last 60 minutes) or
--                                     "session" (the whole session so far)
--   E.PlayRates:BasisText()           the same as a tooltip text
--   E.PlayRates:BestHour()            the best full hour of net gold
--   E.PlayRates.session               { earned, spent, xp, ... } read only
--   E.PlayRates:Reset()               start the session again
--   E.PlayRates:OnChange(fn)          fn() after a reset or a restart
--
-- Rules (Forever): only the player's own money and XP, as the game reports
-- them; every value is checked for a secret before any math. Nothing is
-- posted to chat.
local _, E = ...
local L = E.L

local IsSecret = E.Secret
local HOUR = 3600
local MIN_TIME = 120 -- seconds of play before a rate is shown
local WINDOW = 60    -- minute counts the rate reads once the session is an hour old
local RESUME = 30    -- minutes, when the Info Bar has no setting yet

local Rates = { MIN_TIME = MIN_TIME }
E.PlayRates = Rates

local function Plain(value)
	if IsSecret(value) or type(value) ~= "number" then return nil end
	return value
end

-- session = { elapsed (online seconds before `since`), since (GetTime while
-- counting), earned, spent, xp, minutes = { { at = minute, money, xp } },
-- hours = { [hour] = net money } }
local function NewSession()
	return { elapsed = 0, earned = 0, spent = 0, xp = 0, minutes = {}, hours = {} }
end
Rates.NewSession = NewSession

local watchers = {}
function Rates:OnChange(fn)
	watchers[#watchers + 1] = fn
end

local function Changed()
	for _, fn in ipairs(watchers) do
		local ok, err = pcall(fn)
		if not ok then geterrorhandler()(err) end
	end
end

function Rates:Elapsed()
	local s = self.session
	if not s then return 0 end
	return s.elapsed + (s.since and math.max(GetTime() - s.since, 0) or 0)
end

-- One gain (or loss) into this minute's and this hour's count.
function Rates:Add(money, xp)
	local s = self.session
	if not s then return end
	local elapsed = self:Elapsed()
	local minute = math.floor(elapsed / 60)
	local last = s.minutes[#s.minutes]
	if not (last and last.at == minute) then
		last = { at = minute, money = 0, xp = 0 }
		table.insert(s.minutes, last)
	end
	last.money, last.xp = last.money + money, last.xp + xp
	while s.minutes[1] and s.minutes[1].at <= minute - WINDOW do table.remove(s.minutes, 1) end
	if money ~= 0 then
		local hour = math.floor(elapsed / HOUR) + 1
		s.hours[hour] = (s.hours[hour] or 0) + money
	end
end

-- Per hour of the session's average (first hour) or the last 60 minutes;
-- nil before MIN_TIME. field: "money" (net) or "xp".
function Rates:Rate(field)
	local s = self.session
	local elapsed = self:Elapsed()
	if not s or elapsed < MIN_TIME then return nil end
	local from, span = 0, elapsed
	if elapsed > HOUR then
		from = math.floor(elapsed / 60) - (WINDOW - 1)
		span = elapsed - from * 60
	end
	local sum = 0
	for _, entry in ipairs(s.minutes) do
		if entry.at >= from then sum = sum + (entry[field] or 0) end
	end
	return sum / span * HOUR
end

-- What the rate reads: the last hour, or the whole session while it is
-- younger than an hour.
function Rates:Basis()
	return self:Elapsed() > HOUR and "hour" or "session"
end

-- The same, for a tooltip: "the last hour" or "this session, 14 min".
function Rates:BasisText()
	if self:Basis() == "hour" then return L["the last hour"] end
	return L["this session, %s"]:format(E:FormatDuration(self:Elapsed(), "long"))
end

-- Seconds to the next level at the current XP rate, or nil.
function Rates:TimeToLevel()
	local rate = self:Rate("xp")
	local current, maximum = Plain(UnitXP("player")), Plain(UnitXPMax("player"))
	if not (rate and rate > 0 and current and maximum) then return nil end
	return (maximum - current) / rate * HOUR
end

-- The best complete hour of the session (net money), or nil.
function Rates:BestHour()
	local s = self.session
	if not s then return nil end
	local current = math.floor(self:Elapsed() / HOUR) + 1
	local best
	for hour = 1, current - 1 do
		local value = s.hours[hour] or 0
		if not best or value > best then best = value end
	end
	return best
end

-- Starts every session count again: earned, spent, XP and the hours.
function Rates:Reset()
	local counting = self.session and self.session.since ~= nil
	self.session = NewSession()
	if counting then self.session.since = GetTime() end
	self.lastMoney = Plain(GetMoney())
	self:ReadXP()
	Changed()
end

---------------------------------------------------------------------------
-- Money and XP
---------------------------------------------------------------------------
function Rates:TrackMoney()
	local money = Plain(GetMoney())
	if not (money and self.session) then return end
	local last = self.lastMoney
	self.lastMoney = money
	if not last or money == last then return end
	local delta = money - last
	if delta > 0 then
		self.session.earned = self.session.earned + delta
	else
		self.session.spent = self.session.spent - delta
	end
	self:Add(delta, 0)
end

-- The XP reading the next gain is counted from.
function Rates:ReadXP()
	self.lastXP, self.lastXPMax = Plain(UnitXP("player")), Plain(UnitXPMax("player"))
end

-- A drop in XP is a new level: what was left to it plus the new XP.
function Rates:TrackXP()
	if not self.session then return end
	local xp, maximum = Plain(UnitXP("player")), Plain(UnitXPMax("player"))
	if not (xp and maximum) then return end
	local last, lastMax = self.lastXP, self.lastXPMax
	self.lastXP, self.lastXPMax = xp, maximum
	if not (last and lastMax) then return end
	local gained = xp >= last and xp - last or (lastMax - last) + xp
	if gained > 0 then
		self.session.xp = self.session.xp + gained
		self:Add(0, gained)
	end
end

---------------------------------------------------------------------------
-- Over a reload: saved per character at log-out
---------------------------------------------------------------------------
E:RegisterPrivate("infoBarSession", {})

local function ResumeLimit()
	local infoBar = E.modules and E.modules.InfoBar
	return (tonumber(infoBar and infoBar.db and infoBar.db.sessionResume) or RESUME) * 60
end

function Rates:Save()
	local store = E:GetPrivate("infoBarSession")
	local s = self.session
	if not (store and s) then return end
	store.session = {
		savedAt = time(), elapsed = math.floor(self:Elapsed()), earned = s.earned, spent = s.spent, xp = s.xp,
		minutes = s.minutes, hours = s.hours,
	}
end

-- The saved session when the log-out was short enough, else a new one.
function Rates:Restore()
	local store = E:GetPrivate("infoBarSession")
	local saved = store and store.session
	if store then store.session = nil end
	if type(saved) ~= "table" or type(saved.savedAt) ~= "number" or type(saved.elapsed) ~= "number"
		or time() - saved.savedAt > ResumeLimit() then
		return NewSession()
	end
	local s = NewSession()
	s.elapsed = math.max(saved.elapsed, 0)
	s.earned, s.spent, s.xp = tonumber(saved.earned) or 0, tonumber(saved.spent) or 0, tonumber(saved.xp) or 0
	for _, entry in ipairs(type(saved.minutes) == "table" and saved.minutes or {}) do
		if type(entry) == "table" and tonumber(entry.at) then
			s.minutes[#s.minutes + 1] = { at = tonumber(entry.at), money = tonumber(entry.money) or 0, xp = tonumber(entry.xp) or 0 }
		end
	end
	for hour, value in pairs(type(saved.hours) == "table" and saved.hours or {}) do
		if tonumber(hour) and tonumber(value) then s.hours[tonumber(hour)] = tonumber(value) end
	end
	return s
end

-- Counting starts at login whatever modules are on.
function Rates:Enable()
	if not self.session then self.session = self:Restore() end
	self.session.since = GetTime()
	self.lastMoney = Plain(GetMoney())
	self:ReadXP()
	if not self.events then
		self.events = CreateFrame("Frame")
		self.events:SetScript("OnEvent", function(_, event, unit)
			if event == "PLAYER_MONEY" then
				Rates:TrackMoney()
			elseif event == "PLAYER_XP_UPDATE" then
				if unit == nil or unit == "player" then Rates:TrackXP() end
			elseif event == "PLAYER_LOGOUT" then
				Rates:Save()
			end
		end)
	end
	for _, event in ipairs({ "PLAYER_MONEY", "PLAYER_XP_UPDATE", "PLAYER_LOGOUT" }) do self.events:RegisterEvent(event) end
	Changed()
end

-- Stops counting (the clock and the events) until Enable.
function Rates:Disable()
	if self.events then self.events:UnregisterAllEvents() end
	local s = self.session
	if s and s.since then
		s.elapsed, s.since = self:Elapsed(), nil
	end
end

E:RegisterEvent("PLAYER_LOGIN", function() Rates:Enable() end, Rates)
