-- EldoUI Loot Guide: data for the Catalog sections.
-- The pages are in UI/Pages/Crafting.lua, Reputation.lua, PvP.lua,
-- Sets.lua and Events.lua; this file reads EldoUI_LootData and the client.
--
--   Crafting   LG:Professions(), LG:ProfessionCrafts(skill), LG:SkillBand(craft, skill),
--              LG:CraftKnown(spellID), LG:ScanTradeSkill() (profession window, read-only),
--              LG:RecipeSources(craft)
--   Reputation LG:Factions(showAll, side), LG:FactionRewards(factionID),
--              LG:FactionQuests(factionID), LG:FactionStanding(factionID),
--              LG:StandingToGo(factionID, standing)
--   PvP        LG:PvPWallet(), LG:PvPGroups(), LG:PvPCost(itemID), LG:WeeklyHonour(),
--              LG:PvPPlan() / LG:SetPvPPick(itemID, on), LG:PlanRows()
--   Sets       LG:ItemSets(), LG:SetInfo(setID), LG:SetBonuses(setID), LG:SetsOf(itemID)
--   Tokens     LG:TokenList(), (LG:TokenRewards in Data.lua)
--   Collected  LG:Collections(), LG:IsLearned(itemID)
--   Events     LG:EventActive(event), LG:EventItems(event)
--
-- Everything is read-only: nothing crafts, buys, learns or queues. Merchant
-- and profession windows are read only when the player opens them.
local _, E = ...
local LG = E.LootGuide
local L = E.L

local Key = E.Key
local Secret = E.Secret

local Plain = E.Plain

local function LD()
	return select(3, LG:DataStatus())
end

-- Field n of a packed "a|b|c" string, without splitting the whole record.
local FIELD_PATTERNS = {}
local function Field(packed, n)
	if type(packed) ~= "string" then return end
	local pattern = FIELD_PATTERNS[n]
	if not pattern then
		pattern = "^" .. ("[^|]*|"):rep(n - 1) .. "([^|]*)"
		FIELD_PATTERNS[n] = pattern
	end
	return packed:match(pattern)
end
LG.Field = Field

-- Indexes built once per data load (items by set, faction, honor rank ...).
local indexes = {}
LG:On("catalogue-data", function(changed)
	if changed.data then wipe(indexes) end
end)
-- Also from LG:ClearDataCaches, before the "data" listeners run, so a page
-- that redraws when the data arrives never reads an index built without it.
function LG:ClearCatalogIndexes()
	wipe(indexes)
end

