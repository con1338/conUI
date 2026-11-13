-- EldoUI My Adventure: the Goals section (design.md 4.3).
--
-- Four views inside one section page of the My Adventure hub:
--   list     active goal cards (icon, name, hint, a progress bar that moves
--            by itself), a "Reached" fold of medals, and the header actions
--            New goal and Archive
--   archive  archived goals with Restore and Delete
--   pick     "What would you like to work towards?": one tile per goal kind
--   form     the questions for that kind (an item slot, a name with
--            suggestions, a count with steps), Set goal under them and
--            Back in the header
--
-- The section is registered for the hub (UI/Hub.lua, LG.Kit.SectionHost):
--   A.PageUI.RegisterSection(key, def) hands the def to
--   LG:RegisterHubSection("adventure", key, def) when the hub defines it
--   (plan 2.4), else to A:RegisterSection(key, def), and always keeps it in
--   A.hubSections[key] so the hub can collect it when it builds.
--   def = { key, title, icon, desc, order, group = "today", count = fn,
--     build = fn(parent, host) -> frame, show = fn(frame, arg), hide = fn(frame) }
--   show's arg: nil, "new" (the picker), "archive", a goal kind key (its
--   form), a goal id or "journal:goal:<id>" (scrolls to that goal).
--
-- Shared page parts for the Goals, Notes and quick-note pages live on
-- A.PageUI (this file loads first): the section registry, the one hook
-- that hands shift-clicked links to whichever of our boxes wants them,
-- a check box, edit boxes and suggestion chips, all built from the kit
-- (E.AdventureKit, LG.Kit, LG.PageKit) and the design tokens.
local _, E = ...
local L = E.L
local A = E.Adventure
local J = E.Journal
local LG = E.LootGuide
local K = E.AdventureKit
local G = A.Goals
local T = E.tokens

local UI = A.PageUI or {}
A.PageUI = UI

local function Kit() return LG.Kit end
local function PageKit() return LG.PageKit end

