-- EldoUI Loot Sim: Mage, Warlock and Priest models.
--   Mage     Frost: Frostbolt; Fire: Fireball; Arcane: Arcane Missiles with
--            Arcane Power on cooldown. Evocation when mana runs low.
--   Warlock  Bane of Agony and Corruption kept up (Siphon Life for
--            Affliction, Immolate for Destruction), Shadow Bolt, Life Tap
--            when mana runs out.
--   Priest   Shadow: Shadow Word: Pain kept up, Mind Blast on cooldown,
--            Mind Flay; Discipline and Holy for damage: Holy Fire and Smite.
local _, S = ...
local Engine = S.Engine
local L = S.E and S.E.L or setmetatable({}, { __index = function(_, key) return key end })

local function Mana(f)
	return f.maxPower > 0 and f.power / f.maxPower or 0
end

local function Left(f)
	return f.length - f.t
end

---------------------------------------------------------------------------
-- Mage
---------------------------------------------------------------------------
local function MageAct(filler)
	return function(f)
		if Mana(f) < 0.1 and f:Try("evocation") then return true end
		if filler == "arcaneMissiles" then f:Try("arcanePower") end
		return f:Try(filler) or f:Try("frostbolt") or f:Try("fireball")
	end
end

Engine.RegisterClass("MAGE", {
	variants = {
		frost = { title = L["Frostbolt"], Act = MageAct("frostbolt") },
		fire = { title = L["Fireball"], Act = MageAct("fireball") },
		arcane = { title = L["Arcane Missiles and Arcane Power"], Act = MageAct("arcaneMissiles") },
	},
	pick = function(sheet)
		local spells = sheet.spells or {}
		if sheet.spec == "MAGE_FIRE" and spells.fireball then return "fire" end
		if sheet.spec == "MAGE_ARCANE" and spells.arcaneMissiles then return "arcane" end
		if spells.frostbolt then return "frost" end
		return "fire"
	end,
})

---------------------------------------------------------------------------
-- Warlock
---------------------------------------------------------------------------
local function WarlockAct(extra)
	return function(f)
		local bolt = f:Spell("shadowBolt")
		if bolt and f.power < f:Cost(bolt) then return f:Try("lifeTap") end
		if Left(f) > 15 and f:DotLeft("curseOfAgony") <= 0 and f:Try("curseOfAgony") then return true end
		if Left(f) > 12 and f:DotLeft("corruption") <= 0 and f:Try("corruption") then return true end
		if extra == "siphonLife" and Left(f) > 15 and f:DotLeft("siphonLife") <= 0 and f:Try("siphonLife") then return true end
		if extra == "immolate" and Left(f) > 8 and f:DotLeft("immolateDot") <= 0 and f:Try("immolate") then return true end
		return f:Try("shadowBolt") or f:Try("lifeTap")
	end
end

Engine.RegisterClass("WARLOCK", {
	variants = {
		affliction = { title = L["Curses, Corruption, Siphon Life and Shadow Bolt"], Act = WarlockAct("siphonLife") },
		dots = { title = L["Bane of Agony, Corruption and Shadow Bolt"], Act = WarlockAct(nil) },
		destruction = { title = L["Immolate, Bane of Agony, Corruption and Shadow Bolt"], Act = WarlockAct("immolate") },
	},
	pick = function(sheet)
		if sheet.spec == "WARLOCK_AFF" and (sheet.spells or {}).siphonLife then return "affliction" end
		if sheet.spec == "WARLOCK_DESTRO" then return "destruction" end
		return "dots"
	end,
})

---------------------------------------------------------------------------
-- Priest
---------------------------------------------------------------------------
Engine.RegisterClass("PRIEST", {
	variants = {
		shadow = { title = L["Shadow Word: Pain, Mind Blast and Mind Flay"],
			Act = function(f)
				if Left(f) > 12 and f:DotLeft("shadowWordPain") <= 0 and f:Try("shadowWordPain") then return true end
				if f:Try("mindBlast") then return true end
				return f:Try("mindFlay") or f:Try("smite")
			end },
		smite = { title = L["Shadow Word: Pain, Holy Fire and Smite"],
			Act = function(f)
				if Left(f) > 12 and f:DotLeft("shadowWordPain") <= 0 and f:Try("shadowWordPain") then return true end
				if f:DotLeft("holyFireDot") <= 0 and f:Try("holyFire") then return true end
				return f:Try("smite") or f:Try("mindBlast")
			end },
	},
	pick = function(sheet)
		if sheet.spec == "PRIEST_SHADOW" and (sheet.spells or {}).mindFlay then return "shadow" end
		if sheet.spec == "PRIEST_SHADOW" then return "shadow" end
		return "smite"
	end,
})
