-- EldoUI Loot Sim: the character reader.
--
-- Reads your own character sheet out of combat: stats, attack power, crit,
-- hit, spell power, weapon damage and speed, weapon skill, mana and its
-- regeneration, the ranks of your spells (from their own descriptions),
-- talents, your buffs, weapon enchants, the form you are in and your pet.
-- Only the player's own data the game shows on the character sheet and in
-- the spellbook; never combat events or anything about other units. Every
-- value is checked with issecretvalue before it is used, and the reader
-- refuses to run in combat.
--
-- Reader.Read() -> sheet, report   or   nil, reason ("combat", "class")
-- Reader.ApplyTalent(mods, def, rank) adds one talent's effect to mods.
local _, S = ...
local D = S.Data

local Reader = {}
S.Reader = Reader

local SCHOOLS = { holy = 2, fire = 3, nature = 4, frost = 5, shadow = 6, arcane = 7 }
local ENGLISH = { enUS = true, enGB = true }

local function Secret(value)
	return issecretvalue and issecretvalue(value)
end

-- pcall a game function; secret values come back as nil.
local Read = S.E.PlainCallEach
Reader.Call = Read

local function Num(value)
	if Secret(value) then return end
	return tonumber(value)
end

-- "1,044" or "1.044" -> 1044 (the client's own separators).
local function ParseNumber(text)
	local thousands = rawget(_G, "LARGE_NUMBER_SEPARATOR")
	if type(thousands) == "string" and thousands ~= "" then text = text:gsub("%" .. thousands, "") end
	local decimal = rawget(_G, "DECIMAL_SEPARATOR")
	if type(decimal) == "string" and decimal ~= "" and decimal ~= "." then text = text:gsub("%" .. decimal, ".") end
	return tonumber((text:gsub(",", "")))
end

-- Numbers in a spell description, in order; percentIndex is the first
-- one followed by "%", afterPercent the one after it.
local function Numbers(text)
	local out = {}
	if type(text) ~= "string" then return out end
	for digits, percent in text:gmatch("(%d[%d,%.]*)(%%?)") do
		local value = ParseNumber((digits:gsub("[%.,]$", "")))
		if value then
			out[#out + 1] = value
			if percent == "%" and not out.percentIndex then
				out.percentIndex = #out
			elseif out.percentIndex and not out.afterPercent then
				out.afterPercent = #out
			end
		end
	end
	return out
end
Reader.Numbers = Numbers

-- Values of one ability from its description (falls back to the table).
function Reader.ParseSpell(def, text, level)
	local values = {}
	local nums = Numbers(text)
	local parse = def.parse
	local nextIndex
	if parse == "range" and nums[1] and nums[2] then
		values.min, values.max, nextIndex = nums[1], nums[2], 3
	elseif parse == "first" and nums[1] then
		if def.kind == "queue" or def.weapon or (def.kind == "ranged" and def.weapon) then
			values.bonus = nums[1]
		elseif def.mana then
			values.mana = nums[1]
		elseif def.rap then
			values.rap = nums[1]
		else
			values.min, values.max = nums[1], nums[1]
		end
		nextIndex = 2
	elseif parse == "percent" and nums.percentIndex then
		values.apPct = nums[nums.percentIndex]
	elseif parse == "afterPercent" and nums.afterPercent then
		values.bonus = nums[nums.afterPercent]
	elseif parse == "perTick" and nums[1] then
		values.min = nums[1] * (def.ticks or 1)
		values.max = values.min
	end
	if def.dot and nextIndex and nums[nextIndex] then values.dot = nums[nextIndex] end
	values.parsed = next(values) ~= nil
	if not values.parsed then
		if def.min then
			values.min, values.max = D.Fallback(def.min, level), D.Fallback(def.max, level)
		end
		if def.bonus then values.bonus = D.Fallback(def.bonus, level) end
		if def.dot then values.dot = D.Fallback(def.dot, level) end
	end
	return values
end

---------------------------------------------------------------------------
-- Talents and buffs -> mods
---------------------------------------------------------------------------
local function Add(map, key, value)
	map[key] = (map[key] or 0) + value
end

function Reader.ApplyTalent(mods, def, rank)
	mods.dmg = mods.dmg or {}
	mods.crit = mods.crit or {}
	mods.critChance = mods.critChance or {}
	mods.cast = mods.cast or {}
	mods.cost = mods.cost or {}
	mods.cd = mods.cd or {}
	mods.special = mods.special or {}
	for field, map in pairs({ dmg = mods.dmg, crit = mods.crit, critChance = mods.critChance, cast = mods.cast, cost = mods.cost, cd = mods.cd }) do
		for suffix = 1, 3 do
			local entry = def[field .. (suffix == 1 and "" or tostring(suffix))]
			if entry then Add(map, entry[1], entry[2] * rank) end
		end
	end
	if def.special then
		local value = def.values and def.values[math.min(rank, #def.values)] or (def.per or 0) * rank
		mods.special[def.special] = (mods.special[def.special] or 0) + value
	end
end

---------------------------------------------------------------------------
-- Parts of the sheet
---------------------------------------------------------------------------
local function WeaponInfo(slot)
	local itemID = Num(Read(GetInventoryItemID, "player", slot))
	if not itemID then return end
	local _, _, _, equipLoc, _, classID, subclassID = Read(C_Item.GetItemInfoInstant, itemID)
	if classID ~= 2 then return end
	local kind = D.WEAPON_KIND[subclassID or -1] or "weapon"
	return { itemID = itemID, kind = kind, twoHand = D.TWO_HAND[subclassID or -1] or equipLoc == "INVTYPE_2HWEAPON" or false }
end

local function Form()
	local id = Num(Read(rawget(_G, "GetShapeshiftFormID")))
	if id == 1 then return "cat" end
	if id == 5 or id == 8 then return "bear" end
	if id == 31 then return "moonkin" end
end

-- Weapon skill of a weapon kind from the game's skill list (rank plus the
-- bonus from race, gear and enchants); nil when the list does not have it.
local function SkillLine(skillID)
	local info = C_SkillInfo
	if not (info and skillID) then return end
	local function Value(line)
		if type(line) ~= "table" or line.isHeader or Num(line.skillID) ~= skillID then return end
		local rank = Num(line.rank)
		if not rank or rank <= 0 then return end
		return rank + (Num(line.modifier) or 0) + (Num(line.tempPoints) or 0)
	end
	local value = Value(Read(info.GetSkillLineInfoByID, skillID))
	if value then return value end
	for index = 1, Num(Read(info.GetNumSkillLines)) or 0 do
		value = Value(Read(info.GetSkillLineInfo, index))
		if value then return value end
	end
end

local function WeaponSkill(sheet, slot)
	local itemID = Num(Read(GetInventoryItemID, "player", slot))
	local subclassID, classID, _
	if itemID then _, _, _, _, _, classID, subclassID = Read(C_Item.GetItemInfoInstant, itemID) end
	local skillID
	if classID == 2 then
		skillID = D.WEAPON_SKILL[subclassID or -1]
	elseif slot == 16 then
		skillID = D.UNARMED_SKILL
	end
	local value = SkillLine(skillID)
	if value then return value end
	-- No skill line to read: the usual skill for the level, and the
	-- result page says it is an estimate.
	if skillID then sheet.skillEstimated = true end
	return sheet.level * 5
end

local function Weapons(sheet)
	local ap = sheet.ap or 0
	local mainSpeed, offSpeed = Read(UnitAttackSpeed, "player")
	local minMain, maxMain, minOff, maxOff, _, _, percent = Read(UnitDamage, "player")
	percent = Num(percent) or 1
	if percent <= 0 then percent = 1 end
	-- Weapon skill comes from the skill list.
	local skill, offSkill = WeaponSkill(sheet, 16), WeaponSkill(sheet, 17)
	local rangedSkill
	mainSpeed, offSpeed = Num(mainSpeed), Num(offSpeed)
	if mainSpeed and mainSpeed > 0 and Num(minMain) then
		local info = WeaponInfo(16) or { kind = sheet.form and "paw" or "fist", twoHand = false }
		local apPart = ap / 14 * mainSpeed
		info.min = math.max(1, Num(minMain) / percent - apPart)
		info.max = math.max(info.min, (Num(maxMain) or minMain) / percent - apPart)
		-- In a form the game reads the Feral Combat weapon skill.
		info.speed, info.skill = mainSpeed, sheet.form and (SkillLine(D.FERAL_SKILL) or sheet.level * 5) or skill
		if sheet.form then info.kind, info.twoHand = "paw", false end
		sheet.mh = info
	end
	if not sheet.form and offSpeed and offSpeed > 0 and Num(minOff) and Num(minOff) > 0 then
		local info = WeaponInfo(17)
		if info then
			local apPart = ap / 14 * offSpeed
			info.min = math.max(1, Num(minOff) * 2 / percent - apPart)
			info.max = math.max(info.min, (Num(maxOff) or minOff) * 2 / percent - apPart)
			info.speed, info.skill = offSpeed, offSkill
			sheet.oh = info
		end
	end
	local speed, minRanged, maxRanged, _, _, rangedPercent = Read(UnitRangedDamage, "player")
	speed = Num(speed)
	if speed and speed > 0 and Num(minRanged) and Num(minRanged) > 0 then
		local info = WeaponInfo(18) or { kind = "ranged" }
		rangedPercent = Num(rangedPercent) or 1
		if rangedPercent <= 0 then rangedPercent = 1 end
		local apPart = (sheet.rap or 0) / 14 * speed
		info.min = math.max(1, Num(minRanged) / rangedPercent - apPart)
		info.max = math.max(info.min, (Num(maxRanged) or minRanged) / rangedPercent - apPart)
		rangedSkill = WeaponSkill(sheet, 18)
		info.speed, info.skill = speed, rangedSkill
		sheet.ranged = info
	end
end

local function Spells(sheet, report)
	local defs = D.SPELLS[sheet.class] or {}
	local spell = C_Spell or {}
	sheet.spells = {}
	report.spells = {}
	for key, def in pairs(defs) do
		local name = Read(spell.GetSpellName, def.id)
		local info = name and Read(spell.GetSpellInfo, name)
		local id = type(info) == "table" and Num(info.spellID) or nil
		local known = id and (Read(rawget(_G, "IsPlayerSpell"), id) or Read(rawget(_G, "IsSpellKnown"), id))
		if id and known then
			local text = Read(spell.GetSpellDescription, id)
			local values = Reader.ParseSpell(def, text, sheet.level)
			values.known, values.spellID, values.name = true, id, info.name or name
			local cast = Num(info.castTime)
			if cast and def.cast then
				values.cast, values.castLive = cast / 1000, true
			end
			local costs = Read(spell.GetSpellPowerCost, id)
			if type(costs) == "table" and type(costs[1]) == "table" and Num(costs[1].cost) then
				values.cost, values.costLive = Num(costs[1].cost), true
			end
			local learned = Read(spell.GetSpellLevelLearned, id)
			if Num(learned) and Num(learned) > 0 and Num(learned) < 20 then
				values.levelPenalty = S.Combat.LowLevelPenalty(Num(learned))
			end
			sheet.spells[key] = values
			report.spells[#report.spells + 1] = { key = key, name = values.name, parsed = values.parsed }
		end
	end
	table.sort(report.spells, function(a, b) return tostring(a.name) < tostring(b.name) end)
	report.notSimulated = {}
	for _, entry in ipairs(D.NOT_SIMULATED[sheet.class] or {}) do
		local name = Read(spell.GetSpellName, entry[1])
		local info = name and Read(spell.GetSpellInfo, name)
		if type(info) == "table" and Num(info.spellID) then
			report.notSimulated[#report.notSimulated + 1] = { name = name, reason = entry[2] }
		end
	end
end

-- Talents come from the Loot Guide's reader (the game's talent tree, or
-- the old talent tabs where a client has them).
local function Talents(sheet, report, mods)
	report.talentsPlayed, report.talentsOther = {}, {}
	local LG = S.E and S.E.LootGuide
	local talents = LG and LG.TalentRanks and LG:TalentRanks()
	local defs = D.TALENTS[sheet.class] or {}
	local english = ENGLISH[(Read(GetLocale)) or ""]
	for _, talent in ipairs(talents and talents.list or {}) do
		local name = talent.name or (talent.spellID and ("#" .. talent.spellID)) or "?"
		local def = english and defs[name]
		local label = ("%s %d/%d"):format(name, talent.rank, talent.maxRank or talent.rank)
		if def then
			Reader.ApplyTalent(mods, def, talent.rank)
			report.talentsPlayed[#report.talentsPlayed + 1] = label
		else
			report.talentsOther[#report.talentsOther + 1] = label
		end
	end
	report.talentKey = talents and talents.key or ""
	report.talentsByName = english and true or false
end

local function Auras(report, mods)
	report.buffs = {}
	local get = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
	if not get then return end
	for index = 1, 40 do
		local aura = Read(get, "player", index, "HELPFUL")
		if type(aura) ~= "table" then break end
		local spellID, name = Num(aura.spellId), aura.name
		if spellID and not Secret(name) then
			local effect = D.AURAS[spellID]
			if effect then
				mods.dmg = mods.dmg or {}
				Add(mods.dmg, effect[1], effect[2])
				report.buffs[#report.buffs + 1] = name
			end
		end
	end
end

local function PermanentEnchant(slot)
	local link = Read(GetInventoryItemLink, "player", slot)
	if type(link) ~= "string" then return end
	return tonumber(link:match("item:%d+:(%d+)"))
end

local function Enchants(sheet, report)
	sheet.enchants, report.enchants = {}, {}
	local info = (C_Item and C_Item.GetWeaponEnchantInfo) or rawget(_G, "GetWeaponEnchantInfo")
	-- Without it, temporary enchants (poisons, oils, shaman weapons) stay
	-- unknown: tooltip text is never matched against English words.
	report.tempEnchantsUnknown = info == nil or nil
	local hasMain, _, _, mainID, hasOff, _, _, offID = Read(info)
	-- A hand can carry both: a permanent enchant (Crusader) and a temporary
	-- one (a poison, Windfury). Each is read on its own, so an unknown
	-- temporary enchant never hides the known permanent one.
	for slot, hand in pairs({ [16] = "mh", [17] = "oh" }) do
		local temp
		if hand == "mh" then temp = hasMain and Num(mainID) else temp = hasOff and Num(offID) end
		local list = {}
		for _, id in ipairs({ PermanentEnchant(slot) or false, temp or false }) do
			local def = id and D.ENCHANTS[id]
			if def then
				list[#list + 1] = def
				report.enchants[#report.enchants + 1] = def.kind
			end
		end
		if #list > 0 then sheet.enchants[hand] = list end
	end
end

local function Pet(sheet, report)
	if not Read(UnitExists, "pet") then return end
	local minDamage, maxDamage = Read(UnitDamage, "pet")
	local speed = Read(UnitAttackSpeed, "pet")
	minDamage, maxDamage, speed = Num(minDamage), Num(maxDamage), Num(speed)
	local name = Read(UnitName, "pet")
	report.pet = type(name) == "string" and name or nil
	if minDamage and minDamage > 0 and speed and speed > 0 then
		sheet.pet = { min = minDamage, max = maxDamage or minDamage, speed = speed, crit = 5, level = Num(Read(UnitLevel, "pet")) or sheet.level }
	else
		sheet.petDismissed = true
	end
end

---------------------------------------------------------------------------
-- Read
---------------------------------------------------------------------------
function Reader.InCombat()
	return (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and Read(UnitAffectingCombat, "player")) and true or false
end

function Reader.Read()
	if Reader.InCombat() then return nil, "combat" end
	local _, class = Read(UnitClass, "player")
	if not D.CLASS[class or ""] then return nil, "class" end
	local sheet = { class = class, level = Num(Read(UnitLevel, "player")) or 1 }
	local report = { stats = {} }
	local engine = S.E and S.E.ItemScore
	sheet.spec = engine and engine.PlayerSpec and engine:PlayerSpec() or nil
	sheet.form = Form()
	if sheet.form == "moonkin" then sheet.form = nil end
	for index, key in ipairs({ "str", "agi", "sta", "int", "spi" }) do
		local _, value = Read(UnitStat, "player", index)
		sheet[key] = Num(value) or 0
	end
	local base, pos, neg = Read(UnitAttackPower, "player")
	sheet.ap = (Num(base) or 0) + (Num(pos) or 0) + (Num(neg) or 0)
	base, pos, neg = Read(UnitRangedAttackPower, "player")
	sheet.rap = (Num(base) or 0) + (Num(pos) or 0) + (Num(neg) or 0)
	sheet.crit = Num(Read(GetCritChance)) or 0
	sheet.rangedCrit = Num(Read(rawget(_G, "GetRangedCritChance"))) or sheet.crit
	sheet.hit = Num(Read(rawget(_G, "GetHitModifier"))) or 0
	sheet.spellHit = Num(Read(rawget(_G, "GetSpellHitModifier"))) or 0
	local rangedHit = Num(Read(rawget(_G, "GetRangedHitModifier")))
	local rangedRating = Num(rawget(_G, "CR_HIT_RANGED"))
	local rangedBonus = rangedRating and Num(Read(rawget(_G, "GetCombatRatingBonus"), rangedRating)) or 0
	sheet.rangedHit = rangedHit and rangedHit + (rangedBonus or 0) or sheet.hit
	local mhExpertise, ohExpertise, rangedExpertise = Read(rawget(_G, "GetExpertise"))
	sheet.expertise = { mh = Num(mhExpertise) or 0, oh = Num(ohExpertise) or 0, ranged = Num(rangedExpertise) or 0 }
	sheet.spellCrit, sheet.spellPower = {}, {}
	for school, index in pairs(SCHOOLS) do
		sheet.spellCrit[school] = Num(Read(rawget(_G, "GetSpellCritChance"), index)) or 0
		sheet.spellPower[school] = Num(Read(rawget(_G, "GetSpellBonusDamage"), index)) or 0
	end
	sheet.maxPower = Num(Read(UnitPowerMax, "player", 0)) or 0
	sheet.power = sheet.maxPower
	local idle, casting = Read(rawget(_G, "GetManaRegen"))
	sheet.regen = { idle = Num(idle) or 0, casting = Num(casting) or 0 }
	Weapons(sheet)
	sheet.gear = {}
	for slot = 1, 18 do
		local itemID = Num(Read(GetInventoryItemID, "player", slot))
		if itemID then sheet.gear[slot] = itemID end
	end
	local mods = {}
	Spells(sheet, report)
	Talents(sheet, report, mods)
	Auras(report, mods)
	sheet.mods = mods
	Enchants(sheet, report)
	Pet(sheet, report)
	local stats = report.stats
	stats[#stats + 1] = { "ap", sheet.ap }
	stats[#stats + 1] = { "rap", sheet.rap }
	stats[#stats + 1] = { "crit", sheet.crit }
	stats[#stats + 1] = { "hit", sheet.hit }
	local best = 0
	for _, value in pairs(sheet.spellPower) do best = math.max(best, value) end
	stats[#stats + 1] = { "spellPower", best }
	stats[#stats + 1] = { "spellHit", sheet.spellHit }
	stats[#stats + 1] = { "mana", sheet.maxPower }
	report.form = sheet.form
	report.skillEstimated = sheet.skillEstimated
	return sheet, report
end
