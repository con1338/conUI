-- EldoUI profile rules: switch profile automatically by talent group
-- (dual spec) or by the content you are in (solo, party, raid, battleground),
-- so a healer layout and a damage layout can live side by side.
--
-- Rules live per character in EldoUIDB.profileRules[charKey]:
--   { enabled = false, spec = { [1] = "Profile", [2] = "Profile" },
--     content = { solo = "", party = "", raid = "", pvp = "" },
--     otherwise = "", home = "Profile" }
-- An empty entry means "no rule". A content rule wins over a spec rule;
-- when neither fits, `otherwise` is used, or when it is empty `home`: the
-- profile the player last picked by hand (or the one in use before a rule
-- first switched), so leaving a group goes back to it.
-- A profile picked by hand pauses the rules until the content or the
-- talent group changes, so the pick is not undone at the next loading
-- screen. Switching happens out of combat only; a change in combat waits.
--
-- Class defaults: EldoUIDB.classProfiles[classFile] = "Profile" is
-- the profile a NEW character of that class starts with, on its first login
-- with EldoUI. Characters that already have a profile are never switched.
local _, E = ...
local L = E.L

local CONTENT = {
	{ key = "solo", label = "Solo", desc = "Profile to use when you are solo." },
	{ key = "party", label = "Party or dungeon", desc = "Profile to use in a party or dungeon." },
	{ key = "raid", label = "Raid", desc = "Profile to use in a raid group or raid instance." },
	{ key = "pvp", label = "Battleground", desc = "Profile to use in battlegrounds and arenas." },
}

local function Rules()
	EldoUIDB.profileRules = EldoUIDB.profileRules or {}
	local rules = EldoUIDB.profileRules[E.charKey]
	if not rules then
		rules = { enabled = false, spec = {}, content = {} }
		EldoUIDB.profileRules[E.charKey] = rules
	end
	rules.spec = rules.spec or {}
	rules.content = rules.content or {}
	return rules
end

---------------------------------------------------------------------------
-- Class defaults for new characters
---------------------------------------------------------------------------
local function ClassProfiles()
	EldoUIDB.classProfiles = EldoUIDB.classProfiles or {}
	return EldoUIDB.classProfiles
end

-- Playable classes on this client: { { file = "WARRIOR", name = "Warrior" }, ... }.
local classList
local function Classes()
	if classList then return classList end
	classList = {}
	if C_CreatureInfo and C_CreatureInfo.GetClassInfo then
		for id = 1, 30 do
			local info = C_CreatureInfo.GetClassInfo(id)
			if type(info) == "table" and type(info.classFile) == "string" then
				table.insert(classList, { file = info.classFile, name = info.className or info.classFile })
			end
		end
	end
	table.sort(classList, function(a, b) return a.name < b.name end)
	return classList
end

local function PlayerClass()
	local _, classFile = UnitClass("player")
	return classFile
end

-- True when this character already had an EldoUI profile before this login:
-- under its current key, or under an older key (its first name alone, or
-- the key with the Forever surname) whose records its GUID owns. A new
-- character that only shares a first name is not known.
local function KnownCharacter()
	if type(EldoUIDB) ~= "table" or type(EldoUIDB.profileKeys) ~= "table" then return false end
	local realm = GetRealmName()
	local keys = EldoUIDB.profileKeys
	if E.CurrentCharacterKey and keys[E:CurrentCharacterKey()] then return true end
	if not (E.OwnsOlderCharacterKey and E:OwnsOlderCharacterKey()) then return false end
	if keys[("%s - %s"):format(E:PlayerName(), realm)] then return true end
	local oldName = UnitName("player")
	if type(oldName) == "string" and not (issecretvalue and issecretvalue(oldName)) and keys[("%s - %s"):format(oldName, realm)] then
		return true
	end
	return false
end

-- At the database start a character seen for the first time takes its
-- class's default profile, if one is set and still exists. Whether the
-- character is new is read before the profile loads, which records it.
local knownCharacter, hadSettings = true, true

E:OnDatabaseLoad(function()
	knownCharacter = KnownCharacter()
	hadSettings = type(EldoUIDB) == "table"
end, "before")

E:OnDatabaseLoad(function(self)
	if knownCharacter or not hadSettings then return end
	local classFile = PlayerClass()
	local wanted = classFile and ClassProfiles()[classFile]
	if type(wanted) == "string" and wanted ~= "" and EldoUIDB.profiles[wanted] and wanted ~= self.profileName then
		self:SetProfile(wanted, true)
		self.classProfileApplied = wanted
	end
end, "after")

