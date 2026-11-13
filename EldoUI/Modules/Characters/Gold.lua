-- EldoUI Characters: the Gold tab, your gold over time.
--
-- Each character keeps one snapshot of its gold per day (record.moneyDays
-- = { [YYYYMMDD] = copper }, the last amount seen that day, 400 days at
-- most), written when the game reports a money change and at login. The
-- level log's gold at each ding fills in days before the snapshots began.
-- The chart shows one character or all of them added up, as one bar per
-- day (one per week for the year view). Only your own gold, as the game
-- reports it; a secret amount is never stored.
local _, E = ...
local L = E.L
local Key = E.Key
local Kit = E.UIKit
local M = E.modules.Characters

local DAY = 86400
local KEEP_DAYS = 400
local ACCOUNT = "*"
M.GOLD_ACCOUNT = ACCOUNT

local function Store() return E.Characters end

-- YYYYMMDD of a time, in the player's own calendar.
local function DayKey(t)
	return tonumber(date("%Y%m%d", t or time()))
end
M.GoldDayKey = DayKey

-- Today's snapshot for this character (the amount the store last read).
function M:RecordGoldDay()
	local C = Store()
	if not (C and C.Recording and C:Recording()) then return end
	local record = C:Me()
	local money = record and record.money
	if E.Secret(money) or type(money) ~= "number" then return end
	local days = type(record.moneyDays) == "table" and record.moneyDays or {}
	record.moneyDays = days
	days[DayKey()] = money
	local list = {}
	for day in pairs(days) do list[#list + 1] = day end
	if #list > KEEP_DAYS then
		table.sort(list)
		for index = 1, #list - KEEP_DAYS do days[list[index]] = nil end
	end
end

-- Known amounts of one character, oldest first: { { day, money }, ... }.
local function Known(record)
	local byDay = {}
	for level, row in pairs(type(record.levels) == "table" and record.levels or {}) do
		if type(level) == "number" and type(row) == "table" and tonumber(row.at) and tonumber(row.money) then
			local day = DayKey(row.at)
			-- The ding latest in the day wins.
			local seen = byDay[day]
			if not seen or seen.at < row.at then byDay[day] = { at = row.at, money = row.money } end
		end
	end
	for day, money in pairs(type(record.moneyDays) == "table" and record.moneyDays or {}) do
		if type(day) == "number" and type(money) == "number" then byDay[day] = { at = math.huge, money = money } end
	end
	local list = {}
	for day, entry in pairs(byDay) do list[#list + 1] = { day, entry.money } end
	table.sort(list, function(a, b) return a[1] < b[1] end)
	return list
end

-- The last known amount on or before each wanted day (nil before the first).
local function Fill(known, days)
	local values, at = {}, 0
	for index, day in ipairs(days) do
		while known[at + 1] and known[at + 1][1] <= day do at = at + 1 end
		values[index] = at > 0 and known[at][2] or nil
	end
	return values
end

-- Points for a key (a character, or M.GOLD_ACCOUNT for every character)
-- over the last `range` days: { { t, day, value }, ... }, oldest first.
-- One point per day up to 90 days, one per week (its last day) beyond.
function M:GoldSeries(key, range)
	range = tonumber(range) or 30
	local step = range > 90 and 7 or 1
	local count = math.ceil(range / step)
	local now = time()
	local points, days = {}, {}
	for index = 1, count do
		local t = now - (count - index) * step * DAY
		points[index] = { t = t, day = DayKey(t) }
		days[index] = points[index].day
	end
	local C = Store()
	local keys = key == ACCOUNT and C:Keys("account") or { key }
	for _, each in ipairs(keys) do
		local record = C:Get(each)
		if record then
			for index, value in pairs(Fill(Known(record), days)) do
				points[index].value = (points[index].value or 0) + value
			end
		end
	end
	return points, step
end

---------------------------------------------------------------------------
-- The tab
---------------------------------------------------------------------------
local RANGES = { { 30, Key("Last 30 days") }, { 90, Key("Last 90 days") }, { 365, Key("Last year") } }
local AXIS_W, DATE_H, TOP_PAD, BAR_GAP = 96, 18, 10, 1

local function KeyValues()
	local values = { { ACCOUNT, L["All characters"] } }
	for _, key in ipairs(Store():Keys("account")) do
		local record = Store():Get(key)
		if record then values[#values + 1] = { key, M.ClassName(record, true) } end
	end
	return values
end

local function Paint(frame)
	local r, g, b = Kit.Accent()
	for _, bar in ipairs(frame.bars) do
		bar.fill:SetColorTexture(r, g, b, bar:IsMouseOver() and 1 or 0.75)
	end
end

local function Bar(frame, index)
	local bar = frame.bars[index]
	if bar then return bar end
	bar = CreateFrame("Button", nil, frame.plot)
	bar.fill = bar:CreateTexture(nil, "ARTWORK")
	bar.fill:SetPoint("BOTTOMLEFT")
	bar.fill:SetPoint("BOTTOMRIGHT")
	Kit.Tooltip(bar, nil, function(tooltip)
		local point = bar.point
		if not point then return end
		local when = E:ShortDay(point.t)
		if frame.step > 1 then when = (L["Week to %s"]):format(when) end
		Kit.TipTitle(tooltip, when)
		tooltip:AddLine(M.Money(point.value), E:TokenColor("body"))
		local before = bar.before
		if before then
			local change = point.value - before
			local text = change >= 0 and M.Good("+" .. M.Money(change)) or M.Bad("-" .. M.Money(-change))
			tooltip:AddLine((frame.step > 1 and L["%s since the week before"] or L["%s since the day before"]):format(text), E:TokenColor("body"))
		end
	end)
	bar:HookScript("OnEnter", function() Paint(frame) end)
	bar:HookScript("OnLeave", function() Paint(frame) end)
	frame.bars[index] = bar
	return bar
end

local function Draw(frame)
	local points = frame.points or {}
	local width, height = frame.plot:GetWidth() or 0, frame.plot:GetHeight() or 0
	local top = 0
	for _, point in ipairs(points) do
		if point.value and point.value > top then top = point.value end
	end
	frame.top = top
	frame.maxLabel:SetText(top > 0 and M.Money(top, true) or "")
	frame.midLabel:SetText(top > 0 and M.Money(top / 2, true) or "")
	local count = #points
	local slot = count > 0 and width / count or 0
	local last
	for index, point in ipairs(points) do
		local bar = Bar(frame, index)
		bar:ClearAllPoints()
		bar:SetPoint("BOTTOMLEFT", frame.plot, "BOTTOMLEFT", (index - 1) * slot, 0)
		bar:SetSize(math.max(slot - BAR_GAP, 1), math.max(height, 1))
		bar.point, bar.before = point, last
		if point.value and top > 0 and height > 0 then
			bar.fill:SetHeight(math.max(point.value / top * height, 1))
			bar:Show()
		else
			bar:Hide()
		end
		if point.value then last = point.value end
	end
	for index = count + 1, #frame.bars do
		frame.bars[index].point = nil
		frame.bars[index]:Hide()
	end
	frame.firstDate:SetText(points[1] and E:ShortDay(points[1].t) or "")
	frame.lastDate:SetText(points[count] and E:ShortDay(points[count].t) or "")
	Paint(frame)
end

local function Summary(frame)
	local points = frame.points or {}
	local first, last
	for _, point in ipairs(points) do
		if point.value then
			first = first or point.value
			last = point.value
		end
	end
	if not last then return L["Gold shows here from today on: one point per day for each character you log in on."] end
	local change = last - first
	local text = change >= 0 and M.Good("+" .. M.Money(change)) or M.Bad("-" .. M.Money(-change))
	local range
	for _, entry in ipairs(RANGES) do
		if entry[1] == frame.range then range = L[entry[2]] end
	end
	return (L["Now %s  ·  %s (%s)"]):format(M.Money(last), text, range or "")
end

local function Update(frame)
	local key = frame.key
	if key ~= ACCOUNT and not Store():Get(key or "") then key = E.charKey end
	frame.key = key
	frame.range = frame.range or 30
	frame.pick:Refresh()
	frame.rangePick:Refresh()
	frame.points, frame.step = M:GoldSeries(key, frame.range)
	Draw(frame)
	frame.summary:SetText(Summary(frame))
end
M.UpdateGold = Update

-- The tab's empty state while nothing is known for the pick.
function M.GoldEmpty(frame)
	for _, point in ipairs(frame.points or {}) do
		if point.value then return nil end
	end
	return L["No gold history yet"], L["Each character keeps one point per day from now on, and the gold at each level-up from the level log."]
end

local watcher = {}

M:AddTab({
	key = "gold", order = 58, title = "Gold",
	desc = "Your gold over time: one character or all of them, per day or per week.",
	create = function(content)
		local frame = CreateFrame("Frame", nil, content)
		frame:SetAllPoints()
		frame.bars = {}
		frame.key, frame.range = E.charKey, 30
		frame.toolbar = CreateFrame("Frame", nil, frame)
		frame.toolbar:SetPoint("TOPLEFT")
		frame.toolbar:SetPoint("TOPRIGHT")
		frame.toolbar:SetHeight(E.tokens.height.button)
		frame.pick = Kit.Dropdown(frame.toolbar, {
			width = 200, values = KeyValues,
			get = function() return frame.key end,
			set = function(value) frame.key = value Update(frame) end,
		})
		frame.pick:SetPoint("LEFT", 2, 0)
		Kit.Tooltip(frame.pick, L["Character"], L["One character's gold, or all characters added up."])
		frame.rangePick = Kit.Dropdown(frame.toolbar, {
			width = 140, values = RANGES,
			get = function() return frame.range end,
			set = function(value) frame.range = value Update(frame) end,
		})
		frame.rangePick:SetPoint("LEFT", frame.pick, "RIGHT", 8, 0)
		Kit.Tooltip(frame.rangePick, L["Range"], L["Up to 90 days shows one bar per day; the year shows one bar per week."])
		frame.summary = Kit.Text(frame.toolbar, E.tokens.size.label, "RIGHT", "secondary")
		frame.summary:SetPoint("LEFT", frame.rangePick, "RIGHT", 12, 0)
		frame.summary:SetPoint("RIGHT", -4, 0)
		frame.summary:SetWordWrap(false)

		frame.chart = CreateFrame("Frame", nil, frame)
		frame.chart:SetPoint("TOPLEFT", frame.toolbar, "BOTTOMLEFT", 0, -8)
		frame.chart:SetPoint("BOTTOMRIGHT")
		E:SetTemplate(frame.chart, true)
		frame.plot = CreateFrame("Frame", nil, frame.chart)
		frame.plot:SetPoint("TOPLEFT", AXIS_W, -TOP_PAD)
		frame.plot:SetPoint("BOTTOMRIGHT", -10, DATE_H + 4)
		-- Grid: the top, the middle and the base line, labeled on the left.
		local function Grid(y)
			local line = Kit.Divider(frame.chart)
			line:SetPoint("LEFT", frame.plot, "TOPLEFT", 0, 0)
			line:SetPoint("RIGHT", frame.plot, "TOPRIGHT", 0, 0)
			line.y = y
			return line
		end
		frame.grid = { Grid(1), Grid(0.5), Grid(0) }
		local function Label()
			local text = Kit.Text(frame.chart, E.tokens.size.small, "RIGHT", "secondary")
			text:SetWidth(AXIS_W - 12)
			text:SetWordWrap(false)
			return text
		end
		frame.maxLabel, frame.midLabel = Label(), Label()
		frame.firstDate = Kit.Text(frame.chart, E.tokens.size.small, "LEFT", "secondary")
		frame.firstDate:SetPoint("TOPLEFT", frame.plot, "BOTTOMLEFT", 0, -4)
		frame.lastDate = Kit.Text(frame.chart, E.tokens.size.small, "RIGHT", "secondary")
		frame.lastDate:SetPoint("TOPRIGHT", frame.plot, "BOTTOMRIGHT", 0, -4)
		local function PlaceGrid()
			local height = frame.plot:GetHeight() or 0
			for _, line in ipairs(frame.grid) do
				line:ClearAllPoints()
				line:SetPoint("LEFT", frame.plot, "BOTTOMLEFT", 0, height * line.y)
				line:SetPoint("RIGHT", frame.plot, "BOTTOMRIGHT", 0, height * line.y)
			end
			frame.maxLabel:ClearAllPoints()
			frame.maxLabel:SetPoint("RIGHT", frame.plot, "TOPLEFT", -8, 0)
			frame.midLabel:ClearAllPoints()
			frame.midLabel:SetPoint("RIGHT", frame.plot, "BOTTOMLEFT", -8, height / 2)
		end
		PlaceGrid()
		frame.plot:SetScript("OnSizeChanged", function()
			PlaceGrid()
			if frame.points then Draw(frame) end
		end)
		E:RegisterThemed(frame, Paint)
		return frame
	end,
	show = function(frame, arg)
		if type(arg) == "string" and (arg == ACCOUNT or Store():Get(arg)) then frame.key = arg end
		Update(frame)
	end,
	refresh = function(frame, changed)
		if type(changed) == "table" and changed.section and changed.section ~= "money" and not changed.forgotten and not changed.settings then return end
		Update(frame)
	end,
	empty = function(frame) return M.GoldEmpty(frame) end,
	enable = function()
		local C = Store()
		if C and C.RegisterCallback and not watcher.on then
			watcher.on = true
			C.RegisterCallback(watcher, "Updated", function(_, key, section)
				if M.active and key == E.charKey and (section == "money" or section == "login") then M:RecordGoldDay() end
			end)
		end
		M:RecordGoldDay()
	end,
	disable = function()
		local C = Store()
		if C and C.UnregisterCallback and watcher.on then
			watcher.on = nil
			C.UnregisterCallback(watcher, "Updated")
		end
	end,
})
