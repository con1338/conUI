-- EldoUI My Adventure: the options page, its style presets and the layout
-- pairs.
--
-- One page "My Adventure" with tabs: Journal, Story, Where next, Moments
-- and sounds, Tracker and buttons, and (once their files add rows) Keeping
-- it safe and Data. Every row has a desc; a tab with no rows is left out,
-- so no page is a placeholder. The Presets tab (Core/Config.lua) comes last.
--
-- Rows other files own:
--   A.MomentOptions, A.TrackerOptions   placed on their tabs as they are
--   A:AddOptionRows(tab, rows)          more rows for a tab, from any file
--       tab: "journal", "story", "next", "moments", "tracker", "safe", "data"
--       (backups, export and import, entry points and the data page add
--       theirs here; the page is built the first time it opens)
--   A.Options.rows                      every row of the page, cog rows
--                                       included (tests, search)
--   A.Options.reasons                   settings without a row, and why
--
-- Settings that need more than a stored value (one place, after every
-- change on the page and on a profile switch):
--   useStores      calls A:StoresChanged()
--   detail         a preset fills Finds from and Reputation with its own
--                  floors; Custom starts from the preset you left
--   lootMin/repMin a change on a preset turns it into Custom
--
-- Style presets (E:RegisterStyles("Adventure")): EldoUI, Storybook,
-- Essentials, Chronicler, Compact and Quiet. Styles own the look, never
-- positions. Layout pairs: applying a layout preset gives the journal the
-- Book look of its paired style (EldoUI, Storybook or Compact) while
-- "Style follows the layout" is on; what the journal shows is kept.
local _, E = ...
local L = E.L
local LG = E.LootGuide
local A = E.Adventure
local J = E.Journal
if not A then return end

-- Defaults this page owns (Moments.lua adds momentFanfare the same way).
A.defaults.followLayout = true

-- A reset keeps the one-time Start page claim (UI/Hub.lua), so a reset
-- never moves the Loot Guide's start page again.
A.keepOnReset = A.keepOnReset or {}
if not tContains(A.keepOnReset, "startClaimed") then table.insert(A.keepOnReset, "startClaimed") end

local Options = A.Options or {}
A.Options = Options

local TABS = {
	{ key = "journal", label = L["Journal"] },
	{ key = "story", label = L["Story"] },
	{ key = "next", label = L["Where next"] },
	{ key = "moments", label = L["Moments and sounds"] },
	{ key = "tracker", label = L["Tracker and buttons"] },
	{ key = "safe", label = L["Keeping it safe"] },
	{ key = "data", label = L["Data"] },
}
Options.TABS = TABS

local extra = {}
for _, tab in ipairs(TABS) do extra[tab.key] = {} end
Options.extra = extra

-- More rows for a tab, from another file. Rows added after the page was
-- first built show after the next /reload.
function A:AddOptionRows(tab, rows)
	if type(rows) ~= "table" or not extra[tab] then return false end
	for _, row in ipairs(rows) do
		if type(row) == "table" then table.insert(extra[tab], row) end
	end
	return true
end

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function Running()
	return A:Running()
end

local function GuideOn()
	return LG and LG.active and true or false
end

local function NotCustom()
	return not (A.db and A.db.detail == "custom")
end

local function Copy(row)
	local out = {}
	for key, value in pairs(row) do out[key] = value end
	return out
end

-- The section My Adventure opens on: Today, every page section, or the
-- last one you had open. Links to other tabs (Dungeons, Open World) are
-- not sections of their own.
local function OpenOnValues()
	local values = { today = L["Today"], last = L["The last one you had open"] }
	if type(A.Sections) == "function" then
		local ok, defs = pcall(A.Sections, A)
		for _, def in ipairs(ok and type(defs) == "table" and defs or {}) do
			if type(def.key) == "string" and not def.link and type(def.title) == "string" then values[def.key] = def.title end
		end
	end
	return values
end

