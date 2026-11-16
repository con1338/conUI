-- EldoUI Quality of Life: an early hint when your bags are almost full
-- (Sound and misc tab, on by default; review verbesserungen.md, B7).
--
-- When the free slots of your ordinary bags drop to the limit (3 by
-- default), one card comes up: how many are left, and under it "Make
-- room", the five cheapest things you carry, gray items first. A click on
-- one puts it on your cursor; a click outside your bags then brings up
-- the game's own "Destroy this item?" question, and dropped on an open
-- vendor window it is sold. EldoUI never deletes, sells or moves an item
-- itself, and never opens a Blizzard dialog from its own code.
--
-- When it comes: once each time the free slots drop to the limit or below;
-- again only after more than the limit were free once more. Not at login
-- or after a loading screen: the bags you have then are where it starts,
-- and for a few seconds the bags may still be loading. Never in combat: a
-- drop in combat shows its card when combat ends, if the bags are still
-- that full. While the card shows or waits for its turn it follows the
-- bags, and it goes away once more than the limit is free. /eui room and
-- "Show now" bring the same list any time (titled "Make room"); that card
-- also follows the bags but stays until it times out or is closed.
--
-- What "Make room" leaves out: items one of your quests or a recipe one of
-- your characters can learn needs (Core/ItemProtect.lua), items without a
-- vendor price, locked items, items in an equipment set, purchases you
-- can still return, the Merchant's "never sell" list, and food, drink and
-- potions, reagents, ammo, quivers, keys and recipes, which a vendor price
-- tells little about. Only ordinary bags count: a profession bag or a
-- quiver has its own space.
--
-- Rules (Midnight / Forever): only the bags and item data, read through
-- the shared bag cache and in pcall; a secret value counts as not there.
-- Picking an item up is the player's click; the game's own dialog does the
-- rest.
-- Written from scratch for EldoUI.
local _, E = ...
local L = E.L

local M = E:GetModule("QoL")

M.defaults.bagSpace = true
M.defaults.bagSpaceFree = 3          -- free slots that bring the card
M.defaults.bagSpaceSound = "none"    -- media id, "none" for silence

-- Minimal keeps the game as Blizzard made it (Modules/QoL.lua, "Minimal").
for _, style in ipairs(E.styles and E.styles.QoL or {}) do
	if style.key == "Minimal" and type(style.settings) == "table" then style.settings.bagSpace = false end
end

local Plain, PlainCall, PlainEach = E.Plain, E.PlainCall, E.PlainCallEach
local OWNER = "QoL:BagSpace" -- its own event owner: Tweaks already has the module's PLAYER_REGEN_ENABLED
local KEY = "QoL:bagSpace"   -- the card's key: a new card replaces the one on screen or waiting
local SHOWN = 5
local DURATION = 30
local SETTLE = 5             -- seconds after login or a loading screen before a drop counts
local ICON = "Interface\\Icons\\INV_Misc_Bag_08"

-- Item classes a vendor price tells little about (Enum.ItemClass).
local ITEM_CLASS = rawget(_G, "Enum") and Enum.ItemClass or {}
local SKIP_CLASS = {}
for _, id in ipairs({ ITEM_CLASS.Consumable or 0, ITEM_CLASS.Reagent or 5, ITEM_CLASS.Projectile or 6,
	ITEM_CLASS.Recipe or 9, ITEM_CLASS.Quiver or 11, ITEM_CLASS.Questitem or 12, ITEM_CLASS.Key or 13 }) do
	SKIP_CLASS[id] = true
end
M.BAG_SPACE_SKIP_CLASS = SKIP_CLASS

local function Limit() return tonumber(M.db.bagSpaceFree) or 3 end

