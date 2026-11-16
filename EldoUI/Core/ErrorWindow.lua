-- EldoUI error log window: the errors, warnings and blocked actions that
-- Core\Errors.lua caught, in a window of their own that works with every
-- module on or off. /eui errors opens it; the chat panel's Errors tab and
-- the options window link here.
--
--   +--------------------------------------------------------------+
--   | Error log                                                  x |
--   |==============================================================|
--   | [This session] [EldoUI only]                  12 logged      |
--   | 14:02  x3  attempt to index... [Report] | 2026-10-13 14:02 ... |
--   | 13:58  x1  blocked ...         [Report] | (selectable text)    |
--   | Reports are text you copy yourself; EldoUI sends nothing.    |
--   |--------------------------------------------------------------|
--   | 12 logged, 3 shown      [Select text] [Report] [Copy all] [Clear]
--   +--------------------------------------------------------------+
--
-- Report opens a copy box with the entry as a bug report: scrubbed of
-- the character's name, realm, guild, GUIDs and chat text, with the
-- EldoUI version, the game build and the error's signature, plus the
-- link to the public bug form. Nothing is ever sent by EldoUI itself.
local _, E = ...
local L = E.L
local Errors = E.errors

local LIST_SHARE = 0.42 -- part of the content width the list takes
local window

-- The window's own saved place, size and filters (account wide).
local function Store()
	if type(EldoUIDB) ~= "table" then return nil end
	EldoUIDB.errorWindow = type(EldoUIDB.errorWindow) == "table" and EldoUIDB.errorWindow or {}
	local store = EldoUIDB.errorWindow
	store.filters = type(store.filters) == "table" and store.filters or {}
	return store
end

-- True when an entry came from EldoUI or one of its plugin folders.
local function FromEldoUI(entry)
	local addon = entry.addon
	return type(addon) == "string" and (addon == "EldoUI" or addon:find("^EldoUI_") ~= nil)
end

