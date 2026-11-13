-- EldoUI key map: one home for every class spell, per role. Each button of
-- the main action block has one category, the same on every character, so
-- interrupt, movement, defensive and control spells sit under the same keys
-- on every alt, and a role change moves only the rotation.
--
--   Bar 1 (plain keys)  1-5 your rotation or heals, 6 interrupt, 7 movement
--                       ability, 8 hard control, 9 short defensive, 10 long
--                       defensive or emergency, 11 self sustain, 12 main
--                       cooldown
--   Bar 2 (Shift)       1-5 second rotation, area and resource spells,
--                       6 second stop, 7 second movement, 8 second control,
--                       9 group defensive, 10 cleanse, 11 offensive dispel,
--                       12 support or rescue
--   Bar 3 (Ctrl)        the 3x3 box of what you use between pulls: 1-5
--                       class utility, 6 role utility, 7 travel,
--                       8 resurrection, 9 class buff. Its keys 10-12 press
--                       the Consumable Bar (health potion, healthstone, and
--                       a mana potion or a bandage), see C.consumableKeys.
--
-- The fight spells are on bars 1 and 2, the easy keys; bar 3 holds only
-- spells for between pulls, and a few long cooldowns (longCooldown) whose
-- key the cooldown display shows.
--
-- Bar 1 pages: a Warrior's bar 1 has one page per stance, a Rogue's a
-- Stealth page, a Druid's a Cat Form and a Bear Form page. A button keeps
-- its category on every page; only its spell changes. Bars 2 and 3 never
-- page.
--
-- Per class, every button and role has one state: a spell (its ranks,
-- highest first, and the spells that replace each other: the first one
-- you know wins), reserved (the class has nothing for that category; the
-- reason says where the nearest thing is) or open (your own pick, and
-- why). An entry is one of those, or a list of them per role and page:
--
--   { spells, roles, page, note, tier, talent, longCooldown }
--   { reserved = reason, roles, page }
--   { open = reason, roles, page }
--
-- roles: "tank", "healer", "melee" or "ranged", or a list; left out: every
-- role of the class. page: "battle", "defensive" or "berserker"
-- (Warrior), "stealth" (Rogue), "cat" or "bear" (Druid), or a list; left
-- out: the normal page (no stance, out of Stealth, caster form) and every
-- page without an entry of its own. tier: how often the spell is pressed,
-- 1 (rotation) to 5 (outside a fight), one number or one per role.
--
-- A spell that belongs off the action bars has a fixed place instead
-- (C.offBar): the stance bar, the pet bar, the totem bar, tracking, the
-- travel menu, the spellbook (you place it yourself), the crafting window
-- or passive. Spells new to WoW: Forever wait in C.pending until their
-- home is settled; they are never placed or shown as a home.
--
-- Every spell below comes from EldoUI's own class data for WoW: Forever:
-- the trainer lists (Training/<Class>.lua), the class quest spells
-- (Training/Shared.lua), the class premades (ClassPremades.lua) and the
-- talents and starting spells of each class; Forever's own spell table
-- confirms each one. Spell names are read from the game when shown.
-- Nothing here acts in play: the How to play preview shows the spells, and
-- only its Apply, when you tick it, puts known ones on empty buttons.
-- Written from scratch for EldoUI.
-- The spell IDs here are checked against the WoW: Forever client tables of
-- build 1.60.1.70862.
local _, E = ...
local L = E.L

local Key = E.Key
local C = {}
E.keybindCategories = C

-- The key map's version: raise it when a home moves.
C.version = 1

-- Category keys of bars 1-3. Bar 3 has nine buttons: the box.
C.slots = {
	{ "core1", "core2", "core3", "core4", "core5", "interrupt", "movement", "control", "defensive", "emergency", "sustain", "cooldown" },
	{ "second1", "second2", "second3", "second4", "second5", "stop", "movement2", "control2", "groupDefensive", "cleanse", "purge", "support" },
	{ "utility1", "utility2", "utility3", "utility4", "utility5", "roleUtility", "travel", "resurrect", "buff" },
}

-- How much a category's key matters: 1 must be a visible button with a
-- key, 2 is pressed in most fights, 3 now and then.
C.categoryTier = {
	core1 = 1, core2 = 1, core3 = 1, core4 = 1, core5 = 1, interrupt = 1, movement = 1, control = 1, defensive = 1, emergency = 1,
	sustain = 2, cooldown = 2, second1 = 2, second2 = 2, second3 = 2, second4 = 2, second5 = 2, stop = 2, groupDefensive = 2, cleanse = 2,
	movement2 = 3, control2 = 3, purge = 3, support = 3,
	utility1 = 3, utility2 = 3, utility3 = 3, utility4 = 3, utility5 = 3, roleUtility = 3, travel = 3, resurrect = 3, buff = 3,
}

-- Bar 3's keys 10-12: the Consumable Bar's buttons (the button number of
-- its item), a bandage instead of the mana potion for Warriors and Rogues.
C.consumableKeys = E.keybindConsumableKeys or {
	{ key = "healthPotion", button = 3 },
	{ key = "healthstone", button = 6 },
	{ key = "manaPotion", button = 4, WARRIOR = { key = "bandage", button = 5 }, ROGUE = { key = "bandage", button = 5 } },
}

-- label: the category's name; short: its tag on a key cap (a word, so the
-- meaning never rests on color); desc: what goes there.
C.info = {
	core = { label = "Rotation", short = Key("Core"), desc = "Your main damage or healing spells for your role, in the order you press them most." },
	interrupt = { label = "Interrupt", short = Key("Kick"), desc = "Stops an enemy cast." },
	movement = { label = "Movement ability", short = Key("Move"), desc = "Gets you somewhere fast: a charge, blink or sprint." },
	control = { label = "Hard control", short = Key("CC"), desc = "Takes an enemy out for a while: a stun, fear or polymorph." },
	defensive = { label = "Short defensive", short = Key("Def"), desc = "A defensive you use often." },
	emergency = { label = "Long defensive", short = Key("Emerg"), desc = "The big defensive or emergency button." },
	sustain = { label = "Self sustain", short = Key("Sust"), desc = "Keeps you going: mana, health or a pet heal." },
	cooldown = { label = "Main cooldown", short = Key("CD"), desc = "Your main damage or healing cooldown." },
	second = { label = "Second rotation", short = Key("Sec"), desc = "Area, finisher or resource spells for your role." },
	stop = { label = "Second stop", short = Key("Stop"), desc = "A second way to stop or push away an enemy." },
	movement2 = { label = "Second movement", short = Key("Move2"), desc = "A second movement spell, or a travel form." },
	control2 = { label = "Second control", short = Key("CC2"), desc = "A root, snare or second control spell." },
	groupDefensive = { label = "Group defensive", short = Key("Grp"), desc = "Protects the group or an ally." },
	cleanse = { label = "Cleanse", short = Key("Clns"), desc = "Removes a harmful effect from an ally." },
	purge = { label = "Offensive dispel", short = Key("Purge"), desc = "Removes a helpful effect from an enemy." },
	support = { label = "Support", short = Key("Help"), desc = "Helps an ally or your pet." },
	utility = { label = "Class utility", short = Key("Util"), desc = "Spells you use now and then." },
	travel = { label = "Travel", short = Key("Trav"), desc = "A mount or travel spell you own." },
	resurrect = { label = "Resurrection", short = Key("Res"), desc = "Brings an ally back." },
	buff = { label = "Class buff", short = Key("Buff"), desc = "Your armor, aura, shield or group buff." },
	roleUtility = { label = "Role utility", short = Key("Role"), desc = "A spell for your role: a taunt, a mark or a slow fall." },
}

-- core1 -> core: numbered categories share one description.
function C.Info(key)
	if type(key) ~= "string" then return nil end
	return C.info[key] or C.info[key:gsub("%d+$", "")]
end

-- The roles each class plays, in the order the key map lists them.
C.classRoles = {
	WARRIOR = { "tank", "melee" }, PALADIN = { "tank", "healer", "melee" }, HUNTER = { "ranged" }, ROGUE = { "melee" },
	PRIEST = { "healer", "ranged" }, SHAMAN = { "healer", "melee", "ranged" }, MAGE = { "ranged" }, WARLOCK = { "ranged" },
	DRUID = { "tank", "healer", "melee", "ranged" },
}

-- The pages of bar 1 per class ("normal": no stance, out of Stealth, the
-- caster form), and the game's page (bar offset) and form of each.
-- Warriors are always in a stance, so their bar 1 never shows its own
-- buttons: their bar 1 spells go on the stance pages.
C.pages = {
	WARRIOR = { "battle", "defensive", "berserker" },
	ROGUE = { "normal", "stealth" },
	DRUID = { "normal", "cat", "bear" },
}
C.pageInfo = {
	WARRIOR = {
		battle = { offset = 1, form = { 2457 } },    -- Battle Stance
		defensive = { offset = 2, form = { 71 } },   -- Defensive Stance
		berserker = { offset = 3, form = { 2458 } }, -- Berserker Stance
	},
	ROGUE = {
		stealth = { offset = 1, form = { 1784 } },   -- Stealth
	},
	DRUID = {
		cat = { offset = 1, prowl = 2, form = { 768 } },  -- Cat Form (and Prowl)
		bear = { offset = 3, form = { 9634, 5487 } },     -- Dire Bear Form, else Bear Form
	},
}
C.alwaysPaged = { WARRIOR = true }

---------------------------------------------------------------------------
-- Classes
---------------------------------------------------------------------------

