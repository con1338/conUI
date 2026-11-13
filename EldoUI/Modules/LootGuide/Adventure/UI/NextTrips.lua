-- EldoUI My Adventure: the Next trips section.
--
--   +----------------------------------------------------------------+
--   | Next trips                                 [ Put away (2) ]    |
--   | 14 ideas for level 24, best first. ...                         |
--   |----------------------------------------------------------------|
--   | [All 14][Dungeons 3][Quests 6][Attunements 1][Zones 4]         |
--   | [Your group][Solo][2-3][Full group]   [Any time][30m][1h][2h]  |
--   | +------------------------------------------------------------+ |
--   | | [ic] DUNGEON · 22-30                                     78 | |
--   | |      Shadowfang Keep                                       | |
--   | |      22-30, 5 players                                      | |
--   | |      Fits your level (24; the dungeon is 22-30).           | |
--   | |      3 quests to pick up first: The Book of Ur (...).      | |
--   | |      Classic values; Forever may differ.                   | |
--   | |      [Plan the trip][Open][Entrance][Find a group][Not now]| |
--   | +------------------------------------------------------------+ |
--
-- The ranked list of the where-next engine (Next.lua): every card says why
-- it is there (up to three reasons; the tooltip has all of them and "Why
-- not higher?"), where its facts come from, and what you can do about it.
-- Every action is navigation and runs on a click only: a map pin, a page,
-- the objective tracker for quests already in your log, the group finder
-- window, the chat box filled but never sent, a goal, or "Not now".
--
-- Filters (kept per character in the journal's ui.next): the kind (All,
-- Dungeons, Quests, Attunements, Zones and Other, each shown only while it
-- has cards), the group (your group now, Solo, 2-3, Full group and Raid
-- while raids are on) and the time you have. "Put away" lists the cards
-- you sent off with "Not now", each with Bring back.
--
-- Routes (A:OpenSection("next", arg)):
--   nil                 the list as you left it
--   "dungeons", ...     a kind filter (all, dungeons, quests, attune, zones, other)
--   { kind = key }      the same
--   { card = id }       that card, its trip plan open, scrolled to
--   { first = key }     from a dim medal of the Keepsakes Firsts strip: a lead
--                       line for that first and the filter that leads to it
--   { notnow = true }   the cards you put away
--
-- Shared with Today (UI/Today.lua): A.NextUI
--   NX.State()                    the filters (ui.next)
--   NX.Opts()                     J:Next options from the filters
--   NX.Card(parent)               the suggestion card; card:Set(data, opts) -> height
--                                 opts = { width, plan, owner, redraw, onToggle, expanded }
--   NX.Run(data, action, owner, redraw)   one card action, with its toast
--   NX.Icon(card), NX.KindName(kind), NX.Note(flow, title, text, buttons, icon)
--   NX.Row(flow, item)            a compact two-line row (Also good, Waiting, Lately)
--   NX.Caption(flow, label, note) a section caption with its rule
local _, E = ...
local L = E.L
local Key = E.Key
local A = E.Adventure
local J = E.Journal
local LG = E.LootGuide
local K = E.AdventureKit
local T = E.tokens

local KEY = "next"
local INSET = 12
local ART = 36
local TEXT_X = INSET + ART + 10
local LINE = 20
local CONTROLS_Y = -(K.HEADER_HEIGHT + 8)

local function Kit() return LG.Kit end
local function PageKit() return LG.PageKit end

local NX = A.NextUI or {}
A.NextUI = NX

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
-- Kinds and filters
---------------------------------------------------------------------------
local ICONS = J.ICON or {}
local KIND_ICON = {
	dungeon = ICONS.dungeon, attune = ICONS.attune, turnin = "Interface/GossipFrame/ActiveQuestIcon",
	logzone = ICONS.scroll, zone = ICONS.zone, chain = "Interface/GossipFrame/AvailableQuestIcon",
	goal = ICONS.goal, rare = ICONS.rare, rep = ICONS.rep, train = ICONS.spell, event = ICONS.summary,
}
local KIND_NAME = {
	dungeon = Key("Dungeon"), attune = Key("Attunement"), turnin = Key("Hand in"), logzone = Key("In your log"),
	zone = Key("Zone"), chain = Key("Quest chain"), goal = Key("Goal"), rare = Key("Rare"), rep = Key("Reputation"),
	train = Key("Trainer"), event = Key("World event"),
}

-- kind filter -> the engine kinds it shows (other: everything not listed)
local FILTERS = {
	{ "all", Key("All"), Key("Every suggestion, best first.") },
	{ "dungeons", Key("Dungeons"), Key("Dungeons that fit your level, with their quests to take along.") },
	{ "quests", Key("Quests"), Key("Quests to hand in, quests in your log by zone, and quest chains to go on with.") },
	{ "attune", Key("Attunements"), Key("The next open step of each attunement and key.") },
	{ "zones", Key("Zones"), Key("Zones with quests for your level that you have not done yet.") },
	{ "other", Key("Other"), Key("Suggestions from other parts of EldoUI and from plugins.") },
}
local FILTER_KINDS = {
	dungeons = { dungeon = true }, quests = { turnin = true, logzone = true, chain = true },
	attune = { attune = true }, zones = { zone = true },
}
local FILTER_NAME = {}
for _, entry in ipairs(FILTERS) do FILTER_NAME[entry[1]] = entry[2] end

local GROUPS = {
	{ "auto", Key("Your group"), Key("Rank for the group you are in right now (on your own: solo).") },
	{ "solo", Key("Solo"), Key("Rank as if you play on your own.") },
	{ "small", Key("2-3"), Key("Rank for two or three players.") },
	{ "full", Key("Full group"), Key("Rank for a full group of five.") },
	{ "raid", Key("Raid"), Key("Rank for a raid group.") },
}
local TIMES = {
	{ "any", Key("Any time"), Key("No time limit.") },
	{ "30", Key("30m"), Key("You have about half an hour: trips that fit it rank higher.") },
	{ "60", Key("1h"), Key("You have about an hour: trips that fit it rank higher.") },
	{ "120", Key("2h"), Key("You have about two hours: trips that fit it rank higher.") },
}

-- A dungeon or raid card shows that instance's own art.
function NX.Icon(card)
	if not card then return ICONS.summary end
	if card.icon then return card.icon end
	if card.kind == "dungeon" and card.key and LG.InstanceArt then
		local art = Safe(LG.InstanceArt, LG, card.key)
		if art then return art end
	end
	return KIND_ICON[card.kind] or ICONS.summary
end

function NX.KindName(kind)
	return KIND_NAME[kind] and L[KIND_NAME[kind]] or L["Idea"]
end

local function FilterOf(kind)
	for key, kinds in pairs(FILTER_KINDS) do
		if kinds[kind] then return key end
	end
	return "other"
end
NX.FilterOf = FilterOf

local session = {}

function NX.State()
	local rec = J.Char and J:Char()
	local ui = rec and rec.ui
	local state
	if type(ui) == "table" then
		if type(ui.next) ~= "table" then ui.next = {} end
		state = ui.next
	else
		state = session
	end
	if not FILTER_NAME[state.kind or ""] then state.kind = "all" end
	return state
end

function NX.Opts(extra)
	local state = NX.State()
	local opts = {}
	if state.group and state.group ~= "auto" then opts.group = state.group end
	if state.group == "raid" and not (A.db and A.db.nextRaids) then opts.group = nil end
	if tonumber(state.minutes) then opts.minutes = tonumber(state.minutes) end
	for key, value in pairs(extra or {}) do opts[key] = value end
	return opts
end

---------------------------------------------------------------------------
-- Flow parts shared with Today
---------------------------------------------------------------------------
-- A caption: upper-case accent label, a note, a rule to the right edge.
local function CaptionBlock(child)
	local block = CreateFrame("Frame", nil, child)
	block.label = K.Text(block, K.size.caption, "LEFT", "accent")
	block.label:SetPoint("LEFT", 0, 0)
	block.label:SetWordWrap(false)
	block.note = K.Text(block, K.size.small, "LEFT", "secondary")
	block.note:SetPoint("LEFT", block.label, "RIGHT", 8, 0)
	block.note:SetWordWrap(false)
	block.rule = K.Rule(block)
	block.rule:SetPoint("LEFT", block.note, "RIGHT", 8, 0)
	block.rule:SetPoint("RIGHT", block, "RIGHT", 0, 0)
	return block
end

function NX.Caption(flow, label, note)
	flow:Space(4)
	local block = flow:Take("ak-caption", CaptionBlock)
	block.label:SetText(E:CaptionText(label or ""))
	K.Paint(block.label, "accent")
	block.note:SetText(note or "")
	flow:Place(block, 18, 0, 6)
	return block
end

-- A note card: icon, title, text, buttons (empty states inside a page).
local function NoteBlock(child)
	local block = CreateFrame("Frame", nil, child)
	block.box = K.Card(block)
	block.box:SetAllPoints()
	block.box:SetFrameLevel(math.max(block:GetFrameLevel() - 1, 0))
	block.art = K.Art(block, 32)
	block.art:SetPoint("TOPLEFT", INSET, -INSET)
	block.title = K.Text(block, K.size.section, "LEFT", "head", true)
	block.title:SetPoint("TOPLEFT", INSET + 32 + 10, -INSET)
	block.title:SetPoint("TOPRIGHT", -INSET, -INSET)
	block.title:SetWordWrap(false)
	block.text = K.Text(block, K.size.label, "LEFT", "secondary")
	block.text:SetPoint("TOPLEFT", block.title, "BOTTOMLEFT", 0, -6)
	block.text:SetWordWrap(true)
	block.text:SetSpacing(2)
	block.buttons = {}
	return block
end

function NX.Note(flow, title, text, buttons, icon)
	local block = flow:Take("ak-note", NoteBlock)
	local width = flow:Width()
	K.SetIcon(block.art.icon, icon or A.HUB_ICON)
	block.title:SetText(title or "")
	block.text:SetWidth(math.max(width - (INSET + 32 + 10) - INSET, 40))
	block.text:SetText(text or "")
	local height = INSET + 18 + 6 + math.ceil(block.text:GetStringHeight() or 14)
	local x = INSET + 32 + 10
	local count = buttons and #buttons or 0
	for index = 1, math.max(#block.buttons, count) do
		local data = buttons and buttons[index]
		local button = block.buttons[index]
		if data and not button then
			button = Kit().Button(block, "", 80, T.height.button)
			block.buttons[index] = button
		end
		if button then
			button:SetShown(data ~= nil)
			if data then
				button:SetText(data[1])
				E.UIKit.FitButton(button, 60)
				button:SetScript("OnClick", data[2])
				Kit().Tooltip(button, data[1], data[3])
				button:ClearAllPoints()
				button:SetPoint("TOPLEFT", block, "TOPLEFT", x, -(height + 10))
				x = x + button:GetWidth() + 8
			end
		end
	end
	if count > 0 then height = height + 10 + T.height.button end
	height = math.max(height + INSET, INSET * 2 + 32)
	flow:Place(block, height, 0, 10)
	return block
end

-- A compact row: icon, title, a sub line, an optional bar, a right text
-- and a quiet link on the right. item = { icon, title, sub, right, onClick,
-- tip, tipTitle, link = { label, onClick, tip }, progress = { have, need },
-- titleRole }
local function RowBlock(child)
	local row = CreateFrame("Button", nil, child)
	row.hover = row:CreateTexture(nil, "HIGHLIGHT")
	row.hover:SetAllPoints()
	row.hover:SetColorTexture(1, 1, 1, T.hover.row)
	row.art = K.Art(row, 22)
	row.art:SetPoint("TOPLEFT", 4, -5)
	row.title = K.Text(row, K.size.label, "LEFT", "body")
	row.title:SetPoint("TOPLEFT", 36, -5)
	row.title:SetWordWrap(false)
	row.sub = K.Text(row, K.size.small, "LEFT", "secondary")
	row.sub:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -2)
	row.sub:SetWordWrap(false)
	row.right = K.Text(row, K.size.small, "RIGHT", "secondary")
	row.track = K.Track(row, 4)
	row.link = CreateFrame("Button", nil, row)
	row.link:SetHeight(16)
	row.link.text = K.Text(row.link, K.size.small, "RIGHT", "secondary")
	row.link.text:SetPoint("RIGHT")
	row.link:SetScript("OnEnter", function(self) K.Paint(self.text, "accent") end)
	row.link:SetScript("OnLeave", function(self) K.Paint(self.text, "secondary") end)
	E:PadHitRect(row.link, 4)
	row:RegisterForClicks("LeftButtonUp")
	return row
end

function NX.Row(flow, item)
	local row = flow:Take("ak-row", RowBlock)
	local height = item.progress and 40 or 34
	flow:Place(row, height, item.indent, 2)
	K.SetIcon(row.art.icon, item.icon or ICONS.summary)
	row.art:SetShown(item.icon ~= false)
	row.title:SetText(item.title or "")
	K.Paint(row.title, item.titleRole or "body")
	row.sub:SetText(item.sub or "")
	local rightEdge = -8
	if item.link then
		row.link.text:SetText(item.link[1])
		row.link:SetWidth(math.ceil(row.link.text:GetStringWidth()) + 2)
		row.link:ClearAllPoints()
		row.link:SetPoint("RIGHT", row, "RIGHT", -8, 0)
		row.link:SetScript("OnClick", item.link[2])
		Kit().Tooltip(row.link, item.link[1], item.link[3])
		row.link:Show()
		rightEdge = -(8 + row.link:GetWidth() + 12)
	else
		row.link:Hide()
	end
	row.right:ClearAllPoints()
	row.right:SetPoint("RIGHT", row, "RIGHT", rightEdge, 0)
	row.right:SetText(item.right or "")
	local rightWidth = item.right and (math.ceil(row.right:GetStringWidth()) + 12) or 0
	row.title:SetPoint("TOPRIGHT", row, "TOPRIGHT", rightEdge - rightWidth, -5)
	row.sub:SetPoint("TOPRIGHT", row.title, "BOTTOMRIGHT", 0, -2)
	if item.progress then
		row.track:ClearAllPoints()
		row.track:SetPoint("TOPLEFT", row.sub, "BOTTOMLEFT", 0, -4)
		row.track:SetPoint("TOPRIGHT", row.sub, "BOTTOMRIGHT", 0, -4)
		row.track:SetProgress(item.progress[1], item.progress[2])
		row.track:Show()
	else
		row.track:Hide()
	end
	row:SetScript("OnClick", item.onClick)
	row.hover:SetShown(item.onClick ~= nil)
	row:EnableMouse(item.onClick ~= nil or item.tip ~= nil)
	Kit().Tooltip(row, item.tip and (item.tipTitle or item.title), item.tip)
	row.item = item
	return row
end

---------------------------------------------------------------------------
-- Actions: one click, one thing, and a short notice of what happened
---------------------------------------------------------------------------
local function Toast(owner, text, opts)
	if not (owner and text) then return end
	opts = opts or {}
	opts.anchor = opts.anchor or owner
	opts.point = opts.point or "BOTTOM"
	opts.y = opts.y or 12
	E.UIKit.Toast(owner, text, opts)
end
NX.Toast = Toast

local ACTION_TIP = {
	map = Key("Pins the place on your map and turns on the arrow."),
	open = Key("Opens its page in the Journal."),
	track = Key("Puts its quests that are already in your log on the objective tracker. Nothing is accepted for you."),
	group = Key("Opens the game's group finder window. Nothing is listed or queued for you."),
	copy = Key("Puts a group line into the chat box. Nothing is sent until you press Enter."),
	goal = Key("Adds it to your goals, so the tracker and the Goals page follow it."),
	notnow = Key("Puts this card away until your next level or for 24 hours."),
}
NX.ACTION_TIP = ACTION_TIP

function NX.Run(card, action, owner, redraw)
	if type(card) ~= "table" or type(action) ~= "table" then return false end
	local key = action.key
	if key == "goal" then
		if type(J.AddGoal) ~= "function" then return false end
		local goal, err = J:AddGoal(action.goal)
		if goal then
			local G = A.Goals
			local label = G and G.Label and G:Label(goal) or card.title
			Toast(owner, (L["New goal: %s."]):format(label), { action = A:SectionShown("goals") and
				{ L["Show"], function() A:OpenSection("goals", goal.id) end } or nil })
		else
			Toast(owner, err or L["That goal could not be set."], { warn = true })
		end
		if redraw then redraw() end
		return goal ~= nil
	end
	if key == "notnow" then
		local ok = J:NextAct(card, "notnow")
		if ok then
			Toast(owner, L["Put away until your next level or for 24 hours."], { action = { L["Undo"], function()
				J:ClearNotNow(card.id)
				if redraw then redraw() end
			end } })
		end
		if redraw then redraw() end
		return ok
	end
	local ok = J:NextAct(card, key)
	if key == "map" then
		Toast(owner, ok and (L["%s is pinned on your map."]):format(action.title or card.title) or L["This place has no point on your map yet."],
			{ warn = not ok })
	elseif key == "track" then
		Toast(owner, ok and L["On your objective tracker."] or L["None of these quests is in your quest log."], { warn = not ok })
	elseif key == "copy" then
		if ok then Toast(owner, L["The line is in the chat box. Press Enter to send it, or Escape to drop it."]) end
	elseif key == "group" then
		if not ok then Toast(owner, L["The group finder could not open here."], { warn = true }) end
	end
	return ok
end

---------------------------------------------------------------------------
-- The suggestion card
---------------------------------------------------------------------------
local PLAN_PARTS = {
	{ "before", Key("Before you go") }, { "onTheWay", Key("On the way") }, { "access", Key("Getting in") },
	{ "inside", Key("Inside") }, { "gettingThere", Key("Getting there") }, { "afterwards", Key("Afterwards") },
}
local PLAN_MAX = 5
local STATUS_TEXT = { available = Key("to pick up"), active = Key("in your log") }

local function CardTip(card)
	return function(tooltip)
		local secondary = T.text.secondary
		if card.subtitle then tooltip:AddLine(card.subtitle, secondary[1], secondary[2], secondary[3], true) end
		if card.score then
			tooltip:AddLine((L["Score %s of 100"]):format(tostring(card.score)), secondary[1], secondary[2], secondary[3])
		end
		if card.why and card.why[1] then
			tooltip:AddLine(" ")
			E.UIKit.TipTitle(tooltip, L["Why"])
			for _, why in ipairs(card.why) do
				local body = T.text.body
				tooltip:AddLine(why.text, body[1], body[2], body[3], true)
			end
		end
		if card.whyNot and card.whyNot[1] then
			tooltip:AddLine(" ")
			E.UIKit.TipTitle(tooltip, L["Why not higher?"])
			for _, why in ipairs(card.whyNot) do tooltip:AddLine(why.text, secondary[1], secondary[2], secondary[3], true) end
		end
		if card.dataLabel then
			local dim = T.text.dim
			tooltip:AddLine(" ")
			tooltip:AddLine(E:Translate(card.dataLabel), dim[1], dim[2], dim[3], true)
		end
	end
end

local function PlanLine(parent)
	local line = CreateFrame("Button", nil, parent)
	line:SetHeight(LINE)
	line.hover = line:CreateTexture(nil, "HIGHLIGHT")
	line.hover:SetAllPoints()
	line.hover:SetColorTexture(1, 1, 1, T.hover.row)
	line.mark = line:CreateTexture(nil, "ARTWORK")
	line.mark:SetSize(12, 12)
	line.mark:SetPoint("LEFT", 0, 0)
	line.text = K.Text(line, K.size.label, "LEFT", "body")
	line.text:SetPoint("LEFT", 18, 0)
	line.text:SetWordWrap(false)
	line.link = CreateFrame("Button", nil, line)
	line.link:SetHeight(16)
	line.link.text = K.Text(line.link, K.size.small, "RIGHT", "secondary")
	line.link.text:SetPoint("RIGHT")
	line.link:SetScript("OnEnter", function(self) K.Paint(self.text, "accent") end)
	line.link:SetScript("OnLeave", function(self) K.Paint(self.text, "secondary") end)
	E:PadHitRect(line.link, 4)
	return line
end

local function PlanCaption(parent)
	local fs = K.Text(parent, K.size.caption, "LEFT", "accent")
	fs:SetWordWrap(false)
	return fs
end

-- What a plan line opens, and its quiet link.
local function LineActions(entry, owner)
	local open, link
	if entry.quest then
		open = function() J:Open(J:Address("quest", entry.quest)) end
	elseif entry.id then
		open = function() J:Open(J:Address("quest", entry.id)) end
	elseif entry.attune and E.Attunements then
		open = function() E.Attunements:Open(entry.attune) end
	elseif entry.instance then
		open = function() LG:Open("journal", entry.instance) end
	elseif entry.item then
		open = function() J:Open(J:Address("item", entry.item)) end
	end
	if type(entry.point) == "table" then
		local title = entry.title or entry.text
		link = { L["Map"], function()
			local ok = LG:SetWaypoint(entry.point, title)
			Toast(owner, ok and (L["%s is pinned on your map."]):format(title) or L["This place has no point on your map yet."], { warn = not ok })
		end, ACTION_TIP.map }
	end
	return open, link
end

local function PlanEntries(plan, part)
	local list = {}
	for _, entry in ipairs(plan[part] or {}) do
		local text = entry.text
		local state
		if part == "before" then
			local bits = {}
			if entry.giver then bits[#bits + 1] = entry.giver end
			if entry.zone then bits[#bits + 1] = entry.zone end
			bits[#bits + 1] = E:Translate(STATUS_TEXT[entry.status])
			text = ("%s  %s"):format(entry.title or "", K.InkHex("secondary") .. table.concat(bits, " · ") .. "|r")
			if entry.note then text = text .. "  " .. K.InkHex("dim") .. entry.note .. "|r" end
			state = entry.status == "active" and "done" or "todo"
		elseif part == "access" then
			state = entry.done and "done" or "todo"
		end
		list[#list + 1] = { entry = entry, text = text, state = state }
	end
	return list
end

local MARK = { done = "Interface/GossipFrame/ActiveQuestIcon", todo = "Interface/GossipFrame/AvailableQuestIcon" }

function NX.Card(parent)
	local card = CreateFrame("Button", nil, parent)
	card.box = K.Card(card, { accent = true })
	card.box:SetAllPoints()
	card.box:SetFrameLevel(math.max(card:GetFrameLevel() - 1, 0))
	card.art = K.Art(card, ART)
	card.art:SetPoint("TOPLEFT", INSET, -INSET)
	-- The caption line (kind and levels) with the score at its right end;
	-- below it the title, the sub line and the reasons use the whole width
	-- right of the icon and wrap instead of being cut.
	card.kind = K.Text(card, K.size.small, "LEFT", "accent")
	card.kind:SetWordWrap(false)
	card.score = K.Text(card, K.size.small, "RIGHT", "secondary")
	card.score:SetWordWrap(false)
	card.title = K.Text(card, K.size.section + 2, "LEFT", "head", true)
	card.title:SetWordWrap(true)
	card.subtitle = K.Text(card, K.size.small, "LEFT", "secondary")
	card.subtitle:SetWordWrap(true)
	card.reasons, card.lines, card.captions, card.buttons = {}, {}, {}, {}
	card.label = K.Text(card, K.size.small, "LEFT", "dim")
	card.label:SetWordWrap(true)
	card:RegisterForClicks("LeftButtonUp")

	local function Reason(index)
		local fs = card.reasons[index]
		if not fs then
			fs = K.Text(card, K.size.label, "LEFT", "body")
			fs:SetWordWrap(true)
			fs:SetSpacing(2)
			card.reasons[index] = fs
		end
		return fs
	end

	local function Line(index)
		local line = card.lines[index]
		if not line then
			line = PlanLine(card)
			card.lines[index] = line
		end
		return line
	end

	local function Caption(index)
		local fs = card.captions[index]
		if not fs then
			fs = PlanCaption(card)
			card.captions[index] = fs
		end
		return fs
	end

	local function Button(index)
		local button = card.buttons[index]
		if not button then
			button = Kit().Button(card, "", 60, T.height.button)
			card.buttons[index] = button
		end
		return button
	end

	-- data: a J:Next card. Returns the height the card needs.
	function card:Set(data, opts)
		opts = opts or {}
		self.data = data
		local width = math.max(opts.width or self:GetWidth() or 600, 300)
		local textWidth = width - TEXT_X - INSET
		K.SetIcon(self.art.icon, NX.Icon(data))
		local kind = E:CaptionText(NX.KindName(data.kind))
		if data.level and data.level.min then
			local range = data.level.min == data.level.max and tostring(data.level.min) or ("%d-%d"):format(data.level.min, data.level.max)
			kind = ("%s  ·  %s"):format(kind, E:CaptionText((L["level %s"]):format(range)))
		end
		self.kind:SetText(kind)
		K.Paint(self.kind, "accent")
		self.score:SetText(data.score and (L["Score %s"]):format(tostring(math.floor(data.score + 0.5))) or "")
		-- Caption line: the score keeps its own room at the right.
		local y = 10
		local scoreWidth = data.score and math.ceil(self.score:GetStringWidth() or 0) or 0
		self.score:ClearAllPoints()
		self.score:SetPoint("TOPRIGHT", self, "TOPRIGHT", -INSET, -y)
		self.score:SetWidth(math.max(scoreWidth, 1))
		self.kind:ClearAllPoints()
		self.kind:SetPoint("TOPLEFT", self, "TOPLEFT", TEXT_X, -y)
		self.kind:SetWidth(math.max(textWidth - (scoreWidth > 0 and (scoreWidth + 8) or 0), 40))
		y = y + math.ceil(math.max(self.kind:GetStringHeight() or 0, self.score:GetStringHeight() or 0, 10)) + 4
		-- Title and sub line wrap over the full text width.
		local function Block(fs, text, gap)
			fs:ClearAllPoints()
			fs:SetPoint("TOPLEFT", self, "TOPLEFT", TEXT_X, -y)
			fs:SetWidth(textWidth)
			fs:SetText(text or "")
			if text and text ~= "" then
				fs:Show()
				y = y + math.ceil(fs:GetStringHeight() or 0) + gap
			else
				fs:Hide()
			end
		end
		Block(self.title, data.title, 4)
		Block(self.subtitle, data.subtitle, 6)
		-- Why: the top reasons.
		local used = 0
		for index, text in ipairs(data.reasons or {}) do
			local fs = Reason(index)
			fs:ClearAllPoints()
			fs:SetPoint("TOPLEFT", self, "TOPLEFT", TEXT_X, -y)
			fs:SetWidth(textWidth)
			fs:SetText(text)
			fs:Show()
			y = y + math.ceil(fs:GetStringHeight() or 14) + 4
			used = index
		end
		for index = used + 1, #self.reasons do self.reasons[index]:Hide() end
		-- The trip plan (dungeon cards, when asked).
		local lineCount, captionCount = 0, 0
		local plan = opts.plan and data.kind == "dungeon" and Safe(J.TripPlan, J, data) or nil
		self.plan = plan
		if plan then
			y = y + 4
			local parts = {}
			for _, part in ipairs(PLAN_PARTS) do parts[#parts + 1] = part end
			if type(plan.checklist) == "table" and plan.checklist[1] then parts[#parts + 1] = { "checklist", L["Packed?"] } end
			for _, part in ipairs(parts) do
				local entries
				if part[1] == "checklist" then
					entries = {}
					for _, item in ipairs(plan.checklist) do
						entries[#entries + 1] = { entry = item, text = item.text, state = item.ok and "done" or "warn" }
					end
				else
					entries = PlanEntries(plan, part[1])
				end
				if entries[1] then
					captionCount = captionCount + 1
					local caption = Caption(captionCount)
					caption:ClearAllPoints()
					caption:SetPoint("TOPLEFT", self, "TOPLEFT", TEXT_X, -(y + 4))
					caption:SetText(E:CaptionText(part[2]))
					K.Paint(caption, "accent")
					caption:Show()
					y = y + 18
					for index, item in ipairs(entries) do
						if index > PLAN_MAX then
							lineCount = lineCount + 1
							local more = Line(lineCount)
							more:ClearAllPoints()
							more:SetPoint("TOPLEFT", self, "TOPLEFT", TEXT_X, -y)
							more:SetPoint("TOPRIGHT", self, "TOPRIGHT", -INSET, -y)
							more.text:SetText(E:Plural(#entries - PLAN_MAX, "and %d more", "and %d more"):format(#entries - PLAN_MAX))
							K.Paint(more.text, "secondary")
							more.mark:Hide()
							more.link:Hide()
							more:SetScript("OnClick", nil)
							more.hover:Hide()
							more:Show()
							y = y + LINE
							break
						end
						lineCount = lineCount + 1
						local line = Line(lineCount)
						line:ClearAllPoints()
						line:SetPoint("TOPLEFT", self, "TOPLEFT", TEXT_X, -y)
						line:SetPoint("TOPRIGHT", self, "TOPRIGHT", -INSET, -y)
						line.text:SetText(item.text or "")
						local role = item.state == "warn" and "warn" or (item.state == "done" and part[1] == "checklist") and "good" or "body"
						K.Paint(line.text, role)
						if item.state == "done" or item.state == "todo" then
							line.mark:SetTexture(MARK[item.state])
							line.mark:SetDesaturated(item.state == "todo" and part[1] == "access")
							line.mark:Show()
						else
							line.mark:Hide()
						end
						local open, link = LineActions(item.entry, opts.owner)
						line:SetScript("OnClick", open)
						line.hover:SetShown(open ~= nil)
						line:EnableMouse(open ~= nil)
						if link then
							line.link.text:SetText(link[1])
							line.link:SetWidth(math.ceil(line.link.text:GetStringWidth()) + 2)
							line.link:ClearAllPoints()
							line.link:SetPoint("RIGHT", line, "RIGHT", 0, 0)
							line.link:SetScript("OnClick", link[2])
							Kit().Tooltip(line.link, link[1], link[3])
							line.link:Show()
							line.text:SetPoint("RIGHT", line.link, "LEFT", -8, 0)
						else
							line.link:Hide()
							line.text:SetPoint("RIGHT", line, "RIGHT", 0, 0)
						end
						line:Show()
						y = y + LINE
					end
				end
			end
		end
		for index = lineCount + 1, #self.lines do self.lines[index]:Hide() end
		for index = captionCount + 1, #self.captions do self.captions[index]:Hide() end
		-- Where the facts come from.
		y = y + 4
		self.label:ClearAllPoints()
		self.label:SetPoint("TOPLEFT", self, "TOPLEFT", TEXT_X, -y)
		self.label:SetWidth(textWidth)
		self.label:SetText(E:Translate(data.dataLabel) or "")
		self.label:SetShown(data.dataLabel ~= nil)
		if data.dataLabel then y = y + math.ceil(self.label:GetStringHeight() or 0) + 4 end
		-- Actions: the plan switch first (dungeon cards), then the card's own.
		local actions = {}
		if opts.onToggle and data.kind == "dungeon" then
			actions[#actions + 1] = { label = opts.expanded and L["Hide the plan"] or L["Plan the trip"], tip =
				L["Before you go, getting in, inside, getting there, and afterward: the whole trip in one list."], run = opts.onToggle }
		end
		for _, action in ipairs(data.actions or {}) do
			actions[#actions + 1] = { label = action.label, tip = ACTION_TIP[action.key], action = action }
		end
		local x = TEXT_X
		y = y + 4
		for index, entry in ipairs(actions) do
			local button = Button(index)
			button:SetText(E:Translate(entry.label) or "")
			E.UIKit.FitButton(button, 56)
			if x + button:GetWidth() > width - INSET and x > TEXT_X then
				x = TEXT_X
				y = y + T.height.button + 6
			end
			button:ClearAllPoints()
			button:SetPoint("TOPLEFT", self, "TOPLEFT", x, -y)
			local run, action = entry.run, entry.action
			button:SetScript("OnClick", function()
				if run then
					run(data)
				else
					NX.Run(data, action, opts.owner, opts.redraw)
				end
			end)
			Kit().Tooltip(button, entry.label, entry.tip)
			button.actionKey = action and action.key or "plan"
			button:Show()
			x = x + button:GetWidth() + 6
		end
		for index = #actions + 1, #self.buttons do self.buttons[index]:Hide() end
		if #actions > 0 then y = y + T.height.button end
		y = y + INSET
		self.box:SetAccent(opts.accent ~= false)
		self:SetScript("OnClick", opts.onClick and function() opts.onClick(data) end or nil)
		Kit().Tooltip(self, data.title, CardTip(data))
		self.height = math.max(y, INSET * 2 + ART)
		return self.height
	end
	return card
end

---------------------------------------------------------------------------
-- Firsts: a dim medal on the Keepsakes page leads here
---------------------------------------------------------------------------
-- key -> filter, lead text (with cards), text when that filter is empty
local FIRSTS = {
	dungeon = { "dungeons", Key("Your first dungeon is waiting. These fit your level:"),
		Key("No dungeon fits your level yet. The first ones open in the low teens; until then the quests below lead you there.") },
	boss = { "dungeons", Key("A first boss kill waits at the end of a dungeon. These fit your level:"),
		Key("No dungeon fits your level yet. The first ones open in the low teens.") },
	raid = { "dungeons", Key("Raids open near the level cap. Until then, these dungeons fit your level:"),
		Key("Raids open near the level cap. Turn on raids in the settings to see them here.") },
	attune = { "attune", Key("Your first attunement step is open:"),
		Key("No attunement step is open for your level yet. The Attunements page shows each one and the level it starts at.") },
	groupquest = { "quests", Key("Quests are quicker with company. These fit your level:"),
		Key("No quest to suggest right now. Pick up quests from the people with a yellow mark over their heads.") },
	flight = { "zones", Key("Every flight master you speak to adds a flight path. These zones fit your level:"),
		Key("Speak to the flight master in the next town you reach to learn its flight path.") },
	epic = { "dungeons", Key("Epic finds come from bosses. These dungeons fit your level:"),
		Key("Epic finds come from bosses deep in dungeons, later in your journey.") },
	rare = { "zones", Key("Rare creatures roam the zones for your level. These fit you:"),
		Key("Rare creatures roam every zone. The Open World tab lists them by zone.") },
	honored = { "zones", Key("Reputation grows with the quests of a faction's lands. These zones fit your level:"),
		Key("Reputation grows with the quests of a faction's lands. The Reputation page in the Atlas lists every faction.") },
	mount = { "all", Key("Your first mount comes from your race's mount vendor once you have the level and the gold it asks for. Meanwhile:"),
		Key("Your first mount comes from your race's mount vendor once you have the level and the gold it asks for.") },
	death = { "all", Key("Everyone falls sometime. There is no need to chase this one; here is what fits you instead:"),
		Key("Everyone falls sometime. There is no need to chase this one.") },
}
NX.FIRSTS = FIRSTS

---------------------------------------------------------------------------
-- The page
---------------------------------------------------------------------------
local function Count(cards)
	local counts = { all = #cards }
	for _, card in ipairs(cards) do
		local filter = FilterOf(card.kind)
		counts[filter] = (counts[filter] or 0) + 1
	end
	return counts
end

local function Filtered(cards, kind)
	if kind == "all" then return cards end
	local out = {}
	for _, card in ipairs(cards) do
		if FilterOf(card.kind) == kind then out[#out + 1] = card end
	end
	return out
end

-- The cards you put away (still away now).
local function Away()
	local result = J:Next(NX.Opts({ hidden = true }))
	local out = {}
	for _, card in ipairs(result.cards or {}) do
		if J:IsNotNow(card.id) then out[#out + 1] = card end
	end
	return out
end
NX.Away = Away

-- Lay the shown buttons of a switch side by side.
local function LayoutSwitch(switch)
	local x = 0
	for _, button in ipairs(switch.buttons) do
		button:ClearAllPoints()
		if button:IsShown() then
			button:SetPoint("LEFT", switch, "LEFT", x, 0)
			x = x + button:GetWidth() + 2
		end
	end
	switch:SetWidth(math.max(x - 2, 1))
end

local function MaxLevel()
	local level = A.Plain(GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion())
	return type(level) == "number" and level or 60
end

local function Level()
	local level = A.Plain(UnitLevel("player"))
	return type(level) == "number" and level or 1
end

-- The empty list, worded for where you are.
local function EmptyNote(frame, result, kind)
	local flow = frame.flow
	if kind ~= "all" and (result.cards[1] ~= nil) then
		NX.Note(flow, L["Nothing of this kind right now"], (L["No %s suggestion fits you at the moment. The other filters still have ideas."]):format(
			(E:Translate(FILTER_NAME[kind]) or ""):lower()), { { L["Show all"], function() frame:SetKind("all") end } }, A.HUB_ICON)
		return
	end
	if result.data == "none" and not LG:HasData() then
		NX.Note(flow, L["No suggestions yet"],
			L["The guide needs the loot data (the EldoUI_LootData addon) or the game's dungeon finder list to suggest trips. Quests in your log still show here."],
			nil, A.HUB_ICON)
		return
	end
	local level = Level()
	if level >= MaxLevel() then
		local buttons = {}
		if not (A.db and A.db.nextRaids) then
			buttons[#buttons + 1] = { L["Include raids"], function()
				A.db.nextRaids = true
				if A.Next then A.Next:Invalidate() end
				frame:Draw()
			end, L["Raids join the suggestions (the Include raids setting of My Adventure)."] }
		end
		if E.Attunements and E.Attunements.Running and E.Attunements:Running() then
			buttons[#buttons + 1] = { L["Attunements"], function() E.Attunements:Open() end, L["Every attunement and key, step by step."] }
		end
		NX.Note(flow, L["Every level is behind you"],
			L["What is left are raids, attunements, and reputation. Nothing else fits right now; put-away cards come back after 24 hours."],
			buttons, A.HUB_ICON)
		return
	end
	if level <= 1 then
		NX.Note(flow, L["The first page is still blank"],
			L["Look for the people with a yellow mark over their heads near where you started: they have your first quests. Ideas show here as soon as there is one."],
			nil, A.HUB_ICON)
		return
	end
	NX.Note(flow, L["Nothing to suggest right now"],
		L["No dungeon, quest, or attunement step fits your level and group at the moment. Try another group size, or bring back a card you put away."],
		nil, A.HUB_ICON)
end

local function Build(parent)
	local frame = CreateFrame("Frame", nil, parent)
	frame:SetAllPoints()
	frame.expanded = {}

	frame.header = K.Header(frame)
	frame.header:SetPoint("TOPLEFT")
	frame.header:SetPoint("TOPRIGHT")

	local state = NX.State()
	frame.kinds = K.Switch(frame, FILTERS, state.kind, function(kind) frame:SetKind(kind) end)
	frame.kinds:SetPoint("TOPLEFT", 0, CONTROLS_Y)
	frame.groups = K.Switch(frame, GROUPS, state.group or "auto", function(group)
		NX.State().group = group ~= "auto" and group or nil
		frame:Draw()
	end)
	frame.groups:SetPoint("TOPLEFT", 0, CONTROLS_Y - 24)
	frame.times = K.Switch(frame, TIMES, state.minutes and tostring(state.minutes) or "any", function(value)
		NX.State().minutes = tonumber(value)
		frame:Draw()
	end)
	frame.times:SetPoint("LEFT", frame.groups, "RIGHT", 16, 0)

	frame.flow = PageKit().Flow(frame)
	frame.flow:SetPoint("TOPLEFT", 0, CONTROLS_Y - 50)
	frame.flow:SetPoint("BOTTOMRIGHT")
	-- Redraw when the width changed (a draw that resizes nothing never loops).
	-- Drawn while hidden, the cards would keep a stale width: they are
	-- drawn again on show.
	frame.flow.onResize = function(flow)
		if math.floor(flow:Width()) == frame.drawnWidth then return end
		if frame:IsVisible() then frame:Draw(true) else frame.dirty = true end
	end

	local function Redraw() frame:Draw(true) end

	function frame:SetKind(kind)
		NX.State().kind = FILTER_NAME[kind or ""] and kind or "all"
		self.lead = nil
		self:Draw()
	end

	function frame:ShowAway(on)
		self.away = on and true or false
		self:Draw()
	end

	function frame:Draw(keepScroll)
		if not self:IsShown() then
			self.dirty = true
			return
		end
		self.dirty = false
		self.drawnWidth = math.floor(self.flow:Width())
		local st = NX.State()
		local result = J:Next(NX.Opts())
		self.result = result
		local cards = result.cards or {}
		local counts = Count(cards)
		self.counts = counts
		local away = Away()
		self.awayCount = #away
		-- Header.
		local level = result.level or Level()
		self.header:SetTitle(L["Next trips"])
		local sentence
		if self.away then
			sentence = L["The cards you put away. They come back at your next level or after 24 hours."]
		elseif #cards > 0 then
			sentence = E:Plural(#cards, "%s idea for level %s, best first.", "%s ideas for level %s, best first."):format(K.Num(#cards), K.Num(level))
				.. " " .. L["Hover a card to see why it ranks where it does."]
		else
			sentence = (L["Ideas for level %s show here."]):format(K.Num(level))
		end
		self.header:SetSentence(sentence)
		local actions = {}
		if self.away then
			actions[1] = { L["Back to the list"], function() self:ShowAway(false) end, L["The suggestions again."] }
		elseif #away > 0 then
			actions[1] = { (L["Put away (%d)"]):format(#away), function() self:ShowAway(true) end,
				L["The cards you sent off with Not now, with Bring back."] }
		end
		self.header:SetActions(actions)
		-- Filters: a kind shows only while it has cards (or is the one picked).
		if not FILTER_NAME[st.kind] or (st.kind ~= "all" and (counts[st.kind] or 0) == 0 and not self.lead) then st.kind = "all" end
		for _, button in ipairs(self.kinds.buttons) do
			local n = counts[button.key] or 0
			local label = L[FILTER_NAME[button.key]]
			button:SetLabel(n > 0 and (label .. " " .. K.InkHex("secondary") .. n .. "|r") or label)
			button:SetShown(button.key == "all" or n > 0 or button.key == st.kind)
		end
		self.kinds:SetActive(st.kind)
		LayoutSwitch(self.kinds)
		local raids = A.db and A.db.nextRaids
		for _, button in ipairs(self.groups.buttons) do button:SetShown(button.key ~= "raid" or raids) end
		if st.group == "raid" and not raids then st.group = nil end
		self.groups:SetActive(st.group or "auto")
		LayoutSwitch(self.groups)
		self.times:SetActive(st.minutes and tostring(st.minutes) or "any")
		local controls = not self.away
		self.kinds:SetShown(controls)
		self.groups:SetShown(controls)
		self.times:SetShown(controls)
		if self.flowControls ~= controls then
			self.flowControls = controls
			self.flow:ClearAllPoints()
			self.flow:SetPoint("TOPLEFT", 0, controls and (CONTROLS_Y - 50) or CONTROLS_Y)
			self.flow:SetPoint("BOTTOMRIGHT")
		end

		local flow = self.flow
		flow:Begin()
		self.cardFrames, self.positions = {}, {}
		local width = flow:Width()
		if self.away then
			if #away == 0 then
				NX.Note(flow, L["Nothing put away"], L["Cards you send off with Not now wait here until your next level or for 24 hours."], nil, A.HUB_ICON)
			end
			for _, card in ipairs(away) do
				NX.Row(flow, { icon = NX.Icon(card), title = card.title, sub = card.subtitle or NX.KindName(card.kind),
					link = { L["Bring back"], function()
						J:ClearNotNow(card.id)
						self:Draw(true)
					end, L["The card joins the suggestions again."] } })
			end
			flow:Finish(keepScroll)
			return
		end
		-- A lead line from the Firsts strip.
		local lead = self.lead and FIRSTS[self.lead]
		local shown = Filtered(cards, st.kind)
		self.shown = shown
		if lead then
			local text = L[shown[1] and lead[2] or lead[3]]
			local buttons = { { L["Show all"], function() self:SetKind("all") end } }
			if self.lead == "attune" and E.Attunements and E.Attunements.Running and E.Attunements:Running() then
				table.insert(buttons, 1, { L["Attunements"], function() E.Attunements:Open() end })
			end
			NX.Note(flow, (L["First: %s"]):format(self.leadLabel or ""), text, buttons, self.leadIcon or A.HUB_ICON)
		end
		if not shown[1] then
			if not lead then EmptyNote(self, result, st.kind) end
		end
		for _, card in ipairs(shown) do
			local block = flow:Take("ak-card", NX.Card)
			local expanded = self.expanded[card.id] and true or false
			local height = block:Set(card, { width = width, plan = expanded, expanded = expanded, owner = self, redraw = Redraw,
				onToggle = function(data)
					self.expanded[data.id] = not self.expanded[data.id] or nil
					self:Draw(true)
				end })
			self.positions[card.id] = flow.y
			flow:Place(block, height, 0, 10)
			self.cardFrames[#self.cardFrames + 1] = block
		end
		if result.hidden and result.hidden > 0 then
			NX.Row(flow, { icon = false, title = E:Plural(result.hidden, "%d card put away", "%d cards put away"):format(result.hidden),
				sub = L["They come back at your next level or after 24 hours."],
				link = { L["Show"], function() self:ShowAway(true) end, L["The cards you sent off with Not now."] } })
		end
		flow:Finish(keepScroll)
		if self.scrollTo and self.positions[self.scrollTo] then
			local _, maximum = flow.bar:GetMinMaxValues()
			flow.bar:SetValue(math.min(self.positions[self.scrollTo], maximum or 0))
			self.scrollTo = nil
		end
	end

	frame:SetScript("OnShow", function(self) if self.dirty then self:Draw(true) end end)
	return frame
end

local function FirstLabel(key)
	for _, first in ipairs(A.Firsts and A:Firsts() or {}) do
		if first.key == key then return first.label, first.icon end
	end
	return nil
end

local function Show(frame, arg)
	frame.away = false
	-- A string is a filter kind ("dungeons") or a card id from J:Next() (the
	-- tracker's A:OpenSection("next", id)); nil is a rail click.
	if type(arg) == "string" then arg = FILTER_NAME[arg] and { kind = arg } or { card = arg } end
	if type(arg) == "table" and arg.id and not arg.card then arg.card = arg.id end
	if type(arg) == "table" then
		if arg.notnow then frame.away = true end
		if arg.first and FIRSTS[arg.first] then
			frame.lead = arg.first
			frame.leadLabel, frame.leadIcon = FirstLabel(arg.first)
			frame.leadLabel = frame.leadLabel or arg.first
			NX.State().kind = FIRSTS[arg.first][1]
		elseif arg.kind and FILTER_NAME[arg.kind] then
			frame.lead = nil
			NX.State().kind = arg.kind
		end
		if arg.card then
			NX.State().kind = "all"
			frame.lead = nil
			frame.expanded[arg.card] = true
			frame.scrollTo = arg.card
		end
	else
		frame.lead = nil
	end
	frame:Draw(arg == nil)
end

local function Refresh(frame, changed)
	if changed.adventure or changed.quests or changed.attune or changed.data or changed.settings or changed.player
		or changed.rank or changed.journey then
		frame:Draw(true)
	end
end

A:RegisterSection(KEY, {
	title = "Next trips",
	icon = "Interface\\Icons\\INV_Misc_Spyglass_02",
	desc = "Where to go next and why: dungeons with their quests, quests that fit your level, attunement steps, and zones to explore.",
	words = { "next", "trips", "where", "suggestions", "ideas" },
	build = Build,
	show = Show,
	refresh = Refresh,
	search = function(text)
		local folded = E:FoldText(strtrim(text or ""))
		if #folded < 3 then return {} end
		local out = {}
		local result = J:Next(NX.Opts())
		for _, card in ipairs(result.cards or {}) do
			local hay = E:FoldText((card.title or "") .. " " .. (card.subtitle or ""))
			if hay:find(folded, 1, true) then
				out[#out + 1] = { title = card.title, sub = (L["Next trip: %s"]):format(card.subtitle or NX.KindName(card.kind)),
					icon = NX.Icon(card), arg = { card = card.id } }
				if #out >= 10 then break end
			end
		end
		return out
	end,
})
