-- EldoUI Loot Sim: gear changes on a character sheet.
--
-- The reader takes the sheet with what you wear. To rate another item the
-- sim takes the worn item's stats off and puts the new one's on, with the
-- public Classic stat rules (Data.lua): strength and agility to attack
-- power, agility to crit, intellect to mana and spell crit, spirit and mana
-- per 5 to regeneration. Item stats come from the same place the rest of
-- EldoUI reads them (E.ItemScore: the game's item stats, "Equip:" lines and
-- EldoUI_LootData); weapon damage and speed from EldoUI_LootData's record.
--
-- Gear.Stats(itemID) -> stats or nil (nil: no numbers for this item yet; a
--   miss is not remembered, so the numbers show once the game has them)
-- Gear.Apply(sheet, changes) -> new sheet, missing (changes: slot -> itemID
--   or false for an empty slot; missing: itemIDs without numbers; a
--   two-hander in slot 16 empties slot 17 unless changes names slot 17)
-- Gear.AddStats(sheet, stats) -> new sheet with extra stats (stat values)
local _, S = ...
local D = S.Data

local Gear = {}
S.Gear = Gear

local RAW = {
	ITEM_MOD_STRENGTH_SHORT = "str", ITEM_MOD_AGILITY_SHORT = "agi", ITEM_MOD_STAMINA_SHORT = "sta",
	ITEM_MOD_INTELLECT_SHORT = "int", ITEM_MOD_SPIRIT_SHORT = "spi",
	ITEM_MOD_ATTACK_POWER_SHORT = "ap", ITEM_MOD_MELEE_ATTACK_POWER_SHORT = "meleeAp", ITEM_MOD_RANGED_ATTACK_POWER_SHORT = "rap",
	ITEM_MOD_FERAL_ATTACK_POWER_SHORT = "feralAp",
	ITEM_MOD_SPELL_POWER_SHORT = "sp", ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = "sp",
	ITEM_MOD_MANA_REGENERATION_SHORT = "mp5", ITEM_MOD_POWER_REGEN0_SHORT = "mp5",
}
local RATINGS = {
	ITEM_MOD_CRIT_RATING_SHORT = { "crit", 9 }, ITEM_MOD_CRIT_MELEE_RATING_SHORT = { "crit", 9 },
	ITEM_MOD_CRIT_RANGED_RATING_SHORT = { "rangedCrit", 10 }, ITEM_MOD_CRIT_SPELL_RATING_SHORT = { "spellCrit", 11 },
	ITEM_MOD_HIT_RATING_SHORT = { "hit", 6 }, ITEM_MOD_HIT_MELEE_RATING_SHORT = { "hit", 6 },
	ITEM_MOD_HIT_SPELL_RATING_SHORT = { "spellHit", 8 },
}

local function Secret(value)
	return issecretvalue and issecretvalue(value)
end

local function Engine()
	return S.E and S.E.ItemScore
end

local function Percent(cr, value)
	local engine = Engine()
	if engine and engine.RatingPercent then return engine.RatingPercent(cr, value) end
	return value
end

-- Weapon damage "min-max[+min-max:school]@delay" from a LootData record.
local function RecordWeapon(itemID)
	local LG = S.E and S.E.LootGuide
	local record = LG and LG.ItemRecord and LG:ItemRecord(itemID)
	local weapon = record and record.weapon
	if type(weapon) ~= "string" then return end
	local delay = tonumber(weapon:match("@(%d+)$"))
	local low, high = weapon:match("^(%d+)%-(%d+)")
	if not (delay and low) then return end
	return tonumber(low), tonumber(high), delay / 1000
end

local cache = {}
function Gear.ClearCache()
	wipe(cache)
end

