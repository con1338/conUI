-- EldoUI Social: the calendar (calendar).
--
-- Blizzard_Calendar (load on demand): CalendarFrame with the month grid of
-- 42 day buttons, and the event dialogs beside it (view and create event,
-- holiday, raid lockout, mass invite, event and texture pickers).
--   Skin  art-style panel instead of the stone frame, flat day cells, theme
--         fonts, flat buttons, inputs, check boxes and dropdowns in the dialogs
--   Move  drag by the top-left corner, scale (Modules/Social.lua window mover)
-- Event icons, today's glow, the selected day and the darkened days of
-- other months stay Blizzard's: they carry the meaning.
-- Nothing is accepted, declined or created for the player.
-- Written from scratch for EldoUI; no code or media from other addons.
local _, E = ...

local M = E:GetModule("Social")
local K = M.kit
local Usable, Try = K.Usable, K.Try

local ID = "calendar"
local ADDON = "Blizzard_Calendar"
local DAYS = 42 -- CALENDAR_MAX_DAYS_PER_MONTH: six weeks

local function Skin() return M.active and E:BlizzardAllowed(ID, "skin") end

local dayParts = setmetatable({}, { __mode = "k" }) -- day button -> { bg, right, bottom }

local BORDER = { "TopLeft", "TopMiddle", "TopRight", "LeftTop", "LeftMiddle", "LeftBottom",
	"RightTop", "RightMiddle", "RightBottom", "BottomLeft", "BottomMiddle", "BottomRight" }

---------------------------------------------------------------------------
-- Day cells
---------------------------------------------------------------------------
local function DayParts(button)
	local parts = dayParts[button]
	if parts then return parts end
	parts = {}
	parts.bg = button:CreateTexture(nil, "BACKGROUND", nil, -8)
	parts.bg:SetAllPoints()
	parts.bg:SetColorTexture(unpack(E.tokens.track))
	parts.right = button:CreateTexture(nil, "BACKGROUND", nil, -7)
	parts.right:SetPoint("TOPRIGHT")
	parts.right:SetPoint("BOTTOMRIGHT")
	parts.right:SetWidth(E.pixel)
	parts.right:SetColorTexture(unpack(E.tokens.edge.divider))
	parts.bottom = button:CreateTexture(nil, "BACKGROUND", nil, -7)
	parts.bottom:SetPoint("BOTTOMLEFT")
	parts.bottom:SetPoint("BOTTOMRIGHT")
	parts.bottom:SetHeight(E.pixel)
	parts.bottom:SetColorTexture(unpack(E.tokens.edge.divider))
	dayParts[button] = parts
	return parts
end

local function StyleDays()
	local db = M.db.calendar
	for i = 1, DAYS do
		local button = _G["CalendarDayButton" .. i]
		if Usable(button) then
			local normal = button.GetNormalTexture and button:GetNormalTexture()
			local parts = DayParts(button)
			-- Flat cells: Blizzard's parchment day art goes invisible.
			K.Fade(normal, db.flatDays, ID)
			parts.bg:SetShown(db.flatDays and true or false)
			parts.right:SetShown(db.flatDays and true or false)
			parts.bottom:SetShown(db.flatDays and true or false)
			local date = _G["CalendarDayButton" .. i .. "DateFrameDate"]
			if date and date.SetFont then K.Fonts(db.dateSize or 13, date) end
		end
	end
end

---------------------------------------------------------------------------
-- Dialogs
---------------------------------------------------------------------------
local DIALOGS = { "CalendarViewHolidayFrame", "CalendarViewRaidFrame", "CalendarViewEventFrame", "CalendarCreateEventFrame",
	"CalendarMassInviteFrame", "CalendarEventPickerFrame", "CalendarTexturePickerFrame" }
local CLOSE = { "CalendarViewHolidayCloseButton", "CalendarViewRaidCloseButton", "CalendarViewEventCloseButton",
	"CalendarCreateEventCloseButton", "CalendarMassInviteCloseButton" }
local BUTTONS = { "CalendarViewEventAcceptButton", "CalendarViewEventTentativeButton", "CalendarViewEventDeclineButton",
	"CalendarViewEventRemoveButton", "CalendarCreateEventInviteButton", "CalendarCreateEventMassInviteButton",
	"CalendarCreateEventRaidInviteButton", "CalendarCreateEventCreateButton", "CalendarMassInviteAcceptButton",
	"CalendarEventPickerCloseButton", "CalendarTexturePickerCancelButton", "CalendarTexturePickerAcceptButton" }
local EDITS = { "CalendarCreateEventTitleEdit", "CalendarCreateEventInviteEdit", "CalendarMassInviteMinLevelEdit", "CalendarMassInviteMaxLevelEdit" }
local CHECKS = { "CalendarCreateEventAutoApproveCheck", "CalendarCreateEventLockEventCheck" }

