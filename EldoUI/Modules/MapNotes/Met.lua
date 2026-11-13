-- EldoUI Map Notes: "Rares you've met".
--
-- When you target or point at a rare creature outdoors, Map Notes keeps
-- where you stood, its name and when, and pins that spot on the map. The
-- rare test is Rare Alerts' (M:ReadRareUnit): the game's own
-- classification, read only after the unit's identity is known not to be
-- secret. Nothing is kept in dungeons, raids, battlegrounds or arenas.
--
-- Saved account-wide, with the other notes:
--   E.global.MapNotes.met[key] = { m = uiMapID, x, y, n = name, t = time,
--     npc, c = classification, l = level }
--   key: "n:<npc id>", or "s:<name>" when the game gives no creature id.
local _, E = ...
local L = E.L
local M = E.MapNotes

local Try, Clean = M.Try, M.Clean
local abs = math.abs

local MAX_MET = 500
local MOVED = 0.005 -- a new spot only when you stood this far (map share) from the last one

function M:MetStore()
	local store = self:Notes()
	if type(store.met) ~= "table" then store.met = {} end
	return store.met
end

local function Outdoors()
	local inside = IsInInstance and Clean(Try(IsInInstance))
	return not inside
end

-- Your position on the map you are in, or nil where the game gives none.
local function PlayerSpot()
	if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then return nil end
	local uiMapID = Clean(Try(C_Map.GetBestMapForUnit, "player"))
	if type(uiMapID) ~= "number" then return nil end
	local pos = Try(C_Map.GetPlayerMapPosition, uiMapID, "player")
	if type(pos) ~= "table" or E:IsSecret(pos) or not pos.GetXY then return nil end
	local x, y = Try(pos.GetXY, pos)
	x, y = Clean(x), Clean(y)
	if type(x) ~= "number" or type(y) ~= "number" or x <= 0 or y <= 0 or x >= 1 or y >= 1 then return nil end
	return uiMapID, x, y
end

local function Trim(store)
	local count, oldestKey, oldest = 0, nil, nil
	for key, entry in pairs(store) do
		count = count + 1
		local t = type(entry) == "table" and tonumber(entry.t) or 0
		if not oldest or t < oldest then oldestKey, oldest = key, t end
	end
	if count > MAX_MET and oldestKey then
		store[oldestKey] = nil
		return Trim(store)
	end
end

-- info: { npc, name, classification, level } from M:ReadRareUnit.
function M:MeetRare(info)
	if not (self.active and self.db.metRares) or type(info) ~= "table" then return end
	local name = info.name
	if type(name) ~= "string" or E:IsSecret(name) or name == "" then return end
	if not Outdoors() then return end
	local uiMapID, x, y = PlayerSpot()
	if not uiMapID then return end
	local npc = tonumber(info.npc)
	local key = npc and ("n:%d"):format(npc) or ("s:" .. name)
	local store = self:MetStore()
	local entry = store[key]
	local now = time and time() or 0
	if type(entry) == "table" and entry.m == uiMapID and type(entry.x) == "number" and type(entry.y) == "number"
		and abs(entry.x - x) < MOVED and abs(entry.y - y) < MOVED then
		entry.t = now
		return entry
	end
	local class = info.classification
	store[key] = {
		m = uiMapID, x = math.floor(x * 10000 + 0.5) / 10000, y = math.floor(y * 10000 + 0.5) / 10000,
		n = name, t = now, npc = npc,
		c = (class == "rare" or class == "rareelite" or class == "worldboss") and class or nil,
		l = tonumber(info.level),
	}
	Trim(store)
	self:Refresh()
	return store[key]
end

function M:ForgetMet(key)
	local store = self:MetStore()
	if key == nil or store[key] == nil then return end
	store[key] = nil
	self:Refresh()
end

function M:ForgetAllMet()
	wipe(self:MetStore())
	self:Refresh()
end

-- The pins of one map (Core.lua's AllPoints).
function M:MetPoints(uiMapID, out)
	local LG = M.LootGuide()
	for key, entry in pairs(self:MetStore()) do
		if type(entry) == "table" and entry.m == uiMapID and type(entry.x) == "number" and type(entry.y) == "number" then
			local loot = {}
			if LG and LG.MobLoot and entry.npc then
				local ok, rows = pcall(LG.MobLoot, LG, entry.npc)
				for _, row in ipairs(ok and type(rows) == "table" and rows or {}) do
					if row.itemID and not row.questOnly then loot[#loot + 1] = { itemID = row.itemID, chance = row.chance } end
				end
			end
			out[#out + 1] = {
				key = "r:" .. key, group = "metRares", kind = "rare",
				uiMapID = uiMapID, x = entry.x, y = entry.y, title = entry.n, npc = entry.npc,
				level = entry.l, elite = entry.c == "rareelite" or entry.c == "worldboss",
				worldBoss = entry.c == "worldboss" or nil,
				loot = loot, met = entry.t, metKey = key, source = "met",
			}
		end
	end
end

E:RegisterMapPinLayer("metRares", {
	title = "Rares you've met", order = 25, continent = false,
	available = function() return M.active end,
	count = function(uiMapID) return M:CountGroup("metRares", uiMapID) end,
})

---------------------------------------------------------------------------
-- Listening: your target and your mouseover
---------------------------------------------------------------------------
local listener = CreateFrame("Frame")
listener:SetScript("OnEvent", function(_, event)
	if not (M.active and M.db.metRares) then return end
	local RS = E.RareScanner
	if not (RS and RS.ReadRareUnit) then return end
	local unit = event == "PLAYER_TARGET_CHANGED" and "target" or "mouseover"
	local info = RS:ReadRareUnit(unit)
	if info then M:MeetRare(info) end
end)

function M:EnableMet()
	pcall(listener.RegisterEvent, listener, "PLAYER_TARGET_CHANGED")
	pcall(listener.RegisterEvent, listener, "UPDATE_MOUSEOVER_UNIT")
end

function M:DisableMet()
	listener:UnregisterAllEvents()
end