function Gear.Stats(itemID)
	itemID = tonumber(itemID)
	if not itemID then return end
	if cache[itemID] ~= nil then return cache[itemID] or nil end
	local engine = Engine()
	local raw = engine and engine.RawStats and engine:RawStats("item:" .. itemID)
	local _, _, _, equipLoc, _, classID, subclassID = C_Item.GetItemInfoInstant(itemID)
	if Secret(equipLoc) then
		cache[itemID] = false
		return
	end
	if type(raw) ~= "table" then
		-- Not cached: the game may hand the stats out a moment later, so ask
		-- it to load the item and try again on the next call.
		if C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(itemID) end
		return
	end
	local stats = {}
	for key, value in pairs(raw) do
		value = not Secret(value) and tonumber(value)
		if value and value ~= 0 then
			if RAW[key] then
				stats[RAW[key]] = (stats[RAW[key]] or 0) + value
			elseif RATINGS[key] then
				local rule = RATINGS[key]
				stats[rule[1]] = (stats[rule[1]] or 0) + Percent(rule[2], value)
				if key == "ITEM_MOD_CRIT_RATING_SHORT" then stats.spellCritAlso = true end
			elseif key == "ITEM_MOD_DAMAGE_PER_SECOND_SHORT" then
				stats.dps = value
			end
		end
	end
	if classID == 2 then
		local low, high, speed = RecordWeapon(itemID)
		stats.weapon = { min = low, max = high, speed = speed, kind = D.WEAPON_KIND[subclassID or -1] or "weapon",
			twoHand = D.TWO_HAND[subclassID or -1] or equipLoc == "INVTYPE_2HWEAPON" or false, dps = stats.dps,
			ranged = equipLoc == "INVTYPE_RANGED" or equipLoc == "INVTYPE_RANGEDRIGHT" or equipLoc == "INVTYPE_THROWN" }
	end
	stats.equipLoc = equipLoc
	cache[itemID] = stats
	return stats
end

---------------------------------------------------------------------------
-- Copy and change a sheet
---------------------------------------------------------------------------
local function Copy(value)
	if type(value) ~= "table" then return value end
	local out = {}
	for key, item in pairs(value) do
		if key == "spells" or key == "mods" or key == "enchants" or key == "pet" then
			out[key] = item -- read-only parts are shared
		else
			out[key] = Copy(item)
		end
	end
	return out
end
Gear.Copy = Copy

local function AddEach(map, value)
	if type(map) ~= "table" then return end
	for school in pairs(map) do map[school] = map[school] + value end
end

-- sign: 1 to put the stats on, -1 to take them off.
local function Put(sheet, stats, sign)
	local info = D.CLASS[sheet.class] or {}
	local level = math.max(10, sheet.level or 60)
	local function Get(key) return (stats[key] or 0) * sign end
	local str, agi, int, spi = Get("str"), Get("agi"), Get("int"), Get("spi")
	sheet.str = (sheet.str or 0) + str
	sheet.agi = (sheet.agi or 0) + agi
	sheet.int = (sheet.int or 0) + int
	sheet.spi = (sheet.spi or 0) + spi
	local apAgi = info.apAgi or 0
	if sheet.form == "cat" then apAgi = apAgi + (info.apAgiCat or 0) end
	sheet.ap = (sheet.ap or 0) + str * (info.apStr or 1) + agi * apAgi + Get("ap") + Get("meleeAp")
		+ (sheet.form and Get("feralAp") or 0)
	-- Careful Aim turns Intellect into ranged attack power.
	local special = sheet.mods and sheet.mods.special
	local rapInt = special and special.carefulAim or 0
	sheet.rap = (sheet.rap or 0) + agi * (info.rapAgi or 0) + int * rapInt + Get("ap") + Get("rap")
	local critPer = (info.critAgi or 20) * level / 60
	sheet.crit = (sheet.crit or 0) + agi / critPer + Get("crit")
	sheet.rangedCrit = (sheet.rangedCrit or sheet.crit) + agi / critPer + Get("crit") + Get("rangedCrit")
	sheet.hit = (sheet.hit or 0) + Get("hit")
	sheet.spellHit = (sheet.spellHit or 0) + Get("spellHit")
	local spellCrit = Get("spellCrit") + (stats.spellCritAlso and Get("crit") or 0)
	if info.spellCritInt then spellCrit = spellCrit + int / (info.spellCritInt * level / 60) end
	if type(sheet.spellCrit) == "table" then AddEach(sheet.spellCrit, spellCrit) else sheet.spellCrit = (sheet.spellCrit or 0) + spellCrit end
	local sp = Get("sp")
	if type(sheet.spellPower) == "table" then AddEach(sheet.spellPower, sp) else sheet.spellPower = (sheet.spellPower or 0) + sp end
	if info.power == "mana" and (sheet.maxPower or 0) > 0 then
		sheet.maxPower = sheet.maxPower + int * D.MANA_PER_INT
		sheet.power = sheet.maxPower
		sheet.regen = sheet.regen or { idle = 0, casting = 0 }
		local spiritRegen = info.regen and spi / info.regen[2] / 2 or 0
		local mp5 = Get("mp5") / 5
		sheet.regen.idle = math.max(0, sheet.regen.idle + spiritRegen + mp5)
		sheet.regen.casting = math.max(0, sheet.regen.casting + mp5)
	end
