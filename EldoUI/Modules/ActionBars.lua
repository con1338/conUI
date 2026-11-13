-- EldoUI Action Bars: eight bars of secure action buttons built on
-- LibActionButton-1.0 (BSD, embedded in Libs/), with flat EldoUI styling,
-- per-bar layout, paging, visibility drivers and fading, and Blizzard
-- keybindings carried over. Bar 1 pages like Blizzard's main bar (stance,
-- vehicle, possess, override and bar paging).
--
-- This file is the core of the module: settings, the bars, paging,
-- visibility and fade, bindings and the per-element switches for Blizzard's
-- main and extra bars. The rest lives in Modules/ActionBars/:
--   Cooldowns.lua  secret-safe cooldown numbers (Blizzard's countdown formatter)
--   Buttons.lua    button look, text, proc glow, skin groups, Blizzard button skins
--   Special.lua    pet and stance bars, extra/zone ability, vehicle exit,
--                  possess, override, seat indicator, totem bar, gamepad HUD
--   Ranks.lua      lower spell ranks moved to the highest rank (offer or automatic)
--   RankCheck.lua  lower spell ranks lit up and listed (spellbook button)
--   CueData.lua    spell cues: which buffs show on which spells, per class
--   Cues.lua       spell cues: proc flash and your buffs on the buttons
--   Options.lua    the options page
--
-- Fading and "when is a bar shown" use the shared visibility engine
-- (Core/Visibility.lua); the proc glow look the shared glows
-- (Core/Glow.lua).
--
-- Rules kept everywhere (Midnight/Forever):
--   * Protected frames (bars, buttons, Blizzard bars) change only out of
--     combat, through E:RunOutOfCombat. In combat only state drivers (secure)
--     and alpha change.
--   * Blizzard frames are hidden by reparenting to a hidden frame, never by
--     overwriting their functions or writing fields into them.
--   * Every touch of a Blizzard element is gated by its switch
--     (E:BlizzardAllowed / E:BlizzardHidden, Core/Blizzard.lua).
local _, E = ...
local L = E.L

local LAB = _G.LibStub("LibActionButton-1.0")

local NUM_BARS = 8

-- Per-bar settings. Style presets set only the look (size, spacing,
-- texts); M:FillDefaults still fills in keys an older profile or a plugin
-- preset left out.
-- Two switches per bar: `enabled` (On) is the player's own: the buttons,
-- their actions and their keys exist. `shown` (Shown) is what a layout's
-- hidden list changes: a bar that is On but not Shown keeps every action
-- and key and only steps out of sight (Modules/ActionBars/HiddenBars.lua).
-- `hiddenMouseover`: while out of sight, the bar shows when the mouse
-- points at it out of combat (true) or never shows at all (false).
local function BarText()
	-- A bar's own text settings, used while its "Own text settings" is on.
	return {
		showHotkey = true, hotkeySize = 13, hotkeyPosition = "TOPRIGHT",
		showCount = true, countSize = 14, countPosition = "BOTTOMRIGHT",
		showMacro = false, macroSize = 11,
	}
end

local function BarDefaults(enabled, perRow, size)
	return {
		enabled = enabled, shown = true, hiddenMouseover = true, buttons = 12, perRow = perRow, size = size, spacing = 4, showGrid = true,
		aspect = "1:1",         -- button shape, width:height
		scale = 100,            -- percent
		alpha = 100,            -- percent, opacity when shown
		growth = "TOPLEFT",     -- corner the first button sits in
		fillOrder = "rows",     -- rows | columns: which way the buttons fill the grid
		-- When the bar shows and how it fades: the shared visibility block
		-- (Core/Visibility.lua). Hidden in vehicles by default.
		fade = E:VisibilityDefaults({ hideVehicle = true }),
		customVisibility = "",  -- advanced: macro conditions that replace the Show rule
		blizzard = "auto",      -- Blizzard's own bar: auto | show | hide
		pageShift = 0, pageCtrl = 0, pageAlt = 0, -- modifier paging: 0 = off, else bar number
		customPaging = "",      -- macro conditions for paging (advanced)
		flyout = "AUTO",        -- AUTO | UP | DOWN | LEFT | RIGHT
		backdrop = false, backdropPadding = 4,
		clickThrough = false,
		ownText = false,        -- use `text` below instead of the Text tab
		text = BarText(),
	}
end

-- Button shapes: width divided by height.
local ASPECTS = { ["1:1"] = 1, ["5:4"] = 1.25, ["4:3"] = 4 / 3, ["3:2"] = 1.5, ["2:1"] = 2 }

local M = E:NewModule("ActionBars", {
	title = "Action Bars",
	desc = "Eight flat action bars, pet and stance bars, cooldown numbers, proc glow and fade rules.",
	conflicts = { "EllesmereUIActionBars", "Bartender4", "Dominos", "ElvUI" },
	frames = {
		"EldoUI_ActionBar1", "EldoUI_ActionBar2", "EldoUI_ActionBar3", "EldoUI_ActionBar4",
		"EldoUI_ActionBar5", "EldoUI_ActionBar6", "EldoUI_ActionBar7", "EldoUI_ActionBar8", "EldoUI_PetBar",
		"EldoUI_StanceBar", "EldoUI_PossessBar", "EldoUI_VehicleSeat", "EldoUI_VehicleExit",
		"EldoUI_VehicleExitButton", "EldoUI_ExtraAbility", "EldoUI_TotemBar", "EldoUI_GamepadBar",
		"EldoUI_ProcOverlayHolder",
	},
	movers = {
		"EldoUI_ActionBar1", "EldoUI_ActionBar2", "EldoUI_ActionBar3", "EldoUI_ActionBar4",
		"EldoUI_ActionBar5", "EldoUI_ActionBar6", "EldoUI_ActionBar7", "EldoUI_ActionBar8", "EldoUI_PetBar",
		"EldoUI_StanceBar", "EldoUI_PossessBar", "EldoUI_VehicleSeat", "EldoUI_VehicleExit",
		"EldoUI_ExtraAbility", "EldoUI_TotemBar", "EldoUI_GamepadBar", "EldoUI_ProcOverlay",
	},
	blizzard = {
		"main-action-bar", "multi-action-bars", "action-button-look", "player-spells", "pet-stance-bars",
		"vehicle-possess-override", "extra-zone-ability", "totem-bar", "gamepad-hud",
	},
	savedKeys = { "profile.modules.ActionBars" },
	optionsPage = "module:ActionBars",
	presets = { "Clean", "Compact", "Large", "Macros", "Standard" },
	defaults = {
		hideBlizzard = true, -- v0.5.0 setting; only read when moving to the element switches
		-- Text (every bar uses these unless it has its own text settings)
		textPreset = "standard", -- standard | compact | large | keybind | clean | custom
		showHotkey = true,
		hotkeyAbbrev = true,
		fontSize = 13,          -- keybind text size
		hotkeyPosition = "TOPRIGHT",
		hotkeyColor = { 0.85, 0.85, 0.88 },
		showCount = true,
		countSize = 14,
		countPosition = "BOTTOMRIGHT",
		countColor = { 1, 1, 1 },
		showMacro = false,
		macroSize = 11,
		macroColor = { 1, 1, 1 },
		textOutline = "theme",   -- theme | NONE | OUTLINE | THICKOUTLINE
		textOffsetX = 0,         -- nudges every corner text inward (+) or outward (-)
		textOffsetY = 0,
		-- Cooldowns
		cooldownText = "eldoui", -- eldoui | blizzard | off
		cooldownSize = 16,
		cooldownExpiring = 5,    -- seconds below which numbers turn the expiring color
		cooldownTenths = 3,      -- seconds below which tenths show (0 = never)
		cooldownColor = { 1, 1, 1 },
		cooldownSecondsColor = { 1, 0.9, 0.4 },
		cooldownExpiringColor = { 1, 0.3, 0.3 },
		cooldownOwnLook = false, -- off: thresholds and colors from General > Fonts and Text
		swipeAlpha = 80,
		drawBling = true,
		cooldownMinDuration = 2, -- seconds: shorter cooldowns (the global cooldown) show no numbers
		cooldownEdge = false,    -- bright edge on the swipe
		chargeCooldown = "edge", -- recharge of spells with charges: swipe | edge | none
		desaturateCooldown = false, -- gray icon while the game says the action is on cooldown
		-- Buttons
		buttonZoom = 8,          -- percent of the icon edge cropped
		rangeColoring = "button", -- button | hotkey | off
		rangeColor = { 0.8, 0.1, 0.1 },
		manaColor = { 0.5, 0.5, 1.0 },
		unusableColor = { 0.4, 0.4, 0.4 },
		equippedBorder = true,   -- colored border on items you wear
		equippedColor = { 0.3, 0.85, 0.3 },
		lockBars = "game",       -- game | locked | unlocked (lockActionBars)
		pickupKey = "game",      -- game | SHIFT | CTRL | ALT (the PICKUPACTION modifier)
		procGlow = "blizzard",   -- blizzard | eldoui | none
		highlightStyle = "fill", -- fill | accent | none
		pushedStyle = "fill",
		tooltips = "enabled",    -- enabled | nocombat | disabled
		castVFX = false,
		masque = true,
		gamepadHide = true,      -- hide EldoUI's bars while the gamepad UI is on
		linkMouseover = false,   -- bars on "Mouse over" show together when one is hovered
		endCaps = "keep",        -- Blizzard main bar gryphons: keep | hide (works with the module off too)
		hudTray = false,         -- one skin panel behind bars 1 and 2 (the Twin Orbs layout turns it on)
		flyoutSkin = true,
		-- Spell ranks (Ranks.lua): offered after a new rank is learned and
		-- at login, swapped when the player applies the preview; or, when
		-- the player turns on auto, moved automatically out of combat in
		-- scope (used: every bar the player uses | main: bars 1-3), the
		-- gamepad bars in both.
		-- The rank check (RankCheck.lua): glows on lower ranks (off |
		-- spellbook | always), the spellbook button and the chat report.
		ranks = { offer = true, auto = false, scope = "used", chat = true, exclude = "", highlight = "spellbook", spellbookButton = true,
			report = true, macros = true, otherBars = true },
		-- Spell cues (Cues.lua), off by default: a flash on a proc (sound
		-- off), your buffs on the spells they change, your own effects on
		-- their buttons; on other bar addons' and Blizzard's buttons too.
		cues = { enabled = false, flash = true, sound = false, soundFile = "eldo:EldoChime", soundChannel = "Master",
			buffs = true, own = true, stacks = true, otherBars = true },
		optionsBar = 1,          -- which bar the Bars tab of the options page shows
		bars = {
			[1] = BarDefaults(true, 12, 46),
			[2] = BarDefaults(true, 12, 46),
			[3] = BarDefaults(true, 12, 46),
			[4] = BarDefaults(true, 1, 40),
			[5] = BarDefaults(true, 12, 40),
			[6] = BarDefaults(false, 6, 36),
			[7] = BarDefaults(false, 6, 36),
			[8] = BarDefaults(false, 1, 40),
		},
		-- Bar 1 extras
		pageVehicle = true,      -- bar 1 shows vehicle, override and possess actions
		pageForms = true,        -- bar 1 follows stance, form and stealth pages
		-- Special bars (Special.lua)
		pet = { mode = "eldoui", buttons = 10, perRow = 10, size = 30, spacing = 4, scale = 100, alpha = 100, growth = "TOPLEFT", fillOrder = "rows",
			fade = E:VisibilityDefaults({ hideVehicle = true }), customVisibility = "",
			backdrop = false, backdropPadding = 4, happiness = true, autocastGlow = true },
		stance = { mode = "eldoui", perRow = 10, size = 30, spacing = 4, scale = 100, alpha = 100, growth = "TOPLEFT", fillOrder = "rows",
			fade = E:VisibilityDefaults({ hideVehicle = true }), customVisibility = "",
			backdrop = false, backdropPadding = 4 },
		possess = { mode = "eldoui", size = 30, spacing = 4, scale = 100 },
		extra = { scale = 100, hideArt = false },
		vehicle = { exit = "auto", exitSize = 32, overrideBar = "eldoui", seat = "keep", seatScale = 100 },
		totem = { scale = 100 },
		proc = { alpha = 100, scale = 100 },
		gamepad = { scale = 100 },
	},
})

-- Bar 1 shows the vehicle's actions by default, so it stays in vehicles.
M.defaults.bars[1].fade.hideVehicle = false

-- Which Blizzard action slots, binding names and bars each EldoUI bar uses.
local BARS = {
	[1] = { binding = "ACTIONBUTTON", page = 1, blizzard = "MainActionBar", buttons = "ActionButton", element = "main-action-bar" },
	[2] = { binding = "MULTIACTIONBAR1BUTTON", page = 6, blizzard = "MultiBarBottomLeft", element = "multi-action-bars" },
	[3] = { binding = "MULTIACTIONBAR2BUTTON", page = 5, blizzard = "MultiBarBottomRight", element = "multi-action-bars" },
	[4] = { binding = "MULTIACTIONBAR3BUTTON", page = 3, blizzard = "MultiBarRight", element = "multi-action-bars" },
	[5] = { binding = "MULTIACTIONBAR4BUTTON", page = 4, blizzard = "MultiBarLeft", element = "multi-action-bars" },
	[6] = { binding = "MULTIACTIONBAR5BUTTON", page = 13, blizzard = "MultiBar5", element = "multi-action-bars" },
	[7] = { binding = "MULTIACTIONBAR6BUTTON", page = 14, blizzard = "MultiBar6", element = "multi-action-bars" },
	[8] = { binding = "MULTIACTIONBAR7BUTTON", page = 15, blizzard = "MultiBar7", element = "multi-action-bars" },
}
for _, info in ipairs(BARS) do
	info.buttons = info.buttons or (info.blizzard .. "Button")
end
M.BARS = BARS
M.NUM_BARS = NUM_BARS

-- Default positions (1440p pixels), used when the layout preset has none.
local DEFAULT_POINTS = {
	{ "BOTTOM", "UIParent", "BOTTOM", 0, 40 },
	{ "BOTTOM", "UIParent", "BOTTOM", 0, 90 },
	{ "BOTTOM", "UIParent", "BOTTOM", 0, 140 },
	{ "RIGHT", "UIParent", "RIGHT", -4, 0 },
	{ "RIGHT", "UIParent", "RIGHT", -48, 0 },
	{ "BOTTOMRIGHT", "UIParent", "BOTTOM", -320, 40 },
	{ "BOTTOMLEFT", "UIParent", "BOTTOM", 320, 40 },
	{ "RIGHT", "UIParent", "RIGHT", -92, 0 },
}

M.bars = {}      -- [index] = header frame
M.holders = {}   -- every EldoUI bar frame that fades (bars, pet, stance)

-- The dock reads these bars as obstacles, never as movers it may write.
local dockCreated, dockPublish, dockLayout
do
	local created, hiddenSource, paintSource, refresh, reading = {}, nil, nil, nil, nil
	local partsSource, surfaceMeasure, paintGeometrySource
	local dockGeometryEpoch = {}
	local targetAdmit, targetGeneration, targetEnabled = E.IsCurrentProfile, E.GetApplyGeneration, E.ModuleEnabledValue
	local surfaceRead, surfaceSource
	local bindSurface = E.BindSurfaceMeasurementRead
	if type(bindSurface) == "function" then
		bindSurface(E, M, function(_, read, source) surfaceRead, surfaceSource = read, source end)
	end
	local Secret, plainCall = E.Secret, E.PlainCallAll
	local authorityEqual, geometrySecret = rawequal, Secret
	local moverGeometrySource = E.MoverAuthoritySource
	local geometryFactory, existingGeometry
	if type(moverGeometrySource) == "function" then
		local _, capture, _, _, existing = moverGeometrySource()
		geometryFactory, existingGeometry = capture, existing
	end
local function GeometrySame(value, saved) return not geometrySecret(value) and authorityEqual(value, saved) end
local nativeBinding, admitGeometry
if type(moverGeometrySource) == "function" then local _, _, _, _, _, bind, admit = moverGeometrySource();nativeBinding, admitGeometry = bind, admit end
local function ObserveOwnedGeometry(object)
	if type(admitGeometry) ~= "function" then return end
	return admitGeometry(object)
end

	local function ObserveDock(object)
		local capture, seal
		if existingGeometry then capture, seal = existingGeometry(object) end
		if not capture then
			local record = ObserveOwnedGeometry(object)
			if not record then return end
			capture, seal = record.capture, record.source
		end
		return { capture = capture, source = seal }
	end
	local INDEXES = { 1, 2, 3, 5 }
	local METHODS = { "GetParent", "GetNumPoints", "GetPoint", "GetRect", "GetEffectiveScale", "IsShown", "IsVisible" }
	local GEOMETRY = { "enabled", "shown", "buttons", "perRow", "size", "spacing", "aspect", "scale", "growth", "fillOrder", "backdrop", "backdropPadding" }
	local function Same(a, b) return not Secret(a) and not Secret(b) and rawequal(a, b) end
	-- Captured values are private public-value pins; only the current value can become secret.
	local function Matches(value, captured) return not Secret(value) and rawequal(value, captured) end
	local function Plain(v) return not Secret(v) and type(v) == "table" and getmetatable(v) == nil end
	local function Number(v) return not Secret(v) and type(v) == "number" and v == v and v > -math.huge and v < math.huge end
	local function Pack(...) return { n = select("#", ...), ... } end
	local function NativeValues(ok, ...)
		if not ok then return end
		for i = 1, select("#", ...) do if Secret(select(i, ...)) then return end end
		return ...
	end
	local function Invoke(fn, ...) return plainCall(fn, ...) end
	function M:RegisterDockHiddenSource(read)
		if not Same(self, M) or E.Secret(read) or type(read) ~= "function" or (hiddenSource and not Same(hiddenSource, read)) then return false end
		hiddenSource = read;return true
	end
	function M:RegisterDockPaintSource(read, captureGeometry)
		if not Same(self, M) or E.Secret(read) or type(read) ~= "function" or E.Secret(captureGeometry) or type(captureGeometry) ~= "function"
			or (paintSource and (not Same(paintSource, read) or not Same(paintGeometrySource, captureGeometry))) then return false end
		paintSource, paintGeometrySource = read, captureGeometry;partsSource, surfaceMeasure = M.ButtonParts, E.SurfaceMeasure;return true
	end
	dockCreated = function(index, frame)
		local buttons, getters, geometry = {}, {}, {}
		for i, button in ipairs(frame.buttons) do buttons[i] = button end
		local function Bind(object)
			local methods = {};for _, key in ipairs(METHODS) do methods[key] = object[key] end
			getters[object] = methods
			geometry[object] = ObserveDock(object)
		end
		Bind(frame);Bind(E.movers[frame.eldoMover]);Bind(frame.backdrop)
		for _, button in ipairs(buttons) do Bind(button) end
		created[index] = { frame = frame, buttons = buttons, list = frame.buttons, backdrop = frame.backdrop, getters = getters, geometry = geometry, ready = false }
	end
	dockLayout = function(index)
		local own, root, db, profile = created[index], E.db, M.db, E.profileName
		local getter, admit = targetGeneration, targetAdmit
		local token
		if Same(E.GetApplyGeneration, getter) and Same(E.IsCurrentProfile, admit) then token = Invoke(getter, E, "profile") end
		local cfg, values = nil, {}
		if not E.Secret(db) and type(db) == "table" and Plain(rawget(db, "bars")) then cfg = rawget(rawget(db, "bars"), index) end
		if Plain(cfg) then for _, key in ipairs(GEOMETRY) do values[key] = rawget(cfg, key) end end
		if own then own.ready = false end
		return function()
			if own and Same(E.db, root) and Same(M.db, db) and Same(E.profileName, profile)
				and Same(E.GetApplyGeneration, getter) and Same(E.IsCurrentProfile, admit)
				and Number(token) and token >= 1 and Same(Invoke(getter, E, "profile"), token) and Same(Invoke(admit, E), true) then
				if not Plain(cfg) then return end
				for _, key in ipairs(GEOMETRY) do if not Same(rawget(cfg, key), values[key]) then return end end
				own.ready, own.token, own.settings, own.values = true, token, cfg, values
			end
		end
	end
	local function Read(mode, request)
		local root, db, profile, modules, movers = E.db, M.db, E.profileName, E.modules, E.movers
		local rootSeal, liveGeometry, readGeometrySeal, paintGeometrySeal, nativeProof
		local measureChecks, measureCustody = {}, nil

		local admit, generation = targetAdmit, targetGeneration
		if not Plain(root) or not Plain(modules) or not Same(rawget(modules, "ActionBars"), M)
			or E.Secret(db) or type(db) ~= "table" or not Plain(rawget(db, "bars")) or not Plain(movers)
			or E.Secret(admit) or type(admit) ~= "function" or E.Secret(generation) or type(generation) ~= "function"
			or not Same(rawget(E, "Secret"), Secret) or not Same(rawget(E, "PlainCallAll"), plainCall)
			or not Same(E.IsCurrentProfile, admit) or not Same(E.GetApplyGeneration, generation) or not Same(E.ModuleEnabledValue, targetEnabled)
			or not Same(Invoke(admit, E), true) then return { kind = "pending" } end
		local token, settings, active, meta = Invoke(generation, E, "profile"), rawget(db, "bars"), M.active, getmetatable(db)
		local moduleMeta = getmetatable(M)
		local frames = M.bars
		if not Plain(frames) or E.Secret(meta) then return { kind = "unavailable" } end
		if not Number(token) or token < 1 or token % 1 ~= 0 or E.Secret(active) or type(active) ~= "boolean" then return { kind = "unavailable" } end
		local hidden, paint, readEnabled, geometryRead = hiddenSource, paintSource, targetEnabled, paintGeometrySource
		local partsRead, measure = partsSource, surfaceMeasure
		local enabled = Invoke(readEnabled, E, M)
		if E.Secret(enabled) or type(enabled) ~= "boolean" then return { kind = "unavailable" } end
		local nativePhase = {}
		local function SourceCurrent(phase)
			return not request.invalid and Matches(rawget(E, "MoverAuthoritySource"), moverGeometrySource)
				and Matches(rawget(E, "Secret"), Secret) and Matches(rawget(E, "PlainCallAll"), plainCall)
				and (not rootSeal or rootSeal())
				and (phase == nativePhase or not liveGeometry or liveGeometry())
				and (not measureCustody or measureCustody())
				and ((not request.checking and request.complete) or not readGeometrySeal or readGeometrySeal())
				and Matches(rawget(E, "db"), root) and Matches(rawget(E, "profileName"), profile)
				and Matches(rawget(E, "modules"), modules) and Plain(modules) and Matches(rawget(E, "movers"), movers) and Plain(movers)
				and Matches(getmetatable(M), moduleMeta) and Matches(rawget(M, "bars"), frames) and Plain(frames)
				and Matches(rawget(modules, "ActionBars"), M) and Matches(rawget(M, "db"), db) and Matches(getmetatable(db), meta)
				and Matches(rawget(db, "bars"), settings) and Plain(settings)
				and Matches(rawget(M, "active"), active) and Matches(hiddenSource, hidden) and Matches(paintSource, paint) and Matches(paintGeometrySource, geometryRead)
				and Matches(rawget(M, "ButtonParts"), partsRead) and Matches(rawget(E, "SurfaceMeasure"), measure)
				and Matches(rawget(E, "IsCurrentProfile"), admit) and Matches(rawget(E, "GetApplyGeneration"), generation)
				and Matches(rawget(E, "ModuleEnabledValue"), readEnabled)
		end
		local function PaintCurrent()
			for _, check in ipairs(measureChecks) do if not check() then return false end end
			return true
		end
		local function Current()
			if not SourceCurrent() or (not nativeProof and not PaintCurrent()) then return false end
			if nativeProof then return true end
			local now = Invoke(generation, E, "profile")
			if not SourceCurrent() or not PaintCurrent() or not Matches(now, token) then return false end
			local admitted = Invoke(admit, E)
			if not SourceCurrent() or not PaintCurrent() or not Matches(admitted, true) then return false end
			local on = Invoke(readEnabled, E, M)
			return SourceCurrent() and PaintCurrent() and Matches(on, enabled)
		end
		local function CheckedReturn(...)
			if not Current() then error("Passive dock source changed") end
			return ...
		end
		local function Call(fn, ...)
			if not Current() then error("Passive dock source changed") end
			return CheckedReturn(Invoke(fn, ...))
		end
		if not Current() then return { kind = "unavailable" } end
		if mode == "notice" or not active or not enabled then return { kind = active and enabled and "live" or "inactive", current = Current } end
		if type(surfaceRead) ~= "function" or type(surfaceSource) ~= "function" or not surfaceSource() then return { kind = "unavailable" } end
		measureCustody = surfaceSource
		if type(hidden) ~= "function" or type(paint) ~= "function" then return { kind = "pending" } end
		if not Same(rawget(E, "MoverAuthoritySource"), moverGeometrySource) or type(geometryFactory) ~= "function" or type(paintGeometrySource) ~= "function" then return { kind = "unavailable" } end
		local paintGeometryOwns
		readGeometrySeal = geometryFactory()
		paintGeometrySeal, paintGeometryOwns = paintGeometrySource()
		if type(readGeometrySeal) ~= "function" or type(paintGeometrySeal) ~= "function" or type(paintGeometryOwns) ~= "function"
			or not readGeometrySeal(true) or not paintGeometrySeal(true) then return { kind = "unavailable" } end
		local ownGeometry, ownSources, dockEpoch = {}, {}, dockGeometryEpoch
		for _, index in ipairs(INDEXES) do
			local own = created[index]
			if not own or not Plain(own.geometry) then return { kind = "pending" } end
			for object in pairs(own.getters) do
				local record = rawget(own.geometry, object)
				if not record or type(record.capture) ~= "function" or type(record.source) ~= "function" or not record.source() then return { kind = "unavailable" } end
				ownGeometry[#ownGeometry + 1] = record.capture()
				ownSources[#ownSources + 1] = record.source
			end
		end
		liveGeometry = function(full)
			if not Same(rawget(E, "MoverAuthoritySource"), moverGeometrySource) or not Same(dockGeometryEpoch, dockEpoch) or not paintGeometrySeal(full) then return false end
			for _, check in ipairs(ownGeometry) do if not check() then return false end end
			if full then for _, check in ipairs(ownSources) do if not check() then return false end end end
			return true
		end
		local uiRoot = rawget(_G, "UIParent")
		if Secret(uiRoot) or (type(uiRoot) ~= "table" and type(uiRoot) ~= "userdata") then return { kind = "unavailable" } end
		local rootMeta = getmetatable(uiRoot)
		local rootIndex = type(rootMeta) == "table" and rawget(rootMeta, "__index") or nil
		local rootDirect = type(uiRoot) == "table" and rawget(uiRoot, "GetEffectiveScale") or nil
		local rootInherited = type(rootIndex) == "table" and rawget(rootIndex, "GetEffectiveScale") or nil
		local rootRead = rootDirect or rootInherited or uiRoot.GetEffectiveScale
		rootSeal = function()
			return Matches(rawget(_G, "UIParent"), uiRoot) and Matches(getmetatable(uiRoot), rootMeta)
				and (type(rootMeta) ~= "table" or Matches(rawget(rootMeta, "__index"), rootIndex))
				and (type(uiRoot) ~= "table" or Matches(rawget(uiRoot, "GetEffectiveScale"), rootDirect))
				and (type(rootIndex) ~= "table" or Matches(rawget(rootIndex, "GetEffectiveScale"), rootInherited))
		end
		if Secret(rootRead) or type(rootRead) ~= "function" or not Current() then return { kind = "unavailable" } end
		local nativeRoot = nativeBinding and nativeBinding(uiRoot)
		if not nativeRoot or not Same(rootRead, nativeRoot.getters.GetEffectiveScale) then return { kind = "unavailable" } end
		local rootScale = Call(rootRead, uiRoot)
		if not Number(rootScale) or rootScale <= 0 then return { kind = "unavailable" } end
		local checks, custodyChecks, methodChecks, nativeChecks, nodes, obstacles = {}, {}, {}, {}, {}, {}
		local receiverChecks = {}
		local nativePhaseChecks, nativePhaseReferences = {}, {}
		local nativeGeometryChecks = {}
		local function Metadata(check)
			checks[#checks + 1], custodyChecks[#custodyChecks + 1] = check, check
		end
		local function ReferenceCurrent(object)
			if Secret(object) then return false end
			if object == nil then return true end
			if type(existingGeometry) == "function" then
				local capture, source = existingGeometry(object)
				if type(capture) == "function" and type(source) == "function" and source() then return true end
			end
			for _, own in pairs(created) do
				local record = own.geometry and rawget(own.geometry, object)
				if record and record.source() then return true end
			end
			return paintGeometryOwns(object)
		end
		local function Object(object, force, surface, expected, expectedParent)
			if E.Secret(object) or (type(object) ~= "table" and type(object) ~= "userdata") then return end
			if not Plain(expected) then return end
			local methods = {}
			local native = nativeBinding and nativeBinding(object)
			if not native then return end
			local objectMeta, rawMethods = getmetatable(object), {}
			local index = type(objectMeta) == "table" and rawget(objectMeta, "__index") or nil
			for _, key in ipairs(METHODS) do
				if not SourceCurrent() then return end
				local direct = type(object) == "table" and rawget(object, key) or nil
				local inherited = type(index) == "table" and rawget(index, key) or nil
				local fn = direct or inherited
				if E.Secret(fn) then return end
				if type(fn) == "nil" then fn = object[key];if not Current() then return end end
				if E.Secret(fn) or type(fn) ~= "function" or not Same(fn, rawget(expected, key)) or not Same(fn, native.getters[key]) then return end
				methods[key] = fn
				rawMethods[key] = { value = direct, index = inherited }
			end
			local function MethodCurrent(key)
				return Matches(rawget(expected, key), methods[key])
					and (type(object) ~= "table" or Matches(rawget(object, key), rawMethods[key].value))
					and (type(index) ~= "table" or Matches(rawget(index, key), rawMethods[key].index))
			end
			local function MethodsCurrent(selected)
				if not Same(getmetatable(object), objectMeta) or (type(objectMeta) == "table" and not Same(rawget(objectMeta, "__index"), index))
					or not Plain(expected) then return false end
				if selected then return MethodCurrent("GetParent") and MethodCurrent(selected) end
				for _, key in ipairs(METHODS) do if not MethodCurrent(key) then return false end end
				return true
			end
			methodChecks[#methodChecks + 1] = MethodsCurrent
			local savedParent = expectedParent
			local pointReadPhase = {}
			local function ReadSourceCurrent(phase)
				if phase == pointReadPhase then return not request.invalid end
				return SourceCurrent(phase)
			end
			local function CheckedValues(phase, key, ...)
				if not ReadSourceCurrent(phase) or not MethodsCurrent(key) or not native.source(key) then error("Passive dock receiver changed") end
				return ...
			end
			local function Query(phase, key, read, ...)
				if not ReadSourceCurrent(phase) or not MethodsCurrent(key) then error("Passive dock receiver changed") end
				return CheckedValues(phase, key, NativeValues(pcall(read, object, ...)))
			end
			local function MethodValues(key, ...)
				if not MethodsCurrent(key) then error("Passive dock getter changed") end
				return ...
			end
			local function QueryObject(phase, key, ...)
				if not ReadSourceCurrent(phase) or not MethodsCurrent(key) or not native.source(key) then error("Passive dock receiver changed") end
				local fn = methods[key]
				if phase ~= pointReadPhase and not nativeProof and rawMethods[key].value == nil and rawMethods[key].index == nil then
					fn = object[key]
					if not Current() or not MethodsCurrent(key) or not Same(fn, methods[key]) then error("Passive dock getter changed") end
				end
				local parent = Query(phase, key, methods.GetParent)
				if not MethodsCurrent(key) or E.Secret(parent) or not Same(parent, savedParent) then error("Passive dock parent changed") end
				if key == "GetParent" then return parent end
				return MethodValues(key, Query(phase, key, fn, ...))
			end
			-- The captured getters of the game's own frame are read one right after
			-- the other and are taken to have no side effects here.
			-- No surface/provider callback or cross-call cache enters this block.
			local function ScalarReturn(ok, ...)
				if not ok then return false end
				for i = 1, select("#", ...) do if Secret((select(i, ...))) then return false end end
				return true, ...
			end
			local function Scalar(key)
				return ScalarReturn(pcall(methods[key], object))
			end
			local function NativeScalars(phase)
				if not SourceCurrent(phase) or not MethodsCurrent() or not native.source() then return end
				local epoch = native.capture()
				if type(epoch) ~= "function" or not epoch() then return end
				local parentOK, parent = Scalar("GetParent")
				if not parentOK or not Same(parent, savedParent) then return end
				local countOK, count = Scalar("GetNumPoints")
				if not countOK or not Number(count) or count < 0 or count > 4 or count % 1 ~= 0 then return end
				local scaleOK, scale = Scalar("GetEffectiveScale")
				if not scaleOK or not Number(scale) or scale <= 0 then return end
				local shownOK, shown = Scalar("IsShown")
				if not shownOK or type(shown) ~= "boolean" then return end
				local visibleOK, visible = Scalar("IsVisible")
				if not visibleOK or type(visible) ~= "boolean" then return end
				local l, b, w, h
				if visible or force then
					local rectOK
					rectOK, l, b, w, h = Scalar("GetRect")
					if not rectOK or not Number(l) or not Number(b) or not Number(w) or w <= 0 or not Number(h) or h <= 0 then return end
				end
				if not SourceCurrent(phase) or not MethodsCurrent() or not native.source() or not epoch() then return end
				return true, parent, count, scale, shown, visible, l, b, w, h
			end
			local function NativePoints(phase, count, initial, scalar)
				if Secret(scalar) or (scalar ~= nil and type(scalar) ~= "boolean") then return end
				if not Number(count) or count < 0 or count > 4 or count % 1 ~= 0 then return end
				if phase ~= nativePhase and not initial then return end
				if not SourceCurrent(phase) or not MethodsCurrent() or not native.source() then return end
				local epoch = native.capture()
				if type(epoch) ~= "function" or not epoch() then return end
				local points = not scalar and {}
				local p1, r1, rp1, x1, y1, p2, r2, rp2, x2, y2
				local p3, r3, rp3, x3, y3, p4, r4, rp4, x4, y4
				-- Only the admitted intrinsic parent/point getters run between
				-- these seals. Keep receiver checks and getter order; defer the
				-- repeated whole-dock geometry scan until this read completes.
				for i = 1, count do
					local p, rel, rp, x, y = QueryObject(pointReadPhase, "GetPoint", i)
					if Secret(p) or type(p) ~= "string" or Secret(rel) or Secret(rp) or type(rp) ~= "string"
						or not Number(x) or not Number(y) then return end
					if scalar then
						if i == 1 then p1, r1, rp1, x1, y1 = p, rel, rp, x, y
						elseif i == 2 then p2, r2, rp2, x2, y2 = p, rel, rp, x, y
						elseif i == 3 then p3, r3, rp3, x3, y3 = p, rel, rp, x, y
						else p4, r4, rp4, x4, y4 = p, rel, rp, x, y end
					else points[i] = { p, rel, rp, x, y } end
				end
				if not SourceCurrent(phase) or not MethodsCurrent() or not native.source() or not epoch() then return end
				if scalar then return true, epoch, p1, r1, rp1, x1, y1, p2, r2, rp2, x2, y2, p3, r3, rp3, x3, y3, p4, r4, rp4, x4, y4 end
				return points, epoch
			end
			local saved, paintCheck
			local function Capture(compare, phase)
				if not SourceCurrent(phase) or not MethodsCurrent() then return end
				local parent, count, scale, shown, visible, l, b, w, h
				if native.native == true then
					local good
					good, parent, count, scale, shown, visible, l, b, w, h = NativeScalars(phase)
					if not good then return end
				else
					parent, count = QueryObject(nil, "GetParent"), QueryObject(nil, "GetNumPoints")
					scale = QueryObject(nil, "GetEffectiveScale")
					shown, visible = QueryObject(nil, "IsShown"), QueryObject(nil, "IsVisible")
					if Same(visible, true) or force then l, b, w, h = QueryObject(nil, "GetRect") end
				end
				local paintInsets = compare and saved.paint or { 0, 0, 0, 0 }
				if nativeProof and saved then paintInsets = saved.paint
				elseif surface and Same(visible, true) and saved and paintCheck then
					if not paintCheck() then return end
					paintInsets = saved.paint
				elseif surface and Same(visible, true) then
					local metrics, custody = Call(surfaceRead, object)
					if not Plain(metrics) or not Plain(rawget(metrics, "paint")) or type(custody) ~= "function" or not custody() then return end
					if not paintCheck then paintCheck = custody;measureChecks[#measureChecks + 1] = custody end
					for i = 1, 4 do
						local inset = rawget(metrics.paint, i)
						if not Number(inset) or inset < 0 then return end
						paintInsets[i] = inset
					end
				end
				if E.Secret(parent) or not Number(count) or count < 0 or count > 4 or count % 1 ~= 0
					or not Number(scale) or scale <= 0 or E.Secret(shown) or type(shown) ~= "boolean"
					or E.Secret(visible) or type(visible) ~= "boolean" then return end
				if (visible or force) and (not Number(l) or not Number(b) or not Number(w) or w <= 0 or not Number(h) or h <= 0) then return end
				if compare and count ~= #saved.points then return end
				local points = not compare and {}
				local nativePoints, pointEpoch
				local p1, r1, rp1, x1, y1, p2, r2, rp2, x2, y2
				local p3, r3, rp3, x3, y3, p4, r4, rp4, x4, y4
				if native.native == true and (not compare or phase == nativePhase) then
					nativePoints, pointEpoch, p1, r1, rp1, x1, y1, p2, r2, rp2, x2, y2, p3, r3, rp3, x3, y3, p4, r4, rp4, x4, y4 = NativePoints(phase, count, not compare, compare)
					if not nativePoints then return end
				end
				for i = 1, count do
					local p, rel, rp, x, y
					if nativePoints then
						if compare then
							if i == 1 then p, rel, rp, x, y = p1, r1, rp1, x1, y1
							elseif i == 2 then p, rel, rp, x, y = p2, r2, rp2, x2, y2
							elseif i == 3 then p, rel, rp, x, y = p3, r3, rp3, x3, y3
							else p, rel, rp, x, y = p4, r4, rp4, x4, y4 end
						else
							local point = nativePoints[i]
							p, rel, rp, x, y = point[1], point[2], point[3], point[4], point[5]
						end
					else p, rel, rp, x, y = QueryObject(phase, "GetPoint", i) end
					if E.Secret(p) or type(p) ~= "string" or E.Secret(rel) or E.Secret(rp) or type(rp) ~= "string"
						or not Number(x) or not Number(y)
						or (phase == nativePhase and rel ~= nil and not nativePhaseReferences[rel]) or not ReferenceCurrent(rel) then return end
					if compare then
						local point = saved.points[i]
						if not Same(p, point[1]) or not Same(rel, point[2]) or not Same(rp, point[3])
							or not Same(x, point[4]) or not Same(y, point[5]) then return end
					else points[i] = { p, rel, rp, x, y } end
				end
				if not SourceCurrent(phase) or not MethodsCurrent()
					or (pointEpoch and (not native.source() or not pointEpoch())) then return end
				if compare then
					return Same(parent, saved.parent) and Same(l, saved.l) and Same(b, saved.b)
						and Same(w, saved.w) and Same(h, saved.h) and Same(scale, saved.scale)
						and Same(shown, saved.shown) and Same(visible, saved.visible)
				end
				return { parent = parent, points = points, l = l, b = b, w = w, h = h, scale = scale, shown = shown, visible = visible, paint = paintInsets }
			end
			saved = Capture()
			if not saved then return end
			savedParent = saved.parent
			receiverChecks[object] = function() return MethodsCurrent() and Same(QueryObject(nil, "GetParent"), savedParent) and MethodsCurrent() end
			local function GeometryCurrent(phase)
				return Capture(true, phase) == true
			end
			nativePhaseChecks[#nativePhaseChecks + 1] = function()
				return native.native == true and MethodsCurrent() and native.source()
			end
			if saved.parent ~= nil then nativePhaseReferences[saved.parent] = true end
			for _, point in ipairs(saved.points) do if point[2] ~= nil then nativePhaseReferences[point[2]] = true end end
			checks[#checks + 1], nativeChecks[#nativeChecks + 1] = GeometryCurrent, GeometryCurrent
			nativeGeometryChecks[GeometryCurrent] = true
			local ratio = saved.scale / rootScale
			if saved.visible or force then
				saved.rect = { (saved.l - saved.paint[1]) * ratio, (saved.b - saved.paint[4]) * ratio,
					(saved.l + saved.w + saved.paint[2]) * ratio, (saved.b + saved.h + saved.paint[3]) * ratio }
				saved.width, saved.height = saved.w * ratio, saved.h * ratio
			end
			saved.ratio = ratio
			return saved
		end
		for _, index in ipairs(INDEXES) do
			local own, cfg = created[index], rawget(settings, index)
			local name = "EldoUI_ActionBar" .. index
			local mover = rawget(movers, name)
			if own and (not own.ready or not Same(own.token, token)) then return { kind = "pending" } end
			if not own or not Plain(cfg) or not Plain(own.list) or not Same(rawget(frames, index), own.frame) or not Same(own.frame.buttons, own.list)
				or not Same(own.frame.backdrop, own.backdrop) or E.Secret(mover) or not mover or not Same(mover.frame, own.frame)
				or not Same(mover.module, "ActionBars") then return { kind = "unavailable" } end
			if not Same(cfg, own.settings) then return { kind = "pending" } end
			for _, key in ipairs(GEOMETRY) do if not Same(rawget(cfg, key), rawget(own.values, key)) then return { kind = "pending" } end end
			local hiddenState = Call(hidden, index)
			local paintState = Call(paint, index)
			if not Plain(hiddenState) or hiddenState.kind ~= "live" or type(hiddenState.current) ~= "function"
				or not Plain(paintState) or paintState.kind ~= "live" or type(paintState.current) ~= "function"
				or not Same(Invoke(hiddenState.current), true) or not Same(Invoke(paintState.current), true) then return { kind = "unavailable" } end
			local hiddenCurrent, paintCurrent, paintGetters, paintParts = hiddenState.current, paintState.current, paintState.getters, paintState.parts
			checks[#checks + 1] = function()
				return Same(rawget(hiddenState, "current"), hiddenCurrent) and Same(rawget(hiddenState, "kind"), "live")
					and Same(rawget(paintState, "current"), paintCurrent) and Same(rawget(paintState, "kind"), "live")
					and Same(rawget(paintState, "getters"), paintGetters) and Same(rawget(paintState, "parts"), paintParts)
					and Same(Call(hiddenCurrent), true) and Same(Call(paintCurrent), true)
			end
			local plans = rawget(M, "hiddenPlans")
			if not Plain(plans) then return { kind = "unavailable" } end
			local plan, planPoint, planShape, planSize, planValues = rawget(plans, index), nil, nil, nil, {}
			if plan then
				if not Plain(plan) or not Plain(rawget(plan, "point")) then return { kind = "unavailable" } end
				planPoint, planShape, planSize = rawget(plan, "point"), rawget(plan, "shape"), rawget(plan, "size")
				for i = 1, 5 do planValues[i] = rawget(planPoint, i) end
			end
			local mouseover, originalArt, hudTray = rawget(cfg, "hiddenMouseover"), rawget(own.frame, "originalArt"), rawget(own.frame, "hudTray")
			custodyChecks[#custodyChecks + 1] = function()
				if not Same(rawget(M, "hiddenPlans"), plans) or not Same(rawget(plans, index), plan)
					or not Same(rawget(cfg, "hiddenMouseover"), mouseover)
					or not Same(rawget(own.frame, "originalArt"), originalArt) or not Same(rawget(own.frame, "hudTray"), hudTray)
					or not Same(rawget(paintState, "getters"), paintGetters) or not Same(rawget(paintState, "parts"), paintParts)
					or not Same(rawget(hiddenState, "current"), hiddenCurrent) or not Same(rawget(paintState, "current"), paintCurrent) then return false end
				if plan then
					if not Plain(plan) or not Same(rawget(plan, "point"), planPoint) or not Plain(planPoint)
						or not Same(rawget(plan, "shape"), planShape) or not Same(rawget(plan, "size"), planSize) then return false end
					for i = 1, 5 do if not Same(rawget(planPoint, i), planValues[i]) then return false end end
				end
				return true
			end
			local enabledBar = rawget(cfg, "enabled")
			if E.Secret(enabledBar) or type(enabledBar) ~= "boolean" then return { kind = "unavailable" } end
			Metadata(function()
				for _, key in ipairs(GEOMETRY) do if not Same(rawget(cfg, key), rawget(own.values, key)) then return false end end
				return Same(rawget(created, index), own) and Same(rawget(frames, index), own.frame) and Plain(own.list)
					and Same(rawget(own.frame, "buttons"), own.list) and Same(rawget(own.frame, "backdrop"), own.backdrop)
					and own.ready and Same(own.token, token)
					and Same(rawget(settings, index), cfg) and Same(rawget(cfg, "enabled"), enabledBar)
					and Same(rawget(movers, name), mover) and Same(rawget(mover, "frame"), own.frame) and Same(rawget(mover, "module"), "ActionBars")
			end)
			local carrier, body = Object(mover, true, false, own.getters[mover], uiRoot), Object(own.frame, false, false, own.getters[own.frame], uiRoot)
			if not carrier or not carrier.rect or not body or not Same(carrier.parent, UIParent) or not Same(body.parent, UIParent)
				or #body.points ~= 1 or not Same(body.points[1][2], mover) or body.points[1][1] ~= "CENTER" or body.points[1][3] ~= "CENTER"
				or body.points[1][4] ~= 0 or body.points[1][5] ~= 0 or #carrier.points ~= 1 then return { kind = "unavailable" } end
			local point = carrier.points[1]
			nodes[name] = { mover = mover, frame = own.frame, width = carrier.width, height = carrier.height,
				scale = carrier.ratio, point = point, rect = carrier.rect, bodyKind = enabledBar and body.visible and "live" or "inactive" }
			if enabledBar and body.visible then obstacles[#obstacles + 1] = { owner = name, rect = body.rect } end
			for i = 1, 12 do
				local button = own.buttons[i]
				if not Same(rawget(own.list, i), button) then return { kind = "unavailable" } end
				local buttonBox = Object(button, false, false, own.getters[button], own.frame)
				if not buttonBox or not Same(buttonBox.parent, own.frame) then return { kind = "unavailable" } end
				Metadata(function() return Same(rawget(own.list, i), button) end)
				if enabledBar and body.visible and buttonBox.visible then obstacles[#obstacles + 1] = { owner = name, rect = buttonBox.rect } end
				local parts = Call(partsRead, M, button)
				if not Plain(parts) then return { kind = "pending" } end
				local backdrop, tint = rawget(parts, "backdrop"), rawget(parts, "tint")
				if E.Secret(backdrop) or (type(backdrop) ~= "table" and type(backdrop) ~= "userdata") or E.Secret(tint) then return { kind = "unavailable" } end
				checks[#checks + 1] = function()
					return Same(Call(partsRead, M, button), parts) and Same(rawget(parts, "backdrop"), backdrop) and Same(rawget(parts, "tint"), tint)
				end
				custodyChecks[#custodyChecks + 1] = function()
					return Plain(parts) and Same(rawget(parts, "backdrop"), backdrop) and Same(rawget(parts, "tint"), tint)
				end
				if not Plain(paintState.getters) then return { kind = "unavailable" } end
				for _, object in ipairs({ backdrop, tint }) do
					local box = Object(object, false, Same(object, backdrop), rawget(paintState.getters, object), Same(object, backdrop) and button or backdrop)
					if not box or not Same(box.parent, Same(object, backdrop) and button or backdrop) then return { kind = "unavailable" } end
					if enabledBar and body.visible and box.visible then obstacles[#obstacles + 1] = { owner = name, rect = box.rect } end
				end
			end
			if own.backdrop then
				local box = Object(own.backdrop, false, true, own.getters[own.backdrop], own.frame)
				if not box or not Same(box.parent, own.frame) then return { kind = "unavailable" } end
				if enabledBar and body.visible and box.visible then obstacles[#obstacles + 1] = { owner = name, rect = box.rect } end
			end
			if not Plain(paintState.parts) then return { kind = "unavailable" } end
			for _, part in ipairs(paintState.parts) do
				if not Plain(part) or E.Secret(rawget(part, "surface")) or type(rawget(part, "surface")) ~= "boolean" then return { kind = "unavailable" } end
				local object, parent, surface = rawget(part, "object"), rawget(part, "parent"), rawget(part, "surface")
				local box = Object(object, false, surface, rawget(paintState.getters, object), parent)
				if not box or not Same(box.parent, parent) then return { kind = "unavailable" } end
				if enabledBar and body.visible and box.visible then obstacles[#obstacles + 1] = { owner = name, rect = box.rect } end
			end
		end
		for _, node in pairs(nodes) do
			local relative, point = node.point[2], node.point
			local parent
			for name, other in pairs(nodes) do if Same(relative, other.mover) then parent = name end end
			if parent then node.parent = parent;node.point = { point[1], parent .. "Mover", point[3], point[4], point[5] }
			else
				-- A saved/manual or hidden position is a measured passive root.
				-- Its live tuple is still checked; no foreign chain is adopted.
				node.point = { "BOTTOMLEFT", "UIParent", "BOTTOMLEFT", 0, 0 };node.root = node.rect
			end
		end
		-- Returned records are read-only snapshots, not new source authority.
		local savedNodes, savedObstacles = {}, {}
		for key, node in pairs(nodes) do
			local saved = { record = node, point = {}, rect = {}, fields = {} }
			for _, field in ipairs({ "mover", "frame", "width", "height", "scale", "parent", "root", "bodyKind" }) do saved.fields[field] = node[field] end
			for i = 1, 5 do saved.point[i] = node.point[i] end
			for i = 1, 4 do saved.rect[i] = node.rect[i] end
			saved.pointRecord, saved.rectRecord = node.point, node.rect
			savedNodes[key] = saved
		end
		for i, obstacle in ipairs(obstacles) do
			savedObstacles[i] = { record = obstacle, owner = obstacle.owner, rect = obstacle.rect,
				values = { obstacle.rect[1], obstacle.rect[2], obstacle.rect[3], obstacle.rect[4] } }
		end
		Metadata(function()
			if not Plain(nodes) or not Plain(obstacles) then return false end
			local count = 0;for _ in pairs(nodes) do count = count + 1 end
			if count ~= 4 or #obstacles ~= #savedObstacles then return false end
			for key, saved in pairs(savedNodes) do
				local node = rawget(nodes, key)
				if not Plain(node) or not Matches(node, saved.record) or not Plain(node.point) or not Plain(node.rect)
					or not Matches(node.point, saved.pointRecord) or not Matches(node.rect, saved.rectRecord) then return false end
				for _, field in ipairs({ "mover", "frame", "width", "height", "scale", "parent", "root", "bodyKind" }) do if not Matches(node[field], saved.fields[field]) then return false end end
				for i = 1, 5 do if not Matches(node.point[i], saved.point[i]) then return false end end
				for i = 1, 4 do if not Matches(node.rect[i], saved.rect[i]) then return false end end
			end
			for i, saved in ipairs(savedObstacles) do
				local obstacle = rawget(obstacles, i)
				if not Plain(obstacle) or not Matches(obstacle, saved.record) or not Matches(obstacle.owner, saved.owner)
					or not Plain(obstacle.rect) or not Matches(obstacle.rect, saved.rect) then return false end
				for k = 1, 4 do if not Matches(obstacle.rect[k], saved.values[k]) then return false end end
			end
			return true
		end)
		local function Custody(receiver, sourceOnly)
			if request.checking or request.custody or (reading and reading ~= request) then request.invalid = true;return false end
			local previous = reading
			request.custody, reading = true, request
			local ok, current = pcall(function()
				if sourceOnly then
					if receiver ~= nil or not SourceCurrent() then return false end
				elseif not Current() then return false end
				for _, check in ipairs(custodyChecks) do if not check() then return false end end
				if sourceOnly then for _, check in ipairs(methodChecks) do if not check() then return false end end end
				local parent = receiverChecks[receiver]
				if parent then
					if not parent() then return false end
					for _, check in ipairs(custodyChecks) do if not check() then return false end end
					-- The parent read can change the profile or the bar's state.
					if not Current() then return false end
				end
				return SourceCurrent()
			end)
			request.custody, reading = nil, previous
			return ok and Same(current, true) and not request.invalid
		end
		local function NativePhaseCurrent()
			for _, check in ipairs(nativePhaseChecks) do if not check() then return false end end
			for object in pairs(nativePhaseReferences) do if not ReferenceCurrent(object) then return false end end
			return true
		end
		local function NativeGeometry()
			if nativeProof then return false end
			nativeProof = true
			local ok, current = pcall(function()
				if not SourceCurrent() or not PaintCurrent() or not liveGeometry(true) or not nativeRoot.source("GetEffectiveScale") then return false end
				local phase = NativePhaseCurrent() and nativePhase or nil
				if not Same(Invoke(nativeRoot.getters.GetEffectiveScale, uiRoot), rootScale) then return false end
				for _, check in ipairs(nativeChecks) do if not check(phase) then return false end end
				for _, check in ipairs(custodyChecks) do if not check() then return false end end
				for _, check in ipairs(methodChecks) do if not check() then return false end end
				if phase and not NativePhaseCurrent() then return false end
				return nativeRoot.source() and liveGeometry(true) and SourceCurrent() and PaintCurrent()
			end)
			nativeProof = nil
			return ok and Same(current, true)
		end
		local function NativeCurrent()
			if request.checking or request.custody or (reading and reading ~= request) then request.invalid = true;return false end
			local previous = reading
			request.checking, reading = true, request
			local ok, current = pcall(NativeGeometry)
			request.checking, reading = nil, previous
			return ok and Same(current, true) and not request.invalid
		end
		local function FinalCurrent()
			if request.checking or (reading and reading ~= request) then request.invalid = true;return false end
			local previous, previousGeometry = reading, readGeometrySeal
			if request.complete then readGeometrySeal = geometryFactory() end
			request.checking, reading = true, request
			local ok, valid = pcall(function()
				if not Current() or not liveGeometry(true) or not Same(Call(rootRead, uiRoot), rootScale) then return false end
				local phase = NativePhaseCurrent() and nativePhase or nil
				if not Current() then return false end
				if phase then
					if not NativePhaseCurrent() then return false end
					for _, check in ipairs(checks) do
						local current
						if nativeGeometryChecks[check] then current = Invoke(check, phase)
						else current = Invoke(check) end
						if not Same(current, true) or not Current() or not NativePhaseCurrent() then return false end
					end
				else
					for _, check in ipairs(checks) do if not Same(Invoke(check), true) or not Current() then return false end end
				end
				if not Current() then return false end
				for _, check in ipairs(custodyChecks) do if not check() then return false end end
				for _, check in ipairs(methodChecks) do if not check() then return false end end
				if phase and not NativePhaseCurrent() then return false end
				return liveGeometry(true) and readGeometrySeal(true) and SourceCurrent() and NativeGeometry()
			end)
			request.checking, reading, readGeometrySeal = nil, previous, previousGeometry
			return ok and Same(valid, true) and not request.invalid
		end
		if not FinalCurrent() then return { kind = "unavailable" } end
		return { kind = "live", nodes = nodes, obstacles = obstacles, current = FinalCurrent }, Custody, NativeCurrent
	end
	local function Snapshot(mode, private)
		if E.Secret(mode) or (mode ~= nil and mode ~= "notice") then return { kind = "unavailable" } end
		if reading then reading.invalid = true;return { kind = "unavailable" } end
		local request = {}
		reading = request
		local ok, value, custody, native = pcall(Read, mode, request)
		reading = nil
		if not ok or request.invalid or not Plain(value) then return { kind = "unavailable" } end
		request.complete = true
		if private then return value, custody, native end
		return value
	end
	function M:DockSnapshot(mode)
		if not Same(self, M) then return { kind = "unavailable" } end
		return Snapshot(mode)
	end
	local snapshot = M.DockSnapshot
	local read = function(mode)
		if not Same(M.DockSnapshot, snapshot) then return { kind = "unavailable" } end
		return Snapshot(mode, true)
	end
	dockPublish = function(publish)
		local fn = E.RefreshWideConsumableLayout
		if not refresh and not E.Secret(fn) and type(fn) == "function" then refresh = fn end
		if Same(fn, refresh) and type(refresh) == "function" then refresh(E, M, read, 4, publish == true) end
	end
	function M:PublishDockBounds() dockPublish(true) end
end

---------------------------------------------------------------------------
-- Small shared helpers (also used by the other files of the module)
---------------------------------------------------------------------------
-- Blizzard frames go here to hide them; it never shows (the core's hidden
-- parent, kept there by E:HideBlizzardFrame).
M.hider = E.BlizzardKeep.hider

-- v0.6 fade keys (one bar) as the shared visibility block. Absent
-- keys had their old default. Returns the block, or nil when the table has
-- none of the old keys.
local LEGACY_RULE = { combat = "combat", nocombat = "nocombat", target = "target",
	combattarget = "combatOrTarget", hidden = "never" }
local function LegacyFade(db, fadeTime)
	if type(db) ~= "table" then return nil end
	local found = false
	for _, key in ipairs({ "visibility", "mouseover", "fadeOutOfCombat", "fadeAlpha", "hideInVehicle" }) do
		if db[key] ~= nil then found = true end
	end
	if not found then return nil end
	local faded = (tonumber(db.fadeAlpha) or 0) / 100
	local block
	if LEGACY_RULE[db.visibility] then
		-- The old rule hid the bar for real outside it.
		block = E:VisibilityFromLegacy(LEGACY_RULE[db.visibility], 0)
	elseif db.mouseover then
		block = E:VisibilityFromLegacy("mouseover", faded)
	elseif db.fadeOutOfCombat then
		block = E:VisibilityFromLegacy("combat", faded)
		-- Old fades never hid the bar; keep it hoverable at 0.
		if faded <= 0 then block.fadedAlpha = 0.05 end
	else
		block = E:VisibilityFromLegacy("always", 0)
	end
	block.hideVehicle = db.hideInVehicle ~= false
	if fadeTime then block.fadeTime = math.max(0, math.min(1, tonumber(fadeTime) or 0.2)) end
	-- Custom conditions used to count only with Show = custom; now a filled
	-- box always wins, so an unused leftover is cleared.
	if db.visibility ~= "custom" then db.customVisibility = "" end
	E:NormalizeVisibility(block)
	db.visibility, db.mouseover, db.fadeOutOfCombat, db.fadeAlpha, db.hideInVehicle = nil, nil, nil, nil, nil
	return block
end

-- Settings older versions saved, moved to their new keys once.
function M:Migrate()
	local db = self.db
	if type(db) ~= "table" then return end
	local fadeTime = db.fadeTime
	local list = {}
	for _, bar in pairs(type(db.bars) == "table" and db.bars or {}) do list[#list + 1] = bar end
	list[#list + 1] = db.pet
	list[#list + 1] = db.stance
	for _, bar in ipairs(list) do
		local block = LegacyFade(bar, fadeTime)
		if block then bar.fade = block end
	end
	db.fadeTime = nil
	self:MoveCooldownLook()
end

-- Cooldown colors and thresholds moved to General: a profile
-- that changed them here takes them along once, so nothing looks different.
local COOLDOWN_LOOK = { "cooldownExpiring", "cooldownTenths", "cooldownColor", "cooldownSecondsColor", "cooldownExpiringColor" }
local function SameValue(a, b)
	if type(a) ~= "table" or type(b) ~= "table" then return a == b end
	for i = 1, 3 do
		if a[i] ~= b[i] then return false end
	end
	return true
end
function M:MoveCooldownLook()
	local db, general = self.db, E.db and E.db.general
	if type(db) ~= "table" or type(general) ~= "table" or db.cooldownLookMoved then return end
	local defaults = self.defaults
	for _, key in ipairs(COOLDOWN_LOOK) do
		local value = db[key]
		if value ~= nil and not SameValue(value, defaults[key]) and SameValue(general[key], E.defaults.general[key]) then
			general[key] = type(value) == "table" and { value[1], value[2], value[3] } or value
		end
	end
	db.cooldownLookMoved = true
end

-- Settings tables replaced by style presets lose keys; fill them back in.
function M:FillDefaults()
	self:Migrate()
	E.ApplyDefaults(self.db, self.defaults)
	if self.NormalizeTextPreset then self:NormalizeTextPreset() end
end

local function Clamp(value, low, high, fallback)
	value = tonumber(value) or fallback
	if value < low then return low end
	if value > high then return high end
	return value
end
M.Clamp = Clamp

-- Movers that should not show in move mode (their frame is off, or the
-- element's Move switch is off). Core/Movers.lua shows every mover, so the
-- module hides its own inactive ones after move mode opens. The mover itself
-- is hidden too: move mode and its test frames skip a hidden mover, so a bar
-- that is off never gets a test-frame stand-in without a box around it.
local inactiveMovers = {}

function M:SetMoverActive(name, active)
	inactiveMovers[name] = not active or nil
	local mover = E.movers[name]
	if mover then mover:SetShown(active and true or false) end
	if mover and E:IsMoveMode() then
		active = active and E:MoveModeAccepts(mover)
		mover.overlay:SetShown(active)
		mover:EnableMouse(active)
	end
end

hooksecurefunc(E, "ToggleMoveMode", function()
	if E:IsMoveMode() then
		for name in pairs(inactiveMovers) do
			local mover = E.movers[name]
			if mover then
				mover.overlay:Hide()
				mover:EnableMouse(false)
			end
		end
	end
	if M.active then M:UpdateAllFades() end
end)

-- Size a frame and keep its mover the size it shows at (movers follow
-- SetSize but not the frame's scale).
function M:SizeFrame(frame, width, height, scale)
	frame:SetSize(width, height)
	frame:SetScale(scale or 1)
	local mover = frame.eldoMover and E.movers[frame.eldoMover]
	if mover then mover:SetSize(width * (scale or 1), height * (scale or 1)) end
end

-- Place an EldoUI frame: on its EldoUI mover when `useMover`, otherwise on
-- top of the Blizzard frame it replaces (Blizzard's Edit Mode position).
function M:PlaceFrame(frame, useMover, blizzardFrame)
	local mover = frame.eldoMover and E.movers[frame.eldoMover]
	-- A Blizzard frame Edit Mode never placed has no position to take over.
	if blizzardFrame and not blizzardFrame:GetCenter() then blizzardFrame = nil end
	frame:ClearAllPoints()
	if useMover or not blizzardFrame then
		if mover then frame:SetPoint("CENTER", mover, "CENTER") end
	else
		frame:SetPoint("CENTER", blizzardFrame, "CENTER")
	end
	if frame.eldoMover then self:SetMoverActive(frame.eldoMover, (useMover or not blizzardFrame) and frame.eldoEnabled ~= false) end
end

---------------------------------------------------------------------------
-- Fading and showing: the shared visibility engine (Core/Visibility.lua).
-- It drives each holder's alpha (allowed in combat); the module adds
-- the secure state driver that really hides a bar, so a hidden bar takes no
-- clicks. Holders: bars 1-8, pet and stance bars.
---------------------------------------------------------------------------
local dragging = false   -- a spell is on the cursor (ACTIONBAR_SHOWGRID)

-- Faded bars show fully in move and keybind mode and while a spell is
-- dragged, so the player can see where to drop it.
local function ForceShow()
	return E:IsMoveMode() or (E.IsKeybindMode and E:IsKeybindMode()) or dragging
end

local function FullAlpha(frame)
	local db = frame.eldoDB
	return Clamp(db and db.alpha, 0, 100, 100) / 100
end

-- Start (or refresh) the fade of `frame` from its settings table `db`
-- (db.fade is the visibility block, db.alpha the full opacity).
-- keepInVehicle: function, true while "Hide in a vehicle" must not apply.
-- Bars that show on mouse over can be linked: hovering any of them shows
-- them all. They share one list of frames the mouse-over test looks at.
local linkedBars = {}

local function Unlink(frame)
	for index = #linkedBars, 1, -1 do
		if linkedBars[index] == frame then table.remove(linkedBars, index) end
	end
end

-- A flyout opened from a bar's button sits outside the bar, so the mouse on
-- it would let a mouse-over bar fade while the flyout still takes clicks.
-- An open flyout (the library's or the game's) whose button belongs to one
-- of these bars counts as the mouse on the bar. Read only, so it works in
-- combat.
local function FlyoutOver(bar, linked)
	for index = 1, 2 do
		local flyout
		if index == 1 then flyout = LAB.GetSpellFlyoutFrame and LAB:GetSpellFlyoutFrame() else flyout = _G.SpellFlyout end
		if flyout and flyout.IsVisible and flyout:IsVisible() and flyout:IsMouseOver() then
			local owner = flyout:GetParent()
			for _ = 1, 4 do
				if not owner then break end
				if owner == bar then return true end
				if linked then
					for _, other in ipairs(linked) do
						if owner == other then return true end
					end
				end
				owner = owner.GetParent and owner:GetParent()
			end
		end
	end
	return false
end

function M:RegisterHolder(frame, db, keepInVehicle)
	frame.eldoDB = db
	frame.eldoKeepInVehicle = keepInVehicle
	self.holders[frame] = true
	if type(db.fade) ~= "table" then db.fade = E:VisibilityDefaults({ hideVehicle = true }) end
	Unlink(frame)
	-- A bar that is On but not Shown follows the hidden-bar rule instead of
	-- its own (kept for when it shows again).
	local block = frame.index and self:FadeBlock(frame.index) or db.fade
	local linked = self.db.linkMouseover and block.show == "mouseover"
	if linked then linkedBars[#linkedBars + 1] = frame end
	E:AttachVisibility(frame, block, {
		alpha = function() return FullAlpha(frame) end,
		forceShow = ForceShow,
		keepInVehicle = keepInVehicle,
		watch = linked and linkedBars or nil,
		alsoOver = function() return FlyoutOver(frame, linked and linkedBars or nil) end,
	})
end

-- "Show mouse-over bars together" or a bar's Show rule changed: relink
-- every bar. Only the fade changes, so this also works in combat.
function M:UpdateMouseoverLink()
	for frame in pairs(self.holders) do
		self:RegisterHolder(frame, frame.eldoDB, frame.eldoKeepInVehicle)
	end
	self:UpdateAllFades()
end

-- The bars linked right now (for the options page and tests).
function M:LinkedMouseoverBars()
	return linkedBars
end

function M:UpdateFade(frame, instant)
	if E:IsVisibilityAttached(frame) then E:UpdateVisibility(frame, instant) end
end

function M:UpdateAllFades(instant)
	for frame in pairs(self.holders) do self:UpdateFade(frame, instant) end
end

-- A holder that no longer shows anything: back to full alpha, no fading.
function M:ReleaseHolder(frame)
	self.holders[frame] = nil
	Unlink(frame)
	E:DetachVisibility(frame)
end

---------------------------------------------------------------------------
-- Visibility drivers (secure, so they work in combat)
---------------------------------------------------------------------------
-- Build the driver for a holder. `base` goes first (for example the pet
-- bar's "[nopet] hide"). The Show rule comes from the shared block: a rule
-- that fades to nothing hides the bar for real; one that fades to a visible
-- alpha (or "Mouse over") keeps it shown and only changes its alpha. A
-- filled custom-conditions box replaces the Show rule (advanced).
-- `keepInVehicle` ignores the block's "Hide in a vehicle" (bar 1 while it
-- shows the vehicle's actions).
function M:VisibilityDriver(db, base, keepInVehicle, block)
	block = block or (type(db.fade) == "table" and db.fade) or {}
	local parts = { "[petbattle] hide" }
	if base and base ~= "" then parts[#parts + 1] = base end
	if block.hideVehicle and not keepInVehicle then parts[#parts + 1] = "[vehicleui][overridebar][possessbar] hide" end
	local custom = block == db.fade and type(db.customVisibility) == "string" and db.customVisibility:find("%S") and db.customVisibility
	if custom then
		parts[#parts + 1] = (custom:gsub(";%s*$", ""))
	else
		-- The shared rule without its vehicle part (handled above).
		-- Talent group and resting are carried as their current state; the
		-- bars are rebuilt when they change (OnEnable).
		local rule = E:VisibilityDriver({
			show = block.show, fadedAlpha = block.fadedAlpha, hideMounted = block.hideMounted,
			groupOnly = block.groupOnly, groupSize = block.groupSize, needFocus = block.needFocus,
			talentGroup = block.talentGroup, hideResting = block.hideResting, instance = E:VisibilityInstanceMode(block),
		}, { staticState = true })
		parts[#parts + 1] = rule or "show"
	end
	return table.concat(parts, "; ")
end

-- Apply a driver, or hide the frame for good. Out of combat only.
function M:SetDriver(frame, driver)
	if driver and frame.eldoDriver == driver then return end
	frame.eldoDriver = driver
	UnregisterStateDriver(frame, "visibility")
	if driver then
		RegisterStateDriver(frame, "visibility", driver)
	else
		frame:Hide()
	end
end

---------------------------------------------------------------------------
-- Gamepad UI: Blizzard swaps to its controller bars; EldoUI's bars step
-- aside when the player wants that (gamepadHide).
---------------------------------------------------------------------------
function M:GamepadActive()
	return E:GamepadUIActive()
end

function M:HiddenForGamepad()
	return self.db.gamepadHide and self:GamepadActive()
end

---------------------------------------------------------------------------
-- Paging
---------------------------------------------------------------------------
local function PageIndex(fn, fallback)
	if C_ActionBar and C_ActionBar[fn] then
		local ok, value = pcall(C_ActionBar[fn])
		if ok and type(value) == "number" and value > 0 then return value end
	end
	return fallback
end

local function ModifierPaging(db)
	local parts = {}
	for _, entry in ipairs({ { "shift", db.pageShift }, { "ctrl", db.pageCtrl }, { "alt", db.pageAlt } }) do
		local bar = tonumber(entry[2]) or 0
		if BARS[bar] then parts[#parts + 1] = ("[mod:%s] %d"):format(entry[1], BARS[bar].page) end
	end
	return parts
end

-- The page driver for bar `index`.
function M:PagingDriver(index)
	local db = self.db.bars[index]
	local parts = {}
	-- Bar 1 shows the vehicle's abilities when asked to, and always when
	-- EldoUI hides Blizzard's override bar (otherwise they'd be unreachable).
	local vehicle = self.db.pageVehicle or (self.OverrideBarHidden and self:OverrideBarHidden())
	if index == 1 and vehicle then
		parts[#parts + 1] = ("[overridebar] %d"):format(PageIndex("GetOverrideBarIndex", 18))
		parts[#parts + 1] = ("[vehicleui][possessbar] %d"):format(PageIndex("GetVehicleBarIndex", 16))
	end
	if type(db.customPaging) == "string" and db.customPaging:find("%S") then
		parts[#parts + 1] = (db.customPaging:gsub(";%s*$", ""))
	end
	for _, part in ipairs(ModifierPaging(db)) do parts[#parts + 1] = part end
	if index == 1 then
		if self.db.pageForms then
			parts[#parts + 1] = ("[shapeshift] %d"):format(PageIndex("GetTempShapeshiftBarIndex", 17))
		end
		for page = 2, 6 do parts[#parts + 1] = ("[bar:%d] %d"):format(page, page) end
		if self.db.pageForms then
			for bonus = 1, 5 do parts[#parts + 1] = ("[bonusbar:%d] %d"):format(bonus, 6 + bonus) end
		end
	end
	parts[#parts + 1] = tostring(BARS[index].page)
	return table.concat(parts, "; ")
end

---------------------------------------------------------------------------
-- Bars
---------------------------------------------------------------------------
-- Move mode's stand-in for a bar with nothing on it: its buttons in the
-- bar's size, spacing, rows, icon crop and key text.
local function StandIn(index)
	return function()
		local db, bar = M.db, M.db and M.db.bars[index]
		if not bar then return nil end
		local text, grid = M:BarText(bar), M.BarGrid and M:BarGrid(index)
		local count = math.max(1, math.min(tonumber(grid and grid.count or bar.buttons) or 12, 12))
		local perRow = tonumber(grid and grid.perRow or bar.perRow) or count
		return "icons", {
			count = count, columns = math.max(1, math.min(perRow, count)), size = bar.size, spacing = bar.spacing,
			keys = text.showHotkey, fontSize = text.hotkeySize, zoom = db.buttonZoom,
		}
	end
end

local function CreateBar(index)
	local info = BARS[index]
	local name = "EldoUI_ActionBar" .. index
	local header = CreateFrame("Frame", name, UIParent, "SecureHandlerStateTemplate")
	header.index = index
	header.buttons = {}
	header.eldoMover = name
	for slot = 1, 12 do
		local button = LAB:CreateButton(slot, name .. "Button" .. slot, header)
		M.UseActionSlotAPI(button)
		-- Every bar can page (bar 1 always, the others through modifier or
		-- custom paging), so each button knows all 18 pages.
		for page = 1, 18 do
			button:SetState(page, "action", (page - 1) * 12 + slot)
		end
		button:SetState(0, "action", (info.page - 1) * 12 + slot)
		header.buttons[slot] = button
		-- Keybind mode (/eui kb): hover the button and press a key.
		E:RegisterKeybindButton(button, info.binding .. slot)
	end
	header:SetAttribute("_onstate-page", [[
		self:SetAttribute("state", newstate)
		control:ChildUpdate("state", newstate)
	]])
	header.backdrop = CreateFrame("Frame", nil, header)
	header.backdrop:SetFrameLevel(math.max(header:GetFrameLevel() - 1, 0))
	header:SetSize(1, 1)
	-- After a move, "Automatic" flyouts point away from the new edge.
	-- The mover's switch (a layout's hidden list) is the bar's Shown switch:
	-- a hidden bar keeps its actions and keys.
	E:CreateMover(header, name, L["Action Bar %d"]:format(index), DEFAULT_POINTS[index], { enabledPath = { "bars", index, "shown" },
		sample = { config = StandIn(index) }, onMoved = function() M:UpdateFlyout(index) end })
	M:RegisterHolder(header, M.db.bars[index])
	-- A bar the visibility driver shows again catches up on the cooldowns
	-- that ran while it was hidden (the cooldown events skip hidden bars).
	header:HookScript("OnShow", function(self) if M.RefreshBarCooldowns then M:RefreshBarCooldowns(self) end end)
	dockCreated(index, header)
	return header
end

-- Bars 1 to 5 always exist; bars 6 to 8 only once they are turned On, so
-- an unused bar makes no buttons, mover or bindings.
local LAZY_FROM = 6
function M:BarWanted(index)
	if index < LAZY_FROM then return true end
	local barDB = self.db and self.db.bars and self.db.bars[index]
	return barDB and barDB.enabled and true or false
end

-- Make the bars that are wanted and missing. Returns true if it made one.
function M:CreateWantedBars()
	local made = false
	for index = 1, NUM_BARS do
		if not self.bars[index] and self:BarWanted(index) then
			self.bars[index] = CreateBar(index)
			made = true
		end
	end
	return made
end

-- Where the first button sits and which way the rest grow.
local GROWTH = {
	TOPLEFT = { "TOPLEFT", 1, -1 },
	TOPRIGHT = { "TOPRIGHT", -1, -1 },
	BOTTOMLEFT = { "BOTTOMLEFT", 1, 1 },
	BOTTOMRIGHT = { "BOTTOMRIGHT", -1, 1 },
}
M.GROWTH = GROWTH

-- Lay out `buttons` (the first `count` shown) in a grid on `frame`. Buttons
-- are `size` wide and `buttonHeight` high (square when it is nil).
-- `perRow` buttons make a row. With `columnsFirst` the buttons fill each
-- column before the next one starts (an upright bar), in a grid of the
-- same number of rows.
-- Returns the frame's width and height.
function M:GridLayout(frame, buttons, count, perRow, size, spacing, growth, buttonHeight, columnsFirst)
	perRow = math.max(1, math.min(count, perRow))
	local rows = math.ceil(count / perRow)
	local columns = columnsFirst and math.ceil(count / rows) or perRow
	local grow = GROWTH[growth] or GROWTH.TOPLEFT
	local w, h = size, buttonHeight or size
	for slot, button in ipairs(buttons) do
		button:ClearAllPoints()
		button:SetSize(w, h)
		if slot <= count then
			local column, row
			if columnsFirst then
				column, row = math.floor((slot - 1) / rows), (slot - 1) % rows
			else
				column, row = (slot - 1) % perRow, math.floor((slot - 1) / perRow)
			end
			button:SetPoint(grow[1], frame, grow[1], grow[2] * column * (w + spacing), grow[3] * row * (h + spacing))
		end
	end
	local width = math.max(1, columns * w + (columns - 1) * spacing)
	local height = math.max(1, rows * h + (rows - 1) * spacing)
	return width, height
end

-- Button width and height of a bar from its size and shape. The
-- size is the width; flat shapes are lower.
function M:ButtonSize(barDB)
	local width = Clamp(barDB.size, 16, 80, 40)
	local ratio = ASPECTS[barDB.aspect] or 1
	return width, math.max(8, math.floor(width / ratio + 0.5))
end
M.ASPECTS = ASPECTS

-- Should EldoUI's buttons only be dragged off with the pick-up key? They
-- follow the game's "Lock action bars" setting like Blizzard's buttons (the
-- Buttons tab can change that setting, Buttons.lua).
function M:BarsLocked()
	return GetCVarBool and GetCVarBool("lockActionBars") and true or false
end

-- flat: keep the flat box under every skin (its edge carries a color, the
-- pet's happiness).
function M:UpdateBackdrop(frame, db, flat)
	local backdrop = frame.backdrop
	if not backdrop then return end
	if db.backdrop then
		local pad = db.backdropPadding or 4
		backdrop:ClearAllPoints()
		backdrop:SetPoint("TOPLEFT", frame, "TOPLEFT", -pad, pad)
		backdrop:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", pad, -pad)
		-- A native skin frames the bar background in its own material, see-
		-- through like the flat one; the five classic skins keep the flat box.
		if not flat and E.Skins and E.Skins.IsNative(E:SkinPart("actionbuttons")) then
			E:PaintSurface(backdrop, "panel", "actionbuttons", { transparent = true })
		else
			E:ReleaseSurface(backdrop)
			E:SetTemplate(backdrop, true)
		end
		backdrop:Show()
	else
		backdrop:Hide()
	end
	-- Bar 1 under Vanilla Original: the classic tray and end caps.
	if self.PaintOriginalTray then self:PaintOriginalTray(frame, db) end
	-- Bars 1 and 2: the HUD tray behind both (Buttons.lua).
	if self.UpdateHudTray and self.bars and (frame == self.bars[1] or frame == self.bars[2]) then self:UpdateHudTray() end
end

-- Flyouts open away from the screen edge the bar sits next to.
function M:FlyoutDirection(frame, setting, vertical)
	if setting and setting ~= "AUTO" then return setting end
	local x, y = frame:GetCenter()
	local width, height = UIParent:GetSize()
	if not x then return "UP" end
	if vertical then return x > width / 2 and "LEFT" or "RIGHT" end
	return y > height / 2 and "DOWN" or "UP"
end

-- Is EldoUI's bar `index` on right now?
function M:BarActive(index)
	return self.active and self.db.bars[index].enabled
end

-- Which bar shows each page of 12 action slots: every bar's own page,
-- and bar 1 also pages 2 and 7-10 (bar paging and the stance, form and
-- stealth pages).
local PAGE_BAR = { [2] = 1, [7] = 1, [8] = 1, [9] = 1, [10] = 1 }
for index, info in ipairs(BARS) do PAGE_BAR[info.page] = index end

-- Show rules that keep a bar out of sight in a fight: "Never", "Out of
-- combat" and "Mouse over" (whatever their faded opacity). Every other
-- rule, and custom macro conditions, count as shown.
local HIDDEN_RULES = { never = true, nocombat = true, mouseover = true }

-- Is action slot `slot` on a button the player can't see? True when the
-- button isn't drawn: the EldoUI bar that shows it is turned off or kept
-- off by the layout (and Blizzard's bar of that number isn't showing
-- instead), or the button is past the bar's button count (M:ButtonShown
-- answers this part when the module has it). Also true when the bar's
-- opacity is 0 or its Show rule is one of HIDDEN_RULES. False while this
-- module is off (Blizzard's bars show every slot). nil for a slot no bar
-- shows. Used by the Cooldown Manager's key text.
function M:SlotButtonHidden(slot)
	if not (self.active and type(self.db) == "table" and type(self.db.bars) == "table") then return false end
	slot = tonumber(slot)
	if not slot or slot < 1 then return nil end
	local index = PAGE_BAR[math.floor((slot - 1) / 12) + 1]
	local barDB = index and self.db.bars[index]
	if type(barDB) ~= "table" then return nil end
	local button = (slot - 1) % 12 + 1
	if not barDB.enabled or barDB.shown == false then
		local bar = _G[BARS[index].blizzard]
		return not (self:BlizzardBarShown(index) and bar and bar.IsVisible and bar:IsVisible())
	end
	if self.ButtonShown then
		if not self:ButtonShown(index, button) then return true end
	elseif button > math.floor(Clamp(barDB.buttons, 1, 12, 12)) then
		return true
	end
	if (tonumber(barDB.alpha) or 100) <= 0 then return true end
	local custom = type(barDB.customVisibility) == "string" and barDB.customVisibility:find("%S")
	local block = type(barDB.fade) == "table" and barDB.fade
	return not custom and block and HIDDEN_RULES[block.show] or false
end

-- Should EldoUI's bar sit on its own mover (true) or on Blizzard's bar?
function M:BarUsesMover(index)
	return E:BlizzardAllowed(BARS[index].element, "move") or not E:BlizzardAllowed(BARS[index].element)
end

-- Flyout direction of one bar where it sits now.
local function BarFlyout(header, barDB)
	local grid = M:BarGrid(header.index)
	local vertical = math.min(grid.count, grid.perRow or 12) == 1 and grid.count > 1
	return M:FlyoutDirection(header, barDB.flyout, vertical)
end

-- A bar was moved: re-point its "Automatic" flyouts. Button config is a
-- protected change, so it waits for the end of combat.
function M:UpdateFlyout(index)
	local header = self.bars[index]
	if not self.active or not header then return end
	E:RunOutOfCombat(function()
		local barDB = self.db.bars[index]
		local flyout = BarFlyout(header, barDB)
		if flyout == header.eldoFlyout then return end
		header.eldoFlyout = flyout
		local grid = self:BarGrid(index)
		for slot, button in ipairs(header.buttons) do
			button:UpdateConfig(self:ButtonConfig(BARS[index].binding .. slot, barDB, flyout))
			self:StyleButton(button, grid.width, grid.height, barDB)
		end
	end)
end

local function LayoutBar(header, index)
	local db = M.db
	local barDB = db.bars[index]
	local completeDock = dockLayout(index)
	-- The grid drawn: the bar's own, or the small shape of a hidden bar.
	-- Buttons past the drawn count keep their action and key.
	local grid = M:BarGrid(index)
	local count = grid.count
	local buttonWidth, buttonHeight = grid.width, grid.height
	local width, height = M:GridLayout(header, header.buttons, count, grid.perRow, buttonWidth, grid.spacing, grid.growth, buttonHeight,
		grid.columns)
	M:SizeFrame(header, width, height, grid.scale)
	M:UpdateBackdrop(header, barDB)

	local flyout = BarFlyout(header, barDB)
	header.eldoFlyout = flyout
	local locked = M:BarsLocked()
	local fallback = M.HiddenAlphaFallback and M:HiddenAlphaFallback()
	local mouse = not barDB.clickThrough and (not M.HiddenMouseAllowed or M:HiddenMouseAllowed(index))
	for slot, button in ipairs(header.buttons) do
		button:UpdateConfig(M:ButtonConfig(BARS[index].binding .. slot, barDB, flyout))
		M:StyleButton(button, buttonWidth, buttonHeight, barDB)
		-- Locked bars: dragging needs the pick-up key (LibActionButton
		-- checks this attribute together with the PICKUPACTION modifier).
		button:SetAttribute("buttonlock", locked or nil)
		if slot <= count then
			button:EnableMouse(mouse)
			button:SetAttribute("statehidden", nil)
			-- Full alpha, except an empty slot on a bar that hides its empty
			-- slots while no spell is dragged.
			button:SetAlpha((dragging or button.config.showGrid or button:HasAction()) and 1 or 0)
			button:Show()
		elseif fallback then
			-- Hidden buttons kept invisible (E:HiddenButtonsMode): alpha 0, no clicks.
			button:EnableMouse(false)
			button:SetAttribute("statehidden", nil)
			button:SetAlpha(0)
			button:Show()
		else
			button:EnableMouse(mouse)
			button:SetAttribute("statehidden", true)
			button:SetAlpha(1)
			button:Hide()
		end
	end

	local blizzardBar = _G[BARS[index].blizzard]
	header.eldoEnabled = barDB.enabled
	M:PlaceFrame(header, M:BarUsesMover(index), blizzardBar)

	-- Paging and visibility.
	RegisterStateDriver(header, "page", M:PagingDriver(index))
	local show = barDB.enabled and not M:HiddenForGamepad() and M:OwnBarAllowed(index)
	-- Bar 1 showing the vehicle's actions must stay in vehicles.
	local keep = index == 1 and function() return M:BarOneInVehicle() end or nil
	M:RegisterHolder(header, barDB, keep)
	local driverBlock = M.HiddenDriverBlock and M:HiddenDriverBlock(index) or M:FadeBlock(index)
	M:SetDriver(header, show and M:VisibilityDriver(barDB, nil, keep and keep(), driverBlock) or nil)
	M:UpdateFade(header, true)
	completeDock()
end
M.LayoutBar = LayoutBar

-- Is bar `index` Shown? Bars 1 and 2 always are: a layout may hide bar 3
-- and the bars after it, never the two main rows.
function M:BarShown(index)
	if index <= 2 then return true end
	local barDB = self.db and self.db.bars and self.db.bars[index]
	return not (barDB and barDB.shown == false)
end

-- Is bar `index` On but out of sight (the hidden-bar look and rule)?
function M:BarHidden(index)
	local barDB = self.db and self.db.bars and self.db.bars[index]
	return barDB and barDB.enabled and not self:BarShown(index) and true or false
end

-- The grid bar `index` draws now: its own settings, or the hidden-bar
-- shape (Modules/ActionBars/HiddenBars.lua). Fields: count, perRow,
-- width, height, spacing, growth, columns (fill columns first), scale.
function M:BarGrid(index)
	local barDB = self.db.bars[index]
	local hidden = self:BarHidden(index) and self.HiddenGrid and self:HiddenGrid(index)
	if hidden then return hidden end
	local width, height = self:ButtonSize(barDB)
	local count, perRow = math.floor(Clamp(barDB.buttons, 1, 12, 12)), barDB.perRow
	if index == 3 and not self:BarThreeIsWing() then count, perRow = self:BarThreeGrid(count, perRow) end
	return {
		count = count, perRow = perRow, width = width, height = height,
		spacing = Clamp(barDB.spacing, -1, 20, 4), growth = barDB.growth, columns = barDB.fillOrder == "columns",
		scale = Clamp(barDB.scale, 50, 200, 100) / 100,
	}
end

-- Bar 3 draws at most nine buttons, in the shape its layout gives it: a
-- row of 12 becomes a row of 9, a 4x3 or 6x2 grid a 3x3 box, a column stays
-- a column. Buttons 10 to 12 keep their actions and the player's own keys.
local BAR3_MAX = 9
function M:BarThreeGrid(count, perRow)
	count = math.min(BAR3_MAX, count)
	perRow = math.floor(tonumber(perRow) or 12)
	if perRow == 12 then perRow = BAR3_MAX
	elseif perRow == 4 or perRow == 6 then perRow = 3
	else perRow = math.max(1, math.min(perRow, BAR3_MAX)) end
	return count, perRow
end

-- A layout that puts bars 2 and 3 on either side of bar 1 as a matching
-- pair (one long row, or three blocks side by side) keeps bar 3 at its
-- layout's grid while it stays where the layout put it, so the row stays
-- even. Its buttons 10 to 12 then show without a key from the key set.
local function LayoutPoint(name)
	return E.GetRoleMoverPoint and E:GetRoleMoverPoint(name) or E.GetLayoutPoint and E:GetLayoutPoint(name)
end
local MIRROR = { LEFT = "RIGHT", RIGHT = "LEFT" }
function M:BarThreeIsWing()
	if E.db and E.db.movers and E.db.movers.EldoUI_ActionBar3 then return false end
	local three, two = LayoutPoint("EldoUI_ActionBar3"), LayoutPoint("EldoUI_ActionBar2")
	if type(three) ~= "table" or type(two) ~= "table" then return false end
	if three[2] ~= "EldoUI_ActionBar1Mover" or two[2] ~= "EldoUI_ActionBar1Mover" then return false end
	if not (MIRROR[three[1]] and three[3] == MIRROR[three[1]]) then return false end
	if two[1] ~= MIRROR[three[1]] or two[3] ~= three[1] then return false end
	local bars = self.db.bars
	return math.floor(tonumber(bars[2].perRow) or 12) == math.floor(tonumber(bars[3].perRow) or 12)
		and math.floor(Clamp(bars[2].buttons, 1, 12, 12)) == math.floor(Clamp(bars[3].buttons, 1, 12, 12))
end

-- Bar 3 as its layout lays it out (all its buttons, its own row length),
-- for the frames whose spot depends on its size. Nil while it draws that
-- grid anyway or is out of sight.
E:RegisterLayoutMeasure("EldoUI_ActionBar3", function()
	if not (M.active and M.db and M.bars[3]) or not M:BarShown(3) then return nil end
	local barDB = M.db.bars[3]
	local count, perRow = math.floor(Clamp(barDB.buttons, 1, 12, 12)), math.floor(tonumber(barDB.perRow) or 12)
	local drawn = M:BarGrid(3)
	if drawn.count == count and drawn.perRow == perRow then return nil end
	perRow = math.max(1, math.min(count, perRow))
	local rows = math.ceil(count / perRow)
	local columns = drawn.columns and math.ceil(count / rows) or perRow
	local spacing = drawn.spacing
	local width = math.max(1, columns * drawn.width + (columns - 1) * spacing) * drawn.scale
	local height = math.max(1, rows * drawn.height + (rows - 1) * spacing) * drawn.scale
	return width, height
end)

-- A frame placed against a side edge of bar 3 (the pet, stance and totem
-- bars) stays where the layout put it when bar 3 draws fewer buttons than
-- its layout's row: bar 3 shrinks toward the point it is placed by.
local function SideOf(point)
	point = tostring(point or "")
	if point:find("LEFT") then return "LEFT" end
	if point:find("RIGHT") then return "RIGHT" end
	return "CENTER"
end
E:RegisterMoverEdgeShift("EldoUI_ActionBar3Mover", function(relativePoint)
	local side = SideOf(relativePoint)
	if side == "CENTER" or not (M.active and E.movers.EldoUI_ActionBar3) then return nil end
	local layoutW = E:LayoutMeasuredSize("EldoUI_ActionBar3")
	local drawnW = E.movers.EldoUI_ActionBar3:GetWidth()
	local lost = (layoutW or 0) - (drawnW or 0)
	if lost < 0.5 then return nil end
	local own = E.db.movers.EldoUI_ActionBar3 or E:GetMoverDefaultPoint("EldoUI_ActionBar3")
	local fixed = SideOf(type(own) == "table" and own[1])
	if side == fixed then return 0 end
	local shift = fixed == "CENTER" and lost / 2 or lost
	return side == "LEFT" and -shift or shift
end)

-- Bar 3 changed its size: the frames placed against it follow.
function M:PlaceBarThreeNeighbors()
	for name in pairs(E.movers) do
		if not E.db.movers[name] then
			local point = E:GetMoverDefaultPoint(name)
			if type(point) == "table" and point[2] == "EldoUI_ActionBar3Mover" then E:ApplyMover(name) end
		end
	end
end

-- The fade block bar `index` follows now: the player's own, or the
-- hidden-bar rule while the bar is On but not Shown.
function M:FadeBlock(index)
	local barDB = self.db.bars[index]
	if self:BarHidden(index) and self.HiddenFadeBlock then return self:HiddenFadeBlock(index) end
	return barDB.fade
end

-- Is button `button` of bar `bar` drawn on screen? False for a bar that is
-- Off, not Shown or stood down for the gamepad, and for slots past the
-- drawn grid. While Blizzard's bar of the same number shows in its place,
-- that bar draws the button with the same key, so it counts as drawn. The second value is true for a button of
-- a hidden bar that shows when the mouse points at it out of combat.
-- Every button of an On bar has its key either way.
function M:ButtonShown(bar, button)
	local barDB = self.db and self.db.bars and self.db.bars[bar]
	button = tonumber(button)
	if not (barDB and button and button >= 1 and button <= 12 and BARS[bar]) then return false, false end
	if not (self.active and barDB.enabled) or self:HiddenForGamepad() then return false, false end
	if not self:OwnBarAllowed(bar) then return true, false end
	local inGrid = button <= self:BarGrid(bar).count
	if not self:BarShown(bar) then return false, inGrid and barDB.hiddenMouseover ~= false end
	return inGrid, false
end

-- Does bar 1 page to the vehicle's actions?
function M:BarOneInVehicle()
	return self.db.pageVehicle or (self.OverrideBarHidden and self:OverrideBarHidden()) or false
end

-- Locked bars changed in the game's settings: EldoUI's buttons follow.
function M:UpdateButtonLock()
	local locked = self:BarsLocked()
	for _, header in pairs(self.bars) do
		for _, button in ipairs(header.buttons) do button:SetAttribute("buttonlock", locked or nil) end
	end
end

-- Blizzard bindings (ACTIONBUTTON1 etc.) are pointed at EldoUI's buttons.
-- Every button of an On bar gets its key, drawn or not: a bar a layout
-- hides and the slots past a shortened bar's end keep working.
-- Only what changed since the last pass is written (boundKeys: per bar,
-- key -> button name), so a pass with nothing new writes nothing.
function M:UpdateBindings()
	self.boundKeys = self.boundKeys or {}
	for index, header in pairs(self.bars) do
		local wanted = {}
		local barDB = self.db.bars[index]
		if self.active and barDB.enabled and not self:HiddenForGamepad() and self:OwnBarAllowed(index) then
			for slot, button in ipairs(header.buttons) do
				local command = BARS[index].binding .. slot
				for _, key in ipairs({ GetBindingKey(command) }) do wanted[key] = button:GetName() end
			end
		end
		local bound = self.boundKeys[index] or {}
		for key in pairs(bound) do
			if wanted[key] == nil then SetOverrideBinding(header, false, key, nil) end
		end
		for key, name in pairs(wanted) do
			if bound[key] ~= name then SetOverrideBindingClick(header, false, key, name) end
		end
		self.boundKeys[index] = wanted
	end
	-- Pet and stance buttons are Blizzard's own buttons (Special.lua), so
	-- their BONUSACTIONBUTTON / SHAPESHIFTBUTTON keys need nothing here.
end

---------------------------------------------------------------------------
-- Blizzard's main bar and extra bars 2-8
---------------------------------------------------------------------------
local hiddenBars = {}    -- [Blizzard bar] = true while EldoUI keeps it hidden
-- The game's bar shows its empty slots on these two events, hidden or not.
-- Picking up a spell in combat would then run that update on a bar EldoUI
-- hid, and the game blocks it. A hidden bar has no slots to show, so it
-- stops listening until it comes back.
local GRID_EVENTS = { "ACTIONBAR_SHOWGRID", "ACTIONBAR_HIDEGRID" }
local gridEvents = setmetatable({}, { __mode = "k" }) -- [Blizzard bar] = events EldoUI took off it


-- Should Blizzard's bar `index` be hidden right now?
function M:BlizzardBarHidden(index)
	local info = BARS[index]
	local mode = self.db.bars[index].blizzard
	if mode == "show" then return false end
	if mode == "hide" then return E:BlizzardHidden(info.element) end
	-- auto: when EldoUI's own bar takes its place, and while the layout in use
	-- keeps EldoUI's bar off (the layout wants no bar there at all, so
	-- Blizzard's bar of the same number must not come back in its place).
	if not E:BlizzardAllowed(info.element, "replace") then return false end
	return self:BarActive(index) or (self.active and self:LayoutKeepsOff(index))
end

-- True while the layout in use hides EldoUI's bar `index` and the player
-- turned the bar Off: the layout wants no bar there, so Blizzard's bar of
-- the same number stays away too.
function M:LayoutKeepsOff(index)
	local hidden = E.db.general.layoutHidden
	return hidden and hidden["EldoUI_ActionBar" .. index] == true and not self.db.bars[index].enabled or false
end

local function HideBlizzardBar(index)
	local info = BARS[index]
	local bar = _G[info.blizzard]
	if not bar or hiddenBars[bar] then return end
	hiddenBars[bar] = true
	local taken = {}
	for _, event in ipairs(GRID_EVENTS) do
		if bar:IsEventRegistered(event) then
			bar:UnregisterEvent(event)
			taken[#taken + 1] = event
		end
	end
	gridEvents[bar] = taken
	-- The core keeps it there when Edit Mode or a vehicle re-parents it
	-- (SetParent post-hook, after combat for these protected bars).
	E:HideBlizzardFrame(bar, { check = function() return hiddenBars[bar] == true end })
	for slot = 1, 12 do
		local button = _G[info.buttons .. slot]
		if button then
			-- Hidden buttons stop doing work; a /reload brings them back.
			button:UnregisterAllEvents()
			button:SetAttribute("statehidden", true)
			button:Hide()
		end
	end
end

-- True when it brought back a bar hidden this session: its buttons lost
-- their events (UnregisterAllEvents above), so it needs a reload.
local function ShowBlizzardBar(index)
	local info = BARS[index]
	local bar = _G[info.blizzard]
	if not bar or not hiddenBars[bar] then return false end
	hiddenBars[bar] = nil
	for _, event in ipairs(gridEvents[bar] or {}) do bar:RegisterEvent(event) end
	gridEvents[bar] = nil
	E:UnhideBlizzardFrame(bar, UIParent)
	for slot = 1, 12 do
		local button = _G[info.buttons .. slot]
		if button then
			button:SetAttribute("statehidden", nil)
		end
	end
	if bar.UpdateShownButtons then bar:UpdateShownButtons() end
	return true
end

function M:UpdateBlizzardBars()
	local returned = false
	for index = 1, NUM_BARS do
		if self.active and self:BlizzardBarHidden(index) then
			HideBlizzardBar(index)
		elseif ShowBlizzardBar(index) then
			returned = true
		end
	end
	if self.UpdateBlizzardButtonSkins then self:UpdateBlizzardButtonSkins() end
	-- A bar that comes back shows, but its buttons stay still (no cooldowns,
	-- range or usability) until a reload; the same note OnDisable gives.
	if returned then E:ShowReloadPrompt(L["Blizzard's action bars come fully back after a reload."]) end
end

-- Never two bars in one place (design decision): EldoUI's bar shows
-- (and takes the bar's keys) only while Blizzard's bar of the same number is
-- out of sight, unless the player keeps both ("Always keep Blizzard's").
function M:OwnBarAllowed(index)
	if self.db.bars[index].blizzard == "show" then return true end
	local bar = _G[BARS[index].blizzard]
	if not bar or hiddenBars[bar] then return true end
	return not bar:IsShown()
end

function M:BlizzardBarShown(index)
	local bar = _G[BARS[index].blizzard]
	return bar and not hiddenBars[bar]
end

---------------------------------------------------------------------------
-- What changed since the last apply. A setting change used to
-- rebuild all 96 buttons. Now OnProfileChanged compares the settings with
-- the ones last applied, in four groups:
--   bars[i]   one bar's own table: lay out (re-anchor, resize, re-skin) only that bar
--   restyle   button look shared by every bar (text, cooldown numbers,
--             colors, overlays) and the General fonts and art style:
--             re-skin every button, nothing is re-anchored
--   special   pet, stance, vehicle, extra and totem bars: those only
--   rest      everything else, or another profile: one full rebuild
-- Every path runs through E:RunOutOfCombat (buttons are protected).
---------------------------------------------------------------------------
local RESTYLE_KEYS = {
	textPreset = true, showHotkey = true, hotkeyAbbrev = true, fontSize = true, hotkeyPosition = true, hotkeyColor = true,
	showCount = true, countSize = true, countPosition = true, countColor = true, showMacro = true, macroSize = true,
	macroColor = true, textOutline = true, textOffsetX = true, textOffsetY = true,
	cooldownText = true, cooldownSize = true, cooldownExpiring = true, cooldownTenths = true, cooldownColor = true,
	cooldownSecondsColor = true, cooldownExpiringColor = true, cooldownOwnLook = true, swipeAlpha = true, drawBling = true,
	cooldownMinDuration = true, cooldownEdge = true, chargeCooldown = true, desaturateCooldown = true,
	buttonZoom = true, rangeColoring = true, rangeColor = true, manaColor = true, unusableColor = true,
	equippedBorder = true, equippedColor = true, highlightStyle = true, pushedStyle = true, tooltips = true, castVFX = true,
}
local SPECIAL_KEYS = { pet = true, stance = true, possess = true, extra = true, vehicle = true, totem = true, proc = true, gamepad = true }
-- Read by the options page only, or applied on their own (linkMouseover
-- only links the fades, M:UpdateMouseoverLink; cues, M:ApplyCues).
local IGNORED_KEYS = { optionsBar = true, cooldownLookMoved = true, linkMouseover = true, cues = true }
-- General settings the buttons draw with (fonts, cooldown numbers, art style).
local GENERAL_LOOK = { "font", "fontSize", "fontOutline", "fontShadow", "cooldownFont", "cooldownFontSize",
	"cooldownFontOutline", "cooldownExpiring", "cooldownTenths", "cooldownColor", "cooldownSecondsColor",
	"cooldownExpiringColor", "artStyle", "skinParts", "skinVariant", "accent", "accentCustom", "panelAlpha" }

local function Serialize(value, out)
	local kind = type(value)
	if kind == "table" then
		local keys = {}
		for key in pairs(value) do keys[#keys + 1] = key end
		table.sort(keys, function(a, b)
			local ta, tb = type(a), type(b)
			if ta ~= tb then return ta < tb end
			return a < b
		end)
		out[#out + 1] = "{"
		for _, key in ipairs(keys) do
			out[#out + 1] = tostring(key)
			out[#out + 1] = "="
			Serialize(value[key], out)
			out[#out + 1] = ","
		end
		out[#out + 1] = "}"
	else
		out[#out + 1] = kind:sub(1, 1) .. tostring(value)
	end
	return out
end

local function Signature(value)
	return table.concat(Serialize(value, {}))
end

function M:SettingsSnapshot()
	local db = self.db
	local restyle, special, rest = {}, {}, {}
	for key, value in pairs(db) do
		if key ~= "bars" and not IGNORED_KEYS[key] then
			local group = RESTYLE_KEYS[key] and restyle or SPECIAL_KEYS[key] and special or rest
			group[key] = value
		end
	end
	local general = E.db and E.db.general or {}
	restyle.general = {}
	for _, key in ipairs(GENERAL_LOOK) do restyle.general[key] = general[key] end
	-- The key map's "show keys on bars 1 to 3" (Core/KeymapSync.lua).
	restyle.showKeys = E.KeymapSetting and E:KeymapSetting("showKeys") or false
	local bars = {}
	for index = 1, NUM_BARS do bars[index] = Signature(db.bars[index]) end
	return { profile = db, bars = bars, restyle = Signature(restyle), special = Signature(special), rest = Signature(rest) }
end

-- Re-skin one bar's buttons where they are: config and look, no layout.
function M:RestyleBar(index)
	local header = self.bars[index]
	if not header then return end
	local barDB = self.db.bars[index]
	local grid = self:BarGrid(index)
	local width, height = grid.width, grid.height
	self:UpdateBackdrop(header, barDB)
	for slot, button in ipairs(header.buttons) do
		button:UpdateConfig(self:ButtonConfig(BARS[index].binding .. slot, barDB, header.eldoFlyout))
		self:StyleButton(button, width, height, barDB)
	end
end

-- Apply what changed since the last apply. Returns what it did: "full",
-- "bars" (with the changed indexes), "restyle", "special" or "none".
function M:ApplyChanges()
	local new = self:SettingsSnapshot()
	local old = self.applied
	if not old or old.profile ~= new.profile or old.rest ~= new.rest then
		self:Apply()
		return "full"
	end
	local changed = {}
	for index = 1, NUM_BARS do
		if old.bars[index] ~= new.bars[index] then changed[#changed + 1] = index end
	end
	local restyle = old.restyle ~= new.restyle
	local special = restyle or old.special ~= new.special
	self.applied = new
	if #changed > 0 then
		-- A bar turned On for the first time is made now.
		self:CreateWantedBars()
		-- An enabled bar or a "Blizzard's bar" choice can change which bars
		-- show, so Blizzard's bars and the key bindings follow.
		self:UpdateBlizzardBars()
		for _, index in ipairs(changed) do
			if self.bars[index] then LayoutBar(self.bars[index], index) end
			if index == 3 then self:PlaceBarThreeNeighbors() end
		end
		self:UpdateBindings()
		-- A bar that hides or shows again changes its spot.
		if self.PlaceHiddenBars then self:PlaceHiddenBars() end
		-- A bar turned on gets its spell ranks upgraded (when that is on).
		if self.RankBarsChanged then self:RankBarsChanged() end
	end
	if restyle then
		local done = {}
		for _, index in ipairs(changed) do done[index] = true end
		for index = 1, NUM_BARS do
			if not done[index] then self:RestyleBar(index) end
		end
		if self.UpdateBlizzardButtonSkins then self:UpdateBlizzardButtonSkins() end
	end
	if special and self.ApplySpecial then self:ApplySpecial() end
	if #changed > 0 or special then self:UpdateAllFades(true) end
	if #changed > 0 or restyle then self:RelayoutButtonSkins() end
	if #changed > 0 or restyle then dockPublish(true) end
	if #changed > 0 then return "bars", changed end
	if restyle then return "restyle" end
	if special then return "special" end
	return "none"
end

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------
function M:Apply()
	if not self.active then return end
	self:FillDefaults()
	for index = 1, NUM_BARS do
		if not self.bars[index] and self:BarWanted(index) then self.bars[index] = CreateBar(index) end
	end
	-- Blizzard's bars first: an EldoUI bar shows only where Blizzard's is gone.
	self:UpdateBlizzardBars()
	for index = 1, NUM_BARS do
		if self.bars[index] then LayoutBar(self.bars[index], index) end
	end
	if self.ApplySpecial then self:ApplySpecial() end
	if self.ApplyLook then self:ApplyLook() end
	self:UpdateBindings()
	if self.PlaceHiddenBars then self:PlaceHiddenBars() end
	self:UpdateAllFades(true)
	self:RelayoutButtonSkins()
	self.applied = self:SettingsSnapshot()
	if self.RankBarsChanged then self:RankBarsChanged() end
	dockPublish(true)
end

-- Every button's skin frame laid out again from its final size, once per
-- apply: a layout or setup apply ends with the sizes it settled on.
function M:RelayoutButtonSkins()
	local Skins = E.Skins
	if not (Skins and Skins.Relayout) then return end
	for _, header in pairs(self.bars) do
		for _, button in ipairs(header.buttons or {}) do Skins.Relayout(button) end
	end
end

function M:OnInitialize()
	self:FillDefaults()
	dockPublish(false)
end

function M:OnEnable()
	E:RunOutOfCombat(function() self:Apply() end)
	-- The game's own key bindings changed. The game sends this while it is
	-- still updating them, so EldoUI's keys follow a frame later, once for
	-- a burst of events, and in combat once after the fight.
	self:RegisterEvent("UPDATE_BINDINGS", function()
		E:Debounce("ActionBars:bindings", 0, function()
			E:RunOutOfCombat(function() self:UpdateBindings() end, "ActionBars:bindings")
		end)
	end)
	-- Fades: the visibility engine follows combat, target and the mouse;
	-- dragging a spell shows every bar.
	self:RegisterEvent("ACTIONBAR_SHOWGRID", function() dragging = true; self:UpdateAllFades() end)
	self:RegisterEvent("ACTIONBAR_HIDEGRID", function() dragging = false; self:UpdateAllFades() end)
	-- "Lock action bars" changed in the game's options.
	self:RegisterEvent("CVAR_UPDATE", function()
		local locked = self:BarsLocked()
		if locked ~= self.lastLocked then
			self.lastLocked = locked
			E:RunOutOfCombat(function() if self.active then self:UpdateButtonLock() end end)
		end
	end)
	-- Gamepad and mouse UI swap.
	-- The game sets its interface up first: the bars follow a frame later.
	self:RegisterEvent("INPUT_DEVICE_INTERFACE_TRANSITION", function()
		self:UpdateAllFades(true)
		E:Debounce("ActionBars:interface", 0, function()
			E:RunOutOfCombat(function() self:Apply() end, "ActionBars:interface")
		end)
	end)
	-- A login or reload builds everything. Any other loading screen only
	-- applies what changed and asserts what the game may have reset:
	-- Blizzard's bars, the key bindings and the fades.
	self:RegisterEvent("PLAYER_ENTERING_WORLD", function(_, _, isInitialLogin, isReloadingUi)
		if isInitialLogin or isReloadingUi or not self.applied then
			E:RunOutOfCombat(function() self:Apply() end)
			return
		end
		E:RunOutOfCombat(function()
			if not self.active then return end
			if self:ApplyChanges() == "full" then return end
			self:UpdateBlizzardBars()
			self:UpdateBindings()
			self:UpdateAllFades(true)
		end)
	end)
	-- Talent group and resting rules are carried in the drivers as their
	-- current state (Core/Visibility.lua): rebuild when they change.
	local function StateChanged()
		for frame in pairs(self.holders) do
			local db = frame.eldoDB
			if db and E:VisibilityUsesState(db.fade) then
				E:RunOutOfCombat(function() if self.active then self:Apply() end end)
				return
			end
		end
	end
	self:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED", StateChanged)
	self:RegisterEvent("PLAYER_UPDATE_RESTING", StateChanged)
end

function M:OnDisable()
	local hadHidden = next(hiddenBars) ~= nil
	E:RunOutOfCombat(function()
		self.boundKeys = nil
		for index, header in pairs(self.bars) do
			ClearOverrideBindings(header)
			self:SetDriver(header, nil)
			header:Hide()
			self:SetMoverActive("EldoUI_ActionBar" .. index, false)
		end
		dockPublish(true)
		self:UpdateBlizzardBars()
		if self.DisableSpecial then self:DisableSpecial() end
		if self.ApplyLook then self:ApplyLook() end
		for frame in pairs(self.holders) do self:ReleaseHolder(frame) end
		self:UpdateEndCaps()
	end)
	-- The next enable starts from a full build.
	self.applied = nil
	-- Blizzard's hidden bars come fully back (their events) only with a reload.
	if hadHidden then E:ShowReloadPrompt(L["Blizzard's action bars come fully back after a reload."]) end
end

function M:OnProfileChanged()
	-- Style presets replace whole tables; refill missing keys right away (pure
	-- data, safe in combat) so nothing reads a half-filled profile.
	if self.db then self:FillDefaults() end
	if self.ApplyRankCheck then self:ApplyRankCheck() end
	if self.ApplyCues then self:ApplyCues() end
	if E.KeymapAutomationChanged then E:KeymapAutomationChanged() end
	if self.active then self:UpdateMouseoverLink() end
	-- Only what changed; a new profile still rebuilds once.
	if self.active then E:RunOutOfCombat(function() if self.active then self:ApplyChanges() end end) end
end

-- Keybind mode shows faded bars at full opacity.
if E.ToggleKeybindMode then
	hooksecurefunc(E, "ToggleKeybindMode", function() if M.active then M:UpdateAllFades() end end)
end

---------------------------------------------------------------------------
-- Blizzard element switches
---------------------------------------------------------------------------
local function Reapply()
	if M.active then M:Apply() end
end

-- v0.5.0 replaced and hid Blizzard's bars whenever the module was on.
local function LegacyBars()
	return M.db.enabled and M.db.hideBlizzard
end

-- The one handler of Main action bar: the end caps first (alpha only),
-- then the bars.
local function ReapplyMain()
	M:UpdateEndCaps()
	Reapply()
end

E:RegisterBlizzardHandler("main-action-bar", {
	owner = "ActionBars",
	owns = true,
	apply = ReapplyMain,
	undo = ReapplyMain,
	reload = { hide = true, replace = true, skin = true },
	install = { replace = true, move = true, skin = true, improve = true },
	legacy = LegacyBars,
	refreshModule = false,
})

E:RegisterBlizzardHandler("multi-action-bars", {
	owner = "ActionBars",
	apply = Reapply,
	undo = Reapply,
	reload = { hide = true, replace = true, skin = true },
	install = { replace = true, move = true, skin = true },
	legacy = LegacyBars,
	refreshModule = false,
})
