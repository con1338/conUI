-- EldoUI tooltip info rows, shown in the Tooltip info area:
--
--   Gathering   the skill a herb or ore node needs, and the skill a dead
--               mob needs for skinning (or herb / mining on special mobs),
--               colored by how your own skill compares, as the profession
--               window colors recipes
--   Mount       the mount a player rides and where it comes from (the game's
--               own Mount Journal text), out of combat
--   Targeted by the members of your group targeting this unit
--   Quest use   the quests in your log that ask for an item, each with how
--               many you have and how many it needs
--
-- Each row is a tooltip section with its own Always / Shift / Never setting
-- on the Tooltip page. Nothing here is hidden combat data: node names and
-- mob levels are what the tooltip already shows, skill ranks are your own,
-- and every unit query goes through Safe() so a secret value only skips
-- the row.
--
-- Nodes come from EldoUI's own list of gathering requirements (public
-- game knowledge, with the game's object ids), so the node row works on
-- every client language: the hovered node's object id finds it.
local _, E = ...
local L = E.L

local Safe = E.Plain

local SKILL = { herbalism = 182, mining = 186, skinning = 393, engineering = 202 }
local SKILL_NAME = E:TranslateValues({
	herbalism = E.Key("Herbalism"), mining = E.Key("Mining"), skinning = E.Key("Skinning"), engineering = E.Key("Engineering"),
})

-- A node's profession, from the shared node list (E.NodeSkill).
local NODE_SKILL = { herb = "herbalism", ore = "mining" }

-- What a dead mob needs: skinning from its level (classic rule), the same
-- rule for mobs that are herb-gathered or mined.
local function CorpseRank(level)
	if type(level) ~= "number" or level < 1 then return nil end
	if level <= 10 then return 1 end
	if level <= 20 then return (level - 10) * 10 end
	return level * 5
end

-- Your rank in a profession, or nil when you don't have it.
local function PlayerRank(skill)
	local id = SKILL[skill]
	if not id or not (C_SkillInfo and C_SkillInfo.GetSkillLineInfoByID) then return nil end
	local ok, info = pcall(C_SkillInfo.GetSkillLineInfoByID, id)
	local rank = ok and type(info) == "table" and Safe(info.rank)
	if type(rank) == "number" and rank > 0 then return rank end
end

-- The profession window's colors: red too low, orange always a skill-up,
-- yellow often, green rarely, gray never.
local function RankColor(rank, required)
	if not rank or rank < required then return 1, 0.25, 0.25 end
	if rank < required + 25 then return 1, 0.5, 0.25 end
	if rank < required + 50 then return 1, 1, 0 end
	if rank < required + 100 then return 0.25, 0.75, 0.25 end
	return 0.55, 0.55, 0.55
end

local function AddSkillRow(add, skill, required)
	local rank = PlayerRank(skill)
	local r, g, b = RankColor(rank, required)
	local right = tostring(required)
	if rank then
		right = right .. E:TextHex("secondary") .. " " .. L["(you %d)"]:format(rank) .. "|r"
	end
	add(SKILL_NAME[skill], right, nil, nil, nil, r, g, b)
end

-- Tooltip lines of the mob that say which gathering skill its corpse needs.
local function CorpseSkill(tooltip)
	local name = tooltip:GetName()
	if not name then return end
	local checks = {
		{ _G.UNIT_SKINNABLE_LEATHER, "skinning" },
		{ _G.UNIT_SKINNABLE_HERB, "herbalism" },
		{ _G.UNIT_SKINNABLE_ROCK, "mining" },
		{ _G.UNIT_SKINNABLE_BOLTS, "engineering" },
	}
	for index = 2, tooltip:NumLines() do
		local line = _G[name .. "TextLeft" .. index]
		local text = line and Safe(line:GetText())
		if type(text) == "string" then
			for _, check in ipairs(checks) do
				if type(check[1]) == "string" and text == check[1] then return check[2] end
			end
		end
	end
end

E:RegisterTooltipSection("gathering", {
	order = 45,
	title = "Gathering skill",
	desc = "The Herbalism, Mining or Skinning rank a node or corpse needs, colored by your own rank like the profession window (red: too low, gray: no more skill-ups).",
	default = "always",
	object = function(_, name, add, data)
		local nodes = E.NodeSkill
		if not nodes then return end
		local entry
		if not E.Secret(data) and type(data) == "table" and (not canaccesstable or canaccesstable(data)) then
			entry = nodes.EntryOf(data.guid)
		end
		local node = nodes:Find(name, entry)
		local skill = node and NODE_SKILL[node.kind]
		if not skill then return end
		AddSkillRow(add, skill, node.rank)
		if not (E.GatheringItemCounts and node.itemID) then return end
		local carried, total = E:GatheringItemCounts(node.itemID)
		if carried == nil then return end
		add(total and L["You have: %d · all characters %d"]:format(carried, total) or L["You have: %d"]:format(carried))
	end,
	unit = function(tooltip, unit, add)
		if Safe(UnitIsPlayer(unit)) then return end
		local skill = CorpseSkill(tooltip)
		if not skill then return end
		local required = CorpseRank(Safe(UnitLevel(unit)))
		if not required then return end
		if skill == "engineering" then
			add(SKILL_NAME.engineering, nil)
			return
		end
		AddSkillRow(add, skill, required)
	end,
})

