-- EldoUI preset packs (data in Data/Packs.lua): what a pack picks, the
-- look of the current profile as a pack, and packs as share strings.
--
--   E:PackLayout(pack)        the layout key a pack uses
--   E:PackArtStyle(pack)      the skin a pack shows: its own when this
--                             version has it, Modern for one it doesn't
--                             (second return: the skin asked for), the
--                             layout's skin when the pack names none
--   E:PackStyles(pack)        { Module = style key }: the layout's suggested
--                             styles with the pack's own on top, only styles
--                             that exist and fit the layout
--   E:CurrentLookPack()       the profile's layout, skin, faction look,
--                             unit-frame graphics, Blizzard windows, accent
--                             and styles as a pack (for the Share menu)
--   E:PackPlan(pack)          the pack as a setup plan for E:ApplySetup
--                             (Core/Layout.lua): its layout, look, Blizzard
--                             windows, styles, role and UI amount
--   E:ApplyPackLook(pack)     applies that plan on the current profile,
--                             with one Undo; the setup applies a whole pack
--                             (E.Installer)
-- A pack string ("!EUP1!...") is read by EldoUI's own deserializer and
-- checked key by key: only layouts and styles that exist are used, and
-- nothing in it is ever run. A skin or unit-frame graphics this version
-- doesn't have are kept by name (Modern is drawn in their place), so the
-- pack still works in a version that has them. Look fields are optional
-- within the supported profile generation.
-- Written from scratch for EldoUI.
local _, E = ...
local ReadAccountRoot = E.ReadAccountRoot
local L = E.L

