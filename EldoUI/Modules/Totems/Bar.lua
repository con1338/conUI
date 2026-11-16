-- EldoUI Shaman Totems: the totem bar. One button per element (earth,
-- fire, water, air) casts the picked totem; pointing at a button opens its
-- picker with every totem you know for that element (left-click drops it,
-- right-click makes it the element's pick); Drop All drops the whole set
-- (right-click: loadouts). Each button shows its element's running totem
-- as the game's own sweep and countdown.
--
-- Secure parts: the buttons are SecureActionButtonTemplate buttons. Their
-- spells, the pickers' contents and the layout are written out of combat;
-- the pickers open and close in combat through restricted snippets
-- (SecureHandlerEnterLeaveTemplate), so a fight never changes a spell.
-- Written from scratch for EldoUI.
local _, E = ...
local L = E.L
local M = E:GetModule("ShamanTotems")
local D = E.ShamanData
local Try = M.Try
local Plain = E.Plain
local Secret = E.Secret
-- Every cooldown and totem time goes through EldoUI's one cooldown source.
local Source = E.CombatKit and E.CombatKit.Cooldowns

local Bar = {}
M.Bar = Bar
M:AddPart("bar", Bar)

local DEFAULT_POINT = { "CENTER", "UIParent", "CENTER", 0, -230 }
local MAX_PICKS = 8
local PICKER_GAP = 2

E:RegisterGlowUser("totemHint", {
	title = "Shaman Totems: counter hint",
	desc = "The earth totem button while you are feared and know Tremor Totem (Shaman Totems > Group).",
	order = 47,
	button = true,
	default = { style = "pixel", colorMode = "custom", color = { 1, 0.82, 0 } },
})

---------------------------------------------------------------------------
-- A bar button in the action button look (shared with the cooldown bar).
-- masqueGroup: the Masque group it joins when "Use Masque" is on (a fixed
-- English name: Masque keeps its skin settings under it).
---------------------------------------------------------------------------
M.MASQUE_TOTEMS, M.MASQUE_COOLDOWNS = "Totem Bar", "Shaman Cooldowns"

function M.NewButton(parent, name, templates, masqueGroup)
	local button = CreateFrame("Button", name, parent, templates)
	E:SetTemplate(button)
	button.icon = button:CreateTexture(nil, "ARTWORK")
	button.icon:SetPoint("TOPLEFT", E.pixel, -E.pixel)
	button.icon:SetPoint("BOTTOMRIGHT", -E.pixel, E.pixel)
	E:TrimIcon(button.icon)
	button.cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
	button.cooldown:SetAllPoints(button.icon)
	if button.cooldown.SetDrawEdge then button.cooldown:SetDrawEdge(false) end
	button.hotkey = E:CreateText(button, E.tokens.size.tiny, "RIGHT")
	button.hotkey:SetPoint("TOPRIGHT", -2, -2)
	button.count = E:CreateText(button, E.tokens.size.small, "RIGHT")
	button.count:SetPoint("BOTTOMRIGHT", -2, 2)
	E:SkinHudButton(button, button.icon)
	-- The element's (or state's) thin edge along the bottom.
	button.edge = button:CreateTexture(nil, "OVERLAY", nil, 2)
	button.edge:SetPoint("BOTTOMLEFT", button.icon, "BOTTOMLEFT")
	button.edge:SetPoint("BOTTOMRIGHT", button.icon, "BOTTOMRIGHT")
	button.edge:SetHeight(2)
	button.edge:SetTexture(E.media.flat)
	button.edge:Hide()
	-- The pressed look stays EldoUI's (PaintButton keeps it in the accent).
	if masqueGroup and M.db.masque then
		E:MasqueButton(masqueGroup, button, { Icon = button.icon, Cooldown = button.cooldown, Count = button.count,
			HotKey = button.hotkey, Highlight = highlight }, "Action")
	end
	return button
end

-- Accent and fonts follow the theme (called from every Apply).
function M.PaintButton(button)
	E:SetFont(button.hotkey, E.tokens.size.tiny)
	E:SetFont(button.count, E.tokens.size.small)
	E:SetTemplate(button)
