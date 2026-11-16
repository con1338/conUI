-- EldoUI Characters: the options page.
local _, E = ...
local L = E.L
local M = E:GetModule("Characters")
if not M then return end

local function Store() return E.Characters end


local function ForgetValues()
	local values = E:RawValues({ [""] = L["Choose a character"] })
	if not Store() or type(EldoUIDB) ~= "table" then return values end
	for _, key in ipairs(Store():Keys("account", true)) do
		if key ~= E.charKey then
			local record = Store():Get(key)
			values[key] = ("%s (%d)"):format(key, record and record.level or 0)
		end
	end
	return values
end

local function TabValues()
	local values = {}
	for _, tab in ipairs(M.tabs) do values[tab.key] = tab.title end
	return values
end

-- Per-character switch: this character's entry in `skip`, a view of the
-- account-wide list (M:SkipView), so it never changes with the profile.
local function SkipKey()
	M:SkipView()
	return "skip." .. tostring(E.charKey)
end

M.options = {
	{ type = "tab", label = "General" },
	{ type = "description", label = "Each character records its level, gold, gear, bags, professions, quests and lockouts when you log in. Open the Alts window with /eui alts." },
	{ type = "execute", label = "Open the Alts window", desc = "Opens the window (/eui alts).", func = function() M:Open() end },
	{ type = "header", label = "Window" },
	{ type = "select", key = "scope", label = "Characters shown", desc = "Which characters the window lists first. You can change it in the window's top bar too. On Forever, \"This realm\" means everyone on the same ruleset (PvE, PvP, RP or Hardcore).",
		values = { char = "This character", realm = "This realm", faction = "This faction", account = "All characters" } },
	{ type = "select", key = "openTab", label = "Opens on", desc = "The tab the window shows when you open it.", values = TabValues },
	{ type = "toggle", key = "chips", label = "Filter chips", desc = "A row of filters above the Overview: faction, level, fully rested, mail and lockouts." },
	{ type = "range", unit = "px", key = "rowHeight", label = "Row height", desc = "Height of each Overview row in pixels.", min = 14, max = 26, step = 1 },
	{ type = "toggle", key = "restedEstimate", label = "Estimate rested XP", desc = "Shows how much rested XP your offline characters have built up since logout, from the game's published rate. Estimates are marked with ~." },
	{ type = "header", label = "Reminders" },
	{ type = "toggle", key = "warnMail", label = "Mail that runs out soon", desc = "A few seconds after login, prints a chat line for each character with mail that is returned or deleted soon, on every realm." },
	{ type = "cog", label = "Mail warning time", dependsOn = "warnMail", desc = "How early the mail reminder warns.", options = {
		{ type = "range", key = "warnMailDays", label = "Days before", desc = "Warn about mail with fewer days left than this. The Mail and AH tab colors those mails yellow.", min = 1, max = 15, step = 1 },
	} },
	{ type = "toggle", key = "warnAuction", label = "Auction house not visited", desc = "A few seconds after login, prints a chat line for each character with running auctions who has not visited the auction house for a while." },
	{ type = "cog", label = "Auction warning time", dependsOn = "warnAuction", desc = "How long a character can stay away from the auction house before the reminder.", options = {
		{ type = "range", key = "warnAuctionDays", label = "Days away", desc = "Remind after this many days without an auction house visit.", min = 1, max = 30, step = 1 },
	} },
	{ type = "toggle", key = "agendaWarn", label = "Agenda reminders", desc = "Prints a chat line shortly before a profession cooldown is ready, a lockout resets or a calendar event starts, for any of your characters. Once each, and not while you are in combat." },
	{ type = "cog", label = "Agenda reminder details", dependsOn = "agendaWarn", desc = "How early, and for which kinds.", options = {
		{ type = "range", key = "agendaLead", label = "Minutes before", desc = "How many minutes before the time the reminder prints.", min = 1, max = 120, step = 1 },
		{ type = "toggle", key = "agendaWarnCooldowns", label = "Profession cooldowns", desc = "Remind when a saved profession cooldown is about to be ready." },
		{ type = "toggle", key = "agendaWarnLockouts", label = "Lockout resets", desc = "Remind when a saved raid or dungeon lockout is about to reset." },
		{ type = "toggle", key = "agendaWarnCalendar", label = "Calendar events", desc = "Remind when a calendar event one of your characters saw is about to start." },
	} },
	{ type = "toggle", key = "weekStartsMonday", label = "Week starts on Monday", desc = "The Agenda's month view starts each week on Monday instead of Sunday." },
	{ type = "header", label = "Recording" },
	{ type = "toggle", key = SkipKey, label = "Don't record this character", desc = "This character stops saving its Alts window info and leaves the Alts window, item counts and address book. Its bags and bank stay saved for itself. Kept per character." },

	{ type = "toggle", key = "requestPlayed", label = "Ask for played time at login", desc = "Asks the server for your played time a few seconds after login, so the window can show and total it." }, -- lint: unused-key ok (read by Core/CharacterStore.lua)
	{ type = "toggle", key = "quietPlayed", label = "Keep EldoUI's played request out of chat", desc = "The answer to EldoUI's own played-time request doesn't print in chat. A /played you type always prints." }, -- lint: unused-key ok (read by Core/CharacterStore.lua)
	{ type = "toggle", key = "playedOnLevelUp", label = "Exact played time at each level", desc = "Asks for played time right after a level-up, so the level log has the exact value instead of an estimate from the login read." }, -- lint: unused-key ok (read by Core/CharacterStore.lua)

	{ type = "header", label = "Guild" },
	{ type = "toggle", key = "guildShare", label = "Share alt info with your guild", desc = "Adds Send my alts and Ask the guild buttons to the Guild tab, to swap your characters' names, classes and levels with guild members who use EldoUI. Nothing is sent without your click." },

	{ type = "tab", label = "Tooltips" },
	{ type = "description", label = "Item counts per character are set on the Bags page and in the Tooltip sections. They also work while Bags is off." },
	{ type = "toggle", key = "countsWithBagAddons", label = "Item counts next to Baganator, Bagnon or ArkInventory", desc = "Those addons show their own counts, so EldoUI hides its counts while one of them is loaded. Turn this on to show both." }, -- lint: unused-key ok (read through Data/Competitors.lua by Core/AddonConflicts.lua)
	{ type = "toggle", key = "recipeColours", label = "Recipe colors at vendors and the auction house", desc = "Vendor and auction house recipes get a color: green if one of your characters can learn it now, yellow if later, red if all of them know it." },
	{ type = "toggle", key = "questTooltip", label = "Your characters on quest tooltips", desc = "A quest link's tooltip says which of your characters have the quest, are ready to turn it in or completed it." },
	{ type = "input", key = "reagentsExtra", label = "More reagents", desc = "Item IDs (separated by commas) that the character tooltip counts as reagents, next to the class reagents EldoUI knows." },
	{ type = "select", key = "datatext", label = "Alts datatext shows", desc = "The text of the Alts datatext: how many characters you have, or their total gold.", -- lint: unused-key ok (read by the Alts datatext in Modules/InfoBar.lua)
		values = { count = "Number of characters", gold = "Total gold" } },

	{ type = "tab", label = "Forget" },
	{ type = "description", label = "Remove characters you deleted or no longer play. Their journal stays on the Saved data page until you put it back or remove it." },
	{ type = "toggle", key = "forgetSettings", label = "Also forget their EldoUI settings", desc = "Forget also removes the character's profile choice, own settings, setup state, profile rules and key binding backup." },
	{ type = "select", key = "forgetPick", label = "Character", desc = "Pick the character to forget.", values = ForgetValues },
	{ type = "execute", label = "Forget character", desc = "Asks once, then removes the character picked above.", func = function()
		if M.db.forgetPick ~= "" then
			M:ConfirmForget(M.db.forgetPick)
			M.db.forgetPick = ""
		end
	end },
	{ type = "range", key = "forgetLevel", label = "Forget characters below level", desc = "The level used by the button below.", min = 2, max = 60, step = 1 },
	{ type = "execute", label = "Forget all below that level", desc = "Removes every saved character (not this one) below the level above, for example old bank or mail alts you deleted.", func = function()
		E:ShowConfirm({ key = "ELDOUI_ALTS_FORGET_BELOW", title = L["Alts"],
			text = L["Forget every saved character below level %s?"]:format(M.db.forgetLevel),
			accept = YES, cancel = NO, danger = true, onAccept = function() M:ForgetBelow(M.db.forgetLevel) end })
	end },
	{ type = "execute", label = "Saved size", desc = "Shows how much saved data each character uses (/eui alts size).", func = function() M:Command("size") end },
}
