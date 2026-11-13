-- EldoUI Dungeon Routes: hand-placed packs.
--
-- The packs of the Classic dungeons come from EldoUI_LootData (classic-db).
-- A dungeon that data lacks, such as one WoW: Forever adds, gets its packs
-- here, placed by hand from what players saw in game, never copied from
-- another addon or a website (the rule of tools/lootdata/overrides/
-- forever.json). A plugin can add its own the same way.
--
--   EldoUI.DungeonRoutes:RegisterPacks(key, {
--       name = "Dungeon name", min = 30, max = 35,   -- levels
--       map = instanceMapID,                          -- GetInstanceInfo()'s 8th value
--       source = "seen in game, 1.60.1",              -- where the facts come from
--       packs = { "id|x,y,z|npc*count,...|flags|x,y;...", ... }, -- LootData's pack format
--       shipped = "1,2,3",                            -- optional: a suggested route (pack indices)
--       mobs = { [npc] = "name|minLevel|maxLevel|rank" },  -- creatures the data lacks
--       bosses = { "First boss", "Second boss" },      -- names in kill order (flags b1, b2, ...)
--       floors = { { name, bounds = { left, right, top, bottom } } }, -- optional map edges
--   })
--   EldoUI.DungeonRoutes:UnregisterPacks(key)
--
-- x, y, z are world yards. With `floors` (or a map art folder the client
-- has, `art = { folder }`) the dungeon gets a map in E.DungeonMaps; without
-- one the window shows the schematic view built from the packs.
--
-- Data gap (2026-10-13): no WoW: Forever-only dungeon has confirmed packs
-- yet. tools/lootdata/overrides/forever.json lists no new dungeons, so
-- FOREVER_PACKS below is empty on purpose. Packs are added once someone
-- records them in game (a journal-data issue with what was seen).
local _, E = ...
local M = E.DungeonRoutes

local FOREVER_PACKS = {
	-- [key] = { name, min, max, map, source, packs = { ... }, ... },
}

local Secret = E.Secret

-- Checks a pack record: "id|x,y,z|members|flags|path".
local function ValidRecord(record)
	return type(record) == "string" and not Secret(record) and #record < 400
		and record:match("^%d+|%-?%d+,%-?%d+,%-?%d+|[%d%*,]+") ~= nil
end

function M:RegisterPacks(key, def)
	if type(key) ~= "string" or not key:match("^[%w_]+$") or #key > 32 or type(def) ~= "table" then return false, "key" end
	if type(def.packs) ~= "table" then return false, "packs" end
	local packs = {}
	for _, record in ipairs(def.packs) do
		if ValidRecord(record) then packs[#packs + 1] = record end
	end
	if #packs == 0 then return false, "packs" end
	local entry = {
		name = type(def.name) == "string" and def.name or key,
		min = tonumber(def.min), max = tonumber(def.max), map = tonumber(def.map),
		source = type(def.source) == "string" and def.source or nil,
		packs = packs,
		shipped = type(def.shipped) == "string" and def.shipped:match("^[%d,]+$") and def.shipped or nil,
		mobs = type(def.mobs) == "table" and def.mobs or nil,
		bosses = type(def.bosses) == "table" and def.bosses or nil,
	}
	self.extraPacks[key] = entry
	-- A map for it (unless the Classic list already has one).
	local DM = E.DungeonMaps
	if DM and not DM:Get(key) and (def.floors or def.art or entry.map) then
		DM:Register(key, { name = entry.name, map = entry.map, floors = def.floors, art = def.art })
	end
	self:ForgetPacks(key)
	self:Changed("data")
	return true
end

function M:UnregisterPacks(key)
	if not self.extraPacks[key] then return false end
	self.extraPacks[key] = nil
	self:ForgetPacks(key)
	self:Changed("data")
	return true
end

-- Where a dungeon's packs come from: "classic", "hand" or nil.
function M:PackSource(key)
	local data = self:Data(true)
	if data and type(data.routePacks) == "table" and type(data.routePacks[key]) == "table" then return "classic" end
	if self.extraPacks[key] then return "hand", self.extraPacks[key].source end
end

for key, def in pairs(FOREVER_PACKS) do M:RegisterPacks(key, def) end
