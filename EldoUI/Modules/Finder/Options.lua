-- EldoUI Finder: options and style presets.
local _, E = ...
local L = E.L
local M = E.Finder

local KEYS = {
	[""] = "Not bound",
	["CTRL-SPACE"] = "Ctrl+Space",
	["ALT-SPACE"] = "Alt+Space",
	["SHIFT-SPACE"] = "Shift+Space",
	["CTRL-F"] = "Ctrl+F",
	["CTRL-SHIFT-F"] = "Ctrl+Shift+F",
	["ALT-F"] = "Alt+F",
}
local KEY_ORDER = { "", "CTRL-SPACE", "ALT-SPACE", "SHIFT-SPACE", "CTRL-F", "CTRL-SHIFT-F", "ALT-F" }

-- What the key does in the game now, for the description.
local function KeyNote()
	local key = M.db and M.db.key
	if type(key) ~= "string" or key == "" or not GetBindingAction then return "" end
	local action = GetBindingAction(key)
	if type(action) == "string" and action ~= "" and action ~= "CLICK EldoUIFinderToggle:LeftButton" then
		local name = rawget(_G, "BINDING_NAME_" .. action)
		return " " .. L["While EldoUI is on, this key opens the Finder instead of: %s."]:format(type(name) == "string" and name or action)
	end
	return ""
end

local KIND_ROWS = {
	{ "panel", E.Key("Game panels"), E.Key("Character, spellbook, quest log, map, bags, friends, guild, collections and the other game windows.") },
	{ "setting", "Settings", E.Key("EldoUI's settings (each opens the options search on it) and the game settings browser.") },
	{ "mount", "Mounts", E.Key("Your collected mounts. Your click or Enter on the result summons it.") },
	{ "toy", "Toys", E.Key("The toys the toy box lists. Your click or Enter on the result uses it.") },
	{ "item", E.Key("Bag items"), E.Key("Items in your bags that have a use. Your click or Enter on the result uses it.") },
	{ "macro", "Macros", E.Key("Your account and character macros. Your click or Enter on the result runs it.") },
	{ "place", "Places", E.Key("Zones (opens the world map there) and your EldoUI waypoints.") },
	{ "command", "EldoUI commands", E.Key("Turn modules on or off, and run a typed /eui command.") },
}

