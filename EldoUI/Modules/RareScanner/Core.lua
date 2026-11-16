-- EldoUI Rare Alerts: tells the player when a rare creature shows
-- up, with a click-to-target card (Popup.lua), one sound and an optional
-- chat line (Notice.lua), a tooltip line and an Info Bar data text
-- (Options.lua), and an optional player-pressed targeting key (Target.lua).
--
-- This file: the module, its settings, the detection sources, the rare
-- test, dedupe, filters, the session list, ignore and watch lists,
-- notability and the callbacks.
--
-- How it stays within the rules (Midnight / Forever):
--   * It reads only what the game shows the player: minimap skulls
--     (vignettes), nameplates, the target, the mouseover, the group's
--     targets and monster yells. The game decides what a rare is
--     (UnitClassification, the vignette's kill atlas).
--   * Every identity read is guarded: C_Secrets.ShouldUnitIdentityBeSecret
--     first, then issecretvalue on each value. A secret name or GUID is
--     skipped, never compared, parsed or used as a table key.
--   * No combat log, no ADDON_ACTION_FORBIDDEN, no TargetUnit, no
--     SetRaidTarget, no polling: every source is an event.
--   * Nothing about rares is saved: sightings live in a session-only list
--     (with the position, for the waypoint click). Only the options and the
--     ignore list are saved.
--   * "Already done" comes only from the game: the marker names its own
--     completion quest (rewardQuestID) and C_QuestLog.IsQuestFlaggedCompleted
--     says whether this character has it. Nothing is inferred from kills.
--   * Treasures and events come from the same minimap markers: the game's
--     loot and event atlases or its Treasure marker type. They have no
--     creature, so their card sets a waypoint instead of targeting.
--   * Feature checks use the client's capabilities (C_VignetteInfo,
--     C_EventUtils.IsEventValid, C_Secrets), never the expansion level.
--
-- Rare data: LD.rares from EldoUI_LootData (through the Loot Guide's data
-- readers), names live from the client. Rares the data does not know
-- (Forever's own) are still announced from the game's classification; their
-- names are remembered for this session only, and the player can add names
-- to the watch list.
--
-- Public API (E.RareScanner, also EldoUI.RareScanner for plugins):
--   M:IsRare(npc)       true when LD.rares lists the creature
--   M:ReadRareUnit(unit[, watched])  the game's rare test for a unit it shows
--   M:Session()         this session's sightings, newest first
--   M:Ignore(key)       stop alerting for a rare ("npc:123" or "name:foo")
--   M:RemoveFromSession(key)  drop one line of the session list
--   M:Test()            a sample card with the current settings
--   M.callbacks         CallbackHandler: "RareSpotted"(info), "RareDead"(key)
--     M:RegisterCallback("RareSpotted", fn) / M:UnregisterCallback(...)
--   info = { key, kind, npc, name, classification, level, zone, uiMapID,
--            x, y, source, dead, done, quiet, notable, notableItems }
--   kind: "rare" (a creature), "treasure" or "event" (a minimap marker)
-- Written from scratch for EldoUI; no code, strings or data from other addons.
local _, E = ...
local L = E.L

local M = E:NewModule("RareScanner", {
	title = "Rare Alerts",
	aliases = { "Rare Scanner" }, -- the earlier title, for search and /eui
	desc = "Tells you when a rare creature, a treasure or an event shows up: a card and a sound. Reads only what the game shows (minimap markers, nameplates, your target).",
	category = "Quality of Life",
	conflicts = { "SilverDragon" },
	movers = { "EldoUI_RareHistory" },
	defaults = {
		enabled = true,
		style = "Standard",
		sources = { vignette = true, nameplate = true, target = true, group = true, chat = true },
		worldBosses = true,
		treasures = true,
		events = true,
		doneQuiet = false,
		quietKinds = { rare = false, rareelite = false, worldboss = false, treasure = false, event = false },
		quietZones = {},
		quietMode = "card",
		watch = "",
		ignore = {},
		instances = false,
		taxi = false,
		dead = false,
		repeatAfter = 600,
		popup = true,
		closeAfter = 60,
		closeDead = true,
		stackSize = 1,
		model = true,
		showSource = true,
		showLoot = true,
		width = 280,
		height = 88,
		scale = 1,
		fontSize = 13,
		sound = true,
		soundID = "eldo:EldoChime",
		soundRepeat = 1,
		notableSound = true,
		notableID = "eldo:EldoAlarm",
		notableRepeat = 3,
		treasureSound = true,
		treasureID = "eldo:Glass",
		channel = "default",
		vibrate = false,
		vibrateStrength = 0.6,
		flashTaskbar = true,
		chat = false,
		markOnClick = false,
		marker = 8,
		targetButton = false,
		shareTo = "group",
		sharePin = true,
		historyWindow = false,
		historyCollapsed = false,
		historyVisibility = E:VisibilityDefaults({ show = "nocombat" }),
	},
})

-- "Reset to defaults" keeps the player's own data and window places
-- (E:ResetModuleSettings, Core/Config.lua).
M.keepOnReset = { "ignore", "quietZones" }
M.keepOnResetNote = E.Key("Your ignore list and quiet zones are kept too.")
E.RareScanner = M
M.SESSION_CAP = 50

-- Fanfare's "Rare spotted" and other addons that announce rares.
E:RegisterFeatureConflicts("rarealert", { "SilverDragon", "NPCScan", "RareScanner" })

local CBH = LibStub and LibStub("CallbackHandler-1.0", true)
if CBH then M.callbacks = CBH:New(M) end

-- Session-only state, never saved.
M.session = {}      -- key -> entry
M.sessionList = {}  -- entries, newest first
M.lastAlert = {}    -- key -> GetTime() of the last alert
M.names = {}        -- npc -> name read from the game this session
local vignettesSeen = {} -- vignette guid -> key, while the vignette exists

---------------------------------------------------------------------------
-- Secret-safe reads
---------------------------------------------------------------------------
local Secret = E.Secret
M.Secret = Secret

-- The first value of fn(...), or nil when the call fails or it is secret.
local Read = E.PlainCall
M.Read = Read

-- True when the game hides this unit's identity (instances, restricted
-- content): the unit is skipped before any name or GUID is read.
local IdentitySecret = E.IdentitySecret
M.IdentitySecret = IdentitySecret

