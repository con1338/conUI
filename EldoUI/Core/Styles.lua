-- EldoUI style presets: each module can offer a few ready-made looks
-- (for example "Minimal" or "Portraits" unit frames) that set many of its
-- options in one click. They show at the top of the module's config page.
--
--   E:RegisterStyles("UnitFrames", {
--       { key = "Minimal", title = "Minimal", desc = "...", settings = { units = { player = { width = 220 } } } },
--   })
-- Settings are merged into the module's saved settings, so anything a
-- style doesn't mention keeps its current value. The exception is what
-- the list owns: the paths in opts.restores and every visibility block
-- (a "rules" facet) one of its styles writes. A style that leaves an owned
-- path out sets it back to the module's default, so a frame one style hid
-- or faded comes back with the next style.
--
-- `mode = true` marks a preset that switches how a module works rather than
-- how it looks. On a fresh profile it can match the defaults on purpose.
--
-- opts.playerLists names lists the player fills in ({ "texts" }): a
-- style that leaves them out keeps the player's entries, unless the style
-- in use wrote them.
--
-- A third argument { describe = true } shows each preset's one-line
-- description under its button on the module's Presets tab, for presets
-- that switch how a module works and need saying (Edit Mode).
--
-- Styles own the look, layouts own the positions:
-- a style never moves a frame, so any mix of styles keeps the layout's
-- zones, and the next layout click doesn't undo a style.
local _, E = ...
local L = E.L

E.styles = {}
E.styleOptions = {}

