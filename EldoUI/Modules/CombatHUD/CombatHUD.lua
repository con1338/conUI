-- EldoUI Combat HUD: one module page for Blizzard's own combat
-- displays that EldoUI skins and places. Each display is a feature in its
-- own file (Modules/CombatHUD/*.lua) with its own Blizzard element switch:
--   DamageMeter.lua    damage-meter          (+ combat timer)
--   Threat.lua         EldoUI's threat meter, E:GetThreat
--   SwingTimer.lua     swing-timer           (+ EldoUI's own swing bars)
--   LossOfControl.lua  loss-of-control
--   Timers.lua         mirror-quest-timers
--   DeathRecap.lua     death-recap-ghost
--   Cursor.lua         EldoUI's cursor and GCD ring
--
-- A feature is a table:
--   key       settings key (module settings `<key>.*`)
--   id        Blizzard element id (nil for EldoUI's own displays)
--   title     tab label
--   addon     load-on-demand Blizzard addon the frames live in (optional)
--   defaults  settings
--   options   option rows (keys start with `<key>.`)
--   switches  { action = description } for the element switch rows
--   install, reload   handler fields (Core/Blizzard.lua)
--   Setup(f, db)    once, when first applied (hooks, holders)
--   Apply(f, db)    after every change while the element is on
--   Restore(f)      back to Blizzard (best effort; skin and move reload)
-- Blizzard's floating combat text and frame feedback moved to
-- the Combat Text module (Modules/CombatText); their settings were
-- copied over once.
-- Written from scratch for EldoUI.
local _, E = ...
local L = E.L
local K = E.CombatKit

local M = E:NewModule("CombatHUD", {
	title = "Combat HUD",
	desc = "Skins and places Blizzard's own combat displays: damage meter, swing timer, loss of control, mirror and quest timers, death recap. Plus EldoUI's threat meter, combat timer and cursor ring.",
	category = "Combat",
	frames = { "EldoUI_Crosshair" },
	movers = {
		"EldoUI_Details", "EldoUI_CombatTimer", "EldoUI_ThreatMeter", "EldoUI_SwingMainHand",
		"EldoUI_SwingOffHand", "EldoUI_SwingRanged", "EldoUI_LossOfControl", "EldoUI_MirrorTimers",
		"EldoUI_QuestTimer", "EldoUI_DeathRecap", "EldoUI_GhostButton",
	},
	blizzard = {
		"damage-meter", "swing-timer", "loss-of-control", "mirror-quest-timers", "death-recap-ghost",
	},
	savedKeys = { "profile.modules.CombatHUD", "private.combatHUDOverview" },
	optionsPage = "module:CombatHUD",
	presets = { "Accent", "Clean", "CombatOnly", "Large", "Melee", "Minimal" },
	defaults = {},
})
E.CombatHUD = M
M.features = {}
M.options = {}

---------------------------------------------------------------------------
-- Overview (the page's first tab): one fold section per display
-- (DESIGN.md §0a rule 4), a centered name between two thin accent lines,
-- with value rows for its settings: on or off, and for Blizzard's own
-- displays what EldoUI may change. Only settings, never combat data. A
-- click on a section's rows opens that display's tab. The fold state is
-- kept per character. The displays themselves keep their HUD look.
---------------------------------------------------------------------------
E:RegisterPrivate("combatHUDOverview", { folded = {} })

local OVERVIEW_GAP = 4     -- space under a section
local OVERVIEW_INSET = 16  -- the block's inset around the sections, top and bottom together

local function OverviewFolded()
	local store = E:GetPrivate("combatHUDOverview")
	if type(store) ~= "table" then return {} end
	if type(store.folded) ~= "table" then store.folded = {} end
	return store.folded
end

-- The value rows of one display: { label, value, kind }.
function M:OverviewRows(feature)
	local rows = {}
	if feature.id then
		local on = E:BlizzardAllowed(feature.id)
		rows[1] = { L["State"], on and L["EldoUI changes it"] or L["Blizzard's own"], on and "good" or "secondary" }
		local data = E.blizzardElements[feature.id]
		local actions = {}
		if on and data then
			for _, action in ipairs({ "skin", "move", "hide", "replace", "improve" }) do
				if data.allowed[action] and E:BlizzardAllowed(feature.id, action) then
					actions[#actions + 1] = L[E.BLIZZARD_ACTION_LABEL[action]]
				end
			end
		end
		rows[2] = { L["Changes"], #actions > 0 and table.concat(actions, ", ") or L["Nothing"], #actions > 0 and "body" or "secondary" }
	else
		local db = self.db and self.db[feature.key]
		local on = type(db) == "table" and db.enabled and true or false
		rows[1] = { L["State"], on and L["On"] or L["Off"], on and "good" or "secondary" }
		rows[2] = { L["Kind"], L["EldoUI's own display"], "secondary" }
	end
	return rows
end

local overview = { type = "preview", height = 96 }
M.Overview = overview

local function OverviewHeight()
	local folded = OverviewFolded()
	local T = E.tokens.height
	local height = 0
	for _, feature in ipairs(M.features) do
		height = height + T.foldRow + OVERVIEW_GAP
		if not folded[feature.key] then height = height + #M:OverviewRows(feature) * T.row end
	end
	return math.max(height, T.foldRow) + OVERVIEW_INSET
end

-- Place the sections from the top; folded ones keep only their divider.
local function LayoutOverview(canvas)
	local folded = OverviewFolded()
	local T = E.tokens.height
	local y = 0
	for _, feature in ipairs(M.features) do
		local section = canvas.sections[feature.key]
		section.divider:ClearAllPoints()
		section.divider:SetPoint("TOPLEFT", canvas, "TOPLEFT", 0, -y)
		section.divider:SetPoint("TOPRIGHT", canvas, "TOPRIGHT", 0, -y)
		section.divider:SetFolded(folded[feature.key] and true or false, true)
		y = y + T.foldRow
		local rows = M:OverviewRows(feature)
		section.content:ClearAllPoints()
		section.content:SetPoint("TOPLEFT", canvas, "TOPLEFT", 0, -y)
		section.content:SetPoint("TOPRIGHT", canvas, "TOPRIGHT", 0, -y)
		section.content:SetHeight(math.max(#rows * T.row, 1))
		for index, data in ipairs(rows) do
			local row = section.rows[index]
			if not row then
				row = E.UIKit.ValueRow(section.content, {})
				row:EnableMouse(true)
				row:SetScript("OnMouseUp", function() E:ShowConfigTab("module:CombatHUD", feature.title) end)
				E.UIKit.Tooltip(row, L[feature.title], nil, { { L["Click"], L["open its settings"] } })
				section.rows[index] = row
			end
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", section.content, "TOPLEFT", 0, -(index - 1) * T.row)
			row:SetPoint("TOPRIGHT", section.content, "TOPRIGHT", 0, -(index - 1) * T.row)
			row:SetLabel(data[1])
			row:SetValue(data[2], data[3])
			row:Show()
		end
		for index = #rows + 1, #section.rows do section.rows[index]:Hide() end
		if not folded[feature.key] then y = y + #rows * T.row end
		y = y + OVERVIEW_GAP
	end
end

-- A fold changes the block's height: the page lays itself out again.
local function Relayout(canvas)
	local height = OverviewHeight()
	LayoutOverview(canvas)
	if overview.height ~= height then
		overview.height = height
		if E.RefreshConfig then E:RefreshConfig() end
	end
end

function overview.create(canvas)
	if not canvas then return end
	canvas.sections = {}
	for _, feature in ipairs(M.features) do
		local section = { rows = {} }
		section.content = CreateFrame("Frame", nil, canvas)
		section.divider = E.UIKit.FoldDivider(canvas, { label = L[feature.title], content = section.content,
			onToggle = function(isFolded)
				OverviewFolded()[feature.key] = isFolded or nil
				Relayout(canvas)
			end })
		canvas.sections[feature.key] = section
	end
	overview.canvas = canvas
	overview.height = OverviewHeight()
	LayoutOverview(canvas)
end

function overview.update(canvas)
	if canvas and canvas.sections then Relayout(canvas) end
end

table.insert(M.options, { type = "tab", label = "Overview" })
table.insert(M.options, overview)

---------------------------------------------------------------------------
-- Features
---------------------------------------------------------------------------
function M:AddFeature(feature)
	self.defaults[feature.key] = feature.defaults or {}
	table.insert(self.features, feature)
	table.insert(self.options, { type = "tab", label = feature.title })
	if feature.id then
		K.SwitchOptions(self.options, feature.id, feature.switches)
	end
	if feature.note then
		table.insert(self.options, { type = "description", label = feature.note })
	end
	for _, row in ipairs(feature.options or {}) do
		table.insert(self.options, row)
	end
	if feature.id then
		E:RegisterBlizzardHandler(feature.id, {
			owner = "CombatHUD",
			apply = function() M:ApplyFeature(feature) end,
			undo = function() M:RestoreFeature(feature) end,
			reload = feature.reload or { skin = true, move = true },
			install = feature.install or { skin = true, move = true },
			-- v0.5.0 never touched these displays.
			legacy = function() return false end,
		})
	end
	return feature
end

-- Hidden-row helpers for option tables: hide a row while the element (or
-- one of its actions) is off.
function M.Off(id, action)
	return function()
		if action == "hide" then return not E:BlizzardHidden(id) end
		return not E:BlizzardAllowed(id, action)
	end
end

local function Run(feature, method, ...)
	local fn = feature[method]
	if not fn then return end
	local ok, err = pcall(fn, feature, ...)
	if not ok then geterrorhandler()(("EldoUI Combat HUD %s:%s: %s"):format(feature.key, method, tostring(err))) end
end

local function Wanted(feature)
	if not M.active then return false end
	if feature.key == "threat" and E:StandsBack(M, feature.key) then return false end
	if feature.id then return E:BlizzardAllowed(feature.id) end
	return M.db[feature.key].enabled and true or false
end

function M:ApplyFeature(feature)
	if not self.active then return end
	K.BindSwitches(self)
	local function Go()
		if not Wanted(feature) then
			self:RestoreFeature(feature)
			return
		end
		local db = self.db[feature.key]
		if not feature.ready then
			feature.ready = true
			Run(feature, "Setup", db)
		end
		feature.applied = true
		Run(feature, "Apply", db)
	end
	if feature.addon and not C_AddOns.IsAddOnLoaded(feature.addon) then
		-- Load-on-demand: apply once Blizzard loads it (queued only once).
		if not feature.waiting then
			feature.waiting = true
			E:OnBlizzardAddOn(feature.addon, function()
				feature.waiting = nil
				E:RunOutOfCombat(function() M:ApplyFeature(feature) end)
			end)
		end
		return
	end
	E:RunOutOfCombat(Go)
end

function M:RestoreFeature(feature)
	if not feature.applied then return end
	feature.applied = nil
	Run(feature, "Restore")
end

function M:OnStandBack(feature)
	if feature ~= "threat" then return end
	for _, entry in ipairs(self.features) do
		if entry.key == feature then self:ApplyFeature(entry) return end
	end
end

function M:ApplyAll()
	for _, feature in ipairs(self.features) do self:ApplyFeature(feature) end
end

-- feature:Migrate(db) moves older settings once (each guards itself).
function M:MigrateFeatures()
	if type(self.db) ~= "table" then return end
	for _, feature in ipairs(self.features) do
		if feature.Migrate and type(self.db[feature.key]) == "table" then Run(feature, "Migrate", self.db[feature.key]) end
	end
end

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------
function M:OnInitialize()
	K.BindSwitches(self)
	self:MigrateFeatures()
end

function M:OnEnable()
	K.BindSwitches(self)
	self:MigrateFeatures()
	self:RegisterEvent("PLAYER_ENTERING_WORLD", function() M:ApplyAll() end)
	if EventRegistry and EventRegistry.RegisterCallback then
		EventRegistry:RegisterCallback("EditMode.Exit", function()
			C_Timer.After(0, function() M:ApplyAll() end)
		end, self)
	end
	self:ApplyAll()
end

function M:OnDisable()
	self:UnregisterEvent("PLAYER_ENTERING_WORLD")
	if EventRegistry and EventRegistry.UnregisterCallback then
		EventRegistry:UnregisterCallback("EditMode.Exit", self)
	end
	for _, feature in ipairs(self.features) do self:RestoreFeature(feature) end
end

function M:OnProfileChanged()
	K.BindSwitches(self)
	self:MigrateFeatures()
	if self.active then self:ApplyAll() end
end

---------------------------------------------------------------------------
-- /eui diag rows for the Combat HUD probes: does the game hand
-- out threat and meter durations in readable
-- form right now? The report only tests values; it never works around one.
---------------------------------------------------------------------------
local issecret = issecretvalue or function() return false end

local function Mark(value)
	if issecret(value) then return E:TextHex("warn") .. "secret|r" end
	if type(value) == "nil" then return E:TextHex("secondary") .. "none|r" end
	return E:TextHex("good") .. "readable|r"
end

function M:DiagnosticsLines()
	local lines = { "   " .. E:TextHex("accent") .. "Combat HUD|r" }
	local function Line(label, value) table.insert(lines, ("   %s: %s"):format(label, tostring(value))) end
	-- Threat: the game's own secrecy flag, then the values themselves.
	if UnitExists("target") then
		local secret = self.ThreatValuesSecret and self.ThreatValuesSecret("player", "target")
		Line("Threat values secret (C_Secrets)", secret and E:TextHex("warn") .. "yes|r" or "no")
		local ok, _, status, scaled, percent = pcall(UnitDetailedThreatSituation, "player", "target")
		if ok then Line("Threat on target", ("status %s, percent %s, scaled %s"):format(Mark(status), Mark(percent), Mark(scaled))) end
	else
		Line("Threat", E:TextHex("secondary") .. "target a mob to test|r")
	end
	-- Damage meter session duration.
	local api = C_DamageMeter and C_DamageMeter.GetSessionDurationSeconds
	local types = Enum and Enum.DamageMeterSessionType
	if api and types and types.Current then
		local ok, seconds = pcall(api, types.Current)
		Line("Meter session duration", ok and Mark(seconds) or E:TextHex("warn") .. "error|r")
	else
		Line("Meter session duration", E:TextHex("secondary") .. "C_DamageMeter not on this client|r")
	end
	return lines
end

-- Append the rows to the core report (/eui diag).
E:RegisterDiagnostics("CombatHUD", function() return M.active and M:DiagnosticsLines() or {} end)

E:AddCommand("hud", "Combat HUD settings (damage meter, swing timer, loss of control, timers, death recap, cursor ring)", function()
	E:ToggleConfig("module:CombatHUD")
end, "Layout & frames")

---------------------------------------------------------------------------
-- Style presets (settings only; the element switches stay as they are)
---------------------------------------------------------------------------
E:RegisterStyles("CombatHUD", {
	{ key = "Clean", title = "Clean", desc = "Theme font and texture everywhere, class-colored meter, slim swing bars.",
		settings = {
			meter = { colorMode = "class", background = 60, fontSize = 12 },
			swing = { width = 240, height = 14, colorMode = "custom", showTitle = true, showTime = true },
			loc = { scale = 100, hideArt = true },
			timers = { width = 220, height = 14 },
			threat = { barHeight = 14, spacing = 1, background = 60, header = true, borders = true, barColor = "class" },
			combattimer = { colorCombat = true },
		} },
	{ key = "Minimal", title = "Minimal", desc = "No titles, no backgrounds: just bars and numbers.",
		settings = {
			meter = { background = 0, colorMode = "class" },
			swing = { showTitle = false, showTime = true, height = 10, spark = false },
			loc = { hideArt = true, scale = 90 },
			timers = { height = 10 },
			threat = { header = false, background = 0, borders = false, barHeight = 10, spacing = 2 },
			combattimer = { background = false, colorCombat = false },
		} },
	{ key = "Large", title = "Large", desc = "Bigger text and bars for big screens or sitting far away.",
		settings = {
			meter = { fontSize = 14, width = 480, height = 280 },
			swing = { width = 300, height = 20, fontSize = 13 },
			loc = { scale = 125 },
			timers = { width = 280, height = 20, fontSize = 13 },
			threat = { width = 280, barHeight = 20, fontSize = 13, rows = 6 },
			combattimer = { fontSize = 20 },
		} },
	{ key = "Accent", title = "Accent", desc = "Meter, swing bars and the running combat timer in the UI accent color.",
		settings = {
			meter = { colorMode = "accent" },
			swing = { colorMode = "accent" },
			threat = { barColor = "accent", tankColor = true },
			combattimer = { colorCombat = true },
		} },
	{ mode = true, key = "CombatOnly", title = "Combat only", desc = "Meter hidden out of combat, cursor ring only in combat.",
		settings = {
			meter = { visibility = { preset = "combat", show = "combat" } },
			cursor = { visibility = "combat" },
			threat = { show = "auto" },
			combattimer = { outOfCombat = false },
		} },
	{ mode = true, key = "Melee", title = "Melee", desc = "EldoUI's own swing bars with titles and time, GCD ring on the cursor.",
		settings = {
			swing = { showTitle = true, showTime = true, height = 14 },
			swingbars = { enabled = true, inCombatOnly = true },
			cursor = { enabled = true, gcd = true, visibility = "combat" },
		} },
}, { restores = {
	"meter.visibility", "cursor.visibility", "cursor.enabled", "swingbars.enabled",
	"combattimer.outOfCombat"
} })
