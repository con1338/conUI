-- EldoUI Training data shared by every class: the data namespace, the
-- trainer reputations (Forever discounts training at Honored), the spells
-- that come from class quests, and the weapon masters.
--
-- This file and the other files in Data/Training are adapted from
-- What's Training? (https://github.com/fusionpit/WhatsTraining, branch
-- forever, commit 716de2c), used under the MIT License:
--
-- MIT License
--
-- Copyright (c) 2019
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in all
-- copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
-- SOFTWARE.
-- The faction, area and spell IDs are checked against the WoW: Forever client
-- tables of build 1.60.1.70938.
local _, E = ...

local D = { classes = {} }
E.TrainingData = D

---------------------------------------------------------------------------
-- Trainer reputations. factions[id] = { side = 0 neutral / 1 Alliance /
-- 2 Horde, city = capital city, noRep = no reputation (area id instead) };
-- roles[class or "PET"][faction] = reputations whose trainers teach it;
-- npcs[weapon master npc id] = the reputation of that master's city.
---------------------------------------------------------------------------
D.trainerFactions = {
	factions = {
		[21] = { side = 0 },
		[47] = { side = 1, city = true },
		[54] = { side = 1, city = true },
		[68] = { side = 2, city = true },
		[69] = { side = 1, city = true },
		[72] = { side = 1, city = true },
		[76] = { side = 2, city = true },
		[81] = { side = 2, city = true },
		[349] = { side = 0 },
		[530] = { side = 2, city = true },
		[609] = { side = 0 },
		[2740] = { side = 1 },
		[2787] = { side = 2 },
	},
	roles = {
		DRUID = {
			Alliance = { 69, 72, 609, 2740 },
			Horde = { 81, 609, 2787 },
		},
		-- Forever's tome vendors charge full price at every standing (Era discounts them, so this is
		-- probably a Forever bug). No GRIMOIRE role means Pricing shows only the base cost for tomes.
		-- GRIMOIRE = {
		-- 	Alliance = { 54, 72 },
		-- 	Horde = { 68, 76 },
		-- },
		HUNTER = {
			Alliance = { 47, 69, 72 },
			Horde = { 76, 81, 530 },
		},
		MAGE = {
			Alliance = { 47, 54, 69, 72, 2740 },
			Horde = { 68, 76, 530 },
		},
		PALADIN = {
			Alliance = { 47, 72 },
			Horde = { 68 },
		},
		PET = {
			Alliance = { 47, 69, 72 },
			Horde = { 76, 81 },
		},
		PRIEST = {
			Alliance = { 47, 54, 69, 72 },
			Horde = { 68, 76, 530 },
		},
		ROGUE = {
			Alliance = { 21, 47, 54, 69, 72, 349 },
			Horde = { 21, 68, 76, 81, 349, 530 },
		},
		SHAMAN = {
			Alliance = { 47 },
			Horde = { 76, 81, 2787 },
		},
		WARLOCK = {
			Alliance = { 47, 54, 72 },
			Horde = { 68, 76 },
		},
		WARRIOR = {
			Alliance = { 47, 54, 69, 72 },
			Horde = { 68, 76, 81 },
		},
	},
	npcs = {
		[2704] = 530,
		[11865] = 47,
		[11866] = 69,
		[11867] = 72,
		[11868] = 76,
		[11869] = 81,
		[11870] = 68,
		[13084] = 47,
	},
}

