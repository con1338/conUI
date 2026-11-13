-- Battleground Timers: base, tower and graveyard captures.
--
-- One engine for every node battleground (Arathi Basin, Darkspear Islands,
-- Alterac Valley), fed by the map's own points of interest:
-- AREA_POIS_UPDATED (and once, a second after entering) ->
-- C_Map.GetBestMapForUnit("player") -> C_AreaPoiInfo.GetAreaPOIForMap ->
-- GetAreaPOIInfo per areaPoiID. Each POI is tracked by its areaPoiID.
--
--   1. The game's own time first: IsAreaPOITimed(id) and then
--      GetAreaPOISecondsLeft(id) > 0 gives the bar its time. This also
--      gets a late join or a /reload right without any addon messages.
--   2. Otherwise the POI's state: EldoUI's own textureIndex tables per map
--      (MapData, filled from /eui probe bg), then the atlas name (left /
--      right, alliance / horde, contested / assault words), then factionID.
--      An assault starts a bar with the map's assault seconds from the
--      moment the change was seen; a settled state stops it.
--   3. A POI whose state cannot be read yet: any change of its icon while
--      no bar runs and the last change was not one assault time ago
--      starts a bar; the next change (defended or flipped) stops it.
-- POIs seen for the first time (entering, /reload) never start a bar from
-- 2. or 3.: the start of that assault is unknown, so none is shown rather
-- than a wrong one. Mines and other resource nodes change owner at once:
-- they never get a capture bar (Extras.lua shows their owner).
--
-- The assault time is learned on this client: the game's own time at the
-- start of an assault, or the time from an assault to the flip when both
-- were seen. It is kept per battleground for the whole account and used
-- instead of MapData's public value. Nothing here reads the combat log or
-- sends anything.
local _, E = ...
local L = E.L
local M = E:GetModule("Battlegrounds")
local Read, IsSecret = M.Read, M.IsSecret

local P = M:AddPart({ name = "captures" })
M.Captures = P

local SETTLE = 1          -- seconds after entering before the first scan
local GAME_SLACK = 2      -- game time drift before a bar restarts
local FLIP_SLACK = 5      -- a change this close to one assault time is the flip
local LEARN_MIN, LEARN_MAX = 10, 900 -- plausible assault times (seconds)

local pois = {}           -- areaPoiID -> { sig, side, assault, changedAt, name }

local Plain = E.Plain

---------------------------------------------------------------------------
-- Reading a POI's state
---------------------------------------------------------------------------
local ASSAULT_WORDS = { "assault", "contested", "conflict", "capping", "attack" }
local SETTLED_WORDS = { "controlled", "owned", "captured", "held" }

local function HasWord(text, words)
	for _, word in ipairs(words) do
		if text:find(word, 1, true) then return true end
	end
	return false
end

-- side ("alliance" / "horde" / nil) and assault (true / false / nil = unknown).
function P.Classify(info, map)
	local index = Plain(info.textureIndex)
	local atlas = Plain(info.atlasName)
	local side, assault
	if index and map then
		local state = map.assaultStates and map.assaultStates[index]
		if state then return M.Side(state), true end
		state = map.settledStates and map.settledStates[index]
		if state then return M.Side(state), false end
	end
	if type(atlas) == "string" and atlas ~= "" then
		local lower = atlas:lower()
		if lower:find("alliance", 1, true) or lower:find("left", 1, true) then
			side = "alliance"
		elseif lower:find("horde", 1, true) or lower:find("right", 1, true) then
			side = "horde"
		end
		if HasWord(lower, ASSAULT_WORDS) then
			assault = true
		elseif HasWord(lower, SETTLED_WORDS) then
			assault = false
		end
	end
	if not side then side = M.Side(Plain(info.factionID)) end
	return side, assault
end

---------------------------------------------------------------------------
-- The assault time: measured on this client, else MapData's public value
---------------------------------------------------------------------------
local function Learned(create)
	local global = E.global
	if type(global) ~= "table" then return nil end
	if create then
		global.Battlegrounds = type(global.Battlegrounds) == "table" and global.Battlegrounds or {}
		global.Battlegrounds.assault = type(global.Battlegrounds.assault) == "table" and global.Battlegrounds.assault or {}
	end
	local saved = global.Battlegrounds
	return type(saved) == "table" and type(saved.assault) == "table" and saved.assault or nil
end

function M:AssaultTime(map)
	if not map then return nil end
	local learned = Learned()
	local seconds = learned and map.instanceID and learned[map.instanceID]
	if type(seconds) == "number" and seconds >= LEARN_MIN and seconds <= LEARN_MAX then return seconds end
	return map.assault
end

local function Learn(map, seconds)
	if not (map and map.instanceID and map.instanceID ~= 0) or type(seconds) ~= "number" then return end
	seconds = math.floor(seconds + 0.5)
	if seconds < LEARN_MIN or seconds > LEARN_MAX then return end
	local learned = Learned(true)
	if learned then learned[map.instanceID] = seconds end
end
P.Learn = Learn

local function IsResource(atlas, map)
	local word = map and map.resourceAtlas
	return type(word) == "string" and type(atlas) == "string" and atlas:lower():find(word, 1, true) ~= nil
end

---------------------------------------------------------------------------
-- Bars
---------------------------------------------------------------------------
local function Key(id) return "poi:" .. id end

