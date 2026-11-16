-- EldoUI Profession Planner: the Shopping List tracker, the planner
-- window (shopping list and leveling plan) and the Pin buttons.
--
-- Pin buttons:
--   * the game's profession window (Blizzard UI > Professions, Improve):
--     a Pin button next to the selected recipe, read from the recipe the
--     window shows (post-hook, nothing replaced)
--   * Loot Guide > Crafting details: through LG.craftDetailExtras
--   * Alts > Professions: Alt-click a recipe row (its tooltip says so)
-- None of them crafts anything: a pin only adds the recipe to the list.
local _, E = ...
local L = E.L
local M = E.ProfessionPlanner
local Kit = E.UIKit

local floor, max = math.floor, math.max

local function Hex(color) return E:TokenHex(color) end

---------------------------------------------------------------------------
-- Pin menu (x1, x5, x10, x20, unpin)
---------------------------------------------------------------------------
function M:PinMenu(owner, recipeID, info)
	E.UIKit.ContextMenu(owner, function(_, root)
		root:CreateTitle(L["Pin to the shopping list"])
		for _, qty in ipairs(M.QUANTITIES) do
			root:CreateRadio(E:Plural(qty, "%d craft", "%d crafts"):format(qty), function()
				local pin = M:IsPinned(recipeID)
				return pin and pin.qty == qty
			end, function() M:Pin(recipeID, qty, info) end)
		end
		if M:IsPinned(recipeID) then
			root:CreateButton(L["Unpin"], function() M:Unpin(recipeID) end)
		end
	end)
end

---------------------------------------------------------------------------
-- Tracker
---------------------------------------------------------------------------
local HEADER = 22
local PAD = 6

local function LineHeight() return (M.db.fontSize or 12) + 5 end

function M:TrackerHeight()
	return HEADER + PAD + (self.db.maxLines or 24) * LineHeight() + 26
end

local function LineTooltip(row)
	local data = row.data
	if not data then return end
	GameTooltip:SetOwner(row, "ANCHOR_LEFT")
	if data.kind == "reagent" then
		if GameTooltip.SetItemByID then GameTooltip:SetItemByID(data.id) end
		local total, mine, alts = M:Have(data.id)
		local s, b = Kit.SECONDARY, Kit.TEXT
		GameTooltip:AddLine(" ")
		GameTooltip:AddDoubleLine(L["You"], tostring(mine), s[1], s[2], s[3], b[1], b[2], b[3])
		for _, alt in ipairs(alts) do GameTooltip:AddDoubleLine(alt.name, tostring(alt.count), s[1], s[2], s[3], b[1], b[2], b[3]) end
		GameTooltip:AddDoubleLine(L["Total"], tostring(total), s[1], s[2], s[3], b[1], b[2], b[3])
	elseif data.kind == "pin" then
		GameTooltip:AddLine(data.text, unpack(E.tokens.text.body))
		E:TooltipHint(GameTooltip, { L["Click"], L["open the planner"] }, { L["Right-click"], L["change the number of crafts or unpin"] })
	elseif data.kind == "cooldown" then
		GameTooltip:AddLine(data.text, unpack(E.tokens.text.body))
		GameTooltip:AddLine(L["Saved when that character last opened its profession window."], Kit.SECONDARY[1], Kit.SECONDARY[2], Kit.SECONDARY[3], true)
	end
	GameTooltip:Show()
end

local function CreateLine(parent)
	local row = CreateFrame("Button", nil, parent)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	row.icon = row:CreateTexture(nil, "ARTWORK")
	E:TrimIcon(row.icon)
	row.left = E:CreateText(row, M.db.fontSize, "LEFT")
	row.left:SetWordWrap(false)
	row.right = E:CreateText(row, M.db.fontSize, "RIGHT")
	row.hover = row:CreateTexture(nil, "HIGHLIGHT")
	row.hover:SetAllPoints()
	row.hover:SetColorTexture(1, 1, 1, E.tokens.hover.row)
	row:SetScript("OnEnter", LineTooltip)
	row:SetScript("OnLeave", GameTooltip_Hide)
	row:SetScript("OnClick", function(self, button)
		local data = self.data
		if not data then return end
		if data.kind == "pin" and button == "RightButton" then
			M:PinMenu(self, data.id)
		elseif data.kind == "reagent" and IsModifiedClick("CHATLINK") then
			local _, link = C_Item.GetItemInfo(data.id)
			if link then E:InsertLink(link) end
		else
			M:OpenWindow("list")
		end
	end)
	return row
