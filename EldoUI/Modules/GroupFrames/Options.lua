-- EldoUI Group Frames options page and style presets.
-- Loaded right after Modules/GroupFrames/Blizzard.lua; adds to the same
-- module, before anything reads its options.
--
--   Copy settings   "Copy settings from" between sections
--   Options         every tab of the Group Frames page (M.options)
--   Style presets   the Group Frames styles (E:RegisterStyles)
--
-- The constants it shares with Modules/GroupFrames.lua come through the
-- module table (M.inner), set at the end of that file.
local _, E = ...
local L = E.L
local M = E:GetModule("GroupFrames")
if not M then return end

local inner = M.inner
local MAX_ICONS, MAX_PRIVATE = inner.MAX_ICONS, inner.MAX_PRIVATE
local SECTION_KEYS, SECTION_TITLES, HOLDER_SECTIONS = inner.SECTION_KEYS, inner.SECTION_TITLES, inner.HOLDER_SECTIONS
local NAME_PRESETS, HEALTH_PRESETS, EXTRA_PRESETS = inner.NAME_PRESETS, inner.HEALTH_PRESETS, inner.EXTRA_PRESETS
local TextSlot = inner.TextSlot

---------------------------------------------------------------------------
-- Copy settings between sections ("Copy settings from" at the top of each
-- section tab): looks, texts, icons and auras. What makes a section itself
-- (on/off, raid size, who is listed, show yourself) stays, and keys the
-- target section does not have are not added.
---------------------------------------------------------------------------
local COPY_SKIP = {
	enabled = true, minMembers = true, showPlayer = true, showSolo = true, source = true, assists = true,
	targets = true, inParty = true, inRaid = true, auras = true,
}

