-- EldoUI Info Bar: the calendar in the Time and Date blocks.
--
-- Their tooltips list the calendar invites waiting for an answer, today's
-- events with their start times, the next guild event and the daily and
-- weekly reset countdowns; each part shows only when the game has the
-- data. A small accent dot follows the block text while an invite waits.
-- The Guild tooltip names the next guild event.
--
-- Where a game rule turns the calendar off, the click does nothing and
-- its hint is left out.
--
-- Rules (Forever): the calendar is the game's own data; nothing is
-- accepted or declined here, and a click opens the calendar as before.
-- The calendar is not read in combat or while the game locks chat down
-- (encounters, keys, PvP), when it would refuse.
local _, E = ...
local L = E.L
local M = E.modules.InfoBar
local Plain = E.Plain

local Cal = {}
M.calendar = Cal

local MAX_DAY_EVENTS = 4

local function Api(name)
	local cal = rawget(_G, "C_Calendar")
	local fn = cal and cal[name]
	return type(fn) == "function" and fn or nil
end

local function Call(fn, ...)
	if not fn then return nil end
	return E.PlainCall(fn, ...)
end

local function CurrentCalendarTime()
	local clock = rawget(_G, "C_DateAndTime")
	return clock and Call(clock.GetCurrentCalendarTime)
end

-- True when a game rule turns the in-game calendar off.
function Cal.Disabled()
	local rules = rawget(_G, "C_GameRules")
	local active = rules and rules.IsGameRuleActive
	local rule = Enum and Enum.GameRule and Enum.GameRule.IngameCalendarDisabled
	if type(active) ~= "function" or rule == nil then return false end
	return Call(active, rule) == true
end

-- The calendar is read only where the game allows it.
function Cal.Readable()
	if Cal.Disabled() or InCombatLockdown() then return false end
	return not (E.CommRestricted and E:CommRestricted())
end

function Cal.PendingInvites()
	if not Cal.Readable() then return 0 end
	local count = Call(Api("GetNumPendingInvites"))
	return type(count) == "number" and count or 0
end

-- The calendar's month offset of today and today's day of the month.
local function Today()
	local now = CurrentCalendarTime()
	if type(now) ~= "table" then return nil end
	local day, month, year = Plain(now.monthDay), Plain(now.month), Plain(now.year)
	if not (day and month and year) then return nil end
	local offset = 0
	local shown = Call(Api("GetMonthInfo"), 0)
	if type(shown) == "table" and shown.month and shown.year then
		offset = (year - shown.year) * 12 + (month - shown.month)
	end
	return offset, day
end

-- Compare calendar times in the realm's clock, including across month ends.
local function CalendarMinute(info)
	if type(info) ~= "table" then return nil end
	local year, month, day = Plain(info.year), Plain(info.month), Plain(info.monthDay)
	local hour, minute = Plain(info.hour), Plain(info.minute)
	if type(year) ~= "number" or type(month) ~= "number" or type(day) ~= "number"
		or type(hour) ~= "number" or type(minute) ~= "number" then return nil end
	return ((((year * 12 + month) * 31 + day) * 24 + hour) * 60 + minute)
end

local function Clock(time)
	if type(time) ~= "table" or type(time.hour) ~= "number" then return nil end
	return E:FormatClock(time.hour, time.minute or 0)
end

-- Today's events: { { title, at }, ... }, at most MAX_DAY_EVENTS, and the
-- number left out.
function Cal.TodayEvents()
	if not Cal.Readable() then return {}, 0 end
	local offset, day = Today()
	if not day then return {}, 0 end
	local count = Call(Api("GetNumDayEvents"), offset, day)
	local list, more = {}, 0
	for index = 1, type(count) == "number" and count or 0 do
		local info = Call(Api("GetDayEvent"), offset, day, index)
		local title = type(info) == "table" and Plain(info.title)
		if type(title) == "string" and title ~= "" then
			if #list < MAX_DAY_EVENTS then
				list[#list + 1] = { title = title, at = Clock(info.startTime) }
			else
				more = more + 1
			end
		end
	end
	return list, more
end

-- The next guild event: title and "weekday hh:mm", or nil.
function Cal.NextGuildEvent()
	if not Cal.Readable() then return nil end
	local now = CalendarMinute(CurrentCalendarTime())
	if not now then return nil end
	local count = Call(Api("GetNumGuildEvents"))
	local nextTitle, nextInfo, nextTime
	for index = 1, type(count) == "number" and count or 0 do
		local info = Call(Api("GetGuildEventInfo"), index)
		local title = type(info) == "table" and Plain(info.title)
		local at = CalendarMinute(info)
		if type(title) == "string" and title ~= "" and at and at >= now and (not nextTime or at < nextTime) then
			nextTitle, nextInfo, nextTime = title, info, at
		end
	end
	if not nextInfo then return nil end
	local when, weekday = Clock(nextInfo) or "", Plain(nextInfo.weekday)
	if type(weekday) == "number" and E.WeekdayName then when = E:WeekdayName(weekday, true) .. " " .. when end
	return nextTitle, when
end

-- Seconds until the daily and weekly resets, or nil.
function Cal.Resets()
	local clock = rawget(_G, "C_DateAndTime")
	if not clock then return nil end
	local daily = clock.GetSecondsUntilDailyReset and Call(clock.GetSecondsUntilDailyReset)
	local weekly = clock.GetSecondsUntilWeeklyReset and Call(clock.GetSecondsUntilWeeklyReset)
	return type(daily) == "number" and daily or nil, type(weekly) == "number" and weekly or nil
end

-- The calendar lines of the Time and Date tooltips.
function Cal.AddLines(tooltip)
	local Kit = E.UIKit
	local invites = Cal.PendingInvites()
	local events, more = Cal.TodayEvents()
	local guildTitle, guildWhen = Cal.NextGuildEvent()
	local daily, weekly = Cal.Resets()
	if invites == 0 and #events == 0 and not guildTitle and not daily and not weekly then return end
	tooltip:AddLine(" ")
	if invites > 0 then
		Kit.TipPair(tooltip, L["Invites waiting"], tostring(invites), E:TokenColor("accent"))
	end
	for _, event in ipairs(events) do
		Kit.TipPair(tooltip, event.title, event.at or L["Today"])
	end
	if more > 0 then Kit.TipText(tooltip, L["and %d more"]:format(more)) end
	if guildTitle then Kit.TipPair(tooltip, L["Next guild event"], guildTitle .. "  " .. guildWhen) end
	if daily then Kit.TipPair(tooltip, L["Daily reset"], E:FormatDuration(daily, "long")) end
	if weekly then Kit.TipPair(tooltip, L["Weekly reset"], E:FormatDuration(weekly, "long")) end
end

-- The line for the Guild tooltip.
function Cal.AddGuildLine(tooltip)
	local title, when = Cal.NextGuildEvent()
	if title then E.UIKit.TipPair(tooltip, L["Next guild event"], title .. "  " .. when) end
end

-- The block text with the invite dot.
function Cal.Mark(text)
	if Cal.PendingInvites() > 0 then return text .. " " .. E:TextHex("accent") .. "•|r" end
	return text
end

-- The click hint, left out while the calendar is off.
function Cal.Hint(tooltip)
	if not Cal.Disabled() then E:TooltipHint(tooltip, { L["Click"], L["calendar"] }) end
end

for _, name in ipairs({ "Time", "Date" }) do
	local def = E.dataTexts[name]
	if def then
		def.events = def.events or {}
		table.insert(def.events, "CALENDAR_UPDATE_PENDING_INVITES")
	end
end
