-- EldoUI Attunements: the chain views of the tab.
--
--   A:LayoutChain(graph, visible)  positions of the shown steps: layers top
--                                  to bottom by longest path, centered, the
--                                  order inside a layer by the parents above
--   A.ChainView.Create(parent, host[, source])  the flowchart: nodes, edges
--                                  with right-angle bends, side box, pan by
--                                  drag, a scroll bar when the chain is taller
--                                  than the view, wheel scrolls, Shift+wheel
--                                  scrolls sideways, Ctrl+wheel zooms 60-150 %
--   A.ChainView.List(flow, host, key)  the same steps as rows in a P.Flow
--
-- host: OnStep(step, mouseButton), StepTooltip(tooltip, step), Selected().
-- source: what the chart draws, the attunement steps unless given (the
-- Journal's quest chains bring their own; see ChainView.ATTUNE).
-- Frames are pooled in Lua tables (no global names). Nothing here acts on
-- the game: a click selects, opens the map pin menu or the Journal.
local _, E = ...
local LG = E.LootGuide
local Kit = LG.Kit
local P = LG.PageKit
local L = E.L
local A = E:GetModule("Attunements")

local NODE_W, NODE_H = 180, 36
local LAYER_STEP = 56            -- top of one layer to the top of the next
local COL_GAP = 16
local PAD = 12
local SIDE_W, SIDE_ROW = 200, 26
local ZOOM_MIN, ZOOM_MAX, ZOOM_STEP = 0.6, 1.5, 0.1
local WHEEL_STEP = 40
-- Pan limits: the chain may move this far past the view's top and bottom.
local TOP_ROOM, BOTTOM_ROOM = 8, 40
A.ZOOM_MIN, A.ZOOM_MAX = ZOOM_MIN, ZOOM_MAX
A.NODE_W, A.NODE_H = NODE_W, NODE_H

local function Clamp(value, low, high)
	return math.max(low, math.min(high, value))
end

local function UI()
	local ui = LG:UI()
	if type(ui.attune) ~= "table" then ui.attune = {} end
	local s = ui.attune
	s.zoom = Clamp(tonumber(s.zoom) or 1, ZOOM_MIN, ZOOM_MAX)
	return s
end
A.PageState = UI

---------------------------------------------------------------------------
-- Which steps show: steps for both sides always; one side's steps by the
-- "Show steps for" setting (your faction, Alliance, Horde or both).
---------------------------------------------------------------------------
function A:StepVisible(step)
	if not step.faction then return true end
	local filter = self.db and self.db.showFaction or "mine"
	if filter == "all" then return true end
	if filter == "mine" then filter = LG:Player().faction or step.faction end
	return step.faction == filter
end

---------------------------------------------------------------------------
-- Layout
---------------------------------------------------------------------------
function A:LayoutChain(graph, visible)
	visible = visible or function(step) return A:StepVisible(step) end
	local layers, layerKeys = {}, {}
	for _, step in ipairs(graph.list) do
		if visible(step) then
			if not layers[step.layer] then
				layers[step.layer] = {}
				layerKeys[#layerKeys + 1] = step.layer
			end
			table.insert(layers[step.layer], step)
		end
	end
	table.sort(layerKeys)
	local pos, width = {}, 0
	for _, key in ipairs(layerKeys) do
		local n = #layers[key]
		width = math.max(width, n * NODE_W + (n - 1) * COL_GAP)
	end
	width = width + 2 * PAD
	for row, key in ipairs(layerKeys) do
		local list = layers[key]
		-- Under the parents: the mean x of the shown steps each one follows.
		local weight = {}
		for _, step in ipairs(list) do
			local sum, n = 0, 0
			for _, f in ipairs(step.follows) do
				if pos[f] then
					sum, n = sum + pos[f].x, n + 1
				end
			end
			weight[step.id] = n > 0 and sum / n or nil
		end
		table.sort(list, function(a, b)
			local wa, wb = weight[a.id], weight[b.id]
			if wa and wb and wa ~= wb then return wa < wb end
			if (wa ~= nil) ~= (wb ~= nil) then return wa ~= nil end
			return a.index < b.index
		end)
		local n = #list
		local left = (width - (n * NODE_W + (n - 1) * COL_GAP)) / 2
		for column, step in ipairs(list) do
			pos[step.id] = { x = math.floor(left + (column - 1) * (NODE_W + COL_GAP) + 0.5), y = PAD + (row - 1) * LAYER_STEP,
				row = row, column = column }
		end
	end
	local height = PAD * 2 + math.max(#layerKeys, 1) * LAYER_STEP - (LAYER_STEP - NODE_H)
	local side
	local sideSteps = {}
	for _, step in ipairs(graph.sideList) do
		if visible(step) then sideSteps[#sideSteps + 1] = step end
	end
	if #sideSteps > 0 then
		local boxHeight = 22 + #sideSteps * SIDE_ROW + 6
		local anchor = pos["end"] or nil
		local top = anchor and math.max(PAD, anchor.y + NODE_H - boxHeight) or PAD
		side = { x = width + 12, y = top, w = SIDE_W, h = boxHeight, steps = sideSteps }
		width = width + 12 + SIDE_W + PAD
		height = math.max(height, top + boxHeight + PAD)
	end
	return { pos = pos, width = width, height = height, side = side, rows = #layerKeys }
end

---------------------------------------------------------------------------
-- Looks per kind and state
---------------------------------------------------------------------------
local KIND_ICON = {
	level = "Interface\\Icons\\INV_Misc_PocketWatch_01",
	rep = "Interface\\Icons\\INV_Misc_Ribbon_01",
	link = "Interface\\Icons\\INV_Misc_Key_04",
	kill = "Interface\\Icons\\INV_Sword_04",
	drop = "Interface\\Icons\\INV_Sword_04",
	interact = "Interface\\Icons\\INV_Misc_Gear_01",
	pickup = "Interface\\GossipFrame\\AvailableQuestIcon",
	quest = "Interface\\GossipFrame\\AvailableQuestIcon",
	turnin = "Interface\\GossipFrame\\ActiveQuestIcon",
}
local QUEST_GLYPHS = { pickup = true, quest = true, turnin = true }
local CHECK_ATLAS = "common-icon-checkmark"

function A:StepIcon(step)
	local kind = step.kind
	if kind == "item" or kind == "goal" then
		local icon = C_Item and C_Item.GetItemIconByID and A.Plain(select(2, pcall(C_Item.GetItemIconByID, step.ref)))
		if type(icon) ~= "number" and type(icon) ~= "string" then
			local record = LG:ItemRecord(step.ref)
			icon = record and record.icon
		end
		return E:ClientIcon(icon, "Interface\\Icons\\INV_Misc_QuestionMark"), false
	end
	if kind == "end" then
		local entry = self:Get(step.ref)
		if entry and entry.instance and LG:InstanceInfo(entry.instance) then return LG:InstanceArt(entry.instance), false end
		return "Interface\\Icons\\INV_Misc_Key_04", false
	end
	return KIND_ICON[kind] or "Interface\\Icons\\INV_Misc_QuestionMark", QUEST_GLYPHS[kind] or false
end

-- r, g, b of a state's caption.
function A:StateColor(state)
	if state == "done" then return unpack(E.tokens.text.good) end
	if state == "active" or state == "turnin" then return Kit.Accent() end
	if state == "available" then return P.QuestStatusColor("available") end
	if state == "low" or state == "locked" or state == "otherfaction" then return unpack(E.tokens.text.dim) end
	return unpack(E.tokens.text.secondary)
end

local FACTION_CREST = { Alliance = "Interface\\FriendsFrame\\PlusManz-Alliance", Horde = "Interface\\FriendsFrame\\PlusManz-Horde" }

-- The caption for a state that says more than the step's own line.
local function StateCaption(step, state, key, charKey)
	if state == "locked" then
		local graph = A:Steps(key)
		for _, f in ipairs(step.follows) do
			local up = graph and graph.byId[f]
			if up and A:StepState(key, f, charKey) ~= "done" and A:StepVisible(up) then
				return (L["After: %s"]):format(A:StepTitle(up))
			end
		end
		return A.STATE_TITLE.locked
	elseif state == "low" then
		local quest = step.quest and LG:Quest(step.quest)
		local level = quest and quest.minLevel or (step.kind == "level" and step.ref)
		if level then
			local r, g, b = Kit.LevelColor(level)
			return Kit.Hex(r, g, b) .. (L["Level %d"]):format(level) .. "|r"
		end
	elseif state == "unknown" then
		return L["Not tracked: marked done when the next step is done"]
	elseif state == "otherfaction" and step.faction then
		return (L["%s only"]):format(P.FACTION_TITLE[step.faction] or step.faction)
	end
	return A:StepCaption(step, charKey, state)
end
A.StateCaption = StateCaption

---------------------------------------------------------------------------
-- A chart's source: where its steps, states and looks come from.
--   Graph(key) -> { list, byId, sideList }, State(key, stepId[, charKey]),
--   Title(step), Icon(step, state) -> icon, plain,
--   Caption(step, state, key[, charKey]), Visible(step),
--   View() -> { zoom }, wheel (false: the wheel scrolls the page around
--   the chart instead of the chart)
---------------------------------------------------------------------------
local ATTUNE = {
	Graph = function(key) return A:Steps(key) end,
	State = function(key, stepId, charKey) return A:StepState(key, stepId, charKey) end,
	Title = function(step) return A:StepTitle(step) end,
	Icon = function(step) return A:StepIcon(step) end,
	Caption = StateCaption,
	Visible = function(step) return A:StepVisible(step) end,
	View = UI,
	wheel = true,
}

---------------------------------------------------------------------------
-- A node (chart) or a row (step list): the same parts.
---------------------------------------------------------------------------
local function CreateNode(parent, height)
	local node = CreateFrame("Button", nil, parent)
	node:SetSize(NODE_W, height or NODE_H)
	node:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	E:SetTemplate(node, true)
	node.select = node:CreateTexture(nil, "BACKGROUND", nil, 1)
	node.select:SetPoint("TOPLEFT", E.pixel, -E.pixel)
	node.select:SetPoint("BOTTOMRIGHT", -E.pixel, E.pixel)
	E:AccentTexture(node.select, E.tokens.pressed)
	node.hover = node:CreateTexture(nil, "HIGHLIGHT")
	node.hover:SetPoint("TOPLEFT", E.pixel, -E.pixel)
	node.hover:SetPoint("BOTTOMRIGHT", -E.pixel, E.pixel)
	node.hover:SetColorTexture(1, 1, 1, E.tokens.hover.row)
	node.bar = node:CreateTexture(nil, "ARTWORK", nil, 2)
	node.bar:SetPoint("TOPLEFT", E.pixel, -E.pixel)
	node.bar:SetPoint("BOTTOMLEFT", E.pixel, E.pixel)
	E:Hairline(node.bar, "w", 2)
	node.icon = node:CreateTexture(nil, "ARTWORK")
	node.icon:SetSize(24, 24)
	node.icon:SetPoint("LEFT", 6, 0)
	node.check = node:CreateTexture(nil, "OVERLAY")
	node.check:SetSize(14, 14)
	node.check:SetPoint("TOPRIGHT", -3, -3)
	if Kit.HasAtlas(CHECK_ATLAS) then node.check:SetAtlas(CHECK_ATLAS) end
	node.glyph = Kit.Text(node, 12, "CENTER")
	node.glyph:SetPoint("CENTER", node.check, "CENTER")
	node.crest = node:CreateTexture(nil, "OVERLAY")
	node.crest:SetSize(12, 12)
	node.crest:SetPoint("BOTTOMRIGHT", -3, 3)
	node.title = Kit.Text(node, 12, "LEFT")
	-- The 24 px icon sits on the node's middle: the lines beside it take
	-- their top and bottom from its edges.
	node.title:SetPoint("TOPLEFT", node.icon, "TOPRIGHT", 6, 1)
	node.title:SetPoint("TOPRIGHT", node, "RIGHT", -18, 12 + 1)
	node.title:SetWordWrap(false)
	node.caption = Kit.Text(node, 11, "LEFT", "secondary")
	node.caption:SetPoint("BOTTOMLEFT", node.icon, "BOTTOMRIGHT", 6, -1)
	node.caption:SetPoint("BOTTOMRIGHT", node, "RIGHT", -6, -12 - 1)
	node.caption:SetWordWrap(false)
	node.rep = E:CreateStatusBar(node)
	node.rep:SetPoint("BOTTOMLEFT", node.icon, "BOTTOMRIGHT", 6, -4)
	node.rep:SetPoint("BOTTOMRIGHT", node, "RIGHT", -8, -12 - 4)
	E:Hairline(node.rep, "h", 3)
	node.rep:SetMinMaxValues(0, 1)
	node.rep:Hide()
	return node
end

-- Fill a node for a step. charKey nil: the character you play.
local function PaintNode(node, key, step, selected, charKey, source)
	source = source or ATTUNE
	local state = source.State(key, step.id, charKey) or "unknown"
	node.step, node.key, node.state = step, key, state
	local icon, plain = source.Icon(step, state)
	node.icon:SetTexture(icon)
	if plain then node.icon:SetTexCoord(0, 1, 0, 1) else E:TrimIcon(node.icon) end
	node.icon:SetDesaturated(state == "otherfaction" or state == "locked")
	node.title:SetText(source.Title(step))
	local caption = source.Caption(step, state, key, charKey)
	node.caption:SetText(caption or "")
	if state == "available" then node.caption:SetTextColor(A:StateColor(state))
	elseif state == "active" or state == "turnin" then node.caption:SetTextColor(E:TokenColor("accent"))
	else Kit.Paint(node.caption, "secondary") end
	-- Left bar and border: done in the good color, open steps in the accent.
	local good = E.tokens.text.good
	if state == "done" then
		node.bar:SetColorTexture(good[1], good[2], good[3], 1)
		node.bar:Show()
		node:SetBackdropBorderColor(unpack(E.media.borderColor))
	elseif state == "active" or state == "turnin" then
		E:AccentTexture(node.bar, 1)
		node.bar:Show()
		node:SetBackdropBorderColor(Kit.Accent())
	elseif state == "unknown" then
		node.bar:Hide()
		node:SetBackdropBorderColor(unpack(E.tokens.text.dim))
	else
		node.bar:Hide()
		node:SetBackdropBorderColor(unpack(E.media.borderColor))
	end
	local hasCheck = state == "done"
	node.check:SetShown(hasCheck and Kit.HasAtlas(CHECK_ATLAS))
	node.glyph:SetShown(hasCheck and not Kit.HasAtlas(CHECK_ATLAS))
	node.glyph:SetText(P.QUEST_GLYPH.done)
	node.glyph:SetTextColor(good[1], good[2], good[3])
	node.crest:SetShown(state == "otherfaction" and FACTION_CREST[step.faction or ""] ~= nil)
	if FACTION_CREST[step.faction or ""] then node.crest:SetTexture(FACTION_CREST[step.faction]) end
	node:SetAlpha((state == "locked" or state == "low" or state == "otherfaction") and E.tokens.disabledAlpha or 1)
	node.select:SetShown(selected and true or false)
	-- Reputation: a thin bar with how far you are in the current standing.
	local repShown = false
	if step.kind == "rep" and state ~= "done" then
		local reader = A:Reader(charKey)
		local value, max = nil, nil
		if reader then value, max = reader:RepValue(step.ref) end
		if value and max and max > 0 then
			node.rep:SetValue(Clamp(value / max, 0, 1))
			node.rep:SetStatusBarColor(Kit.Accent())
			repShown = true
		end
	end
	node.rep:SetShown(repShown)
	node.caption:ClearAllPoints()
	node.caption:SetPoint("BOTTOMLEFT", node.icon, "BOTTOMRIGHT", 6, repShown and 2 or -1)
	node.caption:SetPoint("BOTTOMRIGHT", node, "RIGHT", -6, -12 + (repShown and 2 or -1))
end
A.PaintNode = PaintNode

local function NodeScripts(node, host)
	node:SetScript("OnClick", function(self, button)
		if self.step then host:OnStep(self.step, button, self) end
	end)
	node:SetScript("OnEnter", function(self)
		if not self.step then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		host:StepTooltip(GameTooltip, self.step, self.key)
		GameTooltip:Show()
	end)
	node:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

---------------------------------------------------------------------------
-- The flowchart
---------------------------------------------------------------------------
local Chart = {}

local function Take(pool, used, create)
	local widget = table.remove(pool)
	if not widget then widget = create() end
	used[#used + 1] = widget
	widget:Show()
	return widget
end

local function Release(pool, used)
	for _, widget in ipairs(used) do
		widget:Hide()
		widget:ClearAllPoints()
		pool[#pool + 1] = widget
	end
	wipe(used)
end

function Chart:Line(x, y, w, h, done)
	local line = Take(self.linePool, self.lines, function() return self.canvas:CreateTexture(nil, "BORDER") end)
	line:SetPoint("TOPLEFT", self.canvas, "TOPLEFT", x, -y)
	line:SetSize(math.max(w, E.pixel), math.max(h, E.pixel))
	if done then
		local good = E.tokens.text.good
		line:SetColorTexture(good[1], good[2], good[3], 0.6)
	else
		local edge = E.tokens.edge.window
		line:SetColorTexture(edge[1], edge[2], edge[3], math.max(edge[4] * 2.5, 0.25))
	end
	return line
end

-- One edge: down from the parent, across, down into the child.
function Chart:Edge(from, to, done)
	local px = E.pixel
	local x1, y1 = from.x + NODE_W / 2, from.y + NODE_H
	local x2, y2 = to.x + NODE_W / 2, to.y
	local mid = math.floor((y1 + y2) / 2 + 0.5)
	if math.abs(x1 - x2) < 1 then
		self:Line(x1, y1, px, y2 - y1, done)
	else
		self:Line(x1, y1, px, mid - y1, done)
		self:Line(math.min(x1, x2), mid, math.abs(x2 - x1) + px, px, done)
		self:Line(x2, mid, px, y2 - mid, done)
	end
	local joint = self:Line(x2 - 2 + px / 2, y2 - 4, 4, 4, done)
	return joint
end

function Chart:Draw(key)
	self.key = key
	Release(self.nodePool, self.nodes)
	Release(self.linePool, self.lines)
	Release(self.labelPool, self.labels)
	local source = self.source
	local graph = key and source.Graph(key)
	if not graph then
		self.layout = nil
		self.canvas:SetSize(1, 1)
		return
	end
	local layout = A:LayoutChain(graph, source.Visible)
	self.layout = layout
	self.canvas:SetSize(layout.width, layout.height)
	local selected = self.host:Selected()
	local function Node(step, x, y, height)
		local node = Take(self.nodePool, self.nodes, function()
			local made = CreateNode(self.canvas)
			NodeScripts(made, self.host)
			return made
		end)
		node:SetSize(NODE_W, height or NODE_H)
		node:SetPoint("TOPLEFT", self.canvas, "TOPLEFT", x, -y)
		PaintNode(node, key, step, selected == step.id, nil, source)
		return node
	end
	for _, step in ipairs(graph.list) do
		local at = layout.pos[step.id]
		if at then
			Node(step, at.x, at.y)
			local shown = 0
			for _, f in ipairs(step.follows) do
				if layout.pos[f] then
					shown = shown + 1
					self:Edge(layout.pos[f], at, source.State(key, f) == "done")
				end
			end
			-- An any-of join: "one of these" over the node.
			if step.any and shown > 1 then
				local label = Take(self.labelPool, self.labels, function() return Kit.Text(self.canvas, 10, "LEFT", "secondary") end)
				label:SetPoint("BOTTOMLEFT", self.canvas, "TOPLEFT", at.x + NODE_W / 2 + 6, -(at.y - 1))
				label:SetText(L["one of these"])
			end
		end
	end
	local side = layout.side
	if side then
		local box = self.sideBox
		box:ClearAllPoints()
		box:SetPoint("TOPLEFT", self.canvas, "TOPLEFT", side.x, -side.y)
		box:SetSize(side.w, side.h)
		box:Show()
		for index, step in ipairs(side.steps) do
			local node = Node(step, side.x + 6, side.y + 22 + (index - 1) * SIDE_ROW, SIDE_ROW - 4)
			node:SetWidth(side.w - 12)
			node.caption:SetText("")
		end
	else
		self.sideBox:Hide()
	end
end

-- Pan (viewport units) and zoom.
function Chart:Apply()
	local z = self.source.View().zoom
	local layout = self.layout
	local vw, vh = self.view:GetWidth() or 0, self.view:GetHeight() or 0
	local cw, ch = layout and layout.width * z or 0, layout and layout.height * z or 0
	local x, y = self.panX or 0, self.panY or 0
	if cw <= vw then x = (vw - cw) / 2 else x = Clamp(x, vw - cw - 40, 40) end
	if ch <= vh then y = math.min(math.max(y, 0), math.max(vh - ch, 0)) else y = Clamp(y, vh - ch - BOTTOM_ROOM, TOP_ROOM) end
	self.panX, self.panY = x, y
	self.canvas:SetScale(z)
	self.canvas:ClearAllPoints()
	self.canvas:SetPoint("TOPLEFT", self.view, "TOPLEFT", x / z, y / z)
	self:SyncBar(ch > vh and ch + TOP_ROOM + BOTTOM_ROOM - vh or 0, TOP_ROOM - y)
	if self.onZoom then self.onZoom(z) end
end

-- The scroll bar follows the pan: value 0 is the top of the chain. Shown
-- only while the chain is taller than the view.
function Chart:SyncBar(range, value)
	local bar = self.bar
	if not bar then return end
	local scrolls = range > 0
	bar:SetShown(scrolls)
	if not scrolls then return end
	self.syncing = true
	bar:SetMinMaxValues(0, math.floor(range + 0.5))
	bar:SetValue(Clamp(math.floor(value + 0.5), 0, math.floor(range + 0.5)))
	self.syncing = false
end

-- Wheel: down scrolls down, Shift sideways, Ctrl zooms.
function Chart:Wheel(delta)
	if IsControlKeyDown() then
		self:SetZoom(self.source.View().zoom + delta * ZOOM_STEP)
	elseif IsShiftKeyDown() then
		self.panX = (self.panX or 0) + delta * WHEEL_STEP
		self:Apply()
	else
		self.panY = (self.panY or 0) + delta * WHEEL_STEP
		self:Apply()
	end
end

function Chart:SetZoom(z)
	local s = self.source.View()
	local old = s.zoom
	s.zoom = Clamp(math.floor(z * 10 + 0.5) / 10, ZOOM_MIN, ZOOM_MAX)
	-- Keep the middle of the view in the middle.
	local vw, vh = self.view:GetWidth() or 0, self.view:GetHeight() or 0
	local cx, cy = (vw / 2 - (self.panX or 0)) / old, (vh / 2 - (self.panY or 0)) / old
	self.panX, self.panY = vw / 2 - cx * s.zoom, vh / 2 - cy * s.zoom
	self:Apply()
end

function Chart:Fit()
	local layout = self.layout
	if not layout then return end
	local vw, vh = self.view:GetWidth() or 0, self.view:GetHeight() or 0
	if vw <= 0 or vh <= 0 then return end
	self.source.View().zoom = Clamp(math.floor(math.min(vw / layout.width, vh / layout.height) * 10) / 10, ZOOM_MIN, ZOOM_MAX)
	self.panX, self.panY = 0, 0
	self:Apply()
end

-- New entry: back to the top.
function Chart:Reset()
	self.panX, self.panY = 0, TOP_ROOM
end

-- Scroll so a step's node is in view.
function Chart:ShowStep(stepId)
	local at = self.layout and self.layout.pos[stepId]
	if not at then return end
	local z = self.source.View().zoom
	local vh = self.view:GetHeight() or 0
	local top = (self.panY or 0) + at.y * z
	if top < 0 or top + NODE_H * z > vh then
		self.panY = vh / 2 - (at.y + NODE_H / 2) * z
		self:Apply()
	end
end

-- The node frames on show (tests, tours).
function Chart:Nodes()
	return self.nodes
end

local ChainView = {}
A.ChainView = ChainView
ChainView.ATTUNE = ATTUNE

function ChainView.Create(parent, host, source)
	local chart = CreateFrame("Frame", nil, parent)
	for name, fn in pairs(Chart) do chart[name] = fn end
	chart.host = host
	chart.source = source or ATTUNE
	chart.nodePool, chart.nodes, chart.linePool, chart.lines, chart.labelPool, chart.labels = {}, {}, {}, {}, {}, {}
	chart.view = CreateFrame("Frame", nil, chart)
	chart.view:SetAllPoints()
	chart.view:SetClipsChildren(true)
	chart.view:EnableMouse(true)
	chart.view:EnableMouseWheel(chart.source.wheel ~= false)
	chart.canvas = CreateFrame("Frame", nil, chart.view)
	chart.canvas:SetSize(1, 1)
	chart.canvas:SetPoint("TOPLEFT")
	chart.sideBox = CreateFrame("Frame", nil, chart.canvas)
	E:SetTemplate(chart.sideBox, true)
	chart.sideBox.title = Kit.Text(chart.sideBox, 10, "LEFT", "header")
	chart.sideBox.title:SetPoint("TOPLEFT", 8, -6)
	chart.sideBox.title:SetText(E:CaptionText(L["Inside the dungeon"]))
	chart.sideBox:Hide()
	-- Drag the background to pan.
	chart.view:SetScript("OnMouseDown", function(self, button)
		if button ~= "LeftButton" then return end
		local scale = self:GetEffectiveScale() or 1
		local x, y = GetCursorPosition()
		chart.drag = { x = x / scale, y = y / scale, panX = chart.panX or 0, panY = chart.panY or 0 }
		self:SetScript("OnUpdate", function(own)
			local drag = chart.drag
			if not drag then return end
			local s = own:GetEffectiveScale() or 1
			local cx, cy = GetCursorPosition()
			chart.panX = drag.panX + cx / s - drag.x
			chart.panY = drag.panY - (cy / s - drag.y)
			chart:Apply()
		end)
	end)
	chart.view:SetScript("OnMouseUp", function(self)
		chart.drag = nil
		self:SetScript("OnUpdate", nil)
	end)
	chart.view:SetScript("OnHide", function(self)
		chart.drag = nil
		self:SetScript("OnUpdate", nil)
	end)
	chart.view:SetScript("OnMouseWheel", function(_, delta) chart:Wheel(delta) end)
	-- The kit's scroll bar on the right edge, above the chain.
	chart.bar = E.UIKit.ScrollBar(chart, function(value)
		if chart.syncing then return end
		chart.panY = TOP_ROOM - value
		chart:Apply()
	end)
	chart.bar:SetFrameLevel(chart.view:GetFrameLevel() + 20)
	chart.bar:EnableMouseWheel(chart.source.wheel ~= false)
	chart.bar:SetScript("OnMouseWheel", function(_, delta) chart:Wheel(delta) end)
	chart.bar:Hide()
	chart.view:SetScript("OnSizeChanged", function() chart:Apply() end)
	return chart
end

---------------------------------------------------------------------------
-- The step list: one row per shown step, sub-steps of a quest indented,
-- steps of one layer that run side by side under "Do these in any order".
---------------------------------------------------------------------------
local ROW_H = 34

function ChainView.List(flow, host, key)
	local graph = key and A:Steps(key)
	if not graph then return end
	local selected = host:Selected()
	local lastLayer
	local layerCount = {}
	for _, step in ipairs(graph.list) do
		if A:StepVisible(step) and step.kind ~= "item" and step.kind ~= "kill" and step.kind ~= "interact" then
			layerCount[step.layer] = (layerCount[step.layer] or 0) + 1
		end
	end
	for _, step in ipairs(graph.list) do
		if A:StepVisible(step) then
			local sub = step.kind == "item" or step.kind == "kill" or step.kind == "interact"
			local parallel = not sub and (layerCount[step.layer] or 0) > 1
			if parallel and lastLayer ~= step.layer then
				local any = false
				for _, other in ipairs(graph.list) do
					for _, f in ipairs(other.follows) do
						local up = graph.byId[f]
						if up and up.layer == step.layer and other.any then any = true end
					end
				end
				P.FlowText(flow, any and L["One of these is enough"] or L["Do these in any order"], 10, "secondary", 0, 2)
			end
			if not sub then lastLayer = parallel and step.layer or nil end
			local indent = (sub and 12 or 0) + (parallel and 12 or 0)
			local row = flow:Take("attuneStep", function(child)
				local made = CreateNode(child, ROW_H)
				NodeScripts(made, host)
				return made
			end)
			flow:Place(row, ROW_H, indent, 2)
			PaintNode(row, key, step, selected == step.id)
		end
	end
	if #graph.sideList > 0 then
		local any = false
		for _, step in ipairs(graph.sideList) do
			if A:StepVisible(step) then
				if not any then
					P.FlowCaption(flow, L["Inside the dungeon"], L["not counted"])
					any = true
				end
				local row = flow:Take("attuneStep", function(child)
					local made = CreateNode(child, ROW_H)
					NodeScripts(made, host)
					return made
				end)
				flow:Place(row, ROW_H, 0, 2)
				PaintNode(row, key, step, selected == step.id)
			end
		end
	end
end