function E:SetClassProfile(classFile, profile)
	if not classFile then return end
	ClassProfiles()[classFile] = (profile and profile ~= "") and profile or nil
end

-- The profile a new character of the class starts with, or nil
-- (classFile: the player's class when left out).
function E:GetClassProfile(classFile)
	classFile = classFile or PlayerClass()
	local name = classFile and ClassProfiles()[classFile]
	if type(name) == "string" and name ~= "" and EldoUIDB.profiles[name] then return name end
	return nil
end

-- True when `name` is the profile the class rule gives this character's class.
function E:IsClassProfile(name)
	return name ~= nil and self:GetClassProfile() == name
end

local function SpecGroup()
	if C_SpecializationInfo and C_SpecializationInfo.GetActiveSpecGroup then
		return C_SpecializationInfo.GetActiveSpecGroup() or 1
	end
	return 1
end

local function NumSpecGroups()
	return GetNumSpecGroups and GetNumSpecGroups() or 1
end

local function Content()
	local _, instanceType = IsInInstance()
	if instanceType == "pvp" or instanceType == "arena" then return "pvp" end
	if instanceType == "raid" or IsInRaid() then return "raid" end
	if instanceType == "party" or IsInGroup() then return "party" end
	return "solo"
end

local function Usable(name)
	return type(name) == "string" and name ~= "" and EldoUIDB.profiles[name] ~= nil
end

-- The profile the rules ask for right now, or nil.
function E:WantedProfile()
	local rules = Rules()
	if not rules.enabled then return nil end
	local wanted = rules.content[Content()]
	if not Usable(wanted) then wanted = rules.spec[SpecGroup()] end
	if not Usable(wanted) then wanted = rules.otherwise end
	if not Usable(wanted) then wanted = rules.home end
	if not Usable(wanted) then return nil end
	return wanted
end

-- A profile picked by hand holds until the content or the talent group
-- changes (this session only).
local paused
local ruleSwitching, loggedIn = false, false

local function State()
	return Content() .. ":" .. tostring(SpecGroup())
end

function E:ProfileRulesOn()
	return type(EldoUIDB) == "table" and Rules().enabled == true
end

function E:ProfileRulesPaused()
	return paused ~= nil
end

-- Apply the rules now, over a profile picked by hand (the rules page
-- after a change).
function E:ResumeProfileRules()
	paused = nil
	self:CheckProfileRules()
end

function E:CheckProfileRules()
	self:RunOutOfCombat(function()
		if paused then
			if paused == State() then return end
			paused = nil
		end
		local wanted = self:WantedProfile()
		if wanted and wanted ~= self.profileName then
			local rules = Rules()
			if not Usable(rules.home) then rules.home = self.profileName end
			ruleSwitching = true
			local ok, err = pcall(self.SetProfile, self, wanted)
			ruleSwitching = false
			if not ok then geterrorhandler()(err) end
			if self.RefreshConfig then self:RefreshConfig() end
			-- The first switch a rule makes explains itself once.
			if self.Tour then self.Tour:Offer("profile:rule", wanted) end
		end
	end, "profileRules")
end

-- Every switch the rules did not make is the player's own pick: it
-- becomes the profile to go back to, and with the rules on it holds until
-- the content or the talent group changes.
local SetProfile = E.SetProfile
function E:SetProfile(name, ...)
	local result = SetProfile(self, name, ...)
	-- Only a character with rules keeps a pick: one that never set rules
	-- gets no rules entry from a profile switch.
	local all = loggedIn and not ruleSwitching and self.profileName == name and type(EldoUIDB) == "table"
		and rawget(EldoUIDB, "profileRules")
	if type(all) == "table" and type(all[self.charKey]) == "table" then
		local rules = Rules()
		-- With the rules off a pick only keeps an earlier return profile
		-- current; otherwise the first switch a rule makes records it.
		if rules.enabled or rules.home ~= nil then rules.home = name end
		if rules.enabled then
			local was = paused
			paused = State()
			if not was and self.ConfigNotice then
				self:ConfigNotice(L["Profile rules wait until your content or talent group changes, so your pick stays."])
			end
		end
	end
	return result
end

local function Check() E:CheckProfileRules() end

E:RegisterEvent("PLAYER_LOGIN", function()
	loggedIn = true
	if E.classProfileApplied then
		E:Print(L["New character: using the %s class profile %s (/eui > Profile rules)."]:format(
			tostring((UnitClass("player"))), E:Highlight(E.classProfileApplied)))
	end
	E:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED", Check, Rules)
	E:RegisterEvent("PLAYER_ENTERING_WORLD", Check, Rules)
	E:RegisterEvent("GROUP_ROSTER_UPDATE", Check, Rules)

	local proxy = {}
	local function Profiles()
		local values = { [""] = L["No rule"] }
		for _, name in ipairs(E:GetProfileList()) do values[name] = name end
		return E:RawValues(values)
	end
	local options = {
		{ type = "description", label = L["Switch profile by talent group or by kind of content. A content rule wins over a talent group rule. Switching waits until you leave combat."] },
		{ type = "toggle", key = "enabled", label = L["Switch profiles automatically"], desc = L["Use the rules below when your talent group or content changes."] },
		{ type = "header", label = L["Talent groups"] },
	}
	for group = 1, math.max(NumSpecGroups(), 2) do
		table.insert(options, { type = "select", key = "spec." .. group, label = L["Talent group %d"]:format(group),
			desc = L["Profile to use while this talent group is active."], values = Profiles, dependsOn = "enabled" })
	end
	table.insert(options, { type = "header", label = L["Content"] })
	for _, entry in ipairs(CONTENT) do
		table.insert(options, { type = "select", key = "content." .. entry.key, label = L[entry.label],
			desc = L[entry.desc], values = Profiles, dependsOn = "enabled" })
	end
	table.insert(options, { type = "select", key = "otherwise", label = L["Otherwise use"],
		desc = L["Profile to use when no rule above fits, such as solo with only a Party rule."], dependsOn = "enabled",
		values = function()
			local values = { [""] = L["The profile you last picked"] }
			for _, name in ipairs(E:GetProfileList()) do values[name] = name end
			return E:RawValues(values)
		end })
	table.insert(options, { type = "header", label = L["New characters"] })
	table.insert(options, { type = "description", label = L["The profile a new character of each class starts with on its first login with EldoUI. Characters that already have a profile keep it."] })
	for _, class in ipairs(Classes()) do
		table.insert(options, { type = "select", key = "class." .. class.file, label = class.name,
			desc = L["Profile a new %s starts with."]:format(class.name), values = Profiles })
	end
	E:RegisterConfigPage("profilerules", L["Profile rules"], options,
		function()
			local rules = Rules()
			proxy.class = proxy.class or {}
			for _, class in ipairs(Classes()) do proxy.class[class.file] = ClassProfiles()[class.file] or "" end
			proxy.enabled = rules.enabled
			proxy.spec = proxy.spec or {}
			proxy.content = proxy.content or {}
			for group = 1, math.max(NumSpecGroups(), 2) do proxy.spec[group] = rules.spec[group] or "" end
			for _, entry in ipairs(CONTENT) do proxy.content[entry.key] = rules.content[entry.key] or "" end
			proxy.otherwise = rules.otherwise or ""
			return proxy
		end,
		function()
			local rules = Rules()
			rules.enabled = proxy.enabled and true or false
			for group, name in pairs(proxy.spec) do rules.spec[group] = name end
			for key, name in pairs(proxy.content) do rules.content[key] = name end
			rules.otherwise = proxy.otherwise
			for classFile, name in pairs(proxy.class or {}) do E:SetClassProfile(classFile, name) end
			-- New rules apply now, even over a pick made by hand.
			E:ResumeProfileRules()
		end, 98.5)
end, Rules, "modules")

E:AddCommand("profilerules", "on | off  switch profiles by talent group and content", function(arg)
	local rules = Rules()
	arg = (arg or ""):lower()
	if arg == "on" or arg == "off" then rules.enabled = arg == "on" end
	E:Print((rules.enabled and L["Profile rules are on. Set them in /eui > Profile rules."] or L["Profile rules are off. Set them in /eui > Profile rules."]))
	Check()
end, "Profiles & sharing")

E:AddCommand("classprofile", "[<profile> | none]  the profile new characters of your class start with", function(arg)
	arg = strtrim(arg or "")
	local classFile = PlayerClass()
	local className = tostring((UnitClass("player")))
	if arg == "" then
		local current = ClassProfiles()[classFile]
		E:Print(current and L["New %s characters start with profile %s."]:format(className, E:Highlight(current))
			or L["New %s characters start with the Default profile."]:format(className))
		return
	end
	if arg:lower() == "none" then
		E:SetClassProfile(classFile, nil)
		E:Print(L["New %s characters start with the Default profile."]:format(className))
		return
	end
	if not EldoUIDB.profiles[arg] then
		E:Print(L["There is no profile %q. /eui profile list shows them."]:format(arg))
		return
	end
	E:SetClassProfile(classFile, arg)
	E:Print(L["New %s characters start with profile %s."]:format(className, E:Highlight(arg)))
end, "Profiles & sharing")
