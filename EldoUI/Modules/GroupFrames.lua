-- EldoUI Group Frames: party, raid, main tank and group pet frames, plus
-- the switches for Blizzard's own party and raid frames.
--
-- Engines (setting "engine"):
--   "eldo"     EldoUI's own frames, built on Blizzard's secure group headers
--              (SecureGroupHeaderTemplate with SecureUnitButtonTemplate
--              children), so clicking and click-casting work in combat.
--   "skin"     Blizzard's compact party and raid frames with EldoUI's skin
--              (needs the element's Skin switch on the Blizzard UI page).
--   "blizzard" Blizzard's own frames, untouched by this module.
--   "auto"     (default) EldoUI frames, but if the header has not produced
--              any visible buttons ~2 s after joining a group, fall back to
--              Blizzard's frames (skinned if allowed) for the rest of the
--              session. Secure group headers were reported broken on some
--              Forever builds; this keeps the player from ending up without
--              group frames.
--
-- Blizzard's frames are only touched when the player allows it on the
-- Blizzard UI page (Core/Blizzard.lua): "party-frames" and "raid-frames"
-- each have a master switch plus Skin, Move, Hide, Replace and Improve.
-- With the master switch off this module never hides, skins, moves or
-- reparents Blizzard's frames; EldoUI's own frames follow this module's
-- settings as before.
--
-- WoW: Forever follows the Midnight rules: health, auras, threat and range
-- can be "secret" in combat. Values go straight into widget setters (bars,
-- string.format into SetText, SetAlphaFromBoolean, color curves); nothing
-- here does arithmetic or comparisons on them. Auras come only from
-- Blizzard's own filters (RAID, RAID_PLAYER_DISPELLABLE, RAID_IN_COMBAT,
-- BIG_DEFENSIVE, EXTERNAL_DEFENSIVE); boss mechanics only through Blizzard's
-- private aura anchors. Nothing here decides anything for the player.
--
-- Addon code may not read auras in combat on Forever, so the debuff, buff,
-- defensive and dispel-highlight icons are drawn by the game's own aura
-- containers (Core/AuraWidget.lua): EldoUI hands the client the filter,
-- size and place once, and the client fills them in and out of combat.
-- Only test frames, and a frame whose container could not be made (out of
-- combat), use the EldoUI icons below.
--
-- Shared engines (Core): texts are tag strings (Core/Tags.lua, E:BindTag),
-- each holder fades through Core/Visibility.lua (a state driver for the
-- real hide, since the holder carries secure buttons), aura filters are
-- Core/Filters.lua blocks handed to the containers, and the dispel / boss
-- aura glows are General > Glows rows (Core/Glow.lua) drawn on aura slots
-- the client shows and hides itself.
--
-- Layout depth: each section (party, raid, mid-size raid, large raid,
-- main tanks, pets) has its own size, two-axis growth, spacing, sorting,
-- group filter, bars, texts, icon places, auras and range fade.
-- Heal prediction and absorbs come from the game's own calculator;
-- the bars only receive its results.
--
-- Effects come from Core/UnitFX.lua: threat border, low health and
-- low power warnings through gates, the health gradient curve, the dead
-- and offline look, aura pop-in and expiring, the target flash, the
-- fade-in and the status pulse (Core/FrameFX.lua). Range fades an inner
-- art frame, never the secure button. Portraits (2D, 3D or the class icon)
-- come from Core/Portrait.lua; the party frames can also take the Boxed
-- look: a portrait box, a name bar and a class or role badge.
local _, E = ...
local L = E.L

local Key = E.Key
---------------------------------------------------------------------------
-- Headers and holders
---------------------------------------------------------------------------
-- Every header sits in a holder frame that carries the mover. The main tank
-- targets share the main tank holder; the raid header switches between the
-- "raid" and "raid40" settings by group size.
local HEADERS = {
	party = { element = "party-frames", holder = "party", max = 5 },
	raid = { element = "raid-frames", holder = "raid", max = 40 },
	tanks = { element = "raid-frames", holder = "tanks", settings = "tanks", max = 8 },
	tanktargets = { element = "raid-frames", holder = "tanks", settings = "tanks", suffix = "target", max = 8 },
	pets = { element = "party-frames", holder = "pets", settings = "pets", max = 40, pet = true },
}
local HEADER_ORDER = { "party", "raid", "tanks", "tanktargets", "pets" }
local HOLDERS = {
	party = { mover = "EldoUI_Party", title = "Party", point = { "TOPLEFT", "UIParent", "TOPLEFT", 19, -420 } },
	raid = { mover = "EldoUI_Raid", title = "Raid", point = { "TOPLEFT", "UIParent", "TOPLEFT", 19, -380 } },
	tanks = { sample = { kind = "unit" }, mover = "EldoUI_Tanks", title = "Main Tanks", point = { "TOPLEFT", "UIParent", "TOPLEFT", 19, -860 } },
	pets = { sample = { kind = "unit" }, mover = "EldoUI_GroupPets", title = "Group Pets", point = { "TOPLEFT", "UIParent", "TOPLEFT", 460, -380 } },
}
local HOLDER_ORDER = { "party", "raid", "tanks", "pets" }
local MAX_ICONS = 6       -- buff and debuff icons per frame
local MAX_PRIVATE = 2     -- private aura anchors per frame

-- Settings tables that look like a frame section (size, growth, texts).
local SECTION_KEYS = { "party", "raid", "raid25", "raid40", "tanks", "pets" }
local SECTION_TITLES = {
	party = "Party", raid = "Raid", raid25 = E.Key("Mid raid"), raid40 = E.Key("Large raid"), tanks = E.Key("Main tanks"), pets = "Pets",
}
-- Raid size bands, largest first: the first enabled band the raid reaches
-- is used; "raid" covers every size below them.
local RAID_BANDS = { "raid40", "raid25" }
-- Sections with their own holder (and so their own fade rules).
local HOLDER_SECTIONS = { party = true, raid = true, tanks = true, pets = true }

-- Per-section aura blocks. The filter blocks are Core/Filters.lua blocks.
local function AuraBlocks(debuffPreset, buffPreset)
	return {
		debuffs = {
			enabled = true, max = 3, size = 18, position = "BOTTOMRIGHT", timer = false,
			filter = E:AuraFilterDefaults("HARMFUL", debuffPreset or "dispellable"),
		},
		buffs = {
			enabled = true, max = 3, size = 14, position = "BOTTOMLEFT", timer = false,
			style = "ICONS",                     -- "ICONS" or "SQUARES" (colored corner squares)
			squareColor = { 0.3, 1, 0.4 },
			missing = false,                     -- out of combat: mark members without your group buff
			missingColor = { 1, 0.25, 0.25 },
			missingPosition = "TOPRIGHT",
			filter = E:AuraFilterDefaults("HELPFUL", buffPreset or "hots"),
		},
		defensives = { enabled = true, external = true, size = 20, position = "CENTER", timer = false },
	}
end

local function TextSlot(preset)
	return { preset = preset, custom = "" }
end

local function SectionDefaults(width, height, spacing, growth, per, extra)
	local settings = {
		enabled = true, width = width, height = height, spacing = spacing, growth = growth,
		growth2 = "AUTO",          -- second direction (new column or row); AUTO = right or down
		splitSpacing = false,      -- own vertical gap
		spacingY = spacing,
		centered = false,          -- the first row or column grows from the middle
		unitsPerColumn = per, maxColumns = 8, maxGroups = 8, sortBy = "GROUP", sortDir = "ASC",
		visibilityMacro = "",      -- advanced: own macro conditional for the header
		classColor = true, classColorName = false, colorByValue = false,
		fill = "HORIZONTAL", reverseFill = false,
		powerHeight = 0, powerFilter = "ALL", -- "ALL" or "HEALERS"
		castbar = { enabled = false, height = 4, name = false }, -- cast bar at the bottom (GroupFrames/Cast.lua)
		portrait = "NONE",         -- "NONE", "CLASS", "2D" or "3D" (party)
		portraitBox = false,       -- the portrait in its own box, as tall as the frame (Boxed look)
		portraitDeadGrey = true,   -- gray while dead or offline (Effects: Dead and offline look)
		nameBar = false,           -- the name in its own bar over the health bar (Boxed look)
		badge = { enabled = false, size = 16, mode = "CLASS" }, -- class or role badge on the frame's right edge
		nameLength = 10, fontSize = 12, roleIcon = true,
		texts = { name = TextSlot("name"), health = TextSlot("healthpercent"), extra = TextSlot("off"), extraPosition = "BOTTOM" },
		icons = {
			topSize = 0, topPosition = "TOPLEFT",           -- role, leader and main tank row (0 = fits the font)
			raidSize = 0, raidPosition = "TOPRIGHT",        -- raid target marker
			statusSize = 0, statusPosition = "CENTER",      -- ready check, resurrection, summon, phase
		},
		rangeAlpha = 0.4,
		auras = true,
	}
	for key, value in pairs(AuraBlocks()) do settings[key] = value end
	for key, value in pairs(extra or {}) do settings[key] = value end
	return settings
end

-- Effects: one Effects block for every section. The threat border
-- is on from Subtle up (the old "Aggro border" default).
local GFX = {}
GFX.EFFECTS = { "fadeIn", "targetFlash", "auraPop", "auraExpiring", "statusPulse", "threat", "lowHealth", "lowPower", "deadLook" }
E:RegisterUnitFXPresets("GroupFrames", {
	subtle = { threat = { enabled = true, style = "BORDER", pulse = false } },
}, GFX.EFFECTS)

local M = E:NewModule("GroupFrames", {
	title = "Party and Raid",
	-- The words players use for these frames reach the module in /eui.
	aliases = { "Raid Frames", "Party Frames", "Grid" },
	desc = "Party, raid, main tank and pet frames with role, leader, status, aggro, buff, debuff, defensive and boss-mechanic indicators.",
	conflicts = {
		"EllesmereUIRaidFrames", "EllesmereUIPartyFrames", "EllesmereUIGroupFrames",
		"ElvUI", "Grid2", "VuhDo", "Cell", "VoidBox", "Aptechka",
	},
	frames = {
		"EldoUI_PartyHolder", "EldoUI_RaidHolder", "EldoUI_MainTanksHolder", "EldoUI_GroupPetsHolder",
		"EldoUI_PartyHeader", "EldoUI_RaidHeader", "EldoUI_TanksHeader", "EldoUI_TanktargetsHeader",
		"EldoUI_PetsHeader",
	},
	movers = { "EldoUI_Party", "EldoUI_Raid", "EldoUI_Tanks", "EldoUI_GroupPets" },
	blizzard = { "party-frames", "raid-frames" },
	savedKeys = { "profile.modules.GroupFrames" },
	optionsPage = "module:GroupFrames",
	presets = { "Blizzard", "Healer", "List", "Minimal", "Perl", "RaidLead", "Wide" },
	defaults = {
		engine = "auto",          -- "auto", "eldo", "skin" or "blizzard"
		hideBlizzard = true,      -- v0.5.0 setting, only read to keep old setups (legacy)
		skinBlizzard = true,      -- skin Blizzard's frames when Auto falls back to them
		fallbackNotice = true,    -- one chat line when auto falls back
		testSize = "party",       -- "party", "raid10", "raid20", "raid25" or "raid40"
		raidManager = "blizzard", -- Blizzard's raid manager side panel: "blizzard", "skin" or "hide"
		blizzardScale = 1,        -- scale of Blizzard's frames when EldoUI moves them
		smoothBars = "general",        -- the game animates health and power changes
		prediction = { heals = true, absorbs = true, healAbsorbs = true },
		-- Whole-frame highlights from aura slots the client fills.
		dispel = { enabled = true, mine = true, style = "BORDER" }, -- "BORDER", "GLOW" or "BOTH"
		bossGlow = false,
		privateAuras = { enabled = true, count = 1, size = 20, position = "TOP", countdown = false },
		indicators = {
			leader = true, mainTank = true, raidTarget = true, readyCheck = true, readyHold = 6,
			resurrect = true, summon = true, phase = true, afk = true,
			aggroSource = "any", target = true, mouseover = true,
		},
		effects = E:UnitFXDefaults("GroupFrames"),
		graphics = "FOLLOW",      -- frame art (Core/UnitGraphics.lua), compact on every section
		party = SectionDefaults(180, 44, 4, "DOWN", 5, {
			showPlayer = true, showSolo = false, powerHeight = 4, nameLength = 12, fontSize = 14,
			visibility = E:VisibilityDefaults(),
		}),
		raid = SectionDefaults(80, 40, 2, "RIGHT", 5, { nameLength = 7, visibility = E:VisibilityDefaults() }),
		raid25 = SectionDefaults(72, 34, 2, "RIGHT", 5, {
			enabled = false, minMembers = 11, nameLength = 6, fontSize = 11,
		}),
		raid40 = SectionDefaults(64, 30, 1, "RIGHT", 5, {
			minMembers = 26, nameLength = 5, fontSize = 11, roleIcon = false,
			texts = { name = TextSlot("name"), health = TextSlot("off"), extra = TextSlot("off"), extraPosition = "BOTTOM" },
		}),
		tanks = SectionDefaults(120, 26, 2, "DOWN", 8, {
			enabled = false, source = "ASSIGNED", assists = true, targets = true, inParty = false,
			nameLength = 10, fontSize = 11, roleIcon = false, maxColumns = 1, visibility = E:VisibilityDefaults(),
		}),
		pets = SectionDefaults(80, 22, 2, "DOWN", 5, {
			enabled = false, inParty = true, inRaid = false, nameLength = 8, fontSize = 10,
			roleIcon = false, auras = false, visibility = E:VisibilityDefaults(),
			texts = { name = TextSlot("name"), health = TextSlot("off"), extra = TextSlot("off"), extraPosition = "BOTTOM" },
		}),
	},
})

local NAME_PRESETS = { "name", "namelevel", "off" }

-- [name] on every group frame follows this override. Test frames
-- show sample surnames in it too.
E:RegisterNameFormatUser("GroupFrames", { title = "Group frames", order = 20,
	desc = "Name format of [name] on party, raid, main tank and pet frames. Name length cuts the name after this format.",
	refresh = function()
		if M.testing then E:RunOutOfCombat(function() M:LayoutTest() end) end
	end })

local HEALTH_PRESETS = { "healthpercent", "healthcurrent", "healthdeficit", "healthcurrentmax", "healthcurrentpercent", "off" }
local EXTRA_PRESETS = { "off", "status", "healthpercent", "powerpercent" }

M.holders = {}
M.headers = {}
M.fakes = {}

---------------------------------------------------------------------------
-- Settings migration (0.6 and older): shared aura blocks, one range alpha
-- and fixed health text formats became per-section settings. Old keys
-- have no default any more, so whatever is left of them is the player's.
---------------------------------------------------------------------------
local OLD_DEBUFF_FILTERS = {
	MINE = { preset = "dispellable" }, ALL = { preset = "all" },
	GROUP = { custom = { extra = "RAID_PLAYER_DISPELLABLE" } }, COMBAT = { custom = { extra = "RAID_IN_COMBAT" } },
}
local OLD_BUFF_FILTERS = {
	HOTS = { preset = "hots" }, MINE = { preset = "mine" }, ALL = { preset = "all" }, RAID = { custom = { raid = true } },
}
local OLD_HEALTH_FORMATS = { PERCENT = "healthpercent", CURRENT = "healthcurrent", DEFICIT = "healthdeficit" }

local function MigrateFilter(block, kind, old)
	local map = old and (kind == "HARMFUL" and OLD_DEBUFF_FILTERS or OLD_BUFF_FILTERS)[old]
	if not map or type(block) ~= "table" then return end
	if map.preset then
		block.preset = map.preset
		return
	end
	block.preset = "custom"
	block.groups = block.groups or {}
	local group = block.groups[1] or {}
	block.groups[1] = group
	group.enabled = true
	for key, value in pairs(map.custom) do group[key] = value end
end

function M:Migrate()
	local db = self.db
	if not db then return end
	-- The General tab's "Copy from" pick: each section tab has its own
	-- "Copy settings from" row now.
	if rawget(db, "copySource") ~= nil then db.copySource = nil end
	-- "Smooth bars" was an on/off tick before it could follow General.
	if type(db.smoothBars) == "boolean" then db.smoothBars = db.smoothBars and "general" or "off" end
	local oldDebuffs, oldBuffs, oldDefensives = db.debuffs, db.buffs, db.defensives
	for _, key in ipairs(SECTION_KEYS) do
		local section = db[key]
		if type(section) == "table" then
			if db.rangeAlpha ~= nil then section.rangeAlpha = db.rangeAlpha end
			for name, old in pairs({ debuffs = oldDebuffs, buffs = oldBuffs, defensives = oldDefensives }) do
				if type(old) == "table" and type(section[name]) == "table" then
					for field, value in pairs(old) do
						if field == "filter" then
							MigrateFilter(section[name].filter, name == "debuffs" and "HARMFUL" or "HELPFUL", value)
						elseif field ~= "highlight" and field ~= "highlightMine" then
							section[name][field] = type(value) == "table" and CopyTable(value) or value
						end
					end
				end
			end
			-- Fixed health text -> tag slot.
			if section.healthText ~= nil or section.healthFormat ~= nil then
				section.texts = section.texts or {}
				section.texts.health = section.texts.health or TextSlot("healthpercent")
				if section.healthText == false then
					section.texts.health.preset = "off"
				elseif section.healthText == true or section.healthFormat then
					section.texts.health.preset = OLD_HEALTH_FORMATS[section.healthFormat or "PERCENT"] or "healthpercent"
				end
				section.healthText, section.healthFormat = nil, nil
			end
		end
	end
	if type(oldDebuffs) == "table" then
		if oldDebuffs.highlight ~= nil then db.dispel.enabled = oldDebuffs.highlight and true or false end
		if oldDebuffs.highlightMine ~= nil then db.dispel.mine = oldDebuffs.highlightMine and true or false end
	end
	db.debuffs, db.buffs, db.defensives, db.rangeAlpha = nil, nil, nil, nil
	-- The aggro border is the Effects tab's threat border now.
	if type(db.effects) ~= "table" then db.effects = {} end
	if type(db.indicators) == "table" and type(db.indicators.aggro) == "boolean" then
		db.effects.threat = type(db.effects.threat) == "table" and db.effects.threat or {}
		db.effects.threat.enabled = db.indicators.aggro
		db.indicators.aggro = nil
	end
	E:NormalizeUnitFX(db.effects, "GroupFrames")
end

local activeButtons = {} -- header buttons that currently show a unit
local allButtons = setmetatable({}, { __mode = "k" }) -- every button we set up

---------------------------------------------------------------------------
-- Value helpers (secret-safe)
---------------------------------------------------------------------------
local IsSecret = E.Secret

-- A plain (non-secret) result of fn(...), or nil.
local Plain = E.PlainCall

-- Test frames only (real names go through the [name:N] tag). UTF-8 safe
-- cut from Core (E:Utf8Sub).
local function ShortName(name, length)
	if not length or length <= 0 or IsSecret(name) then return name end
	local ok, short = pcall(E.Utf8Sub, E, name, length)
	if ok then return short end
	return name
end

