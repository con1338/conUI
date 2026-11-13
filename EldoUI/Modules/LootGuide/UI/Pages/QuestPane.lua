-- EldoUI Loot Guide: the Quests tab of an instance.
--
--   P.QuestItems(key, faction)   list items for the left pane: status
--                                headers and one row per chain
--   P.QuestRowCreate / Update    the Kit list row for those items
--   P.QuestDetail(parent)        the detail pane: name, XP and money,
--                                status, facts, rewards, chain (a step
--                                list, or a flowchart when it branches),
--                                objectives, start and finish, notes
--   P.FactionMenu(owner, value, fn) mine / Alliance / Horde / all
--
-- Everything shown is read from the quest log and EldoUI_LootData. Nothing
-- here accepts, turns in or skips a quest.
local _, E = ...
local LG = E.LootGuide
local Kit = LG.Kit
local P = LG.PageKit
local L = E.L

local Key = E.Key
local FACTIONS = { "mine", "Alliance", "Horde", "all" }
local FACTION_TITLE = E:TranslateValues({
	mine = E.Key("My faction"), Alliance = E.Key("Alliance"), Horde = E.Key("Horde"), all = E.Key("Both factions"),
})
P.FACTION_TITLE = FACTION_TITLE

function P.FactionMenu(owner, value, onPick)
	E.UIKit.ContextMenu(owner, function(_, root)
		root:CreateTitle(L["Show quests for"])
		for _, key in ipairs(FACTIONS) do
			root:CreateRadio(FACTION_TITLE[key], function() return value == key end, function() onPick(key) end)
		end
	end, { at = "owner" })
end

