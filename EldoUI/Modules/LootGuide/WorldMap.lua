-- EldoUI Loot Guide: world map pins.
--
--   * Entrance pins (option "Dungeon entrances on the world map"): one per
--     instance entrance the client knows (C_EncounterJournal entrances, see
--     LG:EntrancePoint); entrances that several wings share get one pin and
--     a choice. Where the world map draws its own entrance pin (the game's
--     dungeon entrance layer is on), ours steps aside, so no entrance shows
--     twice. Hover: name and level (or the list); click: opens the
--     instance in the Journal with its dungeon map, over the map (the
--     player closes the map). The pin of the instance you opened last
--     breathes until the map closes.
--   * Our mark: the place a Map button pinned (LG:SetWaypoint) shows as an
--     accent pin; right-click on it clears it (only while the game's pin is
--     still ours).
--   * LG:ShowMark() opens the world map on the mark through the game's own
--     request (E:OpenWorldMapAt), only out of combat and while the game's
--     map restriction is off; otherwise one chat hint "Open the map (M) to
--     see the mark", and the mark waits on the map.
--
-- Pins are drawn through E.DungeonMaps' world-map overlay (our own frames
-- on top of Blizzard's map canvas; Blizzard's pin pools are not used).
local _, E = ...
local LG = E.LootGuide
local L = E.L

local ENTRANCE_ICON = "Interface\\Icons\\INV_Misc_Book_09"
local RAID_ICON = "Interface\\Icons\\INV_Misc_Head_Dragon_01"

local Secret = E.Secret

---------------------------------------------------------------------------
-- Map open / close rules
---------------------------------------------------------------------------
function LG:MapRestricted()
	return E:MapRestricted()
end

-- Opens the world map on a zone; otherwise the hint to open it.
function LG:OpenWorldMapAt(uiMapID)
	if E:OpenWorldMapAt(uiMapID) then return true end
	E:Print(L["Open the map (M) to see the mark."])
	return false
end

-- The mark a Map button set: open the map there.
function LG:ShowMark()
	local own = self.ownWaypoint
	if type(own) ~= "table" then return end
	return self:OpenWorldMapAt(own.uiMapID)
end

function LG:MarkChanged()
	if E.RefreshMapPins then E:RefreshMapPins() end
end

---------------------------------------------------------------------------
-- Entrances, grouped where wings share one door
---------------------------------------------------------------------------
local entranceCache

LG:On("worldmap-data", function(changed)
	if changed.data then entranceCache = nil end
end)

