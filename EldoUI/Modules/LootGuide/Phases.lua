-- EldoUI Loot Guide: WoW: Forever's content schedule.
--
-- WoW: Forever opens content in announced steps (LG.FOREVER_SCHEDULE in
-- Forever.lua): what was there at launch, then the December raids and so
-- on. The step an instance opens with comes from that table; an item's
-- step is the earliest step of any of its sources (Data.lua, LG:ItemPhase).
-- The Classic phase numbers in the loot data describe Classic Era and are
-- not used here.
--
--   LG:CurrentPhase()            the step that is open now: the "Content
--                                open now" option, else the announced days
--   LG:MaxPhase()                the last announced step
--   LG:PlanPhase()               the step Best in Slot plans for (its chip,
--                                window state): "current" follows the live one
--   LG:InstanceStep(key)         the step an instance opens with (1: launch)
--   LG:OpenNow(info)             a catalog entry you can go to now
--   LG:IsFuturePhase(itemID[, phase]) the item arrives after `phase`
--   LG:PhaseBadge(itemID or { phase })  "Dec 9" for loot not out yet (badges on)
--   LG:PhaseOpensText(phase[, long])    the day a step opens, nil once open
--   LG:PhaseName(phase)
--
-- Nothing is inferred: the steps and days are public announcements written
-- into the table. Presentation only.
local _, E = ...
local LG = E.LootGuide
local L = E.L

local function Schedule()
	return LG.FOREVER_SCHEDULE or {}
end

-- Seconds since 1970 at 00:00 UTC of a day (no time zone involved).
local function DayStart(day)
	local y, m, d = day.year, day.month, day.day
	if m <= 2 then y = y - 1 end
	local era = math.floor(y / 400)
	local yoe = y - era * 400
	local doy = math.floor((153 * ((m + 9) % 12) + 2) / 5) + d - 1
	local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
	return (era * 146097 + doe - 719468) * 86400
end

local function Now()
	local server = rawget(_G, "GetServerTime")
	if server then
		local ok, now = pcall(server)
		if ok and type(now) == "number" and not E.Secret(now) then return now end
	end
	return time()
end

function LG:MaxPhase()
	local count = #Schedule()
	return count > 0 and count or nil
end

-- The last step whose day has come.
local function ScheduledStep()
	local now, current = Now(), 1
	for index, step in ipairs(Schedule()) do
		if not step.opens or DayStart(step.opens) <= now then current = index end
	end
	return current
end

function LG:CurrentPhase()
	local max = self:MaxPhase()
	if not max then return end
	local override = self.db and tonumber(self.db.phaseOverride)
	if override then return math.max(1, math.min(max, override)) end
	return math.min(max, ScheduledStep())
end

-- "current" or a step number (the Best in Slot chip).
function LG:PlanPhase()
	local value = self:UI().bisPhase
	local max = self:MaxPhase()
	if tonumber(value) and max then return math.max(1, math.min(max, tonumber(value))), false end
	return self:CurrentPhase(), true
end

function LG:SetPlanPhase(value)
	self:UI().bisPhase = tonumber(value) or nil
	self:Fire("list")
end

function LG:PhaseName(phase)
	local step = Schedule()[tonumber(phase) or 0]
	return step and step.name or L["Launch content"]
end

-- The step an instance opens with; 1 for one open since launch.
function LG:InstanceStep(key)
	if key == nil then return 1 end
	for index, step in ipairs(Schedule()) do
		if step.instances and step.instances[key] then return index end
	end
	return 1
end

-- A catalog entry you can go to now: on WoW: Forever and its step open.
function LG:OpenNow(info)
	if not self:Playable(info) then return false end
	local current = self:CurrentPhase()
	return not current or (info.phase or 1) <= current
end

-- The day a step opens, short ("Dec 9") or long ("December 9"), in the
-- player's language; nil when the step is open now.
function LG:PhaseOpensText(phase, long)
	phase = tonumber(phase)
	local current = self:CurrentPhase()
	if not (phase and current) or phase <= current then return end
	local step = Schedule()[phase]
	if not (step and step.opens) then return self:PhaseName(phase) end
	-- Noon UTC: the same calendar day in every time zone a realm is in.
	local stamp = DayStart(step.opens) + 12 * 3600
	return long and E:LongDay(stamp) or E:ShortDay(stamp)
end

-- An item only a raid or world boss WoW: Forever has not opened drops
-- counts as not out yet, whatever the step.
function LG:IsFuturePhase(itemID, phase)
	if self.ItemOffForever and self:ItemOffForever(itemID) then return true end
	phase = phase or self:CurrentPhase()
	if not phase then return false end
	local itemPhase = self:ItemPhase(itemID)
	return itemPhase ~= nil and itemPhase > phase, itemPhase
end

-- The day it opens (bronze) for loot or a source that is not out yet.
-- arg: an itemID, or { phase = n } for an instance, set or vendor group.
function LG:PhaseBadge(arg)
	if not (self.db and self.db.phaseBadges) then return end
	local phase
	if type(arg) == "table" then phase = tonumber(arg.phase) else phase = self:ItemPhase(arg) end
	local text = phase and self:PhaseOpensText(phase)
	if not text then return end
	return E:TokenHex(E.tokens.palette.bronze) .. text .. "|r", phase
end

-- Step choices for the option and the chip: { [n] = name }.
function LG:PhaseValues(withAuto)
	local values = {}
	for phase = 1, self:MaxPhase() or 1 do values[phase] = self:PhaseName(phase) end
	if withAuto then values.auto = L["Auto"] end
	return values
end

LG.ScheduleDayStart = DayStart
