-- EldoUI Zone Quests: what is done and what is left in each zone.
--
-- The Loot Guide's quest engine answers this for dungeons
-- (LG:InstanceQuests); this file does the same for the open world:
--
--   LG:ZoneQuests(uiMapID, opts)   rows of a zone, grouped by status
--       opts (all optional, default the Zone Quests settings):
--         mine         only your side, race and class (default true)
--         hideDone     leave out completed quests
--         hideGray     leave out quests gray for your level
--         chains       one row per chain inside the zone
--         repeatables  keep repeatable quests
--       row = { id, quest, status, detail, group, level, fit, new,
--               repeatable, giver = { npc, name }, chainPart, chainLength }
--   LG:ZoneQuestCounts(uiMapID)    total, done, open (your quests only,
--       every quest, not one per chain; repeatables only when counted)
--   LG:ZoneQuestZones()            { { uiMapID, name, continent, total,
--       done, open }, ... } every zone the data knows, by continent and name
--   LG:ZoneQuestGiverPoint(row)    { uiMapID, x, y } of the giver, or nil
--
-- Quests come from EldoUI_LootData (Quests.lua and Journey.lua), the
-- Forever overlay and what the Journal saw you meet (LG:JourneyQuest); the
-- zone from the data's zone id (My Adventure's zone table), what you saw,
-- or the giver's spawn camp. Quests the data lacks and the game showed you
-- (or that the New in Forever check marks) are counted once seen and carry
-- new = true. Status is the game's own: completed flags, your quest log,
-- your level. Nothing here accepts, tracks or turns in a quest.
local _, E = ...
local L = E.L
local Key = E.Key
local LG = E.LootGuide

local Z = E:NewModule("ZoneQuests", {
	title = "Zone Quests",
	desc = "Which quests of each zone you have done and which are left, as a Catalog section of the Loot Guide, with the quest givers on the world map.",
	category = LG and LG.category,
	conflicts = { "QuestCompletist" },
	frames = {},
	movers = {},
	blizzard = {},
	savedKeys = { "profile.modules.ZoneQuests" },
	optionsPage = "module:ZoneQuests",
	presets = { "Bronze", "Contrast", "Dots", "Icons", "Minimal" },
	reload = false,
	defaults = {
		style = "Icons",
		mine = true,           -- only quests for your side, race and class
		hideDone = false,
		hideGray = false,
		chains = true,         -- one row per chain
		repeatables = false,   -- count and list repeatable quests
		pins = false,          -- quest giver pins on the world map
		pinSize = 18,
		pinLook = "icons",     -- icons, dots, contrast, bronze, minimal
		pinAvailable = true,   -- pins for quests you can take now
		pinLocked = false,     -- ... that need a prerequisite first
		pinLow = false,        -- ... that need a higher level
		zoneInfo = true,       -- "Quests 34/81" in Zone Info's map tooltip
	},
})
E.ZoneQuests = Z
-- The built-in group list (Core/Config.lua) names this module too, so it
-- keeps its group after the module split.
if E.defaultModuleCategory then E.defaultModuleCategory.ZoneQuests = Z.category end

local Secret = E.Secret

local Plain = E.Plain

function Z:Running()
	return self.active and LG and LG.active and true or false
end

---------------------------------------------------------------------------
-- Groups (page order) and their titles
---------------------------------------------------------------------------
Z.GROUPS = { "available", "active", "locked", "low", "done", "notforyou" }
Z.GROUP_TITLE = E:TranslateValues({
	available = E.Key("Available now"), active = E.Key("In your quest log"), locked = E.Key("Needs a prerequisite"),
	low = E.Key("Too low level"), done = E.Key("Done"), notforyou = E.Key("Not for you"),
})
local GROUP_OF = { available = "available", turnin = "active", active = "active", locked = "locked", low = "low",
	done = "done", notforyou = "notforyou" }
local GROUP_RANK = {}
for index, key in ipairs(Z.GROUPS) do GROUP_RANK[key] = index end
Z.GROUP_OF = GROUP_OF

