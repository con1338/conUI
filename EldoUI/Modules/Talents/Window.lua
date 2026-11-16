-- EldoUI Talent Planner window: an E.UIKit tabbed window on the
-- EldoUI_TalentPlanner mover.
--
--   Trees  your class's talent trees side by side: your ranks, your plan's
--          ranks in the accent color, the next point with an accent ring,
--          the pick order (which plan point takes a talent first),
--          arrows for prerequisites. Left click adds a rank to the plan,
--          right click removes one, Shift-click links the talent. Under
--          the trees: the level guide (a slider that shows the plan as it
--          stands at any level) and the Learn buttons. Over them: the
--          build bar (BuildBar.lua: category, Recommended build, Import
--          build).
--   Guide  every point of the plan with its level, what you have learned
--          and what comes next.
--   Builds the talent paths EldoUI suggests for the class (Builds.lua),
--          copied into a new plan with one click. Only for a class that
--          has paths.
--   Plans  your plans for each talent group: use, rename, copy, delete,
--          export, import and send.
--
-- The class button picks whose trees you plan: your own class (with your
-- ranks and the Learn buttons) or another class, whose plans are saved for
-- the whole account and are never learned from here.
local _, E = ...
local L = E.L
local P = E.TalentPlan
local M = E.Talents
local Kit = E.UIKit
local B = E.TalentBuilds

local WIDTH, HEIGHT = 860, 560
local CONTENT_W, CONTENT_H = WIDTH - 16, HEIGHT - 70
local MOVER = "EldoUI_TalentPlanner"
local TOP_STRIP, BUILD_ROW, ACTION_BAR, GUIDE_STRIP = 30, 28, 30, 44
local PANEL_GAP, HEADER = 8, 26

local win
local trees      -- the Trees tab frame

function M:ViewGroup()
	if self.viewClass and self:IsOtherClass(self.viewClass) then return self.viewClass end
	local group = self.viewGroup or E:TalentGroup()
	if group > self:NumGroups() then group = 1 end
	return group
end

local function Accent()
	return Kit.Accent()
end

local function Hex(color)
	return Kit.Hex(color[1], color[2], color[3])
end

---------------------------------------------------------------------------
-- What the trees show: live ranks, the plan up to the guide level, the
-- next step.
---------------------------------------------------------------------------
local function Context()
	local group = M:ViewGroup()
	local tree = M:TreeOf(group)
	if not tree then return nil end
	local plan = M:ActivePlan(group)
	local order = plan and plan.order or {}
	local upto = #order
	if M.guideLevel then upto = math.min(upto, P.PointsAt(M.guideLevel)) end
	local next = M:OpenSteps(plan, group)[1]
	return {
		tree = tree, group = group, plan = plan, order = order,
		live = M:LiveState(group), shown = P.Count(tree, order, upto), full = P.Count(tree, order),
		next = next, level = M.guideLevel, upto = upto,
		picks = P.Picks(order, upto), allPicks = P.Picks(order),
	}
end