M.options = function()
	local options = {
		{ type = "header", label = "Opening" },
		{ type = "description", label = "Open the Finder with your key or /eui go. A result that uses a mount, toy, item or macro needs your click or Enter, out of combat." },
		{ type = "select", key = "key", label = "Key", values = KEYS, order = KEY_ORDER,
			desc = function() return L["The key that opens and closes the Finder. Not bound by default."] .. KeyNote() end },
		{ type = "range", key = "results", label = "Results", min = 3, max = 20, step = 1,
			desc = "How many results the box shows at most." },
		{ type = "toggle", key = "recent", label = "Recent results first",
			desc = "Results you used lately rank higher, and show when the box is empty. Pinned results (right-click) always show first." },
		{ type = "toggle", key = "calculator", label = "Calculator",
			desc = "Typing a sum (\"= 12*35+4\" or \"12*35+4\") shows the answer; a click opens it ready to copy." },
		{ type = "select", key = "fuzzy", label = "Match", order = { "off", "normal", "loose" },
			values = { off = "Exact words only", normal = "Close matches", loose = "Loose matches" },
			desc = "How close a result must be to what you typed. Close matches also find \"swgry\" for Swift Gryphon." },
		{ type = "execute", label = "Clear recent and pinned", confirm = true, desc = "Forgets which results you used and which you pinned.",
			func = function()
				wipe(M.db.recents)
				wipe(M.db.pinned)
				if E.ConfigNotice then E:ConfigNotice(L["Recent and pinned results cleared."]) end
			end },
		{ type = "header", label = "What it searches" },
	}
	for _, row in ipairs(KIND_ROWS) do
		options[#options + 1] = { type = "toggle", key = "kinds." .. row[1], label = row[2], desc = row[3] }
	end
	-- Kinds added by other modules and plugins.
	for _, kind in ipairs(M.providerOrder) do
		local provider = M.providers[kind]
		local known = false
		for _, row in ipairs(KIND_ROWS) do if row[1] == kind then known = true end end
		if not known and provider.option and kind ~= "calc" then
			options[#options + 1] = { type = "toggle", key = "kinds." .. kind, label = provider.label,
				desc = L["Results from %s."]:format(L[provider.label]) }
		end
	end
	local look = {
		{ type = "header", label = "Look" },
		{ type = "range", unit = "px", key = "width", label = "Width", min = 360, max = 1000, step = 10, desc = "Width of the search box and its results." },
		{ type = "range", unit = "px", key = "rowHeight", label = "Row height", min = 18, max = 48, step = 1, desc = "Height of one result row." },
		{ type = "range", key = "fontSize", label = "Search text size", min = 12, max = 24, step = 1, desc = "Size of the text you type." },
		{ type = "toggle", key = "icons", label = "Icons", desc = "The icon of each result on the left of its row." },
		{ type = "toggle", key = "kindLabels", label = "Kind labels", desc = "Panel, Setting, Mount and the other kinds on the right of each row." },
		{ type = "toggle", key = "subtitles", label = "Second line", desc = "A short note under or after the result (the settings page, a macro's kind, a stack size)." },
		{ type = "toggle", key = "dim", label = "Dim the screen", desc = "The game dims behind the open box; a click on the dimmed area closes it." },
		{ type = "toggle", key = "transparent", label = "See-through background", desc = "The box lets the game show through a little. How much: General > Panel opacity.",
			hidden = function() return M.db.panelStyle ~= "theme" end },
		{ type = "select", key = "panelStyle", label = "Panel look",
			values = function()
				local values = { theme = L["Like the rest of EldoUI"] }
				for key, title in pairs(E:ArtStyleValues()) do values[key] = title end
				return values
			end,
			desc = "The box in the general art style, or in one of the other art styles." },
	}
	for _, row in ipairs(look) do options[#options + 1] = row end
	return options
end

-- Look only: no style writes a position, a key or what is searched.
E:RegisterStyles("Finder", {
	{ key = "Spotlight", title = "Spotlight", desc = "A large search line with the screen dimmed behind it.",
		settings = { width = 620, rowHeight = 32, fontSize = 18, results = 8, icons = true, kindLabels = true, subtitles = true, dim = true, transparent = false, panelStyle = "theme" } },
	{ key = "TopBar", title = "Top bar", desc = "A wide, flat bar with short single-line rows.",
		settings = { width = 900, rowHeight = 24, fontSize = 14, results = 6, icons = true, kindLabels = true, subtitles = true, dim = false, transparent = true, panelStyle = "theme" } },
	{ key = "Compact", title = "Compact", desc = "A narrow box with small rows and no second line.",
		settings = { width = 420, rowHeight = 22, fontSize = 13, results = 6, icons = true, kindLabels = false, subtitles = false, dim = false, transparent = false, panelStyle = "theme" } },
	{ key = "Large", title = "Large", desc = "Big rows and text that read well from a distance.",
		settings = { width = 760, rowHeight = 40, fontSize = 22, results = 10, icons = true, kindLabels = true, subtitles = true, dim = true, transparent = false, panelStyle = "theme" } },
	{ key = "Forever", title = "Forever bronze", desc = "The box in the WoW Forever bronze frame, whatever your general art style.",
		settings = { width = 600, rowHeight = 30, fontSize = 16, results = 8, icons = true, kindLabels = true, subtitles = true, dim = false, transparent = false, panelStyle = "Forever" } },
	{ key = "Minimal", title = "Minimal", desc = "Text only: no icons, kind labels or second line, see-through.",
		settings = { width = 520, rowHeight = 24, fontSize = 15, results = 8, icons = false, kindLabels = false, subtitles = false, dim = false, transparent = true, panelStyle = "theme" } },
})