local function Tooltip(side, fromGame)
	local who = side and M:SideName(side) or L["A side"]
	if fromGame then
		return L["%s is taking this point. Time from the game."]:format(who)
	end
	return L["%s is taking this point. Estimated from when the map changed."]:format(who)
end

local function StartBar(id, entry, seconds, fromGame, icon)
	local key = Key(id)
	if fromGame and M:BarNear(key, seconds, GAME_SLACK) then return end
	M:Bar(key, {
		kind = entry.side or "other",
		side = entry.side,
		label = entry.name,
		duration = seconds,
		icon = icon or (entry.side and M:FactionIcon(entry.side)) or nil,
		tooltip = Tooltip(entry.side, fromGame),
	})
end

---------------------------------------------------------------------------
-- Scan
---------------------------------------------------------------------------
function P:MapID()
	local mapID = Read(C_Map.GetBestMapForUnit, "player")
	if type(mapID) ~= "number" or mapID <= 0 then mapID = M.map and M.map.uiMapID end
	return mapID
end

function P:Active()
	return M.map ~= nil and M.db.captures and not M:StandBack()
end

function P:Scan()
	if not self:Active() then return end
	local map = M.map
	local mapID = self:MapID()
	if not mapID then return end
	local ids = Read(C_AreaPoiInfo.GetAreaPOIForMap, mapID)
	if type(ids) ~= "table" then return end
	local now = GetTime()
	local seen = {}
	for _, id in ipairs(ids) do
		if type(id) == "number" and not IsSecret(id) then
			seen[id] = true
			local info = Read(C_AreaPoiInfo.GetAreaPOIInfo, mapID, id)
			if type(info) == "table" then self:Track(id, info, map, now) end
		end
	end
	-- Owner chips, after the capture bars are settled.
	if M.UpdateOwner then
		for id, entry in pairs(pois) do
			if seen[id] then M:UpdateOwner(id, entry, map) end
		end
	end
	-- POIs that went away.
	for id in pairs(pois) do
		if not seen[id] then
			pois[id] = nil
			M:Stop(Key(id))
			if M.ForgetOwner then M:ForgetOwner(id) end
		end
	end
end

function P:Track(id, info, map, now)
	local name = Plain(info.name)
	if type(name) ~= "string" or name == "" then return end
	local index, atlas = Plain(info.textureIndex), Plain(info.atlasName)
	local sig = tostring(index) .. "|" .. tostring(atlas)
	local side, assault = P.Classify(info, map)
	local entry = pois[id]
	local first = entry == nil
	local changed = not first and entry.sig ~= sig
	local lastChange = entry and entry.changedAt
	entry = entry or {}
	pois[id] = entry
	entry.name, entry.side, entry.assault = name, side, assault
	if first or changed then
		entry.sig = sig
		entry.previousChange = lastChange
		entry.changedAt = first and nil or now
	end
	local icon = (type(atlas) == "string" and atlas ~= "") and atlas or nil
	local key = Key(id)
	entry.resource = IsResource(atlas, map) or nil
	if entry.resource then
		M:Stop(key)
		return
	end

	-- 1. The game's own time. At the start of an assault it is the whole
	-- assault time on this client.
	local timed = Read(C_AreaPoiInfo.IsAreaPOITimed, id)
	if timed then
		local seconds = Read(C_AreaPoiInfo.GetAreaPOISecondsLeft, id)
		if type(seconds) == "number" and seconds > 0 then
			if changed then Learn(map, seconds) end
			entry.assaultAt = nil
			StartBar(id, entry, seconds, true, icon)
			return
		end
	end
	local length = M:AssaultTime(map)
	-- 2. A known state. An assault seen from its start and then settled in
	-- the attacker's color was a flip: its length is this client's time.
	if assault == true and changed then
		entry.assaultAt, entry.assaultSide = now, side
	elseif assault == false then
		if changed and entry.assaultAt and side and side == entry.assaultSide then
			Learn(map, now - entry.assaultAt)
		end
		entry.assaultAt, entry.assaultSide = nil, nil
	end
	if assault == true then
		if not M:HasBar(key) and entry.changedAt and length then
			local left = length - (now - entry.changedAt)
			if left > 0 then StartBar(id, entry, left, false, icon) end
		elseif M:HasBar(key) and changed then
			-- Re-assaulted by the other side: a fresh timer in its color.
			if length then StartBar(id, entry, length, false, icon) end
		end
		return
	elseif assault == false then
		M:Stop(key)
		return
	end
	-- 3. Unknown state: work from changes and timing.
	if not changed then return end
	if M:HasBar(key) then
		M:Stop(key)   -- defended or flipped
		return
	end
	if not length then return end
	local previous = entry.previousChange
	if previous and math.abs((now - previous) - length) <= FLIP_SLACK then
		return        -- the flip at the end of an assault
	end
	StartBar(id, entry, length, false, icon)
end

---------------------------------------------------------------------------
-- Part hooks
---------------------------------------------------------------------------
function P:Enable()
	M:RegisterEvent("AREA_POIS_UPDATED", function() P:Scan() end)
end

function P:Disable()
	M:UnregisterEvent("AREA_POIS_UPDATED")
	wipe(pois)
end

function P:Enter()
	wipe(pois)
	C_Timer.After(SETTLE, function() P:Scan() end)
end

function P:Leave()
	wipe(pois)
	M:StopPrefix("poi:")
end

function P:Refresh()
	if not self:Active() then
		M:StopPrefix("poi:")
		return
	end
	self:Scan()
end
