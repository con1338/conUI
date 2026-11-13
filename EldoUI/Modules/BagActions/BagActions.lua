-- EldoUI Bag Actions: hold a modifier (Alt by default) over an item
-- in your bags and click it to disenchant it, prospect or mill it, or pick
-- its lock. The same works on a lockbox in the trade window's "will not be
-- traded" slot, so a rogue can open someone else's box.
--
-- How it works: one secure action button (EldoUI_BagActionButton) is laid
-- over the item slot you hover while the modifier is down. Its attributes
-- (spell, target-bag, target-slot) and its place are set only out of
-- combat. Your click on it casts that one spell on that one item; nothing
-- repeats, chains or happens without the click. A state driver hides it in
-- secure code the moment combat starts or the modifier is released, so it
-- never lingers.
--
-- Only actions your character knows are offered (C_SpellBook), and only on
-- items they apply to: armor and weapons of a quality up to your cap for
-- Disenchanting (minus the items the game won't disenchant), "Prospectable"
-- and "Millable" stacks of five, and locked boxes your Lockpicking can open.
-- Items on your exclude list are never offered. WoW: Forever (Classic rules)
-- has Disenchanting and Pick Lock; Prospecting and Milling show only on a
-- client that has those spells.
--
-- Where: EldoUI's bag windows (Modules/Bags/Core.lua calls WatchSlot), Blizzard's
-- bag windows when Blizzard UI > Bags > Improve is on, and the trade window
-- when Blizzard UI > Trade window > Improve is on. Blizzard's buttons only
-- get HookScript hooks; every hook checks those switches each time it runs.
--
-- Behavior adapted from Molinari by Adrian L Lange (p3lim), MIT License
-- (see THIRD_PARTY_NOTICES.md and Modules/BagActions/Data.lua): the secure
-- overlay over the hovered slot, sized from the slot's scaled rectangle, and
-- the "/cast + ClickTargetTradeButton(7)" macro for the trade slot. Written
-- for EldoUI: own options, glow engine, exclude list and quality cap.
local _, E = ...
local L = E.L

local D = E.BagActionsData or {}

local M = E:NewModule("BagActions", {
	title = "Bag Actions",
	category = "Items & Economy",
	desc = "Hold a modifier key over an item in your bags and click it to disenchant, prospect, mill or pick its lock. One click casts one spell on one item.",
	frames = { "EldoUI_BagActionButton" },
	movers = {},
	blizzard = {},
	savedKeys = { "profile.modules.BagActions" },
	optionsPage = "module:BagActions",
	presets = { "Careful", "Enchanter", "Everything", "Lockpicker", "Standard" },
	reload = false,
	defaults = {
		enabled = false,   -- casts spells on the player's click: the player turns it on
		modifier = "alt",  -- alt | ctrl | shift
		disenchant = true,
		prospect = true,
		mill = true,
		pickLock = true,
		trade = true,      -- pick the lock in the trade window's "will not be traded" slot
		maxQuality = 3,    -- highest quality offered for Disenchanting (3 = rare)
		exclude = {},      -- [itemID] = true: never offered
		excludeAdd = "",   -- option input: an item to add
		excludeRemove = "", -- option select: an item to remove
	},
})
E.BagActions = M

M.BUTTON_NAME = "EldoUI_BagActionButton"
local TRADE_SLOT = 7 -- "will not be traded"

-- In check order: a locked box is never disenchanted.
M.ACTIONS = {
	{ key = "pickLock", spell = 1804, label = "Pick Lock" },
	{ key = "prospect", spell = 31252, label = "Prospecting", stack = 5, line = "ITEM_PROSPECTABLE" },
	{ key = "mill", spell = 51005, label = "Milling", stack = 5, line = "ITEM_MILLABLE" },
	{ key = "disenchant", spell = 13262, label = "Disenchanting" },
}
M.actionByKey = {}
for _, action in ipairs(M.ACTIONS) do M.actionByKey[action.key] = action end

local MODIFIERS = {
	alt = { label = "Alt", driver = "[mod:alt,nomod:ctrl,nomod:shift]" },
	ctrl = { label = "Ctrl", driver = "[mod:ctrl,nomod:alt,nomod:shift]" },
	shift = { label = "Shift", driver = "[mod:shift,nomod:alt,nomod:ctrl]" },
}

local watched = setmetatable({}, { __mode = "k" })     -- slot button -> "eldoui" | "blizzard" | "trade"
local hookedFrames = setmetatable({}, { __mode = "k" }) -- Blizzard container frame -> true

local hover    -- slot button under the mouse
local attached -- { owner, source, action, bag, slot, itemID } while the overlay is shown

---------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------
local Clean = E.Plain

local function Try(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a, b, c, d, e, f, g = pcall(fn, ...)
	if ok then return a, b, c, d, e, f, g end
end

local function InCombat()
	return InCombatLockdown and InCombatLockdown() or false
end

function M.SpellExists(spellID)
	local exists = C_Spell and C_Spell.DoesSpellExist
	if type(exists) ~= "function" then return true end
	return Clean(Try(exists, spellID)) and true or false
end

function M.SpellKnown(spellID)
	local book = C_SpellBook
	if book and book.IsSpellKnown then
		return Clean(Try(book.IsSpellKnown, spellID)) and true or false
	end
	local known = rawget(_G, "IsPlayerSpell")
	return Clean(Try(known, spellID)) and true or false
end

local function SpellName(action)
	local name = C_Spell and C_Spell.GetSpellName and Clean(Try(C_Spell.GetSpellName, action.spell))
	return type(name) == "string" and name ~= "" and name or L[action.label]
end
M.SpellName = SpellName

function M:ModifierDown()
	local alt, ctrl, shift = IsAltKeyDown(), IsControlKeyDown(), IsShiftKeyDown()
	local want = self.db and self.db.modifier or "alt"
	if want == "ctrl" then return ctrl and not alt and not shift end
	if want == "shift" then return shift and not alt and not ctrl end
	return alt and not ctrl and not shift
end

local function ModifierLabel()
	local mod = MODIFIERS[M.db and M.db.modifier] or MODIFIERS.alt
	return mod.label
end

-- Left texts of a tooltip's lines, as a set; nil when the client gives none.
local function LineSet(data)
	if type(data) ~= "table" or type(data.lines) ~= "table" then return nil end
	local set = {}
	for _, line in ipairs(data.lines) do
		local text = type(line) == "table" and Clean(line.leftText)
		if type(text) == "string" then set[text] = true end
	end
	return set
end

local function BagLines(bag, slot)
	local info = C_TooltipInfo
	return LineSet(info and info.GetBagItem and Try(info.GetBagItem, bag, slot))
end

local function TradeLines()
	local info = C_TooltipInfo
	return LineSet(info and info.GetTradeTargetItem and Try(info.GetTradeTargetItem, TRADE_SLOT))
end

local function HasLine(lines, globalName)
	local text = rawget(_G, globalName)
	return lines ~= nil and type(text) == "string" and lines[text] == true
end

local function ItemIDFromLink(link)
	link = Clean(link)
	return type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
end

---------------------------------------------------------------------------
-- What an item allows
---------------------------------------------------------------------------
local function Enabled(key)
	return M.db and M.db[key] and true or false
end

local function Offered(action)
	return Enabled(action.key) and M.SpellKnown(action.spell)
end

-- A lockbox the player's Lockpicking can open (Classic: level x 5).
local function CanPickLock(itemID, lines)
	local needed = D.lockboxes and D.lockboxes[itemID]
	if lines and not HasLine(lines, "LOCKED") then return false end -- already open
	if needed then
		local level = Clean(UnitLevel("player")) or 0
		return needed <= level * 5
	end
	return lines ~= nil and HasLine(lines, "LOCKED")
end
M.CanPickLock = CanPickLock

local CLASS_WEAPON = Enum and Enum.ItemClass and Enum.ItemClass.Weapon or 2
local CLASS_ARMOR = Enum and Enum.ItemClass and Enum.ItemClass.Armor or 4
local ARMOR_COSMETIC = Enum and Enum.ItemArmorSubclass and Enum.ItemArmorSubclass.Cosmetic or 5
local INVTYPE_BODY = Enum and Enum.InventoryType and Enum.InventoryType.IndexBodyType or 4

local function CanDisenchant(itemID, quality, lines)
	if D.noDisenchant and D.noDisenchant[itemID] then return false end
	quality = Clean(quality)
	if type(quality) ~= "number" or quality < 2 or quality > 4 then return false end
	if quality > (tonumber(M.db.maxQuality) or 3) then return false end
	local _, _, _, _, _, classID, subclassID = Try(C_Item.GetItemInfoInstant, itemID)
	classID, subclassID = Clean(classID), Clean(subclassID)
	if classID ~= CLASS_WEAPON and classID ~= CLASS_ARMOR then return false end
	if classID == CLASS_ARMOR and subclassID == ARMOR_COSMETIC then return false end
	local invType = C_Item.GetItemInventoryTypeByID and Clean(Try(C_Item.GetItemInventoryTypeByID, itemID))
	if invType == INVTYPE_BODY then return false end -- shirts
	if C_Item.IsCosmeticItem and Clean(Try(C_Item.IsCosmeticItem, itemID)) then return false end
	if HasLine(lines, "ITEM_DISENCHANT_NOT_DISENCHANTABLE") then return false end
	return true
end
M.CanDisenchant = CanDisenchant

-- The action for a bag slot, or nil. Returns action, itemID.
function M:ActionForBag(bag, slot)
	if type(bag) ~= "number" or type(slot) ~= "number" then return nil end
	local lastBag = rawget(_G, "NUM_TOTAL_EQUIPPED_BAG_SLOTS") or rawget(_G, "NUM_BAG_SLOTS") or 4
	if bag < 0 or bag > lastBag then return nil end -- bank and keyring: cast from the bags only
	local info = Try(C_Container.GetContainerItemInfo, bag, slot)
	if type(info) ~= "table" then return nil end
	local itemID = Clean(info.itemID)
	if not itemID or Clean(info.isLocked) then return nil end
	if self.db.exclude[itemID] then return nil end
	local lines = BagLines(bag, slot)
	local count = Clean(info.stackCount) or 1
	for _, action in ipairs(self.ACTIONS) do
		if Offered(action) then
			if action.key == "pickLock" then
				if CanPickLock(itemID, lines) then return action, itemID end
			elseif action.key == "disenchant" then
				if CanDisenchant(itemID, info.quality, lines) then return action, itemID end
			elseif HasLine(lines, action.line) and count >= action.stack then
				return action, itemID
			end
		end
	end
	return nil
end

-- Pick Lock on the trade partner's "will not be traded" slot.
function M:ActionForTrade()
	local action = self.actionByKey.pickLock
	if not (Enabled("trade") and Offered(action)) then return nil end
	local itemID = ItemIDFromLink(GetTradeTargetItemLink and Try(GetTradeTargetItemLink, TRADE_SLOT))
	if not itemID or self.db.exclude[itemID] then return nil end
	if CanPickLock(itemID, TradeLines()) then return action, itemID end
	return nil
end

---------------------------------------------------------------------------
-- Where the slot buttons come from, and whether they may be used now
---------------------------------------------------------------------------
local function SourceAllowed(source)
	if source == "eldoui" then
		local bags = E.modules.Bags
		return bags and bags.active and true or false
	elseif source == "blizzard" then
		return E:BlizzardAllowed("bags-containers", "improve") and not E:BlizzardHidden("bags-containers")
	elseif source == "trade" then
		return Enabled("trade") and E:BlizzardAllowed("trade", "improve")
	end
	return false
end
M.SourceAllowed = SourceAllowed

local function SlotOf(button)
	local bag = button.GetBagID and Clean(Try(button.GetBagID, button))
	if bag == nil then
		local parent = button:GetParent()
		bag = parent and Clean(parent:GetID())
	end
	return bag, Clean(button:GetID())
end

-- Something that stops the click from being ours (another window uses it).
local function Busy()
	local mail = rawget(_G, "SendMailFrame")
	if mail and mail:IsVisible() then return true end -- Alt-click attaches to mail
	local auction = rawget(_G, "AuctionHouseFrame") or rawget(_G, "AuctionFrame")
	if auction and auction:IsVisible() then return true end
	return false
end

---------------------------------------------------------------------------
-- The secure overlay
---------------------------------------------------------------------------
local function ClearAttributes(button)
	for _, mod in ipairs({ "alt", "ctrl", "shift" }) do button:SetAttribute(mod .. "-type1", nil) end
	button:SetAttribute("spell", nil)
	button:SetAttribute("macrotext", nil)
	button:SetAttribute("target-bag", nil)
	button:SetAttribute("target-slot", nil)
end

function M:Driver()
	local mod = MODIFIERS[self.db.modifier] or MODIFIERS.alt
	return "[combat] off; " .. mod.driver .. " on; off"
end

function M:ApplyDriver()
	local button = self.button
	if not button then return end
	E:RunOutOfCombat(function()
		if not M.button then return end
		if UnregisterStateDriver then UnregisterStateDriver(M.button, "bagaction") end
		if M.active and RegisterStateDriver then RegisterStateDriver(M.button, "bagaction", M:Driver()) end
	end)
end

local function ShowTooltip(button)
	local a = attached
	if not a then return end
	GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
	if a.source == "trade" then
		GameTooltip:SetTradeTargetItem(TRADE_SLOT)
	else
		GameTooltip:SetBagItem(a.bag, a.slot)
	end
	local c = E.media.accentColor
	GameTooltip:AddLine(" ")
	E:TooltipHint(GameTooltip, { L["%s-click"]:format(ModifierLabel()), SpellName(a.action) },
		{ L["%s-right-click"]:format(ModifierLabel()), L["never offer this item again"] })
	GameTooltip:Show()
end

function M:CreateButton()
	if self.button then return self.button end
	local button = CreateFrame("Button", self.BUTTON_NAME, UIParent, "SecureActionButtonTemplate, SecureHandlerStateTemplate")
	button:SetFrameStrata("TOOLTIP")
	-- Act on the release: with the game's "cast on key press" setting a
	-- secure button otherwise waits for a press it never receives.
	button:RegisterForClicks("AnyUp")
	button:SetAttribute("useOnKeyDown", false)
	button:Hide()
	-- Secure code: combat or a released modifier hides it at once.
	button:SetAttribute("_onstate-bagaction", [[
		if newstate == "off" and self:IsShown() then
			self:ClearAllPoints()
			self:Hide()
		end
	]])
	button:SetScript("OnEnter", ShowTooltip)
	button:SetScript("OnLeave", function()
		GameTooltip:Hide()
		hover = nil -- the slot below gets OnEnter again if the mouse is still on it
		M:Detach()
	end)
	-- Right-click (type2 is never set, so the secure part does nothing).
	button:HookScript("OnClick", function(_, mouse)
		if mouse == "RightButton" and attached and attached.itemID then
			M:SetExcluded(attached.itemID, true)
			M:Detach()
		end
	end)
	button:HookScript("OnHide", function(frame)
		E:HideGlow(frame)
		attached = nil
		E:RunOutOfCombat(function()
			if not M.button:IsShown() then ClearAttributes(M.button) end
		end)
	end)
	self.button = button
	return button
end

-- Lay the overlay over `owner` (screen rectangle, so scroll frames and
-- scaled windows don't matter) with the action's attributes.
function M:Attach(owner, source, action, itemID, bag, slot)
	if InCombat() then return false end
	local button = self:CreateButton()
	local left, bottom, width, height
	if owner.GetScaledRect then left, bottom, width, height = owner:GetScaledRect() end
	left, bottom, width, height = Clean(left), Clean(bottom), Clean(width), Clean(height)
	if not (left and bottom and width and height) or width <= 0 or height <= 0 then return false end
	local k = 1 / (UIParent:GetEffectiveScale() or 1)

	ClearAttributes(button)
	local prefix = (MODIFIERS[self.db.modifier] and self.db.modifier or "alt") .. "-"
	if source == "trade" then
		button:SetAttribute(prefix .. "type1", "macro")
		button:SetAttribute("macrotext", ("/cast %s\n/run ClickTargetTradeButton(%d)"):format(SpellName(action), TRADE_SLOT))
	else
		button:SetAttribute(prefix .. "type1", "spell")
		button:SetAttribute("spell", action.spell)
		button:SetAttribute("target-bag", bag)
		button:SetAttribute("target-slot", slot)
	end
	button:ClearAllPoints()
	button:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left * k, bottom * k)
	button:SetSize(width * k, height * k)
	attached = { owner = owner, source = source, action = action, itemID = itemID, bag = bag, slot = slot }
	button:Show()
	E:ShowUserGlow(button, "bagActions")
	if M.tourReplay or not E.Tour:Seen("bagactions:first") then
		E.Tour:Offer("bagactions:first", owner, action, M.tourReplay)
		M.tourReplay = nil
	end
	return true
end

-- Tour help: the first time an action is offered on an item, a callout
-- beside the item says what the click does. It is a plain frame next to
-- the slot: it only reads where the slot is and never changes the slot or
-- the secure button over it. It shows only right then, never later from
-- a queue.
E.Tour:Register("bagactions:first", {
	form = "spot", word = "bagactions",
	offer = function(_, owner, action, force)
		if not (owner and action) then return false end
		local modifier = ModifierLabel()
		return E.Tour:Spot("bagactions:first", {
			force = force, now = true, target = owner,
			title = L["Bag Actions"],
			text = L["%s-click casts %s on this item: one click, one cast, one item. %s-right-click never offers this item again."]
				:format(modifier, SpellName(action), modifier),
		})
	end,
	replay = function()
		if not M.active then
			E:Print(E:ModuleOffHint("BagActions"))
			return
		end
		-- It needs an item under the mouse: it shows on the next one.
		M.tourReplay = true
		E:Print(L["Hold %s over an item Bag Actions can use: the help shows there."]:format(ModifierLabel()))
	end,
})

function M:Detach()
	if not (self.button and self.button:IsShown()) then
		attached = nil
		return
	end
	if InCombat() then return end -- the state driver already hid it
	self.button:Hide()
	self.button:ClearAllPoints()
end

function M:Attached() return attached end

---------------------------------------------------------------------------
-- Hover tracking
---------------------------------------------------------------------------
function M:Evaluate()
	if not self.active or InCombat() then return end
	local owner = hover
	if not owner or not self:ModifierDown() or Busy() then
		self:Detach()
		return
	end
	local source = watched[owner]
	if not SourceAllowed(source) then
		self:Detach()
		return
	end
	local action, itemID, bag, slot
	if source == "trade" then
		action, itemID = self:ActionForTrade()
	else
		bag, slot = SlotOf(owner)
		action, itemID = self:ActionForBag(bag, slot)
	end
	if not action then
		self:Detach()
		return
	end
	local a = attached
	if a and a.owner == owner and a.action == action and a.itemID == itemID and a.bag == bag and a.slot == slot and self.button:IsShown() then
		return
	end
	self:Attach(owner, source, action, itemID, bag, slot)
end

local function OnSlotEnter(button)
	hover = button
	if M.active then M:Evaluate() end
end

local function OnSlotLeave(button)
	-- The overlay just covered this slot: it takes over until the mouse leaves it.
	if attached and attached.owner == button and M.button and M.button:IsShown() then return end
	if hover == button then hover = nil end
end

-- The bag window closed under the overlay: it goes too.
local function OnSlotHide(button)
	if hover == button then hover = nil end
	if attached and attached.owner == button then M:Detach() end
end

-- Hook a slot button once; `source` decides which switch it answers to.
function M:WatchSlot(button, source)
	if not button or watched[button] then return end
	watched[button] = source or "eldoui"
	button:HookScript("OnEnter", OnSlotEnter)
	button:HookScript("OnLeave", OnSlotLeave)
	button:HookScript("OnHide", OnSlotHide)
end

local function BlizzardBagFrames()
	local bags = E.modules.Bags
	if bags and bags.BlizzardBagFrames then return bags.BlizzardBagFrames() end
	local frames = {}
	if ContainerFrameCombinedBags then frames[#frames + 1] = ContainerFrameCombinedBags end
	for i = 1, (NUM_CONTAINER_FRAMES or 13) do
		local frame = _G["ContainerFrame" .. i]
		if frame then frames[#frames + 1] = frame end
	end
	return frames
end

local function WatchContainer(frame)
	if not (M.active and SourceAllowed("blizzard") and frame.EnumerateValidItems) then return end
	for _, button in frame:EnumerateValidItems() do
		if button then M:WatchSlot(button, "blizzard") end
	end
end

-- Blizzard's bag windows: only with Blizzard UI > Bags > Improve on.
function M:HookBlizzardBags()
	if not SourceAllowed("blizzard") then return end
	for _, frame in ipairs(BlizzardBagFrames()) do
		if not hookedFrames[frame] and frame.UpdateItems then
			hookedFrames[frame] = true
			hooksecurefunc(frame, "UpdateItems", WatchContainer)
		end
		WatchContainer(frame)
	end
end

-- The trade partner's "will not be traded" slot: only with Blizzard UI >
-- Trade window > Improve on.
function M:HookTrade()
	if not SourceAllowed("trade") then return end
	local button = _G["TradeRecipientItem" .. TRADE_SLOT .. "ItemButton"]
	if button then self:WatchSlot(button, "trade") end
end

---------------------------------------------------------------------------
-- Exclude list
---------------------------------------------------------------------------
local function ItemName(itemID)
	local name = C_Item.GetItemNameByID and Clean(Try(C_Item.GetItemNameByID, itemID))
	return type(name) == "string" and name or L["Item %d"]:format(itemID)
end

-- An item ID, an item link, or the name of an item the client knows.
function M.ParseItem(text)
	text = strtrim(tostring(text or ""))
	if text == "" then return nil end
	local id = tonumber(text) or tonumber(text:match("item:(%d+)"))
	if id then return id end
	return Clean(Try(C_Item.GetItemInfoInstant, text))
end

function M:SetExcluded(itemID, on)
	if type(itemID) ~= "number" then return end
	self.db.exclude[itemID] = on and true or nil
	if on then self:Print(L["%s will not be offered any more (Bag Actions options to undo)."]:format(ItemName(itemID))) end
end

function M:ApplyExcludeInput()
	local db = self.db
	local add = strtrim(tostring(db.excludeAdd or ""))
	if add ~= "" then
		local id = self.ParseItem(add)
		if id then
			db.exclude[id] = true
		else
			self:Print(L["%q is not an item ID, link or known item name."]:format(add))
		end
		db.excludeAdd = ""
	end
	local remove = tonumber(db.excludeRemove)
	if remove then db.exclude[remove] = nil end
	db.excludeRemove = ""
end

local function ExcludeValues()
	local values = {}
	for id in pairs(M.db.exclude) do values[id] = ItemName(id) end
	return values
end

---------------------------------------------------------------------------
-- Events and module life
---------------------------------------------------------------------------
local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_REGEN_DISABLED" then
		hover = nil
		if not InCombat() then M:Detach() end
	elseif event == "TRADE_SHOW" then
		M:HookTrade()
	elseif event == "TRADE_CLOSED" then
		if attached and attached.source == "trade" then M:Detach() end
	elseif event == "PLAYER_ENTERING_WORLD" then
		M:HookBlizzardBags()
	else -- MODIFIER_STATE_CHANGED, BAG_UPDATE_DELAYED, TRADE_TARGET_ITEM_CHANGED
		M:Evaluate()
	end
end)

M.refreshWhenOff = function(module) module:ApplyExcludeInput() end

function M:OnEnable()
	self:CreateButton()
	self:ApplyDriver()
	for _, event in ipairs({ "MODIFIER_STATE_CHANGED", "BAG_UPDATE_DELAYED", "PLAYER_REGEN_DISABLED", "PLAYER_ENTERING_WORLD",
		"TRADE_SHOW", "TRADE_CLOSED", "TRADE_TARGET_ITEM_CHANGED" }) do
		pcall(events.RegisterEvent, events, event)
	end
	self:HookBlizzardBags()
	self:HookTrade()
end

function M:OnDisable()
	events:UnregisterAllEvents()
	hover = nil
	self:Detach()
	self:ApplyDriver()
end

function M:OnProfileChanged()
	self:ApplyExcludeInput()
	if not self.active then return end
	self:ApplyDriver()
	self:HookBlizzardBags()
	self:HookTrade()
	if not InCombat() then
		self:Detach()
		self:Evaluate()
	end
end

---------------------------------------------------------------------------
-- Glow, options and styles
---------------------------------------------------------------------------
E:RegisterGlowUser("bagActions", {
	title = "Bag actions",
	desc = "The slot you can disenchant, prospect, mill or unlock while you hold the Bag Actions modifier.",
	order = 70,
	button = true,
	default = { style = "pixel", colorMode = "accent" },
})

local function ActionRow(key, label, desc)
	local action = M.actionByKey[key]
	return { type = "toggle", key = key, label = label, desc = desc,
		requires = function() return M.SpellExists(action.spell) end }
end

M.options = {
	{ type = "description", label = "Hold the modifier and point at an item: a glow shows when you can break or open it, and your click casts that spell on it. Not in combat." },
	{ type = "header", label = "Actions" },
	{ type = "select", key = "modifier", label = "Modifier key", values = { alt = "Alt", ctrl = "Ctrl", shift = "Shift" },
		desc = "Hold this key (and no other) over an item to get the action. Alt-click still attaches items while the mailbox is open." },
	ActionRow("disenchant", "Disenchant", E.Key("Armor and weapons up to the quality cap below. Needs Enchanting.")),
	ActionRow("prospect", E.Key("Prospect"), E.Key("Stacks of five ore marked Prospectable. Needs Jewelcrafting.")),
	ActionRow("mill", E.Key("Mill"), E.Key("Stacks of five herbs marked Millable. Needs Inscription.")),
	ActionRow("pickLock", E.Key("Pick lock"), E.Key("Locked boxes your Lockpicking skill can open. Rogues only.")),
	{ type = "toggle", key = "trade", label = "Pick locks in trades", dependsOn = "pickLock",
		requires = function() return M.SpellExists(1804) end,
		disabled = function()
			if not E:BlizzardAllowed("trade", "improve") then return L["Turn on Blizzard UI > Trade window > Improve first"] end
		end,
		desc = "Open a lockbox someone puts in the trade window's \"Will not be traded\" slot." },
	{ type = "select", key = "maxQuality", label = "Disenchant up to", dependsOn = "disenchant",
		requires = function() return M.SpellExists(13262) end,
		values = { [2] = "Uncommon (green)", [3] = "Rare (blue)", [4] = "Epic (purple)" },
		desc = "Better items than this never get the disenchant button, so a stray click can't destroy them." },
	{ type = "execute", label = "Glow style", desc = "Opens the Glows page, where the Bag actions glow gets its style and color.",
		func = function() E:ToggleConfig("glows") end },
	{ type = "header", label = "Never offer" },
	{ type = "description", label = "Items on this list never get an action. Modifier + right-click an item with a glow to add it, or type it here." },
	{ type = "input", key = "excludeAdd", label = "Add an item", desc = "Type an item ID or name, or paste an item link, and press Enter." },
	{ type = "select", key = "excludeRemove", label = "Remove", values = ExcludeValues,
		desc = "Pick an item to offer actions for it again.", hidden = function() return next(M.db.exclude) == nil end },
	{ type = "execute", label = "Clear the list", desc = "Every item can get an action again.", confirm = true,
		hidden = function() return next(M.db.exclude) == nil end,
		func = function()
			wipe(M.db.exclude)
			M:OnProfileChanged()
			E:RefreshConfig()
		end },
}

E:RegisterStyles("BagActions", {
	{ key = "Standard", title = "Standard", desc = "Alt, every action you know, disenchant up to rare.",
		settings = { modifier = "alt", disenchant = true, prospect = true, mill = true, pickLock = true, trade = true, maxQuality = 3 } },
	{ key = "Careful", title = "Careful", desc = "Ctrl, and only green items are disenchanted.",
		settings = { modifier = "ctrl", maxQuality = 2 } },
	{ key = "Everything", title = "Everything", desc = "Disenchant epics too.",
		settings = { maxQuality = 4 } },
	{ key = "Enchanter", title = "Enchanter", desc = "Only Disenchanting.",
		settings = { disenchant = true, prospect = false, mill = false, pickLock = false } },
	{ key = "Lockpicker", title = "Lockpicker", desc = "Only Pick Lock, in bags and trades.",
		settings = { disenchant = false, prospect = false, mill = false, pickLock = true, trade = true } },
})
