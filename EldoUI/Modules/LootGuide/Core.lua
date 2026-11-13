-- EldoUI Loot Guide: a loot journal, best-in-slot planner and wishlist in
-- one window, plus loot lines in item tooltips.
--
-- This file is the module shell every Loot Guide page builds on:
--   * the module and its settings (E.db.modules.LootGuide)
--   * per-character data in EldoUIDB.lootGuide[charKey] (shared with the
--     scoring engine, which keeps `rating` and `spec` there) and an
--     account cache in EldoUIDB.lootGuideCache, with schema migrations
--   * a message bus with one debounced redraw (LG:On / LG:Fire)
--   * an event dispatcher so the module's files share one module object
--   * the page registry (LG:RegisterPage): pages land one issue at a time,
--     and a page that is not built yet has no tab, no command and no option
--     (the Catalog page exists only while a section is registered)
--   * slash commands, the addon compartment entry, the "Loot Guide"
--     datatext and the key binding names
--   * the wishlist and the two plan sets (per character)
--
-- The other files reach this table as E.LootGuide (no locals shared across
-- files, so the planned EldoUI_LootGuide addon folder is a plain move).
--
-- Rules (Midnight / Forever): presentation only. Nothing here acts for the
-- player; loot rolls stay manual (RollOnLoot is never called). The window
-- is a plain frame, not protected, and hides when combat starts.
local _, E = ...
local L = E.L

-- luacheck: globals SLASH_ELDOUILOOTGUIDE1 SLASH_ELDOUILOOTGUIDE2

local PAGE_KEYS = { "foryou", "journal", "world", "bis", "wishlist", "catalogue", "database" }

local M = E:NewModule("LootGuide", {
	title = "Loot Guide",
	desc = "Loot journal, best-in-slot sets, wishlist and loot lines in item tooltips.",
	category = "Items & Economy",
	conflicts = { "Lootified" },
	frames = { "EldoUILootGuide", "EldoUILootGuideMap", "EldoUI_LootCheck" },
	movers = { "EldoUI_LootCheck" },
	blizzard = {},
	savedKeys = {
		"profile.modules.LootGuide", "EldoUIDB.lootGuide", "EldoUIDB.lootGuideCache",
		"EldoUIDB.lootGuideLists", "EldoUIDB.lootGuideTours",
	},
	optionsPage = "module:LootGuide",
	presets = { "Atlas", "Collector", "Compact", "EldoUI", "Leveller", "Quiet", "Raider" },
	reload = false,
	defaults = {
		style = "EldoUI",
		startPage = "foryou",  -- a page key, or "last"
		pages = { foryou = true, journal = true, world = true, bis = true, wishlist = true, catalogue = true, database = true },
		autoOpen = true,       -- inside a dungeon the window opens on it
		density = "comfortable",
		scale = 1,
		transparent = false,
		sounds = true,
		dropRates = "both",    -- off, classic, seen, both (tooltips and lists)
		includeRaids = false,  -- For You and suggestions also count raids
		levelWindow = 3,       -- levels around an instance that count as "right for you"
		minQuality = 2,        -- Journal and lists hide items below this quality
		wishAlert = true,      -- tell when a wishlist item is in loot, a roll or the dungeon you enter
		wishSound = "eldo:Tada",
		wishRoute = "auto",    -- auto, lane, banner, chat
		rollBox = true,        -- gain and a roll suggestion beside each loot roll (advice only)
		suggest = true,        -- the Need/Greed/Pass word in that box (a label)
		check = "ALT",         -- item check card: ALT, CTRLALT or OFF
		mapEntrances = true,   -- dungeon entrance pins on the world map
		mapBosses = true,      -- numbered boss markers on dungeon maps
		craftOwnFirst = true,  -- Catalog > Crafting: your professions first
		craftShowGrey = true,  -- ... also recipes that no longer give skill
		repShowAll = false,    -- Catalog > Reputation: factions you have not met
		pvpIncome = 0,         -- weekly honor for the planner; 0 = your recent weeks
		setsMyClass = true,    -- Catalog > Sets: your own class's sets
		collectHideLearned = false, -- Collections: only what you have not learned
		phaseBadges = true,    -- "P3" on loot from a later content phase
		phaseOverride = "auto", -- the phase that counts as out now
		simSpeed = "fast",     -- simulator time per frame: smooth 4 ms, fast 8 ms, turbo 16 ms
		tipSources = { drops = true, quests = true, vendors = true, reputation = true, pvp = true, crafting = true, sets = true },
	},
})
E.LootGuide = M
M.PAGE_KEYS = PAGE_KEYS
M.SCALE_MIN, M.SCALE_MAX = 0.7, 1.5