-- Race masks per side (as Quests.lua).
local ALLIANCE = 1 + 4 + 8 + 64
local HORDE = 2 + 16 + 32 + 128

---------------------------------------------------------------------------
-- The zone index: uiMapID -> { questID, ... }, built once per data change
---------------------------------------------------------------------------
local index          -- uiMapID -> list of quest ids
local questZone      -- questID -> uiMapID
local nextOf         -- questID -> quests that need it (any zone)
local countCache = {}
local building = false

local function Next()
	local A = E.Adventure
	return A and A.Next
end

local function Data()
	return select(3, LG:DataStatus())
end

function Z:Invalidate(all)
	wipe(countCache)
	if all then index, questZone, nextOf = nil, nil, nil end
	self.rev = (self.rev or 0) + 1
end

-- The zone of a merged quest record: what you saw or the overlay says,
-- the data's zone id, else (out of combat) the zone of its giver's camp.
local function ZoneOf(quest)
	local N = Next()
	local map = N and N.QuestZone and N.QuestZone(quest)
	if map then return map end
	if InCombatLockdown() then return nil end
	local first = quest.starts and quest.starts[1]
	if not first or first.kind == "item" then return nil end
	local camps = LG:SpawnPoints(first.kind, first.id)
	if camps[1] and LG.MapPosition then
		local uiMapID = LG:MapPosition(camps[1])
		return uiMapID
	end
end

local function AddIds(set, tbl)
	if type(tbl) ~= "table" then return end
	for questID in pairs(tbl) do
		if type(questID) == "number" then set[questID] = true end
	end
end

local function Build()
	if index then return index end
	if building or InCombatLockdown() then return nil end
	building = true
	local ids = {}
	local LD = Data()
	if LD then
		AddIds(ids, LD.quests)
		AddIds(ids, LD.journey)
	end
	local overlay = E.foreverData
	if type(overlay) == "table" then AddIds(ids, overlay.quests) end
	local db = rawget(_G, "EldoUIDB")
	local seen = type(db) == "table" and type(db.journalSeen) == "table" and db.journalSeen or nil
	if seen then AddIds(ids, seen.quests) end
	local byZone, zoneOf, needs = {}, {}, {}
	for questID in pairs(ids) do
		local quest = LG:JourneyQuest(questID)
		if quest and not quest.removed and not quest.instance then
			local map = ZoneOf(quest)
			if map then
				byZone[map] = byZone[map] or {}
				table.insert(byZone[map], questID)
				zoneOf[questID] = map
			end
			for _, list in ipairs({ quest.allOf or {}, quest.anyOf or {} }) do
				for _, prev in ipairs(list) do
					if prev > 0 then
						needs[prev] = needs[prev] or {}
						table.insert(needs[prev], questID)
					end
				end
			end
		end
	end
	for _, list in pairs(byZone) do table.sort(list) end
	for _, list in pairs(needs) do table.sort(list) end
	index, questZone, nextOf = byZone, zoneOf, needs
	building = false
	return index
end
Z.Build = Build

-- Is the index there (or can it be built now)?
function Z:Ready()
	return Build() ~= nil
end

-- The zone a quest belongs to, or nil.
function LG:ZoneOfQuest(questID)
	if not Build() then return nil end
	return questZone[tonumber(questID)]
end

---------------------------------------------------------------------------
-- Status of a merged record
---------------------------------------------------------------------------
local function OnQuest(questID)
	return LG:OnQuest(questID)
end

local function LogFlag(name, questID)
	local log = C_QuestLog
	if not (log and log[name]) then return false end
	local ok, value = pcall(log[name], questID)
	if not ok or Secret(value) then return false end
	return value and true or false
end

