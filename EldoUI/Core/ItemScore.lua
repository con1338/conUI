-- EldoUI item scoring engine (E.ItemScore): one place that says how good an
-- item is for you and whether it beats what you wear. Bag, merchant, roll
-- and quest-reward arrows (Upgrades), the upgrade line in tooltips and the
-- Loot Guide all ask this engine, so they always agree. It lives in the core
-- so it keeps working when the Upgrades module is off.
--
-- Everything comes from data the game hands out: item stats from
-- C_Item.GetItemStats, what you wear from GetInventoryItemLink, "can I use
-- it" from the red text Blizzard puts in the item's own tooltip, rating
-- conversion from GetCombatRatingBonusForCombatRatingValue. No combat data
-- is read and nothing here acts for the player.
--
-- Scales. A scale gives each stat a weight; an item's score is the sum of
-- stat x weight. Scales are kept in the profile (E.db.itemScore):
--   * starter class scales (Data/StatWeights.lua, plain model): the ones
--     Upgrades has always used. Each stat counts per point as listed.
--   * spec scales "SPEC_<SPEC>" (spec model), one per talent spec. Ratings are
--     turned into percent by the game first; attack power uses the higher of
--     the melee and ranged weights; feral attack power counts only for Cat
--     and Bear; spell power that is also healing is counted once; haste and
--     expertise fall back to part of the crit and hit weights; weapon DPS is
--     weighted per slot (the off hand at half). "Equip:" lines the stat API
--     leaves out are read with the client's own ITEM_MOD_* strings.
--     WoW: Forever gear gives hit, crit, haste, expertise, dodge, parry and
--     block as a percent ("Improves your chance to hit by 1.0%"). Those
--     lines are read with the client's TOOLTIP_ITEM_STAT_* strings and
--     count at their percent, with no rating conversion.
--   * custom scales the player made, imported or got from a stat priority.
-- Editing a starter or spec scale stores a copy; resetting removes it.
--
-- Public API (E.ItemScore):
--   :Rate(link[, spec[, tooltip]]) -> result or nil
--       spec nil = this class's active scale (what the arrows use);
--       "player" = the player's spec; a spec key ("ROGUE_COMBAT") or a scale
--       key. result = { score, base, delta, percent, dps, upgrade, usable,
--       worn, slot, scale (name), scaleKey, spec, model, rater, bis }.
--       percent is nil when the slot is empty; dps/bis come from a rater.
--   :RegisterRater(key, { title, desc, rate = function(rater, link, spec, result) end })
--       a rating mode ("sim" by EldoUI_LootSim). rate returns fields that
--       replace the weights result's (dps, upgrade, percent ...) or nil to
--       keep it. "weights" is built in.
--   :GetRating() / :SetRating(key) / :Raters()   rating mode, per character
--   :SpecWeights(spec), :SpecInfo(spec), :Specs([class]), :PlayerSpec(),
--   :SetPlayerSpec(spec)
--   :DefaultPriority(spec), :Priority(spec), :WeightsFromPriority(order),
--   :SetPriority(spec, order[, moved])  (order nil = back to the default)
--   :Bump()   scores changed: drop caches, redraw every consumer
--   :RegisterStatsProvider(fn(itemID, link) -> stats)  e.g. EldoUI_LootData
--   :RawStats(link)   the item's own stats by ITEM_MOD_* key (the simulator)
--   scale management: :GetScale, :ActiveScaleKey, :ActiveScale, :SelectScale,
--   :SetWeight, :NewScale, :RenameScale, :DeleteScale, :ResetScale,
--   :ScaleList, :ScaleString, :PawnString, :ParseScaleString, :ParsePawnString
-- E:RegisterUpgradeRefresh(fn): fn() runs whenever scores may have changed.
local _, E = ...

local ItemScore = {}
E.ItemScore = ItemScore

local W = E.StatWeights
local STEP = 0.8 -- one place lower in a stat priority keeps 80 % of the value

E.defaults.itemScore = {
	gems = true,        -- socketed gems count towards an item's score
	enchants = false,   -- the enchant counts too (off: items compared bare)
	scales = {},        -- key -> { name, class, custom, model, spec, weights }
	activeByClass = {}, -- class -> scale key
}

---------------------------------------------------------------------------
-- Stats: our key, the game's label, the GetItemStats keys it reads.
-- cr: the game's combat-rating id the spec model converts it with.
-- specOnly: only the spec model reads it (plain scales never had it).
---------------------------------------------------------------------------
local STATS = {
	{ key = "Strength", gs = "ITEM_MOD_STRENGTH_SHORT", read = { "ITEM_MOD_STRENGTH_SHORT" } },
	{ key = "Agility", gs = "ITEM_MOD_AGILITY_SHORT", read = { "ITEM_MOD_AGILITY_SHORT" } },
	{ key = "Stamina", gs = "ITEM_MOD_STAMINA_SHORT", read = { "ITEM_MOD_STAMINA_SHORT" } },
	{ key = "Intellect", gs = "ITEM_MOD_INTELLECT_SHORT", read = { "ITEM_MOD_INTELLECT_SHORT" } },
	{ key = "Spirit", gs = "ITEM_MOD_SPIRIT_SHORT", read = { "ITEM_MOD_SPIRIT_SHORT" } },
	{ key = "Armor", gs = "RESISTANCE0_NAME", read = { "RESISTANCE0_NAME" }, max = 0.5, step = 0.01 },
	{ key = "AttackPower", gs = "ITEM_MOD_ATTACK_POWER_SHORT", read = { "ITEM_MOD_ATTACK_POWER_SHORT", "ITEM_MOD_MELEE_ATTACK_POWER_SHORT" } },
	{ key = "RangedAttackPower", gs = "ITEM_MOD_RANGED_ATTACK_POWER_SHORT", read = { "ITEM_MOD_RANGED_ATTACK_POWER_SHORT" } },
	{ key = "SpellPower", gs = "ITEM_MOD_SPELL_POWER_SHORT", read = { "ITEM_MOD_SPELL_POWER_SHORT", "ITEM_MOD_SPELL_DAMAGE_DONE_SHORT" } },
	{ key = "Healing", gs = "ITEM_MOD_SPELL_HEALING_DONE_SHORT", read = { "ITEM_MOD_SPELL_HEALING_DONE_SHORT" } },
	{ key = "Crit", gs = "ITEM_MOD_CRIT_RATING_SHORT", read = { "ITEM_MOD_CRIT_RATING_SHORT", "ITEM_MOD_CRIT_MELEE_RATING_SHORT", "ITEM_MOD_CRIT_RANGED_RATING_SHORT" }, rating = true },
	{ key = "SpellCrit", gs = "ITEM_MOD_CRIT_SPELL_RATING_SHORT", read = { "ITEM_MOD_CRIT_SPELL_RATING_SHORT" }, rating = true },
	{ key = "Hit", gs = "ITEM_MOD_HIT_RATING_SHORT", read = { "ITEM_MOD_HIT_RATING_SHORT", "ITEM_MOD_HIT_MELEE_RATING_SHORT", "ITEM_MOD_HIT_RANGED_RATING_SHORT" }, rating = true },
	{ key = "SpellHit", gs = "ITEM_MOD_HIT_SPELL_RATING_SHORT", read = { "ITEM_MOD_HIT_SPELL_RATING_SHORT" }, rating = true },
	{ key = "Haste", gs = "ITEM_MOD_HASTE_RATING_SHORT", read = { "ITEM_MOD_HASTE_RATING_SHORT", "ITEM_MOD_HASTE_SPELL_RATING_SHORT" }, rating = true },
	{ key = "Expertise", gs = "ITEM_MOD_EXPERTISE_RATING_SHORT", read = { "ITEM_MOD_EXPERTISE_RATING_SHORT" }, rating = true },
	{ key = "Mastery", gs = "ITEM_MOD_MASTERY_RATING_SHORT", read = { "ITEM_MOD_MASTERY_RATING_SHORT" }, rating = true },
	{ key = "Versatility", gs = "ITEM_MOD_VERSATILITY", read = { "ITEM_MOD_VERSATILITY" }, rating = true },
	{ key = "Mp5", gs = "ITEM_MOD_MANA_REGENERATION_SHORT", read = { "ITEM_MOD_MANA_REGENERATION_SHORT", "ITEM_MOD_POWER_REGEN0_SHORT" } },
	{ key = "Hp5", gs = "ITEM_MOD_HEALTH_REGEN_SHORT", read = { "ITEM_MOD_HEALTH_REGEN_SHORT", "ITEM_MOD_HEALTH_REGENERATION_SHORT" } },
	{ key = "Defense", gs = "ITEM_MOD_DEFENSE_SKILL_RATING_SHORT", read = { "ITEM_MOD_DEFENSE_SKILL_RATING_SHORT" }, rating = true },
	{ key = "Dodge", gs = "ITEM_MOD_DODGE_RATING_SHORT", read = { "ITEM_MOD_DODGE_RATING_SHORT" }, rating = true },
	{ key = "Parry", gs = "ITEM_MOD_PARRY_RATING_SHORT", read = { "ITEM_MOD_PARRY_RATING_SHORT" }, rating = true },
	{ key = "Block", gs = "ITEM_MOD_BLOCK_RATING_SHORT", read = { "ITEM_MOD_BLOCK_RATING_SHORT" }, rating = true },
	{ key = "BlockValue", gs = "ITEM_MOD_BLOCK_VALUE_SHORT", read = { "ITEM_MOD_BLOCK_VALUE_SHORT" } },
	{ key = "Dps", gs = "ITEM_MOD_DAMAGE_PER_SECOND_SHORT", read = { "ITEM_MOD_DAMAGE_PER_SECOND_SHORT" }, max = 10, step = 0.1 },
	{ key = "RangedDps", label = "Ranged weapon DPS", read = {}, max = 10, step = 0.1, specOnly = true },
	-- Resistances: the game's damage class numbers (2 Fire to 6 Arcane). No
	-- shipped scale weights them; a player sets them for a raid that needs it.
	{ key = "FireResistance", label = "Fire resistance", gs = "RESISTANCE2_NAME", read = { "RESISTANCE2_NAME", "ITEM_MOD_FIRE_RESISTANCE_SHORT" } },
	{ key = "NatureResistance", label = "Nature resistance", gs = "RESISTANCE3_NAME", read = { "RESISTANCE3_NAME", "ITEM_MOD_NATURE_RESISTANCE_SHORT" } },
	{ key = "FrostResistance", label = "Frost resistance", gs = "RESISTANCE4_NAME", read = { "RESISTANCE4_NAME", "ITEM_MOD_FROST_RESISTANCE_SHORT" } },
	{ key = "ShadowResistance", label = "Shadow resistance", gs = "RESISTANCE5_NAME", read = { "RESISTANCE5_NAME", "ITEM_MOD_SHADOW_RESISTANCE_SHORT" } },
	{ key = "ArcaneResistance", label = "Arcane resistance", gs = "RESISTANCE6_NAME", read = { "RESISTANCE6_NAME", "ITEM_MOD_ARCANE_RESISTANCE_SHORT" } },
	-- Empty sockets: points per socket of each color.
	{ key = "RedSocket", gs = "EMPTY_SOCKET_RED", read = { "EMPTY_SOCKET_RED" }, max = 40, step = 0.5, socket = true },
	{ key = "YellowSocket", gs = "EMPTY_SOCKET_YELLOW", read = { "EMPTY_SOCKET_YELLOW" }, max = 40, step = 0.5, socket = true },
	{ key = "BlueSocket", gs = "EMPTY_SOCKET_BLUE", read = { "EMPTY_SOCKET_BLUE" }, max = 40, step = 0.5, socket = true },
	{ key = "MetaSocket", gs = "EMPTY_SOCKET_META", read = { "EMPTY_SOCKET_META" }, max = 40, step = 0.5, socket = true },
	{ key = "PrismaticSocket", gs = "EMPTY_SOCKET_PRISMATIC", read = { "EMPTY_SOCKET_PRISMATIC" }, max = 40, step = 0.5, socket = true },
}
local STAT_BY_KEY = {}
for _, stat in ipairs(STATS) do STAT_BY_KEY[stat.key] = stat end
ItemScore.STATS, ItemScore.STAT_BY_KEY = STATS, STAT_BY_KEY

