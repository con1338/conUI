-- EldoUI Quest Starter Drops: settings page and style presets.
local _, E = ...
local L = E.L
local LG = E.LootGuide
local QD = E:GetModule("QuestDrops")

local function GuideOff() return not (LG and LG.active) end
local function GuideOn() return not GuideOff() end

local function PlatesMissing()
	local module = E.modules.Nameplates
	if not (module and module.active) then return L["Turn on the Nameplates module first."] end
end

QD.options = {
	{ type = "description", label = L["Creatures that can drop an item that starts a quest get a tooltip line and a small icon on their nameplate."] },
	{ type = "description", hidden = GuideOn, label = L["The drop data comes with the Loot Guide. Turn the Loot Guide on to use it."] },
	{ type = "execute", label = L["Turn on the Loot Guide"], hidden = GuideOn,
		func = function()
			E:SetModuleEnabled("LootGuide", true)
			if E.RefreshConfig then E:RefreshConfig() end
		end,
		desc = L["Switches the Loot Guide module on; quest starter hints come with it."] },

	{ type = "header", label = L["What shows"], hidden = GuideOff },
	{ type = "toggle", key = "hideDone", label = L["Hide when the quest is done or taken"], hidden = GuideOff,
		desc = L["No hint once you have done the quest or it is in your quest log."] },
	{ type = "toggle", key = "hideOwned", label = L["Hide when the item is in your bags"], hidden = GuideOff,
		desc = L["No hint while you carry the item that starts the quest."] },
	{ type = "toggle", key = "hideOther", label = L["Hide quests that are not for you"], hidden = GuideOff,
		desc = L["No hint for a quest of the other side, or of another race or class."] },
	{ type = "range", key = "minChance", label = L["Minimum drop chance"], min = 0, max = 50, step = 1, hidden = GuideOff,
		desc = L["Leave out items that drop less often than this, in percent. 0 shows every one."] },
	{ type = "description", hidden = GuideOff,
		label = L["The tooltip line has its own switch on the Tooltip page. The chance follows the Loot Guide's Drop chances setting."] },

	{ type = "header", label = L["Nameplate icon"], hidden = GuideOff },
	{ type = "toggle", key = "plates", label = L["Icon on nameplates"], hidden = GuideOff, disabled = PlatesMissing,
		desc = L["A small icon on the nameplate of a creature that can drop a quest starter. Needs EldoUI's Nameplates module."] },
	{ type = "select", key = "plateLook", label = L["Icon look"], hidden = GuideOff, dependsOn = "plates",
		values = QD.PLATE_LOOK_TITLE, order = { "scroll", "exclamation", "dot", "bronze", "safe" },
		desc = L["A scroll, the quest giver's exclamation mark, a dot in your accent color, a scroll in a bronze frame, or a yellow square with a mark that reads for every kind of color blindness."] },
	{ type = "range", unit = "px", key = "plateSize", label = L["Icon size"], min = 8, max = 32, step = 1, hidden = GuideOff, dependsOn = "plates",
		desc = L["Size of the nameplate icon."] },
	{ type = "select", key = "platePosition", label = L["Icon position"], hidden = GuideOff, dependsOn = "plates",
		values = { top = L["Above the name"], left = L["Left of the bar"], right = L["Right of the bar"] }, order = { "top", "left", "right" },
		desc = L["Where the icon sits on the plate. Right of the bar comes after the elite and quest icons."] },
}

E:RegisterStyles("QuestDrops", {
	{ key = "Scroll", title = L["Scroll"], desc = L["A scroll above the name."],
		settings = { plateLook = "scroll", plateSize = 14, platePosition = "top" } },
	{ key = "Exclamation", title = L["Exclamation mark"], desc = L["The quest giver's exclamation mark right of the bar, like the game's quest icon."],
		settings = { plateLook = "exclamation", plateSize = 16, platePosition = "right" } },
	{ key = "Dot", title = L["Dot"], desc = L["A small dot in your accent color left of the bar."],
		settings = { plateLook = "dot", plateSize = 12, platePosition = "left" } },
	{ key = "Bronze", title = L["Forever bronze"], desc = L["A scroll in a bronze frame above the name, to match the WoW Forever art style."],
		settings = { plateLook = "bronze", plateSize = 16, platePosition = "top" } },
	{ key = "Safe", title = L["Color-blind safe"], desc = L["A yellow square with a mark above the name; the shape carries it too."],
		settings = { plateLook = "safe", plateSize = 14, platePosition = "top" } },
})
