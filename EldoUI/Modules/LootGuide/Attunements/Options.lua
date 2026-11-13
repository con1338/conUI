-- EldoUI Attunements: settings page and style presets.
--
-- Rare settings sit behind the gear of the row they belong to. While the
-- Loot Guide is off the page shows only a notice and a button to turn it
-- on: the tab lives in the Loot Guide window. Tooltip lines have their
-- Always / Shift / Ctrl / Alt / Never switches on the Tooltip page.
local _, E = ...
local LG = E.LootGuide
local L = E.L
local A = E:GetModule("Attunements")

local function GuideOff()
	return not (LG and LG.active)
end

local function GuideOn()
	return not GuideOff()
end

A.options = {
	{ type = "description", label = L["Attunements, keys and dungeon quest chains as a Loot Guide tab. Progress comes from your quest log, bags and reputation."] },
	{ type = "description", hidden = GuideOn, label = L["The Attunements tab lives in the Loot Guide. Turn the Loot Guide on to use it."] },
	{ type = "execute", label = L["Turn on the Loot Guide"], hidden = GuideOn,
		func = function()
			E:SetModuleEnabled("LootGuide", true)
			if E.RefreshConfig then E:RefreshConfig() end
		end,
		desc = L["Switches the Loot Guide module on; the Attunements tab comes with it."] },

	{ type = "header", label = L["Window"], hidden = GuideOff },
	{ type = "select", key = "view", label = L["View"], hidden = GuideOff,
		values = { chain = L["Flowchart"], list = L["Step list"] },
		desc = L["How a chain shows: a flowchart of steps, or one step per row (easier to read at a small window scale)."] },
	{ type = "select", key = "showFaction", label = L["Show steps for"], hidden = GuideOff,
		values = { mine = L["My faction"], Alliance = L["Alliance"], Horde = L["Horde"], all = L["Both factions"] },
		desc = L["Which faction's steps the chain shows. Steps for both factions always show."],
		cog = {
			{ type = "toggle", key = "hideDone", label = L["Hide finished"],
				desc = L["The list on the left leaves out attunements you have finished."] },
			{ type = "select", key = "showExpansions", label = L["Content"],
				values = { forever = L["In the game"], all = L["All"] },
				desc = L["In the game: only instances the game has. All: also those the client does not list yet."] },
			{ type = "select", key = "classQuests", label = L["Class quests"],
				values = { mine = L["My class"], all = L["All classes"] },
				desc = L["Which classes the Class quests group lists."] },
		} },
	{ type = "select", key = "overview", label = L["Overview opens on"], hidden = GuideOff,
		values = { mine = L["My characters"], guild = L["Guild"] },
		desc = L["The view the Overview button opens first."] },
	{ type = "toggle", key = "instanceLine", label = L["Attunement line in the Journal"], hidden = GuideOff,
		desc = L["Dungeon and raid pages in the Journal show how far you are with their attunement."] },
	{ type = "execute", label = L["Open the Attunements tab"], hidden = GuideOff, func = function() A:Open() end,
		desc = L["Same as /eui attune. Opens the Loot Guide on the Attunements tab."] },

	{ type = "header", label = L["Alerts"], hidden = GuideOff },
	{ type = "toggle", key = "alerts", label = L["Step alerts"], hidden = GuideOff,
		desc = L["A toast when you finish a step or a whole attunement. Nothing is posted to chat."],
		cog = {
			{ type = "media", mediaKind = "sound", none = true, key = "alertSound", label = L["Sound when an attunement is done"],
				desc = L["Plays with the toast for a finished attunement. Step toasts are silent."] },
			{ type = "toggle", key = "guildButton", label = L["Tell the guild button"],
				desc = L["Adds a button to the toast that posts one line in guild chat when you click it."] },
			{ type = "execute", label = L["Test alert"], testSafe = true, func = function() A:TestAlert() end,
				desc = L["Shows a sample toast with your settings."] },
		} },

	{ type = "header", label = L["Tooltips and map"], hidden = GuideOff },
	{ type = "description", hidden = GuideOff,
		label = L["Attunement lines on item and character tooltips have their own switches on the Tooltip page."] },
	{ type = "toggle", key = "mapPins", label = L["Next step on the map"], hidden = GuideOff,
		desc = L["A pin where the next step of each attunement you are on starts. Click it for the arrow."] },

	{ type = "header", label = L["Guild and group"], hidden = GuideOff },
	{ type = "toggle", key = "guildShare", label = L["Share with guild and group"], hidden = GuideOff,
		desc = L["Lets you ask guild or group members who use EldoUI for their attunements, and send yours. Nothing is sent until you click Ask or Send mine."],
		cog = {
			{ type = "select", key = "guildAnswer", label = L["When someone asks"],
				values = { ask = L["Ask me"], never = L["Never"] },
				desc = L["Ask me: a toast lets you send your progress with one click. Never: requests are ignored."] },
			{ type = "range", key = "guildMaxNames", label = L["Names per step"], min = 0, max = 25, step = 1, zeroText = "None",
				desc = L["How many guild members a step's tooltip lists by name."] },
			{ type = "range", key = "guildKeepDays", label = L["Keep results (days)"], min = 7, max = 180, step = 1,
				desc = L["Results older than this are removed."] },
		} },
	-- Outside the gear: results you already received still show on
	-- tooltips while sharing is off, so they can be cleared at any time.
	{ type = "execute", label = L["Clear guild results"], confirm = true, hidden = GuideOff, func = function() A:ClearPeers() end,
		desc = L["Removes every result you received."] },

	{ type = "header", label = L["Forever dungeons"], hidden = GuideOff },
	{ type = "toggle", key = "record", label = L["Remember Forever quests"], hidden = GuideOff,
		desc = L["Keeps a short list of Forever-only quests you accept (name, giver, place) so their dungeon page can show them. Stays on this PC."] },
	{ type = "execute", label = L["Copy the list"], testSafe = true, hidden = GuideOff, func = function() A:CopySeen() end,
		desc = L["Opens a copy box with the list, to send to EldoUI's authors so the dungeon can get a full chain."] },

	{ type = "header", label = L["Help"], hidden = GuideOff },
	{ type = "description", hidden = GuideOff,
		label = L["Green is done, the accent is in your quest log, yellow is available, gray is locked. An unreported step counts once the next is done."] },
	{ type = "execute", label = L["Show data status"], testSafe = true, hidden = GuideOff, func = function() A:Open("status") end,
		desc = L["Shows on the Attunements tab how many attunements, steps and quests are loaded and the data version."] },
}

