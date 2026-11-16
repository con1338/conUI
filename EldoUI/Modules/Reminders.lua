-- EldoUI Buff and Consumable Reminders: a large icon in the middle of the
-- screen when one of your own class buffs is missing, about to run out, or
-- known at a higher rank than the one on you, plus a row below it for the
-- elixirs, flasks, food and weapon oils/stones you chose to keep up.
-- More reminders: a missing pet, a pet on passive or the wrong demon,
-- your own custom spells, buffs a group member could give you, a missing
-- Healthstone in instances, low durability, and a low-mana note on
-- a ready check. Where they show is set per content type (open world,
-- dungeons, raids, battlegrounds, rest areas).
--
-- How it stays within the rules: it only reads the auras, tracking, pet,
-- durability and weapon enchant data the game hands every addon, skips
-- anything secret (issecretvalue), and reads no auras in combat at all
-- (InCombatLockdown gate): in combat the reminders either hide or keep
-- what they showed before the fight, frozen, never guessed.
-- Click-to-buff (opt-in, off by default): each icon gets a secure button
-- (SecureActionButtonTemplate) on top of it that casts the missing buff or
-- uses the consumable when YOU click it, one action per click. EldoUI never
-- casts by itself; the buttons' attributes are only set out of combat.
local _, E = ...
local L = E.L

local Key = E.Key
local M = E:NewModule("Reminders", {
	title = "Buff and Consumable Reminders",
	desc = "A large icon when a class buff, gathering tracking or a chosen consumable is missing or running out.",
	category = "Interface",
	defaults = {
		enabled = true,
		iconSize = 48,
		spacing = 6,
		consumableScale = 0.8,
		showLabel = true,
		highlight = "pulse",     -- missing reminders: pulse | glow (Glows page) | none
		alpha = 1,
		buffs = true,
		rank = true,
		group = true,
		askBuffs = false,        -- buffs a group member of another class could give you
		tracking = true,
		consumables = true,
		showCount = true,        -- item count on consumable icons
		remindWithoutItem = true, -- remind even with none of the item in your bags
		pets = true,             -- no pet out (hunter, warlock)
		petPassive = true,       -- pet set to passive
		demons = {},             -- [demonKey] = true/false: demons you allow (warlock)
		healthstone = true,      -- in dungeons and raids, with a warlock in the group
		xpFood = false,          -- while leveling: no XP bonus running
		customSpells = {},       -- [spellID] = true: your own buffs to keep up (any rank)
		customAdd = "",          -- option input: a spell ID to add
		customRemove = "",       -- option select: a spell ID to remove
		durability = true,       -- worn gear warning at General > Worn gear
		readyCheckMana = true,   -- low-mana note on a ready check (own mana, out of combat)
		readyCheckPercent = 50,
		clickCast = false,       -- click-to-buff secure buttons (your click only)
		threshold = 60,          -- buffs: seconds left that count as "running out"
		consumableMinutes = 3,   -- consumables: minutes left
		inCombat = false,
		showWorld = true,        -- where reminders show (content rules)
		showDungeon = true,
		showRaid = true,
		showPvP = true,
		showResting = false,
		sound = "none",          -- media id (E:PlayMedia)
		classBuffs = {},         -- [slotKey] = true/false, filled from CLASS_BUFFS below
		-- The spell and rank a class buff slot asks for: buffLines[slotKey] is
		-- the first spell ID of the picked spell ("" for Automatic: the one
		-- cast last), buffRanks[slotKey] a rank's spell ID ("" for the
		-- highest known). lastLines[slotKey] is the spell cast last.
		buffLines = {},
		buffRanks = {},
		lastLines = {},
		items = {},              -- [itemID] = { kind = "aura"|"food"|"main"|"off", spellID, spell }
		-- Shamans: an alert when the shield or a weapon imbue fades or is
		-- gone (Combat Text in combat, an alert card out of combat), and an
		-- optional sound the game plays when the shield drops.
		alerts = { shield = true, imbue = true, shieldSound = false, sound = "eldo:EldoChime" },
		-- Rogues: the poison each hand's reminder puts on with a click. A
		-- line key (POISON_LINES), "" for none (the reminder only tells), and
		-- on the off hand "main" for the main hand's pick.
		poisons = { main = "", off = "main" },
		-- Warlocks: make each stone you know and lack (one click casts the
		-- Create spell), the Spellstone or Firestone you keep up ("" for
		-- neither), and a Soulstone for the group's healer (in dungeons and
		-- raids) or, off by default, on yourself when solo.
		stones = true,
		stonePick = "",
		soulstoneGroup = true,
		soulstoneSolo = false,
	},
})

-- "Reset to defaults" keeps the player's own data and window places
-- (E:ResetModuleSettings, Core/Config.lua).
M.keepOnReset = { "customSpells", "items" }
M.keepOnResetNote = E.Key("Your own spells and chosen consumables are kept too.")

local IsSecret = E.Secret

