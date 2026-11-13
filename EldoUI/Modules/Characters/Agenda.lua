-- EldoUI Characters: the Agenda tab.
--
-- A month view of what happens to your characters: lockout resets,
-- profession cooldowns ready, calendar events, mail running out and
-- auctions ending. Each day shows a dot per kind; click a day for the
-- list. Optional reminders print a local chat line shortly before a
-- cooldown is ready, a lockout resets or a calendar event starts (once
-- each, and not while you are in combat). All times come from what each
-- character saw on its last login.
local _, E = ...
local L = E.L
local Kit = E.UIKit
local M = E.modules.Characters

local function Store() return E.Characters end

local function Grey(text) return M.Grey(text) end

local KINDS = {
	lockout = { title = "Lockout resets", color = Kit.BAD },
	cooldown = { title = "Cooldown ready", color = Kit.GOOD },
	calendar = { title = "Calendar event" },  -- the accent color
	mail = { title = "Mail runs out", color = Kit.WARN },
	auction = { title = "Auction ends" },     -- the game's epic item color
}

-- A kind's color, read when drawing: UIKit tokens, the accent color
-- (style presets change it) and the game's own item quality color.
local function KindColor(kind)
	if kind == "calendar" then return E.media.accentColor end
	if kind == "auction" then
		local epic = Enum and Enum.ItemQuality and Enum.ItemQuality.Epic or 4
		local getColor = C_Item and C_Item.GetItemQualityColor
		if getColor then
			local r, g, b = getColor(epic)
			if type(r) == "number" and type(g) == "number" and type(b) == "number" then return { r, g, b } end
		end
		return Kit.SECONDARY
	end
	local entry = KINDS[kind]
	return entry and entry.color or Kit.SECONDARY
end
M.AgendaKindColor = KindColor
local KIND_ORDER = { "lockout", "cooldown", "calendar", "mail", "auction" }
M.AGENDA_KINDS = KINDS