C.classes = {
	-- Warrior (tank, melee). Bar 1 pages by stance.
	WARRIOR = {
		-- Bar 1
		core1 = { spells = { 25286, 11567, 11566, 11565, 11564, 1608, 285, 284, 78 }, tier = 1 }, -- Heroic Strike
		core2 = {
			{ spells = { 11585, 11584, 7887, 7384 }, tier = { tank = 4, melee = 2 } }, -- Overpower
			{ page = "defensive", spells = { 25288, 11601, 11600, 7379, 6574, 6572 }, tier = { tank = 1, melee = 5 } }, -- Revenge
			{ page = "berserker", spells = { 1680 }, tier = { tank = 5, melee = 1 } }, -- Whirlwind
		},
		core3 = {
			{ spells = { 20662, 20661, 20660, 20658, 5308 }, tier = 2 }, -- Execute
			{ page = "defensive", spells = { 11597, 11596, 8380, 7405, 7386 }, tier = { tank = 1, melee = 4 } }, -- Sunder Armor
		},
		core4 = {
			{ spells = { 11574, 11573, 11572, 6548, 6547, 6546, 772 }, tier = { tank = 4, melee = 3 } }, -- Rend
			{ roles = "tank", page = "berserker", open = Key("Tanks rarely fight in Berserker Stance; your own pick.") },
			{ roles = "melee", page = "berserker", spells = { 23894, 23893, 23892, 23881 }, tier = 1, talent = true }, -- Bloodthirst (talent)
		},
		core5 = {
			{ roles = "tank", open = Key("Mortal Strike is an Arms talent; your own pick.") },
			{ roles = "tank", page = "defensive", spells = { 23925, 23924, 23923, 23922 }, tier = 1, talent = true }, -- Shield Slam (talent)
			{ roles = "tank", page = "berserker", open = Key("Your own pick for Berserker Stance.") },
			{ roles = "melee", spells = { 21553, 21552, 21551, 12294 }, tier = 1, talent = true }, -- Mortal Strike (talent)
			{ roles = "melee", page = "defensive", open = Key("Shield Slam is a tank talent; your own pick.") },
			{ roles = "melee", page = "berserker", spells = { 11597, 11596, 8380, 7405, 7386 }, tier = 4 }, -- Sunder Armor
		},
		interrupt = {
			{ spells = { 1672, 1671, 72 }, note = Key("Pummel in Berserker Stance, Shield Bash with a shield."), tier = 3 }, -- Shield Bash
			{ page = "berserker", spells = { 6554, 6552 }, note = Key("Pummel in Berserker Stance, Shield Bash with a shield."), tier = 3 }, -- Pummel
		},
		movement = {
			{ spells = { 11578, 6178, 100 }, note = Key("Charge in Battle Stance, Intercept in Berserker Stance."), tier = 2 }, -- Charge
			{ roles = "tank", page = "defensive", spells = { 355 }, note = Key("No movement spell in Defensive Stance: Taunt takes this key."), tier = 1 }, -- Taunt
			{ page = "berserker", spells = { 20617, 20616, 20252 }, note = Key("Charge in Battle Stance, Intercept in Berserker Stance."), tier = 3 }, -- Intercept
			{ roles = "melee", page = "defensive", spells = { 1240289, 1240288, 1240287 }, note = Key("Charge works in Defensive Stance with the Vanguard talent."), tier = 3, talent = true }, -- Charge (Vanguard)
		},
		control = { spells = { 5246 }, note = Key("A fear, not a stun."), tier = 4 }, -- Intimidating Shout
		defensive = {
			{ roles = "tank", spells = { 20560, 20559, 7402, 7400, 694 }, tier = 3 }, -- Mocking Blow
			{ page = "defensive", spells = { 2565 }, tier = { tank = 1, melee = 5 } }, -- Shield Block
			{ page = "berserker", spells = { 18499 }, tier = 3 }, -- Berserker Rage
			{ roles = "melee", spells = { 12292 }, tier = 3, talent = true }, -- Sweeping Strikes (talent)
		},
		emergency = {
			{ spells = { 20230 }, tier = 4 }, -- Retaliation
			{ page = "defensive", spells = { 871 }, note = Key("Shield Wall: in Defensive Stance, with a shield."), tier = 3 }, -- Shield Wall
			{ page = "berserker", reserved = Key("Shield Wall needs Defensive Stance: it is on this button there.") },
		},
		sustain = {
			{ spells = { 402927 }, note = Key("Victory Rush: usable after a kill, it heals you."), tier = 3 }, -- Victory Rush
			{ roles = "tank", page = "defensive", spells = { 676 }, tier = 4 }, -- Disarm
		},
		cooldown = {
			{ roles = "tank", open = Key("Death Wish is a Fury talent; your own pick.") },
			{ roles = "tank", page = "defensive", spells = { 12975 }, tier = 3, talent = true }, -- Last Stand (talent)
			{ page = "berserker", spells = { 1719 }, tier = 4 }, -- Recklessness
			{ roles = "melee", spells = { 12328 }, tier = 3, talent = true }, -- Death Wish (talent)
			{ roles = "melee", page = "defensive", open = Key("Last Stand is a tank talent; your own pick.") },
		},
		-- Bar 2
		second1 = { spells = { 20569, 11609, 11608, 7369, 845 }, tier = 2 }, -- Cleave
		second2 = { spells = { 11581, 11580, 8205, 8204, 8198, 6343 }, tier = { tank = 2, melee = 4 } }, -- Thunder Clap
		second3 = { spells = { 11556, 11555, 11554, 6190, 1160 }, tier = { tank = 2, melee = 4 } }, -- Demoralizing Shout
		second4 = {
			{ roles = "tank", open = Key("Tanks have Sunder Armor on Rotation 3 of Defensive Stance; your own pick.") },
			{ roles = "melee", spells = { 1310200, 1310199, 1310198, 1310197, 1310196, 11605, 11604, 8820, 1464, 1240193 }, tier = 2 }, -- Slam (Improved Slam's first)
		},
		second5 = { spells = { 2687 }, tier = 2 }, -- Bloodrage
		stop = {
			{ roles = "tank", spells = { 12809 }, tier = 3, talent = true }, -- Concussion Blow (talent)
			{ roles = "melee", spells = { 676 }, tier = 4 }, -- Disarm
		},
		movement2 = { spells = { 25289, 11551, 11550, 11549, 6192, 5242, 6673 }, tier = 2 }, -- Battle Shout
		control2 = { spells = { 7373, 7372, 1715 }, tier = { tank = 4, melee = 2 } }, -- Hamstring
		groupDefensive = {
			{ roles = "tank", spells = { 1161 }, tier = 3 }, -- Challenging Shout
			{ roles = "melee", spells = { 12323 }, tier = 4, talent = true }, -- Piercing Howl (talent)
		},
		cleanse = { reserved = Key("Warriors have no cleanse.") },
		purge = { reserved = Key("Warriors have no offensive dispel.") },
		support = { reserved = Key("Warriors have no ally spell.") },
		-- Bar 3
		utility1 = {
			{ roles = "tank", open = Key("Your own pick.") },
			{ roles = "melee", spells = { 20560, 20559, 7402, 7400, 694 }, tier = 5 }, -- Mocking Blow
		},
		utility2 = { open = Key("Your own pick.") },
		utility3 = {
			{ roles = "tank", open = Key("Your own pick for between pulls.") },
			{ roles = "melee", open = Key("Your own pick.") },
		},
		utility4 = {
			{ roles = "tank", open = Key("Your own pick for between pulls.") },
			{ roles = "melee", open = Key("Your own pick.") },
		},
		utility5 = {
			{ roles = "tank", open = Key("Your own pick for between pulls.") },
			{ roles = "melee", open = Key("Your own pick.") },
		},
		roleUtility = {
			{ roles = "tank", open = Key("Your own pick.") },
			{ roles = "melee", open = Key("Taunt is the tank's, on the Movement ability button of Defensive Stance; your own pick.") },
		},
		travel = { open = Key("Your own pick, such as a mount (the Consumable Bar can show yours too).") },
		resurrect = { reserved = Key("Warriors have no resurrection.") },
		buff = { open = Key("Your own pick.") },
	},
	-- Paladin (tank, healer, melee).
	PALADIN = {
		-- Bar 1
		core1 = { spells = { 20271 }, tier = 1 }, -- Judgement
		core2 = {
			{ roles = "tank", spells = { 20293, 20292, 20291, 20290, 20289, 20288, 20287, 20154 }, tier = 1 }, -- Seal of Righteousness
			{ roles = "healer", spells = { 10329, 10328, 3472, 1042, 1026, 647, 639, 635 }, tier = 1 }, -- Holy Light
			{ roles = "melee", spells = { 20308, 20307, 20306, 20305, 20162, 21082 }, tier = 1 }, -- Seal of the Crusader
		},
		core3 = {
			{ roles = "tank", spells = { 1239570, 20928, 20927, 20925 }, tier = 1, talent = true }, -- Holy Shield (talent)
			{ roles = "healer", spells = { 19943, 19942, 19941, 19940, 19939, 19750 }, tier = 1 }, -- Flash of Light
			{ roles = "melee", spells = { 20920, 20919, 20918, 20915, 20375 }, tier = 1, talent = true }, -- Seal of Command (talent)
		},
		core4 = {
			{ roles = "tank", spells = { 20924, 20923, 20922, 20116, 26573 }, tier = 1 }, -- Consecration
			{ roles = "healer", spells = { 20930, 20929, 20473, 1311606 }, tier = 2, talent = true }, -- Holy Shock (talent)
			{ roles = "melee", spells = { 10333, 10332, 5569, 2495, 680, 1866, 678, 679 }, tier = 2 }, -- Holy Strike
		},
		core5 = {
			{ roles = { "tank", "melee" }, spells = { 10314, 10313, 10312, 5615, 5614, 879 }, tier = 4 }, -- Exorcism
			{ roles = "healer", spells = { 20357, 20356, 20166 }, tier = 2 }, -- Seal of Wisdom
		},
		interrupt = {
			{ roles = { "tank", "melee" }, spells = { 10308, 5589, 5588, 853 }, note = Key("Paladins have no interrupt: Hammer of Justice stuns the caster."), tier = 3 }, -- Hammer of Justice
			{ roles = "healer", spells = { 4987, 1152 }, note = Key("Paladins have no interrupt: healers get Cleanse on this key."), tier = 1 }, -- Cleanse
		},
		movement = { spells = { 1044 }, note = Key("Frees an ally (or you) from movement effects."), tier = 3 }, -- Blessing of Freedom
		control = {
			{ roles = "tank", reserved = Key("Hammer of Justice is on the Interrupt button, where tanks stop casts.") },
			{ roles = "healer", spells = { 10308, 5589, 5588, 853 }, note = Key("Hammer of Justice: a stun."), tier = 3 }, -- Hammer of Justice
			{ roles = "melee", reserved = Key("Hammer of Justice is on the Interrupt button, where melee stop casts.") },
		},
		defensive = { spells = { 5573, 498 }, tier = 3 }, -- Divine Protection
		emergency = { spells = { 1020, 642 }, tier = 3 }, -- Divine Shield
		sustain = { spells = { 10310, 2800, 633 }, tier = 3 }, -- Lay on Hands
		cooldown = { reserved = Key("No main cooldown before talents; healers have Divine Favor on Second rotation 3.") },
		-- Bar 2
		second1 = {
			{ roles = "tank", spells = { 10318, 2812 }, tier = 4 }, -- Holy Wrath
			{ roles = { "healer", "melee" }, spells = { 20924, 20923, 20922, 20116, 26573 }, tier = 4 }, -- Consecration
		},
		second2 = {
			{ roles = { "tank", "melee" }, spells = { 24239, 24274, 24275 }, tier = 3 }, -- Hammer of Wrath
			{ roles = "healer", spells = { 20349, 20348, 20347, 20165 }, tier = 2 }, -- Seal of Light
		},
		second3 = {
			{ roles = "tank", spells = { 20357, 20356, 20166 }, tier = 2 }, -- Seal of Wisdom
			{ roles = "healer", spells = { 20216 }, tier = 3, talent = true }, -- Divine Favor (talent)
			{ roles = "melee", spells = { 20293, 20292, 20291, 20290, 20289, 20288, 20287, 20154 }, tier = 2 }, -- Seal of Righteousness
		},
		second4 = {
			{ roles = "tank", spells = { 20349, 20348, 20347, 20165 }, tier = 4 }, -- Seal of Light
			{ roles = "healer", open = Key("Your own pick.") },
			{ roles = "melee", spells = { 20357, 20356, 20166 }, tier = 2 }, -- Seal of Wisdom
		},
		second5 = {
			{ roles = { "tank", "melee" }, spells = { 10329, 10328, 3472, 1042, 1026, 647, 639, 635 }, tier = 4 }, -- Holy Light
			{ roles = "healer", open = Key("Your own pick.") },
		},
		stop = { reserved = Key("Hammer of Justice is the paladin stop: on the Interrupt button for tanks and melee, on Hard control for healers.") },
		movement2 = { reserved = Key("Blessing of Freedom, on the Movement ability button, is the paladin's movement spell.") },
		control2 = { reserved = Key("Paladins have one control spell: Hammer of Justice.") },
		groupDefensive = { spells = { 20729, 6940 }, tier = 4 }, -- Blessing of Sacrifice
		cleanse = {
			{ roles = { "tank", "melee" }, spells = { 4987, 1152 }, tier = 3 }, -- Cleanse
			{ roles = "healer", reserved = Key("Healers have Cleanse on the Interrupt button: paladins have no interrupt.") },
		},
		purge = { reserved = Key("Paladins have no offensive dispel.") },
		support = { spells = { 10278, 5599, 1022 }, tier = 3 }, -- Blessing of Protection
		-- Bar 3
		utility1 = { spells = { 19838, 19837, 19836, 19835, 19834, 19740 }, tier = 5 }, -- Blessing of Might
		utility2 = { spells = { 19854, 19853, 19852, 19850, 19742 }, tier = 5 }, -- Blessing of Wisdom
		utility3 = { spells = { 25916, 25782 }, tier = 5 }, -- Greater Blessing of Might
		utility4 = { spells = { 25918, 25894 }, tier = 5 }, -- Greater Blessing of Wisdom
		utility5 = { open = Key("Your own pick.") },
		roleUtility = {
			{ roles = "tank", spells = { 25780 }, tier = 5 }, -- Righteous Fury
			{ roles = "healer", spells = { 19752 }, tier = 5 }, -- Divine Intervention
			{ roles = "melee", open = Key("Righteous Fury is the tank's; your own pick.") },
		},
		travel = { spells = { 23214, 13819 }, tier = 5 }, -- Summon Warhorse
		resurrect = { spells = { 20773, 20772, 10324, 10322, 7328 }, tier = 5 }, -- Redemption
		buff = { spells = { 25898, 20217 }, tier = 5 }, -- Blessing of Kings
	},
	-- Hunter (ranged).
	HUNTER = {
		-- Bar 1
		core1 = { spells = { 75 }, tier = 1 }, -- Auto Shot
		core2 = { spells = { 14287, 14286, 14285, 14284, 14283, 14282, 14281, 3044 }, tier = 1 }, -- Arcane Shot
		core3 = { spells = { 13555, 13554, 13553, 13552, 13551, 13550, 13549, 1978 }, tier = 1 }, -- Serpent Sting
		core4 = { spells = { 20904, 20903, 20902, 20901, 20900, 19434 }, tier = 1 }, -- Aimed Shot (a trainer spell on WoW: Forever)
		core5 = { spells = { 14266, 14265, 14264, 14263, 14262, 14261, 14260, 2973 }, tier = 2 }, -- Raptor Strike
		interrupt = { spells = { 14325, 14324, 14323, 1130 }, note = Key("Hunters have no interrupt: Hunter's Mark takes this key."), tier = 2 }, -- Hunter's Mark
		movement = { spells = { 20910, 20909, 1242634, 19306 }, tier = 3, talent = true }, -- Counterattack (talent)
		control = { spells = { 14311, 14310, 1499 }, note = Key("Freezing Trap: the enemy that steps on it freezes."), tier = 3 }, -- Freezing Trap
		defensive = { spells = { 5384 }, tier = 3 }, -- Feign Death
		emergency = { spells = { 14280, 14279, 3034 }, tier = 4 }, -- Viper Sting
		sustain = { spells = { 14271, 14270, 14269, 1495 }, tier = 2 }, -- Mongoose Bite
		cooldown = { spells = { 14295, 14294, 1510 }, tier = 4 }, -- Volley
		-- Bar 2
		second1 = { spells = { 2643 }, tier = 1 }, -- Multi-Shot
		second2 = { spells = { 14305, 14304, 14303, 14302, 13795 }, tier = 4 }, -- Immolation Trap
		second3 = { spells = { 14317, 14316, 13813 }, tier = 4 }, -- Explosive Trap
		second4 = { spells = { 13809 }, tier = 3 }, -- Frost Trap
		second5 = { spells = { 5116 }, tier = 3 }, -- Concussive Shot
		stop = { spells = { 19503 }, tier = 3, talent = true }, -- Scatter Shot (talent)
		movement2 = { spells = { 13163 }, tier = 4 }, -- Aspect of the Monkey
		control2 = { spells = { 14268, 14267, 2974 }, tier = 2 }, -- Wing Clip
		groupDefensive = { spells = { 1543 }, tier = 4 }, -- Flare
		cleanse = { spells = { 14273, 14272, 781 }, tier = 3 }, -- Disengage
		purge = { spells = { 19801 }, tier = 4 }, -- Tranquilizing Shot
		support = { spells = { 13544, 13543, 13542, 3662, 3661, 3111, 136 }, note = Key("Heals your pet."), tier = 2 }, -- Mend Pet
		-- Bar 3
		utility1 = { spells = { 19263 }, tier = 3, talent = true, longCooldown = true }, -- Deterrence (talent)
		utility2 = { spells = { 3045 }, tier = 4, longCooldown = true }, -- Rapid Fire
		utility3 = { spells = { 19574 }, tier = 3, talent = true, longCooldown = true }, -- Bestial Wrath (talent)
		utility4 = { spells = { 20190, 20043 }, tier = 5 }, -- Aspect of the Wild
		utility5 = { spells = { 5118 }, note = Key("A speed aspect, not a dash: a hit dazes you while it is on."), tier = 5 }, -- Aspect of the Cheetah
		roleUtility = { spells = { 6197 }, tier = 5 }, -- Eagle Eye
		travel = { spells = { 13159 }, tier = 5 }, -- Aspect of the Pack
		resurrect = { spells = { 982 }, tier = 5 }, -- Revive Pet
		buff = { spells = { 25296, 14322, 14321, 14320, 14319, 14318, 13165 }, tier = 5 }, -- Aspect of the Hawk
	},
	-- Rogue (melee). Bar 1 has a Stealth page.
	ROGUE = {
		-- Bar 1
		core1 = {
			{ spells = { 11294, 11293, 8621, 1760, 1759, 1758, 1757, 1752 }, tier = 1 }, -- Sinister Strike
			{ page = "stealth", spells = { 11269, 11268, 11267, 8725, 8724, 8676 }, tier = 2 }, -- Ambush
		},
		core2 = {
			{ spells = { 11300, 11299, 8624, 8623, 6762, 6761, 6760, 2098 }, tier = 1 }, -- Eviscerate
			{ page = "stealth", spells = { 11290, 11289, 8633, 8632, 8631, 703 }, tier = 2 }, -- Garrote
		},
		core3 = {
			{ spells = { 6774, 5171 }, tier = 1 }, -- Slice and Dice
			{ page = "stealth", spells = { 1833 }, tier = 2 }, -- Cheap Shot
		},
		core4 = {
			{ spells = { 11281, 11280, 11279, 8721, 2591, 2590, 2589, 53 }, tier = 1 }, -- Backstab
			{ page = "stealth", spells = { 921 }, tier = 4 }, -- Pick Pocket
		},
		core5 = {
			{ spells = { 11275, 11274, 11273, 8640, 8639, 1943 }, tier = 2 }, -- Rupture
			{ page = "stealth", spells = { 1725 }, tier = 4 }, -- Distract
		},
		interrupt = {
			{ spells = { 1769, 1768, 1767, 1766 }, tier = 3 }, -- Kick
			{ page = "stealth", spells = { 14183 }, note = Key("Kick is on this key outside Stealth."), tier = 2, talent = true }, -- Premeditation (talent)
		},
		movement = { spells = { 11305, 8696, 2983 }, tier = 3 }, -- Sprint
		control = {
			{ spells = { 8643, 408 }, note = Key("A finisher: spends combo points."), tier = 3 }, -- Kidney Shot
			{ page = "stealth", spells = { 11297, 2070, 6770 }, tier = 4 }, -- Sap
		},
		defensive = {
			{ spells = { 5277 }, tier = 3 }, -- Evasion
			{ page = "stealth", reserved = Key("Evasion is on this button outside Stealth.") },
		},
		emergency = {
			{ spells = { 1857, 1856 }, tier = 3 }, -- Vanish
			{ page = "stealth", reserved = Key("Vanish is on this button outside Stealth.") },
		},
		sustain = {
			{ spells = { 14278 }, tier = 2, talent = true }, -- Ghostly Strike (talent)
			{ page = "stealth", reserved = Key("Rogues have no self heal: your bandage is on the Consumable Bar.") },
		},
		cooldown = {
			{ spells = { 13750 }, tier = 3, talent = true }, -- Adrenaline Rush (talent)
			{ page = "stealth", spells = { 14185 }, tier = 4, talent = true }, -- Preparation (talent)
		},
		-- Bar 2
		second1 = { spells = { 13877 }, tier = 3, talent = true }, -- Blade Flurry (talent)
		second2 = { spells = { 11198, 11197, 8650, 8649, 8647 }, tier = 2 }, -- Expose Armor
		second3 = { spells = { 14251 }, tier = 2, talent = true }, -- Riposte (talent)
		second4 = { spells = { 16511 }, tier = 1, talent = true }, -- Hemorrhage (talent)
		second5 = { spells = { 14177 }, tier = 3, talent = true }, -- Cold Blood (talent)
		stop = { spells = { 2094 }, tier = 3 }, -- Blind
		movement2 = { spells = { 11303, 8637, 6768, 1966 }, tier = 2 }, -- Feint
		control2 = { spells = { 11286, 11285, 8629, 1777, 1776 }, tier = 3 }, -- Gouge
		groupDefensive = { reserved = Key("Rogues have no group defensive.") },
		cleanse = { reserved = Key("Rogues have no cleanse.") },
		purge = { reserved = Key("Rogues have no offensive dispel.") },
		support = { reserved = Key("Rogues have no ally spell.") },
		-- Bar 3
		utility1 = { open = Key("Your own pick.") },
		utility2 = { spells = { 1804 }, tier = 5 }, -- Pick Lock
		utility3 = { spells = { 1842 }, tier = 5 }, -- Disarm Trap
		utility4 = { open = Key("Your own pick.") },
		utility5 = { open = Key("Your own pick.") },
		roleUtility = { open = Key("Your own pick.") },
		travel = { open = Key("Your own pick, such as a mount (the Consumable Bar can show yours too).") },
		resurrect = { reserved = Key("Rogues have no resurrection.") },
		buff = { open = Key("Your weapon poison (an item).") },
	},
	-- Priest (healer, ranged).
	PRIEST = {
		-- Bar 1
		core1 = {
			{ roles = "healer", spells = { 10917, 10916, 10915, 9474, 9473, 9472, 2061 }, tier = 1 }, -- Flash Heal
			{ roles = "ranged", spells = { 10947, 10946, 10945, 8106, 8105, 8104, 8103, 8102, 8092 }, tier = 1 }, -- Mind Blast
		},
		core2 = {
			{ roles = "healer", spells = { 25315, 10929, 10928, 10927, 6078, 6077, 6076, 6075, 6074, 139 }, tier = 1 }, -- Renew
			{ roles = "ranged", spells = { 10894, 10893, 10892, 2767, 992, 970, 594, 589 }, tier = 1 }, -- Shadow Word: Pain
		},
		core3 = {
			{ roles = "healer", spells = { 10965, 10964, 10963, 2060 }, tier = 1 }, -- Greater Heal
			{ roles = "ranged", spells = { 18807, 17314, 17313, 17312, 17311, 15407 }, tier = 1, talent = true }, -- Mind Flay (talent)
		},
		core4 = {
			{ roles = "healer", spells = { 6064, 6063, 2055, 2054, 2053, 2052, 2050 }, tier = 1 }, -- Heal (Lesser Heal before level 16)
			{ roles = "ranged", spells = { 10934, 10933, 6060, 1004, 984, 598, 591, 585 }, tier = 1 }, -- Smite
		},
		core5 = {
			{ roles = "healer", spells = { 10934, 10933, 6060, 1004, 984, 598, 591, 585 }, tier = 4 }, -- Smite
			{ roles = "ranged", spells = { 15261, 15267, 15266, 15265, 15264, 15263, 15262, 14914 }, tier = 2 }, -- Holy Fire
		},
		interrupt = {
			{ roles = "healer", spells = { 988, 527 }, note = Key("Healers get Dispel Magic on this key: it cleanses allies and purges enemies."), tier = 1 }, -- Dispel Magic
			{ roles = "ranged", spells = { 15487 }, tier = 3, talent = true }, -- Silence (talent)
		},
		-- Each race's priest spell (Desperate Prayer Dwarf, Divine Grace Human,
		-- Contingency Plan Gnome, Dark Sacrifice Undead); Night Elf and Troll
		-- priests have theirs on Shift+6 and Shift+7.
		movement = { spells = { 19243, 19242, 19241, 19240, 19238, 19236, 13908, 1277378, 1277377, 1277376, 1277374, 1277372, 1277371, 1277370, 1277640, 1277639, 1277638, 1277634, 1277462, 1277328, 1277327, 1277326, 1277325, 1277324 }, note = Key("Priests have no movement spell: your race's priest spell takes this key, if it has one here."), tier = 3 }, -- Race spell
		control = { spells = { 10890, 10888, 8124, 8122 }, note = Key("A fear, not a stun."), tier = 3 }, -- Psychic Scream
		defensive = { spells = { 10901, 10900, 10899, 10898, 6066, 6065, 3747, 600, 592, 17 }, tier = 2 }, -- Power Word: Shield
		emergency = { spells = { 10942, 10941, 9592, 9579, 9578, 586 }, tier = 3 }, -- Fade
		sustain = { spells = { 14751 }, tier = 4, talent = true }, -- Inner Focus (talent)
		cooldown = { spells = { 10060 }, tier = 4, talent = true }, -- Power Infusion (talent)
		-- Bar 2
		second1 = {
			{ roles = "healer", spells = { 10961, 10960, 996, 596 }, tier = 2 }, -- Prayer of Healing
			{ roles = "ranged", spells = { 27801, 27800, 27799, 15431, 15430, 15237 }, tier = 4, talent = true }, -- Holy Nova (talent)
		},
		second2 = {
			{ roles = "healer", spells = { 27801, 27800, 27799, 15431, 15430, 15237 }, tier = 4, talent = true }, -- Holy Nova (talent)
			{ roles = "ranged", spells = { 15286 }, tier = 2, talent = true }, -- Vampiric Embrace (talent)
		},
		second3 = {
			{ roles = "healer", open = Key("Your own pick.") }, -- Lightwell is no longer learned on WoW: Forever
			{ roles = "ranged", spells = { 10876, 10875, 10874, 8131, 8129 }, tier = 4 }, -- Mana Burn
		},
		second4 = {
			{ roles = "healer", spells = { 15261, 15267, 15266, 15265, 15264, 15263, 15262, 14914 }, tier = 4 }, -- Holy Fire
			{ roles = "ranged", spells = { 10917, 10916, 10915, 9474, 9473, 9472, 2061 }, tier = 3 }, -- Flash Heal
		},
		second5 = {
			{ roles = "healer", spells = { 10894, 10893, 10892, 2767, 992, 970, 594, 589 }, tier = 4 }, -- Shadow Word: Pain
			{ roles = "ranged", spells = { 25315, 10929, 10928, 10927, 6078, 6077, 6076, 6075, 6074, 139 }, tier = 4 }, -- Renew
		},
		-- The race's attack spell first (Starshards Night Elf, Hex of Weakness
		-- Troll, Chastise Dwarf, Confounding Flash Gnome); Devouring Plague,
		-- every priest's on WoW: Forever, takes the key for the others.
		stop = { spells = { 19305, 19304, 19303, 19302, 19299, 19296, 10797, 19285, 19284, 19283, 19282, 19281, 9035, 1277335, 1277334, 1277333, 1277332, 1277331, 1277455, 19280, 19279, 19278, 19277, 19276, 2944 }, tier = 4 }, -- Race spell, else Devouring Plague
		movement2 = { spells = { 2651, 19312, 19311, 19310, 19309, 19308, 18137, 19275, 19274, 19273, 19271, 13896, 19266, 19265, 19264, 19262, 19261, 2652 }, tier = 4 }, -- Racial: Elune's Grace, Shadowguard, Feedback or Touch of Weakness
		control2 = { spells = { 10955, 9485, 9484 }, tier = 4 }, -- Shackle Undead
		groupDefensive = { spells = { 6346 }, tier = 4 }, -- Fear Ward
		cleanse = {
			{ roles = "healer", reserved = Key("Healers have Dispel Magic on the Interrupt button: it cleanses allies and purges enemies.") },
			{ roles = "ranged", spells = { 988, 527 }, tier = 3 }, -- Dispel Magic
		},
		purge = {
			{ roles = "healer", reserved = Key("Dispel Magic works on enemies too: healers have it on the Interrupt button.") },
			{ roles = "ranged", reserved = Key("Dispel Magic works on enemies too: it is on the Cleanse button.") },
		},
		support = { spells = { 552, 528 }, tier = 4 }, -- Abolish Disease
		-- Bar 3
		utility1 = { spells = { 10952, 10951, 1006, 602, 7128, 588 }, tier = 5 }, -- Inner Fire
		utility2 = { open = Key("Your own pick.") },
		utility3 = { spells = { 27681, 27841, 14819, 14818, 14752 }, tier = 5 }, -- Divine Spirit (a trainer spell on WoW: Forever)
		utility4 = { open = Key("Your own pick.") },
		utility5 = { open = Key("Your own pick.") },
		roleUtility = { spells = { 1706 }, tier = 5 }, -- Levitate
		travel = { open = Key("Your own pick, such as a mount (the Consumable Bar can show yours too).") },
		resurrect = { spells = { 20770, 10881, 10880, 2010, 2006 }, tier = 5 }, -- Resurrection
		buff = { spells = { 10938, 10937, 2791, 1245, 1244, 1243 }, tier = 5 }, -- Power Word: Fortitude
	},
	-- Shaman (healer, melee, ranged).
	SHAMAN = {
		-- Bar 1
		core1 = {
			{ roles = "healer", spells = { 10396, 10395, 8005, 959, 939, 913, 547, 332, 331 }, tier = 1 }, -- Healing Wave
			{ roles = "melee", spells = { 17364 }, tier = 1, talent = true }, -- Stormstrike (talent)
			{ roles = "ranged", spells = { 15208, 15207, 10392, 10391, 6041, 943, 915, 548, 529, 403 }, tier = 1 }, -- Lightning Bolt
		},
		core2 = {
			{ roles = "healer", spells = { 10468, 10467, 10466, 8010, 8008, 8004 }, tier = 1 }, -- Lesser Healing Wave
			{ roles = "melee", spells = { 10448, 10447, 8053, 8052, 8050 }, tier = 1 }, -- Flame Shock
			{ roles = "ranged", spells = { 10605, 2860, 930, 421 }, tier = 1 }, -- Chain Lightning
		},
		core3 = {
			{ roles = "healer", spells = { 10623, 10622, 1064 }, tier = 1 }, -- Chain Heal
			{ roles = "melee", spells = { 10473, 10472, 8058, 8056 }, tier = 2 }, -- Frost Shock
			{ roles = "ranged", spells = { 10448, 10447, 8053, 8052, 8050 }, tier = 1 }, -- Flame Shock
		},
		core4 = {
			{ roles = { "healer", "melee" }, spells = { 15208, 15207, 10392, 10391, 6041, 943, 915, 548, 529, 403 }, tier = 4 }, -- Lightning Bolt
			{ roles = "ranged", spells = { 10473, 10472, 8058, 8056 }, tier = 2 }, -- Frost Shock
		},
		core5 = {
			{ roles = "healer", spells = { 10473, 10472, 8058, 8056 }, tier = 4 }, -- Frost Shock
			{ roles = "melee", spells = { 10605, 2860, 930, 421 }, tier = 4 }, -- Chain Lightning
			{ roles = "ranged", open = Key("Your own pick.") },
		},
		interrupt = { spells = { 10414, 10413, 10412, 8046, 8045, 8044, 8042 }, note = Key("Check in game that Earth Shock interrupts on this client."), tier = 3 }, -- Earth Shock
		movement = { spells = { 2645 }, note = Key("A form: faster on foot, no spells while in it."), tier = 4 }, -- Ghost Wolf
		control = { reserved = Key("Shamans have no hard control; Earthbind Totem, on Second control, slows instead.") },
		defensive = { spells = { 408510, 10432, 10431, 8134, 945, 905, 325, 324 }, tier = 2 }, -- Lightning Shield
		emergency = { reserved = Key("No big defensive: Nature's Swiftness and a heal are the emergency.") },
		sustain = {
			{ roles = "healer", spells = { 1325256, 17359, 17354, 16190 }, tier = 4, talent = true }, -- Mana Tide Totem (talent)
			{ roles = { "melee", "ranged" }, spells = { 10396, 10395, 8005, 959, 939, 913, 547, 332, 331 }, tier = 3 }, -- Healing Wave
		},
		cooldown = {
			{ roles = "healer", spells = { 16188 }, tier = 3, talent = true }, -- Nature's Swiftness (talent)
			{ roles = { "melee", "ranged" }, spells = { 16166, 425336 }, tier = 4, talent = true }, -- Lightning Mastery (talent)
		},
		-- Bar 2
		second1 = {
			{ roles = "healer", spells = { 10605, 2860, 930, 421 }, tier = 4 }, -- Chain Lightning
			{ roles = { "melee", "ranged" }, spells = { 10468, 10467, 10466, 8010, 8008, 8004 }, tier = 3 }, -- Lesser Healing Wave
		},
		second2 = {
			{ roles = "healer", spells = { 10448, 10447, 8053, 8052, 8050 }, tier = 4 }, -- Flame Shock
			{ roles = { "melee", "ranged" }, open = Key("Your own pick.") },
		},
		second3 = { open = Key("Your own pick: totems sit on the totem bar.") },
		second4 = { open = Key("Your own pick: totems sit on the totem bar.") },
		second5 = { open = Key("Your own pick: totems sit on the totem bar.") },
		stop = { spells = { 8177 }, note = Key("Takes one harmful spell aimed at the group."), tier = 3 }, -- Grounding Totem
		movement2 = { reserved = Key("Ghost Wolf, on the Movement ability button, is the shaman's movement spell.") },
		control2 = { spells = { 2484 }, tier = 4 }, -- Earthbind Totem
		groupDefensive = { reserved = Key("Your totems protect the group: the totem bar.") },
		cleanse = { spells = { 526 }, tier = 4 }, -- Cure Poison
		purge = { spells = { 8012, 370 }, tier = 4 }, -- Purge
		support = { spells = { 2870 }, tier = 4 }, -- Cure Disease
		-- Bar 3
		utility1 = { spells = { 16362, 10486, 8235, 8232, 16342, 16341, 16339, 8030, 8027, 8024, 16316, 16315, 16314, 10399, 8019, 8018, 8017 }, tier = 5 }, -- Rockbiter Weapon
		utility2 = { spells = { 131 }, tier = 5 }, -- Water Breathing
		utility3 = { spells = { 546 }, tier = 5 }, -- Water Walking
		utility4 = { spells = { 6196 }, tier = 5 }, -- Far Sight
		utility5 = { open = Key("Your own pick.") },
		roleUtility = { spells = { 36936 }, tier = 5 }, -- Totemic Recall
		travel = { spells = { 556 }, tier = 5 }, -- Astral Recall
		resurrect = { spells = { 20777, 20776, 20610, 20609, 2008 }, tier = 5 }, -- Ancestral Spirit
		buff = { open = Key("Lightning Shield is on the Short defensive button; your own pick.") },
	},
	-- Mage (ranged).
	MAGE = {
		-- Bar 1
		core1 = { spells = { 10181, 10180, 10179, 8408, 8407, 8406, 7322, 837, 205, 116 }, tier = 1 }, -- Frostbolt
		core2 = { spells = { 10151, 10150, 10149, 10148, 8402, 8401, 8400, 3140, 145, 143, 133 }, tier = 1 }, -- Fireball
		core3 = { spells = { 10199, 10197, 8413, 8412, 2138, 2137, 2136 }, tier = 1 }, -- Fire Blast
		core4 = { spells = { 10212, 10211, 8417, 8416, 5145, 5144, 5143 }, tier = 2 }, -- Arcane Missiles
		core5 = { spells = { 10207, 10206, 10205, 8446, 8445, 8444, 2948 }, tier = 2 }, -- Scorch
		interrupt = { spells = { 2139 }, tier = 3 }, -- Counterspell
		movement = { spells = { 1953 }, tier = 3 }, -- Blink
		control = { spells = { 12826, 12825, 12824, 118, 28272 }, note = Key("Turns the enemy into a sheep; damage breaks it."), tier = 3 }, -- Polymorph
		defensive = { spells = { 10230, 6131, 865, 122 }, note = Key("Frost Nova: roots the enemies around you so you can step away."), tier = 3 }, -- Frost Nova
		emergency = { spells = { 11958 }, note = Key("Ice Block: a Frost talent."), tier = 3, talent = true }, -- Ice Block (talent)
		sustain = { spells = { 12051 }, tier = 4 }, -- Evocation
		cooldown = { spells = { 12042, 11129, 12043 }, tier = 4, talent = true }, -- Arcane Power, Combustion or Presence of Mind (talent)
		-- Bar 2
		second1 = { spells = { 10202, 10201, 8439, 8438, 8437, 1449 }, tier = 2 }, -- Arcane Explosion
		second2 = { spells = { 10187, 10186, 10185, 8427, 6141, 10 }, tier = 4 }, -- Blizzard
		second3 = { spells = { 10216, 10215, 8423, 8422, 2121, 2120 }, tier = 4 }, -- Flamestrike
		second4 = { spells = { 18809, 12526, 12525, 12524, 12523, 12522, 12505, 11366 }, tier = 2, talent = true }, -- Pyroblast (talent)
		second5 = { spells = { 10193, 10192, 10191, 8495, 8494, 1463 }, tier = 3 }, -- Mana Shield
		stop = { spells = { 13021, 13020, 13019, 13018, 11113 }, tier = 3, talent = true }, -- Blast Wave (talent)
		movement2 = { spells = { 13033, 13032, 13031, 11426 }, tier = 3, talent = true }, -- Ice Barrier (talent)
		control2 = { spells = { 10161, 10160, 10159, 8492, 120 }, tier = 2 }, -- Cone of Cold
		groupDefensive = { spells = { 10225, 10223, 8458, 8457, 543 }, tier = 4 }, -- Fire Ward
		cleanse = { spells = { 475 }, tier = 3 }, -- Remove Lesser Curse
		purge = { spells = { 10177, 8462, 8461, 6143 }, tier = 4 }, -- Frost Ward
		support = { spells = { 12472 }, tier = 4, talent = true }, -- Cold Snap (talent)
		-- Bar 3
		utility1 = { spells = { 22783, 22782, 6117, 10220, 10219, 7320, 7302, 7301, 7300, 168 }, tier = 5 }, -- Frost Armor, Ice Armor or Mage Armor
		utility2 = { spells = { 10174, 10173, 8451, 8450, 604 }, tier = 5 }, -- Dampen Magic
		utility3 = { spells = { 10170, 10169, 8455, 1008 }, tier = 5 }, -- Amplify Magic
		utility4 = { spells = { 10054, 10053, 3552, 759 }, tier = 5 }, -- Conjure Mana Gem (Agate, Jade, Citrine, Ruby)
		utility5 = { spells = { 10140, 10139, 10138, 6127, 5506, 5505, 5504 }, tier = 5 }, -- Conjure Water
		roleUtility = { spells = { 130 }, tier = 5 }, -- Slow Fall
		travel = { open = Key("Your own pick, such as a mount; teleports and portals are in the travel menu.") },
		resurrect = { spells = { 28612, 10145, 10144, 6129, 990, 597, 587 }, tier = 5 }, -- Conjure Food
		buff = { spells = { 10157, 10156, 1461, 1460, 1459 }, tier = 5 }, -- Arcane Intellect
	},
	-- Warlock (ranged).
	WARLOCK = {
		-- Bar 1
		core1 = { spells = { 11661, 11660, 11659, 7641, 1106, 1088, 705, 695, 686 }, tier = 1 }, -- Shadow Bolt
		core2 = { spells = { 11672, 11671, 7648, 6223, 6222, 172 }, tier = 1 }, -- Corruption
		core3 = { spells = { 11713, 11712, 11711, 6217, 1014, 980 }, tier = 1 }, -- Bane of Agony
		core4 = { spells = { 11668, 11667, 11665, 2941, 1094, 707, 348 }, tier = 1 }, -- Immolate
		core5 = { spells = { 11700, 11699, 7651, 709, 699, 689 }, tier = 2 }, -- Drain Life
		interrupt = { spells = { 17926, 17925, 6789 }, note = Key("Death Coil stops a cast; your Felhunter's Spell Lock is on the pet bar."), tier = 3 }, -- Death Coil
		movement = { spells = { 18647, 710 }, note = Key("Warlocks have no movement spell: Banish takes this key."), tier = 4 }, -- Banish
		control = { spells = { 6215, 6213, 5782 }, note = Key("A fear, not a stun."), tier = 3 }, -- Fear
		defensive = { spells = { 11708, 11707, 7646, 6205, 1108, 702 }, tier = 4 }, -- Curse of Weakness
		emergency = { spells = { 11740, 11739, 6229 }, tier = 3 }, -- Shadow Ward
		sustain = { spells = { 11689, 11688, 11687, 1456, 1455, 1454 }, note = Key("Trades health for mana."), tier = 1 }, -- Life Tap
		cooldown = { spells = { 18288, 18708 }, tier = 4, talent = true }, -- Amplify Curse or Fel Domination (talent)
		-- Bar 2
		second1 = { spells = { 11678, 11677, 6219, 5740 }, tier = 4 }, -- Rain of Fire
		second2 = { spells = { 11684, 11683, 1949 }, tier = 4 }, -- Hellfire
		second3 = { spells = { 11675, 8289, 8288, 1120 }, tier = 4 }, -- Drain Soul
		second4 = { spells = { 17923, 17922, 17921, 17920, 17919, 5676 }, tier = 2 }, -- Searing Pain
		second5 = { spells = { 18881, 18880, 18879, 18265, 18932, 18931, 18930, 17962, 1293818, 1293817, 18871, 18870, 18869, 18868, 18867, 17877 }, tier = 2, talent = true }, -- Conflagrate, Shadowburn or Siphon Life (talent)
		stop = { spells = { 11719, 1714 }, tier = 4 }, -- Curse of Tongues
		movement2 = { spells = { 11717, 7659, 7658, 704 }, tier = 4 }, -- Curse of Recklessness
		control2 = { spells = { 17928, 5484 }, tier = 3 }, -- Howl of Terror
		groupDefensive = { reserved = Key("A Soulstone on an ally is the warlock's ally save: Create Soulstone is on the Resurrection button.") },
		cleanse = { reserved = Key("Your Felhunter's Devour Magic is on the pet bar.") },
		purge = { spells = { 11704, 11703, 6226, 5138 }, tier = 4 }, -- Drain Mana
		support = { spells = { 11695, 11694, 11693, 3700, 3699, 3698, 755 }, note = Key("Heals your demon."), tier = 2 }, -- Health Funnel
		-- Bar 3
		utility1 = { spells = { 5697 }, tier = 5 }, -- Unending Breath
		utility2 = { spells = { 698 }, tier = 5 }, -- Ritual of Summoning
		utility3 = { spells = { 126 }, tier = 5 }, -- Eye of Kilrogg
		utility4 = { spells = { 11743, 2970, 132 }, tier = 5 }, -- Detect Invisibility
		utility5 = { spells = { 17953, 17952, 17951, 6366 }, tier = 5 }, -- Create Firestone
		roleUtility = { spells = { 11730, 11729, 5699, 6202, 6201 }, tier = 5 }, -- Create Healthstone
		travel = { spells = { 23161, 5784 }, tier = 5 }, -- Summon Felsteed, then Dreadsteed
		resurrect = { spells = { 20757, 20756, 20755, 20752, 693 }, tier = 5 }, -- Create Soulstone
		buff = { spells = { 11735, 11734, 11733, 1086, 706, 696, 687 }, tier = 5 }, -- Demon Armor (Demon Skin before)
	},
	-- Druid (tank, healer, melee, ranged). Bar 1 has a Cat Form and a Bear Form page.
	DRUID = {
		-- Bar 1
		core1 = {
			{ roles = { "tank", "melee", "ranged" }, spells = { 9912, 8905, 6780, 5180, 5179, 5178, 5177, 5176 }, tier = { tank = 4, melee = 4, ranged = 1 } }, -- Wrath
			{ page = "cat", spells = { 9850, 9849, 5201, 3029, 16942 }, tier = 1 }, -- Claw
			{ page = "bear", spells = { 9881, 9880, 9745, 8972, 6809, 6808, 6807 }, tier = 1 }, -- Maul
			{ roles = "healer", spells = { 9889, 9888, 9758, 8903, 6778, 5189, 5188, 5187, 5186, 5185 }, tier = 1 }, -- Healing Touch
		},
		core2 = {
			{ roles = { "tank", "melee", "ranged" }, spells = { 9835, 9834, 9833, 8929, 8928, 8927, 8926, 8925, 8924, 8921 }, tier = { tank = 4, melee = 4, ranged = 1 } }, -- Moonfire
			{ page = "cat", spells = { 9896, 9894, 9752, 9493, 9492, 1079 }, tier = 1 }, -- Rip
			{ page = "bear", spells = { 9908, 9754, 769, 780, 779 }, tier = 1 }, -- Swipe
			{ roles = "healer", spells = { 25299, 9841, 9840, 9839, 8910, 3627, 2091, 2090, 1430, 1058, 774 }, tier = 1 }, -- Rejuvenation
		},
		core3 = {
			{ roles = { "tank", "melee", "ranged" }, spells = { 9876, 9875, 8951, 8950, 8949, 2912 }, tier = { tank = 5, melee = 5, ranged = 1 } }, -- Starfire
			{ page = "cat", spells = { 9830, 9829, 8992, 6800, 5221 }, tier = 1 }, -- Shred
			{ page = "bear", spells = { 9898, 9747, 9490, 1735, 99 }, tier = 2 }, -- Demoralizing Roar
			{ roles = "healer", spells = { 9858, 9857, 9856, 9750, 8941, 8940, 8939, 8938, 8936 }, tier = 1 }, -- Regrowth
		},
		core4 = {
			{ roles = { "tank", "melee", "ranged" }, spells = { 24977, 24976, 24975, 24974, 5570 }, tier = { tank = 5, melee = 5, ranged = 1 }, talent = true }, -- Insect Swarm (talent)
			{ page = "cat", spells = { 22829, 22828, 22827, 22568, 1328618 }, tier = 1 }, -- Ferocious Bite
			{ page = "bear", spells = { 5229 }, tier = 2 }, -- Enrage
			{ roles = "healer", spells = { 18562 }, tier = 3, talent = true }, -- Swiftmend (talent)
		},
		core5 = {
			{ roles = { "tank", "melee", "ranged" }, spells = { 9907, 9749, 778, 770 }, tier = 2 }, -- Faerie Fire
			{ page = "cat", spells = { 9904, 1824, 1823, 1822 }, tier = 2 }, -- Rake
			{ page = "bear", open = Key("Your own pick for Bear Form.") },
			{ roles = "healer", spells = { 9835, 9834, 9833, 8929, 8928, 8927, 8926, 8925, 8924, 8921 }, tier = 4 }, -- Moonfire
		},
		interrupt = {
			{ roles = { "tank", "melee", "ranged" }, reserved = Key("Druids have no interrupt; Bash in Bear Form is a stun.") },
			{ page = "cat", spells = { 9913, 6783, 5215 }, note = Key("Druids have no interrupt: Prowl takes this key in Cat Form."), tier = 2 }, -- Prowl
			{ roles = "tank", page = "bear", spells = { 6795 }, note = Key("Druids have no interrupt: the bear's taunt takes this key."), tier = 1 }, -- Growl
			{ roles = "healer", spells = { 2782 }, note = Key("Druids have no interrupt: healers get Remove Curse on this key."), tier = 3 }, -- Remove Curse
			{ roles = { "healer", "melee", "ranged" }, page = "bear", reserved = Key("Bash, on Hard control, is the bear's stop.") },
		},
		movement = {
			{ reserved = Key("Dash needs Cat Form; Travel Form is on the stance bar.") },
			{ page = "cat", spells = { 9821, 1850 }, note = Key("In Cat Form."), tier = 3 }, -- Dash
			{ page = "bear", spells = { 1238122 }, tier = 3, talent = true }, -- Feral Charge (talent)
		},
		control = {
			{ spells = { 18658, 18657, 2637 }, tier = 4 }, -- Hibernate
			{ page = "cat", spells = { 9827, 9823, 9005 }, tier = 2 }, -- Pounce
			{ page = "bear", spells = { 8983, 6798, 5211 }, note = Key("In Bear Form: a short stun."), tier = 3 }, -- Bash
		},
		defensive = {
			{ spells = { 22812 }, tier = 3 }, -- Barkskin
			{ page = "cat", spells = { 9892, 9000, 8998 }, tier = 3 }, -- Cower
			{ page = "bear", spells = { 22842 }, tier = 3 }, -- Frenzied Regeneration
		},
		emergency = {
			{ spells = { 17116 }, tier = 3, talent = true }, -- Nature's Swiftness (talent)
			{ page = "cat", reserved = Key("Leave Cat Form for Barkskin and Nature's Swiftness: they are on the caster page.") },
			{ page = "bear", spells = { 5209 }, tier = 3 }, -- Challenging Roar
		},
		sustain = {
			{ roles = { "tank", "melee", "ranged" }, spells = { 25299, 9841, 9840, 9839, 8910, 3627, 2091, 2090, 1430, 1058, 774 }, tier = 3 }, -- Rejuvenation
			{ page = "cat", spells = { 9867, 9866, 6787, 6785 }, tier = 2 }, -- Ravage
			{ page = "bear", reserved = Key("Frenzied Regeneration is on the Short defensive button.") },
			{ roles = "healer", open = Key("Innervate, on Main cooldown, is your mana; your own pick.") },
		},
		cooldown = {
			{ spells = { 29166 }, tier = 4 }, -- Innervate
			{ page = "cat", spells = { 5217 }, tier = 2 }, -- Tiger's Fury
			{ page = "bear", open = Key("Your own pick for Bear Form.") },
		},
		-- Bar 2
		second1 = { spells = { 17402, 17401, 16914 }, tier = 4 }, -- Hurricane
		second2 = {
			{ roles = { "tank", "melee", "ranged" }, spells = { 9889, 9888, 9758, 8903, 6778, 5189, 5188, 5187, 5186, 5185 }, tier = 4 }, -- Healing Touch
			{ roles = "healer", spells = { 9912, 8905, 6780, 5180, 5179, 5178, 5177, 5176 }, tier = 4 }, -- Wrath
		},
		second3 = {
			{ roles = { "tank", "melee", "ranged" }, spells = { 9858, 9857, 9856, 9750, 8941, 8940, 8939, 8938, 8936 }, tier = 4 }, -- Regrowth
			{ roles = "healer", spells = { 9876, 9875, 8951, 8950, 8949, 2912 }, tier = 5 }, -- Starfire
		},
		second4 = { open = Key("Your own pick.") },
		second5 = { open = Key("Your own pick.") },
		stop = { reserved = Key("Bash, on Hard control in Bear Form, is the druid stop.") },
		movement2 = { reserved = Key("Travel Form and Aquatic Form are on the stance bar.") },
		control2 = { spells = { 9853, 9852, 5196, 5195, 1062, 339 }, tier = 4 }, -- Entangling Roots
		groupDefensive = {
			{ roles = { "tank", "melee", "ranged" }, open = Key("Tranquility is the healer's; your own pick.") },
			{ roles = "healer", spells = { 9863, 9862, 8918, 740 }, tier = 4 }, -- Tranquility
		},
		cleanse = {
			{ roles = { "tank", "melee", "ranged" }, spells = { 2782 }, tier = 3 }, -- Remove Curse
			{ roles = "healer", reserved = Key("Healers have Remove Curse on the Interrupt button of the caster page: druids have no interrupt.") },
		},
		purge = { reserved = Key("Druids have no offensive dispel.") },
		support = { spells = { 2893, 8946 }, tier = 3 }, -- Abolish Poison (Cure Poison before)
		-- Bar 3
		utility1 = { open = Key("Your own pick.") },
		utility2 = { spells = { 9910, 9756, 8914, 1075, 782, 467 }, tier = 5 }, -- Thorns
		utility3 = { spells = { 16864 }, tier = 5 }, -- Omen of Clarity
		utility4 = { open = Key("Your own pick.") },
		utility5 = { spells = { 9901, 8955, 2908 }, tier = 5 }, -- Soothe Animal
		roleUtility = {
			{ roles = "tank", open = Key("Growl is on the Interrupt button of Bear Form; your own pick.") },
			{ roles = { "healer", "melee", "ranged" }, open = Key("Growl is the tank's, on the Interrupt button of Bear Form; your own pick.") },
		},
		travel = { spells = { 18960 }, tier = 5 }, -- Teleport: Moonglade
		resurrect = { spells = { 20748, 20747, 20742, 20739, 20484 }, note = Key("Works in combat; needs a reagent."), tier = 4, longCooldown = true }, -- Rebirth
		buff = { spells = { 9885, 9884, 8907, 5234, 6756, 5232, 1126 }, tier = 5 }, -- Mark of the Wild
	},
}