-- { [uiMapID] = { { x, y, keys = { key, ... } }, ... } }
function LG:EntrancePins()
	if entranceCache then return entranceCache end
	if InCombatLockdown() then return {} end
	local out = {}
	for _, info in ipairs(self:Catalog()) do
		if not info.world and self:Playable(info) then
			local point = self:EntrancePoint(info.key)
			if point and point.uiMapID then
				local list = out[point.uiMapID] or {}
				out[point.uiMapID] = list
				local shared
				for _, pin in ipairs(list) do
					if math.abs(pin.x - point.x) < 0.01 and math.abs(pin.y - point.y) < 0.01 then shared = pin break end
				end
				if shared then
					table.insert(shared.keys, info.key)
				else
					list[#list + 1] = { x = point.x, y = point.y, keys = { info.key }, raid = info.kind == "raid" }
				end
			end
		end
	end
	entranceCache = out
	return out
end

-- The Journal's Entrance button: pin the entrance, light its pin and open
-- the map there (out of combat).
function LG:ShowEntrance(key)
	local point = self:EntrancePoint(key)
	local info = self:InstanceInfo(key)
	if not point then
		E:Print(L["The client does not know where this entrance is."])
		return false
	end
	if not self:SetWaypoint(point, info and info.name or key) then return false end
	self.ownWaypoint.entrance = key
	self.litEntrance = key
	if E.RefreshMapPins then E:RefreshMapPins() end
	return self:ShowMark()
end

-- Open the instance and its dungeon map. The map stays open: closing it
-- from addon code would leave the game's map blocked later.
function LG:OpenFromEntrance(key)
	if InCombatLockdown() then
		E:Print(L["The Loot Guide opens out of combat."])
		return
	end
	self:Open("journal", key)
	if self.OpenDungeonMap then self:OpenDungeonMap(key) end
end

local function EntranceTooltip(tooltip, pin)
	local P = LG.PageKit
	E.UIKit.TipTitle(tooltip, #pin.keys > 1 and L["Instance entrance"] or (LG:InstanceName(pin.keys[1]) or pin.keys[1]))
	local r, g, b = 0.65, 0.65, 0.7
	for _, key in ipairs(pin.keys) do
		local info = LG:InstanceInfo(key)
		if info then
			if #pin.keys > 1 then
				tooltip:AddDoubleLine(info.name, P and P.LevelText(info) or "", 1, 1, 1, 1, 1, 1)
			else
				tooltip:AddDoubleLine(L["Level"], P and P.LevelText(info) or "", r, g, b, 1, 1, 1)
				if P then tooltip:AddDoubleLine(L["Group"], P.SizeText(info), r, g, b, 1, 1, 1) end
			end
		end
	end
	tooltip:AddLine(" ")
	E:TooltipHint(tooltip, { L["Click"], #pin.keys > 1 and L["pick one and open it in the Loot Guide"] or L["open it in the Loot Guide with its dungeon map"] })
end

local function EntranceClick(pin, button, frame)
	if button ~= "LeftButton" then return end
	if #pin.keys == 1 then
		LG:OpenFromEntrance(pin.keys[1])
		return
	end
	E.UIKit.ContextMenu(frame, function(_, root)
		root:CreateTitle(L["Instance entrance"])
		for _, key in ipairs(pin.keys) do
			local info = LG:InstanceInfo(key)
			root:CreateButton(info and info.name or key, function() LG:OpenFromEntrance(key) end)
		end
	end)
end

-- The game's own entrance pins on a map: { { x, y }, ... }, empty when the
-- world map draws none (no entrance layer, or "Dungeon entrances" is off in
-- its filter menu).
local ENTRANCE_CVAR = "showDungeonEntrancesOnMap"
local STEP_ASIDE = 0.02 -- map share: closer than this to the game's pin, ours hides

local function Plain(value)
	if type(value) ~= "number" or Secret(value) then return nil end
	return value
end

local function GameEntranceLayer(map)
	local providers = type(map) == "table" and rawget(map, "dataProviders")
	if type(providers) ~= "table" then return nil end
	local mixin = rawget(_G, "DungeonEntranceDataProviderMixin")
	for provider in pairs(providers) do
		if type(provider) == "table" and (provider.cvar == ENTRANCE_CVAR
			or (type(mixin) == "table" and mixin.RefreshAllData and provider.RefreshAllData == mixin.RefreshAllData)) then
			return provider
		end
	end
end

function LG:GameEntrances(uiMapID)
	local out = {}
	local map = rawget(_G, "WorldMapFrame")
	local layer = GameEntranceLayer(map)
	if not layer then return out end
	local on
	if type(layer.IsCVarSet) == "function" then
		local ok, set = pcall(layer.IsCVarSet, layer)
		on = ok and not Secret(set) and set
	elseif C_CVar and C_CVar.GetCVarBool then
		local ok, set = pcall(C_CVar.GetCVarBool, ENTRANCE_CVAR)
		on = ok and not Secret(set) and set
	end
	if not on then return out end
	local journal = C_EncounterJournal
	if journal and journal.GetDungeonEntrancesForMap then
		local ok, list = pcall(journal.GetDungeonEntrancesForMap, uiMapID)
		if ok and type(list) == "table" and not Secret(list) then
			for _, entrance in ipairs(list) do
				local pos = type(entrance) == "table" and entrance.position
				if type(pos) == "table" and not Secret(pos) then
					local x, y = Plain(pos.x), Plain(pos.y)
					if x and y then out[#out + 1] = { x = x, y = y } end
				end
			end
		end
	end
	-- And the pins it drew on the map shown now.
	local shown
	if type(map.GetMapID) == "function" then
		local ok, id = pcall(map.GetMapID, map)
		shown = ok and Plain(id)
	end
	if shown == uiMapID and type(map.EnumeratePinsByTemplate) == "function" then
		pcall(function()
			for pin in map:EnumeratePinsByTemplate("DungeonEntrancePinTemplate") do
				if type(pin) == "table" and type(pin.GetPosition) == "function" then
					local fine, x, y = pcall(pin.GetPosition, pin)
					if fine then
						x, y = Plain(x), Plain(y)
						if x and y then out[#out + 1] = { x = x, y = y } end
					end
				end
			end
		end)
	end
	return out
end

-- Our entrance pins of a map that the game does not draw itself.
function LG:OwnEntrancePins(uiMapID)
	local list = self:EntrancePins()[uiMapID] or {}
	local game = self:GameEntrances(uiMapID)
	if #game == 0 then return list end
	local out = {}
	for _, entry in ipairs(list) do
		local covered = false
		for _, spot in ipairs(game) do
			if math.abs(spot.x - entry.x) < STEP_ASIDE and math.abs(spot.y - entry.y) < STEP_ASIDE then covered = true break end
		end
		if not covered then out[#out + 1] = entry end
	end
	return out
end

local entranceProvider = {
	order = 40,
	group = "entrances",  -- the map switch (Core/MapPins.lua)
	pins = function(_, ctx)
		if ctx.kind ~= "world" or not (LG.active and LG.db.mapEntrances and LG:HasData()) then return end
		local list = {}
		for _, entry in ipairs(LG:OwnEntrancePins(ctx.uiMapID)) do
			local lit = false
			for _, key in ipairs(entry.keys) do
				if key == LG.litEntrance then lit = true end
			end
			list[#list + 1] = { x = entry.x, y = entry.y, id = "entrance:" .. entry.keys[1], keys = entry.keys,
				icon = entry.raid and RAID_ICON or ENTRANCE_ICON, size = 22, label = #entry.keys > 1 and #entry.keys or nil,
				tooltip = EntranceTooltip, onClick = EntranceClick, pulse = lit }
		end
		return list
	end,
}

---------------------------------------------------------------------------
-- Our mark
---------------------------------------------------------------------------
local markProvider = {
	order = 45,
	pins = function(_, ctx)
		local own = LG.ownWaypoint
		if ctx.kind ~= "world" or not LG.active or type(own) ~= "table" or own.uiMapID ~= ctx.uiMapID then return end
		-- The waypoint was reached, removed or replaced: no stale mark.
		if not LG:MarkAlive() then return end
		-- An entrance mark shows as its lit entrance pin instead.
		if own.entrance and LG.db.mapEntrances then return end
		return { { x = own.x, y = own.y, id = "lootguide-mark", size = 18, color = { E.media.accentColor[1], E.media.accentColor[2], E.media.accentColor[3] },
			label = "!", pulse = true,
			tooltip = function(tooltip)
				E.UIKit.TipTitle(tooltip, own.title or L["Loot Guide mark"])
				E:TooltipHint(tooltip, { L["Right-click"], L["clear the mark"] })
			end,
			onClick = function(_, button)
				if button == "RightButton" then
					LG:ClearWaypoint()
					E:Print(L["Map pin cleared."])
				end
			end } }
	end,
}

---------------------------------------------------------------------------
-- Enable / disable
---------------------------------------------------------------------------
local mapHooked
function LG:OnEnableMaps()
	if not E.DungeonMaps then return end
	E:AddMapPinProvider("lootguide-entrances", entranceProvider)
	E:AddMapPinProvider("lootguide-mark", markProvider)
	local frame = rawget(_G, "WorldMapFrame")
	if frame then
		E.DungeonMaps:AttachWorldMap()
		if not mapHooked then
			mapHooked = true
			-- The lit entrance stops breathing once the map closes.
			frame:HookScript("OnHide", function()
				if LG.litEntrance then
					LG.litEntrance = nil
					E:RefreshMapPins()
				end
			end)
		end
	end
end

function LG:OnDisableMaps()
	if not E.RemoveMapPinProvider then return end
	E:RemoveMapPinProvider("lootguide-entrances")
	E:RemoveMapPinProvider("lootguide-mark")
end

LG:On("worldmap-pins", function(changed)
	if changed.settings or changed.data then E:RefreshMapPins() end
end)

-- The map switch (Core/MapPins.lua): the Map Notes button and keybind hide
-- the entrance pins with every other EldoUI pin.
if E.RegisterMapPinLayer then
	E:RegisterMapPinLayer("entrances", {
		title = "Instance entrances", order = 80, continent = true,
		available = function() return LG.active and LG.db.mapEntrances and LG:HasData() and true or false end,
		count = function(uiMapID) return LG.active and LG:HasData() and #LG:OwnEntrancePins(uiMapID) or 0 end,
	})
end
