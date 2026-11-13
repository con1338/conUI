-- UI amount: how much EldoUI shows on top of what you need to play
-- (Layout and style > UI amount, Core/UIAmount.lua).
--
--   Essential  your frames, bars, class tools, chat and minimap; the extra
--              helpers and tooltip lines are off
--   Moderate   Essential plus EldoUI's helpers, the same as a new profile
--   Full       Moderate plus tools you open when you want them; nothing
--              new fills the middle of the screen
--
-- A level only switches the modules in E.uiAmountModules on or off. It
-- never moves a frame, changes a skin, a key binding or a convenience
-- setting (repair, selling, loot), and never touches another addon.
-- Modules in E.uiAmountNever are part of playing your class or role, act
-- for you, or own a whole Blizzard window: no level lists them.
--
-- E.uiAmountRecommended: the level each layout was made for. A layout
-- not listed (a plugin's) gets Moderate.
-- Written from scratch for EldoUI.
local _, E = ...

E.uiAmountLevels = {
	order = { "essential", "moderate", "full" },
	essential = { title = "Essential",
		desc = "Only what you need to play: your frames, bars, class tools, chat and minimap. EldoUI's extra helpers and tooltip lines are off." },
	moderate = { title = "Moderate",
		desc = "Essential plus EldoUI's helpers: counters, rare alerts, extra tooltip lines and group panels. A new profile starts here." },
	full = { title = "Full",
		desc = "Moderate plus tools you open when you want them: the Alts window, the dungeon log and the Legacy planner. Nothing new fills the middle of the screen." },
}

-- Each row: the module and whether it is on at each level. Moderate is
-- what a new profile has, so picking it on a fresh profile changes nothing.
E.uiAmountModules = {
	{ module = "Counters", essential = false, moderate = true, full = true },
	{ module = "Farming", essential = false, moderate = true, full = true },
	{ module = "SplitTimer", essential = false, moderate = true, full = true },
	{ module = "FlightGames", essential = false, moderate = false, full = true },
	{ module = "RareScanner", essential = false, moderate = true, full = true },
	{ module = "ReadyReport", essential = false, moderate = true, full = true },
	{ module = "PartyQuests", essential = false, moderate = true, full = true },
	{ module = "PlayerNotes", essential = false, moderate = true, full = true },
	{ module = "MobInfo", essential = false, moderate = true, full = true },
	{ module = "QuestDrops", essential = false, moderate = true, full = true },
	{ module = "Appearances", essential = false, moderate = true, full = true },
	{ module = "SpellEfficiency", essential = false, moderate = true, full = true },
	{ module = "Characters", essential = false, moderate = false, full = true },
	{ module = "Instances", essential = false, moderate = false, full = true },
	{ module = "Legacy", essential = false, moderate = false, full = true },
}

-- Never part of a level: frames and bars you play with, class and role
-- tools, features that act for you, and modules that own a Blizzard window
-- (the Blizzard windows choice and the Modules page decide those).
E.uiAmountNever = {
	UnitFrames = true, ActionBars = true, ClassPower = true, GroupFrames = true, Nameplates = true,
	Auras = true, AuraGroups = true, PetCare = true, ShamanTotems = true, ClassBar = true, MageTravel = true,
	BlessingPlan = true, ClickCast = true, CastFX = true, CooldownManager = true, CombatHUD = true,
	CombatText = true, Battlegrounds = true, EncounterTimeline = true, DBM = true, RaidTools = true,
	Chat = true, Minimap = true, InfoBar = true, MicroMenu = true, StatusBars = true,
	ObjectiveTracker = true, Tooltip = true, Bags = true, Loot = true, Merchant = true,
	Mail = true, Trade = true, Auction = true, BagActions = true, Fishing = true,
	Camera = true, Talents = true, Quickdraw = true, Dialogue = true, QoL = true,
	Reminders = true, Hardcore = true, Streamer = true, Integrations = true, EditMode = true,
	Notifications = true, SystemUI = true, Skins = true, Character = true, Social = true,
	NPCWindows = true, Maps = true, Camp = true,
}

E.uiAmountRecommended = {
	-- The layout families.
	EldoVanilla = "essential", EldoCenter = "moderate", EldoModern = "moderate", EldoBlizz = "moderate", EldoHeritage = "essential",
	EldoZen = "essential", EldoWide = "moderate", EldoCozy = "essential", EldoHunter = "moderate",
	EldoPlates = "moderate", EldoSanctum = "moderate",
	-- Legacy layouts keep the level they were made for.
	EldoClassic = "moderate", EldoClean = "essential", EldoSyntax = "essential", EldoViolet = "essential",
	EldoJoe = "moderate", EldoCookies = "moderate", EldoCompact = "moderate", EldoZerby = "moderate",
	EldoDark = "moderate", EldoVanillaCompact = "essential", EldoVanillaFocus = "moderate",
}
