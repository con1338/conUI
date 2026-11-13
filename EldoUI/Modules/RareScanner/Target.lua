-- Rare Alerts: the targeting key, off by default.
--
-- A hidden secure button, EldoUI_RareTargetButton, holds "/targetexact"
-- lines for this zone's rares (closest camp first, then rares seen this
-- session). The player presses it with its key binding (Key Bindings >
-- EldoUI Rare Alerts) or a "/click" macro: one press = one try. Nothing
-- presses it for the player, no timer runs it, and its text changes only
-- out of combat. This replaces any automatic targeting: TargetUnit is
-- never called.
local _, E = ...
local L = E.L
local M = E.RareScanner

local BUTTON = "EldoUI_RareTargetButton"
local MACRO_NAME = "EldoUI Rares"
local MACRO_ICON = "INV_MISC_QUESTIONMARK"
local MAX_TEXT = 255
M.TARGET_BUTTON, M.MACRO_NAME = BUTTON, MACRO_NAME

E:NameBinding("BINDING_HEADER_ELDOUIRARES", E.Key("EldoUI Rare Alerts"))
E:NameBinding("BINDING_NAME_CLICK " .. BUTTON .. ":LeftButton", E.Key("Target a rare nearby"))

-- The zone map (mapType Zone) of a uiMapID, walking up the parents.
local function ZoneMap(uiMapID)
	local guard = 0
	while uiMapID and C_Map and C_Map.GetMapInfo and guard < 5 do
		local info = M.Read(C_Map.GetMapInfo, uiMapID)
		if type(info) ~= "table" then return uiMapID end
		local zoneType = Enum and Enum.UIMapType and Enum.UIMapType.Zone or 3
		if info.mapType == zoneType or not info.parentMapID or info.parentMapID == 0 then return uiMapID end
		uiMapID, guard = info.parentMapID, guard + 1
	end
	return uiMapID
end

-- This zone's rares from the Loot Guide's World index, closest camp first.
function M:ZoneRares(uiMapID)
	local lg = E.LootGuide
	if not (uiMapID and lg and lg.WorldZones) then return {} end
	local ok, index = pcall(lg.WorldZones, lg)
	if not ok or type(index) ~= "table" then return {} end
	local zone = index.zones and (index.zones[uiMapID] or index.zones[ZoneMap(uiMapID)])
	if not zone then return {} end
	local list = {}
	local px, py
	if C_Map and C_Map.GetPlayerMapPosition then
		local pos = M.Read(C_Map.GetPlayerMapPosition, zone.id, "player")
		if type(pos) == "table" and type(pos.x) == "number" and not M.Secret(pos.x) and not M.Secret(pos.y) then px, py = pos.x, pos.y end
	end
	for _, npc in ipairs(zone.rares or {}) do
		local distance = math.huge
		if px and lg.SpawnPoints and lg.MapPosition then
			for _, camp in ipairs(lg:SpawnPoints("npc", npc)) do
				local map, x, y = lg:MapPosition(camp)
				if map == zone.id and x then
					local d = (x - px) ^ 2 + (y - py) ^ 2
					if d < distance then distance = d end
				end
			end
		end
		list[#list + 1] = { npc = npc, distance = distance }
	end
	table.sort(list, function(a, b)
		if a.distance ~= b.distance then return a.distance < b.distance end
		return a.npc < b.npc
	end)
	return list
end

-- The button's macro text, under 255 characters, or nil when empty.
function M:TargetMacro()
	local _, uiMapID = self.PlayerZone()
	local names, seen = {}, {}
	local function Add(name)
		if type(name) ~= "string" or M.Secret(name) or name == "" then return end
		local key = name:lower()
		if seen[key] then return end
		seen[key] = true
		names[#names + 1] = name
	end
	for _, rare in ipairs(self:ZoneRares(uiMapID)) do
		if not self:IsIgnored("npc:" .. rare.npc) then Add(self:NameOf(rare.npc)) end
	end
	for _, entry in ipairs(self.sessionList) do
		if entry.zone == (self.PlayerZone()) and not self:IsIgnored(entry.key) then Add(entry.name) end
	end
	local lines = {}
	local length = 0
	for _, name in ipairs(names) do
		local line = "/targetexact " .. name
		local extra = #line + (#lines > 0 and 1 or 0)
		if length + extra > MAX_TEXT then break end
		lines[#lines + 1] = line
		length = length + extra
	end
	if #lines == 0 then return nil end
	return table.concat(lines, "\n")
end

function M:EnsureTargetButton()
	if self.targetButton then return self.targetButton end
	if InCombatLockdown() then return nil end
	local button = CreateFrame("Button", BUTTON, UIParent, "SecureActionButtonTemplate")
	button:Hide()
	button:EnableMouse(false)
	button:RegisterForClicks("AnyUp")
	button:SetAttribute("useOnKeyDown", false)
	button:SetAttribute("type", "macro")
	self.targetButton = button
	return button
end

-- Refill the button's lines (zone change, login, new sighting, option).
function M:RefillTargetButton()
	E:RunOutOfCombat(function()
		local button = M.active and M:EnsureTargetButton() or M.targetButton
		if not button then return end
		local text = (M.active and M.db.targetButton) and M:TargetMacro() or nil
		if button:GetAttribute("macrotext") ~= text then button:SetAttribute("macrotext", text) end
		M.targetText = text
	end)
end

function M:EnableTargetButton()
	self:RefillTargetButton()
end

function M:DisableTargetButton()
	E:RunOutOfCombat(function()
		if M.targetButton then M.targetButton:SetAttribute("macrotext", nil) end
		M.targetText = nil
	end)
end

-- "Create a macro for your bars": a character macro that presses the
-- button, made once on the player's click. An existing one is left as is;
-- the player's own macros are never edited.
function M:CreateTargetMacro()
	return E:RunOutOfCombat(function()
		if type(GetMacroIndexByName) ~= "function" or type(CreateMacro) ~= "function" then return end
		local index = GetMacroIndexByName(MACRO_NAME)
		if type(index) == "number" and index > 0 then
			E:Print(L["The macro %s already exists. Find it under Macros (/macro), Character tab."]:format(E:Highlight(MACRO_NAME)))
			return
		end
		local ok, made = pcall(CreateMacro, MACRO_NAME, MACRO_ICON, "/click " .. BUTTON, true)
		if ok and made then
			E:Print(L["Made the character macro %s. Drag it from Macros (/macro) to an action bar."]:format(E:Highlight(MACRO_NAME)))
		else
			E:Print(L["No free character macro slot. Delete one under Macros (/macro) and try again."])
		end
	end)
end
