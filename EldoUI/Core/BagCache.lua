-- EldoUI bag cache (E.BagCache): one read of the bags shared by every
-- module that looks through them.
--
--   for bag, slot, info in E.BagCache:Items() do ... end      -- filled slots
--   for bag, slot, info in E.BagCache:Items({ reagent = true }) do ... end
--   local info = E.BagCache:Info(bag, slot)                   -- or nil
--   local slots = E.BagCache:NumSlots(bag)
--   local free, family = E.BagCache:Free(bag)
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
local function Record(bag)
	local now = GetTime()
	local record = cache[bag]
	if record and record.at == now then return record end
	local container = Container()
	local slots = container and Call(container.GetContainerNumSlots, bag)
	record = { at = now, slots = type(slots) == "number" and slots or 0, info = {} }
	cache[bag] = record
	return record
end

-- Forget one bag, or every bag (nil).
function B:Invalidate(bag)
	if bag == nil then
		wipe(cache)
	else
		cache[bag] = nil
	end
end

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
function B:Free(bag)
	local record = Record(bag)
	if record.free == nil then
		local container = Container()
		local free, family
		if container then free, family = Call(container.GetContainerNumFreeSlots, bag) end
		record.free = type(free) == "number" and free or 0
		record.family = family
	end
	return record.free, record.family
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
	if type(bag) == "number" and not (E.Secret and E.Secret(bag)) then
		cache[bag] = nil
	else
		wipe(cache)
	end
end

local function DropAll()
	wipe(cache)
end

E:RegisterEvent("BAG_UPDATE", DropBag, owner)
E:RegisterEvent("ITEM_LOCK_CHANGED", DropBag, owner)
for _, event in ipairs({ "BAG_CONTAINER_UPDATE", "BAG_SLOT_FLAGS_UPDATED", "INVENTORY_SEARCH_UPDATE",
	"PLAYER_ENTERING_WORLD" }) do
	E:RegisterEvent(event, DropAll, owner)
end

E:RegisterEvent("BAG_UPDATE_DELAYED", function()
	wipe(cache)
	for key, fn in pairs(callbacks) do
		local ok, err = pcall(fn, key)
		if not ok then geterrorhandler()(err) end
	end
end, owner)
