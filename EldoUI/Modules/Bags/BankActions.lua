-- EldoUI Bags, part eight: the bank's own actions in EldoUI's bank window.
-- Each one runs only on the player's click, and only where the game
-- offers it.
--
--   Buy a tab     a rail button at the bank while the game sells another
--                 tab, and a plus on the next tab of the bag bar when the
--                 bar is shown. Both are the game's own purchase button
--                 (the template Blizzard provides for addons): its click
--                 opens the game's confirm with the cost, and only that
--                 confirm buys the tab.
--   Deposit       a rail button puts everything that fits into the bank,
--                 the game's own deposit. Right-click deposits into the
--                 warband bank where it is shown; that one asks first, with
--                 the game's own message, when refundable items would lose
--                 their refund.
--   Tab settings  right-click a bank tab on the bag bar to rename it or
--                 choose which kinds of items it takes, as in the game's
--                 tab settings. The icon stays as it is.
--
-- Written from scratch for EldoUI.
local _, E = ...

local M = E:GetModule("Bags")
if not M then return end

local L = E.L

local BANK_CHARACTER = Enum.BankType and Enum.BankType.Character
local BANK_ACCOUNT = Enum.BankType and Enum.BankType.Account
local PURCHASE_TEMPLATE = "BankPanelPurchaseButtonScriptTemplate"
local NAME_LETTERS = 16

local function Ask(fn, ...)
	if not fn then return nil end
	local ok, value = pcall(fn, ...)
	if ok then return value end
end

---------------------------------------------------------------------------
-- Buy a tab
---------------------------------------------------------------------------
local function BuyTooltip(button)
	local bankType = button.bankType
	GameTooltip:SetOwner(button, "ANCHOR_TOP")
	GameTooltip:SetText(bankType == BANK_ACCOUNT and L["Buy the next account bank page"] or L["Buy the next bank tab"])
	local offer = C_Bank and Ask(C_Bank.FetchNextPurchasableBankTabData, bankType)
	local cost = type(offer) == "table" and offer.tabCost
	if type(cost) == "number" and not E:IsSecret(cost) then
		local money = GetMoneyString and GetMoneyString(cost, true) or tostring(cost)
		if offer.canAfford == false then
			E.UIKit.TipPair(GameTooltip, L["Cost"], money, E:TokenColor("bad"))
			GameTooltip:AddLine(L["You don't have enough gold yet."], E:TokenColor("bad"))
		else
			E.UIKit.TipPair(GameTooltip, L["Cost"], money)
		end
	end
	E:TooltipHint(GameTooltip, { L["Click"], L["buy it (the game asks first)"] })
	GameTooltip:Show()
end

local function Plus(button)
	local color = E.media.accentColor
	for index, size in ipairs({ { 10, 2 }, { 2, 10 } }) do
		local bar = button:CreateTexture(nil, "OVERLAY")
		bar:SetSize(size[1], size[2])
		bar:SetPoint("CENTER")
		bar:SetColorTexture(color[1], color[2], color[3], 1)
		button["plus" .. index] = bar
	end
end

-- One purchase button per bank type and window, made the first time the
-- bar has a tab to sell. Nil when the client has no such template.
local function BuyButton(window, bankType)
	window.buyButtons = window.buyButtons or {}
	local button = window.buyButtons[bankType]
	if button ~= nil then return button or nil end
	local ok, made = pcall(CreateFrame, "Button", nil, window.bar, PURCHASE_TEMPLATE)
	if not ok or not made then
		window.buyButtons[bankType] = false
		return nil
	end
	button = made
	button:SetAttribute("overrideBankType", bankType)
	button.bankType = bankType
	local hover = button:CreateTexture(nil, "HIGHLIGHT")
	hover:SetAllPoints()
	hover:SetColorTexture(1, 1, 1, E.tokens.hover.hud)
	Plus(button)
	button:SetScript("OnEnter", function(self)
		if self.barButton then self.barButton:SetBackdropBorderColor(unpack(E.media.accentColor)) end
		BuyTooltip(self)
	end)
	button:SetScript("OnLeave", function(self)
		GameTooltip_Hide()
		if self.barButton then M:PaintBarButton(self.barButton) end
	end)
	window.buyButtons[bankType] = button
	return button
end