-- "Offline", "Ghost", "Dead", "AFK" or nil. Group members' states are
-- normally not secret; anything secret or failing reads as "no status".
local function UnitStatus(unit)
	if Plain(UnitIsConnected, unit) == false then return PLAYER_OFFLINE or L["Offline"] end
	if Plain(UnitIsGhost, unit) then return L["Ghost"] end
	if Plain(UnitIsDead, unit) then return DEAD or L["Dead"] end
	if M.db.indicators.afk and Plain(UnitIsAFK, unit) then return "AFK" end
end

local function PowerColor(unit)
	local ok, _, token = pcall(UnitPowerType, unit)
	local color = ok and E:PowerColorObject(token)
	if color then return color.r, color.g, color.b end
	return 0.2, 0.4, 1
end

local function ClassRGB(class)
	local color = E:ClassColorObject(class)
	if color then return color.r, color.g, color.b end
	return unpack(E.media.accentColor)
end

local function AtlasExists(atlas)
	return atlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) ~= nil
end

local ROLE_ATLAS = { TANK = "roleicon-tiny-tank", HEALER = "roleicon-tiny-healer", DAMAGER = "roleicon-tiny-dps" }

local function SetRoleTexture(icon, role)
	local atlas = role and ROLE_ATLAS[role]
	if not atlas then
		icon:Hide()
		return
	end
	if AtlasExists(atlas) then
		icon:SetAtlas(atlas)
		icon:SetTexCoord(0, 1, 0, 1)
	elseif GetTexCoordsForRoleSmallCircle then
		icon:SetTexture("Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES")
		icon:SetTexCoord(GetTexCoordsForRoleSmallCircle(role))
	else
		icon:Hide()
		return
	end
	icon:Show()
end

local READY_TEXTURES = {
	ready = READY_CHECK_READY_TEXTURE or "Interface\\RaidFrame\\ReadyCheck-Ready",
	notready = READY_CHECK_NOT_READY_TEXTURE or "Interface\\RaidFrame\\ReadyCheck-NotReady",
	waiting = READY_CHECK_WAITING_TEXTURE or "Interface\\RaidFrame\\ReadyCheck-Waiting",
}

-- Leader, assistant, main tank and main assist marks (the game's own art).
local GROUP_ICONS = {
	leader = "Interface\\GroupFrame\\UI-Group-LeaderIcon",
	assist = "Interface\\GroupFrame\\UI-Group-AssistantIcon",
	maintank = "Interface\\GroupFrame\\UI-Group-MainTankIcon",
	mainassist = "Interface\\GroupFrame\\UI-Group-MainAssistIcon",
}

-- Center status icons, the same atlases Blizzard's raid frames use.
local STATUS_ATLAS = {
	summonPending = "RaidFrame-Icon-SummonPending",
	summonAccepted = "RaidFrame-Icon-SummonAccepted",
	summonDeclined = "RaidFrame-Icon-SummonDeclined",
	resurrect = "RaidFrame-Icon-Rez",
	phase = "RaidFrame-Icon-Phasing",
}

-- Dispel-type colors for the debuff highlight. Keys are the client's
-- dispel type enum values (Magic 1, Curse 2, Disease 3, Poison 4, Enrage 9,
-- Bleed 11) used by C_UnitAuras.GetAuraDispelTypeColor's color curve.
local DISPEL_COLORS = {
	[0] = { 0.8, 0, 0 },
	[1] = { 0.2, 0.6, 1 },
	[2] = { 0.6, 0, 1 },
	[3] = { 0.6, 0.4, 0 },
	[4] = { 0, 0.6, 0 },
	[9] = { 0.8, 0, 0 },
	[11] = { 0.8, 0, 0 },
}
local FALLBACK_HIGHLIGHT = { 0.8, 0, 0 }
-- Dispel types of the test frames' samples (DISPEL_COLORS 1-4).
M.SAMPLE_DISPEL = { "Magic", "Curse", "Disease", "Poison" }
local curves = {}

local function GetCurve(kind, points)
	if curves[kind] ~= nil then return curves[kind] end
	curves[kind] = false
	if not (C_CurveUtil and C_CurveUtil.CreateColorCurve) then return false end
	local ok, curve = pcall(function()
		local curve = C_CurveUtil.CreateColorCurve()
		if curve.SetType and Enum.LuaCurveType and Enum.LuaCurveType.Step then curve:SetType(Enum.LuaCurveType.Step) end
		for key, color in pairs(points) do curve:AddPoint(key, CreateColor(color[1], color[2], color[3], color[4] or 1)) end
		return curve
	end)
	if ok and curve then curves[kind] = curve end
	return curves[kind]
end

-- Color the highlight border from Blizzard's dispel-type color. The color
-- may hold secret values, so it only ever goes into a widget setter.
local function ColorHighlight(highlight, unit, aura)
	local curve = aura.auraInstanceID and C_UnitAuras.GetAuraDispelTypeColor and GetCurve("dispel", DISPEL_COLORS)
	if curve then
		local ok, color = pcall(C_UnitAuras.GetAuraDispelTypeColor, unit, aura.auraInstanceID, curve)
		if ok and color and pcall(function() highlight:SetBackdropBorderColor(color:GetRGBA()) end) then return end
	end
	local done = pcall(function()
		local color = _G.DebuffTypeColor[aura.dispelName]
		highlight:SetBackdropBorderColor(color.r, color.g, color.b, 1)
	end)
	if not done then highlight:SetBackdropBorderColor(FALLBACK_HIGHLIGHT[1], FALLBACK_HIGHLIGHT[2], FALLBACK_HIGHLIGHT[3], 1) end
end

---------------------------------------------------------------------------
-- Aura filters: Blizzard's own (AuraUtil.AuraFilters in Blizzard_FrameXMLUtil)
-- and Core/Filters.lua blocks built on them.
---------------------------------------------------------------------------
local DEFENSIVE_FILTERS = { "HELPFUL|BIG_DEFENSIVE", "HELPFUL|EXTERNAL_DEFENSIVE" }
local GROUP_RAID_BUFF = "HELPFUL|RAID"                        -- buffs you can cast on others
local DISPEL_MINE = "HARMFUL|RAID"                            -- what you can dispel
local DISPEL_GROUP = "HARMFUL|RAID_PLAYER_DISPELLABLE"        -- what someone in the group can dispel

-- The groups of a section's buff or debuff block, for the containers.
local function FilterGroups(block, kind, max)
	return E:AuraFilterGroups(block and block.filter, kind, max)
end

-- The dispel highlight's filter: yours, or anything the group can dispel.
local function DispelFilter()
	if M.db.dispel.mine then
		local filter = E.AuraHighlightSpec and E:AuraHighlightSpec("dispel")
		return filter or DISPEL_MINE
	end
	return DISPEL_GROUP
end

-- Spell names of the group buffs you can give, from the buff rules of the
-- Reminders module when it offers them. nil = use the game's
-- "buffs you can cast" filter instead.
local function GroupBuffRules()
	if not E.GetGroupBuffRules then return nil end
	local ok, rules = pcall(E.GetGroupBuffRules, E)
	if ok and type(rules) == "table" and next(rules) then return rules end
end

---------------------------------------------------------------------------
-- Layout helpers shared by the element updates and the styling
---------------------------------------------------------------------------
local function SettingsOf(button)
	return button.db or M.db.party
end

-- A row of icons from a corner: the first sits in the corner, the rest
-- grow inward along the edge.
local CORNER_GROWTH = {
	TOPLEFT = { "LEFT", "RIGHT", 1 }, BOTTOMLEFT = { "LEFT", "RIGHT", 1 }, LEFT = { "LEFT", "RIGHT", 1 },
	TOPRIGHT = { "RIGHT", "LEFT", -1 }, BOTTOMRIGHT = { "RIGHT", "LEFT", -1 }, RIGHT = { "RIGHT", "LEFT", -1 },
	TOP = { "LEFT", "RIGHT", 1 }, BOTTOM = { "LEFT", "RIGHT", 1 }, CENTER = { "LEFT", "RIGHT", 1 },
}
local CORNER_OFFSET = {
	TOPLEFT = { 2, -2 }, TOPRIGHT = { -2, -2 }, BOTTOMLEFT = { 2, 2 }, BOTTOMRIGHT = { -2, 2 },
	LEFT = { 2, 0 }, RIGHT = { -2, 0 }, TOP = { 0, -2 }, BOTTOM = { 0, 2 }, CENTER = { 0, 0 },
}
-- Buff and debuff rows can also sit in one row under the frame: buffs from
-- the left, debuffs from the right. Position -> the point on that row.
local BELOW = { BELOWLEFT = "TOPLEFT", BELOWRIGHT = "TOPRIGHT" }
local BELOW_GAP = 2

local PREDICTION_BARS = { "other", "mine", "absorb", "healAbsorb" }

-- A prediction bar that continues the health fill (incoming heals,
-- absorbs): it starts where `anchor` ends and grows the same way.
local function AttachAfter(bar, anchor, vertical, reverse, width, height)
	bar:ClearAllPoints()
	if vertical then
		local from, to = reverse and "TOP" or "BOTTOM", reverse and "BOTTOM" or "TOP"
		bar:SetPoint(from .. "LEFT", anchor, to .. "LEFT")
		bar:SetPoint(from .. "RIGHT", anchor, to .. "RIGHT")
		bar:SetHeight(math.max(height, 1))
	else
		local from, to = reverse and "RIGHT" or "LEFT", reverse and "LEFT" or "RIGHT"
		bar:SetPoint("TOP" .. from, anchor, "TOP" .. to)
		bar:SetPoint("BOTTOM" .. from, anchor, "BOTTOM" .. to)
		bar:SetWidth(math.max(width, 1))
	end
	bar:SetOrientation(vertical and "VERTICAL" or "HORIZONTAL")
	bar:SetReverseFill(reverse and true or false)
end

-- A bar that eats into the fill from its end (heal absorbs).
local function AttachInside(bar, anchor, vertical, reverse, width, height)
	bar:ClearAllPoints()
	if vertical then
		local edge = reverse and "BOTTOM" or "TOP"
		bar:SetPoint(edge .. "LEFT", anchor, edge .. "LEFT")
		bar:SetPoint(edge .. "RIGHT", anchor, edge .. "RIGHT")
		bar:SetHeight(math.max(height, 1))
	else
		local edge = reverse and "LEFT" or "RIGHT"
		bar:SetPoint("TOP" .. edge, anchor, "TOP" .. edge)
		bar:SetPoint("BOTTOM" .. edge, anchor, "BOTTOM" .. edge)
		bar:SetWidth(math.max(width, 1))
	end
	bar:SetOrientation(vertical and "VERTICAL" or "HORIZONTAL")
	bar:SetReverseFill(not reverse)
end

-- Portrait, name bar, health and power inside the frame, the fill direction
-- and the prediction bars on the fill's edge. Power can follow the member's
-- role (healers only), so this runs again when roles change; it only moves
-- EldoUI's own child regions, which is fine in combat too. Sizes come from
-- the settings, never from measuring a bar.
local function LayoutBars(button)
	local db = SettingsOf(button)
	local inset = E.pixel
	local width, height = db.width, db.height
	local powerHeight = db.powerHeight or 0
	local showPower = powerHeight > 0 and (db.powerFilter ~= "HEALERS" or button.isHealer == true)
	local style = db.portrait
	local portrait = style == "CLASS" or style == "2D" or style == "3D"
	local box = portrait and db.portraitBox and true or false
	local nameBar = db.nameBar and math.max((db.fontSize or 12) + 6, 12) or 0
	local vertical = db.fill == "VERTICAL"
	local reverse = db.reverseFill and true or false
	local key = table.concat({ width, height, powerHeight, tostring(showPower), tostring(style), tostring(box), nameBar,
		tostring(vertical), tostring(reverse), inset }, ":")
	if button.barsKey == key then return end
	button.barsKey = key

	-- Portrait: a square beside the bars, or (Boxed) its own box as tall as
	-- the frame, sharing its inner edge with the bars.
	local holder = button.portraitHolder
	local left = inset
	holder:ClearAllPoints()
	local px = 0
	if box then
		holder:SetPoint("TOPLEFT", 0, 0)
		holder:SetPoint("BOTTOMLEFT", 0, 0)
		holder:SetWidth(height)
		E:SetTemplate(holder)
		px = E:PixelFor(holder)
		left = height
	elseif portrait then
		if holder.SetBackdrop then holder:SetBackdrop(nil) end
		local size = math.max(height - 2 * inset, 1)
		holder:SetSize(size, size)
		holder:SetPoint("TOPLEFT", inset, -inset)
		left = inset + size + inset
	end
	button.portrait:ClearAllPoints()
	button.portrait:SetPoint("TOPLEFT", holder, "TOPLEFT", px, -px)
	button.portrait:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", -px, px)
	if portrait and style == "3D" then E.Portrait.Model(button) end
	if button.model then
		button.model:ClearAllPoints()
		button.model:SetPoint("TOPLEFT", holder, "TOPLEFT", px, -px)
		button.model:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", -px, px)
	end
	if not portrait then E.Portrait:Release(button) end
	button.portraitShown = portrait
	holder:SetShown(portrait)

	-- Name bar (Boxed): its own strip over the health bar.
	local top = inset
	local bar = button.nameBar
	bar:ClearAllPoints()
	if nameBar > 0 then
		bar:SetPoint("TOPLEFT", left, -inset)
		bar:SetPoint("TOPRIGHT", -inset, -inset)
		bar:SetHeight(nameBar)
		E:SetTemplate(bar)
		bar:Show()
		top = inset + nameBar + inset
	else
		bar:Hide()
	end

	button.power:SetShown(showPower)
	button.power:ClearAllPoints()
	button.power:SetPoint("BOTTOMLEFT", left, inset)
	button.power:SetPoint("BOTTOMRIGHT", -inset, inset)
	button.power:SetHeight(math.max(powerHeight, 1))

	button.health:ClearAllPoints()
	button.health:SetPoint("TOPLEFT", left, -top)
	button.health:SetPoint("TOPRIGHT", -inset, -top)
	if showPower then
		button.health:SetPoint("BOTTOM", button.power, "TOP", 0, inset)
	else
		button.health:SetPoint("BOTTOM", 0, inset)
	end
	button.health:SetOrientation(vertical and "VERTICAL" or "HORIZONTAL")
	button.health:SetReverseFill(reverse)

	local healthWidth = width - left - inset
	local healthHeight = height - top - inset - (showPower and (powerHeight + inset) or 0)
	local p = button.prediction
	local fill = button.health:GetStatusBarTexture()
	AttachAfter(p.other, fill, vertical, reverse, healthWidth, healthHeight)
	AttachAfter(p.mine, fill, vertical, reverse, healthWidth, healthHeight)
	AttachAfter(p.absorb, p.other:GetStatusBarTexture(), vertical, reverse, healthWidth, healthHeight)
	AttachInside(p.healAbsorb, fill, vertical, reverse, healthWidth, healthHeight)
	-- Overshield marker: a thin line at the far end of the health bar.
	local marker = p.overAbsorb
	marker:ClearAllPoints()
	if vertical then
		local edge = reverse and "BOTTOM" or "TOP"
		marker:SetPoint(edge .. "LEFT", button.health, edge .. "LEFT")
		marker:SetPoint(edge .. "RIGHT", button.health, edge .. "RIGHT")
		E:Hairline(marker, "h", 2)
	else
		local edge = reverse and "LEFT" or "RIGHT"
		marker:SetPoint("TOP" .. edge, button.health, "TOP" .. edge)
		marker:SetPoint("BOTTOM" .. edge, button.health, "BOTTOM" .. edge)
		E:Hairline(marker, "w", 2)
	end
	-- The gates follow their anchors' new sizes.
	if button.lowHealthGate then button.lowHealthGate:SetAnchor(button.health) end
	if button.lowPowerGate then button.lowPowerGate:SetAnchor(button.power) end
end

-- Role, leader/assist and main tank/assist icons sit in a row from the
-- section's corner; hidden icons take no space.
local function LayoutTopIcons(button)
	local icons = SettingsOf(button).icons
	local position = icons and icons.topPosition or "TOPLEFT"
	local growth = CORNER_GROWTH[position] or CORNER_GROWTH.TOPLEFT
	local offset = CORNER_OFFSET[position] or CORNER_OFFSET.TOPLEFT
	local previous
	for _, icon in ipairs(button.topIcons) do
		if icon:IsShown() then
			icon:ClearAllPoints()
			if previous then
				icon:SetPoint(growth[1], previous, growth[2], growth[3], 0)
			else
				icon:SetPoint(position, button.health, position, offset[1], offset[2])
			end
			previous = icon
		end
	end
end

---------------------------------------------------------------------------
-- Element updates (real units)
---------------------------------------------------------------------------
local function Interpolation()
	return E:BarInterpolation(M.db.smoothBars)
end

-- A value from the client straight into the bar (it may be secret).
local function SetBarValue(bar, value)
	local smooth = Interpolation()
	if smooth and pcall(bar.SetValue, bar, value, smooth) then return end
	pcall(bar.SetValue, bar, value)
end

-- Tag strings of a section's three text slots (Core/Tags.lua presets).
local TEXT_SLOTS = { name = "nameText", health = "healthText", extra = "extraText" }

local function SlotTag(db, slot)
	local block = db.texts and db.texts[slot]
	if type(block) ~= "table" then return "" end
	local tag = E:TagForSlot(block)
	-- Name length cuts the formatted name of the name presets.
	if slot == "name" and (db.nameLength or 0) > 0 and (block.preset == "name" or block.preset == "namelevel") then
		tag = tag:gsub("%[name%]", ("[name:%d]"):format(db.nameLength))
	end
	return tag
end

-- Bind the texts to the button's unit: the tag engine refreshes them on
-- their own tags' events. Units without unit events (main tank targets)
-- are rendered by the poll instead.
local function BindTexts(button)
	local db = SettingsOf(button)
	button.tags = button.tags or {}
	for slot, field in pairs(TEXT_SLOTS) do
		local tag = SlotTag(db, slot)
		button.tags[slot] = tag
		local text = button[field]
		if button.unit and tag ~= "" and not button.unitSuffix then
			E:BindTag(text, tag, button.unit, "GroupFrames")
		else
			E:UnbindTag(text)
			if tag == "" or not button.unit then text:SetText("") end
		end
	end
end

local function UpdateTexts(button)
	if not button.tags then return end
	for slot, field in pairs(TEXT_SLOTS) do
		local tag = button.tags[slot]
		if tag and tag ~= "" then E:RenderTag(button[field], tag, button.unit, "GroupFrames") end
	end
end

local function UpdateNameColor(button)
	local db = SettingsOf(button)
	if db.classColorName then
		local ok, r, g, b = pcall(E.ClassColor, E, button.unit)
		if ok then
			button.nameText:SetTextColor(r, g, b)
			return
		end
	end
	button.nameText:SetTextColor(1, 1, 1)
end

-- Heal prediction and absorbs: Core/UnitGraphics.lua reads Blizzard's
-- calculator and sets the bars, for unit and group frames alike.
local function UpdatePrediction(button)
	local p = button.prediction
	local settings = M.db.prediction
	local unit = button.unit
	if not (settings.heals or settings.absorbs or settings.healAbsorbs) then
		for _, key in ipairs(PREDICTION_BARS) do p[key]:Hide() end
		p.overAbsorb:Hide()
		return
	end
	local UG = E.UnitGraphics
	local detailed, all, mine, absorb, healAbsorb, overAbsorbed = UG.ReadPrediction(unit)
	if not detailed then
		all = Plain(UnitGetIncomingHeals, unit)
		mine = Plain(UnitGetIncomingHeals, unit, "player")
		absorb = Plain(UnitGetTotalAbsorbs, unit)
		healAbsorb = Plain(UnitGetTotalHealAbsorbs, unit)
	end
	local okMax, max = pcall(UnitHealthMax, unit)
	if not okMax then max = nil end
	UG.SetPredictionBar(p.other, settings.heals, all, max)
	UG.SetPredictionBar(p.mine, settings.heals, mine, max)
	UG.SetPredictionBar(p.absorb, settings.absorbs, absorb, max)
	UG.SetPredictionBar(p.healAbsorb, settings.healAbsorbs, healAbsorb, max)
	-- Overshield marker from Blizzard's own "clamped" flag.
	if settings.absorbs and type(overAbsorbed) == "boolean" and p.overAbsorb.SetAlphaFromBoolean then
		p.overAbsorb:Show()
		pcall(p.overAbsorb.SetAlphaFromBoolean, p.overAbsorb, overAbsorbed, 1, 0)
	else
		p.overAbsorb:Hide()
	end
end

-- Health color from the shared UnitFX gradient curve (secret-safe): the
-- client turns the health into the color. False when the client can't do
-- it, so the caller falls back to class colors.
local function ColorByValue(bar, unit)
	local color = E:UnitCurveHealth(unit, "healthGradient")
	if type(color) == "nil" then return false end
	return E:PaintColorResult(bar, color, "SetStatusBarColor") and true or false
end

-- An effect's settings from the Effects block (nil when off).
function GFX.On(key)
	local effects = M.db and M.db.effects
	local settings = effects and effects[key]
	if type(settings) == "table" and settings.enabled then return settings end
end

-- Class colors off: a dark fill over a lit well in the member's class
-- color, so the lost health stands out (Core/UnitGraphics.lua keeps the
-- fill and well rule for unit and group frames alike).
local function DarkHealth(bar)
	E.UnitGraphics:DarkFill(bar)
end

-- The empty part under the fill: dark under a light fill, lit in the
-- class color under the dark fill.
local function PaintWell(button, unit, classFile)
	local db = SettingsOf(button)
	E.UnitGraphics:PaintWell(button.health, db.classColor and "DEFAULT" or "LIT", unit, nil, classFile)
end
GFX.PaintWell = PaintWell

-- White texts on the health bar read on every fill: on a light fill (a
-- priest's or a mage's class color, the health gradient) the name and the
-- health value wear the dark halo (E:SetTextOnLightFill), on a dark fill
-- the font settings alone. A name in its own bar (Boxed) is not on the fill.
local function FitTextsToFill(button, light)
	E:SetTextOnLightFill(button.healthText, light)
	E:SetTextOnLightFill(button.nameText, light and not button.nameBar:IsShown())
end
GFX.FitTextsToFill = FitTextsToFill

local function UpdateHealth(button)
	local unit = button.unit
	local bar = button.health
	local db = SettingsOf(button)
	pcall(bar.SetMinMaxValues, bar, 0, UnitHealthMax(unit))
	SetBarValue(bar, UnitHealth(unit))
	if button.wellUnit ~= unit then
		button.wellUnit = unit
		PaintWell(button, unit)
	end

	-- Offline, dead, ghost and AFK replace the health text.
	local status = UnitStatus(unit)
	button.statusText:SetText(status or "")
	button.statusText:SetShown(status ~= nil)
	button.healthText:SetShown(status == nil)
	-- Dead, ghost, offline (Effects: Dead and offline look) and tapped take
	-- their General > Colors state color.
	local sr, sg, sb = E.FrameFX.StateColor(unit, GFX.On("deadLook") and true or false)
	local light
	if sr then
		bar:SetStatusBarColor(sr, sg, sb)
		light = E:IsLightFill(sr, sg, sb)
	elseif db.colorByValue and ColorByValue(bar, unit) then
		-- The game turns the health into the color: it is never read here.
		light = true
	elseif db.classColor then
		local ok, r, g, b = pcall(E.ClassColor, E, unit)
		if ok then bar:SetStatusBarColor(r, g, b) end
		light = not ok or E:IsLightFill(r, g, b)
	else
		DarkHealth(bar)
		light = E:IsLightFill(E.UnitGraphics.DarkFillColor())
	end
	FitTextsToFill(button, light)
	UpdatePrediction(button)
	E:UnitFXLowHealth(button.lowHealthGate, unit, GFX.On("lowHealth"))
end

local function UpdatePower(button)
	if not button.power:IsShown() then
		if button.lowPowerGate then button.lowPowerGate:Clear() end
		return
	end
	local unit = button.unit
	local bar = button.power
	pcall(bar.SetMinMaxValues, bar, 0, UnitPowerMax(unit))
	SetBarValue(bar, UnitPower(unit))
	bar:SetStatusBarColor(PowerColor(unit))
	E:UnitFXLowPower(button.lowPowerGate, unit, GFX.On("lowPower"))
end

local CLASS_ICONS = "Interface\\TargetingFrame\\UI-Classes-Circles"

local function SetClassPortrait(texture, class)
	local coords = class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
	if not coords then return false end
	texture:SetTexture(CLASS_ICONS)
	texture:SetTexCoord(unpack(coords))
	return true
end

-- Portrait: Core/Portrait.lua picks the 3D model, the 2D picture
-- or the class icon, grays it while dead or offline and reloads a model
-- only for a new unit or when forced (no flicker on polls).
function GFX.PortraitOpts(button, test)
	local db = SettingsOf(button)
	local opts = button.portraitOpts or {}
	button.portraitOpts = opts
	opts.style = db.portrait
	opts.framing = "FACE"
	opts.deadGrey = db.portraitDeadGrey ~= false and GFX.On("deadLook") and true or false
	opts.coords = button.portraitCoords
	opts.test = test and true or nil
	return opts
end

local function UpdatePortrait(button, force)
	if not button.portraitShown then return end
	E.Portrait:Update(button, button.unit, GFX.PortraitOpts(button), force and true or false)
end
function GFX.ForcePortrait(button) UpdatePortrait(button, true) end

-- The class or role badge on the frame's right edge.
function GFX.UpdateBadge(button, unit)
	local badge = button.badge
	local settings = SettingsOf(button).badge
	if not (badge and type(settings) == "table" and settings.enabled) then
		if badge then badge:Hide() end
		return
	end
	badge:SetShown(E.FrameFX.BadgeClass(badge, unit or button.unit, settings.mode))
end

local function UpdateRole(button)
	local icon = button.roleIcon
	local ok, role = pcall(UnitGroupRolesAssigned, button.unit)
	if not ok or IsSecret(role) then role = nil end
	if not SettingsOf(button).roleIcon or not pcall(SetRoleTexture, icon, role) then icon:Hide() end
	local healer = role == "HEALER"
	if button.isHealer ~= healer then
		button.isHealer = healer
		LayoutBars(button)
		GFX.SyncPartEvents(button)
		UpdatePower(button)
	end
	LayoutTopIcons(button)
end

local function UpdateGroupIcons(button)
	local unit = button.unit
	local indicators = M.db.indicators
	local leaderTexture, tankTexture
	if indicators.leader then
		if Plain(UnitIsGroupLeader, unit) then
			leaderTexture = GROUP_ICONS.leader
		elseif Plain(UnitIsGroupAssistant, unit) and IsInRaid() then
			leaderTexture = GROUP_ICONS.assist
		end
	end
	if indicators.mainTank and GetPartyAssignment and IsInRaid() then
		if Plain(GetPartyAssignment, "MAINTANK", unit) then
			tankTexture = GROUP_ICONS.maintank
		elseif Plain(GetPartyAssignment, "MAINASSIST", unit) then
			tankTexture = GROUP_ICONS.mainassist
		end
	end
	button.leaderIcon:SetTexture(leaderTexture)
	button.leaderIcon:SetShown(leaderTexture ~= nil)
	button.tankIcon:SetTexture(tankTexture)
	button.tankIcon:SetShown(tankTexture ~= nil)
	LayoutTopIcons(button)
end

local function UpdateRaidTarget(button)
	local icon = button.raidIcon
	-- GetRaidTargetIndex is secret on Forever: the index goes
	-- straight to the texture, with no test or math on it.
	local ok, index = false, nil
	if M.db.indicators.raidTarget and GetRaidTargetIndex then ok, index = pcall(GetRaidTargetIndex, button.unit) end
	local shown = ok and (IsSecret(index) or type(index) == "number") and SetRaidTargetIconTexture
		and pcall(SetRaidTargetIconTexture, icon, index) and true or false
	icon:SetShown(shown)
end

local function UpdateReadyCheck(button)
	local icon = button.readyIcon
	local status = M.db.indicators.readyCheck and Plain(GetReadyCheckStatus, button.unit)
	local texture = status and READY_TEXTURES[status]
	if texture then
		E.FrameFX.CancelFade(icon)
		icon.holding = nil
		icon:SetTexture(texture)
		icon:Show()
	elseif not icon.holding then
		icon:Hide()
	end
end

-- Summon, resurrection and phasing: the same priority as Blizzard's
-- center status icon (summon first, then resurrection, then phasing).
local function UpdateStatusIcon(button)
	local unit = button.unit
	local indicators = M.db.indicators
	local atlas
	if indicators.summon and C_IncomingSummon and Plain(C_IncomingSummon.HasIncomingSummon, unit) then
		local status = Plain(C_IncomingSummon.IncomingSummonStatus, unit)
		local states = Enum.SummonStatus or {}
		if status == states.Pending then
			atlas = STATUS_ATLAS.summonPending
		elseif status == states.Accepted then
			atlas = STATUS_ATLAS.summonAccepted
		elseif status == states.Declined then
			atlas = STATUS_ATLAS.summonDeclined
		end
	end
	if not atlas and indicators.resurrect and Plain(UnitHasIncomingResurrection, unit) then
		atlas = STATUS_ATLAS.resurrect
	end
	if not atlas and indicators.phase and Plain(UnitPhaseReason, unit) then
		atlas = STATUS_ATLAS.phase
	end
	if atlas and AtlasExists(atlas) then
		button.statusIcon:SetAtlas(atlas)
		button.statusIcon:Show()
	else
		button.statusIcon:Hide()
	end
	-- A resurrection or summon on its way breathes (Effects: status pulse).
	E.FrameFX.Pulse(button.statusIcon, atlas ~= nil and atlas ~= STATUS_ATLAS.phase and AtlasExists(atlas) and GFX.On("statusPulse") and true or false)
end

local function SetBorderColor(border, r, g, b, a)
	for _, edge in ipairs(border.edges) do edge:SetVertexColor(r, g, b, a) end
end

-- Threat border (Effects): the game's threat situation (0-3) for the
-- member, on any enemy or on your target (Blizzard's per-pair state, the
-- same source as the Threat module). Core/UnitFX.lua's threat curve
-- turns it into the border color, secret or not; nothing is compared.
local function UpdateThreat(button)
	local gate = button.threatGate
	local settings = GFX.On("threat")
	if not settings then
		gate:Clear()
		return
	end
	local other
	if M.db.indicators.aggroSource == "target" then
		if not Plain(UnitExists, "target") or Plain(UnitIsFriend, "player", "target") then
			gate:Clear()
			return
		end
		other = "target"
	end
	E:UnitFXThreat(gate, button.unit, settings, { other = other, thickness = 2 })
end

local function UpdateTargetBorder(button)
	local targeted = Plain(UnitIsUnit, button.unit, "target") and true or false
	local isTarget = M.db.indicators.target and targeted
	button.targetBorder:SetShown(isTarget and true or false)
	-- Effects: a short flash on the member you just targeted.
	if targeted and not button.wasTargeted then E.FrameFX.Flash(button.art, button.art, GFX.On("targetFlash")) end
	button.wasTargeted = targeted
end

-- Range: UnitInRange only answers for group members and can be secret in
-- combat, so Core/UnitFX.lua lets the client apply the alpha
-- (SetAlphaFromBoolean) to the inner art frame; the secure button's own
-- alpha is never touched. Each section keeps its own out-of-range opacity.
local function UpdateRange(button)
	local unit = button.unit
	if Plain(UnitIsUnit, unit, "player") then
		button.art:SetAlpha(1)
		return
	end
	local range = button.rangeSettings or { enabled = true }
	button.rangeSettings = range
	range.alpha = SettingsOf(button).rangeAlpha or 0.4
	E:UnitFXRange(button.art, unit, range)
end

-- One aura icon: texture, timer swipe and stack text, all through the
-- client's own formatters (the values may be secret in combat).
local function SetAuraIcon(icon, unit, aura, timer)
	pcall(icon.texture.SetTexture, icon.texture, aura.icon)
	icon.cooldown:SetHideCountdownNumbers(not timer)
	local id = aura.auraInstanceID
	local okDuration, duration = false, nil
	if id and C_UnitAuras.GetAuraDuration then okDuration, duration = pcall(C_UnitAuras.GetAuraDuration, unit, id) end
	if okDuration and duration and icon.cooldown.SetCooldownFromDurationObject then
		pcall(icon.cooldown.SetCooldownFromDurationObject, icon.cooldown, duration)
	else
		icon.cooldown:Clear()
	end
	local count = ""
	if id and C_UnitAuras.GetAuraApplicationDisplayCount then
		local okCount, text = pcall(C_UnitAuras.GetAuraApplicationDisplayCount, unit, id)
		if okCount and text then count = text end
	end
	icon.count:SetText(count)
	icon:Show()
end

-- Fill `icons` with the auras Blizzard's filter returns, in Blizzard's order.
-- `square`: an RGBA color to draw a flat square instead of the aura's
-- icon (the timer swipe stays).
local function FillIcons(icons, unit, filter, max, square, timer)
	local shown = 0
	max = math.min(max, #icons)
	-- The EldoUI icons (test frames, or no container): these reads fail in
	-- combat on Forever, so the icons then stay empty.
	if filter and max > 0 and C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
		for index = 1, 40 do
			if shown >= max then break end
			local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, unit, index, filter)
			if not ok or not aura then break end
			shown = shown + 1
			local icon = icons[shown]
			SetAuraIcon(icon, unit, aura, timer)
			if square then
				icon.texture:SetTexture(E.media.flat)
				icon.texture:SetVertexColor(square[1], square[2], square[3], square[4] or 1)
				icon.count:SetText("")
			else
				icon.texture:SetVertexColor(1, 1, 1, 1)
			end
		end
	end
	for index = shown + 1, #icons do icons[index]:Hide() end
end

local function FirstAura(unit, filter)
	if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return nil end
	local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, unit, 1, filter)
	if ok then return aura end
