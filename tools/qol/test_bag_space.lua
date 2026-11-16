-- Offline test for the hint when the bags are almost full (Quality of Life
-- > Sound and misc; review verbesserungen.md, B7).
-- Run from the repository root:
--   lua5.1 tools/qol/test_bag_space.lua
-- It loads EldoUI/Modules/QoL/BagSpace.lua as it is, together with EldoUI's
-- own Core/Safe.lua (secret values) and Core/BagCache.lua (the bags), with
-- stand-ins for the QoL module, the bags, the item API, the cursor, the
-- combat lockdown, the alert cards, item protection and the Merchant's
-- "never sell" list.
-- Checked: when the card comes (a drop to the limit, not at login or right
-- after a loading screen, once until more than the limit is free again,
-- after combat for a drop in combat, not when freed in combat, not again
-- after another setting of the page changed; anew with a new profile or
-- limit); that it follows the bags while it shows or waits, catches up
-- after combat and goes away once there is room (not one sliding out); that
-- it is always a card, also without lines; the card asked for with
-- /eui room or Show now, which stays with room; which items "Make room"
-- lists (gray first, then by what the stack sells for, five at most) and
-- which it leaves out (protected, no vendor price, locked, equipment sets,
-- refundable, "never sell", food and potions, reagents, ammo, recipes,
-- quivers, quest items, keys, items in profession bags, secret links);
-- picking an item up (only with an empty cursor, from where it is now and
-- only a copy that passes the checks, the hint once a session); the sound;
-- the switch, the module turned off; defaults, Minimal and options. The
-- notice queue is modeled as far as the part sees it (E:NoticeQueue,
-- E:DismissAlert, the lane for alerts without lines).
local ROOT = (arg and arg[0] or ""):match("^(.-)tools/qol/") or "./"

local function ReadFile(path)
	local file = assert(io.open(ROOT .. path, "rb"), "can't open " .. path)
	local text = file:read("*a")
	file:close()
	return (text:gsub("\r\n", "\n"))
end
local function Load(path) return assert(loadstring(ReadFile(path), "=" .. path:match("[^/]+$"))) end
local SAFE, BAGCACHE, CHUNK = Load("EldoUI/Core/Safe.lua"), Load("EldoUI/Core/BagCache.lua"), Load("EldoUI/Modules/QoL/BagSpace.lua")

local passed, failed = 0, 0
local function Check(ok, what)
	if ok then
		passed = passed + 1
	else
		failed = failed + 1
		print("FAIL: " .. what)
	end
end

---------------------------------------------------------------------------
-- The game
---------------------------------------------------------------------------
local SECRET = setmetatable({}, { __tostring = function() return "<secret>" end })
function issecretvalue(value) return value == SECRET end
local world

Enum = { ItemClass = { Consumable = 0, Container = 1, Weapon = 2, Armor = 4, Reagent = 5, Projectile = 6, Tradegoods = 7,
	Recipe = 9, Quiver = 11, Questitem = 12, Key = 13, Miscellaneous = 15 } }
NUM_BAG_SLOTS = 4

-- Items: world.items[id] = { class, price, name }.
-- Bags: world.bags[bag] = { size, family, [slot] = { id, count, quality, locked, noValue, set, refund, secretLink } }.
local function Slot(bag, slot)
	local list = world.bags[bag]
	return list and list[slot] or nil
end
local function Link(id) return ("|cffffffff|Hitem:%d::::::::|h[Item %d]|h|r"):format(id, id) end
local function IDOfLink(link) return tonumber(tostring(link):match("item:(%d+)")) end

