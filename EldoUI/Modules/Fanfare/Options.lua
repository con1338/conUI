-- Fanfare options: a General tab for the look, and a Triggers tab that
-- edits one trigger at a time (pick it at the top, then "When", "Only if"
-- and what happens). Rows use a key function, so they always edit the
-- trigger that is picked.
local _, E = ...
local L = E.L

local Key = E.Key
local F = E.fanfare
local M = F.module

local function Editing()
	local id = M.db and M.db.editing
	if id and M.db.triggers[id] and not M.db.triggers[id].deleted then return id end
	local first = M:Triggers()[1]
	if M.db then M.db.editing = first end
	return first
end

local function Trigger()
	local id = Editing()
	return id and M.db.triggers[id]
end

-- Key into the picked trigger.
local function K(path)
	return function() return "triggers." .. (Editing() or "none") .. "." .. path end
end

local function NoTrigger() return Trigger() == nil end

-- Hide a row when there is no trigger or the source doesn't use it.
local function Needs(condition)
	return function()
		local trigger = Trigger()
		return not trigger or not F:SourceAllows(trigger.source, condition)
	end
end

local function Off(action)
	return function()
		local trigger = Trigger()
		return not trigger or not trigger.actions[action].enabled
	end
end

local function TokenHelp()
	local trigger = Trigger()
	local tokens = { "{name}", "{player}", "{level}", "{zone}", "{subzone}", "{class}" }
	local source = trigger and F.sources[trigger.source]
	for _, token in ipairs(source and source.tokens or {}) do
		local text = "{" .. token .. "}"
		if not tContains(tokens, text) then table.insert(tokens, 1, text) end
	end
	return L["Text shown big on screen. Fills in: %s"]:format(table.concat(tokens, " "))
end

local function TriggerValues()
	local values = {}
	for _, id in ipairs(M:Triggers()) do
		local trigger = M.db.triggers[id]
		local state = trigger.enabled and "" or " " .. E:TextHex("secondary") .. L["(off)"] .. "|r"
		values[id] = ("%s " .. E:TextHex("secondary") .. "· %s|r%s"):format(E:Translate(trigger.name), L[trigger.group], state)
	end
	return values
end

local function GroupValues()
	local values = {}
	for _, group in ipairs(F.groupOrder) do values[group] = group end
	values.Custom = "Custom"
	for _, id in ipairs(M:Triggers()) do
		local group = M.db.triggers[id].group
		values[group] = group
	end
	return values
end

local ANY = { any = "Any" }
local function With(extra)
	local values = CopyTable(ANY)
	for k, v in pairs(extra) do values[k] = v end
	return values
end

local COLOR_MODES = {
	accent = "Accent color", quality = "Item quality", class = "Class color", whisper = "Whisper pink",
	success = "Green (success)", warn = "Yellow (warning)", danger = "Red (danger)", white = "White", custom = "Custom color",
}
local QUALITIES = { [0] = "Any", [2] = "Uncommon+", [3] = "Rare+", [4] = "Epic+", [5] = "Legendary" }
local CHANNELS = function()
	local values = { default = "Module default" }
	for k, v in pairs(E.soundChannels) do values[k] = v end
	return values
end

local function Refresh()
	M:Rebuild()
	E:RefreshConfig()
end

