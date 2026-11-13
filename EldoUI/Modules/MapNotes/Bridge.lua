-- EldoUI Map Notes: HandyNotes follows the map switch.
--
-- WoW: Forever's own rares and treasures come from HandyNotes and its
-- "WoW Forever" plugin when the player has them installed. With the bridge
-- on (the default), HandyNotes is a group in the map button's menu, and the
-- one switch hides its pins together with EldoUI's.
--
-- Only Ace3's public addon calls are used: AceAddon-3.0:GetAddon,
-- addon:IsEnabled(), :Enable(), :Disable(). Nothing is read from or written
-- into HandyNotes' saved data. EldoUI only turns HandyNotes back on when
-- EldoUI was the one that turned it off, so a player who switched HandyNotes
-- off in its own settings keeps it off.
local _, E = ...
local L = E.L
local M = E.MapNotes

local turnedOff  -- EldoUI switched HandyNotes off this session

function M:HandyNotes()
	if not (C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("HandyNotes")) then return end
	local stub = rawget(_G, "LibStub")
	local ace = stub and stub("AceAddon-3.0", true)
	local addon = ace and ace.GetAddon and select(2, pcall(ace.GetAddon, ace, "HandyNotes", true))
	if type(addon) == "table" and type(addon.IsEnabled) == "function" then return addon end
end

local function Bridged()
	return M.active and M.db.handyNotesBridge and M:HandyNotes() ~= nil
end

function M:ApplyBridge()
	local addon = self:HandyNotes()
	if not addon then return end
	local want = true
	if self.active and self.db.handyNotesBridge then
		-- The switch and the HandyNotes group only: "On the world map" off
		-- must not take HandyNotes' minimap pins with it.
		want = E:MapPinGroupShown("handynotes")
	end
	local ok, enabled = pcall(addon.IsEnabled, addon)
	if not ok then return end
	if want and not enabled and turnedOff then
		E:RunOutOfCombat(function()
			if pcall(addon.Enable, addon) then turnedOff = nil end
		end)
	elseif not want and enabled then
		E:RunOutOfCombat(function()
			if pcall(addon.Disable, addon) then turnedOff = true end
		end)
	end
end

-- Map Notes off or the bridge off: give HandyNotes back as it was.
function M:ReleaseBridge()
	local addon = self:HandyNotes()
	if not (addon and turnedOff) then return end
	E:RunOutOfCombat(function()
		if pcall(addon.Enable, addon) then turnedOff = nil end
	end)
end

-- HandyNotes' own settings (its slash command, which every version has).
function M:OpenHandyNotes()
	for key, fn in pairs(SlashCmdList or {}) do
		if type(key) == "string" and type(fn) == "function" then
			for i = 1, 9 do
				local command = rawget(_G, "SLASH_" .. key .. i)
				if command == nil then break end
				if type(command) == "string" and command:lower() == "/handynotes" then
					fn("")
					return true
				end
			end
		end
	end
	E:Print(L["HandyNotes isn't loaded."])
	return false
end

E:RegisterMapPinLayer("handynotes", {
	title = "HandyNotes (with its plugins)", order = 90,
	continent = "own", -- HandyNotes draws its own pins
	available = Bridged,
	refresh = function()
		if Bridged() then
			M:ApplyBridge()
		elseif M.active then
			M:ReleaseBridge()
		end
	end,
})