-- Rows per density (DESIGN.md: 16-20 px in lists).
M.ROW_HEIGHT = { comfortable = 20, compact = 16 }

---------------------------------------------------------------------------
-- Per-character data and the account cache
---------------------------------------------------------------------------
local CHAR_SCHEMA = 1
local CACHE_SCHEMA = 1

-- The loot list presets the first-run card offers. "realistic" is what a
-- character can plan on; "everything" also counts rares, world drops and
-- PvP rewards. One key per list source chip (LG.SOURCE_CHIPS, Rank.lua).
M.LIST_PRESETS = {
	realistic = { quests = true, dungeons = true, crafted = true, rares = false, world = false,
		vendor = true, reputation = true, pvp = false },
	everything = { quests = true, dungeons = true, crafted = true, rares = true, world = true,
		vendor = true, reputation = true, pvp = true },
}

local function NewSet(index)
	return { name = (L["Set %d"]):format(index), slots = {} }
end

-- The load check of a character's record (Core/Database.lua, the saved
-- data registry): a value of the wrong kind is set aside, never replaced;
-- the sets list closes up a gap in its order.
local function CheckChar(data, C)
	for _, key in ipairs({ "wishlist", "list", "wishLists", "shownLists", "ui", "tours" }) do C.Table(data, key) end
	local sets = C.List(data, "sets")
	for index, set in ipairs(sets) do
		if type(set) ~= "table" then
			C.Keep("sets." .. index, set, "Expected a table.")
			sets[index] = NewSet(index)
		elseif set.slots ~= nil and type(set.slots) ~= "table" then
			C.Keep("sets." .. index .. ".slots", set.slots, "Expected a table.")
			set.slots = nil
		end
	end
	if data.list.sources ~= nil then C.Table(data.list, "sources", "list.sources") end
	C.Number(data.list, "minChance", "list.minChance")
	if data.activeList ~= nil and type(data.activeList) ~= "string" then
		C.Keep("activeList", data.activeList, "Expected a text.")
		data.activeList = nil
	end
end
E:RegisterStore("lootGuide", { perKey = true, title = "Loot Guide of %s", version = CHAR_SCHEMA, validate = CheckChar })

-- Fill in what an older (or brand new) record lacks. Runs once per login.
local function MigrateChar(data, charKey)
	E:MigrateStore("lootGuide", data, charKey)
	if type(data.wishlist) ~= "table" then data.wishlist = {} end
	if type(data.sets) ~= "table" then data.sets = {} end
	for index = 1, 2 do
		if type(data.sets[index]) ~= "table" then data.sets[index] = NewSet(index) end
		if type(data.sets[index].slots) ~= "table" then data.sets[index].slots = {} end
	end
	if type(data.list) ~= "table" then data.list = {} end
	if type(data.list.sources) ~= "table" then data.list.sources = CopyTable(M.LIST_PRESETS.realistic) end
	-- Source chips added later (vendor, reputation, PvP) start as the
	-- character's preset has them.
	local preset = M.LIST_PRESETS[data.list.preset or ""] or M.LIST_PRESETS.realistic
	for chip, on in pairs(preset) do
		if data.list.sources[chip] == nil then data.list.sources[chip] = on end
	end
	data.list.minChance = tonumber(data.list.minChance) or 0
	-- Several wishlists: the main list stays data.wishlist; more
	-- lists per character in data.wishLists, account lists in
	-- EldoUIDB.lootGuideLists. activeList gets the stars, shownLists are
	-- marked too.
	if type(data.wishLists) ~= "table" then data.wishLists = {} end
	if type(data.shownLists) ~= "table" then data.shownLists = {} end
	if type(data.activeList) ~= "string" then data.activeList = "main" end
	if type(data.ui) ~= "table" then data.ui = {} end
	if type(data.tours) ~= "table" then data.tours = {} end
	-- Wishlist entries were plain `true` in early test builds.
	for itemID, entry in pairs(data.wishlist) do
		if entry == true then data.wishlist[itemID] = { added = time() } end
	end
	return data
end