-- After the bar is laid out: the purchase button covers the slot of the
-- next tab, one per bank type. In combat the buttons stay as they are and
-- follow the bar once combat ends.
local function PlaceBuyButtons(window)
	if InCombatLockdown() then
		E:RunOutOfCombat(function() PlaceBuyButtons(window) end, "Bags:buy:" .. tostring(window.kind))
		return
	end
	local used = {}
	if window.bar:IsShown() then
		for _, barButton in ipairs(window.barButtons or {}) do
			local entry = barButton:IsShown() and barButton.entry
			if entry and entry.buy and not used[entry.buy] then
				local button = BuyButton(window, entry.buy)
				if button then
					used[entry.buy] = true
					button.barButton = barButton
					button:ClearAllPoints()
					button:SetAllPoints(barButton)
					button:SetFrameLevel(barButton:GetFrameLevel() + 2)
					button:Show()
				end
			end
		end
	end
	for bankType, button in pairs(window.buyButtons or {}) do
		if button and not used[bankType] then
			button.barButton = nil
			button:Hide()
		end
	end
end

hooksecurefunc(M, "UpdateBar", function(_, window) PlaceBuyButtons(window) end)

-- The rail's purchase button: the game's purchase button laid over the
-- rail button, so the bank sells its next tab with or without the bag bar.
-- Nil when the client has no such template; the rail button then opens the
-- game's own bank window, which has its own purchase button.
local function RailBuyButton(window, railButton)
	if window.railBuy ~= nil then return window.railBuy or nil end
	local ok, made = pcall(CreateFrame, "Button", nil, railButton, PURCHASE_TEMPLATE)
	if not ok or not made then
		window.railBuy = false
		return nil
	end
	made:SetAllPoints(railButton)
	made:SetFrameLevel(railButton:GetFrameLevel() + 2)
	local hover = made:CreateTexture(nil, "HIGHLIGHT")
	hover:SetAllPoints()
	hover:SetColorTexture(1, 1, 1, E.tokens.hover.hud)
	made:SetScript("OnEnter", BuyTooltip)
	made:SetScript("OnLeave", GameTooltip_Hide)
	window.railBuy = made
	return made
end

-- The bank type whose next tab the window offers: the character bank
-- first, then the account bank where it is shown. Only for the live bank.
local function OfferedTab(window)
	if not (window.viewChar == E.charKey and M:BankIsOpen() and M.CanBuyBankTab) then return nil end
	if M.CanBuyBankTab(BANK_CHARACTER) then return BANK_CHARACTER end
	if M.AccountTabsShown() and M.CanBuyBankTab(BANK_ACCOUNT) then return BANK_ACCOUNT end
end
M.OfferedBankTab = OfferedTab

---------------------------------------------------------------------------
-- Deposit
---------------------------------------------------------------------------
local function CanDeposit(bankType)
	if not (bankType and M:BankIsOpen() and C_Bank and C_Bank.AutoDepositItemsIntoBank) then return false end
	if not C_Bank.DoesBankTypeSupportAutoDeposit then return false end
	return Ask(C_Bank.DoesBankTypeSupportAutoDeposit, bankType) == true
end
M.CanDeposit = CanDeposit

-- The warband bank takes refundable items for good: the game asks first,
-- as its own deposit button does.
local function LosesRefund()
	if not (ItemUtil and ItemUtil.IteratePlayerInventory and C_Bank.IsItemAllowedInBankType and C_Item.CanBeRefunded) then return false end
	return ItemUtil.IteratePlayerInventory(function(location)
		return C_Bank.IsItemAllowedInBankType(BANK_ACCOUNT, location) and C_Item.CanBeRefunded(location)
	end) and true or false
end

function M:Deposit(mouse)
	if InCombatLockdown() then return end
	if mouse == "RightButton" then
		if not (self.AccountTabsShown() and CanDeposit(BANK_ACCOUNT)) then return end
		if LosesRefund() and StaticPopupDialogs and StaticPopupDialogs.ACCOUNT_BANK_DEPOSIT_ALL_NO_REFUND_CONFIRM then
			StaticPopup_Show("ACCOUNT_BANK_DEPOSIT_ALL_NO_REFUND_CONFIRM", nil, nil, { bankType = BANK_ACCOUNT })
			return
		end
		C_Bank.AutoDepositItemsIntoBank(BANK_ACCOUNT)
		return
	end
	if CanDeposit(BANK_CHARACTER) then C_Bank.AutoDepositItemsIntoBank(BANK_CHARACTER) end
end