end

local function KeyText(command)
	local key = GetBindingKey and GetBindingKey(command)
	if type(key) ~= "string" or key == "" then return "" end
	local bars = E.modules.ActionBars
	if bars and bars.AbbreviateKey then return bars:AbbreviateKey(key) end
	return GetBindingText and GetBindingText(key, "KEY_") or key
end
M.KeyText = KeyText

---------------------------------------------------------------------------
-- Building
---------------------------------------------------------------------------
-- Restricted snippets: the picker shows while the pointer is on the
-- element button or the picker, and hides once it is on neither. The
-- picker's frame covers its button too, so moving between them keeps it.
local OWNER_ENTER = [[
	local picker = self:GetFrameRef("picker")
	if picker and (self:GetAttribute("eldo-picks") or 0) > 0 then picker:Show() end
]]
local LEAVE = [[
	local picker = self:GetFrameRef("picker")
	if picker and not picker:IsUnderMouse(true) then picker:Hide() end
]]

-- The tooltip sits beside the whole bar, left of it (right of it when the
-- bar is too close to the left edge), so it never covers the totem pickers
-- that open above the buttons.
local function ShowTip(button)
	if not button.tip then return end
	GameTooltip:SetOwner(button, "ANCHOR_NONE")
	button:tip(GameTooltip)
	GameTooltip:Show()
	local bar = Bar.frame
	GameTooltip:ClearAllPoints()
	if not bar then
		GameTooltip:SetPoint("BOTTOM", button, "TOP", 0, 8)
		return
	end
	local left, scale = bar:GetLeft(), bar:GetEffectiveScale() / GameTooltip:GetEffectiveScale()
	if left and left * scale < GameTooltip:GetWidth() + 16 then
		GameTooltip:SetPoint("BOTTOMLEFT", bar, "BOTTOMRIGHT", 8, 0)
	else
		GameTooltip:SetPoint("BOTTOMRIGHT", bar, "BOTTOMLEFT", -8, 0)
	end
end
M.ShowTip = ShowTip

local function ElementTip(button, tooltip)
	local pick = button.pick
	if pick and pick.spell and tooltip.SetSpellByID then
		tooltip:SetSpellByID(pick.spell)
	else
		E.UIKit.TipTitle(tooltip, L[M.ELEMENT_TITLES[button.element]])
		E.UIKit.TipText(tooltip, L["You know no totem for this element yet."])
	end
	if M.CoverageLines then M:CoverageLines(tooltip, button.element) end
	if button.waiting then E.UIKit.TipText(tooltip, L["The game hides which totem is down right now; the timer shows again when it tells."]) end
	E:TooltipHint(tooltip, { L["Point at it"], L["pick another totem"] })
end

M.ELEMENT_TITLES = { EARTH = "Earth", FIRE = "Fire", WATER = "Water", AIR = "Air" }
-- L["Earth"], L["Fire"], L["Water"], L["Air"]

local function PickerTip(button, tooltip)
	if button.spell and tooltip.SetSpellByID then
		tooltip:SetSpellByID(button.spell)
	end
	if InCombatLockdown() then
		E.UIKit.TipText(tooltip, L["Picks change out of combat."])
	else
		E:TooltipHint(tooltip, { L["Click"], L["drop it"] }, { L["Right-click"], L["make it this element's totem"] })
	end
end

local function PickerClick(button, mouse)
	if mouse ~= "RightButton" or not button.key then return end
	if InCombatLockdown() then return end
	M:SetPick(button.element, button.key)
end

local function DropTip(button, tooltip)
	local call = M:CallSpell()
	E.UIKit.TipTitle(tooltip, L["Drop all totems"])
	if Bar.useCall and call then
		E.UIKit.TipText(tooltip, L["Uses %s with your picks."]:format(M.SpellName(call) or ""))
	else
		E.UIKit.TipText(tooltip, L["Drops one totem per press, in element order. The sequence starts over 15 seconds after your last press."])
	end
	local name = M.LoadoutName and M:LoadoutName(M.db.activeLoadout)
	if name then E.UIKit.TipText(tooltip, L["Loadout: %s"]:format(name)) end
	local jobs = M.MyJobs and M.received and M:MyJobs(M.received)
	if jobs then E.UIKit.TipText(tooltip, L["Your part of the group plan: %s"]:format(table.concat(jobs, ", "))) end
	local pending = M.PendingLoadout and M:PendingLoadout()
	if pending then E.UIKit.TipText(tooltip, L["The loadout %s switches when combat ends."]:format(pending)) end
	E:TooltipHint(tooltip, { L["Click"], L["drop all"] }, { L["Right-click"], L["loadouts"] })