-- The game's own (localized) name for a stat, else our label or key.
-- A stat's name: the game's own name when it has one (then true as the
-- second value), else the English label.
function ItemScore.StatLabel(stat)
	if type(stat) == "string" then stat = STAT_BY_KEY[stat] end
	if not stat then return "?" end
	local text = stat.gs and _G[stat.gs]
	if type(text) == "string" and text ~= "" and not text:find("%%") then return text, true end
	return stat.label or stat.key
end
local StatLabel = ItemScore.StatLabel

---------------------------------------------------------------------------
-- Spec model: how each GetItemStats key counts. w = the weight it uses;
-- either = the higher of two weights (stats that help both kinds); cr =
-- combat-rating id(s) for the conversion to percent.
---------------------------------------------------------------------------
local SPEC_READ = {
	ITEM_MOD_STRENGTH_SHORT = { w = "Strength" },
	ITEM_MOD_AGILITY_SHORT = { w = "Agility" },
	ITEM_MOD_STAMINA_SHORT = { w = "Stamina" },
	ITEM_MOD_INTELLECT_SHORT = { w = "Intellect" },
	ITEM_MOD_SPIRIT_SHORT = { w = "Spirit" },
	RESISTANCE0_NAME = { w = "Armor" },
	ITEM_MOD_ATTACK_POWER_SHORT = { either = { "AttackPower", "RangedAttackPower" } },
	ITEM_MOD_MELEE_ATTACK_POWER_SHORT = { w = "AttackPower" },
	ITEM_MOD_RANGED_ATTACK_POWER_SHORT = { w = "RangedAttackPower" },
	ITEM_MOD_FERAL_ATTACK_POWER_SHORT = { w = "AttackPower", feral = true },
	ITEM_MOD_SPELL_POWER_SHORT = { either = { "SpellPower", "Healing" } },
	ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = { w = "SpellPower" },
	ITEM_MOD_SPELL_HEALING_DONE_SHORT = { w = "Healing", sameAs = "ITEM_MOD_SPELL_POWER_SHORT" },
	ITEM_MOD_CRIT_RATING_SHORT = { either = { "Crit", "SpellCrit" }, cr = { 9, 11 } },
	ITEM_MOD_CRIT_MELEE_RATING_SHORT = { w = "Crit", cr = 9 },
	ITEM_MOD_CRIT_RANGED_RATING_SHORT = { w = "Crit", cr = 10 },
	ITEM_MOD_CRIT_SPELL_RATING_SHORT = { w = "SpellCrit", cr = 11 },
	ITEM_MOD_HIT_RATING_SHORT = { either = { "Hit", "SpellHit" }, cr = { 6, 8 } },
	ITEM_MOD_HIT_MELEE_RATING_SHORT = { w = "Hit", cr = 6 },
	ITEM_MOD_HIT_RANGED_RATING_SHORT = { w = "Hit", cr = 7 },
	ITEM_MOD_HIT_SPELL_RATING_SHORT = { w = "SpellHit", cr = 8 },
	ITEM_MOD_HASTE_RATING_SHORT = { w = "Haste", cr = 18 },
	ITEM_MOD_HASTE_SPELL_RATING_SHORT = { w = "Haste", cr = 20 },
	ITEM_MOD_EXPERTISE_RATING_SHORT = { w = "Expertise", cr = 24 },
	ITEM_MOD_MASTERY_RATING_SHORT = { w = "Mastery", cr = 26 },
	ITEM_MOD_VERSATILITY = { w = "Versatility", cr = 29 },
	ITEM_MOD_MANA_REGENERATION_SHORT = { w = "Mp5" },
	ITEM_MOD_POWER_REGEN0_SHORT = { w = "Mp5" },
	ITEM_MOD_HEALTH_REGEN_SHORT = { w = "Hp5" },
	ITEM_MOD_HEALTH_REGENERATION_SHORT = { w = "Hp5" },
	ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = { w = "Defense", cr = 2 },
	ITEM_MOD_DODGE_RATING_SHORT = { w = "Dodge", cr = 3 },
	ITEM_MOD_PARRY_RATING_SHORT = { w = "Parry", cr = 4 },
	ITEM_MOD_BLOCK_RATING_SHORT = { w = "Block", cr = 5 },
	ITEM_MOD_BLOCK_VALUE_SHORT = { w = "BlockValue" },
	ITEM_MOD_DAMAGE_PER_SECOND_SHORT = { dps = true },
	-- Percent lines (read from the tooltip, see PERCENT_LINES): spec
	-- weights are per 1 %, so they need no conversion. Expertise weights are
	-- per point, at 0.25 % per point.
	PCT_HIT = { either = { "Hit", "SpellHit" } },
	PCT_CRIT = { either = { "Crit", "SpellCrit" } },
	PCT_SPELL_HIT = { w = "SpellHit" },
	PCT_SPELL_CRIT = { w = "SpellCrit" },
	PCT_HASTE = { w = "Haste" },
	PCT_EXPERTISE = { w = "Expertise", per = 4 },
	PCT_DODGE = { w = "Dodge" },
	PCT_PARRY = { w = "Parry" },
	PCT_BLOCK = { w = "Block" },
}
for _, stat in ipairs(STATS) do
	if stat.key:find("Resistance$") then
		for _, key in ipairs(stat.read) do SPEC_READ[key] = { w = stat.key } end
	end