-- Combined state (live ranks plus the plan's) for "can this rank go in?".
local function Planned(ctx, nodeID)
	return ctx.shown.ranks[nodeID] or 0
end

---------------------------------------------------------------------------
-- Tiles
---------------------------------------------------------------------------
local function TileTooltip(tile)
	local node = tile.node
	local ctx = trees and trees.ctx
	if not (node and ctx) then return end
	-- The talent's own spell tooltip from the game, then the plan lines in
	-- the kit's look.
	Kit.AnchorTooltip(tile)
	local ok = node.spellID and GameTooltip.SetSpellByID and pcall(GameTooltip.SetSpellByID, GameTooltip, node.spellID)
	if not ok then Kit.TipTitle(GameTooltip, node.name) end
	GameTooltip:AddLine(" ")
	local live = ctx.live.ranks[node.id] or 0
	local planned = ctx.full.ranks[node.id] or 0
	Kit.TipPair(GameTooltip, L["You have"], ("%d/%d"):format(live, node.maxRanks))
	Kit.TipPair(GameTooltip, L["Your plan"], ("%d/%d"):format(planned, node.maxRanks), Accent())
	local picks = ctx.allPicks[node.id] or {}
	if #picks > 0 then
		local levels = {}
		for each, index in ipairs(picks) do levels[each] = tostring(P.Level(index)) end
		Kit.TipPair(GameTooltip, L["Plan levels"], table.concat(levels, ", "))
		Kit.TipPair(GameTooltip, E:Plural(#picks, "Pick in the plan", "Picks in the plan"), table.concat(picks, ", "))
	end
	if live > planned then
		GameTooltip:AddLine(L["You have more ranks here than your plan."], Kit.WARN[1], Kit.WARN[2], Kit.WARN[3], true)
	end
	if planned < node.maxRanks then
		local can, reason, detail = P.CanAdd(ctx.tree, ctx.full, node.id, ctx.tree.maxPoints)
		if not can then GameTooltip:AddLine(M:ReasonText(reason, detail, ctx.group), Kit.BAD[1], Kit.BAD[2], Kit.BAD[3], true) end
	end
	GameTooltip:AddLine(" ")
	E:TooltipHint(GameTooltip, { L["Left-click"], L["add a rank"] }, { L["Right-click"], L["remove one"] }, { L["Shift-click"], L["link it"] })
	GameTooltip:Show()
end

local function TileClick(tile, button)
	local node = tile.node
	if not node then return end
	if button == "LeftButton" and IsShiftKeyDown() then
		local link = node.spellID and C_Spell and C_Spell.GetSpellLink and C_Spell.GetSpellLink(node.spellID)
		if link then E:InsertLink(link) end
		return
	end
	local ok, err
	if button == "RightButton" then
		ok, err = M:PlanRemove(node.id, M:ViewGroup())
	else
		ok, err = M:PlanAdd(node.id, M:ViewGroup())
	end
	if not ok and err then M:SetWindowStatus(err, true) end
	if GameTooltip:GetOwner() == tile then C_Timer.After(0, function() if tile:IsMouseOver() then TileTooltip(tile) end end) end
end

-- A badge text with its shape mark in front, when shape marks are on.
local function Marked(kind, text)
	local mark = E:StatusMark(kind)
	return mark ~= "" and (mark .. text) or text
end

local function CreateTile(panel)
	local tile = CreateFrame("Button", nil, panel)
	tile:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	tile:SetFrameLevel(panel:GetFrameLevel() + 3)
	E:SetTemplate(tile)
	tile.icon = tile:CreateTexture(nil, "ARTWORK")
	tile.icon:SetPoint("TOPLEFT", E.pixel, -E.pixel)
	tile.icon:SetPoint("BOTTOMRIGHT", -E.pixel, E.pixel)
	E:TrimIcon(tile.icon)
	tile.ring = CreateFrame("Frame", nil, tile)
	tile.ring:SetPoint("TOPLEFT", -3, 3)
	tile.ring:SetPoint("BOTTOMRIGHT", 3, -3)
	tile.ring:SetFrameLevel(tile:GetFrameLevel() + 1)
	E:SetTemplate(tile.ring, true)
	tile.ring:SetBackdropColor(0, 0, 0, 0)
	tile.ring:Hide()
	tile.badge = CreateFrame("Frame", nil, tile)
	tile.badge:SetSize(34, 13)
	tile.badge:SetPoint("BOTTOMRIGHT", tile, "BOTTOMRIGHT", 6, -5)
	tile.badge:SetFrameLevel(tile:GetFrameLevel() + 2)
	E:SetTemplate(tile.badge)
	tile.badge.text = Kit.Text(tile.badge, 10, "CENTER")
	tile.badge.text:SetPoint("CENTER", 0, 0)
	-- Pick order: the plan point that first takes this talent.
	tile.order = M:CreateOrderBadge(tile)
	tile.order:SetPoint("TOPLEFT", tile, "TOPLEFT", -5, 5)
	tile.order:SetFrameLevel(tile:GetFrameLevel() + 2)
	tile:SetScript("OnClick", TileClick)
	tile:SetScript("OnEnter", TileTooltip)
	tile:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return tile
end

-- Colors by meaning: green full, accent planned, orange off plan. The
-- badge text tells them apart too, since the accent can sit close to green
-- or orange: "2>5" learned 2 of a planned 5, "+5/5" full, "!3/5" off plan.
local function PaintTile(tile, node, ctx)
	tile.node = node
	local live = ctx.live.ranks[node.id] or 0
	local planned = Planned(ctx, node.id)
	local shownRank = math.max(live, planned)
	local color
	local badge = ("%d/%d"):format(shownRank, node.maxRanks)
	if live > (ctx.full.ranks[node.id] or 0) then
		color = Kit.WARN
		badge = Marked("warn", badge)
	elseif live >= node.maxRanks then
		color = Kit.GOOD
		badge = Marked("good", badge)
	elseif planned > live then
		color = { Accent() }
		badge = ("%d>%d"):format(live, planned)
	elseif live > 0 then
		color = Kit.TEXT
	end
	tile.icon:SetTexture(node.icon)
	local open = shownRank > 0 or P.CanAdd(ctx.tree, ctx.shown, node.id) or (ctx.live.ranks[node.id] or 0) > 0
	tile.icon:SetDesaturated(not open and shownRank == 0)
	tile.icon:SetAlpha((shownRank == 0 and not open) and 0.45 or 1)
	if color then
		tile:SetBackdropBorderColor(color[1], color[2], color[3])
	else
		tile:SetBackdropBorderColor(unpack(E.media.borderColor))
	end
	tile.badge.text:SetText(badge)
	if color then
		tile.badge.text:SetTextColor(color[1], color[2], color[3])
	else
		Kit.Paint(tile.badge.text, shownRank == 0 and "dim" or "secondary")
	end
	local isNext = ctx.next and ctx.next.nodeID == node.id and not ctx.level
	tile.ring:SetShown(isNext and true or false)
	if isNext then tile.ring:SetBackdropBorderColor(Accent()) end
	tile.isNext = isNext
	tile.live, tile.planned = live, planned
	local picks = M:ShowsOrder() and ctx.picks[node.id]
	tile.order:SetOrder(picks and picks[1] or nil)
end

---------------------------------------------------------------------------
-- Tree panels
---------------------------------------------------------------------------
local function CreatePanel(parent)
	local panel = CreateFrame("Frame", nil, parent)
	E:SetTemplate(panel, true)
	panel.icon = panel:CreateTexture(nil, "ARTWORK")
	panel.icon:SetSize(18, 18)
	panel.icon:SetPoint("TOPLEFT", 6, -4)
	E:TrimIcon(panel.icon)
	panel.name = Kit.Text(panel, 13, "LEFT", "header")
	panel.name:SetPoint("LEFT", panel.icon, "RIGHT", 6, 0)
	panel.spent = Kit.Text(panel, 11, "RIGHT", "secondary")
	panel.spent:SetPoint("TOPRIGHT", -8, -7)
	local line = Kit.Divider(panel)
	line:SetPoint("TOPLEFT", 4, -HEADER)
	line:SetPoint("TOPRIGHT", -4, -HEADER)
	panel.tiles = {}
	panel.lines = {}
	return panel
end

local function Line(panel, index)
	local line = panel.lines[index]
	if not line then
		line = panel:CreateTexture(nil, "ARTWORK")
		panel.lines[index] = line
	end
	line:Show()
	return line
end

-- An arrow from `from` to `to`: down, sideways, or sideways then down.
local function DrawArrow(panel, used, fromTile, toTile, color)
	local fx, fy = fromTile.cx, fromTile.cy
	local tx, ty = toTile.cx, toTile.cy
	local half = fromTile.size / 2
	local thick = 2
	local function Segment(x1, y1, x2, y2)
		used = used + 1
		local line = Line(panel, used)
		line:ClearAllPoints()
		line:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
		if x1 == x2 then
			line:SetPoint("TOPLEFT", panel, "TOPLEFT", x1 - thick / 2, -math.min(y1, y2))
			line:SetSize(thick, math.max(math.abs(y2 - y1), 1))
		else
			line:SetPoint("TOPLEFT", panel, "TOPLEFT", math.min(x1, x2), -(y1 - thick / 2))
			line:SetSize(math.max(math.abs(x2 - x1), 1), thick)
		end
	end
	if fx == tx then
		Segment(fx, fy + half, tx, ty - half)
	elseif fy == ty then
		Segment(fx + (tx > fx and half or -half), fy, tx + (tx > fx and -half or half), ty)
	else
		Segment(fx + (tx > fx and half or -half), fy, tx, fy)
		Segment(tx, fy, tx, ty - half)
	end
	return used
end

local function LayoutPanel(panel, group, ctx, width, height)
	local tree = ctx.tree
	panel:SetSize(width, height)
	panel.icon:SetTexture(group.icon or 134400)
	panel.icon:SetShown(group.icon ~= nil)
	panel.name:SetText(group.name or "")
	local planned = ctx.shown.spent[group.groupID] or 0
	local live = ctx.live.spent[group.groupID] or 0
	panel.spent:SetText(L["Plan %d  You %d"]:format(planned, live))
	local rows, cols = math.max(tree.rows, 1), math.max(tree.cols, 1)
	local innerW, innerH = width - 16, height - HEADER - 12
	local cellW, cellH = innerW / cols, innerH / rows
	local size = math.floor(math.min(M.db.tileSize or 36, cellW * 0.78, cellH * 0.78))
	size = math.max(size, 16)
	local used = 0
	local byNode = {}
	local index = 0
	for _, nodeID in ipairs(tree.order) do
		local node = tree.nodes[nodeID]
		if node.group == group.groupID then
			index = index + 1
			local tile = panel.tiles[index] or CreateTile(panel)
			panel.tiles[index] = tile
			tile:SetSize(size, size)
			tile.size = size
			tile.cx = 8 + (node.col - 0.5) * cellW
			tile.cy = HEADER + 6 + (node.row - 0.5) * cellH
			tile:ClearAllPoints()
			tile:SetPoint("CENTER", panel, "TOPLEFT", tile.cx, -tile.cy)
			PaintTile(tile, node, ctx)
			tile:Show()
			byNode[nodeID] = tile
		end
	end
	for extra = index + 1, #panel.tiles do panel.tiles[extra]:Hide() end
	if M.db.showArrows ~= false then
		for nodeID, tile in pairs(byNode) do
			for _, prereq in ipairs(tree.nodes[nodeID].prereqs) do
				local from = byNode[prereq]
				if from then
					local full = math.max(ctx.live.ranks[prereq] or 0, Planned(ctx, prereq)) >= tree.nodes[prereq].maxRanks
					local r, g, b = Accent()
					local color = full and { r, g, b, 0.9 } or { Kit.DIM[1], Kit.DIM[2], Kit.DIM[3], 0.8 }
					used = DrawArrow(panel, used, from, tile, color)
				end
			end
		end
	end
	for extra = used + 1, #panel.lines do panel.lines[extra]:Hide() end
	panel.byNode = byNode
end

---------------------------------------------------------------------------
-- Level guide strip
---------------------------------------------------------------------------
local function GuideLabel(frame, ctx)
	local tree = ctx.tree
	if not ctx.level then
		frame.guideLabel:SetText(L["Level guide: your whole plan (%d of %d points)"]:format(#ctx.order, tree.maxPoints))
		return
	end
	local step = ctx.order[ctx.upto] and ctx.upto == P.PointsAt(ctx.level) and ctx.order[ctx.upto]
	if step then
		local rank = 0
		for index = 1, ctx.upto do if ctx.order[index] == step then rank = rank + 1 end end
		local node = tree.nodes[step]
		frame.guideLabel:SetText(L["Level %d: %s %d/%d"]:format(ctx.level, node.name, rank, node.maxRanks))
	else
		frame.guideLabel:SetText(L["Level %d: no point planned"]:format(ctx.level))
	end
end

local function GuideMarkers(frame, ctx)
	local tree = ctx.tree
	local slider = frame.slider
	local width = slider:GetWidth() or (CONTENT_W - 120)
	if width <= 0 then width = CONTENT_W - 120 end
	local low, high = P.FIRST_LEVEL, tree.maxLevel
	local used = 0
	if M.db.guideMarkers ~= false and C_Spell and C_Spell.IsSpellPassive then
		local seen = {}
		for index, nodeID in ipairs(ctx.order) do
			local node = tree.nodes[nodeID]
			if node and node.spellID and not seen[nodeID] then
				seen[nodeID] = true
				local ok, passive = pcall(C_Spell.IsSpellPassive, node.spellID)
				if ok and passive == false then
					used = used + 1
					local mark = frame.markers[used]
					if not mark then
						mark = CreateFrame("Frame", nil, frame.guide)
						mark:SetSize(6, 8)
						mark.tex = mark:CreateTexture(nil, "OVERLAY")
						mark.tex:SetAllPoints()
						mark:EnableMouse(true)
						frame.markers[used] = mark
					end
					local level = P.Level(index)
					local x = (level - low) / math.max(high - low, 1) * width
					mark:ClearAllPoints()
					mark:SetPoint("BOTTOM", slider, "TOPLEFT", x, 1)
					mark.tex:SetColorTexture(Accent())
					Kit.Tooltip(mark, L["Level %d: %s"]:format(level, node.name), L["Your plan buys a new ability here."])
					mark:Show()
				end
			end
		end
	end
	for extra = used + 1, #frame.markers do frame.markers[extra]:Hide() end
end

local function CreateGuide(frame)
	local guide = CreateFrame("Frame", nil, frame)
	guide:SetHeight(GUIDE_STRIP)
	guide:SetPoint("BOTTOMLEFT", 0, ACTION_BAR + 2)
	guide:SetPoint("BOTTOMRIGHT", 0, ACTION_BAR + 2)
	frame.guide = guide
	frame.guideLabel = Kit.Text(guide, 12, "LEFT")
	frame.guideLabel:SetPoint("TOPLEFT", 2, -2)
	frame.guideAll = Kit.Button(guide, L["Whole plan"], 96, 20, function()
		M.guideLevel = nil
		frame.slider:SetValue(frame.slider.max or 60)
		M:RefreshWindow()
	end, L["Whole plan"], L["Shows every point of your plan again."])
	frame.guideAll:SetPoint("TOPRIGHT", 0, 0)
	frame.guideNow = Kit.Button(guide, L["My level"], 80, 20, function()
		local level = M:PlayerLevel()
		frame.slider:SetValue(math.max(level, P.FIRST_LEVEL))
	end, L["My level"], L["Shows your plan as it should stand at your level now."])
	frame.guideNow:SetPoint("RIGHT", frame.guideAll, "LEFT", -4, 0)
	local slider = CreateFrame("Slider", nil, guide)
	slider:SetOrientation("HORIZONTAL")
	slider:SetHeight(10)
	slider:SetPoint("BOTTOMLEFT", 4, 4)
	slider:SetPoint("BOTTOMRIGHT", -4, 4)
	slider:SetValueStep(1)
	slider:SetObeyStepOnDrag(true)
	slider:SetMinMaxValues(P.FIRST_LEVEL, 60)
	slider.max = 60
	-- The shared flat slider (E:SkinSlider): track, accent fill and thumb.
	slider.parts = E:SkinSlider(slider, { thumbHeight = 14 })
	slider.thumb = slider.parts and slider.parts.thumb
	slider:SetValue(60)
	-- The trees redraw when the knob is let go (E.UIKit.SliderCommit);
	-- while it is dragged only the label shows the level.
	local Feed = E.UIKit.SliderCommit(slider, {
		preview = function(value)
			if slider.kitDragging then frame.guideLabel:SetText(L["Level %d"]:format(math.floor((value or 0) + 0.5))) end
		end,
		commit = function(value)
			value = math.floor((value or 0) + 0.5)
			local level = value < (slider.max or 60) and value or nil
			if level ~= M.guideLevel then
				M.guideLevel = level
				M:RefreshWindow()
			end
		end,
	})
	slider:SetScript("OnValueChanged", function(own, value)
		if own.updating then return end
		Feed(value)
	end)
	Kit.Tooltip(slider, L["Level guide"], L["Drag to see your plan as it stands at any level. The trees show only the points planned up to that level."])
	frame.slider = slider
	frame.markers = {}
end

---------------------------------------------------------------------------
-- Plan picker
---------------------------------------------------------------------------
local function NewPlanDialog(fromLive)
	local question = fromLive and L["Name for the new plan (it starts as the talents you have):"] or L["Name for the new plan:"]
	M:AskText(question, fromLive and L["My talents"] or L["My plan"], function(text)
		local plan, err
		if fromLive then plan, err = M:CreatePlanFromLive(text, M:ViewGroup()) else plan, err = M:CreatePlan(text, nil, M:ViewGroup()) end
		if not plan then M:SetWindowStatus(err, true) end
	end)
end

local function PlanMenu(owner)
	local group = M:ViewGroup()
	E.UIKit.ContextMenu(owner, function(_, root)
		root:CreateTitle(L["Plans"])
		local active = M:ActivePlan(group)
		for _, plan in ipairs(M:Plans(group)) do
			local label = plan == active and (Kit.AccentHex() .. plan.name .. "|r") or plan.name
			root:CreateButton(label, function() M:SetActivePlan(plan.id, group) end)
		end
		root:CreateDivider()
		root:CreateButton(L["New empty plan"], function() NewPlanDialog(false) end)
		if not M:IsOtherClass(group) then root:CreateButton(L["New plan from my talents"], function() NewPlanDialog(true) end) end
		root:CreateButton(L["Manage plans"], function() M:OpenPlanner("plans") end)
	end, { at = "owner" })
end

-- Class picker: your class first, then the others in the game's order.
local function ClassLabel(token)
	local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]
	local name = M:ClassName(token)
	if color and color.GenerateHexColorMarkup then return color:GenerateHexColorMarkup() .. name .. "|r" end
	return name
end

function M:SetViewClass(class)
	if not self:IsOtherClass(class) then class = nil end
	self.viewClass = class
	self.selectedPlan = nil
	self.guideLevel = nil
	self:Changed()
end

local function ClassMenu(owner)
	local own = M:ClassToken()
	E.UIKit.ContextMenu(owner, function(_, root)
		root:CreateTitle(L["Plan for"])
		root:CreateButton(ClassLabel(own) .. "  " .. E:TextHex("secondary") .. L["(you)"] .. "|r", function() M:SetViewClass(nil) end)
		root:CreateDivider()
		for _, token in ipairs(M.CLASSES) do
			if token ~= own then
				local count = #M:Plans(token)
				local label = ClassLabel(token)
				if count > 0 then label = label .. "  " .. E:TextHex("secondary") .. E:Plural(count, "%d plan", "%d plans"):format(count) .. "|r" end
				root:CreateButton(label, function() M:SetViewClass(token) end)
			end
		end
	end, { at = "owner" })
end

---------------------------------------------------------------------------
-- Trees tab
---------------------------------------------------------------------------
local function LearnTip(mode)
	return function(tooltip)
		local ok, why = M:CanLearn(M:ViewGroup())
		if mode == "next" then
			tooltip:AddLine(L["Learns the next rank of your plan. One click, one rank; nothing else is spent."], Kit.SECONDARY[1], Kit.SECONDARY[2], Kit.SECONDARY[3], true)
		else
			tooltip:AddLine(L["Learns every rank your plan has up to your level, as far as your unspent points go, in one go."], Kit.SECONDARY[1], Kit.SECONDARY[2], Kit.SECONDARY[3], true)
		end
		if ok then
			local names = {}
			for _, step in ipairs(M:LearnSteps(mode)) do names[#names + 1] = M:StepText(step) end
			if #names > 0 then tooltip:AddLine(table.concat(names, ", "), Kit.TEXT[1], Kit.TEXT[2], Kit.TEXT[3], true) end
		elseif why then
			tooltip:AddLine(why, Kit.WARN[1], Kit.WARN[2], Kit.WARN[3], true)
		end
	end
end

local function CreateTrees(content)
	local frame = CreateFrame("Frame", nil, content)
	frame:SetAllPoints()
	trees = frame

	frame.planButton = Kit.Button(frame, L["Plan"], 200, 22, function(own) PlanMenu(own) end,
		L["Plan"], L["Pick another plan, start a new one, or start from the talents you have."])
	frame.planButton:SetPoint("TOPLEFT", 0, 0)
	frame.classButton = Kit.Button(frame, L["Class"], 120, 22, function(own) ClassMenu(own) end,
		L["Class"], L["Plan your own class, or another class for an alt or a friend. Plans for other classes are saved for your whole account and are never learned from here."])
	frame.classButton:SetPoint("LEFT", frame.planButton, "RIGHT", 8, 0)
	frame.groupBar = Kit.ChipBar(frame, {
		chips = {
			{ 1, L["Talent group 1"], L["Plan for your first talent group."] },
			{ 2, L["Talent group 2"], L["Plan for your second talent group (dual talents). Each group keeps its own plans."] },
		},
		selected = M:ViewGroup(),
		onChange = function(_, key)
			M.viewGroup = key
			M:Changed()
		end,
	})
	frame.groupBar:SetPoint("LEFT", frame.classButton, "RIGHT", 12, 0)
	frame.points = Kit.Text(frame, 12, "RIGHT", "secondary")
	frame.points:SetPoint("TOPRIGHT", -2, -5)

	-- The build bar (BuildBar.lua): category, Recommended build, Import build.
	frame.buildBar = M:CreateBuildBar(frame, { group = function() return M:ViewGroup() end, notify = M.WindowNotice })
	frame.buildBar:SetPoint("TOPLEFT", 0, -TOP_STRIP)
	frame.buildBar:SetPoint("TOPRIGHT", 0, -TOP_STRIP)

	frame.treeArea = CreateFrame("Frame", nil, frame)
	frame.treeArea:SetPoint("TOPLEFT", 0, -(TOP_STRIP + BUILD_ROW))
	frame.treeArea:SetPoint("TOPRIGHT", 0, -(TOP_STRIP + BUILD_ROW))
	frame.panels = {}

	CreateGuide(frame)

	frame.learnNext = Kit.Button(frame, L["Learn next"], 110, 24, function() M:Learn("next") end, L["Learn next"], LearnTip("next"))
	frame.learnNext:SetPoint("BOTTOMLEFT", 0, 2)
	frame.learnLevel = Kit.Button(frame, L["Learn to my level"], 140, 24, function() M:Learn("level") end, L["Learn to my level"], LearnTip("level"))
	frame.learnLevel:SetPoint("LEFT", frame.learnNext, "RIGHT", 6, 0)
	Kit.FitButton(frame.learnLevel, 130)
	frame.clear = Kit.Button(frame, L["Clear plan"], 90, 24, function()
		M:Confirm(L["Empty this plan? Your talents don't change."], function() M:ClearPlan(M:ViewGroup()) end)
	end, L["Clear plan"], L["Removes every point from this plan. Undo brings them back."])
	frame.clear:SetPoint("BOTTOMRIGHT", 0, 2)
	frame.undo = Kit.Button(frame, L["Undo"], 70, 24, function()
		M:Undo(M:ActivePlan(M:ViewGroup()))
	end, L["Undo"], L["Takes back your last change to this plan."])
	frame.undo:SetPoint("RIGHT", frame.clear, "LEFT", -6, 0)
	frame.status = Kit.Text(frame, 12, "LEFT", "secondary")
	frame.status:SetPoint("LEFT", frame.learnLevel, "RIGHT", 12, 0)
	frame.status:SetPoint("RIGHT", frame.undo, "LEFT", -12, 0)
	frame.status:SetWordWrap(false)
	return frame
end

local function StatusText(ctx)
	if M:IsOtherClass(ctx.group) then
		return L["%s plan, saved for your account. Learn it on a %s."]:format(M:ClassName(ctx.group), M:ClassName(ctx.group))
	end
	if not ctx.plan then return L["Click a talent to start a plan."] end
	if not ctx.next then
		if #ctx.order == 0 then return L["Click a talent to start a plan."] end
		return L["Everything in this plan is learned."]
	end
	return L["Next: %s (level %d)"]:format(M:StepText(ctx.next, ctx.group), ctx.next.level)
end

local function RefreshTrees(frame)
	local ctx = Context()
	frame.ctx = ctx
	if not ctx then return end
	local tree = ctx.tree
	frame.planButton:SetText(ctx.plan and ctx.plan.name or L["No plan yet"])
	Kit.FitButton(frame.planButton, 160)
	frame.classButton:SetText(ClassLabel(M:IsOtherClass(ctx.group) and ctx.group or M:ClassToken()))
	Kit.FitButton(frame.classButton, 100)
	frame.groupBar:SetShown(M:NumGroups() > 1 and not M:IsOtherClass(ctx.group))
	frame.groupBar:SetSelected(ctx.group)
	frame.points:SetText(L["Plan %d/%d  Learned %d  Unspent %d"]:format(#ctx.order, tree.maxPoints, ctx.live.total,
		ctx.group == E:TalentGroup() and M:Unspent(ctx.group) or 0))

	local showGuide = M.db.showGuide ~= false
	frame.guide:SetShown(showGuide)
	local bottom = ACTION_BAR + 4 + (showGuide and GUIDE_STRIP + 4 or 0)
	frame.buildBar:Update()
	local height = CONTENT_H - TOP_STRIP - BUILD_ROW - bottom
	frame.treeArea:SetHeight(height)
	local count = math.max(#tree.groups, 1)
	local width = (CONTENT_W - (count - 1) * PANEL_GAP) / count
	for index, group in ipairs(tree.groups) do
		local panel = frame.panels[index] or CreatePanel(frame.treeArea)
		frame.panels[index] = panel
		panel:ClearAllPoints()
		panel:SetPoint("TOPLEFT", frame.treeArea, "TOPLEFT", (index - 1) * (width + PANEL_GAP), 0)
		LayoutPanel(panel, group, ctx, width, height)
		panel:Show()
	end
	for extra = #tree.groups + 1, #frame.panels do frame.panels[extra]:Hide() end

	if showGuide then
		local slider = frame.slider
		slider.updating = true
		slider.max = tree.maxLevel
		slider:SetMinMaxValues(P.FIRST_LEVEL, tree.maxLevel)
		slider:SetValue(ctx.level or tree.maxLevel)
		slider.updating = false
		if slider.parts then slider.parts.Paint() end
		GuideLabel(frame, ctx)
		GuideMarkers(frame, ctx)
	end

	local canLearn = M:CanLearn(ctx.group)
	frame.learnNext:SetEnabled(canLearn and true or false)
	frame.learnLevel:SetEnabled(canLearn and true or false)
	frame.undo:SetEnabled(M:CanUndo(ctx.plan))
	frame.clear:SetEnabled(ctx.plan ~= nil and #ctx.order > 0)
	local level = M:PlayerLevel()
	local steps = canLearn and M:LearnSteps("level", ctx.group) or {}
	frame.learnLevel:SetText(#steps > 1 and L["Learn to my level (%d)"]:format(#steps) or L["Learn to my level"])
	Kit.FitButton(frame.learnLevel, 130)
	frame.learnLevel.level = level
	if not frame.message then frame.status:SetText(StatusText(ctx)) end
end

-- The answer to a click in the planner (a plan saved, a build copied, an
-- import refused): a toast over the window's footer, the warn bar for a
-- problem, with an optional action such as Undo. Chat only when the
-- window has closed in the meantime.
function M.WindowNotice(text, warn, action)
	local frame = win and win.frame
	if not (frame and win:IsOpen()) then
		E:Print(text)
		return
	end
	Kit.Toast(frame, text, { warn = warn, action = action, anchor = frame.footer, point = "TOP", y = 6 })
end

-- A short message on the Trees tab (a refusal, what was learned).
function M:SetWindowStatus(message, failed)
	if not trees then return end
	local token = {}
	trees.message = token
	trees.status:SetText(message or "")
	if failed then trees.status:SetTextColor(Kit.WARN[1], Kit.WARN[2], Kit.WARN[3]) else Kit.Paint(trees.status, "secondary") end
	C_Timer.After(6, function()
		if trees.message ~= token then return end
		trees.message = nil
		Kit.Paint(trees.status, "secondary")
		if trees.ctx then trees.status:SetText(StatusText(trees.ctx)) end
	end)
end

---------------------------------------------------------------------------
-- Guide tab: every point of the plan with its level.
---------------------------------------------------------------------------
local STATUS_ORDER = { next = 1, open = 2, learned = 3 }

local function GuideItems()
	local group = M:ViewGroup()
	local tree = M:TreeOf(group)
	local items = {}
	if not tree then return items end
	local plan = M:ActivePlan(group)
	local next = M:OpenSteps(plan, group)[1]
	for _, step in ipairs(M:PlanSteps(plan, group)) do
		local node = tree.nodes[step.nodeID]
		if node then
			local status = step.learned and "learned" or (next and next.index == step.index and "next" or "open")
			local treeGroup = tree.groups[node.groupIndex]
			items[#items + 1] = {
				level = step.level, name = node.name, icon = node.icon, rank = step.rank, maxRanks = node.maxRanks,
				tree = treeGroup and treeGroup.name or "", status = status, spellID = node.spellID,
			}
		end
	end
	return items
end

local function CreateGuideTab(content)
	local frame = CreateFrame("Frame", nil, content)
	frame:SetAllPoints()

	local statusText = { learned = L["Learned"], next = L["Next"], open = L["Planned"] }
	frame.table = Kit.CreateTable(frame, {
		{ key = "level", title = L["Level"], width = 70, align = "RIGHT", desc = L["The level this point is for: one point per level from 10."] },
		{ key = "name", title = L["Talent"], text = function(item) return ("|T%s:14:14:0:0:64:64:5:59:5:59|t %s"):format(tostring(item.icon), item.name) end },
		{ key = "rank", title = L["Rank"], width = 70, align = "CENTER", text = function(item) return ("%d/%d"):format(item.rank, item.maxRanks) end },
		{ key = "tree", title = L["Tree"], width = 140 },
		{ key = "status", title = L["Status"], width = 120, value = function(item) return STATUS_ORDER[item.status] end,
			text = function(item) return statusText[item.status] end,
			color = function(item)
				if item.status == "learned" then return Kit.GOOD[1], Kit.GOOD[2], Kit.GOOD[3] end
				if item.status == "next" then return Accent() end
				return Kit.SECONDARY[1], Kit.SECONDARY[2], Kit.SECONDARY[3]
			end },
	}, {
		sortKey = "level",
		empty = { L["No plan yet"], L["Click talents on the Trees tab to plan them. This list then shows every point with its level."], 134400 },
		onClick = function(item, button)
			if button == "LeftButton" and IsShiftKeyDown() and item.spellID and C_Spell.GetSpellLink then
				local link = C_Spell.GetSpellLink(item.spellID)
				if link then E:InsertLink(link) end
			end
		end,
		updateRow = function(row, item)
			row:SetScript("OnEnter", function(own)
				if not item.spellID then return end
				Kit.AnchorTooltip(own)
				pcall(GameTooltip.SetSpellByID, GameTooltip, item.spellID)
				GameTooltip:Show()
			end)
			row:SetScript("OnLeave", function() GameTooltip:Hide() end)
		end,
	})
	frame.table:SetAllPoints()
	return frame
end

local function RefreshGuideTab(frame)
	frame.table:SetData(GuideItems())
end

---------------------------------------------------------------------------
-- Builds tab: the talent paths EldoUI suggests for the class. Copy to a
-- new plan makes a plan of your own (never over one you have) and puts it
-- in use; Undo on the Trees tab takes it back.
---------------------------------------------------------------------------
local BUILD_DETAIL = 128

local function BuildItems()
	local group = M:ViewGroup()
	local tree = M:TreeOf(group)
	local items = {}
	for index, path in ipairs(M:PathsOf(group)) do
		local order, skipped = B.Resolve(tree, path)
		items[#items + 1] = {
			path = path, key = path.key, index = index, title = path.title, role = path.role,
			situation = path.situation, checked = path.checked, points = #order, skipped = skipped,
		}
	end
	return items
end

local function SelectedBuild(items)
	for _, item in ipairs(items) do
		if item.key == M.selectedBuild then return item end
	end
	return items[1]
end

local function CopySelectedBuild(frame)
	local item = frame.item
	if not item then return end
	local plan, result = M:CopyPath(item.key, M:ViewGroup())
	if not plan then
		frame.detail.warn:SetText(result or "")
		return
	end
	win:Open("trees")
	local text, warn = M:CopyPathText(plan, result)
	M.WindowNotice(text, warn, { L["Undo"], function() M:Undo(plan) end })
end

local function BuildTooltip(row)
	local item = row.item
	if not item then return end
	Kit.AnchorTooltip(row)
	Kit.TipTitle(GameTooltip, item.title)
	Kit.TipText(GameTooltip, item.path.note)
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine(L["Suggested by EldoUI, checked on %s."]:format(item.checked), Kit.DIM[1], Kit.DIM[2], Kit.DIM[3], true)
	GameTooltip:Show()
end

local function CreateBuildsTab(content)
	local frame = CreateFrame("Frame", nil, content)
	frame:SetAllPoints()

	frame.table = Kit.CreateTable(frame, {
		{ key = "title", title = L["Path"], desc = L["A talent path EldoUI suggests for your class."] },
		{ key = "role", title = L["Role"], width = 100, value = function(item) return B.ROLE_ORDER[item.role] end,
			text = function(item) return B.RoleText(item.role) end, desc = L["The job in a group this path is made for."] },
		{ key = "situation", title = L["Situation"], width = 110, value = function(item) return B.SITUATION_ORDER[item.situation] end,
			text = function(item) return B.SituationText(item.situation) end, desc = L["Where the path works best: leveling, dungeons, raids, PvP or farming."] },
		{ key = "points", title = L["Points"], width = 70, align = "RIGHT", desc = L["How many points the path plans, of the 51 a level 60 character has."],
			color = function(item)
				if item.skipped > 0 then return Kit.WARN[1], Kit.WARN[2], Kit.WARN[3] end
				return Kit.TEXT[1], Kit.TEXT[2], Kit.TEXT[3]
			end },
		{ key = "checked", title = L["Checked on"], width = 130, desc = L["The game version EldoUI checked the path on."],
			color = function() return Kit.SECONDARY[1], Kit.SECONDARY[2], Kit.SECONDARY[3] end },
	}, {
		sortKey = "role",
		createRow = function(row)
			row.selected = row:CreateTexture(nil, "BACKGROUND")
			row.selected:SetAllPoints()
		end,
		updateRow = function(row, item)
			local r, g, b = Accent()
			row.selected:SetColorTexture(r, g, b, 0.25)
			row.selected:SetShown(frame.item ~= nil and frame.item.key == item.key)
			row:SetScript("OnEnter", BuildTooltip)
			row:SetScript("OnLeave", function() GameTooltip:Hide() end)
		end,
		onClick = function(item)
			M.selectedBuild = item.key
			M:RefreshWindow()
		end,
	})
	frame.table:SetPoint("TOPLEFT", 0, 0)
	frame.table:SetPoint("BOTTOMRIGHT", 0, BUILD_DETAIL)

	local detail = CreateFrame("Frame", nil, frame)
	detail:SetPoint("TOPLEFT", frame.table, "BOTTOMLEFT", 0, -8)
	detail:SetPoint("BOTTOMRIGHT")
	frame.detail = detail
	local line = Kit.Divider(detail)
	line:SetPoint("TOPLEFT")
	line:SetPoint("TOPRIGHT")
	detail.title = Kit.Text(detail, 16, "LEFT")
	detail.title:SetPoint("TOPLEFT", 0, -10)
	detail.title:SetPoint("TOPRIGHT", -200, -10)
	detail.title:SetWordWrap(false)
	detail.meta = Kit.Text(detail, 12, "LEFT", "secondary")
	detail.meta:SetPoint("TOPLEFT", detail.title, "BOTTOMLEFT", 0, -4)
	detail.meta:SetPoint("TOPRIGHT", detail.title, "BOTTOMRIGHT", 0, -4)
	detail.note = Kit.Text(detail, 12, "LEFT")
	detail.note:SetPoint("TOPLEFT", detail.meta, "BOTTOMLEFT", 0, -6)
	detail.note:SetPoint("TOPRIGHT", detail.meta, "BOTTOMRIGHT", 0, -6)
	detail.note:SetWordWrap(true)
	detail.note:SetMaxLines(3)
	detail.source = Kit.Text(detail, 11, "LEFT", "dim")
	detail.source:SetPoint("BOTTOMLEFT", 0, 4)
	detail.source:SetPoint("BOTTOMRIGHT", -200, 4)
	detail.warn = Kit.Text(detail, 12, "LEFT", "warn")
	detail.warn:SetPoint("BOTTOMLEFT", detail.source, "TOPLEFT", 0, 4)
	detail.warn:SetPoint("BOTTOMRIGHT", detail.source, "TOPRIGHT", 0, 4)
	detail.copy = Kit.Button(detail, L["Copy to a new plan"], 180, 24, function() CopySelectedBuild(frame) end,
		L["Copy to a new plan"], L["Makes a new plan from this path and follows it: the trees, the level-up card and the Learn buttons show its next point. Your other plans stay as they are, and Undo takes the copy back."])
	detail.copy:SetPoint("TOPRIGHT", 0, -10)
	return frame
end

local function RefreshBuildsTab(frame, arg)
	if type(arg) == "string" then M.selectedBuild = arg end
	local items = BuildItems()
	local item = SelectedBuild(items)
	frame.item = item
	frame.table:SetData(items)
	local detail = frame.detail
	detail:SetShown(item ~= nil)
	if not item then return end
	local tree = M:TreeOf(M:ViewGroup())
	detail.title:SetText(item.title)
	detail.meta:SetText(("%s  |  %s  |  %s"):format(B.RoleText(item.role), B.SituationText(item.situation),
		L["%d of %d points"]:format(item.points, tree and tree.maxPoints or 0)))
	detail.note:SetText(item.path.note)
	detail.source:SetText(L["Suggested by EldoUI, checked on %s."]:format(item.checked))
	detail.warn:SetText(item.skipped > 0 and E:Plural(item.skipped, "%d point of this path isn't in your game's tree, so the plan skips it.",
		"%d points of this path aren't in your game's tree, so the plan skips them."):format(item.skipped) or "")
	detail.copy:SetEnabled(#M:Plans(M:ViewGroup()) < 10 and item.points > 0)
end

local function NoBuilds()
	return #M:PathsOf(M:ViewGroup()) == 0
end

---------------------------------------------------------------------------
-- Plans tab
---------------------------------------------------------------------------
local function SelectedPlan()
	local group = M:ViewGroup()
	local plan = M.selectedPlan and M:FindPlan(M.selectedPlan, group)
	return plan or M:ActivePlan(group)
end

local function SendMenu(owner, plan)
	E.UIKit.ContextMenu(owner, function(_, root)
		root:CreateTitle(L["Send to"])
		if IsInGroup() then root:CreateButton(IsInRaid() and L["Raid"] or L["Party"], function() M:SendPlan(plan.id, "GROUP") end) end
		if IsInGuild() then root:CreateButton(L["Guild"], function() M:SendPlan(plan.id, "GUILD") end) end
		root:CreateButton(L["A player..."], function()
			M:AskText(L["Send the plan to which player?"], "", function(text) M:SendPlan(plan.id, text) end)
		end)
	end, { at = "owner" })
end

local function CreatePlansTab(content)
	local frame = CreateFrame("Frame", nil, content)
	frame:SetAllPoints()

	frame.list = Kit.CreateList(frame, {
		rowHeight = 22,
		create = function(row)
			E:SkinRow(row)
			row.selected = row:CreateTexture(nil, "BACKGROUND")
			row.selected:SetAllPoints()
			row.name = Kit.Text(row, 12, "LEFT")
			row.name:SetPoint("LEFT", 6, 0)
			row.name:SetPoint("RIGHT", -70, 0)
			row.name:SetWordWrap(false)
			row.points = Kit.Text(row, 11, "RIGHT", "secondary")
			row.points:SetPoint("RIGHT", -6, 0)
			row:SetScript("OnClick", function(own)
				M.selectedPlan = own.item.id
				M:RefreshWindow()
			end)
			row:SetScript("OnDoubleClick", function(own) M:SetActivePlan(own.item.id, M:ViewGroup()) end)
		end,
		update = function(row, plan)
			local active = M:ActivePlan(M:ViewGroup())
			row.name:SetText(plan.name)
			if plan == active then row.name:SetTextColor(E:TokenColor("accent")) else Kit.Paint(row.name) end
			row.points:SetText(L["%d points"]:format(#plan.order))
			local r, g, b = Accent()
			row.selected:SetColorTexture(r, g, b, 0.25)
			row.selected:SetShown(plan == SelectedPlan())
		end,
		empty = { L["No plans yet"], L["Click talents on the Trees tab, or start a plan from the talents you have."], 134400,
			{ { L["New plan from my talents"], function() NewPlanDialog(true) end, L["A plan that starts with the talents you have now."] } } },
	})
	frame.list:SetPoint("TOPLEFT", 0, 0)
	frame.list:SetPoint("BOTTOMLEFT", 0, 0)
	frame.list:SetWidth(300)

	local detail = CreateFrame("Frame", nil, frame)
	detail:SetPoint("TOPLEFT", frame.list, "TOPRIGHT", 16, 0)
	detail:SetPoint("BOTTOMRIGHT")
	frame.detail = detail
	detail.title = Kit.Text(detail, 16, "LEFT")
	detail.title:SetPoint("TOPLEFT", 0, -2)
	detail.title:SetPoint("TOPRIGHT", -180, -2)
	detail.lines = {}
	for index = 1, 5 do
		local line = Kit.Text(detail, 12, "LEFT", index == 1 and "body" or "secondary")
		line:SetPoint("TOPLEFT", 0, -28 - (index - 1) * 20)
		line:SetPoint("TOPRIGHT", -180, -28 - (index - 1) * 20)
		detail.lines[index] = line
	end
	local buttons = {
		{ "use", L["Use this plan"], L["The trees, the next point and the Learn buttons follow this plan."], function(plan) M:SetActivePlan(plan.id, M:ViewGroup()) end },
		{ "rename", L["Rename"], L["Gives the plan another name."], function(plan)
			M:AskText(L["New name for the plan:"], plan.name, function(text) M:RenamePlan(plan.id, text, M:ViewGroup()) end)
		end },
		{ "copy", L["Copy"], L["Makes a copy to try changes on."], function(plan)
			local copy, err = M:CopyPlan(plan.id, M:ViewGroup())
			if copy then M.selectedPlan = copy.id else M:SetWindowStatus(err, true) end
		end },
		{ "delete", L["Delete"], L["Deletes the plan. Your talents don't change."], function(plan)
			M:Confirm(L["Delete the plan %s?"]:format(plan.name), function()
				M:DeletePlan(plan.id, M:ViewGroup())
				M.selectedPlan = nil
			end)
		end },
		{ "export", L["Export"], L["A text string of the plan to copy and share (!EUT1!)."], function(plan) M:ExportPlan(plan.id) end },
		{ "send", L["Send..."], L["Offers the plan to your group, guild or a player who uses EldoUI. They see it before they save it."], function(plan, own) SendMenu(own, plan) end },
		{ "new", L["New empty plan"], L["Starts a plan with no points."], function() NewPlanDialog(false) end, true },
		{ "fromLive", L["New plan from my talents"], L["Starts a plan with the talents you have now."], function() NewPlanDialog(true) end, true },
		{ "import", L["Import"], L["Paste a talent plan string someone shared."], function() M:ShowImportBox(M.WindowNotice) end, true },
	}
	detail.buttons = {}
	for index, data in ipairs(buttons) do
		local button = Kit.Button(detail, data[2], 170, 22, nil, data[2], data[3])
		button:SetPoint("TOPRIGHT", 0, -(index - 1) * 26 - (index > 6 and 12 or 0))
		button:SetScript("OnClick", function(own)
			local plan = SelectedPlan()
			if plan or data[5] then data[4](plan, own) end
		end)
		button.always = data[5]
		detail.buttons[data[1]] = button
	end
	return frame
end

local function RefreshPlansTab(frame)
	local group = M:ViewGroup()
	local plans = M:Plans(group)
	frame.list:SetData(plans)
	local plan = SelectedPlan()
	local detail = frame.detail
	for _, button in pairs(detail.buttons) do
		button:SetEnabled(button.always or plan ~= nil)
	end
	local other = M:IsOtherClass(group)
	detail.buttons.new:SetEnabled(#plans < 10)
	detail.buttons.fromLive:SetEnabled(#plans < 10 and not other)
	for _, line in ipairs(detail.lines) do line:SetText("") end
	if not plan then
		detail.title:SetText(other and M:ClassName(group) or L["Talent group %d"]:format(group))
		detail.lines[1]:SetText(L["No plans yet"])
		return
	end
	detail.title:SetText(plan.name)
	local tree = M:TreeOf(group)
	local steps = M:PlanSteps(plan, group)
	local learned = 0
	for _, step in ipairs(steps) do if step.learned then learned = learned + 1 end end
	detail.lines[1]:SetText(L["%d of %d points"]:format(#plan.order, tree and tree.maxPoints or 0) .. "  " .. M:DescribePlanOrder(plan.order, group))
	if other then
		detail.lines[2]:SetText(L["Saved for your %s characters."]:format(M:ClassName(group)))
		detail.lines[3]:SetText(L["Learn it on a %s: the planner offers it at login."]:format(M:ClassName(group)))
	else
		detail.lines[2]:SetText(L["Learned %d of them"]:format(learned))
		local next = M:OpenSteps(plan, group)[1]
		detail.lines[3]:SetText(next and L["Next: %s (level %d)"]:format(M:StepText(next, group), next.level) or L["Nothing left to learn in this plan."])
	end
	detail.lines[4]:SetText(plan == M:ActivePlan(group) and (Kit.AccentHex() .. L["In use"] .. "|r") or L["Double-click a plan or press Use this plan to follow it."])
	if plan.created then detail.lines[5]:SetText(L["Made %s"]:format(E:ShortDay(plan.created))) end
	detail.buttons.use:SetEnabled(plan ~= M:ActivePlan(group))
end

---------------------------------------------------------------------------
-- Dialogs
---------------------------------------------------------------------------
function M:AskText(question, text, accept)
	E:ShowConfirm({ key = "ELDOUI_TALENTS_TEXT", title = L["Talents"], text = question, accept = ACCEPT,
		edit = { text = text or "", maxLetters = 40 },
		onAccept = function(_, typed) if accept then accept(typed or "") end end })
end

function M:Confirm(question, accept)
	E:ShowConfirm({ key = "ELDOUI_TALENTS_CONFIRM", title = L["Talents"], text = question, accept = YES, cancel = NO, danger = true,
		onAccept = function() if accept then accept() end end })
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------
local function NoTree()
	local group = M:ViewGroup()
	if M:TreeOf(group) then return nil end
	if M:IsOtherClass(group) then
		return L["%s tree not available"]:format(M:ClassName(group)), M:NoTreeText(group), 134400,
			{ { L["Back to my class"], function() M:SetViewClass(nil) end, L["Plan your own class again."] } }
	end
	return L["Talents aren't loaded yet"], L["The game hasn't sent your talent tree yet. Open the planner again in a moment."], 134400
end

local function Footer()
	-- Why Blizzard's talent window has no Planner row comes first; the
	-- click help line comes back once Improve is on.
	local hint = M.BlizzardRowHint and M:BlizzardRowHint()
	return hint or L["Left-click a talent: add a rank to the plan. Right-click: remove one. EldoUI learns only when you click Learn."]
end

local function HelpText(tooltip)
	local grey = Kit.SECONDARY
	tooltip:AddLine(L["Plan your talents level by level. Your ranks are white. A planned talent shows what you have and the plan, like 2>5, in your accent color. Full talents are green with +, and ranks you have outside the plan orange with !. The ring marks the next point."], grey[1], grey[2], grey[3], true)
	tooltip:AddLine(" ")
	tooltip:AddLine(L["Learn next and Learn to my level are the only buttons that spend points, and only when you click them. Plans are saved per character and talent group."], grey[1], grey[2], grey[3], true)
end

function M:BuildWindow()
	if win then return win end
	win = Kit.CreateTabbedWindow({
		name = "EldoUI_TalentPlannerFrame",
		options = { page = "module:Talents" },
		title = L["Talents"],
		width = WIDTH, height = HEIGHT,
		store = function()
			if type(M.db.window) ~= "table" then M.db.window = {} end
			return M.db.window
		end,
		tabs = {
			{ key = "trees", title = L["Trees"], desc = L["Your talent trees with your plan, the level guide and the Learn buttons."],
				create = CreateTrees, show = RefreshTrees, refresh = RefreshTrees, empty = NoTree },
			{ key = "guide", title = L["Guide"], desc = L["Every point of your plan with its level."],
				create = CreateGuideTab, show = RefreshGuideTab, refresh = RefreshGuideTab, empty = NoTree },
			{ key = "builds", title = L["Builds"], desc = L["Talent paths EldoUI suggests for your class, by role and situation. Copy one into a plan of your own to follow it."],
				create = CreateBuildsTab, show = RefreshBuildsTab, refresh = RefreshBuildsTab, empty = NoTree, hidden = NoBuilds },
			{ key = "plans", title = L["Plans"], desc = L["Your plans: use, rename, copy, delete, export, import and send them."],
				create = CreatePlansTab, show = RefreshPlansTab, refresh = RefreshPlansTab, empty = NoTree,
				count = function() return #M:Plans(M:ViewGroup()) end },
		},
		help = { text = HelpText },
		footer = Footer,
		transparent = function() return M.db.transparent end,
	})
	-- The window sits on its mover (/eui move); dragging the title bar
	-- moves the mover, and the zoom grip keeps its scale.
	win.ApplyPosition = function(own)
		local frame = own.frame
		if not frame then return end
		frame:SetScale(own:Scale())
		if M.mover then
			frame:ClearAllPoints()
			frame:SetPoint("CENTER", M.mover, "CENTER")
		end
	end
	win.SavePosition = function(own)
		local frame = own.frame
		if not (frame and M.mover) then return end
		local left, bottom = frame:GetLeft(), frame:GetBottom()
		if not (left and bottom) then return end
		local scale = frame:GetScale()
		local width, height = frame:GetWidth(), frame:GetHeight()
		E:SaveMoverFromRect(M.mover, (left + width / 2) * scale - width / 2, (bottom + height / 2) * scale - height / 2)
	end
	local frame = win:Build()
	self.mover = E:CreateMover(frame, MOVER, L["Talent Planner"], { "TOP", "UIParent", "TOP", 0, -80 }, {
		sample = false,
		onMoved = function() win:ApplyPosition() end,
	})
	win:ApplyPosition()
	return win
end

function M:Window()
	return win
end

-- tab: "trees", "guide", "builds" (arg: the path to show) or "plans".
function M:OpenPlanner(tab, arg)
	if not self.active then return false end
	self:BuildWindow()
	return win:Open(tab, arg)
end

function M:ClosePlanner()
	if win then win:Close() end
end

function M:TogglePlanner(tab)
	if not self.active then return end
	self:BuildWindow()
	win:Toggle(tab)
end

function M:RefreshWindow()
	if not (win and win:IsOpen()) then return end
	-- The class picked has no suggested paths: the Builds tab goes.
	if win:Current() == "builds" and NoBuilds() then
		win:Open("trees")
		return
	end
	win:Refresh()
end

function M:RestyleWindow()
	if win then
		win:Restyle()
		self:RefreshWindow()
	end
end