local function Safe(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a, b = pcall(fn, ...)
	if not ok then
		geterrorhandler()(a)
		return nil
	end
	return a, b
end

---------------------------------------------------------------------------
-- Section registry
---------------------------------------------------------------------------
UI.sections = UI.sections or {}

function UI.RegisterSection(key, def)
	def.key = key
	UI.sections[key] = def
	A.hubSections = A.hubSections or {}
	A.hubSections[key] = def
	if LG and type(LG.RegisterHubSection) == "function" then
		Safe(LG.RegisterHubSection, LG, "adventure", key, def)
	elseif type(A.RegisterSection) == "function" then
		Safe(A.RegisterSection, A, key, def)
	end
end

-- Opens a section of the hub. The page arg follows the Catalog host's
-- convention: a section key, or { section = key, arg = value }.
function UI.Open(key, arg)
	if not (A:Running() and LG.Open) then return false end
	LG:Open("adventure", arg ~= nil and { section = key, arg = arg } or key)
	return true
end

---------------------------------------------------------------------------
-- Shift-clicked links: one hook for every box of these pages.
--   UI.AddLinkTarget({ active = fn() -> bool, take = fn(link) -> bool })
-- The newest active target takes the link. Several hooks can see the
-- same click (the chat box util, the modified item click), so the same
-- link within 0.2 s is handed over once.
---------------------------------------------------------------------------
local targets = {}
local lastLink, lastAt = nil, 0
UI.linkTargets = targets

function UI.AddLinkTarget(target)
	targets[#targets + 1] = target
	UI.HookLinks()
	return target
end

function UI.TakeLink(link)
	if type(link) ~= "string" or E:IsSecret(link) or link == "" then return false end
	local now = GetTime()
	if link == lastLink and now - lastAt < 0.2 then return false end
	for index = #targets, 1, -1 do
		local target = targets[index]
		if Safe(target.active) then
			lastLink, lastAt = link, now
			return Safe(target.take, link) and true or false
		end
	end
	return false
end

function UI.HookLinks()
	if UI.linksHooked then return end
	UI.linksHooked = true
	local util = rawget(_G, "ChatFrameUtil")
	if type(util) == "table" and type(util.InsertLink) == "function" then
		hooksecurefunc(util, "InsertLink", function(link) UI.TakeLink(link) end)
	end
	if type(rawget(_G, "ChatEdit_InsertLink")) == "function" then
		hooksecurefunc("ChatEdit_InsertLink", function(link) UI.TakeLink(link) end)
	end
	if type(rawget(_G, "HandleModifiedItemClick")) == "function" then
		hooksecurefunc("HandleModifiedItemClick", function(link)
			local modified = rawget(_G, "IsModifiedClick")
			if type(modified) == "function" and modified("CHATLINK") then UI.TakeLink(link) end
		end)
	end
end

---------------------------------------------------------------------------
-- Small parts
---------------------------------------------------------------------------
-- A check box with its label in the kit's ink; desc is the tooltip.
function UI.Check(parent, label, desc, onClick)
	local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	check:SetSize(22, 22)
	E:SkinCheckBox(check)
	check.label = K.Text(check, K.size.label, "LEFT", "body")
	check.label:SetPoint("LEFT", check, "RIGHT", 2, 0)
	check.label:SetText(label or "")
	check:SetHitRectInsets(0, -(math.ceil(check.label:GetStringWidth()) + 6), 0, 0)
	if label then Kit().Tooltip(check, label, desc) end
	check:SetScript("OnClick", function(self)
		local on = self:GetChecked() and true or false
		if onClick then Safe(onClick, on, self) end
	end)
	function check:Width()
		return 24 + math.ceil(self.label:GetStringWidth())
	end
	return check
end

local function PaintBox(box)
	local c = K.Ink("body")
	box:SetTextColor(c[1], c[2], c[3])
end

-- A one-line edit box in the EldoUI look. opts: letters, width, numeric.
function UI.EditBox(parent, opts)
	opts = opts or {}
	local box = CreateFrame("EditBox", nil, parent)
	box:SetAutoFocus(false)
	box:SetFontObject(ChatFontNormal)
	box:SetTextInsets(4, 4, 2, 2)
	box:SetHeight(22)
	if opts.width then box:SetWidth(opts.width) end
	box:SetMaxLetters(opts.letters or 120)
	if opts.numeric then box:SetNumeric(true) end
	E:SkinEditBox(box)
	PaintBox(box)
	box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	return box
end

-- A multi-line writing field: a box with a scroll frame so long notes stay
-- inside it. field.box is the edit box.
function UI.WritingField(parent, height, letters, hint)
	local field = CreateFrame("Frame", nil, parent)
	field:SetHeight(height or 64)
	E:SetTemplate(field, true)
	local scroll = CreateFrame("ScrollFrame", nil, field, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 6, -4)
	scroll:SetPoint("BOTTOMRIGHT", -24, 4)
	if scroll.ScrollBar and E.SkinScrollBar then E:SkinScrollBar(scroll.ScrollBar) end
	local box = CreateFrame("EditBox", nil, scroll)
	box:SetMultiLine(true)
	box:SetAutoFocus(false)
	box:SetMaxLetters(letters or 600)
	box:SetFontObject(ChatFontNormal)
	E:SetFont(box, K.size.body)
	box:SetWidth(300)
	PaintBox(box)
	scroll:SetScrollChild(box)
	scroll:SetScript("OnSizeChanged", function(self, width) box:SetWidth(math.max((width or 0) - 4, 40)) end)
	field.hint = K.Text(field, K.size.body, "LEFT", "dim")
	field.hint:SetPoint("TOPLEFT", 8, -6)
	field.hint:SetPoint("TOPRIGHT", -24, -6)
	field.hint:SetWordWrap(true)
	field.hint:SetText(hint or "")
	local function SyncHint()
		field.hint:SetShown((box:GetText() or "") == "" and not box:HasFocus())
	end
	box:HookScript("OnTextChanged", SyncHint)
	box:HookScript("OnEditFocusGained", SyncHint)
	box:HookScript("OnEditFocusLost", SyncHint)
	box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	field:EnableMouse(true)
	field:SetScript("OnMouseDown", function() box:SetFocus() end)
	box:HookScript("OnEditFocusGained", function() field:SetBackdropBorderColor(Kit().Accent()) end)
	box:HookScript("OnEditFocusLost", function() field:SetBackdropBorderColor(unpack(E.media.borderColor)) end)
	field.box, field.scroll = box, scroll
	SyncHint()
	return field
end

-- Enter saves, Shift+Enter starts a new line, in a multi-line box. The
-- client may or may not have put the new line in already.
function UI.EnterSaves(box, onSave)
	box:SetScript("OnEnterPressed", function(self)
		local text = self:GetText() or ""
		local cursor = self:GetCursorPosition() or #text
		local typed = cursor > 0 and text:sub(cursor, cursor) == "\n"
		if IsShiftKeyDown() then
			if not typed then self:Insert("\n") end
			return
		end
		if typed then
			self:SetText(text:sub(1, cursor - 1) .. text:sub(cursor + 1))
			self:SetCursorPosition(cursor - 1)
		end
		Safe(onSave)
	end)
end

-- A row of suggestion chips that wraps to the width of its parent.
--   chips:Set(list, onPick)  list = { { label, value, extra, tip } }
function UI.Chips(parent)
	local chips = CreateFrame("Frame", nil, parent)
	chips:SetHeight(1)
	chips.buttons = {}
	function chips:Set(list, onPick)
		list = list or {}
		local width = math.max(self:GetWidth() or 0, 200)
		local x, y = 0, 0
		for index = 1, math.max(#self.buttons, #list) do
			local data = list[index]
			local button = self.buttons[index]
			if data and not button then
				button = PageKit().Toggle(self, "", nil)
				E:SkinHoverPress(button)
				self.buttons[index] = button
			end
			if button then
				button:SetShown(data ~= nil)
				if data then
					button:SetLabel(data.label or tostring(data.value))
					button:SetOn(false)
					button:SetScript("OnClick", function() if onPick then Safe(onPick, data) end end)
					Kit().Tooltip(button, data.label, data.tip)
					local w = button:GetWidth()
					if x > 0 and x + w > width then x, y = 0, y + 22 end
					button:ClearAllPoints()
					button:SetPoint("TOPLEFT", self, "TOPLEFT", x, -y)
					x = x + w + 6
				end
			end
		end
		self:SetHeight(#list > 0 and (y + 18) or 1)
		self:SetShown(#list > 0)
	end
	return chips
end

-- A hover overlay in the control hover alpha.
function UI.Hover(frame, alpha)
	local hover = frame:CreateTexture(nil, "HIGHLIGHT")
	hover:SetAllPoints()
	hover:SetColorTexture(1, 1, 1, alpha or T.hover.control)
	return hover
end

-- Fold state helper: a fold item that redraws its page when toggled.
function UI.FoldItem(key, label, note, default, onToggle)
	return { kind = "fold", key = key, label = label, note = note, open = K.FoldOpen(key, default),
		onToggle = onToggle }
end

---------------------------------------------------------------------------
-- Row kinds of the goals list (added to the journal list's kinds)
---------------------------------------------------------------------------
local GOAL_CARD = 60
local MEDAL_HEIGHT = 120
local TILE_HEIGHT = 56

local function Query(text, key)
	local q = E:FoldText(K.Query(key))
	if q == "" then return true end
	return E:FoldText(text or ""):find(q, 1, true) ~= nil
end

-- goal card: { goal, onTick, links }
K.ROWS.advGoal = {
	height = function() return GOAL_CARD + 8 end,
	create = function(row)
		row:RegisterForClicks("LeftButtonUp")
		row.card = K.Card(row)
		row.card:SetPoint("TOPLEFT", 0, -4)
		row.card:SetPoint("BOTTOMRIGHT", 0, 4)
		row.card:SetFrameLevel(math.max(row:GetFrameLevel() - 1, 0))
		row.hover = UI.Hover(row, T.hover.row)
		row.art = K.Art(row, 40)
		row.art:SetPoint("TOPLEFT", K.CARD_INSET - 2, -14)
		row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
		row.check:SetSize(28, 28)
		row.check:SetPoint("TOPLEFT", K.CARD_INSET + 4, -20)
		E:SkinCheckBox(row.check)
		row.name = K.Text(row, K.size.section + 2, "LEFT", "head", true)
		row.name:SetPoint("TOPLEFT", 62, -14)
		row.hint = K.Text(row, K.size.small, "LEFT", "secondary")
		row.hint:SetPoint("LEFT", row.name, "RIGHT", 8, 0)
		row.hint:SetWordWrap(false)
		row.track = K.Track(row, 16)
		row.track:SetPoint("TOPLEFT", 62, -36)
		row.track:SetPoint("TOPRIGHT", -K.CARD_INSET, -36)
	end,
	update = function(row, item, width)
		local goal = item.goal
		local todo = goal.kind == "todo"
		local have, need, hint, trackLabel = G:Progress(goal)
		local label = G:Label(goal)
		width = width or row:GetWidth() or 600
		row.art:SetShown(not todo)
		row.check:SetShown(todo)
		row.check:SetChecked(goal.done and true or false)
		row.check:SetScript("OnClick", function() if item.onTick then item.onTick(goal) end end)
		if not todo then K.SetIcon(row.art.icon, G:Icon(goal)) end
		row.hint:SetText(hint or "")
		local hintWidth = math.ceil(row.hint:GetStringWidth())
		local room = math.max(width - 62 - K.CARD_INSET - hintWidth - 8 - 96, 60)
		row.name:SetText(label)
		row.name:SetWordWrap(todo)
		row.name:SetMaxLines(todo and 2 or 1)
		row.name:SetWidth(math.min(math.ceil(row.name:GetStringWidth()) + 2, room))
		row.name:ClearAllPoints()
		row.name:SetPoint(todo and "LEFT" or "TOPLEFT", row, todo and "LEFT" or "TOPLEFT", 62, todo and 0 or -14)
		row.track:SetShown(not todo)
		if not todo then row.track:SetProgress(have, need, trackLabel) end
		row:SetScript("OnClick", todo and function() if item.onTick then item.onTick(goal) end end or nil)
		row.hover:SetShown(todo)
		Kit().Tooltip(row, label, function(tooltip)
			local c = K.Ink("secondary")
			if hint and hint ~= "" then tooltip:AddLine(hint, c[1], c[2], c[3], true) end
			if todo then
				E:TooltipHint(tooltip, { L["Click"], goal.done and L["uncheck it"] or L["check it off"] })
			else
				tooltip:AddLine(trackLabel or ("%s / %s"):format(BreakUpLargeNumbers(have), BreakUpLargeNumbers(need)), c[1], c[2], c[3])
			end
		end)
		K.HoverLinks(row, item.links)
		row:EnableMouse(true)
	end,
}

-- medals: { goals = { goal, ... } up to 5, links = fn(goal) }
local function CreateMedal(parent)
	local medal = CreateFrame("Frame", nil, parent)
	medal:EnableMouse(true)
	medal.art = K.Art(medal, 40)
	medal.art:SetPoint("TOP", 0, -22)
	medal.label = K.Text(medal, K.size.small, "CENTER", "body")
	-- Under the 40 px art.
	medal.label:SetPoint("TOPLEFT", 4, -(22 + 40 + 6))
	medal.label:SetPoint("TOPRIGHT", -4, -(22 + 40 + 6))
	medal.label:SetWordWrap(true)
	medal.label:SetMaxLines(2)
	medal.date = K.Text(medal, K.size.caption, "CENTER", "secondary")
	medal.date:SetPoint("BOTTOM", 0, 10)
	return medal
end

K.ROWS.advMedals = {
	height = function() return MEDAL_HEIGHT end,
	create = function(row)
		row:EnableMouse(false)
		row.medals = {}
		for index = 1, 5 do row.medals[index] = CreateMedal(row) end
	end,
	update = function(row, item, width)
		width = width or row:GetWidth() or 600
		local each = math.floor(width / 5)
		for index, medal in ipairs(row.medals) do
			local goal = item.goals[index]
			medal:SetShown(goal ~= nil)
			if goal then
				medal:ClearAllPoints()
				medal:SetPoint("TOPLEFT", row, "TOPLEFT", (index - 1) * each, 0)
				medal:SetSize(each, MEDAL_HEIGHT)
				K.SetIcon(medal.art.icon, G:Icon(goal))
				local good = K.Ink("good")
				medal.art:SetBackdropBorderColor(good[1], good[2], good[3])
				local label = G:Label(goal)
				medal.label:SetText(label)
				medal.date:SetText(G.DateText(goal.doneAt))
				Kit().Tooltip(medal, label, (L["Reached %s."]):format(G.DateText(goal.doneAt)))
				K.HoverLinks(medal, item.links and item.links(goal) or nil)
			end
		end
	end,
}

-- tiles: { kinds = { def, def }, onPick = fn(def) }
local function CreateTile(parent)
	local tile = CreateFrame("Button", nil, parent)
	tile:RegisterForClicks("LeftButtonUp")
	tile.card = K.Card(tile)
	tile.card:SetAllPoints()
	tile.card:SetFrameLevel(math.max(tile:GetFrameLevel() - 1, 0))
	UI.Hover(tile)
	tile.art = K.Art(tile, 36)
	tile.art:SetPoint("LEFT", 10, 0)
	tile.name = K.Text(tile, K.size.body, "LEFT", "body")
	tile.name:SetPoint("TOPLEFT", tile.art, "TOPRIGHT", 10, 0)
	tile.name:SetPoint("TOPRIGHT", tile, "RIGHT", -10, 18) -- the art's top: it is 36 px, centered
	tile.name:SetWordWrap(false)
	tile.desc = K.Text(tile, K.size.small, "LEFT", "secondary")
	tile.desc:SetPoint("TOPLEFT", tile.name, "BOTTOMLEFT", 0, -3)
	tile.desc:SetPoint("TOPRIGHT", tile.name, "BOTTOMRIGHT", 0, -3)
	tile.desc:SetWordWrap(true)
	tile.desc:SetMaxLines(2)
	E:SkinHoverPress(tile)
	return tile
end

K.ROWS.advTiles = {
	height = function() return TILE_HEIGHT + 10 end,
	create = function(row)
		row:EnableMouse(false)
		row.tiles = { CreateTile(row), CreateTile(row) }
	end,
	update = function(row, item, width)
		width = width or row:GetWidth() or 600
		local each = math.floor((width - 10) / 2)
		for index, tile in ipairs(row.tiles) do
			local def = item.kinds[index]
			tile:SetShown(def ~= nil)
			if def then
				tile:ClearAllPoints()
				tile:SetPoint("TOPLEFT", row, "TOPLEFT", (index - 1) * (each + 10), 0)
				tile:SetSize(each, TILE_HEIGHT)
				K.SetIcon(tile.art.icon, def.icon)
				tile.name:SetText(def.title)
				tile.desc:SetText(def.desc)
				tile:SetScript("OnClick", function() if item.onPick then item.onPick(def) end end)
				Kit().Tooltip(tile, def.title, def.desc)
			end
		end
	end,
}

---------------------------------------------------------------------------
-- The page
---------------------------------------------------------------------------
local Page = {}
UI.GoalsPage = Page
local page

local CONTROLS_Y = -60
local LIST_Y = -88

local function Toast(text, warn)
	if page and page:IsVisible() then E.UIKit.Toast(page, text, { anchor = page.list, point = "BOTTOM", y = 8, warn = warn }) end
end

local function SetView(view, kind)
	page.view = view
	if kind then page.kind = kind end
	Page.Refresh()
end
Page.SetView = SetView

local function Undoable(trashID, text)
	if not trashID then return end
	K.UndoToast(page, text, trashID, function() Page.Refresh() end)
end

local function ListItems()
	local active, reached = G:List()
	local items = {}
	local filtered = 0
	for _, goal in ipairs(active) do
		if Query(G:Label(goal), "goals") then
			filtered = filtered + 1
			items[#items + 1] = {
				kind = "advGoal", goal = goal,
				onTick = function(g)
					G:Tick(g.id)
					Page.Refresh()
				end,
				links = {
					{ L["Delete"], function() Undoable(G:Delete(goal.id), L["Goal deleted."]) Page.Refresh() end,
						L["Removes this goal. You can undo it for a moment."] },
					{ L["Archive"], function() G:Archive(goal.id, true) Page.Refresh() end,
						L["Hides this goal from the page. The archive keeps it."] },
				},
			}
		end
	end
	local shownReached = {}
	for _, goal in ipairs(reached) do
		if Query(G:Label(goal), "goals") then shownReached[#shownReached + 1] = goal end
	end
	if shownReached[1] then
		local open = K.FoldOpen("goals.reached", true)
		items[#items + 1] = { kind = "space", height = 6 }
		items[#items + 1] = { kind = "fold", key = "goals.reached", label = L["Reached"], note = tostring(#shownReached),
			open = open, onToggle = function() Page.Refresh() end }
		if open then
			for first = 1, #shownReached, 5 do
				local chunk = {}
				for index = first, math.min(first + 4, #shownReached) do chunk[#chunk + 1] = shownReached[index] end
				items[#items + 1] = { kind = "advMedals", goals = chunk, links = function(goal)
					local links = {}
					if goal.kind == "todo" then
						links[#links + 1] = { L["Undo"], function() G:Tick(goal.id) Page.Refresh() end, L["Moves this to-do back to your goals."] }
					end
					links[#links + 1] = { L["Archive"], function() G:Archive(goal.id, true) Page.Refresh() end,
						L["Hides this goal from the page. The archive keeps it."] }
					return links
				end }
			end
			items[#items + 1] = { kind = "more", text = L["Archive every reached goal"], onClick = function()
				local count = G:ArchiveReached()
				Page.Refresh()
				if count > 0 then Toast((E:Plural(count, "%d goal moved to the archive.", "%d goals moved to the archive.")):format(count)) end
			end }
		end
	end
	return items, filtered + #shownReached, #active, #reached
end

local function ArchiveItems()
	local _, _, archived = G:List()
	local items = {}
	local shown = {}
	for _, goal in ipairs(archived) do
		if Query(G:Label(goal), "goals") then shown[#shown + 1] = goal end
	end
	for index, goal in ipairs(shown) do
		local sub
		if goal.done then
			sub = (L["Reached %s · archived %s"]):format(G.DateText(goal.doneAt), G.DateText(goal.archived))
		else
			sub = (L["Set %s · archived %s"]):format(G.DateText(goal.created), G.DateText(goal.archived))
		end
		items[#items + 1] = {
			kind = "ledger", icon = G:Icon(goal), title = G:Label(goal), sub = sub,
			position = #shown == 1 and "only" or index == 1 and "first" or index == #shown and "last" or "middle",
			links = {
				{ L["Delete"], function() Undoable(G:Delete(goal.id), L["Goal deleted."]) Page.Refresh() end,
					L["Removes this goal for good. You can undo it for a moment."] },
				{ L["Restore"], function() G:Archive(goal.id, false) Page.Refresh() end, L["Puts this goal back on the page."] },
			},
		}
	end
	return items
end

local function PickItems()
	local items = {}
	local kinds = G:Kinds()
	for first = 1, #kinds, 2 do
		items[#items + 1] = { kind = "advTiles", kinds = { kinds[first], kinds[first + 1] },
			onPick = function(def) Page.OpenForm(def.key) end }
	end
	return items
end

---------------------------------------------------------------------------
-- The form
---------------------------------------------------------------------------
local Form = {}

local function FieldLabel(parent)
	local fs = K.Text(parent, K.size.body, "LEFT", "head")
	fs:SetWordWrap(false)
	return fs
end

local function StepOf(def)
	return def and def.count and def.count.step or 1
end

local function SetCount(value)
	local def = G:Kind(page.kind)
	local spec = def and def.count
	if not spec then return end
	local max = type(spec.max) == "function" and spec.max() or spec.max or G.MAX_COUNT
	value = math.min(math.max(math.floor(tonumber(value) or 0), spec.min or 1), max)
	page.form.count:SetText(tostring(value))
end

local function Bump(direction)
	local def = G:Kind(page.kind)
	local step = StepOf(def) * (IsShiftKeyDown() and 10 or 1)
	SetCount((tonumber(page.form.count:GetText()) or 0) + direction * step)
end

local function SetItem(itemID)
	local form = page.form
	form.itemID = itemID
	if itemID then
		K.SetIcon(form.slot.art.icon, G.ItemIcon(itemID) or "Interface/Icons/INV_Misc_QuestionMark")
		form.slot.plus:Hide()
		local name = G.ItemName(itemID)
		if name then form.text:SetText(name) end
	else
		form.slot.art.icon:Hide()
		form.slot.plus:Show()
	end
end

local function TakeCursorItem()
	local kind, itemID = GetCursorInfo()
	if kind == "item" and type(itemID) == "number" then
		SetItem(itemID)
		ClearCursor()
		return true
	end
	return false
end

function Form.Build(parent)
	local form = CreateFrame("Frame", nil, parent)
	form:SetPoint("TOPLEFT", 0, CONTROLS_Y)
	form:SetPoint("BOTTOMRIGHT")
	form:Hide()
	form.itemLabel = FieldLabel(form)
	form.slot = CreateFrame("Button", nil, form)
	form.slot:SetSize(36, 36)
	form.slot:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	form.slot.art = K.Art(form.slot, 36)
	form.slot.art:SetAllPoints()
	form.slot.art.icon:Hide()
	form.slot.plus = K.Text(form.slot, 16, "CENTER", "dim")
	form.slot.plus:SetPoint("CENTER")
	form.slot.plus:SetText("+")
	UI.Hover(form.slot)
	form.slot:SetScript("OnReceiveDrag", TakeCursorItem)
	form.slot:SetScript("OnClick", function()
		if not TakeCursorItem() then
			SetItem(nil)
			form.text:SetText("")
		end
	end)
	Kit().Tooltip(form.slot, L["Item"], L["Drop an item here from your bags, or shift-click one."], { { L["Click"], L["clear it"] } })
	form.orLabel = K.Text(form, K.size.small, "LEFT", "secondary")
	form.textLabel = FieldLabel(form)
	form.text = UI.EditBox(form, { letters = 200 })
	form.text:SetScript("OnEnterPressed", function() Page.Submit() end)
	form.text:SetScript("OnTextChanged", function(_, typed)
		if typed and page.kind ~= "item" then page.form.target = nil end
	end)
	form.chips = UI.Chips(form)
	form.countLabel = FieldLabel(form)
	form.minus = Kit().IconButton(form, 20, nil, function() Bump(-1) end, L["Fewer"],
		L["Steps the number down. Shift-click steps ten times as far."], "-")
	form.count = UI.EditBox(form, { letters = 5, width = 70, numeric = true })
	form.count:SetJustifyH("CENTER")
	form.count:SetScript("OnEnterPressed", function() Page.Submit() end)
	form.count:EnableMouseWheel(true)
	form.count:SetScript("OnMouseWheel", function(_, delta) Bump(delta > 0 and 1 or -1) end)
	form.plus = Kit().IconButton(form, 20, nil, function() Bump(1) end, L["More"],
		L["Steps the number up. Shift-click steps ten times as far."], "+")
	form.stepHint = K.Text(form, K.size.small, "LEFT", "secondary")
	form.standingLabel = FieldLabel(form)
	local options = {}
	for _, reaction in ipairs(G.STANDINGS) do options[#options + 1] = { reaction, G.StandingName(reaction) } end
	form.standing = K.Switch(form, options, 7, function(value) page.form.standingValue = value end)
	-- Set goal sits right under the last question (the level picker for a
	-- level goal); Back stays in the header.
	form.submit = E.UIKit.Button(form, { text = L["Set goal"], kind = "primary", minWidth = 96, onClick = function() Page.Submit() end,
		tipTitle = L["Set goal"], tip = L["Saves the goal. Its progress moves by itself as the game reports it."] })
	form.error = K.Text(form, K.size.label, "LEFT", "bad")
	form.error:SetWordWrap(true)
	UI.AddLinkTarget({
		active = function() return page and page:IsVisible() and page.view == "form" end,
		take = function(link)
			local kind = page.kind
			local itemID = tonumber(link:match("|Hitem:(%d+)"))
			local questID = tonumber(link:match("|Hquest:(%d+)"))
			if itemID and (kind == "item" or kind == "wish") then
				if kind == "item" then SetItem(itemID) else
					page.form.target = itemID
					page.form.text:SetText(G.ItemName(itemID, link:match("%[(.-)%]")) or "")
				end
				return true
			end
			if questID and kind == "quest" then
				page.form.target = questID
				page.form.text:SetText(G.QuestTitle(questID, link:match("%[(.-)%]")) or "")
				return true
			end
			if page.form.text:HasFocus() then
				page.form.text:Insert(G.Plainify(link))
				return true
			end
			return false
		end,
	})
	return form
end

-- Lays the questions of one kind out from the top.
function Form.Fill(kindKey)
	local def = G:Kind(kindKey)
	local form = page.form
	if not def then return end
	form.itemID, form.target, form.standingValue = nil, nil, 7
	form.error:SetText("")
	form.text:SetText("")
	SetItem(nil)
	local y = 0
	local function Place(region, x, height, gap)
		region:ClearAllPoints()
		region:SetPoint("TOPLEFT", form, "TOPLEFT", x or 0, -y)
		y = y + (height or 20) + (gap or 8)
	end
	local isItem = def.input == "item"
	form.itemLabel:SetShown(isItem)
	form.slot:SetShown(isItem)
	form.orLabel:SetShown(isItem)
	if isItem then
		form.itemLabel:SetText(def.question or L["Which item?"])
		Place(form.itemLabel, 0, 16, 6)
		form.slot:ClearAllPoints()
		form.slot:SetPoint("TOPLEFT", form, "TOPLEFT", 0, -y)
		form.orLabel:ClearAllPoints()
		form.orLabel:SetPoint("TOPLEFT", form.slot, "TOPRIGHT", 12, 0)
		form.orLabel:SetText(L["Or type its name:"])
		form.text:ClearAllPoints()
		form.text:SetPoint("TOPLEFT", form.orLabel, "BOTTOMLEFT", 4, -4)
		form.text:SetWidth(300)
		y = y + 36 + 12
	end
	local hasText = def.input == "text"
	form.textLabel:SetShown(hasText)
	form.text:SetShown(hasText or isItem)
	if hasText then
		form.textLabel:SetText(def.question or "")
		Place(form.textLabel, 0, 16, 6)
		form.text:ClearAllPoints()
		form.text:SetPoint("TOPLEFT", form, "TOPLEFT", 4, -y)
		form.text:SetWidth(320)
		y = y + 22 + 8
	end
	local suggestions = def.suggest and Safe(def.suggest) or {}
	form.chips:ClearAllPoints()
	form.chips:SetPoint("TOPLEFT", form, "TOPLEFT", 0, -y)
	form.chips:SetPoint("TOPRIGHT", form, "TOPRIGHT", 0, -y)
	form.chips:Set(suggestions, function(data)
		form.text:SetText(data.label == data.value and data.value or tostring(data.value))
		form.target = data.extra
		if kindKey == "item" and data.extra then SetItem(data.extra) end
	end)
	if suggestions[1] then y = y + form.chips:GetHeight() + 10 end
	local spec = def.count
	for _, region in ipairs({ form.countLabel, form.minus, form.count, form.plus, form.stepHint }) do region:SetShown(spec ~= nil) end
	if spec then
		form.countLabel:SetText(spec.question or L["How many?"])
		Place(form.countLabel, 0, 16, 6)
		form.minus:ClearAllPoints()
		form.minus:SetPoint("TOPLEFT", form, "TOPLEFT", 0, -(y + 1))
		form.count:ClearAllPoints()
		form.count:SetPoint("LEFT", form.minus, "RIGHT", 8, 0)
		form.plus:ClearAllPoints()
		form.plus:SetPoint("LEFT", form.count, "RIGHT", 8, 0)
		form.stepHint:ClearAllPoints()
		form.stepHint:SetPoint("LEFT", form.plus, "RIGHT", 12, 0)
		form.stepHint:SetText((L["Shift-click the arrows to step by %s."]):format(BreakUpLargeNumbers(spec.step * 10)))
		y = y + 22 + 10
		SetCount(spec.default and spec.default() or 1)
	end
	form.standingLabel:SetShown(def.standing == true)
	form.standing:SetShown(def.standing == true)
	if def.standing then
		form.standingLabel:SetText(L["Which standing?"])
		Place(form.standingLabel, 0, 16, 6)
		form.standing:SetActive(7)
		Place(form.standing, 0, 18, 10)
	end
	y = y + 4
	Place(form.submit, 0, form.submit:GetHeight(), 8)
	form.error:ClearAllPoints()
	form.error:SetPoint("TOPLEFT", form, "TOPLEFT", 0, -y)
	form.error:SetPoint("TOPRIGHT", form, "TOPRIGHT", 0, -y)
end

function Page.OpenForm(kindKey)
	page.kind = kindKey
	page.view = "form"
	Form.Fill(kindKey)
	Page.Refresh()
	local def = G:Kind(kindKey)
	if def and def.input == "text" then C_Timer.After(0, function() if page.form:IsVisible() then page.form.text:SetFocus() end end) end
end

function Page.Submit()
	if not (page and page.view == "form") then return end
	local form = page.form
	local def = G:Kind(page.kind)
	if not def then return end
	local goal, err = G:Add({
		kind = page.kind, text = form.text:GetText(), item = form.text:GetText(), itemID = form.itemID,
		target = form.target, need = def.count and tonumber(form.count:GetText()) or nil,
		standing = form.standingValue,
	})
	if not goal then
		form.error:SetText(err or L["That goal could not be set."])
		return
	end
	form.text:ClearFocus()
	form.count:ClearFocus()
	page.view = "list"
	Page.Refresh()
	Toast((L["New goal: %s"]):format(G:Label(goal)))
end

---------------------------------------------------------------------------
-- Drawing the page
---------------------------------------------------------------------------
local function HeaderFor(view, activeCount, reachedCount)
	local header = page.header
	local _, _, archived = G:List()
	if view == "form" then
		local def = G:Kind(page.kind)
		header:SetTitle(def and def.title or L["A new goal"])
		header:SetSentence(def and def.desc or "")
		header:SetActions({ { L["Back"], function() SetView("pick") end, L["Back to the goal kinds."] } })
	elseif view == "pick" then
		header:SetTitle(L["A new goal"])
		header:SetSentence(L["What would you like to work towards?"])
		header:SetActions({ { L["Back"], function() SetView("list") end, L["Back to your goals."] } })
	elseif view == "archive" then
		header:SetTitle(L["Archived goals"])
		header:SetSentence(L["Hidden from the page until you restore them. Delete removes them for good."])
		header:SetActions({ { L["Back"], function() SetView("list") end, L["Back to your goals."] } })
	else
		header:SetTitle(L["Goals"])
		if activeCount > 0 then
			header:SetSentence((E:Plural(activeCount, "%s thing to work towards.", "%s things to work towards.")):format(K.Num(activeCount)))
		elseif reachedCount > 0 then
			header:SetSentence(L["Everything reached. Start a new one with New goal."])
		else
			header:SetSentence(L["Nothing to work towards yet. Start one with New goal."])
		end
		local actions = { { L["New goal"], function() SetView("pick") end, L["Pick what you want to work towards."] } }
		if #archived > 0 then
			actions[#actions + 1] = { (L["Archive %s"]):format(#archived), function() SetView("archive") end,
				L["Goals you archived. Restore or delete them there."] }
		end
		header:SetActions(actions)
	end
end

function Page.Refresh()
	if not page then return end
	if not A:Running() then
		page.header:SetTitle(L["Goals"])
		page.header:SetSentence(A:OffReason() or "")
		page.header:SetActions({})
		page.list:SetEmpty(L["My Adventure is off"], A:OffReason() or "", G.ICON_TODO)
		page.list:SetData({})
		page.form:Hide()
		return
	end
	local view = page.view or "list"
	local activeCount, reachedCount = G:CountActive(), select(2, G:List())
	reachedCount = #reachedCount
	HeaderFor(view, activeCount, reachedCount)
	local isForm = view == "form"
	page.form:SetShown(isForm)
	page.list:SetShown(not isForm)
	page.search:SetShown(view == "list" or view == "archive")
	if isForm then return end
	local items
	if view == "pick" then
		page.list:ClearAllPoints()
		page.list:SetPoint("TOPLEFT", 0, CONTROLS_Y)
		page.list:SetPoint("BOTTOMRIGHT")
		page.list:SetEmpty(nil, nil)
		items = PickItems()
	else
		page.list:ClearAllPoints()
		page.list:SetPoint("TOPLEFT", 0, LIST_Y)
		page.list:SetPoint("BOTTOMRIGHT")
		if view == "archive" then
			items = ArchiveItems()
			page.list:SetEmpty(L["No archived goals"], L["Goals you archive wait here until you restore or delete them."], G.ICON_TODO)
		else
			local shown
			items, shown = ListItems()
			if shown == 0 and (activeCount > 0 or reachedCount > 0) then
				page.list:SetEmpty(L["Nothing matches"], L["No goal matches that search."], "Interface/Icons/Ability_Tracking")
			else
				page.list:SetEmpty(L["Nothing to work towards yet"], L["Set a goal: reach a level, collect an item, run a dungeon."],
					"Interface/Icons/Ability_Tracking", { { L["New goal"], function() SetView("pick") end, L["Pick what you want to work towards."] } })
			end
		end
	end
	page.list:SetData(items, true)
	if page.focus then
		for index, item in ipairs(items) do
			if item.goal and item.goal.id == page.focus then page.list:ScrollTo(index, "center") end
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
	page.search = K.Search(page, "goals", L["Search goals"], function() Page.Refresh() end)
	page.search:SetPoint("TOPLEFT", 6, CONTROLS_Y)
	page.search:SetWidth(260)
	page.list = K.CreateJournalList(page, { gap = 0 })
	page.list:SetPoint("TOPLEFT", 0, LIST_Y)
	page.list:SetPoint("BOTTOMRIGHT")
	page.form = Form.Build(page)
	page:SetScript("OnShow", function() Page.Refresh() end)
	if J.RegisterCallback then
		J.RegisterCallback(Page, "Redraw", function(_, what)
			if page:IsVisible() and page.view ~= "form" and type(what) == "table"
				and (what.goals or what.all or what.settings or what.sources) then
				Page.Refresh()
			end
		end)
	end
	Page.frame = page
	return page
end

-- arg: nil, "new", "archive", a kind key, a goal id or "journal:goal:<id>".
local function Show(frame, arg)
	page = frame or page
	if not page then return end
	if type(arg) == "string" then
		local kind, id = J:ParseAddress(arg)
		if kind == "goal" then arg = id end
	end
	if arg == "new" then
		page.view = "pick"
	elseif arg == "archive" then
		page.view = "archive"
	elseif type(arg) == "string" and G:Kind(arg) then
		Page.OpenForm(arg)
		return
	elseif tonumber(arg) and G:Get(arg) then
		page.view = "list"
		page.focus = tonumber(arg)
		K.SetFoldOpen("goals.reached", true)
	elseif not arg then
		page.view = "list"
	end
	Page.Refresh()
end

local function Hide(frame)
	frame = frame or page
	if frame and frame.form then
		frame.form.text:ClearFocus()
		frame.form.count:ClearFocus()
	end
end

Page.Build, Page.Show, Page.Hide = Build, Show, Hide

UI.RegisterSection("goals", {
	title = "Goals",
	icon = "Interface/Icons/Ability_Tracking",
	desc = "Things you want to work towards. Their progress moves by itself as the game reports it.",
	order = 30,
	group = "today",
	count = function() return A:Running() and G:CountActive() or 0 end,
	build = Build,
	show = Show,
	hide = Hide,
})