---------------------------------------------------------------------------
-- The list: { header = status, count } and { row = InstanceQuests row }
---------------------------------------------------------------------------
function P.QuestItems(key, faction)
	local items = {}
	local rows = LG:InstanceQuests(key, { faction = faction })
	local current, header
	for _, row in ipairs(rows) do
		if row.status ~= current then
			current = row.status
			header = { header = row.status, count = 0 }
			items[#items + 1] = header
		end
		header.count = header.count + 1
		items[#items + 1] = { row = row }
	end
	return items, #rows
end

function P.QuestRowCreate(row)
	row:RegisterForClicks("LeftButtonUp")
	row.glyph = Kit.Text(row, 13, "CENTER")
	row.glyph:SetPoint("LEFT", 2, 0)
	row.glyph:SetWidth(14)
	row.level = Kit.Text(row, 11, "RIGHT")
	row.level:SetPoint("RIGHT", -4, 0)
	row.tag = Kit.Chip(row, "")
	row.tag:SetPoint("RIGHT", row.level, "LEFT", -4, 0)
	row.name = Kit.Text(row, 12, "LEFT")
	row.name:SetPoint("LEFT", row.glyph, "RIGHT", 4, 0)
	row.name:SetPoint("RIGHT", row.tag, "LEFT", -4, 0)
	row.name:SetWordWrap(false)
	row.select = row:CreateTexture(nil, "BACKGROUND")
	row.select:SetAllPoints()
	E:AccentTexture(row.select, 0.15)
	row.hover = row:CreateTexture(nil, "HIGHLIGHT")
	row.hover:SetAllPoints()
	row.hover:SetColorTexture(1, 1, 1, E.tokens.hover.row)
	row:SetScript("OnEnter", function(self)
		local item = self.item
		if not (item and item.row) then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		local quest = LG:Quest(item.row.id)
		E.UIKit.TipTitle(GameTooltip, quest and quest.title or ("#" .. item.row.id))
		GameTooltip:AddLine(LG.QUEST_STATUS_TITLE[item.row.status] or "", P.QuestStatusColor(item.row.status))
		if item.row.status == "locked" and item.row.detail then
			E.UIKit.TipText(GameTooltip, (L["First: %s"]):format(LG:QuestTitle(item.row.detail) or ("#" .. item.row.detail)))
		elseif item.row.status == "low" and item.row.detail then
			E.UIKit.TipText(GameTooltip, (L["From level %d"]):format(item.row.detail))
		end
		if (item.row.chainLength or 1) > 1 then
			E.UIKit.TipText(GameTooltip, E:Plural(item.row.chainLength, "Part of a chain of %d quest", "Part of a chain of %d quests"):format(item.row.chainLength))
		end
		E:TooltipHint(GameTooltip, { L["Click"], L["the details"] })
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- selected: the quest id on show in the detail pane.
function P.QuestRowUpdate(row, item, selected)
	if item.header then
		row.glyph:SetText("")
		row.name:SetText(E:TextHex("accent") .. E:CaptionText(LG.QUEST_STATUS_TITLE[item.header] or item.header) .. "|r  " .. E:TextHex("secondary") .. item.count .. "|r")
		E:SetFont(row.name, E.tokens.size.tiny)
		row.level:SetText("")
		row.tag:Hide()
		row.select:Hide()
		row.hover:Hide()
		row:EnableMouse(false)
		return
	end
	local data = item.row
	local quest = LG:Quest(data.id)
	E:SetFont(row.name, E.tokens.size.label)
	row:EnableMouse(true)
	row.hover:Show()
	row.glyph:SetText(P.QUEST_GLYPH[data.status] or "")
	row.glyph:SetTextColor(P.QuestStatusColor(data.status))
	local name = quest and quest.title or ("#" .. data.id)
	if (data.chainLength or 1) > 1 then name = name .. " " .. E:TextHex("secondary") .. "(" .. data.chainLength .. ")|r" end
	row.name:SetText(name)
	local dim = data.status == "done" or data.status == "notforyou"
	if dim then Kit.Paint(row.name, "dim") else Kit.Paint(row.name) end
	local level = quest and quest.level
	if level and level > 0 then
		row.level:SetText(tostring(level))
		row.level:SetTextColor(Kit.LevelColor(level))
	else
		row.level:SetText("")
	end
	row.tag:SetShown(data.key)
	if data.key then row.tag:SetLabel(L["Key"], 1, 0.82, 0) end
	row.select:SetShown(selected == data.id)
end

---------------------------------------------------------------------------
-- Detail
---------------------------------------------------------------------------
local CLASS_BITS = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "DEATHKNIGHT", "SHAMAN", "MAGE", "WARLOCK", "MONK", "DRUID" }

local function ClassNames(mask)
	if not mask or mask == 0 then return end
	local names = {}
	for index, token in ipairs(CLASS_BITS) do
		if bit.band(mask, bit.lshift(1, index - 1)) ~= 0 then
			local name = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[token] or token
			names[#names + 1] = name
		end
	end
	return #names > 0 and table.concat(names, ", ") or nil
end

local function FactionName(factionID)
	local rep = C_Reputation
	if rep and rep.GetFactionDataByID then
		local ok, data = pcall(rep.GetFactionDataByID, factionID)
		if ok and type(data) == "table" and type(data.name) == "string" and not P.Secret(data.name) then return data.name end
	end
	return ("#%d"):format(factionID)
end

local function PlaceName(place)
	if place.kind == "object" then return LG:ObjectName(place.id) or (L["Object"] .. " " .. place.id) end
	if place.kind == "item" then
		local record = LG:ItemRecord(place.id)
		return record and record.name or ("item:" .. place.id)
	end
	local mob = LG:Mob(place.id)
	return mob and mob.name or L["NPC %s"]:format(tostring(place.id))
end

local function PlaceLine(flow, label, place)
	local name = PlaceName(place)
	local camps = place.kind ~= "item" and LG:SpawnPoints(place.kind, place.id) or {}
	local zone = camps[1] and LG:SpawnZone(camps[1])
	if not zone and camps[1] then
		for _, info in ipairs(LG:Catalog()) do
			if info.map == camps[1].map then zone = info.name break end
		end
	end
	local text = (E:TextHex("secondary") .. "%s|r  %s%s"):format(label, name, zone and ("  " .. E:TextHex("secondary") .. zone .. "|r") or "")
	local button = place.kind ~= "item" and P.MapButton(place.kind, place.id, name) or nil
	P.FlowLine(flow, text, nil, button)
end

---------------------------------------------------------------------------
-- The chain as a flowchart: the Attunements tab's chart, drawn from
-- LG:QuestGraph. Each node's look comes from the quest's status; the mouse
-- wheel scrolls the pane, and a drag moves a wide chart sideways.
---------------------------------------------------------------------------
local CHART_STATE = { turnin = "turnin", active = "active", available = "available", locked = "locked", low = "low",
	done = "done", notforyou = "otherfaction" }

local function ChainView()
	local A = E:GetModule("Attunements")
	return A and A.ChainView
end

-- Status per quest, read once per drawing.
local function Status(pane, questID)
	local cache = pane.statuses
	if not cache[questID] then cache[questID] = { LG:QuestStatus(questID) } end
	return cache[questID][1], cache[questID][2]
end

local function QuestSource(pane)
	local view = { zoom = 1 }
	local source = { wheel = false, view = view }
	function source.Graph() return pane.graph end
	function source.State(_, stepId)
		local step = pane.graph and pane.graph.byId[stepId]
		return step and CHART_STATE[(Status(pane, step.quest))] or "unknown"
	end
	function source.Title(step) return LG:QuestTitle(step.quest) or ("#" .. step.quest) end
	function source.Icon(_, state)
		if state == "turnin" then return "Interface\\GossipFrame\\ActiveQuestIcon", true end
		return "Interface\\GossipFrame\\AvailableQuestIcon", true
	end
	function source.Caption(step)
		local status, detail = Status(pane, step.quest)
		if status == "low" and detail then
			local r, g, b = Kit.LevelColor(detail)
			return Kit.Hex(r, g, b) .. (L["Level %d"]):format(detail) .. "|r"
		end
		return LG.QUEST_STATUS_TITLE[status]
	end
	function source.Visible() return true end
	function source.View() return view end
	return source
end

local function ChartHost(pane)
	local host = {}
	function host.OnStep(_, step, button)
		if button ~= "LeftButton" or step.quest == pane.questID then return end
		if pane.onOpen then pane.onOpen(step.quest) else pane:SetQuest(step.quest) end
	end
	function host.StepTooltip(_, tooltip, step)
		local status, detail = Status(pane, step.quest)
		E.UIKit.TipTitle(tooltip, LG:QuestTitle(step.quest) or ("#" .. step.quest))
		tooltip:AddLine(LG.QUEST_STATUS_TITLE[status] or "", P.QuestStatusColor(status))
		if status == "locked" and detail then
			E.UIKit.TipText(tooltip, (L["First: %s"]):format(LG:QuestTitle(detail) or ("#" .. detail)))
		elseif status == "low" and detail then
			E.UIKit.TipText(tooltip, (L["From level %d"]):format(detail))
		end
		local quest = LG:Quest(step.quest)
		if quest and quest.instance then E.UIKit.TipText(tooltip, LG:InstanceName(quest.instance) or quest.instance) end
		if step.quest ~= pane.questID then E:TooltipHint(tooltip, { L["Click"], L["the details"] }) end
	end
	function host.Selected() return pane.questID and ("q" .. pane.questID) end
	return host
end

-- "Flowchart | Step list" over a branching chain; the choice is kept with
-- the Journal's window state.
local function ChoiceBar(child)
	local bar = CreateFrame("Frame", nil, child)
	local function Pick(view)
		return function()
			P.JournalState().chainView = view
			if bar.pane then bar.pane:Redraw(true) end
		end
	end
	bar.chart = P.Toggle(bar, L["Flowchart"], Pick("chart"), L["Flowchart"], L["The chain as a chart: every step a box, lines to the steps that need it."])
	bar.chart:SetPoint("LEFT")
	bar.list = P.Toggle(bar, L["Step list"], Pick("list"), L["Step list"], L["One step per row, in order. Easier to read at a small window scale."])
	bar.list:SetPoint("LEFT", bar.chart, "RIGHT", 4, 0)
	return bar
end

-- Lines another module adds under a quest's facts (the Attunements tab:
-- "Part of attunement"). fn(flow, questID, pane) draws with P.FlowLine.
local detailExtras, detailExtraOrder = {}, {}
function P.AddQuestDetailExtra(key, fn)
	if not detailExtras[key] then detailExtraOrder[#detailExtraOrder + 1] = key end
	detailExtras[key] = fn
end

function P.QuestDetail(parent)
	local pane = CreateFrame("Frame", nil, parent)
	pane.flow = P.Flow(pane)
	pane.flow:SetAllPoints()
	pane.statuses = {}
	-- pane.faction: fn() -> "mine", "Alliance", "Horde" or "all", whose
	-- quests the flowchart shows (the Journal's faction choice).

	-- The flowchart at full width, as tall as the chain; zoomed out (down to
	-- the chart's smallest zoom) when the chain is wider than the pane.
	function pane:DrawChart(flow, graph, view)
		self.graph, self.statuses = graph, {}
		local chart = flow:Take("chainChart", function(child) return view.Create(child, ChartHost(self), QuestSource(self)) end)
		chart:Draw(self.questID)
		local layout = chart.layout
		if not layout then return end
		local A = E:GetModule("Attunements")
		local fit = math.floor(math.min(1, flow:Width() / layout.width) * 10) / 10
		chart.source.view.zoom = math.max(A.ZOOM_MIN, fit)
		flow:Place(chart, math.ceil(layout.height * chart.source.view.zoom) + 4, 0, 6)
		chart:Reset()
		chart:Apply()
		self.chart = chart
	end

	-- onOpen(questID): a chain step was clicked.
	function pane:SetQuest(questID, onOpen)
		self.questID, self.onOpen = questID, onOpen or self.onOpen
		self:Redraw()
	end

	function pane:Redraw(keepScroll)
		local flow = self.flow
		flow:Begin()
		local questID = self.questID
		local quest = questID and LG:Quest(questID)
		if not quest then
			P.FlowText(flow, L["Pick a quest on the left to see its chain, objectives and rewards."], 12, "secondary")
			flow:Finish()
			return
		end
		local status, detail = LG:QuestStatus(questID)

		-- Name, XP and money.
		local xp, money, live = LG:QuestReward(questID)
		local reward = {}
		if xp and xp > 0 then reward[#reward + 1] = (L["%s XP"]):format(BreakUpLargeNumbers and BreakUpLargeNumbers(xp) or tostring(xp)) end
		local coins = P.MoneyText(money)
		if coins then reward[#reward + 1] = coins end
		P.FlowText(flow, quest.title or ("#" .. questID), 16, nil, 0, 2)
		if #reward > 0 then
			P.FlowText(flow, table.concat(reward, "   ") .. (live and "" or ("  " .. E:TextHex("dim") .. L["(Classic data)"] .. "|r")), 12, nil, 0, 4)
		end

		-- Status.
		local r, g, b = P.QuestStatusColor(status)
		local statusText = Kit.Hex(r, g, b) .. (LG.QUEST_STATUS_TITLE[status] or status) .. "|r"
		if status == "locked" and detail then
			statusText = statusText .. "  " .. E:TextHex("secondary") .. (L["First: %s"]):format(LG:QuestTitle(detail) or ("#" .. detail)) .. "|r"
		elseif status == "low" and detail then
			statusText = statusText .. "  " .. E:TextHex("secondary") .. (L["From level %d"]):format(detail) .. "|r"
		elseif status == "notforyou" and detail then
			local why = { race = L["another race or faction"], class = L["another class"], skill = L["a profession you do not have"] }
			statusText = statusText .. "  " .. E:TextHex("secondary") .. (L["For %s"]):format(why[detail] or detail) .. "|r"
		end
		P.FlowText(flow, statusText, 12, nil, 0, 6)

		-- Facts.
		local facts = {}
		if quest.level and quest.level > 0 then facts[#facts + 1] = (L["Level %d"]):format(quest.level) end
		if quest.minLevel and quest.minLevel > 0 then facts[#facts + 1] = (L["needs level %d"]):format(quest.minLevel) end
		facts[#facts + 1] = LG:QuestSide(questID) or L["Both factions"]
		if quest.suggested and quest.suggested > 1 then facts[#facts + 1] = (L["group of %d"]):format(quest.suggested) end
		local classes = ClassNames(quest.classMask)
		if classes then facts[#facts + 1] = classes end
		if LG:IsKeyQuest(questID) then facts[#facts + 1] = L["gives a key"] end
		if quest.instance then facts[#facts + 1] = LG:InstanceName(quest.instance) or quest.instance end
		facts[#facts + 1] = live and L["Seen in Forever"] or L["Classic data"]
		P.FlowText(flow, table.concat(facts, "  ·  "), 11, "secondary", 0, 4)
		for _, key in ipairs(detailExtraOrder) do
			local ok, err = pcall(detailExtras[key], flow, questID, self)
			if not ok then geterrorhandler()(err) end
		end

		-- Rewards.
		if #quest.rewards > 0 or #quest.choice > 0 or #quest.reputation > 0 then
			P.FlowCaption(flow, L["Rewards"])
			for _, item in ipairs(quest.rewards) do
				P.FlowItem(flow, { itemID = item.id, tag = item.count and item.count > 1 and ("x" .. item.count) or L["Reward"],
					onClick = function() P.OpenItem(item.id) end })
			end
			if #quest.choice > 0 then
				P.FlowText(flow, L["Choose one:"], 11, "secondary", 0, 2)
				for _, item in ipairs(quest.choice) do
					P.FlowItem(flow, { itemID = item.id, tag = L["Choice"], onClick = function() P.OpenItem(item.id) end })
				end
			end
			for _, rep in ipairs(quest.reputation) do
				local color = rep.value >= 0 and E:TextHex("good") .. "+" or E:TextHex("bad")
				P.FlowText(flow, ("%s%d|r %s"):format(color, rep.value, FactionName(rep.faction)), 11, nil, 4, 2)
			end
		end

		-- Chain: the step list, or with branches a flowchart (a single line
		-- keeps the list).
		local chain = LG:QuestChain(questID)
		local graph = LG:QuestGraph(questID, self.faction and self.faction() or "mine")
		local view = graph and #graph.list > 1 and not graph.line and ChainView() or nil
		self.chainView, self.chart, self.choice = nil, nil, nil
		if #chain > 1 or view then
			local useChart = view and P.JournalState().chainView == "chart"
			self.chainView = useChart and "chart" or "list"
			local parts = useChart and #graph.list or #chain
			P.FlowCaption(flow, L["Chain"], E:Plural(parts, "%d part", "%d parts"):format(parts))
			if view then
				local bar = flow:Take("chainChoice", ChoiceBar)
				flow:Place(bar, 18, 0, 6)
				bar.pane = self
				bar.chart:SetOn(useChart)
				bar.list:SetOn(not useChart)
				self.choice = bar
			end
			if useChart then
				self:DrawChart(flow, graph, view)
				if graph.capped then
					P.FlowText(flow, E:Plural(#graph.list, "Shows the nearest %d quest of the chain.", "Shows the nearest %d quests of the chain."):format(#graph.list), 10, "secondary", 0, 4)
				end
			else
				for _, step in ipairs(chain) do
					local stepStatus = LG:QuestStatus(step.id)
					local sr, sg, sb = P.QuestStatusColor(stepStatus)
					local mark = step.step == "current" and (E:TextHex("accent") .. "> |r") or "   "
					local name = LG:QuestTitle(step.id) or ("#" .. step.id)
					if step.step == "current" then name = E:TextHex("accent") .. name .. "|r" end
					local where = step.instance and ("  " .. E:TextHex("secondary") .. "[" .. (LG:InstanceName(step.instance) or step.instance) .. "]|r") or ""
					local text = ("%s%d. %s%s|r %s%s"):format(mark, step.part, Kit.Hex(sr, sg, sb), P.QUEST_GLYPH[stepStatus] or "", name, where)
					local id = step.id
					P.FlowLine(flow, text, step.step ~= "current" and function()
						if self.onOpen then self.onOpen(id) else self:SetQuest(id) end
					end or nil, nil, name, LG.QUEST_STATUS_TITLE[stepStatus])
				end
			end
		end

		-- Objectives.
		local objectives = LG:QuestObjectives(questID)
		if #objectives.rows > 0 then
			P.FlowCaption(flow, L["Objectives"], objectives.live and L["from your quest log"] or nil)
			for _, row in ipairs(objectives.rows) do
				if row.text then
					local color = row.done and E:TextHex("good") or E:TextHex("body")
					P.FlowText(flow, color .. row.text .. "|r", 12, nil, 4, 2)
				elseif row.itemID then
					local chance = P.BestChance(row.itemID)
					P.FlowItem(flow, { itemID = row.itemID, tag = row.need and ("x" .. row.need) or nil,
						sub = chance and (L["drops %s"]):format(Kit.ChanceText(chance)) or nil,
						onClick = function() P.OpenItem(row.itemID) end })
				else
					local name = row.npc and PlaceName({ kind = "npc", id = row.npc }) or PlaceName({ kind = "object", id = row.object })
					local verb = row.npc and L["Kill %d x %s"] or L["Use %d x %s"]
					P.FlowText(flow, verb:format(row.need or 1, name), 12, nil, 4, 2)
				end
			end
		end

		-- Start and finish.
		if #quest.starts > 0 or #quest.ends > 0 then
			P.FlowCaption(flow, L["Start and finish"])
			for _, place in ipairs(quest.starts) do PlaceLine(flow, L["Starts"], place) end
			for _, place in ipairs(quest.ends) do PlaceLine(flow, L["Ends"], place) end
		end

		-- Notes: the quest text from the data.
		if type(quest.text) == "string" and quest.text ~= "" then
			P.FlowCaption(flow, L["Notes"])
			P.FlowText(flow, quest.text, 12, "secondary")
		end
		flow:Finish(keepScroll)
	end
	return pane
end