---------------------------------------------------------------------------
-- Mount: what a player rides, from the game's Mount Journal
---------------------------------------------------------------------------
local function CleanSource(text)
	if type(text) ~= "string" or text == "" then return nil end
	text = text:gsub("|n", " · "):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("%s+$", "")
	return text
end

-- Reads the unit's buffs, which WoW: Forever only allows out of combat
-- (C_UnitAuras.GetAuraDataByIndex throws in combat): skipped in combat.
local function FindMount(unit)
	if InCombatLockdown() then return end
	if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex and C_MountJournal and C_MountJournal.GetMountFromSpell) then return end
	for index = 1, 40 do
		local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, unit, index, "HELPFUL")
		if not ok or type(aura) ~= "table" then return end
		local spellID = Safe(aura.spellId)
		if type(spellID) == "number" then
			local mountID = Safe(C_MountJournal.GetMountFromSpell(spellID))
			if type(mountID) == "number" then return mountID end
		end
	end
end

E:RegisterTooltipSection("mount", {
	order = 46,
	title = "Mount",
	desc = "The mount a player rides, whether you have it, and where it comes from (Mount Journal text). Out of combat only.",
	default = "always",
	unit = function(_, unit, add)
		if InCombatLockdown() or not Safe(UnitIsPlayer(unit)) then return end
		local mountID = FindMount(unit)
		if not mountID then return end
		local name, _, _, _, _, _, _, _, _, _, collected = C_MountJournal.GetMountInfoByID(mountID)
		name, collected = Safe(name), Safe(collected)
		if type(name) ~= "string" then return end
		local mark = collected and " " .. E:TextHex("good") .. L["(you have it)"] .. "|r" or ""
		add(L["Mount"], name .. mark)
		if C_MountJournal.GetMountInfoExtraByID then
			local _, _, source = C_MountJournal.GetMountInfoExtraByID(mountID)
			source = CleanSource(Safe(source))
			if source then add(source, nil, 0.75, 0.75, 0.75) end
		end
	end,
})

