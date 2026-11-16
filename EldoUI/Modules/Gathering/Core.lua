-- EldoUI Gathering: remembers where you gathered herbs, ore, treasure and
-- fishing pools, and shows those nodes as pins on the world map and the
-- minimap.
--
-- A node is recorded when one of your own gathering casts succeeds (Herb
-- Gathering, Mining, Opening, Fishing): the cast's target name is the node,
-- your map position is where it stood. Finds close together merge into one
-- node with a count. Nodes are kept account-wide, per map. Opening also
-- opens quest objects, so a treasure is only recorded when a loot window
-- follows (see "Treasure" below); fishing has no target, see "Fishing".
--
-- Files: Core.lua (kinds, store, recording, options), Skill.lua (required
-- skill and the skill filter), Share.lua (export, import and sending through
-- Core/Share.lua), Map.lua (world map and minimap pins).
--
-- Read-only API for other modules (Zone Info reads it):
--   E.Gathering:NodeTypesInZone(uiMapID[, shownOnly])
--       -> sorted list of { name, kind, label, nodes, finds }, one entry per
--          node name on that map (kind order herb, ore, treasure, fishing,
--          then name). nodes = how many separate spots, finds = how many
--          gathers in all. shownOnly = only what the pin filters show.
--          An empty list when nothing is known; never creates data.
--   E.Gathering:Gathered(charKey) -> { [node name] = gathers } of one of
--          your characters (since this was added; older finds count for
--          all your characters).
--
-- My Adventure reads this store as the journal source "gathering":
-- a new node you found becomes a "gather" row (one per day, map and node
-- name), and the gathers per character feed the journal's facts. A node
-- keeps who found it first (w = charKey) and when (f).
--
-- Only your own finds (and strings you chose to import) are shown; nothing is
-- tracked, switched or shared for you.
local _, E = ...
local L = E.L
local WP = E.Waypoints -- shared map helpers (they work with Waypoints off too)

local sqrt, cos, sin, floor = math.sqrt, math.cos, math.sin, math.floor

local M = E:NewModule("Gathering", {
	title = "Gathering",
	category = "Quality of Life",
	desc = "Remembers where you gathered herbs, ore, treasure and fishing pools and shows the nodes on the world map and minimap.",
	conflicts = { "GatherMate2", "GatherLite" },
	frames = {},
	movers = {},
	blizzard = {},
	savedKeys = { "profile.modules.Gathering", "global.GatherNodes", "global.gatherNodeNames" },
	optionsPage = "module:Gathering",
	presets = { "Angler", "Dots", "Herbalist", "HighContrast", "Miner", "MinimapOnly", "Standard" },
	reload = false,
	defaults = {
		record = true,
		herb = true,
		ore = true,
		treasure = true,
		fish = true,
		worldPins = true,
		minimapPins = true,
		minimapEdge = false,  -- keep far nodes on the minimap's edge
		pinSize = 14,
		pinAlpha = 0.9,
		iconStyle = "icons",  -- icons | dots | contrast
		mergeYards = 20,
		recordNote = false,   -- a chat line for every new node
		skillFilter = "all",  -- all | canGather | skillUp (Skill.lua)
		hiddenNames = {},     -- node name -> true: hidden from the pins
		shareSend = false,    -- sending to other players is opt-in
		shareTo = "group",    -- group | guild | player
		sharePlayer = "",
	},
})
E.Gathering = M

local Clean = E.Plain

