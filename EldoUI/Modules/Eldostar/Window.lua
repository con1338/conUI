-- EldoUI Eldostar: the guide window.
--
--   Standard view                              Compact view
--   +----------------------------------+       +----------------------------------+
--   | Elwynn Forest 1-10   12/80  ^  x |       | 12/80 Northshire Abbey      v  x |
--   |----------------------------------|       | o Kill Kobold Vermin  4/8   <  > |
--   | Northshire Abbey                 |       +----------------------------------+
--   | The guide's tip for the step     |
--   | v Accept A Threat Within         |
--   | o Kill Kobold Vermin        4/8  |
--   | ALONG THE WAY                    |
--   | o Collect Linen Cloth       1/5  |
--   |----------------------------------|
--   | <  Undo               Skip  Next |
--   +----------------------------------+
--
-- One frame, EldoUI_Eldostar, on its own mover. The mover takes the
-- layout's guide spot (the same point the layout gives the guide of
-- another addon), so no layout needs a point of its own for it. The
-- window is a plain frame: it shows, hides and takes clicks in combat
-- like any other window, and nothing in it is protected.
--
-- The guide's title opens the guide list in the Journal. A goal the game
-- cannot answer is ticked with a click; one the game answers ticks by
-- itself. The window follows the shared visibility rules (alpha only) and
-- the style presets; the resize grip sizes the standard view.
local _, E = ...
local L = E.L
local M = E.Eldostar
local UI = E.UIKit

local MOVER = M.MOVER
local WIDTH, HEIGHT = 300, 260
local MIN_WIDTH, MIN_HEIGHT = 220, 170
local PAD = 8
local HEADER = 24
local FOOTER = 30
local ICON = 16
local MARK = 12

local OPTIONS_LINK = { page = "module:Eldostar" }

local function Size()
	return tonumber(M.db and M.db.fontSize) or E.tokens.size.body
end

local function Compact()
	return M.db and M.db.view == "compact"
end

local function Locked()
	return (M.db and M.db.locked) or E:IsMoverLocked(MOVER)
end

---------------------------------------------------------------------------
-- Goal rows
---------------------------------------------------------------------------
local TIP_MANUAL = L["Click to check this off when it is done. Click again to uncheck it."]
local TIP_AUTO = L["The game reports this one, so it ticks by itself."]

local function CountText(entry)
	if entry.have and entry.need and entry.need > 1 then return ("%d/%d"):format(entry.have, entry.need) end
	return nil
end

local function GoalWidth(width)
	return math.max((width or WIDTH) - 2 * PAD - MARK - 6 - 40, 40)
end

local function ItemHeight(item, _, width)
	local size = Size()
	if item.kind == "section" then return size + 10 end
	if item.kind == "space" then return 4 end
	if item.kind == "tip" or item.kind == "notice" or item.kind == "alongNote" then
		return UI.TextHeight(item.text, (width or WIDTH) - 2 * PAD, size - 1) + 6
	end
	return UI.TextHeight(M.EntryText(item.entry), GoalWidth(width), size) + 6
end

local function ItemKind(item)
	if item.kind == "goal" or item.kind == "along" then return "goal" end
	if item.kind == "space" then return "space" end
	return "text"
end

