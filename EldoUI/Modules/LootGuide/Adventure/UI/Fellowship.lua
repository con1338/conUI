-- EldoUI My Adventure: the Fellowship section, the companions list and
-- companion page in the Journal window's look.
--
--   Fellowship
--   You have shared the road with 23 adventurers, 41h in all. Most often
--   with Aria Swift.
--   -----------------------------------------------------------------------
--   [Most time][Recent][Met first] [Everyone][Dungeon runs][Noted] [Search]
--   +-----------------------------+ +-----------------------------+
--   | [ic] Aria Swift      3h 10m | | [ic] Brann Ironpick  1h 05m |
--   |      Night Elf Druid, l 24  | |      Dwarf Hunter, level 30 |
--   |      Met Sep 20 at level 12 | |      Met Oct 1 at level 20  |
--   | [=====|===|======|==]       | | [==|=========|=====]        |
--   +-----------------------------+ +-----------------------------+
--   FLEETING COMPANY  8   under 10 minutes together ------------- >
--
-- A companion page: the met sentence, the tally (time together, quests
-- together, dungeon runs, levels side by side), the time split with its
-- legend, your Player Notes note and mark, and the folds Dungeons together
-- (the journal's runs with them, a page at a time), Won with you (the loot
-- they won in those runs, with the rolls), Quests together (open first,
-- then the ones you handed in) and Moments.
--
-- People come from J:People(): the journal's fellowship (time, split,
-- levels), the Instances runs (people you ran dungeons with, also before
-- the journal kept company) and Player Notes (the note and mark; account
-- wide). Every number is one of those records; nothing is guessed. The
-- note and mark stay in Player Notes, which this page edits through
-- E.PlayerNotes:EditNote(key).
--
-- Routes: show(frame, arg) with nil (the list), { fellow = key },
-- { search = text }, { filter = "all"|"dungeons"|"noted" }; the address
-- "journal:fellow:<key>" opens a companion page.
--
-- Portions adapted from Forever Journal by Ugge Zen, MIT License (see
-- THIRD_PARTY_NOTICES.md): the fellowship list with its companion cards and
-- fleeting company, the companion page with its tally, split and folds, and
-- their texts.
--
-- MIT License
--
-- Copyright (c) 2026 Ugge Zen
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in all
-- copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
-- SOFTWARE.
local _, E = ...
local L = E.L
local Key = E.Key
local A = E.Adventure
local J = E.Journal
local LG = E.LootGuide
local K = E.AdventureKit
local T = E.tokens
local Fmt = A.Fmt
local LP = A.LogPages

local KEY = "fellowship"
local ICON = "Interface\\Icons\\Spell_Holy_PrayerOfHealing"
local DUNGEON_ICON = "Interface\\Icons\\INV_Misc_Key_03"
local CARD_HEIGHT = 92
local ROW_CAP = 120

local Text = LP.Text

local function H()
	return A.History
end

local function Rec()
	return J:Char()
end

local function Notes()
	local M = E.PlayerNotes
	return M and M.active and M or nil
end

local function FleetingSeconds()
	local minutes = tonumber(A.db and A.db.fleetingMinutes) or 10
	return math.max(minutes, 1) * 60
end

---------------------------------------------------------------------------
-- Player Notes: the note and the mark of a companion
---------------------------------------------------------------------------
-- The Player Notes key of a journal key: the one Player Notes linked when
-- they joined (OnJoined), else the store entry with the same journal key,
-- else Player Notes' own key for the name.
local function NoteKey(key)
	local M = E.PlayerNotes
	if not (M and M.Store) or type(key) ~= "string" then return nil end
	if E.PlainCall(RegionalUniqueNamesEnabled) == true then return M.CharacterKey(key) end
	if M.FindByJournal then
		local found = M:FindByJournal(key)
		if found then return found end
	end
	local exact = M.Key(key)
	if exact and M:Get(exact) then return exact end
	for storeKey, record in pairs(M:Store()) do
		if type(record) == "table" and J:Key(M:JournalName(storeKey)) == key then return storeKey end
	end
	return exact
end

local function NoteOf(key)
	local M = E.PlayerNotes
	local noteKey = NoteKey(key)
	local record = noteKey and M and M:Get(noteKey)
	if type(record) ~= "table" then return nil, nil, noteKey end
	local note = Text(record.note)
	local mark = M.MARKS and record.mark and M.MARKS[record.mark] and record.mark or nil
	return note, mark, noteKey
end

local MARK_PILL = { good = "good", avoid = "bad" }

local function MarkLabel(mark)
	if mark == "good" then return L["Good"] end
	if mark == "avoid" then return L["Avoid"] end
	return nil
end

