-- EldoUI Notifications: options page and style presets.
--
-- Each tab starts with the element's own switches (the same ones as on the
-- Blizzard UI page, mirrored through a small proxy so both pages always
-- agree), then the detailed settings for the switches that are on.
local _, E = ...
local L = E.L
local M = E:GetModule("Notifications")

---------------------------------------------------------------------------
-- Switch proxy: options read and write E:BlizzardState through
-- db.blizz.<element>.<action>. Nothing is stored in the profile.
---------------------------------------------------------------------------
local proxyMeta = {}
local proxy = setmetatable({}, proxyMeta)
proxyMeta.__index = function(_, id)
	return setmetatable({}, {
		__index = function(_, key)
			local state = E:BlizzardState(id)
			return state and state[key]
		end,
		__newindex = function(_, key, value)
			E:SetBlizzardElement(id, key, value)
		end,
	})
end
proxyMeta.__newindex = function() end

local function AttachProxy()
	if M.db and rawget(M.db, "blizz") ~= proxy then
		rawset(M.db, "blizz", proxy)
	end
end

local initialize, profileChanged = M.OnInitialize, M.OnProfileChanged
function M:OnInitialize()
	initialize(self)
	AttachProxy()
	E:AddCommand("cutscenes", "forget  play every cutscene again once (skip seen cutscenes)", function(arg)
		if (arg or ""):lower():find("forget") then M:ForgetSeenCinematics() else E:Print(L["Usage: /eui cutscenes forget"]) end
	end, "Layout & frames")
end
function M:OnProfileChanged()
	AttachProxy()
	profileChanged(self)
end

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function Off(id, action)
	return function() return not E:BlizzardAllowed(id, action) end
end

-- The raw Hide switch (not implied by Replace).
local function HideOff(id)
	return function()
		local state = E:BlizzardState(id)
		return not (state and state.enabled and state.hide)
	end
end

-- `labels.noLook`: the tab brings its own headers after the switches.
local function Switches(options, id, labels)
	local data = E.blizzardElements[id]
	table.insert(options, { type = "header", label = "Blizzard switches" })
	table.insert(options, { type = "toggle", key = "blizz." .. id .. ".enabled", label = "Let EldoUI change this",
		desc = "Off keeps Blizzard's own %s, untouched. The same switch as on the Blizzard UI page.", descFill = data.title })
	for _, action in ipairs({ "skin", "move", "hide", "replace", "improve" }) do
		if data.allowed[action] and labels[action] then
			-- Named as on the Blizzard UI page; what the switch does
			-- here is in the desc.
			table.insert(options, { type = "toggle", key = "blizz." .. id .. "." .. action, label = E.BLIZZARD_ACTION_LABEL[action],
				desc = labels[action][2], hidden = Off(id) })
		end
	end
	table.insert(options, { type = "description", label = "Blizzard's own version is showing. Turn on \"Let EldoUI change this\" to use the settings below.",
		hidden = function() return E:BlizzardAllowed(id) end })
	-- The element's own settings follow under their own header.
	if not labels.noLook then table.insert(options, { type = "header", label = "Look" }) end
end

local CVAR_VALUES = { game = "Game setting", on = "On", off = "Off" }
local GROWTH = { DOWN = "Down", UP = "Up" }

local options = {}
local function Add(option) table.insert(options, option) end

---------------------------------------------------------------------------
-- Alerts
---------------------------------------------------------------------------
local ALERTS = "alert-toasts"
Add({ type = "tab", label = "Alerts" })
-- Preview: one sample card of the EldoUI alert lane in its width and icon
-- size (E:ConfigSample, Core/MoverSamples.lua).
local function UpdatePreview(canvas)
	local lane = M.db and M.db.alerts and M.db.alerts.lane
	if not (canvas and lane) then return end
	E:ConfigSample(canvas, "toast", {
		width = lane.width, height = (lane.iconSize or 36) + 12,
		title = L["Achievement"], text = L["Test achievement"], icon = E.media.icon,
	})
