-- EldoUI Chat, part 3: one list editor window for the chat lists (chat
-- colors, blocked phrases, channel mutes, alert keywords). Same look as
-- every EldoUI window: art-style panel, accent line, theme font, flat
-- boxes. One window per list, made on first use; Escape closes it.
--
--   M:OpenListEditor(spec)
--     spec.key         unique name ("phrases")
--     spec.title       window title
--     spec.help        one gray line under the title
--     spec.items()     the rows: a list of anything
--     spec.text(item)  main text of a row, and an optional gray second text
--     spec.controls    per row, right to left: { kind = "button" | "swatch",
--                      label = string or fn(item), width, tip,
--                      color = fn(item) (swatch), click = fn(item, index, control) }
--     spec.add         optional { hint, hint2 (a second field), button,
--                      func = fn(text, text2) -> ok, message }
--     spec.status()    optional text right of the title (counts, paused ...)
--     spec.extra       optional fn(window): add controls under the list
--                      (window.extraTop is where they start, measured
--                      from the top of window.body)
--     spec.footer      optional list of { label (string or fn()), width, tip,
--                      shown = fn(), click = fn(window) }
--     spec.options     optional options link target for the buttons with a
--                      tip (default: the Chat page)
--   M:RefreshListEditor(key)   redraw after a change made elsewhere
-- Written from scratch for EldoUI.
local _, E = ...
local L = E.L

local M = E:GetModule("Chat")

local ROWS = 10
local HELP_TOP, BODY_TOP, BODY_GAP = 36, 56, 4 -- help text, list body and the gap between them
local ROW_HEIGHT = 22
local editors = {}

-- The kit's input (E.UIKit.Input): flat box, accent edge on focus, a
-- dim hint (box.hint) while empty.
local function FlatInput(parent, width)
	return E.UIKit.Input(parent, { width = width, height = 20 })
end
M.FlatInput = FlatInput

-- The kit's tooltip (title, then the text in the secondary gray), and the
-- options link when one is given (Ctrl-click opens that page).
local function Tip(frame, title, text, link)
	E.UIKit.Tooltip(frame, title, text)
	if link then E:BindOptionsLink(frame, link) end
end
-- An editor's buttons open its spec.options, or the Chat page.
local CHAT_LINK = { page = "module:Chat" }
M.Tip = Tip

local function Swatch(parent)
	local swatch = CreateFrame("Button", nil, parent)
	swatch:SetSize(36, 16)
	E:SetTemplate(swatch)
	E:SkinHoverPress(swatch)
	return swatch
end

local function Label(value, item)
	if type(value) == "function" then return value(item) end
	return value
end