C_Container = {
	GetContainerNumSlots = function(bag) return world.bags[bag] and world.bags[bag].size or 0 end,
	GetContainerNumFreeSlots = function(bag)
		local list = world.bags[bag]
		if not list then return 0, 0 end
		local used = 0
		for slot = 1, list.size do
			if list[slot] then used = used + 1 end
		end
		return list.size - used, list.family or 0
	end,
	GetContainerItemInfo = function(bag, slot)
		local entry = Slot(bag, slot)
		if not entry then return nil end
		return { itemID = entry.id, hyperlink = entry.secretLink and SECRET or Link(entry.id), stackCount = entry.count or 1,
			quality = entry.quality or 1, isLocked = entry.locked or false, hasNoValue = entry.noValue or false, iconFileID = 9000 + entry.id }
	end,
	GetContainerItemID = function(bag, slot)
		local entry = Slot(bag, slot)
		return entry and entry.id or nil
	end,
	GetContainerItemLink = function(bag, slot)
		local entry = Slot(bag, slot)
		return entry and Link(entry.id) or nil
	end,
	GetContainerItemEquipmentSetInfo = function(bag, slot)
		local entry = Slot(bag, slot)
		return entry and entry.set or false, ""
	end,
	GetContainerItemPurchaseInfo = function(bag, slot)
		local entry = Slot(bag, slot)
		return { refundSeconds = entry and entry.refund or 0 }
	end,
	PickupContainerItem = function(bag, slot) table.insert(world.pickups, ("%d:%d"):format(bag, slot)) end,
}
C_Item = {
	GetItemInfoInstant = function(link)
		local id = IDOfLink(link)
		local item = id and world.items[id]
		if not item then return nil end
		return id, "type", "subtype", "", 1, item.class or 7, 0
	end,
	GetItemInfo = function(link)
		local id = IDOfLink(link)
		local item = id and world.items[id]
		if not item then return nil end
		return item.name or ("Item " .. id), link, 1, 1, 1, "type", "subtype", 20, "", 1, item.price
	end,
}
function CursorHasItem() return world.cursor end
function GetCursorInfo() return world.cursorInfo end
function InCombatLockdown() return world.combat end
function GetTime() return world.now end
function wipe(t)
	for key in pairs(t) do t[key] = nil end
	return t
end
function geterrorhandler() return function(err) error(err, 2) end end

---------------------------------------------------------------------------
-- EldoUI around the part
---------------------------------------------------------------------------
local test