end
Add({ type = "preview", label = "Preview", height = 64, create = UpdatePreview, update = UpdatePreview,
	desc = "A sample card of the EldoUI alert lane in its width and icon size." })
Switches(options, ALERTS, {
	noLook = true,
	skin = { "Skin", E.Key("A flat EldoUI box behind every alert; no glow and shine flash.") },
	move = { "Move into one lane", E.Key("Alerts sit on the \"Alert Lane\" mover, level-up toasts and boss banners on \"Banners\", Battle.net toasts and the GM ticket on \"Battle.net Toasts\".") },
	hide = { "Hide (pick the types)", E.Key("Hide the alert types checked below.") },
	replace = { "EldoUI alert lane", E.Key("EldoUI's own toasts for achievements, level-up, quest complete and more. Blizzard's version of each type you tick is hidden.") },
})
Add({ type = "header", label = "Lane", hidden = function() return not (E:BlizzardAllowed(ALERTS, "move") or E:BlizzardAllowed(ALERTS, "replace")) end })
Add({ type = "select", key = "alerts.growth", label = "Growth direction", desc = "New alerts are added below (Down) or above (Up) the Alert lane mover.", values = GROWTH,
	hidden = function() return not (E:BlizzardAllowed(ALERTS, "move") or E:BlizzardAllowed(ALERTS, "replace")) end })
Add({ type = "range", key = "alerts.spacing", label = "Spacing", desc = "Gap between alerts in the lane.", min = 0, max = 30, step = 1,
	hidden = function() return not (E:BlizzardAllowed(ALERTS, "move") or E:BlizzardAllowed(ALERTS, "replace")) end })
Add({ type = "range", percent = true, key = "alerts.scale", label = "Blizzard alert scale", desc = "Size of Blizzard's alerts in the lane.", min = 0.5, max = 1.5, step = 0.05, hidden = Off(ALERTS, "move") })
Add({ type = "range", percent = true, key = "alerts.bannerScale", label = "Banner scale", desc = "Size of level-up toasts and the boss banner.", min = 0.5, max = 1.5, step = 0.05, hidden = Off(ALERTS, "move") })
Add({ type = "toggle", key = "alerts.hideGlow", label = "No glow flash", desc = "Turns off the bright glow and shine when an alert appears.", hidden = Off(ALERTS, "skin") })
Add({ type = "header", label = "Hide these types", hidden = HideOff(ALERTS) })
for _, entry in ipairs({
	{ "achievement", "Achievements", E.Key("Achievements, criteria and Legacy challenge alerts.") },
	{ "loot", E.Key("Loot won"), E.Key("Items won from rolls and loot upgrades.") },
	{ "money", E.Key("Money and honor won"), E.Key("Gold and honor reward alerts.") },
	{ "recipe", "Recipes", E.Key("New recipe and specialization alerts.") },
	{ "collection", "Collections", E.Key("New mount, pet, toy and appearance alerts.") },
	{ "instance", E.Key("Dungeon and scenario complete"), E.Key("The reward alert after a dungeon, scenario or world quest.") },
	{ "other", E.Key("Everything else"), E.Key("Any alert type not listed here.") },
	{ "levelup", E.Key("Level-up toasts"), E.Key("The big level-up and new spell toast in the middle of the screen.") },
	{ "events", E.Key("Quest and zone event toasts"), E.Key("Other big toasts in the middle of the screen.") },
	{ "bossBanner", E.Key("Boss banner"), E.Key("The banner after a boss kill with its loot.") },
	{ "bnet", E.Key("Battle.net toasts"), E.Key("Friend online/offline and broadcast toasts above the chat (game setting).") },
}) do
	Add({ type = "toggle", key = "alerts.hide." .. entry[1], label = entry[2], desc = entry[3], hidden = HideOff(ALERTS) })
