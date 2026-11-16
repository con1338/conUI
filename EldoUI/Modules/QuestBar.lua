-- EldoUI Quest Item Bar: one button for every quest item in your bags that
-- you can use, so you don't open your bags to use one. A click or the
-- button's key uses the item (review verbesserungen.md, B5).
--
-- Which items (one button per item, in the order they sit in your bags):
--   * the item the quest log names for a quest (GetQuestLogSpecialItemInfo),
--     while you carry it; not for a quest that is ready to turn in, unless
--     the game keeps the item for it or "Finished quests too" is on;
--   * an item the game flags as a quest item, or of the Quest item class,
--     that has a use (a use spell, or something inside to open);
--   * an item that starts a quest you don't have and haven't done (the "!"
--     items), until "Items that start a quest" is off.
-- An item you Shift-right-click stays off the bar until "Show hidden items
-- again". At most 12 buttons.
--
-- Rules (Midnight / Forever):
--   * The buttons are secure action buttons with Blizzard's own "item"
--     action: the item is used only by your click or key press. Which item
--     a button holds, which buttons show and where they sit change out of
--     combat only (E:RunOutOfCombat); in combat a button keeps its item.
--     The bags are read again when combat ends.
--   * Every game value is read in pcall and a secret one counts as not
--     there; nothing secret is compared. Counts and cooldowns are drawn as
--     the game gives them (the cooldown through the combat kit's one
--     cooldown source, Modules/CombatHUD/Kit.lua).
--   * Range: only for the quest log's items, the game's own answer
--     (IsQuestLogSpecialItemInRange), five times a second while one shows.
--
-- The Quest Tracker's quest item button (Modules/ObjectiveTracker.lua)
-- stays as it is: it keeps the tracked quest's item on its own key.
local _, E = ...
local L = E.L

local M = E:NewModule("QuestBar", {
	title = "Quest Item Bar",
	category = "Quality of Life",
	desc = "A bar with every quest item in your bags that you can use, and the items that start a quest. A click or the button's key uses the item; the bar changes only out of combat.",
	frames = { "EldoUI_QuestBar", "EldoUI_QuestBarHolder" },
	movers = { "EldoUI_QuestBar" },
	blizzard = {},
	savedKeys = { "profile.modules.QuestBar" },
	optionsPage = "module:QuestBar",
	reload = false,
	defaults = {
		enabled = true,
		starters = true,      -- items that start a quest
		complete = false,     -- also the quest log's items of quests ready to turn in
		hidden = {},          -- itemID -> true: left off the bar (Shift-right-click)
		buttonSize = 32,
		spacing = 4,
		vertical = false,
		showCount = true,
		hotkey = true,
		range = true,
		glow = true,
		masque = false,       -- Masque skins the buttons (Core/Masque.lua; after a reload)
		visibility = E:VisibilityDefaults(),
	},
})
E.QuestBar = M

local Plain = E.Plain
local PlainCall = E.PlainCall
local PlainEach = E.PlainCallEach

M.MAX = 12
local BUTTON = "EldoUI_QuestBarButton"
local MOVER = "EldoUI_QuestBar"
local QUEST_CLASS = 12            -- Enum.ItemClass.Questitem
local PLACEHOLDER = 134400        -- the game's question-mark icon
local STARTER_MARK = "Interface\\ContainerFrame\\UI-Icon-QuestBang"
local MASQUE_GROUP = "Quest Item Bar" -- a fixed English name: Masque keeps its skin settings under it
local RANGE_TICK, BIND_TICK = "QuestBar:range", "QuestBar:bind"
local APPLY_KEY = "QuestBar:apply"

E:RegisterGlowUser("questBar", {
	title = "Quest Item Bar",
	desc = "A button of the Quest Item Bar glows for a few seconds when a new quest item lands on it.",
	order = 61,
	button = true,
})

---------------------------------------------------------------------------
-- What the game says about an item
---------------------------------------------------------------------------
local function ItemIDOf(link)
	local id = type(link) == "string" and link:match("item:(%d+)")
	return id and tonumber(id) or nil
