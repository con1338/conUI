-- EldoUI Training: the Hunter's pet abilities (the Training module's
-- "Pet abilities" tab beside the Training tab under the spellbook, and the
-- Pet abilities tab of the Training window). Hunters only.
--
-- Every rank a Hunter pet can have, sorted by what you can do about it:
--   Can teach now          you know the rank, your pet's family can learn
--                          it, the pet has the level and the training points
--   Not enough training points, Needs pet level
--   Learn by taming        tame a beast that knows the rank and let it use
--                          the ability: Beast Training keeps it for good
--   Pet trainer            the pet trainer teaches it to you
--   Not known yet          no known beast teaches it
--   Known by your pet, Learned by you
-- The ranks, pet levels and training points are the client's own
-- (Data/Training/PetAbilities.lua). Which wild beast knows a rank comes from
-- the Loot Guide's data folder (EldoUI_LootData), Classic-era values that
-- WoW: Forever may differ from.
--
-- Information only: it never teaches, trains, tames or casts anything, and
-- the map pin is set on your click. It reads the pet that is out, its
-- training points and its spellbook, and what Beast Training listed.
local _, E = ...
local L = E.L
local D = E.TrainingData

local P = {}
E.TrainingPets = P

local IsSecret = E.Secret
local BEAST_TRAINING_LEVEL = 10
local BEASTS_SHOWN = 5