-- Every event between `from` and `to` (Unix times) for the scope:
-- { at, kind, key, text, shared }. A holiday or raid reset is the same for
-- every character: it comes once, `shared`, under the first one that saw it.
function M:AgendaEvents(from, to, keys)
	local events, sharedSeen = {}, {}
	local sharedKinds = Store().SHARED_CALENDAR or {}
	local function Add(at, kind, key, text, shared)
		if type(at) == "number" and at >= from and at < to then
			events[#events + 1] = { at = at, kind = kind, key = key, text = text, shared = shared }
		end
	end
	for _, key in ipairs(keys or self:Keys()) do
		local record = Store():Get(key)
		for _, lock in pairs(type(record.lockouts) == "table" and record.lockouts or {}) do
			Add(lock.resetAt, "lockout", key, L["%s resets"]:format(lock.name or "?"))
		end
		for _, cd in pairs(type(record.cooldowns) == "table" and record.cooldowns or {}) do
			Add(cd.readyAt, "cooldown", key, L["%s ready"]:format(cd.name or "?"))
		end
		for _, event in ipairs(type(record.calendar) == "table" and record.calendar or {}) do
			if sharedKinds[event.kind] then
				local id = tostring(event.title) .. "\001" .. tostring(event.at)
				if not sharedSeen[id] then
					sharedSeen[id] = true
					Add(event.at, "calendar", key, event.title or "?", true)
				end
			else
				Add(event.at, "calendar", key, event.title or "?")
			end
		end
		for _, mail in ipairs(type(record.mailMeta) == "table" and record.mailMeta or {}) do
			Add(mail.expires, "mail", key, L["Mail from %s runs out"]:format(mail.sender or "?"))
		end
		local auctions = type(record.auctions) == "table" and record.auctions.list
		for _, auction in ipairs(type(auctions) == "table" and auctions or {}) do
			local name = auction.link and auction.link:match("%[(.-)%]") or (auction.id and ("item:" .. auction.id)) or "?"
			Add(auction.endsAt, "auction", key, L["Auction ends: %s"]:format(name))
		end
	end
	table.sort(events, function(a, b)
		if a.at ~= b.at then return a.at < b.at end
		return a.kind < b.kind
	end)
	return events
end

---------------------------------------------------------------------------
-- Reminders
---------------------------------------------------------------------------
local WARN_KINDS = { lockout = "agendaWarnLockouts", cooldown = "agendaWarnCooldowns", calendar = "agendaWarnCalendar" }

-- Prints each due reminder once; returns how many it printed.
function M:CheckAgenda()
	if not (self.active and self.db.agendaWarn) then return 0 end
	if InCombatLockdown() then return 0 end
	self.agendaWarned = self.agendaWarned or {}
	local now = Store().Now()
	local lead = (self.db.agendaLead or 15) * 60
	local printed = 0
	for _, event in ipairs(self:AgendaEvents(now, now + lead + 1, Store():Keys("account"))) do
		local option = WARN_KINDS[event.kind]
		local id = event.kind .. "\001" .. (event.shared and "account" or event.key) .. "\001" .. event.at .. "\001" .. event.text
		if option and self.db[option] and not self.agendaWarned[id] then
			self.agendaWarned[id] = true
			printed = printed + 1
			if event.shared then
				E:Print(L["%s in %s."]:format(event.text, M.Duration(event.at - now)))
			else
				E:Print(L["%s: %s in %s."]:format(M.ClassName(Store():Get(event.key), true), event.text, M.Duration(event.at - now)))
			end
		end
	end
	return printed
end

local function StartTicker()
	if M.agendaTicker then return end
	M.agendaTicker = C_Timer.NewTicker(30, function() M:CheckAgenda() end)
end

local function StopTicker()
	if M.agendaTicker then
		M.agendaTicker:Cancel()
		M.agendaTicker = nil
	end
end

---------------------------------------------------------------------------
-- Month view
---------------------------------------------------------------------------
local CELL_W, CELL_H = 64, 52

local function DayStart(at)
	local t = date("*t", at)
	return time({ year = t.year, month = t.month, day = t.day, hour = 0 })
end

local function WeekdayNames()
	local names = {}
	for index = 1, 7 do names[index] = E:WeekdayName(index, true) end
	return names
end

local function MonthStart(year, month)
	return time({ year = year, month = month, day = 1, hour = 0 })
end

local function Update(frame)
	local year, month = frame.year, frame.month
	local first = MonthStart(year, month)
	local nextYear, nextMonth = month == 12 and year + 1 or year, month == 12 and 1 or month + 1
	local last = MonthStart(nextYear, nextMonth)
	frame.title:SetText(E:MonthYear(first + 43200))
	local mondayFirst = M.db.weekStartsMonday
	local names = WeekdayNames()
	for index = 1, 7 do
		local name = mondayFirst and names[index % 7 + 1] or names[index]
		frame.weekdays[index]:SetText(name)
	end
	local wday = date("*t", first).wday
	local offset = mondayFirst and (wday + 5) % 7 or (wday - 1)
	local events = M:AgendaEvents(first, last)
	frame.events = events
	local byDay = {}
	for _, event in ipairs(events) do
		local day = date("*t", event.at).day
		byDay[day] = byDay[day] or {}
		byDay[day][event.kind] = true
		byDay[day].count = (byDay[day].count or 0) + 1
	end
	local today = date("*t", Store().Now())
	local days = date("*t", last - 43200).day
	for index, cell in ipairs(frame.cells) do
		local day = index - offset
		if day >= 1 and day <= days then
			cell.day = day
			cell.text:SetText(day)
			local isToday = today.year == year and today.month == month and today.day == day
			if isToday then cell.text:SetTextColor(E:TokenColor("accent")) else Kit.Paint(cell.text) end
			local dots = 0
			for _, kind in ipairs(KIND_ORDER) do
				if byDay[day] and byDay[day][kind] then
					dots = dots + 1
					local dot = cell.dots[dots]
					local color = KindColor(kind)
					dot:SetColorTexture(color[1], color[2], color[3], 1)
					dot:Show()
				end
			end
			for hide = dots + 1, #cell.dots do cell.dots[hide]:Hide() end
			cell.selected:SetShown(frame.day == day)
			cell:Show()
		else
			cell.day = nil
			cell:Hide()
		end
	end
	-- The list of the selected day.
	frame.day = math.min(math.max(frame.day or 1, 1), days)
	local from = time({ year = year, month = month, day = frame.day, hour = 0 })
	local list = {}
	for _, event in ipairs(events) do
		if event.at >= from and event.at < from + 86400 then list[#list + 1] = event end
	end
	frame.dayEvents = list
	frame.dayTitle:SetText(E:LongDay(from + 43200, true))
	frame.list:SetData(list)
end
M.UpdateAgenda = Update

function M.AgendaGoTo(frame, at)
	local t = date("*t", at)
	frame.year, frame.month, frame.day = t.year, t.month, t.day
end

M:AddTab({
	key = "agenda", order = 70, title = "Agenda",
	desc = "A month of lockout resets, cooldowns, calendar events, mail and auctions for your characters.",
	create = function(content)
		local frame = CreateFrame("Frame", nil, content)
		frame:SetAllPoints()
		M.AgendaGoTo(frame, Store().Now())
		frame.month_ = CreateFrame("Frame", nil, frame)
		frame.month_:SetPoint("TOPLEFT")
		frame.month_:SetSize(CELL_W * 7, 24 + 18 + CELL_H * 6)
		local bar = frame.month_
		frame.prev = E.UIKit.IconButton(bar, 20, "chevron-left", function()
			frame.month = frame.month - 1
			if frame.month < 1 then frame.month, frame.year = 12, frame.year - 1 end
			frame.day = 1
			Update(frame)
		end, L["Previous month"], L["Shows the month before."])
		frame.prev:SetPoint("TOPLEFT", 0, 0)
		frame.next = E.UIKit.IconButton(bar, 20, "chevron-right", function()
			frame.month = frame.month + 1
			if frame.month > 12 then frame.month, frame.year = 1, frame.year + 1 end
			frame.day = 1
			Update(frame)
		end, L["Next month"], L["Shows the month after."])
		frame.next:SetPoint("TOPRIGHT", 0, 0)
		frame.title = Kit.Text(bar, 13, "CENTER", "header")
		frame.title:SetPoint("LEFT", frame.prev, "RIGHT", 4, 0)
		frame.title:SetPoint("RIGHT", frame.next, "LEFT", -4, 0)
		frame.todayButton = Kit.Button(bar, L["Today"], 60, 20, function()
			M.AgendaGoTo(frame, Store().Now())
			Update(frame)
		end, L["Today"], L["Jumps back to today."])
		frame.todayButton:SetPoint("RIGHT", frame.next, "LEFT", -4, 0)
		frame.weekdays = {}
		for index = 1, 7 do
			local text = Kit.Text(bar, 11, "CENTER", "secondary")
			text:SetSize(CELL_W, 16)
			text:SetPoint("TOPLEFT", (index - 1) * CELL_W, -24)
			frame.weekdays[index] = text
		end
		frame.cells = {}
		for index = 1, 42 do
			local cell = CreateFrame("Button", nil, bar)
			cell:SetSize(CELL_W - 2, CELL_H - 2)
			cell:SetPoint("TOPLEFT", ((index - 1) % 7) * CELL_W, -42 - math.floor((index - 1) / 7) * CELL_H)
			E:SetTemplate(cell, true)
			cell.text = Kit.Text(cell, 12, "LEFT")
			cell.text:SetPoint("TOPLEFT", 4, -3)
			cell.selected = cell:CreateTexture(nil, "OVERLAY")
			cell.selected:SetPoint("BOTTOMLEFT", 1, 1)
			cell.selected:SetPoint("BOTTOMRIGHT", -1, 1)
			cell.selected:SetHeight(2)
			cell.selected:SetColorTexture(Kit.Accent())
			cell.dots = {}
			for dot = 1, #KIND_ORDER do
				local texture = cell:CreateTexture(nil, "ARTWORK")
				texture:SetSize(7, 7)
				texture:SetPoint("BOTTOMLEFT", 4 + (dot - 1) * 10, 6)
				cell.dots[dot] = texture
			end
			cell:SetScript("OnClick", function(own)
				if own.day then
					frame.day = own.day
					Update(frame)
				end
			end)
			frame.cells[index] = cell
		end
		local legend = Kit.Text(frame, 11, "LEFT", "dim")
		legend:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -6)
		legend:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", 0, -6)
		local parts = {}
		for _, kind in ipairs(KIND_ORDER) do
			local color = KindColor(kind)
			parts[#parts + 1] = ("|TInterface\\Buttons\\WHITE8X8:8:8:0:0:8:8:0:8:0:8:%d:%d:%d|t "):format(color[1] * 255, color[2] * 255, color[3] * 255)
				.. L[KINDS[kind].title]
		end
		legend:SetText(table.concat(parts, "   "))
		legend:SetWordWrap(true)
		frame.side = CreateFrame("Frame", nil, frame)
		frame.side:SetPoint("TOPLEFT", bar, "TOPRIGHT", 14, 0)
		frame.side:SetPoint("BOTTOMRIGHT")
		frame.dayTitle = Kit.Text(frame.side, 13, "LEFT", "header")
		frame.dayTitle:SetPoint("TOPLEFT", 2, -2)
		frame.list = Kit.CreateList(frame.side, {
			rowHeight = 34,
			empty = { L["Nothing this day"], L["No reset, cooldown, event, mail or auction on this day."] },
			create = function(row)
				E:SkinRow(row)
				row.dot = row:CreateTexture(nil, "ARTWORK")
				row.dot:SetSize(7, 7)
				row.dot:SetPoint("TOPLEFT", 4, -7)
				row.text = Kit.Text(row, 12, "LEFT")
				row.text:SetPoint("TOPLEFT", 16, -3)
				row.text:SetPoint("TOPRIGHT", -4, -3)
				row.text:SetWordWrap(false)
				row.sub = Kit.Text(row, 11, "LEFT", "secondary")
				row.sub:SetPoint("TOPLEFT", row.text, "BOTTOMLEFT", 0, -2)
				row.sub:SetPoint("TOPRIGHT", row.text, "BOTTOMRIGHT", 0, -2)
			end,
			update = function(row, event)
				local color = KindColor(event.kind)
				row.dot:SetColorTexture(color[1], color[2], color[3], 1)
				row.text:SetText(event.text)
				local who = event.shared and "" or (M.ClassName(Store():Get(event.key), true) .. "  ")
				row.sub:SetText(E:FormatTime(event.at) .. "  " .. who .. Grey(L[KINDS[event.kind].title]))
			end,
		})
		frame.list:SetPoint("TOPLEFT", frame.dayTitle, "BOTTOMLEFT", -2, -6)
		frame.list:SetPoint("BOTTOMRIGHT")
		return frame
	end,
	show = function(frame) Update(frame) end,
	refresh = function(frame) Update(frame) end,
	count = function()
		local now = Store().Now()
		local count = #M:AgendaEvents(now, now + 86400)
		return count > 0 and count or nil
	end,
	enable = function() StartTicker() end,
	disable = function() StopTicker() end,
})
