-- EldoUI roles: one choice of role (melee, ranged, healer, tank) adds a
-- small layer over the chosen layout and styles, plus an optional class
-- layer and, for healers, click-cast bindings the player confirms.
-- The data is in Data/RoleProfiles.lua.
--
--   E:GetRole()                       "none", "melee", "ranged", "healer" or
--                                     "tank" (an older "damage" reads as the
--                                     class's damage role)
--   E:GetRoleGroup()                  the role as "none", "damage", "healer"
--                                     or "tank", for data written for the
--                                     three older roles
--   E:ResolveRoleKey(role[, class])   a role key or "none"; nil for a name
--                                     EldoUI doesn't know
--   E:RoleGroup(role)                 "damage" for melee and ranged (and the
--                                     older "damage"), else the role itself
--   E:DetectRole()                    the role the game suggests (spec, group
--                                     role, class), only to pre-select
--   E:GetRolePoints(role[, layout[, spot]])
--                                     mover -> point the role uses there
--   E:GetHealerSpot()                 where the healer role puts the group
--                                     frames: "side" or "bottom"
--   E:SetHealerSpot(spot)             pick it (applies at once for a healer)
--   E:GetRoleMoverPoint(name)         the role's point for a mover now (scaled
--                                     like a layout point), or nil
--   E:GetRoleClassLayer([class])      the class layer, or nil
--   E:GetRoleClickCast()              click-cast suggestions from the spellbook
--   E:ApplyRole(role, opts)           opts: classLayer (bool), bindings (list
--                                     from GetRoleClickCast the player ticked)
--   E:BindRoleClickCast(list)         create those bindings (ClickCast module)
--
-- Rules:
--   * Everything runs through E:RunOutOfCombat: nothing moves in combat.
--   * A role only changes what it names. Switching role first puts back the
--     values the previous role changed, unless the player changed them
--     since. A frame the player dragged keeps its place.
--   * Role positions are defaults, like layout points: Core/Movers.lua asks
--     E:GetRoleMoverPoint before the layout's point, so they follow the
--     screen and the scale and are never saved as dragged positions.
--   * The encounter zone, the countdown and the cast bar never move by role
--     (E.roleProtectedMovers).
--   * Detection only pre-selects. Nothing changes until the player picks a
--     role in the installer or on the Role page.
--   * Click-cast bindings are only made from the list the player ticked.
--   * A profile saved with the older "damage" role gets its class's damage
--     role written in once ("roles:four"); the old name is kept next to it
--     in general.roleLegacy and nothing else changes.
local _, E = ...
local L = E.L

E.defaults.general.role = "none"       -- the role layer in use
E.defaults.general.roleClass = false   -- the class layer is on
E.defaults.general.roleMovers = {}     -- old saves only: mover -> point a role wrote in older versions
E.defaults.general.roleRestore = {}    -- module -> path -> { old, set } to undo the role's settings
E.defaults.general.healerSpot = "side" -- healer group frames: "side" (beside the center) or "bottom"

local GROUP_ROLE = { TANK = "tank", HEALER = "healer", DAMAGER = "damage" }

local Secret = E.Secret

local function PlayerClass()
	local _, class = UnitClass("player")
	if Secret(class) then return nil end
	return class
end

function E:ResolveRoleKey(role, class)
	if role == "none" then return "none" end
	if type(role) ~= "string" then return nil end
	if self.roleProfiles[role] then return role end
	local alias = self.roleAliases[role]
	if not alias then return nil end
	if self.roleGroups[alias] == "damage" then
		local own = self.roleClassDamage[class or PlayerClass() or ""]
		if own and self.roleProfiles[own] then return own end
	end
	return self.roleProfiles[alias] and alias or nil
end

function E:RoleGroup(role)
	local key = self:ResolveRoleKey(role)
	if not key or key == "none" then return "none" end
	return self.roleGroups[key] or key
end

function E:GetRole()
	return self:ResolveRoleKey(self.db.general.role) or "none"
end

function E:GetRoleGroup()
	return self:RoleGroup(self:GetRole())
end

-- The role the game suggests: the spec's role, then the group role, then
-- what the class can do. Returns the key and where it came from.
function E:DetectRole()
	local spec = C_SpecializationInfo
	if spec and type(spec.GetSpecialization) == "function" and type(spec.GetSpecializationInfo) == "function" then
		local ok, index = pcall(spec.GetSpecialization)
		if ok and type(index) == "number" and not Secret(index) and index > 0 then
			local okInfo, _, _, _, _, role = pcall(spec.GetSpecializationInfo, index)
			if okInfo and not Secret(role) and GROUP_ROLE[role] then return self:ResolveRoleKey(GROUP_ROLE[role]), "spec" end
		end
	end
	if type(UnitGroupRolesAssigned) == "function" then
		local ok, role = pcall(UnitGroupRolesAssigned, "player")
		if ok and not Secret(role) and GROUP_ROLE[role] then return self:ResolveRoleKey(GROUP_ROLE[role]), "group" end
	end
	local class = PlayerClass()
	if class and self.roleClassDefault[class] then return self.roleClassDefault[class], "class" end
	return nil
