-- EldoUI Party Quests: settings page and style presets.
local _, E = ...
local L = E.L
local Key = E.Key
local PQ = E:GetModule("PartyQuests")

local function SyncOff() return not PQ.db.sync end

PQ.options = {
	{ type = "description", label = L["In a group, a small panel shows the quests you share with your party and the ones only you or they have. Share and Ask are one click each."] },

	{ type = "header", label = L["Panel"] },
	{ type = "toggle", key = "panel", label = L["Show the panel in a group"],
		desc = L["The Party Quests panel shows while you are in a party. /eui party shows or hides it too. Place it in move mode (Party Quests)."] },
	{ type = "toggle", key = "hideInRaid", label = L["Hide in raids"],
		desc = L["No panel and no sync while you are in a raid group. Off: the panel compares your quests with your own raid subgroup."] },
	{ type = "toggle", key = "showShared", label = L["Shared quests"], dependsOn = "panel",
		desc = L["Cards for quests you and at least one member are on, with each member's progress when they sync."] },
	{ type = "toggle", key = "showMine", label = L["Only mine"], dependsOn = "panel",
		desc = L["Cards for quests no one else in the party has, with a Share button when the quest can be shared."] },
	{ type = "toggle", key = "showTheirs", label = L["Only theirs"], dependsOn = "panel",
		disabled = function() if SyncOff() then return L["Needs Sync with group."] end end,
		desc = L["Cards for quests a member has and you lack, with an Ask button. Needs Sync with group on both sides."] },
	{ type = "select", key = "look", label = L["Look"], dependsOn = "panel",
		values = PQ.LOOK_TITLE, order = { "cards", "list", "tracker", "bronze", "minimal" },
		desc = L["Boxed cards with progress bars, one line a quest, plain text like the objective tracker, cards in a bronze frame, or one line without a panel."] },
	{ type = "range", key = "fontSize", label = L["Text size"], min = 10, max = 16, step = 1, dependsOn = "panel",
		desc = L["Size of the quest titles; the member line is one size smaller."] },
	{ type = "toggle", key = "bars", label = L["Progress bars"], dependsOn = "panel",
		disabled = function()
			if PQ.db.look ~= "cards" and PQ.db.look ~= "bronze" then return L["Only the Cards and Forever bronze looks have bars."] end
		end,
		desc = L["A thin bar under each card with your own progress on the quest."] },

	{ type = "header", label = L["Sync with group"] },
	{ type = "toggle", key = "sync", label = L["Enable"],
		desc = L["Shares your quest progress with group members who run EldoUI as addon messages, never in chat, and shows theirs. Not in battlegrounds or arenas. On by default."] },
	{ type = "toggle", key = "popups", label = L["Progress popups"], disabled = function() if SyncOff() then return L["Needs Sync with group."] end end,
		desc = L["A short popup when a member finishes an objective or the whole of a quest you share."] },

	{ type = "header", label = L["Summary"] },
	{ type = "toggle", key = "summary", label = L["Group summary"],
		desc = L["When the group ends, a card with how long you grouped and the quests you turned in while a member was on them too."] },
}

-- The shared visibility rows, at the end of the panel section.
do
	local at = #PQ.options + 1
	for index, row in ipairs(PQ.options) do
		if row.type == "header" and row.label == Key("Sync with group") then at = index break end
	end
	for _, row in ipairs(E:VisibilityOptions("visibility", { db = function() return PQ.db end,
		hidden = function() return not PQ.db.panel end })) do
		table.insert(PQ.options, at, row)
		at = at + 1
	end
end

E:RegisterStyles("PartyQuests", {
	{ key = "Cards", title = L["Cards"], desc = L["Boxed cards with your progress bar and each member's count."],
		settings = { look = "cards", fontSize = 12, bars = true } },
	{ key = "Compact", title = L["Compact list"], desc = L["One line a quest with how many of you are on it; the tooltip has the details."],
		settings = { look = "list", fontSize = 12, bars = false } },
	{ key = "Tracker", title = L["Tracker-style"], desc = L["No panel: accent titles and member lines, like the objective tracker."],
		settings = { look = "tracker", fontSize = 13, bars = false } },
	{ key = "Bronze", title = L["Forever bronze"], desc = L["Cards in a bronze frame, to match the WoW Forever art style."],
		settings = { look = "bronze", fontSize = 12, bars = true } },
	{ key = "Minimal", title = L["Minimal"], desc = L["No panel, one small line a quest."],
		settings = { look = "minimal", fontSize = 11, bars = false } },
})
