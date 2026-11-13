-- Encounter Timeline: test fights and the static sample.
--
-- Forever's DBM ships almost no ability timers yet, so three scripted test
-- fights show what a fight looks like: "dungeon" (a dungeon boss), "raid"
-- (a busy raid boss with close timers and a waiting stack) and "pull"
-- (a pull countdown, then a break). Each script uses pause, resume, a
-- changed total and an early stop, and clears itself at the end. A real
-- boss-mod timer or pull countdown stops a running test first.
-- With "Show test frames" in move mode, the dungeon fight plays and the
-- static sample (frozen rows) follows it, so the frame keeps its look while
-- it is placed; plain move mode shows only the box.
-- Every name here is EldoUI's own; the icons are standard game icons.
local _, E = ...
local L = E.L
local M = E:GetModule("EncounterTimeline")

local ICONS = {
	cleave = "Interface\\Icons\\Ability_Warrior_Cleave",
	nova = "Interface\\Icons\\Spell_Fire_SealOfFire",
	adds = "Interface\\Icons\\Spell_Shadow_RaiseDead",
	bolt = "Interface\\Icons\\Spell_Shadow_ShadowBolt",
	enrage = "Interface\\Icons\\Ability_Druid_ChallangingRoar",
	storm = "Interface\\Icons\\Spell_Nature_Lightning",
	frost = "Interface\\Icons\\Spell_Frost_FrostNova",
	bomb = "Interface\\Icons\\INV_Misc_Bomb_04",
	shield = "Interface\\Icons\\Spell_Holy_PowerWordShield",
	phase = "Interface\\Icons\\Spell_Arcane_PortalDalaran",
}

-- DBM's color types (1 adds, 2 AoE, 3 targeted, 4 interrupt,
-- 6 stage), painted from the design tokens.
local function TypeColor(colorType)
	local text = E.tokens.text
	if colorType == 1 then return text.good end
	if colorType == 2 then return text.bad end
	if colorType == 3 then return text.warn end
	if colorType == 4 then return E.media.accentColor end
	if colorType == 6 then return text.secondary end
	return nil
end

-- Steps: { seconds after the start, action, id, data }; data.label is
-- the English name, translated where it is shown.
-- Shown translated: L["Crushing Cleave"], L["Fire Nova"], L["Bone Servants"], L["Shadow Volley"],
-- L["Enrage"], L["Chain Storm"], L["Frost Ring"], L["Living Bomb"], L["Ward of Spite"], L["Second Stage"],
-- L["Pull"], L["Break"]
M.TEST_SCRIPTS = {
	dungeon = {
		title = "Dungeon boss",
		steps = {
			{ 0, "begin", 1, { label = "Crushing Cleave", duration = 8, icon = ICONS.cleave, colorType = 3 } },
			{ 0, "begin", 2, { label = "Fire Nova", duration = 14, icon = ICONS.nova, colorType = 2 } },
			{ 0, "begin", 3, { label = "Bone Servants", duration = 22, icon = ICONS.adds, colorType = 1 } },
			{ 0, "begin", 4, { label = "Shadow Volley", duration = 30, icon = ICONS.bolt, colorType = 4 } },
			{ 0, "begin", 5, { label = "Enrage", duration = 45, icon = ICONS.enrage, colorType = 6 } },
			{ 8.5, "begin", 1, { label = "Crushing Cleave", duration = 12, icon = ICONS.cleave, colorType = 3 } },
			{ 10, "pause", 3 },
			{ 13, "resume", 3 },
			{ 15, "begin", 2, { label = "Fire Nova", duration = 14, icon = ICONS.nova, colorType = 2 } },
			{ 16, "update", 4, { elapsed = 16, total = 24 } },
			{ 20, "stop", 5 },
			{ 30, "done" },
		},
	},
	raid = {
		title = "Raid boss",
		steps = {
			{ 0, "begin", 1, { label = "Chain Storm", duration = 6, icon = ICONS.storm, colorType = 2 } },
			{ 0, "begin", 2, { label = "Frost Ring", duration = 6.5, icon = ICONS.frost, colorType = 3 } },
			{ 0, "begin", 3, { label = "Living Bomb", duration = 12, icon = ICONS.bomb, colorType = 3 } },
			{ 0, "begin", 4, { label = "Ward of Spite", duration = 17, icon = ICONS.shield, colorType = 4 } },
			{ 0, "begin", 5, { label = "Bone Servants", duration = 26, icon = ICONS.adds, colorType = 1 } },
			{ 0, "begin", 6, { label = "Shadow Volley", duration = 33, icon = ICONS.bolt, colorType = 2 } },
			{ 0, "begin", 7, { label = "Second Stage", duration = 40, icon = ICONS.phase, colorType = 6 } },
			{ 0, "begin", 8, { label = "Enrage", duration = 70, icon = ICONS.enrage, colorType = 6 } },
			{ 0, "begin", 9, { label = "Fire Nova", duration = 55, icon = ICONS.nova, colorType = 2 } },
			{ 7, "begin", 1, { label = "Chain Storm", duration = 9, icon = ICONS.storm, colorType = 2 } },
			{ 9, "pause", 4 },
			{ 12, "resume", 4 },
			{ 13, "update", 5, { elapsed = 13, total = 20 } },
			{ 18, "stop", 9 },
			{ 22, "stop", 8 },
			{ 41, "done" },
		},
	},
	pull = {
		title = "Pull and break",
		steps = {
			{ 0, "begin", 1, { label = "Pull", duration = 10, icon = M.KIND_ICON.pull } },
			{ 0, "begin", 2, { label = "Break", duration = 25, icon = M.KIND_ICON["break"] } },
			{ 4, "pause", 1 },
			{ 6, "resume", 1 },
			{ 8, "update", 2, { elapsed = 8, total = 20 } },
			{ 16, "stop", 2 },
			{ 17, "done" },
		},
	},
}
M.TEST_ORDER = { "dungeon", "raid", "pull" }

