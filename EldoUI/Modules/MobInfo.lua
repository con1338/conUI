-- EldoUI Mob and Loot Info: remembers what you loot from which mob and shows
-- it in tooltips.
--   * Item tooltips: "Dropped by N mobs", then the mobs with the best drop
--     rate, as "Name   67% (4/6)" (drops / corpses you looted).
--   * Hostile NPC tooltips: corpses looted, average money per corpse and
--     the top drops in quality color. NPC ID on Shift.
-- Only loot windows the player opens are counted, through the data the game
-- gives addons (GetLootSourceInfo). No combat log, no combat math: secret
-- values are skipped, never compared. All tooltip lines go through
-- E:RegisterTooltipSection (Modules/Tooltip.lua).
-- Written from scratch for EldoUI; no code from other addons.
local _, E = ...
local L = E.L

local M = E:NewModule("MobInfo", {
	title = "Mob and Loot Info",
	desc = "Tracks what you loot from each mob and shows drop rates in item and mob tooltips.",
	conflicts = { "MobInfo2" },
	frames = {},
	movers = {},
	blizzard = {},
	savedKeys = { "profile.modules.MobInfo", "EldoUIDB.mobInfo" },
	optionsPage = "module:MobInfo",
	presets = { "Collector", "Early", "Farmer", "Minimal", "Standard" },
	uiAmount = "moderate",
	reload = false,
	defaults = {
		track = true,         -- record loot windows
		itemSection = true,   -- "Dropped by" on item tooltips
		unitSection = true,   -- loot summary on hostile NPC tooltips
		maxShown = 5,         -- mobs listed on an item before "+N more"
		unitDrops = 3,        -- drops listed on a mob tooltip
		minCorpses = 3,       -- corpses needed before a % is shown
		showHealth = true,    -- max health on mob tooltips, only when plain
	},
})

local MAX_MOBS = 2000       -- NPCs kept, least recently seen go first
local PRUNE_TO = 1900       -- prune in batches so it runs rarely
local MAX_ITEMS = 40        -- items kept per NPC, most frequent stay
local FULL_LIST = 30        -- hard cap for the Shift list
local RING_SIZE = 256       -- recent corpse GUIDs, so each corpse counts once
local PENDING_MAX = 400     -- names/levels of mobs seen but not looted yet

local SLOT_ITEM = Enum and Enum.LootSlotType and Enum.LootSlotType.Item or 1
local SLOT_MONEY = Enum and Enum.LootSlotType and Enum.LootSlotType.Money or 2

local GREY = { 0.65, 0.65, 0.68 }
local GREY_CODE = E:TextHex("secondary")
local WHITE = { 1, 1, 1 }

local store            -- EldoUIDB.mobInfo
local mobCount = 0
local index, indexDirty -- itemID -> { [npcID] = true }, built on first use
local pending, pendingCount = {}, 0
local ring, ringSet, ringPos = {}, {}, 0

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
-- A value the addon may read and compare, or nil when the game hides it.
local Plain = E.Plain

local function NpcFromGUID(guid)
	guid = Plain(guid)
	if type(guid) ~= "string" then return nil end
	local kind, _, _, _, _, id = strsplit("-", guid)
	if kind ~= "Creature" and kind ~= "Vehicle" then return nil end
	return tonumber(id)
end

local function ItemIDFromLink(link)
	link = Plain(link)
	if type(link) ~= "string" then return nil end
	return tonumber(link:match("item:(%d+)"))
end

local function Remember(guid)
	ringPos = ringPos % RING_SIZE + 1
	local old = ring[ringPos]
	if old then ringSet[old] = nil end
	ring[ringPos] = guid
	ringSet[guid] = true
end