end

function Bar:Build()
	if self.frame then return end
	local holder = CreateFrame("Frame", "EldoUI_ShamanTotemsHolder", UIParent, "SecureHandlerStateTemplate")
	holder:SetAllPoints(UIParent)
	holder:SetFrameStrata("LOW")
	self.holder = holder
	local frame = CreateFrame("Frame", "EldoUI_ShamanTotems", holder, "SecureHandlerStateTemplate")
	frame:SetSize(156, 28)
	frame:SetFrameStrata("LOW")
	self.frame = frame
	self.buttons = {}
	for index, element in ipairs(D.ELEMENTS) do
		local button = M.NewButton(frame, "EldoUI_TotemButton" .. index, "SecureActionButtonTemplate, SecureHandlerEnterLeaveTemplate",
			M.MASQUE_TOTEMS)
		button.element = element
		button.command = ("CLICK EldoUI_TotemButton%d:LeftButton"):format(index)
		button:RegisterForClicks("AnyUp", "AnyDown")
		button:SetAttribute("type", nil)
		button:SetAttribute("type1", "spell")
		button.tip = ElementTip
		button:HookScript("OnEnter", ShowTip)
		button:HookScript("OnLeave", GameTooltip_Hide)
		button.timerBar = E:CreateStatusBar(button)
		button.timerBar:SetHeight(3)
		button.timerBar:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -1)
		button.timerBar:SetPoint("TOPRIGHT", button, "BOTTOMRIGHT", 0, -1)
		button.timerBar:SetMinMaxValues(0, 1)
		button.timerBar:Hide()
		E:SetTemplate(button.timerBar, true)
		-- The picker.
		local picker = CreateFrame("Frame", "EldoUI_TotemPicker" .. index, frame, "SecureHandlerBaseTemplate")
		picker:EnableMouse(false)
		picker:SetFrameLevel(frame:GetFrameLevel() + 10)
		picker:Hide()
		picker.buttons = {}
		for slot = 1, MAX_PICKS do
			local pick = M.NewButton(picker, ("EldoUI_TotemPicker%dButton%d"):format(index, slot), "SecureActionButtonTemplate, SecureHandlerEnterLeaveTemplate",
				M.MASQUE_TOTEMS)
			pick.element = element
			pick:RegisterForClicks("AnyUp", "AnyDown")
			pick:SetAttribute("type", nil)
			pick:SetAttribute("type1", "spell")
			pick:SetAttribute("_onleave", LEAVE)
			SecureHandlerSetFrameRef(pick, "picker", picker)
			pick.tip = PickerTip
			pick:HookScript("OnEnter", ShowTip)
			pick:HookScript("OnLeave", GameTooltip_Hide)
			pick:HookScript("PostClick", PickerClick)
			pick:Hide()
			picker.buttons[slot] = pick
		end
		SecureHandlerSetFrameRef(button, "picker", picker)
		button:SetAttribute("_onenter", OWNER_ENTER)
		button:SetAttribute("_onleave", LEAVE)
		button.picker = picker
		E:RegisterKeybindButton(button, button.command)
		self.buttons[index] = button
	end
	local drop = M.NewButton(frame, "EldoUI_TotemDropAll", "SecureActionButtonTemplate", M.MASQUE_TOTEMS)
	drop.command = "CLICK EldoUI_TotemDropAll:LeftButton"
	drop:RegisterForClicks("AnyUp", "AnyDown")
	drop:SetAttribute("type", nil)
	drop.tip = DropTip
	drop:HookScript("OnEnter", ShowTip)
	drop:HookScript("OnLeave", GameTooltip_Hide)
	drop:HookScript("PostClick", function(btn, mouse)
		if mouse == "RightButton" and M.OpenLoadoutMenu then M:OpenLoadoutMenu(btn) end
	end)
	E:RegisterKeybindButton(drop, drop.command)
	self.drop = drop
	-- Totemic Recall for its key binding (the cooldown bar shows it too).
	local recall = CreateFrame("Button", "EldoUI_TotemRecall", holder, "SecureActionButtonTemplate")
	recall:RegisterForClicks("AnyUp", "AnyDown")
	recall:SetAttribute("type", "spell")
	recall:Hide()
	self.recall = recall
	E:CreateMover(frame, "EldoUI_ShamanTotems", L["Shaman Totems"], DEFAULT_POINT,
		{ layoutAlias = "EldoUI_Totems", combat = true, sample = { kind = "icons", count = 5 } })