local function CreateRow(row, kind)
	if kind == "space" then
		row:EnableMouse(false)
		return
	end
	if kind == "text" then
		row:EnableMouse(false)
		row.text = UI.Text(row, Size() - 1, "LEFT", "secondary")
		-- Top corners only: the text is as tall as its lines.
		row.text:SetPoint("TOPLEFT", PAD, -3)
		row.text:SetPoint("TOPRIGHT", -PAD, -3)
		row.text:SetWordWrap(true)
		return
	end
	row.hover = row:CreateTexture(nil, "HIGHLIGHT")
	row.hover:SetAllPoints()
	row.hover:SetColorTexture(1, 1, 1, E.tokens.hover.row)
	row.mark = row:CreateTexture(nil, "ARTWORK")
	row.mark:SetSize(MARK, MARK)
	row.mark:SetPoint("TOPLEFT", PAD, -4)
	row.count = UI.Text(row, Size() - 1, "RIGHT", "secondary")
	row.count:SetPoint("TOPRIGHT", -PAD, -3)
	row.count:SetWidth(40)
	row.text = UI.Text(row, Size(), "LEFT")
	row.text:SetPoint("TOPLEFT", row.mark, "TOPRIGHT", 6, 1)
	row.text:SetPoint("TOPRIGHT", row.count, "TOPLEFT", -2, 0)
	row.text:SetWordWrap(true)
	row:RegisterForClicks("LeftButtonUp")
	row:SetScript("OnClick", function(self, button)
		if E:IsOptionsLinkClick(self, button) then return end
		local entry = self.item and self.item.entry
		if entry and not entry.auto then M:ToggleGoal(entry.key) end
	end)
	E:BindOptionsLink(row, OPTIONS_LINK)
end

