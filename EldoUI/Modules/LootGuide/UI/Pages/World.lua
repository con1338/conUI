-- EldoUI Loot Guide: the World page.
--
-- Left: the zones the loot data has rares and named mobs for, "zones for
-- your level" or "all zones", each with a "here" pin, the rare count and
-- the level range. It follows the zone you are in until you pick one by
-- hand; the pick lasts until your map changes.
--
-- Right: the zone's header (level, rares, mobs, "you are here", Upgrades
-- only), rare cards three per row (face, level, name, camps, best drops:
-- upgrades first, then usable, then the rest; expand; a Map button that
-- cycles the camps; "seen now" while the game shows the rare's vignette),
-- one line per other mob with its best drop (click to expand), the random
-- world drops for the zone's level band and the footnote on chances.
--
-- Where a creature stands comes from the loot data (world positions); the
-- zone is what the client's map API makes of that position, cached. The
-- "seen now" chip reads the game's own vignettes (C_VignetteInfo); nothing
-- is inferred, and the "Rare spotted" alert stays Fanfare's.
local _, E = ...
local LG = E.LootGuide
local Kit = LG.Kit
local P = LG.PageKit
local L = E.L

local Key = E.Key
local LIST_WIDTH = 230
local CARD_GAP = 8
local CARD_TOP = 64       -- portrait, name, level, camps
local DROP_ROW = 20
local DROPS_SHOWN = 3     -- collapsed card
local DROPS_MAX = 12      -- expanded card
local MOB_DROPS = 8
local WORLD_DROPS = 12

local Secret = E.Secret

-- Window state (scope, Upgrades only, expanded cards). The hand-picked zone
-- is session state: it lasts until your map changes.
local function State()
	local ui = LG:UI()
	if type(ui.world) ~= "table" then ui.world = {} end
	local s = ui.world
	if s.scope ~= "all" then s.scope = "level" end
	if type(s.open) ~= "table" then s.open = {} end
	return s
end

local picked, pickedOn   -- uiMapID picked by hand, the player's map then

---------------------------------------------------------------------------
-- Creature loot
---------------------------------------------------------------------------
local lootCache = {}

-- A rare's WoW: Forever drops from the Forever overlay (Data/Forever.lua):
-- { items, set, setName, confirmed } or nil.
function LG:ForeverRare(npc)
	local data = E.foreverData
	local rares = type(data) == "table" and data.rares
	local rare = type(rares) == "table" and rares[tonumber(npc)]
	if type(rare) == "table" and type(rare.items) == "table" and #rare.items > 0 then return rare end
end

-- True when the character has the item in the bags, the bank or worn.
function LG:HasItem(itemID)
	local api = C_Item
	if not (api and itemID) then return false end
	if api.IsEquippedItem then
		local ok, worn = pcall(api.IsEquippedItem, itemID)
		if ok and worn == true then return true end
	end
	if api.GetItemCount then
		local ok, count = pcall(api.GetItemCount, itemID, true)
		if ok and type(count) == "number" and not E:IsSecret(count) and count > 0 then return true end
	end
	return false
end

-- How many pieces of a rare's Forever set the character has.
function LG:ForeverSetOwned(rare)
	local owned = 0
	for _, itemID in ipairs(rare and rare.items or {}) do
		if self:HasItem(itemID) then owned = owned + 1 end
	end
	return owned
end

-- { { itemID, chance, questOnly, set }, ... } for a creature outside
-- instances: its WoW: Forever drops first, then the loot data's.
function LG:MobLoot(npc)
	npc = tonumber(npc)
	if not npc then return {} end
	if lootCache[npc] then return lootCache[npc] end
	local LD = select(3, self:DataStatus())
	local out = {}
	local rare = self:ForeverRare(npc)
	if rare then
		for _, itemID in ipairs(rare.items) do out[#out + 1] = { itemID = itemID, set = rare.set or true } end
	end
	local packed = LD and LD.loot and LD.loot[npc]
	for item, chance in tostring(packed or ""):gmatch("(%d+):(%-?[%d%.]+)") do
		local value, questOnly = self.ParseChance(chance)
		out[#out + 1] = { itemID = tonumber(item), chance = value, questOnly = questOnly }
	end
	lootCache[npc] = out
	return out
end

---------------------------------------------------------------------------
-- Zone index: rares and named world mobs by the zone of their main camp
---------------------------------------------------------------------------
local index    -- { zones = { [uiMapID] = zone }, list = { zone, ... } }
local unplaced = {} -- npc -> true: the map API could not place it this session

local worldBands -- the world drops' level bands, read once per data

LG:On("world-index", function(changed)
	if changed.data then
		index = nil
		worldBands = nil
		wipe(lootCache)
		wipe(unplaced)
	end
end)

local function DataVersion(LD)
	return tostring(LD.version) .. "/" .. tostring(LD.build)
end

-- The zone (uiMapID) of a creature's biggest camp. Cached per data version
-- (the map API answers the same); 0 is saved only for a creature with no
-- camps in the data. When the client cannot place a camp right now (the map
-- API failing for a moment), that is remembered for this session only, so
-- a later login (or new data) tries again.
local function ZoneOf(npc, store)
	local known = store[npc]
	if known then return known ~= 0 and known or nil end
	if unplaced[npc] then return end
	local camps = LG:SpawnPoints("npc", npc)
	if not camps[1] then
		store[npc] = 0
		return
	end
	local uiMapID = LG:MapPosition(camps[1])
	if uiMapID then store[npc] = uiMapID else unplaced[npc] = true end
	return uiMapID
end

local function BuildIndex()
	local LD = select(3, LG:DataStatus())
	local result = { zones = {}, list = {} }
	if not LD then return result end
	local cache = LG:Cache()
	if type(cache.worldZones) ~= "table" or cache.worldZones.version ~= DataVersion(LD) then
		cache.worldZones = { version = DataVersion(LD), zoneOf = {} }
	end
	local store = cache.worldZones.zoneOf
	local function Add(npc, rare)
		local mob = LG:Mob(npc)
		if not mob or mob.instance then return end
		local uiMapID = mob.forever and mob.map or ZoneOf(npc, store)
		if not uiMapID then return end
		local zone = result.zones[uiMapID]
		if not zone then
			zone = { id = uiMapID, name = LG:MapName(uiMapID) or ("#" .. uiMapID), rares = {}, mobs = {} }
			result.zones[uiMapID] = zone
			result.list[#result.list + 1] = zone
		end
		if rare then zone.rares[#zone.rares + 1] = npc else zone.mobs[#zone.mobs + 1] = npc end
		if mob.minLevel and mob.minLevel > 0 then zone.min = math.min(zone.min or mob.minLevel, mob.minLevel) end
		if mob.maxLevel and mob.maxLevel > 0 then zone.max = math.max(zone.max or mob.maxLevel, mob.maxLevel) end
	end
	local rares = {}
	for _, npc in ipairs(LD.rares or {}) do
		rares[npc] = true
		Add(npc, true)
	end
	-- WoW: Forever rares the loot data lacks, on the map they were seen on.
	local overlay = E.foreverData and E.foreverData.rares
	for npc in pairs(type(overlay) == "table" and overlay or {}) do
		if not rares[npc] and not (LD.mobs and LD.mobs[npc]) then
			rares[npc] = true
			Add(npc, true)
		end
	end
	for _, npc in ipairs(LD.worldMobs or {}) do
		if not rares[npc] then Add(npc, false) end
	end
	local function ByLevel(a, b)
		local ma, mb = LG:Mob(a), LG:Mob(b)
		local la, lb = ma and ma.maxLevel or 0, mb and mb.maxLevel or 0
		if la ~= lb then return la < lb end
		return (ma and ma.name or "") < (mb and mb.name or "")
	end
	for _, zone in ipairs(result.list) do
		table.sort(zone.rares, ByLevel)
		table.sort(zone.mobs, ByLevel)
	end
	table.sort(result.list, function(a, b)
		if (a.min or 0) ~= (b.min or 0) then return (a.min or 0) < (b.min or 0) end
		return a.name < b.name
	end)
	return result
end

function LG:WorldZones()
	if not index then index = BuildIndex() end
	return index
end

-- The zone you are in, as the index knows it (a city or cave map walks up
-- to its zone).
local function PlayerZone()
	if not (C_Map and C_Map.GetBestMapForUnit) then return end
	local ok, uiMapID = pcall(C_Map.GetBestMapForUnit, "player")
	if not ok or Secret(uiMapID) then return end
	local zones = LG:WorldZones().zones
	for _ = 1, 4 do
		if not uiMapID then return end
		if zones[uiMapID] then return uiMapID end
		local info = C_Map.GetMapInfo and C_Map.GetMapInfo(uiMapID)
		uiMapID = type(info) == "table" and not Secret(info.parentMapID) and info.parentMapID or nil
	end
end
LG.WorldPlayerZone = PlayerZone

local function PlayerMap()
	if not (C_Map and C_Map.GetBestMapForUnit) then return end
	local ok, uiMapID = pcall(C_Map.GetBestMapForUnit, "player")
	if ok and not Secret(uiMapID) then return uiMapID end
end

-- current: the player's zone when the caller already has it.
local function SelectedZone(current)
	local zones = LG:WorldZones().zones
	if picked and zones[picked] then return picked, true end
	if current == nil then current = PlayerZone() end
	return current or nil, false
end

-- Hand pick: lasts until the map changes.
function LG:PickWorldZone(uiMapID)
	picked, pickedOn = uiMapID, PlayerMap()
	self:Fire("world")
end

LG:Listen("ZONE_CHANGED_NEW_AREA", "world-zone", function()
	if picked and PlayerMap() ~= pickedOn then picked, pickedOn = nil, nil end
	LG:Fire("world")
end)

---------------------------------------------------------------------------
-- "Seen now": the game's own vignettes
---------------------------------------------------------------------------
local seenNow = {}
local seenGuids = {}     -- vignette guid -> true, from the last full read
local lastScan = -math.huge
local scanQueued = false
local SCAN_GAP = 0.5     -- seconds between two full reads at most

-- The game's vignettes are read only while the World page is on screen.
local function WorldShown()
	local def = LG.GetPage and LG:GetPage("world")
	local frame = def and def.frame
	return frame and frame:IsVisible() and true or false
end

local function NpcFromGUID(guid)
	if type(guid) ~= "string" or Secret(guid) then return end
	local kind, _, _, _, _, id = strsplit("-", guid)
	if kind == "Creature" or kind == "Vehicle" then return tonumber(id) end
end

-- Fires "vignettes" only when the set of creatures seen changed (the
-- minimap event comes every time a vignette moves).
function LG:ScanVignettes()
	local now, guids = {}, {}
	lastScan = GetTime()
	local api = C_VignetteInfo
	if api and api.GetVignettes and api.GetVignetteInfo then
		local ok, list = pcall(api.GetVignettes)
		if ok and type(list) == "table" and not Secret(list) then
			for _, guid in ipairs(list) do
				if type(guid) == "string" and not Secret(guid) then guids[guid] = true end
				local fine, info = pcall(api.GetVignetteInfo, guid)
				if fine and type(info) == "table" then
					local npc = NpcFromGUID(info.objectGUID)
					if npc then now[npc] = true end
				end
			end
		end
	end
	seenGuids = guids
	local changed = false
	for npc in pairs(seenNow) do if not now[npc] then changed = true break end end
	if not changed then
		for npc in pairs(now) do if not seenNow[npc] then changed = true break end end
	end
	if not changed then return end
	seenNow = now
	self:Fire("vignettes")
end

function LG:IsSeenNow(npc)
	return seenNow[tonumber(npc) or 0] == true
end

-- A full read at most every SCAN_GAP seconds, only while World is shown.
local function QueueScan()
	if scanQueued or not WorldShown() then return end
	local wait = lastScan + SCAN_GAP - GetTime()
	if wait <= 0 then
		LG:ScanVignettes()
		return
	end
	scanQueued = true
	C_Timer.After(wait, function()
		scanQueued = false
		if WorldShown() then LG:ScanVignettes() end
	end)
end

LG:Listen("VIGNETTES_UPDATED", "world-vignettes", QueueScan)
-- Comes each time a vignette moves: one already known changes nothing.
LG:Listen("VIGNETTE_MINIMAP_UPDATED", "world-vignettes", function(_, guid)
	if type(guid) == "string" and not Secret(guid) and seenGuids[guid] then return end
	QueueScan()
end)

---------------------------------------------------------------------------
-- Drop order: upgrades, then usable, then the rest; then the chance
---------------------------------------------------------------------------
local function Usable(itemID)
	local record = LG:ItemRecord(itemID)
	if not record then return false end
	return (LG:CanUseRecord(record, true))
end

-- isUpgrade(itemID) defaults to the shared check.
local function SortDrops(drops, isUpgrade)
	isUpgrade = isUpgrade or P.IsUpgrade
	local list = {}
	for _, drop in ipairs(drops) do
		if not drop.questOnly then
			local upgrade = isUpgrade(drop.itemID) and true or false
			list[#list + 1] = { itemID = drop.itemID, chance = drop.chance, upgrade = upgrade, set = drop.set,
				rank = upgrade and 1 or Usable(drop.itemID) and 2 or 3 }
		end
	end
	table.sort(list, function(a, b)
		-- A rare's WoW: Forever set comes first: it is why players hunt it.
		if (a.set ~= nil) ~= (b.set ~= nil) then return a.set ~= nil end
		if a.rank ~= b.rank then return a.rank < b.rank end
		if (a.chance or 0) ~= (b.chance or 0) then return (a.chance or 0) > (b.chance or 0) end
		return a.itemID < b.itemID
	end)
	return list
end

LG.SortMobDrops = function(drops) return SortDrops(drops) end

-- What the page worked out: upgrade marks per item, sorted drops per
-- creature, world drops per zone. Kept while only the view changes (a card
-- opened, another zone, a rare seen); gear, lists, bags, spec or data
-- start it over.
local memo = { upgrade = {}, drops = {}, world = {} }

local function ForgetMemo()
	wipe(memo.upgrade)
	wipe(memo.drops)
	wipe(memo.world)
end

local function IsUpgrade(itemID)
	local known = memo.upgrade[itemID]
	if known == nil then
		known = P.IsUpgrade(itemID) and true or false
		memo.upgrade[itemID] = known
	end
	return known
end

local function SortedDrops(npc)
	local list = memo.drops[npc]
	if not list then
		list = SortDrops(LG:MobLoot(npc), IsUpgrade)
		memo.drops[npc] = list
	end
	return list
end

-- Upgrades sort first, so the best drop tells.
local function HasUpgrade(npc)
	local best = SortedDrops(npc)[1]
	return best ~= nil and best.upgrade
end

local function LevelRange(minLevel, maxLevel)
	if not minLevel then return "?" end
	if not maxLevel or maxLevel == minLevel then return tostring(minLevel) end
	return ("%d-%d"):format(minLevel, maxLevel)
end

local function ZoneLevelText(zone)
	if not zone.min then return "" end
	local info = { min = zone.min, max = zone.max or zone.min }
	return P.LevelText(info)
end

---------------------------------------------------------------------------
-- Rare cards
---------------------------------------------------------------------------
local function DropData(drop, npc)
	local data = P.ChanceData(drop.chance, npc, drop.itemID)
	data.itemID = drop.itemID
	data.onClick = function() P.OpenItem(drop.itemID) end
	local rare = drop.set and LG:ForeverRare(npc)
	if rare then
		data.badge = E:TextHex("accent") .. (L["set %d/%d"]):format(LG:ForeverSetOwned(rare), #rare.items) .. "|r"
	end
	return data
end

local function CreateCard(parent)
	local card = CreateFrame("Frame", nil, parent)
	E:SetTemplate(card, true)
	card.portrait = card:CreateTexture(nil, "ARTWORK")
	card.portrait:SetSize(40, 40)
	card.portrait:SetPoint("TOPLEFT", 8, -8)
	card.name = Kit.Text(card, 12, "LEFT")
	card.name:SetPoint("TOPLEFT", card.portrait, "TOPRIGHT", 8, 0)
	card.name:SetPoint("TOPRIGHT", -8, -8)
	card.name:SetWordWrap(false)
	card.level = Kit.Text(card, 11, "LEFT", "secondary")
	card.level:SetPoint("TOPLEFT", card.name, "BOTTOMLEFT", 0, -2)
	card.camps = Kit.Text(card, 10, "LEFT", "secondary")
	card.camps:SetPoint("TOPLEFT", card.level, "BOTTOMLEFT", 0, -2)
	card.seen = Kit.Chip(card, "")
	card.seen:SetLabel(L["Seen now"], unpack(Kit.GOOD))
	card.seen:SetPoint("TOPRIGHT", -6, -6)
	Kit.Tooltip(card.seen, L["Seen now"], L["The game shows this rare on your minimap right now."])
	card.map = Kit.Button(card, L["Map"], 46, 18)
	card.map:SetPoint("TOPRIGHT", -6, -40)
	card.more = Kit.Button(card, "", 60, 16)
	card.more:SetPoint("BOTTOMRIGHT", -6, 4)
	card.cells = {}
	return card
end

local function FillCard(card, npc, page)
	local s = State()
	local mob = LG:Mob(npc)
	card.npc = npc
	local portrait = false
	local setPortrait = rawget(_G, "SetPortraitTextureFromCreatureDisplayID")
	if mob and mob.display and setPortrait then portrait = pcall(setPortrait, card.portrait, mob.display) end
	if not portrait then
		card.portrait:SetTexture("Interface\\Icons\\INV_Misc_Head_Dragon_01")
		E:TrimIcon(card.portrait)
	else
		card.portrait:SetTexCoord(0, 1, 0, 1)
	end
	local name = mob and mob.name or L["NPC %s"]:format(npc)
	card.name:SetText(name)
	local levelHex = Kit.Hex(Kit.LevelColor(mob and mob.maxLevel or 1))
	card.level:SetText(levelHex .. (L["Level %s"]):format(LevelRange(mob and mob.minLevel, mob and mob.maxLevel))
		.. "|r  " .. (P.WORLD_RANK[mob and mob.rank or 4] or L["Rare"]))
	local camps = LG:SpawnPoints("npc", npc)
	if mob and mob.forever then
		-- A WoW: Forever rare the loot data lacks: where a player saw it.
		card.camps:SetText(mob.x and mob.y and (L["Seen at %d, %d"]):format(math.floor(mob.x * 100 + 0.5), math.floor(mob.y * 100 + 0.5)) or "")
	else
		card.camps:SetText(E:Plural(#camps, "%d camp", "%d camps"):format(#camps))
	end
	card.seen:SetShown(LG:IsSeenNow(npc))
	local button = P.MapButton("npc", npc, name)
	card.map:SetScript("OnClick", button[2])
	card.map:SetEnabled(not button[5])
	Kit.Tooltip(card.map, button[3], button[4])
	-- Drops.
	local drops = SortedDrops(npc)
	local open = s.open[npc]
	local shown = math.min(#drops, open and DROPS_MAX or DROPS_SHOWN)
	for i = 1, shown do
		local cell = card.cells[i]
		if not cell then
			cell = P.ItemCell(card)
			card.cells[i] = cell
		end
		cell:ClearAllPoints()
		cell:SetPoint("TOPLEFT", 6, -(CARD_TOP + (i - 1) * DROP_ROW))
		cell:SetPoint("TOPRIGHT", -6, -(CARD_TOP + (i - 1) * DROP_ROW))
		cell:SetHeight(DROP_ROW - 2)
		P.SetItem(cell, DropData(drops[i], npc))
		cell:Show()
	end
	for i = shown + 1, #card.cells do card.cells[i]:Hide() end
	if #drops > DROPS_SHOWN then
		card.more:SetText(open and L["Less"] or (L["+%d more"]):format(#drops - DROPS_SHOWN))
		card.more:SetWidth(math.ceil((card.more:GetFontString() and card.more:GetFontString():GetStringWidth() or 40) + 16))
		card.more:SetScript("OnClick", function()
			s.open[npc] = not s.open[npc] or nil
			page:Draw(true, true)
		end)
		Kit.Tooltip(card.more, open and L["Less"] or L["More"], open and L["Shows the three best drops only."] or L["Shows every drop of this rare."])
		card.more:Show()
	elseif #drops == 0 then
		card.more:Hide()
	else
		card.more:Hide()
	end
	card.empty = #drops == 0
	local height = CARD_TOP + shown * DROP_ROW + (#drops > DROPS_SHOWN and 22 or 6)
	if #drops == 0 then height = CARD_TOP + 4 end
	card:Show()
	return height
end

local function CardRow(child)
	local row = CreateFrame("Frame", nil, child)
	row.cards = {}
	for i = 1, 3 do row.cards[i] = CreateCard(row) end
	return row
end

-- One row of three cards per block, built when it scrolls into view.
local CARD_ROW_ESTIMATE = CARD_TOP + DROPS_SHOWN * DROP_ROW + 22 + CARD_GAP

local function PlaceCardRow(page, flow, rares, start)
	local width = math.floor((flow:Width() - 2 * CARD_GAP) / 3)
	local row = flow:Take("rarecards", CardRow)
	local tallest = 0
	for i = 1, 3 do
		local card = row.cards[i]
		card:ClearAllPoints()
		card:SetPoint("TOPLEFT", (i - 1) * (width + CARD_GAP), 0)
		card:SetWidth(width)
		local npc = rares[start + i - 1]
		if npc then
			local height = FillCard(card, npc, page)
			tallest = math.max(tallest, height)
		else
			card:Hide()
		end
	end
	for i = 1, 3 do
		if row.cards[i]:IsShown() then row.cards[i]:SetHeight(tallest) end
	end
	flow:Place(row, tallest, 0, CARD_GAP)
end

local function PlaceCards(page, flow, rares)
	for start = 1, #rares, 3 do
		flow:Defer(CARD_ROW_ESTIMATE, function(f) PlaceCardRow(page, f, rares, start) end)
	end
end

---------------------------------------------------------------------------
-- Zone body
---------------------------------------------------------------------------
-- { { itemID, a, b, chance }, ... }: the world drops' bands, read once.
local function WorldBands()
	if worldBands then return worldBands end
	worldBands = {}
	local LD = select(3, LG:DataStatus())
	for itemID, band in pairs(LD and LD.worldDrops or {}) do
		local a, b, chance = tostring(band):match("^(%d+)%-(%d+):(.+)$")
		a, b = tonumber(a), tonumber(b)
		if a and b then worldBands[#worldBands + 1] = { itemID = itemID, a = a, b = b, chance = tonumber(chance) } end
	end
	return worldBands
end

-- Every usable world drop of the zone's level band, upgrades first.
local function ZoneWorldDrops(zone)
	local list = memo.world[zone.id]
	if list then return list end
	list = {}
	if zone.min then
		local lo, hi = zone.min, zone.max or zone.min
		for _, band in ipairs(WorldBands()) do
			local itemID = band.itemID
			if band.a <= hi and band.b >= lo then
				local record = LG:ItemRecord(itemID)
				if record and (record.quality or 0) >= 2 and LG:SlotGroup(itemID) and Usable(itemID) then
					list[#list + 1] = { itemID = itemID, chance = band.chance, upgrade = IsUpgrade(itemID), level = record.itemLevel or 0,
						band = ("%d-%d"):format(band.a, band.b) }
				end
			end
		end
		table.sort(list, function(x, y)
			if x.upgrade ~= y.upgrade then return x.upgrade end
			if x.level ~= y.level then return x.level > y.level end
			return x.itemID < y.itemID
		end)
	end
	memo.world[zone.id] = list
	return list
end

local function WorldDropsFor(zone, upgradesOnly)
	local all = ZoneWorldDrops(zone)
	if not upgradesOnly then return all, #all end
	local out = {}
	for _, drop in ipairs(all) do
		if drop.upgrade then out[#out + 1] = drop end
	end
	return out, #out
end

local function DrawZone(page)
	local s = State()
	local flow = page.flow
	local zones = LG:WorldZones()
	local selected, byHand = SelectedZone(page.current)
	local zone = selected and zones.zones[selected]
	page.selected = selected
	flow:Begin()
	if not zone then
		page.header:Hide()
		page.flow:ClearAllPoints()
		page.flow:SetPoint("TOPLEFT", page.list, "TOPRIGHT", 14, 0)
		page.flow:SetPoint("BOTTOMRIGHT")
		P.FlowCaption(flow, L["Pick a zone"])
		P.FlowText(flow, L["The loot data has no rares or named creatures for the zone you are in. Pick a zone on the left."], 12, "secondary")
		flow:Finish()
		return
	end
	page.header:Show()
	page.flow:ClearAllPoints()
	page.flow:SetPoint("TOPLEFT", page.header, "BOTTOMLEFT", 0, -6)
	page.flow:SetPoint("BOTTOMRIGHT")
	local here = page.current == zone.id
	page.header.name:SetText(zone.name)
	page.header.facts:SetText(("%s  ·  %s  ·  %s"):format((L["Level %s"]):format(ZoneLevelText(zone)),
		E:Plural(#zone.rares, "%d rare", "%d rares"):format(#zone.rares),
		E:Plural(#zone.mobs, "%d other creature", "%d other creatures"):format(#zone.mobs)))
	page.header.here:SetShown(here)
	page.header.follow:SetShown(byHand)
	-- Best in Slot off: no gain marks, so no Upgrades only either.
	local upgradesOnly = s.upgradesOnly and LG:BiSOn()
	page.header.upgrades:SetShown(LG:BiSOn())
	page.header.upgrades:SetOn(upgradesOnly)
	-- Rares.
	local rares = {}
	for _, npc in ipairs(zone.rares) do
		if not upgradesOnly or HasUpgrade(npc) then rares[#rares + 1] = npc end
	end
	-- Seen now first, then upgrades, then level (keys worked out once).
	local keys = {}
	for _, npc in ipairs(rares) do
		local mob = LG:Mob(npc)
		keys[npc] = { seen = LG:IsSeenNow(npc), up = HasUpgrade(npc), level = mob and mob.maxLevel or 0 }
	end
	table.sort(rares, function(a, b)
		local ka, kb = keys[a], keys[b]
		if ka.seen ~= kb.seen then return ka.seen end
		if ka.up ~= kb.up then return ka.up end
		if ka.level ~= kb.level then return ka.level < kb.level end
		return a < b
	end)
	page.rares = rares
	if #zone.rares > 0 then
		P.FlowCaption(flow, L["Rares"], upgradesOnly and (L["%d of %d with an upgrade"]):format(#rares, #zone.rares) or tostring(#rares))
		if #rares > 0 then
			PlaceCards(page, flow, rares)
		else
			P.FlowText(flow, L["No rare here drops an upgrade for you."], 12, "secondary")
		end
	end
	-- Other creatures.
	local mobs = {}
	for _, npc in ipairs(zone.mobs) do
		if not upgradesOnly or HasUpgrade(npc) then mobs[#mobs + 1] = npc end
	end
	page.mobs = mobs
	if #zone.mobs > 0 then
		flow:Defer(40, function()
			P.FlowCaption(flow, L["Other creatures"], upgradesOnly and (L["%d of %d with an upgrade"]):format(#mobs, #zone.mobs) or tostring(#mobs))
			if #mobs == 0 then P.FlowText(flow, L["No other creature here drops an upgrade for you."], 12, "secondary") end
		end)
		for _, npc in ipairs(mobs) do
			-- One line per creature (and its open drops), built when it
			-- scrolls into view.
			local estimate = s.open[npc] and (22 + MOB_DROPS * (math.max(Kit.RowHeight(), 20) + 2) + 18) or 22
			flow:Defer(estimate, function()
				local mob = LG:Mob(npc)
				local name = mob and mob.name or L["NPC %s"]:format(npc)
				local drops = SortedDrops(npc)
				local best = drops[1]
				local bestText = ""
				if best then
					local record = LG:ItemRecord(best.itemID)
					local r, g, b = Kit.QualityColor(record and record.quality or 1)
					bestText = "  " .. E:TextHex("secondary") .. L["best:"] .. "|r " .. Kit.Hex(r, g, b) .. (record and record.name or ("item:" .. best.itemID)) .. "|r"
						.. (best.upgrade and ("  " .. Kit.Hex(unpack(Kit.GOOD)) .. L["upgrade"] .. "|r") or "")
				end
				local open = s.open[npc]
				local text = (open and "- " or "+ ") .. name .. "  " .. Kit.Hex(Kit.LevelColor(mob and mob.maxLevel or 1))
					.. LevelRange(mob and mob.minLevel, mob and mob.maxLevel) .. "|r" .. bestText
				P.FlowLine(flow, text, function()
					s.open[npc] = not s.open[npc] or nil
					page:Draw(true, true)
				end, P.MapButton("npc", npc, name), name, E:Plural(#drops, "%d known drop. Click to show or hide it.", "%d known drops. Click to show or hide them."):format(#drops))
				if open then
					for i = 1, math.min(#drops, MOB_DROPS) do P.FlowItem(flow, DropData(drops[i], npc), 16) end
					if #drops > MOB_DROPS then
						P.FlowText(flow, (L["and %d more"]):format(#drops - MOB_DROPS), 11, "secondary", 16)
					elseif #drops == 0 then
						P.FlowText(flow, L["No known drops."], 11, "secondary", 16)
					end
				end
			end)
		end
	end
	-- World drops for the zone's level band.
	local drops, total = WorldDropsFor(zone, upgradesOnly)
	page.worldDrops = drops
	flow:Defer(60 + math.min(#drops, WORLD_DROPS) * (math.max(Kit.RowHeight(), 20) + 2), function()
		P.FlowCaption(flow, L["Random world drops"], (L["level %s, any creature"]):format(LevelRange(zone.min, zone.max)))
		if #drops == 0 then
			P.FlowText(flow, upgradesOnly and L["No random world drop for this level is an upgrade for you."]
				or L["No random world drop for this level fits you."], 12, "secondary")
		end
		for i = 1, math.min(#drops, WORLD_DROPS) do
			local d = drops[i]
			local data = DropData(d, nil)
			data.sub = (L["Random world drop, level %s"]):format(d.band)
			P.FlowItem(flow, data)
		end
		if total > WORLD_DROPS then
			P.FlowText(flow, (L["and %d more; Search finds them by name."]):format(total - WORLD_DROPS), 11, "secondary")
		end
		flow:Space(8)
		P.FlowText(flow, L["Chances are Classic values; Forever may differ."], 11, "dim")
	end)
	flow:Finish(page.keepScroll)
end

---------------------------------------------------------------------------
-- Zone list
---------------------------------------------------------------------------
local function ZoneRows(current)
	local s = State()
	local level = LG:Player().level
	local rows = {}
	for _, zone in ipairs(LG:WorldZones().list) do
		local info = { min = zone.min, max = zone.max or zone.min }
		local fit = zone.min and LG:FitsLevel(info, level)
		if s.scope == "all" or fit == "fit" or fit == "near" or zone.id == current then rows[#rows + 1] = zone end
	end
	return rows
end

local function CreateZoneRow(row)
	E:SkinRow(row)
	row:RegisterForClicks("LeftButtonUp")
	row.mark = row:CreateTexture(nil, "OVERLAY")
	row.mark:SetPoint("TOPLEFT")
	row.mark:SetPoint("BOTTOMLEFT")
	row.mark:SetWidth(2)
	E:AccentTexture(row.mark, 1)
	row.pin = row:CreateTexture(nil, "OVERLAY")
	row.pin:SetSize(12, 12)
	row.pin:SetPoint("LEFT", 6, 0)
	if Kit.HasAtlas("Waypoint-MapPin-ChatIcon") then row.pin:SetAtlas("Waypoint-MapPin-ChatIcon") else row.pin:SetColorTexture(Kit.Accent()) end
	row.level = Kit.Text(row, 11, "RIGHT", "secondary")
	row.level:SetPoint("RIGHT", -6, 0)
	row.rares = Kit.Text(row, 11, "RIGHT")
	row.rares:SetPoint("RIGHT", row.level, "LEFT", -6, 0)
	row.name = Kit.Text(row, 12, "LEFT")
	row.name:SetPoint("LEFT", 22, 0)
	row.name:SetPoint("RIGHT", row.rares, "LEFT", -4, 0)
	row.name:SetWordWrap(false)
	row:SetScript("OnClick", function(self)
		if self.item then LG:PickWorldZone(self.item.id) end
	end)
	row:SetScript("OnEnter", function(self)
		local zone = self.item
		if not zone then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		E.UIKit.TipTitle(GameTooltip, zone.name)
		local r, g, b = unpack(Kit.SECONDARY)
		GameTooltip:AddDoubleLine(L["Level"], ZoneLevelText(zone), r, g, b, 1, 1, 1)
		GameTooltip:AddDoubleLine(L["Rares"], tostring(#zone.rares), r, g, b, 1, 1, 1)
		GameTooltip:AddDoubleLine(L["Other creatures"], tostring(#zone.mobs), r, g, b, 1, 1, 1)
		if PlayerZone() == zone.id then GameTooltip:AddLine(L["You are here."], unpack(Kit.GOOD)) end
		GameTooltip:AddLine(" ")
		E.UIKit.TipText(GameTooltip, L["The guide goes back to following your zone when your map changes."])
		E:TooltipHint(GameTooltip, { L["Click"], L["show it"] })
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function UpdateZoneRow(row, zone)
	local page = row.list.page
	local selected = page and page.selected == zone.id
	row.mark:SetShown(selected)
	row.name:SetText(zone.name)
	if selected then row.name:SetTextColor(E:TokenColor("accent")) else Kit.Paint(row.name) end
	row.pin:SetShown(page ~= nil and page.current == zone.id)
	row.rares:SetText(#zone.rares > 0 and (E:TextHex("accent") .. #zone.rares .. "|r") or "")
	row.level:SetText(ZoneLevelText(zone))
end

local function ScopeMenu(owner, page)
	E.UIKit.ContextMenu(owner, function(_, root)
		root:CreateRadio(L["Zones for your level"], function() return State().scope == "level" end, function()
			State().scope = "level"
			page:Draw(nil, true)
		end)
		root:CreateRadio(L["All zones"], function() return State().scope == "all" end, function()
			State().scope = "all"
			page:Draw(nil, true)
		end)
	end, { at = "owner" })
end

---------------------------------------------------------------------------
-- Page
---------------------------------------------------------------------------
local function Create(parent)
	local page = CreateFrame("Frame", nil, parent)
	page:SetAllPoints()
	page.scope = P.Toggle(page, "", function(self) ScopeMenu(self, page) end, L["Zones"],
		L["Zones for your level, or every zone the loot data knows creatures for."])
	page.scope:SetPoint("TOPLEFT", 0, 0)
	page.count = Kit.Text(page, 11, "RIGHT", "secondary")
	page.count:SetPoint("TOPLEFT", LIST_WIDTH - 60, -3)
	page.count:SetWidth(60)
	page.list = Kit.CreateList(page, { rowHeight = 22, create = CreateZoneRow, update = UpdateZoneRow, gap = 1 })
	page.list.page = page
	page.list:SetPoint("TOPLEFT", 0, -24)
	page.list:SetPoint("BOTTOMLEFT")
	page.list:SetWidth(LIST_WIDTH)
	page.line = page:CreateTexture(nil, "ARTWORK")
	page.line:SetWidth(E.pixel)
	page.line:SetColorTexture(unpack(E.tokens.edge.divider))
	page.line:SetPoint("TOPLEFT", page.list, "TOPRIGHT", 6, 24)
	page.line:SetPoint("BOTTOMLEFT", page.list, "BOTTOMRIGHT", 6, 0)
	-- Header.
	local header = CreateFrame("Frame", nil, page)
	header:SetPoint("TOPLEFT", LIST_WIDTH + 14, 0)
	header:SetPoint("TOPRIGHT")
	header:SetHeight(40)
	header.name = Kit.Text(header, 15, "LEFT")
	header.name:SetPoint("TOPLEFT", 0, -2)
	header.here = Kit.Chip(header, "")
	header.here:SetLabel(L["You are here"], Kit.Accent())
	header.here:SetPoint("LEFT", header.name, "RIGHT", 8, 0)
	Kit.Tooltip(header.here, L["You are here"], L["The game's map says you are in this zone."])
	header.facts = Kit.Text(header, 11, "LEFT", "secondary")
	header.facts:SetPoint("TOPLEFT", header.name, "BOTTOMLEFT", 0, -4)
	header.upgrades = P.Toggle(header, L["Upgrades only"], function()
		local s = State()
		s.upgradesOnly = not s.upgradesOnly
		page:Draw(nil, true)
	end, L["Upgrades only"], L["Shows only rares and creatures that drop an upgrade for you."])
	header.upgrades:SetPoint("TOPRIGHT", 0, -2)
	header.follow = Kit.Button(header, L["My zone"], 70, 18, function()
		picked, pickedOn = nil, nil
		page:Draw(nil, true)
	end, L["My zone"], L["Goes back to the zone you are in."])
	header.follow:SetPoint("RIGHT", header.upgrades, "LEFT", -6, 0)
	page.header = header
	-- Virtual: long zones build their cards and lines as you scroll.
	page.flow = P.Flow(page, { virtual = true })
	page.flow:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -6)
	page.flow:SetPoint("BOTTOMRIGHT")
	-- keepMemo: only the view changed, the upgrade checks still hold.
	function page:Draw(keepScroll, keepMemo)
		if not keepMemo then ForgetMemo() end
		local s = State()
		self.scope:SetLabel((s.scope == "all" and L["All zones"] or L["Zones for your level"]), true)
		self.current = PlayerZone() or false
		local rows = ZoneRows(self.current)
		self.count:SetText(tostring(#rows))
		self.keepScroll = keepScroll
		DrawZone(self)
		self.list:SetData(rows)
		if self.selected then
			for i, zone in ipairs(rows) do
				if zone.id == self.selected then self.list:ScrollTo(i) break end
			end
		end
	end
	-- New item data: the item rows on the page paint again (names, icons,
	-- upgrade marks); the order stays until something else changes.
	function page:RepaintItems()
		for _, widget in ipairs(self.flow.used) do
			if widget.flowKind == "item" then
				if widget.data then P.SetItem(widget, widget.data) end
			elseif widget.cards then
				for _, card in ipairs(widget.cards) do
					if card:IsShown() then
						for _, cell in ipairs(card.cells) do
							if cell:IsShown() and cell.data then P.SetItem(cell, cell.data) end
						end
					end
				end
			end
		end
	end
	return page
end

local function Show(page, arg)
	if tonumber(arg) and LG:WorldZones().zones[tonumber(arg)] then picked, pickedOn = tonumber(arg), PlayerMap() end
	LG:ScanVignettes()
	page:Draw()
	Kit.Tour("world", {
		{ target = page.scope, text = L["Zones for your level or all zones. The guide follows your zone until you click one."] },
		{ target = page.header.upgrades, text = L["Upgrades only hides creatures with nothing for you. Map on a rare card pins its camps, one per click."] },
	})
end

local function Refresh(page, changed)
	local relevant = changed.data or changed.gear or changed.list or changed.spec or changed.rank or changed.player
		or changed.settings or changed.wishlist or changed.bags
	if relevant or changed.world or changed.vignettes then
		page:Draw(not (changed.world or changed.data), not relevant)
	elseif changed.items then
		page:RepaintItems()
	end
end

local function Empty()
	if not LG:HasData() then
		return L["World needs the loot data"],
			L["Rares, creatures and their camps come from EldoUI_LootData. Install it next to EldoUI and reload."], LG.ICON, {
				{ L["Show data status"], function() LG:PrintDataStatus() end, L["Prints where the loot data comes from (same as /lg data)."] },
			}
	end
	if #LG:WorldZones().list == 0 then
		return L["No zones placed yet"], L["The game's map could not place any creature camp. Open the world map once and come back."], LG.ICON
	end
end

-- "/eui world westfall" -> that zone.
local function Alias(text)
	text = E:FoldText(text or "")
	if text == "" then return end
	for _, zone in ipairs(LG:WorldZones().list) do
		if E:FoldText(zone.name) == text then return zone.id end
	end
	for _, zone in ipairs(LG:WorldZones().list) do
		if #text >= 3 and E:FoldText(zone.name):find(text, 1, true) then return zone.id end
	end
end

LG:RegisterPage("world", {
	title = "World",
	desc = "Rares and creatures by zone: their best drops for you, their camps on your map and which rares the game shows near you now.",
	order = 30,
	command = "world",
	usage = Key("open World; add a zone name (/eui world westfall)"),
	create = Create,
	show = Show,
	refresh = Refresh,
	empty = Empty,
	alias = Alias,
})
