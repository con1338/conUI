-- EldoUI Loot Guide: the Database page.
--
--   [Items][Mobs][Quests][Places]  [search ............]  1,234  [switch] [Sort v] [Reset]
--   +-----------+-------------------------------------------+--------------+
--   | filters   |  sortable table (virtual rows)            |  detail      |
--   +-----------+-------------------------------------------+--------------+
--
-- Four tables over the loot data and the quest engine: Items, Mobs, Quests
-- and Places. Every table has its search, one switch, a sort control, its
-- filters on the left (chips with "All", checks with colored dots, a
-- two-knob level range), sortable headers and a detail panel on the right
-- with one main action and up to three icon actions. The state lasts the
-- session (not saved); Reset puts the open table back.
--
-- Other pages route here with LG:Open("database", { tab = "items", id = 19019 }).
-- Presentation only: every action opens a page, a map pin or the dressing
-- room.
local _, E = ...
local LG = E.LootGuide
local Kit = LG.Kit
local P = LG.PageKit
local L = E.L

local Key = E.Key
local FILTER_WIDTH = 190
local DETAIL_WIDTH = 260
local TOP = 28
local MAX_LEVEL = 60

local Secret = E.Secret

local function Fold(text)
	return E:FoldText(tostring(text or ""))
end

local TAB_ORDER = { "items", "mobs", "quests", "places" }

---------------------------------------------------------------------------
-- Session state (not saved)
---------------------------------------------------------------------------
local defs = {}       -- tab -> table definition (below)
LG.databaseTables = defs -- read-only for plugins: rows(), filters, match(row, state)
local state = {}      -- tab -> { search, switch, sort, down, filters, selected }
local current = "items"

local function Fresh(tab)
	local def = defs[tab]
	return { search = "", switch = false, sort = def.sorts[1][1], down = def.sorts[1][3] or false, filters = {}, selected = nil }
end

local function State(tab)
	tab = tab or current
	if not state[tab] then state[tab] = Fresh(tab) end
	return state[tab]
end

function LG:ResetDatabase(tab)
	if tab then state[tab] = nil else wipe(state) end
	self:Fire("database")
end

---------------------------------------------------------------------------
-- Shared caches (per data load and per ranking)
---------------------------------------------------------------------------
local base = {}        -- tab -> rows built from the data
local forYou = {}      -- "item:<id>" / "mob:<npc>" / "place:<key>" -> number

LG:On("database-cache", function(changed)
	if changed.data then wipe(base) end
	if changed.data or changed.gear or changed.list or changed.spec or changed.rank or changed.player or changed.bags then wipe(forYou) end
end)

local function ItemGain(itemID)
	local key = "item:" .. itemID
	local value = forYou[key]
	if value == nil then
		value = false
		if LG:BiSOn() and not LG:Owns(itemID) then
			local target = LG:UpgradeTargets(itemID)[1]
			if target then value = target.worn and target.worn > 0 and (target.gain / target.worn * 100) or 100 end
		end
		forYou[key] = value
	end
	return value or nil
end

local function GainLabel(value)
	if not value then return "" end
	return Kit.Hex(unpack(Kit.GOOD)) .. ("+%.1f%%"):format(value) .. "|r"
end

local function Usable(record)
	if not record then return false end
	return (LG:CanUseRecord(record, true))
end

---------------------------------------------------------------------------
-- Labels
---------------------------------------------------------------------------
local GROUP_FALLBACK = {
	head = Key("Head"), neck = Key("Neck"), shoulder = Key("Shoulder"), back = Key("Back"), chest = Key("Chest"), wrist = Key("Wrist"),
	hands = Key("Hands"), waist = Key("Waist"), legs = Key("Legs"), feet = Key("Feet"), finger = Key("Finger"), trinket = Key("Trinket"),
	mainhand = Key("Main hand"), offhand = Key("Off hand"), twohand = Key("Two-hand"), onehand = Key("One-hand"), ranged = Key("Ranged"),
	relic = Key("Relic"),
}
local function GroupLabel(group)
	if not group then return L["Other"] end
	local text = rawget(_G, "INVTYPE_" .. (({ head = "HEAD", neck = "NECK", shoulder = "SHOULDER", back = "CLOAK", chest = "CHEST",
		wrist = "WRIST", hands = "HAND", waist = "WAIST", legs = "LEGS", feet = "FEET", finger = "FINGER", trinket = "TRINKET",
		mainhand = "WEAPONMAINHAND", offhand = "WEAPONOFFHAND", twohand = "2HWEAPON", onehand = "WEAPON", ranged = "RANGED",
		relic = "RELIC" })[group] or ""))
	if type(text) == "string" and not Secret(text) then return text end
	return E:Translate(GROUP_FALLBACK[group]) or group
end

local QUALITY_LABEL = { [0] = Key("Poor"), [1] = Key("Common"), [2] = Key("Uncommon"), [3] = Key("Rare"), [4] = Key("Epic"), [5] = Key("Legendary") }
local TYPE_LABEL = { boss = Key("Boss"), rare = Key("Rare"), elite = Key("Elite"), normal = Key("Normal") }
local STATUS_LABEL = {
	turnin = Key("Ready to turn in"), active = Key("In your log"), available = Key("Available"), locked = Key("Locked"),
	low = Key("Level too low"), done = Key("Done"), notforyou = Key("Not for you"),
}
local STATUS_ORDER = { turnin = 1, active = 2, available = 3, locked = 4, low = 5, done = 6, notforyou = 7 }
local PLACE_LABEL = { dungeon = Key("Dungeon"), raid = Key("Raid"), zone = Key("Zone") }

local function MobType(mob)
	local rank = mob and mob.rank or 0
	if rank == 3 then return "boss" end
	if rank == 2 or rank == 4 then return "rare" end
	if rank == 1 then return "elite" end
	return "normal"
end

local function LevelRange(a, b)
	if not a then return "" end
	if not b or a == b then return tostring(a) end
	return ("%d-%d"):format(a, b)
end

---------------------------------------------------------------------------
-- Items
---------------------------------------------------------------------------
local sourceCache = {}
LG:On("database-sources", function(changed) if changed.data then wipe(sourceCache) end end)

-- dungeon, raid, rare, world, quest or other (the first that fits).
local function SourceKinds(itemID)
	local kinds = sourceCache[itemID]
	if kinds then return kinds end
	kinds = {}
	for _, entry in ipairs(LG:ItemSources(itemID) or {}) do
		if entry.kind == "npc" or entry.kind == "object" then
			local info = entry.instance and LG:InstanceInfo(entry.instance)
			if info then
				kinds[info.kind == "raid" and "raid" or "dungeon"] = true
			elseif entry.rank == 2 or entry.rank == 4 then
				kinds.rare = true
			else
				kinds.world = true
			end
		elseif entry.kind == "world" then
			kinds.world = true
		elseif entry.kind == "quest" or entry.kind == "choice" then
			kinds.quest = true
		else
			kinds.other = true
		end
	end
	if not next(kinds) then kinds.other = true end
	sourceCache[itemID] = kinds
	return kinds
end

local function ItemRows()
	local LD = select(3, LG:DataStatus())
	local rows = {}
	for itemID in pairs(LD and LD.items or {}) do
		local record = LG:ItemRecord(itemID)
		if record then
			rows[#rows + 1] = { id = itemID, name = record.name or "", fold = Fold(record.name), quality = record.quality or 1,
				level = record.reqLevel or 0, ilvl = record.itemLevel or 0, group = LG:SlotGroup(itemID), record = record }
		end
	end
	return rows
end

