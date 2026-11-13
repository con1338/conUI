-- EldoUI Ready Check Report: options page and style presets.
local _, E = ...
local L = E.L
local M = E.ReadyReport

local function NoBuffs() return not M.db.checks.buffs end

M.options = {
	{ type = "description", label = "Buffs are read out of combat; the panel closes when combat starts. Nothing is sent unless you click. /eui readycheck opens it." },
	{ type = "tab", label = "General" },
	{ type = "header", label = "When it opens" },
	{ type = "select", key = "openOn", label = "Open on a ready check", values = { lead = "When I lead or assist", always = "Always", never = "Never" }, order = { "lead", "always", "never" },
		desc = "When the panel opens by itself as a ready check starts. With Never it only opens from /eui readycheck." },
	{ type = "toggle", key = "autoClose", label = "Close after the ready check", desc = "Close the panel a few seconds after the ready check ends." },
	{ type = "range", key = "closeDelay", label = "Close after", unit = "s", min = 0, max = 60, step = 1, dependsOn = "autoClose",
		desc = "How long the panel stays open after the ready check ends." },
	{ type = "header", label = "What it checks" },
	{ type = "toggle", key = "checks.ready", label = "Ready answers", desc = "A column with each member's answer to the ready check: ready, not ready or waiting." },
	{ type = "toggle", key = "checks.buffs", label = "Class buffs", desc = "A column with the class buffs a member is missing." },
	{ type = "toggle", key = "checks.flask", label = "Flask or elixir", desc = "Whether a member has a flask or at least one elixir up." },
	{ type = "toggle", key = "checks.food", label = "Food buff", desc = "Whether a member is Well Fed." },
	{ type = "toggle", key = "checks.durability", label = "Durability", desc = "The lowest item durability of you and of members who share it." },
	{ type = "execute", label = "Durability colors", keywords = "durability warning low", dependsOn = "checks.durability",
		desc = "Worn gear shows orange and counts in the summary, low gear shows red. Both thresholds are set once for every module, on the General page (Clock and durability).",
		func = function() E:ToggleConfig("general") end },
	{ type = "toggle", key = "checks.version", label = "EldoUI version", desc = "The EldoUI version of members who share it; an older one than yours shows orange." },
	{ type = "header", label = "Class buffs" },
	{ type = "toggle", key = "buffs.FORT", label = "Fortitude", desc = "Power Word: Fortitude or Prayer of Fortitude.", hidden = NoBuffs },
	{ type = "toggle", key = "buffs.INT", label = "Intellect", desc = "Arcane Intellect or Arcane Brilliance.", hidden = NoBuffs },
	{ type = "toggle", key = "buffs.MOTW", label = "Mark of the Wild", desc = "Mark of the Wild or Gift of the Wild.", hidden = NoBuffs },
	{ type = "toggle", key = "buffs.BLESSING", label = "Blessing", desc = "Any paladin blessing, single or greater.", hidden = NoBuffs },
	{ type = "toggle", key = "buffs.SPIRIT", label = "Spirit", desc = "Divine Spirit or Prayer of Spirit (a talent, so off by default).", hidden = NoBuffs },
	{ type = "toggle", key = "buffs.SHADOW", label = "Shadow Protection", desc = "Shadow Protection or Prayer of Shadow Protection.", hidden = NoBuffs },
	{ type = "toggle", key = "onlyGivers", label = "Only buffs your group can give", desc = "Count a buff as missing only when a class that casts it is in the group.", hidden = NoBuffs },
	{ type = "tab", label = "Sharing" },
	{ type = "header", label = "Sharing and posting" },
	{ type = "toggle", key = "share", label = "Share mine button", desc = "Adds a Share mine button that sends your lowest durability and EldoUI version to the group once per ready check, for their report. Nothing is sent without your click." },
	{ type = "toggle", key = "postButton", label = "Post to group button", desc = "A button that sends the summary line to party or raid chat when you click it." },
	{ type = "tab", label = "Look" },
	{ type = "header", label = "Panel" },
	{ type = "select", key = "layout", label = "Layout", values = { grid = "Grid with icons", list = "Compact list", summary = "Summary only" }, order = { "grid", "list", "summary" },
		desc = "Grid shows missing buffs as icons, Compact list as names, Summary only shows the counts without rows." },
	{ type = "range", key = "rowHeight", label = "Row height", min = 16, max = 28, step = 1, desc = "Height of one member row." },
	{ type = "toggle", key = "classColors", label = "Class colored names", desc = "Member names in their class color." },
	{ type = "toggle", key = "transparent", label = "See-through background", desc = "The report panel lets the game show through a little. How much: General > Panel opacity." },
	{ type = "execute", label = "Open the report", desc = "Open the panel now with your group (out of combat).",
		func = function() if M.active then M:Open() end end },
}

-- Looks only: no positions, no sharing.
E:RegisterStyles("ReadyReport", {
	{ key = "Grid", title = L["Grid"], desc = L["Every column, missing buffs as icons, 20 px rows."],
		settings = { layout = "grid", rowHeight = 20, classColors = true, transparent = false,
			checks = { ready = true, buffs = true, flask = true, food = true, durability = true, version = true } } },
	{ key = "CompactList", title = L["Compact list"], desc = L["Missing buffs as names in short 16 px rows."],
		settings = { layout = "list", rowHeight = 16, classColors = true, transparent = false,
			checks = { ready = true, buffs = true, flask = true, food = true, durability = true, version = false } } },
	{ key = "SummaryOnly", title = L["Summary only"], desc = L["A small panel with only the counts: who misses what, without member rows."],
		settings = { layout = "summary", classColors = true, transparent = false } },
	{ key = "ForeverBronze", title = L["Forever bronze"], desc = L["The grid in a solid panel that follows your art style (the bronze frame line under WoW Forever), 22 px rows."],
		settings = { layout = "grid", rowHeight = 22, classColors = true, transparent = false,
			checks = { ready = true, buffs = true, flask = true, food = true, durability = true, version = true } } },
	{ key = "Minimal", title = L["Minimal"], desc = L["A see-through compact list with buffs and the ready answer only."],
		settings = { layout = "list", rowHeight = 16, classColors = false, transparent = true,
			checks = { ready = true, buffs = true, flask = false, food = false, durability = false, version = false } } },
})
