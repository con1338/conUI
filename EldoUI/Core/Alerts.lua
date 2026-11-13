-- EldoUI notices: one queue for everything EldoUI shows for a moment.
--
--   E:PushAlert({
--       title = "Talents", text = "Your saved build differs from the one you use.",
--       icon = 132222, duration = 15,
--       actions = { { label = "Apply", func = function() ... end }, { label = "Later" } },
--   })
--
-- When the Alerts & Messages module offers alerts with buttons
-- (Notifications:PushAlert) the alert goes there. A plain alert (no
-- buttons) goes into its alert lane when that lane is EldoUI's. Otherwise
-- EldoUI shows its own small card at the alert lane's place (top of the
-- screen when the module is off): panel look, icon, accent title, text and
-- up to three buttons. A card stays while the mouse is over it; right-click
-- or the x closes it; a button runs its function, then closes the card.
-- At most three cards show at once, the rest wait their turn.
-- E:DismissAlert(key) takes an alert away again (its card and a waiting one).
--
-- While the Alerts & Messages lane shows its own toasts, the cards line up
-- after the last of them (in the lane's direction) instead of on top, and
-- move along when the lane changes.
--
-- data: title, text, icon (file ID, path or atlas), actions = { { label,
-- func, tip, now } } (func(data, card); now = true closes the card at once,
-- without the slide), duration (seconds, default 8; 20 with buttons), sound
-- (media id), key (a new alert with the same key replaces the old one),
-- closable (true: a plain alert that must have its x, such as a long
-- brief, shows as this card and never as a lane toast), lines = { { text,
-- icon, func, tip } } (a checklist under the text: each line with a func is
-- a link that runs it on a click and keeps the card; an alert with lines
-- always shows as this card), options = { page, key } (where Ctrl-click
-- on the card or toast goes: the pushing module's own settings; without
-- it, the alert lane's). A module calls M:PushAlert(data), which fills
-- options with its own page.
--
-- One lane for every notice. The cards above are one holder of a family:
-- the alert lane's toasts, the zone toast, the rare card and the low-mana
-- note of a ready check are the others. Each holder keeps its own mover
-- and look; the queue here decides for all of them:
--   * a holder shows as many notices at once as it has room for, the rest
--     wait in the order they came
--   * a notice with a key refreshes the one on screen with that key, or
--     takes the place of the waiting one
--   * a waiting notice without buttons drops away once it waited longer
--     than its holder allows: notices are short-lived, and nothing is
--     summed up afterwards
--   * the time on screen is kept on the shared ticker; a notice never
--     closes while the mouse is over it, and a holder that shows a running
--     time is told once a second
--   * a holder can hold notices back for a while (in combat, say); they
--     show when it is ready again
-- Reminders (a missing buff, a weapon enchant) are not notices: they stay
-- up while the thing is missing, in their own frame.
--
--   E:RegisterNoticeHolder(id, holder)  holder fields, all optional but show:
--     show(data)          draws it and returns its frame (nil: dropped)
--     refresh(frame, data) the same key again while it shows
--     hide(frame, data, now) takes it away (now: at once, no animation);
--                         the holder calls E:NoticeClosed(frame) once gone
--     slots               number, or function: notices on screen at once (1)
--     ready(data)         false holds notices back for now
--     usable()            false: the holder is off and takes no notices
--     duration            seconds on screen, number or function(data);
--                         data.duration wins; none: until closed
--     wait                seconds a notice may wait before it drops away
--     most                notices waiting at once (20); the oldest drop
--     hovered(frame)      true keeps it up (default: the mouse is over it)
--     tick()              called once a second while one of its notices shows
--     changed()           its waiting count changed
--     waiting             the list to keep its waiting notices in
--   E:PushNotice(id, data) -> id, frame | "waiting" | nil
--   E:CloseNotice(frame[, now]), E:NoticeClosed(frame), E:PumpNotices([id]),
--   E:DropNotices(id[, now]), E:NoticeWaiting(id), E:NoticeQueue()
local _, E = ...
local L = E.L

local MAX_SHOWN = 3
local MAX_WAITING = 20
local WIDTH = 300
local cards, pool, waiting = {}, {}, {}
-- Every notice on screen, any holder: frame -> { id, frame, data, expires }.
local onScreen = {}

local function HasAtlas(name)
	return type(name) == "string" and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil
end

local function Accent()
	local c = E.media.accentColor
	return c[1], c[2], c[3]
end

-- The Alerts & Messages lane's mover (same size and place as the lane),
-- when that module made one.
local function Anchor()
	return E.movers and E.movers.EldoUI_AlertLane or nil
end

local GAP = 4

local function Notifications()
	local notifications = E.GetModule and E:GetModule("Notifications")
	if notifications and notifications.active then return notifications end
	return nil
end

-- The last frame the Alerts & Messages lane shows right now (its toasts,
-- the talking head or Blizzard alerts it moved), and the way the lane
-- grows ("DOWN" or "UP"). The lane module names its own last frame after
-- each layout; no other frame is looked at, because UIParent also holds
-- frames addon code may not touch at all.
local function LaneTail()
	local notifications = Notifications()
	if not notifications then return nil end
	local alerts = type(notifications.db) == "table" and notifications.db.alerts
	local growth = type(alerts) == "table" and alerts.growth == "UP" and "UP" or "DOWN"
	local tail = notifications.laneTail
	if type(tail) ~= "table" or type(tail.IsShown) ~= "function" or not tail:IsShown() then return nil, growth end
	for _, card in ipairs(cards) do
		if card == tail then return nil, growth end
	end
	return tail, growth
end
E.AlertLaneTail = LaneTail

local function Layout()
	local lane = Anchor()
	local tail, growth = nil, "DOWN"
	if #cards > 0 then tail, growth = LaneTail() end
	local up = tail ~= nil and growth == "UP"
	local previous = tail
	for _, card in ipairs(cards) do
		card:ClearAllPoints()
		if previous and up then
			card:SetPoint("BOTTOM", previous, "TOP", 0, GAP)
		elseif previous then
			card:SetPoint("TOP", previous, "BOTTOM", 0, -GAP)
		elseif lane then
			card:SetPoint("TOP", lane, "TOP", 0, 0)
		else
			card:SetPoint("TOP", UIParent, "TOP", 0, -60)
		end
		previous = card
	end
end

-- The lane lays itself out again when a toast comes or goes: the cards
-- follow it. The hook is laid again when the function was swapped since
-- (a reload of the module, a test stub put back).
local hookedLane, laneAgain
local function FollowLane()
	local notifications = Notifications()
	if not (notifications and type(notifications.LayoutLane) == "function") then return end
	if hookedLane and notifications.LayoutLane == hookedLane then return end
	hooksecurefunc(notifications, "LayoutLane", function()
		if #cards == 0 then return end
		Layout()
		-- A toast from the lane's pool is shown right after its layout:
		-- once more on the next frame, when it counts as shown.
		if not laneAgain and C_Timer and C_Timer.After then
			laneAgain = true
			C_Timer.After(0, function()
				laneAgain = false
				if #cards > 0 then Layout() end
			end)
		end
	end)
	hookedLane = notifications.LayoutLane
end

local function Release(card)
	-- Once only: a slide-out can finish after ClearAlerts already released
	-- the card, and a card twice in the pool would later anchor to itself.
	local found
	for index, active in ipairs(cards) do
		if active == card then table.remove(cards, index) found = true break end
	end
	if not found then return end
	card:Hide()
	card.data, card.closing = nil, nil
	pool[#pool + 1] = card
	Layout()
	E:NoticeClosed(card)
end

local function Dismiss(card)
	if card.closing then return end
	card.closing = true
	if onScreen[card] then onScreen[card].closing = true end
	E:SlideOut(card, "UP", function() Release(card) end)
end

local function RunAction(card, action)
	-- "now": the card is gone before the action runs (a screenshot).
	if action.now then
		card.closing = true
		if onScreen[card] then onScreen[card].closing = true end
		card:Hide()
	end
	if type(action.func) == "function" then
		local ok, err = pcall(action.func, card.data, card)
		if not ok then geterrorhandler()(err) end
	end
	if action.now then Release(card) else Dismiss(card) end
end

local function CreateCard()
	local card = CreateFrame("Button", nil, UIParent)
	card:SetFrameStrata("DIALOG")
	card:SetWidth(WIDTH)
	card:RegisterForClicks("RightButtonUp")
	card:SetClampedToScreen(true)
	E:SetPanelTemplate(card, false)
	card.iconBox = CreateFrame("Frame", nil, card)
	card.iconBox:SetSize(36, 36)
	card.iconBox:SetPoint("TOPLEFT", 8, -8)
	E:SetTemplate(card.iconBox)
	card.icon = card.iconBox:CreateTexture(nil, "ARTWORK")
	card.icon:SetPoint("TOPLEFT", E.pixel, -E.pixel)
	card.icon:SetPoint("BOTTOMRIGHT", -E.pixel, E.pixel)
	E:TrimIcon(card.icon)
	card.close = CreateFrame("Button", nil, card, "UIPanelCloseButton")
	card.close:SetSize(18, 18)
	card.close:SetPoint("TOPRIGHT", -2, -2)
	E:SkinCloseButton(card.close)
	card.close:SetScript("OnClick", function() Dismiss(card) end)
	card.title = E:CreateText(card, E.tokens.size.small, "LEFT")
	-- The texts get their widths in Measure, so they are measured at the
	-- width they are drawn at.
	card.title:SetPoint("TOPLEFT", card.iconBox, "TOPRIGHT", 8, -1)
	card.title:SetWordWrap(true)
	card.text = E:CreateText(card, E.tokens.size.body, "LEFT")
	card.text:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", 0, -3)
	card.text:SetWordWrap(true)
	card.text:SetJustifyV("TOP")
	card.buttons = {}
	card.rows = {}
	card:SetScript("OnClick", function(self, button)
		if button == "RightButton" then Dismiss(self) end
	end)
	-- The tooltip names the clicks: right-click closes, Ctrl-click opens
	-- the settings behind the alert.
	card:SetScript("OnEnter", function(self)
		self:SetBackdropBorderColor(Accent())
		if not self.data then return end
		E.UIKit.AnchorTooltip(self)
		E:TooltipHint(GameTooltip, { L["Right-click"], L["close it"] })
		GameTooltip:Show()
	end)
	card:SetScript("OnLeave", function(self)
		E:SetPanelTemplate(self, false)
		GameTooltip:Hide()
	end)
	E:BindOptionsLink(card, function(own)
		local data = own.data
		return data and (data.options or { page = "module:Notifications" }) or nil
	end)
	return card
end

local LINE_HEIGHT = 18
-- Card geometry: the icon column on the left, the text column next to it.
local PAD = 8          -- the card's edge to the icon and to the text top
local ICON = 36        -- the icon box
local COLUMN = PAD + ICON + 8 -- the card's left edge to the text column
local RIGHT_INSET = 10 -- the text column to the card's right edge
local CLOSE = 18       -- the x button
local ROW_GAP = 4      -- between buttons, and between button rows

-- The card's width: wider with Large text, so a long notice keeps a
-- readable line length instead of growing very tall.
local function CardWidth()
	local scale = E.TextScale and E:TextScale() or 1
	return math.floor(WIDTH * (1 + (scale - 1) * 0.5) + 0.5)
end

-- One checklist line: icon, text, and a click that runs its func.
local function LineRow(card, index)
	local row = card.rows[index]
	if row then return row end
	row = CreateFrame("Button", nil, card)
	row:SetHeight(LINE_HEIGHT)
	row:RegisterForClicks("LeftButtonUp")
	row.hover = row:CreateTexture(nil, "HIGHLIGHT")
	row.hover:SetAllPoints()
	row.hover:SetColorTexture(1, 1, 1, E.tokens.hover.row)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(14, 14)
	row.icon:SetPoint("LEFT", 2, 0)
	E:TrimIcon(row.icon)
	row.text = E:CreateText(row, E.tokens.size.label, "LEFT")
	row.text:SetPoint("LEFT", row.icon, "RIGHT", 5, 0)
	row.text:SetWordWrap(true)
	card.rows[index] = row
	return row
end

-- The checklist's content. Where each line sits is Measure's job.
local function FillLines(card, lines)
	for index = 1, math.max(#card.rows, #lines) do
		local line = lines[index]
		local row = (line and LineRow(card, index)) or card.rows[index]
		if row then
			row:SetShown(line ~= nil)
			row.line = line
			if line then
				local icon = line.icon
				if HasAtlas(icon) then row.icon:SetAtlas(icon) elseif icon then row.icon:SetTexture(E.ClientIcon and E:ClientIcon(icon) or icon) end
				row.icon:SetShown(icon ~= nil)
				E:SetFont(row.text, E.tokens.size.label)
				row.text:SetText(line.text or "")
				local link = type(line.func) == "function"
				if link then row.text:SetTextColor(E:TokenColor("accent")) else row.text:SetTextColor(1, 1, 1) end
				row.hover:SetShown(link)
				row:EnableMouse(link)
				row:SetScript("OnClick", link and function(self)
					E:KeepNotice(card, 10)
					local ok, err = pcall(self.line.func, card.data, card)
					if not ok then geterrorhandler()(err) end
				end or nil)
				if link then E.UIKit.Tooltip(row, line.label or line.text, line.tip) end
			end
		end
	end
end

local function TextHeight(fontString, minimum)
	local text = fontString:GetText()
	if not text or text == "" then return 0 end
	return math.max(math.ceil(fontString:GetStringHeight() or 0), minimum or 0)
end

-- Lay the card out from its content: every text gets its final width
-- first (after the icon, the x, the font and Large text), then is
-- measured; the checklist and the buttons go below all of it, the buttons
-- wrap onto more rows when they do not fit side by side, and the card
-- takes the height of everything. Run again whenever the content, the
-- font, the text size or the theme changes; a card from the pool is
-- measured anew each time.
local function Measure(card)
	local width = CardWidth()
	card:SetWidth(width)
	local column = width - COLUMN - RIGHT_INSET
	card.title:SetWidth(width - COLUMN - 2 - CLOSE - 4)
	card.text:SetWidth(column)
	local titleHeight = TextHeight(card.title, 0)
	local textHeight = TextHeight(card.text, 0)
	local top = PAD + 1 + titleHeight + 3 + textHeight
	-- The checklist: one row per line, each as tall as its wrapped text.
	local rowWidth = width - (COLUMN - 4) - PAD
	local rowsShown = false
	for _, row in ipairs(card.rows) do
		if row:IsShown() and row.line then
			if not rowsShown then top, rowsShown = top + 3, true end
			row:SetWidth(rowWidth)
			row.text:SetWidth(rowWidth - 2 - 14 - 5 - 2)
			local height = math.max(LINE_HEIGHT, TextHeight(row.text, 12) + 4)
			row:SetHeight(height)
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", card, "TOPLEFT", COLUMN - 4, -top)
			top = top + height + 1
		end
	end
	top = math.max(PAD + ICON, top)
	-- The buttons: side by side while they fit the text column, then on
	-- the next row. A label longer than the whole column wraps inside its
	-- button, which grows taller, so it stays readable.
	local x, rowTop, rowHeight, any = 0, top + 6, 0, false
	for _, button in ipairs(card.buttons) do
		if button:IsShown() then
			local label = button:GetFontString()
			if label then label:SetWordWrap(false) end
			E.UIKit.FitButton(button, 70)
			local buttonHeight = E.tokens.height.button
			if label then buttonHeight = math.max(buttonHeight, math.ceil(TextHeight(label, 0) + 8)) end
			if button:GetWidth() > column then
				button:SetWidth(column)
				if label then
					label:SetWordWrap(true)
					buttonHeight = math.max(buttonHeight, math.ceil(TextHeight(label, 0) + 8))
				end
			end
			button:SetHeight(buttonHeight)
			if any and x + button:GetWidth() > column then
				rowTop = rowTop + rowHeight + ROW_GAP
				x, rowHeight = 0, 0
			end
			button:ClearAllPoints()
			button:SetPoint("TOPLEFT", card, "TOPLEFT", COLUMN + x, -rowTop)
			x = x + button:GetWidth() + ROW_GAP
			rowHeight = math.max(rowHeight, buttonHeight)
			any = true
		end
	end
	local height = any and (rowTop + rowHeight + PAD) or (top + PAD)
	card:SetHeight(math.ceil(height))
	card.measuredScale = E.TextScale and E:TextScale() or 1
	return height
end

local function Fill(card, data)
	card.data = data
	card.closing = nil
	local actions = type(data.actions) == "table" and data.actions or {}
	E:SetPanelTemplate(card, false)
	local icon = data.icon or E.media.icon
	if HasAtlas(icon) then card.icon:SetAtlas(icon) else card.icon:SetTexture(E.ClientIcon and E:ClientIcon(icon) or icon) end
	E:SetFont(card.title, E.tokens.size.small)
	E:SetFont(card.text, E.tokens.size.body)
	card.title:SetText(data.title or "")
	card.title:SetTextColor(E:TokenColor("accent"))
	card.text:SetText(data.text or "")
	card.text:SetTextColor(1, 1, 1)
	FillLines(card, type(data.lines) == "table" and data.lines or {})
	for index = 1, math.max(#card.buttons, #actions) do
		local action = actions[index]
		local button = card.buttons[index]
		if action and index <= 3 and not button then
			button = E.UIKit.Button(card, "", 80)
			card.buttons[index] = button
		end
		if button then
			button:SetShown(action ~= nil and index <= 3)
			if action and index <= 3 then
				button:SetText(action.label or action[1] or OKAY)
				button:SetScript("OnClick", function() RunAction(card, action) end)
				E.UIKit.Tooltip(button, action.label or action[1], action.tip)
			end
		end
	end
	Measure(card)
	if data.sound then E:PlayMedia(data.sound) end
end

-- Measure every card on screen again and line them up: once more on the
-- next frame after a card shows (the game knows a new text's final
-- metrics by then), and after each font, text size or theme change.
local function Remeasure()
	for _, card in ipairs(cards) do
		if card.data then Measure(card) end
	end
	Layout()
end

local remeasureQueued
local function RemeasureSoon()
	if remeasureQueued or not (C_Timer and C_Timer.After) then return end
	remeasureQueued = true
	C_Timer.After(0, function()
		remeasureQueued = false
		if #cards > 0 then Remeasure() end
	end)
end

if E.OnThemeChanged then
	-- At once, and on the next frame: the buttons take their new font
	-- after the theme refreshers have run.
	E:OnThemeChanged("alerts", function()
		if #cards == 0 then return end
		Remeasure()
		RemeasureSoon()
	end)
end

local function Show(data)
	FollowLane()
	local card = table.remove(pool) or CreateCard()
	Fill(card, data)
	cards[#cards + 1] = card
	Layout()
	E:SlideIn(card, "UP")
	RemeasureSoon()
	return card
end

---------------------------------------------------------------------------
-- The queue
---------------------------------------------------------------------------
local holders, holderOrder = {}, {}
local since = setmetatable({}, { __mode = "k" }) -- waiting data -> { seq, at }
local counter = 0
local DUE, TICK = "EldoUI:notices", "EldoUI:notices:tick"
local Arm

local function Report(ok, err)
	if not ok then geterrorhandler()(err) end
	return ok
end

local function Slots(holder)
	local slots = holder.slots
	if type(slots) == "function" then
		local ok, value = pcall(slots)
		slots = ok and value or 1
	end
	return math.max(1, math.floor(tonumber(slots) or 1))
end

local function Usable(holder)
	if not holder.usable then return true end
	local ok, usable = pcall(holder.usable)
	return ok and usable and true or false
end

local function Ready(holder, data)
	if not holder.ready then return true end
	local ok, ready = pcall(holder.ready, data)
	return ok and ready ~= false
end

-- Seconds on screen; nil: until it is closed.
local function Lasts(holder, data)
	local seconds = data.duration
	if seconds == nil then
		seconds = holder.duration
		if type(seconds) == "function" then
			local ok, value = pcall(seconds, data)
			seconds = ok and value or nil
		end
	end
	seconds = tonumber(seconds)
	return (seconds and seconds > 0) and seconds or nil
end

-- How long it may wait for its turn; nil: as long as it takes (a notice
-- with buttons or a checklist waits for the player).
local function WaitLimit(holder, data)
	if (type(data.actions) == "table" and #data.actions > 0) or type(data.lines) == "table" or data.closable then return nil end
	local limit = tonumber(holder.wait)
	return (limit and limit > 0) and limit or nil
end

local function Hovered(holder, frame)
	if holder.hovered then
		local ok, hovered = pcall(holder.hovered, frame)
		return ok and hovered and true or false
	end
	return type(frame.IsMouseOver) == "function" and frame:IsMouseOver() and true or false
end

local function Changed(holder)
	if holder.changed then Report(pcall(holder.changed)) end
end

local function Stamp(data)
	if not since[data] then
		counter = counter + 1
		since[data] = { seq = counter, at = GetTime() }
	end
	return since[data]
end

local function ShowIn(holder, data)
	local ok, frame = pcall(holder.show, data)
	if not Report(ok, frame) or not frame then return nil end
	local entry = { id = holder.id, frame = frame, data = data }
	local seconds = Lasts(holder, data)
	entry.expires = seconds and (GetTime() + seconds) or nil
	holder.shown[#holder.shown + 1] = entry
	onScreen[frame] = entry
	return frame
end

local function Pump(holder)
	if holder.pumping then return end
	holder.pumping = true
	local list, moved = holder.waiting, false
	while #list > 0 and #holder.shown < Slots(holder) and Usable(holder) and Ready(holder, list[1]) do
		local data = table.remove(list, 1)
		since[data] = nil
		moved = true
		ShowIn(holder, data) -- a holder that cannot draw it after all drops it
	end
	holder.pumping = false
	if moved then Changed(holder) end
end

local function Close(entry, now)
	if entry.closing and not now then return end
	entry.closing = true
	local holder = holders[entry.id]
	if holder and holder.hide then Report(pcall(holder.hide, entry.frame, entry.data, now)) end
end

-- Notices whose time is up close (unless the mouse is over them: then a
-- second later), waiting ones too old to matter drop away.
local function Due()
	local now = GetTime()
	local closing = {}
	for frame, entry in pairs(onScreen) do
		if entry.expires and not entry.closing and now >= entry.expires - 0.001 then
			local holder = holders[entry.id]
			if holder and Hovered(holder, frame) then entry.expires = now + 1 else closing[#closing + 1] = entry end
		end
	end
	for _, entry in ipairs(closing) do Close(entry) end
	for _, id in ipairs(holderOrder) do
		local holder = holders[id]
		local dropped = false
		for index = #holder.waiting, 1, -1 do
			local data = holder.waiting[index]
			local limit = WaitLimit(holder, data)
			if limit and now - Stamp(data).at >= limit - 0.001 then
				table.remove(holder.waiting, index)
				since[data] = nil
				dropped = true
			end
		end
		if dropped then Changed(holder) end
		Pump(holder)
	end
	Arm()
end

local function Tick()
	for _, id in ipairs(holderOrder) do
		local holder = holders[id]
		if holder.tick and #holder.shown > 0 then Report(pcall(holder.tick)) end
	end
end

-- One wake-up on the shared ticker for the next notice whose time is up
-- (or the next waiting one to drop); none while nothing is due, so an
-- empty queue costs nothing. The once-a-second tick runs only while a
-- holder that shows a running time has a notice up.
Arm = function()
	local ticker = E.Ticker
	if not ticker then return end
	local now, soonest = GetTime(), nil
	for _, entry in pairs(onScreen) do
		if entry.expires and not entry.closing and (not soonest or entry.expires < soonest) then soonest = entry.expires end
	end
	local ticking = false
	for _, id in ipairs(holderOrder) do
		local holder = holders[id]
		for _, data in ipairs(holder.waiting) do
			local limit = WaitLimit(holder, data)
			if limit then
				local at = Stamp(data).at + limit
				if not soonest or at < soonest then soonest = at end
			end
		end
		if holder.tick and #holder.shown > 0 then ticking = true end
	end
	if soonest then ticker:Subscribe(DUE, math.max(0, soonest - now), Due, "notices") else ticker:Unsubscribe(DUE) end
	if ticking then
		if not ticker:IsSubscribed(TICK) then ticker:Subscribe(TICK, 1, Tick, "notices") end
	else
		ticker:Unsubscribe(TICK)
	end
end

function E:RegisterNoticeHolder(id, holder)
	assert(id ~= nil and type(holder) == "table" and type(holder.show) == "function",
		"EldoUI:RegisterNoticeHolder(id, holder): holder.show is required")
	local old = holders[id]
	holder.id = id
	holder.shown = old and old.shown or {}
	holder.waiting = holder.waiting or (old and old.waiting) or {}
	if not old then holderOrder[#holderOrder + 1] = id end
	holders[id] = holder
	return holder
end

function E:NoticeHolder(id)
	return holders[id]
end

-- A notice for one holder. Returns the holder id and the frame it shows
-- in, "waiting" when it waits its turn, nil when the holder takes none.
function E:PushNotice(id, data)
	local holder = holders[id]
	if type(data) ~= "table" or not holder or not Usable(holder) then return nil end
	local key = data.key
	if key ~= nil then
		for _, entry in ipairs(holder.shown) do
			if not entry.closing and entry.data and entry.data.key == key then
				entry.data = data
				if holder.refresh then Report(pcall(holder.refresh, entry.frame, data)) end
				local seconds = Lasts(holder, data)
				entry.expires = seconds and (GetTime() + seconds) or nil
				Arm()
				return id, entry.frame
			end
		end
		for index = #holder.waiting, 1, -1 do
			if holder.waiting[index].key == key then
				since[holder.waiting[index]] = nil
				table.remove(holder.waiting, index)
			end
		end
	end
	Pump(holder) -- the ones that came first go first
	if #holder.waiting == 0 and #holder.shown < Slots(holder) and Ready(holder, data) then
		local frame = ShowIn(holder, data)
		Arm()
		if frame then return id, frame end
		return nil
	end
	Stamp(data)
	holder.waiting[#holder.waiting + 1] = data
	local most = tonumber(holder.most) or 20
	while #holder.waiting > most do since[table.remove(holder.waiting, 1)] = nil end
	Changed(holder)
	Arm()
	return "waiting"
end

-- The holder's notice is gone (closed, timed out, hidden): its place is
-- free for the next one.
function E:NoticeClosed(frame)
	local entry = frame ~= nil and onScreen[frame]
	if not entry then return false end
	onScreen[frame] = nil
	local holder = holders[entry.id]
	if holder then
		for index, other in ipairs(holder.shown) do
			if other == entry then table.remove(holder.shown, index) break end
		end
		Pump(holder)
	end
	Arm()
	return true
end

-- The player closed it (or the code did): through its holder's hide.
function E:CloseNotice(frame, now)
	local entry = frame ~= nil and onScreen[frame]
	if not entry then return false end
	Close(entry, now)
	return true
end

-- More time on screen: at least `seconds` from now.
function E:KeepNotice(frame, seconds)
	local entry = frame ~= nil and onScreen[frame]
	if not (entry and entry.expires) then return false end
	entry.expires = math.max(entry.expires, GetTime() + (tonumber(seconds) or 0))
	Arm()
	return true
end

-- Show what waits, when its holder can take it now (one holder, or all).
function E:PumpNotices(id)
	for _, other in ipairs(holderOrder) do
		if id == nil or other == id then Pump(holders[other]) end
	end
	Arm()
end

-- A holder turned off: its waiting notices go, the ones on screen close.
function E:DropNotices(id, now)
	local holder = holders[id]
	if not holder then return 0 end
	local count = #holder.waiting
	for _, data in ipairs(holder.waiting) do since[data] = nil end
	wipe(holder.waiting)
	local open = {}
	for _, entry in ipairs(holder.shown) do open[#open + 1] = entry end
	for _, entry in ipairs(open) do Close(entry, now) end
	if count > 0 then Changed(holder) end
	Arm()
	return count + #open
end

function E:NoticeWaiting(id)
	local holder = holders[id]
	return holder and #holder.waiting or 0
end

-- The whole queue, for diagnostics: every holder, what shows
-- (holder, data, frame) and what waits (holder, data, oldest first).
function E:NoticeQueue()
	local shown, waitingAll = {}, {}
	for _, id in ipairs(holderOrder) do
		for _, entry in ipairs(holders[id].shown) do
			shown[#shown + 1] = { holder = id, data = entry.data, frame = entry.frame, closing = entry.closing }
		end
		for _, data in ipairs(holders[id].waiting) do
			waitingAll[#waitingAll + 1] = { holder = id, data = data, seq = Stamp(data).seq }
		end
	end
	table.sort(waitingAll, function(a, b) return a.seq < b.seq end)
	local ids = {}
	for index, id in ipairs(holderOrder) do ids[index] = id end
	return { holders = ids, shown = shown, waiting = waitingAll }
end

-- Held notices show when combat ends.
local combatEnd = CreateFrame("Frame")
combatEnd:RegisterEvent("PLAYER_REGEN_ENABLED")
combatEnd:SetScript("OnEvent", function() E:PumpNotices() end)

---------------------------------------------------------------------------
-- EldoUI's own cards: the holder for alerts with buttons, and for plain
-- ones while the alert lane is not EldoUI's.
---------------------------------------------------------------------------
E:RegisterNoticeHolder("card", {
	slots = MAX_SHOWN,
	most = MAX_WAITING,
	waiting = waiting,
	wait = 120,
	duration = function(data)
		local actions = type(data.actions) == "table" and data.actions or {}
		return #actions > 0 and 20 or 8
	end,
	show = Show,
	refresh = function(card, data)
		Fill(card, data)
		Layout()
	end,
	hide = function(card, _, now)
		if now then
			card.closing = true
			Release(card)
		else
			Dismiss(card)
		end
	end,
})

-- Where alerts go right now: "notifications" (its own alert API),
-- "lane" (its toast lane, plain alerts only) or "card" (EldoUI's own card).
local function Route(data)
	local notifications = E.GetModule and E:GetModule("Notifications")
	if notifications and notifications.active and type(rawget(notifications, "PushAlert")) == "function" then
		-- Its own alert API only: every module has PushAlert from the
		-- module prototype, which comes back here.
		return "notifications", notifications
	end
	local hasActions = (type(data.actions) == "table" and #data.actions > 0) or (type(data.lines) == "table" and #data.lines > 0)
	local lane = holders.lane
	if not hasActions and not data.closable and lane and Usable(lane) and E:BlizzardAllowed("alert-toasts", "replace") then return "lane" end
	return "card"
end

function E:PushAlert(data)
	if type(data) ~= "table" then return nil end
	local route, notifications = Route(data)
	if route == "notifications" then
		local ok, err = pcall(notifications.PushAlert, notifications, data)
		if ok then return "notifications" end
		geterrorhandler()(err)
		route = "card"
	end
	local shown, frame = E:PushNotice(route, data)
	if shown == "waiting" then return route == "card" and "waiting" or route end
	return shown, frame
end

-- Cards on screen (oldest first) and alerts waiting, for diagnostics.
function E:AlertCards()
	return cards, waiting
end

-- Take an alert away by its key, in every holder: its notice closes and a
-- waiting one with that key is dropped. When the Alerts & Messages module
-- shows alerts with its own API, it is asked to drop it too (its
-- DismissAlert).
function E:DismissAlert(key)
	if key == nil then return 0 end
	local count = 0
	for _, id in ipairs(holderOrder) do
		local holder = holders[id]
		local dropped = false
		for index = #holder.waiting, 1, -1 do
			local data = holder.waiting[index]
			if data.key == key then
				since[data] = nil
				table.remove(holder.waiting, index)
				count = count + 1
				dropped = true
			end
		end
		if dropped then Changed(holder) end
		local open = {}
		for _, entry in ipairs(holder.shown) do
			if not entry.closing and entry.data and entry.data.key == key then open[#open + 1] = entry end
		end
		for _, entry in ipairs(open) do
			Close(entry)
			count = count + 1
		end
	end
	local notifications = Notifications()
	local dismiss = notifications and rawget(notifications, "DismissAlert")
	if type(dismiss) == "function" then
		local ok, err = pcall(dismiss, notifications, key)
		if not ok then geterrorhandler()(err) end
	end
	Arm()
	return count
end

function E:ClearAlerts()
	wipe(waiting)
	for index = #cards, 1, -1 do Release(cards[index]) end
	Arm()
end