-- The coin slot's text, e.g. "1 Gold\n5 Silver\n3 Copper", in any locale.
local moneyPatterns
local function ParseMoney(text)
	text = Plain(text)
	if type(text) ~= "string" then return nil end
	if not moneyPatterns then
		moneyPatterns = {}
		for _, entry in ipairs({ { GOLD_AMOUNT, 10000 }, { SILVER_AMOUNT, 100 }, { COPPER_AMOUNT, 1 } }) do
			if type(entry[1]) == "string" and entry[1]:find("%%d") then
				local pattern = entry[1]:gsub("%%d", "\001")
				pattern = pattern:gsub("[%(%)%.%+%-%*%?%[%]%^%$%%]", "%%%0")
				pattern = pattern:gsub("\001", "(%%d+)")
				table.insert(moneyPatterns, { pattern, entry[2] })
			end
		end
	end
	local copper = 0
	for _, entry in ipairs(moneyPatterns) do
		local amount = tonumber(text:match(entry[1]))
		if amount then copper = copper + amount * entry[2] end
	end
	return copper
end

local function MoneyText(copper)
	return E:FormatMoney(copper)
end

local function ItemNameAndColor(itemID)
	local name, quality
	if C_Item then
		if C_Item.GetItemNameByID then name = C_Item.GetItemNameByID(itemID) end
		if C_Item.GetItemQualityByID then quality = C_Item.GetItemQualityByID(itemID) end
		if not name and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(itemID) end
	end
	local r, g, b = 1, 1, 1
	if quality and C_Item and C_Item.GetItemQualityColor then
		r, g, b = C_Item.GetItemQualityColor(quality)
	elseif quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality] then
		local color = ITEM_QUALITY_COLORS[quality]
		r, g, b = color.r, color.g, color.b
	end
	return name or L["Item #%s"]:format(itemID), r, g, b
end

-- "67% (4/6)", or just "(4/6)" until enough corpses are looted.
local function RateText(drops, corpses)
	local count = ("%s(%d/%d)|r"):format(GREY_CODE, drops, corpses)
	if corpses < M.db.minCorpses then return count end
	return ("%d%% %s"):format(math.floor(drops / corpses * 100 + 0.5), count)
end

local function Accent()
	local color = E.media and E.media.accentColor
	if color then return color[1], color[2], color[3] end
	return 1, 0.82, 0
end

