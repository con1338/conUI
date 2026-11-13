-- EldoUI Talent Planner: options page and style presets.
local _, E = ...
local L = E.L
local M = E.Talents

local function BlizzardReason()
	if not E:BlizzardAllowed("player-spells", "improve") then
		return L["Turn on \"Let EldoUI change this\" and Improve for Spellbook and talents under Blizzard UI"]
	end
end

M.options = {
	{ type = "description", label = L["Plan your talents level by level, for your class or another. A talent is learned only when you click Learn, never on its own."] },
	{ type = "header", label = L["Planner"] },
	{ type = "execute", label = L["Open the Talent Planner"], desc = L["Shows the planner window (also /eui talents, a key binding, the Spec block on the Info Bar with Shift-click, and the Menu block)."], testSafe = true,
		func = function() M:OpenPlanner() end },
	{ type = "toggle", key = "showGuide", label = L["Level guide"], desc = L["A slider under the trees that shows your plan as it stands at any level."] },
	{ type = "toggle", key = "showOrder", label = L["Pick order numbers"], desc = L["A small number on each talent of your plan: which of the plan's points takes it first. The talent's tooltip lists every point. Also shown on Blizzard's talent window while Show my plan is on."] },
	{ type = "cog", label = L["More look settings"], desc = L["Talent size, prerequisite arrows, ability marks and a see-through window."], options = {
		{ type = "range", key = "tileSize", label = L["Talent size"], min = 24, max = 48, step = 2, desc = L["Largest size of a talent icon; small screens and long trees shrink it to fit."] },
		{ type = "toggle", key = "showArrows", label = L["Prerequisite arrows"], desc = L["Lines from a talent to the talents that need it at full rank."] },
		{ type = "toggle", key = "guideMarkers", label = L["Ability marks"], desc = L["Small marks on the level guide where your plan gets a new ability (not a passive talent)."], dependsOn = "showGuide" },
		{ type = "toggle", key = "transparent", label = L["See-through window"], desc = L["The window lets the game show through a little. How much: General > Panel opacity."] },
	} },
	{ type = "header", label = L["Learning"] },
	{ type = "toggle", key = "confirmNewTree", label = L["Ask before a new tree"], desc = L["Asks once more when Learn would put your first point into a tree you have no points in."] },
	{ type = "media", key = "learnSound", label = L["Sound when learned"], mediaKind = "sound", none = true, desc = L["Plays when the game confirms a talent you learned from the planner."] },
	{ type = "header", label = L["Reminders"] },
	{ type = "toggle", key = "levelUpToast", label = L["On level-up"], desc = L["On level-up, one card lists what the level brings: your talent point, new spell ranks, class quests, gear and dungeons, each a link. Nothing is spent unless you click."] },
	{ type = "toggle", key = "loginToast", label = L["At login"], desc = L["At login, a reminder when you have unspent points and your plan says where they go."] },
	{ type = "header", label = L["Blizzard's talent window"] },
	{ type = "description", hidden = function() return M:BlizzardRowHint() == nil end,
		label = function() return M:BlizzardRowHint() or "" end },
	{ type = "toggle", key = "blizzOverlay", label = L["Show my plan"], desc = L["Marks your plan's ranks on Blizzard's talent buttons, with a ring on the next point."], disabled = BlizzardReason },
	{ type = "toggle", key = "blizzButton", label = L["Planner and build buttons"], desc = L["Adds Planner, Import build and, for classes with suggested paths, Recommended build to Blizzard's talent page. They only save plans; nothing is learned."], disabled = BlizzardReason },
	{ type = "execute", label = L["Open Blizzard UI switches"], desc = L["Turn on Improve for Spellbook and talents here to see your plan on Blizzard's talent window."],
		func = function() E:ToggleConfig("blizzard") end },
}

E:RegisterStyles("Talents", {
	{ key = "Modern", title = L["Modern"], desc = L["Medium talents, arrows, the level guide with ability marks."],
		settings = { tileSize = 36, showOrder = true, showArrows = true, showGuide = true, guideMarkers = true, transparent = false } },
	{ key = "Compact", title = L["Compact"], desc = L["Smaller talents and no level guide, for small screens."],
		settings = { tileSize = 28, showOrder = true, showArrows = true, showGuide = false, guideMarkers = false, transparent = false } },
	{ key = "Large", title = L["Large"], desc = L["Big talents, easy to read."],
		settings = { tileSize = 46, showOrder = true, showArrows = true, showGuide = true, guideMarkers = true, transparent = false } },
	{ key = "Glass", title = L["Glass"], desc = L["A see-through window over the game."],
		settings = { tileSize = 36, showOrder = true, showArrows = true, showGuide = true, guideMarkers = true, transparent = true } },
	{ key = "Clean", title = L["Clean"], desc = L["No arrows, marks or pick order numbers: only the talents and the guide."],
		settings = { tileSize = 36, showOrder = false, showArrows = false, showGuide = true, guideMarkers = false, transparent = false } },
	{ key = "Minimal", title = L["Minimal"], desc = L["Small talents, nothing else around them."],
		settings = { tileSize = 30, showOrder = false, showArrows = false, showGuide = false, guideMarkers = false, transparent = true } },
})
