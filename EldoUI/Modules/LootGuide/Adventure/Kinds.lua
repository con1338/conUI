-- EldoUI My Adventure: every line kind of the journal.
--
-- One table says, for each kind: its group (the Journey filter), icon,
-- which detail setting shows it, where a click goes, how much it is worth
-- when the store must make room, whether it may roll up into a chapter
-- summary, when it is a keepsake, and the fields its packed row holds.
--   J:Kind(kind)                 the definition, or nil
--   J:Kinds()                    every kind key, sorted
--   J:RegisterKind(kind, def)    plugins add their own kinds
--   J:Shows(key[, ctx])          one detail setting ("spells", "lootMin", ...)
--   J:SetShows(key, value)       change one: the preset becomes "custom"
--   J:Shown(row[, ctx])          the one visibility function (detail preset,
--                                group filter, kinds, search)
--   J:IsKeepsake(row)            the row is a keepsake card
--   J:Worth(row)                 3 never dropped first, 1 dropped first
--   J:LinkFor(row)               the address a click on the row opens
--
-- Portions adapted from Forever Journal by Ugge Zen, MIT License (see
-- THIRD_PARTY_NOTICES.md): the event kinds, their icons and groups, the
-- detail presets and which setting shows each kind, the worth order used
-- when the journal fills up, and the armor filter for finds.
--
-- MIT License
--
-- Copyright (c) 2026 Ugge Zen
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
local _, E = ...
local A = E.Adventure
local J = E.Journal

---------------------------------------------------------------------------
-- Field types of a packed row: n number, s string, i string kept once in
-- the character's string table (zones, names), b true or nil.
-- Every row also has t, seq, kind, level, zone, subzone and keep.
---------------------------------------------------------------------------
local ICON = {
	level = "Interface/Icons/Spell_Holy_SurgeOfLight", zone = "Interface/Icons/INV_Misc_Map_01",
	dungeon = "Interface/Icons/INV_Misc_Key_03", death = "Interface/Icons/Ability_Rogue_FeignDeath",
	spell = "Interface/Icons/INV_Misc_Book_11", recipe = "Interface/Icons/INV_Scroll_03",
	profession = "Interface/Icons/INV_Misc_Note_01", skill = "Interface/Icons/INV_Sword_04",
	respec = "Interface/Icons/Spell_Nature_Polymorph_Cow", rep = "Interface/Icons/INV_Misc_Note_02",
	boss = "Interface/TargetingFrame/UI-TargetingFrame-Skull", loot = "Interface/Icons/INV_Misc_Bag_10",
	mount = "Interface/Icons/Ability_Mount_RidingHorse", pet = "Interface/Icons/INV_Box_PetCarrier_01",
	flight = "Interface/Icons/Ability_Hunter_EagleEye", goal = "Interface/Icons/Achievement_Quests_Completed_08",
	note = "Interface/Icons/INV_Misc_Note_05", quest = "Interface/GossipFrame/ActiveQuestIcon", -- no-L
	people = "Interface/Icons/Achievement_GuildPerk_EverybodysFriend", pvp = "Interface/Icons/INV_BannerPVP_02",
	attune = "Interface/Icons/INV_Misc_Key_14", gear = "Interface/Icons/INV_Chest_Chain",
	legacy = "Interface/Icons/Achievement_Level_10", rest = "Interface/Icons/Spell_Nature_Sleep",
	gather = "Interface/Icons/INV_Misc_Herb_07", farm = "Interface/Icons/INV_Misc_Coin_02",
	rare = "Interface/Icons/Ability_Hunter_MarkedForDeath", scene = "Interface/Icons/INV_Misc_Film_01",
	guild = "Interface/Icons/INV_Shirt_GuildTabard_01", hearth = "Interface/Icons/INV_Misc_Rune_01",
	scroll = "Interface/Icons/INV_Scroll_11", session = "Interface/Icons/INV_Misc_PocketWatch_01",
	summary = "Interface/Icons/INV_Misc_Book_09",
}
J.ICON = ICON