---------------------------------------------------------------------------
-- Ownership: a few keys belong to the layout, never to a style. Which
-- action bars are on and how many buttons a row holds is placement (the
-- layout's points are made for that shape), so an Action Bars style sets
-- only button size, spacing and the look. The module names its own
-- layout keys when it registers its styles:
--   E:RegisterStyles("ActionBars", list, { layoutOwned = function(settings, found) ... end })
-- The function adds { table, key, "readable.path" } to `found` for each
-- layout key the settings write. A style that writes one anyway is
-- reported once and the key is dropped from it.
---------------------------------------------------------------------------
local LAYOUT_OWNED = {}

-- The layout-owned keys a style's settings write, as readable paths.
function E:StyleLayoutKeys(moduleName, settings)
	local check, found = LAYOUT_OWNED[moduleName], {}
	if check and type(settings) == "table" then check(settings, found) end
	local paths = {}
	for _, entry in ipairs(found) do paths[#paths + 1] = entry[3] end
	return paths, found
end

---------------------------------------------------------------------------
-- Footprints: the frame sizes a style sets, so a layout can tell whether
-- the style fits its spots. Read from the style's settings when it is
-- registered:
--   style.footprint = {
--       movers = { EldoUI_Player = { width = 277, height = 46 }, ... },
--       bars   = { [1] = { size = 46, spacing = 4 }, ... },  -- Action Bars
--       paint  = { EldoUI_Target = 4, ... },  -- unit-frame graphics outside the frame
--   }
-- A style that sets no size has an empty footprint and fits every layout.
-- paint is read again on every E:StyleFootprint call: it follows the skin
-- and the graphics picks in use (E.UnitGraphics:Metrics), which can change
-- after the style was registered. E:StylePaintedSize adds it to a size.
---------------------------------------------------------------------------
local UNIT_MOVERS = { player = "EldoUI_Player", target = "EldoUI_Target", focus = "EldoUI_Focus",
	pet = "EldoUI_Pet", targettarget = "EldoUI_ToT" }
local GROUP_SIZE = 5
-- Forever's micro menu buttons and bag bar buttons, in units at 100 %.
local MICRO_BUTTONS, MICRO_SIZE = 14, { 32, 40 }
local BAG_BUTTONS, BAG_SIZE = 5, 45

local function Num(value) return type(value) == "number" and value or nil end

-- A setting of a style, or the module's default when the style leaves it
-- out: `Setting(settings, defaults, "combo", "height")`.
local function Setting(settings, defaults, ...)
	local value, fallback = settings, defaults
	for index = 1, select("#", ...) do
		local key = select(index, ...)
		value = type(value) == "table" and value[key] or nil
		fallback = type(fallback) == "table" and fallback[key] or nil
	end
	if value == nil then return fallback end
	return value
end

-- The tallest Class Power stack a style makes: combo points (pips or the
-- arc), health, power, druid mana in the stack, extra bars in the stack and
-- the GCD bar, with the gap between rows.
local function ClassPowerHeight(settings)
	local module = E.modules and E.modules.ClassPower
	local defaults = module and module.defaults or {}
	local gap = Num(Setting(settings, defaults, "gap")) or 0
	local rows = {}
	if Setting(settings, defaults, "combo", "enabled") then
		if Setting(settings, defaults, "combo", "style") == "ARC" then
			rows[#rows + 1] = (Num(Setting(settings, defaults, "combo", "arcRadius")) or 0) + (Num(Setting(settings, defaults, "combo", "arcSize")) or 0)
		else
			rows[#rows + 1] = Num(Setting(settings, defaults, "combo", "height")) or 0
		end
	end
	for _, part in ipairs({ "health", "power" }) do
		if Setting(settings, defaults, part, "enabled") then rows[#rows + 1] = Num(Setting(settings, defaults, part, "height")) or 0 end
	end
	local powerOn = Setting(settings, defaults, "power", "enabled")
	local manaAttach = Setting(settings, defaults, "druidMana", "attach")
	if Setting(settings, defaults, "druidMana", "enabled") and (manaAttach == "STACK" or (manaAttach == "INSET" and not powerOn)) then
		rows[#rows + 1] = Num(Setting(settings, defaults, "druidMana", "height")) or 0
	end
	for index = 1, 4 do
		local key = "bar" .. index
		if Setting(settings, defaults, "bars", key, "enabled") and Setting(settings, defaults, "bars", key, "place") ~= "MOVER" then
			rows[#rows + 1] = Num(Setting(settings, defaults, "bars", key, "height")) or 0
		end
	end
	if Setting(settings, defaults, "gcd", "enabled") then rows[#rows + 1] = Num(Setting(settings, defaults, "gcd", "height")) or 0 end
	if #rows == 0 then return nil end
	local height = gap * (#rows - 1)
	for _, row in ipairs(rows) do height = height + row end
	return height
end

local FOOTPRINTS = {
	UnitFrames = function(settings, fp)
		for unit, info in pairs(type(settings.units) == "table" and settings.units or {}) do
			local name = UNIT_MOVERS[unit]
			if name and type(info) == "table" and (Num(info.width) or Num(info.height)) then
				fp.movers[name] = { width = Num(info.width), height = Num(info.height) }
			end
			-- The power orb of the Orbs shape sits on the detached power bar's mover.
			if unit == "player" and type(info) == "table" and info.shape == "ORB" and Num(info.powerHeight) then
				fp.movers.EldoUI_PlayerFramePower = { width = Num(info.powerWidth) or info.powerHeight, height = info.powerHeight }
			end
		end
	end,
	-- The party block: five frames in a column (DOWN, UP) or a row.
	GroupFrames = function(settings, fp)
		local party = type(settings.party) == "table" and settings.party
		if not (party and Num(party.width) and Num(party.height)) then return end
		local spacing = Num(party.spacing) or 0
		local across = party.growth == "RIGHT" or party.growth == "LEFT"
		local width = across and (GROUP_SIZE * party.width + (GROUP_SIZE - 1) * spacing) or party.width
		local height = across and party.height or (GROUP_SIZE * party.height + (GROUP_SIZE - 1) * spacing)
		fp.movers.EldoUI_Party = { width = width, height = height }
	end,
	Minimap = function(settings, fp)
		if Num(settings.size) then fp.movers.EldoUI_Minimap = { width = settings.size, height = settings.size } end
	end,
	-- Width, and the height of the tallest stack (combo points included).
	ClassPower = function(settings, fp)
		if Num(settings.width) then fp.movers.EldoUI_PlayerPower = { width = settings.width, height = ClassPowerHeight(settings) } end
	end,
	-- Bar 1's height, and bar 2 when the style turns it on.
	InfoBar = function(settings, fp)
		if Num(settings.height) then fp.movers.EldoUI_InfoBar = { height = settings.height } end
		local bar2 = type(settings.bar2) == "table" and settings.bar2
		if bar2 and bar2.enabled then
			local module = E.modules and E.modules.InfoBar
			local default = module and module.defaults and module.defaults.bar2
			fp.movers.EldoUI_InfoBar2 = { height = Num(bar2.height) or (default and Num(default.height)) }
		end
	end,
	-- The micro menu (Forever's fourteen 32 x 40 buttons in rows) and the
	-- bag bar (the backpack and four bags, 45 units each), at the style's
	-- scale. Settings a style leaves out come from the module's defaults.
	MicroMenu = function(settings, fp)
		local module = E.modules and E.modules.MicroMenu
		local defaults = module and module.defaults or {}
		local micro = type(settings.micro) == "table" and settings.micro
		if micro and Num(micro.scale) then
			local base = defaults.micro or {}
			local hidden = 0
			for _, on in pairs(type(micro.hide) == "table" and micro.hide or {}) do
				if on then hidden = hidden + 1 end
			end
			local count = math.max(1, MICRO_BUTTONS - hidden)
			local perRow = math.max(1, math.min(Num(micro.perRow) or Num(base.perRow) or MICRO_BUTTONS, count))
			local rows = math.ceil(count / perRow)
			local spacing = Num(micro.spacing) or Num(base.spacing) or 0
			local scale = micro.scale / 100
			fp.movers.EldoUI_MicroMenu = {
				width = (perRow * MICRO_SIZE[1] + (perRow - 1) * spacing) * scale,
				height = (rows * MICRO_SIZE[2] + (rows - 1) * spacing) * scale,
			}
		end
		local bags = type(settings.bags) == "table" and settings.bags
		if bags and Num(bags.scale) then
			local base = defaults.bags or {}
			local count = bags.onlyBackpack and 1 or BAG_BUTTONS
			local spacing = Num(bags.spacing) or Num(base.spacing) or 0
			local length = (count * BAG_SIZE + (count - 1) * spacing) * bags.scale / 100
			local across = BAG_SIZE * bags.scale / 100
			local vertical = bags.vertical
			if vertical == nil then vertical = base.vertical end
			fp.movers.EldoUI_BagBar = { width = vertical and across or length, height = vertical and length or across }
		end
	end,
	ActionBars = function(settings, fp)
		for index, bar in pairs(type(settings.bars) == "table" and settings.bars or {}) do
			if type(bar) == "table" and (Num(bar.size) or Num(bar.spacing)) then
				fp.bars[index] = { size = Num(bar.size), spacing = Num(bar.spacing) }
			end
		end
	end,
}

local function Footprint(moduleName, settings)
	local fp = { movers = {}, bars = {}, paint = {} }
	local read = FOOTPRINTS[moduleName]
	if read and type(settings) == "table" then read(settings, fp) end
	return fp
end

-- Paint: how far the unit-frame graphics reach outside each frame a style
-- sizes, from the style's size and portrait over the frame's own settings.
local UNIT_OF = {}
for unit, name in pairs(UNIT_MOVERS) do UNIT_OF[name] = unit end
local PAINT = {
	UnitFrames = function(settings, fp, UG)
		local module = E.modules and E.modules.UnitFrames
		local units = module and module.db and type(module.db.units) == "table" and module.db.units or {}
		local styled = type(settings.units) == "table" and settings.units or {}
		for name in pairs(fp.movers) do
			local unit = UNIT_OF[name]
			local own = type(units[unit]) == "table" and units[unit] or {}
			local mine = type(styled[unit]) == "table" and styled[unit] or {}
			local portrait = mine.portrait
			if portrait == nil then portrait = own.portrait end
			local db = { graphics = own.graphics, height = Num(mine.height) or own.height, portrait = portrait }
			fp.paint[name] = UG:Metrics(db, "unit", unit).paint[1]
		end
	end,
	GroupFrames = function(_, fp, UG)
		local module = E.modules and E.modules.GroupFrames
		if fp.movers.EldoUI_Party then
			fp.paint.EldoUI_Party = UG:Metrics(module and module.db and module.db.party, "group").paint[1]
		end
	end,
}

local function Paint(moduleName, fp, settings)
	if fp.paint then wipe(fp.paint) else fp.paint = {} end
	local read, UG = PAINT[moduleName], E.UnitGraphics
	if read and UG and UG.Metrics and type(settings) == "table" then read(settings, fp, UG) end
end

-- The footprint of a registered style (empty when it sets no size).
function E:StyleFootprint(moduleName, styleKey)
	for _, style in ipairs(self.styles[moduleName] or {}) do
		if style.key == styleKey then
			style.footprint = style.footprint or Footprint(moduleName, style.settings)
			Paint(moduleName, style.footprint, style.settings)
			return style.footprint
		end
	end
end

-- Width and height of a frame a style sizes, with what the unit-frame
-- graphics paint round it (nil when the style doesn't size that frame).
function E:StylePaintedSize(moduleName, styleKey, moverName)
	local fp = self:StyleFootprint(moduleName, styleKey)
	local size = fp and fp.movers[moverName]
	if not size then return nil end
	local paint = fp.paint[moverName] or 0
	return size.width and size.width + 2 * paint, size.height and size.height + 2 * paint
end

-- True when a style sets the size of a frame a layout places.
function E:StyleHasFootprint(moduleName, styleKey)
	local fp = self:StyleFootprint(moduleName, styleKey)
	return fp ~= nil and (next(fp.movers) ~= nil or next(fp.bars) ~= nil)
end

-- Does a style fit a layout? Each layout lists the styles whose sizes
-- don't fit its spots (`incompatible = { UnitFrames = { Healer =
-- "EldoUI_Party" } }`, the value naming the frame the style would run
-- into); the layout checks keep that list true. A unit-frame graphics
-- choice whose painted extent runs into a frame is listed the same way
-- under "UnitGraphics", by its id. Returns true, or false and a short
-- reason for the player.
function E:StyleFits(layoutKey, moduleName, styleKey, descriptor)
	if E.Secret(descriptor) then return false end
	if type(descriptor) ~= "nil" then
		if type(descriptor) ~= "table" or type(getmetatable(descriptor)) ~= "nil"
			or E.Secret(moduleName) or type(moduleName) ~= "string" or E.Secret(styleKey) or type(styleKey) ~= "string" then return false end
		local incompatible, title = rawget(descriptor, "incompatible"), rawget(descriptor, "title")
		if E.Secret(incompatible) or E.Secret(title) or (type(title) ~= "nil" and type(title) ~= "string")
			or (type(incompatible) ~= "nil" and (type(incompatible) ~= "table" or type(getmetatable(incompatible)) ~= "nil")) then return false end
		local list = incompatible and rawget(incompatible, moduleName)
		if E.Secret(list) or (type(list) ~= "nil" and (type(list) ~= "table" or type(getmetatable(list)) ~= "nil")) then return false end
		local other = list and rawget(list, styleKey)
		if E.Secret(other) or (type(other) ~= "nil" and type(other) ~= "string" and type(other) ~= "boolean") then return false end
		if not other then return true end
		return false, L["Too large for the %s layout's spots."]:format(title or "?")
	end
	local layout = layoutKey and self.layouts and self.layouts[layoutKey]
	local list = layout and type(layout.incompatible) == "table" and layout.incompatible[moduleName]
	local other = type(list) == "table" and list[styleKey]
	if not other then return true end
	local mover = type(other) == "string" and self.movers and self.movers[other]
	local title = mover and mover.title and L[mover.title]
	local layoutTitle = self:LayoutTitle(layoutKey)
	if title then
		return false, L["Too large for the %s layout: it would cover the %s."]:format(layoutTitle, E:InSentence(title))
	end
	return false, L["Too large for the %s layout's spots."]:format(layoutTitle)
end

-- One source per module: the module registers its own list in its own
-- files. A second list for the same module would silently replace the
-- first, so it goes to the error log and the later one is kept.
-- opts (optional): describe (above), layoutOwned (the layout keys, above),
-- restores (dotted paths the list owns, header).
function E:RegisterStyles(moduleName, list, opts)
	if self.styles[moduleName] and self.styles[moduleName] ~= list and self.errors and self.errors.Add then
		self.errors:Add("warning", ("EldoUI: style presets for %s were registered twice; the later list is used."):format(tostring(moduleName)))
	end
	if type(opts) == "table" and type(opts.layoutOwned) == "function" then LAYOUT_OWNED[moduleName] = opts.layoutOwned end
	for _, style in ipairs(type(list) == "table" and list or {}) do
		local paths, found = self:StyleLayoutKeys(moduleName, style.settings)
		if #paths > 0 then
			for _, entry in ipairs(found) do entry[1][entry[2]] = nil end
			if self.errors and self.errors.Add then
				self.errors:Add("warning", ("EldoUI: the %s style %s sets %s, which the layout owns; those keys are left out."):format(
					tostring(moduleName), tostring(style.key), table.concat(paths, ", ")))
			end
		end
		style.footprint = Footprint(moduleName, style.settings)
	end
	self.styles[moduleName] = list
	self.styleOptions[moduleName] = type(opts) == "table" and opts or nil
end

-- A list of plain values (datatext slots) is replaced as a whole. A table
-- of tables (the action bars) is merged entry by entry like any other
-- nested table, so a bar keeps the keys the style doesn't name and bars the
-- style doesn't list stay as they are. Same rule as layouts (Core/Layout.lua),
-- through E.IsList.
local function Merge(target, source)
	for key, value in pairs(source) do
		if type(value) == "table" and E.IsList(value) then
			target[key] = CopyTable(value)
		elseif type(value) == "table" then
			if type(target[key]) ~= "table" then target[key] = {} end
			Merge(target[key], value)
		else
			target[key] = value
		end
	end
end

-- Role and style on the same frames: a role that sets the width of a part
-- of a module (the healer's party and raid frames) owns that part's size
-- and shape, and a style keeps only its look there. Returns { part = true }
-- or nil.
local SIZE_KEYS = { "width", "height", "spacing", "growth", "unitsPerColumn", "maxColumns" }
function E:RoleSizedParts(role, moduleName)
	local profile = role and self.roleProfiles and self.roleProfiles[role]
	local settings = profile and type(profile.settings) == "table" and profile.settings[moduleName]
	local parts
	for part, value in pairs(type(settings) == "table" and settings or {}) do
		if type(value) == "table" and value.width ~= nil then
			parts = parts or {}
			parts[part] = true
		end
	end
	return parts
end

-- The settings a style writes, without the size keys of `sizedBy` parts.
function E:StyleSettings(style, sizedBy)
	local settings = style.settings or {}
	if not sizedBy then return settings end
	settings = CopyTable(settings)
	for part in pairs(sizedBy) do
		if type(settings[part]) == "table" then
			for _, key in ipairs(SIZE_KEYS) do settings[part][key] = nil end
			-- A part left with nothing would read as an empty list and clear
			-- the player's part on the merge.
			if next(settings[part]) == nil then settings[part] = nil end
		end
	end
	return settings
end

-- The paths a module's style list owns (header): opts.restores, the
-- visibility block of each "rules" facet that one of its styles writes,
-- and every setting any of its styles writes. So a style never inherits a
-- setting from the style picked before it, and going back to a style
-- gives exactly what it gave the first time.
function E:StyleOwnedPaths(moduleName)
	local owned, seen = {}, {}
	local function Add(path)
		if not seen[path] then
			seen[path] = true
			owned[#owned + 1] = path
		end
	end
	local opts = self.styleOptions[moduleName]
	for _, path in ipairs(opts and opts.restores or {}) do Add(path) end
	-- Every setting a style of the list writes; a list of plain values (the
	-- datatext slots) counts as one setting. A module whose styles seed
	-- data the player then owns (opts.restoresOnly: sound triggers) keeps
	-- only its listed paths.
	local function Walk(settings, prefix)
		for key, value in pairs(settings) do
			local path = prefix and (prefix .. "." .. tostring(key)) or tostring(key)
			if type(value) == "table" and not E.IsList(value) then Walk(value, path) else Add(path) end
		end
	end
	if not (opts and opts.restoresOnly) then
		for _, style in ipairs(self.styles[moduleName] or {}) do Walk(style.settings or {}, nil) end
	end
	for _, record in pairs(self.VisibilityFacets and self:VisibilityFacets() or {}) do
		local path = record.module == moduleName and record.facet == "rules" and record.setting
		if path then
			for _, style in ipairs(self.styles[moduleName] or {}) do
				if E.GetPath(style.settings or {}, path) ~= nil then Add(path) break end
			end
		end
	end
	table.sort(owned)
	return owned
end

-- The owned paths a style leaves out, which E:ApplyStyle sets back to the
-- module's default.
function E:StyleRestores(moduleName, style, sizedBy)
	local settings, out = self:StyleSettings(style, sizedBy), {}
	local roleSize = {}
	for part in pairs(sizedBy or {}) do
		for _, key in ipairs(SIZE_KEYS) do roleSize[part .. "." .. key] = true end
	end
	for _, path in ipairs(self:StyleOwnedPaths(moduleName)) do
		-- A size the role owns stays the role's.
		if E.GetPath(settings, path) == nil and not roleSize[path] then out[#out + 1] = path end
	end
	return out
end

-- silent: no chat line (the installer applies a style per category).
-- sizedBy (optional, E:RoleSizedParts): parts whose size a role owns.
function E:ApplyStyle(moduleName, styleKey, silent, sizedBy)
	local module = self.modules[moduleName]
	if not module or not module.db then return end
	for _, style in ipairs(self.styles[moduleName] or {}) do
		if style.key == styleKey then
			local defaults = module.defaults or {}
			-- A setting the style leaves out comes from the layout in use: in a
			-- part the style writes (a unit, a bar, the raid block) from the
			-- layout's own settings, else the default; in a part it doesn't
			-- touch, the layout's suggested style comes first, so that part
			-- keeps the layout's look.
			local layout = self.layouts and self.db and self.layouts[self.db.general.layout]
			local fromLayout = layout and type(layout.modules) == "table" and layout.modules[moduleName]
			local suggested = layout and type(layout.suggest) == "table" and layout.suggest[moduleName]
			local fromLook
			for _, other in ipairs(self.styles[moduleName] or {}) do
				if other.key == suggested and other ~= style then fromLook = self:StyleSettings(other, sizedBy) end
			end
			local own = self:StyleSettings(style, sizedBy)
			-- A list the player fills in (opts.playerLists: a unit's texts)
			-- goes back only when the style in use wrote it: another style
			-- leaves the player's own entries alone.
			local opts = self.styleOptions[moduleName]
			local previous
			for _, other in ipairs(self.styles[moduleName] or {}) do
				if other.key == module.db.style then previous = other.settings or {} end
			end
			local function KeepsList(path)
				for _, name in ipairs(opts and opts.playerLists or {}) do
					if ("." .. path .. "."):find("." .. name .. ".", 1, true) then
						return not (previous and E.GetPath(previous, path) ~= nil)
					end
				end
				return false
			end
			for _, path in ipairs(self:StyleRestores(moduleName, style, sizedBy)) do
				if not KeepsList(path) then
				local first, second, rest = path:match("^([^%.]+)%.([^%.]+)%.?(.*)$")
				local part = first and (rest ~= "" and (first .. "." .. second) or first)
				local ownsPart = part ~= nil and type(E.GetPath(own, part)) == "table"
				local value
				if not ownsPart and fromLook then value = E.GetPath(fromLook, path) end
				if value == nil and fromLayout then value = E.GetPath(fromLayout, path) end
				if value == nil then value = E.GetPath(defaults, path) end
				E.SetPath(module.db, path, type(value) == "table" and CopyTable(value) or value)
				end
			end
			Merge(module.db, self:StyleSettings(style, sizedBy))
			-- The layout's own style is the layout's look: the layout's values
			-- for the settings styles write go on top, as the layout applied
			-- them, so going back to it gives exactly what the layout gave.
			-- Placement (which bars are on, their rows) stays the player's.
			if fromLayout and styleKey == suggested then
				-- A size the role owns stays the role's here too.
				local roleSize = {}
				for part in pairs(sizedBy or {}) do
					for _, key in ipairs(SIZE_KEYS) do roleSize[part .. "." .. key] = true end
				end
				for _, path in ipairs(self:StyleOwnedPaths(moduleName)) do
					local value
					if not roleSize[path] then value = E.GetPath(fromLayout, path) end
					if value ~= nil then E.SetPath(module.db, path, type(value) == "table" and CopyTable(value) or value) end
				end
			end
			module.db.style = styleKey
			self:RefreshModule(module, true)
			-- A frame that grew past its spot takes the layout's wide point.
			if self.ApplyWidePoints then self:ApplyWidePoints() end
			if not silent then
				self:ConfigNotice(L["%s style %s applied."]:format(L[module.title], E:Highlight(L[style.title])))
			end
			return true
		end
	end
end

-- The key of the style applied last in a module's list (nil when none).
-- It stays after the player changes a setting by hand: the mark on the
-- style rows means "applied last", not "matches the settings now".
function E:StyleApplied(moduleName)
	local module = self.modules and self.modules[moduleName]
	return module and module.db and module.db.style or nil
end

-- True while this style is the one applied last.
local function Applied(moduleName, styleKey)
	return function() return E:StyleApplied(moduleName) == styleKey end
end

-- Grayed with the reason while a style doesn't fit the layout in use.
local function Unfit(moduleName, styleKey)
	return function()
		local fits, reason = E:StyleFits(E.db and E.db.general.layout, moduleName, styleKey)
		if not fits then return reason end
	end
end

-- A style list can say when its styles show nothing yet (opts.notice, a
-- function of "page" or "setup" that returns the text, or nil): the minimap
-- styles shape EldoUI's minimap, not the game's. The text is already in
-- the player's language.
function E:StyleNotice(moduleName, where)
	local opts = self.styleOptions[moduleName]
	local notice = opts and opts.notice
	if type(notice) ~= "function" then return nil end
	local ok, text = pcall(notice, where or "page")
	return ok and type(text) == "string" and text ~= "" and text or nil
end

-- The notice as a page row: shown only while there is one.
local function NoticeRow(moduleName)
	return { type = "description", tone = "warning",
		label = function() return E:StyleNotice(moduleName, "page") or "" end,
		hidden = function() return E:StyleNotice(moduleName, "page") == nil end }
end

-- Option rows for the top of a module page.
function E:StyleOptions(moduleName)
	local list = self.styles[moduleName]
	if not list then return end
	local options = { { type = "header", label = "Style presets" } }
	if self.styleOptions[moduleName] and self.styleOptions[moduleName].notice then options[#options + 1] = NoticeRow(moduleName) end
	local describe = self.styleOptions[moduleName] and self.styleOptions[moduleName].describe
	for _, style in ipairs(list) do
		table.insert(options, { type = "execute", label = style.title, desc = style.desc, width = 200,
			disabled = Unfit(moduleName, style.key), active = Applied(moduleName, style.key),
			func = function() E:ApplyStyle(moduleName, style.key); E:RefreshConfig() end })
		-- Its one line under the button.
		if describe and style.desc then
			table.insert(options, { type = "description", label = style.desc })
		end
	end
	return options
end

---------------------------------------------------------------------------
-- A new look: skin, accent, font, texture or contrast. One repaint for
-- everything, with no /reload:
--   1. the kits and everything in the theme registry (E:UpdateArtStyle),
--   2. tag texts (a new "Big numbers" style shows at once),
--   3. every active module repaints through its `themed` callback
--      (E:NewModule: a function, or the name of one of its methods).
-- Settings changes keep going through OnProfileChanged; a new look no
-- longer re-applies every setting of every module.
--
-- For one release a module that has no `themed` callback yet still gets
-- its OnProfileChanged on a new look, so nothing stops repainting while
-- modules move over (E.themeFallback; the debug line names each module
-- once per session).
---------------------------------------------------------------------------
E.themeFallback = true

local fallbackNamed = {}

-- The module's own repaint, or nil when it has none.
function E:ModuleThemedCallback(module)
	local descriptor = self:GetModuleDescriptor(module)
	local themed = descriptor and descriptor.themed
	if type(themed) == "string" then themed = module[themed] end
	return type(themed) == "function" and themed or nil
end

-- Repaint every active module once. In combat each waits for the end of
-- the fight, one queued repaint per module however many looks change.
-- themedOnly: skip modules without a themed callback (a profile switch
-- has already re-applied their settings).
function E:RepaintModules(themedOnly)
	if not self.modules then return end
	for _, module in self:IterateModules() do
		if module.active then
			local themed = self:ModuleThemedCallback(module)
			if themed then
				self:RunOutOfCombat(function()
					if not module.active then return end
					local ok, err = pcall(themed, module)
					if not ok then geterrorhandler()(err) end
				end, "Theme:" .. tostring(module.name))
			elseif self.themeFallback and module.OnProfileChanged and not themedOnly then
				if not fallbackNamed[module.name] then
					fallbackNamed[module.name] = true
					self:Debug(("%s has no themed callback; a new look re-applies all its settings."):format(module.name))
				end
				self:RefreshModule(module, true)
			end
		end
	end
end

function E:RefreshTheme(themedOnly)
	self:UpdateAccent()
	self:UpdateArtStyle()
	if self.UpdateTags then self:UpdateTags() end
	self:RepaintModules(themedOnly)
end

-- One page that lists every category, for mixing and matching.
E:RegisterEvent("PLAYER_LOGIN", function()
	local options = {
		{ type = "description", label = "Open a part of the UI to pick its style; styles mix freely. A style that doesn't fit your layout is grayed out with the reason." },
	}
	for name, module in E:IterateModules() do
		if E.styles[name] then
			-- Each part folds, closed at first: the page reads as the list
			-- of parts, and a click opens the styles of one.
			table.insert(options, { type = "header", label = module.title, fold = "folded" })
			if E.styleOptions[name] and E.styleOptions[name].notice then table.insert(options, NoticeRow(name)) end
			for _, style in ipairs(E.styles[name]) do
				-- Styles that act for the player stay on their module page.
				if not style.acts then
					table.insert(options, { type = "execute", label = style.title, desc = style.desc, width = 200,
						disabled = Unfit(name, style.key), active = Applied(name, style.key),
						func = function() E:ApplyStyle(name, style.key); E:RefreshConfig() end })
				end
			end
		end
	end
	E:RegisterConfigPage("styles", "Style presets", options, function() return E.db end, function() end, 2.5)
end, E.styles, "pages")
