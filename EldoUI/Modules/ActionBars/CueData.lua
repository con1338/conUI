-- EldoUI Action Bars: spell cue data, per class.
--
-- Which of your buffs, and which of your effects on your target, show on
-- which action buttons (Spell cues, Cues.lua). The game draws each one: a
-- cue is an aura slot that the client fills while the aura is there.
-- EldoUI never reads an aura, a cooldown or a resource for it.
--
-- pairs: an aura on a unit that changes other spells.
--   auras = { spell IDs of the aura }   ranksOf = { a spell ID whose
--   every rank in your spellbook counts as the aura too }
--   unit = "player" | "target" | "pet", kind = "HELPFUL" | "HARMFUL"
--   mine = true: only the one you put there
--   on = { spell IDs }: the buttons it shows on, matched by the spell's
--   name, so every rank of the spell counts
-- own: a spell whose own aura (buff, debuff, heal over time) shows on its
--   button while it lasts: { spell ID, unit, kind, mine }. Every rank in
--   your spellbook counts.
--
-- Every ID is from the game's own spell data for WoW: Forever (spell
-- tables, talent tree TraitDefinition and TraitNodeEntry, trainer ranks),
-- first written on build 1.60.1.70450 and checked again on build
-- 1.60.1.70938. Spells that the game's data still names but no Forever
-- talent or trainer grants, and talent effects without an aura of their
-- own, are left out.
-- Written from scratch for EldoUI.
local _, E = ...

local P, T, PET = "player", "target", "pet"
local HELP, HARM = "HELPFUL", "HARMFUL"