end
Add({ type = "header", label = "EldoUI alert lane", hidden = Off(ALERTS, "replace") })
for _, entry in ipairs({
	{ "achievement", "Achievements", E.Key("Achievement name, points and icon. Click opens it in the achievement window.") },
	{ "levelup", "Level up", E.Key("Your new level. While the Talent Planner's level-up reminder or the Journal's level moment is on, that card shows the level instead.") },
	{ "levelupSpells", E.Key("New spells on level up"), E.Key("The level-up toast lists the spells and ranks your class trainer teaches from your new level that you don't know yet. Needs the Training module.") },
	{ "quest", "Quest complete", E.Key("Quest name with the XP and money it gave.") },
	{ "loot", E.Key("Loot won"), E.Key("Items you won from a roll. Off by default: the Loot module shows loot toasts.") },
	{ "recipe", "Recipes", E.Key("New recipes learned.") },
	{ "collection", "Collections", E.Key("New mounts, pets and toys.") },
	{ "boss", E.Key("Boss kills"), E.Key("The boss you just defeated.") },
}) do
	Add({ type = "toggle", key = "alerts.lane." .. entry[1], label = entry[2], desc = entry[3], hidden = Off(ALERTS, "replace") })
end
Add({ type = "range", key = "alerts.lane.max", label = "Toasts at once", desc = "More wait in line until one goes.", min = 1, max = 8, step = 1, hidden = Off(ALERTS, "replace") })
Add({ type = "range", unit = "s", key = "alerts.lane.duration", label = "Seconds on screen", desc = "How long a toast stays. Hovering it keeps it; right-click closes it.", min = 2, max = 20, step = 1, hidden = Off(ALERTS, "replace") })
Add({ type = "range", key = "alerts.lane.width", label = "Width", desc = "Width of each toast.", min = 200, max = 480, step = 10, hidden = Off(ALERTS, "replace") })
Add({ type = "range", key = "alerts.lane.iconSize", label = "Icon size", desc = "Size of the icon; the toast's height follows it.", min = 20, max = 64, step = 2, hidden = Off(ALERTS, "replace") })
Add({ type = "range", key = "alerts.lane.fontSize", label = "Text size", desc = "Size of the toast's main line.", min = 9, max = 20, step = 1, hidden = Off(ALERTS, "replace") })
Add({ type = "toggle", key = "alerts.lane.sound", label = "Sound", desc = "A short sound with each toast.", hidden = Off(ALERTS, "replace") })
Add({ type = "media", key = "alerts.lane.soundID", label = "Toast sound", mediaKind = "sound", dependsOn = "alerts.lane.sound",
	desc = "The sound each toast plays. The default is the game's epic loot sound.", hidden = Off(ALERTS, "replace") })
Add({ type = "toggle", key = "alerts.lane.holdInCombat", label = "Wait until combat ends", desc = "Toasts that arrive in combat show after it.", hidden = Off(ALERTS, "replace") })
Add({ type = "execute", label = "Test the lane", desc = "Shows three sample toasts (/eui notify test lane).", func = function() M:Test("lane") end, hidden = Off(ALERTS, "replace") })
Add({ type = "header", label = "Game toast settings", hidden = Off(ALERTS) })
for _, entry in ipairs({
	{ "enableLootToasts", E.Key("Loot toasts"), E.Key("Blizzard's loot alerts (game setting).") },
	{ "enableCollectionToasts", E.Key("Collection toasts"), E.Key("New mount, pet and toy alerts (game setting).") },
	{ "enableLearnedRecipeToasts", E.Key("Recipe toasts"), E.Key("New recipe alerts (game setting).") },
	{ "showToastOnline", E.Key("Friend online"), E.Key("Battle.net toast when a friend comes online (game setting).") },
	{ "showToastOffline", E.Key("Friend offline"), E.Key("Battle.net toast when a friend goes offline (game setting).") },
	{ "showToastBroadcast", E.Key("Broadcasts"), E.Key("Battle.net toast for friends' broadcasts (game setting).") },
	{ "showToastFriendRequest", E.Key("Friend requests"), E.Key("Battle.net toast for new friend requests (game setting).") },
}) do
	Add({ type = "select", key = "alerts.cvars." .. entry[1], label = entry[2],
		desc = "%s \"Game setting\" leaves it as you set it in the game; Blizzard default puts your value back.", descFill = entry[3],
		values = CVAR_VALUES, hidden = Off(ALERTS) })
