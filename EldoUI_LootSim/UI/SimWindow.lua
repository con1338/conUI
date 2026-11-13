-- EldoUI Loot Sim: the simulator window.
--
--   +----------------------------------------------------------------+
--   | Simulator                                                   x  |
--   | Estimates from fights against a target dummy ...               |
--   |================================================================|
--   | Target [Same level] [+1] [+2] [Boss]   Fight [1 min] [3] [5]   |
--   | [Character] [Planner] [Sets]                                   |
--   | (note: Weights mode, combat, no pet ...)                       |
--   | ...tab content...                                              |
--   |----------------------------------------------------------------|
--   | [=====progress=====] Best in Slot run 42 %       [Stop] [Sim]  |
--   +----------------------------------------------------------------+
--
-- Character: DPS ± error, damage per ability, the value of one more point
--   of each stat and what was read (stats, talents the sim plays, other
--   talents, spells it does not simulate and why, enchants, buffs, pet).
-- Planner: the two plan sets the Best in Slot page shows; click a slot to
--   pick an item (search, higher levels), drop an item from your bags on a
--   slot, start from what you wear or from Best in Slot, or empty the set.
-- Sets: what you wear, Best in Slot and the plan sets as bars from the same
--   fights, with check boxes for the ones to run.
-- Sim (bottom right) reads your character again and runs the shown tab.
-- Built on E.WindowKit.CreateWindow, resizable and draggable; geometry in
-- EldoUIDB.lootGuideCache.simWindow.
local _, S = ...
local E = S.E
local LG = E.LootGuide
local L = E.L
local Kit = LG.Kit
local P = LG.PageKit
local WK = E.WindowKit

local Window = {}
S.Window = Window

local WIDTH, HEIGHT = 720, 560
local MIN_W, MIN_H = 600, 440
local ALL_SLOTS = { 1, 2, 3, 15, 5, 9, 10, 6, 7, 8, 11, 12, 13, 14, 16, 17, 18 }
local TABS = { "char", "planner", "sets" }
local TAB_TITLES = { char = L["Character"], planner = L["Planner"], sets = L["Sets"] }
local TAB_TIPS = {
	char = L["Your DPS with what you wear, the damage of each ability, what one more point of each stat is worth, and what the simulator read."],
	planner = L["Your two plan sets (the same as on the Best in Slot page). Click a slot to pick an item or drop one from your bags."],
	sets = L["What you wear, Best in Slot and your plan sets compared as DPS from the same fights."],
}
local TARGET_TITLES = { same = L["Same level"], plus1 = L["+1 level"], plus2 = L["+2 levels"], boss = L["Boss (+3)"] }
-- Stat names as the value list shows them, and without the "(1 %)" for the
-- short list of what was read.
local STAT_NAMES = {
	str = L["Strength"], agi = L["Agility"], ap = L["Attack power"], crit = L["Crit chance (1 %)"], hit = L["Hit chance (1 %)"],
	sp = L["Spell power"], spellCrit = L["Spell crit (1 %)"], spellHit = L["Spell hit (1 %)"], int = L["Intellect"],
	rap = L["Ranged attack power"], spellPower = L["Spell power"], mana = L["Mana"],
}
local STAT_SHORT = {
	crit = L["Crit chance"], hit = L["Hit chance"], spellCrit = L["Spell crit"], spellHit = L["Spell hit"],
}
local SOURCE_NAMES = {
	melee = L["Melee swings"], offhand = L["Off-hand swings"], windfury = L["Windfury Weapon"], autoShot = L["Auto Shot"],
	pet = L["Pet"], poison = L["Poison"], fiery = L["Fiery Weapon"], lifesteal = L["Lifestealing"], deepWounds = L["Deep Wounds"], ignite = L["Ignite"],
	sealOfCommand = L["Seal of Command"], sealOfRighteousness = L["Seal of Righteousness"],
}
local ENCHANT_NAMES = {
	crusader = L["Crusader"], fiery = L["Fiery Weapon"], lifesteal = L["Lifestealing"], windfury = L["Windfury"], poison = L["Poison"], flametongue = L["Flametongue"],
	frostbrand = L["Frostbrand"], rockbiter = L["Rockbiter"], stone = L["Sharpening stone"], oil = L["Wizard oil"],
}
local REASON_DETAIL = {
	noPet = L["Your pet is not out. Call it and press Sim again."],
	catForm = L["You are not in Cat Form. Shift and press Sim again."],
	bearForm = L["You are not in Bear Form. Shift and press Sim again."],
}

local window

local function Secret(value)
	return issecretvalue and issecretvalue(value)
end

local function UI()
	return LG:UI()
end

local function Hex(color)
	return Kit.Hex(color[1], color[2], color[3])
end

---------------------------------------------------------------------------
-- Geometry
---------------------------------------------------------------------------
local function SaveGeometry()
	if not window then return end
	local left, top = window:GetLeft(), window:GetTop()
	if not left or not top then return end
	LG:Cache().simWindow = { x = math.floor(left + 0.5), y = math.floor(top + 0.5),
		w = math.floor(window:GetWidth() + 0.5), h = math.floor(window:GetHeight() + 0.5) }