end
Gear.Put = Put

-- Weapon numbers for a new weapon in a hand.
local function NewWeapon(stats, worn)
	local weapon = stats.weapon
	if not weapon then return end
	local speed = weapon.speed or (worn and worn.speed) or (weapon.twoHand and 3.5 or 2.5)
	local low, high = weapon.min, weapon.max
	if not low then
		if not weapon.dps then return end
		local avg = weapon.dps * speed
		low, high = avg * 0.8, avg * 1.2
	end
	return { min = low, max = high, speed = speed, kind = weapon.kind, twoHand = weapon.twoHand,
		skill = worn and worn.skill or nil, itemID = nil, estimated = weapon.min == nil }
end

local HAND = { [16] = "mh", [17] = "oh", [18] = "ranged" }

-- True when the item is a two-handed weapon (it empties the off hand).
function Gear.IsTwoHand(itemID)
	local stats = itemID and Gear.Stats(itemID)
	return stats and stats.weapon and stats.weapon.twoHand or false
end

function Gear.Apply(sheet, changes)
	local out = Copy(sheet)
	local missing = {}
	out.gear = out.gear or {}
	-- A two-hander in the main hand takes the off hand's item off too.
	if changes[17] == nil and Gear.IsTwoHand(changes[16]) then
		local copy = { [17] = false }
		for slot, itemID in pairs(changes) do copy[slot] = itemID end
		changes = copy
	end
	for slot, itemID in pairs(changes) do
		local worn = sheet.gear and sheet.gear[slot]
		if worn ~= itemID then
			local wornStats = worn and Gear.Stats(worn)
			local newStats = itemID and Gear.Stats(itemID)
			if itemID and not newStats then
				missing[#missing + 1] = itemID
			elseif worn and not wornStats then
				missing[#missing + 1] = worn
			else
				if wornStats then Put(out, wornStats, -1) end
				if newStats then Put(out, newStats, 1) end
				local hand = HAND[slot]
				if hand and not out.form then
					if newStats and newStats.weapon then
						local weapon = NewWeapon(newStats, sheet[hand])
						if weapon then
							weapon.skill = weapon.skill or (out.level or 60) * 5
							weapon.itemID = itemID
							out[hand] = weapon
							if hand == "mh" and weapon.twoHand then out.oh = nil end
						else
							missing[#missing + 1] = itemID
						end
					elseif hand ~= "ranged" or not itemID then
						if hand == "oh" then out.oh = nil elseif hand == "mh" and not itemID then out.mh = nil end
					end
				end
				out.gear[slot] = itemID or nil
			end
		end
	end
	return out, missing
end

-- stats: { str = 20 } and so on (the "value of one more point" runs).
function Gear.AddStats(sheet, stats)
	local out = Copy(sheet)
	Put(out, stats, 1)
	return out
end
