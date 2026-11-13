-- EldoUI built-in addon setups. Each uses the other addon's own public
-- import and export functions; see Core/AddonSetup.lua for the flow.
local _, E = ...
local L = E.L

local Key = E.Key
-- Every setup here can be undone, or says how: E:RestoreAddonSetup(name)
-- runs the setup's `restore`, which returns true when the other addon is
-- back the way it was before EldoUI's import, or false and what the player
-- can do themselves.
function E:RestoreAddonSetup(name)
	local setup = self.addonSetups and self.addonSetups[name]
	if not (setup and type(setup.restore) == "function") then return false, L["EldoUI has nothing to undo for this addon."] end
	return setup.restore()
end

-- Details! Damage Meter: one profile per layout, through Details' own
-- public profile calls (ImportProfile, ExportCurrentProfile,
-- GetCurrentProfileName, ApplyProfile). EldoUI never writes Details' saved
-- tables itself. The import goes into a profile named "EldoUI - <Layout>"
-- and switches Details to it; the profile Details used before is
-- remembered, so Integrations > Details! can switch back. A layout without
-- its own string uses the "default" one (Data/Profiles.lua).
--
-- The remembered name sits in the saved file under
-- "detailsPreviousProfile" (the key it always had); RememberDetailsProfile
-- is the only place that writes it and E:DetailsPreviousProfile() reads it.
E:RegisterStore("detailsPreviousProfile", { owner = "Setups", accessor = "RememberDetailsProfile" })

local function RememberDetailsProfile(name)
	if type(EldoUIDB) == "table" then EldoUIDB.detailsPreviousProfile = name end
end

-- The player's own Details profile from before EldoUI's import, or nil.
function E:DetailsPreviousProfile()
	local name = type(EldoUIDB) == "table" and EldoUIDB.detailsPreviousProfile
	return type(name) == "string" and name or nil
end
local function DetailsAPI()
	local details = _G.Details -- optional addon, looked up when used
	if type(details) == "table" and type(details.ImportProfile) == "function" then return details end
end

local function LayoutKey()
	local key = E.db and E.db.general and E.db.general.layout
	return type(key) == "string" and key or "default"
end

local function LayoutTitle(key)
	local layout = E.layouts and E.layouts[key]
	return layout and layout.title and L[layout.title] or tostring(key or "")
end

-- The Details profile EldoUI imports into for a layout.
function E:DetailsProfileName(key)
	return E:Utf8Sub("EldoUI - " .. LayoutTitle(key or LayoutKey()), 50)
end

E:RegisterAddonSetup("Details", {
	title = "Details! Damage Meter",
	key = LayoutKey,
	keyLabel = function() return LayoutTitle(LayoutKey()) end,
	layoutKeyed = true,
	available = function()
		return DetailsAPI() ~= nil
	end,
	export = function()
		return DetailsAPI():ExportCurrentProfile()
	end,
	import = function(data, _, key)
		local details = DetailsAPI()
		if not details then return false, L["Details is not loaded"] end
		local previous
		if type(details.GetCurrentProfileName) == "function" then
			local ok, name = pcall(details.GetCurrentProfileName, details)
			if ok and type(name) == "string" then previous = name end
		end
		local name = E:DetailsProfileName(key)
		-- ImportProfile creates (or refreshes) the named profile and switches
		-- to it itself; a second ApplyProfile would only reload it.
		if not details:ImportProfile(data, name, false, false, true) then
			return false, L["Details refused the profile string"]
		end
		-- The player's own profile, for "Switch back" (not an EldoUI one).
		if previous and previous ~= name and not previous:find("^EldoUI") then
			RememberDetailsProfile(previous)
		end
		return true
	end,
	restore = function()
		if E:RestoreDetailsProfile() then return true end
		if E:DetailsPreviousProfile() and InCombatLockdown() then return false, L["Details switches back after combat."] end
		return false, L["There is no Details profile of yours to switch back to."]
	end,
})

-- Switch Details back to the profile it used before EldoUI's import.
function E:RestoreDetailsProfile()
	local details = DetailsAPI()
	local previous = E:DetailsPreviousProfile()
	if not (details and previous and type(details.ApplyProfile) == "function") then return false end
	if InCombatLockdown() then
		E:RunOutOfCombat(function() E:RestoreDetailsProfile() end, "Details:restore")
		return false
	end
	if type(details.GetProfile) == "function" and not details:GetProfile(previous, false) then
		-- That profile is gone from Details: nothing left to switch back to.
		RememberDetailsProfile(nil)
		return false
	end
	details:ApplyProfile(previous)
	return true
end

-- Blizzard Cooldown Manager: one layout per class and specialization.
-- Blizzard's own Import box is used, because the game has no documented
-- addon call for importing a cooldown layout. EldoUI only shows the string
-- in a copy box, so it changes nothing itself: the player's import adds
-- the layout next to their own, and switching back is picking their own
-- layout again in the same settings, which `restore` says.
-- Forever has the specialization calls in C_SpecializationInfo only (the
-- old GetSpecialization globals are not there). A secret value is never
-- used as a key.
local function SpecKey()
	local _, class = UnitClass("player")
	if issecretvalue and issecretvalue(class) then class = nil end
	local specID = 0
	local spec = C_SpecializationInfo
	if spec and type(spec.GetSpecialization) == "function" and type(spec.GetSpecializationInfo) == "function" then
		local ok, index = pcall(spec.GetSpecialization)
		if ok and type(index) == "number" and not (issecretvalue and issecretvalue(index)) and index > 0 then
			local okInfo, id = pcall(spec.GetSpecializationInfo, index)
			if okInfo and type(id) == "number" and not (issecretvalue and issecretvalue(id)) then specID = id end
		end
	end
	return ("%s-%d"):format(class or "UNKNOWN", specID)
end

-- The same class and specialization in the player's words: the game's
-- localized names ("Warrior", "Arms Warrior"), never the key above.
local function SpecLabel()
	local className = UnitClass("player")
	if type(className) ~= "string" or (issecretvalue and issecretvalue(className)) then className = nil end
	local spec = C_SpecializationInfo
	if className and spec and type(spec.GetSpecialization) == "function" and type(spec.GetSpecializationInfo) == "function" then
		local ok, index = pcall(spec.GetSpecialization)
		if ok and type(index) == "number" and not (issecretvalue and issecretvalue(index)) and index > 0 then
			local okInfo, id, specName = pcall(spec.GetSpecializationInfo, index)
			if okInfo and type(id) == "number" and id > 0 and type(specName) == "string"
				and not (issecretvalue and issecretvalue(specName)) and specName ~= "" then
				return ("%s %s"):format(specName, className)
			end
		end
	end
	return className or L["your class"]
end

E:RegisterAddonSetup("CooldownManager", {
	title = "Cooldown Manager",
	key = SpecKey,
	keyLabel = SpecLabel,
	available = function()
		return CooldownViewerSettings ~= nil
	end,
	import = function(data)
		E:ShowCopyBox(L["EldoUI Cooldown Manager layout (%s)"]:format(SpecLabel()),
			L["Copy this string, open the Cooldown Manager settings, choose Import under Layouts and paste it."],
			data)
		return true
	end,
	restore = function()
		return false, L["Your own layout is still there: open the Cooldown Manager settings and choose it under Layouts."]
	end,
})
