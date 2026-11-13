-- EldoUI Instances: the options page and style presets.
local _, E = ...
local L = E.L
local Key = E.Key
local M = E.Instances

local function WipeRuns()
	local store = M:Store()
	store.runs = {}
	M.current = nil
	if M.active then
		M:OnEnteringWorld(false, false)
		M:ScheduleFree()
	end
	M:Changed("runs")
end

local SHOW = {
	{ "time", Key("Time inside"), Key("How long you were inside.") },
	{ "kills", Key("XP kills"), Key("Kills that gave you experience (counted from the game's XP lines, so quest XP is left out).") },
	{ "xp", Key("Experience"), Key("Experience gained inside.") },
	{ "xpPercent", Key("XP as % of a level"), Key("The experience as a share of the level you had when you entered.") },
	{ "xpHour", Key("XP per hour"), Key("Experience divided by the time inside.") },
	{ "xpKill", Key("XP per kill"), Key("Average experience per XP kill.") },
	{ "runsLevel", Key("Runs per level"), Key("How many runs like this one a whole level takes.") },
	{ "runsNext", Key("Runs to the next level"), Key("How many more runs like this one until you level up.") },
	{ "gold", Key("Gold from mobs"), Key("Coins you looted (the money change when no loot line could be read). Never posted to chat.") },
	{ "rep", Key("Reputation"), Key("Reputation gained or lost, per faction.") },
	{ "currency", Key("Currencies"), Key("Currencies gained inside.") },
	{ "groupLevel", Key("Group level"), Key("The average level of your group.") },
	{ "honor", Key("Honor"), Key("Honor and honorable kills in a battleground.") },
}

local function ShowOptions()
	local list = {}
	for _, row in ipairs(SHOW) do
		list[#list + 1] = { type = "toggle", key = "show." .. row[1], label = row[2], desc = row[3] }
	end
	return list
end

function M:BuildOptions()
	local options = {
		{ type = "tab", label = L["General"] },
		{ type = "description", label = L["Counts your dungeon entries against the hourly limit (5 per hour, shared by your characters) and logs every run. The count is an estimate."] },
		{ type = "execute", label = L["Open the run log"], desc = L["The log of every run (also a click on the Instances datatext, or /eui instances)."], func = function() M:OpenLog() end },
		{ type = "header", label = L["Hourly limit"] },
		{ type = "range", key = "hourlyLimit", label = L["Instances per hour"], min = 1, max = 10, step = 1,
			desc = L["How many new instances the server lets you enter per hour. Change it if Forever uses a different limit."],
			cog = {
				{ type = "range", key = "dailyLimit", label = L["Instances per day"], min = 0, max = 60, step = 1,
					zeroText = "Off", desc = L["A daily limit to count against as well. Forever has none."] },
			} },
		{ type = "toggle", key = "countRaids", label = L["Count raids"], desc = L["Raids count toward the hourly limit too. Off: raids are logged in orange and don't count."] },
		{ type = "toggle", key = "detectSameRun", label = L["Detect the same run"], desc = L["Walking out and back into the same instance doesn't count twice: entries with the same instance ID, read from the mobs you target, are merged."] },
		{ type = "header", label = L["Data"] },
		{ type = "range", key = "keepRuns", label = L["Runs kept"], min = 50, max = 500, step = 10, desc = L["How many runs this log keeps (all characters). Older runs leave the log; My Adventure keeps every run in its journal, with who was in it."] },
		{ type = "execute", label = L["Remove all runs"], desc = L["Empties the run log for every character, after a confirmation."], func = function()
			E:ShowConfirm({ key = "ELDOUI_INSTANCES_WIPE", title = L["Instances"],
				text = L["Remove every run from the log, for all characters? Trades and lockouts are kept."],
				accept = YES or L["Yes"], cancel = NO or L["No"], danger = true, onAccept = WipeRuns })
		end },

		{ type = "tab", label = L["Notices"] },
		{ type = "description", label = L["Lines in your own chat window. Nothing here is sent to other players."] },
		{ type = "header", label = L["Entering"] },
		{ type = "toggle", key = "noticeEnter", label = L["Dungeon entered"], desc = L["A line with the hourly count when you enter a dungeon, with links to the log and to remove the entry."] },
		{ type = "toggle", key = "noticeRaid", label = L["Raid entered"], desc = L["The same line when you enter a raid."] },
		{ type = "toggle", key = "noticePvP", label = L["Battleground entered"], desc = L["A line when you enter a battleground or arena, which never counts toward the limit."] },
		{ type = "toggle", key = "noticeMerge", label = L["Same run merged"], desc = L["A line when an entry turns out to be the same run as the one before."] },
		{ type = "toggle", key = "noticeFree", label = L["Slot free again"], desc = L["A line at the moment the hourly count drops below the limit again."],
			cog = {
				{ type = "media", key = "freeSound", label = L["Sound"], mediaKind = "sound", none = true, desc = L["A sound with the slot-free line."] },
			} },
		{ type = "header", label = L["Leaving"] },
		{ type = "toggle", key = "summary", label = L["Run summary"], desc = L["When you leave, one line with what the run gave you: time, XP kills, experience, gold and reputation."],
			cog = ShowOptions() },
		{ type = "toggle", key = "summaryOnlyActivity", label = L["Only when something happened"], dependsOn = "summary",
			desc = L["Leaves the summary out when the run gave no experience, kills, gold, reputation or currency."] },
	}
	-- The log, reset and battleground files add their own tabs.
	for _, add in ipairs(self.optionParts or {}) do add(options) end
	return options
end

M.options = function() return M:BuildOptions() end