-- group: growth, gear, deeds, places, people, notes (the Journey filter).
-- show: the detail setting that shows the kind ("always" when none).
-- worth: 3 levels, goals, notes and keepsakes; 2 deaths and arrivals; 1 the rest.
-- rollup: may fold into its chapter's summary row once two levels behind.
-- link: the address kind a click opens and the field that names it.
-- keepsake: when a row of the kind gets its own card.
-- derived: a story beat worked out from other facts, never a stored row.
local KINDS = {
	-- The base kinds
	level = { group = "growth", icon = ICON.level, show = "always", worth = 3, link = { "moment" },
		fields = { { "took", "n" } } },
	zone = { group = "places", icon = ICON.zone, show = "zones", worth = 2, link = { "place", "zone" },
		fields = { { "begin", "b" } } },
	dungeon = { group = "places", icon = ICON.dungeon, show = "zones", worth = 2, link = { "instance", "instance" },
		fields = { { "instance", "i" }, { "instanceID", "n" } } },
	death = { group = "deeds", icon = ICON.death, show = "deaths", worth = 2, link = { "place", "zone" } },
	boss = { group = "deeds", icon = ICON.boss, show = "bosses", worth = 2, link = { "instance", "instance" },
		keepsake = function(row) return row.first == true end,
		fields = { { "boss", "i" }, { "encounter", "n" }, { "first", "b" }, { "instance", "i" }, { "kills", "n" } } },
	loot = { group = "gear", icon = ICON.loot, show = "loot", worth = 1, rollup = true, link = { "item", "item" },
		keepsake = function(row) return (tonumber(row.quality) or 0) >= 4 end,
		fields = { { "item", "n" }, { "quality", "n" }, { "armor", "n" }, { "from", "i" } } },
	rep = { group = "deeds", icon = ICON.rep, show = "rep", worth = 1, link = { "section", nil, "reputation" },
		keepsake = function(row) return (tonumber(row.standing) or 0) >= 6 end,
		fields = { { "faction", "i" }, { "factionID", "n" }, { "standing", "n" } } },
	spell = { group = "growth", icon = ICON.spell, show = "spells", worth = 1, rollup = true,
		fields = { { "spell", "n" }, { "name", "i" }, { "rank", "s" } } },
	recipe = { group = "growth", icon = ICON.recipe, show = "recipes", worth = 1, rollup = true,
		link = { "section", nil, "crafting" }, fields = { { "recipe", "n" }, { "name", "i" } } },
	profession = { group = "growth", icon = ICON.profession, show = "professions", worth = 2,
		link = { "section", nil, "crafting" }, fields = { { "profession", "i" } } },
	skill = { group = "growth", icon = ICON.skill, show = "professions", worth = 1,
		link = { "section", nil, "crafting" }, keepsake = function(row) return row.mastered == true end,
		fields = { { "profession", "i" }, { "rank", "n" }, { "max", "n" }, { "mastered", "b" } } },
	mount = { group = "gear", icon = ICON.mount, show = "mounts", worth = 2, link = { "section", nil, "keepsakes" },
		keepsake = function() return true end, fields = { { "mount", "n" }, { "name", "i" } } },
	pet = { group = "gear", icon = ICON.pet, show = "mounts", worth = 1, link = { "section", nil, "keepsakes" },
		fields = { { "pet", "n" }, { "name", "i" } } },
	respec = { group = "growth", icon = ICON.respec, show = "respecs", worth = 1, fields = { { "points", "n" } } },
	flight = { group = "places", icon = ICON.flight, show = "flights", worth = 1, rollup = true,
		fields = { { "place", "i" }, { "node", "n" } } },
	goal = { group = "deeds", icon = ICON.goal, show = "goals", worth = 3, link = { "goal", "goal" },
		fields = { { "goal", "n" }, { "name", "s" } } },
	goalset = { group = "deeds", icon = ICON.goal, show = "goals", worth = 3, link = { "goal", "goal" },
		fields = { { "goal", "n" }, { "name", "s" } } },
	note = { group = "notes", icon = ICON.note, show = "always", worth = 3, link = { "note", "note" },
		fields = { { "note", "n" } } },

	-- New kinds from EldoUI's stores
	run = { group = "places", icon = ICON.dungeon, show = "runs", worth = 1, link = { "instance", "instance" },
		fields = { { "instance", "i" }, { "instanceID", "n" }, { "duration", "n" }, { "run", "n" } } },
	bossagain = { group = "deeds", icon = ICON.boss, show = "minor", worth = 1, rollup = true,
		link = { "instance", "instance" }, fields = { { "boss", "i" }, { "encounter", "n" }, { "kills", "n" }, { "instance", "i" } } },
	raid = { group = "places", icon = ICON.dungeon, show = "always", worth = 2, link = { "instance", "instance" },
		keepsake = function() return true end, fields = { { "instance", "i" }, { "instanceID", "n" } } },
	raidboss = { group = "deeds", icon = ICON.boss, show = "always", worth = 2, link = { "instance", "instance" },
		keepsake = function() return true end, fields = { { "boss", "i" }, { "encounter", "n" }, { "instance", "i" } } },
	pvpwin = { group = "deeds", icon = ICON.pvp, show = "runs", worth = 1, link = { "section", nil, "pvp" },
		fields = { { "battleground", "i" }, { "run", "n" } } },
	pvploss = { group = "deeds", icon = ICON.pvp, show = "runs", worth = 1, link = { "section", nil, "pvp" },
		fields = { { "battleground", "i" }, { "run", "n" } } },
	quest = { group = "deeds", icon = ICON.quest, show = "minor", worth = 1, rollup = true, link = { "quest", "quest" },
		fields = { { "quest", "n" }, { "xp", "n" }, { "money", "n" } } },
	questchain = { group = "deeds", icon = ICON.quest, show = "zones", worth = 2, link = { "quest", "quest" },
		fields = { { "quest", "n" }, { "chain", "n" } } },
	dungeonquest = { group = "deeds", icon = ICON.quest, show = "runs", worth = 1, link = { "quest", "quest" },
		fields = { { "quest", "n" }, { "instance", "i" } } },
	groupquest = { group = "people", icon = ICON.quest, show = "companions", worth = 1, link = { "quest", "quest" },
		fields = { { "quest", "n" }, { "names", "s" } } },
	attunestep = { group = "deeds", icon = ICON.attune, show = "zones", worth = 2, link = { "section", nil, "attune" },
		fields = { { "attune", "s" }, { "step", "n" }, { "total", "n" } } },
	attuned = { group = "deeds", icon = ICON.attune, show = "always", worth = 2, link = { "section", nil, "attune" },
		keepsake = function() return true end, fields = { { "attune", "s" }, { "instance", "i" } } },
	challenge = { group = "deeds", icon = ICON.legacy, show = "challenges", worth = 1,
		fields = { { "challenge", "n" }, { "name", "i" } } },
	legacylevel = { group = "growth", icon = ICON.legacy, show = "challenges", worth = 2, fields = { { "rank", "n" } } },
	title = { group = "deeds", icon = ICON.scroll, show = "mounts", worth = 2, link = { "section", nil, "keepsakes" },
		keepsake = function() return true end, fields = { { "title", "n" }, { "name", "i" } } },
	explored = { group = "places", icon = ICON.zone, show = "zones", worth = 2, link = { "place", "zone" } },
	subzone = { group = "places", icon = ICON.zone, show = "minor", worth = 1, rollup = true, link = { "place", "zone" } },
	hearth = { group = "places", icon = ICON.hearth, show = "minor", worth = 1, fields = { { "place", "i" } } },
	gear = { group = "gear", icon = ICON.gear, show = "gear", worth = 1, rollup = true, link = { "item", "item" },
		fields = { { "item", "n" }, { "quality", "n" }, { "gain", "n" } } },
	wish = { group = "gear", icon = ICON.loot, show = "always", worth = 2, link = { "item", "item" },
		keepsake = function() return true end, fields = { { "item", "n" } } },
	met = { group = "people", icon = ICON.people, show = "companions", worth = 1, link = { "fellow", "key" },
		fields = { { "name", "i" }, { "class", "s" }, { "key", "s" } } },
	together = { group = "people", icon = ICON.people, show = "companions", worth = 1, link = { "fellow", "key" },
		fields = { { "name", "i" }, { "seconds", "n" }, { "key", "s" } } },
	rested = { group = "growth", icon = ICON.rest, show = "minor", worth = 1, rollup = true, fields = { { "pct", "n" } } },
	gap = { group = "growth", icon = ICON.session, show = "always", worth = 2, fields = { { "days", "n" } } },
	gather = { group = "places", icon = ICON.gather, show = "minor", worth = 1, rollup = true, link = { "place", "zone" },
		fields = { { "node", "i" }, { "count", "n" } } },
	farm = { group = "places", icon = ICON.farm, show = "minor", worth = 1, rollup = true, link = { "place", "zone" },
		fields = { { "seconds", "n" }, { "money", "n" } } },
	rare = { group = "places", icon = ICON.rare, show = "minor", worth = 1, rollup = true,
		fields = { { "rare", "i" }, { "npc", "n" } } },
	cinematic = { group = "places", icon = ICON.scene, show = "minor", worth = 1, rollup = true },
	guild = { group = "people", icon = ICON.guild, show = "companions", worth = 2, fields = { { "guild", "i" } } },
	session = { group = "growth", icon = ICON.session, show = "minor", worth = 1, rollup = true,
		fields = { { "login", "n" }, { "logout", "n" }, { "played", "n" } } },
	-- The chapter summary that ordinary rows roll up into (Store.lua).
	rollup = { group = "growth", icon = ICON.summary, show = "always", worth = 2, link = { "moment" },
		fields = { { "counts", "s" }, { "best", "n" }, { "bestQuality", "n" }, { "to", "n" } } },

	-- Derived story beats (Story/Derive.lua): no row of their own.
	deathstreak = { group = "deeds", icon = ICON.death, show = "deaths", derived = true },
	deathless = { group = "deeds", icon = ICON.level, show = "always", derived = true },
	questburst = { group = "deeds", icon = ICON.quest, show = "always", derived = true },
	fast = { group = "growth", icon = ICON.level, show = "always", derived = true },
	slow = { group = "growth", icon = ICON.level, show = "always", derived = true },
	firstdungeon = { group = "places", icon = ICON.dungeon, show = "always", derived = true },
	firstepic = { group = "gear", icon = ICON.loot, show = "always", derived = true },
	firstraid = { group = "places", icon = ICON.dungeon, show = "always", derived = true },
	firstmount = { group = "gear", icon = ICON.mount, show = "always", derived = true },
	maxlevel = { group = "growth", icon = ICON.level, show = "always", derived = true },
	mostrun = { group = "places", icon = ICON.dungeon, show = "always", derived = true },
	topfellow = { group = "people", icon = ICON.people, show = "always", derived = true },
	homezone = { group = "places", icon = ICON.zone, show = "always", derived = true },
}
J.KINDS = KINDS

