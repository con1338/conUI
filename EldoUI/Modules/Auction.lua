-- EldoUI Auction House: Shopping List, Quick Sell and Cancel Undercut tabs added to the
-- game's auction window, in the EldoUI look, plus a price database built
-- from the player's searches (EldoUI's tabs and the game's own Buy tab) and
-- full scans, crafting costs and
-- disenchant values in the tooltip.
--
-- Blizzard element "auction-house": EldoUI only changes the
-- auction window when the player ticks "Let EldoUI change this" under
-- Blizzard UI:
--   skin     EldoUI look for Blizzard's own screens (reload to undo)
--   move     mover and scale for the window
--   improve  EldoUI's Shopping List / Quick Sell / Cancel Undercut tabs and the tab the
--            window opens on
-- Saved prices and the tooltip lines don't change Blizzard's window, so they
-- follow this module's own switches.
--
-- Rules this module keeps (the auction house is protected on Forever):
--   * Every Post, Buy and Cancel comes from one click of the player, one
--     action per click. Nothing is queued to act later, nothing buys or bids
--     on its own. Buying always happens in Blizzard's own buy screen.
--   * The auction house is only asked for data when the player presses
--     Search / Scan / Full scan / Refresh or clicks an item to sell, and
--     every request waits for the game's throttle
--     (AUCTION_HOUSE_THROTTLED_SYSTEM_READY). A full scan is one
--     C_AuctionHouse.ReplicateItems() call, which Blizzard allows once every
--     15 minutes.
--   * Blizzard's window is never reparented or given new fields; EldoUI's
--     panel lies on top of it while one of its tabs is open. Only then are
--     the few Blizzard screens it replaces put away (NATIVE_SCREENS: the
--     Buy, Sell and Auctions screens and the window title), one by one, and
--     each comes back exactly as it was when a Blizzard tab is picked, the
--     window closes or the Improve switch goes off.
--
-- WoW: Forever uses the modern auction house (C_AuctionHouse, Buy / Sell /
-- Auctions tabs) with 2 / 8 / 24 hour durations and copper-exact prices.
-- Blizzard_AuctionHouseUI loads on Forever ("mainline" game type with a
-- Camelot data file); the classic AuctionFrame does not exist there, so
-- EldoUI has no classic auction house path.
-- Written from scratch for EldoUI; no code, text or media from other addons.
local _, E = ...
local L = E.L

local M = E:NewModule("Auction", {
	title = "Auction House",
	desc = "Shopping lists, quick selling with price checks, canceling, full scans, crafting costs and a price database for the auction house.",
	category = "Items & Economy",
	conflicts = { "Auctionator", "aux-addon" },
	frames = { "EldoUI_AuctionPanel", "EldoUI_AuctionTabRail" },
	movers = { "EldoUI_AuctionWindow" },
	blizzard = { "auction-house" },
	savedKeys = { "profile.modules.Auction", "EldoUIDB.auction" },
	optionsPage = "module:Auction",
	presets = { "Clean", "Compact", "Large", "Ledger", "Overview", "Standard" },
	defaults = {
		undercutMode = "percent",   -- "percent" or "fixed"
		undercutPercent = 0,        -- percent below the lowest price
		undercutFixed = 1,          -- copper below the lowest price
		duration = 2,               -- 1 short, 2 medium, 3 long
		rememberPrice = true,       -- use your last posted price when nobody else sells the item
		defaultTab = "none",        -- open on this EldoUI tab, stored as: none, Shopping, Selling, Cancelling (spelling: ok)
		tooltip = true,
		tooltipVendor = true,
		tooltipDisenchant = true,
		knownTint = true,           -- tint recipes, mounts, pets and toys you already have
		tooltipCrafting = true,
		craftingPrices = true,      -- remember recipes when a profession window is open
		-- Look (style presets set these)
		rowHeight = 20,
		iconSize = 36,
		fontSize = 13,
		zebra = true,
		headerAccent = true,
		moneyStyle = "general",     -- general (Fonts and text > Money) / icons / letters / short
	},
})

local floor, max, min = math.floor, math.max, math.min
local AH = C_AuctionHouse
local RECENT_MAX = 30
local HISTORY_DAYS = 14
local POST_HISTORY_MAX = 100
local IS_FOREVER = (function()
	local build = select(4, GetBuildInfo())
	return build and build >= 16000 and build < 20000
end)()
-- Duration index (what the API takes) -> hours, for the labels.
local DURATION_HOURS = IS_FOREVER and { 2, 8, 24 } or { 12, 24, 48 }

local TABS = { "Shopping", "Selling", "Cancelling" }
-- Names that say what each tab adds next to Blizzard's Buy, Sell and
-- Auctions tabs; the keys stay the stored ones.
local TAB_TITLES = E:TranslateValues({ Shopping = E.Key("Shopping List"), Selling = E.Key("Quick Sell"), Cancelling = E.Key("Cancel Undercut") })

---------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------
local function Call(fn, ...)
	if type(fn) ~= "function" then return false end
	return pcall(fn, ...)
end

-- Returns every result of the function, or nil when it is missing or
-- fails. All of them: GetReplicateItemInfo has 18 (buyout is the 10th,
-- the item ID the 17th).
local function Results(ok, ...)
	if ok then return ... end
end

local function Get(fn, ...)
	if type(fn) ~= "function" then return nil end
	return Results(pcall(fn, ...))
end

local IsSecret = E.Secret

-- Forever's own auction house shows the required level of weapons and
-- armor instead of their item level (the game's AuctionHouse_
-- ShouldUseRequiredLevel). EldoUI's lists follow it when the game says so.
local function UsesRequiredLevel()
	local fn = _G.AuctionHouse_ShouldUseRequiredLevel
	if type(fn) ~= "function" or not (AH and AH.GetItemKeyRequiredLevel) then return false end
	local ok, use = pcall(fn)
	return ok and use == true
end

-- The level shown after an item's name: the required level (true as the
-- second value) or the item level. Nil for commodities and items without
-- one.
local function ItemKeyLevel(itemKey, commodity)
	if commodity or type(itemKey) ~= "table" then return nil end
	if UsesRequiredLevel() then
		local info = Get(AH.GetItemKeyInfo, itemKey)
		if type(info) == "table" and info.isEquipment == false then return nil end
		local level = Get(AH.GetItemKeyRequiredLevel, itemKey)
		if IsSecret(level) or type(level) ~= "number" or level <= 0 then return nil end
		return level, true
	end
	local level = itemKey.itemLevel
	if IsSecret(level) or type(level) ~= "number" or level <= 1 then return nil end
	return level, false
end

-- An item key's tooltip: the game's sample link first (it carries random
-- suffix stats such as "of the Bear"), else the item key with its
-- required level.
local function SetItemKeyTooltip(tooltip, itemKey)
	if type(itemKey) ~= "table" then return end
	local link = Get(AH and AH.GetItemKeySampleLink, itemKey)
	if not IsSecret(link) and type(link) == "string" and link ~= "" and tooltip.SetHyperlink then
		if Call(tooltip.SetHyperlink, tooltip, link) then return end
	end
	if tooltip.SetItemKey then
		local required = Get(AH and AH.GetItemKeyRequiredLevel, itemKey)
		Call(tooltip.SetItemKey, tooltip, itemKey.itemID, itemKey.itemLevel, itemKey.itemSuffix, required)
	elseif itemKey.itemID then
		tooltip:SetItemByID(itemKey.itemID)
	end
end

local function AHReady()
	if not AH or not AH.IsThrottledMessageSystemReady then return true end
	local ok, ready = pcall(AH.IsThrottledMessageSystemReady)
	return not ok or ready
end

local function PriceSorts()
	local order = Enum.AuctionHouseSortOrder
	if not order then return {} end
	return { { sortOrder = order.Price, reverseSort = false } }
end

local function QualityColor(quality)
	if quality and C_Item.GetItemQualityColor then
		local r, g, b = C_Item.GetItemQualityColor(quality)
		if r then return r, g, b end
	end
	local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
	if color then return color.r, color.g, color.b end
	return 1, 1, 1
end

local function KeyString(itemKey)
	return ("%d:%d:%d:%d"):format(itemKey.itemID or 0, itemKey.itemLevel or 0, itemKey.itemSuffix or 0, itemKey.battlePetSpeciesID or 0)
end

-- Price database key: the item ID, or "p<species>" for caged battle pets.
local function DBKey(itemID, speciesID)
	if speciesID and speciesID > 0 then return "p" .. speciesID end
	return itemID
end

local function DBKeyFromItemKey(itemKey)
	return DBKey(itemKey.itemID, itemKey.battlePetSpeciesID)
end

local function DBKeyFromLink(link, itemID)
	local species = type(link) == "string" and link:match("battlepet:(%d+)")
	if species then return "p" .. species end
	return itemID or (link and C_Item.GetItemInfoInstant and C_Item.GetItemInfoInstant(link))
end

local function VendorPrice(item)
	if not item then return 0 end
	local price = select(11, C_Item.GetItemInfo(item))
	return price or 0
end

-- Money in the Money style (Fonts and text page), or the window's own choice.
local function Money(copper)
	if not copper then return "" end
	return E:FormatMoney(floor(copper + 0.5), M.db and M.db.moneyStyle)
end

local function TimeLeft(seconds)
	if not seconds then return "" end
	if seconds >= 3600 then return L["%dh"]:format(floor(seconds / 3600 + 0.5)) end
	if seconds >= 60 then return L["%dm"]:format(floor(seconds / 60 + 0.5)) end
	return L["%ds"]:format(seconds)
end

local function Today()
	return floor(time() / 86400)
end

---------------------------------------------------------------------------
-- Saved data: EldoUIDB.auction
--   prices[realm][key] = { l = last price, m = lowest of the kept days,
--                          t = time of the last price, d = { [day] = price } }
--   posted[realm][key] = your last posted unit price
--   history[realm]     = { { i = key, p = price, q = quantity, t = time } }
--   packed[realm]      = prices, posted and history of another auction
--                        house as one packed string (below)
--   lists              = { { name = "...", terms = { "..." } } }
--   recent             = { "term", ... }   newest first, at most 30
--   favourites        = { [itemID] = true }
--   chars[charKey]     = { counts = { [itemID] = listed }, updated = time }
--   recipes[itemID]    = crafting costs (below)
--   fullScan, fullScanInfo[realm] = the last full scan and when it ran
-- The Profession Planner adds shopping lists to `lists`; the Alts window
-- and the bags read `chars`. Store() fills a missing part and never
-- replaces one that is there.
---------------------------------------------------------------------------
E:RegisterStore("auction", { owner = "Auction",
	shape = "prices, posted and history per realm (other auction houses packed); lists, recent searches, favorites, recipes; chars per character" })

local function Store()
	EldoUIDB.auction = EldoUIDB.auction or {}
	local store = EldoUIDB.auction
	store.prices = store.prices or {}
	store.posted = store.posted or {}
	store.history = store.history or {}
	store.lists = store.lists or {}
	store.recent = store.recent or {}
	store.favourites = store.favourites or {}
	store.chars = store.chars or {}
	store.packed = store.packed or {}
	return store
end
M.Store = Store

-- Forever groups realms into one auction house per ruleset (PvE, PvP,
-- Hardcore, RP); elsewhere connected realms share one. Faction is kept
-- apart as well.
local function RulesetName()
	local rules = C_GameRules and C_GameRules.IsGameRuleActive
	local enum = Enum.GameRule
	if not rules or not enum then return "PvE" end
	for _, entry in ipairs({ { "PvPRuleset", "PvP" }, { "RPRuleset", "RP" }, { "HardcoreRuleset", "HC" } }) do
		if enum[entry[1]] and Get(rules, enum[entry[1]]) then return entry[2] end
	end
	return "PvE"
end