end

local function HasBuffNamed(unit, name)
	if not (C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName) then return nil end
	local ok, aura = pcall(C_UnitAuras.GetAuraDataBySpellName, unit, name, "HELPFUL")
	if not ok then return nil end
	return aura ~= nil
end

-- Out of combat only: does this member lack a group buff you can give?
-- Returns the buff's icon (or true without one) when it does. With the
-- Reminders buff rules each rule is one buff, met by any of its
-- spell names; without them, the game's "buffs you can cast" filter: you
-- wear one, this member wears none. Only presence; nothing is computed.
local function MissingBuff(unit)
	local rules = GroupBuffRules()
	if rules then
		for _, rule in ipairs(rules) do
			local has, known = false, true
			for name in pairs(rule.names or {}) do
				local found = HasBuffNamed(unit, name)
				if found == nil then known = false end
				if found then has = true break end
			end
			if not has and known then return rule.icon or true end
		end
		return nil
	end
	if FirstAura("player", GROUP_RAID_BUFF) ~= nil and FirstAura(unit, GROUP_RAID_BUFF) == nil then return true end
end

local function ShowMissingBuff(texture, missing, color)
	if not missing then
		texture:Hide()
		return
	end
	if missing ~= true then
		texture:SetTexture(missing)
		E:TrimIcon(texture)
		texture:SetVertexColor(1, 1, 1, 1)
	else
		texture:SetTexture(E.media.flat)
		texture:SetTexCoord(0, 1, 0, 1)
		texture:SetVertexColor(unpack(color))
	end
	texture:Show()
end

local function UpdateAuras(button)
	local unit = button.unit
	local db = SettingsOf(button)
	local showAuras = db.auras ~= false
	local debuffs, buffs = db.debuffs, db.buffs

	if button.containers then
		-- The game's containers follow UNIT_AURA themselves; units without
		-- unit events (main tank targets) are polled, so refresh those.
		if button.unitSuffix then
			for _, container in pairs(button.containers) do E.AuraWidget.Refresh(container) end
		end
	else
		local debuffGroups = FilterGroups(debuffs, "HARMFUL", debuffs.max)
		local buffGroups = FilterGroups(buffs, "HELPFUL", buffs.max)
		FillIcons(button.debuffIcons, unit, debuffGroups[1] and debuffGroups[1].filter or DISPEL_MINE,
			(showAuras and debuffs.enabled) and debuffs.max or 0, nil, debuffs.timer)
		FillIcons(button.buffIcons, unit, buffGroups[1] and buffGroups[1].filter or "HELPFUL|PLAYER",
			(showAuras and buffs.enabled) and buffs.max or 0, buffs.style == "SQUARES" and buffs.squareColor or nil, buffs.timer)
	end

	local missing
	if showAuras and buffs.missing and not InCombatLockdown() and Plain(UnitIsConnected, unit)
		and not Plain(UnitIsDeadOrGhost, unit) and not Plain(UnitIsUnit, unit, "player") then
		missing = MissingBuff(unit)
	end
	ShowMissingBuff(button.missingBuff, missing, buffs.missingColor)
	if button.containers then return end

	local defensives = db.defensives
	local defensive
	if showAuras and defensives.enabled then
		defensive = FirstAura(unit, DEFENSIVE_FILTERS[1])
		if not defensive and defensives.external then defensive = FirstAura(unit, DEFENSIVE_FILTERS[2]) end
	end
	if defensive and button.defensiveIcon then
		SetAuraIcon(button.defensiveIcon, unit, defensive, defensives.timer)
	elseif button.defensiveIcon then
		button.defensiveIcon:Hide()
	end

	-- The border color comes from the first debuff the player (or the
	-- group) can dispel, whatever the icon filter shows.
	local dispel = M.db.dispel
	local highlight = showAuras and dispel.enabled and dispel.style ~= "GLOW" and FirstAura(unit, DispelFilter())
	if highlight then
		ColorHighlight(button.highlight, unit, highlight)
		button.highlight:Show()
	else
		button.highlight:Hide()
	end
end

-- Boss mechanics: Blizzard draws private auras into anchors we give it;
-- the addon never sees them.
local function RemovePrivateAnchors(button)
	for index, id in pairs(button.privateAnchorIDs) do
		if C_UnitAuras and C_UnitAuras.RemovePrivateAuraAnchor then pcall(C_UnitAuras.RemovePrivateAuraAnchor, id) end
		button.privateAnchorIDs[index] = nil
	end
end