local function Try(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a, b, c = pcall(fn, ...)
	if ok then return a, b, c end
end

local function Plain(value)
	if IsSecret(value) then return nil end
	return value
end

---------------------------------------------------------------------------
-- The client's pet ability table, indexed once
---------------------------------------------------------------------------
local index

local function Index()
	if index then return index end
	index = { chain = {}, entryToPet = {}, order = {}, trainer = {} }
	local data = D and D.petAbilities
	if not data then return index end
	for key, ability in pairs(data.abilities or {}) do
		for position, spell in ipairs(ability.ranks) do
			index.chain[spell] = { key = key, position = position, ability = ability }
			index.order[#index.order + 1] = spell
		end
	end
	for spell, rank in pairs(data.ranks or {}) do
		if rank[3] and rank[3] > 0 then index.entryToPet[rank[3]] = spell end
	end
	table.sort(index.order, function(a, b)
		local ca, cb = index.chain[a], index.chain[b]
		if ca.ability.name ~= cb.ability.name then return ca.ability.name < cb.ability.name end
		return ca.position < cb.position
	end)
	-- The ranks the pet trainer teaches you, with your level and the price
	-- (Data/Training/Hunter.lua).
	local make = D.classes and D.classes.HUNTER
	local hunter = make and make() or {}
	for level, spells in pairs(hunter.spells or {}) do
		for _, spell in ipairs(spells) do
			if D.hunterPetAbilities and D.hunterPetAbilities[spell.id] then
				index.trainer[spell.id] = { level = level, cost = spell.cost or 0 }
			end
		end
	end
	return index
end

function P:Available()
	return select(2, UnitClass("player")) == "HUNTER" and D ~= nil and D.petAbilities ~= nil
end

-- Pet level, full training points, the Beast Training spell and whether it
-- comes with Beast Training, for a pet spell.
function P:Rank(spell)
	local rank = D.petAbilities and D.petAbilities.ranks[spell]
	if not rank then return nil end
	return { petLevel = rank[1], tp = rank[2], entry = rank[3] > 0 and rank[3] or nil, auto = rank[4] == 1 }
end

-- The pet spell a Beast Training row or a "You have learned" link names:
-- the pet's own spell, or the Beast Training spell the Hunter keeps.
function P:PetSpell(id)
	if type(id) ~= "number" then return nil end
	if D.petAbilities and D.petAbilities.ranks[id] then return id end
	return Index().entryToPet[id]
end

function P:Trainer(spell)
	return Index().trainer[spell]
end

---------------------------------------------------------------------------
-- The pet that is out
---------------------------------------------------------------------------
local function PetBank()
	return Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Pet
end

local function PetHas(spell)
	local bank = PetBank()
	if not (bank and C_SpellBook and C_SpellBook.IsSpellInSpellBook) then return false end
	return Try(C_SpellBook.IsSpellInSpellBook, spell, bank, false) == true
end

---------------------------------------------------------------------------
-- What a family eats and the loyalty ranks (Data/Training/PetCare.lua)
---------------------------------------------------------------------------
-- The food types in the order of the client's food mask bits, lowest first.
local FOODS = { E.Key("Meat"), E.Key("Fish"), E.Key("Cheese"), E.Key("Bread"), E.Key("Fungus"), E.Key("Fruit"),
	E.Key("Raw Meat"), E.Key("Raw Fish") }

-- The loyalty ranks as the client table names them, in the language shown.
local LOYALTY_NAMES = E:TranslateValues({
	Rebellious = E.Key("Rebellious"), Unruly = E.Key("Unruly"), Submissive = E.Key("Submissive"),
	Dependable = E.Key("Dependable"), Faithful = E.Key("Faithful"), ["Best Friend"] = E.Key("Best Friend"),
})

-- The food types a family eats, in the language shown, or nil when the
-- family is not a Hunter pet.
function P:Diet(family)
	local care = D and D.petCare
	local mask = care and type(family) == "number" and care.diet[family]
	if type(mask) ~= "number" then return nil end
	local out = {}
	for bit = 1, #FOODS do
		if math.floor(mask / 2 ^ (bit - 1)) % 2 == 1 then out[#out + 1] = L[FOODS[bit]] end
	end
	return #out > 0 and out or nil
end

function P:DietText(family)
	local foods = self:Diet(family)
	return foods and table.concat(foods, ", ") or nil
end

-- The loyalty ranks, lowest first, in the language shown.
function P:LoyaltyRanks()
	local out = {}
	for position, name in ipairs(D and D.petCare and D.petCare.loyalty or {}) do out[position] = LOYALTY_NAMES[name] or name end
	return out
end

-- The rank number in the game's loyalty text: its number, else the rank
-- it names.
function P:LoyaltyRank(text)
	if type(text) ~= "string" then return nil end
	local ranks = self:LoyaltyRanks()
	local number = tonumber(text:match("%d+"))
	if number and number >= 1 and number <= #ranks then return number end
	local lower = text:lower()
	for position, name in ipairs(D and D.petCare and D.petCare.loyalty or {}) do
		if lower:find(name:lower(), 1, true) or lower:find(ranks[position]:lower(), 1, true) then return position end
	end
end

-- { name, family, familyName, level, loyalty, loyaltyRank, total, used,
-- free, speed, happiness, damage, loyaltyRate, xp, xpMax } or nil.
-- speed: seconds between the pet's attacks, as the game reports it now.
-- happiness 1 to 3 with the damage percent it gives and the loyalty rate
-- (above 0 rising, below 0 falling), as the game reports them.
function P:Pet()
	if not Plain(UnitExists("pet")) then return nil end
	local pet = { name = Plain(UnitName("pet")), level = Plain(UnitLevel("pet")) }
	local familyName, family = UnitCreatureFamily("pet")
	pet.familyName, pet.family = Plain(familyName), Plain(family)
	if C_PetInfo and C_PetInfo.GetPetLoyalty then pet.loyalty = Plain(Try(C_PetInfo.GetPetLoyalty)) end
	if type(pet.loyalty) ~= "string" or pet.loyalty == "" then pet.loyalty = nil end
	pet.loyaltyRank = self:LoyaltyRank(pet.loyalty)
	if C_PetInfo and C_PetInfo.GetPetHappiness then
		local happiness, damage, rate = Try(C_PetInfo.GetPetHappiness)
		happiness, damage, rate = Plain(happiness), Plain(damage), Plain(rate)
		if type(happiness) == "number" and happiness >= 1 then
			pet.happiness = happiness
			pet.damage = type(damage) == "number" and damage > 0 and damage or nil
			pet.loyaltyRate = type(rate) == "number" and rate or nil
		end
	end
	if GetPetExperience then
		local xp, xpMax = Try(GetPetExperience)
		xp, xpMax = Plain(xp), Plain(xpMax)
		if type(xp) == "number" and type(xpMax) == "number" and xpMax > 0 then pet.xp, pet.xpMax = xp, xpMax end
	end
	if UnitAttackSpeed then
		local speed = Plain(Try(UnitAttackSpeed, "pet"))
		if type(speed) == "number" and speed > 0 then pet.speed = speed end
	end
	if C_PetInfo and C_PetInfo.GetPetTrainingPoints then
		local total, used = Try(C_PetInfo.GetPetTrainingPoints)
		total, used = Plain(total), Plain(used)
		if type(total) == "number" and type(used) == "number" then
			pet.total, pet.used, pet.free = total, used, total - used
		end
	end
	return pet
end

-- The family's own ranks (besides the general ones), as a set.
local function FamilyRanks(family)
	local info = family and D.petAbilities.families[family]
	if not info then return nil end
	local set = {}
	for _, spell in ipairs(info.ranks) do set[spell] = true end
	return set
end

-- The highest rank of the same ability the pet has, as its position.
local function PetRankPosition(spell, petSpells)
	local chain = Index().chain[spell]
	if not chain then return 0 end
	local best = 0
	for position, other in ipairs(chain.ability.ranks) do
		if petSpells[other] and position > best then best = position end
	end
	return best
end

---------------------------------------------------------------------------
-- Beasts that teach a rank (EldoUI_LootData.tameSpells)
---------------------------------------------------------------------------
local beastsBySpell, beastsData

local function LootGuide()
	local LG = E.LootGuide
	if LG and LG.HasData and LG:HasData() then return LG end
end

-- Loads the Loot Guide's data folder for the beast list, out of combat.
function P:LoadBeasts()
	local LG = E.LootGuide
	if not (LG and LG.LoadData) or InCombatLockdown() then return false end
	return LG:LoadData() and true or false
end

local function BeastIndex()
	local LD = rawget(_G, "EldoUI_LootData")
	if not (LootGuide() and type(LD) == "table" and type(LD.tameSpells) == "table") then return nil end
	if beastsData == LD.tameSpells then return beastsBySpell end
	beastsData, beastsBySpell = LD.tameSpells, {}
	for npc, text in pairs(LD.tameSpells) do
		for spell in tostring(text):gmatch("%d+") do
			spell = tonumber(spell)
			local list = beastsBySpell[spell]
			if not list then
				list = {}
				beastsBySpell[spell] = list
			end
			list[#list + 1] = npc
		end
	end
	return beastsBySpell
end

-- True when the beast list can answer (the data folder is loaded).
function P:HasBeasts()
	return BeastIndex() ~= nil
end

-- Beasts that teach `spell`: { { id, name, minLevel, maxLevel, rank, family } },
-- the ones you can tame now first (closest to your level), then by level.
function P:Beasts(spell)
	local list = BeastIndex()
	list = list and list[spell]
	if not list then return {} end
	local LG = LootGuide()
	local level = Plain(UnitLevel("player")) or 1
	local out = {}
	for _, npc in ipairs(list) do
		local mob = LG:Mob(npc)
		if mob and mob.name then out[#out + 1] = mob end
	end
	local function Now(mob) return (mob.minLevel or 99) <= level end
	table.sort(out, function(a, b)
		if Now(a) ~= Now(b) then return Now(a) end
		if Now(a) then
			if (a.maxLevel or 0) ~= (b.maxLevel or 0) then return (a.maxLevel or 0) > (b.maxLevel or 0) end
		elseif (a.minLevel or 0) ~= (b.minLevel or 0) then
			return (a.minLevel or 0) < (b.minLevel or 0)
		end
		if a.name ~= b.name then return a.name < b.name end
		return a.id < b.id
	end)
	return out
end

-- Where you stand, in the world coordinates the spawn camps use.
local function PlayerWorld()
	if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return nil end
	local map = Plain(Try(C_Map.GetBestMapForUnit, "player"))
	if not map then return nil end
	local position = Try(C_Map.GetPlayerMapPosition, map, "player")
	if type(position) ~= "table" or not position.GetXY then return nil end
	local x, y = position:GetXY()
	if not (Plain(x) and Plain(y)) then return nil end
	local continent, world = Try(C_Map.GetWorldPosFromMapPos, map, CreateVector2D(x, y))
	if not continent or type(world) ~= "table" or not world.GetXY then return nil end
	local wx, wy = world:GetXY()
	return continent, wx, wy
end

-- The spawn camp nearest to you among the beasts you can tame now (else
-- any that teach the rank): { npc, mob, uiMapID, x, y (0-1), zone }.
function P:NearestBeast(spell)
	local LG = LootGuide()
	if not LG then return nil end
	local beasts = self:Beasts(spell)
	local level = Plain(UnitLevel("player")) or 1
	local continent, px, py = PlayerWorld()
	local best, bestDistance, bestNow
	for _, mob in ipairs(beasts) do
		local now = (mob.minLevel or 99) <= level
		for _, camp in ipairs(LG:SpawnPoints("npc", mob.id)) do
			local distance = (continent == camp.map and px) and ((camp.x - px) ^ 2 + (camp.y - py) ^ 2) or math.huge
			local better = not best or (now and not bestNow) or (now == bestNow and distance < bestDistance)
			if better then
				local uiMapID, x, y = LG:MapPosition(camp)
				if uiMapID then
					best = { npc = mob.id, mob = mob, uiMapID = uiMapID, x = x, y = y, zone = LG:MapName(uiMapID) }
					bestDistance, bestNow = distance, now
				end
			end
		end
	end
	return best
end

-- A map pin on the nearest beast that teaches `spell`, on your click.
function P:SetBeastWaypoint(spell)
	local spot = self:NearestBeast(spell)
	if not spot then return false end
	return E.LootGuide:SetWaypoint({ uiMapID = spot.uiMapID, x = spot.x, y = spot.y, zone = spot.zone }, spot.mob.name)
end

---------------------------------------------------------------------------
-- The list: groups of ranks
---------------------------------------------------------------------------
P.CATEGORIES = {
	{ key = "teach", title = "Can teach now", tone = "good" },
	{ key = "points", title = "Not enough training points", tone = "warn" },
	{ key = "level", title = "Needs pet level", tone = "accent", showLevel = true },
	{ key = "taming", title = "Learn by taming", tone = "gold", showLevel = true },
	{ key = "trainer", title = "Pet trainer", tone = "body", showLevel = true },
	{ key = "unknown", title = "Not known yet", tone = "secondary", showLevel = true },
	{ key = "pet", title = "Known by your pet", tone = "secondary", option = "showKnown" },
	{ key = "learned", title = "Learned by you", tone = "secondary", option = "showKnown" },
}

-- What the Hunter has learned: Beast Training rows, the "You have learned"
-- line, and the two Growl ranks that come with Beast Training.
local function HunterKnows(spell, rank, learned, playerLevel)
	if learned[spell] then return true end
	if rank.auto then return playerLevel >= BEAST_TRAINING_LEVEL end
	if rank.entry and C_SpellBook and C_SpellBook.IsSpellKnown then
		return Try(C_SpellBook.IsSpellKnown, rank.entry) == true
	end
	return false
end

-- Builds the list. `learned`: the pet spells Beast Training showed;
-- `allFamilies`: list every family, not only the pet's.
-- Returns { pet, family set used, groups = { { def, entries } }, teach = n }.
function P:Build(learned, allFamilies)
	local out = { groups = {}, byKey = {}, teach = 0 }
	for _, def in ipairs(self.CATEGORIES) do
		local group = { def = def, entries = {} }
		out.groups[#out.groups + 1] = group
		out.byKey[def.key] = group
	end
	if not (D and D.petAbilities) then return out end
	local idx = Index()
	local playerLevel = Plain(UnitLevel("player")) or 1
	local pet = self:Pet()
	out.pet = pet
	local familyRanks = pet and FamilyRanks(pet.family)
	out.filtered = familyRanks ~= nil and not allFamilies
	local petSpells = {}
	if pet then
		for _, spell in ipairs(idx.order) do
			if PetHas(spell) then petSpells[spell] = true end
		end
	end
	local beasts = BeastIndex()
	out.beasts = beasts ~= nil
	for _, spell in ipairs(idx.order) do
		local chain = idx.chain[spell]
		local rank = self:Rank(spell)
		local forPet = familyRanks and (chain.ability.general or familyRanks[spell]) or false
		if rank and (not out.filtered or forPet) then
			local entry = { kind = "petrank", id = spell, key = "pet:" .. spell, petLevel = rank.petLevel,
				level = rank.petLevel, cost = 0, tp = rank.tp, net = rank.tp, chain = chain, auto = rank.auto,
				trainer = idx.trainer[spell] }
			local known = HunterKnows(spell, rank, learned, playerLevel)
			local petPosition = forPet and PetRankPosition(spell, petSpells) or 0
			local category
			if petPosition >= chain.position then
				category = "pet"
			elseif known then
				if forPet and pet then
					-- A higher rank costs only the difference to the one the pet has.
					if petPosition > 0 then
						local had = self:Rank(chain.ability.ranks[petPosition])
						entry.net = math.max(0, rank.tp - (had and had.tp or 0))
					end
					if (pet.level or 0) < rank.petLevel then
						category = "level"
					elseif pet.free and entry.net > pet.free then
						category = "points"
					else
						category = "teach"
					end
				else
					category = "learned"
				end
			elseif entry.trainer then
				entry.level = entry.trainer.level
				category = "trainer"
			elseif beasts and not (beasts[spell] and #beasts[spell] > 0) then
				category = "unknown"
			else
				category = "taming"
				entry.beasts = beasts and #beasts[spell] or nil
			end
			entry.category = category
			local group = out.byKey[category]
			group.entries[#group.entries + 1] = entry
			if category == "teach" then out.teach = out.teach + 1 end
		end
	end
	return out
end
