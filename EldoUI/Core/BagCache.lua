-- EldoUI bag cache (E.BagCache): one read of the bags shared by every
-- module that looks through them.
--
--   for bag, slot, info in E.BagCache:Items() do ... end      -- filled slots
--   for bag, slot, info in E.BagCache:Items({ reagent = true }) do ... end
--   local info = E.BagCache:Info(bag, slot)                   -- or nil
--   local slots = E.BagCache:NumSlots(bag)
--   local free, family, known = E.BagCache:Free(bag)
--   local free, total = E.BagCache:GeneralSlots(bags)
--   E.BagCache:RegisterCallback(owner, fn) -- fn() once the bags settled
--
-- `info` is the game's container item info (itemID, hyperlink, iconFileID,
-- stackCount, quality, isLocked, hasNoValue, ...). It is shared: read it,
-- never change it. What the cache holds is never older than the current
-- frame or the last bag event, so a module reads the same thing it would
-- read from the game, and several modules that look on the same event
-- read the bags only once.
--
-- Bag lists (opts of Items and BagIDs):
--   default         the backpack and the equipped bags (0 .. NUM_BAG_SLOTS)
--   equipped = true every equipped bag, the reagent bag too where the
--                   client counts it (0 .. NUM_TOTAL_EQUIPPED_BAG_SLOTS)
--   reagent = true  adds the reagent bag when the client has one with slots
local _, E = ...

local B = {}
E.BagCache = B

local cache = {}      -- bag -> { at, slots, info = { [slot] = info | false }, free, family }
local callbacks = {}  -- owner -> fn
local revision = 0

local function Container()
	local container = rawget(_G, "C_Container")
	return type(container) == "table" and container or nil
end

local function Plain(value)
	if E.Secret and E.Secret(value) then return nil end
	return value
end