end

local function ApplyGeometry()
	local geo = LG:Cache().simWindow
	window:ClearAllPoints()
	if type(geo) == "table" and tonumber(geo.x) and tonumber(geo.y) then
		window:SetSize(math.max(MIN_W, tonumber(geo.w) or WIDTH), math.max(MIN_H, tonumber(geo.h) or HEIGHT))
		window:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", geo.x, geo.y)
	else
		window:SetSize(WIDTH, HEIGHT)
		window:SetPoint("CENTER", 0, 40)
	end
end

---------------------------------------------------------------------------
-- Flow blocks: a bar with a label and a value
---------------------------------------------------------------------------
local function BarBlock(child)
	local block = CreateFrame("Frame", nil, child)
	block.label = Kit.Text(block, 12, "LEFT")
	block.label:SetPoint("TOPLEFT", 0, 0)
	block.label:SetWordWrap(false)
	block.value = Kit.Text(block, 12, "RIGHT")
	block.value:SetPoint("TOPRIGHT", -4, 0)
	block.label:SetPoint("TOPRIGHT", block.value, "TOPLEFT", -8, 0)
	block.bar = E:CreateStatusBar(block)
	block.bar:SetHeight(6)
	block.bar:SetPoint("TOPLEFT", 0, -17)
	block.bar:SetPoint("TOPRIGHT", -4, -17)
	block.bar:SetMinMaxValues(0, 1)
	block.sub = Kit.Text(block, 10, "LEFT", "secondary")
	block.sub:SetPoint("TOPLEFT", block.bar, "BOTTOMLEFT", 0, -4)
	block.sub:SetPoint("TOPRIGHT", block.bar, "BOTTOMRIGHT", 0, -4)
	block.sub:SetWordWrap(false)
	return block
end

local function FlowBar(flow, label, value, fraction, sub, indent)
	local block = flow:Take("bar", BarBlock)
	flow:Place(block, sub and 38 or 26, indent, 4)
	block.label:SetText(label or "")
	block.value:SetText(value or "")
	block.bar:SetValue(math.max(0, math.min(1, fraction or 0)))
	block.bar:SetStatusBarColor(Kit.Accent())
	block.sub:SetText(sub or "")
	block.sub:SetShown(sub ~= nil)
	return block
end

local function CheckBlock(child)
	local block = CreateFrame("Frame", nil, child)
	block.check = WK.Check(block, "", nil, function(on)
		if block.onToggle then block.onToggle(on) end
	end)
	block.check:SetPoint("LEFT", -2, 0)
	return block
end

---------------------------------------------------------------------------
-- Names
---------------------------------------------------------------------------
local function ItemName(itemID)
	local name, _, quality = C_Item.GetItemInfo(itemID)
	if Secret(name) then name = nil end
	if not name then
		local record = LG:ItemRecord(itemID)
		name, quality = record and record.name, record and record.quality
	end
	local r, g, b = Kit.QualityColor(quality)
	return Kit.Hex(r, g, b) .. (name or ("item:" .. tostring(itemID))) .. "|r"
end

local function SourceName(key, report)
	if SOURCE_NAMES[key] then return SOURCE_NAMES[key] end
	for _, spell in ipairs(report and report.spells or {}) do
		if spell.key == key and spell.name then return spell.name end
	end
	return key
end

local function Stale(record)
	return record and record.key ~= LG:SimSetupKey(LG:SimSettings(record.length))
end

---------------------------------------------------------------------------
-- Character tab
---------------------------------------------------------------------------
local function List(items)
	if not items or #items == 0 then return "|cffa6a6a6" .. L["none"] .. "|r" end
	return table.concat(items, ", ")
end

