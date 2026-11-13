-- EldoUI Loot Sim: Warrior, Rogue and Paladin models.
--
-- Each model is a short priority list played against the dummy (our own
-- reading of the usual Classic rotations, no code from anywhere else):
--   Warrior  Arms: Mortal Strike, Whirlwind, Overpower; Fury: Bloodthirst,
--            Whirlwind; Protection: Shield Slam, Sunder Armor. Heroic
--            Strike takes spare rage, Bloodrage and Death Wish on cooldown.
--   Rogue    opener Ambush with a dagger; Slice and Dice kept up, then
--            Eviscerate at five combo points; builder Backstab (dagger),
--            Hemorrhage (Subtlety) or Sinister Strike; Blade Flurry and
--            Adrenaline Rush on cooldown.
--   Paladin  Seal of Command (slow two-hander) or Seal of Righteousness;
--            judging Righteousness and sealing again; Holy and Protection
--            add Consecration while mana lasts.
local _, S = ...
local Engine = S.Engine
local L = S.E and S.E.L or setmetatable({}, { __index = function(_, key) return key end })

---------------------------------------------------------------------------
-- Warrior
---------------------------------------------------------------------------
local function WarriorOffGcd(f, threshold)
	if f.power < 30 then f:Try("bloodrage") end
	if f.power >= threshold then f:Try("heroicStrike") end
end

Engine.RegisterClass("WARRIOR", {
	variants = {
		arms = { title = L["Arms: Mortal Strike"], melee = true,
			OffGcd = function(f) WarriorOffGcd(f, 55) end,
			Act = function(f)
				return f:Try("deathWish") or f:Try("mortalStrike") or f:Try("whirlwind") or f:Try("overpower")
			end },
		fury = { title = L["Fury: Bloodthirst"], melee = true,
			OffGcd = function(f) WarriorOffGcd(f, 50) end,
			Act = function(f)
				return f:Try("deathWish") or f:Try("bloodthirst") or f:Try("whirlwind") or f:Try("overpower")
			end },
		prot = { title = L["Protection: Shield Slam and Sunder Armor"], melee = true,
			OffGcd = function(f) WarriorOffGcd(f, 45) end,
			Act = function(f)
				return f:Try("shieldSlam") or f:Try("sunderArmor")
			end },
		basic = { title = L["Heroic Strike and Overpower"], melee = true,
			OffGcd = function(f) WarriorOffGcd(f, 30) end,
			Act = function(f) return f:Try("overpower") end },
	},
	pick = function(sheet)
		local spells = sheet.spells or {}
		if sheet.spec == "WARRIOR_PROT" and spells.shieldSlam then return "prot" end
		if spells.mortalStrike then return "arms" end
		if spells.bloodthirst then return "fury" end
		if sheet.spec == "WARRIOR_PROT" and spells.sunderArmor then return "prot" end
		return "basic"
	end,
})

---------------------------------------------------------------------------
-- Rogue
---------------------------------------------------------------------------
local function RogueAct(builder)
	return function(f)
		if f:Try("ambush") then return true end
		if f:Try("bladeFlurry") or f:Try("adrenalineRush") then return true end
		local snd = f:Aura("sliceAndDice")
		if not snd and f.cp >= 2 and f:Knows("sliceAndDice") then return f:Try("sliceAndDice") end
		if f.cp >= 5 or (f.cp >= 4 and f.power >= 90) then
			if f:Try("eviscerate") then return true end
			return false
		end
		if f.cp < 5 and f:Try(builder) then return true end
		if builder ~= "sinisterStrike" and f.cp < 5 then return f:Try("sinisterStrike") end
		return false
	end
end

Engine.RegisterClass("ROGUE", {
	variants = {
		daggers = { title = L["Daggers: Ambush, Backstab, Slice and Dice, Eviscerate"], Act = RogueAct("backstab"), wait = 0.1, melee = true },
		swords = { title = L["Sinister Strike, Slice and Dice, Eviscerate"], Act = RogueAct("sinisterStrike"), wait = 0.1, melee = true },
		hemo = { title = L["Hemorrhage, Slice and Dice, Eviscerate"], Act = RogueAct("hemorrhage"), wait = 0.1, melee = true },
	},
	pick = function(sheet)
		local spells = sheet.spells or {}
		if sheet.spec == "ROGUE_SUB" and spells.hemorrhage then return "hemo" end
		if sheet.mh and sheet.mh.kind == "dagger" and spells.backstab then return "daggers" end
		return "swords"
	end,
})

---------------------------------------------------------------------------
-- Paladin
---------------------------------------------------------------------------
local function PaladinAct(seal, consecrate, judge)
	return function(f)
		if not f:Aura("seal") then
			if f:Try(seal) then return true end
			if seal ~= "sealOfRighteousness" and f:Try("sealOfRighteousness") then return true end
		end
		if judge and f:Aura("seal") and f:Ready("judgement") and f.power >= 300 then
			if f:Try("judgement") then return true end
		end
		if consecrate and f.power > f.maxPower * 0.5 and f:Try("consecration") then return true end
		return false
	end
end

Engine.RegisterClass("PALADIN", {
	variants = {
		command = { title = L["Seal of Command"], Act = PaladinAct("sealOfCommand", false, false), melee = true },
		righteousness = { title = L["Seal of Righteousness, judged and renewed"], Act = PaladinAct("sealOfRighteousness", false, true), melee = true },
		consecration = { title = L["Seal of Righteousness and Consecration"], Act = PaladinAct("sealOfRighteousness", true, true), melee = true },
	},
	pick = function(sheet)
		local spells = sheet.spells or {}
		if sheet.spec == "PALADIN_RET" then
			if spells.sealOfCommand and sheet.mh and sheet.mh.twoHand and (sheet.mh.speed or 0) >= 3.3 then return "command" end
			return "righteousness"
		end
		if spells.consecration then return "consecration" end
		return "righteousness"
	end,
})