---------------------------------------------------------------------------
-- Targeted by: group members whose target is this unit
---------------------------------------------------------------------------
local function GroupUnits()
	local units = {}
	if IsInRaid() then
		for index = 1, GetNumGroupMembers() do units[#units + 1] = "raid" .. index end
	elseif IsInGroup() then
		units[1] = "player"
		for index = 1, GetNumSubgroupMembers() do units[#units + 1] = "party" .. index end
	end
	return units
end

local function ClassName(unit)
	local name = Safe(E:DisplayName(unit, "Tooltip"))
	if type(name) ~= "string" then return nil end
	local _, class = UnitClass(unit)
	class = Safe(class)
	local color = E:ClassColorObject(class)
	if color then return color:WrapTextInColorCode(name) end
	return name
end

E:RegisterTooltipSection("targetedBy", {
	order = 47,
	title = "Targeted by",
	desc = "Members of your party or raid who have this unit targeted. Skipped whenever the game keeps targets secret.",
	default = "always",
	unit = function(_, unit, add)
		local names = {}
		for _, member in ipairs(GroupUnits()) do
			if Safe(UnitExists(member .. "target")) and Safe(UnitIsUnit(member .. "target", unit)) then
				local name = ClassName(member)
				if name then names[#names + 1] = name end
			end
		end
		if #names == 0 then return end
		local shown = #names > 6 and (table.concat(names, ", ", 1, 6) .. (" +%d"):format(#names - 6)) or table.concat(names, ", ")
		add(L["Targeted by (%d)"]:format(#names), shown)
	end,
})

---------------------------------------------------------------------------
-- Quest use: quests in your log that ask for this item, with the count
---------------------------------------------------------------------------
-- The log is read into an index by item name on the first hover after a
-- quest log event, so a hover is one table lookup. The rows themselves are
-- never kept, so the count is always the game's current one.
local QuestUse = { dirty = true, byName = {}, byQuest = {}, MAX = 2 }
E.QuestUse = QuestUse

-- The item an objective asks for, lower case: "Linen Cloth: 4/10",
-- "4/10 Linen Cloth" or "Linen Cloth: 10/10 (Complete)" give "linen cloth".
function QuestUse.ObjectiveItem(text)
	if type(text) ~= "string" then return nil end
	text = text:gsub("%s*%b()%s*$", "")
	local name = text:match("^(.-)%s*:%s*%d+%s*/%s*%d+$") or text:match("^%d+%s*/%s*%d+%s+(.+)$")
	return name and name ~= "" and name:lower() or nil
end

local function Objectives(questID, title)
	local items = {}
	local ok, list = pcall(C_QuestLog.GetQuestObjectives, questID)
	if not ok or type(list) ~= "table" then return items end
	for _, objective in ipairs(list) do
		local kind = type(objective) == "table" and Safe(objective.type)
		local name = (kind == nil or kind == "item") and QuestUse.ObjectiveItem(Safe(objective.text))
		local have, need = tonumber(Safe(objective.numFulfilled)) or 0, tonumber(Safe(objective.numRequired))
		if name and need and need > 0 then
			local entry = { questID = questID, title = title, name = name, have = have, need = need,
				done = Safe(objective.finished) == true or have >= need }
			QuestUse.byName[name] = QuestUse.byName[name] or {}
			table.insert(QuestUse.byName[name], entry)
			items[#items + 1] = entry
		end
	end
	return items
end

function QuestUse.Rebuild()
	QuestUse.dirty = false
	QuestUse.byName, QuestUse.byQuest = {}, {}
	local log = C_QuestLog
	if not (log and log.GetNumQuestLogEntries and log.GetInfo and log.GetQuestObjectives) then return end
	local ok, count = pcall(log.GetNumQuestLogEntries)
	for index = 1, ok and tonumber(Safe(count)) or 0 do
		local got, info = pcall(log.GetInfo, index)
		if got and type(info) == "table" and not Safe(info.isHeader) and not Safe(info.isHidden) then
			local questID, title = Safe(info.questID), Safe(info.title)
			if type(questID) == "number" and type(title) == "string" and title ~= "" then
				QuestUse.byQuest[questID] = { title = title, items = Objectives(questID, title) }
			end
		end
	end
end

local function ItemName(itemID, link)
	local name = itemID and C_Item.GetItemNameByID and Safe((C_Item.GetItemNameByID(itemID)))
	if type(name) ~= "string" and C_Item.GetItemInfo then name = Safe((C_Item.GetItemInfo(link or itemID))) end
	return type(name) == "string" and name ~= "" and name or nil
end

-- The quests in the log that ask for the item, in log order: matched by
-- the item's name, and with the Loot Guide data also by its quest list.
function QuestUse.Find(itemID, link)
	if QuestUse.dirty then QuestUse.Rebuild() end
	local found, seen = {}, {}
	local name = ItemName(itemID, link)
	for _, entry in ipairs(name and QuestUse.byName[name:lower()] or {}) do
		if not seen[entry.questID] then
			seen[entry.questID] = true
			found[#found + 1] = entry
		end
	end
	-- The Loot Guide is read in place: this tooltip part belongs to no
	-- module of its own.
	local guide = itemID and E.LootGuide
	if guide and guide.HasData and guide:HasData() then
		local ok, quests = pcall(guide.ItemQuests, guide, itemID)
		for _, questID in ipairs(ok and type(quests) == "table" and quests.needed or {}) do
			local quest = QuestUse.byQuest[questID]
			if quest and not seen[questID] then
				seen[questID] = true
				found[#found + 1] = #quest.items == 1 and quest.items[1] or { questID = questID, title = quest.title }
			end
		end
	end
	return found
end

-- The quests this section names for the item (the Loot Guide's "Needed
-- for" row leaves them out).
function QuestUse.Shown(itemID, link)
	local ids = {}
	for index, entry in ipairs(QuestUse.Find(itemID, link)) do
		if index > QuestUse.MAX then break end
		ids[#ids + 1] = entry.questID
	end
	return ids
end

local function MarkDirty() QuestUse.dirty = true end
for _, event in ipairs({ "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN" }) do
	E:RegisterEvent(event, MarkDirty, QuestUse)
end

E:RegisterTooltipSection("questUse", {
	order = 48.5,
	title = "Quest use",
	desc = "Quests in your log that ask for this item, with how many you have and how many they need.",
	default = "always",
	item = function(_, link, itemID, add)
		itemID = tonumber(Safe(itemID)) or (type(link) == "string" and tonumber(link:match("item:(%d+)")))
		if not itemID then return end
		local found = QuestUse.Find(itemID, link)
		for index = 1, math.min(#found, QuestUse.MAX) do
			local entry = found[index]
			local count = ""
			if entry.need then
				count = entry.done and ("   " .. E:TextHex("good") .. L["%d/%d done"]:format(entry.have, entry.need) .. "|r")
					or ("   |cffffffff%d/%d|r"):format(entry.have, entry.need)
			end
			add(index == 1 and L["For quest"] or " ", entry.title .. count)
		end
		if #found > QuestUse.MAX then add(" ", L["(+%d more)"]:format(#found - QuestUse.MAX), nil, nil, nil, 0.65, 0.65, 0.7) end
	end,
})
