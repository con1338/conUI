-- EldoUI Eldostar: options page and style presets.
local _, E = ...
local L = E.L
local M = E.Eldostar

local function NotLive()
	if not M.active then return E:ModuleOffNote("Eldostar") end
	if not M:IsLive() then return E:GuideProviderStatus() end
end

local function NoGuide()
	local reason = NotLive()
	if reason then return reason end
	if not M:Current() then return L["No guide in use yet."] end
end

local function WaypointsOff()
	local waypoints = E.modules.Waypoints
	if not (waypoints and waypoints.active) then return E:ModuleOffNote("Waypoints") end
end

local function ChoiceRoot() return M:Choices() end

local function GroupValues()
	local out = {}
	for quest in pairs(ChoiceRoot().groups) do
		if type(quest) == "number" then out[quest] = M.QuestName(quest) or L["quest %d"]:format(quest) end
	end
	return out
end

local function GroupChoiceKey()
	return "groups." .. tostring(ChoiceRoot().selectedGroup or 0)
end

local function GroupChoiceDisabled()
	local quest = tonumber(ChoiceRoot().selectedGroup)
	if not quest then return L["Choose a group quest first."] end
	if not M:GroupChoiceCanChange(quest) then return L["The route has already passed this quest's choice."] end
end

local function DungeonOptions()
	local rows, ids, names = {}, {}, M.Dungeons()
	for id in pairs(names) do ids[#ids + 1] = id end
	table.sort(ids, function(a, b) return names[a] < names[b] end)
	for _, id in ipairs(ids) do
		local title = names[id]
		rows[#rows + 1] = { type = "toggle", key = "dungeons." .. id, root = ChoiceRoot,
			label = function() return title end, desc = "Include this dungeon in this character's leveling guides." }
	end
	return rows
end

-- A change to the provider also reaches the guide spot while Eldostar is
-- switched off (Automatic then hands the spot to the other guide).
M.refreshWhenOff = function()
	E:GuideProviderChanged()
end

M.options = {
	{ type = "description", label = "EldoUI's own leveling guide: community guides, step by step, on the layout's guide spot. The guides are in English." },
	{ type = "description", label = function() return E:GuideProviderStatus() end },
	{ type = "tab", label = "Guide" },
	{ type = "header", label = "Guide provider" },
	{ type = "select", key = "provider", label = "Guide on the guide spot", values = E.GUIDE_PROVIDER_TITLES, -- lint: unused-key ok (read by E:GuideProviderChoice, Modules/Integrations.lua)
		order = E.GUIDE_PROVIDER_ORDER, desc = E.GUIDE_PROVIDER_ROW_DESC },
	{ type = "header", label = "Your guide" },
	{ type = "description", label = function()
		local guide, record, steps = M:Current()
		if not guide and M:Waiting() then
			return L["At the level cap the window waits until you start a guide: from the Journal's Guides page, Open the guide list below or /eui eldostar."]
		end
		if not guide then return L["No guide in use yet."] end
		if record.done then return L["You finished %s."]:format(guide.title) end
		return L["%s, step %d of %d."]:format(guide.title, record.s, #steps)
	end, hidden = function() return not M:IsLive() end },
	{ type = "execute", label = "Open the guide list", noUndo = true, disabled = NotLive,
		desc = "The guide list is in the Journal, under My Adventure: Guides. /eui eldostar guides does the same.",
		func = function()
			if not M:OpenPicker() then
				E:Print(L["The guide list is in the Journal, under My Adventure. Turn My Adventure on to browse the guides."])
			end
		end },
	{ type = "execute", label = "Show the window", noUndo = true, disabled = NotLive,
		desc = "Shows the guide window again after you closed it. /eui eldostar show does the same.",
		func = function() M:ShowNow() end },
	{ type = "execute", label = "Start the guide over", noUndo = true, disabled = NoGuide,
		desc = "Clears this character's place in the guide in use and starts it from its first step.",
		func = function()
			local guide = M:Current()
			if not guide then return end
			E:ShowConfirm({
				title = L["Start over?"],
				text = L["Start %s over from its first step? Your place in it is cleared."]:format(guide.title),
				accept = L["Start over"],
				danger = true,
				onAccept = function() M:ResetGuide(guide.id) end,
			})
		end },
	{ type = "execute", label = "Stop the guide", noUndo = true, disabled = NoGuide,
		desc = "No guide in use for this character. Your place in it is kept for when you start it again.",
		func = function() M:StopGuide() end },
	{ type = "header", label = "Steps" },
	{ type = "toggle", key = "autoAdvance", label = "Move on by itself",
		desc = "A step whose goals are all done moves on to the next one. Off: Next moves on." },
	{ type = "toggle", key = "useDeathskips", label = "Use deathskips",
		desc = "Follow deathskip goals in guides. Available for non-Hardcore characters.",
		disabled = function() if M.Hardcore() == true then return L["Deathskips are disabled in Hardcore."] end end },
	{ type = "toggle", key = "waypoint", label = "Waypoint to the goal", disabled = WaypointsOff,
		desc = "The waypoint arrow points at the step's next goal: the place the guide gives, else the quest giver, the one you turn in to or the creature, from the Loot Guide's data." },
	{ type = "header", label = "Group quest choices" },
	{ type = "select", key = "policy", root = ChoiceRoot, label = "Group quests",
		values = { ask = "Ask for each quest", ["do"] = "Do group quests", skip = "Skip group quests" },
		order = { "ask", "do", "skip" }, desc = "Choose whether to ask before following group-quest steps." },
	{ type = "select", key = "selectedGroup", root = ChoiceRoot, label = "Saved group quests", values = GroupValues,
		desc = "Choose a saved group-quest answer to edit." },
	{ type = "select", key = GroupChoiceKey, root = ChoiceRoot, label = "Group quest answer", disabled = GroupChoiceDisabled,
		values = { ask = "Ask for each quest", ["do"] = "Do it with a group", skip = "Skip it" },
		order = { "ask", "skip", "do" }, desc = "Choose this character's route for the selected group quest." },
	{ type = "cog", label = "Dungeons in leveling guides", options = DungeonOptions(),
		desc = "Choose which dungeons this character's guides include." },
	{ type = "header", label = "Guide data" },
	{ type = "description", label = function()
		local lines = { M:DataStateText() }
		local source = M:SourceText()
		if source then lines[#lines + 1] = source end
		return table.concat(lines, "\n")
	end },
	{ type = "tab", label = "Window" },
	{ type = "header", label = "Window" },
	{ type = "select", key = "view", label = "View", values = { standard = "Standard", compact = "Compact" },
		order = { "standard", "compact" },
		desc = "Standard shows the whole step: its tip, every goal and the buttons. Compact shows the step and its next goal on two lines." },
	{ type = "range", key = "fontSize", label = "Text size", min = 10, max = 16, step = 1,
		desc = "Size of the goals; the step's title is one size larger." },
	{ type = "toggle", key = "showTip", label = "Tips", desc = "The guide's tip for the step, under its title." },
	{ type = "toggle", key = "showAlong", label = "Goals along the way",
		desc = "Goals the guide lists for the way to the next place. They never hold the step up." },
	{ type = "toggle", key = "transparent", label = "See-through window",
		desc = "The window lets the game show through a little. How much: General > Panel opacity." },
	{ type = "toggle", key = "locked", label = "Lock the window",
		desc = "The window keeps its place and size: no dragging in move mode and no resize grip." },
	{ type = "execute", label = "Reset the size", noUndo = true,
		desc = "The standard view goes back to its own size.",
		func = function()
			M.db.window = {}
			if M.frame then M:ApplySize() end
		end },
}

-- The shared visibility rows, at the end of the Window tab.
for _, row in ipairs(E:VisibilityOptions("visibility", { db = function() return M.db end })) do
	M.options[#M.options + 1] = row
end

local function Settings(base)
	local out = { view = "standard", fontSize = 13, showTip = true, showAlong = true, transparent = false }
	for key, value in pairs(base) do out[key] = value end
	return out
end

E:RegisterStyles("Eldostar", {
	{ key = "Standard", title = L["Standard"], desc = L["The whole step with its tip, goals and buttons, in a solid panel."],
		settings = Settings({}) },
	{ key = "Compact", title = L["Compact"], desc = L["The step and its next goal on two lines."],
		settings = Settings({ view = "compact", fontSize = 12 }) },
	{ key = "Glass", title = L["Glass"], desc = L["The whole step in a see-through panel."],
		settings = Settings({ transparent = true }) },
	{ key = "Minimal", title = L["Minimal"], desc = L["Small text, no tips and no goals along the way, in a see-through panel."],
		settings = Settings({ fontSize = 12, showTip = false, showAlong = false, transparent = true }) },
	{ key = "Roomy", title = L["Roomy"], desc = L["Larger text for the whole step."],
		settings = Settings({ fontSize = 15 }) },
})