local function UpdateRow(row, item, _, kind)
	local size = Size()
	if kind == "space" then return end
	if kind == "text" then
		E:SetFont(row.text, math.max(size - 1, 9))
		row.text:SetText(item.text or "")
		if item.kind == "section" then
			E:SetHeaderFont(row.text, math.max(size - 1, 9))
			row.text:SetTextColor(UI.Accent())
			row.text:SetText((item.text or ""):upper())
		elseif item.kind == "notice" then
			UI.Paint(row.text, "warn")
		else
			UI.Paint(row.text, "secondary")
		end
		return
	end
	local entry = item.entry
	local note = entry.goal.kind == "note"
	E:SetFont(row.text, size)
	E:SetFont(row.count, math.max(size - 1, 9))
	row.text:SetText(M.EntryText(entry))
	row.count:SetText(CountText(entry) or "")
	row.mark:SetShown(not note)
	if entry.done then
		UI.SetGlyph(row.mark, "check")
		row.mark:SetVertexColor(unpack(E.tokens.text.good))
		UI.Paint(row.text, "dim")
	elseif entry.leftOut then
		-- A quest this character never took: shown, dimmed, for a player
		-- who does have it, and it doesn't hold the step.
		UI.SetGlyph(row.mark, "dot")
		row.mark:SetVertexColor(unpack(E.tokens.text.secondary))
		UI.Paint(row.text, "dim")
	else
		UI.SetGlyph(row.mark, "dot")
		row.mark:SetVertexColor(unpack(entry.auto and E.tokens.text.secondary or E.media.accentColor))
		UI.Paint(row.text, note and "secondary" or nil)
	end
	local manual = not (entry.auto or note)
	row.hover:SetShown(manual)
	row:EnableMouse(not note)
	if note then
		UI.Tooltip(row, nil, nil)
	else
		local lines = M.GoalDetails(entry.goal)
		if entry.leftOut then lines[#lines + 1] = L["You don't have this quest, so it doesn't hold the step up."] end
		lines[#lines + 1] = manual and TIP_MANUAL or TIP_AUTO
		UI.Tooltip(row, M.GoalText(entry.goal), table.concat(lines, "\n"))
	end
end

-- The list items of a step: tip, notice, goals, then the goals along the way.
function M:StepItems(view)
	local items = {}
	if view.notice then items[#items + 1] = { kind = "notice", text = view.notice } end
	if self.db.showTip and view.step.tip then items[#items + 1] = { kind = "tip", text = view.step.tip } end
	if #items > 0 then items[#items + 1] = { kind = "space" } end
	for _, entry in ipairs(view.goals) do items[#items + 1] = { kind = "goal", entry = entry } end
	if self.db.showAlong then
		local notes = self.db.showTip and view.alongNotes or {}
		if #view.along > 0 then
			items[#items + 1] = { kind = "space" }
			items[#items + 1] = { kind = "section", text = L["Along the way"] }
			for _, note in ipairs(notes) do items[#items + 1] = { kind = "alongNote", text = note } end
			for _, entry in ipairs(view.along) do items[#items + 1] = { kind = "along", entry = entry } end
		end
	end
	return items
end

-- The first goal of the step not done yet (the compact view's line).
local function FirstOpen(view)
	for _, entry in ipairs(view.goals or {}) do
		if not entry.done and entry.counts then return entry end
	end
end

---------------------------------------------------------------------------
-- Placing: on the mover, or held under the game's player frame while a
-- fresh profile waits for its setup (the same rule as the guide spot's
-- other guide, Modules/Integrations.lua).
---------------------------------------------------------------------------
function M:PlaceWindow()
	local frame, mover = self.frame, E.movers[MOVER]
	if not (frame and mover) then return end
	local left, top = mover:GetLeft(), mover:GetTop()
	local width, height = frame:GetSize()
	local held = E.GuideSpotSafeTop and left and top and E:GuideSpotSafeTop(left, top, width, height) or nil
	self.held = held ~= nil
	frame:ClearAllPoints()
	if held then
		frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, held)
	else
		frame:SetPoint("CENTER", mover, "CENTER")
	end
end

-- The size of the view: the saved (or design) size of the standard view;
-- the compact view keeps its width and takes two lines.
function M:ApplySize()
	local frame = self.frame
	if not frame then return end
	local store = self.db.window
	local width = store and tonumber(store.w) or WIDTH
	if Compact() then
		local size = Size()
		frame:SetSize(math.max(MIN_WIDTH, width), 2 * (size + 10) + 8)
	elseif not frame.grip:Restore() then
		frame:SetSize(WIDTH, HEIGHT)
	end
	frame.grip:SetShown(not Compact() and not Locked())
	self:PlaceWindow()
end

---------------------------------------------------------------------------
-- The frame
---------------------------------------------------------------------------
local function Button(parent, text, onClick, tipTitle, tip)
	local button = UI.Button(parent, text, 60, E.tokens.height.button, function(self, mouse)
		if E:IsOptionsLinkClick(self, mouse) then return end
		onClick()
	end, tipTitle, tip)
	UI.FitButton(button, 48)
	E:BindOptionsLink(button, OPTIONS_LINK)
	return button
end

local function IconButton(parent, glyph, onClick, tipTitle, tip)
	return UI.IconButton(parent, ICON, glyph, function() onClick() end, tipTitle, tip, nil, { options = OPTIONS_LINK })
end

local function BrowseGuides()
	if not M:OpenPicker() then
		E:Print(L["The guide list is in the Journal, under My Adventure. Turn My Adventure on to browse the guides."])
	end
end

function M:CreateWindow()
	if self.frame then return self.frame end
	local frame = CreateFrame("Frame", MOVER, UIParent)
	frame:SetSize(WIDTH, HEIGHT)
	frame:SetFrameStrata("MEDIUM")
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)
	frame:Hide()
	E:SetPanelTemplate(frame, self.db.transparent)
	self.frame = frame

	-- Header: the guide's title (opens the guide list), the step count,
	-- the view switch and the close button.
	frame.close = IconButton(frame, "cross", function()
		M.Store().hidden = true
		M:ShowWindow()
	end, L["Close"], L["Hides the guide window for this character. /eui eldostar show brings it back."])
	frame.close:SetPoint("TOPRIGHT", -4, -4)
	frame.viewButton = IconButton(frame, "chevron-up", function()
		M.db.view = Compact() and "standard" or "compact"
		M:ApplyLook()
		M:UpdateWindow()
	end)
	frame.viewButton:SetPoint("RIGHT", frame.close, "LEFT", -2, 0)
	frame.count = UI.Text(frame, E.tokens.size.small, "RIGHT", "secondary")
	frame.count:SetPoint("RIGHT", frame.viewButton, "LEFT", -4, 0)
	frame.titleButton = CreateFrame("Button", nil, frame)
	-- Centered on the header like the buttons beside it.
	frame.titleButton:SetPoint("LEFT", frame, "TOPLEFT", PAD, -HEADER / 2)
	frame.titleButton:SetPoint("RIGHT", frame.count, "LEFT", -6, 0)
	frame.titleButton:SetHeight(HEADER - 8)
	frame.titleButton:RegisterForClicks("LeftButtonUp")
	frame.titleButton:SetScript("OnClick", function(button, mouse)
		if E:IsOptionsLinkClick(button, mouse) then return end
		BrowseGuides()
	end)
	-- A title cut short shows in full in the tooltip.
	UI.Tooltip(frame.titleButton, L["Guides"], function(tip)
		local title = frame.title
		if title:IsTruncated() then UI.TipTitle(tip, title:GetText(), true) end
		UI.TipText(tip, L["Opens the guide list in the Journal, where you start another guide."])
	end)
	E:BindOptionsLink(frame.titleButton, OPTIONS_LINK)
	frame.title = UI.Text(frame.titleButton, E.tokens.size.section, "LEFT", "header")
	frame.title:SetAllPoints()
	frame.title:SetWordWrap(false)
	frame.line = UI.Divider(frame)
	frame.line:SetPoint("TOPLEFT", 1, -HEADER)
	frame.line:SetPoint("TOPRIGHT", -1, -HEADER)

	-- The step's title, then the list of tip and goals.
	frame.step = UI.Text(frame, Size() + 1, "LEFT", "header")
	frame.step:SetPoint("TOPLEFT", PAD, -HEADER - 6)
	frame.step:SetPoint("TOPRIGHT", -PAD, -HEADER - 6)
	frame.step:SetWordWrap(true)
	frame.step:SetMaxLines(2)
	frame.list = UI.CreateList(frame, {
		height = ItemHeight,
		kind = function(item) return ItemKind(item) end,
		create = CreateRow,
		update = UpdateRow,
	})

	-- Footer: back, undo, skip, next.
	frame.footer = CreateFrame("Frame", nil, frame)
	frame.footer:SetPoint("BOTTOMLEFT", 0, 0)
	frame.footer:SetPoint("BOTTOMRIGHT", 0, 0)
	frame.footer:SetHeight(FOOTER)
	frame.footLine = UI.Divider(frame.footer)
	frame.footLine:SetPoint("TOPLEFT", 1, 0)
	frame.footLine:SetPoint("TOPRIGHT", -1, 0)
	frame.prev = IconButton(frame.footer, "chevron-left", function() M:Prev() end,
		L["Previous step"], L["Goes back one step. The guide stays there until you move on."])
	frame.prev:SetPoint("LEFT", PAD - 2, -1)
	frame.undo = Button(frame.footer, L["Undo"], function() M:Undo() end,
		L["Undo"], L["Takes back the last move, skip or check-off."])
	frame.undo:SetPoint("LEFT", frame.prev, "RIGHT", 6, 0)
	frame.next = Button(frame.footer, L["Next"], function() M:Next() end,
		L["Next"], L["Moves on to the next step. A step also moves on by itself once its goals are done, when that option is on."])
	frame.next:SetPoint("RIGHT", -PAD - 12, -1)
	frame.skip = Button(frame.footer, L["Skip"], function() M:Skip() end,
		L["Skip"], L["Skips this step and remembers it as skipped. Undo takes it back."])
	frame.skip:SetPoint("RIGHT", frame.next, "LEFT", -6, 0)

	-- Compact view: the first open goal and two arrows.
	frame.goalLine = UI.Text(frame, Size(), "LEFT")
	frame.goalLine:SetWordWrap(false)
	frame.cNext = IconButton(frame, "chevron-right", function() M:Next() end,
		L["Next"], L["Moves on to the next step."])
	frame.cPrev = IconButton(frame, "chevron-left", function() M:Prev() end,
		L["Previous step"], L["Goes back one step. The guide stays there until you move on."])

	-- Message and actions for every state without a step.
	frame.message = UI.Text(frame, E.tokens.size.label, "CENTER", "secondary")
	frame.message:SetPoint("TOPLEFT", PAD + 4, -HEADER - 16)
	frame.message:SetPoint("TOPRIGHT", -PAD - 4, -HEADER - 16)
	frame.message:SetWordWrap(true)
	frame.action1 = Button(frame, "", function() if frame.action1.run then frame.action1.run() end end)
	frame.action2 = Button(frame, "", function() if frame.action2.run then frame.action2.run() end end)

	frame.grip = UI.SizeGrip(frame, {
		resize = true, width = WIDTH, height = HEIGHT, minWidth = MIN_WIDTH, minHeight = MIN_HEIGHT,
		store = function() return M.db and M.db.window end,
		onStop = function()
			-- Sizing took the frame off its mover: the mover takes the new
			-- size and the frame goes back on it.
			local width, height = frame:GetSize()
			frame:SetSize(width, height)
			M:PlaceWindow()
		end,
	})
	E:BindOptionsLink(frame, OPTIONS_LINK)

	E:CreateMover(frame, MOVER, L["Eldostar"], { "TOPRIGHT", "UIParent", "TOPRIGHT", -400, -358 },
		{ layoutAlias = "EldoUI_RXP", followShown = true, onMoved = function() M:PlaceWindow() end })
	-- A fresh profile's setup was finished or skipped: the window leaves
	-- the spot it took under the game's player frame.
	if E.Installer and type(E.Installer.SetupDone) == "function" then
		hooksecurefunc(E.Installer, "SetupDone", function()
			if M.held and M:IsLive() then M:PlaceWindow() end
		end)
	end
	self:ApplyLook()
	return frame
end

---------------------------------------------------------------------------
-- Look: style presets, text size, panel, view
---------------------------------------------------------------------------
function M:ApplyLook()
	local frame = self.frame
	if not frame then return end
	local db = self.db
	E:SetPanelTemplate(frame, db.transparent)
	local size = Size()
	E:SetHeaderFont(frame.step, size + 1)
	frame.step:SetTextColor(UI.Accent())
	E:SetFont(frame.goalLine, size)
	UI.Paint(frame.title, "header")
	-- The window's own lock follows the option once it changes; the box's
	-- lock in move mode works as it does for every frame.
	if self.lockApplied ~= db.locked then
		if self.lockApplied ~= nil or db.locked then E:SetMoverLocked(MOVER, db.locked) end
		self.lockApplied = db.locked
	end
	local compact = Compact()
	frame.viewButton:SetArt(compact and "chevron-down" or "chevron-up")
	UI.Tooltip(frame.viewButton, compact and L["Standard view"] or L["Compact view"],
		compact and L["Shows the whole step: its tip, every goal and the buttons."]
		or L["Shows the step and its next goal on two lines."])
	frame.list.dirty = true
	self:ApplySize()
end

-- The shared visibility rules (alpha only, so they work in combat).
function M:ApplyVisibility()
	local frame = self.frame
	if not frame then return end
	local block = self.db.visibility
	if type(block) ~= "table" then
		block = E:VisibilityDefaults({ instance = "hide" })
		self.db.visibility = block
	end
	if self.visibilityBlock ~= block then E:DetachVisibility(frame) end
	if E:IsVisibilityAttached(frame) then
		E:UpdateVisibility(frame)
	else
		E:AttachVisibility(frame, block, { forceShow = function() return E:IsMoveMode() end, restoreShown = false })
	end
	self.visibilityBlock = block
end

---------------------------------------------------------------------------
-- Show, hide, fill
---------------------------------------------------------------------------
function M:WindowWanted()
	return self.awake and self:IsLive() and not self.Store().hidden
end

function M:ShowWindow()
	if not self:WindowWanted() then
		self:HideWindow()
		return
	end
	local frame = self:CreateWindow()
	frame:Show()
	self:ApplyVisibility()
	self:PlaceWindow()
	self:UpdateWindow()
end

function M:HideWindow()
	local frame = self.frame
	if not frame then return end
	frame:Hide()
	if E:IsVisibilityAttached(frame) then E:DetachVisibility(frame) end
	self.visibilityBlock = nil
end

local function SetAction(button, text, run, tipTitle, tip)
	button:SetShown(text ~= nil)
	if not text then return end
	button:SetText(text)
	UI.FitButton(button, 80)
	button.run = run
	UI.Tooltip(button, tipTitle or text, tip)
end

local function ShowMessage(frame, text, first, second)
	frame.message:SetText(text or "")
	frame.message:Show()
	SetAction(frame.action1, first and first[1], first and first[2], first and first[3], first and first[4])
	SetAction(frame.action2, second and second[1], second and second[2], second and second[3], second and second[4])
	frame.action1:ClearAllPoints()
	frame.action2:ClearAllPoints()
	frame.action1:SetPoint("TOP", frame.message, "BOTTOM", 0, -12)
	frame.action2:SetPoint("TOP", frame.action1:IsShown() and frame.action1 or frame.message, "BOTTOM", 0, -6)
end

-- Which parts show for a state and view.
-- The header title: a long one steps its font down a point or two before
-- it is cut short (its tooltip still shows a cut title in full).
local TITLE_STEPS = 2
local function SetTitle(frame, text)
	local title, size = frame.title, E.tokens.size.section
	title:SetText(text or "")
	local room = frame.titleButton:GetWidth() or 0
	for step = 0, TITLE_STEPS do
		title.kitSize = size - step
		E:SetWindowFont(title, title.kitSize)
		if room <= 0 or (title:GetStringWidth() or 0) <= room then break end
	end
end

local function Parts(frame, step, compact)
	frame.step:SetShown(step and not compact)
	frame.list:SetShown(step and not compact)
	frame.footer:SetShown(step and not compact)
	frame.goalLine:SetShown(compact)
	frame.cNext:SetShown(step and compact)
	frame.cPrev:SetShown(step and compact)
	frame.line:SetShown(not compact)
	frame.message:SetShown(not step and not compact)
	frame.action1:SetShown(false)
	frame.action2:SetShown(false)
end

local function LayoutCompact(frame)
	frame.title:ClearAllPoints()
	frame.title:SetAllPoints()
	frame.cNext:ClearAllPoints()
	frame.cNext:SetPoint("BOTTOMRIGHT", -4, 6)
	frame.cPrev:ClearAllPoints()
	frame.cPrev:SetPoint("RIGHT", frame.cNext, "LEFT", -2, 0)
	frame.goalLine:ClearAllPoints()
	frame.goalLine:SetPoint("LEFT", frame, "BOTTOMLEFT", PAD, 6 + ICON / 2)
	frame.goalLine:SetPoint("RIGHT", frame.cPrev, "LEFT", -4, 0)
end

function M:UpdateWindow()
	local frame = self.frame
	if not (frame and frame:IsShown()) then return end
	local view = self:View()
	self.view = view
	local compact = Compact()
	local step = view.state == "step"
	Parts(frame, step, compact)
	if compact then LayoutCompact(frame) end

	local guide = view.guide
	if step then
		frame.count:SetText(("%d/%d"):format(view.index, view.total))
	else
		frame.count:SetText("")
	end

	if view.state == "step" then
		self:OfferTour()
		local stepTitle = view.step.title
		if compact then
			SetTitle(frame, stepTitle)
			local open = FirstOpen(view)
			local text = open and M.EntryText(open, true) or L["Every goal is done."]
			local count = open and CountText(open)
			UI.Paint(frame.goalLine)
			frame.goalLine:SetText(count and ("%s  %s"):format(text, E:TokenHex(E.tokens.text.secondary) .. count .. "|r") or text)
			frame.cPrev:SetEnabled(view.canPrev and true or false)
		else
			SetTitle(frame, guide.title)
			frame.step:SetText(stepTitle)
			frame.list:ClearAllPoints()
			frame.list:SetPoint("TOPLEFT", frame.step, "BOTTOMLEFT", -PAD, -6)
			frame.list:SetPoint("BOTTOMRIGHT", frame.footer, "TOPRIGHT", 0, 2)
			frame.list:SetData(self:StepItems(view), self.listStep == view.index)
			self.listStep = view.index
			frame.prev:SetEnabled(view.canPrev and true or false)
			frame.undo:SetEnabled(view.canUndo and true or false)
		end
		return
	end

	self.listStep = nil
	SetTitle(frame, guide and guide.title or L["Eldostar"])
	if compact then
		-- One line: what the standard view says, cut to fit; the title
		-- opens the guide list.
		local text
		if view.state == "choose" then
			text = L["Pick a guide to start."]
		elseif view.state == "finished" then
			text = L["You finished %s."]:format(guide.title)
		else
			text = view.text or self:DataStateText()
		end
		frame.goalLine:SetText(text)
		UI.Paint(frame.goalLine, "secondary")
		return
	end
	if view.state == "choose" then
		local suggest = view.suggest
		ShowMessage(frame,
			suggest and L["Pick a guide to start. For your level: %s."]:format(suggest.title) or L["Pick a guide to start."],
			suggest and { L["Start this guide"], function() M:StartGuide(suggest.id) end, suggest.title,
				L["Starts the guide where its steps fit your character."] },
			{ L["Browse guides"], BrowseGuides, L["Guides"], L["Opens the guide list in the Journal."] })
	elseif view.state == "finished" then
		local suggest = view.suggest
		local text = L["You finished %s."]:format(guide.title)
		if suggest then text = text .. "\n" .. L["Next: %s"]:format(suggest.title) end
		ShowMessage(frame, text,
			suggest and { L["Start the next guide"], function() M:StartGuide(suggest.id) end, suggest.title,
				L["Starts the guide where its steps fit your character."] },
			{ L["Browse guides"], BrowseGuides, L["Guides"], L["Opens the guide list in the Journal."] })
	else
		ShowMessage(frame, view.text or self:DataStateText())
	end
end

---------------------------------------------------------------------------
-- Tour help: the first time the window shows a step, a short tour of its
-- parts (once per account; /eui tour eldostar shows it again)
---------------------------------------------------------------------------
local function Arrow()
	local arrow = _G.EldoUI_WaypointArrow
	if M.waypoint and arrow and arrow:IsVisible() then return arrow end
end

E.Tour:Register("eldostar:first", {
	form = "tour", word = "eldostar",
	offer = function(_, force)
		local frame = M.frame
		if not (frame and frame:IsShown() and M.view and M.view.state == "step") then return false end
		local compact = Compact()
		return E.Tour:Run("eldostar:first", {
			{ target = compact and frame.goalLine or frame.step, title = L["Your current step"],
				text = compact and L["The step's next open goal. The arrows beside it move between steps."]
					or L["The step and its goals. A goal the game reports ticks by itself; click the others once they are done."] },
			{ target = Arrow, title = L["The waypoint arrow"],
				text = L["It points to the step's next goal, with the distance."] },
			{ target = frame.footer, title = L["Next, Skip and Undo"],
				text = L["Next moves on, Skip skips a step and Undo takes back the last move, skip or check-off."] },
			{ target = frame.viewButton, title = compact and L["Standard view"] or L["Compact view"],
				text = compact and L["Shows the whole step: its tip, every goal and the buttons."]
					or L["Shows the step and its next goal on two lines."] },
			{ target = frame.titleButton, title = L["Guides"],
				text = L["Opens the guide list in the Journal, where you start another guide."] },
		}, { force = force, title = L["Eldostar"] })
	end,
	replay = function(def)
		if not (M.frame and M.frame:IsShown() and M.view and M.view.state == "step") then
			E:Print(L["The Eldostar tour shows while the guide window has a step open."])
			return
		end
		def.offer(def, true)
	end,
})

-- From UpdateWindow while a step shows: the tour waits a moment, so the
-- window has settled.
function M:OfferTour()
	if self.tourWaiting or E.Tour:Seen("eldostar:first") then return end
	self.tourWaiting = true
	C_Timer.After(1, function()
		M.tourWaiting = nil
		E.Tour:Offer("eldostar:first")
	end)
end