local function UpdatePrivateAnchors(button)
	RemovePrivateAnchors(button)
	local settings = M.db.privateAuras
	local unit = button.unit
	if not unit or not settings.enabled or SettingsOf(button).auras == false then return end
	if not (C_UnitAuras and C_UnitAuras.AddPrivateAuraAnchor) then return end
	for index = 1, math.min(settings.count, MAX_PRIVATE) do
		local anchor = button.privateAnchors[index]
		local ok, id = pcall(C_UnitAuras.AddPrivateAuraAnchor, {
			unitToken = unit,
			auraIndex = index,
			parent = anchor,
			showCooldownFrame = true,
			showCooldownEdge = false,
			showCountdownNumbers = settings.countdown and true or false,
			showDispelIcon = false,
			isContainer = false,
			iconInfo = {
				iconAnchor = { point = "CENTER", relativeTo = anchor, relativePoint = "CENTER", offsetX = 0, offsetY = 0 },
				iconWidth = anchor:GetWidth(),
				iconHeight = anchor:GetHeight(),
			},
		})
		if ok and id then button.privateAnchorIDs[index] = id end
	end
end

-- changed: a new unit is on the button (or it just showed).
local function UpdateAll(button, changed)
	local unit = button.unit
	if not unit or not Plain(UnitExists, unit) then return end
	UpdateRole(button)
	UpdateHealth(button)
	UpdatePower(button)
	UpdateTexts(button)
	UpdateNameColor(button)
	UpdatePortrait(button, changed == true)
	GFX.UpdateBadge(button)
	UpdateGroupIcons(button)
	UpdateRaidTarget(button)
	UpdateReadyCheck(button)
	UpdateStatusIcon(button)
	UpdateThreat(button)
	UpdateTargetBorder(button)
	UpdateAuras(button)
	UpdateRange(button)
end

local UNIT_EVENTS = {
	UNIT_HEALTH = UpdateHealth,
	UNIT_MAXHEALTH = UpdateHealth,
	-- Offline, dead or out of view: the dead look and the portrait follow.
	UNIT_CONNECTION = function(button) UpdateHealth(button) UpdatePortrait(button) UpdateRange(button) end,
	UNIT_FLAGS = function(button) UpdateHealth(button) UpdatePortrait(button) end,
	PLAYER_FLAGS_CHANGED = UpdateHealth,
	UNIT_HEAL_PREDICTION = UpdatePrediction,
	UNIT_ABSORB_AMOUNT_CHANGED = UpdatePrediction,
	UNIT_HEAL_ABSORB_AMOUNT_CHANGED = UpdatePrediction,
	UNIT_POWER_UPDATE = UpdatePower,
	UNIT_MAXPOWER = UpdatePower,
	UNIT_DISPLAYPOWER = UpdatePower,
	UNIT_NAME_UPDATE = UpdateNameColor,
	UNIT_PORTRAIT_UPDATE = GFX.ForcePortrait,
	UNIT_MODEL_CHANGED = GFX.ForcePortrait,
	UNIT_AURA = UpdateAuras,
	-- A unit the game sends range events for leaves the range timer.
	UNIT_IN_RANGE_UPDATE = function(button)
		button.rangeFed = button.unit
		UpdateRange(button)
	end,
	UNIT_THREAT_SITUATION_UPDATE = UpdateThreat,
	UNIT_THREAT_LIST_UPDATE = UpdateThreat,
	UNIT_PHASE = function(button) UpdateStatusIcon(button) UpdatePortrait(button) end,
	INCOMING_RESURRECT_CHANGED = UpdateStatusIcon,
	INCOMING_SUMMON_CHANGED = UpdateStatusIcon,
}

-- Unit events of the parts a button may not show: registered only while
-- the part is on, so a raid without power bars or portraits never wakes
-- for every member's mana tick or model change. The power part follows
-- the healer-only filter as roles change.
do
	local PARTS = {
		power = { "UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER" },
		portrait = { "UNIT_PORTRAIT_UPDATE", "UNIT_MODEL_CHANGED" },
		prediction = { "UNIT_HEAL_PREDICTION", "UNIT_ABSORB_AMOUNT_CHANGED", "UNIT_HEAL_ABSORB_AMOUNT_CHANGED" },
		threat = { "UNIT_THREAT_SITUATION_UPDATE", "UNIT_THREAT_LIST_UPDATE" },
	}
	GFX.partEvents = {}
	for part, events in pairs(PARTS) do
		for _, event in ipairs(events) do GFX.partEvents[event] = part end
	end
	local function Wanted(button, part)
		if part == "power" then return button.power:IsShown() and true or false end
		if part == "portrait" then return button.portraitShown and true or false end
		if part == "prediction" then
			local settings = M.db.prediction
			return (settings.heals or settings.absorbs or settings.healAbsorbs) and true or false
		end
		return GFX.On("threat") and true or false
	end
	-- After the unit or the button's look changed: each part's events on
	-- or off for the button's unit.
	function GFX.SyncPartEvents(button)
		local unit = button.unit
		if not unit or button.unitSuffix then return end
		local on = button.partsOn or {}
		button.partsOn = on
		for part, events in pairs(PARTS) do
			local want = Wanted(button, part)
			if on[part] ~= want then
				on[part] = want
				for _, event in ipairs(events) do
					if want then pcall(button.RegisterUnitEvent, button, event, unit)
					else pcall(button.UnregisterEvent, button, event) end
				end
			end
		end
	end
end

-- UNIT_AURA: the game's containers apply added, changed and removed auras
-- themselves; a partial update only checks the missing group buff mark
-- (out of combat). A full update (no update info, or the game says so),
-- and buttons without containers, refill everything. M.auraUpdates counts
-- both kinds, for the diagnostics.
M.auraUpdates = { partial = 0, full = 0 }
local function OnAura(button, updateInfo)
	local full = type(updateInfo) ~= "table" or not button.containers
	if not full then
		local flag = updateInfo.isFullUpdate
		full = IsSecret(flag) or flag == true
	end
	if full then
		M.auraUpdates.full = M.auraUpdates.full + 1
		UpdateAuras(button)
		return
	end
	M.auraUpdates.partial = M.auraUpdates.partial + 1
	local db = SettingsOf(button)
	local buffs = db.buffs
	if db.auras ~= false and buffs.missing and not InCombatLockdown() then
		local unit = button.unit
		local missing
		if Plain(UnitIsConnected, unit) and not Plain(UnitIsDeadOrGhost, unit) and not Plain(UnitIsUnit, unit, "player") then
			missing = MissingBuff(unit)
		end
		ShowMissingBuff(button.missingBuff, missing, buffs.missingColor)
	end
end

local function OnEvent(button, event, _, updateInfo)
	if not button.unit then return end
	if event == "UNIT_AURA" then return OnAura(button, updateInfo) end
	local handler = UNIT_EVENTS[event]
	if handler then handler(button) end
end

-- Units with a suffix ("raid3target") get no unit events: the shown ones
-- refresh a few times a second on the shared ticker (Core/Ticker.lua),
-- which stops while none of them shows.
local POLL_TICK, POLL_INTERVAL = "GroupFrames:poll", 0.25
local polledButtons = {} -- button -> true while it follows a suffix unit
local function Poll()
	local any = false
	for button in pairs(polledButtons) do
		if button.unit and button:IsVisible() then
			any = true
			UpdateAll(button)
		end
	end
	if not any then E.Ticker:Unsubscribe(POLL_TICK) end
end

function GFX.WatchPoll()
	if E.Ticker:IsSubscribed(POLL_TICK) then return end
	for button in pairs(polledButtons) do
		if button.unit and button:IsVisible() then
			E.Ticker:Subscribe(POLL_TICK, POLL_INTERVAL, Poll, M)
			return
		end
	end
end

-- Range: group members get UNIT_IN_RANGE_UPDATE when they walk in or
-- out of range. Until a button's unit has sent one (and for units that
-- never do: pets, target suffixes), it is checked twice a second.
local RANGE_TICK, RANGE_INTERVAL = "GroupFrames:range", 0.5
local function RangeTick()
	if not next(activeButtons) then
		E.Ticker:Unsubscribe(RANGE_TICK)
		return
	end
	for button in pairs(activeButtons) do
		local unit = button.unit
		if unit and button.rangeFed ~= unit and button:IsVisible() then
			M.rangeTicks = (M.rangeTicks or 0) + 1
			UpdateRange(button)
		end
	end
end

function GFX.WatchRange()
	if M.active and next(activeButtons) and not E.Ticker:IsSubscribed(RANGE_TICK) then
		E.Ticker:Subscribe(RANGE_TICK, RANGE_INTERVAL, RangeTick, M)
	end
end

function GFX.StopTicks()
	wipe(polledButtons)
	E.Ticker:Unsubscribe(POLL_TICK)
	E.Ticker:Unsubscribe(RANGE_TICK)
end

-- The header puts a new unit on a button: follow it.
local function SetUnit(button, unit)
	if unit and button.unitSuffix then unit = unit .. button.unitSuffix end
	if button.unit == unit then return end
	button.unit = unit
	-- The aura containers read the new unit themselves (allowed in combat).
	for _, container in pairs(button.containers or {}) do E.AuraWidget.SetUnit(container, unit) end
	button:UnregisterAllEvents()
	polledButtons[button] = nil
	BindTexts(button)
	if unit then
		if button.unitSuffix then
			polledButtons[button] = true
			GFX.WatchPoll()
		else
			for event in pairs(UNIT_EVENTS) do
				if not GFX.partEvents[event] then pcall(button.RegisterUnitEvent, button, event, unit) end
			end
			button.partsOn = nil
			GFX.SyncPartEvents(button)
		end
		activeButtons[button] = true
		GFX.WatchRange()
		UpdateAll(button, true)
	else
		activeButtons[button] = nil
	end
	UpdatePrivateAnchors(button)
	-- The cast bar follows the new unit (GroupFrames/Cast.lua).
	if M.CastUnitChanged then M.CastUnitChanged(button) end
end

-- Module or frame source off: the button stops following its unit and
-- forgets it, so ResumeButtons sets it up in full again.
local function ReleaseButton(button)
	activeButtons[button] = nil
	polledButtons[button] = nil
	button.unit = nil
	button:UnregisterAllEvents()
end

-- Module or frame source back on: every known button follows the unit the
-- header gave it again (ready check, target border, markers, roster), as
-- after a reload. The header keeps its unit attributes, so no attribute
-- change would bring them back on its own.
local function ResumeButtons()
	for button in pairs(allButtons) do
		if not button.unit then
			local unit = button:GetAttribute("unit")
			if unit then SetUnit(button, unit) end
		end
	end
end

---------------------------------------------------------------------------
-- Button visuals (shared by header buttons and test frames)
---------------------------------------------------------------------------
local function CreateAuraIcon(parent)
	local icon = CreateFrame("Frame", nil, parent)
	E:SetTemplate(icon)
	icon.texture = icon:CreateTexture(nil, "ARTWORK")
	icon.texture:SetPoint("TOPLEFT", E.pixel, -E.pixel)
	icon.texture:SetPoint("BOTTOMRIGHT", -E.pixel, E.pixel)
	E:TrimIcon(icon.texture)
	icon.cooldown = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
	icon.cooldown:SetAllPoints(icon.texture)
	icon.cooldown:SetDrawEdge(false)
	icon.cooldown:SetHideCountdownNumbers(true)
	icon.count = E:CreateText(icon, E.tokens.size.tiny, "RIGHT")
	icon.count:SetPoint("BOTTOMRIGHT", 1, 0)
	icon:Hide()
	return icon
end

-- The EldoUI aura icons (test frames, and header buttons without the
-- game's aura containers): six debuffs, six buffs and the defensive icon,
-- made as one set on the text layer. Made once, then kept and reused.
local function CreateLegacyIcons(button)
	if button.defensiveIcon then return end
	for index = 1, MAX_ICONS do
		button.debuffIcons[index] = CreateAuraIcon(button.textLayer)
		button.buffIcons[index] = CreateAuraIcon(button.textLayer)
	end
	button.defensiveIcon = CreateAuraIcon(button.textLayer)
end

-- A border made of four flat edge textures, so its color can come from a
-- color curve (secret-safe SetVertexColor) instead of a backdrop.
local function CreateEdgeBorder(parent, level)
	local border = CreateFrame("Frame", nil, parent)
	border:SetFrameLevel(level)
	border.edges = {}
	for index = 1, 4 do
		local edge = border:CreateTexture(nil, "OVERLAY")
		edge:SetTexture(E.media.flat)
		border.edges[index] = edge
	end
	border:Hide()
	return border
end

local function LayoutEdgeBorder(border, thickness)
	local top, bottom, left, right = unpack(border.edges)
	top:ClearAllPoints()
	top:SetPoint("TOPLEFT")
	top:SetPoint("TOPRIGHT")
	top:SetHeight(thickness)
	bottom:ClearAllPoints()
	bottom:SetPoint("BOTTOMLEFT")
	bottom:SetPoint("BOTTOMRIGHT")
	bottom:SetHeight(thickness)
	left:ClearAllPoints()
	left:SetPoint("TOPLEFT", 0, -thickness)
	left:SetPoint("BOTTOMLEFT", 0, thickness)
	left:SetWidth(thickness)
	right:ClearAllPoints()
	right:SetPoint("TOPRIGHT", 0, -thickness)
	right:SetPoint("BOTTOMRIGHT", 0, thickness)
	right:SetWidth(thickness)
end

local function OnEnterHighlight(button)
	if M.db and M.db.indicators.mouseover then button.hover:Show() end
end

local function OnLeaveHighlight(button)
	button.hover:Hide()
end

-- Colors from General > Colors (Heal prediction), set by FrameFX.
local function CreatePredictionBar(parent)
	local bar = CreateFrame("StatusBar", nil, parent)
	bar:SetStatusBarTexture(E.media.statusbar)
	bar:SetMinMaxValues(0, 1)
	bar:SetValue(0)
	bar:Hide()
	if E.statusBars then E.statusBars[bar] = true end
	return bar
end

-- db: the section the button is made for. With its aura display off the
-- aura icon set waits until the section shows auras (StyleButton).
local function CreateVisuals(button, db)
	-- Everything drawn sits on an inner art frame: the range fade
	-- and the fade-in work on its alpha, never on the secure button's.
	local art = CreateFrame("Frame", nil, button)
	art:SetAllPoints()
	art:EnableMouse(false)
	E:SetTemplate(art)
	button.art = art
	button.health = E:CreateStatusBar(art)
	button.health:SetClipsChildren(true)
	button.power = E:CreateStatusBar(art)
	-- Portrait: beside the bars or in its own box.
	local holder = CreateFrame("Frame", nil, art)
	holder:EnableMouse(false)
	holder:Hide()
	E.Portrait:Attach(button, holder)
	-- The Boxed name bar over the health bar.
	button.nameBar = CreateFrame("Frame", nil, art)
	button.nameBar:EnableMouse(false)
	button.nameBar:Hide()

	-- Heal prediction and absorbs live inside the (clipping) health bar.
	local p = {}
	p.other = CreatePredictionBar(button.health)
	p.mine = CreatePredictionBar(button.health)
	p.absorb = CreatePredictionBar(button.health)
	p.healAbsorb = CreatePredictionBar(button.health)
	p.mine:SetFrameLevel(p.other:GetFrameLevel() + 1)
	p.overAbsorb = button.health:CreateTexture(nil, "OVERLAY")
	p.overAbsorb:Hide()
	button.prediction = p
	E.FrameFX.ColorPrediction(p)

	local textLayer = CreateFrame("Frame", nil, art)
	textLayer:SetAllPoints()
	textLayer:SetFrameLevel(button.health:GetFrameLevel() + 3)
	button.textLayer = textLayer
	-- The name and value texts sit on their own layer above every aura
	-- icon and the game's aura containers, so an icon at the center of a
	-- small raid cell never hides them; the texts have an outline.
	local labelLayer = CreateFrame("Frame", nil, art)
	labelLayer:SetAllPoints()
	labelLayer:EnableMouse(false)
	labelLayer:SetFrameLevel(textLayer:GetFrameLevel() + 6)
	button.labelLayer = labelLayer
	button.nameText = E:CreateText(labelLayer)
	button.healthText = E:CreateText(labelLayer)
	button.statusText = E:CreateText(labelLayer)
	button.statusText:SetTextColor(unpack(E.media.text.secondary))
	button.statusText:Hide()
	button.extraText = E:CreateText(labelLayer)

	button.hover = button.health:CreateTexture(nil, "OVERLAY")
	button.hover:SetAllPoints(button.health)
	button.hover:SetTexture(E.media.flat)
	button.hover:Hide()

	button.roleIcon = textLayer:CreateTexture(nil, "OVERLAY")
	button.leaderIcon = textLayer:CreateTexture(nil, "OVERLAY")
	button.tankIcon = textLayer:CreateTexture(nil, "OVERLAY")
	button.topIcons = { button.roleIcon, button.leaderIcon, button.tankIcon }
	for _, icon in ipairs(button.topIcons) do icon:Hide() end
	button.raidIcon = textLayer:CreateTexture(nil, "OVERLAY")
	button.raidIcon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
	button.raidIcon:Hide()
	button.readyIcon = textLayer:CreateTexture(nil, "OVERLAY", nil, 7)
	button.readyIcon:Hide()
	button.statusIcon = textLayer:CreateTexture(nil, "OVERLAY", nil, 6)
	button.statusIcon:Hide()

	button.highlight = CreateFrame("Frame", nil, art, "BackdropTemplate")
	button.highlight:SetAllPoints()
	button.highlight:SetFrameLevel(textLayer:GetFrameLevel() + 1)
	button.highlight:Hide()
	-- Test frames: the dispel-type symbol of the sample (AuraWidget writes
	-- the real one through the client).
	button.highlight.symbol = E:CreateText(button.highlight, E.tokens.size.tiny, "RIGHT", "OVERLAY")
	button.highlight.symbol:SetPoint("RIGHT", -2, 0)

	-- Danger gates (Core/UnitFX.lua): threat round the frame, low health on
	-- the health bar, low power on the power bar.
	button.threatGate = E:CreateGate(art, 12)
	button.lowHealthGate = E:CreateGate(button.health, 3)
	button.lowPowerGate = E:CreateGate(button.power, 3)
	button.targetBorder = CreateEdgeBorder(art, textLayer:GetFrameLevel() + 2)
	button.targetBorder:SetAllPoints()
	button.badge = E.FrameFX.Badge(textLayer)

	button.debuffIcons, button.buffIcons = {}, {}
	if not db or db.auras ~= false then CreateLegacyIcons(button) end
	button.missingBuff = textLayer:CreateTexture(nil, "OVERLAY", nil, 5)
	button.missingBuff:SetTexture(E.media.flat)
	button.missingBuff:Hide()

	-- Holders for the game's aura containers: icons inside the health bar
	-- (inset like the EldoUI icons), the dispel highlight over the frame.
	button.auraHolder = CreateFrame("Frame", nil, textLayer)
	button.auraHolder:SetPoint("TOPLEFT", button.health, "TOPLEFT", 2, -2)
	button.auraHolder:SetPoint("BOTTOMRIGHT", button.health, "BOTTOMRIGHT", -2, 2)
	-- The row under the frame ("Below" positions): as wide as the frame.
	button.belowHolder = CreateFrame("Frame", nil, textLayer)
	button.belowHolder:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -BELOW_GAP)
	button.belowHolder:SetPoint("TOPRIGHT", button, "BOTTOMRIGHT", 0, -BELOW_GAP)
	button.belowHolder:SetHeight(1)
	button.highlightHolder = CreateFrame("Frame", nil, art)
	button.highlightHolder:SetAllPoints()
	button.highlightHolder:SetFrameLevel(textLayer:GetFrameLevel() + 1)

	button.privateAnchors, button.privateAnchorIDs = {}, {}
	for index = 1, MAX_PRIVATE do
		local anchor = CreateFrame("Frame", nil, textLayer)
		anchor:SetFrameLevel(textLayer:GetFrameLevel() + 3)
		button.privateAnchors[index] = anchor
	end

	-- Every layer drawn over the unit button leaves the mouse to it, so a
	-- click on any part of the frame targets the member (and click-casts).
	for _, layer in ipairs({ textLayer, button.highlight, button.auraHolder, button.belowHolder, button.highlightHolder,
		button.targetBorder, button.health, button.power }) do
		layer:EnableMouse(false)
	end
	for _, anchor in ipairs(button.privateAnchors) do anchor:EnableMouse(false) end