-- EldoUIDB.lootGuide[charKey]; nil before the saved variables exist.
function M:Char()
	if type(EldoUIDB) ~= "table" or not E.charKey then return end
	if type(EldoUIDB.lootGuide) ~= "table" then EldoUIDB.lootGuide = {} end
	local data = EldoUIDB.lootGuide[E.charKey]
	if type(data) ~= "table" then
		data = {}
		EldoUIDB.lootGuide[E.charKey] = data
	end
	if not self.charMigrated or self.charMigrated ~= data then
		self.charMigrated = data
		MigrateChar(data, E.charKey)
	end
	return data
end

-- EldoUIDB.lootGuideCache: window geometry and caches keyed by game build
-- and client language (a new build or language starts the caches over,
-- geometry is kept).
function M:Cache()
	if type(EldoUIDB) ~= "table" then return {} end
	local cache = EldoUIDB.lootGuideCache
	if type(cache) ~= "table" then
		cache = {}
		EldoUIDB.lootGuideCache = cache
	end
	if not self.cacheChecked then
		self.cacheChecked = true
		local build = select(2, GetBuildInfo())
		local locale = GetLocale()
		if cache.schema ~= CACHE_SCHEMA or cache.build ~= build or cache.locale ~= locale then
			local window = type(cache.window) == "table" and cache.window or nil
			local simWindow = type(cache.simWindow) == "table" and cache.simWindow or nil
			wipe(cache)
			cache.window, cache.simWindow = window, simWindow
			cache.schema, cache.build, cache.locale = CACHE_SCHEMA, build, locale
		end
	end
	return cache
end

-- Window state the player never sets as an option (last page, filters).
function M:UI()
	local data = self:Char()
	return data and data.ui or {}
end

---------------------------------------------------------------------------
-- Message bus: LG:Fire("wishlist") ... one redraw a moment later.
-- Messages: items, wishlist, sets, spec, gear, list, bags, quests, player,
-- settings, data, pages, rank.
---------------------------------------------------------------------------
local listeners = {}   -- key -> fn(changed) where changed = { [message] = true }
local pending = {}
local flushQueued = false

function M:On(key, fn)
	listeners[key] = fn
end

function M:Off(key)
	listeners[key] = nil
end

local function Flush()
	flushQueued = false
	local changed = pending
	pending = {}
	for key, fn in pairs(listeners) do
		local ok, err = pcall(fn, changed)
		if not ok then geterrorhandler()(("EldoUI Loot Guide listener %s: %s"):format(tostring(key), tostring(err))) end
	end
end

function M:Fire(message)
	pending[message or "settings"] = true
	if flushQueued then return end
	flushQueued = true
	C_Timer.After(0.1, Flush)
end

---------------------------------------------------------------------------
-- Events: every file of the module registers here, one game event handler
-- per event fans out to them.
---------------------------------------------------------------------------
local eventHandlers = {}  -- event -> { key -> fn(event, ...) }

local function Dispatch(_, event, ...)
	local list = eventHandlers[event]
	if not list then return end
	for key, fn in pairs(list) do
		local ok, err = pcall(fn, event, ...)
		if not ok then geterrorhandler()(("EldoUI Loot Guide %s (%s): %s"):format(event, tostring(key), tostring(err))) end
	end
end

function M:Listen(event, key, fn)
	eventHandlers[event] = eventHandlers[event] or {}
	eventHandlers[event][key] = fn
	if self.active then self:RegisterEvent(event, Dispatch) end
end

local function RegisterAll()
	for event in pairs(eventHandlers) do M:RegisterEvent(event, Dispatch) end
end

local function UnregisterAll()
	for event in pairs(eventHandlers) do M:UnregisterEvent(event) end
end

---------------------------------------------------------------------------
-- Pages
-- LG:RegisterPage(key, {
--     title   = "Journal",
--     order   = 20,
--     command = "journal", usage = "[instance]  ...",  -- /eui journal
--     create  = function(content) return frame end,    -- once, on first show
--     show    = function(frame, arg) end,              -- arg from a route
--     hide    = function(frame) end,
--     count   = function() return n end,               -- number on the tab
--     alias   = function(text) return arg end,         -- /lg <text> lookups
--     instanceRoute = function(mapID) return arg end,  -- autoOpen inside a dungeon
--     empty   = function() return title, text end,     -- designed empty state
--     run     = function(arg) return handled end,       -- words the page handles itself
--     hidden  = true,                                   -- no tab (search, item page)
-- })
-- Pages appear in the window, the "Open on" and "Pages" options and the
-- slash commands as soon as they register.
---------------------------------------------------------------------------
local pages, pageOrder = {}, {}