-- Each auction house is its own market: your faction's, and the neutral
-- one the goblin auctioneers share (Booty Bay, Gadgetzan, Everlook). Prices
-- are kept per house: "<realm> - Alliance", "<realm> - Horde" or
-- "<realm> - Neutral". While a neutral house is open, its prices are the
-- ones read and saved; otherwise your faction's.
local realmName, house
local function RealmKey()
	if not realmName then
		if RegionalUniqueNamesEnabled and Get(RegionalUniqueNamesEnabled) then
			realmName = "Region-" .. RulesetName()
		else
			local connected = {}
			for _, name in ipairs(Get(C_AutoComplete and C_AutoComplete.GetAutoCompleteRealms) or {}) do connected[#connected + 1] = name end
			table.sort(connected)
			realmName = connected[1] or Get(GetNormalizedRealmName) or GetRealmName()
		end
	end
	return ("%s - %s"):format(realmName, house or UnitFactionGroup("player") or "Neutral")
end

-- The house the auctioneer you talk to belongs to: an auctioneer of
-- neither faction runs a neutral house.
local NEUTRAL_CUT, FACTION_CUT = 0.15, 0.05
local function ReadHouse()
	if not UnitExists("npc") then return nil end
	local faction = UnitFactionGroup("npc")
	if IsSecret(faction) then return nil end
	if faction == "Alliance" or faction == "Horde" then return nil end
	return "Neutral"
end
M.ReadHouse = ReadHouse
function M.SetHouse(kind)
	house = kind
end
function M.House()
	return house or "faction"
end
-- The share of a sale the house keeps.
function M.HouseCut()
	return house == "Neutral" and NEUTRAL_CUT or FACTION_CUT
end

---------------------------------------------------------------------------
-- Other auction houses, packed. Only the auction house of the character
-- on hand is read, so every other one is kept as one packed string
-- (packed[houseKey]) instead of thousands of small tables the game reads
-- at each login. A house is unpacked the first time its data is asked
-- for. With the Auction module off, the current house is packed at
-- logout as well. A string that can't be read leaves that house empty;
-- a client without the packing calls keeps the plain tables.
---------------------------------------------------------------------------
local PACK_PREFIX = "EUP1:"
local PACK_PARTS = { p = "prices", o = "posted", h = "history" }

local function Codec()
	local util = C_EncodingUtil
	local method = Enum.CompressionMethod and Enum.CompressionMethod.Deflate
	if util and method and util.SerializeCBOR and util.DeserializeCBOR and util.CompressString
		and util.DecompressString and util.EncodeBase64 and util.DecodeBase64 then
		return util, method
	end
end

local function UnpackHouse(key)
	local store = Store()
	local text = store.packed[key]
	if text == nil then return end
	local util, method = Codec()
	if not util then return end
	store.packed[key] = nil
	local ok, data = pcall(function()
		if type(text) ~= "string" or text:sub(1, #PACK_PREFIX) ~= PACK_PREFIX then error("unknown format") end
		return util.DeserializeCBOR(util.DecompressString(util.DecodeBase64(text:sub(#PACK_PREFIX + 1)), method))
	end)
	if not ok or type(data) ~= "table" then return end
	for short, part in pairs(PACK_PARTS) do
		local value = data[short]
		if type(value) == "table" then
			local target = store[part][key]
			if type(target) ~= "table" then
				store[part][key] = value
			elseif part == "history" then
				-- Newest first: what was posted since comes before the packed list.
				for _, entry in ipairs(value) do target[#target + 1] = entry end
				while #target > POST_HISTORY_MAX do table.remove(target) end
			else
				for item, entry in pairs(value) do
					if target[item] == nil then target[item] = entry end
				end
			end
		end
	end
end

local function PackHouse(key)
	local util, method = Codec()
	if not util or type(key) ~= "string" then return false end
	UnpackHouse(key)
	local store = Store()
	local data, any = {}, false
	for short, part in pairs(PACK_PARTS) do
		local value = store[part][key]
		if type(value) == "table" and next(value) ~= nil then data[short], any = value, true end
	end
	if not any then
		for _, part in pairs(PACK_PARTS) do store[part][key] = nil end
		return false
	end
	local ok, text = pcall(function()
		return PACK_PREFIX .. util.EncodeBase64(util.CompressString(util.SerializeCBOR(data), method))
	end)
	if not ok or type(text) ~= "string" then return false end
	store.packed[key] = text
	for _, part in pairs(PACK_PARTS) do store[part][key] = nil end
	return true
end

-- Houses other than this one that still have plain tables.
local function UnpackedOthers()
	local store, here, list, seen = Store(), RealmKey(), {}, {}
	for _, part in pairs(PACK_PARTS) do
		for key, value in pairs(store[part]) do
			if key ~= here and not seen[key] and type(value) == "table" then
				seen[key] = true
				list[#list + 1] = key
			end
		end
	end
	table.sort(list)
	return list
end

-- One house per frame, so a login never stalls on a large one.
local function PackOthers(now)
	local list = UnpackedOthers()
	if now then
		for _, key in ipairs(list) do PackHouse(key) end
		return
	end
	local index = 0
	local function Step()
		index = index + 1
		if list[index] == nil then return end
		PackHouse(list[index])
		C_Timer.After(0, Step)
	end
	Step()
end

local function PriceDB()
	local prices = Store().prices
	local key = RealmKey()
	UnpackHouse(key)
	prices[key] = prices[key] or {}
	return prices[key]
end

local function PostedDB()
	local posted = Store().posted
	local key = RealmKey()
	UnpackHouse(key)
	posted[key] = posted[key] or {}
	return posted[key]
end

local function PostHistory()
	local history = Store().history
	local key = RealmKey()
	UnpackHouse(key)
	history[key] = history[key] or {}
	return history[key]
end

M.RealmKey, M.PackHouse, M.UnpackHouse, M.PackOthers = RealmKey, PackHouse, UnpackHouse, PackOthers

-- Logout: with the module off, this house is packed too (the module
-- on keeps it as it is, for the next visit).
function M.PackAtLogout()
	if not M.active then PackHouse(RealmKey()) end
end

-- These run whether the module is on or off.
do
	local packer = {}
	E:RegisterEvent("PLAYER_ENTERING_WORLD", function()
		E:UnregisterEvent("PLAYER_ENTERING_WORLD", packer)
		C_Timer.After(5, function() PackOthers() end)
	end, packer)
	E:RegisterEvent("PLAYER_LOGOUT", function() M.PackAtLogout() end, packer)
end

-- The Data section's size line: this house's prices and the packed ones.
function M.SavedPricesText()
	local store, here = Store(), RealmKey()
	local size = E.Characters and E.Characters.Size
	local plain, packed = 0, 0
	if size then
		for _, part in pairs(PACK_PARTS) do plain = plain + size(E.Characters, store[part][here]) end
	end
	for _, text in pairs(store.packed) do
		if type(text) == "string" then packed = packed + #text end
	end
	return L["Saved prices take about %d KB for this realm and faction and %d KB, packed, for the others."]:format(
		math.floor(plain / 1024 + 0.5), math.floor(packed / 1024 + 0.5))
end

local function SavePrice(key, price)
	if not key or not price or price <= 0 then return end
	local db = PriceDB()
	local record = db[key] or {}
	db[key] = record
	local today = Today()
	record.l, record.t = price, time()
	record.d = record.d or {}
	if not record.d[today] or price < record.d[today] then record.d[today] = price end
	local lowest
	for day, value in pairs(record.d) do
		if day <= today - HISTORY_DAYS then
			record.d[day] = nil
		elseif not lowest or value < lowest then
			lowest = value
		end
	end
	record.m = lowest or price
end

-- Lowest price per key seen in one search, saved together.
local function SaveBatch(batch)
	for key, price in pairs(batch) do SavePrice(key, price) end
end

-- A full scan brings tens of thousands of prices: they are written a few
-- hundred per frame so the game never stalls. Whatever is still waiting
-- is written at once on logout.
local SAVES_PER_FRAME = 500
-- The scan's own price tables wait in a queue as they are (the close frame
-- copies nothing); saveKey is the last key written of the first one.
local saveQueue, saveKey = {}, nil
local saveNext = false               -- a step is scheduled
local function SaveSome(limit)
	while limit > 0 do
		local batch = saveQueue[1]
		if not batch then return true end
		local key, price = next(batch, saveKey)
		if key == nil then
			table.remove(saveQueue, 1)
			saveKey = nil
		else
			SavePrice(key, price)
			saveKey = key
			limit = limit - 1
		end
	end
	return saveQueue[1] == nil
end

local function SaveStep()
	saveNext = false
	if not SaveSome(SAVES_PER_FRAME) then
		saveNext = true
		C_Timer.After(0, SaveStep)
	end
end

-- Takes the table over: nothing may change it afterwards.
local function QueueBatch(batch)
	if not next(batch) then return end
	saveQueue[#saveQueue + 1] = batch
	if not saveNext then
		saveNext = true
		C_Timer.After(0, SaveStep)
	end
end

-- Writes every queued price now (on logout).
function M:FlushPrices()
	SaveSome(math.huge)
end

-- True while prices of a full scan are still being written.
function M:IsSavingPrices()
	return saveQueue[1] ~= nil
end

function M:GetPrice(key)
	local record = key and PriceDB()[key]
	return record and record.l, record
end

---------------------------------------------------------------------------
-- Disenchant values
-- What disenchanting an item gives, by quality, item level and armor or
-- weapon, written down from the game's public disenchanting rules for
-- classic-era items (not copied from any addon). The value is the expected
-- worth of those materials at your saved auction prices: chance x average
-- amount x price, summed. Without a saved price for any of the materials
-- no value shows. Plugins may still set M.GetDisenchantValue to their own.
---------------------------------------------------------------------------
local MAT = {
	strangeDust = 10940, soulDust = 11083, visionDust = 11137, dreamDust = 11176, illusionDust = 16204,
	lesserMagic = 10938, greaterMagic = 10939, lesserAstral = 10998, greaterAstral = 11082,
	lesserMystic = 11134, greaterMystic = 11135, lesserNether = 11174, greaterNether = 11175,
	lesserEternal = 16202, greaterEternal = 16203,
	smallGlimmering = 10978, largeGlimmering = 11084, smallGlowing = 11138, largeGlowing = 11139,
	smallRadiant = 11177, largeRadiant = 11178, smallBrilliant = 14343, largeBrilliant = 14344,
	nexus = 20725,
}

-- Uncommon armor: { up to item level, dust, dust min, dust max, essence, ess min, ess max, shard, dust %, essence %, shard % }
-- Weapons swap the dust and essence chances.
local UNCOMMON = {
	{ 15, MAT.strangeDust, 1, 2, MAT.lesserMagic, 1, 2, nil, 80, 20, 0 },
	{ 20, MAT.strangeDust, 2, 3, MAT.greaterMagic, 1, 2, MAT.smallGlimmering, 75, 20, 5 },
	{ 25, MAT.strangeDust, 4, 6, MAT.lesserAstral, 1, 2, MAT.smallGlimmering, 75, 15, 10 },
	{ 30, MAT.soulDust, 1, 2, MAT.greaterAstral, 1, 2, MAT.largeGlimmering, 75, 20, 5 },
	{ 35, MAT.soulDust, 2, 5, MAT.lesserMystic, 1, 2, MAT.smallGlowing, 75, 20, 5 },
	{ 40, MAT.visionDust, 1, 2, MAT.greaterMystic, 1, 2, MAT.largeGlowing, 75, 20, 5 },
	{ 45, MAT.visionDust, 2, 5, MAT.lesserNether, 1, 2, MAT.smallRadiant, 75, 20, 5 },
	{ 50, MAT.dreamDust, 1, 2, MAT.greaterNether, 1, 2, MAT.largeRadiant, 75, 20, 5 },
	{ 55, MAT.dreamDust, 2, 5, MAT.lesserEternal, 1, 2, MAT.smallBrilliant, 75, 20, 5 },
	{ 60, MAT.illusionDust, 1, 2, MAT.greaterEternal, 1, 2, MAT.largeBrilliant, 75, 20, 5 },
	{ 65, MAT.illusionDust, 2, 5, MAT.greaterEternal, 2, 3, MAT.largeBrilliant, 75, 20, 5 },
}

-- Rare: one shard; epic: shards or Nexus Crystals. { up to item level, { { item, %, min, max } } }
local RARE = {
	{ 25, { { MAT.smallGlimmering, 100, 1, 1 } } },
	{ 30, { { MAT.largeGlimmering, 100, 1, 1 } } },
	{ 35, { { MAT.smallGlowing, 100, 1, 1 } } },
	{ 40, { { MAT.largeGlowing, 100, 1, 1 } } },
	{ 45, { { MAT.smallRadiant, 100, 1, 1 } } },
	{ 50, { { MAT.largeRadiant, 100, 1, 1 } } },
	{ 55, { { MAT.smallBrilliant, 100, 1, 1 } } },
	{ 65, { { MAT.largeBrilliant, 99.5, 1, 1 }, { MAT.nexus, 0.5, 1, 1 } } },
}
local EPIC = {
	{ 45, { { MAT.smallRadiant, 100, 2, 4 } } },
	{ 50, { { MAT.largeRadiant, 100, 2, 4 } } },
	{ 55, { { MAT.smallBrilliant, 100, 2, 4 } } },
	{ 60, { { MAT.nexus, 100, 1, 1 } } },
	{ 80, { { MAT.nexus, 100, 1, 2 } } },
}

local function Band(list, level)
	for _, band in ipairs(list) do
		if level <= band[1] then return band end
	end
end

-- { { itemID, chance (0-1), average amount } } for an item, or nil.
function M:DisenchantResults(item)
	if not item then return nil end
	local _, _, quality, baseLevel, _, _, _, _, _, _, _, classID = C_Item.GetItemInfo(item)
	if not quality or quality < 2 or quality > 4 then return nil end
	if classID ~= Enum.ItemClass.Armor and classID ~= Enum.ItemClass.Weapon then return nil end
	local level = baseLevel
	if C_Item.GetDetailedItemLevelInfo then
		local detailed = C_Item.GetDetailedItemLevelInfo(item)
		if type(detailed) == "number" and detailed > 0 then level = detailed end
	end
	if not level or level < 5 then return nil end
	local out = {}
	if quality == 2 then
		local band = Band(UNCOMMON, level)
		if not band then return nil end
		local dustChance, essenceChance = band[9], band[10]
		if classID == Enum.ItemClass.Weapon then dustChance, essenceChance = essenceChance, dustChance end
		out[#out + 1] = { band[2], dustChance / 100, (band[3] + band[4]) / 2 }
		out[#out + 1] = { band[5], essenceChance / 100, (band[6] + band[7]) / 2 }
		if band[8] and band[11] > 0 then out[#out + 1] = { band[8], band[11] / 100, 1 } end
	else
		local band = Band(quality == 3 and RARE or EPIC, level)
		if not band then return nil end
		for _, result in ipairs(band[2]) do
			out[#out + 1] = { result[1], result[2] / 100, (result[3] + result[4]) / 2 }
		end
	end
	return out
end

-- Expected copper from disenchanting, at your saved auction prices.
function M:GetDisenchantValue(item)
	local results = self:DisenchantResults(item)
	if not results then return nil end
	local value, known = 0, false
	for _, result in ipairs(results) do
		local price = self:GetPrice(result[1])
		if price then
			value = value + result[2] * result[3] * price
			known = true
		end
	end
	return known and floor(value + 0.5) or nil
end

---------------------------------------------------------------------------
-- Crafting costs: recipes are remembered while a profession window is
-- open (EldoUIDB.auction.recipes[itemID] = { name, n = average made,
-- r = { [reagentID] = amount } }). A reagent costs its saved auction price
-- or what a vendor charges (remembered by the Merchant module), whichever
-- is lower.
---------------------------------------------------------------------------
local function Recipes()
	local store = Store()
	store.recipes = store.recipes or {}
	return store.recipes
end

local function ReagentCost(itemID)
	local ah = M:GetPrice(itemID)
	local vendor = EldoUIDB.vendorBuy and EldoUIDB.vendorBuy[itemID]
	if ah and vendor then return min(ah, vendor) end
	return ah or vendor
end

-- Cost of one crafted item, whether every reagent had a price, the recipe.
function M:GetCraftingCost(itemID)
	local recipe = itemID and Recipes()[itemID]
	if not recipe then return nil end
	local cost, complete = 0, true
	for reagent, amount in pairs(recipe.r or {}) do
		local price = ReagentCost(reagent)
		if price then cost = cost + price * amount else complete = false end
	end
	return floor(cost / max(recipe.n or 1, 1) + 0.5), complete, recipe
end

local recipeScan
function M:ScanRecipes()
	local TS = C_TradeSkillUI
	if not self.active or not self.db.craftingPrices or not TS or not TS.GetRecipeSchematic then return end
	if TS.IsNPCCrafting and Get(TS.IsNPCCrafting) then return end
	if TS.IsTradeSkillLinked and Get(TS.IsTradeSkillLinked) then return end
	local ids = Get(TS.GetAllRecipeIDs) or Get(TS.GetFilteredRecipeIDs)
	if type(ids) ~= "table" or #ids == 0 then return end
	if recipeScan then recipeScan.ids = ids return end
	recipeScan = { ids = ids, index = 0 }
	local basic = Enum.CraftingReagentType and Enum.CraftingReagentType.Basic
	local itemType = Enum.TradeskillRecipeType and Enum.TradeskillRecipeType.Item
	local function Step()
		local scan = recipeScan
		if not scan then return end
		local recipes = Recipes()
		for _ = 1, 40 do
			scan.index = scan.index + 1
			local recipeID = scan.ids[scan.index]
			if not recipeID then
				recipeScan = nil
				return
			end
			local info = Get(TS.GetRecipeInfo, recipeID)
			local schematic = (not info or info.learned ~= false) and Get(TS.GetRecipeSchematic, recipeID, false)
			if schematic and schematic.outputItemID and (not itemType or schematic.recipeType == nil or schematic.recipeType == itemType) then
				local reagents, any = {}, false
				for _, slot in ipairs(schematic.reagentSlotSchematics or {}) do
					local first = slot.reagents and slot.reagents[1]
					if first and first.itemID and slot.required ~= false and (not basic or slot.reagentType == nil or slot.reagentType == basic) then
						reagents[first.itemID] = (reagents[first.itemID] or 0) + (slot.quantityRequired or 1)
						any = true
					end
				end
				if any then
					recipes[schematic.outputItemID] = {
						name = schematic.name, n = ((schematic.quantityMin or 1) + (schematic.quantityMax or 1)) / 2,
						r = reagents, t = time(),
					}
				end
			end
		end
		C_Timer.After(0, Step)
	end
	Step()
end

---------------------------------------------------------------------------
-- Theme: everything EldoUI draws here re-applies on accent / style changes
---------------------------------------------------------------------------
local themed = {}
local function Themed(fn)
	themed[#themed + 1] = fn
	fn()
end

local function Accent()
	local c = E.media.accentColor
	return c[1], c[2], c[3]
end

local function AccentTexture(texture, alpha)
	Themed(function()
		local r, g, b = Accent()
		texture:SetColorTexture(r, g, b, alpha or 1)
	end)
	return texture
end

-- Every font string remembers its size so a font change re-applies at once.
local fontStrings = setmetatable({}, { __mode = "k" })

local function ApplyFont(text, size, header)
	if header then
		E:SetHeaderFont(text, size)
	else
		E:SetFont(text, size)
	end
end

local function Text(parent, size, justify, header)
	size = size or (M.db and M.db.fontSize) or 13
	local text = E:CreateText(parent, size, justify or "LEFT")
	if header then ApplyFont(text, size, true) end
	fontStrings[text] = { size = size, header = header }
	return text
end

-- A button's own label, registered like Text().
local function Label(button, size, header)
	local text = button:CreateFontString(nil, "OVERLAY")
	ApplyFont(text, size, header)
	fontStrings[text] = { size = size, header = header }
	text:SetPoint("CENTER")
	button:SetFontString(text)
	return text
end

-- Secondary text (captions, empty lists, column titles).
local function Grey(text)
	text:SetTextColor(unpack(E.tokens.text.secondary))
	return text
end

local function Abbreviate(number)
	if not number then return "" end
	if number >= 10000 then return E:FormatNumber(number) end
	if BreakUpLargeNumbers then return BreakUpLargeNumbers(number) end
	return tostring(number)
end

---------------------------------------------------------------------------
-- Widgets: the shared kit (E.UIKit), so the auction window's buttons,
-- inputs, scroll bars, tabs and tooltips look and react like every other
-- EldoUI window.
---------------------------------------------------------------------------
local Kit = E.UIKit

-- A vertical scroll bar in the kit look. onValue(value) gets whole steps.
local function ScrollBar(parent, onValue)
	local bar = Kit.ScrollBar(parent, onValue)
	bar:ClearAllPoints()
	return bar
end

-- A kit button. kind "primary" is the one main action of a page (Post).
-- The kit's button; `large` gives the footer height (height.buttonLarge),
-- every other button is height.button (DESIGN.md 3: never a typed height).
local function Button(parent, label, width, large, kind)
	return Kit.Button(parent, label, { width = width, large = large and true or nil, kind = kind == "primary" and "primary" or nil,
		size = E.tokens.size.body })
end

local function Tooltip(frame, title, body)
	Kit.Tooltip(frame, title, body)
end

local function Input(parent, width, numeric)
	return Kit.Input(parent, { width = width, numeric = numeric })
end

-- Row buttons: "x" is the kit's row delete (it turns the bad color on
-- hover), "copy" a kit icon button with the copy glyph. button.tip is read
-- when the tooltip shows, so a row can change it per item.
local function Glyph(parent, kind, size)
	local button
	if kind == "x" then
		button = Kit.RemoveButton(parent, nil, nil, nil, size)
	else
		button = Kit.IconButton(parent, size or 16, "copy")
	end
	Kit.Tooltip(button, nil, function(tooltip)
		if button.tip then Kit.TipTitle(tooltip, button.tip) end
	end)
	return button
end

local strips = {}

-- EldoUI's own bottom tabs (E:SkinTabs, boxed): gray text, the open one
-- in accent text on a tinted box with a 2 px accent underline.
local function PaintTab(tab, selected)
	tab.eldoSelected = selected
end

-- Small tab strip inside a page (Kit.TabStrip). defs = { { key =, label = } };
-- onSelect(key).
local function TabStrip(parent, defs, onSelect)
	local list = {}
	for index, def in ipairs(defs) do list[index] = { key = def.key, label = L[def.label] } end
	local strip = Kit.TabStrip(parent, list, onSelect, { edge = "BOTTOM" })
	strips[#strips + 1] = strip
	return strip
end

---------------------------------------------------------------------------
-- List view: a sortable table with a header, virtual rows and a thin
-- scroll bar. spec = {
--   columns = { { key, title, width | flex, justify, text(item) -> s, r, g, b,
--                 icon(item) -> fileID, sort(item) -> value } },
--   header = true, onClick(item, button, row), onEnter(item, row),
--   setupRow(row), updateRow(row, item), isSelected(item), empty = "text" }
---------------------------------------------------------------------------
local ListView = {}
local views = {}

-- Item row hooks: other modules mark EldoUI's auction rows and
-- Selling grid buttons (Appearances' collected mark) without touching this
-- file. fn(holder, item, kind): holder is a frame covering the item icon,
-- item a link or item ID (nil: the row shows no item now, hide the mark),
-- kind "shopping", "selling", "cancelling" or "crafting". Each hook runs in
-- a pcall; an error goes to the error log.
M.itemRowHooks = {}
function M:RegisterItemRowHook(key, fn)
	self.itemRowHooks[key] = type(fn) == "function" and fn or nil
	self:RefreshItemRows()
end

function M.ItemOfEntry(entry)
	if type(entry) ~= "table" then return nil end
	return entry.link or entry.itemLink or entry.hyperlink or (type(entry.itemKey) == "table" and entry.itemKey.itemID) or entry.itemID
end

function M.RunItemRowHooks(holder, item, kind)
	if not holder then return end
	for key, fn in pairs(M.itemRowHooks) do
		local ok, err = pcall(fn, holder, item, kind)
		if not ok then geterrorhandler()(("EldoUI Auction item row hook %s: %s"):format(tostring(key), tostring(err))) end
	end
end

-- Repaint every row and grid button, e.g. when a hook's own data changed.
function M:RefreshItemRows()
	for _, view in ipairs(views) do
		if view.rows and view:IsShown() then view:Refresh() end
	end
	if self.RefreshSellingGrid then self:RefreshSellingGrid() end
end

local function CreateListView(parent, spec)
	local view = CreateFrame("Frame", nil, parent)
	for k, v in pairs(ListView) do view[k] = v end
	view.spec, view.items, view.shown, view.rows, view.offset = spec, {}, {}, {}, 0
	view.headerHeight = spec.header and 20 or 0
	view:EnableMouseWheel(true)
	view:SetScript("OnMouseWheel", function(self, delta) self:ScrollBy(-delta * 3) end)
	view:SetScript("OnSizeChanged", function(self) self:Layout() end)

	if spec.header then
		view.header = CreateFrame("Frame", nil, view)
		view.header:SetPoint("TOPLEFT")
		view.header:SetPoint("TOPRIGHT", -8, 0)
		view.header:SetHeight(view.headerHeight)
		view.header.bg = view.header:CreateTexture(nil, "BACKGROUND")
		view.header.bg:SetAllPoints()
		view.header.line = view.header:CreateTexture(nil, "ARTWORK")
		view.header.line:SetPoint("BOTTOMLEFT")
		view.header.line:SetPoint("BOTTOMRIGHT")
		view.header.line:SetHeight(E.pixel)
		Themed(function()
			local r, g, b = Accent()
			if M.db.headerAccent then
				view.header.bg:SetColorTexture(r * 0.25, g * 0.25, b * 0.25, 0.6)
				view.header.line:SetColorTexture(r, g, b, 0.9)
			else
				view.header.bg:SetColorTexture(unpack(E.tokens.track))
				view.header.line:SetColorTexture(unpack(E.tokens.edge.window))
			end
		end)
		view.headers = {}
		for index, column in ipairs(spec.columns) do
			local button = CreateFrame("Button", nil, view.header)
			button:SetHeight(view.headerHeight)
			button.text = Text(button, 12, column.justify or "LEFT")
			button.text:SetPoint("LEFT", 4, 0)
			button.text:SetPoint("RIGHT", -4, 0)
			button.text:SetText(column.title and L[column.title] or "")
			Grey(button.text)
			if column.sort then
				button:SetScript("OnClick", function() view:SortBy(index) end)
				local hover = E:SkinHoverPress(button)
				hover:SetColorTexture(1, 1, 1, E.tokens.hover.row)
			end
			view.headers[index] = button
		end
	end

	local bar = ScrollBar(view, function(value)
		if view.syncing then return end
		view.offset = value
		view:Refresh()
	end)
	bar:SetPoint("TOPRIGHT", 0, -view.headerHeight)
	bar:SetPoint("BOTTOMRIGHT")
	view.bar = bar

	view.empty = Text(view, 13, "CENTER")
	view.empty:SetPoint("CENTER", 0, -view.headerHeight / 2)
	Grey(view.empty)
	views[#views + 1] = view
	return view
end

function ListView:ColumnLayout(width)
	local fixed, flex = 0, 0
	for _, column in ipairs(self.spec.columns) do
		if column.flex then flex = flex + 1 else fixed = fixed + (column.width or 80) end
	end
	local rest = max(40, width - fixed)
	local x, out = 0, {}
	for index, column in ipairs(self.spec.columns) do
		local w = column.flex and rest / max(flex, 1) or (column.width or 80)
		out[index] = { x = x, w = w }
		x = x + w
	end
	return out
end

function ListView:CreateRow()
	local spec = self.spec
	local row = CreateFrame("Button", nil, self)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	row.stripe = row:CreateTexture(nil, "BACKGROUND")
	row.stripe:SetAllPoints()
	row.selectedTex = row:CreateTexture(nil, "BACKGROUND", nil, 1)
	row.selectedTex:SetAllPoints()
	AccentTexture(row.selectedTex, E.tokens.pressed)
	row.selectedTex:Hide()
	local hover = row:CreateTexture(nil, "HIGHLIGHT")
	hover:SetAllPoints()
	hover:SetColorTexture(1, 1, 1, E.tokens.hover.row)
	row.cells = {}
	for index, column in ipairs(spec.columns) do
		local cell = { }
		if column.icon then
			cell.icon = row:CreateTexture(nil, "ARTWORK")
			E:TrimIcon(cell.icon)
			-- The frame item row hooks draw on (one per row, over its icon).
			if not row.itemIcon then
				row.itemIcon = CreateFrame("Frame", nil, row)
				row.itemIcon:SetAllPoints(cell.icon)
			end
		end
		cell.text = Text(row, M.db.fontSize, column.justify or "LEFT")
		row.cells[index] = cell
	end
	row:SetScript("OnClick", function(button, mouse)
		if button.item and spec.onClick then spec.onClick(button.item, mouse, button) end
	end)
	row:SetScript("OnEnter", function(button)
		if button.item and spec.onEnter then spec.onEnter(button.item, button) end
	end)
	row:SetScript("OnLeave", GameTooltip_Hide)
	if spec.setupRow then spec.setupRow(row) end
	return row
end

function ListView:Layout()
	local width, height = self:GetWidth(), self:GetHeight()
	if width < 10 or height < 10 then return end
	local rowHeight = M.db.rowHeight
	local count = max(1, floor((height - self.headerHeight) / rowHeight))
	local columns = self:ColumnLayout(width - 8)
	if self.headers then
		for index, button in ipairs(self.headers) do
			button:ClearAllPoints()
			button:SetPoint("LEFT", self.header, "LEFT", columns[index].x, 0)
			button:SetWidth(columns[index].w)
		end
	end
	for i = 1, max(count, #self.rows) do
		local row = self.rows[i]
		if i <= count then
			if not row then
				row = self:CreateRow()
				self.rows[i] = row
			end
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", 0, -self.headerHeight - (i - 1) * rowHeight)
			row:SetPoint("TOPRIGHT", self, "TOPRIGHT", -8, -self.headerHeight - (i - 1) * rowHeight)
			row:SetHeight(rowHeight)
			for index, cell in ipairs(row.cells) do
				local c = columns[index]
				local left = c.x + 4
				if cell.icon then
					local size = rowHeight - 4
					cell.icon:SetSize(size, size)
					cell.icon:ClearAllPoints()
					cell.icon:SetPoint("LEFT", row, "LEFT", left, 0)
					left = left + size + 4
				end
				cell.text:ClearAllPoints()
				cell.text:SetPoint("LEFT", row, "LEFT", left, 0)
				cell.text:SetWidth(max(10, c.x + c.w - left - 4))
				E:SetFont(cell.text, M.db.fontSize)
			end
			if self.spec.layoutRow then self.spec.layoutRow(row, columns) end
		elseif row then
			row:Hide()
		end
	end
	self.visible = count
	self:Refresh()
end

function ListView:SetItems(items)
	self.items = items or {}
	self:ApplySort()
	self:Refresh()
end

function ListView:SortBy(index)
	if self.sortIndex == index then
		self.sortDesc = not self.sortDesc
	else
		self.sortIndex, self.sortDesc = index, false
	end
	self:ApplySort()
	self:Refresh()
end

function ListView:ApplySort()
	local column = self.sortIndex and self.spec.columns[self.sortIndex]
	local list = {}
	for i, item in ipairs(self.items) do list[i] = item end
	if column and column.sort then
		local desc = self.sortDesc
		local values = {}
		for _, item in ipairs(list) do values[item] = column.sort(item) end
		table.sort(list, function(a, b)
			local va, vb = values[a], values[b]
			if va == vb then return false end
			if va == nil then return false end
			if vb == nil then return true end
			if type(va) ~= type(vb) then va, vb = tostring(va), tostring(vb) end
			if desc then return va > vb end
			return va < vb
		end)
	end
	self.shown = list
	if self.headers then
		for index, button in ipairs(self.headers) do
			local title = self.spec.columns[index].title or ""
			if index == self.sortIndex then title = title .. (self.sortDesc and "  v" or "  ^") end
			button.text:SetText(title)
		end
	end
end

function ListView:ScrollBy(delta)
	self.offset = self.offset + delta
	self:Refresh()
end

function ListView:Refresh()
	local count = self.visible or 0
	local total = #self.shown
	local maxOffset = max(0, total - count)
	self.offset = min(max(self.offset, 0), maxOffset)
	self.syncing = true
	self.bar:SetMinMaxValues(0, maxOffset)
	self.bar:SetValue(self.offset)
	self.syncing = false
	self.bar:SetShown(maxOffset > 0)
	local spec = self.spec
	for i = 1, count do
		local row = self.rows[i]
		local item = self.shown[self.offset + i]
		if row then
			row.item = item
			if item then
				for index, column in ipairs(spec.columns) do
					local cell = row.cells[index]
					local text, r, g, b = "", 1, 1, 1
					if column.text then text, r, g, b = column.text(item) end
					cell.text:SetText(text or "")
					cell.text:SetTextColor(r or 1, g or 1, b or 1)
					if cell.icon then
						local icon = column.icon(item)
						cell.icon:SetTexture(icon)
						cell.icon:SetShown(icon ~= nil)
						local tr, tg, tb
						if column.tint then tr, tg, tb = column.tint(item) end
						cell.icon:SetVertexColor(tr or 1, tg or 1, tb or 1)
					end
				end
				local stripe = M.db.zebra and (self.offset + i) % 2 == 0
				row.stripe:SetColorTexture(1, 1, 1, stripe and 0.03 or 0)
				row.selectedTex:SetShown(spec.isSelected and spec.isSelected(item) or false)
				if spec.updateRow then spec.updateRow(row, item) end
				if row.itemIcon and next(M.itemRowHooks) then
					M.RunItemRowHooks(row.itemIcon, M.ItemOfEntry(item), spec.itemKind or "shopping")
				end
				row:Show()
			else
				if row.itemIcon and next(M.itemRowHooks) then M.RunItemRowHooks(row.itemIcon, nil, spec.itemKind or "shopping") end
				row:Hide()
			end
		end
	end
	self.empty:SetShown(total == 0 and (self.emptyText or spec.empty) ~= nil)
	self.empty:SetText(self.emptyText or spec.empty or "")
end

function ListView:SetEmptyText(text)
	self.emptyText = text
	self:Refresh()
end

---------------------------------------------------------------------------
-- Throttle: one request waits for the game's "ready" signal. A newer
-- click replaces an older waiting request; nothing repeats on its own.
---------------------------------------------------------------------------
local waiter, poll

local function RunWaiter()
	if waiter and AHReady() then
		local fn = waiter
		waiter = nil
		fn()
	end
	if not waiter and poll then
		poll:Cancel()
		poll = nil
	end
end

local function WhenReady(fn)
	if AHReady() then
		waiter = nil
		fn()
		return
	end
	waiter = fn
	M:SetStatus(L["Waiting for the auction house..."])
	-- The ready event is the main signal; a slow check covers a missed one.
	if not poll then poll = C_Timer.NewTicker(0.5, RunWaiter) end
end

local function ClearWaiter()
	waiter = nil
	if poll then poll:Cancel(); poll = nil end
end

---------------------------------------------------------------------------
-- Item price search (one item): used by Selling and by the Canceling
-- undercut check. done(list) gets { price, quantity, own, itemLevel }
-- sorted by price, or nil when the search failed.
---------------------------------------------------------------------------
local itemSearch
local othersLowest = {}   -- key -> lowest price from other sellers this session

local function FinishItemSearch(list)
	local request = itemSearch
	itemSearch = nil
	if not request then return end
	if list then
		table.sort(list, function(a, b) return a.price < b.price end)
		local key = request.dbKey
		if list[1] then SavePrice(key, list[1].price) end
		othersLowest[key] = nil
		for _, entry in ipairs(list) do
			if not entry.own then othersLowest[key] = entry.price; break end
		end
	end
	request.done(list)
end

local function CollectCommodity(itemID)
	local list = {}
	local count = Get(AH.GetNumCommoditySearchResults, itemID) or 0
	for index = 1, count do
		local info = Get(AH.GetCommoditySearchResultInfo, itemID, index)
		if info and info.unitPrice then
			list[#list + 1] = {
				price = info.unitPrice,
				quantity = info.quantity or 0,
				own = (info.numOwnerItems or 0) > 0 or info.containsOwnerItem or false,
			}
		end
	end
	return list
end

-- Searches in the game's own Buy tab are remembered too: EldoUI reads the
-- results the game already sent and asks the auction house for nothing.
local function SaveBrowsePrices(results)
	if type(results) ~= "table" then return end
	local batch = {}
	for _, result in ipairs(results) do
		local itemKey, price = type(result) == "table" and result.itemKey, type(result) == "table" and result.minPrice
		if type(itemKey) == "table" and not IsSecret(price) and type(price) == "number" and price > 0 then
			local key = DBKeyFromItemKey(itemKey)
			if key and (not batch[key] or price < batch[key]) then batch[key] = price end
		end
	end
	SaveBatch(batch)
end

-- The lowest price of an item list from the game's own buy screen.
local function SaveLowest(key, list)
	local lowest
	for _, entry in ipairs(list or {}) do
		if not lowest or entry.price < lowest then lowest = entry.price end
	end
	if key and lowest then SavePrice(key, lowest) end
end

local function CollectItems(itemKey)
	local list = {}
	local count = Get(AH.GetNumItemSearchResults, itemKey) or 0
	for index = 1, count do
		local info = Get(AH.GetItemSearchResultInfo, itemKey, index)
		if info and info.buyoutAmount and info.buyoutAmount > 0 then
			local level = info.itemKey and info.itemKey.itemLevel
			if (not level or level == 0) and info.itemLink and C_Item.GetDetailedItemLevelInfo then
				level = C_Item.GetDetailedItemLevelInfo(info.itemLink)
			end
			list[#list + 1] = {
				price = info.buyoutAmount,
				quantity = info.quantity or 1,
				own = info.containsOwnerItem or false,
				itemLevel = level,
			}
		end
	end
	return list
end

function M:SearchItem(itemKey, commodity, done)
	local request = { itemKey = itemKey, itemID = itemKey.itemID, commodity = commodity, done = done, dbKey = DBKeyFromItemKey(itemKey) }
	if itemSearch then
		local old = itemSearch
		itemSearch = nil
		old.done(nil)
	end
	itemSearch = request
	-- Gives up after a while (no answer, or a newer request took the turn).
	C_Timer.After(15, function()
		if itemSearch == request then FinishItemSearch(nil) end
	end)
	WhenReady(function()
		if itemSearch ~= request then return end
		local ok
		if commodity then
			ok = Call(AH.SendSearchQuery, itemKey, PriceSorts(), true)
		else
			ok = Call(AH.SendSellSearchQuery, itemKey, PriceSorts(), true)
			if not ok then ok = Call(AH.SendSearchQuery, itemKey, PriceSorts(), true) end
		end
		if not ok then return FinishItemSearch(nil) end
		request.sent = true
	end)
end

---------------------------------------------------------------------------
-- Panel on top of Blizzard's auction window
---------------------------------------------------------------------------
local Shopping, Selling, Cancelling = {}, {}, {}
local pages = { Shopping = Shopping, Selling = Selling, Cancelling = Cancelling }
M.pages = pages
local HEADER, FOOTER, PAD = 28, 26, 8
-- The dark rail behind the window's bottom tabs reaches this far past them.
local RAIL_PAD = 2

-- The status line at the panel's foot. owner names who wrote it ("selling"
-- for the price check of the item in the sell slot), so that part can take
-- its own text away again without wiping a scan or a post message.
function M:SetStatus(text, owner)
	if not self.panel then return end
	self.panel.status:SetText(text or "")
	self.statusOwner = text and text ~= "" and owner or nil
end

function M:ClearStatus(owner)
	if self.panel and self.statusOwner == owner then self:SetStatus("") end
end

function M:UpdateMoney()
	if self.panel and self.panel:IsShown() then self.panel.money:SetText(Money(GetMoney())) end
end

local function BlizzardTabs()
	return AuctionHouseFrame and AuctionHouseFrame.Tabs or {}
end

-- The dark base of EldoUI's panel and of the tab rail: the skin's backdrop,
-- darker and fully opaque, so nothing behind shows through.
local function BaseColor()
	local r, g, b = unpack(E.media.backdropColor)
	return r * 0.6, g * 0.6, b * 0.6, 1
end

---------------------------------------------------------------------------
-- Blizzard's screens under EldoUI's pages. While Shopping, Selling or
-- Canceling is open, the Blizzard screens they replace are put away one by
-- one (never their children, never the whole window), and each is noted.
-- Going back to a Blizzard tab, closing the window or turning Improve off
-- shows exactly the noted ones again. When Blizzard itself picks a screen
-- (its own tab or the buy screen) and that changes its display mode, it
-- has just set every screen, so only the title and close button come back.
-- Asked for the mode it already shows, Blizzard sets no screen at all
-- (SetDisplayMode returns at once, Blizzard_AuctionHouseFrame.lua): its Sell
-- tab while an item still sits in its sell slot, or a bag item clicked on
-- Quick Sell. Then the noted screens come back too (F22: the Sell tab came
-- back empty, seen in the game on 16.11.2026).
---------------------------------------------------------------------------
local NATIVE_SCREENS = { "SearchBar", "CategoriesList", "BrowseResultsFrame", "ItemBuyFrame", "CommoditiesBuyFrame",
	"ItemSellFrame", "ItemSellList", "CommoditiesSellFrame", "CommoditiesSellList", "AuctionsFrame",
	"WoWTokenResults", "WoWTokenSellFrame" }
local NATIVE_CHROME = { "TitleContainer", "TitleText", "CloseButton" }
local putAway = {} -- frame -> "screen" or "chrome"
local modeAway     -- Blizzard's display mode when the first of them was put away

local function Protected(frame)
	return InCombatLockdown() and E.FrameCheck(frame, "IsProtected") and true or false
end

local function DisplayMode()
	local ahf = AuctionHouseFrame
	return ahf and ahf.GetDisplayMode and ahf:GetDisplayMode() or nil
end

local function PutAway(frame, kind)
	if type(frame) ~= "table" or putAway[frame] or not frame.IsShown or not frame:IsShown() then return end
	-- A protected frame can't change in combat: it stays as it is.
	if Protected(frame) then return end
	if next(putAway) == nil then modeAway = DisplayMode() end
	putAway[frame] = kind
	frame:Hide()
end

function M:HideNative()
	local ahf = AuctionHouseFrame
	if not ahf then return end
	for _, key in ipairs(NATIVE_SCREENS) do PutAway(ahf[key], "screen") end
	for _, key in ipairs(NATIVE_CHROME) do PutAway(ahf[key], "chrome") end
end

-- blizzardShown: Blizzard has just chosen its screens; leave those to it.
function M:RestoreNative(blizzardShown)
	for frame, kind in pairs(putAway) do
		putAway[frame] = nil
		if not (blizzardShown and kind == "screen") then
			if Protected(frame) then
				E:RunOutOfCombat(function() frame:Show() end)
			else
				frame:Show()
			end
		end
	end
	modeAway = nil
end

-- After Blizzard's SetDisplayMode (hooked in SetupAuctionHouse): its
-- screens are its own again. Only a new display mode means Blizzard has
-- shown them itself.
function M:OnBlizzardDisplayMode()
	local same = next(putAway) ~= nil and DisplayMode() == modeAway
	self:HidePanel(not same)
end

-- The Blizzard frames put away right now (a copy).
function M:NativeHidden()
	local copy = {}
	for frame, kind in pairs(putAway) do copy[frame] = kind end
	return copy
end

function M:CreatePanel()
	local ahf = AuctionHouseFrame
	local panel = CreateFrame("Frame", "EldoUI_AuctionPanel", ahf)
	panel:SetAllPoints(ahf)
	panel:SetFrameLevel(ahf:GetFrameLevel() + 100)
	panel:EnableMouse(true)
	panel:Hide()
	-- An opaque base so Blizzard's screen underneath never shows through.
	panel.base = panel:CreateTexture(nil, "BACKGROUND", nil, -8)
	panel.base:SetPoint("TOPLEFT", 2, -2)
	panel.base:SetPoint("BOTTOMRIGHT", -2, 2)
	Themed(function() panel.base:SetColorTexture(BaseColor()) end)
	panel.skin = CreateFrame("Frame", nil, panel)
	panel.skin:SetAllPoints()
	panel.skin:SetFrameLevel(panel:GetFrameLevel() + 1)
	E:SetPanelTemplate(panel.skin)
	local content = CreateFrame("Frame", nil, panel)
	content:SetAllPoints()
	content:SetFrameLevel(panel:GetFrameLevel() + 2)
	panel.content = content

	panel.title = Text(content, 16, "LEFT", true)
	panel.title:SetPoint("TOPLEFT", 12, -6)
	panel.accent = AccentTexture(content:CreateTexture(nil, "ARTWORK"))
	panel.accent:SetPoint("TOPLEFT", E.pixel, -HEADER + 4)
	panel.accent:SetPoint("TOPRIGHT", -E.pixel, -HEADER + 4)
	panel.accent:SetHeight(E.pixel * 2)

	local close = CreateFrame("Button", nil, content, "UIPanelCloseButtonNoScripts")
	close:SetSize(22, 22)
	close:SetPoint("TOPRIGHT", -3, -3)
	close:SetScript("OnClick", function() HideUIPanel(AuctionHouseFrame) end)
	if E.SkinCloseButton then Call(E.SkinCloseButton, E, close) end
	panel.close = close

	panel.money = Text(content, 13, "LEFT")
	panel.money:SetPoint("BOTTOMLEFT", PAD + 2, 8)
	panel.status = Text(content, 13, "RIGHT")
	panel.status:SetPoint("BOTTOMRIGHT", -PAD - 2, 8)
	Grey(panel.status)

	-- Page area between header and footer.
	panel.body = CreateFrame("Frame", nil, content)
	panel.body:SetPoint("TOPLEFT", PAD, -HEADER - 4)
	panel.body:SetPoint("BOTTOMRIGHT", -PAD, FOOTER)
	self.panel = panel

	for _, name in ipairs(TABS) do
		local page = pages[name]
		page.frame = CreateFrame("Frame", nil, panel.body)
		page.frame:SetAllPoints()
		page.frame:Hide()
		page:Create(page.frame)
	end
end

---------------------------------------------------------------------------
-- The window's bottom tabs: Blizzard's Buy / Sell / Auctions (when the
-- window has the EldoUI look) and EldoUI's Shopping / Selling / Canceling
-- share one look, the kit's boxed tab (the box, edge, hover and press of
-- the kit's buttons, the open tab tinted with the accent underline), on
-- one opaque rail so the world never shows through or between them.
---------------------------------------------------------------------------
local navHooked = setmetatable({}, { __mode = "k" })

-- The kit's button edge: the accent on hover, back to the tab's own on leave.
local function NavHover(tab)
	if navHooked[tab] then return end
	local parts = E:GetSkin(tab, "tab")
	if not (parts and parts.bg and parts.bg.SetBackdropBorderColor) then return end
	navHooked[tab] = true
	tab:HookScript("OnEnter", function(self)
		if not self.IsEnabled or self:IsEnabled() then parts.bg:SetBackdropBorderColor(Kit.Accent()) end
	end)
	tab:HookScript("OnLeave", function() parts.bg:SetBackdropBorderColor(unpack(E.media.borderColor)) end)
end

local function StyleNav(list, isSelected)
	E:SkinTabs(list, { edge = "BOTTOM", boxed = true, owner = AuctionHouseFrame, isSelected = isSelected })
	for _, tab in ipairs(list) do NavHover(tab) end
end

-- Blizzard's tabs: none is open while an EldoUI page is.
local function NativeSelected()
	if M.current then return false end
end

function M:CreateTabs()
	local ahf = AuctionHouseFrame
	local blizzard = BlizzardTabs()
	local anchor = blizzard[#blizzard]
	self.tabs = {}
	local previous
	for _, name in ipairs(TABS) do
		local tab = CreateFrame("Button", "EldoUI_AuctionTab" .. name, ahf)
		tab:SetHeight(anchor and anchor:GetHeight() or 30)
		Label(tab, 13)
		tab:SetText(TAB_TITLES[name])
		if previous then
			tab:SetPoint("LEFT", previous, "RIGHT", 4, 0)
		elseif anchor then
			tab:SetPoint("LEFT", anchor, "RIGHT", 4, 0)
		else
			tab:SetPoint("TOPLEFT", ahf, "BOTTOMLEFT", 12, 2)
		end
		previous = tab
		tab.pageName = name
		tab:SetScript("OnClick", function() M:ShowPage(name) end)
		self.tabs[name] = tab
	end
	local list = {}
	for _, name in ipairs(TABS) do list[#list + 1] = self.tabs[name] end
	StyleNav(list, function(tab) return tab.eldoSelected end)
	self:FitTabs()

	local rail = CreateFrame("Frame", "EldoUI_AuctionTabRail", ahf)
	E:SetTemplate(rail)
	Themed(function() rail:SetBackdropColor(BaseColor()) end)
	rail:Hide()
	self.rail = rail
end

-- Each EldoUI tab is as wide as its label needs, at every text size. When
-- the row would pass the window's right edge (large text, a longer
-- language), the tabs first lose some padding, then their labels step down
-- a size until the last tab ends inside the window.
local TAB_TEXT, TAB_TEXT_MIN = 13, 9

function M:FitTabs()
	local list = {}
	for _, name in ipairs(TABS) do
		local tab = self.tabs and self.tabs[name]
		local label = tab and tab:GetFontString()
		if label then list[#list + 1] = { tab = tab, label = label } end
	end
	local function Fit(size, pad, least)
		local total = 0
		for _, item in ipairs(list) do
			ApplyFont(item.label, size)
			local width = max(least, math.ceil(item.label:GetStringWidth()) + pad)
			item.tab:SetWidth(width)
			total = total + width
		end
		return total + 4 * (#list - 1)
	end
	local total = Fit(TAB_TEXT, 30, 90)
	local ahf, first = AuctionHouseFrame, list[1] and list[1].tab
	local left, right = first and first:GetLeft(), ahf and ahf:GetRight()
	if not (left and right) then return end
	local room = right - 4 - left
	if total <= room then return end
	local size = TAB_TEXT
	total = Fit(size, 16, 0)
	while total > room and size > TAB_TEXT_MIN do
		size = size - 1
		total = Fit(size, 16, 0)
	end
end

-- The bottom tabs in their row, left to right: Blizzard's when they have
-- the EldoUI look, then EldoUI's.
function M:NavTabs()
	local list = {}
	if self.skinned then
		for _, tab in ipairs(BlizzardTabs()) do
			if tab:IsShown() then list[#list + 1] = tab end
		end
	end
	for _, name in ipairs(TABS) do
		local tab = self.tabs and self.tabs[name]
		if tab and tab:IsShown() then list[#list + 1] = tab end
	end
	return list
end

-- The rail spans the first to the last tab and the tallest of them, and
-- sits under every tab's box.
function M:LayoutRail()
	local rail = self.rail
	if not rail then return end
	local list = self:NavTabs()
	local own = self.tabs and self.tabs.Shopping
	if not (own and own:IsShown()) or #list == 0 then
		rail:Hide()
		return
	end
	local tallest, lowest = 0, math.huge
	for _, tab in ipairs(list) do
		tallest = max(tallest, tab:GetHeight() or 0)
		lowest = min(lowest, tab:GetFrameLevel())
	end
	local first, last = list[1], list[#list]
	-- The tabs sit centered on one line, so a shorter tab has room above and below.
	local up = (tallest - (first:GetHeight() or 0)) / 2
	local down = (tallest - (last:GetHeight() or 0)) / 2
	rail:ClearAllPoints()
	rail:SetPoint("TOPLEFT", first, "TOPLEFT", -RAIL_PAD, RAIL_PAD + up)
	rail:SetPoint("BOTTOMRIGHT", last, "BOTTOMRIGHT", RAIL_PAD, -RAIL_PAD - down)
	-- Under the tabs' boxes, which sit one level under their tab.
	rail:SetFrameLevel(max(lowest - 2, 0))
	rail:Show()
end

-- The tab look painted last: "<EldoUI page>|<Blizzard tab>". The tabs
-- repaint only when it changes (or after a theme or text size change,
-- force), and not while the window is hidden: then the next show paints.
local paintedTabs

function M:UpdateTabStates(force)
	for name, tab in pairs(self.tabs or {}) do
		PaintTab(tab, self.current == name)
	end
	local ahf = AuctionHouseFrame
	if not (ahf and ahf:IsShown()) then
		paintedTabs = nil
		return
	end
	local key = (self.current or "") .. "|" .. tostring(ahf.selectedTab)
	if key == paintedTabs and not force then return end
	paintedTabs = key
	-- Blizzard's tabs only change look; their selection state is left alone.
	for index, tab in ipairs(BlizzardTabs()) do
		if self.current then
			Call(PanelTemplates_DeselectTab, tab)
		elseif AuctionHouseFrame.selectedTab == index then
			Call(PanelTemplates_SelectTab, tab)
		end
	end
	if E.UpdateTabs then Call(E.UpdateTabs, E) end
end

function M:ShowPage(name)
	if not self.panel or not pages[name] then return end
	self.current = name
	for pageName, page in pairs(pages) do page.frame:SetShown(pageName == name) end
	self.panel.title:SetText(("%s|r  %s"):format(E.color .. "EldoUI", TAB_TITLES[name]))
	self.panel:Show()
	self:HideNative()
	-- The sell slot's price line belongs to the Selling page.
	if name ~= "Selling" then self:ClearStatus("selling") end
	self:UpdateMoney()
	self:UpdateTabStates()
	if pages[name].OnShow then pages[name]:OnShow() end
end

-- blizzardShown: Blizzard has just picked one of its own screens.
function M:HidePanel(blizzardShown)
	if not self.panel then return end
	self.panel:Hide()
	self:RestoreNative(blizzardShown)
	if self.current then
		self.lastPage, self.lastHide = self.current, GetTime()
		self.current = nil
		self:UpdateTabStates()
	end
end

local function Allowed(action)
	return M.active and E:BlizzardAllowed("auction-house", action)
end

-- The game's gamepad interface walks the window's buttons with its
-- controller cursor, so EldoUI's tabs and pages step aside while it is on
-- and come back with the mouse interface: the game's own screens stay.
-- The look, the window position and the saved prices stay.
local function Additions()
	return not E:GamepadUIActive()
end

-- EldoUI look for Blizzard's own screens ("Skin"; a reload undoes it).
function M:SkinAuctionHouse()
	if self.skinned or not Allowed("skin") or not AuctionHouseFrame then return end
	self.skinned = true
	if E.SkinPanel then Call(E.SkinPanel, E, AuctionHouseFrame) end
	if E.SkinTabs then Call(StyleNav, BlizzardTabs(), NativeSelected) end
end

-- EldoUI's tabs and panel ("Improve"). The hooks stay once made and check
-- the switch each time they run.
function M:SetupAuctionHouse()
	if self.attached or not AuctionHouseFrame or not Allowed("improve") then return end
	self.attached = true
	self:CreatePanel()
	self:CreateTabs()
	-- Blizzard showing one of its own screens (its tabs, or the buy screen
	-- opened from a result) hides EldoUI's panel.
	if AuctionHouseFrame.SetDisplayMode then
		hooksecurefunc(AuctionHouseFrame, "SetDisplayMode", function() M:OnBlizzardDisplayMode() end)
	end
	for _, tab in ipairs(BlizzardTabs()) do
		tab:HookScript("OnClick", function() M:HidePanel(); M.lastPage = nil end)
	end
	-- A bag item clicked while EldoUI's Quick Sell tab was open goes to EldoUI's sell slot.
	if AuctionHouseFrame.SetPostItem then
		hooksecurefunc(AuctionHouseFrame, "SetPostItem", function(_, location)
			if not (Allowed("improve") and Additions() and location) then return end
			if M.current == "Selling" then
				-- Blizzard kept its screen: the panel is still open.
				Selling:SelectLocation(location)
			elseif M.lastPage == "Selling" and M.lastHide == GetTime() and not M.current then
				-- Blizzard switched to its Sell screen because of this very click.
				M:ShowPage("Selling")
				Selling:SelectLocation(location)
			end
		end)
	end
	AuctionHouseFrame:HookScript("OnHide", function() M:HidePanel(); M.lastPage = nil end)
	-- On every show the tabs fit the window again (its first show places
	-- them), and tabs left unpainted while it was away are painted.
	AuctionHouseFrame:HookScript("OnShow", function()
		if not M.active then return end
		M:FitTabs()
		if not paintedTabs then M:UpdateTabStates() end
	end)
	self:UpdateShown()
end

-- An auction addon with its own screens and price lines: EldoUI's tabs and
-- its price line stand back while it runs (Data/Competitors.lua);
-- the saved prices, the look and the window position stay.
function M:OnStandBack()
	self:UpdateShown()
end

function M:UpdateShown()
	if not self.tabs then return end
	local on = Allowed("improve") and Additions() and not E:StandsBack(self, "tabs")
	for _, tab in pairs(self.tabs) do tab:SetShown(on) end
	if not on then self:HidePanel() end
	self:LayoutRail()
end

-- Tour help: EldoUI's tabs beside Blizzard's, shown once per account.
local function FirstTab()
	local tab = M.tabs and M.tabs[TABS[1]]
	if tab and tab:IsVisible() then return tab end
end

E.Tour:Register("auction:tabs", {
	form = "spot", word = "auction",
	offer = function(_, force)
		if not FirstTab() then return false end
		return E.Tour:Spot("auction:tabs", {
			force = force, target = FirstTab,
			title = L["EldoUI's auction tabs"],
			text = L["Shopping List, Quick Sell and Cancel Undercut are EldoUI's tabs, next to the game's Buy, Sell and Auctions. Every search, post, purchase and cancel is one click of yours."],
		})
	end,
	replay = function(def)
		if not FirstTab() then
			E:Print(L["This help shows while the auction house is open with EldoUI's tabs."])
			return
		end
		def.offer(def, true)
	end,
})

M.window = E:EconomyWindow({
	id = "auction-house",
	key = "auctionHouse",
	frame = function() return AuctionHouseFrame end,
	mover = "EldoUI_AuctionWindow",
	title = "Auction House",
	point = { "TOPLEFT", "UIParent", "TOPLEFT", 20, -150 },
})

function M:ApplyBlizzard()
	if not self.active or not AuctionHouseFrame then return end
	self:SkinAuctionHouse()
	self.window:Apply()
	self:SetupAuctionHouse()
	self:UpdateShown()
end

function M:RestoreBlizzard()
	self.window:Restore()
	self:UpdateShown()
end

E:RegisterBlizzardHandler("auction-house", {
	owner = "Auction",
	apply = function() M:ApplyBlizzard() end,
	undo = function() M:RestoreBlizzard() end,
	reload = { skin = true },
	install = { skin = true, improve = true },
	-- v0.5.0 added EldoUI's tabs (and skinned the window) when the module was on.
	legacy = function() return M.db and M.db.enabled end,
})

---------------------------------------------------------------------------
-- Full scan: one click = one C_AuctionHouse.ReplicateItems() request,
-- which Blizzard allows once every 15 minutes. The answer is read in
-- small steps so the game doesn't stall, and the lowest unit buyout of
-- every item is saved like a search result.
---------------------------------------------------------------------------
local FULL_SCAN_COOLDOWN = 15 * 60
local fullScan -- { requested = true } or { index, count, batch } while reading

local function LastFullScan()
	local store = Store()
	store.fullScan = store.fullScan or {}
	return store.fullScan[RealmKey()]
end

function M:FullScanWait()
	local last = LastFullScan()
	if not last then return 0 end
	return max(0, FULL_SCAN_COOLDOWN - (time() - last))
end

function M:CanFullScan()
	return AH and AH.ReplicateItems ~= nil and AH.GetNumReplicateItems ~= nil and not fullScan
end

function M:FullScan()
	if not self:CanFullScan() then return end
	local wait = self:FullScanWait()
	if wait > 0 then
		self:SetStatus(L["A full scan is possible again in %d min."]:format(math.ceil(wait / 60)))
		return
	end
	fullScan = { requested = true }
	WhenReady(function()
		if not fullScan or not fullScan.requested then return end
		if Call(AH.ReplicateItems) then
			local store = Store()
			store.fullScan = store.fullScan or {}
			store.fullScan[RealmKey()] = time()
			M:SetStatus(L["Full scan requested. The auction house sends every listing; this can take a moment."])
			-- No answer: give the button back.
			C_Timer.After(120, function()
				if fullScan and fullScan.requested then
					fullScan = nil
					M:SetStatus(L["The full scan got no answer."])
					M:UpdateScanButton()
				end
			end)
		else
			fullScan = nil
			M:SetStatus(L["The full scan isn't available right now."])
		end
		M:UpdateScanButton()
	end)
	self:UpdateScanButton()
end

-- What the last full scan saved: { at, items, partial } (partial: the
-- auction house closed before the scan was read to the end).
function M:LastFullScanInfo()
	local info = Store().fullScanInfo
	return info and info[RealmKey()]
end

-- Saves what a scan read (all of it, or the part read so far).
local function FinishScan(scan, partial)
	local items = scan.items or 0
	QueueBatch(scan.batch)
	local store = Store()
	store.fullScanInfo = store.fullScanInfo or {}
	store.fullScanInfo[RealmKey()] = { at = time(), items = items, partial = partial or nil }
	return items
end

local function ReadReplicate()
	local scan = fullScan
	if not scan then return end
	local last = min(scan.count - 1, scan.index + 499)
	for index = scan.index, last do
		local _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID = Get(AH.GetReplicateItemInfo, index)
		if itemID and buyout and buyout > 0 and count and count > 0 then
			local key = itemID
			if itemID == 82800 then
				-- Caged battle pets: the species is in the link.
				key = DBKeyFromLink(Get(AH.GetReplicateItemLink, index), itemID)
			end
			local unit = floor(buyout / count)
			local known = scan.batch[key]
			if unit > 0 and (not known or unit < known) then
				if not known then scan.items = scan.items + 1 end
				scan.batch[key] = unit
			end
		end
	end
	scan.index = last + 1
	if scan.index >= scan.count then
		local items = FinishScan(scan)
		fullScan = nil
		M:SetStatus(L["Full scan done: %s listings, prices for %s items saved."]:format(Abbreviate(scan.count), Abbreviate(items)))
		M:UpdateScanButton()
		return
	end
	M:SetStatus(L["Reading the full scan: %d%%"]:format(floor(scan.index / scan.count * 100)))
	C_Timer.After(0, ReadReplicate)
end

function M:OnReplicateList()
	if not fullScan or not fullScan.requested then return end
	local count = Get(AH.GetNumReplicateItems) or 0
	fullScan = { index = 0, count = count, batch = {}, items = 0 }
	if count == 0 then
		fullScan = nil
		self:SetStatus(L["The full scan returned no listings."])
		self:UpdateScanButton()
		return
	end
	ReadReplicate()
end

-- Stops a scan. A scan that was being read keeps the prices read so far
-- (the listings can't be read once the auction house is closed).
function M:StopFullScan()
	local scan = fullScan
	fullScan = nil
	if scan and scan.batch and next(scan.batch) then FinishScan(scan, true) end
	self:UpdateScanButton()
end

function M:UpdateScanButton()
	local button = Shopping.scanButton
	if not button then return end
	button:SetEnabled(self:CanFullScan() and true or false)
end

---------------------------------------------------------------------------
-- Shopping
---------------------------------------------------------------------------
local shop = { results = {}, byKey = {}, queue = {}, terms = {} }

-- Results you already know (recipes, mounts, pets, toys) get
-- a green icon. What counts as known is what the game reports.
local function KnownTint(entry)
	if not M.db.knownTint or not E.IsItemKnown then return nil end
	local item = entry.link or (entry.itemKey and entry.itemKey.itemID)
	if item and E:IsItemKnown(item) then return unpack(E.knownTint) end
	-- Characters module: recipes one of your characters can learn.
	if item and E.AltRecipeTint then return E:AltRecipeTint(item) end
end

local function Lists() return Store().lists end
local function Recent() return Store().recent end

local function AddRecent(term)
	local list = Recent()
	for i = #list, 1, -1 do
		if list[i]:lower() == term:lower() then table.remove(list, i) end
	end
	table.insert(list, 1, term)
	while #list > RECENT_MAX do table.remove(list) end
end

local function ResolveEntry(entry)
	local info = Get(AH.GetItemKeyInfo, entry.itemKey)
	if info and info.itemName then
		entry.name, entry.quality, entry.icon, entry.commodity = info.itemName, info.quality, info.iconFileID, info.isCommodity
		entry.pending = nil
	else
		local name, _, quality, _, _, _, _, _, _, icon = C_Item.GetItemInfo(entry.itemKey.itemID)
		entry.name = name or entry.name or L["Item %s"]:format(entry.itemKey.itemID)
		entry.quality = quality or entry.quality
		entry.icon = icon or entry.icon or (C_Item.GetItemIconByID and C_Item.GetItemIconByID(entry.itemKey.itemID))
		entry.pending = true
	end
end

-- Exact searches ("Iron Ore" in quotes) keep only that exact name.
local function MatchesTerm(entry)
	if not entry.exact then return true end
	if entry.pending then return true end
	return entry.name and entry.name:lower() == entry.exact:lower()
end

local function RecipeTerms(itemID, recipe)
	local terms = {}
	local function Add(id)
		local name = C_Item.GetItemInfo(id)
		if name then
			terms[#terms + 1] = '"' .. name .. '"'
		elseif C_Item.RequestLoadItemDataByID then
			C_Item.RequestLoadItemDataByID(id)
		end
	end
	Add(itemID)
	for reagent in pairs(recipe.r or {}) do Add(reagent) end
	return terms
end

function Shopping:Rebuild()
	local list = {}
	for _, entry in ipairs(shop.results) do
		if MatchesTerm(entry) then list[#list + 1] = entry end
	end
	self.results:SetItems(list)
	if #list == 0 then
		self.results:SetEmptyText(shop.searching and L["Searching..."] or (shop.done and L["Nothing found."] or L["Type a search term, or pick a shopping list."]))
	else
		self.results:SetEmptyText(nil)
	end
	self.more:SetShown(shop.single and shop.done and not Get(AH.HasFullBrowseResults) and #shop.results > 0)
end

function Shopping:AddBrowseResults(results, exact)
	local batch = {}
	for _, result in ipairs(results or {}) do
		local itemKey = result.itemKey
		if itemKey then
			local id = KeyString(itemKey)
			local entry = shop.byKey[id]
			if not entry then
				entry = { itemKey = itemKey, exact = exact }
				shop.byKey[id] = entry
				shop.results[#shop.results + 1] = entry
			end
			entry.browse = result
			entry.price = result.minPrice
			entry.available = result.totalQuantity
			entry.own = result.containsOwnerItem
			ResolveEntry(entry)
			local key = DBKeyFromItemKey(itemKey)
			if entry.price and entry.price > 0 and (not batch[key] or entry.price < batch[key]) then batch[key] = entry.price end
		end
	end
	SaveBatch(batch)
	self:Rebuild()
end

local function SendNextTerm()
	local term = table.remove(shop.queue, 1)
	if not term then
		shop.searching = false
		shop.done = true
		Shopping.searchButton:Enable()
		M:SetStatus(L["%d results."]:format(#Shopping.results.shown))
		Shopping:Rebuild()
		return
	end
	WhenReady(function()
		if not shop.searching then return end
		local exact = term:match('^"(.*)"$')
		shop.current = { term = term, exact = exact }
		M:SetStatus(shop.total > 1 and L["Searching %d / %d: %s"]:format(shop.total - #shop.queue, shop.total, term) or L["Searching: %s"]:format(term))
		local ok = Call(AH.SendBrowseQuery, {
			searchString = exact or term,
			sorts = PriceSorts(),
			filters = {},
			itemClassFilters = {},
		})
		if not ok then SendNextTerm() end
	end)
end

-- Search one term, or every term of a list. Started by a click; each term
-- waits for the throttle before it is sent.
function Shopping:Search(terms, single)
	local clean = {}
	for _, term in ipairs(terms) do
		term = strtrim(term or "")
		if term ~= "" then clean[#clean + 1] = term end
	end
	if #clean == 0 then return end
	wipe(shop.results)
	wipe(shop.byKey)
	shop.queue = clean
	shop.total = #clean
	shop.single = single
	shop.searching = true
	shop.done = false
	if single then
		AddRecent(clean[1])
		if self.side.selected == "recent" then self:RefreshSide() end
	end
	self:Rebuild()
	SendNextTerm()
end

-- UPDATED brings the full result list, ADDED the extra page of "Load more".
function Shopping:OnBrowseResults(added)
	if not shop.current then return end
	local results = added or Get(AH.GetBrowseResults)
	self:AddBrowseResults(results, shop.current.exact)
	if shop.searching then
		if not added then
			shop.last, shop.current = shop.current, nil
			SendNextTerm()
		end
	else
		shop.last, shop.current = shop.current, nil
		M:SetStatus(L["%d results."]:format(#self.results.shown))
		self:Rebuild()
	end
end

function Shopping:OnBrowseFailure()
	if not shop.searching then return end
	M:SetStatus(L["The auction house did not answer. Try again."])
	shop.current = nil
	SendNextTerm()
end

-- Opens Blizzard's own buy screen for the item.
local function OpenBuy(entry)
	if not entry.browse or not AuctionHouseFrame or not AuctionHouseFrame.SelectBrowseResult then
		M:Print(L["Use Blizzard's Buy tab for this item."])
		return
	end
	local ok, err = pcall(AuctionHouseFrame.SelectBrowseResult, AuctionHouseFrame, entry.browse)
	if not ok then E:Debug("Auction buy screen:", err) end
end

-- Shopping lists side panel: lists (with their terms when selected) or recent searches.
function Shopping:SelectedList()
	local lists = Lists()
	return lists[self.listIndex or 0]
end

function Shopping:RefreshSide()
	local items = {}
	if self.side.selected == "lists" then
		for index, list in ipairs(Lists()) do
			items[#items + 1] = { kind = "list", list = list, index = index }
			if index == self.listIndex then
				for termIndex, term in ipairs(list.terms) do
					items[#items + 1] = { kind = "term", term = term, list = list, termIndex = termIndex }
				end
			end
		end
		self.sideList:SetEmptyText(#items == 0 and L["No shopping lists yet. Click New."] or nil)
	elseif self.side.selected == "crafting" then
		for itemID, recipe in pairs(Recipes()) do
			local cost, complete = M:GetCraftingCost(itemID)
			local value = M:GetPrice(itemID)
			items[#items + 1] = { kind = "recipe", itemID = itemID, recipe = recipe, cost = cost, complete = complete,
				profit = (value and cost and complete) and (value - cost) or nil }
		end
		table.sort(items, function(a, b)
			if (a.profit ~= nil) ~= (b.profit ~= nil) then return a.profit ~= nil end
			if a.profit and b.profit and a.profit ~= b.profit then return a.profit > b.profit end
			return (a.recipe.name or "") < (b.recipe.name or "")
		end)
		self.sideList:SetEmptyText(#items == 0 and L["Open a profession window once and its recipes show here."] or nil)
	else
		for index, term in ipairs(Recent()) do items[#items + 1] = { kind = "recent", term = term, index = index } end
		self.sideList:SetEmptyText(#items == 0 and L["No recent searches."] or nil)
	end
	self.sideList:SetItems(items)
	local list = self:SelectedList()
	self.searchList:SetEnabled(list ~= nil and #list.terms > 0)
	self.renameButton:SetEnabled(list ~= nil)
	self.exportButton:SetEnabled(list ~= nil)
	self.searchList:SetShown(self.side.selected == "lists")
	self.listButtons:SetShown(self.side.selected == "lists")
end

-- Another module wrote EldoUIDB.auction.lists (the Profession Planner's
-- "Send to Shopping"): an open side list shows it at once.
function M:ListsChanged()
	local frame = Shopping.frame
	if Shopping.sideList and frame and frame:IsVisible() then Shopping:RefreshSide() end
end

-- One shopping list by name, made or replaced (the Profession Planner's
-- "Send to Shopping"). terms: a list of search texts. Other lists are
-- left as they are.
function M:SetShoppingList(name, terms)
	if type(name) ~= "string" or name == "" then return end
	terms = type(terms) == "table" and terms or {}
	local lists = Lists()
	for _, list in ipairs(lists) do
		if list.name == name then
			list.terms = terms
			self:ListsChanged()
			return
		end
	end
	lists[#lists + 1] = { name = name, terms = terms }
	self:ListsChanged()
end

local function UniqueName(base)
	local taken = {}
	for _, list in ipairs(Lists()) do taken[list.name] = true end
	local name, n = base, 2
	while taken[name] do name = ("%s %d"):format(base, n); n = n + 1 end
	return name
end

function Shopping:NewList(name, terms)
	local lists = Lists()
	lists[#lists + 1] = { name = UniqueName(name), terms = terms or {} }
	self.listIndex = #lists
	self.side:Select("lists")
end

function Shopping:AddTerm(term)
	term = strtrim(term or "")
	if term == "" then return end
	local list = self:SelectedList()
	if not list then
		self:NewList(L["Shopping list"])
		list = self:SelectedList()
	end
	for _, existing in ipairs(list.terms) do
		if existing:lower() == term:lower() then return end
	end
	list.terms[#list.terms + 1] = term
	M:SetStatus(L["Added \"%s\" to %s."]:format(term, list.name))
	self:RefreshSide()
end

-- Inline name box for New / Rename.
function Shopping:AskName(title, initial, onSave)
	local ask = self.ask
	ask.label:SetText(title)
	ask.box:SetText(initial or "")
	ask.onSave = onSave
	ask:Show()
	ask.box:SetFocus()
	ask.box:HighlightText()
end

function Shopping:Export()
	local list = self:SelectedList()
	if not list then return end
	local lines = { "EldoUI shopping list: " .. list.name } -- no-L: Import below reads this header in every language
	for _, term in ipairs(list.terms) do lines[#lines + 1] = term end
	if E.ShowCopyBox then
		E:ShowCopyBox(L["Export: %s"]:format(list.name), L["One search term per line. Press Ctrl+C to copy; others paste it under Import."], table.concat(lines, "\n"))
	end
end

function Shopping:Import()
	if not E.ShowPasteBox then return end
	E:ShowPasteBox(L["Import a shopping list"], L["Paste a list (one search term per line) and click Save."], function(text)
		local name, terms = nil, {}
		for line in tostring(text or ""):gmatch("[^\r\n]+") do
			line = strtrim(line)
			local header = line:match("^EldoUI shopping list:%s*(.+)$")
			if header then
				name = header
			elseif line ~= "" and #terms < 500 then
				terms[#terms + 1] = E:Utf8Sub(line, 120)
			end
		end
		if #terms == 0 then return M:Print(L["Nothing to import."]) end
		Shopping:NewList(name or L["Imported"], terms)
		M:Print(L["Imported %d search terms."]:format(#terms))
	end)
end

function Shopping:Create(frame)
	local SIDE = 236

	-- Search bar
	local label = Text(frame, 14, "LEFT", true)
	label:SetPoint("TOPLEFT", 2, -4)
	label:SetText(L["Search"])
	local box = Input(frame, 260)
	box:SetPoint("LEFT", label, "RIGHT", 8, 0)
	box:SetScript("OnEnterPressed", function(b)
		b:ClearFocus()
		Shopping:Search({ b:GetText() }, true)
	end)
	self.box = box
	local search = Button(frame, L["Search"], 90)
	search:SetPoint("LEFT", box, "RIGHT", 8, 0)
	search:SetScript("OnClick", function() Shopping:Search({ box:GetText() }, true) end)
	Tooltip(search, L["Search"], L["Put a term in quotes (\"Iron Ore\") for an exact name."])
	self.searchButton = search
	local add = Button(frame, L["Add to list"], 100)
	add:SetPoint("LEFT", search, "RIGHT", 4, 0)
	add:SetScript("OnClick", function() Shopping:AddTerm(box:GetText()) end)
	Tooltip(add, L["Add to list"], L["Adds the search term to the selected shopping list."])
	local scan = Button(frame, L["Full scan"], 90)
	scan:SetPoint("LEFT", add, "RIGHT", 4, 0)
	scan:SetScript("OnClick", function() M:FullScan() end)
	scan:HookScript("OnEnter", function(b)
		GameTooltip:SetOwner(b, "ANCHOR_TOP")
		GameTooltip:AddLine(L["Full scan"])
		GameTooltip:AddLine(L["Asks the auction house once for every listing and saves the lowest price of each item. Blizzard allows one full scan every 15 minutes."], Kit.TEXT[1], Kit.TEXT[2], Kit.TEXT[3], true)
		local wait = M:FullScanWait()
		if wait > 0 then GameTooltip:AddLine(L["Possible again in %d min."]:format(math.ceil(wait / 60)), E:TokenColor("warn")) end
		local last = M:LastFullScanInfo()
		if last and last.partial then
			GameTooltip:AddLine(L["The last full scan stopped when the auction house closed. The prices read until then are saved."], E:TokenColor("secondary", true))
		end
		GameTooltip:Show()
	end)
	scan:HookScript("OnLeave", GameTooltip_Hide)
	self.scanButton = scan

	-- Side: lists / recent
	local side = CreateFrame("Frame", nil, frame)
	side:SetPoint("TOPLEFT", 0, -32)
	side:SetPoint("BOTTOMLEFT", 0, 0)
	side:SetWidth(SIDE)
	self.side = TabStrip(side, { { key = "lists", label = "Lists" }, { key = "recent", label = "Recent" }, { key = "crafting", label = "Crafting" } },
		function() Shopping:RefreshSide() end)
	self.side.tabs[1]:SetPoint("TOPLEFT", 0, 0)

	self.listButtons = CreateFrame("Frame", nil, side)
	self.listButtons:SetPoint("BOTTOMLEFT")
	self.listButtons:SetPoint("BOTTOMRIGHT")
	self.sideWidth = SIDE
	local new = Button(self.listButtons, L["New"], 50)
	new:SetScript("OnClick", function()
		Shopping:AskName(L["New list name"], UniqueName(L["Shopping list"]), function(name) Shopping:NewList(name) end)
	end)
	local rename = Button(self.listButtons, L["Rename"], 50)
	rename:SetScript("OnClick", function()
		local list = Shopping:SelectedList()
		if list then Shopping:AskName(L["Rename list"], list.name, function(name) list.name = name; Shopping:RefreshSide() end) end
	end)
	self.renameButton = rename
	local export = Button(self.listButtons, L["Export"], 50)
	export:SetScript("OnClick", function() Shopping:Export() end)
	self.exportButton = export
	local import = Button(self.listButtons, L["Import"], 50)
	import:SetScript("OnClick", function() Shopping:Import() end)
	self.listButtonRow = { new, rename, export, import }
	self:LayoutListButtons()

	local searchList = Button(side, L["Search list"], SIDE)
	searchList:SetPoint("BOTTOMLEFT", self.listButtons, "TOPLEFT", 0, 4)
	searchList:SetScript("OnClick", function()
		local list = Shopping:SelectedList()
		if list then Shopping:Search(list.terms, false) end
	end)
	Tooltip(searchList, L["Search list"], L["Searches every term of the selected list, one after the other."])
	self.searchList = searchList

	local function RowButtons(row)
		row.copy = Glyph(row, "copy", 16)
		row.copy:SetPoint("RIGHT", -24, 0)
		row.delete = Glyph(row, "x", 16)
		row.delete:SetPoint("RIGHT", -4, 0)
		row.copy:SetScript("OnClick", function()
			local item = row.item
			if not item then return end
			if item.kind == "list" then
				local terms = {}
				for i, term in ipairs(item.list.terms) do terms[i] = term end
				Shopping:NewList(L["%s copy"]:format(item.list.name), terms)
			elseif item.kind == "term" then
				Shopping.box:SetText(item.term)
				Shopping.box:SetFocus()
			elseif item.kind == "recipe" then
				local terms = RecipeTerms(item.itemID, item.recipe)
				if #terms > 0 then Shopping:NewList(item.recipe.name or L["Recipe"], terms) end
			else
				Shopping:AddTerm(item.term)
			end
		end)
		row.delete:SetScript("OnClick", function()
			local item = row.item
			if not item then return end
			if item.kind == "list" then
				-- A whole list asks first; the question names it and its size.
				local list = item.list
				local count = #list.terms
				E:ShowConfirm({ title = L["Delete list"], accept = DELETE or L["Delete"], danger = true,
					text = E:Plural(count, "Delete the shopping list %s and its %d search?", "Delete the shopping list %s and its %d searches?"):format(list.name, count)
						.. " " .. L["This can't be undone."],
					onAccept = function()
						local lists = Lists()
						for index = #lists, 1, -1 do
							if lists[index] == list then table.remove(lists, index) end
						end
						Shopping.listIndex = nil
						Shopping:RefreshSide()
						if M.panel then E.UIKit.Toast(M.panel, L["Deleted the shopping list %s."]:format(list.name)) end
					end })
				return
			elseif item.kind == "term" then
				table.remove(item.list.terms, item.termIndex)
			elseif item.kind == "recipe" then
				Recipes()[item.itemID] = nil
			else
				table.remove(Recent(), item.index)
			end
			Shopping:RefreshSide()
		end)
	end
	self.sideList = CreateListView(side, {
		columns = { { key = "name", flex = true, text = function(item)
			if item.kind == "list" then
				local open = Shopping.listIndex == item.index
				local r, g, b = 1, 1, 1
				if open then r, g, b = Accent() end
				return ("%s " .. E:TextHex("secondary") .. "(%d)|r"):format(item.list.name, #item.list.terms), r, g, b
			elseif item.kind == "term" then
				return "    " .. item.term, 0.85, 0.85, 0.88
			elseif item.kind == "recipe" then
				local name = item.recipe.name or C_Item.GetItemInfo(item.itemID) or L["Item %s"]:format(item.itemID)
				if item.profit then
					local sign = item.profit >= 0 and E:TextHex("good") .. "+" or E:TextHex("bad") .. "-"
					return ("%s  %s%s|r"):format(name, sign, Money(math.abs(item.profit)))
				end
				return name .. "  " .. E:TextHex("secondary") .. "?|r"
			end
			return item.term
		end } },
		setupRow = RowButtons,
		updateRow = function(row, item)
			row.copy.tip = item.kind == "list" and L["Copy list"] or item.kind == "term" and L["Copy to the search box"]
				or item.kind == "recipe" and L["Make a shopping list of its reagents"] or L["Add to the selected list"]
			row.delete.tip = item.kind == "list" and L["Delete list"] or item.kind == "recipe" and L["Forget this recipe"] or L["Remove"]
			row.cells[1].text:SetWidth(max(10, row:GetWidth() - 52))
		end,
		isSelected = function(item) return item.kind == "list" and item.index == Shopping.listIndex end,
		onClick = function(item, mouse)
			if item.kind == "list" then
				if Shopping.listIndex == item.index and mouse == "LeftButton" then
					Shopping.listIndex = nil
				else
					Shopping.listIndex = item.index
				end
				if mouse == "RightButton" then Shopping:Search(item.list.terms, false) end
				Shopping:RefreshSide()
			elseif item.kind == "recipe" then
				local terms = RecipeTerms(item.itemID, item.recipe)
				if #terms > 0 then Shopping:Search(terms, false) end
			else
				Shopping.box:SetText(item.term)
				Shopping:Search({ item.term }, true)
			end
		end,
		onEnter = function(item, row)
			if item.kind == "recipe" then
				GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
				GameTooltip:AddLine(item.recipe.name or L["Recipe"])
				for reagent, amount in pairs(item.recipe.r or {}) do
					local price = ReagentCost(reagent)
					GameTooltip:AddDoubleLine(("%d x %s"):format(amount, C_Item.GetItemInfo(reagent) or L["Item %s"]:format(reagent)),
						price and Money(price * amount) or "?", 1, 1, 1, 1, 1, 1)
				end
				if item.cost then E.UIKit.TipPair(GameTooltip, L["Cost per item"], Money(item.cost) .. (item.complete and "" or " +?")) end
				local value = M:GetPrice(item.itemID)
				if value then E.UIKit.TipPair(GameTooltip, L["Auction price"], Money(value)) end
				E:TooltipHint(GameTooltip, { L["Click"], L["search the item and its reagents"] })
				GameTooltip:Show()
				return
			end
			if item.kind ~= "list" then return end
			GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
			GameTooltip:AddLine(item.list.name)
			E:TooltipHint(GameTooltip, { L["Click"], L["show its terms"] }, { L["Right-click"], L["search the whole list"] })
			GameTooltip:Show()
		end,
	})
	self.sideList:SetPoint("TOPLEFT", 0, -28)
	self.sideList:SetPoint("BOTTOMRIGHT", searchList, "TOPRIGHT", 0, 4)

	-- Name box overlay
	local ask = CreateFrame("Frame", nil, side)
	ask:SetPoint("TOPLEFT", self.sideList, "TOPLEFT", 0, 0)
	ask:SetPoint("TOPRIGHT", self.sideList, "TOPRIGHT", 0, 0)
	ask:SetHeight(64)
	ask:SetFrameLevel(self.sideList:GetFrameLevel() + 10)
	ask:EnableMouse(true)
	E:SetPanelTemplate(ask)
	ask.label = Text(ask, 13, "LEFT")
	ask.label:SetPoint("TOPLEFT", 8, -6)
	ask.box = Input(ask, SIDE - 16)
	ask.box:SetPoint("TOPLEFT", 8, -24)
	ask.box:SetMaxLetters(40)
	ask.box:SetScript("OnEnterPressed", function(b)
		local name = strtrim(b:GetText() or "")
		ask:Hide()
		if name ~= "" and ask.onSave then ask.onSave(name) end
	end)
	ask.box:SetScript("OnEscapePressed", function() ask:Hide() end)
	ask.hint = Text(ask, 11, "LEFT")
	ask.hint:SetPoint("TOPLEFT", ask.box, "BOTTOMLEFT", 0, -2)
	ask.hint:SetText(L["Enter saves, Esc cancels"])
	Grey(ask.hint)
	ask:Hide()
	self.ask = ask

	-- Results
	local results = CreateListView(frame, {
		header = true, itemKind = "shopping",
		columns = {
			{ key = "price", title = "Price", width = 140, justify = "RIGHT",
				text = function(e) return e.price and Money(e.price) or "" end,
				sort = function(e) return e.price or math.huge end },
			{ key = "name", title = "Name", flex = true, icon = function(e) return e.icon end,
				tint = KnownTint,
				text = function(e)
					local name = e.name or ""
					if e.shownLevel == nil then
						local level, required = ItemKeyLevel(e.itemKey, e.commodity)
						e.shownLevel, e.shownRequired = level or false, required
					end
					local level = e.shownLevel
					if level then
						local levelText = e.shownRequired and L["(req. level %d)"]:format(level) or ("(%d)"):format(level)
						name = name .. " " .. E:TextHex("secondary") .. levelText .. "|r"
					end
					if e.own then name = name .. " " .. E:TextHex("good") .. "*|r" end
					local r, g, b = QualityColor(e.quality)
					return name, r, g, b
				end,
				sort = function(e) return (e.name or ""):lower() end },
			{ key = "available", title = "Available", width = 90, justify = "RIGHT",
				text = function(e) return e.available and Abbreviate(e.available) or "?" end,
				sort = function(e) return e.available or 0 end },
		},
		onClick = function(entry, mouse)
			if mouse == "LeftButton" and IsModifiedClick("CHATLINK") then
				local link = select(2, C_Item.GetItemInfo(entry.itemKey.itemID))
				if link then E:InsertLink(link) end
				return
			end
			OpenBuy(entry)
		end,
		onEnter = function(entry, row)
			GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
			SetItemKeyTooltip(GameTooltip, entry.itemKey)
			GameTooltip:AddLine(" ")
			E:TooltipHint(GameTooltip, { L["Click"], L["open it in Blizzard's buy screen"] })
			GameTooltip:Show()
		end,
		empty = L["Type a search term, or pick a shopping list."],
	})
	results:SetPoint("TOPLEFT", side, "TOPRIGHT", 12, 0)
	results:SetPoint("BOTTOMRIGHT", 0, 28)
	results.sortIndex = 1
	self.results = results

	local more = Button(frame, L["Load more results"], 160)
	more:SetPoint("BOTTOM", results, "BOTTOM", 0, -26)
	more:SetScript("OnClick", function()
		if not shop.single or shop.searching or not shop.last then return end
		WhenReady(function()
			shop.current = shop.last
			if Call(AH.RequestMoreBrowseResults) then
				M:SetStatus(L["Loading more..."])
			end
		end)
	end)
	more:Hide()
	self.more = more

	self.side:Select("lists")
end

-- New / Rename / Export / Import under the side list: one row while every
-- label fits whole, each button as wide as its label plus an even share of
-- the rest; two rows of two when they don't (long translations, Large text).
function Shopping:LayoutListButtons()
	local holder, row = self.listButtons, self.listButtonRow
	if not (holder and row) then return end
	local total, gap = self.sideWidth, 4
	local needs, sum = {}, 0
	for index, button in ipairs(row) do
		local label = button:GetFontString()
		-- The kit's label sits 6 px inside each edge.
		needs[index] = math.ceil(label and label:GetStringWidth() or 40) + 12
		sum = sum + needs[index]
	end
	local perRow = (sum + gap * (#row - 1) <= total) and #row or 2
	local rows = math.ceil(#row / perRow)
	local height = row[1]:GetHeight()
	for first = 1, #row, perRow do
		local last = min(first + perRow - 1, #row)
		local used = 0
		for index = first, last do used = used + needs[index] end
		local extra = max(0, total - used - gap * (last - first)) / (last - first + 1)
		local line = (first - 1) / perRow
		local x = 0
		for index = first, last do
			local button = row[index]
			local width = floor(needs[index] + extra)
			button:ClearAllPoints()
			button:SetWidth(width)
			button:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", x, (rows - 1 - line) * (height + gap))
			x = x + width + gap
		end
	end
	holder:SetHeight(rows * height + (rows - 1) * gap)
end

function Shopping:OnShow()
	self:RefreshSide()
	self:Rebuild()
	self.box:SetFocus()
end

---------------------------------------------------------------------------
-- Selling
---------------------------------------------------------------------------
local sell = { entries = {}, order = {} }

local function IsFavourite(itemID) return Store().favourites[itemID] == true end

local function ItemLocationFor(bag, slot)
	if not ItemLocation or not ItemLocation.CreateFromBagAndSlot then return nil end
	return ItemLocation:CreateFromBagAndSlot(bag, slot)
end

local function CanSell(location, info)
	if info.isBound then return false end
	if AH.IsSellItemValid then
		local ok, valid = pcall(AH.IsSellItemValid, location, false)
		if ok then return valid end
	end
	return true
end

-- Bag items that can go on the auction house, one entry per item
-- (stackables per item ID, gear per exact link), with their total count.
local function ScanBags()
	local entries, byKey = {}, {}
	local bags = E.BagCache
	for _, bag in ipairs(bags:BagIDs({ reagent = true })) do
		for slot = 1, bags:NumSlots(bag) do
			local info = bags:Info(bag, slot)
			if info and info.itemID and info.hyperlink then
				local location = ItemLocationFor(bag, slot)
				if location and CanSell(location, info) then
					local _, _, _, _, _, _, _, maxStack, _, _, _, classID = C_Item.GetItemInfo(info.hyperlink)
					local stackable = (maxStack or 1) > 1
					local key = stackable and ("i" .. info.itemID) or info.hyperlink
					local entry = byKey[key]
					if not entry then
						entry = {
							key = key, itemID = info.itemID, link = info.hyperlink, icon = info.iconFileID,
							quality = info.quality, count = 0, bag = bag, slot = slot,
							classID = classID or select(6, C_Item.GetItemInfoInstant(info.itemID)) or 15,
							name = C_Item.GetItemInfo(info.hyperlink) or "",
						}
						byKey[key] = entry
						entries[#entries + 1] = entry
					end
					entry.count = entry.count + (info.stackCount or 1)
				end
			end
		end
	end
	return entries, byKey
end

local function ClassName(classID)
	local name = Get(C_Item.GetItemClassInfo, classID) or (GetItemClassInfo and Get(GetItemClassInfo, classID))
	return name or MISCELLANEOUS or L["Other"]
end

function Selling:RebuildGrid()
	local entries, byKey = ScanBags()
	sell.byKey = byKey
	local groups, byClass = {}, {}
	local favourites = { title = L["Favorites"], items = {} }
	for _, entry in ipairs(entries) do
		if IsFavourite(entry.itemID) then
			favourites.items[#favourites.items + 1] = entry
		else
			local group = byClass[entry.classID]
			if not group then
				group = { title = ClassName(entry.classID), classID = entry.classID, items = {} }
				byClass[entry.classID] = group
				groups[#groups + 1] = group
			end
			group.items[#group.items + 1] = entry
		end
	end
	table.sort(groups, function(a, b) return a.classID < b.classID end)
	table.insert(groups, 1, favourites)
	local function ByQuality(a, b)
		if (a.quality or 0) ~= (b.quality or 0) then return (a.quality or 0) > (b.quality or 0) end
		return a.name < b.name
	end
	sell.order = {}
	for _, group in ipairs(groups) do
		table.sort(group.items, ByQuality)
		for _, entry in ipairs(group.items) do sell.order[#sell.order + 1] = entry end
	end
	self.groups = groups
	self:LayoutGrid()
	-- The selected item may have moved or been posted.
	if sell.entry then
		local fresh = byKey[sell.entry.key]
		if fresh then
			sell.entry.count, sell.entry.bag, sell.entry.slot = fresh.count, fresh.bag, fresh.slot
			sell.location = ItemLocationFor(fresh.bag, fresh.slot)
			self:UpdateDetails()
		else
			self:ClearItem()
		end
	end
end

function Selling:GridButton(index)
	self.buttons = self.buttons or {}
	local button = self.buttons[index]
	if button then return button end
	button = CreateFrame("Button", nil, self.gridChild)
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	E:SetTemplate(button)
	button.icon = button:CreateTexture(nil, "ARTWORK")
	button.icon:SetPoint("TOPLEFT", E.pixel, -E.pixel)
	button.icon:SetPoint("BOTTOMRIGHT", -E.pixel, E.pixel)
	E:TrimIcon(button.icon)
	button.count = Text(button, 12, "RIGHT")
	button.count:SetPoint("BOTTOMRIGHT", -2, 2)
	button.selected = AccentTexture(button:CreateTexture(nil, "OVERLAY"), E.tokens.pressed)
	button.selected:SetAllPoints(button.icon)
	local hover = button:CreateTexture(nil, "HIGHLIGHT")
	hover:SetAllPoints(button.icon)
	hover:SetColorTexture(1, 1, 1, E.tokens.hover.hud)
	button:SetScript("OnClick", function(b, mouse)
		local entry = b.entry
		if not entry then return end
		if mouse == "RightButton" then
			local favs = Store().favourites
			favs[entry.itemID] = not favs[entry.itemID] or nil
			Selling:RebuildGrid()
		elseif IsModifiedClick("CHATLINK") then
			E:InsertLink(entry.link)
		else
			Selling:SelectEntry(entry)
		end
	end)
	button:SetScript("OnEnter", function(b)
		if not b.entry then return end
		GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
		GameTooltip:SetBagItem(b.entry.bag, b.entry.slot)
		GameTooltip:AddLine(" ")
		E:TooltipHint(GameTooltip, { L["Right-click"], IsFavourite(b.entry.itemID) and L["remove from Favorites"] or L["add to Favorites"] })
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", GameTooltip_Hide)
	self.buttons[index] = button
	return button
end

function Selling:GroupHeader(index)
	self.headers = self.headers or {}
	local header = self.headers[index]
	if header then return header end
	header = CreateFrame("Frame", nil, self.gridChild)
	header:SetHeight(20)
	header.bg = header:CreateTexture(nil, "BACKGROUND")
	header.bg:SetAllPoints()
	Themed(function()
		local r, g, b = Accent()
		header.bg:SetColorTexture(r * 0.25, g * 0.25, b * 0.25, M.db.headerAccent and 0.6 or 0.25)
	end)
	header.text = Text(header, 13, "LEFT")
	header.text:SetPoint("LEFT", 4, 0)
	self.headers[index] = header
	return header
end

function M.RefreshSellingGrid()
	if Selling.grid and Selling.grid:IsVisible() then Selling:LayoutGrid() end
end

function Selling:LayoutGrid()
	if not self.groups then return end
	local width = self.grid:GetWidth() - 8
	if width < 40 then return end
	local size = M.db.iconSize
	local gap = 4
	local columns = max(1, floor((width + gap) / (size + gap)))
	local y, buttonIndex, headerIndex = 0, 0, 0
	for _, group in ipairs(self.groups) do
		headerIndex = headerIndex + 1
		local header = self:GroupHeader(headerIndex)
		header:ClearAllPoints()
		header:SetPoint("TOPLEFT", 0, -y)
		header:SetWidth(width)
		header.text:SetText(("%s " .. E:TextHex("secondary") .. "(%d)|r"):format(group.title, #group.items))
		header:Show()
		y = y + 22
		for i, entry in ipairs(group.items) do
			buttonIndex = buttonIndex + 1
			local button = self:GridButton(buttonIndex)
			local column = (i - 1) % columns
			local row = floor((i - 1) / columns)
			button:SetSize(size, size)
			button:ClearAllPoints()
			button:SetPoint("TOPLEFT", column * (size + gap), -(y + row * (size + gap)))
			button.entry = entry
			button.icon:SetTexture(entry.icon)
			button.count:SetText(entry.count > 1 and entry.count or "")
			local r, g, b = 0, 0, 0
			if entry.quality and entry.quality >= 2 then r, g, b = QualityColor(entry.quality) end
			button:SetBackdropBorderColor(r, g, b, 1)
			button.selected:SetShown(sell.entry ~= nil and sell.entry.key == entry.key)
			if next(M.itemRowHooks) then M.RunItemRowHooks(button, M.ItemOfEntry(entry), "selling") end
			button:Show()
		end
		local rows = math.ceil(#group.items / columns)
		y = y + rows * (size + gap) + 4
	end
	for i = buttonIndex + 1, #(self.buttons or {}) do self.buttons[i]:Hide(); self.buttons[i].entry = nil end
	for i = headerIndex + 1, #(self.headers or {}) do self.headers[i]:Hide() end
	self.gridChild:SetSize(width, max(y, 1))
	local range = max(0, y - self.grid:GetHeight())
	self.gridBar:SetMinMaxValues(0, range)
	self.gridBar:SetShown(range > 0)
	if self.grid:GetVerticalScroll() > range then self.grid:SetVerticalScroll(range) end
end

-- Unit price after the undercut, never below the vendor price.
local function Undercut(price, itemID)
	local db = M.db
	local value
	if db.undercutMode == "fixed" then
		value = price - (db.undercutFixed or 0)
	else
		value = floor(price * (100 - (db.undercutPercent or 0)) / 100)
	end
	local floorPrice = max(1, VendorPrice(itemID))
	return max(value, floorPrice)
end

function Selling:SelectLocation(location)
	if not location or not location.GetBagAndSlot then return end
	local bag, slot = location:GetBagAndSlot()
	if not bag then return end
	self:RebuildGrid()
	local info = C_Container.GetContainerItemInfo(bag, slot)
	if not info then return end
	for _, entry in ipairs(sell.order) do
		if entry.key == "i" .. info.itemID or entry.key == info.hyperlink then
			return self:SelectEntry(entry)
		end
	end
end

-- No item in the sell slot: nothing of the last item stays on screen (its
-- quantity, price, deposit, total and listing line), and a price check
-- still on its way for it is dropped when it answers. Remembered prices
-- stay saved.
function Selling:ClearItem()
	sell.entry, sell.location, sell.itemKey, sell.results = nil, nil, nil, nil
	sell.request = (sell.request or 0) + 1
	self.quantity:SetText("")
	self.price:Clear()
	M:ClearStatus("selling")
	self:UpdateDetails()
	self:LayoutGrid()
	self:RefreshRight()
end

function Selling:SelectEntry(entry)
	local location = ItemLocationFor(entry.bag, entry.slot)
	if not location or not C_Item.DoesItemExist(location) then
		return self:RebuildGrid()
	end
	sell.entry, sell.location, sell.results = entry, location, nil
	sell.request = (sell.request or 0) + 1
	local request = sell.request
	sell.dbKey = DBKeyFromLink(entry.link, entry.itemID)
	sell.itemKey = Get(AH.GetItemKeyFromItem, location) or (AH.MakeItemKey and AH.MakeItemKey(entry.itemID)) or { itemID = entry.itemID, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 }
	local status = Get(AH.GetItemCommodityStatus, location)
	local enum = Enum.ItemCommodityStatus
	if enum and status == enum.Commodity then
		sell.commodity = true
	elseif enum and status == enum.Item then
		sell.commodity = false
	else
		sell.commodity = entry.key:sub(1, 1) == "i"
	end
	-- Starting values until the price check answers.
	self.quantity:SetNumber(self:PostLimit())
	local start = (M.db.rememberPrice and PostedDB()[sell.dbKey]) or M:GetPrice(sell.dbKey)
	self.price:SetValue(start or 0)
	self:UpdateDetails()
	self:LayoutGrid()
	self:RefreshRight()
	-- The price check: the click on the item is the player's request.
	M:SetStatus(L["Checking prices..."], "selling")
	M:SearchItem(sell.itemKey, sell.commodity, function(list)
		-- An answer for an item that left the slot (cleared, posted or
		-- another item picked since) changes nothing.
		if sell.request ~= request or sell.entry ~= entry then return end
		-- The price line shows only on the Selling page.
		local function Status(text)
			if M.current == "Selling" then M:SetStatus(text, "selling") end
		end
		if not list then
			Status(L["Price check failed. Click the item to try again."])
			return
		end
		sell.results = list
		local lowest = list[1]
		if lowest then
			self.price:SetValue(lowest.own and lowest.price or Undercut(lowest.price, entry.itemID))
			Status(L["%d listings. Lowest %s."]:format(#list, Money(lowest.price)))
		else
			local remembered = M.db.rememberPrice and PostedDB()[sell.dbKey]
			if remembered then self.price:SetValue(remembered) end
			Status(L["Nobody sells this item right now."])
		end
		self:UpdateDetails()
		self:RefreshRight()
	end)
end

function Selling:PostLimit()
	if not sell.entry then return 0 end
	local count = sell.location and Get(AH.GetAvailablePostCount, sell.location)
	return count or sell.entry.count or 1
end

function Selling:Duration()
	return M.selectedDuration or M.db.duration or 2
end

function Selling:Deposit(quantity)
	if not sell.location or quantity < 1 then return 0 end
	local deposit
	if sell.commodity then
		deposit = Get(AH.CalculateCommodityDeposit, sell.entry.itemID, self:Duration(), quantity)
	else
		deposit = Get(AH.CalculateItemDeposit, sell.location, self:Duration(), quantity)
	end
	return deposit or 0
end

function Selling:UpdateDetails()
	local entry = sell.entry
	if entry then
		self.slot.icon:SetTexture(entry.icon)
		local r, g, b = QualityColor(entry.quality)
		self.slot:SetBackdropBorderColor(r, g, b, 1)
		self.name:SetText(entry.name)
		self.name:SetTextColor(r, g, b)
	else
		self.slot.icon:SetTexture(nil)
		self.slot:SetBackdropBorderColor(unpack(E.media.borderColor))
		self.name:SetText(L["Pick an item from your bags"])
		Grey(self.name)
	end
	local quantity = self.quantity:GetNumber() or 0
	local price = self.price:GetValue()
	local receive = math.floor(price * (1 - M.HouseCut()))
	if entry then
		self.deposit:SetText(L["Deposit: %s"]:format(Money(self:Deposit(quantity))))
		self.total:SetText(L["Total: %s, you receive %s"]:format(Money(price * quantity), Money(receive * quantity)))
	else
		-- Nothing to sell: no deposit or total to show.
		self.deposit:SetText("")
		self.total:SetText("")
	end
	local vendor = entry and VendorPrice(entry.itemID) or 0
	self.warning:SetText(entry and price > 0 and receive < vendor and (E:TextHex("bad") .. L["Below the vendor price"] .. "|r") or "")
	for index, button in ipairs(self.durations) do
		local on = index == self:Duration()
		button.on = on
		local text = button:GetFontString()
		if on then text:SetTextColor(E:TokenColor("accent")) else Grey(text) end
		if button.mark then button.mark:SetShown(on) end
	end
	local ready = entry ~= nil and quantity > 0 and price > 0 and AHReady()
	self.post:SetEnabled(ready)
	self.skip:SetEnabled(#sell.order > 0)
	self.maxButton:SetEnabled(entry ~= nil)
end

-- One post per click.
function Selling:Post()
	local entry, location = sell.entry, sell.location
	if not entry or not location or not C_Item.DoesItemExist(location) then
		M:SetStatus(L["The item moved. Pick it again."])
		return self:RebuildGrid()
	end
	local quantity = min(self.quantity:GetNumber() or 0, self:PostLimit())
	local price = self.price:GetValue()
	if quantity < 1 or price < 1 then return end
	if not AHReady() then
		M:SetStatus(L["The auction house is busy. Click Post again in a moment."])
		return
	end
	local duration = self:Duration()
	local ok, result
	if sell.commodity then
		ok, result = pcall(AH.PostCommodity, location, duration, quantity, price)
		-- Lets Blizzard's own confirmation dialog finish a post the game wants confirmed.
		local frame = AuctionHouseFrame and AuctionHouseFrame.CommoditiesSellFrame
		if ok and result and frame and frame.CachePendingPost then Call(frame.CachePendingPost, frame, location, duration, quantity, price) end
	else
		ok, result = pcall(AH.PostItem, location, duration, quantity, nil, price)
		local frame = AuctionHouseFrame and AuctionHouseFrame.ItemSellFrame
		if ok and result and frame and frame.CachePendingPost then Call(frame.CachePendingPost, frame, location, duration, quantity, nil, price) end
	end
	if not ok then
		M:SetStatus(L["Posting failed."])
		E:Debug("Auction post:", result)
		return
	end
	PostedDB()[sell.dbKey] = price
	local history = PostHistory()
	table.insert(history, 1, { i = sell.dbKey, p = price, q = quantity, t = time() })
	while #history > POST_HISTORY_MAX do table.remove(history) end
	self.post:Disable()
	self:ClearItem()
	M:SetStatus(L["Posted %d x %s at %s each."]:format(quantity, entry.name, Money(price)))
end

-- Skip: the next item in the grid (selecting it checks its price, as a click does).
function Selling:Skip()
	if #sell.order == 0 then return end
	local nextIndex = 1
	if sell.entry then
		for index, entry in ipairs(sell.order) do
			if entry.key == sell.entry.key then nextIndex = index % #sell.order + 1; break end
		end
	end
	self:SelectEntry(sell.order[nextIndex])
end

function Selling:RefreshRight()
	local mode = self.right.selected
	local items = {}
	local key = sell.dbKey
	if not sell.entry then
		self.priceList:SetEmptyText(L["Pick an item to see its prices."])
	elseif mode == "current" then
		for _, entry in ipairs(sell.results or {}) do items[#items + 1] = entry end
		self.priceList:SetEmptyText(sell.results and L["No listings."] or L["Checking prices..."])
	elseif mode == "history" then
		local _, record = M:GetPrice(key)
		for day, price in pairs(record and record.d or {}) do items[#items + 1] = { day = day, price = price } end
		self.historyList:SetEmptyText(L["No saved prices yet. Search or scan to collect them."])
	else
		for _, entry in ipairs(PostHistory()) do
			if entry.i == key then items[#items + 1] = { time = entry.t, price = entry.p, quantity = entry.q } end
		end
		self.yoursList:SetEmptyText(L["You haven't posted this item with EldoUI yet."])
	end
	self.priceList:SetShown(mode == "current")
	self.historyList:SetShown(mode == "history")
	self.yoursList:SetShown(mode == "yours")
	local view = mode == "current" and self.priceList or mode == "history" and self.historyList or self.yoursList
	view:SetItems(sell.entry and items or {})
end

local function MoneyInput(parent, onChange)
	local holder = CreateFrame("Frame", nil, parent)
	holder:SetSize(196, 22)
	local boxes = {}
	local coins = { "Interface\\MoneyFrame\\UI-GoldIcon", "Interface\\MoneyFrame\\UI-SilverIcon", "Interface\\MoneyFrame\\UI-CopperIcon" }
	local widths = { 80, 38, 38 }
	local previous
	for index = 1, 3 do
		local box = Input(holder, widths[index], true)
		box:SetMaxLetters(index == 1 and 7 or 2)
		box:SetJustifyH("RIGHT")
		box:SetTextInsets(4, 16, 0, 0)
		if previous then box:SetPoint("LEFT", previous, "RIGHT", 4, 0) else box:SetPoint("LEFT") end
		local coin = box:CreateTexture(nil, "OVERLAY")
		coin:SetSize(12, 12)
		coin:SetPoint("RIGHT", -3, 0)
		coin:SetTexture(coins[index])
		box:HookScript("OnTextChanged", function(_, user) if user then onChange() end end)
		boxes[index] = box
		previous = box
	end
	Kit.TabOrder(boxes[1], boxes[2], boxes[3])
	function holder:GetValue()
		return (boxes[1]:GetNumber() or 0) * 10000 + (boxes[2]:GetNumber() or 0) * 100 + (boxes[3]:GetNumber() or 0)
	end
	function holder:SetValue(copper)
		copper = floor(copper or 0)
		boxes[1]:SetText(floor(copper / 10000))
		boxes[2]:SetText(floor(copper / 100) % 100)
		boxes[3]:SetText(copper % 100)
	end
	-- Empty boxes: no price at all (reads as 0).
	function holder:Clear()
		for _, box in ipairs(boxes) do box:SetText("") end
	end
	holder.boxes = boxes
	return holder
end

-- Columns of the current prices on the Quick Sell tab. Where the game shows
-- required levels, every row of one item shares it, so there is no level
-- column (the same as Blizzard's own sell list).
function M.PriceColumns()
	local columns = {
		{ title = "Unit price", width = 150, justify = "RIGHT", text = function(e) return Money(e.price) end, sort = function(e) return e.price end },
		{ title = "Available", width = 90, justify = "RIGHT", text = function(e) return Abbreviate(e.quantity) end, sort = function(e) return e.quantity end },
	}
	if not UsesRequiredLevel() then
		columns[#columns + 1] = { title = "Item level", width = 80, justify = "RIGHT", text = function(e) return e.itemLevel and e.itemLevel > 0 and e.itemLevel or "" end, sort = function(e) return e.itemLevel or 0 end }
	end
	columns[#columns + 1] = { title = "Yours", flex = true, justify = "CENTER", text = function(e) if e.own then return YES or L["Yes"], 0.4, 0.87, 0.4 end return "" end }
	return columns
end

function Selling:Create(frame)
	local TOP = 96
	-- Sell slot and name
	local slot = CreateFrame("Button", nil, frame)
	slot:SetSize(48, 48)
	slot:SetPoint("TOPLEFT", 2, -8)
	E:SetTemplate(slot)
	slot.icon = slot:CreateTexture(nil, "ARTWORK")
	slot.icon:SetPoint("TOPLEFT", E.pixel, -E.pixel)
	slot.icon:SetPoint("BOTTOMRIGHT", -E.pixel, E.pixel)
	E:TrimIcon(slot.icon)
	slot:SetScript("OnEnter", function(b)
		if not sell.entry then return end
		GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
		GameTooltip:SetBagItem(sell.entry.bag, sell.entry.slot)
		GameTooltip:Show()
	end)
	slot:SetScript("OnLeave", GameTooltip_Hide)
	slot:SetScript("OnClick", function() Selling:ClearItem() end)
	self.slot = slot
	self.name = Text(frame, 16, "LEFT", true)
	self.name:SetPoint("BOTTOMLEFT", slot, "TOPRIGHT", 8, -20)
	self.name:SetWidth(260)

	local onChange = function() Selling:UpdateDetails() end
	local qLabel = Text(frame, 13, "RIGHT")
	qLabel:SetPoint("TOPLEFT", slot, "BOTTOMLEFT", 0, -10)
	qLabel:SetText(L["Quantity"])
	self.quantity = Input(frame, 60, true)
	self.quantity:SetPoint("LEFT", qLabel, "RIGHT", 8, 0)
	self.quantity:SetScript("OnTextChanged", function(_, user) if user then onChange() end end)
	self.maxButton = Button(frame, L["Max"], 44)
	self.maxButton:SetPoint("LEFT", self.quantity, "RIGHT", 4, 0)
	self.maxButton:SetScript("OnClick", function()
		Selling.quantity:SetNumber(Selling:PostLimit())
		onChange()
	end)
	local pLabel = Text(frame, 13, "RIGHT")
	pLabel:SetPoint("LEFT", self.maxButton, "RIGHT", 12, 0)
	pLabel:SetText(L["Unit price"])
	self.price = MoneyInput(frame, onChange)
	self.price:SetPoint("LEFT", pLabel, "RIGHT", 8, 0)
	self.warning = Text(frame, 11, "LEFT")
	self.warning:SetPoint("TOPLEFT", self.price, "BOTTOMLEFT", 0, -3)

	-- Duration
	local dLabel = Text(frame, 13, "LEFT")
	dLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 340, -8)
	dLabel:SetText(L["Duration"])
	self.durations = {}
	for index, hours in ipairs(DURATION_HOURS) do
		local button = Button(frame, L["%dh"]:format(hours), 44)
		if index == 1 then button:SetPoint("LEFT", dLabel, "RIGHT", 8, 0) else button:SetPoint("LEFT", self.durations[index - 1], "RIGHT", 4, 0) end
		button.mark = AccentTexture(button:CreateTexture(nil, "OVERLAY"))
		button.mark:SetPoint("BOTTOMLEFT", E.pixel, E.pixel)
		button.mark:SetPoint("BOTTOMRIGHT", -E.pixel, E.pixel)
		button.mark:SetHeight(E.pixel * 2)
		button:SetScript("OnClick", function()
			M.selectedDuration = index
			onChange()
		end)
		self.durations[index] = button
	end

	-- Deposit / total and the Post / Skip buttons on the right.
	self.deposit = Text(frame, 13, "RIGHT")
	self.deposit:SetPoint("TOPRIGHT", 0, -8)
	self.total = Text(frame, 13, "RIGHT")
	self.total:SetPoint("TOPRIGHT", self.deposit, "BOTTOMRIGHT", 0, -6)
	self.skip = Button(frame, L["Skip"], 72, true)
	self.skip:SetPoint("TOPRIGHT", 0, -56)
	self.skip:SetScript("OnClick", function() Selling:Skip() end)
	Tooltip(self.skip, L["Skip"], L["Selects the next item and checks its price."])
	self.post = Button(frame, L["Post"], 140, true, "primary")
	self.post:SetPoint("RIGHT", self.skip, "LEFT", -8, 0)
	self.post:SetScript("OnClick", function() Selling:Post() end)
	Tooltip(self.post, L["Post"], L["Puts this item on the auction house. One click, one post."])

	-- Bag grid on the left
	local grid = CreateFrame("ScrollFrame", nil, frame)
	grid:SetPoint("TOPLEFT", 0, -TOP)
	grid:SetPoint("BOTTOMLEFT", 0, 0)
	grid:SetWidth(258)
	grid:EnableMouseWheel(true)
	self.grid = grid
	self.gridChild = CreateFrame("Frame", nil, grid)
	self.gridChild:SetSize(250, 1)
	grid:SetScrollChild(self.gridChild)
	local bar = ScrollBar(frame, function(value) grid:SetVerticalScroll(value) end)
	bar:SetPoint("TOPLEFT", grid, "TOPRIGHT", 1, 0)
	bar:SetPoint("BOTTOMLEFT", grid, "BOTTOMRIGHT", 1, 0)
	grid:SetScript("OnMouseWheel", function(_, delta)
		local low, high = bar:GetMinMaxValues()
		bar:SetValue(min(high, max(low, bar:GetValue() - delta * (M.db.iconSize + 4))))
	end)
	grid:SetScript("OnSizeChanged", function() Selling:LayoutGrid() end)
	self.gridBar = bar

	-- Prices on the right
	local right = CreateFrame("Frame", nil, frame)
	right:SetPoint("TOPLEFT", grid, "TOPRIGHT", 12, 0)
	right:SetPoint("BOTTOMRIGHT")
	self.right = TabStrip(right, { { key = "current", label = "Current prices" }, { key = "history", label = "Price history" }, { key = "yours", label = "Your history" } },
		function() Selling:RefreshRight() end)
	self.right.tabs[1]:SetPoint("BOTTOMLEFT", 0, 0)

	local function Area(view)
		view:SetPoint("TOPLEFT", right, "TOPLEFT", 0, 0)
		view:SetPoint("BOTTOMRIGHT", right, "BOTTOMRIGHT", 0, 28)
		return view
	end
	self.priceList = Area(CreateListView(right, {
		header = true, itemKind = "selling",
		columns = M.PriceColumns(),
		onClick = function(e)
			if not sell.entry then return end
			Selling.price:SetValue(e.own and e.price or Undercut(e.price, sell.entry.itemID))
			Selling:UpdateDetails()
		end,
		onEnter = function(_, row)
			E.UIKit.AnchorTooltip(row)
			E.UIKit.TooltipHint(GameTooltip, { L["Click"], L["use this price (minus your undercut)"] })
			GameTooltip:Show()
		end,
	}))
	self.priceList.sortIndex = 1
	self.historyList = Area(CreateListView(right, {
		header = true, itemKind = "selling",
		columns = {
			{ title = "Day", flex = true, text = function(e) return E:WeekdayName(date("*t", e.day * 86400).wday, true) .. " " .. E:ShortDay(e.day * 86400) end, sort = function(e) return -e.day end },
			{ title = "Lowest price", width = 160, justify = "RIGHT", text = function(e) return Money(e.price) end, sort = function(e) return e.price end },
		},
	}))
	self.historyList.sortIndex = 1
	self.yoursList = Area(CreateListView(right, {
		header = true, itemKind = "selling",
		columns = {
			{ title = "Posted", flex = true, text = function(e) return E:ShortDate(e.time) end, sort = function(e) return -e.time end },
			{ title = "Quantity", width = 80, justify = "RIGHT", text = function(e) return e.quantity end, sort = function(e) return e.quantity end },
			{ title = "Unit price", width = 150, justify = "RIGHT", text = function(e) return Money(e.price) end, sort = function(e) return e.price end },
		},
	}))
	self.yoursList.sortIndex = 1
	self.right:Select("current", true)
	self:UpdateDetails()
end

function Selling:OnShow()
	self:RebuildGrid()
	self:UpdateDetails()
	self:RefreshRight()
end

---------------------------------------------------------------------------
-- Canceling
---------------------------------------------------------------------------
local owned = { list = {} }

local function IsSold(info)
	local enum = Enum.AuctionStatus
	return enum and info.status == enum.Sold
end

-- Per-character listed counts for other modules (Bags tooltip).
local function SaveCounts(list)
	local chars = Store().chars
	local entry = chars[E.charKey] or {}
	chars[E.charKey] = entry
	entry.counts = {}
	for _, auction in ipairs(list) do
		if not auction.sold then
			local id = auction.itemKey.itemID
			entry.counts[id] = (entry.counts[id] or 0) + (auction.quantity or 1)
		end
	end
	entry.updated = time()
end

function Cancelling:Update()
	local list = {}
	local count = Get(AH.GetNumOwnedAuctions) or 0
	for index = 1, count do
		local info = Get(AH.GetOwnedAuctionInfo, index)
		if info and info.itemKey then
			local entry = {
				auctionID = info.auctionID, itemKey = info.itemKey, link = info.itemLink,
				quantity = info.quantity or 1, price = info.buyoutAmount, bid = info.bidAmount,
				timeLeft = info.timeLeftSeconds, sold = IsSold(info), key = DBKeyFromItemKey(info.itemKey),
			}
			ResolveEntry(entry)
			list[#list + 1] = entry
		end
	end
	owned.list = list
	SaveCounts(list)
	self:Refresh()
end

-- Undercut: a lower price from someone else in your last scan.
local function Undercutted(entry)
	if entry.sold or not entry.price then return false end
	local lowest = othersLowest[entry.key]
	if not lowest then
		local last = M:GetPrice(entry.key)
		lowest = last
	end
	return lowest ~= nil and lowest < entry.price
end

function Cancelling:Refresh()
	if not self.list then return end
	self.list:SetItems(owned.list)
	self.list:SetEmptyText(owned.queried and L["You have no auctions."] or L["Click Refresh to load your auctions."])
end

function Cancelling:Query()
	owned.queried = true
	WhenReady(function()
		if Call(AH.QueryOwnedAuctions, PriceSorts()) or Call(AH.QueryOwnedAuctions, {}) then
			M:SetStatus(L["Loading your auctions..."])
		end
	end)
end

-- One click scans the price of each item you have listed, one at a time.
function Cancelling:ScanPrices()
	local seen, todo = {}, {}
	for _, entry in ipairs(owned.list) do
		if not entry.sold and not seen[entry.key] then
			seen[entry.key] = true
			todo[#todo + 1] = entry
		end
	end
	if #todo == 0 then return end
	self.scanButton:Disable()
	local index = 0
	local function NextItem()
		index = index + 1
		local entry = todo[index]
		if not entry or not M.current then
			Cancelling.scanButton:Enable()
			M:SetStatus(L["Price scan finished."])
			Cancelling:Refresh()
			return
		end
		M:SetStatus(L["Scanning %d / %d: %s"]:format(index, #todo, entry.name or "?"))
		local commodity = entry.commodity
		if commodity == nil then commodity = (select(8, C_Item.GetItemInfo(entry.itemKey.itemID)) or 1) > 1 end
		M:SearchItem(entry.itemKey, commodity, function()
			Cancelling:Refresh()
			NextItem()
		end)
	end
	NextItem()
end

function Cancelling:Create(frame)
	local refresh = Button(frame, L["Refresh"], 100)
	refresh:SetPoint("TOPLEFT", 0, -2)
	refresh:SetScript("OnClick", function() Cancelling:Query() end)
	local scan = Button(frame, L["Scan prices"], 110)
	scan:SetPoint("LEFT", refresh, "RIGHT", 4, 0)
	scan:SetScript("OnClick", function(_, mouse) if not E:IsOptionsLinkClick(scan, mouse) then Cancelling:ScanPrices() end end)
	Tooltip(scan, L["Scan prices"], L["Checks the current price of each item you have listed, so undercut auctions are marked."])
	E:BindOptionsLink(scan, { page = "module:Auction" })
	self.scanButton = scan
	local legend = Text(frame, 12, "LEFT")
	legend:SetPoint("LEFT", scan, "RIGHT", 12, 0)
	legend:SetText(L["%s = someone listed it cheaper in your last scan."]:format(E:TextHex("bad") .. L["Undercut"] .. "|r"))
	Grey(legend)

	self.list = CreateListView(frame, {
		header = true, itemKind = "cancelling",
		columns = {
			{ title = "Item", flex = true, icon = function(e) return e.icon end,
				text = function(e) local r, g, b = QualityColor(e.quality); return e.name or "", r, g, b end,
				sort = function(e) return (e.name or ""):lower() end },
			{ title = "Qty", width = 50, justify = "RIGHT", text = function(e) return e.quantity end, sort = function(e) return e.quantity end },
			{ title = "Unit price", width = 140, justify = "RIGHT", text = function(e) return e.price and Money(e.price) or (e.bid and Money(e.bid) or "") end,
				sort = function(e) return e.price or 0 end },
			{ title = "Time left", width = 70, justify = "RIGHT", text = function(e) return e.sold and "" or TimeLeft(e.timeLeft) end,
				sort = function(e) return e.timeLeft or 0 end },
			{ title = "Status", width = 90, justify = "CENTER", text = function(e)
				if e.sold then return L["Sold"], 0.4, 0.87, 0.4 end
				if Undercutted(e) then return L["Undercut"], 1, 0.4, 0.33 end
				return "", 1, 1, 1
			end, sort = function(e) return e.sold and 2 or (Undercutted(e) and 0 or 1) end },
			{ title = "", width = 80 },
		},
		setupRow = function(row)
			row.cancel = Button(row, L["Cancel"], 70)
			row.cancel:SetScript("OnClick", function(b)
				local entry = row.item
				if not entry or entry.sold or not entry.auctionID then return end
				-- One cancel per click.
				local ok = Call(AH.CancelAuction, entry.auctionID)
				if ok then
					entry.cancelled = true
					b:Disable()
					M:SetStatus(L["Canceled %s."]:format(entry.name or L["auction"]))
				end
			end)
			row.cancel:HookScript("OnEnter", function(b)
				local entry = row.item
				if not entry or not entry.auctionID then return end
				GameTooltip:SetOwner(b, "ANCHOR_LEFT")
				GameTooltip:AddLine(L["Cancel this auction"])
				local cost = Get(AH.GetCancelCost, entry.auctionID)
				if cost and cost > 0 then GameTooltip:AddLine(L["Cost: %s"]:format(Money(cost)), unpack(Kit.TEXT)) end
				GameTooltip:Show()
			end)
			row.cancel:HookScript("OnLeave", GameTooltip_Hide)
		end,
		layoutRow = function(row, columns)
			local c = columns[#columns]
			row.cancel:ClearAllPoints()
			row.cancel:SetPoint("LEFT", row, "LEFT", c.x + 4, 0)
			row.cancel:SetHeight(max(16, M.db.rowHeight - 4))
		end,
		updateRow = function(row, entry)
			local can = not entry.sold and not entry.cancelled and entry.auctionID ~= nil
			if can and AH.CanCancelAuction then can = Get(AH.CanCancelAuction, entry.auctionID) ~= false end
			row.cancel:SetShown(not entry.sold)
			row.cancel:SetEnabled(can or false)
		end,
		onEnter = function(entry, row)
			GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
			if entry.link then GameTooltip:SetHyperlink(entry.link) else GameTooltip:SetItemByID(entry.itemKey.itemID) end
			local lowest = othersLowest[entry.key] or M:GetPrice(entry.key)
			if lowest then
				GameTooltip:AddLine(" ")
				GameTooltip:AddDoubleLine(L["Lowest seen"], Money(lowest), 0.6, 0.8, 1, 1, 1, 1)
			end
			GameTooltip:Show()
		end,
	})
	self.list:SetPoint("TOPLEFT", 0, -28)
	self.list:SetPoint("BOTTOMRIGHT")
	self.list.sortIndex = 1
end

function Cancelling:OnShow()
	self:Refresh()
	-- Opening the tab is the player's click; load the list once per visit.
	if not owned.loadedThisVisit then
		owned.loadedThisVisit = true
		self:Query()
	end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local itemInfoQueued = false
local function RefreshNames()
	if itemInfoQueued then return end
	itemInfoQueued = true
	C_Timer.After(0.2, function()
		itemInfoQueued = false
		for _, entry in ipairs(shop.results) do if entry.pending then ResolveEntry(entry) end end
		for _, entry in ipairs(owned.list) do if entry.pending then ResolveEntry(entry) end end
		if M.current == "Shopping" then Shopping:Rebuild() end
		if M.current == "Cancelling" then Cancelling:Refresh() end
	end)
end

-- The auction house closes. Searches and the full scan stop here. The
-- panel and Blizzard's put-away screens wait for the window's own hide
-- when it is still on screen: shown under a hidden window, those screens
-- come back without drawing or asking the server anything, instead of
-- refreshing all at once while the window closes.
function M:OnAuctionHouseClosed()
	if house then
		-- Back to your faction's prices; the neutral house is packed.
		house = nil
		C_Timer.After(1, function() PackOthers() end)
	end
	ClearWaiter()
	itemSearch = nil
	shop.searching, shop.queue, shop.current = false, {}, nil
	if Shopping.searchButton then Shopping.searchButton:Enable() end
	if Cancelling.scanButton then Cancelling.scanButton:Enable() end
	self:StopFullScan()
	local ahf = AuctionHouseFrame
	if not (self.attached and ahf and ahf:IsShown()) then
		self:HidePanel()
		return
	end
	-- A window still open a frame later (another addon keeping it up)
	-- gets its screens back the usual way.
	C_Timer.After(0, function()
		if AuctionHouseFrame and AuctionHouseFrame:IsShown() then M:HidePanel() end
	end)
end

local AH_EVENTS = {
	AUCTION_HOUSE_SHOW = function()
		M.SetHouse(ReadHouse())
		M:ApplyBlizzard()
		owned.loadedThisVisit = false
		if not M.panel or not Allowed("improve") or not Additions() then return end
		-- The first visit with EldoUI's tabs: a tour help, once the window
		-- has stayed open a moment.
		if not E.Tour:Seen("auction:tabs") then
			C_Timer.After(1, function()
				if AuctionHouseFrame and AuctionHouseFrame:IsShown() then E.Tour:Offer("auction:tabs") end
			end)
		end
		local tab = M.db.defaultTab
		if pages[tab] then
			-- After Blizzard has opened its own first screen.
			C_Timer.After(0, function()
				if AuctionHouseFrame and AuctionHouseFrame:IsShown() then M:ShowPage(tab) end
			end)
		end
	end,
	AUCTION_HOUSE_CLOSED = function() M:OnAuctionHouseClosed() end,
	-- Gamepad and mouse interface swap: EldoUI's tabs follow.
	INPUT_DEVICE_INTERFACE_TRANSITION = function() M:UpdateShown() end,
	REPLICATE_ITEM_LIST_UPDATE = function() M:OnReplicateList() end,
	PLAYER_LOGOUT = function() M:FlushPrices() end,
	AUCTION_HOUSE_THROTTLED_SYSTEM_READY = function()
		RunWaiter()
		if M.current == "Selling" then Selling:UpdateDetails() end
	end,
	-- EldoUI's own search, or a search in the game's Buy tab (its prices
	-- are remembered for the tooltips as well).
	AUCTION_HOUSE_BROWSE_RESULTS_UPDATED = function()
		if Shopping.results and shop.current then Shopping:OnBrowseResults()
		else SaveBrowsePrices(Get(AH.GetBrowseResults)) end
	end,
	AUCTION_HOUSE_BROWSE_RESULTS_ADDED = function(added)
		if Shopping.results and shop.current and type(added) == "table" then Shopping:OnBrowseResults(added)
		else SaveBrowsePrices(added) end
	end,
	AUCTION_HOUSE_BROWSE_FAILURE = function() Shopping:OnBrowseFailure() end,
	COMMODITY_SEARCH_RESULTS_UPDATED = function(itemID)
		if itemSearch and itemSearch.sent and itemSearch.itemID == itemID then
			FinishItemSearch(CollectCommodity(itemID))
		elseif type(itemID) == "number" and not IsSecret(itemID) then
			SaveLowest(DBKey(itemID), CollectCommodity(itemID))
		end
	end,
	ITEM_SEARCH_RESULTS_UPDATED = function(itemKey)
		if itemSearch and itemSearch.sent and type(itemKey) == "table" and itemKey.itemID == itemSearch.itemID then
			FinishItemSearch(CollectItems(itemKey))
		elseif type(itemKey) == "table" and type(itemKey.itemID) == "number" then
			SaveLowest(DBKeyFromItemKey(itemKey), CollectItems(itemKey))
		end
	end,
	OWNED_AUCTIONS_UPDATED = function() Cancelling:Update() end,
	ITEM_KEY_ITEM_INFO_RECEIVED = RefreshNames,
	AUCTION_HOUSE_POST_WARNING = function()
		M:SetStatus(L["The game asks you to confirm this post."])
	end,
	AUCTION_CANCELED = function()
		if M.current == "Cancelling" then Cancelling:Refresh() end
	end,
	PLAYER_MONEY = function() M:UpdateMoney() end,
	BAG_UPDATE_DELAYED = function()
		if M.current == "Selling" then Selling:RebuildGrid() end
	end,
}

---------------------------------------------------------------------------
-- Tooltip: "Auction", "Vendor" and "Disenchant" lines
---------------------------------------------------------------------------
-- Prices go into the shared info area (Modules/Tooltip.lua), with the
-- Tooltip module on or off: the auction price joins the "Value" row and
-- the rest gets its own "Auction" section.
-- How old a saved price is: "seen today", "seen 3 days ago". In the
-- secondary text color, dimmer once it is older than the HISTORY_DAYS the
-- price memory keeps.
local function PriceAge(record)
	if not (record and type(record.t) == "number") then return "" end
	local days = max(0, floor((time() - record.t) / 86400))
	local text = days == 0 and L["seen today"] or E:Plural(days, "seen %d day ago", "seen %d days ago"):format(days)
	local color = days > HISTORY_DAYS and E.tokens.text.dim or E.tokens.text.secondary
	return (" |cff%02x%02x%02x(%s)|r"):format(color[1] * 255, color[2] * 255, color[3] * 255, text)
end
M.PriceAge = PriceAge
M.ItemKeyLevel = ItemKeyLevel
M.SetItemKeyTooltip = SetItemKeyTooltip
M.UsesRequiredLevel = UsesRequiredLevel

-- The price and its age ("3g (seen 2 days ago)"); AuctionValueText adds
-- "AH" for the shared Value row.
local function AuctionPriceText(link, id)
	if not M.active or not M.db.tooltip or IsSecret(id) or E:StandsBack(M, "tooltip") then return nil end
	local price, record = M:GetPrice(DBKeyFromLink(link, id))
	if not price then return nil end
	return Money(price) .. PriceAge(record)
end

local function AuctionValueText(link, id)
	local text = AuctionPriceText(link, id)
	return text and L["AH %s"]:format(text)
end

local function DisenchantValue(link, id)
	if not M.active or not M.db.tooltipDisenchant or type(M.GetDisenchantValue) ~= "function" then return nil end
	local ok, value = pcall(M.GetDisenchantValue, M, link or id)
	if ok and type(value) == "number" and value > 0 then return value end
end

-- "Craft" line: what the reagents of a remembered recipe cost, and the
-- profit at the saved auction price. Prices only, from your own data.
local function CraftingText(link, id)
	if not M.active or not M.db.tooltipCrafting or not M.db.craftingPrices or IsSecret(id) or type(id) ~= "number" then return nil end
	local cost, complete = M:GetCraftingCost(id)
	if not cost or cost <= 0 then return nil end
	local text = Money(cost) .. (complete and "" or " " .. E:TextHex("secondary") .. "+?|r")
	local value = complete and M:GetPrice(DBKeyFromLink(link, id))
	if value then
		local profit = value - cost
		text = text .. (profit >= 0 and "  " .. E:TextHex("good") .. "+" or "  " .. E:TextHex("bad") .. "-") .. Money(math.abs(profit)) .. "|r"
	end
	return text
end

-- Is a vendor price on this tooltip already? The game's own money line, or
-- the Tooltip module's Value row with its vendor piece.
local function TooltipShowsVendor(tooltip)
	if tooltip and (tooltip.shownMoneyFrames or 0) > 0 then return true end
	local tip = E.modules.Tooltip
	return tip and tip.active and tip.db and tip.db.vendorPrice and E:TooltipSectionShown("value") or false
end

local tooltipHooked = false
local function HookTooltips()
	if tooltipHooked then return end
	tooltipHooked = true
	-- One route, whatever the Tooltip module does: the auction price
	-- joins the shared Value row, the rest is the "Auction" section. Both
	-- show as plain rows while the Tooltip module is off.
	E:RegisterTooltipValue("auction", { order = 20, item = function(_, link, id) return AuctionValueText(link, id) end })
	E:RegisterTooltipSection("auction", { order = 31, title = "Auction",
		desc = "Auction price (when the Value row is off), vendor price where the tooltip has none, disenchant value and crafting cost from EldoUI's Auction House module.",
		item = function(tooltip, link, id, add)
			if not M.active then return end
			if not E:TooltipSectionShown("value") then
				local text = AuctionPriceText(link, id)
				if text then add(L["Auction"], text) end
			end
			if M.db.tooltipVendor and not TooltipShowsVendor(tooltip) then
				local vendor = VendorPrice(link or id)
				if vendor > 0 then add(L["Vendor"], Money(vendor)) end
			end
			local value = DisenchantValue(link, id)
			if value then add(L["Disenchant"], Money(value)) end
			local craft = CraftingText(link, id)
			if craft then add(L["Craft"], craft) end
		end })
end
M.HookTooltips = HookTooltips

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------
function M:OnEnable()
	HookTooltips()
	-- Events this client doesn't know are skipped instead of failing.
	local valid = C_EventUtils and C_EventUtils.IsEventValid
	for event, handler in pairs(AH_EVENTS) do
		if not valid or Get(valid, event) ~= false then
			local ok = pcall(self.RegisterEvent, self, event, function(_, _, ...) handler(...) end)
			if not ok then self:UnregisterEvent(event) end
		end
	end
	-- Profession windows: remember recipes for crafting costs.
	for _, event in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE" }) do
		if not valid or Get(valid, event) ~= false then
			pcall(self.RegisterEvent, self, event, function() M:ScanRecipes() end)
		end
	end
	-- Forever loads the modern auction house (Blizzard_AuctionHouseUI) on demand.
	E:OnBlizzardAddOn("Blizzard_AuctionHouseUI", function() M:ApplyBlizzard() end)
	-- The Profession Planner fills a shopping list: redraw the side list.
	local planner = E.modules.ProfessionPlanner
	if planner and type(planner.SendToShopping) == "function" and not self.plannerHooked then
		self.plannerHooked = true
		hooksecurefunc(planner, "SendToShopping", function() if M.active then M:ListsChanged() end end)
	end
	self:UpdateShown()
end

function M:OnDisable()
	ClearWaiter()
	self:StopFullScan()
	itemSearch = nil
	self:RestoreBlizzard()
end

function M:OnProfileChanged()
	if not self.db then return end
	for _, fn in ipairs(themed) do pcall(fn) end
	for text, info in pairs(fontStrings) do ApplyFont(text, info.size, info.header) end
	for _, strip in ipairs(strips) do strip:Repaint() end
	if self.tabs then
		self:FitTabs()
		self:UpdateTabStates(true)
	end
	Shopping:LayoutListButtons()
	for _, view in ipairs(views) do view:Layout() end
	if self.current == "Selling" then
		Selling:LayoutGrid()
		Selling:UpdateDetails()
	end
	if self.current then self:UpdateMoney() end
	self:ApplyBlizzard()
	self:UpdateShown()
end

---------------------------------------------------------------------------
-- Options and style presets
---------------------------------------------------------------------------
M.options = {
	{ type = "description", label = "Adds Shopping List, Quick Sell and Cancel Undercut tabs to the auction house. Every post, purchase, cancel and search is one click of yours." },
	{ type = "execute", label = "Open Blizzard UI switches", desc = "Choose here whether EldoUI skins, moves or extends Blizzard's auction window (element \"Auction house\").",
		func = function() E:ToggleConfig("blizzard") end },
	{ type = "header", label = "Selling" },
	{ type = "select", key = "undercutMode", label = "Undercut by", desc = "How the Quick Sell tab lowers the cheapest current price. The price never goes below the vendor price.",
		values = { percent = "A percentage", fixed = "A fixed amount" } },
	{ type = "range", key = "undercutPercent", label = "Undercut percentage", unit = "%", min = 0, max = 50, step = 1, zeroText = "Match",
		desc = "How much below the cheapest current price the Quick Sell tab starts.", hidden = function() return M.db.undercutMode ~= "percent" end },
	{ type = "range", key = "undercutFixed", label = "Undercut amount", unit = "copper", min = 0, max = 10000, step = 1, zeroText = "Match",
		desc = "How much below the cheapest current price the Quick Sell tab starts. 100 copper = 1 silver.", hidden = function() return M.db.undercutMode ~= "fixed" end },
	{ type = "select", key = "duration", label = "Default duration", desc = "The duration the Quick Sell tab starts with.",
		values = { [1] = ("Short (%dh)"):format(DURATION_HOURS[1]), [2] = ("Medium (%dh)"):format(DURATION_HOURS[2]), [3] = ("Long (%dh)"):format(DURATION_HOURS[3]) } },
	{ type = "toggle", key = "rememberPrice", label = "Remember my last price", desc = "Starts from the price you last posted the item at, and uses it when nobody else sells the item." },
	{ type = "select", key = "defaultTab", label = "Open the auction house on", desc = "Which tab is shown when you talk to an auctioneer.",
		values = { none = "Blizzard's Buy tab", Shopping = "EldoUI Shopping List", Selling = "EldoUI Quick Sell", Cancelling = "EldoUI Cancel Undercut" } },
	{ type = "header", label = "Tooltip" },
	{ type = "toggle", key = "tooltip", label = "Auction price line",
		disabled = function()
			local standing, _, title = E:StandsBack(M, "tooltip")
			return standing and L["Handled by %s. Type %s to choose."]:format(title, E:Highlight("/eui addons")) or nil
		end, desc = "The last price seen on this realm and faction: from your searches in EldoUI's tabs or the game's Buy tab, and from full scans." },
	{ type = "toggle", key = "tooltipVendor", label = "Vendor price line", desc = "Only when the game or EldoUI's tooltip doesn't show it already." },
	{ type = "toggle", key = "tooltipDisenchant", label = "Disenchant value line", desc = "Expected worth of the materials from disenchanting a green, blue or purple item, at your saved auction prices. Shows only once you have prices for those materials." },
	{ type = "toggle", key = "knownTint", label = "Tint items you already know",
		desc = "Recipes, mounts, pets and toys you already have get a green icon in EldoUI's Shopping results." },
	{ type = "toggle", key = "tooltipCrafting", label = "Crafting cost line", dependsOn = "craftingPrices",
		desc = "For items you can craft: what the reagents cost at your saved auction or vendor prices, and the profit at the item's auction price. Needs Remember recipes (Crafting, below)." },
	{ type = "header", label = "Crafting" },
	{ type = "toggle", key = "craftingPrices", label = "Remember recipes", desc = "While a profession window is open, EldoUI notes which reagents each recipe needs. Used by the crafting cost line and the Crafting list in the Shopping List tab." },
	{ type = "execute", confirm = true, label = "Forget recipes", desc = "Clears every remembered recipe.", func = function() wipe(Recipes()); M:Print(L["Recipes forgotten."]) end },
	{ type = "description", label = "Full scan (Shopping List tab) asks the auction house for every listing at once. The game allows it once every 15 minutes." },
	{ type = "header", label = "Look" },
	{ type = "range", key = "rowHeight", label = "Row height", min = 16, max = 28, step = 1, desc = "Height of every list row." },
	{ type = "range", key = "iconSize", label = "Bag icon size (Quick Sell)", min = 26, max = 48, step = 1, desc = "Size of the item icons in the Quick Sell tab." },
	{ type = "range", key = "fontSize", label = "List text size", min = 10, max = 16, step = 1, desc = "Text size in the lists." },
	{ type = "toggle", key = "zebra", label = "Striped rows", desc = "A faint tint on every other row." },
	{ less = true, type = "toggle", key = "headerAccent", label = "Accent-tinted column headers", desc = "Column and group headers in a dark tint of the accent color." },
	{ type = "select", key = "moneyStyle", label = "Prices as", desc = "How prices are written. \"Use general setting\" follows Fonts and text > Money.",
		values = function() return E:MoneyStyleValues(true) end },
	{ type = "header", label = "Window" },
	{ type = "execute", label = "Open Windows", testSafe = true,
		desc = "Blizzard's auction window. Its size, dragging and resets are on the Move windows page; where it opens is its mover in move mode.",
		func = function() E:ToggleConfig("windows") end },
	{ type = "header", label = "Data" },
	{ type = "execute", confirm = true, label = "Clear saved prices", desc = "Forgets every saved auction price for this realm and faction.",
		func = function() wipe(PriceDB()); M:Print(L["Saved prices cleared."]) end },
	{ type = "description", label = function() return M.SavedPricesText() end },
}

E:RegisterStyles("Auction", {
	{ key = "Standard", title = "Standard", desc = "Balanced rows, coin icons and accent headers.",
		settings = { rowHeight = 20, iconSize = 36, fontSize = 13, zebra = true, headerAccent = true } },
	{ key = "Compact", title = "Compact", desc = "Short rows and small icons: more results on screen.",
		settings = { rowHeight = 16, iconSize = 30, fontSize = 12, zebra = true, headerAccent = true } },
	{ key = "Large", title = "Large", desc = "Tall rows, big icons and larger text.",
		settings = { rowHeight = 24, iconSize = 44, fontSize = 15, zebra = true, headerAccent = true } },
	{ key = "Clean", title = "Clean", desc = "No stripes, neutral headers, quiet look.",
		settings = { rowHeight = 20, iconSize = 34, fontSize = 13, zebra = false, headerAccent = false } },
	{ key = "Ledger", title = "Ledger", desc = "Trader's ledger: striped rows with prices as colored text.",
		settings = { rowHeight = 18, iconSize = 32, fontSize = 13, zebra = true, headerAccent = false } },
	{ key = "Overview", title = "Overview", desc = "The smallest rows and icons: the most results on screen.",
		settings = { rowHeight = 16, iconSize = 28, fontSize = 12, zebra = true, headerAccent = true } },
})
