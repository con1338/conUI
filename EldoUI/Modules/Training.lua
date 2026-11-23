-- EldoUI Training: what your class trainer can teach you, now and later.
--
-- A list of every class spell the trainer teaches on WoW: Forever, grouped
-- by what you can do about it:
--   Available now        you have the level and the earlier rank
--   Needs another spell  you have the level but miss an earlier rank
--   Upcoming             what opens at later levels, by level, dimmed,
--                        the level it needs in red
--   Pet training, Needs a talent
--   Ignored, Known       at the bottom, with what they saved or cost
-- Each row has its rank, level and cost (with your best reputation discount
-- when you want it), each group its total, and the tooltip says where to
-- learn it. Right-click ignores a spell (per character), Shift-click links
-- it. A second tab lists weapon skills and the weapon masters who teach
-- them; clicking one puts a map pin on the nearest master. Hunters see the
-- Beast Training abilities, warlocks the demon grimoires. Hunters also get
-- a Pet abilities tab (Modules/TrainingPets.lua): every pet ability rank,
-- what the pet out can learn now and which beasts to tame for the rest.
--
-- Where it shows:
--   - its own window (/eui training, the info bar block "Training", the
--     addon compartment), which works without the spellbook
--   - a "Training" tab under Blizzard's spellbook (PlayerSpellsFrame), and
--     for Hunters a "Pet abilities" tab beside it, only while "Let EldoUI
--     change this" and "Improve" are on for the element "Spellbook and
--     talents" under Blizzard UI
--   - the trainer list beside Blizzard's trainer window (Modules/Skins.lua)
--     leaves out ignored spells, through E:IsTrainingIgnored
--
-- Information only. It never trains, buys or casts anything; the map pin is
-- set on your click. Nothing here reads combat data.
--
-- The spell data (Data/Training) and the way spells are sorted into groups,
-- ranks are matched and reputation discounts are applied are adapted from
-- What's Training? (https://github.com/fusionpit/WhatsTraining, branch
-- forever, commit b5a5a74) under the MIT License, Copyright (c) 2019. The
-- full license text is at the top of Data/Training/Shared.lua (credited in
-- THIRD_PARTY_NOTICES.md). The window, spellbook tab, info bar block and
-- everything EldoUI-specific are written for EldoUI.
local _, E = ...
local L = E.L
local Key = E.Key
local D = E.TrainingData