end

local function ItemClass(itemID)
	local get = (C_Item and C_Item.GetItemInfoInstant) or rawget(_G, "GetItemInfoInstant")
	local _, _, _, _, _, classID = PlainEach(get, itemID)
	return classID
end

-- A use spell ("Use: ..."), or something inside to open.
local function HasUse(itemID, info)
	local get = (C_Item and C_Item.GetItemSpell) or rawget(_G, "GetItemSpell")
	local name, spellID = PlainEach(get, itemID)
	if name ~= nil or spellID ~= nil then return true end
	return type(info) == "table" and Plain(info.hasLoot) == true
end

local function Count(itemID)
	local get = (C_Item and C_Item.GetItemCount) or rawget(_G, "GetItemCount")
	local count = PlainCall(get, itemID)
	return type(count) == "number" and count or 0
end

local function ItemIcon(itemID)
	local icon = C_Item and PlainCall(C_Item.GetItemIconByID, itemID)
	return icon or PLACEHOLDER
end

local function ItemName(itemID)
	local name = C_Item and PlainCall(C_Item.GetItemNameByID, itemID)
	return type(name) == "string" and name ~= "" and name or L["Item %s"]:format(itemID)
end

local function SlotQuestInfo(bag, slot)
	local get = C_Container and C_Container.GetContainerItemQuestInfo
	local info = PlainCall(get, bag, slot)
	return type(info) == "table" and info or nil
end

local function Completed(questID)
	return PlainCall(C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted, questID) == true
end

---------------------------------------------------------------------------
-- The items
---------------------------------------------------------------------------
-- itemID -> { logIndex, questID, charges }: the items the quest log names
-- for its quests. A quest ready to turn in only when the game keeps its item
-- for it (showWhenComplete) or the setting asks for it. Second result:
-- itemID -> true for the items left out that way, so the bag rule below
-- doesn't bring them back.
function M:QuestLogItems()
	local items, finished = {}, {}
	local log = C_QuestLog
	local special = rawget(_G, "GetQuestLogSpecialItemInfo")
	if not (log and log.GetNumQuestLogEntries and log.GetInfo and special) then return items, finished end
	local entries = PlainCall(log.GetNumQuestLogEntries)
	for index = 1, type(entries) == "number" and entries or 0 do
		local info = PlainCall(log.GetInfo, index)
		if type(info) == "table" and Plain(info.isHeader) ~= true then
			local link, _, charges, showWhenComplete = PlainEach(special, index)
			local itemID = ItemIDOf(link)
			if itemID and not items[itemID] then
				local questID = Plain(info.questID)
				local complete = questID and PlainCall(log.IsComplete, questID) == true
				if not complete or showWhenComplete or self.db.complete then
					items[itemID] = { logIndex = index, questID = questID, charges = charges }
				else
					finished[itemID] = true
				end
			end
		end
	end
	return items, finished
end

-- The quest's place in the quest log now. The log can change in combat (a
-- new quest, a folded header) while the bar keeps its items; a quest that
-- left the log has none.
local function LogIndex(quest)
	local lookup = C_QuestLog and C_QuestLog.GetLogIndexForQuestID
	if quest.questID and type(lookup) == "function" then
		local index = PlainCall(lookup, quest.questID)
		return type(index) == "number" and index or nil
	end
	return quest.logIndex
end
M.LogIndex = LogIndex

-- "quest", "starter" or nil for the item in a bag slot.
function M:KindOf(itemID, bag, slot, info, logItems, finished)
	if logItems[itemID] then return "quest" end
	if finished and finished[itemID] then return nil end
	local quest = SlotQuestInfo(bag, slot)
	local questID = quest and Plain(quest.questID)
	if self.db.starters and type(questID) == "number" and Plain(quest.isActive) ~= true and not Completed(questID) then
		return "starter"
	end
	local flagged = (quest and Plain(quest.isQuestItem) == true) or ItemClass(itemID) == QUEST_CLASS
	if flagged and HasUse(itemID, info) then return "quest" end
	return nil
