-- EldoUI layout presets: ready-made looks the player applies with one click
-- (options panel, installer, or /eui layout <name>). A preset holds:
--   points  = default position for every mover, { point, relativeTo, relativePoint, x, y }.
--             relativeTo is "UIParent", or another mover of the same module
--             ("EldoUI_PlayerMover"), so a stack follows when a frame changes size.
--   modules = module settings the preset sets (sizes, datatexts, bar shapes);
--             nested tables are merged into the module's settings
--   hidden  = optional list of movers the preset switches off (Core/Movers.lua
--             enabledPath); they come back on with the next preset. For an
--             action bar that switch is its Shown switch: the bar keeps its
--             actions and keys, and shows on mouse over out of combat in a
--             small box in the bottom-right corner. A layout may hide bar 3
--             and the bars after it, never bars 1 and 2.
--   widePoints = optional second points for frames that can outgrow their
--             spot (see "Wide points" below)
--   suggest = { UnitFrames = "<style key>", Nameplates = ..., ... }: the
--             style that fits the layout for each part of the UI (unit,
--             group and nameplate frames, action bars, auras, minimap, info
--             bar, class power, combat text). Every layout names one per
--             part; the setup preselects them. A layout that hides
--             EldoUI_Target also sets Nameplates.targetDetails, so your
--             target's plate carries the details.
--   incompatible = { GroupFrames = { Healer = "EldoUI_Party" } }: optional,
--             styles whose sizes don't fit the layout's spots, each naming
--             the frame it would cover; the setup grays them out.
--   skin    = the skin the layout was made for (a skin ID, Data/Skins.lua).
--             A profile that follows its layout's skin gets it with the
--             layout; a profile with a skin picked by hand is asked once
--             whether it wants the layout's look (E:ConfirmApplyLayout).
--   windows = optional, "original" or "match": how Blizzard's own windows
--             look with this layout when the player lets them follow it.
--   family  = the layout family it belongs to (its own key for one of the
--             eleven built-in families, E.layoutFamilies).
--   retiredIn = set on a legacy layout: one that left the layout list in
--             that version. It keeps every value it had, so a profile on it
--             places exactly as before until the player picks a layout.
--   artOptions = optional, the art a family offers: { skin, windows } each.
--
-- The presets are measured in UI units on a canvas 1440 units tall (2560x1440
-- at 16:9). The "auto" UI scale draws that canvas on every screen
-- (Core/Scale.lua), so a preset looks the same everywhere; only on a 1440p
-- screen is one unit also one screen pixel. A position the player drags in
-- move mode is saved in the profile and stays through a layout change,
-- until the player asks for the layout's spots back.
-- New presets are added to E.layouts and to E.layoutOrder; plugins can do the same.
-- The built-in list is the eleven families of E.layoutFamilies; the layouts
-- that left it are kept in E.legacyLayouts (see "The layout catalog" below).
-- Most presets are generated into Data/Layouts.lua by tools/gen_presets.py.
-- The placement rules (zones, gaps, chains) follow one matrix:
-- chains stay inside one module and never point both ways across presets.
-- The Encounter Timeline sits right of center at CENTER 752,-124
-- (Eldo-Classic 846,-50, 200 long) with its big icon at 776,-188. To keep
-- it clear: don't grow the loot feed downward, keep the target of target
-- 12 px clear of x 592..912 above y -160, and keep the top of Details!
-- window 2 below y -192 left of x 821.
--
-- For maintainers: the developer notes of the source repository hold the
-- placement rules (one owner per mover, chains, which point wins, a point
-- in every layout, the 1440 canvas) and how layouts, styles, art styles,
-- accents and roles stack.
local _, E = ...
local ReadAccountRoot = E.ReadAccountRoot
local L = E.L

E.defaults.general.layout = "EldoCenter1000"
E.defaults.general.layoutHidden = {} -- movers the current preset switched off (name = true)
E.defaults.general.layoutPending = {} -- movers the preset keeps off that didn't exist yet (name = layout key)

-- Before action bars had a Shown switch, a layout's hidden list turned the
-- whole bar off, keys and all. A bar an earlier layout switched off that
-- way comes back On and hidden, so its keys work again; a bar the player
-- turned off without the layout stays off.
E:RegisterProfileMigration(function(profile)
	local hidden = type(profile.general) == "table" and profile.general.layoutHidden
	local modules = profile.modules
	local bars = type(modules) == "table" and type(modules.ActionBars) == "table" and modules.ActionBars.bars
	if type(hidden) ~= "table" or type(bars) ~= "table" then return end
	for index = 1, 8 do
		local bar = bars[index]
		if hidden["EldoUI_ActionBar" .. index] == true and type(bar) == "table" and bar.enabled == false then
			bar.enabled = true
			bar.shown = false
		end
	end
end, "actionbars:shown", 1)