end

function M:BuildTracker()
	if self.tracker then return end
	local frame = CreateFrame("Frame", "EldoUI_ShoppingList", UIParent)
	frame:SetSize(self.db.width, self:TrackerHeight())
	frame:SetFrameStrata("LOW")
	frame.bg = CreateFrame("Frame", nil, frame)
	frame.bg:SetPoint("TOPLEFT")
	frame.bg:SetPoint("TOPRIGHT")
	frame.bg:SetHeight(HEADER)
	frame.bg:SetFrameLevel(max(frame:GetFrameLevel() - 1, 0))
	frame.header = CreateFrame("Button", nil, frame)
	frame.header:SetPoint("TOPLEFT")
	frame.header:SetPoint("TOPRIGHT")
	frame.header:SetHeight(HEADER)
	frame.title = Kit.Text(frame.header, 13, "LEFT", "header")
	frame.title:SetPoint("LEFT", PAD, 0)
	frame.title:SetText(L["Shopping list"])
	frame.summary = Kit.Text(frame.header, 11, "RIGHT", "secondary")
	frame.summary:SetPoint("RIGHT", -PAD, 0)
	-- Left-click opens the planner; a right-click is left to the shared
	-- Hide menu (the header only takes left clicks).
	frame.header:SetScript("OnClick", function() M:OpenWindow("list") end)
	Kit.Tooltip(frame.header, L["Shopping list"], function(tip)
		if E:IsRightClickLocked() or not E:CanHide("EldoUI_ShoppingList") then
			Kit.TooltipHint(tip, { L["Click"], L["open the Profession Planner"] })
		else
			Kit.TooltipHint(tip, { L["Click"], L["open the Profession Planner"] }, { L["Right-click"], L["hide the list"] })
		end
	end)
	E:SkinHoverPress(frame.header)
	frame.send = Kit.Button(frame, L["Send to Shopping"], 140, E.tokens.height.button, function() M:SendAndTell(frame) end,
		L["Send to Shopping"], L["Puts every missing reagent on the auction house shopping list \"Profession Planner\". You still search and buy yourself."])
	frame.send:Hide()
	frame.lines = {}
	frame:Hide()
	self.tracker = frame
	E:CreateMover(frame, "EldoUI_ShoppingList", L["Shopping List"], { "TOP", "UIParent", "TOP", 277, -516 })
	E:RegisterHideable(frame.header, "EldoUI_ShoppingList", { mouse = true })
	-- Whatever shows the tracker (a box shown again, move mode ending), it
	-- only stays on screen while the one rule below wants it.
	frame:HookScript("OnShow", function(f)
		if not M:TrackerWanted() then f:Hide() end
	end)
	hooksecurefunc(E, "ToggleMoveMode", function() M:RefreshTracker() end)
	E:RegisterHideListener(function() M:RefreshTracker() end)
	self:StyleTracker()
	self:UpdateTrackerVisibility()
end

-- The tracker follows the shared visibility block (out of combat only by
-- default); move mode always shows it.
local function InMoveMode() return E.IsMoveMode and E:IsMoveMode() end
function M:UpdateTrackerVisibility()
	local frame = self.tracker
	if not frame then return end
	if type(self.db.visibility) ~= "table" then self.db.visibility = E:VisibilityDefaults({ show = "nocombat" }) end
	if self.active then
		E:AttachVisibility(frame, self.db.visibility, { forceShow = InMoveMode })
	elseif E:IsVisibilityAttached(frame) then
		E:DetachVisibility(frame)
	end
end

