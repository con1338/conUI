-- EldoUI Bags, part nine: the guild bank in EldoUI's own window, when the
-- Bags page's "Guild bank" choice is "EldoUI window". The game's guild bank
-- window keeps running out of sight, so the game still decides when the
-- guild bank is open; EldoUI's window opens and closes with it, and
-- closing EldoUI's window closes the guild bank.
--
--   Tabs        the column on the left, one button per tab; the tooltip
--               names the tab and the withdrawals left today. The guild
--               leader also gets a plus to buy the next tab (the game's
--               own confirm with the cost).
--   Slots       the tab's 98 slots in the game's order (14 by 7), with the
--               bag window's slot look and search. Clicks act as in the
--               game's window: pick up, right-click to the bags,
--               Shift-click to split, modified clicks link, drag in and
--               out, money on the cursor goes into the bank.
--   Rail        item log, money log and tab info take the slots' place;
--               the tab info is saved with its Save button by whoever may
--               edit it.
--   Footer      the guild's gold, what you may still withdraw today, and
--               Deposit and Withdraw (the game's own money dialogs).
--
-- Every item and money action is the player's click and one game call.
-- Written from scratch for EldoUI.
local _, E = ...

local M = E:GetModule("Bags")
if not M then return end

local L = E.L
local Kit = E.UIKit

-- The game's own words (global strings), read as they are.
local function G(name)
	return rawget(_G, name)
end

-- Slot size and spacing come from the bag window's settings (Layout).
local SLOT, GAP = 34, 4
local COLUMNS, ROWS = 14, 7
local SLOTS = COLUMNS * ROWS
local TAB_SIZE = 30
local TOP = 30 -- search line
local MAX_TABS = MAX_GUILDBANK_TABS or 8
local MONEY_LOG = MAX_TABS + 1

local win          -- the window, built on first use
local tab = 1      -- the tab on show
local mode = "bank" -- bank / log / moneylog / info
local closing = false

-- The game's own window, out of sight while EldoUI's shows.
local hidden = CreateFrame("Frame", nil, UIParent)
hidden:SetScale(0.001)
hidden:SetAlpha(0)
hidden:SetPoint("TOPLEFT")
hidden:SetSize(1, 1)
local blizzardParent

function M:OwnGuildBank()
	return self.active and self.db.guildBank == "eldoui"
end

local function HideBlizzard()
	local frame = rawget(_G, "GuildBankFrame")
	if not frame or frame:GetParent() == hidden then return end
	E:RunOutOfCombat(function()
		if not M:OwnGuildBank() or frame:GetParent() == hidden then return end
		blizzardParent = blizzardParent or frame:GetParent() or UIParent
		frame:SetParent(hidden)
	end)
end

local function RestoreBlizzard()
	local frame = rawget(_G, "GuildBankFrame")
	if not (frame and blizzardParent) then return end
	E:RunOutOfCombat(function()
		frame:SetParent(blizzardParent)
		blizzardParent = nil
	end)
end

local function Call(fn, ...)
	if not fn then return nil end
	return fn(...)
end

local function TabInfo(index)
	if not GetGuildBankTabInfo then return nil end
	local name, icon, viewable, canDeposit, numWithdrawals, remaining = GetGuildBankTabInfo(index)
	if not name then return nil end
	return { name = name, icon = icon, viewable = viewable, canDeposit = canDeposit, withdrawals = numWithdrawals, remaining = remaining }
end

local function Withdrawals(info)
	if not info then return "" end
	local left = info.remaining
	if left == nil or left < 0 then return L["Withdrawals: unlimited"] end
	return L["Withdrawals left today: %d"]:format(left)
end

-- Money in the Money style, as in the bag and bank windows.
local function Money(copper)
	if type(copper) ~= "number" then return "" end
	return M.Money(copper)
end

---------------------------------------------------------------------------
-- Slots
---------------------------------------------------------------------------
-- The game's window shows seven columns of two by seven slots: slot IDs
-- run down each pair of columns. Column x (1-14), row y (1-7) -> slot.
local function SlotAt(x, y)
	local pair = math.floor((x - 1) / 2)
	return pair * ROWS * 2 + ((x - 1) % 2) * ROWS + y
end
M.GuildSlotAt = SlotAt

local function Record(slot)
	local texture, count, locked, _, quality = GetGuildBankItemInfo(tab, slot)
	if not texture then return { slot = slot, empty = true } end
	local link = GetGuildBankItemLink(tab, slot)
	local id = link and tonumber(link:match("item:(%d+)"))
	return { slot = slot, icon = texture, count = count, locked = locked, quality = quality, link = link, id = id,
		short = M.ShortItem(link) or "" }
end

local function SlotClick(button, mouse)
	local slot = button:GetID()
	if HandleModifiedItemClick(GetGuildBankItemLink(tab, slot)) then return end
	if IsModifiedClick("SPLITSTACK") then
		if not CursorHasItem() then
			local _, count, locked = GetGuildBankItemInfo(tab, slot)
			if not locked and count and count > 1 and StackSplitFrame then
				StackSplitFrame:OpenStackSplitFrame(count, button, "BOTTOMLEFT", "TOPLEFT")
			end
		end
		return
	end
	local kind, money = GetCursorInfo()
	if kind == "money" then
		DepositGuildBankMoney(money)
		ClearCursor()
	elseif kind == "guildbankmoney" then
		DropCursorMoney()
		ClearCursor()
	elseif mouse == "RightButton" then
		AutoStoreGuildBankItem(tab, slot)
		GameTooltip_Hide()
	else
		PickupGuildBankItem(tab, slot)
	end
end

local function SlotEnter(button)
	if not GameTooltip.SetGuildBankItem then return end
	GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
	GameTooltip:SetGuildBankItem(tab, button:GetID())
	GameTooltip:Show()
end

local function MakeSlot(parent, slot)
	local button = CreateFrame("ItemButton", "EldoUI_GuildBankSlot" .. slot, parent)
	button:SetSize(SLOT, SLOT)
	button:SetID(slot)
	M.StyleSlot(button)
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button:RegisterForDrag("LeftButton")
	button:SetScript("OnClick", SlotClick)
	button:SetScript("OnEnter", SlotEnter)
	button:SetScript("OnLeave", function()
		GameTooltip_Hide()
		ResetCursor()
	end)
	button:SetScript("OnDragStart", function(self) PickupGuildBankItem(tab, self:GetID()) end)
	button:SetScript("OnReceiveDrag", function(self) PickupGuildBankItem(tab, self:GetID()) end)
	button:SetScript("OnHide", function(self)
		if self.hasStackSplit == 1 and StackSplitFrame then StackSplitFrame:Hide() end
	end)
	-- The game's split frame calls this with the amount picked.
	button.SplitStack = function(self, split) SplitGuildBankItem(tab, self:GetID(), split) end
	return button
end

function M:PaintGuildSlots()
	if not (win and win:IsShown() and mode == "bank") then return end
	local query = win.query
	local found = 0
	for slot, button in pairs(win.slots) do
		local record = Record(slot)
		button.eldoRecord = record
		local icon = button.icon or button.Icon
		if record.empty then
			icon:SetTexture(nil)
			M.PaintSlotEmpty(button, nil, nil, query and 0.4 or 1)
		else
			icon:SetTexture(record.icon)
			local alpha = 1
			if query and not M.Matches(query, record) then alpha = 0.2 elseif query then found = found + 1 end
			M.PaintSlotItem(button, record, alpha)
			icon:SetDesaturated(record.locked and true or false)
		end
	end
	-- "No matches" while a search finds nothing in this tab; typed text
	-- stops before it.
	local line, search = win.noMatch, win.search
	if line then
		local base = search.eldoInsets or {}
		local left, right, top, bottom = base[1] or 0, base[2] or 0, base[3] or 0, base[4] or 0
		if query and found == 0 then
			line:SetText(L["No matches"])
			line:Show()
			local width = line.GetUnboundedStringWidth and line:GetUnboundedStringWidth() or line:GetStringWidth() or 0
			search:SetTextInsets(left, math.max(right, width + 24), top, bottom)
		else
			line:Hide()
			search:SetTextInsets(left, right, top, bottom)
		end
	end
end

---------------------------------------------------------------------------
-- Tabs
---------------------------------------------------------------------------
local function CanBuyTab(count)
	return IsGuildLeader and IsGuildLeader() and count < MAX_TABS and GetGuildBankTabCost and (GetGuildBankTabCost() or 0) > 0
end

local function TabEnter(button)
	GameTooltip:SetOwner(button, "ANCHOR_LEFT")
	if button.buy then
		GameTooltip:SetText(G("BUY_GUILDBANK_TAB") or L["Buy a guild bank tab"])
		Kit.TipPair(GameTooltip, L["Cost"], Money(GetGuildBankTabCost()))
		E:TooltipHint(GameTooltip, { L["Click"], L["buy it (the game asks first)"] })
	else
		local info = TabInfo(button.index)
		GameTooltip:SetText(info and info.name or "")
		if info and not info.viewable then
			GameTooltip:AddLine(L["You can't view this tab."], E:TokenColor("bad"))
		else
			Kit.TipText(GameTooltip, Withdrawals(info))
		end
	end
	GameTooltip:Show()
end

local function TabButton(index)
	local button = win.tabButtons[index]
	if button then return button end
	button = CreateFrame("Button", nil, win.tabColumn)
	button:SetSize(TAB_SIZE, TAB_SIZE)
	E:SetTemplate(button)
	button.icon = button:CreateTexture(nil, "ARTWORK")
	button.icon:SetPoint("TOPLEFT", E.pixel, -E.pixel)
	button.icon:SetPoint("BOTTOMRIGHT", -E.pixel, E.pixel)
	E:TrimIcon(button.icon)
	local hover = button:CreateTexture(nil, "HIGHLIGHT")
	hover:SetAllPoints(button.icon)
	hover:SetColorTexture(1, 1, 1, E.tokens.hover.hud)
	-- The plus of the tab to buy.
	button.plus = {}
	for part, size in ipairs({ { 12, 2 }, { 2, 12 } }) do
		local bar = button:CreateTexture(nil, "OVERLAY")
		bar:SetSize(size[1], size[2])
		bar:SetPoint("CENTER")
		button.plus[part] = bar
	end
	button:SetPoint("TOP", win.tabColumn, "TOP", 0, -((index - 1) * (TAB_SIZE + GAP)))
	button:SetScript("OnEnter", TabEnter)
	button:SetScript("OnLeave", GameTooltip_Hide)
	button:SetScript("OnClick", function(self)
		if self.buy then
			StaticPopup_Show("CONFIRM_BUY_GUILDBANK_TAB")
			return
		end
		M:SelectGuildTab(self.index)
	end)
	win.tabButtons[index] = button
	return button
end

function M:UpdateGuildTabs()
	if not win then return end
	local count = Call(GetNumGuildBankTabs) or 0
	local shown = 0
	for index = 1, count do
		local info = TabInfo(index)
		local button = TabButton(index)
		button.index, button.buy = index, nil
		button.icon:SetTexture(info and info.icon or 134400) -- 134400: the question mark icon
		button.icon:SetDesaturated(not (info and info.viewable))
		for _, bar in ipairs(button.plus) do bar:Hide() end
		local r, g, b = unpack(index == tab and E.media.accentColor or E.media.borderColor)
		button:SetBackdropBorderColor(r, g, b)
		button:Show()
		shown = index
	end
	if CanBuyTab(count) then
		shown = count + 1
		local button = TabButton(shown)
		button.index, button.buy = shown, true
		button.icon:SetTexture(nil)
		local accent = E.media.accentColor
		for _, bar in ipairs(button.plus) do
			bar:SetColorTexture(accent[1], accent[2], accent[3], 1)
			bar:Show()
		end
		button:SetBackdropBorderColor(unpack(E.media.borderColor))
		button:Show()
	end
	for index = shown + 1, #win.tabButtons do win.tabButtons[index]:Hide() end
	self:UpdateGuildTitle()
end

function M:UpdateGuildTitle()
	if not win then return end
	local info = TabInfo(tab)
	local guild = GetGuildInfo and GetGuildInfo("player")
	win:SetTitle(guild or (G("GUILD_BANK") or L["Guild bank"]), info and info.name or nil)
	win.tabText:SetText(Withdrawals(info))
end

function M:SelectGuildTab(index)
	if win.info:IsShown() and win.info.dirty then self:SaveGuildInfo() end
	tab = index
	if SetCurrentGuildBankTab then SetCurrentGuildBankTab(index) end
	if mode == "log" then
		Call(QueryGuildBankTab, index)
		Call(QueryGuildBankLog, index)
	elseif mode == "info" then
		Call(QueryGuildBankText, index)
	elseif mode == "bank" then
		Call(QueryGuildBankTab, index)
	end
	self:UpdateGuildTabs()
	self:UpdateGuildView()
end

---------------------------------------------------------------------------
-- Logs and tab info
---------------------------------------------------------------------------
local function When(year, month, day, hour)
	if not (G("GUILD_BANK_LOG_TIME") and TimeUtil and TimeUtil.GetRecentTimeDate) then return "" end
	return G("GUILD_BANK_LOG_TIME"):format(TimeUtil.GetRecentTimeDate(year, month, day, hour))
end

local function Who(name)
	return E:TextHex("accent") .. (name or UNKNOWN or "?") .. "|r"
end

local MONEY_FORMATS = {
	deposit = "GUILDBANK_DEPOSIT_MONEY_FORMAT", withdraw = "GUILDBANK_WITHDRAW_MONEY_FORMAT",
	repair = "GUILDBANK_REPAIR_MONEY_FORMAT", withdrawForTab = "GUILDBANK_WITHDRAWFORTAB_MONEY_FORMAT",
	buyTab = "GUILDBANK_BUYTAB_MONEY_FORMAT", buyRename = "GUILDBANK_GUILD_RENAME_PURCHASE",
	refundRename = "GUILDBANK_GUILD_RENAME_REFUND",
}

-- The log lines, newest last, written with the game's own phrases.
function M:GuildLogLines(which)
	local lines = {}
	if which == "moneylog" then
		for index = 1, Call(GetNumGuildBankMoneyTransactions) or 0 do
			local kind, name, amount, year, month, day, hour = GetGuildBankMoneyTransaction(index)
			amount = amount or 0
			local money = GetDenominationsFromCopper and GetDenominationsFromCopper(amount) or Money(amount)
			local text
			if kind == "depositSummary" then
				text = G("GUILDBANK_AWARD_MONEY_SUMMARY_FORMAT") and G("GUILDBANK_AWARD_MONEY_SUMMARY_FORMAT"):format(money)
			elseif kind == "buyTab" and amount <= 0 then
				text = G("GUILDBANK_UNLOCKTAB_FORMAT") and G("GUILDBANK_UNLOCKTAB_FORMAT"):format(Who(name))
			else
				local pattern = MONEY_FORMATS[kind] and rawget(_G, MONEY_FORMATS[kind])
				text = pattern and pattern:format(Who(name), money)
			end
			if text then lines[#lines + 1] = text .. When(year, month, day, hour) end
		end
		return lines
	end
	for index = 1, Call(GetNumGuildBankTransactions, tab) or 0 do
		local kind, name, link, count, tab1, tab2, year, month, day, hour = GetGuildBankTransaction(tab, index)
		local text
		if kind == "deposit" or kind == "withdraw" then
			local pattern = kind == "deposit" and G("GUILDBANK_DEPOSIT_FORMAT") or G("GUILDBANK_WITHDRAW_FORMAT")
			text = pattern and pattern:format(Who(name), link or "")
			if text and count and count > 1 and G("GUILDBANK_LOG_QUANTITY") then text = text .. G("GUILDBANK_LOG_QUANTITY"):format(count) end
		elseif kind == "move" and G("GUILDBANK_MOVE_FORMAT") then
			text = G("GUILDBANK_MOVE_FORMAT"):format(Who(name), link or "", count or 1, GetGuildBankTabInfo(tab1) or "", GetGuildBankTabInfo(tab2) or "")
		end
		if text then lines[#lines + 1] = text .. When(year, month, day, hour) end
	end
	return lines
end

function M:UpdateGuildLog()
	if not (win and (mode == "log" or mode == "moneylog")) then return end
	local lines = self:GuildLogLines(mode)
	local text = #lines > 0 and table.concat(lines, "\n") or L["Nothing in this log yet."]
	win.logText:SetText(text)
	local area = win.log
	win.logText:SetWidth(math.max((area.scroll:GetWidth() or 0) - 4, 100))
	area.child:SetHeight(math.max(win.logText:GetStringHeight() + 8, 1))
	area:Update()
	-- Newest at the bottom, as in the game's window.
	area.scroll:SetVerticalScroll(area:Range())
	area:Update()
end

function M:UpdateGuildInfo()
	if not (win and mode == "info") then return end
	local text = Call(GetGuildBankText, tab) or ""
	local edit = win.infoEdit
	if not edit:HasFocus() then
		edit:SetText(text)
		win.info.dirty = nil
	end
	local canEdit = CanEditGuildBankTabInfo and CanEditGuildBankTabInfo() or false
	edit:EnableMouse(canEdit)
	edit:EnableKeyboard(canEdit)
	win.infoSave:SetShown(canEdit)
	win.infoNote:SetShown(not canEdit)
end

function M:SaveGuildInfo()
	if not (win and CanEditGuildBankTabInfo and CanEditGuildBankTabInfo() and SetGuildBankText) then return end
	SetGuildBankText(tab, win.infoEdit:GetText() or "")
	win.info.dirty = nil
	win.infoEdit:ClearFocus()
end

function M:SetGuildMode(which)
	if mode == which then which = "bank" end
	if mode == "info" and win.info.dirty then self:SaveGuildInfo() end
	mode = which
	if which == "log" then
		Call(QueryGuildBankTab, tab)
		Call(QueryGuildBankLog, tab)
	elseif which == "moneylog" then
		Call(QueryGuildBankLog, MONEY_LOG)
	elseif which == "info" then
		Call(QueryGuildBankText, tab)
	else
		Call(QueryGuildBankTab, tab)
	end
	self:UpdateGuildView()
end

function M:GuildMode()
	return mode, tab
end

function M:UpdateGuildView()
	if not win then return end
	win.grid:SetShown(mode == "bank")
	win.log:SetShown(mode == "log" or mode == "moneylog")
	win.info:SetShown(mode == "info")
	win.search:SetShown(mode == "bank")
	for key, button in pairs(win.rail.buttons) do M.SetRailActive(button, key == mode) end
	if mode == "bank" then
		self:PaintGuildSlots()
	elseif mode == "info" then
		self:UpdateGuildInfo()
	else
		self:UpdateGuildLog()
	end
end

---------------------------------------------------------------------------
-- Footer: the guild's gold
---------------------------------------------------------------------------
function M:UpdateGuildMoney()
	if not win then return end
	local parts = { L["Guild gold: %s"]:format(Money(Call(GetGuildBankMoney) or 0)) }
	local canWithdraw = CanWithdrawGuildBankMoney and CanWithdrawGuildBankMoney()
	if canWithdraw then
		local allowed = Call(GetGuildBankWithdrawMoney) or 0
		if allowed < 0 then
			parts[#parts + 1] = L["You may withdraw: unlimited"]
		else
			parts[#parts + 1] = L["You may withdraw: %s"]:format(Money(allowed))
		end
	end
	win.footerText:SetText(table.concat(parts, "   "))
	win.withdraw:SetShown(canWithdraw and true or false)
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------
local function Clamp(value, low, high, fallback)
	value = tonumber(value) or fallback
	return math.min(math.max(value, low), high)
end

-- The window's size for the bag window's Slot size and Spacing.
local function Measure()
	local db = M.db or {}
	SLOT, GAP = Clamp(db.size, 24, 52, 34), Clamp(db.spacing, 0, 10, 4)
	local inner = COLUMNS * (SLOT + GAP) - GAP
	local width = Kit.TOOL_PAD * 2 + TAB_SIZE + 10 + inner + 10 + E.tokens.rail.width
	local height = Kit.TOOL_HEADER + Kit.TOOL_PAD * 2 + TOP + ROWS * (SLOT + GAP) - GAP + Kit.TOOL_FOOTER
	return width, height, inner
end

-- Slot size, spacing and window size follow the bag window's settings.
local function Layout()
	if not win then return end
	local width, height, inner = Measure()
	win:SetSize(width, height)
	win:SetScale(Clamp(M.db and M.db.scale, 0.5, 1.5, 1))
	for x = 1, COLUMNS do
		for y = 1, ROWS do
			local button = win.slots[SlotAt(x, y)]
			button:SetSize(SLOT, SLOT)
			button:ClearAllPoints()
			button:SetPoint("TOPLEFT", (x - 1) * (SLOT + GAP), -((y - 1) * (SLOT + GAP)))
		end
	end
	for index, button in pairs(win.tabButtons) do
		button:ClearAllPoints()
		button:SetPoint("TOP", win.tabColumn, "TOP", 0, -((index - 1) * (TAB_SIZE + GAP)))
	end
	if win.infoEdit then win.infoEdit:SetWidth(inner - 40) end
end
M.LayoutGuildBank = Layout

local function Build()
	local railWidth = E.tokens.rail.width
	local width, height, inner = Measure()
	win = Kit.CreateToolWindow("EldoUI_GuildBankWindow", { title = G("GUILD_BANK") or L["Guild bank"], width = width, height = height,
		footer = Kit.TOOL_FOOTER, resizable = false, movable = false })
	E:BindOptionsLink(win, { page = "module:Bags", key = "guildBank" })
	local content = win.content

	win.tabColumn = CreateFrame("Frame", nil, content)
	win.tabColumn:SetPoint("TOPLEFT", 0, 0)
	win.tabColumn:SetPoint("BOTTOMLEFT", 0, 0)
	win.tabColumn:SetWidth(TAB_SIZE)
	win.tabButtons = {}

	local main = CreateFrame("Frame", nil, content)
	main:SetPoint("TOPLEFT", TAB_SIZE + 10, 0)
	main:SetPoint("BOTTOMRIGHT", -(railWidth + 10), 0)
	win.main = main

	win.search = Kit.Input(main, { width = 200, hint = G("SEARCH") or L["Search"], maxLetters = 60,
		tipTitle = L["Search"], tip = L["The bag window's search words work here too."] })
	win.search:SetPoint("TOPLEFT", 0, 0)
	win.search:SetScript("OnTextChanged", function(self)
		local text = self:GetText() or ""
		win.query = text ~= "" and M.ParseQuery(text) or nil
		M:PaintGuildSlots()
	end)
	-- "No matches", as in the bag window.
	win.noMatch = Kit.Text(win.search, E.tokens.size.small, "RIGHT", "secondary")
	if win.search.clearButton then
		win.noMatch:SetPoint("RIGHT", win.search.clearButton, "LEFT", -4, 0)
	else
		win.noMatch:SetPoint("RIGHT", win.search, "RIGHT", -20, 0)
	end
	win.noMatch:Hide()
	win.search.eldoInsets = { win.search:GetTextInsets() }
	win.tabText = Kit.Text(main, E.tokens.size.label, "RIGHT", "secondary")
	win.tabText:SetPoint("TOPRIGHT", 0, -6)
	win.tabText:SetPoint("TOPLEFT", win.search, "TOPRIGHT", 10, -6)

	win.grid = CreateFrame("Frame", nil, main)
	win.grid:SetPoint("TOPLEFT", 0, -TOP)
	win.grid:SetPoint("BOTTOMRIGHT")
	win.slots = {}
	for x = 1, COLUMNS do
		for y = 1, ROWS do
			local slot = SlotAt(x, y)
			local button = MakeSlot(win.grid, slot)
			button:SetPoint("TOPLEFT", (x - 1) * (SLOT + GAP), -((y - 1) * (SLOT + GAP)))
			win.slots[slot] = button
		end
	end

	-- Logs in the slots' place.
	win.log = Kit.ScrollArea(main)
	win.log:SetPoint("TOPLEFT", 0, -TOP)
	win.log:SetPoint("BOTTOMRIGHT")
	win.logText = Kit.Text(win.log.child, E.tokens.size.body, "LEFT")
	win.logText:SetPoint("TOPLEFT", 2, -4)
	win.logText:SetJustifyV("TOP")
	win.logText:SetSpacing(3)
	win.log:Hide()

	-- Tab info in the slots' place.
	local info = CreateFrame("Frame", nil, main)
	info:SetPoint("TOPLEFT", 0, -TOP)
	info:SetPoint("BOTTOMRIGHT")
	info:Hide()
	win.info = info
	local box = Kit.ScrollArea(info)
	box:SetPoint("TOPLEFT")
	box:SetPoint("BOTTOMRIGHT", 0, 34)
	E:SetTemplate(box)
	local edit = CreateFrame("EditBox", nil, box.child)
	edit:SetMultiLine(true)
	edit:SetAutoFocus(false)
	edit:SetMaxLetters(500)
	edit:SetFontObject(ChatFontNormal)
	E:SetFont(edit, E.tokens.size.body)
	edit:SetPoint("TOPLEFT", 6, -6)
	edit:SetWidth(inner - 40)
	edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	edit:SetScript("OnTextChanged", function(self, user)
		if user then info.dirty = true end
		box.child:SetHeight(math.max(self:GetHeight() + 12, 1))
		box:Update()
	end)
	box:EnableMouse(true)
	box:SetScript("OnMouseDown", function() if edit:IsMouseEnabled() then edit:SetFocus() end end) -- EldoUI's own edit box
	win.infoEdit = edit
	win.infoSave = Kit.Button(info, G("SAVE_CHANGES") or L["Save"], { kind = "primary", onClick = function() M:SaveGuildInfo() end })
	win.infoSave:SetPoint("BOTTOMRIGHT")
	win.infoNote = Kit.Text(info, E.tokens.size.label, "LEFT", "secondary")
	win.infoNote:SetPoint("BOTTOMLEFT", 0, 8)
	win.infoNote:SetText(L["Only members the guild allows can change this text."])

	-- Side rail: the logs and the tab info.
	win.rail = Kit.IconRail(content, { side = "RIGHT", buttons = {
		{ key = "log", art = E:ClientIcon("Interface\\Icons\\INV_Misc_Book_09"), mono = true,
			tipTitle = G("GUILD_BANK_LOG") or L["Log"], tip = L["Who put in and took out what, in this tab."],
			onClick = function() M:SetGuildMode("log") end, options = { page = "module:Bags", key = "guildBank" } },
		{ key = "moneylog", art = E:ClientIcon("Interface\\Icons\\INV_Misc_Coin_02"), mono = true,
			tipTitle = G("GUILD_BANK_MONEY_LOG") or L["Money log"], tip = L["Who put in and took out gold."],
			onClick = function() M:SetGuildMode("moneylog") end, options = { page = "module:Bags", key = "guildBank" } },
		{ key = "info", art = E:ClientIcon("Interface\\Icons\\INV_Misc_Note_01"), mono = true,
			tipTitle = G("GUILD_BANK_TAB_INFO") or L["Tab info"], tip = L["The tab's text, for the whole guild."],
			onClick = function() M:SetGuildMode("info") end, options = { page = "module:Bags", key = "guildBank" } },
	} })
	win.rail:SetPoint("TOPRIGHT", 0, 0)
	win.rail:SetPoint("BOTTOMRIGHT", 0, 0)
	for _, button in pairs(win.rail.buttons) do
		local mark = button:CreateTexture(nil, "OVERLAY")
		mark:SetPoint("TOPLEFT", -3, 0)
		mark:SetPoint("BOTTOMLEFT", -3, 0)
		mark:SetWidth(2)
		E:AccentTexture(mark)
		mark:Hide()
		button.activeMark = mark
	end

	-- Footer: gold and the game's money dialogs.
	win.footerText:ClearAllPoints()
	win.footerText:SetPoint("LEFT", 12, 0)
	win.deposit = Kit.Button(win.footer, G("DEPOSIT") or L["Deposit"], { onClick = function()
		StaticPopup_Hide("GUILDBANK_WITHDRAW")
		if StaticPopup_Visible("GUILDBANK_DEPOSIT") then StaticPopup_Hide("GUILDBANK_DEPOSIT") else StaticPopup_Show("GUILDBANK_DEPOSIT") end
	end, tipTitle = L["Deposit gold"], tip = L["Opens the game's own gold deposit."] })
	win.deposit:SetPoint("RIGHT", -Kit.TOOL_PAD, 0)
	win.withdraw = Kit.Button(win.footer, G("WITHDRAW") or L["Withdraw"], { onClick = function()
		StaticPopup_Hide("GUILDBANK_DEPOSIT")
		if StaticPopup_Visible("GUILDBANK_WITHDRAW") then StaticPopup_Hide("GUILDBANK_WITHDRAW") else StaticPopup_Show("GUILDBANK_WITHDRAW") end
	end, tipTitle = L["Withdraw gold"], tip = L["Opens the game's own gold withdrawal."] })
	win.withdraw:SetPoint("RIGHT", win.deposit, "LEFT", -6, 0)
	win.footerText:SetPoint("RIGHT", win.withdraw, "LEFT", -10, 0)

	-- On the Guild bank mover, which every layout places.
	function win:Place()
		local anchor = M.GuildAnchor and M.GuildAnchor()
		self:ClearAllPoints()
		if anchor then
			self:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, 0)
		else
			self:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 20, -120)
		end
	end

	win:HookScript("OnHide", function()
		if win.info.dirty then M:SaveGuildInfo() end
		if M.db and M.db.clearSearch and (win.search:GetText() or "") ~= "" then win.search:SetText("") end
		StaticPopup_Hide("GUILDBANK_WITHDRAW")
		StaticPopup_Hide("GUILDBANK_DEPOSIT")
		StaticPopup_Hide("CONFIRM_BUY_GUILDBANK_TAB")
		if not closing and CloseGuildBankFrame then CloseGuildBankFrame() end
	end)
	return win
end

function M:GuildBankWindow()
	return win
end

function M:OpenGuildBank()
	if not self:OwnGuildBank() then return end
	HideBlizzard()
	if not win then Build() end
	mode = "bank"
	tab = Call(GetCurrentGuildBankTab) or 1
	local count = Call(GetNumGuildBankTabs) or 0
	if tab > count then tab = math.max(count, 1) end
	Layout()
	win:Place()
	win:Open()
	self:SelectGuildTab(tab)
	self:UpdateGuildMoney()
end

function M:CloseGuildBank()
	if win and win:IsShown() then
		closing = true
		win:Hide()
		closing = false
	end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local function Valid(event)
	return not (C_EventUtils and C_EventUtils.IsEventValid) or C_EventUtils.IsEventValid(event)
end

hooksecurefunc(M, "OnEnable", function(self)
	local function Shown() return win and win:IsShown() end
	local handlers = {
		GUILDBANKFRAME_OPENED = function() self:OpenGuildBank() end,
		GUILDBANKFRAME_CLOSED = function() self:CloseGuildBank() end,
		GUILDBANKBAGSLOTS_CHANGED = function() if Shown() then self:PaintGuildSlots() end end,
		GUILDBANK_ITEM_LOCK_CHANGED = function() if Shown() then self:PaintGuildSlots() end end,
		GUILDBANK_UPDATE_TABS = function() if Shown() then self:UpdateGuildTabs() self:PaintGuildSlots() end end,
		GUILDBANKLOG_UPDATE = function() if Shown() then self:UpdateGuildLog() end end,
		GUILDBANK_UPDATE_MONEY = function() if Shown() then self:UpdateGuildMoney() end end,
		GUILDBANK_UPDATE_WITHDRAWMONEY = function() if Shown() then self:UpdateGuildMoney() self:UpdateGuildTitle() end end,
		GUILDBANK_UPDATE_TEXT = function(_, _, index) if Shown() and index == tab then self:UpdateGuildInfo() end end,
		GUILDBANK_TEXT_CHANGED = function(_, _, index) if Shown() and index == tab and mode == "info" then Call(QueryGuildBankText, tab) end end,
	}
	for event, fn in pairs(handlers) do
		if Valid(event) then self:RegisterEvent(event, fn) end
	end
	-- The game's window stays out of sight each time it opens.
	E:OnBlizzardAddOn("Blizzard_GuildBankUI", function()
		local frame = rawget(_G, "GuildBankFrame")
		if not frame or M.guildHooked then return end
		M.guildHooked = true
		frame:HookScript("OnShow", function()
			if M:OwnGuildBank() then HideBlizzard() end
		end)
	end)
end)

-- The choice changed on the Bags page, or the module was switched off.
hooksecurefunc(M, "ApplyBlizzardBank", function(self)
	if self:OwnGuildBank() then return end
	RestoreBlizzard()
	self:CloseGuildBank()
end)
hooksecurefunc(M, "DisableBlizzard", function(self)
	RestoreBlizzard()
	self:CloseGuildBank()
end)