-- status, detail as LG:QuestStatus, for every record (lean ones too).
function Z:Status(questID, quest)
	if quest and quest.full then return LG:QuestStatus(questID) end
	if LG:QuestDone(questID) then return "done" end
	local player = LG:Player()
	if quest then
		local rMask, cMask = quest.raceMask, quest.classMask
		if rMask and rMask > 0 and (player.raceMask or 0) > 0 and bit.band(rMask, player.raceMask) == 0 then return "notforyou", "race" end
		if cMask and cMask > 0 and (player.classMask or 0) > 0 and bit.band(cMask, player.classMask) == 0 then return "notforyou", "class" end
	end
	if OnQuest(questID) then
		if LogFlag("ReadyForTurnIn", questID) or LogFlag("IsComplete", questID) then return "turnin" end
		return "active"
	end
	if not quest then return "available" end
	if quest.skill and quest.skill > 0 and not (player.professions and player.professions[quest.skill]) then return "notforyou", "skill" end
	for _, prev in ipairs(quest.allOf or {}) do
		if prev > 0 and not LG:QuestDone(prev) then return "locked", prev end
	end
	if quest.anyOf and #quest.anyOf > 0 then
		local any = false
		for _, prev in ipairs(quest.anyOf) do
			if LG:QuestDone(prev) then any = true break end
		end
		if not any then return "locked", quest.anyOf[1] end
	end
	if quest.activeQuest and quest.activeQuest > 0 and not OnQuest(quest.activeQuest) then return "locked", quest.activeQuest end
	if quest.minLevel and quest.minLevel > (player.level or 1) then return "low", quest.minLevel end
	return "available"
end

-- New in Forever: the data does not know it (overlay or seen by you), or
-- the New in Forever check says so.
local function IsNew(questID, quest)
	if quest and (quest.provenance == "forever" or quest.provenance == "seen") then return true end
	return E.IsForeverQuest and E:IsForeverQuest(questID) and true or false
end
Z.IsNew = IsNew

local function Settings(opts)
	local db = Z.db or Z.defaults
	opts = opts or {}
	local function Pick(key)
		if opts[key] ~= nil then return opts[key] end
		return db[key]
	end
	return {
		mine = Pick("mine") ~= false, hideDone = Pick("hideDone") and true or false, hideGray = Pick("hideGray") and true or false,
		chains = Pick("chains") ~= false, repeatables = Pick("repeatables") and true or false,
	}
end

---------------------------------------------------------------------------
-- Chains inside the zone
---------------------------------------------------------------------------
local function Previous(quest, inZone)
	for _, list in ipairs({ quest.allOf or {}, quest.anyOf or {} }) do
		for _, prev in ipairs(list) do
			if prev > 0 and inZone[prev] then return prev end
		end
	end
end

local function Following(quest, inZone)
	if quest.nextInChain and quest.nextInChain > 0 and inZone[quest.nextInChain] then return quest.nextInChain end
	for _, id in ipairs(nextOf and nextOf[quest.id] or {}) do
		if inZone[id] then return id end
	end
end

-- root, part, length of a quest's chain inside the zone.
local function ChainOf(questID, inZone)
	local seen = { [questID] = true }
	local root, part = questID, 1
	local cursor = LG:JourneyQuest(questID)
	for _ = 1, 30 do
		local prev = cursor and Previous(cursor, inZone)
		if not prev or seen[prev] then break end
		seen[prev] = true
		root, part = prev, part + 1
		cursor = LG:JourneyQuest(prev)
	end
	local length = part
	cursor = LG:JourneyQuest(questID)
	for _ = 1, 30 do
		local nextID = cursor and Following(cursor, inZone)
		if not nextID or seen[nextID] then break end
		seen[nextID] = true
		length = length + 1
		cursor = LG:JourneyQuest(nextID)
	end
	return root, part, length
end
Z.ChainOf = ChainOf

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------
local function GiverOf(quest)
	if type(quest.giver) == "table" and (quest.giver.npc or quest.giver.name) then
		local name = quest.giver.name
		if not name and quest.giver.npc then
			local mob = LG:Mob(quest.giver.npc)
			name = mob and mob.name
		end
		return { npc = quest.giver.npc, name = name, map = quest.giver.map, x = quest.giver.x, y = quest.giver.y }
	end
	local first = quest.starts and quest.starts[1]
	if not first then return nil end
	if first.kind == "npc" then
		local mob = LG:Mob(first.id)
		return { npc = first.id, name = mob and mob.name or nil }
	elseif first.kind == "object" then
		return { object = first.id, name = LG:ObjectName(first.id) }
	elseif first.kind == "item" then
		local record = LG:ItemRecord(first.id)
		return { item = first.id, name = record and record.name or nil }
	end