end

---------------------------------------------------------------------------
-- Talking head
---------------------------------------------------------------------------
local HEAD = "talking-head"
Add({ type = "tab", label = "Talking head" })
Switches(options, HEAD, {
	skin = { "Skin", E.Key("EldoUI panel, font and colors instead of the parchment art.") },
	move = { "Move", E.Key("Into the alert lane, or onto its own \"Talking Head\" mover.") },
	hide = { "Hide", E.Key("No talking head (see below for the voice).") },
})
Add({ type = "description", label = "Forever may use the talking head only in a few places; check it in game.", hidden = Off(HEAD) })
Add({ type = "select", key = "talkingHead.anchor", label = "Where", desc = "In the alert lane (above or below the alerts), or on its own mover.",
	values = { lane = "Alert lane", own = "Own mover" }, hidden = Off(HEAD, "move") })
Add({ type = "range", percent = true, key = "talkingHead.scale", label = "Scale", desc = "Size of the talking head.", min = 0.5, max = 1.5, step = 0.05, hidden = Off(HEAD, "move") })
Add({ type = "range", key = "talkingHead.textSize", label = "Text size", desc = "0 keeps Blizzard's size.", min = 0, max = 20, step = 1, hidden = Off(HEAD, "skin") })
Add({ type = "select", key = "talkingHead.hideMode", label = "When hidden", desc = "Hide it completely (no voice), or hide only the frame and still hear the voice.",
	values = { all = "No talking head", frame = "Frame only, keep voice" }, hidden = HideOff(HEAD) })

---------------------------------------------------------------------------
-- Raid warnings
---------------------------------------------------------------------------
local WARNING = "raid-warning"
Add({ type = "tab", label = "Raid warnings" })
Switches(options, WARNING, {
	skin = { "EldoUI font", E.Key("Raid warnings and boss emotes in the EldoUI font and outline.") },
	move = { "Move and scale", E.Key("On the \"Raid Warnings\" mover.") },
	hide = { "Hide raid warnings", E.Key("Player raid warnings no longer show in the middle of the screen (they stay in chat). Boss emotes always show.") },
})
Add({ type = "range", percent = true, key = "raidWarning.scale", label = "Scale", desc = "Size of raid warnings and boss emotes.", min = 0.5, max = 1.5, step = 0.05, hidden = Off(WARNING, "move") })
Add({ type = "execute", label = "Test", desc = "Shows a sample raid warning.", func = function() M:Test("warning") end, hidden = Off(WARNING) })
Add({ type = "header", label = "Battleground messages" })
Add({ type = "toggle", key = "bgMessages.enabled", label = "Battleground messages as big text",
	desc = "Battleground system messages (flag taken, base assaulted) also show as big text right under the raid warnings, in the game's colors. They stay in chat as well. Works without the switches above." })
Add({ type = "range", key = "bgMessages.fontSize", label = "Text size", desc = "Size of the battleground message text.", min = 12, max = 36, step = 1, dependsOn = "bgMessages.enabled" })
Add({ type = "range", unit = "s", key = "bgMessages.duration", label = "Seconds on screen", desc = "How long a battleground message stays before it fades.", min = 2, max = 15, step = 1, dependsOn = "bgMessages.enabled" })
Add({ type = "execute", label = "Test", desc = "Shows a sample battleground message (/eui notify test bg).", testSafe = true,
	func = function() M:Test("bg") end, dependsOn = "bgMessages.enabled" })

