-- EldoUI Unit Frames options page.
-- Loaded right after Modules/UnitFrames.lua; adds to the same module,
-- before anything reads its options.
--
-- The helpers it shares with Modules/UnitFrames.lua come through the
-- module table (M.inner, M.INFO and so on), set in that file.
local _, E = ...
local L = E.L
local Key = E.Key
local M = E:GetModule("UnitFrames")
if not M then return end

local inner = M.inner
local UNITS, INFO, UFX = M.UNITS, M.INFO, M.UFX
local HasCastbar, HasAuras = M.HasCastbar, M.HasAuras
local Text, ExtraTag = inner.Text, inner.ExtraTag
local AURA_KIND, OTHER = inner.AURA_KIND, inner.OTHER

---------------------------------------------------------------------------
-- Options: one tab per element (General, Health, Power, Texts, Cast
-- bar, Buffs, Debuffs, Icons, Fader), each starting with the Unit picker
-- that says which frame the tab edits, plus Blizzard's own frames. Rare
-- settings carry `cog = true` (folded into a cog popup by the options
-- window); every row has a description.
---------------------------------------------------------------------------
local UNIT_TITLES = {}
for _, key in ipairs(UNITS) do UNIT_TITLES[key] = INFO[key].title end

local function EditKey()
	local key = M.db and M.db.editUnit
	return INFO[key or ""] and key or "player"
end

local function Edit()
	return M.db and M.db.units[EditKey()]
end

local function Off()
	local db = Edit()
	return not (db and db.enabled)
end

