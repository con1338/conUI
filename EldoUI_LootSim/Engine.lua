-- EldoUI Loot Sim: the fight engine.
--
-- An event queue (a binary heap ordered by time) runs one fight against a
-- training dummy: white swings, auto shots, the pet, spell casts, damage
-- over time, power ticks and the class model's decisions. Every roll comes
-- from a named dice stream of the fight's seed (Rng.lua), so a seed always
-- gives the same fight and two gear sets can be compared on the same dice.
--
-- Input is a character sheet (from Reader.lua, or any table of this shape):
--   class, level, ap, rap, crit, rangedCrit, hit, spellHit, spellCrit
--   (number or per school), spellPower (number or per school), mh / oh /
--   ranged = { min, max, speed, kind, skill, twoHand }, power, maxPower,
--   regen = { idle, casting } (mana per second), spells = { key = values
--   read from your spellbook }, mods (talents and buffs), enchants (per
--   hand one enchant, or a list: permanent and temporary), pet,
--   form, str.
-- Output: total damage, damage per second and the damage per source.
--
-- Nothing here touches the game: the engine only works on the sheet.
local _, S = ...
local C = S.Combat
local D = S.Data
local Rng = S.Rng

local Engine = {}
S.Engine = Engine

local floor = math.floor
local max, min = math.max, math.min

---------------------------------------------------------------------------
-- Event heap
---------------------------------------------------------------------------
local function Less(a, b)
	if a.t ~= b.t then return a.t < b.t end
	return a.seq < b.seq
end

local function Push(heap, event)
	local n = heap.n + 1
	heap.n = n
	heap[n] = event
	local index = n
	while index > 1 do
		local parent = floor(index / 2)
		if Less(heap[index], heap[parent]) then
			heap[index], heap[parent] = heap[parent], heap[index]
			index = parent
		else
			break
		end
	end
end

local function Pop(heap)
	local n = heap.n
	if n == 0 then return end
	local top = heap[1]
	heap[1] = heap[n]
	heap[n] = nil
	n = n - 1
	heap.n = n
	local index = 1
	while true do
		local left, right, smallest = index * 2, index * 2 + 1, index
		if left <= n and Less(heap[left], heap[smallest]) then smallest = left end
		if right <= n and Less(heap[right], heap[smallest]) then smallest = right end
		if smallest == index then break end
		heap[index], heap[smallest] = heap[smallest], heap[index]
		index = smallest
	end
	return top
end
Engine.Push, Engine.Pop = Push, Pop

---------------------------------------------------------------------------
-- The fight
---------------------------------------------------------------------------
local Fight = {}
Fight.__index = Fight
Engine.Fight = Fight

local function SpellPower(sheet, school)
	local power = sheet.spellPower
	if type(power) == "table" then return (power[school] or 0) + (power.all or 0) end
	return tonumber(power) or 0
end

local function SpellCrit(sheet, school)
	local crit = sheet.spellCrit
	if type(crit) == "table" then return crit[school] or crit.all or 0 end
	return tonumber(crit) or 0
end

-- Merge the sheet's spell values over the table definition.
local function Spells(sheet)
	local defs = D.SPELLS[sheet.class] or {}
	local out = {}
	for key, values in pairs(sheet.spells or {}) do
		local def = defs[key]
		if def and values.known ~= false then
			out[key] = setmetatable(values, { __index = def })
		end
	end
	return out
end