local function OpenOnOrder()
	local order = { "today" }
	if type(A.Sections) == "function" then
		local ok, defs = pcall(A.Sections, A)
		for _, def in ipairs(ok and type(defs) == "table" and defs or {}) do
			if type(def.key) == "string" and def.key ~= "today" and not def.link then order[#order + 1] = def.key end
		end
	end
	order[#order + 1] = "last"
	return order
end

-- Book looks the client can draw (Parchment needs the paper tokens).
local function LookValues()
	local values = { Parchment = L["Parchment"], EldoUI = L["EldoUI"], Night = L["Night ledger"] }
	local SV = A.StoryView
	if SV and type(SV.Looks) == "function" then
		local ok, looks = pcall(SV.Looks)
		if ok and type(looks) == "table" and #looks > 0 then
			values = {}
			for _, look in ipairs(looks) do values[look.key] = look.label end
		end
	end
	return values
end

---------------------------------------------------------------------------
-- The custom detail ticks (J.SHOW_KEYS, shown while "How much the journal
-- shows" is Custom)
---------------------------------------------------------------------------
local SHOW_ROWS = {
	spells = { E.Key("Spells and ranks"), E.Key("A row each time you learn a spell or a new rank.") },
	recipes = { "Recipes", E.Key("A row for each recipe you learn.") },
	professions = { E.Key("Professions and skills"), E.Key("New professions and each new skill rank, with a keepsake when you master one.") },
	respecs = { E.Key("Talent re-specs"), E.Key("A row when you reset your talents.") },
	bosses = { E.Key("Boss kills"), E.Key("A row for each boss you kill in a dungeon or raid, with a keepsake for the first kill.") },
	mounts = { E.Key("Mounts, pets and titles"), E.Key("New mounts, companion pets and titles.") },
	deaths = { "Deaths", E.Key("A row each time you die, with the place.") },
	zones = { E.Key("Places and dungeons"), E.Key("New zones, first visits to dungeons and raids, explored areas, quest chains and attunement steps.") },
	flights = { E.Key("Flight paths"), E.Key("A row for each flight path you learn.") },
	goals = { E.Key("Goals reached"), E.Key("A row when you set a goal and when you reach it.") },
	runs = { "Dungeon runs", E.Key("Each dungeon run with its time, dungeon quests and battlegrounds won or lost.") },
	companions = { "Companions", E.Key("People you meet and group with, group quests and your guild.") },
	gear = { E.Key("Gear upgrades"), E.Key("A row when you equip an item that is better than the one it replaced.") },
	challenges = { "Legacy challenges", E.Key("Legacy challenges you complete and each new Legacy level.") },
}

local function DetailCog()
	local rows = {}
	rows[#rows + 1] = { type = "select", key = "lootMin", label = L["Finds from"],
		values = { [2] = L["Uncommon (green)"], [3] = L["Rare (blue)"], [4] = L["Epic (purple)"], [5] = L["Legendary (orange)"] },
		order = { 2, 3, 4, 5 },
		desc = L["The lowest quality a find needs to be written on the Journey. Changing it on a preset turns it into Custom."] }
	rows[#rows + 1] = { type = "select", key = "repMin", label = L["Reputation"],
		values = { all = L["Every new standing"], honored = L["Honored and up only"] }, order = { "all", "honored" },
		desc = L["Every new standing, or Honored and up only. Changing it on a preset turns it into Custom."] }
	for _, key in ipairs(J.SHOW_KEYS or {}) do
		local text = SHOW_ROWS[key]
		if text then
			rows[#rows + 1] = { type = "toggle", key = "show." .. key, label = L[text[1]], desc = L[text[2]], hidden = NotCustom }
		end
	end
	return rows
end

---------------------------------------------------------------------------
-- Moments: one tick per kind and one sound per kind
---------------------------------------------------------------------------
local MOMENT_KINDS = {
	{ "zone", E.Key("New places"), E.Key("A card the first time you enter a zone. Stays off while Zone Info's zone toast is on.") },
	{ "level", E.Key("Level summaries"), E.Key("A card for each new level, with where you were and how long the level took. Stays off while Fanfare shows its own level-up text.") },
	{ "dungeon", E.Key("First dungeons"), E.Key("A card at the door the first time you enter a dungeon or raid.") },
	{ "goal", E.Key("Goals reached"), E.Key("A card when you reach one of your goals.") },
	{ "rested", "Well rested", E.Key("A card when your rested bonus is full.") },
	{ "keepsake", "Keepsakes", E.Key("A card for each big moment: a first boss kill, an epic find, a new mount, Honored and up, a mastered profession or an attunement.") },
	{ "note", E.Key("Notes saved"), E.Key("A short card when you save a note.") },
}

local SOUND_KINDS = {
	{ "level", E.Key("Level summary sound") }, { "zone", E.Key("New place sound") }, { "dungeon", E.Key("First dungeon sound") },
	{ "goal", E.Key("Goal reached sound") }, { "rested", E.Key("Well rested sound") }, { "keepsake", E.Key("Keepsake sound") },
	{ "note", E.Key("Note saved sound") }, { "reminder", E.Key("Reminder sound") },
}

local function KindTicks()
	local rows = {}
	for _, kind in ipairs(MOMENT_KINDS) do
		rows[#rows + 1] = { type = "toggle", key = "momentKinds." .. kind[1], label = L[kind[2]], desc = L[kind[3]] }
	end
	return rows
end

local function SoundRows()
	local rows = { { type = "header", label = L["Sounds"] } }
	for _, kind in ipairs(SOUND_KINDS) do
		rows[#rows + 1] = { type = "media", mediaKind = "sound", none = true, key = "sounds." .. kind[1], label = L[kind[2]],
			desc = L["Plays with this kind of moment. None: the card stays quiet."] }
	end
	return rows
end

---------------------------------------------------------------------------
-- The page
---------------------------------------------------------------------------
local function Add(list, rows)
	for _, row in ipairs(rows or {}) do list[#list + 1] = row end
end

local function JournalRows()
	return {
		{ type = "description", hidden = GuideOn,
			label = L["My Adventure lives in the Journal window. Turn the Loot Guide on to use it."] },
		{ type = "execute", label = L["Turn on the Loot Guide"], hidden = GuideOn,
			desc = L["Switches the Loot Guide module on; My Adventure comes with it."],
			func = function()
				E:SetModuleEnabled("LootGuide", true)
				if E.RefreshConfig then E:RefreshConfig() end
			end },
		{ type = "execute", label = L["Open My Adventure"], hidden = function() return not Running() end,
			desc = L["Opens the Journal window on My Adventure."],
			func = function() if LG and LG.Open then LG:Open("adventure") end end },

		{ type = "header", label = L["Writing"] },
		{ type = "toggle", key = "record", label = L["Write the journal"],
			desc = L["Write down what this character does: levels, places, quests, finds, people, goals and notes. Off: the journal keeps what it has and adds nothing."] },
		{ type = "toggle", key = "useStores", label = L["Use the Characters and Instances records"],
			desc = L["Lets the journal fill your level log, quest history and dungeon runs even while the Characters and Instances windows are off. Nothing is kept twice."] },
		{ type = "select", label = L["Open on"], values = OpenOnValues, order = OpenOnOrder(),
			key = "openOn", -- lint: unused-key ok (read by UI/Hub.lua, StartSection)
			desc = L["The section My Adventure opens on: Today, a page you pick (Next trips, Journey, Book, Story so far, Keepsakes, Places, Quests, Fellowship, Goals or Notes), or the last one you had open."] },

		{ type = "header", label = L["What the pages show"] },
		{ type = "select", key = "detail", label = L["How much the journal shows"],
			values = { essentials = L["Essentials"], story = L["Storyteller"], chronicler = L["Chronicler"], custom = L["Custom"] },
			order = { "essentials", "story", "chronicler", "custom" },
			desc = L["What the pages show; everything is always written down. Essentials: levels, deaths, notes, goals. Storyteller: adds spells, professions and places. Chronicler: everything."],
			cog = DetailCog() },
		{ type = "toggle", key = "keepsakes", label = L["Big moments as keepsakes"],
			desc = L["First boss kills, epic finds, Honored and up, new mounts, mastered professions and attunements get their own card. Off: they are plain rows."] },
		{ type = "select", key = "journeyBy", label = L["Journey by"],
			values = { level = L["Level"], day = L["Day"], zone = L["Zone"] }, order = { "level", "day", "zone" },
			desc = L["Chapters by level, or groups by day or by zone."] },
		{ type = "toggle", key = "foldChapters", label = L["Fold older chapters"],
			desc = L["Chapters older than the last two start folded."] },

		{ type = "header", label = L["Quests and companions"] },
		{ type = "select", key = "questGroup", label = L["Quests grouped by"],
			values = { day = L["Day"], level = L["Level"], zone = L["Zone"], type = L["Type"] }, order = { "day", "level", "zone", "type" },
			desc = L["How the Quests page groups the quests you handed in: by day, level, zone or type."] },
		{ type = "toggle", key = "questRewards", label = L["Quest rewards"],
			desc = L["Experience and money next to each quest you handed in."] },
		{ type = "range", key = "fleetingMinutes", label = L["Met in passing under"], unit = "min", min = 1, max = 60, step = 1,
			desc = L["Companions with less time together than this go in Fleeting company on the Fellowship page."] },

		{ type = "header", label = L["Notes and goals"] },
		{ type = "toggle", key = "pinNewNotes", label = L["Pin new notes to the Journey"],
			desc = L["New notes start pinned under the level you wrote them at."] },
		{ type = "toggle", key = "archiveReminders", label = L["Archive finished reminders"],
			desc = L["A one-time reminder moves to the archive once it has fired or you mark it done."] },
		{ type = "toggle", key = "archiveGoals", label = L["Archive reached goals"],
			desc = L["A reached goal moves to the archive instead of staying in the Reached list."] },

		{ type = "header", label = L["Look"] },
		{ type = "select", key = "page", label = L["Page look"],
			values = { panel = L["Journal window"], paper = L["Paper"] }, order = { "panel", "paper" },
			desc = L["The pages of My Adventure on the Journal window's own dark panel, or on parchment with dark ink. The Book and the character card keep their own Book look."] },
		{ type = "toggle", key = "followLayout", label = L["Style follows the layout"],
			desc = L["When you apply a layout preset, the Book takes the look of the style that fits it: EldoUI, Storybook or Compact. What the journal shows is kept."] },
	}
end

local function StoryRows()
	return {
		{ type = "header", label = L["Telling"] },
		{ type = "select", key = "tone", label = L["Tone"],
			values = { chronicle = L["Chronicle"], bard = L["Bard"], ledger = L["Ledger"] }, order = { "chronicle", "bard", "ledger" },
			desc = L["How the story is told: Chronicle (a careful record), Bard (warm and heroic) or Ledger (facts only, short rows). The facts are the same in every tone."] },
		{ type = "select", key = "storyLength", label = L["How much story"],
			values = { short = L["Short"], standard = L["Standard"], long = L["Long"] }, order = { "short", "standard", "long" },
			desc = L["Short, standard or long chapters. Short chapters keep only the biggest moments."] },
		{ type = "select", key = "pronoun", label = L["Refer to my character as"],
			values = { nameThey = L["My name, then they"], name = L["Always my name"], she = L["She"], he = L["He"] },
			order = { "nameThey", "name", "she", "he" },
			desc = L["Your name, or the pronoun you pick. Exports always use your name."] },
		{ type = "toggle", key = "nameCompanions", label = L["Name companions in the story"],
			desc = L["Write the names of people you grouped with. They are left out of the character card and exports unless you check them there."] },
		{ type = "toggle", key = "showSources", label = L["Show sources"],
			desc = L["A small mark after each sentence; hover it to see the facts the sentence comes from."] },
		{ type = "execute", label = L["Reshuffle wording"],
			desc = L["Picks new wording for the whole story. The facts don't change."],
			func = function()
				local SV = A.StoryView
				if SV and type(SV.Reshuffle) == "function" then SV.Reshuffle() end
			end },

		{ type = "header", label = L["Pages"] },
		{ type = "select", key = "bookLook", label = L["Book look"], values = LookValues, order = { "Parchment", "EldoUI", "Night" },
			desc = L["Parchment, EldoUI or Night ledger for the Book and the character card."] },
		{ type = "range", key = "readingSize", label = L["Reading size"], unit = "%", min = 90, max = 140, step = 5,
			desc = L["Text size of the story in the Book and Story so far, 90 to 140%."] },
		{ type = "select", key = "storyMotion", label = L["Story motion"],
			values = { general = L["Follow General > Animations"], off = L["Off"] }, order = { "general", "off" },
			desc = L["Page turns and the river draw in. Follows General > Animations unless you turn it off here."] },
	}
end

local function NextRows()
	return {
		{ type = "header", label = L["Suggestions"] },
		{ type = "range", key = "pickupCap", label = L["Levels above you"], min = 0, max = 5, step = 1,
			desc = L["Quests above your level by more than this are not suggested."] },
		{ type = "select", key = "nextWeights", label = L["Suggestions lean to"],
			values = { balanced = L["Balanced"], leveling = L["Leveling"], dungeons = L["Dungeons"], collecting = L["Collecting"] },
			order = { "balanced", "leveling", "dungeons", "collecting" },
			desc = L["Balanced, Leveling (zones and chains), Dungeons (dungeons, prep and attunements) or Collecting (reputation, rares and goals)."] },
		{ type = "toggle", key = "nextRaids", label = L["Suggest raids"],
			desc = L["Next trips also lists raids that fit you."] },
		{ type = "toggle", key = "prepChecklist", label = L["Dungeon prep checklist"],
			desc = L["Bag space, repairs, food and water, ammo and hearthstone on the trip card. Nothing is bought or used."] },

		{ type = "header", label = L["On the way"] },
		{ type = "toggle", key = "briefs", label = L["Arrival and dungeon briefs"],
			desc = L["A short card when you enter a zone or a dungeon: your quests there, rares, your notes and your last run. Off in combat."] },
		{ type = "toggle", key = "levelUpPage", label = L["What opens at the next level"],
			desc = L["On a level-up the moment links to the dungeons, quests, spells and attunement steps that just opened."] },
		{ type = "toggle", key = "sessionRecap", label = L["Session recap when you log out"],
			desc = L["A short summary of the session during the logout countdown, also kept as a row in the Day view."] },
	}
end

local function MomentRows()
	local rows = { { type = "header", label = L["Moments"] } }
	for _, row in ipairs(A.MomentOptions or {}) do
		local copy = Copy(row)
		if copy.key == "moments" then copy.cog = KindTicks() end
		rows[#rows + 1] = copy
	end
	Add(rows, SoundRows())
	return rows
end

local function TrackerRows()
	local rows = { { type = "header", label = L["Journal tracker"] } }
	for _, row in ipairs(A.TrackerOptions or {}) do rows[#rows + 1] = Copy(row) end
	return rows
end

local BUILDERS = { journal = JournalRows, story = StoryRows, next = NextRows, moments = MomentRows, tracker = TrackerRows }
Options.BUILDERS = BUILDERS

-- Every row of a list, cog rows included.
local function Flatten(list, out)
	for _, row in ipairs(list) do
		out[#out + 1] = row
		if type(row.cog) == "table" then Flatten(row.cog, out) end
		if row.type == "cog" and type(row.options) == "table" then Flatten(row.options, out) end
	end
	return out
end

function Options.Build()
	local options = {}
	for _, tab in ipairs(TABS) do
		local rows = {}
		if BUILDERS[tab.key] then Add(rows, BUILDERS[tab.key]()) end
		Add(rows, extra[tab.key])
		-- A tab with nothing to change is left out (no placeholder pages).
		local real = false
		for _, row in ipairs(rows) do
			if row.type ~= "header" and row.type ~= "description" then real = true break end
		end
		if real then
			options[#options + 1] = { type = "tab", label = tab.label }
			Add(options, rows)
		end
	end
	Options.rows = Flatten(options, {})
	return options
end

-- Built the first time the page opens (sections and other files' rows
-- are all registered by then).
A.options = function() return Options.Build() end

-- Settings without a row of their own, and why (the journaloptions check).
Options.reasons = {
	enabled = "the module switch at the top of the page",
	style = "the Presets tab (style presets)",
	startClaimed = "a one-time flag: My Adventure became the Journal window's start page once",
	minimapAngle = "set by dragging the minimap button around the edge",
	lootArmor = "set from the armor tiles of the Journey filter; no page draws them yet",
	colorblind = "the color-blind safe set (E.tokens.palette.safe) has no reader on the journal pages yet",
}

---------------------------------------------------------------------------
-- Settings that need more than a stored value
---------------------------------------------------------------------------
local seen = {}

local function Remember()
	local db = A.db
	if type(db) ~= "table" then return end
	seen.useStores, seen.detail, seen.lootMin, seen.repMin = db.useStores, db.detail, db.lootMin, db.repMin
end

function Options.Watch()
	local db = A.db
	if type(db) ~= "table" then return end
	if seen.useStores ~= nil and seen.useStores ~= db.useStores and type(A.StoresChanged) == "function" then
		A:StoresChanged()
	end
	local presets = J.DETAIL or {}
	if seen.detail ~= nil and seen.detail ~= db.detail then
		if db.detail == "custom" then
			-- Custom starts from the preset you left (once; later visits keep your ticks).
			if type(db.show) ~= "table" or next(db.show) == nil then
				db.show = {}
				for key, value in pairs(presets[seen.detail] or presets.story or {}) do db.show[key] = value end
			end
			if db.show.lootMin ~= nil then db.lootMin = db.show.lootMin end
			if db.show.repMin ~= nil then db.repMin = db.show.repMin end
		elseif presets[db.detail] then
			db.lootMin, db.repMin = presets[db.detail].lootMin, presets[db.detail].repMin
		end
	elseif db.detail ~= "custom" and (seen.lootMin ~= db.lootMin or seen.repMin ~= db.repMin) and seen.detail ~= nil then
		-- A floor changed on a preset: the preset becomes Custom.
		if type(J.SetShows) == "function" then
			J:SetShows("lootMin", db.lootMin)
			J:SetShows("repMin", db.repMin)
		end
	end
	if db.detail == "custom" and type(db.show) == "table" then
		db.show.lootMin, db.show.repMin = db.lootMin, db.repMin
	end
	Remember()
end

hooksecurefunc(A, "OnProfileChanged", function() Options.Watch() end)

A:AddPart("options", {
	order = 1,
	init = Remember,
	start = Remember,
})

---------------------------------------------------------------------------
-- Style presets (design.md 8; styles own the look, never positions)
---------------------------------------------------------------------------
local ALL_KINDS = { zone = true, level = true, dungeon = true, goal = true, rested = true, keepsake = true, note = true }
local NO_SOUNDS = { goal = "none", zone = "none", reminder = "none", level = "none", dungeon = "none", rested = "none",
	keepsake = "none", note = "none" }

local STYLES = {
	{ key = "EldoUI", title = "EldoUI",
		desc = L["The Journal window's dark page and the EldoUI Book, the Storyteller detail with keepsakes, the tracker under your quests and moments in the alert lane."],
		look = { bookLook = "EldoUI" },
		settings = {
			bookLook = "EldoUI", tone = "chronicle", detail = "story", keepsakes = true, foldChapters = true, storyLength = "standard",
			trackerGoals = true, trackerGoalsMax = 5, trackerReminders = true, trackerRemindersMax = 3, trackerNext = true, trackerHeight = 140,
			moments = true, momentSeconds = 5, momentKinds = ALL_KINDS, sounds = A.defaults.sounds,
		} },
	{ key = "Storybook", title = "Storybook",
		desc = L["Parchment pages with dark ink for the Book and the character card, told as a Chronicle."],
		look = { bookLook = "Parchment" },
		settings = { bookLook = "Parchment", tone = "chronicle", keepsakes = true } },
	{ key = "Essentials", title = "Essentials",
		desc = L["Levels, deaths, notes, goals and keepsakes only. Short chapters, a small tracker and moments for levels, first dungeons, goals and keepsakes."],
		settings = {
			detail = "essentials", storyLength = "short", foldChapters = true,
			trackerGoalsMax = 3, trackerRemindersMax = 2, trackerHeight = 100,
			momentKinds = { zone = false, level = true, dungeon = true, goal = true, rested = false, keepsake = true, note = false },
		} },
	{ key = "Chronicler", title = "Chronicler",
		desc = L["Everything, rare (blue) finds too, long chapters, every chapter open and a taller tracker."],
		settings = { detail = "chronicler", foldChapters = false, storyLength = "long", trackerGoalsMax = 8, trackerRemindersMax = 5, trackerHeight = 220 } },
	{ key = "Compact", title = "Compact",
		desc = L["The Night ledger Book in smaller text, short chapters and a slim tracker. Row size stays the Loot Guide's own setting."],
		look = { bookLook = "Night" },
		settings = { bookLook = "Night", readingSize = 90, storyLength = "short", trackerGoalsMax = 3, trackerRemindersMax = 2, trackerHeight = 100 } },
	{ key = "Quiet", title = "Quiet",
		desc = L["No moments, no sounds, no tracker. The journal still writes everything down, and reminders still show."],
		settings = { moments = false, sounds = NO_SOUNDS, trackerGoals = false, trackerReminders = false, trackerNext = false } },
}
Options.STYLES = STYLES
E:RegisterStyles("Adventure", STYLES)

local function Style(key)
	for _, style in ipairs(STYLES) do
		if style.key == key then return style end
	end
end
Options.Style = Style

---------------------------------------------------------------------------
-- Layout pairs: the style whose look fits each layout preset. Layouts not
-- listed (a plugin's own) leave the journal as it is.
---------------------------------------------------------------------------
Options.LAYOUT_STYLES = {
	EldoCenter1000 = "EldoUI", EldoZen1000 = "EldoUI", EldoWide1000 = "EldoUI", EldoBlizz1000 = "Storybook",
	EldoHunter1000 = "EldoUI", EldoCozy1000 = "Storybook", EldoVanilla1000 = "Storybook", EldoSanctum1000 = "EldoUI",
	EldoModern2000 = "EldoUI", EldoHeritage2000 = "Storybook", EldoPlates2000 = "Compact", EldoSanctum2000 = "EldoUI",
	EldoCenter = "EldoUI", EldoModern = "EldoUI", EldoClassic = "Storybook", EldoClean = "EldoUI", EldoCookies = "Storybook", EldoZen = "EldoUI",
	EldoWide = "EldoUI", EldoBlizz = "Storybook", EldoSyntax = "Compact", EldoCompact = "Compact", EldoJoe = "EldoUI",
	EldoHeritage = "Storybook", EldoHunter = "EldoUI", EldoDark = "EldoUI", EldoCozy = "Storybook", EldoViolet = "Compact",
	EldoPlates = "Compact", EldoZerby = "Compact", EldoVanilla = "Storybook", EldoVanillaCompact = "Storybook",
	EldoVanillaFocus = "Storybook", EldoSanctum = "EldoUI",
}

-- The paired style's look (its `look` keys only) for a layout; true when
-- something was set.
function Options.FollowLayout(layoutKey)
	local db = A.db
	if type(db) ~= "table" or db.followLayout == false then return false end
	local style = Style(Options.LAYOUT_STYLES[layoutKey or ""])
	if not (style and style.look) then return false end
	for key, value in pairs(style.look) do db[key] = value end
	if A.active and A.OnProfileChanged then E:RunOutOfCombat(function() A:OnProfileChanged() end) end
	return true
end

if type(E.RegisterLayoutCallback) == "function" then
	-- Installer previews (silent) leave the journal alone.
	E:RegisterLayoutCallback(function(key, _, silent)
		if not silent then Options.FollowLayout(key) end
	end)
end