local function Try(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a, b, c = pcall(fn, ...)
	if ok then return a, b, c end
end

---------------------------------------------------------------------------
-- Kinds of nodes and the casts that gather them
---------------------------------------------------------------------------
-- The first spell of each kind is the main one: its name and icon come from
-- the game; the English name is the fallback. skillLine: the profession the
-- skill filter reads (Skill.lua).
M.KINDS = {
	{ key = "herb", label = "Herbs", spells = { 2366, 2368, 3570, 11993 }, name = "Herb Gathering", icon = 136065, color = { 0.35, 0.9, 0.35 }, skillLine = 182 },
	{ key = "ore", label = "Ore", spells = { 2575, 2576, 3564, 10248 }, name = "Mining", icon = 136248, color = { 0.95, 0.7, 0.3 }, skillLine = 186 },
	{ key = "treasure", label = "Treasure", spells = { 3365, 6247, 6477, 21248, 22810 }, name = "Opening", icon = 132594, color = { 0.4, 0.75, 1 } },
	{ key = "fish", label = "Fishing", spells = { 7620, 7731, 7732, 18248 }, name = "Fishing", icon = 136245, color = { 0.8, 0.5, 1 }, skillLine = 356 },
}
M.kindByKey = {}
local kindBySpell = {}
for index, kind in ipairs(M.KINDS) do
	kind.order = index
	M.kindByKey[kind.key] = kind
	for _, id in ipairs(kind.spells) do kindBySpell[id] = kind end
end

local kindByName
local function KindOfSpell(spellID)
	if kindBySpell[spellID] then return kindBySpell[spellID] end
	-- A rank or Forever spell we don't list: compare names.
	if not kindByName then
		kindByName = {}
		for _, kind in ipairs(M.KINDS) do
			local name = C_Spell and C_Spell.GetSpellName and Clean(Try(C_Spell.GetSpellName, kind.spells[1]))
			kindByName[type(name) == "string" and name or kind.name] = kind
			kindByName[kind.name] = kind
		end
	end
	local name = C_Spell and C_Spell.GetSpellName and Clean(Try(C_Spell.GetSpellName, spellID))
	return name and kindByName[name] or nil
end
M.KindOfSpell = KindOfSpell

function M.KindIcon(kind)
	local icon = C_Spell and C_Spell.GetSpellTexture and Clean(Try(C_Spell.GetSpellTexture, kind.spells[1]))
	return icon or kind.icon
end

---------------------------------------------------------------------------
-- Store: account-wide, per map: { x, y, n = name, k = kind, c = count,
-- t = last, s = true while the node only came from an import, w = the
-- character that found it (charKey), f = when it was first found }, and
-- byChar[charKey][name] = gathers.
---------------------------------------------------------------------------
function M:Store()
	local store = E:GetGlobal("GatherNodes") or { maps = {} }
	store.maps = store.maps or {}
	return store
end

function M:Nodes(mapID)
	local maps = self:Store().maps
	if mapID == nil then return maps end
	maps[mapID] = maps[mapID] or {}
	return maps[mapID]
end

function M:Count()
	local total = 0
	for _, list in pairs(self:Store().maps) do total = total + #list end
	return total
end

-- Distance in yards between two points on one map (falls back to map units).
local function Yards(mapID, x1, y1, x2, y2)
	local c1, n1, w1 = WP.WorldPos(mapID, x1, y1)
	local c2, n2, w2 = WP.WorldPos(mapID, x2, y2)
	if c1 and c1 == c2 then
		local dn, dw = n1 - n2, w1 - w2
		return sqrt(dn * dn + dw * dw)
	end
	local dx, dy = (x1 - x2) * 4000, (y1 - y2) * 4000
	return sqrt(dx * dx + dy * dy)
end

-- The node of this name within the merge distance, if any.
function M:FindNear(mapID, x, y, name)
	local list = self:Store().maps[mapID]
	if not list then return nil end
	for _, node in ipairs(list) do
		if node.n == name and Yards(mapID, node.x, node.y, x, y) <= self.db.mergeYards then return node end
	end
end

-- A lookup of one map's nodes for many FindNear calls in a row (an
-- import): each position is worked out once and kept in cells as wide as
-- the merge distance, so a point checks only the cells around it. It finds
-- the same node FindNear would: world yards on one continent, map units
-- otherwise, and the earliest node in the list when several are close.
local NearIndex = {}
NearIndex.__index = NearIndex

local function CellKey(name, plane, ca, cb)
	return ("%s\001%s\001%d\001%d"):format(name, tostring(plane), ca, cb)
end

local function PointOf(mapID, x, y)
	local c, n, w = WP.WorldPos(mapID, x, y)
	return { c = c, n = n, w = w, fx = x * 4000, fy = y * 4000 }
end

function NearIndex:Add(node, point)
	point = point or PointOf(self.mapID, node.x, node.y)
	self.count = self.count + 1
	point.node, point.order = node, self.count
	local size, cells = self.size, self.cells
	local key = CellKey(node.n, "map", floor(point.fx / size), floor(point.fy / size))
	cells[key] = cells[key] or {}
	table.insert(cells[key], point)
	if point.c then
		key = CellKey(node.n, point.c, floor(point.n / size), floor(point.w / size))
		cells[key] = cells[key] or {}
		table.insert(cells[key], point)
	end
end

-- The node near (x, y) and the point worked out for it (for Add).
function NearIndex:Find(x, y, name)
	local q = PointOf(self.mapID, x, y)
	local size, cells, best = self.size, self.cells, nil
	local function Scan(plane, a, b, world)
		local ca, cb = floor(a / size), floor(b / size)
		for da = -1, 1 do
			for db = -1, 1 do
				local list = cells[CellKey(name, plane, ca + da, cb + db)]
				for _, p in ipairs(list or {}) do
					local d1, d2
					if world then
						d1, d2 = p.n - q.n, p.w - q.w
					elseif not (q.c and p.c == q.c) then
						d1, d2 = p.fx - q.fx, p.fy - q.fy
					end
					if d1 and sqrt(d1 * d1 + d2 * d2) <= size and (not best or p.order < best.order) then best = p end
				end
			end
		end
	end
	if q.c then Scan(q.c, q.n, q.w, true) end
	Scan("map", q.fx, q.fy, false)
	return best and best.node, q