-- A role a pack can name: one of the four, or an older name EldoUI still
-- reads ("damage" becomes the class's damage role).
local function PackRole(value)
	local key = E.ResolveRoleKey and E:ResolveRoleKey(value)
	if key and key ~= "none" then return key end
	return nil
end
local VARIANTS = { auto = true, alliance = true, horde = true, neutral = true }
local WINDOWS = { keep = true, layout = true, original = true, match = true }

local function Plain(value)
	return not E.Secret(value) and type(value) == "table" and type(getmetatable(value)) == "nil"
end

local function CurrentProfile()
	local predicate = E.IsCurrentProfile
	if E.Secret(predicate) or type(predicate) ~= "function" then return false end
	local ok, current = pcall(predicate, E)
	return ok and not E.Secret(current) and current == true and E.IsCurrentProfile == predicate
end

-- Read-only family picks use the current slot. Native input must name that
-- actual placement; a retired key that doubles as a family is ambiguous.
local function CurrentLayout(key, familyAlias)
	if E.Secret(key) or type(key) ~= "string" or not Plain(E.layoutFamilies) then return nil end
	local resolve = E.FamilyLayoutKey
	if E.Secret(resolve) or type(resolve) ~= "function" then return nil end
	for _, slot in ipairs(E.layoutFamilies) do
		if not Plain(slot) then return nil end
		local family = rawget(slot, "key")
		if E.Secret(family) or type(family) ~= "string" then return nil end
		local ok, current = pcall(resolve, E, family)
		if ok and not E.Secret(current) and type(current) == "string"
			and (key == current or (familyAlias and key == family)) then return current end
	end
end

local function ImportQuery(name, value)
	local owner = E.Import
	if not Plain(owner) then return nil end
	local fn = rawget(owner, name)
	if E.Secret(fn) or type(fn) ~= "function" then return nil end
	local ok, result = pcall(fn, value)
	if not ok or E.Secret(result) or not Plain(result) or E.Secret(E.Import) or E.Import ~= owner
		or E.Secret(rawget(owner, name)) or rawget(owner, name) ~= fn then return nil end
	return result
end

local function LayoutSource(pack, familyAlias)
	if type(pack) == "nil" then pack = {} end
	if not Plain(pack) or E.Secret(pack.layout) then return nil end
	local key, envelope = pack.layout, rawget(pack, "layoutDependencies")
	if E.Secret(envelope) then return nil end
	if type(envelope) ~= "nil" then
		local plan = ImportQuery("PrepareLayoutDependencies", envelope)
		if not plan or E.Secret(plan.layout) or plan.layout ~= key or not Plain(plan.layoutData) then return nil end
		return key, plan.layoutData
	end
	local current = type(key) == "nil" and CurrentLayout(E.defaults.general.layout, true) or CurrentLayout(key, familyAlias)
	if current then return current, E.layouts[current] end
	if type(key) == "string" then
		local view = ImportQuery("CurrentLayout", key)
		if view then return key, view end
	end
end

local function PackTarget(target)
	local root, profile, name = ReadAccountRoot(), E.db, E.profileName
	local getter, active, admit = E.GetApplyGeneration, E.IsApplyGenerationCurrent, E.IsCurrentProfile
	if E.Secret(root) or E.Secret(profile) or E.Secret(name) or E.Secret(getter) or E.Secret(active) or E.Secret(admit)
		or type(getter) ~= "function" or type(active) ~= "function" or type(admit) ~= "function" then return nil end
	if target and (root ~= target.root or profile ~= target.profile or name ~= target.name or getter ~= target.getter
		or active ~= target.active or admit ~= target.admit) then return nil end
	local ok, generation = pcall(getter, E, "profile")
	if not ok or E.Secret(generation) or type(generation) ~= "number" or generation < 1 or generation >= math.huge
		or generation % 1 ~= 0 or (target and generation ~= target.generation) or not CurrentProfile() then return nil end
	local valid, current = pcall(active, E, generation, "profile")
	if not valid or E.Secret(current) or current ~= true or E.Secret(E.GetApplyGeneration) or E.GetApplyGeneration ~= getter
		or E.Secret(E.IsApplyGenerationCurrent) or E.IsApplyGenerationCurrent ~= active or E.Secret(E.IsCurrentProfile) or E.IsCurrentProfile ~= admit
		or E.Secret(E.db) or E.db ~= profile or E.Secret(ReadAccountRoot()) or ReadAccountRoot() ~= root
		or E.Secret(E.profileName) or E.profileName ~= name then return nil end
	return target or { root = root, profile = profile, name = name, getter = getter, active = active, admit = admit, generation = generation }
end

local function CurrentPack(data)
	if not Plain(data) then return false end
	local generation = rawget(data, "profileBaseline")
	return not E.Secret(generation) and type(generation) == "number" and generation == E.PROFILE_BASELINE
end

-- A skin or graphics name: letters and digits, at most 32 characters.
local function IsName(value)
	return type(value) == "string" and #value <= 32 and value:match("^%a[%w]*$") ~= nil
end

-- The layout a pack uses: its own, else EldoUI's suggestion.
function E:PackLayout(pack)
	if type(pack) == "nil" then pack = {} end
	if not Plain(pack) or E.Secret(pack.layout) then return nil end
	local key = pack.layout
	local resolved = LayoutSource(pack, true)
	if resolved then return resolved end
	if (type(key) == "string" and key:match("^Imported_")) or type(rawget(pack, "layoutDependencies")) ~= "nil" then return nil end
	return CurrentLayout(self.defaults.general.layout, true)
end

function E:PackArtStyle(pack)
	if type(pack) == "nil" then pack = {} end
	if not Plain(pack) or E.Secret(pack.artStyle) then return nil end
	local art = pack.artStyle
	if type(art) ~= "string" then
		local _, layout = LayoutSource(pack, true)
		if Plain(layout) and not E.Secret(layout.skin) and type(layout.skin) == "string" and layout.skin ~= "" then return layout.skin end
		return self:ClientLook().artStyle
	end
	if self.artStyles[art] and art ~= "Contrast" then return art end
	return "Modern", art
end

-- A shipped pack whose layout this version doesn't have is left out, so
-- no card shows a layout it can't place. Family picks resolve to current
-- slots; the catalog loads before this file.
function E:PrunePacks()
	for index = #self.packOrder, 1, -1 do
		local pack = self.packs[self.packOrder[index]]
		if not pack or (pack.layout and not CurrentLayout(pack.layout, true)) then
			if pack then self.packs[pack.key] = nil end
			table.remove(self.packOrder, index)
		end
	end
end
E:PrunePacks()

-- Only the source-owned declarations loaded before this module receive
-- their generation here. Runtime inputs never take this admission path.
for _, key in ipairs(E.packOrder) do
	local pack = E.packs[key]
	if Plain(pack) then
		local identity, layout = rawget(pack, "key"), rawget(pack, "layout")
		if not E.Secret(identity) and identity == key and not E.Secret(layout)
			and (type(layout) == "nil" or CurrentLayout(layout, true)) then
			if type(layout) ~= "nil" then pack.layout = CurrentLayout(layout, true) end
			pack.profileBaseline = E.PROFILE_BASELINE
		end
	end
end

local function FindStyle(moduleName, key)
	for _, style in ipairs(E.styles[moduleName] or {}) do
		if style.key == key and not style.acts then return style end
	end
end

function E:PackStyles(pack)
	local layoutKey = self:PackLayout(pack)
	local _, layout = LayoutSource(pack, true)
	local styles = {}
	local function Take(list)
		for moduleName, key in pairs(type(list) == "table" and list or {}) do
			if type(moduleName) == "string" and type(key) == "string" and FindStyle(moduleName, key)
				and self:StyleFits(layoutKey, moduleName, key, layout) then
				styles[moduleName] = key
			end
		end
	end
	Take(layout and layout.suggest)
	Take(type(pack) == "table" and pack.styles)
	return styles
end

-- The current profile's look as a pack.
function E:CurrentLookPack()
	if not CurrentProfile() then return nil end
	local profile = self.db
	local general = self.db.general
	if not Plain(general) then return nil end
	if not LayoutSource({ layout = general.layout }) then return nil end
	local styles = {}
	for moduleName in pairs(self.styles) do
		local module = self.modules[moduleName]
		local key = module and module.db and module.db.style
		if type(key) == "string" and FindStyle(moduleName, key) then styles[moduleName] = key end
	end
	local units = self.modules.UnitFrames and self.modules.UnitFrames.db
	local graphics = units and self.GetPath(units, "allFrames.graphics")
	local pack = {
		profileBaseline = self.PROFILE_BASELINE,
		title = L["My look"], layout = general.layout,
		-- A profile that follows its layout shares no skin: the layout brings it.
		artStyle = not general.skinFollow and general.artStyle or nil,
		skinVariant = VARIANTS[general.skinVariant] and general.skinVariant ~= "auto" and general.skinVariant or nil,
		graphics = IsName(graphics) and graphics ~= "FOLLOW" and graphics or nil,
		blizzardWindows = WINDOWS[general.blizzardWindows] and general.blizzardWindows ~= "keep" and general.blizzardWindows or nil,
		accent = general.accent ~= "custom" and general.accent or nil, role = PackRole(general.role),
		styles = styles,
	}
	if not CurrentLayout(general.layout) then
		pack.layoutDependencies = ImportQuery("CaptureLayoutDependencies", general.layout)
		if not pack.layoutDependencies then return nil end
	end
	if not CurrentProfile() or self.db ~= profile then return nil end
	return pack
end

-- A pack from a share string, with only the keys EldoUI knows.
local function CleanPack(data)
	if not CurrentProfile() or not CurrentPack(data) then return nil end
	local profile = E.db
	for _, key in ipairs({ "title", "layout", "artStyle", "skinVariant", "graphics", "blizzardWindows", "accent", "role", "uiAmount", "styles", "layoutDependencies" }) do
		if E.Secret(rawget(data, key)) then return nil end
	end
	if type(data.styles) ~= "nil" and not Plain(data.styles) then return nil end
	local pack = { styles = {}, profileBaseline = data.profileBaseline }
	if type(data.title) == "string" then pack.title = data.title:sub(1, 48) end
	if type(data.layout) ~= "nil" then
		if type(rawget(data, "layoutDependencies")) ~= "nil" then
			pack.layout = LayoutSource(data)
			if not pack.layout then return nil end
			pack.layoutDependencies = CopyTable(data.layoutDependencies)
		else
			pack.layout = CurrentLayout(data.layout)
			if not pack.layout then return nil end
		end
	elseif type(rawget(data, "layoutDependencies")) ~= "nil" then return nil end
	if IsName(data.artStyle) and data.artStyle ~= "Follow" then pack.artStyle = data.artStyle end
	if VARIANTS[data.skinVariant] then pack.skinVariant = data.skinVariant end
	if IsName(data.graphics) then pack.graphics = data.graphics end
	if WINDOWS[data.blizzardWindows] then pack.blizzardWindows = data.blizzardWindows end
	if type(data.accent) == "string" and (data.accent == "class" or data.accent:match("^%x%x%x%x%x%x$")) then pack.accent = data.accent:upper() end
	if pack.accent == "CLASS" then pack.accent = "class" end
	pack.role = PackRole(data.role)
	if E.UIAmount and E.UIAmount.LEVELS[data.uiAmount] then pack.uiAmount = data.uiAmount end
	for moduleName, key in pairs(type(data.styles) == "table" and data.styles or {}) do
		if not E.Secret(moduleName) and not E.Secret(key) and type(moduleName) == "string" and type(key) == "string"
			and FindStyle(moduleName, key) then pack.styles[moduleName] = key end
	end
	if not CurrentProfile() or E.db ~= profile then return nil end
	return pack
end
E.CleanPack = CleanPack

-- A pack as a setup plan: its layout, and its look as a whole (the skin it
-- names, else the layout's), the accent, faction look, unit graphics and
-- Blizzard windows it names, the layout's suggested styles with its own on
-- top, its role and UI amount. A pack names its whole look, so no question
-- is asked about it.
function E:PackPlan(pack)
	if not Plain(pack) or E.Secret(pack.layout) or E.Secret(rawget(pack, "layoutDependencies")) then return nil end
	local key = pack.layout
	local imported = type(key) == "string" and ImportQuery("CurrentLayout", key)
	if imported and type(rawget(pack, "layoutDependencies")) == "nil" then
		local copy = CopyTable(pack)
		copy.layout = nil
		pack = CleanPack(copy)
		if pack then pack.layout = key end
	else pack = CleanPack(pack) end
	if not pack or type(rawget(pack, "layoutDependencies")) ~= "nil" then return nil end
	return {
		profileBaseline = pack.profileBaseline,
		layout = self:PackLayout(pack), look = "layout",
		skin = pack.artStyle, accent = pack.accent, skinVariant = pack.skinVariant, graphics = pack.graphics,
		windows = pack.blizzardWindows or false, styles = pack.styles,
		role = pack.role, uiAmount = pack.uiAmount,
		title = L["Pack %s"]:format(pack.title or L["Imported pack"]), source = "pack",
	}
end

-- The pack on the current profile through the one setup change: frames
-- the player dragged stay where they are, and Undo puts back what it set.
function E:ApplyPackLook(pack, callback)
	if E.Secret(callback) or (type(callback) ~= "nil" and type(callback) ~= "function") then return false end
	local apply, readPlan = self.ApplySetup, self.PackPlan
	if E.Secret(apply) or type(apply) ~= "function" or E.Secret(readPlan) or type(readPlan) ~= "function" then return false end
	local target = PackTarget()
	pack = CleanPack(pack)
	if not target or not pack or not PackTarget(target) or E.Secret(self.PackPlan) or self.PackPlan ~= readPlan
		or E.Secret(self.ApplySetup) or self.ApplySetup ~= apply then return false end
	local source, snapshot = pack, CopyTable(pack)
	local result, status, ran
	self:RunOutOfCombat(function()
		ran = true
		if not PackTarget(target) or not E.DeepEqual(source, snapshot) or E.Secret(self.ApplySetup) or self.ApplySetup ~= apply
			or E.Secret(self.PackPlan) or self.PackPlan ~= readPlan then
			if callback then callback(false, "rejected") end
			return
		end
		local working = CopyTable(snapshot)
		if type(working.layoutDependencies) ~= "nil" then
			local plan = ImportQuery("PrepareLayoutDependencies", working.layoutDependencies)
			local owner = self.Import
			local commit = Plain(owner) and rawget(owner, "ApplyLayoutDependencies")
			if not plan or E.Secret(commit) or type(commit) ~= "function" or not PackTarget(target) then
				if callback then callback(false, "rejected") end
				return
			end
			local ok, accepted, id = pcall(commit, plan)
			if not ok or E.Secret(accepted) or accepted ~= true or E.Secret(id) or type(id) ~= "string"
				or not PackTarget(target) or E.Secret(self.Import) or self.Import ~= owner
				or E.Secret(rawget(owner, "ApplyLayoutDependencies")) or rawget(owner, "ApplyLayoutDependencies") ~= commit then
				if callback then callback(false, "rejected") end
				return
			end
			working.layout, working.layoutDependencies = id, nil
		end
		if not PackTarget(target) or E.Secret(self.PackPlan) or self.PackPlan ~= readPlan then
			if callback then callback(false, "rejected") end
			return
		end
		local plan = readPlan(self, working)
		if not plan or not PackTarget(target) or E.Secret(self.ApplySetup) or self.ApplySetup ~= apply
			or E.Secret(self.PackPlan) or self.PackPlan ~= readPlan then
			if callback then callback(false, "rejected") end
			return
		end
		result, status = apply(self, plan)
		if E.Secret(result) or E.Secret(status) or (type(status) ~= "nil" and type(status) ~= "string") or not PackTarget(target) then result = false
		elseif result ~= true then result = status == "same" end
		if result then status = "applied" end
		if callback then callback(result == true, status or "rejected") end
	end, "Packs:apply")
	if not ran then return false, "queued" end
	return result, status
end

local function LayoutTitle(key)
	return key and E:LayoutTitle(key) or "?"
end

E:RegisterShareKind("pack", {
	prefix = "!EUP1!",
	version = 1,
	title = function(data) return L["Preset pack: %s"]:format(type(data) == "table" and type(data.title) == "string" and data.title or L["Imported pack"]) end,
	build = function() return E:CurrentLookPack() end,
	describe = function(data)
		local pack = CleanPack(data)
		if not pack then return { L["The pack is empty."] } end
		local art, asked = E:PackArtStyle(pack)
		local skin = asked and L["%s (not available): Modern is used"]:format(asked) or L[(E.artStyleInfo[art] or {}).title or "?"]
		if not pack.artStyle then skin = L["%s (from the layout)"]:format(skin) end
		local lines = {
			L["Layout: %s"]:format((select(2, LayoutSource(pack)) or {}).title or LayoutTitle(E:PackLayout(pack))),
			L["Skin: %s"]:format(skin),
		}
		if pack.skinVariant then
			local values = E:SkinVariants(art)
			if values and values[pack.skinVariant] then lines[#lines + 1] = L["Faction look: %s"]:format(values[pack.skinVariant]) end
		end
		if pack.graphics then
			local UG = E.UnitGraphics
			local values = UG and UG.Values and UG:Values(pack.graphics)
			lines[#lines + 1] = L["Unit-frame graphics: %s"]:format(values and values[pack.graphics] or pack.graphics)
		end
		local windows = pack.blizzardWindows and E.Appearance and E.Appearance.WINDOWS
		if windows then lines[#lines + 1] = L["Blizzard windows: %s"]:format(L[windows.titles[pack.blizzardWindows]]) end
		local parts = {}
		for moduleName, key in pairs(E:PackStyles(pack)) do
			local module = E.modules[moduleName]
			local style = FindStyle(moduleName, key)
			if module and style then parts[#parts + 1] = ("%s %s"):format(L[module.title], L[style.title]) end
		end
		table.sort(parts)
		if #parts > 0 then lines[#lines + 1] = L["Styles: %s"]:format(table.concat(parts, ", ")) end
		if pack.uiAmount then
			local count = #E:UIAmountPlan(pack.uiAmount)
			lines[#lines + 1] = L["UI amount: %s (%s)"]:format(E.UIAmount.Title(pack.uiAmount),
				E:Plural(count, "switches %d module", "switches %d modules"):format(count))
		end
		lines[#lines + 1] = L["Importing sets this look on your current profile. Frames you dragged stay where you put them, and Undo puts back what it changed."]
		return lines
	end,
	apply = function(data, callback) return E:ApplyPackLook(data, callback) end,
})