local function VerdictLine(itemID, record)
	local ok, reason = LG:CanUseRecord(record)
	if not ok then
		if reason == "skill" then return L["Profession needed"], Kit.WARN end
		if reason == "armor" or reason == "weapon" or reason == "class" or reason == "race" then
			return L["Your class can't use this"], Kit.BAD
		end
	end
	local useLevel = LG:UseLevel(itemID) or 1
	if useLevel > LG:Player().level then return (L["From level %d"]):format(useLevel), Kit.WARN end
	local gain = ItemGain(itemID)
	if gain then return (L["Upgrade: %s"]):format(("+%.1f%%"):format(gain)), Kit.GOOD end
	if LG:Owns(itemID) then return L["You have it"], Kit.SECONDARY end
	return L["Not an upgrade now"], Kit.SECONDARY
end

local function InsertChatLink(link)
	if link then Kit.InsertLink(link) end
end

defs.items = {
	title = "Items",
	switch = { Key("Usable by me"), Key("Only items your class, race and professions can use (any level).") },
	sorts = { { "foryou", Key("For you"), true }, { "level", Key("Level") }, { "name", Key("Name") }, { "quality", Key("Quality"), true } },
	filters = {
		{ key = "slot", kind = "chips", title = "Slot", options = function()
			local out = {}
			for _, group in ipairs(LG.SLOT_GROUPS) do out[#out + 1] = { group, GroupLabel(group) } end
			out[#out + 1] = { "none", L["Not gear"] }
			return out
		end },
		{ key = "quality", kind = "checks", title = "Quality", options = function()
			local out = {}
			for q = 0, 5 do out[#out + 1] = { q, L[QUALITY_LABEL[q]], { Kit.QualityColor(q) } } end
			return out
		end },
		{ key = "level", kind = "range", title = "Required level" },
		{ key = "source", kind = "chips", title = "Source", options = function()
			return { { "dungeon", L["Dungeon"] }, { "raid", L["Raid"] }, { "rare", L["Rare"] }, { "world", L["World"] },
				{ "quest", L["Quest"] }, { "other", L["Other"] } }
		end },
	},
	columns = {
		{ key = "name", title = "Item", desc = "The item; its color is its quality.",
			text = function(row)
				local icon = C_Item.GetItemIconByID and C_Item.GetItemIconByID(row.id)
				local r, g, b = Kit.QualityColor(row.quality)
				return (not Secret(icon) and icon and ("|T" .. icon .. ":14:14:0:0:64:64:5:59:5:59|t ") or "") .. Kit.Hex(r, g, b) .. row.name .. "|r"
			end },
		{ key = "slot", title = "Slot", width = 110, value = function(row) return row.group and GroupLabel(row.group) or "" end },
		{ key = "level", title = "Level", width = 56, align = "RIGHT", value = function(row) return row.level end,
			text = function(row) return row.level > 0 and tostring(row.level) or "" end },
		{ key = "foryou", title = "For you", width = 76, align = "RIGHT", desc = "What the item adds over what you wear, with your stat priority.",
			value = function(row) return ItemGain(row.id) or -1 end, text = function(row) return GainLabel(ItemGain(row.id)) end },
	},
	rows = ItemRows,
	match = function(row, st)
		local f = st.filters
		if st.switch and not Usable(row.record) then return false end
		if f.slot and not f.slot[row.group or "none"] then return false end
		if f.quality and not f.quality[row.quality] then return false end
		if f.level and (row.level < f.level[1] or row.level > f.level[2]) then return false end
		if f.source then
			local any = false
			for kind in pairs(SourceKinds(row.id)) do if f.source[kind] then any = true end end
			if not any then return false end
		end
		return true
	end,
	sortValue = {
		foryou = function(row) return ItemGain(row.id) or -1 end,
		level = function(row) return row.level end,
		name = function(row) return row.fold end,
		quality = function(row) return row.quality end,
	},
	detail = function(pane, row)
		local flow = pane.flow
		local record = row.record
		local itemID = row.id
		local cell = P.FlowItem(flow, { itemID = itemID, onClick = function() P.OpenItem(itemID) end })
		local r, g, b = Kit.QualityColor(row.quality)
		if cell.iconBox and cell.iconBox.SetBackdropBorderColor then cell.iconBox:SetBackdropBorderColor(r, g, b) end
		local text, color = VerdictLine(itemID, record)
		P.FlowText(flow, Kit.Hex(unpack(color)) .. text .. "|r", 12)
		local facts = {}
		if row.group then facts[#facts + 1] = GroupLabel(row.group) end
		if row.level > 0 then facts[#facts + 1] = (L["requires level %d"]):format(row.level) end
		if row.ilvl > 0 then facts[#facts + 1] = (L["item level %d"]):format(row.ilvl) end
		if #facts > 0 then P.FlowText(flow, table.concat(facts, "  ·  "), 11, "secondary") end
		local engine = E.ItemScore
		local stats = {}
		for key, value in pairs(record.stats or {}) do
			stats[#stats + 1] = ("%s%d %s"):format(value > 0 and "+" or "", value, engine and engine.StatLabel and engine.StatLabel(key) or key)
		end
		table.sort(stats)
		if #stats > 0 then
			P.FlowCaption(flow, L["Stats"])
			P.FlowText(flow, table.concat(stats, "\n"), 11)
		end
		local sources = LG:ItemSources(itemID) or {}
		if #sources > 0 then
			P.FlowCaption(flow, L["Sources"], tostring(#sources))
			for i = 1, math.min(#sources, 6) do
				local entry = sources[i]
				local chance = type(entry.chance) == "number" and ("  " .. Kit.Hex(Kit.ChanceColor(entry.chance)) .. Kit.ChanceText(entry.chance) .. "|r") or ""
				P.FlowText(flow, P.SourceLine(entry) .. chance, 11)
			end
			if #sources > 6 then P.FlowText(flow, (L["and %d more"]):format(#sources - 6), 11, "secondary") end
		end
		local quests = LG:ItemQuests(itemID)
		if quests then
			P.FlowCaption(flow, L["Quests"])
			for _, questID in ipairs(quests.rewards) do
				P.FlowLine(flow, (L["Reward: %s"]):format(LG:QuestTitle(questID) or ("#" .. questID)), function()
					LG:OpenDatabase("quests", questID)
				end, nil, L["Quests"], L["Shows the quest in the Quests table."])
			end
			for _, questID in ipairs(quests.needed) do
				P.FlowLine(flow, (L["Needed for: %s"]):format(LG:QuestTitle(questID) or ("#" .. questID)), function()
					LG:OpenDatabase("quests", questID)
				end, nil, L["Quests"], L["Shows the quest in the Quests table."])
			end
		end
		local note = LG:ItemNote(itemID)
		if note then
			P.FlowCaption(flow, L["Note"])
			P.FlowText(flow, tostring(note), 11, "secondary")
		end
	end,
	main = function(row) return { L["Open"], function() P.OpenItem(row.id) end, L["Open"], L["Opens the item where it drops: the boss, the quest or the item page."] } end,
	icons = function(row)
		local itemID = row.id
		local out = {}
		if LG:WishlistOn() then
			out[#out + 1] = { "Interface\\Common\\FavoritesIcon", LG:IsWished(itemID) and L["Remove from wishlist"] or L["Add to wishlist"],
				L["Your wishlist alerts you when the item drops."], function() LG:ToggleWished(itemID) end }
		end
		if LG:ItemSlots(itemID) then
			out[#out + 1] = { "Interface\\Icons\\INV_Chest_Cloth_17", L["Try on"], L["Shows the item on your character in the dressing room."], function()
				local _, link = C_Item.GetItemInfo(itemID)
				if not Secret(link) and link and DressUpItemLink then DressUpItemLink(link) end
			end }
		end
		out[#out + 1] = { "Interface\\ChatFrame\\UI-ChatIcon-Chat-Up", L["Link in chat"], L["Puts the item link into the chat line you are typing in."], function()
			local _, link = C_Item.GetItemInfo(itemID)
			if not Secret(link) and link then InsertChatLink(link) end
		end }
		return out
	end,
	search = function(row, text) return row.fold:find(text, 1, true) ~= nil end,
}

---------------------------------------------------------------------------
-- Mobs
---------------------------------------------------------------------------
-- Drops of a creature: instance bosses and trash from the instance loot,
-- others from the creature loot table.
function LG:MobDrops(npc)
	local mob = self:Mob(npc)
	if mob and mob.instance then
		local loot = self:InstanceLoot(mob.instance)
		local out = {}
		for _, boss in ipairs(loot.bosses) do
			if boss.npc == npc then
				for _, drop in ipairs(boss.loot) do out[#out + 1] = drop end
			end
		end
		for _, drop in ipairs(loot.trash) do
			if drop.npc == npc then out[#out + 1] = drop end
		end
		if #out > 0 then return out end
	end
	return self.MobLoot and self:MobLoot(npc) or {}
end

local function MobUpgrades(npc)
	local key = "mob:" .. npc
	local value = forYou[key]
	if value == nil then
		value = 0
		for _, drop in ipairs(LG:MobDrops(npc)) do
			if not drop.questOnly and ItemGain(drop.itemID) then value = value + 1 end
		end
		forYou[key] = value
	end
	return value
end

local function MobRows()
	local LD = select(3, LG:DataStatus())
	local rows = {}
	for npc in pairs(LD and LD.mobs or {}) do
		local mob = LG:Mob(npc)
		if mob then
			local where = "world"
			local info = mob.instance and LG:InstanceInfo(mob.instance)
			if info then where = info.kind == "raid" and "raid" or "dungeon" end
			local drops = (LD.loot and LD.loot[npc]) and select(2, tostring(LD.loot[npc]):gsub(":", "")) or nil
			rows[#rows + 1] = { id = npc, name = mob.name or "", fold = Fold(mob.name), type = MobType(mob), level = mob.maxLevel or 0,
				minLevel = mob.minLevel, where = where, instance = mob.instance, mob = mob, dropCount = drops, family = mob.family }
		end
	end
	return rows
end

local function DropCount(row)
	if row.drops == nil then row.drops = #LG:MobDrops(row.id) end
	return row.drops
end

local function PlaceOfMob(row)
	if row.instance then return LG:InstanceName(row.instance) or row.instance end
	local camps = LG:SpawnPoints("npc", row.id)
	return camps[1] and LG:SpawnZone(camps[1]) or ""
end

-- Beasts a Hunter can tame: a paw before the name (a long name is cut at
-- its end, never the paw), and a filter for
-- Hunters ("Tameable", then one chip per pet family in the data).
local PAW = "Interface\\Icons\\Ability_Hunter_BeastTaming"
local function Paw(size) return ("|T%s:%d:%d:0:0:64:64:5:59:5:59|t"):format(PAW, size, size) end
local function IsHunter()
	local _, class = UnitClass("player")
	return class == "HUNTER"
end
local familyOptions
local function FamilyOptions()
	if not familyOptions then
		local LD = select(3, LG:DataStatus())
		local seen = {}
		for npc in pairs(LD and LD.mobs or {}) do
			local mob = LG:Mob(npc)
			if mob and mob.family then seen[mob.family] = true end
		end
		familyOptions = {}
		for family in pairs(seen) do
			local name = LG:FamilyName(family)
			if name then familyOptions[#familyOptions + 1] = { family, name } end
		end
		table.sort(familyOptions, function(a, b) return a[2] < b[2] end)
	end
	local out = { { "__off", L["All"] }, { "any", L["Tameable"] } }
	for _, option in ipairs(familyOptions) do out[#out + 1] = option end
	return out
end
LG:On("database-families", function(changed)
	if changed.data then familyOptions = nil end
end)

defs.mobs = {
	title = "Mobs",
	switch = { Key("With upgrades for me"), Key("Only creatures that drop at least one upgrade for you.") },
	sorts = { { "level", Key("Level") }, { "name", Key("Name") }, { "drops", Key("Drops"), true }, { "foryou", Key("For you"), true } },
	filters = {
		{ key = "type", kind = "chips", title = "Type", options = function()
			return { { "boss", L[TYPE_LABEL.boss] }, { "rare", L[TYPE_LABEL.rare] }, { "elite", L[TYPE_LABEL.elite] }, { "normal", L[TYPE_LABEL.normal] } }
		end },
		{ key = "level", kind = "range", title = "Level" },
		{ key = "where", kind = "chips", title = "Where", options = function()
			return { { "dungeon", L["Dungeon"] }, { "raid", L["Raid"] }, { "world", L["World"] } }
		end },
		{ key = "tame", kind = "radio", title = "Tameable", shown = IsHunter, options = FamilyOptions },
	},
	-- The name takes the width the narrow columns leave.
	columns = {
		{ key = "name", title = "Name", text = function(row) return row.family and (Paw(14) .. " " .. row.name) or row.name end },
		{ key = "type", title = "Type", width = 60, value = function(row) return E:Translate(TYPE_LABEL[row.type]) end },
		{ key = "level", title = "Level", width = 50, align = "RIGHT", value = function(row) return row.level end,
			text = function(row) return LevelRange(row.minLevel, row.level) end },
		{ key = "where", title = "Where", width = 100, value = function(row) return row.instance and (LG:InstanceName(row.instance) or row.instance) or L["World"] end },
		{ key = "drops", title = "Drops", width = 46, align = "RIGHT", value = function(row) return DropCount(row) end },
		{ key = "foryou", title = "For you", width = 54, align = "RIGHT", desc = "How many of its drops are upgrades for you.",
			value = function(row) return MobUpgrades(row.id) end,
			text = function(row) local n = MobUpgrades(row.id) return n > 0 and (Kit.Hex(unpack(Kit.GOOD)) .. n .. "|r") or "" end },
	},
	rows = MobRows,
	match = function(row, st)
		local f = st.filters
		if st.switch and MobUpgrades(row.id) == 0 then return false end
		if f.type and not f.type[row.type] then return false end
		if f.where and not f.where[row.where] then return false end
		if f.level and (row.level < f.level[1] or (row.minLevel or row.level) > f.level[2]) then return false end
		if f.place and row.instance ~= f.place then return false end
		if f.tame and not (row.family and (f.tame.any or f.tame[row.family])) then return false end
		return true
	end,
	sortValue = {
		level = function(row) return row.level end,
		name = function(row) return row.fold end,
		drops = function(row) return DropCount(row) end,
		foryou = function(row) return MobUpgrades(row.id) end,
	},
	detail = function(pane, row)
		local flow = pane.flow
		local face = flow:Take("face", function(child)
			local frame = CreateFrame("Frame", nil, child)
			frame.portrait = frame:CreateTexture(nil, "ARTWORK")
			frame.portrait:SetSize(48, 48)
			frame.portrait:SetPoint("LEFT")
			frame.name = Kit.Text(frame, 14, "LEFT")
			frame.name:SetPoint("TOPLEFT", frame.portrait, "TOPRIGHT", 8, -4)
			frame.name:SetPoint("TOPRIGHT", frame, "RIGHT", 0, 24 - 4) -- the 48 px portrait is centered
			frame.sub = Kit.Text(frame, 11, "LEFT", "secondary")
			frame.sub:SetPoint("TOPLEFT", frame.name, "BOTTOMLEFT", 0, -3)
			frame.sub:SetPoint("TOPRIGHT", frame.name, "BOTTOMRIGHT", 0, -3)
			return frame
		end)
		flow:Place(face, 50, 0, 6)
		local setPortrait = rawget(_G, "SetPortraitTextureFromCreatureDisplayID")
		local ok = row.mob.display and setPortrait and pcall(setPortrait, face.portrait, row.mob.display)
		if not ok then
			face.portrait:SetTexture("Interface\\Icons\\INV_Misc_Head_Dragon_01")
			E:TrimIcon(face.portrait)
		else
			face.portrait:SetTexCoord(0, 1, 0, 1)
		end
		face.name:SetText(row.name)
		face.sub:SetText(Kit.Hex(Kit.LevelColor(row.level)) .. (L["Level %s"]):format(LevelRange(row.minLevel, row.level)) .. "|r  " .. (E:Translate(TYPE_LABEL[row.type]) or ""))
		local place = PlaceOfMob(row)
		if place ~= "" then P.FlowText(flow, place, 12, "secondary") end
		if row.family then
			local family = LG:FamilyName(row.family)
			P.FlowText(flow, Paw(14) .. " " .. (family and L["Tameable: %s"]:format(family) or L["Tameable"]), 12, "secondary")
		end
		local drops = LG.SortMobDrops and LG.SortMobDrops(LG:MobDrops(row.id)) or LG:MobDrops(row.id)
		P.FlowCaption(flow, L["Drops"], tostring(#drops))
		if #drops == 0 then P.FlowText(flow, L["No known drops."], 11, "secondary") end
		for i = 1, math.min(#drops, 10) do
			local data = P.ChanceData(drops[i].chance, row.id, drops[i].itemID)
			data.itemID = drops[i].itemID
			data.onClick = function() P.OpenItem(drops[i].itemID) end
			P.FlowItem(flow, data)
		end
		if #drops > 10 then P.FlowText(flow, (L["and %d more"]):format(#drops - 10), 11, "secondary") end
	end,
	main = function(row)
		if row.instance and LG:InstanceInfo(row.instance) then
			return { L["Open the place"], function() LG:Open("journal", { key = row.instance, npc = row.id }) end, L["Open the place"],
				L["Opens the dungeon in the Journal on this creature."] }
		end
		local camps = LG:SpawnPoints("npc", row.id)
		local uiMapID = camps[1] and LG:MapPosition(camps[1])
		return { L["Open the place"], function() LG:Open("world", uiMapID) end, L["Open the place"],
			L["Opens the zone on the World page."], not uiMapID }
	end,
	icons = function(row)
		if row.instance and LG:EntrancePoint(row.instance) then
			return { { "Interface\\Icons\\INV_Misc_Map_01", L["Entrance"], L["Pins the dungeon's entrance on your map."], function() LG:ShowEntrance(row.instance) end } }
		end
		local button = P.MapButton("npc", row.id, row.name)
		if button[5] then return {} end
		return { { "Interface\\Icons\\INV_Misc_Map_01", L["Map"], button[4], button[2] } }
	end,
	search = function(row, text) return row.fold:find(text, 1, true) ~= nil end,
}

---------------------------------------------------------------------------
-- Quests
---------------------------------------------------------------------------
local rewardCache = {}
LG:On("database-rewards", function(changed)
	if changed.data or changed.gear or changed.list or changed.spec or changed.rank or changed.player then wipe(rewardCache) end
end)

-- "upgrade", "usable" or "none" for the best reward.
local function RewardKind(questID)
	local kind = rewardCache[questID]
	if kind then return kind end
	kind = "none"
	local quest = LG:Quest(questID)
	for _, list in ipairs({ quest and quest.rewards or {}, quest and quest.choice or {} }) do
		for _, reward in ipairs(list) do
			if ItemGain(reward.id) then
				kind = "upgrade"
			elseif kind == "none" and Usable(LG:ItemRecord(reward.id)) and LG:SlotGroup(reward.id) then
				kind = "usable"
			end
		end
	end
	rewardCache[questID] = kind
	return kind
end

local function QuestRows()
	local LD = select(3, LG:DataStatus())
	local rows = {}
	for questID in pairs(LD and LD.quests or {}) do
		local quest = LG:Quest(questID)
		if quest then
			rows[#rows + 1] = { id = questID, name = quest.title or "", fold = Fold(quest.title), level = quest.level or 0,
				minLevel = quest.minLevel, instance = quest.instance, where = quest.instance and "dungeon" or "world" }
		end
	end
	return rows
end

local function Status(row)
	return (LG:QuestStatus(row.id))
end

defs.quests = {
	title = "Quests",
	sorts = { { "status", Key("Status") }, { "level", Key("Level") }, { "name", Key("Name") } },
	filters = {
		{ key = "status", kind = "checks", title = "Status", options = function()
			local out = {}
			for _, key in ipairs({ "turnin", "active", "available", "locked", "low", "done", "notforyou" }) do
				out[#out + 1] = { key, L[STATUS_LABEL[key]], { P.QuestStatusColor(key) } }
			end
			return out
		end },
		{ key = "level", kind = "range", title = "Level" },
		{ key = "where", kind = "chips", title = "Where", options = function()
			return { { "dungeon", L["Dungeons and raids"] }, { "world", L["World"] } }
		end },
		{ key = "reward", kind = "radio", title = "Reward", options = function()
			return { { "any", L["Any"] }, { "usable", L["Usable"] }, { "upgrade", L["Upgrade"] } }
		end },
	},
	columns = {
		{ key = "status", title = "", width = 22, value = function(row) return STATUS_ORDER[Status(row)] end,
			text = function(row)
				local status = Status(row)
				local r, g, b = P.QuestStatusColor(status)
				return Kit.Hex(r, g, b) .. (P.QUEST_GLYPH[status] or "") .. "|r"
			end, desc = "Status: ? ready, ! open, x locked, - too low or not for you, v done." },
		{ key = "name", title = "Quest", text = function(row) return row.name end },
		{ key = "level", title = "Level", width = 50, align = "RIGHT", value = function(row) return row.level end },
		{ key = "where", title = "Where", width = 130, value = function(row) return row.instance and (LG:InstanceName(row.instance) or row.instance) or "" end },
		{ key = "reward", title = "Reward", width = 70, value = function(row) return RewardKind(row.id) end,
			text = function(row)
				local kind = RewardKind(row.id)
				if kind == "upgrade" then return Kit.Hex(unpack(Kit.GOOD)) .. L["upgrade"] .. "|r" end
				if kind == "usable" then return L["usable"] end
				return ""
			end },
	},
	rows = QuestRows,
	match = function(row, st)
		local f = st.filters
		if f.status and not f.status[Status(row)] then return false end
		if f.level and (row.level < f.level[1] or row.level > f.level[2]) then return false end
		if f.where and not f.where[row.where] then return false end
		local reward = f.reward and next(f.reward)
		if reward == "usable" and RewardKind(row.id) == "none" then return false end
		if reward == "upgrade" and RewardKind(row.id) ~= "upgrade" then return false end
		if f.place and row.instance ~= f.place then return false end
		return true
	end,
	sortValue = {
		status = function(row) return STATUS_ORDER[Status(row)] or 9 end,
		level = function(row) return row.level end,
		name = function(row) return row.fold end,
	},
	detail = function(pane, row)
		pane.quest:Show()
		pane.flow:Hide()
		pane.quest:SetQuest(row.id, function(id) LG:OpenDatabase("quests", id) end)
	end,
	main = function(row)
		if row.instance and LG:InstanceInfo(row.instance) then
			return { L["Open in Journal"], function() LG:Open("journal", { key = row.instance, quest = row.id }) end, L["Open in Journal"],
				L["Opens the dungeon's quest list on this quest."] }
		end
	end,
	icons = function() return {} end,
	search = function(row, text) return row.fold:find(text, 1, true) ~= nil end,
}

---------------------------------------------------------------------------
-- Places: instances and the World page's zones
---------------------------------------------------------------------------
local function PlaceRows()
	local rows = {}
	for _, info in ipairs(LG:Catalog()) do
		if info.status ~= "announced" then
			rows[#rows + 1] = { id = info.key, name = info.name or info.key, fold = Fold(info.name), type = info.kind == "raid" and "raid" or "dungeon",
				min = info.min, max = info.max, info = info }
		end
	end
	if LG.WorldZones then
		for _, zone in ipairs(LG:WorldZones().list) do
			rows[#rows + 1] = { id = "zone:" .. zone.id, name = zone.name, fold = Fold(zone.name), type = "zone", min = zone.min, max = zone.max,
				zone = zone }
		end
	end
	return rows
end

local function PlaceUpgrades(row)
	local key = "place:" .. row.id
	local value = forYou[key]
	if value == nil then
		if row.zone then
			value = 0
			for _, list in ipairs({ row.zone.rares, row.zone.mobs }) do
				for _, npc in ipairs(list) do value = value + MobUpgrades(npc) end
			end
		else
			value = P.InstanceStats(row.id).upgrades
		end
		forYou[key] = value
	end
	return value
end

local function BestUpgrades(row)
	local seen, out = {}, {}
	local function Add(itemID)
		if seen[itemID] then return end
		seen[itemID] = true
		local gain = ItemGain(itemID)
		if gain then out[#out + 1] = { itemID = itemID, gain = gain } end
	end
	if row.zone then
		for _, list in ipairs({ row.zone.rares, row.zone.mobs }) do
			for _, npc in ipairs(list) do
				for _, drop in ipairs(LG:MobDrops(npc)) do if not drop.questOnly then Add(drop.itemID) end end
			end
		end
	else
		local loot = LG:InstanceLoot(row.id)
		for _, boss in ipairs(loot.bosses) do for _, drop in ipairs(boss.loot) do Add(drop.itemID) end end
		for _, drop in ipairs(loot.trash) do Add(drop.itemID) end
	end
	table.sort(out, function(a, b) return a.gain > b.gain end)
	return out
end

defs.places = {
	title = "Places",
	switch = { Key("Near my level"), Key("Only places whose level range fits you or is close.") },
	sorts = { { "level", Key("Level") }, { "name", Key("Name") }, { "foryou", Key("For you"), true } },
	filters = {
		{ key = "type", kind = "chips", title = "Type", options = function()
			return { { "dungeon", L[PLACE_LABEL.dungeon] }, { "raid", L[PLACE_LABEL.raid] }, { "zone", L[PLACE_LABEL.zone] } }
		end },
		{ key = "level", kind = "range", title = "Level" },
	},
	columns = {
		{ key = "name", title = "Place", text = function(row) return row.name end },
		{ key = "type", title = "Type", width = 70, value = function(row) return E:Translate(PLACE_LABEL[row.type]) end },
		{ key = "level", title = "Level", width = 64, align = "RIGHT", value = function(row) return row.min or 0 end,
			text = function(row) return row.min and P.LevelText({ min = row.min, max = row.max or row.min }) or "" end },
		{ key = "foryou", title = "For you", width = 60, align = "RIGHT", desc = "Upgrades for you that drop there.",
			value = function(row) return PlaceUpgrades(row) end,
			text = function(row) local n = PlaceUpgrades(row) return n > 0 and (Kit.Hex(unpack(Kit.GOOD)) .. n .. "|r") or "" end },
	},
	rows = PlaceRows,
	match = function(row, st)
		local f = st.filters
		if st.switch then
			local fit = row.min and LG:FitsLevel({ min = row.min, max = row.max or row.min })
			if fit ~= "fit" and fit ~= "near" then return false end
		end
		if f.type and not f.type[row.type] then return false end
		if f.level and (row.min or 0) > f.level[2] then return false end
		if f.level and (row.max or row.min or 0) < f.level[1] then return false end
		return true
	end,
	sortValue = {
		level = function(row) return row.min or 0 end,
		name = function(row) return row.fold end,
		foryou = function(row) return PlaceUpgrades(row) end,
	},
	detail = function(pane, row)
		local flow = pane.flow
		local head = flow:Take("placehead", function(child)
			local frame = CreateFrame("Frame", nil, child)
			frame.art = P.Art(frame, 48)
			frame.art:SetPoint("LEFT")
			frame.name = Kit.Text(frame, 14, "LEFT")
			frame.name:SetPoint("TOPLEFT", frame.art, "TOPRIGHT", 8, -4)
			frame.name:SetPoint("TOPRIGHT", frame, "RIGHT", 0, 24 - 4) -- the 48 px art is centered
			frame.sub = Kit.Text(frame, 11, "LEFT", "secondary")
			frame.sub:SetPoint("TOPLEFT", frame.name, "BOTTOMLEFT", 0, -3)
			frame.sub:SetPoint("TOPRIGHT", frame.name, "BOTTOMRIGHT", 0, -3)
			return frame
		end)
		flow:Place(head, 50, 0, 6)
		head.art.icon:SetTexture(row.zone and "Interface\\Icons\\INV_Misc_Map02" or LG:InstanceArt(row.id))
		head.name:SetText(row.name)
		local level = row.min and P.LevelText({ min = row.min, max = row.max or row.min }) or ""
		head.sub:SetText((E:Translate(PLACE_LABEL[row.type]) or "") .. (level ~= "" and ("  ·  " .. (L["Level %s"]):format(level)) or ""))
		if row.zone then
			P.FlowText(flow, E:Plural(#row.zone.rares, "%d rare", "%d rares"):format(#row.zone.rares) .. ", "
				.. E:Plural(#row.zone.mobs, "%d other creature", "%d other creatures"):format(#row.zone.mobs), 11, "secondary")
			P.FlowCaption(flow, L["Rares"], tostring(#row.zone.rares))
			for i = 1, math.min(#row.zone.rares, 8) do
				local mob = LG:Mob(row.zone.rares[i])
				P.FlowText(flow, (mob and mob.name or "?") .. "  " .. E:TextHex("secondary") .. LevelRange(mob and mob.minLevel, mob and mob.maxLevel) .. "|r", 11)
			end
		else
			local zone = LG:InstanceZone(row.id)
			local facts = { P.SizeText(row.info) }
			if zone then facts[#facts + 1] = zone end
			P.FlowText(flow, table.concat(facts, "  ·  "), 11, "secondary")
			local loot = LG:InstanceLoot(row.id)
			P.FlowCaption(flow, L["Bosses"], tostring(#loot.bosses))
			for i, boss in ipairs(loot.bosses) do
				if i > 12 then break end
				P.FlowText(flow, ("%d. %s"):format(i, boss.name), 11)
			end
		end
		local best = BestUpgrades(row)
		P.FlowCaption(flow, L["Best upgrades"], tostring(#best))
		if #best == 0 then P.FlowText(flow, L["Nothing here is an upgrade for you now."], 11, "secondary") end
		for i = 1, math.min(#best, 5) do
			P.FlowItem(flow, { itemID = best[i].itemID, onClick = function() P.OpenItem(best[i].itemID) end })
		end
	end,
	main = function(row)
		if row.zone then
			return { L["Open in World"], function() LG:Open("world", row.zone.id) end, L["Open in World"], L["Opens the zone's rares and creatures."] }
		end
		return { L["Open in Journal"], function() LG:Open("journal", row.id) end, L["Open in Journal"], L["Opens the place in the Journal."] }
	end,
	icons = function(row)
		local out = {}
		if row.zone then
			out[#out + 1] = { "Interface\\Icons\\INV_Misc_Map_01", L["Zone map"], L["Opens the world map on this zone (out of combat)."], function() LG:OpenWorldMapAt(row.zone.id) end }
			out[#out + 1] = { "Interface\\Icons\\Ability_Hunter_SniperShot", L["Creatures"], L["Shows the zone's creatures in the Mobs table."], function()
				local st = State("mobs")
				st.search = ""
				st.filters = { where = { world = true } }
				LG:OpenDatabase("mobs")
			end }
			return out
		end
		if LG:EntrancePoint(row.id) then
			out[#out + 1] = { "Interface\\Icons\\INV_Misc_Map_01", L["Entrance"], L["Pins the entrance on your map."], function() LG:ShowEntrance(row.id) end }
		end
		if LG.OpenDungeonMap and E.DungeonMaps and E.DungeonMaps:KeyFor(row.id) then
			out[#out + 1] = { "Interface\\Icons\\INV_Misc_Map02", L["Dungeon map"], L["Opens the dungeon map with its bosses."], function() LG:OpenDungeonMap(row.id) end }
		end
		out[#out + 1] = { "Interface\\GossipFrame\\AvailableQuestIcon", L["Quests"], L["Shows the quests for this place in the Quests table."], function()
			local st = State("quests")
			st.search = ""
			st.filters = { place = row.id }
			LG:OpenDatabase("quests")
		end }
		if #out < 3 then
			out[#out + 1] = { "Interface\\Icons\\Ability_Hunter_SniperShot", L["Creatures"], L["Shows the place's creatures in the Mobs table."], function()
				local st = State("mobs")
				st.search = ""
				st.filters = { place = row.id }
				LG:OpenDatabase("mobs")
			end }
		end
		return out
	end,
	search = function(row, text) return row.fold:find(text, 1, true) ~= nil end,
}

---------------------------------------------------------------------------
-- Filter widgets (left)
---------------------------------------------------------------------------
local function ChipHolder(child)
	local holder = CreateFrame("Frame", nil, child)
	holder.chips = {}
	return holder
end

-- Chips a holder no longer shows wait here, off every holder, so a holder
-- only owns the chips it draws: pooled holders move between filters
-- and tables, and a holder with 20 chips must not show 7.
local spareChips, spareParent = {}, nil

local function TakeChip(holder)
	local chip = table.remove(spareChips)
	if chip then
		chip:SetParent(holder)
		return chip
	end
	return P.Toggle(holder, "", nil, nil, nil)
end

local function ReleaseChip(chip)
	if not spareParent then
		spareParent = CreateFrame("Frame")
		spareParent:Hide()
	end
	chip:Hide()
	chip:ClearAllPoints()
	chip:SetScript("OnClick", nil)
	chip:SetParent(spareParent)
	spareChips[#spareChips + 1] = chip
end

-- Chips with "All" first; a set of values or nil (= all).
local function DrawChips(page, flow, filter, st, single)
	local holder = flow:Take("chips", ChipHolder)
	local options = filter.options()
	local chosen = st.filters[filter.key]
	local list = {}
	if not single then list[1] = { "__all", L["All"] } end
	for _, option in ipairs(options) do list[#list + 1] = option end
	local x, y, width = 0, 0, flow:Width()
	for index, option in ipairs(list) do
		local chip = holder.chips[index]
		if not chip then
			chip = TakeChip(holder)
			holder.chips[index] = chip
		end
		chip:SetLabel(option[2])
		local value = option[1]
		if single then
			chip:SetOn((chosen and chosen[value]) or (not chosen and index == 1))
		else
			chip:SetOn(value == "__all" and not chosen or (chosen and chosen[value]) or false)
		end
		chip:SetScript("OnClick", function()
			local f = st.filters
			if single then
				f[filter.key] = index > 1 and { [value] = true } or nil
			elseif value == "__all" then
				f[filter.key] = nil
			else
				local set = f[filter.key] or {}
				set[value] = not set[value] or nil
				f[filter.key] = next(set) and set or nil
			end
			page:Draw()
		end)
		Kit.Tooltip(chip, option[2], (not single and value == "__all") and L["Shows every kind."] or nil,
			(single or value ~= "__all") and { { L["Click"], single and L["choose"] or L["add or remove this from the filter"] } } or nil)
		local w = chip:GetWidth()
		if x > 0 and x + w > width then
			x, y = 0, y + 22
		end
		chip:ClearAllPoints()
		chip:SetPoint("TOPLEFT", x, -y)
		chip:Show()
		x = x + w + 4
	end
	while #holder.chips > #list do ReleaseChip(table.remove(holder.chips)) end
	flow:Place(holder, y + 20, 0, 4)
end

local function CheckRow(child)
	local row = CreateFrame("Button", nil, child)
	row.box = CreateFrame("Frame", nil, row)
	row.box:SetSize(12, 12)
	row.box:SetPoint("LEFT", 2, 0)
	E:SetTemplate(row.box, true)
	row.fill = row.box:CreateTexture(nil, "OVERLAY")
	row.fill:SetPoint("TOPLEFT", 2, -2)
	row.fill:SetPoint("BOTTOMRIGHT", -2, 2)
	row.dot = row:CreateTexture(nil, "ARTWORK")
	row.dot:SetSize(8, 8)
	row.dot:SetPoint("LEFT", row.box, "RIGHT", 6, 0)
	row.label = Kit.Text(row, 11, "LEFT")
	row.label:SetPoint("LEFT", row.dot, "RIGHT", 6, 0)
	row.label:SetPoint("RIGHT")
	return row
end

-- Checks with colored dots; nothing ticked = all.
local function DrawChecks(page, flow, filter, st)
	local chosen = st.filters[filter.key]
	for _, option in ipairs(filter.options()) do
		local row = flow:Take("check", CheckRow)
		flow:Place(row, 18, 0, 1)
		local value = option[1]
		local on = chosen == nil or chosen[value] == true
		row.fill:SetColorTexture(Kit.Accent())
		row.fill:SetShown(on)
		row.dot:SetColorTexture(unpack(option[3]))
		row.label:SetText(E:Translate(option[2]))
		row:SetScript("OnClick", function()
			local f = st.filters
			local set = f[filter.key]
			if not set then
				set = {}
				for _, other in ipairs(filter.options()) do set[other[1]] = true end
			end
			set[value] = not set[value] or nil
			local all = true
			for _, other in ipairs(filter.options()) do if not set[other[1]] then all = false end end
			f[filter.key] = (not all) and set or nil
			page:Draw()
		end)
		Kit.Tooltip(row, option[2], L["With all checked, nothing is filtered."], { { L["Click"], L["show or hide this"] } })
	end
end

local function RangeBlock(child)
	local block = CreateFrame("Frame", nil, child)
	block.text = Kit.Text(block, 11, "LEFT", "secondary")
	block.text:SetPoint("TOPLEFT")
	local function Slider(y)
		local slider = CreateFrame("Slider", nil, block)
		slider:SetOrientation("HORIZONTAL")
		slider:SetHeight(12)
		slider:SetPoint("TOPLEFT", 0, y)
		slider:SetPoint("TOPRIGHT", -6, y)
		slider:SetMinMaxValues(1, MAX_LEVEL)
		slider:SetValueStep(1)
		slider:SetObeyStepOnDrag(true)
		E:SetTemplate(slider, true)
		local thumb = slider:CreateTexture(nil, "OVERLAY")
		thumb:SetSize(8, 12)
		thumb:SetColorTexture(Kit.Accent())
		slider:SetThumbTexture(thumb)
		slider:EnableMouseWheel(true)
		-- Applies when the knob is let go (E.UIKit.SliderCommit); while it
		-- is dragged only the "from to" text moves.
		local Feed = E.UIKit.SliderCommit(slider, {
			preview = function() block:ShowRange() end,
			commit = function() if block.apply then block.apply() end end,
		})
		slider:SetScript("OnValueChanged", function()
			if block.setting then block:ShowRange() else Feed() end
		end)
		slider:SetScript("OnMouseWheel", function(self, delta)
			self:SetValue(math.max(1, math.min(MAX_LEVEL, math.floor((self:GetValue() or 1) + 0.5) + delta)))
		end)
		return slider
	end
	function block:ShowRange()
		self.text:SetText((L["%d to %d"]):format(math.floor((self.low:GetValue() or 1) + 0.5), math.floor((self.high:GetValue() or 1) + 0.5)))
	end
	block.low = Slider(-16)
	block.high = Slider(-32)
	return block
end

-- Two knobs: from and to.
local function DrawRange(page, flow, filter, st)
	local block = flow:Take("range", RangeBlock)
	flow:Place(block, 46, 0, 4)
	local range = st.filters[filter.key] or { 1, MAX_LEVEL }
	block.setting = true
	block.low:SetValue(range[1])
	block.high:SetValue(range[2])
	block.setting = false
	block:ShowRange()
	block.apply = function()
		local low, high = math.floor(block.low:GetValue() + 0.5), math.floor(block.high:GetValue() + 0.5)
		if low > high then low, high = high, low end
		st.filters[filter.key] = (low > 1 or high < MAX_LEVEL) and { low, high } or nil
		page:Draw()
	end
	Kit.Tooltip(block.low, L["From level"], L["Drag the lower knob and let go, or use the mouse wheel."])
	Kit.Tooltip(block.high, L["To level"], L["Drag the upper knob and let go, or use the mouse wheel."])
end

local function DrawFilters(page)
	local def = defs[current]
	local st = State()
	local flow = page.filters
	flow:Begin()
	if st.filters.place then
		local name = LG:InstanceName(st.filters.place) or st.filters.place
		P.FlowLine(flow, (L["Only %s"]):format(name), nil, { L["Clear"], function()
			st.filters.place = nil
			page:Draw()
		end, L["Clear"], L["Shows every place again."] })
	end
	for _, filter in ipairs(def.filters) do
		if filter.shown and not filter.shown() then
			-- A filter this character has no use for (the pet families for
			-- a non-Hunter) is not drawn and filters nothing.
			st.filters[filter.key] = nil
		else
			P.FlowCaption(flow, filter.title)
			if filter.kind == "chips" then
				DrawChips(page, flow, filter, st)
			elseif filter.kind == "radio" then
				DrawChips(page, flow, filter, st, true)
			elseif filter.kind == "checks" then
				DrawChecks(page, flow, filter, st)
			elseif filter.kind == "range" then
				DrawRange(page, flow, filter, st)
			end
		end
	end
	flow:Finish(true)
end

---------------------------------------------------------------------------
-- Detail (right)
---------------------------------------------------------------------------
local function DrawDetail(page, row)
	local detail = page.detail
	local def = defs[current]
	detail.quest:Hide()
	detail.flow:Show()
	if not row then
		detail.flow:Begin()
		P.FlowText(detail.flow, L["Pick a row to see it here."], 12, "secondary")
		detail.flow:Finish()
		detail.main:Hide()
		for _, icon in ipairs(detail.icons) do icon:Hide() end
		return
	end
	detail.flow:Begin()
	local ok, err = pcall(def.detail, detail, row)
	if not ok then geterrorhandler()(err) end
	if detail.flow:IsShown() then detail.flow:Finish() end
	local main = def.main and def.main(row)
	if main then
		detail.main:SetText(main[1])
		detail.main:SetScript("OnClick", main[2])
		Kit.Tooltip(detail.main, main[3], main[4])
		detail.main:SetEnabled(not main[5])
		detail.main:Show()
	else
		detail.main:Hide()
	end
	local icons = def.icons and def.icons(row) or {}
	for index, button in ipairs(detail.icons) do
		local icon = icons[index]
		if icon then
			button.icon:SetTexture(icon[1])
			E:TrimIcon(button.icon)
			button:SetScript("OnClick", function()
				local tab = current
				icon[4]()
				if current == tab and page:IsVisible() then DrawDetail(page, row) end
			end)
			Kit.Tooltip(button, icon[2], icon[3])
			button:Show()
		else
			button:Hide()
		end
	end
end

---------------------------------------------------------------------------
-- The table and the bar
---------------------------------------------------------------------------
-- Item names the client learned since the rows were built (a non-English
-- client caching an item): renamed in place, so search, sort and the
-- table show the client's name without a /reload.
local function ApplyItemNames()
	local rows = base.items
	if not rows then return false end
	local renamed = LG:TakeRenamedItems()
	if not renamed then return false end
	for _, row in ipairs(rows) do
		local name = renamed[row.id]
		if name then
			row.name, row.fold = name, Fold(name)
			row.record = LG:ItemRecord(row.id) or row.record
		end
	end
	return true
end

local function Filtered()
	local def = defs[current]
	if not base[current] then base[current] = def.rows() end
	if current == "items" then ApplyItemNames() end
	local st = State()
	local text = Fold(strtrim(st.search or ""))
	local out = {}
	for _, row in ipairs(base[current]) do
		if (text == "" or def.search(row, text)) and def.match(row, st) then out[#out + 1] = row end
	end
	return out
end

local function SortMenu(owner, page)
	local def = defs[current]
	E.UIKit.ContextMenu(owner, function(_, root)
		root:CreateTitle(L["Sort by"])
		for _, sort in ipairs(def.sorts) do
			root:CreateRadio(L[sort[2]], function() return State().sort == sort[1] end, function()
				local st = State()
				st.sort, st.down = sort[1], sort[3] or false
				page:Draw()
			end)
		end
	end, { at = "owner" })
end

local function BuildTable(page, tab)
	local def = defs[tab]
	local tbl = Kit.CreateTable(page, def.columns, {
		onClick = function(row)
			State().selected = row.id
			page.table.list:Refresh()
			DrawDetail(page, row)
		end,
		updateRow = function(rowFrame, row)
			if not rowFrame.select then
				rowFrame.select = rowFrame:CreateTexture(nil, "BACKGROUND", nil, 1)
				rowFrame.select:SetAllPoints()
			end
			local r, g, b = Kit.Accent()
			rowFrame.select:SetColorTexture(r, g, b, 0.15)
			rowFrame.select:SetShown(State().selected == row.id)
		end,
		onSort = function(key, down)
			local st = State()
			st.sort, st.down = key, down
			page:Draw(true)
		end,
	})
	tbl:SetPoint("TOPLEFT", page.filters, "TOPRIGHT", 10, 0)
	tbl:SetPoint("BOTTOMRIGHT", page.detail, "BOTTOMLEFT", -10, 0)
	tbl:Hide()
	return tbl
end

local function Create(parent)
	local page = CreateFrame("Frame", nil, parent)
	page:SetAllPoints()
	page.tabs = {}
	local anchor
	for _, tab in ipairs(TAB_ORDER) do
		local chip = P.Toggle(page, defs[tab].title, function()
			current = tab
			page:Draw()
		end, defs[tab].title, L["Switches the table. Each table keeps its search and filters for this session."])
		chip:SetHeight(22)
		if anchor then chip:SetPoint("LEFT", anchor, "RIGHT", 4, 0) else chip:SetPoint("TOPLEFT", 0, 0) end
		anchor = chip
		page.tabs[tab] = chip
	end
	page.search = CreateFrame("EditBox", nil, page, "SearchBoxTemplate")
	E:SearchHint(page.search)
	page.search:SetSize(200, 20)
	page.search:SetPoint("LEFT", anchor, "RIGHT", 12, 0)
	page.search:SetAutoFocus(false)
	E:SkinEditBox(page.search)
	page.search:HookScript("OnTextChanged", function(self, typed)
		if not typed then return end
		State().search = self:GetText() or ""
		page:Draw()
	end)
	page.scope = Kit.Chip(page, "")
	page.scope:SetPoint("LEFT", page.search, "RIGHT", 6, 0)
	page.count = Kit.Text(page, 11, "LEFT", "secondary")
	page.count:SetPoint("LEFT", page.scope, "RIGHT", 8, 0)
	page.reset = Kit.Button(page, L["Reset"], 60, 20, function()
		LG:ResetDatabase(current)
		page.search:SetText("")
		page:Draw()
	end, L["Reset"], L["Clears this table's search, switch, filters and sort."])
	page.reset:SetPoint("TOPRIGHT", 0, 0)
	page.sort = P.Toggle(page, "", function(self) SortMenu(self, page) end, L["Sort by"], L["How the rows are ordered. A click on a column header sorts too."])
	page.sort:SetHeight(20)
	page.sort:SetPoint("RIGHT", page.reset, "LEFT", -6, 0)
	page.switch = P.Toggle(page, "", function()
		local st = State()
		st.switch = not st.switch
		page:Draw()
	end)
	page.switch:SetHeight(20)
	page.switch:SetPoint("RIGHT", page.sort, "LEFT", -6, 0)

	page.filters = P.Flow(page)
	page.filters:SetPoint("TOPLEFT", 0, -TOP)
	page.filters:SetPoint("BOTTOMLEFT")
	page.filters:SetWidth(FILTER_WIDTH)

	local detail = CreateFrame("Frame", nil, page)
	detail:SetPoint("TOPRIGHT", 0, -TOP)
	detail:SetPoint("BOTTOMRIGHT")
	detail:SetWidth(DETAIL_WIDTH)
	E:SetTemplate(detail, true)
	detail.main = Kit.Button(detail, " ", 120, 22)
	detail.main:SetPoint("BOTTOMLEFT", 8, 8)
	detail.icons = {}
	for index = 1, 3 do
		local button = Kit.IconSlot(detail, 22)
		button:SetPoint("BOTTOMRIGHT", -8 - (index - 1) * 26, 8)
		detail.icons[index] = button
	end
	detail.flow = P.Flow(detail)
	detail.flow:SetPoint("TOPLEFT", 8, -8)
	detail.flow:SetPoint("BOTTOMRIGHT", -4, 38)
	detail.quest = P.QuestDetail(detail)
	detail.quest:SetPoint("TOPLEFT", 8, -8)
	detail.quest:SetPoint("BOTTOMRIGHT", -4, 38)
	detail.quest:Hide()
	page.detail = detail

	page.tables = {}
	function page:Draw(keepScroll)
		local def = defs[current]
		local st = State()
		for tab, chip in pairs(self.tabs) do chip:SetOn(tab == current) end
		if (self.search:GetText() or "") ~= (st.search or "") then self.search:SetText(st.search or "") end
		self.scope:SetLabel(def.title)
		Kit.Tooltip(self.scope, L["Search in"], (L["The search looks through the %s table."]):format(L[def.title]))
		if def.switch then
			self.switch:SetLabel(def.switch[1])
			self.switch:SetOn(st.switch)
			Kit.Tooltip(self.switch, def.switch[1], def.switch[2])
			self.switch:Show()
		else
			self.switch:Hide()
		end
		local sortLabel = ""
		for _, sort in ipairs(def.sorts) do if sort[1] == st.sort then sortLabel = L[sort[2]] end end
		self.sort:SetLabel((L["Sort: %s"]):format(sortLabel), true)
		for tab, tbl in pairs(self.tables) do if tab ~= current then tbl:Hide() end end
		local tbl = self.tables[current]
		if not tbl then
			tbl = BuildTable(self, current)
			self.tables[current] = tbl
		end
		self.table = tbl
		tbl:Show()
		local rows = Filtered()
		self.rows = rows
		self.count:SetText(rows and (L["%s rows"]):format(BreakUpLargeNumbers and BreakUpLargeNumbers(#rows) or tostring(#rows)) or "")
		-- Sort: the chosen key through the column, else the table's own value.
		local valueOf = def.sortValue[st.sort]
		if valueOf then
			local column
			for _, c in ipairs(def.columns) do if c.key == st.sort then column = c end end
			if column then
				tbl.sortKey, tbl.sortDown = st.sort, st.down
			else
				table.sort(rows, function(a, b)
					local va, vb = valueOf(a), valueOf(b)
					if va == vb then return tostring(a.id) < tostring(b.id) end
					if st.down then return va > vb end
					return va < vb
				end)
				tbl.sortKey = nil
			end
		end
		local offset = tbl.list.offset
		tbl:SetData(rows)
		if keepScroll then
			tbl.list.offset = offset
			tbl.list:Refresh()
		end
		DrawFilters(self)
		local selected
		if st.selected ~= nil then
			for index, row in ipairs(tbl.list.data) do
				if row.id == st.selected then
					selected = row
					if not keepScroll then tbl.list:ScrollTo(index) end
					break
				end
			end
		end
		DrawDetail(self, selected)
	end
	return page
end

-- LG:OpenDatabase("items", 19019): a table, optionally on one row.
function LG:OpenDatabase(tab, id)
	if defs[tab] then
		current = tab
		if id ~= nil then
			local st = State(tab)
			st.selected = id
			st.search = ""
		end
	end
	if self:CurrentPage() == "database" then
		local page = self:GetPage("database")
		if page and page.frame then page.frame:Draw() end
	else
		self:Open("database")
	end
end

local function Show(page, arg)
	if type(arg) == "table" and defs[arg.tab or ""] then
		current = arg.tab
		if arg.id ~= nil then
			State().selected = arg.id
			State().search = ""
		end
	elseif type(arg) == "string" and defs[arg] then
		current = arg
	end
	page:Draw()
	Kit.Tour("database", {
		{ target = page.tabs.items, text = L["Four tables: items, creatures, quests and places. Each keeps its own search and filters until you log out."] },
		{ target = page.reset, text = L["Reset clears this table's search, filters and sort."] },
	})
end

local function Refresh(page, changed)
	if changed.data or changed.gear or changed.list or changed.spec or changed.rank or changed.player or changed.quests
		or changed.wishlist or changed.database or changed.settings or changed.bags then
		page:Draw(true)
	elseif changed.itemnames and current == "items" and ApplyItemNames() then
		page:Draw(true)
	elseif changed.items and page.table then
		page.table:Refresh()
	end
end

local function Empty()
	if not LG:HasData() then
		return L["The database needs the loot data"],
			L["Items, creatures, quests and places come from EldoUI_LootData. Install it next to EldoUI and reload."], LG.ICON, {
				{ L["Show data status"], function() LG:PrintDataStatus() end, L["Prints where the loot data comes from (same as /lg data)."] },
			}
	end
end

LG:RegisterPage("database", {
	title = "Database",
	desc = "Every item, creature, quest and place in sortable tables with filters and a detail panel.",
	order = 60,
	command = "database",
	usage = Key("open the Database; items | mobs | quests | places"),
	create = Create,
	show = Show,
	refresh = Refresh,
	empty = Empty,
	alias = function(text)
		text = (text or ""):lower()
		if text == "mob" or text == "creatures" then return "mobs" end
		if defs[text] then return text end
	end,
})
