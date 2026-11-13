-- EldoUI My Adventure: the character's journal as a tab in the
-- Loot Guide's Journal window. A diary that writes itself, keepsakes,
-- places, quests, the people you traveled with, goals and notes with
-- reminders, the story from 1 to 60 and where to go next.
--
-- This file is the module shell every Adventure file builds on:
--   * the module and its settings (E.db.modules.Adventure)
--   * parts: each file adds A:AddPart(key, { order, init, start, stop })
--     and the shell starts them while both this module and the Loot Guide
--     are on, and stops them in reverse order
--   * the revision counter and one coalesced redraw (A:MarkDirty)
--   * a time-sliced job runner for heavy work (roll-up, imports, exports):
--     4 ms a frame, never in combat
--   * addresses ("journal:quest:123") and their openers
--
-- The saved journal (Store.lua), the provider API E.Journal (Sources.lua,
-- also EldoUI.Journal for plugins) and the line kinds (Kinds.lua) load
-- right after this file. The other files reach this module as E.Adventure.
--
-- Rules (Midnight / Forever): presentation only. The journal writes down
-- what the game reports, never guesses hidden combat data and never acts
-- for the player: every action is navigation (a page, the map, a mark).
-- Secret values are dropped before anything is stored. Saved data lives
-- in EldoUIDB.journal[charKey], never in another saved table.
local _, E = ...
local L = E.L
local LG = E.LootGuide