---------------------------------------------------------------------------
-- Off the action bars: { spells, home, roles, tier, talent }
---------------------------------------------------------------------------

C.offBar = {
	WARRIOR = {
		{ home = "stance", spells = { 2457 }, tier = 5 }, -- Battle Stance
		{ home = "stance", spells = { 71 }, tier = 5 }, -- Defensive Stance
		{ home = "stance", spells = { 2458 }, tier = 5 }, -- Berserker Stance
		{ home = "passive", spells = { 3127 }, tier = 5 }, -- Parry
		{ home = "passive", spells = { 674 }, tier = 5 }, -- Dual Wield
		{ home = "passive", spells = { 750 }, tier = 5 }, -- Plate Mail
		{ home = "passive", spells = { 1310185 }, tier = 5 }, -- Tactical Mastery
	},
	PALADIN = {
		{ roles = { "tank", "melee" }, home = "book", spells = { 19943, 19942, 19941, 19940, 19939, 19750 }, tier = 5 }, -- Flash of Light
		{ roles = { "tank", "healer" }, home = "book", spells = { 20308, 20307, 20306, 20305, 20162, 21082 }, tier = 5 }, -- Seal of the Crusader
		{ roles = "healer", home = "book", spells = { 20293, 20292, 20291, 20290, 20289, 20288, 20287, 20154 }, tier = 5 }, -- Seal of Righteousness
		{ roles = { "tank", "healer" }, home = "book", spells = { 10333, 10332, 5569, 2495, 680, 1866, 678, 679 }, tier = 5 }, -- Holy Strike
		{ roles = "healer", home = "book", spells = { 10314, 10313, 10312, 5615, 5614, 879 }, tier = 4 }, -- Exorcism
		{ roles = { "healer", "melee" }, home = "book", spells = { 10318, 2812 }, tier = 5 }, -- Holy Wrath
		{ roles = "healer", home = "book", spells = { 24239, 24274, 24275 }, tier = 4 }, -- Hammer of Wrath
		{ roles = "melee", home = "book", spells = { 20349, 20348, 20347, 20165 }, tier = 5 }, -- Seal of Light
		{ home = "book", spells = { 20164 }, tier = 5 }, -- Seal of Justice
		{ roles = { "tank", "melee" }, home = "book", spells = { 19752 }, tier = 5 }, -- Divine Intervention
		{ home = "book", spells = { 10326, 5627, 2878 }, tier = 5 }, -- Turn Undead
		{ home = "stance", spells = { 10293, 10292, 1032, 10291, 643, 10290, 465 }, tier = 5 }, -- Devotion Aura
		{ home = "stance", spells = { 10301, 10300, 10299, 10298, 7294 }, tier = 5 }, -- Retribution Aura
		{ home = "stance", spells = { 19746 }, tier = 5 }, -- Concentration Aura
		{ home = "stance", spells = { 19896, 19895, 19876 }, tier = 5 }, -- Shadow Resistance Aura
		{ home = "stance", spells = { 19898, 19897, 19888 }, tier = 5 }, -- Frost Resistance Aura
		{ home = "stance", spells = { 19900, 19899, 19891 }, tier = 5 }, -- Fire Resistance Aura
		{ home = "passive", spells = { 3127 }, tier = 5 }, -- Parry
		{ home = "passive", spells = { 750 }, tier = 5 }, -- Plate Mail
		{ home = "track", spells = { 5502 }, tier = 5 }, -- Sense Undead
	},
	HUNTER = {
		{ home = "book", spells = { 15632, 15631, 15630, 15629, 14274, 20736 }, tier = 4 }, -- Distracting Shot
		{ home = "book", spells = { 3043 }, tier = 4 }, -- Scorpid Sting
		{ home = "book", spells = { 14327, 14326, 1513 }, tier = 4 }, -- Scare Beast
		{ home = "book", spells = { 1002 }, tier = 5 }, -- Eyes of the Beast
		{ home = "book", spells = { 1462 }, tier = 5 }, -- Beast Lore
		{ home = "book", spells = { 1299447, 1299446, 1299445, 13161 }, tier = 5 }, -- Aspect of the Beast
		{ home = "pet", spells = { 883 }, tier = 5 }, -- Call Pet
		{ home = "pet", spells = { 2641 }, tier = 5 }, -- Dismiss Pet
		{ home = "pet", spells = { 6991 }, tier = 5 }, -- Feed Pet
		{ home = "pet", spells = { 1515 }, tier = 5 }, -- Tame Beast
		{ home = "pet", spells = { 5149 }, tier = 5 }, -- Beast Training
		{ home = "pet", spells = { 5042, 5041, 4194, 4193, 4192, 4191, 4190, 4189, 4188, 4187 }, tier = 5 }, -- Great Stamina (pet training)
		{ home = "pet", spells = { 24630, 24629, 24555, 24554, 24553, 24552, 24551, 24550, 24549, 24545 }, tier = 5 }, -- Natural Armor (pet training)
		{ home = "pet", spells = { 14921, 14920, 14919, 14918, 14917 }, tier = 5 }, -- Growl (pet training)
		{ home = "pet", spells = { 24445, 24444, 24439, 23992 }, tier = 5 }, -- Fire Resistance (pet training)
		{ home = "pet", spells = { 24449, 24448, 24447, 24446 }, tier = 5 }, -- Frost Resistance (pet training)
		{ home = "pet", spells = { 24507, 24506, 24505, 24488 }, tier = 5 }, -- Arcane Resistance (pet training)
		{ home = "pet", spells = { 24504, 24503, 24502, 24492 }, tier = 5 }, -- Nature Resistance (pet training)
		{ home = "pet", spells = { 24501, 24500, 24497, 24493 }, tier = 5 }, -- Shadow Resistance (pet training)
		{ home = "track", spells = { 1494 }, tier = 5 }, -- Track Beasts
		{ home = "track", spells = { 19883 }, tier = 5 }, -- Track Humanoids
		{ home = "track", spells = { 19884 }, tier = 5 }, -- Track Undead
		{ home = "track", spells = { 19885 }, tier = 5 }, -- Track Hidden
		{ home = "track", spells = { 19880 }, tier = 5 }, -- Track Elementals
		{ home = "track", spells = { 19878 }, tier = 5 }, -- Track Demons
		{ home = "track", spells = { 19882 }, tier = 5 }, -- Track Giants
		{ home = "track", spells = { 19879 }, tier = 5 }, -- Track Dragonkin
		{ home = "passive", spells = { 3127 }, tier = 5 }, -- Parry
		{ home = "passive", spells = { 674 }, tier = 5 }, -- Dual Wield
		{ home = "passive", spells = { 8737 }, tier = 5 }, -- Mail
	},
	ROGUE = {
		{ home = "stance", spells = { 1787, 1786, 1785, 1784 }, tier = 5 }, -- Stealth
		{ home = "passive", spells = { 2836 }, tier = 5 }, -- Detect Traps
		{ home = "passive", spells = { 1860 }, tier = 5 }, -- Safe Fall
		{ home = "passive", spells = { 674 }, tier = 5 }, -- Dual Wield
		{ home = "passive", spells = { 3127 }, tier = 5 }, -- Parry
		{ home = "craft", spells = { 3420 }, tier = 5 }, -- Crippling Poison
		{ home = "craft", spells = { 5763 }, tier = 5 }, -- Mind-numbing Poison
		{ home = "craft", spells = { 8687 }, tier = 5 }, -- Instant Poison II
		{ home = "craft", spells = { 2835 }, tier = 5 }, -- Deadly Poison
		{ home = "craft", spells = { 13220 }, tier = 5 }, -- Wound Poison
		{ home = "craft", spells = { 8691 }, tier = 5 }, -- Instant Poison III
		{ home = "craft", spells = { 2837 }, tier = 5 }, -- Deadly Poison II
		{ home = "craft", spells = { 8694 }, tier = 5 }, -- Mind-numbing Poison II
		{ home = "craft", spells = { 13228 }, tier = 5 }, -- Wound Poison II
		{ home = "craft", spells = { 11341 }, tier = 5 }, -- Instant Poison IV
		{ home = "craft", spells = { 11357 }, tier = 5 }, -- Deadly Poison III
		{ home = "craft", spells = { 13229 }, tier = 5 }, -- Wound Poison III
		{ home = "craft", spells = { 3421 }, tier = 5 }, -- Crippling Poison II
		{ home = "craft", spells = { 11342 }, tier = 5 }, -- Instant Poison V
		{ home = "craft", spells = { 11400 }, tier = 5 }, -- Mind-numbing Poison III
		{ home = "craft", spells = { 11358 }, tier = 5 }, -- Deadly Poison IV
		{ home = "craft", spells = { 13230 }, tier = 5 }, -- Wound Poison IV
		{ home = "craft", spells = { 11343 }, tier = 5 }, -- Instant Poison VI
		{ home = "craft", spells = { 6510 }, tier = 5 }, -- Blinding Powder
		{ home = "craft", spells = { 2842 }, tier = 5 }, -- Poisons
	},
	PRIEST = {
		{ roles = "ranged", home = "book", spells = { 10965, 10964, 10963, 2060 }, tier = 5 }, -- Greater Heal
		{ roles = "ranged", home = "book", spells = { 6064, 6063, 2055, 2054, 2053, 2052, 2050 }, tier = 5 }, -- Heal (Lesser Heal before level 16)
		{ roles = "healer", home = "book", spells = { 10947, 10946, 10945, 8106, 8105, 8104, 8103, 8102, 8092 }, tier = 5 }, -- Mind Blast
		{ roles = "ranged", home = "book", spells = { 10961, 10960, 996, 596 }, tier = 5 }, -- Prayer of Healing
		{ roles = "healer", home = "book", spells = { 10876, 10875, 10874, 8131, 8129 }, tier = 5 }, -- Mana Burn
		{ home = "stance", spells = { 15473 }, tier = 5, talent = true }, -- Shadowform (talent)
		{ home = "book", spells = { 10912, 10911, 605 }, tier = 5 }, -- Mind Control
		{ home = "book", spells = { 10953, 8192, 453 }, tier = 5 }, -- Mind Soothe
		{ home = "book", spells = { 10909, 2096 }, tier = 5 }, -- Mind Vision
		{ home = "book", spells = { 10958, 10957, 976 }, tier = 5 }, -- Shadow Protection
	},
	SHAMAN = {
		{ roles = { "melee", "ranged" }, home = "book", spells = { 10623, 10622, 1064 }, tier = 5 }, -- Chain Heal
		{ home = "book", spells = { 16356, 16355, 10456, 8038, 8033 }, tier = 5 }, -- Frostbrand Weapon
		{ home = "totem", spells = { 10428, 10427, 6392, 6391, 6390, 5730 }, tier = 5 }, -- Stoneclaw Totem
		{ home = "totem", spells = { 10408, 10407, 10406, 8155, 8154, 8071 }, tier = 5 }, -- Stoneskin Totem
		{ home = "totem", spells = { 10442, 8161, 8160, 8075 }, tier = 5 }, -- Strength of Earth Totem
		{ home = "totem", spells = { 8143 }, tier = 5 }, -- Tremor Totem
		{ home = "totem", spells = { 10438, 10437, 6365, 6364, 6363, 3599 }, tier = 5 }, -- Searing Totem
		{ home = "totem", spells = { 10587, 10586, 10585, 8190 }, tier = 5 }, -- Magma Totem
		{ home = "totem", spells = { 10479, 10478, 8181 }, tier = 5 }, -- Frost Resistance Totem
		{ home = "totem", spells = { 16387, 10526, 8249, 8227 }, tier = 5 }, -- Flametongue Totem
		{ home = "totem", spells = { 10463, 10462, 6377, 6375, 5394 }, tier = 5 }, -- Healing Stream Totem
		{ home = "totem", spells = { 10497, 10496, 10495, 5675 }, tier = 5 }, -- Mana Spring Totem
		{ home = "totem", spells = { 10538, 10537, 8184 }, tier = 5 }, -- Fire Resistance Totem
		{ home = "totem", spells = { 8166 }, tier = 5 }, -- Poison Cleansing Totem
		{ home = "totem", spells = { 8170 }, tier = 5 }, -- Disease Cleansing Totem
		{ home = "totem", spells = { 10601, 10600, 10595 }, tier = 5 }, -- Nature Resistance Totem
		{ home = "totem", spells = { 10614, 10613, 8512 }, tier = 5 }, -- Windfury Totem
		{ home = "totem", spells = { 10627, 8835 }, tier = 5 }, -- Grace of Air Totem
		{ home = "totem", spells = { 15112, 15111, 15107 }, tier = 5 }, -- Windwall Totem
		{ home = "totem", spells = { 6495 }, tier = 5 }, -- Sentry Totem
		{ home = "totem", spells = { 66844, 66843, 66842 }, tier = 5 }, -- Call of the Elements, Ancestors, Spirits (totem sets)
		{ home = "passive", spells = { 20608 }, tier = 5 }, -- Reincarnation
		{ home = "passive", spells = { 8737 }, tier = 5 }, -- Mail
	},
	MAGE = {
		{ home = "travelmenu", spells = { 3561 }, tier = 5 }, -- Teleport: Stormwind
		{ home = "travelmenu", spells = { 3562 }, tier = 5 }, -- Teleport: Ironforge
		{ home = "travelmenu", spells = { 3563 }, tier = 5 }, -- Teleport: Undercity
		{ home = "travelmenu", spells = { 3567 }, tier = 5 }, -- Teleport: Orgrimmar
		{ home = "travelmenu", spells = { 3565 }, tier = 5 }, -- Teleport: Darnassus
		{ home = "travelmenu", spells = { 3566 }, tier = 5 }, -- Teleport: Thunder Bluff
		{ home = "travelmenu", spells = { 10059 }, tier = 5 }, -- Portal: Stormwind
		{ home = "travelmenu", spells = { 11416 }, tier = 5 }, -- Portal: Ironforge
		{ home = "travelmenu", spells = { 11417 }, tier = 5 }, -- Portal: Orgrimmar
		{ home = "travelmenu", spells = { 11418 }, tier = 5 }, -- Portal: Undercity
		{ home = "travelmenu", spells = { 11419 }, tier = 5 }, -- Portal: Darnassus
		{ home = "travelmenu", spells = { 11420 }, tier = 5 }, -- Portal: Thunder Bluff
	},
	WARLOCK = {
		{ home = "pet", spells = { 688 }, tier = 5 }, -- Summon Imp
		{ home = "pet", spells = { 697 }, tier = 5 }, -- Summon Voidwalker
		{ home = "pet", spells = { 712 }, tier = 5 }, -- Summon Succubus
		{ home = "pet", spells = { 713 }, tier = 5 }, -- Summon Incubus
		{ home = "pet", spells = { 691 }, tier = 5 }, -- Summon Felhunter
		{ home = "book", spells = { 11726, 11725, 1098 }, tier = 5 }, -- Subjugate Demon
		{ home = "book", spells = { 603 }, tier = 5 }, -- Bane of Doom
		{ home = "book", spells = { 17924, 6353 }, tier = 5 }, -- Soul Fire
		{ home = "track", spells = { 5500 }, tier = 5 }, -- Sense Demons
		{ home = "book", spells = { 1122 }, tier = 5 }, -- Inferno
		{ home = "book", spells = { 18540 }, tier = 5 }, -- Ritual of Doom
		{ home = "pet", spells = { 713 }, tier = 5 }, -- Summon Incubus
		{ home = "book", spells = { 17728, 17727, 2362 }, tier = 5 }, -- Create Spellstone
	},
	DRUID = {
		{ home = "stance", spells = { 5487 }, tier = 5 }, -- Bear Form (Dire Bear Form later)
		{ home = "stance", spells = { 9634 }, tier = 5 }, -- Dire Bear Form
		{ home = "stance", spells = { 768 }, tier = 5 }, -- Cat Form
		{ home = "stance", spells = { 783 }, tier = 5 }, -- Travel Form
		{ home = "stance", spells = { 1066 }, tier = 5 }, -- Aquatic Form
		{ home = "stance", spells = { 24858 }, tier = 5, talent = true }, -- Moonkin Form (talent)
		{ home = "book", spells = { 21850, 21849 }, tier = 5 }, -- Gift of the Wild
		{ home = "track", spells = { 5225 }, tier = 5 }, -- Track Humanoids (Cat Form)
		{ home = "passive", spells = { 20719 }, tier = 5 }, -- Feline Grace
	},
}