---------------------------------------------------------------------------
-- Errors
---------------------------------------------------------------------------
local ERRORS = "ui-errors"
Add({ type = "tab", label = "Error text" })
Switches(options, ERRORS, {
	skin = { "EldoUI font", E.Key("Red error text in the EldoUI font; size and time below.") },
	move = { "Move and scale", E.Key("On the \"Red Error Text\" mover.") },
	hide = { "Hide (filter)", E.Key("Hide red errors by category, in combat, or always. Yellow quest progress always shows.") },
})
Add({ type = "range", key = "errors.fontSize", label = "Text size", desc = "0 keeps Blizzard's size.", min = 0, max = 24, step = 1, hidden = Off(ERRORS, "skin") })
Add({ type = "range", unit = "s", key = "errors.duration", label = "Seconds on screen", desc = "How long a message stays; 0 keeps Blizzard's time.", min = 0, max = 10, step = 0.5, hidden = Off(ERRORS, "skin") })
Add({ type = "range", percent = true, key = "errors.scale", label = "Scale", desc = "Size of the error text.", min = 0.5, max = 1.5, step = 0.05, hidden = Off(ERRORS, "move") })
Add({ type = "select", key = "errors.mode", label = "Hide", desc = "By category (checked below), every red error in combat, or always.",
	values = { filter = "By category", combat = "In combat", always = "Always" }, hidden = HideOff(ERRORS) })
local function NotFilter()
	return HideOff(ERRORS)() or M.db.errors.mode ~= "filter"
end
for _, entry in ipairs({
	{ "power", E.Key("Not enough mana, rage or energy"), E.Key("Every \"not enough\" power message.") },
	{ "cooldown", E.Key("Not ready yet"), E.Key("Ability, spell and item cooldown messages.") },
	{ "range", E.Key("Out of range"), E.Key("Out of range and too close.") },
	{ "target", E.Key("No or invalid target"), E.Key("No target, invalid target and target is dead.") },
	{ "facing", E.Key("Wrong facing"), E.Key("Target must be in front of you, or you must be behind it.") },
	{ "moving", E.Key("Can't do that while moving"), E.Key("Casting while moving.") },
	{ "busy", E.Key("Another action in progress"), E.Key("Spell already in progress and interrupted casts.") },
}) do
	Add({ type = "toggle", key = "errors.categories." .. entry[1], label = "Hide: %s", labelFill = entry[2], desc = entry[3], hidden = NotFilter })
end
Add({ type = "toggle", key = "errors.hideStatus", label = "Hide \"Screen captured\"", desc = "The text in the middle of the screen after a screenshot.", hidden = HideOff(ERRORS) })
Add({ type = "execute", label = "Test", desc = "Shows a sample red error.", func = function() M:Test("errors") end, hidden = Off(ERRORS) })

---------------------------------------------------------------------------
-- Zone text
---------------------------------------------------------------------------
local ZONE = "zone-text"
Add({ type = "tab", label = "Zone text" })
Switches(options, ZONE, {
	skin = { "EldoUI font", E.Key("Zone, subzone and PvP text in the EldoUI font; sizes below.") },
	move = { "Move and scale", E.Key("On the \"Zone Text\" mover.") },
	hide = { "Hide", E.Key("No zone text when you enter a new area.") },
})
Add({ type = "range", key = "zoneText.zoneSize", label = "Zone size", desc = "0 keeps Blizzard's size.", min = 0, max = 48, step = 1, hidden = Off(ZONE, "skin") })
Add({ type = "range", key = "zoneText.subZoneSize", label = "Subzone size", desc = "0 keeps Blizzard's size.", min = 0, max = 40, step = 1, hidden = Off(ZONE, "skin") })
Add({ type = "range", key = "zoneText.pvpSize", label = "PvP text size", desc = "\"Contested territory\" and similar; 0 keeps Blizzard's size.", min = 0, max = 30, step = 1, hidden = Off(ZONE, "skin") })
Add({ type = "range", percent = true, key = "zoneText.scale", label = "Scale", desc = "Size of all zone text.", min = 0.5, max = 1.5, step = 0.05, hidden = Off(ZONE, "move") })
Add({ type = "select", key = "zoneText.hidePart", label = "Hide what", desc = "All zone text, or only the subzone (the zone name still shows when you enter a new zone).",
	values = { both = "Zone and subzone", sub = "Only the subzone" }, hidden = HideOff(ZONE) })