end

---------------------------------------------------------------------------
-- Secure attributes and layout (out of combat)
---------------------------------------------------------------------------
-- The macro Drop All runs without a call: one totem per press.
local function SequenceText(picks)
	local names = {}
	for _, pick in ipairs(picks) do
		if pick and pick.name then names[#names + 1] = pick.name end
	end
	if #names == 0 then return nil end
	return "/castsequence reset=combat/15 " .. table.concat(names, ", ")
end
Bar.SequenceText = SequenceText

local function Place(button, frame, index, size, spacing, vertical)
	button:ClearAllPoints()
	button:SetSize(size, size)
	local offset = (index - 1) * (size + spacing)
	if vertical then
		button:SetPoint("TOP", frame, "TOP", 0, -offset)
	else
		button:SetPoint("LEFT", frame, "LEFT", offset, 0)
	end
end

-- The picker opens from its button toward db.flyout; its frame covers the
-- button too (see the snippets above).
local function LayoutPicker(button, count, size)
	local picker = button.picker
	local dir = M.db.flyout
	local length = count * (size + PICKER_GAP)
	picker:ClearAllPoints()
	if dir == "DOWN" then
		picker:SetPoint("TOPLEFT", button, "TOPLEFT")
		picker:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, -length)
	elseif dir == "LEFT" then
		picker:SetPoint("TOPRIGHT", button, "TOPRIGHT")
		picker:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", -length, 0)
	elseif dir == "RIGHT" then
		picker:SetPoint("TOPLEFT", button, "TOPLEFT")
		picker:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", length, 0)
	else
		picker:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT")
		picker:SetPoint("TOPRIGHT", button, "TOPRIGHT", 0, length)
	end
	for slot, pick in ipairs(picker.buttons) do
		pick:ClearAllPoints()
		pick:SetSize(size, size)
		local step = slot * (size + PICKER_GAP)
		if dir == "DOWN" then
			pick:SetPoint("TOP", button, "TOP", 0, -step)
		elseif dir == "LEFT" then
			pick:SetPoint("RIGHT", button, "RIGHT", -step, 0)
		elseif dir == "RIGHT" then
			pick:SetPoint("LEFT", button, "LEFT", step, 0)
		else
			pick:SetPoint("BOTTOM", button, "BOTTOM", 0, step)
		end
	end
end