end
-- A fixed order, so sums come out the same every session.
local SPEC_READ_ORDER = {}
for key in pairs(SPEC_READ) do SPEC_READ_ORDER[#SPEC_READ_ORDER + 1] = key end
table.sort(SPEC_READ_ORDER)

---------------------------------------------------------------------------
-- Scales: starter class scales plus one spec scale per spec
---------------------------------------------------------------------------
local STARTER = {}
for key, scale in pairs(W.starter) do STARTER[key] = scale end
local SPEC_BY_KEY, SPECS_BY_CLASS = {}, {}
for _, spec in ipairs(W.specs) do
	SPEC_BY_KEY[spec.key] = spec
	SPECS_BY_CLASS[spec.class] = SPECS_BY_CLASS[spec.class] or {}
	table.insert(SPECS_BY_CLASS[spec.class], spec)
	local className = spec.class:sub(1, 1) .. spec.class:sub(2):lower()
	STARTER["SPEC_" .. spec.key] = { name = ("%s: %s (spec)"):format(className, spec.name), class = spec.class,
		model = "spec", spec = spec.key, weights = spec.weights }
end
local CLASS_DEFAULT = W.classDefault

local playerClass
local function Class()
	if not playerClass then playerClass = select(2, UnitClass("player")) end
	return playerClass
end

local Safe = E.Plain

---------------------------------------------------------------------------
-- Caches. version bumps on every scale, gear or item-data change, so
-- consumers (Loot Guide rankings) can key their own caches on it.
---------------------------------------------------------------------------
ItemScore.version = 0
local statCache = {}       -- link -> GetItemStats table
local providerCache = {}   -- link -> stats from a provider (or false)
local equipLineCache = {}  -- link -> stats read from "Equip:" lines (or false)
local scoreCache = {}      -- scaleKey .. role -> { link -> score }
local partsCache = {}      -- scaleKey .. role -> { link -> { gems, enchant } }
local equippedCache = {}   -- scaleKey .. role -> { slot -> score }
local usableCache = {}     -- link -> true/false
local enchantCache = {}    -- link -> { [stat key] = amount } or false
local playerSpec           -- detected spec, until talents change

local function Invalidate()
	ItemScore.version = ItemScore.version + 1
	wipe(scoreCache)
	wipe(equippedCache)
	wipe(partsCache)
end

-- Item data arrives one item at a time (GET_ITEM_INFO_RECEIVED comes in
-- storms while windows ask for many items). So only the entries of the
-- item that arrived are dropped: every cached link is filed under the item
-- ids it names (the item and its socketed gems).
local linksById = {}   -- itemID -> { [link] = true }
local waitingIds = {}  -- itemID -> true: scored before its data was there

-- The item id and the gem ids of a link (item:id:enchant:gem1:gem2:gem3:gem4).
local function LinkIds(link)
	local fields = type(link) == "string" and link:match("item:([%-%d:]*)")
	if not fields then return {} end
	local ids, index = {}, 0
	for field in (fields .. ":"):gmatch("([^:]*):") do
		index = index + 1
		if index == 1 or (index >= 3 and index <= 6) then
			local id = tonumber(field)
			if id and id > 0 then ids[#ids + 1] = id end
		end
		if index >= 6 then break end
	end
	return ids
end

-- Every link the caches hold is counted once. Past LINK_CAP links (bags,
-- bank and a long open list fit well below it) every link cache starts
-- over and the version moves on, so a long session of lists and tooltips
-- keeps a bounded memory.
local LINK_CAP = 3000
local held = { links = {}, count = 0 }
local function Rollover()
	for _, cache in ipairs({ statCache, providerCache, equipLineCache, usableCache, enchantCache, linksById, held.links }) do
		wipe(cache)
	end
	held.count = 0
	Invalidate()
end
local function Hold(link)
	if held.links[link] then return end
	if held.count >= LINK_CAP then Rollover() end
	held.links[link] = true
	held.count = held.count + 1
end
ItemScore.LINK_CAP = LINK_CAP
function ItemScore:HeldLinks() return held.count end

local function Track(link)
	Hold(link)
	for _, id in ipairs(LinkIds(link)) do
		local links = linksById[id]
		if not links then
			links = {}
			linksById[id] = links
		end
		links[link] = true
	end
end

local function Wait(link)
	for _, id in ipairs(LinkIds(link)) do waitingIds[id] = true end
end

local function Bucket(cache, name)
	local bucket = cache[name]
	if not bucket then
		bucket = {}
		cache[name] = bucket
	end
	return bucket
end

---------------------------------------------------------------------------
-- Settings: E.db.itemScore, moved once from the Upgrades module
---------------------------------------------------------------------------
local bound -- the profile table the engine last saw

-- A stored scale that is only an untouched copy of its starter (Upgrades
-- used to copy the active starter into the profile on every login).
local function IsStarterCopy(key, scale)
	local starter = STARTER[key]
	if not starter or scale.custom then return false end
	return scale.name == starter.name and scale.class == starter.class
		and (scale.model or "plain") == (starter.model or "plain") and E.DeepEqual(scale.weights, starter.weights)
end

-- Upgrades' scales/activeByClass/gems/enchants -> E.db.itemScore. Runs
-- whenever the engine meets a profile, so an old Upgrades share string
-- imported later is moved too. Returns true when something moved.
local function Migrate(profile)
	local old = profile and profile.modules and profile.modules.Upgrades
	local settings = profile and profile.itemScore
	if type(old) ~= "table" or type(settings) ~= "table" then return false end
	local moved = false
	if type(old.scales) == "table" then
		for key, scale in pairs(old.scales) do
			if type(key) == "string" and type(scale) == "table" and type(scale.weights) == "table" then
				if IsStarterCopy(key, scale) then
					settings.scales[key] = nil
				else
					settings.scales[key] = scale
				end
			end
		end
		old.scales = nil
		moved = true
	end
	if type(old.activeByClass) == "table" then
		for class, key in pairs(old.activeByClass) do
			if type(key) == "string" then settings.activeByClass[class] = key end
		end
		old.activeByClass = nil
		moved = true
	end
	for _, key in ipairs({ "gems", "enchants" }) do
		if type(old[key]) == "boolean" then
			settings[key] = old[key]
			old[key] = nil
			moved = true
		end
	end
	-- Derived values Upgrades kept beside them.
	if type(old.activeScale) == "string" then old.activeScale = nil end
	if type(old.current) == "table" and getmetatable(old.current) == nil then old.current = nil end
	return moved
end

local function DB()
	local profile = E.db
	if not profile then return nil end
	if profile ~= bound then
		bound = profile
		if type(profile.itemScore) ~= "table" then profile.itemScore = {} end
		E.ApplyDefaults(profile.itemScore, E.defaults.itemScore)
		Migrate(profile)
		Invalidate()
	end
	return profile.itemScore
end

-- Read-only fallback before the saved settings are loaded.
local function S() return DB() or E.defaults.itemScore end

function ItemScore:Settings() return S() end

-- Moves Upgrades data again (after a share import). True when it moved any.
function ItemScore:MigrateLegacy()
	local moved = DB() and Migrate(E.db)
	if moved then self:Bump() end
	return moved
end

function ItemScore:GetSetting(key) return S()[key] end

function ItemScore:SetSetting(key, value)
	local settings = DB()
	if not settings or settings[key] == value then return end
	settings[key] = value
	self:Bump()
end

-- Back to the defaults, keeping the stored scales (they are the player's work).
function ItemScore:ResetSettings()
	local settings = DB()
	if not settings then return end
	settings.gems = E.defaults.itemScore.gems
	settings.enchants = E.defaults.itemScore.enchants
	wipe(settings.activeByClass)
	self:Bump()
end

---------------------------------------------------------------------------
-- Per character data (EldoUIDB.lootGuide[charKey]): rating mode and spec
---------------------------------------------------------------------------
local function CharStore(create)
	if type(EldoUIDB) ~= "table" or not E.charKey then return end
	local all = EldoUIDB.lootGuide
	if type(all) ~= "table" then
		if not create then return end
		all = {}
		EldoUIDB.lootGuide = all
	end
	local mine = all[E.charKey]
	if type(mine) ~= "table" then
		if not create then return end
		mine = {}
		all[E.charKey] = mine
	end
	return mine
end

---------------------------------------------------------------------------
-- Scale management
---------------------------------------------------------------------------
function ItemScore:GetScale(key)
	if type(key) ~= "string" then return end
	return S().scales[key] or STARTER[key]
end
local function GetScale(key) return ItemScore:GetScale(key) end

function ItemScore:IsStarter(key) return STARTER[key] ~= nil end

function ItemScore:IsCustom(key)
	local scale = S().scales[key]
	return scale and scale.custom and true or false
end

function ItemScore:ActiveScaleKey(class)
	class = class or Class()
	local key = S().activeByClass[class]
	if not GetScale(key) then key = CLASS_DEFAULT[class] or "GENERIC_STR" end
	return key
end

function ItemScore:ActiveScale(class)
	return GetScale(self:ActiveScaleKey(class)) or STARTER.GENERIC_STR
end

function ItemScore:SelectScale(key, class)
	local settings = DB()
	if not settings or not GetScale(key) then return false end
	settings.activeByClass[class or Class()] = key
	self:Bump()
	return true
end

-- Stored copy of a starter scale, made on its first edit.
local function Materialise(key)
	local settings = DB()
	if not settings then return end
	local scales = settings.scales
	if not scales[key] and STARTER[key] then
		local starter = STARTER[key]
		scales[key] = { name = starter.name, class = starter.class, model = starter.model, spec = starter.spec,
			weights = CopyTable(starter.weights) }
	end
	local scale = scales[key]
	if scale then scale.weights = scale.weights or {} end
	return scale
end

function ItemScore:SetWeight(key, stat, value)
	if not STAT_BY_KEY[stat] then return false end
	local scale = Materialise(key)
	if not scale then return false end
	value = tonumber(value)
	if value == 0 then value = nil end
	if scale.weights[stat] == value then return true end
	scale.weights[stat] = value
	self:Bump()
	return true
end

local function NewKey()
	local scales, index = S().scales, 1
	while scales["custom" .. index] do index = index + 1 end
	return "custom" .. index, index
end

-- A new custom scale for this class, selected. Without weights it copies
-- the active scale (and its model).
function ItemScore:NewScale(name, weights, model)
	local settings = DB()
	if not settings then return end
	local key, index = NewKey()
	local source = self:ActiveScale()
	if not weights then
		weights = source.weights
		model = source.model
	end
	settings.scales[key] = { name = name or ("Custom " .. index), class = Class(), custom = true,
		model = model == "spec" and "spec" or nil, weights = CopyTable(weights or {}) }
	self:SelectScale(key)
	return key
end

function ItemScore:RenameScale(key, name)
	name = type(name) == "string" and strtrim(name) or ""
	if name == "" or not GetScale(key) then return false end
	local scale = Materialise(key)
	scale.name = name
	self:Bump()
	return true
end

function ItemScore:DeleteScale(key)
	local settings = DB()
	local scale = settings and settings.scales[key]
	if not scale or not scale.custom then return false end
	settings.scales[key] = nil
	for class, active in pairs(settings.activeByClass) do
		if active == key then settings.activeByClass[class] = nil end
	end
	self:Bump()
	return true
end

-- A starter or spec scale back to EldoUI's values.
function ItemScore:ResetScale(key)
	local settings = DB()
	if not settings or not STARTER[key] or not settings.scales[key] then return false end
	settings.scales[key] = nil
	self:Bump()
	return true
end

-- key -> label of every scale this class can pick (for a dropdown).
function ItemScore:ScaleList(class)
	class = class or Class()
	local list, scales = {}, S().scales
	for key, scale in pairs(STARTER) do
		if scale.class == nil or scale.class == class then list[key] = (scales[key] and scales[key].name) or scale.name end
	end
	for key, scale in pairs(scales) do
		if scale.custom then list[key] = scale.name .. " (custom)" end
	end
	return list
end

---------------------------------------------------------------------------
-- Item stats
---------------------------------------------------------------------------
local statProviders = {}

-- fn(itemID, link) -> a GetItemStats-style table (ITEM_MOD_* keys) for an
-- item the client hasn't cached, e.g. from EldoUI_LootData's records.
function ItemScore:RegisterStatsProvider(fn)
	if type(fn) == "function" then table.insert(statProviders, fn) end
end

local function ProviderStats(link)
	local cached = providerCache[link]
	if cached ~= nil then return cached or nil end
	local result = false
	if #statProviders > 0 then
		local id = C_Item.GetItemInfoInstant(link)
		if id then
			for _, fn in ipairs(statProviders) do
				local ok, stats = pcall(fn, id, link)
				if ok and type(stats) == "table" and next(stats) then
					result = stats
					break
				end
			end
		end
	end
	providerCache[link] = result
	Track(link)
	return result or nil
end

local function ItemStats(link)
	local stats = statCache[link]
	if stats then return stats end
	local get = (C_Item and C_Item.GetItemStats) or _G.GetItemStats
	if get then
		local ok, result = pcall(get, link)
		if ok and type(result) == "table" and next(result) then
			Hold(link)
			statCache[link] = result
			return result
		end
	end
	return ProviderStats(link)
end

-- The same item with no enchant and no gems: item:id:enchant:gem1:gem2:gem3:gem4:...
-- Its stats are the item's own, whatever the client adds for gems.
local function BareLink(link)
	local bare, count = link:gsub("(item:%-?%d+):[^:|]*:[^:|]*:[^:|]*:[^:|]*:[^:|]*", "%1:::::", 1)
	return count > 0 and bare or link
end

-- "Equip:" lines in the client's language: each ITEM_MOD_* long string
-- ("Increases your hit rating by %s.") as a Lua pattern with one capture.
local equipPatterns
local function FormatToPattern(format)
	local out, index, captures = {}, 1, 0
	while index <= #format do
		local char = format:sub(index, index)
		if char == "%" then
			local spec, conv = format:match("^(%%%d*%$?[%-%+ #0]*%d*%.?%d*)([sdfgc%%])", index)
			if not spec then return end
			if conv == "%" then
				out[#out + 1] = "%%"
			elseif conv == "c" then
				out[#out + 1] = "[%+%-]?"
			else
				out[#out + 1] = "([%d%.,]+)"
				captures = captures + 1
			end
			index = index + #spec + 1
		else
			out[#out + 1] = char:find("[%^%$%(%)%.%[%]%*%+%-%?]") and ("%" .. char) or char
			index = index + 1
		end
	end
	if captures ~= 1 then return end
	return "^" .. table.concat(out) .. "$"
end

ItemScore.StatFormatPattern = FormatToPattern

local function EquipPatterns()
	if equipPatterns then return equipPatterns end
	equipPatterns = {}
	for _, key in ipairs(SPEC_READ_ORDER) do
		local long = key:gsub("_SHORT$", "")
		local text = long ~= key and _G[long]
		local pattern = type(text) == "string" and FormatToPattern(text)
		if pattern then equipPatterns[#equipPatterns + 1] = { pattern = pattern, key = key } end
	end
	return equipPatterns
end

-- Percent "Equip:" lines: the client's TOOLTIP_ITEM_STAT_<name>_INCREASE
-- and _DECREASE strings, matched against the whole line (two client
-- languages print another prefix than ITEM_SPELL_TRIGGER_ONEQUIP). Each
-- reads into its own PCT_* key; a rating key the stat API returns for the
-- same stat is that same bonus and is dropped (replaces).
local PERCENT_LINES = {
	{ name = "HIT_PERCENT", key = "PCT_HIT", replaces = { "ITEM_MOD_HIT_RATING_SHORT", "ITEM_MOD_HIT_MELEE_RATING_SHORT", "ITEM_MOD_HIT_RANGED_RATING_SHORT" } },
	{ name = "CRIT_PERCENT", key = "PCT_CRIT", replaces = { "ITEM_MOD_CRIT_RATING_SHORT", "ITEM_MOD_CRIT_MELEE_RATING_SHORT", "ITEM_MOD_CRIT_RANGED_RATING_SHORT" } },
	{ name = "HASTE_PCT", key = "PCT_HASTE", replaces = { "ITEM_MOD_HASTE_RATING_SHORT" } },
	{ name = "EXPERTISE_PCT", key = "PCT_EXPERTISE", replaces = { "ITEM_MOD_EXPERTISE_RATING_SHORT" } },
	{ name = "DODGE_PCT", key = "PCT_DODGE", replaces = { "ITEM_MOD_DODGE_RATING_SHORT" } },
	{ name = "PARRY_PCT", key = "PCT_PARRY", replaces = { "ITEM_MOD_PARRY_RATING_SHORT" } },
	{ name = "BLOCK_CHANCE", key = "PCT_BLOCK", replaces = { "ITEM_MOD_BLOCK_RATING_SHORT" } },
}
ItemScore.PERCENT_LINES = PERCENT_LINES

local percentPatterns
local function PercentPatterns()
	if percentPatterns then return percentPatterns end
	percentPatterns = {}
	for _, line in ipairs(PERCENT_LINES) do
		for _, direction in ipairs({ "INCREASE", "DECREASE" }) do
			local text = Safe(rawget(_G, "TOOLTIP_ITEM_STAT_" .. line.name .. "_" .. direction))
			local pattern = type(text) == "string" and FormatToPattern(text)
			if pattern then
				percentPatterns[#percentPatterns + 1] = { pattern = pattern, key = line.key, sign = direction == "INCREASE" and 1 or -1 }
			end
		end
	end
	-- A client without these strings is asked again next time.
	local list = percentPatterns
	if #list == 0 then percentPatterns = nil end
	return list
end

-- Builds the line patterns again from the client's strings (after the
-- strings changed, as the test kit does for each client language).
function ItemScore:ResetStatPatterns()
	percentPatterns, equipPatterns = nil, nil
	wipe(equipLineCache)
	Invalidate()
end

-- The same single-stat patterns also provide compact tooltip labels.
function ItemScore:ShortEquipText(text)
	text = Safe(text)
	if type(text) ~= "string" then return end
	local trigger = Safe(ITEM_SPELL_TRIGGER_ONEQUIP)
	if type(trigger) ~= "string" or text:sub(1, #trigger) ~= trigger then return end
	local effect = strtrim(text:sub(#trigger + 1))
	for _, entry in ipairs(EquipPatterns()) do
		local amount = effect:match(entry.pattern)
		local label = amount and Safe(rawget(_G, entry.key))
		if type(label) == "string" and label ~= "" then return "+" .. amount .. " " .. label end
	end
end

local function ParseNumber(text)
	local thousands = _G.LARGE_NUMBER_SEPARATOR
	local decimal = _G.DECIMAL_SEPARATOR
	if type(thousands) == "string" and thousands ~= "" then text = text:gsub("%" .. thousands, "") end
	if type(decimal) == "string" and decimal ~= "" and decimal ~= "." then text = text:gsub("%" .. decimal, ".") end
	return tonumber((text:gsub(",", "")))
end

-- Stats the item's "Equip:" lines give that GetItemStats left out.
local function EquipLineStats(link, known)
	local cached = equipLineCache[link]
	if cached == nil then
		cached = false
		local trigger = _G.ITEM_SPELL_TRIGGER_ONEQUIP
		if C_TooltipInfo and C_TooltipInfo.GetHyperlink and type(trigger) == "string" then
			local ok, data = pcall(C_TooltipInfo.GetHyperlink, link)
			if ok and type(data) == "table" and type(data.lines) == "table" then
				for _, line in ipairs(data.lines) do
					local text = Safe(line.leftText)
					local percent
					if type(text) == "string" then
						text = strtrim(text)
						for _, entry in ipairs(PercentPatterns()) do
							local value = text:match(entry.pattern)
							value = value and ParseNumber(value)
							if value then
								cached = cached or {}
								cached[entry.key] = (cached[entry.key] or 0) + value * entry.sign
								percent = true
								break
							end
						end
					end
					if not percent and type(text) == "string" and text:sub(1, #trigger) == trigger then
						text = strtrim(text:sub(#trigger + 1))
						for _, entry in ipairs(EquipPatterns()) do
							local value = text:match(entry.pattern)
							value = value and ParseNumber(value)
							if value then
								cached = cached or {}
								cached[entry.key] = (cached[entry.key] or 0) + value
								break
							end
						end
					end
				end
			end
		end
		equipLineCache[link] = cached
		Track(link)
	end
	if not cached then return known end
	local merged
	for key, value in pairs(cached) do
		if not known or known[key] == nil then
			merged = merged or (known and CopyTable(known) or {})
			merged[key] = value
		end
	end
	if merged then
		for _, line in ipairs(PERCENT_LINES) do
			if merged[line.key] ~= nil then
				for _, rating in ipairs(line.replaces) do merged[rating] = nil end
			end
		end
	end
	return merged or known
end

-- The item's own stats (no gems, no enchant) by the game's ITEM_MOD_* keys,
-- "Equip:" lines included. Used by the Loot Guide's simulator to put an
-- item on a character sheet. nil when the game has not sent the item yet.
function ItemScore:RawStats(link)
	if type(link) ~= "string" then return end
	local bare = BareLink(link)
	local stats = ItemStats(bare)
	return EquipLineStats(bare, stats)
end

---------------------------------------------------------------------------
-- Gems and enchants
---------------------------------------------------------------------------
local function SocketCount(stats)
	local count = 0
	for _, stat in ipairs(STATS) do
		if stat.socket then
			local value = Safe(stats[stat.read[1]])
			if type(value) == "number" then count = count + value end
		end
	end
	return count
end

-- Gems socketed in the item: their links, read with C_Item.GetItemGem.
local function GemLinks(link)
	local list = {}
	local getGem = C_Item and C_Item.GetItemGem
	if not getGem then return list end
	for index = 1, 4 do
		local ok, _, gemLink = pcall(getGem, link, index)
		if ok and type(gemLink) == "string" then list[#list + 1] = gemLink end
	end
	return list
end

-- Lower-case stat names as the game writes them, longest first (so "attack
-- power" wins over "power"): { label, stat key } pairs.
local enchantLabels
local function EnchantLabels()
	if enchantLabels then return enchantLabels end
	local byLabel = {}
	for _, stat in ipairs(STATS) do
		if not stat.socket and not stat.specOnly then
			for _, key in ipairs(stat.read) do
				local text = _G[key]
				if type(text) == "string" and text ~= "" and not text:find("%%") then byLabel[text:lower()] = stat.key end
			end
			byLabel[StatLabel(stat):lower()] = stat.key
		end
	end
	enchantLabels = {}
	for label, key in pairs(byLabel) do enchantLabels[#enchantLabels + 1] = { label, key } end
	table.sort(enchantLabels, function(a, b)
		if #a[1] ~= #b[1] then return #a[1] > #b[1] end
		return a[1] < b[1]
	end)
	return enchantLabels
end

-- The stat key of the label at the start of `text` (lower case). The label
-- is compared byte for byte, so accented, Cyrillic, Hangul and Han labels
-- ("Stärke", "к ловкости") are read in every client language. A label that
-- ends in a Latin letter or digit must end a word there.
local function LeadingStat(text)
	for _, pair in ipairs(EnchantLabels()) do
		local label = pair[1]
		if text:sub(1, #label) == label then
			local nextByte = text:byte(#label + 1)
			if not label:sub(-1):find("%w") or not nextByte
				or not (string.char(nextByte):find("%w") or nextByte >= 128) then
				return pair[2]
			end
		end
	end
end

-- The enchant's plain stat bonuses ("+7 Agility"), read from the enchant
-- line of the item's own tooltip data. Procs and other effects are not counted.
local function EnchantStats(link)
	local cached = enchantCache[link]
	if cached ~= nil then return cached or nil end
	local result = false
	if C_TooltipInfo and C_TooltipInfo.GetHyperlink then
		local enchantType = Enum.TooltipDataLineType and Enum.TooltipDataLineType.ItemEnchantmentPermanent or 15
		local ok, data = pcall(C_TooltipInfo.GetHyperlink, link)
		if ok and type(data) == "table" and type(data.lines) == "table" then
			for _, line in ipairs(data.lines) do
				local text = Safe(line.leftText)
				if Safe(line.type) == enchantType and type(text) == "string" then
					for amount, rest in text:gmatch("%+(%d+)%s*([^%+]*)") do
						local key = LeadingStat(rest:lower())
						if key then
							result = result or {}
							result[key] = (result[key] or 0) + tonumber(amount)
						end
					end
				end
			end
		end
	end
	enchantCache[link] = result
	Track(link)
	return result or nil
end

---------------------------------------------------------------------------
-- Weighing: plain model (sum of stat x weight, as Upgrades always did)
---------------------------------------------------------------------------
-- Points for a stats table. which = "stats" (no sockets), "sockets" or nil (all).
local function PlainWeighted(stats, weights, which)
	local total = 0
	for _, stat in ipairs(STATS) do
		if not stat.specOnly and (which == nil or (which == "sockets") == (stat.socket == true)) then
			local weight = tonumber(weights[stat.key])
			if weight and weight ~= 0 then
				for _, key in ipairs(stat.read) do
					local value = Safe(stats[key])
					if type(value) == "number" then total = total + value * weight end
				end
			end
		end
	end
	return total
end

---------------------------------------------------------------------------
-- Weighing: spec model
---------------------------------------------------------------------------
-- Percent (or skill/expertise points) a rating gives, by the game's own
-- table; the fixed level-60 table when the game can't tell.
local function RatingPercent(cr, value)
	local convert = GetCombatRatingBonusForCombatRatingValue
	if convert then
		local ok, result = pcall(convert, cr, value)
		result = ok and Safe(result)
		if type(result) == "number" and result > 0 then return result end
	end
	local per = W.ratingAt60[cr]
	if per then return value / per end
	return value
end
ItemScore.RatingPercent = RatingPercent

local function Weight(weights, name)
	local value = tonumber(weights[name])
	if value then return value end
	-- Fallbacks for stats a spec scale doesn't name.
	if name == "Haste" then
		return 0.7 * math.max(tonumber(weights.Crit) or 0, tonumber(weights.SpellCrit) or 0)
	elseif name == "Expertise" then
		return 0.25 * (tonumber(weights.Hit) or 0)
	end
	return 0
end

-- role: "main", "off" or "ranged" (which weapon slot DPS counts for).
local function SpecWeighted(stats, scale, role, which)
	local weights = scale.weights
	local spec = scale.spec and SPEC_BY_KEY[scale.spec]
	local total = 0
	if which ~= "sockets" then
		for _, key in ipairs(SPEC_READ_ORDER) do
			local rule = SPEC_READ[key]
			local value = Safe(stats[key])
			if type(value) == "number" and value ~= 0 then
				if rule.dps then
					local weight
					if role == "ranged" then
						weight = tonumber(weights.RangedDps) or 0
					elseif role == "off" then
						weight = (tonumber(weights.Dps) or 0) / 2
					else
						weight = tonumber(weights.Dps) or 0
					end
					total = total + value * weight
				elseif rule.feral and not (spec and spec.form) then -- luacheck: ignore 542
					-- Feral attack power only works in Cat and Bear form.
				elseif rule.sameAs and Safe(stats[rule.sameAs]) == value then -- luacheck: ignore 542
					-- Healing that is the same bonus as the spell power: counted there.
				elseif rule.either then
					-- The higher weight: the most a bonus adds, or the
					-- most a negative one ("decrease" line) takes away.
					local best = 0
					for index, name in ipairs(rule.either) do
						local amount = value
						if rule.cr then amount = RatingPercent(rule.cr[index], value) end
						local part = amount * Weight(weights, name)
						if value > 0 then best = math.max(best, part) else best = math.min(best, part) end
					end
					total = total + best
				else
					local amount = rule.cr and RatingPercent(rule.cr, value) or value * (rule.per or 1)
					total = total + amount * Weight(weights, rule.w)
				end
			end
		end
	end
	if which ~= "stats" then
		for _, stat in ipairs(STATS) do
			if stat.socket then
				local weight = tonumber(weights[stat.key])
				local value = Safe(stats[stat.read[1]])
				if weight and type(value) == "number" then total = total + value * weight end
			end
		end
	end
	return total
end

---------------------------------------------------------------------------
-- Scoring
---------------------------------------------------------------------------
-- Score of an item link for a scale. role (spec model only): weapon slot.
local function Score(link, key, role)
	if not link then return 0 end
	local scale = GetScale(key)
	if not scale then return nil end
	local spec = scale.model == "spec"
	role = spec and (role or "main") or ""
	local bucket = Bucket(scoreCache, key .. role)
	local cached = bucket[link]
	if cached then return cached end
	local bare = BareLink(link)
	local stats = ItemStats(bare)
	if spec then stats = EquipLineStats(bare, stats) end
	if not stats then
		Wait(link)
		return nil
	end
	local weights = scale.weights
	local settings = S()
	local total, sockets
	if spec then
		total, sockets = SpecWeighted(stats, scale, role, "stats"), SpecWeighted(stats, scale, role, "sockets")
	else
		total, sockets = PlainWeighted(stats, weights, "stats"), PlainWeighted(stats, weights, "sockets")
	end
	local parts = {}
	if settings.gems then
		local gems = GemLinks(link)
		if #gems > 0 then
			-- Filled sockets are worth their gems instead of the empty-socket value.
			local slots = SocketCount(stats)
			if slots > 0 then sockets = sockets * math.max(0, slots - #gems) / slots end
			local gemScore = 0
			for _, gemLink in ipairs(gems) do
				local gemStats = ItemStats(gemLink)
				if gemStats then
					gemScore = gemScore + (spec and SpecWeighted(gemStats, scale, role, "stats") or PlainWeighted(gemStats, weights, "stats"))
				end
			end
			parts.gems = gemScore
			total = total + gemScore
		end
	end
	total = total + sockets
	if settings.enchants then
		local enchant = EnchantStats(link)
		if enchant then
			local enchantScore = 0
			if spec then
				local asStats = {}
				for statKey, amount in pairs(enchant) do
					local read = STAT_BY_KEY[statKey].read[1]
					asStats[read] = (asStats[read] or 0) + amount
				end
				enchantScore = SpecWeighted(asStats, scale, role, "stats")
			else
				for statKey, amount in pairs(enchant) do
					enchantScore = enchantScore + amount * (tonumber(weights[statKey]) or 0)
				end
			end
			parts.enchant = enchantScore
			total = total + enchantScore
		end
	end
	bucket[link] = total
	Bucket(partsCache, key .. role)[link] = parts
	Track(link)
	return total
end

-- How much of an item's score came from gems and its enchant (after a Rate).
function ItemScore:Parts(link, key)
	key = key or self:ActiveScaleKey()
	if not link then return end
	for _, role in ipairs({ "", "main", "off", "ranged" }) do
		local bucket = partsCache[key .. role]
		if bucket and bucket[link] then return bucket[link] end
	end
end

local SLOT = {
	HEAD = INVSLOT_HEAD or 1, NECK = INVSLOT_NECK or 2, SHOULDER = INVSLOT_SHOULDER or 3, CHEST = INVSLOT_CHEST or 5,
	WAIST = INVSLOT_WAIST or 6, LEGS = INVSLOT_LEGS or 7, FEET = INVSLOT_FEET or 8, WRIST = INVSLOT_WRIST or 9,
	HAND = INVSLOT_HAND or 10, FINGER1 = INVSLOT_FINGER1 or 11, FINGER2 = INVSLOT_FINGER2 or 12,
	TRINKET1 = INVSLOT_TRINKET1 or 13, TRINKET2 = INVSLOT_TRINKET2 or 14, BACK = INVSLOT_BACK or 15,
	MAINHAND = INVSLOT_MAINHAND or 16, OFFHAND = INVSLOT_OFFHAND or 17, RANGED = INVSLOT_RANGED or 18,
}
ItemScore.SLOT = SLOT

-- equip location -> slots to compare against
local EQUIP = {
	INVTYPE_HEAD = { SLOT.HEAD }, INVTYPE_NECK = { SLOT.NECK }, INVTYPE_SHOULDER = { SLOT.SHOULDER },
	INVTYPE_CHEST = { SLOT.CHEST }, INVTYPE_ROBE = { SLOT.CHEST }, INVTYPE_WAIST = { SLOT.WAIST },
	INVTYPE_LEGS = { SLOT.LEGS }, INVTYPE_FEET = { SLOT.FEET }, INVTYPE_WRIST = { SLOT.WRIST },
	INVTYPE_HAND = { SLOT.HAND }, INVTYPE_CLOAK = { SLOT.BACK },
	INVTYPE_FINGER = { SLOT.FINGER1, SLOT.FINGER2 }, INVTYPE_TRINKET = { SLOT.TRINKET1, SLOT.TRINKET2 },
	INVTYPE_WEAPON = { SLOT.MAINHAND, SLOT.OFFHAND }, INVTYPE_2HWEAPON = { SLOT.MAINHAND },
	INVTYPE_WEAPONMAINHAND = { SLOT.MAINHAND }, INVTYPE_WEAPONOFFHAND = { SLOT.OFFHAND },
	INVTYPE_SHIELD = { SLOT.OFFHAND }, INVTYPE_HOLDABLE = { SLOT.OFFHAND },
	INVTYPE_RANGED = { SLOT.RANGED }, INVTYPE_RANGEDRIGHT = { SLOT.RANGED }, INVTYPE_THROWN = { SLOT.RANGED },
	INVTYPE_RELIC = { SLOT.RANGED },
}
ItemScore.EQUIP = EQUIP
local OFFHAND_TYPES = { INVTYPE_WEAPONOFFHAND = true, INVTYPE_SHIELD = true, INVTYPE_HOLDABLE = true }
local RANGED_TYPES = { INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true, INVTYPE_THROWN = true }
local DUAL_TYPES = { INVTYPE_WEAPON = true, INVTYPE_WEAPONOFFHAND = true }

local function EquipLoc(link)
	if not link then return end
	local _, _, _, equipLoc = C_Item.GetItemInfoInstant(link)
	return equipLoc
end

-- Weapon role of whatever sits in an inventory slot.
local function SlotRole(slot)
	if slot == SLOT.OFFHAND then return "off" end
	if slot == SLOT.RANGED then return "ranged" end
	return "main"
end

local function SlotScore(slot, key)
	local scale = GetScale(key)
	local role = scale and scale.model == "spec" and SlotRole(slot) or ""
	local bucket = Bucket(equippedCache, key .. role)
	local cached = bucket[slot]
	if cached then return cached end
	local link = GetInventoryItemLink("player", slot)
	local score = Score(link, key, role ~= "" and role or nil)
	if score then bucket[slot] = score end
	return score
end

-- Plain model: the score of what this item would replace and that slot.
-- nil when it can't be told honestly (unknown stats, or an off-hand while
-- a two-hander is worn). Second value true when the item is worn now.
local function BaseScore(link, equipLoc, key)
	local slots = EQUIP[equipLoc]
	if not slots then return end
	for _, slot in ipairs(slots) do
		if GetInventoryItemLink("player", slot) == link then return nil, true, slot end -- worn right now
	end
	local mainLink = GetInventoryItemLink("player", SLOT.MAINHAND)
	local mainIs2H = EquipLoc(mainLink) == "INVTYPE_2HWEAPON"

	if equipLoc == "INVTYPE_2HWEAPON" then
		local main, off = SlotScore(SLOT.MAINHAND, key), SlotScore(SLOT.OFFHAND, key)
		if not main or not off then return end
		return main + off, nil, SLOT.MAINHAND
	end
	if OFFHAND_TYPES[equipLoc] then
		if mainIs2H then return end
		return SlotScore(SLOT.OFFHAND, key), nil, SLOT.OFFHAND
	end
	if equipLoc == "INVTYPE_WEAPON" or equipLoc == "INVTYPE_WEAPONMAINHAND" then
		local main = SlotScore(SLOT.MAINHAND, key)
		if not main then return end
		if mainIs2H then return main, nil, SLOT.MAINHAND end -- replaces the two-hander (and nothing in the off hand)
		local offLink = GetInventoryItemLink("player", SLOT.OFFHAND)
		local offLoc = EquipLoc(offLink)
		if equipLoc == "INVTYPE_WEAPON" and DUAL_TYPES[offLoc] then
			local off = SlotScore(SLOT.OFFHAND, key)
			if off and off < main then return off, nil, SLOT.OFFHAND end
			return main, nil, SLOT.MAINHAND
		end
		return main, nil, SLOT.MAINHAND
	end
	-- Rings and trinkets: against the one worn from the same "only one
	-- equipped" group, since the game swaps that one; else the weaker one.
	local group = E:ItemLimitGroup(tonumber(tostring(link):match("item:(%d+)")))
	if group then
		for _, slot in ipairs(slots) do
			local worn = GetInventoryItemLink("player", slot)
			local wornID = worn and tonumber(tostring(worn):match("item:(%d+)"))
			if wornID and E:ItemLimitGroup(wornID) == group then return SlotScore(slot, key), nil, slot end
		end
	end
	local lowest, lowestSlot
	for _, slot in ipairs(slots) do
		local score = SlotScore(slot, key)
		if not score then return end
		if not lowest or score < lowest then lowest, lowestSlot = score, slot end
	end
	return lowest, nil, lowestSlot
end

-- The "only one of these equipped" group of an item and how many of it
-- may be worn at once: the game's answer, else the client data
-- (Data/ItemLimitGroups). nil for an item in no such group.
function E:ItemLimitGroup(itemID)
	if type(itemID) ~= "number" then return end
	local api = C_Item and C_Item.GetItemUniquenessByID
	if api then
		local ok, _, _, count, group = pcall(api, itemID)
		count, group = ok and E.Plain(count), ok and E.Plain(group)
		if type(group) == "number" and group > 0 then return group, type(count) == "number" and count > 0 and count or 1 end
	end
	local group = E.ItemLimitGroups and E.ItemLimitGroups[itemID]
	if group then return group, 1 end
end

local function IsRed(color)
	if type(color) ~= "table" then return false end
	local r, g, b = Safe(color.r), Safe(color.g), Safe(color.b)
	return type(r) == "number" and type(g) == "number" and type(b) == "number" and r > 0.95 and g < 0.25 and b < 0.25
end

-- Can the player use it? Read from the red text the game puts in the item's
-- own tooltip data (armor type, weapon skill, level, class).
local function UsableFromData(link)
	local cached = usableCache[link]
	if cached ~= nil then return cached end
	if not (C_TooltipInfo and C_TooltipInfo.GetHyperlink) then return true end
	local ok, data = pcall(C_TooltipInfo.GetHyperlink, link)
	if not ok or type(data) ~= "table" or type(data.lines) ~= "table" then return true end
	local usable = true
	for index = 2, #data.lines do
		local line = data.lines[index]
		if IsRed(line.leftColor) or IsRed(line.rightColor) then
			usable = false
			break
		end
	end
	usableCache[link] = usable
	Track(link)
	return usable
end

-- The same check on a tooltip that is already on screen (cheaper).
local function UsableFromTooltip(tooltip)
	local name = tooltip and tooltip:GetName()
	if not name then return true end
	for index = 2, tooltip:NumLines() do
		for _, side in ipairs({ "Left", "Right" }) do
			local line = _G[name .. "Text" .. side .. index]
			if line and line:IsShown() then
				local text = Safe(line:GetText())
				if text and text ~= "" then
					local r, g, b = line:GetTextColor()
					if IsRed({ r = r, g = g, b = b }) then return false end
				end
			end
		end
	end
	return true
end

function ItemScore:IsUsable(link, tooltip)
	if not link then return false end
	if tooltip then return UsableFromTooltip(tooltip) end
	return UsableFromData(link)
end

-- Smallest gain (percent) that counts as an upgrade; Upgrades sets it.
local threshold = function() return 0 end
function ItemScore:SetThreshold(fn)
	if type(fn) == "function" then threshold = fn end
end

local function Finish(result)
	if result.base then
		result.delta = result.score - result.base
		if result.base > 0 then result.percent = result.delta / result.base * 100 end
		result.upgrade = result.usable and result.delta > 0 and (not result.percent or result.percent >= (tonumber(threshold()) or 0))
	end
	return result
end

-- Spec model: the weapon slot an item would fill decides how its DPS counts,
-- so a one-hander for a dual wielder is tried in both hands.
local function EvaluateSpec(link, equipLoc, key, result)
	local role = RANGED_TYPES[equipLoc] and "ranged" or (OFFHAND_TYPES[equipLoc] and "off") or "main"
	local base, worn, slot = BaseScore(link, equipLoc, key)
	if worn then role = SlotRole(slot) end
	local score = Score(link, key, role)
	if not score then return end
	if equipLoc == "INVTYPE_WEAPON" and not worn then
		local mainLink = GetInventoryItemLink("player", SLOT.MAINHAND)
		local offLoc = EquipLoc(GetInventoryItemLink("player", SLOT.OFFHAND))
		if EquipLoc(mainLink) ~= "INVTYPE_2HWEAPON" and DUAL_TYPES[offLoc] then
			local main, off = SlotScore(SLOT.MAINHAND, key), SlotScore(SLOT.OFFHAND, key)
			local asOff = Score(link, key, "off")
			base, slot = main, SLOT.MAINHAND
			if main and off and asOff and (asOff - off) > (score - main) then
				score, base, slot = asOff, off, SLOT.OFFHAND
			elseif not main then
				base = nil
			end
		end
	end
	result.score, result.base, result.worn, result.slot = score, base, worn, slot
	return Finish(result)
end

-- The built-in "weights" rating of an item for one scale.
local function Evaluate(link, key, tooltip)
	if not link then return end
	local equipLoc = EquipLoc(link)
	if not equipLoc or not EQUIP[equipLoc] then return end
	local scale = GetScale(key)
	if not scale then return end
	local usable
	local result = { scale = scale.name, scaleKey = key, model = scale.model or "plain", spec = scale.spec, upgrade = false }
	if scale.model == "spec" then
		result.usable = ItemScore:IsUsable(link, tooltip)
		return EvaluateSpec(link, equipLoc, key, result)
	end
	local score = Score(link, key)
	if not score then return end
	local base, worn, slot = BaseScore(link, equipLoc, key)
	if tooltip then usable = UsableFromTooltip(tooltip) else usable = UsableFromData(link) end
	result.score, result.base, result.worn, result.usable, result.slot = score, base, worn, usable, slot
	return Finish(result)
end

---------------------------------------------------------------------------
-- Specs
---------------------------------------------------------------------------
function ItemScore:SpecInfo(spec) return SPEC_BY_KEY[spec] end

-- The specs of a class in talent-window order (every class when nil).
function ItemScore:Specs(class)
	if class then return SPECS_BY_CLASS[class] or {} end
	return W.specs
end

function ItemScore:SpecScaleKey(spec)
	return SPEC_BY_KEY[spec] and ("SPEC_" .. spec) or nil
end

-- A copy of the weights a spec rates by (the player's priority or EldoUI's).
function ItemScore:SpecWeights(spec)
	local scale = GetScale(self:SpecScaleKey(spec))
	return scale and CopyTable(scale.weights) or nil
end

-- The talent tree with the most points (the game's own answer), Feral as
-- Bear when the player's group role is tank. Healer trees played for
-- damage are never detected, only picked.
local function DetectSpec()
	local class = Class()
	local specs = SPECS_BY_CLASS[class]
	if not specs then return end
	local index
	local info = C_SpecializationInfo
	if info and info.GetSpecialization then
		local ok, value = pcall(info.GetSpecialization)
		index = ok and Safe(value) or nil
	end
	if type(index) ~= "number" or index < 1 then
		-- No talents yet: the class's first damage tree.
		for _, spec in ipairs(specs) do
			if spec.role == "DAMAGER" and not spec.manual then
				index = spec.tab
				break
			end
		end
		index = index or 1
	end
	local found
	for _, spec in ipairs(specs) do
		if spec.tab == index and not spec.manual then
			if spec.form then
				local role = Safe(UnitGroupRolesAssigned and UnitGroupRolesAssigned("player"))
				local wanted = role == "TANK" and "bear" or "cat"
				if spec.form == wanted then return spec.key end
				found = found or spec.key
			else
				return spec.key
			end
		end
	end
	return found or specs[1].key
end

-- The spec the talents point to (ignores a spec picked by hand).
function ItemScore:DetectedSpec()
	if not playerSpec then playerSpec = DetectSpec() end
	return playerSpec
end

-- Was the spec picked by hand?
function ItemScore:IsManualSpec()
	local mine = CharStore()
	local manual = mine and mine.spec
	local info = manual and SPEC_BY_KEY[manual]
	return info ~= nil and info.class == Class()
end

function ItemScore:PlayerSpec()
	local mine = CharStore()
	local manual = mine and mine.spec
	local info = manual and SPEC_BY_KEY[manual]
	if info and info.class == Class() then return manual end
	if not playerSpec then playerSpec = DetectSpec() end
	return playerSpec
end

-- Pick the spec by hand (nil goes back to detection). Per character.
function ItemScore:SetPlayerSpec(spec)
	if spec ~= nil then
		local info = SPEC_BY_KEY[spec]
		if not info or info.class ~= Class() then return false end
	end
	local mine = CharStore(spec ~= nil)
	if mine then mine.spec = spec end
	self:Bump()
	return true
end

---------------------------------------------------------------------------
-- Stat priority (the Loot Guide's drag strip): order = stats by weight x
-- typical amount. Dragging one stat sets only that stat's weight, to the
-- geometric mean of its new neighbors (one step past the end at the ends).
---------------------------------------------------------------------------
local function OrderOf(weights)
	local list = {}
	for _, stat in ipairs(STATS) do
		local weight = tonumber(weights[stat.key])
		if not stat.socket and weight and weight > 0 then list[#list + 1] = stat end
	end
	local typical = W.typical
	local rank = {}
	for index, stat in ipairs(list) do rank[stat.key] = index end
	table.sort(list, function(a, b)
		local va = tonumber(weights[a.key]) * (typical[a.key] or 1)
		local vb = tonumber(weights[b.key]) * (typical[b.key] or 1)
		if va ~= vb then return va > vb end
		return rank[a.key] < rank[b.key]
	end)
	local order = {}
	for index, stat in ipairs(list) do order[index] = stat.key end
	return order
end

function ItemScore:DefaultPriority(spec)
	local starter = STARTER[self:SpecScaleKey(spec) or ""]
	return starter and OrderOf(starter.weights) or {}
end

function ItemScore:Priority(spec)
	local scale = GetScale(self:SpecScaleKey(spec))
	return scale and OrderOf(scale.weights) or {}
end

local function Round(value) return math.floor(value * 1000 + 0.5) / 1000 end

-- Weights for an order: each place keeps 80 % of the value of the one
-- above (value = weight x typical amount), the first stat weighs 1.
function ItemScore:WeightsFromPriority(order)
	local weights, typical = {}, W.typical
	local first = order and order[1]
	if not first then return weights end
	local value = typical[first] or 1
	for _, key in ipairs(order) do
		if STAT_BY_KEY[key] and not STAT_BY_KEY[key].socket then
			weights[key] = Round(value / (typical[key] or 1))
			value = value * STEP
		end
	end
	return weights
end

local function SameOrder(a, b)
	if #a ~= #b then return false end
	for index = 1, #a do
		if a[index] ~= b[index] then return false end
	end
	return true
end

-- The player's own order for a spec. moved: the stat that was dragged (only
-- its weight changes); without it the whole order becomes new weights.
-- nil order, or the default order again, removes the player's priority.
function ItemScore:SetPriority(spec, order, moved)
	local key = self:SpecScaleKey(spec)
	if not key or not DB() then return false end
	if order == nil or SameOrder(order, self:DefaultPriority(spec)) then
		self:ResetScale(key)
		return true
	end
	local current = GetScale(key).weights
	local typical = W.typical
	local weights
	if moved and STAT_BY_KEY[moved] then
		weights = {}
		local position
		for index, stat in ipairs(order) do
			weights[stat] = current[stat]
			if stat == moved then position = index end
		end
		if not position then return false end
		-- Stats left out of the order no longer count; sockets keep their value.
		for statKey, value in pairs(current) do
			if STAT_BY_KEY[statKey] and STAT_BY_KEY[statKey].socket then weights[statKey] = value end
		end
		local function Value(stat)
			local weight = stat and tonumber(weights[stat])
			return weight and weight > 0 and weight * (typical[stat] or 1) or nil
		end
		local above, below = Value(order[position - 1]), Value(order[position + 1])
		local value
		if above and below then
			value = math.sqrt(above * below)
		elseif below then
			value = below / STEP
		elseif above then
			value = above * STEP
		else
			value = typical[moved] or 1
		end
		weights[moved] = Round(value / (typical[moved] or 1))
	else
		weights = self:WeightsFromPriority(order)
	end
	local scale = Materialise(key)
	scale.weights = weights
	scale.priority = true
	self:Bump()
	return true
end

---------------------------------------------------------------------------
-- Rating modes ("Rate items by"), per character
---------------------------------------------------------------------------
local raters, raterOrder = {}, {}

function ItemScore:RegisterRater(key, def)
	assert(type(key) == "string" and type(def) == "table", "ItemScore:RegisterRater(key, def)")
	assert(key == "weights" or type(def.rate) == "function", "ItemScore:RegisterRater: def.rate must be a function")
	def.key = key
	if not raters[key] then table.insert(raterOrder, key) end
	raters[key] = def
	if key ~= "weights" then self:Bump() end
end

ItemScore:RegisterRater("weights", { title = "Stat weights",
	desc = "Each stat is worth what your scale says; the score is their sum." })

-- { { key, title, desc }, ... } in the order they were registered.
function ItemScore:Raters()
	local list = {}
	for _, key in ipairs(raterOrder) do
		local def = raters[key]
		list[#list + 1] = { key = key, title = def.title or key, desc = def.desc }
	end
	return list
end

function ItemScore:GetRating()
	local mine = CharStore()
	local key = mine and mine.rating
	if key and raters[key] then return key end
	return "weights"
end

function ItemScore:SetRating(key)
	if key ~= nil and not raters[key] then return false end
	local mine = CharStore(key ~= nil)
	if mine and mine.rating ~= key then
		mine.rating = key
		self:Bump()
	end
	return true
end

-- Which scale a Rate call means.
function ItemScore:ScaleKeyFor(spec)
	if spec == nil then return self:ActiveScaleKey() end
	if spec == "player" then return self:SpecScaleKey(self:PlayerSpec()) end
	return self:SpecScaleKey(spec) or (GetScale(spec) and spec) or nil
end

function ItemScore:Rate(link, spec, tooltip)
	if type(link) ~= "string" then return end
	local key = self:ScaleKeyFor(spec)
	if not key then return end
	local ok, result = pcall(Evaluate, link, key, tooltip)
	if not ok or not result then return end
	result.rater = "weights"
	local raterKey = self:GetRating()
	local rater = raterKey ~= "weights" and raters[raterKey]
	if rater then
		local fine, extra = pcall(rater.rate, rater, link, result.spec or spec, result)
		if fine and type(extra) == "table" then
			for field, value in pairs(extra) do result[field] = value end
			result.rater = raterKey
		elseif not fine then
			geterrorhandler()(extra)
		end
	end
	return result
end

---------------------------------------------------------------------------
-- Scale strings: EldoUI's plain text and Pawn's format
---------------------------------------------------------------------------
-- Plain text, easy to read and to type by hand:
--   EldoUI scale "Warrior: Damage": Strength=1, Agility=0.6, Dps=3
-- A spec-model scale adds Model=spec (older EldoUI versions skip it).
local function FormatNumber(value)
	return (("%.3f"):format(value):gsub("%.?0+$", ""))
end
ItemScore.FormatNumber = FormatNumber

function ItemScore:ScaleString(key)
	key = key or self:ActiveScaleKey()
	local scale = GetScale(key) or self:ActiveScale()
	local parts = {}
	if scale.model == "spec" then parts[1] = "Model=spec" end
	for _, stat in ipairs(STATS) do
		local value = tonumber(scale.weights[stat.key])
		if value and value ~= 0 then parts[#parts + 1] = ("%s=%s"):format(stat.key, FormatNumber(value)) end
	end
	return ('EldoUI scale "%s": %s'):format((scale.name or "Scale"):gsub('"', "'"), table.concat(parts, ", "))
end

-- Pawn scale strings: ( Pawn: v1: "Name": Class=Warrior, Strength=1, Ap=0.5 )
-- The stat names below are the names Pawn's public scale format uses; the
-- first name per EldoUI stat is the one EldoUI writes. Pawn stats EldoUI has
-- no use for (class, spec, weapon types ...) are skipped.
local PAWN = {
	{ "Strength", "Strength" }, { "Agility", "Agility" }, { "Stamina", "Stamina" }, { "Intellect", "Intellect" },
	{ "Spirit", "Spirit" }, { "Armor", "Armor" },
	{ "Ap", "AttackPower" }, { "Rap", "RangedAttackPower" },
	{ "SpellPower", "SpellPower" }, { "SpellDamage", "SpellPower" }, { "Healing", "Healing" },
	{ "CritRating", "Crit" }, { "SpellCritRating", "SpellCrit" },
	{ "HitRating", "Hit" }, { "SpellHitRating", "SpellHit" },
	{ "HasteRating", "Haste" }, { "SpellHasteRating", "Haste" },
	{ "ExpertiseRating", "Expertise" }, { "MasteryRating", "Mastery" }, { "Versatility", "Versatility" },
	{ "Mp5", "Mp5" }, { "Hp5", "Hp5" },
	{ "DefenseRating", "Defense" }, { "DodgeRating", "Dodge" }, { "ParryRating", "Parry" },
	{ "BlockRating", "Block" }, { "BlockValue", "BlockValue" },
	{ "Dps", "Dps" }, { "MeleeDps", "Dps" }, { "RangedDps", "Dps" },
	{ "RedSocket", "RedSocket" }, { "YellowSocket", "YellowSocket" }, { "BlueSocket", "BlueSocket" },
	{ "MetaSocket", "MetaSocket" }, { "PrismaticSocket", "PrismaticSocket" },
	{ "FireResistance", "FireResistance" }, { "NatureResistance", "NatureResistance" }, { "FrostResistance", "FrostResistance" },
	{ "ShadowResistance", "ShadowResistance" }, { "ArcaneResistance", "ArcaneResistance" },
}
local FROM_PAWN, TO_PAWN = {}, {}
for _, pair in ipairs(PAWN) do
	FROM_PAWN[pair[1]:lower()] = pair[2]
	if not TO_PAWN[pair[2]] then TO_PAWN[pair[2]] = pair[1] end
end
TO_PAWN.RangedDps = "RangedDps"

-- Spec weights are per 1 %; Pawn's are per rating point.
local PAWN_CR = { Crit = 9, SpellCrit = 11, Hit = 6, SpellHit = 8, Haste = 18, Expertise = 24, Mastery = 26,
	Versatility = 29, Defense = 2, Dodge = 3, Parry = 4, Block = 5 }

function ItemScore:PawnString(key)
	key = key or self:ActiveScaleKey()
	local scale = GetScale(key) or self:ActiveScale()
	local parts = {}
	for _, stat in ipairs(STATS) do
		local value = tonumber(scale.weights[stat.key])
		local name = TO_PAWN[stat.key]
		if name and value and value ~= 0 then
			if scale.model == "spec" and PAWN_CR[stat.key] then value = value * RatingPercent(PAWN_CR[stat.key], 1) end
			parts[#parts + 1] = ("%s=%s"):format(name, FormatNumber(value))
		end
	end
	-- Pawn names the class in English, e.g. Class=Warrior, DeathKnight.
	local class = scale.class or Class()
	local english = { DEATHKNIGHT = "DeathKnight", DEMONHUNTER = "DemonHunter" }
	if class then table.insert(parts, 1, "Class=" .. (english[class] or (class:sub(1, 1) .. class:sub(2):lower()))) end
	return ('( Pawn: v1: "%s": %s )'):format((scale.name or "Scale"):gsub('"', "'"), table.concat(parts, ", "))
end

-- Pawn weights can be on any scale (Strength=2.6). When one is above what
-- EldoUI's slider allows, every weight is scaled down by the same factor so
-- their ratios, and so the upgrade order, stay the same.
local function FitWeights(weights)
	local factor = 1
	for key, value in pairs(weights) do
		local stat = STAT_BY_KEY[key]
		local max = stat and stat.max or 3
		if value > max then factor = math.min(factor, max / value) end
	end
	if factor < 1 then
		for key, value in pairs(weights) do weights[key] = tonumber(FormatNumber(value * factor)) end
	end
	return factor
end

-- -> { name, weights, count, skipped, factor } or nil when it isn't a Pawn
-- string. count 0 means it had no stat EldoUI uses.
function ItemScore:ParsePawnString(text)
	if type(text) ~= "string" then return end
	local name, body = text:match('Pawn:%s*v%d+:%s*"([^"]*)"%s*:(.*)')
	if not body then return end
	local weights, count, skipped = {}, 0, 0
	for key, value in body:gmatch("([%w_]+)%s*=%s*([^,%)]+)") do
		local ours = FROM_PAWN[key:lower()]
		value = tonumber(strtrim(value))
		if ours and value then
			-- Pawn may list both Ap and FeralAp, SpellPower and SpellDamage: keep the larger.
			if value > 0 and (not weights[ours] or value > weights[ours]) then
				if not weights[ours] then count = count + 1 end
				weights[ours] = value
			end
		elseif value then
			skipped = skipped + 1
		end
	end
	local factor = count > 0 and FitWeights(weights) or 1
	return { name = name ~= "" and name or nil, weights = weights, count = count, skipped = skipped, factor = factor }
end

-- EldoUI's own format -> { name, weights, count, model } (count 0: nothing usable).
function ItemScore:ParseScaleString(text)
	if type(text) ~= "string" then return end
	local name = text:match('"(.-)"')
	local model = text:find("[Mm]odel%s*=%s*spec") and "spec" or nil
	local weights, count = {}, 0
	for key, value in text:gmatch("([%a]+)%s*=%s*(%-?[%d%.]+)") do
		local stat = STAT_BY_KEY[key]
		value = tonumber(value)
		if stat and value then
			local max = stat.max or 3
			if model == "spec" and stat.rating then max = 40 end
			weights[key] = math.max(0, math.min(max, value))
			count = count + 1
		end
	end
	return { name = name ~= "" and name or nil, weights = weights, count = count, model = model }
end

---------------------------------------------------------------------------
-- Redraw: everything that shows a score registers a refresher
---------------------------------------------------------------------------
local refreshers = {}
function E:RegisterUpgradeRefresh(fn)
	if type(fn) == "function" then refreshers[#refreshers + 1] = fn end
end

local redrawPending = false
function ItemScore:Redraw()
	if redrawPending then return end
	redrawPending = true
	C_Timer.After(0.1, function()
		redrawPending = false
		for _, fn in ipairs(refreshers) do
			local ok, err = pcall(fn)
			if not ok then geterrorhandler()(err) end
		end
	end)
end

function ItemScore:Bump()
	Invalidate()
	self:Redraw()
end

-- Drops what was cached for one item (and for links that hold it as a
-- gem). true when anything was dropped.
local function DropItem(itemID)
	local links = linksById[itemID]
	linksById[itemID] = nil
	if not links then return false end
	for _, cache in ipairs({ scoreCache, partsCache }) do
		for _, bucket in pairs(cache) do
			for link in pairs(links) do bucket[link] = nil end
		end
	end
	for _, cache in ipairs({ providerCache, equipLineCache, enchantCache, usableCache }) do
		for link in pairs(links) do cache[link] = nil end
	end
	for _, bucket in pairs(equippedCache) do
		for slot in pairs(bucket) do
			local worn = GetInventoryItemLink("player", slot)
			if worn and links[worn] then bucket[slot] = nil end
		end
	end
	return true
end

-- Redraws for arriving item data: at most one every half second.
local ITEM_REDRAW_GAP = 0.5
local itemRedrawPending = false
local function ItemRedraw()
	if itemRedrawPending then return end
	itemRedrawPending = true
	C_Timer.After(ITEM_REDRAW_GAP, function()
		itemRedrawPending = false
		ItemScore.version = ItemScore.version + 1
		ItemScore:Redraw()
	end)
end

local function OnItemData(itemID)
	itemID = tonumber(Safe(itemID))
	if not itemID then return end
	local waited = waitingIds[itemID]
	waitingIds[itemID] = nil
	if DropItem(itemID) or waited then ItemRedraw() end
end

-- Caches that depend on gear, item data, level and talents.
local function OnEvent(_, event, ...)
	if event == "GET_ITEM_INFO_RECEIVED" then
		OnItemData(...)
		return
	end
	if event == "PLAYER_EQUIPMENT_CHANGED" then
		Invalidate()
	elseif event == "PLAYER_LEVEL_UP" then
		-- Rating conversion changes with level, usability too.
		Invalidate()
		wipe(usableCache)
	elseif event == "SKILL_LINES_CHANGED" then
		wipe(usableCache)
	else -- talents or group role
		playerSpec = nil
		Invalidate()
	end
	ItemScore:Redraw()
end
for _, event in ipairs({ "PLAYER_EQUIPMENT_CHANGED", "GET_ITEM_INFO_RECEIVED", "PLAYER_LEVEL_UP", "SKILL_LINES_CHANGED",
	"PLAYER_TALENT_UPDATE", "CHARACTER_POINTS_CHANGED", "ACTIVE_TALENT_GROUP_CHANGED", "PLAYER_ROLES_ASSIGNED" }) do
	E:RegisterEvent(event, OnEvent, ItemScore)
end
