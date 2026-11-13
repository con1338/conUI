-- EldoUI Attunements: the tab in the Loot Guide window.
--
--   +--------------+-----------------------------------------------------+
--   | Faction      | Flowchart  Step list  Overview        - 100 % +  Fit|
--   | RAIDS        | [art] Molten Core (55-60)                           |
--   |  * MC   3/4  | Raid attunement · Raid 40 · 3 of 4 steps            |
--   |  * Ony  5/16 | line of description                                 |
--   | KEYS         |-----------------------------------------------------|
--   |  ...         |   the chain (flowchart or step list), the overview  |
--   |              |   (My characters / Guild), a designed empty state   |
--   |              |-----------------------------------------------------|
--   |              |   the step you clicked: quest detail, map, Journal  |
--   +--------------+-----------------------------------------------------+
--
-- Window state (selected entry, zoom, overview group) is kept per character
-- in LG:UI().attune; the view and faction are the module's settings.
-- Everything shown comes from A (Core.lua): this file keeps no progress.
local _, E = ...
local LG = E.LootGuide
local Kit = LG.Kit
local P = LG.PageKit
local L = E.L
local Key = E.Key
local A = E:GetModule("Attunements")

local LEFT_WIDTH = 240
local BAR = 22
local HEADER = 64
local DETAIL_HEIGHT = 190
local OVERVIEW_COLUMNS = 6
local CELL_WIDTH = 92
local NAME_WIDTH = 170

local function State()
	local s = A.PageState()
	if s.mode ~= "entry" and s.mode ~= "overview" and s.mode ~= "status" then s.mode = "entry" end
	if s.overview ~= "mine" and s.overview ~= "guild" then s.overview = A.db and A.db.overview or "mine" end
	if s.group ~= "raids" and s.group ~= "keys" and s.group ~= "misc" then s.group = "raids" end
	s.columnPage = tonumber(s.columnPage) or 1
	return s
end

local function Hex(color) return E:TokenHex(color) end
local function Secondary(text) return Hex(E.tokens.text.secondary) .. tostring(text) .. "|r" end
A.Secondary = Secondary

-- Solo / Party / Raid in good / warn / bad (how many players a step wants).
function A:SizeColored(size)
	local color = (not size or size <= 1) and E.tokens.text.good or size <= 5 and E.tokens.text.warn or E.tokens.text.bad
	return Hex(color) .. self:SizeText(size) .. "|r"
end

local function EntrySize(entry)
	local info = entry.instance and LG:InstanceInfo(entry.instance)
	if info then return info.size or 5 end
	return 1
end

local CHECK = "|A:common-icon-checkmark:14:14|a"
local function CheckMark()
	if Kit.HasAtlas("common-icon-checkmark") then return CHECK end
	return P.QuestGlyph("done")
end
A.CheckMark = CheckMark

-- A cell for one character and entry: a check, "x/n" or "-".
function A:CellText(key, charKey, record)
	local entry = self:Get(key)
	if not entry then return Secondary("-") end
	local faction = record and record.faction or LG:Player().faction
	if entry.side and faction and entry.side ~= faction then return Secondary("-") end
	local done, total, _, state = self:Progress(key, charKey)
	if state == "done" then return CheckMark() end
	if total == 0 then return Secondary("-") end
	if done == 0 then return Secondary(("0/%d"):format(total)) end
	return ("%d/%d"):format(done, total)
end