local COPY_KEEP = {}
for key in pairs(COPY_SKIP) do COPY_KEEP[#COPY_KEEP + 1] = key end
table.sort(COPY_KEEP)
local COPY_VALUES = {}
for _, key in ipairs(SECTION_KEYS) do COPY_VALUES[key] = SECTION_TITLES[key] end

---------------------------------------------------------------------------
-- Options
---------------------------------------------------------------------------
local ENGINES = {
	auto = "Auto (EldoUI, Blizzard if it fails)",
	eldo = "EldoUI frames",
	skin = "Blizzard frames, skinned",
	blizzard = "Blizzard frames, untouched",
}
local GROWTHS = { DOWN = "Down", UP = "Up", RIGHT = "Right", LEFT = "Left" }
local SORT_NAMES = {
	GROUP = "Group", ROLE = "Role (tank, healer, damage)", CLASS = "Class", NAME = "Name",
	INDEX = "Join order (no grouping)",
}
local POSITIONS = {
	TOPLEFT = "Top left", TOP = "Top", TOPRIGHT = "Top right", LEFT = "Left", CENTER = "Center",
	RIGHT = "Right", BOTTOMLEFT = "Bottom left", BOTTOM = "Bottom", BOTTOMRIGHT = "Bottom right",
}
-- Buffs and debuffs can also go in one row under the frame.
local AURA_POSITIONS = { BELOWLEFT = "Below the frame, from the left", BELOWRIGHT = "Below the frame, from the right" }
for key, label in pairs(POSITIONS) do AURA_POSITIONS[key] = label end
local MANAGER_MODES = { blizzard = "Blizzard's", skin = "Skinned", hide = "Hidden (use Raid Tools)" }
local DEBUFF_PRESETS = { "dispellable", "important", "cc", "all" }
local BUFF_PRESETS = { "hots", "mine", "important", "defensives", "all" }

local function NotEldo() return M.db and M:GetEngine() ~= "eldo" end
local function Settings() return M.db end

-- Preview: a sample party of five in the party frames' size, growth,
-- colors and texts (E:ConfigSample, Core/MoverSamples.lua).
local function UpdatePreview(canvas)
	local db = M.db and M.db.party
	if not (canvas and db) then return end
	E:ConfigSample(canvas, "party", {
		count = 5, width = db.width, height = db.height, spacing = db.spacing,
		vertical = db.growth == "DOWN" or db.growth == "UP", powerHeight = db.powerHeight,
		fontSize = db.fontSize, reverse = db.reverseFill, nameJustify = "CENTER",
		color = not db.classColor and { E:GetReactionColor(5) } or nil,
	})
end

M.options = {
	{ type = "tab", label = "General" },
	{ type = "preview", label = "Preview", height = 140, create = UpdatePreview, update = UpdatePreview,
		desc = "A sample party in your party frames' size, growth and colors." },
	{ type = "header", label = "Frames" },
	{ type = "select", key = "engine", label = "Frame source", values = ENGINES, wide = true,
		desc = "Auto uses EldoUI's frames and switches to Blizzard's frames if the client's group headers don't work. Skinned needs the Skin switch for party and raid frames on the Blizzard UI page." },
	{ type = "toggle", key = "skinBlizzard", label = "Skin Blizzard's frames when Auto falls back", cog = true,
		desc = "Only when the Skin switch for party and raid frames is on (Blizzard UI page)." },
	{ type = "toggle", key = "fallbackNotice", label = "Tell me when Auto switches to Blizzard's frames", cog = true,
		desc = "One chat line the first time Auto falls back in a session." },
	{ type = "select", key = "graphics", label = "Group-frame graphics", wide = true, -- lint: unused-key ok (Core/UnitGraphics.lua reads it)
		values = function() return E.UnitGraphics and E.UnitGraphics:Values(M.db and M.db.graphics) or {} end,
		order = { "FOLLOW", "MODERN", "VANILLA", "PORTRAITBARS" },
		valueDescs = function() return E.UnitGraphics and E.UnitGraphics:Descs() end,
		hidden = function() return not E.UnitGraphics or NotEldo() end,
		desc = "The frame art of EldoUI's party and raid frames: the skin's material and a fine edge, never outside a frame, so raids keep their spacing. Positions, sizes and bars stay." },
	{ type = "header", label = "Bars" },
	{ type = "select", key = "smoothBars", label = "Smooth bars",
		values = { general = "General setting", on = "On", off = "Off" },
		desc = "Health and power bars glide to new values (the game animates them; no math in EldoUI). General setting follows Textures > Smooth bars." },
	{ type = "toggle", key = "prediction.heals", label = "Incoming heals", desc = "Heals on the way to a member, from the game's heal prediction, drawn after the health." },
	{ type = "toggle", key = "prediction.absorbs", label = "Absorb shields", desc = "Damage absorb shields as a light bar after the health, with a line at the edge when the shield is bigger than the missing health." },
	{ type = "toggle", key = "prediction.healAbsorbs", label = "Heal absorbs", desc = "Healing that will be eaten first, as a dark red part at the end of the health." },
	{ type = "header", label = "Preview" },
	{ type = "select", key = "testSize", label = "Test group size",
		values = { party = "Party (5)", raid10 = "Raid (10)", raid20 = "Raid (20)", raid25 = "Raid (25)", raid40 = "Raid (40)" },
		desc = "How many sample frames the test shows. Also /eui grouptest raid20." },
	{ type = "execute", label = "Test frames", desc = "Shows sample frames so you can size and place them while solo. Click again to hide them.",
		func = function() M:ToggleTest() end },
	{ type = "header", label = "Blizzard's frames" },
	{ type = "description", label = "EldoUI changes Blizzard's party and raid frames only as allowed on the Blizzard UI page. Off there keeps them as Blizzard made them." },
	{ type = "execute", label = "Blizzard party and raid switches", desc = "Choose on the Blizzard UI page whether EldoUI may skin, move, hide or replace Blizzard's party and raid frames.",
		func = function() E:ToggleConfig("blizzard") end },
	{ type = "select", key = "raidManager", label = "Raid manager side panel", values = MANAGER_MODES,
		desc = "Blizzard's raid manager on the left edge. Hidden keeps markers and ready check in EldoUI's Raid Tools. Needs the raid frames switch on the Blizzard UI page; Skinned also needs its Skin switch." },
	{ type = "range", percent = true, key = "blizzardScale", label = "Scale of Blizzard's frames", min = 0.5, max = 1.5, step = 0.05,
		desc = "Only when the Move switch is on: Blizzard's frames then sit on EldoUI's party and raid movers at this scale.", hidden = function() return not NotEldo() end },

	{ type = "tab", label = "Indicators" },
	{ type = "header", label = "Icons" },
	{ type = "toggle", key = "indicators.leader", label = "Leader and assistant", desc = "The group leader's crown and the raid assistant's mark." },
	{ type = "toggle", key = "indicators.mainTank", label = "Main tank and main assist", desc = "The raid's own main tank and main assist marks." },
	{ type = "toggle", key = "indicators.raidTarget", label = "Raid target marker", desc = "Skull, cross and the other markers on members." },
	{ type = "toggle", key = "indicators.readyCheck", label = "Ready check", desc = "Ready, not ready and waiting during a ready check; the result stays a while, then fades." },
	{ type = "range", key = "indicators.readyHold", label = "Ready check result stays", min = 1, max = 10, step = 1, cog = true,
		desc = "Seconds the ready check result stays before it fades out.", hidden = function() return not M.db.indicators.readyCheck end },
	{ type = "toggle", key = "indicators.resurrect", label = "Resurrection coming", desc = "Someone is casting a resurrection on this member." },
	{ type = "toggle", key = "indicators.summon", label = "Summon", desc = "A summon is pending, accepted or declined." },
	{ type = "toggle", key = "indicators.phase", label = "Other phase", desc = "The member is in another phase or war mode state." },
	{ type = "toggle", key = "indicators.afk", label = "AFK text", desc = "Shows AFK in place of the health text." },
	{ type = "header", label = "Borders" },
	{ type = "select", key = "indicators.aggroSource", label = "Threat border on", values = { any = "Any enemy", target = "Your target" },
		desc = "Any enemy: the member has threat on something. Your target: the member's threat state on what you have targeted, as the game reports it. The border itself is on the Effects tab.",
		hidden = function() return not (M.db.effects and M.db.effects.threat and M.db.effects.threat.enabled) end },
	{ type = "toggle", key = "indicators.target", label = "Target border", desc = "Accent border on the member you have targeted." },
	{ type = "toggle", key = "indicators.mouseover", label = "Mouse-over highlight", desc = "Light accent tint on the frame under the mouse." },
	{ type = "header", label = "Highlights" },
	{ type = "toggle", key = "dispel.enabled", label = "Dispellable debuff highlight", desc = "Marks members with a debuff that can be dispelled. The game decides which debuffs count." },
	{ type = "toggle", key = "dispel.mine", label = "Only debuffs I can dispel", desc = "Off: any debuff someone in the group can dispel.",
		hidden = function() return not M.db.dispel.enabled end },
	{ type = "select", key = "dispel.style", label = "Highlight look", values = { BORDER = "Border in the dispel color", GLOW = "Glow", BOTH = "Border and glow" },
		desc = "The border takes the debuff type's color (magic, curse, disease, poison). The glow's style and color are set on the Glows page.",
		hidden = function() return not M.db.dispel.enabled end },
	{ type = "toggle", key = "bossGlow", label = "Glow on boss auras", desc = "A glow while a member has an aura the game marks as a boss aura. Style and color on the Glows page." },
	{ type = "execute", label = "Glow styles", desc = "Opens the Glows page, where the dispel and boss aura glows get their style and color.",
		func = function() E:ToggleConfig("glows") end },
	{ type = "header", label = "Boss mechanics (private auras)" },
	{ type = "toggle", key = "privateAuras.enabled", label = "Show boss mechanic auras", desc = "Blizzard draws these into an anchor on the frame; EldoUI never sees them." },
	{ type = "range", key = "privateAuras.count", label = "Anchors", min = 1, max = MAX_PRIVATE, step = 1, desc = "How many boss auras at once.", dependsOn = "privateAuras.enabled" },
	{ type = "range", key = "privateAuras.size", label = "Size", min = 10, max = 40, step = 1, desc = "Icon size, capped by the frame height.", dependsOn = "privateAuras.enabled" },
	{ type = "select", key = "privateAuras.position", label = "Position", values = POSITIONS, desc = "Where the anchors sit.", dependsOn = "privateAuras.enabled" },
	{ type = "toggle", key = "privateAuras.countdown", label = "Countdown numbers", desc = "Blizzard's countdown numbers on the icon.", dependsOn = "privateAuras.enabled" },
}

-- Effects: Core/UnitFX.lua's rows, one block for every section.
table.insert(M.options, { type = "tab", label = "Effects" })
for _, row in ipairs(E:UnitFXOptions("effects", { consumer = "GroupFrames", db = Settings })) do table.insert(M.options, row) end
table.insert(M.options, { type = "description", label = "Each section keeps its own out-of-range opacity (Bars, on its tab)." })

-- Whole sentences per section (translations never glue words together).
local ENABLE_DESC = {
	party = L["Show EldoUI's party frames."], raid = L["Show EldoUI's raid frames."],
	tanks = L["Show EldoUI's main tanks frames."], pets = L["Show EldoUI's pets frames."],
}

local function AddSection(section)
	local base = section .. "."
	local title = SECTION_TITLES[section]
	local function Add(option)
		if type(option.key) == "string" then option.key = base .. option.key end
		table.insert(M.options, option)
	end
	local function AddRows(rows)
		for _, row in ipairs(rows) do table.insert(M.options, row) end
	end
	local function DB() return M.db[section] end
	local function AurasOff() return DB().auras == false end
	local function Off(block) return function() return AurasOff() or not DB()[block].enabled end end
	local raidBand = section == "raid25" or section == "raid40"
	table.insert(M.options, { type = "tab", label = title })

	Add({ type = "header", label = "Layout" })
	AddRows(E:CopySettingsOptions({ path = section, values = COPY_VALUES, keep = COPY_KEEP, existingOnly = true,
		desc = "Copy the size, growth, bars, texts, icons and auras of another section onto this one, with a preview of what changes first. On/off, raid size and who is listed stay as they are." }))
	if raidBand then
		Add({ type = "toggle", key = "enabled", label = "Own settings for this raid size",
			desc = "Use these settings once the raid is big enough; otherwise a smaller raid tab is used." })
		Add({ type = "range", key = "minMembers", label = "From this many players", min = 6, max = 40, step = 1,
			desc = "Raids with at least this many members use these settings (the largest size reached wins). Switches out of combat." })
	else
		Add({ type = "toggle", key = "enabled", label = "Enable", desc = ENABLE_DESC[section] })
	end
	Add({ type = "range", key = "width", label = "Width", min = 40, max = 300, step = 1, desc = "Frame width." })
	Add({ type = "range", key = "height", label = "Height", min = 16, max = 120, step = 1, desc = "Frame height." })
	Add({ type = "range", key = "spacing", label = "Spacing", min = 0, max = 30, step = 1, desc = "Gap between frames. Buffs or debuffs below the frame need the icon size plus a few pixels." })
	Add({ type = "toggle", key = "splitSpacing", label = "Own vertical spacing", cog = true,
		desc = "Use a different gap between rows than between columns." })
	Add({ type = "range", key = "spacingY", label = "Vertical spacing", min = 0, max = 15, step = 1, cog = true,
		desc = "Gap between rows.", hidden = function() return not DB().splitSpacing end })
	if section ~= "tanks" then
		Add({ type = "select", key = "growth", label = "Growth direction", values = GROWTHS, desc = "Where the next member goes." })
		Add({ type = "select", key = "growth2", label = "Then", cog = true,
			values = function()
				local vertical = DB().growth == "DOWN" or DB().growth == "UP"
				if vertical then return { AUTO = "Automatic (right)", RIGHT = "Right", LEFT = "Left" } end
				return { AUTO = "Automatic (down)", DOWN = "Down", UP = "Up" }
			end,
			desc = "Where a new column (or row) starts once one is full." })
		Add({ type = "toggle", key = "centered", label = "Start from the center",
			desc = "The first column (or row) grows out from the middle of its edge, so a small group stays centered on the mover." })
		Add({ type = "range", key = "unitsPerColumn", label = "Units per column", min = 1, max = section == "party" and 5 or 40, step = 1,
			desc = "Members per column (or row when growing sideways). 5 puts each raid group in its own column." })
	end
	if section ~= "party" and section ~= "tanks" then
		Add({ type = "range", key = "maxColumns", label = "Maximum columns", min = 1, max = 8, step = 1,
			desc = "Columns (or rows) at most. With 5 units per column and Group sorting this is the number of groups side by side." })
	end
	if section == "raid" or raidBand then
		Add({ type = "range", key = "maxGroups", label = "Groups shown", min = 1, max = 8, step = 1,
			desc = "Show raid groups 1 to this number, e.g. 5 to leave out bench groups 6 to 8." })
	end
	if section == "party" then
		Add({ type = "toggle", key = "showPlayer", label = "Show yourself", desc = "Your own frame in the party frames." })
		Add({ type = "toggle", key = "showSolo", label = "Show when solo", desc = "Keep your own frame visible when not in a group." })
	end
	if section ~= "tanks" then
		Add({ type = "select", key = "sortBy", label = "Sort by", values = SORT_NAMES,
			desc = "Order of the members. Role, Class, Name and Join order sort the whole raid, ignoring groups. Changes wait until combat ends." })
		Add({ type = "select", key = "sortDir", label = "Sort direction", values = { ASC = "Ascending", DESC = "Descending" }, cog = true,
			desc = "Descending turns the order around (last group or Z first)." })
	end
	if section == "tanks" then
		Add({ type = "select", key = "source", label = "Who is listed", desc = "Main tanks set by the raid leader, members with the tank role, or both.",
			values = { ASSIGNED = "Main tanks (raid assignment)", ROLE = "Tank role", BOTH = "Both" } })
		Add({ type = "toggle", key = "assists", label = "Main assists too", desc = "Also list the raid's main assists." })
		Add({ type = "toggle", key = "targets", label = "Their targets", desc = "A second column with each tank's target." })
		Add({ type = "toggle", key = "inParty", label = "Also in a party", desc = "Show the list in five-player groups too." })
	elseif section == "pets" then
		Add({ type = "toggle", key = "inParty", label = "In a party", desc = "Show pets in five-player groups." })
		Add({ type = "toggle", key = "inRaid", label = "In a raid", desc = "Show pets in raids." })
	end
	Add({ type = "input", key = "visibilityMacro", label = "Visibility macro", cog = true,
		desc = "A macro conditional that replaces when these frames show, for example \"[group:raid] show; hide\". End it with show or hide. Empty = EldoUI's own rule." })

	Add({ type = "header", label = "Bars" })
	Add({ type = "toggle", key = "classColor", label = "Class-colored health", desc = "Off: dark health bars." })
	Add({ type = "toggle", key = "colorByValue", label = "Color by health",
		desc = "Green when full, yellow at half, red when low. The game turns the health into the color, so it works in combat too. Overrides the class color." })
	Add({ type = "select", key = "fill", label = "Health fill", values = { HORIZONTAL = "Left to right", VERTICAL = "Bottom to top" },
		desc = "Bottom to top makes the health bars grow upward, like healer grids." })
	Add({ type = "toggle", key = "reverseFill", label = "Reverse fill", cog = true,
		desc = "The health fills from the other side (right to left, or top to bottom)." })
	Add({ type = "range", key = "powerHeight", label = "Power bar height (0 hides it)", min = 0, max = 12, step = 1, desc = "Height of the mana, rage or energy bar." })
	Add({ type = "select", key = "powerFilter", label = "Power bar on", values = { ALL = "Everyone", HEALERS = "Healers only" },
		desc = "Healers only shows the bar on members with the healer role; the others get a taller health bar.",
		hidden = function() return (DB().powerHeight or 0) <= 0 end })
	if section == "party" then
		local function NoPortrait() return DB().portrait == "NONE" end
		Add({ type = "select", key = "portrait", label = "Show",
			values = { NONE = "None", CLASS = "Class icon", ["2D"] = "Character portrait", ["3D"] = "3D model" }, order = { "NONE", "CLASS", "2D", "3D" },
			desc = "A picture on the left of each party frame. A member out of view or offline shows the 2D portrait instead of the model." })
		Add({ type = "toggle", key = "portraitBox", label = "Portrait in its own box", hidden = NoPortrait,
			desc = "The portrait gets its own bordered box as tall as the whole frame (the Boxed look)." })
		Add({ type = "toggle", key = "portraitDeadGrey", label = "Gray when dead or offline", hidden = NoPortrait,
			desc = "The portrait loses its color while the member is dead, a ghost or offline. Needs Dead and offline look on the Effects tab." })
		Add({ type = "toggle", key = "nameBar", label = "Name bar",
			desc = "The name in its own bar over the health bar, the health text on the right of the health bar (the Boxed look)." })
		Add({ type = "toggle", key = "badge.enabled", label = "Class or role badge",
			desc = "A class or role icon on the frame's top right corner. Round in the Blizzard and Classic skins, square in Modern (Layout and style > Appearance)." })
		Add({ type = "select", key = "badge.mode", label = "Badge shows", values = { CLASS = "Class (role when none)", ROLE = "Group role" },
			order = { "CLASS", "ROLE" }, desc = "The member's class icon, or the role picked in the group finder.",
			hidden = function() return not DB().badge.enabled end })
		Add({ type = "range", key = "badge.size", label = "Badge size", min = 10, max = 28, step = 1, cog = true,
			desc = "Size of the class or role badge.", hidden = function() return not DB().badge.enabled end })
	end
	Add({ type = "range", percent = true, key = "rangeAlpha", label = "Out-of-range opacity", min = 0.1, max = 1, step = 0.05,
		desc = "Opacity of members out of range. The game decides who is in range." })

	Add({ type = "header", label = "Text" })
	AddRows(E:TagSlotOptions(base .. "texts.name", { label = "Name text", presets = NAME_PRESETS, db = Settings }))
	Add({ type = "range", key = "nameLength", label = "Name length", zeroText = "Full", min = 0, max = 20, step = 1,
		desc = "Letters of the name to show, counted after the Name format (General page). Accents and other alphabets stay whole.",
		hidden = function()
			local preset = DB().texts.name.preset
			return preset ~= "name" and preset ~= "namelevel"
		end })
	AddRows(E:TagSlotOptions(base .. "texts.health", { label = "Health text", presets = HEALTH_PRESETS, db = Settings }))
	AddRows(E:TagSlotOptions(base .. "texts.extra", { label = "Extra text", presets = EXTRA_PRESETS, db = Settings }))
	Add({ type = "select", key = "texts.extraPosition", label = "Extra text position", values = POSITIONS, cog = true,
		desc = "Where the extra text sits on the health bar.", hidden = function() return DB().texts.extra.preset == "off" end })
	Add({ type = "toggle", key = "classColorName", label = "Class-colored names", desc = "Off: white names." })
	Add({ type = "range", key = "fontSize", label = "Text size", min = 8, max = 20, step = 1, desc = "Name size; the other texts are a little smaller." })

	Add({ type = "header", label = "Icons" })
	Add({ type = "toggle", key = "roleIcon", label = "Role icon", desc = "Tank, healer or damage icon." })
	Add({ type = "select", key = "icons.topPosition", label = "Role and leader icons", values = POSITIONS,
		desc = "Corner of the row with the role, leader and main tank icons." })
	Add({ type = "range", key = "icons.topSize", label = "Role and leader icon size", zeroText = "Auto", min = 0, max = 32, step = 1, cog = true,
		desc = "0 fits the icons to the font and frame." })
	Add({ type = "select", key = "icons.raidPosition", label = "Raid marker", values = POSITIONS, desc = "Where the skull, cross and other markers sit." })
	Add({ type = "range", key = "icons.raidSize", label = "Raid marker size", zeroText = "Auto", min = 0, max = 32, step = 1, cog = true,
		desc = "0 fits the marker to the font and frame." })
	Add({ type = "select", key = "icons.statusPosition", label = "Ready check and status", values = POSITIONS,
		desc = "Where the ready check, resurrection, summon and phase icons sit." })
	Add({ type = "range", key = "icons.statusSize", label = "Ready check and status size", zeroText = "Auto", min = 0, max = 40, step = 1, cog = true,
		desc = "0 fits the icons to the frame height." })

	if section == "tanks" or section == "pets" then
		Add({ type = "header", label = "Auras" })
		Add({ type = "toggle", key = "auras", label = "Auras and boss auras", desc = "Buffs, debuffs, defensives and boss auras on these frames." })
	end
	Add({ type = "header", label = "Debuffs", hidden = AurasOff })
	Add({ type = "toggle", key = "debuffs.enabled", label = "Show debuffs", desc = "Debuff icons; the game does the filtering.", hidden = AurasOff })
	Add({ type = "range", key = "debuffs.max", label = "Debuff icons", min = 0, max = MAX_ICONS, step = 1, desc = "How many icons at most.", hidden = Off("debuffs") })
	Add({ type = "range", key = "debuffs.size", label = "Debuff icon size", min = 8, max = 40, step = 1, desc = "Capped by the frame height.", hidden = Off("debuffs") })
	Add({ type = "select", key = "debuffs.position", label = "Debuff position", values = AURA_POSITIONS, desc = "Corner or edge the icons start from, or one row under the frame (leave room with Spacing).", hidden = Off("debuffs") })
	Add({ type = "toggle", key = "debuffs.timer", label = "Debuff countdown numbers", cog = true, hidden = Off("debuffs"),
		desc = "Time left on the debuff icons, drawn by the game in the shared EldoUI cooldown look (Fonts and text > Cooldown numbers)." })
	AddRows(E:AuraFilterOptions(base .. "debuffs.filter", { kind = "HARMFUL", label = false, presets = DEBUFF_PRESETS, db = Settings, hidden = Off("debuffs") }))

	Add({ type = "header", label = "Buffs", hidden = AurasOff })
	Add({ type = "toggle", key = "buffs.enabled", label = "Show buffs", desc = "Buff icons, for example your heals over time.", hidden = AurasOff })
	Add({ type = "range", key = "buffs.max", label = "Buff icons", min = 0, max = MAX_ICONS, step = 1, desc = "How many icons at most.", hidden = Off("buffs") })
	Add({ type = "range", key = "buffs.size", label = "Buff icon size", min = 8, max = 32, step = 1, desc = "Capped by the frame height.", hidden = Off("buffs") })
	Add({ type = "select", key = "buffs.position", label = "Buff position", values = AURA_POSITIONS, desc = "Corner or edge the icons start from, or one row under the frame (leave room with Spacing).", hidden = Off("buffs") })
	Add({ type = "select", key = "buffs.style", label = "Buff look", values = { ICONS = "Spell icons", SQUARES = "Colored squares" }, hidden = Off("buffs"),
		desc = "Squares are small colored indicators in the corner, like healer frames; the timer swipe stays." })
	Add({ type = "color", key = "buffs.squareColor", label = "Square color", desc = "Color of the buff squares.",
		hidden = function() return Off("buffs")() or DB().buffs.style ~= "SQUARES" end })
	Add({ type = "toggle", key = "buffs.timer", label = "Buff countdown numbers", cog = true, hidden = Off("buffs"),
		desc = "Time left on the buff icons, drawn by the game in the shared EldoUI cooldown look." })
	AddRows(E:AuraFilterOptions(base .. "buffs.filter", { kind = "HELPFUL", label = false, presets = BUFF_PRESETS, db = Settings, hidden = Off("buffs") }))
	Add({ type = "toggle", key = "buffs.missing", label = "Mark missing group buff", hidden = AurasOff,
		desc = "Out of combat, marks members who lack a group buff you can give (from Buff and Consumable Reminders, or the buffs you can cast). Hidden in combat." })
	Add({ type = "color", key = "buffs.missingColor", label = "Missing buff color", cog = true,
		desc = "Color of the mark when the buff's own icon isn't known.", hidden = function() return AurasOff() or not DB().buffs.missing end })
	Add({ type = "select", key = "buffs.missingPosition", label = "Missing buff position", values = POSITIONS,
		desc = "Corner of the missing buff mark.", hidden = function() return AurasOff() or not DB().buffs.missing end })

	Add({ type = "header", label = "Defensives", hidden = AurasOff })
	Add({ type = "toggle", key = "defensives.enabled", label = "Big defensive", desc = "One icon for a big defensive cooldown, from Blizzard's defensive filter.", hidden = AurasOff })
	Add({ type = "toggle", key = "defensives.external", label = "External defensives too", desc = "Also show defensives others cast on the member.", hidden = Off("defensives") })
	Add({ type = "range", key = "defensives.size", label = "Defensive icon size", min = 8, max = 40, step = 1, desc = "Capped by the frame height.", hidden = Off("defensives") })
	Add({ type = "select", key = "defensives.position", label = "Defensive position", values = POSITIONS, desc = "Where the icon sits.", hidden = Off("defensives") })
	Add({ type = "toggle", key = "defensives.timer", label = "Defensive countdown numbers", cog = true, hidden = Off("defensives"),
		desc = "Time left on the defensive icon, drawn by the game in the shared EldoUI cooldown look." })

	if HOLDER_SECTIONS[section] then
		AddRows(E:VisibilityOptions(base .. "visibility", {
			label = section == "raid" and L["Fade (every raid size)"] or L["Fade"], secure = true, db = Settings,
		}))
	end
end
for _, section in ipairs(SECTION_KEYS) do AddSection(section) end

---------------------------------------------------------------------------
-- Style presets. Party and raid stay in the left-middle zone (x 19 to
-- about 450, y -300 to -1000 at 1440p), clear of the action bars, unit
-- frames, chat and minimap. Party and raid never show at the same time.
-- Every party section keeps a power bar at least on healers, so a healer's
-- mana always shows; raid sections may leave it out.
---------------------------------------------------------------------------
local function Texts(health, extra)
	return { name = TextSlot("name"), health = TextSlot(health or "healthpercent"), extra = TextSlot(extra or "off"), extraPosition = "BOTTOM" }
end
-- Every style sets the Boxed pieces too (portrait, box, name bar, badge),
-- so switching away from Boxed leaves none of them behind.
local function Section(width, height, spacing, growth, perColumn, extra)
	local settings = { width = width, height = height, spacing = spacing, growth = growth, unitsPerColumn = perColumn,
		portrait = "NONE", portraitBox = false, nameBar = false, badge = { enabled = false } }
	for key, value in pairs(extra or {}) do settings[key] = value end
	return settings
end
local NO_BUFFS = { enabled = false }

E:RegisterStyles("GroupFrames", {
	{ key = "List", title = "Vertical list", desc = "Wide party bars stacked down; raid groups as narrow columns.",
		settings = {
			party = Section(200, 46, 4, "DOWN", 5, { powerHeight = 5, classColor = true, nameLength = 14, fontSize = 14, roleIcon = true, texts = Texts(), sortBy = "GROUP" }),
			raid = Section(52, 34, 2, "DOWN", 5, { maxColumns = 8, powerHeight = 0, classColor = true, nameLength = 5, fontSize = 11, roleIcon = false, texts = Texts("off"), sortBy = "GROUP" }),
			raid40 = Section(46, 28, 1, "DOWN", 5, { maxColumns = 8, powerHeight = 0, nameLength = 4, fontSize = 10, roleIcon = false, texts = Texts("off") }),
		} },
	{ key = "Healer", title = "Healer grid", desc = "Big tiles in rows of five, sorted by role, health growing upward, power only on healers, your heals over time and every heal and shield on the way.",
		settings = {
			party = Section(84, 64, 3, "RIGHT", 5, { powerHeight = 3, powerFilter = "HEALERS", fill = "VERTICAL", classColor = true, nameLength = 8, fontSize = 13, roleIcon = true, texts = Texts("healthdeficit"), sortBy = "ROLE",
				buffs = { enabled = true, max = 3, size = 14 }, debuffs = { enabled = true, max = 3, size = 18 } }),
			raid = Section(84, 52, 3, "RIGHT", 5, { maxColumns = 8, powerHeight = 3, powerFilter = "HEALERS", fill = "VERTICAL", classColor = true, nameLength = 8, fontSize = 12, roleIcon = true, texts = Texts("healthdeficit"), sortBy = "GROUP",
				buffs = { enabled = true, max = 3, size = 14 }, debuffs = { enabled = true, max = 3, size = 18 } }),
			raid40 = Section(72, 40, 2, "RIGHT", 5, { maxColumns = 8, powerHeight = 2, powerFilter = "HEALERS", fill = "VERTICAL", nameLength = 6, fontSize = 11, roleIcon = true, texts = Texts("healthdeficit") }),
			prediction = { heals = true, absorbs = true, healAbsorbs = true },
			dispel = { enabled = true, mine = true, style = "BOTH" },
		} },
	{ key = "Wide", title = "Wide bars", desc = "Long horizontal bars; the raid in four columns of ten.",
		settings = {
			party = Section(240, 40, 4, "DOWN", 5, { powerHeight = 6, classColor = true, nameLength = 16, fontSize = 15, roleIcon = true, texts = Texts("healthcurrentmax"), sortBy = "GROUP" }),
			raid = Section(104, 24, 2, "DOWN", 10, { maxColumns = 4, powerHeight = 0, classColor = true, nameLength = 10, fontSize = 11, roleIcon = true, texts = Texts(), sortBy = "GROUP" }),
			raid40 = Section(96, 22, 1, "DOWN", 10, { maxColumns = 4, powerHeight = 0, nameLength = 9, fontSize = 10, roleIcon = true, texts = Texts() }),
		} },
	{ key = "Blizzard", title = "Blizzard-like", desc = "Blizzard's compact raid frame proportions, two groups per column, power bars only on healers.",
		settings = {
			party = Section(110, 56, 2, "DOWN", 5, { powerHeight = 6, powerFilter = "HEALERS", classColor = true, nameLength = 10, fontSize = 12, roleIcon = true, texts = Texts(), sortBy = "GROUP" }),
			raid = Section(72, 36, 2, "DOWN", 10, { maxColumns = 4, powerHeight = 4, powerFilter = "HEALERS", classColor = true, nameLength = 7, fontSize = 11, roleIcon = true, texts = Texts("off"), sortBy = "GROUP" }),
			raid40 = Section(66, 32, 2, "DOWN", 10, { maxColumns = 4, powerHeight = 0, nameLength = 6, fontSize = 10, roleIcon = true, texts = Texts("off") }),
		} },
	{ key = "Minimal", title = "Minimal", desc = "Small, out-of-the-way frames: thin class-colored bars with names and role icons, no buff icons, and a slim mana bar on healers in the party. Good for damage dealers.",
		settings = {
			party = Section(150, 28, 2, "DOWN", 5, { powerHeight = 2, powerFilter = "HEALERS", classColor = true, nameLength = 10, fontSize = 12, roleIcon = true, texts = Texts(), sortBy = "ROLE",
				buffs = NO_BUFFS, defensives = { enabled = false } }),
			raid = Section(60, 22, 1, "RIGHT", 5, { maxColumns = 8, powerHeight = 0, classColor = true, nameLength = 6, fontSize = 10, roleIcon = false, texts = Texts("off"), sortBy = "GROUP",
				buffs = NO_BUFFS, defensives = { enabled = false } }),
			raid40 = Section(52, 20, 1, "RIGHT", 5, { maxColumns = 8, powerHeight = 0, nameLength = 5, fontSize = 9, roleIcon = false, texts = Texts("off"),
				buffs = NO_BUFFS, defensives = { enabled = false } }),
			indicators = { leader = false, mainTank = false, mouseover = false },
		} },
	{ key = "Perl", title = "Boxed", desc = "Party frames to match the Boxed unit frames: a boxed 3D portrait, a name bar, a thick health bar with value and percent, buffs and debuffs below, a class badge.",
		settings = {
			party = Section(186, 42, 18, "DOWN", 5, { powerHeight = 5, classColor = true, nameLength = 14, fontSize = 12, roleIcon = true, texts = Texts("healthcurrentpercent"),
				sortBy = "GROUP", portrait = "3D", portraitBox = true, nameBar = true, badge = { enabled = true, size = 16, mode = "CLASS" },
				buffs = { enabled = true, max = 4, size = 12, position = "BELOWLEFT" }, debuffs = { enabled = true, max = 4, size = 14, position = "BELOWRIGHT" } }),
		} },
	{ key = "RaidLead", title = "Raid leader", desc = "Raid frames plus main tanks with their targets and the group's pets.",
		settings = {
			raid = Section(80, 40, 2, "RIGHT", 5, { maxColumns = 8, powerHeight = 2, nameLength = 7, fontSize = 12, roleIcon = true, texts = Texts(), sortBy = "GROUP" }),
			raid40 = Section(64, 30, 1, "RIGHT", 5, { maxColumns = 8, powerHeight = 0, nameLength = 5, fontSize = 11, roleIcon = false, texts = Texts("off") }),
			tanks = { enabled = true, targets = true, assists = true, width = 120, height = 26, spacing = 2 },
			pets = { enabled = true, inParty = true, inRaid = true, width = 80, height = 22, maxColumns = 8 },
			indicators = { leader = true, mainTank = true, readyCheck = true },
		} },
})