local GROUPS = { "growth", "gear", "deeds", "places", "people", "notes" }
J.GROUPS = GROUPS

local function Prepare(kind, def)
	def.kind = kind
	def.fields = def.fields or {}
	def.worth = tonumber(def.worth) or 1
	def.group = def.group or "deeds"
	def.show = def.show or "always"
	def.icon = def.icon or ICON.summary
	def.index = {}
	for position, field in ipairs(def.fields) do def.index[field[1]] = position end
	return def
end

for kind, def in pairs(KINDS) do Prepare(kind, def) end

function J:Kind(kind)
	return KINDS[kind]
end

function J:Kinds()
	local list = {}
	for kind in pairs(KINDS) do list[#list + 1] = kind end
	table.sort(list)
	return list
end

local FIELD_TYPES = { n = true, s = true, i = true, b = true }
local RESERVED = { t = true, seq = true, kind = true, level = true, zone = true, subzone = true, keep = true,
	src = true, ref = true }

-- A plugin's kind: { group, icon, show, worth, rollup, link, keepsake,
-- fields = { { name, "n"|"s"|"i"|"b" }, ... } }. A built-in kind keeps its
-- definition. Returns the kind's definition, or nil and why.
function J:RegisterKind(kind, def)
	if type(kind) ~= "string" or not kind:match("^[%w_]+$") then return nil, "bad kind" end
	if KINDS[kind] and not KINDS[kind].plugin then return KINDS[kind] end
	if type(def) ~= "table" then def = {} end
	local copy = {}
	for key, value in pairs(def) do copy[key] = value end
	local fields = {}
	for _, field in ipairs(type(def.fields) == "table" and def.fields or {}) do
		if type(field) == "table" and type(field[1]) == "string" and not RESERVED[field[1]] and FIELD_TYPES[field[2]] then
			fields[#fields + 1] = { field[1], field[2] }
		end
	end
	copy.fields = fields
	copy.derived = nil
	copy.plugin = true
	if copy.group and not tContains(GROUPS, copy.group) then copy.group = nil end
	KINDS[kind] = Prepare(kind, copy)
	return KINDS[kind]
end

---------------------------------------------------------------------------
-- How much the journal shows. Everything is always written down; these
-- only choose what the pages show. "minor" is the small rows only the
-- Chronicler preset shows (no tick of its own).
---------------------------------------------------------------------------
J.DETAIL = {
	essentials = { spells = false, recipes = false, professions = false, respecs = false, mounts = true, bosses = true,
		deaths = true, zones = false, flights = false, goals = true, runs = false, companions = false, gear = false,
		challenges = false, minor = false, lootMin = 4, repMin = "honored", keepsakes = true },
	story = { spells = true, recipes = true, professions = true, respecs = true, mounts = true, bosses = true,
		deaths = true, zones = true, flights = true, goals = true, runs = true, companions = true, gear = true,
		challenges = true, minor = false, lootMin = 4, repMin = "all", keepsakes = true },
	chronicler = { spells = true, recipes = true, professions = true, respecs = true, mounts = true, bosses = true,
		deaths = true, zones = true, flights = true, goals = true, runs = true, companions = true, gear = true,
		challenges = true, minor = true, lootMin = 3, repMin = "all", keepsakes = true },
}
J.DETAIL_ORDER = { "essentials", "story", "chronicler" }
-- The custom ticks, in option order (Options.lua draws them).
J.SHOW_KEYS = { "spells", "recipes", "professions", "respecs", "bosses", "mounts", "deaths", "zones", "flights",
	"goals", "runs", "companions", "gear", "challenges" }

-- Settings for one check: ctx fields win over the module's settings.
local function Setting(ctx, key)
	if ctx and ctx[key] ~= nil then return ctx[key] end
	local db = A.db
	return db and db[key]
end

function J:Shows(key, ctx)
	local detail = Setting(ctx, "detail") or "story"
	if detail == "custom" then
		local show = Setting(ctx, "show")
		if type(show) == "table" and show[key] ~= nil then return show[key] end
		if key == "lootMin" or key == "repMin" then
			local value = Setting(ctx, key)
			if value ~= nil then return value end
		end
		return J.DETAIL.story[key]
	end
	local preset = J.DETAIL[detail] or J.DETAIL.story
	return preset[key]
end

-- Change one setting: the current preset becomes a custom one.
function J:SetShows(key, value)
	local db = A.db
	if not db then return end
	if db.detail ~= "custom" then
		local from = J.DETAIL[db.detail] or J.DETAIL.story
		db.show = {}
		for name, on in pairs(from) do db.show[name] = on end
		db.detail = "custom"
	end
	db.show[key] = value
	A:MarkDirty("settings")
end

-- Armor types for the loot filter, by Enum.ItemArmorSubclass. Weapons,
-- rings, cloaks and the rest have none and always show.
J.ARMOR = { 1, 2, 3, 4 }

local function ArmorShown(row, ctx)
	local armor = tonumber(row.armor)
	if not armor then return true end
	local hidden = Setting(ctx, "lootArmor")
	return not (type(hidden) == "table" and hidden[armor] == false)
end

local function SearchHit(row, word)
	for key, value in pairs(row) do
		if key ~= "kind" and type(value) == "string" and E:FoldText(value):find(word, 1, true) then return true end
	end
	return false
end

-- ctx (all optional): detail, show, lootMin, repMin, lootArmor (settings
-- to use instead of the module's), group ("all" or a group), kinds (set),
-- search (text), keepsakes (only keepsake rows).
function J:Shown(row, ctx)
	if type(row) ~= "table" then return false end
	local def = KINDS[row.kind]
	if def and def.derived then return false end
	if def and def.show ~= "always" then
		if def.show == "loot" then
			local floor = tonumber(J:Shows("lootMin", ctx)) or 4
			if (tonumber(row.quality) or 4) < floor then return false end
			if not ArmorShown(row, ctx) then return false end
		elseif def.show == "rep" then
			if J:Shows("repMin", ctx) == "honored" and not (row.keep or (tonumber(row.standing) or 0) >= 6) then
				return false
			end
		elseif not J:Shows(def.show, ctx) then
			return false
		end
	end
	if ctx then
		if ctx.group and ctx.group ~= "all" and not (def and def.group == ctx.group) then return false end
		if type(ctx.kinds) == "table" and not ctx.kinds[row.kind] then return false end
		if ctx.keepsakes and not self:IsKeepsake(row) then return false end
		if type(ctx.search) == "string" and ctx.search ~= "" then
			local word = E:FoldText(ctx.search)
			if word ~= "" and not SearchHit(row, word) then return false end
		end
	end
	return true
end

function J:IsKeepsake(row)
	if type(row) ~= "table" then return false end
	if A.db and A.db.keepsakes == false then return false end
	if row.keep then return true end
	local def = KINDS[row.kind]
	if def and type(def.keepsake) == "function" then
		local ok, yes = pcall(def.keepsake, row)
		return ok and yes and true or false
	end
	return false
end

-- The order when the journal must make room: plain rows go
-- first, then deaths and arrivals; levels, goals, notes and keepsakes last.
function J:Worth(row)
	if type(row) ~= "table" then return 1 end
	if row.keep then return 3 end
	local def = KINDS[row.kind]
	if def and def.worth >= 3 then return 3 end
	if self:IsKeepsake(row) then return 3 end
	return def and def.worth or 1
end

-- May the row fold into its chapter's summary?
function J:Rollable(row)
	local def = KINDS[row and row.kind]
	if not (def and def.rollup) or row.keep then return false end
	return not self:IsKeepsake(row)
end

function J:LinkFor(row)
	local def = KINDS[row and row.kind]
	local link = def and def.link
	if not link then return nil end
	local kind, field, fixed = link[1], link[2], link[3]
	if kind == "moment" then return self:Address("moment", row.seq) end
	if fixed then return self:Address(kind, fixed) end
	local id = field and row[field]
	if id == nil or id == "" then return nil end
	return self:Address(kind, id)
end