-- The entries the filters let through, newest first.
local function Filtered()
	local store = Store()
	local filters = store and store.filters or {}
	local list = {}
	for _, entry in ipairs(Errors.entries) do
		if (not filters.session or entry.session == Errors.session) and (not filters.eldoui or FromEldoUI(entry)) then
			list[#list + 1] = entry
		end
	end
	table.sort(list, function(a, b) return (a.last or 0) > (b.last or 0) end)
	return list
end

-- The day (with its year, the text may be kept) and the time to the second,
-- in EldoUI's date format.
local function Moment(stamp)
	stamp = stamp or 0
	return ("%s, %s"):format(E:ShortDay(stamp, true), E:FormatTime(stamp, true))
end

-- One entry in the selectable detail pane: when, how often, where,
-- then the message, stack, and any saved local variables.
local function DetailText(entry)
	local lines = {
		E:Plural(entry.count or 1, "First %s, last %s, %d time", "First %s, last %s, %d times"):format(Moment(entry.first),
			Moment(entry.last), entry.count or 1),
		L["Addon: %s"]:format(entry.addon or L["Unknown addon"]),
	}
	if entry.zone then lines[#lines + 1] = L["Zone: %s"]:format(entry.zone) end
	if entry.combat then lines[#lines + 1] = L["In combat"] end
	lines[#lines + 1] = ""
	lines[#lines + 1] = entry.message or ""
	if entry.stack and entry.stack ~= "" then
		lines[#lines + 1] = ""
		lines[#lines + 1] = entry.stack
	end
	local locals = E.Plain(entry.locals)
	if type(locals) == "string" and locals:find("%S") then
		lines[#lines + 1] = ""
		lines[#lines + 1] = L["Local variables"]
		lines[#lines + 1] = Errors.ScrubLocals(locals)
	end
	return table.concat(lines, "\n")
end

-- The bug report of one entry in a copy box (see the top of the file).
local function ShowReport(entry)
	if not entry then return end
	local text = L["Open %s and paste this text into a new bug report."]:format(Errors.REPORT_URL)
		.. "\n\n" .. Errors:ReportText(entry)
	E:ShowCopyBox(L["Report this error"],
		L["Everything is selected. Press Ctrl+C. Names, realm, guild and chat text are left out, and EldoUI sends nothing by itself."],
		text)
end
function E:ShowErrorReport(entry) ShowReport(entry) end

local function KindWord(entry)
	if entry.kind == "warning" then return L["warning"] end
	if entry.kind == "blocked" then return L["blocked"] end
	return nil
end

---------------------------------------------------------------------------
-- Building
---------------------------------------------------------------------------
local Refresh

local function CreateRow(row)
	local Kit = E.UIKit
	row.fill = row:CreateTexture(nil, "BACKGROUND")
	row.fill:SetAllPoints()
	row.hover = row:CreateTexture(nil, "BACKGROUND", nil, 1)
	row.hover:SetAllPoints()
	row.hover:SetColorTexture(1, 1, 1, E.tokens.hover.row)
	row.hover:Hide()
	row.time = Kit.Text(row, E.tokens.size.small, "LEFT", "secondary")
	row.time:SetPoint("LEFT", 6, 0)
	row.time:SetWordWrap(false)
	row.time:SetWidth(54)
	row.count = Kit.Text(row, E.tokens.size.small, "RIGHT")
	row.count:SetPoint("LEFT", row.time, "RIGHT", 2, 0)
	row.count:SetWidth(34)
	row.report = Kit.Button(row, L["Report"], { width = 64, height = E.tokens.height.row - 4, size = E.tokens.size.small,
		tipTitle = L["Report"], tip = L["This error as a bug report to copy, with a link to the bug form. Nothing is sent by itself."] })
	row.report:SetPoint("RIGHT", -3, 0)
	row.report:SetScript("OnClick", function(self) ShowReport(self:GetParent().item) end)
	row.report:HookScript("OnSizeChanged", function() if window.Layout then window.Layout() end end)
	row.text = Kit.Text(row, E.tokens.size.label, "LEFT")
	row.text:SetPoint("LEFT", row.count, "RIGHT", 8, 0)
	row.text:SetPoint("RIGHT", row.report, "LEFT", -6, 0)
	row.text:SetWordWrap(false)
	row:SetScript("OnEnter", function(self) self.hover:Show() end)
	row:SetScript("OnLeave", function(self) self.hover:Hide() end)
	row:SetScript("OnClick", function(self)
		window.selected = self.item
		Refresh()
	end)
end

local function UpdateRow(row, entry)
	-- Today the time; an earlier day its date.
	row.time:SetText(E:When(entry.last or 0))
	row.time:SetWidth(math.max(54, math.ceil(row.time:GetStringWidth()) + 4))
	row.count:SetText("x" .. tostring(entry.count or 1))
	row.count:SetTextColor(E:TokenColor(entry.kind == "error" and "bad" or "warn"))
	local first = (entry.message or ""):match("^[^\n]*") or ""
	local kind = KindWord(entry)
	row.text:SetText(kind and (E:TextHex("warn") .. kind .. "|r " .. first) or first)
	if entry == window.selected then
		local r, g, b = E.UIKit.Accent()
		row.fill:SetColorTexture(r, g, b, E.tokens.pressed)
	else
		row.fill:SetColorTexture(0, 0, 0, 0)
	end
end

local function CreateWindow()
	local Kit = E.UIKit
	window = Kit.CreateToolWindow("EldoUI_ErrorWindow", {
		title = L["Error log"], width = 780, height = 480, strata = "DIALOG",
		resizable = { minWidth = 600, minHeight = 320 }, footer = Kit.TOOL_FOOTER, store = Store,
	})
	local content = window.content

	local store = Store()
	window.filters = Kit.ChipBar(content, {
		multi = true,
		selected = store and store.filters or nil,
		chips = {
			{ "session", L["This session"], L["Only errors seen since you logged in or reloaded."] },
			{ "eldoui", L["EldoUI only"], L["Only errors from EldoUI and its plugins. Errors from other addons are hidden."] },
		},
		onChange = function(selected)
			local saved = Store()
			if saved then
				saved.filters.session = selected.session or nil
				saved.filters.eldoui = selected.eldoui or nil
			end
			window.selected = nil
			Refresh()
		end,
	})
	window.filters:SetPoint("TOPLEFT", 0, 0)
	window.count = Kit.Text(content, E.tokens.size.small, "RIGHT", "secondary")
	window.count:SetPoint("TOPRIGHT", 0, -3)
	window.count:SetPoint("TOPLEFT", window.filters, "TOPRIGHT", 8, -3)

	-- List on the left, newest first.
	local listBox = CreateFrame("Frame", nil, content)
	listBox:SetPoint("TOPLEFT", 0, -26)
	listBox:SetPoint("BOTTOMLEFT", 0, 0)
	E:SetTemplate(listBox, true)
	window.listBox = listBox
	window.list = Kit.CreateList(listBox, {
		rowHeight = E.tokens.height.row, create = CreateRow, update = UpdateRow,
		empty = { title = L["No errors logged"], text = L["Nothing went wrong since the log was last cleared."] },
	})
	window.list:SetPoint("TOPLEFT", 2, -2)
	window.list:SetPoint("BOTTOMRIGHT", -2, 2)

	-- The selected entry on the right, as text you can select and copy.
	local holder = CreateFrame("Frame", nil, content)
	holder:SetPoint("TOPLEFT", listBox, "TOPRIGHT", 8, 0)
	holder:SetPoint("BOTTOMRIGHT", 0, 20)
	-- Privacy: what a report holds and that it never leaves on its own.
	-- It sits under the detail box and wraps; the box ends as far above the
	-- bottom as the text needs.
	window.privacy = Kit.Text(content, E.tokens.size.small, "LEFT", "secondary")
	window.privacy:SetPoint("TOPLEFT", holder, "BOTTOMLEFT", 0, -4)
	window.privacy:SetPoint("TOPRIGHT", holder, "BOTTOMRIGHT", 0, -4)
	window.privacy:SetJustifyV("TOP")
	window.privacy:SetWordWrap(true)
	window.privacy:SetText(L["Reports are text you copy yourself, without names or chat. EldoUI never sends anything."])
	E:SetTemplate(holder, true)
	local area = Kit.ScrollArea(holder)
	area:SetPoint("TOPLEFT", 6, -6)
	area:SetPoint("BOTTOMRIGHT", -6, 6)
	window.area = area
	local box = CreateFrame("EditBox", nil, area.child)
	box:SetMultiLine(true)
	box:SetAutoFocus(false)
	box:SetMaxLetters(0)
	box:SetPoint("TOPLEFT")
	box:SetPoint("TOPRIGHT")
	E:SetFont(box, E.tokens.size.label)
	box:SetTextColor(E:TokenColor("body"))
	-- Read only: typing puts the entry's text back.
	box:SetScript("OnTextChanged", function(self, userInput)
		if userInput then
			self:SetText(self.shown or "")
			self:HighlightText()
		end
		area.child:SetHeight(math.max(self:GetHeight() or 0, area:GetHeight() or 0))
		area:Update()
	end)
	box:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
	box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	holder:EnableMouse(true)
	holder:SetScript("OnMouseDown", function() box:SetFocus() end)
	window.box = box

	local function FitPrivacy()
		local height = math.ceil(window.privacy:GetStringHeight() or 0)
		holder:SetPoint("BOTTOMRIGHT", 0, math.max(height, 12) + 8)
	end
	E:RegisterThemed(window.privacy, FitPrivacy)
	local function Layout()
		local width = content:GetWidth() or 0
		local minimum = 200
		-- Long dates and larger buttons keep room for the message beside them.
		for _, row in ipairs(window.list:ShownRows()) do
			minimum = math.max(minimum, row.time:GetWidth() + row.count:GetWidth() + row.report:GetWidth()
				+ 80 + 29 + Kit.SCROLL_WIDTH + 4)
		end
		local wanted = math.max(math.floor(width * LIST_SHARE), minimum)
		if listBox:GetWidth() ~= wanted then listBox:SetWidth(wanted) end
		FitPrivacy()
		area.child:SetWidth(math.max((area.scroll:GetWidth() or 0), 50))
		box:SetWidth(area.child:GetWidth())
	end
	hooksecurefunc(window.list, "Refresh", Layout)
	window:HookScript("OnSizeChanged", Layout)
	window.Layout = Layout

	-- Footer: the status line and the buttons.
	local clear = Kit.Button(window.footer, L["Clear"], { width = 96, large = true, kind = "danger",
		tipTitle = L["Clear"], tip = L["Empty the error log. It can't be undone."] })
	clear:SetPoint("RIGHT", -8, 0)
	clear:SetScript("OnClick", function() E:AskClearErrorLog() end)
	local copyAll = Kit.Button(window.footer, L["Copy all"], { width = 96, large = true,
		tipTitle = L["Copy all"], tip = L["Every entry the filters show, as text to copy."] })
	copyAll:SetPoint("RIGHT", clear, "LEFT", -8, 0)
	copyAll:SetScript("OnClick", function()
		local parts = {}
		for _, entry in ipairs(Filtered()) do parts[#parts + 1] = Errors:Format(entry) end
		E:ShowCopyBox(L["EldoUI error log"], L["Everything is selected. Press Ctrl+C."], table.concat(parts, "\n\n"))
	end)
	local issue = Kit.Button(window.footer, L["Report"], { width = 96, large = true,
		tipTitle = L["Report"], tip = L["The shown entry as a bug report to copy, with a link to the bug form. Nothing is sent by itself."] })
	issue:SetPoint("RIGHT", copyAll, "LEFT", -8, 0)
	issue:SetScript("OnClick", function() ShowReport(window.shownEntry) end)
	local selectText = Kit.Button(window.footer, L["Select text"], { width = 96, large = true,
		tipTitle = L["Select text"], tip = L["Select the shown entry so Ctrl+C copies it."] })
	selectText:SetPoint("RIGHT", issue, "LEFT", -8, 0)
	selectText:SetScript("OnClick", function()
		box:SetFocus()
		box:HighlightText()
	end)
	window.buttons = { select = selectText, issue = issue, copyAll = copyAll, clear = clear }
	window.footerText:SetPoint("RIGHT", selectText, "LEFT", -8, 0)

	-- New errors show while the window is open, at most twice a second, so
	-- a storm of repeats leaves the text readable; a theme change repaints.
	local refreshQueued = false
	Errors:OnChange(window, function()
		if not window:IsShown() or refreshQueued then return end
		refreshQueued = true
		C_Timer.After(0.5, function()
			refreshQueued = false
			if window:IsShown() then
				Errors:MarkSeen()
				Refresh()
			end
		end)
	end)
	E:RegisterThemed(window, function(self) if self:IsShown() then Refresh() end end)
	window:HookScript("OnShow", function()
		Layout()
		Errors:MarkSeen()
		Refresh()
	end)
	return window
end

Refresh = function()
	if not window then return end
	local entries = Filtered()
	local found = false
	for _, entry in ipairs(entries) do
		if entry == window.selected then found = true break end
	end
	if not found then window.selected = nil end
	local shown = window.selected or entries[1]
	window.shownEntry = shown
	window.list:SetData(entries)
	-- The text is set again for another entry, or for a new count while
	-- the player is not selecting in it.
	local text = shown and DetailText(shown) or ""
	local box = window.box
	if box.entry ~= shown or (text ~= box.shown and not box:HasFocus()) then
		box.entry, box.shown = shown, text
		box:SetText(text)
	end
	window.buttons.select:SetEnabled(shown ~= nil)
	window.buttons.issue:SetEnabled(shown ~= nil)
	window.buttons.copyAll:SetEnabled(#entries > 0)
	window.buttons.clear:SetEnabled(#Errors.entries > 0)
	window.count:SetText(L["%d shown"]:format(#entries))
	local status = L["%d logged"]:format(#Errors.entries)
	if Errors.dropped > 0 then status = L["%d logged, %d skipped (too many at once)"]:format(#Errors.entries, Errors.dropped) end
	window.footerText:SetText(status)
end

---------------------------------------------------------------------------
-- API
---------------------------------------------------------------------------
-- show: true opens, false closes, nil toggles. Returns the window.
function E:ToggleErrorWindow(show)
	if not window then CreateWindow() end
	if show == nil then show = not window:IsShown() end
	if show then
		window:Open()
		Refresh()
	else
		window:Close()
	end
	return window
end

function E:ClearErrorLog()
	Errors:Clear()
	if window then
		window.selected = nil
		Refresh()
	end
end

-- One question for every Clear button on the log (this window and the
-- chat panel's Errors tab): both show the same log. onCleared runs after.
function E:AskClearErrorLog(onCleared)
	return E:ShowConfirm({ key = "ELDOUI_ERRORS_CLEAR", title = L["Clear the error log?"],
		text = L["Every logged error, warning and blocked action is removed."], accept = L["Clear"], danger = true,
		onAccept = function()
			E:ClearErrorLog()
			if onCleared then onCleared() end
		end })
end

E:AddCommand("errors", "[clear]  open EldoUI's error log, or empty it", function(arg)
	if (arg or ""):lower() == "clear" then
		E:ClearErrorLog()
		E:Print(L["Error log cleared."])
	else
		E:ToggleErrorWindow(true)
	end
end, "Troubleshooting")