local function Add(option)
	M.options[#M.options + 1] = option
end

-- A row for the edited unit: "castbar.width" -> "units.<unit>.castbar.width".
-- `when` (optional) adds a reason to hide the row.
local function Row(option, when)
	local field = option.key
	if field then
		option.key = function() return ("units.%s.%s"):format(EditKey(), field) end
	end
	option.hidden = function()
		if Off() then return true end
		return when and when(Edit()) or false
	end
	Add(option)
	return option
end

local function UnitIs(...)
	local keys = { ... }
	return function() return tContains(keys, EditKey()) end
end

local function Not(test) return function(db) return not test(db) end end

-- The Unit picker at the top of every unit tab.
local function UnitPicker(extra)
	Add({ type = "header", label = "Unit" })
	Add({ type = "select", key = "editUnit", label = "Edit unit", values = UNIT_TITLES,
		desc = "The frame this tab changes. Every tab edits the same unit, so pick it once and walk through the tabs." })
	if extra then extra() end
end

-- Rows from the shared builders (filters, fading, text slots) work on a
-- path under "edit"; they are pointed at the edited unit here.
local function Rewrite(path, from, to)
	if type(path) ~= "string" then return path end
	if path:sub(1, #from) == from then return to() .. path:sub(#from + 1) end
	return path
end

local function AddShared(rows, from, to, when)
	for _, row in ipairs(rows) do
		local key = row.key
		if type(key) == "string" then
			row.key = function() return Rewrite(key, from, to) end
		elseif type(key) == "function" then
			row.key = function() return Rewrite(key(), from, to) end
		end
		local rowHidden = row.hidden
		row.hidden = function()
			if Off() or (when and when(Edit())) then return true end
			if type(rowHidden) == "function" then return rowHidden() end
			return rowHidden and true or false
		end
		Add(row)
	end
end

local function UnitPath() return ("units.%s."):format(EditKey()) end
local function EditDb() return { edit = Edit() } end

local ANCHORS = { TOPLEFT = "Top left", TOP = "Top", TOPRIGHT = "Top right", LEFT = "Left", CENTER = "Center", RIGHT = "Right",
	BOTTOMLEFT = "Bottom left", BOTTOM = "Bottom", BOTTOMRIGHT = "Bottom right" }
local SIDES = { LEFT = "Left of the frame", RIGHT = "Right of the frame", UP = "Above", DOWN = "Below" }

---------------------------------------------------------------------------
-- General
---------------------------------------------------------------------------
-- Preview: the edited frame with sample values, in its size, colors and
-- texts (E:ConfigSample, Core/MoverSamples.lua).
-- (A field of M: this file's main chunk is at the 200 locals limit.)
M.HEALTH_SAMPLES = { PERCENT = "80%", CURRENT = "24.0K", BOTH = "24.0K | 80%", DEFICIT = "-6.0K", CUSTOM = "24.0K" }

function M.UpdatePreview(canvas)
	local db = Edit()
	if not (canvas and db) then return end
	local color = db.healthCustomColor
	if db.healthColor ~= "CUSTOM" then color = { E:GetReactionColor(5) } end
	if db.classColor then color = { E:GetClassColor(select(2, UnitClass("player"))) } end
	local justify = db.nameText
	if justify == "NONE" then justify = false elseif justify ~= "CENTER" and justify ~= "RIGHT" then justify = "LEFT" end
	-- A power bar or orb on its own mover (the player's own position, the
	-- orb shape) is not part of the frame, so it stays out of the preview.
	local power = db.powerHeight
	if EditKey() == "player" and (db.powerStyle == "DETACHED" or db.shape == "ORB") then power = 0 end
	E:ConfigSample(canvas, "unit", {
		width = db.width, height = db.height, powerHeight = power,
		name = EditKey() == "player" and UnitName("player") or L[UNIT_TITLES[EditKey()] or ""],
		healthText = M.HEALTH_SAMPLES[db.healthText], nameJustify = justify,
		color = color and color[1] and color or nil, fontSize = M.db.fontSize, reverse = db.healthReverse,
	})
end

M.options = {
	{ type = "tab", label = "General" },
	{ type = "preview", label = "Preview", height = 84, create = M.UpdatePreview, update = M.UpdatePreview,
		desc = "The frame the tabs edit, with sample values, in its current size, colors and texts." },
	{ type = "header", label = "All frames" },
	{ type = "range", key = "fontSize", label = "Text size", min = 10, max = 22, step = 1,
		desc = "Size of the name and health text on every EldoUI unit frame (the power text is 3 points smaller)." },
	{ type = "select", key = "smoothBars", label = "Smooth bars",
		values = { general = "General setting", on = "On", off = "Off" },
		desc = "Health and power bars glide to new values (the game animates them; no math in EldoUI). General setting follows Textures > Smooth bars." },
	{ type = "execute", label = "Test frames", testSafe = true,
		desc = "Show every enabled frame with sample values so you can place and style them, even without a target, focus or boss. Click again or enter combat to end. Also /eui testframes.",
		func = function() M:SetTestMode(not M.testMode) end },
	{ type = "description", label = "Blizzard's own unit frames have their own switches on the Blizzard UI page (Unit frames tab): keep, skin, move or replace each one." },
}

UnitPicker(function()
	for _, row in ipairs(E:CopySettingsOptions({ path = function() return "units." .. EditKey() end,
		values = function()
			local values = {}
			for key, title in pairs(UNIT_TITLES) do values["units." .. key] = title end
			return values
		end,
		keep = { "enabled", "castbar.detached" }, after = M.AfterCopy,
		desc = "Copy every setting of another frame onto this one (size, bars, texts, cast bar, auras, icons, fading), with a preview of what changes first. This frame's on/off switch and position stay as they are." })) do Add(row) end
end)
-- "All frames" portrait style, after the General tab's first rows.
table.insert(M.options, 5, { type = "select", key = "allFrames.portraitStyle", label = "Portrait style, all frames",
	values = function()
		local values = { ["2D"] = "2D picture", ["3D"] = "3D model", CLASS = "Class icon (players)" }
		if M.db and M.db.allFrames and M.db.allFrames.portraitStyle == "MIXED" then values.MIXED = "Mixed" end
		return values
	end,
	order = { "2D", "3D", "CLASS", "MIXED" },
	desc = "One portrait style for every unit frame that shows a portrait and for the party frames (Group Frames). Mixed: the frames use different styles; each frame's own style is on its General tab." })
-- A graphics choice the current layout can't fit (the layout lists it
-- among its UnitGraphics entries that don't fit) stays in the list, grayed,
-- with the reason. Only that one choice: the rest of its family stays open.
local function GraphicsUnfit(value)
	local fits, reason = E:StyleFits(E.db.general.layout, "UnitGraphics", value)
	if not fits then return reason end
end

-- "All frames" graphics, right under the portrait style.
table.insert(M.options, 6, { type = "select", key = "allFrames.graphics", label = "Unit-frame graphics", wide = true,
	values = function()
		local UG = E.UnitGraphics
		return UG and UG:Values(M.db and M.db.allFrames and M.db.allFrames.graphics) or {}
	end,
	order = { "FOLLOW", "MODERN", "VANILLA", "PORTRAITBARS" },
	valueDescs = function() return E.UnitGraphics and E.UnitGraphics:Descs() end,
	valueDisabled = GraphicsUnfit,
	hidden = function() return not E.UnitGraphics end,
	desc = "The frame art of every EldoUI unit frame: portrait ring or frame, bar border and fill. It never changes positions, sizes, bars or what the portrait shows. Blizzard's own frames are not affected." })

Add({ type = "header", label = "Frame" })
Add({ type = "toggle", key = function() return UnitPath() .. "enabled" end, label = "Enable",
	desc = "Show EldoUI's frame for this unit. Units Blizzard draws too (player, target, focus, pet, boss) show only while Blizzard UI lets EldoUI replace or hide Blizzard's frame, so the unit never shows twice." })
Row({ type = "range", unit = "px", key = "width", label = "Width", min = 60, max = 600, step = 1, desc = "Frame width in pixels." })
Row({ type = "range", unit = "px", key = "height", label = "Height", min = 14, max = 120, step = 1, desc = "Frame height in pixels, power bar and info panel included." })
Row({ type = "range", percent = true, key = "scale", label = "Scale", min = 0.5, max = 2, step = 0.05, desc = "Scale of the whole frame." })
Row({ type = "range", key = "spacing", label = "Space between frames", min = 0, max = 100, step = 1,
	desc = "Gap between the frames of this group (boss 1-5, party pets, party targets)." }, function() return not INFO[EditKey()].count end)
Row({ type = "select", key = "growth", label = "Growth direction", values = { DOWN = "Down", UP = "Up" },
	desc = "Which way the list of frames grows from its mover." }, function() return not INFO[EditKey()].count end)
Row({ type = "toggle", key = "highlight", label = "Mouse-over highlight", desc = "Lighten the health bar while the mouse is over the frame." })
Row({ type = "select", key = "graphics", label = "Graphics for this frame", cog = true,
	values = function()
		local UG = E.UnitGraphics
		if not UG then return {} end
		local db = Edit()
		local values = UG:Values(db and db.graphics, L["Follow skin"])
		values.ALL = L["Like all frames"]
		return values
	end,
	order = { "ALL", "FOLLOW", "MODERN", "VANILLA", "PORTRAITBARS" },
	valueDescs = function() return E.UnitGraphics and E.UnitGraphics:Descs() end,
	valueDisabled = GraphicsUnfit,
	desc = "Give this frame its own frame art. Like all frames uses the Unit-frame graphics row at the top of this tab. Frames lower than 40 pixels get a thin edge in place of the full border." },
	function() return not E.UnitGraphics end)
Row({ type = "toggle", key = "targetGlow", label = "Glow when targeted",
	desc = "A glow round this frame while its unit is your target (look: the Glows page, \"Unit frames: your target\")." },
	UnitIs("target", "targettarget"))
Row({ type = "select", key = "strata", label = "Draw above other frames", cog = true,
	values = { BACKGROUND = "Lowest", LOW = "Low", MEDIUM = "Normal", HIGH = "High" },
	order = { "BACKGROUND", "LOW", "MEDIUM", "HIGH" },
	desc = "How high the frame sits among other bars. Raise it when another frame covers it. The game menu, the settings and popups always stay on top." })
Row({ type = "range", key = "level", label = "Stacking order", min = 0, max = 100, step = 1, cog = true, zeroText = "Auto",
	desc = "Fine-tunes which frame draws on top when two frames share the same Draw above other frames setting. Higher is on top; Auto suits most setups." })
Row({ type = "toggle", key = "happiness", label = "Pet happiness", desc = "Blizzard's happiness icon for hunter pets, with its tooltip." },
	Not(UnitIs("pet")))
Row({ type = "toggle", key = "happinessBorder", label = "Happiness border", desc = "Color the frame border red, yellow or green by happiness." },
	Not(UnitIs("pet")))

Add({ type = "header", label = "Portrait" })
do
	local function NoPortrait(db) return db.portrait == "none" end
	local function No3D(db) return db.portrait == "none" or db.portraitStyle ~= "3D" end
	local function NoBox(db) return db.portrait ~= "boxLeft" and db.portrait ~= "boxRight" end
	Row({ type = "select", key = "portrait", label = "Show",
		values = { none = "None", left = "Left of the bars", right = "Right of the bars", boxLeft = "Box on the left", boxRight = "Box on the right",
			overlay = "Over the health bar" },
		order = { "none", "left", "right", "boxLeft", "boxRight", "overlay" },
		desc = "Beside the bars, in its own box as tall as the whole frame (the Boxed look), or faintly over the health bar." })
	Row({ type = "select", key = "portraitStyle", label = "Portrait style", values = { ["2D"] = "2D picture", ["3D"] = "3D model", CLASS = "Class icon (players)" },
		order = { "2D", "3D", "CLASS" },
		desc = "2D picture, 3D model, or the class icon for players. A unit that is out of view or offline shows the 2D picture instead of the model." },
		NoPortrait)
	Row({ type = "range", unit = "px", key = "portraitWidth", label = "Box width", min = 0, max = 160, step = 1, zeroText = "Square",
		desc = "Width of the portrait box. Square makes it as wide as the frame is tall." }, NoBox)
	Row({ type = "range", percent = true, key = "portraitAlpha", label = "Overlay opacity", min = 0.05, max = 1, step = 0.05,
		desc = "How strong the portrait shows over the health bar." }, function(db) return db.portrait ~= "overlay" end)
	Row({ type = "select", key = "portraitFraming", label = "3D framing", values = { FACE = "Face", BUST = "Head and shoulders", BODY = "Whole body" },
		order = { "FACE", "BUST", "BODY" }, desc = "How much of the 3D model the camera shows." }, No3D)
	Row({ type = "range", key = "portraitDistance", label = "3D camera distance", min = 0.5, max = 3, step = 0.05, cog = true,
		desc = "Zoom of the 3D model: lower is closer." }, No3D)
	Row({ type = "range", key = "portraitRotation", label = "3D rotation", min = -180, max = 180, step = 5, cog = true,
		desc = "Turn the 3D model, in degrees." }, No3D)
	Row({ type = "range", key = "portraitHeight", label = "3D model height", min = -1, max = 1, step = 0.05, cog = true,
		desc = "Move the 3D model up or down in its box." }, No3D)
	Row({ type = "toggle", key = "portraitRaid2D", label = "2D picture in raids",
		desc = "Show the 2D picture instead of the 3D model while you are in a raid, to save frame rate." }, No3D)
	Row({ type = "toggle", key = "portraitDeadGrey", label = "Gray when dead or offline",
		desc = "The portrait loses its color while the unit is dead, a ghost or offline. Needs Dead and offline look on the Effects tab." },
		NoPortrait)
	Row({ type = "toggle", key = "portraitDesaturate", label = "Always gray", cog = true,
		desc = "Show the portrait without color all the time." }, NoPortrait)
	Row({ type = "select", key = "threatOn", label = "Threat border on", values = { FRAME = "The whole frame", PORTRAIT = "The portrait" },
		order = { "FRAME", "PORTRAIT" },
		desc = "Where the threat border of the Effects tab shows: round the whole frame or only round the portrait." },
		function(db) return db.portrait == "none" or db.portrait == "overlay" end)
end

Add({ type = "header", label = "Info panel" })
Row({ type = "toggle", key = "infoPanel.enabled", label = "Enable",
	desc = "A strip under the bars or a name bar over them, for extra texts (Texts tab: attach a text to the info panel)." })
Row({ type = "select", key = "infoPanel.position", label = "Position", values = { BOTTOM = "Under the bars", TOP = "Name bar over the bars" },
	order = { "BOTTOM", "TOP" },
	desc = "Under the bars, or over them as a name bar. Beside a portrait box it spans the bars only." },
	function(db) return not db.infoPanel.enabled end)
Row({ type = "input", key = "infoPanel.tag", label = "Info panel right text",
	desc = "Tags shown on the right of the strip, e.g. [race] [class:smart]. Empty: none. The Text tags page lists every tag." },
	function(db) return not db.infoPanel.enabled end)
Row({ type = "range", unit = "px", key = "infoPanel.height", label = "Info panel height", min = 8, max = 30, step = 1,
	desc = "Height of the strip, taken from the frame's height." }, function(db) return not db.infoPanel.enabled end)
Row({ type = "toggle", key = "infoPanel.transparent", label = "See-through background", cog = true,
	desc = "The strip lets the game show through a little. How much: General > Panel opacity." }, function(db) return not db.infoPanel.enabled end)

Add({ type = "header", label = "Badges" })
do
	local BADGE_ANCHORS = E.FrameFX.BADGE_ANCHORS
	local BADGE_ORDER = { "PORTRAIT_TOP", "PORTRAIT_BOTTOM", "OUTER_TOP", "OUTER_BOTTOM" }
	local LEVEL_ORDER = { "PORTRAIT_TOP", "PORTRAIT_BOTTOM", "OUTER_TOP", "OUTER_BOTTOM", "PLATE_CIRCLE" }
	-- The classic frame's circle holds the level only.
	local CLASS_ANCHORS = {}
	for _, key in ipairs(BADGE_ORDER) do CLASS_ANCHORS[key] = BADGE_ANCHORS[key] end
	Row({ type = "toggle", key = "badges.level.enabled", label = "Level badge",
		desc = "The unit's level in a small badge, colored by how hard it is for you." })
	Row({ type = "select", key = "badges.level.anchor", label = "Level badge position", values = BADGE_ANCHORS, order = LEVEL_ORDER,
		desc = "On the portrait's top or bottom edge, on the frame's corner away from the portrait, or in the circle of the classic frame art (Original game art), which also shows the rest, combat and corpse marks." },
		function(db) return not db.badges.level.enabled end)
	Row({ type = "range", key = "badges.level.size", label = "Level badge size", min = 12, max = 32, step = 1, cog = true,
		desc = "Size of the level badge." }, function(db) return not db.badges.level.enabled end)
	Row({ type = "toggle", key = "badges.class.enabled", label = "Class or role badge",
		desc = "A class or role icon on the frame's edge. Round in the Blizzard and Classic skins, square in Modern (Layout and style > Appearance)." })
	Row({ type = "select", key = "badges.class.mode", label = "Badge shows", values = { CLASS = "Class (role when none)", ROLE = "Group role" },
		order = { "CLASS", "ROLE" }, desc = "The player's class icon, or the role picked in the group finder." },
		function(db) return not db.badges.class.enabled end)
	Row({ type = "select", key = "badges.class.anchor", label = "Class badge position", values = CLASS_ANCHORS, order = BADGE_ORDER,
		desc = "On the portrait's top or bottom edge, or on the frame's corner away from the portrait." },
		function(db) return not db.badges.class.enabled end)
	Row({ type = "range", key = "badges.class.size", label = "Class badge size", min = 12, max = 32, step = 1, cog = true,
		desc = "Size of the class or role badge." }, function(db) return not db.badges.class.enabled end)
end

Add({ type = "header", label = "Private auras" })
local function NoPrivate() return not tContains({ "player", "target", "focus" }, EditKey()) end
Row({ type = "toggle", key = "privateAuras.enabled", label = "Boss mechanic auras",
	desc = "Let Blizzard draw private (boss mechanic) auras on this frame. Needs the Private auras switch on the Blizzard UI page." }, NoPrivate)
Row({ type = "range", key = "privateAuras.count", label = "How many", min = 1, max = 4, step = 1, desc = "Number of private aura slots." },
	function(db) return NoPrivate() or not db.privateAuras.enabled end)
Row({ type = "range", key = "privateAuras.size", label = "Size", min = 16, max = 64, step = 1, desc = "Icon size of the private auras." },
	function(db) return NoPrivate() or not db.privateAuras.enabled end)
Row({ type = "select", key = "privateAuras.anchor", label = "Attach to", values = SIDES, desc = "Where the private auras sit around the frame." },
	function(db) return NoPrivate() or not db.privateAuras.enabled end)

---------------------------------------------------------------------------
-- Health
---------------------------------------------------------------------------
Add({ type = "tab", label = "Health" })
UnitPicker()
Add({ type = "header", label = "Color" })
Row({ type = "toggle", key = "classColor", label = "Class color for players",
	desc = "Players in their class color. NPCs use the color mode below." })
Row({ type = "select", key = "healthColor", label = "Color mode",
	values = { REACTION = "By reaction", GRADIENT = "By health (red to green)", CUSTOM = "One color" },
	desc = "By reaction: hostile red, neutral yellow, friendly green, from the Reaction colors on the Colors page. By health: the game turns the health percentage into a color. One color: your own." })
Row({ type = "color", key = "healthCustomColor", label = "Health color", desc = "The health bar color when the color mode is One color." },
	function(db) return db.healthColor ~= "CUSTOM" end)
Row({ type = "select", key = "healthBackdrop", label = "Empty part",
	values = { DEFAULT = "Theme", CLASS = "Dark class color", CUSTOM = "Own color" },
	desc = "Color of the missing-health part of the bar." })
Row({ type = "color", key = "healthBackdropColor", label = "Empty part color", desc = "The color of the empty part of the health bar when its mode is Own color." },
	function(db) return db.healthBackdrop ~= "CUSTOM" end)
Add({ type = "description", label = "Tapped, dead, ghost and offline units take their colors from the Colors page (Status), shared with the party and raid frames.",
	hidden = Off })
-- The player frame can be two orbs (Core/Orb.lua) instead of bars.
local function IsOrb(db) return EditKey() == "player" and db.shape == "ORB" end
Add({ type = "header", label = "Orbs", hidden = function() return Off() or EditKey() ~= "player" end })
Row({ type = "select", key = "shape", label = "Shape", values = { BARS = "Bars", ORB = "Orbs" },
	desc = "Bars, or your health and power as two liquid orbs held in your skin's ring. The orb is as big as the frame's smaller side; the power orb has its own mover, Player Frame Power Bar." },
	function() return EditKey() ~= "player" end)
Row({ type = "toggle", key = "orbMotion", label = "Moving liquid",
	desc = "The liquid in the orbs swirls slowly. Off keeps it still. It is also still while Animations is off on the General page." },
	Not(IsOrb))
Row({ type = "toggle", key = "orbStatues", label = "Statues beside the orbs",
	desc = "A carved statue stands on the outer side of each orb, left of health and right of power. Only skins that draw statues show them, such as Infernal Stone." },
	Not(IsOrb))
Add({ type = "header", label = "Bar", hidden = function() return Off() or IsOrb(Edit()) end })
Row({ type = "select", key = "healthOrientation", label = "Direction", values = { HORIZONTAL = "Horizontal", VERTICAL = "Vertical" }, cog = true,
	desc = "Which way the health bar fills." }, IsOrb)
Row({ type = "toggle", key = "healthReverse", label = "Reverse fill", cog = true,
	desc = "Fill from the right (or from the top when vertical)." }, IsOrb)
Add({ type = "header", label = "Incoming heals and shields", hidden = function() return Off() or IsOrb(Edit()) end })
Row({ type = "toggle", key = "healPrediction", label = "Incoming heals", desc = "Show heals on the way (Blizzard's heal prediction): yours brighter on top of everyone's." }, IsOrb)
Row({ type = "toggle", key = "absorbs", label = "Absorb shields", desc = "Show damage absorb shields, with a white edge when the shield is bigger than the missing health." }, IsOrb)
Row({ type = "toggle", key = "healAbsorbs", label = "Heal absorbs", desc = "Show effects that absorb healing, over the end of the health bar." }, IsOrb)

---------------------------------------------------------------------------
-- Power
---------------------------------------------------------------------------
Add({ type = "tab", label = "Power" })
UnitPicker()
Add({ type = "header", label = "Power bar" })
Row({ type = "range", unit = "px", key = "powerHeight", label = "Height", min = 0, max = 30, step = 1, zeroText = "Hidden", desc = "Height of the power bar." }, IsOrb)
Row({ type = "range", key = "powerHeight", label = "Orb size", min = 60, max = 300, step = 2,
	desc = "Size of the power orb, ring included. It sits on its own mover, Player Frame Power Bar." }, Not(IsOrb))
local function NoPower(db) return (db.powerHeight or 0) <= 0 or IsOrb(db) end
Row({ type = "select", key = "powerStyle", label = "Style",
	values = function()
		local values = { ATTACHED = "Under the health bar", INSET = "On the bottom edge" }
		if EditKey() == "player" then values.DETACHED = "Own position (mover)" end
		return values
	end,
	desc = "Under the health bar, a smaller bar on the frame's bottom edge, or (player) a separate bar with its own mover, Player Frame Power Bar." }, NoPower)
Row({ type = "range", unit = "px", key = "powerWidth", label = "Width", min = 0, max = 600, step = 1, zeroText = "Auto",
	desc = "Width of an edge or own-position bar. Auto makes it about as wide as the frame." },
	function(db) return NoPower(db) or db.powerStyle == "ATTACHED" end)
Row({ type = "toggle", key = "powerHideNPC", label = "Hide for NPCs", desc = "Only players show a power bar." }, NoPower)
Row({ type = "toggle", key = "powerHealerOnly", label = "Healers only",
	desc = "In a group, only units in the healer role show a power bar." }, NoPower)
Row({ type = "toggle", key = "powerHideOOC", label = "Hide out of combat", cog = true,
	desc = "The power bar shows only while you are in combat." }, NoPower)
Row({ type = "toggle", key = "powerReverse", label = "Reverse fill", cog = true, desc = "Fill the power bar from the right." }, NoPower)
Add({ type = "description", label = "In the orb shape the power orb fills upward and keeps its own mover.",
	hidden = function() return Off() or not IsOrb(Edit()) end })
Row({ type = "toggle", key = "powerPrediction", label = "Spell cost",
	desc = "While you cast, the part of your power the spell will cost is marked on the bar (your own spells; costs the game keeps secret show nothing)." },
	function(db) return NoPower(db) or EditKey() ~= "player" end)

---------------------------------------------------------------------------
-- Texts
---------------------------------------------------------------------------
local HEALTH_TEXTS = { PERCENT = "Percent", CURRENT = "Current", BOTH = "Current | percent", DEFICIT = "Missing health",
	CUSTOM = "Custom tags", NONE = "Hidden" }
local POWER_TEXTS = { PERCENT = "Percent", CURRENT = "Current", BOTH = "Current | percent", CUSTOM = "Custom tags", NONE = "Hidden" }


Add({ type = "tab", label = "Text" })
UnitPicker()
Add({ type = "header", label = "Name, health and power" })
Row({ type = "select", key = "nameText", label = "Name",
	values = { LEFT = "Left", CENTER = "Center", RIGHT = "Right", TOP = "Above the frame", INFO = "In the info panel", NONE = "Hidden" },
	order = { "LEFT", "CENTER", "RIGHT", "TOP", "INFO", "NONE" },
	desc = "Where the name sits. In the info panel: on the left of the strip or name bar (General tab), else on the health bar." })
Row({ type = "input", key = "nameTag", label = "Name tags", cog = true,
	desc = "What the name text shows, e.g. [classcolor][name:medium][close]. The Text tags page lists every tag with a live preview." }, function(db) return db.nameText == "NONE" end)
Row({ type = "range", key = "nameSize", label = "Name size", min = 0, max = 22, step = 1, zeroText = "Text size",
	desc = "Size of this frame's name. Text size uses the size on the General tab, like the other texts." }, function(db) return db.nameText == "NONE" end)
Row({ type = "select", key = "healthText", label = "Health text", values = HEALTH_TEXTS,
	desc = "Health on the bar; Dead, Ghost or Offline instead when that applies. Values come straight from the game." })
Row({ type = "input", key = "healthTag", label = "Health tags", desc = "Your own health text. The Text tags page lists every tag with a live preview." },
	function(db) return db.healthText ~= "CUSTOM" end)
Row({ type = "range", key = "healthSize", label = "Health text size", min = 0, max = 24, step = 1, zeroText = "Text size",
	desc = "Size of this frame's health text. Text size uses the size on the General tab." }, function(db) return db.healthText == "NONE" end)
Row({ type = "range", unit = "px", key = "healthX", label = "Health text X", min = -40, max = 40, step = 1, cog = true,
	desc = "Moves the health text left or right from its place." }, function(db) return db.healthText == "NONE" end)
Row({ type = "range", unit = "px", key = "healthY", label = "Health text Y", min = -20, max = 20, step = 1, cog = true,
	desc = "Moves the health text up or down from its place." }, function(db) return db.healthText == "NONE" end)
Row({ type = "select", key = "powerText", label = "Power text", values = POWER_TEXTS,
	desc = "Power text on the power bar (needs a power bar 8 px or taller)." })
Row({ type = "input", key = "powerTag", label = "Power tags", desc = "Your own power text. The Text tags page lists every tag with a live preview." },
	function(db) return db.powerText ~= "CUSTOM" end)
Row({ type = "range", key = "powerSize", label = "Power text size", min = 0, max = 24, step = 1, zeroText = "Auto",
	desc = "Size of this frame's power text. Auto is a little smaller than the text size, or the text size on orbs." }, function(db) return db.powerText == "NONE" end)
Row({ type = "range", unit = "px", key = "powerX", label = "Power text X", min = -40, max = 40, step = 1, cog = true,
	desc = "Moves the power text left or right from its place." }, function(db) return db.powerText == "NONE" end)
Row({ type = "range", unit = "px", key = "powerY", label = "Power text Y", min = -20, max = 20, step = 1, cog = true,
	desc = "Moves the power text up or down from its place." }, function(db) return db.powerText == "NONE" end)

-- Extra texts: a list; "Remove" leaves a marker so saved lists keep their
-- numbering.
local function Texts() local db = Edit(); return db and db.texts or {} end
local function CurrentIndex()
	local index = tonumber(M.db and M.db.editText) or 1
	local text = Texts()[index]
	if type(text) == "table" and not text.removed then return index end
	for listIndex, entry in ipairs(Texts()) do
		if type(entry) == "table" and not entry.removed then return listIndex end
	end
end
local function NoText() return CurrentIndex() == nil end
local function TextPath() return ("units.%s.texts.%d"):format(EditKey(), CurrentIndex() or 1) end

Add({ type = "header", label = "Extra texts" })
Add({ type = "description", label = "Any number of extra texts made of tags, placed anywhere on the frame.", hidden = Off })
Add({ type = "select", key = "editText", label = "Edit text", hidden = function() return Off() or NoText() end,
	values = function()
		local values = {}
		for index, text in ipairs(Texts()) do
			if type(text) == "table" and not text.removed then
				local tag = ExtraTag(text)
				values[index] = tag ~= "" and L["Text %d: %s"]:format(index, tag) or L["Text %d (off)"]:format(index)
			end
		end
		return values
	end,
	desc = "Pick the extra text the rows below change." })
Add({ type = "execute", label = "Add text", testSafe = true, hidden = Off,
	desc = "Add an extra text to this frame and edit it below.",
	func = function()
		local texts = Edit().texts
		local text = Text(true, "", "CENTER", 0, 0, 11)
		text.preset = "namelevel"
		texts[#texts + 1] = text
		M.db.editText = #texts
		M:OnProfileChanged()
	end })
Add({ type = "execute", label = "Remove text", testSafe = true, hidden = function() return Off() or NoText() end,
	desc = "Remove the extra text picked above.",
	func = function()
		local index = CurrentIndex()
		if not index then return end
		local text = Edit().texts[index]
		text.removed = true
		text.enabled = false
		M:OnProfileChanged()
	end })
local function TextRow(option, when)
	local field = option.key
	option.key = function() return TextPath() .. "." .. field end
	option.hidden = function()
		if Off() or NoText() then return true end
		return when and when(Texts()[CurrentIndex()]) or false
	end
	Add(option)
end
local function TextOff(text) return not text.enabled end
TextRow({ type = "toggle", key = "enabled", label = "Show this text", desc = "Turn this extra text on or off." })
AddShared(E:TagSlotOptions("edit.text", { label = "Shows", db = function() return { edit = { text = Texts()[CurrentIndex() or 1] } } end,
	presets = { "name", "namelevel", "healthpercent", "healthcurrentmax", "healthcurrentpercent", "powerpercent", "status", "off" } }),
	"edit.text", TextPath, function() local text = Texts()[CurrentIndex() or 1]; return NoText() or not text or not text.enabled end)
TextRow({ type = "media", key = "font", label = "Font", mediaKind = "font", desc = "Font of this text (Default: the UI font)." }, TextOff)
TextRow({ type = "range", key = "size", label = "Size", min = 6, max = 30, step = 1, desc = "Font size of this text." }, TextOff)
TextRow({ type = "select", key = "outline", label = "Outline", cog = true,
	values = { DEFAULT = "As the UI", NONE = "None", OUTLINE = "Thin", THICKOUTLINE = "Thick", MONOCHROME = "Sharp (monochrome)" },
	desc = "Outline round the letters." }, TextOff)
TextRow({ type = "select", key = "justify", label = "Alignment", cog = true,
	values = { AUTO = "From the position", LEFT = "Left", CENTER = "Center", RIGHT = "Right" },
	desc = "How the text lines up. From the position: left on the left side, right on the right side." }, TextOff)
TextRow({ type = "select", key = "attach", label = "Attach to",
	values = { FRAME = "Frame", HEALTH = "Health bar", POWER = "Power bar", INFO = "Info panel" },
	desc = "The part of the frame the position below refers to (Info panel needs the info panel on, General tab)." }, TextOff)
TextRow({ type = "select", key = "anchor", label = "Attach to", values = ANCHORS, desc = "Point of that part the text sits on." }, TextOff)
TextRow({ type = "range", unit = "px", key = "x", label = "X offset", min = -150, max = 150, step = 1, desc = "Horizontal shift in pixels." }, TextOff)
TextRow({ type = "range", unit = "px", key = "y", label = "Y offset", min = -150, max = 150, step = 1, desc = "Vertical shift in pixels." }, TextOff)

---------------------------------------------------------------------------
-- Cast bar
---------------------------------------------------------------------------
Add({ type = "tab", label = "Cast bar" })
UnitPicker()
local function NoCast(db) return not HasCastbar(EditKey()) or not db.castbar.enabled end
local function NoCastHere() return not HasCastbar(EditKey()) end
Add({ type = "description", label = "Target of target, focus target, pet target and party target frames have no cast bar.",
	hidden = function() return not NoCastHere() end })
Add({ type = "header", label = "Cast bar", hidden = function() return Off() or NoCastHere() end })
Row({ type = "toggle", key = "castbar.enabled", label = "Enable", desc = "Show this unit's casts. Timing comes from the game's duration objects." }, NoCastHere)
Row({ type = "toggle", key = "castbar.detached", label = "Own position",
	desc = "Put the cast bar on its own mover (Player Cast Bar) instead of under the frame." },
	function(db) return NoCast(db) or EditKey() ~= "player" end)
do
	local function NotDetachedPlayer(db) return NoCast(db) or EditKey() ~= "player" or not db.castbar.detached end
	Row({ type = "select", key = "castbar.anchor", label = "Attach to",
		values = { MOVER = "Its own mover", COOLDOWNS_BELOW = "Under the Cooldown Manager", COOLDOWNS_ABOVE = "Above the Cooldown Manager" },
		desc = "Where your detached cast bar sits: on the Player Cast Bar mover, or hung under or above the Cooldown Manager so it moves with it (the mover is then not used)." },
		NotDetachedPlayer)
	local function NotOnCooldowns(db) return NotDetachedPlayer(db) or (db.castbar.anchor or "MOVER") == "MOVER" end
	Row({ type = "toggle", key = "castbar.matchWidth", label = "Match its width",
		desc = "Make the cast bar (icon included) as wide as the Cooldown Manager; it follows when the number of tracked spells changes." },
		NotOnCooldowns)
	Row({ type = "range", unit = "px", key = "castbar.anchorGap", label = "Gap to the Cooldown Manager", min = 0, max = 30, step = 1, cog = true,
		desc = "Space between the Cooldown Manager and the cast bar." }, NotOnCooldowns)
	Row({ type = "range", unit = "px", key = "castbar.width", label = "Width", min = 60, max = 600, step = 1, desc = "Width of the bar, icon included." },
		function(db) return NoCast(db) or (not NotOnCooldowns(db) and db.castbar.matchWidth) end)
end
Row({ type = "range", unit = "px", key = "castbar.height", label = "Height", min = 8, max = 40, step = 1, desc = "Height of the bar and icon." }, NoCast)
local function Detached(db) return NoCast(db) or (EditKey() == "player" and db.castbar.detached) end
Row({ type = "range", unit = "px", key = "castbar.offsetX", label = "X offset", min = -200, max = 200, step = 1,
	desc = "Horizontal shift from the frame's right edge." }, Detached)
Row({ type = "range", unit = "px", key = "castbar.offsetY", label = "Gap", min = -60, max = 60, step = 1,
	desc = "Distance between the frame and its cast bar below it." }, Detached)
Row({ type = "select", key = "castbar.colorMode", label = "Color",
	values = { ACCENT = "Theme accent", CLASS = "Class (players)", REACTION = "Reaction", CUSTOM = "Own color" },
	desc = "Color of the bar for casts you can interrupt." }, NoCast)
Row({ type = "color", key = "castbar.color", label = "Bar color", desc = "The cast bar color when its color mode is Own color." },
	function(db) return NoCast(db) or db.castbar.colorMode ~= "CUSTOM" end)
Row({ type = "color", key = "castbar.lockedColor", label = "Can't interrupt", cog = true,
	desc = "Color for casts that can't be interrupted (the game decides; the client picks the color)." }, NoCast)
Row({ type = "toggle", key = "castbar.reverse", label = "Reverse fill", cog = true, desc = "Fill the bar from the right." }, NoCast)
Row({ type = "toggle", key = "castbar.spark", label = "Spark", desc = "A bright line at the end of the fill." }, NoCast)
Row({ type = "toggle", key = "castbar.customBackdrop", label = "Own background", cog = true, desc = "Use your own color behind the bar." }, NoCast)
Row({ type = "color", key = "castbar.backdropColor", label = "Background color", cog = true, desc = "Color behind the bar." },
	function(db) return NoCast(db) or not db.castbar.customBackdrop end)

Add({ type = "header", label = "Other units' casts", hidden = function() return Off() or NoCastHere() or EditKey() == "player" end })
do
	local function NoOtherCast(db) return NoCast(db) or EditKey() == "player" end
	Row({ type = "toggle", key = "castbar.showMyInterrupt", label = "Show my interrupt",
		desc = "Show your known interrupt's icon and cooldown while your target or focus casts." },
		function(db) return NoCast(db) or (EditKey() ~= "target" and EditKey() ~= "focus") end)
	Row({ type = "toggle", key = "castbar.hideLocked", label = "Hide casts you can't interrupt",
		desc = "Hides the bar while the cast can't be interrupted." },
		NoOtherCast)
	Row({ type = "toggle", key = "castbar.hideUnimportant", label = "Only important spells", requiresAPI = "C_Spell.IsSpellImportant",
		desc = "Hide the bar for spells the game does not mark as important, so only the casts that matter show." },
		NoOtherCast)
	Row({ type = "toggle", key = "castbar.raidMarker", label = "Raid marker",
		desc = "The unit's raid marker (skull, cross ...) in front of the spell name." }, NoOtherCast)
end

Add({ type = "header", label = "Icon", hidden = function() return Off() or NoCastHere() end })
Row({ type = "toggle", key = "castbar.icon", label = "Spell icon", desc = "Show the spell's icon." }, NoCast)
local function NoIcon(db) return NoCast(db) or not db.castbar.icon end
Row({ type = "select", key = "castbar.iconPosition", label = "Icon side", values = { LEFT = "Left", RIGHT = "Right" },
	desc = "Which end of the bar the icon sits at." }, NoIcon)
Row({ type = "select", key = "castbar.iconAttach", label = "Icon placement", cog = true,
	values = { ATTACHED = "Beside the bar", INSIDE = "Inside the bar", DETACHED = "Free (own size and offset)" },
	desc = "Beside the bar (part of its width), inside the bar's end, or free with its own size and offset." }, NoIcon)
local function NotFree(db) return NoIcon(db) or db.castbar.iconAttach ~= "DETACHED" end
Row({ type = "range", unit = "px", key = "castbar.iconSize", label = "Icon size", min = 0, max = 64, step = 1, cog = true, zeroText = "Auto",
	desc = "Size of a free icon. Auto makes it as tall as the bar." }, NotFree)
Row({ type = "range", unit = "px", key = "castbar.iconX", label = "Icon X offset", min = -100, max = 100, step = 1, cog = true,
	desc = "Horizontal shift of a free icon." }, NotFree)
Row({ type = "range", unit = "px", key = "castbar.iconY", label = "Icon Y offset", min = -100, max = 100, step = 1, cog = true,
	desc = "Vertical shift of a free icon." }, NotFree)

Add({ type = "header", label = "Text", hidden = function() return Off() or NoCastHere() end })
Row({ type = "toggle", key = "castbar.showName", label = "Spell name", desc = "The spell's name on the bar." }, NoCast)
Row({ type = "range", key = "castbar.nameLength", label = "Name length", min = 0, max = 40, step = 1, cog = true, zeroText = "Full",
	desc = "Cut long spell names to this many letters (names the game keeps secret are never cut)." },
	function(db) return NoCast(db) or not db.castbar.showName end)
Row({ type = "range", key = "castbar.nameSize", label = "Name size", min = 0, max = 24, step = 1, cog = true, zeroText = "Auto",
	desc = "Font size of the spell name. Auto follows the bar's height." }, NoCast)
Row({ type = "toggle", key = "castbar.time", label = "Cast time", desc = "Time on the bar, formatted by the game." }, NoCast)
Row({ type = "select", key = "castbar.timeFormat", label = "Time format",
	values = { REMAINING = "Time left", ELAPSED = "Time spent", REMAININGMAX = "Time left / total" },
	desc = "How the cast time reads." }, function(db) return NoCast(db) or not db.castbar.time end)
Row({ type = "range", key = "castbar.timeSize", label = "Time size", min = 0, max = 24, step = 1, cog = true, zeroText = "Auto",
	desc = "Font size of the cast time. Auto follows the bar's height." }, function(db) return NoCast(db) or not db.castbar.time end)
Row({ type = "toggle", key = "castbar.spellTarget", label = "Spell target",
	desc = "Name of the cast's target next to the spell." },
	function(db) return NoCast(db) or EditKey() == "player" end)
Row({ type = "toggle", key = "castbar.targetClassColor", label = "Target in class color", cog = true,
	desc = "Color the target's name by class when the game tells it." },
	function(db) return NoCast(db) or EditKey() == "player" or not db.castbar.spellTarget end)

Add({ type = "header", label = "Timing", hidden = function() return Off() or NoCastHere() end })
Row({ type = "toggle", key = "castbar.showInterrupted", label = "Show interrupted",
	desc = "When the cast fails or is interrupted, the bar stays a moment in the interrupted color with the reason." }, NoCast)
Row({ type = "color", key = "castbar.failedColor", label = "Interrupted color", cog = true,
	desc = "Bar color after a failed or interrupted cast." }, function(db) return NoCast(db) or not db.castbar.showInterrupted end)
Row({ type = "toggle", key = "castbar.showSuccess", label = "Show finished casts",
	desc = "When the cast goes off, the bar stays a moment in the success color." }, NoCast)
Row({ type = "color", key = "castbar.successColor", label = "Finished color", cog = true,
	desc = "Bar color after a cast that went off." }, function(db) return NoCast(db) or not db.castbar.showSuccess end)
do
	local function NoHold(db) return NoCast(db) or not (db.castbar.showInterrupted or db.castbar.showSuccess) end
	Row({ type = "range", unit = "s", key = "castbar.holdTime", label = "Hold time", min = 0, max = 3, step = 0.1,
		desc = "Seconds a finished, failed or interrupted cast stays on the bar." }, NoHold)
	Row({ type = "toggle", key = "castbar.feedback", label = "Feedback word",
		desc = "While the bar holds, the spell name changes to Done, Interrupted or Failed." }, NoHold)
	Row({ type = "toggle", key = "castbar.flash", label = "Flash at the end",
		desc = "A short flash over the bar when a cast ends (needs animations on, General)." }, NoHold)
end
Row({ type = "toggle", key = "castbar.latency", label = "Latency zone",
	desc = "A red zone at the end of your casts, as long as your current latency." },
	function(db) return NoCast(db) or EditKey() ~= "player" end)
Row({ type = "toggle", key = "castbar.ticks", label = "Channel ticks",
	desc = "Marks on the bar where your channeled spells tick (Drain Life, Mind Flay, Blizzard, Tranquility ...)." },
	function(db) return NoCast(db) or EditKey() ~= "player" end)

---------------------------------------------------------------------------
-- Buffs and debuffs
---------------------------------------------------------------------------
-- Whole sentences per block, so translations never glue words together.
local AURA_TEXTS = {
	buffs = {
		show = Key("Show buffs"), showDesc = Key("Show this unit's buffs. The game keeps them updated, in combat too."),
		most = Key("The most buffs shown at once."), attachDesc = Key("Sit next to the frame, or stack on the debuffs so both blocks never overlap."),
		own = Key("Your own buffs first, then everyone else's."), grey = Key("Show other people's buffs in gray (puts yours first too)."),
		which = Key("Which buffs"),
	},
	debuffs = {
		show = Key("Show debuffs"), showDesc = Key("Show this unit's debuffs. The game keeps them updated, in combat too."),
		most = Key("The most debuffs shown at once."), attachDesc = Key("Sit next to the frame, or stack on the buffs so both blocks never overlap."),
		own = Key("Your own debuffs first, then everyone else's."), grey = Key("Show other people's debuffs in gray (puts yours first too)."),
		which = Key("Which debuffs"),
	},
}

local function AuraTab(which, title)
	local other = OTHER[which]
	local texts = AURA_TEXTS[which]
	local kind = AURA_KIND[which]
	local function Block(db) return db[which] end
	local function NoAurasHere() return not HasAuras(EditKey()) end
	local function NoBlock(db) return NoAurasHere() or not Block(db).enabled end
	local function P(field) return which .. "." .. field end
	Add({ type = "tab", label = title })
	UnitPicker()
	Add({ type = "description", label = "Target of target, focus target, pet target and party target frames show no auras.",
		hidden = function() return not NoAurasHere() end })
	Add({ type = "header", label = title, hidden = function() return Off() or NoAurasHere() end })
	Row({ type = "toggle", key = P("enabled"), label = texts.show, desc = texts.showDesc }, NoAurasHere)
	Row({ type = "select", key = P("style"), label = "Look", values = { ICONS = "Icons", BARS = "Timer bars" },
		desc = "Icons with a countdown, or one timer bar per aura with its name." }, NoBlock)
	local function Icons(db) return NoBlock(db) or Block(db).style == "BARS" end
	local function Bars(db) return NoBlock(db) or Block(db).style ~= "BARS" end
	Row({ type = "range", unit = "px", key = P("size"), label = "Icon size", min = 12, max = 64, step = 1, desc = "Width and height of each aura icon in this row." }, Icons)
	Row({ type = "range", key = P("perRow"), label = "Per row", min = 1, max = 20, step = 1, desc = "Icons in one row before the next row starts." }, Icons)
	Row({ type = "range", key = P("max"), label = "Most shown", min = 1, max = 40, step = 1, desc = texts.most }, NoBlock)
	Row({ type = "range", unit = "px", key = P("barHeight"), label = "Bar height", min = 10, max = 40, step = 1, desc = "Height of each timer bar." }, Bars)
	Row({ type = "range", unit = "px", key = P("barWidth"), label = "Bar width", min = 0, max = 500, step = 1, zeroText = "Auto",
		desc = "Width of each timer bar. Auto makes it as wide as the frame." }, Bars)
	if kind == "HARMFUL" then
		Row({ type = "select", key = P("barColor"), label = "Bar color", values = { DISPEL = "By debuff type", ACCENT = "Theme accent" },
			desc = "Color timer bars by magic, curse, disease, poison or bleed (the game picks the color), or use the accent color." }, Bars)
	end
	Row({ type = "range", unit = "px", key = P("spacing"), label = "Spacing", min = 0, max = 20, step = 1, cog = true, desc = "Gap between icons or bars." }, NoBlock)

	Add({ type = "header", label = "Position", hidden = function() return Off() or NoAurasHere() end })
	Row({ type = "select", key = P("anchor"), label = "Side", values = { TOP = "Above", BOTTOM = "Below", LEFT = "Left", RIGHT = "Right" },
		desc = "Which side of the frame (or of the other block) they sit on." }, NoBlock)
	Row({ type = "select", key = P("attachTo"), label = "Attach to",
		values = { FRAME = "The frame", [other:upper()] = other == "buffs" and "The buffs" or "The debuffs" },
		desc = texts.attachDesc }, NoBlock)
	Row({ type = "select", key = P("growthX"), label = "Growth direction", values = { RIGHT = "To the right", LEFT = "To the left" },
		desc = "Which way a row fills." }, NoBlock)
	Row({ type = "select", key = P("growthY"), label = "New rows", values = { UP = "Above", DOWN = "Below" }, cog = true,
		desc = "Where a second row goes." }, NoBlock)
	Row({ type = "range", unit = "px", key = P("x"), label = "X offset", min = -200, max = 200, step = 1, cog = true, desc = "Horizontal shift." }, NoBlock)
	Row({ type = "range", unit = "px", key = P("y"), label = "Y offset", min = -200, max = 200, step = 1, cog = true, desc = "Vertical shift." }, NoBlock)

	Add({ type = "header", label = "Order", hidden = function() return Off() or NoAurasHere() end })
	Row({ type = "select", key = P("sort"), label = "Sort", values = { TIME = "Time left", NAME = "Name", INDEX = "Order applied" },
		desc = "Order of the auras (with a filter preset; custom filter groups have their own sort)." }, NoBlock)
	Row({ type = "toggle", key = P("sortReverse"), label = "Reverse order", cog = true, desc = "Turn the sort order around." }, NoBlock)
	Row({ type = "toggle", key = P("ownFirst"), label = "Yours first",
		desc = texts.own }, NoBlock)
	Row({ type = "toggle", key = P("desaturateOthers"), label = "Gray out others'",
		desc = texts.grey }, NoBlock)

	Add({ type = "header", label = "Time and stacks", hidden = function() return Off() or NoAurasHere() end })
	Row({ type = "select", key = P("duration"), label = "Show as",
		values = { SWIPE = "Swipe and numbers", SWIPEONLY = "Swipe only", TEXT = "Text only", BOTH = "Swipe and text", NONE = "Nothing" },
		desc = "How the time left shows." }, NoBlock)
	local function NoNumbers(db) return NoBlock(db) or Block(db).duration == "NONE" or Block(db).duration == "SWIPEONLY" end
	Row({ type = "range", key = P("durationSize"), label = "Time size", min = 0, max = 24, step = 1, cog = true, zeroText = "Auto",
		desc = "Font size of the time. Auto follows the icon size." }, NoNumbers)
	Row({ type = "select", key = P("durationPoint"), label = "Time position", cog = true,
		values = { CENTER = "Center", TOP = "Top", BOTTOM = "Bottom", TOPLEFT = "Top left", TOPRIGHT = "Top right",
			BOTTOMLEFT = "Bottom left", BOTTOMRIGHT = "Bottom right", BELOW = "Under the icon", ABOVE = "Over the icon" },
		desc = "Where the time sits on the icon." }, function(db) return NoNumbers(db) or Block(db).style == "BARS" end)
	Row({ type = "range", unit = "px", key = P("durationX"), label = "Time X offset", min = -30, max = 30, step = 1, cog = true, desc = "Horizontal shift of the time." },
		function(db) return NoNumbers(db) or Block(db).style == "BARS" end)
	Row({ type = "range", unit = "px", key = P("durationY"), label = "Time Y offset", min = -30, max = 30, step = 1, cog = true, desc = "Vertical shift of the time." },
		function(db) return NoNumbers(db) or Block(db).style == "BARS" end)
	Row({ type = "range", key = P("countSize"), label = "Stack size", min = 0, max = 24, step = 1, cog = true, zeroText = "Auto",
		desc = "Font size of the stack count. Auto follows the icon size." }, NoBlock)
	Row({ type = "select", key = P("countPoint"), label = "Stack position", cog = true, values = ANCHORS,
		desc = "Where the stack count sits on the icon." }, Icons)
	Row({ type = "range", unit = "px", key = P("countX"), label = "Stack X offset", min = -30, max = 30, step = 1, cog = true, desc = "Horizontal shift of the stack count." }, Icons)
	Row({ type = "range", unit = "px", key = P("countY"), label = "Stack Y offset", min = -30, max = 30, step = 1, cog = true, desc = "Vertical shift of the stack count." }, Icons)
	Row({ type = "toggle", key = P("dispelBorder"), label = "Debuff type border",
		desc = "Border colored by magic, curse, disease, poison or bleed (the game picks the color)." }, Icons)
	Row({ type = "toggle", key = P("clickThrough"), label = "Click through", cog = true,
		desc = "No tooltip on mouse-over; clicks go to the frame underneath." }, NoBlock)

	AddShared(E:AuraFilterOptions("edit." .. which .. ".filter", { kind = kind, db = EditDb, label = texts.which }),
		"edit.", UnitPath, NoBlock)
end
AuraTab("buffs", "Buffs")
AuraTab("debuffs", "Debuffs")

---------------------------------------------------------------------------
-- Icons
---------------------------------------------------------------------------
Add({ type = "tab", label = "Icons" })
UnitPicker()
Add({ type = "header", label = "Status icons" })
local function I(field) return "indicators." .. field end
Row({ type = "range", unit = "px", key = I("size"), label = "Icon size", min = 8, max = 40, step = 1, desc = "Size of the status icons." })
Row({ type = "toggle", key = I("leader"), label = "Leader", desc = "Crown on the group leader (and a badge on raid assistants)." })
Row({ type = "toggle", key = I("role"), label = "Main tank / assist", desc = "Raid main tank and main assist icons." })
Row({ type = "toggle", key = I("pvp"), label = "PvP", desc = "Faction badge when PvP is on." })
Row({ type = "toggle", key = I("pvpTimer"), label = "PvP countdown", cog = true,
	desc = "Show the time left on your PvP flag beside the badge and in its tooltip." },
	function(db) return EditKey() ~= "player" or not db.indicators.pvp end)
Row({ type = "toggle", key = I("quest"), label = "Quest mob",
	desc = "Show an icon on the target and focus when the unit belongs to one of your unfinished quest objectives." },
	function() return EditKey() ~= "target" and EditKey() ~= "focus" end)
Row({ type = "toggle", key = I("raidMarker"), label = "Raid marker", desc = "The raid target marker on this unit." })
Row({ type = "toggle", key = I("classification"), label = "Elite and rare", desc = "Gold dragon for elites and bosses, silver for rares." },
	UnitIs("player", "pet"))
Row({ type = "toggle", key = I("readyCheck"), label = "Ready check", desc = "Ready, not ready or waiting during a ready check; the result stays a while, then fades." })
Row({ type = "range", key = I("readyHold"), label = "Ready check result stays", min = 1, max = 10, step = 1, cog = true,
	desc = "Seconds the ready check result stays before it fades out." }, function(db) return not db.indicators.readyCheck end)
Row({ type = "toggle", key = I("resurrect"), label = "Resurrection", desc = "An icon while a resurrection is on its way to this unit." })
Row({ type = "toggle", key = I("summon"), label = "Summon", desc = "Pending, accepted or declined summon." })
Row({ type = "toggle", key = I("phase"), label = "Other phase", desc = "An icon when this unit is in another phase." })
Row({ type = "toggle", key = I("combat"), label = "Combat", desc = "Crossed swords while this unit is in combat." })
local function NoCombat(db) return not db.indicators.combat end
Row({ type = "select", key = I("combatStyle"), label = "Combat look", values = { MODERN = "Modern", CLASSIC = "Classic" },
	desc = "Modern swords or the classic combat icon." }, NoCombat)
Row({ type = "color", key = I("combatColor"), label = "Combat color", cog = true, desc = "Tint of the combat icon (white keeps its own colors)." }, NoCombat)
Row({ type = "select", key = I("combatPoint"), label = "Combat position", values = ANCHORS, cog = true, desc = "Point of the frame the combat icon sits on." }, NoCombat)
Row({ type = "range", unit = "px", key = I("combatX"), label = "Combat X offset", min = -100, max = 100, step = 1, cog = true, desc = "Horizontal shift of the combat icon." }, NoCombat)
Row({ type = "range", unit = "px", key = I("combatY"), label = "Combat Y offset", min = -100, max = 100, step = 1, cog = true, desc = "Vertical shift of the combat icon." }, NoCombat)
Row({ type = "range", unit = "px", key = I("combatSize"), label = "Combat icon size", min = 0, max = 48, step = 1, cog = true, zeroText = "Same", desc = "Size of the combat icon. Same uses the icon size above." }, NoCombat)
local function NotPlayer() return EditKey() ~= "player" end
Row({ type = "toggle", key = I("resting"), label = "Resting", desc = "Shown while you rest in an inn or city." }, NotPlayer)
local function NoResting(db) return NotPlayer() or not db.indicators.resting end
Row({ type = "select", key = I("restingStyle"), label = "Resting look", values = { CLASSIC = "Icon", TEXT = "zzz text" },
	desc = "The classic resting icon or a small zzz." }, NoResting)
Row({ type = "color", key = I("restingColor"), label = "Resting color", cog = true, desc = "Tint of the resting icon or text." }, NoResting)
Row({ type = "select", key = I("restingPoint"), label = "Resting position", values = ANCHORS, cog = true, desc = "Point of the frame the resting icon sits on." }, NoResting)
Row({ type = "range", unit = "px", key = I("restingX"), label = "Resting X offset", min = -100, max = 100, step = 1, cog = true, desc = "Horizontal shift of the resting icon." }, NoResting)
Row({ type = "range", unit = "px", key = I("restingY"), label = "Resting Y offset", min = -100, max = 100, step = 1, cog = true, desc = "Vertical shift of the resting icon." }, NoResting)
Row({ type = "range", unit = "px", key = I("restingSize"), label = "Resting icon size", min = 0, max = 48, step = 1, cog = true, zeroText = "Same", desc = "Size of the resting icon. Same uses the icon size above." }, NoResting)

---------------------------------------------------------------------------
-- Effects: Core/UnitFX.lua's rows for the edited unit. The player,
-- the target-like frames and the small frames each start on their own
-- preset; units without auras or a cast bar skip those rows.
---------------------------------------------------------------------------
Add({ type = "tab", label = "Effects" })
UnitPicker()
do
	local function NoAuras() return not HasAuras(EditKey()) end
	local function NoCastRow() return not HasCastbar(EditKey()) end
	for _, consumer in ipairs(UFX.ORDER) do
		local rows = E:UnitFXOptions("edit.effects", { consumer = consumer, db = EditDb,
			hidden = { auraPop = NoAuras, auraExpiring = NoAuras, importantGlow = NoCastRow } })
		AddShared(rows, "edit.", UnitPath, function() return UFX.Consumer(EditKey()) ~= consumer end)
	end
end

---------------------------------------------------------------------------
-- Fader
---------------------------------------------------------------------------
Add({ type = "tab", label = "Visibility" })
UnitPicker()
AddShared(E:VisibilityOptions("edit.fader", { db = EditDb, label = "Fading" }), "edit.", UnitPath)
local function Always(db) return db.fader.show == "always" or db.fader.show == "never" end
Add({ type = "header", label = "Also show while", hidden = function() return Off() or Always(Edit()) end })
Row({ type = "toggle", key = "fader.casting", label = "Casting", desc = "Fully shown while this unit casts (for the player: while you cast)." }, Always)
Row({ type = "toggle", key = "fader.focus", label = "You have a focus", desc = "Fully shown while you have a focus target." }, Always)
Row({ type = "toggle", key = "fader.resting", label = "Resting", desc = "Fully shown while you rest in an inn or city." }, Always)
Add({ type = "description", label = "Fading only changes how visible a frame is: it can still be clicked. Frames always show in move mode and test mode.",
	hidden = Off })

---------------------------------------------------------------------------
-- Blizzard frames
---------------------------------------------------------------------------
local function ElementOn(id) return function() return not E:BlizzardAllowed(id) end end
Add({ type = "tab", label = "Blizzard frames" })
Add({ type = "description", label = "Settings for Blizzard's own frames, for elements switched on on the Blizzard UI page. Edit Mode settings stay in Edit Mode." })
Add({ type = "header", label = "Look" })
Add({ type = "toggle", key = "blizzard.flatArt", label = "Flat frame art",
	desc = "With Skin on: hide Blizzard's frame art and put flat EldoUI boxes behind the bars." })
Add({ type = "select", key = "blizzard.targetCastbar", label = "Target and focus cast bars", values = { BLIZZARD = "Blizzard's", HIDDEN = "Hidden" },
	desc = "Blizzard's cast bars under its target and focus frames. EldoUI's own frames have their own cast bars.", hidden = ElementOn("target-focus-frames") })
Add({ type = "toggle", key = "blizzard.petCastbar", label = "Pet cast bar", desc = "Keep Blizzard's pet cast bar.", hidden = ElementOn("pet-frame") })
Add({ type = "toggle", key = "blizzard.privateWarning", label = "Move private boss warnings",
	desc = "Private boss emotes show at the Private Boss Warnings mover (needs Move on for Private auras).", hidden = ElementOn("private-auras") })
Add({ type = "header", label = "Scale (with Move on)" })
for _, entry in ipairs({
	{ "player-frame", "Player frame", Key("Scale of Blizzard's player frame while EldoUI moves it.") },
	{ "target-focus-frames", E.Key("Target and focus"), Key("Scale of Blizzard's target and focus while EldoUI moves it.") },
	{ "pet-frame", E.Key("Pet frame"), Key("Scale of Blizzard's pet frame while EldoUI moves it.") },
	{ "boss-frames", "Boss frames", Key("Scale of Blizzard's boss frames while EldoUI moves it.") },
	{ "player-cast-bar", "Player cast bar", Key("Scale of Blizzard's player cast bar while EldoUI moves it.") } }) do
	Add({ type = "range", key = "blizzard.scale." .. entry[1], label = entry[2], percent = true, min = 0.5, max = 2, step = 0.05,
		desc = entry[3], hidden = ElementOn(entry[1]) })
end

---------------------------------------------------------------------------
-- Style presets: a few ready-made looks. A style sets the frames' sizes
-- and pieces; the layout owns their positions, and a frame that grows past
-- its spot takes the layout's wide point, so its neighbors make room (see
-- Core/Layout.lua). A style that doesn't fit a layout is grayed out there.
---------------------------------------------------------------------------
-- Every style sets the Boxed pieces too (name bar, badges, threat spot), so
-- switching away from Boxed leaves no name bar or badge behind.
local PLAIN = {
	infoPanel = { enabled = false, position = "BOTTOM", tag = "" },
	badges = { level = { enabled = false }, class = { enabled = false } },
	threatOn = "FRAME",
}
local MIRROR = { left = "right", boxLeft = "boxRight" }
local function Frames(width, height, extra)
	local unit = { width = width, height = height }
	for key, value in pairs(CopyTable(PLAIN)) do unit[key] = value end
	for key, value in pairs(extra or {}) do unit[key] = value end
	local target = CopyTable(unit)
	target.portrait = MIRROR[unit.portrait] or unit.portrait
	unit.castbar = { width = width }
	target.castbar = { width = width }
	return { units = { player = unit, target = target } }
end

-- Boxed: a 3D portrait in its own box, a name bar with race
-- and class over a thick health bar, the power bar below, and the level
-- and class badges on the edges.
local function Boxed()
	-- Small frames (pet, target of target) keep the name on the health bar.
	local function Unit(width, height, side, badges)
		local small = height < 40
		return {
			width = width, height = height, powerHeight = math.floor(height / 7), portrait = side, portraitStyle = "3D", portraitWidth = 0,
			portraitFraming = "FACE", nameText = small and "LEFT" or "INFO", healthText = small and "PERCENT" or "BOTH", classColor = true,
			threatOn = "PORTRAIT",
			infoPanel = { enabled = not small, height = 14, position = "TOP", transparent = false,
				tag = width >= 200 and "[race] [class:smart]" or "" },
			badges = {
				level = { enabled = badges, anchor = "PORTRAIT_BOTTOM", size = 18 },
				class = { enabled = badges, anchor = "OUTER_TOP", size = 20, mode = "CLASS" },
			},
			castbar = { width = width },
		}
	end
	return { units = {
		player = Unit(260, 52, "boxLeft", true),
		target = Unit(260, 52, "boxRight", true),
		focus = Unit(200, 42, "boxRight", false),
		pet = Unit(150, 30, "boxLeft", false),
		targettarget = Unit(150, 30, "boxRight", false),
	} }
end

-- Classic: the shape of the original frames. The player and target bars
-- are 1.09 times the classic 119x23 tracks, so they read on a large screen;
-- the target of target and pet keep the classic 46x15 and 69x15. A
-- portrait box on the outer side, the name panel above the bars (under them
-- on the small frames), thin health and power bars. The game's own frame
-- art fits this shape exactly under the Vanilla Original skin
-- (Core/UnitGraphics.lua), and the frames sit in the original corners of
-- the Vanilla Original layout. The cast bars are thin and sit under the
-- bars, inside the plate's lower edge; the focus (a later frame) gets thin
-- bars of the same kind.
local function Classic()
	-- bars: the bars' width and height; box: the portrait box beside them;
	-- info: the name panel's height and edge. The frame keeps a pixel above
	-- the name panel, between it and the bars and under the bars.
	-- circle: the frame's classic art has the level circle.
	local function Unit(barsWidth, barsHeight, powerHeight, side, box, infoHeight, infoEdge, extra, circle)
		local unit = {
			width = barsWidth + box, height = barsHeight + infoHeight + 3, powerHeight = powerHeight,
			portrait = side, portraitStyle = "2D", portraitWidth = box, classColor = false, nameText = "INFO",
			infoPanel = { enabled = true, height = infoHeight, position = infoEdge, transparent = true, tag = "" },
			-- The level by the portrait, as the original frames show it (in the
			-- art's level circle on the player and target frames, which have
			-- one), and no level text over the frame's edge (it would sit on the
			-- target of target in some layouts).
			badges = { level = { enabled = box >= 40, anchor = circle and "PLATE_CIRCLE" or "PORTRAIT_BOTTOM", size = 18 },
				class = { enabled = false } },
			texts = {
				Text(false, "[level:smart] [classification]", "TOPRIGHT", -2, 12, 11),
				Text(false, "[status]", "CENTER", 0, 0, 12),
			},
			threatOn = "FRAME",
		}
		for key, value in pairs(extra or {}) do unit[key] = value end
		return unit
	end
	return { units = {
		player = Unit(129, 25, 11, "boxLeft", 77, 22, "TOP", { healthText = "BOTH",
			castbar = { width = 129, height = 12, offsetX = 0, offsetY = -5 } }, true),
		target = Unit(129, 25, 11, "boxRight", 117, 22, "TOP", { healthText = "BOTH",
			castbar = { width = 129, height = 12, offsetX = -117, offsetY = -5 } }, true),
		-- The small frames' names take the classic small size, so a name
		-- fits the short name panel under their bars.
		targettarget = Unit(46, 15, 5, "boxLeft", 45, 15, "BOTTOM", { healthText = "NONE", nameSize = 10 }),
		pet = Unit(69, 15, 5, "boxLeft", 47, 15, "BOTTOM", { healthText = "NONE", nameSize = 10, castbar = { width = 69, offsetX = 0 } }),
		-- The focus came later: thin bars in the same spirit, no plate.
		focus = { width = 200, height = 30, powerHeight = 6, portrait = "none", classColor = false, nameText = "LEFT",
			infoPanel = CopyTable(PLAIN.infoPanel), badges = CopyTable(PLAIN.badges), threatOn = "FRAME",
			castbar = { width = 200, height = 12 } },
	} }
end

-- Orbs: the player's health and power as two liquid orbs in the skin's
-- ring (Core/Orb.lua), the power orb on the detached power bar's mover.
-- The target is a long bar with its name in the middle, made to sit
-- centered above the action bars; the player's cast bar hangs under the health
-- orb, as wide as the orb (Own position stays the player's choice).
local function Orbs()
	local settings = Frames(320, 30, { powerHeight = 4, portrait = "none", nameText = "CENTER", healthText = "PERCENT", classColor = true })
	settings.units.target.castbar = { width = 320, height = 16 }
	local player = settings.units.player
	for key, value in pairs({
		width = 150, height = 150, shape = "ORB", orbMotion = true, portrait = "none", nameText = "NONE",
		healthText = "CURRENT", powerText = "CURRENT", powerStyle = "DETACHED", powerWidth = 150, powerHeight = 150,
		classColor = false, healthColor = "CUSTOM", healthCustomColor = { 0.78, 0.09, 0.07 },
		castbar = { width = 150, height = 14 },
	}) do player[key] = value end
	return settings
end

E:RegisterStyles("UnitFrames", {
	{ key = "Clean", title = "Clean bars", desc = "Flat bars with name left and health right.",
		settings = Frames(277, 46, { powerHeight = 6, portrait = "none", nameText = "LEFT", healthText = "BOTH", classColor = true }) },
	{ key = "Portrait", title = "Portraits", desc = "Bigger frames with a portrait on the outside edge.",
		settings = Frames(300, 56, { powerHeight = 8, portrait = "left", nameText = "LEFT", healthText = "BOTH", classColor = true }) },
	{ key = "Minimal", title = "Minimal", desc = "Thin bars with a slim power bar, health in percent.",
		settings = Frames(220, 28, { powerHeight = 4, portrait = "none", nameText = "CENTER", healthText = "PERCENT", classColor = true }) },
	{ key = "Healer", title = "Healer wide", desc = "Wide frames with the current health value, easy to read next to party and raid frames.",
		settings = Frames(340, 40, { powerHeight = 5, portrait = "none", nameText = "LEFT", healthText = "CURRENT", classColor = true }) },
	{ key = "Blizzard", title = "Blizzard-like", desc = "Portrait frames with the name on top and a thick power bar.",
		settings = Frames(232, 60, { powerHeight = 12, portrait = "left", nameText = "TOP", healthText = "BOTH", classColor = false }) },
	{ key = "Classic", title = "Classic frames", desc = "The original frames' shape: thin bars beside a round portrait, the name above them. With the Vanilla Original skin they wear the game's own frame art.",
		settings = Classic() },
	{ key = "Perl", title = "Boxed", desc = "A 3D portrait in its own box, a name bar with race and class, a thick health bar, and level and class badges. Pairs with the Boxed party frames.",
		settings = Boxed() },
	{ key = "Orbs", title = "Orbs", desc = "Your health and power as two liquid orbs in your skin's ring, with the values in the middle, and a long target bar. Made for the Twin Orbs layout.",
		settings = Orbs() },
}, { playerLists = { "texts" } })
