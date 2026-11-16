-- EldoUI Loot Guide: item tooltip lines.
--
-- Three sections in EldoUI's one info area under the tooltip divider (no
-- own hook on GameTooltip; Modules/Tooltip.lua draws them). Each has its own
-- Always / Shift / Ctrl / Alt / Never setting on the Tooltip settings page:
--   lootPlan   (order 12, always)  "Best in Slot", plan sets, "On your
--              wishlist", a short item note, "Alt-click: item check"
--   lootSource (order 48, always)  where it drops: "Ras Frostwhisper ·
--              Scholomance   12%" (+2 more); rare and world mobs with rank and
--              level; random world drops with their level band; "Vendor:
--              <npc> · <zone>   <cost>". With Shift: up to three sources and
--              three vendors, each drop with what you saw drop yourself.
--   lootQuests (order 49, shift)   "Reward from", "Needed for", "Starts"
--   lootCatalogue (order 47, always) the Catalog facts: "Crafted: Tailoring
--              250", "Teaches: <craft> · Tailoring 250" (skill color band,
--              "known" once learned), "Buys: 3 items for Priest" on tokens,
--              "Reputation: Argent
--              Dawn · Revered", "PvP: 7,650 honor · Rank 8", "Part of: <set>
--              (2/8)", "Already learned", the content phase of loot that is
--              not out yet and the tank note on close Best in Slot picks
-- The gain line ("+6.2%", "+12.4 DPS", "BiS") is the Upgrades module's
-- `upgrade` section (order 10), so there is one gain number everywhere.
-- MobInfo's "Dropped by" (order 50) steps aside for items this file shows a
-- source for (E:LootGuideKnows).
--
-- Drop chances follow the Drop chances option: Classic values from
-- EldoUI_LootData, what you saw (Mob and Loot Info), both, or none. Which
-- kinds of sources show (drops, quests, vendors, reputation, PvP, crafting,
-- sets) is in that option's cog (LG.db.tipSources).
-- lootPlan lists every wishlist that holds the item, each with its note.
--
-- Rules: comparison tooltips are skipped; the item link and ID are checked
-- with issecretvalue before use (item data is not secret, but the check is
-- cheap). Rows are cached per item, so a tooltip costs a table lookup.
local _, E = ...
local LG = E.LootGuide
local L = E.L

local Key = E.Key
local GREY = { 0.65, 0.65, 0.7 }
local WHITE = { 0.92, 0.92, 0.94 }
local GOLD = { 1, 0.82, 0 }
local MAX_SOURCES = 3
local MAX_QUESTS = 3

local RANK = E:TranslateValues({ [1] = E.Key("Elite"), [2] = E.Key("Rare elite"), [3] = E.Key("Boss"), [4] = E.Key("Rare") })

local Secret = E.Secret

local function Hex(color)
	return ("|cff%02x%02x%02x"):format(color[1] * 255, color[2] * 255, color[3] * 255)
end

local function ItemID(link, itemID)
	if Secret(link) or Secret(itemID) then return end
	itemID = tonumber(itemID)
	if not itemID and type(link) == "string" then itemID = tonumber(link:match("item:(%d+)")) end
	return itemID
end

-- Is a kind of source switched on for tooltips (Drop chances cog)?
local function SourceOn(kind)
	local kinds = LG.db and LG.db.tipSources
	return not (type(kinds) == "table" and kinds[kind] == false)
end
LG.TooltipSourceOn = function(_, kind) return SourceOn(kind) end

local function IsCompare(tooltip)
	local name = tooltip and tooltip.GetName and tooltip:GetName()
	return type(name) == "string" and name:find("Shopping", 1, true) ~= nil
end

---------------------------------------------------------------------------
-- Row cache: itemID -> { [variant] = rows }. Cleared when anything the
-- rows show changes (data loaded, wishlist, sets, settings, a loot window).
---------------------------------------------------------------------------
local rowCache = {}
local cacheSize = 0

function LG:ClearTooltipCache()
	wipe(rowCache)
	cacheSize = 0
end