local function DialogRoots()
	local roots = {}
	for _, name in ipairs(DIALOGS) do
		if Usable(_G[name]) then roots[#roots + 1] = _G[name] end
	end
	return roots
end

local function SkinDialogs()
	for _, name in ipairs(DIALOGS) do
		local dialog = _G[name]
		if Usable(dialog) then
			K.SkinDialog(dialog)
			E:SkinScrollBar(dialog.ScrollBar)
		end
	end
	for _, name in ipairs(CLOSE) do E:SkinCloseButton(_G[name]) end
	for _, name in ipairs(BUTTONS) do E:SkinButton(_G[name]) end
	for _, name in ipairs(EDITS) do E:SkinEditBox(_G[name]) end
	for _, name in ipairs(CHECKS) do E:SkinCheckBox(_G[name]) end
	E:SkinAlphaZero(_G.CalendarViewEventDivider, _G.CalendarCreateEventDivider)
	local create = _G.CalendarCreateEventFrame
	if Usable(create) then
		for _, key in ipairs({ "EventTypeDropdown", "HourDropdown", "MinuteDropdown", "AMPMDropdown" }) do
			E:SkinDropdown(create[key])
		end
	end
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
local function SkinWindow()
	local frame = _G.CalendarFrame
	for _, part in ipairs(BORDER) do E:SkinAlphaZero(_G["CalendarFrame" .. part .. "Texture"]) end
	E:SkinAlphaZero(_G.CalendarMonthBackground, _G.CalendarYearBackground)
	for i = 1, 7 do E:SkinAlphaZero(_G["CalendarWeekday" .. i .. "Background"]) end
	E:SkinPanel(frame, { strip = false, transparent = M.db.transparent, accentOffset = 30, insets = false, title = false, close = false })
	E:SkinCloseButton(_G.CalendarCloseButton)
	E:SkinDropdown(frame.FilterButton)
end

local function StyleText()
	local db = M.db.calendar
	local month, year = _G.CalendarMonthName, _G.CalendarYearName
	if month and month.SetFont then
		E:SetFont(month, E.tokens.size.dialogTitle)
		month:SetTextColor(1, 1, 1)
	end
	if year and year.SetFont then
		E:SetFont(year, E.tokens.size.small)
		year:SetTextColor(unpack(E.media.text.secondary))
	end
	for i = 1, 7 do
		local name = _G["CalendarWeekday" .. i .. "Name"]
		if name and name.SetFont then
			E:SetFont(name, db.weekdaySize or E.tokens.size.label)
			name:SetTextColor(unpack(E.media.text.secondary))
		end
	end
end

M:AddPart({
	id = ID,
	addon = ADDON,
	install = { skin = true },
	setup = function()
		if not Usable(_G.CalendarFrame) then error("EldoUI Social: CalendarFrame is missing") end
	end,
	apply = function(part)
		if Skin() then
			E:SkinRecord(ID, _G.CalendarFrame, function()
				if not part.skinned then
					part.skinned = true
					SkinWindow()
				end
				E:SetPanelTransparent(_G.CalendarFrame, M.db.transparent)
				StyleText()
				StyleDays()
			end)
			K.Want(part, "dialogs", DialogRoots(), M.db.calendar.dialogs, function()
				if part.dialogs then return end
				part.dialogs = true
				Try(SkinDialogs)
			end)
		end
		M:ApplyWindow("calendar")
	end,
	undo = function()
		K.Unfade(ID)
		for _, parts in pairs(dayParts) do
			parts.bg:Hide()
			parts.right:Hide()
			parts.bottom:Hide()
		end
		M:RestoreWindow("calendar")
	end,
})

---------------------------------------------------------------------------
-- Options
---------------------------------------------------------------------------
M:AddOptions({ { type = "tab", label = "Calendar" } })
M:AddOptions(M:SwitchOptions(ID, { { "calendar", "Calendar" } }))
M:AddOptions({
	{ type = "header", label = "Month" },
	{ type = "toggle", disabled = E:BlizzardNeeds(ID, "skin"), key = "calendar.flatDays", label = "Flat day cells",
		desc = "Plain dark cells with thin dividers instead of Blizzard's parchment days. Event icons and today's glow stay." },
	{ type = "range", disabled = E:BlizzardNeeds(ID, "skin"), key = "calendar.dateSize", label = "Day number size", min = 9, max = 18, step = 1, desc = "Size of the day numbers." },
	{ type = "range", disabled = E:BlizzardNeeds(ID, "skin"), key = "calendar.weekdaySize", label = "Weekday name size", min = 9, max = 16, step = 1, desc = "Size of the weekday names above the grid." },
	{ type = "header", label = "Event windows" },
	{ type = "toggle", disabled = E:BlizzardNeeds(ID, "skin"), key = "calendar.dialogs", label = "Skin event windows",
		desc = "The view, create, holiday, raid and picker windows next to the calendar get the EldoUI look too." },
})
