-- EldoUI My Adventure: the journal tracker under the quest tracker: goals, reminders, the next step, hand-ins, the dock.
--
-- Text lines in the Quest Tracker's look (its font size and header style
-- while that module skins the tracker, the theme font otherwise):
--   GOALS        your active goals ("12/20" right of "20 Linen Cloth");
--                a to-do has a box, and a click ticks it
--   REMINDERS    reminders waiting for their place or time, with the
--                trigger under each ("When you reach Goldshire · every time")
--   NEXT         the top card of Next trips (a ready hand-in, a trip and
--                its prep, the next attunement step)
-- Lines past the height fold into "+3 more". Left-click: a to-do ticks,
-- any other line opens it in My Adventure; right-click opens Goals, Notes
-- or Next trips. Every line has a tooltip with its full text. Nothing in
-- the game is changed: ticking a to-do changes the journal only.
--
-- Where it sits (plan 2.5, design.md 5.2):
--   * Docked (default, "Keep it in the quest column", the mover not
--     dragged): in the bottom band of the Quest Tracker's column. The Quest
--     Tracker leaves that band free (ObjectiveTracker:ReserveBottom("journal",
--     height + 8), out of combat), so Blizzard's list ends above it.
--   * With Questie's tracker on the column: under Questie's live bottom
--     edge, clipped to the column's bottom; with less than 60 px left only
--     the first three lines show. Questie sizes itself, so nothing is
--     reserved.
--   * Dragged away, or the Quest Tracker module or its Move and scale
--     switch off: at its own layout point (EldoUI_JournalTracker), and the
--     band is given back. "Reset position" docks it again.
-- Hidden while it has nothing to list; move mode shows its box.
--
-- API (E.Adventure.Tracker):
--   T:Refresh()          redraw now (normally one coalesced redraw)
--   T:Place()            dock or undock now
--   T:Toggle([on])       the "Show or hide the journal tracker" key (per character)
--   T:Hidden()           true while the player hid it
--   T:Lines()            the lines on screen: { kind, text, right, sub, id }
--   T:Mode()             "band", "questie", "own" or nil (not built)
--   T:Frame()            the frame (tests, tours)
local _, E = ...
local L = E.L
local A = E.Adventure
local J = E.Journal

local Plain = A.Plain

local T = {}
A.Tracker = T

local NAME = "EldoUI_JournalTracker"
local ELEMENT = "objective-tracker"
T.WIDTH = 260
T.GAP = 8                 -- between Blizzard's list (or Questie) and the journal lines
T.TIGHT = 60              -- under Questie: less room than this shows three lines
T.TIGHT_LINES = 3
T.INDENT = 18
T.DEFAULT_POINT = { "TOPRIGHT", "UIParent", "TOPRIGHT", -75, -643 }

local frame, mover
local rows = {}           -- pooled line buttons
local lines = {}          -- what shows now
local mode
local refreshQueued = false

local function Settings()
	return A.db or A.defaults
end

local function Rec()
	return J.Char and J:Char()
end

local function Quests()
	return E.GetModule and E:GetModule("ObjectiveTracker")
end

local function Plainify(text)
	local G = A.Goals
	if G and G.Plainify then return G.Plainify(text) end
	return type(text) == "string" and text or ""
end