local function ItemIndex()
	if indexes.items then return indexes.items end
	local data = LD()
	local out = { sets = {}, factions = {}, honor = {}, mounts = {}, pets = {}, tabards = {}, legendary = {}, epics = {} }
	for itemID, packed in pairs(data and data.items or {}) do
		local quality = tonumber(Field(packed, 2))
		local invType = tonumber(Field(packed, 5))
		local set = tonumber(Field(packed, 14))
		if set and set > 0 then
			out.sets[set] = out.sets[set] or {}
			table.insert(out.sets[set], itemID)
		end
		local faction, standing = (Field(packed, 18) or ""):match("^(%d+):(%d+)$")
		if faction then
			faction = tonumber(faction)
			out.factions[faction] = out.factions[faction] or {}
			table.insert(out.factions[faction], { itemID = itemID, standing = tonumber(standing) })
		end
		local honor = tonumber(Field(packed, 19))
		if honor and honor > 0 then out.honor[#out.honor + 1] = itemID end
		local flags = Field(packed, 16) or ""
		if flags:find("M", 1, true) then out.mounts[#out.mounts + 1] = itemID end
		if flags:find("P", 1, true) then out.pets[#out.pets + 1] = itemID end
		if invType == 19 then out.tabards[#out.tabards + 1] = itemID end
		if quality == 5 then out.legendary[#out.legendary + 1] = itemID end
		if quality == 4 and invType and invType > 0 then
			local sources = data.sources and data.sources[itemID]
			if type(sources) == "string" and sources:find("w", 1, true) then out.epics[#out.epics + 1] = itemID end
		end
	end
	-- WoW: Forever's battleground reputation rewards (Data/PvPRewards.lua)
	-- and its own factions' rewards (Data/ForeverFactions.lua). A Classic item
	-- the loot data already ties to a faction keeps that one.
	for _, list in ipairs({ E.pvpRewards and E.pvpRewards.items or {}, E.foreverFactions and E.foreverFactions.items or {} }) do
		for itemID, packed in pairs(list) do
			local faction, standing = (Field(packed, 11) or ""):match("^(%d+):(%d+)$")
			local classic = data and data.items and data.items[itemID]
			if faction and not (classic and (Field(classic, 18) or "") ~= "") then
				faction = tonumber(faction)
				out.factions[faction] = out.factions[faction] or {}
				table.insert(out.factions[faction], { itemID = itemID, standing = tonumber(standing) })
			end
		end
	end
	for _, list in pairs(out) do
		if list[1] and type(list[1]) == "number" then table.sort(list) end
	end
	indexes.items = out
	return out
end
LG.CatalogueItemIndex = ItemIndex

---------------------------------------------------------------------------
-- Crafting
---------------------------------------------------------------------------
-- The twelve professions, gathering last. skill line IDs.
LG.PROFESSIONS = {
	{ id = 171, name = Key("Alchemy"), icon = "Interface\\Icons\\Trade_Alchemy" },
	{ id = 164, name = Key("Blacksmithing"), icon = "Interface\\Icons\\Trade_BlackSmithing" },
	{ id = 333, name = Key("Enchanting"), icon = "Interface\\Icons\\Trade_Engraving" },
	{ id = 202, name = Key("Engineering"), icon = "Interface\\Icons\\Trade_Engineering" },
	{ id = 165, name = Key("Leatherworking"), icon = "Interface\\Icons\\INV_Misc_ArmorKit_17" },
	{ id = 197, name = Key("Tailoring"), icon = "Interface\\Icons\\Trade_Tailoring" },
	{ id = 185, name = Key("Cooking"), icon = "Interface\\Icons\\INV_Misc_Food_15" },
	{ id = 129, name = Key("First Aid"), icon = "Interface\\Icons\\Spell_Holy_SealOfSacrifice" },
	{ id = 356, name = Key("Fishing"), icon = "Interface\\Icons\\Trade_Fishing", gathering = true },
	{ id = 186, name = Key("Mining"), icon = "Interface\\Icons\\Trade_Mining", gathering = true },
	{ id = 182, name = Key("Herbalism"), icon = "Interface\\Icons\\Trade_Herbalism", gathering = true },
	{ id = 40, name = Key("Rogue poisons"), icon = "Interface\\Icons\\Trade_BrewPoison", class = "ROGUE" },
}
E:TranslateFields(LG.PROFESSIONS, "name")
local PROFESSION_BY_ID = {}
for _, prof in ipairs(LG.PROFESSIONS) do PROFESSION_BY_ID[prof.id] = prof end

function LG:ProfessionInfo(skill)
	return PROFESSION_BY_ID[tonumber(skill) or 0]
end

-- The client's own (localized) name, else ours.
function LG:ProfessionName(skill)
	local util = C_TradeSkillUI
	if util and util.GetTradeSkillDisplayName then
		local ok, name = pcall(util.GetTradeSkillDisplayName, skill)
		if ok and type(name) == "string" and not Secret(name) and name ~= "" then return name end
	end
	local prof = PROFESSION_BY_ID[tonumber(skill) or 0]
	return prof and prof.name or ("#" .. tostring(skill))
end

-- The twelve, with your skill; yours first when "Your professions first" is on.
function LG:Professions()
	local mine = self:Player().professions
	local list = {}
	for index, prof in ipairs(self.PROFESSIONS) do
		list[#list + 1] = { id = prof.id, name = self:ProfessionName(prof.id), icon = prof.icon, gathering = prof.gathering,
			rank = mine[prof.id], order = index }
	end
	if self.db.craftOwnFirst then
		table.sort(list, function(a, b)
			if (a.rank ~= nil) ~= (b.rank ~= nil) then return a.rank ~= nil end
			return a.order < b.order
		end)
	end
	return list
end

local KnownStore -- below

-- Craft spells per skill line, built once from LD.crafts (the skill is
-- read without decoding every record).
local function CraftIndex()
	if indexes.crafts then return indexes.crafts end
	local data = LD()
	local out = {}
	for spellID, packed in pairs(data and data.crafts or {}) do
		local skill = tonumber((Field(packed, 3) or ""):match("^(%d+):"))
		if not skill and data.trainer and data.trainer[spellID] then
			skill = tonumber((Field(data.trainer[spellID], 1) or ""):match("^(%d+):"))
		end
		if skill then
			out[skill] = out[skill] or {}
			table.insert(out[skill], spellID)
		end
	end
	indexes.crafts = out
	return out
end

-- { craft, ... } for a skill line, by the skill needed then the name.
-- Recipes seen in your profession window that the loot data lacks (or all
-- of them without EldoUI_LootData) come from that window's cache.
function LG:ProfessionCrafts(skill)
	local list = {}
	local listed = {}
	for _, spellID in ipairs(CraftIndex()[tonumber(skill) or 0] or {}) do
		local craft = self:Craft(spellID)
		if craft then
			list[#list + 1] = craft
			listed[spellID] = true
		end
	end
	local store = KnownStore()
	for spellID, seen in pairs(store and store.seen or {}) do
		if type(seen) == "table" and seen.skill == tonumber(skill) and not listed[spellID] then
			list[#list + 1] = self:ApplyCraftLearnRank({
				id = spellID, result = seen.result or 0, count = seen.count or 1, reagents = seen.reagents or {},
				recipes = {}, skill = seen.skill, seen = true,
			})
		end
	end
	table.sort(list, function(a, b)
		if (a.rank or 0) ~= (b.rank or 0) then return (a.rank or 0) < (b.rank or 0) end
		return a.id < b.id
	end)
	return list
end

-- The client table supplies yellow and gray. Green begins at the
-- rounded-down midpoint. The learn requirement remains a separate value.
-- Older or unmatched recipes retain the usual estimated steps.
local BAND_STEPS = { yellow = 25, green = 37, grey = 50 }
LG.BAND_STEPS = BAND_STEPS

KnownStore = function(create)
	local data = LG:Char()
	if not data then return end
	if create and type(data.crafts) ~= "table" then data.crafts = { known = {}, band = {} } end
	if data.crafts and type(data.crafts.seen) ~= "table" then data.crafts.seen = {} end
	return data.crafts
end

-- What the profession window shows for a recipe (read-only): its skill
-- line, result and reagents, so crafts appear without the loot data too.
local function SeenRecipe(util, recipeID, profession)
	local entry = {}
	if profession then
		entry.skill = tonumber(Plain(profession.parentProfessionID)) or tonumber(Plain(profession.professionID))
	end
	if util.GetRecipeSchematic then
		local ok, schematic = pcall(util.GetRecipeSchematic, recipeID, false)
		if ok and type(schematic) == "table" then
			entry.result = tonumber(Plain(schematic.outputItemID))
			entry.count = tonumber(Plain(schematic.quantityMin)) or 1
			entry.reagents = {}
			for _, slot in ipairs(type(schematic.reagentSlotSchematics) == "table" and schematic.reagentSlotSchematics or {}) do
				local reagent = type(slot.reagents) == "table" and slot.reagents[1]
				local itemID = reagent and tonumber(Plain(reagent.itemID))
				if itemID then entry.reagents[#entry.reagents + 1] = { id = itemID, count = tonumber(Plain(slot.quantityRequired)) or 1 } end
			end
		end
	end
	if entry.skill and PROFESSION_BY_ID[entry.skill] and entry.result then return entry end
end

function LG:SkillThresholds(craft)
	local learn = craft.rank or 1
	local source = E.recipeThresholds and E.recipeThresholds[craft.id]
	local yellow, grey = craft.yellow, craft.grey
	local learnConfirmed = craft.learnConfirmed == true
	if source and source[1] == craft.skill then
		yellow, grey = source[2], source[3]
	end
	if yellow and grey and 0 < yellow and yellow <= grey then
		return { orange = learn, yellow = yellow, green = math.floor((yellow + grey) / 2), grey = grey,
			learnConfirmed = learnConfirmed }, false
	end
	return { orange = learn, yellow = learn + BAND_STEPS.yellow, green = learn + BAND_STEPS.green, grey = learn + BAND_STEPS.grey,
		learnConfirmed = learnConfirmed }, true
end

function LG:SkillBand(craft, skill)
	if not craft then return end
	local thresholds, estimated = self:SkillThresholds(craft)
	local store = KnownStore()
	local seen = store and store.band and store.band[craft.id]
	if not skill then return nil, estimated, thresholds end
	if type(seen) == "table" and seen.skill == skill then return seen.color, estimated, thresholds end
	if skill < thresholds.orange and (thresholds.learnConfirmed or estimated) then return "red", estimated, thresholds end
	if skill >= thresholds.grey then return "grey", estimated, thresholds end
	if skill >= thresholds.green then return "green", estimated, thresholds end
	if skill >= thresholds.yellow then return "yellow", estimated, thresholds end
	return "orange", estimated, thresholds
end

LG.BAND_COLORS = {
	orange = { 1, 0.5, 0.25 }, yellow = { 1, 1, 0 }, green = { 0.25, 0.75, 0.25 }, grey = { 0.5, 0.5, 0.5 }, red = { 1, 0.3, 0.3 },
}

function LG:CraftKnown(spellID)
	local store = KnownStore()
	return store and store.known and store.known[tonumber(spellID) or 0] and true or false
end

-- Read the open profession window (read-only): which recipes you know and
-- their color. Works with the modern trade-skill API and the classic one.
local DIFFICULTY = { optimal = "orange", medium = "yellow", easy = "green", trivial = "grey",
	[0] = "orange", [1] = "yellow", [2] = "green", [3] = "grey" }

local function SaveObservedBand(store, recipeID, color, skill)
	skill = tonumber(Plain(skill))
	if color and skill and skill > 0 then store.band[recipeID] = { skill = skill, color = color } end
end

function LG:ScanTradeSkill()
	local store = KnownStore(true)
	if not store then return 0 end
	if type(store.band) ~= "table" then store.band = {} end
	local count = 0
	local util = C_TradeSkillUI
	if util and util.GetAllRecipeIDs and util.GetRecipeInfo then
		local ids = E.PlainCall(util.GetAllRecipeIDs)
		if type(ids) == "table" then
			for _, recipeID in ipairs(ids) do
				local info = E.PlainCall(util.GetRecipeInfo, recipeID)
				if type(info) == "table" and Plain(info.learned) then
					store.known[recipeID] = true
					local profession = E.PlainCall(util.GetProfessionInfoByRecipeID, recipeID)
					if type(profession) ~= "table" then profession = nil end
					if not store.seen[recipeID] then store.seen[recipeID] = SeenRecipe(util, recipeID, profession) end
					local band = DIFFICULTY[Plain(info.relativeDifficulty) or -1] or DIFFICULTY[Plain(info.difficulty) or ""]
					-- The cached player rank can still be from before this list update.
					SaveObservedBand(store, recipeID, band, profession and profession.skillLevel)
					count = count + 1
				end
			end
		end
	end
	-- The classic profession window (probed: Forever may not have it).
	local numSkills, skillInfo, recipeLink = rawget(_G, "GetNumTradeSkills"), rawget(_G, "GetTradeSkillInfo"), rawget(_G, "GetTradeSkillRecipeLink")
	if count == 0 and numSkills and skillInfo and recipeLink then
		local ok, total = pcall(numSkills)
		local _, skill = E.PlainCallEach(rawget(_G, "GetTradeSkillLine"))
		for index = 1, ok and tonumber(Plain(total)) or 0 do
			local _, kind = skillInfo(index)
			kind = Plain(kind)
			if kind and kind ~= "header" and kind ~= "subheader" then
				local link = Plain(recipeLink(index))
				local spellID = type(link) == "string" and tonumber(link:match("enchant:(%d+)") or link:match("spell:(%d+)"))
				if spellID then
					store.known[spellID] = true
					SaveObservedBand(store, spellID, DIFFICULTY[kind], skill)
					count = count + 1
				end
			end
		end
	end
	if count > 0 then self:Fire("crafts") end
	return count
end

for _, event in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE" }) do
	LG:Listen(event, "crafts", function() C_Timer.After(0.2, function() LG:ScanTradeSkill() end) end)
end

-- Where a craft's recipe comes from: { trainer = { cost, value, npcs },
-- recipes = { { itemID, vendors = { npc... }, drops = { source... },
-- quests = { questID... } } } }.
function LG:RecipeSources(craft)
	local out = { trainer = craft and craft.trainer, recipes = {} }
	for _, itemID in ipairs(craft and craft.recipes or {}) do
		local entry = { itemID = itemID, vendors = {}, drops = {}, quests = {} }
		for _, source in ipairs(self:ItemSources(itemID) or {}) do
			if source.kind == "vendor" or source.kind == "repvendor" or source.kind == "pvpvendor" then
				entry.vendors[#entry.vendors + 1] = source
			elseif source.kind == "npc" or source.kind == "object" or source.kind == "world" then
				entry.drops[#entry.drops + 1] = source
			elseif source.kind == "quest" or source.kind == "choice" then
				entry.quests[#entry.quests + 1] = source.id
			end
		end
		out.recipes[#out.recipes + 1] = entry
	end
	return out
end

-- "Crafted: Tailoring 250" and "Recipe: Tailoring 250 · trainer" lines.
function LG:CraftOf(itemID)
	for _, source in ipairs(self:ItemSources(itemID) or {}) do
		if source.kind == "crafted" then return self:Craft(source.id) end
	end
end

---------------------------------------------------------------------------
-- Reputation
---------------------------------------------------------------------------
-- side: nil = both, "Alliance", "Horde".
LG.FACTIONS = {
	{ id = 529, name = Key("Argent Dawn") }, { id = 576, name = Key("Timbermaw Hold") },
	{ id = 59, name = Key("Thorium Brotherhood") }, { id = 609, name = Key("Cenarion Circle") },
	{ id = 270, name = Key("Zandalar Tribe") }, { id = 910, name = Key("Brood of Nozdormu") },
	{ id = 749, name = Key("Hydraxian Waterlords") }, { id = 87, name = Key("Bloodsail Buccaneers") },
	{ id = 589, name = Key("Wintersaber Trainers"), side = "Alliance" }, { id = 809, name = Key("Shen'dralar") },
	{ id = 909, name = Key("Darkmoon Faire") }, { id = 349, name = Key("Ravenholdt") },
	{ id = 730, name = Key("Stormpike Guard"), side = "Alliance" }, { id = 729, name = Key("Frostwolf Clan"), side = "Horde" },
	{ id = 890, name = Key("Silverwing Sentinels"), side = "Alliance" }, { id = 889, name = Key("Warsong Outriders"), side = "Horde" },
	{ id = 509, name = Key("The League of Arathor"), side = "Alliance" }, { id = 510, name = Key("The Defilers"), side = "Horde" },
	{ id = 2799, name = Key("Theramore Expeditionary Force"), side = "Alliance" }, { id = 2798, name = Key("Darkspear Raiders"), side = "Horde" },
	{ id = 72, name = Key("Stormwind"), side = "Alliance" }, { id = 47, name = Key("Ironforge"), side = "Alliance" },
	{ id = 69, name = Key("Darnassus"), side = "Alliance" }, { id = 54, name = Key("Gnomeregan Exiles"), side = "Alliance" },
	{ id = 76, name = Key("Orgrimmar"), side = "Horde" }, { id = 81, name = Key("Thunder Bluff"), side = "Horde" },
	{ id = 68, name = Key("Undercity"), side = "Horde" }, { id = 530, name = Key("Darkspear Trolls"), side = "Horde" },
	{ id = 369, name = Key("Gadgetzan") }, { id = 470, name = Key("Ratchet") }, { id = 21, name = Key("Booty Bay") },
	{ id = 577, name = Key("Everlook") },
}
E:TranslateFields(LG.FACTIONS, "name")
LG.STANDING_THRESHOLD = { [0] = -42000, [1] = -6000, [2] = -3000, [3] = 0, [4] = 3000, [5] = 9000, [6] = 21000, [7] = 42000 }
local FACTION_BY_ID = {}
for _, faction in ipairs(LG.FACTIONS) do FACTION_BY_ID[faction.id] = faction end
-- WoW: Forever's own factions (Data/ForeverFactions.lua, client tables) come
-- first, in the game's order; one listed above keeps its place and gains its cap.
do
	local forever = E.foreverFactions and E.foreverFactions.factions
	if type(forever) == "table" then
		local sides = { A = "Alliance", H = "Horde" }
		local list = {}
		for _, row in ipairs(forever) do
			local known = FACTION_BY_ID[row[1]]
			if known then
				known.cap = row[3]
			else
				local faction = { id = row[1], side = sides[row[2]], cap = row[3], name = row[4] }
				FACTION_BY_ID[faction.id] = faction
				list[#list + 1] = faction
			end
		end
		for _, faction in ipairs(LG.FACTIONS) do list[#list + 1] = faction end
		LG.FACTIONS = list
	end
end

function LG:FactionName(factionID)
	local rep = C_Reputation
	if rep and rep.GetFactionDataByID then
		local ok, data = pcall(rep.GetFactionDataByID, factionID)
		if ok and type(data) == "table" and type(data.name) == "string" and not Secret(data.name) and data.name ~= "" then return data.name end
	end
	local known = FACTION_BY_ID[tonumber(factionID) or 0]
	return known and known.name or ("#" .. tostring(factionID))
end

-- The standing name for 0 (hated) .. 7 (exalted), from the client.
function LG:StandingName(standing)
	local name = rawget(_G, "FACTION_STANDING_LABEL" .. ((tonumber(standing) or 3) + 1))
	if type(name) == "string" then return name end
	local names = { [0] = L["Hated"], L["Hostile"], L["Unfriendly"], L["Neutral"], L["Friendly"], L["Honored"], L["Revered"], L["Exalted"] }
	return names[tonumber(standing) or 3] or "?"
end

-- The game's standing color.
function LG:StandingColor(standing)
	local r, g, b = E:GetReactionColor((tonumber(standing) or 3) + 1)
	if r then return r, g, b end
	return 0.8, 0.8, 0.8
end

-- { standing (0-7), value, min, max, met } from the client, or nil.
function LG:FactionStanding(factionID)
	local rep = C_Reputation
	if not (rep and rep.GetFactionDataByID) then return end
	local ok, data = pcall(rep.GetFactionDataByID, tonumber(factionID))
	if not ok or type(data) ~= "table" then return end
	local reaction, value = Plain(data.reaction), Plain(data.currentStanding)
	if not tonumber(reaction) then return end
	return { standing = tonumber(reaction) - 1, value = tonumber(value), min = tonumber(Plain(data.currentReactionThreshold)),
		max = tonumber(Plain(data.nextReactionThreshold)), name = Plain(data.name) }
end

-- The most reputation a faction gives when it stops below Exalted, and the
-- standing that is: (cap, standing), or nil.
function LG:FactionCap(factionID)
	local known = FACTION_BY_ID[tonumber(factionID) or 0]
	local cap = known and tonumber(known.cap)
	if not cap then return end
	local standing = 0
	for index = 7, 0, -1 do
		if cap >= self.STANDING_THRESHOLD[index] then standing = index break end
	end
	return cap, standing
end

-- Reputation left to reach a standing (0 when reached; nil when unknown or
-- above the faction's cap).
function LG:StandingToGo(factionID, standing)
	local live = self:FactionStanding(factionID)
	local need = self.STANDING_THRESHOLD[tonumber(standing) or 0]
	if not (live and need) then return end
	local cap = self:FactionCap(factionID)
	if cap and need > cap then return end
	if live.standing >= standing then return 0 end
	if not live.value then return end
	return math.max(need - live.value, 0)
end

-- Faction ids the reputation panel shows (met factions), or nil when the
-- client does not say.
local function MetFactions()
	local rep = C_Reputation
	if not (rep and rep.GetNumFactions and rep.GetFactionDataByIndex) then return end
	local ok, count = pcall(rep.GetNumFactions)
	count = ok and tonumber(Plain(count)) or 0
	if count == 0 then return end
	local met = {}
	for index = 1, count do
		local fine, data = pcall(rep.GetFactionDataByIndex, index)
		if fine and type(data) == "table" and tonumber(Plain(data.factionID)) then met[tonumber(data.factionID)] = true end
	end
	return next(met) and met or nil
end

-- The factions to list: { { id, name, side, standing } } for your side
-- (side = "other" lists the other side's), met only unless showAll.
function LG:Factions(showAll, side)
	local mine = self:Player().faction
	local met = not showAll and MetFactions() or nil
	local list = {}
	for index, faction in ipairs(self.FACTIONS) do
		local sideOK
		if side == "other" then
			sideOK = faction.side ~= nil and faction.side ~= mine
		else
			sideOK = faction.side == nil or faction.side == mine
		end
		if sideOK and (not met or met[faction.id] or side == "other") then
			list[#list + 1] = { id = faction.id, name = self:FactionName(faction.id), side = faction.side, order = index,
				live = self:FactionStanding(faction.id) }
		end
	end
	return list
end

-- Items a faction's standing opens: { [standing] = { itemID, ... } }.
function LG:FactionRewards(factionID)
	local out = {}
	for _, entry in ipairs(ItemIndex().factions[tonumber(factionID) or 0] or {}) do
		local standing = entry.standing or 4
		out[standing] = out[standing] or {}
		table.insert(out[standing], entry.itemID)
	end
	return out
end

-- Quests that need a standing with the faction: { [standing] = { questID, ... } }.
local function QuestRepIndex()
	if indexes.questRep then return indexes.questRep end
	local data = LD()
	local out = {}
	for questID, packed in pairs(data and data.quests or {}) do
		local faction, value = (Field(packed, 26) or ""):match("^(%d+):(%-?%d+)$")
		faction, value = tonumber(faction), tonumber(value)
		if faction and value then
			local standing = 0
			for s = 7, 0, -1 do
				if value >= LG.STANDING_THRESHOLD[s] then standing = s break end
			end
			out[faction] = out[faction] or {}
			out[faction][standing] = out[faction][standing] or {}
			table.insert(out[faction][standing], questID)
		end
	end
	indexes.questRep = out
	return out
end

function LG:FactionQuests(factionID)
	return QuestRepIndex()[tonumber(factionID) or 0] or {}
end

-- What a reward costs: { gold, seen, cost = { { id, amount, currency } } }.
function LG:RewardCost(itemID)
	local seen = self:SeenVendorCost(itemID)
	local gold, fromVendor = self:Price(itemID)
	return { gold = gold, seen = seen ~= nil, fromVendor = fromVendor, cost = seen and seen.cost or nil }
end

---------------------------------------------------------------------------
-- PvP
---------------------------------------------------------------------------
-- Battleground marks (items) and their battlegrounds.
LG.PVP_MARKS = {
	{ id = 20560, key = "av", name = Key("Alterac Valley") },
	{ id = 20558, key = "wsg", name = Key("Warsong Gulch") },
	{ id = 20559, key = "ab", name = Key("Arathi Basin") },
	{ id = 274895, key = "di", name = Key("Darkspear Islands") },
}
E:TranslateFields(LG.PVP_MARKS, "name")
-- Battleground factions -> group key.
local BG_FACTIONS = { [729] = "av", [730] = "av", [889] = "wsg", [890] = "wsg", [509] = "ab", [510] = "ab",
	[2798] = "di", [2799] = "di" }
LG.PVP_BG_FACTIONS = BG_FACTIONS
-- Battleground quartermasters -> group key (classic-db lists no standing
-- on most Alterac Valley and Warsong Gulch rewards; the vendor tells).
local BG_VENDORS = { [13216] = "av", [13217] = "av", [13218] = "av", [13219] = "av", [14753] = "wsg", [14754] = "wsg",
	[15126] = "ab", [15127] = "ab" }
LG.PVP_BG_VENDORS = BG_VENDORS
-- Honor currency ids to try (Classic, then the modern one).
local HONOR_CURRENCIES = { 1901, 1792 }
-- The season rank track: the faction Blizzard's own WoW: Forever rank window
-- reads (renown level = PvP rank, 0 before Rank 1).
local PVP_RANK_FACTION = 2800
local PVP_RANKS = 14
LG.PVP_RANK_FACTION = PVP_RANK_FACTION

-- The rank on the season track, or nil when the game does not say.
local function SeasonRank()
	local factions = rawget(_G, "C_MajorFactions")
	if not (type(factions) == "table" and factions.GetMajorFactionProgressionInfo) then return end
	local ok, info = pcall(factions.GetMajorFactionProgressionInfo, PVP_RANK_FACTION)
	if not ok or type(info) ~= "table" then return end
	local rank = Plain(info.renownLevel)
	if type(rank) ~= "number" or rank < 0 or rank > PVP_RANKS then return end
	return rank
end

-- The rank's title in the client's language, as Blizzard's rank window
-- builds it: PVP_RANK_<4 + rank>_<0 Horde, 1 Alliance>, the female form too.
local function RankTitle(rank)
	if not rank or rank < 1 then return end
	local side = UnitFactionGroup and select(2, pcall(UnitFactionGroup, "player"))
	local key = ("PVP_RANK_%d_%d"):format(rank + 4, side == "Alliance" and 1 or 0)
	local getText = rawget(_G, "GetText")
	if getText then
		local sex = UnitSex and select(2, pcall(UnitSex, "player"))
		local ok, text = pcall(getText, key, tonumber(Plain(sex)))
		if ok and type(text) == "string" and not Secret(text) and text ~= "" and text ~= key then return text end
	end
	local text = rawget(_G, key)
	if type(text) == "string" and text ~= "" then return text end
end

function LG:HonorCurrency()
	local info = C_CurrencyInfo
	if not (info and info.GetCurrencyInfo) then return end
	for _, id in ipairs(HONOR_CURRENCIES) do
		local ok, data = pcall(info.GetCurrencyInfo, id)
		if ok and type(data) == "table" and type(Plain(data.name)) == "string" and data.name ~= "" then
			return id, tonumber(Plain(data.quantity)) or 0, data.name, Plain(data.iconFileID)
		end
	end
end

-- { honor, honorName, honorIcon, marks = { { id, key, name, count } }, rank, rankName }
function LG:PvPWallet()
	local wallet = { marks = {} }
	local _, amount, name, icon = self:HonorCurrency()
	wallet.honor, wallet.honorName, wallet.honorIcon = amount, name, icon
	for _, mark in ipairs(self.PVP_MARKS) do
		local count = C_Item.GetItemCount and C_Item.GetItemCount(mark.id, true) or 0
		if Secret(count) then count = 0 end
		wallet.marks[#wallet.marks + 1] = { id = mark.id, key = mark.key, name = mark.name, count = tonumber(count) or 0 }
	end
	local season = SeasonRank()
	if season then
		wallet.rank, wallet.rankName = season, RankTitle(season)
		return wallet
	end
	local unitRank, rankInfo = rawget(_G, "UnitPVPRank"), rawget(_G, "GetPVPRankInfo")
	if unitRank and rankInfo then
		local ok, rank = pcall(unitRank, "player")
		rank = ok and tonumber(Plain(rank)) or nil
		if rank and rank >= 5 then
			local fine, rankName, number = pcall(rankInfo, rank)
			if fine and not Secret(rankName) then wallet.rank, wallet.rankName = tonumber(Plain(number)) or (rank - 4), rankName end
		end
	end
	return wallet
end

-- The rank WoW: Forever's rank rewards need, as the game reports it per rank
-- (C_MajorFactions.GetRenownRewardsForLevel), kept per season. Read when the
-- PvP page asks; until the game answers, no rank is shown.
local function RankStore()
	local cache = LG:Cache()
	local season = rawget(_G, "GetCurrentArenaSeason") and select(2, pcall(GetCurrentArenaSeason))
	season = tonumber(Plain(season)) or 0
	if type(cache.pvpRanks) ~= "table" or cache.pvpRanks.season ~= season then
		cache.pvpRanks = { season = season, items = {} }
	end
	return cache.pvpRanks
end

function LG:LearnPvPRewardRanks()
	local factions = rawget(_G, "C_MajorFactions")
	if self.pvpRanksRead or not (type(factions) == "table" and factions.GetRenownRewardsForLevel) then return end
	local store, found = RankStore(), 0
	for rank = 1, PVP_RANKS do
		local ok, rewards = pcall(factions.GetRenownRewardsForLevel, PVP_RANK_FACTION, rank)
		if ok and type(rewards) == "table" then
			for _, reward in ipairs(rewards) do
				local itemID = type(reward) == "table" and tonumber(Plain(reward.itemID))
				if itemID and itemID > 0 then
					found = found + 1
					if not store.items[itemID] or store.items[itemID] > rank then store.items[itemID] = rank end
				end
			end
		end
	end
	-- An empty answer (the data not loaded yet) is asked again next time.
	if found > 0 then self.pvpRanksRead = true end
end

function LG:PvPRewardRank(itemID)
	local rank = RankStore().items[tonumber(itemID)]
	return type(rank) == "number" and rank or nil
end

-- The rank an item needs: the item's own (original rank items) or the
-- game's answer for a WoW: Forever reward; nil when nobody says.
function LG:PvPItemRank(itemID)
	local record = self:ItemRecord(itemID)
	if not record then return end
	if record.pvpReward then return self:PvPRewardRank(itemID) end
	if record.honorRank and record.honorRank > 0 then return record.honorRank end
end

local function PlayerSide()
	local ok, side = pcall(UnitFactionGroup, "player")
	return ok and (side == "Horde" and "H" or side == "Alliance" and "A") or nil
end

-- Group key for a PvP item.
function LG:PvPGroup(itemID)
	local record = self:ItemRecord(itemID)
	if not record then return end
	if record.repFaction and BG_FACTIONS[record.repFaction] then return BG_FACTIONS[record.repFaction] end
	if record.pvpReward then
		if record.class == 2 then return "weapons" end
		if record.invType == 12 or record.invType == 19 then return "insignia" end
		if record.invType == 0 then return "seals" end
		if record.set and record.set > 0 then return "sets" end
		return "armor"
	end
	if not (record.honorRank and record.honorRank > 0) then
		for _, npc in ipairs(self:Vendors(itemID) or {}) do
			if BG_VENDORS[npc] then return BG_VENDORS[npc] end
		end
		return
	end
	if record.mount then return "mounts" end
	if record.invType == 12 then return "insignia" end
	if record.set and record.set > 0 then return "sets" end
	if record.class == 2 then return "weapons" end
	return "armor"
end

LG.PVP_GROUPS = {
	{ key = "av", title = "Alterac Valley" }, { key = "wsg", title = "Warsong Gulch" }, { key = "ab", title = "Arathi Basin" },
	{ key = "di", title = "Darkspear Islands", map = 2524 },
	{ key = "sets", title = "PvP class sets" }, { key = "armor", title = "PvP armor" }, { key = "weapons", title = "PvP weapons" },
	{ key = "seals", title = "Emboldened seals" }, { key = "mounts", title = "Mounts" }, { key = "insignia", title = "Insignia and tabards" },
}
E:TranslateFields(LG.PVP_GROUPS, "title")

-- A group's name: a battleground WoW: Forever added reads its name from the
-- game's map, in the client's language.
function LG:PvPGroupTitle(group)
	local info = group.map and C_Map and C_Map.GetMapInfo and select(2, pcall(C_Map.GetMapInfo, group.map))
	local name = type(info) == "table" and info.name
	if type(name) == "string" and not Secret(name) and name ~= "" then return name end
	return group.title
end

-- { [group] = { itemID, ... } } for your faction (side = "all" both).
function LG:PvPGroups(side)
	local out = {}
	local index = ItemIndex()
	local seen = {}
	local function Add(itemID)
		if seen[itemID] then return end
		local group = self:PvPGroup(itemID)
		if not group then return end
		if side ~= "all" then
			local record = self:ItemRecord(itemID)
			local ok, reason = self:CanUseRecord(record, true)
			if not ok and reason == "race" then return end
			local mine = record and record.side and PlayerSide()
			if mine and record.side ~= mine then return end
		end
		seen[itemID] = true
		out[group] = out[group] or {}
		table.insert(out[group], itemID)
	end
	-- WoW: Forever's rank vendors sell their own rewards. The original rank
	-- items stay out, except the war mounts, until a vendor shows otherwise.
	local rewards = E.pvpRewards and E.pvpRewards.items
	if type(rewards) == "table" then
		self:LearnPvPRewardRanks()
		local mine = PlayerSide()
		for itemID in pairs(rewards) do
			local record = self:ItemRecord(itemID)
			if record and (side == "all" or not record.side or not mine or record.side == mine) then Add(itemID) end
		end
		for _, itemID in ipairs(index.honor) do
			local record = self:ItemRecord(itemID)
			if record and record.mount then Add(itemID) end
		end
	else
		for _, itemID in ipairs(index.honor) do Add(itemID) end
	end
	for faction in pairs(BG_FACTIONS) do
		for _, entry in ipairs(index.factions[faction] or {}) do Add(entry.itemID) end
	end
	for npc in pairs(BG_VENDORS) do
		for itemID in pairs(self:VendorItems(npc) or {}) do Add(itemID) end
	end
	-- Rank or standing first, read once per item rather than per comparison.
	local rank = {}
	for itemID in pairs(seen) do
		local record = self:ItemRecord(itemID)
		rank[itemID] = { self:PvPItemRank(itemID) or (record and record.repStanding) or 0, record and record.itemLevel or 0 }
	end
	for _, list in pairs(out) do
		table.sort(list, function(a, b)
			local ra, rb = rank[a], rank[b]
			if ra[1] ~= rb[1] then return ra[1] < rb[1] end
			if ra[2] ~= rb[2] then return ra[2] < rb[2] end
			return a < b
		end)
	end
	return out
end

-- Honor and mark cost seen at a vendor: honor, marks = { [itemID] = n }, gold; nil when unknown.
function LG:PvPCost(itemID)
	local seen = self:SeenVendorCost(itemID)
	if not seen then return end
	local honor, marks = nil, {}
	local honorID = self:HonorCurrency()
	for _, part in ipairs(seen.cost or {}) do
		if part.currency then
			if part.id == honorID or part.id == 1901 or part.id == 1792 then honor = (honor or 0) + (part.amount or 0) end
		else
			marks[part.id] = (marks[part.id] or 0) + (part.amount or 0)
		end
	end
	return honor, marks, seen.gold
end

-- Weekly honor income, from your own currency changes (per character,
-- the last 8 weeks). The week ends at the weekly reset.
local WEEK = 7 * 24 * 3600

local function IncomeStore()
	local data = LG:Char()
	if not data then return end
	if type(data.pvpIncome) ~= "table" then data.pvpIncome = { weeks = {} } end
	if type(data.pvpIncome.weeks) ~= "table" then data.pvpIncome.weeks = {} end
	return data.pvpIncome
end

local function WeekKey(now)
	now = now or time()
	local untilReset = C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset and C_DateAndTime.GetSecondsUntilWeeklyReset()
	untilReset = tonumber(Plain(untilReset))
	if not untilReset then return math.floor(now / WEEK) end
	-- The time the current week ends, rounded to the hour (stable per week).
	return math.floor((now + untilReset) / 3600 + 0.5)
end
LG.HonorWeekKey = WeekKey

-- Record a change in honor (CURRENCY_DISPLAY_UPDATE).
function LG:TrackHonour(amount)
	local store = IncomeStore()
	amount = tonumber(amount)
	if not (store and amount) then return end
	local week = WeekKey()
	if store.last and amount > store.last then
		store.weeks[week] = (store.weeks[week] or 0) + (amount - store.last)
	end
	store.last = amount
	store.weeks[week] = store.weeks[week] or 0
	-- Keep the newest 8 weeks.
	local keys = {}
	for key in pairs(store.weeks) do keys[#keys + 1] = key end
	table.sort(keys)
	for index = 1, #keys - 8 do store.weeks[keys[index]] = nil end
end

-- honor per week for the planner, and where it came from ("typed",
-- "recent", "none").
function LG:WeeklyHonour()
	local typed = tonumber(self.db.pvpIncome)
	if typed and typed > 0 then return typed, "typed" end
	local store = IncomeStore()
	if not store then return 0, "none" end
	local current = WeekKey()
	local sum, weeks = 0, 0
	for key, gain in pairs(store.weeks) do
		if key ~= current then
			sum, weeks = sum + gain, weeks + 1
		end
	end
	if weeks == 0 then
		local now = store.weeks[current]
		if now and now > 0 then return now, "recent" end
		return 0, "none"
	end
	return math.floor(sum / weeks + 0.5), "recent"
end

LG:Listen("CURRENCY_DISPLAY_UPDATE", "pvp", function()
	local _, amount = LG:HonorCurrency()
	if amount then LG:TrackHonour(amount) end
	LG:Fire("wallet")
end)
LG:Listen("BAG_UPDATE_DELAYED", "pvp", function() LG:Fire("wallet") end)
-- A new rank on the season track.
LG:Listen("UPDATE_FACTION", "pvp", function() LG:Fire("wallet") end)
LG:Listen("MAJOR_FACTION_RENOWN_LEVEL_CHANGED", "pvp", function(_, factionID)
	if factionID == PVP_RANK_FACTION then LG:Fire("wallet") end
end)
LG:Listen("PLAYER_PVP_RANK_CHANGED", "pvp", function() LG:Fire("wallet") end)
LG:Listen("PLAYER_ENTERING_WORLD", "pvp", function()
	local _, amount = LG:HonorCurrency()
	if amount then LG:TrackHonour(amount) end
end)

-- Planner picks (per character, window state).
function LG:PvPPlan()
	local data = self:Char()
	if not data then return {} end
	if type(data.pvpPlan) ~= "table" then data.pvpPlan = {} end
	return data.pvpPlan
end

function LG:IsPvPPick(itemID)
	for _, id in ipairs(self:PvPPlan()) do
		if id == tonumber(itemID) then return true end
	end
	return false
end

function LG:SetPvPPick(itemID, on)
	local plan = self:PvPPlan()
	itemID = tonumber(itemID)
	if not itemID then return end
	for index = #plan, 1, -1 do
		if plan[index] == itemID then table.remove(plan, index) end
	end
	if on then plan[#plan + 1] = itemID end
	self:Fire("pvpplan")
end

-- The planner: one row per pick, in order, with the running total and
-- the weeks until you can afford it. { { itemID, honor, total, now (can
-- buy now), weeks (0 = this week, nil = never), known (cost seen) } },
-- summary { total, known, unknown, income, source }.
function LG:PlanRows()
	local rows = {}
	local wallet = self:PvPWallet()
	local have = wallet.honor or 0
	local income, source = self:WeeklyHonour()
	local total, unknown = 0, 0
	for _, itemID in ipairs(self:PvPPlan()) do
		local honor = self:PvPCost(itemID)
		local row = { itemID = itemID, honor = honor, known = honor ~= nil }
		if honor then
			total = total + honor
			row.total = total
			row.now = total <= have
			if row.now then
				row.weeks = 0
			elseif income > 0 then
				row.weeks = math.ceil((total - have) / income)
			end
		else
			unknown = unknown + 1
		end
		rows[#rows + 1] = row
	end
	return rows, { total = total, unknown = unknown, have = have, income = income, source = source }
end

-- Color for "weeks to afford": green this week, then yellow, orange, red.
function LG:WeeksColor(weeks)
	if weeks == nil then return E:TokenColor("bad") end
	if weeks <= 0 then return E:TokenColor("good") end
	if weeks <= 2 then return 1, 0.85, 0.2 end
	if weeks <= 5 then return 1, 0.55, 0.2 end
	return E:TokenColor("bad")
end

---------------------------------------------------------------------------
-- Item sets and tokens
---------------------------------------------------------------------------
local RAID_TIER = { mc = "tier", onyxia = "tier", bwl = "tier", aq40 = "aq", naxx = "tier", zg = "zg", aq20 = "aq" }

function LG:ItemSetName(setID, fallbackItem)
	if C_Item and C_Item.GetItemSetInfo then
		local ok, name = pcall(C_Item.GetItemSetInfo, setID)
		if ok and type(name) == "string" and not Secret(name) and name ~= "" then return name end
	end
	local setInfo = rawget(_G, "GetItemSetInfo")
	if setInfo then
		local ok, name = pcall(setInfo, setID)
		if ok and type(name) == "string" and not Secret(name) and name ~= "" then return name end
	end
	local record = fallbackItem and self:ItemRecord(fallbackItem)
	return record and ((L["Set of %s"]):format(record.name)) or ((L["Item set %d"]):format(setID))
end

-- Which group a set is in: "tier", "dungeon", "zg", "aq", "pvp", "other".
local function SetGroup(pieces)
	local group = "other"
	for _, itemID in ipairs(pieces) do
		local record = LG:ItemRecord(itemID)
		if record and record.honorRank and record.honorRank > 0 then return "pvp" end
		for _, source in ipairs(LG:ItemSources(itemID) or {}) do
			local inst = source.instance
			if not inst and source.kind == "token" then
				for _, tokenSource in ipairs(LG:ItemSources(source.id) or {}) do inst = inst or tokenSource.instance end
			end
			if not inst and (source.kind == "quest" or source.kind == "choice") then inst = LG:QuestInstance(source.id) end
			if inst then
				if RAID_TIER[inst] then return RAID_TIER[inst] end
				local info = LG:InstanceInfo(inst)
				if info and info.kind == "dungeon" then group = "dungeon" end
			end
		end
	end
	return group
end

LG.SET_GROUPS = {
	{ key = "tier", title = "Tier sets" }, { key = "dungeon", title = "Dungeon sets" },
	{ key = "zg", title = "Zul'Gurub sets" }, { key = "aq", title = "Ahn'Qiraj sets" },
	{ key = "pvp", title = "PvP sets" }, { key = "other", title = "Other sets" },
}
E:TranslateFields(LG.SET_GROUPS, "title")

-- Every set: { { id, name, pieces = { itemID... }, group, classMask } }.
function LG:ItemSets()
	if indexes.setList then return indexes.setList end
	local list = {}
	for setID, pieces in pairs(ItemIndex().sets) do
		local classMask = 0
		for _, itemID in ipairs(pieces) do
			local record = self:ItemRecord(itemID)
			if record and record.classMask and record.classMask > 0 then classMask = bit.bor(classMask, record.classMask) end
		end
		list[#list + 1] = { id = setID, pieces = pieces, group = SetGroup(pieces), classMask = classMask,
			name = self:ItemSetName(setID, pieces[1]) }
	end
	table.sort(list, function(a, b)
		if a.name ~= b.name then return a.name < b.name end
		return a.id < b.id
	end)
	indexes.setList = list
	return list
end

function LG:SetInfo(setID)
	for _, set in ipairs(self:ItemSets()) do
		if set.id == tonumber(setID) then return set end
	end
end

-- Sets an item belongs to: setID, set.
function LG:SetsOf(itemID)
	local record = self:ItemRecord(itemID)
	local setID = record and record.set
	if not setID or setID == 0 then return end
	return setID, self:SetInfo(setID)
end

-- Pieces you own of a set.
function LG:SetOwned(set)
	local count = 0
	for _, itemID in ipairs(set and set.pieces or {}) do
		if self:Owns(itemID) then count = count + 1 end
	end
	return count
end

-- Bonuses read from a piece's own tooltip (the client's text; read-only):
-- { { count, text } }. Cached per set.
local bonusCache = {}
function LG:SetBonuses(setID)
	setID = tonumber(setID)
	if bonusCache[setID] then return bonusCache[setID] end
	local set = self:SetInfo(setID)
	local out = {}
	local info = C_TooltipInfo
	if set and info and info.GetItemByID then
		for _, itemID in ipairs(set.pieces) do
			local ok, data = pcall(info.GetItemByID, itemID)
			if ok and type(data) == "table" and type(data.lines) == "table" then
				for _, line in ipairs(data.lines) do
					local text = Plain(line.leftText)
					if type(text) == "string" then
						local count, rest = text:match("^%((%d+)%)%s*(.+)$")
						if count and rest then out[#out + 1] = { count = tonumber(count), text = rest } end
					end
				end
				if #out > 0 then break end
			end
		end
	end
	table.sort(out, function(a, b) return a.count < b.count end)
	if #out > 0 then bonusCache[setID] = out end
	return out
end

-- Token items: { tokenItemID, ... } sorted by name.
function LG:TokenList()
	if indexes.tokens then return indexes.tokens end
	local data = LD()
	local list = {}
	for tokenID in pairs(data and data.tokens or {}) do list[#list + 1] = tokenID end
	table.sort(list, function(a, b)
		local ra, rb = self:ItemRecord(a), self:ItemRecord(b)
		local na, nb = ra and ra.name or "", rb and rb.name or ""
		if na ~= nb then return na < nb end
		return a < b
	end)
	indexes.tokens = list
	return list
end

-- Token rewards for a class (classID nil = yours, 0 = any class).
function LG:TokenFor(tokenID, classID)
	local mask = classID == 0 and 0 or bit.lshift(1, (classID or self:Player().classID or 1) - 1)
	local out = {}
	for _, reward in ipairs(self:TokenRewards(tokenID) or {}) do
		if mask == 0 or reward.classMask == 0 or bit.band(reward.classMask, mask) ~= 0 then out[#out + 1] = reward.itemID end
	end
	return out
end

---------------------------------------------------------------------------
-- Collections and learned state
---------------------------------------------------------------------------
LG.COLLECTION_GROUPS = {
	{ key = "mounts", title = "Mounts" }, { key = "pets", title = "Companions" },
	{ key = "tabards", title = "Tabards" }, { key = "legendary", title = "Legendary items" },
	{ key = "epics", title = "World epics" },
}
E:TranslateFields(LG.COLLECTION_GROUPS, "title")

function LG:Collections()
	local index = ItemIndex()
	return { mounts = index.mounts, pets = index.pets, tabards = index.tabards, legendary = index.legendary, epics = index.epics }
end

local learnedCache = {}
LG:On("catalogue-learned", function(changed)
	if changed.learned or changed.bags or changed.data then wipe(learnedCache) end
end)

-- true when the character has learned (mount, companion) or owns
-- (tabard, legendary, world epic) the item; nil when the client cannot say.
function LG:IsLearned(itemID)
	itemID = tonumber(itemID)
	if not itemID then return end
	if learnedCache[itemID] ~= nil then return learnedCache[itemID] or nil end
	local record = self:ItemRecord(itemID)
	local learned
	if record and record.mount and C_MountJournal and C_MountJournal.GetMountFromItem then
		local ok, mountID = pcall(C_MountJournal.GetMountFromItem, itemID)
		mountID = ok and Plain(mountID) or nil
		if mountID and C_MountJournal.GetMountInfoByID then
			local info = { pcall(C_MountJournal.GetMountInfoByID, mountID) }
			if info[1] then learned = Plain(info[12]) and true or false end
		end
	elseif record and record.pet and C_PetJournal and C_PetJournal.GetPetInfoByItemID then
		local info = { pcall(C_PetJournal.GetPetInfoByItemID, itemID) }
		local species = info[1] and Plain(info[14])
		if species and C_PetJournal.GetNumCollectedInfo then
			local ok, owned = pcall(C_PetJournal.GetNumCollectedInfo, species)
			if ok then learned = (tonumber(Plain(owned)) or 0) > 0 end
		end
	end
	if learned == nil and record and (record.mount or record.pet) and C_TooltipInfo and C_TooltipInfo.GetItemByID then
		-- The item's own tooltip says "Already known".
		local known = rawget(_G, "ITEM_SPELL_KNOWN")
		local ok, data = pcall(C_TooltipInfo.GetItemByID, itemID)
		if ok and type(data) == "table" and type(known) == "string" then
			learned = false
			for _, line in ipairs(data.lines or {}) do
				if Plain(line.leftText) == known then learned = true break end
			end
		end
	end
	if learned == nil then learned = self:Owns(itemID) ~= nil end
	learnedCache[itemID] = learned and true or false
	return learned
end

for _, event in ipairs({ "NEW_MOUNT_ADDED", "COMPANION_LEARNED", "NEW_PET_ADDED", "COMPANION_UPDATE" }) do
	LG:Listen(event, "learned", function() LG:Fire("learned") end)
end

---------------------------------------------------------------------------
-- World events
---------------------------------------------------------------------------
-- Is the event on today? true / false from the calendar, nil when the
-- client has no calendar (the chip hides).
-- Is a calendar entry this event? The holiday ID first, which reads the
-- same in every client language (each Faire location has its own); on an
-- English client the title too, the whole name, so a plain "Darkmoon
-- Faire" never lights both locations.
local englishClient = (GetLocale and GetLocale() or "enUS"):sub(1, 2) == "en"
local function IsEvent(event, info)
	if type(info) ~= "table" then return false end
	local id = tonumber(Plain(info.eventID))
	if event.holiday and Plain(info.calendarType) == "HOLIDAY" and id == event.holiday then return true end
	if not englishClient then return false end
	local title = Plain(info.title)
	if type(title) ~= "string" then return false end
	local folded = LG:Fold(title)
	return folded ~= "" and folded:find(LG:Fold(event.name), 1, true) ~= nil
end

local function CalendarDay()
	local now = C_DateAndTime and C_DateAndTime.GetCurrentCalendarTime and C_DateAndTime.GetCurrentCalendarTime()
	return type(now) == "table" and now or nil
end

-- True when the game's calendar has the event today, false when it has
-- not, nil without a calendar.
function LG:EventActive(event)
	local cal = rawget(_G, "C_Calendar")
	if not (cal and cal.GetNumDayEvents and cal.GetDayEvent and event and event.name) then return end
	local now = CalendarDay()
	local day = now and Plain(now.monthDay)
	if not day then return end
	local ok, count = pcall(cal.GetNumDayEvents, 0, day)
	count = ok and tonumber(Plain(count)) or 0
	for index = 1, count do
		local fine, info = pcall(cal.GetDayEvent, 0, day, index)
		if fine and IsEvent(event, info) then return true end
	end
	return false
end

-- When the event next starts, from the calendar of this month and the
-- next: a Unix time, or nil when neither month lists it.
function LG:EventNext(event)
	local cal = rawget(_G, "C_Calendar")
	local minutesOf = E.Characters and E.Characters.CalendarMinutes
	if not (cal and cal.GetNumDayEvents and cal.GetDayEvent and cal.GetMonthInfo and minutesOf and event) then return end
	local now = CalendarDay()
	local nowMinutes = now and minutesOf(now)
	if not nowMinutes then return end
	for offset = 0, 1 do
		local ok, month = pcall(cal.GetMonthInfo, offset)
		local days = ok and type(month) == "table" and tonumber(Plain(month.numDays)) or 0
		for day = offset == 0 and Plain(now.monthDay) or 1, days do
			local fine, count = pcall(cal.GetNumDayEvents, offset, day)
			for index = 1, fine and tonumber(Plain(count)) or 0 do
				local got, info = pcall(cal.GetDayEvent, offset, day, index)
				if got and IsEvent(event, info) then
					local start = minutesOf(info.startTime)
					if start and start > nowMinutes then return time() + (start - nowMinutes) * 60 end
				end
			end
		end
	end
end

-- Items of an event: vendors' goods, quest rewards and its mobs' drops.
-- { vendors = { { npc, items = { itemID... } } }, quests = { { questID, items } }, mobs = { { npc, items } } }
function LG:EventItems(event)
	local out = { vendors = {}, quests = {}, mobs = {} }
	if not event then return out end
	for _, npc in ipairs(event.vendors or {}) do
		local items = {}
		for itemID in pairs(self:VendorItems(npc) or {}) do items[#items + 1] = itemID end
		table.sort(items)
		if #items > 0 then out.vendors[#out.vendors + 1] = { npc = npc, items = items } end
	end
	for _, questID in ipairs(event.quests or {}) do
		local quest = self:Quest(questID)
		local items = {}
		for _, pair in ipairs(quest and quest.rewards or {}) do items[#items + 1] = pair.id or pair[1] end
		for _, pair in ipairs(quest and quest.choice or {}) do items[#items + 1] = pair.id or pair[1] end
		out.quests[#out.quests + 1] = { questID = questID, items = items }
	end
	local extra = self.FOREVER_EVENT_EXTRAS and self.FOREVER_EVENT_EXTRAS[event.id]
	if extra then out.vendors[#out.vendors + 1] = { npc = extra.npc, items = extra.items } end
	local data = LD()
	for _, npc in ipairs(event.mobs or {}) do
		local items = {}
		for item in tostring(data and data.loot and data.loot[npc] or ""):gmatch("(%d+):") do items[#items + 1] = tonumber(item) end
		if #items > 0 then out.mobs[#out.mobs + 1] = { npc = npc, items = items } end
	end
	return out
end
