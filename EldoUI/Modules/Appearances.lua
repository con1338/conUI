-- EldoUI Appearances: whether you have an item's appearance, at a
-- glance. A small mark in a corner of item buttons (bags, vendor, loot,
-- loot rolls, mail), a tooltip line and the appearance progress of Loot
-- Guide sets.
--
--   known      the game says this item's appearance is in your collection
--   other      you have the look from another item, not from this one
--   unknown    not in your collection and you can collect it
--   notyours   your character can't collect it (class or armor type)
--
-- Every answer comes from the game (C_TransmogCollection): EldoUI reads,
-- caches until the collection changes and shows it. Nothing is guessed.
--
-- Probe (Forever 1.60.1): C_TransmogCollection.GetItemInfo,
-- GetAppearanceInfoBySource, PlayerCanCollectSource and
-- PlayerHasTransmogByItemInfo are in the client's API documentation and
-- Blizzard_Collections (the Wardrobe) loads on Forever. When the client
-- answers none of them the module shows nothing and says so in its options.
--
-- Where it hooks (no file of another module changes): E:SetUpgradeArrow
-- (EldoUI's bags, vendor rows and roll bars call it for each item button),
-- Blizzard's bag frames (UpdateItems), MerchantFrame_UpdateMerchantInfo,
-- GroupLootFrame1-4, EldoUI's loot window (Loot:ShowLoot), Blizzard's loot
-- window rows, the inbox, the open letter and EldoUI's auction rows and
-- Selling grid (Auction:RegisterItemRowHook).
local _, E = ...
local L = E.L


local M = E:NewModule("Appearances", {
	title = "Appearances",
	category = "Items & Economy",
	desc = "A mark on item buttons and a tooltip line that say whether you have an item's appearance, and set progress in the Loot Guide.",
	conflicts = { "CanIMogIt", "AllTheThings" },
	frames = {},
	movers = {},
	blizzard = {},
	savedKeys = { "profile.modules.Appearances" },
	optionsPage = "module:Appearances",
	presets = { "ColoredCorner", "ForeverBronze", "Icons", "Minimal", "TextBadge" },
	uiAmount = "moderate",
	reload = false,
	defaults = {
		enabled = true,
		bags = true,
		vendor = true,
		loot = true,
		mail = true,
		auction = true,
		tooltip = true,
		sets = true,
		showKnown = false,
		showOther = true,
		showUnknown = true,
		hideNotYours = true,
		look = "icon",        -- icon | corner | text
		corner = "TOPRIGHT",
		size = 14,
	},
})
E.Appearances = M

local Clean = E.Plain

local function Try(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a, b = pcall(fn, ...)
	if ok then return a, b end
end

local function API()
	return rawget(_G, "C_TransmogCollection")
end

-- Does this client answer appearance questions at all?
function M:Supported()
	local api = API()
	return type(api) == "table" and (type(api.GetItemInfo) == "function" or type(api.PlayerHasTransmogByItemInfo) == "function")
end

---------------------------------------------------------------------------
-- The answer for one item (link or ID), cached until the collection changes
---------------------------------------------------------------------------
local cache = {}
local NONE = {}

local function Read(item)
	local api = API()
	if not api then return nil end
	local _, sourceID = Try(api.GetItemInfo, item)
	sourceID = Clean(sourceID)
	if type(sourceID) == "number" then
		local info = Clean(Try(api.GetAppearanceInfoBySource, sourceID))
		local hasData, canCollect = Try(api.PlayerCanCollectSource, sourceID)
		hasData, canCollect = Clean(hasData), Clean(canCollect)
		if type(info) == "table" then
			if Clean(info.sourceIsCollected) then return "known", true end
			if Clean(info.appearanceIsCollected) then return "other", true end
		elseif Clean(Try(api.PlayerKnowsSource, sourceID)) then
			return "known", true
		end
		if hasData == false then return "unknown", false end -- item data not loaded yet: ask again
		if canCollect == false then return "notyours", true end
		return "unknown", true
	end
	-- Fallback: the yes/no answer for the item.
	local has = Clean(Try(api.PlayerHasTransmogByItemInfo, item))
	if has == true then return "known", true end
	if has == false and sourceID ~= nil then return "unknown", true end
	return nil, sourceID == nil
end

-- "known" | "other" | "unknown" | "notyours" | nil (no appearance).
function M:State(item)
	item = Clean(item)
	if item == nil or item == "" then return nil end
	local caching = self.active == true
	local key = type(item) == "string" and (item:match("|H(item:[^|]+)|h") or item) or item
	local hit = caching and cache[key]
	if hit then return hit ~= NONE and hit or nil end
	local ok, state, final = pcall(Read, item)
	if not ok then return nil end
	if caching and self.active == true and final then cache[key] = state or NONE end
	return state
end

function M:ClearCache()
	wipe(cache)
end

-- Whether a state gets a mark with the current options.
function M:Shows(state)
	if state == "known" then return self.db.showKnown end
	if state == "other" then return self.db.showOther end
	if state == "unknown" then return self.db.showUnknown end
	if state == "notyours" then return not self.db.hideNotYours end
	return false
end

---------------------------------------------------------------------------
-- The mark
---------------------------------------------------------------------------
local marks = setmetatable({}, { __mode = "k" })

local STATE_COLOR = {
	known = function() return E.tokens.text.good end,
	other = function() return E.tokens.text.warn end,
	unknown = function() return E.media.accentColor end,
	notyours = function() return E.tokens.text.dim end,
}
-- The game's ready-check marks: check, question mark, cross.
local STATE_TEXTURE = {
	known = rawget(_G, "READY_CHECK_READY_TEXTURE") or "Interface\\RaidFrame\\ReadyCheck-Ready",
	other = rawget(_G, "READY_CHECK_WAITING_TEXTURE") or "Interface\\RaidFrame\\ReadyCheck-Waiting",
	unknown = rawget(_G, "READY_CHECK_NOT_READY_TEXTURE") or "Interface\\RaidFrame\\ReadyCheck-NotReady",
}
local STATE_TEXT = {
	known = "Have",
	other = "Look",
	unknown = "New",
	notyours = "-",
}

local function IconRegion(button)
	local name = button.GetName and button:GetName()
	return button.icon or button.Icon or (name and (rawget(_G, name .. "IconTexture") or rawget(_G, name .. "Icon"))) or button
end

local function Mark(button)
	local mark = marks[button]
	if mark then return mark end
	mark = CreateFrame("Frame", nil, button)
	mark:SetAllPoints(IconRegion(button))
	mark:SetFrameLevel(button:GetFrameLevel() + 4)
	mark.icon = mark:CreateTexture(nil, "OVERLAY")
	mark.corner = mark:CreateTexture(nil, "OVERLAY")
	mark.text = E:CreateText(mark, E.tokens.size.tiny, "CENTER")
	mark.text:SetShadowOffset(1, -1)
	marks[button] = mark
	return mark
end

local function Hide(button)
	local mark = marks[button]
	if mark then mark:Hide() end
end

-- Show the mark for `item` on `button` (nil hides it). place: the option key.
function M:Apply(button, item, place)
	if not button then return end
	if not (self.active and (not place or self.db[place])) then return Hide(button) end
	local state = item and self:State(item)
	if not (state and self:Shows(state)) then return Hide(button) end
	local mark = Mark(button)
	local db = self.db
	local color = STATE_COLOR[state]()
	local point = db.corner
	mark.icon:Hide()
	mark.corner:Hide()
	mark.text:Hide()
	if db.look == "icon" and STATE_TEXTURE[state] then
		mark.icon:ClearAllPoints()
		mark.icon:SetPoint(point, mark, point, 0, 0)
		mark.icon:SetSize(db.size, db.size)
		mark.icon:SetTexture(STATE_TEXTURE[state])
		mark.icon:Show()
	elseif db.look == "corner" or (db.look == "icon" and not STATE_TEXTURE[state]) then
		mark.corner:ClearAllPoints()
		mark.corner:SetPoint(point, mark, point, 0, 0)
		mark.corner:SetSize(math.floor(db.size * 0.6), math.floor(db.size * 0.6))
		mark.corner:SetColorTexture(color[1], color[2], color[3], 0.9)
		mark.corner:Show()
	else
		mark.text:ClearAllPoints()
		mark.text:SetPoint(point, mark, point, point:find("LEFT") and 1 or -1, point:find("TOP") and -1 or 1)
		E:SetFont(mark.text, math.max(8, math.floor(db.size * 0.7)))
		mark.text:SetText(L[STATE_TEXT[state]])
		mark.text:SetTextColor(color[1], color[2], color[3])
		mark.text:Show()
	end
	mark.state = state
	mark:Show()
	return state
end

function M:HideAll()
	for _, mark in pairs(marks) do mark:Hide() end
end

---------------------------------------------------------------------------
-- Places
---------------------------------------------------------------------------
-- EldoUI's own buttons through E:SetUpgradeArrow: which place a button is.
local KIND_PLACE = { bags = "bags", merchant = "vendor", rolls = "loot" }

local function PlaceOf(button, opts)
	if opts and opts.kind then return KIND_PLACE[opts.kind] or false end
	local frame, depth = button, 0
	while frame and depth < 8 do
		local name = frame.GetName and frame:GetName()
		if type(name) == "string" then
			if name:find("Bag") or name:find("Bank") then return "bags" end
			if name:find("Merchant") then return "vendor" end
			if name:find("Loot") then return "loot" end
		end
		if rawget(frame, "rollID") ~= nil or rawget(frame, "buttons") ~= nil and rawget(frame, "timer") ~= nil then return "loot" end
		frame = frame.GetParent and frame:GetParent()
		depth = depth + 1
	end
	return false
end

local function OnUpgradeArrow(_, button, link, opts)
	if not M.active or not button then return end
	local place = PlaceOf(button, opts)
	if place == false then return end
	M:Apply(button, link, place)
end

-- Blizzard's bag frames
local function UpdateContainer(frame)
	if not (M.active and frame and frame:IsShown()) then return end
	local function Update(button)
		local ok, bag = pcall(button.GetBagID, button)
		local link = ok and bag and Try(C_Container.GetContainerItemLink, bag, button:GetID())
		M:Apply(button, link, "bags")
	end
	if frame.EnumerateValidItems then
		for _, button in frame:EnumerateValidItems() do Update(button) end
	elseif frame.Items then
		for _, button in ipairs(frame.Items) do Update(button) end
	end
end

local function BlizzardBags()
	local frames = {}
	local combined = rawget(_G, "ContainerFrameCombinedBags")
	if combined then frames[#frames + 1] = combined end
	for index = 1, (rawget(_G, "NUM_TOTAL_BAG_FRAMES") or 13) do
		local frame = rawget(_G, "ContainerFrame" .. index)
		if frame then frames[#frames + 1] = frame end
	end
	return frames
end

-- Blizzard's vendor
local function UpdateMerchant()
	local frame = rawget(_G, "MerchantFrame")
	if not (M.active and frame and frame:IsShown()) then return end
	local perPage = rawget(_G, "MERCHANT_ITEMS_PER_PAGE") or 10
	local buyback = frame.selectedTab == 2
	for index = 1, perPage do
		local button = rawget(_G, "MerchantItem" .. index .. "ItemButton")
		if button then
			local item = ((frame.page or 1) - 1) * perPage + index
			local link = not buyback and item <= (tonumber(Clean(Try(GetMerchantNumItems))) or 0) and Try(GetMerchantItemLink, item) or nil
			M:Apply(button, link, "vendor")
		end
	end
end

-- Blizzard's roll frames
local function UpdateRoll(frame)
	if not M.active then return end
	local rollID = frame and frame.rollID
	local link = rollID and Try(GetLootRollItemLink, rollID)
	M:Apply(frame.IconFrame or frame.Icon or frame, link, "loot")
end

-- EldoUI's loot window
local function UpdateEldoLoot()
	local loot = E.modules.Loot
	local frame = loot and loot.lootFrame
	if not (M.active and frame) then return end
	for _, row in ipairs(frame.rows or {}) do
		if row.iconBox then M:Apply(row.iconBox, row.slot and Try(GetLootSlotLink, row.slot), "loot") end
	end
end

-- Blizzard's loot window rows
local function UpdateLootRow(row)
	if not (M.active and row) then return end
	local slot = row.GetSlotIndex and Try(row.GetSlotIndex, row)
	local button = row.Item or row
	M:Apply(button, slot and Try(GetLootSlotLink, slot), "loot")
end

-- Mail: the inbox list and the open letter
local function UpdateInbox()
	local inbox = rawget(_G, "InboxFrame")
	if not (M.active and inbox) then return end
	local perPage = rawget(_G, "INBOXITEMS_TO_DISPLAY") or 7
	for index = 1, perPage do
		local item = rawget(_G, "MailItem" .. index)
		local button = item and (item.Button or rawget(_G, "MailItem" .. index .. "Button"))
		if button then
			local mail = ((inbox.pageNum or 1) - 1) * perPage + index
			M:Apply(button, Try(GetInboxItemLink, mail, 1), "mail")
		end
	end
end

local function UpdateOpenMail()
	local inbox = rawget(_G, "InboxFrame")
	local open = rawget(_G, "OpenMailFrame")
	local id = (open and open.openMailID) or (inbox and inbox.openMailID)
	if not M.active then return end
	for index = 1, rawget(_G, "ATTACHMENTS_MAX_RECEIVE") or 16 do
		local button = rawget(_G, "OpenMailAttachmentButton" .. index)
		if button then M:Apply(button, id and Try(GetInboxItemLink, id, index), "mail") end
	end
end

-- The place updaters (they take any frames, plugins too).
M.places = { arrow = OnUpgradeArrow, container = UpdateContainer, merchant = UpdateMerchant, roll = UpdateRoll,
	eldoLoot = UpdateEldoLoot, lootRow = UpdateLootRow, inbox = UpdateInbox, openMail = UpdateOpenMail }

---------------------------------------------------------------------------
-- Tooltip line
---------------------------------------------------------------------------
local TOOLTIP_TEXT = {
	known = E.Key("collected"),
	other = E.Key("collected (from another item)"),
	unknown = E.Key("not collected"),
	notyours = E.Key("your character can't collect it"),
}

local function TooltipLine(_, link, itemID, add)
	if not (M.active and M.db.tooltip) then return end
	local state = M:State(Clean(link) or Clean(itemID))
	if not state then return end
	local s = E.tokens.text.secondary
	local c = STATE_COLOR[state]()
	add(L["Appearance"], L[TOOLTIP_TEXT[state]], s[1], s[2], s[3], c[1], c[2], c[3])
end
M.TooltipLine = TooltipLine

---------------------------------------------------------------------------
-- Loot Guide sets: "3/8 looks" after each set, the mark on each piece
---------------------------------------------------------------------------
function M:SetProgress(set)
	if not (set and type(set.pieces) == "table") then return nil end
	local have, total = 0, 0
	for _, itemID in ipairs(set.pieces) do
		local state = self:State(itemID)
		if state then
			total = total + 1
			if state == "known" or state == "other" then have = have + 1 end
		end
	end
	if total == 0 then return nil end
	return have, total
end

local function SetLineExtra(set)
	if not (M.active and M.db.sets) then return nil end
	local have, total = M:SetProgress(set)
	if not have then return nil end
	local color = have == total and E.tokens.text.good or E.tokens.text.secondary
	return E:TokenHex(color) .. (L["%d/%d looks"]):format(have, total) .. "|r"
end
M.SetLineExtra = SetLineExtra

local function MarkCell(cell, data)
	if not (cell and cell.iconBox) then return end
	if not (M.active and M.db.sets and data and data.itemID) then return Hide(cell.iconBox) end
	M:Apply(cell.iconBox, tonumber(data.itemID), nil)
end

---------------------------------------------------------------------------
-- Hooks and refresh
---------------------------------------------------------------------------
local hooked = {}

local function Hook(key, fn)
	if hooked[key] then return end
	local ok = pcall(fn)
	hooked[key] = ok
end

function M:InstallHooks()
	if type(E.SetUpgradeArrow) == "function" then
		Hook("arrow", function() hooksecurefunc(E, "SetUpgradeArrow", OnUpgradeArrow) end)
	end
	for _, frame in ipairs(BlizzardBags()) do
		if frame.UpdateItems and not hooked[frame] then
			hooked[frame] = pcall(hooksecurefunc, frame, "UpdateItems", UpdateContainer)
		end
	end
	if rawget(_G, "MerchantFrame_UpdateMerchantInfo") then
		Hook("merchant", function() hooksecurefunc("MerchantFrame_UpdateMerchantInfo", UpdateMerchant) end)
	end
	for index = 1, 4 do -- GroupLootFrame1-4
		local frame = rawget(_G, "GroupLootFrame" .. index)
		if frame and not hooked[frame] then
			hooked[frame] = pcall(frame.HookScript, frame, "OnShow", UpdateRoll)
		end
	end
	local loot = E.modules.Loot
	if loot and type(loot.ShowLoot) == "function" then
		Hook("eldoLoot", function()
			hooksecurefunc(loot, "ShowLoot", UpdateEldoLoot)
			hooksecurefunc(loot, "UpdateLootSlot", UpdateEldoLoot)
		end)
	end
	local lootFrame = rawget(_G, "LootFrame")
	if lootFrame and lootFrame.ScrollBox and E.HookScrollBoxRows then
		Hook("blizzLoot", function() E:HookScrollBoxRows(lootFrame.ScrollBox, UpdateLootRow) end)
	end
	local inbox = rawget(_G, "InboxFrame")
	if inbox and type(inbox.Update) == "function" then
		Hook("inbox", function() hooksecurefunc(inbox, "Update", UpdateInbox) end)
	end
	local open = rawget(_G, "OpenMailFrame")
	if open and type(open.Update) == "function" then
		Hook("openMail", function() hooksecurefunc(open, "Update", UpdateOpenMail) end)
	end
	-- EldoUI's auction house rows and Selling grid (Modules/Auction.lua).
	local auction = E.modules.Auction
	if auction and type(auction.RegisterItemRowHook) == "function" and not hooked.auction then
		hooked.auction = true
		auction:RegisterItemRowHook("appearances", function(holder, item) M:Apply(holder, item, "auction") end)
	end
	local LG = E.LootGuide
	if LG then
		LG.setLineExtras = LG.setLineExtras or {}
		if not hooked.setLine then
			hooked.setLine = true
			table.insert(LG.setLineExtras, SetLineExtra)
		end
		if LG.PageKit and type(LG.PageKit.SetItem) == "function" then
			Hook("lgCell", function() hooksecurefunc(LG.PageKit, "SetItem", MarkCell) end)
		end
	end
end

-- Redraw every place that is open now.
function M:Refresh()
	self:ClearCache()
	if not self.active then
		self:HideAll()
		return
	end
	for _, mark in pairs(marks) do mark:Hide() end
	for _, frame in ipairs(BlizzardBags()) do UpdateContainer(frame) end
	UpdateMerchant()
	for index = 1, 4 do
		local frame = rawget(_G, "GroupLootFrame" .. index)
		if frame and frame:IsShown() then UpdateRoll(frame) end
	end
	UpdateEldoLoot()
	UpdateInbox()
	UpdateOpenMail()
	local auction = E.modules.Auction
	if auction and auction.active and auction.RefreshItemRows then pcall(auction.RefreshItemRows, auction) end
	-- EldoUI's bags, vendor and roll bars redraw their own buttons.
	local upgrades = E.modules.Upgrades
	if upgrades and upgrades.active and upgrades.RefreshIcons then pcall(upgrades.RefreshIcons, upgrades) end
	local bags = E.modules.Bags
	if bags and bags.active and bags.RefreshViews then pcall(bags.RefreshViews, bags) end
	local merchant = E.modules.Merchant
	local merchantFrame = rawget(_G, "MerchantFrame")
	if merchant and merchant.active and merchant.UpdateList and merchantFrame and merchantFrame:IsShown() then
		pcall(merchant.UpdateList, merchant)
	end
end

local EVENTS = { "TRANSMOG_COLLECTION_UPDATED", "TRANSMOG_COLLECTION_SOURCE_ADDED", "TRANSMOG_COLLECTION_SOURCE_REMOVED",
	"GET_ITEM_INFO_RECEIVED" }

local function OnEvent(_, event)
	if not M.active then return end
	if event == "GET_ITEM_INFO_RECEIVED" then
		-- Answers that waited for item data come in on the next redraw.
		return
	end
	M:ClearCache()
	if M.pending then return end
	M.pending = true
	C_Timer.After(0.3, function()
		M.pending = nil
		if M.active then M:Refresh() end
	end)
end

function M:OnInitialize()
	if E.RegisterTooltipSection then
		E:RegisterTooltipSection("appearance", { order = 44, title = "Appearance", default = "always",
			desc = "Whether you have the item's appearance: collected, collected from another item, not collected, or not for your character.",
			item = TooltipLine })
	end
end

function M:OnEnable()
	if not self:Supported() then return end
	for _, event in ipairs(EVENTS) do E:RegisterEvent(event, OnEvent, "Appearances") end
	self:InstallHooks()
	self:Refresh()
end

function M:OnDisable()
	for _, event in ipairs(EVENTS) do E:UnregisterEvent(event, "Appearances") end
	self:ClearCache()
	self:HideAll()
end

function M:OnProfileChanged()
	if not self.active then return end
	self:Refresh()
end

---------------------------------------------------------------------------
-- Options and styles
---------------------------------------------------------------------------
local API_PATH = "C_TransmogCollection.GetItemInfo"

M.options = {
	{ type = "description", label = "Marks item buttons with whether you have the item's appearance. The game gives every answer; EldoUI only shows it.",
		requiresAPI = API_PATH },
	{ type = "description", label = "This client does not report appearance collections, so there is nothing to show.",
		requires = function() return not M:Supported() end },
	{ type = "header", label = "Where", requiresAPI = API_PATH },
	{ type = "toggle", key = "bags", label = "Bags and bank", requiresAPI = API_PATH, desc = "Marks items in your bags and bank (EldoUI's and Blizzard's)." },
	{ type = "toggle", key = "vendor", label = "Vendors", requiresAPI = API_PATH, desc = "Marks the items a vendor sells." },
	{ type = "toggle", key = "loot", label = "Loot and rolls", requiresAPI = API_PATH, desc = "Marks items in the loot window and on loot rolls." },
	{ type = "toggle", key = "auction", label = "Auction house", requiresAPI = API_PATH, desc = "Marks the items in EldoUI's Shopping, Selling and Canceling lists at the auction house." },
	{ type = "toggle", key = "mail", label = "Mail", requiresAPI = API_PATH, desc = "Marks the first item of each letter in the inbox and the items of an open letter." },
	{ type = "toggle", key = "tooltip", label = "Tooltip line", requiresAPI = API_PATH, desc = "Adds \"Appearance: collected / not collected\" to item tooltips, also at the auction house." },
	{ type = "toggle", key = "sets", label = "Loot Guide", requiresAPI = API_PATH, desc = "Shows how many looks of each set you have on the Loot Guide's Sets page, and marks the items in Loot Guide lists." },
	{ type = "header", label = "What", requiresAPI = API_PATH },
	{ type = "toggle", key = "showUnknown", label = "Not collected", requiresAPI = API_PATH, desc = "Marks items whose appearance you don't have yet and can collect." },
	{ type = "toggle", key = "showOther", label = "From another item", requiresAPI = API_PATH, desc = "Marks items whose look you already have from another item." },
	{ type = "toggle", key = "showKnown", label = "Collected", requiresAPI = API_PATH, desc = "Marks items whose appearance is in your collection." },
	{ type = "toggle", key = "hideNotYours", label = "Hide what you can't collect", requiresAPI = API_PATH, desc = "No mark on items your character can't collect (class or armor type). Off: they get a gray mark." },
	{ type = "tab", label = "Look", requiresAPI = API_PATH },
	{ type = "select", key = "look", label = "Mark", order = { "icon", "corner", "text" }, requiresAPI = API_PATH,
		values = { icon = "Icon", corner = "Colored corner", text = "Text badge" }, -- no-L (option values, Config.lua translates them)
		desc = "How the mark looks: a check, a question mark or a cross; a small colored square; or a short word (New, Look, Have)." },
	{ type = "select", key = "corner", label = "Corner", order = { "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }, requiresAPI = API_PATH,
		values = { TOPLEFT = "Top left", TOPRIGHT = "Top right", BOTTOMLEFT = "Bottom left", BOTTOMRIGHT = "Bottom right" },
		desc = "The corner of the item button the mark sits in. The upgrade arrow uses the top left." },
	{ type = "range", key = "size", label = "Size", min = 8, max = 24, step = 1, requiresAPI = API_PATH, desc = "Size of the mark." },
}

E:RegisterStyles("Appearances", {
	{ key = "Icons", title = "Icons", desc = "A small check, question mark or cross in the top right corner.",
		settings = { look = "icon", corner = "TOPRIGHT", size = 14 } },
	{ key = "ColoredCorner", title = "Colored corner", desc = "A small colored square in the top right corner.",
		settings = { look = "corner", corner = "TOPRIGHT", size = 14 } },
	{ key = "TextBadge", title = "Text badge", desc = "A short word at the bottom: New, Look or Have.",
		settings = { look = "text", corner = "BOTTOMLEFT", size = 14 } },
	{ key = "ForeverBronze", title = "Forever bronze", desc = "Large icons, every state marked, for the WoW Forever look.",
		settings = { look = "icon", corner = "TOPRIGHT", size = 16, showKnown = true } },
	{ key = "Minimal", title = "Minimal", desc = "Only what you don't have yet, as a small corner.",
		settings = { look = "corner", corner = "TOPRIGHT", size = 10, showOther = false, showKnown = false } },
})
