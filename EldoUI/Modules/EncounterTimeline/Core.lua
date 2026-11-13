-- EldoUI Encounter Timeline: a slim bar where the timers your boss
-- mod publishes travel toward "now", with a big icon for the next event at
-- the bar's now end. Both are one frame on one mover.
--
-- Files (Modules/EncounterTimeline/):
--   Core.lua     module, settings, migration, the frame and its mover,
--                visibility, glow user,
--                commands, probe, diagnostics, style presets
--   Store.lua    the event store, its one driver frame and the threshold
--                crossings (tick flash, stages, the Soon slot, sound)
--   Sources.lua  DBM callbacks, BigWigs messages, the Blizzard pull
--                countdown, the ready check, ENCOUNTER_END, source choice,
--                "Fade DBM's own bars"
--   Bar.lua      the frame's layout and the bar: backing, track, now-marker,
--                ticks, warning zones, icon pool, lanes, waiting grid
--   Soon.lua     the Soon slot (big icons, swipe, number, glow, pop-in)
--                and the countdown sound
--   Test.lua     three scripted test fights and the static sample
--   Options.lua  the options page with its status preview
--
-- How it stays within the rules (Forever runs the Midnight restrictions):
--   * Forever does not load Blizzard's encounter timeline, so EldoUI keeps
--     its own clock: GetTime() plus the duration the boss mod hands out.
--   * It shows only what DBM, BigWigs or Blizzard publish: DBM's public
--     DBM_Timer* callbacks, BigWigs' public messages, START_PLAYER_COUNTDOWN
--     and READY_CHECK. It never creates or predicts a timer, never reads a
--     boss mod's bar frames or bar texts, and reads no combat log. Listening
--     to the boss-mod callbacks is the one allowed exception: the boss mods
--     publish these callbacks for other addons.
--   * Every value that may be secret is tested first. A secret duration
--     drops the timer; a secret text only reaches SetText; a secret icon
--     shows the question mark; a secret spell id gives no tooltip.
--   * The frames are EldoUI's own, never secure and never anchored to a
--     secure frame, so they update in combat. Nothing acts for the player.
-- Written from scratch for EldoUI.
local _, E = ...
local L = E.L

local M = E:NewModule("EncounterTimeline", {
	title = "Encounter Timeline",
	desc = L["A timeline bar that shows the timers DBM or BigWigs publish, plus the pull countdown, as icons moving toward now."],
	category = "Combat",
	conflicts = { "AbilityTimeline" },
	frames = { "EldoUI_EncounterTimeline", "EldoUI_EncounterTimelineBig" },
	movers = { "EldoUI_EncounterTimeline" },
	blizzard = {},
	savedKeys = { "profile.modules.EncounterTimeline" },
	optionsPage = "module:EncounterTimeline",
	presets = { "Accent", "Eldo", "Focus", "Framed", "Minimal", "Raid" },
	reload = false,
	defaults = {
		enabled = true,
		source = "auto",            -- auto | dbm | bigwigs | both
		orientation = "horizontal", -- horizontal | vertical
		reverse = false,            -- icons travel right (horizontal) or up (vertical)
		window = 20,                -- seconds ahead, 10-60
		length = 320,               -- the bar along the travel axis, 160-600 (layouts set it)
		thickness = 40,             -- across it, 32-48
		iconSize = 28,              -- 16-36, at most thickness - 4
		lanes = true,               -- icons that would touch take an upper and a lower lane
		waiting = { enabled = true, max = 3 },
		ticks = { enabled = true, every = 5, labels = true },
		zones = true,               -- tint the last warn / bad seconds of the track
		backing = "strip",          -- strip | panel | none
		border = "bossmod",         -- bossmod | accent | none
		numbers = 10,               -- seconds on the icons from this many seconds (0 = off)
		tenths = false,             -- one decimal under 1 s
		stages = { warn = 5, bad = 3 },
		tooltip = "off",            -- off | anchor | cursor
		names = "off",              -- off | side (vertical only)
		font = "THEME",
		fontSize = 12,
		bigIcon = {
			enabled = true,
			seconds = 5,
			size = 64,
			max = 1,
			swipe = true,
			glow = true,
			name = false,
		},
		sound = {
			countdown = false,      -- loud: off by default
			from = 5,
			tick = "kit:UI_COUNTDOWN_TIMER",
			final = "kit:UI_COUNTDOWN_FINISHED",
			channel = "default",    -- default follows General > Sound channel
			onlySoon = true,
		},
		events = {
			boss = true, pull = true, breaks = true, readyCheck = false, other = false,
			minDuration = 0,
		},
		fadeDBM = false,
		fadeDBMAlpha = 0,
		visibility = E:VisibilityDefaults({ hideVehicle = true }),
	},
})