local function Call(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a, b = pcall(fn, ...)
	if not ok then return nil end
	return Plain(a), Plain(b)
end

-- The record of one bag, read again when a bag event came in or a new
-- frame started since it was read.
local function SlotCount(value)
	return type(value) == "number" and value >= 0 and value < math.huge and value % 1 == 0
end

local function Record(bag)
	local now = GetTime()
	local record = cache[bag]
	if record and record.at == now then return record end
	local container = Container()
	local slots = container and Call(container.GetContainerNumSlots, bag)
	local known = SlotCount(slots)
	record = { at = now, slots = known and slots or 0, slotsKnown = known, info = {} }
	cache[bag] = record
	return record
end

-- Forget one bag, or every bag (nil).
function B:Invalidate(bag)
	revision = revision + 1
	if bag == nil then
		wipe(cache)
	else
		cache[bag] = nil
	end
end

function B:Revision() return revision end

function B:NumSlots(bag)
	return Record(bag).slots
end

-- The container item info of a slot, or nil for an empty slot.
function B:Info(bag, slot)
	local record = Record(bag)
	if type(slot) ~= "number" or slot < 1 or slot > record.slots then return nil end
	local info = record.info[slot]
	if info == nil then
		local container = Container()
		info = container and Call(container.GetContainerItemInfo, bag, slot)
		if type(info) ~= "table" then info = false end
		record.info[slot] = info
	end
	return info or nil
end

-- One value of a slot from its own game call, kept like the info.
local function Field(bag, slot, key, method)
	local record = Record(bag)
	if type(slot) ~= "number" or slot < 1 or slot > record.slots then return nil end
	local list = record[key]
	if not list then
		list = {}
		record[key] = list
	end
	local value = list[slot]
	if value == nil then
		local container = Container()
		value = container and Call(container[method], bag, slot)
		if value == nil then value = false end
		list[slot] = value
	end
	return value or nil
end

-- The item ID (GetContainerItemID) and link (GetContainerItemLink) of a slot.
function B:ItemID(bag, slot)
	return Field(bag, slot, "ids", "GetContainerItemID")
end

function B:Link(bag, slot)
	return Field(bag, slot, "links", "GetContainerItemLink")
end

-- Free slots of a bag and its bag family (as GetContainerNumFreeSlots).
-- The third result tells whether its free slot count was readable.
function B:Free(bag)
	local record = Record(bag)
	if record.free == nil then
		local container = Container()
		local free, family
		if container then free, family = Call(container.GetContainerNumFreeSlots, bag) end
		record.free = type(free) == "number" and free or 0
		record.readFamily = family
		record.family = type(free) == "number" and family or nil
		record.freeKnown = type(free) == "number"
	end
	return record.free, record.family, record.freeKnown
end

local function FixedBankTab(index, bag)
	if not index then return false end
	local first, last = index.CharacterBankTab_1, index.CharacterBankTab_9
	if first and last and bag >= first and bag <= last then return true end
	first, last = index.AccountBankTab_1, index.AccountBankTab_9
	return first and last and bag >= first and bag <= last
end

-- General capacity in the caller's bag or bank list. An unknown family
-- only counts for known fixed storage with a readable free-slot count.
-- A requested breakdown also reports whether the general total is complete.
function B:GeneralSlots(bags, fixedBankTabs, breakdown)
	local free, total, known = 0, 0, true
	local rows = breakdown and {} or nil
	local index = Enum and Enum.BagIndex
	local bank = index and index.Bank or rawget(_G, "BANK_CONTAINER")
	for _, bag in ipairs(bags) do
		local excluded = index and (bag == index.Keyring or bag == index.ReagentBag)
		if rows or not excluded then
			local bagFree, family, freeKnown = self:Free(bag)
			local record = Record(bag)
			local slots = self:NumSlots(bag)
			local general = not excluded and (family == 0 or (freeKnown and family == nil
				and (bag == 0 or bag == bank or (fixedBankTabs and FixedBankTab(index, bag)))))
			if general then
				free = free + bagFree
				total = total + slots
			end
			-- A container change can leave the free read from the former bag.
			if rows and general and slots == 0 and bagFree ~= 0 then known = false end
			if rows and (not record.slotsKnown or slots > 0) then
				local capacityFamily = record.readFamily
				local special = excluded or (SlotCount(capacityFamily) and capacityFamily > 0)
				local readable = record.slotsKnown and freeKnown and SlotCount(bagFree) and bagFree <= slots
				if not special and not (general and readable) then known = false end
				rows[#rows + 1] = { bag = bag, special = special, free = readable and bagFree or nil,
					total = record.slotsKnown and slots or nil }
			end
		end
	end
	if rows then return free, total, known and total > 0, rows end
	return free, total
end

-- The bag IDs to look through (see opts at the top).
function B:BagIDs(opts)
	local last
	if opts and opts.equipped then
		last = rawget(_G, "NUM_TOTAL_EQUIPPED_BAG_SLOTS") or rawget(_G, "NUM_BAG_SLOTS") or 4
	else
		last = rawget(_G, "NUM_BAG_SLOTS") or 4
	end
	local bags = {}
	for bag = 0, last do bags[#bags + 1] = bag end
	if opts and opts.reagent then
		local index = rawget(_G, "Enum") and Enum.BagIndex
		local reagent = index and index.ReagentBag
		if reagent and reagent > last and self:NumSlots(reagent) > 0 then bags[#bags + 1] = reagent end
	end
	return bags
end

-- Every filled slot: for bag, slot, info in E.BagCache:Items(opts).
function B:Items(opts)
	local bags = self:BagIDs(opts)
	local bagIndex, slot = 1, 0
	return function()
		while bags[bagIndex] do
			local bag = bags[bagIndex]
			slot = slot + 1
			if slot > self:NumSlots(bag) then
				bagIndex, slot = bagIndex + 1, 0
			else
				local info = self:Info(bag, slot)
				if info then return bag, slot, info end
			end
		end
	end
end

-- fn() runs after the bags settled (BAG_UPDATE_DELAYED), one per owner.
function B:RegisterCallback(owner, fn)
	if owner == nil or type(fn) ~= "function" then return end
	callbacks[owner] = fn
end

function B:UnregisterCallback(owner)
	if owner ~= nil then callbacks[owner] = nil end
end

---------------------------------------------------------------------------
-- Events: a change in a bag drops what the cache holds for it.
---------------------------------------------------------------------------
local owner = {}

local function DropBag(_, _, bag)
	B:Invalidate(type(bag) == "number" and Plain(bag) or nil)
end

local function DropAll()
	B:Invalidate()
end

E:RegisterEvent("BAG_UPDATE", DropBag, owner)
E:RegisterEvent("ITEM_LOCK_CHANGED", DropBag, owner)
for _, event in ipairs({ "BAG_CONTAINER_UPDATE", "BAG_SLOT_FLAGS_UPDATED", "INVENTORY_SEARCH_UPDATE",
	"PLAYER_ENTERING_WORLD" }) do
	E:RegisterEvent(event, DropAll, owner)
end

E:RegisterEvent("BAG_UPDATE_DELAYED", function()
	B:Invalidate()
	for key, fn in pairs(callbacks) do
		local ok, err = pcall(fn, key)
		if not ok then geterrorhandler()(err) end
	end
end, owner)