local function DrawChar(flow)
	local store = LG:SimStore()
	local record = store.char
	if not record then
		P.FlowText(flow, L["Press Sim to read your character and fight a target dummy 120 times. It takes a few seconds and runs out of combat."], 12, "secondary")
		return
	end
	local report = record.report or {}
	local block = flow:Take("big", function(child)
		local frame = CreateFrame("Frame", nil, child)
		frame.text = Kit.Text(frame, 22, "LEFT")
		frame.text:SetPoint("TOPLEFT", 0, -2)
		frame.note = Kit.Text(frame, 11, "LEFT", "secondary")
		frame.note:SetPoint("LEFT", frame.text, "RIGHT", 10, -2)
		return frame
	end)
	flow:Place(block, 30, 0, 2)
	E:SetFont(block.text, 22)
	block.text:SetText(L["%.1f DPS  |cffa6a6a6± %.1f|r"]:format(record.dps or 0, record.err or 0))
	local target = (L["target level %d"]):format(record.targetLevel or 0)
	block.note:SetText(("%s · %s · %s"):format(L["estimate"], target, (L["%d s fights"]):format(record.length or 0))) -- no-plural: seconds
	if Stale(record) then
		P.FlowText(flow, Hex(Kit.WARN) .. L["Outdated: your gear, talents, level or the fight settings changed since this run. Press Sim to run it again."] .. "|r", 11)
	end
	if report.variantTitle then
		P.FlowText(flow, (L["Rotation: %s"]):format(report.variantTitle), 11, "secondary")
	end
	-- Damage per ability.
	P.FlowCaption(flow, L["Damage per ability"])
	local sources = {}
	for key, entry in pairs(record.sources or {}) do
		if (entry.dps or 0) > 0 then sources[#sources + 1] = { key = key, entry = entry } end
	end
	table.sort(sources, function(a, b) return a.entry.dps > b.entry.dps end)
	local top = sources[1] and sources[1].entry.dps or 1
	for _, source in ipairs(sources) do
		local entry = source.entry
		local casts = entry.count or 0
		local crit = casts > 0 and (entry.crits or 0) / casts * 100 or 0
		local sub = (L["%.1f a fight · %.0f %% crit · %.1f missed"]):format(casts, crit, entry.misses or 0)
		FlowBar(flow, SourceName(source.key, report), ("%.1f  |cffa6a6a6%.0f %%|r"):format(entry.dps, (entry.share or 0) * 100), entry.dps / top, sub)
	end
	-- Stat values.
	if record.values and #record.values > 0 then
		P.FlowCaption(flow, L["One more point is worth"], L["DPS, with a 95 % range"])
		for _, value in ipairs(record.values) do
			P.FlowLine(flow, L["%s  %s%+.2f DPS|r  |cffa6a6a6± %.2f|r"]:format(STAT_NAMES[value.stat] or value.stat, Hex(Kit.GOOD), value.perPoint or 0, value.err or 0), nil, nil,
				STAT_NAMES[value.stat] or value.stat, (L["Measured by adding %d to your sheet and running the same fights. Per point of the stat."]):format(value.amount or 0))
		end
	end
	-- What was read.
	P.FlowCaption(flow, L["What was read"], L["only your own character sheet"])
	local stats = {}
	for _, pair in ipairs(report.stats or {}) do
		local value = tonumber(pair[2]) or 0
		local text = (pair[1] == "crit" or pair[1] == "hit" or pair[1] == "spellHit") and ("%.1f %%"):format(value) or tostring(math.floor(value + 0.5))
		stats[#stats + 1] = (STAT_SHORT[pair[1]] or STAT_NAMES[pair[1]] or pair[1]) .. " " .. text
	end
	P.FlowText(flow, Hex(Kit.SECONDARY) .. L["Stats"] .. ":|r " .. List(stats), 11)
	P.FlowText(flow, Hex(Kit.SECONDARY) .. L["Talents the simulator plays"] .. ":|r " .. List(report.talentsPlayed), 11)
	P.FlowText(flow, Hex(Kit.SECONDARY) .. L["Other talents"] .. ":|r " .. List(report.talentsOther), 11)
	local enchants = {}
	for _, kind in ipairs(report.enchants or {}) do enchants[#enchants + 1] = ENCHANT_NAMES[kind] or kind end
	P.FlowText(flow, Hex(Kit.SECONDARY) .. L["Weapon enchants"] .. ":|r " .. List(enchants), 11)
	if report.tempEnchantsUnknown then
		P.FlowText(flow, L["This game client does not tell add-ons about poisons, oils and other temporary weapon enchants, so they are not counted."], 11, "dim")
	end
	P.FlowText(flow, Hex(Kit.SECONDARY) .. L["Buffs counted"] .. ":|r " .. List(report.buffs), 11)
	if report.pet then P.FlowText(flow, Hex(Kit.SECONDARY) .. L["Pet"] .. ":|r " .. report.pet, 11) end
	if report.skillEstimated then
		P.FlowText(flow, L["The game did not show your weapon skill, so the simulator used the usual skill for your level (5 per level)."], 11, "dim")
	end
	if report.talentsByName == false and #(report.talentsOther or {}) > 0 then
		P.FlowText(flow, Hex(Kit.WARN) .. L["Talents are read by name, which works on English game clients only. On this client the simulator plays without talent effects."] .. "|r", 11)
	end
	local skipped = report.notSimulated or {}
	if #skipped > 0 then
		P.FlowText(flow, Hex(Kit.SECONDARY) .. L["Spells not simulated"] .. ":|r", 11)
		for _, entry in ipairs(skipped) do
			P.FlowText(flow, ("%s  |cffa6a6a6%s|r"):format(entry.name or "?", L[entry.reason or ""]), 11, nil, 12, 2)
		end
	end
	P.FlowText(flow, L["Set bonuses and item procs (\"Chance on hit\") are not counted. The target dummy does not hit back."], 11, "dim")
end

---------------------------------------------------------------------------
-- Planner tab
---------------------------------------------------------------------------
local function PlanIndex()
	local index = tonumber(UI().simPlan) or 1
	return (index == 2) and 2 or 1
end

local function PlanSlots()
	local data = LG:Char()
	return data and data.sets[PlanIndex()].slots or {}
end

local function IsTwoHander(itemID)
	local equipLoc = itemID and select(4, C_Item.GetItemInfoInstant(itemID))
	return not Secret(equipLoc) and equipLoc == "INVTYPE_2HWEAPON"
end

local function PutInSlot(slot, itemID)
	local slots = PlanSlots()
	if itemID and itemID ~= 0 then
		local fits = LG:ItemSlots(itemID)
		local ok = false
		for _, s in ipairs(fits or {}) do if s == slot then ok = true end end
		if not ok then
			E:Print(L["That item does not go in this slot."])
			return
		end
		slots[slot] = itemID
		if slot == 16 and IsTwoHander(itemID) then slots[17] = nil end
		if slot == 17 and IsTwoHander(slots[16]) then slots[16] = nil end
	else
		slots[slot] = nil
	end
	LG:Fire("sets")
	Window.Draw()
end

local picker

local function PickerRowCreate(row)
	row.cell = P.ItemCell(row)
	row.cell:SetAllPoints()
end

local function PickerRowUpdate(row, item)
	if item.none then
		P.SetItem(row.cell, { itemID = 0, sub = L["Leaves the slot empty"] })
		row.cell.name:SetText(L["None"])
		Kit.Paint(row.cell.name, "secondary")
		row.cell.icon:SetTexture(134400)
		row.cell.right:SetText("")
		row.cell.starButton:Hide()
		row.cell.data = { itemID = 0, onClick = function() PutInSlot(item.slot, nil) picker:Hide() end }
		row.cell:SetScript("OnClick", function() PutInSlot(item.slot, nil) picker:Hide() end)
		return
	end
	local bits = {}
	if item.source and item.source ~= "" then bits[#bits + 1] = item.source end
	if item.useLevel and item.useLevel > LG:Player().level then bits[#bits + 1] = (L["from level %d"]):format(item.useLevel) end
	if not S.Gear.Stats(item.itemID) then bits[#bits + 1] = Hex(Kit.WARN) .. L["no numbers yet"] .. "|r" end
	P.SetItem(row.cell, { itemID = item.itemID, sub = table.concat(bits, " · "), dim = not item.onList,
		onClick = function() PutInSlot(item.slot, item.itemID) picker:Hide() end })
end

local function BuildPicker()
	if picker then return picker end
	picker = CreateFrame("Frame", nil, window)
	picker:SetSize(330, 360)
	picker:SetFrameLevel(window:GetFrameLevel() + 40)
	picker:EnableMouse(true)
	E:SetTemplate(picker)
	picker:Hide()
	picker.title = Kit.Text(picker, 13, "LEFT", "header")
	picker.title:SetPoint("TOPLEFT", 10, -8)
	picker.close = CreateFrame("Button", nil, picker, "UIPanelCloseButton")
	picker.close:SetPoint("TOPRIGHT", -2, -2)
	E:SkinCloseButton(picker.close)
	picker.close:SetScript("OnClick", function() picker:Hide() end)
	picker.search = CreateFrame("EditBox", nil, picker, "SearchBoxTemplate")
	picker.search:SetSize(200, 20)
	picker.search:SetPoint("TOPLEFT", 12, -30)
	picker.search:SetAutoFocus(false)
	E:SkinEditBox(picker.search)
	Kit.Tooltip(picker.search, L["Search"], L["Filters the rows by item name and source."])
	picker.search:HookScript("OnTextChanged", function() if picker:IsShown() then picker:Draw() end end)
	picker.higher = P.Toggle(picker, L["Higher levels"], function()
		UI().simHigher = not UI().simHigher
		picker:Draw(true)
	end, L["Higher levels"], L["Also lists items above your level, to plan ahead. Saved for this character."])
	picker.higher:SetPoint("LEFT", picker.search, "RIGHT", 8, 0)
	picker.notice = Kit.Text(picker, 11, "LEFT", "secondary")
	picker.notice:SetPoint("BOTTOMLEFT", 10, 8)
	picker.notice:SetPoint("BOTTOMRIGHT", -10, 8)
	picker.list = Kit.CreateList(picker, { create = PickerRowCreate, update = PickerRowUpdate, gap = 2 })
	picker.list:SetPoint("TOPLEFT", 8, -58)
	picker.list:SetPoint("BOTTOMRIGHT", -8, 26)
	function picker:Draw(rebuild)
		local higher = UI().simHigher and true or false
		if rebuild or not self.rows or self.rowsSlot ~= self.slot or self.rowsHigher ~= higher then
			self.rows = LG.BiSFlyoutRows and LG:BiSFlyoutRows(self.slot, higher) or {}
			self.rowsSlot, self.rowsHigher = self.slot, higher
		end
		local text = (self.search:GetText() or ""):lower()
		local shown = { { none = true, slot = self.slot } }
		for _, row in ipairs(self.rows) do
			row.slot = self.slot
			if text == "" or (row.name or ""):lower():find(text, 1, true) or (row.source or ""):lower():find(text, 1, true) then
				shown[#shown + 1] = row
			end
		end
		self.title:SetText(("%s  |cffa6a6a6%d|r"):format(LG:SlotLabel(self.slot), #self.rows))
		self.higher:SetOn(higher)
		self.list:SetData(shown)
		self.notice:SetText(#self.rows == 0 and L["Nothing fits: turn on Higher levels, or install EldoUI_LootData for the full item list."]
			or L["Dimmed items are not on your loot list (Best in Slot > Filter)."])
	end
	return picker
end

local function OpenPicker(anchor, slot)
	BuildPicker()
	picker.slot = slot
	picker.search:SetText("")
	picker:ClearAllPoints()
	picker:SetPoint("TOPLEFT", anchor, "TOPRIGHT", -120, 0)
	picker:Draw(true)
	picker:Show()
end

local function SlotBlock(child)
	local row = CreateFrame("Button", nil, child)
	row.slotName = Kit.Text(row, 11, "LEFT", "secondary")
	row.slotName:SetPoint("LEFT", 4, 0)
	row.slotName:SetWidth(90)
	row.slotName:SetWordWrap(false)
	row.cell = P.ItemCell(row)
	row.cell:SetPoint("TOPLEFT", 98, 0)
	row.cell:SetPoint("BOTTOMRIGHT")
	row.empty = Kit.Text(row, 12, "LEFT", "dim")
	row.empty:SetPoint("LEFT", 98, 0)
	row.hover = row:CreateTexture(nil, "HIGHLIGHT")
	row.hover:SetAllPoints()
	row.hover:SetColorTexture(1, 1, 1, 0.04)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	local function Drop(self)
		local kind, itemID = GetCursorInfo()
		if kind ~= "item" or Secret(itemID) then return end
		ClearCursor()
		PutInSlot(self.slot, tonumber(itemID))
	end
	row:SetScript("OnReceiveDrag", Drop)
	row.cell:SetScript("OnReceiveDrag", function() Drop(row) end)
	row:SetScript("OnClick", function(self, button)
		if GetCursorInfo() then Drop(self) return end
		if button == "RightButton" then PutInSlot(self.slot, nil) return end
		OpenPicker(self, self.slot)
	end)
	Kit.Tooltip(row, L["Slot"], L["Click to pick an item, right-click to empty the slot. You can also drop an item from your bags here."])
	return row
end

local function CopyInto(items)
	local slots = PlanSlots()
	wipe(slots)
	for _, slot in ipairs(ALL_SLOTS) do slots[slot] = items and items[slot] or nil end
	LG:Fire("sets")
	Window.Draw()
end

-- The plan set is shared with the Best in Slot page, so a set that holds
-- items is only replaced after a question. An empty set fills at once.
local function ReplaceSet(question, items)
	if next(PlanSlots()) == nil then
		CopyInto(items())
		return
	end
	E:ShowConfirm({ key = "ELDOUI_LOOTSIM_REPLACE", title = L["Simulator"],
		text = question:format(E:Highlight(LG:SetName(PlanIndex()))) .. "\n" .. L["The set is shared with the Best in Slot page. This can't be undone."],
		accept = OKAY or L["OK"], danger = true,
		onAccept = function() CopyInto(items()) end })
end

local function DrawPlanner(flow)
	local index = PlanIndex()
	local row = flow:Take("plantools", function(child)
		local frame = CreateFrame("Frame", nil, child)
		frame.sets = {}
		for i = 1, 2 do
			frame.sets[i] = P.Toggle(frame, "", function()
				UI().simPlan = i
				Window.Draw()
			end, L["Plan set"], L["Your plan sets are shared with the Best in Slot page. Rename them there."])
			if i == 1 then frame.sets[i]:SetPoint("LEFT", 0, 0) else frame.sets[i]:SetPoint("LEFT", frame.sets[1], "RIGHT", 4, 0) end
		end
		frame.worn = Kit.Button(frame, L["From what I wear"], 120, 20, function()
			ReplaceSet(L["Replace the items in %s with your equipped gear?"], function() return LG:Player().equipped end)
		end, L["From what I wear"], L["Fills the set with your equipped gear."])
		frame.bis = Kit.Button(frame, L["From Best in Slot"], 120, 20, function()
			ReplaceSet(L["Replace the items in %s with the Best in Slot items?"], function() return LG:BiSSet(LG:PlanPhase()) or {} end)
		end, L["From Best in Slot"], L["Fills the set with the Best in Slot items (the simulated set in Simulator mode)."])
		frame.clear = Kit.Button(frame, L["Empty"], 70, 20, function()
			ReplaceSet(L["Remove every item from %s?"], function() return {} end)
		end, L["Empty"], L["Empties the set."])
		frame.clear:SetPoint("RIGHT", -4, 0)
		frame.bis:SetPoint("RIGHT", frame.clear, "LEFT", -6, 0)
		frame.worn:SetPoint("RIGHT", frame.bis, "LEFT", -6, 0)
		return frame
	end)
	flow:Place(row, 22, 0, 6)
	for i = 1, 2 do
		row.sets[i]:SetLabel(LG:SetName(i))
		row.sets[i]:SetOn(i == index)
	end
	local slots = PlanSlots()
	local noNumbers = {}
	for _, slot in ipairs(ALL_SLOTS) do
		local block = flow:Take("slot", SlotBlock)
		flow:Place(block, math.max(Kit.RowHeight(), 20), 0, 2)
		block.slot = slot
		block.slotName:SetText(LG:SlotLabel(slot))
		local itemID = slots[slot]
		if itemID then
			block.cell:Show()
			block.empty:Hide()
			local worn = LG:Player().equipped[slot]
			local sub = worn == itemID and L["you wear it"] or nil
			if not S.Gear.Stats(itemID) then
				noNumbers[#noNumbers + 1] = itemID
				sub = Hex(Kit.WARN) .. L["no numbers yet"] .. "|r"
			end
			P.SetItem(block.cell, { itemID = itemID, sub = sub, onClick = function() OpenPicker(block, slot) end })
		else
			block.cell:Hide()
			block.empty:Show()
			block.empty:SetText(L["empty: you keep what you wear"])
		end
	end
	if #noNumbers > 0 then
		P.FlowCaption(flow, L["No numbers yet"])
		local names = {}
		for _, itemID in ipairs(noNumbers) do names[#names + 1] = ItemName(itemID) end
		P.FlowText(flow, L["The simulator has no stats for these items, so sets with them are not simulated: "] .. table.concat(names, ", ")
			.. ". " .. L["Hover them once (the game then sends their stats) or install EldoUI_LootData."], 11, "secondary")
	end
	P.FlowText(flow, L["Sim runs your plan sets against what you wear; the Sets tab shows the result."], 11, "dim")
end

---------------------------------------------------------------------------
-- Sets tab
---------------------------------------------------------------------------
local function SetsShown()
	local ui = UI()
	if type(ui.simSets) ~= "table" then ui.simSets = {} end
	return ui.simSets
end

-- The sets the next Sets run compares (checked ones).
function Window.SetsToRun()
	local shown = SetsShown()
	local list = {}
	for _, entry in ipairs(LG:SimSetList()) do
		if shown[entry.key] ~= false then list[#list + 1] = entry end
	end
	return list
end

local function DrawSets(flow)
	local shown = SetsShown()
	P.FlowCaption(flow, L["Run these"])
	for _, entry in ipairs(LG:SimSetList()) do
		local block = flow:Take("check", CheckBlock)
		flow:Place(block, 22, 0, 0)
		block.check.label:SetText(entry.title)
		block.check:SetChecked(shown[entry.key] ~= false)
		Kit.Tooltip(block.check, entry.title, L["Checked sets run in the next Sets run, all in the same fights."])
		block.onToggle = function(on) shown[entry.key] = on end
	end
	local store = LG:SimStore()
	local sets = store.sets
	P.FlowCaption(flow, L["Results"], sets and L["estimate"] or nil)
	if not (sets and sets.results) then
		P.FlowText(flow, L["Press Sim to compare the checked sets in the same fights."], 12, "secondary")
		return
	end
	if Stale(sets) then
		P.FlowText(flow, Hex(Kit.WARN) .. L["Outdated: your gear, talents, level or the fight settings changed since this run."] .. "|r", 11)
	end
	local best, base = 0, nil
	for _, result in ipairs(sets.results) do
		if result.dps then
			best = math.max(best, result.dps)
			if result.key == "worn" then base = result.dps end
		end
	end
	local roomy = window and window:GetHeight() > 520
	for _, result in ipairs(sets.results) do
		if result.dps then
			local value = ("%.1f  |cffa6a6a6± %.1f|r"):format(result.dps, result.err or 0)
			if base and result.key ~= "worn" then
				local diff = result.dps - base
				value = value .. "  " .. Hex(diff >= 0 and Kit.GOOD or Kit.BAD) .. ("%+.1f"):format(diff) .. "|r"
			end
			local sub
			if roomy and result.sources then
				local parts = {}
				for key, entry in pairs(result.sources) do parts[#parts + 1] = { key = key, dps = entry.dps or 0 } end
				table.sort(parts, function(a, b) return a.dps > b.dps end)
				local words = {}
				for i = 1, math.min(3, #parts) do words[#words + 1] = ("%s %.0f"):format(SourceName(parts[i].key, store.char and store.char.report), parts[i].dps) end
				sub = table.concat(words, " · ")
			end
			FlowBar(flow, result.title or result.key, value, best > 0 and result.dps / best or 0, sub)
		else
			P.FlowText(flow, ("%s  %s"):format(result.title or result.key, Hex(Kit.WARN) .. L["not simulated: items without numbers"] .. "|r"), 12)
		end
	end
	P.FlowText(flow, L["The same fights (same dice) for every set, so the differences are steadier than the totals."], 11, "dim")
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------
local function Tab()
	local tab = UI().simTab
	for _, key in ipairs(TABS) do if key == tab then return tab end end
	return "char"
end

local function NoteText()
	local status = LG:SimStatus()
	if status == "paused" then
		return Hex(Kit.WARN) .. L["Paused for combat. The run goes on when combat ends."] .. "|r"
	end
	local reason = LG.simMessage
	if reason then
		return Hex(Kit.WARN) .. (REASON_DETAIL[reason] or LG.SIM_REASONS[reason] or L["The simulator could not start."]) .. "|r"
	end
	if not LG:SimMode() then
		return L["Upgrades follow your stat weights. Choose Simulator under Rate items by to rate items with these fights."]
	end
end

local function UpdateFooter()
	if not window then return end
	local progress, kind = LG:SimProgress()
	local status = LG:SimStatus()
	if progress then
		window.bar:SetValue(progress)
		window.bar:Show()
		local title = ({ bis = L["Best in Slot run"], char = L["Character run"], item = L["Item run"], sets = L["Sets run"] })[kind] or L["Simulator"]
		window.status:SetText(("%s  %d %%%s"):format(title, math.floor(progress * 100), status == "paused" and ("  · " .. L["paused for combat"]) or ""))
	else
		window.bar:Hide()
		local bisStatus, record = LG:SimStatus()
		if bisStatus == "ready" and record then
			window.status:SetText((L["Best in Slot simulated %s"]):format(LG:SimSetGainText() or ""))
		elseif bisStatus == "outdated" then
			window.status:SetText(L["Best in Slot run is outdated"])
		else
			window.status:SetText(L["Ready"])
		end
	end
	window.stop:SetEnabled(progress ~= nil)
	window.sim:SetEnabled(progress == nil)
	window.note:SetText(NoteText() or "")
	window.useSim:SetShown(not LG:SimMode() and LG.simMessage == nil and status ~= "paused")
end
Window.UpdateFooter = UpdateFooter

local function Layout()
	local note = window.note:GetText()
	local hasNote = note ~= nil and note ~= ""
	window.flow:ClearAllPoints()
	window.flow:SetPoint("TOPLEFT", window.content, "TOPLEFT", 0, hasNote and -70 or -52)
	window.flow:SetPoint("BOTTOMRIGHT", window.content, "BOTTOMRIGHT", 0, 0)
end

function Window.Draw()
	if not (window and window:IsShown()) then return end
	local ui = UI()
	for key, chip in pairs(window.targets) do chip:SetOn((ui.simTarget or "boss") == key) end
	for length, chip in pairs(window.lengths) do chip:SetOn((tonumber(ui.simLength) or 180) == length) end
	local tab = Tab()
	for key, button in pairs(window.tabs) do button.on = key == tab end
	E:UpdateTabs()
	UpdateFooter()
	Layout()
	local flow = window.flow
	flow:Begin()
	if tab == "planner" then
		DrawPlanner(flow)
	elseif tab == "sets" then
		DrawSets(flow)
	else
		DrawChar(flow)
	end
	flow:Finish(true)
end

local function RunShownTab()
	LG.simMessage = nil
	local tab = Tab()
	if tab == "char" then
		LG:RunSim("char", nil, true)
	else
		LG:RunSim("sets", Window.SetsToRun(), true)
	end
	Window.Draw()
end

local function Chip(parent, label, onClick, tip)
	local chip = P.Toggle(parent, label, onClick, label, tip)
	chip:SetHeight(20)
	return chip
end

local function Build()
	if window then return window end
	-- The kit grip resizes it; the size lives with the position.
	window = WK.CreateWindow("EldoUILootSim", { width = WIDTH, height = HEIGHT, footer = 40, headerHeight = 60,
		resizable = { minWidth = MIN_W, minHeight = MIN_H },
		sizeStore = function() return LG:Cache().simWindow end,
		onResize = function()
			SaveGeometry()
			Window.Draw()
		end })
	window:SetTitle(L["Simulator"], L["Estimates from fights against a target dummy with your own character sheet and public Classic combat rules. Set bonuses and item procs are not counted."])
	local function Stop() window:StopMovingOrSizing() SaveGeometry() end
	window:HookScript("OnDragStop", Stop)
	window.header:HookScript("OnDragStop", Stop)
	window.estimate = Kit.Chip and Kit.Chip(window.headerRight, L["estimate"]) or nil
	if window.estimate then
		window.estimate:SetPoint("TOPRIGHT", 0, 0)
		Kit.Tooltip(window.estimate, L["estimate"], L["The numbers come from many short fights with random rolls. The ± range shows how sure they are (95 %)."])
	end

	-- Fight settings.
	local content = window.content
	local targetLabel = Kit.Text(content, 11, "LEFT", "secondary")
	targetLabel:SetPoint("TOPLEFT", 0, -2)
	targetLabel:SetText(L["Target"])
	window.targets = {}
	local anchor = targetLabel
	for _, key in ipairs(LG.SIM_TARGETS) do
		local chip = Chip(content, TARGET_TITLES[key], function()
			UI().simTarget = key
			LG:Fire("sim")
			Window.Draw()
		end, L["The level of the target dummy. Bosses are three levels above you: more misses, glancing blows and resists."])
		chip:SetPoint("LEFT", anchor, "RIGHT", anchor == targetLabel and 8 or 4, 0)
		window.targets[key] = chip
		anchor = chip
	end
	local lengthLabel = Kit.Text(content, 11, "LEFT", "secondary")
	lengthLabel:SetPoint("LEFT", anchor, "RIGHT", 18, 0)
	lengthLabel:SetText(L["Fight"])
	window.lengths = {}
	anchor = lengthLabel
	for _, length in ipairs(LG.SIM_LENGTHS) do
		local chip = Chip(content, (L["%d min"]):format(length / 60), function()
			UI().simLength = length
			LG:Fire("sim")
			Window.Draw()
		end, L["How long each fight lasts for the Character and Sets tabs. Best in Slot runs always use one-minute fights."])
		chip:SetPoint("LEFT", anchor, "RIGHT", anchor == lengthLabel and 8 or 4, 0)
		window.lengths[length] = chip
		anchor = chip
	end
	-- Tabs.
	window.tabs = {}
	anchor = nil
	-- EldoUI's flat tabs: gray text, the open one in the accent with its
	-- underline, in the theme font (and Large text).
	for _, key in ipairs(TABS) do
		local tab = CreateFrame("Button", nil, content)
		tab:SetHeight(E.tokens.height.tab)
		tab.tabKey = key
		tab:SetScript("OnClick", function()
			UI().simTab = key
			if picker then picker:Hide() end
			Window.Draw()
		end)
		E:SkinTabs({ tab }, { isSelected = function(own) return own.tabKey == Tab() end, size = E.tokens.size.body })
		tab:SetText(TAB_TITLES[key])
		local text = tab:GetFontString()
		tab:SetWidth(math.max(64, math.ceil((text and text:GetStringWidth() or 60) + 24)))
		Kit.Tooltip(tab, TAB_TITLES[key], TAB_TIPS[key])
		if anchor then tab:SetPoint("LEFT", anchor, "RIGHT", 2, 0) else tab:SetPoint("TOPLEFT", 0, -26) end
		window.tabs[key] = tab
		anchor = tab
	end
	window.note = Kit.Text(content, 11, "LEFT", "secondary")
	window.note:SetPoint("TOPLEFT", 0, -56)
	window.note:SetPoint("TOPRIGHT", -110, -56)
	window.note:SetWordWrap(false)
	window.useSim = Kit.Button(content, L["Use the simulator"], 104, 18, function()
		if E.ItemScore then E.ItemScore:SetRating("sim") end
		LG:Fire("settings")
		if E.RefreshConfig then E:RefreshConfig() end
		Window.Draw()
	end, L["Use the simulator"], L["Rates items for this character by these fights (Rate items by: Simulator). You can switch back on the Loot Guide settings page."])
	window.useSim:SetPoint("TOPRIGHT", 0, -53)
	window.flow = P.Flow(content)

	-- Footer: progress, Stop, Sim.
	local footer = window.footer
	window.sim = Kit.Button(footer, L["Sim"], 80, 24, RunShownTab, L["Sim"],
		L["Reads your character again and runs the shown tab: Character, or your sets for Planner and Sets. Runs in small steps out of combat."])
	window.sim:SetPoint("RIGHT", -18, 0)
	window.stop = Kit.Button(footer, L["Stop"], 70, 24, function() LG:StopSim() Window.Draw() end, L["Stop"], L["Stops the run. Results saved so far stay."])
	window.stop:SetPoint("RIGHT", window.sim, "LEFT", -6, 0)
	window.bar = E:CreateStatusBar(footer)
	window.bar:SetSize(160, 6)
	window.bar:SetPoint("LEFT", 4, 0)
	window.bar:SetMinMaxValues(0, 1)
	window.bar:SetStatusBarColor(Kit.Accent())
	window.status = Kit.Text(footer, 11, "LEFT", "secondary")
	window.status:SetPoint("LEFT", window.bar, "RIGHT", 10, 0)
	window.status:SetPoint("RIGHT", window.stop, "LEFT", -10, 0)
	window.status:SetWordWrap(false)

	window:SetScript("OnSizeChanged", function() if window:IsShown() then Layout() end end)
	window:HookScript("OnHide", function() if picker then picker:Hide() end end)
	LG:SimWatch("simwindow", function()
		if not (window and window:IsShown()) then return end
		UpdateFooter()
		if not LG:SimJob() then Window.Draw() end
	end)
	LG:On("simwindow", function(changed)
		if window and window:IsShown() and (changed.sim or changed.sets or changed.gear or changed.settings or changed.spec) then Window.Draw() end
	end)
	return window
end

local function Tour()
	if not Kit.Tour then return end
	Kit.Tour("sim", {
		{ target = window.targets.boss, text = L["Pick the target dummy's level and the fight length. Bosses are three levels above you."] },
		{ target = window.tabs.char, text = L["Character shows your DPS, each ability's share and what one more point of each stat is worth. Planner and Sets compare your plan sets."] },
		{ target = window.sim, text = L["Sim reads your character and runs the shown tab. It runs in small steps, pauses in combat and never acts for you."] },
	})
end

function Window.Open(tab)
	Build()
	if tab and (tab == "char" or tab == "planner" or tab == "sets") then UI().simTab = tab end
	ApplyGeometry()
	window:Show()
	Window.Draw()
	Tour()
end

function Window.Frame()
	return window
end

-- Combat: the window closes like the Loot Guide window (runs pause).
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:SetScript("OnEvent", function()
	if window and window:IsShown() then window:Hide() end
end)
