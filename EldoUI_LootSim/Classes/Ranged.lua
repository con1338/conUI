-- EldoUI Loot Sim: Hunter, Shaman and Druid models.
--   Hunter   Hunter's Mark, Rapid Fire, Aimed Shot (when known), Multi-Shot,
--            Arcane Shot and Serpent Sting while mana lasts; auto shot and
--            the pet from its own sheet. A hunter needs the pet out,
--            unless Lone Wolf is taken (then no pet on purpose).
--   Shaman   Enhancement: Stormstrike and Earth Shock between Windfury
--            swings; Elemental (and Restoration for damage): Chain
--            Lightning on cooldown, Lightning Bolt.
--   Druid    Cat: Shred (Claw without it), Ferocious Bite at five combo
--            points; Bear: Maul with spare rage, Swipe; Balance (and
--            Restoration for damage): Moonfire and Insect Swarm kept up,
--            Starfire (Wrath before you learn it). Cat and Bear need you in
--            that form, so the sim reads the form's attack power.
local _, S = ...
local Engine = S.Engine
local L = S.E and S.E.L or setmetatable({}, { __index = function(_, key) return key end })

local function Mana(f)
	return f.maxPower > 0 and f.power / f.maxPower or 0
end

---------------------------------------------------------------------------
-- Hunter
---------------------------------------------------------------------------
local function HunterAct(aimed)
	return function(f)
		if f:Try("huntersMark") then return true end
		f:Try("rapidFire")
		if aimed and f:Try("aimedShot") then return true end
		if f:Try("multiShot") then return true end
		if Mana(f) > 0.4 and f:Try("arcaneShot") then return true end
		if not aimed and Mana(f) > 0.25 and f:DotLeft("serpentSting") <= 0 and f.length - f.t > 9 and f:Try("serpentSting") then return true end
		return false
	end
end

Engine.RegisterClass("HUNTER", {
	variants = {
		aimed = { title = L["Aimed Shot, Multi-Shot and Arcane Shot"], Act = HunterAct(true), autoShot = true },
		shots = { title = L["Multi-Shot, Arcane Shot and Serpent Sting"], Act = HunterAct(false), autoShot = true },
	},
	pick = function(sheet)
		return (sheet.spells or {}).aimedShot and "aimed" or "shots"
	end,
	check = function(sheet)
		if not sheet.ranged then return "noRanged" end
		local special = sheet.mods and sheet.mods.special
		local alone = special and special.loneWolf
		if (sheet.level or 1) >= 10 and not sheet.pet and not sheet.petDismissed and not alone then return "noPet" end
	end,
})

---------------------------------------------------------------------------
-- Shaman
---------------------------------------------------------------------------
Engine.RegisterClass("SHAMAN", {
	variants = {
		enhancement = { title = L["Stormstrike, Earth Shock and Windfury"], melee = true,
			Act = function(f)
				if f:Try("stormstrike") then return true end
				if Mana(f) > 0.3 and f:Try("earthShock") then return true end
				return false
			end },
		elemental = { title = L["Chain Lightning and Lightning Bolt"],
			Act = function(f)
				if Mana(f) > 0.5 and f:Try("chainLightning") then return true end
				return f:Try("lightningBolt")
			end },
	},
	pick = function(sheet)
		if sheet.spec == "SHAMAN_ENH" then return "enhancement" end
		return "elemental"
	end,
})

---------------------------------------------------------------------------
-- Druid
---------------------------------------------------------------------------
Engine.RegisterClass("DRUID", {
	variants = {
		cat = { title = L["Cat: Shred and Ferocious Bite"], wait = 0.1, melee = true,
			Act = function(f)
				if f.cp >= 5 then return f:Try("ferociousBite") end
				return f:Try("shred") or f:Try("claw")
			end },
		bear = { title = L["Bear: Maul and Swipe"], melee = true,
			OffGcd = function(f) if f.power >= 25 then f:Try("maul") end end,
			Act = function(f)
				if f.power >= 45 then return f:Try("swipe") end
				return false
			end },
		balance = { title = L["Moonfire, Insect Swarm and Starfire"],
			Act = function(f)
				if f:DotLeft("moonfireDot") <= 0 and f.length - f.t > 8 and f:Try("moonfire") then return true end
				if f:DotLeft("insectSwarm") <= 0 and f.length - f.t > 8 and f:Try("insectSwarm") then return true end
				return f:Try("starfire") or f:Try("wrath")
			end },
	},
	pick = function(sheet)
		if sheet.spec == "DRUID_CAT" then return "cat" end
		if sheet.spec == "DRUID_BEAR" then return "bear" end
		return "balance"
	end,
	check = function(sheet)
		if sheet.spec == "DRUID_CAT" and sheet.form ~= "cat" then return "catForm" end
		if sheet.spec == "DRUID_BEAR" and sheet.form ~= "bear" then return "bearForm" end
	end,
})