E:RegisterFeatureConflicts("encountertimeline", { "AbilityTimeline" })

E:RegisterGlowUser("encounterTimeline", {
	title = "Encounter Timeline",
	desc = "Glow on the big icon of the Encounter Timeline in the last seconds before an event.",
	order = 60,
	button = true,
	default = { style = "pixel", colorMode = "accent" },
})

-- Blizzard's own countdown sounds as picks in the sound lists (the kits
-- Blizzard's pull countdown plays). Only names the client has are listed.
if SOUNDKIT then
	if SOUNDKIT.UI_COUNTDOWN_TIMER then
		E:RegisterMedia("sound", "kit:UI_COUNTDOWN_TIMER", "Countdown tick", SOUNDKIT.UI_COUNTDOWN_TIMER, { source = "Game", type = "kit", tags = { "game" } })
	end
	if SOUNDKIT.UI_COUNTDOWN_FINISHED then
		E:RegisterMedia("sound", "kit:UI_COUNTDOWN_FINISHED", "Countdown end", SOUNDKIT.UI_COUNTDOWN_FINISHED, { source = "Game", type = "kit", tags = { "game" } })
	end
end

local issecret = issecretvalue or function() return false end

function M.IsSecret(value)
	return issecret(value) and true or false
end

-- A plain number, or nil (secrets, strings and nil give nil).
function M.Number(value)
	if issecret(value) or type(value) ~= "number" then return nil end
	if value ~= value then return nil end -- NaN
	return value
end

-- A plain non-empty string, or nil.
function M.String(value)
	if issecret(value) or type(value) ~= "string" or value == "" then return nil end
	return value
end

local function Clamp(value, low, high, fallback)
	value = tonumber(value) or fallback
	if value < low then return low end
	if value > high then return high end
	return value
end
M.Clamp = Clamp

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------
-- The values the bar uses, clamped (a hand-edited or imported profile can
-- hold anything).
function M:Settings()
	local db = self.db
	local s = self.cache or {}
	self.cache = s
	s.vertical = db.orientation == "vertical"
	s.reverse = db.reverse and true or false
	s.window = Clamp(db.window, 10, 60, 20)
	s.length = Clamp(db.length, 160, 600, 320)
	s.thickness = Clamp(db.thickness, 32, 48, 40)
	s.iconSize = math.min(Clamp(db.iconSize, 16, 36, 28), s.thickness - 4)
	s.lanes = db.lanes and true or false
	s.waiting = db.waiting.enabled and true or false
	s.waitMax = math.floor(Clamp(db.waiting.max, 1, 6, 3))
	s.ticks = db.ticks.enabled and true or false
	s.tickEvery = Clamp(db.ticks.every, 2, 15, 5)
	s.tickLabels = db.ticks.labels and true or false
	s.zones = db.zones and true or false
	s.backing = (db.backing == "panel" or db.backing == "none") and db.backing or "strip"
	s.border = (db.border == "accent" or db.border == "none") and db.border or "bossmod"
	s.numbers = Clamp(db.numbers, 0, 30, 10)
	s.tenths = db.tenths and true or false
	s.bad = Clamp(db.stages.bad, 1, 10, 3)
	s.warn = math.max(Clamp(db.stages.warn, 1, 10, 5), s.bad)
	s.tooltip = (db.tooltip == "anchor" or db.tooltip == "cursor") and db.tooltip or "off"
	s.names = s.vertical and db.names == "side"
	s.font = db.font
	s.fontSize = Clamp(db.fontSize, 9, 16, 12)
	local big = db.bigIcon
	s.big = big.enabled and true or false
	s.bigSeconds = Clamp(big.seconds, 2, 10, 5)
	s.bigSize = Clamp(big.size, 40, 64, 64)
	s.bigMax = math.floor(Clamp(big.max, 1, 3, 1))
	s.bigSwipe = big.swipe and true or false
	s.bigGlow = big.glow and true or false
	s.bigName = big.name and true or false
	local sound = db.sound
	s.sound = sound.countdown and true or false
	s.soundFrom = math.floor(Clamp(sound.from, 3, 10, 5))
	s.onlySoon = sound.onlySoon ~= false
	s.minDuration = Clamp(db.events.minDuration, 0, 20, 0)
	s.motion = not (E.db and E.db.general and E.db.general.animations == false)
	return s
