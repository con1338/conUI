-- EldoUI CastFX: which school (and so which theme) a spell of the
-- player belongs to. The game has no spell-school call for addons, so this
-- is our own table, written by hand for EldoUI from game knowledge (no data
-- from another addon).
--
-- Each list holds the rank 1 spell ID of a spell. CastFX asks the client
-- for that spell's name and icon at login, so every rank, and every client
-- language, matches through the name or the icon as well. A spell the table
-- misses falls back to the class theme; the player can pin any spell to a
-- theme on the CastFX page. `/eui castfx dump` prints the spells of your
-- spellbook with their IDs, to extend this table.
--
--   schools[school]        = { spellID, ... }   rank 1 IDs
--   professions[theme]     = { spellID, ... }   profession casts
-- The spell IDs here are checked against the WoW: Forever client tables of
-- build 1.60.1.70938.
local _, E = ...

E.CastFXSpells = {
	schools = {
		arcane = {
			5143, 12051, 118, 1449, 5504, 587, 759, 1463, 604, 1008, 130, 1459, 23028, 475, 2139,
			3561, 3562, 3565, 3567, 3563, 3566, 10059, 11416, 11419, 11417, 11418, 11420, 6117, -- mage
			18960, -- Teleport: Moonglade
		},
		fire = {
			133, 11366, 2948, 2120, 2136, 543, 11113, -- mage
			348, 5676, 6353, 5740, 1949, 17962, 6366, 1122, -- warlock
			8050, 3599, 408341, 8190, 8024, -- shaman
		},
		frost = {
			116, 10, 120, 122, 168, 6143, 11426, 11958, -- mage
			8056, 8033, 131, 546, -- shaman
		},
		shadow = {
			686, 172, 980, 5782, 689, 1120, 5138, 755, 688, 697, 712, 691, 698, 6201, 693, 710,
			1098, 5484, 1454, 17877, 6789, 5784, 23161, 687, 706, 126, 2362, 18265, 702, 704,
			1714, 1311676, 603, 18223, 6229, 18540, 5500, -- warlock
			8092, 589, 15407, 605, 8129, 8122, 2944, 9035, 2652, 15286, 15473, 976, -- priest
		},
		holy = {
			585, 2050, 2054, 2060, 2061, 139, 17, 14914, 596, 2006, 15237, 9484, 527, 1243, 588,
			14752, 552, 528, 13908, 10797, 6346, 724, 21562, 2651, -- priest
			635, 19750, 7328, 24275, 879, 2812, 26573, 642, 633, 13819, 23214, 2878, 465, 20473,
			4987, 1152, 19752, 20217, 19740, 19742, 20925, -- paladin
		},
		nature = {
			403, 421, 331, 8004, 1064, 2008, 8042, 370, 2645, 556, 6196, 324, 5394, 2484, 8071,
			8075, 5675, 8143, 8177, 526, 2870, 8017, 8232, -- shaman
			5176, 2912, 8921, 5185, 8936, 774, 339, 2637, 16914, 740, 20484, 5570, 2908, 770,
			1126, 467, 2782, 2893, 8946, 21849, 29166, 22812, 18562, -- druid
			982, 136, 1515, 1002, 1513, 1978, 3034, -- hunter
		},
		physical = {
			19434, 2643, 1510, 3044, 5116, 1130, 1543, 883, 2641, 6991, 20736, 19801, -- hunter
			1240193, 1464, 8820, 11604, 11605, 1310196, 1310197, 1310198, 1310199, 1310200, -- warrior (Slam, Improved Slam)
			1804, 1842, 6770, 2094, -- rogue
		},
	},
	professions = {
		mining = { 2575, 2580, 2656 },        -- Mining, Find Minerals, Smelting
		herbalism = { 2366, 2383 },           -- Herb Gathering, Find Herbs
		fishing = { 7620 },                   -- Fishing
		crafting = {
			8613, 13262, 2550, 3273, 2259, 2018, 7411, 4036, 2108, 3908, -- skinning, disenchant, crafts
			3365, -- Opening
		},
	},
}