local function CreateEditor(spec)
	-- The shared tool window shell (E.UIKit.CreateToolWindow).
	local name = "EldoUI_ChatList_" .. spec.key
	local frame = E.UIKit.CreateToolWindow(name, { title = spec.title, width = spec.width or 420,
		height = 120 + ROWS * ROW_HEIGHT + (spec.extraHeight or 0), strata = "DIALOG",
		point = { "CENTER", UIParent, "CENTER", 0, 60 } })
	frame.spec = spec
	frame.offset = 0
	frame.status = E.UIKit.Text(frame.header, E.tokens.size.small, "RIGHT", "secondary")
	frame.status:SetPoint("RIGHT", -32, 0)
	frame.title:SetPoint("RIGHT", frame.status, "LEFT", -8, 0)
	frame.line = frame.headerLine

	frame.help = E.UIKit.Text(frame, E.tokens.size.small, "LEFT", "secondary")
	frame.help:SetPoint("TOPLEFT", 10, -HELP_TOP)
	frame.help:SetWidth((spec.width or 420) - 20)
	frame.help:SetWordWrap(true)
	frame.help:SetText(spec.help or "")
	-- The counts move under the help text when the title needs their room.
	frame.statusLine = E.UIKit.Text(frame, E.tokens.size.small, "LEFT", "secondary")
	frame.statusLine:SetPoint("TOPLEFT", frame.help, "BOTTOMLEFT", 0, -2)
	frame.statusLine:SetWidth((spec.width or 420) - 20)
	frame.statusLine:Hide()

	-- Everything below starts under the help text, however many lines it takes.
	local body = CreateFrame("Frame", nil, frame)
	body:SetPoint("TOPLEFT", frame.help, "BOTTOMLEFT", -10, -BODY_GAP)
	body:SetPoint("TOPRIGHT", frame.help, "BOTTOMRIGHT", 10, -BODY_GAP)
	body:SetHeight(1)
	frame.body = body
	frame.baseHeight = 120 + ROWS * ROW_HEIGHT + (spec.extraHeight or 0)

	local top = 0
	if spec.add then
		local twoFields = spec.add.hint2 ~= nil
		local width = (spec.width or 420) - 20 - 96
		local first = FlatInput(frame, twoFields and math.floor(width * 0.45) or width)
		first:SetPoint("TOPLEFT", body, "TOPLEFT", 10, top)
		first.hint:SetText(spec.add.hint or "")
		local second
		if twoFields then
			second = FlatInput(frame, width - first:GetWidth() - 6)
			second:SetPoint("LEFT", first, "RIGHT", 6, 0)
			second.hint:SetText(spec.add.hint2)
		end
		local add = M:FlatButton(frame, spec.add.button or L["Add"], 90, 20)
		add:SetPoint("TOPRIGHT", body, "TOPRIGHT", -10, top)
		local function DoAdd()
			local text, text2 = strtrim(first:GetText() or ""), second and strtrim(second:GetText() or "") or nil
			if text == "" then return end
			local ok, message = spec.add.func(text, text2)
			if ok then
				first:SetText("")
				if second then second:SetText("") end
				first:ClearFocus()
				if second then second:ClearFocus() end
			end
			frame.feedback = message
			M:RefreshListEditor(spec.key)
		end
		add:SetScript("OnClick", DoAdd)
		first:SetScript("OnEnterPressed", DoAdd)
		if second then second:SetScript("OnEnterPressed", DoAdd) end
		frame.input, frame.input2, frame.addButton = first, second, add
		top = top - 28
	end

	-- Rows; the wheel scrolls.
	local area = CreateFrame("Frame", nil, frame)
	area:SetPoint("TOPLEFT", body, "TOPLEFT", 8, top)
	area:SetPoint("TOPRIGHT", body, "TOPRIGHT", -8, top)
	area:SetHeight(ROWS * ROW_HEIGHT)
	E:SetTemplate(area, true)
	area:EnableMouseWheel(true)
	area:SetScript("OnMouseWheel", function(_, delta)
		local count = #spec.items()
		frame.offset = math.max(0, math.min(frame.offset - delta, math.max(0, count - ROWS)))
		M:RefreshListEditor(spec.key)
	end)
	frame.area = area
	frame.empty = E.UIKit.Text(area, E.tokens.size.small, "CENTER", "dim")
	frame.empty:SetPoint("CENTER")
	frame.empty:SetText(spec.emptyText or L["Nothing here yet."])
	frame.rows = {}
	for index = 1, ROWS do
		local row = CreateFrame("Frame", nil, area)
		row:SetHeight(ROW_HEIGHT - 2)
		row:SetPoint("TOPLEFT", 2, -2 - (index - 1) * ROW_HEIGHT)
		row:SetPoint("TOPRIGHT", -2, -2 - (index - 1) * ROW_HEIGHT)
		row.stripe = row:CreateTexture(nil, "BACKGROUND")
		row.stripe:SetAllPoints()
		row.stripe:SetColorTexture(1, 1, 1, index % 2 == 0 and E.tokens.hover.row / 2 or 0)
		row.controls = {}
		local anchor
		for c, control in ipairs(spec.controls or {}) do
			local widget
			if control.kind == "swatch" then
				widget = Swatch(row)
			else
				widget = M:FlatButton(row, Label(control.label, nil) or "", control.width or 60, 18)
			end
			if anchor then widget:SetPoint("RIGHT", anchor, "LEFT", -4, 0) else widget:SetPoint("RIGHT", -2, 0) end
			anchor = widget
			widget:SetScript("OnClick", function(self, mouse)
				if E:IsOptionsLinkClick(self, mouse) then return end
				if row.item ~= nil and control.click then control.click(row.item, row.index, self) end
				M:RefreshListEditor(spec.key)
			end)
			if control.tip then Tip(widget, control.tipTitle or (type(control.label) == "string" and control.label) or "", control.tip, spec.options or CHAT_LINK) end
			row.controls[c] = widget
		end
		row.text = E.UIKit.Text(row, E.tokens.size.label, "LEFT")
		row.text:SetPoint("LEFT", 6, 0)
		row.text:SetWordWrap(false)
		row.sub = E.UIKit.Text(row, E.tokens.size.small, "RIGHT", "secondary")
		if anchor then
			row.sub:SetPoint("RIGHT", anchor, "LEFT", -8, 0)
		else
			row.sub:SetPoint("RIGHT", -6, 0)
		end
		row.text:SetPoint("RIGHT", row.sub, "LEFT", -6, 0)
		frame.rows[index] = row
	end
	top = top - ROWS * ROW_HEIGHT - 6
	frame.extraTop = top
	if spec.extra then spec.extra(frame) end

	frame.feedbackText = E.UIKit.Text(frame, E.tokens.size.small, "LEFT")
	frame.feedbackText:SetPoint("BOTTOMLEFT", 10, 10)
	frame.feedbackText:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, 10)
	local anchor
	frame.footerButtons = {}
	for _, button in ipairs(spec.footer or {}) do
		local widget = M:FlatButton(frame, Label(button.label) or "", button.width or 90, 20)
		if anchor then widget:SetPoint("RIGHT", anchor, "LEFT", -4, 0) else widget:SetPoint("BOTTOMRIGHT", -10, 8) end
		anchor = widget
		widget:SetScript("OnClick", function(self, mouse)
			if E:IsOptionsLinkClick(self, mouse) then return end
			button.click(frame)
			M:RefreshListEditor(spec.key)
		end)
		if button.tip then Tip(widget, type(button.label) == "string" and button.label or "", button.tip, spec.options or CHAT_LINK) end
		frame.footerButtons[#frame.footerButtons + 1] = widget
	end
	-- With footer buttons the feedback line ends left of them, on its own
	-- bottom line (the buttons sit 2 lower).
	if anchor then
		frame.feedbackText:ClearAllPoints()
		frame.feedbackText:SetPoint("BOTTOMLEFT", 10, 10)
		frame.feedbackText:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMLEFT", -8, 2)
	end
	frame:HookScript("OnShow", function() M:RefreshListEditor(spec.key) end)
	return frame
end

-- The title keeps its whole name: when the counts on its right leave too
-- little room (Large text), they move to their own line under the help.
-- The window grows by whatever the help and that line need.
local function Layout(frame, statusText)
	local function Width(fs) return fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth() or fs:GetStringWidth() or 0 end
	frame.status:SetText(statusText)
	local room = (frame:GetWidth() or 0) - 12 - 32
	local below = frame.help
	if statusText ~= "" and Width(frame.title) + 8 + Width(frame.status) > room then
		frame.status:SetText("")
		frame.statusLine:SetText(statusText)
		frame.statusLine:Show()
		frame.title:SetPoint("RIGHT", frame.header, "RIGHT", -32, 0)
		below = frame.statusLine
	else
		frame.statusLine:Hide()
		frame.title:SetPoint("RIGHT", frame.status, "LEFT", -8, 0)
	end
	local used = frame.help:GetStringHeight() or 0
	frame.help:SetHeight(math.max(1, used))
	if below == frame.statusLine then
		local line = frame.statusLine:GetStringHeight() or 0
		frame.statusLine:SetHeight(math.max(1, line))
		used = used + 2 + line
	end
	frame.body:ClearAllPoints()
	frame.body:SetPoint("TOPLEFT", below, "BOTTOMLEFT", -10, -BODY_GAP)
	frame.body:SetPoint("TOPRIGHT", below, "BOTTOMRIGHT", 10, -BODY_GAP)
	frame:SetHeight(math.ceil(frame.baseHeight + math.max(0, HELP_TOP + used + BODY_GAP - BODY_TOP)))
end

function M:RefreshListEditor(key)
	local frame = editors[key]
	if not (frame and frame:IsShown()) then return end
	local spec = frame.spec
	local items = spec.items()
	frame.offset = math.max(0, math.min(frame.offset, math.max(0, #items - ROWS)))
	for index, row in ipairs(frame.rows) do
		local position = index + frame.offset
		local item = items[position]
		row.item, row.index = item, position
		row:SetShown(item ~= nil)
		if item ~= nil then
			local text, sub = spec.text(item)
			row.text:SetText(text or "")
			row.sub:SetText(sub or "")
			for c, control in ipairs(spec.controls or {}) do
				local widget = row.controls[c]
				if control.kind == "swatch" then
					local r, g, b = control.color(item)
					widget:SetBackdropColor(r or 1, g or 1, b or 1, 1)
				elseif type(control.label) == "function" then
					widget.text:SetText(control.label(item))
				end
				if control.shown then widget:SetShown(control.shown(item) and true or false) end
			end
		end
	end
	frame.empty:SetShown(#items == 0)
	Layout(frame, spec.status and spec.status() or "")
	frame.feedbackText:SetText(frame.feedback or "")
	for index, button in ipairs(spec.footer or {}) do
		local widget = frame.footerButtons[index]
		if type(button.label) == "function" then widget.text:SetText(button.label()) end
		if button.shown then widget:SetShown(button.shown() and true or false) end
	end
	if spec.refresh then spec.refresh(frame) end
end

function M:OpenListEditor(spec)
	local frame = editors[spec.key]
	if not frame then
		frame = CreateEditor(spec)
		editors[spec.key] = frame
	end
	frame.feedback = nil
	frame:Show()
	self:RefreshListEditor(spec.key)
	return frame
end

function M:ListEditor(key)
	return editors[key]
end

-- The look follows the theme like every other EldoUI window (the shell
-- repaints itself; this stays for callers).
function M:RestyleListEditors()
	for _, frame in pairs(editors) do
		E:SetPanelTemplate(frame)
		E:AccentTexture(frame.headerLine)
	end
end