function M:StyleTracker()
	local frame = self.tracker
	if not frame then return end
	frame:SetSize(self.db.width, self:TrackerHeight())
	local backdrop = self.db.backdrop
	if backdrop == "panel" then
		E:SetPanelTemplate(frame.bg, false)
	else
		E:SetTemplate(frame.bg, true)
	end
	frame.bg:SetShown(backdrop ~= "none")
	E:SetStyleEdge(frame.bg, self.db.edge and backdrop ~= "none")
	for _, row in ipairs(frame.lines) do
		E:SetFont(row.left, self.db.fontSize)
		E:SetFont(row.right, self.db.fontSize)
	end
	Kit.Paint(frame.title, "header")
end

-- Rows for the tracker (and the reagent table): pins, reagents, cooldowns.
function M:TrackerRows()
	local rows = {}
	for _, entry in ipairs(self:Needs()) do
		local recipe = entry.recipe
		local name = recipe and recipe.name or ("#" .. entry.pin.id)
		rows[#rows + 1] = { kind = "pin", id = entry.pin.id, text = ("%s  x%d"):format(name, entry.pin.qty),
			icon = recipe and recipe.result and recipe.result > 0 and self:ItemIcon(recipe.result) or recipe and recipe.icon }
		if not recipe then
			rows[#rows + 1] = { kind = "note", text = L["Open your profession window once to read this recipe."], depth = 1 }
		end
		for _, line in ipairs(entry.lines) do
			local done = line.have >= line.need
			if not (done and self.db.hideDone) then
				local text = self:ItemName(line.id) or ("#" .. line.id)
				if line.made then text = text .. " " .. Hex(Kit.SECONDARY) .. (L["(make %d)"]):format(line.crafts) .. "|r" end
				rows[#rows + 1] = { kind = "reagent", id = line.id, text = text, have = line.have, need = line.need, done = done,
					depth = line.depth + 1, icon = self:ItemIcon(line.id) }
			end
		end
	end
	if self.db.cooldowns then
		for _, cd in ipairs(self:Cooldowns()) do
			rows[#rows + 1] = { kind = "cooldown", id = cd.id, text = ("%s: %s"):format(cd.name, cd.who),
				ready = cd.left <= 0, left = cd.left }
		end
	end
	return rows
end

local function Duration(seconds)
	if seconds >= 86400 then return (L["%dd"]):format(floor(seconds / 86400 + 0.5)) end
	if seconds >= 3600 then return (L["%dh"]):format(floor(seconds / 3600 + 0.5)) end
	return (L["%dm"]):format(max(1, floor(seconds / 60 + 0.5)))
end
M.Duration = Duration

local CHECK = "|T" .. (rawget(_G, "READY_CHECK_READY_TEXTURE") or "Interface\\RaidFrame\\ReadyCheck-Ready") .. ":0|t"

-- The one rule for the tracker on screen: the module is on, the tracker
-- option is on and something is pinned. Cooldown rows alone never keep an
-- empty list up. Move mode shows it while frames are being placed.
function M:TrackerWanted()
	if not (self.active and self.db.tracker) then return false end
	if E.IsMoveMode and E:IsMoveMode() then return true end
	return #self:Pins() > 0
end

function M:RefreshTracker()
	local frame = self.tracker
	if not frame then return end
	if not self:TrackerWanted() then
		frame:Hide()
		return
	end
	local rows = self:TrackerRows()
	local lineHeight, size = LineHeight(), self.db.fontSize
	local shown = math.min(#rows, self.db.maxLines)
	local done, total = 0, 0
	for _, row in ipairs(rows) do
		if row.kind == "reagent" and row.depth == 1 then
			total = total + 1
			if row.done then done = done + 1 end
		end
	end
	frame.summary:SetText(total > 0 and ("%d/%d"):format(done, total) or "")
	for index = 1, shown do
		local data = rows[index]
		local row = frame.lines[index] or CreateLine(frame)
		frame.lines[index] = row
		row.data = data
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -(HEADER + (index - 1) * lineHeight))
		row:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -(HEADER + (index - 1) * lineHeight))
		row:SetHeight(lineHeight)
		E:SetFont(row.left, size)
		E:SetFont(row.right, size)
		local indent = (data.depth or 0) * 10
		local iconShown = self.db.icons and data.icon ~= nil
		row.icon:SetSize(size, size)
		row.icon:ClearAllPoints()
		row.icon:SetPoint("LEFT", indent, 0)
		row.icon:SetTexture(data.icon)
		row.icon:SetShown(iconShown)
		row.left:ClearAllPoints()
		row.left:SetPoint("LEFT", iconShown and row.icon or row, iconShown and "RIGHT" or "LEFT", iconShown and 4 or indent, 0)
		row.left:SetPoint("RIGHT", row.right, "LEFT", -4, 0)
		row.right:ClearAllPoints()
		row.right:SetPoint("RIGHT")
		row.left:SetText(data.text or "")
		if data.kind == "pin" then
			row.left:SetTextColor(unpack(E.tokens.text.body))
			row.right:SetText("")
		elseif data.kind == "reagent" then
			local color = data.done and E.tokens.text.good or E.tokens.text.secondary
			row.left:SetTextColor(unpack(color))
			if data.done and self.db.checks then
				row.right:SetText(CHECK)
			else
				row.right:SetText(("%d/%d"):format(data.have, data.need))
			end
			row.right:SetTextColor(unpack(data.done and E.tokens.text.good or E.tokens.text.body))
		elseif data.kind == "cooldown" then
			row.left:SetTextColor(unpack(E.tokens.text.secondary))
			row.right:SetText(data.ready and L["Ready"] or Duration(data.left))
			row.right:SetTextColor(unpack(data.ready and E.tokens.text.good or E.tokens.text.secondary))
		else
			row.left:SetTextColor(unpack(E.tokens.text.dim))
			row.right:SetText("")
		end
		row:Show()
	end
	for index = shown + 1, #frame.lines do
		frame.lines[index].data = nil
		frame.lines[index]:Hide()
	end
	local height = HEADER + shown * lineHeight + PAD
	local missing = self.atAuction and #self:Missing() > 0
	frame.send:ClearAllPoints()
	frame.send:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -height)
	frame.send:SetShown(missing and true or false)
	if missing then height = height + E.tokens.height.button + PAD end
	frame.bg:SetHeight(height)
	frame:Show()