local M = E:NewModule("Training", {
	title = "Training",
	category = "Quality of Life",
	desc = "What your class trainer can teach you now and later, with costs, totals, an ignore list, weapon skills and pet training. Its own window, a spellbook tab and an info bar block.",
	conflicts = { "WhatsTraining" },
	frames = { "EldoUI_Training" },
	movers = { "EldoUI_TrainingWindow" },
	-- The Talent Planner owns "Spellbook and talents"; the tab joins its
	-- hook list.
	blizzard = { "player-spells" },
	savedKeys = { "profile.modules.Training", "private.training" },
	optionsPage = "module:Training",
	presets = { "Compact", "Focus", "Glass", "Large", "Ledger", "Standard" },
	reload = false,
	defaults = {
		spellbookTab = true,     -- "Training" tab under the spellbook (needs Improve)
		showKnown = true,         -- known spells at the bottom
		showIgnored = true,       -- ignored spells above them
		showLater = true,         -- Upcoming lists every later level, not only soonLevels
		soonLevels = 2,           -- Upcoming always reaches this many levels ahead
		showKnownWeapons = false, -- known weapon skills on the Weapons tab
		petAllFamilies = false,   -- Pet abilities: every family, not only your pet's
		priceMode = "best",       -- "base" or "best" (cheapest reputation discount)
		datatextFormat = "countCost",
		slashWT = true,           -- also /wt
		compartment = true,       -- entry in the addon compartment
		-- Look
		fontSize = 12,
		rowHeight = 20,
		width = 380,
		height = 480,
		-- Size while joined to the spellbook (false: its own width, the
		-- spellbook's height).
		dockWidth = false,
		dockHeight = false,
		scale = 1,
		showIcons = true,
		semanticHeaders = true,   -- headers in the game's meaning colors, else accent
		stripes = true,
		transparent = false,
		-- Window state
		tab = "spells",
		collapsed = {},
	},
})

-- Per character: what you ignored and the pet training the game only shows
-- at the trainer.
E:RegisterPrivate("training", {
	ignored = {},     -- spellID or "tome:<id>" -> true
	petLearned = {},  -- hunter pet ability spellID or "tome:<id>" -> true
	petScanned = false, -- Hunters: Beast Training was open once
	demon = false,    -- the demon last summoned (warlocks)
	trainers = {},    -- class trainers you opened: name -> { map, x, y (0-100), class, portal }
	ridingCost = {},  -- riding spellID -> the cost a riding trainer asked (copper)
})

local floor, max, min = math.floor, math.max, math.min
local MOVER = "EldoUI_TrainingWindow"
local ELEMENT = "player-spells"
local QUEST_MARK = "|A:SmallQuestBang:14:14|a"

-- Game globals that may not exist on every client: read without warnings.
local function G(name)
	return rawget(_G, name)
end

local function Store()
	return E:GetPrivate("training") or { ignored = {}, petLearned = {} }
end

local IsSecret = E.Secret

local function Try(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a, b, c = pcall(fn, ...)
	if ok then return a, b, c end
end

local function Coins(copper)
	return E:FormatMoney(floor(copper or 0))
end

local function Hex(color, fallback)
	if type(color) == "table" and color.GenerateHexColorMarkup then return color:GenerateHexColorMarkup() end
	return fallback
end

local function AccentHex()
	local r, g, b = unpack(E.media.accentText)
	return ("|cff%02x%02x%02x"):format(r * 255, g * 255, b * 255)
end

local GREY = E:TextHex("secondary")

-- Demon family names: Data/Training keys on the English name, the list
-- shows it in the player's language.
local FAMILY_NAMES = E:TranslateValues({
	Imp = E.Key("Imp"), Voidwalker = E.Key("Voidwalker"), Succubus = E.Key("Succubus"),
	Incubus = E.Key("Incubus"), Felhunter = E.Key("Felhunter"),
})

local function FamilyName(family)
	return FAMILY_NAMES[family] or family or ""
end

---------------------------------------------------------------------------
-- Groups. Colors are the game's meaning colors (DESIGN.md §2); with
-- "Colored headers" off they all use the accent.
---------------------------------------------------------------------------
local CATEGORIES = {
	spells = {
		{ key = "available", title = "Available now", color = function() return Hex(G("GREEN_FONT_COLOR"), E:TextHex("good")) end },
		{ key = "upcoming", title = "Upcoming", color = function() return Hex(G("LIGHTBLUE_FONT_COLOR"), E:TextHex("accent")) end, showLevel = true, upcoming = true },
		{ key = "missing", title = "Needs another spell first", color = function() return Hex(G("ORANGE_FONT_COLOR"), E:TextHex("warn")) end, showLevel = false },
		{ key = "pet", title = "Pet training", color = function() return "|cffffffff" end, showLevel = true },
		{ key = "talent", title = "Needs a talent", color = function() return "|cffffffff" end, showLevel = true },
		{ key = "ignored", title = "Ignored", color = function() return Hex(G("LIGHTYELLOW_FONT_COLOR"), E:TextHex("gold")) end, option = "showIgnored", totalLabel = Key("saved %s"), byName = true },
		{ key = "known", title = "Known", color = function() return Hex(G("GRAY_FONT_COLOR"), E:TextHex("secondary")) end, option = "showKnown", totalLabel = Key("spent %s"), byName = true },
	},
	weapons = {
		{ key = "available", title = "Available now", color = function() return Hex(G("GREEN_FONT_COLOR"), E:TextHex("good")) end },
		{ key = "upcoming", title = "Upcoming", color = function() return Hex(G("LIGHTBLUE_FONT_COLOR"), E:TextHex("accent")) end, showLevel = true, upcoming = true },
		{ key = "ignored", title = "Ignored", color = function() return Hex(G("LIGHTYELLOW_FONT_COLOR"), E:TextHex("gold")) end, option = "showIgnored", totalLabel = Key("saved %s") },
		{ key = "known", title = "Known", color = function() return Hex(G("GRAY_FONT_COLOR"), E:TextHex("secondary")) end, option = "showKnownWeapons", totalLabel = Key("spent %s") },
	},
}

---------------------------------------------------------------------------
-- The catalog: every spell, grimoire and weapon skill this character's
-- trainers teach, built once per session from Data/Training.
---------------------------------------------------------------------------
local catalog            -- { spells = { entry, ... }, weapons = { entry, ... }, byKey = {} }
local overrides = {}     -- spellID -> list of ranks that replace each other
local classToken, playerFaction, playerRace

-- Riding: Apprentice at 40 and Journeyman at 60, taught by the riding
-- trainers of every race (skill line 762 in the client's tables, build
-- 1.60.1.70862). The cost a trainer asks replaces the fallback here.
local RIDING = {
	{ id = 33388, level = 40, cost = 1000000 },                      -- Apprentice Riding, 100 g
	{ id = 33391, level = 60, cost = 10000000, requires = { 33388 } }, -- Journeyman Riding, 1,000 g
}
M.RIDING = RIDING

local function RaceAllowed(spell)
	if spell.race == nil and spell.races == nil then return true end
	if spell.races then return tContains(spell.races, playerRace) end
	return spell.race == playerRace
end

local function BuildCatalog()
	classToken = select(2, UnitClass("player"))
	playerFaction = UnitFactionGroup("player")
	playerRace = select(3, UnitRace("player"))
	catalog = { spells = {}, weapons = {}, byKey = {}, byName = {} }
	wipe(overrides)
	if not D or not classToken then return catalog end

	local make = D.classes[classToken]
	local data = make and make() or { spells = {} }
	for _, ranks in ipairs(data.overrides or {}) do
		for _, id in ipairs(ranks) do overrides[id] = ranks end
	end

	local function Add(list, entry)
		if catalog.byKey[entry.key] then return end
		list[#list + 1] = entry
		catalog.byKey[entry.key] = entry
	end
	local petAbilities = classToken == "HUNTER" and D.hunterPetAbilities or {}
	for level, spells in pairs(data.spells or {}) do
		for _, spell in ipairs(spells) do
			if (spell.faction == nil or spell.faction == playerFaction) and RaceAllowed(spell) then
				Add(catalog.spells, {
					kind = petAbilities[spell.id] and "pet" or "spell",
					id = spell.id, key = spell.id, cost = spell.cost or 0, level = level,
					requiredIds = spell.requiredIds, requiredTalentId = spell.requiredTalentId,
				})
			end
		end
	end
	-- Class quest rewards for this race (first matching entry wins).
	for id, entries in pairs(D.questSpells and D.questSpells[classToken] or {}) do
		for _, quest in ipairs(entries) do
			if playerRace and tContains(quest.races, playerRace) then
				Add(catalog.spells, { kind = "spell", id = id, key = id, cost = 0, level = quest.level,
					quest = quest.areas or { quest.area } })
				break
			end
		end
	end
	-- Riding, for every class.
	local seen = type(Store().ridingCost) == "table" and Store().ridingCost or {}
	for _, riding in ipairs(RIDING) do
		local cost = tonumber(seen[riding.id]) or riding.cost
		Add(catalog.spells, { kind = "riding", id = riding.id, key = riding.id, cost = cost, level = riding.level, requiredIds = riding.requires })
	end
	-- Warlock grimoires.
	if classToken == "WARLOCK" and D.warlockTomes then
		for level, tomes in pairs(D.warlockTomes) do
			for _, tome in ipairs(tomes) do
				local id = tome.id or tome.itemId
				Add(catalog.spells, { kind = "tome", id = D.warlockTomeSpells[tome.itemId], itemId = tome.itemId,
					key = "tome:" .. id, cost = tome.cost or 0, level = level, family = tome.family,
					shared = tome.id ~= nil })
			end
		end
	end
	-- Weapon skills this class can learn.
	for id, weapon in pairs(D.weapons or {}) do
		if weapon.classes[classToken] then
			Add(catalog.weapons, { kind = "weapon", id = id, key = id, cost = weapon.cost, level = weapon.level,
				order = weapon.order, trainers = weapon.trainers[playerFaction] or {} })
		end
	end
	return catalog
end

-- The catalog for the class you play (built again if that ever changes).
local function Catalog()
	if not catalog or select(2, UnitClass("player")) ~= classToken then catalog = BuildCatalog() end
	return catalog
end

---------------------------------------------------------------------------
-- Names, ranks and icons. Spell and item data can arrive a moment after we
-- ask (SPELL_DATA_LOAD_RESULT / ITEM_DATA_LOAD_RESULT); our own event
-- handler rebuilds then, without Blizzard's shared load listeners.
---------------------------------------------------------------------------
local spellCache, itemCache = {}, {}
local pendingSpells, pendingItems = {}, {}

local ROMAN = { I = 1, V = 5, X = 10 }
local function RomanToNumber(numeral)
	local total, previous = 0, 0
	for i = #numeral, 1, -1 do
		local value = ROMAN[numeral:sub(i, i)]
		total = value < previous and total - value or total + value
		previous = value
	end
	return total
end

-- "Instant Poison II" with "Rank 2" reads "Instant Poison" plus the rank.
local function StripRankNumeral(name, rank)
	local base, numeral = name:match("^(.-)%s+([IVX]+)$")
	local number = rank and rank:match("%d+")
	if base and number and RomanToNumber(numeral) == tonumber(number) then return base end
	return name
end

local function SpellData(id)
	if not id then return nil end
	local cached = spellCache[id]
	if cached and cached.rank ~= nil then return cached end
	local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
	if not name then
		if not pendingSpells[id] and C_Spell and C_Spell.RequestLoadSpellData then
			pendingSpells[id] = true
			Try(C_Spell.RequestLoadSpellData, id)
		end
		return cached
	end
	local rank = C_Spell.GetSpellSubtext and C_Spell.GetSpellSubtext(id)
	if rank == "" then rank = false end
	cached = cached or {}
	cached.rawName = name
	cached.rank = rank
	cached.name = StripRankNumeral(name, rank or nil)
	cached.icon = C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id)
	-- An empty name is not an answer yet: ask again next time.
	if name ~= "" then spellCache[id] = cached end
	return cached
end

local function ItemData(itemID)
	local cached = itemCache[itemID]
	if cached then return cached end
	local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID)
	if not name then
		if not pendingItems[itemID] and C_Item and C_Item.RequestLoadItemDataByID then
			pendingItems[itemID] = true
			Try(C_Item.RequestLoadItemDataByID, itemID)
		end
		return nil
	end
	-- "Grimoire of Firebolt (Rank 2)": the rank comes from the taught spell.
	cached = { name = (name:gsub("%s*%(.+%)$", "")), icon = C_Item.GetItemIconByID and C_Item.GetItemIconByID(itemID) }
	itemCache[itemID] = cached
	return cached
end

-- Display name, rank text and icon of an entry (nil while still loading).
local function Describe(entry)
	if entry.kind == "tome" then
		local item = ItemData(entry.itemId)
		local spell = SpellData(entry.id)
		if not item then return nil end
		return item.name, spell and spell.rank or nil, item.icon
	end
	local spell = SpellData(entry.id)
	if not spell then return nil end
	return spell.name, spell.rank or nil, spell.icon
end

---------------------------------------------------------------------------
-- What you know
---------------------------------------------------------------------------
local function Bank(name)
	return Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank[name]
end

local function SpellKnown(id)
	if not id or not C_SpellBook then return false end
	local bank = Bank("Player")
	if C_SpellBook.IsSpellInSpellBook and C_SpellBook.IsSpellInSpellBook(id, bank, false) then return true end
	return C_SpellBook.IsSpellKnown and C_SpellBook.IsSpellKnown(id, bank) or false
end

-- Warrior, rogue and druid ranks replace each other in the spellbook, so a
-- higher known rank means the lower ones are known too.
local function KnownByLaterRank(id)
	local ranks = overrides[id]
	if not ranks then return false end
	local mine
	for index, other in ipairs(ranks) do
		if other == id then mine = index end
	end
	for index = (mine or #ranks) + 1, #ranks do
		if SpellKnown(ranks[index]) then return true end
	end
	return false
end

local function KnowsSpell(id)
	return SpellKnown(id) or KnownByLaterRank(id)
end

local function IsKnown(entry)
	if entry.kind == "tome" then return Store().petLearned[entry.key] == true end
	if entry.kind == "pet" and Store().petLearned[entry.id] then return true end
	return KnowsSpell(entry.id)
end

local function IsIgnored(entry)
	return Store().ignored[entry.key] == true
end

---------------------------------------------------------------------------
-- Prices. Forever's trainers take 10% off from Honored with the city that
-- trains you (What's Training?'s table of which reputation trains what).
-- Grimoire vendors charge full price.
---------------------------------------------------------------------------
local reputations = {}

local function Reputation(id)
	local row = reputations[id]
	if row then return row end
	local data = C_Reputation and C_Reputation.GetFactionDataByID and Try(C_Reputation.GetFactionDataByID, id)
	local reaction = type(data) == "table" and data.reaction or 4
	if IsSecret(reaction) or type(reaction) ~= "number" then reaction = 4 end
	local info = D.trainerFactions.factions[id] or {}
	row = {
		id = id,
		name = type(data) == "table" and data.name or L["Faction %d"]:format(id),
		reaction = reaction,
		pct = reaction >= 6 and 10 or 0,
		city = info.city,
	}
	reputations[id] = row
	return row
end

local function TrainingFactions(entry)
	local roles = D.trainerFactions.roles
	if entry.kind == "weapon" then
		local list, seen = {}, {}
		for _, trainer in ipairs(entry.trainers) do
			local id = D.trainerFactions.npcs[trainer.npc]
			if id and not seen[id] then
				list[#list + 1] = id
				seen[id] = true
			end
		end
		return list
	elseif entry.kind == "tome" or entry.kind == "riding" then
		return {}
	end
	local role = roles[entry.kind == "pet" and "PET" or classToken]
	return role and role[playerFaction] or {}
end

local function Discounted(cost, pct)
	return floor((cost * (100 - pct) + 50) / 100)
end

local function Price(entry)
	local cost = entry.cost or 0
	if cost == 0 or M.db.priceMode ~= "best" then return cost end
	local best = cost
	for _, id in ipairs(TrainingFactions(entry)) do
		best = min(best, Discounted(cost, Reputation(id).pct))
	end
	return best
end

---------------------------------------------------------------------------
-- Sorting into groups
---------------------------------------------------------------------------
local view = { spells = {}, weapons = {}, totals = {} }
local frame
E.Training = M

-- Read-only counts for other pages (the journal's Today and level-up page):
-- { count, cost, weaponCount, weaponCost, soon } from the last rebuild.
function M:Totals()
	local t = view.totals or {}
	return { count = t.count or 0, cost = t.cost or 0, weaponCount = t.weaponCount or 0,
		weaponCost = t.weaponCost or 0, soon = t.soon or 0 }
end
local filter = ""
local playerLevel = 1
local watchedSpells = {}

-- Sorts an entry into its group. Upcoming entries more than `soon` levels
-- away are marked `far`: they show while "All later levels" is on.
local function Classify(entry, level, soon)
	entry.far = nil
	if IsKnown(entry) then return "known" end
	if IsIgnored(entry) then return "ignored" end
	local function Upcoming()
		entry.far = entry.level > level + soon or nil
		return "upcoming"
	end
	if entry.kind == "weapon" then
		if entry.level > level then return Upcoming() end
		return "available"
	end
	if entry.kind == "tome" or entry.kind == "pet" then
		if entry.level > level + soon then return Upcoming() end
		return "pet"
	end
	if entry.requiredTalentId and not KnowsSpell(entry.requiredTalentId) then
		return "talent"
	end
	if entry.level > level then return Upcoming() end
	for _, id in ipairs(entry.requiredIds or {}) do
		if not KnowsSpell(id) then return "missing" end
	end
	return "available"
end

local function ByLevel(a, b)
	if a.level ~= b.level then return a.level < b.level end
	if (a.quest == nil) ~= (b.quest == nil) then return b.quest ~= nil end
	if a.name ~= b.name then return a.name < b.name end
	return tostring(a.key) < tostring(b.key)
end

local function ByName(a, b)
	if a.name ~= b.name then return a.name < b.name end
	if a.level ~= b.level then return a.level < b.level end
	return tostring(a.key) < tostring(b.key)
end

local function ByWeapon(a, b)
	if a.order ~= b.order then return (a.order or 99) < (b.order or 99) end
	return ByLevel(a, b)
end

local function WatchSpell(id)
	if watchedSpells[id] == nil then watchedSpells[id] = KnowsSpell(id) end
end

-- Learnable spells and the prerequisites that can change their groups.
-- Weapon skills can change when the skill lines change, too.
local function WatchEntry(entry, category)
	if entry.requiredTalentId then
		WatchSpell(entry.requiredTalentId)
		WatchSpell(entry.id)
	end
	if category == "available" or category == "missing" or category == "ignored"
		or (entry.kind == "weapon" and category == "known") then
		if entry.kind == "tome" then return end
		watchedSpells[entry.id] = category == "known"
		for _, id in ipairs(entry.requiredIds or {}) do WatchSpell(id) end
	end
end

local function SpellbookChanged()
	for id, known in pairs(watchedSpells) do
		if KnowsSpell(id) ~= known then return true end
	end
	return false
end

-- Groups for one tab: { def, entries = { entry, ... } } with names filled.
local function Group(list, defs, level, soon, weapons)
	local groups, index = {}, {}
	for _, def in ipairs(defs) do
		local group = { def = def, entries = {} }
		groups[#groups + 1] = group
		index[def.key] = group
	end
	for _, entry in ipairs(list) do
		local name, rank, icon = Describe(entry)
		if name then
			entry.name, entry.rank, entry.icon = name, rank, icon
			entry.search = (name .. " " .. (rank or "")):lower()
			entry.category = Classify(entry, level, soon)
			WatchEntry(entry, entry.category)
			local group = index[entry.category]
			if group then group.entries[#group.entries + 1] = entry end
		end
	end
	for _, group in ipairs(groups) do
		local sorter = weapons and ByWeapon or (group.def.byName and ByName or ByLevel)
		table.sort(group.entries, sorter)
	end
	return groups
end

local function UpdateTotals()
	-- Totals for the info bar and the footer: class spells you can learn now.
	local count, cost = 0, 0
	-- Riding is a riding trainer's, not the class trainer's.
	for _, entry in ipairs(view.spells[1].entries) do
		if entry.kind ~= "riding" then
			count = count + 1
			cost = cost + Price(entry)
		end
	end
	local weaponCount, weaponCost = 0, 0
	for _, entry in ipairs(view.weapons[1].entries) do
		weaponCount = weaponCount + 1
		weaponCost = weaponCost + Price(entry)
	end
	-- "soon": upcoming spells within the Upcoming reach (the journal's pages).
	local soonCount = 0
	for _, entry in ipairs(view.spells[2].entries) do
		if not entry.far then soonCount = soonCount + 1 end
	end
	view.totals = { count = count, cost = cost, weaponCount = weaponCount, weaponCost = weaponCost,
		soon = soonCount }
end

function M:Rebuild(level)
	if not self.active then return end
	catalog = Catalog()
	playerLevel = level or UnitLevel("player") or 1
	if IsSecret(playerLevel) then playerLevel = 1 end
	local soon = self.db.soonLevels or 2
	wipe(watchedSpells)
	view.spells = Group(catalog.spells, CATEGORIES.spells, playerLevel, soon, false)
	view.weapons = Group(catalog.weapons, CATEGORIES.weapons, playerLevel, soon, true)
	view.pets = self:BuildPets()
	self.petView = view.pets -- tests and diagnostics
	UpdateTotals()
	self:Render()
	self:RefreshDataText()
end

-- Hunters: the Pet abilities list (Modules/TrainingPets.lua), with names
-- filled; nil for other classes.
local function PetsShown()
	local pets = E.TrainingPets
	return classToken == "HUNTER" and pets ~= nil and pets:Available()
end

local PET_TONES = { good = "good", warn = "warn", accent = "accent", gold = "gold", body = "body", secondary = "secondary" }
function M:BuildPets()
	if not PetsShown() then return nil end
	local built = E.TrainingPets:Build(Store().petLearned, self.db.petAllFamilies)
	for _, group in ipairs(built.groups) do
		local def = group.def
		if not def.color then
			local tone = PET_TONES[def.tone] or "body"
			def.color = function() return E:TextHex(tone) end
		end
		local named = {}
		for _, entry in ipairs(group.entries) do
			local name, rank, icon = Describe(entry)
			if name then
				entry.name, entry.rank, entry.icon = name, rank, icon
				entry.search = (name .. " " .. (rank or "")):lower()
				named[#named + 1] = entry
			end
		end
		group.entries = named
	end
	return built
end

-- Wait for bursts of events to settle. A rebuild also prices and paints the
-- current groups, so it covers any narrower updates queued alongside it.
local updates, updateTimer = {}, nil
local function ScheduleUpdate()
	if updateTimer or InCombatLockdown() then return end
	updateTimer = C_Timer.NewTimer(0.3, function()
		updateTimer = nil
		if InCombatLockdown() then return end
		local due = updates
		updates = {}
		if due.rebuild or (due.spellbook and SpellbookChanged()) then
			M:Rebuild(type(due.rebuild) == "number" and due.rebuild or nil)
			return
		end
		if due.prices then
			UpdateTotals()
			M:RefreshDataText()
		end
		if (due.prices or due.money) and frame and frame:IsVisible() then M:Render() end
	end)
end

local function QueueUpdate(kind, value)
	if not M.active then return end
	updates[kind] = value or updates[kind] or true
	ScheduleUpdate()
end

function M:QueueRebuild(level)
	QueueUpdate("rebuild", level)
end

-- The lines above the Pet abilities list: the pet that is out, its
-- training points, which families the list shows, and what is missing.
local function PetInfoRows(rows)
	local pets = view.pets
	local pet = pets.pet
	if pet then
		local level = pet.level and L["level %d"]:format(pet.level) or ""
		local family = pet.familyName and (" " .. GREY .. pet.familyName .. "|r") or ""
		rows[#rows + 1] = { info = "pet", text = ("|cffffffff%s|r%s  %s"):format(pet.name or L["Your pet"], family, GREY .. level .. "|r"),
			right = pet.loyalty and (GREY .. pet.loyalty .. "|r") or "" }
		local care = E.TrainingPets
		if pet.happiness then
			local name = G("PET_HAPPINESS" .. pet.happiness) or L["Happiness %d of 3"]:format(pet.happiness)
			local text = pet.damage and L["%s: deals %s damage"]:format(name, ("|cffffffff%d%%|r"):format(pet.damage)) or name
			local rate = pet.loyaltyRate
			local right = rate and rate > 0 and (E:TextHex("good") .. L["Loyalty rising"] .. "|r")
				or rate and rate < 0 and (E:TextHex("bad") .. L["Loyalty falling"] .. "|r") or ""
			rows[#rows + 1] = { info = "happiness", text = text, right = right, tip = "happiness" }
		end
		local diet = care and care:DietText(pet.family)
		if diet then rows[#rows + 1] = { info = "diet", text = L["Eats: %s"]:format("|cffffffff" .. diet .. "|r") } end
		local ranks = care and care:LoyaltyRanks() or {}
		if pet.loyaltyRank and #ranks > 0 then
			local text = pet.loyaltyRank < #ranks and L["Next loyalty rank: %s"]:format("|cffffffff" .. ranks[pet.loyaltyRank + 1] .. "|r")
				or L["%s is the highest loyalty rank."]:format(ranks[#ranks])
			rows[#rows + 1] = { info = "loyalty", text = text, right = GREY .. ("%d / %d"):format(pet.loyaltyRank, #ranks) .. "|r", tip = "loyalty" }
		end
		if pet.xp then
			local Number = BreakUpLargeNumbers or tostring
			rows[#rows + 1] = { info = "xp", text = L["Experience: %s / %s"]:format("|cffffffff" .. Number(pet.xp) .. "|r", Number(pet.xpMax)),
				right = GREY .. ("%d%%"):format(math.floor(pet.xp / pet.xpMax * 100)) .. "|r" }
		end
		if pet.free then
			local free = pet.free < 0 and (E:TextHex("bad") .. pet.free .. "|r") or ("|cffffffff" .. pet.free .. "|r")
			rows[#rows + 1] = { info = "points", text = L["Training points: %s free of %d"]:format(free, pet.total) }
		end
		if pet.speed then
			-- WoW: Forever keeps a tamed beast's own attack speed, so it is worth seeing.
			rows[#rows + 1] = { info = "speed", text = L["Attacks every %s seconds"]:format(("|cffffffff%.1f|r"):format(pet.speed)) }
		end
		if pet.familyName and E.TrainingPets and D.petAbilities.families[pet.family] then
			rows[#rows + 1] = { info = "family", toggle = true, text = pets.filtered
				and L["Showing what a %s can learn"]:format(pet.familyName) or L["Showing every family"] }
		end
	else
		rows[#rows + 1] = { info = "nopet", text = L["Call your pet to see what it can learn."] }
	end
	if not Store().petScanned then
		rows[#rows + 1] = { info = "scan", text = L["Open Beast Training once so the list knows what you have learned."] }
	end
	if not pets.beasts then
		rows[#rows + 1] = { info = "beasts", load = true, text = L["Click to load the beasts to tame (Loot Guide data)."] }
	end
end

-- Flat rows for the list: headers, family sub-headers and entries.
local function Rows(tab)
	local rows = {}
	local db = M.db
	local groups = view[tab] or {}
	if tab == "pets" then
		if not view.pets then
			rows[1] = { empty = true, text = L["Only Hunters have pets to train."] }
			return rows
		end
		PetInfoRows(rows)
		groups = view.pets.groups
	end
	for _, group in ipairs(groups) do
		local def = group.def
		if not def.option or db[def.option] then
			local shown, total = {}, 0
			for _, entry in ipairs(group.entries) do
				if (filter == "" or entry.search:find(filter, 1, true)) and not (entry.far and not db.showLater) then
					shown[#shown + 1] = entry
					total = total + Price(entry)
				end
			end
			if #shown > 0 then
				local collapsed = db.collapsed[tab .. ":" .. def.key] and filter == ""
				rows[#rows + 1] = { header = true, def = def, count = #shown, total = total, tab = tab, collapsed = collapsed }
				if not collapsed then
					if def.key == "pet" and classToken == "WARLOCK" then
						-- Grimoires by demon, in the order you get the demons.
						for _, family in ipairs(D.warlockFamilies or {}) do
							local familyRows, familyTotal = {}, 0
							for _, entry in ipairs(shown) do
								if entry.family == family then
									familyRows[#familyRows + 1] = { entry = entry, def = def }
									familyTotal = familyTotal + Price(entry)
								end
							end
							if #familyRows > 0 then
								rows[#rows + 1] = { family = family, total = familyTotal, icon = D.warlockIcons and D.warlockIcons[family] }
								for _, row in ipairs(familyRows) do rows[#rows + 1] = row end
							end
						end
					else
						for _, entry in ipairs(shown) do rows[#rows + 1] = { entry = entry, def = def } end
					end
				end
			end
		end
	end
	local hasEntries = false
	for _, row in ipairs(rows) do
		if row.header or row.entry then hasEntries = true break end
	end
	if not hasEntries then
		rows[#rows + 1] = { empty = true, text = filter ~= "" and L["Nothing matches your search."] or
			(tab == "weapons" and L["No weapon skills left to learn."] or L["Nothing left to learn. Well done."]) }
	end
	return rows
end

---------------------------------------------------------------------------
-- Public hook for the trainer list (Modules/Skins.lua): true when the
-- player ignored this spell here. `spell` is a spellID, or a name with an
-- optional rank text ("Fireball", "Rank 3").
---------------------------------------------------------------------------
function E:IsTrainingIgnored(spell, rank)
	if not (M.active and catalog) then return false end
	local ignored = Store().ignored
	if type(spell) == "number" then return ignored[spell] == true end
	if type(spell) ~= "string" then return false end
	local wanted = StripRankNumeral(spell, rank):lower()
	for _, entry in ipairs(catalog.spells) do
		if ignored[entry.key] and entry.name and entry.name:lower() == wanted
			and (rank == nil or rank == "" or entry.rank == rank) then
			return true
		end
	end
	return false
end

function M:SetIgnored(entry, ignore, allRanks)
	local ignored = Store().ignored
	local function Set(target) ignored[target.key] = ignore or nil end
	Set(entry)
	if allRanks and entry.name then
		for _, other in ipairs(entry.kind == "weapon" and catalog.weapons or catalog.spells) do
			if other.name == entry.name and other.kind == entry.kind and (not ignore or not IsKnown(other)) then Set(other) end
		end
	end
	self:Rebuild()
	-- The trainer list follows at once when it is open.
	local skins = E:GetModule("Skins")
	if skins and skins.active and skins.UpdateTrainerList then Try(skins.UpdateTrainerList, skins) end
end

function M:ClearIgnored()
	local ignored = Store().ignored
	local count = 0
	for key in pairs(ignored) do
		ignored[key] = nil
		count = count + 1
	end
	self:Print(count == 1 and L["1 spell is no longer ignored."] or L["%d spells are no longer ignored."]:format(count))
	self:Rebuild()
end

---------------------------------------------------------------------------
-- Weapon masters: the nearest one, and a map pin on a click
---------------------------------------------------------------------------
local function MasterName(trainer)
	local locale = GetLocale and GetLocale() or "enUS"
	if locale == "enGB" then locale = "enUS" elseif locale == "esMX" then locale = "esES" end
	return trainer.names[locale] or trainer.names.enUS or L["Weapon Master"]
end

local function AreaName(id)
	return C_Map and C_Map.GetAreaInfo and Try(C_Map.GetAreaInfo, id) or L["Area %s"]:format(tostring(id))
end

local function WorldPosition(mapID, x, y)
	if not (C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return nil end
	local continent, position = Try(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(x, y))
	if not continent or type(position) ~= "table" or not position.GetXY then return nil end
	local wx, wy = position:GetXY()
	return continent, wx, wy
end

local function PlayerWorldPosition()
	if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then return nil end
	local map = Try(C_Map.GetBestMapForUnit, "player")
	if IsSecret(map) or not map then return nil end
	local position = Try(C_Map.GetPlayerMapPosition, map, "player")
	if type(position) ~= "table" or not position.GetXY then return nil end
	local x, y = position:GetXY()
	if IsSecret(x) or not x or IsSecret(y) then return nil end
	return WorldPosition(map, x, y)
end

-- The master on your continent closest to you, else the first one.
function M:NearestMaster(entry)
	local trainers = entry.trainers or {}
	if #trainers == 0 then return nil end
	local continent, px, py = PlayerWorldPosition()
	local best, bestDistance
	if continent then
		for _, trainer in ipairs(trainers) do
			local c, x, y = WorldPosition(trainer.uiMapID, trainer.x / 100, trainer.y / 100)
			if c == continent and x then
				local distance = (x - px) ^ 2 + (y - py) ^ 2
				if not bestDistance or distance < bestDistance then best, bestDistance = trainer, distance end
			end
		end
	end
	return best or trainers[1]
end

function M:SetWaypoint(entry)
	local trainer = self:NearestMaster(entry)
	if not trainer or not trainer.uiMapID then return end
	local name, zone = MasterName(trainer), trainer.zoneName or AreaName(trainer.zone)
	local tomtom = rawget(_G, "TomTom")
	if type(tomtom) == "table" and type(tomtom.AddWaypoint) == "function" then
		Try(tomtom.AddWaypoint, tomtom, trainer.uiMapID, trainer.x / 100, trainer.y / 100,
			{ title = name, from = "EldoUI", persistent = false, minimap = true, world = true })
		self:Print(L["TomTom arrow set to %s in %s."]:format(name, zone))
		return
	end
	local mapPoint = G("UiMapPoint")
	if not (C_Map and C_Map.SetUserWaypoint and mapPoint and mapPoint.CreateFromCoordinates)
		or (C_Map.CanSetUserWaypointOnMap and not C_Map.CanSetUserWaypointOnMap(trainer.uiMapID)) then
		self:Print(L["%s is in %s (%.1f, %.1f)."]:format(name, zone, trainer.x, trainer.y))
		return
	end
	local point = mapPoint.CreateFromCoordinates(trainer.uiMapID, trainer.x / 100, trainer.y / 100)
	Try(C_Map.SetUserWaypoint, point)
	if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then Try(C_SuperTrack.SetSuperTrackedUserWaypoint, true) end
	self:Print(L["Map pin set on %s in %s."]:format(name, zone))
end

---------------------------------------------------------------------------
-- The level-up checklist (Talent Planner): what opens at one level
---------------------------------------------------------------------------
-- Class spells and ranks that open at exactly `level`, not known and not
-- ignored, without spells a class quest teaches:
-- { { entry, name, rank, icon, cost, talent = spellID of a needed talent } }.
function M:SpellsAt(level)
	local out = {}
	if not (self.active and type(level) == "number") then return out end
	catalog = Catalog()
	for _, entry in ipairs(catalog.spells) do
		if entry.level == level and (entry.kind == "spell" or entry.kind == "riding") and not entry.quest and not IsKnown(entry) and not IsIgnored(entry) then
			local name, rank, icon = Describe(entry)
			if name then
				local talent = entry.requiredTalentId
				-- talentKnown: the trainer teaches this rank now (no talent
				-- needed, or the player has that talent).
				out[#out + 1] = { entry = entry, name = name, rank = rank, icon = icon, cost = Price(entry), talent = talent,
					talentKnown = not talent or SpellKnown(talent) or KnownByLaterRank(talent) or false }
			end
		end
	end
	table.sort(out, function(a, b)
		if a.name ~= b.name then return a.name < b.name end
		return tostring(a.entry.key) < tostring(b.entry.key)
	end)
	return out
end

-- What your class trainer has for you at `level` (default yours): { count,
-- cost, next }, next being the lowest higher level where a spell or rank
-- opens. Ignored spells and class quest rewards do not count; a rank that
-- needs a talent or an earlier rank you lack waits. Read only.
function M:TrainerSummary(level)
	local out = { count = 0, cost = 0 }
	if not tonumber(level) then
		level = UnitLevel("player")
		if IsSecret(level) then level = nil end
	end
	if not (self.active and type(level) == "number") then return out end
	for _, entry in ipairs(Catalog().spells) do
		if entry.kind == "spell" and not entry.quest and not IsKnown(entry) and not IsIgnored(entry) then
			if entry.level > level then
				if not out.next or entry.level < out.next then out.next = entry.level end
			elseif Classify(entry, level, 0) == "available" then
				out.count = out.count + 1
				out.cost = out.cost + (Price(entry) or 0)
			end
		end
	end
	return out
end

-- The weapon skills weapon master `npc` teaches that you can learn now and
-- do not know yet: { name, ... } in the game's names, sorted.
function M:WeaponsFrom(npc)
	local out = {}
	local level = UnitLevel("player")
	if IsSecret(level) then level = nil end
	if not (self.active and type(npc) == "number" and type(level) == "number") then return out end
	for _, entry in ipairs(Catalog().weapons) do
		for _, trainer in ipairs(entry.trainers or {}) do
			if trainer.npc == npc then
				local name = entry.level <= level and not IsKnown(entry) and not IsIgnored(entry) and Describe(entry)
				if name then out[#out + 1] = name end
				break
			end
		end
	end
	table.sort(out)
	return out
end

-- Your class trainers from the Loot Guide's open data (EldoUI_LootData,
-- npc services marked as class trainers whose title names your class),
-- on your side of the world, plus the class trainers you opened yourself
-- (WoW: Forever's own trainers for its new race and class pairs, which the
-- open data does not have): { { uiMapID, x, y (0-100), names, zoneName } }.
-- portal: a mage's portal trainers instead.
local CLASS_WORDS = {
	WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter", ROGUE = "Rogue", PRIEST = "Priest",
	SHAMAN = "Shaman", MAGE = "Mage", WARLOCK = "Warlock", DRUID = "Druid",
}
local PORTAL_WORD = "Portal"

-- A trainer title that teaches your class: the English word or the game's
-- own class name ("Schamanenlehrer" holds "Schamane").
local function TeachesYou(title, portal)
	if type(title) ~= "string" or IsSecret(title) then return false end
	if portal then return title:find(PORTAL_WORD, 1, true) ~= nil end
	local className, token = UnitClass("player")
	local word = CLASS_WORDS[token or ""]
	if not word or title:find(PORTAL_WORD, 1, true) then return false end
	return title:find(word, 1, true) ~= nil or (type(className) == "string" and not IsSecret(className) and title:find(className, 1, true) ~= nil)
end
M.TeachesYou = TeachesYou

-- The riding ranks as the last rebuild sorted them (read only):
-- { { entry with id, level, cost, category }, ... }.
function M:RidingRanks()
	local out = {}
	for _, entry in ipairs(Catalog().spells) do
		if entry.kind == "riding" then out[#out + 1] = entry end
	end
	table.sort(out, function(x, y) return x.level < y.level end)
	return out
end

-- A riding trainer's list: the cost it asks for each riding rank is kept
-- and replaces the fallback.
function M.ReadRidingCosts()
	local count = Try(GetNumTrainerServices)
	if type(count) ~= "number" or count <= 0 then return false end
	local names = {}
	for _, riding in ipairs(RIDING) do
		local spell = SpellData(riding.id)
		if spell and spell.name then names[spell.name] = riding.id end
	end
	local store, found = Store(), false
	store.ridingCost = type(store.ridingCost) == "table" and store.ridingCost or {}
	for index = 1, count do
		local name = Try(GetTrainerServiceInfo, index)
		local id = type(name) == "string" and not IsSecret(name) and names[name]
		if id then
			local cost = Try(GetTrainerServiceCost, index)
			if type(cost) == "number" and not IsSecret(cost) and cost > 0 then
				if store.ridingCost[id] ~= cost then found = true end
				store.ridingCost[id] = cost
			end
		end
	end
	if found then catalog = nil end
	return found
end

-- Opening a class trainer outside an instance keeps where it stands.
local function RememberTrainer()
	if not (C_Trainer and C_Trainer.GetTrainerType and Enum.TrainerType and C_TooltipInfo and C_TooltipInfo.GetUnit) then return end
	if Try(C_Trainer.GetTrainerType) ~= Enum.TrainerType.General or IsInInstance() then return end
	local name = UnitName("npc")
	local data = Try(C_TooltipInfo.GetUnit, "npc")
	local line = type(data) == "table" and type(data.lines) == "table" and data.lines[2]
	local title = type(line) == "table" and line.leftText
	if IsSecret(name) or type(name) ~= "string" then return end
	local portal = select(2, UnitClass("player")) == "MAGE" and TeachesYou(title, true)
	if not (portal or TeachesYou(title)) then return end
	local map = Try(C_Map.GetBestMapForUnit, "player")
	if IsSecret(map) or type(map) ~= "number" then return end
	local position = Try(C_Map.GetPlayerMapPosition, map, "player")
	if type(position) ~= "table" or not position.GetXY then return end
	local x, y = position:GetXY()
	if IsSecret(x) or IsSecret(y) or not (x and y) then return end
	local store = Store()
	store.trainers = type(store.trainers) == "table" and store.trainers or {}
	store.trainers[name] = { map = map, x = floor(x * 1000 + 0.5) / 10, y = floor(y * 1000 + 0.5) / 10, class = select(2, UnitClass("player")), portal = portal or nil }
end
M.RememberTrainer = RememberTrainer

function M:ClassTrainers(portal)
	local LD = G("EldoUI_LootData")
	local LG = E.LootGuide
	local token = select(2, UnitClass("player"))
	local word = CLASS_WORDS[token or ""]
	if not word then return {} end
	local side = UnitFactionGroup("player")
	if IsSecret(side) then side = nil end
	local out, seen = {}, {}
	for name, spot in pairs(Store().trainers or {}) do
		if type(spot) == "table" and tonumber(spot.map) and (spot.class == nil or spot.class == token)
			and (spot.portal and true or false) == (portal and true or false) then
			seen[name] = true
			out[#out + 1] = { uiMapID = spot.map, x = spot.x, y = spot.y, names = { enUS = name },
				zoneName = LG and LG.MapName and LG:MapName(spot.map) or nil }
		end
	end
	if not (type(LD) == "table" and type(LD.services) == "table" and LG and LG.MapPosition) then return out end
	local zones = E.zoneData and E.zoneData.zones or {}
	for _, text in pairs(LD.services) do
		local kinds, map, camps, name, sub = tostring(text):match("^(%a+)|%d+|(%d+)|([^|]*)|([^|]*)|?(.*)$")
		local teaches = sub and (portal and sub:find(PORTAL_WORD, 1, true) or not portal and sub:find(word, 1, true) and not sub:find(PORTAL_WORD, 1, true))
		if kinds and kinds:find("c", 1, true) and teaches and not seen[name] then
			local x, y = (camps or ""):match("^(%-?[%d%.]+),(%-?[%d%.]+)")
			local uiMapID, px, py = LG:MapPosition({ map = tonumber(map), x = tonumber(x), y = tonumber(y) })
			local zone = uiMapID and zones[uiMapID]
			local zoneSide = type(zone) == "table" and zone.faction
			if uiMapID and px and px >= 0 and px <= 1 and py >= 0 and py <= 1
				and not (side and (zoneSide == "Alliance" or zoneSide == "Horde") and zoneSide ~= side) then
				out[#out + 1] = { uiMapID = uiMapID, x = px * 100, y = py * 100, names = { enUS = name },
					zoneName = LG.MapName and LG:MapName(uiMapID) or nil }
			end
		end
	end
	table.sort(out, function(a, b)
		if a.uiMapID ~= b.uiMapID then return a.uiMapID < b.uiMapID end
		return a.x < b.x
	end)
	return out
end

-- A map pin on your nearest class trainer (portal: portal trainer), on
-- your click. False when the data names none.
function M:SetTrainerWaypoint(portal)
	local trainers = self:ClassTrainers(portal)
	if #trainers == 0 then return false end
	self:SetWaypoint({ trainers = trainers })
	return true
end

---------------------------------------------------------------------------
-- Tooltip
---------------------------------------------------------------------------
local function KnownRankText(entry)
	if entry.kind ~= "spell" or entry.category == "known" or not entry.name then return nil end
	local bestRank, bestNumber, compareID, compareNumber
	local rankNumber = tonumber((entry.rank or ""):match("%d+"))
	for _, other in ipairs(catalog.spells) do
		if other ~= entry and other.kind == "spell" and other.name == entry.name and other.category == "known" then
			local otherRank = tonumber((other.rank or ""):match("%d+"))
			local number = otherRank or other.level
			if not bestNumber or number > bestNumber then bestRank, bestNumber = other.rank, number end
			if rankNumber and otherRank and otherRank < rankNumber and (not compareNumber or otherRank > compareNumber)
				and SpellKnown(other.id) then
				compareID, compareNumber = other.id, otherRank
			end
		end
	end
	return bestRank, compareID
end

local compareTip, compareOwner, compareEntry, compareID
local compareHooks = setmetatable({}, { __mode = "k" })

local function StopComparing()
	if not compareOwner then return end
	compareOwner, compareEntry, compareID = nil, nil, nil
	M:UnregisterEvent("MODIFIER_STATE_CHANGED")
	if compareTip then compareTip:Hide() end
end

local function PositionCompareTip(tooltip, main)
	local ratio = UIParent:GetEffectiveScale() / main:GetEffectiveScale()
	local width = tooltip:GetWidth()
	local right, left = E.PlainCall(main.GetRight, main), E.PlainCall(main.GetLeft, main)
	local gap = 8
	tooltip:ClearAllPoints()
	if right and left then
		local screenRight = (UIParent:GetRight() or UIParent:GetWidth()) * ratio
		local screenLeft = (UIParent:GetLeft() or 0) * ratio
		-- The tooltip remains outside the main tooltip even when both are wide.
		if right + gap + width > screenRight and left - screenLeft > screenRight - right then
			tooltip:SetPoint("TOPRIGHT", main, "TOPLEFT", -gap, 0)
			return
		end
	end
	tooltip:SetPoint("TOPLEFT", main, "TOPRIGHT", gap, 0)
end

function M:OwnsRowTooltip(tooltip)
	return compareOwner ~= nil and tooltip == GameTooltip and tooltip:IsOwned(compareOwner)
end

local function UpdateCompareTooltip()
	if not compareOwner then return end
	local main = GameTooltip
	if not main or E.FrameCheck(main, "IsForbidden") or not main:IsShown() or not M:OwnsRowTooltip(main) or not SpellKnown(compareID) then
		StopComparing()
		return
	end
	if E.PlainCall(IsModifiedClick, "COMPAREITEMS") ~= true then
		if compareTip then compareTip:Hide() end
		return
	end
	if not compareTip then
		compareTip = CreateFrame("GameTooltip", "EldoUI_TrainingCompareTooltip", UIParent, "GameTooltipTemplate")
		compareTip:EnableMouse(false)
		compareTip:SetClampedToScreen(false)
		local panel = CreateFrame("Frame", nil, compareTip)
		panel:SetAllPoints(compareTip)
		panel:SetFrameLevel(max(compareTip:GetFrameLevel() - 1, 0))
		E:SetPanelTemplate(panel)
		compareTip:Hide()
	end
	if compareTip:IsShown() then return end
	compareTip:SetScale(main:GetEffectiveScale() / UIParent:GetEffectiveScale())
	compareTip:SetOwner(compareOwner, "ANCHOR_NONE")
	compareTip:ClearAllPoints()
	compareTip:SetPoint("TOPLEFT", main, "TOPRIGHT", 8, 0)
	-- Keep the spell's rank subtitle and request its exact ID.
	if E.PlainCall(compareTip.SetSpellByID, compareTip, compareID, false, true, true) ~= true then
		compareTip:Hide()
		return
	end
	if compareTip.NineSlice then compareTip.NineSlice:SetAlpha(0) end
	E.UIKit.TipText(compareTip, L["Currently known"])
	compareTip:Show()
	PositionCompareTip(compareTip, main)
end

local function CompareKey()
	if type(IsModifiedClick) ~= "function" then return end
	local key = E.PlainCall(GetModifiedClick, "COMPAREITEMS")
	if type(key) ~= "string" or key == "" or key == "NONE" then return end
	return E.PlainCall(GetBindingText, key, "KEY_") or key
end

local function AddPriceLines(tooltip, entry)
	local money = GetMoney()
	local cost = entry.cost or 0
	if cost == 0 then
		if entry.quest then tooltip:AddLine(L["Free: a class quest reward"], unpack(E.UIKit.TEXT)) end
		return
	end
	local price = Price(entry)
	local priceText = Coins(price)
	if price > money then priceText = Hex(G("RED_FONT_COLOR"), E:TextHex("bad")) .. priceText .. "|r" end
	E.UIKit.TipPair(tooltip, L["Cost"], priceText)
	local factions = TrainingFactions(entry)
	if #factions == 0 then return end
	if price ~= cost then E.UIKit.TipPair(tooltip, L["Without discount"], Coins(cost), unpack(E.UIKit.SECONDARY)) end
	-- One line per capital city that trains it, cheapest first.
	local rows = {}
	for _, id in ipairs(factions) do
		local rep = Reputation(id)
		if rep.city then rows[#rows + 1] = { rep = rep, price = Discounted(cost, rep.pct) } end
	end
	table.sort(rows, function(a, b)
		if a.price ~= b.price then return a.price < b.price end
		return a.rep.name < b.rep.name
	end)
	for _, row in ipairs(rows) do
		local standing = _G["FACTION_STANDING_LABEL" .. row.rep.reaction] or ""
		local left = ("%s %s(%s)|r"):format(row.rep.name, GREY, standing)
		local r, g, b = 0.75, 0.75, 0.8
		if row.rep.pct > 0 then r, g, b = 0.4, 1, 0.4 end
		tooltip:AddDoubleLine(left, Coins(row.price), r, g, b, 1, 1, 1)
	end
end

-- The tooltip of a Pet abilities rank: what it needs and where you learn it.
local function PetTooltip(tooltip, entry, def)
	local pets = view.pets
	local pet = pets and pets.pet
	Try(tooltip.SetSpellByID, tooltip, entry.id)
	tooltip:AddLine(" ")
	tooltip:AddLine((def.color and def.color() or "|cffffffff") .. L[def.title] .. "|r")
	local red = Hex(G("RED_FONT_COLOR"), E:TextHex("bad"))
	local above = pet and pet.level and entry.petLevel > pet.level
	E.UIKit.TipPair(tooltip, L["Pet level"], (above and red or "|cffffffff") .. entry.petLevel .. "|r")
	if (entry.tp or 0) > 0 then
		local points = tostring(entry.net or entry.tp)
		if entry.net and entry.net ~= entry.tp then points = L["%d (full rank %d)"]:format(entry.net, entry.tp) end
		E.UIKit.TipPair(tooltip, L["Training points"], (entry.category == "points" and red or "|cffffffff") .. points .. "|r")
	end
	local category = entry.category
	if category == "teach" or category == "points" or category == "level" then
		E.UIKit.TipText(tooltip, L["Teach it to your pet in Beast Training."])
	elseif category == "pet" then
		E.UIKit.TipText(tooltip, L["Your pet knows this rank or a higher one."])
	elseif category == "learned" then
		E.UIKit.TipText(tooltip, L["You have learned it. Call a pet of a family that can learn it to teach it."])
	elseif category == "trainer" then
		local trainer = entry.trainer
		E.UIKit.TipPair(tooltip, L["Level"], (trainer.level > playerLevel and red or "|cffffffff") .. trainer.level .. "|r")
		if (trainer.cost or 0) > 0 then E.UIKit.TipPair(tooltip, L["Cost"], Coins(trainer.cost)) end
		E.UIKit.TipText(tooltip, L["The pet trainer in the capital cities teaches it to you; then teach it to your pet in Beast Training."])
	elseif category == "unknown" then
		E.UIKit.TipText(tooltip, L["No known beast teaches this rank. Where it is learned on WoW: Forever is not known yet."])
	elseif category == "taming" then
		E.UIKit.TipText(tooltip, L["Tame a beast that knows it and let your pet use it: Beast Training keeps the rank for good."])
		local helper = E.TrainingPets
		if helper and helper:HasBeasts() then
			local beasts = helper:Beasts(entry.id)
			local LG = E.LootGuide
			for index = 1, min(#beasts, 5) do
				local mob = beasts[index]
				local level = mob.minLevel == mob.maxLevel and tostring(mob.minLevel) or ("%d-%d"):format(mob.minLevel or 0, mob.maxLevel or 0)
				local family = LG and LG.FamilyName and mob.family and LG:FamilyName(mob.family) or ""
				local mark = (mob.rank == 2 or mob.rank == 4) and (" " .. L["(rare)"]) or (mob.rank == 1 or mob.rank == 3) and (" " .. L["(elite)"]) or ""
				local left = ("%s %s(%s)|r%s"):format(mob.name, GREY, level, mark)
				tooltip:AddDoubleLine(left, family, 1, 1, 1, 0.75, 0.75, 0.8)
			end
			if #beasts > 5 then tooltip:AddLine(L["and %d more"]:format(#beasts - 5), unpack(E.UIKit.SECONDARY)) end
			if #beasts > 0 then
				local spot = helper:NearestBeast(entry.id)
				if spot and spot.zone then E.UIKit.TipPair(tooltip, L["Nearest"], ("%s, %s"):format(spot.mob.name, spot.zone)) end
			end
			tooltip:AddLine(L["Beast lists are Classic values; WoW: Forever may differ."], unpack(E.UIKit.SECONDARY))
		else
			tooltip:AddLine(L["Load the beasts to tame with the line at the top of the list."], unpack(E.UIKit.SECONDARY))
		end
	end
	tooltip:AddLine(" ")
	if category == "taming" and E.TrainingPets and E.TrainingPets:HasBeasts() and #E.TrainingPets:Beasts(entry.id) > 0 then
		E:TooltipHint(tooltip, { L["Click"], L["map pin on the nearest beast"] })
	end
	E:TooltipHint(tooltip, { L["Shift-click"], L["link in chat"] })
	tooltip:Show()
end

function M:ShowTooltip(owner, row)
	if not GameTooltip or E.FrameCheck(GameTooltip, "IsForbidden") or not row then return end
	StopComparing()
	if row.info then
		if not (row.toggle or row.load or row.tip) then return end
		GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
		if row.tip == "happiness" then
			GameTooltip:AddLine(L["Happiness"])
			E.UIKit.TipText(GameTooltip, L["A happy pet deals more damage and an unhappy one less. Feed it to keep it happy."])
		elseif row.tip == "loyalty" then
			GameTooltip:AddLine(L["Loyalty"])
			E.UIKit.TipText(GameTooltip, L["A happy pet gains loyalty over time and an unhappy one loses it. Each loyalty rank gives it more training points."])
			local ranks = E.TrainingPets and E.TrainingPets:LoyaltyRanks() or {}
			local current = view.pets and view.pets.pet and view.pets.pet.loyaltyRank
			for index, name in ipairs(ranks) do
				local color = index == current and E.UIKit.TEXT or E.UIKit.SECONDARY
				GameTooltip:AddDoubleLine(name, tostring(index), color[1], color[2], color[3], color[1], color[2], color[3])
			end
		elseif row.toggle then
			GameTooltip:AddLine(L["Pet abilities"])
			E:TooltipHint(GameTooltip, { L["Click"], view.pets and view.pets.filtered and L["show every family"] or L["show only your pet's family"] })
		else
			GameTooltip:AddLine(L["Beasts to tame"])
			E.UIKit.TipText(GameTooltip, L["Which beast teaches which rank comes from the Loot Guide's data folder, EldoUI_LootData."])
			E:TooltipHint(GameTooltip, { L["Click"], L["load it"] })
		end
		GameTooltip:Show()
		return
	end
	if row.header then
		GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
		GameTooltip:AddLine(L[row.def.title])
		E:TooltipHint(GameTooltip, { L["Click"], row.collapsed and L["unfold"] or L["fold"] })
		GameTooltip:Show()
		return
	end
	local entry = row.entry
	if not entry then return end
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	if entry.kind == "petrank" then return PetTooltip(GameTooltip, entry, row.def) end
	if entry.kind == "tome" then
		Try(GameTooltip.SetItemByID, GameTooltip, entry.itemId)
	else
		Try(GameTooltip.SetSpellByID, GameTooltip, entry.id, false, true, true)
	end
	GameTooltip:AddLine(" ")
	local def = row.def
	GameTooltip:AddLine((def.color and def.color() or "|cffffffff") .. L[def.title] .. "|r")
	if entry.level and entry.level > 1 then
		local color = entry.level > playerLevel and Hex(G("RED_FONT_COLOR"), E:TextHex("bad")) or "|cffffffff"
		E.UIKit.TipPair(GameTooltip, L["Level"], color .. entry.level .. "|r")
	end
	AddPriceLines(GameTooltip, entry)
	if entry.category == "missing" then
		for _, id in ipairs(entry.requiredIds or {}) do
			if not (SpellKnown(id) or KnownByLaterRank(id)) then
				local need = SpellData(id)
				local text = need and need.name and (need.rank and L["%s (%s)"]:format(need.name, need.rank) or need.name) or L["Spell %d"]:format(id)
				GameTooltip:AddLine(L["Learn first: %s"]:format(text), E:TokenColor("warn"))
			end
		end
	elseif entry.category == "talent" then
		local talent = SpellData(entry.requiredTalentId)
		GameTooltip:AddLine(L["Needs the talent %s"]:format(talent and talent.name or "?"), E:TokenColor("warn"))
	end
	if entry.quest then
		local areas = {}
		for _, area in ipairs(entry.quest) do areas[#areas + 1] = AreaName(area) end
		local where = areas[1] or ""
		for index = 2, #areas do where = L["%s or %s"]:format(where, areas[index]) end
		GameTooltip:AddLine(QUEST_MARK .. " " .. L["From a class quest in %s"]:format(where), E:TokenColor("gold"))
	end
	local knownRank, knownID = KnownRankText(entry)
	if knownRank then E.UIKit.TipPair(GameTooltip, L["You know"], knownRank) end
	if entry.kind == "tome" then
		E.UIKit.TipText(GameTooltip, L["For your %s. Sold by the demon trainer's vendor."]:format(FamilyName(entry.family)))
	elseif entry.kind == "pet" then
		E.UIKit.TipText(GameTooltip, L["Your pet learns it from the pet trainer. EldoUI notes what you know when you open Beast Training."])
	elseif entry.kind == "riding" then
		E.UIKit.TipText(GameTooltip, L["A riding trainer teaches it, next to the mount vendor of each race. The cost is the one a trainer asked, once you have opened one."])
	elseif entry.kind == "weapon" then
		for _, trainer in ipairs(entry.trainers) do
			GameTooltip:AddDoubleLine(MasterName(trainer), AreaName(trainer.zone), 1, 1, 1, 0.8, 0.8, 0.85)
		end
	end
	GameTooltip:AddLine(" ")
	if entry.kind == "weapon" and #entry.trainers > 0 then
		E:TooltipHint(GameTooltip, { L["Click"], L["map pin on the nearest weapon master"] })
	end
	E:TooltipHint(GameTooltip, { L["Shift-click"], L["link in chat"] })
	if entry.category ~= "known" then
		E:TooltipHint(GameTooltip, { L["Right-click"], IsIgnored(entry) and L["stop ignoring"] or L["ignore"] },
			{ L["Ctrl-right-click"], IsIgnored(entry) and L["stop ignoring every rank"] or L["ignore every rank"] })
	end
	local key = knownID and CompareKey()
	if key then E.UIKit.TipText(GameTooltip, L["Hold %s to compare with the rank you know"]:format(key)) end
	GameTooltip:Show()
	if key and GameTooltip:IsShown() and GameTooltip:IsOwned(owner) then
		if not compareHooks[GameTooltip] then
			compareHooks[GameTooltip] = true
			GameTooltip:HookScript("OnHide", StopComparing)
			GameTooltip:HookScript("OnTooltipCleared", StopComparing)
		end
		compareOwner, compareEntry, compareID = owner, entry, knownID
		self:RegisterEvent("MODIFIER_STATE_CHANGED", UpdateCompareTooltip)
		UpdateCompareTooltip()
	end
end

local function HideTooltip(owner)
	if not owner or compareOwner == owner then StopComparing() end
	if GameTooltip and not E.FrameCheck(GameTooltip, "IsForbidden") and (not owner or GameTooltip:IsOwned(owner)) then
		GameTooltip:Hide()
	end
end

local function Link(entry)
	if entry.kind == "tome" then
		local _, link = Try(C_Item.GetItemInfo, entry.itemId)
		return link
	end
	return C_Spell and C_Spell.GetSpellLink and Try(C_Spell.GetSpellLink, entry.id)
end

function M:ClickRow(row, button)
	if row.info then
		if row.toggle then
			self.db.petAllFamilies = not self.db.petAllFamilies
			self:Rebuild()
		elseif row.load and E.TrainingPets and E.TrainingPets:LoadBeasts() then
			self:Rebuild()
		end
		return
	end
	if row.header then
		local key = row.tab .. ":" .. row.def.key
		self.db.collapsed[key] = not self.db.collapsed[key] or nil
		self:Render()
		return
	end
	local entry = row.entry
	if not entry then return end
	if entry.kind == "petrank" then
		if IsShiftKeyDown() then
			local link = Link(entry)
			local util = G("ChatFrameUtil")
			local insert = util and util.InsertLink or G("ChatEdit_InsertLink")
			if link and insert then insert(link) end
		elseif button ~= "RightButton" and entry.category == "taming" and E.TrainingPets then
			E.TrainingPets:SetBeastWaypoint(entry.id)
		end
		return
	end
	if button == "RightButton" then
		if entry.category ~= "known" then self:SetIgnored(entry, not IsIgnored(entry), IsControlKeyDown()) end
	elseif IsShiftKeyDown() then
		local link = Link(entry)
		local util = G("ChatFrameUtil")
		local insert = util and util.InsertLink or G("ChatEdit_InsertLink")
		if link and insert then insert(link) end
	elseif entry.kind == "weapon" then
		self:SetWaypoint(entry)
	end
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------

local function Text(parent, size, justify)
	return E:CreateText(parent, size, justify)
end

local function HeaderColor(def)
	if M.db.semanticHeaders and def.color then return def.color() end
	return AccentHex()
end

local function CreateRow(list)
	local row = CreateFrame("Button", nil, list)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	row.stripe = row:CreateTexture(nil, "BACKGROUND", nil, -7)
	row.stripe:SetAllPoints()
	row.stripe:SetColorTexture(1, 1, 1, E.tokens.hover.row / 2)
	row.line = row:CreateTexture(nil, "BACKGROUND", nil, -6)
	row.line:SetPoint("BOTTOMLEFT")
	row.line:SetPoint("BOTTOMRIGHT")
	row.line:SetHeight(E.pixel)
	row.hover = row:CreateTexture(nil, "HIGHLIGHT")
	row.hover:SetAllPoints()
	E:AccentTexture(row.hover, 0.15)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	E:TrimIcon(row.icon)
	row.name = Text(row, 12, "LEFT")
	row.level = Text(row, 11, "RIGHT")
	row.cost = Text(row, 11, "RIGHT")
	row:SetScript("OnClick", function(self, button) M:ClickRow(self.data, button) end)
	row:SetScript("OnEnter", function(self) if self.data then M:ShowTooltip(self, self.data) end end)
	row:SetScript("OnLeave", HideTooltip)
	return row
end

local function LayoutRow(row, db)
	local height = db.rowHeight
	row:SetHeight(height)
	E:SetFont(row.name, db.fontSize)
	E:SetFont(row.level, max(db.fontSize - 1, 8))
	E:SetFont(row.cost, max(db.fontSize - 1, 8))
	row.icon:SetSize(height - 4, height - 4)
	row.icon:ClearAllPoints()
	row.icon:SetPoint("LEFT", 4, 0)
	row.cost:ClearAllPoints()
	row.cost:SetPoint("RIGHT", -4, 0)
	row.level:ClearAllPoints()
	row.level:SetPoint("RIGHT", row.cost, "LEFT", -8, 0)
	row.level:SetWidth(46)
end

local function Coin(copper, money, color)
	if copper <= 0 then return "" end
	local text = Coins(copper)
	if color then return color .. text .. "|r" end
	if money and copper > money then return Hex(G("RED_FONT_COLOR"), E:TextHex("bad")) .. text .. "|r" end
	return text
end

-- Pet abilities rows: the pet level a rank needs (red above the pet's
-- level) and its training points (red when the pet can't afford them); the
-- pet trainer's ranks show your level and the price instead.
local PET_MUTED = { pet = true, learned = true, unknown = true }
local function PetColumns(row, entry, money)
	local pets = view.pets
	local pet = pets and pets.pet
	local red = Hex(G("RED_FONT_COLOR"), E:TextHex("bad"))
	if entry.category == "trainer" and entry.trainer then
		local level = entry.trainer.level
		row.level:SetText((level > playerLevel and red or "|cffffffff") .. (G("LEVEL_ABBR") or L["Lvl"]) .. " " .. level .. "|r")
		row.cost:SetText(Coin(entry.trainer.cost, money))
		return
	end
	local muted = PET_MUTED[entry.category]
	local above = pet and pet.level and entry.petLevel > pet.level
	row.level:SetText((muted and GREY or above and red or "|cffffffff") .. L["Pet %d"]:format(entry.petLevel) .. "|r")
	local points = entry.net or entry.tp or 0
	if points > 0 then
		local color = muted and GREY or (entry.category == "points" and red) or "|cffffffff"
		row.cost:SetText(color .. L["%d TP"]:format(points) .. "|r")
	else
		row.cost:SetText("")
	end
end

local function FillRow(row, data, db, index, money)
	row.data = data
	row.stripe:SetShown(db.stripes and index % 2 == 0)
	row.line:SetColorTexture(1, 1, 1, E.tokens.hover.row)
	row.line:Hide()
	row.name:ClearAllPoints()
	row.name:SetPoint("RIGHT", row.level, "LEFT", -4, 0)
	if data.empty then
		row.icon:Hide()
		row.level:SetText("")
		row.cost:SetText("")
		row.name:SetPoint("LEFT", 8, 0)
		row.name:SetText(GREY .. data.text .. "|r")
		row:EnableMouse(false)
		return
	end
	if data.info then
		-- The lines above the Pet abilities list; the family line and the
		-- beast data line take a click.
		row.icon:Hide()
		row.stripe:Hide()
		row.level:SetText("")
		row.cost:SetText(data.right or "")
		row.name:SetPoint("LEFT", 4, 0)
		local clickable = data.toggle or data.load
		row.name:SetText((clickable and AccentHex() or "") .. data.text .. (clickable and "|r" or ""))
		row:EnableMouse((clickable or data.tip) and true or false)
		return
	end
	row:EnableMouse(true)
	if data.header then
		row.icon:Hide()
		row.line:Show()
		row.line:SetColorTexture(unpack(E.media.accentColor))
		row.line:SetAlpha(0.5)
		row.stripe:Hide()
		row.name:SetPoint("LEFT", 4, 0)
		local sign = data.collapsed and "+ " or ""
		row.name:SetText(("%s%s%s|r %s(%d)|r"):format(sign, HeaderColor(data.def), L[data.def.title], GREY, data.count))
		row.level:SetText("")
		local label = data.def.totalLabel and L[data.def.totalLabel]
		-- Only what you can learn now is weighed against your money.
		local muted = label ~= nil or data.def.upcoming
		local cost = Coin(data.total, not muted and money or nil, muted and GREY or nil)
		row.cost:SetText(cost ~= "" and (label and (GREY .. label:format("|r" .. cost)) or cost) or "")
		return
	end
	row.line:SetAlpha(1)
	if data.family then
		row.icon:SetShown(db.showIcons and data.icon ~= nil)
		if data.icon then row.icon:SetTexture(data.icon) end
		row.name:SetPoint("LEFT", (db.showIcons and data.icon) and row.icon or row, (db.showIcons and data.icon) and "RIGHT" or "LEFT", 6, 0)
		row.name:SetText("|cffffffff" .. FamilyName(data.family) .. "|r")
		row.level:SetText("")
		row.cost:SetText(Coin(data.total, money))
		row:EnableMouse(false)
		return
	end
	local entry = data.entry
	-- Upcoming rows are dimmed: you can't learn them yet.
	local upcoming = entry.category == "upcoming"
	local muted = entry.category == "known" or entry.category == "ignored" or upcoming
		or (entry.kind == "petrank" and PET_MUTED[entry.category])
	row.icon:SetShown(db.showIcons)
	row.icon:SetTexture(entry.icon)
	row.icon:SetDesaturated(muted)
	row.icon:SetAlpha(upcoming and E.tokens.disabledAlpha or 1)
	if db.showIcons then
		row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
	else
		row.name:SetPoint("LEFT", 8, 0)
	end
	local name = entry.name
	if muted then name = GREY .. name .. "|r" end
	local rank = entry.rank and (" " .. GREY .. entry.rank .. "|r") or ""
	row.name:SetText((entry.quest and (QUEST_MARK .. " ") or "") .. name .. rank)
	if entry.kind == "petrank" then return PetColumns(row, entry, money) end
	if data.def.showLevel and entry.level then
		local hex
		if entry.level > playerLevel then
			-- The level you still need, in red.
			hex = Hex(G("RED_FONT_COLOR"), E:TextHex("bad"))
		else
			local color = GetQuestDifficultyColor and E:DifficultyColor(GetQuestDifficultyColor(entry.level))
			hex = type(color) == "table" and color.r and ("|cff%02x%02x%02x"):format(color.r * 255, color.g * 255, color.b * 255) or "|cffffffff"
		end
		local mark = E:LevelMark(entry.level)
		row.level:SetText(hex .. (G("LEVEL_ABBR") or L["Lvl"]) .. " " .. entry.level .. "|r" .. (mark ~= "" and (" " .. mark) or ""))
	else
		row.level:SetText("")
	end
	if entry.category == "known" then
		row.cost:SetText(GREY .. (entry.cost > 0 and Coins(Price(entry)) or "") .. "|r")
	else
		local quiet = entry.category == "ignored" or upcoming
		row.cost:SetText(entry.cost > 0 and Coin(Price(entry), not quiet and money or nil, quiet and GREY or nil) or (entry.quest and (GREY .. L["Quest"] .. "|r") or ""))
	end
end

-- The kit's tab strip shows which list is open.
local win
local function UpdateTabs()
	local tab = M.db.tab == "pets" and not PetsShown() and "spells" or M.db.tab
	if win and frame and frame:IsShown() and win.current ~= tab and win:GetTab(tab) then
		win:ShowTab(tab)
	end
end

-- The list the window shows: "spells", "weapons", or "pets" for Hunters.
local function CurrentTab()
	local tab = M.db.tab
	if tab == "weapons" then return "weapons" end
	if tab == "pets" and PetsShown() then return "pets" end
	return "spells"
end

function M:Render()
	if not frame or not frame:IsShown() then return end
	local db = self.db
	local tab = CurrentTab()
	local rows = Rows(tab)
	frame.rowsData = rows
	local visible = min(frame.visible or 0, #frame.rows)
	local maxOffset = max(0, #rows - visible)
	frame.offset = min(frame.offset or 0, maxOffset)
	frame.scroll:SetMinMaxValues(0, maxOffset)
	frame.scroll:SetShown(maxOffset > 0)
	if frame.scroll:GetValue() ~= frame.offset then frame.scroll:SetValue(frame.offset) end
	local money = GetMoney()
	for index, row in ipairs(frame.rows) do
		local data = index <= visible and rows[index + frame.offset]
		if row == compareOwner and (not data or data.entry ~= compareEntry or data.entry.category == "known" or not SpellKnown(compareID)) then
			HideTooltip(row)
		end
		if data then
			FillRow(row, data, db, index + frame.offset, money)
			row:Show()
		else
			row.data = nil
			row:Hide()
		end
	end
	-- Footer: what you can learn now and what you have.
	local totals = view.totals or {}
	local isWeapons = tab == "weapons"
	local count = isWeapons and totals.weaponCount or totals.count or 0
	local cost = isWeapons and totals.weaponCost or totals.cost or 0
	local left
	if tab == "pets" then
		local teach = view.pets and view.pets.teach or 0
		left = teach > 0 and L["%d to teach your pet now"]:format(teach) or (GREY .. L["Nothing to teach your pet right now"] .. "|r")
	elseif count > 0 then
		left = L["%d to learn now: %s"]:format(count, Coin(cost, money))
	else
		left = GREY .. L["Nothing to learn right now"] .. "|r"
	end
	frame.summary:SetText(left)
	frame.money:SetText(GREY .. L["You have|r %s"]:format(Coins(money)))
	UpdateTabs()
end

local function LayoutRows()
	if not frame then return end
	local db = M.db
	local listHeight = frame.list:GetHeight() or 0
	local wanted = max(1, floor(listHeight / db.rowHeight))
	for index = #frame.rows + 1, wanted do frame.rows[index] = CreateRow(frame.list) end
	for index, row in ipairs(frame.rows) do
		LayoutRow(row, db)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", frame.list, "TOPLEFT", 0, -(index - 1) * db.rowHeight)
		row:SetPoint("TOPRIGHT", frame.list, "TOPRIGHT", -10, -(index - 1) * db.rowHeight)
		if index > wanted then row:Hide() end
	end
	frame.visible = wanted
	M:Render()
end

-- Saves where the standalone window stands as its mover's place.
local function SaveSpot()
	if M.docked or M.trainerDocked or not (frame and M.mover) then return end
	local scale = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
	local left, bottom = frame:GetLeft(), frame:GetBottom()
	if left and bottom then E:SaveMoverFromRect(M.mover, left * scale, bottom * scale) end
end

-- The kit's tabbed window keeps its zoom (Ctrl+mouse wheel on the title
-- bar) and its size (the corner grip) here: the module's Scale, Width and
-- Height settings. Its place is the module's mover, not the kit's.
-- Joined to the spellbook the window keeps a size of its own (dockWidth,
-- dockHeight), so resizing one never changes the other.
local SIZE_KEYS = { w = "width", h = "height" }
local DOCK_KEYS = { w = "dockWidth", h = "dockHeight" }
local function SizeKey(key)
	if M.docked then return DOCK_KEYS[key] end
	return SIZE_KEYS[key]
end
local spot = setmetatable({}, {
	__index = function(_, key)
		if not M.db then return nil end
		if key == "scale" then return M.db.scale end
		if SIZE_KEYS[key] then return M.db[SizeKey(key)] or nil end
	end,
	__newindex = function(_, key, value)
		if not M.db then return end
		if key == "scale" then
			M.db.scale = value
		elseif SIZE_KEYS[key] then
			-- No value: the grip is back at the size it was made with; keep
			-- what the window shows now.
			if value == nil and frame then
				value = key == "w" and frame:GetWidth() or frame:GetHeight()
			end
			if tonumber(value) then M.db[SizeKey(key)] = math.floor(value + 0.5) end
		end
	end,
})

-- Both tabs show the same list; the tab picks what it lists.
local function TabShow(key)
	return function()
		if M.db.tab ~= key then
			M.db.tab = key
			if frame then frame.offset = 0 end
		end
		M:Render()
	end
end

-- Every scale change (stand-alone, docked in the spellbook or next to the
-- trainer) snaps the 1-pixel edges to one screen pixel at that scale.
local function SetWindowScale(scale)
	frame:SetScale(scale)
	if frame.kitSnapped ~= scale then
		frame.kitSnapped = scale
		E:SnapBorders(frame)
	end
end

function M:CreateWindow()
	if frame then return frame end
	local db = self.db
	local Kit = E.UIKit
	local body
	local tabs = {
		{ key = "spells", title = L["Spells"], desc = L["Spells and abilities your class trainer teaches."],
			create = function() return body end, show = TabShow("spells") },
		{ key = "weapons", title = L["Weapons"], desc = L["Weapon skills the weapon masters teach."],
			create = function() return body end, show = TabShow("weapons") },
	}
	-- Hunters only: the Pet abilities list.
	tabs[#tabs + 1] = { key = "pets", title = L["Pet abilities"], desc = L["Every pet ability rank, what your pet can learn now and which beasts teach the rest."],
		create = function() return body end, show = TabShow("pets"), hidden = function() return not PetsShown() end }
	win = Kit.CreateTabbedWindow({
		name = "EldoUI_Training",
		options = { page = "module:Training" },
		title = L["Training"],
		width = db.width, height = db.height,
		-- The same limits as the Width and Height settings.
		minWidth = 300, minHeight = 300, maxWidth = 640, maxHeight = 900,
		store = function() return spot end,
		transparent = function() return M.db.transparent end,
		hideInCombat = false,
		footer = function() return L["Right-click: ignore  Shift: link"] end,
		tabs = tabs,
	})
	frame = win:Build()
	if frame.SetDontSavePosition then frame:SetDontSavePosition(true) end

	-- Drag the title bar while the window stands alone; its mover keeps the place.
	-- Dragged while joined to the spellbook it lets go and stands alone
	-- where you drop it; the spellbook never moves with it.
	frame.topBar:SetScript("OnDragStart", function()
		if M.trainerDocked then return end
		if M.docked then M:ReleaseDock() end
		frame:StartMoving()
	end)
	frame.topBar:SetScript("OnDragStop", function()
		frame:StopMovingOrSizing()
		if frame.SetUserPlaced then pcall(frame.SetUserPlaced, frame, false) end
		SaveSpot()
	end)
	-- The grip and the zoom keep the window's top-left corner: the place
	-- goes to the mover, then the window stands on it again.
	function win.SavePosition() SaveSpot() end
	function win.ApplyPosition() M:PlaceWindow() end
	frame.close:SetScript("OnClick", function() M:Hide() end)

	-- The list body: search, the rows, what you can learn and your money.
	body = CreateFrame("Frame", nil, frame.content)
	body:SetAllPoints(frame.content)
	frame.body = body
	frame.search = Kit.Input(body, { hint = L["Search"], tip = L["Filter the list by name."] })
	frame.search:SetPoint("TOPLEFT", 0, 0)
	frame.search:SetPoint("TOPRIGHT", 0, 0)
	frame.search:HookScript("OnTextChanged", function(box)
		local text = (box:GetText() or ""):lower()
		if text == filter then return end
		filter = text
		frame.offset = 0
		M:Render()
	end)
	frame.search:HookScript("OnEscapePressed", function(box) box:SetText("") end)

	-- The class name in its class color, beside the money.
	frame.subtitle = Text(body, E.tokens.size.small, "RIGHT")
	frame.subtitle:SetPoint("BOTTOMRIGHT", 0, 0)
	frame.money = Text(body, E.tokens.size.small, "LEFT")
	frame.money:SetPoint("BOTTOMLEFT", 2, 0)
	frame.money:SetPoint("BOTTOMRIGHT", frame.subtitle, "BOTTOMLEFT", -8, 0)
	frame.summary = Text(body, E.tokens.size.label, "LEFT")
	frame.summary:SetPoint("BOTTOMLEFT", frame.money, "TOPLEFT", 0, 4)
	frame.summary:SetPoint("BOTTOMRIGHT", frame.subtitle, "TOPRIGHT", 0, 4)
	frame.summary:SetJustifyV("BOTTOM")

	-- The list: a few row frames that show whatever part is scrolled in.
	frame.list = CreateFrame("Frame", nil, body)
	frame.list:SetPoint("TOPLEFT", frame.search, "BOTTOMLEFT", 0, -6)
	frame.list:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", 0, 40)
	frame.list:EnableMouseWheel(true)
	frame.list:SetScript("OnMouseWheel", function(_, delta)
		local _, high = frame.scroll:GetMinMaxValues()
		frame.scroll:SetValue(max(0, min(high, (frame.offset or 0) - delta * 3)))
	end)
	frame.list:SetScript("OnSizeChanged", function() LayoutRows() end)
	frame.rows = {}
	frame.offset = 0

	-- The kit's scroll bar (thin track, dim thumb, accent on hover or drag).
	frame.scroll = Kit.ScrollBar(frame.list, function(offset)
		if offset == frame.offset then return end
		frame.offset = offset
		M:Render()
	end)
	frame.divider = Kit.Divider(body)
	frame.divider:SetPoint("BOTTOMLEFT", 0, 34)
	frame.divider:SetPoint("BOTTOMRIGHT", 0, 34)

	frame:HookScript("OnShow", function()
		M:Rebuild()
		LayoutRows()
	end)
	frame:HookScript("OnHide", function()
		HideTooltip()
		if M.docked then M:Undock() end
		M:UpdateLauncher()
	end)

	self.mover = E:CreateMover(frame, MOVER, L["Training Window"], { "TOP", "UIParent", "TOP", 0, -90 }, {
		sample = false,
		onMoved = function() M:PlaceWindow() end,
	})
	self:ApplyLook()
	return frame
end

-- Opens the kit window on the chosen tab (the tab strip, the footer).
local function OpenWindow()
	win:Open(CurrentTab())
end

-- Standalone: on our mover. Docked: over the spellbook pages.
function M:PlaceWindow()
	if not frame or self.trainerDocked then return end
	if self.docked then return self:PlaceDocked() end
	frame:SetParent(UIParent)
	frame:SetFrameStrata("HIGH")
	win.opts.width, win.opts.height = self.db.width, self.db.height
	frame:SetSize(self.db.width, self.db.height)
	SetWindowScale(win:EffectiveScale())
	frame:ClearAllPoints()
	if self.mover then frame:SetPoint("CENTER", self.mover, "CENTER") end
end

function M:ApplyLook()
	if not frame then return end
	local db = self.db
	win:Restyle()
	if not (self.docked or self.trainerDocked) then
		win.opts.width, win.opts.height = db.width, db.height
		frame:SetSize(db.width, db.height)
		SetWindowScale(win:EffectiveScale())
	elseif self.docked then
		self:PlaceDocked()
	end
	-- The class name in its class color, next to the title.
	local className = UnitClass("player")
	frame.subtitle:SetText(className or "")
	frame.subtitle:SetTextColor(E:ClassColor("player"))
	LayoutRows()
end

function M:Show(tab)
	if not self.active then return end
	self:CreateWindow()
	if tab then self.db.tab = tab end
	OpenWindow()
	self:PlaceWindow()
	self:Render()
end

function M:Hide()
	if self.docked then self:Undock() end
	-- Closed beside a trainer: it stays closed until the trainer closes.
	if self.trainerDocked then
		self.trainerDismissed = true
		self:UndockTrainer()
	end
	if frame then frame:Hide() end
end

---------------------------------------------------------------------------
-- Beside a class trainer: one list of what a trainer
-- teaches. While this module is on, the Skins trainer list (Modules/
-- Skins.lua) shows this window beside Blizzard's class trainer instead of
-- its own compact list; profession trainers keep that list. Only our own
-- frame moves; Blizzard's trainer window is not changed.
---------------------------------------------------------------------------
function M:DockTrainer(trainerFrame)
	if not (self.active and trainerFrame and trainerFrame:IsShown()) or self.trainerDismissed then return false end
	if self.docked then self:Undock() end
	self:CreateWindow()
	self.trainerDocked = true
	OpenWindow()
	frame:SetParent(UIParent)
	frame:SetFrameStrata(E.FrameStrata(trainerFrame, "MEDIUM"))
	SetWindowScale(trainerFrame:GetEffectiveScale() / UIParent:GetEffectiveScale())
	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", trainerFrame, "TOPRIGHT", 4, 0)
	frame:SetSize(self.db.width, math.max(trainerFrame:GetHeight() or 0, 300))
	frame:SetFrameLevel(E.FrameLevel(trainerFrame, 1) + 2)
	if not self.trainerHooked[trainerFrame] then
		self.trainerHooked[trainerFrame] = true
		trainerFrame:HookScript("OnHide", function()
			M.trainerDismissed = nil
			if M.trainerDocked then M:UndockTrainer() end
		end)
	end
	self:Render()
	return true
end
M.trainerHooked = setmetatable({}, { __mode = "k" })

function M:UndockTrainer()
	self.trainerDocked = false
	if frame then
		frame:Hide()
		self:PlaceWindow()
	end
end

function M:Toggle(tab)
	if frame and frame:IsShown() and (not tab or self.db.tab == tab) then
		self:Hide()
	else
		self:Show(tab)
	end
end

---------------------------------------------------------------------------
-- Spellbook tab (element "Spellbook and talents", action Improve). A flat
-- EldoUI tab under the spellbook, beside Blizzard's own tabs; clicking it
-- lays the Training list over the spellbook pages. Nothing in Blizzard's
-- frame is changed: our tab and panel are our own frames, parented to it.
---------------------------------------------------------------------------
local launcher

-- The tab steps aside while the game's gamepad interface is on.
local function SpellbookAllowed()
	return M.active and M.db.spellbookTab and E:BlizzardAllowed(ELEMENT, "improve") and not E:GamepadUIActive()
end

local function Book()
	local root = _G.PlayerSpellsFrame
	return root, root and root.SpellBookFrame
end

-- The Training tab under the spellbook, once made (tests and diagnostics).
function M:SpellbookLauncher()
	return launcher
end

-- Hunters: the Pet abilities tab beside it, once made.
local petLauncher
function M:PetLauncher()
	return petLauncher
end

local function TabButton(root, label, width)
	local button = CreateFrame("Button", nil, root)
	button:SetSize(width, 30)
	E:SetTemplate(button)
	button.text = Text(button, 13, "CENTER")
	button.text:SetPoint("CENTER", 0, 1)
	button.text:SetText(label)
	button.underline = button:CreateTexture(nil, "OVERLAY")
	button.underline:SetPoint("BOTTOMLEFT", 6, 3)
	button.underline:SetPoint("BOTTOMRIGHT", -6, 3)
	button.underline:SetHeight(2)
	button.hover = button:CreateTexture(nil, "HIGHLIGHT")
	button.hover:SetPoint("TOPLEFT", E.pixel, -E.pixel)
	button.hover:SetPoint("BOTTOMRIGHT", -E.pixel, E.pixel)
	E:AccentTexture(button.hover, 0.15)
	button:SetScript("OnLeave", HideTooltip)
	button:Hide()
	return button
end

-- A tab click opens its list beside the spellbook, or closes it when that
-- list is already open there.
local function TabClick(tab)
	local open = M.docked and ((tab == "pets") == (CurrentTab() == "pets"))
	if open then return M:Hide() end
	if tab == "pets" then
		M.db.tab = "pets"
	elseif M.db.tab == "pets" then
		M.db.tab = "spells"
	end
	if frame then frame.offset = 0 end
	if M.docked then
		OpenWindow()
		M:Render()
		M:UpdateLauncher()
	else
		M:Dock()
	end
end

function M:CreatePetLauncher()
	if petLauncher then return petLauncher end
	local root = Book()
	if not (root and PetsShown()) then return nil end
	petLauncher = TabButton(root, L["Pet abilities"], 130)
	petLauncher:SetScript("OnClick", function() TabClick("pets") end)
	petLauncher:SetScript("OnEnter", function(button)
		if E.FrameCheck(GameTooltip, "IsForbidden") then return end
		E.UIKit.AnchorTooltip(button)
		GameTooltip:AddLine(L["Pet abilities"])
		local teach = view.pets and view.pets.teach or 0
		if teach > 0 then
			GameTooltip:AddLine(L["%d to teach your pet now"]:format(teach), unpack(E.UIKit.TEXT))
		else
			GameTooltip:AddLine(L["Every pet ability rank, what your pet can learn now and which beasts teach the rest."], unpack(E.tokens.text.secondary))
		end
		GameTooltip:Show()
	end)
	return petLauncher
end

function M:CreateLauncher()
	if launcher then return launcher end
	local root = Book()
	if not root then return nil end
	launcher = TabButton(root, L["Training"], 110)
	launcher:SetScript("OnClick", function() TabClick("spells") end)
	launcher:SetScript("OnEnter", function(button)
		if E.FrameCheck(GameTooltip, "IsForbidden") then return end
		E.UIKit.AnchorTooltip(button)
		GameTooltip:AddLine(L["Training"])
		local totals = view.totals or {}
		if (totals.count or 0) > 0 then
			GameTooltip:AddLine(L["%d to learn now: %s"]:format(totals.count, Coins(totals.cost)), unpack(E.UIKit.TEXT))
		else
			GameTooltip:AddLine(L["Nothing to learn right now."], unpack(E.tokens.text.secondary))
		end
		GameTooltip:Show()
	end)
	return launcher
end

function M:UpdateLauncher()
	local root, book = Book()
	if not root then return end
	if not SpellbookAllowed() then
		if launcher then launcher:Hide() end
		if petLauncher then petLauncher:Hide() end
		if self.docked then self:Hide() end
		return
	end
	self:CreateLauncher()
	self:CreatePetLauncher()
	launcher:ClearAllPoints()
	local tabs = root.TabSystem
	local pets = petLauncher and PetsShown()
	if tabs and tabs.GetRight and tabs:GetRight() then
		launcher:SetPoint("TOPLEFT", tabs, "TOPRIGHT", 4, 0)
	elseif pets then
		launcher:SetPoint("TOPRIGHT", root, "BOTTOMRIGHT", -24 - petLauncher:GetWidth() - 4, 2)
	else
		launcher:SetPoint("TOPRIGHT", root, "BOTTOMRIGHT", -24, 2)
	end
	local shown = book ~= nil and book:IsShown()
	launcher:SetShown(shown)
	if petLauncher then
		petLauncher:ClearAllPoints()
		petLauncher:SetPoint("TOPLEFT", launcher, "TOPRIGHT", 4, 0)
		petLauncher:SetShown(shown and pets and true or false)
	end
	if launcher:IsShown() then self:OfferTabHelp() end
	local r, g, b = unpack(E.media.accentColor)
	local onPets = CurrentTab() == "pets"
	for _, button in ipairs({ launcher, petLauncher }) do
		local active = self.docked == true and ((button == petLauncher) == onPets)
		button.underline:SetColorTexture(r, g, b, 1)
		button.underline:SetShown(active)
		button.text:SetTextColor(active and r or 0.85, active and g or 0.85, active and b or 0.88)
	end
	if self.docked and (not book or not book:IsShown()) then self:Hide() end
end

-- Joined to the spellbook: the window stands beside it on its right edge
-- (its left edge when there is no room on the right), parented to it, so
-- moving or closing the spellbook takes it along. The two never overlap,
-- and the window keeps a size of its own: the grip changes only it.
local function DockSide(root, width)
	local scale = root:GetEffectiveScale() / UIParent:GetEffectiveScale()
	local right, left = root:GetRight(), root:GetLeft()
	local screen = UIParent:GetWidth() or 0
	if right and left and (right + width) * scale > screen + 1 and left * scale >= width * scale then
		return "left"
	end
	return "right"
end

function M:DockSize()
	local root = Book()
	local db = self.db
	local width = tonumber(db.dockWidth) or db.width
	local height = tonumber(db.dockHeight) or (root and root:GetHeight()) or db.height
	return max(300, width), max(300, height)
end

function M:PlaceDocked()
	local root = Book()
	if not (frame and root) then return end
	local width, height = self:DockSize()
	win.opts.width, win.opts.height = width, height
	frame:SetSize(width, height)
	frame:ClearAllPoints()
	-- One anchor only: the grip sizes from the far corner and the shared
	-- edge stays where it is.
	self.dockSide = DockSide(root, width)
	if self.dockSide == "left" then
		frame:SetPoint("TOPRIGHT", root, "TOPLEFT", 0, 0)
	else
		frame:SetPoint("TOPLEFT", root, "TOPRIGHT", 0, 0)
	end
end

function M:Dock()
	local root, book = Book()
	if not (root and book and book:IsShown()) then return self:Show() end
	-- In combat the window opens on its own instead of on the spellbook.
	if InCombatLockdown() then return self:Show() end
	self:CreateWindow()
	self.docked = true
	OpenWindow()
	frame:SetParent(root)
	SetWindowScale(1)
	frame:SetFrameStrata(E.FrameStrata(root, "MEDIUM"))
	frame:SetFrameLevel(E.FrameLevel(root, 1) + 10)
	self:PlaceDocked()
	LayoutRows()
	self:UpdateLauncher()
end

-- Lets go of the spellbook and stays open where it is, standing alone.
function M:ReleaseDock()
	if not (self.docked and frame) then return end
	local before = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
	local left, top = frame:GetLeft(), frame:GetTop()
	self.docked = false
	frame:SetParent(UIParent)
	frame:SetFrameStrata("HIGH")
	win.opts.width, win.opts.height = self.db.width, self.db.height
	frame:SetSize(self.db.width, self.db.height)
	SetWindowScale(win:EffectiveScale())
	if left and top then
		local after = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
		frame:ClearAllPoints()
		frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left * before / after, top * before / after)
	end
	SaveSpot()
	LayoutRows()
	self:UpdateLauncher()
end

function M:Undock()
	self.docked = false
	if frame then
		frame:Hide()
		self:PlaceWindow()
	end
	self:UpdateLauncher()
end

function M:HookSpellbook()
	if self.spellbookHooked then return end
	local root, book = Book()
	if not (root and book) then return end
	self.spellbookHooked = true
	-- Blizzard's own events for the spellbook page (no hooks into its code).
	local function Update() if M.active then M:UpdateLauncher() end end
	if EventRegistry and EventRegistry.RegisterCallback then
		for _, event in ipairs({ "PlayerSpellsFrame.SpellBookFrame.Show", "PlayerSpellsFrame.SpellBookFrame.Hide" }) do
			EventRegistry:RegisterCallback(event, Update, M)
		end
	end
	book:HookScript("OnShow", Update)
	book:HookScript("OnHide", Update)
	root:HookScript("OnHide", function()
		if M.docked then M:Hide() end
	end)
end

-- Hooks go in only once the player allows the element; with the switch off
-- Blizzard's spellbook stays exactly as Blizzard made it.
function M:ApplySpellbook()
	if not SpellbookAllowed() then return self:RestoreSpellbook() end
	if C_AddOns.IsAddOnLoaded("Blizzard_PlayerSpells") then
		self:HookSpellbook()
		self:UpdateLauncher()
		return
	end
	if self.waitingSpellbook then return end
	self.waitingSpellbook = true
	E:OnBlizzardAddOn("Blizzard_PlayerSpells", function()
		M.waitingSpellbook = false
		if not SpellbookAllowed() then return end
		M:HookSpellbook()
		M:UpdateLauncher()
	end)
end

function M:RestoreSpellbook()
	if launcher then launcher:Hide() end
	if petLauncher then petLauncher:Hide() end
	if self.docked then self:Hide() end
end

-- The Talent Planner owns "Spellbook and talents"; the Training tab joins
-- its hook list.
E:HookBlizzardElement(ELEMENT, {
	owner = "Training",
	apply = function() if M.active then M:ApplySpellbook() end end,
	undo = function() M:RestoreSpellbook() end,
	install = { improve = true },
	-- New: nothing put a Training tab on the spellbook before.
	legacy = function() return false end,
})

---------------------------------------------------------------------------
-- Info bar block "Training"
---------------------------------------------------------------------------
function M:DataText()
	if not self.active then return GREY .. L["Training"] .. "|r" end
	local totals = view.totals or {}
	local count, cost = totals.count or 0, totals.cost or 0
	local format = self.db.datatextFormat
	if count == 0 then return GREY .. L["Training: none"] .. "|r" end
	if format == "count" then
		return L["Train: %s%d|r"]:format(AccentHex(), count)
	elseif format == "cost" then
		return L["Train: %s"]:format(Coin(cost, GetMoney()))
	end
	return L["Train: %s%d|r  %s"]:format(AccentHex(), count, Coin(cost, GetMoney()))
end

function M:DataTooltip(tooltip)
	tooltip:AddLine(L["Training"])
	if not self.active then
		E.UIKit.TipText(tooltip, E:ModuleOffNote("Training"))
		return
	end
	local money = GetMoney()
	local shownGroups = 0
	for _, group in ipairs(view.spells or {}) do
		local key = group.def.key
		local entries = group.entries
		if key == "upcoming" then
			-- The tooltip keeps to the next few levels.
			entries = {}
			for _, entry in ipairs(group.entries) do
				if not entry.far then entries[#entries + 1] = entry end
			end
		end
		if (key == "available" or key == "missing" or key == "upcoming" or key == "pet") and #entries > 0 then
			shownGroups = shownGroups + 1
			local total = 0
			for _, entry in ipairs(entries) do total = total + Price(entry) end
			tooltip:AddLine(" ")
			tooltip:AddDoubleLine(group.def.color() .. L[group.def.title] .. "|r", Coin(total, key == "available" and money or nil))
			for index, entry in ipairs(entries) do
				if index > 8 then
					tooltip:AddLine(GREY .. L["...and %d more"]:format(#entries - 8) .. "|r")
					break
				end
				local level = key ~= "available" and (GREY .. " " .. (G("LEVEL_ABBR") or L["Lvl"]) .. " " .. entry.level .. "|r") or ""
				tooltip:AddDoubleLine(entry.name .. (entry.rank and (" " .. GREY .. entry.rank .. "|r") or "") .. level,
					entry.cost > 0 and Coin(Price(entry), key == "available" and money or nil) or "", 1, 1, 1, 1, 1, 1)
			end
		end
	end
	if shownGroups == 0 then E.UIKit.TipText(tooltip, L["Nothing left to learn."]) end
	local totals = view.totals or {}
	if (totals.weaponCount or 0) > 0 then
		tooltip:AddLine(" ")
		tooltip:AddDoubleLine(L["Weapon skills to learn: %d"]:format(totals.weaponCount), Coin(totals.weaponCost, money))
	end
	tooltip:AddLine(" ")
	E:TooltipHint(tooltip, { L["Click"], L["Training window"] })
end

function M:RefreshDataText()
	local bar = E:GetModule("InfoBar")
	if bar and bar.active and bar.RefreshDataText then Try(bar.RefreshDataText, bar, "Training") end
end

E:RegisterDataText("Training", {
	title = "Training",
	events = { "PLAYER_MONEY" },
	text = function() return M:DataText() end,
	tooltip = function(tooltip) M:DataTooltip(tooltip) end,
	onClick = function()
		M:Toggle()
	end,
})

---------------------------------------------------------------------------
-- Commands and the addon compartment
---------------------------------------------------------------------------
local function Command(arg)
	arg = strtrim(arg or ""):lower()
	if arg ~= "" and arg ~= "spells" and arg ~= "weapons" and arg ~= "config" and arg ~= "options" and arg ~= "settings"
		and arg ~= "on" and arg ~= "off" and arg ~= "toggle" then
		E:Print(L["Usage: /eui training [spells | weapons | config | on | off]"])
		return
	end
	if arg == "on" or arg == "off" or arg == "toggle" then
		local on = arg == "on" or (arg == "toggle" and not M:IsEnabled())
		E:SetModuleFromCommand("Training", on)
		return
	elseif arg == "config" or arg == "options" or arg == "settings" then
		E:ToggleConfig("module:Training")
		return
	end
	if not M.active then
		E:Print(E:ModuleOffHint("Training"))
		return
	end
	M:Toggle(arg == "weapons" and "weapons" or arg == "spells" and "spells" or nil)
end

E:AddCommand("training", "[spells | weapons | config | on | off]  the Training window: what your trainer can teach you", Command, "Tools")

-- /wt as a short alias, only when nothing else uses it.
local function SlashTaken(command)
	for key in pairs(SlashCmdList) do
		for i = 1, 9 do
			local value = rawget(_G, "SLASH_" .. key .. i)
			if value == nil then break end
			if type(value) == "string" and value:lower() == command then return true end
		end
	end
	return false
end

-- On a beast a Hunter could tame: what its family eats. Never in combat,
-- and never on a pet someone already has.
local function BeastDietSection(_, unit, add)
	if classToken ~= "HUNTER" or InCombatLockdown() or type(unit) ~= "string" or not E.TrainingPets then return end
	local controlled = Try(UnitPlayerControlled, unit)
	if IsSecret(controlled) or controlled then return end
	local _, family = Try(UnitCreatureFamily, unit)
	if IsSecret(family) then return end
	local diet = E.TrainingPets:DietText(family)
	if diet then add(L["Eats"], diet) end
end

M.BeastDietSection = BeastDietSection

function M:RegisterExtras()
	if classToken == "HUNTER" and not self.dietDone and E.RegisterTooltipSection then
		self.dietDone = true
		E:RegisterTooltipSection("petDiet", { order = 46, title = "Hunter: what a beast eats", default = "always", module = "Training",
			desc = "On a beast you could tame: the food its family eats. Hunters only, never in combat.",
			unit = BeastDietSection })
	end
	if self.db.slashWT and not self.slashDone and not C_AddOns.IsAddOnLoaded("WhatsTraining") and not SlashTaken("/wt") then
		self.slashDone = true
		_G["SLASH_ELDOUITRAINING1"] = "/wt"
		SlashCmdList.ELDOUITRAINING = function(msg) Command(msg) end
	end
	if self.db.compartment and not self.compartmentDone and AddonCompartmentFrame and AddonCompartmentFrame.RegisterAddon then
		self.compartmentDone = true
		Try(AddonCompartmentFrame.RegisterAddon, AddonCompartmentFrame, {
			text = L["EldoUI Training"],
			icon = E:ClientIcon("Interface\\Icons\\INV_Misc_Book_11"),
			notCheckable = true,
			func = function() if M.active then M:Toggle() end end,
		})
	end
end

---------------------------------------------------------------------------
-- Pet training the game only shows at the trainer
---------------------------------------------------------------------------
-- A pet ability rank as the pet spell the lists use: Beast Training and
-- the "You have learned" line may name the Hunter's own Beast Training
-- spell instead.
local function PetSpell(id)
	if type(id) ~= "number" then return nil end
	local pets = E.TrainingPets
	local spell = pets and pets:PetSpell(id)
	if spell then return spell end
	return D.hunterPetAbilities[id] and id or nil
end

local function ScanPetTrainer()
	if classToken ~= "HUNTER" or not (C_Trainer and C_Trainer.GetTrainerType) then return end
	if not (Enum.TrainerType and C_Trainer.GetTrainerType() == Enum.TrainerType.Pet) then return end
	if type(GetNumTrainerServices) ~= "function" or not (C_TooltipInfo and C_TooltipInfo.GetTrainerService) then return end
	-- Beast Training (no trainer NPC) lists what you know; at a pet trainer
	-- only the services marked as used are known.
	local beastTraining = not UnitExists("npc")
	local store = Store()
	local learned, changed = store.petLearned, false
	if beastTraining and not store.petScanned then
		store.petScanned = true
		changed = true
	end
	for index = 1, GetNumTrainerServices() do
		local _, serviceType = GetTrainerServiceInfo(index)
		local data = Try(C_TooltipInfo.GetTrainerService, index)
		local id = type(data) == "table" and data.id
		local spell = not IsSecret(id) and PetSpell(id)
		if spell and (beastTraining or serviceType == "used") and not learned[spell] then
			learned[spell] = true
			changed = true
		end
	end
	if changed then M:QueueRebuild() end
end

-- "You have learned a new spell: %s." as a pattern, read once it is asked for.
local LEARN_PATTERN
local function LearnPattern()
	if LEARN_PATTERN == nil then
		local template = _G.ERR_LEARN_SPELL_S
		LEARN_PATTERN = type(template) == "string" and template:gsub("%%s", "(.+)") or false
	end
	return LEARN_PATTERN
end

local function LearnedFromChat(message)
	if classToken ~= "HUNTER" or type(message) ~= "string" or IsSecret(message) or not LearnPattern() then return end
	local learnedText = message:match(LEARN_PATTERN)
	local id = PetSpell(learnedText and tonumber(learnedText:match("|Hspell:(%d+)")))
	if id and not Store().petLearned[id] then
		Store().petLearned[id] = true
		M:QueueRebuild()
	end
end

-- Grimoires the demon that is out has learned: its pet spellbook has the
-- taught spell. Succubus and Incubus share grimoires, so those need to
-- know which of the two you summoned.
local function CheckDemon()
	if not M.active or classToken ~= "WARLOCK" or not catalog or not UnitExists("pet") then return end
	local bank = Bank("Pet")
	if not (bank and C_SpellBook and C_SpellBook.IsSpellInSpellBook) then return end
	local store, changed = Store(), false
	for _, entry in ipairs(catalog.spells) do
		if entry.kind == "tome" and entry.id and not store.petLearned[entry.key]
			and (not entry.shared or entry.family == store.demon)
			and C_SpellBook.IsSpellInSpellBook(entry.id, bank, false) then
			store.petLearned[entry.key] = true
			changed = true
		end
	end
	if changed then M:QueueRebuild() end
end

local unitEvents

local function UnitEvents(on)
	if not unitEvents then
		unitEvents = CreateFrame("Frame")
		unitEvents:SetScript("OnEvent", function(_, event, unit, _, spellID)
			if classToken == "HUNTER" then
				-- The pet out, its level or its training points changed.
				M:QueueRebuild()
				return
			end
			if event == "UNIT_SPELLCAST_SUCCEEDED" then
				if IsSecret(spellID) then return end
				local family = D.warlockSummons and D.warlockSummons[spellID]
				if family then
					Store().demon = family
					C_Timer.After(0.5, CheckDemon)
				end
			elseif event == "UNIT_PET" then
				C_Timer.After(0.5, CheckDemon)
			end
		end)
	end
	unitEvents:UnregisterAllEvents()
	if on and classToken == "WARLOCK" then
		unitEvents:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
		unitEvents:RegisterUnitEvent("UNIT_PET", "player")
	elseif on and PetsShown() then
		unitEvents:RegisterUnitEvent("UNIT_PET", "player")
		unitEvents:RegisterUnitEvent("UNIT_LEVEL", "pet")
		unitEvents:RegisterEvent("UNIT_PET_TRAINING_POINTS")
		unitEvents:RegisterEvent("PET_BAR_UPDATE")
		-- Happiness, loyalty and the pet's experience for the lines on top;
		-- an event this client lacks is skipped.
		pcall(unitEvents.RegisterUnitEvent, unitEvents, "UNIT_HAPPINESS", "pet")
		pcall(unitEvents.RegisterEvent, unitEvents, "UNIT_PET_EXPERIENCE")
		pcall(unitEvents.RegisterEvent, unitEvents, "PET_UI_UPDATE")
	end
end

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------
local EVENTS = {
	"PLAYER_ENTERING_WORLD", "PLAYER_LEVEL_UP", "LEARNED_SPELL_IN_SKILL_LINE", "SPELLS_CHANGED",
	"SKILL_LINES_CHANGED", "UPDATE_FACTION", "PLAYER_MONEY", "SPELL_DATA_LOAD_RESULT", "ITEM_DATA_LOAD_RESULT",
	"TRAINER_SHOW", "TRAINER_UPDATE", "CHAT_MSG_SYSTEM", "PLAYER_REGEN_ENABLED", "PLAYER_TALENT_UPDATE",
}

local function OnEvent(_, event, ...)
	if event == "PLAYER_LEVEL_UP" then
		-- UnitLevel lags behind this event; its payload is the new level.
		local level = ...
		M:QueueRebuild(type(level) == "number" and not IsSecret(level) and level or nil)
	elseif event == "PLAYER_MONEY" then
		if frame and frame:IsVisible() then QueueUpdate("money") end
	elseif event == "PLAYER_REGEN_ENABLED" then
		if next(updates) then ScheduleUpdate() end
	elseif event == "SPELLS_CHANGED" or event == "SKILL_LINES_CHANGED" or event == "PLAYER_TALENT_UPDATE" then
		QueueUpdate("spellbook")
	elseif event == "UPDATE_FACTION" then
		wipe(reputations)
		QueueUpdate("prices")
	elseif event == "SPELL_DATA_LOAD_RESULT" then
		local id = ...
		if pendingSpells[id] then
			pendingSpells[id] = nil
			M:QueueRebuild()
		end
	elseif event == "ITEM_DATA_LOAD_RESULT" then
		local id = ...
		if pendingItems[id] then
			pendingItems[id] = nil
			M:QueueRebuild()
		end
	elseif event == "TRAINER_SHOW" or event == "TRAINER_UPDATE" then
		ScanPetTrainer()
		if event == "TRAINER_SHOW" then RememberTrainer() end
		if M.ReadRidingCosts() then M:QueueRebuild() end
	elseif event == "CHAT_MSG_SYSTEM" then
		LearnedFromChat(...)
	elseif event == "PLAYER_ENTERING_WORLD" then
		local initialLogin, reloading = ...
		if classToken == "WARLOCK" then C_Timer.After(1, CheckDemon) end
		if initialLogin or reloading then M:QueueRebuild() end
	else
		M:QueueRebuild()
	end
end

function M:OnEnable()
	catalog = Catalog()
	for _, event in ipairs(EVENTS) do
		if event ~= "CHAT_MSG_SYSTEM" or classToken == "HUNTER" then self:RegisterEvent(event, OnEvent) end
	end
	UnitEvents(true)
	self:RegisterExtras()
	-- The gamepad and mouse interfaces swap: the spellbook tab follows.
	self:RegisterEvent("INPUT_DEVICE_INTERFACE_TRANSITION", function() M:ApplySpellbook() end)
	self:ApplySpellbook()
	self:Rebuild()
end

function M:OnDisable()
	if updateTimer then updateTimer:Cancel() end
	updateTimer = nil
	wipe(updates)
	StopComparing()
	for _, event in ipairs(EVENTS) do self:UnregisterEvent(event) end
	UnitEvents(false)
	self:RestoreSpellbook()
	-- Turned off beside a trainer is not "closed by the player".
	if self.trainerDocked then self:UndockTrainer() end
	self:Hide()
	self:RefreshDataText()
end

function M:OnProfileChanged()
	if not self.active then return end
	self.db.collapsed = self.db.collapsed or {}
	self:ApplyLook()
	self:ApplySpellbook()
	self:Rebuild()
end

---------------------------------------------------------------------------
-- Options and styles
---------------------------------------------------------------------------
local function SpellbookReason()
	if not E:BlizzardAllowed(ELEMENT, "improve") then
		return L["Turn on \"Let EldoUI change this\" and Improve for Spellbook and talents under Blizzard UI"]
	end
end

local function Look(extra)
	local list = {
		{ type = "range", key = "fontSize", label = "Text size", min = 9, max = 16, step = 1, desc = "Size of the spell names; levels and costs are one size smaller." },
		{ type = "range", unit = "px", key = "rowHeight", label = "Row height", min = 14, max = 28, step = 1, desc = "Height of each line in the list." },
		{ type = "toggle", key = "showIcons", label = "Spell icons", desc = "Shows each spell's icon in front of its name." },
		{ type = "toggle", key = "stripes", label = "Striped rows", desc = "Tints every other row a little, to follow a line across." },
		{ type = "toggle", key = "semanticHeaders", label = "Colored group titles", desc = "Group titles in the game's colors: green for available now, blue for upcoming, gray for known. Off uses your accent color." },
		{ type = "toggle", key = "transparent", label = "See-through window", desc = "The window lets the game show through a little. How much: General > Panel opacity." },
	}
	for _, row in ipairs(extra or {}) do list[#list + 1] = row end
	return list
end

M.options = {
	{ type = "description", label = "Everything your class trainer teaches on Forever, from the spell data of What's Training? (MIT). Nothing is trained for you." },
	{ type = "header", label = "Window" },
	{ type = "execute", label = "Open the Training window", desc = "Shows the window with what you can learn (also /eui training and the Training info bar block).", testSafe = true,
		func = function() M:Show() end },
	{ type = "toggle", key = "spellbookTab", label = "Tab on the spellbook", desc = "A Training tab under Blizzard's spellbook that lays this list over the spellbook pages.",
		disabled = SpellbookReason },
	{ type = "execute", label = "Open Blizzard UI switches", desc = "Turn on Improve for Spellbook and talents here to get the spellbook tab.",
		func = function() E:ToggleConfig("blizzard") end },
	{ type = "header", label = "List" },
	{ type = "toggle", key = "showKnown", label = "Known spells", desc = "Lists the spells you already know at the bottom, with what they cost you." },
	{ type = "toggle", key = "showIgnored", label = "Ignored spells", desc = "Lists the spells you ignored (right-click a spell) above the known ones, with what you save." },
	{ type = "toggle", key = "showLater", label = "All later levels", desc = "Upcoming lists everything you learn at later levels, up to the level cap. Off keeps it to the next few levels." },
	{ type = "range", key = "soonLevels", label = "Levels ahead for Upcoming", min = 1, max = 10, step = 1, desc = "Upcoming always lists what opens within this many levels; with All later levels on it lists the rest too." },
	{ type = "toggle", key = "showKnownWeapons", label = "Known weapon skills", desc = "Lists the weapon skills you already have on the Weapons tab." },
	{ type = "select", key = "priceMode", label = "Prices", desc = "Base price, or the price at the trainer where your reputation gives the best discount (Honored or better: 10% off).",
		values = { base = "Base price", best = "With your best discount" } },
	{ type = "execute", label = "Stop ignoring everything", desc = "Clears this character's ignore list.", confirm = true,
		func = function() M:ClearIgnored() end },
	{ type = "header", label = "Info bar and shortcuts" },
	{ type = "select", key = "datatextFormat", label = "Info bar block", desc = "What the Training block on the info bar shows (add it under Info Bar).",
		values = { count = "Spells to learn", cost = "Total cost", countCost = "Spells and cost" } },
	{ type = "toggle", key = "slashWT", label = "/wt command", desc = "Also opens the window with /wt, unless another addon uses /wt.", reload = true },
	{ type = "toggle", key = "compartment", label = "Addon menu entry", desc = "An entry in the addon compartment menu by the minimap that opens the window.", reload = true },
	{ type = "header", label = "Look" },
	{ type = "range", unit = "px", key = "width", label = "Width", min = 300, max = 640, step = 10, desc = "Width of the window when it stands alone." },
	{ type = "range", unit = "px", key = "height", label = "Height", min = 300, max = 900, step = 10, desc = "Height of the window when it stands alone." },
	{ type = "cog", label = "More look settings", desc = "Text size, row height, icons, stripes, group title colors and see-through. Drag the window's corner grip to change its size; Ctrl+mouse wheel on the title bar zooms it.", options = Look({}) },
}

E:RegisterStyles("Training", {
	{ key = "Standard", title = "Standard", desc = "Icons, colored group titles, striped rows.",
		settings = { fontSize = 12, rowHeight = 20, width = 380, height = 540, scale = 1, showIcons = true, stripes = true, semanticHeaders = true, transparent = false, showKnown = true, showIgnored = true, showLater = true } },
	{ key = "Compact", title = "Compact", desc = "Smaller text and rows; more spells fit.",
		settings = { fontSize = 11, rowHeight = 16, width = 340, height = 480, scale = 1, showIcons = true, stripes = true, semanticHeaders = true, transparent = false } },
	{ key = "Large", title = "Large", desc = "Bigger text and rows, easy to read.",
		settings = { fontSize = 14, rowHeight = 24, width = 460, height = 640, scale = 1, showIcons = true, stripes = true, semanticHeaders = true, transparent = false } },
	{ key = "Ledger", title = "Ledger", desc = "No icons, accent group titles, like a price list.",
		settings = { fontSize = 12, rowHeight = 18, width = 400, height = 560, scale = 1, showIcons = false, stripes = true, semanticHeaders = false, transparent = false } },
	{ key = "Focus", title = "Focus", desc = "Only what you can learn now and in the next few levels; known and ignored spells hidden.",
		settings = { fontSize = 12, rowHeight = 20, width = 360, height = 420, scale = 1, showIcons = true, stripes = false, semanticHeaders = true, transparent = false, showKnown = false, showIgnored = false, showLater = false } },
	{ key = "Glass", title = "Glass", desc = "See-through window without stripes.",
		settings = { fontSize = 12, rowHeight = 20, width = 380, height = 540, scale = 1, showIcons = true, stripes = false, semanticHeaders = true, transparent = true } },
})

---------------------------------------------------------------------------
-- Tour help: the Training tab, once the spellbook has stayed open a moment
---------------------------------------------------------------------------
local function ShownLauncher()
	if launcher and launcher:IsVisible() then return launcher end
end

E.Tour:Register("training:tab", {
	form = "spot", word = "training",
	offer = function(_, force)
		return E.Tour:Spot("training:tab", {
			force = force, target = ShownLauncher,
			title = L["Training"],
			text = L["The Training tab lists what your class trainer can teach you now and at later levels, with the cost. It only shows the list: you still learn at the trainer."],
		})
	end,
	replay = function(def) def.offer(def, true) end,
})

local tabHelpPending = false
function M:OfferTabHelp()
	if tabHelpPending or E.Tour:Seen("training:tab") then return end
	tabHelpPending = true
	C_Timer.After(1, function()
		tabHelpPending = false
		if ShownLauncher() then E.Tour:Offer("training:tab") end
	end)
end
