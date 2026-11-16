-- EldoUI Legacy Planner: options page and style presets.
local _, E = ...
local L = E.L
local M = E.Legacy

local function BlizzardReason()
	if not E:BlizzardAllowed("legacy-achievements", "improve") then
		return L["Turn on \"Let EldoUI change this\" and Improve for the Legacy window under Blizzard UI"]
	end
end

local function CharactersReason()
	if not (E.Characters and E.Characters.Recording and E.Characters:Recording()) then
		return L["Turn on the Alts module first"]
	end
end

M.options = {
	{ type = "description", label = L["Plan your Legacy points, keep named profiles for your characters and browse Legacy Challenges. You spend points in Blizzard's Legacy window."] },
	{ type = "header", label = L["Planner"] },
	{ type = "execute", label = L["Open the Legacy Planner"], desc = L["Shows the planner window (also /eui legacy)."], testSafe = true,
		func = function() M:OpenPlanner() end },
	{ type = "range", unit = "px", key = "rowHeight", label = L["Row height"], min = 18, max = 28, step = 1, desc = L["Height of a node or profile row; challenge rows grow with it."] },
	{ type = "toggle", key = "showIcons", label = L["Node icons"], desc = L["Shows each Legacy node's icon in front of its name on the Build page."] },
	{ type = "toggle", key = "transparent", label = L["See-through window"], desc = L["The planner lets the game show through a little. How much: General > Panel opacity."] },
	{ type = "select", key = "challengeStatus", label = L["Challenges shown"], desc = L["Which Legacy Challenges the Challenges page lists when it opens; its filter chips change this too."],
		values = { all = L["All"], progress = L["In progress"], new = L["Not started"], done = L["Done"] } },
	{ type = "header", label = L["Blizzard's Legacy window"] },
	{ type = "toggle", key = "blizzButton", label = L["Planner button"], desc = L["A Planner button on Blizzard's Legacy window that opens this planner beside it."], disabled = BlizzardReason },
	{ type = "toggle", key = "openWithBlizzard", label = L["Open with the Legacy window"], desc = L["Opens the planner beside Blizzard's Legacy window whenever that window opens, and closes it again with it."], disabled = BlizzardReason },
	{ type = "execute", label = L["Open Blizzard UI switches"], desc = L["Turn on Improve for the Legacy window here to dock the planner beside Blizzard's window."],
		func = function() E:ToggleConfig("blizzard") end },
	{ type = "header", label = L["Alts"] },
	{ type = "toggle", key = "recordAlts", label = L["Record Legacy points for alts"], desc = L["Saves each character's spent and owned Legacy points at login, for the Legacy column in the Alts window (pick it with Columns)."], disabled = CharactersReason },
}

E:RegisterStyles("Legacy", {
	{ key = "Modern", title = L["Modern"], desc = L["Medium rows with node icons."],
		settings = { rowHeight = 22, showIcons = true, transparent = false } },
	{ key = "Compact", title = L["Compact"], desc = L["Small rows, more nodes on screen."],
		settings = { rowHeight = 18, showIcons = true, transparent = false } },
	{ key = "Large", title = L["Large"], desc = L["Tall rows and big icons, easy to read."],
		settings = { rowHeight = 28, showIcons = true, transparent = false } },
	{ key = "Glass", title = L["Glass"], desc = L["A see-through window over the game."],
		settings = { rowHeight = 22, showIcons = true, transparent = true } },
	{ key = "Clean", title = L["Clean"], desc = L["No icons: names and ranks only."],
		settings = { rowHeight = 20, showIcons = false, transparent = false } },
	{ key = "Minimal", title = L["Minimal"], desc = L["Small rows, no icons, see-through."],
		settings = { rowHeight = 18, showIcons = false, transparent = true } },
})