local function CachedRows(section, itemID, variant, build)
	local key = section .. variant
	local entry = rowCache[itemID]
	if entry and entry[key] then return entry[key] end
	if cacheSize > 1500 then LG:ClearTooltipCache() end
	if not rowCache[itemID] then
		rowCache[itemID] = {}
		cacheSize = cacheSize + 1
	end
	local rows = build() or false
	rowCache[itemID][key] = rows
	return rows
end

local function Emit(rows, add)
	if not rows then return end
	for _, row in ipairs(rows) do add(row[1], row[2], row[3], row[4], row[5], row[6], row[7], row[8]) end
end

---------------------------------------------------------------------------
-- Drop chance text by the Drop chances option
---------------------------------------------------------------------------
local function ChanceRight(entry, itemID)
	local mode = LG.db.dropRates
	if mode == "off" then return end
	local Kit = LG.Kit
	local parts = {}
	if (mode == "classic" or mode == "both") and type(entry.chance) == "number" then
		local r, g, b = Kit.ChanceColor(entry.chance)
		local text = Kit.ChanceText(entry.chance)
		if entry.questOnly then text = text .. " " .. L["(quest)"] end
		parts[#parts + 1] = Kit.Hex(r, g, b) .. text .. "|r"
	end
	if (mode == "seen" or mode == "both") and entry.kind == "npc" then
		local drops, kills = LG:Seen(entry.id, itemID)
		if drops and kills then
			parts[#parts + 1] = Hex(GREY) .. (L["seen %d/%d"]):format(drops, kills) .. "|r"
		end
	end
	if #parts == 0 then return end
	return table.concat(parts, "  ")
end

-- "Ras Frostwhisper · Scholomance", "Mor'Ladim · Rare · 35", "Chest · Stratholme"
local function SourceLeft(entry)
	if entry.kind == "world" then
		local band = entry.minLevel and entry.maxLevel and (" · " .. (L["level %d-%d"]):format(entry.minLevel, entry.maxLevel)) or ""
		return L["Random world drop"] .. Hex(GREY) .. band .. "|r"
	end
	local name = entry.name or (entry.kind == "npc" and L["NPC #%s"]:format(tostring(entry.id))) or L["Container"]
	local where
	if entry.instance then
		where = LG:InstanceName(entry.instance)
	elseif entry.kind == "npc" then
		local bits = {}
		if RANK[entry.rank or 0] then bits[#bits + 1] = RANK[entry.rank] end
		if entry.minLevel and entry.minLevel > 0 then
			if entry.maxLevel and entry.maxLevel ~= entry.minLevel then
				bits[#bits + 1] = ("%d-%d"):format(entry.minLevel, entry.maxLevel)
			else
				bits[#bits + 1] = tostring(entry.minLevel)
			end
		end
		where = #bits > 0 and table.concat(bits, " · ") or nil
	end
	if where then return name .. Hex(GREY) .. " · " .. where .. "|r" end
	return name
end

-- The drop sources (not quest rewards) of an item, best first.
local function Drops(itemID)
	local list, more = LG:ItemSources(itemID)
	if not list then return end
	local drops = {}
	for _, entry in ipairs(list) do
		if entry.kind == "npc" or entry.kind == "object" or entry.kind == "world" then drops[#drops + 1] = entry end
	end
	return drops, more or 0
end

-- "12 |T..|t" for an extended cost part.
local function CostPart(part)
	local icon, name
	if part.currency and C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
		local ok, currency = pcall(C_CurrencyInfo.GetCurrencyInfo, part.id)
		if ok and type(currency) == "table" then icon, name = currency.iconFileID, currency.name end
	elseif not part.currency then
		icon = C_Item.GetItemIconByID and C_Item.GetItemIconByID(part.id)
		name = C_Item.GetItemInfo(part.id)
	end
	if Secret(icon) then icon = nil end
	if Secret(name) then name = nil end
	local amount = tostring(part.amount or 1)
	if icon then return amount .. " |T" .. tostring(icon) .. ":12:12|t" end
	return amount .. " " .. (name or ("#" .. tostring(part.id)))
end

local function CostText(seen, price)
	local parts = {}
	local copper = seen and seen.gold or price
	if copper and copper > 0 then parts[#parts + 1] = LG.PageKit and LG.PageKit.MoneyText(copper) or tostring(copper) end
	for _, part in ipairs(seen and seen.cost or {}) do parts[#parts + 1] = CostPart(part) end
	if seen and seen.stack then parts[#parts + 1] = Hex(GREY) .. (L["for %d"]):format(seen.stack) .. "|r" end
	return #parts > 0 and table.concat(parts, " ") or nil
end

-- Vendor rows: { left, right } for up to `limit` vendors, and how many more.
local function VendorRows(itemID, limit)
	local npcs, more = LG:Vendors(itemID)
	local seen = LG:SeenVendorCost(itemID)
	if (not npcs or #npcs == 0) and seen and seen.npc then npcs = { seen.npc } end
	if not npcs or #npcs == 0 then return end
	local price = LG:Price(itemID)
	local rows = {}
	for index = 1, math.min(limit, #npcs) do
		local npc = npcs[index]
		local mob = LG:Mob(npc)
		local name = mob and mob.name or (seen and seen.npc == npc and seen.name) or L["NPC #%s"]:format(tostring(npc))
		local zone
		if mob and mob.instance then
			zone = LG:InstanceName(mob.instance)
		else
			local camp = LG:SpawnPoints("npc", npc)[1]
			zone = camp and LG:SpawnZone(camp)
		end
		local left = L["Vendor"] .. ": " .. name .. (zone and (Hex(GREY) .. " · " .. zone .. "|r") or "")
		rows[#rows + 1] = { left, CostText(seen and seen.npc == npc and seen or (index == 1 and seen) or nil, price), WHITE[1], WHITE[2], WHITE[3] }
	end
	return rows, #npcs - math.min(limit, #npcs) + (more or 0)
end

---------------------------------------------------------------------------
-- Sections
---------------------------------------------------------------------------
local function SourceSection(tooltip, link, itemID, add, info)
	if not LG.active or IsCompare(tooltip) or not LG:HasData() then return end
	itemID = ItemID(link, itemID)
	if not itemID then return end
	local shift = info and info.shift or IsShiftKeyDown()
	local variant = (shift and "s" or "n") .. LG.db.dropRates
	Emit(CachedRows("source", itemID, variant, function()
		local rows = {}
		local limit = shift and MAX_SOURCES or 1
		local drops, more
		if SourceOn("drops") then drops, more = Drops(itemID) end
		if drops and #drops > 0 then
			for index = 1, math.min(limit, #drops) do
				local entry = drops[index]
				rows[#rows + 1] = { SourceLeft(entry), ChanceRight(entry, itemID), WHITE[1], WHITE[2], WHITE[3] }
			end
			local hidden = #drops - limit + (more or 0)
			if hidden > 0 then
				local last = rows[#rows]
				last[1] = last[1] .. Hex(GREY) .. " " .. (L["(+%d more)"]):format(hidden) .. "|r"
			end
		end
		if SourceOn("vendors") then
			local vendors, hidden = VendorRows(itemID, limit)
			for _, row in ipairs(vendors or {}) do rows[#rows + 1] = row end
			if vendors and hidden > 0 then
				local last = rows[#rows]
				last[1] = last[1] .. Hex(GREY) .. " " .. (L["(+%d more)"]):format(hidden) .. "|r"
			end
		end
		return #rows > 0 and rows or nil
	end), add)
end

local function QuestList(ids, limit)
	local names = {}
	for index = 1, math.min(#ids, limit) do
		names[#names + 1] = LG:QuestTitle(ids[index]) or ("#" .. tostring(ids[index]))
	end
	local text = table.concat(names, ", ")
	if #ids > limit then text = text .. Hex(GREY) .. " " .. (L["(+%d more)"]):format(#ids - limit) .. "|r" end
	return text
end

local function QuestSection(tooltip, link, itemID, add)
	if not LG.active or IsCompare(tooltip) or not LG:HasData() or not SourceOn("quests") then return end
	itemID = ItemID(link, itemID)
	if not itemID then return end
	-- Quests the Quest use row already names (with their count) stay out
	-- of "Needed for"; the cache is kept per set of such quests.
	local named, variant = {}, ""
	if E.QuestUse and E:TooltipSectionShown("questUse") then
		local ids = E.QuestUse.Shown(itemID, link)
		for _, questID in ipairs(ids) do named[questID] = true end
		variant = table.concat(ids, ",")
	end
	Emit(CachedRows("quests", itemID, variant, function()
		local quests = LG:ItemQuests(itemID)
		if not quests then return end
		local rows = {}
		local needed = {}
		for _, questID in ipairs(quests.needed) do
			if not named[questID] then needed[#needed + 1] = questID end
		end
		if #quests.rewards > 0 then rows[#rows + 1] = { L["Reward from"], QuestList(quests.rewards, MAX_QUESTS) } end
		if #needed > 0 then rows[#rows + 1] = { L["Needed for"], QuestList(needed, MAX_QUESTS) } end
		if quests.starts then rows[#rows + 1] = { L["Starts"], QuestList({ quests.starts }, 1) } end
		return #rows > 0 and rows or nil
	end), add)
end

local function PlanSection(tooltip, link, itemID, add)
	if not LG.active or IsCompare(tooltip) then return end
	itemID = ItemID(link, itemID)
	if not itemID then return end
	Emit(CachedRows("plan", itemID, "", function()
		local rows = {}
		if LG:BiSOn() then
			local bis = LG.IsBiS and LG:IsBiS(itemID)
			local sets = LG:SetsWith(itemID)
			local bits = {}
			if bis then bits[#bits + 1] = type(bis) == "string" and (L["Best in Slot"] .. " · " .. bis) or L["Best in Slot"] end
			if sets then
				for index = 1, 2 do if sets[index] then bits[#bits + 1] = LG:SetName(index) end end
			end
			if #bits > 0 then
				local good = LG.Kit.GOOD
				rows[#rows + 1] = { table.concat(bits, " · "), nil, good[1], good[2], good[3] }
			end
		end
		if LG:WishlistOn() then
			local star = LG.Kit.HasAtlas("PetJournal-FavoritesIcon") and CreateAtlasMarkup
				and (CreateAtlasMarkup("PetJournal-FavoritesIcon", 12, 12) .. " ") or ""
			-- Every list that holds the item, each with its own note.
			local holding = {}
			for _, info in ipairs(LG:WishLists()) do
				local list = LG:WishListRecord(info.id)
				local entry = list and list.items and list.items[itemID]
				if entry then holding[#holding + 1] = { list = list, entry = entry } end
			end
			for _, hold in ipairs(holding) do
				local list = hold.list
				local label = L["On your wishlist"]
				if list.id ~= "main" or #holding > 1 then label = (L["On your wishlist %s"]):format(list.name or L["Wishlist"]) end
				rows[#rows + 1] = { star .. label, nil, GOLD[1], GOLD[2], GOLD[3] }
				local note = type(hold.entry) == "table" and hold.entry.note
				if type(note) == "string" and note ~= "" then
					rows[#rows + 1] = { "   \"" .. note .. "\"", nil, GOLD[1], GOLD[2], GOLD[3] }
				end
			end
		end
		local note = LG:ItemNote(itemID)
		if note and note ~= "" then rows[#rows + 1] = { note, nil, GREY[1], GREY[2], GREY[3] } end
		if LG.OpenCheck and LG.CheckHint then
			local hint = LG:CheckHint()
			if hint then rows[#rows + 1] = { hint, nil, GREY[1], GREY[2], GREY[3] } end
		end
		return #rows > 0 and rows or nil
	end), add)
end

-- Catalog facts.
local function RecipeHow(craft)
	local sources = LG:RecipeSources(craft)
	if sources.trainer then return L["trainer"] end
	for _, recipe in ipairs(sources.recipes) do
		if #recipe.vendors > 0 then return L["vendor"] end
		if #recipe.drops > 0 then return L["drop"] end
		if #recipe.quests > 0 then return L["quest"] end
	end
end

-- The name of what a recipe teaches: the crafted item, else the spell.
local function CraftName(craft)
	if craft.result and craft.result > 0 then
		local name = C_Item.GetItemInfo(craft.result)
		if Secret(name) then name = nil end
		local record = not name and LG:ItemRecord(craft.result)
		name = name or (record and record.name)
		if name then return name end
	end
	local spell = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(craft.id)
	if Secret(spell) then spell = nil end
	return spell or ("#" .. tostring(craft.id))
end

local function CatalogueSection(tooltip, link, itemID, add)
	if not LG.active or IsCompare(tooltip) then return end
	itemID = ItemID(link, itemID)
	if not itemID then return end
	Emit(CachedRows("catalogue", itemID, "", function()
		local rows = {}
		local Kit = LG.Kit
		local record = LG:ItemRecord(itemID)
		-- Loot from an instance WoW: Forever has not opened yet.
		local badge, phase
		if LG.PhaseBadge then badge, phase = LG:PhaseBadge(itemID) end
		if badge then rows[#rows + 1] = { (L["Not out yet: opens %s"]):format(LG:PhaseOpensText(phase, true)), nil, 0.85, 0.7, 0.4 } end
		-- Crafted and recipes.
		local craft = SourceOn("crafting") and LG.CraftOf and LG:CraftOf(itemID)
		if craft and craft.skill then
			rows[#rows + 1] = { L["Crafted"], ("%s %s"):format(LG:ProfessionName(craft.skill), tostring(craft.rank or "")), GREY[1], GREY[2], GREY[3] }
		end
		local teaches = SourceOn("crafting") and LG:Recipe(itemID)
		if teaches and teaches.skill then
			local how = RecipeHow(teaches)
			local known = LG:CraftKnown(teaches.id)
			local mySkill = LG:Player().professions[teaches.skill]
			local band = LG:SkillBand(teaches, mySkill)
			local color = known and Kit.GOOD or LG.BAND_COLORS[band or ""] or WHITE
			rows[#rows + 1] = { L["Teaches"] .. ": " .. CraftName(teaches), ("%s %s"):format(LG:ProfessionName(teaches.skill), tostring(teaches.rank or ""))
				.. (known and (" · " .. L["known"]) or (how and (" · " .. how) or "")), GREY[1], GREY[2], GREY[3], color[1], color[2], color[3] }
		end
		-- Tokens: what they buy for your class.
		local bought = SourceOn("sets") and LG.TokenFor and LG:TokenFor(itemID)
		if bought and #bought > 0 then
			local className = UnitClass("player")
			if Secret(className) then className = nil end
			rows[#rows + 1] = { E:Plural(#bought, "Buys: %d item for %s", "Buys: %d items for %s"):format(#bought, className or L["your class"]), nil, GOLD[1], GOLD[2], GOLD[3] }
		end
		-- Reputation.
		if SourceOn("reputation") and record and record.repFaction and record.repStanding then
			local live = LG:FactionStanding(record.repFaction)
			local reached = live and live.standing >= record.repStanding
			local color = reached and WHITE or Kit.BAD
			rows[#rows + 1] = { L["Reputation"], ("%s · %s"):format(LG:FactionName(record.repFaction), LG:StandingName(record.repStanding)),
				GREY[1], GREY[2], GREY[3], color[1], color[2], color[3] }
		end
		-- PvP cost and rank.
		local pvpRank = SourceOn("pvp") and record and LG.PvPItemRank and LG:PvPItemRank(itemID)
		if pvpRank then
			local honor = LG:PvPCost(itemID)
			local wallet = LG:PvPWallet()
			local reached = wallet.rank and wallet.rank >= pvpRank
			local text = (L["Rank %d"]):format(pvpRank)
			if honor then text = (L["%s honor"]):format(BreakUpLargeNumbers and BreakUpLargeNumbers(honor) or honor) .. " · " .. text end
			local color = reached and WHITE or Kit.BAD
			rows[#rows + 1] = { L["PvP"], text, GREY[1], GREY[2], GREY[3], color[1], color[2], color[3] }
		end
		-- Item set.
		local setID, set
		if SourceOn("sets") then setID, set = LG:SetsOf(itemID) end
		if setID and set then
			rows[#rows + 1] = { (L["Part of: %s (%d/%d)"]):format(set.name, LG:SetOwned(set), #set.pieces), nil, GOLD[1], GOLD[2], GOLD[3] }
		end
		-- Mounts and companions.
		if record and (record.mount or record.pet) and LG:IsLearned(itemID) then
			rows[#rows + 1] = { L["Already learned"], nil, Kit.GOOD[1], Kit.GOOD[2], Kit.GOOD[3] }
		end
		-- Tank note on close picks.
		if LG.TankNote and LG:BiSOn() then
			local note = LG:TankNote(itemID)
			if note then rows[#rows + 1] = { note, nil, GREY[1], GREY[2], GREY[3] } end
		end
		return #rows > 0 and rows or nil
	end), add)
end

LG.TooltipSections = { plan = PlanSection, source = SourceSection, quests = QuestSection, catalogue = CatalogueSection }

---------------------------------------------------------------------------
-- Registration and cache upkeep
---------------------------------------------------------------------------
function LG:OnEnableTooltip()
	self:ClearTooltipCache()
	if self.sectionsRegistered or not E.RegisterTooltipSection then return end
	self.sectionsRegistered = true
	E:RegisterTooltipSection("lootPlan", { order = 12, title = L["Loot Guide: plan"], default = "always",
		desc = L["Best in Slot, your plan sets, your wishlist and a short note about the item."],
		item = PlanSection })
	E:RegisterTooltipSection("lootSource", { order = 48, title = L["Loot Guide: drops"], default = "always",
		desc = L["Where the item drops and how often, and the vendors that sell it with the cost. Hold Shift for more sources and the drops you saw yourself."],
		item = SourceSection })
	E:RegisterTooltipSection("lootQuests", { order = 49, title = L["Loot Guide: quests"], default = "shift",
		desc = L["Quests that reward the item, need it, or start from it."],
		item = QuestSection })
	E:RegisterTooltipSection("lootCatalogue", { order = 47, title = L["Loot Guide: crafting, reputation, PvP, sets"], default = "always",
		desc = L["Crafted by, or what a recipe teaches and whether you know it; what a token buys; the reputation or PvP rank it needs; the set it is part of; already learned; a later phase and the tank note."],
		item = CatalogueSection })
end

function LG:OnDisableTooltip()
	self:ClearTooltipCache()
end

LG:On("tooltip", function(changed)
	if changed.data or changed.wishlist or changed.sets or changed.settings or changed.list or changed.pages or changed.rank
		or changed.spec or changed.gear or changed.learned or changed.crafts or changed.wallet or changed.reputation or changed.bags then
		LG:ClearTooltipCache()
	end
end)

-- Seen counts change when you loot.
LG:Listen("LOOT_CLOSED", "tooltip", function() LG:ClearTooltipCache() end)

-- A sample item for the "Show sample tooltip" button: one LootData knows,
-- else something you wear.
function LG:SampleItem()
	if self:HasData() then
		local data = rawget(_G, "EldoUI_LootData")
		local sources = data and data.sources
		if type(sources) == "table" then
			local itemID = next(sources)
			if itemID then return itemID end
		end
	end
	for slot = 1, 18 do
		local id = GetInventoryItemID("player", slot)
		if not Secret(id) and id then return id end
	end
end

function LG:ShowSampleTooltip()
	local itemID = self:SampleItem()
	if not itemID then
		E:Print(L["No sample item: wear something or install EldoUI_LootData."])
		return
	end
	GameTooltip:SetOwner(UIParent, "ANCHOR_CURSOR")
	if GameTooltip.SetItemByID then GameTooltip:SetItemByID(itemID) end
	GameTooltip:Show()
end