E.layouts = {
	-- Info bar on top, compact center (player frame, action bar and resource
	-- bar together under the character), party frames left of center, stacked
	-- meters bottom right, chat bottom left.
	EldoModern = {
		title = "Modern Center",
		family = "EldoModern",
		-- A legacy layout since 0.7.2000: EldoModern2000 (at the end of
		-- this table) is the family's current version.
		retiredIn = "0.7.2000",
		familyVersion = true,
		accent = "0CD29D",
		skin = "Forever",
		desc = "Info bar on top, compact center, meters bottom right.",
		suggest = { UnitFrames = "Clean", GroupFrames = "List", ActionBars = "Standard", Auras = "Standard", Minimap = "Square",
			InfoBar = "Full", ClassPower = "Standard", CombatText = "Clean", Nameplates = "EldoUI" },
		incompatible = { UnitFrames = { Orbs = "EldoUI_Focus" } },
		points = {
			EldoUI_ActionBar1 = { "CENTER", "UIParent", "CENTER", 0, -224 },
			EldoUI_ActionBar2 = { "BOTTOM", "UIParent", "BOTTOM", 0, 58 },
			EldoUI_ActionBar3 = { "BOTTOM", "EldoUI_ActionBar2Mover", "TOP", 0, 6 },
			EldoUI_ActionBar4 = { "RIGHT", "UIParent", "RIGHT", -19, 74 },
			EldoUI_ActionBar5 = { "BOTTOM", "EldoUI_ActionBar3Mover", "TOP", 0, 6 },
			EldoUI_ActionBar6 = { "CENTER", "UIParent", "CENTER", -572, -406 },
			EldoUI_ActionBar7 = { "CENTER", "UIParent", "CENTER", 488, -608 },
			EldoUI_ActionBar8 = { "LEFT", "UIParent", "LEFT", 432, -48 },
			EldoUI_AlertLane = { "TOP", "UIParent", "TOP", -485, -332 },
			EldoUI_Alts = { "TOPLEFT", "UIParent", "TOPLEFT", 20, -152 },
			EldoUI_AuctionWindow = { "TOPLEFT", "UIParent", "TOPLEFT", 20, -152 },
			EldoUI_AuraGroup1 = { "TOP", "UIParent", "CENTER", -756, -90 },
			EldoUI_AuraGroup2 = { "TOP", "EldoUI_AuraGroup1Mover", "BOTTOM", 0, -6 },
			EldoUI_AuraGroup3 = { "TOP", "EldoUI_AuraGroup2Mover", "BOTTOM", 0, -6 },
			EldoUI_AuraGroup4 = { "TOP", "UIParent", "CENTER", -656, -244 },
			EldoUI_AuraGroup5 = { "TOP", "EldoUI_AuraGroup4Mover", "BOTTOM", 0, -6 },
			EldoUI_AuraGroup6 = { "TOP", "EldoUI_AuraGroup5Mover", "BOTTOM", 0, -6 },
			EldoUI_BGTimers = { "CENTER", "UIParent", "CENTER", 520, 140 },
			EldoUI_BagBar = { "BOTTOMRIGHT", "UIParent", "BOTTOMRIGHT", -463, 37 },
			EldoUI_BagsAnchor = { "BOTTOMRIGHT", "UIParent", "BOTTOMRIGHT", -19, 8 },
			EldoUI_BankAnchor = { "TOPLEFT", "UIParent", "TOPLEFT", 20, -152 },
			EldoUI_Banners = { "TOP", "UIParent", "TOP", 0, -88 },
			EldoUI_BattlefieldMap = { "TOPLEFT", "UIParent", "TOPLEFT", 327, -76 },
			EldoUI_BigWigsBars = { "CENTER", "UIParent", "CENTER", 520, 140 },
			EldoUI_BigWigsCountdown = { "CENTER", "UIParent", "CENTER", 0, 215 },
			EldoUI_BigWigsEmphasize = { "CENTER", "UIParent", "CENTER", 540, 300 },
			EldoUI_BigWigsMessages = { "TOP", "UIParent", "TOP", 0, -224 },
			EldoUI_Boss = { "CENTER", "UIParent", "CENTER", 800, 140 },
			EldoUI_BossEmote = { "TOP", "UIParent", "TOP", 0, -176 },
			EldoUI_BossInfo = { "CENTER", "UIParent", "CENTER", 295, 268 },
			EldoUI_BossWarnings = { "CENTER", "UIParent", "CENTER", 0, 350 },
			EldoUI_Buffs = { "TOPRIGHT", "UIParent", "TOPRIGHT", -276, -51 },
			EldoUI_CampPanel = { "TOPRIGHT", "UIParent", "TOPRIGHT", -632, -264 },
			EldoUI_Chat = { "BOTTOMLEFT", "UIParent", "BOTTOMLEFT", 19, 8 },
			EldoUI_ChatRight = { "BOTTOMRIGHT", "UIParent", "BOTTOMRIGHT", -30, 304 },
			EldoUI_CombatTimer = { "BOTTOMRIGHT", "UIParent", "BOTTOMRIGHT", -463, 412 },
			EldoUI_ConsumableBar = { "BOTTOM", "UIParent", "BOTTOM", 330, 240 },
			EldoUI_CooldownPulse = { "CENTER", "UIParent", "CENTER", 96, 0 },
			EldoUI_Cooldowns = { "CENTER", "UIParent", "CENTER", 0, -276 },
			EldoUI_CooldownsBars = { "CENTER", "UIParent", "CENTER", -324, -348 },
			EldoUI_CooldownsBuffs = { "CENTER", "UIParent", "CENTER", 0, -118 },
			EldoUI_CooldownsItems = { "BOTTOM", "EldoUI_CooldownsBuffsMover", "TOP", 0, 6 },
			EldoUI_CooldownsMobility = { "RIGHT", "EldoUI_CooldownsBuffsMover", "LEFT", -12, 0 },
			EldoUI_CooldownsTrinkets = { "LEFT", "EldoUI_CooldownsBuffsMover", "RIGHT", 12, 0 },
			EldoUI_CooldownsUtility = { "TOP", "EldoUI_CooldownsMover", "BOTTOM", 0, -6 },
			EldoUI_Counters = { "TOPRIGHT", "UIParent", "TOPRIGHT", -388, -328 },
			EldoUI_DataPanel1 = { "TOPLEFT", "UIParent", "TOPLEFT", 327, -280 },
			EldoUI_DeathLog = { "TOP", "UIParent", "TOP", 0, -104 },
			EldoUI_DeathRecap = { "CENTER", "UIParent", "CENTER", -24, 108 },
			EldoUI_Debuffs = { "TOPRIGHT", "EldoUI_BuffsMover", "BOTTOMRIGHT", 0, -12 },
			EldoUI_Details = { "BOTTOMRIGHT", "UIParent", "BOTTOMRIGHT", -19, 8 },
			EldoUI_Details1 = { "BOTTOMRIGHT", "UIParent", "BOTTOMRIGHT", -19, 8 },
			EldoUI_Details2 = { "BOTTOMRIGHT", "EldoUI_Details1Mover", "TOPRIGHT", 0, 8 },
			EldoUI_Durability = { "CENTER", "UIParent", "RIGHT", -798, 558 },
			EldoUI_EIM = { "BOTTOMLEFT", "UIParent", "BOTTOMLEFT", 19, 298 },
			EldoUI_EncounterBar = { "CENTER", "UIParent", "CENTER", 800, -132 },
			EldoUI_EncounterTimeline = { "LEFT", "UIParent", "CENTER", 482, 16 },
			EldoUI_EncounterTimelineBig = { "RIGHT", "EldoUI_EncounterTimelineMover", "LEFT", -8, 0 },
			EldoUI_EnemySpotter = { "BOTTOMLEFT", "UIParent", "TOPLEFT", 325, -500 },
			EldoUI_Errors = { "TOP", "UIParent", "TOP", 0, -284 },
			EldoUI_ExtraAbility = { "BOTTOMRIGHT", "UIParent", "BOTTOMRIGHT", -463, 180 },
			EldoUI_Fanfare = { "CENTER", "UIParent", "CENTER", 0, 324 },
			EldoUI_FarmBar = { "TOP", "UIParent", "TOP", -440, -40 },
			EldoUI_Finder = { "TOP", "UIParent", "TOP", 0, -172 },
			EldoUI_GDKPLedger = { "TOPLEFT", "UIParent", "TOPLEFT", 552, -44 },
			EldoUI_FishingBar = { "BOTTOM", "UIParent", "BOTTOM", -450, 232 },
			EldoUI_ShoppingList = { "TOP", "UIParent", "TOP", 281, -476 },
			EldoUI_FlightBar = { "TOP", "UIParent", "TOP", -440, -40 },
			EldoUI_Focus = { "CENTER", "UIParent", "CENTER", -500, -150 },
			EldoUI_FocusTarget = { "CENTER", "UIParent", "CENTER", -600, -114 },
			EldoUI_GamepadBar = { "BOTTOM", "UIParent", "BOTTOM", 0, 58 },
			EldoUI_GhostButton = { "TOP", "UIParent", "TOP", 266, -40 },
			EldoUI_GroupPets = { "TOPLEFT", "EldoUI_RaidMover", "TOPRIGHT", 8, 0 },
			EldoUI_GuildBank = { "TOPLEFT", "UIParent", "TOPLEFT", 20, -152 },
			EldoUI_InfoBar = { "TOP", "UIParent", "TOP", 0, 0 },
			-- The second bar on its own mover sits under the first, clear of
			-- the experience bar at the bottom edge, between the farming bar
			-- and the mirror timers.
			EldoUI_InfoBar2 = { "TOP", "EldoUI_InfoBarMover", "BOTTOM", -55, 0 },
			EldoUI_InstanceLog = { "TOP", "UIParent", "TOP", 0, -152 },
			EldoUI_LootAnchor = { "LEFT", "UIParent", "LEFT", 280, 28 },
			EldoUI_LootCheck = { "CENTER", "UIParent", "CENTER", -570, 380 },
			EldoUI_LootFeed = { "RIGHT", "UIParent", "RIGHT", -420, -178 },
			EldoUI_LootRolls = { "TOP", "UIParent", "TOP", -485, -172 },
			EldoUI_LootToasts = { "BOTTOMRIGHT", "UIParent", "BOTTOMRIGHT", -470, 532 },
			EldoUI_LossOfControl = { "CENTER", "UIParent", "CENTER", 0, 120 },
			EldoUI_MailWindow = { "TOPLEFT", "UIParent", "TOPLEFT", 20, -152 },
			EldoUI_MerchantWindow = { "TOPLEFT", "UIParent", "TOPLEFT", 20, -152 },
			EldoUI_MicroMenu = { "BOTTOMRIGHT", "UIParent", "BOTTOMRIGHT", -463, 74 },
			EldoUI_Minimap = { "TOPRIGHT", "UIParent", "TOPRIGHT", -19, -51 },
			EldoUI_MirrorTimers = { "TOP", "UIParent", "TOP", 266, -40 },
			EldoUI_Party = { "CENTER", "UIParent", "CENTER", -660, 145 },
			EldoUI_PartyPets = { "CENTER", "UIParent", "CENTER", -922, 8 },
			EldoUI_PartyTargets = { "LEFT", "UIParent", "LEFT", 136, -24 },
			EldoUI_Pet = { "TOPLEFT", "EldoUI_PlayerMover", "BOTTOMLEFT", 0, -40 },
			EldoUI_PetBar = { "BOTTOMRIGHT", "EldoUI_ActionBar5Mover", "TOP", -6, 8 },
			EldoUI_PetFeed = { "CENTER", "UIParent", "CENTER", -600, -300 },
			EldoUI_PetTarget = { "TOPLEFT", "EldoUI_PetMover", "BOTTOMLEFT", 0, -6 },
			EldoUI_PingFeed = { "BOTTOM", "UIParent", "CENTER", -865, -390 },
			EldoUI_Player = { "CENTER", "UIParent", "CENTER", -444, -224 },
			EldoUI_PlayerCastbar = { "CENTER", "UIParent", "CENTER", 0, -361 },
			EldoUI_PlayerFramePower = { "TOP", "EldoUI_PlayerMover", "BOTTOM", 0, -4 },
			EldoUI_PlayerPower = { "CENTER", "UIParent", "CENTER", 0, -190 },
			EldoUI_PlayerPowerBar1 = { "TOP", "UIParent", "CENTER", -298, -368 },
			EldoUI_PlayerPowerBar2 = { "TOP", "EldoUI_PlayerPowerBar1Mover", "BOTTOM", 0, -6 },
			EldoUI_PlayerPowerBar3 = { "TOP", "EldoUI_PlayerPowerBar2Mover", "BOTTOM", 0, -6 },
			EldoUI_PlayerPowerBar4 = { "TOP", "EldoUI_PlayerPowerBar3Mover", "BOTTOM", 0, -6 },
			EldoUI_Popups = { "TOP", "UIParent", "TOP", -485, -88 },
			EldoUI_PossessBar = { "BOTTOMRIGHT", "EldoUI_ActionBar5Mover", "TOP", -6, 8 },
			EldoUI_ProcOverlay = { "CENTER", "UIParent", "CENTER", 0, 0 },
			EldoUI_Prompt = { "TOP", "UIParent", "TOP", 0, -236 },
			EldoUI_RareAlert = { "TOP", "UIParent", "TOP", -475, -228 },
			EldoUI_ReadyReport = { "TOP", "UIParent", "TOP", 0, -476 },
			EldoUI_SplitTimer = { "TOPRIGHT", "UIParent", "TOPRIGHT", -40, -290 },
			-- Dungeon Routes: the route card, right of center under the top notices.
			EldoUI_RouteCard = { "TOPLEFT", "UIParent", "TOP", 400, -320 },
			EldoUI_ZoneToast = { "TOP", "UIParent", "TOP", -268, -460 },
			EldoUI_QuestItem = { "TOPRIGHT", "UIParent", "TOPRIGHT", -347, -335 },
			EldoUI_QuestTimer = { "TOPRIGHT", "UIParent", "TOPRIGHT", -75, -828 },
			EldoUI_Questie = { "TOPRIGHT", "UIParent", "TOPRIGHT", -75, -335 },
			EldoUI_Quests = { "TOPRIGHT", "UIParent", "TOPRIGHT", -75, -335 },
			-- My Adventure: the bottom band of the quest column (its bottom edge is the column's).
			EldoUI_JournalTracker = { "TOPRIGHT", "UIParent", "TOPRIGHT", -75, -675 },
			EldoUI_QueueStatus = { "TOPRIGHT", "UIParent", "TOPRIGHT", -216, -248 },
			EldoUI_RXP = { "TOPLEFT", "UIParent", "TOPLEFT", 19, -60 },
			EldoUI_Raid = { "TOPLEFT", "UIParent", "TOPLEFT", 19, -504 },
			EldoUI_RaidTools = { "BOTTOMLEFT", "UIParent", "TOPLEFT", 19, -492 },
			EldoUI_RaidWarning = { "TOP", "UIParent", "TOP", 0, -88 },
			EldoUI_ReadyCheck = { "CENTER", "UIParent", "CENTER", -9, 114 },
			EldoUI_Reminders = { "CENTER", "UIParent", "CENTER", -128, 0 },
			EldoUI_SCTIncoming = { "CENTER", "UIParent", "CENTER", -300, 41 },
			EldoUI_SCTNotify = { "CENTER", "UIParent", "CENTER", 0, 314 },
			EldoUI_SCTStatic = { "CENTER", "UIParent", "CENTER", -544, -592 },
			EldoUI_SCTTarget = { "CENTER", "UIParent", "CENTER", 300, 60 },
			EldoUI_StanceBar = { "BOTTOMLEFT", "EldoUI_ActionBar5Mover", "TOP", 6, 8 },
			EldoUI_StartCountdown = { "CENTER", "UIParent", "CENTER", 0, 203 },
			EldoUI_SwingMainHand = { "CENTER", "UIParent", "CENTER", 0, -384 },
			EldoUI_SwingOffHand = { "TOP", "EldoUI_SwingMainHandMover", "BOTTOM", 0, -6 },
			EldoUI_SwingRanged = { "TOP", "EldoUI_SwingOffHandMover", "BOTTOM", 0, -6 },
			EldoUI_TalentPlanner = { "TOP", "UIParent", "TOP", 0, -80 },
			EldoUI_TalkingHead = { "TOP", "UIParent", "TOP", 0, -88 },
			EldoUI_Tanks = { "TOPLEFT", "EldoUI_RaidMover", "BOTTOMLEFT", 0, -12 },
			EldoUI_Target = { "CENTER", "UIParent", "CENTER", 445, -224 },
			EldoUI_TempEnchants = { "TOPRIGHT", "EldoUI_DebuffsMover", "TOPLEFT", -12, 0 },
			EldoUI_ThreatMeter = { "BOTTOMRIGHT", "UIParent", "BOTTOMRIGHT", -463, 312 },
			EldoUI_ToT = { "LEFT", "EldoUI_TargetMover", "RIGHT", 8, 0 },
			EldoUI_Tooltip = { "BOTTOMRIGHT", "UIParent", "BOTTOMRIGHT", -67, 506 },
			EldoUI_TopWidgets = { "TOP", "UIParent", "TOP", 0, -40 },
			EldoUI_TotemBar = { "BOTTOMLEFT", "EldoUI_ActionBar5Mover", "TOP", 6, 8 },
			EldoUI_ShamanTotems = { "CENTER", "UIParent", "CENTER", 0, -160 },
			EldoUI_Totems = { "CENTER", "UIParent", "CENTER", 0, -160 },
			EldoUI_TrackingBars = { "CENTER", "UIParent", "CENTER", 0, -317 },
			EldoUI_TradeWindow = { "TOPLEFT", "UIParent", "TOPLEFT", 20, -152 },
			EldoUI_TrainingWindow = { "TOPLEFT", "UIParent", "TOPLEFT", 20, -152 },
			EldoUI_VehicleExit = { "CENTER", "UIParent", "CENTER", -388, -512 },
			EldoUI_VehicleSeat = { "CENTER", "UIParent", "CENTER", -620, -468 },
			EldoUI_Volume = { "TOPRIGHT", "UIParent", "TOPRIGHT", -402, -782 },
			EldoUI_WaypointArrow = { "TOP", "UIParent", "TOP", 344, -198 },
			EldoUI_WaypointCoords = { "TOP", "UIParent", "TOP", 344, -172 },
			EldoUI_XPBar = { "BOTTOM", "UIParent", "BOTTOM", 0, 8 },
			EldoUI_ZoneText = { "TOP", "UIParent", "TOP", 0, -88 },
		},
		-- A pets grid wider than the band beside the raid hangs under the raid;
		-- the main tanks then take the spot beside the raid.
		-- Player and target sit on either side of bar 1: a wider frame style
		-- or bigger bar buttons move them outward, their inner edges kept
		-- 12 units from the bar.
		-- A wider raid (List, Wide and Healer styles) takes that band too:
		-- the pets go under it the same way. A bigger minimap moves the buff
		-- and debuff rows and the durability figure left with it, and the
		-- split timer, the quest list and the quest timer under it down.
		widePoints = {
			EldoUI_Buffs = { width = 237, of = "EldoUI_Minimap", point = { "TOPRIGHT", "UIParent", "TOPRIGHT", -319, -51 } },
			EldoUI_Durability = { width = 237, of = "EldoUI_Minimap", point = { "CENTER", "UIParent", "RIGHT", -841, 558 } },
			EldoUI_SplitTimer = { height = 237, of = "EldoUI_Minimap", point = { "TOPRIGHT", "UIParent", "TOPRIGHT", -40, -337 } },
			EldoUI_Quests = { height = 237, of = "EldoUI_Minimap", point = { "TOPRIGHT", "UIParent", "TOPRIGHT", -75, -382 } },
			EldoUI_Questie = { height = 237, of = "EldoUI_Minimap", point = { "TOPRIGHT", "UIParent", "TOPRIGHT", -75, -382 } },
			EldoUI_QuestTimer = { height = 237, of = "EldoUI_Minimap", point = { "TOPRIGHT", "UIParent", "TOPRIGHT", -75, -875 } },
			-- The durability figure moves out with a larger map, toward the
			-- raid warnings and the waypoint pair: the raid warnings and the
			-- coordinates give way to the left, the arrow moves down.
			EldoUI_RaidWarning = { width = 237, of = "EldoUI_Minimap", point = { "TOP", "UIParent", "TOP", -16, -88 } },
			EldoUI_WaypointArrow = { width = 237, of = "EldoUI_Minimap", point = { "TOP", "UIParent", "TOP", 344, -216 } },
			EldoUI_WaypointCoords = { width = 237, of = "EldoUI_Minimap", point = { "TOP", "UIParent", "TOP", 324, -172 } },
			EldoUI_GroupPets = { width = 83, point = { "TOPLEFT", "EldoUI_RaidMover", "BOTTOMLEFT", 0, -12 },
				also = { { width = 412, of = "EldoUI_Raid" } } },
			EldoUI_Tanks = { width = 83, of = "EldoUI_GroupPets", point = { "TOPLEFT", "EldoUI_RaidMover", "TOPRIGHT", 8, 0 },
				also = { { height = 350, of = "EldoUI_Raid" }, { width = 412, of = "EldoUI_Raid" } } },
			EldoUI_Player = { width = 278, point = { "RIGHT", "UIParent", "CENTER", -346, -224 },
				also = { { width = 597, of = "EldoUI_ActionBar1" } } },
			EldoUI_Target = { width = 278, point = { "LEFT", "UIParent", "CENTER", 347, -224 },
				also = { { width = 597, of = "EldoUI_ActionBar1" } } },
		},
		-- On a 16:10 screen the boss frames move in beside the middle and the
		-- boss mod's info frame takes the matching spot left of it, the party
		-- frames keep their row clear of each other and of the raid pets, the
		-- combat text and the vehicle seats clear the chat, the waypoint
		-- arrow the enchants, the durability figure and the camp panel the
		-- arrow, and the banners and raid warnings the arrow and the
		-- durability figure. Under a larger minimap the encounter bar keeps
		-- clear of the quest list, the waypoint arrow and its coordinates
		-- of the enchants and the buffs, and the banners of the arrow; the
		-- loot toasts keep clear of the target of target in the Classic unit
		-- frame style, and the large micro menu goes above the extra ability
		-- button, clear of bar 2.
		narrowPoints = {
			EldoUI_PingFeed = { below = 2400, point = { "BOTTOM", "UIParent", "CENTER", -572, -194 } },
			EldoUI_ToT = { below = 2400, point = { "LEFT", "EldoUI_TargetMover", "RIGHT", 12, 24 } },
			EldoUI_EncounterBar = { below = 2400, point = { "CENTER", "UIParent", "CENTER", 688, -132 } },
			EldoUI_LootToasts = { below = 2400, point = { "BOTTOMRIGHT", "UIParent", "BOTTOMRIGHT", -470, 541 } },
			EldoUI_MicroMenu = { below = 2400, point = { "BOTTOMRIGHT", "UIParent", "BOTTOMRIGHT", -463, 74 },
				adaptive = { width = 400, point = { "BOTTOMRIGHT", "UIParent", "BOTTOMRIGHT", -463, 304 } } },
			EldoUI_Banners = { below = 2400, point = { "TOP", "UIParent", "TOP", -16, -88 },
				adaptive = { width = 237, of = "EldoUI_Minimap", point = { "TOP", "UIParent", "TOP", -56, -88 } } },
			EldoUI_Boss = { below = 2400, point = { "CENTER", "UIParent", "CENTER", 296, 128 } },
			EldoUI_BossInfo = { below = 2400, point = { "CENTER", "UIParent", "CENTER", -294, 240 } },
			EldoUI_CampPanel = { below = 2400, point = { "TOPRIGHT", "UIParent", "TOPRIGHT", -688, -290 } },
			EldoUI_Durability = { below = 2400, point = { "CENTER", "UIParent", "RIGHT", -798, 603 } },
			EldoUI_Party = { below = 2400, point = { "RIGHT", "UIParent", "CENTER", -446, 145 } },
			EldoUI_PartyPets = { below = 2400, point = { "CENTER", "UIParent", "CENTER", -794, 8 } },
			EldoUI_RaidWarning = { below = 2400, point = { "TOP", "UIParent", "TOP", -100, -88 } },
			EldoUI_SCTStatic = { below = 2400, point = { "CENTER", "UIParent", "CENTER", -736, -371 } },
			EldoUI_SocialToasts = { below = 2400, point = { "BOTTOMLEFT", "UIParent", "BOTTOMLEFT", 584, 8 },
				adaptive = { width = 597, of = "EldoUI_ActionBar2", point = { "BOTTOMLEFT", "UIParent", "BOTTOMLEFT", 584, 118 } } },
			EldoUI_VehicleSeat = { below = 2400, point = { "CENTER", "UIParent", "CENTER", -508, -544 } },
			EldoUI_WaypointArrow = { below = 2400, point = { "TOP", "UIParent", "TOP", 324, -202 },
				adaptive = { width = 237, of = "EldoUI_Minimap", point = { "TOP", "UIParent", "TOP", 284, -202 } } },
			EldoUI_WaypointCoords = { below = 2400, point = { "TOP", "UIParent", "TOP", 352, -172 },
				adaptive = { width = 237, of = "EldoUI_Minimap", point = { "TOP", "UIParent", "TOP", 312, -172 } } },
		},
		modules = {
			Minimap = { size = 237 },
			Chat = { width = 557, height = 282 },
			-- The timeline sits under the boss mod bars, its "now" end at the big icon.
			EncounterTimeline = { length = 200 },
			InfoBar = {
				height = 32,
				left = { "Friends", "Guild", "Class" },
				center = { "Time" },
				right = { "Profession", "Bags", "Durability", "Gold", "FPS", "Latency", "Memory" },
			},
		},
	},

	-- Info bar along the bottom, four action bar rows above it, player
	-- health and power either side of the character, guide and quests right.
	EldoClassic = {
		title = "Eldo-Classic (1440p)",
		-- A legacy layout since 0.7.0000: it stays exactly as it was, and
		-- profiles on it keep it until the player picks a layout.
		family = "EldoBlizz",
		retiredIn = "0.7.0000",
		accent = "33AAFF",
		skin = "Classic",
		desc = "Info bar at the bottom, stacked bar rows, guide and quests on the right.",
		suggest = { UnitFrames = "Blizzard", GroupFrames = "Blizzard", ActionBars = "Macros", Auras = "Standard", Minimap = "Large",
			InfoBar = "Full", ClassPower = "Chunky", CombatText = "Blizzlike", Nameplates = "EldoUI" },
		incompatible = { UnitFrames = { Orbs = "EldoUI_PlayerCastbar" } },
		points = {
			EldoUI_ActionBar1 = { "BOTTOM", "UIParent", "BOTTOM", 0, 92 },
			EldoUI_ActionBar2 = { "BOTTOM", "EldoUI_ActionBar1Mover", "TOP", 0, 6 },
			EldoUI_ActionBar3 = { "BOTTOM", "EldoUI_ActionBar2Mover", "TOP", 0, 6 },
			EldoUI_ActionBar4 = { "LEFT", "UIParent", "LEFT", 19, 100 },
			EldoUI_ActionBar5 = { "BOTTOM", "EldoUI_ActionBar3Mover", "TOP", 0, 6 },
			EldoUI_ActionBar6 = { "CENTER", "UIParent", "CENTER", -668, -204 },
			EldoUI_ActionBar7 = { "CENTER", "UIParent", "CENTER", 380, -184 },
			EldoUI_ActionBar8 = { "LEFT", "UIParent", "LEFT", 24, 404 },
			EldoUI_AlertLane = { "TOP", "UIParent", "TOP", -560, -300 },
			EldoUI_Alts = { "TOPLEFT", "UIParent", "TOPLEFT", 71, -120 },
			EldoUI_AuctionWindow = { "TOPLEFT", "UIParent", "TOPLEFT", 71, -120 },
			EldoUI_AuraGroup1 = { "TOP", "UIParent", "CENTER", -468, 74 },
			EldoUI_AuraGroup2 = { "TOP", "EldoUI_AuraGroup1Mover", "BOTTOM", 0, -6 },
			EldoUI_AuraGroup3 = { "TOP", "EldoUI_AuraGroup2Mover", "BOTTOM", 0, -6 },
			EldoUI_AuraGroup4 = { "TOP", "UIParent", "CENTER", -572, 36 },
			EldoUI_AuraGroup5 = { "TOP", "EldoUI_AuraGroup4Mover", "BOTTOM", 0, -6 },
			EldoUI_AuraGroup6 = { "TOP", "EldoUI_AuraGroup5Mover", "BOTTOM", 0, -6 },
			EldoUI_BGTimers = { "CENTER", "UIParent", "CENTER", 520, 126 },
			EldoUI_BagBar = { "BOTTOMRIGHT", "UIParent", "BOTTOMRIGHT", -471, 32 },
			EldoUI_BagsAnchor = { "BOTTOMRIGHT", "UIParent", "BOTTOMRIGHT", -19, 40 },
			EldoUI_BankAnchor = { "TOPLEFT", "UIParent", "TOPLEFT", 71, -120 },
			EldoUI_Banners = { "TOP", "UIParent", "TOP", 0, -56 },
			EldoUI_BattlefieldMap = { "TOPLEFT", "UIParent", "TOPLEFT", 255, -44 },
			EldoUI_BigWigsBars = { "CENTER", "UIParent", "CENTER", 520, 120 },
			EldoUI_BigWigsCountdown = { "CENTER", "UIParent", "CENTER", 0, 235 },
			EldoUI_BigWigsEmphasize = { "CENTER", "UIParent", "CENTER", 540, 280 },
			EldoUI_BigWigsMessages = { "TOP", "UIParent", "TOP", 0, -192 },
			EldoUI_Boss = { "CENTER", "UIParent", "CENTER", 620, -232 },
			EldoUI_BossEmote = { "TOP", "UIParent", "TOP", 0, -144 },
			EldoUI_BossInfo = { "CENTER", "UIParent", "CENTER", 296, 280 },
			EldoUI_BossWarnings = { "CENTER", "UIParent", "CENTER", 0, 370 },
			EldoUI_Buffs = { "TOPRIGHT", "UIParent", "TOPRIGHT", -339, -19 },
			EldoUI_CampPanel = { "TOPRIGHT", "UIParent", "TOPRIGHT", -816, -253 },
			EldoUI_Chat = { "BOTTOMLEFT", "UIParent", "BOTTOMLEFT", 19, 40 },
			EldoUI_ChatRight = { "BOTTOMRIGHT", "UIParent", "BOTTOMRIGHT", -30, 304 },
			EldoUI_CombatTimer = { "CENTER", "UIParent", "CENTER", 470, -311 },
			EldoUI_ConsumableBar = { "BOTTOM", "UIParent", "BOTTOM", 330, 208 },
			EldoUI_CooldownPulse = { "CENTER", "UIParent", "CENTER", 96, 0 },
			EldoUI_Cooldowns = { "CENTER", "UIParent", "CENTER", 0, -156 },
			EldoUI_CooldownsBars = { "CENTER", "UIParent", "CENTER", -436, -216 },
			EldoUI_CooldownsBuffs = { "CENTER", "UIParent", "CENTER", 0, -108 },
			EldoUI_CooldownsItems = { "BOTTOM", "EldoUI_CooldownsBuffsMover", "TOP", 0, 6 },
			EldoUI_CooldownsMobility = { "RIGHT", "EldoUI_CooldownsBuffsMover", "LEFT", -12, 0 },
			EldoUI_CooldownsTrinkets = { "LEFT", "EldoUI_CooldownsBuffsMover", "RIGHT", 12, 0 },
			EldoUI_CooldownsUtility = { "TOP", "EldoUI_CooldownsMover", "BOTTOM", 0, -6 },
			EldoUI_Counters = { "TOPLEFT", "UIParent", "TOPLEFT", 19, -8 },
			EldoUI_DataPanel1 = { "TOPLEFT", "UIParent", "TOPLEFT", 600, -356 },
			EldoUI_DeathLog = { "TOP", "UIParent", "TOP", 0, -94 },
			EldoUI_DeathRecap = { "CENTER", "UIParent", "CENTER", 0, 118 },
			EldoUI_Debuffs = { "TOPRIGHT", "EldoUI_BuffsMover", "BOTTOMRIGHT", 0, -12 },
			EldoUI_Details = { "BOTTOMRIGHT", "UIParent", "BOTTOMRIGHT", -19, 40 },
			EldoUI_Details1 = { "BOTTOMRIGHT", "UIParent", "BOTTOMRIGHT", -19, 40 },
			EldoUI_Details2 = { "BOTTOMRIGHT", "EldoUI_Details1Mover", "TOPRIGHT", 0, 8 },
			EldoUI_Durability = { "CENTER", "UIParent", "CENTER", 522, 438 },
			EldoUI_EIM = { "BOTTOMLEFT", "UIParent", "BOTTOMLEFT", 19, 348 },
			EldoUI_EncounterBar = { "CENTER", "UIParent", "CENTER", 535, 2 },
			EldoUI_EncounterTimeline = { "CENTER", "UIParent", "CENTER", 846, -50 },
			EldoUI_EncounterTimelineBig = { "TOPLEFT", "EldoUI_EncounterTimelineMover", "BOTTOMLEFT", 0, -20 },
			EldoUI_EnemySpotter = { "TOPLEFT", "UIParent", "TOPLEFT", 329, -344 },
			EldoUI_Errors = { "TOP", "UIParent", "TOP", 0, -260 },
			EldoUI_ExtraAbility = { "CENTER", "UIParent", "CENTER", 450, -580 },
			EldoUI_Fanfare = { "CENTER", "UIParent", "CENTER", 0, 324 },
			EldoUI_FarmBar = { "TOP", "UIParent", "TOP", -440, -8 },
			EldoUI_Finder = { "TOP", "UIParent", "TOP", 0, -140 },
			EldoUI_GDKPLedger = { "BOTTOMLEFT", "UIParent", "BOTTOMLEFT", 120, 328 },
			EldoUI_FishingBar = { "BOTTOM", "UIParent", "BOTTOM", -546, 292 },
			EldoUI_ShoppingList = { "TOP", "UIParent", "TOP", 281, -476 },
			EldoUI_FlightBar = { "TOP", "UIParent", "TOP", -440, -8 },
			EldoUI_Focus = { "CENTER", "UIParent", "CENTER", -444, -164 },
			EldoUI_FocusTarget = { "CENTER", "UIParent", "CENTER", -568, -108 },
			EldoUI_GamepadBar = { "BOTTOM", "UIParent", "BOTTOM", 0, 92 },
			EldoUI_GhostButton = { "TOP", "UIParent", "TOP", 266, -8 },
			EldoUI_GroupPets = { "TOPLEFT", "EldoUI_RaidMover", "TOPRIGHT", 8, 0 },
			EldoUI_GuildBank = { "TOPLEFT", "UIParent", "TOPLEFT", 71, -120 },
			EldoUI_InfoBar = { "BOTTOM", "UIParent", "BOTTOM", 0, 0 },
			EldoUI_InfoBar2 = { "TOP", "UIParent", "TOP", 0, 0 },
			EldoUI_InstanceLog = { "TOP", "UIParent", "TOP", 0, -120 },
			EldoUI_LootAnchor = { "LEFT", "UIParent", "LEFT", 280, 60 },
			EldoUI_LootCheck = { "CENTER", "UIParent", "CENTER", -570, 380 },
			EldoUI_LootFeed = { "RIGHT", "UIParent", "RIGHT", -420, 416 },
			EldoUI_LootRolls = { "TOP", "UIParent", "TOP", -560, -140 },
			EldoUI_LootToasts = { "BOTTOMRIGHT", "UIParent", "BOTTOMRIGHT", -470, 200 },
			EldoUI_LossOfControl = { "CENTER", "UIParent", "CENTER", 0, 120 },
			EldoUI_MailWindow = { "TOPLEFT", "UIParent", "TOPLEFT", 71, -120 },
			EldoUI_MerchantWindow = { "TOPLEFT", "UIParent", "TOPLEFT", 71, -120 },
			EldoUI_MicroMenu = { "BOTTOMRIGHT", "UIParent", "BOTTOMRIGHT", -471, 83 },
			EldoUI_Minimap = { "TOPRIGHT", "UIParent", "TOPRIGHT", -19, -19 },
			EldoUI_MirrorTimers = { "TOP", "UIParent", "TOP", 266, -8 },
			EldoUI_Party = { "TOPLEFT", "UIParent", "TOPLEFT", 71, -400 },
			EldoUI_PartyPets = { "CENTER", "UIParent", "CENTER", -826, 104 },
			EldoUI_PartyTargets = { "CENTER", "UIParent", "CENTER", -956, 120 },
			EldoUI_Pet = { "RIGHT", "EldoUI_PlayerMover", "LEFT", -8, 0 },
			EldoUI_PetBar = { "RIGHT", "EldoUI_ActionBar5Mover", "LEFT", -12, 0 },
			EldoUI_PetFeed = { "CENTER", "UIParent", "CENTER", -484, -250 },
			EldoUI_PetTarget = { "TOP", "EldoUI_PetMover", "BOTTOM", 0, -6 },
			EldoUI_PingFeed = { "BOTTOM", "UIParent", "CENTER", -821, -374 },
			EldoUI_Player = { "CENTER", "UIParent", "CENTER", -177, -250 },
			EldoUI_PlayerCastbar = { "CENTER", "UIParent", "CENTER", 0, -341 },
			EldoUI_PlayerFramePower = { "TOP", "EldoUI_PlayerMover", "BOTTOM", 0, -4 },
			EldoUI_PlayerPower = { "CENTER", "UIParent", "CENTER", 0, -320 },
			EldoUI_PlayerPowerBar1 = { "TOP", "UIParent", "CENTER", -298, -368 },
			EldoUI_PlayerPowerBar2 = { "TOP", "EldoUI_PlayerPowerBar1Mover", "BOTTOM", 0, -6 },
			EldoUI_PlayerPowerBar3 = { "TOP", "EldoUI_PlayerPowerBar2Mover", "BOTTOM", 0, -6 },
			EldoUI_PlayerPowerBar4 = { "TOP", "EldoUI_PlayerPowerBar3Mover", "BOTTOM", 0, -6 },
			EldoUI_Popups = { "TOP", "UIParent", "TOP", -560, -56 },
			EldoUI_PossessBar = { "RIGHT", "EldoUI_ActionBar5Mover", "LEFT", -12, 0 },
			EldoUI_ProcOverlay = { "CENTER", "UIParent", "CENTER", 0, 0 },
			EldoUI_Prompt = { "TOP", "UIParent", "TOP", 0, -236 },
			EldoUI_RareAlert = { "TOP", "UIParent", "TOP", -550, -196 },
			EldoUI_ReadyReport = { "TOP", "UIParent", "TOP", 0, -444 },
			EldoUI_SplitTimer = { "TOPLEFT", "UIParent", "TOPLEFT", 19, -44 },
			-- Dungeon Routes: the route card, right of center under the top notices.
			EldoUI_RouteCard = { "TOPLEFT", "UIParent", "TOP", 690, -300 },
			EldoUI_ZoneToast = { "TOP", "UIParent", "TOP", 0, -180 },
			EldoUI_QuestItem = { "TOPRIGHT", "UIParent", "TOPRIGHT", -603, -331 },
			EldoUI_QuestTimer = { "TOPRIGHT", "UIParent", "TOPRIGHT", -19, -819 },
			EldoUI_Questie = { "TOPRIGHT", "UIParent", "TOPRIGHT", -19, -331 },
			EldoUI_Quests = { "TOPRIGHT", "UIParent", "TOPRIGHT", -19, -331 },
			-- My Adventure: the bottom band of the quest column, 8 px over the quest timer.
			EldoUI_JournalTracker = { "TOPRIGHT", "UIParent", "TOPRIGHT", -19, -671 },
			EldoUI_QueueStatus = { "TOPRIGHT", "UIParent", "TOPRIGHT", -279, -279 },
			EldoUI_RXP = { "TOPRIGHT", "UIParent", "TOPRIGHT", -291, -331 },
			-- Eldostar: the guide column, under the route card.
			EldoUI_Eldostar = { "TOPRIGHT", "UIParent", "TOPRIGHT", -291, -450 },
			EldoUI_Raid = { "TOPLEFT", "UIParent", "TOPLEFT", 71, -400 },
			EldoUI_RaidTools = { "BOTTOMLEFT", "UIParent", "TOPLEFT", 75, -388 },
			EldoUI_RaidWarning = { "TOP", "UIParent", "TOP", 0, -56 },
			EldoUI_ReadyCheck = { "CENTER", "UIParent", "CENTER", -9, 114 },
			EldoUI_Reminders = { "CENTER", "UIParent", "CENTER", -128, 4 },
			EldoUI_SCTIncoming = { "CENTER", "UIParent", "CENTER", -300, 45 },
			EldoUI_SCTNotify = { "CENTER", "UIParent", "CENTER", 0, 330 },
			EldoUI_SCTStatic = { "CENTER", "UIParent", "CENTER", -560, -560 },
			EldoUI_SCTTarget = { "CENTER", "UIParent", "CENTER", 300, 60 },
			EldoUI_StanceBar = { "LEFT", "EldoUI_ActionBar5Mover", "RIGHT", 12, 0 },
			EldoUI_StartCountdown = { "CENTER", "UIParent", "CENTER", 0, 235 },
			EldoUI_SwingMainHand = { "CENTER", "UIParent", "CENTER", 0, -364 },
			EldoUI_SwingOffHand = { "TOP", "EldoUI_SwingMainHandMover", "BOTTOM", 0, -6 },
			EldoUI_SwingRanged = { "TOP", "EldoUI_SwingOffHandMover", "BOTTOM", 0, -6 },
			EldoUI_TalentPlanner = { "TOP", "UIParent", "TOP", 0, -80 },
			EldoUI_TalkingHead = { "TOP", "UIParent", "TOP", 0, -56 },
			EldoUI_Tanks = { "TOPLEFT", "EldoUI_RaidMover", "BOTTOMLEFT", 0, -12 },
			EldoUI_Target = { "CENTER", "UIParent", "CENTER", 178, -250 },
			EldoUI_TempEnchants = { "TOPRIGHT", "EldoUI_DebuffsMover", "TOPLEFT", -12, 0 },
			EldoUI_ThreatMeter = { "CENTER", "UIParent", "CENTER", 392, -376 },
			EldoUI_ToT = { "LEFT", "EldoUI_TargetMover", "RIGHT", 8, 0 },
			EldoUI_Tooltip = { "BOTTOMRIGHT", "UIParent", "BOTTOMRIGHT", -67, 538 },
			EldoUI_TopWidgets = { "TOP", "UIParent", "TOP", 0, -8 },
			EldoUI_TotemBar = { "LEFT", "EldoUI_ActionBar5Mover", "RIGHT", 12, 0 },
			EldoUI_ShamanTotems = { "TOPRIGHT", "UIParent", "CENTER", -150, -322 },
			EldoUI_Totems = { "TOPRIGHT", "UIParent", "CENTER", -150, -322 },
			EldoUI_TrackingBars = { "CENTER", "UIParent", "CENTER", 0, -257 },
			EldoUI_TradeWindow = { "TOPLEFT", "UIParent", "TOPLEFT", 71, -120 },
			EldoUI_TrainingWindow = { "TOPLEFT", "UIParent", "TOPLEFT", 71, -120 },
			EldoUI_VehicleExit = { "CENTER", "UIParent", "CENTER", -420, -480 },
			EldoUI_VehicleSeat = { "CENTER", "UIParent", "CENTER", -566, -320 },
			EldoUI_Volume = { "TOPRIGHT", "UIParent", "TOPRIGHT", -194, -542 },
			EldoUI_WaypointArrow = { "TOP", "UIParent", "TOP", 344, -167 },
			EldoUI_WaypointCoords = { "TOP", "UIParent", "TOP", 344, -141 },
			EldoUI_XPBar = { "BOTTOM", "UIParent", "BOTTOM", 0, 37 },
			EldoUI_ZoneText = { "TOP", "UIParent", "TOP", 0, -56 },
		},
		-- A pets grid wider than the band beside the raid hangs under the raid;
		-- the main tanks then take the spot beside the raid.
		-- A micro menu wider than two rows of seven sits above the loot
		-- notices, to the left of the damage meter. Bigger bar
		-- buttons move the extra ability button a little to the right.
		widePoints = {
			EldoUI_ExtraAbility = { width = 597, of = "EldoUI_ActionBar1", point = { "CENTER", "UIParent", "CENTER", 466, -580 } },
			EldoUI_GroupPets = { width = 400, point = { "TOPLEFT", "EldoUI_RaidMover", "BOTTOMLEFT", 0, -12 } },
			EldoUI_Tanks = { width = 400, of = "EldoUI_GroupPets", point = { "TOPLEFT", "EldoUI_RaidMover", "TOPRIGHT", 8, 0 },
				also = { { height = 350, of = "EldoUI_Raid" } } },
			EldoUI_MicroMenu = { width = 190, point = { "BOTTOMRIGHT", "UIParent", "BOTTOMRIGHT", -471, 396 } },
		},
		modules = {
			Minimap = { size = 300 },
			Chat = { width = 540, height = 300 },
			-- RestedXP and the boss frames own the right side: a shorter timeline.
			EncounterTimeline = { length = 200 },
			InfoBar = {
				height = 28,
				left = { "Friends", "Guild", "Profession" },
				center = { "Time" },
				right = { "Class", "Bags", "Durability", "Gold", "FPS", "Latency", "Memory" },
			},
		},
	},
	-- Modern Center, version 0.7.2000: the same layout with the notice lane of
	-- the other current layouts, so the zone toast has a clear spot under the
	-- ready check: the ready check and loss of control higher, both countdowns
	-- right above the proc overlay row, the toast at the screen's center line
	-- and the Shopping List where the toast ends. The record lists only what
	-- changes; the rest is a copy of EldoModern, and the sections further down
	-- that add Modern Center points or bar shapes add them to both. Profiles on
	-- EldoModern keep its points.
	EldoModern2000 = {
		family = "EldoModern",
		familyVersion = true,
		points = {
			EldoUI_BigWigsCountdown = { "CENTER", "UIParent", "CENTER", 0, 94 },
			EldoUI_StartCountdown = { "CENTER", "UIParent", "CENTER", 0, 67 },
			EldoUI_ReadyCheck = { "CENTER", "UIParent", "CENTER", -9, 200 },
			EldoUI_LossOfControl = { "CENTER", "UIParent", "CENTER", 0, 206 },
			EldoUI_ZoneToast = { "TOP", "UIParent", "CENTER", 0, 138 },
			EldoUI_ShoppingList = { "TOP", "UIParent", "TOP", 285, -476 },
			-- The talking head sits between the loot rolls and the waypoint
			-- arrow and coordinates, also when a larger minimap moves those in.
			-- On 16:10 the head, the loot rolls and the rare card move
			-- further left.
			EldoUI_TalkingHead = { "TOP", "UIParent", "TOP", -34, -88 },
			-- Party Quests opens left of the top center, clear of the quest
			-- tracker, as in the other current layouts.
			EldoUI_PartyQuests = { "TOP", "UIParent", "TOP", -502, -150 },
			-- The Feed Pet button sits left of the pet's target, above action
			-- bar 6, clear of the pet frame in every unit frame style and with
			-- larger bar buttons.
			EldoUI_PetFeed = { "CENTER", "UIParent", "CENTER", -600, -350 },
			-- The right chat panel sits a little lower, clear of the target of
			-- target beside a wide target frame and of the quest timer under a
			-- large minimap.
			EldoUI_ChatRight = { "BOTTOMRIGHT", "UIParent", "BOTTOMRIGHT", -30, 279 },
		},
		narrowPoints = {
			EldoUI_TalkingHead = { below = 2400, point = { "TOP", "UIParent", "TOP", -88, -88 } },
			EldoUI_RareAlert = { below = 2400, point = { "TOP", "UIParent", "TOP", -515, -228 } },
			EldoUI_LootRolls = { below = 2400, point = { "TOP", "UIParent", "TOP", -537, -172 } },
			EldoUI_PartyQuests = { below = 2400, point = { "TOP", "UIParent", "TOP", -478, -150 } },
			-- Popup dialogs move left with the talking head, clear of it.
			EldoUI_Popups = { below = 2400, point = { "TOP", "UIParent", "TOP", -541, -88 } },
			-- The boss frames start a little lower, clear of the raid warnings.
			EldoUI_Boss = { below = 2400, point = { "CENTER", "UIParent", "CENTER", 296, 120 } },
		},
	},
}

-- EldoModern2000 takes everything it does not change from EldoModern.
do
	local function Copy(value)
		if type(value) ~= "table" then return value end
		local copy = {}
		for key, entry in pairs(value) do copy[key] = Copy(entry) end
		return copy
	end
	local layout, base = E.layouts.EldoModern2000, E.layouts.EldoModern
	for field, value in pairs(base) do
		if field ~= "retiredIn" and layout[field] == nil then layout[field] = Copy(value) end
	end
	for _, field in ipairs({ "points", "narrowPoints" }) do
		for name, point in pairs(base[field] or {}) do
			if layout[field][name] == nil then layout[field][name] = Copy(point) end
		end
	end
end

E.layoutOrder = { "EldoModern", "EldoModern2000", "EldoClassic" }

-- Action bar shapes: every preset names the shape of
-- bars 1 to 5, so a shape a previous preset set never leaks into the next,
-- and of bar 8: a 6 by 2 block like bars 6 and 7, so the bar has a spot of
-- its own when the player turns it on.
function E.LayoutBarShapes(overrides)
	local bars = {
		[1] = { buttons = 12, perRow = 12, size = 46, spacing = 4 },
		[2] = { buttons = 12, perRow = 12, size = 46, spacing = 4 },
		[3] = { buttons = 12, perRow = 12, size = 46, spacing = 4 },
		[4] = { buttons = 12, perRow = 1, size = 40, spacing = 4 },
		[5] = { buttons = 12, perRow = 12, size = 40, spacing = 4 },
		[8] = { buttons = 12, perRow = 6, size = 36, spacing = 4 },
	}
	for index, shape in pairs(overrides or {}) do
		for key, value in pairs(shape) do bars[index][key] = value end
	end
	return { bars = bars }
end
E.layouts.EldoModern.modules.ActionBars = E.LayoutBarShapes()
E.layouts.EldoModern2000.modules.ActionBars = E.LayoutBarShapes()
-- Modern Center's right-edge column hides its empty buttons, like every
-- side grid at a screen edge.
E.layouts.EldoModern.modules.ActionBars.bars[4].showGrid = false
E.layouts.EldoModern2000.modules.ActionBars.bars[4].showGrid = false
E.layouts.EldoClassic.modules.ActionBars = E.LayoutBarShapes()
-- The micro menu on its own mover sits right above the bag bar, sharing
-- its right edge: three rows of five at 80 % in Eldo-Modern, two rows of
-- seven in Eldo-Classic.
E.layouts.EldoModern.modules.MicroMenu = { micro = { scale = 80, perRow = 5, spacing = 2, growth = "rightDown" } }
E.layouts.EldoModern2000.modules.MicroMenu = { micro = { scale = 80, perRow = 5, spacing = 2, growth = "rightDown" } }
E.layouts.EldoClassic.modules.MicroMenu = { micro = { scale = 80, perRow = 7, spacing = 2, growth = "rightDown" } }
-- The experience bar is as long as the bottom bar row (12 buttons of 46).
E.layouts.EldoModern.modules.StatusBars = { width = 596 }
E.layouts.EldoModern2000.modules.StatusBars = { width = 596 }
E.layouts.EldoClassic.modules.StatusBars = { width = 596 }

-- The layout the profile places by. A layout key that is not installed
-- (an imported layout that was removed, a layout of a newer EldoUI) stays
-- in the profile: the frames use the default layout until the player picks
-- one, and the chat says so once (E:EffectiveLayout tells why).
local missingNoted = {}
local function CurrentLayout()
	local key = E.db.general.layout
	local layout = E.layouts[key]
	if layout then return layout end
	local resolved = E.ResolveLayoutKey and E:ResolveLayoutKey(key)
	if resolved then return E.layouts[resolved] end
	local fallback = E.defaults.general.layout
	if key ~= nil and not missingNoted[key] then
		missingNoted[key] = true
		E:Print(L["Your layout %s is not installed. Your frames use the %s layout until you pick one; your own positions are kept."]
			:format(E:Highlight(tostring(key)), E:Highlight(E.LayoutTitle and E:LayoutTitle(fallback) or fallback)))
	end
	return E.layouts[fallback]
end

E.defaults.general.layoutFit = true

-- Presets are measured on a 1440-unit-tall screen (layout.refHeight). On a
-- smaller or larger screen the offsets are scaled by the height ratio, so a
-- frame placed 400 units right of center at 1440p sits 300 right at 1080p and
-- everything keeps its place relative to the others. The "auto" UI scale
-- keeps a 1440-unit canvas on every screen instead (Core/Scale.lua): the
-- ratio is then canvas / refHeight, 1 for every 1440p preset, so "Fit
-- layouts to the screen height" only matters with "pixel" or a number.
-- Movers are clamped to the screen as a last guard. Dragged positions are
-- never scaled; role points (Core/Roles.lua) are scaled like layout points.
--
-- Wide points: a frame that can grow wider than the free band at its
-- spot gets a second point in layout.widePoints:
--   widePoints = {
--       EldoUI_GroupPets = { width = 93, point = { "TOPLEFT", "EldoUI_RaidMover", "BOTTOMLEFT", 0, -12 } },
--       EldoUI_Tanks = { width = 93, of = "EldoUI_GroupPets", point = { ... } },
--   }
-- While the mover (or the mover named by `of`) is wider than `width` (layout
-- units, scaled like the offsets) the layout uses that point instead, so a
-- neighbor can make room in the same step. A wide point can also take a
-- `height` (the mover is taller than that) and more conditions in `also`,
-- each with its own `width` or `height` and `of`; any condition that holds
-- picks the wide point:
--       EldoUI_Tanks = { width = 93, of = "EldoUI_GroupPets", point = { ... },
--           also = { { height = 350, of = "EldoUI_Raid" } } },
-- (the main tanks go beside the raid when the pets grid is wide, or when
-- the raid is taller than the band under it). A condition can also name a
-- style, `style = { Auras = "Bars" }`: it holds while that style is the one
-- applied last, for a style whose frames have the size of another spot (the
-- timer-bar debuffs beside the buffs in Nameplate Focus). Wide points
-- follow the chain rules of `points` (same module, no cycles across
-- layouts). The module that resizes the frame re-places the movers with
-- E:ApplyMover, which waits for the end of combat; a style apply and a
-- layout apply pick the right points by themselves.
--
-- Narrow points: the layouts are made for a screen 2560 layout units wide
-- (16:9). A screen of another shape keeps the height (1440 units at Auto)
-- and changes the width: 16:10 is 2304 units wide, so each side column has
-- 128 units less room. A frame that would then sit on a neighbor gets a
-- spot of its own in layout.narrowPoints:
--   narrowPoints = {
--       EldoUI_Boss = { below = 2400, point = { "CENTER", "UIParent", "CENTER", 796, -384 } },
--   }
-- While the screen is narrower than `below` layout units the layout uses
-- that point; it comes before a wide point. Same chain rules as `points`.
local scaled = setmetatable({}, { __mode = "k" })

-- The factor layout offsets are multiplied by: 1 with layout fit off,
-- otherwise the screen height in UI units over the layout's refHeight. With
-- the "auto" scale the screen is the 1440-unit canvas by definition (a
-- notch offset on UIParent doesn't shift the presets). `height` (optional)
-- is a screen height to measure for instead of UIParent's (layout maps).
-- Picker retirement does not change a built-in family's placement policy.
function E:LayoutUsesFamilyPlacement(layout)
	if type(layout) ~= "table" then return false end
	if not layout.retiredIn then return true end
	local value = layout.familyVersion
	if self.IsSecret and self:IsSecret(value) then return false end
	return type(value) == "boolean" and value
end

function E:GetLayoutRatio(layout, height)
	if not self.db.general.layoutFit then return 1 end
	layout = layout or CurrentLayout()
	height = self.db.general.uiScale == "auto" and 1440 or height or UIParent:GetHeight()
	return height / (layout and layout.refHeight or 1440)
end

-- A point of the layout (or the role layer) scaled by `ratio`: offsets
-- from the screen follow the screen height; chained points keep their gaps
-- scaled too, so a stack keeps its shape. Cached per point and ratio.
function E:ScaleLayoutPoint(point, ratio)
	if not point or math.abs(ratio - 1) < 0.01 then return point end
	local cache = scaled[point]
	if not cache or cache.ratio ~= ratio then
		cache = { ratio = ratio, value = { point[1], point[2], point[3], math.floor(point[4] * ratio + 0.5), math.floor(point[5] * ratio + 0.5) } }
		scaled[point] = cache
	end
	return cache.value
end

local function LayoutNumber(value, positive)
	return not E:IsSecret(value) and type(value) == "number" and value == value
		and math.abs(value) < math.huge and (not positive or value > 0)
end

-- Project an existing point chain without reading its current placement.
-- read(name) returns point, width, height, parent name, root rect, offset scale.
-- The installer keeps its screen fallback; placement callers omit it.
function E:LayoutRectangles(read, options)
	options = options or {}
	local rects, busy = {}, {}
	local function Axis(rect, point, low, high, first, last)
		if point:find(first) then return rect[low] end
		if point:find(last) then return rect[high] end
		return (rect[low] + rect[high]) / 2
	end
	local function Resolve(name, depth)
		depth = depth or 0
		if rects[name] then return rects[name] end
		if busy[name] or depth > (options.depth or 12) then return nil, "cycle" end
		local point, width, height, parent, root, scale = read(name)
		if E:IsSecret(point) then return nil, "invalid" end
		if not point then return nil, "missing" end
		if type(point) ~= "table" or E:IsSecret(point[1]) or E:IsSecret(point[3])
			or type(point[1]) ~= "string" or type(point[3]) ~= "string"
			or not LayoutNumber(point[4]) or not LayoutNumber(point[5])
			or not LayoutNumber(width, true) or not LayoutNumber(height, true)
			or not LayoutNumber(scale, true) then return nil, "invalid" end
		if not options.fallback then
			local anchors = "|TOPLEFT|TOP|TOPRIGHT|LEFT|CENTER|RIGHT|BOTTOMLEFT|BOTTOM|BOTTOMRIGHT|"
			if not anchors:find("|" .. point[1] .. "|", 1, true) or not anchors:find("|" .. point[3] .. "|", 1, true) then return nil, "invalid" end
		end
		busy[name] = true
		local relative = root
		if parent then relative = Resolve(parent, depth + 1) or options.fallback end
		busy[name] = nil
		if type(relative) ~= "table" then return nil, "relative" end
		for index = 1, 4 do if not LayoutNumber(relative[index]) then return nil, "relative" end end
		local x = Axis(relative, point[3], 1, 3, "LEFT", "RIGHT") + point[4] * scale
		local y = Axis(relative, point[3], 2, 4, "BOTTOM", "TOP") + point[5] * scale
		local left = point[1]:find("LEFT") and x or (point[1]:find("RIGHT") and x - width or x - width / 2)
		local bottom = point[1]:find("BOTTOM") and y or (point[1]:find("TOP") and y - height or y - height / 2)
		local rect = { left, bottom, left + width, bottom + height }
		for index = 1, 4 do if not LayoutNumber(rect[index]) then return nil, "invalid" end end
		rects[name] = rect
		return rect
	end
	return Resolve, rects
end

-- A frame that draws less than its layout gives it (bar 3 shows at most
-- nine of its buttons) is measured at its layout size, so the frames whose
-- spot depends on its size stay where the layout puts them.
-- fn() returns width, height in UI units, or nil for the size on screen.
local measureHooks = {}
function E:RegisterLayoutMeasure(name, fn)
	measureHooks[name] = fn
end

-- The size the wide points measure for mover `name`.
function E:LayoutMeasuredSize(name)
	local mover = self.movers[name]
	if not mover then return nil end
	local hook = measureHooks[name]
	if hook then
		local ok, width, height = pcall(hook)
		if ok and type(width) == "number" and type(height) == "number" then return width, height end
	end
	return mover:GetWidth() or 0, mover:GetHeight() or 0
end

-- Does one wide point condition hold? `cond` has `width` and/or `height`
-- (layout units) and `of` (the mover measured; `name` itself without it).
local function Outgrows(cond, name, ratio)
	-- A style condition holds while that style is the one applied last.
	if type(cond.style) == "table" then
		for moduleName, styleKey in pairs(cond.style) do
			if E.StyleApplied and E:StyleApplied(moduleName) == styleKey then return true end
		end
	end
	local width, height = E:LayoutMeasuredSize(cond.of or name)
	if not width then return false end
	if type(cond.width) == "number" and width > cond.width * ratio + 0.5 then return true end
	if type(cond.height) == "number" and height > cond.height * ratio + 0.5 then return true end
	return false
end

-- The layout's point for `name`, or its wide point when the mover is wider
-- (or taller) than the layout allows at the normal spot. `ratio` is the
-- layout fit ratio.
local PointFor

-- Beside and under the minimap: a frame whose wide point measures the
-- map moves out with a map larger than the layout's by exactly the
-- difference, keeping the layout's gap to the map, or to the ring a skin
-- draws round it; with a smaller map it keeps its own spot. Beside the map
-- (width) for frames placed from the screen's right edge, under it
-- (height) for frames placed from its top edge. Not on legacy layouts,
-- which place exactly as they always did.
local function FollowMap(layout, point, wide, ratio)
	if not E:LayoutUsesFamilyPlacement(layout) or wide.of ~= "EldoUI_Minimap" or point[2] ~= "UIParent" or ratio <= 0 then return nil end
	local across = type(wide.width) == "number" and (tostring(point[1]):find("RIGHT") or tostring(point[3]):find("RIGHT"))
	local down = not across and type(wide.height) == "number" and tostring(point[1]):find("TOP")
	if not (across or down) then return nil end
	local map = E.movers.EldoUI_Minimap
	local size = map and (across and map:GetWidth() or map:GetHeight())
	if type(size) ~= "number" or E:IsSecret(size) then return nil end
	local minimap = E.modules.Minimap
	local pad = minimap and minimap.active and tonumber(minimap.paintPad) or 0
	local shift = (size + pad - (across and wide.width or wide.height) * ratio) / ratio
	-- Only a map bigger than the layout's (or a drawn ring past its box)
	-- moves its neighbors out; a smaller map leaves them on the layout's own
	-- spots, which keep clear of each other (moving them in would put the
	-- buff rows over the quest list under the map).
	if shift < 0.5 then return point end
	if across then return { point[1], point[2], point[3], point[4] - shift, point[5] } end
	return { point[1], point[2], point[3], point[4], point[5] - shift }
end

-- The group pets and the main tanks can both want the spot beside the
-- raid (a tall raid sends the tanks there). Then the frame in use keeps
-- the spot and the other goes beside it: with the tanks on, the pets go
-- beside the tanks; with the tanks off, the tanks' holder goes beside the
-- pets, so the two never sit on each other, not even in move mode.
local function SameSpot(a, b)
	return a and b and a[2] == b[2] and a[3] == b[3] and a[4] == b[4] and a[5] == b[5]
end
local function BesideTanks(layout, name, own, ratio)
	if not E:LayoutUsesFamilyPlacement(layout) or not own then return nil end
	if name ~= "EldoUI_GroupPets" and name ~= "EldoUI_Tanks" then return nil end
	if not (E.movers.EldoUI_Tanks and E.movers.EldoUI_GroupPets and layout.points.EldoUI_Tanks and layout.points.EldoUI_GroupPets) then return nil end
	local groups = E.modules.GroupFrames
	-- The switch decides, not whether the holder is built yet: a layout can
	-- place the pets before the main tanks frame is shown.
	local on = groups and groups.db and type(groups.db.tanks) == "table" and groups.db.tanks.enabled
	if name == "EldoUI_GroupPets" and on then
		if SameSpot(own, PointFor(layout, "EldoUI_Tanks", ratio)) then return { "TOPLEFT", "EldoUI_TanksMover", "TOPRIGHT", 8, 0 } end
	elseif name == "EldoUI_Tanks" and not on then
		if SameSpot(own, PointFor(layout, "EldoUI_GroupPets", ratio)) then return { "TOPLEFT", "EldoUI_GroupPetsMover", "TOPRIGHT", 8, 0 } end
	end
	return nil
end

-- The screen's width in layout units (UI units divided by the fit ratio).
local function LayoutWidth(ratio)
	local width = UIParent:GetWidth() or 0
	return width / ((ratio and ratio > 0) and ratio or 1)
end
E.LayoutWidth = LayoutWidth

-- A module can send one of its frames to the spot of another mover of the
-- layout while one of its own settings asks for it: fn() returns that
-- mover's name, or nil for the frame's own spot. The module re-places its
-- mover (E:ApplyMover) when the answer changes. Battleground Timers use it
-- while they show next to a boss mod's battleground timers
-- (Modules/Battlegrounds/Battlegrounds.lua), the flight timer while the
-- second info bar has a box of its own (Modules/QoL.lua).
local spotRules = {}
function E:RegisterLayoutSpotRule(name, fn)
	spotRules[name] = fn
end

-- The optional narrow alternative must remain a public native point tuple.
local function AdaptivePoint(point)
	if E:IsSecret(point) or type(point) ~= "table" or #point ~= 5 then return false end
	local anchors = "|TOPLEFT|TOP|TOPRIGHT|LEFT|CENTER|RIGHT|BOTTOMLEFT|BOTTOM|BOTTOMRIGHT|"
	for index = 1, 5 do
		local value = point[index]
		if E:IsSecret(value) then return false end
		if index <= 3 then
			if type(value) ~= "string" or value == "" then return false end
			if index ~= 2 and (not value:match("^[A-Z]+$") or not anchors:find("|" .. value .. "|", 1, true)) then return false end
		elseif type(value) ~= "number" or value ~= value or math.abs(value) == math.huge then
			return false
		end
	end
	return true
end

function PointFor(layout, name, ratio)
	local rule = spotRules[name]
	local other = rule and rule()
	if type(other) == "string" and other ~= name and layout.points[other] then return PointFor(layout, other, ratio) end
	local point = layout.points[name]
	-- A narrow spot also stands without a point of its own: a frozen layout
	-- keeps its points as shipped and gets a 16:10 spot only there.
	local narrow = layout.narrowPoints and layout.narrowPoints[name]
	if narrow and type(narrow.below) == "number" then
		local width = LayoutWidth(ratio)
		if width > 0 and width < narrow.below then
			local adaptive = narrow.adaptive
			if type(adaptive) == "table" and AdaptivePoint(adaptive.point) then
				local follow = type(narrow.point) == "table" and FollowMap(layout, narrow.point, adaptive, ratio)
				if follow then return follow end
				if Outgrows(adaptive, name, ratio) then return adaptive.point end
				for _, cond in ipairs(type(adaptive.also) == "table" and adaptive.also or {}) do
					if type(cond) == "table" and Outgrows(cond, name, ratio) then return adaptive.point end
				end
			end
			return narrow.point
		end
	end
	local wide = point and layout.widePoints and layout.widePoints[name]
	if not wide then return point end
	local follow = FollowMap(layout, point, wide, ratio)
	if follow then return follow end
	local chosen = point
	if Outgrows(wide, name, ratio) then
		chosen = wide.point
	else
		for _, cond in ipairs(type(wide.also) == "table" and wide.also or {}) do
			if Outgrows(cond, name, ratio) then
				chosen = wide.point
				break
			end
		end
	end
	return BesideTanks(layout, name, chosen, ratio) or chosen
end

local CLUSTER_ARROW, CLUSTER_COORDS = "EldoUI_WaypointArrow", "EldoUI_WaypointCoords"

local function ClusterDescriptor(layout, ratio)
	local narrow = layout.narrowPoints and layout.narrowPoints[CLUSTER_ARROW]
	if narrow and LayoutNumber(narrow.below, true) then
		local width = LayoutWidth(ratio)
		if LayoutNumber(width, true) and width < narrow.below then return narrow.adaptive end
	end
	return layout.widePoints and layout.widePoints[CLUSTER_ARROW]
end

function E:MinimapClusterEnabled()
	local layout = CurrentLayout()
	local ratio = self:GetLayoutRatio(layout)
	if not self:LayoutUsesFamilyPlacement(layout) or not LayoutNumber(ratio, true) or not LayoutNumber(LayoutWidth(ratio), true) then return false end
	local descriptor = ClusterDescriptor(layout, ratio)
	return type(descriptor) == "table" and descriptor.cluster == true and descriptor.of == "EldoUI_Minimap"
end

-- The native owners call this only after their own layout has finished.
function E:RefreshMinimapCluster()
	if not self:MinimapClusterEnabled() or not self.LayoutClusterOwnsMover
		or not self:LayoutClusterOwnsMover(CLUSTER_ARROW) or not self:LayoutClusterOwnsMover(CLUSTER_COORDS) then return end
	local profile, layout = self.db, CurrentLayout()
	local arrow, coords = self.movers[CLUSTER_ARROW], self.movers[CLUSTER_COORDS]
	local owners = {}
	for _, name in ipairs({ "Minimap", "Auras", "Waypoints", "QoL" }) do
		local module = self.modules[name]
		if not module then return end
		owners[name] = { module, module.db, module.active }
	end
	local function Valid()
		if self.db ~= profile or CurrentLayout() ~= layout or not self:MinimapClusterEnabled()
			or self.movers[CLUSTER_ARROW] ~= arrow or self.movers[CLUSTER_COORDS] ~= coords
			or not self:LayoutClusterOwnsMover(CLUSTER_ARROW) or not self:LayoutClusterOwnsMover(CLUSTER_COORDS) then return false end
		for name, owned in pairs(owners) do
			if self.modules[name] ~= owned[1] or owned[1].db ~= owned[2] or owned[1].active ~= owned[3] then return false end
		end
		return true
	end
	self:RunOutOfCombat(function()
		if not Valid() then return end
		local expectedArrow, expectedCoords = self:GetLayoutPoint(CLUSTER_ARROW), self:GetLayoutPoint(CLUSTER_COORDS)
		local function SamePoint(a, b)
			if not AdaptivePoint(a) or not AdaptivePoint(b) then return false end
			for index = 1, 5 do if a[index] ~= b[index] then return false end end
			return true
		end
		self:ApplyMover(CLUSTER_ARROW)
		if Valid() and SamePoint(expectedArrow, self:GetLayoutPoint(CLUSTER_ARROW))
			and SamePoint(expectedCoords, self:GetLayoutPoint(CLUSTER_COORDS)) then self:ApplyMover(CLUSTER_COORDS) end
	end, "Layout:MinimapCluster")
end

-- The map's own cluster has a fixed set of owners. A layout may keep its
-- navigation pair outside their measured rectangles without reading auras.
function E:LayoutMinimapCluster(layout, name, point, ratio)
	if name ~= CLUSTER_ARROW and name ~= CLUSTER_COORDS then return nil, "off" end
	if not LayoutNumber(ratio, true) or not AdaptivePoint(point) then return nil, "invalid" end
	local descriptor = ClusterDescriptor(layout, ratio)
	if type(descriptor) ~= "table" or descriptor.cluster == nil then return nil, "off" end
	if descriptor.cluster ~= true or descriptor.of ~= "EldoUI_Minimap" or not self:LayoutUsesFamilyPlacement(layout)
		or not LayoutNumber(ratio, true) or not self.LayoutClusterOwnsMover then return nil, "unavailable" end
	local map, auras, way = self.modules.Minimap, self.modules.Auras, self.modules.Waypoints
	if not (map and map.active and map.mode == "replace" and map.masked and type(map.db) == "table"
		and auras and type(auras.db) == "table" and way and way.active and type(way.db) == "table") then return nil, "owner" end
	if not (self:BlizzardAllowed("minimap", "replace") and self:BlizzardAllowed("minimap", "move")) then return nil, "policy" end
	local private
	if auras.active and auras.db.privateAuras and auras.db.privateAuras.enabled then
		if type(auras.PrivateLayoutGeometry) ~= "function" then return nil, "private" end
		private = auras:PrivateLayoutGeometry()
		if not private then return nil, "private" end
	end
	local rootScale = UIParent:GetEffectiveScale()
	if not LayoutNumber(rootScale, true) then return nil, "scale" end
	local function Public(...)
		for index = 1, select("#", ...) do if E:IsSecret((select(index, ...))) then return false end end
		return true
	end
	local function Scale(frame)
		local value = frame and frame:GetEffectiveScale()
		if LayoutNumber(value, true) then return value / rootScale end
	end
	local nodes, occupied = {}, {}
	local function Add(key, frame, owner, on)
		local mover = self.movers[key]
		if not Public(frame, mover) or not (frame and mover and mover.frame == frame and mover.module == owner and self:LayoutClusterOwnsMover(key)) then return false end
		local count = frame:GetNumPoints()
		if not LayoutNumber(count) or count ~= 1 then return false end
		local p, relative, rp, x, y = frame:GetPoint(1)
		if not Public(p, relative, rp, x, y) or p ~= "CENTER" or relative ~= mover or rp ~= "CENTER" or x ~= 0 or y ~= 0 then return false end
		local ms, fs = Scale(mover), Scale(frame)
		local w, h = frame:GetSize()
		if not (LayoutNumber(ms, true) and LayoutNumber(fs, true) and LayoutNumber(w, true) and LayoutNumber(h, true)) then return false end
		nodes[key] = { mover = mover, frame = frame, scale = ms, width = w * fs, height = h * fs }
		if on then occupied[#occupied + 1] = key end
		return true
	end
	if not Add("EldoUI_Minimap", map.holder, "Minimap", map.holder and map.holder:IsShown())
		or not Add(CLUSTER_ARROW, way.arrowHolder, "Waypoints", false)
		or not Add(CLUSTER_COORDS, way.coordHolder, "Waypoints", false) then return nil, "frame" end
	for _, row in ipairs({ { "Buffs", "buffHolder", "buffs" }, { "Debuffs", "debuffHolder", "debuffs" }, { "TempEnchants", "enchantHolder", "enchants" } }) do
		local db = auras.db[row[3]]
		if type(db) ~= "table" or not Add("EldoUI_" .. row[1], auras[row[2]], "Auras", auras.active and db.enabled) then return nil, "auras" end
	end
	local qol = self.modules.QoL
	if not (qol and type(qol.DurabilityLayoutBounds) == "function") then return nil, "durability" end
	local holder, bounds, reason = qol:DurabilityLayoutBounds()
	if reason then return nil, reason end
	if holder then
		if not Add("EldoUI_Durability", holder, "QoL", true) then return nil, "durability" end
		nodes.EldoUI_Durability.bounds = bounds
	end
	local function Root(relativePoint)
		local anchor = self.GetMoverAnchor and self:GetMoverAnchor(relativePoint) or UIParent
		local s = Scale(anchor)
		if not LayoutNumber(s, true) then return nil end
		local l, b, w, h = anchor:GetRect()
		if not (LayoutNumber(l) and LayoutNumber(b) and LayoutNumber(w, true) and LayoutNumber(h, true)) then return nil end
		return { l * s, b * s, (l + w) * s, (b + h) * s }
	end
	local points = {}
	local resolve = self:LayoutRectangles(function(key)
		local node = nodes[key]
		if not node then return end
		local p = self:ScaleLayoutPoint(PointFor(layout, key, ratio), ratio)
		if not AdaptivePoint(p) or p.link ~= nil then return end
		points[key] = p
		local parent = p[2]:match("^(EldoUI_.+)Mover$")
		if p[2] ~= "UIParent" and not parent then return end
		if key ~= CLUSTER_COORDS and (parent == CLUSTER_ARROW or parent == CLUSTER_COORDS) then return end
		local root = p[2] == "UIParent" and Root(p[3]) or nil
		local w, h = node.mover:GetSize()
		if not LayoutNumber(w, true) or not LayoutNumber(h, true) then return end
		return p, w * node.scale, h * node.scale, parent, root, node.scale
	end)
	local rects = {}
	for key, node in pairs(nodes) do
		local rect = resolve(key)
		if not rect then return nil, "dependency" end
		local cx, cy = (rect[1] + rect[3]) / 2, (rect[2] + rect[4]) / 2
		rects[key] = { cx - node.width / 2, cy - node.height / 2, cx + node.width / 2, cy + node.height / 2 }
		if node.bounds then
			for index = 1, 4 do if not LayoutNumber(node.bounds[index]) then return nil, "bounds" end end
			rects[key] = { cx + node.bounds[1], cy + node.bounds[2], cx + node.bounds[3], cy + node.bounds[4] }
		end
	end
	local arrow, coords = points[CLUSTER_ARROW], points[CLUSTER_COORDS]
	if arrow[2] ~= "UIParent" or (coords[2] ~= "UIParent" and coords[2] ~= CLUSTER_ARROW .. "Mover") then return nil, "navigation" end
	if private then
		local slots = self:LayoutRectangles(function(index)
			local slot = private.slots[index]
			if not slot or index > private.count then return end
			local scale = Scale(slot.holder)
			if not LayoutNumber(scale, true) then return end
			return slot.point, slot.width * scale, slot.height * scale, nil, rects.EldoUI_Debuffs, scale
		end)
		for index = 1, private.count do
			local rect = slots(index)
			if not rect then return nil, "private" end
			local key = "private" .. index
			rects[key], occupied[#occupied + 1] = rect, key
		end
	end
	local mapRect = rects.EldoUI_Minimap
	local hardware = map.originalHardware
	if hardware and hardware:IsShown() then
		local border = hardware.border
		if not (border and border:IsShown() and border:GetParent() == hardware and border:GetNumPoints() == 1) then return nil, "border" end
		local p, relative, rp, x, y = border:GetPoint(1)
		local scale = Scale(border)
		local w, h = border:GetSize()
		if not Public(p, relative, rp) or p ~= "CENTER" or relative ~= map.holder or rp ~= "CENTER" or not LayoutNumber(x) or not LayoutNumber(y)
			or not LayoutNumber(scale, true) or not LayoutNumber(w, true) or not LayoutNumber(h, true) then return nil, "border" end
		local cx = (mapRect[1] + mapRect[3]) / 2 + x * scale
		local cy = (mapRect[2] + mapRect[4]) / 2 + y * scale
		mapRect[1], mapRect[2] = math.min(mapRect[1], cx - w * scale / 2), math.min(mapRect[2], cy - h * scale / 2)
		mapRect[3], mapRect[4] = math.max(mapRect[3], cx + w * scale / 2), math.max(mapRect[4], cy + h * scale / 2)
	else
		local pad = map.paintPad
		if not LayoutNumber(pad) or pad < 0 then return nil, "border" end
		local grow = pad * Scale(map.holder)
		mapRect[1], mapRect[2], mapRect[3], mapRect[4] = mapRect[1] - grow, mapRect[2] - grow, mapRect[3] + grow, mapRect[4] + grow
	end
	local shift = 0
	for _, consumer in ipairs({ CLUSTER_ARROW, CLUSTER_COORDS }) do
		if (consumer == CLUSTER_ARROW and way.db.arrow) or (consumer == CLUSTER_COORDS and way.db.coordBox) then
			local own = rects[consumer]
			for _, key in ipairs(occupied) do
				local peer = rects[key]
				if own[2] < peer[4] + 4 and own[4] > peer[2] - 4 then shift = math.max(shift, own[3] + 4 - peer[1]) end
			end
		end
	end
	if shift <= 0 then return point end
	-- A coordinate box attached to the structural arrow inherits this same
	-- correction, including while the arrow itself is switched off.
	if name == CLUSTER_COORDS and coords[2] == CLUSTER_ARROW .. "Mover" then return point end
	local moved = { point[1], point[2], point[3], point[4] - shift / nodes[name].scale, point[5] }
	return moved
end

-- Is `name` on its wide point in the current layout?
function E:IsLayoutPointWide(name)
	local layout = CurrentLayout()
	local point = PointFor(layout, name, self:GetLayoutRatio(layout))
	return point ~= nil and point ~= layout.points[name]
end

-- Re-places every frame the current layout gives a wide point, and every
-- frame a spot rule can send elsewhere, so a style that made a frame (or
-- the frame a wide point measures) bigger or smaller moves its neighbors at
-- once. Each frame picks its spot from the sizes as they are now;
-- ApplyMover waits for the end of combat.
function E:ApplyWidePoints()
	local layout = CurrentLayout()
	for name in pairs(layout and type(layout.widePoints) == "table" and layout.widePoints or {}) do
		self:ApplyMover(name)
	end
	for name, narrow in pairs(layout and type(layout.narrowPoints) == "table" and layout.narrowPoints or {}) do
		if type(narrow) == "table" and type(narrow.adaptive) == "table"
			and not (layout.widePoints and layout.widePoints[name]) then self:ApplyMover(name) end
	end
	for name in pairs(spotRules) do
		local narrow = layout and layout.narrowPoints and layout.narrowPoints[name]
		if not (layout and layout.widePoints and layout.widePoints[name])
			and not (type(narrow) == "table" and type(narrow.adaptive) == "table") then self:ApplyMover(name) end
	end
end

-- Only the current Wide family opts into the consumable dock through its
-- existing Action Bar 5 point. Old and imported point records keep their route.
local WideConsumablePoint
do
	local CB, MAIN = "EldoUI_ConsumableBar", "EldoUI_Cooldowns"
	local busy, invalidate, lastShape, lastContext = false, nil, nil, nil
	local stackOwner, stackSource, readBounds, publicReadBounds, refreshStack, latestRequest
	local boundStackOwner, boundStack, boundStackPublic, boundStackNative
	local powerRowOwner, powerRowRead, powerRowCount
	local actionOwner, actionRead, actionCount
	local moverReadSource, moverReadAuthority
	local secretSource, isSecretSource = E.Secret, E.IsSecret
	local Secret = secretSource
	if type(Secret) ~= "function" then
		local read = isSecretSource
		Secret = function(value) return read(E, value) end
	end
	local function Public(...)
		for i = 1, select("#", ...) do if Secret((select(i, ...))) then return false end end
		return true
	end
	local function Same(a, b) return not Secret(a) and not Secret(b) and rawequal(a, b) end
	local function Table(value) return not Secret(value) and type(value) == "table" and type(getmetatable(value)) == "nil" end
	local function Record(read)
		local count, seen = 0, {}
		local function Copy(value, depth)
			if not Public(value) or depth > 8 then error("Unreadable layout source") end
			local kind = type(value)
			if kind ~= "table" then
				if kind ~= "nil" and kind ~= "boolean" and kind ~= "string" and kind ~= "function" and not LayoutNumber(value) then error("Unreadable layout value") end
				return { kind = kind, value = value }
			end
			if not Table(value) or seen[value] then error("Unreadable layout record") end
			seen[value] = true
			local result = { kind = kind, value = value, fields = {}, count = 0 }
			for key, item in pairs(value) do
				if not Public(key) or (type(key) ~= "string" and not LayoutNumber(key)) then error("Unreadable layout key") end
				count = count + 1;if count > 256 then error("Layout source is too large") end
				result.fields[key] = Copy(item, depth + 1);result.count = result.count + 1
			end
			seen[value] = nil;return result
		end
		local expected = Copy(read(), 0)
		local function Equal(value, saved)
			if not Public(value) or type(value) ~= saved.kind or not Same(value, saved.value) then return false end
			if saved.kind ~= "table" then return true end
			if not Table(value) then return false end
			local size = 0;for _ in pairs(value) do size = size + 1 end
			if size ~= saved.count then return false end
			for key, item in pairs(saved.fields) do if not Equal(rawget(value, key), item) then return false end end
			return true
		end
		return function() return Equal(read(), expected) end
	end
	local function Enabled(layout)
		local catalog = rawget(E, "layouts")
		if not Public(catalog) or type(catalog) ~= "table" or not Same(layout, rawget(catalog, "EldoWide1000")) or not Table(layout) then return false end
		local points = rawget(layout, "points")
		if not Table(points) then return false end
		local point = rawget(points, CB)
		return AdaptivePoint(point) and point[2] == "EldoUI_ActionBar5Mover"
	end
	-- The mover owner binds this source during its own setup, before reads.
	function E:RegisterWideMoverReadSource(source, authority)
		if not Same(self, E) or not Public(source, authority) or type(source) ~= "function" or type(authority) ~= "function"
			or not Same(rawget(E, "MoverAuthoritySource"), source) or not Same(rawget(E, "LayoutClusterOwnsMover"), authority) then return false end
		if moverReadSource then return Same(moverReadSource, source) and Same(moverReadAuthority, authority) end
		moverReadSource, moverReadAuthority = source, authority
		return true
	end
	function E:RegisterWideStackReadSource(owner, stack, public, native)
		if not Same(self, E) or not Table(rawget(E, "modules")) or not Same(rawget(E.modules, "CooldownManager"), owner)
			or not Table(rawget(E, "CombatKit")) or not Same(rawget(E.CombatKit, "CooldownStack"), stack) or not Table(stack)
			or not Public(public, native) or type(public) ~= "function" or type(native) ~= "function" or not Same(rawget(stack, "LayoutBounds"), public) then return false end
		if boundStack then return Same(owner, boundStackOwner) and Same(stack, boundStack) and Same(public, boundStackPublic) and Same(native, boundStackNative) end
		boundStackOwner, boundStack, boundStackPublic, boundStackNative = owner, stack, public, native
		return true
	end

	local function Shape(layout, ratio)
		if busy then if invalidate then invalidate() end; return end
		if not Same(rawget(E, "Secret"), secretSource)
			or not Enabled(layout) or not LayoutNumber(ratio, true) or not Table(E.modules) or not Table(E.movers) then return end
		busy = true
		local reentered = false
		local invalidateRead = function() reentered = true end
		invalidate = invalidateRead
		local ok, result = pcall(function()
			local root, profile, movers, modules = E.db, E.profileName, E.movers, E.modules
			local uiRoot, catalog, secretMethod = UIParent, rawget(E, "layouts"), rawget(E, "IsSecret")
			local catalogMeta = getmetatable(catalog)
			if not Table(root) or not Table(root.general) then return end
			local general, layoutKey, uiScale, fit = root.general, root.general.layout, root.general.uiScale, root.general.layoutFit
			local cb, bars, uf, cdm = modules.ConsumableBar, modules.ActionBars, modules.UnitFrames, modules.CooldownManager
			if not Public(cb, bars, uf, cdm) or not (cb and bars and uf and cdm) or not Table(cb.db)
				or not Public(bars.db) or type(bars.db) ~= "table" or not Table(uf.db) or not Table(cdm.db) or not Table(bars.db.bars)
				or not Table(uf.frames) or not Public(cb.active, bars.active, uf.active, cdm.active)
				or cb.active ~= true or bars.active ~= true or uf.active ~= true then return end
			local passiveTransaction = actionOwner ~= nil or rawget(bars, "DockSnapshot") ~= nil
			local bar, db, vertical, count = cb.bar, cb.db, cb.db.vertical, cb.shownButtons
			if not Public(bar, vertical) or type(vertical) ~= "boolean" or not LayoutNumber(count) or count < 0 then return end
			local owners = { { cb, cb.db, cb.active }, { bars, bars.db, bars.active }, { uf, uf.db, uf.active }, { cdm, cdm.db, cdm.active } }
			local names = { "ConsumableBar", "ActionBars", "UnitFrames", "CooldownManager" }
			local rootScale
			local nodes, passive, dock, dockCustody, dockCurrent, dockNativeCurrent = {}, {}, nil, nil, nil, nil
			local checks, pointChecks = {}, {}
			local authority, scalePoint, choosePoint = E.LayoutClusterOwnsMover, E.ScaleLayoutPoint, PointFor
			if not Public(authority, scalePoint) or type(authority) ~= "function" or type(scalePoint) ~= "function" then return end
			local frames, actionFrames, actionDB = uf.frames, bars.bars, bars.db.bars
			local receivers, sourceSeals, mainSourceSeal, authoritySeal = {}, {}, nil, nil
			local geometryFactory, intrinsicSeal, domain, readSeal, existingNativeGeometry, nativeBinding, nativeProof
			local authoritySource = moverReadSource
			if not Public(authoritySource) or type(authoritySource) ~= "function" or not Same(authority, moverReadAuthority)
				or not Same(rawget(E, "MoverAuthoritySource"), authoritySource) then return end
			local pointSource, narrowSource, wideSource, savedPoints, gamepad = rawget(layout, "points"), rawget(layout, "narrowPoints"), rawget(layout, "widePoints"), rawget(root, "movers"), rawget(root, "gamepadUI")
			local gamepadPoints = Table(gamepad) and rawget(gamepad, "movers") or nil
			local sourceMethods = {}
			for _, name in ipairs({ "LayoutOwnsMover", "SavedMoverPosition", "MoverStore", "GetGamepadMoverPoint", "GetRoleMoverPoint", "GamepadModeActive", "GamepadOverlayOwns", "GetMoverAnchor" }) do sourceMethods[#sourceMethods + 1] = { name, rawget(E, name) } end
			for _, name in ipairs({ CB, MAIN, "EldoUI_Player", "EldoUI_Target", "EldoUI_Focus", "EldoUI_PlayerPower", "EldoUI_ActionBar1", "EldoUI_ActionBar2", "EldoUI_ActionBar3", "EldoUI_ActionBar5" }) do
				for _, list in ipairs({ { pointSource }, { narrowSource }, { wideSource }, { savedPoints }, { gamepadPoints }, { spotRules } }) do
					local source = list[1]
					if source ~= nil and not Table(source) then return end
					sourceSeals[#sourceSeals + 1] = Record(function() return source and rawget(source, name) end)
				end
				local mover = rawget(movers, name)
				if mover then sourceSeals[#sourceSeals + 1] = Record(function() return rawget(mover, "defaultPoint") end) end
			end
			for _, field in ipairs({ "safeArea", "safeAreaWidth", "safeAreaMargin", "safeAreaCorners" }) do
				sourceSeals[#sourceSeals + 1] = Record(function() return rawget(general, field) end)
			end
			local function SourceSealed(full)
				if not Same(rawget(E, "Secret"), secretSource) or not Same(rawget(E, "IsSecret"), secretMethod)
					or not Same(rawget(_G, "UIParent"), uiRoot) or not Same(rawget(E, "layouts"), catalog) or not Same(getmetatable(catalog), catalogMeta)
					or not Same(rawget(catalog, "EldoWide1000"), layout) or not Same(rawget(layout, "points"), pointSource)
					or not Same(rawget(layout, "narrowPoints"), narrowSource) or not Same(rawget(layout, "widePoints"), wideSource)
					or not Same(rawget(root, "movers"), savedPoints) or not Same(rawget(root, "gamepadUI"), gamepad)
					or (gamepad and (not Table(gamepad) or not Same(rawget(gamepad, "movers"), gamepadPoints))) then return false end
				if not Same(rawget(E, "MoverAuthoritySource"), authoritySource) or (authoritySeal and not authoritySeal())
					or (intrinsicSeal and not intrinsicSeal()) or (readSeal and not readSeal(full)) then return false end
				if dock then
					for name, node in pairs(nodes) do if not domain(name, node.mover, node.frame, full) then return false end end
					for name, node in pairs(passive) do if not domain(name, node.mover, node.frame, full) then return false end end
				end
				for _, method in ipairs(sourceMethods) do if not Same(rawget(E, method[1]), method[2]) then return false end end
				if full then for _, seal in ipairs(sourceSeals) do if not seal() then return false end end end
				return not mainSourceSeal or mainSourceSeal(full)
			end
			local function Sealed(object, record)
				if not Same(getmetatable(object), record.meta) then return false end
				if type(record.meta) == "table" and not Same(rawget(record.meta, "__index"), record.index) then return false end
				for name, method in pairs(record.methods) do
					if (type(object) == "table" and not Same(rawget(object, name), method.raw))
						or (type(record.index) == "table" and not Same(rawget(record.index, name), method.inherited)) then return false end
				end
				return true
			end
			local function MethodsCurrent(receiver)
				if receiver then local record = receivers[receiver];return not record or Sealed(receiver, record) end
				for object, record in pairs(receivers) do if not Sealed(object, record) then return false end end
				return true
			end
			local function BaseCurrent(receiver)
				if reentered or not SourceSealed() or (receiver and not MethodsCurrent(receiver)) or not Same(rawget(E, "db"), root) or not Table(root) or not Same(rawget(root, "general"), general)
					or not Table(general) or not Same(rawget(general, "layout"), layoutKey)
					or not Same(rawget(general, "uiScale"), uiScale) or not Same(rawget(general, "layoutFit"), fit)
					or not Same(rawget(E, "profileName"), profile) or not Same(rawget(E, "movers"), movers) or not Table(movers)
					or not Same(rawget(E, "modules"), modules) or not Table(modules) or not Enabled(layout)
					or not Same(rawget(cb, "bar"), bar) or not Same(rawget(cb, "db"), db) or not Table(db) or not Same(rawget(db, "vertical"), vertical)
					or not Same(rawget(uf, "frames"), frames) or not Same(rawget(bars, "bars"), actionFrames) or not Same(rawget(owners[2][2], "bars"), actionDB)
					or not Same(rawget(cb, "shownButtons"), count) or not Same(rawget(E, "LayoutClusterOwnsMover"), authority)
					or not Same(rawget(E, "ScaleLayoutPoint"), scalePoint) or not Same(PointFor, choosePoint) then return false end
				for i, saved in ipairs(owners) do
					if not Same(rawget(modules, names[i]), saved[1]) or not Same(rawget(saved[1], "db"), saved[2])
						or (saved[1] ~= bars and not Table(saved[2])) or not Same(rawget(saved[1], "active"), saved[3]) then return false end
				end
				for key, node in pairs(nodes) do
					if not Same(rawget(movers, key), node.mover) or not Same(rawget(node.mover, "frame"), node.frame)
						or (dock and (Same(receiver, node.mover) or Same(receiver, node.frame)) and not domain(key, node.mover, node.frame, true)) then return false end
				end
				return true
			end
			local function ContextCurrent(receiver)
				if not BaseCurrent(receiver) then return false end
				if nativeProof then return true end
				if dockCustody then
					local good, current = pcall(dockCustody, receiver)
					if not good or not Same(current, true) or not BaseCurrent(receiver) then return false end
				end
				for _, check in ipairs(checks) do
					local good, current = pcall(check)
					if not good or not Public(current) or current ~= true or not BaseCurrent(receiver) then return false end
				end
				return BaseCurrent(receiver)
			end
			local function Current(receiver)
				if not ContextCurrent(receiver) then return false end
				if nativeProof then return true end
				for key in pairs(nodes) do
					local valid, owned = pcall(authority, E, key)
					if not valid or not Public(owned) or owned ~= true or not ContextCurrent(receiver) then return false end
				end
				return true
			end
			local function CallReturn(ok, ...)
				if not ok or not ContextCurrent() then error("Wide read context changed") end
				return ...
			end
			local function Call(fn, ...)
				if not ContextCurrent() then error("Wide read context changed") end
				return CallReturn(pcall(fn, ...))
			end
			local function Method(object, name)
				if not Public(object) or (type(object) ~= "table" and type(object) ~= "userdata") or not BaseCurrent(object)
					or (Same(object, uiRoot) and readSeal and not readSeal(true)) then error("Wide receiver changed") end
				local record = receivers[object]
				local saved = record and record.methods[name]
				if saved and (nativeProof or saved.raw ~= nil or saved.inherited ~= nil) then
					if record.native and not record.native.source(name) then error("Wide native getter changed") end
					return saved.fn, record
				end
				if not ContextCurrent(object) then error("Wide receiver changed") end
				local fn = object[name]
				if not Public(fn) or type(fn) ~= "function" or not ContextCurrent(object) then error("Wide getter changed") end
				if not record then
					local meta = getmetatable(object)
					if not Public(meta) then error("Wide receiver changed") end
					record = { meta = meta, index = type(meta) == "table" and rawget(meta, "__index") or nil, methods = {} }
					receivers[object] = record
				end
				if not Same(object, E) then
					if not record.native then record.native = nativeBinding and nativeBinding(object) end
					if not record.native or not record.native.source(name) or not Same(fn, record.native.getters[name]) then error("Wide native getter unavailable") end
				end
				saved = record.methods[name]
				if saved and not Same(saved.fn, fn) then error("Wide getter replaced") end
				if not saved then
					local direct = type(object) == "table" and rawget(object, name) or nil
					local inherited = type(record.index) == "table" and rawget(record.index, name) or nil
					if (direct ~= nil and not Same(direct, fn)) or (direct == nil and inherited ~= nil and not Same(inherited, fn)) then error("Wide getter changed during lookup") end
					record.methods[name] = { fn = fn, raw = direct, inherited = inherited }
				end
				if not BaseCurrent(object) then error("Wide receiver changed") end
				return fn, record
			end
			local function ReadReturn(object, ok, ...)
				if not ok or not BaseCurrent(object) then error("Wide receiver changed") end
				return ...
			end
			local function QueryRead(object, getter, ...)
				if not BaseCurrent(object) then error("Wide receiver changed") end
				return ReadReturn(object, pcall(getter, object, ...))
			end
			local function Read(object, name, ...)
				local fn, record = Method(object, name)
				local parent = Method(object, "GetParent")
				local actual = QueryRead(object, parent)
				if not Public(actual) or (record.hasParent and not Same(actual, record.parent)) then error("Wide parent changed") end
				record.hasParent, record.parent = true, actual
				if name == "GetParent" then return actual end
				return QueryRead(object, fn, ...)
			end
			authoritySeal, geometryFactory, intrinsicSeal, domain, existingNativeGeometry, nativeBinding = Call(authoritySource)
			if not Public(authoritySeal, geometryFactory, intrinsicSeal, domain) or type(authoritySeal) ~= "function"
				or type(geometryFactory) ~= "function" or type(intrinsicSeal) ~= "function" or type(domain) ~= "function" or type(existingNativeGeometry) ~= "function"
				or type(nativeBinding) ~= "function" or not authoritySeal() then return end
			readSeal = geometryFactory()
			if not Public(readSeal) or type(readSeal) ~= "function" or not readSeal() then return end
			rootScale = Read(uiRoot, "GetEffectiveScale")
			if not LayoutNumber(rootScale, true) then return end
			local function Add(key, frame, owner)
				local mover = movers[key]
				if not Public(frame, mover) or not frame or not mover or not Same(mover.frame, frame)
					or not Same(mover.module, owner) or (passiveTransaction and not domain(key, mover, frame, true)) or not Call(authority, E, key) then return end
				local width, height = Read(mover, "GetSize")
				local scale = Read(mover, "GetEffectiveScale")
				if not LayoutNumber(width, true) or not LayoutNumber(height, true) or not LayoutNumber(scale, true) or not Current() then return end
				local node = { mover = mover, frame = frame, width = width * scale / rootScale, height = height * scale / rootScale, scale = scale / rootScale }
				nodes[key] = node
				if passiveTransaction and (key == CB or key == MAIN) then
					local number = Read(mover, "GetNumPoints")
					if not LayoutNumber(number) or number < 1 or number > 4 or number % 1 ~= 0 then return end
					node.nativePoints = {}
					for i = 1, number do
						local p, relative, rp, x, y = Read(mover, "GetPoint", i)
						if not Public(p, relative, rp, x, y) or type(p) ~= "string" or type(rp) ~= "string" or not LayoutNumber(x) or not LayoutNumber(y) then return end
						local capture, seal = existingNativeGeometry(relative)
						if type(capture) ~= "function" or type(seal) ~= "function" or not seal() then return end
						node.nativePoints[i] = { p, relative, rp, x, y }
					end
				end
				return node
			end
			-- Main's witness is taken before the passive read, so a callback
			-- during that read that moves or resizes Main is seen below.
			local kit = E.CombatKit
			local stack = kit and kit.CooldownStack
			if not Same(cdm, stackOwner) or not Same(stack, stackSource) or not Same(stack.LayoutBounds, publicReadBounds)
				or not Same(stack, boundStack) or not Same(readBounds, boundStackNative) or not Same(cdm, boundStackOwner)
				or not Same(stack.Refresh, refreshStack) then return end
			local read = readBounds
			local snapshot = Call(read)
			if not Table(snapshot) or snapshot.kind ~= "live" or not Table(snapshot.body) or snapshot.body.kind ~= "live"
				or not Public(snapshot.current) or type(snapshot.current) ~= "function" then return end
			local mainCurrent, mainGeometry, mainNative = snapshot.current, snapshot.geometryCurrent, snapshot.nativeCurrent
			if not Public(mainGeometry, mainNative) or type(mainGeometry) ~= "function" or type(mainNative) ~= "function" then return end
			mainSourceSeal = function(full)
				return Same(rawget(E, "CombatKit"), kit) and Table(kit) and Same(rawget(kit, "CooldownStack"), stack) and Table(stack)
					and Same(rawget(stack, "LayoutBounds"), publicReadBounds) and Same(rawget(stack, "Refresh"), refreshStack)
					and Same(read, boundStackNative) and Same(rawget(stack, "LayoutBounds"), publicReadBounds)
					and Table(snapshot) and Same(rawget(snapshot, "current"), mainCurrent)
					and Same(rawget(snapshot, "geometryCurrent"), mainGeometry) and Same(rawget(snapshot, "nativeCurrent"), mainNative) and mainGeometry(full == true)
			end
			if not Call(mainCurrent) or not Current() then return end
			if not Add(CB, bar, "ConsumableBar") or not Table(bars.bars) then return end
			if actionOwner or rawget(bars, "DockSnapshot") ~= nil then
				if not Same(actionOwner, bars) or not Public(actionRead) or type(actionRead) ~= "function" or actionCount ~= 4 then return end
				local reader = actionRead
				local good, value, custody, native = pcall(reader)
				if not good or not Table(value) or value.kind ~= "live" or not Table(value.nodes) or not Table(value.obstacles)
					or not Public(value.current, custody, native) or type(value.current) ~= "function" or type(custody) ~= "function" or type(native) ~= "function" then return end
				dock, passive, dockCustody, dockCurrent, dockNativeCurrent = value, value.nodes, custody, value.current, native
				for _, index in ipairs({ 1, 2, 3, 5 }) do
					local passiveName = "EldoUI_ActionBar" .. index
					local node = rawget(passive, passiveName)
					if not Table(node) or not Same(node.mover, movers[passiveName]) or not Same(node.frame, rawget(bars.bars, index))
						or not AdaptivePoint(node.point) or not LayoutNumber(node.width, true) or not LayoutNumber(node.height, true)
						or not LayoutNumber(node.scale, true) or not Table(node.rect) then return end
				end
				checks[#checks + 1] = function() return Same(actionOwner, bars) and Same(actionRead, reader)
					and Table(value) and Same(rawget(value, "nodes"), passive) and Same(rawget(value, "current"), dockCurrent) end
				if not Current() then return end
			else
				-- Without a passive geometry provider, every anchor must retain
				-- ordinary mover ownership.
				if not Table(bars.db) or not Table(bars.db.bars[5]) or not Public(bars.db.bars[5].enabled)
					or bars.db.bars[5].enabled ~= true or not Add("EldoUI_ActionBar5", bars.bars[5], "ActionBars") then return end
			end
			for _, key in ipairs({ "player", "target", "focus" }) do
				local frame = uf.frames[key]
				if not Public(frame) or not frame or not Table(frame.db) or not Public(frame.db.enabled)
					or frame.db.enabled ~= true or not Add("EldoUI_" .. key:sub(1, 1):upper() .. key:sub(2), frame, "UnitFrames") then return end
			end
			local main = movers[MAIN]
			if not Public(main) or not main or not Same(snapshot.body.anchor, main) or not Call(authority, E, MAIN) then return end
			if not Add(MAIN, main.frame, "CooldownManager") then return end
			local resolve = Call(Method(E, "LayoutRectangles"), E, function(key)
				local obstacle = rawget(passive, key)
				if obstacle then return obstacle.point, obstacle.width, obstacle.height, obstacle.parent, obstacle.root, obstacle.scale end
				local node = nodes[key]
				if not node then return end
				local point = Call(scalePoint, E, Call(choosePoint, layout, key, ratio), ratio)
				if not AdaptivePoint(point) or type(point.link) ~= "nil" then return end
				local parent = point[2]:match("^(EldoUI_.+)Mover$")
				if point[2] ~= "UIParent" and not parent then return end
				local rootRect
				if not parent then
					local relative = rawget(E, "GetMoverAnchor") and Call(Method(E, "GetMoverAnchor"), E, point[3]) or uiRoot
					if passiveTransaction then local capture, seal = existingNativeGeometry(relative);if type(capture) ~= "function" or type(seal) ~= "function" or not seal() then return end end
					local l, b, w, h = Read(relative, "GetRect")
					local scale = Read(relative, "GetEffectiveScale")
					if not LayoutNumber(l) or not LayoutNumber(b) or not LayoutNumber(w, true) or not LayoutNumber(h, true)
						or not LayoutNumber(scale, true) or not Current() then return end
					local r = scale / rootScale;rootRect = { l * r, b * r, (l + w) * r, (b + h) * r }
				end
				return point, node.width, node.height, parent, rootRect, node.scale
			end)
			local player, target, focus, base = Call(resolve, "EldoUI_Player"), Call(resolve, "EldoUI_Target"), Call(resolve, "EldoUI_Focus"), Call(resolve, CB)
			local mainRect = Call(resolve, MAIN)
			if not player or not target or not focus or not base or not mainRect or not Current() or not Call(mainCurrent) then return end
			local passiveRects = {}
			for passiveName in pairs(passive) do
				local rect = Call(resolve, passiveName)
				if not rect or passiveName == CB or passiveName == MAIN then return end
				passiveRects[passiveName] = rect
			end
			local point = Call(scalePoint, E, Call(choosePoint, layout, CB, ratio), ratio)
			local cbNode = nodes[CB]
			local gap = point[5] * cbNode.scale
			if not LayoutNumber(gap) or gap < 0 then return end
			local chosen, subject = point, base
			if vertical or cbNode.width > target[1] - player[3] - 2 * gap then
				local peer, peerName, peerPoint
				if vertical then peer, peerName, peerPoint = target, "EldoUI_TargetMover", "BOTTOMRIGHT"
				else peer, peerName, peerPoint = focus, "EldoUI_FocusMover", "TOPRIGHT" end
				chosen = { "BOTTOMLEFT", peerName, peerPoint, gap / cbNode.scale, gap / cbNode.scale }
				local b = (vertical and peer[2] or peer[4]) + gap
				subject = { peer[3] + gap, b, peer[3] + gap + cbNode.width, b + cbNode.height }
			end
			local body, minBottom = snapshot.body.rect, snapshot.body.rect.b
			for _, part in ipairs(snapshot.body.parts) do minBottom = math.min(minBottom, part.b) end
			local mainLeft, mainBottom, mainWidth, mainHeight = Read(main, "GetRect")
			local mainScaleValue = Read(main, "GetEffectiveScale")
			if not LayoutNumber(mainLeft) or not LayoutNumber(mainBottom) or not LayoutNumber(mainWidth, true) or not LayoutNumber(mainHeight, true) or not LayoutNumber(mainScaleValue, true) then return end
			local anchorBottom = mainBottom * mainScaleValue / rootScale
			for _, box in ipairs(snapshot.boxes) do
				if not Table(box) or not LayoutNumber(box.b) then return end
				minBottom = math.min(minBottom, box.b)
			end
			local depth = math.max(0, anchorBottom - minBottom)
			local adjusted = Call(scalePoint, E, Call(choosePoint, layout, MAIN, ratio), ratio)
			local required = mainRect[2]
			local cohort, peers = { [snapshot.body.frame] = true }, {}
			if dock then
				for _, obstacle in ipairs(dock.obstacles) do
					if not Table(obstacle) or not Public(obstacle.owner) or type(obstacle.owner) ~= "string"
						or not Table(obstacle.rect) then return end
					local node, projected = rawget(passive, obstacle.owner), rawget(passiveRects, obstacle.owner)
					if not node or not projected then return end
					local box = {}
					for i = 1, 4 do
						if not LayoutNumber(obstacle.rect[i]) or not LayoutNumber(node.rect[i]) then return end
						box[i] = obstacle.rect[i] + projected[i <= 2 and i or i - 2] - node.rect[i <= 2 and i or i - 2]
					end
					peers[#peers + 1] = box
				end
			end
			for _, box in ipairs(snapshot.boxes) do cohort[box.frame] = true end
			for _, part in ipairs(snapshot.body.parts) do cohort[part.frame] = true end
			local function Peer(frame, capacity)
				if not Public(frame) or not frame then return false end
				if cohort[frame] then return true end
				local rect, getScale, shown = Method(frame, "GetRect"), Method(frame, "GetEffectiveScale"), Method(frame, "IsShown")
				if not Public(rect, getScale, shown) or type(rect) ~= "function" or type(getScale) ~= "function" or type(shown) ~= "function" then return false end
				local on = Read(frame, "IsShown")
				if not Public(on) or type(on) ~= "boolean" or not Current() or not Call(mainCurrent) then return false end
				if not on and not capacity then return true end
				local l, b, w, h = Read(frame, "GetRect")
				local scale = Read(frame, "GetEffectiveScale")
				if not LayoutNumber(l) or not LayoutNumber(b) or not LayoutNumber(w, true) or not LayoutNumber(h, true)
					or not LayoutNumber(scale, true) or not MethodsCurrent(frame) or not Current() or not Call(mainCurrent) then return false end
				local r = scale / rootScale
				peers[#peers + 1] = { l * r, b * r, (l + w) * r, (b + h) * r }
				return true
			end
			for i = 1, 8 do
				local cfg = bars.db.bars[i]
				if not Table(cfg) or not Public(cfg.enabled) then return end
				if cfg.enabled == true and not Peer(bars.bars[i]) then return end
			end
			for _, frame in pairs(uf.frames) do
				if not Public(frame) or not frame or not Table(frame.db) or not Public(frame.db.enabled) then return end
				if frame.db.enabled == true then
					if not Peer(frame, true) then return end
					local castbar = frame.castbar
					if not Public(castbar) then return end
					if castbar then
						if not Public(castbar.enabled) then return end
						if castbar.enabled == true and not cohort[castbar] then
							if not Peer(castbar, true) or not Peer(castbar.iconFrame) then return end
						end
					end
				end
			end
			local power = modules.ClassPower
			if not Public(power) then return end
			if power and (not Public(power.active) or type(power.active) ~= "boolean") then return end
			if power and power.active == true then
				local powerDB, container, holder, extras = power.db, power.container, power.holder, power.extraBars
				if not Table(powerDB) or not Table(extras) or not Table(powerDB.bars) then return end
				local configs = powerDB.bars
				checks[#checks + 1] = function() return Same(rawget(modules, "ClassPower"), power) and Same(power.db, powerDB)
					and Same(power.container, container) and Same(power.holder, holder) and Same(power.extraBars, extras)
					and Same(power.active, true) and Table(powerDB) and Same(rawget(powerDB, "bars"), configs) and Table(configs) end
				if not Same(powerRowOwner, power) or not Public(powerRowRead) or type(powerRowRead) ~= "function"
					or not LayoutNumber(powerRowCount, true) or powerRowCount % 1 ~= 0 then return end
				local readInventory, inventoryCount = powerRowRead, powerRowCount
				local inventoryKind, inventory, inventoryCurrent = Call(readInventory, "frames")
				if not Current() or not Public(inventoryKind, inventoryCurrent) or inventoryKind ~= "live" or not Table(inventory)
					or type(inventoryCurrent) ~= "function" or not Same(rawget(inventory, "count"), inventoryCount)
					or not Table(rawget(inventory, "frames")) then return end
				for key in pairs(inventory) do if not Public(key) or (key ~= "count" and key ~= "frames") then return end end
				local inventoryFrames, expectedFrames, seenFrames = rawget(inventory, "frames"), {}, {}
				local function Dense(list)
					if not Table(list) then return false end
					local size = 0
					for key in pairs(list) do
						if not LayoutNumber(key, true) or key % 1 ~= 0 or key > inventoryCount then return false end
						size = size + 1
					end
					return size == inventoryCount
				end
				if not Dense(inventoryFrames) or not Dense(extras) then return end
				for i = 1, inventoryCount do
					local frame = rawget(inventoryFrames, i)
					if not Public(frame) or (type(frame) ~= "table" and type(frame) ~= "userdata")
						or seenFrames[frame] or not Same(rawget(extras, i), frame) then return end
					seenFrames[frame], expectedFrames[i] = true, frame
				end
				checks[#checks + 1] = function()
					if not Same(powerRowOwner, power) or not Same(powerRowRead, readInventory) or not Same(powerRowCount, inventoryCount)
						or not Dense(extras) then return false end
					for i = 1, inventoryCount do if not Same(rawget(extras, i), expectedFrames[i]) then return false end end
					return inventoryCurrent()
				end
				local function Point(frame, expected, parent, expectedRatio)
					if not Public(frame) or (type(frame) ~= "table" and type(frame) ~= "userdata") then return false end
					local meta = getmetatable(frame)
					if not Public(meta) then return false end
					for _, name in ipairs({ "GetParent", "GetNumPoints", "GetPoint", "GetEffectiveScale", "IsShown" }) do
						local fn = Method(frame, name)
						if not Public(fn) or type(fn) ~= "function" or not Current() then return false end
					end
					local function DataCurrent()
						if not Same(getmetatable(frame), meta) then return false end
						if not MethodsCurrent(frame) then return false end
						return true
					end
					checks[#checks + 1] = DataCurrent
					local savedScale
					local function Verify()
						local function PointRead(name, ...)
							if not Current() then error("Follower context changed") end
							local out = { pcall(Read, frame, name, ...) }
							if not out[1] or not Current() then error("Follower read failed") end
							return unpack(out, 2)
						end
						local actualParent, scale, number = PointRead("GetParent"), PointRead("GetEffectiveScale"), PointRead("GetNumPoints")
						if not Same(actualParent, parent) or not LayoutNumber(scale, true) or not Same(number, 1) then return false end
						if expectedRatio and not Same(scale / rootScale, expectedRatio) then return false end
						if savedScale and not Same(scale, savedScale) then return false end
						savedScale = scale
						local actualPoint = { PointRead("GetPoint", 1) }
						for i = 1, 5 do if not Same(actualPoint[i], expected[i]) then return false end end
						return true
					end
					if not Verify() then return false end
					pointChecks[#pointChecks + 1] = Verify
					return true
				end
				local following = false
				if Same(rawget(powerDB, "attachTo"), "MOVER") then
					local owned = Call(authority, E, "EldoUI_PlayerPower")
					if not Public(owned) or type(owned) ~= "boolean" or not Current() then return end
					if owned then
						local points, narrow, wide = layout.points, layout.narrowPoints, layout.widePoints
						if not Table(points) or (type(narrow) ~= "nil" and not Table(narrow)) or (type(wide) ~= "nil" and not Table(wide)) then return end
						checks[#checks + 1] = function() return Same(layout.points, points) and Same(layout.narrowPoints, narrow) and Same(layout.widePoints, wide) end
						checks[#checks + 1] = Record(function() return rawget(points, "EldoUI_PlayerPower") end)
						checks[#checks + 1] = Record(function() return narrow and rawget(narrow, "EldoUI_PlayerPower") end)
						checks[#checks + 1] = Record(function() return wide and rawget(wide, "EldoUI_PlayerPower") end)
						checks[#checks + 1] = Record(function() return spotRules.EldoUI_PlayerPower end)
						if not Current() then return end
						local chosenPoint = Call(choosePoint, layout, "EldoUI_PlayerPower", ratio)
						if not Current() or not AdaptivePoint(chosenPoint) then return end
						local selected = Call(scalePoint, E, chosenPoint, ratio)
						if not Current() or not Table(selected) or not AdaptivePoint(selected) or type(rawget(selected, "link")) ~= "nil" then return end
						if selected[2] == MAIN .. "Mover" then
							local mover = movers.EldoUI_PlayerPower
							if not Public(mover, holder, container) or not mover or not holder or not container
								or not Same(mover.frame, holder) or not Same(mover.module, "ClassPower") then return end
							checks[#checks + 1] = function() return Same(rawget(movers, "EldoUI_PlayerPower"), mover)
								and Same(mover.frame, holder) and Same(mover.module, "ClassPower") end
							local expected = { selected[1], main, selected[3], selected[4], selected[5] }
							if not Point(mover, expected, uiRoot) or not Point(holder, { "CENTER", mover, "CENTER", 0, 0 }, uiRoot)
								or not Point(container, { "CENTER", holder, "CENTER", 0, 0 }, holder) then return end
							following = true
						end
					end
				end
				if Same(rawget(powerDB, "attachTo"), "COOLDOWNS") then
					-- Membership alone does not prove a child follows Main. Match
					-- the exact registered power entry and its measured container,
					-- then admit the source attachment before using row leases.
					local entries, boxes = snapshot.entries, snapshot.boxes
					if not Table(entries) or not Table(boxes) then return end
					local entry, box
					local function Selected(list, selectedKey)
						local found, size = nil, 0
						for index, value in pairs(list) do
							if not LayoutNumber(index, true) or index % 1 ~= 0 or not Table(value) then return end
							size = size + 1
							if Same(rawget(value, "key"), selectedKey) then if found then return end;found = value end
						end
						for index = 1, size do if not Table(rawget(list, index)) then return end end
						return found
					end
					entry, box = Selected(entries, "power"), Selected(boxes, "power")
					if not entry or not box or not Same(entry.frame, container) or not Same(box.frame, container)
						or not Same(entry.box, box) or not Same(entry.side, "ABOVE") or not Same(box.side, "ABOVE")
						or not LayoutNumber(entry.offset) or entry.offset < 0 or not LayoutNumber(box.ratio, true)
						or not Table(entry.spec) or not Public(entry.spec.frame) or type(entry.spec.frame) ~= "function" then return end
					local offset, member, memberRatio = entry.offset, entry.spec, box.ratio
					local memberFrame = member.frame
					local mainParent, mainScale, rootScaleRead = Method(main, "GetParent"), Method(main, "GetEffectiveScale"), Method(uiRoot, "GetEffectiveScale")
					if not Public(mainParent, mainScale, rootScaleRead) or type(mainParent) ~= "function"
						or type(mainScale) ~= "function" or type(rootScaleRead) ~= "function" then return end
					checks[#checks + 1] = function()
						return Same(snapshot.entries, entries) and Same(snapshot.boxes, boxes)
							and Same(Selected(entries, "power"), entry) and Same(Selected(boxes, "power"), box)
							and Same(entry.frame, container) and Same(box.frame, container) and Same(entry.box, box)
							and Same(entry.side, "ABOVE") and Same(box.side, "ABOVE") and Same(entry.offset, offset)
							and Same(box.ratio, memberRatio) and Same(entry.spec, member) and Same(member.frame, memberFrame)
							and MethodsCurrent(main) and MethodsCurrent(uiRoot)
					end
					local function AnchorCurrent()
						if not Current() then return false end
						local parent = Read(main, "GetParent")
						if not Same(parent, uiRoot) or not Current() then return false end
						local currentScale = Read(main, "GetEffectiveScale")
						if not Same(currentScale, mainScaleValue) or not Current() then return false end
						local currentRootScale = Read(uiRoot, "GetEffectiveScale")
						return Same(currentRootScale, rootScale) and Current()
					end
					if not AnchorCurrent() then return end
					pointChecks[#pointChecks + 1] = AnchorCurrent
					if not Public(holder) or not holder or not Point(container, { "BOTTOM", main, "TOP", 0, 6 + offset }, holder, memberRatio) then return end
					following = true
				end
				if not following and not Peer(container) then return end
				for index = 1, inventoryCount do
					local frame = expectedFrames[index]
					local cfg = rawget(configs, "bar" .. index)
					if not Table(cfg) or not Public(frame) or not frame or not Same(frame.cfg, cfg) then return end
					local function ExtraCurrent() return Same(rawget(extras, index), frame) and Same(rawget(configs, "bar" .. index), cfg) and Same(frame.cfg, cfg) end
					checks[#checks + 1] = ExtraCurrent
					local place = rawget(cfg, "place")
					if not Public(place) or (place ~= "STACK" and place ~= "MOVER") then return end
					if following and place == "STACK" then
						local shown = Read(frame, "IsShown")
						if not Public(shown) or type(shown) ~= "boolean" or not Current() then return end
						if shown then
							if not Same(powerRowOwner, power) or not Public(powerRowRead) or type(powerRowRead) ~= "function" then return end
							local readRow = powerRowRead
							local state, rowPoint, check = Call(readRow, index, frame)
							if not Current() or not Same(powerRowRead, readRow) or not Public(state, check) or state ~= "live"
								or not Table(rowPoint) or type(check) ~= "function" then return end
							checks[#checks + 1] = function() return Same(powerRowOwner, power) and Same(powerRowRead, readRow) and check() end
							local expected = { rowPoint[1], rowPoint[2], rowPoint[3], rowPoint[4], rowPoint[5] }
							if not Current() or not Point(frame, expected, container) then return end
						end
					elseif not Peer(frame) then return end
				end
			end
			local micro = modules.MicroMenu
			if not Public(micro) then return end
			if micro and (not Public(micro.active) or type(micro.active) ~= "boolean") then return end
			if micro and micro.active == true then
				if not Peer(micro.microHolder) or not Peer(micro.bagHolder) then return end
			end
			-- Side rows remain attached to their real body. Their lower edge
			-- clears the measured neighboring frames; this is one vertical bound.
			for _, part in ipairs(snapshot.body.parts) do
				local left = mainRect[1] + part.l - mainLeft * mainScaleValue / rootScale
				local right = left + part.r - part.l
				local offset = part.b - anchorBottom
				for _, peer in ipairs(peers) do
					if left < peer[3] and right > peer[1] then required = math.max(required, peer[4] + gap - offset) end
				end
			end
			if count > 0 and not vertical and subject[1] < mainRect[3] + gap and subject[3] > mainRect[1] - gap then
				required = math.max(required, subject[4] + gap + depth)
			end
			local rise = required - mainRect[2]
			adjusted = { adjusted[1], adjusted[2], adjusted[3], adjusted[4], adjusted[5] + rise / nodes[MAIN].scale }
			if passiveTransaction then
				for _, entry in ipairs({ { CB, chosen }, { MAIN, adjusted } }) do
					local node, expected = nodes[entry[1]], entry[2]
					local relative
					if expected[2] == "UIParent" then
						relative = rawget(E, "GetMoverAnchor") and Call(Method(E, "GetMoverAnchor"), E, expected[3]) or uiRoot
					else
						local name = expected[2]:match("^(EldoUI_.+)Mover$")
						local parent = name and (nodes[name] or passive[name])
						relative = parent and parent.mover
					end
					local capture, seal = existingNativeGeometry(relative)
					if type(capture) ~= "function" or type(seal) ~= "function" or not seal() then return end
					local delivery = { expected[1], relative, expected[3], expected[4], expected[5] }
					pointChecks[#pointChecks + 1] = function()
						local countNow = Read(node.mover, "GetNumPoints")
						if not LayoutNumber(countNow) or countNow < 1 or countNow > 4 or countNow % 1 ~= 0 then return false end
						local initial, delivered = countNow == #node.nativePoints, countNow == 1
						for i = 1, countNow do
							local now = { Read(node.mover, "GetPoint", i) }
							for k = 1, 5 do
								initial = initial and Same(now[k], node.nativePoints[i] and node.nativePoints[i][k])
								delivered = delivered and Same(now[k], delivery[k])
							end
						end
						return initial or delivered
					end
				end
			end
			local checkingPoints = false
			local function FinalCurrent()
				if checkingPoints then reentered = true; return false end
				if busy and invalidate ~= invalidateRead then if invalidate then invalidate() end;reentered = true;return false end
				local previousBusy, previousInvalidate, previousRead = busy, invalidate, readSeal
				if not readSeal then readSeal = geometryFactory() end
				busy, invalidate, checkingPoints = true, invalidateRead, true
				local good, current = pcall(function()
					if not MethodsCurrent() or not Current() then return false end
					for _, check in ipairs(pointChecks) do if not check() then return false end end
					if not Current() or not Call(mainCurrent) then return false end
					if dock and not dockCurrent() then return false end
					nativeProof = true
					for _, check in ipairs(pointChecks) do if not check() then return false end end
					if not mainNative() or (dockNativeCurrent and not dockNativeCurrent()) then return false end
					nativeProof = nil
					-- The final source seal performs no authority or geometry query.
					local sealed, current = true, true
					if dockCustody then sealed, current = pcall(dockCustody, nil, true) end
					return sealed and Same(current, true) and MethodsCurrent() and BaseCurrent() and SourceSealed(true)
				end)
				busy, invalidate, checkingPoints, readSeal, nativeProof = previousBusy, previousInvalidate, false, previousRead, nil
				return good and current == true and not reentered
			end
			local signature = { tostring(cbNode.width), tostring(cbNode.height), tostring(vertical), tostring(count), tostring(ratio), tostring(depth), tostring(required) }
			for _, entry in ipairs(snapshot.entries) do
				if entry.box then signature[#signature + 1] = ("%s:%.17g:%.17g"):format(entry.key, entry.box.height, entry.gap) end
			end
			local text = table.concat(signature, "|")
			if not FinalCurrent() then return end
			readSeal = nil
			return { subject = chosen, main = adjusted, signature = text, current = FinalCurrent,
				stackCurrent = FinalCurrent, cb = cb, cdm = cdm, bar = bar, body = snapshot.body.frame, mainMover = main, mainFrame = nodes[MAIN].frame }
		end)
		busy, invalidate = false, nil
		if ok and not reentered then return result end
	end
	WideConsumablePoint = function(layout, name, point, ratio)
		if name ~= CB and name ~= MAIN then return end
		local state = Shape(layout, ratio)
		if not state then return end
		return name == CB and state.subject or state.main
	end
	function E:RefreshWideConsumableLayout(owner, rowReader, rowCount, publish)
		if not Table(self.modules) or not Public(owner) or type(owner) ~= "table" then return end
		local notice
		local actionNotice = Same(owner, rawget(self.modules, "ActionBars"))
		if actionNotice then
			if not actionRead and Public(rowReader) and type(rowReader) == "function" and Same(rowCount, 4) then
				actionOwner, actionRead, actionCount = owner, rowReader, rowCount
			end
			if not Same(publish, true) or not Same(actionOwner, owner) or not Same(actionRead, rowReader) or not Same(actionCount, rowCount) then return end
			local ok, state = pcall(rowReader, "notice")
			if not ok or not Table(state) or not Public(state.current) or type(state.current) ~= "function"
				or (state.kind ~= "live" and state.kind ~= "inactive") then return end
			local good, current = pcall(state.current)
			if not good or not Same(current, true) then return end
			notice = state.current
		end
		if Same(owner, rawget(self.modules, "ClassPower")) then
			if not powerRowRead and Public(rowReader) and type(rowReader) == "function"
				and LayoutNumber(rowCount, true) and rowCount % 1 == 0 and rowCount <= 16 then powerRowOwner, powerRowRead, powerRowCount = owner, rowReader, rowCount end
			-- Initialization admits metadata only. Actual completed resource
			-- layouts (or a completed disable) publish into the same queue.
			if not Same(publish, true) or not Same(owner, powerRowOwner) or not Same(rowReader, powerRowRead)
				or not Same(rowCount, powerRowCount) then return end
			local ok, kind, _, check = pcall(powerRowRead, "notice")
			if not ok or not Public(kind, check) or type(check) ~= "function"
				or not ((Same(rawget(owner, "active"), true) and kind == "live")
					or (Same(rawget(owner, "active"), false) and kind == "inactive")) then return end
			local valid, current = pcall(check)
			if not valid or not Same(current, true) then return end
			notice = check
		end
		if Same(owner, rawget(self.modules, "CooldownManager")) and not stackSource then
			local kit = self.CombatKit
			if not Public(kit) or type(kit) ~= "table" then return end
			local stack = kit.CooldownStack
			if Public(stack) and type(stack) == "table" and Public(stack.LayoutBounds, stack.Refresh, stack.HasBodySource)
				and type(stack.LayoutBounds) == "function" and type(stack.Refresh) == "function" and type(stack.HasBodySource) == "function" then
				local check = stack.HasBodySource
				local ok, present = pcall(check)
				if ok and Public(present) and present == true and Same(stack.HasBodySource, check)
					and Same(self.CombatKit, kit) and Same(kit.CooldownStack, stack) and Same(boundStack, stack)
					and Same(boundStackOwner, owner) and Same(boundStackPublic, stack.LayoutBounds) then
					stackOwner, stackSource, readBounds, publicReadBounds, refreshStack = owner, stack, boundStackNative, stack.LayoutBounds, stack.Refresh
				end
			end
		end
		-- Constructor identity can arrive before the profile is initialized.
		local root, profile = self.db, self.profileName
		if not Table(root) or not Table(rawget(root, "general")) then return end
		local general = rawget(root, "general")
		local layout = CurrentLayout()
		local ownerKey = Same(owner, rawget(self.modules, "ConsumableBar")) and "ConsumableBar"
			or (Same(owner, rawget(self.modules, "CooldownManager")) and "CooldownManager")
			or (notice and Same(owner, rawget(self.modules, "ClassPower")) and "ClassPower")
			or (notice and actionNotice and "ActionBars")
		if not ownerKey or not Enabled(layout) then return end
		local generation = self:NewApplyGeneration("Layout:WideConsumable")
		if not LayoutNumber(generation) then return end
		local request = { root = root, profile = profile, layout = layout, general = general,
			layoutKey = rawget(general, "layout"), owner = owner, ownerKey = ownerKey, modules = self.modules,
			settings = rawget(owner, "db"), active = rawget(owner, "active"), bar = rawget(owner, "bar"), generation = generation,
			notice = notice, rowReader = notice and (actionNotice and actionRead or powerRowRead),
			rowCount = notice and (actionNotice and actionCount or powerRowCount),
			apply = self.ApplyMover, wide = self.ApplyWidePoints, ratio = self.GetLayoutRatio,
			ooc = self.RunOutOfCombat, isCurrent = self.IsApplyGenerationCurrent }
		if not Public(request.apply, request.wide, request.ratio, request.ooc, request.isCurrent)
			or type(request.apply) ~= "function" or type(request.wide) ~= "function" or type(request.ratio) ~= "function"
			or type(request.ooc) ~= "function" or type(request.isCurrent) ~= "function" then return end
		latestRequest = request
		-- Debounce keeps its FIRST callback. The callback reads the latest
		-- request at dispatch, including notifications received during combat.
		self:Debounce("Layout:WideConsumable", 0, function()
			local pending = latestRequest
			if not pending then return end
			local function Current(candidate)
				local checked = candidate or pending
				local ok, current = pcall(function()
					return Same(latestRequest, checked) and Same(self.db, checked.root) and Table(checked.root)
						and Same(rawget(checked.root, "general"), checked.general) and Table(checked.general)
						and Same(rawget(checked.general, "layout"), checked.layoutKey) and Same(CurrentLayout(), checked.layout)
						and Same(self.profileName, checked.profile) and Same(self.modules, checked.modules) and Table(checked.modules)
						and Same(rawget(checked.modules, checked.ownerKey), checked.owner)
						and Same(rawget(checked.modules, "CooldownManager"), stackOwner)
						and Same(rawget(checked.owner, "db"), checked.settings) and Same(rawget(checked.owner, "active"), checked.active)
						and Same(rawget(checked.owner, "bar"), checked.bar)
						and Same(self.ApplyMover, checked.apply) and Same(self.ApplyWidePoints, checked.wide) and Same(self.GetLayoutRatio, checked.ratio)
						and Same(self.IsApplyGenerationCurrent, checked.isCurrent) and Same(self.RunOutOfCombat, checked.ooc)
						and checked.isCurrent(self, checked.generation, "Layout:WideConsumable")
						and (not checked.notice or (((Same(powerRowOwner, checked.owner) and Same(powerRowRead, checked.rowReader)
							and Same(powerRowCount, checked.rowCount)) or (Same(actionOwner, checked.owner) and Same(actionRead, checked.rowReader)
							and Same(actionCount, checked.rowCount))) and checked.notice()))
				end)
				return ok and Public(current) and current == true
			end
			local function Release() if Same(latestRequest, pending) then latestRequest = nil end end
			if not Current() then Release(); return end
			pending.ooc(self, function()
				if not Current() then Release(); return end
				local kit = self.CombatKit
				if not Public(kit) or type(kit) ~= "table" then Release(); return end
				local stack = kit.CooldownStack
				if not stackSource or not Same(stack, stackSource) or not Same(stack.Refresh, refreshStack) or not Same(stack.LayoutBounds, publicReadBounds)
					or not Same(readBounds, boundStackNative) then Release(); return end
				refreshStack()
				if not Current() then Release(); return end
				local cb = rawget(pending.modules, "ConsumableBar")
				if Public(cb) and type(cb) == "table" and Public(rawget(cb, "active"))
					and (rawget(cb, "active") == false or (pending.ownerKey == "ActionBars" and Same(rawget(pending.owner, "active"), false))) then
					local previous = lastContext
					lastShape, lastContext = nil, nil
					local function RestoreMain()
						if previous and Same(previous[1], pending.root) and Same(previous[2], rawget(cb, "bar")) then
							local movers, authority = self.movers, self.LayoutClusterOwnsMover
							local main = Table(movers) and rawget(movers, MAIN)
							local ok, snapshot = pcall(readBounds)
							local function RawCurrent()
								return Same(self.movers, movers) and Table(movers) and Same(rawget(movers, MAIN), previous[4])
									and Public(main) and main and Same(main, previous[4]) and Same(main.frame, previous[5])
									and Same(main.module, "CooldownManager") and Same(self.LayoutClusterOwnsMover, authority)
							end
							if not ok or not Table(snapshot) or snapshot.kind ~= "live" or not Table(snapshot.body)
								or snapshot.body.kind ~= "live" or not Same(snapshot.body.frame, previous[3])
								or not Same(snapshot.body.anchor, main) or not Public(snapshot.current, authority)
								or type(snapshot.current) ~= "function" or type(authority) ~= "function"
								or not Current() or not RawCurrent() then return end
							local valid, owned = pcall(authority, self, MAIN)
							if not valid or not Public(owned) or type(owned) ~= "boolean"
								or not Current() or not snapshot.current() or not RawCurrent() then return end
							if owned then
								pending.apply(self, MAIN)
								if not Current() or not snapshot.current() or not RawCurrent() then return end
							end
						end
					end
					RestoreMain()
					-- The wide points have their own layout route, so they apply even
					-- when the main points were left alone above.
					if not Current() then Release(); return end
					pending.wide(self)
					Release()
					return
				end
				local state = Shape(pending.layout, pending.ratio(self, pending.layout))
				if not state or not Current() or not state.current() or not state.stackCurrent() then Release(); return end
				local same = lastContext and Same(lastContext[1], pending.root) and Same(lastContext[2], state.bar) and Same(lastContext[3], state.body)
				if same and lastShape == state.signature then Release(); return end
				local function EqualFresh(candidate, delivered)
					if not candidate or candidate.ownerKey ~= "ClassPower" or not Same(candidate.root, pending.root)
						or not Same(candidate.profile, pending.profile) or not Same(candidate.general, pending.general)
						or not Same(candidate.layout, pending.layout) or not Same(candidate.modules, pending.modules)
						or not Same(candidate.apply, pending.apply) or not Same(candidate.wide, pending.wide)
						or not Same(candidate.ratio, pending.ratio) or not Current(candidate) then return end
					local fresh = Shape(candidate.layout, candidate.ratio(self, candidate.layout))
					if fresh and Current(candidate) and fresh.signature == delivered.signature
						and Same(fresh.bar, delivered.bar) and Same(fresh.body, delivered.body)
						and fresh.current() and fresh.stackCurrent() and Current(candidate) then return fresh end
				end
				pending.apply(self, CB)
				if not Current() or not state.current() or not state.stackCurrent() then Release(); return end
				pending.apply(self, MAIN)
				-- Main can finish an unchanged resource layout while it moves.
				-- Continue only through that new request's freshly admitted shape;
				-- its lease never makes the superseded request current again.
				local delivery, delivered = pending, state
				if not Current() or not state.current() or not state.stackCurrent() then
					delivery = latestRequest
					delivered = EqualFresh(delivery, state)
					if not delivered then Release(); return end
				end
				if not Current(delivery) or not delivered.current() or not delivered.stackCurrent() then Release(); return end
				delivery.wide(self)
				if Current(delivery) and delivered.current() and delivered.stackCurrent() then
					lastShape, lastContext = delivered.signature, { delivery.root, delivered.bar, delivered.body, delivered.mainMover, delivered.mainFrame }
				else
					-- Leave a newer request pending; cache delivery only against its
					-- same-context, same-geometry current source.
					local newer = latestRequest
					local fresh = EqualFresh(newer, delivered)
					if fresh then lastShape, lastContext = fresh.signature, { newer.root, fresh.bar, fresh.body, fresh.mainMover, fresh.mainFrame } end
				end
				Release()
			end, "Layout:WideConsumable", { generation = pending.generation, lane = "Layout:WideConsumable" })
		end)
	end
end

function E:GetLayoutPoint(name)
	local layout = CurrentLayout()
	local ratio = self:GetLayoutRatio(layout)
	local point = self:ScaleLayoutPoint(PointFor(layout, name, ratio), ratio)
	if point and (name == CLUSTER_ARROW or name == CLUSTER_COORDS) then
		local ok, moved = pcall(self.LayoutMinimapCluster, self, layout, name, point, ratio)
		if ok and moved then return moved end
	end
	local ok, adjusted = pcall(WideConsumablePoint, layout, name, point, ratio)
	if ok and adjusted then return adjusted end
	return point
end

-- Layout settings are merged into a module's settings: a nested table (one
-- action bar, one unit) keeps the keys the layout doesn't name, a list
-- (datatext slots, E.IsList) is replaced as a whole.
local function MergeSettings(target, source)
	for key, value in pairs(source) do
		if type(value) ~= "table" then
			target[key] = value
		elseif E.IsList(value) then
			target[key] = CopyTable(value)
		else
			if type(target[key]) ~= "table" then target[key] = {} end
			MergeSettings(target[key], value)
		end
	end
end
E.MergeLayoutSettings = MergeSettings

local function SameValue(a, b)
	if type(a) ~= "table" or type(b) ~= "table" then return a == b end
	for key, value in pairs(a) do
		if not SameValue(value, b[key]) then return false end
	end
	for key in pairs(b) do
		if a[key] == nil then return false end
	end
	return true
end

-- Undo what the previous preset set and the next one leaves out: such a key
-- goes back to the module default, but only while it still holds the
-- previous preset's value, so a style or the player's own change since
-- stays. Without this a preset applied after another kept the other's
-- settings (target details on plates, bar shapes, Info Bar texts).
local function UnsetSettings(target, previous, upcoming, defaults)
	for key, value in pairs(previous) do
		local nextValue, default
		if type(upcoming) == "table" then nextValue = upcoming[key] end
		if type(defaults) == "table" then default = defaults[key] end
		if type(value) ~= "table" or E.IsList(value) then
			if nextValue == nil and SameValue(target[key], value) then
				target[key] = type(default) == "table" and CopyTable(default) or default
			end
		elseif type(target[key]) == "table" and (nextValue == nil or type(nextValue) == "table") then
			UnsetSettings(target[key], value, nextValue, default)
		end
	end
end

-- The module and settings table that switch a mover on and off, from the
-- mover's enabledPath (Core/Movers.lua). Returns the table, the key in it
-- and the module, or nil when the mover can't be switched.
function E:GetMoverSwitch(name)
	local mover = self.movers[name]
	local path = mover and mover.enabledPath
	local module = mover and mover.module and self.modules[mover.module]
	if not (path and module and type(module.db) == "table") then return end
	local settings = module.db
	for index = 1, #path - 1 do
		settings = settings[path[index]]
		if type(settings) ~= "table" then return end
	end
	return settings, path[#path], module
end

-- "Layout applied" listeners: fn(key, layout, silent) runs after a preset
-- is applied and every mover is in place, e.g. to send boss-mod anchors
-- (BigWigs, DBM) the new spots. `silent` is true for installer previews.
local layoutCallbacks = {}

function E:RegisterLayoutCallback(fn)
	assert(type(fn) == "function", "EldoUI:RegisterLayoutCallback(fn)")
	table.insert(layoutCallbacks, fn)
end

local function Refresh(module)
	if module.active and module.OnProfileChanged then
		local ok, err = pcall(module.OnProfileChanged, module)
		if not ok then geterrorhandler()(err) end
	end
end

-- A mover the current preset keeps off was just made (its module was
-- turned on after the preset was applied): switch the frame off now, as
-- the preset would have. Called by E:CreateMover a frame later.
function E:ApplyPendingLayoutHidden(name)
	local general = self.db.general
	local key = general.layoutPending[name]
	if not key then return end
	if key ~= general.layout then
		general.layoutPending[name] = nil
		return
	end
	self:RunOutOfCombat(function()
		if general.layoutPending[name] ~= general.layout then return end
		local settings, field, module = self:GetMoverSwitch(name)
		if not settings then return end
		general.layoutPending[name] = nil
		if settings[field] then
			settings[field] = false
			general.layoutHidden[name] = true
			Refresh(module)
			self:RefreshMovers()
		end
	end)
end

-- The geometry of a layout: switch preset, set the preset's module settings
-- and move every frame into place. Every route that changes the setup goes
-- through E:ApplySetup below, which calls this as its first part. Called on
-- its own (plugins), it also drops dragged positions and lets a skin that
-- follows the layout follow it, as it always did. `silent` skips the chat
-- line. opts.keepPositions keeps the frames the player dragged where they
-- are; opts.setup marks the call from E:ApplySetup (the look is its own part
-- there, so the skin is left to it).
function E:ApplyLayout(key, silent, opts)
	local layout = self.layouts[key]
	if not layout then return false end
	if InCombatLockdown() then
		if not silent then self:ConfigNotice(L["Layouts can't be changed in combat."], true) end
		return false
	end
	opts = type(opts) == "table" and opts or {}
	local previous = self.layouts[self.db.general.layout]
	self.db.general.layout = key
	local accentChanged = self:SetLayoutAccent(layout.accent)
	self:UpdateAccent()
	if not opts.keepPositions then wipe(self.db.movers) end
	local touched = {}
	-- Frames the previous preset switched off come back first.
	local hidden = self.db.general.layoutHidden
	for name in pairs(hidden) do
		local settings, field, module = self:GetMoverSwitch(name)
		if settings then
			if settings[field] == false then
				settings[field] = true
				touched[module] = true
			end
			hidden[name] = nil
		end
	end
	if previous and previous ~= layout then
		local nextModules = layout.modules or {}
		for moduleName, values in pairs(previous.modules or {}) do
			local module = self.modules[moduleName]
			if module and type(module.db) == "table" then
				UnsetSettings(module.db, values, nextModules[moduleName], module.defaults)
				touched[module] = true
			end
		end
	end
	for moduleName, values in pairs(layout.modules or {}) do
		local module = self.modules[moduleName]
		if module and type(module.db) == "table" then
			MergeSettings(module.db, values)
			touched[module] = true
		end
	end
	-- Then the frames this preset keeps off (placed, so they appear in a free
	-- spot when the player switches them on). A frame whose module is off
	-- has no mover yet: it is switched off when the mover is made
	-- (E:ApplyPendingLayoutHidden), so turning the module on later doesn't
	-- bring back a frame the layout keeps off.
	local pending = self.db.general.layoutPending
	wipe(pending)
	for _, name in ipairs(layout.hidden or {}) do
		local settings, field, module = self:GetMoverSwitch(name)
		if settings and settings[field] then
			settings[field] = false
			hidden[name] = true
			touched[module] = true
		elseif not settings and not self.movers[name] then
			pending[name] = key
		end
	end
	for module in pairs(touched) do Refresh(module) end
	-- A new accent reaches every line, tab and window, not only these modules.
	if accentChanged then self:RefreshTheme() end
	self:RefreshMovers()
	-- A profile that follows its layout's skin gets the skin this layout was
	-- made for (a repeat changes nothing); a skin the player picked stays.
	if not opts.setup and self.FollowLayoutSkin then self:FollowLayoutSkin(key) end
	if not silent then self:ConfigNotice(L["Layout %s applied."]:format(E:Highlight(layout.title))) end
	for _, fn in ipairs(layoutCallbacks) do
		local ok, err = pcall(fn, key, layout, silent and true or false)
		if not ok then geterrorhandler()(err) end
	end
	return true
end

---------------------------------------------------------------------------
-- The layout catalog: one lookup for every place that names a layout.
--
-- The built-in list is eleven layout families (E.layoutFamilies, in the order
-- the pickers show them). A layout that left the list is a legacy layout
-- (E.legacyLayouts): it keeps every value it had, E.layouts still answers
-- its key, and a profile on it places exactly as before until the player
-- picks another layout. E.layoutAliases names the family each legacy
-- layout is closest to. A family slot without a layout yet stays out of
-- the pickers.
--
--   E:ResolveLayoutKey(key)  the layout key to use for `key` (a layout, a
--                            legacy layout, or an older name kept in
--                            E.layoutAliases), or nil
--   E:LayoutRecord(key)      the layout table and its key, or nil
--   E:AllLayoutKeys()        the families, then the legacy layouts, then
--                            every other layout (imported, plugins)
--   E:LayoutTitle(key)       the title the pickers show
--   E:LayoutFamily(key)      the family a layout belongs to, or is closest to
--   E:LayoutFamilyTitle(key) a family's title (also for an empty slot)
--   E:IsLegacyLayout(key)    true for a legacy layout
--   E:LayoutIdentity(key)    how the setup names the layout a profile uses
--                            ("Legacy: <title> (nearest: <family>)")
--   E:LegacyLayoutsInUse()   { key = true } for the legacy layouts a saved
--                            profile uses
--   E:EffectiveLayout()      the key the frames are placed by and why:
--                            nil, "legacy", "alias" or "missing"
-- Layout data never changes under a key players already use: a re-tuned
-- layout gets a new key, and the old one stays as a legacy layout.
---------------------------------------------------------------------------
E.layoutFamilies = {
	{ key = "EldoVanilla", title = "Vanilla Original", current = "EldoVanilla1000" },
	{ key = "EldoCenter", title = "EldoUI Center", current = "EldoCenter1000" },
	{ key = "EldoModern", title = "Modern Center", current = "EldoModern2000" },
	{ key = "EldoBlizz", title = "Blizzard Bottom Block", current = "EldoBlizz1000" },
	{ key = "EldoHeritage", title = "Portrait Staggered", current = "EldoHeritage2000" },
	{ key = "EldoZen", title = "Compact HUD", current = "EldoZen1000" },
	{ key = "EldoWide", title = "Widescreen Edges", current = "EldoWide1000" },
	{ key = "EldoCozy", title = "Close Combat", current = "EldoCozy1000" },
	{ key = "EldoHunter", title = "Open Center", current = "EldoHunter1000" },
	{ key = "EldoPlates", title = "Nameplate Focus", current = "EldoPlates2000" },
	{ key = "EldoSanctum", title = "Twin Orbs", current = "EldoSanctum2000" },
}
E.legacyLayouts = E.legacyLayouts or {}
E.legacyLayoutOrder = E.legacyLayoutOrder or {}
E.layoutAliases = E.layoutAliases or {}

-- Moves every layout marked retiredIn out of the list into the legacy
-- layouts (E.layouts keeps answering their keys) and puts the families
-- first, in their order. Runs after the built-in layouts are defined; a
-- second run changes nothing.
-- Family IDs stay stable while their current placement gets a new key.
function E:FamilyLayoutKey(family)
	local found, key
	for _, slot in ipairs(self.layoutFamilies) do
		if slot.key == family then
			if found then return nil end
			found, key = slot, type(slot.current) == "nil" and slot.key or slot.current
		end
	end
	if not found or type(key) ~= "string" or (self.IsSecret and self:IsSecret(key)) then return nil end
	for _, slot in ipairs(self.layoutFamilies) do
		local other = type(slot.current) == "nil" and slot.key or slot.current
		if slot ~= found and type(other) == "string" and not (self.IsSecret and self:IsSecret(other)) and other == key then return nil end
	end
	local layout = rawget(self.layouts, key)
	if type(layout) == "table" and not layout.retiredIn and layout.family == family then return key end
end

local function FamilyPlacementKeys(self)
	local keys = {}
	for _, slot in ipairs(self.layoutFamilies) do
		if type(slot.key) == "string" then keys[slot.key] = true end
		if type(slot.current) == "string" and not (self.IsSecret and self:IsSecret(slot.current)) then keys[slot.current] = true end
	end
	-- A rejected native version is not a plugin. Imported snapshots retain
	-- their separate identity even when they carry family placement metadata.
	for key, layout in pairs(self.layouts) do
		if type(layout) == "table" then
			local marker = layout.familyVersion
			if type(marker) == "boolean" and not (self.IsSecret and self:IsSecret(marker))
				and marker and not layout.imported then keys[key] = true end
		end
	end
	return keys
end

function E:BuildLayoutCatalog()
	local layouts = self.layouts
	for _, key in ipairs(self.layoutOrder) do
		local layout = rawget(layouts, key)
		if type(layout) == "table" and layout.retiredIn and not self.legacyLayouts[key] then
			self.legacyLayouts[key] = layout
			self.legacyLayoutOrder[#self.legacyLayoutOrder + 1] = key
		end
	end
	for key, layout in pairs(self.legacyLayouts) do
		rawset(layouts, key, nil)
		if type(layout.family) == "string" and self.layoutAliases[key] == nil then self.layoutAliases[key] = layout.family end
	end
	if getmetatable(layouts) == nil then setmetatable(layouts, { __index = self.legacyLayouts }) end
	local order, seen, familyKeys = {}, {}, FamilyPlacementKeys(self)
	for _, slot in ipairs(self.layoutFamilies) do
		local key = self:FamilyLayoutKey(slot.key)
		if key and not seen[key] then
			order[#order + 1] = key
			seen[key] = true
		end
	end
	for _, key in ipairs(self.layoutOrder) do
		if rawget(layouts, key) and not seen[key] and not familyKeys[key] then
			order[#order + 1] = key
			seen[key] = true
		end
	end
	for index = #self.layoutOrder, 1, -1 do self.layoutOrder[index] = nil end
	for index, key in ipairs(order) do self.layoutOrder[index] = key end
end

function E:ResolveLayoutKey(key)
	if type(key) ~= "string" then return nil end
	if self.layouts[key] then return key end
	local target = self.layoutAliases[key]
	if type(target) == "string" and self.layouts[target] then return target end
	return nil
end

function E:LayoutRecord(key)
	local resolved = self:ResolveLayoutKey(key)
	if not resolved then return nil end
	return self.layouts[resolved], resolved
end

function E:IsLegacyLayout(key)
	return type(key) == "string" and self.legacyLayouts[key] ~= nil
end

function E:AllLayoutKeys()
	local keys, seen, familyKeys = {}, {}, FamilyPlacementKeys(self)
	local function Add(key)
		if not seen[key] and self.layouts[key] then
			keys[#keys + 1] = key
			seen[key] = true
		end
	end
	for _, slot in ipairs(self.layoutFamilies) do
		local key = self:FamilyLayoutKey(slot.key)
		if key then Add(key) end
	end
	for _, key in ipairs(self.legacyLayoutOrder) do Add(key) end
	for _, key in ipairs(self.layoutOrder) do if not familyKeys[key] then Add(key) end end
	return keys
end

function E:LayoutTitle(key)
	local layout, resolved = self:LayoutRecord(key)
	if not layout then return tostring(key or "?") end
	return ((layout.title or resolved):gsub(" %(1440p%)", ""))
end

function E:LayoutFamily(key)
	if type(key) ~= "string" then return nil end
	local layout = self.layouts[key]
	if type(layout) == "table" and type(layout.family) == "string" then return layout.family end
	if type(self.layoutAliases[key]) == "string" then return self.layoutAliases[key] end
	for _, slot in ipairs(self.layoutFamilies) do
		if slot.key == key then return key end
	end
	return nil
end

function E:LayoutFamilyTitle(key)
	for _, slot in ipairs(self.layoutFamilies) do
		if slot.key == key then return L[slot.title] end
	end
	return self:LayoutTitle(key)
end

function E:LayoutIdentity(key)
	if self:IsLegacyLayout(key) then
		local family = self:LayoutFamily(key)
		if family then return L["Legacy: %s (nearest: %s)"]:format(self:LayoutTitle(key), self:LayoutFamilyTitle(family)) end
		return L["Legacy: %s"]:format(self:LayoutTitle(key))
	end
	if not self:ResolveLayoutKey(key) then return L["%s (not installed)"]:format(tostring(key or "?")) end
	return self:LayoutTitle(key)
end

function E:LegacyLayoutsInUse()
	local used = {}
	local profiles = type(EldoUIDB) == "table" and type(EldoUIDB.profiles) == "table" and EldoUIDB.profiles or {}
	for _, profile in pairs(profiles) do
		local key = type(profile) == "table" and type(profile.general) == "table" and profile.general.layout
		if self:IsLegacyLayout(key) then used[key] = true end
	end
	if self.db and self:IsLegacyLayout(self.db.general.layout) then used[self.db.general.layout] = true end
	return used
end

function E:EffectiveLayout()
	local key = self.db and self.db.general.layout
	if type(key) == "string" and self.layouts[key] then
		return key, self:IsLegacyLayout(key) and "legacy" or nil
	end
	local resolved = self:ResolveLayoutKey(key)
	if resolved then return resolved, "alias" end
	return self.defaults.general.layout, "missing"
end

---------------------------------------------------------------------------
-- The catalog update, once per profile ("layouts:catalog" version 2).
-- It never applies a layout and never moves a frame:
--   * the layout key is written into the profile, so a profile that used
--     the default layout keeps it when a later version has another default
--   * a profile on a legacy layout gets general.layoutLegacy = { key,
--     family, version } and stays on it
--   * when that profile had dragged frames, a copy of its screen (the
--     legacy layout's spots with the dragged positions) is added to My
--     layouts, so the player can keep it even after picking a family
-- E.layoutCatalogReport keeps one line per profile for /eui diag.
---------------------------------------------------------------------------
local LEGACY_DEFAULT = "EldoModern" -- the default layout before 0.7.0000
E.layoutCatalogReport = E.layoutCatalogReport or {}

local function ProfileName(profile)
	local profiles = type(EldoUIDB) == "table" and EldoUIDB.profiles
	if type(profiles) ~= "table" then return nil end
	for name, saved in pairs(profiles) do
		if saved == profile then return name end
	end
	return nil
end

-- The copy under My layouts of a legacy screen with dragged frames. Returns
-- its key, or nil when the profile has no drags or is not a saved profile.
local function SaveLegacyCopy(profile, name, key, legacy)
	local movers = profile.movers
	if not name or type(movers) ~= "table" or next(movers) == nil then return nil end
	if type(EldoUIDB.importedLayouts) ~= "table" then EldoUIDB.importedLayouts = {} end
	local store = EldoUIDB.importedLayouts
	for id, saved in pairs(store) do
		if type(saved) == "table" and type(saved.legacy) == "table" and saved.legacy.key == key and saved.legacy.profile == name then return id end
	end
	local points = CopyTable(legacy.points or {})
	for mover, position in pairs(movers) do
		if type(position) == "table" then points[mover] = CopyTable(position) end
	end
	local base = (key .. name):gsub("[^%w]", "")
	local id, index = base, 2
	while store[id] or rawget(E.layouts, "Imported_" .. id) do
		id = base .. index
		index = index + 1
	end
	local title = E:LayoutTitle(key)
	store[id] = {
		title = L["%s (my copy)"]:format(title),
		desc = L["The %s layout with the frames you dragged on profile %s, saved when it became a legacy layout."]:format(title, name),
		accent = legacy.accent,
		points = points,
		modules = type(legacy.modules) == "table" and CopyTable(legacy.modules) or nil,
		hidden = type(legacy.hidden) == "table" and CopyTable(legacy.hidden) or nil,
		source = "legacy",
		legacy = { key = key, profile = name, version = 1 },
	}
	if E.Import and E.Import.RegisterImportedLayouts then E.Import.RegisterImportedLayouts() end
	return id
end

local function CatalogUpdate(profile)
	if type(profile.general) ~= "table" then profile.general = {} end
	local general = profile.general
	if general.layout == nil then general.layout = LEGACY_DEFAULT end
	local key = general.layout
	local name = ProfileName(profile)
	local legacy = type(key) == "string" and E.legacyLayouts[key]
	local line
	if legacy then
		if type(general.layoutLegacy) ~= "table" then
			general.layoutLegacy = { key = key, family = legacy.family, version = 1 }
		end
		local copy = SaveLegacyCopy(profile, name, key, legacy)
		line = ("%s: kept on the legacy layout %s (nearest: %s)%s"):format(tostring(name or "?"), tostring(key),
			tostring(legacy.family), copy and (", copy under My layouts: Imported_" .. copy) or "")
	elseif E:ResolveLayoutKey(key) then
		line = ("%s: kept on %s"):format(tostring(name or "?"), tostring(key))
	else
		line = ("%s: %s is not installed; frames use %s"):format(tostring(name or "?"), tostring(key), tostring(E.defaults.general.layout))
	end
	if name then table.insert(E.layoutCatalogReport, line) end
end
E:RegisterProfileMigration(CatalogUpdate, "layouts:catalog", 2)

---------------------------------------------------------------------------
-- One setup change for every route: the Layouts page, /eui layout, the
-- Overview, a pack, an import and the setup all describe what they want as
-- a plan and hand it to E:ApplySetup, so the same pick ends in the same
-- setup wherever it was made.
--
--   plan = {
--     layout   = a layout key; nil keeps the layout in use
--     look     = "layout": take the layout's look (the skin and the Blizzard
--                windows follow the layout, its suggested styles, its accent)
--                "keep": choices you made stay; parts that follow the layout
--                keep following it; a style the old layout brought that
--                doesn't fit the new one takes the new layout's style
--                nil: "layout" while your skin follows the layout, else "keep"
--     skin, skinVariant, graphics, accent = parts picked by hand (a pack)
--     windows  = a Blizzard windows choice; false keeps it as set; nil
--                follows `look`
--     styles   = { Module = style key } on top of the look's styles
--     role, roleClass, uiAmount
--     resetPositions = true: frames you dragged go back to the layout's
--                spots (the layout in use is applied again too)
--     title    = what the chat line and the Undo alert call the change
--     source   = where the change came from (for plugins)
--     silent   = no chat line and no Undo alert
--     undo     = false: keep no undo record (the setup keeps its own)
--   }
--
--   E:ResolveSetup(plan)     the recipe: every part with its target and
--                            whether it is inherited from the layout or
--                            picked by hand; nil and why when it can't
--   E:SetupChanges(plan)     what applying would change, one line each;
--                            empty when the setup is already in use
--   E:ApplySetup(plan)       applies it: true when done, false and "same"
--                            (nothing to change), "queued" (after combat)
--                            or why it can't
--   E:UndoSetup()            puts back the newest change of this profile
--   E:SetupUndoRecord()      that change's record, or nil
--
-- Applying the setup you already use changes nothing. Frames you dragged
-- stay where you put them unless the plan asks to reset positions. Undo
-- works by value: a setting you changed yourself since stays yours.
--
-- An undo record holds only what the change wrote: on both sides, before
-- and after, the settings, frame positions and module settings whose
-- value changed (inside tables too; a list of plain values is kept
-- whole). The newest three of each profile are saved at logout
-- (EldoUIDB.setupHistory, by profile), so Undo works after a reload or a
-- new login.
---------------------------------------------------------------------------
E.setupHistory = E.setupHistory or {}
local SETUP_HISTORY = 10
-- Saved: the newest records per profile, and all profiles together at
-- most this many bytes as the saved file writes them (oldest go first).
local SAVED_PER_PROFILE = 3
local SAVED_BYTES = 128 * 1024
E.SETUP_HISTORY_SAVED, E.SETUP_HISTORY_BYTES = SAVED_PER_PROFILE, SAVED_BYTES
-- The profile settings a setup change can write (besides positions and
-- module settings). The Blizzard windows choice is put back through its own
-- function, so the windows it painted come back as they were.
local SETUP_GENERAL = {
	"layout", "layoutHidden", "layoutPending", "roleMovers", "accent", "accentFromArt", "artStyle", "skinFollow",
	"skinVariant", "accessBackup", "role", "roleClass", "roleRestore", "uiAmount", "uiAmountRestore",
}

local function CopyValue(value)
	if type(value) == "table" then return CopyTable(value) end
	return value
end

-- What differs between two values: the before and after parts that are
-- not equal, and true; nil, nil, false when they are equal. Tables are
-- compared key by key (a list of bars entry by entry); a list of plain
-- values (a color, a list of names), or a key that is a table on one side
-- only, is kept whole. The values are the record's own copies, so the
-- parts are kept as they are.
local function ValueList(t)
	return t[1] ~= nil and type(t[1]) ~= "table"
end

local function Changed(before, after)
	if E.DeepEqual(before, after) then return nil, nil, false end
	if type(before) ~= "table" or type(after) ~= "table" or ValueList(before) or ValueList(after) then
		return before, after, true
	end
	local keys, b, a = {}, {}, {}
	for key in pairs(before) do keys[key] = true end
	for key in pairs(after) do keys[key] = true end
	for key in pairs(keys) do
		local old, new, differs = Changed(before[key], after[key])
		if differs then b[key], a[key] = old, new end
	end
	return b, a, true
end

-- Put target[key] back to `before` only where it still holds `after`;
-- tables key by key, so a part changed since keeps its value.
local function RestoreByValue(target, key, before, after)
	if type(target) ~= "table" then return end
	local now = target[key]
	if E.DeepEqual(now, after) then
		target[key] = CopyValue(before)
		return
	end
	if type(now) ~= "table" or type(after) ~= "table" then return end
	local keys = {}
	for sub in pairs(after) do keys[sub] = true end
	if type(before) == "table" then
		for sub in pairs(before) do keys[sub] = true end
	end
	for sub in pairs(keys) do
		local old
		if type(before) == "table" then old = before[sub] end
		RestoreByValue(now, sub, old, after[sub])
	end
end

-- The skin in use, also while High contrast keeps it aside.
local function SkinInUse(general)
	local backup = type(general.accessBackup) == "table" and general.accessBackup.contrast
	if general.artStyle == "Contrast" and type(backup) == "table" and backup.artStyle then return backup.artStyle end
	return general.artStyle
end

local function FindStyle(moduleName, key)
	for _, style in ipairs(E.styles and E.styles[moduleName] or {}) do
		if style.key == key and not style.acts then return style end
	end
end

local function ModuleOn(name)
	local module = E.modules[name]
	return module and module.db and module.db.enabled and true or false
end

local function SetupPlain(value)
	return not E.Secret(value) and type(value) == "table" and type(getmetatable(value)) == "nil"
end

local function SetupTarget(self, target)
	local root, profile, name, admit = ReadAccountRoot(), self.db, self.profileName, self.IsCurrentProfile
	local getter, active = self.GetApplyGeneration, self.IsApplyGenerationCurrent
	if not SetupPlain(root) or not SetupPlain(profile) or E.Secret(name) or type(name) ~= "string"
		or E.Secret(admit) or type(admit) ~= "function" or E.Secret(getter) or type(getter) ~= "function"
		or E.Secret(active) or type(active) ~= "function" then return nil end
	local general = rawget(profile, "general")
	if not SetupPlain(general) then return nil end
	if target and (root ~= target.root or profile ~= target.profile or name ~= target.name or general ~= target.general
		or admit ~= target.admit or getter ~= target.getter or active ~= target.active) then return nil end
	local read, generation = pcall(getter, self, "profile")
	if not read or E.Secret(generation) or type(generation) ~= "number" or generation ~= generation
		or generation < 1 or generation >= math.huge or generation % 1 ~= 0 then return nil end
	if target and generation ~= target.generation then return nil end
	local ok, current = pcall(admit, self, profile, name)
	if not ok or E.Secret(current) or current ~= true then return nil end
	local valid, live = pcall(active, self, generation, "profile")
	if not valid or E.Secret(live) or live ~= true or E.Secret(self.IsCurrentProfile) or self.IsCurrentProfile ~= admit
		or E.Secret(self.GetApplyGeneration) or self.GetApplyGeneration ~= getter
		or E.Secret(self.IsApplyGenerationCurrent) or self.IsApplyGenerationCurrent ~= active
		or E.Secret(ReadAccountRoot()) or ReadAccountRoot() ~= root
		or E.Secret(self.db) or self.db ~= profile or E.Secret(self.profileName) or self.profileName ~= name
		or E.Secret(rawget(profile, "general")) or rawget(profile, "general") ~= general then return nil end
	return target or { root = root, profile = profile, name = name, general = general, admit = admit,
		getter = getter, active = active, generation = generation }
end

local function SetupLayout(self, key)
	if E.Secret(key) or type(key) ~= "string" or not SetupPlain(self.layoutFamilies) then return nil end
	local resolve = self.FamilyLayoutKey
	if E.Secret(resolve) or type(resolve) ~= "function" then return nil end
	for _, slot in ipairs(self.layoutFamilies) do
		if not SetupPlain(slot) then return nil end
		local family = rawget(slot, "key")
		if E.Secret(family) or type(family) ~= "string" then return nil end
		local ok, current = pcall(resolve, self, family)
		if not ok or E.Secret(current) then return nil end
		if current == key and not E.Secret(self.FamilyLayoutKey) and self.FamilyLayoutKey == resolve then return key end
	end
	local owner = self.Import
	if not SetupPlain(owner) then return nil end
	local read = rawget(owner, "CurrentLayout")
	if E.Secret(read) or type(read) ~= "function" then return nil end
	local ok, layout = pcall(read, key)
	if ok and SetupPlain(layout) and not E.Secret(self.Import) and self.Import == owner
		and not E.Secret(rawget(owner, "CurrentLayout")) and rawget(owner, "CurrentLayout") == read
		and not E.Secret(rawget(self.layouts, key)) and rawget(self.layouts, key) == layout then return key end
end

local function HistoryData(value, open)
	if E.Secret(value) then return false end
	local kind = type(value)
	if kind == "number" then return value == value and value > -math.huge and value < math.huge end
	if kind ~= "table" then return kind == "nil" or kind == "string" or kind == "boolean" end
	if not SetupPlain(value) or open[value] then return false end
	open[value] = true
	for key, inner in pairs(value) do
		if E.Secret(key) or (type(key) ~= "string" and type(key) ~= "number")
			or not HistoryData(key, open) or not HistoryData(inner, open) then open[value] = nil; return false end
	end
	open[value] = nil
	return true
end

function E:ResolveSetup(plan)
	if not SetupPlain(plan) then return nil, "no plan" end
	local target = SetupTarget(self)
	if not target then return nil, "no profile" end
	for _, field in ipairs({ "layout", "look", "skin", "styles", "source", "title", "silent", "undo", "resetPositions",
		"windows", "accent", "skinVariant", "graphics", "role", "roleClass", "uiAmount" }) do
		if E.Secret(rawget(plan, field)) then return nil, "no plan" end
	end
	local general = self.db.general
	local key = SetupLayout(self, general.layout)
	if not key then return nil, "unknown layout" end
	if plan.layout ~= nil then
		key = SetupLayout(self, plan.layout)
		if not key then return nil, "unknown layout" end
	end
	local layout = self:LayoutRecord(key) or self.layouts[self.defaults.general.layout]
	local look = plan.look
	if look ~= "layout" and look ~= "keep" then look = general.skinFollow and "layout" or "keep" end
	local recipe = {
		source = plan.source, title = plan.title, silent = plan.silent and true or false, undo = plan.undo ~= false,
		layout = key, layoutChanges = key ~= general.layout, reset = plan.resetPositions and true or false,
		look = look, lookAsked = plan.look == "layout" or plan.look == "keep",
		styles = {}, inherited = {}, explicit = {},
	}
	-- Skin: picked by hand, or the layout's while the look follows it.
	if type(plan.skin) == "string" then
		recipe.skin = { value = plan.skin }
		recipe.explicit.skin = true
	elseif look == "layout" then
		recipe.skin = { value = self.LayoutSkin and self:LayoutSkin(key) or general.artStyle, follow = true }
		recipe.inherited.skin = true
	end
	-- Blizzard windows: a choice, kept, or the layout's when its look is asked for.
	if type(plan.windows) == "string" then
		recipe.windows = plan.windows
		recipe.explicit.windows = true
	elseif plan.windows == nil and plan.look == "layout" then
		recipe.windows = "layout"
		recipe.inherited.windows = true
	end
	if type(plan.accent) == "string" then recipe.accent = plan.accent end
	if type(plan.skinVariant) == "string" then recipe.skinVariant = plan.skinVariant end
	if type(plan.graphics) == "string" then recipe.graphics = plan.graphics end
	-- Styles: the layout's suggestions with the look, the plan's own on top;
	-- only styles that exist and fit the layout's spots.
	local function Take(list, inherited)
		for moduleName, styleKey in pairs(type(list) == "table" and list or {}) do
			if not E.Secret(moduleName) and not E.Secret(styleKey) and type(moduleName) == "string" and type(styleKey) == "string" and self.modules[moduleName]
				and FindStyle(moduleName, styleKey) and (not self.StyleFits or self:StyleFits(key, moduleName, styleKey)) then
				recipe.styles[moduleName] = styleKey
				recipe.inherited["style:" .. moduleName] = inherited or nil
			end
		end
	end
	if look == "layout" then Take(layout and layout.suggest, true) end
	-- A style the layout you leave brought with it, and that doesn't fit the
	-- new layout's spots (the orbs of Twin Orbs), goes with that layout: the
	-- new layout's own style takes its place, also when your look stays.
	local leaving = recipe.layoutChanges and self.layouts[general.layout]
	if type(leaving) == "table" and type(leaving.suggest) == "table" and self.StyleFits then
		for moduleName, styleKey in pairs(leaving.suggest) do
			local module = type(moduleName) == "string" and type(styleKey) == "string" and not recipe.styles[moduleName]
				and self.modules[moduleName]
			if module and type(module.db) == "table" and module.db.style == styleKey and not self:StyleFits(key, moduleName, styleKey) then
				Take({ [moduleName] = layout and type(layout.suggest) == "table" and layout.suggest[moduleName] or nil }, true)
			end
		end
	end
	Take(plan.styles, false)
	if plan.role ~= nil and self.roleProfiles and (plan.role == "none" or self.roleProfiles[plan.role]) then
		recipe.role = { value = plan.role, classLayer = plan.roleClass }
	end
	if plan.uiAmount ~= nil and self.UIAmount and self.UIAmount.LEVELS[plan.uiAmount] then recipe.uiAmount = plan.uiAmount end
	if not SetupTarget(self, target) then return nil, "no profile" end
	return recipe
end

local function WindowTitle(mode)
	local W = E.Appearance and E.Appearance.WINDOWS
	return W and W.titles[mode] and L[W.titles[mode]] or tostring(mode)
end

local function SkinTitle(id)
	local info = E.artStyleInfo and E.artStyleInfo[id]
	return info and L[info.title] or tostring(id)
end

-- What a resolved recipe changes, one line per part ({ part, text }).
local function Changes(self, recipe)
	local general = self.db.general
	local list = {}
	local function Add(part, text) list[#list + 1] = { part = part, text = text } end
	if recipe.layoutChanges then
		Add("layout", L["Layout: %s"]:format(self:LayoutTitle(recipe.layout)))
	end
	if recipe.reset and next(self.db.movers or {}) then
		Add("positions", L["Frames you dragged go back to the layout's spots."])
	elseif recipe.reset and not recipe.layoutChanges then
		Add("layout", L["Layout: %s"]:format(self:LayoutTitle(recipe.layout)))
	end
	local skin = recipe.skin
	if skin then
		local differs = SkinInUse(general) ~= skin.value
		if skin.follow and (differs or not general.skinFollow) then
			Add("skin", L["Skin: %s"]:format(L["%s (from the layout)"]:format(SkinTitle(skin.value))))
		elseif not skin.follow and (differs or general.skinFollow) then
			Add("skin", L["Skin: %s"]:format(SkinTitle(skin.value)))
		end
	end
	if recipe.skinVariant and general.skinVariant ~= recipe.skinVariant then
		local values = self.SkinVariants and self:SkinVariants(skin and skin.value or general.artStyle)
		Add("skinVariant", L["Faction look: %s"]:format(values and values[recipe.skinVariant] or recipe.skinVariant))
	end
	if recipe.graphics then
		local units = self.modules.UnitFrames and self.modules.UnitFrames.db
		if units and self.GetPath(units, "allFrames.graphics") ~= recipe.graphics then
			local UG = self.UnitGraphics
			local values = UG and UG.Values and UG:Values(recipe.graphics)
			Add("graphics", L["Unit-frame graphics: %s"]:format(values and values[recipe.graphics] or recipe.graphics))
		end
	end
	if recipe.accent and general.accent ~= recipe.accent then Add("accent", L["Accent color"]) end
	if recipe.windows and self.BlizzardWindowsMode and self:BlizzardWindowsMode() ~= recipe.windows then
		Add("windows", L["Blizzard windows: %s"]:format(WindowTitle(recipe.windows)))
	end
	local parts = {}
	for moduleName, styleKey in pairs(recipe.styles) do
		local module = self.modules[moduleName]
		if module and module.db and module.db.style ~= styleKey then
			parts[#parts + 1] = ("%s %s"):format(L[module.title], L[FindStyle(moduleName, styleKey).title])
		end
	end
	if #parts > 0 then
		table.sort(parts)
		Add("styles", L["Styles: %s"]:format(table.concat(parts, ", ")))
	end
	local role = recipe.role
	if role and (self:GetRole() ~= role.value or (role.classLayer ~= nil and (general.roleClass and true or false) ~= (role.classLayer and true or false))) then
		local profile = self.roleProfiles[role.value]
		Add("role", L["Role: %s"]:format(profile and L[profile.title] or L["No role"]))
	end
	if recipe.uiAmount then
		local count = #self:UIAmountPlan(recipe.uiAmount)
		if count > 0 or general.uiAmount ~= recipe.uiAmount then
			Add("uiAmount", L["UI amount: %s (%s)"]:format(self.UIAmount.Title(recipe.uiAmount),
				E:Plural(count, "switches %d module", "switches %d modules"):format(count)))
		end
	end
	return list
end

function E:SetupChanges(plan)
	local target = SetupTarget(self)
	if not target then return {} end
	local recipe = self:ResolveSetup(plan)
	if not recipe or not SetupTarget(self, target) then return {} end
	local changes = Changes(self, recipe)
	return SetupTarget(self, target) and changes or {}
end

-- The modules a recipe can write to: the old and the new layout's
-- settings and switched-off frames, the styles, the unit graphics and the
-- role layers.
local function TouchedModules(self, recipe)
	local general = self.db.general
	local names = {}
	local function Layout(layout)
		for moduleName in pairs(layout and layout.modules or {}) do names[moduleName] = true end
		for _, mover in ipairs(layout and layout.hidden or {}) do
			local _, _, module = self:GetMoverSwitch(mover)
			if module then names[module.name] = true end
		end
	end
	Layout(self.layouts[general.layout])
	Layout(self.layouts[recipe.layout])
	for mover in pairs(general.layoutHidden or {}) do
		local _, _, module = self:GetMoverSwitch(mover)
		if module then names[module.name] = true end
	end
	for moduleName in pairs(recipe.styles) do names[moduleName] = true end
	if recipe.graphics then names.UnitFrames = true end
	if recipe.role then
		local function Role(key)
			local profile = key and self.roleProfiles and self.roleProfiles[key]
			for moduleName in pairs(profile and profile.settings or {}) do names[moduleName] = true end
		end
		Role(general.role)
		Role(recipe.role.value)
		local layer = self.GetRoleClassLayer and self:GetRoleClassLayer()
		for moduleName in pairs(layer and layer.settings or {}) do names[moduleName] = true end
		for moduleName in pairs(type(general.roleRestore) == "table" and general.roleRestore or {}) do names[moduleName] = true end
	end
	local list = {}
	for moduleName in pairs(names) do
		local module = self.modules[moduleName]
		if module and type(module.db) == "table" then list[#list + 1] = moduleName end
	end
	table.sort(list)
	return list
end

-- What the change will touch, as it is now (the shape of the setup's own
-- layout snapshot, with the look and role parts next to it).
local function TakeSnapshot(self, recipe)
	local general = self.db.general
	local record = {
		schema = self.SCHEMA_VERSION, profileSchema = self.PROFILE_SCHEMA, profileBaseline = self.db.profileBaseline, eldoui = self.version,
		at = time and time() or 0, profile = self.profileName, source = recipe.source,
		title = recipe.title or self:LayoutTitle(recipe.layout), layout = recipe.layout,
		before = { general = {}, movers = CopyTable(self.db.movers or {}), modules = {},
			windows = self.BlizzardWindowsMode and self:BlizzardWindowsMode() or general.blizzardWindows },
		switched = {},
	}
	for _, key in ipairs(SETUP_GENERAL) do record.before.general[key] = CopyValue(general[key]) end
	record.moduleNames = TouchedModules(self, recipe)
	for _, moduleName in ipairs(record.moduleNames) do
		record.before.modules[moduleName] = CopyTable(self.modules[moduleName].db)
	end
	if recipe.uiAmount then
		for _, row in ipairs(self.uiAmountModules or {}) do record.switched[row.module] = { from = ModuleOn(row.module) } end
	end
	return record
end

local function FinishSnapshot(self, record)
	local general = self.db.general
	record.after = { general = {}, movers = CopyTable(self.db.movers or {}), modules = {},
		windows = self.BlizzardWindowsMode and self:BlizzardWindowsMode() or general.blizzardWindows }
	for _, key in ipairs(SETUP_GENERAL) do record.after.general[key] = CopyValue(general[key]) end
	for _, moduleName in ipairs(record.moduleNames) do
		local module = self.modules[moduleName]
		if module and type(module.db) == "table" then record.after.modules[moduleName] = CopyTable(module.db) end
	end
	for name, entry in pairs(record.switched) do
		entry.to = ModuleOn(name)
		if entry.to == entry.from then record.switched[name] = nil end
	end
	-- Keep only what the change wrote. Undo restores by value, so a part
	-- whose before equals its after needs no place in the record.
	local before, after = record.before, record.after
	before.general, after.general = Changed(before.general, after.general)
	before.general, after.general = before.general or {}, after.general or {}
	before.movers, after.movers = Changed(before.movers, after.movers)
	before.movers, after.movers = before.movers or {}, after.movers or {}
	local names = {}
	for moduleName in pairs(before.modules) do names[moduleName] = true end
	for moduleName in pairs(after.modules) do names[moduleName] = true end
	for moduleName in pairs(names) do
		local old, new, differs = Changed(before.modules[moduleName], after.modules[moduleName])
		if differs and type(old) == "table" and type(new) == "table" then
			before.modules[moduleName], after.modules[moduleName] = old, new
		else
			before.modules[moduleName], after.modules[moduleName] = nil, nil
		end
	end
end

local function Remember(self, record)
	local history = self.setupHistory
	history[#history + 1] = record
	while #history > SETUP_HISTORY do table.remove(history, 1) end
end

---------------------------------------------------------------------------
-- The saved undo history (store "setupHistory", one part per profile):
--   EldoUIDB.setupHistory[<profile>] = { v = 1, records = { oldest ... newest } }
-- Written at logout (a reload too) from the history in use, read once
-- when the saved settings load. A record whose account file version or
-- profile version is not the one this EldoUI writes, of a profile that is
-- gone, or of the wrong shape is dropped, never repaired: Undo would not
-- know what it put back. A part from a newer EldoUI is kept as it is and
-- not read.
---------------------------------------------------------------------------
local newerParts = {}

local function ValidSide(side)
	if type(side) ~= "table" then return false end
	for _, part in ipairs({ "general", "movers", "modules" }) do
		if type(side[part]) ~= "table" then return false end
	end
	for name, settings in pairs(side.modules) do
		if type(name) ~= "string" or type(settings) ~= "table" then return false end
	end
	for name, point in pairs(side.movers) do
		if type(name) ~= "string" or (point ~= nil and type(point) ~= "table") then return false end
	end
	return true
end

local function ValidRecord(self, record, profile)
	local target = SetupTarget(self)
	if not target or not SetupPlain(record) or not HistoryData(record, {}) or E.Secret(profile) or type(profile) ~= "string"
		or record.profile ~= profile or record.schema ~= self.SCHEMA_VERSION or record.profileSchema ~= self.PROFILE_SCHEMA
		or record.profileBaseline ~= self.PROFILE_BASELINE then return false end
	local saved = rawget(target.root.profiles, profile)
	local ok, current = pcall(target.admit, self, saved, profile)
	if not ok or E.Secret(current) or current ~= true or not SetupTarget(self, target) then return false end
	if not SetupLayout(self, record.layout) or not SetupTarget(self, target) then return false end
	if not (ValidSide(record.before) and ValidSide(record.after)) then return false end
	for _, side in ipairs({ record.before, record.after }) do
		if side.general.layout ~= nil and not SetupLayout(self, side.general.layout) then return false end
	end
	if not SetupTarget(self, target) then return false end
	if type(record.switched) ~= "table" or type(record.moduleNames) ~= "table" then return false end
	for name, entry in pairs(record.switched) do
		if type(name) ~= "string" or type(entry) ~= "table" or type(entry.from) ~= "boolean" or type(entry.to) ~= "boolean" then return false end
	end
	local count, names = 0, {}
	for index, name in pairs(record.moduleNames) do
		if type(index) ~= "number" or index < 1 or index % 1 ~= 0 or type(name) ~= "string" or names[name] then return false end
		names[name], count = true, count + 1
	end
	for index = 1, count do if type(record.moduleNames[index]) ~= "string" then return false end end
	if record.title ~= nil and type(record.title) ~= "string" then return false end
	return true
end

function E:LoadSetupHistory()
	local target = SetupTarget(self)
	if not target then return 0 end
	local list = self.setupHistory
	if not SetupPlain(list) then return 0 end
	wipe(list)
	local history = {}
	local saved = self:SavedSetupHistory()
	if not SetupTarget(self, target) or E.Secret(saved) or (type(saved) ~= "nil" and not SetupPlain(saved)) then return 0 end
	wipe(newerParts)
	if type(saved) == "table" then
		local info = self:StoreInfo("setupHistory")
		if not SetupTarget(self, target) then return 0 end
		local order = 0
		for profile, part in pairs(saved) do
			if E.Secret(profile) or E.Secret(part) then return 0 end
			if type(profile) == "string" and SetupPlain(part) and not E.Secret(part.v) then
				if (tonumber(part.v) or 0) > (info and info.version or 1) then
					newerParts[profile] = part
				else
					if not SetupTarget(self, target) then return 0 end
					self:MigrateStore("setupHistory", part, profile)
					if not SetupTarget(self, target) then return 0 end
					local records = rawget(part, "records")
					if E.Secret(records) or (type(records) ~= "nil" and not SetupPlain(records)) then return 0 end
					for _, record in ipairs(records or {}) do
						if ValidRecord(self, record, profile) then
							order = order + 1
							history[#history + 1] = { record = record, at = tonumber(record.at) or 0, order = order }
						end
					end
				end
			end
		end
	end
	table.sort(history, function(a, b)
		if a.at ~= b.at then return a.at < b.at end
		return a.order < b.order
	end)
	if not SetupTarget(self, target) or E.Secret(self.setupHistory) or self.setupHistory ~= list then return 0 end
	for index, item in ipairs(history) do list[index] = item.record end
	return #list
end

-- The newest records of each profile, within the byte limit.
function E:SaveSetupHistory()
	local target = SetupTarget(self)
	if not target then return false end
	local history = self.setupHistory
	if not SetupPlain(history) then return false end
	local perProfile, kept = {}, {}
	for index = #history, 1, -1 do
		local record = history[index]
		local profile = type(record) == "table" and record.profile
		if not E.Secret(profile) and type(profile) == "string" and ValidRecord(self, record, profile) then
			local count = (perProfile[profile] or 0) + 1
			perProfile[profile] = count
			if count <= SAVED_PER_PROFILE then kept[#kept + 1] = record end
		end
	end
	-- kept runs newest first: the byte limit lets the oldest go.
	local total, saved = 0, {}
	for _, record in ipairs(kept) do
		total = total + self:SavedBytes(record)
		if not SetupTarget(self, target) then return false end
		if total > SAVED_BYTES then break end
		local part = saved[record.profile]
		if not part then
			part = { v = 1, records = {} }
			saved[record.profile] = part
		end
		table.insert(part.records, 1, record)
	end
	for profile, part in pairs(newerParts) do
		if saved[profile] == nil then saved[profile] = part end
	end
	if not SetupTarget(self, target) then return false end
	self:WriteSetupHistory(next(saved) and saved or nil)
	return SetupTarget(self, target) ~= nil
end

-- Profile changes: a deleted or reset profile loses its history, a
-- renamed one keeps it under the new name.
function E:DropSetupHistory(profile)
	local history = self.setupHistory
	for index = #history, 1, -1 do
		if type(history[index]) ~= "table" or history[index].profile == profile then table.remove(history, index) end
	end
	newerParts[profile] = nil
end

function E:RenameSetupHistory(old, new)
	for _, record in ipairs(self.setupHistory) do
		if type(record) == "table" and record.profile == old then record.profile = new end
	end
	if newerParts[old] ~= nil then
		newerParts[new], newerParts[old] = newerParts[old], nil
	end
end

E:OnDatabaseLoad(function(self) self:LoadSetupHistory() end)

-- The parts in order: geometry, look, windows, styles, role, UI amount.
local function Commit(self, recipe, target, generation)
	local history = self.setupHistory
	local function Current()
		return SetupPlain(history) and not E.Secret(self.setupHistory) and self.setupHistory == history
			and SetupTarget(self, target) and self:IsApplyGenerationCurrent(generation, "setup")
	end
	if not Current() then return false end
	local general = self.db.general
	local record = recipe.undo and TakeSnapshot(self, recipe) or nil
	if not Current() then return false end
	local layout = self.layouts[recipe.layout]
	local geometry = recipe.layoutChanges or recipe.reset
	if geometry then
		self:ApplyLayout(recipe.layout, true, { keepPositions = not recipe.reset, setup = true })
		if not Current() then return false end
	end
	local skin = recipe.skin
	local skinBefore, followBefore = SkinInUse(general), general.skinFollow
	if skin and skin.follow then
		general.skinFollow = true
		if self.FollowLayoutSkin then self:FollowLayoutSkin(recipe.layout) end
	elseif skin then
		self:SetSkin(skin.value)
		if not Current() then return false end
		-- Windows that follow the layout follow the new one.
		if geometry and general.blizzardWindows == "layout" and self.ApplyBlizzardWindows then self:ApplyBlizzardWindows() end
	elseif geometry and self.FollowLayoutSkin then
		-- Parts that follow the layout follow it; your own picks stay.
		self:FollowLayoutSkin(recipe.layout)
	end
	if not Current() then return false end
	local skinChanged = SkinInUse(general) ~= skinBefore or general.skinFollow ~= followBefore
	if recipe.accent then
		general.accent, general.accentFromArt = recipe.accent, false
	elseif recipe.look == "layout" and (skinChanged or geometry or recipe.lookAsked) and self.FullLookAccent then
		local accent, fromArt = self:FullLookAccent(SkinInUse(general), layout and layout.accent)
		if not Current() then return false end
		general.accent, general.accentFromArt = accent, fromArt
	end
	if not Current() then return false end
	if recipe.skinVariant and self.SetSkinVariant then self:SetSkinVariant(recipe.skinVariant) end
	if not Current() then return false end
	local units = recipe.graphics and self.modules.UnitFrames and self.modules.UnitFrames.db
	if units then self.SetPath(units, "allFrames.graphics", recipe.graphics) end
	if not Current() then return false end
	if recipe.windows and self.SetBlizzardWindows then
		local mode = self:BlizzardWindowsMode()
		if not Current() then return false end
		if mode ~= recipe.windows then
			local _, needsReload = self:SetBlizzardWindows(recipe.windows, true)
			if not Current() then return false end
			if needsReload and self.ConfigNeedsReload then self:ConfigNeedsReload("blizzardWindows", L["Blizzard windows"]) end
		end
	end
	if not Current() then return false end
	for moduleName, styleKey in pairs(recipe.styles) do
		local module = self.modules[moduleName]
		if module and module.db and module.db.style ~= styleKey then self:ApplyStyle(moduleName, styleKey, true) end
		if not Current() then return false end
	end
	local role = recipe.role
	if role and self.ApplyRole then
		local value = self:GetRole()
		if not Current() then return false end
		if value ~= role.value or (role.classLayer ~= nil and (general.roleClass and true or false) ~= (role.classLayer and true or false)) then
			self:ApplyRole(role.value, { classLayer = role.classLayer })
		end
	end
	if not Current() then return false end
	if recipe.uiAmount and self.ApplyUIAmount then self:ApplyUIAmount(recipe.uiAmount) end
	if not Current() then return false end
	self:RefreshTheme()
	if not Current() then return false end
	self:RefreshMovers()
	if not Current() then return false end
	if record then
		FinishSnapshot(self, record)
		if not Current() or not ValidRecord(self, record, target.name) or not Current() then return false end
		Remember(self, record)
	end
	if not recipe.silent then
		local title = recipe.title or self:LayoutTitle(recipe.layout)
		self:ConfigNotice(L["%s applied."]:format(self:Highlight(title)))
		if not Current() then return false end
		if record and self.PushAlert then
			self:PushAlert({ key = "setup-undo", title = L["Setup changed"],
				text = L["%s applied. Undo puts back what it changed."]:format(self:Highlight(title)),
				actions = {
					{ label = L["Undo"], tip = L["Put back the setup from before this change. Settings you changed since stay yours."],
						func = function() E:UndoSetup() end },
					{ label = L["Keep"] },
				} })
		end
	end
	return Current() and true or false
end

function E:ApplySetup(plan)
	local target, resolve = SetupTarget(self), self.ResolveSetup
	if not target or E.Secret(resolve) or type(resolve) ~= "function" then return false, "no profile" end
	local recipe, why = resolve(self, plan)
	if not SetupTarget(self, target) or E.Secret(self.ResolveSetup) or self.ResolveSetup ~= resolve then return false, "no profile" end
	if not recipe then return false, why end
	local changes = Changes(self, recipe)
	if not SetupTarget(self, target) then return false, "no profile" end
	if #changes == 0 then return false, "same" end
	-- One combat rule: the change waits for the end of combat, and a newer
	-- change or a profile switch since makes it stale.
	local generation = self:NewApplyGeneration("setup")
	local done = false
	local ran = self:RunOutOfCombat(function()
		if not SetupTarget(self, target) or E.Secret(self.ResolveSetup) or self.ResolveSetup ~= resolve then return end
		local fresh = resolve(self, plan)
		if not SetupTarget(self, target) or E.Secret(self.ResolveSetup) or self.ResolveSetup ~= resolve then return end
		if fresh then
			local remaining = Changes(self, fresh)
			if SetupTarget(self, target) and #remaining > 0 then done = Commit(self, fresh, target, generation) end
		end
	end, "setup", { generation = generation, lane = "setup" })
	if not ran then
		if not recipe.silent and SetupTarget(self, target) then self:Print(L["The setup change waits for the end of combat."]) end
		return false, "queued"
	end
	return done, done and "applied" or "same"
end

-- The newest change of this profile that can still be undone.
function E:SetupUndoRecord()
	local target = SetupTarget(self)
	if not target then return nil end
	local history = self.setupHistory
	if not SetupPlain(history) then return nil end
	for index = #history, 1, -1 do
		local record = history[index]
		if ValidRecord(self, record, target.name) and SetupTarget(self, target) then return record, index end
	end
	return nil
end

local function Undo(self, record, target, generation)
	local function Current()
		return SetupTarget(self, target) and self:IsApplyGenerationCurrent(generation, "setup")
	end
	if not Current() then return false end
	local general = self.db.general
	local before, after = record.before, record.after
	-- Modules a UI amount switched, while they are as it left them.
	for name, entry in pairs(record.switched) do
		if ModuleOn(name) == entry.to then self:SetModuleEnabled(name, entry.from) end
		if not Current() then return false end
	end
	local refresh = {}
	for moduleName, saved in pairs(before.modules) do
		local module = self.modules[moduleName]
		local now = after.modules[moduleName]
		if module and type(module.db) == "table" and now then
			local keys = {}
			for key in pairs(saved) do keys[key] = true end
			for key in pairs(now) do keys[key] = true end
			for key in pairs(keys) do
				if not (key == "enabled" and record.switched[moduleName]) then RestoreByValue(module.db, key, saved[key], now[key]) end
			end
			refresh[module] = true
		end
	end
	for _, key in ipairs(SETUP_GENERAL) do RestoreByValue(general, key, before.general[key], after.general[key]) end
	self.db.movers = self.db.movers or {}
	local names = {}
	for name in pairs(before.movers) do names[name] = true end
	for name in pairs(after.movers) do names[name] = true end
	for name in pairs(names) do RestoreByValue(self.db.movers, name, before.movers[name], after.movers[name]) end
	for module in pairs(refresh) do
		Refresh(module)
		if not Current() then return false end
	end
	local setter, apply, getter = self.SetBlizzardWindows, self.ApplyBlizzardWindows, self.BlizzardWindowsMode
	if E.Secret(setter) or E.Secret(apply) or E.Secret(getter) then return false end
	local mode
	if (setter and before.windows ~= after.windows) or apply then
		if type(getter) ~= "function" or (type(setter) ~= "nil" and type(setter) ~= "function")
			or (type(apply) ~= "nil" and type(apply) ~= "function") then return false end
		mode = getter(self)
		if E.Secret(mode) or type(mode) ~= "string" or not Current()
			or E.Secret(self.BlizzardWindowsMode) or self.BlizzardWindowsMode ~= getter
			or E.Secret(self.SetBlizzardWindows) or self.SetBlizzardWindows ~= setter
			or E.Secret(self.ApplyBlizzardWindows) or self.ApplyBlizzardWindows ~= apply then return false end
	end
	if setter and before.windows ~= after.windows and mode == after.windows then
		setter(self, before.windows, true)
	elseif apply and mode == "layout" and before.general.layout ~= after.general.layout then
		apply(self, true)
	end
	if not Current() then return false end
	self:UpdateAccent()
	if not Current() then return false end
	self:RefreshTheme()
	if not Current() then return false end
	self:RefreshMovers()
	if not Current() then return false end
	if self.ApplyWidePoints then self:ApplyWidePoints() end
	if not Current() then return false end
	local layout = self.layouts[general.layout]
	if layout then
		for _, fn in ipairs(layoutCallbacks) do
			local ok, err = pcall(fn, general.layout, layout, true)
			if not ok then geterrorhandler()(err) end
			if not Current() then return false end
		end
	end
	return Current() and true or false
end

function E:UndoSetup()
	local target = SetupTarget(self)
	if not target then return false end
	local history = self.setupHistory
	if not SetupPlain(history) then return false end
	local record, index = self:SetupUndoRecord()
	if not record then
		if SetupTarget(self, target) then self:ConfigNotice(L["There is no setup change to undo on this profile."]) end
		return false
	end
	if not SetupTarget(self, target) then return false end
	if InCombatLockdown() then self:Print(L["Undo waits for the end of combat."]) end
	if not SetupTarget(self, target) then return false end
	local generation = self:NewApplyGeneration("setup")
	self:RunOutOfCombat(function()
		if not SetupTarget(self, target) or E.Secret(self.setupHistory) or self.setupHistory ~= history
			or history[index] ~= record or not ValidRecord(self, record, target.name) then return end
		if not Undo(self, record, target, generation) then return end
		if not SetupTarget(self, target) or E.Secret(self.setupHistory) or self.setupHistory ~= history or history[index] ~= record then return end
		table.remove(history, index)
		if self.DismissAlert then self:DismissAlert("setup-undo") end
		if not SetupTarget(self, target) then return end
		self:ConfigNotice(L["Undone: %s."]:format(self:Highlight(record.title or "?")))
		if SetupTarget(self, target) and self.RefreshConfig then self:RefreshConfig() end
	end, "setup:undo", { generation = generation, lane = "setup" })
	return true
end

-- The Layouts page and /eui layout ask first, with what the pick changes.
-- Frames you dragged stay unless you tick the reset. A profile that keeps
-- its own look (it picked a skin by hand) is asked once whether it wants
-- the layout's look; Keep is the default.
function E:ConfirmApplyLayout(key, opts)
	local target = SetupTarget(self)
	if not target then return false end
	local layout, resolved = self:LayoutRecord(key)
	if not layout or not SetupTarget(self, target) then return false end
	if InCombatLockdown() then
		self:ConfigNotice(L["Layouts can't be changed in combat."], true)
		return false
	end
	opts = type(opts) == "table" and opts or {}
	local general = self.db.general
	local pinned = not general.skinFollow
	local title = self:LayoutTitle(resolved)
	local function Apply(look, reset)
		if not SetupTarget(self, target) then return false end
		local ok, status = E:ApplySetup({ layout = resolved, look = look, resetPositions = reset and true or nil,
			source = opts.source or "layouts", title = title })
		if not ok and status == "same" then
			E:ConfigNotice(L["Nothing to change: you already use the %s layout as it is."]:format(E:Highlight(title)))
		end
		if E.RefreshConfig then E:RefreshConfig() end
	end
	local lines = {}
	if resolved ~= general.layout then
		lines[1] = L["Move every EldoUI frame into the %s layout? Frames you dragged stay where you put them."]:format(E:Highlight(title))
	else
		lines[1] = L["You use the %s layout. Apply it again?"]:format(E:Highlight(title))
	end
	local function Describe(look)
		for _, change in ipairs(self:SetupChanges({ layout = resolved, look = look })) do
			if change.part ~= "layout" then lines[#lines + 1] = change.text end
		end
	end
	local info = { title = L["Apply a layout"], data = resolved,
		check = { label = L["Put frames I dragged back in the layout's spots"],
			desc = L["Off: frames you moved stay where you put them. On: every frame goes to the layout's spot (Undo puts them back)."] } }
	if pinned then
		lines[#lines + 1] = L["Your profile keeps its own look. Use %s's look (art, windows, styles)?"]:format(title)
		local count = #lines
		Describe("layout")
		if #lines == count then lines[#lines + 1] = L["Its look matches yours already."] end
		-- A style that doesn't fit the new layout changes with either answer.
		for _, change in ipairs(self:SetupChanges({ layout = resolved, look = "keep" })) do
			if change.part == "styles" then
				lines[#lines + 1] = L["Either way, a style that doesn't fit this layout changes. %s"]:format(change.text)
			end
		end
		info.accept = L["Keep my look"]
		info.onAccept = function(_, _, checked) Apply("keep", checked) end
		info.extra = { L["Use its look"], function(_, _, checked) Apply("layout", checked) end }
	else
		Describe(nil)
		info.accept = L["Apply"]
		info.onAccept = function(_, _, checked) Apply(nil, checked) end
	end
	info.text = table.concat(lines, "\n")
	self:ShowConfirm(info)
	return true
end

-- Party Quests: the panel sits in the quest tracker column, under the
-- minimap block (left of the right-hand action bars in Eldo-Classic).
-- Modern Center's placement is kept as it shipped.
E.layouts.EldoModern.points.EldoUI_PartyQuests = { "TOPRIGHT", "UIParent", "TOPRIGHT", -104, -460 }
E.layouts.EldoClassic.points.EldoUI_PartyQuests = { "TOPRIGHT", "UIParent", "TOPRIGHT", -344, -460 }

-- Mage Travel: the button sits next to the Consumable Bar (under it in
-- Eldo-Modern, right of it in Eldo-Classic), with room for a row of items.
E.layouts.EldoModern.points.EldoUI_MageTravel = { "BOTTOM", "UIParent", "BOTTOM", 330, 198 }
E.layouts.EldoModern2000.points.EldoUI_MageTravel = { "BOTTOM", "UIParent", "BOTTOM", 330, 198 }
E.layouts.EldoClassic.points.EldoUI_MageTravel = { "BOTTOM", "UIParent", "BOTTOM", 424, 208 }

-- Dialog: the NPC dialog view at the top center, clear of the
-- action bars, the cast bar and the chat.
E.layouts.EldoModern.points.EldoUI_Dialogue = { "TOP", "UIParent", "TOP", -44, -265 }
E.layouts.EldoModern2000.points.EldoUI_Dialogue = { "TOP", "UIParent", "TOP", -44, -265 }
E.layouts.EldoClassic.points.EldoUI_Dialogue = { "TOP", "UIParent", "TOP", -44, -152 }