local function Setup()
	world = { now = 100, combat = false, cursor = false, items = {}, bags = {}, protected = {}, neverSell = {},
		pickups = {}, printed = {}, alerts = {}, dismissed = {}, cards = {}, waiting = {}, lane = {}, events = {}, newCards = 0 }
	test = { parts = {}, options = {}, commands = {} }
	local L = setmetatable({}, { __index = function(_, key) return key end })
	local E = { L = L, modules = {} }
	local M = { name = "QoL", defaults = {}, active = false }
	function M:AddPart(name, hooks) test.parts[name] = hooks end
	function M:AddOptions(tab, rows) test.options[#test.options + 1] = { tab = tab, rows = rows } end
	-- EldoUI's notice queue as far as the part sees it (Core/Alerts.lua): an
	-- alert without lines or buttons that is not closable goes to the alert
	-- lane as a toast; the rest become cards, three on screen, the others
	-- wait. A key refreshes the card on screen or the waiting one (not one
	-- that slides out).
	function M:PushAlert(data)
		table.insert(world.alerts, data)
		local hasLines = type(data.lines) == "table" and #data.lines > 0
		if not hasLines and not data.closable then
			table.insert(world.lane, data)
			return
		end
		for _, list in ipairs({ world.cards, world.waiting }) do
			for _, entry in ipairs(list) do
				if not entry.closing and entry.data.key == data.key then
					entry.data = data
					return
				end
			end
		end
		world.newCards = world.newCards + 1
		table.insert(#world.cards < 3 and world.cards or world.waiting, { data = data })
	end
	function E:GetModule(name) if name == "QoL" then return M end end
	E.styles = { QoL = { { key = "Minimal", settings = {} }, { key = "Default", settings = {} } } }
	function E:RegisterEvent(event, fn, owner) world.events[event .. ":" .. tostring(owner)] = fn end
	function E:UnregisterEvent(event, owner) world.events[event .. ":" .. tostring(owner)] = nil end
	function E:DismissAlert(key)
		table.insert(world.dismissed, key)
		for _, list in ipairs({ world.cards, world.waiting }) do
			for index = #list, 1, -1 do
				if not list[index].closing and list[index].data.key == key then table.remove(list, index) end
			end
		end
	end
	function E:NoticeQueue()
		local shown, waiting = {}, {}
		for _, entry in ipairs(world.cards) do shown[#shown + 1] = { holder = "card", data = entry.data, closing = entry.closing } end
		for _, entry in ipairs(world.waiting) do waiting[#waiting + 1] = { holder = "card", data = entry.data } end
		return { holders = { "card" }, shown = shown, waiting = waiting }
	end
	function E:EconomyMoney(copper) return copper .. "c" end
	function E:Print(text) table.insert(world.printed, text) end
	function E:AddCommand(name, usage, fn, group) test.commands[name] = { usage = usage, fn = fn, group = group } end
	function E:ModuleOffHint(name) return "off: " .. name end
	E.Key = function(text) return text end
	function E:IsItemProtected(itemID, bag, slot)
		world.protectArgs = { itemID, bag, slot }
		return world.protected[itemID] == true
	end
	E.modules.Merchant = { db = {} }
	function E.modules.Merchant:NeverSell(itemID) return world.neverSell[itemID] == true end
	SAFE(nil, E)
	BAGCACHE(nil, E)
	CHUNK(nil, E)
	-- The module's settings: its defaults, as a new profile has them.
	M.db = {}
	for key, value in pairs(M.defaults) do M.db[key] = value end
	test.E, test.M = E, M
	return M
end

-- The bags settled (BAG_UPDATE_DELAYED): EldoUI's bag cache forgets what it
-- read and hands the event to its callbacks, the part's among them.
local function Settle()
	world.now = world.now + 1
	local delayed
	for key, handler in pairs(world.events) do
		if key:find("^BAG_UPDATE_DELAYED:") then delayed = handler end
	end
	if delayed then delayed() end
end

-- Turn the part on; unless `settling`, the bags have settled since (the
-- first seconds after login don't count).
local function Enable(M, settling)
	M.active = true
	test.parts.BagSpace.enable(M)
	if not settling then world.now = world.now + 10 end
end

local function EndCombat()
	world.combat = false
	world.now = world.now + 1
	local fn = world.events["PLAYER_REGEN_ENABLED:QoL:BagSpace"]
	if fn then fn() end
end

-- Bag 0 with `size` slots and these items from slot 1; bag 1 is a herb bag.
local function Bags(size, list, herbs)
	world.bags = { [0] = { size = size, family = 0 }, [1] = { size = 4, family = 32 } }
	for slot, entry in ipairs(list or {}) do world.bags[0][slot] = entry end
	for slot, entry in ipairs(herbs or {}) do world.bags[1][slot] = entry end
	world.now = world.now + 1
end

-- Fill or empty bag 0 to `free` free slots with plain cloth.
local function SetFree(free)
	local list = world.bags[0]
	local used = 0
	for slot = 1, list.size do if list[slot] then used = used + 1 end end
	local want = list.size - free
	for slot = list.size, 1, -1 do
		if used > want and list[slot] and list[slot].filler then list[slot] = nil used = used - 1 end
	end
	for slot = 1, list.size do
		if used < want and not list[slot] then list[slot] = { id = 2589, count = 1, filler = true } used = used + 1 end
	end
	Settle()
end

local function Item(id, fields)
	world.items[id] = fields or {}
end

local function LastAlert() return world.alerts[#world.alerts] end
local function OurCard() return { data = { key = "QoL:bagSpace" } } end
local function LineIDs(data)
	local ids = {}
	for _, line in ipairs(data.lines or {}) do ids[#ids + 1] = tostring(line.text:match("item:(%d+)")) end
	return table.concat(ids, " ")
end

-- The standard bag: every kind of item once (25 slots, 17 used).
local function StandardWorld()
	Item(2589, { class = 15, price = 0 })     -- the filler: no vendor price, never listed
	Item(3000, { class = 15, price = 40 })    -- gray trash, 40c
	Item(3001, { class = 15, price = 5 })     -- gray trash, 5c each, 3 of them: 15c
	Item(3002, { class = 4, price = 100 })    -- white armor, 1s
	Item(3003, { class = 7, price = 30 })     -- trade goods, 30c
	Item(3004, { class = 0, price = 1 })      -- water: consumable
	Item(3005, { class = 5, price = 2 })      -- a reagent
	Item(3006, { class = 6, price = 1 })      -- arrows
	Item(3007, { class = 12, price = 1 })     -- a quest item
	Item(3008, { class = 15, price = 0 })     -- no vendor price
	Item(3009, { class = 2, price = 20 })     -- a protected item (a quest needs it)
	Item(3010, { class = 2, price = 21 })     -- in an equipment set
	Item(3011, { class = 2, price = 22 })     -- refundable
	Item(3012, { class = 7, price = 23 })     -- on the "never sell" list
	Item(3013, { class = 15, price = 24 })    -- locked
	Item(3014, { class = 15, price = 25 })    -- has no value (game flag)
	Item(3015, { class = 15, price = 26 })    -- a secret link
	Item(3016, { class = 7, price = 1 })      -- a herb in the herb bag
	Item(3017, { class = 9, price = 3 })      -- a recipe
	world.protected[3009] = true
	world.neverSell[3012] = true
	Bags(25, {
		{ id = 3002 }, { id = 3000, quality = 0 }, { id = 3001, quality = 0, count = 3 }, { id = 3003 }, { id = 3004, count = 20 },
		{ id = 3005 }, { id = 3006, count = 200 }, { id = 3007 }, { id = 3008 }, { id = 3009 },
		{ id = 3010, set = true }, { id = 3011, refund = 3600 }, { id = 3012 }, { id = 3013, locked = true }, { id = 3014, noValue = true },
		{ id = 3015, secretLink = true }, { id = 3017 },
	}, { { id = 3016, count = 5 } })
end

---------------------------------------------------------------------------
-- Checks
---------------------------------------------------------------------------
-- Which items "Make room" lists, and in which order.
do
	local M = Setup()
	StandardWorld()
	local list = M:RoomCandidates()
	local ids = {}
	for _, entry in ipairs(list) do ids[#ids + 1] = tostring(entry.id) end
	Check(table.concat(ids, " ") == "3001 3000 3003 3002", "gray first, then by what the stack sells for: " .. table.concat(ids, " "))
	Check(list[1].value == 15 and list[1].count == 3 and list[1].bag == 0 and list[1].slot == 3, "a stack's value is price times count")
	Check(list[1].icon == 9000 + 3001, "with the item's icon")
	Check(M.FreeBagSlots() == 8, "only the ordinary bag counts: 8 free, not the herb bag's 3: " .. M.FreeBagSlots())
end

-- More than five: five lines, cheapest first.
do
	local M = Setup()
	local list = {}
	for id = 4001, 4008 do
		Item(id, { class = 7, price = 100 - id % 100 })
		list[#list + 1] = { id = id }
	end
	Bags(10, list)
	M.db.bagSpaceFree = 3
	Enable(M)
	M:ShowBagSpace(true)
	Check(LineIDs(LastAlert()) == "4008 4007 4006 4005 4004", "five lines, the cheapest first: " .. LineIDs(LastAlert()))
end

-- When the card comes.
do
	local M = Setup()
	StandardWorld()
	SetFree(5)
	Enable(M)
	Check(#world.alerts == 0, "at login: no card")
	SetFree(4)
	Check(#world.alerts == 0, "4 free: no card")
	SetFree(3)
	local card = LastAlert()
	Check(#world.alerts == 1 and card.key == "QoL:bagSpace" and card.title == "Bags almost full", "3 free: the card")
	Check(card.text == "Free slots left: 3. Make room: the cheapest things you carry.", "the free slots and the list: " .. card.text)
	Check(LineIDs(card) == "3001 3000 3003 3002" and #card.lines == 4, "the lines are the items to part with")
	Check(card.lines[1].text == Link(3001) .. " x3, sells for 15c" and card.lines[2].text == Link(3000) .. ", sells for 40c", "each line: item, count, value")
	Check(card.sound == nil, "no sound by default")
	Check(card.duration == 30 and card.icon ~= nil, "it stays 30 seconds")
	SetFree(2)
	Check(#world.alerts == 2 and LastAlert().text:find("Free slots left: 2.", 1, true) and LastAlert().sound == nil,
		"while the card shows, it follows the bags (no sound)")
	world.cards = {} -- the card closed
	SetFree(1)
	Check(#world.alerts == 2, "a further drop after the card closed: no new card")
	SetFree(3)
	Check(#world.alerts == 2, "back to the limit from below: none")
	world.cards = { OurCard() }
	SetFree(4)
	Check(world.dismissed[#world.dismissed] == "QoL:bagSpace" and #world.cards == 0, "room again: the card goes away")
	SetFree(3)
	Check(#world.alerts == 3, "and the next drop brings it again")
end

-- At login with full bags: the next drop brings the card.
do
	local M = Setup()
	StandardWorld()
	SetFree(2)
	Enable(M)
	Check(#world.alerts == 0, "logged in with 2 free: no card")
	SetFree(2)
	Check(#world.alerts == 0, "no change: none")
	SetFree(1)
	Check(#world.alerts == 1, "one slot less: the card")
end

-- Combat.
do
	local M = Setup()
	StandardWorld()
	SetFree(5)
	Enable(M)
	world.combat = true
	SetFree(3)
	Check(#world.alerts == 0 and M.BagSpaceState().pending == true, "a drop in combat: no card yet")
	EndCombat()
	Check(#world.alerts == 1 and world.newCards == 1, "combat over: the card")
	EndCombat()
	Check(world.newCards == 1, "only once")
	SetFree(6)
	world.combat = true
	SetFree(2)
	SetFree(5)
	EndCombat()
	Check(world.newCards == 1 and #world.cards == 0, "room again before combat ended: no card")
	world.cards = { OurCard() }
	world.combat = true
	local before = #world.alerts
	SetFree(3)
	SetFree(2)
	Check(#world.alerts == before, "in combat the shown card is not refreshed")
	EndCombat()
	Check(#world.alerts == before + 1 and LastAlert().title == "Bags almost full" and LastAlert().text:find("left: 2.", 1, true),
		"after combat it comes")
	-- A card that is up while the hint is used up: it catches up after combat.
	world.combat = true
	SetFree(1)
	Check(#world.alerts == before + 1, "a further drop in combat: nothing yet")
	EndCombat()
	Check(#world.alerts == before + 2 and LastAlert().text:find("left: 1.", 1, true) and LastAlert().sound == nil,
		"after combat the card shows the bags as they are, quietly")
end

-- The sound.
do
	local M = Setup()
	StandardWorld()
	SetFree(5)
	M.db.bagSpaceSound = "eldo:EldoChime"
	Enable(M)
	SetFree(3)
	Check(LastAlert().sound == "eldo:EldoChime", "the chosen sound comes with the card")
	SetFree(2)
	Check(LastAlert().sound == nil, "a refresh is quiet")
end

-- Nothing to part with.
do
	local M = Setup()
	Item(5000, { class = 0, price = 5 })
	Bags(3, { { id = 5000 } })
	Enable(M)
	M:ShowBagSpace(true)
	Check(#LastAlert().lines == 0 and LastAlert().text:find("Nothing to offer", 1, true), "nothing to part with: it says why")
	Check(LastAlert().closable == true and #world.lane == 0 and #world.cards == 1, "without lines it is still a card, not a toast in the lane")
end

-- Picking an item up.
do
	local M = Setup()
	StandardWorld()
	SetFree(5)
	Enable(M)
	SetFree(3)
	local lines = LastAlert().lines
	Check(lines[1].label == "Make room" and lines[1].tip:find("destroy it", 1, true) ~= nil, "each line says what a click does")
	lines[1].func()
	Check(world.pickups[1] == "0:3", "a click picks the item up from its slot")
	Check(#world.printed == 1 and world.printed[1]:find("is on your cursor", 1, true) ~= nil, "with a hint")
	lines[2].func()
	Check(world.pickups[2] == "0:2" and #world.printed == 1, "the hint only once a session")
	world.cursor = true
	lines[3].func()
	Check(#world.pickups == 2 and world.printed[2] == "Clear your cursor first.", "an item on the cursor: nothing picked up")
	world.cursor = false
	world.cursorInfo = "money"
	lines[3].func()
	Check(#world.pickups == 2 and world.printed[3] == "Clear your cursor first.", "money on the cursor: nothing picked up")
	world.cursorInfo = nil
	world.cursor = false
	world.bags[0][19] = world.bags[0][4] -- the trade goods moved
	world.bags[0][4] = nil
	world.now = world.now + 1
	lines[3].func()
	Check(world.pickups[3] == "0:19", "an item that moved is picked up where it is now")
	world.bags[0][19] = nil
	world.now = world.now + 1
	lines[3].func()
	Check(#world.pickups == 3 and world.printed[#world.printed]:find("is no longer in your bags", 1, true) ~= nil, "an item that is gone: a note")
end

-- The switch, the limit, a new profile, the module off.
do
	local M = Setup()
	StandardWorld()
	SetFree(5)
	M.db.bagSpace = false
	Enable(M)
	SetFree(3)
	Check(#world.alerts == 0, "switched off: no card")
	M.db.bagSpace = true
	test.parts.BagSpace.profile(M)
	SetFree(2)
	Check(#world.alerts == 1, "switched on: the next drop brings it")
	M.db.bagSpaceFree = 6
	world.cards = {} -- the card closed
	test.parts.BagSpace.profile(M)
	Check(#world.alerts == 1, "a new limit starts from the bags as they are")
	SetFree(1)
	Check(#world.alerts == 2 and world.newCards == 2, "and works from there")
	world.cards = { OurCard() }
	M.db.bagSpace = false
	test.parts.BagSpace.profile(M)
	Check(#world.cards == 0, "switched off: the card goes")
	M.db.bagSpace = true
	test.parts.BagSpace.profile(M)
	world.cards = { OurCard() }
	M.active = false
	test.parts.BagSpace.disable(M)
	Check(#world.cards == 0 and M.BagSpaceState() == nil, "module off: the card goes, the state too")
	Check(world.events["PLAYER_REGEN_ENABLED:QoL:BagSpace"] == nil, "and it stops listening for the end of combat")
	local count = #world.alerts
	SetFree(0)
	Check(#world.alerts == count, "module off: the bags wake nothing")
end

-- The card asked for with /eui room: it follows the bags, stays with room.
do
	local M = Setup()
	StandardWorld()
	SetFree(8)
	Enable(M)
	test.commands.room.fn()
	Check(LastAlert().title == "Make room" and world.newCards == 1, "/eui room: a card titled Make room")
	SetFree(7)
	Check(#world.alerts == 2 and #world.cards == 1 and LastAlert().title == "Make room" and LastAlert().text:find("left: 7.", 1, true),
		"with many free slots it follows the bags and stays")
	SetFree(8)
	Check(#world.cards == 1 and LastAlert().text:find("left: 8.", 1, true), "more room: it still stays")
	SetFree(3)
	Check(LastAlert().title == "Bags almost full" and LastAlert().sound == nil and #world.cards == 1,
		"the hint takes its place when the bags get full")
	SetFree(4)
	Check(#world.cards == 0, "and the hint goes once there is room")
	M.db.bagSpace = false
	test.parts.BagSpace.profile(M)
	test.commands.room.fn()
	SetFree(5)
	Check(#world.cards == 1 and LastAlert().text:find("left: 5.", 1, true), "with the hint off, the card asked for still follows the bags")
	world.cards = {}
	SetFree(6)
	Check(#world.alerts == 6, "a closed card is not brought back")
end

-- A card waiting for its turn, and one that slides out.
do
	local M = Setup()
	StandardWorld()
	SetFree(5)
	Enable(M)
	world.cards = { { data = { key = "a" } }, { data = { key = "b" } }, { data = { key = "c" } } }
	SetFree(3)
	Check(#world.waiting == 1 and world.waiting[1].data.key == "QoL:bagSpace", "behind three cards the hint waits")
	SetFree(2)
	Check(#world.waiting == 1 and world.waiting[1].data.text:find("left: 2.", 1, true) and world.newCards == 1,
		"a waiting card follows the bags")
	SetFree(4)
	Check(#world.waiting == 0, "room again: the waiting card is dropped")
	world.cards = { { data = { key = "QoL:bagSpace" }, closing = true } }
	SetFree(3)
	local count = #world.alerts
	world.cards[2] = nil
	SetFree(2)
	Check(#world.alerts == count, "a card that slides out is not refreshed")
end

-- Other changes on the page, a new profile, a lower limit.
do
	local M = Setup()
	StandardWorld()
	SetFree(5)
	Enable(M)
	SetFree(2)
	Check(world.newCards == 1, "the hint came")
	world.cards = {}
	test.parts.BagSpace.profile(M) -- another setting of the page changed
	SetFree(1)
	Check(world.newCards == 1, "another setting changed: the hint does not come again")
	M.db = {}
	for key, value in pairs(M.defaults) do M.db[key] = value end
	test.parts.BagSpace.profile(M) -- a new profile
	SetFree(0)
	Check(world.newCards == 2, "a new profile starts anew")
	SetFree(3)
	Check(#world.cards == 1, "the card is up")
	M.db.bagSpaceFree = 2
	test.parts.BagSpace.profile(M)
	Check(#world.cards == 0, "a limit lowered below the free slots: the card goes")
end

-- After login or a loading screen the bags settle first.
do
	local M = Setup()
	StandardWorld()
	SetFree(5)
	Enable(M, true)
	SetFree(3)
	Check(world.newCards == 0, "a drop in the first seconds after login: no card")
	world.now = world.now + 10
	SetFree(2)
	Check(world.newCards == 1, "later the next drop brings it")
	SetFree(5)
	world.events["PLAYER_ENTERING_WORLD:QoL:BagSpace"]()
	SetFree(3)
	Check(world.newCards == 1, "right after a loading screen: no card")
end

-- An item that moved: only a copy that passes the checks is picked up.
do
	local M = Setup()
	StandardWorld()
	SetFree(5)
	Enable(M)
	local entry = M:RoomCandidates()[3]
	Check(entry.id == 3003 and entry.slot == 4, "the trade goods in slot 4")
	Check(world.protectArgs and world.protectArgs[2] == 0 and type(world.protectArgs[3]) == "number", "protection is asked with bag and slot")
	world.bags[0][4] = nil
	world.bags[0][25] = { id = 3003, set = true }
	world.bags[1][2] = { id = 3003 }
	world.now = world.now + 1
	M:PickUpForRoom(entry)
	Check(#world.pickups == 0 and world.printed[1]:find("no longer in your bags", 1, true), "not the copy in an equipment set, not one in a herb bag")
	world.bags[0][24] = { id = 3003 }
	world.now = world.now + 1
	M:PickUpForRoom(entry)
	Check(world.pickups[1] == "0:24", "a plain copy is picked up")
end

-- /eui room, Show now, defaults, Minimal and options.
do
	local M = Setup()
	StandardWorld()
	local room = test.commands.room
	Check(room and room.group == "Tools" and room.usage ~= "", "/eui room is a command")
	room.fn()
	Check(world.printed[1] == "off: QoL" and #world.alerts == 0, "module off: /eui room says so")
	Enable(M)
	room.fn()
	Check(#world.alerts == 1 and LastAlert().sound == nil, "/eui room shows the card, quiet")
	Check(M.defaults.bagSpace == true and M.defaults.bagSpaceFree == 3 and M.defaults.bagSpaceSound == "none", "defaults: on, 3 free, no sound")
	Check(test.E.styles.QoL[1].settings.bagSpace == false and test.E.styles.QoL[2].settings.bagSpace == nil, "Minimal turns it off")
	local rows = test.options[1].rows
	Check(test.options[1].tab == "Sound and misc" and rows[1].type == "header", "a section on the Sound and misc tab")
	for _, row in ipairs(rows) do
		if row.type ~= "header" then
			Check(type(row.desc) == "string" and row.desc ~= "", "the option has a description: " .. tostring(row.label))
		end
		if row.key then Check(M.defaults[row.key] ~= nil, "the option has a default: " .. row.key) end
		if row.key and row.key ~= "bagSpace" then Check(row.dependsOn == "bagSpace", "it waits for the switch: " .. row.key) end
	end
	for _, row in ipairs(rows) do
		if row.type == "execute" then
			local before = #world.alerts
			row.func()
			Check(#world.alerts == before + 1, "Show now shows the card")
		end
	end
	local skip = M.BAG_SPACE_SKIP_CLASS
	Check(skip[0] and skip[5] and skip[6] and skip[9] and skip[11] and skip[12] and skip[13] and not skip[7] and not skip[15],
		"left out: consumables, reagents, ammo, recipes, quivers, quest items, keys")
end

print(("%d checks passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