E:RegisterStyles("Attunements", {
	{ key = "EldoUI", title = "EldoUI", desc = L["Flowchart, your faction, toasts on, a line in the Journal."],
		settings = { view = "chain", showFaction = "mine", hideDone = false, alerts = true, instanceLine = true, mapPins = false,
			showExpansions = "forever", classQuests = "mine", overview = "mine" } },
	{ key = "Steps", title = L["Step list"], desc = L["One step per row and finished attunements hidden: easy to read at a small window scale."],
		settings = { view = "list", hideDone = true } },
	{ mode = true, key = "Raider", title = L["Raider"], desc = L["Guild view first and more names per step, for raid leaders checking who is ready. Still sends nothing without a click."],
		settings = { view = "chain", overview = "guild", guildShare = true, guildMaxNames = 15, alerts = true } },
	{ mode = true, key = "Leveller", title = L["Leveler"], desc = L["The next step's quest giver on the map and toasts as you go."],
		settings = { view = "list", mapPins = true, alerts = true, showExpansions = "forever" } },
	{ mode = true, key = "Explorer", title = L["Both factions"], desc = L["Every step for both sides and every class, also content the client does not list yet."],
		settings = { showFaction = "all", showExpansions = "all", classQuests = "all", hideDone = false } },
	{ mode = true, key = "Quiet", title = L["Quiet"], desc = L["No toasts, no pins, no Journal line; the tab only."],
		settings = { alerts = false, mapPins = false, instanceLine = false, guildShare = false } },
})