---------------------------------------------------------------------------
-- Left list
---------------------------------------------------------------------------
local function ListItems()
	local items = {}
	local byGroup = {}
	for _, key in ipairs(A:List()) do
		local entry = A:Get(key)
		byGroup[entry.group] = byGroup[entry.group] or {}
		table.insert(byGroup[entry.group], key)
	end
	for _, group in ipairs(A.GROUPS) do
		local list = byGroup[group.key]
		if list and #list > 0 then
			items[#items + 1] = { header = group.title, count = #list }
			for _, key in ipairs(list) do items[#items + 1] = { key = key } end
		end
	end
	return items
end

local function RowCreate(row)
	row.select = row:CreateTexture(nil, "BACKGROUND")
	row.select:SetAllPoints()
	E:AccentTexture(row.select, E.tokens.pressed)
	row.hover = row:CreateTexture(nil, "HIGHLIGHT")
	row.hover:SetAllPoints()
	row.hover:SetColorTexture(1, 1, 1, E.tokens.hover.row)
	row.dot = row:CreateTexture(nil, "ARTWORK")
	row.dot:SetSize(6, 6)
	row.dot:SetPoint("LEFT", 6, 0)
	row.mark = Kit.Text(row, 12, "CENTER")
	row.mark:SetPoint("CENTER", row.dot, "CENTER")
	row.right = Kit.Text(row, 11, "RIGHT", "secondary")
	row.right:SetPoint("RIGHT", -4, 0)
	row.name = Kit.Text(row, 12, "LEFT")
	row.name:SetPoint("LEFT", row.dot, "RIGHT", 8, 0)
	row.name:SetPoint("RIGHT", row.right, "LEFT", -4, 0)
	row.name:SetWordWrap(false)
	row:SetScript("OnClick", function(self)
		if self.item and self.item.key then self.list.page:Select(self.item.key) end
	end)
	row:SetScript("OnEnter", function(self)
		local key = self.item and self.item.key
		if not key then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		self.list.page:EntryTooltip(GameTooltip, key)
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function RowUpdate(row, item)
	if item.header then
		row.dot:Hide()
		row.mark:SetText("")
		row.name:SetText(E:TextHex("accent") .. E:CaptionText(item.header) .. "|r  " .. Secondary(item.count))
		E:SetFont(row.name, E.tokens.size.section - 2)
		row.right:SetText("")
		row.select:Hide()
		row.hover:Hide()
		row:EnableMouse(false)
		return
	end
	row:EnableMouse(true)
	row.hover:Show()
	E:SetFont(row.name, E.tokens.size.label)
	local key = item.key
	local entry = A:Get(key)
	local done, total, _, state = A:Progress(key)
	row.select:SetShown(State().selected == key)
	row.name:SetText(A:Name(entry))
	local low = entry.minLevel and entry.minLevel > LG:Player().level and state ~= "done"
	if low or state == "locked" then Kit.Paint(row.name, "dim") else Kit.Paint(row.name) end
	if state == "done" then
		row.dot:Hide()
		row.mark:SetText(CheckMark())
		row.right:SetText("")
	else
		row.mark:SetText("")
		row.dot:Show()
		local r, g, b = A:StateColor(state == "active" and "active" or state == "available" and "available" or "locked")
		row.dot:SetColorTexture(r, g, b, 1)
		if low then
			row.right:SetText((L["Lvl %d"]):format(entry.minLevel))
		elseif total > 0 then
			row.right:SetText(("%d/%d"):format(done, total))
		else
			row.right:SetText("")
		end
	end
end

---------------------------------------------------------------------------
-- The overview grid: one row per character (or guild member), one column
-- per entry. Shared by My characters and Guild (Guild.lua).
---------------------------------------------------------------------------
function A.CreateGrid(parent, opts)
	local grid = CreateFrame("Frame", nil, parent)
	grid.opts = opts or {}
	grid.heads = {}
	grid.header = CreateFrame("Frame", nil, grid)
	grid.header:SetPoint("TOPLEFT")
	grid.header:SetPoint("TOPRIGHT")
	grid.header:SetHeight(20)
	local line = Kit.Divider(grid.header)
	line:SetPoint("BOTTOMLEFT")
	line:SetPoint("BOTTOMRIGHT")
	grid.nameHead = Kit.Text(grid.header, 11, "LEFT", "secondary")
	grid.nameHead:SetPoint("LEFT", 4, 0)
	grid.columns = {}
	grid.list = Kit.CreateList(grid, {
		rowHeight = 20,
		create = function(row)
			row.hover = row:CreateTexture(nil, "HIGHLIGHT")
			row.hover:SetAllPoints()
			row.hover:SetColorTexture(1, 1, 1, E.tokens.hover.row)
			row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
			row.label = Kit.Text(row, 12, "LEFT")
			row.label:SetPoint("LEFT", 4, 0)
			row.label:SetWidth((grid.opts.nameWidth or NAME_WIDTH) - 8)
			row.label:SetWordWrap(false)
			row.cells = {}
			row:SetScript("OnClick", function(self, button)
				if grid.opts.onClick and self.item then grid.opts.onClick(self.item, button, self) end
			end)
		end,
		update = function(row, item)
			row.label:SetText(item.label or "")
			local x = grid.opts.nameWidth or NAME_WIDTH
			for index = 1, math.max(#row.cells, #grid.columns) do
				local cell = row.cells[index]
				local column = grid.columns[index]
				if not cell then
					cell = CreateFrame("Button", nil, row)
					cell:SetHeight(18)
					cell.text = Kit.Text(cell, 12, "CENTER")
					cell.text:SetAllPoints()
					cell:SetScript("OnEnter", function(self)
						local own = self:GetParent()
						if not (own.item and self.column and grid.opts.cellTooltip) then return end
						GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
						grid.opts.cellTooltip(GameTooltip, own.item, self.column)
						GameTooltip:Show()
					end)
					cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
					cell:SetScript("OnClick", function(self, button)
						local own = self:GetParent()
						if grid.opts.onClick and own.item then grid.opts.onClick(own.item, button, own, self.column) end
					end)
					cell:RegisterForClicks("LeftButtonUp", "RightButtonUp")
					row.cells[index] = cell
				end
				cell.column = column
				if column then
					cell:ClearAllPoints()
					cell:SetPoint("LEFT", row, "LEFT", x + 2, 0)
					cell:SetWidth((column.width or CELL_WIDTH) - 4)
					cell.text:SetText(item.cells and item.cells[index] or "")
					x = x + (column.width or CELL_WIDTH)
					cell:Show()
				else
					cell:Hide()
				end
			end
		end,
	})
	grid.list:SetPoint("TOPLEFT", grid.header, "BOTTOMLEFT", 0, -2)
	grid.list:SetPoint("BOTTOMRIGHT")
	-- columns: { { title, tip, width } }; rows: { { label, cells = { text }, ... } }
	function grid:SetColumns(nameTitle, columns)
		self.nameHead:SetText(nameTitle or "")
		self.columns = columns or {}
		local x = self.opts.nameWidth or NAME_WIDTH
		for index = 1, math.max(#self.heads, #self.columns) do
			local head = self.heads[index]
			local column = self.columns[index]
			if not head then
				head = CreateFrame("Frame", nil, self.header)
				head:SetHeight(20)
				head.text = Kit.Text(head, 11, "CENTER", "secondary")
				head.text:SetAllPoints()
				head.text:SetWordWrap(false)
				self.heads[index] = head
			end
			if column then
				head:ClearAllPoints()
				head:SetPoint("LEFT", self.header, "LEFT", x + 2, 0)
				head:SetWidth((column.width or CELL_WIDTH) - 4)
				head.text:SetText(column.title or "")
				Kit.Tooltip(head, column.tipTitle or column.title, column.tip)
				x = x + (column.width or CELL_WIDTH)
				head:Show()
			else
				head:Hide()
			end
		end
	end
	function grid:SetRows(rows)
		self.list:SetData(rows or {})
	end
	return grid
end

---------------------------------------------------------------------------
-- The page
---------------------------------------------------------------------------
local Page = {}

function Page:Select(key, stepId)
	local s = State()
	if not A:Get(key) then return end
	if s.selected ~= key then
		s.step = nil
		self.chart:Reset()
	end
	s.selected = key
	s.mode = "entry"
	if stepId then s.step = stepId end
	self:Draw()
	if stepId and self.chart:IsShown() then self.chart:ShowStep(stepId) end
end

-- The host the chain views talk to.
function Page:Selected()
	return State().step
end

function Page:OnStep(step, button, owner)
	local s = State()
	local key = s.selected
	if button == "RightButton" then
		self:StepMenu(owner, key, step)
		return
	end
	if IsShiftKeyDown() and (step.kind == "item" or step.kind == "goal") then
		local _, link = C_Item.GetItemInfo(step.ref)
		if type(link) == "string" and not A.Secret(link) then Kit.InsertLink(link) end
		return
	end
	if step.kind == "link" and A:Get(step.ref) then
		self:Select(step.ref)
		return
	end
	s.step = step.id
	self:DrawBody()
	self:DrawDetail()
end

function Page:StepMenu(owner, key, step)
	local place = A:StepPlace(step)
	local quest = step.quest and LG:Quest(step.quest)
	local entry = A:Get(key)
	local instance = quest and quest.instance and LG:InstanceInfo(quest.instance) and quest.instance
		or (entry and entry.instance and LG:InstanceInfo(entry.instance) and entry.instance)
	E.UIKit.ContextMenu(owner, function(_, root)
		root:CreateTitle(A:StepTitle(step))
		if place then
			root:CreateButton(L["Show on the map"], function() LG:CycleCamps(place.kind, place.id, place.name) end)
		end
		if instance then
			root:CreateButton(L["Open in the Journal"], function()
				LG:Open("journal", step.quest and { key = instance, quest = step.quest } or instance)
			end)
		end
		if step.kind == "item" or step.kind == "goal" then
			root:CreateButton(L["Link in chat"], function()
				local _, link = C_Item.GetItemInfo(step.ref)
				if type(link) == "string" and not A.Secret(link) then Kit.InsertLink(link) end
			end)
		end
		if A.GuildOnStep then
			local names = A:GuildOnStep(key, step)
			if #names > 0 then
				root:CreateButton((L["Guild on this step (%d)"]):format(#names), function() self:ShowGuildOnStep(key, step) end)
			end
		end
	end)
end

function Page:ShowGuildOnStep(key, step)
	local names = A.GuildOnStep and A:GuildOnStep(key, step) or {}
	local list = {}
	for index, row in ipairs(names) do list[index] = row.name end
	E:ShowCopyBox((L["Guild on this step (%d)"]):format(#names), A:StepTitle(step), table.concat(list, "\n"))
end

-- Where a step is, as "Name, Zone".
local function PlaceText(place)
	if not place then return end
	local zone = place.zone or (place.uiMapID and LG:MapName(place.uiMapID))
	if place.instance then zone = LG:InstanceName(place.instance) or zone end
	return zone and ("%s, %s"):format(place.name or "?", zone) or place.name
end
A.PlaceText = PlaceText

local KIND_TITLE = {
	pickup = Key("Quest"), quest = Key("Quest"), turnin = Key("Turn-in"), item = Key("Item"), goal = Key("Item"), kill = Key("Defeat"),
	drop = Key("Boss drop"), interact = Key("Use"), rep = Key("Reputation"), level = Key("Level"), link = Key("Attunement"),
	["end"] = Key("Goal"),
}

function Page:StepTooltip(tooltip, step, key)
	key = key or State().selected
	local state = A:StepState(key, step.id) or "unknown"
	local sr, sg, sb = unpack(E.tokens.text.secondary)
	E.UIKit.TipTitle(tooltip, A:StepTitle(step))
	local bits = { E:Translate(KIND_TITLE[step.kind]) or "" }
	local quest = step.quest and LG:Quest(step.quest)
	if quest and quest.level and quest.level > 0 then
		local r, g, b = Kit.LevelColor(quest.level)
		bits[#bits + 1] = Kit.Hex(r, g, b) .. (L["Lvl %d"]):format(quest.level) .. "|r"
	end
	if quest then bits[#bits + 1] = A:SizeColored(quest.suggested) end
	tooltip:AddLine(table.concat(bits, "  ·  "), sr, sg, sb)
	local r, g, b = A:StateColor(state)
	tooltip:AddLine(A.STATE_TITLE[state] or state, r, g, b)
	if quest and (step.kind == "pickup" or step.kind == "quest") then
		local objectives = LG:QuestObjectives(step.quest)
		for index, row in ipairs(objectives.rows) do
			if index > 3 then break end
			if row.text then E.UIKit.TipTitle(tooltip, row.text, true) end
		end
	end
	local place = A:StepPlace(step)
	if place then
		local label = step.kind == "turnin" and L["Ends at %s"] or (step.kind == "kill" or step.kind == "drop" or step.kind == "interact" or step.kind == "item" or step.kind == "goal") and L["At %s"] or L["Starts at %s"]
		tooltip:AddLine(label:format(PlaceText(place)), sr, sg, sb, true)
	end
	-- Your other characters on this step.
	local store = E.Characters
	if store and store:Full() and step.kind ~= "end" then
		local lines = 0
		for _, charKey in ipairs(store:Keys("account")) do
			if charKey ~= E.charKey and lines < 6 then
				local other = A:StepState(key, step.id, charKey)
				if other == "done" or other == "active" or other == "turnin" then
					if lines == 0 then tooltip:AddLine(" ") tooltip:AddLine(L["Your characters"], sr, sg, sb) end
					local record = store:Get(charKey)
					local mr, mg, mb = A:StateColor(other)
					tooltip:AddDoubleLine(record and record.name or charKey, A.STATE_TITLE[other], 1, 1, 1, mr, mg, mb)
					lines = lines + 1
				end
			end
		end
	end
	if A.GuildOnStep then
		local names = A:GuildOnStep(key, step)
		local max = A.db.guildMaxNames or 10
		if #names > 0 and max > 0 then
			tooltip:AddLine(" ")
			tooltip:AddLine((L["Guild on this step (%d)"]):format(#names), sr, sg, sb)
			for index, row in ipairs(names) do
				if index > max then
					tooltip:AddLine(E:Plural(#names - max, "and %d more", "and %d more"):format(#names - max), sr, sg, sb)
					break
				end
				E.UIKit.TipTitle(tooltip, row.text or row.name)
			end
		end
	end
	tooltip:AddLine(" ")
	if step.kind == "link" then
		E:TooltipHint(tooltip, { L["Click"], L["open that attunement"] })
	else
		E:TooltipHint(tooltip, { L["Click"], L["the details below"] })
	end
	if step.kind == "item" or step.kind == "goal" then E:TooltipHint(tooltip, { L["Shift-click"], L["link the item in chat"] }) end
	E:TooltipHint(tooltip, { L["Right-click"], L["map, Journal and more"] })
end

function Page:EntryTooltip(tooltip, key)
	local entry = A:Get(key)
	local sr, sg, sb = unpack(E.tokens.text.secondary)
	E.UIKit.TipTitle(tooltip, A:Name(entry))
	tooltip:AddLine(E:Translate(A.KIND_TITLE[entry.subKind or entry.kind]) or "", sr, sg, sb)
	if entry.desc then tooltip:AddLine(E:Translate(entry.desc), sr, sg, sb, true) end
	local done, total, percent, state = A:Progress(key)
	if total > 0 then
		local r, g, b = A:StateColor(state)
		tooltip:AddLine(E:Plural(total, "%d of %d step (%d%%)", "%d of %d steps (%d%%)"):format(done, total, percent), r, g, b)
	end
	local nextStep = A:NextSteps(key)[1]
	if nextStep and state ~= "done" then E.UIKit.TipTitle(tooltip, (L["Next: %s"]):format(A:StepTitle(nextStep)), true) end
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------
function Page:DrawLeft()
	local s = State()
	local items = ListItems()
	-- The selection: kept while it is listed, else the first entry.
	local valid = false
	for _, item in ipairs(items) do if item.key == s.selected then valid = true end end
	if not valid then
		s.selected = nil
		for _, item in ipairs(items) do
			if item.key then s.selected = item.key break end
		end
		s.step = nil
	end
	self.left.faction:SetLabel(P.FACTION_TITLE[A.db.showFaction] or P.FACTION_TITLE.mine)
	self.left.list:SetData(items)
	self.items = items
	-- A new selection (from a link, a waypoint or a slash command) or a
	-- longer or shorter list scrolls the list to the selected row; any
	-- other redraw keeps where the list was scrolled.
	if s.selected ~= self.revealed or #items ~= self.revealedCount then
		self.revealed, self.revealedCount = s.selected, #items
		for index, item in ipairs(items) do
			if item.key == s.selected then self.left.list:ScrollTo(index) break end
		end
	end
end

function Page:DrawHeader()
	local s = State()
	local header = self.header
	local entry = s.selected and A:Get(s.selected)
	header:SetShown(s.mode == "entry" and entry ~= nil)
	if not entry or s.mode ~= "entry" then return end
	local art
	if entry.instance and LG:InstanceInfo(entry.instance) then
		art = LG:InstanceArt(entry.instance)
	elseif entry.goalItems and entry.goalItems[1] then
		art = A:StepIcon({ kind = "goal", ref = entry.goalItems[1] })
	else
		art = "Interface\\Icons\\INV_Misc_Key_04"
	end
	header.art.icon:SetTexture(art)
	local name = A:Name(entry)
	local info = entry.instance and LG:InstanceInfo(entry.instance)
	local minLevel, maxLevel = entry.minLevel or (info and info.min), entry.maxLevel or (info and info.max)
	if minLevel and maxLevel then
		name = name .. "  " .. Secondary(minLevel == maxLevel and ("(%d)"):format(minLevel) or ("(%d-%d)"):format(minLevel, maxLevel))
	end
	header.name:SetText(name)
	local bits = { E:Translate(A.KIND_TITLE[entry.subKind or entry.kind]) or "" }
	if entry.instance and info then bits[#bits + 1] = A:SizeColored(EntrySize(entry)) end
	if entry.side then bits[#bits + 1] = P.FACTION_TITLE[entry.side] or entry.side end
	local done, total, percent, state = A:Progress(entry.key)
	if total > 0 then
		local r, g, b = A:StateColor(state == "done" and "done" or state == "active" and "active" or "available")
		bits[#bits + 1] = Kit.Hex(r, g, b) .. E:Plural(total, "%d of %d step (%d%%)", "%d of %d steps (%d%%)"):format(done, total, percent) .. "|r"
	end
	if not entry.forever then bits[#bits + 1] = L["Classic data"] end
	header.sub:SetText(table.concat(bits, "  ·  "))
	header.desc:SetText(A:Desc(entry) or "")
end

function Page:DrawBar()
	local s = State()
	local bar = self.bar
	local entryMode = s.mode == "entry"
	local view = A.db.view
	bar.chain:SetOn(entryMode and view == "chain")
	bar.steps:SetOn(entryMode and view == "list")
	bar.overview:SetOn(s.mode == "overview")
	bar.mine:SetShown(s.mode == "overview")
	bar.guild:SetShown(s.mode == "overview")
	bar.mine:SetOn(s.overview == "mine")
	bar.guild:SetOn(s.overview == "guild")
	local zoom = entryMode and view == "chain" and self.chart:IsShown()
	for _, part in ipairs({ bar.zoomOut, bar.zoomIn, bar.percent, bar.fit }) do part:SetShown(zoom) end
	bar.percent:SetText(("%d %%"):format(math.floor(A.PageState().zoom * 100 + 0.5)))
	bar.zoomOut:SetEnabled(A.PageState().zoom > A.ZOOM_MIN + 0.001)
	bar.zoomIn:SetEnabled(A.PageState().zoom < A.ZOOM_MAX - 0.001)
end

-- The body: chain, steps, overview, Forever state, data status or empty.
function Page:DrawBody()
	local s = State()
	local body = self.body
	self.chart:Hide()
	self.steps:Hide()
	self.overview:Hide()
	self.empty:Hide()
	if self.guildView then self.guildView:Hide() end
	if s.mode == "status" then
		self:ShowStatus()
		return
	end
	if s.mode == "overview" then
		if s.overview == "guild" then
			if not self.guildView and A.CreateGuildView then self.guildView = A:CreateGuildView(body, self) end
			if self.guildView then
				self.guildView:Show()
				self.guildView:Draw()
			end
		else
			self.overview:Show()
			self:DrawOverview()
		end
		return
	end
	local entry = s.selected and A:Get(s.selected)
	if not entry or A:NothingToShow(entry) then
		self:ShowEmpty()
		return
	end
	-- A Forever dungeon with no written chain: the quests you recorded for it.
	if A:Unwritten(entry) then
		self.steps:Show()
		self:DrawForever(entry)
		return
	end
	if A.db.view == "list" then
		self.steps:Show()
		local flow = self.steps
		flow:Begin()
		A.ChainView.List(flow, self, entry.key)
		flow:Finish(self.keepScroll)
		self.keepScroll = nil
	else
		self.chart:Show()
		self.chart:Draw(entry.key)
		self.chart:Apply()
	end
end

function Page:DrawForever(entry)
	local flow = self.steps
	flow:Begin()
	local name = A:Name(entry)
	local seen = A:SeenFor(entry)
	P.FlowText(flow, name, 14, nil, 0, 4)
	if not entry.inGame and entry.subKind == "dungeon" then
		P.FlowText(flow, L["The game does not list this dungeon yet. It shows here as soon as it does."], 12, "secondary", 0, 6)
	end
	P.FlowCaption(flow, L["Quests you have taken for it"], tostring(#seen))
	for _, row in ipairs(seen) do
		local q = row.q
		local status = LG:QuestStatus(q)
		local r, g, b = P.QuestStatusColor(status)
		local title = row.record.title or ("#" .. q)
		local where = row.record.map and LG:MapName(row.record.map)
		P.FlowLine(flow, ("%s%s|r  %s%s"):format(Kit.Hex(r, g, b), P.QUEST_GLYPH[status] or "", title, where and ("  " .. Secondary(where)) or ""),
			nil, nil, title, LG.QUEST_STATUS_TITLE[status])
	end
	P.FlowLine(flow, Secondary(A.db.record and L["Forever quests you accept are remembered on this PC."] or L["Remember Forever quests is off."]), nil,
		{ L["Copy the list"], function() A:CopySeen() end, L["Copy the list"],
			L["Opens a copy box with the Forever quests you took, to send to EldoUI's authors so the dungeon can get a full chain."] })
	flow:Finish()
end

function Page:ShowEmpty()
	local empty = self.empty
	local status = LG:DataStatus()
	if not LG:HasData() then
		local text = status == "missing" and L["Install EldoUI_LootData to see quest chains. It holds every quest an attunement needs."]
			or status == "disabled" and L["EldoUI_LootData is switched off in the addon list. Turn it on to see quest chains."]
			or L["The quest chains come from EldoUI_LootData, which loads a few seconds after login."]
		empty:Set(L["No quest chains yet"], text, LG.ICON, {
			{ L["Show data status"], function() State().mode = "status" self:Draw() end, L["Shows what the tab has loaded, here in the window."] },
		})
	elseif #A:List({ all = true }) > 0 then
		local buttons = {}
		if A.db.hideDone then
			buttons[#buttons + 1] = { L["Show finished"], function() A.db.hideDone = false A:Changed() end, L["Turns Hide finished off."] }
		end
		if A.db.showFaction ~= "all" or A.db.showExpansions ~= "all" or A.db.classQuests ~= "all" then
			buttons[#buttons + 1] = { L["Show everything"], function()
				A.db.showFaction, A.db.showExpansions, A.db.classQuests = "all", "all", "all"
				A:Changed()
			end, L["Shows both factions, every class and content the game does not list yet."] }
		end
		empty:Set(L["Nothing matches"], L["Your filters hide every attunement. Show finished attunements?"], LG.ICON, buttons)
	else
		empty:Set(L["No quest chains yet"], L["The tab lists attunements, keys and dungeon quests once the quest data is loaded."], LG.ICON)
	end
	empty:Show()
end

function Page:ShowStatus()
	local empty = self.empty
	empty:Set(L["Attunements data"], L["What the tab has loaded. Chains come from EldoUI_LootData (Classic values; WoW: Forever may differ)."], LG.ICON, {
		{ L["Back"], function() State().mode = "entry" self:Draw() end, L["Goes back to the attunement you had open."] },
	}, A:DataStatusLines())
	empty:Show()
end

-- My characters: one row per character, one column per entry of a group.
function Page:DrawOverview()
	local s = State()
	local view = self.overview
	local store = E.Characters
	local full = store and store:Full()
	view.hint:SetShown(not full)
	view.turnOn:SetShown(not full)
	view.grid:SetShown(full and true or false)
	for key, chip in pairs(view.groups) do chip:SetOn(s.group == key) end
	if not full then
		local module = E.GetModule and E:GetModule("Characters")
		local conflict = module and select(2, E:GetModuleConflict(module))
		view.hint:SetText(conflict and (L["The Alts module stays off while %s is loaded, so only this character is known."]):format(conflict)
			or L["Turn on the Alts module to see the attunements of your other characters here."])
		view.turnOn:SetEnabled(module ~= nil and not conflict)
		view.prev:Hide()
		view.next:Hide()
		view.pageText:SetText("")
		return
	end
	local keys = {}
	for _, key in ipairs(A:MainKeys(true)) do
		if A:Get(key).group == s.group then keys[#keys + 1] = key end
	end
	local pages = math.max(math.ceil(#keys / OVERVIEW_COLUMNS), 1)
	s.columnPage = math.min(math.max(s.columnPage, 1), pages)
	local first = (s.columnPage - 1) * OVERVIEW_COLUMNS + 1
	local columns = {}
	for index = first, math.min(first + OVERVIEW_COLUMNS - 1, #keys) do
		local key = keys[index]
		columns[#columns + 1] = { key = key, title = A:Name(key), tip = A:Desc(key) }
	end
	view.prev:SetShown(pages > 1)
	view.next:SetShown(pages > 1)
	view.prev:SetEnabled(s.columnPage > 1)
	view.next:SetEnabled(s.columnPage < pages)
	view.pageText:SetText(pages > 1 and (L["%d of %d"]):format(s.columnPage, pages) or "")
	view.grid:SetColumns(L["Character"], columns)
	local module = E.modules and E.modules.Characters
	local charKeys = module and module.active and module.Keys and module:Keys() or store:Keys("account")
	local rows = {}
	for _, charKey in ipairs(charKeys) do
		local record = store:Get(charKey)
		if record then
			local label = (module and module.ClassName) and module.ClassName(record) or (record.name or charKey)
			label = label .. "  " .. Secondary(record.level or "?")
			local cells = {}
			for index, column in ipairs(columns) do cells[index] = A:CellText(column.key, charKey, record) end
			rows[#rows + 1] = { label = label, cells = cells, charKey = charKey, record = record }
		end
	end
	view.grid:SetRows(rows)
end

local function OverviewCellTooltip(tooltip, item, column)
	local key = column.key
	local sr, sg, sb = unpack(E.tokens.text.secondary)
	E.UIKit.TipTitle(tooltip, A:Name(key))
	tooltip:AddLine(item.record and item.record.name or item.charKey, sr, sg, sb)
	local done, total, percent, state = A:Progress(key, item.charKey)
	local r, g, b = A:StateColor(state)
	tooltip:AddLine(A.STATE_TITLE[state] or "", r, g, b)
	if total > 0 then E.UIKit.TipTitle(tooltip, E:Plural(total, "%d of %d step (%d%%)", "%d of %d steps (%d%%)"):format(done, total, percent)) end
	local nextStep = A:NextSteps(key, item.charKey)[1]
	if nextStep and state ~= "done" then E.UIKit.TipTitle(tooltip, (L["Next: %s"]):format(A:StepTitle(nextStep)), true) end
	if item.charKey ~= E.charKey then tooltip:AddLine(L["As of that character's last login."], sr, sg, sb, true) end
	tooltip:AddLine(" ")
	E:TooltipHint(tooltip, { L["Click"], L["open this attunement"] })
end

-- The step on show below the chart.
function Page:DrawDetail()
	local s = State()
	local entry = s.mode == "entry" and s.selected and A:Get(s.selected)
	local step = entry and s.step and entry.steps.byId[s.step] or nil
	if entry and s.step and not step then
		for _, other in ipairs(entry and entry.steps.sideList or {}) do
			if other.id == s.step then step = other end
		end
	end
	local detail = self.detail
	local shown = step ~= nil
	detail:SetShown(shown)
	self.body:ClearAllPoints()
	self.body:SetPoint("TOPLEFT", self.right, "TOPLEFT", 0, -(BAR + 6 + (self.header:IsShown() and HEADER or 0)))
	self.body:SetPoint("BOTTOMRIGHT", self.right, "BOTTOMRIGHT", 0, shown and (DETAIL_HEIGHT + 8) or 0)
	if not shown then return end
	detail.title:SetText(A:StepTitle(step))
	local quest = step.quest and LG:Quest(step.quest)
	if quest then
		detail.flow:Hide()
		detail.quest:Show()
		detail.quest:SetQuest(step.quest)
		return
	end
	detail.quest:Hide()
	detail.flow:Show()
	local flow = detail.flow
	flow:Begin()
	local state = A:StepState(entry.key, step.id) or "unknown"
	local r, g, b = A:StateColor(state)
	P.FlowText(flow, Kit.Hex(r, g, b) .. (A.STATE_TITLE[state] or state) .. "|r", 12, nil, 0, 4)
	local caption = A.StateCaption(step, state, entry.key)
	if caption and caption ~= "" then P.FlowText(flow, caption, 12, "secondary", 0, 4) end
	if step.kind == "rep" then
		P.FlowText(flow, (L["Reputation with %s: %s or better."]):format(A.FactionName(step.ref), A.StandingName(step.standing)), 12, nil, 0, 4)
	elseif step.kind == "drop" then
		local mob = LG:Mob(step.ref)
		P.FlowText(flow, (L["%s drops %s. Your bags count it as soon as you loot it."]):format(mob and mob.name or "?", A.ItemName(step.item)), 12, nil, 0, 4)
	elseif step.kind == "goal" then
		P.FlowText(flow, L["In your bags or bank. The step is done as soon as you have it."], 12, "secondary", 0, 4)
		P.FlowItem(flow, { itemID = step.ref, onClick = function() P.OpenItem(step.ref) end })
	elseif step.kind == "link" then
		local linked = step.ref
		P.FlowLine(flow, A:Name(linked), function() self:Select(linked) end, { L["Open"], function() self:Select(linked) end,
			L["Open"], L["Shows that attunement."] })
	end
	local place = A:StepPlace(step)
	if place then
		P.FlowLine(flow, Secondary(L["Where"]) .. "  " .. (PlaceText(place) or ""), nil, P.MapButton(place.kind, place.id, place.name))
	end
	if entry.instance and LG:InstanceInfo(entry.instance) then
		local instance = entry.instance
		P.FlowLine(flow, Secondary(L["Instance"]) .. "  " .. (LG:InstanceName(instance) or instance), nil,
			{ L["Journal"], function() LG:Open("journal", instance) end, L["Journal"], L["Opens the instance in the Journal: bosses, loot and its quests."] })
	end
	flow:Finish()
end

function Page:Draw()
	if not self:IsVisible() then
		self.stale = true
		return
	end
	self.stale = nil
	self:DrawLeft()
	self:DrawHeader()
	self:DrawBar()
	self:DrawDetail()
	self:DrawBody()
	self:DrawBar()
end

---------------------------------------------------------------------------
-- Building
---------------------------------------------------------------------------
local function BuildLeft(page)
	local left = CreateFrame("Frame", nil, page)
	left:SetPoint("TOPLEFT")
	left:SetPoint("BOTTOMLEFT")
	left:SetWidth(LEFT_WIDTH)
	page.left = left
	left.faction = P.Toggle(left, P.FACTION_TITLE.mine, function(self)
		P.FactionMenu(self, A.db.showFaction, function(key)
			A.db.showFaction = key
			A:Changed()
			if E.RefreshConfig then E:RefreshConfig() end
		end)
	end, L["Show steps for"], L["Which faction's steps the chains show (the same as the setting). Steps for both factions always show."])
	left.faction:SetPoint("TOPLEFT")
	left.list = Kit.CreateList(left, { create = RowCreate, update = RowUpdate, gap = 1 })
	left.list.page = page
	left.list:SetPoint("TOPLEFT", 0, -(BAR + 6))
	left.list:SetPoint("BOTTOMRIGHT")
end

local function BuildBar(page, right)
	local bar = CreateFrame("Frame", nil, right)
	bar:SetPoint("TOPLEFT")
	bar:SetPoint("TOPRIGHT")
	bar:SetHeight(BAR)
	page.bar = bar
	local function View(view)
		return function()
			A.db.view = view
			State().mode = "entry"
			page:Draw()
			if E.RefreshConfig then E:RefreshConfig() end
		end
	end
	bar.chain = P.Toggle(bar, L["Flowchart"], View("chain"), L["Flowchart"], L["The chain as a chart: every step a box, lines to the steps that need it."])
	bar.chain:SetPoint("LEFT", 0, 0)
	bar.steps = P.Toggle(bar, L["Step list"], View("list"), L["Step list"], L["One step per row, in order. Easier to read at a small window scale."])
	bar.steps:SetPoint("LEFT", bar.chain, "RIGHT", 4, 0)
	bar.overview = P.Toggle(bar, L["Overview"], function()
		local s = State()
		s.mode = s.mode == "overview" and "entry" or "overview"
		page:Draw()
	end, L["Overview"], L["Who is attuned: your characters, or guild and group members who shared theirs."])
	bar.overview:SetPoint("LEFT", bar.steps, "RIGHT", 12, 0)
	bar.mine = P.Toggle(bar, L["My characters"], function()
		State().overview = "mine"
		page:Draw()
	end, L["My characters"], L["Your characters and how far each one is (Alts module)."])
	bar.mine:SetPoint("LEFT", bar.overview, "RIGHT", 4, 0)
	bar.guild = P.Toggle(bar, L["Guild"], function()
		State().overview = "guild"
		page:Draw()
	end, L["Guild"], L["Guild and group members who sent their attunements. Nothing is sent without a click."])
	bar.guild:SetPoint("LEFT", bar.mine, "RIGHT", 4, 0)
	bar.fit = Kit.Button(bar, L["Fit"], 44, BAR, function()
		page.chart:Fit()
		page:DrawBar()
	end, L["Fit"], L["Zooms so the whole chain fits the window."])
	bar.fit:SetPoint("RIGHT", 0, 0)
	bar.zoomIn = Kit.IconButton(bar, BAR, nil, function()
		page.chart:SetZoom(A.PageState().zoom + 0.1)
		page:DrawBar()
	end, L["Zoom in"], L["Ctrl+mouse wheel zooms too (60 to 150 %)."], "+")
	bar.zoomIn:SetPoint("RIGHT", bar.fit, "LEFT", -4, 0)
	bar.percent = Kit.Text(bar, 11, "CENTER", "secondary")
	bar.percent:SetWidth(44)
	bar.percent:SetPoint("RIGHT", bar.zoomIn, "LEFT", -2, 0)
	bar.zoomOut = Kit.IconButton(bar, BAR, nil, function()
		page.chart:SetZoom(A.PageState().zoom - 0.1)
		page:DrawBar()
	end, L["Zoom out"], L["Ctrl+mouse wheel zooms too (60 to 150 %)."], "-")
	bar.zoomOut:SetPoint("RIGHT", bar.percent, "LEFT", -2, 0)
end

local function BuildHeader(page, right)
	local header = CreateFrame("Frame", nil, right)
	header:SetPoint("TOPLEFT", 0, -(BAR + 6))
	header:SetPoint("TOPRIGHT", 0, -(BAR + 6))
	header:SetHeight(HEADER)
	page.header = header
	header.art = P.Art(header, 40)
	header.art:SetPoint("TOPLEFT", 0, 0)
	header.name = Kit.Text(header, 16, "LEFT")
	header.name:SetPoint("TOPLEFT", header.art, "TOPRIGHT", 10, -1)
	header.name:SetPoint("TOPRIGHT", 0, -1)
	header.name:SetWordWrap(false)
	header.sub = Kit.Text(header, 11, "LEFT", "secondary")
	header.sub:SetPoint("TOPLEFT", header.name, "BOTTOMLEFT", 0, -4)
	header.sub:SetPoint("TOPRIGHT", header.name, "BOTTOMRIGHT", 0, -4)
	header.sub:SetWordWrap(false)
	header.desc = Kit.Text(header, 11, "LEFT", "secondary")
	header.desc:SetPoint("TOPLEFT", header.art, "BOTTOMLEFT", 0, -4)
	header.desc:SetPoint("TOPRIGHT", 0, -(40 + 4)) -- under the 40 px art
	header.desc:SetWordWrap(false)
	header.rule = Kit.Divider(header)
	header.rule:SetPoint("BOTTOMLEFT", 0, 2)
	header.rule:SetPoint("BOTTOMRIGHT", 0, 2)
end

local function BuildOverview(page, body)
	local view = CreateFrame("Frame", nil, body)
	view:SetAllPoints()
	view:Hide()
	page.overview = view
	view.groups = {}
	local anchor
	for _, group in ipairs({ { "raids", L["Raids"] }, { "keys", L["Keys"] }, { "misc", L["Other chains"] } }) do
		local key = group[1]
		local chip = P.Toggle(view, group[2], function()
			local s = State()
			s.group, s.columnPage = key, 1
			page:DrawOverview()
		end, group[2], L["Which attunements the columns show."])
		if anchor then chip:SetPoint("LEFT", anchor, "RIGHT", 4, 0) else chip:SetPoint("TOPLEFT", 0, 0) end
		anchor = chip
		view.groups[key] = chip
	end
	-- Pager arrows: the kit chevrons in a flat box.
	local function Arrow(dir, onClick, title, tip)
		local button = E.UIKit.IconButton(view, 18, "chevron-" .. dir, onClick, title, tip)
		button:SetSize(24, 18)
		E:SetTemplate(button, true)
		return button
	end
	view.next = Arrow("right", function()
		State().columnPage = State().columnPage + 1
		page:DrawOverview()
	end, L["More attunements"], L["Shows the next attunements as columns."])
	view.next:SetPoint("TOPRIGHT", 0, 0)
	view.pageText = Kit.Text(view, 11, "CENTER", "secondary")
	view.pageText:SetWidth(60)
	view.pageText:SetPoint("RIGHT", view.next, "LEFT", -4, 0)
	view.prev = Arrow("left", function()
		State().columnPage = State().columnPage - 1
		page:DrawOverview()
	end, L["Earlier attunements"], L["Shows the attunements before these as columns."])
	view.prev:SetPoint("RIGHT", view.pageText, "LEFT", -4, 0)
	view.grid = A.CreateGrid(view, {
		cellTooltip = OverviewCellTooltip,
		onClick = function(_, _, _, column)
			if column and column.key then page:Select(column.key) end
		end,
	})
	view.grid:SetPoint("TOPLEFT", 0, -26)
	view.grid:SetPoint("BOTTOMRIGHT")
	view.hint = Kit.Text(view, 12, "LEFT", "secondary")
	view.hint:SetPoint("TOPLEFT", 0, -32)
	view.hint:SetPoint("TOPRIGHT", 0, -32)
	view.hint:SetWordWrap(true)
	view.turnOn = Kit.Button(view, L["Turn on Alts"], 150, 22, function()
		E:SetModuleEnabled("Characters", true)
		C_Timer.After(0.2, function() page:Draw() end)
	end, L["Turn on Alts"], L["Switches the Alts module on. Each character is added the next time you log in on it."])
	view.turnOn:SetPoint("TOPLEFT", view.hint, "BOTTOMLEFT", 0, -10)
end

local function BuildDetail(page, right)
	local detail = CreateFrame("Frame", nil, right)
	detail:SetPoint("BOTTOMLEFT")
	detail:SetPoint("BOTTOMRIGHT")
	detail:SetHeight(DETAIL_HEIGHT)
	detail:Hide()
	page.detail = detail
	local rule = Kit.Divider(detail)
	rule:SetPoint("TOPLEFT")
	rule:SetPoint("TOPRIGHT")
	detail.title = Kit.Text(detail, 10, "LEFT", "header")
	detail.title:SetPoint("TOPLEFT", 0, -6)
	detail.title:SetPoint("TOPRIGHT", -24, -6)
	detail.title:SetWordWrap(false)
	detail.close = Kit.IconButton(detail, 18, nil, function()
		State().step = nil
		page:Draw()
	end, L["Close"], L["Hides the step details."], "cross")
	detail.close:SetPoint("TOPRIGHT", 0, -2)
	detail.quest = P.QuestDetail(detail)
	detail.quest.inAttunements = true
	detail.quest:SetPoint("TOPLEFT", 0, -22)
	detail.quest:SetPoint("BOTTOMRIGHT")
	detail.quest.onOpen = function(questID)
		-- A quest of the same chain: select its step; else the Journal.
		local key = State().selected
		for _, hit in ipairs(A:ForQuest(questID)) do
			if hit.key == key then
				page:Select(key, hit.step.id)
				return
			end
		end
		local quest = LG:Quest(questID)
		if quest and quest.instance and LG:InstanceInfo(quest.instance) then
			LG:Open("journal", { key = quest.instance, quest = questID })
		else
			detail.quest:SetQuest(questID)
		end
	end
	detail.flow = P.Flow(detail)
	detail.flow:SetPoint("TOPLEFT", 0, -22)
	detail.flow:SetPoint("BOTTOMRIGHT")
end

local function Create(parent)
	local page = CreateFrame("Frame", nil, parent)
	page:SetAllPoints()
	for name, fn in pairs(Page) do page[name] = fn end
	BuildLeft(page)
	local right = CreateFrame("Frame", nil, page)
	right:SetPoint("TOPLEFT", page.left, "TOPRIGHT", 12, 0)
	right:SetPoint("BOTTOMRIGHT")
	page.right = right
	BuildBar(page, right)
	BuildHeader(page, right)
	page.body = CreateFrame("Frame", nil, right)
	page.body:SetPoint("TOPLEFT", 0, -(BAR + 6 + HEADER))
	page.body:SetPoint("BOTTOMRIGHT")
	page.chart = A.ChainView.Create(page.body, page)
	page.chart:SetAllPoints()
	page.chart:Hide()
	page.chart.onZoom = function() if page.bar then page:DrawBar() end end
	page.steps = P.Flow(page.body)
	page.steps:SetAllPoints()
	page.steps:Hide()
	BuildOverview(page, page.body)
	page.empty = Kit.EmptyState(page.body)
	page.empty:Hide()
	BuildDetail(page, right)
	page:SetScript("OnShow", function(self) if self.stale then self:Draw() end end)
	A.pageFrame = page
	return page
end

-- arg: an entry key or a name, "overview", "guild", "status", or
-- { key, step } (a step of an entry).
local function Show(page, arg)
	local s = State()
	if type(arg) == "table" and arg.key and A:Get(arg.key) then
		s.mode = "entry"
		if s.selected ~= arg.key then page.chart:Reset() end
		s.selected, s.step = arg.key, arg.step
	elseif arg == "overview" or arg == "guild" or arg == "mine" then
		s.mode = "overview"
		if arg ~= "overview" then s.overview = arg end
	elseif arg == "status" then
		s.mode = "status"
	elseif type(arg) == "string" then
		local key = A:Get(arg) and arg or A:Find(arg)
		if key then
			s.mode = "entry"
			if s.selected ~= key then
				page.chart:Reset()
				s.step = nil
			end
			s.selected = key
		end
	end
	page:Draw()
	if s.step and page.chart:IsShown() then page.chart:ShowStep(s.step) end
end

local function Refresh(page, changed)
	if changed.attune or changed.data or changed.settings or changed.player or changed.quests or changed.attunePeers then
		page.keepScroll = true
		page:Draw()
	end
end

-- Settings changed from the tab itself (filters, view): one redraw.
function A:Changed()
	self:ClearProgress()
	self:MarkDirty("all")
	LG:Fire("attune")
	if self.pageFrame then self.pageFrame:Draw() end
end

local PAGE = {
	title = "Attunements",
	desc = "Attunements, keys and dungeon quest chains: every step, what you have done and what comes next.",
	order = 25,
	create = Create,
	show = Show,
	refresh = Refresh,
	count = function() return A:InProgressCount() end,
	alias = function(text) return A:Find(text) end,
}
A.PAGE = PAGE

local lastCount
function A:StartPage()
	if LG:GetPage("attune") ~= PAGE then LG:RegisterPage("attune", PAGE) end
	lastCount = nil
	-- The tab's number: the window lays tabs out again on "pages".
	LG:On("attunepage", function(changed)
		if not (changed.attune or changed.settings or changed.data) then return end
		local count = A:InProgressCount()
		if count ~= lastCount then
			local first = lastCount == nil
			lastCount = count
			if not first then LG:Fire("pages") end
		end
	end)
end

function A:StopPage()
	LG:Off("attunepage")
	if LG:GetPage("attune") then LG:UnregisterPage("attune") end
	if self.pageFrame then self.pageFrame:Hide() end
end
