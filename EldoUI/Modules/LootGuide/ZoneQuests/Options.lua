-- EldoUI Zone Quests: settings page and style presets.
--
-- The list lives in the Loot Guide (Catalog > Zones); while the Loot Guide
-- is off the page shows a notice and a button to turn it on.
local _, E = ...
local L = E.L
local LG = E.LootGuide
local Z = E:GetModule("ZoneQuests")

local function GuideOff() return not (LG and LG.active) end
local function GuideOn() return not GuideOff() end

Z.options = {
	{ type = "description", label = L["Every zone's quests in the Loot Guide's Catalog: how many you have done, what is left and who gives them."] },
	{ type = "description", hidden = GuideOn, label = L["The Zones section lives in the Loot Guide. Turn the Loot Guide on to use it."] },
	{ type = "execute", label = L["Turn on the Loot Guide"], hidden = GuideOn,
		func = function()
			E:SetModuleEnabled("LootGuide", true)
			if E.RefreshConfig then E:RefreshConfig() end
		end,
		desc = L["Switches the Loot Guide module on; the Zones section comes with it."] },

	{ type = "header", label = L["Zone list"], hidden = GuideOff },
	{ type = "toggle", key = "mine", label = L["My quests only"], hidden = GuideOff,
		desc = L["List only quests for your side, race, class and professions. Off also shows the others, in a Not for you group."] },
	{ type = "toggle", key = "hideDone", label = L["Hide done"], hidden = GuideOff,
		desc = L["Leave the quests you have done out of the list. The counts still include them."] },
	{ type = "toggle", key = "hideGray", label = L["Hide gray quests"], hidden = GuideOff,
		desc = L["Leave out quests so far below your level that they give no experience."] },
	{ type = "toggle", key = "chains", label = L["Chains as one row"], hidden = GuideOff,
		desc = L["Show each quest chain of the zone as one row: the step that needs you now, with its place in the chain."] },
	{ type = "toggle", key = "repeatables", label = L["Count repeatable quests"], hidden = GuideOff,
		desc = L["Repeatable and daily quests count toward a zone's total and show in its list."] },
	{ type = "execute", label = L["Open Catalog > Zones"], hidden = GuideOff, func = function() Z:Open() end,
		desc = L["Same as /eui zones. Opens the Loot Guide on the zone you are in."] },

	{ type = "header", label = L["World map"], hidden = GuideOff },
	{ type = "toggle", key = "pins", label = L["Quest givers on the map"], hidden = GuideOff,
		desc = L["A pin on the world map for each giver of the quests left in the zone the map shows. Hover it for the quests, click it for a waypoint. The map's EldoUI pin switch hides it with the other pins."] },
	{ type = "select", key = "pinLook", label = L["Pin look"], hidden = GuideOff, dependsOn = "pins",
		values = { icons = L["Quest icons"], dots = L["Dots"], contrast = L["High contrast"], bronze = L["Forever bronze"], minimal = L["Minimal"] },
		order = { "icons", "dots", "contrast", "bronze", "minimal" },
		desc = L["How the giver pins look: the quest icon, colored dots, bright color-blind safe colors, the bronze of the Forever art style, or small plain dots."] },
	{ type = "range", key = "pinSize", label = L["Pin size"], min = 10, max = 32, step = 1, hidden = GuideOff, dependsOn = "pins",
		desc = L["Size of the giver pins on the map."] },
	{ type = "toggle", key = "pinAvailable", label = L["Quests you can take now"], hidden = GuideOff, dependsOn = "pins",
		desc = L["Pins for the givers of quests you can pick up now."] },
	{ type = "toggle", key = "pinLocked", label = L["Quests that need a prerequisite"], hidden = GuideOff, dependsOn = "pins",
		desc = L["Also pin givers whose quests open after another quest."] },
	{ type = "toggle", key = "pinLow", label = L["Quests above your level"], hidden = GuideOff, dependsOn = "pins",
		desc = L["Also pin givers whose quests need a higher level."] },

	{ type = "header", label = L["Zone Info"], hidden = GuideOff },
	{ type = "toggle", key = "zoneInfo", label = L["Quest count in the zone tooltip"], hidden = GuideOff,
		desc = L["Adds a Quests line (done of total) to Zone Info's world map tooltip when you hover a zone. Needs the Zone Info module."] },
}

Z.refreshWhenOff = function(module)
	if module.Invalidate then module:Invalidate(false) end
end

E:RegisterStyles("ZoneQuests", {
	{ key = "Icons", title = L["Icons"], desc = L["Quest icons on the map for quests you can take now; everything listed."],
		settings = { pinLook = "icons", pinSize = 18, pinAvailable = true, pinLocked = false, pinLow = false, hideDone = false, chains = true } },
	{ key = "Dots", title = L["Dots"], desc = L["Colored dots: accent for quests you can take, orange for a prerequisite, gray for too low."],
		settings = { pinLook = "dots", pinSize = 14, pinAvailable = true, pinLocked = true, pinLow = true } },
	{ key = "Contrast", title = L["High contrast"], desc = L["Large pins in color-blind safe colors with a mark on each; done quests hidden from the list."],
		settings = { pinLook = "contrast", pinSize = 22, pinAvailable = true, pinLocked = true, pinLow = false, hideDone = true } },
	{ key = "Bronze", title = L["Forever bronze"], desc = L["Quest icons on bronze, to match the WoW Forever art style."],
		settings = { pinLook = "bronze", pinSize = 18, pinAvailable = true, pinLocked = false, pinLow = false } },
	{ key = "Minimal", title = L["Minimal"], desc = L["Small plain dots for quests you can take now, gray quests and done quests left out of the list."],
		settings = { pinLook = "minimal", pinSize = 12, pinAvailable = true, pinLocked = false, pinLow = false, hideDone = true, hideGray = true } },
})