local RailButtons = M.RailButtons
function M.RailButtons(window, isBank)
	local list = RailButtons(window, isBank)
	if not isBank then return list end
	local deposit = { key = "deposit", art = E:ClientIcon("Interface\\Icons\\INV_Misc_Bag_10"), mono = true,
		tipTitle = L["Deposit everything"],
		tip = function(tooltip)
			E.UIKit.TipText(tooltip, L["Puts every item that fits into the bank, as the game's own deposit does."])
			if M.AccountTabsShown() and CanDeposit(BANK_ACCOUNT) then
				E.UIKit.TooltipHint(tooltip, { L["Right-click"], L["deposit into the account bank"] })
			end
		end,
		onClick = function(_, mouse) M:Deposit(mouse) end, options = { page = "module:Bags", key = "bankMode" } }
	local buy = { key = "buytab", art = E:ClientIcon("Interface\\Icons\\INV_Misc_Coin_01"), mono = true,
		tipTitle = L["Buy the next bank tab"], tip = L["Open the game's own bank window, e.g. to buy bank space."],
		onClick = function() M:ShowBlizzardBank() end }
	local at = #list + 1
	for index, def in ipairs(list) do
		if def.key == "blizzard" then at = index + 1 end
	end
	table.insert(list, at, deposit)
	table.insert(list, at + 1, buy)
	return list
end

-- The rail button shows only at the bank, where the game supports it.
hooksecurefunc(M, "UpdateWindow", function(_, window)
	local button = window and window.kind == "bank" and window.rail and window.rail.buttons.deposit
	if not button then return end
	if not button.eldoClicks then
		button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		button.eldoClicks = true
	end
	local shown = window.viewChar == E.charKey and (CanDeposit(BANK_CHARACTER) or (M.AccountTabsShown() and CanDeposit(BANK_ACCOUNT)))
	local layout = false
	if button:IsShown() ~= (shown and true or false) then
		button:SetShown(shown)
		layout = true
	end
	-- The next tab to buy, on the rail.
	local railButton = window.rail.buttons.buytab
	if railButton then
		local bankType = OfferedTab(window)
		local overlay = bankType and RailBuyButton(window, railButton)
		if overlay then
			overlay:SetAttribute("overrideBankType", bankType)
			overlay.bankType = bankType
		end
		if railButton:IsShown() ~= (bankType ~= nil) then
			railButton:SetShown(bankType ~= nil)
			layout = true
		end
	end
	if layout then window.rail:Layout() end
end)

---------------------------------------------------------------------------
-- Tab settings
---------------------------------------------------------------------------
local function WriteTab(bankType, id, change)
	local Tab = M.BankTab
	local tab = Tab.Fresh(bankType, id)
	if not tab or InCombatLockdown() or not M:BankIsOpen() then return end
	local name, flags = change(tab.name or "", tab.depositFlags or 0)
	C_Bank.UpdateBankTabSettings(bankType, tab.ID, name, tab.icon or 134400, flags) -- 134400: the question mark icon
end

function M:RenameBankTab(entry)
	local bankType = entry.kind == "account" and BANK_ACCOUNT or BANK_CHARACTER
	local tab = self.BankTab.Fresh(bankType, entry.bag)
	if not tab then return end
	E:ShowConfirm({
		title = L["Rename bank tab"],
		text = L["The name shows on the tab, in the game's bank and in EldoUI's."],
		edit = { text = tab.name or "", maxLetters = NAME_LETTERS },
		accept = L["Rename"],
		onAccept = function(_, text)
			text = strtrim(text or "")
			WriteTab(bankType, entry.bag, function(_, flags) return text, flags end)
		end,
	})
end

-- Called from the bag bar's tab menu (Core.lua ShowBagMenu), after the
-- sorting toggle.
function M:AddBankTabSettings(root, entry)
	local flags = Enum.BagSlotFlags
	if not (flags and self:BankIsOpen() and C_Bank and C_Bank.UpdateBankTabSettings) then return end
	local bankType = entry.kind == "account" and BANK_ACCOUNT or BANK_CHARACTER
	if not bankType then return end
	local Tab = self.BankTab
	root:CreateButton(L["Rename"], function() M:RenameBankTab(entry) end)
	root:CreateDivider()
	root:CreateTitle(E:GameText(BAG_FILTER_ASSIGN_TO, L["Assign to"]))
	for _, pair in ipairs(Tab.SORT_FLAGS) do
		local flag = flags[pair[1]]
		if flag then
			root:CreateCheckbox(E:Translate(pair[2]), function()
				local tab = Tab.Fresh(bankType, entry.bag)
				return tab and Tab.HasFlag(tab.depositFlags, flag) or false
			end, function()
				WriteTab(bankType, entry.bag, function(name, value)
					return name, Tab.Flags(value, flag, not Tab.HasFlag(value, flag))
				end)
			end)
		end
	end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local function Valid(event)
	return not (C_EventUtils and C_EventUtils.IsEventValid) or C_EventUtils.IsEventValid(event)
end

hooksecurefunc(M, "OnEnable", function(self)
	-- A new name or deposit setting redraws the tab's tooltip and menu.
	if Valid("BANK_TAB_SETTINGS_UPDATED") then
		self:RegisterEvent("BANK_TAB_SETTINGS_UPDATED", function() self:RefreshViews() end)
	end
end)