local A = E:NewModule("Adventure", {
	title = "My Adventure",
	desc = "Your character's journal in the Journal window: a diary that writes itself, keepsakes, places, quests, goals and notes, your story from 1 to 60 and where to go next.",
	category = "Items & Economy",
	conflicts = { "ForeverJournal" },
	frames = {
		"EldoUI_JournalCardOverlay", "EldoUI_JournalMinimapButton", "EldoUI_JournalMoments",
		"EldoUI_JournalQuickNote", "EldoUI_JournalTracker",
	},
	movers = { "EldoUI_JournalMoments", "EldoUI_JournalTracker" },
	blizzard = {},
	savedKeys = {
		"profile.modules.Adventure", "EldoUIDB.journal", "EldoUIDB.journalBackups", "EldoUIDB.journalCache",
		"EldoUIDB.journalSeen",
	},
	optionsPage = "module:Adventure",
	presets = { "Chronicler", "Compact", "EldoUI", "Essentials", "Quiet", "Storybook" },
	reload = false,
	defaults = {
		style = "EldoUI",
		-- Journal
		record = true,           -- write the journal
		useStores = true,        -- Characters and Instances record while the journal does
		openOn = "today",        -- today, a section key, or "last"
		startClaimed = false,    -- My Adventure became the Journal window's start page once (UI/Hub.lua)
		momentFanfare = true,    -- moments also feed Fanfare's "Journal moment" triggers
		detail = "story",        -- essentials, story, chronicler, custom
		show = {},               -- the custom ticks (detail = "custom")
		lootMin = 4,             -- lowest quality a find needs on the Journey
		repMin = "all",          -- all, honored
		lootArmor = {},          -- [armor subclass] = false hides those finds
		keepsakes = true,
		journeyBy = "level",     -- level, day, zone
		foldChapters = true,
		storyLines = true,
		riverStrip = true,
		questGroup = "day",      -- day, level, zone, type
		questRewards = true,
		fleetingMinutes = 10,
		pinNewNotes = false,
		archiveReminders = true,
		archiveGoals = false,
		mapNotes = true,
		readingSize = 100,
		colorblind = "game",     -- game, on, off
		-- Story
		tone = "chronicle",      -- chronicle, bard, ledger
		storyLength = "standard", -- short, standard, long
		pronoun = "nameThey",
		nameCompanions = true,
		showSources = false,
		storyMotion = "general", -- general, off
		bookLook = "Parchment",  -- Parchment, EldoUI, Night
		page = "panel",          -- panel (the Journal window's own page), paper (parchment and dark ink; UI/Kit.lua K.OnPaper)
		-- Where next
		pickupCap = 2,
		nextWeights = "balanced", -- balanced, leveling, dungeons, collecting
		nextRaids = false,
		briefs = true,
		levelUpPage = true,
		prepChecklist = true,
		resumeAfter = 43200,
		sessionRecap = true,
		-- Moments and sounds
		moments = true,
		momentKinds = { zone = true, level = true, dungeon = true, goal = true, rested = true, keepsake = true, note = true },
		momentSeconds = 5,
		reminderSeconds = 8,
		momentsInDungeons = "after", -- now, after
		sounds = {
			goal = "kit:ALARM_CLOCK_WARNING_3", zone = "kit:IG_QUEST_LOG_OPEN", reminder = "kit:IG_PLAYER_INVITE",
			level = "none", dungeon = "none", rested = "none", keepsake = "none", note = "none",
		},
		soundMaster = false,
		screenshotButton = true,
		-- Tracker and buttons
		trackerGoals = true,
		trackerGoalsMax = 5,
		trackerReminders = true,
		trackerRemindersMax = 3,
		trackerNext = true,
		trackerHeight = 140,
		trackerDock = true,
		minimap = false,
		minimapAngle = 200,      -- degrees around the minimap edge (dragging the button sets it)
		gameMenu = true,
		-- Keeping it safe
		backupEvery = "day",     -- login, day, week, manual
		backupKeep = 3,
		-- Data
		observe = true,
	},
})
E.Adventure = A

-- The provider API (filled by Store.lua and Sources.lua). EldoUI's private
-- table is the global EldoUI, so plugins reach it as EldoUI.Journal.
local J = E.Journal or {}
E.Journal = J
A.J = J
J.module = A

-- Callbacks for pages and plugins: J.RegisterCallback(owner, event, fn).
--   "Logged"(charKey, row)   a row was written (row decoded, with seq)
--   "Changed"(ids)           sources changed (set of source ids), coalesced
--   "Redraw"(what)           one coalesced redraw (set of reasons)
--   "Started" / "Stopped"    the journal starts or stops running
--   "Cleared"(charKey)       a character's journal was cleared or forgotten
local CBH = LibStub and LibStub("CallbackHandler-1.0", true)
if CBH and not J.callbacks then J.callbacks = CBH:New(J) end

function A:Fire(event, ...)
	if J.callbacks then J.callbacks:Fire(event, ...) end
end

local Secret = E.Secret
A.Secret = Secret

-- A value the game gave, or nil when it is secret.
local Plain = E.Plain
A.Plain = Plain

---------------------------------------------------------------------------
-- Settings: ranges and choices are clamped once per load and profile
-- switch, so every file can trust them.
---------------------------------------------------------------------------
local RANGES = {
	fleetingMinutes = { 1, 60, 10 }, lootMin = { 2, 5, 4 }, readingSize = { 90, 140, 100 },
	pickupCap = { 0, 5, 2 }, momentSeconds = { 2, 12, 5 }, reminderSeconds = { 3, 20, 8 },
	trackerGoalsMax = { 1, 10, 5 }, trackerRemindersMax = { 1, 10, 3 }, trackerHeight = { 80, 300, 140 },
	backupKeep = { 1, 10, 3 }, resumeAfter = { 0, 604800, 43200 },
}
local CHOICES = {
	detail = { essentials = true, story = true, chronicler = true, custom = true },
	repMin = { all = true, honored = true },
	journeyBy = { level = true, day = true, zone = true },
	questGroup = { day = true, level = true, zone = true, type = true },
	colorblind = { game = true, on = true, off = true },
	tone = { chronicle = true, bard = true, ledger = true },
	storyLength = { short = true, standard = true, long = true },
	storyMotion = { general = true, off = true },
	bookLook = { Parchment = true, EldoUI = true, Night = true },
	page = { panel = true, paper = true },
	nextWeights = { balanced = true, leveling = true, dungeons = true, collecting = true },
	momentsInDungeons = { now = true, after = true },
	backupEvery = { login = true, day = true, week = true, manual = true },
}
A.RANGES, A.CHOICES = RANGES, CHOICES

local function Sanitize(db)
	if type(db) ~= "table" then return end
	for key, range in pairs(RANGES) do
		local value = tonumber(db[key]) or range[3]
		db[key] = math.min(math.max(value, range[1]), range[2])
	end
	for key, set in pairs(CHOICES) do
		if not set[db[key]] then db[key] = A.defaults[key] end
	end
	for _, key in ipairs({ "show", "lootArmor", "momentKinds", "sounds" }) do
		if type(db[key]) ~= "table" then db[key] = CopyTable(A.defaults[key]) end
	end
	if type(db.openOn) ~= "string" or db.openOn == "" then db.openOn = "today" end
end
A.Sanitize = Sanitize

---------------------------------------------------------------------------
-- Parts: A:AddPart(key, { order = n, init = fn, start = fn, stop = fn })
--   init   once in OnInitialize, also while the module is off (data
--          hygiene such as the Forget hook)
--   start  when the journal starts running (module and Loot Guide on)
--   stop   when it stops (reverse order); the saved journal stays
---------------------------------------------------------------------------
local parts, partList = {}, {}

local function SortParts()
	table.sort(partList, function(a, b)
		if a.order ~= b.order then return a.order < b.order end
		return a.key < b.key
	end)
end

local function CallPart(part, method)
	local fn = part[method]
	if type(fn) ~= "function" then return end
	local ok, err = pcall(fn, A)
	if not ok then geterrorhandler()(("EldoUI My Adventure part %s:%s failed: %s"):format(part.key, method, tostring(err))) end
end

function A:AddPart(key, def)
	assert(type(key) == "string" and type(def) == "table", "A:AddPart(key, def)")
	local part = parts[key]
	if not part then
		part = { key = key }
		parts[key] = part
		partList[#partList + 1] = part
	end
	part.order = tonumber(def.order) or 50
	part.init, part.start, part.stop = def.init, def.start, def.stop
	SortParts()
	if self.initialized and part.init and not part.inited then
		part.inited = true
		CallPart(part, "init")
	end
	if self.started and part.start then CallPart(part, "start") end
	return part
end

function A:Parts()
	return partList
end

-- The journal runs while this module and the Loot Guide are both on.
function A:Running()
	return self.active and LG and LG.active and true or false
end

function A:Start()
	if self.started or not self:Running() then return end
	self.started = true
	for _, part in ipairs(partList) do CallPart(part, "start") end
	self:Fire("Started")
	self:MarkDirty("all")
end

function A:Stop()
	if not self.started then return end
	self.started = false
	for index = #partList, 1, -1 do CallPart(partList[index], "stop") end
	self:CancelJobs()
	self:Fire("Stopped")
end

---------------------------------------------------------------------------
-- Redraw: A:MarkDirty(what) ... one "Redraw" callback a moment later with
-- every reason since, and the Loot Guide bus message "adventure".
---------------------------------------------------------------------------
local dirty, dirtyQueued = {}, false

local function FlushDirty()
	dirtyQueued = false
	local what = dirty
	dirty = {}
	A:Fire("Redraw", what)
	if LG and LG.active and LG.Fire then LG:Fire("adventure") end
end

function A:MarkDirty(what)
	dirty[what or "all"] = true
	if dirtyQueued then return end
	dirtyQueued = true
	C_Timer.After(0.1, FlushDirty)
end

---------------------------------------------------------------------------
-- Jobs: heavy work in slices. A job body runs in a coroutine and calls
-- A.JobYield() between steps; it pauses when its frame budget is spent and
-- while you are in combat. Never yield inside pcall (Lua 5.1).
--   A:RunJob(key, fn, done)  fn(); done(ok, err) when it ends; false when
--                            a job with that key is already running
--   A:JobRunning(key), A:CancelJob(key), A:CancelJobs()
--   A:FinishJobs()           runs every job to its end now (out of combat)
---------------------------------------------------------------------------
A.JOB_BUDGET_MS = 4
local jobs = {}          -- list of { key, co, done }
local jobTicker
local sliceStart = 0
local slicing = false

function A.JobYield()
	if not slicing then return end
	if debugprofilestop() - sliceStart >= A.JOB_BUDGET_MS then coroutine.yield() end
end

local function EndJob(index, ok, err)
	local job = table.remove(jobs, index)
	if not ok then geterrorhandler()(("EldoUI My Adventure job %s failed: %s"):format(job.key, tostring(err))) end
	if type(job.done) == "function" then
		local fine, why = pcall(job.done, ok, err)
		if not fine then geterrorhandler()(why) end
	end
end

local function StopTicker()
	if jobTicker then
		jobTicker:Cancel()
		jobTicker = nil
	end
end

local function Step(unlimited)
	if InCombatLockdown() then return end
	sliceStart = debugprofilestop()
	slicing = not unlimited
	while jobs[1] do
		local job = jobs[1]
		local ok, err = coroutine.resume(job.co)
		if not ok then
			EndJob(1, false, err)
		elseif coroutine.status(job.co) == "dead" then
			EndJob(1, true)
		end
		if not unlimited and debugprofilestop() - sliceStart >= A.JOB_BUDGET_MS then break end
	end
	slicing = false
	if not jobs[1] then StopTicker() end
end

function A:RunJob(key, fn, done)
	if type(key) ~= "string" or type(fn) ~= "function" then return false end
	if self:JobRunning(key) then return false end
	jobs[#jobs + 1] = { key = key, co = coroutine.create(fn), done = done }
	if not jobTicker then jobTicker = C_Timer.NewTicker(0.02, function() Step(false) end) end
	return true
end

function A:JobRunning(key)
	for _, job in ipairs(jobs) do
		if job.key == key then return true end
	end
	return false
end

function A:CancelJob(key)
	for index = #jobs, 1, -1 do
		if jobs[index].key == key then table.remove(jobs, index) end
	end
	if not jobs[1] then StopTicker() end
end

function A:CancelJobs()
	wipe(jobs)
	StopTicker()
end

function A:FinishJobs()
	if InCombatLockdown() then return false end
	Step(true)
	return not jobs[1]
end

---------------------------------------------------------------------------
-- Addresses: "journal:<kind>:<id>". Pages register an opener per kind:
--   J:RegisterAddress("quest", function(id, kind) ... return true end)
-- Kinds in use: quest, place, moment (a row's seq), fellow, section,
-- instance, item, goal, note.
---------------------------------------------------------------------------
local openers = {}

function J:Address(kind, id)
	if type(kind) ~= "string" or id == nil then return nil end
	return ("journal:%s:%s"):format(kind, tostring(id))
end

function J:ParseAddress(text)
	if type(text) ~= "string" then return nil end
	local kind, id = text:match("^journal:([%w_]+):(.+)$")
	if not kind then return nil end
	return kind, tonumber(id) or id
end

function J:RegisterAddress(kind, fn)
	if type(kind) ~= "string" then return end
	openers[kind] = type(fn) == "function" and fn or nil
end

-- Opens what an address points at; false when nothing can show it now.
function J:Open(address)
	if not A:Running() then return false end
	local kind, id = self:ParseAddress(address)
	if not kind then return false end
	local opener = openers[kind]
	if opener then
		local ok, handled = pcall(opener, id, kind)
		if not ok then
			geterrorhandler()(handled)
			return false
		end
		return handled ~= false
	end
	if LG.GetPage and LG:GetPage("adventure") and LG.Open then
		LG:Open("adventure", address)
		return true
	end
	return false
end

---------------------------------------------------------------------------
-- Module life
---------------------------------------------------------------------------
function A:OnInitialize()
	Sanitize(self.db)
	for _, part in ipairs(partList) do
		if part.init and not part.inited then
			part.inited = true
			CallPart(part, "init")
		end
	end
	-- Start and stop with the Loot Guide.
	if LG then
		hooksecurefunc(LG, "OnEnable", function() if A.active then A:Start() end end)
		hooksecurefunc(LG, "OnDisable", function() A:Stop() end)
	end
end

function A:OnEnable()
	Sanitize(self.db)
	self:Start()
end

function A:OnDisable()
	self:Stop()
end

function A:OnProfileChanged()
	Sanitize(self.db)
	if not self:Running() then return end
	self:MarkDirty("settings")
end

-- The line the options page and the commands show while the journal
-- cannot run.
function A:OffReason()
	if not self.active then
		local _, conflict = E:GetModuleConflict(self)
		if conflict then return (L["My Adventure stays off while %s is loaded."]):format(conflict) end
		return L["My Adventure is off."]
	end
	if not (LG and LG.active) then return L["My Adventure lives in the Journal window. Turn the Loot Guide on to use it."] end
	return nil
end

-- The chat line that helps: the shared off line of My Adventure while the
-- journal itself is off, of the Loot Guide while only the Loot Guide is.
function A:OffHint()
	if not self:OffReason() then return nil end
	if not self.active then return E:ModuleOffHint("Adventure") end
	return E:ModuleOffHint("LootGuide", L["My Adventure lives in the Journal window."])
end
