-- EldoUI Hardcore: options page and style presets.
local _, E = ...
local L = E.L
local M = E.Hardcore

local NotHardcore = M.NotHardcoreReason
local function AlertsOff() return not M.db.alerts end
local function PvPOff() return not (M.db.pvpTarget or M.db.pvpSelf) end

M.options = {
	{ type = "description", label = "On a character that is not Hardcore the module does nothing. Messages go out only when you click Tell the guild." },
	{ type = "description", label = "This character is not on a Hardcore realm, so these options do nothing here.", hidden = function() return M.IsHardcore() end },
	{ type = "tab", label = "Deaths" },
	{ type = "header", label = "Death alerts" },
	{ type = "toggle", key = "alerts", label = "Enable", disabled = NotHardcore,
		desc = "A card in the alert lane when someone dies. The game decides which deaths it announces (its own Hardcore death alert setting: guild or all)." },
	{ type = "select", key = "alertScope", label = "Alert for", values = { guild = "Guild and group", group = "Group only", all = "Every announced death" },
		order = { "guild", "group", "all" }, hidden = AlertsOff, disabled = NotHardcore,
		desc = "Whose deaths get a card. The log keeps every announced death either way." },
	{ type = "media", mediaKind = "sound", none = true, key = "alertSound", label = "Alert sound", hidden = AlertsOff, disabled = NotHardcore,
		desc = "Played with each death card." },
	{ type = "header", label = "Your own death" },
	{ type = "toggle", key = "ownCard", label = "Tell the guild card", disabled = NotHardcore,
		desc = "After you die, a card with a Tell the guild button. One click writes one line about your death in guild chat; nothing is sent without it." },
	{ type = "toggle", key = "tellAddon", label = "Include an EldoUI note", hidden = function() return not M.db.ownCard end, disabled = NotHardcore,
		desc = "The same click also sends one addon message to the guild, so guild members' EldoUI logs your class, level, zone and cause." },
	{ type = "toggle", key = "listen", label = "Log guild notes", disabled = NotHardcore,
		desc = "Log the deaths guild members tell the guild about with EldoUI. Notes are accepted from guild members only and never answered." },
	{ type = "header", label = "Death log" },
	{ type = "range", key = "logMax", label = "Entries kept", min = 50, max = 1000, step = 50,
		desc = "The oldest entries go first when the log is full. The log is shared by all your characters." },
	{ type = "execute", label = "Open the death log", func = function() M:Open() end,
		disabled = function()
			if not M.active then return E:ModuleOffNote("Hardcore") end
			if InCombatLockdown() then return L["Opens after combat."] end
		end,
		desc = "Open the Death Log window. /eui deaths does the same." },
	{ type = "toggle", key = "zoneNote", label = "Deaths near your level", disabled = NotHardcore,
		desc = "On entering a zone, show one notice when your log contains at least ten deaths within three levels of you. Once per zone per session, outside combat and instances. Off by default." },
	{ type = "tab", label = "Warnings" },
	{ type = "header", label = "PvP flag" },
	{ type = "toggle", key = "pvpTarget", label = "Warn on a flagged target", disabled = NotHardcore,
		desc = "A warning when your target is flagged for PvP and attacking it (a player or a guard) or healing and buffing it (a player) would flag you too." },
	{ type = "toggle", key = "pvpSelf", label = "Warn when you get flagged", disabled = NotHardcore,
		desc = "A warning when you become flagged for PvP yourself." },
	{ type = "media", mediaKind = "sound", none = true, key = "pvpSound", label = "Warning sound", hidden = PvPOff, disabled = NotHardcore,
		desc = "Played with each PvP warning." },
	{ type = "header", label = "Rules" },
	{ type = "toggle", key = "reminders", label = "Self-Found reminders", disabled = NotHardcore,
		desc = "A short notice at the mailbox, the auction house and the trade window while the game reports Self-Found for this character." },
	{ type = "tab", label = "Look" },
	{ type = "header", label = "Cards" },
	{ type = "select", key = "alertTitle", label = "Card title color", values = { bad = "Red", accent = "Accent color", plain = "Plain" },
		order = { "bad", "accent", "plain" }, desc = "The color of the title on death cards and warnings." },
	{ type = "header", label = "Death log window" },
	{ type = "range", unit = "px", key = "rowHeight", label = "Row height", min = 16, max = 28, step = 1, desc = "Height of each row in the death log." },
	{ type = "toggle", key = "classColors", label = "Class colors", desc = "Names in their class color, when the class is known." },
	{ type = "toggle", key = "transparent", label = "See-through window", desc = "The death log window lets the game show through a little. How much: General > Panel opacity." },
}

local function Settings(base)
	local out = {
		alerts = true, alertTitle = "bad", alertSound = "eldo:EldoWarning", pvpSound = "eldo:EldoAlarm",
		reminders = true, rowHeight = 20, classColors = true, transparent = false,
	}
	for key, value in pairs(base) do out[key] = value end
	return out
end

E:RegisterStyles("Hardcore", {
	{ key = "Stark", title = L["Stark"], desc = L["Red titles, an alarm for PvP and a warning tone for deaths."],
		settings = Settings({}) },
	{ key = "Quiet", title = L["Quiet"], desc = L["Cards in plain colors and no sounds."],
		settings = Settings({ alertTitle = "plain", alertSound = "none", pvpSound = "none" }) },
	{ mode = true, key = "LogOnly", title = L["Log only"], desc = L["No death cards: deaths go to the log. PvP warnings stay, without sound."],
		settings = Settings({ alerts = false, alertTitle = "plain", alertSound = "none", pvpSound = "none" }) },
	{ key = "ForeverBronze", title = L["Forever bronze"], desc = L["Titles in your accent color (warm sand under the WoW Forever art style) and a soft chime."],
		settings = Settings({ alertTitle = "accent", alertSound = "eldo:EldoChime" }) },
	{ key = "Minimal", title = L["Minimal"], desc = L["Only PvP warnings and your own death card; a compact, see-through log."],
		settings = Settings({ alerts = false, reminders = false, alertTitle = "plain", alertSound = "none", rowHeight = 18, transparent = true }) },
})