local function SortPages()
	table.sort(pageOrder, function(a, b)
		local pa, pb = pages[a], pages[b]
		if (pa.order or 50) ~= (pb.order or 50) then return (pa.order or 50) < (pb.order or 50) end
		return a < b
	end)
end

function M:RegisterPage(key, def)
	assert(type(key) == "string" and type(def) == "table", "LootGuide:RegisterPage(key, def)")
	def.key = key
	if not pages[key] then table.insert(pageOrder, key) end
	pages[key] = def
	SortPages()
	if def.command and E.AddCommand then
		-- The usage and the page title are English keys, translated in the help.
		E:AddCommand(def.command, def.usage or E.Key("open the Loot Guide on %s"), function(arg)
			M:Command(key, arg)
		end, "Tools", not def.usage and function() return def.title or key end or nil)
	end
	self:Fire("pages")
end

-- A page that goes away again (the Catalog when its last section leaves).
function M:UnregisterPage(key)
	if not pages[key] then return end
	pages[key] = nil
	for index, other in ipairs(pageOrder) do
		if other == key then table.remove(pageOrder, index) break end
	end
	self:Fire("pages")
end

function M:GetPage(key)
	return pages[key]
end

-- Is a page built and switched on?
function M:IsPageOn(key)
	if not pages[key] then return false end
	local on = self.db and self.db.pages
	return not (type(on) == "table" and on[key] == false)
end

-- Built pages in tab order; `all` includes the ones switched off. Pages
-- with `hidden = true` (Search, the item page) have no tab, no switch and
-- no "Open on" entry; they open from the search box, links and commands.
function M:Pages(all, withHidden)
	local list = {}
	for _, key in ipairs(pageOrder) do
		local page = pages[key]
		if (withHidden or not page.hidden) and (all or self:IsPageOn(key)) then list[#list + 1] = page end
	end
	return list
end

-- The page the window starts on outside a dungeon (nil: no page is built).
function M:StartPage()
	local start = self.db.startPage
	if start == "last" then start = self:UI().lastPage end
	if start and self:IsPageOn(start) then return start end
	local first = self:Pages()[1]
	return first and first.key
end

---------------------------------------------------------------------------
-- The two plan sets (per character). The wishlists live in Wishlist.lua.
---------------------------------------------------------------------------
-- Equipment slots an item can go in, from its inventory type.
local SLOTS_BY_TYPE = {
	INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_BODY = { 4 },
	INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 },
	INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 },
	INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 }, INVTYPE_WEAPON = { 16, 17 },
	INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 }, INVTYPE_WEAPONOFFHAND = { 17 },
	INVTYPE_SHIELD = { 17 }, INVTYPE_HOLDABLE = { 17 }, INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 },
	INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 }, INVTYPE_TABARD = { 19 },
}
M.SLOTS_BY_TYPE = SLOTS_BY_TYPE

function M:ItemSlots(itemID)
	local equipLoc = select(4, C_Item.GetItemInfoInstant(itemID))
	if issecretvalue and issecretvalue(equipLoc) then return end
	return SLOTS_BY_TYPE[equipLoc or ""]
end

-- Which plan sets hold the item: { 1 = true, 2 = true } or nil.
function M:SetsWith(itemID)
	local data = self:Char()
	itemID = tonumber(itemID)
	if not data or not itemID then return end
	local found
	for index = 1, 2 do
		for _, id in pairs(data.sets[index].slots) do
			if id == itemID then
				found = found or {}
				found[index] = true
			end
		end
	end
	return found
end

-- Put an item in plan set 1 or 2: the first empty slot it fits, else the
-- first slot (rings, trinkets and one-hand weapons have two).
function M:PutInSet(index, itemID)
	local data = self:Char()
	itemID = tonumber(itemID)
	local slots = itemID and self:ItemSlots(itemID)
	if not data or not slots or not data.sets[index] then return false end
	local set = data.sets[index].slots
	local target = slots[1]
	for _, slot in ipairs(slots) do
		if set[slot] == itemID then return true end
		if set[slot] == nil then target = slot break end
	end
	-- A two-hander leaves no room for an off hand.
	local equipLoc = select(4, C_Item.GetItemInfoInstant(itemID))
	if equipLoc == "INVTYPE_2HWEAPON" then set[17] = nil end
	set[target] = itemID
	self:Fire("sets")
	return true