end

function M:NearIndex(mapID)
	local index = setmetatable({ mapID = mapID, size = self.db.mergeYards, cells = {}, count = 0 }, NearIndex)
	for _, node in ipairs(self:Nodes(mapID)) do index:Add(node) end
	return index
end

-- Add one of your own finds. Returns the node and whether it is new.
function M:AddNode(mapID, x, y, name, kindKey, when)
	if not (mapID and x and y and type(name) == "string" and name ~= "" and self.kindByKey[kindKey]) then return nil end
	when = when or time()
	local node = self:FindNear(mapID, x, y, name)
	if node then
		-- Average toward the new find, so a node settles on its middle.
		local weight = 1 / ((node.c or 1) + 1)
		node.x = node.x + (x - node.x) * weight
		node.y = node.y + (y - node.y) * weight
		node.c = (node.c or 1) + 1
		node.t = when
		node.s = nil -- you have gathered it yourself now
		return node, false
	end
	local list = self:Nodes(mapID)
	node = { x = x, y = y, n = name, k = kindKey, c = 1, t = when }
	list[#list + 1] = node
	return node, true
end

-- Your own gather counts move with the character to its full-name key.
E:RegisterCharacterKeyMove(function(db, oldKey, newKey)
	local store = type(db.global) == "table" and db.global.GatherNodes
	E.MoveCharacterEntry(type(store) == "table" and store.byChar, oldKey, newKey)
end)

E:RegisterCharacterForget(function(db, key)
	local store = type(db.global) == "table" and db.global.GatherNodes
	if type(store) == "table" and type(store.byChar) == "table" then store.byChar[key] = nil end
end)

-- One of your own gathers, counted for this character.
function M:CountGather(name)
	if type(name) ~= "string" or name == "" or not E.charKey then return end
	local store = self:Store()
	store.byChar = type(store.byChar) == "table" and store.byChar or {}
	local mine = store.byChar[E.charKey]
	if type(mine) ~= "table" then
		mine = {}
		store.byChar[E.charKey] = mine
	end
	mine[name] = (mine[name] or 0) + 1
end

function M:Gathered(charKey)
	local store = self:Store()
	local list = type(store.byChar) == "table" and store.byChar[charKey or E.charKey]
	return type(list) == "table" and list or {}
end

function M:RemoveNode(mapID, node)
	local list = self:Nodes(mapID)
	for i = #list, 1, -1 do
		if list[i] == node then table.remove(list, i) end
	end
	self:RefreshPins()
end

function M:ClearMap(mapID)
	local maps = self:Store().maps
	local removed = maps[mapID] and #maps[mapID] or 0
	maps[mapID] = nil
	self:RefreshPins()
	return removed
end

function M:ClearAll()
	local removed = self:Count()
	self:Store().maps = {}
	self:RefreshPins()
	return removed
end

-- Whether the pin filters show this node: its kind, the per-name filter
-- and the skill filter (Skill.lua).
function M:Shows(node)
	local kind = self.kindByKey[node.k]
	if not (kind and self.db[kind.key]) then return false end
	local hidden = self.db.hiddenNames
	if type(hidden) == "table" and hidden[node.n] then return false end
	return not self:SkillHides(node)
end

-- Skill.lua fills this in.
function M:SkillHides() return false end

-- Per-name filter: hide every node of one name (from the pin menu).
function M:HideName(name)
	if type(name) ~= "string" then return end
	if type(self.db.hiddenNames) ~= "table" then self.db.hiddenNames = {} end
	self.db.hiddenNames[name] = true
	self:RefreshPins()
end

function M:HiddenNameCount()
	local count = 0
	for _ in pairs(type(self.db.hiddenNames) == "table" and self.db.hiddenNames or {}) do count = count + 1 end
	return count
end

function M:ShowAllNames()
	local count = self:HiddenNameCount()
	self.db.hiddenNames = {}
	self:RefreshPins()
	return count
end

-- Read-only summary of one map for other modules (see the header).
function M:NodeTypesInZone(uiMapID, shownOnly)
	local result = {}
	local list = uiMapID and self:Store().maps[uiMapID]
	if type(list) ~= "table" then return result end
	local byName = {}
	for _, node in ipairs(list) do
		local kind = self.kindByKey[node.k]
		if kind and type(node.n) == "string" and (not shownOnly or (self.db and self:Shows(node))) then
			local key = node.k .. "\0" .. node.n
			local entry = byName[key]
			if not entry then
				entry = { name = node.n, kind = node.k, label = kind.label, nodes = 0, finds = 0, order = kind.order }
				byName[key] = entry
				result[#result + 1] = entry
			end
			entry.nodes = entry.nodes + 1
			entry.finds = entry.finds + (tonumber(node.c) or 1)
		end
	end
	table.sort(result, function(a, b)
		if a.order ~= b.order then return a.order < b.order end
		return a.name < b.name
	end)
	for _, entry in ipairs(result) do entry.order = nil end
	return result
end

---------------------------------------------------------------------------
-- Recording your own gathering casts
---------------------------------------------------------------------------
local pending = {} -- castGUID -> { kind, name }
local LOOT_WAIT = 3 -- seconds an Opening waits for its loot window ("Treasure" below)

function M:OnCastSent(target, castGUID, spellID)
	if not self.db.record then return end
	spellID, target, castGUID = Clean(spellID), Clean(target), Clean(castGUID)
	local kind = spellID and KindOfSpell(spellID)
	if not (kind and castGUID) then return end
	if kind.key == "fish" then
		pending[castGUID] = { kind = kind } -- fishing has no target ("Fishing" below)
		return
	end
	if not (type(target) == "string" and target ~= "") then return end
	pending[castGUID] = { kind = kind, name = target }
end

function M:Record(cast, mapID, x, y)
	local node, new = self:AddNode(mapID, x, y, cast.name, cast.kind.key)
	if node then
		self:CountGather(cast.name)
		if new then node.w, node.f = E.charKey, node.t end
		local J = E.Journal
		if J and J.Changed then J:Changed("gathering") end
	end
	if node and new and self.db.recordNote then
		E:Print((L["New %s node: %s (%s %s)"]):format(E:InSentence(L[cast.kind.label]), cast.name, WP.MapName(mapID), WP.FormatCoords(x, y)))
	end
	if node then self:RefreshPins() end
	return node, new
end

function M:OnCastSucceeded(castGUID)
	castGUID = Clean(castGUID)
	local cast = castGUID and pending[castGUID]
	if not cast then return end
	pending[castGUID] = nil
	local mapID, x, y = WP.PlayerPos()
	if not mapID then return end -- no position here (instances)
	if cast.kind.key == "treasure" then
		-- Wait for the loot window (see "Treasure" below).
		self.awaitLoot = { cast = cast, mapID = mapID, x = x, y = y, untilTime = GetTime() + LOOT_WAIT }
		return
	elseif cast.kind.key == "fish" then
		self:FishingCast(mapID, x, y)
		return
	end
	self:Record(cast, mapID, x, y)
end

---------------------------------------------------------------------------
-- Treasure
---------------------------------------------------------------------------
-- Opening (3365 and its relatives) is also the cast for quest objects: a
-- crate to search, a sack to pick up, a lever. The conservative rule: an
-- Opening only becomes a treasure node when a loot window opens within
-- LOOT_WAIT seconds of it, holds at least one slot, is not fishing loot,
-- and holds no quest item. Objects that only advance a quest (no loot
-- window, or quest loot) are never recorded. Only what the loot window
-- shows is read; nothing is looted for you.
local function IsFishing()
	return rawget(_G, "IsFishingLoot") and Clean(Try(IsFishingLoot)) and true or false
end

local function LootLooksLikeTreasure()
	if IsFishing() then return false end
	local count = GetNumLootItems and Clean(Try(GetNumLootItems))
	if type(count) ~= "number" or count < 1 then return false end
	if GetLootSlotInfo then
		for slot = 1, count do
			local ok, _, _, _, _, _, _, isQuestItem, questID = pcall(GetLootSlotInfo, slot)
			if ok and (Clean(isQuestItem) or (Clean(questID) or 0) ~= 0) then return false end
		end
	end
	return true
end
M.LootLooksLikeTreasure = LootLooksLikeTreasure

function M:OnLootOpened(isFromItem)
	local wait = self.awaitLoot
	self.awaitLoot = nil
	if Clean(isFromItem) then return end
	if IsFishing() then
		self:OnFishingLoot()
		return
	end
	if not wait or GetTime() > wait.untilTime then return end
	if not self.db.record or not LootLooksLikeTreasure() then return end
	self:Record(wait.cast, wait.mapID, wait.x, wait.y)
end

function M:OnCastStopped(castGUID)
	castGUID = Clean(castGUID)
	if castGUID then pending[castGUID] = nil end
end

---------------------------------------------------------------------------
-- Fishing
---------------------------------------------------------------------------
-- A Fishing cast has no target, and its loot window does not name the pool.
-- The name comes from what you pointed at yourself: the game's tooltip for
-- a world object (the pool you hovered before or during the cast). The
-- object you hover right before the loot opens is the bobber you clicked;
-- its name (and its object id, when the tooltip carries one) is remembered
-- as "bobber" so it is never taken for a pool. When the loot names its
-- source object and that object is a pool you hovered once, its name is
-- used even without hovering again. No pool name, no node: open-water
-- catches are not recorded. The node goes FISH_REACH yards in front of
-- you, where the bobber lands.
local FISH_WAIT = 30    -- seconds a cast waits for its catch (the channel lasts about 20)
local FISH_REACH = 15   -- yards from you to the bobber
local HOVER_KEEP = 90   -- seconds before a cast a hovered object may still be the pool
local CLICK_WINDOW = 3  -- the object hovered this close to the loot is the clicked bobber
local HOVER_MAX = 12
local BOBBER_NAMES = { ["Fishing Bobber"] = true } -- English; other languages are learned

local hovered = {} -- recent world objects you pointed at: { name, entry, time }, newest last
local seenEntry, seenCount = {}, 0 -- object id -> name, this session

-- The object id of a GameObject GUID ("GameObject-0-1-2-3-<id>-<spawn>").
local function EntryOf(guid)
	guid = Clean(guid)
	if type(guid) ~= "string" then return nil end
	local kind, entry = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
	if kind == "GameObject" then return tonumber(entry) end
end
M.EntryOf = EntryOf

function M:FishMeta()
	local store = self:Store()
	local meta = type(store.fish) == "table" and store.fish or {}
	store.fish = meta
	meta.bobberNames = type(meta.bobberNames) == "table" and meta.bobberNames or {}
	meta.bobberEntries = type(meta.bobberEntries) == "table" and meta.bobberEntries or {}
	meta.pools = type(meta.pools) == "table" and meta.pools or {} -- object id -> pool name
	return meta
end

local function IsBobber(meta, name, entry)
	return (name and (BOBBER_NAMES[name] or meta.bobberNames[name])) or (entry and meta.bobberEntries[entry]) or false
end

-- GameTooltip showed a world object (TooltipDataProcessor, Object type).
function M:OnObjectTooltip(tooltip, data)
	if not self.active or tooltip ~= GameTooltip or type(data) ~= "table" then return end
	local line = type(data.lines) == "table" and data.lines[1]
	local name = type(line) == "table" and Clean(line.leftText)
	if type(name) ~= "string" then
		local first = _G.GameTooltipTextLeft1
		name = first and first.GetText and Clean(Try(first.GetText, first))
	end
	if type(name) ~= "string" or name == "" then return end
	local entry = EntryOf(data.guid)
	hovered[#hovered + 1] = { name = name, entry = entry, time = GetTime() }
	if #hovered > HOVER_MAX then table.remove(hovered, 1) end
	if entry and not seenEntry[entry] then
		if seenCount > 400 then wipe(seenEntry) seenCount = 0 end
		seenEntry[entry] = name
		seenCount = seenCount + 1
	end
end

-- The map point `yards` in front of a map position (facing in radians,
-- 0 = north, counter-clockwise). The same point when it can't be worked out.
function M.Ahead(mapID, x, y, facing, yards)
	if not (facing and C_Map and C_Map.GetMapPosFromWorldPos and CreateVector2D) then return x, y end
	local continent, north, west = WP.WorldPos(mapID, x, y)
	if not continent then return x, y end
	north, west = north + cos(facing) * yards, west + sin(facing) * yards
	local _, position = Try(C_Map.GetMapPosFromWorldPos, continent, CreateVector2D(north, west), mapID)
	if type(position) ~= "table" or not position.GetXY then return x, y end
	local ax, ay = position:GetXY()
	ax, ay = Clean(ax), Clean(ay)
	if not (ax and ay) or ax < 0 or ax > 1 or ay < 0 or ay > 1 then return x, y end
	return ax, ay
end

function M:FishingCast(mapID, x, y)
	local facing = GetPlayerFacing and Clean(Try(GetPlayerFacing))
	local now = GetTime()
	self.awaitFish = { mapID = mapID, x = x, y = y, facing = type(facing) == "number" and facing or nil, castTime = now, untilTime = now + FISH_WAIT }
end

-- The pool this catch came from, or nil (open water, or nothing hovered).
function M:PoolName(wait)
	local meta = self:FishMeta()
	local now = GetTime()
	-- The bobber you clicked: hovered just now, after the cast.
	local last = hovered[#hovered]
	if last and now - last.time <= CLICK_WINDOW and last.time > wait.castTime then
		meta.bobberNames[last.name] = true
		if last.entry then meta.bobberEntries[last.entry] = true end
	end
	-- 1. The loot's source object, when it is a pool you hovered once.
	local source = rawget(_G, "GetLootSourceInfo") and Try(GetLootSourceInfo, 1)
	local entry = EntryOf(source)
	if entry and not meta.bobberEntries[entry] then
		local name = meta.pools[entry] or seenEntry[entry]
		if name and not IsBobber(meta, name) then return name, entry end
	end
	-- 2. The newest object you pointed at around the cast that isn't a bobber.
	for i = #hovered, 1, -1 do
		local h = hovered[i]
		if h.time < wait.castTime - HOVER_KEEP then break end
		if not IsBobber(meta, h.name, h.entry) then return h.name, h.entry end
	end
end

function M:OnFishingLoot()
	local wait = self.awaitFish
	self.awaitFish = nil
	if not wait or GetTime() > wait.untilTime or not self.db.record then return end
	local name, entry = self:PoolName(wait)
	if not name then return end
	if entry then self:FishMeta().pools[entry] = name end
	local x, y = M.Ahead(wait.mapID, wait.x, wait.y, wait.facing, FISH_REACH)
	return self:Record({ kind = self.kindByKey.fish, name = name }, wait.mapID, x, y)
end

---------------------------------------------------------------------------
-- Events, commands and lifecycle
---------------------------------------------------------------------------
local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, unit, a, b, c)
	if not M.active then return end
	if event == "LOOT_OPENED" then
		M:OnLootOpened(a) -- LOOT_OPENED: autoLoot, isFromItem
		return
	elseif event == "SKILL_LINES_CHANGED" then
		M:SkillChanged()
		return
	end
	if unit ~= "player" then return end
	if event == "UNIT_SPELLCAST_SENT" then
		M:OnCastSent(a, b, c)
	elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
		M:OnCastSucceeded(a)
	else
		M:OnCastStopped(a)
	end
end)

function M:ListText(mapID)
	local list = self:Nodes(mapID)
	local names = {}
	for _, entry in ipairs(self:NodeTypesInZone(mapID)) do names[#names + 1] = ("%s x%d"):format(entry.name, entry.nodes) end
	return #list, table.concat(names, ", ")
end

local function CurrentMap()
	local mapID = WP.PlayerPos()
	return mapID or (C_Map and C_Map.GetBestMapForUnit and Clean(Try(C_Map.GetBestMapForUnit, "player")))
end
M.CurrentMap = CurrentMap

function M:Command(arg)
	arg = (arg or ""):match("^%s*(.-)%s*$")
	local word, rest = arg:match("^(%S*)%s*(.-)$")
	word = word:lower()
	local mapID = CurrentMap()
	if word == "clear" then
		if rest:lower() == "all" then
			E:Print((L["%d gathering nodes removed."]):format(self:ClearAll()))
		elseif mapID then
			E:Print((L["%d gathering nodes removed from %s."]):format(self:ClearMap(mapID), WP.MapName(mapID)))
		end
	elseif word == "" or word == "list" then
		if not mapID then E:Print(L["No map here."]) return end
		local count, text = self:ListText(mapID)
		E:Print((L["%s: %d node%s%s"]):format(WP.MapName(mapID), count, count == 1 and "" or "s", count > 0 and (": " .. text) or "."))
		E:Print((L["%d nodes on all maps."]):format(self:Count()))
	elseif word == "export" then
		self:Export(rest:lower() == "all" and "all" or mapID)
	elseif word == "import" then
		self:ShowImport()
	elseif word == "send" then
		local target, scope = rest:match("^(%S*)%s*(.-)$")
		self:Send(scope:lower() == "all" and "all" or mapID, target)
	elseif word == "show" then
		E:Print((L["%d hidden node names shown again."]):format(self:ShowAllNames()))
	else
		E:Print(L["/eui gather [list | clear | clear all | export [all] | import | send <party | guild | name> [all] | show]"])
	end
end

E:AddCommand("gather", "[list | clear [all] | export [all] | import | send <who> [all] | show]  the herb, ore, treasure and fishing nodes you have gathered", function(arg)
	if M.active then M:Command(arg) else E:Print(E:ModuleOffHint("Gathering")) end
end)

local tooltipHooked
local function HookObjectTooltips()
	if tooltipHooked then return end
	local processor = rawget(_G, "TooltipDataProcessor")
	local types = Enum and Enum.TooltipDataType
	if not (processor and processor.AddTooltipPostCall and types and types.Object) then return end
	tooltipHooked = true
	processor.AddTooltipPostCall(types.Object, function(tooltip, data) M:OnObjectTooltip(tooltip, data) end)
end

---------------------------------------------------------------------------
-- The journal source (My Adventure): new nodes as "gather" rows, one per
-- day, map and node name, and the gathers per character as facts.
---------------------------------------------------------------------------
local function DayOf(t)
	return floor(t / 86400)
end

function M:JournalRows(charKey, from, to)
	local groups, rows = {}, {}
	for mapID, list in pairs(self:Store().maps) do
		for _, node in ipairs(list) do
			local first = tonumber(node.f)
			if node.w == charKey and first and first >= from and first <= to and type(node.n) == "string" then
				local key = ("%d:%s:%s"):format(DayOf(first), tostring(mapID), node.n)
				local row = groups[key]
				if not row then
					row = { t = first, kind = "gather", node = node.n, count = 0, zone = WP.MapName(mapID) or false,
						ref = "gathering:" .. key }
					groups[key] = row
					rows[#rows + 1] = row
				end
				row.count = row.count + 1
				if first < row.t then row.t = first end
			end
		end
	end
	return rows
end

function M:JournalFacts(charKey)
	local total, best, bestCount = 0, nil, 0
	for name, count in pairs(self:Gathered(charKey)) do
		total = total + count
		if count > bestCount or (count == bestCount and best and name < best) then best, bestCount = name, count end
	end
	return { gathers = total, mostGathered = best, mostGatheredCount = bestCount > 0 and bestCount or nil }
end

local function RegisterJournalSource()
	local J = E.Journal
	if not (J and J.RegisterSource) then return end
	J:RegisterSource("gathering", {
		title = L["Gathering finds"],
		module = "Gathering",
		scope = "char",
		kinds = { "gather" },
		read = function(charKey, from, to) return M:JournalRows(charKey, from, to) end,
		summarize = function(charKey) return M:JournalFacts(charKey) end,
	})
end

function M:OnInitialize()
	E:RegisterGlobal("GatherNodes", { maps = {} })
	RegisterJournalSource()
end

function M:OnEnable()
	for _, event in ipairs({ "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED" }) do
		pcall(events.RegisterUnitEvent, events, event, "player")
	end
	pcall(events.RegisterEvent, events, "LOOT_OPENED")
	pcall(events.RegisterEvent, events, "SKILL_LINES_CHANGED")
	HookObjectTooltips()
	self:EnableMap()
end

function M:OnDisable()
	events:UnregisterAllEvents()
	wipe(pending)
	wipe(hovered)
	self.awaitLoot, self.awaitFish = nil, nil
	self:DisableMap()
end

function M:OnProfileChanged()
	if self.active then
		self:SkillChanged()
		self:RefreshPins()
	end
end

-- Map.lua, Skill.lua and Share.lua fill these in.
function M:RefreshPins() end
function M:EnableMap() end
function M:DisableMap() end
function M:SkillChanged() end
function M:Export() end
function M:ShowImport() end
function M:Send() end

---------------------------------------------------------------------------
-- Options and styles
---------------------------------------------------------------------------
M.options = {
	{ type = "description", label = "Every herb, ore, chest and fishing pool you gather shows on the world map and minimap; finds close together are one node. Also: /eui gather." },
	{ type = "header", label = "Nodes" },
	{ type = "toggle", key = "record", label = "Remember new finds", desc = "Record a node each time you gather. Off keeps the nodes you have but adds no new ones." },
	{ type = "toggle", key = "herb", label = "Herbs", desc = "Show herb nodes." },
	{ type = "toggle", key = "ore", label = "Ore", desc = "Show mining nodes." },
	{ type = "toggle", key = "treasure", label = "Treasure", desc = "Show chests you opened. An opened object counts only when it gave a loot window without quest items, so quest objects are left out." },
	{ type = "toggle", key = "fish", label = "Fishing pools", desc = "Show fishing pools you fished. Point at the pool before you cast so its name is known; catches in open water are not recorded." },
	{ type = "select", key = "skillFilter", label = "Skill filter", values = {
		all = "Show all nodes",
		canGather = "Hide nodes above my skill",
		skillUp = "Only nodes that still give skill",
	}, desc = "Hide herb and ore nodes by your Herbalism or Mining skill. Nodes whose required skill isn't known stay shown." },
	{ type = "execute", label = "Show hidden nodes again", desc = "Show every node name you hid with \"Hide every ...\" in the pin menu.",
		disabled = function() return M.db and M:HiddenNameCount() == 0 and L["No node names are hidden."] or nil end, func = function()
		E:Print((L["%d hidden node names shown again."]):format(M:ShowAllNames()))
	end },
	{ type = "range", key = "mergeYards", label = "Merge finds within", min = 5, max = 50, step = 5, desc = "Finds of the same node closer than this many yards count as one node." },
	{ type = "toggle", key = "recordNote", label = "Chat line for new nodes", desc = "Print a chat line when a find adds a new node." },
	{ type = "header", label = "Pins" },
	{ type = "toggle", key = "worldPins", label = "World map pins", desc = "Show the nodes on the world map." },
	{ type = "toggle", key = "minimapPins", label = "Minimap pins", desc = "Show nearby nodes on the minimap, also from the zone next door when you stand near its border." },
	{ type = "toggle", key = "minimapEdge", label = "Far nodes on the edge", desc = "Keep this zone's nodes out of minimap range on its edge instead of hiding them.", dependsOn = "minimapPins" },
	{ type = "select", key = "iconStyle", label = "Pin look", values = { icons = "Icons", dots = "Colored dots", contrast = "High contrast" },
		desc = "Profession icons; small dots colored by kind (green herbs, orange ore, blue treasure, violet fishing); or bright dots with a white ring that stand out on any map." },
	{ type = "range", key = "pinSize", label = "Pin size", min = 8, max = 28, step = 1, desc = "Size of the pins." },
	{ type = "range", percent = true, key = "pinAlpha", label = "Pin opacity", min = 0.3, max = 1, step = 0.05, desc = "How solid the pins are." },
	{ type = "header", label = "Data" },
	{ type = "execute", label = "Clear this zone", confirm = true, desc = "Forget every node on the map you are on.", func = function() M:Command("clear") end },
	{ type = "execute", label = "Clear all", desc = "Forget every node on every map (asks first).", func = function()
		E:ShowConfirm({ key = "ELDOUI_GATHER_CLEAR_ALL", title = L["Gathering"], text = L["Forget all %d gathering nodes on every map?"]:format(M:Count()),
			accept = ACCEPT, danger = true, onAccept = function() M:Command("clear all") end })
	end },
	{ type = "execute", label = "Export this zone", desc = "A string with the nodes of the map you are on, to copy and give to a friend.", func = function() M:Export(CurrentMap()) end },
	{ type = "execute", label = "Export all", desc = "A string with every node on every map.", func = function() M:Export("all") end },
	{ type = "execute", label = "Import nodes", desc = "Paste a node string from a friend. You see what it holds first; the nodes are added to yours and nothing is removed.", func = function() M:ShowImport() end },
	{ type = "header", label = "Sharing" },
	{ type = "toggle", key = "shareSend", label = "Allow sending nodes", desc = "Off by default. On shows the send buttons below; each send is one click, and the other player must accept." },
	{ type = "select", key = "shareTo", label = "Send to", values = { group = "My group", guild = "My guild", player = "A player (by name)" },
		desc = "Who gets the offer when you click a send button.", dependsOn = "shareSend" },
	{ type = "input", key = "sharePlayer", label = "Player name", desc = "The player who gets the offer when \"Send to\" is a player. Name-Realm for another realm.", dependsOn = "shareSend" },
	{ type = "execute", label = "Send this zone", desc = "Offer the nodes of the map you are on.", dependsOn = "shareSend", func = function() M:Send(CurrentMap()) end },
	{ type = "execute", label = "Send all", desc = "Offer every node on every map.", dependsOn = "shareSend", func = function() M:Send("all") end },
}

E:RegisterStyles("Gathering", {
	{ key = "Standard", title = "Standard", desc = "All kinds, icons on the world map and minimap.",
		settings = { herb = true, ore = true, treasure = true, fish = true, worldPins = true, minimapPins = true, iconStyle = "icons", pinSize = 14, pinAlpha = 0.9 } },
	{ key = "Dots", title = "Dots", desc = "Small colored dots, quieter on a busy map.",
		settings = { iconStyle = "dots", pinSize = 10 } },
	{ key = "HighContrast", title = "High contrast", desc = "Large bright dots with a white ring, easy to spot on any map.",
		settings = { iconStyle = "contrast", pinSize = 16, pinAlpha = 1 } },
	{ key = "Herbalist", title = "Herbalist", desc = "Only herb nodes, and only those you can gather.",
		settings = { herb = true, ore = false, treasure = false, fish = false, skillFilter = "canGather" } },
	{ key = "Miner", title = "Miner", desc = "Only ore and treasure, and only veins you can mine.",
		settings = { herb = false, ore = true, treasure = true, fish = false, skillFilter = "canGather" } },
	{ key = "Angler", title = "Angler", desc = "Only fishing pools.",
		settings = { herb = false, ore = false, treasure = false, fish = true } },
	{ key = "MinimapOnly", title = "Minimap only", desc = "Nodes on the minimap, a clean world map.",
		settings = { worldPins = false, minimapPins = true } },
})
