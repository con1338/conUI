-- EldoUI Zone Info: facts about a zone where you look for them.
--
--   * World map: hovering a zone on a continent map adds a tooltip with its
--     level range (colored by your level), the herb, ore, skinning and
--     fishing ranges (colored by your chance of a skill-up), the dungeons
--     and raids whose entrance lies there (new ones marked "New in Forever")
--     and whose territory it is. Shift lists the node types found there.
--     With My Adventure on, your journal adds when you first came, your
--     time there and your runs in its dungeons (M:RegisterLines).
--   * Zone toast (off by default): the zone's name, level range and
--     territory when you enter a new zone, on its own mover.
--
-- Hooked after the world map's area label (AreaLabelFrameMixin, the frame
-- that shows the zone name under the cursor): hooksecurefunc on that one
-- frame's EvaluateLabels, which the label calls every frame. Nothing of
-- Blizzard's is replaced.
--
-- The facts come from the game first (C_Map.GetMapLevels,
-- C_EncounterJournal.GetDungeonEntrancesForMap, C_PvP.GetZonePVPInfo, your
-- skills from C_SkillInfo, your own finds from the Gathering module) and
-- from Data/Zones.lua otherwise. Presentation only.
local _, E = ...
local L = E.L

local issecret = issecretvalue or function() return false end

local M = E:NewModule("ZoneInfo", {
	title = "Zone Info",
	category = "Quality of Life",
	desc = "World map tooltip with a zone's level and gathering ranges, dungeons and territory, and an optional toast when you enter a zone.",
	defaults = {
		tooltip = true,        -- the world map hover tooltip
		showLevels = true,
		showGathering = true,  -- herbalism and mining
		showSkinning = true,
		showFishing = true,
		showInstances = true,
		showFaction = true,
		onlyKnown = false,     -- profession lines only for professions you have
		colorize = true,       -- color by your level and skill
		shiftNodes = true,     -- Shift lists the node types
		showJournal = true,    -- My Adventure: your first visit, time there and runs

		toast = false,         -- zone toast on zone change
		toastDuration = 4,
		toastLayout = "stacked", -- stacked | line | banner
		toastLook = "panel",     -- panel | transparent | edge | none
		toastSize = 18,          -- title font size
		toastAnim = "slide",     -- slide | pop | none
		toastLevels = true,
		toastFaction = true,
		toastPvPColor = true,    -- zone name in its territory color
	},
})
E.ZoneInfo = M

local Z = E.zoneData or { herbs = {}, ore = {}, instances = {}, zones = {}, originalInstanceMaps = {}, originalInstanceNames = {} }
M.data = Z

-- Skill lines (C_SkillInfo skill IDs).
local SKILL = { herb = 182, ore = 186, skinning = 393, fishing = 356 }
M.SKILL = SKILL

local MOVER = "EldoUI_ZoneToast"
M.MOVER = MOVER

local Clean = E.Plain

