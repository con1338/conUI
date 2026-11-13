-- EldoUI Macros: options and style presets.
local _, E = ...
local L = E.L
local M = E.Macros

M.options = {
	{ type = "description", label = "Open the editor with /eui macros, Edit in EldoUI in Blizzard's macro window, or the button below. Saving waits for out of combat." },
	{ type = "execute", label = "Open the editor", desc = "Opens the EldoUI macro editor at Blizzard's selected macro, or at your first macro.",
		func = function() M:OpenEditor() end },
	{ type = "toggle", key = "autoOpen", label = "Open with Blizzard's macro window",
		desc = "The EldoUI editor opens and closes together with Blizzard's macro window, and follows its selection. Off: open it with the Edit in EldoUI button." },
	{ type = "header", label = "Check" },
	{ type = "select", key = "warnings", label = "Show", order = { "all", "errors" },
		values = { all = "Problems and warnings", errors = "Problems only" },
		desc = "Problems (unmatched brackets, too long) stop a macro from working. Warnings name a command, condition, spell or item the game does not know right now; a spell you learn later is fine." },
	{ type = "toggle", key = "colors", label = "Colored check view",
		desc = "Known commands in the accent color, conditions dimmed, unknown words in orange and broken lines in red." },
	{ type = "toggle", key = "lineNumbers", label = "Line numbers",
		desc = "Numbers in front of each line of the check view, so a warning points at its line." },
	{ type = "toggle", key = "chips", label = "Condition builder",
		desc = "The row of conditions under the text ([@mouseover], [mod:shift], [nocombat] and more). A click puts one at the cursor, into the bracket you are in." },
	{ type = "header", label = "Look" },
	{ type = "media", mediaKind = "font", key = "font", label = "Font", default = "THEME", defaultLabel = "Theme font",
		desc = "Font of the macro text and the check view. A mono font lines up brackets and conditions." },
	{ type = "range", key = "fontSize", label = "Text size", min = 10, max = 20, step = 1,
		desc = "Size of the macro text and the check view." },
	{ type = "toggle", key = "transparent", label = "See-through window",
		desc = "The editor lets the game show through a little. How much: General > Panel opacity." },
}

-- Look only: no style writes a position or what the editor checks.
E:RegisterStyles("Macros", {
	{ key = "Code", title = "Code", desc = "A mono font with colors and line numbers, like a code editor.",
		settings = { font = "JetBrains Mono", fontSize = 13, colors = true, lineNumbers = true, chips = true, transparent = false } },
	{ key = "Theme", title = "Theme", desc = "The theme font, colors and line numbers.",
		settings = { font = "THEME", fontSize = 13, colors = true, lineNumbers = true, chips = true, transparent = false } },
	{ key = "Large", title = "Large text", desc = "Bigger text in a mono font that reads well from a distance.",
		settings = { font = "IBM Plex Mono", fontSize = 17, colors = true, lineNumbers = true, chips = true, transparent = false } },
	{ key = "Plain", title = "Plain", desc = "No colors or line numbers: only the text and the hints.",
		settings = { font = "THEME", fontSize = 13, colors = false, lineNumbers = false, chips = true, transparent = false } },
	{ key = "Compact", title = "Compact", desc = "Small mono text, no condition builder, see-through.",
		settings = { font = "Fira Mono", fontSize = 11, colors = true, lineNumbers = false, chips = false, transparent = true } },
})