end

function M:RemoveFromSets(itemID)
	local data = self:Char()
	itemID = tonumber(itemID)
	if not data or not itemID then return end
	for index = 1, 2 do
		for slot, id in pairs(data.sets[index].slots) do
			if id == itemID then data.sets[index].slots[slot] = nil end
		end
	end
	self:Fire("sets")
end

function M:SetName(index)
	local data = self:Char()
	local set = data and data.sets[index]
	return set and set.name or (L["Set %d"]):format(index)
end

---------------------------------------------------------------------------
-- Commands
---------------------------------------------------------------------------
local function Accent()
	local r, g, b = unpack(E.media.accentText)
	return ("|cff%02x%02x%02x"):format(r * 255, g * 255, b * 255)
end
M.AccentHex = Accent

local function NotActive()
	if M.active then return false end
	E:Print(E:ModuleOffHint("LootGuide"))
	return true
end

-- /eui <page command> [arg]
function M:Command(key, arg)
	if NotActive() then return end
	if not self:IsPageOn(key) then
		E:Print((L["The %s page is switched off on the Loot Guide settings page."]):format(pages[key] and pages[key].title or key))
		return
	end
	arg = arg ~= "" and arg or nil
	local page = pages[key]
	-- Words a page handles itself ("/eui wishlist add <link>").
	if arg and page.run then
		local ok, handled = pcall(page.run, arg)
		if not ok then geterrorhandler()(handled) end
		if ok and handled then return end
	end
	-- Let the page turn a typed word into its argument ("dm" -> an instance).
	if arg and page.alias then
		local ok, resolved = pcall(page.alias, arg)
		if ok and resolved then arg = resolved end
	end
	self:Open(key, arg)
end

-- /lg, /lootguide, /eui guide
-- No word: toggle (inside a dungeon it opens on that dungeon).
-- data:  what the Loot Guide knows (data source, version, counts)
-- reset: window position and size back to the default
-- other text: an instance alias ("dm") or a search, when those pages exist
function M:SlashCommand(msg)
	if NotActive() then return end
	msg = strtrim(msg or "")
	local word = msg:lower()
	if word == "" then
		self:Toggle()
	elseif word == "data" then
		self:PrintDataStatus()
	elseif word == "reset" then
		self:ResetWindow()
		E:Print(L["Loot Guide window position and size reset."])
	elseif word == "help" then
		self:PrintHelp()
	else
		for _, page in ipairs(self:Pages()) do
			if page.alias then
				local ok, arg = pcall(page.alias, msg)
				if ok and arg then
					self:Open(page.key, arg)
					return
				end
			end
		end
		if self:IsPageOn("search") then
			self:Open("search", msg)
			return
		end
		E:Print((L["Nothing in the Loot Guide matches %q."]):format(msg))
	end
end

function M:PrintHelp()
	local a = Accent()
	E:Print(L["Loot Guide commands:"])
	print(("  %s/lg|r  %s"):format(a, L["open or close the window"]))
	print(("  %s/lg data|r  %s"):format(a, L["where the loot data comes from"]))
	print(("  %s/lg reset|r  %s"):format(a, L["window position and size back to the default"]))
	for _, page in ipairs(self:Pages(false, true)) do
		if page.command then print(("  %s/eui %s|r  %s"):format(a, page.command, E:Translate(page.usage or page.title or page.key))) end
	end
end

SLASH_ELDOUILOOTGUIDE1 = "/lg"
SLASH_ELDOUILOOTGUIDE2 = "/lootguide"
SlashCmdList.ELDOUILOOTGUIDE = function(msg) M:SlashCommand(msg) end

E:AddCommand("guide", "[data | reset | <text>]  open or close the Loot Guide (also /lg)", function(arg)
	M:SlashCommand(arg)
end, "Tools")

-- /eui lootguide: the module's own word. on / off / toggle switch the
-- module (like any /eui <module>), nothing opens its settings page, other
-- words work as in /lg.
local function Switch(word)
	if word == "on" or word == "enable" then return true end
	if word == "off" or word == "disable" then return false end
	if word == "toggle" then return not M:IsEnabled() end