local function Try(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a, b, c, d = pcall(fn, ...)
	if ok then return a, b, c, d end
end

local function Secondary()
	local text = E.media.text
	if type(text) == "table" and type(text.secondary) == "table" then return unpack(text.secondary) end
	return unpack(E.WindowKit.SECONDARY)
end

local function Hex(r, g, b)
	return ("|cff%02x%02x%02x"):format(math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

---------------------------------------------------------------------------
-- Colors (the game's own difficulty colors where it has them)
---------------------------------------------------------------------------
local FALLBACK_COLORS = {
	impossible = { r = 1, g = 0.1, b = 0.1 },
	verydifficult = { r = 1, g = 0.5, b = 0.25 },
	difficult = { r = 1, g = 0.82, b = 0 },
	standard = { r = 0.25, g = 0.75, b = 0.25 },
}

-- r, g, b of a difficulty ("impossible" ... "trivial").
function M.DifficultyRGB(kind)
	if kind == "trivial" or kind == "header" then return Secondary() end
	local colors = rawget(_G, "QuestDifficultyColors")
	local c = type(colors) == "table" and colors[kind] or FALLBACK_COLORS[kind] or FALLBACK_COLORS.difficult
	return c.r or 1, c.g or 1, c.b or 1
end

-- Skill-up chance of a node or mob needing `req` at skill `skill`:
-- impossible (can't yet), verydifficult (orange: always), difficult
-- (yellow: often), standard (green: sometimes), trivial (gray: never).
function M.SkillChance(skill, req)
	if not skill or not req then return nil end
	if skill < req then return "impossible" end
	if skill < req + 25 then return "verydifficult" end
	if skill < req + 50 then return "difficult" end
	if skill < req + 100 then return "standard" end
	return "trivial"
end

-- The best chance among a list of requirements: the hardest one you can
-- already do. Nothing you can do yet is "impossible".
function M.BestChance(skill, reqs)
	if not skill then return nil end
	local best
	for _, req in ipairs(reqs) do
		if req <= skill and (not best or req > best) then best = req end
	end
	if not best then return "impossible" end
	return M.SkillChance(skill, best)
end

-- Skill a mob of `level` asks of a skinner.
function M.SkinningReq(level)
	if level <= 10 then return 1 end
	if level <= 20 then return (level - 10) * 10 end
	return level * 5
end

-- The level-range color, as the world map's own zone label does it.
function M.LevelRGB(low, high, level)
	level = level or Clean(UnitLevel("player"))
	if type(level) ~= "number" then return M.DifficultyRGB("difficult") end
	local GetColor = rawget(_G, "GetQuestDifficultyColor")
	local c
	if type(GetColor) == "function" then
		if level < low then
			c = Try(GetColor, low)
		elseif level > high then
			c = Try(GetColor, high - 2)
		end
	end
	if type(c) == "table" then return c.r or 1, c.g or 1, c.b or 1 end
	if level < low then
		if low - level >= 5 then return M.DifficultyRGB("impossible") end
		return M.DifficultyRGB(low - level >= 3 and "verydifficult" or "difficult")
	elseif level > high then
		if level - high >= 8 then return M.DifficultyRGB("trivial") end
		return M.DifficultyRGB("standard")
	end
	return M.DifficultyRGB("difficult")
end

local function RangeText(low, high)
	if not low then return "" end
	if not high or low == high then return tostring(low) end
	return ("%d-%d"):format(low, high)
end
M.RangeText = RangeText

---------------------------------------------------------------------------
-- What the game and the data know about a zone
---------------------------------------------------------------------------
-- Your rank in a profession, or nil when you don't have it.
function M:PlayerSkill(kind)
	local id = SKILL[kind]
	if self.skillOverride then return self.skillOverride[kind] end
	if not (id and C_SkillInfo and C_SkillInfo.GetSkillLineInfoByID) then return nil end
	local info = Try(C_SkillInfo.GetSkillLineInfoByID, id)
	if type(info) ~= "table" then return nil end
	local rank = Clean(info.rank)
	if type(rank) ~= "number" or rank <= 0 then return nil end
	return rank
end

function M:Levels(mapID)
	local low, high = E:ZoneLevelRange(mapID)
	return low, high
end

-- "Alliance", "Horde", "contested", "sanctuary" or nil. The game's own
-- answer for the zone you stand in, the data for the others.
function M:Territory(mapID)
	if mapID and C_Map and C_Map.GetBestMapForUnit and C_PvP and C_PvP.GetZonePVPInfo then
		local here = Clean(Try(C_Map.GetBestMapForUnit, "player"))
		if here == mapID then
			local pvpType, _, factionName = Try(C_PvP.GetZonePVPInfo)
			pvpType, factionName = Clean(pvpType), Clean(factionName)
			if pvpType == "sanctuary" or pvpType == "contested" then return pvpType end
			local mine = Clean(UnitFactionGroup("player"))
			if pvpType == "friendly" and mine then return mine end
			if pvpType == "hostile" and mine then return mine == "Alliance" and "Horde" or "Alliance" end
			if type(factionName) == "string" and (factionName == "Alliance" or factionName == "Horde") then return factionName end
		end
	end
	local zone = Z.zones[mapID]
	return zone and zone.faction or nil
end

local TERRITORY_TEXT = {
	Alliance = "Alliance territory",
	Horde = "Horde territory",
	contested = "Contested territory",
	sanctuary = "Sanctuary",
}

function M:TerritoryText(territory)
	if not territory then return nil end
	local text = L[TERRITORY_TEXT[territory] or territory]
	local r, g, b
	if territory == "contested" then
		r, g, b = M.DifficultyRGB("verydifficult")
	elseif territory == "sanctuary" then
		r, g, b = 0.41, 0.8, 0.94 -- the game's sanctuary blue (ZoneText)
	else
		local mine = Clean(UnitFactionGroup("player"))
		r, g, b = M.DifficultyRGB(mine == territory and "standard" or "impossible")
	end
	return text, r, g, b
end

local function NodeList(keys, pool)
	local list = {}
	for _, key in ipairs(keys or {}) do
		local node = pool[key]
		if node then list[#list + 1] = node end
	end
	return list
end

-- Requirement of a node by its (English or translated) name.
local reqByName
function M.NodeReq(name)
	if type(name) ~= "string" then return nil end
	if not reqByName then
		reqByName = {}
		for _, pool in ipairs({ Z.herbs, Z.ore }) do
			for _, node in pairs(pool) do
				reqByName[node.name:lower()] = node.skill
				reqByName[L[node.name]:lower()] = node.skill
			end
		end
	end
	return reqByName[name:lower()]
end

-- Dungeons and raids with an entrance in the zone: the data's list plus
-- every entrance the game shows; one the original game did not have is
-- marked new.
local function IsOriginalName(folded)
	if folded == "" then return false end
	for name in pairs(Z.originalInstanceNames) do
		if folded:sub(1, #name) == name or name:sub(1, #folded) == folded then return true end
	end
	return false
end
M.IsOriginalName = IsOriginalName

function M:Instances(mapID)
	local list, seen = {}, {}
	local Fold = Z.Fold or function(text) return tostring(text or ""):lower() end
	local zone = Z.zones[mapID]
	for _, key in ipairs(zone and zone.instances or {}) do
		local inst = Z.instances[key]
		if inst then
			list[#list + 1] = { name = L[inst.name], kind = inst.kind, min = inst.min, max = inst.max, new = inst.new and true or false }
			seen[Fold(inst.name)] = true
			seen[Fold(L[inst.name])] = true
		end
	end
	if C_EncounterJournal and C_EncounterJournal.GetDungeonEntrancesForMap then
		local entrances = Try(C_EncounterJournal.GetDungeonEntrancesForMap, mapID)
		if type(entrances) == "table" then
			for _, entrance in ipairs(entrances) do
				local name = type(entrance) == "table" and Clean(entrance.name)
				if type(name) == "string" and name ~= "" then
					local folded = Fold(name)
					local known = seen[folded]
					if not known then
						for other in pairs(seen) do
							if other ~= "" and (folded:sub(1, #other) == other or other:sub(1, #folded) == folded) then known = true break end
						end
					end
					if not known then
						seen[folded] = true
						list[#list + 1] = { name = name, new = not IsOriginalName(folded) }
					end
				end
			end
		end
	end
	return list
end

---------------------------------------------------------------------------
-- Node types for the Shift list
---------------------------------------------------------------------------
local KIND_ALIASES = { herb = "herb", herbs = "herb", herbalism = "herb", ore = "ore", mining = "ore", mine = "ore", treasure = "treasure" }

local function KindOf(value)
	if type(value) == "table" then value = value.key end
	if type(value) ~= "string" then return nil end
	return KIND_ALIASES[value:lower()] or value:lower()
end

-- Turns whatever Gathering:NodeTypesInZone returns into a list of
-- { name, kind, count }: a list of names, a list of records (Gathering's
-- NodeTypesInZone rows count their finds), name -> count,
-- or kind -> list.
function M.NormalizeNodeTypes(result)
	local out = {}
	if type(result) ~= "table" then return out end
	local function Add(name, kind, count)
		if type(name) ~= "string" or issecret(name) or name == "" then return end
		out[#out + 1] = { name = name, kind = KindOf(kind), count = type(count) == "number" and count or nil }
	end
	local function AddRecord(record, kind)
		if type(record) == "string" then
			Add(record, kind)
		elseif type(record) == "table" then
			local name = record.name or record.n or record.label
			Add(name, record.kind or record.k or kind, record.count or record.finds or record.c or (type(record.n) == "number" and record.n or nil))
		end
	end
	for key, value in pairs(result) do
		if type(key) == "number" then
			AddRecord(value)
		elseif type(key) == "string" then
			if type(value) == "number" then
				Add(key, nil, value)
			elseif value == true then
				Add(key)
			elseif type(value) == "table" then
				if #value > 0 then
					for _, record in ipairs(value) do AddRecord(record, key) end
				else
					Add(key, value.kind or value.k, value.count or value.c)
				end
			end
		end
	end
	table.sort(out, function(a, b)
		if (a.kind or "") ~= (b.kind or "") then return (a.kind or "") < (b.kind or "") end
		return a.name < b.name
	end)
	return out
end

-- Node types of a zone: your Gathering finds when that module knows the
-- zone, else the data's typical nodes. Returns the list and its source
-- ("finds" or "data").
function M:NodeTypes(mapID)
	local gathering = E.modules.Gathering
	if gathering and type(gathering.NodeTypesInZone) == "function" then
		local ok, result = pcall(gathering.NodeTypesInZone, gathering, mapID)
		if ok then
			local list = M.NormalizeNodeTypes(result)
			if #list > 0 then return list, "finds" end
		end
	end
	local list = {}
	local zone = Z.zones[mapID]
	if zone then
		for _, node in ipairs(NodeList(zone.herbs, Z.herbs)) do list[#list + 1] = { name = L[node.name], kind = "herb", req = node.skill } end
		for _, node in ipairs(NodeList(zone.ore, Z.ore)) do list[#list + 1] = { name = L[node.name], kind = "ore", req = node.skill } end
	end
	return list, "data"
end

---------------------------------------------------------------------------
-- Tooltip lines (built as data before they are shown)
---------------------------------------------------------------------------
local function Line(lines, left, right, lr, lg, lb, rr, rg, rb)
	lines[#lines + 1] = { left = left, right = right, lr = lr, lg = lg, lb = lb, rr = rr, rg = rg, rb = rb }
end

-- Lines other modules add at the end, after a divider (My Adventure:
-- when you first came here, your time there and your runs):
--   M:RegisterLines(key, { order, option = "<db key>", live = fn,
--       lines = fn(mapID, shift) -> { { left, right, lr, lg, lb, rr, rg, rb }, ... } })
-- `option` names this module's tick that shows them; `live` says whether
-- the provider can answer now (its tick hides while it can't).
local lineProviders, providerOrder = {}, {}

function M:RegisterLines(key, def)
	if type(key) ~= "string" or type(def) ~= "table" or type(def.lines) ~= "function" then return end
	if not lineProviders[key] then providerOrder[#providerOrder + 1] = key end
	lineProviders[key] = { key = key, order = tonumber(def.order) or 50, option = def.option, live = def.live, lines = def.lines }
	table.sort(providerOrder, function(a, b)
		if lineProviders[a].order ~= lineProviders[b].order then return lineProviders[a].order < lineProviders[b].order end
		return a < b
	end)
end

function M:UnregisterLines(key)
	if not lineProviders[key] then return end
	lineProviders[key] = nil
	for index, name in ipairs(providerOrder) do
		if name == key then table.remove(providerOrder, index) break end
	end
end

local function ProviderLive(provider)
	if type(provider.live) ~= "function" then return true end
	local ok, live = pcall(provider.live)
	return ok and live and true or false
end

-- A provider with this option tick answers now (the tick's row hides otherwise).
function M:LinesLive(option)
	for _, key in ipairs(providerOrder) do
		local provider = lineProviders[key]
		if provider.option == option and ProviderLive(provider) then return true end
	end
	return false
end

local function AddProviderLines(lines, mapID, shift)
	local db = M.db
	for _, key in ipairs(providerOrder) do
		local provider = lineProviders[key]
		if (not provider.option or db[provider.option]) and ProviderLive(provider) then
			local ok, list = pcall(provider.lines, mapID, shift)
			if ok and type(list) == "table" and list[1] then
				Line(lines, nil)
				lines[#lines].divider = true
				for _, row in ipairs(list) do
					if type(row) == "table" and (type(row.left) == "string" or type(row.right) == "string") then
						Line(lines, row.left, row.right, row.lr, row.lg, row.lb, row.rr, row.rg, row.rb)
					end
				end
			elseif not ok and not provider.failed then
				provider.failed = true
				geterrorhandler()(("EldoUI Zone Info lines %s failed: %s"):format(key, tostring(list)))
			end
		end
	end
end

-- One profession line: label, range, color by your best chance.
function M:ProfessionLine(lines, kind, label, reqs, rangeText)
	if #reqs == 0 then return end
	local db = self.db
	local skill = self:PlayerSkill(kind)
	if db.onlyKnown and not skill then return end
	local r, g, b = 1, 1, 1
	if db.colorize and skill then
		local chance
		if kind == "fishing" then
			local req = reqs[1]
			chance = skill >= req and "standard" or (skill >= req - 95 and "difficult" or "impossible")
		else
			chance = M.BestChance(skill, reqs)
		end
		r, g, b = M.DifficultyRGB(chance)
	elseif not skill then
		r, g, b = Secondary()
	end
	local sr, sg, sb = Secondary()
	Line(lines, label, rangeText, sr, sg, sb, r, g, b)
end

function M:BuildLines(mapID, shift)
	local db, lines = self.db, {}
	local zone = Z.zones[mapID]
	local sr, sg, sb = Secondary()
	local low, high = self:Levels(mapID)

	if db.showLevels and low then
		local r, g, b = 1, 1, 1
		if db.colorize then r, g, b = M.LevelRGB(low, high) end
		Line(lines, L["Levels"], RangeText(low, high), sr, sg, sb, r, g, b)
	end
	if db.showFaction then
		local text, r, g, b = self:TerritoryText(self:Territory(mapID))
		if text then Line(lines, text, nil, r, g, b) end
	end

	-- Gathering ranges
	local profession = {}
	if zone and db.showGathering then
		for _, spec in ipairs({ { "herb", "herbs", Z.herbs, L["Herbalism"] }, { "ore", "ore", Z.ore, L["Mining"] } }) do
			local nodes = NodeList(zone[spec[2]], spec[3])
			local reqs, lo, hi = {}, nil, nil
			for _, node in ipairs(nodes) do
				reqs[#reqs + 1] = node.skill
				lo = math.min(lo or node.skill, node.skill)
				hi = math.max(hi or node.skill, node.skill)
			end
			if lo then profession[#profession + 1] = { spec[1], spec[4], reqs, RangeText(lo, hi) } end
		end
	end
	if db.showSkinning and low then
		local lo, hi = M.SkinningReq(low), M.SkinningReq(high)
		local reqs = {}
		for level = low, high do reqs[#reqs + 1] = M.SkinningReq(level) end
		profession[#profession + 1] = { "skinning", L["Skinning"], reqs, RangeText(lo, hi) }
	end
	if db.showFishing and zone and zone.fish then
		profession[#profession + 1] = { "fishing", L["Fishing"], { zone.fish }, tostring(zone.fish) }
	end
	if #profession > 0 then
		local before = #lines
		for _, p in ipairs(profession) do self:ProfessionLine(lines, p[1], p[2], p[3], p[4]) end
		if #lines > before then table.insert(lines, before + 1, { divider = true }) end
	end

	-- Instances
	if db.showInstances then
		local list = self:Instances(mapID)
		if #list > 0 then
			Line(lines, nil)
			lines[#lines].divider = true
			local tagColor = E.QuestTint and E.QuestTint.active and E.QuestTint.Hex and E.QuestTint:Hex()
			if not tagColor then tagColor = Hex(unpack(E.media.accentText)) end
			for _, inst in ipairs(list) do
				local name = inst.name
				if inst.kind == "raid" then name = ("%s (%s)"):format(name, L["Raid"]) end
				if inst.new then name = ("%s %s%s|r"):format(name, tagColor, L["New in Forever"]) end
				local r, g, b = 1, 1, 1
				if db.colorize and inst.min then r, g, b = M.LevelRGB(inst.min, inst.max) end
				Line(lines, name, inst.min and RangeText(inst.min, inst.max) or nil, 1, 1, 1, r, g, b)
			end
		end
	end

	-- Shift: node types
	if db.shiftNodes then
		local nodes, source = self:NodeTypes(mapID)
		if #nodes > 0 then
			if shift then
				Line(lines, nil)
				lines[#lines].divider = true
				Line(lines, source == "finds" and L["Node types you have found here"] or L["Typical node types"], nil, sr, sg, sb)
				local herbSkill, oreSkill = self:PlayerSkill("herb"), self:PlayerSkill("ore")
				for _, node in ipairs(nodes) do
					local req = node.req or M.NodeReq(node.name)
					local skill = node.kind == "herb" and herbSkill or node.kind == "ore" and oreSkill or nil
					local r, g, b = 1, 1, 1
					if db.colorize and skill and req then r, g, b = M.DifficultyRGB(M.SkillChance(skill, req)) end
					local right = req and tostring(req) or (node.count and ("x%d"):format(node.count)) or nil
					Line(lines, node.name, right, r, g, b, sr, sg, sb)
				end
			else
				Line(lines, L["Hold Shift for node types"], nil, sr, sg, sb)
			end
		end
	end

	AddProviderLines(lines, mapID, shift)

	-- No dividers at the edges or twice in a row.
	local clean = {}
	for _, line in ipairs(lines) do
		if line.divider then
			if #clean > 0 and not clean[#clean].divider then clean[#clean + 1] = line end
		else
			clean[#clean + 1] = line
		end
	end
	if #clean > 0 and clean[#clean].divider then clean[#clean] = nil end
	return clean
end

---------------------------------------------------------------------------
-- World map hover
---------------------------------------------------------------------------
local function TipOwner()
	return M.tipOwner
end

function M:HideTip()
	if self.tipShown and GameTooltip:GetOwner() == TipOwner() then GameTooltip:Hide() end
	self.tipShown, self.tipZone, self.tipShift = false, nil, nil
end

function M:ShowTip(mapID, name, shift)
	local owner = TipOwner()
	if not owner then return end
	local lines = self:BuildLines(mapID, shift)
	self.lastLines = lines
	if #lines == 0 then
		self:HideTip()
		return
	end
	GameTooltip:SetOwner(owner, "ANCHOR_CURSOR_RIGHT", 24, 0)
	E.UIKit.TipTitle(GameTooltip, name)
	for _, line in ipairs(lines) do
		if line.divider then
			GameTooltip:AddLine(" ")
		elseif line.right then
			GameTooltip:AddDoubleLine(line.left, line.right, line.lr, line.lg, line.lb, line.rr, line.rg, line.rb)
		else
			GameTooltip:AddLine(line.left, line.lr, line.lg, line.lb, true)
		end
	end
	GameTooltip:Show()
	self.tipShown, self.tipZone, self.tipShift = true, mapID, shift
end

-- The zone under the cursor on the map shown, when it is a child map
-- (a zone on a continent), as the area label itself finds it.
function M:HoveredZone(map)
	if not (map and map.GetMapID and map.GetNormalizedCursorPosition and C_Map and C_Map.GetMapInfoAtPosition) then return nil end
	local mapID = Clean(map:GetMapID())
	local x, y = map:GetNormalizedCursorPosition()
	x, y = Clean(x), Clean(y)
	if not (mapID and x and y) then return nil end
	if x == self.lastX and y == self.lastY and mapID == self.lastMap then return self.lastZone, self.lastName end
	self.lastX, self.lastY, self.lastMap = x, y, mapID
	self.lastZone, self.lastName = nil, nil
	if x < 0 or x > 1 or y < 0 or y > 1 then return nil end
	local info = Try(C_Map.GetMapInfoAtPosition, mapID, x, y)
	if type(info) == "table" and Clean(info.mapID) and info.mapID ~= mapID then
		self.lastZone, self.lastName = info.mapID, Clean(info.name)
	end
	return self.lastZone, self.lastName
end

-- Runs after the area label's EvaluateLabels, every frame the label updates.
function M:OnAreaLabel(label)
	if not (self.active and self.db.tooltip) then
		if self.tipShown then self:HideTip() end
		return
	end
	local types = rawget(_G, "MAP_AREA_LABEL_TYPE")
	local areaName = type(types) == "table" and types.AREA_NAME or 3
	local info = type(label.labelInfoByType) == "table" and label.labelInfoByType[areaName]
	local provider = label.dataProvider
	local map = provider and provider.GetMap and provider:GetMap()
	local zoneID, name
	if info and info.name and map then zoneID, name = self:HoveredZone(map) end
	if not zoneID then
		if self.tipShown then self:HideTip() end
		return
	end
	local shift = IsShiftKeyDown() and true or false
	if self.tipShown and zoneID == self.tipZone and shift == self.tipShift and GameTooltip:GetOwner() == TipOwner() then return end
	self:ShowTip(zoneID, name or "", shift)
end

-- The world map's area label frame (one of its data providers).
function M.FindAreaLabel(map)
	local providers = map and map.dataProviders
	if type(providers) ~= "table" then return nil end
	for provider in pairs(providers) do
		local label = type(provider) == "table" and provider.Label
		if type(label) == "table" and type(label.labelInfoByType) == "table" and type(label.EvaluateLabels) == "function" then
			return label
		end
	end
end

function M:HookWorldMap()
	local map = _G.WorldMapFrame
	if not map or self.hookedLabel then return end
	local label = M.FindAreaLabel(map)
	if not label then
		if not self.labelMissingLogged and E.errors and E.errors.Add then
			self.labelMissingLogged = true
			E.errors:Add("warning", "EldoUI Zone Info: the world map's area label was not found; the zone tooltip is off.")
		end
		return
	end
	self.hookedLabel = label
	local parent = map.ScrollContainer or map
	self.tipOwner = self.tipOwner or CreateFrame("Frame", nil, parent)
	self.tipOwner:SetAllPoints(parent)
	hooksecurefunc(label, "EvaluateLabels", function(frame) M:OnAreaLabel(frame) end)
	map:HookScript("OnHide", function() M:HideTip() end)
end

---------------------------------------------------------------------------
-- Zone toast
---------------------------------------------------------------------------
local LAYOUT_WIDTH = { stacked = 320, line = 380, banner = 480 }

-- The zone notice keeps its centered horizontal axis and follows the Ready
-- Check reservation vertically. Saved points still win; no preset is rewritten.
local function ToastNumber(value, positive)
	return not issecret(value) and type(value) == "number" and value == value
		and math.abs(value) < math.huge and (not positive or value > 0)
end

local readySourceInitialized = false
local readyRegistry, readyOwner, readyReader, readyAccessor, readyMeta, readyIndex
local geometrySupplier, existingGeometry, bindGeometry
local rootRead, toastRead, moverRead
local rootCandidate, toastCandidate
local toastMoverConstructor, toastMoverRegistry
local toastModuleRegistry, toastOwnerMeta, toastOwnerIndex
local function ToastSame(a, b)
	return not issecret(a) and not issecret(b) and rawequal(a, b)
end

local function ToastOwnerCurrent()
	return ToastSame(rawget(E, "modules"), toastModuleRegistry)
		and not issecret(toastModuleRegistry) and type(toastModuleRegistry) == "table"
		and ToastSame(getmetatable(toastModuleRegistry), nil)
		and ToastSame(rawget(toastModuleRegistry, "ZoneInfo"), M)
		and ToastSame(getmetatable(M), toastOwnerMeta)
		and not issecret(toastOwnerMeta) and type(toastOwnerMeta) == "table"
		and ToastSame(rawget(toastOwnerMeta, "__index"), toastOwnerIndex)
		and not issecret(toastOwnerIndex) and type(toastOwnerIndex) == "table"
		and ToastSame(getmetatable(toastOwnerIndex), nil)
end

local TOAST_GEOMETRY_METHODS = { "GetParent", "GetNumPoints", "GetPoint", "GetRect", "GetSize", "GetWidth", "GetHeight",
	"GetEffectiveScale", "IsShown", "IsVisible", "GetLeft", "GetBottom", "GetRight", "GetTop" }

-- Before the first mover seeds native admission, retain only raw constructor
-- identities. No getter or unknown resolver runs and no geometry is admitted.
local function ToastCandidate(object)
	if issecret(object) or (type(object) ~= "table" and type(object) ~= "userdata") then return end
	local candidate = { object = object, paths = {}, getters = {} }
	for _, name in ipairs(TOAST_GEOMETRY_METHODS) do
		local owner, found = object, false
		for _ = 1, 16 do
			local value = type(owner) == "table" and rawget(owner, name) or nil
			local meta = getmetatable(owner)
			if issecret(value) or issecret(meta) then return end
			local index = type(meta) == "table" and rawget(meta, "__index") or nil
			if issecret(index) then return end
			candidate.paths[#candidate.paths + 1] = { owner = owner, meta = meta, index = index, key = name, value = value }
			if type(value) ~= "nil" then
				if type(value) ~= "function" then return end
				candidate.getters[name], found = value, true
				break
			end
			if type(index) ~= "table" then return end
			owner = index
		end
		if not found then return end
	end
	return candidate
end

local function ToastCandidateCurrent(candidate)
	if not candidate then return false end
	for _, row in ipairs(candidate.paths) do
		local meta = getmetatable(row.owner)
		if not ToastSame(meta, row.meta) then return false end
		local index = type(meta) == "table" and rawget(meta, "__index") or nil
		local value = type(row.owner) == "table" and rawget(row.owner, row.key) or nil
		if not ToastSame(index, row.index) or not ToastSame(value, row.value) then return false end
	end
	return true
end

local function BindToastGeometry(object)
	if issecret(object) or not object or type(bindGeometry) ~= "function"
		or not ToastSame(rawget(E, "MoverAuthoritySource"), geometrySupplier) then return end
	local read = bindGeometry(object)
	if issecret(read) or type(read) ~= "table" or rawget(read, "native") ~= true then return end
	local getters = rawget(read, "getters")
	if issecret(getters) or type(getters) ~= "table" then return end
	local retained = { object = object }
	for _, name in ipairs({ "source", "capture" }) do
		local fn = rawget(read, name)
		if issecret(fn) or type(fn) ~= "function" then return end
		retained[name] = fn
	end
	for _, name in ipairs(TOAST_GEOMETRY_METHODS) do
		local fn = rawget(getters, name)
		if issecret(fn) or type(fn) ~= "function" then return end
		retained[name] = fn
	end
	if not retained.source() then return end
	return retained
end

function M:OnInitialize()
	if readySourceInitialized then return end
	readySourceInitialized = true
	toastMoverConstructor = rawget(E, "CreateMover")
	if issecret(toastMoverConstructor) or type(toastMoverConstructor) ~= "function" then return end
	local movers = rawget(E, "movers")
	if issecret(movers) or type(movers) ~= "table" or not ToastSame(getmetatable(movers), nil) then return end
	toastMoverRegistry = movers
	local ownerRegistry, ownerMeta = rawget(E, "modules"), getmetatable(M)
	if issecret(ownerRegistry) or type(ownerRegistry) ~= "table" or not ToastSame(getmetatable(ownerRegistry), nil)
		or not ToastSame(rawget(ownerRegistry, "ZoneInfo"), M) or issecret(ownerMeta) or type(ownerMeta) ~= "table" then return end
	local ownerIndex = rawget(ownerMeta, "__index")
	if issecret(ownerIndex) or type(ownerIndex) ~= "table" or not ToastSame(getmetatable(ownerIndex), nil) then return end
	toastModuleRegistry, toastOwnerMeta, toastOwnerIndex = ownerRegistry, ownerMeta, ownerIndex
	local registry, accessor = rawget(E, "modules"), rawget(E, "GetModule")
	if issecret(registry) or type(registry) ~= "table" or not ToastSame(getmetatable(registry), nil)
		or issecret(accessor) or type(accessor) ~= "function" then return end
	local owner = rawget(registry, "Notifications")
	if issecret(owner) or type(owner) ~= "table" then return end
	local reader = rawget(owner, "ReadyAreaBounds")
	if issecret(reader) or type(reader) ~= "function" then return end
	local meta = getmetatable(owner)
	if issecret(meta) or type(meta) ~= "table" then return end
	local index = rawget(meta, "__index")
	if issecret(index) or type(index) ~= "table" or not ToastSame(getmetatable(index), nil) then return end
	local supplier = rawget(E, "MoverAuthoritySource")
	if issecret(supplier) or type(supplier) ~= "function" then return end
	local _, _, _, _, existing, binder = supplier()
	if issecret(existing) or type(existing) ~= "function" or issecret(binder) or type(binder) ~= "function" then return end
	geometrySupplier, existingGeometry, bindGeometry = supplier, existing, binder
	-- Service custody is independent of whether a first mover has seeded the
	-- intrinsic class yet. Only its actual constructor can finish admission.
	readyRegistry, readyOwner, readyReader, readyAccessor, readyMeta, readyIndex = registry, owner, reader, accessor, meta, index
	rootCandidate = ToastCandidate(UIParent)
	if rootCandidate then rootRead = BindToastGeometry(UIParent) end
end

local function ReadyReaderCurrent()
	return readySourceInitialized and ToastOwnerCurrent() and type(readyReader) == "function"
		and ToastSame(rawget(E, "MoverAuthoritySource"), geometrySupplier)
		and ToastSame(rawget(E, "modules"), readyRegistry) and ToastSame(getmetatable(readyRegistry), nil)
		and ToastSame(rawget(E, "GetModule"), readyAccessor)
		and ToastSame(rawget(readyRegistry, "Notifications"), readyOwner)
		and ToastSame(rawget(readyOwner, "ReadyAreaBounds"), readyReader)
		and ToastSame(getmetatable(readyOwner), readyMeta)
		and ToastSame(rawget(readyMeta, "__index"), readyIndex) and ToastSame(getmetatable(readyIndex), nil)
end

local function CompleteToastGeometry(candidate)
	if not ReadyReaderCurrent() or not ToastCandidateCurrent(candidate) then return end
	local read = BindToastGeometry(candidate.object)
	if not read or not ReadyReaderCurrent() or not ToastCandidateCurrent(candidate) then return end
	for _, name in ipairs(TOAST_GEOMETRY_METHODS) do
		if not ToastSame(read[name], candidate.getters[name]) then return end
	end
	return read
end

function M:DefaultToastPoint()
	if not ToastSame(self, M) or not ReadyReaderCurrent() then return nil end
	if issecret(rawget(self, "active")) or rawget(self, "active") ~= true
		or issecret(rawget(self, "toastFrame")) or not rawget(self, "toastFrame") then return nil end
	-- Retain only this call's context and already-owned geometry seals. These
	-- capabilities inspect existing custody; they install no read-time hooks.
	local context = {}
	local function Keep(owner, key)
		if issecret(owner) or type(owner) ~= "table" then return false end
		local value = rawget(owner, key)
		if issecret(value) then return false end
		context[#context + 1] = { owner, key, value }
		return true, value
	end
	local _, db = Keep(E, "db")
	if issecret(db) or type(db) ~= "table" then return nil end
	for _, field in ipairs({ "profileName", "modules", "movers", "GetMoverAnchor", "SurfaceMeasure" }) do
		if not Keep(E, field) then return nil end
	end
	for _, field in ipairs({ "db", "active", "toastFrame", "toastMover" }) do
		if not Keep(self, field) then return nil end
	end
	local _, positions = Keep(db, "movers")
	local _, general = Keep(db, "general")
	if not Keep(general, "layout") then return nil end
	for _, name in ipairs({ MOVER, "EldoUI_ReadyCheck" }) do
		local valid, position = Keep(positions, name)
		if not valid then return nil end
		if type(position) == "table" then
			if getmetatable(position) ~= nil then return nil end
			for index = 1, 5 do if not Keep(position, index) then return nil end end
		elseif position ~= nil then return nil end
	end
	local seals = {}
	local function ContextSourcesCurrent()
		if not ReadyReaderCurrent() then return false end
		for _, row in ipairs(context) do if not ToastSame(rawget(row[1], row[2]), row[3]) then return false end end
		for _, row in ipairs(seals) do if not row[2]() or not row[1]() then return false end end
		return true
	end
	local function NativeValues(read)
		if not read or not ContextSourcesCurrent() or not read.source() then return end
		local parent = read.GetParent(read.object)
		if issecret(parent) or not ContextSourcesCurrent() or not read.source() then return end
		local l, b, w, h = read.GetRect(read.object)
		if not ContextSourcesCurrent() or not read.source() then return end
		local scale = read.GetEffectiveScale(read.object)
		if not ContextSourcesCurrent() or not read.source()
			or not (ToastNumber(l) and ToastNumber(b) and ToastNumber(w, true)
			and ToastNumber(h, true) and ToastNumber(scale, true)) then return end
		return { parent, l, b, w, h, scale }
	end
	local function RetainGeometry(object)
		if issecret(object) or not object then return false end
		local read = ToastSame(object, UIParent) and rootRead
			or (toastRead and ToastSame(object, toastRead.object) and toastRead)
			or (moverRead and ToastSame(object, moverRead.object) and moverRead)
		if not read then return false end
		local capture, source = existingGeometry(object)
		if type(capture) ~= "function" or type(source) ~= "function" or not source() then return false end
		local values = NativeValues(read)
		if not values then return false end
		seals[#seals + 1] = { capture(true), source, read, values }
		return true
	end
	local movers = rawget(E, "movers")
	if issecret(movers) or type(movers) ~= "table" or getmetatable(movers) ~= nil then return nil end
	local readyAtEntry = rawget(movers, "EldoUI_ReadyCheck")
	if issecret(readyAtEntry) then return nil end
	if not Keep(movers, "EldoUI_ReadyCheck") or not Keep(self.toastFrame, "panel") then return nil end
	if not RetainGeometry(UIParent) or not RetainGeometry(self.toastFrame)
		or not RetainGeometry(self.toastMover or self.toastFrame) then return nil end
	local function ContextCurrent()
		if not ContextSourcesCurrent() then return false end
		for _, row in ipairs(seals) do
			if not row[2]() or not row[1]() then return false end
			local values = NativeValues(row[3])
			if not values then return false end
			for index = 1, 6 do if not ToastSame(values[index], row[4][index]) then return false end end
		end
		return true
	end
	local key, reason = E:EffectiveLayout()
	if issecret(key) or issecret(reason) then return nil end
	local layout = type(key) == "string" and E.layouts[key]
	if reason == "missing" or issecret(layout) or not E:LayoutUsesFamilyPlacement(layout) then return nil end
	local current = false
	for _, family in ipairs(E.layoutFamilies) do if E:FamilyLayoutKey(family.key) == key then current = true break end end
	if not current then return nil end
	local saved = E:SavedMoverPosition(MOVER, true)
	if issecret(saved) or saved ~= nil then return nil end
	local gamepad = E.GetGamepadMoverPoint and E:GetGamepadMoverPoint(MOVER)
	if issecret(gamepad) or gamepad ~= nil then return nil end
	local notifications = readyOwner
	local util = rawget(notifications, "util")
	if issecret(util) or type(util) ~= "table" or getmetatable(util) ~= nil then return nil end
	local holders = rawget(util, "HOLDERS")
	if issecret(holders) or type(holders) ~= "table" or getmetatable(holders) ~= nil then return nil end
	local spec = rawget(holders, "ReadyCheck")
	if issecret(spec) or type(spec) ~= "table" or getmetatable(spec) ~= nil
		or not ToastNumber(rawget(spec, "width"), true) or not ToastNumber(rawget(spec, "height"), true) then return nil end
	if not Keep(notifications, "util") or not Keep(util, "HOLDERS") or not Keep(holders, "ReadyCheck")
		or not Keep(spec, "width") or not Keep(spec, "height") then return nil end
	local point = E:SavedMoverPosition("EldoUI_ReadyCheck", true)
	if issecret(point) then return nil end
	if type(point) == "nil" then point = E:GetMoverDefaultPoint("EldoUI_ReadyCheck") end
	if issecret(point) or type(point) ~= "table" or getmetatable(point) ~= nil or issecret(point[2]) or point[2] ~= "UIParent" then return nil end
	if issecret(point[1]) or issecret(point[3]) or type(point[1]) ~= "string" or type(point[3]) ~= "string"
		or not ToastNumber(point[4]) or not ToastNumber(point[5]) then return nil end
	local function Root(relativePoint)
		local anchor = E.GetMoverAnchor and E:GetMoverAnchor(relativePoint) or UIParent
		if issecret(anchor) or not anchor or not RetainGeometry(anchor) then return end
		local values = NativeValues(rootRead)
		if not values or not ToastSame(anchor, rootRead.object) then return end
		local left, bottom, width, height, scale = unpack(values, 2, 6)
		if not (ToastNumber(scale, true) and ToastNumber(left) and ToastNumber(bottom)
			and ToastNumber(width, true) and ToastNumber(height, true)) then return end
		local rect = { left * scale, bottom * scale, (left + width) * scale, (bottom + height) * scale }
		for _, value in ipairs(rect) do if not ToastNumber(value) then return end end
		return rect, scale
	end
	local root, parentScale = Root(point[3])
	local targetRoot = Root("BOTTOMLEFT")
	if not root or not targetRoot then return nil end
	local width, height, readyScale = spec.width, spec.height, parentScale
	local moverValues = NativeValues(self.toastMover and moverRead or toastRead)
	if not moverValues then return nil end
	local scale = moverValues[6]
	if not (ToastNumber(width, true) and ToastNumber(height, true) and ToastNumber(readyScale, true)
		and ToastNumber(scale, true)) then return nil end
	local resolve = E:LayoutRectangles(function(name)
		if name == "ready" then return point, width * readyScale, height * readyScale, nil, root, readyScale end
	end)
	local rect = resolve("ready")
	if not rect then return nil end
	local readyBottom = rect[2]
	local panel = self.toastFrame.panel
	if issecret(panel) then return nil end
	local paint = E:SurfaceMeasure(panel or self.toastFrame)
	if issecret(paint) or type(paint) ~= "table" then return nil end
	local edges = rawget(paint, "paint")
	if issecret(edges) or type(edges) ~= "table" or getmetatable(edges) ~= nil then return nil end
	for index = 1, 4 do if not ToastNumber(edges[index]) or edges[index] < 0 then return nil end end
	edges = { edges[1], edges[2], edges[3], edges[4] }
	local frameValues = NativeValues(toastRead)
	if not frameValues then return nil end
	local zoneWidth, zoneHeight, frameScale = unpack(frameValues, 4, 6)
	if not (ToastNumber(frameScale, true) and ToastNumber(zoneWidth, true) and ToastNumber(zoneHeight, true)) then return nil end
	if not ContextCurrent() then return nil end
	local ok, occupied = pcall(readyReader, readyOwner)
	if not ok or not ContextCurrent() or issecret(occupied) or type(occupied) ~= "table" then return nil end
	local holder = rawget(occupied, "holder")
	if issecret(holder) then return nil end
	if holder ~= nil then
		if type(holder) ~= "table" or getmetatable(holder) ~= nil then return nil end
		for index = 1, 4 do if not ToastNumber(rawget(holder, index)) then return nil end end
		readyBottom = math.min(readyBottom, rawget(holder, 2))
	end
	local kind = rawget(occupied, "kind")
	if issecret(kind) then return nil end
	if kind == "shown" then
		local bounds = rawget(occupied, "bounds")
		if issecret(bounds) or type(bounds) ~= "table" then return nil end
		for index = 1, 4 do if not ToastNumber(rawget(bounds, index)) then return nil end end
		readyBottom = math.min(readyBottom, bounds[2])
	elseif kind ~= "none" then return nil end
	-- Use the declared holder reservation, without promoting it to native paint.
	-- Keep the original screen-centered Zone axis and add its painted outset
	-- to the ordinary four-unit vertical gap. Ready keeps its own saved axis.
	local center = (targetRoot[1] + targetRoot[3]) / 2
	local top = readyBottom - (4 * scale) - edges[3] * frameScale
	local left, right = center - (zoneWidth / 2 + edges[1]) * frameScale, center + (zoneWidth / 2 + edges[2]) * frameScale
	local bottom = top - (zoneHeight + edges[4]) * frameScale
	if not (ToastNumber(center) and ToastNumber(top) and ToastNumber(left) and ToastNumber(right) and ToastNumber(bottom)) then return nil end
	if left < targetRoot[1] or bottom < targetRoot[2] or right > targetRoot[3] or top + edges[3] * frameScale > targetRoot[4] then return nil end
	local x = (center - targetRoot[1]) / scale
	local y = (top - targetRoot[2]) / scale
	if not ToastNumber(x) or not ToastNumber(y) then return nil end
	return { "TOP", "UIParent", "BOTTOMLEFT", x, y }
end

E:RegisterMoverPointHook(MOVER, function() return M:DefaultToastPoint() end)
E:RegisterMoverCallback("EldoUI_ReadyCheck", function()
	if not issecret(M.active) and M.active == true and not issecret(M.toastMover) and M.toastMover then E:ApplyMover(MOVER) end
end)


function M:CreateToast()
	if not ToastSame(self, M) or not ToastOwnerCurrent() then return end
	if self.toastFrame then return self.toastFrame end
	local frame = CreateFrame("Frame", "EldoUI_ZoneToastFrame", UIParent)
	toastCandidate = ToastCandidate(frame)
	frame:SetFrameStrata("MEDIUM")
	frame:SetSize(320, 56)
	frame:Hide()
	frame.panel = CreateFrame("Frame", nil, frame)
	frame.panel:SetAllPoints()
	frame.panel:SetFrameLevel(frame:GetFrameLevel())
	E:SetPanelTemplate(frame.panel)
	frame.edge = CreateFrame("Frame", nil, frame)
	frame.edge:SetAllPoints()
	frame.edge:SetFrameLevel(frame:GetFrameLevel())
	E:SetTemplate(frame.edge, true)
	E:SetStyleEdge(frame.edge, true)
	frame.title = E:CreateText(frame, E.tokens.size.windowTitle, "CENTER") -- sized by ApplyToastLook
	frame.sub = E:CreateText(frame, E.tokens.size.label, "CENTER")
	frame.line = frame:CreateTexture(nil, "ARTWORK")
	frame.line:SetHeight(E.pixel * 2)
	-- Gone (faded out or hidden): the notice queue may show the next one.
	frame:HookScript("OnHide", function(toast) E:NoticeClosed(toast) end)
	self.toastFrame = frame
	if not ToastSame(rawget(E, "CreateMover"), toastMoverConstructor) then return frame end
	local mover = toastMoverConstructor(E, frame, MOVER, L["Zone Toast"], { "TOP", "UIParent", "TOP", 0, -200 }, { enabledPath = { "toast" }, sample = { kind = "toast" } })
	local registry = rawget(E, "movers")
	if not ToastOwnerCurrent() or issecret(mover) or type(mover) ~= "table" or not ToastSame(registry, toastMoverRegistry)
		or not ToastSame(getmetatable(registry), nil) or not ToastSame(rawget(registry, MOVER), mover)
		or not ToastSame(rawget(mover, "frame"), frame) then return frame end
	-- Bind the toast's reads only right after the mover is made. Reads
	-- already bound are never bound again, and a read still waiting never
	-- takes a handle that changed.
	if ToastSame(rawget(E, "CreateMover"), toastMoverConstructor) then
		if not rootRead then rootRead = CompleteToastGeometry(rootCandidate) end
		if not toastRead then toastRead = CompleteToastGeometry(toastCandidate) end
		moverRead = ReadyReaderCurrent() and BindToastGeometry(mover) or nil
	end
	self.toastMover = mover
	return frame
end

-- Size, look and text placement from the settings and applied font heights,
-- so the mover reserves the text rows at the current accessibility scale.
function M:ApplyToastLook()
	local frame = self.toastFrame
	if not frame then return end
	local db = self.db
	local size = math.max(10, math.min(32, tonumber(db.toastSize) or 18))
	local layout = LAYOUT_WIDTH[db.toastLayout] and db.toastLayout or "stacked"
	local subSize = math.max(10, math.floor(size * 0.65 + 0.5))
	E:SetHeaderFont(frame.title, layout == "banner" and math.floor(size * 1.3 + 0.5) or size)
	E:SetFont(frame.sub, subSize)
	frame.title:ClearAllPoints()
	frame.sub:ClearAllPoints()
	frame.line:ClearAllPoints()
	frame.line:Hide()
	local width = math.floor(LAYOUT_WIDTH[layout] * size / 18 + 0.5)
	local height
	if layout == "line" then
		height = frame.title:GetLineHeight() + 14
		frame.title:SetPoint("CENTER")
		frame.title:SetWidth(width - 16)
		frame.sub:Hide()
	else
		height = frame.title:GetLineHeight() + frame.sub:GetLineHeight() + (layout == "banner" and 30 or 22)
		frame.title:SetPoint("TOP", 0, -8)
		frame.title:SetWidth(width - 16)
		frame.sub:SetPoint("BOTTOM", 0, 8)
		frame.sub:SetWidth(width - 16)
		frame.sub:Show()
		if layout == "banner" then
			local r, g, b = unpack(E.media.accentColor)
			frame.line:SetColorTexture(r, g, b, 0.9)
			frame.line:SetPoint("TOP", frame.title, "BOTTOM", 0, -4)
			frame.line:SetWidth(width * 0.6)
			frame.line:Show()
		end
	end
	frame:SetSize(width, height)
	local look = db.toastLook
	frame.panel:SetShown(look == "panel" or look == "transparent")
	if look == "panel" or look == "transparent" then E:SetPanelTemplate(frame.panel, look == "transparent") end
	frame.edge:SetShown(look == "edge")
	self.toastLayout = layout
	if self.toastMover then E:ApplyMover(MOVER) end
end

-- The zone you stand in (a micro map such as a cave counts as its zone).
function M:CurrentZone()
	if not (C_Map and C_Map.GetBestMapForUnit) then return nil end
	local mapID = Clean(Try(C_Map.GetBestMapForUnit, "player"))
	local name
	for _ = 1, 4 do
		if not mapID then break end
		local info = Try(C_Map.GetMapInfo, mapID)
		if type(info) ~= "table" then break end
		name = Clean(info.name)
		local mapType, parent = Clean(info.mapType), Clean(info.parentMapID)
		-- Only a micro map (a building, a cave) climbs to its zone.
		if mapType ~= 5 or not parent or parent == 0 then break end
		mapID = parent
	end
	if (not name or name == "") and GetRealZoneText then name = Clean(GetRealZoneText()) end
	return mapID, name
end

-- Title and subline of the toast for a zone.
function M:ToastText(mapID, name)
	local db = self.db
	local parts = {}
	local low, high = self:Levels(mapID)
	if db.toastLevels and low then
		parts[#parts + 1] = Hex(M.LevelRGB(low, high)) .. RangeText(low, high) .. "|r"
	end
	local territory = self:Territory(mapID)
	local text, r, g, b = self:TerritoryText(territory)
	if db.toastFaction and text then parts[#parts + 1] = Hex(r, g, b) .. text .. "|r" end
	local title = name or ""
	if db.toastPvPColor and text then title = Hex(r, g, b) .. title .. "|r" end
	return title, table.concat(parts, "  ")
end

-- The toast is a holder of EldoUI's one notice queue (Core/Alerts.lua),
-- under its own "Zone Toast" mover: the queue keeps its time on screen.
-- One zone toast at a time; a new zone while one shows takes its place.
local TOAST_KEY = "zoneinfo:zone"

function M:DrawToast(data)
	local frame = self:CreateToast()
	self:ApplyToastLook()
	local title, sub = self:ToastText(data.mapID, data.name)
	if self.toastLayout == "line" then
		frame.title:SetText(sub ~= "" and ("%s  %s"):format(title, sub) or title)
	else
		frame.title:SetText(title)
		frame.sub:SetText(sub)
	end
	self.toastShownFor = data.mapID
	if self.db.toastAnim == "pop" then
		E:PopIn(frame, 0.8)
	elseif self.db.toastAnim == "slide" then
		E:SlideIn(frame, "DOWN")
	else
		frame:SetAlpha(1)
		frame:Show()
	end
	return frame
end

E:RegisterNoticeHolder("zone", {
	usable = function() return M.active and true or false end,
	duration = function() return math.max(1, tonumber(M.db.toastDuration) or 4) end,
	wait = 5,
	show = function(data) return M:DrawToast(data) end,
	refresh = function(_, data) M:DrawToast(data) end,
	hide = function(_, _, now) M:FadeToast(now) end,
})

function M:ShowToast(mapID, name)
	if not (self.active and self.db.toast) then return end
	E:PushNotice("zone", { key = TOAST_KEY, mapID = mapID, name = name })
end

function M:FadeToast(now)
	local frame = self.toastFrame
	if not frame or not frame:IsShown() then
		if frame then E:NoticeClosed(frame) end
		return
	end
	if now or self.db.toastAnim == "none" then frame:Hide() else E:SlideOut(frame, "UP") end
end

function M:HideToast(now)
	if self.toastFrame and E:CloseNotice(self.toastFrame, now) then return end
	self:FadeToast(now)
end

function M:PreviewToast()
	local mapID, name = self:CurrentZone()
	local was = self.db.toast
	self.db.toast = true
	self:ShowToast(mapID, name or L["Zone Info"])
	self.db.toast = was
end

function M:OnZoneChanged()
	if not self.db.toast then return end
	local mapID, name = self:CurrentZone()
	if not mapID or mapID == self.lastToastZone then return end
	self.lastToastZone = mapID
	self:ShowToast(mapID, name)
end

function M:ApplyToast()
	if self.db.toast then
		self:CreateToast()
		self:ApplyToastLook()
	end
	if self.toastMover then self.toastMover:SetShown(self.db.toast and true or false) end
	if not self.db.toast then self:HideToast(true) end
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
function M:OnEnable()
	E:OnBlizzardAddOn("Blizzard_WorldMap", function() M:HookWorldMap() end)
	self.lastToastZone = self:CurrentZone() -- no toast for the zone you log in to
	self:RegisterEvent("ZONE_CHANGED_NEW_AREA", function() M:OnZoneChanged() end)
	self:ApplyToast()
end

function M:OnDisable()
	self:UnregisterEvent("ZONE_CHANGED_NEW_AREA")
	self:HideTip()
	self:HideToast(true)
	if self.toastMover then self.toastMover:Hide() end
end

function M:OnProfileChanged()
	self:HideTip()
	if self.active then self:ApplyToast() end
end

---------------------------------------------------------------------------
-- Options and styles
---------------------------------------------------------------------------
M.options = {
	{ type = "description", label = "Hover a zone on a continent map for its level range, gathering ranges, dungeons and territory. Hold Shift for its node types." },
	{ type = "header", label = "World map tooltip" },
	{ type = "toggle", key = "tooltip", label = "Zone tooltip on the world map", desc = "Show the tooltip when the mouse is over a zone on a continent map." },
	{ type = "toggle", key = "showLevels", label = "Level range", desc = "The zone's level range: red is too high for you, yellow is right, green and gray are below you.", dependsOn = "tooltip" },
	{ type = "toggle", key = "showFaction", label = "Territory", desc = "Whose territory the zone is: yours (green), the other faction's (red) or contested (orange).", dependsOn = "tooltip" },
	{ type = "toggle", key = "showGathering", label = "Herbalism and mining", desc = "The skill range of the herbs and ore veins in the zone.", dependsOn = "tooltip" },
	{ type = "toggle", key = "showSkinning", label = "Skinning", desc = "The skinning skill the zone's beasts ask for, from its level range.", dependsOn = "tooltip" },
	{ type = "toggle", key = "showFishing", label = "Fishing", desc = "The fishing skill from which no fish get away in the zone.", dependsOn = "tooltip" },
	{ type = "toggle", key = "showInstances", label = "Dungeons and raids", desc = "Dungeons and raids with an entrance in the zone; ones the original game did not have are marked New in Forever.", dependsOn = "tooltip" },
	{ type = "toggle", key = "colorize", label = "Color by your level and skill", desc = "Color the ranges by your level and by your chance of a skill-up: orange always, yellow often, green sometimes, gray never, red not yet. Off shows them in white.", dependsOn = "tooltip" },
	{ type = "toggle", key = "onlyKnown", label = "Only professions you have", desc = "Leave out the herbalism, mining, skinning and fishing lines of professions you have not learned.", dependsOn = "tooltip" },
	{ type = "toggle", key = "shiftNodes", label = "Shift lists node types", desc = "Hold Shift over a zone to list its herbs and ore veins: your own finds when the Gathering module knows the zone, else the nodes that typically grow there.", dependsOn = "tooltip" },
	{ type = "toggle", key = "showJournal", label = "Your journal", desc = "From My Adventure: when you first came to the zone and at what level, the time you spent there, and your runs in its dungeons.", dependsOn = "tooltip",
		hidden = function() return not M:LinesLive("showJournal") end },
	{ type = "header", label = "Zone toast" },
	{ type = "toggle", key = "toast", label = "Enable", desc = "Show the zone's name, level range and territory for a few seconds when you enter another zone. Place it with move mode (Zone Toast)." },
	{ type = "range", unit = "s", key = "toastDuration", label = "Show for", min = 2, max = 10, step = 1, desc = "Seconds the toast stays before it fades.", dependsOn = "toast" },
	{ type = "select", key = "toastLayout", label = "Layout", values = { stacked = "Name above details", line = "One line", banner = "Banner" }, desc = "How the toast arranges the zone name and its details.", dependsOn = "toast" },
	{ type = "select", key = "toastLook", label = "Background", values = { panel = "Panel", transparent = "See-through panel", edge = "Thin frame line", none = "None (text only)" }, desc = "The toast's background; Panel follows your art style.", dependsOn = "toast" },
	{ type = "range", key = "toastSize", label = "Text size", min = 12, max = 28, step = 1, desc = "Size of the zone name; the details are a bit smaller.", dependsOn = "toast" },
	{ type = "select", key = "toastAnim", label = "Animation", values = { slide = "Slide in", pop = "Pop in", none = "None" }, desc = "How the toast appears. Animations follow the General page's animation setting.", dependsOn = "toast" },
	{ type = "toggle", key = "toastLevels", label = "Level range", desc = "Show the zone's level range on the toast.", dependsOn = "toast" },
	{ type = "toggle", key = "toastFaction", label = "Territory", desc = "Show whose territory the zone is on the toast.", dependsOn = "toast" },
	{ type = "toggle", key = "toastPvPColor", label = "Name in territory color", desc = "Color the zone name like the game's zone text: green for yours, red for the other faction's, orange for contested.", dependsOn = "toast" },
	{ type = "execute", label = "Preview the toast", desc = "Show the toast once for the zone you are in, with the settings above.", func = function() M:PreviewToast() end },
}

E:RegisterStyles("ZoneInfo", {
	{ key = "Standard", title = "Standard", desc = "Every tooltip line in color; the toast as a panel with the name above its details.",
		settings = { showLevels = true, showFaction = true, showGathering = true, showSkinning = true, showFishing = true, showInstances = true,
			colorize = true, onlyKnown = false, showJournal = true, toastLayout = "stacked", toastLook = "panel", toastSize = 18, toastAnim = "slide", toastLevels = true, toastFaction = true } },
	{ key = "Minimal", title = "Minimal", desc = "Levels and territory only; the toast as one line of text without a background.",
		settings = { showLevels = true, showFaction = true, showGathering = false, showSkinning = false, showFishing = false, showInstances = false, showJournal = false,
			toastLayout = "line", toastLook = "none", toastSize = 14, toastAnim = "none", toastLevels = true, toastFaction = false } },
	{ key = "Gatherer", title = "Gatherer", desc = "Only the professions you have, with the node list on Shift; a compact toast.",
		settings = { showLevels = true, showFaction = false, showGathering = true, showSkinning = true, showFishing = true, showInstances = false, showJournal = false,
			onlyKnown = true, shiftNodes = true, colorize = true, toastLayout = "line", toastLook = "panel", toastSize = 14 } },
	{ key = "Banner", title = "Banner", desc = "A wide see-through banner with a large zone name and an accent line.",
		settings = { toastLayout = "banner", toastLook = "transparent", toastSize = 22, toastAnim = "pop", toastLevels = true, toastFaction = true, toastPvPColor = true } },
	{ key = "Forever", title = "WoW Forever", desc = "The toast in a thin frame line that matches the WoW Forever art style.",
		settings = { toastLayout = "stacked", toastLook = "edge", toastSize = 18, toastAnim = "slide", toastPvPColor = true } },
	{ key = "Compact", title = "Compact", desc = "A small one-line panel toast and a short tooltip without dungeons.",
		settings = { showInstances = false, toastLayout = "line", toastLook = "panel", toastSize = 12, toastAnim = "slide", toastFaction = false } },
})
