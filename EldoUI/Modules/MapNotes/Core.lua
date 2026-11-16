-- EldoUI Map Notes: rares and your own notes on the world map and the
-- minimap, and one switch on the map screen that shows or hides every EldoUI
-- pin (Core/MapPins.lua).
--
-- WoW: Forever's own rares and treasures come from HandyNotes when it is
-- installed (design decision): the map button then switches it too
-- (Bridge.lua).
--
-- Groups (each one a tick in the map button's menu):
--   user          your own notes (Alt+right-click on the map, Editor.lua)
--   classicRares  rares from the Loot Guide's data (EldoUI_LootData), Classic
--                 zones; shown while that data is loaded
--   metRares      rares you targeted or pointed at outdoors, where you stood
--                 (Met.lua)
--   pack:<id>     note packs other addons register (below)
--   waypoints, gathering, entrances, handynotes: other modules' pins, which
--                 the switch shows or hides (their own settings decide what
--                 they draw)
--
-- Map level (Core/MapPins.lua): zone and city maps show every group; a
-- continent or world map shows only the groups ticked under "Also on
-- continent maps" (continentGroups). City services never show there.
--
-- Note packs (plugins):
--   local MN = EldoUI:GetModule("MapNotes")
--   MN:RegisterPack("MyPack", {
--     title = "Elwynn treasures", kind = "treasure",   -- rare | treasure | note | service
--     maps = { [1429] = { { x = 0.45, y = 0.67, label = "Old chest", quest = 123,
--                           loot = { 2589 }, note = "Behind the mill", icon = nil } } },
--     -- or points = function(uiMapID) return { ... } end
--     -- a point may also carry key (a stable id for "Hide this point"),
--     -- icon = { atlas, texture } and service (the tooltip's second line)
--     continent = true,  -- also on continent maps by default (default: zone
--                        -- maps only); "never" keeps the pack off them
--   })
--   MN:UnregisterPack("MyPack"); MN:RefreshPack("MyPack")
--
-- Rules: static places plus the player's own progress (quest flags,
-- collections) and position. Nothing is targeted, sent or clicked for the
-- player; a waypoint or chat link needs the player's own click, and a chat
-- link waits in the chat box for Enter.
local _, E = ...
local L = E.L

local issecret = issecretvalue or function() return false end
local floor = math.floor

local M = E:NewModule("MapNotes", {
	title = "Map Notes",
	category = "Quality of Life",
	desc = "Rares and your own notes on the world map and minimap, with a button on the map that shows or hides every EldoUI pin at once.",
	frames = { "EldoUI_MapNotesButton" },
	movers = {},
	blizzard = {},
	savedKeys = { "profile.modules.MapNotes", "global.MapNotes", "private.MapNotes" },
	optionsPage = "module:MapNotes",
	presets = { "Dots", "Game", "Hunter", "Large", "Loot", "MapOnly", "Standard" },
	reload = false,
	defaults = {
		shown = true,             -- the one switch: every EldoUI pin
		worldPins = true,
		minimapPins = true,
		minimapEdge = false,      -- far notes on the minimap's edge
		groups = {                -- false hides a group (Core/MapPins.lua)
			user = true, classicRares = true, metRares = true,
			waypoints = true, gathering = true, entrances = true, handynotes = true,
		},
		hideDone = true,
		metRares = true,          -- remember rares you target outdoors (Met.lua)
		continentPins = true,     -- your notes on continent maps too
		continentGroups = {       -- groups on continent and world maps (Core/MapPins.lua)
			transport = true, entrances = true, waypoints = false, gathering = false, classicRares = false,
			metRares = false, ["pack:journal"] = false, zonequests = false, attunements = false,
		},
		pinScale = 1,
		pinAlpha = 1,
		minimapScale = 0.85,
		iconStyle = "art",        -- art | game | dots | icons
		mapButton = true,
		filterMenu = true,
		altClick = true,
		tooltipLoot = true,
		tooltipKnown = true,
		handyNotesBridge = true,  -- HandyNotes follows the switch
	},
})
E.MapNotes = M

-- While HandyNotes is loaded, its Alt+right-click wins (same gesture).
E:RegisterFeatureConflicts("mapnotes", { "HandyNotes" })

---------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------
local function Try(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a, b, c, d = pcall(fn, ...)
	if ok then return a, b, c, d end
end
M.Try = Try

local Clean = E.Plain
M.Clean = Clean

function M.MapName(uiMapID)
	local info = uiMapID and C_Map and C_Map.GetMapInfo and Try(C_Map.GetMapInfo, uiMapID)
	local name = type(info) == "table" and Clean(info.name)
	return (type(name) == "string" and name ~= "") and name or ("#" .. tostring(uiMapID))
end

function M.FormatCoords(x, y)
	return ("%.1f, %.1f"):format((x or 0) * 100, (y or 0) * 100)
end

function M.AccentHex()
	local c = E.media.accentText
	return ("|cff%02x%02x%02x"):format(c[1] * 255, c[2] * 255, c[3] * 255)
end

local function LootGuide()
	local LG = E:GetModule("LootGuide")
	if LG and LG.active and LG.HasData and LG:HasData() then return LG end
end
M.LootGuide = LootGuide

---------------------------------------------------------------------------
-- Saved data
--   E.global.MapNotes.notes[uiMapID][id] = { x, y, t = title, d = note,
--     i = icon index, c = show on the continent map }   (account-wide)
--   E.private.MapNotes.hidden[key] = true               (per character)
---------------------------------------------------------------------------
local MAX_HIDDEN = 2000

function M:Notes()
	local store = E:GetGlobal("MapNotes") or { notes = {}, nextId = 1 }
	if type(store.notes) ~= "table" then store.notes = {} end
	return store
end

function M:Hidden()
	local store = E:GetPrivate("MapNotes") or { hidden = {} }
	if type(store.hidden) ~= "table" then store.hidden = {} end
	return store.hidden
end

function M:HiddenCount()
	local n = 0
	for _ in pairs(self:Hidden()) do n = n + 1 end
	return n
end

function M:HidePoint(key)
	if not key then return end
	local hidden = self:Hidden()
	if not hidden[key] and self:HiddenCount() >= MAX_HIDDEN then
		E:Print(L["Map Notes: too many hidden points. Use \"Show hidden points again\" first."])
		return
	end
	hidden[key] = true
	self:Refresh()
end

function M:ResetHidden()
	wipe(self:Hidden())
	self:Refresh()
end

-- Icons for your own notes: the eight raid markers, then map icons (an
-- atlas when the client has it, else a plain icon).
M.NOTE_ICONS = {
	{ texture = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1" },
	{ texture = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_2" },
	{ texture = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_3" },
	{ texture = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_4" },
	{ texture = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_5" },
	{ texture = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_6" },
	{ texture = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_7" },
	{ texture = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8" },
	{ atlas = "Innkeeper", texture = "Interface\\Icons\\INV_Misc_Rune_01" },
	{ atlas = "Banker", texture = "Interface\\Icons\\INV_Misc_Bag_10_Blue" },
	{ atlas = "Mailbox", texture = "Interface\\Icons\\INV_Letter_15" },
	{ atlas = "Repair", texture = "Interface\\Icons\\Trade_BlackSmithing" },
	{ atlas = "TaxiNode_Neutral", texture = "Interface\\Icons\\Ability_Mount_Gryphon_01" },
	{ atlas = "Profession", texture = "Interface\\Icons\\INV_Misc_Note_01" },
	{ atlas = "Food", texture = "Interface\\Icons\\INV_Misc_Food_15" },
	{ atlas = "VignetteLoot", texture = "Interface\\Icons\\INV_Box_02" },
}

function M:AddNote(uiMapID, x, y, fields)
	if type(uiMapID) ~= "number" or type(x) ~= "number" or type(y) ~= "number" then return end
	if x < 0 or x > 1 or y < 0 or y > 1 then return end
	fields = fields or {}
	local store = self:Notes()
	local id = tonumber(store.nextId) or 1
	store.nextId = id + 1
	store.notes[uiMapID] = store.notes[uiMapID] or {}
	store.notes[uiMapID][id] = {
		x = x, y = y,
		t = type(fields.t) == "string" and fields.t ~= "" and fields.t or nil,
		d = type(fields.d) == "string" and fields.d ~= "" and fields.d or nil,
		i = tonumber(fields.i) or 1,
		c = fields.c and true or nil,
	}
	self:Refresh()
	return id
end

function M:GetNote(uiMapID, id)
	local list = self:Notes().notes[uiMapID]
	return list and list[id]
end

function M:UpdateNote(uiMapID, id, fields)
	local note = self:GetNote(uiMapID, id)
	if not note then return end
	note.t = type(fields.t) == "string" and fields.t ~= "" and fields.t or nil
	note.d = type(fields.d) == "string" and fields.d ~= "" and fields.d or nil
	note.i = tonumber(fields.i) or note.i or 1
	note.c = fields.c and true or nil
	self:Refresh()
	return true
end

local lastDeleted
function M:DeleteNote(uiMapID, id)
	local list = self:Notes().notes[uiMapID]
	local note = list and list[id]
	if not note then return end
	list[id] = nil
	if not next(list) then self:Notes().notes[uiMapID] = nil end
	lastDeleted = { uiMapID = uiMapID, note = note }
	E:Print(L["Map note deleted. /eui mapnote undo brings it back."])
	self:Refresh()
end

function M:UndoDelete()
	if not lastDeleted then E:Print(L["Nothing to bring back."]) return end
	local note = lastDeleted.note
	self:AddNote(lastDeleted.uiMapID, note.x, note.y, note)
	lastDeleted = nil
	E:Print(L["Map note restored."])
end

---------------------------------------------------------------------------
-- Note packs (plugins)
---------------------------------------------------------------------------
M.packs, M.packOrder = {}, {}

function M:RegisterPack(id, def)
	if type(id) ~= "string" or type(def) ~= "table" then return end
	if not self.packs[id] then self.packOrder[#self.packOrder + 1] = id end
	def.id = id
	def.title = type(def.title) == "string" and def.title or id
	self.packs[id] = def
	local group = "pack:" .. id
	E:RegisterMapPinLayer(group, {
		title = def.title, order = 30,
		continent = def.continent == "never" and "never" or def.continent == true,
		available = function() return M.active and M.packs[id] ~= nil end,
		count = function(uiMapID) return M:CountGroup(group, uiMapID) end,
	})
	self:Refresh()
	return def
end

function M:UnregisterPack(id)
	if not self.packs[id] then return end
	self.packs[id] = nil
	for i, other in ipairs(self.packOrder) do
		if other == id then table.remove(self.packOrder, i) break end
	end
	self:Refresh()
end

function M:RefreshPack()
	self:Refresh()
end

local warnedPack = {}
local function PackPoints(pack, uiMapID)
	local list
	if type(pack.points) == "function" then
		local ok, result = pcall(pack.points, uiMapID)
		if ok then list = result elseif not warnedPack[pack.id] then
			warnedPack[pack.id] = true
			if E.errors and E.errors.Add then E.errors:Add("warning", ("Map Notes pack %s: %s"):format(pack.id, tostring(result))) end
		end
	elseif type(pack.maps) == "table" then
		list = pack.maps[uiMapID]
	end
	return type(list) == "table" and list or nil
end

---------------------------------------------------------------------------
-- Points: one table shape for every group
--   { key, group, kind = "rare" | "treasure" | "note", uiMapID, x, y, title,
--     level, elite, worldBoss, npc, quest, loot = { { itemID, chance }, ... }, note,
--     icon = { atlas, texture }, source, noteID }
---------------------------------------------------------------------------
local classicCache = {}  -- uiMapID -> points (rebuilt when the Loot Guide's data changes)

local function ClassicPoints(uiMapID)
	local LG = LootGuide()
	if not (LG and LG.WorldZones and LG.SpawnPoints and LG.MapPosition) then return nil end
	-- Without its data the Loot Guide would build (and keep) an empty zone index.
	if not (LG.HasData and LG:HasData()) then return nil end
	local cached = classicCache[uiMapID]
	if cached then return cached end
	local list = {}
	local ok, index = pcall(LG.WorldZones, LG)
	local zone = ok and type(index) == "table" and index.zones and index.zones[uiMapID]
	for _, npc in ipairs(zone and zone.rares or {}) do
		local mob = LG:Mob(npc)
		if mob then
			local loot = {}
			if LG.MobLoot then
				for _, row in ipairs(LG:MobLoot(npc)) do
					if row.itemID and not row.questOnly then loot[#loot + 1] = { itemID = row.itemID, chance = row.chance } end
				end
			end
			local camps = LG:SpawnPoints("npc", npc)
			for camp = 1, math.min(#camps, 3) do
				local mapID, x, y = LG:MapPosition(camps[camp])
				if mapID == uiMapID and x then
					list[#list + 1] = {
						key = ("c:%d:%d"):format(npc, camp), group = "classicRares", kind = "rare",
						uiMapID = uiMapID, x = x, y = y, title = mob.name, npc = npc,
						level = mob.maxLevel, minLevel = mob.minLevel,
						-- cmangos ranks: 1 elite, 2 rare elite, 3 boss, 4 rare
						elite = mob.rank == 1 or mob.rank == 2 or mob.rank == 3,
						worldBoss = mob.rank == 3 or nil,
						loot = loot, source = "classic",
					}
				end
			end
		end
	end
	classicCache[uiMapID] = list
	return list
end

function M:ClearClassicCache()
	wipe(classicCache)
	if M.ClearServiceCache then M:ClearServiceCache() end -- City services (Services.lua)
end

local function UserPoints(uiMapID, out, onContinent, rect)
	local list = M:Notes().notes[uiMapID]
	if type(list) ~= "table" then return end
	for id, note in pairs(list) do
		if type(note) == "table" and type(note.x) == "number" and type(note.y) == "number" and (not onContinent or note.c) then
			local x, y = note.x, note.y
			if rect then x, y = rect.minX + x * (rect.maxX - rect.minX), rect.minY + y * (rect.maxY - rect.minY) end
			out[#out + 1] = {
				key = ("u:%d:%d"):format(uiMapID, id), group = "user", kind = "note",
				uiMapID = uiMapID, x = x, y = y, zoneX = note.x, zoneY = note.y,
				title = note.t, note = note.d, icon = M.NOTE_ICONS[note.i or 1] or M.NOTE_ICONS[1],
				noteID = id, source = "user",
			}
		end
	end
end

local function AddPackPoints(uiMapID, out)
	for _, id in ipairs(M.packOrder) do
		local pack = M.packs[id]
		local list = pack and PackPoints(pack, uiMapID)
		for index, p in ipairs(list or {}) do
			if type(p) == "table" and type(p.x) == "number" and type(p.y) == "number" then
				local key = (type(p.key) == "string" or type(p.key) == "number") and ("p:%s:%s"):format(id, tostring(p.key))
					or ("p:%s:%d:%d"):format(id, uiMapID, index)
				local icon = p.icon
				if type(icon) == "table" then
					icon = { atlas = icon.atlas, texture = icon.texture }
				elseif icon then
					icon = { atlas = type(icon) == "string" and icon or nil, texture = icon }
				elseif type(pack.icon) == "table" then
					icon = { atlas = pack.icon.atlas, texture = pack.icon.texture }
				elseif pack.icon then
					icon = { atlas = pack.icon, texture = pack.icon }
				end
				out[#out + 1] = {
					key = key, group = "pack:" .. id,
					kind = p.kind or pack.kind or "treasure", uiMapID = uiMapID, x = p.x, y = p.y,
					title = type(p.label) == "string" and not issecret(p.label) and p.label or nil,
					npc = tonumber(p.npc), quest = tonumber(p.quest), loot = (function()
						local loot = {}
						for _, item in ipairs(type(p.loot) == "table" and p.loot or {}) do
							local itemID = tonumber(type(item) == "table" and item.itemID or item)
							if itemID then loot[#loot + 1] = { itemID = itemID } end
						end
						return loot
					end)(),
					note = type(p.note) == "string" and p.note or nil,
					icon = icon, source = pack.title,
					service = type(p.service) == "string" and not issecret(p.service) and p.service or nil,
				}
			end
		end
	end
end

-- Zone rectangle of a child map on a parent map (continent pins).
local function ChildRect(child, parent)
	if not (C_Map and C_Map.GetMapRectOnMap) then return end
	local minX, maxX, minY, maxY = Try(C_Map.GetMapRectOnMap, child, parent)
	minX, maxX, minY, maxY = Clean(minX), Clean(maxX), Clean(minY), Clean(maxY)
	if not (minX and maxX and minY and maxY) or maxX <= minX or maxY <= minY then return end
	return { minX = minX, maxX = maxX, minY = minY, maxY = maxY }
end

local function IsContinent(uiMapID)
	local info = C_Map and C_Map.GetMapInfo and Try(C_Map.GetMapInfo, uiMapID)
	local kind = type(info) == "table" and Clean(info.mapType)
	local continentType = Enum and Enum.UIMapType and Enum.UIMapType.Continent or 2
	return kind == continentType
end

-- Every point on a map, before the visibility rules.
function M:AllPoints(uiMapID)
	local out = {}
	if type(uiMapID) ~= "number" then return out end
	UserPoints(uiMapID, out)
	for _, p in ipairs(ClassicPoints(uiMapID) or {}) do out[#out + 1] = p end
	if self.MetPoints then self:MetPoints(uiMapID, out) end
	AddPackPoints(uiMapID, out)
	if self.db.continentPins and IsContinent(uiMapID) and C_Map.GetMapChildrenInfo then
		local zoneType = Enum and Enum.UIMapType and Enum.UIMapType.Zone or 3
		local children = Try(C_Map.GetMapChildrenInfo, uiMapID, zoneType)
		for _, child in ipairs(type(children) == "table" and children or {}) do
			local childID = Clean(child.mapID)
			local rect = childID and ChildRect(childID, uiMapID)
			if rect then UserPoints(childID, out, true, rect) end
		end
	end
	return out
end

---------------------------------------------------------------------------
-- Loot and progress
---------------------------------------------------------------------------
-- kind, known for an item: "mount", "pet", "toy", "appearance" or nil.
-- Cached until something is collected (the events below wipe it).
local statusCache = {}
local NONE = {}

local function ReadItemStatus(itemID)
	local journal = C_MountJournal
	if journal and journal.GetMountFromItem then
		local mountID = Clean(Try(journal.GetMountFromItem, itemID))
		if mountID and journal.GetMountInfoByID then
			local ok, _, _, _, _, _, _, _, _, _, _, collected = pcall(journal.GetMountInfoByID, mountID)
			if not ok then collected = nil end
			if not issecret(collected) and type(collected) ~= "nil" then return "mount", collected and true or false end
		end
	end
	local pets = C_PetJournal
	if pets and pets.GetPetInfoByItemID then
		local ok, _, _, _, _, _, _, _, _, _, _, _, _, speciesID = pcall(pets.GetPetInfoByItemID, itemID)
		speciesID = ok and Clean(speciesID)
		if speciesID and pets.GetNumCollectedInfo then
			local owned = Clean(Try(pets.GetNumCollectedInfo, speciesID))
			if type(owned) == "number" then return "pet", owned > 0 end
		end
	end
	if C_ToyBox and C_ToyBox.GetToyInfo and Clean(Try(C_ToyBox.GetToyInfo, itemID)) then
		local has = Clean(Try(rawget(_G, "PlayerHasToy"), itemID))
		if has ~= nil then return "toy", has and true or false end
	end
	local transmog = C_TransmogCollection
	if transmog and transmog.PlayerHasTransmog and C_Item and C_Item.IsEquippableItem and Clean(Try(C_Item.IsEquippableItem, itemID)) then
		local has = Clean(Try(transmog.PlayerHasTransmog, itemID))
		if has ~= nil then return "appearance", has and true or false end
	end
end

function M.ItemStatus(itemID)
	itemID = tonumber(itemID)
	if not itemID then return end
	local cached = statusCache[itemID]
	if not cached then
		local kind, known = ReadItemStatus(itemID)
		cached = kind and { kind, known } or NONE
		statusCache[itemID] = cached
	end
	return cached[1], cached[2]
end

function M:ClearStatusCache()
	wipe(statusCache)
end

local function QuestDone(questID)
	if not (questID and C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted) then return false end
	local done = Clean(Try(C_QuestLog.IsQuestFlaggedCompleted, questID))
	return done and true or false
end
M.QuestDone = QuestDone

-- Done: its quest is flagged complete, or it drops a mount, pet or toy and
-- you have all of those. A point with neither is never done.
function M:IsDone(point)
	if point.kind == "note" then return false end
	if point.quest and QuestDone(point.quest) then return true end
	local collectible, missing = 0, 0
	for _, row in ipairs(point.loot or {}) do
		local kind, known = M.ItemStatus(row.itemID)
		if kind == "mount" or kind == "pet" or kind == "toy" then
			collectible = collectible + 1
			if not known then missing = missing + 1 end
		end
	end
	return collectible > 0 and missing == 0
end

-- Should this point be drawn? where = "world" | "minimap"; uiMapID (the
-- map it is drawn on) adds the map level rule.
function M:Shows(point, where, uiMapID)
	if not E:MapPinGroupShown(point.group, where, uiMapID) then return false end
	if self:Hidden()[point.key] then return false end
	if self.db.hideDone and self:IsDone(point) then return false end
	return true
end

function M:Points(uiMapID, where)
	local out = {}
	-- On a continent or world map, the groups that stay on zone maps draw nothing.
	local wide = where ~= "minimap" and E:IsWideMap(uiMapID)
	local onWide = {}
	for _, point in ipairs(self:AllPoints(uiMapID)) do
		local group = point.group
		if wide and onWide[group] == nil then onWide[group] = E:MapPinGroupOnWideMaps(group) end
		if not (wide and not onWide[group]) and self:Shows(point, where) then out[#out + 1] = point end
	end
	return out
end

-- Points of a group on a map that would show (ignores the switch itself,
-- so the menu can count what comes back when you turn a group on).
function M:CountGroup(group, uiMapID)
	local n = 0
	for _, point in ipairs(self:AllPoints(uiMapID)) do
		if point.group == group and not self:Hidden()[point.key] and not (self.db.hideDone and self:IsDone(point)) then n = n + 1 end
	end
	return n
end

---------------------------------------------------------------------------
-- Pin layers for the switch and the menu
---------------------------------------------------------------------------
E:RegisterMapPinLayer("user", {
	title = "My notes", order = 10,
	-- On continent maps: the "My notes" tick there is continentPins.
	continentSetting = {
		get = function() return M.db and M.db.continentPins and true or false end,
		set = function(on) if M.db then M.db.continentPins = on and true or false end end,
	},
	available = function() return M.active end,
	count = function(uiMapID) return M:CountGroup("user", uiMapID) end,
	refresh = function() if M.active then M:RefreshPins() end end,
})
E:RegisterMapPinLayer("classicRares", {
	title = "Rares (Classic zones)", order = 20, continent = false,
	available = function() return M.active and LootGuide() ~= nil end,
	count = function(uiMapID) return M:CountGroup("classicRares", uiMapID) end,
})

---------------------------------------------------------------------------
-- Refresh (bucketed: many events in a row draw once)
---------------------------------------------------------------------------
local pending
function M:Refresh(delay)
	if not self.active then return end
	if pending then return end
	pending = true
	local function Run()
		pending = nil
		if M.active then E:RefreshAllMapPins() end
	end
	if C_Timer and C_Timer.After then C_Timer.After(delay or 0, Run) else Run() end
end

local events = CreateFrame("Frame")
local PROGRESS = {
	"QUEST_TURNED_IN", "LOOT_CLOSED", "NEW_MOUNT_ADDED", "NEW_PET_ADDED", "NEW_TOY_ADDED",
	"TRANSMOG_COLLECTION_UPDATED", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD",
}
events:SetScript("OnEvent", function(_, event, name)
	if not M.active then return end
	if event == "ADDON_LOADED" then
		if name == "HandyNotes" and M.ApplyBridge then M:ApplyBridge() end
		return
	end
	if event == "ZONE_CHANGED_NEW_AREA" or event == "PLAYER_ENTERING_WORLD" then
		M:Refresh()
	else
		M:ClearStatusCache()
		M:Refresh(1.5)
	end
end)

---------------------------------------------------------------------------
-- Commands
---------------------------------------------------------------------------
-- announce: say it in chat (the slash command and the key binding, where
-- nothing on screen shows the switch; the menu tick and the button do).
function M:Toggle(on, announce)
	if on == nil then on = not E:MapPinsShown() end
	E:SetMapPinsShown(on)
	if self.UpdateButton then self:UpdateButton() end
	if announce then E:Print(on and L["Map notes shown."] or L["Map notes hidden."]) end
end

function M:Command(input)
	input = tostring(input or ""):match("^%s*(.-)%s*$")
	local word, rest = input:match("^(%S*)%s*(.-)$")
	word = (word or ""):lower()
	if word == "" or word == "toggle" then return self:Toggle(nil, true) end
	if word == "on" or word == "show" then return self:Toggle(true, true) end
	if word == "off" or word == "hide" then return self:Toggle(false, true) end
	if word == "undo" then return self:UndoDelete() end
	if word == "hidden" then
		self:ResetHidden()
		E:Print(L["Hidden map points are shown again."])
		return
	end
	if word == "add" then
		local x, y, title = rest:match("^([%d%.]+)[%s,]+([%d%.]+)%s*(.*)$")
		local uiMapID = C_Map and C_Map.GetBestMapForUnit and Clean(Try(C_Map.GetBestMapForUnit, "player"))
		if not uiMapID then E:Print(L["Your position isn't known here."]) return end
		if x then
			x, y = tonumber(x), tonumber(y)
			if x > 1 or y > 1 then x, y = x / 100, y / 100 end
		else
			title = rest
			local pos = C_Map.GetPlayerMapPosition and Try(C_Map.GetPlayerMapPosition, uiMapID, "player")
			if type(pos) == "table" and pos.GetXY then x, y = pos:GetXY() end
			x, y = Clean(x), Clean(y)
		end
		if not (x and y) or x <= 0 or y <= 0 or x > 1 or y > 1 then E:Print(L["Your position isn't known here."]) return end
		if self.OpenEditor then
			self:OpenEditor(uiMapID, x, y, nil, title ~= "" and title or nil)
		else
			self:AddNote(uiMapID, x, y, { t = title })
		end
		return
	end
	E:Print(L["/eui mapnote: show or hide all map notes. Also: on, off, add [x y] [title], hidden (show hidden points again), undo."])
end

E:AddCommand("mapnote", "[on | off | add x y title | hidden | undo]  show or hide every EldoUI map pin, add a map note",
	function(arg)
		if M.active then M:Command(arg) else E:Print(E:ModuleOffHint("MapNotes")) end
	end)

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------
function M:OnInitialize()
	E:RegisterGlobal("MapNotes", { notes = {}, nextId = 1, met = {} }, { title = "Map notes", desc = "Your own notes on the world map, and the rares you've met." })
	E:RegisterPrivate("MapNotes", { hidden = {} })
	local LG = E:GetModule("LootGuide")
	if LG and LG.On then
		LG:On("mapnotes", function(changed)
			if changed.data then
				M:ClearClassicCache()
				M:Refresh()
			end
		end)
	end
end

function M:OnEnable()
	for _, event in ipairs(PROGRESS) do pcall(events.RegisterEvent, events, event) end
	pcall(events.RegisterEvent, events, "ADDON_LOADED")
	if self.EnablePins then self:EnablePins() end
	if self.EnableButton then self:EnableButton() end
	if self.EnableEditor then self:EnableEditor() end
	if self.EnableMet then self:EnableMet() end
	if self.ApplyBridge then self:ApplyBridge() end
	E:RefreshAllMapPins()
end

function M:OnDisable()
	events:UnregisterAllEvents()
	if self.DisableMet then self:DisableMet() end
	if self.DisablePins then self:DisablePins() end
	if self.DisableButton then self:DisableButton() end
	if self.ReleaseBridge then self:ReleaseBridge() end
	-- With Map Notes off every other module's pins show again.
	E:RefreshAllMapPins()
end

function M:OnProfileChanged()
	if not self.active then return end
	if self.StylePins then self:StylePins() end
	if self.UpdateButton then self:UpdateButton() end
	if self.ApplyBridge then self:ApplyBridge() end
	E:RefreshAllMapPins()
end

---------------------------------------------------------------------------
-- Options and styles
---------------------------------------------------------------------------
local function LayerAvailable(id)
	local layer = E:MapPinLayer(id)
	if not (layer and layer.available) then return false end
	local ok, available = pcall(layer.available)
	return ok and available and true or false
end

local function HandyNotesLoaded()
	return C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("HandyNotes") and true or false
end

M.options = {
	{ type = "description", label = L["The world map's top right button shows or hides EldoUI's pins: click for groups, Shift-click for all. Alt-right-click the map to add a note."] },
	{ type = "tab", label = L["Notes"] },
	{ type = "header", label = L["Show"] },
	{ type = "toggle", key = "shown", label = L["Show map notes"], desc = L["The one switch: off hides every EldoUI pin on the world map and the minimap. The map button, /eui mapnote and the key binding flip it too."] }, -- lint: unused-key ok (read by E:MapPinsShown in Core/MapPins.lua)
	{ type = "toggle", key = "worldPins", label = L["On the world map"], desc = L["Show the pins on the world map."], dependsOn = "shown" },
	{ type = "toggle", key = "minimapPins", label = L["On the minimap"], desc = L["Show the pins on the minimap too. Only outdoors: the game gives no position in dungeons and raids."], dependsOn = "shown" },
	{ type = "toggle", key = "minimapEdge", label = L["Far notes on the minimap's edge"], desc = L["Notes out of the minimap's range sit on its edge. Off hides them, so they don't pile up under the minimap's buttons."], dependsOn = "minimapPins" },
	{ type = "toggle", key = "hideDone", label = L["Hide completed"], desc = L["Hide a rare or treasure when its quest is done, or when it drops a mount, pet or toy and you have all of them. Points with neither, like most Classic rares, always show."] },
	{ type = "header", label = L["Groups"] },
	{ type = "toggle", key = "groups.user", label = L["My notes"], desc = L["Notes you added with Alt+right-click or /eui mapnote add."] },
	{ type = "toggle", key = "groups.classicRares", label = L["Rares (Classic zones)"], desc = L["Rare creatures from the Loot Guide's data, with their drops. Needs the Loot Guide and its data; values are Classic's, WoW: Forever may differ."] },
	{ type = "toggle", key = "groups.metRares", label = L["Rares you've met"], desc = L["Pins where you stood when you targeted or pointed at a rare creature outdoors. Kept for all your characters. Right-click a pin to forget it."] },
	{ type = "toggle", key = "metRares", label = L["Remember rares you meet"], desc = L["When you target or point at a rare creature outdoors, remember where you stood, its name and when. Nothing is kept in dungeons, raids, battlegrounds or arenas."] },
	{ type = "execute", confirm = true, label = L["Forget all rares you've met"], desc = L["Delete every remembered rare and its pin, for all your characters."], func = function() M:ForgetAllMet() end },
	{ type = "toggle", key = "groups.waypoints", label = L["Waypoints"], desc = L["Pins of the Waypoints module. Its own settings decide which waypoints exist."] },
	{ type = "toggle", key = "groups.gathering", label = L["Gathering nodes"], desc = L["Pins of the Gathering module. Its own settings decide which nodes it records."] },
	{ type = "toggle", key = "groups.entrances", label = L["Instance entrances"], desc = L["The Loot Guide's dungeon and raid entrance pins on the world map."] },
	{ type = "execute", label = L["Show hidden points again"], desc = L["Bring back every point you hid with \"Hide this point\" on this character."], func = function() M:ResetHidden() end },
	{ type = "header", label = L["Also on continent maps"] },
	{ type = "description", label = L["Zone and city maps show every group. Continent and world maps show only the groups checked here. City services stay on zone and city maps."] },
	{ type = "toggle", key = "continentPins", label = L["My notes"], desc = L["Your notes on Kalimdor and the Eastern Kingdoms: the ones you added there, and the zone notes with \"Show on the continent map\" checked."] },
	{ type = "toggle", key = "continentGroups.transport", label = L["Transport"], desc = L["Flight masters, boats, zeppelins, the tram and portals also show on continent maps. Needs Transport Maps."] }, -- lint: unused-key ok (read by E:MapPinGroupOnWideMaps in Core/MapPins.lua)
	{ type = "toggle", key = "continentGroups.entrances", label = L["Instance entrances"], desc = L["Dungeon and raid entrances also show on continent maps."] }, -- lint: unused-key ok (read by E:MapPinGroupOnWideMaps in Core/MapPins.lua)
	{ type = "toggle", key = "continentGroups.waypoints", label = L["Waypoints"], desc = L["Your waypoints also show on continent maps."] }, -- lint: unused-key ok (read by E:MapPinGroupOnWideMaps in Core/MapPins.lua)
	{ type = "toggle", key = "continentGroups.classicRares", label = L["Rares (Classic zones)"], desc = L["Rares from the Loot Guide's data also show on continent maps. There are a lot of them."] }, -- lint: unused-key ok (read by E:MapPinGroupOnWideMaps in Core/MapPins.lua)
	{ type = "toggle", key = "continentGroups.metRares", label = L["Rares you've met"], desc = L["The rares you've met also show on continent maps."] }, -- lint: unused-key ok (read by E:MapPinGroupOnWideMaps in Core/MapPins.lua)
	{ type = "toggle", key = "continentGroups.gathering", label = L["Gathering nodes"], desc = L["Gathering nodes also show on continent maps."] }, -- lint: unused-key ok (read by E:MapPinGroupOnWideMaps in Core/MapPins.lua)
	{ type = "toggle", key = "continentGroups.pack:journal", label = L["Journal notes"], desc = L["Your journal's notes also show on continent maps."], hidden = function() return not LayerAvailable("pack:journal") end }, -- lint: unused-key ok (read by E:MapPinGroupOnWideMaps in Core/MapPins.lua)
	{ type = "toggle", key = "continentGroups.zonequests", label = L["Quest givers"], desc = L["Quest givers also show on continent maps."], hidden = function() return not LayerAvailable("zonequests") end }, -- lint: unused-key ok (read by E:MapPinGroupOnWideMaps in Core/MapPins.lua)
	{ type = "toggle", key = "continentGroups.attunements", label = L["Attunements"], desc = L["Attunement steps also show on continent maps."], hidden = function() return not LayerAvailable("attunements") end }, -- lint: unused-key ok (read by E:MapPinGroupOnWideMaps in Core/MapPins.lua)
	{ type = "tab", label = L["Look"] },
	{ type = "header", label = L["Pins"] },
	{ type = "select", key = "iconStyle", label = L["Pin look"], desc = L["Art style follows EldoUI's art style. Game icons always use the game's map icons. Dots are small dots in the loot's quality color. Loot icons show the best drop."],
		values = { art = L["Art style"], game = L["Game icons"], dots = L["Dots"], icons = L["Loot icons"] } },
	{ type = "range", percent = true, key = "pinScale", label = L["Pin scale"], min = 0.5, max = 2, step = 0.05, desc = L["Size of the world map pins."] },
	{ type = "range", percent = true, key = "pinAlpha", label = L["Pin opacity"], min = 0.3, max = 1, step = 0.05, desc = L["How see-through the pins are."] },
	{ type = "range", percent = true, key = "minimapScale", label = L["Minimap pin scale"], min = 0.5, max = 2, step = 0.05, desc = L["Size of the minimap pins."], dependsOn = "minimapPins" },
	{ type = "header", label = L["Tooltips"] },
	{ type = "toggle", key = "tooltipLoot", label = L["Loot in tooltips"], desc = L["List a rare's or treasure's drops when you hover its pin."] },
	{ type = "toggle", key = "tooltipKnown", label = L["Collected marks"], desc = L["Say whether you already have each mount, pet, toy or appearance in the list."], dependsOn = "tooltipLoot" },
	{ type = "tab", label = L["Map button"] },
	{ type = "header", label = L["World map"] },
	{ type = "toggle", key = "mapButton", label = L["Button on the world map"], desc = L["A small button at the top right of the world map: click for the groups, Shift-click to show or hide everything."] },
	{ type = "toggle", key = "filterMenu", label = L["Entries in the map's filter menu"], desc = L["Add the same checks to the world map's own filter menu. Needs the World Map element switch (Blizzard UI page)."] },
	{ type = "toggle", key = "altClick", label = L["Alt+right-click adds a note"], desc = L["Hold Alt and right-click on the world map to add your own note there. While HandyNotes is loaded, its own Alt+right-click is used instead."] },
	{ type = "header", label = L["HandyNotes"], hidden = function() return not HandyNotesLoaded() end },
	{ type = "toggle", key = "handyNotesBridge", label = L["The switch controls HandyNotes"], desc = L["With HandyNotes installed, it becomes a group in the map button's menu, so one click hides EldoUI's and HandyNotes' pins together."], hidden = function() return not HandyNotesLoaded() end },
	{ type = "toggle", key = "groups.handynotes", label = L["Show HandyNotes"], desc = L["Show HandyNotes' pins (with all its plugins). Off turns HandyNotes off until you check it again."], dependsOn = "handyNotesBridge", hidden = function() return not HandyNotesLoaded() end },
	{ type = "execute", label = L["Open HandyNotes settings"], desc = L["HandyNotes' own settings, where its plugins are listed."], func = function() if M.OpenHandyNotes then M:OpenHandyNotes() end end, hidden = function() return not HandyNotesLoaded() end },
}

E:RegisterStyles("MapNotes", {
	{ key = "Standard", title = L["Standard"], desc = L["Pins in the art style's look, on the world map and the minimap."],
		settings = { iconStyle = "art", pinScale = 1, pinAlpha = 1, minimapPins = true, minimapEdge = false, hideDone = true } },
	{ key = "Game", title = L["Game icons"], desc = L["The game's own rare and treasure map icons, whatever the art style."],
		settings = { iconStyle = "game", pinScale = 1, pinAlpha = 1 } },
	{ key = "Dots", title = L["Quiet dots"], desc = L["Small dots in the loot's quality color, for a calm map."],
		settings = { iconStyle = "dots", pinScale = 0.85, pinAlpha = 0.85, minimapScale = 0.75 } },
	{ key = "Loot", title = L["Loot icons"], desc = L["Each rare shows its best drop's icon."],
		settings = { iconStyle = "icons", pinScale = 1.15, tooltipLoot = true, tooltipKnown = true } },
	{ key = "Large", title = L["Large"], desc = L["Bigger pins for big screens and ultrawides."],
		settings = { pinScale = 1.4, minimapScale = 1.1 } },
	{ key = "Hunter", title = L["Treasure hunter"], desc = L["Rares and treasures shown, done ones hidden, far ones kept on the minimap's edge. Your own notes and other groups stay as they are."],
		settings = { groups = { classicRares = true }, hideDone = true, minimapPins = true, minimapEdge = true } },
	{ key = "MapOnly", title = L["World map only"], desc = L["Notes on the world map; the minimap stays clean."],
		settings = { minimapPins = false } },
})