end

-- Part levels from the button's own level, the order the unit frames use
-- (E.UnitGraphics.BAR_LEVELS): the art frame with the graphics' material,
-- the empty health well, the health fill, heal prediction, then the icon
-- and text layers. No part shares the well's or the fill's level, so the
-- material can never cover them. Only EldoUI's own non-secure children
-- move, never the button.
local LEVEL_STEPS = { text = 3, highlight = 1, targetBorder = 2, labels = 6, private = 3 }
function GFX.SetLevels(button)
	local base, level = button:GetFrameLevel(), E.UnitGraphics.BAR_LEVELS
	button.art:SetFrameLevel(base + level.art)
	button.health.bg:SetFrameLevel(base + level.well)
	button.health:SetFrameLevel(base + level.fill)
	button.power.bg:SetFrameLevel(base + level.well)
	button.power:SetFrameLevel(base + level.fill)
	local p = button.prediction
	for _, key in ipairs({ "other", "absorb", "healAbsorb" }) do p[key]:SetFrameLevel(base + level.prediction) end
	p.mine:SetFrameLevel(base + level.predictionMine)
	local text = base + level.fill + LEVEL_STEPS.text
	button.textLayer:SetFrameLevel(text)
	button.labelLayer:SetFrameLevel(text + LEVEL_STEPS.labels)
	button.highlight:SetFrameLevel(text + LEVEL_STEPS.highlight)
	button.highlightHolder:SetFrameLevel(text + LEVEL_STEPS.highlight)
	button.targetBorder:SetFrameLevel(text + LEVEL_STEPS.targetBorder)
	for _, anchor in ipairs(button.privateAnchors) do anchor:SetFrameLevel(text + LEVEL_STEPS.private) end
end

local function LayoutIconRow(icons, anchorTo, position, size, count, below)
	if BELOW[position] then
		anchorTo, position = below or anchorTo, BELOW[position]
	end
	local growth = CORNER_GROWTH[position] or CORNER_GROWTH.BOTTOMRIGHT
	local offset = CORNER_OFFSET[position] or CORNER_OFFSET.BOTTOMRIGHT
	-- Centered rows (TOP, BOTTOM, CENTER) start half a row to the left.
	local centred = position == "TOP" or position == "BOTTOM" or position == "CENTER"
	local shift = centred and -((count - 1) * (size + 2)) / 2 or 0
	for index, icon in ipairs(icons) do
		icon:SetSize(size, size)
		icon:ClearAllPoints()
		if index == 1 then
			if anchorTo == below and below then
				icon:SetPoint(position, anchorTo, position, 0, 0)
			elseif centred then
				icon:SetPoint(position, anchorTo, position, offset[1] + shift, offset[2])
			else
				icon:SetPoint(position, anchorTo, position, offset[1], offset[2])
			end
		else
			icon:SetPoint(growth[1], icons[index - 1], growth[2], growth[3] * 2, 0)
		end
	end
end

---------------------------------------------------------------------------
-- Aura containers for header buttons (see the top of the file)
---------------------------------------------------------------------------
-- Position -> icon growth and wrap; the container is pinned at the same
-- point of the holder, so corners grow inward and edges stay centered.
local CONTAINER_FLOW = {
	TOPLEFT = { "RIGHT", "DOWN" }, LEFT = { "RIGHT", "DOWN" }, BOTTOMLEFT = { "RIGHT", "UP" },
	TOPRIGHT = { "LEFT", "DOWN" }, RIGHT = { "LEFT", "DOWN" }, BOTTOMRIGHT = { "LEFT", "UP" },
	TOP = { "RIGHT", "DOWN" }, BOTTOM = { "RIGHT", "UP" }, CENTER = { "RIGHT", "DOWN" },
	BELOWLEFT = { "RIGHT", "DOWN" }, BELOWRIGHT = { "LEFT", "DOWN" },
}
-- Highlight border colors by dispel type (the game picks the key, so a
-- secret dispel type is fine).
local HIGHLIGHT_COLORS = {
	None = FALLBACK_HIGHLIGHT, Magic = DISPEL_COLORS[1], Curse = DISPEL_COLORS[2], Disease = DISPEL_COLORS[3],
	Poison = DISPEL_COLORS[4], Enrage = DISPEL_COLORS[9], Bleed = DISPEL_COLORS[11],
}
local CONTAINER_KINDS = { "debuffs", "buffs", "defensives", "highlight", "dispelGlow", "bossGlow" }

-- General > Glows rows (Core/Glow.lua): the glow shows while the client
-- has an aura for the slot, so EldoUI never decides when it lights up.
E:RegisterGlowUser("groupDispel", {
	title = "Party and raid: dispellable debuff",
	desc = "Glow on a party or raid frame while the member has a debuff you (or your group) can dispel. Switch it on under Party and Raid > Indicators.",
	order = 40,
	default = { style = "pixel", colorMode = "custom", color = { 0.2, 0.6, 1 } },
})
E:RegisterGlowUser("groupBoss", {
	title = "Party and raid: boss aura",
	desc = "Glow on a party or raid frame while the member has an aura the game marks as a boss aura. Switch it on under Party and Raid > Indicators.",
	order = 41,
	default = { style = "pulse", colorMode = "custom", color = { 1, 0.35, 0.1 } },
})

local function ContainerRow(position, size, max, filters, timer)
	local flow = CONTAINER_FLOW[position] or CONTAINER_FLOW.BOTTOMRIGHT
	return {
		filters = filters, max = max, perRow = max, size = size, spacing = 2,
		growth = flow[1], wrap = flow[2], attach = BELOW[position] or (CONTAINER_FLOW[position] and position) or "BOTTOMRIGHT",
		below = BELOW[position] and true or nil,
		sort = "INDEX", duration = timer and "SWIPE" or "SWIPEONLY",
		durationSize = math.max(math.floor(size * 0.55), 8), countSize = math.max(math.floor(size * 0.55), 8),
		tooltip = false, -- clicks and mouseover stay the unit button's
	}
end

local function FilterStrings(groups)
	local list = {}
	for index, group in ipairs(groups) do list[index] = group.filter end
	return list
end