---------------------------------------------------------------------------
-- Spells that come from class quests instead of the trainer.
-- questSpells[CLASS][spellID] = list of { races = { raceIDs }, level =
-- level of the first quest, area = AreaTable id (or areas = { ... }),
-- quests = { reward quest ids } }
---------------------------------------------------------------------------
D.questSpells = {
	WARRIOR = {
		[71] = { -- Defensive Stance
			{ races = {2, 6, 8}, level = 10, area = 17, quests = {1498} },
			{ races = {5}, level = 10, area = 85, quests = {1819} },
			{ races = {1}, level = 10, area = 1519, quests = {1665} },
			{ races = {3, 7}, level = 10, area = 1537, quests = {1678} },
			{ races = {4}, level = 10, area = 1657, quests = {1683} },
			{ races = {95, 96}, level = 10, area = 16593, quests = {94003} },
		},
		[355] = { -- Taunt
			{ races = {2, 6, 8}, level = 10, area = 17, quests = {1498} },
			{ races = {5}, level = 10, area = 85, quests = {1819} },
			{ races = {1}, level = 10, area = 1519, quests = {1665} },
			{ races = {3, 7}, level = 10, area = 1537, quests = {1678} },
			{ races = {4}, level = 10, area = 1657, quests = {1683} },
			{ races = {95, 96}, level = 10, area = 16593, quests = {94003} },
		},
		[7386] = { -- Sunder Armor
			{ races = {2, 6, 8}, level = 10, area = 17, quests = {1498} },
			{ races = {5}, level = 10, area = 85, quests = {1819} },
			{ races = {1}, level = 10, area = 1519, quests = {1665} },
			{ races = {3, 7}, level = 10, area = 1537, quests = {1678} },
			{ races = {4}, level = 10, area = 1657, quests = {1683} },
			{ races = {95, 96}, level = 10, area = 16593, quests = {94003} },
		},
		[2458] = { -- Berserker Stance
			{ races = {1, 2, 3, 4, 5, 6, 7, 8, 95, 96}, level = 30, area = 17, quests = {1719} },
		},
		[20252] = { -- Intercept
			{ races = {1, 2, 3, 4, 5, 6, 7, 8, 95, 96}, level = 30, area = 17, quests = {1719} },
		},
	},
	PALADIN = {
		[635] = { -- Holy Light
			{ races = {5}, level = 2, area = 85, quests = {90902} },
		},
		[7328] = { -- Redemption
			{ races = {3}, level = 12, area = 1537, quests = {1785} },
			{ races = {1}, level = 12, area = 1519, quests = {1788} },
			{ races = {5}, level = 12, area = 85, quests = {94441} },
		},
		[5502] = { -- Sense Undead
			{ races = {1, 3}, level = 20, areas = {1519, 1537}, quests = {1652} },
		},
		[13819] = { -- Summon Warhorse
			{ races = {1, 3}, level = 40, area = 1519, quests = {1661} },
		},
		[23214] = { -- Summon Charger
			{ races = {1, 3}, level = 60, area = 1519, quests = {7647} },
		},
	},
	HUNTER = {
		[1515] = { -- Tame Beast
			{ races = {2, 8}, level = 10, area = 14, quests = {6082} },
			{ races = {6}, level = 10, area = 215, quests = {6088} },
			{ races = {3}, level = 10, area = 1, quests = {6085} },
			{ races = {4}, level = 10, area = 141, quests = {6102} },
			{ races = {95, 96}, level = 10, area = 16593, quests = {94013} },
			{ races = {1}, level = 10, area = 12, quests = {94864} },
		},
		[5149] = { -- Beast Training
			{ races = {2, 8}, level = 10, area = 14, quests = {6081} },
			{ races = {6}, level = 10, area = 215, quests = {6089} },
			{ races = {3}, level = 10, area = 1, quests = {6086} },
			{ races = {4}, level = 10, area = 141, quests = {6103} },
			{ races = {95, 96}, level = 10, area = 16593, quests = {94050} },
			{ races = {1}, level = 10, area = 12, quests = {94793} },
		},
		[883] = { -- Call Pet
			{ races = {2, 8}, level = 10, area = 14, quests = {6081} },
			{ races = {6}, level = 10, area = 215, quests = {6089} },
			{ races = {3}, level = 10, area = 1, quests = {6086} },
			{ races = {4}, level = 10, area = 141, quests = {6103} },
			{ races = {95, 96}, level = 10, area = 16593, quests = {94050} },
			{ races = {1}, level = 10, area = 12, quests = {94793} },
		},
		[2641] = { -- Dismiss Pet
			{ races = {2, 8}, level = 10, area = 14, quests = {6081} },
			{ races = {6}, level = 10, area = 215, quests = {6089} },
			{ races = {3}, level = 10, area = 1, quests = {6086} },
			{ races = {4}, level = 10, area = 141, quests = {6103} },
			{ races = {95, 96}, level = 10, area = 16593, quests = {94050} },
			{ races = {1}, level = 10, area = 12, quests = {94793} },
		},
		[6991] = { -- Feed Pet
			{ races = {2, 8}, level = 10, area = 14, quests = {6081} },
			{ races = {6}, level = 10, area = 215, quests = {6089} },
			{ races = {3}, level = 10, area = 1, quests = {6086} },
			{ races = {4}, level = 10, area = 141, quests = {6103} },
			{ races = {95, 96}, level = 10, area = 16593, quests = {94050} },
			{ races = {1}, level = 10, area = 12, quests = {94793} },
		},
		[982] = { -- Revive Pet
			{ races = {2, 8}, level = 10, area = 14, quests = {6081} },
			{ races = {6}, level = 10, area = 215, quests = {6089} },
			{ races = {3}, level = 10, area = 1, quests = {6086} },
			{ races = {4}, level = 10, area = 141, quests = {6103} },
			{ races = {95, 96}, level = 10, area = 16593, quests = {94050} },
			{ races = {1}, level = 10, area = 12, quests = {94793} },
		},
	},
	ROGUE = {
		[2842] = { -- Poisons
			{ races = {1, 3, 4, 7, 95}, level = 20, area = 1519, quests = {2359} },
			{ races = {2, 5, 8}, level = 20, area = 1637, quests = {2480} },
		},
	},
	PRIEST = {
		[13908] = { -- Desperate Prayer
			{ races = {3}, level = 10, areas = {12, 1, 1519, 1537, 1657, 141}, quests = {5635, 5637, 5638, 5639, 5640, 5634, 5636} },
		},
		[13896] = { -- Feedback
			{ races = {1}, level = 20, areas = {1519, 1537, 1657}, quests = {5676, 5677, 5678} },
		},
		[10797] = { -- Starshards
			{ races = {4}, level = 10, areas = {1657, 12, 141, 1, 1519, 1537}, quests = {5627, 5628, 5629, 5630, 5631, 5632, 5633} },
		},
		[2651] = { -- Elune's Grace
			{ races = {4}, level = 20, areas = {1657, 1519, 1537}, quests = {5672, 5673, 5674, 5675} },
		},
		[2652] = { -- Touch of Weakness
			{ races = {5}, level = 10, areas = {1497, 14, 215, 1637, 1638}, quests = {5658, 5660, 5661, 5662, 5663} },
		},
		[9035] = { -- Hex of Weakness
			{ races = {8}, level = 10, areas = {1637, 14, 215, 1497}, quests = {5652, 5654, 5655, 5656, 5657} },
		},
		[18137] = { -- Shadowguard
			{ races = {8}, level = 20, areas = {1638, 1497, 1637}, quests = {5642, 5643, 5680} },
		},
		[1277370] = { -- Divine Grace
			{ races = {1}, level = 10, areas = {1519, 12}, quests = {94773, 94774, 94775, 94776, 94777, 94778, 94779} },
		},
		[1277331] = { -- Chastise
			{ races = {3}, level = 20, areas = {1537, 1519, 1657}, quests = {5641, 5645, 5647} },
		},
		[1277324] = { -- Dark Sacrifice
			{ races = {5}, level = 20, areas = {1638, 1637, 1497}, quests = {5644, 5646, 5679} },
		},
		[1277455] = { -- Confounding Flash
			{ races = {7}, level = 10, areas = {1537, 1}, quests = {94817, 94821, 94822, 94823, 94824, 94825, 94826} },
		},
		[1277462] = { -- Contingency Plan
			{ races = {7}, level = 20, area = 1537, quests = {94818, 94819, 94820} },
		},
	},
	SHAMAN = {
		[8071] = { -- Stoneskin Totem
			{ races = {2, 6}, level = 4, areas = {14, 215}, quests = {1518, 1521} },
			{ races = {8}, level = 4, area = 14, quests = {1518} },
			{ races = {3}, level = 4, area = 1, quests = {94375} },
			{ races = {96}, level = 3, area = 16593, quests = {92468} },
		},
		[3599] = { -- Searing Totem
			{ races = {2, 6, 8}, level = 10, area = 17, quests = {1527} },
			{ races = {3}, level = 10, area = 1, quests = {94468} },
			{ races = {96}, level = 10, area = 16593, quests = {97257} },
		},
		[5394] = { -- Healing Stream Totem
			{ races = {2, 6, 8}, level = 20, area = 17, quests = {96} },
			{ races = {3}, level = 20, area = 38, quests = {94505} },
		},
	},
	MAGE = {
		[28272] = { -- Polymorph: Pig
			{ races = {1, 2, 3, 4, 5, 6, 7, 8, 95, 96}, level = 60, area = 16, quests = {9364} },
		},
		[10140] = { -- Conjure Water Rank 7
			{ races = {1, 2, 3, 4, 5, 6, 7, 8, 95, 96}, level = 60, area = 2557, quests = {7463} },
		},
	},
	WARLOCK = {
		[688] = { -- Summon Imp
			{ races = {5}, level = 1, area = 85, quests = {1470} },
			{ races = {2, 8}, level = 1, area = 14, quests = {1485} },
			{ races = {1}, level = 1, area = 12, quests = {1598} },
			{ races = {7}, level = 1, area = 1, quests = {1599} },
		},
		[697] = { -- Summon Voidwalker
			{ races = {5}, level = 10, area = 1497, quests = {1471} },
			{ races = {2, 8}, level = 10, area = 1637, quests = {1504} },
			{ races = {1, 7}, level = 10, area = 1519, quests = {1689} },
		},
		[712] = { -- Summon Succubus
			{ races = {5}, level = 20, area = 1497, quests = {1474} },
			{ races = {2, 8}, level = 20, area = 1637, quests = {1513} },
			{ races = {1, 7}, level = 20, area = 1519, quests = {1739} },
		},
		[713] = { -- Summon Incubus
			{ races = {5}, level = 20, area = 1497, quests = {65597} },
			{ races = {2, 8}, level = 20, area = 1637, quests = {65604} },
			{ races = {1, 7}, level = 20, area = 17, quests = {65603} },
		},
		[691] = { -- Summon Felhunter
			{ races = {1, 2, 5, 7, 8}, level = 30, area = 17, quests = {1795} },
		},
		[5784] = { -- Summon Felsteed
			{ races = {1, 2, 5, 7, 8}, level = 40, area = 17, quests = {4490} },
		},
		[1122] = { -- Inferno
			{ races = {1, 2, 5, 7, 8}, level = 50, area = 361, quests = {7603} },
		},
		[18540] = { -- Ritual of Doom
			{ races = {1, 2, 5, 7, 8}, level = 60, area = 4, quests = {7583} },
		},
		[23161] = { -- Summon Dreadsteed
			{ races = {1, 2, 5, 7, 8}, level = 60, area = 46, quests = {7631} },
		},
	},
	DRUID = {
		[5487] = { -- Bear Form
			{ races = {4}, level = 10, area = 1657, quests = {6001} },
			{ races = {6}, level = 10, area = 1638, quests = {6002} },
			{ races = {95, 96}, level = 10, area = 16593, quests = {94638} },
		},
		[18960] = { -- Teleport: Moonglade
			{ races = {4}, level = 10, area = 1657, quests = {5921} },
			{ races = {6}, level = 10, area = 1638, quests = {5922} },
			{ races = {96}, level = 10, area = 1638, quests = {94913} },
			{ races = {95}, level = 10, area = 1519, quests = {94914} },
		},
		[768] = { -- Cat Form
			{ races = {4, 95}, level = 20, area = 1657, quests = {98397} },
			{ races = {6, 96}, level = 20, area = 1638, quests = {98362} },
		},
		[8946] = { -- Cure Poison
			{ races = {4}, level = 14, area = 1657, quests = {6125} },
			{ races = {6}, level = 14, area = 1638, quests = {6130} },
		},
		[1066] = { -- Aquatic Form
			{ races = {4}, level = 16, area = 1657, quests = {5061} },
			{ races = {6}, level = 16, area = 1638, quests = {31} },
		},
	},
}

