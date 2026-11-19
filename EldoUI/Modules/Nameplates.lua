-- EldoUI Nameplates: restyles Blizzard's nameplates
-- with a slim EldoUI bar, the name above it, a cast bar under it, your
-- debuffs on top and a few extra icons (quest mob, elite/rare, totem, PvP
-- faction, portrait), colored by what the game says the unit is
-- (reaction, tapped, classification, quest mob, mana user, enemy player
-- class, threat state).
--
-- Plate types: enemy NPCs, enemy players, friendly NPCs and
-- friendly players each have their own size, texts (tag strings),
-- cast bar layout, aura sizes and extras, with "copy settings from" and a
-- test plate. Your own plate stays Blizzard's personal resource display
-- (Player Power owns its switch).
--
-- Style filters: an ordered rule list. Each rule has triggers and
-- actions; for every action the first matching rule wins. Triggers only
-- read facts the game shows the player and that Lua may read: reaction,
-- player or NPC, classification, target / focus / mouse-over, combat, a
-- plain level, raid marker, quest mob, totem or pet, your role, spec and
-- instance type, plate behind the camera, and names or NPC IDs outside
-- instances only. Dropped by rule (Forever / Midnight): health or power
-- thresholds, enemy casts (whether and what they cast), auras on enemies,
-- threat values, and names or NPC IDs inside instances.
--
-- Blizzard element switches (Core/Blizzard.lua, element "nameplates"):
--   master off  nothing here touches Blizzard's plates or the plate CVars.
--   replace     EldoUI plates: our own frame on every plate, Blizzard's art
--               faded to alpha 0 ("EldoUI style").
--   skin        Blizzard's own plates with EldoUI's bar texture, background,
--               border and font ("Blizzard style with the EldoUI look").
--   improve     extra icons (quest mob, elite/rare, totem) on Blizzard's
--               plates. EldoUI plates show them through their own settings.
--   hide        the "which plates show" CVars (enemies, friends, minions,
--               always show, friendly name only, enemy plates in combat).
--   move        stacking, distance, Blizzard plate size and clickable area.
-- Every CVar goes through E:SetCVar(name, value, "nameplates"), so turning
-- the element back to Blizzard default puts the player's own values back.
--
-- How it hooks in: for every NAME_PLATE_UNIT_ADDED we put our own plain
-- (non-secure) frame on the nameplate. We never move, resize or reparent
-- Blizzard's nameplate or its children and never write fields into them.
-- The skin hooks Blizzard's NamePlateUnitFrameMixin with hooksecurefunc and
-- checks the switches every time it runs. Forbidden plates (friendly plates
-- inside instances) are not handed to addons and stay Blizzard's.
--
-- WoW: Forever follows the Midnight rules: in combat many unit values are
-- "secret". Bars and text setters take secrets directly; texts go through
-- the tag engine, which only uses the game's own formatters. Anything we
-- would compare or calculate is first checked with issecretvalue() and
-- skipped when secret (a style filter trigger that can't be read simply
-- doesn't match). Cast bars and aura timers run on Blizzard's duration
-- objects; colors and visibility driven by secret booleans go through
-- C_CurveUtil.EvaluateColorFromBoolean, SetVertexColorFromBoolean and
-- SetAlphaFromBoolean. Auras are picked only by the client's own filters.
--
-- Effects: one Effects tab on the shared engine
-- (Core/UnitFX.lua) with the presets Off, Subtle, Standard and Vivid:
-- cast bar fade and spark, quest icon pop, aura pop-in, threat border (a
-- line under your target) with a pulse at danger, "another tank has it",
-- execute shade (opt-in), absorb shield, the important cast glow (shared
-- General > Glows look), the interrupter's name and the important cast
-- sound (opt-in). Threat, execute and absorb go through the engine's
-- curves and gates, so secret values only ever reach the client's sinks.
--
-- Size and click area live in Modules/Nameplates/Size.lua:
-- the real plate size (C_NamePlate.SetNamePlateSize), friendly click-
-- through and Situations, all out of combat. Blizzard's widgets stay
-- visible: widgets-only units keep Blizzard's plate, normal plates
-- get an EldoUI-owned widget container.
--
-- Written from scratch for EldoUI.
local _, E = ...
local L = E.L

-- The effects the plates offer (Core/UnitFX.lua). The engine's presets
-- already match the plate table (plan 3.5); execute shade and the
-- important cast sound stay off in every preset (opt-in only).
local FX_CONSUMER = "Nameplates"
local FX_EFFECTS = { "castFade", "castSpark", "questPop", "auraPop", "threat", "anotherTank", "execute", "absorb",
	"importantGlow", "interrupter", "importantSound" }
E:RegisterUnitFXPresets(FX_CONSUMER, {}, FX_EFFECTS)

local ELEMENT = "nameplates"
local TOTEM_CREATURE_TYPE = 11 -- creature type ID of totems (C_CreatureInfo)

-- Plate types, in tab order.
local TYPES = { "enemyNPC", "enemyPlayer", "friendlyNPC", "friendlyPlayer" }
local TYPE_TITLES = {
	enemyNPC = E.Key("Enemy NPCs"), enemyPlayer = E.Key("Enemy players"),
	friendlyNPC = E.Key("Friendly NPCs"), friendlyPlayer = E.Key("Friendly players"),
}

local function TypeDefaults(key)
	local enemy = key == "enemyNPC" or key == "enemyPlayer"
	return {
		enabled = true,            -- EldoUI styles this type (off: Blizzard's plate)
		nameOnly = false,          -- just the name, no bar
		width = 140,
		height = 12,
		combatWidth = 0,           -- size while you are in combat, 0 keeps the normal size
		combatHeight = 0,
		nameText = "LEFT",         -- "LEFT", "CENTER" or "NONE"
		nameTag = { preset = "name", custom = "" },
		healthTag = { preset = "healthpercent", custom = "" },
		healthPosition = "RIGHT",  -- "LEFT", "CENTER" or "RIGHT" inside the bar
		healthSize = 0,            -- 0 = the plate text size, made to fit a thin bar
		levelTag = { preset = "off", custom = "" },
		title = false,             -- NPC title line (outside instances)
		portrait = false,          -- class icon for players, portrait for NPCs
		pvp = key == "enemyPlayer" and "PVP" or "NONE", -- "NONE", "PVP" (flagged) or "FACTION" (always)
		power = false,             -- thin power bar under the health bar
		powerHeight = 3,
		raidMarker = true,
		icons = true,              -- elite/rare, quest and totem icons
		castbar = {
			enabled = true, height = 10, nameSize = 10, timeSize = 10,
			icon = "LEFT",          -- "LEFT", "RIGHT" or "NONE"
			iconSize = 0,           -- 0 = as tall as the cast bar
			time = "REMAINING",     -- "REMAINING", "TOTAL" (1.2 / 2.5) or "NONE"
			hold = 0.6,             -- seconds the "Interrupted" strip stays
		},
		debuffs = { enabled = true, size = 22, max = 6 },
		buffs = { enabled = enemy, size = 18, max = 4 },
	}
end

local TYPE_DEFAULTS = {}
for _, key in ipairs(TYPES) do TYPE_DEFAULTS[key] = TypeDefaults(key) end

local M = E:NewModule("Nameplates", {
	title = "Nameplates",
	desc = "Slim nameplates per unit type, with cast bar, your debuffs, quest and elite icons, style filters and a target highlight.",
	conflicts = { "Plater", "TidyPlates_ThreatPlates", "Kui_Nameplates", "EllesmereUINameplates", "ElvUI" },
	-- Its plates are pooled on Blizzard's own plates: no named frame or mover.
	frames = {},
	movers = {},
	blizzard = { "nameplates" },
	savedKeys = { "profile.modules.Nameplates" },
	optionsPage = "module:Nameplates",
	presets = { "Big", "Blizzard", "EldoUI", "Headline", "Slim", "Tank", "TwilightSlim" },
	-- Blizzard's skinned plates only lose the EldoUI look after a /reload.
	reload = { skin = true },
	themed = "OnThemeChanged",
	defaults = {
		schema = 0,                -- settings version (M:Migrate)
		offsetY = 0,
		texture = "theme",         -- "theme" (the General page's bar texture) or a media registry id
		font = "THEME",            -- "THEME" or a font id from the media registry
		fontOutline = "THEME",     -- "THEME", "NONE", "OUTLINE" or "THICKOUTLINE"
		fontSize = 11,
		nameColor = "WHITE",       -- "WHITE" or "REACTION" (class color for players)
		raidMarkerSize = 18,
		testType = "enemyNPC",     -- which type the test plate shows
		types = TYPE_DEFAULTS,
		targetIndicator = "BORDER", -- "BORDER", "GLOW", "BOTH", "ARROWS", "UNDERLINE", "OVERLAY", "PULSE" or "NONE"
		targetAccent = true,       -- use the EldoUI accent for the highlight
		targetColor = { 1, 1, 1 },
		targetScale = 115,         -- percent
		nonTargetAlpha = 75,       -- percent, only while you have a target
		othersMode = "FADE",       -- other plates while you have a target: "FADE", "DIM" or "OFF"
		focusAsTarget = false,     -- your focus is not faded or dimmed either
		targetDetails = false,     -- your target's plate shows power, level, health and the cast target
		outOfCombatAlpha = 0,      -- percent for enemies not in combat, 0 = off
		minorScale = 100,          -- percent for minor (trivial) units
		petScale = 85,             -- percent for pets, guardians and summons
		simplifyMinor = false,     -- minor units get a name-only plate
		focusIndicator = true,
		focusColor = { 1.00, 0.49, 0.04 },
		mouseoverHighlight = true,
		softTargetHighlight = false, -- the mouse-over look on your soft enemy's plate
		colors = {
			classHostile = true,
			classFriendly = true,
			playerBorder = true,   -- players' plates wear a border in their class color
			byClassification = true,
			casters = true,
			byQuest = true,        -- (v0.5.0 used "quest" for both this and the color)
			-- Reaction colors from General > Colors (one red for
			-- unit frames, plates and the Colors page), or the three below.
			reactionSource = "general",
			hostile = { 0.80, 0.14, 0.14 },
			neutral = { 0.81, 0.72, 0.19 },
			friendly = { 0.17, 0.75, 0.29 },
			tapped = { 0.55, 0.55, 0.55 },
			elite = { 0.20, 0.90, 0.85 },  -- aqua, apart from the quest blue
			rare = { 1.00, 0.49, 0.00 },
			rareElite = { 0.93, 0.36, 0.78 },
			boss = { 0.52, 0.24, 0.98 },
			minor = { 0.60, 0.60, 0.60 },
			caster = { 0.23, 0.51, 0.96 },
			quest = { 0.40, 0.75, 1.00 },  -- light blue, never the friendly green
			byMiniboss = false,    -- lieutenants (UnitIsLieutenant) in their own color
			miniboss = { 0.72, 0.42, 0.96 },
			byHealth = false,      -- bar color from the health gradient (Colors page)
		},
		threat = {
			enabled = false,
			mode = "AUTO",         -- "AUTO" (by group role), "TANK" or "DPS"
			custom = false,        -- false: the threat colors of the Colors page
			good = { 0.20, 0.80, 0.20 },
			transition = { 1.00, 0.60, 0.00 },
			bad = { 1.00, 0.10, 0.10 },
		},
		castbar = {
			gap = 2,
			spellName = true,
			targetName = false,
			inFront = true,        -- a casting plate's cast bar draws over other plates
			color = { 1.00, 0.80, 0.00 },
			uninterruptibleColor = { 0.45, 0.45, 0.45 },
			shield = true,
			channelColorOn = false,
			channelColor = { 0.35, 0.75, 1.00 },
			showInterrupted = true,
			interruptedColor = { 0.85, 0.20, 0.20 },
		},
		auraCountSize = 0,         -- stack numbers on plate auras; 0 grows with the icon
		auraTimerSize = 0,         -- countdown numbers; 0 grows with the icon
		debuffs = {
			filter = E:AuraFilterDefaults("HARMFUL", "mine"),
			blizzardFilter = false, -- only debuffs Blizzard marks for nameplates
			spacing = 2,
			timer = true,
		},
		buffs = {
			mode = "DISPELLABLE",  -- "OFF", "DISPELLABLE", "IMPORTANT", "DEFENSIVES" or "ALL"
			position = "RIGHT",    -- "RIGHT" of the bar or "ABOVE" the debuffs
			spacing = 2,
			timer = true,
			highlight = true,      -- border color for stealable / enrage / magic
			stealableColor = { 0.25, 0.65, 1.00 },
			enrageColor = { 1.00, 0.35, 0.10 },
		},
		cc = {
			enabled = true,
			size = 24,
		},
		icons = {
			classification = true,
			classificationSize = 14,
			quest = true,
			questProgress = true,
			questSize = 14,
			totem = true,
			totemSize = 22,
			totemOnly = false,
			pvpSize = 16,
			pet = false,           -- a small paw by pets and guardians
		},
		styleFilters = {
			enabled = true,
			edit = 1,              -- the rule the editor shows
		},
		click = {
			width = 0,             -- extra clickable width (Move switch)
			height = 0,
			friendlyThrough = false, -- clicks pass through friendly plates
		},
		size = { width = 0, height = 0 }, -- Blizzard's real plate size, 0 keeps the game's
		distance = 41,             -- yards for the copied plate distance command (never set by EldoUI)
		cvars = {
			stacking = "KEEP",     -- enemies: "KEEP", "STACK" or "OVERLAP"
			friendlyStacking = "KEEP",
			showEnemies = "KEEP",  -- "KEEP", "ON" or "OFF" for every show* entry
			showEnemyMinions = "KEEP",
			showFriendlyPlayers = "KEEP",
			showFriendlyMinions = "KEEP",
			showFriendlyNpcs = "KEEP",
			showAll = "KEEP",
			friendlyNameOnly = "KEEP",
			enemiesInCombatOnly = false,
		},
		-- Blizzard's plate settings per kind of place (Hide / Move switches).
		situations = {
			enabled = false,
			world = { enemies = "KEEP", friends = "KEEP", stacking = "KEEP" },
			dungeon = { enemies = "KEEP", friends = "KEEP", stacking = "KEEP" },
			raid = { enemies = "KEEP", friends = "KEEP", stacking = "KEEP" },
			battleground = { enemies = "KEEP", friends = "KEEP", stacking = "KEEP" },
		},
		effects = E:UnitFXDefaults(FX_CONSUMER, "subtle"),
	},
})

-- A style filter rule: triggers, then actions. "any" (or 0) = no check.
local RULE_DEFAULTS = {
	enabled = true,
	name = "New rule",
	-- triggers
	reaction = "any",          -- "hostile", "neutral", "friendly"
	unitType = "any",          -- "player", "npc"
	classification = "any",    -- "normal", "elite", "rare", "rareelite", "worldboss", "minus"
	target = "any",            -- "yes" / "no" for the yes/no triggers
	focus = "any",
	mouseover = "any",
	playerCombat = "any",
	unitCombat = "any",
	quest = "any",
	behindCamera = "any",
	creature = "any",          -- "totem", "pet"
	role = "any",              -- "TANK", "HEALER", "DAMAGER"
	spec = 0,                  -- 0 any, 1 or 2 (talent group)
	instance = "any",          -- "none", "party", "raid", "pvp", "arena"
	levelMin = 0,
	levelMax = 0,
	names = "",                -- names or NPC IDs; outside instances only
	casting = "any",           -- the unit is casting or channeling (yes / no)
	-- Gated triggers: the game's answer may be secret, so Lua never
	-- tests it. A rule with one of these matches on its other triggers and
	-- draws its border color and glow inside a gate the client opens.
	castImportant = "any",     -- "yes": the running cast is one the game marks important
	executeZone = "any",       -- "yes": health under executeLower (the game evaluates it)
	executeLower = 20,
	-- actions
	healthColorOn = false, healthColor = { 1, 1, 1 },
	borderColorOn = false, borderColor = { 1, 1, 1 },
	nameColorOn = false, nameColor = { 1, 1, 1 },
	texture = "",              -- "" keeps the plate texture
	scale = 1,                 -- 1 keeps the size
	alpha = 0,                 -- 0 keeps the normal opacity
	hide = false,
	nameOnly = false,
	glow = "none",             -- "none", "glow" (Glows page) or "flash" (a pulse)
	raise = false,             -- draw over other plates
	threatBorder = "keep",     -- "keep", "border", "glow" or "off": the threat border on these plates
	execute = "keep",          -- "keep", "on" or "off": the execute shade on these plates
	sizeWidth = 0,             -- plate size in pixels, 0 keeps the type's
	sizeHeight = 0,
	castTarget = false,        -- show the spell's target under the cast bar
	dim = false,               -- a dark overlay that keeps the name readable
}
local MAX_RULES = 50

local plates = {}        -- unit token -> our plate
local pool = {}          -- Blizzard nameplate frame -> our plate (frames are reused)
local hiddenBlizzard = setmetatable({}, { __mode = "k" }) -- UnitFrame -> true while faded
local hooked = setmetatable({}, { __mode = "k" })         -- UnitFrame -> fade state, once its hooks are in
local skinBorders = setmetatable({}, { __mode = "k" })    -- UnitFrame -> our border frame
local driver = CreateFrame("Frame")
local db
local fighting = false   -- in combat: the type tabs' size in combat applies
local preview            -- the test plate, when shown

---------------------------------------------------------------------------
-- Plate callbacks, for modules that hang their own pieces on plates
-- (Player Power's combo points, Combat Text's plate numbers):
--   M:RegisterPlateCallback([owner,] fn)   one callback per owner
--   M:UnregisterPlateCallback(owner or fn)
--   fn(event, unit, nameplate, kind)
--     ADDED    a plate for `unit` was set up (kind: "FULL", "NAME",
--              "EXTRAS", or false when EldoUI draws nothing on it)
--     REMOVED  the plate of `unit` went away
--     LAYOUT   EldoUI laid the plate of `unit` out again (sizes, offsets)
--     MODE     the plate mode changed: unit and nameplate are nil, kind is
--              "ELDOUI", "BLIZZARD" or "OFF"; every plate is set up anew
-- Forbidden plates (friendly plates in instances) are never reported.
-- M:GetPlateAnchor(unit[, "text"]) says where to hang a piece.
---------------------------------------------------------------------------
-- The list is replaced, never changed in place, so a callback that
-- registers or unregisters while the list is walked is safe.
local plateCallbacks = {} -- list of { owner, fn }

function M:RegisterPlateCallback(owner, fn)
	if fn == nil then owner, fn = nil, owner end
	if type(fn) ~= "function" then error("RegisterPlateCallback([owner,] fn): fn must be a function", 2) end
	owner = owner or fn
	local list, found = {}, false
	for index, entry in ipairs(plateCallbacks) do
		if entry.owner == owner then
			entry = { owner = owner, fn = fn }
			found = true
		end
		list[index] = entry
	end
	if not found then list[#list + 1] = { owner = owner, fn = fn } end
	plateCallbacks = list
end

function M:UnregisterPlateCallback(owner)
	local list = {}
	for _, entry in ipairs(plateCallbacks) do
		if entry.owner ~= owner and entry.fn ~= owner then list[#list + 1] = entry end
	end
	plateCallbacks = list
end

local function FirePlateCallback(event, unit, nameplate, kind)
	local list = plateCallbacks
	for index = 1, #list do
		local entry = list[index]
		local ok, err = pcall(entry.fn, event, unit, nameplate, kind)
		if not ok then geterrorhandler()(err) end
	end
end

---------------------------------------------------------------------------
-- Secret-safe helpers
---------------------------------------------------------------------------
local IsSecret = E.Secret

-- Returns the value when Lua may compare or calculate with it, else nil.
local Plain = E.Plain

-- Calls a game API that may be missing on this client and returns its
-- first result as a plain value (nil when missing, failing or secret).
local function Query(fn, ...)
	if not fn then return nil end
	local ok, value = pcall(fn, ...)
	if not ok then return nil end
	return Plain(value)
end

-- True when a value exists. A secret is never nil, so it counts as present.
local function Present(value)
	if IsSecret(value) then return true end
	return value ~= nil
end

-- A boolean for the *FromBoolean widget setters: secrets pass straight
-- through, plain values become true/false (nil counts as false).
local function Bool(value)
	if IsSecret(value) then return value end
	return value and true or false
end

-- Show a region when `value` is true. A secret boolean can't be tested in
-- Lua, so the region stays shown and the client sets its alpha from it.
local function ShowFromBoolean(region, value)
	if IsSecret(value) then
		region:Show()
		if not (region.SetAlphaFromBoolean and pcall(region.SetAlphaFromBoolean, region, value, 1, 0)) then
			region:Hide()
		end
		return
	end
	region:SetAlpha(1)
	region:SetShown(value and true or false)
end

local function RGB(color)
	return color[1], color[2], color[3]
end

local function Allowed(action)
	return E:BlizzardAllowed(ELEMENT, action)
end

-- Hostile / neutral / friendly bar and name colors: the
-- reaction colors of General > Colors (the player's picks, then the
-- color-blind safe set, then the game's) unless "own colors" is chosen.
function M.ReactionColor(reaction)
	local colors = db.colors
	if colors.reactionSource ~= "own" then
		local r, g, b = E:GetReactionColor(reaction)
		if r then return r, g, b end
	end
	if reaction >= 5 then return RGB(colors.friendly) end
	if reaction <= 3 then return RGB(colors.hostile) end
	return RGB(colors.neutral)
end

-- "ELDOUI" (our plates), "BLIZZARD" (Blizzard's plates, maybe skinned or
-- with extra icons) or "OFF" (Blizzard default, or the module is off).
local function PlateMode()
	if not M.active or not Allowed() then return "OFF" end
	if Allowed("replace") then return "ELDOUI" end
	return "BLIZZARD"
end

local function PlateFor(token)
	if not C_NamePlate then return nil end
	local ok, frame = pcall(C_NamePlate.GetNamePlateForUnit, token)
	return ok and frame or nil
end

-- The settings of a plate's type.
-- Your target's plate with "Target plate details" (Target tab) reads a copy
-- of its type with the power bar, level, health current and percent, and
-- the cast target on, whatever the type tab says.
local detailTypes = {}

local function DetailType(key, t)
	local entry = detailTypes[key]
	if entry and entry.source == t then return entry.settings end
	local copy = CopyTable(t)
	copy.power = true
	copy.levelTag = { preset = "platelevel", custom = "" }
	copy.healthTag = { preset = "healthcurrentpercent", custom = "" }
	detailTypes[key] = { source = t, settings = copy }
	return copy
end

local function T(plate)
	local t = db.types[plate.typeKey] or db.types.enemyNPC
	if plate.isDetailTarget then return DetailType(plate.typeKey, t) end
	return t
end

local function InInstance()
	local ok, inside, kind = pcall(IsInInstance)
	if not ok or IsSecret(inside) then return true, nil end -- unknown counts as inside
	return inside and true or false, Plain(kind)
end

---------------------------------------------------------------------------
-- Fonts: the theme font unless the player picks one for nameplates.
---------------------------------------------------------------------------
local OUTLINES = { NONE = "", OUTLINE = "OUTLINE", THICKOUTLINE = "THICKOUTLINE" }

-- Fonts and bar textures come from the media registry, so EldoUI's
-- own media and any SharedMedia pack can be picked; a missing one falls
-- back to the theme's.
local function SetPlateFont(fontString, size)
	local outline = OUTLINES[db.fontOutline] or E.db.general.fontOutline
	E:SetMediaFont(fontString, db.font ~= "THEME" and db.font or nil, size, outline)
end

-- Every text that can carry letters of another alphabet (the unit's name,
-- the NPC title, the spell being cast, its target, who interrupted it, the
-- quest line) takes the name font: the same font for Latin letters and the
-- game's own font for other alphabets, so no text turns into empty boxes
-- (E:SetNameFont). Numbers keep the plain plate font.
local function SetPlateNameFont(fontString, size)
	local outline = OUTLINES[db.fontOutline] or E.db.general.fontOutline
	local path = not E:IsThemeFont(db.font) and E:FetchMedia("font", db.font) or E.media.font
	if not E:SetNameFont(fontString, path or E.media.font, size or E.db.general.fontSize, outline) then
		SetPlateFont(fontString, size)
	end
end

-- Every part of a plate has its own row: name and level, the NPC title,
-- debuffs, buffs above the bar; power and cast bar under it. M.ROW_GAP is the
-- space between two rows, measured from the one-pixel border every bar
-- draws outside itself, so neighbors never touch at any UI scale.
M.ROW_GAP = 2
M.OUTLINE_ROOM = { [""] = 0, OUTLINE = 1, THICKOUTLINE = 2 }

-- Height of one line of plate text: the glyphs with their descenders and
-- the outline drawn around them.
function M.TextRow(size)
	local outline = OUTLINES[db.fontOutline] or E.db.general.fontOutline or ""
	return math.ceil(size * 1.25) + (M.OUTLINE_ROOM[outline] or 1) * 2
end

local function PlateTexture(name)
	if not name or name == "" or name == "theme" then return E.media.statusbar end
	return E:FetchMedia("statusbar", name) or E.media.statusbars[name] or E.media.statusbar
end
M.PlateTexture = PlateTexture

---------------------------------------------------------------------------
-- Health color, in priority order:
--   0 style filter color          7 rare
--   1 tapped by someone else       8 quest mob
--   2 another tank has it (tanks)  9 mana user (caster)
--   3 threat (option, off)        10 elite, minor
--   4 color by health (off)      11 reaction: hostile / neutral
--   5 player class color / friendly
--   6 boss, rare elite, lieutenant
-- Every input is something the game shows the player (classification
-- dragon, quest marker, mana bar, threat glow). Nothing is guessed from
-- names, NPC IDs or combat events.
---------------------------------------------------------------------------
-- The three local threat colors ("Own threat colors") per threat status
-- 0-3: for a tank's status, for everyone else's, and for a tank's lead
-- over second place (0 safe, 3 not first).
local THREAT_COLORS = {
	tank = { [0] = "bad", [1] = "transition", [2] = "transition", [3] = "good" },
	dps = { [0] = "good", [1] = "transition", [2] = "bad", [3] = "bad" },
	lead = { [0] = "good", [1] = "transition", [2] = "transition", [3] = "bad" },
}

-- The player's role: group role, else the spec's role.
local function PlayerRole()
	local role = Query(UnitGroupRolesAssigned, "player")
	if role and role ~= "NONE" then return role end
	local specInfo = C_SpecializationInfo
	if specInfo and specInfo.GetSpecialization and specInfo.GetSpecializationInfo then
		local spec = Query(specInfo.GetSpecialization)
		if spec then
			local ok, _, _, _, _, specRole = pcall(specInfo.GetSpecializationInfo, spec)
			if ok then return Plain(specRole) end
		end
	end
	return nil
end

local function IsTankMode()
	local mode = db.threat.mode
	if mode == "TANK" then return true end
	if mode == "DPS" then return false end
	return E:PlayerIsTank() or PlayerRole() == "TANK"
end

-- Colors per threat status for the engine's threat curve
-- (E:UnitCurve("threat")). `safe` is the color of the safe status: the
-- plate's normal color on the bar, false on a border (no border then).
-- With "Own threat colors" the safe status of the bar keeps "Safe".
local function ThreatOverrides(role, safe)
	local colors = {}
	local threat = db.threat
	if threat.custom then
		local map = THREAT_COLORS[role] or THREAT_COLORS.dps
		for status = 0, 3 do colors[status] = threat[map[status]] end
	end
	if safe == false or (type(safe) == "table" and not threat.custom) then colors[role == "tank" and 3 or 0] = safe end
	return colors
end

-- The bar color for the game's threat status. The status may be secret:
-- the client evaluates the step curve, Lua never reads the number. nil
-- when threat colors are off or the unit isn't on your threat table.
local function ThreatResult(unit, r, g, b)
	if not db.threat.enabled or not UnitThreatSituation then return nil end
	local status, role = E:ThreatStatusFor("player", unit, IsTankMode())
	if type(status) == "nil" then return nil end
	local spec = { role = role, full = true, colors = ThreatOverrides(role, { r, g, b }) }
	local result = E:UnitCurveEval("threat", status, spec)
	if type(result) ~= "nil" or IsSecret(status) then return result end
	-- No curve API on this client: the plain status picks the color.
	local own = spec.colors[status]
	if type(own) == "table" then return CreateColor(RGB(own)) end
	local key = status
	if role == "tank" then key = ({ [0] = 3, [1] = 2, [2] = 1 })[status] or 0 end
	local cr, cg, cb = E:GetThreatStatusColor(key)
	if type(cr) == "number" then return CreateColor(cr, cg, cb) end
	return nil
end

-- "Another tank has it" (Effects): the other tanks of your group, kept
-- while the group changes. Only plain threat statuses are compared; when
-- one of them is secret the plate keeps the threat curve color.
local otherTanks = {}

local function RebuildTanks()
	wipe(otherTanks)
	local raid = Query(IsInRaid)
	local prefix, count = raid and "raid" or "party", raid and 40 or 4
	for index = 1, count do
		local unit = prefix .. index
		if Query(UnitExists, unit) and not Query(UnitIsUnit, unit, "player") and Query(UnitGroupRolesAssigned, unit) == "TANK" then
			otherTanks[#otherTanks + 1] = unit
		end
	end
end

local function OffTankHolds(unit)
	local fx = db.effects.anotherTank
	if not (fx and fx.enabled) or not UnitThreatSituation or #otherTanks == 0 or not IsTankMode() then return false end
	local ok, mine = pcall(UnitThreatSituation, "player", unit)
	if not ok or IsSecret(mine) then return false end
	if type(mine) == "number" and mine >= 2 then return false end
	for _, tank in ipairs(otherTanks) do
		local okTank, status = pcall(UnitThreatSituation, tank, unit)
		if okTank and not IsSecret(status) and type(status) == "number" and status >= 2 then return true end
	end
	return false
end

-- Reaction 1-8 as a plain number; friend/foe as a fallback.
local function Reaction(unit)
	local reaction = Query(UnitReaction, unit, "player")
	if reaction then return reaction end
	return Query(UnitIsFriend, "player", unit) and 5 or 4
end

local function ClassToken(unit)
	local ok, _, class = pcall(UnitClass, unit)
	return ok and Plain(class) or nil
end

local function ClassColor(unit)
	local class = ClassToken(unit)
	local color = E:ClassColorObject(class)
	if color then return color.r, color.g, color.b end
end

-- The plate's normal color (plain r, g, b) and whether the danger colors
-- (another tank, threat) may paint over it: an enemy NPC nobody else tapped.
local function HealthColor(unit)
	local colors = db.colors
	if Query(UnitIsTapDenied, unit) then
		local r, g, b = RGB(colors.tapped)
		return r, g, b, false
	end

	local isPlayer = Query(UnitIsPlayer, unit)
	local reaction = Reaction(unit)
	local friendly = reaction >= 5
	local enemyNPC = not friendly and not isPlayer

	if isPlayer and ((friendly and colors.classFriendly) or (not friendly and colors.classHostile)) then
		local r, g, b = ClassColor(unit)
		if r then return r, g, b, false end
	end

	if friendly then
		local r, g, b = M.ReactionColor(reaction)
		return r, g, b, false
	end

	if not isPlayer then
		local classification = colors.byClassification and Query(UnitClassification, unit)
		local pick
		if classification == "worldboss" then
			pick = colors.boss
		elseif classification == "rareelite" then
			pick = colors.rareElite
		elseif colors.byMiniboss and Query(UnitIsLieutenant, unit) then
			pick = colors.miniboss
		elseif classification == "rare" then
			pick = colors.rare
		elseif colors.byQuest and C_QuestLog and Query(C_QuestLog.UnitIsRelatedToActiveQuest, unit) then
			pick = colors.quest
		elseif colors.casters and Enum.PowerType and Query(UnitPowerType, unit) == Enum.PowerType.Mana then
			pick = colors.caster
		elseif classification == "elite" then
			pick = colors.elite
		elseif classification == "minus" then
			pick = colors.minor
		end
		if pick then
			local r, g, b = RGB(pick)
			return r, g, b, enemyNPC
		end
	end

	local r, g, b = M.ReactionColor(reaction)
	return r, g, b, enemyNPC
end
-- Name color: white, or class color for players and reaction color
-- for NPCs ("REACTION", and always on name-only plates).
local function NameColor(plate)
	local filter = plate.filter
	if filter and filter.nameColor then return RGB(filter.nameColor) end
	if db.nameColor ~= "REACTION" and plate.kind ~= "NAME" then return 1, 1, 1 end
	local unit = plate.unit
	if Query(UnitIsPlayer, unit) then
		local r, g, b = ClassColor(unit)
		if r then return r, g, b end
	end
	return M.ReactionColor(Reaction(unit))
end

local function PowerColor(unit)
	local ok, _, token = pcall(UnitPowerType, unit)
	token = ok and Plain(token)
	local color = type(token) == "string" and E:PowerColorObject(token)
	if color then return color.r, color.g, color.b end
	return 0.2, 0.4, 1
end

---------------------------------------------------------------------------
-- Element updates
---------------------------------------------------------------------------
-- `instant`: a plate that was just set up for a new unit jumps to its value
-- instead of gliding from the previous unit's.
local function UpdateHealth(plate, instant)
	if plate.kind ~= "FULL" then return end
	local unit, bar = plate.unit, plate.health
	pcall(bar.SetMinMaxValues, bar, 0, UnitHealthMax(unit))
	pcall(bar.SetValue, bar, UnitHealth(unit), E:BarInterpolation(instant and "off" or nil))
end

local function UpdatePower(plate)
	if plate.kind ~= "FULL" or not plate.power:IsShown() then return end
	local unit, bar = plate.unit, plate.power
	pcall(bar.SetMinMaxValues, bar, 0, UnitPowerMax(unit))
	pcall(bar.SetValue, bar, UnitPower(unit))
	bar:SetStatusBarColor(PowerColor(unit))
end

-- The bar color (priority list above). Curve colors (threat, color by
-- health) may come back secret: only the bar's color setter sees them.
local function UpdateColor(plate)
	if plate.kind ~= "FULL" then return end
	local bar = plate.health
	local filter = plate.filter
	if filter and filter.healthColor then
		bar:SetStatusBarColor(RGB(filter.healthColor))
		return
	end
	local unit = plate.unit
	local ok, r, g, b, danger = pcall(HealthColor, unit)
	if not ok or type(r) ~= "number" then return end
	if danger then
		if OffTankHolds(unit) then
			bar:SetStatusBarColor(E:GetStatusColor("offTank"))
			return
		end
		local threat = ThreatResult(unit, r, g, b)
		if type(threat) ~= "nil" and E:PaintColorResult(bar, threat, "SetStatusBarColor") then return end
	end
	if db.colors.byHealth and not Query(UnitIsTapDenied, unit) then
		local result = E:UnitCurveHealth(unit, "healthGradient")
		if type(result) ~= "nil" and E:PaintColorResult(bar, result, "SetStatusBarColor") then return end
	end
	bar:SetStatusBarColor(r, g, b)
end

---------------------------------------------------------------------------
-- Danger effects (Effects tab, Core/UnitFX.lua). Each one draws in a gate,
-- an EldoUI frame on the plate made on first use; the game's threat state,
-- health and important flag only ever reach the gate's sinks.
---------------------------------------------------------------------------
local function FX(key)
	return db.effects[key]
end

local function Gate(plate, field, parent, level)
	local gate = plate[field]
	if not gate then
		gate = E:CreateGate(parent, level)
		plate[field] = gate
	end
	return gate
end

local function ClearGate(plate, field)
	local gate = plate[field]
	if gate then gate:Clear() end
end

-- A style filter can switch the threat border or the execute shade per
-- plate. Its "on" reads the Effects tab for everything else.
local ThreatSettings, ExecuteSettings
do
local THREAT_RULE_STYLE = { border = "BORDER", glow = "GLOW" }
local ruleThreat = setmetatable({}, { __index = function(_, key)
	if key == "enabled" then return true end
	if key == "style" then return "BORDER" end
	return db.effects.threat[key]
end })
local ruleThreatGlow = setmetatable({}, { __index = function(_, key)
	if key == "enabled" then return true end
	if key == "style" then return "GLOW" end
	return db.effects.threat[key]
end })
local ruleExecute = setmetatable({}, { __index = function(_, key)
	if key == "enabled" then return true end
	return db.effects.execute[key]
end })

function ThreatSettings(plate)
	local rule = plate.filter and plate.filter.threatBorder
	if rule == "off" then return nil end
	if THREAT_RULE_STYLE[rule] == "GLOW" then return ruleThreatGlow end
	if THREAT_RULE_STYLE[rule] then return ruleThreat end
	return FX("threat")
end

function ExecuteSettings(plate)
	local rule = plate.filter and plate.filter.execute
	if rule == "off" then return nil end
	if rule == "on" then return ruleExecute end
	return FX("execute")
end
end

-- Threat border (non-target plates) or a thin line under your target's
-- bar. "Another tank has it" paints the calm color instead when both
-- threat statuses are plain.
local function UpdateThreatFX(plate)
	local settings = plate.kind == "FULL" and plate.enemyNPC and not plate.totemOnly and ThreatSettings(plate)
	if not (settings and settings.enabled) then
		ClearGate(plate, "threatGate")
		ClearGate(plate, "threatLine")
		return
	end
	local tank = IsTankMode()
	local onTarget = plate.isTarget and true or false
	local gate
	if onTarget then
		ClearGate(plate, "threatGate")
		gate = Gate(plate, "threatLine", plate.threatLineHolder, 2)
	else
		ClearGate(plate, "threatLine")
		gate = Gate(plate, "threatGate", plate.health.bg, 3)
	end
	if not gate then return end
	if OffTankHolds(plate.unit) then
		if gate.pulseGate then gate.pulseGate:Clear() end
		gate:Pulse(false)
		gate:SetLook((onTarget or settings.style == "TINT") and "TINT" or "BORDER", { alpha = onTarget and 1 or nil })
		gate:FromColor(CreateColor(E:GetStatusColor("offTank")))
		return
	end
	local lineSettings = onTarget and { enabled = true, style = "TINT", pulse = settings.pulse } or settings
	E:UnitFXThreat(gate, "player", lineSettings, {
		role = tank and "tank" or "dps", other = plate.unit,
		colors = ThreatOverrides(tank and (UnitThreatLeadSituation and "lead" or "tank") or "dps", false), tint = onTarget and 1 or nil,
		mark = not onTarget, markSize = 10,
	})
end

-- Execute shade (opt-in): the zone and divider sit where the setting puts
-- them; the game's curve evaluation says whether the unit is inside.
local function UpdateExecute(plate)
	local settings = plate.kind == "FULL" and not plate.friendly and not plate.totemOnly and ExecuteSettings(plate)
	if not (settings and settings.enabled) then
		ClearGate(plate, "executeGate")
		ClearGate(plate, "executeUpper")
		return
	end
	E:UnitFXExecute(Gate(plate, "executeGate", plate.health, 1), plate.unit, settings,
		Gate(plate, "executeUpper", plate.health, 1))
end

-- Absorb shield over the health fill, from the game's calculator.
local function UpdateAbsorb(plate)
	local fx = FX("absorb")
	local on = plate.kind == "FULL" and not plate.totemOnly and fx and fx.enabled
	if not on then
		if plate.absorb then E:UpdateAbsorb(plate.unit, plate.absorb, false) end
		return
	end
	plate.absorb = plate.absorb or E:AttachAbsorb(plate.health)
	E:UpdateAbsorb(plate.unit, plate.absorb, true)
end

local UpdateRuleGates -- style filter gates, defined with the filters

local function OnHealth(plate)
	UpdateHealth(plate)
	if db.colors.byHealth then UpdateColor(plate) end
	UpdateExecute(plate)
	UpdateAbsorb(plate)
	if plate.ruleGated then UpdateRuleGates(plate) end
end

local function OnThreat(plate)
	UpdateColor(plate)
	UpdateThreatFX(plate)
end
local function UpdateName(plate)
	if plate.kind == "EXTRAS" then return end
	plate.nameText:SetTextColor(NameColor(plate))
end

-- NPC title (Innkeeper, Flight Master) from the tag engine; it is empty
-- inside instances and for players.
local function UpdateTitle(plate)
	local text = plate.titleText
	if not text:IsShown() then return end
	E:RenderTag(text, "[npctitle]", plate.unit)
end

-- [name] on every plate follows this override.
E:RegisterNameFormatUser("Nameplates", { title = "Nameplates", order = 30,
	desc = "Name format of [name] on enemy and friendly player nameplates (NPCs have no surname). Names the game keeps secret are shown as they come." })

-- Texts through the tag engine: rendered now and again whenever one
-- of their tags' events fires for this unit.
local function BindTexts(plate)
	local t = T(plate)
	local unit = plate.unit
	local full = plate.kind == "FULL" and not plate.totemOnly
	local name = (plate.kind == "NAME" or (full and t.nameText ~= "NONE")) and E:TagForSlot(t.nameTag) or ""
	E:BindTag(plate.nameText, name, unit, "Nameplates")
	E:BindTag(plate.healthText, full and E:TagForSlot(t.healthTag) or "", unit, "Nameplates")
	E:BindTag(plate.levelText, full and E:TagForSlot(t.levelTag) or "", unit, "Nameplates")
	UpdateName(plate)
	UpdateTitle(plate)
end

local function UnbindTexts(plate)
	for _, text in ipairs({ plate.nameText, plate.healthText, plate.levelText }) do
		E:UnbindTag(text)
		text:SetText("")
	end
	plate.titleText:SetText("")
end

-- The raid marker index is secret in combat; the sprite cell setter takes
-- it as it is. A missing marker makes the setter fail, so the icon hides.
local RAID_ROWS, RAID_COLUMNS = 4, 4

local function UpdateRaidMarker(plate)
	local icon = plate.raidIcon
	if not T(plate).raidMarker or plate.kind == "EXTRAS" or not GetRaidTargetIndex then
		icon:Hide()
		return
	end
	local ok, index = pcall(GetRaidTargetIndex, plate.unit)
	if not ok or not Present(index) then
		icon:Hide()
		return
	end
	if icon.SetSpriteSheetCell and pcall(icon.SetSpriteSheetCell, icon, index, RAID_ROWS, RAID_COLUMNS) then
		icon:Show()
	elseif not IsSecret(index) and SetRaidTargetIconTexture then
		SetRaidTargetIconTexture(icon, index)
		icon:Show()
	else
		icon:Hide()
	end
end

---------------------------------------------------------------------------
-- Extra icons: elite/rare dragon, quest mob, totem, PvP faction and the
-- portrait. Atlas names are the ones Blizzard's own target frame and
-- nameplates use.
---------------------------------------------------------------------------
local CLASSIFICATION_ATLAS = {
	elite = "nameplates-icon-elite-gold",
	worldboss = "nameplates-icon-elite-gold",
	rareelite = "nameplates-icon-elite-silver",
	rare = "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Rare-Star",
}
local QUEST_ATLAS = "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Quest"
local PVP_ATLAS = {
	Alliance = "UI-HUD-UnitFrame-Player-PVP-AllianceIcon",
	Horde = "UI-HUD-UnitFrame-Player-PVP-HordeIcon",
	FFA = "UI-HUD-UnitFrame-Player-PVP-FFAIcon",
}

local function IsTotem(unit)
	if not UnitCreatureType then return false end
	local ok, _, id = pcall(UnitCreatureType, unit)
	return ok and Plain(id) == TOTEM_CREATURE_TYPE
end

-- Quest progress: the client already writes the objective lines into the
-- unit tooltip ("Bandit slain: 3/8"). Only those lines are read and the
-- first unfinished "x/y" or "x%" is shown as it is; nothing is counted here.
-- Tooltip data is not combat data, but every value still goes through Plain
-- so a secret line is simply skipped.
-- In a group the tooltip lists each member who has the quest under a
-- header with their name; only the objectives under the quest's title or
-- under your own name are yours.
local PlaceSideIcons

-- The progress is read once per unit and quest change, not on every
-- event that refreshes the icons (combat flags, roster, zone): each plate
-- keeps the text with the unit it was read for (its GUID, or, when the
-- game keeps the GUID hidden, that setup of the plate) and the quest log
-- change it belongs to. `epoch` goes up in one pass half a second after the last
-- quest event (see the events below): `first` and `due` are the times of the
-- run's first event and of its pass, nil while none waits.
local questState = { epoch = 1, serial = 0, first = nil, due = nil }

local function KeptQuestProgress(plate)
	if plate.questReadKey == plate.questKey and plate.questReadEpoch == questState.epoch then
		return plate.questProgress
	end
	local text = E:QuestUnitProgress(plate.unit) or false
	plate.questReadKey, plate.questReadEpoch, plate.questProgress = plate.questKey, questState.epoch, text
	return text
end

-- PvP badge on players: FFA, or the faction when flagged (or always).
local function PvPAtlas(unit, mode)
	if mode == "NONE" or not Query(UnitIsPlayer, unit) then return nil end
	if Query(UnitIsPVPFreeForAll, unit) then return PVP_ATLAS.FFA end
	if mode == "PVP" and not Query(UnitIsPVP, unit) then return nil end
	local ok, faction = pcall(UnitFactionGroup, unit)
	faction = ok and Plain(faction)
	return faction and PVP_ATLAS[faction] or nil
end

local function UpdatePortrait(plate)
	local portrait = plate.portrait
	if not portrait:IsShown() then return end
	local unit = plate.unit
	local class = Query(UnitIsPlayer, unit) and ClassToken(unit)
	local atlas = class and GetClassAtlas and GetClassAtlas(class)
	portrait.texture:SetTexCoord(0, 1, 0, 1)
	if atlas then
		portrait.texture:SetAtlas(atlas)
	elseif SetPortraitTexture and pcall(SetPortraitTexture, portrait.texture, unit) then
		local crop = E.tokens.portraitCrop -- the unit frames' crop
		portrait.texture:SetTexCoord(crop, 1 - crop, crop, 1 - crop)
	else
		portrait.texture:SetTexture(nil)
	end
end

local function UpdateIcons(plate)
	local icons, unit = db.icons, plate.unit
	local friendly = plate.friendly
	local on = T(plate).icons

	local classification = on and icons.classification and not friendly and plate.kind ~= "NAME"
		and Query(UnitClassification, unit)
	local atlas = classification and CLASSIFICATION_ATLAS[classification]
	if atlas then
		plate.classIcon:SetAtlas(atlas)
		plate.classIcon:Show()
	else
		plate.classIcon:Hide()
	end

	-- Quest mob: the same flags Blizzard's target frame and quest colors
	-- use. A secret answer drives the icon's alpha directly.
	local quest = plate.questIcon
	if on and icons.quest and not friendly and C_QuestLog and C_QuestLog.UnitIsRelatedToActiveQuest then
		local ok, related = pcall(C_QuestLog.UnitIsRelatedToActiveQuest, unit)
		if ok and Present(related) then
			ShowFromBoolean(quest, related)
		else
			quest:Hide()
		end
		-- Quest icon pop (Effects): only when a plain answer turns true
		-- while the plate is up, never on a secret or on the first look.
		local now = ok and Plain(related) == true
		local pop = FX("questPop")
		if now and plate.questWas == false and pop and pop.enabled and not plate.preview then E:PopIn(quest) end
		plate.questWas = ok and not IsSecret(related) and (now and true or false) or nil
		local progress = icons.questProgress and ok and Plain(related) == true and KeptQuestProgress(plate)
		if progress then
			plate.questText:SetText(progress)
			plate.questText:Show()
		else
			plate.questText:Hide()
		end
	else
		quest:Hide()
		plate.questText:Hide()
	end

	local totem = plate.totemIcon
	if on and icons.totem and plate.isTotem and SetPortraitTexture and pcall(SetPortraitTexture, totem, unit) then
		totem:Show()
	else
		totem:Hide()
	end

	-- Pet indicator: a unit a player controls that is not a player.
	local pet = on and icons.pet and plate.kind ~= "EXTRAS" and plate.isPet
	plate.petIcon:SetShown(pet and true or false)

	local pvpAtlas = plate.kind ~= "EXTRAS" and PvPAtlas(unit, T(plate).pvp)
	if pvpAtlas then
		plate.pvpIcon:SetAtlas(pvpAtlas)
		plate.pvpIcon:Show()
	else
		plate.pvpIcon:Hide()
	end
	UpdatePortrait(plate)
	PlaceSideIcons(plate)
end

---------------------------------------------------------------------------
-- Auras. Only the client's own filters decide what shows:
--   debuffs  the shared aura filter block (HARMFUL; presets Mine,
--            Important, Crowd control ...), optionally only the debuffs
--            Blizzard marks for nameplates
--   buffs    HELPFUL|RAID_PLAYER_DISPELLABLE (purge, steal, soothe enrage),
--            HELPFUL|IMPORTANT or HELPFUL, on enemies only
--   cc       HARMFUL|CROWD_CONTROL, the first one
-- Timers and stack counts come back from the client as duration objects and
-- display strings, so nothing secret is calculated here.
---------------------------------------------------------------------------
local STEAL_COLOR = CreateColor(0.25, 0.65, 1)
local filterVersion = 0  -- bumped when the account-wide spell lists change
-- Bumped with every settings, theme or spell list change: plates check
-- their aura containers again only after it moved.
local auraGen = 0
local ClearAuraContainers, UpdateAuras, OnAura

do
local BUFF_FILTERS = {
	DISPELLABLE = "HELPFUL|RAID_PLAYER_DISPELLABLE",
	IMPORTANT = "HELPFUL|IMPORTANT",
	DEFENSIVES = "HELPFUL|BIG_DEFENSIVE", -- the game's big defensive cooldowns
	ALL = "HELPFUL",
}

-- Dispel colors from General > Colors as plain { r, g, b } (container
-- settings are copied, so they hold no color objects).
local function DispelRGB()
	local map = {}
	for key, color in pairs(E:DispelColorMap() or {}) do
		if type(color) == "table" and color.GetRGB then map[key] = { color:GetRGB() } end
	end
	return map
end
local NO_COLOR = CreateColor(0, 0, 0, 0)
local NAMEPLATE_ONLY = "|INCLUDE_NAME_PLATE_ONLY"

local function DebuffGroups(max)
	return E:AuraFilterGroups(db.debuffs.filter, "HARMFUL", max,
		db.debuffs.blizzardFilter and { suffix = NAMEPLATE_ONLY } or nil)
end

-- First debuff filter, for the fallback icons (no containers).
local function DebuffFilter()
	local groups = DebuffGroups(1)
	return groups[1] and groups[1].filter or "HARMFUL|PLAYER"
end

local function CreateAuraIcon(plate)
	local icon = CreateFrame("Frame", nil, plate.root)
	E:SetTemplate(icon)
	-- Colored edge over the template border (stealable, enrage, magic).
	icon.edge = icon:CreateTexture(nil, "BORDER")
	icon.edge:SetAllPoints()
	icon.edge:SetTexture(E.media.flat)
	icon.edge:Hide()
	icon.texture = icon:CreateTexture(nil, "ARTWORK")
	icon.texture:SetPoint("TOPLEFT", E.pixel, -E.pixel)
	icon.texture:SetPoint("BOTTOMRIGHT", -E.pixel, E.pixel)
	E:TrimIcon(icon.texture)
	icon.cooldown = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
	icon.cooldown:SetAllPoints(icon.texture)
	icon.cooldown:SetDrawEdge(false)
	icon.cooldown:SetReverse(true)
	local countLayer = CreateFrame("Frame", nil, icon)
	countLayer:SetAllPoints()
	countLayer:SetFrameLevel(icon.cooldown:GetFrameLevel() + 2)
	icon.count = E:CreateText(countLayer, E.tokens.size.tiny, "RIGHT")
	icon.count:SetPoint("BOTTOMRIGHT", -1, 1)
	icon:Hide()
	return icon
end

-- Fill one icon from an aura: texture, swipe, stack count.
local function SetAuraIcon(icon, unit, aura, showTimer)
	pcall(icon.texture.SetTexture, icon.texture, aura.icon)

	local id = Plain(aura.auraInstanceID)
	local cooldown = icon.cooldown
	local duration
	if id and C_UnitAuras.GetAuraDuration then
		local okDuration, value = pcall(C_UnitAuras.GetAuraDuration, unit, id)
		if okDuration then duration = value end
	end
	if duration and cooldown.SetCooldownFromDurationObject then
		pcall(cooldown.SetCooldownFromDurationObject, cooldown, duration, true)
	else
		-- No duration object for this aura: plain numbers only.
		local expires, length = Plain(aura.expirationTime), Plain(aura.duration)
		if expires and length and length > 0 then
			cooldown:SetCooldown(expires - length, length)
		else
			cooldown:Clear()
		end
	end
	if cooldown.SetHideCountdownNumbers then cooldown:SetHideCountdownNumbers(not showTimer) end

	local count = ""
	if id and C_UnitAuras.GetAuraApplicationDisplayCount then
		local okCount, value = pcall(C_UnitAuras.GetAuraApplicationDisplayCount, unit, id)
		if okCount and Present(value) then count = value end
	else
		local stacks = Plain(aura.applications)
		if stacks and stacks > 1 then count = stacks end
	end
	pcall(icon.count.SetText, icon.count, count)
	icon.edge:Hide()
	icon:Show()
end

-- Enemy buff edge: stealable first (a secret flag is colored by the
-- client), then enrage and magic from Blizzard's dispel colors when the
-- dispel type is readable.
local function DispelColor(dispel)
	if dispel == "" or dispel == "Enrage" then return RGB(db.buffs.enrageColor) end
	local r, g, b = E:GetDispelColor(dispel)
	if type(r) == "number" then return r, g, b end
end

local function ColorBuffEdge(icon, aura)
	local edge = icon.edge
	if not db.buffs.highlight then return end
	local stealable = aura.isStealable
	if IsSecret(stealable) then
		edge:SetAlpha(1)
		edge:Show()
		if not (edge.SetVertexColorFromBoolean and pcall(edge.SetVertexColorFromBoolean, edge, stealable, STEAL_COLOR, NO_COLOR)) then
			edge:Hide()
		end
		return
	end
	local r, g, b
	if stealable then
		r, g, b = STEAL_COLOR:GetRGB()
	else
		local dispel = Plain(aura.dispelName)
		if dispel then r, g, b = DispelColor(dispel) end
	end
	if r then
		edge:SetVertexColor(r, g, b, 1)
		edge:SetAlpha(1)
		edge:Show()
	end
end

-- Read up to `max` auras through one Blizzard filter into an icon list.
local function FillAuras(plate, icons, filter, max, showTimer, colorEdge)
	local shown = 0
	if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
		local unit = plate.unit
		for index = 1, 40 do
			if shown >= max then break end
			local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, unit, index, filter)
			if not ok or not aura then break end
			shown = shown + 1
			local icon = icons[shown]
			if not icon then
				icon = CreateAuraIcon(plate)
				icons[shown] = icon
			end
			SetAuraIcon(icon, unit, aura, showTimer)
			if colorEdge then ColorBuffEdge(icon, aura) end
		end
	end
	for index = shown + 1, #icons do icons[index]:Hide() end
	return shown
end

-- Stack and countdown numbers on plate aura icons: they grow with the
-- icon, or take the size picked on the Auras tab.
function M.AuraTextSizes(size)
	local timer, count = tonumber(db.auraTimerSize) or 0, tonumber(db.auraCountSize) or 0
	return timer > 0 and timer or math.max(math.floor(size * 0.5), 8),
		count > 0 and count or math.max(math.floor(size * 0.45), 7)
end

-- Lay out `shown` icons as a row. `shown` is our own count, not game data.
local function LayoutRow(plate, icons, shown, size, spacing, where, x, y)
	if shown == 0 then return end
	local root = plate.root
	local rowWidth = shown * size + (shown - 1) * spacing
	local _, countSize = M.AuraTextSizes(size)
	for index = 1, shown do
		local icon = icons[index]
		icon:SetSize(size, size)
		if icon.countSize ~= countSize then
			icon.countSize = countSize
			E:SetFont(icon.count, countSize)
		end
		icon:ClearAllPoints()
		local offset = (index - 1) * (size + spacing)
		if where == "RIGHT" then
			icon:SetPoint("LEFT", root, "RIGHT", x + offset, 0)
		else
			icon:SetPoint("BOTTOMLEFT", root, "TOP", -rowWidth / 2 + offset, y)
		end
	end
end

---------------------------------------------------------------------------
-- Aura containers: addon code may not read auras in combat on Forever, so
-- your debuffs, the enemy buffs and the crowd control icon are drawn by
-- the game's own aura containers (Core/AuraWidget.lua). EldoUI hands
-- the client filter, size and place; the client fills the icons in and
-- out of combat and follows UNIT_AURA itself. The EldoUI icons above stay
-- as the fallback when a container cannot be made (out of combat only).
---------------------------------------------------------------------------
local AURA_KINDS = { "debuffs", "buffs", "cc" }

local function PlainRGB(color)
	if type(color) == "table" and color.GetRGB then return { color:GetRGB() } end
	if type(color) == "table" and color.r then return { color.r, color.g, color.b } end
end

local function AuraRow(filters, max, size, spacing, timer, growth, attach)
	return {
		filters = filters, max = max, perRow = max, size = size, spacing = spacing,
		growth = growth, wrap = "UP", attach = attach, sort = "INDEX",
		duration = timer and "SWIPE" or "SWIPEONLY",
		durationSize = (M.AuraTextSizes(size)), countSize = select(2, M.AuraTextSizes(size)),
		tooltip = false, -- the plate stays click-through
		combat = true,   -- plates appear mid-fight
		-- Aura pop-in (Effects): the client plays it on every new icon.
		popIn = FX("auraPop") and FX("auraPop").enabled and E.db.general.animations or nil,
	}
end

-- What each container of a plate should be (nil = none).
local function AuraSettings(plate)
	local wanted = {}
	local t = T(plate)
	local debuffs, buffs = db.debuffs, db.buffs
	if t.debuffs.enabled then
		-- Filter groups with the client's candidate filters.
		local row = AuraRow(nil, t.debuffs.max, t.debuffs.size, debuffs.spacing, debuffs.timer, "RIGHT", "BOTTOM")
		row.groups = DebuffGroups(t.debuffs.max)
		row.dispelBorder, row.dispelColors = true, DispelRGB()
		wanted.debuffs = row
	end
	if t.buffs.enabled and BUFF_FILTERS[buffs.mode] and not plate.friendly then
		local row = AuraRow({ BUFF_FILTERS[buffs.mode] }, t.buffs.max, t.buffs.size, buffs.spacing, buffs.timer, "RIGHT",
			buffs.position == "RIGHT" and "LEFT" or "BOTTOM")
		if buffs.highlight then
			local enrage = buffs.enrageColor
			row.buffEdges = {
				stealable = buffs.stealableColor,
				types = { Enrage = enrage, [""] = enrage, Magic = DispelRGB().Magic or PlainRGB(_G.DEBUFF_TYPE_MAGIC_COLOR) },
			}
		end
		wanted.buffs = row
	end
	if db.cc.enabled then
		wanted.cc = AuraRow({ "HARMFUL|CROWD_CONTROL" }, 1, db.cc.size, 0, true, "LEFT", "RIGHT")
	end
	return wanted
end

-- The widget's signature covers the groups and their candidate filters;
-- filterVersion adds the account-wide spell lists.
local function Signature(widget, settings)
	return widget.Signature(settings, true) .. (settings.groups and (":" .. filterVersion) or "") .. (settings.popIn and ":pop" or "")
end

-- Holders are EldoUI frames on the plate; the containers pin to them
-- (nothing may anchor to a container).
local function AuraHolder(plate, kind)
	plate.auraHolders = plate.auraHolders or {}
	local holder = plate.auraHolders[kind]
	if not holder then
		holder = CreateFrame("Frame", nil, plate.root)
		holder:SetSize(1, 1)
		plate.auraHolders[kind] = holder
	end
	holder:ClearAllPoints()
	local root = plate.root
	if kind == "debuffs" then
		holder:SetPoint("BOTTOM", root, "TOP", 0, plate.debuffOffset or 3)
	elseif kind == "buffs" then
		if db.buffs.position == "RIGHT" then
			holder:SetPoint("LEFT", root, "RIGHT", plate.rightOffset or 3, 0)
		else
			holder:SetPoint("BOTTOM", root, "TOP", 0, plate.buffOffset or 3)
		end
	else
		holder:SetPoint("RIGHT", root, "LEFT", plate.leftOffset or -4, 0)
	end
	return holder
end

-- A plate whose type, side and settings generation are the same as at its
-- last check keeps its containers without building their signatures again.
local function AuraStateSame(plate, t)
	return plate.auraGen == auraGen and plate.auraType == t and plate.auraFriendly == (plate.friendly and true or false)
		and plate.auraMotion == (E.db.general.animations and true or false)
end

-- Match the plate's containers to the settings and point them at its
-- unit. Returns false when the containers cannot be used.
local function UpdateAuraContainers(plate)
	local widget = E.AuraWidget
	if not (widget and widget.Available()) then return false end
	plate.containers = plate.containers or {}
	plate.containerSigs = plate.containerSigs or {}
	local full = plate.kind == "FULL" and plate.unit
	local t = T(plate)
	if AuraStateSame(plate, t) then
		for _, kind in ipairs(AURA_KINDS) do
			local container = plate.containers[kind]
			if container then
				AuraHolder(plate, kind)
				local unit = full and plate.unit or "none"
				widget.SetUnit(container, unit)
				container:SetShown(unit ~= "none")
			end
		end
		return true
	end
	plate.auraGen, plate.auraType, plate.auraFriendly = auraGen, t, plate.friendly and true or false
	plate.auraMotion = E.db.general.animations and true or false
	local wanted = AuraSettings(plate)
	for _, kind in ipairs(AURA_KINDS) do
		local settings = wanted[kind]
		local signature = settings and Signature(widget, settings) or nil
		if plate.containerSigs[kind] ~= signature then
			widget.Release(plate.containers[kind])
			plate.containers[kind], plate.containerSigs[kind] = nil, nil
			if settings then
				settings.unit = "none"
				local container = widget.Create(AuraHolder(plate, kind), settings)
				if container then
					plate.containers[kind], plate.containerSigs[kind] = container, signature
				else
					plate.auraGen = nil -- not made this time: try again next update
				end
			end
		elseif settings then
			AuraHolder(plate, kind)
		end
		local container = plate.containers[kind]
		if container then
			local unit = full and plate.unit or "none"
			widget.SetUnit(container, unit)
			container:SetShown(unit ~= "none")
		end
	end
	return true
end

function ClearAuraContainers(plate)
	for _, container in pairs(plate.containers or {}) do
		E.AuraWidget.SetUnit(container, "none")
		container:Hide()
	end
end

-- The countdown look of the EldoUI fallback icons.
local function LookIcons(icons, size, timer)
	if not (timer and E.AuraWidget and E.AuraWidget.StyleCooldown) then return end
	for _, icon in ipairs(icons) do
		if icon.lookSize ~= size then
			E.AuraWidget.StyleCooldown(icon.cooldown, math.max(math.floor(size * 0.5), 8))
			icon.lookSize = size
		end
	end
end

local function HideAuraIcons(plate)
	for _, list in ipairs({ plate.debuffs, plate.buffs, plate.ccIcons }) do
		for _, icon in ipairs(list) do icon:Hide() end
	end
end

function UpdateAuras(plate)
	if UpdateAuraContainers(plate) then
		HideAuraIcons(plate)
		return
	end
	if plate.kind ~= "FULL" then
		HideAuraIcons(plate)
		return
	end
	local t = T(plate)
	local debuffs, buffs = db.debuffs, db.buffs

	local shown = t.debuffs.enabled and FillAuras(plate, plate.debuffs, DebuffFilter(), t.debuffs.max, debuffs.timer) or 0
	if not t.debuffs.enabled then for _, icon in ipairs(plate.debuffs) do icon:Hide() end end
	LayoutRow(plate, plate.debuffs, shown, t.debuffs.size, debuffs.spacing, "ABOVE", 0, plate.debuffOffset)
	LookIcons(plate.debuffs, t.debuffs.size, debuffs.timer)

	local filter = t.buffs.enabled and not plate.friendly and BUFF_FILTERS[buffs.mode]
	if filter then
		shown = FillAuras(plate, plate.buffs, filter, t.buffs.max, buffs.timer, true)
		LayoutRow(plate, plate.buffs, shown, t.buffs.size, buffs.spacing, buffs.position, plate.rightOffset, plate.buffOffset)
		LookIcons(plate.buffs, t.buffs.size, buffs.timer)
	else
		for _, icon in ipairs(plate.buffs) do icon:Hide() end
	end

	if db.cc.enabled then
		FillAuras(plate, plate.ccIcons, "HARMFUL|CROWD_CONTROL", 1, true)
	else
		for _, icon in ipairs(plate.ccIcons) do icon:Hide() end
	end
	local cc = plate.ccIcons[1]
	if cc then
		cc:SetSize(db.cc.size, db.cc.size)
		cc:ClearAllPoints()
		cc:SetPoint("RIGHT", plate.root, "LEFT", plate.leftOffset, 0)
		LookIcons(plate.ccIcons, db.cc.size, true)
	end
end

-- The containers follow UNIT_AURA themselves; only the fallback icons
-- need the event.
function OnAura(plate)
	if not plate.containers then UpdateAuras(plate) end
end
end

---------------------------------------------------------------------------
-- Cast bar: display only. Other units' cast times are secret in combat, so
-- the bar runs on UnitCastingDuration / UnitChannelDuration. The "can't
-- interrupt" color and shield, and the "important spell" glow, come from
-- the client's own flags through the *FromBoolean setters. Whether Forever
-- hands addons the notInterruptible flag at all is checked in game.
---------------------------------------------------------------------------
local CAST_NORMAL, CAST_LOCKED = CreateColor(1, 0.8, 0), CreateColor(0.45, 0.45, 0.45)
local CAST_CHANNEL = CreateColor(0.35, 0.75, 1)
local IN_FRONT = 300 -- frame levels a casting plate's bar rises by

local function ColorCast(castbar, notInterruptible, channel)
	local normal = (channel and db.castbar.channelColorOn) and CAST_CHANNEL or CAST_NORMAL
	if C_CurveUtil and C_CurveUtil.EvaluateColorFromBoolean then
		local ok, color = pcall(C_CurveUtil.EvaluateColorFromBoolean, Bool(notInterruptible), CAST_LOCKED, normal)
		if ok and Present(color) and pcall(function() castbar:SetStatusBarColor(color:GetRGB()) end) then
			return
		end
	end
	local locked = Plain(notInterruptible)
	castbar:SetStatusBarColor((locked and CAST_LOCKED or normal):GetRGB())
end

-- Cast in front: the cast bar and its icon rise over other plates while a
-- cast runs, and drop back when it ends.
local function CastLevel(plate, front)
	local base = plate.castBase
	local level = (front and db.castbar.inFront) and base + IN_FRONT or base
	plate.castbar:SetFrameLevel(level)
	plate.castIcon:SetFrameLevel(level)
	plate.interrupt:SetFrameLevel(level)
end

-- The spell's target under the cast bar: the Cast bar tab, your target's
-- plate with "Target plate details", or a style filter rule.
local function ShowCastTarget(plate)
	return db.castbar.targetName or plate.isDetailTarget or (plate.filter and plate.filter.castTarget) or false
end

-- Cast bar fade (Effects): an alpha animation on the bar and its icon; the
-- bar hides when it ends. Static with General > Animations off.
local function CastFade(plate)
	local group = plate.castFadeOut
	if group then return group end
	local castbar, icon = plate.castbar, plate.castIcon
	group = castbar:CreateAnimationGroup()
	local fade = group:CreateAnimation("Alpha")
	fade:SetFromAlpha(1)
	fade:SetToAlpha(0)
	fade:SetDuration(0.2)
	fade:SetSmoothing("IN")
	local iconGroup = icon:CreateAnimationGroup()
	local iconFade = iconGroup:CreateAnimation("Alpha")
	iconFade:SetFromAlpha(1)
	iconFade:SetToAlpha(0)
	iconFade:SetDuration(0.2)
	iconFade:SetSmoothing("IN")
	group.icon = iconGroup
	group:SetScript("OnFinished", function()
		plate.castFading = nil
		castbar:Hide()
		icon:Hide()
		if not plate.interrupt:IsShown() then CastLevel(plate, false) end
	end)
	plate.castFadeOut = group
	return group
end

local function StopCastFade(plate)
	local group = plate.castFadeOut
	if group and plate.castFading then
		group:Stop()
		group.icon:Stop()
	end
	plate.castFading = nil
end

local function FadeEnabled()
	local fx = FX("castFade")
	return fx and fx.enabled and E.db.general.animations and true or false
end

-- One updater for every running cast bar: the shared ticker calls it 20
-- times a second while a bar runs and lets go once none does.
local runningCasts = {} -- cast bar -> true while it runs
local CAST_TICK = "Nameplates:cast"

-- Time text: remaining, or remaining / total. A secret duration may refuse
-- the call; then this cast shows no time text instead of failing every
-- update.
local function CastTimeText(castbar)
	local duration = castbar.duration
	if castbar.timeMode == "TOTAL" then
		castbar.time:SetFormattedText("%.1f / %.1f", duration:GetRemainingDuration(), duration:GetTotalDuration())
	else
		castbar.time:SetFormattedText("%.1f", duration:GetRemainingDuration())
	end
end

local function CastUpdate(castbar)
	local showTimer = castbar.timeMode ~= "NONE"
	if castbar.hasDuration then
		if showTimer and not castbar.noTimeText then
			if not pcall(CastTimeText, castbar) then castbar.noTimeText = true end
		end
		return
	end
	if not castbar.endTime then return end
	local now = GetTime()
	if now >= castbar.endTime then
		castbar:Hide()
		return
	end
	local spent = now - castbar.startTime
	local total = castbar.endTime - castbar.startTime
	castbar:SetValue(castbar.channel and (total - spent) or spent)
	if castbar.timeMode == "TOTAL" then
		castbar.time:SetFormattedText("%.1f / %.1f", castbar.endTime - now, total)
	elseif showTimer then
		castbar.time:SetFormattedText("%.1f", castbar.endTime - now)
	end
end

local function CastTick()
	for castbar in pairs(runningCasts) do
		if not castbar:IsShown() then
			runningCasts[castbar] = nil
		elseif castbar:IsVisible() then
			CastUpdate(castbar)
		end
	end
	if next(runningCasts) == nil then E.Ticker:Unsubscribe(CAST_TICK) end
end

local function WatchCast(castbar)
	runningCasts[castbar] = true
	if not E.Ticker:IsSubscribed(CAST_TICK) then E.Ticker:Subscribe(CAST_TICK, 0.05, CastTick, M) end
end

-- `fade`: the cast ended by itself (stop, failed), so the bar may fade out.
local function HideCast(plate, fade)
	local castbar = plate.castbar
	runningCasts[castbar] = nil
	-- Remember when a running cast went away: the stop event can come just
	-- before the interrupted one.
	if castbar:IsShown() and not plate.castFading then plate.castHiddenAt = GetTime() end
	castbar.duration, castbar.startTime, castbar.endTime = nil, nil, nil
	castbar.hasDuration = false
	plate.castShield:Hide()
	plate.castSpark:Hide()
	ClearGate(plate, "importantGate")
	if fade and castbar:IsShown() and not plate.castFading and FadeEnabled() and not plate.preview then
		local group = CastFade(plate)
		plate.castFading = true
		group:Play()
		if plate.castIcon:IsShown() then group.icon:Play() end
		return
	end
	if fade and plate.castFading then return end
	StopCastFade(plate)
	castbar:Hide()
	plate.castIcon:Hide()
	if not plate.interrupt:IsShown() then CastLevel(plate, false) end
end

-- Show the bar; a cast that wasn't on screen fades in (Effects).
local function ShowCastBar(plate, wasShown)
	plate.castbar:Show()
	WatchCast(plate.castbar)
	if wasShown then return end
	local fx = FX("castFade")
	E:UnitFXFadeIn(plate.castbar, fx)
	if plate.castIcon:IsShown() then E:UnitFXFadeIn(plate.castIcon, fx) end
end

-- Important flag of a spell: the game's answer, maybe secret, or nil.
local function ImportantFlag(spellID)
	if type(spellID) == "nil" or not (C_Spell and C_Spell.IsSpellImportant) then return nil end
	local ok, important = pcall(C_Spell.IsSpellImportant, spellID)
	if ok then return important end
	return nil
end

-- `fresh`: a new cast started (not a delay or channel update), so the
-- important cast sound may play.
local function StartCast(plate, channel, fresh)
	if plate.kind ~= "FULL" or plate.preview then return end
	local castbar = plate.castbar
	local t = T(plate)
	if not t.castbar.enabled then return HideCast(plate) end
	local unit = plate.unit
	-- Cast:    name, text, texture, start, end, isTradeSkill, castID, notInterruptible, spellID
	-- Channel: name, text, texture, start, end, isTradeSkill, notInterruptible, spellID
	local info = channel and UnitChannelInfo or UnitCastingInfo
	local ok, name, _, texture, startMS, endMS, _, seventh, eighth, ninth = pcall(info, unit)
	if not ok or not Present(name) then return HideCast(plate) end
	-- Plain ifs: "channel and x or y" would truth-test a secret flag.
	local notInterruptible, spellID
	if channel then
		notInterruptible, spellID = seventh, eighth
	else
		notInterruptible, spellID = eighth, ninth
	end
	plate.interrupt:Hide()
	local wasShown = castbar:IsShown() and not plate.castFading
	StopCastFade(plate)

	local settings = db.castbar
	castbar.channel = channel
	castbar.timeMode = t.castbar.time
	local label = ""
	if settings.spellName then label = name end
	pcall(castbar.text.SetText, castbar.text, label)
	castbar.time:SetText("")
	castbar.target:SetText("")
	if ShowCastTarget(plate) and UnitSpellTargetName then
		local okTarget, target = pcall(UnitSpellTargetName, unit)
		if okTarget and Present(target) then pcall(castbar.target.SetText, castbar.target, target) end
	end
	pcall(plate.castIcon.texture.SetTexture, plate.castIcon.texture, texture)
	plate.castIcon:SetShown(t.castbar.icon ~= "NONE")
	ColorCast(castbar, notInterruptible, channel)
	if settings.shield then ShowFromBoolean(plate.castShield, Bool(notInterruptible)) else plate.castShield:Hide() end
	-- Important cast glow on the shared castImportant look (General > Glows).
	E:UnitFXImportantCast(Gate(plate, "importantGate", castbar, 2), spellID, FX("importantGlow"))
	-- Important cast sound (opt-in): your target only, a plain "true" only.
	local sound = FX("importantSound")
	if fresh and sound and sound.enabled and plate.nameplate == PlateFor("target") then
		E:UnitFXImportantSound(ImportantFlag(spellID), sound)
	end
	local spark = FX("castSpark")
	plate.castSpark:SetShown(spark and spark.enabled and true or false)
	if plate.ruleGated then UpdateRuleGates(plate, spellID) end
	castbar.duration, castbar.startTime, castbar.endTime = nil, nil, nil
	castbar.hasDuration, castbar.noTimeText = false, false
	CastLevel(plate, true)

	local durationFn = channel and UnitChannelDuration or UnitCastingDuration
	if durationFn and castbar.SetTimerDuration then
		-- The duration object itself can be secret: test it with Present().
		local okDuration, duration = pcall(durationFn, unit)
		if okDuration and Present(duration) then
			castbar.duration, castbar.hasDuration = duration, true
			local direction = channel and Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.RemainingTime
			if not pcall(castbar.SetTimerDuration, castbar, duration, nil, direction) then
				pcall(castbar.SetTimerDuration, castbar, duration)
			end
			ShowCastBar(plate, wasShown)
			return
		end
	end
	-- No duration object (the cast just ended, or the game gave none): only
	-- plain (non-secret) times.
	local startPlain, endPlain = Plain(startMS), Plain(endMS)
	if startPlain and endPlain then
		castbar.startTime, castbar.endTime = startPlain / 1000, endPlain / 1000
		castbar:SetMinMaxValues(0, castbar.endTime - castbar.startTime)
		ShowCastBar(plate, wasShown)
	else
		HideCast(plate)
	end
end

local ApplyFilters -- style filters, defined below

-- A stop event can arrive for an old cast while a new one runs, so check.
-- `ended`: a stop event, so a bar that goes away may fade out.
local function RefreshCast(plate, ended)
	if plate.preview then return end
	if plate.kind ~= "FULL" or not T(plate).castbar.enabled then return HideCast(plate) end
	local okCast, casting = pcall(UnitCastingInfo, plate.unit)
	if okCast and Present(casting) then return StartCast(plate, false) end
	local okChannel, channeling = pcall(UnitChannelInfo, plate.unit)
	if okChannel and Present(channeling) then return StartCast(plate, true) end
	HideCast(plate, ended)
	if plate.ruleGated then UpdateRuleGates(plate) end
end

local function CastChanged(plate, channel, fresh)
	if channel == nil then RefreshCast(plate, true) else StartCast(plate, channel, fresh) end
end

-- "Interrupted by <name>" (Effects): the name of the interrupter the
-- event names, as Blizzard's own cast bar shows it. A name the game keeps
-- secret goes straight to the text setter; the class color is used only
-- when the class is plain. Nothing comes from the combat log.
local function InterruptText(text, interruptedBy)
	local fallback = E:GameText(_G.INTERRUPTED, L["Interrupted"])
	local fx = FX("interrupter")
	if not (fx and fx.enabled) or type(interruptedBy) == "nil" or not UnitNameFromGUID then
		text:SetText(fallback)
		return
	end
	local ok, name = pcall(UnitNameFromGUID, interruptedBy)
	if not ok or type(name) == "nil" then
		text:SetText(fallback)
		return
	end
	local format = E:GameText(_G.SPELL_INTERRUPTED_BY, L["Interrupted by %s"])
	if IsSecret(name) then
		if not pcall(text.SetFormattedText, text, format, name) then text:SetText(fallback) end
		return
	end
	if type(name) ~= "string" or name == "" then
		text:SetText(fallback)
		return
	end
	local classFile
	if UnitClassFromGUID then
		local okClass, _, file = pcall(UnitClassFromGUID, interruptedBy)
		classFile = okClass and Plain(file) or nil
	end
	local color = E:ClassColorObject(classFile)
	if color and color.WrapTextInColorCode then name = color:WrapTextInColorCode(name) end
	text:SetFormattedText(format, name)
end

-- "Interrupted" strip in place of the cast bar for a moment. The event
-- itself is the game telling us; nothing is inferred.
local function ShowInterrupted(plate, _, _, interruptedBy)
	local justStopped = plate.castHiddenAt and GetTime() - plate.castHiddenAt < 0.25
	if plate.kind ~= "FULL" or not (db.castbar.showInterrupted and (plate.castbar:IsShown() or justStopped)) then
		return CastChanged(plate)
	end
	StopCastFade(plate)
	HideCast(plate)
	plate.castHiddenAt = nil
	local strip = plate.interrupt
	strip:SetStatusBarColor(RGB(db.castbar.interruptedColor))
	InterruptText(strip.text, interruptedBy)
	strip:Show()
	CastLevel(plate, true)
	local token = {}
	plate.interruptToken = token
	C_Timer.After(math.max(tonumber(T(plate).castbar.hold) or 0.6, 0.1), function()
		if plate.interruptToken == token then
			strip:Hide()
			if not plate.castbar:IsShown() then CastLevel(plate, false) end
		end
	end)
	-- A new cast hides the strip through UNIT_SPELLCAST_START.
end
---------------------------------------------------------------------------
-- Target highlight, focus and mouse-over, target scale, non-target fade
-- and the style filter actions on top. Plates are compared as frames,
-- never by unit identity (which can be secret).
---------------------------------------------------------------------------
local function TargetColor()
	if db.targetAccent then return unpack(E.media.accentColor, 1, 3) end
	return RGB(db.targetColor)
end

local LayoutPlate, UpdatePlate -- defined with the plate construction below
local WatchPlateUnit, UnwatchPlateUnit -- per-plate unit events, defined with the events below

-- The skin's border on EldoUI's own plates: they follow the unit-frame
-- graphics (Layout and style > Appearance > Unit-frame graphics). While
-- those draw the skin's frame art, a plate wears the thin edge a small unit
-- frame wears, cut from the same art; with Modern (flat) graphics or High
-- contrast it keeps its one-pixel border. The empty part of the bar is the
-- unit frames' well. Your own border colors (target, focus, style filter)
-- win: the skin's edge steps aside while one of them shows, and the threat
-- border still draws over it. Plates Blizzard draws keep the game's art.
-- Texture and color only, on EldoUI's own frames.
-- One table for the three helpers: the file's main chunk is near Lua's limit
-- of local variables.
local PlateEdge = {}
function PlateEdge.Art()
	local UG, Skins = E.UnitGraphics, E.Skins
	if not (UG and UG.Resolve and UG.Provider and Skins and Skins.painters and Skins.painters.edge) then return nil end
	local id = UG:Resolve(nil, nil, "unit")
	local provider = id ~= "MODERN" and UG:Provider(id)
	if not provider then return nil end
	local m = E:SkinManifest(E:SkinPart("unitframes"))
	if m and m.data then return m.id, m.data end
	local data = provider.home and E.skinData and E.skinData[provider.home]
	if data then return provider.home, data end
end

function PlateEdge.Show(plate)
	local edge = plate.skinEdge
	if edge then edge:SetShown(plate.edgeData ~= nil and not plate.ownBorder) end
end

function PlateEdge.Paint(plate)
	local UG = E.UnitGraphics
	if UG and UG.PaintWell then UG:PaintWell(plate.health, "DEFAULT") end
	local id, data
	if plate.kind == "FULL" then id, data = PlateEdge.Art() end
	local edge = plate.skinEdge
	if not data then
		if edge and E.Skins then E.Skins.Release(edge) end
		plate.edgeData = nil
		PlateEdge.Show(plate)
		return
	end
	local bg = plate.health.bg
	if not edge then
		-- Over the bar, under the threat border and the texts.
		edge = CreateFrame("Frame", nil, bg)
		edge:SetAllPoints(bg)
		edge:EnableMouse(false)
		plate.skinEdge = edge
	end
	edge:SetFrameLevel(bg:GetFrameLevel() + 2)
	if plate.edgeData ~= data or E.Skins.State(edge) ~= "edge" then
		E.Skins.painters.edge(edge, { id = id, data = data })
	end
	plate.edgeData = data
	PlateEdge.Show(plate)
end

-- Opacity for an enemy that isn't fighting ("Fade units out of combat"):
-- the game's plain combat flag only; a secret flag keeps the plate as it is.
local function OutOfCombatAlpha(plate)
	local percent = tonumber(db.outOfCombatAlpha) or 0
	if percent <= 0 or plate.friendly or plate.preview then return 1 end
	if Query(UnitAffectingCombat, plate.unit) == false then return percent / 100 end
	return 1
end

-- Soft targets; enemyPlate is the plate of your soft enemy target, while
-- there is one.
local Soft = {}

local function UpdateTargetState(plate, targetNameplate, hasTarget, focusNameplate, hoverNameplate)
	local isTarget = targetNameplate ~= nil and plate.nameplate == targetNameplate
	local isFocusPlate = focusNameplate ~= nil and plate.nameplate == focusNameplate
	-- Your focus counts as target for the fade and the dim (Target tab).
	local stepsForward = isTarget or (db.focusAsTarget and isFocusPlate)
	local root = plate.root
	local filter = plate.filter
	local mode = db.othersMode
	local dim = false
	if plate.kind ~= "EXTRAS" then
		local scale = (isTarget and db.targetScale / 100 or 1) * (plate.sizeScale or 1)
		local alpha = 1
		if hasTarget and not stepsForward then
			if mode == "FADE" then alpha = db.nonTargetAlpha / 100 elseif mode == "DIM" then dim = true end
		end
		alpha = math.min(alpha, OutOfCombatAlpha(plate))
		if filter then
			scale = scale * (filter.scale or 1)
			if filter.alpha then alpha = filter.alpha end
			if filter.hide then alpha = 0 end
			if filter.dim then dim = true end
		end
		root:SetScale(scale)
		-- A grown target keeps one-pixel borders: the flat edges are sized
		-- again for the plate's own scale (and back when it shrinks).
		if (plate.edgeScale ~= scale or plate.edgePixel ~= E.pixel) and (plate.edgeScale or scale ~= 1) and E.SnapBorders then
			plate.edgeScale, plate.edgePixel = scale, E.pixel
			E:SnapBorders(root, true)
		end
		root:SetAlpha(alpha)
		root:SetFrameLevel(plate.rootBase + ((filter and filter.raise) and 100 or 0))
	end
	plate.dim:SetShown(dim and plate.kind == "FULL")

	-- "Target plate details": your target's plate is laid out again with
	-- the extra texts and bars.
	local details = db.targetDetails and isTarget and plate.baseKind == "FULL" and not plate.preview or false
	local wasTarget = plate.isTarget
	plate.isTarget = isTarget
	if details ~= (plate.isDetailTarget or false) then
		plate.isDetailTarget = details
		LayoutPlate(plate)
		UpdatePlate(plate)
	elseif wasTarget ~= isTarget then
		-- The threat border becomes a line under the bar on your target.
		UpdateThreatFX(plate)
	end

	-- Border priority: target (accent) > threat (its own gate, drawn over
	-- this border) > style filter > focus > a player's class color > the
	-- skin's edge > normal. A player is read once per plate setup
	-- (plate.isPlayer): an unknown answer gets the normal look.
	local bg = plate.health.bg
	local indicator = plate.kind == "FULL" and db.targetIndicator or "NONE"
	local isFocus = plate.kind == "FULL" and db.focusIndicator and isFocusPlate
	local r, g, b = TargetColor()
	local own = true
	if isTarget and (indicator == "BORDER" or indicator == "BOTH") then
		bg:SetBackdropBorderColor(r, g, b, 1)
	elseif filter and filter.borderColor then
		bg:SetBackdropBorderColor(RGB(filter.borderColor))
	elseif isFocus then
		bg:SetBackdropBorderColor(RGB(db.focusColor))
	else
		local cr, cg, cb
		if plate.kind == "FULL" and plate.isPlayer and db.colors.playerBorder and plate.unit then cr, cg, cb = ClassColor(plate.unit) end
		if cr then
			bg:SetBackdropBorderColor(cr, cg, cb, 1)
		else
			bg:SetBackdropBorderColor(unpack(E.media.borderColor))
			own = false
		end
	end
	plate.ownBorder = own
	PlateEdge.Show(plate)
	if isTarget and (indicator == "GLOW" or indicator == "BOTH") then
		plate.glow:SetVertexColor(r, g, b, 0.9)
		plate.glow:Show()
	else
		plate.glow:Hide()
	end
	local arrows = isTarget and indicator == "ARROWS"
	for _, arrow in ipairs(plate.arrows) do
		arrow:SetVertexColor(r, g, b, 1)
		arrow:SetShown(arrows)
	end
	plate.underline:SetVertexColor(r, g, b, 1)
	plate.underline:SetShown(isTarget and indicator == "UNDERLINE")
	-- Overlay: a light sheen on the bar. Pulse glow: General > Glows
	-- (Nameplates: target), static with animations off.
	plate.overlay:SetShown(isTarget and indicator == "OVERLAY")
	local pulse = isTarget and indicator == "PULSE"
	if pulse and not plate.targetPulse then
		E:ShowUserGlow(plate.targetGlow, "nameplateTarget")
		plate.targetPulse = true
	elseif not pulse and plate.targetPulse then
		E:HideGlow(plate.targetGlow)
		plate.targetPulse = nil
	end

	local hovered = not isTarget and (
		(db.mouseoverHighlight and hoverNameplate ~= nil and plate.nameplate == hoverNameplate)
		or (db.softTargetHighlight and Soft.enemyPlate ~= nil and plate.nameplate == Soft.enemyPlate))
	plate.hover:SetShown((plate.kind == "FULL" and hovered) and true or false)

	-- Name-only plates have no bar to mark: a short line under the name,
	-- in the target color on your target and light on the plate under the
	-- mouse.
	local cue = plate.kind == "NAME" and (isTarget or hovered) and plate.nameText:IsShown()
	local mark = plate.nameMark
	if cue and not mark then
		mark = plate.nameText:GetParent():CreateTexture(nil, "OVERLAY")
		mark:SetTexture(E.media.flat)
		plate.nameMark = mark
	end
	if mark then
		if cue then
			local name = plate.nameText
			local width = 8
			if type(E.PlainCall(name.GetText, name)) == "string" then
				local measured = E.PlainCall(name.GetStringWidth, name)
				local available = E.PlainCall(name.GetWidth, name)
				if type(measured) == "number" and type(available) == "number" then
					width = math.max(8, math.min(measured, available))
				end
			end
			mark:ClearAllPoints()
			mark:SetPoint("TOP", name, "BOTTOM", 0, -1)
			mark:SetSize(width, 2)
			if isTarget then mark:SetVertexColor(r, g, b, 1) else mark:SetVertexColor(1, 1, 1, 0.5) end
			mark:Show()
		else
			mark:Hide()
		end
	end
end

local hoverPlate -- the nameplate under the mouse while we track it

local function TargetStateFor(plate)
	UpdateTargetState(plate, PlateFor("target"), Query(UnitExists, "target") and true or false, PlateFor("focus"), hoverPlate)
end

---------------------------------------------------------------------------
-- Style filters
---------------------------------------------------------------------------
-- Fill a rule with the defaults it lacks and drop unknown keys, so a rule
-- from an old export or a half-written row always works.
local function NormalizeRule(rule)
	for key, value in pairs(RULE_DEFAULTS) do
		if type(rule[key]) ~= type(value) then
			rule[key] = type(value) == "table" and CopyTable(value) or value
		end
	end
	for key in pairs(rule) do
		if RULE_DEFAULTS[key] == nil then rule[key] = nil end
	end
	return rule
end

local function Rules()
	local filters = db.styleFilters
	if type(filters.rules) ~= "table" then filters.rules = {} end
	return filters.rules
end

-- Names and NPC IDs of a rule, parsed once per text.
local nameSets = {}
local function NameSet(text)
	local set = nameSets[text]
	if set then return set end
	set = {}
	for token in text:gmatch("[^,;\n]+") do
		token = strtrim(token):lower()
		if token ~= "" then set[tonumber(token) or token] = true end
	end
	nameSets[text] = set
	return set
end

local function NPCID(unit)
	local ok, guid = pcall(UnitGUID, unit)
	guid = ok and Plain(guid)
	if type(guid) ~= "string" then return nil end
	local kind, id = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)")
	if kind == "Creature" or kind == "Vehicle" then return tonumber(id) end
end

-- Facts that are the same for every plate during one evaluation pass.
local function FilterContext()
	local inside, instance = InInstance()
	local specInfo = C_SpecializationInfo
	return {
		combat = InCombatLockdown() or Query(UnitAffectingCombat, "player") and true or false,
		inside = inside,
		instance = inside and (instance or "unknown") or "none",
		role = PlayerRole(),
		spec = specInfo and Query(specInfo.GetSpecialization),
		target = PlateFor("target"),
		focus = PlateFor("focus"),
		hover = hoverPlate,
	}
end

local function YesNo(setting, value)
	if setting == "any" then return true end
	if value == nil then return false end -- unknown (secret) never matches
	return (setting == "yes") == (value and true or false)
end

local function Matches(rule, plate, ctx)
	local unit = plate.unit
	if rule.reaction ~= "any" then
		local reaction = Query(UnitReaction, unit, "player")
		if not reaction then return false end
		local kind = reaction >= 5 and "friendly" or reaction == 4 and "neutral" or "hostile"
		if kind ~= rule.reaction then return false end
	end
	if rule.unitType ~= "any" then
		local isPlayer = Query(UnitIsPlayer, unit)
		if isPlayer == nil or (rule.unitType == "player") ~= isPlayer then return false end
	end
	if rule.classification ~= "any" and Query(UnitClassification, unit) ~= rule.classification then return false end
	if not YesNo(rule.target, ctx.target ~= nil and ctx.target == plate.nameplate) then return false end
	if not YesNo(rule.focus, ctx.focus ~= nil and ctx.focus == plate.nameplate) then return false end
	if not YesNo(rule.mouseover, ctx.hover ~= nil and ctx.hover == plate.nameplate) then return false end
	if not YesNo(rule.playerCombat, ctx.combat) then return false end
	if rule.unitCombat ~= "any" and not YesNo(rule.unitCombat, Query(UnitAffectingCombat, unit)) then return false end
	if rule.quest ~= "any" then
		-- Quest flags are only used outside instances.
		if ctx.inside or not (C_QuestLog and C_QuestLog.UnitIsRelatedToActiveQuest) then return false end
		if not YesNo(rule.quest, Query(C_QuestLog.UnitIsRelatedToActiveQuest, unit)) then return false end
	end
	if rule.behindCamera ~= "any" then
		local api = C_NamePlateManager
		local behind = api and api.IsNamePlateUnitBehindCamera and Query(api.IsNamePlateUnitBehindCamera, unit)
		if not YesNo(rule.behindCamera, behind) then return false end
	end
	if rule.creature == "totem" and not plate.isTotem then return false end
	if rule.creature == "pet" then
		if Query(UnitIsPlayer, unit) ~= false or not Query(UnitPlayerControlled, unit) then return false end
	end
	if rule.role ~= "any" and ctx.role ~= rule.role then return false end
	if rule.spec ~= 0 and ctx.spec ~= rule.spec then return false end
	if rule.instance ~= "any" and ctx.instance ~= rule.instance then return false end
	if rule.levelMin > 0 or rule.levelMax > 0 then
		local level = Query(UnitEffectiveLevel or UnitLevel, unit)
		if not level then return false end
		if level < 0 then level = 999 end -- "??" (boss or far above you)
		if rule.levelMin > 0 and level < rule.levelMin then return false end
		if rule.levelMax > 0 and level > rule.levelMax then return false end
	end
	if rule.names ~= "" then
		-- Identity is secret inside instances: the trigger only works outside.
		if ctx.inside then return false end
		local set = NameSet(rule.names)
		local okName, name = pcall(UnitName, unit)
		name = okName and Plain(name)
		local id = NPCID(unit)
		if not ((type(name) == "string" and set[name:lower()]) or (id and set[id])) then return false end
	end
	if rule.casting ~= "any" then
		-- Whether a cast runs is a plain fact: the name exists (a secret name
		-- still exists). What is cast is never read.
		local okCast, cast = pcall(UnitCastingInfo, unit)
		local okChannel, channel = pcall(UnitChannelInfo, unit)
		local casting = (okCast and Present(cast)) or (okChannel and Present(channel)) or false
		if not YesNo(rule.casting, casting) then return false end
	end
	return true
end

-- A rule with a gated trigger: its answer may be secret, so the rule's
-- border color and glow are drawn inside gates the client opens.
local function IsGated(rule)
	return rule.castImportant == "yes" or rule.executeZone == "yes"
end

-- Some rule uses this trigger.
local function AnyRuleUses(field)
	for _, rule in ipairs(Rules()) do
		if rule.enabled and rule[field] ~= "any" then return true end
	end
	return false
end

local NO_FILTER = nil

-- The actions for one plate: for each action the first matching rule
-- that sets it wins.
local function Evaluate(plate, ctx)
	if not db.styleFilters.enabled or (plate.baseKind ~= "FULL" and plate.baseKind ~= "NAME") then return NO_FILTER end
	local rules = Rules()
	if #rules == 0 then return NO_FILTER end
	local result
	for _, rule in ipairs(rules) do
		if rule.enabled and IsGated(rule) then
			if Matches(rule, plate, ctx) then
				result = result or { matched = {} }
				table.insert(result.matched, rule.name)
				result.gated = result.gated or rule
			end
		elseif rule.enabled and Matches(rule, plate, ctx) then
			result = result or { matched = {} }
			table.insert(result.matched, rule.name)
			if rule.healthColorOn and not result.healthColor then result.healthColor = rule.healthColor end
			if rule.borderColorOn and not result.borderColor then result.borderColor = rule.borderColor end
			if rule.nameColorOn and not result.nameColor then result.nameColor = rule.nameColor end
			if rule.texture ~= "" and not result.texture then result.texture = rule.texture end
			if rule.scale ~= 1 and not result.scale then result.scale = rule.scale end
			if rule.alpha > 0 and not result.alpha then result.alpha = rule.alpha end
			if rule.hide then result.hide = true end
			if rule.nameOnly then result.nameOnly = true end
			if rule.glow ~= "none" and not result.glow then result.glow = rule.glow end
			if rule.raise then result.raise = true end
			if rule.threatBorder ~= "keep" and not result.threatBorder then result.threatBorder = rule.threatBorder end
			if rule.execute ~= "keep" and not result.execute then result.execute = rule.execute end
			if (rule.sizeWidth > 0 or rule.sizeHeight > 0) and not result.size then
				result.size = { rule.sizeWidth, rule.sizeHeight }
			end
			if rule.castTarget then result.castTarget = true end
			if rule.dim then result.dim = true end
		end
	end
	return result
end

-- The spell ID of the unit's running cast (maybe secret), or nil.
local function CurrentSpellID(unit)
	local okCast, name, _, _, _, _, _, _, _, castSpell = pcall(UnitCastingInfo, unit)
	if okCast and Present(name) then return castSpell end
	local okChannel, channelName, _, _, _, _, _, _, channelSpell = pcall(UnitChannelInfo, unit)
	if okChannel and Present(channelName) then return channelSpell end
	return nil
end

-- Gated rule visuals: an outer gate for "In execute zone" (alpha from the
-- game's curve) holding an inner one for "Cast is important" (alpha from
-- the game's flag). Both open = the rule shows; Lua never tests either.
function UpdateRuleGates(plate, spellID)
	local rule = plate.ruleGated
	if not rule or plate.kind ~= "FULL" then
		ClearGate(plate, "ruleInner")
		ClearGate(plate, "ruleOuter")
		return
	end
	local outer = Gate(plate, "ruleOuter", plate.health.bg, 5)
	local inner = Gate(plate, "ruleInner", outer, 1)
	if not (outer and inner) then return end
	if rule.borderColorOn then
		inner:SetLook("BORDER", { thickness = 1 })
		for _, texture in ipairs(inner.textures) do texture:SetVertexColor(RGB(rule.borderColor)) end
	else
		inner:SetLook("NONE")
	end
	inner:Glow("nameplateFilter", rule.glow ~= "none")
	if rule.executeZone == "yes" then
		outer:FromAlpha(E:UnitCurveHealth(plate.unit, "execute", { lower = rule.executeLower, output = "alpha" }))
	else
		outer:SetOpen(true)
	end
	if rule.castImportant == "yes" then
		if type(spellID) == "nil" then spellID = CurrentSpellID(plate.unit) end
		inner:FromBoolean(ImportantFlag(spellID), 1, 0)
	else
		inner:SetOpen(true)
	end
end

-- Show or hide the filter glow on the plate's own glow frame.
local function FilterGlow(plate, which)
	local frame = plate.filterGlow
	if which == "glow" then
		E:ShowUserGlow(frame, "nameplateFilter")
	elseif which == "flash" then
		local _, opts = E:GlowSettings("nameplateFilter")
		E:ShowGlow(frame, "pulse", opts)
	elseif E:IsGlowShown(frame) then
		E:HideGlow(frame)
	end
end

-- Two filter results that lay a plate out the same (size and cast target).
local function SameShape(a, b)
	local sizeA, sizeB = a and a.size, b and b.size
	return (sizeA and sizeA[1] or 0) == (sizeB and sizeB[1] or 0)
		and (sizeA and sizeA[2] or 0) == (sizeB and sizeB[2] or 0)
		and (a and a.castTarget or false) == (b and b.castTarget or false)
end

function ApplyFilters(plate, ctx)
	if not plate.unit or plate.preview then return end
	local old = plate.filter
	local filter = Evaluate(plate, ctx or FilterContext())
	plate.filter = filter
	plate.ruleGated = filter and filter.gated or nil
	-- Name only, a size or the cast target: lay the plate out again.
	local kind = (filter and filter.nameOnly) and "NAME" or plate.baseKind
	if kind ~= plate.kind or not SameShape(old, filter) then
		plate.kind = kind
		LayoutPlate(plate)
		UpdatePlate(plate)
	elseif (old and old.texture) ~= (filter and filter.texture) then
		local name = (filter and filter.texture) or db.texture
		plate.health:SetStatusBarTexture(PlateTexture(name))
	end
	UpdateColor(plate)
	UpdateName(plate)
	FilterGlow(plate, filter and plate.kind == "FULL" and filter.glow or nil)
	UpdateThreatFX(plate)
	UpdateExecute(plate)
	UpdateRuleGates(plate)
	TargetStateFor(plate)
end

local function ApplyAllFilters()
	local ctx = FilterContext()
	for _, plate in pairs(plates) do
		ApplyFilters(plate, ctx)
	end
end

-- Soft targets (action targeting, gamepad): the game picks the unit; its
-- cursor icon is drawn on that unit's plate when the game's own
-- "SoftTargetIcon..." setting for that kind is on. Plates are compared as
-- frames, never by unit identity.
Soft.ICONS = {
	{ "softinteract", "SoftTargetIconInteract" },
	{ "softenemy", "SoftTargetIconEnemy" },
	{ "softfriend", "SoftTargetIconFriend" },
}

function Soft.CVarOn(name)
	if not (C_CVar and C_CVar.GetCVarBool) then return false end
	local ok, on = pcall(C_CVar.GetCVarBool, name)
	return ok and Plain(on) == true
end

function Soft.UpdateIcon(plate)
	local icon = plate.softIcon
	if not icon then return end
	local token
	if plate.nameplate and (plate.kind == "FULL" or plate.kind == "NAME") then
		for _, soft in ipairs(Soft.ICONS) do
			if PlateFor(soft[1]) == plate.nameplate and Soft.CVarOn(soft[2]) then
				token = soft[1]
				break
			end
		end
	end
	if token and SetUnitCursorTexture then
		local ok, shown = pcall(SetUnitCursorTexture, icon, token)
		if ok and Plain(shown) ~= false then
			icon:Show()
			return
		end
	end
	icon:Hide()
end

function Soft.Update()
	Soft.enemyPlate = PlateFor("softenemy")
	for _, plate in pairs(plates) do Soft.UpdateIcon(plate) end
end

local function UpdateAllTargets()
	local targetNameplate = PlateFor("target")
	local focusNameplate = PlateFor("focus")
	local hasTarget = Query(UnitExists, "target") and true or false
	if db.styleFilters.enabled and #Rules() > 0 then
		-- Target, focus and mouse-over are triggers.
		ApplyAllFilters()
		return
	end
	for _, plate in pairs(plates) do
		UpdateTargetState(plate, targetNameplate, hasTarget, focusNameplate, hoverPlate)
	end
end

-- There is no "mouse left the unit" event, so poll lightly (on the shared
-- ticker) while one plate is highlighted, and not at all otherwise.
local HOVER_TICK = "Nameplates:hover"

local function HoverTick()
	if PlateFor("mouseover") ~= hoverPlate then
		hoverPlate = nil
		E.Ticker:Unsubscribe(HOVER_TICK)
		UpdateAllTargets()
	end
end

local function OnMouseoverChanged()
	if not db.mouseoverHighlight and not AnyRuleUses("mouseover") then
		E.Ticker:Unsubscribe(HOVER_TICK)
		if hoverPlate then hoverPlate = nil; UpdateAllTargets() end
		return
	end
	hoverPlate = PlateFor("mouseover")
	if not hoverPlate then
		E.Ticker:Unsubscribe(HOVER_TICK)
	elseif not E.Ticker:IsSubscribed(HOVER_TICK) then
		E.Ticker:Subscribe(HOVER_TICK, 0.1, HoverTick, M)
	end
	UpdateAllTargets()
end

---------------------------------------------------------------------------
-- Plate construction and layout
---------------------------------------------------------------------------
local function CreatePlate(nameplate)
	local plate = { nameplate = nameplate, debuffs = {}, buffs = {}, ccIcons = {} }
	-- Everything is laid out against `root`, which never receives secret
	-- values, so anchoring stays readable (see platform rules §2.7).
	local root = CreateFrame("Frame", nil, nameplate)
	plate.root = root
	plate.rootBase = root:GetFrameLevel()

	plate.glow = root:CreateTexture(nil, "BACKGROUND")
	plate.glow:SetTexture(E.media.glow)
	plate.glow:SetBlendMode("ADD")
	plate.glow:Hide()

	plate.health = E:CreateStatusBar(root)
	plate.health:SetAllPoints(root)

	-- Style filter glows hang on their own frame over the bar's area (the
	-- bar itself receives secret values and is never measured).
	plate.filterGlow = CreateFrame("Frame", nil, root)
	plate.filterGlow:SetAllPoints(root)

	-- Mouse-over and the "Overlay" target highlight: white sheens at the
	-- design tokens' hover strengths.
	plate.hover = plate.health:CreateTexture(nil, "OVERLAY")
	plate.hover:SetAllPoints()
	plate.hover:SetTexture(E.media.flat)
	plate.hover:SetVertexColor(1, 1, 1, E.tokens.hover.row)
	plate.hover:SetBlendMode("ADD")
	plate.hover:Hide()
	plate.overlay = plate.health:CreateTexture(nil, "OVERLAY")
	plate.overlay:SetAllPoints()
	plate.overlay:SetTexture(E.media.flat)
	plate.overlay:SetVertexColor(1, 1, 1, E.tokens.hover.control)
	plate.overlay:SetBlendMode("ADD")
	plate.overlay:Hide()
	-- "Others step back: Dim": a dark overlay that keeps the name readable.
	plate.dim = plate.health:CreateTexture(nil, "OVERLAY", nil, 7)
	plate.dim:SetAllPoints()
	plate.dim:SetTexture(E.media.flat)
	plate.dim:SetVertexColor(unpack(E.tokens.inset))
	plate.dim:Hide()
	-- The target's pulse glow and the thin threat line under the target's
	-- bar hang on their own frames (the bar receives secret values).
	plate.targetGlow = CreateFrame("Frame", nil, root)
	plate.targetGlow:SetAllPoints(root)
	plate.threatLineHolder = CreateFrame("Frame", nil, root)
	plate.threatLineHolder:SetHeight(2)

	plate.power = E:CreateStatusBar(root)
	plate.power:Hide()

	local textLayer = CreateFrame("Frame", nil, root)
	textLayer:SetAllPoints(root)
	textLayer:SetFrameLevel(plate.health:GetFrameLevel() + 3)
	plate.textLayer = textLayer
	plate.healthText = E:CreateText(textLayer, nil, "RIGHT")
	plate.nameText = E:CreateText(textLayer, nil, "LEFT")
	plate.levelText = E:CreateText(textLayer, nil, "RIGHT")
	plate.titleText = E:CreateText(textLayer, nil, "CENTER")
	plate.titleText:Hide()
	plate.questText = E:CreateText(textLayer, nil, "LEFT")
	plate.questText:Hide()

	plate.raidIcon = textLayer:CreateTexture(nil, "OVERLAY")
	plate.raidIcon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
	plate.raidIcon:Hide()

	plate.classIcon = textLayer:CreateTexture(nil, "OVERLAY")
	plate.classIcon:Hide()
	plate.questIcon = textLayer:CreateTexture(nil, "OVERLAY")
	plate.questIcon:SetAtlas(QUEST_ATLAS)
	plate.questIcon:Hide()
	plate.totemIcon = textLayer:CreateTexture(nil, "OVERLAY")
	E:TrimIcon(plate.totemIcon)
	plate.totemIcon:Hide()
	plate.petIcon = textLayer:CreateTexture(nil, "OVERLAY")
	plate.petIcon:SetAtlas("paw-icon")
	plate.petIcon:Hide()
	plate.pvpIcon = textLayer:CreateTexture(nil, "OVERLAY")
	plate.pvpIcon:Hide()
	-- The game's soft-target cursor icon above the name (Blizzard's own
	-- plate, which shows it, is faded under an EldoUI plate).
	plate.softIcon = textLayer:CreateTexture(nil, "OVERLAY")
	plate.softIcon:SetSize(20, 20)
	plate.softIcon:SetPoint("BOTTOM", plate.nameText, "TOP", 0, 2)
	plate.softIcon:Hide()

	local portrait = CreateFrame("Frame", nil, root)
	E:SetTemplate(portrait)
	portrait.texture = portrait:CreateTexture(nil, "ARTWORK")
	portrait.texture:SetPoint("TOPLEFT", E.pixel, -E.pixel)
	portrait.texture:SetPoint("BOTTOMRIGHT", -E.pixel, E.pixel)
	portrait:Hide()
	plate.portrait = portrait

	plate.arrows = {}
	for index, rotation in ipairs({ math.pi / 2, -math.pi / 2 }) do
		local arrow = textLayer:CreateTexture(nil, "OVERLAY")
		arrow:SetTexture("Interface\\AddOns\\EldoUI\\Media\\Textures\\EldoChevron.tga")
		arrow:SetRotation(rotation)
		arrow:Hide()
		plate.arrows[index] = arrow
	end
	plate.underline = textLayer:CreateTexture(nil, "OVERLAY")
	plate.underline:SetTexture(E.media.flat)
	plate.underline:Hide()

	local castbar = E:CreateStatusBar(root)
	castbar:Hide()
	castbar.text = E:CreateText(castbar, nil, "LEFT")
	castbar.time = E:CreateText(castbar, nil, "RIGHT")
	castbar.target = E:CreateText(castbar, nil, "RIGHT")
	plate.castbar = castbar
	plate.castBase = castbar:GetFrameLevel()
	-- Cast bar spark (Effects): a bright line on the fill's right edge. It
	-- hangs on the fill texture, so it is never measured.
	plate.castSpark = castbar:CreateTexture(nil, "OVERLAY", nil, 7)
	plate.castSpark:SetTexture(E.media.flat)
	plate.castSpark:SetVertexColor(1, 1, 1, 0.9)
	plate.castSpark:SetBlendMode("ADD")
	plate.castSpark:Hide()

	-- Uninterruptible shield and important-spell glow sit over the bar.
	plate.castShield = textLayer:CreateTexture(nil, "OVERLAY")
	plate.castShield:SetAtlas("nameplates-InterruptShield")
	plate.castShield:Hide()

	local interrupt = E:CreateStatusBar(root)
	interrupt:SetMinMaxValues(0, 1)
	interrupt:SetValue(1)
	interrupt.text = E:CreateText(interrupt, nil, "CENTER")
	interrupt.text:SetPoint("CENTER")
	interrupt.text:SetText(E:GameText(_G.INTERRUPTED, L["Interrupted"]))
	interrupt:Hide()
	plate.interrupt = interrupt

	local castIcon = CreateFrame("Frame", nil, root)
	E:SetTemplate(castIcon)
	castIcon.texture = castIcon:CreateTexture(nil, "ARTWORK")
	castIcon.texture:SetPoint("TOPLEFT", E.pixel, -E.pixel)
	castIcon.texture:SetPoint("BOTTOMRIGHT", -E.pixel, E.pixel)
	E:TrimIcon(castIcon.texture)
	castIcon:Hide()
	plate.castIcon = castIcon
	return plate
end

-- Sizes and points come only from settings, never from measuring widgets.
-- The icons right of the bar take room only while they show (an elite
-- icon only on an elite, quest progress only while it has text), so buffs
-- beside the bar start next to it on an ordinary mob. The two target
-- arrows sit the same distance out on both sides, past whatever a side
-- can hold.
function PlaceSideIcons(plate)
	local root = plate.root
	if not root then return end
	local icons, t = db.icons, T(plate)
	local x = 3
	if plate.classIcon:IsShown() then x = x + icons.classificationSize + 2 end
	plate.questIcon:ClearAllPoints()
	plate.questIcon:SetPoint("LEFT", root, "RIGHT", x, 0)
	plate.questText:ClearAllPoints()
	plate.questText:SetPoint("LEFT", root, "RIGHT", x + icons.questSize + 1, 0)
	if plate.questIcon:IsShown() then
		x = x + icons.questSize + 2
		if plate.questText:IsShown() then x = x + math.ceil(plate.questText:GetStringWidth() or 0) + 3 end
	end
	plate.petIcon:ClearAllPoints()
	plate.petIcon:SetPoint("LEFT", root, "RIGHT", x, 0)
	if plate.petIcon:IsShown() then x = x + icons.classificationSize + 2 end
	local moved = plate.rightOffset ~= nil and plate.rightOffset ~= x
	plate.rightOffset = x

	local buffs = db.buffs
	local leftRoom = -(plate.leftOffset or -4) + (db.cc.enabled and (db.cc.size + 2) or 0)
	local rightRoom = x
	if buffs.position == "RIGHT" and buffs.mode ~= "OFF" and t.buffs.enabled then
		rightRoom = x + t.buffs.max * (t.buffs.size + buffs.spacing)
	end
	local out = math.max(leftRoom, rightRoom)
	for index, arrow in ipairs(plate.arrows) do
		arrow:ClearAllPoints()
		if index == 1 then
			arrow:SetPoint("RIGHT", root, "LEFT", -out, 0)
		else
			arrow:SetPoint("LEFT", root, "RIGHT", out, 0)
		end
	end
	-- Buffs beside the bar follow the new room.
	if moved and buffs.position == "RIGHT" and plate.unit then UpdateAuras(plate) end
end

-- The health text inside the bar: its own size, or the plate text size
-- made small enough to stay inside a thin bar.
M.HEALTH_SPOTS = { LEFT = { "LEFT", 3 }, CENTER = { "CENTER", 0 }, RIGHT = { "RIGHT", -3 } }
function M.HealthTextSize(t, height)
	local own = tonumber(t.healthSize) or 0
	if own > 0 then return own end
	return math.min(db.fontSize, math.max(math.floor(height) - 1, 7))
end

function LayoutPlate(plate)
	local root, kind = plate.root, plate.kind
	local t = T(plate)
	local width, height = t.width, t.height
	-- Size in combat (type tabs), then a style filter's size in pixels.
	if fighting then
		if (tonumber(t.combatWidth) or 0) > 0 then width = t.combatWidth end
		if (tonumber(t.combatHeight) or 0) > 0 then height = t.combatHeight end
	end
	local ruleSize = plate.filter and plate.filter.size
	if ruleSize then
		if ruleSize[1] > 0 then width = ruleSize[1] end
		if ruleSize[2] > 0 then height = ruleSize[2] end
	end
	local full = kind == "FULL"
	local totemOnly = full and plate.isTotem and t.icons and db.icons.totem and db.icons.totemOnly
	plate.totemOnly = totemOnly
	local filterTexture = plate.filter and plate.filter.texture
	local texture = PlateTexture(filterTexture or db.texture)

	root:ClearAllPoints()
	root:SetScale(1)
	root:SetAlpha(1)
	local container = kind == "EXTRAS" and plate.nameplate.UnitFrame and plate.nameplate.UnitFrame.HealthBarsContainer
	plate.layoutContainer = container or nil
	if container then
		-- Blizzard's plate: icons sit around Blizzard's own health bar area.
		root:SetAllPoints(container)
	else
		root:SetSize(width, height)
		root:SetPoint("CENTER", plate.nameplate, "CENTER", 0, db.offsetY)
	end

	plate.health:SetShown(full and not totemOnly)
	plate.health:SetStatusBarTexture(texture)
	PlateEdge.Paint(plate)

	local glowSize = 6
	plate.glow:ClearAllPoints()
	plate.glow:SetPoint("TOPLEFT", root, "TOPLEFT", -glowSize, glowSize)
	plate.glow:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", glowSize, -glowSize)

	-- Power: a thin bar right under the health bar.
	local powerShown = full and not totemOnly and t.power
	local power = plate.power
	power:ClearAllPoints()
	power:SetShown(powerShown and true or false)
	local powerRoom = 0
	if powerShown then
		power:SetPoint("TOPLEFT", root, "BOTTOMLEFT", 0, -E.pixel * 2)
		power:SetPoint("TOPRIGHT", root, "BOTTOMRIGHT", 0, -E.pixel * 2)
		power:SetHeight(t.powerHeight)
		power:SetStatusBarTexture(texture)
		powerRoom = t.powerHeight + E.pixel * 2
	end

	local size = db.fontSize
	SetPlateFont(plate.healthText, M.HealthTextSize(t, height))
	local spot = M.HEALTH_SPOTS[t.healthPosition] or M.HEALTH_SPOTS.RIGHT
	plate.healthText:ClearAllPoints()
	plate.healthText:SetPoint(spot[1], root, spot[1], spot[2], 0)
	plate.healthText:SetJustifyH(spot[1])
	plate.healthText:SetShown(full and not totemOnly)

	-- Texts above the bar start clear of its border.
	local textGap = E.pixel + M.ROW_GAP
	local levelShown = full and not totemOnly and t.levelTag.preset ~= "off"
	SetPlateFont(plate.levelText, size)
	plate.levelText:ClearAllPoints()
	plate.levelText:SetPoint("BOTTOMRIGHT", root, "TOPRIGHT", 0, textGap)
	plate.levelText:SetShown(levelShown)

	-- PvP badge left of the name, top left of the bar.
	local pvpSize = db.icons.pvpSize
	local pvpRoom = (t.pvp ~= "NONE" and kind ~= "EXTRAS") and pvpSize + 2 or 0
	plate.pvpIcon:SetSize(pvpSize, pvpSize)
	plate.pvpIcon:ClearAllPoints()
	if kind == "NAME" then
		plate.pvpIcon:SetPoint("RIGHT", plate.nameText, "LEFT", -2, 0)
	else
		plate.pvpIcon:SetPoint("BOTTOMLEFT", root, "TOPLEFT", 0, 1)
	end

	-- Name: above the bar, or alone in the middle on name-only plates.
	local name = plate.nameText
	SetPlateNameFont(name, kind == "NAME" and size + 1 or size)
	name:ClearAllPoints()
	local levelRoom = levelShown and (size * 2 + 4) or 0
	if kind == "NAME" then
		name:SetJustifyH("CENTER")
		name:SetPoint("CENTER", root, "CENTER", 0, 0)
		name:SetWidth(math.max(width, 20))
	elseif t.nameText == "CENTER" then
		name:SetJustifyH("CENTER")
		name:SetPoint("BOTTOM", root, "TOP", 0, textGap)
		name:SetWidth(math.max(width - 2 * levelRoom, 20))
	else
		name:SetJustifyH("LEFT")
		name:SetPoint("BOTTOMLEFT", root, "TOPLEFT", pvpRoom, textGap)
		name:SetWidth(math.max(width - levelRoom - pvpRoom, 20))
	end
	name:SetShown(kind == "NAME" or (full and not totemOnly and t.nameText ~= "NONE"))

	-- NPC title: under the name on name-only plates, above it otherwise.
	local titleShown = t.title and (kind == "NAME" or (full and not totemOnly)) and not Query(UnitIsPlayer, plate.unit)
	local title = plate.titleText
	local titleSize = math.max(size - 2, 6)
	SetPlateNameFont(title, titleSize)
	title:ClearAllPoints()
	title:SetWidth(math.max(width, 20))
	if kind == "NAME" then
		title:SetPoint("TOP", name, "BOTTOM", 0, -1)
	else
		title:SetPoint("BOTTOM", root, "TOP", 0, textGap + (t.nameText ~= "NONE" and M.TextRow(size) + M.ROW_GAP or 0))
	end
	title:SetShown(titleShown and true or false)

	local textAbove = full and not totemOnly and (t.nameText ~= "NONE" or levelShown)
	plate.debuffOffset = textGap + (textAbove and (M.TextRow(size) + M.ROW_GAP) or 0)
		+ ((titleShown and kind ~= "NAME") and (M.TextRow(titleSize) + M.ROW_GAP) or 0)
	plate.buffOffset = plate.debuffOffset + (t.debuffs.enabled and (t.debuffs.size + M.ROW_GAP) or 0)
	-- Room above everything over the bar (GetPlateAnchor(unit, "text")).
	if kind == "NAME" then
		plate.textOffset = math.max(math.floor((size + 1 - height) / 2), 0) + 3
	else
		plate.textOffset = plate.buffOffset + ((t.buffs.enabled and db.buffs.position ~= "RIGHT") and (t.buffs.size + M.ROW_GAP) or 0)
	end

	-- Left of the bar: portrait, raid marker, then crowd control.
	local left = -4
	local portrait = plate.portrait
	portrait:ClearAllPoints()
	local portraitShown = t.portrait and full and not totemOnly
	portrait:SetShown(portraitShown and true or false)
	if portraitShown then
		local portraitSize = math.max(height + powerRoom + 6, 14)
		portrait:SetSize(portraitSize, portraitSize)
		portrait:SetPoint("TOPRIGHT", root, "TOPLEFT", -2, 3)
		left = left - portraitSize
	end
	plate.raidIcon:SetSize(db.raidMarkerSize, db.raidMarkerSize)
	plate.raidIcon:ClearAllPoints()
	plate.raidIcon:SetPoint("RIGHT", root, "LEFT", left, 0)
	plate.leftOffset = left - (t.raidMarker and (db.raidMarkerSize + 2) or 0)

	-- Right of the bar: elite/rare icon, quest icon, pet icon, then buffs
	-- (placed by PlaceSideIcons from what the unit shows).
	local icons = db.icons
	plate.classIcon:SetSize(icons.classificationSize, icons.classificationSize)
	plate.classIcon:ClearAllPoints()
	plate.classIcon:SetPoint("LEFT", root, "RIGHT", 3, 0)
	plate.questIcon:SetSize(icons.questSize, icons.questSize)
	SetPlateNameFont(plate.questText, math.max(size - 1, 6))
	plate.petIcon:SetSize(icons.classificationSize, icons.classificationSize)

	plate.totemIcon:SetSize(icons.totemSize, icons.totemSize)
	plate.totemIcon:ClearAllPoints()
	if totemOnly then
		plate.totemIcon:SetPoint("CENTER", root, "CENTER", 0, 0)
	else
		plate.totemIcon:SetPoint("BOTTOM", root, "TOP", 0, plate.debuffOffset)
	end

	-- Target arrows, outside the icons on both sides, and underline.
	local arrowSize = math.max(height + 4, 12)
	for _, arrow in ipairs(plate.arrows) do arrow:SetSize(arrowSize, arrowSize) end
	plate.rightOffset = nil
	PlaceSideIcons(plate)
	plate.underline:ClearAllPoints()
	plate.underline:SetPoint("TOPLEFT", root, "BOTTOMLEFT", 0, -1 - powerRoom)
	plate.underline:SetPoint("TOPRIGHT", root, "BOTTOMRIGHT", 0, -1 - powerRoom)
	plate.underline:SetHeight(2)
	-- The threat line under your target's bar (Effects, Threat border).
	plate.threatLineHolder:ClearAllPoints()
	plate.threatLineHolder:SetPoint("TOPLEFT", root, "BOTTOMLEFT", 0, -E.pixel)
	plate.threatLineHolder:SetPoint("TOPRIGHT", root, "BOTTOMRIGHT", 0, -E.pixel)
	plate.threatLineHolder:SetHeight(math.max(E.pixel * 2, 1))

	-- Cast bar under the health (and power) bar, icon left or right.
	local cast, castT = db.castbar, t.castbar
	local castbar, castIcon = plate.castbar, plate.castIcon
	-- The style's gap between the borders of the bar above and the cast bar.
	local top = -(cast.gap + E.pixel * 2) - powerRoom
	local iconSize = (castT.iconSize > 0 and castT.iconSize or castT.height) + E.pixel * 2
	local iconSide = castT.icon
	castbar:ClearAllPoints()
	castbar:SetPoint("TOPLEFT", root, "BOTTOMLEFT", iconSide == "LEFT" and iconSize or 0, top)
	castbar:SetPoint("TOPRIGHT", root, "BOTTOMRIGHT", iconSide == "RIGHT" and -iconSize or 0, top)
	castbar:SetHeight(castT.height)
	castbar:SetStatusBarTexture(texture)
	local spark = plate.castSpark
	spark:ClearAllPoints()
	spark:SetPoint("CENTER", castbar:GetStatusBarTexture(), "RIGHT", 0, 0)
	spark:SetSize(math.max(E.pixel * 2, 1), castT.height + 2)
	castIcon:ClearAllPoints()
	if iconSide == "RIGHT" then
		castIcon:SetPoint("TOPRIGHT", root, "BOTTOMRIGHT", 0, top + E.pixel)
	else
		castIcon:SetPoint("TOPLEFT", root, "BOTTOMLEFT", 0, top + E.pixel)
	end
	castIcon:SetSize(iconSize, iconSize)
	SetPlateNameFont(castbar.text, castT.nameSize)
	SetPlateFont(castbar.time, castT.timeSize)
	SetPlateNameFont(castbar.target, math.max(castT.nameSize - 1, 6))
	local timeRoom = castT.time == "TOTAL" and castT.timeSize * 4 or castT.timeSize * 2.5
	castbar.text:ClearAllPoints()
	castbar.text:SetPoint("LEFT", castbar, "LEFT", 3, 0)
	castbar.text:SetPoint("RIGHT", castbar, "RIGHT", castT.time ~= "NONE" and -timeRoom or -3, 0)
	castbar.time:ClearAllPoints()
	castbar.time:SetPoint("RIGHT", castbar, "RIGHT", -3, 0)
	castbar.time:SetShown(castT.time ~= "NONE")
	castbar.timeMode = castT.time
	castbar.target:ClearAllPoints()
	castbar.target:SetPoint("TOPRIGHT", castbar, "BOTTOMRIGHT", 0, -1)
	castbar.target:SetWidth(math.max(width - iconSize, 20))
	local castTarget = ShowCastTarget(plate) and true or false
	castbar.target:SetShown(castTarget)

	local shieldSize = castT.height + 4
	plate.castShield:SetSize(shieldSize * 0.85, shieldSize)
	plate.castShield:ClearAllPoints()
	if iconSide ~= "NONE" then
		plate.castShield:SetPoint("CENTER", castIcon, "CENTER", 0, 0)
	else
		plate.castShield:SetPoint("RIGHT", castbar, "LEFT", -2, 0)
	end

	local interrupt = plate.interrupt
	interrupt:ClearAllPoints()
	interrupt:SetAllPoints(castbar)
	interrupt:SetStatusBarTexture(texture)
	SetPlateNameFont(interrupt.text, castT.nameSize)

	-- Below the plate (combo points from Player Power): under the cast bar.
	plate.belowOffset = full and (top - (castT.enabled and (castT.height + 3) or 0) - (castTarget and castT.nameSize or 0)) or -2
	if plate.widgets then
		-- Blizzard's widgets (escort bars, capture progress) under everything.
		plate.widgets:ClearAllPoints()
		plate.widgets:SetPoint("TOP", root, "BOTTOM", 0, plate.belowOffset)
	end
	if plate.unit and not plate.preview then FirePlateCallback("LAYOUT", plate.unit, plate.nameplate, kind) end
end

-- `instant`: the plate was just set up for a new unit.
function UpdatePlate(plate, instant)
	UpdateHealth(plate, instant)
	UpdatePower(plate)
	UpdateColor(plate)
	BindTexts(plate)
	UpdateRaidMarker(plate)
	UpdateIcons(plate)
	UpdateAuras(plate)
	RefreshCast(plate)
	UpdateThreatFX(plate)
	UpdateExecute(plate)
	UpdateAbsorb(plate)
	UpdateRuleGates(plate)
	-- The plate's unit events follow the parts it shows now.
	local unit = plate.unit
	if unit and plates[unit] == plate then WatchPlateUnit(plate, unit) end
end

---------------------------------------------------------------------------
-- Blizzard's own plate visuals in EldoUI mode: faded, not hidden or
-- reparented, so the protected nameplate and Blizzard's code paths stay
-- untouched.
-- Blizzard sets the UnitFrame's alpha back to 1 while the frame is already
-- shown: CompactUnitFrame_UpdateCenterStatusIcon ends with
-- frame:SetAlpha(CompactUnitFrame_GetRangeAlpha(frame)), and it runs on
-- every frame setup and on UNIT_FLAGS (entering and leaving combat),
-- UNIT_PHASE, summons, resurrections and vehicles. Without an answer to
-- that, Blizzard's plate shows up again under ours. So the frame's SetAlpha
-- and OnShow are hooked (hooksecurefunc: Blizzard's call runs untouched
-- first) and fade the frame again while it still belongs to a plate EldoUI
-- draws. Pieces that ignore their parent's alpha (the selection highlight,
-- and any other the client marks that way) are faded on their own and get
-- their alpha back with the frame. The hooks go in once per frame and do
-- nothing while the frame belongs to a plate EldoUI does not draw.
---------------------------------------------------------------------------
local FadeBlizzard, RestoreBlizzard
do
-- The frame's descendants that ignore their parent's alpha, with the
-- selection highlight first. Read each time the frame starts a fade.
-- The client may answer the "ignores parent alpha" question with a secret
-- boolean, which Lua may not compare. Such a piece is faded on its own as
-- well: fading a piece that follows its parent anyway changes nothing, and
-- its alpha comes back with the frame.
local function IgnoresParentAlpha(region)
	local ok, ignores = pcall(region.IsIgnoringParentAlpha, region)
	if not ok then return false end
	if IsSecret(ignores) then return true end
	return ignores == true
end

local function OwnAlphaPieces(unitFrame)
	local list, seen = {}, {}
	local function Add(region)
		if region and not seen[region] then
			seen[region] = true
			list[#list + 1] = region
		end
	end
	Add(unitFrame.selectionHighlight)
	local function Walk(frame, depth)
		if depth > 4 then return end
		local okRegions, regions = pcall(function() return { frame:GetRegions() } end)
		for _, region in ipairs(okRegions and regions or {}) do
			if IgnoresParentAlpha(region) then Add(region) end
		end
		local okChildren, children = pcall(function() return { frame:GetChildren() } end)
		for _, child in ipairs(okChildren and children or {}) do
			if IgnoresParentAlpha(child) then Add(child) end
			Walk(child, depth + 1)
		end
	end
	Walk(unitFrame, 1)
	return list
end

-- Quiet Blizzard plates: while EldoUI draws every unit type, Blizzard's
-- UnitFrame and its cast bar under each EldoUI plate stop taking events,
-- so the plate's work is not done twice. Method calls only: no replaced
-- functions, no fields written, no reparenting. Blizzard registers its unit
-- events again when it sets the frame up for the next unit; the events it
-- registers once at load come back only with a reload, so once any type
-- goes back to Blizzard's plates (or the module goes off) EldoUI asks for
-- one.
local quietFrames = setmetatable({}, { __mode = "k" })
local anyQuiet, reloadAsked = false, false
local function QuietWanted()
	if PlateMode() ~= "ELDOUI" or not db then return false end
	for _, key in ipairs({ "enemyNPC", "enemyPlayer", "friendlyNPC", "friendlyPlayer" }) do
		local t = db.types[key]
		if not (t and t.enabled) then return false end
	end
	return true
end
local function Quiet(unitFrame)
	if not unitFrame or E.FrameCheck(unitFrame, "IsForbidden") or not QuietWanted() then return end
	pcall(unitFrame.UnregisterAllEvents, unitFrame)
	local container = unitFrame.CastBarsContainer
	local castBar = unitFrame.castBar or (container and container.castBar)
	if castBar and not E.FrameCheck(castBar, "IsForbidden") then pcall(castBar.UnregisterAllEvents, castBar) end
	quietFrames[unitFrame] = true
	anyQuiet = true
end
-- Blizzard has just set a plate up for `unit` (its unit events are back):
-- quiet it again while an EldoUI plate covers it.
local function OnBlizzardAdded(unit)
	local nameplate = PlateFor(unit)
	local unitFrame = nameplate and nameplate.UnitFrame
	if not unitFrame then return end
	quietFrames[unitFrame] = nil
	local plate = pool[nameplate]
	if hiddenBlizzard[unitFrame] and plate and plates[unit] == plate and plate.kind ~= "EXTRAS" then Quiet(unitFrame) end
end
local driverFrame = _G.NamePlateDriverFrame
if driverFrame and type(driverFrame.OnNamePlateAdded) == "function" then
	hooksecurefunc(driverFrame, "OnNamePlateAdded", function(_, unit) OnBlizzardAdded(unit) end)
end
-- Settings or switches changed: quiet frames left while Blizzard's plates
-- are wanted again ask once (each time that happens) for the reload that
-- brings their events back.
function M:CheckQuietPlates()
	if QuietWanted() then
		reloadAsked = false
		return
	end
	if not anyQuiet or reloadAsked then return end
	reloadAsked = true
	E:ShowReloadPrompt(L["Blizzard's nameplates update fully again after a reload."])
end

function FadeBlizzard(unitFrame)
	if not unitFrame then return end
	if E.FrameCheck(unitFrame, "IsForbidden") then return end
	hiddenBlizzard[unitFrame] = true
	local state = hooked[unitFrame]
	if not state then
		state = {}
		hooked[unitFrame] = state
		local function Reassert(self)
			if state.busy or not hiddenBlizzard[self] or PlateMode() ~= "ELDOUI" then return end
			-- Only while its nameplate carries an EldoUI plate: a pooled
			-- frame on its way to another plate is left to OnPlateAdded.
			local ok, parent = pcall(self.GetParent, self)
			local plate = ok and parent and pool[parent]
			if not (plate and plate.unit and plates[plate.unit] == plate) then return end
			state.busy = true
			pcall(self.SetAlpha, self, 0)
			state.busy = false
		end
		pcall(unitFrame.HookScript, unitFrame, "OnShow", Reassert)
		pcall(hooksecurefunc, unitFrame, "SetAlpha", Reassert)
		state.hooks = (state.hooks or 0) + 1
	end
	state.busy = true
	pcall(unitFrame.SetAlpha, unitFrame, 0)
	state.busy = false
	local okParent, nameplate = pcall(unitFrame.GetParent, unitFrame)
	local plate = okParent and nameplate and pool[nameplate]
	if plate and plate.unit and plates[plate.unit] == plate and plate.kind ~= "EXTRAS" then Quiet(unitFrame) end
	if not state.alphas then
		state.pieces, state.alphas = OwnAlphaPieces(unitFrame), {}
		for index, piece in ipairs(state.pieces) do
			local ok, alpha = pcall(piece.GetAlpha, piece)
			-- The highlight's own alpha is 0.25 (Blizzard's template).
			local fallback = piece == unitFrame.selectionHighlight and 0.25 or 1
			state.alphas[index] = (ok and type(alpha) == "number" and not E:IsSecret(alpha)) and alpha or fallback
			pcall(piece.SetAlpha, piece, 0)
		end
	end
end

function RestoreBlizzard(unitFrame)
	if not unitFrame or not hiddenBlizzard[unitFrame] then return end
	hiddenBlizzard[unitFrame] = nil
	pcall(unitFrame.SetAlpha, unitFrame, 1)
	local state = hooked[unitFrame]
	if state and state.alphas then
		for index, piece in ipairs(state.pieces) do
			pcall(piece.SetAlpha, piece, state.alphas[index])
		end
		state.alphas = nil
	end
end
end

---------------------------------------------------------------------------
-- Blizzard style with the EldoUI look (Skin switch): bar texture, flat
-- background, a 1 px border and the nameplate font on Blizzard's plate.
-- Blizzard re-applies its art whenever it sets a plate up, so the mixin is
-- hooked and every hook run checks the switches first. Undoing it fully
-- needs a /reload (registered as reload = { skin = true }).
---------------------------------------------------------------------------
local function SkinWanted()
	return PlateMode() == "BLIZZARD" and Allowed("skin")
end

local function SkinBlizzard(unitFrame)
	if not unitFrame or not SkinWanted() then return end
	if E.FrameCheck(unitFrame, "IsForbidden") then return end
	local container = unitFrame.HealthBarsContainer
	local bar = container and container.healthBar
	local texture = PlateTexture(db.texture)
	if bar then
		pcall(bar.SetStatusBarTexture, bar, texture)
		local bg = bar.bgTexture
		if bg then
			pcall(bg.SetTexture, bg, E.media.flat)
			pcall(bg.SetVertexColor, bg, unpack(E.media.backdropColor))
		end
	end
	if container then
		local border = skinBorders[unitFrame]
		if not border then
			-- Our own unnamed child of the UnitFrame (it follows the frame
			-- from plate to plate), anchored to Blizzard's container, never
			-- to the health bar, which receives secret values.
			local ok, frame = pcall(CreateFrame, "Frame", nil, unitFrame)
			if not ok then return end
			border = frame
			E:SetTemplate(border)
			border:SetBackdropColor(0, 0, 0, 0)
			skinBorders[unitFrame] = border
		end
		border:ClearAllPoints()
		border:SetPoint("TOPLEFT", container, "TOPLEFT", -E.pixel, E.pixel)
		border:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", E.pixel, -E.pixel)
		border:SetFrameLevel(unitFrame:GetFrameLevel() + 5)
		border:SetBackdropBorderColor(unpack(E.media.borderColor))
		border:Show()
	end
	if unitFrame.name then pcall(SetPlateNameFont, unitFrame.name, db.fontSize) end
	local castBar = unitFrame.CastBarsContainer and unitFrame.CastBarsContainer.castBar
	if castBar and castBar.Text then pcall(SetPlateNameFont, castBar.Text, db.types.enemyNPC.castbar.nameSize) end
end

local function HideSkinBorders()
	for _, border in pairs(skinBorders) do border:Hide() end
end

-- Hooked once, on the mixin, before Blizzard creates its plate frames.
local mixinHooked = false
local function HookBlizzardMixin()
	local mixin = _G.NamePlateUnitFrameMixin
	if mixinHooked or not mixin then return end
	mixinHooked = true
	for _, method in ipairs({ "ApplyFrameOptions", "UpdateAnchors" }) do
		if type(mixin[method]) == "function" then
			hooksecurefunc(mixin, method, function(unitFrame)
				if db and SkinWanted() then SkinBlizzard(unitFrame) end
			end)
		end
	end
end

-- One block, so its helpers do not count towards the chunk's 200 locals;
-- only these are used further down.
local ClearEffects, ReAdd, OnPlateAdded, OnPlateRemoved
do
---------------------------------------------------------------------------
-- Nameplate added / removed
---------------------------------------------------------------------------
-- The plate type of a unit, and whether it is friendly.
local function TypeOf(unit)
	local friendly = Query(UnitIsFriend, "player", unit) and true or false
	local player = Query(UnitIsPlayer, unit) and true or false
	return (friendly and "friendly" or "enemy") .. (player and "Player" or "NPC"), friendly
end

-- Minor (trivial) units and pets: plain answers only.
local function IsMinor(unit)
	return Query(UnitClassification, unit) == "minus"
end

local function IsPet(unit)
	return Query(UnitIsPlayer, unit) == false and Query(UnitPlayerControlled, unit) == true
end

-- Units whose plate only shows Blizzard widgets (escort bars, capture
-- progress) keep Blizzard's plate: the game's plain answer only.
local function WidgetsOnly(unit)
	return Query(UnitNameplateShowsWidgetsOnly, unit) == true
end

-- What we draw for a unit: "FULL" (EldoUI plate), "NAME" (name only),
-- "EXTRAS" (only our icons around Blizzard's plate) or nil (nothing).
local function PlateKind(unit, nameplate, mode)
	-- Personal resource display: compared as frames, unit identity can be secret.
	if PlateFor("player") == nameplate then return nil end
	if WidgetsOnly(unit) then return nil end
	-- A game object with a soft-interact plate (a fishing bobber, an herb or
	-- ore node): the game uses that plate only for its interact icon, so it
	-- keeps Blizzard's plate and gets no EldoUI health bar.
	if Query(UnitIsGameObject, unit) == true then return nil end
	local typeKey = TypeOf(unit)
	if mode == "ELDOUI" then
		local t = db.types[typeKey]
		if not t.enabled then return nil end
		if t.nameOnly then return "NAME" end
		-- "Simple plates for minor units" (Game settings).
		if db.simplifyMinor and IsMinor(unit) then return "NAME" end
		return "FULL"
	elseif mode == "BLIZZARD" and Allowed("improve") then
		return "EXTRAS"
	end
end

-- Blizzard's own simplified plate for minor units (Blizzard plates). Only
-- the plates EldoUI simplified are set back.
local simplified = {}

local function Simplify(unit, mode)
	local api = C_NamePlateManager and C_NamePlateManager.SetNamePlateSimplified
	if not api then return end
	local want = mode == "BLIZZARD" and db.simplifyMinor and IsMinor(unit)
	if want then
		if pcall(api, unit, true) then simplified[unit] = true end
	elseif simplified[unit] then
		pcall(api, unit, false)
		simplified[unit] = nil
	end
end

-- Blizzard's widgets on EldoUI plates: an EldoUI-owned container
-- (Blizzard's own sits in the faded UnitFrame and is never reparented).
local function UpdateWidgets(plate)
	local unit = plate.unit
	local setID = unit and plate.kind ~= "EXTRAS" and Query(UnitWidgetSet, unit)
	if type(setID) ~= "number" or setID <= 0 then
		if plate.widgetSet and plate.widgets then pcall(plate.widgets.UnregisterForWidgetSet, plate.widgets) end
		plate.widgetSet = nil
		if plate.widgets then plate.widgets:Hide() end
		return
	end
	if not plate.widgets then
		local ok, container = pcall(CreateFrame, "Frame", nil, plate.root, "UIWidgetContainerTemplate")
		if not ok or not container or not container.RegisterForWidgetSet then return end
		container:EnableMouse(false)
		-- The game fills the container with its own widgets: border snapping
		-- of the plate never walks into them.
		if E.SkipSnap then E:SkipSnap(container) end
		plate.widgets = container
		LayoutPlate(plate)
	end
	if plate.widgetSet ~= setID then
		if plate.widgetSet then pcall(plate.widgets.UnregisterForWidgetSet, plate.widgets) end
		if pcall(plate.widgets.RegisterForWidgetSet, plate.widgets, setID, _G.DefaultWidgetLayout, nil, unit) then
			plate.widgetSet = setID
		else
			plate.widgetSet = nil
		end
	end
	plate.widgets:SetShown(plate.widgetSet ~= nil)
end

local function ReleaseWidgets(plate)
	if plate.widgets and plate.widgetSet then pcall(plate.widgets.UnregisterForWidgetSet, plate.widgets) end
	plate.widgetSet = nil
	if plate.widgets then plate.widgets:Hide() end
end

-- Every effect gate of a plate closed (the frame goes to another unit).
function ClearEffects(plate)
	for _, field in ipairs({ "threatGate", "threatLine", "executeGate", "executeUpper", "importantGate", "ruleInner", "ruleOuter" }) do
		ClearGate(plate, field)
	end
	if plate.absorb then E:UpdateAbsorb(nil, plate.absorb, false) end
	if plate.targetPulse then
		E:HideGlow(plate.targetGlow)
		plate.targetPulse = nil
	end
	plate.isTarget, plate.isDetailTarget, plate.ruleGated, plate.questWas = nil, nil, nil, nil
end

-- Blizzard sets a plate up in the same event and may hand it a pooled
-- UnitFrame after our handler ran, so every plate added this frame is
-- looked at once more on the next one: one pass for all of them.
-- Two sets of lists: a plate added while one set is looked at goes into
-- the other one.
local nextPlate = {} -- unit -> our plate, or false when EldoUI draws nothing on it
local nextFrame = {} -- unit -> Blizzard's nameplate
local otherPlate, otherFrame = {}, {}
local nextPending = false

local function NextFramePass()
	nextPending = false
	local platesNow, framesNow = nextPlate, nextFrame
	nextPlate, nextFrame, otherPlate, otherFrame = otherPlate, otherFrame, platesNow, framesNow
	for unit, nameplate in pairs(framesNow) do
		local plate = platesNow[unit]
		local unitFrame = nameplate.UnitFrame
		if unitFrame == nil then
			plate = nil -- nothing to look at
		end
		if plate == false then
			if not plates[unit] then
				RestoreBlizzard(unitFrame)
				if PlateMode() == "BLIZZARD" then SkinBlizzard(unitFrame) end
			end
		elseif plate and plates[unit] == plate then
			if PlateMode() == "ELDOUI" then
				FadeBlizzard(unitFrame)
			else
				RestoreBlizzard(unitFrame)
				SkinBlizzard(unitFrame)
				-- Icons sit on Blizzard's health bar: again only when the
				-- plate got another UnitFrame.
				if plate.kind ~= "EXTRAS" or plate.layoutContainer ~= unitFrame.HealthBarsContainer then LayoutPlate(plate) end
			end
		end
	end
	wipe(platesNow)
	wipe(framesNow)
end

local function CheckNextFrame(unit, nameplate, plate)
	nextPlate[unit], nextFrame[unit] = plate, nameplate
	if not nextPending then
		nextPending = true
		C_Timer.After(0, NextFramePass)
	end
end

function OnPlateAdded(unit)
	local nameplate = PlateFor(unit)
	if not nameplate then return end -- forbidden plates are not handed to addons
	if E.FrameCheck(nameplate, "IsForbidden") then return end
	local mode = PlateMode()
	local unitFrame = nameplate.UnitFrame
	local kind = mode ~= "OFF" and PlateKind(unit, nameplate, mode)
	Simplify(unit, mode)

	-- Unit token reuse (mind control, vehicles): a token added on a new
	-- plate releases the plate that still had it.
	local stale = plates[unit]
	if stale and stale.nameplate ~= nameplate then OnPlateRemoved(unit) end

	local plate = pool[nameplate]
	-- The frame may still be bound to its previous unit's token.
	if plate and plate.unit and plate.unit ~= unit and plates[plate.unit] == plate then OnPlateRemoved(plate.unit) end
	if not kind then
		-- A reused frame may still carry our look from its last unit.
		if plate then
			plate.root:Hide()
			if plate.unit and plates[plate.unit] == plate then plates[plate.unit] = nil end
			plate.unit = nil
			plate.filter = nil
			UnwatchPlateUnit(plate)
			UnbindTexts(plate)
			-- Its aura rows and cast bar stop following the old unit too.
			ClearAuraContainers(plate)
			HideCast(plate)
			ClearEffects(plate)
			ReleaseWidgets(plate)
		end
		RestoreBlizzard(unitFrame)
		if mode == "BLIZZARD" then SkinBlizzard(unitFrame) end
		-- Blizzard may hand this plate a pooled UnitFrame we faded earlier
		-- after our handler ran; check again next frame.
		CheckNextFrame(unit, nameplate, false)
		FirePlateCallback("ADDED", unit, nameplate, false)
		return
	end

	if not plate then
		plate = CreatePlate(nameplate)
		pool[nameplate] = plate
	end
	ClearEffects(plate)
	plate.unit = unit
	plate.typeKey, plate.friendly = TypeOf(unit)
	plate.isPlayer = Query(UnitIsPlayer, unit) and true or false
	plate.enemyNPC = not plate.friendly and not plate.isPlayer
	plate.isPet = IsPet(unit)
	-- Minor units and pets scale (General tab).
	local scale = 1
	if IsMinor(unit) then scale = scale * (tonumber(db.minorScale) or 100) / 100 end
	if plate.isPet then scale = scale * (tonumber(db.petScale) or 100) / 100 end
	plate.sizeScale = scale
	plate.kind, plate.baseKind = kind, kind
	plate.filter = nil
	plate.castHiddenAt = nil
	plate.isTotem = IsTotem(unit)
	-- Who the kept quest progress belongs to: the unit's GUID, or this
	-- setup of the plate when the game keeps the GUID hidden.
	local okGUID, guid = pcall(UnitGUID, unit)
	guid = okGUID and Plain(guid)
	if type(guid) ~= "string" then
		questState.serial = questState.serial + 1
		guid = questState.serial
	end
	plate.questKey = guid
	plates[unit] = plate
	LayoutPlate(plate)
	plate.root:Show()
	if mode == "ELDOUI" then
		FadeBlizzard(unitFrame)
	else
		RestoreBlizzard(unitFrame)
		SkinBlizzard(unitFrame)
	end
	CheckNextFrame(unit, nameplate, plate)

	UpdatePlate(plate, true)
	if mode == "ELDOUI" then UpdateWidgets(plate) end
	Soft.UpdateIcon(plate)
	if kind == "EXTRAS" then
		TargetStateFor(plate)
	else
		ApplyFilters(plate)
	end
	FirePlateCallback("ADDED", unit, nameplate, kind)
end

function OnPlateRemoved(unit)
	local plate = plates[unit]
	FirePlateCallback("REMOVED", unit, plate and plate.nameplate or PlateFor(unit), plate and plate.kind or false)
	simplified[unit] = nil
	if not plate then return end
	plates[unit] = nil
	plate.unit = nil
	plate.filter = nil
	UnbindTexts(plate)
	E:HideGlow(plate.filterGlow)
	ClearAuraContainers(plate)
	HideCast(plate)
	ClearEffects(plate)
	ReleaseWidgets(plate)
	plate.interrupt:Hide()
	plate.softIcon:Hide()
	plate.root:Hide()
	-- Blizzard's UnitFrame stays faded: the frame is reused for the next
	-- unit, and OnPlateAdded restores it if that unit isn't styled.
end

-- A unit changed sides (duel, mind control): set its plate up again.
function ReAdd(plate)
	local unit = plate.unit
	if not unit then return end
	OnPlateRemoved(unit)
	OnPlateAdded(unit)
end

-- Where another module hangs a piece on the plate of `unit`:
--   frame, point, relativePoint, y  ->  SetPoint(point, frame, relativePoint, 0, y)
-- what = nil or "below": under the plate (below an EldoUI plate's cast
--   bar), where Player Power hangs your combo points.
-- what = "text": above everything over the bar (name, auras), for
--   floating text such as combat text numbers.
-- `frame` is EldoUI's plate root (it never holds secret values, so pieces
-- anchored to it stay measurable) or Blizzard's plate; parent the piece to
-- it to follow the plate's scale and alpha. nil for forbidden plates.
-- "ELDOUI", "BLIZZARD" or "OFF" (plate callbacks only fire while not OFF).
function M:GetPlateMode()
	return PlateMode()
end

function M:GetPlateAnchor(unit, what)
	local nameplate = PlateFor(unit)
	if not nameplate or E.FrameCheck(nameplate, "IsForbidden") then return nil end
	local plate = pool[nameplate]
	local ours = plate and plate.unit and plate.root:IsShown() and plate.kind ~= "EXTRAS"
	if what == "text" then
		if ours then return plate.root, "BOTTOM", "TOP", plate.textOffset or 0 end
		return nameplate, "BOTTOM", "TOP", 0
	end
	if ours then
		return plate.root, "TOP", "BOTTOM", plate.belowOffset or -2
	end
	return nameplate, "TOP", "BOTTOM", 0
end
end

---------------------------------------------------------------------------
-- Test plate: a plate near the screen center that shows the chosen type
-- with your own character's data, for styling out of a fight.
---------------------------------------------------------------------------
local function LayoutPreview()
	if not preview then return end
	local plate = preview
	plate.typeKey = db.testType
	plate.friendly = plate.typeKey == "friendlyNPC" or plate.typeKey == "friendlyPlayer"
	local t = T(plate)
	plate.kind = t.nameOnly and "NAME" or "FULL"
	plate.baseKind = plate.kind
	plate.isTotem = false
	plate.filter = nil
	plate.root:Show()
	LayoutPlate(plate)
	UpdatePlate(plate)
	TargetStateFor(plate)
	-- A still cast bar, so its layout can be judged too.
	local castbar = plate.castbar
	if plate.kind == "FULL" and t.castbar.enabled then
		castbar.hasDuration, castbar.endTime = false, nil
		castbar:SetMinMaxValues(0, 1)
		castbar:SetValue(0.6)
		castbar:SetStatusBarColor(CAST_NORMAL:GetRGB())
		castbar.text:SetText(db.castbar.spellName and L["Test cast"] or "")
		castbar.time:SetText(t.castbar.time == "TOTAL" and "1.0 / 2.5" or "1.0")
		plate.castIcon.texture:SetTexture(136243)
		plate.castIcon:SetShown(t.castbar.icon ~= "NONE")
		local spark = FX("castSpark")
		plate.castSpark:SetShown(spark and spark.enabled and true or false)
		castbar:Show()
	else
		castbar:Hide()
		plate.castIcon:Hide()
	end
end

function M:ToggleTestPlate(show)
	if show == nil then show = not (preview and preview.holder:IsShown()) end
	if not show then
		if preview then
			preview.holder:Hide()
			UnbindTexts(preview)
			ClearAuraContainers(preview)
		end
		return
	end
	if not self.active then return end
	if not preview then
		local holder = CreateFrame("Frame", nil, UIParent)
		holder:SetSize(1, 1)
		holder:SetPoint("CENTER", UIParent, "CENTER", 0, 180)
		holder:SetFrameStrata("HIGH")
		preview = CreatePlate(holder)
		preview.holder = holder
		preview.preview = true
	end
	preview.unit = "player"
	preview.holder:Show()
	LayoutPreview()
end

-- "Show effects on the test plate" (General tab): every effect in turn on
-- the test plate with fixed sample values, so the look can be judged out
-- of a fight. It shows each effect even while its row is off.
do
local TEST_STEP = 1.6 -- seconds per effect
local testToken

local function ClearTestEffects(plate)
	ClearEffects(plate)
	if plate.absorb then
		plate.absorb.bar:Hide()
		plate.absorb.marker:Hide()
	end
	plate.interrupt:Hide()
	plate.questIcon:Hide()
end

local TEST_EFFECTS = {
	function(plate) -- threat border, pulsing like Vivid
		local gate = Gate(plate, "threatGate", plate.health.bg, 3)
		gate:SetLook("BORDER")
		gate:FromColor(CreateColor(E:GetThreatStatusColor(3)))
		gate:Pulse(true, 1)
	end,
	function(plate) -- important cast glow
		local gate = Gate(plate, "importantGate", plate.castbar, 2)
		gate:Glow("castImportant", true)
		gate:SetOpen(true)
	end,
	function(plate) -- "Interrupted by <you>"
		local okGUID, guid = pcall(UnitGUID, "player")
		plate.castbar:Hide()
		plate.interrupt:SetStatusBarColor(RGB(db.castbar.interruptedColor))
		InterruptText(plate.interrupt.text, okGUID and Plain(guid) or nil)
		plate.interrupt:Show()
	end,
	function(plate) -- execute shade at the player's own percent
		local fx = FX("execute")
		local lower = fx and fx.lower or 20
		local style = fx and ({ LINE = "LINE", ZONE = "ZONE" })[fx.style] or "ZONE"
		local gate = Gate(plate, "executeGate", plate.health, 1)
		plate.health:SetMinMaxValues(0, 100)
		plate.health:SetValue(lower / 2)
		gate:SetLook(style, { percent = lower })
		gate:FromColor(CreateColor(E:GetStatusColor("execute")))
	end,
	function(plate) -- absorb shield over a third of the bar
		plate.absorb = plate.absorb or E:AttachAbsorb(plate.health)
		if not plate.absorb then return end
		plate.health:SetMinMaxValues(0, 100)
		plate.health:SetValue(60)
		plate.absorb.bar:SetMinMaxValues(0, 100)
		plate.absorb.bar:SetValue(30)
		plate.absorb.bar:Show()
	end,
	function(plate) -- quest icon pop
		plate.questIcon:SetAlpha(1)
		plate.questIcon:Show()
		E:PopIn(plate.questIcon)
	end,
	function(plate) -- cast bar fade in with the spark
		plate.castbar:Show()
		plate.castSpark:Show()
		E:FadeIn(plate.castbar, 0.3)
	end,
}
M.TEST_EFFECTS = TEST_EFFECTS

function M:PlayTestEffects()
	if not self.active then return end
	self:ToggleTestPlate(true)
	if not preview then return end
	local token = {}
	testToken = token
	local function Step(index)
		if testToken ~= token or not preview.holder:IsShown() then return end
		ClearTestEffects(preview)
		if index > #TEST_EFFECTS then
			testToken = nil
			LayoutPreview()
			return
		end
		LayoutPreview()
		local ok, err = pcall(TEST_EFFECTS[index], preview)
		if not ok then geterrorhandler()(err) end
		C_Timer.After(TEST_STEP, function() Step(index + 1) end)
	end
	Step(1)
end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
-- Cast events also feed the "Is casting" style filter trigger.
local rulesUseCasting = false
local SetPlateCVar -- defined with the CVars below
local RegisterEvents, StopEventWork

do -- (blocks keep the file under Lua's limit of 200 locals per chunk)
local function Refilter(plate)
	if plate.kind ~= "EXTRAS" then ApplyFilters(plate) end
end

local function CastEvent(fn)
	return function(plate, ...)
		fn(plate, ...)
		if rulesUseCasting then Refilter(plate) end
	end
end

local UNIT_EVENTS = {
	-- UNIT_HEALTH, UNIT_MAXHEALTH, UNIT_ABSORB_AMOUNT_CHANGED and
	-- UNIT_HEAL_PREDICTION: below.
	UNIT_POWER_FREQUENT = UpdatePower,
	UNIT_MAXPOWER = UpdatePower,
	UNIT_NAME_UPDATE = function(plate) UpdateName(plate); UpdateTitle(plate) end,
	UNIT_LEVEL = function(plate) UpdateColor(plate); Refilter(plate) end,
	UNIT_CLASSIFICATION_CHANGED = function(plate) UpdateColor(plate); UpdateIcons(plate); Refilter(plate) end,
	UNIT_FACTION = ReAdd,
	-- Combat flag: colors, icons, filters and "Fade units out of combat".
	UNIT_FLAGS = function(plate) UpdateColor(plate); UpdateIcons(plate); Refilter(plate) end,
	UNIT_DISPLAYPOWER = function(plate) UpdateColor(plate); UpdatePower(plate) end,
	UNIT_THREAT_LIST_UPDATE = OnThreat,
	UNIT_AURA = OnAura,
	UNIT_SPELLCAST_START = CastEvent(function(plate) CastChanged(plate, false, true) end),
	UNIT_SPELLCAST_DELAYED = function(plate) StartCast(plate, false) end,
	UNIT_SPELLCAST_CHANNEL_START = CastEvent(function(plate) CastChanged(plate, true, true) end),
	UNIT_SPELLCAST_CHANNEL_UPDATE = function(plate) StartCast(plate, true) end,
	UNIT_SPELLCAST_INTERRUPTIBLE = function(plate) RefreshCast(plate) end,
	UNIT_SPELLCAST_NOT_INTERRUPTIBLE = function(plate) RefreshCast(plate) end,
	UNIT_SPELLCAST_STOP = CastEvent(function(plate) CastChanged(plate) end),
	UNIT_SPELLCAST_CHANNEL_STOP = CastEvent(function(plate) CastChanged(plate) end),
	UNIT_SPELLCAST_FAILED = CastEvent(function(plate) CastChanged(plate) end),
	-- Payload: castGUID, spellID, interruptedBy (the interrupter's GUID).
	UNIT_SPELLCAST_INTERRUPTED = CastEvent(ShowInterrupted),
}

-- Health, max health, absorb and heal prediction often arrive together:
-- each marks the plate, and one pass on the next frame updates it once.
do
	local dirty = {} -- plate -> "health" or "absorb"
	local flusher = CreateFrame("Frame")
	flusher:Hide()
	flusher:SetScript("OnUpdate", function(self)
		self:Hide()
		for plate, what in pairs(dirty) do
			dirty[plate] = nil
			if plate.unit and plates[plate.unit] == plate then
				if what == "health" then OnHealth(plate) else UpdateAbsorb(plate) end
			end
		end
	end)
	local function Health(plate)
		dirty[plate] = "health"
		flusher:Show()
	end
	local function Absorb(plate)
		if not dirty[plate] then dirty[plate] = "absorb" end
		flusher:Show()
	end
	UNIT_EVENTS.UNIT_HEALTH, UNIT_EVENTS.UNIT_MAXHEALTH = Health, Health
	UNIT_EVENTS.UNIT_ABSORB_AMOUNT_CHANGED, UNIT_EVENTS.UNIT_HEAL_PREDICTION = Absorb, Absorb
end

-- Unit events reach a plate through its own event frame, registered for
-- that plate's unit only: the game filters the units, so a raid's health
-- and aura changes never wake the plates of other units. Some events only
-- feed one part of the plate; a plate listens to them only while it shows
-- that part (EVENT_PARTS, PlateParts).
do
local unitEventList -- the unit events this client has, found once

-- The parts as bits, and event -> the part that needs it
local PART = { power = 1, aura = 2, cast = 4, absorb = 8, threat = 16 }
local EVENT_PARTS = {
	UNIT_POWER_FREQUENT = PART.power, UNIT_MAXPOWER = PART.power,
	UNIT_AURA = PART.aura,
	UNIT_ABSORB_AMOUNT_CHANGED = PART.absorb, UNIT_HEAL_PREDICTION = PART.absorb,
	UNIT_THREAT_LIST_UPDATE = PART.threat,
}
for event in pairs(UNIT_EVENTS) do
	if event:find("^UNIT_SPELLCAST_") then EVENT_PARTS[event] = PART.cast end
end

-- The parts the plate shows now, as bits: the power bar, the fallback
-- aura icons (the aura rows follow their unit themselves), the cast bar
-- (or a style rule that reads casting), the absorb shield and the threat
-- color (enemy plates only).
local function PlateParts(plate)
	local t, full = T(plate), plate.kind == "FULL"
	local bars = full and not plate.totemOnly
	local absorb = FX("absorb")
	local parts = 0
	if bars and t.power then parts = parts + PART.power end
	if not plate.containers then parts = parts + PART.aura end
	if (full and t.castbar.enabled) or rulesUseCasting then parts = parts + PART.cast end
	if bars and absorb and absorb.enabled then parts = parts + PART.absorb end
	if not plate.friendly then parts = parts + PART.threat end
	return parts
end

local function OnPlateEvent(frame, event, unit, ...)
	local plate = frame.plate
	if plates[unit] ~= plate then return end -- the plate went away or shows another unit now
	local handler = UNIT_EVENTS[event]
	if handler then handler(plate, ...) end
end

local function UnitEventList(frame)
	if unitEventList then return unitEventList end
	unitEventList = {}
	for event in pairs(UNIT_EVENTS) do
		-- pcall: an event this client doesn't have must not stop the rest.
		if pcall(frame.RegisterUnitEvent, frame, event, "player") then unitEventList[#unitEventList + 1] = event end
	end
	frame:UnregisterAllEvents()
	table.sort(unitEventList)
	return unitEventList
end

function WatchPlateUnit(plate, unit)
	local frame = plate.events
	if not frame then
		frame = CreateFrame("Frame")
		frame.plate = plate
		frame:SetScript("OnEvent", OnPlateEvent)
		plate.events = frame
	end
	-- A plate taken off its unit keeps its registration: the game hands the
	-- same frame the same unit token again, so most plates register once.
	-- A part turned on or off registers or drops only its own events.
	local parts = PlateParts(plate)
	if plate.eventUnit == unit and plate.eventParts == parts then return end
	local fresh = plate.eventUnit ~= unit
	local before = plate.eventParts or 0
	for _, event in ipairs(UnitEventList(frame)) do
		local part = EVENT_PARTS[event]
		local wanted = not part or (parts % (part + part) >= part)
		local had = not part or (before % (part + part) >= part)
		if wanted and (fresh or not had) then
			frame:RegisterUnitEvent(event, unit)
		elseif not wanted and (fresh or had) then
			frame:UnregisterEvent(event)
		end
	end
	plate.eventUnit, plate.eventParts = unit, parts
end

function UnwatchPlateUnit(plate)
	if plate.events and plate.eventUnit then plate.events:UnregisterAllEvents() end
	plate.eventUnit, plate.eventParts = nil, nil
end
end

-- Quest progress (see KeptQuestProgress): a run of quest events becomes
-- one pass half a second after the last of them, and at most two seconds
-- after the first, so a long run still updates. Combat flags, the roster
-- and the zone show the kept text and read nothing.
local QuestChanged

do
local QUEST_TICK = "Nameplates:quest"
local QUEST_WAIT, QUEST_MOST = 0.5, 2

local function QuestPass()
	questState.first, questState.due = nil, nil
	E.Ticker:Unsubscribe(QUEST_TICK)
	questState.epoch = questState.epoch + 1
	if not db then return end
	for _, plate in pairs(plates) do
		UpdateColor(plate)
		UpdateIcons(plate)
		UpdateThreatFX(plate)
	end
	ApplyAllFilters()
end

local function QuestTick()
	local due = questState.due
	if due and GetTime() >= due then QuestPass() end
end

function QuestChanged()
	local now = GetTime()
	questState.first = questState.first or now
	questState.due = math.min(now + QUEST_WAIT, questState.first + QUEST_MOST)
	if not E.Ticker:IsSubscribed(QUEST_TICK) then E.Ticker:Subscribe(QUEST_TICK, 0.1, QuestTick, M) end
end
end

local recolorPending = false
local function RecolorAll()
	if recolorPending then return end
	recolorPending = true
	C_Timer.After(0.2, function()
		recolorPending = false
		if not db then return end
		for _, plate in pairs(plates) do
			UpdateColor(plate)
			UpdateIcons(plate)
			UpdateThreatFX(plate)
		end
		ApplyAllFilters()
	end)
end

-- Your threat changed (the event names you, not the mob): every plate's
-- threat color and border, coalesced like RecolorAll.
local threatPending = false
local function ThreatAll()
	if threatPending then return end
	threatPending = true
	C_Timer.After(0.1, function()
		threatPending = false
		if not db then return end
		for _, plate in pairs(plates) do OnThreat(plate) end
	end)
end

-- Size in combat (type tabs): our own frames, so this works in combat.
local function CombatSize(inCombat)
	fighting = inCombat and true or false
	for _, plate in pairs(plates) do
		local t = db.types[plate.typeKey]
		if t and ((tonumber(t.combatWidth) or 0) > 0 or (tonumber(t.combatHeight) or 0) > 0) then
			LayoutPlate(plate)
			UpdateAuras(plate)
		end
	end
end

-- "Enemy plates only in combat" (Hide switch): the CVar flips right when
-- combat starts (before lockdown) and after it ends.
local function CombatOnlyEnemies(inCombat)
	if not (db.cvars.enemiesInCombatOnly and Allowed("hide")) then return end
	SetPlateCVar("nameplateShowEnemies", inCombat and "1" or "0")
end

local GLOBAL_EVENTS = {
	NAME_PLATE_UNIT_ADDED = function(unit) OnPlateAdded(unit) end,
	NAME_PLATE_UNIT_REMOVED = function(unit) OnPlateRemoved(unit) end,
	PLAYER_TARGET_CHANGED = UpdateAllTargets,
	PLAYER_FOCUS_CHANGED = UpdateAllTargets,
	UPDATE_MOUSEOVER_UNIT = OnMouseoverChanged,
	PLAYER_SOFT_INTERACT_CHANGED = function() Soft.Update() end,
	PLAYER_SOFT_FRIEND_CHANGED = function() Soft.Update() end,
	PLAYER_SOFT_ENEMY_CHANGED = function()
		Soft.Update()
		if db.softTargetHighlight then UpdateAllTargets() end
	end,
	RAID_TARGET_UPDATE = function()
		for _, plate in pairs(plates) do UpdateRaidMarker(plate) end
		ApplyAllFilters()
	end,
	QUEST_LOG_UPDATE = QuestChanged,
	QUEST_ACCEPTED = QuestChanged,
	QUEST_REMOVED = QuestChanged,
	QUEST_TURNED_IN = QuestChanged,
	-- Registered for your own quest log only (DRIVER_UNITS below).
	UNIT_QUEST_LOG_CHANGED = QuestChanged,
	NAME_PLATE_UNIT_BEHIND_CAMERA_CHANGED = function(unit)
		local plate = plates[unit]
		if plate then Refilter(plate) end
	end,
	PLAYER_ROLES_ASSIGNED = function() RebuildTanks(); RecolorAll() end,
	GROUP_ROSTER_UPDATE = function() RebuildTanks(); RecolorAll() end,
	PLAYER_SPECIALIZATION_CHANGED = RecolorAll,
	-- Registered for you only (DRIVER_UNITS below).
	UNIT_THREAT_SITUATION_UPDATE = ThreatAll,
	-- Situations (Game settings): Blizzard's plate settings for this place.
	ZONE_CHANGED_NEW_AREA = function() RecolorAll(); if db.situations.enabled then M:ApplyCVars() end end,
	PLAYER_ENTERING_WORLD = function() if db.situations.enabled then M:ApplyCVars() end end,
	PLAYER_REGEN_DISABLED = function() CombatOnlyEnemies(true); CombatSize(true); ApplyAllFilters() end,
	PLAYER_REGEN_ENABLED = function() CombatOnlyEnemies(false); CombatSize(false); RecolorAll() end,
}

driver:SetScript("OnEvent", function(_, event, unit, ...)
	local global = GLOBAL_EVENTS[event]
	if global then return global(unit, ...) end
end)

function RegisterEvents()
	-- Events of the module's driver that only matter for one unit. Your own
	-- threat situation recolors every plate; another group member's does not
	-- (a mob that another tank takes sends its plate UNIT_THREAT_LIST_UPDATE).
	local DRIVER_UNITS = { UNIT_QUEST_LOG_CHANGED = "player", UNIT_THREAT_SITUATION_UPDATE = "player" }
	-- pcall: an event this client doesn't have must not stop the rest.
	for event in pairs(GLOBAL_EVENTS) do
		local unit = DRIVER_UNITS[event]
		if unit then
			pcall(driver.RegisterUnitEvent, driver, event, unit)
		else
			pcall(driver.RegisterEvent, driver, event)
		end
	end
end

-- Everything the events above keep running stops (the module goes off or
-- its plates are set up anew).
function StopEventWork()
	-- A quest pass still waiting: the kept texts are read again later.
	if questState.due then questState.epoch = questState.epoch + 1 end
	questState.first, questState.due = nil, nil
	E.Ticker:UnsubscribeOwner(M)
	wipe(runningCasts)
	hoverPlate, Soft.enemyPlate = nil, nil
end
end

---------------------------------------------------------------------------
-- CVars. Every one goes through E:SetCVar(name, value, "nameplates"),
-- which remembers the player's own value first; "Game setting" (KEEP)
-- puts that value back. Each group needs its own Blizzard UI switch:
--   hide  which plates show       move  stacking, plate size, click area
-- CVars this client doesn't have are skipped, and their rows hide.
--
-- Forever keeps these plate settings secure (lookup.py marks them
-- [secure]): an addon can't change them, so EldoUI never sets them, and
-- the Game settings tab points to Blizzard's Options instead:
-- nameplateMaxDistance, nameplateSize, nameplateOccludedAlphaMult,
-- nameplateShowOffscreen, nameplateShowEnemyMinus, nameplateShowEnemyTotems.
-- For plate distance the tab builds the player's own /console command to
-- copy (Modules/Nameplates/Size.lua).
-- The real plate size comes from C_NamePlate.SetNamePlateSize
-- (Modules/Nameplates/Size.lua).
---------------------------------------------------------------------------
do
local SECURE_CVARS = { "nameplateMaxDistance", "nameplateSize", "nameplateOccludedAlphaMult",
	"nameplateShowOffscreen", "nameplateShowEnemyMinus", "nameplateShowEnemyTotems" }
M.SECURE_CVARS = SECURE_CVARS

local function CVarExists(name)
	if not (C_CVar and C_CVar.GetCVar) then return false end
	local ok, value = pcall(C_CVar.GetCVar, name)
	return ok and type(value) ~= "nil"
end

function SetPlateCVar(name, value)
	if not CVarExists(name) then return false end
	local ok = pcall(E.SetCVar, E, name, value, ELEMENT)
	return ok
end

-- One bit of a bitfield CVar (nameplateStackingTypes). The whole value is
-- remembered first, so restoring puts every bit back.
local function SetPlateCVarBit(name, index, on)
	if not CVarExists(name) or not C_CVar.SetCVarBitfield then return false end
	pcall(E.SetCVar, E, name, C_CVar.GetCVar(name), ELEMENT)
	return pcall(C_CVar.SetCVarBitfield, name, index, on and true or false)
end

-- Put one CVar back to the player's own value, if EldoUI changed it for
-- this element.
local function RestorePlateCVar(name)
	local snapshot = EldoUIDB and EldoUIDB.cvarSnapshot
	local saved = snapshot and snapshot[name]
	if not saved or saved.owner ~= ELEMENT then return end
	if type(saved.value) ~= "nil" and C_CVar and C_CVar.SetCVar then pcall(C_CVar.SetCVar, name, saved.value) end
	snapshot[name] = nil
end

-- Only plate settings an addon may change (checked with lookup.py -k cvar).
local VISIBILITY_CVARS = {
	{ key = "showEnemies", cvar = "nameplateShowEnemies", label = "Enemy plates",
		desc = "Blizzard's \"Enemy units\" nameplate setting." },
	{ key = "showEnemyMinions", cvar = "nameplateShowEnemyMinions", label = "Enemy minions",
		desc = "Plates for enemy pets, guardians and summons." },
	{ key = "showFriendlyPlayers", cvar = "nameplateShowFriendlyPlayers", label = "Friendly player plates",
		desc = "Blizzard's \"Friendly players\" nameplate setting." },
	{ key = "showFriendlyMinions", cvar = "nameplateShowFriendlyPlayerMinions", label = "Friendly minions",
		desc = "Plates for friendly players' pets and guardians." },
	{ key = "showFriendlyNpcs", cvar = "nameplateShowFriendlyNpcs", label = "Friendly NPC plates",
		desc = "Plates for friendly NPCs such as guards and vendors." },
	{ key = "showAll", cvar = "nameplateShowAll", label = "Always show plates",
		desc = "On: plates show all the time. Off: only in combat or while the plate key is held." },
	{ key = "friendlyNameOnly", cvar = "nameplateShowOnlyNameForFriendlyPlayerUnits", label = "Friendly players: name only (Blizzard)",
		desc = "Blizzard's own name-only plates for friendly players. Also works inside instances, where friendly plates always stay Blizzard's." },
}
M.VISIBILITY_CVARS = VISIBILITY_CVARS

local function TriState(value, name)
	if value == "ON" then
		SetPlateCVar(name, "1")
	elseif value == "OFF" then
		SetPlateCVar(name, "0")
	else
		RestorePlateCVar(name)
	end
end

local STACKING_CVAR = "nameplateStackingTypes"

-- Stacking needs the stacking bitfield CVar (newer clients); without it
-- the rows hide and nothing is set (no older fallback CVar).
local function HasStacking()
	return CVarExists(STACKING_CVAR) and C_CVar.SetCVarBitfield and true or false
end
M.HasStacking = HasStacking

local function ApplyStacking(enemy, friendly)
	if not CVarExists(STACKING_CVAR) then return end
	-- Start from the player's own value every time, so a side set back to
	-- "Game setting" gets its own bit back while the other side keeps
	-- EldoUI's.
	RestorePlateCVar(STACKING_CVAR)
	if enemy == "KEEP" and friendly == "KEEP" then return end
	local types = Enum.NamePlateStackType or {}
	if enemy ~= "KEEP" then SetPlateCVarBit(STACKING_CVAR, types.Enemy or 1, enemy == "STACK") end
	if friendly ~= "KEEP" then SetPlateCVarBit(STACKING_CVAR, types.Friendly or 2, friendly == "STACK") end
end

-- Read-only view of the plates and the pool.
M.internal = { plates = plates, pool = pool, hooked = hooked, fadeBlizzard = FadeBlizzard, restoreBlizzard = RestoreBlizzard }

function M:ApplyCVars()
	-- Master switch off: Core/Blizzard.lua already put every value back.
	if not self.active or not Allowed() then return end
	E:RunOutOfCombat(function()
		if not (self.active and Allowed()) then return end
		local cvars = self.db.cvars
		local hide, move = Allowed("hide"), Allowed("move")
		-- Situations (Size.lua): this place's values win over the rows above.
		local place = self.SituationValues and self:SituationValues() or nil
		for _, entry in ipairs(VISIBILITY_CVARS) do
			local value = hide and cvars[entry.key] or "KEEP"
			if hide and place then
				if entry.key == "showEnemies" and place.enemies ~= "KEEP" then value = place.enemies end
				if entry.key == "showFriendlyPlayers" and place.friends ~= "KEEP" then value = place.friends end
			end
			if entry.key == "showEnemies" and hide and cvars.enemiesInCombatOnly then
				value = InCombatLockdown() and "ON" or "OFF"
			end
			TriState(value, entry.cvar)
		end
		if move then
			local enemy = cvars.stacking
			if place and place.stacking ~= "KEEP" then enemy = place.stacking end
			ApplyStacking(enemy, cvars.friendlyStacking)
		else
			ApplyStacking("KEEP", "KEEP")
		end
		if self.ApplyClickArea then self:ApplyClickArea() end
		if self.ApplyPlateSize then self:ApplyPlateSize() end
	end)
end
end

---------------------------------------------------------------------------
-- Settings migration: v0.6 and older had one layout for every plate. Any
-- of those keys still in the saved settings (or written by an import)
-- moves into every type it applied to, then goes away.
---------------------------------------------------------------------------
local HEALTH_PRESETS = { PERCENT = "healthpercent", CURRENT = "healthcurrent", BOTH = "healthcurrentpercent", NONE = "off" }

local function EachType(fn, which)
	for _, key in ipairs(TYPES) do
		if not which or which(key) then fn(db.types[key], key) end
	end
end
local function Friendly(key) return key == "friendlyNPC" or key == "friendlyPlayer" end

local function MigrateLegacy()
	local legacy = db
	for _, field in ipairs({ "width", "height", "nameText" }) do
		if legacy[field] ~= nil then
			local value = legacy[field]
			EachType(function(t) t[field] = value end)
			legacy[field] = nil
		end
	end
	if legacy.healthText ~= nil then
		local preset = HEALTH_PRESETS[legacy.healthText]
		if preset then EachType(function(t) t.healthTag.preset = preset end) end
		legacy.healthText = nil
	end
	if legacy.levelText ~= nil then
		local preset = legacy.levelText and "platelevel" or "off"
		EachType(function(t) t.levelTag.preset = preset end)
		legacy.levelText = nil
	end
	if legacy.styleFriendly ~= nil then
		local on = legacy.styleFriendly and true or false
		EachType(function(t) t.enabled = on end, Friendly)
		legacy.styleFriendly = nil
	end
	if legacy.friendlyNameOnly ~= nil then
		local on = legacy.friendlyNameOnly and true or false
		EachType(function(t) t.nameOnly = on end, Friendly)
		legacy.friendlyNameOnly = nil
	end
	local cast = legacy.castbar
	if cast.enabled ~= nil then
		local on = cast.enabled and true or false
		EachType(function(t) t.castbar.enabled = on end)
		cast.enabled = nil
	end
	if cast.height ~= nil then
		local value = cast.height
		EachType(function(t) t.castbar.height = value end)
		cast.height = nil
	end
	if cast.fontSize ~= nil then
		local value = cast.fontSize
		EachType(function(t) t.castbar.nameSize, t.castbar.timeSize = value, value end)
		cast.fontSize = nil
	end
	if cast.icon ~= nil then
		local side = cast.icon and "LEFT" or "NONE"
		EachType(function(t) t.castbar.icon = side end)
		cast.icon = nil
	end
	if cast.timer ~= nil then
		local mode = cast.timer and "REMAINING" or "NONE"
		EachType(function(t) t.castbar.time = mode end)
		cast.timer = nil
	end
	for _, field in ipairs({ "enabled", "size", "max" }) do
		if legacy.debuffs[field] ~= nil then
			local value = legacy.debuffs[field]
			EachType(function(t) t.debuffs[field] = value end)
			legacy.debuffs[field] = nil
		end
		if field ~= "enabled" and legacy.buffs[field] ~= nil then
			local value = legacy.buffs[field]
			EachType(function(t) t.buffs[field] = value end, function(key) return not Friendly(key) end)
			legacy.buffs[field] = nil
		end
	end
end

-- Settings migration (runs on every refresh, so imports are covered too):
--   * the plate CVars Forever keeps secure leave the settings and the CVar
--     memory; EldoUI never sets them again, not even to restore them;
--   * the old cast bar "important" switch and color become the shared
--     important cast glow;
--   * effect keys from the plan's first draft move to the engine's keys;
--   * own threat colors that differ from the old defaults stay in use.
do
local OLD_THREAT = { good = { 0.20, 0.80, 0.20 }, transition = { 1.00, 0.60, 0.00 }, bad = { 1.00, 0.10, 0.10 } }
local REMOVED_CVARS = { "maxDistance", "size", "occludedAlpha", "showEnemyMinus", "showEnemyTotems", "showOffscreen" }
-- Plan key in effects -> engine key; plan key in castbar -> engine key.
local EFFECT_RENAMES = { threatBorder = "threat" }
local CAST_RENAMES = { fade = "castFade", spark = "castSpark", interrupter = "interrupter" }

local function SameColor(a, b)
	if type(a) ~= "table" then return true end
	for i = 1, 3 do
		if math.abs((tonumber(a[i]) or 0) - b[i]) > 0.001 then return false end
	end
	return true
end

-- A plain true/false (the plan's draft) becomes { enabled = ... }.
local function AsEffect(value)
	if type(value) == "boolean" then return { enabled = value } end
	if type(value) == "table" then return value end
end

function M:Migrate()
	local data = self.db
	if type(data) ~= "table" then return end
	local cvars = data.cvars
	if type(cvars) == "table" then
		for _, key in ipairs(REMOVED_CVARS) do cvars[key] = nil end
	end
	local snapshot = EldoUIDB and EldoUIDB.cvarSnapshot
	if type(snapshot) == "table" then
		for _, name in ipairs(M.SECURE_CVARS) do
			local saved = snapshot[name]
			if type(saved) == "table" and saved.owner == ELEMENT then snapshot[name] = nil end
		end
	end

	local effects = data.effects
	if type(effects) ~= "table" then
		effects = E:UnitFXDefaults(FX_CONSUMER, "subtle")
		data.effects = effects
	end
	if effects.preset == "Subtle" or type(effects.preset) == "string" and E.UNITFX_PRESET_TITLES[effects.preset:lower()] then
		effects.preset = effects.preset:lower()
	end
	for old, new in pairs(EFFECT_RENAMES) do
		if type(effects[old]) ~= "nil" then
			local value = AsEffect(effects[old])
			if value then effects[new] = value end
			effects[old] = nil
		end
	end
	for _, key in ipairs(FX_EFFECTS) do
		if type(effects[key]) == "boolean" then effects[key] = { enabled = effects[key] } end
	end

	local cast = data.castbar
	if type(cast) == "table" then
		for old, new in pairs(CAST_RENAMES) do
			if type(cast[old]) ~= "nil" then
				local value = AsEffect(cast[old])
				if value then effects[new] = value end
				cast[old] = nil
			end
		end
		if type(cast.importantSound) ~= "nil" then
			local value = cast.importantSound
			if type(value) == "boolean" then value = { enabled = value } end
			if type(value) == "table" then
				effects.importantSound = effects.importantSound or {}
				effects.importantSound.enabled = value.enabled and true or false
				if type(value.sound) == "string" then effects.importantSound.sound = value.sound end
			end
			cast.importantSound = nil
		end
		if type(cast.important) ~= "nil" then
			if cast.important == false then
				effects.importantGlow = AsEffect(effects.importantGlow) or {}
				effects.importantGlow.enabled = false
			end
			cast.important = nil
		end
		cast.importantColor = nil
	end

	local threat = data.threat
	-- Once per profile: own colors from before this switch existed.
	if type(threat) == "table" and (tonumber(data.schema) or 0) < 1 then
		local own = false
		for key, old in pairs(OLD_THREAT) do
			if not SameColor(threat[key], old) then own = true end
		end
		threat.custom = own or threat.custom == true
	end
	-- The old per-type "Copy settings from" picker: the copy is a row with
	-- a preview now, so nothing is left to apply.
	for _, key in ipairs(TYPES) do
		local t = type(data.types) == "table" and data.types[key]
		if type(t) == "table" then t.copyFrom = nil end
	end
	data.schema = 1
end
end

function M:ResetType(key)
	db = self.db
	local enabled = type(db.types[key]) == "table" and db.types[key].enabled
	db.types[key] = CopyTable(TYPE_DEFAULTS[key])
	if enabled ~= nil then db.types[key].enabled = enabled end
	if self.OnProfileChanged then E:RunOutOfCombat(function() self:OnProfileChanged() end) end
	if E.RefreshConfig then E:RefreshConfig() end
end

local function NormalizeRules()
	for _, rule in ipairs(Rules()) do NormalizeRule(rule) end
	-- A rule list longer than the editor allows is cut at the end.
	local rules = Rules()
	for index = #rules, MAX_RULES + 1, -1 do rules[index] = nil end
	wipe(nameSets)
	rulesUseCasting = AnyRuleUses("casting")
end

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------
local function ApplySettings()
	auraGen = auraGen + 1
	CAST_NORMAL:SetRGB(RGB(db.castbar.color))
	CAST_LOCKED:SetRGB(RGB(db.castbar.uninterruptibleColor))
	STEAL_COLOR:SetRGB(RGB(db.buffs.stealableColor))
	CAST_CHANNEL:SetRGB(RGB(db.castbar.channelColor))
end

-- Style every plate that is on screen right now (login, /reload, switch on).
local function ScanPlates()
	if not (C_NamePlate and C_NamePlate.GetNamePlates) then return end
	local ok, list = pcall(C_NamePlate.GetNamePlates)
	for _, nameplate in ipairs(ok and list or {}) do
		local unit = nameplate.namePlateUnitToken or (nameplate.GetUnit and nameplate:GetUnit())
		if unit and not plates[unit] then OnPlateAdded(unit) end
	end
end

-- Drop every plate we drew and give Blizzard's art its alpha back.
-- `keepEvents`: the plates are set up again right away (a settings
-- change), so each keeps its unit's event registration.
local function ReleaseAll(keepEvents)
	local units = {}
	for unit in pairs(plates) do table.insert(units, unit) end
	for _, unit in ipairs(units) do OnPlateRemoved(unit) end
	for _, plate in pairs(pool) do
		plate.root:Hide()
		if not keepEvents then UnwatchPlateUnit(plate) end
	end
	for unitFrame in pairs(hiddenBlizzard) do RestoreBlizzard(unitFrame) end
	HideSkinBorders()
	StopEventWork()
end

-- Re-read settings and switches and redraw. Called on enable, every
-- settings change and every Blizzard UI switch change.
local function Refresh()
	db = M.db
	MigrateLegacy()
	M:Migrate()
	E:NormalizeUnitFX(db.effects, FX_CONSUMER)
	NormalizeRules()
	wipe(detailTypes)
	M:CheckQuietPlates()
	if not M.active then return end
	fighting = InCombatLockdown() and true or false
	RebuildTanks()
	ApplySettings()
	ReleaseAll(PlateMode() ~= "OFF")
	driver:UnregisterAllEvents()
	if PlateMode() ~= "OFF" then
		RegisterEvents()
		ScanPlates()
	end
	M:ApplyCVars()
	if not Allowed("move") then E:RunOutOfCombat(function() M:ApplyClickArea() end) end
	if preview and preview.holder:IsShown() then LayoutPreview() end
	-- Pieces on plates (combo points, combat text) follow the new plates.
	FirePlateCallback("MODE", nil, nil, PlateMode())
end

-- A saved profile whose own hostile, neutral or friendly color differs
-- from the old default keeps its colors. Runs once per saved profile, and a
-- new or reset profile is stamped before the player picks anything, so a
-- fresh choice of General colors stays. A profile the old login check
-- already looked at carries reactionChecked.
function M.MigrateReactionColors(profile)
	local modules = type(profile) == "table" and type(profile.modules) == "table" and profile.modules
	local own = modules and type(modules.Nameplates) == "table" and modules.Nameplates
	local colors = own and type(own.colors) == "table" and own.colors
	if not colors or colors.reactionChecked or colors.reactionSource ~= nil then return end
	for _, key in ipairs({ "hostile", "neutral", "friendly" }) do
		local mine, default = colors[key], M.defaults.colors[key]
		if type(mine) == "table" and type(default) == "table" then
			for i = 1, 3 do
				if math.abs((tonumber(mine[i]) or 0) - default[i]) > 0.005 then colors.reactionSource = "own" end
			end
		end
	end
end
E:RegisterProfileMigration(M.MigrateReactionColors, "Nameplates:reactionColors", 1)

function M:OnInitialize()
	db = self.db
	-- v0.5.0 stored the "color quest mobs" switch and the quest color under
	-- the same key, so the switch could replace the color with true/false.
	local colors = db.colors
	if type(colors.quest) ~= "table" then
		if colors.quest == false then colors.byQuest = false end
		colors.quest = CopyTable(self.defaults.colors.quest)
	end
	-- v0.5.0 had one "Friendly plates" setting for the old nameplateShowFriends CVar.
	local cvars = db.cvars
	if cvars.showFriends ~= nil then
		if cvars.showFriends == "SHOW" then cvars.showFriendlyPlayers = "ON" end
		if cvars.showFriends == "HIDE" then cvars.showFriendlyPlayers = "OFF" end
		cvars.showFriends = nil
	end
	MigrateLegacy()
	self:Migrate()
	E:NormalizeUnitFX(db.effects, FX_CONSUMER)
	E:OnBlizzardAddOn("Blizzard_NamePlates", HookBlizzardMixin)
	E:RegisterGlowUser("nameplateFilter", {
		title = "Nameplate style filters",
		desc = "The glow a nameplate style filter rule puts on matching plates.",
		order = 40,
		default = { style = "pixel", colorMode = "custom", color = { 1, 0.82, 0 } },
	})
	E:RegisterGlowUser("nameplateTarget", {
		title = "Nameplates: target",
		desc = "The pulsing glow round your target's plate when the target highlight is \"Pulse glow\".",
		order = 41,
		default = { style = "pulse", colorMode = "accent" },
	})
	-- The spell lists of the debuff filter changed: rebuild the containers.
	E:OnAuraFiltersChanged("Nameplates", function()
		filterVersion = filterVersion + 1
		auraGen = auraGen + 1
		if M.active then E:RunOutOfCombat(Refresh) end
	end)
end

function M:OnEnable()
	db = self.db
	Refresh()
end

function M:OnDisable()
	driver:UnregisterAllEvents()
	ReleaseAll()
	self:CheckQuietPlates()
	FirePlateCallback("MODE", nil, nil, "OFF")
	self:ToggleTestPlate(false)
	E:RunOutOfCombat(function() M:ApplyClickArea(); M:ApplyPlateSize() end)
	-- The module is off: nothing of ours may stay changed.
	if E.RestoreCVars and self.db then E:RestoreCVars(ELEMENT) end
end

function M:OnProfileChanged()
	db = self.db
	Refresh()
end

-- A new look (font, bar texture, art style): every plate on screen is laid
-- out and drawn again, which also puts the name font back on names, so
-- names in every alphabet keep their letters. Blizzard's skinned plates
-- take the new look too. Settings and plates stay as they are.
function M:OnThemeChanged()
	db = self.db
	if not self.active then return end
	ApplySettings()
	for _, plate in pairs(plates) do
		LayoutPlate(plate)
		UpdatePlate(plate)
	end
	if PlateMode() == "BLIZZARD" and C_NamePlate and C_NamePlate.GetNamePlates then
		local ok, list = pcall(C_NamePlate.GetNamePlates)
		for _, nameplate in ipairs(ok and list or {}) do
			local unit = nameplate.namePlateUnitToken
			if nameplate.UnitFrame and not (unit and plates[unit]) then SkinBlizzard(nameplate.UnitFrame) end
		end
	end
	if preview and preview.holder:IsShown() then LayoutPreview() end
end

-- Back to Blizzard default (master switch off). The skin is only fully
-- gone after a /reload; Core/Blizzard.lua asks for it and restores CVars.
function M:RestoreBlizzardNameplates()
	db = self.db
	driver:UnregisterAllEvents()
	ReleaseAll()
	FirePlateCallback("MODE", nil, nil, "OFF")
	E:RunOutOfCombat(function() M:ApplyClickArea(); M:ApplyPlateSize() end)
end

E:RegisterBlizzardHandler(ELEMENT, {
	owner = "Nameplates",
	apply = function() Refresh() end,
	undo = function() M:RestoreBlizzardNameplates() end,
	reload = { skin = true },
	install = { replace = true, skin = true, move = true, hide = true, improve = true },
	legacy = function() return M.db and M.db.enabled end,
})

-- Helpers the split files (Modules/Nameplates/*.lua) share with this one,
-- read through the module table: they load right after it. PlateDB reads
-- the profile the plates use; UsePlateDB takes up the module's current one.
M.inner = {
	FX_CONSUMER = FX_CONSUMER, ELEMENT = ELEMENT, MAX_RULES = MAX_RULES,
	TYPES = TYPES, TYPE_TITLES = TYPE_TITLES, TypeDefaults = TypeDefaults,
	RULE_DEFAULTS = RULE_DEFAULTS, NormalizeRule = NormalizeRule, Rules = Rules,
	FilterContext = FilterContext, Matches = Matches,
	pool = pool, PlateFor = PlateFor, Friendly = Friendly,
	Allowed = Allowed, IsTankMode = IsTankMode, Refresh = Refresh,
	PlateDB = function() return db end,
	UsePlateDB = function() db = M.db return db end,
}