end

function E:GetRoleClassLayer(class)
	return self.roleClassLayers[class or PlayerClass() or ""]
end

---------------------------------------------------------------------------
-- Positions
---------------------------------------------------------------------------
-- Where the healer role puts the group frames. A spot the role data does
-- not offer reads as "side".
function E:GetHealerSpot()
	local spot = self.db and self.db.general.healerSpot
	local spots = self.roleProfiles.healer and self.roleProfiles.healer.spots
	if type(spot) ~= "string" or not (spots and spots[spot]) then return "side" end
	return spot
end

-- The spot's data when the role uses one other than "side" in this layout.
local function RoleSpot(self, role, layoutKey, spotKey)
	local profile = self.roleProfiles[role]
	if role ~= "healer" or not (profile and profile.spots) then return nil end
	layoutKey = layoutKey or self.db.general.layout
	spotKey = spotKey or self:GetHealerSpot()
	local spot = profile.spots[spotKey]
	if spotKey == "side" or not spot then return nil end
	if not (spot.layouts and spot.layouts[layoutKey]) then return nil end
	return spot
end

-- The raid uses one of the larger raid sizes (Group Frames' Mid or Large
-- raid settings), so the bottom spot hands it to the side spot.
local function LargeRaid(self)
	local frames = self.modules.GroupFrames
	return frames and frames.raidKey ~= nil and frames.raidKey ~= "raid" or false
end

-- The role's points for a layout: the role's own, then the layout's
-- exceptions, then the healer spot's. Protected movers are never in the
-- result. spotKey: the healer spot to read (default the profile's).
function E:GetRolePoints(role, layoutKey, spotKey)
	local profile = self.roleProfiles[role]
	local out = {}
	if not profile then return out end
	local key = layoutKey or self.db.general.layout
	local layout = self.layouts[key]
	if layout and layout.imported and layout.inheritanceVersion == 1 and type(layout.rolePoints) == "table" then
		-- Imported placements already removed their own role overrides from
		-- this snapshot. Falling back to the global layer would put them back.
		for name, point in pairs(type(layout.rolePoints[role]) == "table" and layout.rolePoints[role] or {}) do out[name] = point end
	else
		for name, point in pairs(profile.points or {}) do out[name] = point end
		local extra = profile.layouts and profile.layouts[key]
		for name, point in pairs(extra or {}) do out[name] = point end
		local spot = RoleSpot(self, role, key, spotKey)
		if spot then
			local side = out.EldoUI_Raid
			for name, point in pairs(spot.layouts[key]) do out[name] = point end
			if side and LargeRaid(self) then out.EldoUI_Raid = side end
		end
	end
	for name in pairs(self.roleProtectedMovers) do out[name] = nil end
	return out
end

local function SamePoint(a, b)
	if type(a) ~= "table" or type(b) ~= "table" then return false end
	for index = 1, 5 do
		if a[index] ~= b[index] then return false end
	end
	return true
end

-- In older versions a role wrote fixed numbers into the dragged positions
-- (general.roleMovers kept a copy). Those that still match are dropped, so
-- the frame follows the role point again; one the player dragged since stays.
local function DropRoleMovers()
	local general = E.db.general
	if not next(general.roleMovers) then return end
	for name, point in pairs(general.roleMovers) do
		if SamePoint(E.db.movers[name], point) then E.db.movers[name] = nil end
	end
	wipe(general.roleMovers)
end
E.DropOldRoleMovers = DropRoleMovers

-- The point the current role gives `name` in the current layout, scaled
-- like the layout's own points (layout fit, refHeight; chained points keep
-- their gaps scaled the same way). nil when the role doesn't move it.
local rolePointCache = {}
function E:GetRoleMoverPoint(name)
	local general = self.db.general
	local role = self:GetRole()
	if role == "none" or self.roleProtectedMovers[name] then return nil end
	local layoutKey = general.layout
	local spot, large = self:GetHealerSpot(), LargeRaid(self)
	if rolePointCache.role ~= role or rolePointCache.layout ~= layoutKey or rolePointCache.record ~= self.layouts[layoutKey]
		or rolePointCache.spot ~= spot or rolePointCache.large ~= large then
		rolePointCache.role, rolePointCache.layout, rolePointCache.record = role, layoutKey, self.layouts[layoutKey]
		rolePointCache.spot, rolePointCache.large = spot, large
		rolePointCache.points = self:GetRolePoints(role, layoutKey)
	end
	local point = rolePointCache.points[name]
	if not point then return nil end
	return self:ScaleLayoutPoint(point, self:GetLayoutRatio(self.layouts[layoutKey]))
