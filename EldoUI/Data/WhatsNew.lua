-- What's New: the notes behind the "What's New" page and the one-time
-- "EldoUI was updated" note (Core/Config.lua).
--
-- Newest release first. Each entry:
--   version  the TOC version it belongs to ("0.6.0"); the update note shows
--            only when the newest entry matches the running version
--   date     optional, shown next to the version
--   summary  one sentence for the update note
--   items    short lines in plain player words, one change each
-- The date, summary and lines are marked Key("..."): English while this file
-- loads, translated where the page and the note show them, and listed as keys
-- for the translations.
-- The release step adds a new entry at the top when the TOC version goes up,
-- made from the version's highlights in CHANGELOG.md. Earlier versions are
-- summed up in one entry, the same as in CHANGELOG.md.
local _, E = ...
local Key = E.Key

E.whatsNew = {
	{
		version = "0.7.3001",
		date = Key("November 2026"),
		summary = Key("2 fixes."),
		items = {
			Key("Bags and loot: Right-clicking a potion, food or other usable item in the bag window uses it again."),
			Key("Map and minimap: Logging in no longer shows a blocked-action error from the minimap, and the minimap now shows the name of the player who pings it."),
		},
	},
	{
		version = "0.7.3000",
		date = Key("November 2026"),
		summary = Key("61 new features, 105 improvements and 150 fixes."),
		items = {
			Key("Flight Games is on by default and the Games box appears on your next flight path."),
			Key("Auto UI scale keeps the full layout width on 16:10 screens."),
			Key("Move mode can undo your last change and keeps locked frames in place when you reset."),
			Key("Profile resets, copies, deletions, and imports keep a backup you can undo from the alert."),
			Key("Choose group quests and dungeon routes separately for each character in the leveling guide."),
			Key("Bag and bank windows share the same look and stay sharp at any window scale."),
			Key("Dungeon bosses in the Journal learn their drops from group and solo loot."),
			Key("The Alerts tab keeps its lines between sessions and follows your EldoUI language."),
		},
	},
	{
		version = "0.7.2001",
		date = Key("November 2026"),
		summary = Key("13 new features, 2 improvements and 3 fixes."),
		items = {
			Key("Play 47 Flight Games with your mouse or keyboard and resume an unfinished round on your next flight."),
			Key("Use the new buttons in a whisper window to invite, look up, add, or ignore the contact, or open your saved conversation."),
			Key("Automatic spell rank upgrades now cover every action bar you use and keep lower ranks you place by hand."),
			Key("Nameplates show spell, interrupt, and quest text in more alphabets."),
		},
	},
	{
		version = "0.7.2000",
		date = Key("November 2026"),
		summary = Key("24 new features, 54 improvements and 143 fixes."),
		items = {
			Key("The dungeon map shows the game's minimap large in Live, and WoW: Forever's own dungeons open it with their boss list."),
			Key("All nine WoW: Forever dungeons have their own Journal pages, and quests say where they sit in their chain."),
			Key("A class bar for every class but the shaman keeps your buffs, auras and key cooldowns in view."),
			Key("Spell cues flash the buttons of a spell the game lights up, with an optional sound."),
			Key("A layer chip on the minimap shows your layer and hops you to another with a click."),
			Key("New class reminders for warlocks, rogues, priests, warriors and druids, and a Pet abilities tab for hunters."),
			Key("Player nameplates wear their class color, so players stand out from friendly NPCs."),
			Key("Modern Center, Portrait Staggered, Nameplate Focus and Twin Orbs have new versions in the setup."),
		},
	},
	{
		version = "0.7.1001",
		date = Key("November 2026"),
		summary = Key("1 new feature, 4 improvements and 45 fixes."),
		items = {
			Key("Nameplates: The Game settings tab of the nameplate options has a Plate distance slider."),
			Key("Shaman: Right-click the shield or a weapon imbue icon on the Shaman Cooldowns bar to pick which one it casts, such as Rockbiter, Flametongue or Windfury."),
			Key("Chat: The chat setup keeps everything in your main chat window, also with the Whispers, Loot and Channels tabs: experience, honor, reputation, currency, tradeskills, pet and target icon lines, channels and whispers show there too."),
			Key("Gamepad: The Classic movement key set puts bars 1 to 3 on 1-5 R F G V X Z C, with Shift for bar 2 and Ctrl for bar 3, so T is free and V is used."),
			Key("Chat: A whisper window shows the contact's name in their class color and their race and class under it, also for players outside your friends list and guild."),
			Key("Shaman: Picking an Earth or Fire totem on the Shaman Totems bar sets it in Call of the Elements again."),
			Key("Shaman: The tooltip of the Shaman Totems bar opens beside the bar, so it no longer covers the totem lists that open above the buttons."),
			Key("Auras and cooldowns: The Healthstone reminder shows only when you or a warlock in your group can make one, so a warlock who has not learned Create Healthstone yet is no longer asked for one."),
		},
	},
	{
		version = "0.7.1000",
		date = Key("November 2026"),
		summary = Key("52 new features, 16 improvements and 130 fixes."),
		items = {
			Key("Twin Orbs adds an eleventh layout, with health and power orbs, a shared action-bar tray and the Infernal Stone skin."),
			Key("Gamepad Mode UI offers a controller layout, with your usual frame positions kept for switching back to mouse and keyboard."),
			Key("Undo for layout, pack and setup changes keeps the last three changes of each profile across reloads."),
			Key("Supported addons can follow your layout's reserved spots, with per-addon opt-outs and Undo."),
			Key("Loot rolls show group choices and results, and loot toasts can wait until combat ends."),
			Key("Rare Alerts adds a session history, sharing and quiet-zone controls for rare, treasure and event cards."),
			Key("The Info Bar adds session gold and XP rates, a group roll tracker and mail information across your characters."),
			Key("Encounter Timeline keeps the next-event icon with its bar and separates nearby timer icons."),
		},
	},
	{
		version = "0.7.0003",
		date = Key("October 2026"),
		summary = Key("25 new features, 19 improvements and 27 fixes."),
		items = {
			Key("Your key set now belongs to your profile and knows US, UK, Nordic, German and French keyboards, and new spells land on their own key on bars 1 to 3."),
			Key("Tour helps explain new parts of EldoUI the first time you meet them, and a new character on an account you already set up gets one short page instead of the whole setup."),
			Key("Eldostar, EldoUI's own leveling guide, brings over 200 community guides for WoW: Forever in a window on your layout, with a waypoint to the next goal."),
			Key("My Adventure has a Guides page where you start, follow and search the leveling guides."),
			Key("The Journal can group a boss's loot by kind and shows a branching dungeon quest chain as a flowchart."),
			Key("On a 16:10 screen the layouts give the boss frames, the boss mod windows, the party pets and many more frames a spot of their own."),
			Key("The UI scale choice shows which scales the layouts are made for, with Auto recommended."),
			Key("Switching style presets keeps your layout tidy, and a damaged saved settings file no longer stops EldoUI from loading."),
		},
	},
	{
		version = "0.7.0002",
		date = Key("October 2026"),
		summary = Key("5 improvements and 33 fixes."),
		items = {
			Key("General: The install guide and the release notes name the WoW: Forever game folder, _forever_; the guide tells beta players to install EldoUI there again."),
			Key("Journal: The printable journal page uses the book fonts on your computer and no longer asks a web font site for its fonts when you open it."),
			Key("Options: The Version check option says that it sends your version as a hidden addon message to guild and group members who run EldoUI, never in chat."),
			Key("General: The note after an update has a \"Never show again, even after updates\" check box; the switch on the What's new page turns the note back on."),
			Key("Journal: The copy box of a journal or runs backup code names the button to paste it into once, and the run count's tip says plainly that the Instances module records the runs."),
			Key("General: The bug report form and the support pages name the error window's Report button, as the game shows it."),
			Key("Map and minimap: Buttons on the minimap's side rail keep the rail's order, whichever one you put there first."),
			Key("Group frames: With the raid manager side panel skinned, the ready check, role poll, countdown and option buttons show their icons again."),
		},
	},
	{
		version = "0.7.0001",
		date = Key("October 2026"),
		summary = Key("1 fix."),
		items = {
			Key("General: Every EldoUI version can be downloaded as a zip from its release page."),
		},
	},
	{
		version = "0.7.0000",
		date = Key("October 2026"),
		summary = Key("19 new features, 36 improvements and 25 fixes."),
		items = {
			Key("Ten built-in layouts with clearer names, and EldoUI Center as the new default for new profiles."),
			Key("Four roles in the setup and on the Role page: Melee, Ranged, Healer and Tank."),
			Key("A new Keys and spells step shows your keys, class spells and macros first and changes nothing on your bars until you press Apply."),
			Key("With the Vanilla Original skin, the unit frames, the action bar tray, the minimap border and the micro menu wear the game's own classic art."),
			Key("Every layout or pack change can be undone, from the alert after the change or with /eui layout undo."),
			Key("Your settings, layout, dragged frames and journal carry over to this version, and a copy is kept first that the new Saved data page can put back."),
			Key("EldoUI's own texts are now available in Danish, under General > EldoUI language."),
			Key("Nameplates, bags, cooldown displays and many other parts do much less work, and background work pauses in combat."),
		},
	},
	{
		version = "0.6.6005",
		date = Key("October 2026"),
		summary = Key("The versions from 0.5.0 to 0.6.6005 in short: what they brought that is still in EldoUI."),
		items = {
			Key("A step-by-step setup with Express, preset packs, UI amount and the Overview page."),
			Key("Move any frame with /eui move, and set your keys with /eui kb and the key sets."),
			Key("Unit, party and raid frames, nameplates and eight action bars, with unit-frame graphics in your skin's materials."),
			Key("Eight skins for the whole UI and the Appearance page, with skins for Blizzard's own windows."),
			Key("The Talent Planner with Import build, Training, and lower spell ranks lit on your bars."),
			Key("My Adventure, the Loot Guide, Attunements, Dungeon Routes and Map Notes."),
			Key("Class tools: Shaman Totems, Mage Travel, the Blessing Plan and class reminders."),
			Key("The error log (/eui errors) with a Report button that leaves out your character's name, realm, guild and chat text."),
		},
	},
}
