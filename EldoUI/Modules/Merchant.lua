-- EldoUI Merchant: vendor conveniences and the Blizzard merchant window.
--
-- Module features (each with its own toggle). Repair and selling junk are
-- off until chosen; every purchase asks first.
--   * Repair: guild funds first, then your own gold. Not enough gold? It
--     repairs as soon as you have it while the vendor is still open.
--   * Sell junk: gray items plus your own "always sell" list, in batches of
--     12, re-checked after each batch; refused items are tried again. Never sold: your
--     "never sell" list, unbound gray gear (option), items you can still
--     get a refund for, items in an equipment set, and (option, on) items
--     one of your quests or recipes needs (E:IsItemProtected); the
--     summary says how many were kept.
--     An optional limit allows one batch per visit, so those sales stay
--     in the buyback tab. The summary says how many are left.
--   * Buy back this visit (option, off): a "Buy back (N)" button
--     restores what you sold since the window opened. One click, out of
--     combat; it never buys anything sold on an earlier visit.
--   * Restock: a list of items with an amount each. Restock buys
--     exactly what is missing up to that amount and never more: when a
--     vendor sells an item in lots bigger than what is missing, it rounds
--     down and says so. Ammo fills the quiver, or tops up to its own amount.
--     A confirm question lists every item with its amount and cost; one
--     click on Buy buys exactly that list.
--   * Vendor buy prices are remembered for the Auction House module's
--     crafting costs (EldoUIDB.vendorBuy).
--
-- The Blizzard merchant window (element "merchant") is only
-- changed when the player ticks "Let EldoUI change this" under Blizzard UI:
--   skin     EldoUI look (needs a reload to undo)
--   move     mover and scale
--   improve  restock / ammo buttons, the item list beside the window (all
--            items of the vendor as rows or a 2-6 column grid, a search
--            that hides or dims, and filters: category, slot, quality,
--            usable, affordable, in stock, not known), Shift-click
--            buys a stack, Alt-click adds an item to the restock list.
--            Filters only change what is shown; buying stays one click,
--            one purchase.
-- Repair and junk selling don't change Blizzard's window, so they follow
-- this module's own switches only.
-- Written from scratch for EldoUI; no code or media from other addons.
local _, E = ...
local L = E.L

local M = E:NewModule("Merchant", {
	title = "Merchant",
	category = "Items & Economy",
	desc = "Repair, sell gray items, restock with exact amounts, fill ammo, and an item list for the merchant window.",
	frames = { "EldoUI_MerchantList" },
	movers = { "EldoUI_MerchantWindow" },
	blizzard = { "merchant" },
	savedKeys = { "profile.modules.Merchant", "EldoUIDB.vendorBuy" },
	optionsPage = "module:Merchant",
	presets = { "BigGrid", "Blizzard", "Compact", "Grid", "Ledger", "Standard", "Wide" },
	defaults = {
		autoRepair = "off",     -- off, personal, guild (guild funds, then your own); acts for the player, so off until chosen
		waitForGold = true,
		sellJunk = false,       -- acts for the player: off until chosen
		keepJunkBuyback = false, -- limit junk sales to the buyback tab's 12 stacks
		sellList = "",          -- item IDs, names or links always sold, any quality
		markJunk = "ctrlalt",   -- two-modifier right click, or off
		junkButton = true,
		keepGreyGear = false,   -- keep gray weapons and armor that aren't bound
		keepList = "",          -- item IDs or names never sold
		protectItems = true,    -- never sell what a quest or recipe of yours needs
		buybackButton = false,  -- "Buy back (N)": acts for you on a click, so off until chosen
		summary = true,
		buyStacks = true,
		restock = {},           -- { { id = itemID, name = "Arcane Powder", amount = 20 }, ... }
		restockList = "",       -- v0.5.0 free text, migrated once into `restock`
		restockButton = true,
		autoRestock = false,
		altClickAdd = true,
		ammoButton = true,
		autoAmmo = false,
		ammoAmount = 1000,      -- without a quiver or pouch
		confirm = true,
		recordPrices = true,
		knownTint = true,       -- tint recipes, mounts, pets and toys you already have
		-- Item list beside the window
		list = true,
		listLayout = "rows",    -- rows (a list, 1-2 columns) or grid (tiles, 2-6 columns x rows)
		listColumns = 1,
		listWidth = 300,
		listRowHeight = 22,
		listFontSize = 12,
		listZebra = true,
		listMoney = "general",  -- general (Fonts and text > Money) / icons / letters / short
		gridColumns = 4,
		gridRows = 6,
		gridCellWidth = 150,
		gridIconSize = 32,
		-- Search and filters
		searchMode = "hide",    -- hide or dim: items that don't match the search or the filters
		filterBar = true,
		rememberFilters = false,
		filterState = {},       -- the last filters, kept between vendors when rememberFilters is on
		filterQuality = 0,      -- what every vendor starts with when filters aren't remembered
		filterUsable = false,
		filterAfford = false,
		filterStock = false,
		filterKnown = false,
		-- Window (element "Move and scale")
	},
})

-- "Reset to defaults" keeps the player's own data and window places
-- (E:ResetModuleSettings, Core/Config.lua).
M.keepOnReset = { "restock" }
M.keepOnResetNote = E.Key("Your restock list is kept too.")

local BATCH = 12 -- the buyback tab holds the last 12 sold stacks
local MAX_PASSES = 8
local floor, max, min = math.floor, math.max, math.min

local function Money(copper)
	copper = floor((copper or 0) + 0.5)
	return E:FormatMoney(copper, M.db and M.db.listMoney)
end

local function MerchantOpen()
	return MerchantFrame and MerchantFrame:IsShown()
end

local function Allowed(action)
	return M.active and E:BlizzardAllowed("merchant", action)
end

-- The game's gamepad interface walks the window's buttons with its
-- controller cursor, so EldoUI's own buttons (the list beside the window,
-- Restock, Ammo and Buy back) step aside while it is on and come back
-- with the mouse interface. The look stays.
local function Additions()
	return not E:GamepadUIActive()
end