-- opts: seed, length (s), targetLevel, model, hook (fn(fight) every hundred
-- events, for the scheduler's frame budget).
function Engine.New(sheet, model, opts)
	opts = opts or {}
	local f = setmetatable({}, Fight)
	f.sheet, f.model = sheet, model
	f.length = opts.length or 60
	f.level = sheet.level or 60
	f.targetLevel = opts.targetLevel or f.level
	f.rng = Rng.New(opts.seed or 1)
	f.dice = {}
	for _, name in ipairs({ "melee", "offhand", "yellow", "spell", "proc", "pet", "ranged", "damage", "start", "periodic" }) do
		f.dice[name] = f.rng:Stream(name)
	end
	f.hook, f.hookEvery = opts.hook, opts.hookEvery or 100
	f.heap = { n = 0 }
	f.seq = 0
	f.t = 0
	f.events = 0
	f.sources = {}
	f.total = 0
	f.spells = Spells(sheet)
	f.mods = sheet.mods or {}
	f.cds, f.auras, f.dots = {}, {}, {}
	f.cp = 0
	f.gcd, f.busy = 0, 0
	f.lastSpend = -10
	f.nextThink = math.huge
	f.thinkToken = 0
	local class = D.CLASS[sheet.class] or {}
	f.classInfo = class
	f.powerType = sheet.form == "cat" and "energy" or sheet.form == "bear" and "rage" or class.power or "mana"
	if f.powerType == "rage" then
		f.power, f.maxPower = sheet.startRage or 0, 100
	elseif f.powerType == "energy" then
		f.power, f.maxPower = D.ENERGY_MAX, D.ENERGY_MAX
	else
		f.maxPower = sheet.maxPower or sheet.power or 0
		f.power = sheet.power or f.maxPower
	end
	f.target = { level = f.targetLevel, armor = opts.targetArmor or C.TargetArmor(f.targetLevel), armorDown = 0, sunders = 0 }
	f.used = {}
	return f
end

function Fight:Schedule(t, fn, a, b)
	self.seq = self.seq + 1
	Push(self.heap, { t = t, seq = self.seq, fn = fn, a = a, b = b })
end

function Fight:Spell(key)
	return self.spells[key]
end

function Fight:Knows(key)
	return self.spells[key] ~= nil
end

function Fight:Aura(key)
	local aura = self.auras[key]
	if aura and aura.expires > self.t then return aura end
end

function Fight:AddAura(key, duration, data)
	local aura = data or {}
	aura.expires = self.t + duration
	self.auras[key] = aura
	return aura
end

function Fight:Ready(key)
	local ready = self.cds[key]
	return not ready or ready <= self.t
end

---------------------------------------------------------------------------
-- Modifiers
---------------------------------------------------------------------------
local function Bonus(map, key)
	return map and map[key] or 0
end

-- tags: the targets a talent can name for this hit.
local function Tags(self, spell, hand)
	local tags = { "all" }
	local school = spell and spell.school or "physical"
	if school == "physical" then
		tags[#tags + 1] = "physical"
		local weapon = hand == "oh" and self.sheet.oh or hand == "ranged" and self.sheet.ranged or self.sheet.mh
		if hand ~= "ranged" and hand ~= "pet" and weapon then tags[#tags + 1] = weapon.twoHand and "twohand" or "onehand" end
	else
		tags[#tags + 1] = "school:" .. school
	end
	if hand == "oh" then tags[#tags + 1] = "offhand" end
	if hand == "ranged" then tags[#tags + 1] = "ranged" end
	if hand == "pet" then tags[#tags + 1] = "pet" end
	if spell and spell.key then
		tags[#tags + 1] = "spell:" .. spell.key
		if spell.kind == "melee" or spell.kind == "queue" or spell.kind == "finisher" then tags[#tags + 1] = "yellow" end
		if spell.builder then tags[#tags + 1] = "builder" end
	else
		tags[#tags + 1] = "white"
	end
	return tags
end

function Fight:DamageMult(spell, hand)
	local mult = 1
	local dmg = self.mods.dmg
	for _, tag in ipairs(Tags(self, spell, hand)) do mult = mult * (1 + Bonus(dmg, tag)) end
	local school = spell and spell.school or "physical"
	-- Lone Wolf: more damage with no pet out; Focused Fire: with one.
	local wolf = self:Special("loneWolf")
	if wolf and not self.sheet.pet and hand ~= "pet" then mult = mult * (1 + wolf) end
	local focused = self:Special("focusedFire")
	if focused and self.sheet.pet and hand ~= "pet" then mult = mult * (1 + focused) end
	if self:Aura("deathWish") and school == "physical" then mult = mult * 1.2 end
	local power = self:Aura("arcanePower")
	if power and hand ~= "pet" then mult = mult * (1 + power.damage) end
	local vengeance = self:Aura("vengeance")
	if vengeance and (school == "physical" or school == "holy") then mult = mult * (1 + vengeance.value) end
	if school == "shadow" then
		local isb = self:Aura("isb")
		if isb and isb.charges > 0 then mult = mult * (1 + isb.value) end
		local weaving = self:Aura("shadowWeaving")
		if weaving then mult = mult * (1 + 0.03 * weaving.stacks) end
	end
	if school == "nature" then
		local storm = self:Aura("stormstrike")
		if storm and storm.charges > 0 and spell and spell.kind ~= "dot" then
			mult = mult * 1.2
			storm.charges = storm.charges - 1
		end
	end
	return mult
end

function Fight:CritMult(spell, hand)
	local school = spell and spell.school or "physical"
	local physical = school == "physical" or (spell and (spell.kind == "melee" or spell.kind == "ranged" or spell.kind == "finisher"))
	local base = physical and 1 or 0.5
	local extra = 0
	for _, tag in ipairs(Tags(self, spell, hand)) do extra = extra + Bonus(self.mods.crit, tag) end
	return 1 + base * (1 + extra)
end

function Fight:CritBonusChance(spell, hand)
	local extra = 0
	for _, tag in ipairs(Tags(self, spell, hand)) do extra = extra + Bonus(self.mods.critChance, tag) end
	return extra
end

function Fight:Cost(spell)
	local cost = spell.cost or 0
	-- A cost read from the game already has the talents in it.
	if not spell.costLive then cost = cost - Bonus(self.mods.cost, "spell:" .. spell.key) end
	if self.powerType == "mana" then
		local efficiency = self.mods.special and self.mods.special.efficiency
		if efficiency then cost = cost * (1 - efficiency) end
		local power = self:Aura("arcanePower")
		if power then cost = cost * power.costMult end
		if self:Aura("clearcasting") then cost = 0 end
	end
	return max(0, cost)
end

function Fight:CastTime(spell)
	local cast = spell.cast or 0
	if cast <= 0 then return 0 end
	if spell.castLive then return cast end
	return max(0, cast - Bonus(self.mods.cast, "spell:" .. spell.key))
end

function Fight:Cooldown(spell)
	return max(0, (spell.cd or 0) - Bonus(self.mods.cd, "spell:" .. spell.key))
end

function Fight:Special(name)
	local special = self.mods.special
	return special and special[name]
end

function Fight:AP()
	local ap = self.sheet.ap or 0
	local crusader = self:Aura("crusader")
	if crusader then ap = ap + crusader.ap end
	return ap
end

function Fight:RAP()
	return (self.sheet.rap or 0) + (self.rapBonus or 0)
end

function Fight:Haste()
	local haste = 1
	local snd = self:Aura("sliceAndDice")
	if snd then haste = haste * (1 + snd.haste) end
	local flurry = self:Aura("bladeFlurry")
	if flurry then haste = haste * (1 + flurry.haste) end
	local f = self.flurryCharges and self.flurryCharges > 0 and self:Special("flurry")
	if f then haste = haste * (1 + f) end
	return haste
end

---------------------------------------------------------------------------
-- Damage bookkeeping
---------------------------------------------------------------------------
local function Source(self, key)
	local source = self.sources[key]
	if not source then
		source = { damage = 0, count = 0, crits = 0, misses = 0 }
		self.sources[key] = source
	end
	return source
end

function Fight:Deal(key, amount, outcome)
	local source = Source(self, key)
	source.count = source.count + 1
	if outcome == "miss" or outcome == "dodge" or outcome == "resist" then
		source.misses = source.misses + 1
		return
	end
	if outcome == "crit" then source.crits = source.crits + 1 end
	amount = max(0, amount or 0)
	source.damage = source.damage + amount
	self.total = self.total + amount
end

function Fight:GainPower(amount)
	if amount <= 0 then return end
	self.power = min(self.maxPower, self.power + amount)
	self:Wake(self.t)
end

function Fight:SpendPower(amount)
	if amount <= 0 then return end
	self.power = self.power - amount
	if self.powerType == "mana" then self.lastSpend = self.t end
end

---------------------------------------------------------------------------
-- Weapon damage
---------------------------------------------------------------------------
function Fight:WeaponRoll(weapon, normalized, ranged)
	if not weapon then return 0 end
	local base = self.dice.damage:Range(weapon.min or 0, weapon.max or 0)
	local speed = weapon.speed or 2
	if normalized then
		speed = ranged and C.NORMALIZED.ranged or weapon.kind == "dagger" and C.NORMALIZED.dagger
			or weapon.twoHand and C.NORMALIZED.twohand or C.NORMALIZED.onehand
	end
	local power = ranged and self:RAP() or self:AP()
	return base + power / 14 * speed
end

local function ArmorMult(self)
	local armor = max(0, self.target.armor - self.target.armorDown)
	return 1 - C.ArmorReduction(armor, self.level)
end

---------------------------------------------------------------------------
-- Procs after a hit
---------------------------------------------------------------------------
local function OnMeleeCrit(self, hand)
	local flurry = self:Special("flurry")
	if flurry then self.flurryCharges = 3 end
	local wounds = self:Special("deepWounds")
	if wounds and hand ~= "ranged" then
		local weapon = self.sheet.mh
		local avg = weapon and ((weapon.min + weapon.max) / 2 + self:AP() / 14 * (weapon.speed or 2)) or 0
		self:ApplyDot("deepWounds", { school = "physical", total = avg * wounds * self:DamageMult(nil, "mh"), ticks = 4, duration = 12, noRoll = true })
	end
	local vengeance = self:Special("vengeance")
	if vengeance then self:AddAura("vengeance", 8, { value = vengeance }) end
end

local Swing

-- One weapon enchant's proc on a hit.
local function EnchantProc(self, hand, weapon, enchant, proc)
	if enchant.kind == "windfury" and hand == "mh" and not self.inWindfury and proc:Chance(20) then
		local bonus = enchant.ap * (1 + (self:Special("windfuryAP") or 0))
		self.inWindfury = true
		self.windfuryAP = bonus
		Swing(self, "mh", true)
		self.windfuryAP = nil
		self.inWindfury = nil
	elseif enchant.kind == "poison" and proc:Chance(20) then
		local hit = C.SpellHitChance(self.targetLevel - self.level, 0)
		if self.dice.spell:Random() * 100 < hit then
			local amount = self.dice.damage:Range(enchant.min, enchant.max) * self:DamageMult({ school = "nature", key = "poison" }, hand)
			self:Deal("poison", amount * (1 - C.ResistFraction(self.targetLevel - self.level, self.level)), "hit")
		else
			self:Deal("poison", 0, "resist")
		end
	elseif enchant.kind == "crusader" and proc:Chance(enchant.ppm * (weapon.speed or 2) / 60 * 100) then
		self:AddAura("crusader", enchant.duration, { ap = enchant.str * (self.classInfo.apStr or 1) })
	elseif enchant.kind == "fiery" and proc:Chance(enchant.ppm * (weapon.speed or 2) / 60 * 100) then
		self:Deal("fiery", enchant.min * self:DamageMult({ school = "fire", key = "fiery" }, hand), "hit")
	elseif enchant.kind == "lifesteal" and proc:Chance(enchant.ppm * (weapon.speed or 2) / 60 * 100) then
		self:Deal("lifesteal", enchant.min * self:DamageMult({ school = "shadow", key = "lifesteal" }, hand), "hit")
	end
end

local function WeaponProcs(self, hand, yellow)
	local weapon = hand == "oh" and self.sheet.oh or self.sheet.mh
	if not weapon then return end
	local enchants = self.sheet.enchants or {}
	-- One enchant, or a list of them (a permanent and a temporary one).
	local enchant = enchants[hand]
	local proc = self.dice.proc
	if enchant then
		if enchant.kind then
			EnchantProc(self, hand, weapon, enchant, proc)
		else
			for _, each in ipairs(enchant) do EnchantProc(self, hand, weapon, each, proc) end
		end
	end
	local sword = self:Special("swordSpec")
	if sword and weapon.kind == "sword" and not self.inExtra and proc:Chance(sword) then
		self.inExtra = true
		Swing(self, "mh", true)
		self.inExtra = nil
	end
	-- Paladin seals.
	local seal = self:Aura("seal")
	if seal and hand == "mh" then
		if seal.kind == "righteousness" then
			local amount = (seal.perSpeed * (weapon.speed or 2) + seal.coef * SpellPower(self.sheet, "holy"))
				* self:DamageMult({ school = "holy", key = "sealOfRighteousness" }, "mh")
			self:Deal("sealOfRighteousness", amount, "hit")
		elseif seal.kind == "command" and proc:Chance(seal.ppm * (weapon.speed or 2) / 60 * 100) then
			local amount = (self:WeaponRoll(weapon) * seal.weaponPct / 100 + seal.coef * SpellPower(self.sheet, "holy"))
				* self:DamageMult({ school = "holy", key = "sealOfCommand" }, "mh")
			local crit = self.dice.yellow:Random() * 100 < (self.sheet.crit or 0)
			self:Deal("sealOfCommand", crit and amount * 2 or amount, crit and "crit" or "hit")
		end
	end
	if not yellow then
		local wrath = self:Special("unbridledWrath")
		if wrath and self.powerType == "rage" and proc:Chance(wrath) then self:GainPower(1) end
	end
end

---------------------------------------------------------------------------
-- White swings
---------------------------------------------------------------------------
-- Expertise of a hand as percent off the target's dodge (the sheet's
-- GetExpertise values: main hand, off hand, ranged).
local function Expertise(sheet, hand)
	local expertise = sheet.expertise
	if type(expertise) ~= "table" then return tonumber(expertise) or 0 end
	return tonumber(expertise[hand]) or 0
end

function Fight:WhiteTable(hand)
	local weapon = hand == "oh" and self.sheet.oh or self.sheet.mh
	return C.WhiteTable({ targetLevel = self.targetLevel, level = self.level, skill = weapon and weapon.skill or self.level * 5,
		hit = self.sheet.hit, crit = (self.sheet.crit or 0), dualWield = self.sheet.oh ~= nil, expertise = Expertise(self.sheet, hand) })
end

function Fight:YellowTable(spell, ranged)
	local weapon = ranged and self.sheet.ranged or self.sheet.mh
	local crit = (ranged and self.sheet.rangedCrit or self.sheet.crit) or 0
	return C.YellowTable({ targetLevel = self.targetLevel, skill = weapon and weapon.skill or self.level * 5, hit = self.sheet.hit,
		crit = crit + self:CritBonusChance(spell, ranged and "ranged" or "mh"), noDodge = ranged or (spell and spell.noDodge),
		expertise = Expertise(self.sheet, ranged and "ranged" or "mh") })
end

local function RageFor(self, damage)
	if self.powerType == "rage" then self:GainPower(C.RageFromDamage(damage, self.level)) end
end

-- One white swing (or the queued Heroic Strike / Maul). extra: a proc
-- swing that does not move the swing timer.
Swing = function(self, hand, extra)
	local weapon = hand == "oh" and self.sheet.oh or self.sheet.mh
	if not weapon then return end
	if hand == "mh" and self.queued and not extra then
		local spell = self.spells[self.queued]
		self.queued = nil
		local cost = spell and self:Cost(spell) or 0
		if spell and self.power >= cost then
			self:SpendPower(cost)
			local base = self:WeaponRoll(weapon) + (spell.bonus or 0)
			self:Yellow(spell, "mh", base)
			return
		end
	end
	self.tables = self.tables or {}
	local tbl = self.tables[hand]
	if not tbl then
		tbl = self:WhiteTable(hand)
		self.tables[hand] = tbl
	end
	local roll = (hand == "oh" and self.dice.offhand or self.dice.melee):Random() * 100
	local key = hand == "oh" and "offhand" or "melee"
	if self.windfuryAP then key = "windfury" end
	local outcome
	if roll < tbl.miss then
		outcome = "miss"
	elseif roll < tbl.miss + tbl.dodge then
		outcome = "dodge"
	elseif roll < tbl.miss + tbl.dodge + tbl.glance then
		outcome = "glance"
	elseif roll < tbl.miss + tbl.dodge + tbl.glance + tbl.crit then
		outcome = "crit"
	else
		outcome = "hit"
	end
	if outcome == "dodge" then self.dodgedAt = self.t end
	if outcome == "miss" or outcome == "dodge" then
		self:Deal(key, 0, outcome)
		return
	end
	local base = self:WeaponRoll(weapon)
	if self.windfuryAP then base = base + self.windfuryAP / 14 * (weapon.speed or 2) end
	local amount = base * self:DamageMult(nil, hand)
	if hand == "oh" then amount = amount * 0.5 end
	if outcome == "glance" then amount = amount * tbl.glanceMult end
	if outcome == "crit" then amount = amount * self:CritMult(nil, hand) end
	amount = amount * ArmorMult(self)
	self:Deal(key, amount, outcome)
	RageFor(self, amount)
	if outcome == "crit" then OnMeleeCrit(self, hand) end
	WeaponProcs(self, hand, false)
end

local function SwingEvent(self, hand)
	Swing(self, hand, false)
	if self.flurryCharges and self.flurryCharges > 0 then self.flurryCharges = self.flurryCharges - 1 end
	local weapon = hand == "oh" and self.sheet.oh or self.sheet.mh
	self:Schedule(self.t + (weapon.speed or 2) / self:Haste(), SwingEvent, hand)
	self:Wake(self.t)
end

---------------------------------------------------------------------------
-- Special attacks
---------------------------------------------------------------------------
-- Returns the outcome ("miss", "dodge", "hit", "crit").
function Fight:Yellow(spell, hand, base, ranged)
	local tbl = self:YellowTable(spell, ranged)
	local roll = self.dice.yellow:Random() * 100
	local key = spell.key
	if roll < tbl.miss then
		self:Deal(key, 0, "miss")
		return "miss"
	end
	if roll < tbl.miss + tbl.dodge then
		self:Deal(key, 0, "dodge")
		self.dodgedAt = self.t
		return "dodge"
	end
	local crit = self.dice.yellow:Random() * 100 < tbl.crit
	local amount = base * self:DamageMult(spell, ranged and "ranged" or hand)
	if crit then amount = amount * self:CritMult(spell, ranged and "ranged" or hand) end
	if spell.school == "physical" then amount = amount * ArmorMult(self) end
	self:Deal(key, amount, crit and "crit" or "hit")
	if crit and not ranged then OnMeleeCrit(self, hand) end
	if not ranged then WeaponProcs(self, hand, true) end
	return crit and "crit" or "hit"
end

---------------------------------------------------------------------------
-- Spells
---------------------------------------------------------------------------
function Fight:SpellHits(spell)
	local hit = C.SpellHitChance(self.targetLevel - self.level, self.sheet.spellHit or 0)
	return self.dice.spell:Random() * 100 < hit
end

local function Resist(self, spell)
	if spell.school == "physical" or spell.school == "holy" then return 1 end
	return 1 - C.ResistFraction(self.targetLevel - self.level, self.level)
end

local function Coefficient(spell, castTime)
	if spell.coef then return spell.coef * (spell.levelPenalty or 1) end
	if spell.kind == "dot" then return C.DotCoefficient(spell.duration) * (spell.levelPenalty or 1) end
	if spell.kind == "channel" then return C.ChannelCoefficient(spell.duration) * (spell.levelPenalty or 1) end
	return C.DirectCoefficient(spell.cast or castTime or 1.5) * (spell.levelPenalty or 1)
end

-- Periodic spell damage can crit on WoW: Forever ("Most periodic effects
-- can critically strike"), with the spell crit chance and multiplier.
-- Bleeds and effects that copy another hit (noRoll) do not roll.
local function PeriodicCrit(self, spell)
	if spell.school == "physical" then return false end
	local chance = SpellCrit(self.sheet, spell.school) + self:CritBonusChance(spell, "spell")
	return self.dice.periodic:Random() * 100 < chance
end

local function DotTick(self, key)
	local dot = self.dots[key]
	if not dot or dot.remaining <= 0 then return end
	dot.remaining = dot.remaining - 1
	local amount = dot.perTick * self:DamageMult(dot.spell, dot.hand)
	if dot.spell.school ~= "physical" then amount = amount * Resist(self, dot.spell) end
	local crit = not dot.noRoll and PeriodicCrit(self, dot.spell)
	if crit then amount = amount * self:CritMult(dot.spell, "spell") end
	self:Deal(key, amount, crit and "crit" or "hit")
	if dot.remaining > 0 then self:Schedule(self.t + dot.interval, DotTick, key) end
end

-- def: { school, total, ticks, duration, noRoll, spell } (spell: for mods).
function Fight:ApplyDot(key, def)
	local spell = def.spell or { key = key, school = def.school, kind = "dot" }
	local old = self.dots[key]
	local total = def.total
	if def.add and old and old.remaining > 0 then total = total + old.perTick * old.remaining end
	local dot = { spell = spell, perTick = total / def.ticks, remaining = def.ticks, interval = def.duration / def.ticks, hand = def.hand,
		noRoll = def.noRoll }
	self.dots[key] = dot
	self.dotExpires = self.dotExpires or {}
	self.dotExpires[key] = self.t + def.duration
	self:Schedule(self.t + dot.interval, DotTick, key)
end

function Fight:DotLeft(key)
	local expires = self.dotExpires and self.dotExpires[key]
	return expires and max(0, expires - self.t) or 0
end

-- A spell with rangedHit (Judgement) rolls a ranged attack's miss chance
-- instead of spell hit: WoW: Forever hotfix of 11 November 2026, Judgement
-- "now considered a Ranged Attack" that "uses the Paladin's Ranged Hit
-- chance". Damage, crit and resists stay a spell's; the hotfix names only
-- the hit chance. Judgement of Command counts as melee since 13 November;
-- the sim never judges Command (Classes/Melee.lua).
function Fight:SpellLands(spell)
	if spell.rangedHit then
		if self.dice.spell:Random() * 100 < self:YellowTable(spell, true).miss then return false, "miss" end
		return true
	end
	if not self:SpellHits(spell) then return false, "resist" end
	return true
end

function Fight:SpellDamage(spell, base, castTime)
	local lands, outcome = self:SpellLands(spell)
	if not lands then
		self:Deal(spell.key, 0, outcome)
		return outcome
	end
	local amount = (base + SpellPower(self.sheet, spell.school) * Coefficient(spell, castTime)) * self:DamageMult(spell, "spell")
	local critChance = SpellCrit(self.sheet, spell.school) + self:CritBonusChance(spell, "spell")
	local crit = self.dice.spell:Random() * 100 < critChance
	if crit then amount = amount * self:CritMult(spell, "spell") end
	amount = amount * Resist(self, spell)
	self:Deal(spell.key, amount, crit and "crit" or "hit")
	if spell.school == "shadow" then
		local isb = self:Aura("isb")
		if isb and isb.charges > 0 then isb.charges = isb.charges - 1 end
		local weaving = self:Special("shadowWeaving")
		if weaving and self.dice.proc:Chance(weaving) then
			local aura = self:Aura("shadowWeaving") or self:AddAura("shadowWeaving", 15, { stacks = 0 })
			aura.stacks = min(5, aura.stacks + 1)
			aura.expires = self.t + 15
		end
	end
	if crit then
		local ignite = self:Special("ignite")
		if ignite and spell.school == "fire" then
			self:ApplyDot("ignite", { school = "fire", total = amount * ignite, ticks = 2, duration = 4, add = true, noRoll = true })
		end
		local isb = self:Special("isb")
		if isb and spell.key == "shadowBolt" then self:AddAura("isb", 12, { charges = 4, value = isb }) end
	end
	local clear = self:Special("clearcasting")
	if self:Aura("clearcasting") then self.auras.clearcasting = nil end
	if clear and self.dice.proc:Chance(clear) then self:AddAura("clearcasting", 15, {}) end
	-- The damage-over-time part of a hybrid spell.
	if spell.dot then
		local total = (spell.dot + SpellPower(self.sheet, spell.school) * (spell.dotCoef or C.DotCoefficient(spell.dotDuration)))
		self:ApplyDot(spell.key .. "Dot", { spell = { key = spell.key, school = spell.school, kind = "dot" }, total = total,
			ticks = max(1, floor(spell.dotDuration / 3 + 0.5)), duration = spell.dotDuration })
	end
	return crit and "crit" or "hit"
end

---------------------------------------------------------------------------
-- Using an ability (models call f:Try(key))
---------------------------------------------------------------------------
local function GcdFor(self, spell)
	if spell.offGcd or spell.kind == "queue" then return 0 end
	if self.powerType == "energy" then return 1 end
	return 1.5
end

local Perform = {}

function Perform.melee(self, spell)
	local mh = self.sheet.mh
	if spell.noDamage then
		local outcome = self:Yellow({ key = spell.key, school = "physical", kind = "melee", noDodge = spell.noDodge }, "mh", 0)
		if outcome == "hit" or outcome == "crit" then
			if spell.armor and self.target.sunders < (spell.stacks or 5) then
				self.target.sunders = self.target.sunders + 1
				self.target.armorDown = self.target.sunders * spell.armor
			end
		end
		return outcome
	end
	local base = 0
	if spell.weapon then base = self:WeaponRoll(mh, spell.normalized) * (spell.mult or 1) end
	if spell.apPct then base = base + self:AP() * spell.apPct / 100 end
	if spell.weapon or spell.apPct then
		base = base + (spell.bonus or 0)
	else
		base = self.dice.damage:Range(spell.min or 0, spell.max or 0)
	end
	local outcome = self:Yellow(spell, "mh", base)
	if outcome == "hit" or outcome == "crit" then
		if spell.builder then
			self.cp = min(5, self.cp + 1)
			local fate = self:Special("sealFate")
			if outcome == "crit" and fate and self.dice.proc:Chance(fate) then self.cp = min(5, self.cp + 1) end
		end
		if spell.natureBonus then self:AddAura("stormstrike", 12, { charges = spell.charges or 2 }) end
	end
	return outcome
end

function Perform.queue(self, spell)
	self.queued = spell.key
	return "queued"
end

function Perform.ranged(self, spell)
	local base = self:WeaponRoll(self.sheet.ranged, false, true) + (spell.bonus or 0)
	return self:Yellow(spell, "ranged", base, true)
end

function Perform.spell(self, spell, castTime)
	if spell.judge then
		local seal = self:Aura("seal")
		if not seal then return "none" end
		self.auras.seal = nil
	end
	return self:SpellDamage(spell, self.dice.damage:Range(spell.min or 0, spell.max or 0), castTime)
end

function Perform.dot(self, spell)
	if not self:SpellHits(spell) then
		self:Deal(spell.key, 0, "resist")
		return "resist"
	end
	local duration = spell.duration or 15
	local extra = spell.key == "shadowWordPain" and self:Special("longerSWP")
	local ticks = spell.ticks or 5
	local total = spell.min or 0
	if extra then
		total = total * (duration + extra) / duration
		ticks = ticks + floor(extra / (duration / ticks) + 0.5)
		duration = duration + extra
	end
	total = total + SpellPower(self.sheet, spell.school) * Coefficient(spell)
	self:ApplyDot(spell.key, { spell = spell, total = total, ticks = ticks, duration = duration })
	return "hit"
end

local function ChannelTick(self, spell, state)
	if state.left <= 0 then return end
	state.left = state.left - 1
	if spell.noDamage then
		if spell.manaPct then self:GainPower(self.maxPower * spell.manaPct / 100 / (spell.ticks or 4)) end
	else
		local amount = state.perTick * self:DamageMult(spell, "spell") * Resist(self, spell)
		local crit = PeriodicCrit(self, spell)
		if crit then amount = amount * self:CritMult(spell, "spell") end
		self:Deal(spell.key, amount, crit and "crit" or "hit")
	end
	if state.left > 0 then self:Schedule(self.t + state.interval, ChannelTick, spell, state) end
end

function Perform.channel(self, spell)
	if not spell.noDamage and not self:SpellHits(spell) then
		self:Deal(spell.key, 0, "resist")
		self.busy = self.t + 1
		return "resist"
	end
	local ticks = spell.ticks or 4
	local total = (spell.min or 0) + SpellPower(self.sheet, spell.school) * Coefficient(spell)
	local state = { left = ticks, perTick = total / ticks, interval = spell.duration / ticks }
	self.busy = self.t + spell.duration
	self:Schedule(self.t + state.interval, ChannelTick, spell, state)
	return "hit"
end

function Perform.finisher(self, spell)
	local points = self.cp
	if points <= 0 then return "none" end
	local range = spell.perPoint and spell.perPoint[points]
	local base = range and self.dice.damage:Range(range[1], range[2]) or 0
	if spell.energyDamage and self.power > 0 then
		base = base + self.power * spell.energyDamage
		self.power = 0
	end
	local outcome = self:Yellow(spell, "mh", base)
	if outcome == "hit" or outcome == "crit" then
		self.cp = 0
		local relentless = self:Special("relentless")
		if relentless and self.dice.proc:Chance(relentless * points * 100) then self:GainPower(25) end
	end
	return outcome
end

function Perform.buff(self, spell)
	local key = spell.key
	if spell.rage then self:GainPower(spell.rage) end
	if spell.mana then
		self:GainPower(spell.mana * (1 + (self:Special("lifeTap") or 0)))
	end
	if spell.damage and spell.duration then
		if key == "deathWish" then
			self:AddAura("deathWish", spell.duration, {})
		else
			self:AddAura(key, spell.duration, { damage = spell.damage, costMult = spell.costMult or 1 })
		end
	end
	if key == "sliceAndDice" then
		local points = self.cp
		if points <= 0 then return "none" end
		local duration = (spell.base + spell.perPoint * points) * (1 + (self:Special("longerSnD") or 0))
		self:AddAura("sliceAndDice", duration, { haste = spell.haste })
		self.cp = 0
		local relentless = self:Special("relentless")
		if relentless and self.dice.proc:Chance(relentless * points * 100) then self:GainPower(25) end
	elseif key == "bladeFlurry" then
		self:AddAura("bladeFlurry", spell.duration, { haste = spell.haste })
	elseif key == "adrenalineRush" then
		self:AddAura("adrenalineRush", spell.duration, {})
	elseif key == "rapidFire" then
		self:AddAura("rapidFire", spell.duration, { haste = spell.rangedHaste })
	elseif key == "huntersMark" then
		self.rapBonus = spell.rap or 0
	elseif spell.seal then
		self:AddAura("seal", spell.duration, { kind = spell.seal, perSpeed = spell.perSpeed, coef = spell.coef or 0,
			ppm = spell.ppm, weaponPct = spell.weaponPct })
	end
	return "hit"
end

-- Try an ability now. Returns true when it was used.
function Fight:Try(key)
	local spell = self.spells[key]
	if not spell then return false end
	if spell.form and spell.form ~= self.sheet.form then return false end
	if not self:Ready(key) then return false end
	local gcd = GcdFor(self, spell)
	if gcd > 0 and (self.gcd > self.t or self.busy > self.t) then return false end
	if spell.kind == "queue" and self.queued then return false end
	if spell.dagger and not (self.sheet.mh and self.sheet.mh.kind == "dagger") then return false end
	if spell.opener and self.t > 0 then return false end
	if spell.afterDodge and not (self.dodgedAt and self.t - self.dodgedAt <= 5) then return false end
	if (spell.kind == "finisher" or spell.finisher) and self.cp <= 0 then return false end
	if spell.once and self.used[key] then return false end
	local cost = self:Cost(spell)
	if self.power < cost then return false end
	if spell.kind ~= "queue" then self:SpendPower(cost) end
	self.used[key] = (self.used[key] or 0) + 1
	local cd = self:Cooldown(spell)
	if cd > 0 then self.cds[key] = self.t + cd end
	-- Spells that share one cooldown: the shocks, the hunter's shots.
	local share = spell.share or (spell.shock and "shock")
	if share and cd > 0 then
		for other, def in pairs(self.spells) do
			if (def.share or (def.shock and "shock")) == share then self.cds[other] = self.t + cd end
		end
	end
	if spell.afterDodge then self.dodgedAt = nil end
	if gcd > 0 then self.gcd = self.t + gcd end
	local castTime = self:CastTime(spell)
	local perform = Perform[spell.kind] or Perform.buff
	if castTime > 0 and spell.kind ~= "channel" then
		self.busy = self.t + castTime
		if spell.kind == "ranged" then self.rangedPausedUntil = self.busy end
		self:Schedule(self.busy, function(fight)
			perform(fight, spell, castTime)
			fight:Wake(fight.t)
		end)
	else
		perform(self, spell, castTime)
	end
	self:Wake(max(self.gcd, self.busy, self.t))
	return true
end

---------------------------------------------------------------------------
-- Auto shot and the pet
---------------------------------------------------------------------------
local function AutoShot(self)
	local ranged = self.sheet.ranged
	if not ranged then return end
	local paused = self.rangedPausedUntil
	if paused and paused > self.t then
		self:Schedule(paused + 0.01, AutoShot)
		return
	end
	local tbl = self:YellowTable(nil, true)
	local roll = self.dice.ranged:Random() * 100
	if roll < tbl.miss then
		self:Deal("autoShot", 0, "miss")
	else
		local crit = self.dice.ranged:Random() * 100 < tbl.crit
		local amount = self:WeaponRoll(ranged, false, true) * self:DamageMult(nil, "ranged")
		if crit then amount = amount * self:CritMult(nil, "ranged") end
		self:Deal("autoShot", amount * ArmorMult(self), crit and "crit" or "hit")
	end
	local haste = self.sheet.rangedHaste or 1
	local rapid = self:Aura("rapidFire")
	if rapid then haste = haste * (1 + rapid.haste) end
	self:Schedule(self.t + (ranged.speed or 3) / haste, AutoShot)
	self:Wake(self.t)
end

local function PetSwing(self)
	local pet = self.sheet.pet
	if not pet then return end
	local level = pet.level or self.level
	local diff = C.SkillDiff(self.targetLevel, level * 5)
	local miss, dodge = C.MissChance(diff, 0, false), C.DodgeChance(diff)
	local roll = self.dice.pet:Random() * 100
	if roll < miss then
		self:Deal("pet", 0, "miss")
	elseif roll < miss + dodge then
		self:Deal("pet", 0, "dodge")
	else
		local crit = roll < miss + dodge + (pet.crit or 5)
		local amount = self.dice.pet:Range(pet.min or 0, pet.max or 0) * self:DamageMult(nil, "pet")
		if crit then amount = amount * 2 end
		local armor = max(0, self.target.armor - self.target.armorDown)
		amount = amount * (1 - C.ArmorReduction(armor, level))
		self:Deal("pet", amount, crit and "crit" or "hit")
	end
	self:Schedule(self.t + (pet.speed or 2), PetSwing)
end

---------------------------------------------------------------------------
-- Power ticks
---------------------------------------------------------------------------
local function PowerTick(self)
	if self.powerType == "energy" then
		local rate = self:Aura("adrenalineRush") and 2 or 1
		self:GainPower(D.ENERGY_TICK * rate)
	elseif self.powerType == "mana" then
		local regen = self.sheet.regen or {}
		local perSecond = (self.t - self.lastSpend >= 5) and (regen.idle or 0) or (regen.casting or 0)
		self:GainPower(perSecond * 2)
	end
	self:Schedule(self.t + 2, PowerTick)
end

---------------------------------------------------------------------------
-- Decisions
---------------------------------------------------------------------------
local function Think(self, token)
	if token ~= self.thinkToken then return end
	self.nextThink = math.huge
	local model = self.model
	if model and model.OffGcd then model.OffGcd(self) end
	if self.busy > self.t then
		self:Wake(self.busy)
		return
	end
	if self.gcd > self.t then
		self:Wake(self.gcd)
		return
	end
	local acted = model and model.Act and model.Act(self)
	if not acted then self:Wake(self.t + (model and model.wait or 0.25)) end
end

-- Make sure the model is asked at time t (or sooner).
function Fight:Wake(t)
	if t >= self.nextThink then return end
	if t < self.t then t = self.t end
	self.nextThink = t
	self.thinkToken = self.thinkToken + 1
	self:Schedule(t, Think, self.thinkToken)
end

---------------------------------------------------------------------------
-- Run
---------------------------------------------------------------------------
function Fight:Run()
	local start = self.dice.start
	local melee = self.model and self.model.melee
	if melee and self.sheet.mh then self:Schedule(start:Range(0, 0.2), SwingEvent, "mh") end
	if melee and self.sheet.oh then self:Schedule(start:Range(0.1, 0.5), SwingEvent, "oh") end
	if self.sheet.ranged and self.model and self.model.autoShot then self:Schedule(start:Range(0, 0.3), AutoShot) end
	if self.sheet.pet then self:Schedule(start:Range(0, 0.5), PetSwing) end
	if self.powerType ~= "rage" then self:Schedule(start:Range(0, 2), PowerTick) end
	if self.model and self.model.Setup then self.model.Setup(self) end
	self:Wake(0)
	local heap = self.heap
	local hook, every = self.hook, self.hookEvery
	while heap.n > 0 do
		local event = Pop(heap)
		if event.t > self.length then break end
		self.t = event.t
		event.fn(self, event.a, event.b)
		self.events = self.events + 1
		if hook and self.events % every == 0 then hook(self) end
	end
	self.t = self.length
	return { total = self.total, dps = self.total / self.length, sources = self.sources, events = self.events }
end

-- One fight: Engine.Simulate(sheet, model, opts) -> result.
function Engine.Simulate(sheet, model, opts)
	return Engine.New(sheet, model, opts):Run()
end

---------------------------------------------------------------------------
-- Class models (Classes/*.lua)
-- Engine.RegisterClass(class, {
--     variants = { key = { title, Act = fn(fight) -> used, OffGcd, Setup,
--                  melee (white swings), autoShot, wait } },
--     pick = fn(sheet) -> variant key,
--     check = fn(sheet) -> nil or the reason the sim cannot run,
-- })
---------------------------------------------------------------------------
Engine.classes = {}

function Engine.RegisterClass(class, def)
	Engine.classes[class] = def
end

-- The model for a sheet: model, variant key (or nil, reason).
function Engine.ModelFor(sheet)
	local def = sheet and Engine.classes[sheet.class]
	if not def then return nil, "class" end
	if def.check then
		local reason = def.check(sheet)
		if reason then return nil, reason end
	end
	local key = sheet.variant or def.pick(sheet)
	local model = def.variants[key]
	if not model then return nil, "variant" end
	return model, key
end