---------------------------------------------------------------------------
-- Ready check and pop-ups
---------------------------------------------------------------------------
local POPUPS = "ready-check-popups"
Add({ type = "tab", label = "Ready check" })
Switches(options, POPUPS, {
	skin = { "Skin", E.Key("Ready check, role poll and battleground pop-ups in the EldoUI look.") },
	move = { "Move and scale", E.Key("The ready check on its own mover; ping wheel scale.") },
	replace = { "Compact EldoUI ready check", E.Key("Who asked and a countdown, with Blizzard's own Ready / Not ready buttons. You always answer yourself.") },
	improve = { "Sound, flash and timers", E.Key("Sound and taskbar flash on every pop-up, countdowns, and a not-ready summary.") },
})
Add({ type = "range", percent = true, key = "popups.scale", label = "Ready check scale", desc = "Size of the ready check.", min = 0.5, max = 1.5, step = 0.05, hidden = Off(POPUPS, "move") })
Add({ type = "range", percent = true, key = "popups.pingScale", label = "Ping wheel scale", desc = "Size of the ping wheel (changed out of combat only).", min = 0.5, max = 1.5, step = 0.05, hidden = Off(POPUPS, "move") })
Add({ type = "toggle", key = "popups.masterSound", label = "Sound on the Master channel", desc = "The ready-check sound plays even with game sound effects turned off.", hidden = Off(POPUPS, "improve") })
Add({ type = "media", key = "popups.soundID", label = "Pop-up sound", mediaKind = "sound", dependsOn = "popups.masterSound",
	desc = "The sound for the ready check, role poll, battleground and dungeon ready pop-ups. The default is the game's ready check sound.", hidden = Off(POPUPS, "improve") })
Add({ type = "toggle", key = "popups.flash", label = "Taskbar flash", desc = "The game flashes in the taskbar when a pop-up appears.", hidden = Off(POPUPS, "improve") })
Add({ type = "toggle", key = "popups.timers", label = "Countdown bars", desc = "A countdown on the ready check and battleground pop-up.", hidden = Off(POPUPS, "improve") })
Add({ type = "toggle", key = "popups.queueTimer", label = "Dungeon ready timer", desc = "A countdown bar when the group finder says your dungeon is ready.", hidden = Off(POPUPS, "improve") })
Add({ type = "toggle", key = "popups.summary", label = "Not-ready summary", desc = "After a ready check, one line in chat with who wasn't ready or didn't answer.", hidden = Off(POPUPS, "improve") })

---------------------------------------------------------------------------
-- Pings
---------------------------------------------------------------------------
local function NoFeed() return not M.db.pings.feed end
Add({ type = "tab", label = "Pings" })
Add({ type = "description", label = "Extras for Blizzard's ping system. Each is off until you check it, and none of them ever sends a ping on its own." })
Add({ type = "header", label = "Ping feed" })
Add({ type = "toggle", key = "pings.feed", label = "Enable", desc = "A small list of the pings you receive: time, sender and what they pinged. Place it with the \"Ping Feed\" mover (/eui move)." })
for _, entry in ipairs({
	{ "world", E.Key("In the open world"), E.Key("Show pings outside instances.") },
	{ "dungeon", E.Key("In dungeons"), E.Key("Show pings in dungeons and scenarios.") },
	{ "raid", E.Key("In raids"), E.Key("Show pings in raids.") },
	{ "battleground", E.Key("In battlegrounds"), E.Key("Show pings in battlegrounds.") },
	{ "arena", E.Key("In arenas"), E.Key("Show pings in arenas.") },
}) do
	Add({ type = "toggle", key = "pings.content." .. entry[1], label = entry[2], desc = entry[3], hidden = NoFeed })