function Bar:Apply()
	if not M:Drawing() then
		self:Disable()
		return
	end
	self:Build()
	local db = M.db
	local size, spacing = db.size, db.spacing
	local frame = self.frame
	local picks = {}
	for index, button in ipairs(self.buttons) do
		M.PaintButton(button)
		local pick = M:Pick(button.element)
		button.pick = pick
		picks[index] = pick
		button:SetAttribute("spell", pick and pick.name or nil)
		Place(button, frame, index, size, spacing, db.vertical)
		local known = M:KnownTotems(button.element)
		button:SetAttribute("eldo-picks", #known)
		for slot, picker in ipairs(button.picker.buttons) do
			local item = known[slot]
			M.PaintButton(picker)
			if item then
				picker.key, picker.spell = item.key, item.spell
				picker:SetAttribute("spell", item.name)
				picker.icon:SetTexture(item.icon)
				-- The element's pick is the selected one: the accent edge.
				local selected = pick and pick.key == item.key
				local r, g, b = unpack(E.media.accentColor)
				picker.edge:SetVertexColor(r, g, b, 1)
				picker.edge:SetShown(selected and true or false)
				picker:Show()
			else
				picker.key, picker.spell = nil, nil
				picker:SetAttribute("spell", nil)
				picker:Hide()
			end
		end
		LayoutPicker(button, #known, size)
		button.picker:Hide()
		button.hotkey:SetText(db.showKeys and KeyText(button.command) or "")
		button.timerBar:SetShown(db.timerBars and true or false)
		if button.cooldown.SetHideCountdownNumbers then button.cooldown:SetHideCountdownNumbers(not db.timerText) end
		if button.cooldown.SetReverse then button.cooldown:SetReverse(true) end
		local color = E.tokens.element[button.element]
		button.edge:SetVertexColor(color[1], color[2], color[3], 1)
		button.edge:SetShown(db.elementColors and true or false)
		local bar = button.timerBar
		bar:SetStatusBarColor(color[1], color[2], color[3], 1)
		button:Show()
	end
	-- Drop All: Call of the Elements with your picks, else a sequence.
	local drop = self.drop
	M.PaintButton(drop)
	local call = db.dropAll == "call" and M:CallSpell()
	self.useCall = call and true or false
	if call then
		drop:SetAttribute("type1", "spell")
		drop:SetAttribute("spell", M.SpellName(call))
		drop:SetAttribute("macrotext1", nil)
		drop.icon:SetTexture(M:Spell(call).icon)
	else
		local text = SequenceText(picks)
		drop:SetAttribute("type1", text and "macro" or nil)
		drop:SetAttribute("macrotext1", text)
		drop:SetAttribute("spell", nil)
		local first = picks[1] or picks[2] or picks[3] or picks[4]
		drop.icon:SetTexture(first and first.icon or E:ClientIcon("Interface\\Icons\\Spell_Nature_Purge"))
	end
	drop.hotkey:SetText(db.showKeys and KeyText(drop.command) or "")
	Place(drop, frame, #self.buttons + 1, size, spacing, db.vertical)
	drop:Show()
	-- Totemic Recall for its key.
	local recall = M:Known(D.RECALL) and M.SpellName(D.RECALL) or nil
	self.recall:SetAttribute("spell", recall)
	-- Masque fits its skin to the button size it finds when it skins.
	if db.masque then E:MasqueReSkin(M.MASQUE_TOTEMS) end
	local count = #self.buttons + 1
	local length = count * size + (count - 1) * spacing
	local extra = db.timerBars and 4 or 0
	if db.vertical then frame:SetSize(size + extra, length) else frame:SetSize(length, size + extra) end
	frame:Show()
	self:UpdateVisibility()
	local mover = E.movers.EldoUI_ShamanTotems
	if mover then mover:Show() end
end

function Bar:UpdateVisibility()
	if not self.holder then return end
	if self.visibilityBlock ~= M.db.visibility then E:DetachVisibility(self.holder) end
	if E:IsVisibilityAttached(self.holder) then
		E:UpdateVisibility(self.holder)
	else
		self.visibilityBlock = M.db.visibility
		E:AttachVisibility(self.holder, M.db.visibility, {
			watch = self.frame,
			secure = true,
			forceShow = function() return E.IsMoveMode and E:IsMoveMode() end,
		})
	end
end

---------------------------------------------------------------------------
-- Display (in combat too): icons, timers, the empty fade
---------------------------------------------------------------------------
local function SetTimer(button, slot)
	local cooldown, bar = button.cooldown, button.timerBar
	if not slot then
		cooldown:Clear()
		if bar.SetTimerDuration then bar:SetValue(0) end
		return false
	end
	local duration = Source and Source.TotemDuration(slot)
	local shown = false
	if type(duration) ~= "nil" and cooldown.SetCooldownFromDurationObject then
		shown = pcall(cooldown.SetCooldownFromDurationObject, cooldown, duration)
	end
	if not shown then
		local _, _, start, length = Try(GetTotemInfo, slot)
		start, length = Plain(start), Plain(length)
		if type(start) == "number" and type(length) == "number" and length > 0 then
			cooldown:SetCooldown(start, length)
			shown = true
		else
			cooldown:Clear()
		end
	end
	if M.db.timerBars and type(duration) ~= "nil" and bar.SetTimerDuration then
		local direction = Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.RemainingTime
		if not pcall(bar.SetTimerDuration, bar, duration, nil, direction) then pcall(bar.SetTimerDuration, bar, duration) end
	end
	return shown
end

function Bar:Update()
	if not (self.frame and M:Drawing()) then return end
	local slots, unresolved = M:ElementSlots()
	local db = M.db
	for _, button in ipairs(self.buttons) do
		local pick = button.pick
		button.icon:SetTexture(pick and pick.icon or E:ClientIcon("Interface\\Icons\\INV_Misc_QuestionMark"))
		button.icon:SetDesaturated(not pick)
		local slot = slots[button.element]
		SetTimer(button, slot)
		button.waiting = not slot and unresolved > 0
		-- Unknown is not missing: nothing fades while the game hides a slot.
		local faded = db.emptyFade and not slot and unresolved == 0
		button.icon:SetAlpha((not pick or faded) and 0.45 or 1)
	end
	local drop = self.drop
	if drop then
		drop.cooldown:Clear()
		if self.useCall and Source then Source.DrawSpell(drop.cooldown, M:CallSpell()) end
	end
	self:UpdateHint()
end

-- Tremor hint: your own loss of control says you are feared.
function Bar:Feared()
	local loc = C_LossOfControl
	if not (loc and loc.GetActiveLossOfControlDataCount and loc.GetActiveLossOfControlData) then return false end
	local count = Plain(Try(loc.GetActiveLossOfControlDataCount))
	if type(count) ~= "number" then return false end
	for index = 1, math.min(count, 8) do
		local data = Plain(Try(loc.GetActiveLossOfControlData, index))
		if type(data) == "table" then
			local kind = Plain(data.locType)
			if kind == "FEAR" or kind == "FEAR_MECHANIC" then return true end
		end
	end
	return false
end

function Bar:UpdateHint()
	local earth = self.buttons and self.buttons[1]
	if not earth then return end
	local show = M.db.tremorHint and M:Known(D.byKey.tremor.id) and self:Feared()
	if show and not self.hinting then
		self.hinting = true
		E:ShowUserGlow(earth, "totemHint")
	elseif not show and self.hinting then
		self.hinting = false
		E:HideGlow(earth)
	end
end

function Bar:OnEvent(event)
	if event == "LOSS_OF_CONTROL_ADDED" or event == "LOSS_OF_CONTROL_UPDATE" then self:UpdateHint() end
end

function Bar:Enable() end

function Bar:Disable()
	if not self.frame then
		local mover = E.movers.EldoUI_ShamanTotems
		if mover then mover:Hide() end
		return
	end
	E:DetachVisibility(self.holder)
	self.visibilityBlock = nil
	if self.hinting then
		self.hinting = false
		E:HideGlow(self.buttons[1])
	end
	E:RunOutOfCombat(function()
		Bar.frame:Hide()
		local mover = E.movers.EldoUI_ShamanTotems
		if mover then mover:Hide() end
	end, "ShamanTotems:BarOff")
end

-- Binding names (Key Bindings > AddOns).
E:NameBinding("BINDING_HEADER_ELDOUITOTEMS", E.Key("EldoUI Shaman Totems"))
for index, element in ipairs(D.ELEMENTS) do
	E:NameBinding(("BINDING_NAME_CLICK EldoUI_TotemButton%d:LeftButton"):format(index), E.Key("Drop the %s totem"),
		function() return L[M.ELEMENT_TITLES[element]]:lower() end)
end
E:NameBinding("BINDING_NAME_CLICK EldoUI_TotemDropAll:LeftButton", E.Key("Drop all totems"))
E:NameBinding("BINDING_NAME_CLICK EldoUI_TotemRecall:LeftButton", E.Key("Totemic Recall"))