E.SpellCueData = {
	SHAMAN = {
		pairs = {
			-- Maelstrom Weapon (talent 408498): the buff and its stacks.
			{ auras = { 408505, 409946 }, unit = P, kind = HELP, mine = true, on = { 403, 421, 331, 8004, 1064 } },
			-- Elemental Focus (16164): Clearcasting.
			{ auras = { 16246 }, unit = P, kind = HELP, mine = true, on = { 403, 421, 8042, 8050, 8056 } },
			-- Lightning Mastery.
			{ auras = { 16166 }, unit = P, kind = HELP, mine = true, on = { 403, 421 } },
			-- Nature's Swiftness.
			{ auras = { 16188 }, unit = P, kind = HELP, mine = true, on = { 331, 8004, 1064, 403 } },
			-- Stormstrike on your target.
			{ auras = { 17364 }, unit = T, kind = HARM, mine = true, on = { 8042, 403, 17364 } },
			-- Your Riptide on the target lights Chain Heal.
			{ auras = { 408521, 1239242, 1239243 }, unit = T, kind = HELP, mine = true, on = { 1064 } },
			-- Water Shield charges on its own button.
			{ auras = { 408510, 408511, 409941 }, unit = P, kind = HELP, mine = true, on = { 408510 } },
		},
		own = {
			{ 8050, T, HARM, true },     -- Flame Shock
			{ 324, P, HELP, true },      -- Lightning Shield
			{ 408521, T, HELP, true },   -- Riptide
		},
	},
	MAGE = {
		pairs = {
			-- Arcane Concentration (11213): Clearcasting.
			{ auras = { 12536 }, unit = P, kind = HELP, mine = true, on = { 5143, 1449, 133, 116, 2136, 2948, 10, 2120, 120, 400574 } },
			-- Missile Barrage (400588).
			{ auras = { 400589, 401736 }, unit = P, kind = HELP, mine = true, on = { 5143 } },
			-- Presence of Mind.
			{ auras = { 12043 }, unit = P, kind = HELP, mine = true, on = { 11366, 133, 116 } },
			-- Heating Up (400624), then Hot Streak.
			{ auras = { 400625, 48108, 401724 }, unit = P, kind = HELP, mine = true, on = { 11366 } },
			-- Combustion.
			{ auras = { 11129, 28682 }, unit = P, kind = HELP, mine = true, on = { 133, 2136, 2948 } },
			-- Fingers of Frost (400647).
			{ auras = { 400669, 400670, 401741 }, unit = P, kind = HELP, mine = true, on = { 400640, 116 } },
			-- Improved Scorch (11095): Fire Vulnerability on the target.
			{ auras = { 22959 }, unit = T, kind = HARM, on = { 2948 } },
			-- Winter's Chill (11180) on the target.
			{ auras = { 12579 }, unit = T, kind = HARM, on = { 116 } },
			-- Your Ignite on the target.
			{ auras = { 412538, 412545 }, unit = T, kind = HARM, mine = true, on = { 133, 2136 } },
		},
		own = {
			{ 11426, P, HELP, true },    -- Ice Barrier
		},
	},
	WARLOCK = {
		pairs = {
			-- Nightfall (18094): Shadow Trance.
			{ auras = { 17941 }, unit = P, kind = HELP, mine = true, on = { 686 } },
			-- Decimation (440870).
			{ auras = { 440873, 440923 }, unit = P, kind = HELP, mine = true, on = { 6353 } },
			-- Improved Shadow Bolt (17793): Shadow Vulnerability on the target.
			{ auras = { 17794 }, unit = T, kind = HARM, on = { 686 } },
			-- Your Immolate on the target lights Conflagrate and Incinerate.
			{ ranksOf = { 348 }, auras = { 348 }, unit = T, kind = HARM, mine = true, on = { 17962, 412758 } },
		},
		own = {
			{ 172, T, HARM, true },      -- Corruption
			{ 348, T, HARM, true },      -- Immolate
			{ 980, T, HARM, true },      -- Bane of Agony
			{ 603, T, HARM, true },      -- Bane of Doom
			{ 18265, T, HARM, true },    -- Siphon Life
			{ 706, P, HELP, true },      -- Demon Armor
			{ 687, P, HELP, true },      -- Demon Skin
		},
	},
	PRIEST = {
		pairs = {
			-- Shadow Weaving (15257) stacks on the target.
			{ auras = { 15258 }, unit = T, kind = HARM, on = { 8092, 15407 } },
			-- Inner Focus.
			{ auras = { 14751 }, unit = P, kind = HELP, mine = true, on = { 8092, 2061, 2060, 2054, 596 } },
			-- Weakened Soul on the target (from any priest) on Power Word: Shield.
			{ auras = { 6788 }, unit = T, kind = HARM, on = { 17 } },
		},
		own = {
			{ 589, T, HARM, true },      -- Shadow Word: Pain
			{ 15286, T, HARM, true },    -- Vampiric Embrace
			{ 139, T, HELP, true },      -- Renew
			{ 401859, T, HELP, true },   -- Prayer of Mending
			{ 588, P, HELP, true },      -- Inner Fire
			{ 15473, P, HELP, true },    -- Shadowform
		},
	},
	DRUID = {
		pairs = {
			-- Eclipse (408248).
			{ auras = { 408255, 409813 }, unit = P, kind = HELP, mine = true, on = { 2912, 5176 } },
			-- Nature's Grace (16880).
			{ auras = { 16886 }, unit = P, kind = HELP, mine = true, on = { 2912, 5176 } },
			-- Omen of Clarity: Clearcasting.
			{ auras = { 16870 }, unit = P, kind = HELP, mine = true, on = { 5221, 6807, 22568, 5176, 2912, 5185, 8936 } },
			-- Berserk (417141).
			{ auras = { 417141 }, unit = P, kind = HELP, mine = true, on = { 5221 } },
			-- Nature's Swiftness.
			{ auras = { 17116 }, unit = P, kind = HELP, mine = true, on = { 5185, 8936 } },
			-- Your Rejuvenation or Regrowth on the target lights Swiftmend.
			{ ranksOf = { 774, 8936 }, auras = { 774, 8936 }, unit = T, kind = HELP, mine = true, on = { 18562 } },
			-- Your bleeds on the target light Shred and Ferocious Bite.
			{ ranksOf = { 1822, 1079 }, auras = { 1822, 1079 }, unit = T, kind = HARM, mine = true, on = { 5221, 22568 } },
		},
		own = {
			{ 8921, T, HARM, true },     -- Moonfire
			{ 5570, T, HARM, true },     -- Insect Swarm
			{ 770, T, HARM, true },      -- Faerie Fire
			{ 1822, T, HARM, true },     -- Rake
			{ 1079, T, HARM, true },     -- Rip
			{ 774, T, HELP, true },      -- Rejuvenation
			{ 8936, T, HELP, true },     -- Regrowth
			{ 408120, T, HELP, true },   -- Wild Growth
			{ 467, P, HELP, true },      -- Thorns
		},
	},
	PALADIN = {
		pairs = {
			-- Infusion of Light (426065).
			{ auras = { 426179, 437063, 437877 }, unit = P, kind = HELP, mine = true, on = { 19750, 635 } },
			-- Divine Favor.
			{ auras = { 20216 }, unit = P, kind = HELP, mine = true, on = { 635, 19750, 20473 } },
			-- A seal on you lights Judgement.
			{ ranksOf = { 21084, 20375, 21082, 20165, 20166, 20164, 1311649 },
				auras = { 21084, 20375, 21082, 20165, 20166, 20164, 1311649 },
				unit = P, kind = HELP, mine = true, on = { 20271 } },
		},
		own = {
			{ 20925, P, HELP, true },    -- Holy Shield
			{ 21084, P, HELP, true },    -- Seal of Righteousness
			{ 20375, P, HELP, true },    -- Seal of Command
			{ 21082, P, HELP, true },    -- Seal of the Crusader
			{ 20165, P, HELP, true },    -- Seal of Light
			{ 20166, P, HELP, true },    -- Seal of Wisdom
			{ 20164, P, HELP, true },    -- Seal of Justice
			{ 1311649, P, HELP, true },  -- Seal of Fury
		},
	},
	ROGUE = {
		pairs = {
			-- Cold Blood.
			{ auras = { 14177 }, unit = P, kind = HELP, mine = true, on = { 2098 } },
		},
		own = {
			{ 5171, P, HELP, true },     -- Slice and Dice
			{ 13877, P, HELP, true },    -- Blade Flurry
			{ 13750, P, HELP, true },    -- Adrenaline Rush
			{ 1943, T, HARM, true },     -- Rupture
			{ 703, T, HARM, true },      -- Garrote
			{ 8647, T, HARM, true },     -- Expose Armor
			{ 16511, T, HARM, true },    -- Hemorrhage
		},
	},
	HUNTER = {
		pairs = {
			-- Bestial Wrath on your pet.
			{ auras = { 19574 }, unit = PET, kind = HELP, on = { 19574 } },
		},
		own = {
			{ 1978, T, HARM, true },     -- Serpent Sting
			{ 3034, T, HARM, true },     -- Viper Sting
			{ 3043, T, HARM, true },     -- Scorpid Sting
			{ 1130, T, HARM, true },     -- Hunter's Mark
			{ 13165, P, HELP, true },    -- Aspect of the Hawk
			{ 13163, P, HELP, true },    -- Aspect of the Monkey
			{ 5118, P, HELP, true },     -- Aspect of the Cheetah
			{ 13159, P, HELP, true },    -- Aspect of the Pack
			{ 20043, P, HELP, true },    -- Aspect of the Wild
			{ 13161, P, HELP, true },    -- Aspect of the Beast
		},
	},
	WARRIOR = {
		pairs = {
			-- Sweeping Strikes.
			{ auras = { 12292 }, unit = P, kind = HELP, mine = true, on = { 845, 1680 } },
		},
		own = {
			{ 7386, T, HARM, false },    -- Sunder Armor (stacks from anyone)
			{ 772, T, HARM, true },      -- Rend
			{ 1715, T, HARM, true },     -- Hamstring
			{ 6343, T, HARM, true },     -- Thunder Clap
			{ 1160, T, HARM, true },     -- Demoralizing Shout
			{ 6673, P, HELP, false },    -- Battle Shout
		},
	},
}