---------------------------------------------------------------------------
-- The company: one entry per person
---------------------------------------------------------------------------
-- Quests together: questID -> true per key, from the hand-ins and the
-- quests in your log (both keep "with" when an objective moved forward
-- while you were grouped).
local function QuestsTogether(rec)
	local done, open = {}, {}
	for _, quest in ipairs(rec and rec.quests or {}) do
		if type(quest) == "table" and type(quest.with) == "table" and not quest.archived then
			for key in pairs(quest.with) do
				done[key] = done[key] or {}
				done[key][#done[key] + 1] = quest
			end
		end
	end
	for id, start in pairs(rec and rec.questStart or {}) do
		if type(start) == "table" and type(start.with) == "table" then
			for key in pairs(start.with) do
				open[key] = open[key] or {}
				open[key][tonumber(id) or id] = start
			end
		end
	end
	return done, open
end

local function RunCounts()
	local history = H()
	local counts = {}
	if not (history and history.RunCounts) then return counts end
	return history.RunCounts() or counts
end

local function Company()
	local rec = Rec()
	local fellows = rec and type(rec.fellows) == "table" and rec.fellows or {}
	local done, open = QuestsTogether(rec)
	local runs = RunCounts()
	local list = {}
	for _, person in ipairs(J:People()) do
		local sources = person.sources or {}
		local fellow = sources.fellowship
		local inst = sources.instances
		local raw = fellows[person.key]
		local notes = sources.playernotes
		if fellow or inst or notes then
			local entry = { key = person.key, name = Text(person.name) or person.key, raw = type(raw) == "table" and raw or nil }
			local function Pick(field)
				for _, item in ipairs({ fellow, inst, notes }) do
					if item and not E:IsSecret(item[field]) and item[field] ~= nil then return item[field] end
				end
				return nil
			end
			entry.class = Text(Pick("class"))
			entry.race = Text(Pick("race"))
			entry.level = tonumber(Pick("level"))
			entry.met = tonumber(fellow and fellow.met) or tonumber(inst and inst.first)
			entry.metLevel = tonumber(fellow and fellow.metLevel)
			entry.metZone = Text(fellow and fellow.metZone)
			entry.time = tonumber(fellow and fellow.time) or 0
			entry.split = fellow and fellow.split
			entry.last = math.max(tonumber(fellow and fellow.last) or 0, tonumber(inst and inst.last) or 0)
			entry.runs = math.max(runs[person.key] or 0, tonumber(inst and inst.runs) or 0)
			entry.quests = done[person.key] or {}
			entry.open = open[person.key] or {}
			local openCount = 0
			for _ in pairs(entry.open) do openCount = openCount + 1 end
			entry.questCount = #entry.quests + openCount
			entry.note, entry.mark = NoteOf(person.key)
			entry.notesOnly = not fellow and not inst
			entry.grouped = tonumber(notes and notes.grouped)
			if entry.notesOnly then entry.last = math.max(entry.last, tonumber(notes.last) or 0) end
			entry.noted = entry.note ~= nil or entry.mark ~= nil
			list[#list + 1] = entry
		end
	end
	return list
end

local function Find(key)
	for _, entry in ipairs(Company()) do
		if entry.key == key then return entry end
	end
end

local function Fleeting(entry)
	return not entry.notesOnly and entry.time < FleetingSeconds() and entry.runs == 0 and entry.questCount == 0 and not entry.noted
end

local function ColorName(entry)
	local color = LP.ClassColor(entry.class)
	if color then return E:TokenHex(color) .. entry.name .. "|r" end
	return entry.name
end

-- "Night Elf Druid, level 24"
local function WhoLine(entry)
	local who = table.concat({ entry.race or "", LP.ClassName(entry.class) or "" }, " "):gsub("^%s+", ""):gsub("%s+$", "")
	if who ~= "" and entry.level then return (L["%s, level %d"]):format(who, entry.level) end
	if entry.level then return (L["Level %d"]):format(entry.level) end
	if who ~= "" then return who end
	return nil
end

-- "Met Sep 20 at level 12, Darkshore"
local function MetLine(entry)
	if entry.notesOnly then
		if entry.grouped then
			return E:Plural(entry.grouped, "In your player notes: grouped %d time", "In your player notes: grouped %d times"):format(entry.grouped)
		end
		return L["In your player notes"]
	end
	if not entry.met then return nil end
	local text
	if entry.metLevel then
		text = (L["Met %s at level %d"]):format(Fmt.Short(entry.met), entry.metLevel)
	else
		text = (L["Met %s"]):format(Fmt.Short(entry.met))
	end
	if entry.metZone then text = text .. ", " .. entry.metZone end
	return text
end

local function TimeRight(entry)
	if entry.time > 0 then return Fmt.Span(entry.time) end
	if entry.runs > 0 then return E:Plural(entry.runs, "%d run", "%d runs"):format(entry.runs) end
	return nil
end

local function CardTip(entry)
	return function(tooltip)
		local who = WhoLine(entry)
		if who then tooltip:AddLine(who, unpack(T.text.secondary)) end
		local met = MetLine(entry)
		if met then tooltip:AddLine(met, unpack(T.text.secondary)) end
		LP.SplitTip(tooltip, entry.split, entry.time)
		if entry.runs > 0 then
			tooltip:AddDoubleLine(L["Dungeon runs"], tostring(entry.runs), unpack(T.text.body))
		end
		if entry.questCount > 0 then
			tooltip:AddDoubleLine(L["Quests together"], tostring(entry.questCount), unpack(T.text.body))
		end
		if entry.note then tooltip:AddLine((L["Your note: %s"]):format(entry.note), unpack(T.text.body)) end
		E:TooltipHint(tooltip, { L["Click"], L["open"] })
	end
end

---------------------------------------------------------------------------
-- The companion card (92 px, two per row)
---------------------------------------------------------------------------
local function MakeCard(row)
	local card = CreateFrame("Button", nil, row)
	card:RegisterForClicks("LeftButtonUp")
	card.box = K.Card(card)
	card.box:SetAllPoints()
	card.box:SetFrameLevel(math.max(card:GetFrameLevel() - 1, 0))
	card.hover = card:CreateTexture(nil, "HIGHLIGHT")
	card.hover:SetAllPoints()
	card.hover:SetColorTexture(1, 1, 1, T.hover.row)
	card.art = K.Art(card, 32)
	card.art:SetPoint("TOPLEFT", K.CARD_INSET, -K.CARD_INSET)
	card.time = K.Text(card, K.size.small, "RIGHT", "secondary")
	card.time:SetPoint("TOPRIGHT", -K.CARD_INSET, -12)
	card.pill = K.Pill(card, "", "plain")
	card.pill:SetPoint("RIGHT", card.time, "LEFT", -6, 0)
	card.name = K.Text(card, K.size.section + 2, "LEFT", "head", true)
	card.name:SetWordWrap(false)
	card.name:SetPoint("TOPLEFT", card.art, "TOPRIGHT", 10, 2)
	card.name:SetPoint("TOPRIGHT", -K.CARD_INSET, -K.CARD_INSET + 2)
	card.who = K.Text(card, K.size.small, "LEFT", "secondary")
	card.who:SetWordWrap(false)
	card.who:SetPoint("TOPLEFT", card.name, "BOTTOMLEFT", 0, -4)
	card.who:SetPoint("TOPRIGHT", card.name, "BOTTOMRIGHT", 0, -4)
	card.met = K.Text(card, K.size.small, "LEFT", "secondary")
	card.met:SetWordWrap(false)
	card.met:SetPoint("TOPLEFT", card.who, "BOTTOMLEFT", 0, -3)
	card.met:SetPoint("TOPRIGHT", card.who, "BOTTOMRIGHT", 0, -3)
	card.split = K.SplitBar(card, 6)
	card.split:SetPoint("BOTTOMLEFT", K.CARD_INSET, K.CARD_INSET)
	card.split:SetPoint("BOTTOMRIGHT", -K.CARD_INSET, K.CARD_INSET)
	card.split:EnableMouse(false)
	return card
end

local function SetCard(card, entry)
	K.SetIcon(card.art.icon, LP.ClassIcon(entry.class))
	card.name:SetText(entry.name)
	local color = LP.ClassColor(entry.class)
	if color then card.name:SetTextColor(color[1], color[2], color[3]) else K.Paint(card.name, "head") end
	local right = TimeRight(entry)
	card.time:SetText(right or "")
	local mark = MarkLabel(entry.mark)
	card.pill:SetShown(mark ~= nil)
	if mark then
		card.pill:Set(mark, MARK_PILL[entry.mark])
		if right then
			card.pill:SetPoint("RIGHT", card.time, "LEFT", -6, 0)
		else
			card.pill:SetPoint("RIGHT", card, "TOPRIGHT", -K.CARD_INSET, -18)
		end
	end
	-- The name stops 8 before the pill or the time, whichever is further left.
	local reserve = K.CARD_INSET + (right and card.time:GetStringWidth() or 0)
	if mark then reserve = reserve + (right and 6 or 0) + card.pill:GetWidth() end
	card.name:SetPoint("TOPRIGHT", card, "TOPRIGHT", -(reserve + 8), -K.CARD_INSET + 2)
	card.who:SetText(WhoLine(entry) or "")
	card.met:SetText(MetLine(entry) or "")
	local hasSplit = entry.time > 0
	card.split:SetShown(hasSplit)
	if hasSplit then card.split:SetParts(LP.SplitParts(entry.split)) end
	card:SetScript("OnClick", entry.onClick)
	LG.Kit.Tooltip(card, entry.name, CardTip(entry))
end

K.ROWS.akFellows = LP.CardRow(MakeCard, SetCard)

---------------------------------------------------------------------------
-- The list
---------------------------------------------------------------------------
local SORT = {
	{ "time", Key("Most time"), Key("The people you spent the most time with first.") },
	{ "recent", Key("Recent"), Key("The people you grouped with last first.") },
	{ "first", Key("Met first"), Key("In the order you met them.") },
}
local FILTER = {
	{ "all", Key("Everyone"), Key("Everyone you grouped with.") },
	{ "dungeons", Key("Dungeon runs"), Key("Only the people you ran a dungeon with.") },
	{ "noted", Key("Noted"), Key("Only the people you wrote a note on or marked Good or Avoid, with everyone in your player notes.") },
}
local SORT_KEYS, FILTER_KEYS = {}, {}
for _, entry in ipairs(SORT) do SORT_KEYS[entry[1]] = true end
for _, entry in ipairs(FILTER) do FILTER_KEYS[entry[1]] = true end

local function UIState()
	local rec = Rec()
	local ui = rec and rec.ui
	if type(ui) ~= "table" then
		LP.session = LP.session or {}
		ui = LP.session
	end
	if type(ui.fellowship) ~= "table" then ui.fellowship = {} end
	local s = ui.fellowship
	if not SORT_KEYS[s.sort or ""] then s.sort = "time" end
	if not FILTER_KEYS[s.filter or ""] then s.filter = "all" end
	return s
end

local function Sort(list, sort)
	table.sort(list, function(a, b)
		local ka, kb
		if sort == "first" then
			ka, kb = -(a.met or math.huge), -(b.met or math.huge)
		elseif sort == "recent" then
			ka, kb = a.last or 0, b.last or 0
		else
			ka, kb = a.time, b.time
			if ka == kb then ka, kb = a.runs, b.runs end
		end
		if ka ~= kb then return ka > kb end
		return a.name < b.name
	end)
	return list
end

local function SearchText(entry)
	local bits = { entry.name, entry.race or "", LP.ClassName(entry.class) or "", entry.metZone or "", entry.note or "" }
	return E:FoldText(table.concat(bits, " "))
end

local function Passes(entry, filter, words)
	if filter == "dungeons" and entry.runs == 0 then return false end
	if filter == "noted" and not (entry.noted or entry.notesOnly) then return false end
	if filter ~= "noted" and entry.notesOnly then return false end
	return #words == 0 or LP.Hits(SearchText(entry), words)
end

local function DrawList(frame)
	local s = UIState()
	frame:SetDetail(nil)
	frame.fellow = nil
	frame.sort:SetActive(s.sort)
	frame.filter:SetActive(s.filter)
	local company = Company()
	local words = LP.Words(K.Query(KEY))

	-- The sentence counts the people you grouped with on this character.
	local count, total, top = 0, 0, nil
	for _, entry in ipairs(company) do
		if not entry.notesOnly then
			count = count + 1
			total = total + entry.time
			if entry.time > 0 and (not top or entry.time > top.time) then top = entry end
		end
	end
	frame.header:SetTitle(L["Fellowship"])
	if count == 0 then
		frame.header:SetSentence(L["No one yet. Group up with someone and they join your fellowship here."])
	elseif total > 0 then
		local sentence = E:Plural(count, "You have shared the road with %s adventurer, %s in all.",
			"You have shared the road with %s adventurers, %s in all."):format(K.Num(BreakUpLargeNumbers(count)), K.Num(Fmt.Span(total)))
		if top and count > 1 then sentence = sentence .. " " .. (L["Most often with %s."]):format(ColorName(top)) end
		frame.header:SetSentence(sentence)
	else
		frame.header:SetSentence(E:Plural(count, "You have run dungeons with %s adventurer.", "You have run dungeons with %s adventurers.")
			:format(K.Num(BreakUpLargeNumbers(count))))
	end
	frame.header:SetActions(nil)
	local dungeons, noted = 0, 0
	for _, entry in ipairs(company) do
		if entry.runs > 0 then dungeons = dungeons + 1 end
		if entry.noted or entry.notesOnly then noted = noted + 1 end
	end
	frame.filter:SetLabel("dungeons", dungeons > 0 and (L["Dungeon runs"] .. " " .. K.InkHex("secondary") .. dungeons .. "|r") or L["Dungeon runs"])
	frame.filter:SetLabel("noted", noted > 0 and (L["Noted"] .. " " .. K.InkHex("secondary") .. noted .. "|r") or L["Noted"])

	local shown, fleeting = {}, {}
	for _, entry in ipairs(company) do
		if Passes(entry, s.filter, words) then
			entry.onClick = function() frame:OpenFellow(entry.key) end
			if s.filter == "all" and Fleeting(entry) then
				fleeting[#fleeting + 1] = entry
			else
				shown[#shown + 1] = entry
			end
		end
	end
	Sort(shown, s.sort)
	Sort(fleeting, s.sort)
	local items = {}
	for index = 1, #shown, 2 do
		items[#items + 1] = { kind = "akFellows", cards = { shown[index], shown[index + 1] }, height = CARD_HEIGHT }
	end
	if #fleeting > 0 then
		local rows = {}
		for index, entry in ipairs(fleeting) do
			if index > ROW_CAP and not frame.allFleeting then
				rows[#rows + 1] = { kind = "more", text = (L["Show all %d"]):format(#fleeting), onClick = function()
					frame.allFleeting = true
					frame:Draw(true)
				end }
				break
			end
			rows[#rows + 1] = { kind = "line", icon = LP.ClassIcon(entry.class), text = ColorName(entry),
				time = entry.time > 0 and Fmt.Span(entry.time) or nil, onClick = entry.onClick, tipTitle = entry.name, tip = CardTip(entry) }
		end
		if #shown > 0 then items[#items + 1] = { kind = "space", height = 4 } end
		LP.AddFold(items, "fellowship:fleeting", L["Fleeting company"],
			("%d · %s"):format(#fleeting, E:Plural(math.floor(FleetingSeconds() / 60), "under %d minute together", "under %d minutes together")
				:format(math.floor(FleetingSeconds() / 60))),
			rows, false, function() frame:Draw(true) end, #words > 0)
	end
	frame.shown, frame.fleeting = shown, fleeting
	if #shown == 0 and #fleeting == 0 then items = {} end
	if count == 0 and s.filter ~= "noted" and #words == 0 then
		frame.list:SetEmpty(L["No one yet"], L["Group up with someone and they join your fellowship here."], ICON)
	else
		frame.list:SetEmpty(L["Nothing matches"], L["No one in your fellowship matches that search or filter."], ICON,
			{ { L["Clear the filters"], function() frame:ClearFilters() end } })
	end
	return items
end

---------------------------------------------------------------------------
-- A companion page
---------------------------------------------------------------------------
local function QuestTitle(id, title)
	title = Text(title)
	if title then return title end
	local quest = id and LG.Quest and LG:Quest(tonumber(id))
	return quest and Text(quest.title) or (L["Quest %d"]):format(tonumber(id) or 0)
end

local function OpenQuestState(id)
	for _, quest in ipairs(J.OpenQuests and J:OpenQuests() or {}) do
		if quest.questID == id then return quest end
	end
end

local function QuestRows(entry)
	local rows = {}
	local openIDs = {}
	for id in pairs(entry.open) do
		if type(id) == "number" then openIDs[#openIDs + 1] = id end
	end
	table.sort(openIDs, function(a, b) return (tonumber(entry.open[a].t) or 0) > (tonumber(entry.open[b].t) or 0) end)
	for _, id in ipairs(openIDs) do
		local state = OpenQuestState(id)
		if state then
			local sub
			if state.ready then
				sub = L["Ready to hand in"]
			elseif (state.need or 0) > 0 then
				sub = (L["In progress · %d / %d"]):format(state.have or 0, state.need)
			else
				sub = L["In progress"]
			end
			rows[#rows + 1] = { icon = "Interface\\GossipFrame\\AvailableQuestIcon", title = QuestTitle(id, state.title), sub = sub,
				time = entry.open[id].t and Fmt.Short(entry.open[id].t) or nil,
				onClick = A:SectionShown("quests") and function() A:OpenSection("quests", { quest = id }) end or nil,
				tip = function(tooltip)
					E.UIKit.TipText(tooltip, L["In your quest log."])
					if A:SectionShown("quests") then E:TooltipHint(tooltip, { L["Click"], L["open it in Quests"] }) end
				end }
		end
	end
	for index = #entry.quests, 1, -1 do
		local quest = entry.quests[index]
		local where = Text(quest.z)
		rows[#rows + 1] = { icon = "Interface\\GossipFrame\\ActiveQuestIcon", title = QuestTitle(quest.id, quest.title),
			sub = where and (L["Handed in: %s"]):format(where) or L["Handed in"], time = Fmt.Short(quest.t),
			onClick = A:SectionShown("quests") and function() A:OpenSection("quests", { quest = quest.id, t = quest.t }) end or nil,
			tip = A:SectionShown("quests") and function(tooltip) E:TooltipHint(tooltip, { L["Click"], L["open it in Quests"] }) end or nil }
	end
	return rows
end

local function OpenRun(run)
	if A:SectionShown("places") and run.instance then
		A:OpenSection("places", { dungeon = run.instance })
	elseif A:SectionShown("journey") then
		A:OpenSection("journey", { day = Fmt.DayKey(run.enter) })
	end
end

-- The runs you shared, newest first: a page at a time, the rows built as
-- they come into view.
local function RunRows(entry, redraw)
	local history = H()
	if not (history and history.RunPlacesWith and history.RunRows) then return {}, 0 end
	local listKey = "fellow:" .. tostring(entry.key)
	local places, total = history.RunPlacesWith(entry.key, history.Shown(listKey))
	if total == 0 then return {}, 0 end
	local rows = history.RunRows(listKey, places, total, function(run)
		local bits = { Text(run.instance) or L["A dungeon"] }
		if run.duration then bits[#bits + 1] = (L["%s inside"]):format(Fmt.Span(run.duration)) end
		if run.bosses > 0 then bits[#bits + 1] = E:Plural(run.bosses, "%d boss", "%d bosses"):format(run.bosses) end
		local others = {}
		for _, key in ipairs(run.with) do
			if key ~= entry.key then others[#others + 1] = key end
		end
		local sub
		if #others > 0 and history.Names then
			sub = (L["Also with %s"]):format(history.Names(others))
		elseif run.level then
			sub = (L["At level %d"]):format(run.level)
		end
		local drops = history.DropsNote and history.DropsNote(run)
		if drops then sub = sub and (sub .. " · " .. drops) or drops end
		local art = run.instance and history.Key and history.Key(run.instance)
		return { icon = art and LG:InstanceArt(art) or DUNGEON_ICON, title = table.concat(bits, " · "), sub = sub,
			time = Fmt.Short(run.enter), tip = history.RunTip and history.RunTip(run) or nil, tipTitle = Text(run.instance),
			onClick = function() OpenRun(run) end }
	end, redraw)
	return rows, total
end

-- What they won while you were in the group: one row per item, newest
-- first, from the runs the index names (a page at a time).
local function WonRows(entry, redraw)
	local history, R = H(), A.Runs
	if not (history and history.Run and R and R.WonBy) then return {}, 0 end
	local places = R:WonBy(entry.key)
	local total = #places
	if total == 0 then return {}, 0 end
	local listKey = "won:" .. tostring(entry.key)
	local shown = history.Shown(listKey)
	local rows, seen = {}, {}
	for position = #places, 1, -1 do
		local place = places[position]
		if #rows >= shown then break end
		if not seen[place] then
			seen[place] = true
			local run = history.Run(place)
			local drops = run and history.Drops(run) or {}
			for index = #drops, 1, -1 do
				local drop = drops[index]
				if drop.key == entry.key and not drop.pass and #rows < shown then
					local mine
					for _, roll in ipairs(drop.rolls) do
						if roll.won then mine = roll end
					end
					local where = Text(run.instance) or L["A dungeon"]
					local art = run.instance and history.Key and history.Key(run.instance)
					rows[#rows + 1] = { icon = art and LG:InstanceArt(art) or DUNGEON_ICON, title = drop.item or L["An item"],
						sub = mine and ("%s · %s"):format(where, history.RollText(mine)) or where, time = Fmt.Short(drop.t or run.enter),
						tipTitle = drop.item or L["An item"], tip = function(tooltip)
							tooltip:AddLine(("%s, %s"):format(where, Fmt.Day(drop.t or run.enter)), unpack(T.text.secondary))
							local line = history.RollsLine(drop)
							if line ~= "" then tooltip:AddLine(line, T.text.body[1], T.text.body[2], T.text.body[3], true) end
						end,
						onClick = function() OpenRun(run) end }
				end
			end
		end
	end
	local out = LP.Ledger(rows)
	if total > #rows then
		out[#out + 1] = { kind = "more", text = (L["Show all %d"]):format(total), onClick = function()
			history.SetShown(listKey, total)
			if redraw then redraw() end
		end }
	end
	return out, total
end

-- The meetings with them: when you met and each stretch together (their
-- companion record, as the Companions source tells the timeline) and the
-- journal's own rows of those kinds about them. Nothing else is read.
local function Moments(entry)
	local out = {}
	for _, row in ipairs(J:RowsWhere(nil, { met = true, together = true }, "key", entry.key)) do
		out[#out + 1] = row
	end
	local rec = J:Char()
	local refs = rec and type(rec.refs) == "table" and rec.refs or {}
	local fellow = type(entry.raw) == "table" and entry.raw or nil
	local key = entry.key
	local met = fellow and tonumber(fellow.met)
	if met and not refs["fellowship:met:" .. key] then
		out[#out + 1] = { t = met, kind = "met", level = fellow.metLevel, zone = fellow.metZone, subzone = fellow.metSub,
			name = fellow.name or key, class = fellow.class, key = key }
	end
	for _, step in ipairs(fellow and type(fellow.steps) == "table" and fellow.steps or {}) do
		local t = tonumber(step.t)
		if t and not refs[("fellowship:together:%s:%s"):format(key, tostring(step.secs))] then
			out[#out + 1] = { t = t, kind = "together", level = step.l, zone = false, name = fellow.name or key, seconds = step.secs,
				key = key }
		end
	end
	return out
end

local function MomentRows(entry)
	local rows = {}
	for index, row in ipairs(Moments(entry)) do
		local title, _, icon = A:LineText(row)
		rows[#rows + 1] = { kind = "line", icon = icon, text = title, time = Fmt.When(row.t), sort = row.t or index,
			onClick = A:SectionShown("journey") and function() A:OpenSection("journey", { day = Fmt.DayKey(row.t) }) end or nil,
			tipTitle = title, tip = function(tooltip)
				tooltip:AddLine(("%s, %s"):format(Fmt.Day(row.t), Fmt.Clock(row.t)), unpack(T.text.secondary))
				local zone = Text(row.zone)
				if zone then tooltip:AddLine(zone, unpack(T.text.body)) end
			end }
	end
	table.sort(rows, function(a, b) return a.sort > b.sort end)
	return rows
end

local function LevelsSide(entry)
	local raw = entry.raw
	local low, high = raw and tonumber(raw.lowLevel), raw and tonumber(raw.highLevel)
	if low and high and low ~= high then return ("%d-%d"):format(low, high) end
	if low then return tostring(low) end
	return nil
end

local function MetSentence(entry)
	if entry.notesOnly then
		return L["You have not grouped on this character yet; your player notes know them."]
	end
	if not entry.met then return L["You ran dungeons together before the journal kept company."] end
	local text
	if entry.metLevel and entry.metZone then
		text = (L["Met %s at level %s, %s."]):format(Fmt.Long(entry.met), K.Num(entry.metLevel), entry.metZone)
	elseif entry.metLevel then
		text = (L["Met %s at level %s."]):format(Fmt.Long(entry.met), K.Num(entry.metLevel))
	else
		text = (L["Met %s."]):format(Fmt.Long(entry.met))
	end
	local theirs = entry.raw and tonumber(entry.raw.theirMetLevel)
	if theirs then text = text .. " " .. (L["They were level %s."]):format(K.Num(theirs)) end
	return text
end

local function DrawFellow(frame, key)
	local entry = Find(key)
	frame.fellow = key
	frame:SetDetail(L["Fellowship"], function() frame:ShowList() end)
	local items = {}
	if not entry then
		frame.header:SetTitle(tostring(key))
		frame.header:SetSentence(L["The journal has no company by that name."])
		frame.header:SetActions(nil)
		frame.list:SetEmpty(L["No one by that name"], L["They may be in another character's fellowship."], ICON)
		return items
	end
	local color = LP.ClassColor(entry.class)
	if color then frame.header:SetTitle(entry.name, color[1], color[2], color[3]) else frame.header:SetTitle(entry.name) end
	frame.header:SetSentence(MetSentence(entry))
	local M = Notes()
	local _, _, noteKey = NoteOf(key)
	local actions = {}
	if M and noteKey and M.EditNote then
		actions[#actions + 1] = { entry.note and L["Edit note"] or L["Add note"], function() M:EditNote(noteKey) end,
			L["Your note on them, kept in Player Notes and shown on their tooltip."] }
	end
	frame.header:SetActions(actions)

	local questRows = QuestRows(entry)
	local function Redraw() frame:Draw(true) end
	local runRows, runCount = RunRows(entry, Redraw)
	runCount = math.max(runCount, entry.runs)
	local wonRows, wonCount = WonRows(entry, Redraw)
	items[#items + 1] = { kind = "akStats", stats = {
		{ entry.time > 0 and Fmt.Span(entry.time) or nil, L["grouped together"], nil,
			L["Time in the same group, away from keyboard not counted."] },
		{ entry.questCount, L["quests together"], nil,
			L["A quest counts once you both have it and one of its objectives moves forward while you are grouped."] },
		{ runCount, L["dungeon runs"] },
		{ LevelsSide(entry), L["levels side by side"], nil, L["Your levels while you were grouped with them."] },
	} }
	if entry.time > 0 then
		items[#items + 1] = { kind = "akSplit", parts = LP.SplitParts(entry.split), tipTitle = L["Time together"],
			tip = function(tooltip) LP.SplitTip(tooltip, entry.split, entry.time) end }
	end
	if entry.note or entry.mark then
		local mark = MarkLabel(entry.mark)
		local text = entry.note and (mark and ("%s: %s"):format(mark, entry.note) or entry.note) or mark
		items[#items + 1] = { kind = "note", text = text, sub = L["Your note, from Player Notes"], pinned = entry.mark == "good" }
		items[#items + 1] = { kind = "space", height = 4 }
	end
	items[#items + 1] = { kind = "space", height = 6 }

	LP.AddFold(items, "fellowship:runs", L["Dungeons together"], tostring(runCount),
		#runRows > 0 and runRows or { { kind = "akText", text = L["None yet."] } }, true, Redraw)
	if wonCount > 0 then
		LP.AddFold(items, "fellowship:won", L["Won with you"], tostring(wonCount), wonRows, false, Redraw)
	end
	LP.AddFold(items, "fellowship:quests", L["Quests together"], tostring(#questRows),
		#questRows > 0 and LP.Ledger(questRows, ROW_CAP) or { { kind = "akText",
			text = L["None yet. A quest counts once you both have it and one of its objectives moves forward while you are grouped."] } },
		true, function() frame:Draw(true) end)
	local moments = MomentRows(entry)
	if #moments > 0 then
		LP.AddFold(items, "fellowship:moments", L["Moments"], tostring(#moments), moments, true, function() frame:Draw(true) end)
	end
	return items
end

---------------------------------------------------------------------------
-- The section
---------------------------------------------------------------------------
local function Build(parent)
	local frame
	frame = LP.Page(parent, {
		empty = { L["No one yet"], L["Group up with someone and they join your fellowship here."], ICON },
		controls = function(page, bar)
			page.sort = K.Switch(bar, SORT, UIState().sort, function(sort)
				UIState().sort = sort
				page:Draw()
			end)
			page.sort:SetPoint("LEFT", 0, 0)
			page.filter = K.Switch(bar, FILTER, UIState().filter, function(filter)
				UIState().filter = filter
				page:Draw()
			end)
			page.filter:SetPoint("LEFT", page.sort, "RIGHT", 12, 0)
			page.search = K.Search(bar, KEY, L["Search your fellowship"], function() page:Draw() end)
			page.search:SetPoint("LEFT", page.filter, "RIGHT", 12, 0)
			page.search:SetPoint("RIGHT", bar, "RIGHT", 0, 0)
		end,
	})

	function frame:Draw(keepScroll)
		if not self:IsShown() then
			self.dirty = true
			return
		end
		self.dirty = false
		local started = debugprofilestop()
		local items = self.fellow and DrawFellow(self, self.fellow) or DrawList(self)
		self.items = items
		self.list:SetData(items, keepScroll)
		self.buildMs = debugprofilestop() - started
	end

	function frame:ShowList()
		self.fellow = nil
		self:Draw()
	end

	function frame:OpenFellow(key)
		self.fellow = key
		self:Draw()
	end

	function frame:SetSearch(text)
		self.search:SetText(text or "")
		self.search:GetScript("OnTextChanged")(self.search, true)
	end

	function frame:ClearFilters()
		UIState().filter = "all"
		self:SetSearch("")
		self:Draw()
	end

	frame:SetScript("OnShow", function(self) if self.dirty then self:Draw(true) end end)
	return frame
end

local function Show(frame, arg)
	if type(arg) == "string" then
		local kind, id = J:ParseAddress(arg)
		if kind == "fellow" then arg = { fellow = tostring(id) } else arg = { search = arg } end
	end
	if type(arg) == "table" then
		if arg.filter and FILTER_KEYS[arg.filter] then UIState().filter = arg.filter end
		if arg.sort and SORT_KEYS[arg.sort] then UIState().sort = arg.sort end
		if arg.search then frame:SetSearch(arg.search) end
		frame.fellow = arg.fellow and tostring(arg.fellow) or nil
	elseif arg == nil and not frame.drawnOnce then
		frame.fellow = nil
	end
	frame.drawnOnce = true
	frame:Draw(type(arg) ~= "table")
end

local function Refresh(frame, changed)
	if changed.adventure or changed.settings or changed.data then frame:Draw(true) end
end

A:RegisterSection(KEY, {
	title = "Fellowship",
	icon = ICON,
	desc = "The people you traveled with: time together and how it was spent, dungeons and quests together, and your notes on them.",
	words = { "fellowship", "companions", "friends", "group", "party" },
	build = Build,
	show = Show,
	refresh = Refresh,
	search = function(text)
		local words = LP.Words(text)
		if #words == 0 then return {} end
		local out = {}
		for _, entry in ipairs(Company()) do
			if not entry.notesOnly and LP.Hits(SearchText(entry), words) then
				out[#out + 1] = { title = entry.name, sub = WhoLine(entry) or MetLine(entry) or L["Companion"],
					icon = LP.ClassIcon(entry.class), arg = { fellow = entry.key } }
				if #out >= 20 then break end
			end
		end
		return out
	end,
})

-- "journal:fellow:<key>" opens a companion page.
J:RegisterAddress("fellow", function(id)
	if not A:SectionShown(KEY) then return false end
	return A:OpenSection(KEY, { fellow = tostring(id) })
end)

-- Fellowship knows a companion by J:Key(unit), Player Notes by its own
-- "Name-Realm" key; when someone joins, the two are linked so the page
-- finds the note and Player Notes finds the journal (Player Notes'
-- OnJoined, fired from its group scan).
local M = E.PlayerNotes
if M and M.OnJoined then
	M:OnJoined(function(noteKey, unit)
		local key = J:Key(unit)
		if key and M.LinkJournal then M:LinkJournal(noteKey, key) end
	end)
end

A.FellowshipPage = { NoteKey = NoteKey, Company = Company, Find = Find }