end

-- Settings migrations: one place for later key changes. `version` has no
-- default on purpose: a value equal to its default is not saved, so a
-- profile from before any migration has none and counts as version 1.
--   2: the big icon joined the bar's frame and mover. A bar the player
--      moved keeps its place on screen: its saved point moves by where the
--      bar now sits in the bigger frame. The big icon has no mover of its
--      own any more: its saved place and lock are dropped, and a box that
--      was attached to it keeps its place on screen.
function M:Migrate()
	local db = self.db
	if type(db.version) ~= "number" then db.version = 1 end
	if db.stages.bad > db.stages.warn then db.stages.bad = db.stages.warn end
	if db.version < 2 then self:MigrateFrame() end
	db.version = 2
end

-- How far along the width and the height each anchor point sits.
local POINT_FRACTION = {
	TOPLEFT = { 0, 1 }, TOP = { 0.5, 1 }, TOPRIGHT = { 1, 1 },
	LEFT = { 0, 0.5 }, CENTER = { 0.5, 0.5 }, RIGHT = { 1, 0.5 },
	BOTTOMLEFT = { 0, 0 }, BOTTOM = { 0.5, 0 }, BOTTOMRIGHT = { 1, 0 },
}

-- A point that places the bar (point, relativeTo, relativePoint, x, y)
-- turned into the point that places the whole frame around it, so the bar
-- lands on the same spot. Any other shape comes back as it is.
function M:FramePoint(point)
	local fraction = type(point) == "table" and POINT_FRACTION[point[1]]
	if not (fraction and type(point[4]) == "number" and type(point[5]) == "number") then return point end
	local layout = self:FrameLayout(self.cache or self:Settings())
	local out = {}
	for key, value in pairs(point) do out[key] = value end
	out[4] = point[4] - layout.barX + fraction[1] * (layout.width - layout.barW)
	out[5] = point[5] - layout.barY + fraction[2] * (layout.height - layout.barH)
	return out
end

local OLD_BIG = "EldoUI_EncounterTimelineBig"

function M:MigrateFrame()
	local movers = E.db and E.db.movers
	if type(movers) ~= "table" then return end
	self:DropBigMover(movers)
	local pos = movers.EldoUI_EncounterTimeline
	if type(pos) ~= "table" or pos.link ~= nil or pos[2] ~= "UIParent" or pos[3] ~= pos[1] then return end
	self:Settings() -- this profile's sizes, not the last one's
	local moved = self:FramePoint(pos)
	if moved == pos then return end
	pos[4], pos[5] = moved[4], moved[5]
	self.migratedFrame = true
end

-- The big icon's old mover: its saved place and lock go. A box attached to
-- it keeps the screen place its link remembers; a box chained to it moves
-- onto the timeline, which now holds the big icon.
function M:DropBigMover(movers)
	if movers[OLD_BIG] ~= nil then
		movers[OLD_BIG] = nil
		self.droppedBig = true
	end
	if E.db.moverLocks then E.db.moverLocks[OLD_BIG] = nil end
	for _, pos in pairs(movers) do
		if type(pos) == "table" then
			if type(pos.link) == "table" and pos.link.to == OLD_BIG then pos.link = nil end
			if pos[2] == OLD_BIG .. "Mover" then pos[2] = "EldoUI_EncounterTimelineMover" end
		end
	end
end