end

function M:SendAndTell(owner)
	local ok, text = self:SendToShopping()
	if owner and Kit.Toast then
		Kit.Toast(owner, text, { warn = not ok, anchor = owner, point = "BOTTOM", y = -40 })
	end
	return ok, text
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
local function WindowStore()
	local store = M:Store()
	store.window = type(store.window) == "table" and store.window or {}
	return store.window
end

local function PinRows()
	local rows = {}
	for _, entry in ipairs(M:Needs()) do
		local missing, total = 0, 0
		for _, line in ipairs(entry.lines) do
			if line.depth == 0 then
				total = total + 1
				if line.have < line.need then missing = missing + 1 end
			end
		end
		rows[#rows + 1] = { id = entry.pin.id, name = entry.recipe and entry.recipe.name or ("#" .. entry.pin.id), qty = entry.pin.qty,
			missing = missing, total = total, known = entry.recipe ~= nil, cost = M:CraftCost(entry.recipe) }
	end
	return rows
end

local function ReagentRows()
	local rows = {}
	for id, t in pairs(M:Totals()) do
		rows[#rows + 1] = { id = id, name = M:ItemName(id) or ("#" .. id), have = t.have, need = t.need, missing = t.missing, price = M:Price(id) }
	end
	return rows
end

local function BuildList(content)
	local frame = CreateFrame("Frame", nil, content)
	frame:SetAllPoints()
	frame.pins = Kit.CreateTable(frame, {
		{ key = "name", title = L["Recipe"], value = function(row) return row.name end },
		{ key = "qty", title = L["Crafts"], width = 70, align = "RIGHT", value = function(row) return row.qty end },
		{ key = "missing", title = L["Reagents"], width = 110, align = "RIGHT", value = function(row) return row.missing end,
			text = function(row)
				if not row.known then return Hex(Kit.WARN) .. L["open once"] .. "|r" end
				if row.missing == 0 then return Hex(Kit.GOOD) .. L["all there"] .. "|r" end
				return (L["%d missing"]):format(row.missing)
			end },
		{ key = "cost", title = L["Cost each"], width = 130, align = "RIGHT", value = function(row) return row.cost or -1 end,
			text = function(row) return row.cost and M.Money(row.cost) or Hex(Kit.DIM) .. L["no price"] .. "|r" end },
	}, {
		sortKey = "name", rowHeight = 20,
		onClick = function(row, _, widget) M:PinMenu(widget, row.id) end,
		empty = { L["Nothing pinned"], L["Pin a recipe in your profession window, in the Loot Guide's Crafting page or with Alt-click in Alts > Professions."] },
	})
	frame.pins:SetPoint("TOPLEFT")
	frame.pins:SetPoint("TOPRIGHT")
	frame.pins:SetHeight(180)
	frame.caption = Kit.Text(frame, 12, "LEFT", "header")
	frame.caption:SetPoint("TOPLEFT", frame.pins, "BOTTOMLEFT", 4, -10)
	frame.caption:SetText(L["Reagents"])
	frame.send = Kit.Button(frame, L["Send to Shopping"], 150, nil, function(button) M:SendAndTell(button) end,
		L["Send to Shopping"], L["Puts every missing reagent on the auction house shopping list \"Profession Planner\". You still search and buy yourself."])
	frame.send:SetPoint("TOPRIGHT", frame.pins, "BOTTOMRIGHT", -4, -6)
	frame.clear = Kit.Button(frame, L["Unpin all"], 100, nil, function() M:ConfirmClearPins() end, L["Unpin all"], L["Takes every recipe off the shopping list."])
	frame.clear:SetPoint("RIGHT", frame.send, "LEFT", -6, 0)
	frame.reagents = Kit.CreateTable(frame, {
		{ key = "name", title = L["Reagent"], value = function(row) return row.name end },
		{ key = "have", title = L["Have"], width = 70, align = "RIGHT", value = function(row) return row.have end,
			color = function(row) return unpack(row.missing == 0 and Kit.GOOD or Kit.TEXT) end },
		{ key = "need", title = L["Need"], width = 70, align = "RIGHT", value = function(row) return row.need end },
		{ key = "price", title = L["Price"], width = 130, align = "RIGHT", value = function(row) return row.price or -1 end,
			text = function(row) return row.price and M.Money(row.price) or Hex(Kit.DIM) .. L["no price"] .. "|r" end },
	}, {
		sortKey = "missing", sortDown = true, rowHeight = 18,
		createRow = function(widget)
			widget:HookScript("OnEnter", function(own)
				if not own.item then return end
				GameTooltip:SetOwner(own, "ANCHOR_RIGHT")
				if GameTooltip.SetItemByID then GameTooltip:SetItemByID(own.item.id) end
				GameTooltip:Show()
			end)
			widget:HookScript("OnLeave", GameTooltip_Hide)
		end,
		empty = { L["No reagents"], L["Reagents of the pinned recipes show here with what you have."] },
	})
	frame.reagents:SetPoint("TOPLEFT", frame.pins, "BOTTOMLEFT", 0, -36)
	frame.reagents:SetPoint("BOTTOMRIGHT")
	return frame
end

local function RefreshList(frame)
	frame.pins:SetData(PinRows())
	frame.reagents:SetData(ReagentRows())
	frame.send:SetEnabled(#M:Missing() > 0)
	frame.clear:SetEnabled(#M:Pins() > 0)
end

-- Leveling plan
local TARGETS = { 75, 150, 225, 300 }

local function PlanState()
	local store = WindowStore()
	store.plan = type(store.plan) == "table" and store.plan or {}
	return store.plan
end

local function CraftingProfessions()
	local LG = E.LootGuide
	local list = {}
	for _, prof in ipairs(LG and LG.PROFESSIONS or {}) do
		if not prof.gathering and not prof.class then list[#list + 1] = prof end
	end
	return list
end

local function MySkill(skill)
	local LG = E.LootGuide
	local player = LG and LG.Player and LG:Player()
	return player and player.professions and player.professions[skill]
end

local function BuildPlan(content)
	local frame = CreateFrame("Frame", nil, content)
	frame:SetAllPoints()
	frame.bar = CreateFrame("Frame", nil, frame)
	frame.bar:SetPoint("TOPLEFT")
	frame.bar:SetPoint("TOPRIGHT")
	frame.bar:SetHeight(26)
	frame.prof = Kit.Button(frame.bar, "", 160, nil, function(button)
		E.UIKit.ContextMenu(button, function(_, root)
			root:CreateTitle(L["Profession"])
			for _, prof in ipairs(CraftingProfessions()) do
				local rank = MySkill(prof.id)
				local label = E.LootGuide:ProfessionName(prof.id) .. (rank and (" (" .. rank .. ")") or "")
				root:CreateRadio(label, function() return PlanState().skill == prof.id end, function()
					PlanState().skill = prof.id
					M:RefreshWindow()
				end)
			end
		end, { at = "owner" })
	end, L["Profession"], L["The profession to plan. Your own professions show their skill."])
	frame.prof:SetPoint("LEFT", 4, 0)
	frame.target = Kit.Button(frame.bar, "", 120, nil, function(button)
		E.UIKit.ContextMenu(button, function(_, root)
			root:CreateTitle(L["Target skill"])
			for _, value in ipairs(TARGETS) do
				root:CreateRadio(tostring(value), function() return PlanState().target == value end, function()
					PlanState().target = value
					M:RefreshWindow()
				end)
			end
		end, { at = "owner" })
	end, L["Target skill"], L["The skill to reach. The plan starts at your skill (or 1 when you don't have the profession)."])
	frame.target:SetPoint("LEFT", frame.prof, "RIGHT", 6, 0)
	frame.pin = Kit.Button(frame.bar, L["Pin this plan"], 120, nil, function(button)
		local count = M:PinPlan(frame.plan)
		Kit.Toast(button, E:Plural(count, "%d recipe pinned.", "%d recipes pinned."):format(count))
	end, L["Pin this plan"], L["Pins every recipe of the plan with its number of crafts, so the shopping list shows the reagents."])
	frame.pin:SetPoint("RIGHT", -4, 0)
	frame.summary = Kit.Text(frame, 12, "LEFT")
	frame.summary:SetPoint("TOPLEFT", frame.bar, "BOTTOMLEFT", 4, -6)
	frame.summary:SetPoint("TOPRIGHT", frame.bar, "BOTTOMRIGHT", -4, -6)
	frame.note = Kit.Text(frame, 10, "LEFT", "dim")
	frame.note:SetPoint("TOPLEFT", frame.summary, "BOTTOMLEFT", 0, -4)
	frame.note:SetPoint("TOPRIGHT", frame.summary, "BOTTOMRIGHT", 0, -4)
	frame.note:SetWordWrap(true)
	frame.note:SetText(L["Colors come from your profession window where you opened it, else from Classic's usual steps; crafts per point follow the public Classic chance. Both are estimates. Prices are EldoUI's saved auction and vendor prices."])
	frame.steps = Kit.CreateTable(frame, {
		{ key = "from", title = L["Skill"], width = 90, value = function(row) return row.from end,
			text = function(row) return ("%d-%d"):format(row.from, row.to) end },
		{ key = "name", title = L["Recipe"], value = function(row) return row.name end,
			text = function(row)
				local LG = E.LootGuide
				local color = LG and LG.BAND_COLORS and LG.BAND_COLORS[row.band] or Kit.TEXT
				return Kit.Hex(unpack(color)) .. row.name .. "|r" .. (row.known and "" or ("  " .. Hex(Kit.WARN) .. L["Learn"] .. "|r"))
			end },
		{ key = "crafts", title = L["Crafts"], width = 70, align = "RIGHT", value = function(row) return row.crafts end,
			text = function(row) return "~" .. row.crafts end },
		{ key = "cost", title = L["Cost"], width = 140, align = "RIGHT", value = function(row) return row.cost or -1 end,
			text = function(row) return row.cost and M.Money(row.cost) or Hex(Kit.DIM) .. L["no price"] .. "|r" end },
	}, {
		sortKey = "from", rowHeight = 18,
		onClick = function(row, _, widget) M:PinMenu(widget, row.id) end,
		empty = { L["No plan"], L["Pick a profession and a target skill. The plan needs EldoUI_LootData or recipes you saw in your profession window."] },
	})
	frame.steps:SetPoint("TOPLEFT", frame.note, "BOTTOMLEFT", -4, -8)
	frame.steps:SetPoint("BOTTOMRIGHT")
	return frame
end

local function RefreshPlan(frame)
	local state = PlanState()
	local list = CraftingProfessions()
	if not state.skill then
		for _, prof in ipairs(list) do
			if not state.skill and MySkill(prof.id) then state.skill = prof.id end
		end
		state.skill = state.skill or (list[1] and list[1].id)
	end
	state.target = state.target or 300
	local LG = E.LootGuide
	frame.prof:SetText(state.skill and LG and LG:ProfessionName(state.skill) or L["Profession"])
	frame.target:SetText((L["To %d"]):format(state.target))
	local from = MySkill(state.skill) or 1
	local plan = M:Plan(state.skill, from, state.target)
	frame.plan = plan
	local rows = {}
	for _, step in ipairs(plan.steps) do
		rows[#rows + 1] = { id = step.recipe.id, from = step.from, to = step.to, name = M:Recipe(step.recipe.id) and M:Recipe(step.recipe.id).name or ("#" .. step.recipe.id),
			crafts = step.crafts, cost = step.cost, band = step.band, known = step.known }
	end
	frame.steps:SetData(rows)
	frame.pin:SetEnabled(#rows > 0)
	local text
	if from >= state.target then
		text = (L["Your skill is already %d."]):format(from)
	elseif #rows == 0 then
		text = L["No recipes known for this range."]
	else
		text = (L["From %d to %d: %s"]):format(from, state.target, M.Money(plan.total))
		if plan.unpriced > 0 then text = text .. "  " .. Hex(Kit.WARN) .. E:Plural(plan.unpriced, "(%d step has no price)", "(%d steps have no price)"):format(plan.unpriced) .. "|r" end
		if #plan.gaps > 0 then text = text .. "  " .. Hex(Kit.WARN) .. (L["No recipe for %d-%d"]):format(plan.gaps[1].from, plan.gaps[1].to) .. "|r" end
	end
	frame.summary:SetText(text)
end

function M:CreateWindow()
	if self.window then return self.window end
	self.window = Kit.CreateTabbedWindow({
		name = "EldoUI_ProfessionPlanner",
		options = { page = "module:ProfessionPlanner" },
		title = L["Profession Planner"],
		width = 760, height = 520,
		store = WindowStore,
		tabs = {
			{ key = "list", title = L["Shopping list"], desc = L["Pinned recipes and every reagent with what you have."],
				count = function() return #M:Pins() end,
				create = BuildList, show = RefreshList, refresh = RefreshList },
			{ key = "plan", title = L["Leveling plan"], desc = L["The cheapest recipes to level a profession, from your saved prices."],
				create = BuildPlan, show = RefreshPlan, refresh = RefreshPlan },
		},
		help = { text = L["Pin recipes to see their reagents with what you have on all your characters. At the auction house, Send to Shopping fills a shopping list; you still search and buy yourself."] },
		footer = function()
			local missing = #M:Missing()
			return missing > 0 and E:Plural(missing, "%d reagent to get", "%d reagents to get"):format(missing) or L["Everything is there."]
		end,
	})
	return self.window
end

function M:OpenWindow(tab)
	if not self.active then return end
	self:CreateWindow():Open(tab or "list")
end

function M:RefreshWindow()
	if self.window and self.window:IsOpen() then self.window:Refresh() end
end

function M:Redraw()
	self:RefreshTracker()
	self:RefreshWindow()
	if self.UpdateHooks then self:UpdateHooks() end
end

---------------------------------------------------------------------------
-- Pin buttons
---------------------------------------------------------------------------
local blizzard = {}

local function SchematicRecipe()
	local frame = rawget(_G, "ProfessionsFrame")
	local page = frame and frame.CraftingPage
	local form = page and page.SchematicForm
	if not (form and form.GetRecipeInfo) then return nil, form end
	local ok, info = pcall(form.GetRecipeInfo, form)
	local id = ok and type(info) == "table" and tonumber(info.recipeID)
	return id, form
end

local function BlizzardAllowed()
	return M.active and M.db.blizzardPin and E:BlizzardAllowed("professions", "improve")
end

function M:UpdateBlizzardPin()
	local button = blizzard.button
	if not button then return end
	local id = SchematicRecipe()
	if not (BlizzardAllowed() and id) then
		button:Hide()
		return
	end
	local pin = self:IsPinned(id)
	button:SetText(pin and (L["Pinned x%d"]):format(pin.qty) or L["Pin"])
	Kit.FitButton(button, 70)
	button:Show()
end

local function HookProfessions()
	if blizzard.hooked then return end
	local _, form = SchematicRecipe()
	if not form then return end
	blizzard.hooked = true
	local button = Kit.Button(form, L["Pin"], 70, nil, function(self)
		local id = SchematicRecipe()
		if not id then return end
		M:PinMenu(self, id, M:ReadSchematic(id))
	end, L["Pin to the shopping list"], L["Adds this recipe to the Profession Planner's shopping list with a number of crafts. Nothing is crafted."])
	button:SetPoint("TOPRIGHT", form, "TOPRIGHT", -8, -8)
	button:SetFrameLevel(form:GetFrameLevel() + 10)
	blizzard.button = button
	if form.Init then hooksecurefunc(form, "Init", function() M:UpdateBlizzardPin() end) end
	form:HookScript("OnShow", function() M:UpdateBlizzardPin() end)
	M:UpdateBlizzardPin()
end
M.HookProfessions = HookProfessions

-- Loot Guide > Crafting details: a Pin line (LG.craftDetailExtras).
local function LootGuideExtra(flow, craft, P)
	if not (M.active and M.db.otherPins and craft and craft.id) then return end
	local pin = M:IsPinned(craft.id)
	local text = pin and (L["On your shopping list: %d crafts"]):format(pin.qty) or L["Shopping list"]
	P.FlowLine(flow, text, nil, { pin and L["Change"] or L["Pin"], function(button)
		M:PinMenu(button, craft.id, { result = craft.result, count = craft.count, reagents = craft.reagents, skill = craft.skill, rank = craft.rank })
	end, L["Pin to the shopping list"], L["Adds this recipe to the Profession Planner's shopping list with a number of crafts. Nothing is crafted."] })
end

-- Alts > Professions: recipe rows get a tooltip line and Alt-click pins
-- the recipe, through the Characters recipe row hook.
local function AltsHook()
	return {
		tooltip = function(tooltip, spellID)
			if not (M.active and M.db.otherPins) or type(spellID) ~= "number" then return end
			local pin = M:IsPinned(spellID)
			if pin then Kit.TipText(tooltip, E:Plural(pin.qty, "On your shopping list: %d craft.", "On your shopping list: %d crafts."):format(pin.qty)) end
			E:TooltipHint(tooltip, { L["Alt-click"], pin and L["change the number of crafts"] or L["pin to the shopping list"] })
		end,
		click = function(_, spellID, _, widget)
			if not (IsAltKeyDown() and M.active and M.db.otherPins and type(spellID) == "number") then return false end
			M:PinMenu(widget, spellID)
			return true
		end,
	}
end

function M:InstallHooks()
	if not self.hooksInstalled then
		self.hooksInstalled = true
		local LG = E.LootGuide
		if LG then
			LG.craftDetailExtras = LG.craftDetailExtras or {}
			table.insert(LG.craftDetailExtras, LootGuideExtra)
		end
		local chars = E.modules.Characters
		if chars and chars.RegisterRecipeRowHook then chars:RegisterRecipeRowHook("professionPlanner", AltsHook()) end
		E:RegisterEvent("ADDON_LOADED", function(_, _, addon)
			if addon == "Blizzard_Professions" then HookProfessions() end
		end, "ProfessionPlanner.pins")
	end
	if C_AddOns.IsAddOnLoaded("Blizzard_Professions") then HookProfessions() end
	self:UpdateHooks()
end

function M:UpdateHooks()
	self:UpdateBlizzardPin()
end
