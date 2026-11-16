-- EldoUI Integrations: RestedXP on a game client in another language.
--
-- RestedXP's paid guides are English only. On a client in another language
-- (checked with RestedXP Guides v4.11.36 on a German WoW: Forever 1.60.1)
-- four things go wrong without an error:
--   1. Target names. The guides name the NPCs of their `.target`, `.mob` and
--      `.unitscan` steps in English. RestedXP translates them from its own
--      list (locale/NPCnames.lua), which misses many of them: 556 of the
--      paid Forever guides' names are different in German and not on the
--      list. The target macro, the target buttons, the nameplate marks and
--      the rare alert then look for the English name and find nobody.
--   2. The guide chain. The free guides (levels 1 to 22) load in the
--      client's language, with their own group names ("RestedXP Forever
--      Route (H)"); the paid guides keep the English ones ("RestedXP Forever
--      Guide (H)"). At the end of the free part "next guide" names a guide
--      that only exists in English ("22-24 Hügellandhof" for "22-24
--      Hillsbrad"), so the paid guide never follows.
--   3. Group names. RestedXP's German list names "RestedXP Forever Guide"
--      "Dungeonführer" and "RestedXP Forever Dungeon Guide" "Dungeon
--      Dungeonführer". Its guide menu then shows the paid route under the
--      name of the free dungeon guide, its guide assistant offers the free
--      dungeon guide for the open-world route and no guide for the dungeon
--      route, and a new character starts in the dungeon guide.
--   4. Its leveling report skips the experience of a quest by the English
--      start of that message ("You gain ..."). In another language the
--      quest's experience also counts as experience from monsters.
--
-- What this file does while "Fit RestedXP to this game language" is on:
--   * GetCreatureName: a name RestedXP leaves in English is looked up in
--     QuestieDB, English name -> NPC -> its name in this language
--     (QuestieDB holds both). The English names are read once per session,
--     in small steps after login, then RestedXP's target list is rebuilt.
--   * GetGuideTable: a guide RestedXP can't find in a translated free group
--     is looked for in the group of the same guides in English: under the
--     name the paid guide has (NEXT_NAMES), then by its level range.
--   * GetActiveGuidesByGroupNameOrId (the guide assistant's lists): a
--     translated free group and its English group list their guides
--     together, as one route from level 1 to 60.
--   * RestedXP's four wrong group names get the names of the free groups
--     they stand for (as RestedXP's French and Spanish lists have it), and
--     so does its default group, which it set from one of them.
--   * The leveling report leaves out the quest messages of this language.
-- This is the one place where EldoUI changes how another addon works (see
-- the rules at the top of Integrations.lua). Each wrapper calls RestedXP's
-- own function first and only fills in where RestedXP had no answer; with
-- the switch off, or the integration or module off, each passes RestedXP's
-- answer on unchanged and the group names go back to RestedXP's. A wrapper
-- stays in place once made (another addon may have wrapped the function
-- after EldoUI). RestedXP's files and saved settings are never touched.
local _, E = ...
local L = E.L

local M = E:GetModule("Integrations")

local LOCALE = GetLocale()
local ENGLISH = LOCALE == "enUS" or LOCALE == "enGB"

-- What RestedXP's own translation needs, per client language.
--   texts   RestedXP's text for a group name as it ships (`wrong`), and the
--           name of the free group in this language it stands for
--           (`right`). Only a text that is still exactly `wrong` changes.
--   groups  free group in this language -> the English group of the same
--           guides, where the paid guides carry on
--   next    per free group: the name its last guides give the next guide ->
--           the paid guide's English name
local DATA = {
	deDE = {
		texts = {
			["RestedXP Forever Guide (A)"] = { wrong = "RestedXP Forever Dungeonführer (A)", right = "RestedXP Forever Route (A)" },
			["RestedXP Forever Guide (H)"] = { wrong = "RestedXP Forever Dungeonführer (H)", right = "RestedXP Forever Route (H)" },
			["RestedXP Forever Dungeon Guide (A)"] = { wrong = "RestedXP Forever Dungeon Dungeonführer (A)", right = "RestedXP Forever Dungeonführer (A)" },
			["RestedXP Forever Dungeon Guide (H)"] = { wrong = "RestedXP Forever Dungeon Dungeonführer (H)", right = "RestedXP Forever Dungeonführer (H)" },
		},
		groups = {
			["RestedXP Forever Route (A)"] = "RestedXP Forever Guide (A)",
			["RestedXP Forever Route (H)"] = "RestedXP Forever Guide (H)",
			["RestedXP Forever Dungeonführer (A)"] = "RestedXP Forever Dungeon Guide (A)",
			["RestedXP Forever Dungeonführer (H)"] = "RestedXP Forever Dungeon Guide (H)",
			["RestedXP Allianz Magier"] = "RestedXP Alliance Mage",
			["RestedXP Horde Magier AoE"] = "RestedXP Horde Mage AoE",
			["RestedXP ADV AoE Allianz Magier"] = "RestedXP ADV AoE Alliance Mage",
		},
		next = {
			["RestedXP Forever Route (A)"] = {
				["21-23 Eschental/Steinkrallengebirge"] = "21-23 Ashenvale/Stonetalon",
				["21-23 Steinkrallengebirge/Ashenvale"] = "21-23 Stonetalon/Ashenvale",
			},
			["RestedXP Forever Route (H)"] = { ["22-24 Hügellandhof"] = "22-24 Hillsbrad" },
			["RestedXP Forever Dungeonführer (A)"] = { ["21-23 Eschental/Steinkrallengebirge"] = "21-23 Ashenvale/Stonetalon" },
			["RestedXP Forever Dungeonführer (H)"] = { ["22-24 Hügellandhof"] = "22-24 Hillsbrad" },
			["RestedXP Allianz Magier"] = { ["21-22 Dämmerwald Mage AoE"] = "21-22 Duskwood Mage AoE" },
			["RestedXP Horde Magier AoE"] = { ["21-30 Silberwald/Hillsbrad AoE"] = "21-30 Silverpine/Hillsbrad AoE" },
			["RestedXP ADV AoE Allianz Magier"] = { ["22-26 ADV Sumpfland 1 Magier AoE"] = "22-26 ADV Wetlands 1 Mage AoE" },
		},
	},
}
local data = DATA[LOCALE] or {}
local groups = data.groups or {}
local english = {} -- English group -> free group in this language
for free, group in pairs(groups) do english[group] = free end

-- The game's texts for experience from a quest (no monster named). RestedXP
-- skips these by their English start; the same texts in this language.
local QUEST_XP = {
	"COMBATLOG_XPGAIN_FIRSTPERSON_UNNAMED", "COMBATLOG_XPGAIN_FIRSTPERSON_UNNAMED_GROUP",
	"COMBATLOG_XPGAIN_FIRSTPERSON_UNNAMED_RAID", "COMBATLOG_XPGAIN_QUEST",
}

-- How many NPCs one step of the name reading takes, and how often it steps.
local NAMES_PER_STEP = 500
local STEP_SECONDS = 0.05

local rxp       -- RestedXP's addon table, once it has loaded
local made = {} -- [key] = RestedXP's own function, for each wrapper made
local kept      -- RestedXP's group names and default groups, while changed
local questXP   -- patterns of QUEST_XP in this language
local names = {
	state = "idle", -- idle | reading | ready | missing (no usable QuestieDB)
	index = nil,    -- English name -> NPC id, or a list of ids
	done = 0, total = 0,
	cache = {},     -- English name -> name here, or false for none
	translated = 0, -- names given a name in this language so far
}

local function Active()
	return rxp ~= nil and not ENGLISH and M.active and M.db.enabled
		and M.db.rxp.enabled and M.db.rxp.locale and true or false
end

-- Lets RestedXP build its target list again (it does that in its own
-- update, and waits for the end of a fight for the macro).
local function RefreshTargets()
	local targeting = rxp and rxp.targeting
	if type(targeting) == "table" and type(targeting.UpdateUnitList) == "function"
		and type(rxp.ScheduleTask) == "function" then
		pcall(rxp.ScheduleTask, rxp, targeting.UpdateUnitList)
	end
end

local function Wrap(owner, field, key, make)
	if made[key] or type(owner) ~= "table" then return end
	local own = owner[field]
	if type(own) ~= "function" then return end
	made[key] = own
	owner[field] = make(own)
end

---------------------------------------------------------------------------
-- Target names from QuestieDB
---------------------------------------------------------------------------
-- QuestieDB's NPC table (LibQuestieDB.Npc, contract 4 as Questie asks for):
-- GetRaw(id, "name") is the English name, Get(id, "name") the name in the
-- client's language, GetAllIds() every NPC.
local function QuestieNpcs()
	local lib = _G.LibQuestieDB
	local npc = type(lib) == "table" and lib.Npc
	if type(npc) ~= "table" or type(npc.Get) ~= "function" or type(npc.GetRaw) ~= "function"
		or type(npc.GetAllIds) ~= "function" then return nil end
	if type(lib.RequireContract) == "function" then
		local ok, fits = pcall(lib.RequireContract, 4)
		if not (ok and fits) then return nil end
	end
	return npc
end

local function Here(npc, id)
	local ok, name = pcall(npc.Get, id, "name")
	if ok and type(name) == "string" and name ~= "" then return name end
end

function names.Start()
	if names.state == "reading" or names.state == "ready" then return end
	local npc = QuestieNpcs()
	local ok, ids = false, nil
	if npc then ok, ids = pcall(npc.GetAllIds) end
	if not (ok and type(ids) == "table") then
		names.state = "missing"
		return
	end
	names.state, names.index, names.done, names.total = "reading", {}, 0, #ids
	local ticker
	ticker = C_Timer.NewTicker(STEP_SECONDS, function()
		if not Active() then
			-- Switched off while reading: start over when it is on again.
			ticker:Cancel()
			names.state, names.index, names.done = "idle", nil, 0
			return
		end
		if InCombatLockdown() then return end
		local index = names.index
		local last = math.min(names.done + NAMES_PER_STEP, #ids)
		for position = names.done + 1, last do
			local id = ids[position]
			local got, name = pcall(npc.GetRaw, id, "name")
			if got and type(name) == "string" and name ~= "" then
				local seen = index[name]
				if seen == nil then
					index[name] = id
				elseif type(seen) == "number" then
					index[name] = { seen, id }
				else
					seen[#seen + 1] = id
				end
			end
		end
		names.done = last
		if last >= #ids then
			ticker:Cancel()
			names.state = "ready"
			RefreshTargets()
		end
	end)
end

-- The name in this language for an English NPC name (or an NPC id, which
-- RestedXP keeps in the list until it knows the name), or nil.
local function Translate(name)
	local cached = names.cache[name]
	if cached ~= nil then return cached or nil end
	local npc = QuestieNpcs()
	if not npc then return nil end
	local result
	local id = name:match("^%d+$") and tonumber(name)
	if id then
		result = Here(npc, id)
	elseif names.state ~= "ready" then
		return nil -- not kept: asked again once the names are read
	else
		local seen = names.index[name]
		if type(seen) == "number" then
			result = Here(npc, seen)
		elseif type(seen) == "table" then
			-- Several NPCs have that English name: the name most of them
			-- have here, the first one on a tie.
			local count, best = {}, 0
			for _, each in ipairs(seen) do
				local here = Here(npc, each)
				if here then
					count[here] = (count[here] or 0) + 1
					if count[here] > best then result, best = here, count[here] end
				end
			end
		end
	end
	if result == name then result = nil end
	names.cache[name] = result or false
	if result then names.translated = names.translated + 1 end
	return result
end

local function CreatureName(own)
	return function(name, ...)
		local result = own(name, ...)
		if result ~= name or type(name) ~= "string" or not Active() then return result end
		-- A leading "*" marks a target RestedXP lists last; it takes the mark
		-- off after asking, so the name behind it is what counts.
		local mark, base = name:match("^(%*?)(.+)$")
		if not base then return result end
		if mark ~= "" then
			local listed = own(base, ...)
			if listed ~= base then return mark .. listed end
		end
		local here = Translate(base)
		if here then return mark .. here end
		return result
	end
end

---------------------------------------------------------------------------
-- The guide chain: from the free guides into the paid ones
---------------------------------------------------------------------------
local function GuideActive(guide)
	if type(rxp.IsGuideActive) ~= "function" then return true end
	local ok, on = pcall(rxp.IsGuideActive, guide)
	return ok and on and true or false
end

-- The one guide of `group` the player can use whose name starts with the
-- level range of `name` ("22-24 "), or nil (none, or more than one).
local function ByRange(own, group, name)
	local range = name:match("^(%d+%-%d+) ")
	local list = type(rxp.guideList) == "table" and (rxp.guideList[group] or rxp.guideList["*" .. group])
	local identities = type(list) == "table" and list.names_
	if not (range and type(identities) == "table") then return nil end
	local found
	for _, identity in ipairs(identities) do
		local each = type(identity) == "table" and identity.name
		if type(each) == "string" and each:sub(1, #range + 1) == range .. " " then
			local guide = own(identity.group or group, each)
			if guide and GuideActive(guide) then
				if found and found ~= guide then return nil end
				found = guide
			end
		end
	end
	return found
end

local function GuideTable(own)
	return function(group, name, ...)
		local guide = own(group, name, ...)
		if guide or type(group) ~= "string" or type(name) ~= "string" or not Active() then return guide end
		local paid = groups[group]
		if paid then
			local renamed = data.next and data.next[group] and data.next[group][name]
			guide = renamed and own(paid, renamed) or own(paid, name)
			return guide or ByRange(own, paid, name)
		end
		local free = english[group]
		if free then return own(free, name) end
		return nil
	end
end

local function ActiveGuides(own)
	return function(groupName, groupId, ...)
		local guides = own(groupName, groupId, ...)
		if type(guides) ~= "table" or type(groupName) ~= "string" or not Active() then return guides end
		local partner = groups[groupName] or english[groupName]
		if not partner then return guides end
		local seen = {}
		for _, guide in ipairs(guides) do seen[guide] = true end
		local more = own(partner, partner)
		for _, guide in ipairs(type(more) == "table" and more or {}) do
			if not seen[guide] then
				seen[guide] = true
				guides[#guides + 1] = guide
			end
		end
		return guides
	end
end

---------------------------------------------------------------------------
-- RestedXP's group names
---------------------------------------------------------------------------
local DEFAULT_FIELDS = { "defaultGroup", "defaultGroupHC" }

local function RXPTexts()
	local AceLocale = LibStub and LibStub("AceLocale-3.0", true)
	local ok, texts = false, nil
	if AceLocale then ok, texts = pcall(AceLocale.GetLocale, AceLocale, "RXPGuides", true) end
	return ok and type(texts) == "table" and texts or nil
end

local function SetGroupNames(on)
	local fixes = data.texts
	local texts = fixes and RXPTexts()
	if not texts then return end
	if on and not kept then
		kept = { texts = {}, fields = {} }
		for key, fix in pairs(fixes) do
			if rawget(texts, key) == fix.wrong then
				kept.texts[key] = fix.wrong
				rawset(texts, key, fix.right)
			end
		end
		-- RestedXP set its default group from one of these names while it
		-- loaded (DB/forever/db.lua).
		for _, field in ipairs(DEFAULT_FIELDS) do
			for key, fix in pairs(fixes) do
				if kept.texts[key] and rxp[field] == fix.wrong then
					kept.fields[field] = { old = fix.wrong, new = fix.right }
					rxp[field] = fix.right
				end
			end
		end
	elseif not on and kept then
		for key, old in pairs(kept.texts) do
			if rawget(texts, key) == fixes[key].right then rawset(texts, key, old) end
		end
		for field, change in pairs(kept.fields) do
			if rxp[field] == change.new then rxp[field] = change.old end
		end
		kept = nil
	end
end

---------------------------------------------------------------------------
-- The leveling report: experience from quests
---------------------------------------------------------------------------
-- A game text with %d and %s (also %1$d) as a whole-line pattern.
local function Pattern(text)
	local pattern = text:gsub("%%%d*%$?([ds])", function(kind) return kind == "d" and "\1" or "\2" end)
	pattern = pattern:gsub("[%%%^%$%(%)%.%[%]%*%+%-%?]", "%%%0")
	pattern = pattern:gsub("\1", "%%d+")
	pattern = pattern:gsub("\2", ".+")
	return "^" .. pattern .. "$"
end

local function IsQuestXP(text)
	if not questXP then
		questXP = {}
		for _, key in ipairs(QUEST_XP) do
			local game = _G[key]
			if type(game) == "string" and game ~= "" then questXP[#questXP + 1] = Pattern(game) end
		end
	end
	for _, pattern in ipairs(questXP) do
		-- A text the game keeps secret can't be read: it counts as before.
		local ok, found = pcall(string.match, text, pattern)
		if ok and found then return true end
	end
	return false
end

local function XPGain(own)
	return function(self, event, text, ...)
		if Active() and type(text) == "string" and IsQuestXP(text) then return end
		return own(self, event, text, ...)
	end
end

---------------------------------------------------------------------------
-- Switching it on and off
---------------------------------------------------------------------------
-- Runs with the integration's setup, when RestedXP loads and after every
-- change on the options page.
function M:SetupRXPLocale()
	if ENGLISH then return end
	if not rxp then
		if not C_AddOns.IsAddOnLoaded("RXPGuides") then return end
		local AceAddon = LibStub and LibStub("AceAddon-3.0", true)
		local ok, addon = false, nil
		if AceAddon then ok, addon = pcall(AceAddon.GetAddon, AceAddon, "RXPGuides", true) end
		if not (ok and type(addon) == "table") then return end
		rxp = addon
	end
	local on = Active()
	if on then
		Wrap(rxp, "GetCreatureName", "GetCreatureName", CreatureName)
		Wrap(rxp, "GetGuideTable", "GetGuideTable", GuideTable)
		Wrap(rxp, "GetActiveGuidesByGroupNameOrId", "GetActiveGuidesByGroupNameOrId", ActiveGuides)
		Wrap(rxp.tracker, "CHAT_MSG_COMBAT_XP_GAIN", "tracker.CHAT_MSG_COMBAT_XP_GAIN", XPGain)
		names.Start()
	end
	SetGroupNames(on)
	if on ~= (self.rxpLocaleOn or false) then
		self.rxpLocaleOn = on
		RefreshTargets()
	end
end

-- The switch shows on a client in another language while RestedXP is loaded.
function M:RXPLocaleShown()
	return not ENGLISH and C_AddOns.IsAddOnLoaded("RXPGuides") and true or false
end

-- What the switch does right now, for the options page.
function M:RXPLocaleStatus()
	if not Active() then return "" end
	local lines = {}
	if data.groups then
		lines[1] = L["RestedXP's group names are fixed, and its free guides lead on into the paid ones."]
	end
	if names.state == "ready" then
		lines[#lines + 1] = L["Target names: %d translated with QuestieDB so far."]:format(names.translated)
	elseif names.state == "reading" then
		local share = names.total > 0 and math.floor(names.done * 100 / names.total) or 0
		lines[#lines + 1] = L["Target names: reading QuestieDB's NPC names (%d%%)."]:format(share)
	else
		lines[#lines + 1] = L["Target names: QuestieDB is not loaded, so RestedXP's own list stays."]
	end
	return table.concat(lines, "\n")
end

-- For the offline test (tools/integrations/test_rxp_locale.lua).
M.rxpLocaleNames = names