---------------------------------------------------------------------------
-- The bags
---------------------------------------------------------------------------
-- The ordinary bags (bag family 0) and their free slots in all.
local function OrdinaryBags()
	local bags, free = {}, 0
	for _, bag in ipairs(E.BagCache:BagIDs()) do
		local slots, family = E.BagCache:Free(bag)
		if (family or 0) == 0 then
			bags[#bags + 1] = bag
			free = free + (slots or 0)
		end
	end
	return bags, free
end

function M.FreeBagSlots()
	local _, free = OrdinaryBags()
	return free
end

local function ItemClass(link)
	local get = (C_Item and C_Item.GetItemInfoInstant) or rawget(_G, "GetItemInfoInstant")
	local _, _, _, _, _, classID = PlainEach(get, link)
	return classID
end

local function SellPrice(link)
	local get = (C_Item and C_Item.GetItemInfo) or rawget(_G, "GetItemInfo")
	local name, _, _, _, _, _, _, _, _, _, price = PlainEach(get, link)
	return price, name
end

local function InEquipmentSet(bag, slot)
	return PlainCall(C_Container and C_Container.GetContainerItemEquipmentSetInfo, bag, slot) == true
end

local function Refundable(bag, slot)
	local info = PlainCall(C_Container and C_Container.GetContainerItemPurchaseInfo, bag, slot, false)
	local seconds = type(info) == "table" and Plain(info.refundSeconds)
	return type(seconds) == "number" and seconds > 0
end

-- The Merchant's "never sell" list (it keeps its settings while it is off).
local function NeverSell(itemID, name)
	local merchant = E.modules and E.modules.Merchant
	if not (merchant and merchant.db and type(merchant.NeverSell) == "function") then return false end
	local ok, keep = pcall(merchant.NeverSell, merchant, itemID, name)
	return ok and keep == true
end

-- The item in a slot of an ordinary bag, when you could part with it:
-- { bag, slot, id, link, count, value, icon, gray }, else nil.
local function Candidate(bag, slot)
	local info = E.BagCache:Info(bag, slot)
	local itemID = info and Plain(info.itemID)
	local link = info and Plain(info.hyperlink)
	if type(itemID) ~= "number" or type(link) ~= "string" then return nil end
	if Plain(info.hasNoValue) == true or Plain(info.isLocked) == true or SKIP_CLASS[ItemClass(link) or -1] then return nil end
	local price, name = SellPrice(link)
	if type(price) ~= "number" or price <= 0 then return nil end
	if InEquipmentSet(bag, slot) or Refundable(bag, slot) or NeverSell(itemID, name) then return nil end
	if E.IsItemProtected and E:IsItemProtected(itemID, bag, slot) then return nil end
	local count = Plain(info.stackCount)
	count = type(count) == "number" and count > 0 and count or 1
	return { bag = bag, slot = slot, id = itemID, link = link, count = count, value = price * count,
		icon = Plain(info.iconFileID), gray = Plain(info.quality) == 0 }
end

-- Everything you could part with, cheapest first: gray items first, then
-- by what the stack sells for.
function M:RoomCandidates()
	local list = {}
	for _, bag in ipairs((OrdinaryBags())) do
		for slot = 1, E.BagCache:NumSlots(bag) do
			local entry = Candidate(bag, slot)
			if entry then list[#list + 1] = entry end
		end
	end
	table.sort(list, function(a, b)
		if a.gray ~= b.gray then return a.gray end
		if a.value ~= b.value then return a.value < b.value end
		if a.bag ~= b.bag then return a.bag < b.bag end
		return a.slot < b.slot
	end)
	return list
end

---------------------------------------------------------------------------
-- Picking an item up
---------------------------------------------------------------------------
-- Where the item is now: its slot from the list, else another slot that
-- holds it and still passes every check of the list.
local function FindItem(entry)
	local here = Candidate(entry.bag, entry.slot)
	if here and here.id == entry.id then return entry.bag, entry.slot end
	for _, bag in ipairs((OrdinaryBags())) do
		for slot = 1, E.BagCache:NumSlots(bag) do
			if E.BagCache:ItemID(bag, slot) == entry.id then
				local other = Candidate(bag, slot)
				if other then return bag, slot end
			end
		end
	end
end

function M:PickUpForRoom(entry)
	-- Anything on the cursor (an item, money, a spell, a macro) would meet
	-- the bag slot instead of being picked up.
	if PlainCall(GetCursorInfo) ~= nil or PlainCall(CursorHasItem) == true then
		E:Print(L["Clear your cursor first."])
		return false
	end
	local bag, slot = FindItem(entry)
	if not bag then
		E:Print(L["%s is no longer in your bags."]:format(entry.link))
		return false
	end
	local pickup = C_Container and C_Container.PickupContainerItem
	if type(pickup) ~= "function" then return false end
	pickup(bag, slot)
	-- Once a session: what to do with it now.
	if not self.roomHintShown then
		self.roomHintShown = true
		E:Print(L["%s is on your cursor: click outside your bags to destroy it (the game asks first), drop it on an open vendor window to sell it, or put it back in a bag."]:format(entry.link))
	end
	return true
end

---------------------------------------------------------------------------
-- The card
---------------------------------------------------------------------------
-- true while the card on screen (or waiting) is one the player asked for
-- (/eui room, Show now): it follows the bags but stays when there is room.
local asked = false

local function Lines(list)
	local lines = {}
	for index = 1, math.min(#list, SHOWN) do
		local entry = list[index]
		local name = entry.count > 1 and L["%s x%d"]:format(entry.link, entry.count) or entry.link
		lines[index] = {
			text = L["%s, sells for %s"]:format(name, E:EconomyMoney(entry.value)),
			icon = entry.icon,
			func = function() M:PickUpForRoom(entry) end,
			label = L["Make room"],
			tip = L["Puts it on your cursor: click outside your bags to destroy it (the game asks first), or drop it on an open vendor window to sell it."],
		}
	end
	return lines
end

-- The card with the free slots and the list. quiet: no sound (a refresh).
-- byPlayer: true for /eui room and Show now, false for the hint; nil keeps
-- what the card is (a refresh).
function M:ShowBagSpace(quiet, byPlayer)
	if byPlayer ~= nil then asked = byPlayer end
	local free = M.FreeBagSlots()
	local list = self:RoomCandidates()
	local text = L["Free slots left: %d."]:format(free)
	if #list > 0 then
		text = text .. " " .. L["Make room: the cheapest things you carry."]
	else
		text = text .. " " .. L["Nothing to offer: the rest is needed or kept, has no vendor price, or is food, a reagent, ammo or the like."]
	end
	local sound = self.db.bagSpaceSound
	self:PushAlert({
		key = KEY,
		title = asked and L["Make room"] or L["Bags almost full"],
		text = text,
		icon = ICON,
		lines = Lines(list),
		duration = DURATION,
		-- Always a card, also without lines: the alert lane would show it as
		-- a toast beside the card it should replace.
		closable = true,
		sound = (not quiet and sound and sound ~= "none") and sound or nil,
	})
end

-- Is the card on screen (not sliding out) or waiting for its turn?
local function CardUp()
	if type(E.NoticeQueue) ~= "function" then return false end
	local ok, queue = pcall(E.NoticeQueue, E)
	if not ok or type(queue) ~= "table" then return false end
	for _, entry in ipairs(queue.shown or {}) do
		if not entry.closing and type(entry.data) == "table" and entry.data.key == KEY then return true end
	end
	for _, entry in ipairs(queue.waiting or {}) do
		if type(entry.data) == "table" and entry.data.key == KEY then return true end
	end
	return false
end
M.BagSpaceCardUp = CardUp

-- A card that is up follows the bags: the hint goes once there is room,
-- the one the player asked for stays. Out of combat only.
local function Follow(free)
	if not CardUp() then
		asked = false
		return
	end
	if free > Limit() and not asked then
		E:DismissAlert(KEY)
		return
	end
	M:ShowBagSpace(true)
end

---------------------------------------------------------------------------
-- When it comes
---------------------------------------------------------------------------
-- { last = free slots at the last read, armed = a drop may bring the card,
--   pending = a drop in combat waits for its end, db and limit it started
--   with }
local state
-- No drop counts before this time: after login and loading screens the
-- bags may still be loading.
local settleUntil = 0

function M:CheckBagSpace()
	if not self.active then
		state = nil
		return
	end
	local free = M.FreeBagSlots()
	local combat = InCombatLockdown()
	if not self.db.bagSpace then
		state = nil
		if not combat then
			if asked then
				Follow(free)
			elseif CardUp() then
				E:DismissAlert(KEY)
			end
		end
		return
	end
	local limit = Limit()
	if not state or state.db ~= self.db or state.limit ~= limit then
		-- Switched on, a new profile or a new limit: start from the bags as
		-- they are. Any other change on the page keeps where it stands.
		state = { last = free, armed = true, db = self.db, limit = limit }
		if not combat then Follow(free) end
		return
	end
	local dropped = free < state.last
	state.last = free
	if free > limit then
		state.armed, state.pending = true, nil
		if not combat then Follow(free) end
		return
	end
	if dropped and state.armed and GetTime() >= settleUntil then
		state.armed = false
		if combat then
			state.pending = true
		else
			self:ShowBagSpace(false, false)
		end
	elseif not combat then
		Follow(free)
	end
end

-- After login and loading screens the bags settle before a drop counts.
function M:BagSpaceSettle()
	settleUntil = GetTime() + SETTLE
end

function M:BagSpaceCombatEnded()
	if not self.active then return end
	if state and state.pending then
		state.pending = nil
		if self.db.bagSpace and M.FreeBagSlots() <= Limit() then
			self:ShowBagSpace(false, false)
			return
		end
	end
	-- A card that was up in combat catches up.
	self:CheckBagSpace()
end

M.BagSpaceState = function() return state end -- tools/qol/test_bag_space.lua

M:AddPart("BagSpace", {
	enable = function(self)
		E.BagCache:RegisterCallback(OWNER, function() M:CheckBagSpace() end)
		E:RegisterEvent("PLAYER_REGEN_ENABLED", function() M:BagSpaceCombatEnded() end, OWNER)
		E:RegisterEvent("PLAYER_ENTERING_WORLD", function() M:BagSpaceSettle() end, OWNER)
		state = nil
		self:BagSpaceSettle()
		self:CheckBagSpace()
	end,
	disable = function()
		E.BagCache:UnregisterCallback(OWNER)
		E:UnregisterEvent("PLAYER_REGEN_ENABLED", OWNER)
		E:UnregisterEvent("PLAYER_ENTERING_WORLD", OWNER)
		state, asked = nil, false
		E:DismissAlert(KEY)
	end,
	-- Every change on the page comes here: only the switch, the limit and
	-- a new profile start anew (CheckBagSpace).
	profile = function(self) self:CheckBagSpace() end,
})

E:AddCommand("room", "the cheapest things in your bags, to make room", function()
	if not M.active then
		E:Print(E:ModuleOffHint("QoL"))
		return
	end
	M:ShowBagSpace(true, true)
end, "Tools")

M:AddOptions(E.Key("Sound and misc"), {
	{ type = "header", label = "Bag space" },
	{ type = "toggle", key = "bagSpace", label = "Hint when the bags are almost full",
		desc = "A card when your ordinary bags get down to a few free slots, with the five cheapest things you carry. A click on one puts it on your cursor: click outside your bags to destroy it (the game asks first), or drop it on an open vendor window to sell it. Never in combat." },
	{ type = "range", key = "bagSpaceFree", label = "Free slots", min = 1, max = 10, step = 1, dependsOn = "bagSpace",
		desc = "The card comes when this many slots or fewer are free." },
	{ type = "media", key = "bagSpaceSound", label = "Sound", mediaKind = "sound", none = true, dependsOn = "bagSpace",
		desc = "The sound with the card. None for silence." },
	{ type = "execute", label = "Show now", desc = "Shows the card with the cheapest things you carry now (also /eui room).",
		func = function() M:ShowBagSpace(true, true) end },
})