end
Add({ type = "range", key = "pings.rows", label = "Rows", desc = "How many pings the feed shows; the newest is on top.", min = 2, max = 12, step = 1, hidden = NoFeed })
Add({ type = "range", key = "pings.fade", label = "Fade after", unit = "s", desc = "Rows fade out after this time; 0 keeps them until newer pings push them out.", min = 0, max = 120, step = 5, hidden = NoFeed })
Add({ type = "range", key = "pings.width", label = "Width", desc = "Width of the feed.", min = 180, max = 480, step = 10, hidden = NoFeed })
Add({ type = "range", key = "pings.fontSize", label = "Text size", desc = "Text size of the rows.", min = 9, max = 18, step = 1, hidden = NoFeed })
Add({ type = "toggle", key = "pings.backdrop", label = "Background", desc = "A see-through panel behind the rows.", hidden = NoFeed })
Add({ type = "toggle", key = "pings.sound", label = "Sound", desc = "Plays the sound below when a ping arrives.", hidden = NoFeed })
Add({ type = "media", key = "pings.soundID", label = "Ping sound", mediaKind = "sound", desc = "The sound for a new ping.", dependsOn = "pings.sound", hidden = NoFeed })
Add({ type = "execute", label = "Test", desc = "Adds three sample rows to the feed (/eui notify test pings).", testSafe = true,
	func = function() M:Test("pings") end, hidden = NoFeed })
Add({ type = "header", label = "Pingable icons" })
Add({ type = "toggle", key = "pings.pingableIcons", label = "Ping EldoUI cooldown icons",
	desc = "Hover one of EldoUI's cooldown icons and press your ping key: the game pings that spell or item, as it does for Blizzard's Cooldown Manager. One key press, one ping." })
Add({ type = "header", label = "Ping keys" })
Add({ type = "toggle", key = "pings.keys", label = "Enable",
	desc = "Four key bindings that each ping one spell or item through Blizzard's /pingspell and /pingitem. Bind them in the game's Key Bindings (AddOns > EldoUI Pings). One key press, one ping." })
for index = 1, 4 do
	Add({ type = "input", key = "pings.keySpell" .. index, label = "Ping key %d", labelFill = index,
		desc = "A spell name or spell ID, or item: and an item ID (item:6948). Empty: the key does nothing.", dependsOn = "pings.keys" })
end

---------------------------------------------------------------------------
-- Cutscenes and tutorials
---------------------------------------------------------------------------
local CINE = "tutorials-cinematics"
local HelpTipsHideOff = HideOff(CINE)
local function HelpTipsHidden()
	if HelpTipsHideOff() then return true end
	local get = C_CVar and C_CVar.GetCVar
	if type(get) ~= "function" then return true end
	local ok, value = pcall(get, "hideHelptips")
	return not ok or E:IsSecret(value) or type(value) ~= "string"
