-- EldoUI My Adventure: the Notes section (design.md 4.4).
--
--   header     "Notes", "Here: Goldshire, Elwynn Forest (42.0, 65.0)", Archive n
--   composer   the "Remind me" choice (filled in from what you write until
--              you pick one yourself), "Every time", "Pin to Journey", a
--              600-letter writing field (shift-click items into it), Save
--   search     over the text, the zone and the subzone
--   list       "Waiting to remind you" (armed reminders), then your notes
--              by day, newest first; hover links Archive, Edit, Pin and
--              Remind again
--   archive    archived notes with Restore and Delete
--
-- Section registration and the shared parts are in UI/Goals.lua
-- (A.PageUI). The reminder row (UI.ReminderRow) is shared with the quick
-- note card (UI/QuickNote.lua).
--   show's arg: nil, "archive", "write" (focus the writing field), a note
--   id or "journal:note:<id>" (opens that note for editing).
local _, E = ...
local L = E.L
local Key = E.Key
local A = E.Adventure
local J = E.Journal
local LG = E.LootGuide
local K = E.AdventureKit
local G = A.Goals
local N = A.Notes
local T = E.tokens
local UI = A.PageUI

local function Kit() return LG.Kit end

local function Safe(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a, b = pcall(fn, ...)
	if not ok then
		geterrorhandler()(a)
		return nil
	end
	return a, b
end

local function SameTrigger(a, b)
	if not a or not b then return a == b end
	return a.kind == b.kind and a.target == b.target and a.level == b.level
end

---------------------------------------------------------------------------
-- The reminder row: "Remind me: <choice>" and "Every time".
--   row = UI.ReminderRow(parent, onChange)
--   row:Reset(trigger, repeats)   start over (a new or edited note)
--   row:Suggest(trigger)          follows the text until you pick yourself
--   row:Get() -> trigger, repeats
---------------------------------------------------------------------------
local function MenuChoices(row)
	local list = { { label = L["No reminder"], trigger = false } }
	local function Add(trigger)
		for _, item in ipairs(list) do
			if item.trigger and SameTrigger(item.trigger, trigger) then return end
		end
		list[#list + 1] = { label = N:TriggerLabel(trigger), trigger = trigger }
	end
	if row.suggested and (row.suggested.target or row.suggested.kind == "level") then Add(row.suggested) end
	if row.trigger then Add(row.trigger) end
	local level = row.suggested and row.suggested.kind == "level" and row.suggested.level
	for _, def in ipairs(N:Triggers()) do
		if def.kind == "level" then
			local now = A.Plain(UnitLevel("player"))
			Add({ kind = "level", level = level or ((type(now) == "number" and now or 1) + 1) })
		else
			Add({ kind = def.kind })
		end
	end
	return list
end

function UI.ReminderRow(parent, onChange)
	local row = CreateFrame("Frame", nil, parent)
	row:SetHeight(22)
	row.button = Kit().Button(row, "", 220, T.height.button)
	row.button:SetPoint("LEFT")
	row.every = UI.Check(row, L["Every time"], L["The reminder stays and shows each time, instead of once."], function(on)
		row.repeats = on
		if onChange then Safe(onChange, row) end
	end)
	row.every:SetPoint("LEFT", row.button, "RIGHT", 10, 0)

	function row:Paint()
		local label = self.trigger and N:TriggerLabel(self.trigger) or L["No reminder"]
		self.button:SetText((L["Remind me: %s"]):format(label))
		E.UIKit.FitButton(self.button, 160)
		self.every:SetShown(self.trigger ~= nil)
		self.every:SetChecked(self.repeats and true or false)
		self:SetWidth(self.button:GetWidth() + (self.trigger and (10 + self.every:Width()) or 0))
	end
	function row:Choose(trigger)
		self.picked = true
		self.trigger = trigger or nil
		if not self.trigger then self.repeats = nil end
		self:Paint()
		if onChange then Safe(onChange, self) end
	end
	function row:Reset(trigger, repeats)
		self.trigger, self.repeats = N.CleanTrigger(trigger), repeats and true or nil
		self.picked = self.trigger ~= nil
		self.suggested = nil
		self:Paint()
	end
	function row:Suggest(trigger)
		self.suggested = N.CleanTrigger(trigger)
		if self.picked then return end
		self.trigger = self.suggested
		self:Paint()
	end
	function row:Get()
		return self.trigger, self.trigger and self.repeats or nil
	end
	function row:Choices()
		return MenuChoices(self)
	end

	row.button:SetScript("OnClick", function(self)
		local choices = MenuChoices(row)
		E.UIKit.ContextMenu(self, function(_, root)
			root:CreateTitle(L["Remind me"])
			for _, item in ipairs(choices) do
				root:CreateRadio(item.label, function() return SameTrigger(item.trigger or nil, row.trigger) end,
					function() row:Choose(item.trigger) end)
			end
		end, { at = "owner" })
	end)
	Kit().Tooltip(row.button, L["Remind me"], L["When this note should show again as a reminder. It picks one from what you write until you choose yourself."])
	row:Reset(nil)
	return row
end

-- The line a saved note shows: "Noted in your journal." or
-- "Noted. Reminder set: when you reach Westfall."
function UI.SavedText(note)
	if note and note.trigger then
		return (L["Noted. Reminder set: %s."]):format(N.LowerFirst(N:TriggerLabel(note.trigger, note.repeats)))
	end
	return L["Noted in your journal."]
end

function UI.NoteSound()
	local db = A.db
	local sound = db and type(db.sounds) == "table" and db.sounds.note
	if type(sound) == "string" and sound ~= "none" and sound ~= "" then
		E:PlayMedia(sound, db.soundMaster and "Master" or nil)
	end
end

-- The text box follows its suggestion 0.3 s after typing stops.
function UI.FollowSuggestion(box, reminder)
	box:HookScript("OnTextChanged", function(self, typed)
		if not typed then return end
		self.suggestToken = (self.suggestToken or 0) + 1
		local token = self.suggestToken
		C_Timer.After(0.3, function()
			if self.suggestToken ~= token then return end
			reminder:Suggest(N:Suggest(self:GetText() or ""))
		end)
	end)
end

-- Shift-clicked links go into the box while it has focus.
function UI.LinkIntoBox(box)
	UI.AddLinkTarget({
		active = function() return box:IsVisible() and box:HasFocus() end,
		take = function(link)
			box:Insert(link)
			return true
		end,
	})
end

---------------------------------------------------------------------------
-- Row kinds
---------------------------------------------------------------------------
local TIME_COLUMN = 54
local LINK_ROOM = 150    -- the text leaves room for the hover links

local function DayKey(t)
	return date("%Y%m%d", t or 0)
end

local function DayLabel(t)
	return E:LongDay(t or 0, true)
end

local function Ago(t)
	t = tonumber(t)
	if not t then return "" end
	local seconds = time() - t
	if seconds < 60 then return L["just now"] end
	if seconds < 3600 then
		local minutes = math.floor(seconds / 60)
		return (E:Plural(minutes, "%d minute ago", "%d minutes ago")):format(minutes)
	end
	if seconds < 86400 then
		local hours = math.floor(seconds / 3600)
		return (E:Plural(hours, "%d hour ago", "%d hours ago")):format(hours)
	end
	return G.DateText(t)
end
UI.Ago = Ago

local function TextWidth(width, left)
	return math.max((width or 600) - left - LINK_ROOM, 120)
end

-- reminder: { note, links }
K.ROWS.advReminder = {
	height = function(item, width)
		local text = E.UIKit.TextHeight(item.note.text or "", TextWidth(width, 56), K.size.body, { spacing = 2 })
		return 10 + K.size.small + 4 + text + 4 + K.size.small + 10 + 6
	end,
	create = function(row)
		row:EnableMouse(true)
		row.card = K.Card(row, { accent = true })
		row.card:SetPoint("TOPLEFT", 0, -3)
		row.card:SetPoint("BOTTOMRIGHT", 0, 3)
		row.card:SetFrameLevel(math.max(row:GetFrameLevel() - 1, 0))
		row.art = K.Art(row, 30)
		row.art:SetPoint("TOPLEFT", 14, -12)
		K.SetIcon(row.art.icon, N.ICON_REMINDER)
		row.trigger = K.Text(row, K.size.small, "LEFT", "accent")
		row.trigger:SetPoint("TOPLEFT", 56, -12)
		row.trigger:SetWordWrap(false)
		row.text = K.Text(row, K.size.body, "LEFT", "body")
		row.text:SetPoint("TOPLEFT", row.trigger, "BOTTOMLEFT", 0, -4)
		row.text:SetWordWrap(true)
		row.text:SetSpacing(2)
		row.sub = K.Text(row, K.size.small, "LEFT", "secondary")
		row.sub:SetPoint("TOPLEFT", row.text, "BOTTOMLEFT", 0, -4)
		row.sub:SetWordWrap(false)
	end,
	update = function(row, item, width)
		local note = item.note
		row.trigger:SetText(N:TriggerLabel(note.trigger, note.repeats))
		row.trigger:SetWidth(TextWidth(width, 56))
		K.Paint(row.trigger, "accent")
		row.text:SetWidth(TextWidth(width, 56))
		row.text:SetText(note.text or "")
		local sub = N:WhereText(note)
		if note.firedAt then
			sub = (L["%s · last reminded %s"]):format(sub, Ago(note.firedAt))
		elseif note.snoozeUntil and note.snoozeUntil > time() then
			sub = (L["%s · snoozed until %s"]):format(sub, G.TimeText(note.snoozeUntil))
		else
			sub = (L["%s · level %d"]):format(sub, note.level or 0)
		end
		row.sub:SetText(sub)
		row.sub:SetWidth(math.max((width or 600) - 56 - K.CARD_INSET, 120))
		K.HoverLinks(row, item.links)
	end,
}

-- diary: { note, links }
local function DiaryLines(note)
	local sub = (L["%s · level %d"]):format(N:WhereText(note), note.level or 0)
	local fired
	if note.firedAt and note.trigger then
		fired = (L["Reminded you %s · %s"]):format(Ago(note.firedAt), N:TriggerLabel(note.trigger, note.repeats))
	end
	return sub, fired
end

K.ROWS.advDiary = {
	height = function(item, width)
		local text = E.UIKit.TextHeight(item.note.text or "", TextWidth(width, TIME_COLUMN), K.size.body, { spacing = 2 })
		local _, fired = DiaryLines(item.note)
		return 8 + text + 4 + K.size.small + (fired and (4 + K.size.small) or 0) + 10
	end,
	create = function(row)
		row:EnableMouse(true)
		local hover = row:CreateTexture(nil, "HIGHLIGHT")
		hover:SetAllPoints()
		hover:SetColorTexture(1, 1, 1, T.hover.row)
		row.time = K.Text(row, K.size.small, "LEFT", "secondary")
		row.time:SetPoint("TOPLEFT", 0, -9)
		row.pinned = K.Text(row, K.size.caption, "LEFT", "secondary")
		row.pinned:SetPoint("TOPLEFT", row.time, "BOTTOMLEFT", 0, -2)
		row.pinned:SetText(L["pinned"])
		row.bar = row:CreateTexture(nil, "ARTWORK")
		row.bar:SetPoint("TOPLEFT", 44, -6)
		row.bar:SetPoint("BOTTOMLEFT", 44, 6)
		E:Hairline(row.bar, "w", 2)
		row.text = K.Text(row, K.size.body, "LEFT", "body")
		row.text:SetPoint("TOPLEFT", TIME_COLUMN, -8)
		row.text:SetWordWrap(true)
		row.text:SetSpacing(2)
		row.sub = K.Text(row, K.size.small, "LEFT", "secondary")
		row.sub:SetPoint("TOPLEFT", row.text, "BOTTOMLEFT", 0, -4)
		row.sub:SetWordWrap(false)
		row.fired = K.Text(row, K.size.small, "LEFT", "secondary")
		row.fired:SetPoint("TOPLEFT", row.sub, "BOTTOMLEFT", 0, -4)
		row.fired:SetWordWrap(false)
		row.rule = K.Rule(row)
		row.rule:SetPoint("BOTTOMLEFT", TIME_COLUMN, 0)
		row.rule:SetPoint("BOTTOMRIGHT")
	end,
	update = function(row, item, width)
		local note = item.note
		row.time:SetText(G.TimeText(note.t))
		K.Paint(row.time, note.pinned and "body" or "secondary")
		row.pinned:SetShown(note.pinned and true or false)
		row.bar:SetShown(note.pinned and true or false)
		local c = E.media.accentColor
		row.bar:SetColorTexture(c[1], c[2], c[3], 1)
		row.text:SetWidth(TextWidth(width, TIME_COLUMN))
		row.text:SetText(note.text or "")
		local sub, fired = DiaryLines(note)
		row.sub:SetText(sub)
		row.sub:SetWidth(math.max((width or 600) - TIME_COLUMN - 8, 120))
		row.fired:SetShown(fired ~= nil)
		row.fired:SetText(fired or "")
		row.fired:SetWidth(math.max((width or 600) - TIME_COLUMN - 8, 120))
		K.HoverLinks(row, item.links)
	end,
}

---------------------------------------------------------------------------
-- The page
---------------------------------------------------------------------------
local Page = {}
UI.NotesPage = Page
local page

local COMPOSER_Y = -60
local COMPOSER_HEIGHT = 148

local function Toast(text, warn)
	if page and page:IsVisible() then E.UIKit.Toast(page, text, { anchor = page.list, point = "BOTTOM", y = 8, warn = warn }) end
end

local function Undoable(trashID, text)
	if trashID then K.UndoToast(page, text, trashID, function() Page.Refresh() end) end
end

local function Matches(note)
	local q = E:FoldText(K.Query("notes"))
	if q == "" then return true end
	for _, value in ipairs({ note.text, note.zone, note.subzone }) do
		if type(value) == "string" and E:FoldText(G.Plainify(value)):find(q, 1, true) then return true end
	end
	return false
end

local function Edit(note)
	page.editing = note.id
	page.view = "list"
	local composer = page.composer
	composer.field.box:SetText(note.text or "")
	composer.reminder:Reset(note.trigger, note.repeats)
	composer.pin:SetChecked(note.pinned and true or false)
	Page.Refresh()
	C_Timer.After(0, function() if composer:IsVisible() then composer.field.box:SetFocus() end end)
end
Page.Edit = Edit

local function StopEditing()
	page.editing = nil
	local composer = page.composer
	composer.field.box:SetText("")
	composer.field.box:ClearFocus()
	composer.reminder:Reset(nil)
	composer.pin:SetChecked(A.db and A.db.pinNewNotes and true or false)
end

local function NoteLinks(note)
	local links = {
		{ L["Archive"], function() N:Archive(note.id, true) Page.Refresh() end,
			L["Hides this note from the page. The archive keeps it, and a pinned note stays on your Journey."] },
		{ L["Edit"], function() Edit(note) end, L["Opens this note in the box above."] },
		{ note.pinned and L["Unpin"] or L["Pin"], function() N:SetPinned(note.id, not note.pinned) Page.Refresh() end,
			note.pinned and L["Takes this note off your Journey."] or L["Shows this note on your Journey, under the level you wrote it at."] },
	}
	if note.trigger and note.done then
		links[#links + 1] = { L["Remind again"], function()
			N:RemindAgain(note.id)
			Page.Refresh()
		end, L["Arms the reminder again, from where you are now."] }
	end
	return links
end

local function ListItems()
	local notes, waiting = N:List()
	local items, shown = {}, 0
	local wait = {}
	for _, note in ipairs(waiting) do
		if Matches(note) then wait[#wait + 1] = note end
	end
	if wait[1] then
		local open = K.FoldOpen("notes.waiting", true)
		items[#items + 1] = { kind = "fold", key = "notes.waiting", label = L["Waiting to remind you"], note = tostring(#wait),
			open = open, onToggle = function() Page.Refresh() end }
		if open then
			for _, note in ipairs(wait) do
				items[#items + 1] = { kind = "advReminder", note = note, links = {
					{ L["Done"], function() N:Done(note.id) Page.Refresh() end, L["Stops this reminder."] },
					{ L["Edit"], function() Edit(note) end, L["Opens this note in the box above."] },
				} }
			end
		end
		shown = shown + #wait
		items[#items + 1] = { kind = "space", height = 8 }
	end
	local day
	local dayOpen = true
	for _, note in ipairs(notes) do
		if Matches(note) then
			local key = DayKey(note.t)
			if key ~= day then
				day = key
				local foldKey = "notes.day." .. key
				dayOpen = K.FoldOpen(foldKey, true)
				local count = 0
				for _, other in ipairs(notes) do
					if DayKey(other.t) == key and Matches(other) then count = count + 1 end
				end
				items[#items + 1] = { kind = "fold", key = foldKey, label = DayLabel(note.t), note = tostring(count),
					open = dayOpen, onToggle = function() Page.Refresh() end }
			end
			if dayOpen then items[#items + 1] = { kind = "advDiary", note = note, links = NoteLinks(note) } end
			shown = shown + 1
		end
	end
	return items, shown, #notes + #waiting
end

local function ArchiveItems()
	local _, _, archived = N:List()
	local items, list = {}, {}
	for _, note in ipairs(archived) do
		if Matches(note) then list[#list + 1] = note end
	end
	for index, note in ipairs(list) do
		local sub = (L["%s · %s · archived %s"]):format(G.DateText(note.t), N:WhereText(note), G.DateText(note.archived))
		if note.pinned then sub = (L["%s · pinned"]):format(sub) end
		items[#items + 1] = {
			kind = "ledger", icon = note.trigger and N.ICON_REMINDER or N.ICON, title = note.text, sub = sub,
			position = #list == 1 and "only" or index == 1 and "first" or index == #list and "last" or "middle",
			links = {
				{ L["Delete"], function() Undoable(N:Delete(note.id), L["Note deleted."]) Page.Refresh() end,
					L["Removes this note for good, also from your Journey. You can undo it for a moment."] },
				{ L["Restore"], function() N:Archive(note.id, false) Page.Refresh() end, L["Puts this note back on the page."] },
			},
		}
	end
	return items
end

function Page.Save()
	if not page then return end
	local composer = page.composer
	local text = composer.field.box:GetText() or ""
	local trigger, repeats = composer.reminder:Get()
	local pinned = composer.pin:GetChecked() and true or false
	if page.editing then
		local id = page.editing
		if strtrim(text) == "" then
			StopEditing()
			Undoable(N:Delete(id), L["Note deleted."])
			Page.Refresh()
			return
		end
		local note = N:Edit(id, text, { trigger = trigger or false, repeats = repeats, pinned = pinned })
		StopEditing()
		Page.Refresh()
		if note then Toast(L["Note saved."]) end
		return
	end
	local note, err = N:Add(text, { trigger = trigger, repeats = repeats, pinned = pinned })
	if not note then
		Toast(err or L["Write something first."], true)
		return
	end
	UI.NoteSound()
	StopEditing()
	Page.Refresh()
	Toast(UI.SavedText(note))
end

local function BuildComposer(parent)
	local composer = K.Card(parent, { solid = true })
	composer:SetPoint("TOPLEFT", 0, COMPOSER_Y)
	composer:SetPoint("TOPRIGHT", 0, COMPOSER_Y)
	composer:SetHeight(COMPOSER_HEIGHT)
	composer.reminder = UI.ReminderRow(composer)
	composer.reminder:SetPoint("TOPLEFT", K.CARD_INSET, -8)
	composer.pin = UI.Check(composer, L["Pin to Journey"], L["Shows the note on your Journey, under the level you wrote it at."])
	composer.pin:SetPoint("TOPRIGHT", composer, "TOPRIGHT", -(K.CARD_INSET + composer.pin:Width() - 22), -8)
	composer.field = UI.WritingField(composer, 64, N.MAX_LETTERS,
		L["Write about this place, a reminder for later, or shift-click an item into it."])
	composer.field:SetPoint("TOPLEFT", K.CARD_INSET, -38)
	composer.field:SetPoint("TOPRIGHT", -K.CARD_INSET, -38)
	composer.hint = K.Text(composer, K.size.small, "LEFT", "secondary")
	composer.hint:SetPoint("BOTTOMLEFT", K.CARD_INSET, 14)
	composer.hint:SetText(L["Enter saves, Shift+Enter starts a new line."])
	composer.save = Kit().Button(composer, L["Save note"], 110, T.height.button, function() Page.Save() end,
		L["Save note"], L["Writes the note into your journal with where and when you wrote it."])
	composer.save:SetPoint("BOTTOMRIGHT", -K.CARD_INSET, 8)
	composer.cancel = CreateFrame("Button", nil, composer)
	composer.cancel:SetHeight(16)
	composer.cancel.text = K.Text(composer.cancel, K.size.small, "RIGHT", "secondary")
	composer.cancel.text:SetPoint("RIGHT")
	composer.cancel.text:SetText(L["Cancel editing"])
	composer.cancel:SetWidth(math.ceil(composer.cancel.text:GetStringWidth()))
	E:PadHitRect(composer.cancel, 4)
	composer.cancel:SetPoint("RIGHT", composer.save, "LEFT", -12, 0)
	composer.cancel:SetScript("OnEnter", function(self) K.Paint(self.text, "accent") end)
	composer.cancel:SetScript("OnLeave", function(self) K.Paint(self.text, "secondary") end)
	composer.cancel:SetScript("OnClick", function()
		StopEditing()
		Page.Refresh()
	end)
	Kit().Tooltip(composer.cancel, L["Cancel editing"], L["Leaves the note as it was."])
	local box = composer.field.box
	UI.EnterSaves(box, function() Page.Save() end)
	UI.FollowSuggestion(box, composer.reminder)
	UI.LinkIntoBox(box)
	return composer
end

function Page.Refresh()
	if not page then return end
	local header = page.header
	if not A:Running() then
		header:SetTitle(L["Notes"])
		header:SetSentence(A:OffReason() or "")
		header:SetActions({})
		page.composer:Hide()
		page.search:Hide()
		page.list:SetEmpty(L["My Adventure is off"], A:OffReason() or "", N.ICON)
		page.list:SetData({})
		return
	end
	local _, _, archived = N:List()
	local archive = page.view == "archive"
	page.composer:SetShown(not archive)
	page.search:SetShown(true)
	page.search:ClearAllPoints()
	page.search:SetPoint("TOPLEFT", 6, archive and COMPOSER_Y or (COMPOSER_Y - COMPOSER_HEIGHT - 8))
	page.list:ClearAllPoints()
	page.list:SetPoint("TOPLEFT", 0, archive and (COMPOSER_Y - 28) or (COMPOSER_Y - COMPOSER_HEIGHT - 36))
	page.list:SetPoint("BOTTOMRIGHT")
	if archive then
		header:SetTitle(L["Archived notes"])
		header:SetSentence(L["Hidden from the page until you restore them. Delete removes them for good. Pinned notes stay on your Journey until deleted."])
		header:SetActions({ { L["Back"], function() page.view = "list" Page.Refresh() end, L["Back to your notes."] } })
		page.list:SetEmpty(L["No archived notes"], L["Notes you archive wait here until you restore or delete them."], N.ICON)
		page.list:SetData(ArchiveItems(), true)
		return
	end
	header:SetTitle(L["Notes"])
	local editing = page.editing and N:Get(page.editing)
	if editing then
		header:SetSentence((L["Editing a note from %s"]):format(N:WhereText(editing, true)))
	else
		header:SetSentence((L["Here: %s"]):format(N:WhereText(N:Here(), true)))
	end
	local actions = {}
	if #archived > 0 then
		actions[1] = { (L["Archive %s"]):format(#archived), function() page.view = "archive" Page.Refresh() end,
			L["Notes you archived. Restore or delete them there."] }
	end
	header:SetActions(actions)
	page.composer.save:SetText(editing and L["Save changes"] or L["Save note"])
	E.UIKit.FitButton(page.composer.save, 110)
	page.composer.cancel:SetShown(editing ~= nil)
	if page.editing and not editing then page.editing = nil end
	local items, shown, total = ListItems()
	if shown == 0 and total > 0 then
		page.list:SetEmpty(L["Nothing matches"], L["No note matches that search."], N.ICON)
	else
		page.list:SetEmpty(L["No notes yet"], L["Notes remember where and when you wrote them. Press Enter in the box above to save one."], N.ICON)
	end
	page.list:SetData(items, true)
	if page.focus then
		for index, item in ipairs(items) do
			if item.note and item.note.id == page.focus then page.list:ScrollTo(index, "center") end
		end
		page.focus = nil
	end
end

local function Build(parent)
	page = CreateFrame("Frame", nil, parent)
	page:SetAllPoints()
	page.view = "list"
	page.header = K.Header(page)
	page.header:SetPoint("TOPLEFT")
	page.header:SetPoint("TOPRIGHT")
	page.composer = BuildComposer(page)
	page.search = K.Search(page, "notes", L["Search notes"], function() Page.Refresh() end)
	page.search:SetWidth(260)
	page.list = K.CreateJournalList(page, { gap = 0 })
	page:SetScript("OnShow", function() Page.Refresh() end)
	StopEditing()
	if J.RegisterCallback then
		J.RegisterCallback(Page, "Redraw", function(_, what)
			if page:IsVisible() and type(what) == "table" and (what.notes or what.all or what.settings or what.journal) then
				Page.Refresh()
			end
		end)
	end
	Page.frame = page
	return page
end

-- arg: nil, "archive", "write", a note id or "journal:note:<id>".
local function Show(frame, arg)
	page = frame or page
	if not page then return end
	if type(arg) == "string" then
		local kind, id = J:ParseAddress(arg)
		if kind == "note" then arg = id end
	end
	if arg == "archive" then
		page.view = "archive"
	else
		page.view = "list"
	end
	local note = tonumber(arg) and N:Get(arg)
	if note then
		page.focus = note.id
		if note.archived then
			page.view = "archive"
		else
			Edit(note)
			return
		end
	end
	Page.Refresh()
	if arg == "write" then
		C_Timer.After(0, function() if page.composer:IsVisible() then page.composer.field.box:SetFocus() end end)
	end
end

local function Hide(frame)
	frame = frame or page
	if frame and frame.composer then frame.composer.field.box:ClearFocus() end
end

Page.Build, Page.Show, Page.Hide = Build, Show, Hide

UI.RegisterSection("notes", {
	title = "Notes",
	icon = "Interface/Icons/INV_Feather_05",
	desc = "Notes that remember where and when you wrote them, and reminders that show when you get somewhere.",
	order = 40,
	group = "today",
	count = function() return A:Running() and N:CountWaiting() or 0 end,
	build = Build,
	show = Show,
	hide = Hide,
})