end

-- The bar's items in bag order: { id, kind, bag, slot, quest }. Second
-- result: itemID -> true for every item in the bags, on the bar or not.
function M:Scan()
	local hidden = self.db.hidden or {}
	local logItems, finished = self:QuestLogItems()
	local list, carried = {}, {}
	for bag, slot, info in E.BagCache:Items() do
		local itemID = Plain(info.itemID)
		if type(itemID) == "number" and not carried[itemID] then
			carried[itemID] = true
			if not hidden[itemID] and #list < M.MAX then
				local kind = self:KindOf(itemID, bag, slot, info, logItems, finished)
				if kind then
					list[#list + 1] = { id = itemID, kind = kind, bag = bag, slot = slot, quest = logItems[itemID] }
				end
			end
		end
	end
	return list, carried
end

-- What the secure attributes depend on: the items in their order.
local function Signature(list)
	local parts = {}
	for index, item in ipairs(list or {}) do parts[index] = tostring(item.id) end
	return table.concat(parts, ",")
end
M.Signature = Signature

---------------------------------------------------------------------------
-- The bar
---------------------------------------------------------------------------
local function KeyText(command)
	local key = PlainCall(GetBindingKey, command)
	if type(key) ~= "string" then return nil end
	return PlainCall(GetBindingText, key, "KEY_", true)
end

local function ShowTooltip(button)
	if E.FrameCheck(GameTooltip, "IsForbidden") then return end
	GameTooltip:SetOwner(button, "ANCHOR_TOP")
	local item = button.item
	if item then
		local logIndex = item.quest and LogIndex(item.quest)
		if logIndex and GameTooltip.SetQuestLogSpecialItem then
			GameTooltip:SetQuestLogSpecialItem(logIndex)
		elseif GameTooltip.SetBagItem and E.BagCache:ItemID(item.bag, item.slot) == item.id then
			GameTooltip:SetBagItem(item.bag, item.slot)
		elseif GameTooltip.SetItemByID then
			GameTooltip:SetItemByID(item.id)
		end
		if item.kind == "starter" then E.UIKit.TipText(GameTooltip, L["Starts a quest: a click shows it."]) end
	else
		E.UIKit.TipTitle(GameTooltip, L["Quest Item Bar"])
		E.UIKit.TipText(GameTooltip, L["Empty for now: the next quest item you can use comes here."])
	end
	local key = KeyText(button.command)
	GameTooltip:AddLine(key and L["Key: %s"]:format(key) or L["No key bound (Quest Item Bar > Bind keys)"], E:TokenColor("secondary"))
	if item then E:TooltipHint(GameTooltip, { L["Shift-right-click"], L["leave this item off the bar"] }) end
	GameTooltip:Show()
end

local function OnLeave()
	if not E.FrameCheck(GameTooltip, "IsForbidden") then GameTooltip:Hide() end
end

function M:CreateButton(index)
	local button = CreateFrame("Button", BUTTON .. index, self.bar, "SecureActionButtonTemplate")
	button.index = index
	button.command = ("CLICK %s%d:LeftButton"):format(BUTTON, index)
	-- The left button takes the press and the release, so the item is used
	-- on whichever one the game's "cast on key down" setting asks for, by
	-- click and by key. "*type1" is the left button with any modifier: a
	-- plain "type1" is the unmodified click only (SecureTemplates.lua), and a
	-- key bound with Shift, Ctrl or Alt would use nothing. The right button
	-- has no action: Shift-right-click leaves the item off the bar
	-- (PostClick), nothing is used.
	button:RegisterForClicks("LeftButtonUp", "LeftButtonDown", "RightButtonUp")
	button:SetAttribute("type", nil)
	button:SetAttribute("*type1", "item")
	E:SetTemplate(button)
	button.icon = button:CreateTexture(nil, "ARTWORK")
	button.icon:SetPoint("TOPLEFT", E.pixel, -E.pixel)
	button.icon:SetPoint("BOTTOMRIGHT", -E.pixel, E.pixel)
	E:TrimIcon(button.icon)
	button.cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
	button.cooldown:SetAllPoints(button.icon)
	if E.ApplyCooldownFont then E:ApplyCooldownFont(button.cooldown) end
	button.hotkey = E:CreateText(button, E.tokens.size.small, "RIGHT", "OVERLAY")
	button.hotkey:SetPoint("TOPRIGHT", -2, -3)
	button.count = E:CreateText(button, E.tokens.size.small, "RIGHT", "OVERLAY")
	button.count:SetPoint("BOTTOMRIGHT", -2, 2)
	button.starter = button:CreateTexture(nil, "OVERLAY")
	button.starter:SetAllPoints(button.icon)
	button.starter:SetTexture(STARTER_MARK)
	button.starter:Hide()
	button.highlight = button:CreateTexture(nil, "HIGHLIGHT")
	button.highlight:SetAllPoints(button.icon)
	E:AccentTexture(button.highlight, 0.25)
	button:HookScript("PostClick", function(clicked, mouse, down)
		if mouse == "RightButton" and not down and IsShiftKeyDown() and clicked.item then M:HideItem(clicked.item.id) end
	end)
	button:SetScript("OnEnter", ShowTooltip)
	button:SetScript("OnLeave", OnLeave)
	if self.db.masque then
		E:MasqueButton(MASQUE_GROUP, button, { Icon = button.icon, Cooldown = button.cooldown, Count = button.count,
			HotKey = button.hotkey, Highlight = button.highlight }, "Item")
	end
	button:Hide()
	return button
end

function M:BuildBar()
	if self.bar then return end
	-- The holder carries the visibility rule (a secure state driver for the
	-- hard rules, and the fade); the bar inside shows and hides itself by
	-- how many buttons it has.
	local holder = CreateFrame("Frame", "EldoUI_QuestBarHolder", UIParent, "SecureHandlerStateTemplate")
	holder:SetAllPoints(UIParent)
	holder:SetFrameStrata("LOW")
	self.holder = holder
	local bar = CreateFrame("Frame", MOVER, holder, "SecureHandlerStateTemplate")
	bar:SetSize(32, 32)
	bar:SetFrameStrata("LOW")
	self.bar = bar
	self.buttons = {}
	for index = 1, M.MAX do self.buttons[index] = self:CreateButton(index) end
	-- Beside the extra action button, above it (bottom right).
	E:CreateMover(bar, MOVER, L["Quest Item Bar"], { "BOTTOMRIGHT", "UIParent", "BOTTOMRIGHT", -463, 246 },
		{ group = "Action bars", combat = true })
end

-- Icon, count, starter mark and cooldown of every button: also in combat
-- (nothing secure). A button without an item shows the empty icon.
function M:UpdateButtons()
	if not self.buttons then return end
	local db, list = self.db, self.list or {}
	for index, button in ipairs(self.buttons) do
		local item = list[index]
		button.item = item
		if item then
			local count = Count(item.id)
			local charges = item.quest and Plain(item.quest.charges)
			button.icon:SetTexture(ItemIcon(item.id))
			button.icon:SetDesaturated(count == 0)
			button.icon:SetAlpha(count == 0 and 0.5 or 1)
			local shown = (type(charges) == "number" and charges > 1) and charges or count
			button.count:SetText((db.showCount and shown > 1) and shown or "")
			button.starter:SetShown(item.kind == "starter")
		else
			button.icon:SetTexture(PLACEHOLDER)
			button.icon:SetDesaturated(true)
			button.icon:SetAlpha(0.4)
			button.count:SetText("")
			button.starter:Hide()
		end
		button.icon:SetVertexColor(1, 1, 1)
		button.hotkey:SetText(db.hotkey and KeyText(button.command) or "")
		self:UpdateCooldown(button)
	end
	if E.Ticker:IsSubscribed(RANGE_TICK) then self:PaintRange(true) end
end

local function Cooldowns()
	return E.CombatKit and E.CombatKit.Cooldowns
end

function M:UpdateCooldown(button)
	local source = Cooldowns()
	if source and button.item then
		source.DrawItem(button.cooldown, button.item.id, { hideGCD = true })
	else
		button.cooldown:Clear()
	end
end

function M:UpdateCooldowns()
	for _, button in ipairs(self.buttons or {}) do self:UpdateCooldown(button) end
end

-- The bar's items, place and size: out of combat only. While "Bind keys"
-- runs every button shows, so each one can get its key.
function M:ApplySecure()
	if not (self.active and self.bar) or InCombatLockdown() then return end
	local db, list = self.db, self.list or {}
	local size, spacing = db.buttonSize, db.spacing
	local shown = self.binding and M.MAX or math.min(#list, M.MAX)
	for index, button in ipairs(self.buttons) do
		local item = list[index]
		button:SetAttribute("item", item and ("item:" .. item.id) or nil)
		button:ClearAllPoints()
		if index <= shown then
			button:SetSize(size, size)
			local offset = (index - 1) * (size + spacing)
			if db.vertical then
				button:SetPoint("TOP", self.bar, "TOP", 0, -offset)
			else
				button:SetPoint("LEFT", self.bar, "LEFT", offset, 0)
			end
			button:Show()
			E:RegisterKeybindButton(button, button.command)
		else
			button:Hide()
		end
	end
	-- Masque fits its skin to the button size it finds when it skins.
	if db.masque then E:MasqueReSkin(MASQUE_GROUP) end
	local length = math.max(1, shown) * (size + spacing) - spacing
	if db.vertical then self.bar:SetSize(size, length) else self.bar:SetSize(length, size) end
	self.bar:SetShown(shown > 0 or (E.IsMoveMode and E:IsMoveMode()) or false)
	self.shownButtons = shown
	self.appliedSignature = Signature(list)
	if E.movers and E.movers[MOVER] then E:ApplyMover(MOVER) end
end

function M:UpdateVisibility()
	if not self.holder then return end
	-- A new profile brings a new block: attach that one instead.
	if self.visibilityBlock ~= self.db.visibility then E:DetachVisibility(self.holder) end
	if E:IsVisibilityAttached(self.holder) then
		E:UpdateVisibility(self.holder)
	else
		self.visibilityBlock = self.db.visibility
		-- Move mode and Bind keys show the bar whatever the rule says; Bind
		-- keys also through the state driver, or a rule that really hides
		-- the bar ("In combat", "With a target") leaves nothing to hover.
		E:AttachVisibility(self.holder, self.db.visibility, {
			watch = self.bar,
			secure = true,
			forceShow = function() return M.binding or (E.IsMoveMode and E:IsMoveMode()) or false end,
			forceShowFirst = true,
			condition = function() return M.binding and "show" or nil end,
		})
	end
end

-- The out-of-range color for the quest log's items, while one shows.
-- check false: every icon gets its own color back.
function M:PaintRange(check)
	for _, button in ipairs(self.buttons or {}) do
		local quest = check and button.item and button.item.quest
		local logIndex = quest and LogIndex(quest)
		local valid = logIndex and PlainCall(IsQuestLogSpecialItemInRange, logIndex)
		if valid == 0 then
			button.icon:SetVertexColor(E:TokenColor("bad"))
		else
			button.icon:SetVertexColor(1, 1, 1)
		end
	end
end

function M:UpdateRange()
	local want = false
	if self.active and self.db.range and rawget(_G, "IsQuestLogSpecialItemInRange") then
		for index = 1, self.shownButtons or 0 do
			local item = self.list and self.list[index]
			if item and item.quest then want = true break end
		end
	end
	if want then
		if not E.Ticker:IsSubscribed(RANGE_TICK) then E.Ticker:Subscribe(RANGE_TICK, 0.2, function() M:PaintRange(true) end, M) end
		self:PaintRange(true)
	elseif E.Ticker:IsSubscribed(RANGE_TICK) then
		E.Ticker:Unsubscribe(RANGE_TICK)
		self:PaintRange(false)
	end
end

-- An item that came into the bags since the last read glows for a moment.
-- Not the ones there at the first read, nor items that join the bar
-- otherwise (their data came late, "Show hidden items again", a setting).
function M:GlowNew(before, list)
	if not (before and self.db.glow) then return end
	for index, item in ipairs(list) do
		local button = self.buttons[index]
		if not before[item.id] and button and button:IsShown() then
			E:ShowUserGlow(button, "questBar")
			C_Timer.After(3, function() E:HideGlow(button) end)
		end
	end
end

-- Read the bags and the quest log again. In combat only the counts and
-- cooldowns change; the rest waits for the end of combat.
-- fromEvent: a bag, quest or item event, which applies the buttons again
-- only when the items changed (a settings change always does).
function M:Update(fromEvent)
	if not (self.active and self.bar) then return end
	if InCombatLockdown() then
		self.dirty = true
		self:UpdateButtons()
		return
	end
	self.dirty = false
	local before = self.carried
	local list, carried = self:Scan()
	self.list, self.carried = list, carried
	if not (fromEvent and Signature(list) == self.appliedSignature) then self:ApplySecure() end
	self:UpdateButtons()
	self:GlowNew(before, list)
	self:UpdateVisibility()
	self:UpdateRange()
end

-- Bag and quest log events come in bursts: one read for a burst.
function M:Queue()
	if self.pending then return end
	self.pending = true
	C_Timer.After(0.2, function()
		M.pending = false
		M:Update(true)
	end)
end

---------------------------------------------------------------------------
-- Hidden items and keys
---------------------------------------------------------------------------
function M:HideItem(itemID)
	if type(itemID) ~= "number" then return end
	self.db.hidden = self.db.hidden or {}
	self.db.hidden[itemID] = true
	E:Print(L["%s stays off the Quest Item Bar. \"Show hidden items again\" on its options page brings it back."]:format(ItemName(itemID)))
	if InCombatLockdown() then E:Print(L["The bar changes when combat ends."]) end
	E:RunOutOfCombat(function() M:Update() end, APPLY_KEY)
end

function M:HiddenCount()
	local count = 0
	for _ in pairs(self.db.hidden or {}) do count = count + 1 end
	return count
end

function M:ShowHidden()
	self.db.hidden = {}
	E:RunOutOfCombat(function() M:Update() end, APPLY_KEY)
end

-- Keybind mode with every button shown until the mode closes.
function M:BindKeys()
	if not self.active then
		E:Print(L["Turn on the Quest Item Bar first."])
		return
	end
	if InCombatLockdown() then
		E:Print(L["Keys can't be bound in combat."])
		return
	end
	self.binding = true
	self:ApplySecure()
	self:UpdateButtons()
	self:UpdateVisibility()
	E:ToggleKeybindMode(true)
	E:KeybindStatus(L["Hover a button of the Quest Item Bar and press a key, then click Save."])
	E.Ticker:Subscribe(BIND_TICK, 0.5, function()
		if E:IsKeybindMode() then return end
		E.Ticker:Unsubscribe(BIND_TICK)
		M.binding = false
		E:RunOutOfCombat(function() M:Update() end, APPLY_KEY)
	end, M)
end

-- Key binding names (Bindings.xml): one per button.
E:NameBinding("BINDING_HEADER_ELDOUIQUESTBAR", E.Key("EldoUI Quest Item Bar"))
for index = 1, M.MAX do
	E:NameBinding(("BINDING_NAME_CLICK %s%d:LeftButton"):format(BUTTON, index), E.Key("Quest item %d (Quest Item Bar)"), index)
end

---------------------------------------------------------------------------
-- Events and lifecycle
---------------------------------------------------------------------------
local COOLDOWN_KEY = "QuestBar"
local EVENTS = { "BAG_UPDATE_DELAYED", "QUEST_LOG_UPDATE", "PLAYER_ENTERING_WORLD", "GET_ITEM_INFO_RECEIVED" }

function M:OnEnable()
	self:BuildBar()
	for _, event in ipairs(EVENTS) do
		self:RegisterEvent(event, function() M:Queue() end)
	end
	-- Whatever changed in combat is read once it ends.
	self:RegisterEvent("PLAYER_REGEN_ENABLED", function() if M.dirty then M:Update(true) end end)
	self:RegisterEvent("UPDATE_BINDINGS", function() M:UpdateButtons() end)
	local source = Cooldowns()
	if source then
		source.Subscribe(COOLDOWN_KEY, function(changes)
			if M.active and changes.items then M:UpdateCooldowns() end
		end)
	end
	self:Update()
end

function M:OnDisable()
	E.Ticker:UnsubscribeOwner(M)
	self.binding = false
	self.pending = false
	self.carried = nil -- turned on again later, its items are not new
	local source = Cooldowns()
	if source then source.Unsubscribe(COOLDOWN_KEY) end
	if self.holder then E:DetachVisibility(self.holder) end
	self.visibilityBlock = nil
	E:RunOutOfCombat(function()
		if M.active or not M.bar then return end
		for _, button in ipairs(M.buttons) do
			button:SetAttribute("item", nil)
			button:Hide()
			E:UnregisterKeybindButton(button)
		end
		M.bar:Hide()
		M.list, M.appliedSignature, M.shownButtons = nil, nil, 0
	end, APPLY_KEY)
end

function M:OnProfileChanged()
	if self.active then E:RunOutOfCombat(function() M:Update() end, APPLY_KEY) end
end

---------------------------------------------------------------------------
-- Options
---------------------------------------------------------------------------
M.options = {
	{ type = "description", label = "Every quest item in your bags that you can use gets a button: click it or press its key to use the item. Items that start a quest come too. The bar changes only out of combat. The Quest Tracker's quest item button keeps the tracked quest's item on its own key." },
	{ type = "header", label = "Which items", fold = true },
	{ type = "toggle", key = "starters", label = "Items that start a quest", desc = "Items with a \"!\" that start a quest you don't have yet. A click shows the quest." },
	{ type = "toggle", key = "complete", label = "Finished quests too", desc = "Also the item the quest log names for a quest that is ready to turn in." },
	{ type = "execute", label = "Show hidden items again", desc = "Items you left off the bar with Shift-right-click come back.",
		disabled = function() return M:HiddenCount() == 0 end, func = function() M:ShowHidden() end },
	{ type = "header", label = "Keybinds", fold = true },
	{ type = "execute", label = "Bind keys", desc = "Opens keybind mode with every button of the bar shown: hover one, press a key, then click Save. The first button holds the first quest item in your bags, and so on.",
		func = function() M:BindKeys() end },
	{ type = "toggle", key = "hotkey", label = "Key text", desc = "The bound key in the button's top corner." },
	{ type = "header", label = "Look", fold = true },
	{ type = "range", key = "buttonSize", label = "Button size", min = 20, max = 48, step = 1, desc = "Size of each button." },
	{ type = "range", key = "spacing", label = "Spacing", min = 0, max = 12, step = 1, desc = "Space between buttons." },
	{ type = "toggle", key = "vertical", label = "Vertical", desc = "Stack the buttons top to bottom." },
	{ type = "toggle", key = "showCount", label = "Counts", desc = "Show how many you carry." },
	{ type = "toggle", key = "range", label = "Out-of-range color", desc = "The icon turns red while the game says your target is out of the item's range. Only for the items the quest log names." },
	{ type = "toggle", key = "glow", label = "Glow on a new item", desc = "A button glows for a few seconds when a new quest item lands on it (look under the Glows page)." },
	{ type = "toggle", key = "masque", label = "Use Masque", reload = true, desc = E.MASQUE_OPTION_DESC,
		requires = function() return E:Masque() ~= nil end },
}
for _, row in ipairs(E:VisibilityOptions("visibility", { db = function() return M.db end, secure = true })) do
	table.insert(M.options, row)
end