end

function M:ModuleCommand(msg)
	msg = strtrim(msg or "")
	local word = msg:lower()
	if word == "" then
		E:ToggleConfig("module:LootGuide")
		return
	end
	local switch = Switch(word)
	if switch == nil then
		self:SlashCommand(msg)
		return
	end
	local _, conflict = E:GetModuleConflict(self)
	if switch and conflict then
		E:Print((L["The Loot Guide stays off while %s is loaded."]):format(conflict))
		return
	end
	E:SetModuleEnabled("LootGuide", switch)
	E:Print((switch and L["Loot Guide %son|r."] or L["Loot Guide %soff|r."]):format(switch and E:TextHex("good") or E:TextHex("bad")))
	if E.RefreshConfig then E:RefreshConfig() end
end

E:AddCommand("lootguide", "[on | off | toggle | data | reset | <text>]  the Loot Guide: switch it, or same as /lg", function(arg)
	M:ModuleCommand(arg)
end, "Tools")

-- Called by the key bindings (Bindings.xml at the addon root,
-- Core/Bindings.lua). M:Toggle (UI/Window.lua) opens or closes the window.
function M:BindingToggle()
	if NotActive() then return end
	self:Toggle()
end

function M:BindingBiS()
	if NotActive() then return end
	if self:IsPageOn("bis") then self:Open("bis") else self:Toggle() end
end

---------------------------------------------------------------------------
-- Addon compartment and datatext
-- Left click opens the window, Shift + left click opens the page you left
-- (even inside a dungeon, where a plain click opens that dungeon), right
-- click opens Best in Slot (or the settings page while Best in Slot is not
-- there or switched off).
---------------------------------------------------------------------------
local ICON = "Interface\\Icons\\INV_Misc_Book_09"
M.ICON = ICON

-- Shift-click: the last page, skipping "Open the dungeon you are in".
function M:OpenLast()
	if self:IsOpen() then
		self:Close()
		return
	end
	local last = self:UI().lastPage
	if last and self:IsPageOn(last) then self:Open(last) else self:Open(self:StartPage()) end
end

function M:Click(mouseButton)
	if NotActive() then return end
	if mouseButton == "RightButton" then
		self:AltClick()
	elseif IsShiftKeyDown() then
		self:OpenLast()
	else
		self:Toggle()
	end
end

function M:AltClick()
	if self:IsPageOn("bis") then
		self:Open("bis")
	else
		self:Toggle()
	end
end

-- The lines the compartment entry and the datatext show in their tooltip.
function M:FillSummaryTooltip(tooltip)
	E.UIKit.TipTitle(tooltip, L["Loot Guide"])
	if not self.active then
		E.UIKit.TipText(tooltip, L["Switched off."])
		return
	end
	local wished = self:WishlistOn() and self:WishlistCount() or 0
	if wished > 0 then E.UIKit.TipPair(tooltip, L["Wishlist"], tostring(wished)) end
	local fit = self.InstancesForLevel and self:InstancesForLevel(UnitLevel("player"), 3)
	if fit and #fit > 0 then
		local names = {}
		for _, entry in ipairs(fit) do names[#names + 1] = entry.name end
		E.UIKit.TipPair(tooltip, L["For your level"], table.concat(names, ", "))
	end
	if self.DataStatusText then
		E.UIKit.TipPair(tooltip, L["Loot data"], self:DataStatusText(true))
	end
	local simText = self.SimSummary and self:SimSummary()
	if simText then E.UIKit.TipPair(tooltip, L["Simulator"], simText) end
	tooltip:AddLine(" ")
	-- Right-click opens Best in Slot; without that page it does what a
	-- left-click does, so only the left-click is named.
	if self:IsPageOn("bis") then
		E:TooltipHint(tooltip, { L["Left-click"], L["open"] }, { L["Right-click"], L["Best in Slot"] })
	else
		E:TooltipHint(tooltip, { L["Click"], L["open"] })
	end
	if #self:Pages() > 0 then
		E:TooltipHint(tooltip, { L["Shift-click"], L["the page you left, even inside a dungeon"] })
	end
end

-- Another part of the guide may take the compartment entry over while it
-- runs (My Adventure: the entry then reads "Journal"):
--   M:SetCompartmentOwner(def)   def = { text = fn, active = fn,
--                                click = fn(mouseButton), tooltip = fn(tooltip) }
--   M:SetCompartmentOwner(nil)   gives it back
--   M:SyncCompartment()          the entry's text again (the compartment
--                                reads it each time its menu opens)
-- One entry either way, so the compartment never lists the guide twice.
function M:CompartmentOwner()
	local owner = self.compartmentOwner
	if not owner then return nil end
	if type(owner.active) == "function" then
		local ok, active = pcall(owner.active)
		if not (ok and active) then return nil end
	end
	return owner