M.options = {
	{ type = "tab", label = "General" },
	{ type = "description", label = "Sounds, big text, flashes and icon pops for moments in the game: \"When\", \"Only if\" and what to do. Off by default: turn it on under Modules." },
	{ type = "header", label = "Sound" },
	{ type = "toggle", key = "mute", label = "Mute Fanfare", desc = "Silences every trigger's sound (texts and flashes still show). Also /eui fx mute." },
	{ type = "select", key = "channel", label = "Sound channel", desc = "Volume channel for triggers set to Module default. Default follows the general sound channel.", values = function()
		local values = { default = "General setting" }
		for k, v in pairs(E.soundChannels) do values[k] = v end
		return values
	end },
	{ type = "range", unit = "s", key = "soundGap", label = "Gap between sounds", min = 0, max = 2, step = 0.05, desc = "Minimum seconds between two trigger sounds, so a burst of events plays one sound." },
	{ type = "header", label = "Big text" },
	{ type = "media", mediaKind = "font", key = "splash.font", label = "Font", desc = "Font for the big text. Triggers can pick their own." },
	{ type = "range", key = "splash.size", label = "Size", min = 24, max = 96, step = 1, desc = "Text size. Some layouts cap it so it doesn't cover your frames (Cozy 52, Plates 44)." },
	{ type = "select", key = "splash.outline", label = "Outline", values = { [""] = "None", OUTLINE = "Thin", THICKOUTLINE = "Thick" }, desc = "Outline around the big text, so it reads on any background." },
	{ type = "range", key = "splash.hold", label = "Show for", unit = "s", min = 0.5, max = 4, step = 0.1, desc = "How long the text stays before it fades." },
	{ type = "select", key = "splash.anim", label = "Animation", values = { pop = "Pop", slide = "Slide", bounce = "Bounce", none = "None" }, desc = "How the text appears. With Animations off (General page) it just shows." },
	{ type = "toggle", key = "splash.banner", label = "Banner behind text", desc = "A panel behind the text in your art style." },
	{ type = "range", unit = "px", key = "splash.width", label = "Width", min = 320, max = 900, step = 10, desc = "Width of the text area. Long text shrinks to fit." },
	{ type = "range", key = "queueMax", label = "Texts waiting", min = 1, max = 5, step = 1, desc = "How many texts can wait while one shows. Extra ones are skipped." },
	{ type = "header", label = "Flash and icon" },
	{ type = "select", key = "flash.style", label = "Flash style", values = { edges = "Screen edges", vignette = "Soft vignette", full = "Whole screen (faint)", off = "Off" }, desc = "How triggers with a flash light up the screen. Capped for comfort: at most one flash every half second." },
	{ type = "range", percent = true, key = "flash.alpha", label = "Flash strength", min = 0.05, max = 0.6, step = 0.05, desc = "How strong the flash is." },
	{ type = "range", unit = "px", key = "icon.size", label = "Icon size", min = 32, max = 96, step = 2, desc = "Size of the icon that pops next to the text." },
	{ type = "toggle", key = "combatGimmicks", label = "Visuals in combat", desc = "Show texts, flashes and icons in combat for every trigger. When off, only triggers that allow it (ready check, queue pop, pull) show in combat. Sounds always play." },
	{ type = "header", label = "Try it" },
	{ type = "execute", label = "Test text", desc = "Shows the level-up trigger with sample values.", func = function() M:Test("levelup") end },
	{ type = "execute", label = "Test flash", desc = "Flashes the screen edges once.", func = function() E:ScreenFlash(E.media.accentColor, M.db.flash.alpha, M.db.flash.duration, M.db.flash.style ~= "off" and M.db.flash.style or "edges") end },
	{ type = "execute", label = "Move text", desc = "Drag the big text where you want it.", func = function() E:MoveFrame("EldoUI_Fanfare") end },

	{ type = "tab", label = "Triggers" },
	{ type = "select", key = "editing", label = "Trigger", desc = "The trigger to edit below. (off) marks switched-off ones.", values = TriggerValues },
	{ type = "execute", label = "New", width = 90, desc = "Make a new trigger.", func = function() M:NewTrigger(); Refresh() end },
	{ type = "execute", label = "Duplicate", width = 90, desc = "Copy this trigger.", func = function() if Editing() then M:DuplicateTrigger(Editing()); Refresh() end end },
	{ type = "execute", label = "Delete", width = 90, confirm = Key("Delete this trigger? Built-in ones come back with Restore built-ins."), desc = "Remove this trigger. Built-in ones come back with Restore built-ins.", func = function() if Editing() then M:DeleteTrigger(Editing()); Refresh() end end },
	{ type = "execute", label = "Test", width = 90, desc = "Play this trigger now with sample values, ignoring its conditions.", func = function() if Editing() then M:Test(Editing()) end end },
	{ type = "execute", label = "Up", width = 60, desc = "Move up in the list.", func = function() if Editing() then M:MoveTrigger(Editing(), -1); Refresh() end end },
	{ type = "execute", label = "Down", width = 60, desc = "Move down in the list.", func = function() if Editing() then M:MoveTrigger(Editing(), 1); Refresh() end end },
	{ type = "execute", label = "Restore built-ins", width = 140, confirm = true, desc = "Bring back every built-in trigger as shipped. Your own triggers stay.", func = function() M:RestoreBuiltins(); Refresh() end },

	{ type = "header", label = "Trigger", hidden = NoTrigger },
	{ type = "input", key = K("name"), label = "Name", hidden = NoTrigger, desc = "Name in the list and the {name} token." },
	{ type = "select", key = K("group"), label = "Group", hidden = NoTrigger, values = GroupValues, desc = "Sorts the trigger list." },
	{ type = "toggle", key = K("enabled"), label = "Use this trigger", hidden = NoTrigger, desc = "Switch this trigger on or off." },
	{ type = "range", key = K("cooldown"), label = "Cooldown", unit = "s", min = 0, max = 300, step = 1, hidden = NoTrigger, desc = "After firing, the trigger waits this long before it can fire again." },
	{ type = "select", key = K("source"), label = "When", hidden = NoTrigger, values = function() return F:SourceValues() end,
		desc = "The moment that fires the trigger. You can pick from things the game tells you, like loot, level-ups, whispers and achievements. Enemy casts and health aren't on the list." },
	{ type = "toggle", key = K("allowInCombat"), label = "Visuals in combat", hidden = NoTrigger, desc = "Show this trigger's text, flash and icon in combat too. Sounds always play." },

	{ type = "header", label = "Only if", hidden = NoTrigger },
	{ type = "select", key = K("conditions.instance"), label = "Where", hidden = NoTrigger, desc = "Only in this kind of place.",
		values = With({ world = "Open world", anyInstance = "Any instance", dungeon = "Dungeon", raid = "Raid", pvp = "Battleground", arena = "Arena", scenario = "Scenario" }) },
	{ type = "select", key = K("conditions.combat"), label = "Combat", hidden = NoTrigger, desc = "Only in or out of combat.", values = With({ ["in"] = "In combat", out = "Out of combat" }) },
	{ type = "select", key = K("conditions.group"), label = "Group", hidden = NoTrigger, desc = "Only solo, in a party or in a raid.", values = With({ solo = "Solo", party = "Party", raid = "Raid", grouped = "Party or raid" }) },
	{ type = "select", key = K("conditions.resting"), label = "Resting", hidden = NoTrigger, desc = "Only while resting (inn, city) or not.", values = With({ yes = "Resting", no = "Not resting" }) },
	{ type = "select", key = K("conditions.mounted"), label = "Mounted", hidden = NoTrigger, desc = "Only while mounted or not.", values = With({ yes = "Mounted", no = "Not mounted" }) },
	{ type = "input", key = K("conditions.zone"), label = "Zone contains", hidden = NoTrigger, desc = "Only in zones whose name contains one of these words (comma separated). Empty: anywhere." },
	{ type = "select", key = K("conditions.minQuality"), label = "Item quality", hidden = Needs("minQuality"), values = QUALITIES, desc = "Only items of this quality or better." },
	{ type = "input", key = K("conditions.sender"), label = "From", hidden = Needs("sender"), desc = "Only from these players (comma separated), or the words friends / guild. Empty: anyone. During boss fights the sender is hidden and this check doesn't fire." },
	{ type = "select", key = K("conditions.who"), label = "Who", hidden = Needs("who"),
		values = { friends = "Friends", guild = "Guild members", both = "Friends and guild members" },
		desc = "Whose coming online fires the trigger: people on your friend list (the default), members of your guild, or both. Read from the friend list and guild roster, never from the chat line." },
	{ type = "range", key = K("conditions.minLevel"), label = "From level", min = 0, max = 80, step = 1, hidden = NoTrigger, zeroText = "Any", desc = "Only from this character level." },
	{ type = "range", key = K("conditions.maxLevel"), label = "Up to level", min = 0, max = 80, step = 1, hidden = NoTrigger, zeroText = "Any", desc = "Only up to this character level." },
	{ type = "range", key = K("conditions.chance"), label = "Chance", unit = "%", min = 1, max = 100, step = 1, hidden = NoTrigger, desc = "Fire only this often, for jokes that shouldn't play every time." },

	{ type = "header", label = "Sound", hidden = NoTrigger },
	{ type = "media", mediaKind = "sound", key = K("actions.sound.id"), label = "Play", none = true, allowCustom = true, channel = K("actions.sound.channel"), hidden = NoTrigger,
		desc = "Sound to play. EldoUI's own, the game's, or any SharedMedia pack you have installed. Custom takes a file ID or an addon path." },
	{ type = "select", key = K("actions.sound.channel"), label = "Channel", hidden = NoTrigger, values = CHANNELS, desc = "Volume channel for this sound." },
	{ type = "media", mediaKind = "sound", key = K("actions.sound.fallback"), label = "If missing, play", none = true, channel = K("actions.sound.channel"), hidden = NoTrigger,
		desc = "Played instead when the first sound's addon is not installed." },

	{ type = "header", label = "Big text", hidden = NoTrigger },
	{ type = "toggle", key = K("actions.splash.enabled"), label = "Show text", hidden = NoTrigger, desc = "Show big text in the middle of the screen." },
	{ type = "input", key = K("actions.splash.text"), label = "Text", hidden = Off("splash"), desc = TokenHelp },
	{ type = "input", key = K("actions.splash.sub"), label = "Second line", hidden = Off("splash"), desc = "Smaller gray line under the text. Same tokens." },
	{ type = "select", key = K("actions.splash.colorMode"), label = "Color", hidden = Off("splash"), values = COLOR_MODES, desc = "Color of the text. Item quality fits loot, accent fits your own progress." },
	{ type = "color", key = K("actions.splash.color"), label = "Custom color", hidden = function() local t = Trigger(); return not t or not t.actions.splash.enabled or t.actions.splash.colorMode ~= "custom" end, desc = "Used when the color is Custom color." },
	{ type = "media", mediaKind = "font", key = K("actions.splash.font"), label = "Font", default = "default", hidden = Off("splash"), desc = "Font for this trigger. Module default uses the General tab's font." },
	{ type = "range", key = K("actions.splash.size"), label = "Size", min = 0, max = 120, step = 1, hidden = Off("splash"), zeroText = "General", desc = "Text size for this trigger. General uses the General tab's size." },
	{ type = "range", key = K("actions.splash.hold"), label = "Show for", unit = "s", min = 0, max = 6, step = 0.1, hidden = Off("splash"), zeroText = "General", desc = "How long the text stays. General uses the General tab's time." },
	{ type = "select", key = K("actions.splash.anim"), label = "Animation", hidden = Off("splash"), values = { default = "Module default", pop = "Pop", slide = "Slide", bounce = "Bounce", none = "None" }, desc = "How the text appears." },

	{ type = "header", label = "Flash, icon, chat and screenshot", hidden = NoTrigger },
	{ type = "toggle", key = K("actions.flash.enabled"), label = "Screen flash", hidden = NoTrigger, desc = "Flash the screen once. Keep it for things that need attention now." },
	{ type = "select", key = K("actions.flash.colorMode"), label = "Flash color", hidden = Off("flash"), values = COLOR_MODES, desc = "Item quality and class color follow what fired the trigger." },
	{ type = "select", key = K("actions.flash.style"), label = "Flash style", hidden = Off("flash"), values = { default = "Module default", edges = "Screen edges", vignette = "Soft vignette", full = "Whole screen (faint)" }, desc = "Shape of the flash." },
	{ type = "toggle", key = K("actions.icon.enabled"), label = "Icon pop", hidden = NoTrigger, desc = "Pop an icon next to the text (or alone when there is no text)." },
	{ type = "input", key = K("actions.icon.texture"), label = "Icon", hidden = Off("icon"), desc = "Leave it on auto to use the item, achievement or event icon. Advanced: enter an icon's file ID instead." },
	{ type = "toggle", key = K("actions.chat.enabled"), label = "Chat message (only you see it)", hidden = NoTrigger, desc = "Print a line in your own chat window. Nothing is ever sent to other players." },
	{ type = "input", key = K("actions.chat.text"), label = "Chat text", hidden = Off("chat"), desc = TokenHelp },
	{ type = "toggle", key = K("actions.screenshot.enabled"), label = "Take a screenshot", hidden = NoTrigger,
		desc = "Saves a screenshot half a second after the trigger fires, with its text and icon in the picture (at most one every 10 seconds). Off by default; saved to the game's Screenshots folder." },

	{ type = "tab", label = "Share" },
	{ type = "description", label = "Export every trigger and setting as a text string, or import one. Triggers hold no code, only picks from the same lists." },
	{ type = "execute", label = "Export Fanfare", desc = "All triggers and settings of this module.", func = function() E:ShowExport("module:Fanfare") end },
	{ type = "execute", label = "Import", desc = "Paste an EldoUI string.", func = function() E:ShowImport() end },
}