---------------------------------------------------------------------------
-- Class buff table (EldoUI's own). Each slot is satisfied by any of its
-- spells; `ranks` are spell IDs from rank 1 upward. Names are resolved at
-- runtime with C_Spell.GetSpellInfo, so presence matches by name in any
-- locale; the rank check compares the active aura's spell ID with the
-- higher rank IDs you know.
-- More slot fields: group (count group members without it), default
-- (false: off until you turn it on), role (only for that role), minLevel,
-- missingOnly (never "running out"), weapon ("main" or "off": a weapon
-- enchant per hand instead of an aura), poison (a rogue's poison slot),
-- form (a stance or shapeshift form you should be in, read from the
-- stance bar instead of auras), shield (a shield in the off hand; no
-- spells, no click), newest (Automatic starts on the last spell you know
-- instead of the first).
-- Line fields: family (lines of one family meet each other: a buff and
-- its group version), travel (Automatic never picks it).
---------------------------------------------------------------------------
local ROGUE_POISONS = {
	{ 8681, 8687, 8691, 11341, 11342, 11343 }, -- Instant Poison
	{ 2835, 2837, 11357, 11358 },              -- Deadly Poison
	{ 3420, 3421 },                            -- Crippling Poison
	{ 5763, 8694, 11400 },                     -- Mind-numbing Poison
	{ 13220, 13228, 13229, 13230 },            -- Wound Poison
	{ 2842 },                                  -- Poisons
}

-- The poison lines a reminder can put on, with their items from rank 1
-- upward (item table of the game, build 1.60.1.70938).
local POISON_LINES = {
	{ key = "INSTANT", spells = ROGUE_POISONS[1], items = { 6947, 6949, 6950, 8926, 8927, 8928 } },
	{ key = "DEADLY", spells = ROGUE_POISONS[2], items = { 2892, 2893, 8984, 8985 } },
	{ key = "CRIPPLING", spells = ROGUE_POISONS[3], items = { 3775, 3776 } },
	{ key = "MINDNUMBING", spells = ROGUE_POISONS[4], items = { 5237, 6951, 9186 } },
	{ key = "WOUND", spells = ROGUE_POISONS[5], items = { 10918, 10920, 10921, 10922 } },
}
M.POISON_LINES = POISON_LINES

-- Shaman weapon imbues, every rank, in the order they are trained. Each
-- hand casts the one picked for it, Automatic the one cast last (else the
-- newest you know), at the highest rank known unless a rank is picked.
local SHAMAN_IMBUES = {
	{ 8017, 8018, 8019, 10399, 16314, 16315, 16316 }, -- Rockbiter Weapon
	{ 8024, 8027, 8030, 16339, 16341, 16342 },        -- Flametongue Weapon
	{ 8033, 8038, 10456, 16355, 16356 },              -- Frostbrand Weapon
	{ 8232, 8235, 10486, 16362 },                     -- Windfury Weapon
}

local CLASS_BUFFS = {
	MAGE = {
		{ key = "MAGE_INT", group = true, spells = {
			{ 1459, 1460, 1461, 10156, 10157, family = "int" }, -- Arcane Intellect
			{ 23028, family = "int" },                          -- Arcane Brilliance
		} },
		-- Ice Armor is the later line of Frost Armor, so it comes first.
		{ key = "MAGE_ARMOR", spells = {
			{ 7302, 7320, 10219, 10220 },        -- Ice Armor
			{ 168, 7300, 7301 },                 -- Frost Armor
			{ 6117, 22782, 22783 },              -- Mage Armor
		} },
	},
	PRIEST = {
		{ key = "PRIEST_FORT", group = true, spells = {
			{ 1243, 1244, 1245, 2791, 10937, 10938, family = "fort" }, -- Power Word: Fortitude
			{ 21562, 21564, family = "fort" },                         -- Prayer of Fortitude
		} },
		{ key = "PRIEST_INNER", spells = {
			{ 588, 7128, 602, 1006, 10951, 10952 },   -- Inner Fire
		} },
		-- Off by default: Shadow Protection matters for some fights only.
		{ key = "PRIEST_SHADOWPROT", group = true, default = false, spells = {
			{ 976, 10957, 10958, family = "shadow" }, -- Shadow Protection
			{ 27683, family = "shadow" },             -- Prayer of Shadow Protection
		} },
		{ key = "PRIEST_SPIRIT", group = true, spells = {
			{ 14752, 14818, 14819, 27841, family = "spirit" }, -- Divine Spirit
			{ 27681, family = "spirit" },                      -- Prayer of Spirit
		} },
		-- Off by default, shown only once known: Fear Ward (every priest),
		-- Shadowguard (Troll) and Touch of Weakness (Undead).
		{ key = "PRIEST_FEARWARD", default = false, spells = {
			{ 6346 },                                 -- Fear Ward
		} },
		{ key = "PRIEST_SHADOWGUARD", default = false, spells = {
			{ 18137, 19308, 19309, 19310, 19311, 19312 }, -- Shadowguard
		} },
		{ key = "PRIEST_TOUCH", default = false, spells = {
			{ 2652, 19261, 19262, 19264, 19265, 19266 }, -- Touch of Weakness
		} },
	},
	DRUID = {
		{ key = "DRUID_MOTW", group = true, spells = {
			{ 1126, 5232, 6756, 5234, 8907, 9884, 9885, family = "wild" }, -- Mark of the Wild
			{ 21849, 21850, family = "wild" },                             -- Gift of the Wild
		} },
		{ key = "DRUID_THORNS", spells = {
			{ 467, 782, 1075, 8914, 9756, 9910 },         -- Thorns
		} },
		{ key = "DRUID_OMEN", spells = {
			{ 16864 },                                    -- Omen of Clarity
		} },
		{ key = "DRUID_BEAR", role = "tank", form = true, spells = {
			{ 9634 },                                     -- Dire Bear Form
			{ 5487 },                                     -- Bear Form
		} },
	},
	PALADIN = {
		{ key = "PALADIN_BLESSING", group = true, spells = {
			{ 19740, 19834, 19835, 19836, 19837, 19838, 25291, family = "might" }, -- Blessing of Might
			{ 19742, 19850, 19852, 19853, 19854, 25290, family = "wisdom" },      -- Blessing of Wisdom
			{ 20217, family = "kings" },                                          -- Blessing of Kings
			{ 25782, 25916, family = "might" },                                   -- Greater Blessing of Might
			{ 25894, 25918, family = "wisdom" },                                  -- Greater Blessing of Wisdom
			{ 25898, family = "kings" },                                          -- Greater Blessing of Kings
			-- Blessing of Light, Salvation and Sanctuary are gone on WoW: Forever.
		} },
		{ key = "PALADIN_AURA", spells = {
			{ 465, 10290, 643, 10291, 1032, 10292, 10293 },      -- Devotion Aura
			{ 7294, 10298, 10299, 10300, 10301 },                -- Retribution Aura
			{ 19746 },                                           -- Concentration Aura
			{ 19876, 19895, 19896 },                             -- Shadow Resistance Aura
			{ 19888, 19897, 19898 },                             -- Frost Resistance Aura
			{ 19891, 19899, 19900 },                             -- Fire Resistance Aura
		} },
		-- A seal lasts 30 seconds and auras can't be read in combat, so
		-- this one only says "Missing", for the moment before a pull.
		-- Off by default.
		{ key = "PALADIN_SEAL", default = false, missingOnly = true, spells = {
			{ 20154, 20287, 20288, 20289, 20290, 20291, 20292, 20293 }, -- Seal of Righteousness
			{ 21082, 20162, 20305, 20306, 20307, 20308 },        -- Seal of the Crusader
			{ 20165, 20347, 20348, 20349 },                      -- Seal of Light
			{ 20166, 20356, 20357 },                             -- Seal of Wisdom
			{ 20164 },                                           -- Seal of Justice
			{ 20375, 20915, 20918, 20919, 20920 },               -- Seal of Command
			{ 1311649, 1311656, 20163, 20419, 20421, 20422, 20423 }, -- Seal of Fury
		} },
		{ key = "PALADIN_RF", role = "tank", spells = {
			{ 25780 },                                           -- Righteous Fury
		} },
	},
	WARLOCK = {
		-- Demon Armor (level 20) is the later line of Demon Skin.
		{ key = "WARLOCK_ARMOR", spells = {
			{ 706, 1086, 11733, 11734, 11735 },    -- Demon Armor
			{ 687, 696 },                          -- Demon Skin
		} },
	},
	HUNTER = {
		{ key = "HUNTER_ASPECT", spells = {
			{ 13165, 14318, 14319, 14320, 14321, 14322, 25296 }, -- Aspect of the Hawk
			{ 13163 },                                           -- Aspect of the Monkey
			{ 5118, travel = true },                             -- Aspect of the Cheetah
			{ 13159, travel = true },                            -- Aspect of the Pack
			{ 20043, 20190 },                                    -- Aspect of the Wild
			{ 13161, 1299445, 1299446, 1299447 },                -- Aspect of the Beast
		} },
		{ key = "HUNTER_TRUESHOT", spells = {
			{ 1299348, 19506, 20905, 20906 },      -- Trueshot Aura (talent)
		} },
	},
	SHAMAN = {
		{ key = "SHAMAN_SHIELD", spells = {
			{ 324, 325, 905, 945, 8134, 10431, 10432 }, -- Lightning Shield
			{ 408510, 408511 },                         -- Water Shield (Restoration talent; either ID)
		} },
		-- Weapon imbues: a weapon enchant per hand, not an aura. The off
		-- hand counts only while it holds a weapon.
		{ key = "SHAMAN_IMBUE", weapon = "main", newest = true, spells = SHAMAN_IMBUES },
		{ key = "SHAMAN_IMBUE_OFF", weapon = "off", newest = true, spells = SHAMAN_IMBUES },
	},
	-- Poisons: a weapon enchant per hand from level 20, once you know a
	-- poison. A right-click picks the poison a hand gets; with a pick, a
	-- click puts it on (see PoisonAction).
	ROGUE = {
		{ key = "ROGUE_POISON", weapon = "main", poison = true, minLevel = 20, spells = ROGUE_POISONS },
		{ key = "ROGUE_POISON_OFF", weapon = "off", poison = true, minLevel = 20, spells = ROGUE_POISONS },
	},
	WARRIOR = {
		{ key = "WARRIOR_SHOUT", group = true, spells = {
			{ 6673, 5242, 6192, 11549, 11550, 11551, 25289 }, -- Battle Shout
		} },
		{ key = "WARRIOR_DEFENSIVE", role = "tank", form = true, spells = {
			{ 71 },                                           -- Defensive Stance
		} },
		{ key = "WARRIOR_SHIELD", role = "tank", shield = true, spells = {} },
	},
}

-- A slot whose spell and rank the player can pick: spells they cast
-- (not poisons, which have their own pick, stances or the shield check).
local function Pickable(slot)
	return not (slot.poison or slot.form or slot.shield) and #slot.spells > 0
end
M.Pickable = Pickable

-- spell ID -> list of { slot key, first spell ID of its line }: casting
-- it makes that line the one Automatic uses (travel aspects excepted).
local CAST_LINES = {}
for _, slots in pairs(CLASS_BUFFS) do
	for _, slot in ipairs(slots) do
		M.defaults.classBuffs[slot.key] = slot.default ~= false
		if Pickable(slot) then
			M.defaults.buffLines[slot.key] = ""
			M.defaults.buffRanks[slot.key] = ""
			for _, ranks in ipairs(slot.spells) do
				if not ranks.travel then
					for _, id in ipairs(ranks) do
						local list = CAST_LINES[id] or {}
						list[#list + 1] = { slot.key, ranks[1] }
						CAST_LINES[id] = list
					end
				end
			end
		end
	end
end
M.CLASS_BUFFS = CLASS_BUFFS

-- Gathering tracking: Find Herbs, Find Minerals.
local TRACKING_SPELLS = { 2383, 2580 }
local WELL_FED_SPELL = 19705 -- any "Well Fed" aura; only its name is used

-- Sound keys of older versions (SOUNDKIT names) as media ids.
local OLD_SOUNDS = { RAID_WARNING = true, READY_CHECK = true, ALARM_CLOCK_WARNING_3 = true, TELL_MESSAGE = true, MAP_PING = true }

-- Pets. Hunters: Call Pet / Revive Pet. Warlocks: the summon spells, with
-- the creature family the game reports for each demon (UnitCreatureFamily).
local CALL_PET, REVIVE_PET = 883, 982
local DEMONS = {
	{ key = "IMP", spell = 688, family = 23 },
	{ key = "VOIDWALKER", spell = 697, family = 16 },
	{ key = "SUCCUBUS", spell = 712, family = 17 },
	{ key = "INCUBUS", spell = 713, family = 302 },
	{ key = "FELHUNTER", spell = 691, family = 15 },
}
for _, demon in ipairs(DEMONS) do M.defaults.demons[demon.key] = true end
M.DEMONS = DEMONS

-- Healthstones of every size (and the talented versions).
local HEALTHSTONES = { 5512, 19004, 19005, 5511, 19006, 19007, 5509, 19008, 19009, 5510, 19010, 19011, 9421, 19012, 19013 }

-- Group buffs another class can give: class -> CLASS_BUFFS slot key.
local GIVERS = { PRIEST = "PRIEST_FORT", MAGE = "MAGE_INT", DRUID = "DRUID_MOTW", PALADIN = "PALADIN_BLESSING" }

-- Resolved through E:ClientIcon where they are shown.
local DURABILITY_ICON = "Interface\\Icons\\Trade_BlackSmithing"
local HEALTHSTONE_ICON = "Interface\\Icons\\INV_Stone_04"

---------------------------------------------------------------------------
-- Spell helpers
---------------------------------------------------------------------------
local function SpellName(id)
	local getInfo = C_Spell and C_Spell.GetSpellInfo
	local info = getInfo and getInfo(id)
	if IsSecret(info) or type(info) ~= "table" then return nil end
	if IsSecret(info.name) then return nil end
	return info.name, info.iconID
end

local function Known(id)
	if not (id and C_SpellBook) then return false end
	for _, check in ipairs({ C_SpellBook.IsSpellKnown, C_SpellBook.IsSpellInSpellBook }) do
		local ok, known = pcall(check, id)
		if ok and not IsSecret(known) and known then return true end
	end
	return false
end

-- The spell the game finds by a name: the highest rank of it the player
-- knows, or nil.
local function KnownByName(name)
	local getInfo = C_Spell and C_Spell.GetSpellInfo
	if not (name and getInfo) then return nil end
	local ok, info = pcall(getInfo, name)
	if not ok or IsSecret(info) or type(info) ~= "table" then return nil end
	local id = info.spellID
	if IsSecret(id) or type(id) ~= "number" then return nil end
	return id
end

-- Highest known rank of one spell line: its index and spell ID, or nil.
-- Every rank is asked; the game's lookup by name wins when it names a
-- higher rank of the line.
local function HighestKnown(ranks)
	local found
	for index = #ranks, 1, -1 do
		if Known(ranks[index]) then
			found = index
			break
		end
	end
	local byName = KnownByName(SpellName(ranks[1]))
	local index = byName and tIndexOf(ranks, byName)
	if index and (not found or index > found) then found = index end
	if found then return found, ranks[found] end
end

---------------------------------------------------------------------------
-- Aura scanning. Returns byName, bySpell maps, or nil when the data is
-- secret (then the caller shows nothing). On WoW: Forever addon code may
-- not read auras in combat at all (C_UnitAuras.GetAuraDataByIndex throws),
-- so nothing is read while InCombatLockdown() is true.
---------------------------------------------------------------------------
local function ScanAuras(unit)
	if InCombatLockdown() then return nil end
	if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return nil end
	local byName, bySpell = {}, {}
	for index = 1, 80 do
		local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, unit, index, "HELPFUL")
		if not ok then return nil end
		if IsSecret(aura) then return nil end
		if not aura then break end
		local name, spellId = aura.name, aura.spellId
		if IsSecret(name) or IsSecret(spellId) or IsSecret(aura.expirationTime) then return nil end
		if name then byName[name] = aura end
		if spellId then bySpell[spellId] = aura end
	end
	return byName, bySpell
end

local function TimeLeft(aura)
	local expires = aura.expirationTime
	if IsSecret(expires) or not expires or expires == 0 then return nil end
	return expires - GetTime()
end

---------------------------------------------------------------------------
-- Visibility rules
---------------------------------------------------------------------------
local function SafeBool(fn, ...)
	if not fn then return false end
	local ok, value = pcall(fn, ...)
	if not ok or IsSecret(value) then return nil end
	return value and true or false
end

-- A plain answer of fn, or nil when it fails or is secret.
local function SafeValue(fn, ...)
	if not fn then return nil end
	local ok, value = pcall(fn, ...)
	if not ok or IsSecret(value) then return nil end
	return value
end

function M:ShouldShow()
	if self.preview then return true end
	if SafeBool(UnitIsDeadOrGhost, "player") ~= false then return false end
	if SafeBool(UnitOnTaxi, "player") ~= false then return false end
	if InCombatLockdown() and not self.db.inCombat then return false end
	return true
end

-- "Show when" per content type: open world, dungeons (and scenarios),
-- raids, battlegrounds and arenas, rest areas (inns and cities).
function M:ContentAllowed()
	local db = self.db
	local inside, kind = IsInInstance()
	if IsSecret(inside) or IsSecret(kind) then return true end
	if not inside or kind == "none" or kind == nil then
		if IsResting() then return db.showResting and true or false end
		return db.showWorld and true or false
	end
	if kind == "raid" then return db.showRaid and true or false end
	if kind == "pvp" or kind == "arena" then return db.showPvP and true or false end
	return db.showDungeon and true or false
end

local function InDungeonOrRaid()
	local inside, kind = IsInInstance()
	if IsSecret(inside) or IsSecret(kind) then return false end
	return inside and (kind == "party" or kind == "raid" or kind == "scenario") or false
end

---------------------------------------------------------------------------
-- Group buff count: members who miss the buff. Only when every value we
-- read is plain; otherwise nil (show no number). Range is not part of it:
-- UnitInRange is always secret on Forever.
---------------------------------------------------------------------------
local function GroupUnits()
	local units = {}
	if IsInRaid() then
		for index = 1, GetNumGroupMembers() do
			local unit = "raid" .. index
			if not UnitIsUnit(unit, "player") then table.insert(units, unit) end
		end
	elseif IsInGroup() then
		for index = 1, GetNumSubgroupMembers() do table.insert(units, "party" .. index) end
	end
	return units
end

-- Class tokens of the other group members (non-secret only).
local function GroupClasses()
	local classes = {}
	for _, unit in ipairs(GroupUnits()) do
		if UnitExists(unit) then
			local localized, class = UnitClass(unit)
			if not IsSecret(class) and class then classes[class] = (not IsSecret(localized) and type(localized) == "string") and localized or class end
		end
	end
	return classes
end

-- Connected, living members without any of `names`, and the first such member (the
-- unit a click-to-buff button casts on).
local function CountGroupMissing(names)
	local units = GroupUnits()
	if #units == 0 then return nil end
	local missing, first = 0, nil
	for _, unit in ipairs(units) do
		if UnitExists(unit) then
			local connected = SafeBool(UnitIsConnected, unit)
			local dead = SafeBool(UnitIsDeadOrGhost, unit)
			if connected == nil or dead == nil then return nil end
			if connected and not dead then
				local byName = ScanAuras(unit)
				if not byName then return nil end
				local has = false
				for name in pairs(names) do
					if byName[name] then has = true break end
				end
				if not has then
					missing = missing + 1
					first = first or unit
				end
			end
		end
	end
	return missing, first
end

---------------------------------------------------------------------------
-- Building the reminder list
---------------------------------------------------------------------------
-- Each entry: { key, icon, label, reason, color, count, time, spellID or itemID }
local RED, YELLOW, GREEN = { 1, 0.27, 0.27 }, { 1, 0.8, 0 }, { 0.27, 0.87, 0.27 }

-- A slot's spell lines by the first spell ID of each ("" or nil: none).
local function LineByKey(slot, key)
	if key == nil or key == "" then return nil end
	key = tostring(key)
	for _, ranks in ipairs(slot.spells) do
		if tostring(ranks[1]) == key then return ranks end
	end
end

local function Family(ranks)
	return ranks.family or ranks[1]
end

-- The ranks of a line the player knows, lowest first: { index, spell ID }.
-- Ranks below the highest one count when the game says it knows them.
local function KnownRanks(ranks)
	local list = {}
	local top = HighestKnown(ranks)
	if not top then return list end
	for index = 1, top do
		if index == top or Known(ranks[index]) then list[#list + 1] = { index, ranks[index] } end
	end
	return list
end
M.KnownRanks = KnownRanks

-- The lines of a slot the player knows, in the slot's order.
local function KnownLines(slot)
	local list = {}
	for _, ranks in ipairs(slot.spells) do
		if HighestKnown(ranks) then list[#list + 1] = ranks end
	end
	return list
end
M.KnownLines = KnownLines

-- The line a slot asks for: the picked one; for Automatic the one cast
-- last, else the first (or, with `newest`, the last) known line that is
-- not for travel. Second result: true when the player picked it.
local function SlotLine(slot, known)
	local db = M.db or {}
	if Pickable(slot) then
		local picked = LineByKey(slot, (db.buffLines or {})[slot.key])
		if picked and HighestKnown(picked) then return picked, true end
		local last = LineByKey(slot, (db.lastLines or {})[slot.key])
		if last and HighestKnown(last) then return last, false end
	end
	local first, newest
	for _, ranks in ipairs(known) do
		if not ranks.travel then
			first = first or ranks
			newest = ranks
		end
	end
	if slot.newest then return newest or known[#known], false end
	return first or known[1], false
end

-- The rank of `line` a click casts: the picked rank while it is known,
-- else the highest known. Returns the spell ID and the rank's index.
local function SlotRank(slot, line)
	local index, best = HighestKnown(line)
	local db = M.db or {}
	local pinned = Pickable(slot) and tonumber((db.buffRanks or {})[slot.key])
	-- A kept rank belongs to a picked spell: with the Spell row back on
	-- Automatic (and two spells known) the highest rank counts again.
	if pinned and ((db.buffLines or {})[slot.key] or "") == "" and #KnownLines(slot) > 1 then pinned = nil end
	local pinIndex = pinned and tIndexOf(line, pinned)
	if pinIndex and pinIndex < index and Known(pinned) then return pinned, pinIndex end
	return best, index
end

-- What a slot asks for. Returns nil when the player knows none of its
-- spells, else:
--   names   [spellName] = ranks, every line of the slot the game names
--   best    the spell ID a click casts (picked spell and rank)
--   counts  [spellName] = ranks, the names that meet the slot: every line,
--           or with a picked spell only its family (a buff and its group
--           version)
--   line    the line `best` belongs to; rankIndex its rank
local function SlotInfo(slot)
	local names = {}
	for _, ranks in ipairs(slot.spells) do
		local name = SpellName(ranks[1])
		if name then names[name] = ranks end
	end
	local known = KnownLines(slot)
	if #known == 0 then return nil end
	local line, picked = SlotLine(slot, known)
	local best, rankIndex = SlotRank(slot, line)
	local counts = names
	if picked then
		counts = {}
		local family = Family(line)
		for name, ranks in pairs(names) do
			if Family(ranks) == family then counts[name] = ranks end
		end
	end
	return names, best, counts, line, rankIndex
end
M.SlotInfo = SlotInfo

-- Is there anything to pick: two spells known, or two ranks of one?
local function HasChoice(slot)
	if not Pickable(slot) then return false end
	local known = KnownLines(slot)
	return #known > 1 or (known[1] ~= nil and #KnownRanks(known[1]) > 1)
end
M.HasChoice = HasChoice

-- A spell the player cast: the line it belongs to becomes the one
-- Automatic uses for its slots. True when it is one of them.
function M:NoteCast(spellID)
	if IsSecret(spellID) or type(spellID) ~= "number" then return false end
	local list = CAST_LINES[spellID]
	if not list then return false end
	self.db.lastLines = self.db.lastLines or {}
	for _, pair in ipairs(list) do self.db.lastLines[pair[1]] = pair[2] end
	return true
end

-- A slot that fits your role and level (a role-only slot follows the role
-- picked in setup or on the General page).
local function SlotFits(slot)
	if slot.role and not (E.GetRole and E:GetRole() == slot.role) then return false end
	if slot.minLevel then
		local level = UnitLevel("player")
		if IsSecret(level) or type(level) ~= "number" or level < slot.minLevel then return false end
	end
	return true
end
M.SlotFits = SlotFits

function M:BuffEntries(entries, byName, bySpell, inCombat)
	local _, class = UnitClass("player")
	for _, slot in ipairs(CLASS_BUFFS[class] or {}) do
		-- Off, or not for your role or level: skipped.
		local wanted = self.db.classBuffs[slot.key] ~= false and SlotFits(slot)
		if wanted and slot.weapon then
			self:ImbueEntry(entries, slot)
		elseif wanted and slot.form then
			self:FormEntry(entries, slot)
		elseif wanted and slot.shield then
			self:ShieldEntry(entries, slot)
		elseif wanted then
			local names, best, counts, _, bestIndex = SlotInfo(slot)
			if names then
				local name, icon = SpellName(best)
				local active
				for spellName in pairs(counts) do
					if byName[spellName] then active = byName[spellName] break end
				end
				local entry
				if not active then
					entry = { reason = L["Missing"], color = RED }
				else
					local left = TimeLeft(active)
					if left and left < self.db.threshold and not slot.missingOnly then
						entry = { reason = L["Running out"], color = YELLOW, time = left }
					elseif self.db.rank and not inCombat and not IsSecret(active.spellId) then
						-- Is the active rank lower than one you know (or the
						-- rank you picked)?
						for _, ranks in pairs(counts) do
							local activeIndex = tIndexOf(ranks, active.spellId)
							if activeIndex then
								local knownIndex, knownID = HighestKnown(ranks)
								if knownIndex and tIndexOf(ranks, best) then knownIndex, knownID = bestIndex, best end
								if knownIndex and knownIndex > activeIndex then
									entry = { reason = L["Higher rank known (%d > %d)"]:format(knownIndex, activeIndex), color = GREEN, badge = "UP" }
									best = knownID
									name, icon = SpellName(knownID)
								end
								break
							end
						end
					end
				end
				local groupOnly = false
				if slot.group and self.db.group and not inCombat then
					local missing, firstUnit = CountGroupMissing(counts)
					if missing and missing > 0 then
						if not entry then
							entry = { reason = L["Group members without it"], color = YELLOW }
							groupOnly = true
						end
						entry.count = missing
						entry.groupUnit = firstUnit
					end
				end
				if entry then
					entry.key = slot.key
					entry.spellID = best
					entry.icon = icon
					entry.label = name
					if HasChoice(slot) then entry.pick = "buff:" .. slot.key end
					-- A blessing plan from the group: which blessing is yours.
					if slot.key == "PALADIN_BLESSING" and E.BlessingPlan and E.BlessingPlan.ReminderNote then
						entry.note = E.BlessingPlan:ReminderNote()
					end
					-- Click-to-buff: on you, or on the first member without it.
					entry.action = { type = "spell", spell = best, unit = groupOnly and entry.groupUnit or "player" }
					table.insert(entries, entry)
				end
			end
		end
	end
end

-- The group buffs you can give, for the missing-buff mark of the
-- group frames: { { names = { [spellName] = true }, icon = texture }, ... }.
-- One rule per group slot of your class that you know and haven't turned
-- off under Class buffs; any of its names (single or group version, any
-- rank; with a picked spell, that spell's names) meets it. Empty when you
-- can give none.
function E:GetGroupBuffRules()
	local rules = {}
	local _, class = UnitClass("player")
	if IsSecret(class) then return rules end
	local wanted = M.db and M.db.classBuffs or {}
	for _, slot in ipairs(CLASS_BUFFS[class] or {}) do
		if slot.group and wanted[slot.key] ~= false then
			local names, best, counts = SlotInfo(slot)
			if names then
				local set = {}
				for name in pairs(counts) do set[name] = true end
				local _, icon = SpellName(best)
				rules[#rules + 1] = { names = set, icon = icon }
			end
		end
	end
	return rules
end

-- Gathering tracking through C_Minimap; falls back to the aura list.
local function TrackingState()
	local knownAny, activeAny, icon, spell = nil, nil, nil, nil
	for _, id in ipairs(TRACKING_SPELLS) do
		if Known(id) then
			knownAny = true
			spell = spell or id
		end
	end
	if not knownAny then return nil end
	if C_Minimap and C_Minimap.GetNumTrackingTypes and C_Minimap.GetTrackingInfo then
		local wanted = {}
		for _, id in ipairs(TRACKING_SPELLS) do
			local name = SpellName(id)
			if name then wanted[name] = true end
			wanted[id] = true
		end
		for index = 1, C_Minimap.GetNumTrackingTypes() or 0 do
			local a, b, c, _, _, f = C_Minimap.GetTrackingInfo(index)
			local name, texture, active, spellID
			if type(a) == "table" then
				name, texture, active, spellID = a.name, a.texture, a.active, a.spellID
			else
				name, texture, active, spellID = a, b, c, f
			end
			if IsSecret(active) or IsSecret(name) then return nil end
			if (name and wanted[name]) or (spellID and wanted[spellID]) then
				icon = icon or texture
				if active then activeAny = true end
			end
		end
		return knownAny, activeAny, icon, spell
	end
	return knownAny, nil, icon, spell
end

function M:TrackingEntry(entries, byName)
	local known, active, icon, spell = TrackingState()
	if not known then return end
	if active == nil then
		-- No tracking API: look for the tracking aura on the player.
		for _, id in ipairs(TRACKING_SPELLS) do
			local name = SpellName(id)
			if name and byName[name] then active = true end
		end
	end
	if active then return end
	local name, spellIcon = SpellName(spell)
	table.insert(entries, { key = "TRACKING", spellID = spell, icon = icon or spellIcon, label = name,
		reason = L["No gathering tracking"], color = RED, action = { type = "spell", spell = spell } })
end

---------------------------------------------------------------------------
-- Pets: no pet out, pet on passive, a demon you did not allow.
-- Read out of combat only, like everything here.
---------------------------------------------------------------------------
local function PetOnPassive()
	if not GetPetActionInfo then return false end
	for index = 1, _G.NUM_PET_ACTION_SLOTS or 10 do
		local name, _, isToken, isActive = GetPetActionInfo(index)
		if IsSecret(name) or IsSecret(isActive) then return false end
		if isToken and name == "PET_MODE_PASSIVE" then return isActive and true or false end
	end
	return false
end

function M:PetEntries(entries)
	local db = self.db
	if not (db.pets or db.petPassive) then return end
	if SafeBool(IsMounted) then return end
	local _, class = UnitClass("player")
	local hasPet = SafeBool(UnitExists, "pet")
	if hasPet == nil then return end
	if class == "HUNTER" then
		if not Known(CALL_PET) then return end
		if not hasPet and db.pets then
			local name, icon = SpellName(CALL_PET)
			table.insert(entries, { key = "PET", spellID = CALL_PET, icon = icon, label = name, reason = L["No pet out"], color = RED,
				hint = Known(REVIVE_PET) and SpellName(REVIVE_PET) and { L["Right-click"], (SpellName(REVIVE_PET)) } or nil,
				action = { type = "spell", spell = CALL_PET, spell2 = Known(REVIVE_PET) and REVIVE_PET or nil } })
		end
	elseif class == "WARLOCK" then
		local allowed, first = {}, nil
		for _, demon in ipairs(DEMONS) do
			if Known(demon.spell) and db.demons[demon.key] ~= false then
				allowed[demon.family] = true
				first = first or demon
			end
		end
		if not first then return end
		if not hasPet and db.pets then
			local name, icon = SpellName(first.spell)
			table.insert(entries, { key = "PET", spellID = first.spell, icon = icon, label = name, reason = L["No demon out"], color = RED,
				action = { type = "spell", spell = first.spell } })
		elseif hasPet and db.pets then
			local _, family = UnitCreatureFamily("pet")
			if not IsSecret(family) and family and not allowed[family] then
				local name, icon = SpellName(first.spell)
				table.insert(entries, { key = "PET-WRONG", spellID = first.spell, icon = icon, label = name,
					reason = L["A demon you did not allow is out"], color = YELLOW, action = { type = "spell", spell = first.spell } })
			end
		end
	else
		return
	end
	if hasPet and db.petPassive and PetOnPassive() then
		table.insert(entries, { key = "PET-PASSIVE", icon = E:ClientIcon("Interface\\Icons\\Ability_Seal"), label = E:GameText(_G.PET_MODE_PASSIVE, L["Passive"]),
			reason = L["Your pet is set to passive"], color = YELLOW })
	end
end

---------------------------------------------------------------------------
-- Custom spells: any rank of the spell's family counts (matched by name).
---------------------------------------------------------------------------
function M:CustomEntries(entries, byName)
	local ids = {}
	for id, on in pairs(self.db.customSpells) do
		if on and tonumber(id) then ids[#ids + 1] = tonumber(id) end
	end
	table.sort(ids)
	for _, id in ipairs(ids) do
		local name, icon = SpellName(id)
		if name and not byName[name] then
			table.insert(entries, { key = "CUSTOM-" .. id, spellID = id, icon = icon, label = name, reason = L["Missing"], color = RED,
				-- By name: the game casts the highest rank you know.
				action = Known(id) and { type = "spell", spell = name, unit = "player" } or nil })
		end
	end
end

---------------------------------------------------------------------------
-- "I am missing a buff someone in my group can give" (informational).
---------------------------------------------------------------------------
local function SlotByKey(key)
	for _, slots in pairs(CLASS_BUFFS) do
		for _, slot in ipairs(slots) do
			if slot.key == key then return slot end
		end
	end
end
M.SlotByKey = SlotByKey

function M:AskEntries(entries, byName)
	local _, myClass = UnitClass("player")
	local classes = GroupClasses()
	for class, slotKey in pairs(GIVERS) do
		if classes[class] and class ~= myClass then
			local slot = SlotByKey(slotKey)
			local has, icon, label, spellID = false, nil, nil, nil
			for _, ranks in ipairs(slot and slot.spells or {}) do
				local name, spellIcon = SpellName(ranks[1])
				if name and byName[name] then has = true break end
				if name and not label then label, icon, spellID = name, spellIcon, ranks[1] end
			end
			if not has and label then
				local className = type(classes[class]) == "string" and classes[class] or class
				table.insert(entries, { key = "ASK-" .. class, spellID = spellID, icon = icon, label = label,
					reason = L["Missing: a %s in your group can give it"]:format(className), color = YELLOW })
			end
		end
	end
end

---------------------------------------------------------------------------
-- XP bonuses: auras that raise the XP you gain (spell IDs from the client's
-- spell table, build 1.60.1.70862). The bonus is the aura's own value; the
-- percent here stands in only when the aura carries none.
---------------------------------------------------------------------------
local XP_BONUSES = {
	{ spell = 1243969, percent = 5 },    -- Well Fed XP Boost (XP food)
	{ spell = 335924, percent = 50 },    -- Winds of Wisdom (event)
	{ spell = 436412, percent = 50 },    -- Discoverer's Delight
	{ spell = 1328127, percent = 200 },  -- Elixir of Endless Experience
}
M.XP_BONUSES = XP_BONUSES

-- The XP bonuses on you, { { spell, name, percent, left, icon } }, read
-- out of combat only: in combat the answer is nil.
function E.XPBonuses()
	if InCombatLockdown() then return nil end
	local get = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
	local list = {}
	if not get then return list end
	for _, bonus in ipairs(XP_BONUSES) do
		local aura = E.PlainCall(get, bonus.spell)
		if type(aura) == "table" then
			local name, expires = E.Plain(aura.name), E.Plain(aura.expirationTime)
			local points = type(aura.points) == "table" and E.Plain(aura.points[1]) or nil
			list[#list + 1] = {
				spell = bonus.spell,
				name = type(name) == "string" and name ~= "" and name or SpellName(bonus.spell),
				percent = type(points) == "number" and points > 0 and points or bonus.percent,
				left = type(expires) == "number" and expires > 0 and math.max(0, expires - GetTime()) or nil,
				icon = E.Plain(aura.icon),
			}
		end
	end
	return list
end

-- XP food: while leveling, out of combat, a note when no XP bonus runs.
function M:XPFoodEntry(entries)
	if E:AtMaxLevel() then return end
	local bonuses = E.XPBonuses()
	if not bonuses or #bonuses > 0 then return end
	local name, icon = SpellName(XP_BONUSES[1].spell)
	table.insert(entries, { key = "XPFOOD", icon = E:ClientIcon(icon, "Interface\\Icons\\INV_Misc_Food_15"), label = name or L["XP food"],
		reason = L["No XP bonus running"], color = YELLOW })
end

---------------------------------------------------------------------------
-- Healthstone: in dungeons and raids, with a warlock in the group (or you)
-- who can make one, and none in your bags. You count once you know a
-- Create Healthstone rank; another warlock once they reach the level the
-- trainer teaches the first rank at.
---------------------------------------------------------------------------
local CREATE_HEALTHSTONE = { 6201, 6202, 5699, 11729, 11730 }
local CREATE_HEALTHSTONE_LEVEL = 10

local function HealthstoneMaker()
	local _, myClass = UnitClass("player")
	if myClass == "WARLOCK" then
		for _, id in ipairs(CREATE_HEALTHSTONE) do
			if Known(id) then return true end
		end
	end
	for _, unit in ipairs(GroupUnits()) do
		if UnitExists(unit) then
			local _, class = UnitClass(unit)
			local level = UnitLevel(unit)
			if not IsSecret(class) and class == "WARLOCK" and not IsSecret(level)
				and type(level) == "number" and level >= CREATE_HEALTHSTONE_LEVEL then return true end
		end
	end
	return false
end
M.HealthstoneMaker = HealthstoneMaker

function M:HealthstoneEntry(entries)
	if not InDungeonOrRaid() then return end
	if not HealthstoneMaker() then return end
	-- A warlock who can make one gets the make-a-stone reminder instead.
	if self.db.stones and self:StoneSpell("healthstone") then return end
	for _, id in ipairs(HEALTHSTONES) do
		if (C_Item.GetItemCount(id) or 0) > 0 then return end
	end
	local name = C_Item.GetItemNameByID and C_Item.GetItemNameByID(HEALTHSTONES[7])
	table.insert(entries, { key = "HEALTHSTONE", itemID = HEALTHSTONES[7], icon = E:ClientIcon(HEALTHSTONE_ICON), label = name or L["Healthstone"],
		reason = L["No Healthstone in your bags (a warlock can make one)"], color = YELLOW })
end

---------------------------------------------------------------------------
-- Warlock stones. Out of combat, a reminder for each stone whose Create
-- spell you know and of which you carry none (Healthstone, Soulstone, and
-- the Spellstone or Firestone you picked); a click casts the highest rank
-- you know, which takes a Soul Shard. In a dungeon or raid, with a
-- Soulstone in your bags and its cooldown ready, a reminder while nobody
-- in the group has Soulstone Resurrection names the healer the click
-- uses it on (the group's healer role, else the first member of a healing
-- class). Group auras are read out of combat only; nothing is used or
-- cast without the player's click. Item IDs are from the game's item
-- table (build 1.60.1.70938); Create Healthstone has no item in it (the
-- server picks the stone), so its stones are the three of each size.
---------------------------------------------------------------------------
local SOUL_SHARD = 6265
local STONES = {
	healthstone = { key = "WARLOCK_HEALTHSTONE", spells = CREATE_HEALTHSTONE, items = HEALTHSTONES },
	soulstone = { key = "WARLOCK_SOULSTONE", spells = { 693, 20752, 20755, 20756, 20757 }, items = { 5232, 16892, 16893, 16895, 16896 } },
	firestone = { key = "WARLOCK_FIRESTONE", spells = { 6366, 17951, 17952, 17953 }, items = { 1254, 13699, 13700, 13701 }, pick = true },
	spellstone = { key = "WARLOCK_SPELLSTONE", spells = { 2362, 17727, 17728 }, items = { 5522, 13602, 13603 }, pick = true },
}
M.STONES = STONES
local SOULSTONE_BUFF = 20707 -- Soulstone Resurrection; every rank shares the name
local HEALING_CLASSES = { PRIEST = true, DRUID = true, SHAMAN = true, PALADIN = true }

local function Carried(id)
	local count = C_Item.GetItemCount and C_Item.GetItemCount(id) or 0
	if IsSecret(count) or type(count) ~= "number" then return 0 end
	return count
end

-- The highest rank of a stone you know to make, or nil.
function M:StoneSpell(kind)
	local _, class = UnitClass("player")
	if IsSecret(class) or class ~= "WARLOCK" then return nil end
	local _, id = HighestKnown(STONES[kind].spells)
	return id
end

-- The stone of that kind in your bags (the highest first), or nil.
local function StoneInBags(kind)
	local items = STONES[kind].items
	for index = #items, 1, -1 do
		if Carried(items[index]) > 0 then return items[index] end
	end
end

function M:StoneEntries(entries)
	if not self.db.stones then return end
	local kinds = { "healthstone", "soulstone" }
	if STONES[self.db.stonePick] and STONES[self.db.stonePick].pick then kinds[3] = self.db.stonePick end
	for _, kind in ipairs(kinds) do
		local spell = self:StoneSpell(kind)
		if spell and not StoneInBags(kind) then
			local name, icon = SpellName(spell)
			local shards = Carried(SOUL_SHARD)
			local entry = { key = STONES[kind].key, spellID = spell, icon = icon, label = name, color = YELLOW,
				reason = L["None in your bags"], pick = STONES[kind].pick and "stone" or nil }
			if shards > 0 then
				entry.note = L["Soul Shards: %d"]:format(shards)
				entry.action = { type = "spell", spell = spell, unit = "player" }
			else
				entry.dim = true
				entry.note = L["Needs a Soul Shard."]
			end
			table.insert(entries, entry)
		end
	end
end

-- Does a unit have a Soulstone on it? nil when the game does not say.
local function HasSoulstone(unit, name)
	local byName = ScanAuras(unit)
	if not byName then return nil end
	return byName[name] ~= nil
end

-- The healer the Soulstone goes on: the healer role first, then the first
-- member of a healing class; alive and connected.
local function SoulstoneTarget(units)
	local fallback
	for _, unit in ipairs(units) do
		if UnitExists(unit) and SafeBool(UnitIsConnected, unit) and SafeBool(UnitIsDeadOrGhost, unit) == false then
			local role = SafeValue(UnitGroupRolesAssigned, unit)
			if role == "HEALER" then return unit end
			local _, class = UnitClass(unit)
			if not fallback and not IsSecret(class) and HEALING_CLASSES[class] then fallback = unit end
		end
	end
	return fallback
end

function M:SoulstoneEntry(entries)
	local db = self.db
	if not (db.soulstoneGroup or db.soulstoneSolo) or not self:StoneSpell("soulstone") then return end
	local id = StoneInBags("soulstone")
	if not id then return end
	if C_Container and C_Container.GetItemCooldown then
		local ok, start, duration = pcall(C_Container.GetItemCooldown, id)
		if not ok or IsSecret(start) or IsSecret(duration) then return end
		if type(start) == "number" and start > 0 and type(duration) == "number" and duration > 1.5 then return end
	end
	local name = SpellName(SOULSTONE_BUFF)
	if not name then return end
	local units = GroupUnits()
	local unit
	if #units > 0 then
		if not (db.soulstoneGroup and InDungeonOrRaid()) then return end
		table.insert(units, 1, "player")
		for _, member in ipairs(units) do
			local has = UnitExists(member) and HasSoulstone(member, name)
			if has == nil and UnitExists(member) then return end
			if has then return end
		end
		table.remove(units, 1)
		unit = SoulstoneTarget(units)
		if not unit then return end
	else
		if not db.soulstoneSolo or HasSoulstone("player", name) ~= false then return end
		unit = "player"
	end
	local who = UnitName(unit)
	if IsSecret(who) then who = nil end
	table.insert(entries, { key = "WARLOCK_SOULSTONE_USE", itemID = id, icon = C_Item.GetItemIconByID and C_Item.GetItemIconByID(id) or nil, label = who or L["Soulstone"],
		reason = unit == "player" and L["No Soulstone on you"] or L["Nobody in your group has a Soulstone"], color = YELLOW,
		note = unit ~= "player" and who and L["A click puts it on %s."]:format(who) or nil,
		action = { type = "item", item = "item:" .. id, unit = unit } })
end

-- Right-click on the Spellstone or Firestone reminder: which one you keep
-- up, or neither. Out of combat only, like every pick.
function M:OpenStoneMenu(owner)
	if InCombatLockdown() or not (owner and E.UIKit and E.UIKit.ContextMenu) then return end
	local db = self.db
	local function Pick(kind)
		db.stonePick = kind
		M.dirty = true
		M:Refresh()
	end
	E.UIKit.ContextMenu(owner, function(_, root)
		root:CreateTitle(L["Spellstone or Firestone"])
		root:CreateRadio(L["Neither"], function() return not STONES[db.stonePick] end, function() Pick("") end)
		for _, kind in ipairs({ "spellstone", "firestone" }) do
			local spell = self:StoneSpell(kind)
			if spell then
				root:CreateRadio(SpellName(spell) or kind, function() return db.stonePick == kind end, function() Pick(kind) end)
			end
		end
	end)
end

---------------------------------------------------------------------------
-- Durability: the most worn item, once it reaches the shared
-- thresholds on the General page (E:DurabilityLevel): yellow when worn,
-- red when low.
---------------------------------------------------------------------------
local function LowestDurability()
	local lowest
	for slot = 1, 18 do
		local current, maximum = GetInventoryItemDurability(slot)
		if not IsSecret(current) and not IsSecret(maximum) and current and maximum and maximum > 0 then
			local percent = current / maximum * 100
			if not lowest or percent < lowest then lowest = percent end
		end
	end
	return lowest
end

function M:DurabilityEntry(entries)
	local lowest = LowestDurability()
	local level = E:DurabilityLevel(lowest)
	if not level or level == "ok" then return end
	table.insert(entries, { key = "DURABILITY", icon = E:ClientIcon(DURABILITY_ICON), label = E:GameText(_G.DURABILITY, L["Durability"]),
		text = ("%d%%"):format(lowest), reason = L["Your gear is at %d%% durability: time to repair"]:format(lowest),
		color = level == "low" and RED or YELLOW })
end

---------------------------------------------------------------------------
-- Consumables
---------------------------------------------------------------------------
local function ItemName(id)
	if C_Item.GetItemNameByID then
		local name = C_Item.GetItemNameByID(id)
		if name then return name end
	end
	return C_Item.GetItemInfo and C_Item.GetItemInfo(id)
end

local function ItemIcon(id)
	if C_Item.GetItemIconByID then return C_Item.GetItemIconByID(id) end
	local _, _, _, _, icon = C_Item.GetItemInfoInstant(id)
	return icon
end

-- The buff a consumable gives: its use spell. Cached in the settings once
-- the item data has loaded.
local function ItemSpell(id, data)
	if not data.spellID then
		local spellName, spellID = C_Item.GetItemSpell(id)
		if spellID then
			data.spellID, data.spell = spellID, spellName
		elseif C_Item.RequestLoadItemDataByID then
			C_Item.RequestLoadItemDataByID(id)
		end
	end
	local name = data.spellID and SpellName(data.spellID) or data.spell
	return data.spellID, name
end

-- Has the hand a temporary weapon enchant, and seconds left (nil when
-- the game doesn't say). The game answers per slot with a list of
-- enchants; if that call fails, the older call with one list of values
-- for both hands is tried.
local function WeaponEnchant(hand)
	local slot = hand == "off" and (INVSLOT_OFFHAND or 17) or (INVSLOT_MAINHAND or 16)
	if C_Item and C_Item.GetWeaponEnchantInfo then
		local weaponSlot = Enum.WeaponSlot and (hand == "off" and Enum.WeaponSlot.OffHand or Enum.WeaponSlot.MainHand)
		slot = weaponSlot or slot
		local ok, list = pcall(C_Item.GetWeaponEnchantInfo, slot)
		if ok and type(list) == "table" then
			local permanent = Enum.ItemEnchantType and Enum.ItemEnchantType.Permanent
			for _, enchant in ipairs(list) do
				local has, kind, left = enchant.hasEnchant, enchant.enchantType, enchant.timeLeft
				if IsSecret(has) or IsSecret(kind) or IsSecret(left) then return nil end
				if has and not (permanent and kind == permanent) then
					return true, type(left) == "number" and left / 1000 or nil
				end
			end
			return false
		end
	end
	if not GetWeaponEnchantInfo then return nil end
	local hasMain, mainExpires, _, _, hasOff, offExpires = GetWeaponEnchantInfo()
	local has, expires = hasMain, mainExpires
	if hand == "off" then has, expires = hasOff, offExpires end
	if IsSecret(has) or IsSecret(expires) then return nil end
	return has and true or false, type(expires) == "number" and expires / 1000 or nil
end

local function HasOffHandWeapon()
	local id = GetInventoryItemID("player", INVSLOT_OFFHAND or 17)
	if not id then return false end
	local _, _, _, _, _, classID = C_Item.GetItemInfoInstant(id)
	return classID == (Enum.ItemClass and Enum.ItemClass.Weapon or 2)
end

---------------------------------------------------------------------------
-- Shaman weapon imbues and shield alerts
---------------------------------------------------------------------------
-- A weapon imbue slot (SHAMAN_IMBUE, SHAMAN_IMBUE_OFF): missing or running
-- out on that hand. A click casts the imbue picked for that hand (by
-- default the one cast last) at the rank picked (by default the highest
-- known); a right-click picks them. Any temporary enchant on the hand
-- meets it: the game doesn't tell addons which imbue a weapon holds.
-- A rogue's poison slot (ROGUE_POISON, ROGUE_POISON_OFF) works the same
-- way, named "Poison"; its click puts the picked poison on that hand.
function M:ImbueEntry(entries, slot)
	if slot.weapon == "off" and not HasOffHandWeapon() then return end
	local names, best = SlotInfo(slot)
	if not names then return end
	local has, left = WeaponEnchant(slot.weapon)
	if has == nil then return end
	local entry
	if not has then
		if slot.poison then
			entry = { reason = slot.weapon == "off" and L["No poison on your off hand"] or L["No poison on your main hand"], color = RED }
		else
			entry = { reason = slot.weapon == "off" and L["No off-hand enchant"] or L["No main-hand enchant"], color = RED }
		end
	elseif left and left < self.db.threshold then
		entry = { reason = L["Running out"], color = YELLOW, time = left }
	end
	if not entry then return end
	local name, icon = SpellName(best)
	entry.key, entry.spellID, entry.icon, entry.label = slot.key, best, icon, name
	if slot.poison then
		entry.label = slot.weapon == "off" and L["Off-hand poison"] or L["Main-hand poison"]
		self:PoisonAction(entry, slot.weapon)
	else
		entry.action = { type = "spell", spell = best, unit = "player" }
		if HasChoice(slot) then entry.pick = "buff:" .. slot.key end
	end
	table.insert(entries, entry)
end

---------------------------------------------------------------------------
-- Rogue poison picks. Each hand's reminder keeps the line you picked
-- (right-click, out of combat). With a pick, a click uses the highest rank
-- of that line in your bags and puts it on that hand: one click, one
-- application, by the player. Without one in the bags the icon dims and
-- the tooltip says which poison is missing.
---------------------------------------------------------------------------
local function PoisonLine(key)
	for _, line in ipairs(POISON_LINES) do
		if line.key == key then return line end
	end
end

-- The line a hand puts on, or nil for "just remind me".
function M:PoisonPick(hand)
	local picks = self.db.poisons or {}
	local key = picks[hand]
	if hand == "off" and key == "main" then key = picks.main end
	return PoisonLine(key)
end

-- The highest rank of a line in your bags: item ID and count, or nil.
local function BestPoison(line)
	for index = #line.items, 1, -1 do
		local id = line.items[index]
		local count = C_Item.GetItemCount and C_Item.GetItemCount(id) or 0
		if not IsSecret(count) and type(count) == "number" and count > 0 then return id, count end
	end
end
M.BestPoison = BestPoison

-- Known (any rank of its recipe) or carried: the lines the pick menu offers.
local function PoisonOffered(line)
	return HighestKnown(line.spells) ~= nil or BestPoison(line) ~= nil
end

function M:PoisonAction(entry, hand)
	entry.pick = hand
	local line = self:PoisonPick(hand)
	if not line then return end
	local id, count = BestPoison(line)
	local slot = hand == "off" and (INVSLOT_OFFHAND or 17) or (INVSLOT_MAINHAND or 16)
	if id then
		entry.itemID, entry.icon = id, ItemIcon(id) or entry.icon
		entry.count, entry.poisonCount = count, true
		local name = ItemName(id) or ""
		entry.note = (hand == "off" and L["%s goes on your off hand."] or L["%s goes on your main hand."]):format(name)
		entry.action = { type = "macro", macrotext = ("/use item:%d\n/use %d"):format(id, slot) }
	else
		local name = ItemName(line.items[#line.items]) or SpellName(line.spells[1]) or ""
		entry.dim = true
		entry.note = L["No %s in your bags."]:format(name)
	end
end

-- Right-click on a poison reminder: the lines you know or carry, "none"
-- and, on the off hand, the main hand's pick. Out of combat only.
function M:OpenPoisonMenu(owner, hand)
	if InCombatLockdown() or not (owner and E.UIKit and E.UIKit.ContextMenu) then return end
	local picks = self.db.poisons
	local function Pick(key)
		picks[hand] = key
		M:PickChanged()
	end
	E.UIKit.ContextMenu(owner, function(_, root)
		root:CreateTitle(hand == "off" and L["Off-hand poison"] or L["Main-hand poison"])
		if hand == "off" then
			root:CreateRadio(L["Same as the main hand"], function() return picks.off == "main" end, function() Pick("main") end)
		end
		root:CreateRadio(L["None, just remind me"], function() return (picks[hand] or "") == "" end, function() Pick("") end)
		for _, line in ipairs(POISON_LINES) do
			if PoisonOffered(line) then
				local id, count = BestPoison(line)
				local name = SpellName(line.spells[1]) or ItemName(line.items[1]) or line.key
				local label = id and ("%s (%d)"):format(name, count) or name
				root:CreateRadio(label, function() return picks[hand] == line.key end, function() Pick(line.key) end)
			end
		end
	end)
end

---------------------------------------------------------------------------
-- Class buff picks: the spell and rank a slot asks for (see SlotInfo).
---------------------------------------------------------------------------
-- A pick changed: the reminders and the class bar (which keeps the same
-- picks) follow it.
function M:PickChanged()
	self.dirty = true
	self:Refresh()
	local bar = E.ClassBar
	if bar and bar.active and bar.Refresh then bar:Refresh() end
end

-- Save a pick: line "" is Automatic, rank "" the highest known.
function M:SetBuffPick(key, line, rank)
	self.db.buffLines[key] = line and tostring(line) or ""
	self.db.buffRanks[key] = rank and tostring(rank) or ""
	self:PickChanged()
end

-- The choice for a line's "highest known rank": the line itself, or
-- Automatic when it is the only spell of the slot the player knows.
local function LineChoice(known, ranks)
	return #known > 1 and tostring(ranks[1]) or ""
end

-- Is `ranks` (at `rank`, "" for the highest known) the slot's pick?
local function PickedLine(slot, known, ranks, rank)
	local line, pinned = M.db.buffLines[slot.key] or "", M.db.buffRanks[slot.key] or ""
	if pinned ~= (rank or "") then return false end
	if line == tostring(ranks[1]) then return true end
	return rank == "" and line == "" and #known == 1
end

-- Right-click on a class buff or imbue reminder: Automatic, each spell
-- you know and, for a spell with more than one rank known, its ranks.
-- Out of combat only.
function M:OpenBuffMenu(owner, key)
	if InCombatLockdown() or not (owner and E.UIKit and E.UIKit.ContextMenu) then return end
	local slot = SlotByKey(key)
	if not (slot and HasChoice(slot)) then return end
	local known = KnownLines(slot)
	E.UIKit.ContextMenu(owner, function(_, root)
		if slot.weapon then
			root:CreateTitle(slot.weapon == "off" and L["Off-hand imbue"] or L["Main-hand imbue"])
		else
			root:CreateTitle(L["Spell and rank"])
		end
		if #known > 1 then
			root:CreateRadio(L["Automatic (the one you cast last)"], function() return (M.db.buffLines[key] or "") == "" end,
				function() M:SetBuffPick(key, "", "") end)
		end
		for _, ranks in ipairs(known) do
			local name = SpellName(ranks[1]) or tostring(ranks[1])
			local list = KnownRanks(ranks)
			local choice = LineChoice(known, ranks)
			if #list > 1 then
				local sub = root:CreateButton(name)
				sub:CreateRadio(L["Highest known rank"], function() return PickedLine(slot, known, ranks, "") end,
					function() M:SetBuffPick(key, choice, "") end)
				for index = #list - 1, 1, -1 do
					local rank, id = list[index][1], list[index][2]
					sub:CreateRadio(L["Rank %d"]:format(rank), function() return PickedLine(slot, known, ranks, tostring(id)) end,
						function() M:SetBuffPick(key, ranks[1], id) end)
				end
			else
				root:CreateRadio(name, function() return PickedLine(slot, known, ranks, "") end,
					function() M:SetBuffPick(key, choice, "") end)
			end
		end
	end)
end

-- A right-click pick: a poison hand ("main", "off"), the warlock stone or
-- a class buff ("buff:<slot key>").
function M:OpenPick(owner, pick)
	if pick == "stone" then return self:OpenStoneMenu(owner) end
	local key = type(pick) == "string" and pick:match("^buff:(.+)$")
	if key then return self:OpenBuffMenu(owner, key) end
	return self:OpenPoisonMenu(owner, pick)
end

-- The stance or form you are in, as its spell ID; false in none, nil
-- when the game does not say.
local function ActiveFormSpell()
	if not (GetShapeshiftForm and GetShapeshiftFormInfo) then return nil end
	local ok, index = pcall(GetShapeshiftForm)
	if not ok or IsSecret(index) or type(index) ~= "number" then return nil end
	if index == 0 then return false end
	local read, _, active, _, spellID = pcall(GetShapeshiftFormInfo, index)
	if not read or IsSecret(active) or IsSecret(spellID) or type(spellID) ~= "number" then return nil end
	return spellID
end

-- A form slot (WARRIOR_DEFENSIVE, DRUID_BEAR), for tanks: a reminder when
-- you know the stance or form and are not in it. A click takes it.
function M:FormEntry(entries, slot)
	local names, best = SlotInfo(slot)
	if not names then return end
	local active = ActiveFormSpell()
	if active == nil then return end
	for _, ranks in pairs(names) do
		if active and tIndexOf(ranks, active) then return end
	end
	local name, icon = SpellName(best)
	table.insert(entries, { key = slot.key, reason = L["Missing"], color = RED, spellID = best, icon = icon, label = name,
		action = { type = "spell", spell = best, unit = "player" } })
end

-- The shield slot (WARRIOR_SHIELD), for tanks: a reminder when the off
-- hand holds no shield. It only tells; which shield is yours to pick.
local SHIELD_BLOCK = 2565
local SHIELD_ICON = "Interface\\Icons\\INV_Shield_04"
function M:ShieldEntry(entries, slot)
	local id = GetInventoryItemID("player", INVSLOT_OFFHAND or 17)
	if IsSecret(id) then return end
	if id then
		local _, _, _, equipLoc = C_Item.GetItemInfoInstant(id)
		if IsSecret(equipLoc) or equipLoc == nil or equipLoc == "INVTYPE_SHIELD" then return end
	end
	local _, icon = SpellName(SHIELD_BLOCK)
	table.insert(entries, { key = slot.key, reason = L["No shield"], color = RED, icon = icon or E:ClientIcon(SHIELD_ICON),
		label = L["Shield"] })
end

local function ShamanSlot(key)
	for _, slot in ipairs(CLASS_BUFFS.SHAMAN) do
		if slot.key == key then return slot end
	end
end

local function IsShaman()
	local _, class = UnitClass("player")
	return not IsSecret(class) and class == "SHAMAN"
end

-- Say it where the player looks: the Combat Text notification lane in
-- combat, an alert card out of combat (and in combat while that lane is off).
local function Announce(text, icon)
	local ct = E.CombatText
	if InCombatLockdown() and ct and ct.active and ct.Show then
		local ok, shown = pcall(ct.Show, ct, text, "notify", { icon = icon, color = YELLOW })
		if ok and shown then return end
	end
	M:PushAlert({ key = "reminders:" .. text, title = L["Reminders"], text = text, icon = icon })
end
M.Announce = Announce

-- The state of each watched thing: "on", "low" (running out) or "off".
-- An alert shows once when the state gets worse; nothing shows while the
-- game doesn't say (the shield in combat, a secret enchant answer).
local alertState = {}
M.alertState = alertState
-- `quiet`: the state is kept but nothing shows (dead, on a flight, or
-- where reminders are set not to show), so nothing pops late either.
local function Changed(key, state, text, icon, quiet)
	local before = alertState[key]
	alertState[key] = state
	if quiet or not before or state == before or state == "on" or before == "off" then return end
	Announce(text, icon)
end

function M:ShamanAlerts()
	if not (self.active and IsShaman()) then return end
	local db = self.db.alerts
	-- The same "when and where" as the reminder list.
	local quiet = SafeBool(UnitIsDeadOrGhost, "player") ~= false or SafeBool(UnitOnTaxi, "player") ~= false
		or not self:ContentAllowed()
	for _, key in ipairs({ "SHAMAN_IMBUE", "SHAMAN_IMBUE_OFF" }) do
		local slot = ShamanSlot(key)
		local names, best = SlotInfo(slot)
		local has, left
		if db.imbue and names and (slot.weapon == "main" or HasOffHandWeapon()) then
			has, left = WeaponEnchant(slot.weapon)
		end
		if has == nil then
			alertState[key] = nil
		else
			local state = not has and "off" or (left and left < self.db.threshold and "low") or "on"
			local _, icon = SpellName(best)
			local hand = slot.weapon == "off" and L["Off-hand"] or L["Main-hand"]
			Changed(key, state, state == "off" and L["%s imbue is gone"]:format(hand) or L["%s imbue is running out"]:format(hand), icon, quiet)
		end
	end
	if not db.shield then
		alertState.SHAMAN_SHIELD = nil
	elseif not InCombatLockdown() then
		local names, best, counts = SlotInfo(ShamanSlot("SHAMAN_SHIELD"))
		local byName = names and ScanAuras("player")
		if byName then
			local active
			for spellName in pairs(counts) do
				if byName[spellName] then active = byName[spellName] break end
			end
			local left = active and TimeLeft(active)
			local state = not active and "off" or (left and left < self.db.threshold and "low") or "on"
			local _, icon = SpellName(best)
			Changed("SHAMAN_SHIELD", state, state == "off" and L["Your shield is gone"] or L["Your shield is running out"], icon, quiet)
		end
	end
end

-- The shield-gone sound: the game plays it when a shield leaves you (in
-- combat too). Registered out of combat only.
local shieldSounds = {}
function M:SyncShieldSound()
	local auras = C_UnitAuras
	for _, handle in ipairs(shieldSounds) do
		if auras and auras.RemoveAuraSound then pcall(auras.RemoveAuraSound, handle) end
	end
	wipe(shieldSounds)
	self.shieldSoundStatus = nil
	if not (self.active and self.db.alerts.shieldSound and IsShaman()) then return end
	local removed = Enum.UnitAuraSoundTrigger and Enum.UnitAuraSoundTrigger.Removed
	if not (auras and auras.AddAuraSound and removed) then
		self.shieldSoundStatus = L["Not available in this game client."]
		return
	end
	local file = E:FetchMedia("sound", self.db.alerts.sound)
	if type(file) ~= "string" then file = E:FetchMedia("sound", "eldo:EldoChime") end
	for _, ranks in ipairs(ShamanSlot("SHAMAN_SHIELD").spells) do
		for _, id in ipairs(ranks) do
			local ok, handle = pcall(auras.AddAuraSound, removed,
				{ spellID = id, unitToken = "player", soundFileName = file, outputChannel = "Master" })
			if ok and handle then shieldSounds[#shieldSounds + 1] = handle end
		end
	end
	if #shieldSounds == 0 then self.shieldSoundStatus = L["The game did not take the sound."] end
end
M.shieldSounds = shieldSounds

function M:ConsumableEntries(entries, byName, bySpell)
	local limit = self.db.consumableMinutes * 60
	local groups = {} -- one reminder per buff / weapon hand
	local wellFed = SpellName(WELL_FED_SPELL) or "Well Fed"
	local ids = {}
	for id in pairs(self.db.items) do table.insert(ids, id) end
	table.sort(ids)
	for _, id in ipairs(ids) do
		local data = self.db.items[id]
		local kind = data.kind or "aura"
		local groupKey, missing, left, readable = nil, false, nil, true
		if kind == "main" or kind == "off" then
			groupKey = "weapon-" .. kind
			if kind == "off" and not HasOffHandWeapon() then
				groupKey = nil
			else
				local has, expires = WeaponEnchant(kind)
				if has == nil then readable = false
				elseif not has then missing = true
				elseif expires and expires < limit then left = expires end
			end
		else
			local spellID, spellName = ItemSpell(id, data)
			if kind == "food" then spellID, spellName = nil, wellFed end
			if spellName or spellID then
				groupKey = "aura-" .. (spellName or spellID)
				local aura = (spellID and bySpell[spellID]) or (spellName and byName[spellName])
				if not aura then
					missing = true
				else
					local auraLeft = TimeLeft(aura)
					if auraLeft and auraLeft < limit then left = auraLeft end
				end
			end
		end
		if groupKey and readable and (missing or left) then
			local count = C_Item.GetItemCount(id) or 0
			local current = groups[groupKey]
			-- Prefer the item you actually carry.
			if not current or (current.count == 0 and count > 0) then
				local entry = {
					key = "ITEM-" .. groupKey, itemID = id, icon = ItemIcon(id), label = ItemName(id),
					reason = missing and (kind == "main" and L["No main-hand enchant"] or kind == "off" and L["No off-hand enchant"] or L["Missing"])
						or L["Running out"],
					color = missing and RED or YELLOW, time = left, count = count, isItem = true,
				}
				-- Click-to-buff: use the item; a weapon oil or stone is
				-- used and then put on the weapon slot, like a two-line macro.
				if count > 0 then
					if kind == "main" or kind == "off" then
						local slot = kind == "main" and (INVSLOT_MAINHAND or 16) or (INVSLOT_OFFHAND or 17)
						entry.action = { type = "macro", macrotext = ("/use item:%d\n/use %d"):format(id, slot) }
					else
						entry.action = { type = "item", item = "item:" .. id }
					end
				end
				if current then
					for index, other in ipairs(entries) do
						if other == current then entries[index] = entry end
					end
				else
					table.insert(entries, entry)
				end
				groups[groupKey] = entry
			end
		end
	end
	-- "Remind even with none in your bags" off: drop what you can't use.
	if not self.db.remindWithoutItem then
		for index = #entries, 1, -1 do
			if entries[index].isItem and (entries[index].count or 0) == 0 then table.remove(entries, index) end
		end
	end
end

---------------------------------------------------------------------------
-- Display
---------------------------------------------------------------------------
E:RegisterGlowUser("reminders", {
	title = "Reminders",
	desc = "Missing buff and consumable reminders, when their highlight is set to Glow (Buff and Consumable Reminders > Look).",
	order = 40,
	button = true,
	default = { style = "pixel", colorMode = "custom", color = { 1, 0.27, 0.27 } },
})

local function FormatTime(seconds)
	if seconds >= 60 then return ("%dm"):format(math.ceil(seconds / 60)) end
	return ("%ds"):format(seconds)
end

local function IconTooltip(icon)
	local entry = icon.entry
	if not entry then return end
	GameTooltip:SetOwner(icon, "ANCHOR_BOTTOM", 0, -4)
	if entry.itemID then
		GameTooltip:SetItemByID(entry.itemID)
	elseif entry.spellID then
		GameTooltip:SetSpellByID(entry.spellID)
	else
		E.UIKit.TipTitle(GameTooltip, entry.label or "")
	end
	GameTooltip:AddLine(" ")
	local color = entry.color or RED
	GameTooltip:AddLine(E:Translate(entry.reason) or "", color[1], color[2], color[3], true)
	if entry.note then E.UIKit.TipText(GameTooltip, entry.note) end
	if entry.count and not entry.isItem and not entry.poisonCount then
		GameTooltip:AddLine((entry.count == 1 and L["%d group member without it"] or L["%d group members without it"]):format(entry.count), E:TokenColor("warn"))
	elseif entry.isItem or entry.poisonCount then
		E.UIKit.TipText(GameTooltip, L["%d in your bags"]:format(entry.count or 0))
	end
	if M.db.clickCast and entry.action and not M.preview then
		E:TooltipHint(GameTooltip, { L["Click"], entry.action.type == "spell" and L["cast it"] or L["use it"] })
		if entry.hint then E:TooltipHint(GameTooltip, entry.hint) end
	elseif entry.action and not M.preview then
		-- Off by default: say where it turns on, so a click is never a mystery.
		E.UIKit.TipText(GameTooltip, L["To cast or use it with a click, turn on \"%s\" (/eui > Reminders)."]:format(L["Click an icon to cast or use it"]))
	end
	if entry.pick and not M.preview then
		if InCombatLockdown() then
			E.UIKit.TipText(GameTooltip, L["Picks change out of combat."])
		else
			local what = entry.pick == "stone" and L["pick the stone"] or L["pick the poison"]
			if entry.pick:match("^buff:") then what = L["pick the spell and rank"] end
			E:TooltipHint(GameTooltip, { L["Right-click"], what })
		end
	end
	GameTooltip:Show()
end

function M:CreateIcon()
	local icon = CreateFrame("Button", nil, self.frame)
	E:SetTemplate(icon)
	icon.texture = icon:CreateTexture(nil, "ARTWORK")
	icon.texture:SetPoint("TOPLEFT", E.pixel, -E.pixel)
	icon.texture:SetPoint("BOTTOMRIGHT", -E.pixel, E.pixel)
	E:TrimIcon(icon.texture)
	icon.time = E:CreateText(icon, E.tokens.size.label)
	icon.time:SetPoint("CENTER", 0, 0)
	icon.count = E:CreateText(icon, E.tokens.size.small, "RIGHT")
	icon.count:SetPoint("BOTTOMRIGHT", -2, 2)
	icon.badge = E:CreateText(icon, E.tokens.size.small, "LEFT")
	icon.badge:SetPoint("TOPLEFT", 2, -2)
	icon.label = E:CreateText(icon, E.tokens.size.small)
	E:UseNameFont(icon.label)
	icon.label:SetPoint("TOP", icon, "BOTTOM", 0, -4)
	icon.label:SetTextColor(unpack(E.media.text.secondary))

	local group = icon:CreateAnimationGroup()
	group:SetLooping("BOUNCE")
	local fade = group:CreateAnimation("Alpha")
	fade:SetFromAlpha(1)
	fade:SetToAlpha(0.45)
	fade:SetDuration(0.7)
	icon.pulse = group

	icon:RegisterForClicks("AnyUp")
	icon:SetScript("OnEnter", IconTooltip)
	icon:SetScript("OnLeave", GameTooltip_Hide)
	icon:SetScript("OnClick", function(clicked, button)
		-- Tooltip only; click-to-buff is a separate secure button.
		if E:IsOptionsLinkClick(clicked, button) or E:IsHideClick(clicked, button) then return end
		if button == "RightButton" and clicked.entry and clicked.entry.pick then
			M:OpenPick(clicked, clicked.entry.pick)
			return
		end
		IconTooltip(clicked)
		E:OptionsLinkHint(GameTooltip, clicked)
		GameTooltip:Show()
	end)
	-- Ctrl-click: the click-to-cast setting while it is off, else the page.
	E:BindOptionsLink(icon, function(bound)
		if bound.entry and bound.entry.action and not M.db.clickCast then
			return { page = "module:Reminders", key = "clickCast", label = "Click an icon to cast or use it" }
		end
		return { page = "module:Reminders" }
	end)
	E:RegisterHideable(icon, "EldoUI_Reminders")
	return icon
end

local function SetHighlight(icon, entry, db)
	local missing = entry.color == RED
	local mode = db.highlight
	if missing and mode == "pulse" then
		if not icon.pulse:IsPlaying() then icon.pulse:Play() end
	else
		icon.pulse:Stop()
	end
	if missing and mode == "glow" then
		E:ShowUserGlow(icon, "reminders")
	elseif E:IsGlowShown(icon) then
		E:HideGlow(icon)
	end
end

function M:LayoutRow(entries, pool, size, top)
	local db = self.db
	local count = #entries
	local width = count * size + math.max(count - 1, 0) * db.spacing
	for index, entry in ipairs(entries) do
		local icon = pool[index] or self:CreateIcon()
		pool[index] = icon
		icon.entry = entry
		icon:SetSize(size, size)
		icon:ClearAllPoints()
		icon:SetPoint("TOPLEFT", self.frame, "TOP", -width / 2 + (index - 1) * (size + db.spacing), top)
		E:SetTemplate(icon)
		local color = entry.color or RED
		icon:SetBackdropBorderColor(color[1], color[2], color[3], 1)
		icon.texture:SetTexture(entry.icon or 134400)
		icon.texture:SetDesaturated((entry.isItem and (entry.count or 0) == 0) or entry.dim == true)
		icon.time:SetText(entry.text or (entry.time and FormatTime(entry.time)) or "")
		icon.time:SetTextColor(E:TokenColor("warn"))
		local countText = ""
		if entry.isItem or entry.poisonCount then
			if db.showCount then countText = tostring(entry.count or 0) end
		elseif entry.count then
			countText = tostring(entry.count)
		end
		icon.count:SetText(countText)
		icon.badge:SetText(entry.badge or "")
		icon.badge:SetTextColor(GREEN[1], GREEN[2], GREEN[3])
		icon.label:SetShown(db.showLabel)
		icon.label:SetText(entry.label or "")
		E:SetFont(icon.time, math.max(10, math.floor(size / 4)))
		icon:SetAlpha(1)
		SetHighlight(icon, entry, db)
		if E:IsGlowShown(icon) then E:UpdateGlowLayout(icon) end
		icon:Show()
	end
	for index = count + 1, #pool do
		pool[index].entry = nil
		pool[index].pulse:Stop()
		if E:IsGlowShown(pool[index]) then E:HideGlow(pool[index]) end
		pool[index]:Hide()
	end
end

---------------------------------------------------------------------------
-- Click-to-buff (opt-in). One secure button per icon, parented to
-- UIParent and placed by screen position over the icon, so the reminder
-- frame itself never becomes protected and can still show and hide in
-- combat. Buttons are created, moved and given their spell or item only
-- out of combat; in combat they keep what they had. When the reminders
-- hide in combat, a secure state driver hides the buttons with them.
-- One click = one cast or one use, by the player; nothing runs by itself.
---------------------------------------------------------------------------
local secureButtons = {}
local ACTION_ATTRIBUTES = { "type1", "type2", "spell", "spell2", "item", "macrotext", "unit" }

local function GetSecureButton(index)
	local button = secureButtons[index]
	if button then return button end
	if InCombatLockdown() then return nil end
	button = CreateFrame("Button", "EldoUI_ReminderAction" .. index, UIParent, "SecureActionButtonTemplate")
	button:SetFrameStrata("MEDIUM")
	button:RegisterForClicks("AnyUp", "AnyDown")
	local highlight = button:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetAllPoints()
	button.highlight = highlight
	button:SetScript("OnEnter", function(self) if self.icon then IconTooltip(self.icon) end end)
	button:SetScript("OnLeave", GameTooltip_Hide)
	-- A right-click on a poison reminder opens its pick (the button has
	-- no right-click action of its own there).
	button:HookScript("PostClick", function(self, mouse, down)
		local entry = self.icon and self.icon.entry
		if mouse == "RightButton" and not down and entry and entry.pick then M:OpenPick(self, entry.pick) end
	end)
	button:Hide()
	secureButtons[index] = button
	return button
end

-- Reminders that hide in combat take their buttons with them: the
-- visibility engine registers the state driver (Core/Visibility.lua).
local OUT_OF_COMBAT = E:VisibilityDefaults({ show = "nocombat" })
E:RegisterVisibilityFacet("EldoUI_Reminders", "event", { module = "Reminders" })

local function ClearSecureButton(button)
	if button.driver then
		E:DetachVisibility(button)
		button.driver = nil
	end
	button.icon = nil
	button.key = nil
	button:Hide()
end

-- Out of combat only: put a button over every icon that has an action.
function M:SyncClickCast()
	if InCombatLockdown() then
		if not self.clickPending then
			self.clickPending = true
			E:RunOutOfCombat(function()
				M.clickPending = nil
				M:SyncClickCast()
			end)
		end
		return
	end
	local wanted = {}
	if self.active and self.db.clickCast and not self.preview and self.frame and self.frame:IsShown() then
		for _, pool in ipairs({ self.buffIcons or {}, self.itemIcons or {} }) do
			for _, icon in ipairs(pool) do
				if icon:IsShown() and icon.entry and icon.entry.action then wanted[#wanted + 1] = icon end
			end
		end
	end
	local r, g, b = unpack(E.media.accentColor)
	for index, icon in ipairs(wanted) do
		local button = GetSecureButton(index)
		if not button then break end
		local action = icon.entry.action
		local key = table.concat({ tostring(action.type), tostring(action.spell), tostring(action.spell2),
			tostring(action.item), tostring(action.macrotext), tostring(action.unit) }, "|")
		if button.key ~= key then
			for _, attribute in ipairs(ACTION_ATTRIBUTES) do button:SetAttribute(attribute, nil) end
			button:SetAttribute("type1", action.type)
			if action.type == "spell" then button:SetAttribute("spell", action.spell) end
			if action.type == "item" then button:SetAttribute("item", action.item) end
			if action.type == "macro" then button:SetAttribute("macrotext", action.macrotext) end
			if action.unit then button:SetAttribute("unit", action.unit) end
			if action.spell2 then
				button:SetAttribute("type2", "spell")
				button:SetAttribute("spell2", action.spell2)
			end
			button.key = key
		end
		button.highlight:SetColorTexture(r, g, b, 0.2) -- accent read at draw time
		local left, bottom = icon:GetLeft(), icon:GetBottom()
		if left and bottom then
			local scale = icon:GetEffectiveScale() / UIParent:GetEffectiveScale()
			button:ClearAllPoints()
			button:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left * scale, bottom * scale)
			button:SetSize(icon:GetWidth() * scale, icon:GetHeight() * scale)
			button:SetFrameLevel(icon:GetFrameLevel() + 5)
			button.icon = icon
			-- Reminders that hide in combat take their buttons with them.
			local driver = not self.db.inCombat or nil
			if driver ~= button.driver then
				button.driver = driver
				if driver then
					E:AttachVisibility(button, OUT_OF_COMBAT, { secure = true, exempt = true, watch = false, module = "Reminders" })
				else
					E:DetachVisibility(button)
				end
			end
			if not driver then button:Show() end
		else
			ClearSecureButton(button)
		end
	end
	for index = #wanted + 1, #secureButtons do ClearSecureButton(secureButtons[index]) end
end

---------------------------------------------------------------------------
-- Ready check: a low-mana note above the reminders (own mana, out of
-- combat, plain values only).
---------------------------------------------------------------------------
local MANA = Enum and Enum.PowerType and Enum.PowerType.Mana or 0

local function ManaPercent()
	local powerType = UnitPowerType("player")
	if IsSecret(powerType) or powerType ~= MANA then return nil end
	local current, maximum = UnitPower("player", MANA), UnitPowerMax("player", MANA)
	if IsSecret(current) or IsSecret(maximum) or not current or not maximum or maximum <= 0 then return nil end
	return current / maximum * 100
end

-- The note is a short-lived notice: a holder of EldoUI's one notice queue
-- (Core/Alerts.lua) that sits on the reminder frame. It goes when the
-- ready check ends or its time is up; the reminders themselves stay.
local READY_KEY = "reminders:readycheck"

function M:ShowReadyCheckMana(duration)
	if not (self.db.readyCheckMana and self.frame) or InCombatLockdown() then return end
	local percent = ManaPercent()
	if not percent or percent >= self.db.readyCheckPercent then return end
	E:PushNotice("readycheck", { key = READY_KEY, percent = percent,
		duration = math.max(5, math.min(tonumber(duration) or 30, 60)) })
end

function M:DrawManaNote(data)
	if not self.frame then return nil end
	local note = self.manaNote
	if not note then
		note = CreateFrame("Frame", nil, self.frame)
		note:SetSize(300, 24)
		note:SetPoint("BOTTOM", self.frame, "TOP", 0, 8)
		note.text = E:CreateText(note, E.tokens.size.display)
		note.text:SetPoint("CENTER")
		local group = note:CreateAnimationGroup()
		group:SetLooping("BOUNCE")
		local fade = group:CreateAnimation("Alpha")
		fade:SetFromAlpha(1)
		fade:SetToAlpha(0.35)
		fade:SetDuration(0.6)
		note.pulse = group
		self.manaNote = note
	end
	E:SetFont(note.text, E.tokens.size.display)
	note.text:SetText(L["Low mana: %d%%"]:format(data.percent))
	-- The player's mana color (Colors page), and a pulse only with
	-- General > Animations on.
	local r, g, b = E:GetPowerColor("MANA")
	if r then note.text:SetTextColor(r, g, b) else note.text:SetTextColor(unpack(E.media.text.body)) end
	note:Show()
	note:SetAlpha(1)
	if E.db.general.animations then note.pulse:Play() else note.pulse:Stop() end
	-- The note sits on the reminder frame: keep that shown while it runs.
	self.frame:Show()
	return note
end

function M:EndManaNote()
	local note = self.manaNote
	if not note then return end
	note.pulse:Stop()
	note:Hide()
	E:NoticeClosed(note)
	self:RequestUpdate()
end

function M:HideReadyCheckMana()
	local note = self.manaNote
	if not note then return end
	if not E:CloseNotice(note, true) then self:EndManaNote() end
end

E:RegisterNoticeHolder("readycheck", {
	usable = function() return M.active and M.frame ~= nil end,
	wait = 5,
	show = function(data) return M:DrawManaNote(data) end,
	refresh = function(_, data) M:DrawManaNote(data) end,
	hide = function() M:EndManaNote() end,
})

---------------------------------------------------------------------------
-- Building and showing the list
---------------------------------------------------------------------------
-- Preview icons: real game icons, never a question mark.
local PREVIEW_ICON = "Interface\\Icons\\Spell_Holy_PowerWordShield"
local PREVIEW_ITEM_ICON = "Interface\\Icons\\INV_Misc_Food_15"
local PREVIEW = {
	{ key = "P1", spellID = 1459, reason = Key("Missing (preview)"), color = RED },
	{ key = "P2", spellID = 588, reason = Key("Running out (preview)"), color = YELLOW, time = 42 },
	{ key = "P3", spellID = 2383, reason = Key("Higher rank known (preview)"), color = GREEN, badge = "UP" },
}

function M:Update()
	self.dirty = false
	self.playerAuras, self.showsTime = nil, false
	if not self.frame then return end
	local db = self.db
	local buffs, items = {}, {}
	-- The whole list was read this time (not hidden while dead, on a
	-- flight, in combat or where reminders don't show): only then does it
	-- replace what the sound compares with.
	local whole = false
	if self:ShouldShow() then
		if self.preview then
			for _, entry in ipairs(PREVIEW) do
				local name, icon = SpellName(entry.spellID)
				entry.label, entry.icon = name or L["Preview"], icon or PREVIEW_ICON
				table.insert(buffs, entry)
			end
			table.insert(buffs, { key = "P5", icon = E:ClientIcon(DURABILITY_ICON), label = E:GameText(_G.DURABILITY, L["Durability"]), text = "18%",
				reason = L["Durability (preview)"], color = RED })
			table.insert(items, { key = "P4", icon = PREVIEW_ITEM_ICON, label = L["Consumable"], reason = L["Missing (preview)"], color = RED, count = 5, isItem = true })
		else
			local inCombat = InCombatLockdown()
			-- In combat auras can't be read: keep what showed when the
			-- fight started ("Also in combat") instead of an empty row.
			if inCombat and self.lastKeys then return end
			if self:ContentAllowed() then
				whole = not inCombat
				local byName, bySpell = ScanAuras("player")
				self.playerAuras = byName
				if byName then
					if db.buffs then self:BuffEntries(buffs, byName, bySpell, inCombat) end
					self:CustomEntries(buffs, byName)
					if db.askBuffs and not inCombat then self:AskEntries(buffs, byName) end
					if db.tracking then self:TrackingEntry(buffs, byName) end
					if db.consumables then self:ConsumableEntries(items, byName, bySpell) end
				end
				if not inCombat then
					self:PetEntries(buffs)
					if db.healthstone then self:HealthstoneEntry(items) end
					if db.xpFood then self:XPFoodEntry(items) end
					self:StoneEntries(items)
					self:SoulstoneEntry(items)
				end
			end
			-- Durability: also in rest areas, where you can repair.
			if db.durability and not inCombat then self:DurabilityEntry(buffs) end
		end
	end

	-- Sound when a reminder first appears. A reminder that was there before
	-- a fight, a death, a flight or a hide is no news when it comes back,
	-- and the first list after login or a reload only sets what is known.
	local seen = {}
	local fresh = false
	local known = self.lastKeys
	for _, list in ipairs({ buffs, items }) do
		for _, entry in ipairs(list) do
			seen[entry.key] = true
			if entry.time and not self.preview then self.showsTime = true end
			if known and not known[entry.key] then fresh = true end
		end
	end
	if not self.preview then
		if whole then
			self.lastKeys = seen
		elseif known then
			for key in pairs(seen) do known[key] = true end
		end
	end
	if fresh and db.sound and db.sound ~= "none" and not self.preview then
		local now = GetTime()
		if not self.lastSound or now - self.lastSound > 3 then
			self.lastSound = now
			E:PlayMedia(db.sound)
		end
	end

	local size = db.iconSize
	local small = math.floor(size * db.consumableScale + 0.5)
	local labelGap = db.showLabel and 18 or 0
	self:LayoutRow(buffs, self.buffIcons, size, 0)
	local itemTop = #buffs > 0 and -(size + labelGap + db.spacing) or 0
	self:LayoutRow(items, self.itemIcons, small, itemTop)
	self.frame:SetAlpha(db.alpha)
	local noteShown = self.manaNote and self.manaNote:IsShown()
	self.frame:SetShown(#buffs + #items > 0 or noteShown)
	if not InCombatLockdown() then self:SyncClickCast() end
	-- The tour help follows the icons coming up, not every redraw.
	local iconsUp = #buffs + #items > 0 and not self.preview
	if iconsUp and not self.iconsWereUp then self:OfferTourHelp() end
	self.iconsWereUp = iconsUp
end

---------------------------------------------------------------------------
-- When the list is checked: events mark it dirty and one check follows
-- within 0.2 s on the shared ticker (a burst of events costs one check).
-- Aura changes come only for you and, with the group count on, for the
-- members of your group, each unit on its own registration; a member's
-- aura that only refreshes changes no count and is skipped. Time-bound
-- things (a buff, an imbue or a poison about to run out, the time shown
-- on an icon) wake the check exactly when something can change; with
-- nothing to watch, nothing runs between events.
---------------------------------------------------------------------------
local UPDATE, WAKE = "Reminders:update", "Reminders:wake"

function M:RequestUpdate()
	self.dirty = true
	local ticker = E.Ticker
	if not (self.active and ticker) or ticker:IsSubscribed(UPDATE) then return end
	ticker:Subscribe(UPDATE, 0.2, function()
		ticker:Unsubscribe(UPDATE)
		M:Refresh()
	end, "Reminders")
end

function M:Refresh()
	if not self.active then return end
	if self.dirty then self:Update() end
	self:ShamanAlerts()
	self:ScheduleWake()
end

-- Seconds until a timer with `left` seconds reaches the next point that
-- changes a reminder: a "running out" mark or its end.
local function NextMark(left, marks)
	local best
	for _, mark in ipairs(marks) do
		if left > mark + 0.05 and (not best or left - mark < best) then best = left - mark end
	end
	return best
end

function M:ScheduleWake()
	local ticker = E.Ticker
	if not ticker then return end
	if not self.active then
		ticker:Unsubscribe(WAKE)
		return
	end
	local db = self.db
	local marks = { tonumber(db.threshold) or 60, (tonumber(db.consumableMinutes) or 3) * 60, 0 }
	local soonest
	local function Consider(wait)
		if wait and (not soonest or wait < soonest) then soonest = wait end
	end
	-- Time left on an icon: fresh every two seconds while it shows.
	if self.showsTime and self.frame and self.frame:IsShown() and not InCombatLockdown() then Consider(2) end
	-- Your own buffs, as read by the last check (none in combat).
	for _, aura in pairs(self.playerAuras or {}) do
		local left = TimeLeft(aura)
		if left then Consider(NextMark(left, marks)) end
	end
	-- Weapon imbues, poisons and oils (the game says these in combat too).
	for _, hand in ipairs({ "main", "off" }) do
		local has, left = WeaponEnchant(hand)
		if has and left then Consider(NextMark(left, marks)) end
	end
	if not soonest then
		ticker:Unsubscribe(WAKE)
		return
	end
	ticker:Subscribe(WAKE, math.max(0.2, soonest), function()
		ticker:Unsubscribe(WAKE)
		M.dirty = true
		M:Refresh()
	end, "Reminders")
end

-- A member's aura change that adds or removes an aura (or a full update);
-- one that only refreshes a timer changes no count.
local function AddsOrRemoves(info)
	if type(info) ~= "table" or IsSecret(info) then return true end
	local full, added, removed = info.isFullUpdate, info.addedAuras, info.removedAuraInstanceIDs
	if IsSecret(full) or IsSecret(added) or IsSecret(removed) then return true end
	if full then return true end
	return (type(added) == "table" and #added > 0) or (type(removed) == "table" and #removed > 0) or false
end

local groupWatch = {} -- frames, each listening to two group units
M.groupWatch = groupWatch

local function GroupAura(_, _, _, info)
	if AddsOrRemoves(info) then M:RequestUpdate() end
end

-- Aura events for the group's units only, and only for the group count.
function M:WatchGroup(off)
	local units = (not off and self.active and self.db.group) and GroupUnits() or {}
	local need = math.ceil(#units / 2)
	for index = 1, math.max(need, #groupWatch) do
		local frame = groupWatch[index]
		if index <= need then
			if not frame then
				frame = CreateFrame("Frame")
				frame:SetScript("OnEvent", GroupAura)
				groupWatch[index] = frame
			end
			local first, second = units[index * 2 - 1], units[index * 2]
			if frame.first ~= first or frame.second ~= second then
				frame:UnregisterEvent("UNIT_AURA")
				if second then frame:RegisterUnitEvent("UNIT_AURA", first, second) else frame:RegisterUnitEvent("UNIT_AURA", first) end
				frame.first, frame.second = first, second
			end
		elseif frame and frame.first then
			frame:UnregisterEvent("UNIT_AURA")
			frame.first, frame.second = nil, nil
		end
	end
end

function M:CreateFrame()
	local frame = CreateFrame("Frame", "EldoUI_Reminders", UIParent)
	frame:SetFrameStrata("MEDIUM")
	frame:SetSize(self.db.iconSize * 3 + self.db.spacing * 2, self.db.iconSize * 2)
	self.frame = frame
	self.buffIcons, self.itemIcons = {}, {}

	local driver = CreateFrame("Frame")
	driver:SetScript("OnEvent", function(_, event, unit, ...)
		if not M.active then return end
		if event == "UNIT_SPELLCAST_SUCCEEDED" then
			-- Only a class buff you cast changes a reminder (Automatic).
			local _, spellID = ...
			if not M:NoteCast(spellID) then return end
		elseif event == "READY_CHECK" then
			M:ShowReadyCheckMana(...)
		elseif event == "READY_CHECK_FINISHED" then
			M:HideReadyCheckMana()
		elseif event == "GROUP_ROSTER_UPDATE" then
			M:WatchGroup()
		end
		M:RequestUpdate()
	end)
	self.driver = driver
	E:CreateMover(frame, "EldoUI_Reminders", L["Reminders"], { "CENTER", "UIParent", "CENTER", 0, 120 })
end

-- Your own unit events: only for you (and your pet).
local PLAYER_EVENTS = { UNIT_AURA = true, UNIT_INVENTORY_CHANGED = true, UNIT_PET = true, UNIT_SPELLCAST_SUCCEEDED = true }
local EVENTS = {
	"UNIT_AURA", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "PLAYER_UPDATE_RESTING",
	"PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST", "UNIT_INVENTORY_CHANGED", "BAG_UPDATE_DELAYED",
	"SPELLS_CHANGED", "GROUP_ROSTER_UPDATE", "MINIMAP_UPDATE_TRACKING", "PLAYER_CONTROL_LOST",
	"PLAYER_CONTROL_GAINED", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD", "GET_ITEM_INFO_RECEIVED",
	"PLAYER_EQUIPMENT_CHANGED", "UNIT_PET", "PET_BAR_UPDATE", "UPDATE_INVENTORY_DURABILITY",
	"PLAYER_MOUNT_DISPLAY_CHANGED", "READY_CHECK", "READY_CHECK_FINISHED", "UNIT_SPELLCAST_SUCCEEDED",
}

-- Settings of older versions: "Hide in rest areas", the pulse toggle and
-- SOUNDKIT sound names.
function M:OnInitialize()
	local db = self.db
	if db.hideResting ~= nil then
		db.showResting = not db.hideResting
		db.hideResting = nil
	end
	if db.pulse ~= nil then
		if db.pulse == false and db.highlight == "pulse" then db.highlight = "none" end
		db.pulse = nil
	end
	if type(db.sound) == "string" and OLD_SOUNDS[db.sound] then db.sound = "kit:" .. db.sound end
end

function M:OnEnable()
	if not self.frame then self:CreateFrame() end
	local driver = self.driver
	for _, event in ipairs(EVENTS) do
		if PLAYER_EVENTS[event] then
			pcall(driver.RegisterUnitEvent, driver, event, "player")
		else
			pcall(driver.RegisterEvent, driver, event)
		end
	end
	self.lastKeys = nil
	self:WatchGroup()
	self:Update()
	self:ScheduleWake()
	E:RunOutOfCombat(function() M:SyncShieldSound() end, "Reminders:shieldSound")
end

function M:OnDisable()
	if self.driver then self.driver:UnregisterAllEvents() end
	self:WatchGroup(true)
	if E.Ticker then
		E.Ticker:Unsubscribe(UPDATE)
		E.Ticker:Unsubscribe(WAKE)
	end
	self.preview, self.iconsWereUp = nil, nil
	if self.frame then self.frame:Hide() end
	if self.picker then self.picker:Hide() end
	self:HideReadyCheckMana()
	self:SyncClickCast()
	E:RunOutOfCombat(function() M:SyncShieldSound() end, "Reminders:shieldSound")
end

-- Re-apply size, theme colors and fonts after any option or theme change.
function M:OnProfileChanged()
	if not self.frame then return end
	self:ApplyCustomInput()
	self.frame:SetSize(self.db.iconSize * 3 + self.db.spacing * 2, self.db.iconSize * 2)
	for _, pool in ipairs({ self.buffIcons, self.itemIcons }) do
		for _, icon in ipairs(pool) do
			E:SetFont(icon.count, E.tokens.size.small)
			E:SetFont(icon.badge, E.tokens.size.small)
			E:SetFont(icon.label, E.tokens.size.small)
		end
	end
	if self.picker then E:SetPanelTemplate(self.picker) ; self:RefreshPicker() end
	if self.active then
		self:WatchGroup()
		self:Update()
		self:ScheduleWake()
	end
	E:RunOutOfCombat(function() M:SyncShieldSound() end, "Reminders:shieldSound")
end

-- The option rows "Add a spell ID" and "Remove": read once, then cleared.
function M:ApplyCustomInput()
	local db = self.db
	local add = strtrim(tostring(db.customAdd or ""))
	if add ~= "" then
		local id = tonumber(add) or tonumber(add:match("spell:(%d+)"))
		if id and SpellName(id) then
			db.customSpells[id] = true
		elseif add ~= "" then
			M:PushAlert({ key = "eldoui-reminders-spell", title = L[self.title], text = L["%q is not a spell ID this client knows."]:format(add) })
		end
		db.customAdd = ""
	end
	local remove = tonumber(db.customRemove)
	if remove then db.customSpells[remove] = nil end
	db.customRemove = ""
end

-- Sample reminders: state true shows them (for `seconds`, or until called
-- with false when no time is given; move mode's test frames use that).
function M:SetPreview(state, seconds)
	if not self.active then return end
	self.preview = state and true or nil
	self.previewToken = (self.previewToken or 0) + 1
	if self.preview and seconds then
		local token = self.previewToken
		C_Timer.After(seconds, function()
			if M.preview and M.previewToken == token then M.preview = nil; M:RequestUpdate() end
		end)
	end
	self:Update()
end

function M:TogglePreview()
	self:SetPreview(not self.preview, 15)
end

---------------------------------------------------------------------------
-- Consumable picker: bag consumables plus a search box. Left-click picks
-- or drops an item, right-click changes what it is checked against.
---------------------------------------------------------------------------
local KINDS = { "aura", "food", "main", "off" }
local KIND_NAMES = E:TranslateValues({ aura = E.Key("Buff"), food = E.Key("Well Fed"), main = E.Key("Main hand"), off = E.Key("Off hand") })

-- First guess of what an item does; the player can change it.
local function GuessKind(id)
	local _, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(id)
	if classID == 0 and subclassID == 5 then return "food" end
	if classID == 0 and subclassID == 6 then return "main" end
	local name = (ItemName(id) or ""):lower()
	if (name:find("oil") or name:find("stone") or name:find("poison")) and not name:find("potion") then return "main" end
	local spellName = C_Item.GetItemSpell(id)
	local food = SpellName(433)
	if spellName and food and spellName == food then return "food" end
	return "aura"
end

local function BagConsumables()
	local found, list = {}, {}
	local lastBag = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS
	for bag = 0, lastBag do
		for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			local id = info and info.itemID
			if id and not found[id] then
				local _, _, _, _, _, classID = C_Item.GetItemInfoInstant(id)
				if classID == 0 then
					found[id] = true
					table.insert(list, id)
				end
			end
		end
	end
	return list
end

function M:PickerList()
	local filter = E:FoldText(self.picker.search:GetText())
	local list, seen = {}, {}
	local function Add(id)
		if seen[id] then return end
		seen[id] = true
		local name = ItemName(id)
		if not name and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
		name = name or ("item:" .. id)
		if filter == "" or E:FoldText(name):find(filter, 1, true) then
			table.insert(list, { id = id, name = name, picked = self.db.items[id] ~= nil })
		end
	end
	for id in pairs(self.db.items) do Add(id) end
	for _, id in ipairs(BagConsumables()) do Add(id) end
	table.sort(list, function(a, b)
		if a.picked ~= b.picked then return a.picked end
		return a.name < b.name
	end)
	return list
end

local ROW_HEIGHT = 20

function M:RefreshPicker()
	local picker = self.picker
	if not picker or not picker:IsShown() then return end
	local list = self:PickerList()
	local content = picker.content
	content:SetHeight(math.max(#list * ROW_HEIGHT, 1))
	for index, item in ipairs(list) do
		local row = picker.rows[index]
		if not row then
			row = CreateFrame("Button", nil, content)
			row:SetHeight(ROW_HEIGHT)
			row:SetPoint("TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
			row:SetPoint("RIGHT", content, "RIGHT", 0, 0)
			row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
			row.bg = row:CreateTexture(nil, "BACKGROUND")
			row.bg:SetAllPoints()
			local hover = row:CreateTexture(nil, "HIGHLIGHT")
			hover:SetAllPoints()
			hover:SetColorTexture(1, 1, 1, E.tokens.hover.row)
			row.icon = row:CreateTexture(nil, "ARTWORK")
			row.icon:SetSize(ROW_HEIGHT - 4, ROW_HEIGHT - 4)
			row.icon:SetPoint("LEFT", 4, 0)
			E:TrimIcon(row.icon)
			row.name = E:CreateText(row, E.tokens.size.label, "LEFT")
			row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
			row.name:SetPoint("RIGHT", row, "RIGHT", -96, 0)
			row.kind = E:CreateText(row, E.tokens.size.small, "RIGHT")
			row.kind:SetPoint("RIGHT", -6, 0)
			row:SetScript("OnClick", function(r, button)
				local id = r.itemID
				if button == "RightButton" then
					local data = M.db.items[id]
					if data then
						local kindIndex = tIndexOf(KINDS, data.kind) or 1
						data.kind = KINDS[kindIndex % #KINDS + 1]
					end
				elseif M.db.items[id] then
					M.db.items[id] = nil
				else
					M.db.items[id] = { kind = GuessKind(id) }
				end
				M:RefreshPicker()
				M:RequestUpdate()
			end)
			row:SetScript("OnEnter", function(r)
				E.UIKit.AnchorTooltip(r)
				GameTooltip:SetItemByID(r.itemID)
				GameTooltip:AddLine(" ")
				E:TooltipHint(GameTooltip, { L["Left-click"], L["keep up / stop"] }, { L["Right-click"], L["what to check"] })
				GameTooltip:Show()
			end)
			row:SetScript("OnLeave", GameTooltip_Hide)
			picker.rows[index] = row
		end
		row.itemID = item.id
		row.icon:SetTexture(ItemIcon(item.id) or 134400)
		row.name:SetText(item.name)
		local data = self.db.items[item.id]
		if data then
			local r, g, b = unpack(E.media.accentColor)
			row.bg:SetColorTexture(r, g, b, 0.25)
			row.name:SetTextColor(1, 1, 1)
			row.kind:SetText(KIND_NAMES[data.kind] or data.kind)
			row.kind:SetTextColor(unpack(E.media.text.secondary))
		else
			row.bg:SetColorTexture(1, 1, 1, index % 2 == 0 and E.tokens.hover.row / 2 or 0)
			row.name:SetTextColor(unpack(E.media.text.secondary))
			row.kind:SetText("")
		end
		row:Show()
	end
	for index = #list + 1, #picker.rows do picker.rows[index]:Hide() end
	picker.empty:SetShown(#list == 0)
	if picker.area then picker.area:Update() end
end

-- Enter in the search box adds an item by ID, link or (cached) name.
local function AddFromText(text)
	local id = tonumber(text) or tonumber(text:match("item:(%d+)"))
	if not id and C_Item.GetItemInfo then
		local _, link = C_Item.GetItemInfo(text)
		id = link and tonumber(link:match("item:(%d+)"))
	end
	if not id or not C_Item.GetItemInfoInstant(id) then return false end
	if not M.db.items[id] then M.db.items[id] = { kind = GuessKind(id) } end
	return true
end

function M:ShowPicker()
	local picker = self.picker
	if not picker then
		-- The shared tool window shell and kit parts (E.UIKit).
		picker = E.UIKit.CreateToolWindow("EldoUI_ReminderPicker", { title = L["Consumables to keep up"], width = 380,
			height = 440, strata = "DIALOG" })

		local search = E.UIKit.Input(picker, { height = 20, hint = L["Search / ID"] })
		search:SetPoint("TOPLEFT", 8, -36)
		search:SetPoint("TOPRIGHT", -8, -36)
		search:HookScript("OnTextChanged", function() M:RefreshPicker() end)
		search:SetScript("OnEnterPressed", function(box)
			if AddFromText(box:GetText()) then box:SetText("") end
			box:ClearFocus()
			M:RefreshPicker()
			M:RequestUpdate()
		end)
		picker.search = search

		local area = E.UIKit.ScrollArea(picker)
		area:SetPoint("TOPLEFT", 8, -64)
		area:SetPoint("BOTTOMRIGHT", -8, 40)
		picker.area = area
		picker.content = area.child
		picker.rows = {}

		picker.empty = E.UIKit.Text(picker, E.tokens.size.label, "CENTER", "secondary")
		picker.empty:SetPoint("CENTER", area, "CENTER")
		picker.empty:SetText(L["No consumables in your bags. Type an item ID and press Enter."])

		local footer = E.UIKit.Text(picker, E.tokens.size.small, "LEFT", "secondary")
		footer:SetPoint("BOTTOMLEFT", 8, 8)
		footer:SetPoint("BOTTOMRIGHT", -8, 8)
		footer:SetWordWrap(true)
		footer:SetText(L["Left-click to keep an item up. Right-click to change what is checked: its buff, Well Fed, or the main/off-hand weapon enchant."])

		picker:HookScript("OnShow", function() M:RefreshPicker() end)
		picker:RegisterEvent("BAG_UPDATE_DELAYED")
		picker:RegisterEvent("GET_ITEM_INFO_RECEIVED")
		picker:SetScript("OnEvent", function()
			if picker:IsShown() then M:RefreshPicker() end
		end)
		self.picker = picker
	end
	picker:Show()
	self:RefreshPicker()
end

---------------------------------------------------------------------------
-- Style presets
---------------------------------------------------------------------------
E:RegisterStyles("Reminders", {
	{ key = "Classic", title = "Classic", desc = "48 px icons with names and a pulse on missing buffs.",
		settings = { iconSize = 48, spacing = 6, consumableScale = 0.8, showLabel = true, highlight = "pulse", alpha = 1 } },
	{ key = "Minimal", title = "Minimal", desc = "Small 32 px icons, no names, no highlight.",
		settings = { iconSize = 32, spacing = 4, consumableScale = 0.8, showLabel = false, highlight = "none", alpha = 1 } },
	{ key = "Large", title = "Large", desc = "Big 64 px icons with names, hard to miss.",
		settings = { iconSize = 64, spacing = 8, consumableScale = 0.75, showLabel = true, highlight = "pulse", alpha = 1 } },
	{ key = "Compact", title = "Compact", desc = "Tight 36 px icons, consumables the same size, names off.",
		settings = { iconSize = 36, spacing = 2, consumableScale = 1, showLabel = false, highlight = "pulse", alpha = 1 } },
	{ key = "Ghost", title = "Ghost", desc = "Half-see-through 44 px icons without a highlight.",
		settings = { iconSize = 44, spacing = 6, consumableScale = 0.8, showLabel = true, highlight = "none", alpha = 0.6 } },
	{ key = "Glow", title = "Glow", desc = "48 px icons; missing ones glow in the Reminders glow style (Glows page).",
		settings = { iconSize = 48, spacing = 6, consumableScale = 0.8, showLabel = true, highlight = "glow", alpha = 1 } },
})

---------------------------------------------------------------------------
-- Options
---------------------------------------------------------------------------
local function PlayerClass()
	local _, class = UnitClass("player")
	return class
end

-- A switch for a group of spells has a plain label.
local SLOT_LABELS = {
	MAGE_ARMOR = E.Key("Mage armor"),
	PALADIN_BLESSING = "Blessing", PALADIN_AURA = E.Key("Paladin aura"), PALADIN_SEAL = E.Key("Seal"),
	WARLOCK_ARMOR = E.Key("Demon Skin / Armor"), HUNTER_ASPECT = E.Key("Aspect"),
	SHAMAN_SHIELD = "Shield", SHAMAN_IMBUE = E.Key("Weapon imbue (main hand)"), SHAMAN_IMBUE_OFF = E.Key("Weapon imbue (off hand)"),
	ROGUE_POISON = E.Key("Poison (main hand)"), ROGUE_POISON_OFF = E.Key("Poison (off hand)"),
	WARRIOR_SHIELD = E.Key("Shield (tanks)"),
}
-- A switch for one spell shows the spell as the game names it; the English
-- name stands in until the game has it.
local SLOT_SPELLS = {
	MAGE_INT = "Arcane Intellect",
	PRIEST_FORT = "Power Word: Fortitude", PRIEST_INNER = "Inner Fire",
	PRIEST_SHADOWPROT = "Shadow Protection", PRIEST_SPIRIT = "Divine Spirit",
	DRUID_MOTW = "Mark of the Wild", DRUID_THORNS = "Thorns", DRUID_OMEN = "Omen of Clarity",
	PRIEST_FEARWARD = "Fear Ward", PRIEST_SHADOWGUARD = "Shadowguard", PRIEST_TOUCH = "Touch of Weakness",
	PALADIN_RF = "Righteous Fury", HUNTER_TRUESHOT = "Trueshot Aura",
	WARRIOR_SHOUT = "Battle Shout", WARRIOR_DEFENSIVE = "Defensive Stance", DRUID_BEAR = "Bear Form",
}

-- The game's name of a slot's first spell.
local function SlotSpellName(slot)
	local first = slot.spells and slot.spells[1]
	local id = type(first) == "table" and first[1]
	return id and SpellName(id) or nil
end
M.SlotSpellName = SlotSpellName

-- The English title of a slot's switch (the class bar shows the same).
function M.SlotTitle(slot)
	return SLOT_SPELLS[slot.key] or SLOT_LABELS[slot.key] or slot.key
end

-- The help line of a class buff switch.
local function SlotDesc(slot)
	if slot.poison then
		return E.Key("From level 20, once you know a poison: a reminder when this hand has no poison or it runs low (the off hand only while it holds a weapon). Right-click the icon to pick the poison; a click puts it on.")
	elseif slot.weapon then
		return E.Key("Remind me when this hand has no weapon imbue or it is running out (the off hand only while it holds a weapon). Right-click the icon to pick the imbue and rank.")
	elseif slot.form then
		return E.Key("For tanks (the role you picked in setup): remind me when you know this stance or form and are not in it. A click takes it.")
	elseif slot.shield then
		return E.Key("For tanks (the role you picked in setup): remind me when your off hand holds no shield.")
	elseif slot.missingOnly then
		return E.Key("Remind me when no seal is on you, out of combat, so you start a fight with one. A seal lasts only seconds, so it never shows as running out. Off by default.")
	elseif slot.role == "tank" then
		return E.Key("For tanks (the role you picked in setup): remind me when this buff is missing, running out or a higher rank is known.")
	elseif slot.default == false and slot.group then
		return E.Key("Remind me when this buff is missing, running out or a higher rank is known, on you and, with Group members missing it, in your group. Off by default.")
	elseif slot.default == false then
		return E.Key("Shown once you know it: remind me when this buff is missing, running out or a higher rank is known. Off by default.")
	end
	return E.Key("Remind me when this buff is missing, running out or a higher rank is known.")
end

local function NotPetClass()
	local class = PlayerClass()
	return class ~= "HUNTER" and class ~= "WARLOCK"
end

-- "Remove" list: the custom spells with their names.
local function CustomValues()
	local values = { [""] = "(pick one to remove)" }
	for id in pairs(M.db.customSpells) do
		local name = SpellName(id)
		values[tostring(id)] = ("%s (%d)"):format(name or "?", id)
	end
	return values
end

M.options = {
	{ type = "tab", label = "General" },
	{ type = "header", label = "What to remind" },
	{ type = "toggle", key = "buffs", label = "Class buffs", desc = "Your own class buffs: missing or running out." },
	{ type = "toggle", key = "rank", label = "Higher rank known", desc = "Show when the buff on you is a lower rank than one you know. Out of combat only." },
	{ type = "toggle", key = "group", label = "Group members missing it", desc = "For group buffs (Fortitude, Intellect, Mark of the Wild), count group members without it, when the game lets addons read their auras." },
	{ type = "toggle", key = "askBuffs", label = "Buffs your group could give you", desc = "A yellow note when a priest, mage, druid or paladin is in your group and you lack their buff. Information only. Off by default." },
	{ type = "toggle", key = "tracking", label = "Gathering tracking", desc = "Remind you to turn on Find Herbs or Find Minerals when you know one." },
	{ type = "toggle", key = "consumables", label = "Consumables", desc = "The elixirs, flasks, food and weapon enchants you picked on the Consumables tab." },
	{ type = "toggle", key = "xpFood", label = "XP food", desc = "While leveling, out of combat: a note when no XP bonus is running, such as the Well Fed XP Boost from XP food." },
	{ type = "toggle", key = "healthstone", label = "Healthstone", desc = "In dungeons and raids with a warlock in the group who can make one (or when you can): a note when you carry no Healthstone." },
	{ type = "toggle", key = "durability", label = "Low durability", desc = "An anvil when your most worn item reaches Worn gear on the General page (yellow), red once it is low, so you repair in time. Shown in rest areas too." },
	{ type = "toggle", key = "readyCheckMana", label = "Low mana on a ready check", desc = "A pulsing note above the reminders during a ready check when your own mana is low. Out of combat only.",
		cog = {
			{ type = "range", key = "readyCheckPercent", label = "Low mana below", unit = "%", min = 10, max = 90, step = 5, desc = "The note shows below this much mana." },
		} },
	{ type = "header", label = "When" },
	{ type = "range", key = "threshold", label = "Buff running out", unit = "s", min = 0, max = 600, step = 15, desc = "A class buff with less time left than this shows as running out (yellow)." },
	{ type = "range", key = "consumableMinutes", label = "Consumable running out", unit = "min", min = 0, max = 30, step = 1, desc = "A consumable buff or weapon enchant with less time left than this shows (yellow)." },
	{ type = "toggle", key = "inCombat", label = "Also in combat", desc = "Keep showing the reminders from before the fight while in combat, frozen (the game does not let addons read auras in combat, so they update when combat ends). Off: reminders hide in combat." },
	{ type = "toggle", key = "showWorld", label = "Open world", desc = "Show reminders in the open world." },
	{ type = "toggle", key = "showDungeon", label = "Dungeons", desc = "Show reminders in dungeons." },
	{ type = "toggle", key = "showRaid", label = "Raids", desc = "Show reminders in raids." },
	{ type = "toggle", key = "showPvP", label = "Battlegrounds", desc = "Show reminders in battlegrounds and arenas." },
	{ type = "toggle", key = "showResting", label = "Rest areas", desc = "Show reminders in inns and cities. The durability warning shows there either way." },
	{ type = "media", key = "sound", label = "Sound", mediaKind = "sound", none = true, desc = "A sound when a new reminder appears (at most every 3 seconds)." },
	{ type = "header", label = "Click to buff" },
	{ type = "toggle", key = "clickCast", label = "Click an icon to cast or use it",
		desc = "Off by default. Clicking a reminder casts the missing buff (on you or the first member without it) or uses the consumable: one cast per click, never by itself." },
	{ type = "execute", label = "Preview", desc = "Show sample reminders for 15 seconds, to check size and position.", func = function() M:TogglePreview() end },
	{ type = "execute", label = "Move", desc = "Unlock EldoUI frames to drag the reminders (mover \"Reminders\").", func = function() E:MoveFrame("EldoUI_Reminders") end },

	{ type = "tab", label = "Look" },
	{ type = "header", label = "Icons" },
	{ type = "range", unit = "px", key = "iconSize", label = "Icon size", min = 24, max = 64, step = 2, desc = "Size of the buff icons in pixels." },
	{ type = "range", percent = true, key = "consumableScale", label = "Consumable scale", min = 0.5, max = 1, step = 0.05, desc = "Consumable icons relative to the buff icons." },
	{ type = "range", unit = "px", key = "spacing", label = "Spacing", min = 0, max = 16, step = 1, desc = "Gap between icons." },
	{ type = "range", percent = true, key = "alpha", label = "Opacity", min = 0.3, max = 1, step = 0.05, desc = "Opacity of the whole reminder block." },
	{ type = "toggle", key = "showLabel", label = "Show names", desc = "The buff or item name under each icon." },
	{ type = "select", key = "highlight", label = "Missing reminders", values = { pulse = "Pulse", glow = "Glow", none = "No highlight" },
		desc = "How a missing (red) reminder draws the eye. Glow uses the Reminders row on the Glows page." },

	{ type = "tab", label = "Class buffs" },
	{ type = "header", label = "Your class" },
	{ type = "description", label = "Switch your class buffs on or off and pick the spell and rank each one asks for. Each shows once you know the spell." },
}
-- Click to buff casts on the player's own click: listed for the setup's
-- Convenience step and the Conveniences page (Core/Conveniences.lua), off
-- until ticked and never recommended.
E:RegisterConvenience({ id = "reminderClicks", module = "Reminders", setting = "clickCast", order = 170,
	label = "Click an icon to cast or use it",
	desc = "Acts for you: a click on a reminder casts the missing buff or uses the consumable, one cast per click and never by itself." })
-- The Spell row of a slot: Automatic and each spell the player knows.
local function LineValues(slot)
	return function()
		local values = { [""] = L["Automatic (the one you cast last)"] }
		for _, ranks in ipairs(KnownLines(slot)) do
			values[tostring(ranks[1])] = SpellName(ranks[1]) or tostring(ranks[1])
		end
		return values
	end
end

local function LineOrder(slot)
	return function()
		local order = { "" }
		for _, ranks in ipairs(KnownLines(slot)) do order[#order + 1] = tostring(ranks[1]) end
		return order
	end
end

-- The line the Rank row is for: the picked spell, or the only one known.
local function RankLine(slot)
	local known = KnownLines(slot)
	if #known == 1 then return known[1] end
	local picked = LineByKey(slot, M.db.buffLines[slot.key])
	if picked and HighestKnown(picked) then return picked end
end

-- The Rank row: the highest known, then each known rank, highest first.
local function RankValues(slot)
	return function()
		local values = { [""] = L["Highest known rank"] }
		local line = RankLine(slot)
		local list = line and KnownRanks(line) or {}
		for index = 1, #list - 1 do values[tostring(list[index][2])] = L["Rank %d"]:format(list[index][1]) end
		return values
	end
end

local function RankOrder(slot)
	return function()
		local order = { "" }
		local line = RankLine(slot)
		local list = line and KnownRanks(line) or {}
		for index = #list - 1, 1, -1 do order[#order + 1] = tostring(list[index][2]) end
		return order
	end
end

for class, slots in pairs(CLASS_BUFFS) do
	for _, slot in ipairs(slots) do
		local key = slot.key
		local function OtherClass() return PlayerClass() ~= class end
		table.insert(M.options, {
			type = "toggle", label = SLOT_SPELLS[key] or SLOT_LABELS[key] or key,
			gameName = SLOT_SPELLS[key] and function() return SlotSpellName(slot) end or nil,
			desc = SlotDesc(slot),
			hidden = OtherClass,
			key = "classBuffs." .. key,
		})
		if Pickable(slot) then
			-- Shown only when there is something to pick.
			table.insert(M.options, {
				type = "select", label = slot.weapon and E.Key("Imbue") or E.Key("Spell"), values = LineValues(slot), order = LineOrder(slot),
				desc = slot.weapon and E.Key("The imbue this hand's reminder asks for and a click casts. Automatic: the one you cast last. Any imbue on the hand meets it.")
					or E.Key("The spell this reminder asks for and a click casts; only it (or its group version) meets the reminder. Automatic: the one you cast last."),
				hidden = function() return OtherClass() or #KnownLines(slot) < 2 end,
				dependsOn = "classBuffs." .. key, key = "buffLines." .. key,
			})
			table.insert(M.options, {
				type = "select", label = "Rank", values = RankValues(slot), order = RankOrder(slot),
				desc = "The rank a click casts: the highest you know, or a lower one you keep on purpose (to save mana, for example).",
				hidden = function()
					local line = not OtherClass() and RankLine(slot)
					return not (line and #KnownRanks(line) > 1)
				end,
				dependsOn = "classBuffs." .. key, key = "buffRanks." .. key,
			})
		end
	end
end

local function NotShaman() return PlayerClass() ~= "SHAMAN" end
local function AlertsOff(key) return function() return NotShaman() or not M.db.alerts[key] end end
for _, row in ipairs({
	{ type = "header", label = "Shaman alerts", hidden = NotShaman },
	{ type = "toggle", key = "alerts.shield", label = "Shield alert", hidden = NotShaman,
		desc = "An alert card when your shield is running out or gone. The game doesn't tell addons about your auras in combat, so this one waits until the fight ends." },
	{ type = "toggle", key = "alerts.imbue", label = "Weapon imbue alert", hidden = NotShaman,
		desc = "A note when a weapon imbue is running out or gone: in the Combat Text notification lane in combat, an alert card out of combat." },
	{ type = "toggle", key = "alerts.shieldSound", label = "Sound when the shield drops", hidden = NotShaman,
		desc = "The game plays this sound the moment your shield leaves you, in combat too. Off by default." },
	{ type = "media", mediaKind = "sound", key = "alerts.sound", label = "Shield sound", hidden = AlertsOff("shieldSound"),
		desc = "The sound for a dropped shield." },
	{ type = "description", hidden = function() return AlertsOff("shieldSound")() or not M.shieldSoundStatus end, tone = "warning",
		label = function() return M.shieldSoundStatus or "" end },
}) do table.insert(M.options, row) end

local DEMON_LABELS = { IMP = "Imp", VOIDWALKER = "Voidwalker", SUCCUBUS = "Succubus", INCUBUS = "Incubus", FELHUNTER = "Felhunter" }

local MORE_OPTIONS = {
	{ type = "header", label = "Pet", hidden = NotPetClass },
	{ type = "toggle", key = "pets", label = "No pet out", hidden = NotPetClass,
		desc = "Hunters: no pet (Call Pet on click). Warlocks: no demon, or a demon you did not allow below." },
	{ type = "toggle", key = "petPassive", label = "Pet on passive", hidden = NotPetClass, desc = "A note while your pet is set to passive." },
}
local function NotWarlock() return PlayerClass() ~= "WARLOCK" end
local function NoSoulstone() return NotWarlock() or not M:StoneSpell("soulstone") end
for _, row in ipairs({
	{ type = "header", label = "Stones", hidden = NotWarlock },
	{ type = "toggle", key = "stones", label = "Make stones", hidden = NotWarlock,
		desc = "Out of combat, when you know how to make a Healthstone, a Soulstone or the stone you pick below and carry none of it. A click makes it (it takes a Soul Shard)." },
	{ type = "select", key = "stonePick", label = "Spellstone or Firestone", dependsOn = "stones", hidden = NotWarlock,
		values = { [""] = "Neither", spellstone = "Spellstone", firestone = "Firestone" },
		desc = "The one you keep up. Right-click its reminder to change it." },
	{ type = "toggle", key = "soulstoneGroup", label = "Soulstone in a group", hidden = NoSoulstone,
		desc = "In dungeons and raids, out of combat, while nobody in the group has a Soulstone and yours is ready: a click puts it on the group's healer." },
	{ type = "toggle", key = "soulstoneSolo", label = "Soulstone on yourself", hidden = NoSoulstone,
		desc = "When you play alone: a reminder while you have no Soulstone on you. Off by default." },
}) do table.insert(MORE_OPTIONS, row) end
for _, demon in ipairs(DEMONS) do
	table.insert(MORE_OPTIONS, { type = "toggle", key = "demons." .. demon.key,
		label = DEMON_LABELS[demon.key] or demon.key,
		desc = "Allow this demon. With it off, having it out counts as the wrong demon; the first allowed demon is the one a click summons.",
		hidden = function() return PlayerClass() ~= "WARLOCK" or not Known(demon.spell) end })
end
table.insert(MORE_OPTIONS, { type = "header", label = "Your own spells" })
table.insert(MORE_OPTIONS, { type = "description", label = "Any buff by spell ID: the reminder shows while no rank of it is on you. A tooltip addon or database site shows spell IDs." })
table.insert(MORE_OPTIONS, { type = "input", key = "customAdd", label = "Add a spell ID", desc = "Type a spell ID and press Enter." })
table.insert(MORE_OPTIONS, { type = "select", key = "customRemove", label = "Remove", values = CustomValues,
	desc = "Pick one of your spells to stop reminding about it.", hidden = function() return next(M.db.customSpells) == nil end })
for _, option in ipairs(MORE_OPTIONS) do table.insert(M.options, option) end

table.insert(M.options, { type = "tab", label = "Consumables" })
table.insert(M.options, { type = "header", label = "Consumables" })
table.insert(M.options, { type = "description", label = "Nothing is picked by default. Choose the elixirs, flasks, food and weapon oils or stones you want to keep up, from your bags or by item ID." })
table.insert(M.options, { type = "toggle", key = "showCount", label = "Item count", desc = "How many of the item you carry, in the corner of its icon." })
table.insert(M.options, { type = "toggle", key = "remindWithoutItem", label = "Remind without the item", desc = "Show a consumable reminder (grayed) even when you carry none of it. Off: only when you have one to use." })
table.insert(M.options, { type = "execute", label = "Choose consumables", desc = "Open the list of consumables in your bags, with a search box.", func = function() M:ShowPicker() end })
table.insert(M.options, { type = "execute", label = "Clear all", desc = "Stop watching every consumable.", confirm = true, func = function() wipe(M.db.items); M:RequestUpdate(); M:RefreshPicker() end })

---------------------------------------------------------------------------
-- Tour help: the first reminder icon on screen
---------------------------------------------------------------------------
local function FirstIcon()
	for _, pool in ipairs({ M.buffIcons or {}, M.itemIcons or {} }) do
		local icon = pool[1]
		if icon and icon.entry and icon:IsVisible() then return icon end
	end
end

E.Tour:Register("reminders:first", {
	form = "spot", word = "reminders",
	offer = function(_, force)
		return E.Tour:Spot("reminders:first", {
			-- Offered again when the icons next come up, so it never waits in the queue.
			force = force, now = true, target = FirstIcon,
			title = L["Reminders"],
			text = L["These icons show what you are missing or about to lose, such as a class buff, your pet or a consumable you keep up. Each one goes away once it is done. Point at an icon to see why it shows; /eui reminders chooses what is checked."],
		})
	end,
	replay = function(def) def.offer(def, true) end,
})

-- Explained once an icon has stayed a moment, not for one that only flickers.
local tourHelpPending = false
function M:OfferTourHelp()
	if tourHelpPending or E.Tour:Seen("reminders:first") then return end
	tourHelpPending = true
	C_Timer.After(2, function()
		tourHelpPending = false
		if FirstIcon() and not M.preview then E.Tour:Offer("reminders:first") end
	end)
end