---------------------------------------------------------------------------
-- Storage: EldoUIDB.mobInfo = { v = 1, mobs = { [npcID] = {
--   n = name, l = min level, h = max level, k = corpses looted,
--   c = total copper, s = last seen (time()), i = { [itemID] = drops } } } }
---------------------------------------------------------------------------
-- The load check (Core/Database.lua, the saved data registry): a mob
-- saved under a number written as text moves to its number, and anything
-- else of the wrong kind is set aside, never dropped.
local function CheckStore(saved, C)
	local mobs = C.Table(saved, "mobs")
	local moves = {}
	for id, mob in pairs(mobs) do
		if type(id) ~= "number" or type(mob) ~= "table" then moves[#moves + 1] = id end
	end
	for _, id in ipairs(moves) do
		local mob, number = mobs[id], tonumber(id)
		mobs[id] = nil
		if type(mob) == "table" and number and mobs[number] == nil then
			mobs[number] = mob
			C.report.repaired = C.report.repaired + 1
		else
			C.Keep("mobs." .. tostring(id), mob, "Expected a creature entry.")
		end
	end
	for id, mob in pairs(mobs) do
		local path = "mobs." .. id .. "."
		C.Number(mob, "k", path .. "k", 0)
		C.Number(mob, "c", path .. "c", 0)
		C.Table(mob, "i", path .. "i")
	end
end
E:RegisterStore("mobInfo", { title = "Mob info", validate = CheckStore })

local function LoadStore()
	if type(EldoUIDB.mobInfo) ~= "table" then EldoUIDB.mobInfo = E:KeepInNewTable(EldoUIDB.mobInfo, "mobInfo") end
	store = EldoUIDB.mobInfo
	E:MigrateStore("mobInfo", store)
	if type(store.mobs) ~= "table" then store.mobs = {} end
	mobCount = 0
	for _, mob in pairs(store.mobs) do
		mob.k = tonumber(mob.k) or 0
		mob.c = tonumber(mob.c) or 0
		if type(mob.i) ~= "table" then mob.i = {} end
		mobCount = mobCount + 1
	end
	index, indexDirty = nil, true
end

local function Index()
	if indexDirty or not index then
		index = {}
		for npc, mob in pairs(store.mobs) do
			for item in pairs(mob.i) do
				local set = index[item]
				if not set then set = {}; index[item] = set end
				set[npc] = true
			end
		end
		indexDirty = false
	end
	return index
end

local function MergeLevel(target, level)
	level = Plain(level)
	if type(level) ~= "number" or level <= 0 then return end
	if not target.l or level < target.l then target.l = level end
	if not target.h or level > target.h then target.h = level end
end

local function GetMob(npc)
	local mob = store.mobs[npc]
	if mob then return mob end
	mob = { k = 0, c = 0, i = {} }
	local seen = pending[npc]
	if seen then
		mob.n, mob.l, mob.h = seen.n, seen.l, seen.h
		pending[npc] = nil
		pendingCount = pendingCount - 1
	end
	store.mobs[npc] = mob
	mobCount = mobCount + 1
	return mob
end

local function CapItems(mob)
	local count = 0
	for _ in pairs(mob.i) do count = count + 1 end
	while count > MAX_ITEMS do
		local lowest, lowestDrops
		for item, drops in pairs(mob.i) do
			if not lowestDrops or drops < lowestDrops then lowest, lowestDrops = item, drops end
		end
		mob.i[lowest] = nil
		count = count - 1
		indexDirty = true
	end
end

local function PruneMobs()
	if mobCount <= MAX_MOBS then return end
	local mobs, list = store.mobs, {}
	for id in pairs(mobs) do list[#list + 1] = id end
	table.sort(list, function(a, b) return (mobs[a].s or 0) < (mobs[b].s or 0) end)
	for i = 1, #list - PRUNE_TO do
		mobs[list[i]] = nil
		mobCount = mobCount - 1
	end
	indexDirty = true
end

function M:ResetData()
	wipe(store.mobs)
	mobCount = 0
	index, indexDirty = nil, true
	self:Print(L["Mob and loot data cleared."])
end

function M:DataSize()
	local items = 0
	for _, mob in pairs(store.mobs) do
		for _ in pairs(mob.i) do items = items + 1 end
	end
	-- Rough SavedVariables size: one mob line set plus one line per item.
	local bytes = mobCount * 90 + items * 18
	return mobCount, items, bytes
end

function M:DataSizeText()
	local mobs, items, bytes = self:DataSize()
	return L["%d mobs, %d drop entries, about %.0f KB on disk (limit %d mobs, %d items each)."]:format(
		mobs, items, bytes / 1024, MAX_MOBS, MAX_ITEMS)
end

---------------------------------------------------------------------------
-- Names and levels come from mouseover and target, never from combat data.
---------------------------------------------------------------------------
function M:NoteUnit(unit)
	local npc = NpcFromGUID(UnitGUID(unit))
	if not npc then return end
	local name = Plain(UnitName(unit))
	local mob = store.mobs[npc]
	local target = mob
	if not target then
		target = pending[npc]
		if not target then
			if pendingCount >= PENDING_MAX then wipe(pending); pendingCount = 0 end
			target = {}
			pending[npc] = target
			pendingCount = pendingCount + 1
		end
	end
	if type(name) == "string" and name ~= "" then target.n = name end
	MergeLevel(target, UnitLevel(unit))
	if mob then mob.s = time() end
end

function M:UPDATE_MOUSEOVER_UNIT()
	self:NoteUnit("mouseover")
end

function M:PLAYER_TARGET_CHANGED()
	self:NoteUnit("target")
end

---------------------------------------------------------------------------
-- Loot tracking
---------------------------------------------------------------------------
function M:ScanLoot()
	if not self.db.track or not GetLootSourceInfo then return end
	local corpses
	for slot = 1, GetNumLootItems() do
		local slotType = Plain(GetLootSlotType(slot))
		local itemID, copper
		if slotType == SLOT_ITEM then
			itemID = ItemIDFromLink(GetLootSlotLink(slot))
		elseif slotType == SLOT_MONEY then
			local _, text = GetLootSlotInfo(slot)
			copper = ParseMoney(text)
		end
		if itemID or slotType == SLOT_MONEY then
			local sources = { GetLootSourceInfo(slot) }
			local shared = #sources > 2
			for j = 1, #sources, 2 do
				local guid = Plain(sources[j])
				local npc = type(guid) == "string" and not ringSet[guid] and NpcFromGUID(guid)
				if npc then
					corpses = corpses or {}
					local corpse = corpses[guid]
					if not corpse then
						corpse = { npc = npc, items = {}, copper = 0 }
						corpses[guid] = corpse
					end
					if itemID then
						corpse.items[itemID] = true
					else
						-- A shared coin slot lists each corpse's own amount.
						local amount = copper
						local quantity = Plain(sources[j + 1])
						if (shared or not amount or amount == 0) and type(quantity) == "number" and quantity > 0 then
							amount = quantity
						end
						corpse.copper = corpse.copper + (amount or 0)
					end
				end
			end
		end
	end
	if not corpses then return end

	local targetGUID = Plain(UnitGUID("target"))
	local now = time()
	for guid, corpse in pairs(corpses) do
		Remember(guid)
		local mob = GetMob(corpse.npc)
		if targetGUID and targetGUID == guid then
			local name = Plain(UnitName("target"))
			if type(name) == "string" and name ~= "" then mob.n = name end
			MergeLevel(mob, UnitLevel("target"))
		end
		mob.k = mob.k + 1
		mob.c = mob.c + corpse.copper
		mob.s = now
		for itemID in pairs(corpse.items) do
			mob.i[itemID] = (mob.i[itemID] or 0) + 1
			if index and not indexDirty then
				local set = index[itemID]
				if not set then set = {}; index[itemID] = set end
				set[corpse.npc] = true
			end
		end
		CapItems(mob)
	end
	PruneMobs()
end

function M:LOOT_READY() self:ScanLoot() end
function M:LOOT_OPENED() self:ScanLoot() end

---------------------------------------------------------------------------
-- Tooltip sections
---------------------------------------------------------------------------
-- Every creature you looted `itemID` from:
-- { { npc = npcID, name = name or nil, drops = n, kills = corpses }, ... }
-- (unsorted). Reads the saved data even while the module is off.
function M:GetItemDrops(itemID)
	itemID = tonumber(Plain(itemID))
	local rows = {}
	if not itemID then return rows end
	if store then
		for npc in pairs(Index()[itemID] or {}) do
			local mob = store.mobs[npc]
			local drops = mob and mob.i[itemID]
			if drops and mob.k > 0 then rows[#rows + 1] = { npc = npc, name = mob.n, drops = drops, kills = mob.k } end
		end
		return rows
	end
	local saved = type(EldoUIDB) == "table" and EldoUIDB.mobInfo
	if type(saved) ~= "table" or saved.v ~= 1 or type(saved.mobs) ~= "table" then return rows end
	for npc, mob in pairs(saved.mobs) do
		local drops = type(mob) == "table" and type(mob.i) == "table" and tonumber(mob.i[itemID])
		local kills = drops and tonumber(mob.k)
		if kills and kills > 0 then rows[#rows + 1] = { npc = npc, name = mob.n, drops = drops, kills = kills } end
	end
	return rows
end

local function ItemSection(_, itemLink, itemID, add)
	if not M.active or not M.db.itemSection or not store then return end
	itemID = tonumber(Plain(itemID)) or ItemIDFromLink(itemLink)
	if not itemID then return end
	-- The Loot Guide already lists where this item drops.
	if E.LootGuideKnows and E:LootGuideKnows(itemID) then return end

	local minCorpses = M.db.minCorpses
	local rows = M:GetItemDrops(itemID)
	for _, row in ipairs(rows) do
		row.rate = row.drops / row.kills
		row.sure = row.kills >= minCorpses
	end
	local total = #rows
	if total == 0 then return end
	table.sort(rows, function(a, b)
		if a.sure ~= b.sure then return a.sure end
		if a.rate ~= b.rate then return a.rate > b.rate end
		return a.drops > b.drops
	end)

	local r, g, b = Accent()
	add((total == 1 and L["Dropped by %d mob:"] or L["Dropped by %d mobs:"]):format(total), nil, r, g, b)
	local shift = IsShiftKeyDown()
	local limit = math.min(total, shift and FULL_LIST or M.db.maxShown)
	for i = 1, limit do
		local row = rows[i]
		add(row.name or L["NPC #%s"]:format(row.npc), RateText(row.drops, row.kills), WHITE[1], WHITE[2], WHITE[3])
	end
	if total > limit then
		local more = (shift and L["+%d more"] or L["+%d more (Shift)"]):format(total - limit)
		add(more, nil, GREY[1], GREY[2], GREY[3])
	end
end

local function UnitSection(_, unit, add)
	if not M.active or not M.db.unitSection or not store then return end
	unit = Plain(unit)
	if type(unit) ~= "string" then return end
	-- Hostile NPCs only; anything the game hides counts as "no".
	if Plain(UnitIsPlayer(unit)) ~= false then return end
	if Plain(UnitCanAttack("player", unit)) ~= true then return end
	local npc = NpcFromGUID(UnitGUID(unit))
	if not npc then return end
	M:NoteUnit(unit)

	local mob = store.mobs[npc]
	if mob and mob.k > 0 then
		add(L["Looted"], tostring(mob.k), GREY[1], GREY[2], GREY[3])
		if mob.c > 0 then
			add(L["Avg. money"], MoneyText(math.floor(mob.c / mob.k)), GREY[1], GREY[2], GREY[3])
		end
		if mob.l and mob.h and mob.l ~= mob.h then
			add(L["Levels seen"], ("%d-%d"):format(mob.l, mob.h), GREY[1], GREY[2], GREY[3])
		end
		local drops = {}
		for itemID, count in pairs(mob.i) do drops[#drops + 1] = { id = itemID, count = count } end
		table.sort(drops, function(a, b) return a.count > b.count end)
		for i = 1, math.min(#drops, M.db.unitDrops) do
			local name, r, g, b = ItemNameAndColor(drops[i].id)
			add(name, RateText(drops[i].count, mob.k), r, g, b)
		end
	end
	if M.db.showHealth then
		local maxHealth = Plain(UnitHealthMax(unit))
		if type(maxHealth) == "number" and maxHealth > 0 then
			local text = E:FormatNumber(maxHealth)
			add(L["Max health"], text, GREY[1], GREY[2], GREY[3])
		end
	end
	if IsShiftKeyDown() then
		add(L["NPC ID"], tostring(npc), GREY[1], GREY[2], GREY[3])
	end
end

function M:RegisterSections()
	if self.sectionsRegistered then return end
	if not E.RegisterTooltipSection then
		E:Debug("MobInfo: E:RegisterTooltipSection is missing, so no tooltip lines are shown.")
		return
	end
	self.sectionsRegistered = true
	E:RegisterTooltipSection("droppedBy", { order = 50, title = "Dropped by", module = "MobInfo", item = ItemSection })
	E:RegisterTooltipSection("mobInfo", { order = 50, title = "Mob info", module = "MobInfo", unit = UnitSection })
end

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------
function M:OnInitialize()
	LoadStore()
	self:RegisterSections()
end

-- The store (EldoUIDB.mobInfo), read again when the saved tables changed.
function M:Store()
	if type(EldoUIDB) ~= "table" then return nil end
	if store == nil or EldoUIDB.mobInfo ~= store then LoadStore() end
	return store
end

function M:OnEnable()
	self:RegisterEvent("LOOT_READY")
	self:RegisterEvent("LOOT_OPENED")
	self:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
	self:RegisterEvent("PLAYER_TARGET_CHANGED")
end

function M:OnDisable()
	self:UnregisterEvent("LOOT_READY")
	self:UnregisterEvent("LOOT_OPENED")
	self:UnregisterEvent("UPDATE_MOUSEOVER_UNIT")
	self:UnregisterEvent("PLAYER_TARGET_CHANGED")
end

function M:OnProfileChanged()
	-- Settings are read when a tooltip is drawn; data is account-wide.
end

E:RegisterStyles("MobInfo", {
	{ key = "Standard", title = "Standard", desc = "Top 5 mobs on items, top 3 drops on mobs.",
		settings = { itemSection = true, unitSection = true, maxShown = 5, unitDrops = 3, minCorpses = 3, showHealth = true } },
	{ key = "Minimal", title = "Minimal", desc = "Top 3 mobs on items only, nothing on mob tooltips.",
		settings = { itemSection = true, unitSection = false, maxShown = 3, minCorpses = 5 } },
	{ key = "Farmer", title = "Farmer", desc = "Long drop lists on mobs, short lists on items.",
		settings = { itemSection = true, unitSection = true, maxShown = 3, unitDrops = 8, minCorpses = 5, showHealth = false } },
	{ key = "Collector", title = "Collector", desc = "Long mob lists on items for finding where things drop.",
		settings = { itemSection = true, unitSection = true, maxShown = 10, unitDrops = 3, minCorpses = 3 } },
	{ key = "Early", title = "Early numbers", desc = "Shows percentages from the first corpse on.",
		settings = { itemSection = true, unitSection = true, maxShown = 5, unitDrops = 3, minCorpses = 1 } },
})

M.options = {
	{ type = "header", label = "Tracking" },
	{ type = "toggle", key = "track", label = "Record loot",
		desc = "Counts every mob corpse you loot once and remembers its drops and money. Data is shared by all your characters." },
	{ type = "header", label = "Item tooltips" },
	{ type = "toggle", key = "itemSection", label = "Show \"Dropped by\"",
		desc = "Lists the mobs that dropped the item for you, best drop rate first. When to show it (Always, Shift ...) is set on the Tooltip page." },
	{ type = "range", key = "maxShown", label = "Mobs listed", min = 1, max = 15, step = 1,
		desc = "How many mobs show before \"+N more\". Hold Shift for the full list.", dependsOn = "itemSection" },
	{ type = "header", label = "Mob tooltips" },
	{ type = "toggle", key = "unitSection", label = "Show loot summary",
		desc = "Corpses looted, average money and the top drops on hostile NPCs. When to show it is set on the Tooltip page." },
	{ type = "range", key = "unitDrops", label = "Drops listed", min = 1, max = 10, step = 1,
		desc = "How many of the mob's most common drops to list.", dependsOn = "unitSection" },
	{ type = "toggle", key = "showHealth", label = "Show max health",
		desc = "Only when the game gives the number openly; hidden values are never shown or worked out.", dependsOn = "unitSection" },
	{ type = "header", label = "Drop rates" },
	{ type = "range", key = "minCorpses", label = "Corpses before %", min = 1, max = 20, step = 1,
		desc = "Below this many looted corpses only the count (4/6) shows, since a % from a few kills is misleading." },
	{ type = "header", label = "Data" },
	{ type = "execute", label = "Show data size",
		desc = function() return store and M:DataSizeText() or L["No data loaded."] end,
		func = function() M:Print(M:DataSizeText()) end },
	{ type = "execute", label = "Reset data",
		desc = "Deletes every looted mob and drop count, after you confirm.",
		func = function()
			E:ShowConfirm({ key = "ELDOUI_MOBINFO_RESET", title = L["Mob and Loot Info"],
				text = L["Delete all %s data?\n\nEvery looted mob and drop count is lost."]:format(E:Highlight(L["Mob and Loot Info"])),
				accept = RESET or L["Reset"], danger = true, onAccept = function() M:ResetData() end })
		end },
}
