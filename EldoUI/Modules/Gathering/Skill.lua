-- EldoUI Gathering: required skill per node and the skill filter.
--
-- The skill a herb or vein needs is a fixed fact of the game, written here
-- with the object ids the game gives each node. A node is known by its
-- object id first (a node's tooltip in the world carries it, the same on
-- every client language), then by its English name, then by a name this
-- account saw once together with the object id, then by the translated
-- names in EldoUI_LootData when it is loaded (German and Chinese). Your
-- own skill comes from the game's skill list (C_SkillInfo). The color is
-- the game's usual skill-up color for gathering: red below the skill,
-- orange, yellow, green, then gray when it no longer raises your skill.
local _, E = ...
local L = E.L
local M = E.Gathering
local Kit = E.UIKit


local Clean = E.Plain

-- English node name -> { required skill, main yield item ID, object IDs... }
local NODE_DATA = {
	herb = {
		["Peacebloom"] = { 1, 2447, 1618, 3724 },
		["Silverleaf"] = { 1, 765, 1617, 3725 },
		["Earthroot"] = { 15, 2449, 1619, 3726 },
		["Mageroyal"] = { 50, 785, 1620, 3727 },
		["Briarthorn"] = { 70, 2450, 1621, 3729 },
		["Stranglekelp"] = { 85, 3820, 2045 },
		["Bruiseweed"] = { 100, 2453, 1622, 3730 },
		["Wild Steelbloom"] = { 115, 3355, 1623 },
		["Grave Moss"] = { 120, 3369, 1628 },
		["Kingsblood"] = { 125, 3356, 1624 },
		["Liferoot"] = { 150, 3357, 2041 },
		["Fadeleaf"] = { 160, 3818, 2042 },
		["Goldthorn"] = { 170, 3821, 2046 },
		["Khadgar's Whisker"] = { 185, 3358, 2043 },
		["Wintersbite"] = { 195, 3819, 2044 },
		["Firebloom"] = { 205, 4625, 2866 },
		["Purple Lotus"] = { 210, 8831, 142140, 180165 },
		["Arthas' Tears"] = { 220, 8836, 142141, 176642 },
		["Sungrass"] = { 230, 8838, 142142, 176636, 180164 },
		["Blindweed"] = { 235, 8839, 142143, 183046 },
		["Ghost Mushroom"] = { 245, 8845, 142144 },
		["Gromsblood"] = { 250, 8846, 142145, 176637 },
		["Golden Sansam"] = { 260, 13464, 176583, 176638, 180167 },
		["Dreamfoil"] = { 270, 13463, 176584, 176639, 180168 },
		["Mountain Silversage"] = { 280, 13465, 176586, 176640, 180166 },
		["Plaguebloom"] = { 285, 13466, 176587, 176641 },
		["Icecap"] = { 290, 13467, 176588 },
		["Black Lotus"] = { 300, 13468, 176589 },
	},
	ore = {
		["Copper Vein"] = { 1, 2770, 1731, 2055, 3763, 103713, 181248 },
		["Tin Vein"] = { 65, 2771, 1732, 2054, 3764, 103711, 181249 },
		["Incendicite Mineral Vein"] = { 65, 3340, 1610, 1667 },
		["Silver Vein"] = { 75, 2775, 1733, 105569 },
		["Ooze Covered Silver Vein"] = { 75, 2775, 73940 },
		["Lesser Bloodstone Deposit"] = { 75, 4278, 2653 },
		["Iron Deposit"] = { 125, 2772, 1735 },
		["Indurium Mineral Vein"] = { 150, 5833, 19903 },
		["Gold Vein"] = { 155, 2776, 1734, 150080, 181109 },
		["Ooze Covered Gold Vein"] = { 155, 2776, 73941 },
		["Mithril Deposit"] = { 175, 3858, 2040, 150079, 176645 },
		["Ooze Covered Mithril Deposit"] = { 175, 3858, 123310 },
		["Truesilver Deposit"] = { 230, 7911, 2047, 150081, 181108 },
		["Ooze Covered Truesilver Deposit"] = { 230, 7911, 123309 },
		["Dark Iron Deposit"] = { 230, 11370, 165658 },
		["Small Thorium Vein"] = { 245, 10620, 324, 150082, 176643 },
		["Ooze Covered Thorium Vein"] = { 245, 10620, 123848 },
		["Rich Thorium Vein"] = { 275, 10620, 175404 },
		["Ooze Covered Rich Thorium Vein"] = { 275, 10620, 177388 },
		["Hakkari Thorium Vein"] = { 275, 10620, 180215 },
	},
}

-- E.NodeSkill: the gathering node behind a shown name or object id,
-- shared by the map pins and the tooltip's Gathering skill row.
local Nodes = { byName = {}, byEntry = {} }
E.NodeSkill = Nodes
M.REQUIRED_SKILL = {}
for kind, list in pairs(NODE_DATA) do
	M.REQUIRED_SKILL[kind] = {}
	for name, data in pairs(list) do
		local info = { kind = kind, name = name, rank = data[1], itemID = data[2] }
		M.REQUIRED_SKILL[kind][name] = data[1]
		Nodes.byName[name] = info
		for index = 3, #data do Nodes.byEntry[data[index]] = info end
	end
end

-- Names in the client's language, seen together with a node's object id:
-- the shown name -> the English name. Plain words only.
E:RegisterGlobal("gatherNodeNames", {})