---------------------------------------------------------------------------
-- Kinds of events and their switches
---------------------------------------------------------------------------
M.KIND_SWITCH = { boss = "boss", pull = "pull", ["break"] = "breaks", ready = "readyCheck", other = "other" }

-- Does a row pass the event switches and the "shorter than" filter?
function M:Wanted(row)
	if row.kind == "test" then return true end
	local switch = self.KIND_SWITCH[row.kind]
	if not (switch and self.db.events[switch]) then return false end
	local s = self.cache or self:Settings()
	if s.minDuration > 0 and row.duration < s.minDuration and row.kind ~= "pull" and row.kind ~= "ready" then return false end
	return true
end

---------------------------------------------------------------------------
-- Frames and movers
---------------------------------------------------------------------------
-- One frame holds the big icons and the bar (Bar.lua's FrameLayout), so
-- move mode shows one box and the two are always placed together.
function M:CreateFrames()
	if self.frames then return end
	self.frames = true
	local frame = CreateFrame("Frame", "EldoUI_EncounterTimeline", UIParent)
	frame:SetFrameStrata("MEDIUM")
	frame:SetSize(392, 64)
	frame:EnableMouse(false)
	self.frame = frame
	self:CreateBar(frame)
	self:CreateSoon(frame)
	E:CreateMover(frame, "EldoUI_EncounterTimeline", L["Encounter Timeline"], { "CENTER", "UIParent", "CENTER", 716, -124 },
		{ group = "Combat" })
end

-- The layouts place the bar: a layout's point says where the bar sits. The
-- frame around it (the big icons and the tick numbers) grows from there,
-- so the bar keeps its layout spot whatever the big icon settings are, and
-- the layouts' placement data stays as it is.
E:RegisterMoverPointHook("EldoUI_EncounterTimeline", function(name)
	if not M.frame then return nil end
	local point = E.GetRoleMoverPoint and E:GetRoleMoverPoint(name) or E:GetLayoutPoint(name)
	if type(point) ~= "table" then return nil end
	return M:FramePoint(point)
end)

-- A new frame shape (big icons on or off, a longer bar, another direction)
-- places the frame again, so the bar stays on its layout spot.
function M:PlaceFrame()
	local layout = self.frameLayout
	if not layout then return end
	local shape = ("%s:%s:%s:%s:%s:%s"):format(layout.width, layout.height, layout.barX, layout.barY, layout.barW, layout.barH)
	if shape == self.placedShape then return end
	local first = self.placedShape == nil
	self.placedShape = shape
	if not first then E:ApplyMover("EldoUI_EncounterTimeline") end
end

function M:UpdateVisibility()
	local frame = self.frame
	if E:IsVisibilityAttached(frame) then
		E:UpdateVisibility(frame)
	else
		E:AttachVisibility(frame, self.db.visibility, {
			forceShow = function() return E:IsMoveMode() or M.testing ~= nil end,
		})
	end
end

-- Everything that depends on the settings or the theme.
function M:ApplyAll()
	self:Settings()
	self:ApplyBarLook()
	self:PlaceFrame()
	self:ApplySoonLook()
	self:Refresh()
end

-- Redraw after a row change or a setting change. While the driver runs,
-- the redraw is its next frame: ten timers that start together cost one
-- step. With the driver gone (no rows left) it is drawn at once, so the
-- last row clears.
function M:Refresh()
	if not self.active then return end
	self:UpdateDriver()
	if self.driver:IsShown() then
		self:StepNext()
	else
		self:Tick(true)
	end
end

---------------------------------------------------------------------------
-- Enable / disable
---------------------------------------------------------------------------
function M:OnInitialize()
	self:Migrate()
end

function M:OnEnable()
	self:Migrate()
	self:Settings()
	self:CreateFrames()
	self.frame:Show()
	self:ApplyAll()
	self:UpdateVisibility()
	self:EnableSources()
	self.lastOrientation = self.db.orientation
end

function M:OnDisable()
	self:StopTest(true)
	self:DisableSources()
	self:ClearAll(true)
	self:HideSample()
	self:UpdateDriver()
	if self.frame then
		E:DetachVisibility(self.frame)
		self.frame:Hide()
	end
	self:ApplyFade()
end

function M:OnProfileChanged()
	self:Migrate()
	if not self.active then return end
	self:ApplyAll()
	self:UpdateVisibility()
	self:UpdateSources()
	self:ApplyFade()
	-- Vertical has no layout spot: say so once, with a way to move it.
	if self.db.orientation == "vertical" and self.lastOrientation ~= "vertical" then
		self:VerticalNotice()
	end
	self.lastOrientation = self.db.orientation
end

function M:VerticalNotice()
	self.verticalNotices = (self.verticalNotices or 0) + 1
	M:PushAlert({
		key = "encounterTimelineVertical",
		title = L["Encounter Timeline"],
		text = L["The vertical bar has no place in the layouts. Drag it where you want it in move mode."],
		icon = 134376,
		actions = {
			{ label = L["Move it"], func = function()
				if InCombatLockdown() then return end
				E:ToggleMoveMode(true)
				E:SetMoverGroupFilter("Combat")
			end },
			{ label = L["Later"] },
		},
	})
end

-- Move mode shows the frame's box with its name and nothing under it, as
-- every box does; "Show test frames" plays a test fight and then keeps the
-- static sample (Test.lua), with the name on the tab above the box.
hooksecurefunc(E, "ToggleMoveMode", function()
	if not M.active then return end
	if not E:IsMoveMode() then M:HideSample() end
	M:Refresh()
end)
if E.SetMoveModeTest then
	hooksecurefunc(E, "SetMoveModeTest", function(_, state)
		if M.active and not state then M:HideSample() end
	end)
end

---------------------------------------------------------------------------
-- Commands, probe, diagnostics
---------------------------------------------------------------------------
local TESTS = { dungeon = true, raid = true, pull = true }

E:AddCommand("timeline", "[test dungeon | raid | pull | stop]  the Encounter Timeline page, or a test fight", function(arg)
	local word, rest = tostring(arg or ""):lower():match("^%s*(%S*)%s*(%S*)")
	if word ~= "test" then
		E:ToggleConfig("module:EncounterTimeline")
		return
	end
	if not M.active then
		E:Print(E:ModuleOffHint("EncounterTimeline"))
		return
	end
	if rest == "stop" then
		M:StopTest()
	else
		M:StartTest(TESTS[rest] and rest or "dungeon")
	end
end, "Tools")

local SOURCE_NAMES = { dbm = "DBM", bigwigs = "BigWigs", blizzard = "Blizzard", test = "Test" }
M.SOURCE_NAMES = SOURCE_NAMES

-- Lines for /eui probe timeline and /eui diag (English, for bug reports).
function M:StatusReport()
	local lines = {}
	local function Add(text) lines[#lines + 1] = text end
	Add(("DBM: %s"):format(self:DBMVersion() or "not loaded")) -- no-L: diagnostics stay English
	Add(("BigWigs: %s"):format(self:BigWigsVersion() or "not loaded")) -- no-L
	local listen = self:ActiveSources()
	Add(("Source setting: %s; listening to %s"):format(tostring(self.db.source), -- no-L
		(listen.dbm and listen.bigwigs) and "DBM and BigWigs" or listen.dbm and "DBM" or listen.bigwigs and "BigWigs" or "the pull countdown only"))
	local _, conflict = E:GetModuleConflict(self)
	if conflict then Add(("Off because %s is loaded"):format(conflict)) end -- no-L
	local api = C_EncounterTimeline
	if type(api) == "table" then
		local function Ask(name)
			local fn = api[name]
			if type(fn) ~= "function" then return "missing" end
			local ok, value = pcall(fn)
			if not ok then return "error" end
			if issecret(value) then return "secret" end
			return tostring(value)
		end
		Add(("C_EncounterTimeline: available %s, enabled %s, events %s"):format(Ask("IsFeatureAvailable"), -- no-L
			Ask("IsFeatureEnabled"), Ask("HasAnyEvents")))
	else
		Add("C_EncounterTimeline: missing") -- no-L
	end
	Add(("Events now: %d shown, %d stored; secrets skipped this session: %d"):format(self:CountShown(), self:CountRows(), -- no-L
		self.secretDrops or 0))
	local seen = self.received or {}
	if #seen > 0 then
		Add("Last timers received:") -- no-L
		for index = #seen, math.max(1, #seen - 9), -1 do
			local r = seen[index]
			Add(("  %s %s type=%s %.1fs secret:%s%s%s"):format(SOURCE_NAMES[r.source] or r.source, r.kind, tostring(r.simple or "-"), -- no-L
				r.duration or 0, r.secretText and " text" or "", r.secretIcon and " icon" or "", r.secretSpell and " spellId" or ""))
		end
	end
	return lines
end

E:RegisterProbe("timeline", "the timers DBM, BigWigs and the pull countdown hand the Encounter Timeline", function()
	E:Print(L["Encounter Timeline"])
	for _, line in ipairs(M:StatusReport()) do print("  " .. line) end
end)

E:RegisterDiagnostics("EncounterTimeline", function()
	if not M.initialized then return {} end
	local lines = { "   Encounter Timeline: " .. (M.active and "on" or "off") } -- no-L
	for _, line in ipairs(M:StatusReport()) do lines[#lines + 1] = "     " .. line end
	return lines
end)

---------------------------------------------------------------------------
-- Style presets: looks only. Never length, direction, travel, source,
-- events, sound or the DBM fade; thickness <= 40 and the big
-- icon <= 64, so the layouts' free space holds.
---------------------------------------------------------------------------
E:RegisterStyles("EncounterTimeline", {
	{ key = "Eldo", title = L["EldoUI"], desc = L["The default: flat strip, 28 px icons, a tick every 5 s, boss mod colors, the big icon with glow."],
		settings = { backing = "strip", thickness = 40, iconSize = 28, window = 20, ticks = { enabled = true, every = 5, labels = true },
			zones = true, border = "bossmod", numbers = 10, lanes = true, waiting = { max = 3 },
			bigIcon = { size = 64, swipe = true, glow = true } } },
	{ key = "Minimal", title = L["Minimal"], desc = L["Only the track line and the icons: no background, no tick numbers, a smaller big icon without glow."],
		settings = { backing = "none", thickness = 32, iconSize = 24, window = 20, ticks = { enabled = true, every = 5, labels = false },
			zones = false, border = "bossmod", numbers = 5, lanes = true, waiting = { max = 3 },
			bigIcon = { size = 48, swipe = true, glow = false } } },
	{ key = "Framed", title = L["Framed"], desc = L["The bar sits in a panel that follows your art style: Blizzard border, Classic stone, Forever bronze."],
		settings = { backing = "panel", thickness = 40, iconSize = 26, window = 20, ticks = { enabled = true, every = 5, labels = true },
			zones = true, border = "bossmod", numbers = 10, lanes = true, waiting = { max = 3 },
			bigIcon = { size = 64, swipe = true, glow = true } } },
	{ key = "Raid", title = L["Raid"], desc = L["Looks 30 s ahead with smaller icons and a tick every 10 s, for fights with many timers."],
		settings = { backing = "strip", thickness = 40, iconSize = 24, window = 30, ticks = { enabled = true, every = 10, labels = true },
			zones = true, border = "bossmod", numbers = 5, lanes = true, waiting = { max = 5 },
			bigIcon = { size = 56, swipe = true, glow = true } } },
	{ key = "Focus", title = L["Focus"], desc = L["Looks only 12 s ahead with big icons and early numbers, for fast dungeon pulls."],
		settings = { backing = "strip", thickness = 40, iconSize = 32, window = 12, ticks = { enabled = true, every = 5, labels = true },
			zones = true, border = "bossmod", numbers = 12, stages = { warn = 5, bad = 2 }, lanes = true, waiting = { max = 3 },
			bigIcon = { size = 64, swipe = true, glow = true } } },
	{ key = "Accent", title = L["Accent"], desc = L["Every icon border in your accent color, for a calm one-color bar."],
		settings = { backing = "strip", thickness = 40, iconSize = 28, window = 20, ticks = { enabled = true, every = 5, labels = true },
			zones = false, border = "accent", numbers = 10, lanes = true, waiting = { max = 3 },
			bigIcon = { size = 64, swipe = true, glow = true } } },
})
