-- EldoUI Class Bar data: what the bar shows for each class other than the
-- shaman (who has the Shaman Totems cooldown bar).
--
--   upkeep  slot keys of the class buff reminders (Modules/Reminders.lua):
--           the bar keeps the same spell and rank pick as the reminder, so
--           one pick serves both. Rogue poisons are the poison slots.
--   spells  key cooldowns: { id = rank 1 spell ID, key, name (English, the
--           option's label until the game names it), optional race ID }.
--           An icon shows once you know the spell; a click casts the chosen
--           rank, or the highest by default. Race spells and their options
--           belong to that race only.
--   counts  reagents the class spends: { key, name (a translated key
--           when it names several items), items (any of them counts,
--           summed), spells (shown once you know one of them; none: while
--           you carry some) }, or ammo = true for the ammo in
--           the ammo slot.
-- Spell IDs from the WoW: Forever trainer data (Data/Training/*.lua) and
-- the talent spells of the keybind categories (Data/KeybindCategories.lua).
-- Written from scratch for EldoUI.
-- The spell IDs here are checked against the WoW: Forever client tables of
-- build 1.60.1.70938.
local _, E = ...

E.ClassBarData = {
	WARRIOR = {
		upkeep = { "WARRIOR_SHOUT" },
		spells = {
			{ id = 2687, key = "bloodrage", name = "Bloodrage" },
			{ id = 18499, key = "berserkerrage", name = "Berserker Rage" },
			{ id = 5246, key = "intimidating", name = "Intimidating Shout" },
			{ id = 871, key = "shieldwall", name = "Shield Wall" },
			{ id = 12975, key = "laststand", name = "Last Stand" }, -- talent
			{ id = 20230, key = "retaliation", name = "Retaliation" },
			{ id = 1719, key = "recklessness", name = "Recklessness" },
			{ id = 12328, key = "deathwish", name = "Death Wish" }, -- talent
			{ id = 1310222, key = "spearingstrike", name = "Spearing Strike" }, -- talent
		},
		counts = {},
	},
	PALADIN = {
		upkeep = { "PALADIN_AURA", "PALADIN_SEAL", "PALADIN_BLESSING", "PALADIN_RF" },
		spells = {
			{ id = 853, key = "hammer", name = "Hammer of Justice" },
			{ id = 498, key = "protection", name = "Divine Protection" },
			{ id = 642, key = "shield", name = "Divine Shield" },
			{ id = 1022, key = "blessingprotection", name = "Blessing of Protection" },
			{ id = 1044, key = "freedom", name = "Blessing of Freedom" },
			{ id = 20216, key = "favor", name = "Divine Favor" }, -- talent
			{ id = 20473, key = "holyshock", name = "Holy Shock" }, -- talent
			{ id = 26573, key = "consecration", name = "Consecration" },
			{ id = 633, key = "layonhands", name = "Lay on Hands" },
			{ id = 407632, key = "hammeroftherighteous", name = "Hammer of the Righteous" },
		},
		counts = {
			{ key = "kings", items = { 21177 }, spells = { 25782, 25894, 25898 }, name = "Symbol of Kings" }, -- for greater blessings
			{ key = "divinity", items = { 17033 }, spells = { 19752 }, name = "Symbol of Divinity" }, -- for Divine Intervention
		},
	},
	HUNTER = {
		upkeep = { "HUNTER_ASPECT", "HUNTER_TRUESHOT" },
		spells = {
			{ id = 3045, key = "rapidfire", name = "Rapid Fire" },
			{ id = 19574, key = "bestialwrath", name = "Bestial Wrath" }, -- talent
			{ id = 19577, key = "intimidation", name = "Intimidation" }, -- talent
			{ id = 19503, key = "scattershot", name = "Scatter Shot" }, -- talent
			{ id = 1499, key = "freezingtrap", name = "Freezing Trap" },
			{ id = 781, key = "disengage", name = "Disengage" },
			{ id = 19263, key = "deterrence", name = "Deterrence" }, -- talent
			{ id = 5384, key = "feigndeath", name = "Feign Death" },
			{ id = 136, key = "mendpet", name = "Mend Pet" },
			{ id = 1293241, key = "summonhawk", name = "Summon Hawk" }, -- talent
			{ id = 1310687, key = "snipershot", name = "Sniper Shot" }, -- talent
			{ id = 1317257, key = "striderkick", name = "Strider Kick" }, -- talent
			{ id = 1221404, key = "enchantedflare", name = "Enchanted Flare" },
		},
		counts = {
			{ key = "ammo", ammo = true },
		},
	},
	ROGUE = {
		upkeep = { "ROGUE_POISON", "ROGUE_POISON_OFF" },
		spells = {
			{ id = 1766, key = "kick", name = "Kick" },
			{ id = 2094, key = "blind", name = "Blind" },
			{ id = 5277, key = "evasion", name = "Evasion" },
			{ id = 2983, key = "sprint", name = "Sprint" },
			{ id = 1856, key = "vanish", name = "Vanish" },
			{ id = 14177, key = "coldblood", name = "Cold Blood" }, -- talent
			{ id = 13750, key = "adrenaline", name = "Adrenaline Rush" }, -- talent
			{ id = 13877, key = "bladeflurry", name = "Blade Flurry" }, -- talent
			{ id = 14185, key = "preparation", name = "Preparation" }, -- talent
			{ id = 1316709, key = "deathmark", name = "Death Mark" }, -- talent
		},
		counts = {
			{ key = "flash", items = { 5140 }, spells = { 1856 }, name = "Flash Powder" }, -- for Vanish
			{ key = "blinding", items = { 5530 }, spells = { 2094 }, name = "Blinding Powder" }, -- for Blind
		},
	},
	PRIEST = {
		upkeep = { "PRIEST_INNER", "PRIEST_FORT", "PRIEST_SPIRIT", "PRIEST_SHADOWPROT", "PRIEST_FEARWARD", "PRIEST_SHADOWGUARD", "PRIEST_TOUCH" },
		spells = {
			{ id = 586, key = "fade", name = "Fade" },
			{ id = 8122, key = "scream", name = "Psychic Scream" },
			{ id = 15487, key = "silence", name = "Silence" }, -- talent
			{ id = 14751, key = "innerfocus", name = "Inner Focus" }, -- talent
			{ id = 10060, key = "powerinfusion", name = "Power Infusion" }, -- talent
			{ id = 402174, key = "penance", name = "Penance" }, -- talent
			{ id = 1309595, key = "shadowworddeath", name = "Shadow Word: Death" },
			{ id = 13908, key = "desperate", name = "Desperate Prayer", race = 3 },
			{ id = 1277370, key = "divinegrace", name = "Divine Grace", race = 1 },
			{ id = 13896, key = "feedback", name = "Feedback", race = 1 },
			{ id = 1277331, key = "chastise", name = "Chastise", race = 3 },
			{ id = 10797, key = "starshards", name = "Starshards", race = 4 },
			{ id = 2651, key = "elunesgrace", name = "Elune's Grace", race = 4 },
			{ id = 1277455, key = "confoundingflash", name = "Confounding Flash", race = 7 },
			{ id = 1277462, key = "contingencyplan", name = "Contingency Plan", race = 7 },
			{ id = 1277324, key = "darksacrifice", name = "Dark Sacrifice", race = 5 },
		},
		counts = {
			{ key = "candles", items = { 17028, 17029 }, spells = { 21562, 27683, 27681 }, name = E.Key("Holy and Sacred Candles") }, -- for prayers
			{ key = "feathers", items = { 17056 }, spells = { 1706 }, name = "Light Feather" }, -- for Levitate
		},
	},
	MAGE = {
		upkeep = { "MAGE_ARMOR", "MAGE_INT" },
		spells = {
			{ id = 2139, key = "counterspell", name = "Counterspell" },
			{ id = 122, key = "frostnova", name = "Frost Nova" },
			{ id = 1953, key = "blink", name = "Blink" },
			{ id = 11426, key = "icebarrier", name = "Ice Barrier" }, -- talent
			{ id = 1463, key = "manashield", name = "Mana Shield" },
			{ id = 11958, key = "iceblock", name = "Ice Block" }, -- talent
			{ id = 12472, key = "coldsnap", name = "Cold Snap" }, -- talent
			{ id = 12043, key = "presence", name = "Presence of Mind" }, -- talent
			{ id = 12042, key = "arcanepower", name = "Arcane Power" }, -- talent
			{ id = 11129, key = "combustion", name = "Combustion" }, -- talent
			{ id = 12051, key = "evocation", name = "Evocation" },
			{ id = 1312002, key = "icelance", name = "Ice Lance" }, -- talent
		},
		counts = {
			{ key = "powder", items = { 17020 }, spells = { 23028 }, name = "Arcane Powder" }, -- for Arcane Brilliance
			{ key = "teleport", items = { 17031 }, spells = { 3561, 3562, 3563, 3565, 3566, 3567, 1297659 }, name = "Rune of Teleportation" },
			{ key = "portals", items = { 17032 }, spells = { 10059, 11416, 11417, 11418, 11419, 11420 }, name = "Rune of Portals" },
			{ key = "feathers", items = { 17056 }, spells = { 130, 1302508 }, name = "Light Feather" }, -- for Slow Fall and Study
		},
	},
	WARLOCK = {
		upkeep = { "WARLOCK_ARMOR" },
		spells = {
			{ id = 6789, key = "deathcoil", name = "Death Coil" },
			{ id = 5484, key = "howl", name = "Howl of Terror" },
			{ id = 6229, key = "shadowward", name = "Shadow Ward" },
			{ id = 17877, key = "shadowburn", name = "Shadowburn" }, -- talent
			{ id = 18288, key = "amplify", name = "Amplify Curse" }, -- talent
			{ id = 18708, key = "feldomination", name = "Fel Domination" }, -- talent
		},
		counts = {
			{ key = "shards", items = { 6265 }, name = "Soul Shard" },
		},
	},
	DRUID = {
		upkeep = { "DRUID_MOTW", "DRUID_THORNS", "DRUID_OMEN" },
		spells = {
			{ id = 5211, key = "bash", name = "Bash" },
			{ id = 1850, key = "dash", name = "Dash" },
			{ id = 22812, key = "barkskin", name = "Barkskin" },
			{ id = 22842, key = "frenzied", name = "Frenzied Regeneration" },
			{ id = 17116, key = "swiftness", name = "Nature's Swiftness" }, -- talent
			{ id = 29166, key = "innervate", name = "Innervate" },
			{ id = 740, key = "tranquility", name = "Tranquility" },
			{ id = 20484, key = "rebirth", name = "Rebirth" },
			{ id = 1238122, key = "feralcharge", name = "Feral Charge" }, -- talent
			{ id = 407995, key = "primalbite", name = "Primal Bite" }, -- talent
			{ id = 1322605, key = "shiftingpower", name = "Shifting Power" }, -- talent
		},
		counts = {
			{ key = "thornroot", items = { 17026 }, spells = { 21849 }, name = "Wild Thornroot" }, -- for Gift of the Wild
			{ key = "seeds", items = { 17034, 17035, 17036, 17037, 17038 }, spells = { 20484 }, name = E.Key("Rebirth seeds") }, -- the seeds Rebirth uses
		},
	},
}