-- Spells new to WoW: Forever whose home is settled once the game has
-- shown their names: never placed, never shown as a home.
C.pending = {
	PALADIN = {
		{ 20423, 20422, 20421, 20419, 20163, 1311656, 1311649 }, -- a Forever spell, level 10
		{ 1311595, 1311590, 1310911 }, -- a Forever talent, level 50
		{ 407632 }, -- Hammer of the Righteous, a trainer spell, level 40
	},
	HUNTER = {
		{ 20906, 20905, 19506, 1299348, 1299346 }, -- a Forever talent, level 32
		{ 1293527, 1293526, 1293525, 1293241 }, -- a Forever talent, level 36
		{ 1310786, 1310785, 1310687 }, -- a Forever talent, level 48
		{ 1221404 }, -- Enchanted Flare, a trainer spell, level 32
	},
	ROGUE = {
		{ 1241584, 1241582, 399956 }, -- a Forever talent, level 40
		{ 1329549, 1329283 }, -- Shank, a trainer spell, level 24
		{ 1325758, 1325757, 1325756, 1316709 }, -- Death Mark, a Forever talent, level 40
	},
	PRIEST = {
		{ 1309636, 1309635, 1309633, 1309595 }, -- a Forever spell, level 32
		{ 1316995, 1240721, 1240720, 402174 }, -- a Forever talent, level 40
		{ 1240827, 1240826, 401859 }, -- a Forever talent, level 50
	},
	SHAMAN = {
		{ 408345, 408344, 408343, 408342, 408341 }, -- a Forever spell, level 12
		{ 437009 }, -- a Forever spell, level 22
		{ 1239243, 1239242, 408521 }, -- a Forever talent, level 50
	},
	MAGE = {
		{ 1296017 }, -- a Forever spell, level 6
		{ 1240047, 1240046, 1240045, 1240044, 400640, 1312002 }, -- a Forever talent, level 28
		{ 1239700, 1239699, 1239697, 1239696, 400574 }, -- a Forever talent, level 30
		{ 1326082, 1326081, 1326080, 1326079 }, -- a Forever talent, level 36
		{ 1237313, 1237312, 401502 }, -- a Forever spell, level 40
	},
	WARLOCK = {
		{ 1311680, 1311677, 1311676, 440892 }, -- a Forever spell, level 20
		{ 1293813, 1293812, 412758 }, -- a Forever talent, level 50
	},
	DRUID = {
		{ 1237951, 1237950, 1237949, 1237948, 437138 }, -- a Forever spell, level 12
		{ 1238070, 1238069, 407995 }, -- a Forever talent, level 40
		{ 1238215, 1238214, 408120 }, -- a Forever talent, level 40
		{ 1235827, 1235826, 414644 }, -- a Forever spell, level 42
		{ 17329, 16813, 16812, 16811, 16810, 16689 }, -- Nature's Grasp, a trainer spell, level 10
		{ 1328616, 1328617 }, -- Lacerate, a Forever talent, level 25
	},
}