-- "a = 1, b = 2" or "a, b" -> list of { key = id or lower-case name, amount }.
local function ParseList(text)
	local list = {}
	for entry in (text or ""):gmatch("[^,;\n]+") do
		local key, amount = entry:match("^%s*(.-)%s*=%s*(%d+)%s*$")
		if not key then key = strtrim(entry) end
		local linked = key:match("item:(%d+)")
		if linked then key = linked end
		if key ~= "" then
			list[#list + 1] = { key = tonumber(key) or key:lower(), amount = tonumber(amount) }
		end
	end
	return list
end

local function InList(list, id, name)
	for _, entry in ipairs(list) do
		if entry.key == id or (name and entry.key == name:lower()) then return entry end
	end
end

---------------------------------------------------------------------------
-- Repair
---------------------------------------------------------------------------
-- Another addon that repairs and sells junk: those two parts stand back
-- while it runs (Data/Competitors.lua); the rest stays on.
-- The note on an option row whose job another addon does.
local function HandledBy(feature)
	return function()
		local standing, _, title = E:StandsBack(M, feature)
		return standing and L["Handled by %s. Type %s to choose."]:format(title, E:Highlight("/eui addons")) or nil
	end
end

function M:Repair()
	if self.db.autoRepair == "off" or E:StandsBack(self, "repair") or not CanMerchantRepair() then return end
	local cost, canRepair = GetRepairAllCost()
	if not canRepair or cost == 0 then
		self.repairPending = nil
		return
	end
	if self.db.autoRepair == "guild" and IsInGuild() and CanGuildBankRepair and CanGuildBankRepair() then
		local limit = GetGuildBankWithdrawMoney and GetGuildBankWithdrawMoney() or 0
		if limit == -1 or limit >= cost then
			RepairAllItems(true)
			self.repairPending = nil
			if self.db.summary then self:Print(L["Repaired for %s (guild bank)."]:format(E:EconomyMoney(cost))) end
			return
		end
	end
	if GetMoney() >= cost then
		RepairAllItems()
		self.repairPending = nil
		if self.db.summary then self:Print(L["Repaired for %s."]:format(E:EconomyMoney(cost))) end
	elseif not self.repairPending then
		self.repairPending = self.db.waitForGold
		self:Print((self.db.waitForGold and L["Not enough gold to repair (%s). It happens as soon as you have it."]
			or L["Not enough gold to repair (%s)."]):format(E:EconomyMoney(cost)))
	end
end

---------------------------------------------------------------------------
-- Sell gray items
---------------------------------------------------------------------------
local function KeepGreyGear(bag, slot, info)
	if not M.db.keepGreyGear then return false end
	local classID = select(6, C_Item.GetItemInfoInstant(info.hyperlink))
	if classID ~= Enum.ItemClass.Weapon and classID ~= Enum.ItemClass.Armor then return false end
	local bound = info.isBound
	if C_Item.IsBound and ItemLocation then
		local ok, result = pcall(C_Item.IsBound, ItemLocation:CreateFromBagAndSlot(bag, slot))
		if ok then bound = result end
	end
	return not bound
end

-- Items you could still return for a refund are never sold.
local function HasRefund(bag, slot)
	local getInfo = C_Container.GetContainerItemPurchaseInfo
	if not getInfo then return false end
	local ok, info = pcall(getInfo, bag, slot, false)
	if not ok or E.Secret(info) then return true end
	if type(info) ~= "table" then return false end
	if canaccesstable and not canaccesstable(info) then return true end
	local seconds = info.refundSeconds
	if E.Secret(seconds) then return true end
	return type(seconds) == "number" and seconds > 0
end

-- Items saved in an equipment set are never sold.
local function InEquipmentSet(bag, slot)
	local getInfo = C_Container.GetContainerItemEquipmentSetInfo
	if not getInfo then return false end
	local ok, inSet = pcall(getInfo, bag, slot)
	return not ok or E.Secret(inSet) or inSet == true
end

-- Items one of your quests or recipes needs (Core/ItemProtect.lua).
local function Protected(itemID, bag, slot)
	return M.db.protectItems and E.IsItemProtected and E:IsItemProtected(itemID, bag, slot) or false
end

-- Is the item on the "never sell" list? Bags' "Move these" asks too.
function M:NeverSell(itemID, name)
	return InList(ParseList(self.db.keepList), itemID, name) ~= nil
end

local keepText, sellText, keepRules, sellRules
local function JunkRules()
	if not keepRules or keepText ~= M.db.keepList then
		keepText, keepRules = M.db.keepList, ParseList(M.db.keepList)
	end
	if not sellRules or sellText ~= M.db.sellList then
		sellText, sellRules = M.db.sellList, ParseList(M.db.sellList)
	end
	return keepRules, sellRules
end

-- One rule for the sale queue and the junk marks in both bag windows.
local function JunkItem(bag, slot, info, keep, always)
	if E.Secret(info) or type(info) ~= "table" or (canaccesstable and not canaccesstable(info)) then return false end
	local link, id, quality = E.Plain(info.hyperlink), E.Plain(info.itemID), E.Plain(info.quality)
	local count = E.Plain(info.stackCount)
	if type(link) ~= "string" or type(id) ~= "number" or type(quality) ~= "number"
		or type(count) ~= "number" or count < 1 or count % 1 ~= 0
		or E.Secret(info.hasNoValue) or info.hasNoValue or E.Secret(info.isLocked) or info.isLocked then return false end
	local name, _, _, _, _, _, _, _, _, _, price = E.PlainCallEach(C_Item.GetItemInfo, link)
	local grey = quality == Enum.ItemQuality.Poor
	local listed = not grey and #always > 0 and InList(always, id, name)
	if not (grey or listed) or type(price) ~= "number" or price <= 0 or InList(keep, id, name)
		or (grey and KeepGreyGear(bag, slot, info))
		or HasRefund(bag, slot) or InEquipmentSet(bag, slot) then return false end
	if Protected(id, bag, slot) then return false, true end
	return true, false, price
end

-- A missing result lets bag windows use their gray-only marks while this
-- module is off. The visit limit does not change which items are junk.
function E:WillSellAsJunk(bag, slot, info)
	if not M.active then return nil end
	if E.Secret(bag) or type(bag) ~= "number" then return false end
	if bag < 0 or bag > (NUM_BAG_SLOTS or 4) then
		local bags = self.modules.Bags
		if not (bags and bags.active and bags:BankIsOpen()) then return false end
	end
	local keep, always = JunkRules()
	info = info or self.BagCache:Info(bag, slot)
	local eligible = JunkItem(bag, slot, info, keep, always)
	if eligible and not M.db.sellJunk and self:IsItemProtected(info.itemID, bag, slot) then return false end
	return eligible
end

-- The slots to sell, and how many junk slots were kept for a quest or recipe.
local function JunkSlots(manual)
	local keep, always = JunkRules()
	local list, kept = {}, 0
	local bags = E.BagCache
	local profile = M.db
	for _, bag in ipairs(bags:BagIDs()) do
		for slot = 1, bags:NumSlots(bag) do
			local info = bags:Info(bag, slot)
			local eligible, protected, price = JunkItem(bag, slot, info, keep, always)
			if eligible and manual and E:IsItemProtected(info.itemID, bag, slot) then eligible, protected = false, true end
			if protected then
				kept = kept + 1
			elseif eligible then
				local count = E.Plain(info.stackCount)
				if type(count) == "number" and count >= 1 and count % 1 == 0 then
					list[#list + 1] = { bag = bag, slot = slot, link = E.Plain(info.hyperlink), value = price * count }
				end
			end
		end
	end
	if M.db ~= profile or not M.active then return {}, 0 end
	return list, kept
end
M.JunkSlots = JunkSlots

-- One batch, then a re-check: items still in place were refused and are
-- tried again in the next pass.
function M:SellJunk(pass, visit, manual)
	pass = pass or 1
	visit = visit or self.visit
	if not self.active or self.visit ~= visit then return end
	if pass == 1 and (self.junkSelling or (self.junkBuybackLimited and not manual)) then return end
	if pass == 1 then
		self.junkTotal, self.junkCount, self.attempted = 0, 0, {}
		self.junkKept = nil
		if manual then self.junkBuybackLimited = nil end
	end
	-- Count what the last batch really sold.
	local profile = self.db
	local total, count, previous = self.junkTotal, self.junkCount, self.attempted
	for _, item in ipairs(previous) do
		local ok, info = pcall(C_Container.GetContainerItemInfo, item.bag, item.slot)
		local readable = ok and not E.Secret(info) and (info == nil
			or (type(info) == "table" and (not canaccesstable or canaccesstable(info))
				and not E.Secret(info.hyperlink) and type(info.hyperlink) == "string"))
		if readable and not (info and info.hyperlink == item.link) then
			total = total + item.value
			count = count + 1
		end
	end
	if not self.active or self.visit ~= visit or self.db ~= profile then return end
	self.junkTotal, self.junkCount = total, count
	self.attempted = {}
	local list, kept = JunkSlots(manual)
	if not self.active or self.visit ~= visit or self.db ~= profile then return end
	if pass > 1 and self.db.keepJunkBuyback then self.junkBuybackLimited = true end
	local limited = self.junkBuybackLimited
	if #list == 0 or limited or pass > MAX_PASSES or not MerchantOpen() or (pass > 1 and (manual or not self.db.sellJunk)) then
		if self.db.summary and self.junkTotal > 0 then
			self:Print((self.junkCount == 1 and L["Sold %d junk item and earned %s."] or L["Sold %d junk items and earned %s."]):format(self.junkCount, E:EconomyMoney(self.junkTotal)))
		end
		if self.db.summary and kept > 0 then
			self:Print(E:Plural(kept, "Kept %d item your quests or recipes need.", "Kept %d items your quests or recipes need."):format(kept))
		end
		if self.db.summary and limited and #list > 0 then
			self:Print(E:Plural(#list, "%d junk item is left in your bags.", "%d junk items are left in your bags."):format(#list))
		end
		self.junkKept = kept
		self.junkSelling = nil
		self:UpdateButtons()
		return
	end
	-- One submitted batch fits in buyback, even if a delayed bag read cannot
	-- tell a refused stack from an identical item now occupying its slot.
	self.junkBuybackLimited = self.db.keepJunkBuyback
	self.junkSelling = true
	local attempted = self.attempted
	for index = 1, min(BATCH, #list) do
		if not self.active or self.visit ~= visit or not MerchantOpen() then break end
		local item = list[index]
		local info = E.PlainCall(C_Container.GetContainerItemInfo, item.bag, item.slot)
		if type(info) == "table" and (not canaccesstable or canaccesstable(info)) and E.Plain(info.hyperlink) == item.link
			and JunkItem(item.bag, item.slot, info, JunkRules())
			and (not manual or (not E:IsItemProtected(info.itemID, item.bag, item.slot)
				and Allowed("improve") and Additions() and E.PlainCall(InCombatLockdown) == false)) then
			if not self.active or self.visit ~= visit or self.db ~= profile or not MerchantOpen() then return end
			local current = E.PlainCall(C_Container.GetContainerItemInfo, item.bag, item.slot)
			if type(current) ~= "table" or (canaccesstable and not canaccesstable(current))
				or E.Plain(current.hyperlink) ~= item.link or E.Plain(current.itemID) ~= E.Plain(info.itemID)
				or E.Plain(current.quality) ~= E.Plain(info.quality) or E.Plain(current.stackCount) ~= E.Plain(info.stackCount)
				or E.Secret(current.isLocked) or current.isLocked
				or E.Secret(current.hasNoValue) or current.hasNoValue then break end
			if manual and (not self.db.junkButton or not Allowed("improve") or not Additions()
				or E.PlainCall(InCombatLockdown) ~= false or E:StandsBack(self, "selljunk")) then break end
			if not self.active or self.visit ~= visit or self.db ~= profile or not MerchantOpen() then return end
			local used = pcall(C_Container.UseContainerItem, item.bag, item.slot)
			if self.visit ~= visit or not self.active or not MerchantOpen() then return end
			if used then
				attempted[#attempted + 1] = item
			end
		end
	end
	C_Timer.After(0.6, function()
		if self.active and self.visit == visit and MerchantOpen() then self:SellJunk(pass + 1, visit, manual) end
	end)
end

local function RefreshJunkMarks()
	local bags = E.modules.Bags
	if not (bags and bags.active) then return end
	bags:RefreshViews()
	if bags.RepaintBlizzardBags then bags:RepaintBlizzardBags() end
end

local JUNK_MODIFIERS = {
	ctrlalt = { label = "Ctrl+Alt" },
	ctrlshift = { label = "Ctrl+Shift" },
	altshift = { label = "Alt+Shift" },
}

function M:IsJunkMarkClick(mouse)
	if not self.active or mouse ~= "RightButton" or not JUNK_MODIFIERS[self.db.markJunk] then return false end
	local alt, ctrl, shift = IsAltKeyDown(), IsControlKeyDown(), IsShiftKeyDown()
	if self.db.markJunk == "ctrlalt" then return ctrl and alt and not shift end
	if self.db.markJunk == "ctrlshift" then return ctrl and shift and not alt end
	return alt and shift and not ctrl
end

-- The marking click runs after the slot's own click handler, which stays
-- in place: replacing that handler would stop a right-click from using the
-- item. The marking gesture always holds two modifier keys, so the slot
-- treats it as a modified click and does not use the item.
function M:WatchJunkSlot(button, bag)
	button:HookScript("OnClick", function(own, mouse, down)
		if not down and M:IsJunkMarkClick(mouse) then M:ToggleJunk(bag, own:GetID()) end
	end)
end

local function EditJunkList(text, id, name, add)
	local out = {}
	for entry in (text or ""):gmatch("[^,;\n]+") do
		local parsed = ParseList(entry)[1]
		if not (parsed and (parsed.key == id or (name and parsed.key == name:lower()))) then
			out[#out + 1] = strtrim(entry)
		end
	end
	if add then out[#out + 1] = tostring(id) end
	return table.concat(out, ", ")
end

function M:ToggleJunk(bag, slot)
	local profile = self.db
	if not self.active or E.PlainCall(InCombatLockdown) ~= false
		or E.Secret(bag) or E.Secret(slot) or type(bag) ~= "number" or type(slot) ~= "number" then return false end
	local info = E.PlainCall(C_Container.GetContainerItemInfo, bag, slot)
	if type(info) ~= "table" or (canaccesstable and not canaccesstable(info)) then return false end
	local id, link = E.Plain(info.itemID), E.Plain(info.hyperlink)
	local quality = E.Plain(info.quality)
	if type(id) ~= "number" or type(link) ~= "string" or type(quality) ~= "number" or E.Secret(info.isLocked) or info.isLocked
		or HasRefund(bag, slot) or InEquipmentSet(bag, slot)
		or (E.IsItemProtected and E:IsItemProtected(id, bag, slot)) then return false end
	local name, _, _, _, _, _, _, _, _, _, price = E.PlainCallEach(C_Item.GetItemInfo, link)
	if type(name) ~= "string" or type(price) ~= "number" or price <= 0
		or E.Secret(info.hasNoValue) or info.hasNoValue then return false end
	local latest = E.PlainCall(C_Container.GetContainerItemInfo, bag, slot)
	if type(latest) ~= "table" or (canaccesstable and not canaccesstable(latest))
		or E.Plain(latest.itemID) ~= id or E.Plain(latest.hyperlink) ~= link then return false end
	if self.db ~= profile or not self.active then return false end
	local key = quality == Enum.ItemQuality.Poor and "keepList" or "sellList"
	local other = key == "keepList" and "sellList" or "keepList"
	local present = InList(ParseList(self.db[key]), id, name) ~= nil
	self.db[key] = EditJunkList(self.db[key], id, name, not present)
	self.db[other] = EditJunkList(self.db[other], id, name, false)
	RefreshJunkMarks()
	if E.RefreshTooltipSections then E:RefreshTooltipSections() end
	self:UpdateButtons()
	return true
end

local function RegisterJunkTooltip()
	if not E.RegisterTooltipSection then return end
	E:RegisterTooltipSection("junkMark", {
		order = 34, title = "Junk mark", module = "Merchant", default = "always",
		desc = "Shows whether an item is on your Always sell or Never sell list, with the marking shortcut.",
		item = function(_, link, id, add)
			id = E.Plain(id)
			if type(id) ~= "number" then return end
			local name = E.PlainCall(C_Item.GetItemInfo, link or id)
			if type(name) ~= "string" then return end
			local keep, always = JunkRules()
			local label = InList(keep, id, name) and L["Never sell"] or (InList(always, id, name) and L["Marked as junk"])
			if not label then return end
			local modifier = JUNK_MODIFIERS[M.db.markJunk]
			add(label, modifier and L["%s-right-click to unmark"]:format(modifier.label) or nil)
		end,
	})
end
local junkTooltipOwner = {}
E:RegisterEvent("PLAYER_LOGIN", function()
	RegisterJunkTooltip()
	E:UnregisterEvent("PLAYER_LOGIN", junkTooltipOwner)
end, junkTooltipOwner, "modules")

---------------------------------------------------------------------------
-- Restock list: { id, name, amount } per item
---------------------------------------------------------------------------
local function ResolveItem(text)
	if type(text) == "number" then
		return text, C_Item.GetItemInfo(text)
	end
	text = strtrim(tostring(text or ""))
	if text == "" then return end
	local linked = tonumber(text:match("item:(%d+)"))
	local id = linked or tonumber(text)
	if id then return id, C_Item.GetItemInfo(id) end
	local instant = C_Item.GetItemInfoInstant and C_Item.GetItemInfoInstant(text)
	if type(instant) == "number" then return instant, C_Item.GetItemInfo(instant) or text end
	return nil, text
end

function M:RestockEntries()
	return self.db.restock
end

local function FindEntry(id, name)
	for index, entry in ipairs(M.db.restock) do
		if (id and entry.id == id) or (not entry.id and name and entry.name and entry.name:lower() == name:lower()) then
			return entry, index
		end
	end
end

-- Adds an item (ID, name or link) or changes its amount when it is listed.
function M:AddRestock(item, amount)
	local id, name = ResolveItem(item)
	if not id and not name then return end
	amount = max(0, floor(tonumber(amount) or 0))
	local entry = FindEntry(id, name)
	if entry then
		entry.amount = amount > 0 and amount or entry.amount
		entry.name = name or entry.name
	else
		entry = { id = id, name = name, amount = amount > 0 and amount or 20 }
		table.insert(self.db.restock, entry)
	end
	self:RestockChanged()
	return entry
end

function M:RemoveRestock(index)
	table.remove(self.db.restock, index)
	self:RestockChanged()
end

function M:RestockChanged()
	if self.editor and self.editor:IsShown() then self:UpdateEditor() end
	self:UpdateButtons()
	if E.RefreshConfig then E:RefreshConfig() end
end

-- v0.5.0 kept the list as one string ("Arcane Powder = 20, 5140 = 20").
-- It is read once into the per-item list and then cleared.
function M:MigrateRestockString()
	local text = self.db.restockList
	if type(text) ~= "string" or text == "" then return end
	for _, parsed in ipairs(ParseList(text)) do
		if parsed.amount and parsed.amount > 0 then
			local id = type(parsed.key) == "number" and parsed.key or nil
			local name = type(parsed.key) == "string" and parsed.key or nil
			if not FindEntry(id, name) then
				local resolved, itemName = ResolveItem(parsed.key)
				table.insert(self.db.restock, { id = resolved or id, name = itemName or name, amount = parsed.amount })
			end
		end
	end
	self.db.restockList = ""
end

---------------------------------------------------------------------------
-- Plans: what a click on Buy would buy, item by item
--   plan = { items = { { index, itemID, name, quantity, cost } },
--            skipped = { "Arcane Powder: sold in lots of 5, 3 missing, not bought" } }
---------------------------------------------------------------------------
local function MerchantItem(index)
	local info = C_MerchantFrame and C_MerchantFrame.GetItemInfo and C_MerchantFrame.GetItemInfo(index)
	if info then
		return info.name, info.price, max(info.stackCount or 1, 1), info.numAvailable, info.hasExtendedCost, info
	end
	local legacy = rawget(_G, "GetMerchantItemInfo")
	if type(legacy) ~= "function" then return end
	local name, _, price, perBuy, available, _, _, extended = legacy(index)
	return name, price, max(perBuy or 1, 1), available, extended
end

local function NewPlan() return { items = {}, skipped = {} } end

-- Adds what is missing (`wanted` items) to the plan in whole vendor lots,
-- rounded DOWN: never more than `wanted`.
local function AddToPlan(plan, index, wanted)
	local name, price, perBuy, available, extended = MerchantItem(index)
	if not name or not price or wanted <= 0 then return end
	if extended then
		plan.skipped[#plan.skipped + 1] = L["%s: costs more than gold, buy it by hand"]:format(name)
		return
	end
	local lots = floor(wanted / perBuy)
	if available and available >= 0 then lots = min(lots, floor(available)) end
	if lots <= 0 then
		if perBuy > wanted then
			plan.skipped[#plan.skipped + 1] = L["%s: sold in lots of %d, %d missing, not bought"]:format(name, perBuy, wanted)
		else
			plan.skipped[#plan.skipped + 1] = L["%s: sold out"]:format(name)
		end
		return
	end
	local quantity = lots * perBuy
	if quantity < wanted and perBuy > 1 then
		plan.skipped[#plan.skipped + 1] = L["%s: sold in lots of %d, buys %d of %d missing"]:format(name, perBuy, quantity, wanted)
	end
	plan.items[#plan.items + 1] = { index = index, itemID = GetMerchantItemID(index), name = name, quantity = quantity, perBuy = perBuy, cost = lots * price }
end

function M:RestockPlan()
	local plan = NewPlan()
	if #self.db.restock == 0 then return plan end
	for index = 1, GetMerchantNumItems() do
		local id = GetMerchantItemID(index)
		local name = MerchantItem(index)
		local entry = id and FindEntry(id, name)
		if entry and (entry.amount or 0) > 0 then
			if not entry.id then entry.id = id end
			AddToPlan(plan, index, entry.amount - C_Item.GetItemCount(id, false))
		end
	end
	return plan
end

local function AmmoID()
	if not INVSLOT_AMMO then return end
	local _, class = UnitClass("player")
	if class ~= "HUNTER" then return end
	return GetInventoryItemID("player", INVSLOT_AMMO)
end

-- Fill every quiver or ammo pouch slot; without one, top up to the amount
-- set in the options. Rounded down like every restock.
function M:AmmoPlan()
	local plan = NewPlan()
	local ammo = AmmoID()
	if not ammo then return plan end
	local index
	for i = 1, GetMerchantNumItems() do
		if GetMerchantItemID(i) == ammo then index = i break end
	end
	if not index then return plan end
	local stack = select(8, C_Item.GetItemInfo(ammo)) or 200
	local room, hasAmmoBag = 0, false
	for bag = 1, NUM_BAG_SLOTS do
		local _, family = C_Container.GetContainerNumFreeSlots(bag)
		if family and bit.band(family, 3) ~= 0 then
			hasAmmoBag = true
			for slot = 1, C_Container.GetContainerNumSlots(bag) do
				local info = C_Container.GetContainerItemInfo(bag, slot)
				if not info then
					room = room + stack
				elseif info.itemID == ammo then
					room = room + max(stack - (info.stackCount or 0), 0)
				end
			end
		end
	end
	if not hasAmmoBag then room = self.db.ammoAmount - C_Item.GetItemCount(ammo, false) end
	AddToPlan(plan, index, room)
	return plan
end

local function PlanCost(plan)
	local cost = 0
	for _, entry in ipairs(plan.items) do cost = cost + entry.cost end
	return cost
end

local function MergePlans(a, b)
	for _, entry in ipairs(b.items) do a.items[#a.items + 1] = entry end
	for _, line in ipairs(b.skipped) do a.skipped[#a.skipped + 1] = line end
	return a
end

function M:PlanText(plan, separator)
	local parts = {}
	for _, entry in ipairs(plan.items) do
		parts[#parts + 1] = ("%d x %s  %s"):format(entry.quantity, entry.name, E:EconomyMoney(entry.cost))
	end
	return table.concat(parts, separator or "\n")
end

local function SkippedText(plan)
	if #plan.skipped == 0 then return "" end
	return "\n\n" .. E:TextHex("warn") .. table.concat(plan.skipped, "\n") .. "|r"
end

-- Buys exactly the listed amounts: one purchase per vendor stack, each a
-- whole number of vendor lots.
function M:BuyPlan(plan)
	if not MerchantOpen() then return end
	if GetMoney() < PlanCost(plan) then
		self:Print(L["Not enough gold for that."])
		return
	end
	local bought = NewPlan()
	for _, entry in ipairs(plan.items) do
		-- The vendor's list may have changed since the question.
		if GetMerchantItemID(entry.index) == entry.itemID then
			local perBuy = max(entry.perBuy or 1, 1)
			local maxStack = max(GetMerchantItemMaxStack(entry.index) or perBuy, perBuy)
			local chunk = max(perBuy, floor(maxStack / perBuy) * perBuy)
			local left = entry.quantity
			while left > 0 do
				local amount = min(left, chunk)
				BuyMerchantItem(entry.index, amount)
				left = left - amount
			end
			bought.items[#bought.items + 1] = entry
		end
	end
	if self.db.summary and #bought.items > 0 then
		self:Print(L["Bought %s for %s."]:format(self:PlanText(bought, ", "), E:EconomyMoney(PlanCost(bought))))
	end
	C_Timer.After(0.5, function() M:UpdateButtons() end)
end

-- Asks first unless the player switched the question off. Automatic offers
-- (on vendor open) always ask.
function M:Offer(plan, automatic)
	if #plan.items == 0 then
		if #plan.skipped > 0 and not automatic then self:Print(table.concat(plan.skipped, "; ")) end
		return
	end
	if not self.db.confirm and not automatic then return self:BuyPlan(plan) end
	local details = L["%s\n\nTotal: %s%s"]:format(self:PlanText(plan), E:EconomyMoney(PlanCost(plan)), SkippedText(plan))
	-- A question this one replaces clears only its own pending purchase.
	E:ShowConfirm({ key = "ELDOUI_MERCHANT_RESTOCK", title = L["Merchant"], text = L["Buy exactly these items?\n\n%s"]:format(details),
		accept = E:GameText(PURCHASE, L["Buy"]), data = plan,
		onAccept = function(own)
			if M.pendingPlan == own then M:BuyPlan(own) end
			M.pendingPlan = nil
		end,
		onCancel = function(own) if M.pendingPlan == own then M.pendingPlan = nil end end })
	self.pendingPlan = plan
end

---------------------------------------------------------------------------
-- Single purchases from the item list: one click, one purchase. Items that
-- cost more than gold, or a lot of gold, ask first like Blizzard's window.
---------------------------------------------------------------------------
local function CostText(index, lots)
	local parts = {}
	local _, price = MerchantItem(index)
	if price and price > 0 then parts[#parts + 1] = E:EconomyMoney(price * lots) end
	local count = GetMerchantItemCostInfo and GetMerchantItemCostInfo(index) or 0
	for i = 1, count do
		local texture, value = GetMerchantItemCostItem(index, i)
		if texture and value then parts[#parts + 1] = ("%d |T%s:0|t"):format(value * lots, texture) end
	end
	return table.concat(parts, "  ")
end

local function Purchase(index, itemID, quantity)
	if not MerchantOpen() or GetMerchantItemID(index) ~= itemID then return end
	local _, _, perBuy = MerchantItem(index)
	if not perBuy then return end
	local maxStack = max(GetMerchantItemMaxStack(index) or perBuy, perBuy)
	local chunk = max(perBuy, floor(maxStack / perBuy) * perBuy)
	local left = quantity
	while left > 0 do
		local amount = min(left, chunk)
		BuyMerchantItem(index, amount)
		left = left - amount
	end
end

function M:ConfirmPurchase(index, quantity)
	local name, price, perBuy, _, extended = MerchantItem(index)
	if not name then return end
	quantity = max(perBuy, floor(quantity / perBuy) * perBuy)
	local lots = quantity / perBuy
	local high = MERCHANT_HIGH_PRICE_COST or 1500000
	local itemID = GetMerchantItemID(index)
	if not extended and (price or 0) * lots < high then
		return Purchase(index, itemID, quantity)
	end
	local pending = { index = index, itemID = itemID, quantity = quantity }
	E:ShowConfirm({ key = "ELDOUI_MERCHANT_BUY", title = L["Merchant"],
		text = L["Buy %s for %s?"]:format(("%d x %s"):format(quantity, name), CostText(index, lots)),
		accept = E:GameText(PURCHASE, L["Buy"]), data = pending,
		onAccept = function(own)
			local p = M.pendingPurchase == own and own or nil
			M.pendingPurchase = nil
			if p then Purchase(p.index, p.itemID, p.quantity) end
		end,
		onCancel = function(own) if M.pendingPurchase == own then M.pendingPurchase = nil end end })
	self.pendingPurchase = pending
end

function M:AskQuantity(index)
	local name, _, perBuy = MerchantItem(index)
	if not name then return end
	local maxStack = max(GetMerchantItemMaxStack(index) or perBuy, perBuy)
	local pending = { index = index, default = maxStack }
	E:ShowConfirm({ key = "ELDOUI_MERCHANT_QUANTITY", title = L["Merchant"], text = L["How many %s? (sold in lots of %d)"]:format(name, perBuy),
		accept = E:GameText(OKAY, L["OK"]), edit = { text = tostring(maxStack), numeric = true, maxLetters = 5 }, data = pending,
		onAccept = function(own, typed)
			local p = M.pendingQuantity == own and own or nil
			M.pendingQuantity = nil
			local amount = tonumber(typed)
			if p and amount and amount > 0 then M:ConfirmPurchase(p.index, amount) end
		end,
		onCancel = function(own) if M.pendingQuantity == own then M.pendingQuantity = nil end end })
	self.pendingQuantity = pending
end

---------------------------------------------------------------------------
-- Vendor buy prices for crafting costs (Auction House module)
-- Saved data: EldoUIDB.vendorBuy[itemID] = copper for one item, written
-- while a vendor is open; the Auction House and the Profession Planner
-- read it.
---------------------------------------------------------------------------
E:RegisterStore("vendorBuy", { owner = "Merchant", key = "item", shape = "vendor price in copper for one of each item" })

-- What a vendor asked for one of an item (copper), or nil.
function M:VendorPrice(itemID)
	local saved = type(EldoUIDB) == "table" and EldoUIDB.vendorBuy
	itemID = tonumber(itemID)
	return itemID and type(saved) == "table" and tonumber(saved[itemID]) or nil
end

function M:RecordPrices()
	if not self.db.recordPrices or not MerchantOpen() then return end
	EldoUIDB.vendorBuy = EldoUIDB.vendorBuy or {}
	local store = EldoUIDB.vendorBuy
	for index = 1, GetMerchantNumItems() do
		local _, price, perBuy, available, extended = MerchantItem(index)
		local id = GetMerchantItemID(index)
		-- Limited-stock items are skipped: their price says little about a reagent's cost.
		if id and price and price > 0 and not extended and (available or -1) < 0 then
			store[id] = floor(price / perBuy + 0.5)
		end
	end
end

---------------------------------------------------------------------------
-- Look helpers for EldoUI's own frames here
---------------------------------------------------------------------------
local function Accent()
	local c = E.media.accentColor
	return c[1], c[2], c[3]
end

-- The window's parts are the shared kit's (E.UIKit): flat buttons with the
-- hover and press look, inputs with a hint, the cross glyph.
local function FlatButton(parent, label, width, height)
	return E.UIKit.Button(parent, label, { width = width, height = height or E.tokens.height.button })
end

local function FlatInput(parent, width, numeric, hint)
	return E.UIKit.Input(parent, { width = width, height = 20, numeric = numeric, hint = hint })
end

-- Remove a row (danger hover); clear filters is a plain cross.
local function CloseGlyph(parent, plain)
	if plain then return E.UIKit.IconButton(parent, 16, "cross") end
	return E.UIKit.RemoveButton(parent, nil, nil, nil, 16)
end

local function CursorItem()
	local kind, id, link = GetCursorInfo()
	if kind == "item" then return id, link end
	if kind == "merchant" and id then return GetMerchantItemID(id), GetMerchantItemLink(id) end
end

---------------------------------------------------------------------------
-- Restock list editor: item, amount field, remove button per row. Items
-- can be typed (name, ID or link), dragged in, or Alt-clicked at a vendor.
---------------------------------------------------------------------------
local EDITOR_ROWS = 12

function M:CreateEditor()
	-- The shared tool window shell (E.UIKit.CreateToolWindow).
	local frame = E.UIKit.CreateToolWindow("EldoUI_RestockEditor", { title = L["Restock list"], width = 380,
		height = 120 + EDITOR_ROWS * 24, strata = "DIALOG", point = { "CENTER", UIParent, "CENTER", 0, 60 } })
	frame.line = frame.headerLine

	-- Add row
	local add = FlatInput(frame, 200, false, L["Item name, ID or link, or drop an item"])
	add:SetPoint("TOPLEFT", 10, -38)
	local amount = FlatInput(frame, 56, true)
	amount:SetPoint("LEFT", add, "RIGHT", 6, 0)
	amount:SetMaxLetters(5)
	amount:SetText("20")
	local addButton = FlatButton(frame, L["Add"], 90, 20)
	addButton:SetPoint("LEFT", amount, "RIGHT", 6, 0)
	local function DoAdd()
		local text = add:GetText()
		if strtrim(text or "") == "" then return end
		if M:AddRestock(text, tonumber(amount:GetText())) then
			add:SetText("")
			add:ClearFocus()
		end
	end
	addButton:SetScript("OnClick", DoAdd)
	add:SetScript("OnEnterPressed", DoAdd)
	amount:SetScript("OnEnterPressed", DoAdd)
	local function TakeCursor()
		local id = CursorItem()
		if id then
			ClearCursor()
			M:AddRestock(id, tonumber(amount:GetText()))
		end
	end
	add:SetScript("OnReceiveDrag", TakeCursor)
	add:HookScript("OnMouseDown", function() if CursorItem() then TakeCursor() end end)

	-- Column titles
	local h1 = E.UIKit.Text(frame, E.tokens.size.small, "LEFT", "secondary")
	h1:SetPoint("TOPLEFT", 36, -66)
	h1:SetText(L["Item"])
	local h2 = E.UIKit.Text(frame, E.tokens.size.small, "RIGHT", "secondary")
	h2:SetPoint("TOPRIGHT", -36, -66)
	h2:SetText(L["Keep        In bags"])

	-- Rows
	frame.rows = {}
	frame.offset = 0
	local area = CreateFrame("Frame", nil, frame)
	area:SetPoint("TOPLEFT", 8, -80)
	area:SetPoint("TOPRIGHT", -8, -80)
	area:SetHeight(EDITOR_ROWS * 24)
	area:EnableMouse(true)
	area:EnableMouseWheel(true)
	area:SetScript("OnMouseWheel", function(_, delta)
		frame.offset = max(0, min(frame.offset - delta, max(0, #M.db.restock - EDITOR_ROWS)))
		M:UpdateEditor()
	end)
	area:SetScript("OnReceiveDrag", TakeCursor)
	area:SetScript("OnMouseUp", function() if CursorItem() then TakeCursor() end end)
	for i = 1, EDITOR_ROWS do
		local row = CreateFrame("Frame", nil, area)
		row:SetHeight(22)
		row:SetPoint("TOPLEFT", 0, -(i - 1) * 24)
		row:SetPoint("TOPRIGHT", 0, -(i - 1) * 24)
		row.stripe = row:CreateTexture(nil, "BACKGROUND")
		row.stripe:SetAllPoints()
		row.stripe:SetColorTexture(1, 1, 1, i % 2 == 0 and E.tokens.hover.row / 2 or 0)
		row.icon = row:CreateTexture(nil, "ARTWORK")
		row.icon:SetSize(20, 20)
		row.icon:SetPoint("LEFT", 4, 0)
		E:TrimIcon(row.icon)
		row.name = E.UIKit.Text(row, E.tokens.size.label, "LEFT")
		row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
		row.name:SetWidth(180)
		row.remove = CloseGlyph(row)
		row.remove:SetPoint("RIGHT", -2, 0)
		row.have = E.UIKit.Text(row, E.tokens.size.small, "RIGHT", "secondary")
		row.have:SetPoint("RIGHT", row.remove, "LEFT", -6, 0)
		row.have:SetWidth(44)
		row.amount = FlatInput(row, 52, true)
		row.amount:SetHeight(18)
		row.amount:SetMaxLetters(5)
		row.amount:SetPoint("RIGHT", row.have, "LEFT", -6, 0)
		row.amount:HookScript("OnTextChanged", function(box, user)
			if not user or not row.entry then return end
			row.entry.amount = tonumber(box:GetText()) or 0
			M:UpdateButtons()
		end)
		row.amount:SetScript("OnEnterPressed", function(box) box:ClearFocus() end)
		row.remove:SetScript("OnClick", function()
			if row.index then M:RemoveRestock(row.index) end
		end)
		row:EnableMouse(true)
		row:SetScript("OnEnter", function(line)
			if not line.entry or not line.entry.id then return end
			E.UIKit.AnchorTooltip(line)
			GameTooltip:SetItemByID(line.entry.id)
			GameTooltip:Show()
		end)
		row:SetScript("OnLeave", GameTooltip_Hide)
		frame.rows[i] = row
	end

	frame.empty = E.UIKit.Text(area, E.tokens.size.label, "CENTER", "secondary")
	frame.empty:SetPoint("CENTER")
	frame.empty:SetText(L["Nothing on the list yet."])

	-- Footer
	frame.help = E.UIKit.Text(frame, E.tokens.size.small, "LEFT", "secondary")
	frame.help:SetPoint("BOTTOMLEFT", 10, 10)
	frame.help:SetPoint("BOTTOMRIGHT", -110, 10)
	frame.help:SetWordWrap(true)
	frame.help:SetText(L["Restock buys only what's missing, never more. At a vendor, Alt-click an item to add it."])
	local clear = E.UIKit.Button(frame, L["Clear all"], { width = 90, height = E.tokens.height.button, kind = "danger",
		tipTitle = L["Clear all"], tip = L["Empty the restock list. Asks first."] })
	clear:SetPoint("BOTTOMRIGHT", -10, 8)
	frame.clear = clear
	clear:SetScript("OnClick", function()
		local count = 0
		for _ in pairs(M.db.restock) do count = count + 1 end
		if count == 0 then
			E.UIKit.Toast(frame, L["The restock list is already empty."])
			return
		end
		E:ShowConfirm({ title = L["Clear all"], accept = L["Clear"], danger = true,
			text = E:Plural(count, "Remove %d item from the restock list?", "Remove all %d items from the restock list?"):format(count)
				.. " " .. L["This can't be undone."],
			onAccept = function()
				wipe(M.db.restock)
				M:RestockChanged()
				E.UIKit.Toast(frame, L["The restock list is empty."])
			end })
	end)
	-- The list follows the bags only while it is open.
	frame:HookScript("OnShow", function()
		frame:RegisterEvent("BAG_UPDATE_DELAYED")
		M:UpdateEditor()
	end)
	frame:HookScript("OnHide", function() frame:UnregisterEvent("BAG_UPDATE_DELAYED") end)
	if frame:IsShown() then frame:RegisterEvent("BAG_UPDATE_DELAYED") end
	frame:SetScript("OnEvent", function() if frame:IsShown() then M:UpdateEditor() end end)
	self.editor = frame
end

function M:UpdateEditor()
	local frame = self.editor
	if not frame then return end
	local list = self.db.restock
	frame.offset = max(0, min(frame.offset, max(0, #list - EDITOR_ROWS)))
	for i, row in ipairs(frame.rows) do
		local index = frame.offset + i
		local entry = list[index]
		row.entry, row.index = entry, entry and index
		if entry then
			if entry.id and not entry.name then entry.name = C_Item.GetItemInfo(entry.id) end
			local icon = entry.id and C_Item.GetItemIconByID and C_Item.GetItemIconByID(entry.id)
			row.icon:SetTexture(icon or 134400)
			local quality = entry.id and select(3, C_Item.GetItemInfo(entry.id))
			local r, g, b = 1, 1, 1
			if quality and C_Item.GetItemQualityColor then r, g, b = C_Item.GetItemQualityColor(quality) end
			row.name:SetText(entry.name or L["Item %s"]:format(tostring(entry.id)))
			row.name:SetTextColor(r, g, b)
			if not row.amount:HasFocus() then row.amount:SetText(entry.amount or 0) end
			row.have:SetText(entry.id and C_Item.GetItemCount(entry.id, false) or "?")
			row:Show()
		else
			row:Hide()
		end
	end
	frame.empty:SetShown(#list == 0)
end

function M:ToggleEditor()
	if not self.editor then self:CreateEditor() end
	self.editor:SetShown(not self.editor:IsShown())
end

---------------------------------------------------------------------------
-- Item list beside the merchant window ("Improve"): every item the vendor
-- sells as rows or a grid of tiles, with prices, stock and upgrade
-- arrows. A search and a filter bar hide or dim what doesn't match; they
-- only change what is shown, buying stays one click, one purchase.
---------------------------------------------------------------------------
local HEADER, FOOTER, FILTERBAR, GAP = 56, 64, 48, 4
local DIM_ALPHA = 0.3

local function Clamp(value, low, high)
	value = floor(tonumber(value) or low)
	return value < low and low or (value > high and high or value)
end

-- Blizzard's localized text when the game has it, else ours.
local function GlobalText(name, fallback)
	local text = rawget(_G, name)
	return type(text) == "string" and text ~= "" and text or fallback
end

-- Equip slots in paper-doll order; look-alike slots share one entry.
local SLOT_ORDER = {
	"INVTYPE_HEAD", "INVTYPE_NECK", "INVTYPE_SHOULDER", "INVTYPE_CLOAK", "INVTYPE_CHEST", "INVTYPE_BODY",
	"INVTYPE_TABARD", "INVTYPE_WRIST", "INVTYPE_HAND", "INVTYPE_WAIST", "INVTYPE_LEGS", "INVTYPE_FEET",
	"INVTYPE_FINGER", "INVTYPE_TRINKET", "INVTYPE_WEAPON", "INVTYPE_2HWEAPON", "INVTYPE_WEAPONMAINHAND",
	"INVTYPE_WEAPONOFFHAND", "INVTYPE_SHIELD", "INVTYPE_HOLDABLE", "INVTYPE_RANGED", "INVTYPE_RELIC",
	"INVTYPE_AMMO", "INVTYPE_BAG", "INVTYPE_QUIVER",
}
local SLOT_SAME = { INVTYPE_ROBE = "INVTYPE_CHEST", INVTYPE_RANGEDRIGHT = "INVTYPE_RANGED", INVTYPE_THROWN = "INVTYPE_RANGED" }
local SLOT_FALLBACK = {
	INVTYPE_HEAD = "Head", INVTYPE_NECK = "Neck", INVTYPE_SHOULDER = "Shoulder", INVTYPE_CLOAK = "Back",
	INVTYPE_CHEST = "Chest", INVTYPE_BODY = "Shirt", INVTYPE_TABARD = "Tabard", INVTYPE_WRIST = "Wrist",
	INVTYPE_HAND = "Hands", INVTYPE_WAIST = "Waist", INVTYPE_LEGS = "Legs", INVTYPE_FEET = "Feet",
	INVTYPE_FINGER = "Finger", INVTYPE_TRINKET = "Trinket", INVTYPE_WEAPON = "One-Hand", INVTYPE_2HWEAPON = "Two-Hand",
	INVTYPE_WEAPONMAINHAND = "Main Hand", INVTYPE_WEAPONOFFHAND = "Off Hand", INVTYPE_SHIELD = "Shield",
	INVTYPE_HOLDABLE = "Held In Off-hand", INVTYPE_RANGED = "Ranged", INVTYPE_RELIC = "Relic",
	INVTYPE_AMMO = "Ammo", INVTYPE_BAG = "Bag", INVTYPE_QUIVER = "Quiver",
}

local function SlotName(slot)
	return GlobalText(slot, L[SLOT_FALLBACK[slot] or slot])
end

local QUALITY_FALLBACK = { [0] = "Poor", "Common", "Uncommon", "Rare", "Epic", "Legendary" }

local function QualityName(quality)
	return GlobalText("ITEM_QUALITY" .. quality .. "_DESC", L[QUALITY_FALLBACK[quality] or "Common"])
end

-- The on/off filters, as chips under the search box.
local FILTER_CHIPS = {
	{ "usable", "Usable", "Only items your character can use." },
	{ "afford", "Affordable", "Only items you have the gold (and currency) for." },
	{ "stock", "In stock", "Hide items the vendor has sold out." },
	{ "known", "Not known", "Hide recipes, mounts, pets and toys you already know." },
}

-- What the filters need to know about one vendor item.
function M:ItemFacts(index)
	local name, price, perBuy, available, extended, info = MerchantItem(index)
	if not name then return end
	local link = GetMerchantItemLink(index)
	local id = GetMerchantItemID(index)
	local typeName, subTypeName, equipLoc, classID
	local item = id or link
	if item and C_Item.GetItemInfoInstant then
		local _
		_, typeName, subTypeName, equipLoc, _, classID = C_Item.GetItemInfoInstant(item)
	end
	local quality = link and select(3, C_Item.GetItemInfo(link))
	local usable = true
	if info then
		usable = info.isUsable ~= false
	elseif GetMerchantItemInfo then
		usable = select(7, GetMerchantItemInfo(index)) ~= false
	end
	local afford = true
	if CanAffordMerchantItem then afford = CanAffordMerchantItem(index) ~= false end
	if afford and (price or 0) > GetMoney() then afford = false end
	local slot = equipLoc and equipLoc ~= "" and (SLOT_SAME[equipLoc] or equipLoc) or nil
	return {
		index = index, name = name, price = price, perBuy = perBuy, available = available, extended = extended,
		texture = info and info.texture, link = link, id = id, quality = quality,
		classID = classID, className = typeName, subTypeName = subTypeName,
		slot = SLOT_FALLBACK[slot or ""] and slot or nil,
		usable = usable, afford = afford, inStock = not (available and available == 0),
		known = (link and E.IsItemKnown and E:IsItemKnown(link)) and true or false,
	}
end

function M:DefaultFilters()
	local db = self.db
	return {
		quality = Clamp(db.filterQuality, 0, 5),
		usable = db.filterUsable or nil, afford = db.filterAfford or nil,
		stock = db.filterStock or nil, known = db.filterKnown or nil,
	}
end

-- At every vendor: the remembered filters, or the ones set in the options.
function M:LoadFilters()
	local saved = self.db.rememberFilters and self.db.filterState
	if type(saved) == "table" and next(saved) then
		self.filters = CopyTable(saved)
	else
		self.filters = self:DefaultFilters()
	end
end

function M:Filters()
	if not self.filters then self:LoadFilters() end
	return self.filters
end

-- Applies a filter change: saved when filters are remembered, list redrawn.
function M:FiltersChanged()
	if self.db.rememberFilters and self.filters then self.db.filterState = CopyTable(self.filters) end
	if self.list then self.list.offset = 0 end
	self:UpdateList()
end

function M:SetFilter(key, value)
	local filters = self:Filters()
	if value == false then value = nil end
	filters[key] = value
	self:FiltersChanged()
end

-- Everything shown again: no search, no filters.
function M:ClearFilters()
	self.filters = { quality = 0 }
	if self.list then self.list.search:SetText("") end
	self:FiltersChanged()
end

-- A category or slot filter for something this vendor doesn't sell is
-- ignored here (and shown as "All"), so a remembered one can't empty the list.
function M:ActiveFilter(key, present)
	local value = self:Filters()[key]
	if value == nil then return nil end
	if key == "class" or key == "slot" then
		return present and present[key][value] and value or nil
	end
	return value
end

function M:Matches(facts, search, present)
	if search ~= "" then
		local hay = facts.name:lower()
		if not hay:find(search, 1, true) and not (facts.subTypeName and facts.subTypeName:lower():find(search, 1, true))
			and not (facts.className and facts.className:lower():find(search, 1, true)) then
			return false
		end
	end
	if not self.db.filterBar then return true end
	local class, slot = self:ActiveFilter("class", present), self:ActiveFilter("slot", present)
	if class and facts.classID ~= class then return false end
	if slot and facts.slot ~= slot then return false end
	local quality = self:Filters().quality or 0
	if quality > 0 and facts.quality and facts.quality < quality then return false end
	local filters = self:Filters()
	if filters.usable and not facts.usable then return false end
	if filters.afford and not facts.afford then return false end
	if filters.stock and not facts.inStock then return false end
	if filters.known and facts.known then return false end
	return true
end

function M:AnyFilter(present)
	local filters = self:Filters()
	return (self:ActiveFilter("class", present) or self:ActiveFilter("slot", present) or (filters.quality or 0) > 0
		or filters.usable or filters.afford or filters.stock or filters.known) and true or false
end

function M:ShowFilterMenu(kind, anchor)
	local present = self.list and self.list.present or { class = {}, slot = {} }
	E.UIKit.ContextMenu(anchor, function(_, root)
		local function Radio(label, value)
			root:CreateRadio(label,
				function() return M:ActiveFilter(kind, present) == value or (kind == "quality" and (M:Filters().quality or 0) == value) end,
				function() M:SetFilter(kind, value) end)
		end
		if kind == "class" then
			Radio(L["All categories"], nil)
			local list = {}
			for classID, name in pairs(present.class) do list[#list + 1] = { id = classID, name = name } end
			table.sort(list, function(a, b) return a.name < b.name end)
			for _, entry in ipairs(list) do Radio(entry.name, entry.id) end
		elseif kind == "slot" then
			Radio(L["All slots"], nil)
			for _, slot in ipairs(SLOT_ORDER) do
				if present.slot[slot] then Radio(SlotName(slot), slot) end
			end
		else
			Radio(L["Any quality"], 0)
			for quality = 1, 4 do Radio(L["%s or better"]:format(QualityName(quality)), quality) end
		end
	end, { at = "owner" })
end

local function FilterButton(parent, kind, tipTitle, tipText)
	local button = FlatButton(parent, "", 80, 20)
	button.text:ClearAllPoints()
	button.text:SetPoint("LEFT", 6, 0)
	button.text:SetPoint("RIGHT", -16, 0)
	button.text:SetJustifyH("LEFT")
	button.text:SetWordWrap(false)
	button.arrow = E.UIKit.Chevron(button, "down", 10)
	button.arrow:SetPoint("RIGHT", -4, 0)
	button:SetScript("OnClick", function(self) M:ShowFilterMenu(kind, self) end)
	E.UIKit.Tooltip(button, tipTitle, tipText)
	return button
end

function M:CreateFilterBar(panel)
	local bar = CreateFrame("Frame", nil, panel)
	bar:SetPoint("TOPLEFT", 8, -HEADER)
	bar:SetPoint("TOPRIGHT", -8, -HEADER)
	bar:SetHeight(FILTERBAR - 4)
	bar.class = FilterButton(bar, "class", L["Category"], L["Show one kind of item: weapons, armor, recipes, consumables and so on."])
	bar.slot = FilterButton(bar, "slot", L["Slot"], L["Show gear for one equipment slot."])
	bar.quality = FilterButton(bar, "quality", L["Quality"], L["Hide items below this quality."])
	bar.clear = CloseGlyph(bar, true)
	bar.clear:SetPoint("TOPRIGHT", 0, -2)
	bar.clear:SetScript("OnClick", function() M:ClearFilters() end)
	E.UIKit.Tooltip(bar.clear, L["Show everything"], L["Clears the search and every filter."])
	local chips = {}
	for i, data in ipairs(FILTER_CHIPS) do chips[i] = { data[1], L[data[2]], L[data[3]] } end
	bar.chips = E.UIKit.ChipBar(bar, {
		multi = true,
		chips = chips,
		onChange = function(selected, key) M:SetFilter(key, selected[key] or false) end,
	})
	bar.chips:SetPoint("TOPLEFT", 0, -24)
	panel.filters = bar
end

-- Labels and chips follow the current filters.
function M:UpdateFilterBar(present)
	local panel = self.list
	local bar = panel and panel.filters
	if not bar or not bar:IsShown() then return end
	local filters = self:Filters()
	local class, slot = self:ActiveFilter("class", present), self:ActiveFilter("slot", present)
	local quality = filters.quality or 0
	local function Label(button, active, text)
		button.text:SetText(text)
		if active then button.text:SetTextColor(E:TokenColor("accent")) else button.text:SetTextColor(1, 1, 1) end
	end
	Label(bar.class, class, class and present.class[class] or L["All categories"])
	Label(bar.slot, slot, slot and SlotName(slot) or L["All slots"])
	Label(bar.quality, quality > 0, quality > 0 and L["%s or better"]:format(QualityName(quality)) or L["Any quality"])
	bar.chips:SetSelected({ usable = filters.usable, afford = filters.afford, stock = filters.stock, known = filters.known })
	local searching = strtrim(panel.search:GetText() or "") ~= ""
	bar.clear:SetShown(searching or self:AnyFilter(present))
end

function M:CreateList()
	local panel = CreateFrame("Frame", "EldoUI_MerchantList", MerchantFrame)
	panel:SetPoint("TOPLEFT", MerchantFrame, "TOPRIGHT", 4, 0)
	panel:SetPoint("BOTTOMLEFT", MerchantFrame, "BOTTOMRIGHT", 4, 0)
	panel:EnableMouse(true)
	panel:EnableMouseWheel(true)
	E:SetPanelTemplate(panel)
	panel:Hide()

	panel.title = E.UIKit.Title(panel, E.tokens.size.dialogTitle)
	panel.title:SetPoint("TOPLEFT", 10, -6)
	panel.title:SetText(L["All items"])
	panel.count = E.UIKit.Text(panel, E.tokens.size.small, "RIGHT", "secondary")
	panel.count:SetPoint("TOPRIGHT", -10, -10)
	panel.line = panel:CreateTexture(nil, "ARTWORK")
	panel.line:SetPoint("TOPLEFT", E.pixel, -26)
	panel.line:SetPoint("TOPRIGHT", -E.pixel, -26)
	panel.line:SetHeight(E.pixel * 2)
	E:AccentTexture(panel.line)

	local search = FlatInput(panel, 100, false, L["Search name or type"])
	search:SetPoint("TOPLEFT", 8, -32)
	search:SetPoint("TOPRIGHT", -8, -32)
	search:HookScript("OnTextChanged", function()
		panel.offset = 0
		M:UpdateList()
	end)
	search:SetScript("OnEnterPressed", search.ClearFocus)
	panel.search = search

	self:CreateFilterBar(panel)

	panel.body = CreateFrame("Frame", nil, panel)
	panel.body:SetPoint("TOPLEFT", 6, -HEADER)
	panel.body:SetPoint("BOTTOMRIGHT", -12, FOOTER)
	panel.rows = {}
	panel.offset = 0
	panel:SetScript("OnMouseWheel", function(_, delta)
		panel.offset = panel.offset - delta * (panel.columns or 1)
		M:UpdateList()
	end)
	panel.empty = E.UIKit.Text(panel.body, E.tokens.size.label, "CENTER", "secondary")
	panel.empty:SetPoint("TOPLEFT", 10, -20)
	panel.empty:SetPoint("TOPRIGHT", -10, -20)
	panel.empty:SetWordWrap(true)
	panel.empty:SetText(L["Nothing here matches the search or the filters."])
	panel.empty:Hide()

	-- The kit's scroll bar (thin track, dim thumb, accent on hover or drag).
	local bar = E.UIKit.ScrollBar(panel, function(value)
		if panel.syncing then return end
		panel.offset = value * (panel.columns or 1)
		M:UpdateList()
	end)
	bar:ClearAllPoints()
	bar:SetPoint("TOPRIGHT", -2, -HEADER)
	bar:SetPoint("BOTTOMRIGHT", -2, FOOTER)
	panel.bar = bar

	-- Footer: restock and ammo buttons, and the list editor.
	panel.footer = CreateFrame("Frame", nil, panel)
	panel.footer:SetPoint("BOTTOMLEFT", 8, 8)
	panel.footer:SetPoint("BOTTOMRIGHT", -8, 8)
	panel.footer:SetHeight(FOOTER - 12)
	self.list = panel
end

local function ListRow(panel, i)
	local row = panel.rows[i]
	if row then return row end
	row = CreateFrame("Button", nil, panel.body)
	row:Hide()
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	row:RegisterForDrag("LeftButton")
	row.stripe = row:CreateTexture(nil, "BACKGROUND")
	row.stripe:SetAllPoints()
	local hover = row:CreateTexture(nil, "HIGHLIGHT")
	hover:SetAllPoints()
	hover:SetColorTexture(1, 1, 1, E.tokens.hover.row)
	row.slot = CreateFrame("Button", nil, row)
	row.slot:EnableMouse(false)
	E:SetTemplate(row.slot)
	row.icon = row.slot:CreateTexture(nil, "ARTWORK")
	row.icon:SetPoint("TOPLEFT", E.pixel, -E.pixel)
	row.icon:SetPoint("BOTTOMRIGHT", -E.pixel, E.pixel)
	E:TrimIcon(row.icon)
	row.lot = E:CreateText(row.slot, E.tokens.size.tiny, "RIGHT")
	row.lot:SetPoint("BOTTOMRIGHT", -1, 1)
	row.name = E:CreateText(row, E.tokens.size.label, "LEFT")
	row.price = E:CreateText(row, E.tokens.size.label, "RIGHT")
	row.stock = E:CreateText(row, E.tokens.size.tiny, "RIGHT")
	row.stock:SetTextColor(unpack(E.tokens.text.secondary))
	row.listParts = { row.slot, row.name, row.price, row.stock }
	row:SetScript("OnClick", function(self, mouse)
		local index = self.index
		if not index then return end
		if IsModifiedClick() then
			if HandleModifiedItemClick(GetMerchantItemLink(index)) then return end
			if IsAltKeyDown() then
				M:AddFromMerchant(index)
				return
			end
			if IsModifiedClick("SPLITSTACK") then
				M:AskQuantity(index)
				return
			end
		end
		if mouse == "LeftButton" then
			PickupMerchantItem(index)
		else
			local _, _, perBuy = MerchantItem(index)
			M:ConfirmPurchase(index, perBuy)
		end
	end)
	row:SetScript("OnDragStart", function(self) if self.index then PickupMerchantItem(self.index) end end)
	row:SetScript("OnEnter", function(self)
		if not self.index then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetMerchantItem(self.index)
		if GameTooltip_ShowCompareItem then GameTooltip_ShowCompareItem(GameTooltip) end
		GameTooltip:AddLine(" ")
		E:TooltipHint(GameTooltip, { L["Right-click"], L["buy"] }, { L["Shift-click"], L["amount"] }, { L["Alt-click"], L["restock list"] })
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", function()
		GameTooltip:Hide()
		if ResetCursor then ResetCursor() end
	end)
	panel.rows[i] = row
	return row
end

function M:ListShown()
	return Allowed("improve") and Additions() and self.db.list and MerchantOpen() and MerchantFrame.selectedTab == 1
end

-- Rows: a list beside the window, as tall as the window, 1-2 columns.
-- Grid: tiles (icon, name, price), 2-6 columns by a set number of rows.
do
local layoutRequest = 0

local function MeasuredNumber(value, positive)
	return not E.Secret(value) and type(value) == "number" and value == value
		and value < math.huge and (positive and value > 0 or not positive and value >= 0)
end

-- The client keeps text widths as 32-bit floats, so a fractional width
-- reads back a hair off what was set. Widths within a hundredth of a UI
-- unit count as the same; a real width change is still told apart.
local TEXT_WIDTH_TOLERANCE = 0.01
local function SameTextWidth(actual, expected)
	return MeasuredNumber(actual) and MeasuredNumber(expected) and math.abs(actual - expected) <= TEXT_WIDTH_TOLERANCE
end

local function TextReservation(text, lines, current)
	if not current() then return end
	local value = text:GetText()
	if not current() or E.Secret(value) or (value ~= nil and type(value) ~= "string") then return end
	local path, size, flags = text:GetFont()
	if not current() or E.Secret(path) or type(path) ~= "string" or path == "" or not MeasuredNumber(size, true)
		or E.Secret(flags) or (type(flags) ~= "nil" and type(flags) ~= "string") then return end
	local spacing = text:GetSpacing()
	if not current() or not MeasuredNumber(spacing, false) then return end
	local scale = text:GetScale()
	if not current() or not MeasuredNumber(scale, true) or scale ~= 1 then return end
	local height = text:GetStringHeight()
	if not current() or not MeasuredNumber(height, value ~= nil and value ~= "") then return end
	-- The kit reserves font size plus spacing for each declared line. Empty
	-- rows still have that positive reservation before vendor data arrives.
	local reserved = max(lines * (size + spacing), height)
	if MeasuredNumber(reserved, true) then
		return reserved, { value = value, path = path, size = size, flags = flags, spacing = spacing, scale = scale }
	end
end

local function NaturalTextWidth(text, current)
	if not current() then return end
	local value = text:GetText()
	if not current() or E.Secret(value) or (value ~= nil and type(value) ~= "string") then return end
	local width = text:GetUnboundedStringWidth()
	if not current() or not MeasuredNumber(width, value ~= nil and value ~= "") then return end
	local after = text:GetText()
	if not current() or not E:SafeEquals(after, value) then return end
	return width, value
end

local function FooterReservation(text, width, value, current)
	local function SameText()
		if not current() then return false end
		local actual = text:GetText()
		return current() and E:SafeEquals(actual, value)
	end
	local function Put(method, ...)
		if not SameText() then return false end
		text[method](text, ...)
		return SameText()
	end
	if not MeasuredNumber(width, true) or not Put("SetWordWrap", true)
		or not Put("SetNonSpaceWrap", true) or not Put("SetMaxLines", 0)
		or not Put("SetWidth", width) or not Put("SetHeight", 0) then return end
	local height, font = TextReservation(text, 1, SameText)
	if not height or not SameText() then return end
	local wrapped = text:GetWrappedWidth()
	if not SameText() or not MeasuredNumber(wrapped, value ~= nil and value ~= "") or wrapped > width + TEXT_WIDTH_TOLERANCE then return end
	local truncated = text:IsTruncated()
	if not SameText() or E.Secret(truncated) or type(truncated) ~= "boolean" or truncated then return end
	local finalPath, finalSize, finalFlags = text:GetFont()
	if not SameText() or not E:SafeEquals(finalPath, font.path) or not E:SafeEquals(finalSize, font.size)
		or not E:SafeEquals(finalFlags, font.flags) then return end
	local finalSpacing = text:GetSpacing()
	if not SameText() or not E:SafeEquals(finalSpacing, font.spacing) then return end
	local finalScale = text:GetScale()
	if not SameText() or not E:SafeEquals(finalScale, font.scale) then return end
	local finalWidth = text:GetWidth()
	if not SameText() or not SameTextWidth(finalWidth, width) then return end
	font.width = width
	return height, font
end

local function FooterCurrent(text, saved, current)
	if not current() then return false end
	local value = text:GetText()
	if not current() or not E:SafeEquals(value, saved.value) then return false end
	local path, size, flags = text:GetFont()
	if not current() or not E:SafeEquals(path, saved.path) or not E:SafeEquals(size, saved.size)
		or not E:SafeEquals(flags, saved.flags) then return false end
	for _, entry in ipairs({ { "GetSpacing", "spacing" }, { "GetScale", "scale" }, { "GetWidth", "width" } }) do
		local method, key = entry[1], entry[2]
		local actual = text[method](text)
		local same = key == "width" and SameTextWidth(actual, saved[key]) or E:SafeEquals(actual, saved[key])
		if not current() or not same then return false end
	end
	return true
end

local function MeasuredContext(text, font, height, nonspace, name, current)
	if not FooterCurrent(text, font, current) then return end
	local measured = {}
	for _, entry in ipairs({ { "CanWordWrap", "wrap" }, { "CanNonSpaceWrap", "nonspace" }, { "GetMaxLines", "limit" } }) do
		local value = text[entry[1]](text)
		if not current() or E.Secret(value) then return end
		if entry[2] == "limit" then
			if not MeasuredNumber(value, false) or value % 1 ~= 0 then return end
		elseif type(value) ~= "boolean" then return end
		measured[entry[2]] = value
	end
	if not measured.wrap or measured.nonspace ~= nonspace or measured.limit ~= (name and 2 or 0) then return end
	for _, entry in ipairs({ { "GetHeight", "height" }, { "GetStringHeight", "required" }, { "GetWrappedWidth", "wrapped" } }) do
		local value = text[entry[1]](text)
		if not current() or not MeasuredNumber(value, font.value ~= nil and font.value ~= "") then return end
		measured[entry[2]] = value
	end
	local truncated = text:IsTruncated()
	if not current() or E.Secret(truncated) or type(truncated) ~= "boolean" then return end
	measured.truncated = truncated
	if measured.height < measured.required or measured.height > height then return end
	if not name and (measured.height ~= height or measured.wrapped > font.width + TEXT_WIDTH_TOLERANCE or truncated) then return end
	if not FooterCurrent(text, font, current) then return end
	return measured
end

function M:LayoutList()
	local panel = self.list
	if not panel then return end
	local db = self.db
	layoutRequest = layoutRequest + 1
	local request, active, merchant = layoutRequest, self.active, MerchantFrame
	local rows, body, scroll, filters = panel.rows, panel.body, panel.bar, panel.filters
	local filterButtons, chips = { filters.class, filters.slot, filters.quality }, filters.chips
	local keys = { "listLayout", "filterBar", "gridColumns", "gridRows", "gridCellWidth", "gridIconSize",
		"listColumns", "listWidth", "listRowHeight", "listFontSize", "listMoney" }
	local settings = {}
	for _, key in ipairs(keys) do settings[key] = db[key] end
	local function BaseCurrent()
		if layoutRequest ~= request or not E:SafeEquals(self.list, panel) or not E:SafeEquals(self.db, db)
			or not E:SafeEquals(self.active, active) or not E:SafeEquals(MerchantFrame, merchant)
			or not E:SafeEquals(panel.rows, rows) or not E:SafeEquals(panel.body, body)
			or not E:SafeEquals(panel.bar, scroll) or not E:SafeEquals(panel.filters, filters) then return false end
		if not E:SafeEquals(filters.class, filterButtons[1]) or not E:SafeEquals(filters.slot, filterButtons[2])
			or not E:SafeEquals(filters.quality, filterButtons[3]) or not E:SafeEquals(filters.chips, chips) then return false end
		for _, key in ipairs(keys) do if not E:SafeEquals(db[key], settings[key]) then return false end end
		return true
	end
	local function Current()
		if not BaseCurrent() then return false end
		for _, child in ipairs({ body, scroll, filters }) do
			local parent = child:GetParent()
			if not BaseCurrent() or not E:SafeEquals(parent, panel) then return false end
		end
		return true
	end
	local function Pending()
		if Current() then panel.layoutPending = true end
		return false
	end
	local grid = db.listLayout == "grid"
	local top = HEADER + (db.filterBar and FILTERBAR or 0)
	local columns, perColumn, cellWidth, cellHeight, gap, iconSize
	if grid then
		columns, perColumn = Clamp(db.gridColumns, 2, 6), Clamp(db.gridRows, 2, 12)
		iconSize = Clamp(db.gridIconSize, 20, 48)
		cellWidth, cellHeight, gap = Clamp(db.gridCellWidth, 100, 240), iconSize + 8, GAP
	else
		columns = db.listColumns == 2 and 2 or 1
		cellWidth, cellHeight, gap = db.listWidth, db.listRowHeight, 0
		local height = (MerchantFrame:GetHeight() or 0) - top - FOOTER
		perColumn = max(1, floor((height > 10 and height or 300) / cellHeight))
	end
	local needed = perColumn * columns
	local font = db.listFontSize
	local snapshots = {}
	local function RowCurrent(i, row, parts, original)
		local function Bound()
			if not Current() or not E:SafeEquals(rows[i], row) or not E:SafeEquals(row.listParts, original)
				or not E:SafeEquals(row.slot, parts[1]) or not E:SafeEquals(row.name, parts[2])
				or not E:SafeEquals(row.price, parts[3]) or not E:SafeEquals(row.stock, parts[4]) then return false end
			for part = 1, 4 do if not E:SafeEquals(rawget(original, part), parts[part]) then return false end end
			return true
		end
		if not Bound() then return false end
		local parent = row:GetParent()
		if not Bound() or not E:SafeEquals(parent, body) then return false end
		for part = 1, 4 do
			local child = rawget(parts, part)
			if E.Secret(child) or type(child) ~= "table" then return false end
			parent = child:GetParent()
			if not Bound() or not E:SafeEquals(parent, row) then return false end
		end
		return true
	end
	if not Current() then return Pending() end
	local visible = panel.visible
	if E.Secret(visible) or (type(visible) ~= "nil" and not MeasuredNumber(visible, true)) then return Pending() end
	local laidOut = type(visible) ~= "nil"
	-- Backdrop size callbacks also read these values. A new panel may not
	-- have a size yet; an existing layout must keep positive public sizes.
	local initialWidth = panel:GetWidth()
	if not Current() or not MeasuredNumber(initialWidth, laidOut) then return Pending() end
	local initialHeight = panel:GetHeight()
	if not Current() or not MeasuredNumber(initialHeight, laidOut) then return Pending() end
	if grid then
		for i = 1, needed do
			local row = ListRow(panel, i)
			local original = row.listParts
			if E.Secret(original) or type(original) ~= "table" or type(getmetatable(original)) ~= "nil" then return Pending() end
			local parts = { rawget(original, 1), rawget(original, 2), rawget(original, 3), rawget(original, 4) }
			local function Owns() return RowCurrent(i, row, parts, original) end
			if not Owns() then return Pending() end
			E:SetFont(parts[2], max(9, font - 1))
			if not Owns() then return Pending() end
			E:SetFont(parts[3], max(9, font - 1))
			if not Owns() then return Pending() end
			E:SetFont(parts[4], max(9, font - 2))
			if not Owns() then return Pending() end
			parts[2]:SetWordWrap(true)
			if not Owns() then return Pending() end
			parts[2]:SetMaxLines(2)
			if not Owns() then return Pending() end
			local nameNonspace = parts[2]:CanNonSpaceWrap()
			if not Owns() or E.Secret(nameNonspace) or type(nameNonspace) ~= "boolean" then return Pending() end
			local name, nameContext = TextReservation(parts[2], 2, Owns)
			if not name or not Owns() then return Pending() end
			nameContext.width = cellWidth - iconSize - 12
			local priceWidth, priceText = NaturalTextWidth(parts[3], Owns)
			if priceWidth == nil or not Owns() then return Pending() end
			local stockWidth, stockText = NaturalTextWidth(parts[4], Owns)
			if stockWidth == nil or not Owns() then return Pending() end
			local available = cellWidth - 7
			local both = priceText ~= nil and priceText ~= "" and stockText ~= nil and stockText ~= ""
			local separate = both and priceWidth + GAP + stockWidth > available
			local priceRoom = both and not separate and available - stockWidth - GAP or available
			local stockRoom = both and not separate and stockWidth or available
			local price, priceContext = FooterReservation(parts[3], priceRoom, priceText, Owns)
			if not price or not Owns() then return Pending() end
			local stock, stockContext = FooterReservation(parts[4], stockRoom, stockText, Owns)
			if not stock or not Owns() then return Pending() end
			local header = max(4 + iconSize, 3 + name)
			local height = header + GAP + (separate and price + GAP + stock or max(price, stock)) + 4
			if not MeasuredNumber(height, true) then return Pending() end
			cellHeight = max(cellHeight, math.ceil(height))
			snapshots[i] = { row, parts, original, priceRoom, stockRoom, price, stock, separate,
				priceContext, stockContext, nameContext, name, nameNonspace }
		end
	end
	local function Place(frame, method, ...)
		if not Current() then return false end
		local filterChild = frame == chips
		for _, button in ipairs(filterButtons) do if frame == button then filterChild = true;break end end
		local function TargetCurrent()
			if not Current() then return false end
			if not filterChild then return true end
			local parent = frame:GetParent()
			return Current() and E:SafeEquals(parent, filters)
		end
		if not TargetCurrent() then return false end
		frame[method](frame, ...)
		return TargetCurrent()
	end
	if not Place(filters, "SetShown", db.filterBar and true or false)
		or not Place(body, "ClearAllPoints") or not Place(body, "SetPoint", "TOPLEFT", 6, -top)
		or not Place(body, "SetPoint", "BOTTOMRIGHT", -12, FOOTER)
		or not Place(scroll, "ClearAllPoints") or not Place(scroll, "SetPoint", "TOPRIGHT", -2, -top)
		or not Place(scroll, "SetPoint", "BOTTOMRIGHT", -2, FOOTER)
		or not Place(panel, "ClearAllPoints")
		or not Place(panel, "SetPoint", "TOPLEFT", MerchantFrame, "TOPRIGHT", 4, 0) then return Pending() end
	if grid then
		if not Place(panel, "SetHeight", top + perColumn * (cellHeight + gap) - gap + FOOTER + 2)
			or not Place(panel, "SetWidth", columns * (cellWidth + gap) - gap + 18) then return Pending() end
	else
		if not Place(panel, "SetPoint", "BOTTOMLEFT", MerchantFrame, "BOTTOMRIGHT", 4, 0)
			or not Place(panel, "SetWidth", cellWidth * columns + 18) then return Pending() end
	end
	if not Current() then return Pending() end
	panel.perColumn, panel.columns, panel.grid = perColumn, columns, grid
	for i = 1, max(needed, #panel.rows) do
		if not Current() then return Pending() end
		local row = ListRow(panel, i)
		if i <= needed then
			local column = floor((i - 1) / perColumn)
			local line = (i - 1) % perColumn
			local snapshot = snapshots[i]
			if grid and not RowCurrent(i, snapshot[1], snapshot[2], snapshot[3]) then return Pending() end
			if grid then
				local parts = snapshot[2]
				local function Put(frame, method, ...)
					if not RowCurrent(i, row, parts, snapshot[3]) then return false end
					frame[method](frame, ...)
					return RowCurrent(i, row, parts, snapshot[3])
				end
				if not Put(row, "ClearAllPoints") or not Put(parts[1], "ClearAllPoints")
					or not Put(parts[2], "ClearAllPoints") or not Put(parts[3], "ClearAllPoints")
					or not Put(parts[4], "ClearAllPoints")
					or not Put(row, "SetPoint", "TOPLEFT", column * (cellWidth + gap), -line * (cellHeight + gap))
					or not Put(row, "SetSize", cellWidth, cellHeight)
					or not Put(parts[1], "SetSize", iconSize, iconSize)
					or not Put(parts[1], "SetPoint", "TOPLEFT", 4, -4)
					or not Put(parts[2], "SetPoint", "TOPLEFT", parts[1], "TOPRIGHT", 5, 1)
					or not Put(parts[2], "SetPoint", "TOPRIGHT", -3, -3)
					or not Put(parts[3], "SetWidth", snapshot[4]) or not Put(parts[3], "SetHeight", snapshot[6])
					or not Put(parts[4], "SetWidth", snapshot[5]) or not Put(parts[4], "SetHeight", snapshot[7])
					or not Put(parts[3], "SetPoint", "BOTTOMLEFT", row, "BOTTOMLEFT", 4, snapshot[8] and 4 + snapshot[7] + GAP or 4)
					or not Put(parts[4], "SetPoint", "BOTTOMRIGHT", -3, 4) then return Pending() end
			else
				row:ClearAllPoints()
				row.slot:ClearAllPoints()
				row.name:ClearAllPoints()
				row.price:ClearAllPoints()
				row.stock:ClearAllPoints()
				row:SetPoint("TOPLEFT", column * cellWidth, -line * cellHeight)
				row:SetSize(cellWidth - 4, cellHeight)
				local size = cellHeight - 4
				row.slot:SetSize(size, size)
				row.slot:SetPoint("LEFT", 2, 0)
				row.stock:SetPoint("RIGHT", -2, 0)
				row.price:SetPoint("RIGHT", row.stock, "LEFT", -4, 0)
				row.name:SetPoint("LEFT", row.slot, "RIGHT", 6, 0)
				row.name:SetPoint("RIGHT", row.price, "LEFT", -6, 0)
				row.name:SetWordWrap(false)
				row.name:SetMaxLines(1)
				for _, text in ipairs({ row.price, row.stock }) do
					text:SetWordWrap(false)
					text:SetNonSpaceWrap(false)
					text:SetMaxLines(1)
					text:SetWidth(0)
					text:SetHeight(0)
				end
				E:SetFont(row.name, font)
				E:SetFont(row.price, font)
			end
			if not grid then E:SetFont(row.stock, max(9, font - 2)) end
			if grid and not RowCurrent(i, snapshot[1], snapshot[2], snapshot[3]) then return Pending() end
		else
			row:Hide()
			if not Current() then return Pending() end
		end
	end
	panel.visible = needed
	-- The three filter menus share the width; the chips shrink to fit.
	local width = panel:GetWidth()
	if not Current() or not MeasuredNumber(width, true) or width <= 16 then return Pending() end
	local inner = width - 16
	local third = floor((inner - 20 - 2 * GAP) / 3)
	for i, button in ipairs(filterButtons) do
		if not Place(button, "ClearAllPoints") or not Place(button, "SetWidth", max(40, third))
			or not Place(button, "SetPoint", "TOPLEFT", (i - 1) * (third + GAP), 0) then return Pending() end
	end
	if not Current() then return Pending() end
	local chipsParent = chips:GetParent()
	if not Current() or not E:SafeEquals(chipsParent, filters) then return Pending() end
	local chipsWidth = chips:GetWidth()
	if not Current() then return Pending() end
	chipsParent = chips:GetParent()
	if not Current() or not E:SafeEquals(chipsParent, filters) or not MeasuredNumber(chipsWidth, true)
		or not Place(chips, "SetScale", chipsWidth > inner and inner / chipsWidth or 1) then return Pending() end
	for i, snapshot in ipairs(snapshots) do
		local function Owns() return RowCurrent(i, snapshot[1], snapshot[2], snapshot[3]) end
		local contexts = {}
		contexts[1] = MeasuredContext(snapshot[2][2], snapshot[11], snapshot[12], snapshot[13], true, Owns)
		if not contexts[1] then return Pending() end
		contexts[2] = MeasuredContext(snapshot[2][3], snapshot[9], snapshot[6], true, false, Owns)
		if not contexts[2] then return Pending() end
		contexts[3] = MeasuredContext(snapshot[2][4], snapshot[10], snapshot[7], true, false, Owns)
		if not contexts[3] then return Pending() end
		snapshot[14] = contexts
	end
	self:LayoutButtons()
	if not Current() then return Pending() end
	for i, snapshot in ipairs(snapshots) do
		local function Owns() return RowCurrent(i, snapshot[1], snapshot[2], snapshot[3]) end
		if not Owns() then return Pending() end
		for index = 1, 3 do
			local contextFont = index == 1 and snapshot[11] or snapshot[index + 7]
			local height = index == 1 and snapshot[12] or snapshot[index + 4]
			local nonspace = true
			if index == 1 then nonspace = snapshot[13] end
			local context = MeasuredContext(snapshot[2][index + 1], contextFont, height, nonspace, index == 1, Owns)
			if not context then return Pending() end
			for key, value in pairs(snapshot[14][index]) do
				if not E:SafeEquals(context[key], value) then return Pending() end
			end
		end
	end
	panel.layoutPending = nil
	return true
end
end

local function ExtraCost(index)
	local count = GetMerchantItemCostInfo and GetMerchantItemCostInfo(index) or 0
	local parts = {}
	for i = 1, count do
		local texture, value = GetMerchantItemCostItem(index, i)
		if texture and value then parts[#parts + 1] = ("%d|T%s:0|t"):format(value, texture) end
	end
	return table.concat(parts, " ")
end

function M:FillRow(row, facts, line)
	local index, name, link, quality = facts.index, facts.name, facts.link, facts.quality
	local r, g, b = 1, 1, 1
	if quality and C_Item.GetItemQualityColor then r, g, b = C_Item.GetItemQualityColor(quality) end
	row.icon:SetTexture(facts.texture or (GetMerchantItemInfo and select(2, GetMerchantItemInfo(index))))
	row.name:SetText(name)
	row.name:SetTextColor(r, g, b)
	if self.db.knownTint and facts.known then
		row.icon:SetVertexColor(unpack(E.knownTint))
		row.name:SetText(name .. " " .. E:TokenHex(E.media.text.secondary) .. "(" .. (E:GameText(ITEM_SPELL_KNOWN, L["Already known"])) .. ")|r")
	elseif facts.usable then
		row.icon:SetVertexColor(1, 1, 1)
	else
		row.icon:SetVertexColor(E:TokenColor("bad"))
	end
	-- Uncommon and better: the quality color; the rest the theme border.
	if quality and quality >= 2 then
		row.slot:SetBackdropBorderColor(r, g, b, 1)
	else
		row.slot:SetBackdropBorderColor(unpack(E.media.borderColor))
	end
	row.lot:SetText(facts.perBuy > 1 and facts.perBuy or "")
	local text = (facts.price and facts.price > 0) and Money(facts.price) or ""
	if facts.extended then text = strtrim(text .. " " .. ExtraCost(index)) end
	row.price:SetText(text)
	if facts.afford then row.price:SetTextColor(1, 1, 1) else row.price:SetTextColor(unpack(E.media.text.bad)) end
	local available = facts.available
	row.stock:SetText((available and available >= 0) and ("(%d)"):format(available) or "")
	if self.list.grid then
		row.stripe:SetColorTexture(unpack(E.tokens.track))
	else
		row.stripe:SetColorTexture(1, 1, 1, (self.db.listZebra and line % 2 == 1) and 0.03 or 0)
	end
	row:SetAlpha(facts.match and 1 or DIM_ALPHA)
	if E.SetUpgradeArrow then E:SetUpgradeArrow(row.slot, link) end
	row:Show()
end

function M:UpdateList()
	local panel = self.list
	if not self:ListShown() then
		if panel then panel:Hide() end
		self:LayoutButtons()
		return
	end
	if not panel then
		self:CreateList()
		panel = self.list
	end
	if not panel:IsShown() then
		if self:LayoutList() == false then return end
		panel:Show()
		self:OfferListHelp()
	end
	local search = strtrim(panel.search:GetText() or ""):lower()
	local numItems = GetMerchantNumItems()
	local all, present = {}, { class = {}, slot = {} }
	for index = 1, numItems do
		local facts = self:ItemFacts(index)
		if facts then
			all[#all + 1] = facts
			if facts.classID and facts.className then present.class[facts.classID] = facts.className end
			if facts.slot then present.slot[facts.slot] = true end
		end
	end
	panel.present = present
	-- Hide: only matches are listed. Dim: everything, non-matches faded.
	local dim = self.db.searchMode == "dim"
	local items, matching = {}, 0
	for _, facts in ipairs(all) do
		facts.match = self:Matches(facts, search, present)
		if facts.match then matching = matching + 1 end
		if facts.match or dim then items[#items + 1] = facts end
	end
	panel.matching, panel.shown = matching, #items
	local columns = panel.columns or 1
	local total = #items
	local maxOffset = max(0, total - (panel.visible or 1))
	maxOffset = math.ceil(maxOffset / columns) * columns
	panel.offset = max(0, min(panel.offset, maxOffset))
	panel.syncing = true
	panel.bar:SetMinMaxValues(0, maxOffset / columns)
	panel.bar:SetValue(panel.offset / columns)
	panel.syncing = false
	panel.bar:SetShown(maxOffset > 0)
	panel.count:SetText(matching == #all and E:Plural(#all, "%d item", "%d items"):format(#all) or L["%d of %d"]:format(matching, #all))
	panel.empty:SetShown(matching == 0 and #all > 0 and not dim)
	-- Across each line, then down.
	local perColumn = panel.perColumn or 1
	for i = 1, panel.visible or 0 do
		local row = panel.rows[i]
		local column = floor((i - 1) / perColumn)
		local line = (i - 1) % perColumn
		local facts = items[panel.offset + line * columns + column + 1]
		row.index = facts and facts.index
		if facts then
			self:FillRow(row, facts, line)
		else
			row:Hide()
		end
	end
	if self:LayoutList() == false then return end
	self:UpdateFilterBar(present)
	self:LayoutButtons()
end

-- Alt-click on a vendor item: onto the restock list with one stack.
function M:AddFromMerchant(index)
	if not self.db.altClickAdd then return end
	local id = GetMerchantItemID(index)
	if not id then return end
	local name, _, perBuy = MerchantItem(index)
	local stack = select(8, C_Item.GetItemInfo(id)) or perBuy
	local entry = self:AddRestock(id, FindEntry(id, name) and 0 or max(stack or 1, perBuy))
	if entry then
		self:Print(L["%s is on your restock list: keep %d."]:format(entry.name or name, entry.amount))
		if not (self.editor and self.editor:IsShown()) then self:ToggleEditor() end
	end
end

---------------------------------------------------------------------------
-- Buy back this visit. When the window opens, the buyback tab's
-- items are noted; anything that shows up there afterwards was sold on
-- this visit. One click of "Buy back (N)" buys exactly those back, newest
-- first, out of combat. Nothing happens without that click.
---------------------------------------------------------------------------
local function BuybackLinks()
	local links = {}
	local count = type(GetNumBuybackItems) == "function" and GetNumBuybackItems() or 0
	for index = 1, count do
		local link = GetBuybackItemLink and GetBuybackItemLink(index)
		links[index] = type(link) == "string" and link or ("#" .. index)
	end
	return links
end

function M:NoteBuybackStart()
	local seen = {}
	for _, link in ipairs(BuybackLinks()) do seen[link] = (seen[link] or 0) + 1 end
	self.buybackBefore = seen
end

-- Buyback indexes of the items sold on this visit, lowest first. Entries
-- that were there at the start are matched once each, oldest first, so a
-- copy sold again now still counts as new.
function M:VisitBuyback()
	local indexes = {}
	if not self.buybackBefore then return indexes end
	local left = {}
	for link, count in pairs(self.buybackBefore) do left[link] = count end
	for index, link in ipairs(BuybackLinks()) do
		if (left[link] or 0) > 0 then
			left[link] = left[link] - 1
		else
			indexes[#indexes + 1] = index
		end
	end
	return indexes
end

function M:BuybackVisit()
	if InCombatLockdown() or not MerchantOpen() or type(BuybackItem) ~= "function" then return 0 end
	local indexes = self:VisitBuyback()
	-- Highest index first, so the indexes still to buy don't shift.
	for position = #indexes, 1, -1 do BuybackItem(indexes[position]) end
	return #indexes
end

function M:UpdateBuybackButton()
	local button = self.buybackButton
	if not button then return end
	local open = self.db.buybackButton and Allowed("improve") and Additions() and MerchantOpen()
	local count = open and #self:VisitBuyback() or 0
	local show = open and count > 0
	button:SetShown(show and true or false)
	if not show then return end
	button.text:SetText(L["Buy back (%d)"]:format(count))
	local usable = not InCombatLockdown()
	button:SetEnabled(usable)
	button:SetAlpha(usable and 1 or E.tokens.disabledAlpha)
end

function M:CreateBuybackButton()
	if self.buybackButton or not MerchantFrame then return end
	local button = FlatButton(MerchantFrame, L["Buy back"], 150, 22)
	button:SetPoint("TOPLEFT", MerchantFrame, "BOTTOMLEFT", 0, -4)
	button:HookScript("OnEnter", function(b)
		E.UIKit.AnchorTooltip(b)
		GameTooltip:SetText(L["Buy back this visit"])
		local secondary = E.tokens.text.secondary
		GameTooltip:AddLine(L["Buys back everything you sold since you opened this vendor."], secondary[1], secondary[2], secondary[3], true)
		for _, index in ipairs(self:VisitBuyback()) do
			local link = GetBuybackItemLink and GetBuybackItemLink(index)
			if link then GameTooltip:AddLine(link) end
		end
		GameTooltip:Show()
	end)
	button:HookScript("OnLeave", GameTooltip_Hide)
	button:SetScript("OnClick", function() M:BuybackVisit() end)
	button:Hide()
	self.buybackButton = button
end

function M:SellJunkBatch()
	local visit, profile = self.visit, self.db
	if not (self.active and self.db.junkButton and Allowed("improve") and Additions() and MerchantOpen())
		or E.PlainCall(InCombatLockdown) ~= false or self.junkSelling or E:StandsBack(self, "selljunk") then return false end
	if self.visit ~= visit or self.db ~= profile then return false end
	self:SellJunk(1, visit, true)
	self:UpdateButtons()
	return true
end

function M:UpdateJunkButton(improve)
	local profile = self.db
	local visit = self.visit
	local button = self.sellJunkButton
	if not self.active then if button then button:Hide() end return end
	if not button and improve and self.db.junkButton then
		button = FlatButton(MerchantFrame, L["Sell junk"], 230, 22)
		button:SetScript("OnClick", function() M:SellJunkBatch() end)
		E.UIKit.Tooltip(button, L["Sell junk"], L["Sell up to 12 eligible stacks. Each click starts one batch, which can be restored from the vendor's buyback tab."])
		self.sellJunkButton = button
	end
	if not button then return end
	local show = improve and self.db.junkButton and not E:StandsBack(self, "selljunk")
	local list, value = {}, 0
	if show then list = JunkSlots(true) end
	if self.db ~= profile or self.visit ~= visit or not self.active then return end
	for _, item in ipairs(list) do value = value + item.value end
	button:SetText(L["Sell junk (%d, %s)"]:format(#list, Money(value)))
	E.UIKit.RefitButton(button)
	button:SetEnabled(not self.junkSelling and E.PlainCall(InCombatLockdown) == false)
	button:SetShown(show and #list > 0 and true or false)
end

---------------------------------------------------------------------------
-- Restock / ammo buttons ("Improve")
---------------------------------------------------------------------------
local function VendorButton(label)
	local button = FlatButton(MerchantFrame, label, 150, 22)
	button.label = label
	button:HookScript("OnEnter", function(self)
		E.UIKit.AnchorTooltip(self)
		GameTooltip:SetText(label)
		if self.plan and #self.plan.items > 0 then
			for _, entry in ipairs(self.plan.items) do
				GameTooltip:AddDoubleLine(("%d x %s"):format(entry.quantity, entry.name), E:EconomyMoney(entry.cost), 1, 1, 1, 1, 1, 1)
			end
			local sr, sg, sb = unpack(E.tokens.text.secondary)
			GameTooltip:AddDoubleLine(L["Total"], E:EconomyMoney(PlanCost(self.plan)), sr, sg, sb, 1, 1, 1)
		end
		local wr, wg, wb = unpack(E.tokens.text.warn)
		for _, line in ipairs(self.plan and self.plan.skipped or {}) do GameTooltip:AddLine(line, wr, wg, wb, true) end
		GameTooltip:Show()
	end)
	button:HookScript("OnLeave", GameTooltip_Hide)
	button:SetScript("OnClick", function(self) if self.plan then M:Offer(self.plan) end end)
	button:Hide()
	return button
end

function M:CreateButtons()
	if self.restockButton then return end
	self.restockButton = VendorButton(L["Restock"])
	self.ammoButton = VendorButton(L["Fill ammo"])
	self.editButton = FlatButton(MerchantFrame, L["List"], 44, 22)
	self.editButton:SetScript("OnClick", function() M:ToggleEditor() end)
	E.UIKit.Tooltip(self.editButton, L["Restock list"], L["Which items to keep in your bags, and how many."])
	self.editButton:Hide()
end

local function LayoutJunkButton(self)
	local button = self.sellJunkButton
	if not button or not button:IsShown() then return end
	local parent, anchor, point, relativePoint, offset = MerchantFrame, MerchantFrame, "TOPLEFT", "BOTTOMLEFT", -4
	if self.list and self.list:IsShown() then
		parent = self.list.footer
		anchor, point, relativePoint, offset = parent, "BOTTOMLEFT", "BOTTOMLEFT", 0
	elseif self.buybackButton and self.buybackButton:IsShown() then
		anchor = self.buybackButton
	end
	local ownPoint, ownAnchor, ownRelative, x, y = E.PlainCallAll(button.GetPoint, button)
	if E.PlainCall(button.GetParent, button) == parent and ownPoint == point and ownAnchor == anchor
		and ownRelative == relativePoint and x == 0 and y == offset then return end
	button:SetParent(parent)
	button:ClearAllPoints()
	button:SetPoint(point, anchor, relativePoint, 0, offset)
end

-- In the item list's footer when it shows, else beside the window.
function M:LayoutButtons()
	LayoutJunkButton(self)
	if not self.restockButton then return end
	local inList = self.list and self.list:IsShown()
	local holder = inList and self.list.footer or MerchantFrame
	for _, button in ipairs({ self.restockButton, self.ammoButton, self.editButton }) do
		button:SetParent(holder)
		button:ClearAllPoints()
	end
	if inList then
		local half = (self.list.footer:GetWidth() - 52) / 2
		half = half > 40 and half or 120
		self.restockButton:SetWidth(half)
		self.ammoButton:SetWidth(half)
		self.restockButton:SetPoint("TOPLEFT", 0, 0)
		self.ammoButton:SetPoint("LEFT", self.restockButton, "RIGHT", 4, 0)
		self.editButton:SetPoint("TOPRIGHT", 0, 0)
	else
		self.restockButton:SetWidth(150)
		self.ammoButton:SetWidth(150)
		self.restockButton:SetPoint("TOPLEFT", MerchantFrame, "TOPRIGHT", 4, -30)
		self.ammoButton:SetPoint("TOPLEFT", self.restockButton, "BOTTOMLEFT", 0, -4)
		self.editButton:SetPoint("LEFT", self.restockButton, "RIGHT", 4, 0)
	end
end

function M:UpdateButtons()
	if not MerchantFrame then return end
	local improve = Allowed("improve") and Additions() and MerchantOpen()
	self:CreateBuybackButton()
	self:UpdateBuybackButton()
	self:UpdateJunkButton(improve)
	if not improve then
		if self.restockButton then
			self.restockButton:Hide()
			self.ammoButton:Hide()
			self.editButton:Hide()
		end
		return
	end
	self:CreateButtons()
	local restock = self.db.restockButton and self:RestockPlan() or NewPlan()
	self.restockButton.plan = restock
	self.restockButton.text:SetText(L["Restock  %s"]:format(E:EconomyMoney(PlanCost(restock))))
	self.restockButton:SetShown(#restock.items > 0)
	local ammo = self.db.ammoButton and self:AmmoPlan() or NewPlan()
	self.ammoButton.plan = ammo
	self.ammoButton.text:SetText(L["Fill ammo  %s"]:format(E:EconomyMoney(PlanCost(ammo))))
	self.ammoButton:SetShown(#ammo.items > 0)
	self.editButton:SetShown(self.db.restockButton)
	self:LayoutButtons()
end

---------------------------------------------------------------------------
-- Shift-click on Blizzard's item buttons buys a full stack; Alt-click adds
-- the item to the restock list ("Improve").
---------------------------------------------------------------------------
local function OnModifiedClick(button)
	if not Allowed("improve") or not MerchantFrame or MerchantFrame.selectedTab ~= 1 then return end
	local index = button:GetID()
	if IsAltKeyDown() and not IsShiftKeyDown() then
		M:AddFromMerchant(index)
		return
	end
	if not M.db.buyStacks or not IsShiftKeyDown() then return end
	local name, price, perBuy, _, extended = MerchantItem(index)
	local maxStack = GetMerchantItemMaxStack(index)
	if not name or extended or not maxStack or maxStack <= 1 then return end
	local quantity = floor(maxStack / perBuy) * perBuy
	if quantity <= 0 then return end
	if StackSplitFrame then StackSplitFrame:Hide() end
	-- Expensive stacks ask first, like Blizzard's own window.
	if (price or 0) * (quantity / perBuy) >= (MERCHANT_HIGH_PRICE_COST or 1500000) then
		M:ConfirmPurchase(index, quantity)
	else
		BuyMerchantItem(index, quantity)
	end
end

---------------------------------------------------------------------------
-- Blizzard element "merchant": skin, move and scale
---------------------------------------------------------------------------
local skinned = false

function M:SkinMerchant()
	if skinned or not Allowed("skin") or not MerchantFrame then return end
	skinned = true
	E:SkinPanel(MerchantFrame)
	if E.SkinAlphaZero then
		E:SkinAlphaZero(BuybackBG, MerchantFrameBottomLeftBorder, MerchantFramePortrait,
			MerchantExtraCurrencyBg, MerchantMoneyBg)
	end
	for _, bg in ipairs({ MerchantExtraCurrencyBg, MerchantMoneyBg }) do E:EconomyStrip(bg) end
	E:SkinInset(MerchantMoneyInset)
	E:SkinInset(MerchantExtraCurrencyInset)
	local tabs = {}
	for i = 1, 2 do tabs[#tabs + 1] = _G["MerchantFrameTab" .. i] end
	E:SkinTabs(tabs, { owner = MerchantFrame })
	if MerchantFrame.FilterDropdown then E:SkinDropdown(MerchantFrame.FilterDropdown) end
	for i = 1, 12 do
		local item = _G["MerchantItem" .. i]
		if item then
			E:EconomyStrip(item)
			local button = item.ItemButton or _G["MerchantItem" .. i .. "ItemButton"]
			if button then E:EconomySlot(button, button.icon or _G["MerchantItem" .. i .. "ItemButtonIconTexture"]) end
			local name = item.Name or _G["MerchantItem" .. i .. "Name"]
			if name then E:SetFont(name, E.tokens.size.label) end
		end
	end
	if MerchantBuyBackItem then
		E:EconomyStrip(MerchantBuyBackItem)
		local button = MerchantBuyBackItem.ItemButton or MerchantBuyBackItemItemButton
		if button then E:EconomySlot(button, button.icon) end
	end
	for _, button in ipairs({ MerchantRepairAllButton, MerchantRepairItemButton, MerchantGuildBankRepairButton, MerchantSellAllJunkButton }) do
		E:EconomySlot(button, button.Icon)
	end
	if MerchantPageText then E:SetFont(MerchantPageText, E.tokens.size.label) end
end

M.window = E:EconomyWindow({
	id = "merchant",
	key = "merchant",
	frame = function() return MerchantFrame end,
	mover = "EldoUI_MerchantWindow",
	title = "Merchant Window",
	point = { "TOPLEFT", "UIParent", "TOPLEFT", 20, -150 },
})

-- Blizzard's own item buttons get the "already known" tint
-- after Blizzard has drawn the page (it resets the color on every update).
function M:TintKnown()
	if not self.db.knownTint or not Allowed("improve") or not MerchantFrame or not MerchantFrame:IsShown() then return end
	if MerchantFrame.selectedTab and MerchantFrame.selectedTab ~= 1 then return end
	local perPage = MERCHANT_ITEMS_PER_PAGE or 10
	local page = MerchantFrame.page or 1
	for i = 1, perPage do
		local index = (page - 1) * perPage + i
		local button = _G["MerchantItem" .. i .. "ItemButton"]
		local link = index <= GetMerchantNumItems() and GetMerchantItemLink(index)
		if button and link and E:IsItemKnown(link) then
			local icon = button.icon or _G["MerchantItem" .. i .. "ItemButtonIconTexture"]
			if icon then icon:SetVertexColor(unpack(E.knownTint)) end
		end
	end
end

function M:ApplyBlizzard()
	if not self.active or not MerchantFrame then return end
	self:SkinMerchant()
	self.window:Apply()
	if not self.stackHooked and MerchantItemButton_OnModifiedClick then
		-- A post-hook keeps Blizzard's code untainted; it checks the switch each time.
		hooksecurefunc("MerchantItemButton_OnModifiedClick", OnModifiedClick)
		self.stackHooked = true
	end
	if not self.updateHooked and MerchantFrame_Update then
		hooksecurefunc("MerchantFrame_Update", function()
			if not M.active then return end
			-- The game also runs it while the window closes: then only a
			-- list still on screen goes away, nothing is drawn.
			if not MerchantOpen() then
				if M.list and M.list:IsShown() then M:UpdateList() end
				return
			end
			M:TintKnown()
			M:UpdateList()
		end)
		self.updateHooked = true
	end
	if self.list and self.list:IsShown() then self:LayoutList() end
	self:UpdateButtons()
	self:UpdateList()
end

function M:RestoreBlizzard()
	self.window:Restore()
	if self.list then self.list:Hide() end
	self:UpdateButtons()
end

E:RegisterBlizzardHandler("merchant", {
	owner = "Merchant",
	apply = function() M:ApplyBlizzard() end,
	undo = function() M:RestoreBlizzard() end,
	reload = { skin = true },
	install = { skin = true, improve = true },
	-- v0.5.0 put the restock / ammo buttons on the window when the module was on.
	legacy = function() return M.db and M.db.enabled end,
})

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------
function M:OnInitialize()
	self:MigrateRestockString()
end

-- Bag changes matter only while a vendor is open: the buttons listen from
-- MERCHANT_SHOW to MERCHANT_CLOSED and not for the rest of the session.
function M:WatchBags(open)
	if open then
		self:RegisterEvent("BAG_UPDATE_DELAYED", function() self:UpdateButtons() end)
	else
		self:UnregisterEvent("BAG_UPDATE_DELAYED")
	end
end

function M:OnEnable()
	RefreshJunkMarks()
	self:RegisterEvent("MERCHANT_SHOW", function()
		self:WatchBags(true)
		-- Each visit has its own number: work queued for one visit never
		-- runs in the next, however fast the vendor closes and reopens.
		self.visit = (self.visit or 0) + 1
		local visit = self.visit
		self.junkBuybackLimited = nil
		self.junkSelling = nil
		self.repairPending = nil
		-- Before the junk sale, so those items count as sold on this visit.
		self:NoteBuybackStart()
		-- Every vendor starts with the filters from the options, or the
		-- remembered ones, and an empty search.
		self:LoadFilters()
		if self.list then
			self.list.offset = 0
			self.list.search:SetText("")
		end
		self:Repair()
		if self.db.sellJunk and not E:StandsBack(self, "selljunk") then self:SellJunk() end
		self:RecordPrices()
		C_Timer.After(0.3, function()
			if self.visit ~= visit or not MerchantOpen() then return end
			self:UpdateButtons()
			self:UpdateList()
			-- Automatic offers always ask, whatever the confirm setting.
			local plan = NewPlan()
			if self.db.autoRestock then MergePlans(plan, self:RestockPlan()) end
			if self.db.autoAmmo then MergePlans(plan, self:AmmoPlan()) end
			self:Offer(plan, true)
		end)
	end)
	self:RegisterEvent("MERCHANT_UPDATE", function()
		self:UpdateButtons()
		self:UpdateList()
	end)
	self:WatchBags(MerchantOpen())
	self:RegisterEvent("PLAYER_REGEN_DISABLED", function() self:UpdateButtons() end)
	self:RegisterEvent("PLAYER_REGEN_ENABLED", function() self:UpdateButtons() end)
	self:RegisterEvent("MERCHANT_CLOSED", function()
		self:WatchBags(false)
		self.visit = (self.visit or 0) + 1
		self.attempted = {}
		self.junkSelling = nil
		self.repairPending = nil
		self.buybackBefore = nil
		if self.buybackButton then self.buybackButton:Hide() end
		if self.sellJunkButton then self.sellJunkButton:Hide() end
		self.pendingPlan, self.pendingPurchase, self.pendingQuantity = nil, nil, nil
		E:CancelConfirm("ELDOUI_MERCHANT_RESTOCK")
		E:CancelConfirm("ELDOUI_MERCHANT_BUY")
		E:CancelConfirm("ELDOUI_MERCHANT_QUANTITY")
		if self.list then self.list:Hide() end
	end)
	self:RegisterEvent("PLAYER_MONEY", function()
		if self.repairPending and MerchantOpen() then self:Repair() end
	end)
	-- Gamepad and mouse interface swap: EldoUI's buttons follow.
	self:RegisterEvent("INPUT_DEVICE_INTERFACE_TRANSITION", function()
		if not MerchantOpen() then return end
		self:UpdateButtons()
		self:UpdateList()
	end)
	E:OnBlizzardAddOn("Blizzard_UIPanels_Game", function() M:ApplyBlizzard() end)
end

function M:OnDisable()
	self.visit = (self.visit or 0) + 1
	self.attempted = {}
	self.junkSelling = nil
	RefreshJunkMarks()
	for _, event in ipairs({ "MERCHANT_SHOW", "MERCHANT_UPDATE", "BAG_UPDATE_DELAYED", "MERCHANT_CLOSED", "PLAYER_MONEY",
		"PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "INPUT_DEVICE_INTERFACE_TRANSITION" }) do
		self:UnregisterEvent(event)
	end
	self:RestoreBlizzard()
	if self.editor then self.editor:Hide() end
end

function M:OnProfileChanged()
	self.visit = (self.visit or 0) + 1
	self.attempted, self.junkSelling = {}, nil
	self:MigrateRestockString()
	RefreshJunkMarks()
	if not self.active then return end
	self:ApplyBlizzard()
	if self.list then
		E:SetPanelTemplate(self.list)
		if self.list:IsShown() then self:LayoutList() end
	end
	self:UpdateList()
	if self.editor and self.editor:IsShown() then self:UpdateEditor() end
end

E:AddCommand("restock", "open the restock list (items to keep in your bags)", function()
	if not M.active then
		E:Print(E:ModuleOffHint("Merchant"))
		return
	end
	M:ToggleEditor()
end, "Tools")

---------------------------------------------------------------------------
-- Options and styles
---------------------------------------------------------------------------
M.options = {
	{ type = "tab", label = "General" },
	{ type = "header", label = "General" },
	{ type = "select", key = "autoRepair", disabled = HandledBy("repair"), label = "Repair automatically at vendors",
		desc = "Acts for you when turned on: repairs all gear when you open a vendor who can repair, guild bank first if you choose it, then your own gold. Off until you pick it here or in the setup.",
		values = function()
			local values = { off = L["Off"], personal = L["Own gold"], guild = L["Guild bank, then own gold"] }
			-- Without a guild bank in the game, the guild choice stays only while it is the saved one.
			if E.NoGuildBank and E:NoGuildBank() and M.db.autoRepair ~= "guild" then values.guild = nil end
			return values
		end },
	{ type = "toggle", key = "waitForGold", label = "Repair once you can afford it",
		disabled = function() return M.db.autoRepair == "off" and L["Pick a repair mode first."] end,
		desc = "If your gold is short, the repair happens when you get the money while the vendor is still open." },
	{ type = "toggle", acts = true, key = "sellJunk", disabled = HandledBy("selljunk"), label = "Sell gray items at vendors",
		desc = "Acts for you when turned on: sells gray items and items on your Always sell list in batches of 12 at vendors. Retries refused sales if the sale limit is off. Off by default." },
	{ type = "toggle", key = "keepJunkBuyback", label = "Keep every sale undoable", dependsOn = "sellJunk",
		desc = "Limits automatic junk selling to one batch of up to 12 stacks per visit. Later sales can replace them in the buyback tab. The summary says how many junk items are left. Off by default." },
	{ type = "toggle", key = "summary", label = "Print what was earned and spent", desc = "One chat line: \"Sold 8 junk items and earned 1g 20s\", repairs and restocks." },
	{ type = "toggle", key = "buybackButton", label = "\"Buy back this visit\" button",
		desc = "Off by default. A \"Buy back (3)\" button under the vendor buys back everything you sold this visit, out of combat." },
	{ type = "toggle", key = "recordPrices", label = "Remember vendor prices",
		desc = "Saves what vendors charge for items, so the Auction House module can show crafting costs for reagents bought from vendors." },
	{ type = "description", label = "These change Blizzard's merchant window. Switch them on under Blizzard UI > Items, NPCs and economy > Merchant window.",
		hidden = function() return E:BlizzardAllowed("merchant", "improve") end },
	{ type = "execute", label = "Open Blizzard UI switches", desc = "Opens the Blizzard UI page, where you choose what EldoUI may change on the merchant window.",
		func = function() E:ToggleConfig("blizzard") end },

	{ type = "tab", label = "Junk" },
	{ type = "header", label = "Junk rules" },
	{ type = "select", key = "markJunk", label = "Mark junk",
		values = { off = "Off", ctrlalt = "Ctrl+Alt", ctrlshift = "Ctrl+Shift", altshift = "Alt+Shift" },
		order = { "off", "ctrlalt", "ctrlshift", "altshift" },
		desc = "Hold both modifiers and right-click an item in EldoUI bags or bank. Gray items toggle Never sell, other items toggle Always sell. Protected items stay unchanged." },
	{ type = "toggle", key = "junkButton", label = "Sell junk button",
		desc = "Show the junk count and value at a vendor. One click sells up to 12 stacks, with the same item protection as automatic selling. Requires Merchant Improve." },
	{ type = "description", label = "Sells gray items and your \"always sell\" list; never your \"never sell\" list, refundable items or items in an equipment set." },
	{ type = "toggle", key = "keepGreyGear", label = "Keep unbound gray gear", desc = "Gray weapons and armor that aren't bound stay in your bags, e.g. for transmog or selling to players." },
	{ type = "toggle", key = "protectItems", label = "Protect quest and recipe items",
		desc = "Junk selling skips items an open quest needs, items that start a quest you haven't done, and recipes one of your characters can still learn. On by default." },
	{ type = "input", key = "keepList", label = "Never sell", desc = "Item IDs, names or links, separated by commas. Protects a gray item from being sold." },
	{ type = "input", key = "sellList", label = "Always sell", desc = "Item IDs, names or links of non-gray items to sell as junk too, separated by commas. Empty by default." },

	{ type = "tab", label = "Restock" },
	{ type = "header", label = "Restock list" },
	{ type = "execute", label = "Edit the restock list", desc = "One row per item with the amount to keep in your bags. Type a name, ID or link, drop an item in, or Alt-click an item at a vendor. Also: /eui restock.",
		func = function() M:ToggleEditor() end },
	{ type = "description", label = "Restock buys what is missing up to your amount, never more. When a vendor sells in bigger lots, it buys fewer and says so." },
	{ type = "header", label = "Buying" },
	{ type = "toggle", key = "restockButton", label = "Restock button on the vendor window",
		desc = "A button at vendors that sell items on your list. It buys what's missing, after the confirm question." },
	{ type = "toggle", key = "autoRestock", label = "Offer to restock when a vendor opens",
		desc = "Asks to buy what's missing as soon as you open a vendor that sells it. Always asks first. Off by default." },
	{ type = "toggle", key = "altClickAdd", label = "Alt-click a vendor item to add it",
		desc = "Alt-click an item in the merchant window to put it on the restock list with one stack." },
	{ type = "toggle", key = "knownTint", label = "Tint items you already know",
		desc = "Recipes, mounts, pets and toys you already have get a green icon at vendors (needs \"Improve (extra info)\" for the merchant window under Blizzard UI)." },
	{ type = "toggle", key = "confirm", label = "Ask before buying", desc = "Shows every item with its amount and the total cost before anything is bought. Strongly recommended." },
	{ type = "toggle", key = "buyStacks", label = "Shift-click buys a full stack", desc = "Shift-click on a vendor item buys as many as one stack holds. Expensive stacks ask first." },
	{ type = "header", label = "Ammo (hunters)" },
	{ type = "toggle", key = "ammoButton", label = "Fill ammo button",
		desc = "At a vendor that sells your equipped ammo: fills your quiver or ammo pouch, after the confirm question." },
	{ type = "toggle", key = "autoAmmo", label = "Offer to fill ammo when a vendor opens",
		desc = "Asks to fill your quiver as soon as you open a vendor that sells your ammo. Off by default." },
	{ type = "range", key = "ammoAmount", label = "Ammo without a quiver", desc = "How much ammo to keep when you carry no quiver or ammo pouch. Never buys past this amount.", min = 200, max = 4000, step = 100 },

	{ type = "tab", label = "Item list" },
	{ type = "header", label = "Item list beside the window" },
	{ type = "toggle", key = "list", label = "Show every item beside the window", desc = "Everything the vendor sells, beside the merchant window, with search and filters: price, stock and upgrade arrows. Right-click buys one, Shift-click asks how many." },
	{ type = "select", key = "listLayout", label = "Layout", dependsOn = "list",
		desc = "Rows: a list as tall as the merchant window. Grid: tiles with icon, name and price, 2 to 6 across.",
		values = { rows = "Rows", grid = "Grid of tiles" } }, -- no-L: select values are translated by Core/Config.lua
	{ type = "select", key = "listColumns", label = "Columns", desc = "One or two columns of rows.", dependsOn = "list",
		values = { [1] = "One", [2] = "Two" }, hidden = function() return M.db.listLayout == "grid" end },
	{ type = "range", unit = "px", key = "listWidth", label = "Column width", desc = "Width of one column of rows in pixels.", dependsOn = "list",
		min = 220, max = 400, step = 10, hidden = function() return M.db.listLayout == "grid" end },
	{ type = "range", unit = "px", key = "listRowHeight", label = "Row height", desc = "Height of every row; the icon follows.", dependsOn = "list",
		min = 16, max = 34, step = 1, hidden = function() return M.db.listLayout == "grid" end },
	{ type = "toggle", key = "listZebra", label = "Striped rows", desc = "A faint tint on every other row.", dependsOn = "list",
		hidden = function() return M.db.listLayout == "grid" end },
	{ type = "range", key = "gridColumns", label = "Grid columns", desc = "How many tiles side by side.", dependsOn = "list",
		min = 2, max = 6, step = 1, hidden = function() return M.db.listLayout ~= "grid" end },
	{ type = "range", key = "gridRows", label = "Grid rows", desc = "How many lines of tiles before it scrolls. Columns times rows is how many items you see at once.", dependsOn = "list",
		min = 2, max = 12, step = 1, hidden = function() return M.db.listLayout ~= "grid" end },
	{ type = "range", unit = "px", key = "gridCellWidth", label = "Tile width", desc = "Width of one tile in pixels; long names wrap onto a second line.", dependsOn = "list",
		min = 100, max = 240, step = 10, hidden = function() return M.db.listLayout ~= "grid" end },
	{ type = "range", unit = "px", key = "gridIconSize", label = "Tile icon size", desc = "Size of the item icon; the tile height follows.", dependsOn = "list",
		min = 20, max = 48, step = 1, hidden = function() return M.db.listLayout ~= "grid" end },
	{ type = "range", key = "listFontSize", label = "Text size", desc = "Text size of names and prices.", dependsOn = "list", min = 9, max = 16, step = 1 },
	{ type = "select", key = "listMoney", label = "Prices as", desc = "How prices are written. \"Use general setting\" follows Fonts and text > Money.", dependsOn = "list",
		values = function() return E:MoneyStyleValues(true) end },

	{ type = "header", label = "Search and filters" },
	{ type = "select", key = "searchMode", label = "Items that don't match", dependsOn = "list",
		desc = "What happens to items that don't match the search box or the filters: left out of the list, or shown faded so you still see the whole vendor.",
		values = { hide = "Hide them", dim = "Show them faded" } }, -- no-L: select values are translated by Core/Config.lua
	{ type = "toggle", key = "filterBar", label = "Filter bar", dependsOn = "list",
		desc = "Category, slot and quality menus and the Usable, Affordable, In stock and Not known switches under the search box. Off: no filters apply, only the search." },
	{ type = "toggle", key = "rememberFilters", label = "Keep filters between vendors", dependsOn = "filterBar",
		desc = "On: the next vendor opens with the filters you used last. Off: every vendor opens with the filters below. A category or slot the vendor doesn't sell is ignored there." },
	{ type = "description", label = "Filters every vendor starts with (you can change them on the filter bar at any time):",
		hidden = function() return not M.db.filterBar or M.db.rememberFilters end },
	{ type = "select", key = "filterQuality", label = "Lowest quality", dependsOn = "filterBar",
		desc = "Items below this quality are left out (or faded) when a vendor opens.",
		disabled = function() return M.db.rememberFilters and L["Not used while filters are kept between vendors."] end,
		values = { [0] = "Any quality", [1] = "Common or better", [2] = "Uncommon or better", [3] = "Rare or better", [4] = "Epic or better" } }, -- no-L: select values are translated by Core/Config.lua
	{ type = "toggle", key = "filterUsable", label = "Usable only", dependsOn = "filterBar",
		desc = "Start with only items your character can use.",
		disabled = function() return M.db.rememberFilters and L["Not used while filters are kept between vendors."] end },
	{ type = "toggle", key = "filterAfford", label = "Affordable only", dependsOn = "filterBar",
		desc = "Start with only items you have the gold (and currency) for.",
		disabled = function() return M.db.rememberFilters and L["Not used while filters are kept between vendors."] end },
	{ type = "toggle", key = "filterStock", label = "In stock only", dependsOn = "filterBar",
		desc = "Start with sold-out limited items left out.",
		disabled = function() return M.db.rememberFilters and L["Not used while filters are kept between vendors."] end },
	{ type = "toggle", key = "filterKnown", label = "Hide what you already know", dependsOn = "filterBar",
		desc = "Start with recipes, mounts, pets and toys you already know left out.",
		disabled = function() return M.db.rememberFilters and L["Not used while filters are kept between vendors."] end },

	{ type = "tab", label = "Window" },
	{ type = "header", label = "Merchant window" },
	{ type = "execute", label = "Open Windows", testSafe = true,
		desc = "Blizzard's merchant window. Its size, dragging and resets are on the Move windows page; where it opens is its mover in move mode.",
		func = function() E:ToggleConfig("windows") end },
}

-- The helpers that act for the player, for the setup's Convenience step
-- and the Conveniences page (Core/Conveniences.lua). Each keeps its
-- default above: off until the player ticks it.
do
	local Rules = E.ConvenienceRules
	E:RegisterConvenience({ id = "repair", module = "Merchant", setting = "autoRepair", off = "off", order = 10,
		-- Own gold unless the player picks the guild bank (the setup's choice).
		value = function(pick) return pick and pick.repairMode == "guild" and "guild" or "personal" end,
		label = "Repair automatically at vendors",
		desc = "Acts for you: repairs all gear when you open a vendor who can repair.",
		suits = Rules.Everyone, blocked = HandledBy("repair") })
	E:RegisterConvenience({ id = "sellJunk", module = "Merchant", setting = "sellJunk", order = 20,
		label = "Sell gray items at vendors",
		desc = "Acts for you: sells gray items when you open a vendor, in batches of 12. Only the last 12 sold stacks stay in the buyback tab.",
		suits = Rules.Everyone, blocked = HandledBy("selljunk") })
	E:RegisterConvenience({ id = "autoRestock", module = "Merchant", setting = "autoRestock", order = 30,
		label = "Offer to restock when a vendor opens",
		desc = "Acts for you: asks to buy what your restock list is missing when you open a vendor who sells it, and buys only after you say yes.",
		suits = Rules.Reagents })
	-- Ammo is filled for hunters only (AmmoID).
	E:RegisterConvenience({ id = "autoAmmo", module = "Merchant", setting = "autoAmmo", order = 40,
		label = "Offer to fill ammo when a vendor opens",
		desc = "Acts for you: asks to fill your quiver or ammo pouch when you open a vendor who sells your ammo, and buys only after you say yes.",
		available = Rules.Class("HUNTER"), suits = Rules.Class("HUNTER") })
end

-- Rows whose feature lives on the merchant window need "Improve" there:
-- grayed with the reason while it is off (the rows under the item list
-- and the filter bar follow them).
do
	local NEEDS_IMPROVE = { buybackButton = true, restockButton = true, altClickAdd = true, knownTint = true,
		buyStacks = true, ammoButton = true, list = true }
	local byKey = {}
	for _, row in ipairs(M.options) do
		if type(row.key) == "string" then byKey[row.key] = row end
	end
	local function Needs(row)
		local seen = 0
		while row and seen < 8 do
			if NEEDS_IMPROVE[row.key] then return true end
			row = type(row.dependsOn) == "string" and byKey[row.dependsOn] or nil
			seen = seen + 1
		end
	end
	for _, row in ipairs(M.options) do
		if Needs(row) then
			local own = row.disabled
			if own ~= nil and type(own) ~= "function" then
				local value = own
				own = function() return value end
			end
			row.disabled = E:BlizzardNeeds("merchant", "improve", own)
		end
	end
end

E:RegisterStyles("Merchant", {
	{ key = "Standard", title = "Standard", desc = "One column of rows beside the window, coin icons.",
		settings = { list = true, listLayout = "rows", listColumns = 1, listWidth = 300, listRowHeight = 22, listFontSize = 12, listZebra = true } },
	{ key = "Grid", title = "Grid", desc = "Tiles four across and six down: 24 items at a glance.",
		settings = { list = true, listLayout = "grid", gridColumns = 4, gridRows = 6, gridCellWidth = 150, gridIconSize = 32, listFontSize = 12 } },
	{ key = "BigGrid", title = "Big grid", desc = "Tiles six across and eight down for big vendor lists, prices as short text.",
		settings = { list = true, listLayout = "grid", gridColumns = 6, gridRows = 8, gridCellWidth = 130, gridIconSize = 28, listFontSize = 11 } },
	{ key = "Compact", title = "Compact", desc = "Short rows and small text: more items without scrolling.",
		settings = { list = true, listLayout = "rows", listColumns = 1, listWidth = 260, listRowHeight = 18, listFontSize = 11, listZebra = true } },
	{ key = "Wide", title = "Two columns", desc = "Two columns of rows, for vendors with long lists.",
		settings = { list = true, listLayout = "rows", listColumns = 2, listWidth = 260, listRowHeight = 22, listFontSize = 12, listZebra = true } },
	{ key = "Ledger", title = "Ledger", desc = "Trader's ledger: prices as colored text, no stripes.",
		settings = { list = true, listLayout = "rows", listColumns = 1, listWidth = 300, listRowHeight = 20, listFontSize = 12, listZebra = false } },
	{ key = "Blizzard", title = "Window only", desc = "No item list: Blizzard's pages with EldoUI's buttons only.",
		settings = { list = false } },
})

---------------------------------------------------------------------------
-- Tour help: the item list, once the vendor has stayed open a moment
---------------------------------------------------------------------------
E.Tour:Register("merchant:list", {
	form = "spot", word = "merchant",
	offer = function(_, force)
		return E.Tour:Spot("merchant:list", {
			force = force, target = function() return M.list end,
			title = L["All items"],
			text = L["Everything this vendor sells, with a search and filters. Right-click an item to buy one lot, Shift-click to pick how many, Alt-click to put it on your restock list."],
		})
	end,
	replay = function(def) def.offer(def, true) end,
})

function M:OfferListHelp()
	C_Timer.After(1, function()
		if M.list and M.list:IsVisible() then E.Tour:Offer("merchant:list") end
	end)
end