end

local function Keep(row, s)
	if s.mine and row.status == "notforyou" then return false end
	if s.hideDone and row.status == "done" then return false end
	if s.hideGray and row.fit == "gray" and row.status ~= "done" then return false end
	if not s.repeatables and row.repeatable then return false end
	return true
end

local function MakeRow(questID, quest)
	local status, detail = Z:Status(questID, quest)
	local level = quest.level and quest.level > 0 and quest.level or nil
	return { id = questID, quest = quest, status = status, detail = detail, group = GROUP_OF[status] or "available",
		level = level, fit = LG:QuestFit(level or LG:Player().level), new = IsNew(questID, quest),
		repeatable = quest.repeatable and true or false, giver = GiverOf(quest) }
end

function LG:ZoneQuests(uiMapID, opts)
	uiMapID = tonumber(uiMapID)
	local out = {}
	if not uiMapID or not Build() then return out end
	local s = Settings(opts)
	local ids = index[uiMapID] or {}
	local inZone = {}
	for _, id in ipairs(ids) do inZone[id] = true end
	local byRoot = {}
	for _, questID in ipairs(ids) do
		local quest = LG:JourneyQuest(questID)
		if quest then
			local row = MakeRow(questID, quest)
			if Keep(row, s) then
				local root, part, length = ChainOf(questID, inZone)
				row.chainPart, row.chainLength = part, length
				if s.chains and length > 1 then
					local other = byRoot[root]
					if not other then
						byRoot[root] = row
						out[#out + 1] = row
					elseif GROUP_RANK[row.group] < GROUP_RANK[other.group]
						or (row.group == other.group and row.group ~= "done" and row.chainPart < other.chainPart)
						or (row.group == "done" and other.group == "done" and row.chainPart > other.chainPart) then
						-- The step that needs you now stands for the chain.
						for field, value in pairs(row) do other[field] = value end
					end
				else
					out[#out + 1] = row
				end
			end
		end
	end
	local level = LG:Player().level or 1
	table.sort(out, function(a, b)
		if a.group ~= b.group then return GROUP_RANK[a.group] < GROUP_RANK[b.group] end
		local la, lb = a.level or level, b.level or level
		if la ~= lb then return la < lb end
		local ta, tb = a.quest.title or "", b.quest.title or ""
		if ta ~= tb then return ta < tb end
		return a.id < b.id
	end)
	return out
end

-- total, done, open: your quests in the zone (every quest of a chain).
function LG:ZoneQuestCounts(uiMapID)
	uiMapID = tonumber(uiMapID)
	if not uiMapID then return 0, 0, 0 end
	local cached = countCache[uiMapID]
	if cached then return cached[1], cached[2], cached[3] end
	if not Build() then return 0, 0, 0 end
	local total, done, open = 0, 0, 0
	local s = Settings({ mine = true, hideDone = false, hideGray = false, chains = false })
	for _, questID in ipairs(index[uiMapID] or {}) do
		local quest = LG:JourneyQuest(questID)
		if quest then
			local status = Z:Status(questID, quest)
			local repeatable = quest.repeatable and true or false
			if status ~= "notforyou" and (s.repeatables or not repeatable) then
				total = total + 1
				if status == "done" then
					done = done + 1
				elseif status == "available" or status == "active" or status == "turnin" then
					open = open + 1
				end
			end
		end
	end
	countCache[uiMapID] = { total, done, open }
	return total, done, open
end

-- Every zone with quests: name, continent and counts, by continent then name.
function LG:ZoneQuestZones()
	local out = {}
	if not Build() then return out end
	local N = Next()
	for uiMapID in pairs(index) do
		local total, done, open = self:ZoneQuestCounts(uiMapID)
		if total > 0 then
			local name = N and N.ZoneName and N.ZoneName(uiMapID) or self:MapName(uiMapID)
			if type(name) == "string" and name ~= "" then
				out[#out + 1] = { uiMapID = uiMapID, name = name, continent = N and N.Continent and N.Continent(uiMapID) or 0,
					total = total, done = done, open = open }
			end
		end
	end
	table.sort(out, function(a, b)
		if (a.continent or 0) ~= (b.continent or 0) then return (a.continent or 0) > (b.continent or 0) end
		return a.name < b.name
	end)
	return out
end

-- Where the giver stands: what you saw or the overlay says, else the
-- data's biggest spawn camp (out of combat; map math).
function LG:ZoneQuestGiverPoint(row)
	local giver = row and row.giver
	if not giver then return nil end
	if giver.map and giver.x and giver.y then return { uiMapID = giver.map, x = giver.x, y = giver.y } end
	if InCombatLockdown() then return nil end
	local kind = giver.npc and "npc" or giver.object and "object" or nil
	if not kind then return nil end
	local camps = self:SpawnPoints(kind, giver.npc or giver.object)
	return camps[1] and self:PointFor(camps[1]) or nil
end

-- The Map button of a row: a waypoint on the giver (Waypoints module when
-- it runs, else the game's own pin).
function Z:SetGiverWaypoint(row)
	local point = LG:ZoneQuestGiverPoint(row)
	if not point then return false end
	return LG:SetWaypoint(point, row.quest and row.quest.title or nil)
end

-- The zone you are in (nil inside instances).
function Z:CurrentZone()
	if not (C_Map and C_Map.GetBestMapForUnit) then return nil end
	local ok, map = pcall(C_Map.GetBestMapForUnit, "player")
	map = ok and Plain(map) or nil
	if type(map) ~= "number" then return nil end
	if index and index[map] then return map end
	-- A city or sub-zone map: walk up to the zone that has quests.
	for _ = 1, 4 do
		local info = C_Map.GetMapInfo and C_Map.GetMapInfo(map)
		local parent = type(info) == "table" and Plain(info.parentMapID) or nil
		if type(parent) ~= "number" or parent == 0 then break end
		map = parent
		if index and index[map] then return map end
	end
	return nil
end

---------------------------------------------------------------------------
-- Upkeep: counts follow your quest log, the index follows the data
---------------------------------------------------------------------------
LG:On("zonequests", function(changed)
	if changed.data or changed.journey then
		Z:Invalidate(true)
	elseif changed.quests or changed.player or changed.settings then
		Z:Invalidate(false)
	end
	if Z.active and (changed.data or changed.journey or changed.quests or changed.player) and Z.Changed then Z:Changed() end
end)

function Z:Start()
	if self.started then return end
	self.started = true
	if self.StartPage then self:StartPage() end
	if self.StartPins then self:StartPins() end
	self:RegisterEvent("PLAYER_REGEN_ENABLED", function()
		if self.wantBuild and not index then
			self.wantBuild = nil
			Build()
			if self.Changed then self:Changed() end
		end
	end)
end

function Z:Stop()
	if not self.started then return end
	self.started = false
	if self.StopPage then self:StopPage() end
	if self.StopPins then self:StopPins() end
	self:UnregisterEvent("PLAYER_REGEN_ENABLED")
end

-- Pages and pins call this when they need the index while in combat.
function Z:BuildLater()
	self.wantBuild = true
end

local PIN_LOOKS = { icons = true, dots = true, contrast = true, bronze = true, minimal = true }
local function Sanitize(db)
	if not PIN_LOOKS[db.pinLook] then db.pinLook = "icons" end
	db.pinSize = math.max(10, math.min(32, tonumber(db.pinSize) or 18))
end
Z.Sanitize = Sanitize

function Z:OnEnable()
	Sanitize(self.db)
	self:Invalidate(false)
	self:Start()
end

function Z:OnDisable()
	self:Stop()
end

function Z:OnProfileChanged()
	Sanitize(self.db)
	self:Invalidate(false)
	if not self.active then return end
	if self.RefreshPins then self:RefreshPins() end
	if self.Changed then self:Changed() end
end