---------------------------------------------------------------------------
-- Weapon skills and the masters who teach them. Forever shares Classic
-- Era's masters. D.weapons[skill spellID] = { classes, level, cost, order,
-- trainers = { Alliance = { ... }, Horde = { ... } } }; each trainer is
-- { npc, names (by locale), zone (AreaTable id), uiMapID, x, y }.
---------------------------------------------------------------------------
do
	local IRONFORGE = 1537
	local STORMWIND = 1519
	local DARNASSUS = 1657
	local ORGRIMMAR = 1637
	local THUNDER_BLUFF = 1638
	local UNDERCITY = 1497

	local ONE_HANDED_AXES = 196
	local TWO_HANDED_AXES = 197
	local ONE_HANDED_MACES = 198
	local TWO_HANDED_MACES = 199
	local POLEARMS = 200
	local ONE_HANDED_SWORDS = 201
	local TWO_HANDED_SWORDS = 202
	local STAVES = 227
	local BOWS = 264
	local GUNS = 266
	local DAGGERS = 1180
	local THROWN = 2567
	local CROSSBOWS = 5011
	local FIST_WEAPONS = 15590
	D.weaponSkillNames = {
		Axes = ONE_HANDED_AXES, ["One-Handed Axes"] = ONE_HANDED_AXES, ["Two-Handed Axes"] = TWO_HANDED_AXES,
		Maces = ONE_HANDED_MACES, ["One-Handed Maces"] = ONE_HANDED_MACES, ["Two-Handed Maces"] = TWO_HANDED_MACES,
		Swords = ONE_HANDED_SWORDS, ["One-Handed Swords"] = ONE_HANDED_SWORDS, ["Two-Handed Swords"] = TWO_HANDED_SWORDS,
		Polearms = POLEARMS, Staves = STAVES, Bows = BOWS, Guns = GUNS, Daggers = DAGGERS,
		Thrown = THROWN, Crossbows = CROSSBOWS, ["Fist Weapons"] = FIST_WEAPONS,
	}

	local zones = {
		[IRONFORGE] = { uiMapId = 1455, iconId = 135757 },
		[STORMWIND] = { uiMapId = 1453, iconId = 135763 },
		[DARNASSUS] = { uiMapId = 1457, iconId = 135755 },
		[ORGRIMMAR] = { uiMapId = 1454, iconId = 135759 },
		[THUNDER_BLUFF] = { uiMapId = 1456, iconId = 135765 },
		[UNDERCITY] = { uiMapId = 1458, iconId = 135766 },
	}

	local weaponSkills = {
		[ONE_HANDED_AXES] = {
			classes = {
				WARRIOR = true, PALADIN = true, HUNTER = true, SHAMAN = true,
			},
		},
		[TWO_HANDED_AXES] = {
			classes = {
				WARRIOR = true, PALADIN = true, HUNTER = true, SHAMAN = false,
			},
		},
		[ONE_HANDED_MACES] = {
			classes = {
				WARRIOR = true, PALADIN = true, ROGUE = true, PRIEST = true,
				SHAMAN = true, DRUID = true,
			},
		},
		[TWO_HANDED_MACES] = {
			classes = {
				WARRIOR = true, PALADIN = true, SHAMAN = false, DRUID = true,
			},
		},
		[POLEARMS] = {
			classes = {
				WARRIOR = true, PALADIN = true, HUNTER = true, DRUID = true,
			},
			requiredLevel = 20,
			costCopper = 10000,
		},
		[ONE_HANDED_SWORDS] = {
			classes = {
				WARRIOR = true, PALADIN = true, HUNTER = true, ROGUE = true,
				MAGE = true, WARLOCK = true,
			},
		},
		[TWO_HANDED_SWORDS] = {
			classes = {
				WARRIOR = true, PALADIN = true, HUNTER = true,
			},
		},
		[STAVES] = {
			classes = {
				WARRIOR = true, HUNTER = true, PRIEST = true, SHAMAN = true,
				DRUID = true, WARLOCK = true, MAGE = true,
			},
		},
		[BOWS] = {
			classes = {
				WARRIOR = true, HUNTER = true, ROGUE = true,
			},
		},
		[GUNS] = {
			classes = {
				WARRIOR = true, HUNTER = true, ROGUE = true,
			},
		},
		[DAGGERS] = {
			classes = {
				WARRIOR = true, HUNTER = true, ROGUE = true, PRIEST = true,
				SHAMAN = true, DRUID = true, WARLOCK = true, MAGE = true,
			},
		},
		[THROWN] = {
			classes = {
				WARRIOR = true, HUNTER = true, ROGUE = true,
			},
		},
		[CROSSBOWS] = {
			classes = {
				WARRIOR = true, HUNTER = true, ROGUE = true,
			},
		},
		[FIST_WEAPONS] = {
			classes = {
				WARRIOR = true, HUNTER = true, ROGUE = true, SHAMAN = true,
				DRUID = true,
			},
		},
	}

	local weaponMasters = {
		[11865] = {
			faction = "Alliance",
			location = { zoneId = IRONFORGE, x = 61.2, y = 89.5 },
			teaches = {
				[ONE_HANDED_AXES] = true,
				[TWO_HANDED_AXES] = true,
				[ONE_HANDED_MACES] = true,
				[TWO_HANDED_MACES] = true,
				[GUNS] = true,
				[FIST_WEAPONS] = true,
			},
			names = {
				enUS = "Buliwyf Stonehand",
				esES = "Buliwyf Petramano",
				koKR = "불리위프 스톤헤드",
				ptBR = "Bulif Manopedra",
				ruRU = "Бульвайф Крепкорук",
				zhCN = "布里维夫·石手",
				zhTW = "布里維夫·石拳",
			},
		},
		[13084] = {
			faction = "Alliance",
			location = { zoneId = IRONFORGE, x = 62.2, y = 89.6 },
			teaches = {
				[DAGGERS] = true,
				[THROWN] = true,
				[CROSSBOWS] = true,
			},
			names = {
				enUS = "Bixi Wobblebonk",
				esES = "Bixi Tambaleapié",
				koKR = "빅시 와블봉크",
				ptBR = "Bixi Bateagita",
				ruRU = "Бикси Пошатушка",
				zhCN = "比克斯",
				zhTW = "比克斯",
			},
		},
		[11867] = {
			faction = "Alliance",
			location = { zoneId = STORMWIND, x = 57.1, y = 57.7 },
			teaches = {
				[POLEARMS] = true,
				[ONE_HANDED_SWORDS] = true,
				[TWO_HANDED_SWORDS] = true,
				[STAVES] = true,
				[DAGGERS] = true,
				[CROSSBOWS] = true,
			},
			names = {
				enUS = "Woo Ping",
				koKR = "우 핑",
				ruRU = "Ву Пинг",
				zhCN = "吴平",
				zhTW = "吳平",
			},
		},
		[11866] = {
			faction = "Alliance",
			location = { zoneId = DARNASSUS, x = 57.7, y = 46.0 },
			teaches = {
				[STAVES] = true,
				[BOWS] = true,
				[DAGGERS] = true,
				[THROWN] = true,
				[FIST_WEAPONS] = true,
			},
			names = {
				enUS = "Ilyenia Moonfire",
				esES = "Ilyenia Fuegolunar",
				koKR = "일예니아 문파이어",
				ptBR = "Ilyenia Flameluna",
				ruRU = "Илиения Лунное Пламя",
				zhCN = "伊琳尼雅·月火",
				zhTW = "伊琳尼雅·月火",
			},
		},
		[2704] = {
			faction = "Horde",
			location = { zoneId = ORGRIMMAR, x = 81.5, y = 19.6 },
			teaches = {
				[ONE_HANDED_AXES] = true,
				[TWO_HANDED_AXES] = true,
				[STAVES] = true,
				[BOWS] = true,
				[THROWN] = true,
			},
			names = {
				enUS = "Hanashi",
				koKR = "하나시",
				ruRU = "Ханаши",
				zhCN = "哈纳什",
				zhTW = "哈納什",
			},
		},
		[11868] = {
			faction = "Horde",
			location = { zoneId = ORGRIMMAR, x = 81.7, y = 19.6 },
			teaches = {
				[ONE_HANDED_AXES] = true,
				[TWO_HANDED_AXES] = true,
				[STAVES] = true,
				[BOWS] = true,
				[DAGGERS] = true,
				[THROWN] = true,
				[FIST_WEAPONS] = true,
			},
			names = {
				enUS = "Sayoc",
				koKR = "사요크",
				ruRU = "Сайок",
				zhCN = "塞尤克",
				zhTW = "塞尤克",
			},
		},
		[11869] = {
			faction = "Horde",
			location = { zoneId = THUNDER_BLUFF, x = 40.0, y = 63.1 },
			teaches = {
				[ONE_HANDED_MACES] = true,
				[TWO_HANDED_MACES] = true,
				[STAVES] = true,
				[GUNS] = true,
			},
			names = {
				enUS = "Ansekhwa",
				koKR = "안세크화",
				ruRU = "Ансеква",
				zhCN = "安塞瓦",
				zhTW = "安塞瓦",
			},
		},
		[11870] = {
			faction = "Horde",
			location = { zoneId = UNDERCITY, x = 57.3, y = 32.8 },
			teaches = {
				[POLEARMS] = true,
				[ONE_HANDED_SWORDS] = true,
				[TWO_HANDED_SWORDS] = true,
				[DAGGERS] = true,
				[CROSSBOWS] = true,
			},
			names = {
				enUS = "Archibald",
				koKR = "아키발드",
				ptBR = "Arquibaldo",
				ruRU = "Арчибальд",
				zhCN = "阿基巴德",
				zhTW = "阿基巴德",
			},
		},
	}

	local skillOrder = {
		ONE_HANDED_AXES,
		TWO_HANDED_AXES,
		ONE_HANDED_MACES,
		TWO_HANDED_MACES,
		ONE_HANDED_SWORDS,
		TWO_HANDED_SWORDS,
		DAGGERS,
		FIST_WEAPONS,
		STAVES,
		POLEARMS,
		BOWS,
		GUNS,
		CROSSBOWS,
		THROWN,
	}

	-- Forever's Stormwind map includes the Harbor, which shifts every coordinate on it.
	weaponMasters[11867].location.x, weaponMasters[11867].location.y = 63.9, 69.1 -- Woo Ping
	-- Forever lets these classes learn more weapons than Classic Era.
	weaponSkills[ONE_HANDED_AXES].classes.ROGUE = true
	weaponSkills[TWO_HANDED_AXES].classes.SHAMAN = true
	weaponSkills[TWO_HANDED_MACES].classes.SHAMAN = true

	D.weaponOrder = skillOrder
	D.weapons = {}
	for index, id in ipairs(skillOrder) do
		local skill = weaponSkills[id]
		D.weapons[id] = {
			classes = skill.classes,
			level = skill.requiredLevel or 1,
			cost = skill.costCopper or 1000,
			order = index,
			trainers = { Alliance = {}, Horde = {} },
		}
	end
	for npc, master in pairs(weaponMasters) do
		local location = master.location
		local zone = zones[location.zoneId]
		local trainer = {
			npc = npc, names = master.names, faction = master.faction,
			zone = location.zoneId, uiMapID = zone.uiMapId, icon = zone.iconId,
			x = location.x, y = location.y,
		}
		for skillID in pairs(master.teaches) do
			table.insert(D.weapons[skillID].trainers[master.faction], trainer)
		end
	end
end