local function Learned()
	local saved = E:GetGlobal("gatherNodeNames")
	return type(saved) == "table" and saved or nil
end

-- Translated node names from EldoUI_LootData, when it is loaded. Built
-- once for each loaded copy.
local lootNames, lootSource
local function LootNames()
	local data = rawget(_G, "EldoUI_LootData")
	local objects = type(data) == "table" and type(data.L) == "table" and data.L.objects
	if type(objects) ~= "table" then return nil end
	if lootSource ~= objects then
		lootSource, lootNames = objects, {}
		for entry, info in pairs(Nodes.byEntry) do
			local name = objects[entry]
			if type(name) == "string" and name ~= "" then lootNames[name] = info end
		end
	end
	return lootNames
end

-- The node for a shown name and/or object id: { kind = "herb" or "ore",
-- name = the English name, rank = the skill it needs, itemID = its main yield }, or nil.
function Nodes:Find(name, entry)
	name = Clean(name)
	if type(name) ~= "string" or name == "" then name = nil end
	entry = Clean(entry)
	local info = type(entry) == "number" and self.byEntry[entry] or nil
	if info then
		local saved = name and name ~= info.name and Learned()
		if saved and saved[name] ~= info.name then saved[name] = info.name end
		return info
	end
	if not name then return nil end
	info = self.byName[name]
	if info then return info end
	local saved = Learned()
	local english = saved and saved[name]
	if type(english) == "string" and self.byName[english] then return self.byName[english] end
	local loot = LootNames()
	return loot and loot[name] or nil
end

-- The object id in a GameObject GUID, or nil.
function Nodes.EntryOf(guid)
	guid = Clean(guid)
	if type(guid) ~= "string" then return nil end
	local kind, entry = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
	if kind == "GameObject" then return tonumber(entry) end
end

-- Hovering a node teaches its shown name, so map pins saved under a
-- translated name know their skill too.
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType
	and Enum.TooltipDataType.Object then
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Object, function(tooltip, data)
		if tooltip ~= GameTooltip or type(data) ~= "table" then return end
		local entry = Nodes.EntryOf(data.guid)
		if not (entry and Nodes.byEntry[entry]) then return end
		local line = type(data.lines) == "table" and data.lines[1]
		Nodes:Find(type(line) == "table" and line.leftText or nil, entry)
	end)
end

-- The skill a node needs, or nil when unknown (treasure, fishing, or a
-- translated name not seen with its object id yet).
function M:RequiredSkill(node)
	if not (node and self.REQUIRED_SKILL[node.k]) then return nil end
	local info = Nodes:Find(node.n)
	return info and info.kind == node.k and info.rank or nil
end

-- Your rank in a kind's profession, or nil when the game gives none
-- (not learned, or the skill list isn't there). Cached until the skill
-- list changes.
local rankCache = {}
function M:PlayerSkill(kindKey)
	if rankCache[kindKey] ~= nil then return rankCache[kindKey] or nil end
	local kind = self.kindByKey[kindKey]
	local rank
	if kind and kind.skillLine and C_SkillInfo and C_SkillInfo.GetSkillLineInfoByID then
		local ok, info = pcall(C_SkillInfo.GetSkillLineInfoByID, kind.skillLine)
		if ok and type(info) == "table" then
			rank = Clean(info.rank)
			if type(rank) ~= "number" then rank = nil end
		end
	end
	rankCache[kindKey] = rank or false
	return rank
end

function M:SkillChanged()
	wipe(rankCache)
	if self.active then self:RefreshPins() end
end

-- Skill-up step of a node for your rank: "red" (too low), "orange",
-- "yellow", "green" or "gray"; nil when either side is unknown.
function M:SkillStep(node)
	local required = self:RequiredSkill(node)
	local rank = required and self:PlayerSkill(node.k)
	if not (required and rank) then return nil end
	if rank < required then return "red" end
	if rank < required + 25 then return "orange" end
	if rank < required + 50 then return "yellow" end
	if rank < required + 100 then return "green" end
	return "grey"
end

local STEP_COLORS = {
	red = Kit.BAD,
	orange = { 1, 0.5, 0.25 },
	yellow = { 1, 1, 0 },
	green = { 0.25, 0.75, 0.25 },
}
function M.SkillStepColor(step)
	if step == "grey" then return unpack(Kit.DIM) end
	local color = STEP_COLORS[step]
	if color then return color[1], color[2], color[3] end
	return unpack(Kit.SECONDARY)
end

-- The skill filter (option skillFilter): all, canGather (hide what you
-- can't gather yet) or skillUp (also hide gray nodes).
function M:SkillHides(node)
	local mode = self.db and self.db.skillFilter
	if mode ~= "canGather" and mode ~= "skillUp" then return false end
	local step = self:SkillStep(node)
	if step == "red" then return true end
	return mode == "skillUp" and step == "grey"
end

-- The tooltip row: "Requires Herbalism 150" colored by skill-up step.
function M:SkillLine(node)
	local required = self:RequiredSkill(node)
	if not required then return nil end
	local kind = self.kindByKey[node.k]
	local profession = kind.key == "herb" and L["Herbalism"] or L["Mining"]
	return L["Requires %s %d"]:format(profession, required), self.SkillStepColor(self:SkillStep(node))
end