end
Add({ type = "tab", label = "Cutscenes" })
Switches(options, CINE, {
	skin = { "Skin", E.Key("The \"skip this cutscene?\" dialogs and the tutorial window in the EldoUI look.") },
	hide = { "Turn tutorials off", E.Key("Tutorials and help tips off (game settings; Blizzard default puts yours back).") },
	improve = { "Faster cutscenes", E.Key("Esc skips at once; optional skipping of cutscenes you've seen.") },
})
Add({ type = "toggle", key = "cinematics.tutorials", label = "Tutorials off", desc = "The game's tutorial pop-ups (game setting showTutorials).", hidden = HideOff(CINE) })
Add({ type = "toggle", key = "cinematics.helpTips", label = "Help tips off", desc = "The yellow help tips that point at buttons (game setting, where the client has it).", hidden = HelpTipsHidden })
Add({ type = "toggle", key = "cinematics.escSkip", label = "Esc skips at once", desc = "No \"are you sure\" question after pressing Esc in a cutscene.", hidden = Off(CINE, "improve") })
Add({ type = "toggle", acts = true, key = "cinematics.skipSeen", label = "Skip cutscenes you've seen", desc = "A cutscene or movie you already watched (on any character) is skipped. /eui cutscenes forget plays them again. Off by default.", hidden = Off(CINE, "improve") })
Add({ type = "execute", label = "Forget seen cutscenes", desc = "Every cutscene plays once more.", func = function() M:ForgetSeenCinematics() end, hidden = Off(CINE, "improve") })
-- Skipping acts for the player: listed for the setup's Convenience step and
-- the Conveniences page (Core/Conveniences.lua), off until ticked and never
-- recommended.
E:RegisterConvenience({ id = "skipCutscenes", module = "Notifications", setting = "cinematics.skipSeen", order = 160,
	label = "Skip cutscenes you've seen",
	desc = "Acts for you: skips a cutscene or movie you already watched on any character. Change it later under Alerts and Banners.",
	blocked = function() return E:BlizzardNeedsReason(CINE, "improve") end })

M.options = options

---------------------------------------------------------------------------
-- Style presets
---------------------------------------------------------------------------
E:RegisterStyles("Notifications", {
	{ key = "Default", title = "Default", desc = "Alerts growing down, normal sizes and times.",
		settings = { alerts = { growth = "DOWN", spacing = 4, scale = 1, bannerScale = 1, lane = { width = 300, iconSize = 36, fontSize = 13, max = 4, duration = 5 } },
			talkingHead = { anchor = "lane", scale = 1 }, raidWarning = { scale = 1 }, errors = { scale = 1, fontSize = 0 }, zoneText = { scale = 1 } } },
	{ key = "Minimal", title = "Minimal", desc = "Small toasts, short times, quiet error text.",
		settings = { alerts = { spacing = 2, scale = 0.8, bannerScale = 0.8, hideGlow = true, lane = { width = 240, iconSize = 24, fontSize = 11, max = 3, duration = 3, sound = false } },
			talkingHead = { scale = 0.8 }, errors = { fontSize = 12, duration = 1.5, scale = 0.9 }, zoneText = { scale = 0.8 } } },
	{ key = "Big", title = "Big and bold", desc = "Large toasts, raid warnings and zone text for big screens.",
		settings = { alerts = { spacing = 6, scale = 1.2, bannerScale = 1.1, lane = { width = 380, iconSize = 48, fontSize = 16, max = 5 } },
			talkingHead = { scale = 1.1 }, raidWarning = { scale = 1.25 }, errors = { fontSize = 18, scale = 1.1 }, zoneText = { scale = 1.2 }, popups = { scale = 1.15 } } },
	{ key = "Quiet", title = "Quiet", desc = "Toasts wait until combat ends, no sounds, few at once.",
		settings = { alerts = { lane = { max = 2, duration = 4, sound = false, holdInCombat = true } }, popups = { masterSound = false },
			errors = { mode = "filter", categories = { power = true, cooldown = true, range = true, target = true, facing = false, moving = false, busy = true } } } },
	{ key = "Rising", title = "Rising", desc = "Alerts grow up from their mover, for a lane near the bottom of the screen.",
		settings = { alerts = { growth = "UP", spacing = 4, scale = 1, bannerScale = 1, lane = { width = 300, iconSize = 36, fontSize = 13, max = 4, duration = 5 } } } },
})
