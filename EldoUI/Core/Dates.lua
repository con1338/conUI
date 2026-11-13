local _, E = ...

---------------------------------------------------------------------------
-- Dates and clocks: one shape for every date EldoUI shows.
--
-- Month and weekday names come from the game's calendar strings while
-- EldoUI shows the client's language, and from EldoUI's own translation
-- when it shows another one (an English client with EldoUI in Danish).
-- A language that puts the day first (Danish "21. oktober") gets that
-- order in every shape below. The clock follows the shared 12/24-hour
-- choice (General page, E:Clock24) with the game's own AM/PM words. A date
-- in the current year shows no year.
--
--   E:MonthName(month[, short])      "October" / "Oct"
--   E:WeekdayName(wday[, short])     "Wednesday" / "Wed" (1 = Sunday)
--   E:FormatClock(hour, min[, sec])  "14:02" / "2:02 PM" (+ ":05")
--   E:FormatTime([stamp][, seconds]) the clock of a time() stamp (now)
--     both take a last use24 argument for a module with its own clock
--     choice (true / false; nil follows the General page)
--   E:ShortDay(stamp)                "Oct 14" / "Oct 14, 2025"
--   E:LongDay(stamp[, weekday])      "October 14" / "Wednesday, October 14"
--   E:MonthYear(stamp)               "October 2026"
--   E:ShortDate(stamp)               "Oct 14, 14:02" / "Oct 14, 2025, 14:02"
--   E:When(stamp)                    the clock today, otherwise ShortDay
--   E:DayKey(stamp)                  "2026-10-14" (for keys and copied text)
--
-- Copied reports and saved keys keep the ISO shape on purpose; every text
-- a player reads in a window or tooltip goes through these helpers.
---------------------------------------------------------------------------

local function Stamp(stamp)
	stamp = tonumber(stamp)
	if not stamp then return time() end
	return stamp
end

local function Parts(stamp)
	return date("*t", Stamp(stamp))
end

local function ThisYear(year)
	return year == date("*t", time()).year
end

local Key = E.Key
local MONTHS = { Key("January"), Key("February"), Key("March"), Key("April"), Key("May"), Key("June"),
	Key("July"), Key("August"), Key("September"), Key("October"), Key("November"), Key("December") }
local WEEKDAYS = { Key("Sunday"), Key("Monday"), Key("Tuesday"), Key("Wednesday"), Key("Thursday"), Key("Friday"), Key("Saturday") }
-- Languages whose dates read day first.
local DAY_FIRST = { daDK = true }

-- True while EldoUI shows a language other than the client's: the game's
-- calendar strings would then read in the wrong one.
local function OwnNames()
	local client = GetLocale()
	if client == "enGB" then client = "enUS" end
	return E:GetLanguage() ~= client
end

local function DayFirst()
	return DAY_FIRST[E:GetLanguage()]
end

-- Short form: the first three letters, or the whole name when it has four
-- letters or fewer ("May", "June", French "juin" next to "juil").
local function Short(name)
	if type(name) ~= "string" then return "" end
	if E:Utf8Len(name) <= 4 then return name end
	return E:Utf8Sub(name, 3)
end

function E:MonthName(month, short)
	month = tonumber(month)
	if not month or month < 1 or month > 12 then return "" end
	local names = rawget(_G, "CALENDAR_FULLDATE_MONTH_NAMES")
	local name = type(names) == "table" and names[month]
	if OwnNames() then
		name = E.L[MONTHS[month]]
	elseif type(name) ~= "string" or name == "" then
		name = date("%B", time({ year = 2026, month = month, day = 15, hour = 12 }))
	end
	return short and Short(name) or name
end

function E:WeekdayName(wday, short)
	wday = tonumber(wday)
	if not wday or wday < 1 or wday > 7 then return "" end
	local names = rawget(_G, "CALENDAR_WEEKDAY_NAMES")
	local name = type(names) == "table" and names[wday]
	if OwnNames() then
		name = E.L[WEEKDAYS[wday]]
	elseif type(name) ~= "string" or name == "" then
		-- 2026-10-04 was a Sunday.
		name = date("%A", time({ year = 2026, month = 10, day = 3 + wday, hour = 12 }))
	end
	return short and Short(name) or name
end

local function Meridiem(hour)
	if hour < 12 then return rawget(_G, "TIMEMANAGER_AM") or E.L["AM"] end
	return rawget(_G, "TIMEMANAGER_PM") or E.L["PM"]
end

function E:FormatClock(hour, minute, second, use24)
	hour, minute = tonumber(hour) or 0, tonumber(minute) or 0
	local tail = ""
	if second then tail = (":%02d"):format(tonumber(second) or 0) end
	if use24 == nil then use24 = self:Clock24() end
	if use24 then return ("%02d:%02d%s"):format(hour, minute, tail) end
	local shown = hour % 12
	if shown == 0 then shown = 12 end
	return ("%d:%02d%s %s"):format(shown, minute, tail, Meridiem(hour))
end

function E:FormatTime(stamp, seconds, use24)
	local t = Parts(stamp)
	return self:FormatClock(t.hour, t.min, seconds and t.sec or nil, use24)
end

function E:ShortDay(stamp, withYear)
	local t = Parts(stamp)
	local dayFirst = DayFirst()
	local text = dayFirst and ("%d. %s"):format(t.day, self:MonthName(t.month, true))
		or ("%s %d"):format(self:MonthName(t.month, true), t.day)
	if withYear or not ThisYear(t.year) then text = (dayFirst and "%s %d" or "%s, %d"):format(text, t.year) end
	return text
end

-- withYear keeps the year even in the current year, for text that is kept,
-- such as an exported story.
function E:LongDay(stamp, weekday, withYear)
	local t = Parts(stamp)
	local dayFirst = DayFirst()
	local text = dayFirst and ("%d. %s"):format(t.day, self:MonthName(t.month))
		or ("%s %d"):format(self:MonthName(t.month), t.day)
	if withYear or not ThisYear(t.year) then text = (dayFirst and "%s %d" or "%s, %d"):format(text, t.year) end
	if weekday then text = (dayFirst and "%s %s" or "%s, %s"):format(self:WeekdayName(t.wday), text) end
	return text
end

function E:MonthYear(stamp)
	local t = Parts(stamp)
	return ("%s %d"):format(self:MonthName(t.month), t.year)
end

function E:ShortDate(stamp)
	stamp = Stamp(stamp)
	return ("%s, %s"):format(self:ShortDay(stamp), self:FormatTime(stamp))
end

function E:DayKey(stamp)
	return date("%Y-%m-%d", Stamp(stamp))
end

function E:When(stamp)
	stamp = Stamp(stamp)
	if self:DayKey(stamp) == self:DayKey(time()) then return self:FormatTime(stamp) end
	return self:ShortDay(stamp)
end

-- Older plugins build date() formats from this; the AM/PM it gives is the
-- system's, so new code calls E:FormatTime instead.
function E:ClockFormat()
	return self:Clock24() and "%H:%M" or "%I:%M %p"
end