-- The first line of a note, without links and colors.
local function FirstLine(text)
	text = Plainify(text)
	return (text:match("^[^\n]*") or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

---------------------------------------------------------------------------
-- Look: the Quest Tracker's while it skins the tracker, else the theme's
---------------------------------------------------------------------------
local function Look()
	local quests = Quests()
	local look = { size = 12, header = 13, accent = true, line = true }
	if quests and quests.active and type(quests.db) == "table" and E:BlizzardAllowed(ELEMENT, "skin") then
		local db = quests.db
		local size = tonumber(db.fontSize) or 0
		if size > 0 then look.size = size end
		local header = tonumber(db.headerSize) or 0
		look.header = header > 0 and header or look.size + 1
		look.accent = db.accentHeaders ~= false
		look.line = db.headerLine ~= false
	end
	look.small = math.max(look.size - 1, 9)
	return look
end

---------------------------------------------------------------------------
-- What it lists
---------------------------------------------------------------------------
local function GoalLines(out)
	local db = Settings()
	local G = A.Goals
	if not (db.trackerGoals and G) then return end
	local active = G:List()
	if #active == 0 then return end
	out[#out + 1] = { kind = "header", text = L["Goals"], section = "goals" }
	for index, goal in ipairs(active) do
		if index > (tonumber(db.trackerGoalsMax) or 5) then
			out.more = (out.more or 0) + (#active - index + 1)
			out.moreSection = out.moreSection or "goals"
			break
		end
		local have, need, hint, track = G:Progress(goal)
		local label = G:Label(goal)
		local right
		if goal.kind ~= "todo" then
			right = track or (need > 1 and ("%s/%s"):format(BreakUpLargeNumbers(have), BreakUpLargeNumbers(need)) or nil)
		end
		out[#out + 1] = { kind = goal.kind == "todo" and "todo" or "goal", text = label, right = right, hint = hint,
			id = goal.id, section = "goals", describe = G:Describe(goal) }
	end
end

local function ReminderLines(out)
	local db = Settings()
	local N = A.Notes
	if not (db.trackerReminders and N) then return end
	local waiting = N:Waiting()
	if #waiting == 0 then return end
	out[#out + 1] = { kind = "header", text = L["Reminders"], section = "notes" }
	for index, note in ipairs(waiting) do
		if index > (tonumber(db.trackerRemindersMax) or 3) then
			out.more = (out.more or 0) + (#waiting - index + 1)
			out.moreSection = out.moreSection or "notes"
			break
		end
		local text = FirstLine(note.text)
		if text == "" then text = L["Reminder"] end
		out[#out + 1] = { kind = "reminder", text = text, sub = note.trigger and N:TriggerLabel(note.trigger, note.repeats) or nil,
			id = note.id, section = "notes", full = Plainify(note.text) }
	end
end

local function NextLines(out)
	local db = Settings()
	if not (db.trackerNext and type(J.NextTop) == "function") then return end
	local ok, card = pcall(J.NextTop, J)
	if not ok or type(card) ~= "table" or type(card.title) ~= "string" then return end
	out[#out + 1] = { kind = "header", text = L["Next"], section = "next" }
	out[#out + 1] = { kind = "next", text = card.title, sub = card.subtitle or (type(card.reasons) == "table" and card.reasons[1]) or nil,
		id = card.id, section = "next", why = card.reasons }
end

function T:Collect()
	local out = {}
	if not A:Running() then return out end
	GoalLines(out)
	ReminderLines(out)
	NextLines(out)
	return out
end

---------------------------------------------------------------------------
-- Clicks and tooltips
---------------------------------------------------------------------------
local function Open(section, arg)
	if type(A.OpenSection) == "function" then A:OpenSection(section, arg) end
end

local function OnClick(row, button)
	local line = row.line
	if not line or E:IsMoveMode() or E:IsOptionsLinkClick(row, button) then return end
	if button == "RightButton" then
		Open(line.section or "goals")
	elseif line.kind == "todo" then
		local G = A.Goals
		if G then G:Tick(line.id) end
		T:Queue()
	elseif line.kind == "more" then
		Open(line.section or "goals")
	elseif line.kind == "goal" then
		if not J:Open(J:Address("goal", line.id)) then Open("goals", line.id) end
	elseif line.kind == "reminder" then
		if not J:Open(J:Address("note", line.id)) then Open("notes", line.id) end
	elseif line.kind == "next" then
		Open("next", line.id)
	end
end

local CLICK_HINT = {
	todo = "Click: check it off. Right-click: open Goals.",
	goal = "Click: open this goal. Right-click: open Goals.",
	reminder = "Click: open this note. Right-click: open Notes.",
	next = "Click or right-click: open Next trips.",
	more = "Click: open the rest in My Adventure.",
}

local function OnEnter(row)
	local line = row.line
	if not line or E:IsMoveMode() then return end
	GameTooltip:SetOwner(row, "ANCHOR_LEFT")
	local body = E.tokens.text.body
	local secondary = E.tokens.text.secondary
	GameTooltip:AddLine(line.full or line.describe or line.text, body[1], body[2], body[3], true)
	if line.right then GameTooltip:AddLine(line.right, secondary[1], secondary[2], secondary[3]) end
	if line.hint and line.hint ~= "" then GameTooltip:AddLine(line.hint, secondary[1], secondary[2], secondary[3], true) end
	if line.sub then GameTooltip:AddLine(line.sub, secondary[1], secondary[2], secondary[3], true) end
	if type(line.why) == "table" then
		for index = 1, math.min(#line.why, 3) do GameTooltip:AddLine(line.why[index], secondary[1], secondary[2], secondary[3], true) end
	end
	local hint = CLICK_HINT[line.kind]
	if hint then GameTooltip:AddLine(L[hint], secondary[1], secondary[2], secondary[3], true) end
	GameTooltip:Show()
end

---------------------------------------------------------------------------
-- Frame and rows
---------------------------------------------------------------------------
local function NewRow()
	local row = CreateFrame("Button", nil, frame)
	row:SetHeight(16)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	row.box = CreateFrame("Frame", nil, row)
	row.box:SetSize(12, 12)
	row.box:SetPoint("LEFT", 0, 0)
	E:SetTemplate(row.box, true)
	row.box:EnableMouse(false)
	row.text = E:CreateText(row, E.tokens.size.label, "LEFT")
	row.text:SetWordWrap(false)
	row.right = E:CreateText(row, E.tokens.size.small, "RIGHT")
	row.right:SetWordWrap(false)
	row.right:SetPoint("RIGHT", row, "RIGHT", 0, 0)
	row.line = nil
	row.rule = row:CreateTexture(nil, "ARTWORK")
	row.rule:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
	row.rule:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
	E:Hairline(row.rule, "h")
	row:SetScript("OnClick", OnClick)
	row:SetScript("OnEnter", OnEnter)
	row:SetScript("OnLeave", GameTooltip_Hide)
	-- Ctrl-click opens the tracker row's own setting.
	E:BindOptionsLink(row, function(own)
		local kind = own.line and own.line.kind
		local key = (kind == "todo" or kind == "goal") and "trackerGoals" or kind == "reminder" and "trackerReminders"
			or kind == "next" and "trackerNext" or nil
		return { page = "module:Adventure", key = key }
	end)
	return row
end

local function Row(index)
	local row = rows[index]
	if not row then
		row = NewRow()
		rows[index] = row
	end
	return row
end

local function Paint(row, line, look)
	local accent = E.media.accentText
	local secondary = E.tokens.text.secondary
	local body = E.tokens.text.body
	row.line = line
	row.box:SetShown(line.kind == "todo")
	row.rule:SetShown(line.kind == "header" and look.line)
	row.text:ClearAllPoints()
	row.right:SetText(line.right or "")
	row.right:SetShown(line.right ~= nil)
	E:SetFont(row.right, look.small)
	row.right:SetTextColor(secondary[1], secondary[2], secondary[3])
	local left = 0
	if line.kind == "todo" then left = 16 end
	if line.kind == "sub" then left = T.INDENT end
	row.text:SetPoint("LEFT", row, "LEFT", left, 0)
	if line.right then
		row.text:SetPoint("RIGHT", row.right, "LEFT", -6, 0)
	else
		row.text:SetPoint("RIGHT", row, "RIGHT", 0, 0)
	end
	local text = line.text or ""
	if line.kind == "goal" or line.kind == "reminder" or line.kind == "next" then text = "- " .. text end
	if line.kind == "header" then text = E:CaptionText(text) end
	row.text:SetText(text)
	if line.kind == "header" then
		E:SetFont(row.text, look.header)
		if look.accent then row.text:SetTextColor(accent[1], accent[2], accent[3]) else row.text:SetTextColor(body[1], body[2], body[3]) end
		E:AccentTexture(row.rule, 0.6)
	elseif line.kind == "sub" or line.kind == "more" then
		E:SetFont(row.text, look.small)
		row.text:SetTextColor(secondary[1], secondary[2], secondary[3])
	else
		E:SetFont(row.text, look.size)
		row.text:SetTextColor(body[1], body[2], body[3])
	end
	-- Headers and sub lines take no clicks; their parent line does.
	row:EnableMouse(line.kind ~= "header" and line.kind ~= "sub")
	row:Show()
end

local function Height(line, look)
	if line.kind == "header" then return look.header + 8 end
	if line.kind == "sub" or line.kind == "more" then return look.small + 4 end
	return look.size + 5
end

local function CreateFrames()
	if frame then return end
	frame = CreateFrame("Frame", NAME, UIParent)
	frame:SetSize(T.WIDTH, Settings().trackerHeight or 140)
	frame:SetFrameStrata("LOW")
	frame:EnableMouse(false)
	frame:Hide()
	local previous = E.currentModule
	E.currentModule = A
	mover = E:CreateMover(frame, NAME, L["Journal Tracker"], T.DEFAULT_POINT, {
		group = "Other", enabledPath = { "enabled" },
		onMoved = function() if T.placing == nil then T:Queue() end end,
	})
	E.currentModule = previous
	T.mover = mover
end
T.CreateFrames = CreateFrames

function T:Frame()
	return frame
end

function T:Mode()
	return mode
end

function T:Lines()
	return lines
end

function T:Hidden()
	local rec = Rec()
	return rec and type(rec.ui) == "table" and rec.ui.trackerHidden and true or false
end

function T:Toggle(on)
	local rec = Rec()
	if not (rec and type(rec.ui) == "table") then return false end
	if on == nil then on = rec.ui.trackerHidden and true or false end
	rec.ui.trackerHidden = not on or nil
	self:Refresh()
	return on
end

---------------------------------------------------------------------------
-- The dock
---------------------------------------------------------------------------
local function UIUnits(region, edge)
	local value = region and region[edge] and Plain(region[edge](region))
	if type(value) ~= "number" then return nil end
	local scale = Plain(region:GetEffectiveScale()) or 1
	local parent = Plain(UIParent:GetEffectiveScale()) or 1
	return value * scale / parent
end

local function Dragged()
	local positions = E.db and E.db.movers
	return type(positions) == "table" and positions[NAME] ~= nil
end

-- Where the frame goes and how tall it may be: mode, cap, tight.
local function Dock()
	local db = Settings()
	local quests = Quests()
	local holder = db.trackerDock and not Dragged() and quests and type(quests.ColumnHolder) == "function" and quests:ColumnHolder()
	if not holder then return "own", nil, db.trackerHeight, false end
	local questie = type(quests.QuestieInColumn) == "function" and quests:QuestieInColumn()
	if questie and questie:IsShown() then
		local bottom, floor = UIUnits(questie, "GetBottom"), UIUnits(holder, "GetBottom")
		if bottom and floor then
			local room = math.max(math.floor(bottom - T.GAP - floor), 0)
			return "questie", holder, math.min(db.trackerHeight, room), room < T.TIGHT, room
		end
	end
	return "band", holder, db.trackerHeight, false
end

function T:Place(shown)
	if not frame then return end
	if shown == nil then shown = frame:IsShown() end
	local quests = Quests()
	local how, holder, _, _, room = Dock()
	mode = how
	T.placing = true
	frame:ClearAllPoints()
	if how == "questie" then
		frame:SetPoint("TOPRIGHT", holder, "BOTTOMRIGHT", 0, room)
	elseif how == "band" then
		frame:SetPoint("TOPRIGHT", holder, "BOTTOMRIGHT", 0, Settings().trackerHeight)
	else
		frame:SetPoint("TOPRIGHT", mover, "TOPRIGHT", 0, 0)
	end
	T.placing = nil
	if quests and type(quests.ReserveBottom) == "function" then
		local band = how == "band" and shown and (Settings().trackerHeight + T.GAP) or nil
		quests:ReserveBottom("journal", band)
	end
	self:Follow(how)
end

-- The Quest Tracker's fade rules (alpha only) while docked in its column.
function T:Follow(how)
	local quests = Quests()
	local block = quests and quests.active and type(quests.db) == "table" and quests.db.visibility
	if how ~= "own" and type(block) == "table" and E:BlizzardAllowed(ELEMENT, "improve") then
		if T.following ~= block then E:AttachVisibility(frame, block, { restoreShown = false }) end
		T.following = block
	elseif T.following then
		E:DetachVisibility(frame)
		frame:SetAlpha(1)
		T.following = nil
	end
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------
-- Lines in order, the sub lines after their parent.
local function Flatten(list)
	local out = {}
	for _, line in ipairs(list) do
		out[#out + 1] = line
		if line.sub then out[#out + 1] = { kind = "sub", text = line.sub, parent = line, section = line.section } end
	end
	return out
end

function T:Refresh()
	refreshQueued = false
	if not frame then return end
	local look = Look()
	local list = self:Collect()
	local flat = Flatten(list)
	local how, _, cap, tight = Dock()
	local show = #flat > 0 and A:Running() and not self:Hidden()
	lines = {}
	if not show then
		for _, row in ipairs(rows) do row:Hide() row.line = nil end
		-- The move-mode box keeps the tracker's full size.
		frame:SetSize(T.WIDTH, Settings().trackerHeight or 140)
		frame:Hide()
		self:Place(false)
		return
	end
	cap = math.max(tonumber(cap) or 140, 0)
	local more = { kind = "more", section = list.moreSection }
	local moreHeight = Height(more, look)
	local used, count, shownItems = 0, 0, 0
	local totalItems = 0
	for _, line in ipairs(flat) do
		if line.kind ~= "header" and line.kind ~= "sub" then totalItems = totalItems + 1 end
	end
	local extra = list.more or 0
	for index, line in ipairs(flat) do
		local height = Height(line, look)
		local left = #flat - index
		local limitHit = (tight and count >= T.TIGHT_LINES)
			or (used + height + ((left > 0 or extra > 0) and moreHeight or 0) > cap and index > 1)
		-- A header never stands alone at the bottom.
		if not limitHit and line.kind == "header" and flat[index + 1] and used + height + Height(flat[index + 1], look) > cap then
			limitHit = true
		end
		if limitHit then
			more.section = more.section or line.section
			break
		end
		count = count + 1
		local row = Row(count)
		row:SetHeight(height)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -used)
		row:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -used)
		Paint(row, line, look)
		lines[#lines + 1] = line
		used = used + height
		if line.kind ~= "header" and line.kind ~= "sub" then shownItems = shownItems + 1 end
	end
	local hidden = totalItems - shownItems + extra
	if hidden > 0 then
		more.text = (L["+%d more"]):format(hidden)
		count = count + 1
		local row = Row(count)
		row:SetHeight(moreHeight)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -used)
		row:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -used)
		Paint(row, more, look)
		lines[#lines + 1] = more
		used = used + moreHeight
	end
	for index = count + 1, #rows do
		rows[index]:Hide()
		rows[index].line = nil
	end
	frame:SetSize(T.WIDTH, math.max(math.ceil(used), 1))
	frame:Show()
	self:Place(true)
	mode = how
end

-- One redraw a moment later (bags and quest log fire in bursts).
function T:Queue()
	if refreshQueued then return end
	refreshQueued = true
	C_Timer.After(0.25, function() T:Refresh() end)
end

---------------------------------------------------------------------------
-- Options rows for the "Tracker and buttons" tab (Options.lua places them;
-- every row has a desc).
---------------------------------------------------------------------------
A.TrackerOptions = {
	{ type = "toggle", key = "trackerGoals", label = "Goals in the tracker", desc = "Your active goals under the quest tracker. Click a to-do to check it." },
	{ type = "range", key = "trackerGoalsMax", label = "Goals shown", desc = "How many goals the tracker lists.", min = 1, max = 10, step = 1 },
	{ type = "toggle", key = "trackerReminders", label = "Reminders in the tracker", desc = "Reminders that are waiting for their place or time." },
	{ type = "range", key = "trackerRemindersMax", label = "Reminders shown", desc = "How many waiting reminders the tracker lists.", min = 1, max = 10, step = 1 },
	{ type = "toggle", key = "trackerNext", label = "Next step in the tracker", desc = "One line with the next thing that matters: a ready hand-in, trip prep or the next attunement step." },
	{ type = "range", key = "trackerHeight", label = "Tracker height", desc = "Lines past this height fold into +n more.", min = 80, max = 300, step = 10 },
	{ type = "toggle", key = "trackerDock", label = "Keep it in the quest column", desc = "The quest tracker leaves room at its bottom for the journal tracker. With Questie, the journal tracker sits right under Questie's list." },
	{ type = "description", label = "Turn on Blizzard UI > Objective / quest tracker > Move and scale to keep the quest list clear of the journal tracker.",
		hidden = function()
			local quests = Quests()
			return not (quests and quests.active) or E:BlizzardAllowed(ELEMENT, "move")
		end },
}

---------------------------------------------------------------------------
-- Part
---------------------------------------------------------------------------
local events = CreateFrame("Frame")
T.events = events
events:SetScript("OnEvent", function() T:Queue() end)
T.EVENTS = { "BAG_UPDATE_DELAYED", "PLAYER_LEVEL_UP", "PLAYER_XP_UPDATE", "PLAYER_MONEY", "QUEST_LOG_UPDATE",
	"ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD", "UPDATE_FACTION", "SKILL_LINES_CHANGED" }

local hooked, questieHooked = false, false

-- Questie's tracker grows and shrinks with your quests: the dock follows
-- its size (hooks on Questie's own frame, an addon frame).
local function HookQuestie()
	local quests = Quests()
	local base = quests and type(quests.QuestieInColumn) == "function" and quests:QuestieInColumn()
	if questieHooked or not base then return end
	questieHooked = true
	local function Follow() if A.started then T:Queue() end end
	base:HookScript("OnSizeChanged", Follow)
	base:HookScript("OnShow", Follow)
	base:HookScript("OnHide", Follow)
end
T.HookQuestie = HookQuestie

local function HookQuests()
	if hooked then return end
	local quests = Quests()
	if not quests then return end
	hooked = true
	-- The column changes when the Quest Tracker re-applies its switches,
	-- puts Questie on the mover, or its mover moves.
	hooksecurefunc(quests, "Refresh", function()
		HookQuestie()
		if A.started then T:Queue() end
	end)
	hooksecurefunc(quests, "ApplyQuestie", function()
		HookQuestie()
		if A.started then T:Queue() end
	end)
	E:RegisterMoverCallback("EldoUI_Quests", function() if A.started then T:Queue() end end)
end

A:AddPart("tracker", {
	order = 70,
	start = function()
		CreateFrames()
		mover:Show()
		HookQuests()
		HookQuestie()
		for _, event in ipairs(T.EVENTS) do events:RegisterEvent(event) end
		if J.RegisterCallback then
			J.RegisterCallback(T, "Redraw", function() T:Queue() end)
		end
		T:Queue()
	end,
	stop = function()
		events:UnregisterAllEvents()
		if J.UnregisterCallback then J.UnregisterCallback(T, "Redraw") end
		if frame then
			frame:Hide()
			if T.following then
				E:DetachVisibility(frame)
				T.following = nil
			end
		end
		if mover then mover:Hide() end
		local quests = Quests()
		if quests and type(quests.ReserveBottom) == "function" then quests:ReserveBottom("journal", nil) end
		mode = nil
	end,
})