end

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------
-- Nested settings -> { { path = { ... }, value = v }, ... }
local function Flatten(settings, prefix, out)
	for key, value in pairs(settings) do
		local path = { unpack(prefix) }
		path[#path + 1] = key
		if type(value) == "table" and not E.IsList(value) then
			Flatten(value, path, out)
		else
			out[#out + 1] = { path = path, value = value }
		end
	end
	return out
end

local function Walk(root, path, create)
	local node = root
	for index = 1, #path - 1 do
		if type(node[path[index]]) ~= "table" then
			if not create then return nil end
			node[path[index]] = {}
		end
		node = node[path[index]]
	end
	return node, path[#path]
end

-- The module has this setting (its defaults name it).
local function Known(module, path)
	local node, key = Walk(module.defaults or {}, path, false)
	return node ~= nil and node[key] ~= nil
end

local function Copy(value)
	if type(value) == "table" then return CopyTable(value) end
	return value
end

local function Same(a, b)
	if type(a) ~= type(b) then return false end
	if type(a) ~= "table" then return a == b end
	for key, value in pairs(a) do
		if not Same(value, b[key]) then return false end
	end
	for key in pairs(b) do
		if a[key] == nil then return false end
	end
	return true
end

local function RefreshModule(module)
	if module.active and module.OnProfileChanged then
		local ok, err = pcall(module.OnProfileChanged, module)
		if not ok then geterrorhandler()(err) end
	end
end

-- Put back what the last role (and class layer) changed. A value the
-- player changed since stays theirs.
local function RestoreSettings(touched)
	local restore = E.db.general.roleRestore
	for moduleName, saved in pairs(restore) do
		local module = E.modules[moduleName]
		if module and type(module.db) == "table" then
			for pathText, entry in pairs(saved) do
				local path = { strsplit(".", pathText) }
				local node, key = Walk(module.db, path, true)
				if Same(node[key], entry.set) then
					node[key] = Copy(entry.old)
					touched[module] = true
				end
			end
		end
	end
	wipe(restore)
end

local function ApplySettings(settings, touched)
	local restore = E.db.general.roleRestore
	for moduleName, values in pairs(settings or {}) do
		local module = E.modules[moduleName]
		if module and type(module.db) == "table" then
			for _, item in ipairs(Flatten(values, {}, {})) do
				if Known(module, item.path) then
					local node, key = Walk(module.db, item.path, true)
					local pathText = table.concat(item.path, ".")
					restore[moduleName] = restore[moduleName] or {}
					-- The first value seen is the one to go back to.
					if not restore[moduleName][pathText] then
						restore[moduleName][pathText] = { old = Copy(node[key]) }
					end
					node[key] = Copy(item.value)
					restore[moduleName][pathText].set = Copy(item.value)
					touched[module] = true
				end
			end
		end
	end
end

---------------------------------------------------------------------------
-- Click-casting
---------------------------------------------------------------------------
local function SpellKnown(id)
	if type(IsPlayerSpell) == "function" then
		local ok, known = pcall(IsPlayerSpell, id)
		if ok and not Secret(known) and known then return true end
	end
	if C_SpellBook and type(C_SpellBook.IsSpellKnown) == "function" then
		local ok, known = pcall(C_SpellBook.IsSpellKnown, id)
		if ok and not Secret(known) and known then return true end
	end
	return false
end

local function SpellName(id)
	if C_Spell and C_Spell.GetSpellInfo then
		local ok, info = pcall(C_Spell.GetSpellInfo, id)
		if ok and type(info) == "table" and type(info.name) == "string" and not Secret(info.name) then return info.name, info.iconID end
	end
end

-- The suggestions for this character, read live from the spellbook:
-- { mods, key, spellID, spell (name), icon, what, label, conflict }.
-- `conflict` names a binding the player already has on that click.
function E:GetRoleClickCast()
	local list = {}
	local class = PlayerClass()
	local clickCast = self.modules.ClickCast
	for _, entry in ipairs(self.roleClickCast[class or ""] or {}) do
		for _, id in ipairs(entry.spells) do
			local name, icon = SpellName(id)
			if name and SpellKnown(id) then
				local item = { mods = entry.mods, key = entry.key, spellID = id, spell = name, icon = icon, what = E:Translate(entry.what) }
				if clickCast and clickCast.db and clickCast.BindingLabel then
					item.label = clickCast:BindingLabel(item)
					local _, binding = clickCast:FindBinding(entry.key, entry.mods)
					if binding and not (binding.action == "spell" and binding.value == name) then
						item.conflict = binding.value or binding.action
					elseif binding then
						item.bound = true
					end
				end
				list[#list + 1] = item
				break
			end
		end
	end
	return list
end

-- Make the bindings the player ticked. Turns the Click Casting module on
-- when it is off (the player asked for click-casting).
function E:BindRoleClickCast(list)
	local clickCast = self.modules.ClickCast
	if not (clickCast and clickCast.SetBinding) or type(list) ~= "table" or #list == 0 then return 0 end
	local made = 0
	self:RunOutOfCombat(function()
		if not clickCast:IsEnabled() then self:SetModuleEnabled("ClickCast", true) end
		for _, item in ipairs(list) do
			if clickCast:SetBinding(item.key, item.mods, "spell", item.spell) then made = made + 1 end
		end
		if made > 0 then
		self:Print((made == 1 and L["Click-casting: %d binding set. Change it in /eui > Click Casting."]
			or L["Click-casting: %d bindings set. Change them in /eui > Click Casting."]):format(made))
	end
	end)
	return made
end

---------------------------------------------------------------------------
-- Apply
---------------------------------------------------------------------------
local roleCallbacks = {}

-- fn(role, classLayer) after a role was applied (for plugins).
function E:RegisterRoleCallback(fn)
	assert(type(fn) == "function", "EldoUI:RegisterRoleCallback(fn)")
	table.insert(roleCallbacks, fn)
end

-- opts.classLayer: nil keeps the current setting. opts.bindings: the
-- click-cast suggestions the player ticked.
function E:ApplyRole(role, opts)
	opts = opts or {}
	role = self:ResolveRoleKey(role)
	if not role then return false end
	self:RunOutOfCombat(function()
		local general = self.db.general
		local touched = {}
		RestoreSettings(touched)
		general.role = role
		if opts.classLayer ~= nil then general.roleClass = opts.classLayer and true or false end
		if role ~= "none" then
			ApplySettings(self.roleProfiles[role].settings, touched)
			local spot = RoleSpot(self, role)
			if spot then ApplySettings(spot.settings, touched) end
		end
		local layer = general.roleClass and self:GetRoleClassLayer()
		if layer then ApplySettings(layer.settings, touched) end
		for module in pairs(touched) do RefreshModule(module) end
		-- The role's frames move by their default points (E:GetRoleMoverPoint).
		DropRoleMovers()
		self:RefreshMovers()
		for _, fn in ipairs(roleCallbacks) do
			local ok, err = pcall(fn, role, general.roleClass)
			if not ok then geterrorhandler()(err) end
		end
	end)
	if opts.bindings then self:BindRoleClickCast(opts.bindings) end
	return true
end

-- Pick where the healer role puts the group frames ("side" or "bottom").
-- A healer gets it at once; another role keeps it for later.
function E:SetHealerSpot(spot)
	local spots = self.roleProfiles.healer and self.roleProfiles.healer.spots
	if type(spot) ~= "string" or not (spots and spots[spot]) then return false end
	self.db.general.healerSpot = spot
	if self:GetRole() == "healer" then self:ApplyRole("healer") end
	return true
end

-- A layout click drops dragged positions; the role's frames keep their
-- role points because those are defaults. Old saved role positions go
-- with the click too.
E:RegisterLayoutCallback(function()
	if next(E.db.general.roleMovers) then wipe(E.db.general.roleMovers) end
end)

-- Old saved role positions in a profile from before go when the saved
-- settings load and when the character switches to such a profile.
local function MigrateRoleMovers()
	if not (E.db and next(E.db.general.roleMovers)) then return end
	E:RunOutOfCombat(function()
		DropRoleMovers()
		E:RefreshMovers()
	end)
end
hooksecurefunc(E, "SetProfile", MigrateRoleMovers)
E:OnDatabaseLoad(MigrateRoleMovers, "after")

-- The update to four roles, once per profile ("roles:four" version 1). A
-- profile saved with the older "damage" role gets the damage role of the
-- character's class (Data/RoleProfiles.lua E.roleClassDamage); the old name
-- and the class stay in general.roleLegacy. Melee and Ranged keep every
-- frame where the older role had it, and the values the older role set
-- (general.roleRestore) stay as they are, so switching role later still
-- puts them back. Nothing else is written, moved or applied.
local function FourRolesUpdate(profile)
	local general = type(profile) == "table" and profile.general
	if type(general) ~= "table" then return end
	local old = general.role
	if type(old) ~= "string" or E.roleProfiles[old] or not E.roleAliases[old] then return end
	local class = PlayerClass()
	local role = E:ResolveRoleKey(old, class)
	if not role then return end
	if type(general.roleLegacy) ~= "table" then
		general.roleLegacy = { role = old, class = class, version = 1 }
	end
	general.role = role
end
E:RegisterProfileMigration(FourRolesUpdate, "roles:four", 1)

---------------------------------------------------------------------------
-- Role page in /eui
---------------------------------------------------------------------------
local ROLE_VALUES = { none = "No role" }
for _, key in ipairs(E.roleOrder) do ROLE_VALUES[key] = E.roleProfiles[key].title end

local SPOT_VALUES = {}
for _, key in ipairs(E.roleProfiles.healer and E.roleProfiles.healer.spotOrder or {}) do
	SPOT_VALUES[key] = E.roleProfiles.healer.spots[key].title
end

local proxy = {}

local function DetectedText()
	local role, source = E:DetectRole()
	if not role then return L["EldoUI can't tell your role from the game. Pick the one you play most."] end
	local text = source == "spec" and L["From your specialization, EldoUI suggests %s."]
		or source == "group" and L["From your group role, EldoUI suggests %s."]
		or L["From your class, EldoUI suggests %s."]
	return text:format(L[E.roleProfiles[role].title])
end

local function ClassLayerText()
	local layer = E:GetRoleClassLayer()
	if not layer then return L["Your class has no class details to add."] end
	-- The one-line text; the full list stays in the setup's Role step.
	local text = L["For your class: %s."]:format(layer.text:sub(1, 1):lower() .. layer.text:sub(2))
	if #text > 110 then return L["The setup's Role step lists them for your class."] end
	return text
end

E:RegisterEvent("PLAYER_LOGIN", function()
	if not E.RegisterConfigPage then return end
	local options = {
		{ type = "description", label = "A role moves a few frames on top of your layout: healers get group frames near the center, tanks get threat colors." },
		{ type = "select", key = "role", label = "Role", values = ROLE_VALUES,
			desc = function() return L["The role layer in use. No role leaves the layout as it is. Switching role puts back what the previous role changed, unless you changed it yourself since."] .. " " .. DetectedText() end },
		{ type = "select", key = "healerSpot", label = "Healer group frames", values = SPOT_VALUES,
			disabled = function()
				if proxy.role ~= "healer" then return L["Pick the Healer role to choose where its group frames go."] end
				if not RoleSpot(E, "healer", E.db.general.layout, "bottom") then return L["This layout keeps the healer group frames beside the center."] end
				return false
			end,
			desc = function()
				local spots = E.roleProfiles.healer.spots
				local spot = spots[proxy.healerSpot] or spots.side
				return L["Where the Healer role puts your party and raid frames. The cast bar and the cooldown rows stay where they are."] .. " " .. L[spot.desc]
			end },
		{ type = "toggle", key = "roleClass", label = "Class details",
			disabled = function() return not E:GetRoleClassLayer() and L["Your class has no class details to add."] or false end,
			desc = function() return L["Turn on the resources, reminders and spells your class uses, on top of the role."] .. " " .. ClassLayerText() end },
		{ type = "header", label = "Click-casting" },
		{ type = "description", label = "Healers can bind heals and dispels to modifier clicks on group frames. The setup suggests spells; check the ones you want." },
		{ type = "execute", label = "Set up click-casting",
			desc = "Opens the Role step of the setup with the suggested bindings for your class. Nothing is bound until you check it and click Apply.",
			func = function() E:ShowInstaller("role") end },
	}
	local page = E:RegisterConfigPage("role", "Role", options,
		function()
			proxy.role = E:GetRole()
			proxy.roleClass = E.db.general.roleClass and true or false
			proxy.healerSpot = E:GetHealerSpot()
			return proxy
		end,
		function()
			local spotChanged = proxy.healerSpot ~= E:GetHealerSpot()
			if spotChanged then E.db.general.healerSpot = proxy.healerSpot end
			if proxy.role ~= E:GetRole() or proxy.roleClass ~= (E.db.general.roleClass and true or false)
				or (spotChanged and proxy.role == "healer") then
				E:ApplyRole(proxy.role, { classLayer = proxy.roleClass })
			end
		end, 2.6)
	if page then page.desc = L["Your role and class: a small layer over the layout, and click-cast setup for healers."] end
end, proxy, "modules")