end

function M:SetCompartmentOwner(def)
	self.compartmentOwner = type(def) == "table" and def or nil
	self:SyncCompartment()
end

function M:SyncCompartment()
	local data = self.compartmentData
	if not data then return end
	local owner = self:CompartmentOwner()
	local text = owner and type(owner.text) == "function" and owner.text()
	data.text = type(text) == "string" and text ~= "" and text or L["Loot Guide"]
end

function M:CompartmentClick(mouseButton)
	local owner = self:CompartmentOwner()
	if owner and type(owner.click) == "function" then
		owner.click(mouseButton)
	else
		self:Click(mouseButton)
	end
end

function M:FillCompartmentTooltip(tooltip)
	local owner = self:CompartmentOwner()
	if owner and type(owner.tooltip) == "function" then
		owner.tooltip(tooltip)
	else
		self:FillSummaryTooltip(tooltip)
	end
end

function M:RegisterCompartment()
	if self.compartmentDone then return end
	local frame = _G.AddonCompartmentFrame
	if not (frame and type(frame.RegisterAddon) == "function") then return end
	self.compartmentDone = true
	self.compartmentData = {
		text = L["Loot Guide"],
		icon = ICON,
		notCheckable = true,
		func = function(_, input)
			M:CompartmentClick(type(input) == "table" and input.buttonName or nil)
		end,
		funcOnEnter = function(button)
			GameTooltip:SetOwner(button, "ANCHOR_LEFT")
			M:FillCompartmentTooltip(GameTooltip)
			GameTooltip:Show()
		end,
		funcOnLeave = function() GameTooltip:Hide() end,
	}
	self:SyncCompartment()
	frame:RegisterAddon(self.compartmentData)
end

function M:RegisterDataText()
	if self.dataTextDone or not E.RegisterDataText then return end
	self.dataTextDone = true
	E:RegisterDataText("LootGuide", {
		title = L["Loot Guide"],
		events = { "PLAYER_LEVEL_UP" },
		poll = true,
		interval = 5,
		text = function()
			if not M.active then return E:TextHex("secondary") .. L["Loot Guide"] .. "|r" end
			local sim = M.SimDataText and M:SimDataText()
			if sim then return sim end
			local wished = M:WishlistOn() and M:WishlistCount() or 0
			if wished > 0 then return (L["Loot Guide"] .. " " .. E:TextHex("secondary") .. "(%d)|r"):format(wished) end
			return L["Loot Guide"]
		end,
		tooltip = function(tooltip) M:FillSummaryTooltip(tooltip) end,
		onClick = function(_, mouseButton) M:Click(mouseButton) end,
	})
end

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------
function M:OnInitialize()
	self:Char()
	self:Cache()
end

function M:OnEnable()
	self:Char()
	RegisterAll()
	self:RegisterCompartment()
	self:RegisterDataText()
	if self.OnEnableData then self:OnEnableData() end
	if self.OnEnableTooltip then self:OnEnableTooltip() end
	if self.OnEnableWindow then self:OnEnableWindow() end
	if self.OnEnableCheck then self:OnEnableCheck() end
	if self.HookCheckClicks then self:HookCheckClicks() end
	if self.OnEnableMaps then self:OnEnableMaps() end
	self:Fire("settings")
end

function M:OnDisable()
	UnregisterAll()
	if self.OnDisableWindow then self:OnDisableWindow() end
	if self.OnDisableTooltip then self:OnDisableTooltip() end
	if self.OnDisableMaps then self:OnDisableMaps() end
	local card = self.CheckCard and self:CheckCard()
	if card then card:Hide() end
end

-- Settings, styles, profile switches and theme changes (accent, art style)
-- all land here.
function M:OnProfileChanged()
	if not self.active then return end
	if self.ApplyWindowSettings then self:ApplyWindowSettings() end
	if self.ClearTooltipCache then self:ClearTooltipCache() end
	self:Fire("settings")
end
