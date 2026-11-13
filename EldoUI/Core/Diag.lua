-- EldoUI diagnostics: /eui diag prints what EldoUI sees right now, to help
-- explain "why does this bar show nothing in combat".
--   * client build, EldoUI version, profile, layout and UI scale
--   * which modules are on, off, or held back by another addon
--   * which addon restrictions the client has active (combat, encounter,
--     challenge mode, PvP match, map, chat) and whether it marks auras or
--     cooldowns secret
--   * which game values are secret at this moment, for the player, a group
--     member and a nameplate (Midnight rules hide some combat values from
--     addons; EldoUI then shows Blizzard's own text), and the same report
--     taken automatically at the start of your last fight
--   * how many Blizzard elements EldoUI may change, and errors this session
--
--   /eui diag          print the report
--   /eui diag copy     the report in a copy box, for a bug report
--   /eui diag force    switch the client's test CVar that forces combat
--                      restrictions without a fight (only by this command;
--                      EldoUI warns at login while it is on)
-- The report only reads: it tests values with issecretvalue/canaccessvalue
-- and never works around a secret.
--
-- Modules and plugins add their own rows at the end of the report:
--   E:RegisterDiagnostics("Name", function() return { "line", ... } end)
-- (or E:RegisterDiagnostics(fn)); a failing provider adds one error line.
local _, E = ...
local L = E.L

-- The client's test switch for combat restrictions. Forever 1.60.1 has the
-- first one; Retail 12.0.5+ has the second. Whichever exists is used.
local FORCE_CVARS = { "addonCombatRestrictionsForced", "secretCombatRestrictionsForced" }

local IsSecret = E.Secret

local function CanAccess(value)
	if canaccessvalue then return canaccessvalue(value) and true or false end
	return not IsSecret(value)
end

local function Mark(value)
	if IsSecret(value) then
		return CanAccess(value) and E:TextHex("warn") .. "secret|r" or E:TextHex("warn") .. "secret, no access|r"
	end
	return E:TextHex("good") .. "readable|r"
end

-- The first unit of a kind that exists, e.g. a visible nameplate.
local function FirstUnit(prefix, count)
	for index = 1, count do
		local unit = prefix .. index
		local exists = UnitExists(unit)
		if not IsSecret(exists) and exists then return unit end
	end
end

local function GroupUnit()
	if IsInRaid() then return FirstUnit("raid", 40) end
	if IsInGroup() then return FirstUnit("party", 4) end
end

local function PlateUnit()
	return FirstUnit("nameplate", 40)
end

-- Each probe returns one value from the game; nil means "nothing to test".
local PROBES = {
	{ "Player health", function() return UnitHealth("player") end },
	{ "Player max health", function() return UnitHealthMax("player") end },
	{ "Player power", function() return UnitPower("player") end },
	{ "Target health", function() return UnitExists("target") and UnitHealth("target") or nil end },
	{ "Target name", function() return UnitExists("target") and UnitName("target") or nil end },
	{ "Target cast", function()
		if not UnitExists("target") then return nil end
		local name = UnitCastingInfo("target")
		return name
	end },
	{ "Player threat", function()
		return UnitExists("target") and UnitThreatSituation and UnitThreatSituation("player", "target") or nil
	end },
	{ "Group member health", function()
		local unit = GroupUnit()
		return unit and UnitHealth(unit) or nil
	end },
	{ "Group member name", function()
		local unit = GroupUnit()
		return unit and UnitName(unit) or nil
	end },
	{ "Nameplate health", function()
		local unit = PlateUnit()
		return unit and UnitHealth(unit) or nil
	end },
	{ "Nameplate name", function()
		local unit = PlateUnit()
		return unit and UnitName(unit) or nil
	end },
	{ "First buff", function()
		local aura = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex and C_UnitAuras.GetAuraDataByIndex("player", 1, "HELPFUL")
		return aura and aura.spellId
	end },
	{ "Global cooldown", function()
		local info = C_Spell and C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(29515)
		return info and info.startTime
	end },
}

-- Probe results as text: { { label, text } }.
local function RunProbes()
	local results = {}
	for _, probe in ipairs(PROBES) do
		local ok, value = pcall(probe[2])
		local text
		if not ok then
			text = E:TextHex("secondary") .. "not available|r" -- no-L: diagnostics report stays English for bug reports
		elseif type(value) == "nil" then
			text = E:TextHex("secondary") .. "nothing to test|r" -- no-L: diagnostics report stays English for bug reports
		else
			text = Mark(value)
		end
		table.insert(results, { probe[1], text })
	end
	return results
end

-- Which restrictions the client reports as active.
local function Restrictions()
	local list = {}
	local types = Enum.AddOnRestrictionType
	local restricted = C_RestrictedActions
	if types and restricted and restricted.IsAddOnRestrictionActive then
		local names = {}
		for name, value in pairs(types) do table.insert(names, { name, value }) end
		table.sort(names, function(a, b) return a[2] < b[2] end)
		for _, entry in ipairs(names) do
			local ok, active = pcall(restricted.IsAddOnRestrictionActive, entry[2])
			if ok then
				table.insert(list, { entry[1], active and E:TextHex("warn") .. "active|r" or E:TextHex("good") .. "off|r" })
			end
		end
	end
	local secrets = C_Secrets
	if secrets then
		for _, check in ipairs({
			{ "Secret restrictions", "HasSecretRestrictions" },
			{ "Auras secret", "ShouldAurasBeSecret" },
			{ "Cooldowns secret", "ShouldCooldownsBeSecret" },
		}) do
			local fn = secrets[check[2]]
			if fn then
				local ok, value = pcall(fn)
				if ok then table.insert(list, { check[1], value and E:TextHex("warn") .. "yes|r" or E:TextHex("good") .. "no|r" }) end
			end
		end
	end
	return list
end

---------------------------------------------------------------------------
-- The test CVar
---------------------------------------------------------------------------
local function ForceCVar()
	if not (C_CVar and C_CVar.GetCVar) then return nil end
	for _, name in ipairs(FORCE_CVARS) do
		local ok, value = pcall(C_CVar.GetCVar, name)
		if ok and type(value) == "string" and not IsSecret(value) then return name, value == "1" end
	end
end

function E:ToggleForcedRestrictions()
	local name, on = ForceCVar()
	if not name then
		self:Print(L["This client has no test switch for combat restrictions."])
		return
	end
	if on then
		local snapshot = EldoUIDB and EldoUIDB.cvarSnapshot and EldoUIDB.cvarSnapshot[name]
		if snapshot and snapshot.owner == "diag" then
			self:RestoreCVar(name, "diag")
			self:Print(L["Forced combat restrictions are off again (%s)."]:format(name))
		else
			self:Print(L["%s was switched on outside EldoUI. Type %s to switch it off."]:format(name, E:Highlight(("/console %s 0"):format(name))))
		end
		return
	end
	if InCombatLockdown() then
		self:Print(L["Switch the test restrictions on out of combat."])
		return
	end
	self:SetCVar(name, "1", "diag")
	self:Print(L["Forced combat restrictions are %s (%s): the client acts as if you were in combat. %s switches it off; it stays on after a reload until you do."]:format(E:TextHex("warn") .. L["on"] .. "|r", name, E:Highlight("/eui diag force")))
end

---------------------------------------------------------------------------
-- Snapshot at the start of a fight, so the report can show both states.
---------------------------------------------------------------------------
local combatSnapshot

local function TakeCombatSnapshot()
	if not InCombatLockdown() then return end
	combatSnapshot = {
		time = date("%H:%M:%S"),
		probes = RunProbes(),
		restrictions = Restrictions(),
	}
end

E:RegisterEvent("PLAYER_REGEN_DISABLED", function()
	-- A moment later, so the client has applied the combat rules.
	C_Timer.After(1, TakeCombatSnapshot)
end, PROBES)

E:RegisterEvent("PLAYER_LOGIN", function()
	local name, on = ForceCVar()
	if on then
		E:Print(L["%s: the client acts as if you were always in combat. %s switches it off."]:format(E:TextHex("warn") .. L["Test switch %s is on"]:format(name) .. "|r", E:Highlight("/eui diag force")))
	end
end, FORCE_CVARS, "modules")

---------------------------------------------------------------------------
-- Report
---------------------------------------------------------------------------
local function Line(lines, label, value)
	table.insert(lines, ("   %s: %s"):format(label, tostring(value)))
end

-- Extra rows from modules and plugins, in registration order.
local providers = {}

function E:RegisterDiagnostics(name, fn)
	if type(name) == "function" then name, fn = nil, name end
	assert(type(fn) == "function", "EldoUI:RegisterDiagnostics([name,] fn): fn must be a function")
	name = name or ("provider" .. (#providers + 1))
	for _, provider in ipairs(providers) do
		if provider.name == name then
			provider.fn = fn
			return
		end
	end
	providers[#providers + 1] = { name = name, fn = fn }
end

-- The whole report as lines (with color codes).
function E:GetDiagnosticsLines()
	local lines = {}
	local version, build, _, toc = GetBuildInfo()
	table.insert(lines, ("Diagnostics, %s"):format(date("%Y-%m-%d %H:%M")))
	Line(lines, "Client", ("%s (%s), interface %s"):format(version or "?", build or "?", toc or "?"))
	Line(lines, "EldoUI", ("v%s, profile " .. E:TextHex("accent") .. "%s|r, layout " .. E:TextHex("accent") .. "%s|r"):format(self.version, self.profileName or "?", self.db and self.db.general.layout or "?"))
	-- The layout the frames are placed by, and why when it is not the saved one.
	if self.db and self.EffectiveLayout then
		local requested = self.db.general.layout
		local used, reason = self:EffectiveLayout()
		local text = self:LayoutIdentity(used)
		if reason == "missing" then
			text = L["%s is not installed; frames use %s until a layout is picked"]:format(tostring(requested), self:LayoutTitle(used))
		elseif reason == "alias" then
			text = L["%s is placed as %s"]:format(tostring(requested), self:LayoutTitle(used))
		end
		Line(lines, "Layout in use", text)
		for _, entry in ipairs(self.layoutCatalogReport or {}) do Line(lines, "Layout update", entry) end
	end
	Line(lines, "UI scale", ("%s (UIParent %dx%d)"):format(tostring(self.db and self.db.general.uiScale or "?"), UIParent:GetWidth(), UIParent:GetHeight()))
	Line(lines, "In combat", InCombatLockdown() and "yes" or "no")
	local _, instanceType = IsInInstance()
	Line(lines, "Where", ("%s%s"):format(instanceType or "none", IsInRaid() and ", raid group" or IsInGroup() and ", party" or ""))
	local cvar, forced = ForceCVar()
	if cvar then Line(lines, "Forced restrictions", forced and (E:TextHex("warn") .. "on|r (" .. cvar .. ")") or "off (/eui diag force)") end

	local on, off, held = {}, {}, {}
	for name, module in self:IterateModules() do
		if module.active then
			on[#on + 1] = name
		elseif module:IsEnabled() and self:GetModuleConflict(module) then
			held[#held + 1] = ("%s (%s)"):format(name, select(2, self:GetModuleConflict(module)))
		else
			off[#off + 1] = name
		end
	end
	Line(lines, "Modules on", #on)
	if #held > 0 then Line(lines, "Held back by another addon", table.concat(held, ", ")) end
	if #off > 0 then Line(lines, "Modules off", table.concat(off, ", ")) end
	-- Other addons doing an EldoUI job, and who does it now.
	local found = {}
	for _, row in ipairs(self.DetectedAddons and self:DetectedAddons() or {}) do
		found[#found + 1] = ("%s: %s (%s)"):format(self:CompetitorJobText(row), row.title, row.state)
	end
	if #found > 0 then Line(lines, "Other addons", table.concat(found, ", ")) end

	if self.blizzardElementOrder then
		local changed = 0
		for _, id in ipairs(self.blizzardElementOrder) do
			if self:BlizzardAllowed(id) then changed = changed + 1 end
		end
		Line(lines, "Blizzard elements EldoUI may change", ("%d of %d (/eui blizz)"):format(changed, #self.blizzardElementOrder))
	end

	local restrictions = Restrictions()
	if #restrictions > 0 then
		table.insert(lines, "   " .. E:TextHex("accent") .. "Addon restrictions right now|r")
		for _, entry in ipairs(restrictions) do Line(lines, entry[1], entry[2]) end
	end

	table.insert(lines, "   " .. E:TextHex("accent") .. "Secret values right now|r")
	for _, entry in ipairs(RunProbes()) do Line(lines, entry[1], entry[2]) end

	if combatSnapshot then
		table.insert(lines, ("   " .. E:TextHex("accent") .. "At the start of your last fight (%s)|r"):format(combatSnapshot.time))
		for _, entry in ipairs(combatSnapshot.restrictions) do Line(lines, entry[1], entry[2]) end
		for _, entry in ipairs(combatSnapshot.probes) do Line(lines, entry[1], entry[2]) end
	else
		table.insert(lines, "   " .. E:TextHex("secondary") .. "Fight something (or use /eui diag force) and run /eui diag again to see the in-combat values too.|r")
	end

	-- The log lives in EldoUIErrorsDB.entries (Core/Errors.lua).
	local log = E.errors
	if log and type(log.entries) == "table" then
		local text = ("%d (/eui errors)"):format(#log.entries) -- no-L: diagnostics report stays English for bug reports
		if (log.dropped or 0) > 0 then text = text .. (", %d more skipped this session (too many at once)"):format(log.dropped) end
		Line(lines, "Saved errors", text)
	end

	for _, provider in ipairs(providers) do
		local ok, extra = pcall(provider.fn)
		if not ok then
			Line(lines, provider.name, E:TextHex("warn") .. "error: " .. tostring(extra) .. "|r")
		elseif type(extra) == "table" then
			for _, line in ipairs(extra) do table.insert(lines, tostring(line)) end
		end
	end
	return lines
end

-- Plain text (no color codes), for bug reports.
function E:GetDiagnosticsText()
	local text = table.concat(self:GetDiagnosticsLines(), "\n")
	return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

function E:PrintDiagnostics()
	local lines = self:GetDiagnosticsLines()
	self:Print(lines[1])
	for index = 2, #lines do print(lines[index]) end
end

E:AddCommand("diag", "[copy | force]  version, modules, restrictions and secret values; copy = for a bug report; force = test switch for combat restrictions", function(arg)
	arg = strtrim(arg or ""):lower()
	if arg == "force" then
		E:ToggleForcedRestrictions()
	elseif arg == "copy" then
		E:ShowCopyBox(L["EldoUI diagnostics"], L["Selected: press Ctrl+C and paste it into your bug report."], E:GetDiagnosticsText())
	else
		E:PrintDiagnostics()
	end
end, "Tools")