local function NpcFromGUID(guid)
	if type(guid) ~= "string" or Secret(guid) then return nil end
	local kind, _, _, _, _, id = strsplit("-", guid)
	if kind == "Creature" or kind == "Vehicle" then return tonumber(id) end
end
M.NpcFromGUID = NpcFromGUID

local function Lower(text)
	if type(text) ~= "string" or Secret(text) then return nil end
	text = strtrim(text):lower()
	if text == "" then return nil end
	return text
end

-- Event names this client has (feature check, never the expansion level).
local function EventValid(event)
	local utils = C_EventUtils
	if utils and utils.IsEventValid then
		local ok, valid = pcall(utils.IsEventValid, event)
		return ok and valid == true
	end
	return true
end
M.EventValid = EventValid

---------------------------------------------------------------------------
-- Rare data (EldoUI_LootData through the Loot Guide's readers)
---------------------------------------------------------------------------
local rareSet, nameIndex, indexedFrom

local function LG()
	return E.LootGuide
end

-- The LootData table, or nil when it is not installed or not loaded yet.
function M:Data()
	local lg = LG()
	if not (lg and lg.DataStatus) then return nil end
	local ok, _, _, LD = pcall(lg.DataStatus, lg)
	if ok and type(LD) == "table" then return LD end
end

-- Creature record { name, rank, minLevel, maxLevel, display } or nil.
function M:Record(npc)
	local lg = LG()
	if not (npc and lg and lg.Mob) then return nil end
	local ok, mob = pcall(lg.Mob, lg, npc)
	if ok and type(mob) == "table" then return mob end
end

local function BuildIndex(self)
	local LD = self:Data()
	if LD == indexedFrom and rareSet then return end
	indexedFrom = LD
	rareSet, nameIndex = {}, {}
	if type(LD) ~= "table" or type(LD.rares) ~= "table" then return end
	for _, npc in ipairs(LD.rares) do
		rareSet[npc] = true
		local mob = self:Record(npc)
		local key = mob and Lower(mob.name)
		if key and not nameIndex[key] then nameIndex[key] = npc end
	end
end

function M:IsRare(npc)
	BuildIndex(self)
	return npc and rareSet[tonumber(npc) or 0] == true or false
end

-- The rare npc id for a creature name (client locale), from the data or
-- from a name read this session.
function M:NpcByName(name)
	local key = Lower(name)
	if not key then return nil end
	BuildIndex(self)
	if nameIndex[key] then return nameIndex[key] end
	for npc, seen in pairs(self.names) do
		if Lower(seen) == key then return npc end
	end
end

-- Classification from the data's rank: 2 rare elite, 4 rare, 3 world boss.
local RANK_CLASS = { [2] = "rareelite", [3] = "worldboss", [4] = "rare" }
function M:DataClassification(npc)
	local mob = self:Record(npc)
	return mob and RANK_CLASS[mob.rank]
end

-- The best name for a rare: what the game showed this session, else the data.
function M:NameOf(npc, fallback)
	if npc and self.names[npc] then return self.names[npc] end
	local mob = self:Record(npc)
	return (mob and mob.name) or fallback
end

---------------------------------------------------------------------------
-- Notability: a mount, pet or toy in the rare's Loot Guide loot, or a piece
-- of its WoW: Forever set, that the player does not own yet. Returns true, false, or nil (unknown, no data).
---------------------------------------------------------------------------
local function OwnedMount(itemID)
	local journal = C_MountJournal
	if not (journal and journal.GetMountFromItem and journal.GetMountInfoByID) then return nil end
	local mountID = Read(journal.GetMountFromItem, itemID)
	if type(mountID) ~= "number" then return nil end
	local ok, _, _, _, _, _, _, _, _, _, _, collected = pcall(journal.GetMountInfoByID, mountID)
	if not ok or Secret(collected) then return nil end
	return collected and true or false
end

local function OwnedPet(itemID)
	local journal = C_PetJournal
	if not (journal and journal.GetPetInfoByItemID and journal.GetNumCollectedInfo) then return nil end
	local ok, _, _, _, _, _, _, _, _, _, _, _, _, speciesID = pcall(journal.GetPetInfoByItemID, itemID)
	if not ok or type(speciesID) ~= "number" or Secret(speciesID) then return nil end
	local count = Read(journal.GetNumCollectedInfo, speciesID)
	if type(count) ~= "number" then return nil end
	return count > 0
end

local function OwnedToy(itemID)
	local box = C_ToyBox
	if not (box and box.GetToyInfo and PlayerHasToy) then return nil end
	local toy = Read(box.GetToyInfo, itemID)
	if type(toy) == "nil" then return nil end
	local has = Read(PlayerHasToy, itemID)
	if type(has) ~= "boolean" then return nil end
	return has
end

function M:Notable(npc)
	local lg = LG()
	if not (npc and lg and lg.MobLoot) then return nil, {} end
	local ok, loot = pcall(lg.MobLoot, lg, npc)
	if not ok or type(loot) ~= "table" then return nil, {} end
	local items, known = {}, false
	for _, drop in ipairs(loot) do
		local itemID = drop.itemID
		if type(itemID) == "number" and drop.set and lg.HasItem then
			-- A piece of the rare's WoW: Forever set the character lacks.
			known = true
			if not lg:HasItem(itemID) then items[#items + 1] = { itemID = itemID, kind = "set" } end
		elseif type(itemID) == "number" then
			for _, check in ipairs({ { "mount", OwnedMount }, { "pet", OwnedPet }, { "toy", OwnedToy } }) do
				local owned = check[2](itemID)
				if type(owned) == "boolean" then
					known = true
					if not owned then items[#items + 1] = { itemID = itemID, kind = check[1] } end
					break
				end
			end
		end
	end
	if #items > 0 then return true, items end
	if known then return false, items end
	return nil, items
end

---------------------------------------------------------------------------
-- Watch and ignore lists
---------------------------------------------------------------------------
function M:WatchSet()
	local text = type(self.db.watch) == "string" and self.db.watch or ""
	if self.watchText == text and self.watchCache then return self.watchCache end
	local set = {}
	for part in text:gmatch("[^,;\n]+") do
		local key = Lower(part)
		if key then set[key] = true end
	end
	self.watchText, self.watchCache = text, set
	return set
end

function M:Watched(name)
	local key = Lower(name)
	return key and self:WatchSet()[key] or false
end

local function KeyFor(npc, name)
	if npc then return "npc:" .. npc end
	local lower = Lower(name)
	return lower and ("name:" .. lower) or nil
end
M.KeyFor = KeyFor

function M:IsIgnored(key)
	return type(self.db.ignore) == "table" and key and self.db.ignore[key] == true or false
end

function M:Ignore(key)
	if type(key) ~= "string" then return false end
	if type(self.db.ignore) ~= "table" then self.db.ignore = {} end
	self.db.ignore[key] = true
	if self.CloseKey then self:CloseKey(key) end
	return true
end

function M:ClearIgnored()
	self.db.ignore = {}
end

function M:IgnoredCount()
	local count = 0
	for _ in pairs(type(self.db.ignore) == "table" and self.db.ignore or {}) do count = count + 1 end
	return count
end

---------------------------------------------------------------------------
-- Quiet zones and kinds: a quiet sighting shows its card without sound
-- (quietMode "card") or nothing at all ("nothing"). Zones are the
-- player's own map (C_Map), saved as map IDs so they hold in every client
-- language; kinds come from the game's classification and marker atlas.
---------------------------------------------------------------------------
M.QUIET_KINDS = { "rare", "rareelite", "worldboss", "treasure", "event" }

-- The quiet kind of a sighting: its marker kind, else its classification.
function M.QuietKind(info)
	if info.kind == "treasure" or info.kind == "event" then return info.kind end
	local class = info.classification
	if class == "rareelite" or class == "worldboss" then return class end
	return "rare"
end

local function ZoneKey(uiMapID)
	if type(uiMapID) ~= "number" or Secret(uiMapID) then return nil end
	return tostring(math.floor(uiMapID))
end

function M:IsQuietZone(uiMapID)
	local key = ZoneKey(uiMapID)
	return key ~= nil and type(self.db.quietZones) == "table" and self.db.quietZones[key] == true
end

-- Add or remove a zone (default: where the player is). Returns the new
-- state, or nil when there is no map to name.
function M:SetQuietZone(uiMapID, quiet)
	if uiMapID == nil then uiMapID = select(2, self.PlayerZone()) end
	local key = ZoneKey(uiMapID)
	if not key then return nil end
	if type(self.db.quietZones) ~= "table" then self.db.quietZones = {} end
	self.db.quietZones[key] = quiet and true or nil
	return quiet and true or false
end

function M:ClearQuietZones()
	self.db.quietZones = {}
end

-- The quiet zones' names, sorted, for the options.
function M:QuietZoneNames()
	local names = {}
	for key in pairs(type(self.db.quietZones) == "table" and self.db.quietZones or {}) do
		local uiMapID = tonumber(key)
		local info = uiMapID and C_Map and C_Map.GetMapInfo and Read(C_Map.GetMapInfo, uiMapID)
		local name = type(info) == "table" and type(info.name) == "string" and not Secret(info.name) and info.name or ("#" .. key)
		names[#names + 1] = name
	end
	table.sort(names)
	return names
end

-- True when the sighting is quiet: its zone or its kind (a watched name is
-- the player's own pick, so its kind never quiets it).
function M:IsQuiet(info)
	if self:IsQuietZone(info.uiMapID or select(2, self.PlayerZone())) then return true end
	local kinds = type(self.db.quietKinds) == "table" and self.db.quietKinds or {}
	if kinds[self.QuietKind(info)] and not self:Watched(info.name) then return true end
	return false
end

---------------------------------------------------------------------------
-- Filters
---------------------------------------------------------------------------
-- True when nothing should be scanned right now (instances off, a taxi).
function M:Paused()
	if not self.active then return true end
	if not self.db.instances then
		local inside = Read(IsInInstance)
		if inside then return true end
	end
	if not self.db.taxi and Read(UnitOnTaxi, "player") then return true end
	return false
end

---------------------------------------------------------------------------
-- Session list
---------------------------------------------------------------------------
function M:Session()
	return self.sessionList
end

function M:ClearSession()
	wipe(self.session)
	wipe(self.sessionList)
	wipe(self.lastAlert)
	wipe(vignettesSeen)
	if self.RefreshDataText then self:RefreshDataText() end
	if self.RefreshHistory then self:RefreshHistory() end
end

local function AddToSession(self, info)
	local entry = self.session[info.key]
	if entry then
		for index, item in ipairs(self.sessionList) do
			if item == entry then table.remove(self.sessionList, index) break end
		end
	else
		entry = {}
		self.session[info.key] = entry
	end
	entry.key, entry.npc, entry.name = info.key, info.npc, info.name
	entry.zone, entry.source, entry.dead, entry.t = info.zone, info.source, info.dead, GetTime()
	entry.classification, entry.kind = info.classification, info.kind or "rare"
	entry.uiMapID, entry.x, entry.y = info.uiMapID, info.x, info.y
	entry.done = info.done
	table.insert(self.sessionList, 1, entry)
	while #self.sessionList > self.SESSION_CAP do
		local old = table.remove(self.sessionList)
		if old and self.session[old.key] == old then self.session[old.key] = nil end
	end
	if self.RefreshHistory then self:RefreshHistory() end
	return entry
end

---------------------------------------------------------------------------
-- A sighting
---------------------------------------------------------------------------
local function PlayerZone()
	local uiMapID = C_Map and C_Map.GetBestMapForUnit and Read(C_Map.GetBestMapForUnit, "player")
	local zone = Read(GetRealZoneText)
	if type(zone) ~= "string" or zone == "" then
		local info = uiMapID and C_Map.GetMapInfo and Read(C_Map.GetMapInfo, uiMapID)
		zone = type(info) == "table" and type(info.name) == "string" and info.name or nil
	end
	return zone, uiMapID
end
M.PlayerZone = PlayerZone

-- One sighting from any source. info: { npc, name, classification, level,
-- source, dead, x, y, uiMapID, test }. Returns the accepted info, or nil.
function M:Spotted(info)
	if type(info) ~= "table" or self:Paused() then return nil end
	if info.npc and type(info.name) ~= "string" then info.name = self:NameOf(info.npc) end
	if type(info.name) ~= "string" or info.name == "" then return nil end
	info.kind = info.kind or "rare"
	local key = info.markerKey or KeyFor(info.npc, info.name)
	if not key or self:IsIgnored(key) then return nil end
	info.key = key
	if info.npc and not info.fromData then self.names[info.npc] = info.name end

	local now = GetTime()
	local last = self.lastAlert[key]
	if last and now - last < (tonumber(self.db.repeatAfter) or 600) then
		-- Same rare again: merge what the new source knows (a position, the
		-- dead state) into the card already shown, no second alert.
		local entry = self.session[key]
		if entry and info.dead and not entry.dead then self:MarkDead(key) end
		if entry and info.done then entry.done = true end
		if self.MergeCard then self:MergeCard(info) end
		return nil
	end
	if info.dead and not self.db.dead then return nil end
	if info.classification == "worldboss" and not self.db.worldBosses and not self:Watched(info.name) then return nil end

	if not info.classification and info.npc then info.classification = self:DataClassification(info.npc) end
	if not info.level and info.npc then
		local mob = self:Record(info.npc)
		info.level = mob and mob.maxLevel
	end
	if not info.zone then info.zone, info.uiMapID = PlayerZone() end
	info.notable, info.notableItems = self:Notable(info.npc)

	if not info.test and self:IsQuiet(info) then
		if self.db.quietMode == "nothing" then return nil end
		info.quiet = true
	end

	self.lastAlert[key] = now
	AddToSession(self, info)
	if info.done and self.db.doneQuiet then
		-- Already done and kept quiet: listed, no card, no sound.
		if self.RefreshDataText then self:RefreshDataText() end
		return nil
	end
	self:Announce(info)
	return info
end

-- Notice, card, plugins, Fanfare.
function M:Announce(info)
	if self.Notify then
		local ok, err = pcall(self.Notify, self, info)
		if not ok then geterrorhandler()(err) end
	end
	if self.PushCard then
		local ok, err = pcall(self.PushCard, self, info)
		if not ok then geterrorhandler()(err) end
	end
	if self.callbacks then self.callbacks:Fire("RareSpotted", info) end
	if self.RefreshDataText then self:RefreshDataText() end
	if self.RefillTargetButton and info.npc then self:RefillTargetButton() end
end

function M:MarkDead(key)
	local entry = self.session[key]
	if not entry or entry.dead then return end
	entry.dead = true
	if self.CardDead then self:CardDead(key) end
	if self.RefreshHistory then self:RefreshHistory() end
	if self.callbacks then self.callbacks:Fire("RareDead", key) end
end

---------------------------------------------------------------------------
-- Already done: the marker's own completion quest, read from the game.
-- True when this character has it, nil when the game names none (0),
-- hides it (secret) or the call is missing.
---------------------------------------------------------------------------
function M:DoneFlag(questID)
	if type(questID) ~= "number" or Secret(questID) or questID <= 0 then return nil end
	local log = C_QuestLog
	if not (log and log.IsQuestFlaggedCompleted) then return nil end
	local done = Read(log.IsQuestFlaggedCompleted, questID)
	if done == true then return true end
	return nil
end

---------------------------------------------------------------------------
-- Sources
---------------------------------------------------------------------------
-- Vignettes: the game's minimap markers. The kill atlases (VignetteKill,
-- VignetteKillElite, vignettekillboss; Forever spells some in lower case)
-- mark rares; the loot and event atlases (VignetteLoot*, VignetteEvent*)
-- and the Treasure marker type mark treasures and events.
local function KillAtlas(atlas)
	if type(atlas) ~= "string" or Secret(atlas) then return nil end
	local lower = atlas:lower()
	if not lower:find("vignettekill", 1, true) then return nil end
	if lower:find("boss", 1, true) then return "worldboss" end
	if lower:find("elite", 1, true) then return "rareelite" end
	return "rare"
end
M.KillAtlas = KillAtlas

-- "treasure", "event" or nil for a marker that is not a creature.
local function MarkerKind(vinfo)
	local atlas = vinfo.atlasName
	if type(atlas) == "string" and not Secret(atlas) then
		local lower = atlas:lower()
		if lower:find("vignetteloot", 1, true) then return "treasure" end
		if lower:find("vignetteevent", 1, true) then return "event" end
	end
	local kind, types = vinfo.type, Enum and Enum.VignetteType
	if types and types.Treasure and type(kind) == "number" and not Secret(kind) and kind == types.Treasure then return "treasure" end
end
M.MarkerKind = MarkerKind

-- The switch for each marker kind.
M.KIND_SWITCH = { treasure = "treasures", event = "events" }

-- A treasure or event: a minimap marker with no creature to target.
function M.IsMarker(info)
	return type(info) == "table" and M.KIND_SWITCH[info.kind] ~= nil
end

-- A treasure or event is known by its kind, name, map and spot (rounded
-- to 0.1 % of the map), so two chests of the same name in two places each
-- alert once.
local function MarkerKey(kind, name, uiMapID, x, y)
	local lower = Lower(name)
	if not lower then return nil end
	local key = ("%s:%s:%d"):format(kind, lower, tonumber(uiMapID) or 0)
	if type(x) == "number" and type(y) == "number" then
		key = key .. (":%d:%d"):format(math.floor(x * 1000 + 0.5), math.floor(y * 1000 + 0.5))
	end
	return key
end
M.MarkerKey = MarkerKey

-- The marker's readable position on one map, or nil.
local function VignettePosition(api, guid, uiMapID)
	if Secret(uiMapID) or type(uiMapID) ~= "number" or not api.GetVignettePosition then return nil end
	local okPos, pos = pcall(api.GetVignettePosition, guid, uiMapID)
	if okPos and not Secret(pos) and type(pos) == "table" and (not canaccesstable or canaccesstable(pos)) then
		local px, py = pos.x, pos.y
		if not Secret(px) and not Secret(py) and type(px) == "number" and type(py) == "number"
			and px >= 0 and px <= 1 and py >= 0 and py <= 1 then return px, py end
	end
end

function M:CheckVignette(guid)
	if not self.db.sources.vignette or type(guid) ~= "string" or Secret(guid) then return end
	local api = C_VignetteInfo
	if not (api and api.GetVignetteInfo) then return end
	local ok, vinfo = pcall(api.GetVignetteInfo, guid)
	if not ok or Secret(vinfo) or type(vinfo) ~= "table" or (canaccesstable and not canaccesstable(vinfo)) then return end
	if Secret(vinfo.onMinimap) or vinfo.onMinimap == false then return end
	local class = KillAtlas(vinfo.atlasName)
	local kind = class and "rare" or MarkerKind(vinfo)
	if not kind then return end
	if kind ~= "rare" and not self.db[M.KIND_SWITCH[kind]] then return end
	local dead = kind == "rare" and not Secret(vinfo.isDead) and vinfo.isDead == true
	local seen = vignettesSeen[guid]
	if seen then
		if dead then self:MarkDead(seen) end
		return
	end
	local npc = kind == "rare" and NpcFromGUID(vinfo.objectGUID) or nil
	local name = vinfo.name
	if Secret(name) or type(name) ~= "string" or name == "" then name = nil end
	local zone, uiMapID = PlayerZone()
	local x, y = VignettePosition(api, guid, uiMapID)
	if not x and not Secret(uiMapID) and type(uiMapID) == "number" and C_Map and C_Map.GetMapInfo then
		local info = Read(C_Map.GetMapInfo, uiMapID)
		local parent
		if not Secret(info) and type(info) == "table" and (not canaccesstable or canaccesstable(info)) then
			parent = info.parentMapID
		end
		if not Secret(parent) and type(parent) == "number" and parent > 0 and parent ~= uiMapID then
			x, y = VignettePosition(api, guid, parent)
			if x then uiMapID = parent end
		end
	end
	local key
	if kind == "rare" then
		key = KeyFor(npc, name or (npc and self:NameOf(npc)))
	else
		key = name and MarkerKey(kind, name, uiMapID, x, y)
	end
	if not key then return end
	vignettesSeen[guid] = key
	if class == "worldboss" and npc then class = self:DataClassification(npc) or class end
	self:Spotted({ npc = npc, name = name, kind = kind, classification = class, source = "vignette", dead = dead and true or nil,
		zone = zone, uiMapID = uiMapID, x = x, y = y, markerKey = kind ~= "rare" and key or nil,
		done = self:DoneFlag(vinfo.rewardQuestID) })
end

-- All vignettes now (VIGNETTES_UPDATED); forgets the ones that are gone.
function M:ScanVignettes()
	local api = C_VignetteInfo
	if not (api and api.GetVignettes) then return end
	local ok, list = pcall(api.GetVignettes)
	if not ok or type(list) ~= "table" or Secret(list) then return end
	local present = {}
	for _, guid in ipairs(list) do
		if type(guid) == "string" and not Secret(guid) then
			present[guid] = true
			self:CheckVignette(guid)
		end
	end
	for guid in pairs(vignettesSeen) do
		if not present[guid] then vignettesSeen[guid] = nil end
	end
end

-- The game sends VIGNETTES_UPDATED in bursts (many in one second while
-- the map fills): one scan a short moment after the first of a burst
-- reads them all once.
local scanQueued = false
function M:QueueVignetteScan()
	if scanQueued then return end
	scanQueued = true
	C_Timer.After(0.25, function()
		scanQueued = false
		if not M:Paused() and M.db.sources.vignette then M:ScanVignettes() end
	end)
end

-- The game's rare test for a unit it shows (nameplate, target, mouseover,
-- a group member's target): { npc, name, classification, level, dead }, or
-- nil for a hidden identity, a player's unit, a secret value or a creature
-- that is neither rare nor accepted by watched(name). Map Notes' "Rares
-- you've met" uses the same test.
function M:ReadRareUnit(unit, watched)
	if type(unit) ~= "string" or Secret(unit) then return nil end
	if IdentitySecret(unit) then return nil end
	if not Read(UnitExists, unit) then return nil end
	local controlled = Read(UnitPlayerControlled, unit)
	if controlled or type(controlled) == "nil" then return nil end
	local name = Read(UnitName, unit)
	if type(name) ~= "string" or name == "" then return nil end
	local class = Read(UnitClassification, unit)
	local rare = class == "rare" or class == "rareelite" or class == "worldboss"
	local isWatched = watched and watched(name)
	if not rare and not isWatched then return nil end
	-- A boss-rank NPC the player cannot attack (a city leader) is no rare
	-- to hunt. A secret or missing answer keeps the unit.
	if not isWatched and Read(UnitCanAttack, "player", unit) == false then return nil end
	local npc = NpcFromGUID(Read(UnitGUID, unit))
	local level = Read(UnitLevel, unit)
	if type(level) ~= "number" or level <= 0 then level = nil end
	local dead = Read(UnitIsDead, unit)
	return { npc = npc, name = name, classification = rare and class or nil, level = level, dead = dead and true or nil }
end

local function WatchedName(name) return M:Watched(name) end

-- A unit the game shows: nameplate, target, mouseover, a group member's target.
function M:CheckUnit(unit, source)
	if type(unit) ~= "string" or Secret(unit) or self:Paused() then return end
	local info = self:ReadRareUnit(unit, WatchedName)
	if not info then return end
	if info.classification == "worldboss" and not self.db.worldBosses and not self:Watched(info.name) then return end
	if info.npc then self.names[info.npc] = info.name end
	info.source, info.unit = source, unit
	self:Spotted(info)
end

-- Monster yells and emotes: only a sender we know as a rare.
function M:CheckChat(text, sender)
	if not self.db.sources.chat or Secret(text) or Secret(sender) or type(sender) ~= "string" or sender == "" then return end
	if self:Paused() then return end
	local npc = self:NpcByName(sender)
	if not npc and not self:Watched(sender) then return end
	self:Spotted({ npc = npc, name = sender, source = "chat" })
end

function M:UnitDied(guid)
	local npc = NpcFromGUID(guid)
	if not npc then return end
	self:MarkDead("npc:" .. npc)
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local CHAT_EVENTS = { "CHAT_MSG_MONSTER_YELL", "CHAT_MSG_MONSTER_EMOTE", "CHAT_MSG_MONSTER_SAY", "CHAT_MSG_MONSTER_WHISPER" }
M.registered = {}

-- checked: ask the client first (the vignette events, which a client
-- without vignettes lacks); the rest are core events every client has.
local function Listen(self, event, handler, checked)
	if checked and not EventValid(event) then return end
	local ok = pcall(self.RegisterEvent, self, event, handler)
	if ok then self.registered[event] = true end
end

function M:RegisterSources()
	local sources = self.db.sources
	if C_VignetteInfo then
		Listen(self, "VIGNETTE_MINIMAP_UPDATED", function(_, _, guid, onMinimap)
			if onMinimap and not M:Paused() then M:CheckVignette(guid) end
		end, true)
		Listen(self, "VIGNETTES_UPDATED", function() M:QueueVignetteScan() end, true)
	end
	Listen(self, "NAME_PLATE_UNIT_ADDED", function(_, _, unit) if M.db.sources.nameplate then M:CheckUnit(unit, "nameplate") end end)
	Listen(self, "PLAYER_TARGET_CHANGED", function() if M.db.sources.target then M:CheckUnit("target", "target") end end)
	Listen(self, "UPDATE_MOUSEOVER_UNIT", function() if M.db.sources.target then M:CheckUnit("mouseover", "mouseover") end end)
	Listen(self, "UNIT_TARGET", function(_, _, unit)
		if not M.db.sources.group or type(unit) ~= "string" or Secret(unit) then return end
		if unit:match("^party[1-4]$") then M:CheckUnit(unit .. "target", "group") end
	end)
	for _, event in ipairs(CHAT_EVENTS) do
		Listen(self, event, function(_, _, text, sender) M:CheckChat(text, sender) end)
	end
	Listen(self, "UNIT_DIED", function(_, _, guid) M:UnitDied(guid) end)
	Listen(self, "PLAYER_ENTERING_WORLD", function()
		wipe(vignettesSeen)
		if M.RefillTargetButton then M:RefillTargetButton() end
	end)
	Listen(self, "ZONE_CHANGED_NEW_AREA", function()
		if M.RefillTargetButton then M:RefillTargetButton() end
	end)
	return sources
end

function M:UnregisterSources()
	for event in pairs(self.registered) do self:UnregisterEvent(event) end
	wipe(self.registered)
end

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------
function M:Normalize()
	local db = self.db
	if type(db.sources) ~= "table" then db.sources = {} end
	for key, value in pairs(self.defaults.sources) do
		if type(db.sources[key]) ~= "boolean" then db.sources[key] = value end
	end
	if type(db.ignore) ~= "table" then db.ignore = {} end
	if type(db.watch) ~= "string" then db.watch = "" end
	if type(db.quietKinds) ~= "table" then db.quietKinds = {} end
	for key, value in pairs(self.defaults.quietKinds) do
		if type(db.quietKinds[key]) ~= "boolean" then db.quietKinds[key] = value end
	end
	if type(db.quietZones) ~= "table" then db.quietZones = {} end
	if db.quietMode ~= "card" and db.quietMode ~= "nothing" then db.quietMode = "card" end
	if db.shareTo ~= "group" and db.shareTo ~= "party" and db.shareTo ~= "raid" and db.shareTo ~= "say" then db.shareTo = "group" end
	db.stackSize = math.max(1, math.min(4, math.floor(tonumber(db.stackSize) or 1)))
	db.marker = math.max(1, math.min(8, math.floor(tonumber(db.marker) or 8)))
	self.watchCache = nil
end

function M:OnInitialize()
	self:Normalize()
end

function M:OnEnable()
	self:Normalize()
	self:RegisterSources()
	if self.EnableCards then self:EnableCards() end
	if self.EnableTargetButton then self:EnableTargetButton() end
	if self.ApplyHistory then self:ApplyHistory() end
	if self.RefreshDataText then self:RefreshDataText() end
end

function M:OnDisable()
	self:UnregisterSources()
	if self.DisableCards then self:DisableCards() end
	if self.DisableTargetButton then self:DisableTargetButton() end
	if self.ApplyHistory then self:ApplyHistory() end
	wipe(vignettesSeen)
	if self.RefreshDataText then self:RefreshDataText() end
end

function M:OnProfileChanged()
	self:Normalize()
	if not self.active then return end
	if self.ApplyCards then self:ApplyCards() end
	if self.RefillTargetButton then self:RefillTargetButton() end
	if self.ApplyHistory then self:ApplyHistory() end
end

-- A sample sighting: the card and the notice with the current settings.
-- Not added to the session list and not sent to plugins or Fanfare.
function M:Test()
	if not self.active then
		E:Print(E:ModuleOffHint("RareScanner"))
		return false
	end
	local zone, uiMapID = PlayerZone()
	local npc
	local LD = self:Data()
	if type(LD) == "table" and type(LD.rares) == "table" then npc = LD.rares[1] end
	local info = {
		key = "test", test = true, npc = npc, name = (npc and self:NameOf(npc)) or L["Sample rare"],
		classification = (npc and self:DataClassification(npc)) or "rareelite", source = "test",
		zone = zone or L["Unknown zone"], uiMapID = uiMapID, x = 0.452, y = 0.338,
	}
	local mob = npc and self:Record(npc)
	info.level = mob and mob.maxLevel or 60
	info.notable, info.notableItems = self:Notable(npc)
	if self.Notify then self:Notify(info) end
	if self.PushCard then self:PushCard(info) end
	return true
end
