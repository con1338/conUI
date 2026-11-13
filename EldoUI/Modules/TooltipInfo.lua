-- EldoUI tooltip info rows, shown in the Tooltip info area:
--
--   Gathering   the skill a herb or ore node needs, and the skill a dead
--               mob needs for skinning (or herb / mining on special mobs),
--               colored by how your own skill compares, as the profession
--               window colors recipes
--   Mount       the mount a player rides and where it comes from (the game's
--               own Mount Journal text), out of combat
--   Targeted by the members of your group targeting this unit
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
		local node = nodes:Find(name, type(data) == "table" and nodes.EntryOf(data.guid) or nil)
		local skill = node and NODE_SKILL[node.kind]
		if skill then AddSkillRow(add, skill, node.rank) end
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