-- What each container should be for this button now (nil = none), and
-- for the buff and debuff rows the filter block they come from.
local function ContainerSettings(button)
	local db = SettingsOf(button)
	local wanted, filters = {}, {}
	if db.auras == false then return wanted, filters end
	local maxSize = math.max(8, (db.height or 30) - 6)
	local debuffs, buffs, defensives = db.debuffs, db.buffs, db.defensives
	if debuffs.enabled and debuffs.max > 0 then
		local max = math.min(debuffs.max, MAX_ICONS)
		wanted.debuffs = ContainerRow(debuffs.position, math.max(8, math.min(debuffs.size, maxSize)), max,
			FilterStrings(FilterGroups(debuffs, "HARMFUL", max)), debuffs.timer)
		wanted.debuffs.fx = E.FrameFX.AuraFX(M.db.effects)
		filters.debuffs = { block = debuffs.filter, kind = "HARMFUL", total = max }
	end
	if buffs.enabled and buffs.max > 0 then
		local max = math.min(buffs.max, MAX_ICONS)
		local row = ContainerRow(buffs.position, math.max(8, math.min(buffs.size, maxSize)), max,
			FilterStrings(FilterGroups(buffs, "HELPFUL", max)), buffs.timer)
		if buffs.style == "SQUARES" then
			local c = buffs.squareColor
			row.square = { c[1], c[2], c[3], c[4] or 1 }
			row.countSize = 0
		end
		row.fx = E.FrameFX.AuraFX(M.db.effects)
		wanted.buffs = row
		filters.buffs = { block = buffs.filter, kind = "HELPFUL", total = max }
	end
	if defensives.enabled then
		local list = { DEFENSIVE_FILTERS[1] }
		if defensives.external then list[2] = DEFENSIVE_FILTERS[2] end
		local row = ContainerRow(defensives.position, math.max(8, math.min(defensives.size, maxSize)), #list, list, defensives.timer)
		row.perGroup = 1
		wanted.defensives = row
	end
	local dispel = M.db.dispel
	if dispel.enabled and dispel.style ~= "GLOW" then
		wanted.highlight = {
			filters = { DispelFilter() },
			max = 1, perGroup = 1, perRow = 1, width = db.width, height = db.height, spacing = 0,
			growth = "RIGHT", wrap = "DOWN", attach = "TOPLEFT", sort = "INDEX", duration = "NONE",
			edgeOnly = true, edgeSize = E.pixel * 2, dispelColors = HIGHLIGHT_COLORS, tooltip = false,
		}
	end
	if dispel.enabled and (dispel.style == "GLOW" or dispel.style == "BOTH") then
		wanted.dispelGlow = { slot = true, filter = DispelFilter(), glow = "groupDispel", width = db.width, height = db.height }
	end
	if M.db.bossGlow and E.AuraHighlightSpec then
		local filter, options = E:AuraHighlightSpec("boss")
		if filter then
			wanted.bossGlow = { slot = true, filter = filter, candidateFilters = options and options.candidateFilters,
				glow = "groupBoss", width = db.width, height = db.height }
		end
	end
	return wanted, filters
end

-- The glow look baked into a slot frame when the client builds it (style,
-- color, lines, speed ...). The client may hand the slot frame out
-- forbidden while auras are secret, so E:RefreshGlows can't always reach
-- it: the look and the theme (E:ThemeKey, accent glows) are part of the
-- slot signature instead, and a theme refresh (E:RefreshTheme ->
-- OnProfileChanged) rebuilds the slot with the new look.
local function GlowLook(key)
	if not (key and E.GlowSettings) then return "" end
	local style, opts = E:GlowSettings(key)
	local parts = { tostring(style) }
	local names = {}
	for name in pairs(opts or {}) do names[#names + 1] = name end
	table.sort(names)
	for _, name in ipairs(names) do
		local value = opts[name]
		if type(value) == "table" then
			local list = {}
			for index = 1, 4 do list[index] = ("%.3f"):format(tonumber(value[index]) or 0) end
			value = table.concat(list, ",")
		end
		parts[#parts + 1] = name .. "=" .. tostring(value)
	end
	return table.concat(parts, ";")
end

local function SlotSignature(spec)
	local flags = {}
	for key, value in pairs(spec.candidateFilters or {}) do flags[#flags + 1] = key .. "=" .. tostring(value) end
	table.sort(flags)
	return table.concat({ "slot", spec.filter, table.concat(flags, ","), spec.glow, spec.width, spec.height, E.pixel or 1,
		GlowLook(spec.glow), E.ThemeKey and E:ThemeKey() or "" }, ":")
end
M.SlotSignature = SlotSignature -- test hook

-- One aura slot over the whole frame: the client shows its frame while a
-- matching aura is on the unit and hides it otherwise; the frame carries
-- the glow. No icon, no mouse.
local function CreateGlowSlot(holder, spec, unit)
	local ok, container = pcall(CreateFrame, "AuraContainer", nil, holder, "CustomAuraContainerTemplate")
	if not ok or not container or type(container.AddAuraSlot) ~= "function" then return nil end
	if container.EnableMouse then pcall(container.EnableMouse, container, false) end
	local width, height, glow = spec.width, spec.height, spec.glow
	local added, slotFrame = pcall(container.AddAuraSlot, container, "glow", spec.filter, {
		candidateFilters = spec.candidateFilters,
		initializeFrame = function(frame)
			frame:SetSize(width, height)
			if frame.SetMouseClickEnabled then pcall(frame.SetMouseClickEnabled, frame, false) end
			if frame.SetMouseMotionEnabled then pcall(frame.SetMouseMotionEnabled, frame, false) end
			E:ShowUserGlow(frame, glow)
		end,
	})
	if not added then
		container:Hide()
		return nil
	end
	container:ClearAllPoints()
	container:SetPoint("CENTER", holder, "CENTER")
	if slotFrame then
		pcall(function()
			slotFrame:ClearAllPoints()
			slotFrame:SetPoint("CENTER", holder, "CENTER")
		end)
	end
	container:Show()
	if container.SetUnit then pcall(container.SetUnit, container, unit or "none") end
	return container
end

-- Create, replace or drop a header button's containers to match the
-- settings. Containers are made out of combat; a change in combat waits.
local function ApplyContainers(button)
	local widget = E.AuraWidget
	if not (allButtons[button] and widget and widget.Available()) then return end
	button.containers = button.containers or {}
	button.containerSigs = button.containerSigs or {}
	local wanted, filters = ContainerSettings(button)
	local waiting = false
	for _, kind in ipairs(CONTAINER_KINDS) do
		local settings = wanted[kind]
		local filter = filters[kind]
		local signature
		if settings and settings.slot then
			signature = SlotSignature(settings)
		elseif settings then
			signature = widget.Signature(settings, true) .. (filter and E:AuraFilterSignature(filter.block, filter.kind) or "")
				.. (settings.below and ":below" or "")
		end
		if button.containerSigs[kind] ~= signature then
			if InCombatLockdown() then
				waiting = true
			else
				if button.containers[kind] then E:UntrackAuraContainer(button.containers[kind]) end
				widget.Release(button.containers[kind])
				button.containers[kind], button.containerSigs[kind] = nil, nil
				if settings then
					local holder = (kind == "debuffs" or kind == "buffs" or kind == "defensives") and button.auraHolder or button.highlightHolder
					if settings.below then holder = button.belowHolder end
					local container
					if settings.slot then
						container = CreateGlowSlot(holder, settings, button.unit)
					else
						settings.unit = button.unit or "none"
						-- Its spell lists change in place below: a pool of its own.
						if filter then settings.pool = "GroupFrames" end
						container = widget.Create(holder, settings)
					end
					if container then button.containers[kind], button.containerSigs[kind] = container, signature end
				end
			end
		end
		-- Spell lists and conditions are updated in place (out of combat).
		local container = button.containers[kind]
		if container and filter and not InCombatLockdown() then
			E:ApplyAuraFilters(container, filter.block, filter.kind, filter.total)
			E:TrackAuraContainer(container, filter.block, filter.kind, filter.total)
		end
	end
	-- The EldoUI icons are only for test frames from now on.
	for _, icon in ipairs(button.debuffIcons) do icon:Hide() end
	for _, icon in ipairs(button.buffIcons) do icon:Hide() end
	if button.defensiveIcon then button.defensiveIcon:Hide() end
	button.highlight:Hide()
	if waiting and not button.containersQueued then
		button.containersQueued = true
		E:RunOutOfCombat(function()
			button.containersQueued = nil
			ApplyContainers(button)
		end)
	end
end

-- Drop every container (module off).
local function ReleaseContainers(button)
	if not button.containers or InCombatLockdown() then return end
	for kind, container in pairs(button.containers) do
		E:UntrackAuraContainer(container)
		E.AuraWidget.Release(container)
		button.containers[kind], button.containerSigs[kind] = nil, nil
	end
end

local function PlaceIcon(icon, anchorTo, position, size)
	local offset = CORNER_OFFSET[position] or CORNER_OFFSET.CENTER
	icon:SetSize(size, size)
	icon:ClearAllPoints()
	icon:SetPoint(position, anchorTo, position, offset[1], offset[2])
end

-- The aura icon set for a section that shows auras, made the first time
-- it is styled with them. A header button in combat only gets it when the
-- header makes the button (CreateVisuals); a settings change restyles
-- header buttons after combat (ConfigureHeader), which makes it then.
local function EnsureLegacyIcons(button, db)
	if button.defensiveIcon or db.auras == false then return end
	if allButtons[button] and InCombatLockdown() then return end
	CreateLegacyIcons(button)
end

-- Size-independent styling: bar layout, fonts and icon placement. Only
-- touches EldoUI's own child regions, so it is safe in combat too.
local function StyleButton(button, db)
	button.db = db
	button.barsKey = nil
	button.wellUnit = nil
	local width, height = db.width, db.height
	GFX.SetLevels(button)
	button.health:SetStatusBarTexture(E.media.statusbar)
	button.power:SetStatusBarTexture(E.media.statusbar)
	for _, key in ipairs(PREDICTION_BARS) do button.prediction[key]:SetStatusBarTexture(E.media.statusbar) end
	LayoutBars(button)
	GFX.SyncPartEvents(button)

	local fontSize = db.fontSize
	local smallSize = math.max(fontSize - 2, 8)
	E:SetNameTextFont(button.nameText, fontSize)
	E:SetFont(button.healthText, smallSize)
	E:SetFont(button.statusText, smallSize)
	E:SetFont(button.extraText, smallSize)
	button.nameText:ClearAllPoints()
	-- The status text (Dead, Offline, AFK) takes the health text's place.
	local healthTexts = { button.healthText, button.statusText }
	for _, text in ipairs(healthTexts) do text:ClearAllPoints() end
	local barWidth = width - (button.portraitShown and height or 0)
	if button.nameBar:IsShown() then
		-- Boxed: the name in its bar, the health text on the right of the health.
		button.nameText:SetJustifyH("LEFT")
		button.nameText:SetPoint("LEFT", button.nameBar, "LEFT", 4, 0)
		button.nameText:SetWidth(math.max(barWidth - 10, 1))
		for _, text in ipairs(healthTexts) do
			text:SetJustifyH("RIGHT")
			text:SetPoint("RIGHT", button.health, "RIGHT", -5, 0)
		end
	elseif barWidth >= height * 2.5 then
		-- Wide bar: name left, health right.
		button.nameText:SetJustifyH("LEFT")
		button.nameText:SetPoint("LEFT", button.health, "LEFT", 6, 0)
		button.nameText:SetWidth(barWidth * 0.62)
		for _, text in ipairs(healthTexts) do
			text:SetJustifyH("RIGHT")
			text:SetPoint("RIGHT", button.health, "RIGHT", -5, 0)
		end
	else
		-- Tile: name centered, health under it.
		button.nameText:SetJustifyH("CENTER")
		button.nameText:SetPoint("CENTER", button.health, "CENTER", 0, fontSize * 0.35)
		button.nameText:SetWidth(math.max(barWidth - 6, 1))
		for _, text in ipairs(healthTexts) do
			text:SetJustifyH("CENTER")
			text:SetPoint("TOP", button.nameText, "BOTTOM", 0, -1)
		end
	end
	local extraPosition = (db.texts and db.texts.extraPosition) or "BOTTOM"
	local extraOffset = CORNER_OFFSET[extraPosition] or CORNER_OFFSET.BOTTOM
	button.extraText:ClearAllPoints()
	button.extraText:SetPoint(extraPosition, button.health, extraPosition, extraOffset[1], extraOffset[2])

	local r, g, b = unpack(E.media.accentColor)
	button.hover:SetVertexColor(r, g, b, 0.15)
	SetBorderColor(button.targetBorder, r, g, b, 1)
	LayoutEdgeBorder(button.targetBorder, E.pixel)
	E.FrameFX.ColorPrediction(button.prediction)
	-- The badge: round in the Blizzard and Classic art styles, square in
	-- Modern, centered on the top right corner.
	local badge = db.badge
	if type(badge) == "table" and badge.enabled then
		E.FrameFX.StyleBadge(button.badge, math.max(badge.size or 16, 8), E.FrameFX.RoundArt())
		E.FrameFX.PlaceBadge(button.badge, "OUTER_TOP", button, nil, "RIGHT")
	else
		button.badge:Hide()
	end

	-- Icons: sizes 0 = fit the font and the frame.
	local icons = db.icons or {}
	local autoSize = math.max(10, math.min(fontSize, height - 4))
	local topSize = (icons.topSize or 0) > 0 and icons.topSize or autoSize
	for _, icon in ipairs(button.topIcons) do icon:SetSize(topSize, topSize) end
	if not db.roleIcon then button.roleIcon:Hide() end
	LayoutTopIcons(button)
	local raidSize = (icons.raidSize or 0) > 0 and icons.raidSize or (autoSize + 2)
	PlaceIcon(button.raidIcon, button.health, icons.raidPosition or "TOPRIGHT", raidSize)
	local statusSize = (icons.statusSize or 0) > 0 and icons.statusSize or math.max(10, math.min(height - 6, 24))
	PlaceIcon(button.readyIcon, button.health, icons.statusPosition or "CENTER", statusSize)
	PlaceIcon(button.statusIcon, button.health, icons.statusPosition or "CENTER", statusSize)

	button.highlight:SetBackdrop({ edgeFile = E.media.flat, edgeSize = E.pixel * 2 })

	local maxSize = math.max(8, height - 6)
	local debuffs, buffs, defensives = db.debuffs, db.buffs, db.defensives
	EnsureLegacyIcons(button, db)
	local debuffCount = debuffs.enabled and math.min(debuffs.max, MAX_ICONS) or 0
	LayoutIconRow(button.debuffIcons, button.health, debuffs.position, math.max(8, math.min(debuffs.size, maxSize)), debuffCount, button.belowHolder)
	for index, icon in ipairs(button.debuffIcons) do
		if index > debuffCount then icon:Hide() end
	end
	local buffCount = buffs.enabled and math.min(buffs.max, MAX_ICONS) or 0
	LayoutIconRow(button.buffIcons, button.health, buffs.position, math.max(8, math.min(buffs.size, maxSize)), buffCount, button.belowHolder)
	for index, icon in ipairs(button.buffIcons) do
		if index > buffCount then icon:Hide() end
	end
	local missingSize = math.max(6, math.min(math.floor(buffs.size * 0.6), maxSize))
	PlaceIcon(button.missingBuff, button.health, buffs.missingPosition or "TOPRIGHT", missingSize)
	if not buffs.missing then button.missingBuff:Hide() end
	LayoutIconRow({ button.defensiveIcon }, button.health, defensives.position, math.max(8, math.min(defensives.size, maxSize)), 1)
	if button.defensiveIcon and not defensives.enabled then button.defensiveIcon:Hide() end

	local private = M.db.privateAuras
	local privateCount = math.max(1, math.min(private.count, MAX_PRIVATE))
	LayoutIconRow(button.privateAnchors, button.health, private.position, math.max(8, math.min(private.size, maxSize)), privateCount)

	-- Shared countdown look on the EldoUI icons (test frames, or a frame
	-- whose container could not be made).
	if E.AuraWidget and E.AuraWidget.StyleCooldown then
		local function Look(list, on, size)
			for _, icon in ipairs(list) do
				if on then E.AuraWidget.StyleCooldown(icon.cooldown, math.max(math.floor(size * 0.55), 8)) end
				icon.cooldown:SetHideCountdownNumbers(not on)
			end
		end
		Look(button.debuffIcons, debuffs.timer, debuffs.size)
		Look(button.buffIcons, buffs.timer, buffs.size)
		Look({ button.defensiveIcon }, defensives.timer, defensives.size)
	end
	if allButtons[button] then BindTexts(button) end
	ApplyContainers(button)
	-- Frame art (Group-frame graphics): textures on the art frame only, safe in combat.
	if E.UnitGraphics then E.UnitGraphics:Apply(button, db, "group") end
end

---------------------------------------------------------------------------
-- Secure header buttons
---------------------------------------------------------------------------
-- Runs in the restricted environment when the header creates a button.
-- Sizes and the unit suffix come from header attributes; the Lua side is
-- called by name. Click-cast attributes (Modules/ClickCast.lua) are copied
-- from the header too, so a button made in combat still gets them.
local INITIAL_CONFIG = [[
	local header = self:GetParent()
	self:SetWidth(header:GetAttribute("eldo-width"))
	self:SetHeight(header:GetAttribute("eldo-height"))
	self:SetAttribute("*type1", "target")
	self:SetAttribute("*type2", "togglemenu")
	local suffix = header:GetAttribute("eldo-suffix")
	if suffix then self:SetAttribute("unitsuffix", suffix) end
	local clicks = header:GetAttribute("eldo-clickcast")
	if clicks then
		for key, value in gmatch(clicks, "([^\001\002]+)\002([^\001]*)\001") do
			self:SetAttribute(key, value)
		end
	end
	header:CallMethod("InitButton", self:GetName())
]]

local function OnAttributeChanged(button, name, value)
	if name == "unit" then SetUnit(button, value) end
end

local function SetupButton(button, key)
	if allButtons[button] then return end
	allButtons[button] = true
	local info = HEADERS[key]
	button.headerKey = key
	button.unitSuffix = info.suffix
	local db = M:SettingsFor(key)
	CreateVisuals(button, db)
	StyleButton(button, db)
	button:SetScript("OnEvent", OnEvent)
	button:HookScript("OnAttributeChanged", OnAttributeChanged)
	button:HookScript("OnShow", function(self)
		if polledButtons[self] then GFX.WatchPoll() end
		UpdateAll(self, true)
		-- Effects: a member's frame fades in when it appears.
		E:UnitFXFadeIn(self.art, GFX.On("fadeIn"))
	end)
	button:SetScript("OnEnter", UnitFrame_OnEnter)
	button:SetScript("OnLeave", UnitFrame_OnLeave)
	button:HookScript("OnEnter", OnEnterHighlight)
	button:HookScript("OnLeave", OnLeaveHighlight)
	-- Also covers clients where the restricted snippet did not run.
	E:RunOutOfCombat(function()
		button:RegisterForClicks("AnyUp")
		button:SetAttribute("*type1", "target")
		button:SetAttribute("*type2", "togglemenu")
		if info.suffix then button:SetAttribute("unitsuffix", info.suffix) end
		if E.RegisterClickCastFrame then E:RegisterClickCastFrame(button) end
	end)
	SetUnit(button, button:GetAttribute("unit"))
end

local function HeaderButtons(header)
	local list = {}
	for _, child in ipairs({ header:GetChildren() }) do
		if child:IsObjectType("Button") then table.insert(list, child) end
	end
	return list
end

-- Every EldoUI group button, for other modules (click-casting, plugins).
function M.IterateButtons()
	local list = {}
	for button in pairs(allButtons) do list[#list + 1] = button end
	return ipairs(list)
end

function M:GetHeaders()
	return self.headers
end

-- Growth: the first direction fills a column (or row), the second starts
-- the next one. On the header: point / xOffset / yOffset for the first,
-- columnAnchorPoint / columnSpacing for the second.
local DIRECTIONS = {
	DOWN = { point = "TOP", x = 0, y = -1, vertical = true },
	UP = { point = "BOTTOM", x = 0, y = 1, vertical = true },
	RIGHT = { point = "LEFT", x = 1, y = 0, vertical = false },
	LEFT = { point = "RIGHT", x = -1, y = 0, vertical = false },
}

-- The resolved growth of a settings table: directions, the corner the
-- grid starts in, the holder point the header is pinned to (the middle of
-- an edge with "start from the center") and the gaps.
local function Growth(db)
	local first = DIRECTIONS[db.growth] and db.growth or "DOWN"
	local vertical = DIRECTIONS[first].vertical
	local second = db.growth2
	if not DIRECTIONS[second] or DIRECTIONS[second].vertical == vertical then
		second = vertical and "RIGHT" or "DOWN"
	end
	local up = (vertical and first or second) == "UP"
	local left = (vertical and second or first) == "LEFT"
	local corner = (up and "BOTTOM" or "TOP") .. (left and "RIGHT" or "LEFT")
	local anchor = corner
	if db.centered then
		anchor = vertical and (left and "RIGHT" or "LEFT") or (up and "BOTTOM" or "TOP")
	end
	local hGap = db.spacing or 0
	local vGap = db.splitSpacing and (db.spacingY or hGap) or hGap
	return {
		first = first, second = second, vertical = vertical, up = up, left = left,
		point = DIRECTIONS[first].point, x = DIRECTIONS[first].x, y = DIRECTIONS[first].y,
		column = DIRECTIONS[second].point,
		corner = corner, anchor = anchor,
		firstGap = vertical and vGap or hGap, secondGap = vertical and hGap or vGap,
		hGap = hGap, vGap = vGap,
	}
end

---------------------------------------------------------------------------
-- Settings per header
---------------------------------------------------------------------------
local function GroupSize()
	return Plain(GetNumGroupMembers) or 0
end

-- The raid settings for a raid of `count` members: the largest enabled
-- size band it reaches (large raid, mid raid), else "raid". `preview`
-- (test frames) skips the in-a-raid check.
function M:RaidKey(count, preview)
	count = count or GroupSize()
	if preview or IsInRaid() then
		for _, key in ipairs(RAID_BANDS) do
			local band = self.db[key]
			if band.enabled and count >= (band.minMembers or 40) then return key end
		end
	end
	return "raid"
end

function M:SettingsFor(key)
	if key == "raid" then return self.db[self.raidKey or "raid"] end
	return self.db[HEADERS[key].settings or key]
end

-- Is this header switched on? The raid header follows the Raid tab's
-- switch whichever raid settings are in use.
function M:HeaderWanted(key)
	if key == "raid" then return self.db.raid.enabled end
	local db = self:SettingsFor(key)
	return db.enabled and (key ~= "tanktargets" or db.targets) and true or false
end

local function MaxGroups(db)
	return math.max(1, math.min(tonumber(db.maxGroups) or 8, 8))
end

-- Units per column and number of columns for a settings table.
local function Grid(key, db, count)
	if not count then
		if key == "party" then
			count = db.showPlayer and 5 or 4
		elseif key == "tanks" or key == "tanktargets" then
			count = 8
		elseif key == "pets" then
			count = db.inRaid and 40 or 5
		else
			count = MaxGroups(db) * 5
		end
	end
	local per = math.max(1, math.min(db.unitsPerColumn, count))
	local columns = math.ceil(count / per)
	if key ~= "party" then columns = math.min(columns, db.maxColumns or columns) end
	return per, columns
end

local function GridSize(db, per, columns)
	local growth = Growth(db)
	local rows, cols = per, columns
	if not growth.vertical then rows, cols = columns, per end
	return cols * db.width + (cols - 1) * growth.hGap, rows * db.height + (rows - 1) * growth.vGap
end

-- The healer role's bottom-center spot holds a raid only up to its own
-- size; a raid on the Mid or Large raid settings takes the side spot
-- (Core/Roles.lua reads M.raidKey). Re-place the raid when it crosses.
function M:PlaceRaidForSize()
	local large = self.raidKey ~= nil and self.raidKey ~= "raid"
	if self.raidLarge ~= nil and large ~= self.raidLarge and self.holders.raid then
		E:ApplyMover(HOLDERS.raid.mover)
	end
	self.raidLarge = large
end

local function HolderSize(holderKey)
	if holderKey == "raid" then
		local db = M.db[M.raidKey or "raid"]
		return GridSize(db, Grid("raid", db))
	end
	local db = M.db[holderKey]
	local width, height = GridSize(db, Grid(holderKey, db))
	if holderKey == "tanks" and db.targets then width = width * 2 + db.spacing end
	return width, height
end

local SORTS = {
	GROUP = { groupBy = "GROUP", groupingOrder = "1,2,3,4,5,6,7,8", sortMethod = "INDEX" },
	ROLE = { groupBy = "ASSIGNEDROLE", groupingOrder = "TANK,HEALER,DAMAGER,NONE", sortMethod = "INDEX" },
	CLASS = { groupBy = "CLASS", sortMethod = "NAME" },
	NAME = { sortMethod = "NAME" },
	INDEX = { sortMethod = "INDEX" },
}
local TANK_FILTERS = {
	ASSIGNED = "MAINTANK",
	ROLE = "TANK",
	BOTH = "MAINTANK,TANK",
}

local function SortFor(key, db)
	local sort = SORTS[db.sortBy] or SORTS.GROUP
	if key == "party" and sort == SORTS.GROUP then return SORTS.INDEX end
	if sort == SORTS.CLASS then
		return { groupBy = "CLASS", groupingOrder = table.concat(CLASS_SORT_ORDER or {}, ","), sortMethod = "NAME" }
	end
	return sort
end

-- "1,2,3" for the first three raid groups.
local function GroupList(db)
	local list = {}
	for index = 1, MaxGroups(db) do list[index] = tostring(index) end
	return table.concat(list, ",")
end

-- The header's own state driver: which group types show it. A section
-- can replace it with its own macro conditional (advanced).
local function VisibilityFor(key, db)
	local custom = type(db.visibilityMacro) == "string" and strtrim(db.visibilityMacro) or ""
	if custom ~= "" then return custom end
	if key == "party" then
		return db.showSolo and "[group:raid] hide; show" or "[group:raid] hide; [group:party] show; hide"
	elseif key == "raid" then
		return "[group:raid] show; hide"
	elseif key == "tanks" or key == "tanktargets" then
		return db.inParty and "[group] show; hide" or "[group:raid] show; hide"
	elseif key == "pets" then
		if db.inParty and db.inRaid then return "[group] show; hide" end
		if db.inRaid then return "[group:raid] show; hide" end
		return "[group:raid] hide; [group:party] show; hide"
	end
	return "hide"
end

local ownHeaders = setmetatable({}, { __mode = "k" })
local function CreateHeader(key, holder)
	local info = HEADERS[key]
	local template = info.pet and "SecureGroupPetHeaderTemplate" or "SecureGroupHeaderTemplate"
	local name = "EldoUI_" .. key:gsub("^%l", string.upper) .. "Header"
	local header = CreateFrame("Frame", name, holder, template)
	header.eldoKey = key
	header:SetAttribute("template", "SecureUnitButtonTemplate")
	header:SetAttribute("templateType", "Button")
	header:SetAttribute("initialConfigFunction", INITIAL_CONFIG)
	if info.suffix then header:SetAttribute("eldo-suffix", info.suffix) end
	header.InitButton = function(self, buttonName)
		local button = buttonName and _G[buttonName]
		if button then SetupButton(button, self.eldoKey) end
	end
	if E.RegisterClickCastHeader then E:RegisterClickCastHeader(header) end
	ownHeaders[header] = { key = key, parent = holder }
	return header
end

-- Make every button the header can need now, out of combat, so later
-- roster changes in combat only move units around. A negative starting
-- index makes the header lay out empty slots; it is put back right away.
local function PrecreateButtons(header, key, db)
	local per, columns = Grid(key, db)
	local count = math.min(per * columns, HEADERS[key].max)
	if header:GetAttribute("child" .. count) then return end
	local wasShown = header:IsShown()
	pcall(function()
		header:Show()
		header:SetAttribute("startingIndex", -(count - 1))
		header:SetAttribute("startingIndex", 1)
	end)
	if not wasShown then header:Hide() end
end

-- Out of combat only: one complete configuration reaches the native header.
local configuringHeaders = {}
local function ConfigureHeader(header, key, db)
	assert(not InCombatLockdown() and not configuringHeaders[header], "Group frame configuration is busy")
	local owner = ownHeaders[header]
	assert(owner and owner.key == key and owner.parent == header:GetParent(), "Group header ownership changed")
	local database, settings, profile, modules, active = E.db, M.db, E.profileName, E.modules, M.active
	local registry, parent, init = M.headers, header:GetParent(), header.InitButton
	local shown, previousIgnore = header:IsShown(), header:GetAttribute("_ignore")
	assert(not issecretvalue(shown) and type(shown) == "boolean" and not issecretvalue(previousIgnore)
		and not previousIgnore, "Group header is already being configured")
	local expectedShown, expectedIgnore = shown, previousIgnore
	local fields = { "enabled", "width", "height", "spacing", "spacingY", "splitSpacing", "growth", "growth2", "centered",
		"unitsPerColumn", "maxColumns", "maxGroups", "sortDir", "showSolo", "showPlayer", "inParty", "inRaid", "source", "assists", "sortBy", "targets" }
	local saved, engine, fallback = {}, settings.engine, M.fallback
	for index = 1, #fields do
		local value = db[fields[index]]
		assert(not issecretvalue(value) and type(value) ~= "table", "Opaque group frame layout setting")
		saved[index] = value
	end
	local function SameSettings()
		if settings.engine ~= engine or M.fallback ~= fallback then return false end
		for index = 1, #fields do
			local value = db[fields[index]]
			if issecretvalue(value) or value ~= saved[index] then return false end
		end
		return true
	end
	local scripts, methods = {}, { set = header.SetAttribute, hide = header.Hide, show = header.Show }
	for _, script in ipairs({ "OnAttributeChanged", "OnShow", "OnHide" }) do scripts[script] = header:GetScript(script) end
	local function ReadPoints(frame)
		local points = {}
		for index = 1, frame:GetNumPoints() do points[index] = { frame:GetPoint(index) } end
		return points
	end
	local function SamePoints(frame, points)
		if frame:GetNumPoints() ~= #points then return false end
		for index = 1, #points do
			local p, relative, rp, x, y = frame:GetPoint(index)
			local expected = points[index]
			if issecretvalue(p) or issecretvalue(relative) or issecretvalue(rp) or issecretvalue(x) or issecretvalue(y)
				or p ~= expected[1] or relative ~= expected[2] or rp ~= expected[3] or x ~= expected[4] or y ~= expected[5] then return false end
		end
		return true
	end
	-- A button the header made whose setup callback did not run is set up
	-- here (out of combat, see the first assert). Only the header fills its
	-- child slots, so anything else is still refused below.
	local function Adopt(child)
		if child and not allButtons[child] and child:GetParent() == header and child:IsObjectType("Button") then
			SetupButton(child, key)
			child:SetSize(db.width, db.height)
		end
	end
	local buttons, slots, anchors = {}, {}, {}
	local headerPoints = ReadPoints(header)
	for index = 1, HEADERS[key].max do
		local child = header:GetAttribute("child" .. index)
		Adopt(child)
		if child then
			assert(allButtons[child] and child.headerKey == key and child:GetParent() == header, "Unknown group child")
			buttons[#buttons + 1] = child;slots[child] = index;anchors[child] = ReadPoints(child)
		end
	end
	-- A button this header already set up keeps its place even without a
	-- child slot, so the module can be turned off and on again.
	for _, child in ipairs({ header:GetChildren() }) do
		if slots[child] == nil then
			assert(allButtons[child] and child.headerKey == key and child:GetParent() == header, "Unknown group child")
			buttons[#buttons + 1] = child;slots[child] = false;anchors[child] = ReadPoints(child)
		end
	end
	local childCount, creatingChildren = header:GetNumChildren(), false
	assert(childCount == #buttons, "Unknown group child")
	local function AdmitChildren()
		for index = 1, HEADERS[key].max do
			local child = header:GetAttribute("child" .. index)
			if child and slots[child] == false then
				slots[child] = index
			elseif child and not slots[child] then
				Adopt(child)
				assert(allButtons[child] and child.headerKey == key and child:GetParent() == header, "Unknown group child")
				buttons[#buttons + 1] = child;slots[child] = index
			end
		end
		childCount = header:GetNumChildren()
		assert(childCount == #buttons, "Unknown group child")
	end
	local function HeaderIdentity()
		return E.modules == modules and modules.GroupFrames == M and M.headers == registry and registry[key] == header
			and header.eldoKey == key and header:GetParent() == parent and header.InitButton == init
			and header:GetScript("OnAttributeChanged") == scripts.OnAttributeChanged
			and header:GetScript("OnShow") == scripts.OnShow and header:GetScript("OnHide") == scripts.OnHide
	end
	local function HeaderOwned()
		return HeaderIdentity() and header.SetAttribute == methods.set and header.Hide == methods.hide and header.Show == methods.show
	end
	local cleared, checkingEmpty, hiddenByUs = {}, true, false
	local function Check()
		assert(not InCombatLockdown() and HeaderOwned() and E.db == database and M.db == settings
			and M.active == active and E.profileName == profile and M:SettingsFor(key) == db and SameSettings(), "Group frame configuration ownership changed")
		assert(header:IsShown() == expectedShown and header:GetAttribute("_ignore") == expectedIgnore,
			"Group header visibility or batch ownership changed")
		assert(SamePoints(header, headerPoints), "Group header anchor ownership changed")
		for child, index in pairs(slots) do
			assert((not index or header:GetAttribute("child" .. index) == child) and child:GetParent() == header
				and allButtons[child] and child.headerKey == key, "Group child ownership changed")
			if checkingEmpty then
				assert(cleared[child] and child:GetNumPoints() == 0 or not cleared[child] and anchors[child]
					and SamePoints(child, anchors[child]), "Group frame anchor ownership changed")
			end
		end
		assert(creatingChildren or header:GetNumChildren() == childCount, "Unknown group child")
	end
	local function Set(name, value)
		header:SetAttribute(name, value);Check()
	end
	Check()
	configuringHeaders[header] = true
	local ok, failure = pcall(function()
		header:SetAttribute("_ignore", "EldoUIGroupLayout");expectedIgnore = "EldoUIGroupLayout";Check()
		local per, columns = Grid(key, db)
		local growth = Growth(db)

		for _, button in ipairs(buttons) do
			Check()
			button:SetSize(db.width, db.height);Check()
			StyleButton(button, db);Check()
			if button.unit then UpdateAll(button);Check() end
			UpdatePrivateAnchors(button);Check()
		end

		Set("eldo-width", db.width)
		Set("eldo-height", db.height)
		Set("point", growth.point)
		Set("xOffset", growth.x * growth.firstGap)
		Set("yOffset", growth.y * growth.firstGap)
		Set("columnSpacing", growth.secondGap)
		Set("columnAnchorPoint", growth.column)
		Set("unitsPerColumn", per)
		Set("maxColumns", columns)
		Set("sortDir", db.sortDir == "DESC" and "DESC" or "ASC")
		Set("showSolo", key == "party" and db.showSolo or false)

		if key == "party" then
			Set("showParty", true)
			Set("showRaid", false)
			Set("showPlayer", db.showPlayer or db.showSolo)
		elseif key == "raid" then
			Set("showParty", false)
			Set("showRaid", true)
			Set("showPlayer", true)
			Set("groupFilter", GroupList(db))
		elseif key == "tanks" or key == "tanktargets" then
			local filter = TANK_FILTERS[db.source] or TANK_FILTERS.ASSIGNED
			if db.assists and db.source ~= "ROLE" then filter = filter .. ",MAINASSIST" end
			Set("showParty", db.inParty and true or false)
			Set("showRaid", true)
			Set("showPlayer", true)
			Set("roleFilter", filter)
			Set("groupFilter", nil)
		elseif key == "pets" then
			Set("showParty", db.inParty and true or false)
			Set("showRaid", db.inRaid and true or false)
			Set("showPlayer", true)
			Set("useOwnerUnit", false)
			Set("filterOnPet", true)
		end
		if key == "party" or key == "raid" or key == "pets" then
			local sort = SortFor(key, db)
			Set("groupBy", sort.groupBy)
			Set("groupingOrder", sort.groupingOrder)
			Set("sortMethod", sort.sortMethod)
		else
			Set("sortMethod", "INDEX")
		end

		headerPoints = {}
		header:ClearAllPoints();Check()
		if key == "tanktargets" then
			-- The targets column sits right of the tanks.
			headerPoints[1] = { "TOPLEFT", parent, "TOPLEFT", db.width + db.spacing, 0 }
			header:SetPoint("TOPLEFT", parent, "TOPLEFT", db.width + db.spacing, 0);Check()
		else
			headerPoints[1] = { growth.anchor, parent, growth.anchor, 0, 0 }
			header:SetPoint(growth.anchor, parent, growth.anchor);Check()
		end
		-- Surviving buttons can still carry the other axis of an old grid.
		-- Clear them only after every current attribute has been installed.
		for _, button in ipairs(buttons) do
			Check()
			cleared[button] = true
			button:ClearAllPoints()
			Check()
			assert(button:GetNumPoints() == 0, "Group frame anchor ownership changed")
		end
		header:SetAttribute("_ignore", previousIgnore);expectedIgnore = previousIgnore;Check()
		if shown then
			hiddenByUs, expectedShown = true, false
			header:Hide();Check()
			checkingEmpty, expectedShown, creatingChildren = false, true, true
			header:Show();AdmitChildren();creatingChildren = false;Check()
		end
		checkingEmpty = false
		creatingChildren = true
		PrecreateButtons(header, key, db)
		AdmitChildren();creatingChildren = false
		Check()
	end)
	-- Release our batch independently of the callback that failed. A foreign
	-- header, profile or visibility owner never gets another placement write.
	local released, releaseFailure = pcall(function()
		if HeaderIdentity() and header:GetAttribute("_ignore") == "EldoUIGroupLayout" then
			methods.set(header, "_ignore", previousIgnore)
			expectedIgnore = previousIgnore
			assert(header:GetAttribute("_ignore") == previousIgnore, "Group header batch could not be released")
		end
	end)
	local restored, restoreFailure = pcall(function()
		if not ok and shown and HeaderOwned() and E.db == database and M.db == settings
			and M.active == active and E.profileName == profile and M:SettingsFor(key) == db and SameSettings()
			and header:GetAttribute("_ignore") == previousIgnore and hiddenByUs and not header:IsShown() then
			expectedShown, checkingEmpty = false, true
			Check()
			header:Show()
		end
	end)
	configuringHeaders[header] = nil
	if not ok then
		error(tostring(failure) .. (not released and ("; " .. tostring(releaseFailure)) or "")
			.. (not restored and ("; " .. tostring(restoreFailure)) or ""), 0)
	end
	if not released then error(releaseFailure, 0) end
	if not restored then error(restoreFailure, 0) end
end

---------------------------------------------------------------------------
-- Engine
---------------------------------------------------------------------------
-- "eldo", "skin" or "blizzard": what is actually in use right now.
function M:GetEngine()
	local engine = self.db.engine
	if engine == "blizzard" or engine == "skin" then return engine end
	if engine == "auto" and self.fallback then return "skin" end
	return "eldo"
end

function M:Build()
	self.raidKey = self:RaidKey()
	for _, holderKey in ipairs(HOLDER_ORDER) do
		local info = HOLDERS[holderKey]
		local holder = self.holders[holderKey]
		if not holder then
			holder = CreateFrame("Frame", "EldoUI_" .. info.title:gsub("[^%a]", "") .. "Holder", UIParent)
			holder:SetSize(HolderSize(holderKey))
			self.holders[holderKey] = holder
			holder.moverName = info.mover
			E:CreateMover(holder, info.mover, L[info.title], info.point, { sample = info.sample })
		else
			holder:SetSize(HolderSize(holderKey))
		end
	end
	self:PlaceRaidForSize()
	-- A pets grid wider than the free band beside the raid takes the layout's
	-- wide spot instead (Core/Layout.lua widePoints), and the main
	-- tanks may move with it. The main tanks also go beside a raid that is
	-- taller than the band under it (a raid style with big tiles). Re-place
	-- them when a size crosses the layout's limit. Build runs out of combat;
	-- ApplyMover waits anyway.
	local petsWide = E:IsLayoutPointWide(HOLDERS.pets.mover)
	if petsWide ~= self.petsWide then
		if self.petsWide ~= nil then
			E:ApplyMover(HOLDERS.pets.mover)
			E:ApplyMover(HOLDERS.tanks.mover)
		end
		self.petsWide = petsWide
	end
	local tanksWide = E:IsLayoutPointWide(HOLDERS.tanks.mover)
	-- Turning the main tanks on or off decides which of tanks and pets keeps
	-- a shared spot (Core/Layout.lua), so both are placed again.
	local tanksOn = self.db.tanks.enabled and true or false
	if self.tanksOn ~= nil and tanksOn ~= self.tanksOn then
		E:ApplyMover(HOLDERS.tanks.mover)
		E:ApplyMover(HOLDERS.pets.mover)
	end
	self.tanksOn = tanksOn
	if tanksWide ~= self.tanksWide then
		if self.tanksWide ~= nil then
			E:ApplyMover(HOLDERS.tanks.mover)
			-- The pets go beside the tanks when both want the same spot.
			E:ApplyMover(HOLDERS.pets.mover)
		end
		self.tanksWide = tanksWide
	end
	-- The party takes its wide spot the same way after a style change.
	local partyWide = E:IsLayoutPointWide(HOLDERS.party.mover)
	if partyWide ~= self.partyWide then
		if self.partyWide ~= nil then E:ApplyMover(HOLDERS.party.mover) end
		self.partyWide = partyWide
	end
	if self:GetEngine() ~= "eldo" then return end
	for _, key in ipairs(HEADER_ORDER) do
		if self:HeaderWanted(key) then
			local holder = self.holders[HEADERS[key].holder]
			self.headers[key] = self.headers[key] or CreateHeader(key, holder)
			ConfigureHeader(self.headers[key], key, self:SettingsFor(key))
		end
	end
end

-- Show the engine in use and hide the other one. Out of combat only.
function M:Apply()
	local useEldo = self:GetEngine() == "eldo"
	for _, key in ipairs(HEADER_ORDER) do
		local header = self.headers[key]
		if header then
			if useEldo and self:HeaderWanted(key) then
				RegisterStateDriver(header, "visibility", VisibilityFor(key, self:SettingsFor(key)))
			else
				UnregisterStateDriver(header, "visibility")
				header:Hide()
			end
		end
	end
	if useEldo then
		ResumeButtons()
	else
		for button in pairs(activeButtons) do ReleaseButton(button) end
	end
	self:ApplyFaders()
	self:ApplyBlizzard()
	self:ScheduleCheck()
end

-- Each holder fades by its section's visibility rules (Core/Visibility.lua).
-- The holder carries secure buttons, so a real hide goes through a state
-- driver (registered out of combat by the engine); alpha works anywhere.
-- The test frames and move mode keep it shown.
function M:ApplyFaders()
	local useEldo = self:GetEngine() == "eldo"
	for holderKey, holder in pairs(self.holders) do
		local db = self.db[holderKey]
		local block = db and db.visibility
		if useEldo and HOLDER_SECTIONS[holderKey] and type(block) == "table" then
			E:AttachVisibility(holder, block, {
				secure = true,
				forceShow = function() return self.testing or E:IsMoveMode() end,
			})
		elseif E:IsVisibilityAttached(holder) then
			E:DetachVisibility(holder)
		end
	end
end

-- Auto mode: once in a group, make sure the header really made buttons.
function M:ScheduleCheck()
	if self.db.engine ~= "auto" or self.fallback or self.verified or self.checkPending then return end
	if not IsInGroup() or InCombatLockdown() then return end
	self.checkPending = true
	C_Timer.After(2, function() self:CheckHeaders(1) end)
end

function M:CheckHeaders(attempt)
	self.checkPending = false
	if not self.active or self.db.engine ~= "auto" or self.fallback or self.verified then return end
	if not IsInGroup() or InCombatLockdown() then return end -- retried on roster change / combat end
	local section = IsInRaid() and "raid" or "party"
	if not self.db[section].enabled then return end
	local header = self.headers[section]
	-- A header its visibility rule hides (only in combat, hidden while
	-- mounted, resting ...) makes no buttons until it shows, which says
	-- nothing about this client: the next roster change or combat end
	-- checks again.
	if header and not header:IsVisible() then return end
	local visible = 0
	if header then
		for _, button in ipairs(HeaderButtons(header)) do
			if button:IsVisible() and button:GetAttribute("unit") then visible = visible + 1 end
		end
	end
	if visible > 0 then
		self.verified = true
		return
	end
	if attempt < 2 then
		-- One more try a little later, in case the roster was still loading.
		self.checkPending = true
		C_Timer.After(3, function() self:CheckHeaders(attempt + 1) end)
		return
	end
	self.fallback = true
	if self.db.fallbackNotice then
		self:Print(L["Secure group headers did not create any frames on this client. Using Blizzard's party and raid frames instead."])
	end
	E:RunOutOfCombat(function() self:Apply() end)
end

---------------------------------------------------------------------------
-- Test frames: plain, non-secure frames with sample data, for placing and
-- sizing the frames while solo.
---------------------------------------------------------------------------
local SAMPLES = {
	{ "Eldorin", "WARRIOR", "TANK", 0.86, nil, "Ashvale" },
	{ "Lumessa", "PRIEST", "HEALER", 1, nil, "Brightwater" },
	{ "Kaelthir", "MAGE", "DAMAGER", 0.54, nil, "Emberfall" },
	{ "Brannok", "HUNTER", "DAMAGER", 0.72 },
	{ "Sylvara", "DRUID", "HEALER", 0.31, nil, "Mossbrook" },
	{ "Tharok", "SHAMAN", "DAMAGER", 0, DEAD or Key("Dead") },
	{ "Vesperine", "WARLOCK", "DAMAGER", 0.93 },
	{ "Aldric", "PALADIN", "TANK", 0.65, nil, "Stonehelm" },
	{ "Nyx", "ROGUE", "DAMAGER", 1 },
	{ "Morwenna", "PRIEST", "HEALER", 0.78 },
	{ "Grukk", "WARRIOR", "DAMAGER", 0.44 },
	{ "Faelan", "HUNTER", "DAMAGER", 1, PLAYER_OFFLINE or Key("Offline") },
	{ "Isolde", "MAGE", "DAMAGER", 0.88, nil, "Frostmere" },
	{ "Oakheart", "DRUID", "TANK", 0.97 },
	{ "Seraphel", "PALADIN", "HEALER", 0.59 },
}
local PET_SAMPLES = {
	{ Key("Wolf"), "HUNTER", nil, 0.9 }, { Key("Imp"), "WARLOCK", nil, 1 }, { Key("Voidwalker"), "WARLOCK", nil, 0.6 },
	{ Key("Cat"), "HUNTER", nil, 0.75 }, { Key("Water Elemental"), "MAGE", nil, 0.5 },
}
local TARGET_SAMPLES = { { Key("Training Dummy"), nil, nil, 0.62 }, { Key("Training Dummy"), nil, nil, 0.81 } }
local TEST_COUNTS = { party = 5, raid10 = 10, raid20 = 20, raid25 = 25, raid40 = 40 }
local SAMPLE_ICONS = {
	buff = { "Interface\\Icons\\Spell_Holy_Renew", "Interface\\Icons\\Spell_Nature_Rejuvenation", "Interface\\Icons\\Spell_Nature_ResistNature" },
	debuff = { "Interface\\Icons\\Spell_Shadow_ShadowWordPain", "Interface\\Icons\\Spell_Fire_Immolation", "Interface\\Icons\\Spell_Nature_Poisoncleansingtotem" },
	defensive = "Interface\\Icons\\Spell_Holy_PowerWordShield",
}

local function SampleIcons(icons, list, count)
	for index, icon in ipairs(icons) do
		if index <= count then
			icon.texture:SetTexture(list[(index - 1) % #list + 1])
			icon.cooldown:Clear()
			icon.count:SetText(index == 2 and "2" or "")
			icon:Show()
		else
			icon:Hide()
		end
	end
end

-- Sample text for a test frame's slot. Custom tag strings are shown with
-- your own character's values.
local SAMPLE_MAX_HEALTH = 24000
local function FakeText(db, slot, sample)
	local block = db.texts and db.texts[slot]
	local preset = block and block.preset or "off"
	local first, _, _, health, status = unpack(sample)
	-- Sample pet and target names and the status words are kept in English.
	first, status = E:Translate(first), E:Translate(status)
	-- Sample surname (6th field) in the group frames' Name format.
	local name = sample[6] and E:FormatName(first, sample[6], E:NameFormat("GroupFrames")) or first
	local current = math.floor(health * SAMPLE_MAX_HEALTH)
	if preset == "off" then return "" end
	if preset == "name" then return ShortName(name, db.nameLength) end
	if preset == "namelevel" then return "60 " .. ShortName(name, db.nameLength) end
	if preset == "healthpercent" then return ("%d%%"):format(math.floor(health * 100 + 0.5)) end
	if preset == "healthcurrent" then return E:FormatNumber(current) end
	if preset == "healthdeficit" then
		return health < 1 and ("-" .. E:FormatNumber(SAMPLE_MAX_HEALTH - current)) or ""
	end
	if preset == "healthcurrentmax" then return E:FormatNumber(current) .. " / " .. E:FormatNumber(SAMPLE_MAX_HEALTH) end
	if preset == "healthcurrentpercent" then
		return ("%s | %d%%"):format(E:FormatNumber(current), math.floor(health * 100 + 0.5))
	end
	if preset == "powerpercent" then return "80%" end
	if preset == "status" then return status or "" end
	local ok, text = pcall(E.FormatTag, E, E:TagForSlot(block), "player", "GroupFrames")
	if ok and type(text) == "string" and not IsSecret(text) then return text end
	return ""
end

local function UpdateFake(button, sample, index, db)
	local name, class, role, health, status = unpack(sample)
	status = E:Translate(status)
	button.isHealer = role == "HEALER"
	button.barsKey = nil
	LayoutBars(button)
	button.health:SetMinMaxValues(0, 1)
	button.health:SetValue(health)
	button.statusText:SetText(status or "")
	button.statusText:SetShown(status ~= nil)
	button.healthText:SetShown(status == nil)
	-- The sample's state color (General > Colors, Status) and the same
	-- gradient curve the real frames use.
	local deadLook = GFX.On("deadLook")
	local stateKey = status and (status == (DEAD or L["Dead"]) and "dead" or "offline") or nil
	local painted, light = false, nil
	if stateKey and deadLook then
		local r, g, b = E:GetStatusColor(stateKey)
		button.health:SetStatusBarColor(r, g, b)
		painted, light = true, E:IsLightFill(r, g, b)
	elseif db.colorByValue and not status then
		painted = E:PaintColorResult(button.health, E:UnitCurveEval("healthGradient", health), "SetStatusBarColor")
		light = painted or nil
	end
	if not painted then
		local r, g, b
		if db.classColor and class then
			r, g, b = ClassRGB(class)
		elseif db.classColor then
			r, g, b = E:GetReactionColor(5)
		else
			r, g, b = E.UnitGraphics.DarkFillColor()
		end
		if db.classColor then button.health:SetStatusBarColor(r, g, b) else DarkHealth(button.health) end
		light = E:IsLightFill(r, g, b)
	end
	FitTextsToFill(button, light)
	PaintWell(button, nil, class)
	button.healthText:SetTextColor(1, 1, 1)
	button.nameText:SetText(FakeText(db, "name", sample))
	button.healthText:SetText(FakeText(db, "health", sample))
	button.extraText:SetText(FakeText(db, "extra", sample))
	if db.classColorName and class then button.nameText:SetTextColor(ClassRGB(class)) else button.nameText:SetTextColor(1, 1, 1) end

	button.power:SetMinMaxValues(0, 1)
	button.power:SetValue(0.8)
	local mana = E:PowerColorObject("MANA")
	if role == "TANK" and class == "WARRIOR" then mana = E:PowerColorObject("RAGE") end
	if mana then button.power:SetStatusBarColor(mana.r, mana.g, mana.b) else button.power:SetStatusBarColor(E:GetPowerColor("MANA")) end

	-- Heal prediction and absorbs on a few members.
	local p = button.prediction
	local prediction = M.db.prediction
	local function Sample(bar, on, value)
		bar:SetShown(on and value > 0 and not status)
		bar:SetMinMaxValues(0, 1)
		bar:SetValue(value)
	end
	Sample(p.other, prediction.heals, index % 4 == 3 and 0.18 or 0)
	Sample(p.mine, prediction.heals, index % 4 == 3 and 0.1 or 0)
	Sample(p.absorb, prediction.absorbs, index % 5 == 2 and 0.12 or 0)
	Sample(p.healAbsorb, prediction.healAbsorbs, index % 6 == 5 and 0.15 or 0)
	p.overAbsorb:Hide()

	-- Portraits show your own model or picture; the class icon the sample's.
	if button.portraitShown then
		if db.portrait == "CLASS" then
			if button.model then button.model:Hide() end
			button.portrait:Show()
			if not (class and SetClassPortrait(button.portrait, class)) then
				button.portrait:SetTexture(E.media.flat)
				button.portrait:SetTexCoord(0, 1, 0, 1)
			end
			button.portrait:SetDesaturated(stateKey ~= nil and deadLook and db.portraitDeadGrey ~= false)
		else
			E.Portrait:Update(button, "player", GFX.PortraitOpts(button, true), true)
		end
	end
	GFX.UpdateBadge(button, "player")

	local indicators = M.db.indicators
	if db.roleIcon then SetRoleTexture(button.roleIcon, role) else button.roleIcon:Hide() end
	button.leaderIcon:SetTexture(GROUP_ICONS.leader)
	button.leaderIcon:SetShown(indicators.leader and index == 1)
	button.tankIcon:SetTexture(GROUP_ICONS.maintank)
	button.tankIcon:SetShown(indicators.mainTank and role == "TANK" and index > 5)
	LayoutTopIcons(button)
	button.raidIcon:SetShown(indicators.raidTarget and index == 1)
	if index == 1 then button.raidIcon:SetTexCoord(0, 0.25, 0, 0.25) end
	button.readyIcon:Hide()
	local statusAtlas = index == 6 and STATUS_ATLAS.resurrect or (index == 9 and STATUS_ATLAS.summonPending) or nil
	if statusAtlas and AtlasExists(statusAtlas) and ((index == 6 and indicators.resurrect) or (index == 9 and indicators.summon)) then
		button.statusIcon:SetAtlas(statusAtlas)
		button.statusIcon:Show()
	else
		button.statusIcon:Hide()
	end
	-- Threat border sample on the first frame: the "tanking" color, from
	-- the same curve and gate as the real frames.
	local threat = GFX.On("threat")
	if threat and index == 1 then
		button.threatGate:SetLook("BORDER", { thickness = 2 })
		button.threatGate:Paint(E:UnitCurveEval("threat", 3, { role = "dps" }))
	else
		button.threatGate:Clear()
	end
	button.lowHealthGate:Clear()
	button.lowPowerGate:Clear()
	E.FrameFX.Pulse(button.statusIcon, statusAtlas ~= nil and button.statusIcon:IsShown() and GFX.On("statusPulse") and true or false)
	button.targetBorder:SetShown(indicators.target and index == 3)

	local showAuras = db.auras ~= false
	local debuffs, buffs, defensives = db.debuffs, db.buffs, db.defensives
	SampleIcons(button.debuffIcons, SAMPLE_ICONS.debuff,
		(showAuras and debuffs.enabled and index % 3 == 2) and math.min(debuffs.max, 2) or 0)
	SampleIcons(button.buffIcons, SAMPLE_ICONS.buff,
		(showAuras and buffs.enabled and role ~= nil and index % 2 == 1) and math.min(buffs.max, 2) or 0)
	if buffs.style == "SQUARES" then
		local c = buffs.squareColor
		for _, icon in ipairs(button.buffIcons) do
			icon.texture:SetTexture(E.media.flat)
			icon.texture:SetVertexColor(c[1], c[2], c[3], 1)
			icon.count:SetText("")
		end
	else
		for _, icon in ipairs(button.buffIcons) do icon.texture:SetVertexColor(1, 1, 1, 1) end
	end
	ShowMissingBuff(button.missingBuff, showAuras and buffs.missing and index % 5 == 4 or nil, buffs.missingColor)
	-- No defensive icon yet: this section's auras have been off so far.
	local defensiveIcon = button.defensiveIcon
	if defensiveIcon and showAuras and defensives.enabled and role == "TANK" then
		defensiveIcon.texture:SetTexture(SAMPLE_ICONS.defensive)
		defensiveIcon.count:SetText("")
		defensiveIcon:Show()
	elseif defensiveIcon then
		defensiveIcon:Hide()
	end
	local dispel = M.db.dispel
	local dispelled = showAuras and dispel.enabled and index % 3 == 2
	if dispelled and dispel.style ~= "GLOW" then
		local color = DISPEL_COLORS[(index % 4) + 1] or FALLBACK_HIGHLIGHT
		button.highlight:SetBackdropBorderColor(color[1], color[2], color[3], 1)
		local aw = E.AuraWidget
		local symbol = aw and aw.DispelSymbolsOn() and aw.DispelSymbols()[M.SAMPLE_DISPEL[(index % 4) + 1]] or ""
		button.highlight.symbol:SetText(symbol)
		button.highlight:Show()
	else
		button.highlight:Hide()
	end
	if dispelled and dispel.style ~= "BORDER" then
		E:ShowUserGlow(button.highlightHolder, "groupDispel")
	else
		E:HideGlow(button.highlightHolder)
	end
	if showAuras and M.db.bossGlow and index == 4 then
		E:ShowUserGlow(button, "groupBoss")
	else
		E:HideGlow(button)
	end
	button.art:SetAlpha(index % 7 == 4 and (db.rangeAlpha or 0.4) or 1)
end

local function FakeFrames(holderKey)
	M.fakes[holderKey] = M.fakes[holderKey] or {}
	return M.fakes[holderKey]
end

-- Place `count` fake frames in a grid like the header would.
local function LayoutFakeGrid(fakes, first, holder, db, count, per, samples, offsetX)
	local growth = Growth(db)
	local stepX, stepY = db.width + growth.hGap, db.height + growth.vGap
	local signX, signY = growth.left and -1 or 1, growth.up and 1 or -1
	local shiftX, shiftY = 0, 0
	if db.centered and not offsetX then
		-- The first row or column sits in the middle of its edge.
		local width, height = holder:GetSize()
		local placed = math.min(count, per)
		if growth.vertical then
			shiftY = signY * (height - (placed * stepY - growth.vGap)) / 2
		else
			shiftX = signX * (width - (placed * stepX - growth.hGap)) / 2
		end
	end
	for index = 1, count do
		local slot = first + index - 1
		local fake = fakes[slot]
		if not fake then
			fake = CreateFrame("Frame", nil, UIParent)
			CreateVisuals(fake, db)
			E:AddMoverContent(holder.moverName, fake)
			fake:SetFrameStrata("MEDIUM")
			fakes[slot] = fake
		end
		fake:SetSize(db.width, db.height)
		StyleButton(fake, db)
		local column, row = math.floor((index - 1) / per), (index - 1) % per
		local x, y
		if growth.vertical then
			x, y = column * stepX * signX, row * stepY * signY
		else
			x, y = row * stepX * signX, column * stepY * signY
		end
		fake:ClearAllPoints()
		fake:SetPoint(growth.corner, holder, growth.corner, x + shiftX + (offsetX or 0), y + shiftY)
		UpdateFake(fake, samples[(index - 1) % #samples + 1], index, db)
		fake:Show()
	end
	return first + count
end

local function HideFakes()
	for _, fakes in pairs(M.fakes) do
		for _, fake in ipairs(fakes) do fake:Hide() end
	end
end

-- One group holder filled with `count` test frames.
local function LayoutTestGroup(key, count)
	local db
	if key == "raid" then
		db = M.db[M:RaidKey(count, true)]
	else
		db = M.db.party
		if not db.showPlayer then count = math.min(count, 4) end
	end
	local per, columns = Grid(key, db, count)
	count = math.min(count, per * columns)
	-- Show the test grid in the holder size it will have.
	if key == "raid" then
		M.raidKey = M:RaidKey(count, true)
		M.holders.raid:SetSize(HolderSize("raid"))
		M:PlaceRaidForSize()
	end
	LayoutFakeGrid(FakeFrames(key), 1, M.holders[key], db, count, per, SAMPLES)
end

function M:LayoutTest()
	HideFakes()
	local size = self.db.testSize
	local count = TEST_COUNTS[size] or 5
	local key = count > 5 and "raid" or "party"
	-- Move mode's test frames fill every group holder at once (the party,
	-- a raid of the test size or of 20, the main tanks and the pets), so
	-- each one can be placed with the others in view.
	local all = self.testAll
	if all then
		LayoutTestGroup("party", 5)
		LayoutTestGroup("raid", key == "raid" and count or TEST_COUNTS.raid20)
	else
		LayoutTestGroup(key, count)
	end

	local tanks = self.db.tanks
	if tanks.enabled and (all or key == "raid") then
		local tankSamples = { SAMPLES[1], SAMPLES[8] }
		local fakes = FakeFrames("tanks")
		local nextSlot = LayoutFakeGrid(fakes, 1, self.holders.tanks, tanks, 2, 8, tankSamples)
		if tanks.targets then
			LayoutFakeGrid(fakes, nextSlot, self.holders.tanks, tanks, 2, 8, TARGET_SAMPLES, tanks.width + tanks.spacing)
		end
	end
	local pets = self.db.pets
	if pets.enabled and (all or (key == "party" and pets.inParty) or (key == "raid" and pets.inRaid)) then
		local petPer = Grid("pets", pets, #PET_SAMPLES)
		LayoutFakeGrid(FakeFrames("pets"), 1, self.holders.pets, pets, #PET_SAMPLES, petPer, PET_SAMPLES)
	end
end

-- all: every group holder at once (move mode's test frames).
function M:ShowTest(state, all)
	if state and not self.active then
		E:Print(E:ModuleOffHint("GroupFrames"))
		return
	end
	if state and InCombatLockdown() then
		self:Print(L["Test frames can't be shown in combat."])
		return
	end
	self.testing = state and true or false
	self.testAll = state and all and true or nil
	if state then
		if not self.holders.party then self:Build() end
		self:LayoutTest()
		self:Print(L["Showing test frames. Click the button again to hide them, or use /eui move to place them."])
	else
		HideFakes()
		-- Back to the raid settings the real group needs.
		E:RunOutOfCombat(function()
			self.raidKey = self:RaidKey()
			if self.holders.raid then self.holders.raid:SetSize(HolderSize("raid")) end
			self:PlaceRaidForSize()
		end)
	end
end

function M:ToggleTest()
	self:ShowTest(not self.testing)
end

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------
local function UpdateEach(fn)
	for button in pairs(activeButtons) do
		if button.unit then fn(button) end
	end
end

function M:OnRosterUpdate()
	UpdateEach(UpdateAll)
	-- Bigger or smaller raid: switch between the raid and large-raid settings.
	local raidKey = self:RaidKey()
	if raidKey ~= self.raidKey and not self.raidSwitchQueued then
		self.raidSwitchQueued = true
		E:RunOutOfCombat(function()
			self.raidSwitchQueued = false
			-- The module may have been switched off before combat ended.
			if not self.active then return end
			self:Build()
			self:Apply()
		end)
	end
	if not InCombatLockdown() then
		-- Buttons the header made while the snippet could not call back.
		for key, header in pairs(self.headers) do
			for _, button in ipairs(HeaderButtons(header)) do
				if not allButtons[button] then
					SetupButton(button, key)
					local db = self:SettingsFor(key)
					button:SetSize(db.width, db.height)
				end
			end
		end
		self:ApplyBlizzard()
	end
	if self.skinActive and (self.skinActive.party or self.skinActive.raid) then M.inner.SkinAllCompactFrames() end
	self:ScheduleCheck()
end

-- Any section marks missing group buffs (an out-of-combat check).
local function MissingBuffsWanted()
	for _, key in ipairs(SECTION_KEYS) do
		local section = M.db[key]
		if section and section.buffs and section.buffs.missing then return true end
	end
	return false
end

function M:OnInitialize()
	-- v0.5.0 had "blizzard" for Blizzard's frames with the skin toggle on.
	if not self.db.engineMigrated then
		if self.db.engine == "blizzard" and self.db.skinBlizzard then self.db.engine = "skin" end
		self.db.engineMigrated = true
	end
	self:Migrate()
end

function M:OnEnable()
	-- A burst of roster updates (a raid forming, a battleground filling,
	-- members swapping groups) makes one refresh 0.1 s after the first.
	self:RegisterEvent("GROUP_ROSTER_UPDATE", function()
		E:Debounce("GroupFrames:roster", 0.1, function()
			if self.active then self:OnRosterUpdate() end
		end)
	end)
	self:RegisterEvent("PLAYER_ENTERING_WORLD", function() self:OnRosterUpdate() end)
	self:RegisterEvent("PLAYER_ROLES_ASSIGNED", function() UpdateEach(UpdateRole) end)
	self:RegisterEvent("PARTY_LEADER_CHANGED", function() UpdateEach(UpdateGroupIcons) end)
	self:RegisterEvent("RAID_TARGET_UPDATE", function() UpdateEach(UpdateRaidTarget) end)
	self:RegisterEvent("PLAYER_TARGET_CHANGED", function()
		UpdateEach(UpdateTargetBorder)
		if self.db.indicators.aggroSource == "target" then UpdateEach(UpdateThreat) end
	end)
	self:RegisterEvent("READY_CHECK", function() UpdateEach(UpdateReadyCheck) end)
	self:RegisterEvent("READY_CHECK_CONFIRM", function() UpdateEach(UpdateReadyCheck) end)
	self:RegisterEvent("READY_CHECK_FINISHED", function()
		-- The result stays a few seconds, then fades out.
		UpdateEach(function(button)
			local icon = button.readyIcon
			if icon:IsShown() and not icon.holding then
				icon.holding = true
				E.FrameFX.FadeOut(icon, self.db.indicators.readyHold, function() icon.holding = nil end)
			end
		end)
	end)
	self:RegisterEvent("PLAYER_REGEN_DISABLED", function()
		if self.testing then self:ShowTest(false) end
		if MissingBuffsWanted() then UpdateEach(UpdateAuras) end
	end)
	self:RegisterEvent("PLAYER_REGEN_ENABLED", function()
		self:ScheduleCheck()
		if MissingBuffsWanted() then UpdateEach(UpdateAuras) end
	end)

	E:RunOutOfCombat(function()
		if not self.active then return end
		self:Build()
		self:Apply()
		GFX.WatchRange()
		GFX.WatchPoll()
	end)
end

function M:OnDisable()
	self:ShowTest(false)
	E:RunOutOfCombat(function()
		for _, header in pairs(self.headers) do
			UnregisterStateDriver(header, "visibility")
			header:Hide()
		end
		self:RestoreBlizzardAll()
	end)
	for button in pairs(activeButtons) do
		RemovePrivateAnchors(button)
		ReleaseButton(button)
	end
	GFX.StopTicks()
	for button in pairs(allButtons) do
		for _, field in pairs(TEXT_SLOTS) do E:UnbindTag(button[field]) end
		E.Portrait:Release(button)
	end
	E:RunOutOfCombat(function()
		if self.active then return end
		for button in pairs(allButtons) do ReleaseContainers(button) end
	end)
	for _, holder in pairs(self.holders) do
		if E:IsVisibilityAttached(holder) then E:DetachVisibility(holder) end
	end
end

-- General > Glows changed: glow slots whose baked look no longer matches
-- are rebuilt (their signature holds the look, see GlowLook).
function M:RefreshGlowSlots()
	-- With another frame source the EldoUI buttons are hidden; the header
	-- styles them again (containers included) when EldoUI's comes back.
	if not self.active or self:GetEngine() ~= "eldo" then return end
	E:RunOutOfCombat(function()
		for button in pairs(allButtons) do ApplyContainers(button) end
	end)
end
if E.RefreshGlows then
	hooksecurefunc(E, "RefreshGlows", function() M:RefreshGlowSlots() end)
end

function M:OnProfileChanged()
	self:Migrate()
	local frames = E:GetModule("UnitFrames")
	if frames and frames.SyncAllFrames then frames.SyncAllFrames(false) end
	if not self.active then return end
	if self.db.engine ~= "auto" then self.fallback, self.verified = nil, nil end
	E:RunOutOfCombat(function()
		if not self.active then return end
		self:Build()
		self:Apply()
		if self.testing then self:LayoutTest() end
	end)
end

E:AddCommand("grouptest", "[party | raid10 | raid20 | raid25 | raid40]  show or hide test party and raid frames", function(arg)
	arg = (arg or ""):lower()
	if TEST_COUNTS[arg] then
		M.db.testSize = arg
		M:ShowTest(true)
	else
		M:ToggleTest()
	end
end, "Layout & frames")

-- Helpers and constants the split files (Modules/GroupFrames/*.lua) share
-- with this one, read through the module table: they load right after it.
M.inner = {
	MAX_ICONS = MAX_ICONS, MAX_PRIVATE = MAX_PRIVATE,
	SECTION_KEYS = SECTION_KEYS, SECTION_TITLES = SECTION_TITLES, HOLDER_SECTIONS = HOLDER_SECTIONS,
	NAME_PRESETS = NAME_PRESETS, HEALTH_PRESETS = HEALTH_PRESETS, EXTRA_PRESETS = EXTRA_PRESETS,
	TextSlot = TextSlot,
}