local function TestKey(id) return "test:" .. id end

local function RunStep(step)
	local action, id, data = step[2], step[3], step[4]
	if action == "begin" then
		M:Add({
			key = TestKey(id), source = "test", kind = "test", text = L[data.label], icon = data.icon,
			duration = data.duration, colorType = data.colorType, color = TypeColor(data.colorType),
		})
	elseif action == "pause" then
		M:Pause(TestKey(id))
	elseif action == "resume" then
		M:Resume(TestKey(id))
	elseif action == "update" then
		M:UpdateRow(TestKey(id), data.elapsed, data.total)
	elseif action == "stop" then
		M:Stop(TestKey(id))
	end
	M.testActions[action] = (M.testActions[action] or 0) + 1
end

M.testActions = {}

-- Play a test fight; a second click on the same one stops it.
function M:StartTest(name)
	if not self.active then return false end
	local script = self.TEST_SCRIPTS[name]
	if not script then return false end
	if self.testing == name then
		self:StopTest()
		return false
	end
	self:StopTest(true)
	self:HideSample()
	self.testing = name
	self.testStart = GetTime()
	self.testStep = 1
	wipe(self.testActions)
	self:UpdateVisibility()
	self:TestStep()
	self.testTicker = C_Timer.NewTicker(0.1, function() M:TestStep() end)
	self:Refresh()
	return true
end

function M:TestStep()
	local script = self.testing and self.TEST_SCRIPTS[self.testing]
	if not script then return end
	local elapsed = GetTime() - self.testStart
	while true do
		local step = script.steps[self.testStep]
		if not step or step[1] > elapsed + 1e-6 then break end
		self.testStep = self.testStep + 1
		if step[2] == "done" then
			self:StopTest()
			return
		end
		RunStep(step)
	end
	self:Refresh()
end

-- quiet: no visibility update (the next test starts at once).
function M:StopTest(quiet)
	if self.testTicker then
		self.testTicker:Cancel()
		self.testTicker = nil
	end
	local was = self.testing
	self.testing = nil
	self:RemoveWhere(function(row) return row.source == "test" end)
	if was and not quiet then
		self.testsFinished = (self.testsFinished or 0) + 1
		if self.frame then self:UpdateVisibility() end
		-- Test frames still on: the static sample keeps the frame's look.
		if self.active and E:IsMoveMode() and E:IsMoveModeTest() then self:ShowSample() end
	end
	if self.active then self:Refresh() end
end

---------------------------------------------------------------------------
-- Static sample (move mode with test frames): the big icon, close timers
-- in both lanes, single icons and a full waiting grid with its "+N".
---------------------------------------------------------------------------
-- Shown translated: L["Sample"]
local SAMPLE = {
	{ left = 2.5, icon = ICONS.storm, colorType = 2 },
	{ left = 7, icon = ICONS.cleave, colorType = 3 },
	{ left = 7.6, icon = ICONS.frost, colorType = 3 },
	{ left = 13, icon = ICONS.adds, colorType = 1 },
	{ left = 18, icon = ICONS.shield, colorType = 4 },
	{ left = 34, icon = ICONS.bolt, colorType = 2 },
	{ left = 48, icon = ICONS.phase, colorType = 6 },
	{ left = 75, icon = ICONS.enrage, colorType = 6 },
	{ left = 95, icon = ICONS.nova, colorType = 2 },
}
M.SAMPLE = SAMPLE

function M:ShowSample()
	if not self.active or self.sampleShown then return end
	for index, sample in ipairs(SAMPLE) do
		local duration = math.max(sample.left + 5, 20)
		self:Add({
			key = "sample:" .. index, source = "sample", kind = "test", text = L["Sample"], icon = sample.icon,
			duration = duration, elapsed = duration - sample.left, paused = true, sample = true,
			colorType = sample.colorType, color = TypeColor(sample.colorType),
		})
	end
	self.sampleShown = true
	self:Refresh()
end

function M:HideSample()
	if not self.sampleShown then return end
	self.sampleShown = nil
	self:RemoveWhere(function(row) return row.source == "sample" end)
	if self.active then self:Refresh() end
end