---------------------------------------------------------------------------
-- Reading the game (spell known, name, icon, page)
---------------------------------------------------------------------------
local function Try(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, value = pcall(fn, ...)
	if ok and not (E.Secret and E.Secret(value)) then return value end
end

local function Known(id)
	local book = C_SpellBook
	if not book then return false end
	return (Try(book.IsSpellKnown, id) or Try(book.IsSpellInSpellBook, id)) and true or false
end

local function Name(id)
	local name = Try(C_Spell and C_Spell.GetSpellName, id)
	return type(name) == "string" and name ~= "" and name or nil
end

local function Icon(id)
	return Try(C_Spell and C_Spell.GetSpellTexture, id)
end
C.Known, C.Name, C.Icon = Known, Name, Icon

local function FirstOf(list)
	if type(list) ~= "table" then return list end
	for _, id in ipairs(list) do if Known(id) then return id end end
	return list[#list]
end

local function PlayerClass()
	local _, class = UnitClass("player")
	if E.Secret and E.Secret(class) then return nil end
	return class
end

-- The page of bar 1 the game shows now: the stance, Stealth or form page,
-- else "normal" (a Warrior outside any stance reads as Battle Stance).
function C.CurrentPage(class)
	local pages = C.pages[class or ""]
	if not pages then return nil end
	local offset = Try(C_ActionBar and C_ActionBar.GetBonusBarOffset)
	if type(offset) == "number" and offset > 0 then
		for page, info in pairs(C.pageInfo[class] or {}) do
			if info.offset == offset or info.prowl == offset then return page end
		end
	end
	return pages[1]
end

-- The role the class data is read for: the player's own role when the
-- class plays it; the older "damage", "none" or a role the class does not
-- play read as the class's damage role.
local function ClassRole(class, role)
	local roles = C.classRoles[class or ""]
	if not roles then return role end
	for _, key in ipairs(roles) do if key == role then return role end end
	local own = E.roleClassDamage and E.roleClassDamage[class]
	for _, key in ipairs(roles) do if key == own then return own end end
	for _, key in ipairs(roles) do if key == "melee" or key == "ranged" then return key end end
	return roles[1]
end
C.ClassRole = ClassRole

-- roles of an entry: left out or "all", one role, or a list. "damage"
-- (data written for the older roles) stands for Melee and Ranged alike.
local function RoleListed(key, role)
	return key == role or (key == "damage" and (role == "melee" or role == "ranged" or (E.RoleGroup and E:RoleGroup(role) == "damage")))
end

local function ForRole(entry, role)
	local roles = entry.roles
	if roles == nil or roles == "all" or RoleListed(roles, role) then return true end
	if type(roles) == "table" then
		for _, key in ipairs(roles) do if RoleListed(key, role) then return true end end
	end
	return false
end

local function OnPage(entry, page)
	local pages = entry.page
	if type(pages) == "table" then
		for _, key in ipairs(pages) do if key == page then return true end end
		return false
	end
	return pages == page
end

-- The entry of a category for a role and page: the one naming that page
-- first, then the one without a page.
local function Pick(entry, role, page, paged)
	if type(entry) ~= "table" then return nil end
	local list = entry[1] and entry or { entry }
	local fallback
	for _, variant in ipairs(list) do
		if ForRole(variant, role) then
			if variant.page == nil then
				fallback = fallback or variant
			elseif paged and OnPage(variant, page) then
				return variant
			end
		end
	end
	return fallback
end
C.Pick = Pick

local function TierOf(variant, role)
	local tier = variant and variant.tier
	if type(tier) == "table" then return tier[role] end
	return tier
end

-- What a slot is for on a class, role and page: { key, info, state, spell,
-- name, icon, note, reason, tier, talent, longCooldown, page, form,
-- formName, offset }. state: "ready" (you know it), "unlearned" (the
-- class's spell, not learned yet), "reserved" (the class has none, reason
-- says why), "open" (your own pick, reason says why) or "missing" (data
-- added by a plugin names none yet). role defaults to yours (an older
-- "damage" reads as your class's damage role); page, on bar 1 of a class
-- that pages it, to the page the game shows now.
function C.Resolve(bar, button, class, role, page)
	local key = C.slots[bar] and C.slots[bar][button]
	local out = { key = key, info = C.Info(key), state = "open" }
	if not key then return out end
	class = class or PlayerClass()
	role = ClassRole(class, role or (E.GetRole and E:GetRole()) or "none")
	local paged = bar == 1 and C.pages[class or ""] ~= nil
	if paged then
		page = page or C.CurrentPage(class)
		out.page = page
		local info = C.pageInfo[class][page]
		if info then
			out.form, out.offset = FirstOf(info.form), info.offset
			out.formName = Name(out.form)
		end
	end
	local entry = C.classes[class or ""] and C.classes[class][key]
	local pick = Pick(entry, role, page, paged)
	if not pick then
		if entry then out.reason = L["Your role has no class spell here."] end
		return out
	end
	if pick.reserved then
		out.state, out.reason = "reserved", E:Translate(pick.reserved)
		return out
	end
	if pick.open then
		out.state, out.reason = "open", E:Translate(pick.open)
		return out
	end
	if pick.missing then
		out.state, out.reason = "missing", E:Translate(pick.missing)
		return out
	end
	local id
	for _, spell in ipairs(pick.spells or {}) do
		if Known(spell) then id = spell break end
	end
	out.state = id and "ready" or "unlearned"
	id = id or (pick.spells and pick.spells[#pick.spells])
	out.spell, out.name, out.icon, out.note = id, Name(id), Icon(id), E:Translate(pick.note)
	out.tier, out.talent, out.longCooldown = TierOf(pick, role), pick.talent, pick.longCooldown
	if not id or not Known(id) then out.reason = L["Not learned yet."] end
	return out
end

-- Every spell's home for a class and role, read once: id -> { bar,
-- button, page, tier } or { home, tier }.
local homes = {}
local function Homes(class, role)
	local cache = homes[class .. ":" .. role]
	if cache then return cache end
	cache = {}
	local block = C.classes[class] or {}
	local pages = C.pages[class]
	for bar, row in ipairs(C.slots) do
		for button, key in ipairs(row) do
			local list = (bar == 1 and pages) or { "normal" }
			for _, page in ipairs(list) do
				local pick = Pick(block[key], role, page, bar == 1 and pages ~= nil)
				for _, id in ipairs(pick and pick.spells or {}) do
					if not cache[id] then
						cache[id] = { bar = bar, button = button, page = page ~= "normal" and page or nil, tier = TierOf(pick, role) }
					end
				end
			end
		end
	end
	for _, item in ipairs(C.offBar[class] or {}) do
		if ForRole(item, role) then
			for _, id in ipairs(item.spells) do
				if not cache[id] then cache[id] = { home = item.home, tier = TierOf(item, role) } end
			end
		end
	end
	homes[class .. ":" .. role] = cache
	return cache
end

-- Where a spell (any rank) lives for a class and role: bar, button, page
-- (nil on the normal page and on bars 2 and 3; a spell on several pages
-- gives the first), or nil and its off-bar home ("stance", "pet",
-- "totem", "track", "travelmenu", "book", "craft", "passive"). nil, nil
-- when the key map does not name it.
function C.Home(class, role, spellID)
	class = class or PlayerClass()
	if not (class and C.classes[class]) then return nil, nil end
	local found = Homes(class, ClassRole(class, role or (E.GetRole and E:GetRole()) or "none"))[spellID]
	if not found then return nil, nil end
	if found.home then return nil, found.home end
	return found.bar, found.button, found.page
end

-- How often a spell is pressed for a class and role: 1 (rotation) to 5
-- (outside a fight), or nil when the key map does not name it.
function C.Tier(class, role, spellID)
	class = class or PlayerClass()
	if not (class and C.classes[class]) then return nil end
	local found = Homes(class, ClassRole(class, role or (E.GetRole and E:GetRole()) or "none"))[spellID]
	return found and found.tier or nil
end

-- Every spell on a class's buttons, for checks: { id = category }.
function C.ClassSpells(class)
	local out = {}
	for key, entry in pairs(C.classes[class] or {}) do
		local variants = entry[1] and entry or { entry }
		for _, variant in ipairs(variants) do
			for _, id in ipairs(variant.spells or {}) do out[id] = key end
		end
	end
	return out
end

-- Known spells of your class premade's bar plan that no category names
-- and that have no category of their own: shown as unassigned, so you can
-- still find a key for them. Every premade entry names its category, so
-- this list stays empty unless a plugin adds an entry without one.
function C.Unassigned(class, role)
	class = class or PlayerClass()
	role = ClassRole(class, role or (E.GetRole and E:GetRole()) or "none")
	local premade = E.GetClassPremade and E:GetClassPremade(class)
	local named = C.ClassSpells(class)
	local out, seen = {}, {}
	for _, bar in ipairs(premade and premade.bars or {}) do
		if ForRole(bar, role) and bar.category == nil then
			local inCategory = false
			for _, id in ipairs(bar.spells or {}) do if named[id] then inCategory = true end end
			local id = not inCategory and FirstOf(bar.spells)
			if id and Known(id) and not seen[id] then
				seen[id] = true
				out[#out + 1] = { spell = id, name = Name(id), icon = Icon(id) }
			end
		end
	end
	return out
end
