-- EldoUI Tooltip: the game's tooltips in the EldoUI look, close to WoW's own
-- layout. A panel that follows the art style (90% dark), a 1-pixel border in
-- the item quality or class/reaction color, a soft shadow, class-colored
-- names, guild and rank, a colored level line, a target line and a thin
-- health bar.
--
-- Extra information never gets mixed into Blizzard's lines. Everything EldoUI
-- adds (item level, value, alts, upgrades, auction prices, mob info) goes into
-- one info area at the bottom, under a thin divider, as compact rows with the
-- value right-aligned. Modules and plugins add rows through:
--
--   E:RegisterTooltipSection("inventory", {
--       order = 40,                 -- lower is higher up (see SECTION ORDER)
--       title = "Inventory",        -- the name in options
--       desc  = "...",              -- option tooltip (optional)
--       default = "always",         -- always, shift, ctrl, alt or never
--       item = function(tooltip, itemLink, itemID, add, info) end,
--       unit = function(tooltip, unit, add, data) end, -- data: the tooltip data (guid) or nil
--       object = function(tooltip, name, add, data) end, -- world objects (herbs, ore)
--       quest = function(tooltip, questID, add, data) end, -- quest links
--       spell = function(tooltip, spellID, add, data) end, -- spell tooltips
--       aura = function(tooltip, aura, add, data) end, -- buff and debuff tooltips;
--                                   aura = { unit, auraInstanceID or index, filter }
--       currency = function(tooltip, currencyID, add, data) end, -- currencies
--       module = "PlayerNotes",     -- the module that provides it (optional)
--       option = "tooltip",         -- a switch in that module's settings (optional)
--   })
--   add(left, right, r, g, b, rr, rg, rb)
--       one row; `right` is optional and right-aligned. r, g, b color the
--       left text (default gray label), rr, rg, rb the right (default white).
--   info = { count = stack size under the cursor, shift = IsShiftKeyDown() }
--
-- Each section gets its own visibility setting in options (Always, Shift,
-- Ctrl, Alt, Never), stored by key in the module's `sections` table.
--
-- One list holds every section, and the Tooltip page draws its rows from
-- that list, so a provider never keeps a second copy of the choice. A
-- section that names its `module` shows only while that module is on; with
-- an `option` it also needs that switch of the module turned on. While
-- either is off, its row on the Tooltip page is grayed and says why, and
-- the provider's functions are not called. Registering the same key again
-- replaces the section and keeps the player's choice. Register when the
-- file loads or in OnInitialize, not in OnEnable, so the row is listed
-- while the module is off too.
--
--   E:TooltipSections()        every section in order, as copies:
--                              { key, order, title, desc, default, module,
--                                option, kinds = { "item", ... }, mode, live }
--   E:RefreshTooltipSections() redraws the tooltip under the cursor, so a
--                              section switched on or off shows at once
--                              (out of combat only)
--
-- The section list belongs to EldoUI, not to the module's on/off state:
-- this file always loads, so E:RegisterTooltipSection always exists and
-- modules register once, whatever the Tooltip module does. While the module
-- is off the sections (and the Value row's other pieces) still show as
-- plain rows under Blizzard's own tooltip; only the module's item level and
-- ID rows stay off. Toggling the module never loses a line. That is also
-- why the game's tooltip data callbacks for those plain rows are added once
-- when this file loads: the game has no way to take such a callback back,
-- and they must run while the module is off. Each returns at once while the
-- module is on.
--
-- Blizzard UI page, element "tooltips": EldoUI only changes what the
-- player allowed there.
--   skin     panel, border colors, fonts, scale, the health bar look
--   move     where the tooltip sits (anchor modes, the EldoUI_Tooltip mover)
--   hide     hiding tooltips in combat
--   improve  unit lines (class color, guild, level, target), hidden noise
--            lines, the info area with every module's sections
-- With the element off EldoUI leaves the tooltip exactly as Blizzard made it.
--
-- Midnight/Forever rules: unit fields can be secret in combat. Everything
-- read from a unit or from a tooltip line goes through Safe(), which turns a
-- secret into nil, so EldoUI only skips its extra line and never compares or
-- calculates with hidden data. The health bar keeps Blizzard's own values.
local _, E = ...
local L = E.L

local ELEMENT = "tooltips"

-- Is EldoUI allowed to do `action` to Blizzard's tooltips?
local function Can(action)
	return E:BlizzardAllowed(ELEMENT, action)
end

local M = E:NewModule("Tooltip", {
	title = "Tooltip",
	desc = "Clean tooltips in the game's own style with quality and class borders, a tidy info area and a movable anchor.",
	conflicts = { "TipTac", "TinyTooltip", "ElvUI" },
	frames = { "EldoUI_Tooltip" },
	movers = { "EldoUI_Tooltip" },
	blizzard = { "tooltips" },
	savedKeys = { "profile.modules.Tooltip", "private.pvpDeaths", "private.pvpDeathRecaps" },
	optionsPage = "module:Tooltip",
	presets = { "EldoUI", "Minimal", "Cursor", "Smart", "Classic", "InfoRich" },
	reload = false,
	defaults = {
		skin = true,
		alpha = 0.9,               -- background opacity
		shadow = true,             -- soft shadow around the panel
		ownShadow = false,         -- its own shadow strength and size
		shadowAlpha = E.tokens.shadow.alpha,
		shadowSize = E.tokens.shadow.size,
		borderColor = true,        -- quality / class / reaction border
		anchor = "smart",          -- smart (mover spot, bags, steps aside), fixed (mover), cursor, cursorLeft, cursorRight, blizzard
		cursorX = 0,
		cursorY = 0,
		scale = 1,
		hideInCombat = "never",    -- never, world, frames, units, all
		combatModifier = "SHIFT",  -- NONE, SHIFT, CTRL, ALT: hold to show anyway
		font = true,
		headerSize = 16,
		bodySize = 14,
		smallSize = 12,
		healthBar = true,
		healthBarHeight = 3,
		classColor = true,
		guildRank = true,
		relation = true,           -- Friend, Your guild or Ignored on players
		target = true,
		hidePvP = true,
		hideFaction = false,
		levelColor = true,
		playerItemLevel = true,
		itemLevel = true,
		moveItemLevel = true,      -- Blizzard's item level line moves into the info area
		ids = "shift",             -- never, shift, always: item, spell, aura, NPC, quest, currency and object IDs
		vendorPrice = true,
		hideMadeBy = true,
		hideClickHints = false,
		shortStats = false,
		divider = true,
		sections = {},             -- section key -> always, shift, ctrl, alt, never
	},
})

local TOOLTIPS = {
	"GameTooltip", "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2",
	"ItemRefShoppingTooltip1", "ItemRefShoppingTooltip2", "EmbeddedItemTooltip",
}
-- The info area only goes on the main tooltips, not on comparison tooltips.
local INFO_TOOLTIPS = { GameTooltip = true, ItemRefTooltip = true }

local backdrops = {}    -- tooltip -> EldoUI panel frame
local dividers = {}     -- tooltip -> divider texture
local dividerLine = {}  -- tooltip -> line index the divider sits on
local defaultBorder = {} -- panel -> { r, g, b, a } from the art style
local tinted = {}       -- tooltip -> true while its border carries a color
local skinned = {}      -- tooltip -> true for the tooltips this module styles
local hiddenNine = {}   -- tooltip -> true while EldoUI hides its NineSlice
local clamped = {}      -- tooltip -> the clamp state before EldoUI changed it
local barColor          -- { r, g, b } for the current unit, or nil
local barBackdrop, barPoints, barTexture
local savedFonts = {}   -- font object -> { font, size, flags }
local smartOwner        -- the owner the GameTooltip was placed for in Smart mode
local SmartAdjust       -- defined with the anchor code

local GREY = { 0.65, 0.65, 0.65 }
local WHITE = { 1, 1, 1 }

-- A secret value can be stored and passed on but not compared or used in
-- math. Turn it into nil so callers simply skip the extra line.
local Safe = E.Plain

local function Money(copper)
	return E:FormatMoney(copper)
end

local function Hex(r, g, b)
	return ("|cff%02x%02x%02x"):format(r * 255, g * 255, b * 255)
end

-- Shared money format and optional stack total for every info row.
function E:TooltipMoney(copper, count)
	if type(copper) ~= "number" then return "" end
	local text = Money(copper)
	if not E.Secret(count) and type(count) == "number" and count > 1 and count < math.huge and count % 1 == 0 then
		local gray = Hex(GREY[1], GREY[2], GREY[3])
		text = text .. " " .. gray .. "(" .. count .. ": |r" .. Money(copper * count) .. gray .. ")|r"
	end
	return text
end

local function LineText(tooltip, index, side)
	local name = tooltip:GetName()
	local line = name and _G[("%sText%s%d"):format(name, side or "Left", index)]
	if not line then return end
	return line, Safe(line:GetText())
end

local function ModifierDown(modifier)
	if modifier == "SHIFT" then return IsShiftKeyDown() end
	if modifier == "CTRL" then return IsControlKeyDown() end
	if modifier == "ALT" then return IsAltKeyDown() end
	return false
end

-- Visibility modes shared by sections and the ID lines.
local function ModeShows(mode)
	if mode == "always" or mode == true then return true end
	if mode == "shift" then return IsShiftKeyDown() end
	if mode == "ctrl" then return IsControlKeyDown() end
	if mode == "alt" then return IsAltKeyDown() end
	return false
end

-- Turn a GlobalStrings format ("<Made by %s>") into a Lua pattern.
local function PatternOf(format)
	local spec = E.ChatParse:BuildPattern(format)
	return spec and spec.pattern
end

local function IsWorldOwner(owner)
	return owner == nil or owner == UIParent or owner == WorldFrame
end

-- kind: "unit", "item" or "all"; owner: the frame the tooltip belongs to.
local function ShouldHide(kind, owner)
	local mode = M.db.hideInCombat
	if not Can("hide") then return false end
	if mode == "never" or not InCombatLockdown() or ModifierDown(M.db.combatModifier) then return false end
	if mode == "all" then return true end
	if mode == "units" then return kind == "unit" end
	if mode == "world" then return IsWorldOwner(owner) end
	if mode == "frames" then return not IsWorldOwner(owner) end
	return false
end

-- The combat rule hides the hover tooltip (GameTooltip) only: a link the
-- player clicked and the comparison beside a shown tooltip always show.
-- The hover tooltip is made see-through rather than closed (it is not
-- protected), so the "show anyway" key brings it back at once; it is seen
-- again when it closes, when the next tooltip is not hidden, or after combat.
local combatHidden = false
local function CombatHide(tooltip)
	if tooltip ~= GameTooltip then return end
	tooltip:SetAlpha(0)
	combatHidden = true
	for _, compare in ipairs({ _G.ShoppingTooltip1, _G.ShoppingTooltip2 }) do
		if compare and compare:IsShown() and not E.FrameCheck(compare, "IsForbidden") then compare:Hide() end
	end
end
local function CombatShow(tooltip)
	if not combatHidden or tooltip ~= GameTooltip then return end
	combatHidden = false
	tooltip:SetAlpha(1)
end
M.CombatHidden = function() return combatHidden end -- exposed for inspection

-- Hides GameTooltip when the combat rule says so. kind as ShouldHide; nil
-- reads it from the tooltip ("unit" when it shows a unit, else "all").
local function HideInCombat(tooltip, kind)
	if tooltip ~= GameTooltip then return false end
	if not kind then
		kind = "all"
		if tooltip.GetUnit then
			local ok, _, token = pcall(tooltip.GetUnit, tooltip)
			if ok and Safe(token) then kind = "unit" end
		end
	end
	if not ShouldHide(kind, tooltip:GetOwner()) then
		CombatShow(tooltip)
		return false
	end
	CombatHide(tooltip)
	return true
end

---------------------------------------------------------------------------
-- Info sections
---------------------------------------------------------------------------
local sections = {}      -- ordered list of section definitions
local sectionByKey = {}
local values = {}        -- ordered list of value-line providers
local MODES = { always = "Always", shift = "With Shift", ctrl = "With Ctrl", alt = "With Alt", never = "Never" }
M.sectionModes = MODES

local function SortByOrder(a, b)
	if a.order ~= b.order then return a.order < b.order end
	return a.key < b.key
end

local function SectionMode(section)
	local saved = M.db and M.db.sections and M.db.sections[section.key]
	return saved or section.default or "always"
end

function E:GetTooltipSectionMode(key)
	local section = sectionByKey[key]
	return section and SectionMode(section) or "never"
end

-- Another module's own row for the same choice (Bags > "Show the block")
-- writes here, so the last one changed applies.
function E:SetTooltipSectionMode(key, mode)
	if not (sectionByKey[key] and MODES[mode] and M.db) then return end
	M.db.sections = M.db.sections or {}
	M.db.sections[key] = mode
end

-- The Tooltip module's own rows that only show while it is on (its item
-- level and ID rows). Every other section also shows while it is off.
local MODULE_ONLY = { details = true }

-- The kinds of tooltip a section can add rows to, in the order E:TooltipSections lists them.
local KINDS = { "item", "unit", "object", "quest", "spell", "aura", "currency" }

-- The label of a module's own option row, for the reason text.
local function OptionLabel(module, key)
	local options = type(module.options) == "table" and module.options or nil
	for _, row in ipairs(options or {}) do
		if row.key == key and type(row.label) == "string" then return L[row.label] end
	end
	return key
end

-- Why the section's provider gives no rows now (its module or its switch
-- is off), or nil while it may.
local function ProviderOff(section)
	local name = section.module
	if not name then return nil end
	local module = E.modules[name]
	if not module then return L["%s is not loaded."]:format(name) end
	if not module.active then return E:ModuleOffNote(name) end
	local option = section.option
	if option and not (module.db and module.db[option]) then
		return L["Turned off on the %s page: %s."]:format(L[module.title], OptionLabel(module, option))
	end
	return nil
end

-- May the section's provider add rows now?
local function SectionLive(section)
	return ProviderOff(section) == nil
end

-- Is this section showing on the tooltip right now?
function E:TooltipSectionShown(key)
	local section = sectionByKey[key]
	if not section or not (M.active or not MODULE_ONLY[key]) or not SectionLive(section) then return false end
	return Can("improve") and ModeShows(SectionMode(section)) or false
end

-- Every section in order, as copies (the Tooltip page, plugins and checks
-- read the one list from here).
function E:TooltipSections()
	local list = {}
	for _, section in ipairs(sections) do
		local kinds = {}
		for _, kind in ipairs(KINDS) do
			if section[kind] then kinds[#kinds + 1] = kind end
		end
		list[#list + 1] = {
			key = section.key, order = section.order, title = section.title, desc = section.desc,
			default = section.default, module = section.module, option = section.option, kinds = kinds,
			mode = SectionMode(section), live = SectionLive(section),
		}
	end
	return list
end

-- Redraw the tooltip under the cursor with the game's own refresh, so a
-- section switched on or off shows at once. Out of combat only, and never
-- on a tooltip about a unit the game keeps secret (M.SafeToRedraw, below).
function E:RefreshTooltipSections()
	local tooltip = GameTooltip
	if InCombatLockdown() or not tooltip or not tooltip:IsShown() or E.FrameCheck(tooltip, "IsForbidden") or not tooltip.RefreshData then return end
	if M.SafeToRedraw and not M.SafeToRedraw(tooltip) then return end
	pcall(tooltip.RefreshData, tooltip)
end

local AddSectionOption -- defined with the options below

function E:RegisterTooltipSection(key, def)
	assert(type(key) == "string", "EldoUI:RegisterTooltipSection(key, def): key must be a string")
	assert(type(def) == "table", "EldoUI:RegisterTooltipSection(key, def): def must be a table")
	local section = sectionByKey[key]
	if section then
		for index, entry in ipairs(sections) do
			if entry == section then table.remove(sections, index) break end
		end
	end
	section = {
		key = key,
		order = tonumber(def.order) or 50,
		title = def.title or key,
		desc = def.desc,
		default = MODES[def.default] and def.default or "always",
		item = def.item,
		unit = def.unit,
		object = def.object,
		quest = def.quest,
		spell = def.spell,
		aura = def.aura,
		currency = def.currency,
		module = type(def.module) == "string" and def.module or nil,
		option = type(def.option) == "string" and def.module and def.option or nil,
	}
	sectionByKey[key] = section
	table.insert(sections, section)
	table.sort(sections, SortByOrder)
	-- The default is known to the settings too, so the options show the
	-- changed dot and "Default:", and a reset puts it back.
	M.defaults.sections[key] = section.default
	if M.db and M.db.sections and M.db.sections[key] == nil then M.db.sections[key] = section.default end
	-- Sections registered before the options exist get theirs from the loop
	-- after AddSectionOption is defined.
	if AddSectionOption then AddSectionOption(section) end
end

-- Take a section off again (a plugin that turns its part off): its rows and
-- its option go; the player's saved choice for it stays for a later
-- RegisterTooltipSection with the same key.
function E:UnregisterTooltipSection(key)
	local section = sectionByKey[key]
	if not section then return false end
	sectionByKey[key] = nil
	for index, entry in ipairs(sections) do
		if entry == section then table.remove(sections, index) break end
	end
	M.defaults.sections[key] = nil
	local optionKey = "sections." .. key
	for index, option in ipairs(M.options) do
		if option.key == optionKey then table.remove(M.options, index) break end
	end
	return true
end

-- Pieces of the one-line "Value" row (vendor · auction · age). Providers
-- return a short text such as "AH 3g |cff999999(2h)|r", or nil.
--   E:RegisterTooltipValue("auction", { order = 20, item = function(tooltip, link, id, count) end })
function E:RegisterTooltipValue(key, def)
	for index, entry in ipairs(values) do
		if entry.key == key then table.remove(values, index) break end
	end
	table.insert(values, { key = key, order = tonumber(def.order) or 50, item = def.item })
	table.sort(values, SortByOrder)
end

function E:UnregisterTooltipValue(key)
	for index, entry in ipairs(values) do
		if entry.key == key then
			table.remove(values, index)
			return true
		end
	end
	return false
end

local function ReportOnce(section, err)
	if section.failed then return end
	section.failed = true
	geterrorhandler()(("EldoUI tooltip section %s failed: %s"):format(section.key, tostring(err)))
end

-- Collect the rows of every visible section, in order.
local function CollectRows(tooltip, kind, a, b, info)
	local rows = {}
	local function add(left, right, r, g, b2, rr, rg, rb)
		if left == nil and right == nil then return end
		rows[#rows + 1] = { left = left and tostring(left) or " ", right = right and tostring(right),
			r = r, g = g, b = b2, rr = rr, rg = rg, rb = rb }
	end
	for _, section in ipairs(sections) do
		local fn = section[kind]
		if fn and ModeShows(SectionMode(section)) and SectionLive(section) then
			local ok, err
			if kind == "item" then
				ok, err = pcall(fn, tooltip, a, b, add, info)
			else
				ok, err = pcall(fn, tooltip, a, add, b)
			end
			if not ok then ReportOnce(section, err) end
		end
	end
	return rows
end

local function PlaceDivider(tooltip)
	local divider = dividers[tooltip]
	local index = dividerLine[tooltip]
	if not divider or not index then return end
	local line = LineText(tooltip, index)
	if not line then return end
	divider:ClearAllPoints()
	divider:SetPoint("LEFT", line, "LEFT", 0, 0)
	divider:SetWidth(math.max(tooltip:GetWidth() - 20, 10))
	divider:SetHeight(E.pixel)
	local r, g, b = unpack(E.media.borderColor)
	-- A quiet line: lighter than the border, darker than the text.
	divider:SetColorTexture(math.max(r, 0.25), math.max(g, 0.25), math.max(b, 0.28), 0.9)
	divider:Show()
end

-- Write the rows under one divider. Returns true when anything was added.
local function WriteRows(tooltip, rows)
	if #rows == 0 then return false end
	if M.db.divider and tooltip:GetName() then
		tooltip:AddLine(" ")
		dividerLine[tooltip] = tooltip:NumLines()
	end
	for _, row in ipairs(rows) do
		if row.right then
			local r, g, b = row.r or GREY[1], row.g or GREY[2], row.b or GREY[3]
			tooltip:AddDoubleLine(row.left, row.right, r, g, b, row.rr or WHITE[1], row.rg or WHITE[2], row.rb or WHITE[3])
		else
			tooltip:AddLine(row.left, row.r or WHITE[1], row.g or WHITE[2], row.b or WHITE[3])
		end
	end
	return true
end

---------------------------------------------------------------------------
-- Border color
---------------------------------------------------------------------------
-- A native skin draws its own border art over the panel, so the item
-- quality or reaction color goes on a line just inside that art.
local tintLines = {}    -- panel -> frame with the color line

local function TintLine(bg, r, g, b)
	local mode, id
	if E.Skins then mode, id = E.Skins.State(bg) end
	local line = tintLines[bg]
	if mode ~= "framed" or not r then
		if line then line:Hide() end
		return false
	end
	if not line then
		line = CreateFrame("Frame", nil, bg)
		E:AddBackdrop(line)
		tintLines[bg] = line
	end
	local m = E:SkinManifest(id)
	local inset = m.data and m.data.metrics.borderSize or 2
	line:ClearAllPoints()
	line:SetPoint("TOPLEFT", bg, "TOPLEFT", inset, -inset)
	line:SetPoint("BOTTOMRIGHT", bg, "BOTTOMRIGHT", -inset, inset)
	line:SetBackdrop({ edgeFile = E.media.flat, edgeSize = 2 * E.pixel })
	line:SetBackdropBorderColor(r, g, b, 1)
	line.color = { r, g, b }
	line:Show()
	return true
end
M.TintLine = function(_, tooltip) return tintLines[backdrops[tooltip]] end

local function SetBorder(tooltip, r, g, b)
	if not M.db.borderColor or not Can("skin") then return end
	local bg = backdrops[tooltip]
	if M.db.skin and bg and bg.SetBackdropBorderColor then
		bg:SetBackdropBorderColor(r, g, b, 1)
		TintLine(bg, r, g, b)
	elseif tooltip.NineSlice and tooltip.NineSlice.SetBorderColor then
		tooltip.NineSlice:SetBorderColor(r, g, b)
	end
	tinted[tooltip] = true
end

-- Other modules (Upgrades) may recolor the border of the shown tooltip.
function E:SetTooltipBorder(tooltip, r, g, b)
	if M.active and skinned[tooltip] then SetBorder(tooltip, r, g, b) end
end

local function ResetBorder(tooltip)
	local bg = backdrops[tooltip]
	local color = bg and defaultBorder[bg]
	-- The panel only has backdrop methods once it was skinned.
	if bg and bg.SetBackdropBorderColor then
		if color then bg:SetBackdropBorderColor(color[1], color[2], color[3], color[4] or 1)
		else bg:SetBackdropBorderColor(unpack(E.media.borderColor)) end
	end
	if bg then TintLine(bg) end
	if tinted[tooltip] and not M.db.skin and tooltip.NineSlice and tooltip.NineSlice.SetBorderColor then
		local default = TOOLTIP_DEFAULT_COLOR
		if default then tooltip.NineSlice:SetBorderColor(default.r, default.g, default.b) end
	end
	tinted[tooltip] = nil
end

---------------------------------------------------------------------------
-- Skin
---------------------------------------------------------------------------
-- `full` rebuilds the panel (after a theme or setting change); on every show
-- only the NineSlice and frame level are checked again.
local function UpdateBackdrop(tooltip, full)
	local bg = backdrops[tooltip]
	if not bg then return end
	local on = M.active and M.db.skin and Can("skin")
	bg:SetShown(on)
	if tooltip.NineSlice and (on or hiddenNine[tooltip]) then
		tooltip.NineSlice:SetAlpha(on and 0 or 1)
		hiddenNine[tooltip] = on or nil
	end
	if not on then return end
	bg:SetFrameLevel(math.max(tooltip:GetFrameLevel() - 1, 0))
	if full == true then
		-- The tooltip's own opacity, kept by the panel through art style changes.
		E:SetPanelTemplate(bg, nil, M.db.alpha)
		local br, bgc, bb, ba = bg:GetBackdropBorderColor()
		defaultBorder[bg] = { br, bgc, bb, ba }
		if not tinted[tooltip] then bg:SetBackdropBorderColor(br, bgc, bb, ba) end
		-- The color line follows the new skin (shown only on native skins).
		local line = tintLines[bg]
		if line and line.color and tinted[tooltip] then TintLine(bg, unpack(line.color)) else TintLine(bg) end
	end
	-- The one shared shadow (E:UpdateShadow), set again on every show: an
	-- art style change re-templates the panel and may drop it.
	E:UpdateShadow(bg, M.db.shadow and true or false, M.db.ownShadow and { alpha = M.db.shadowAlpha, size = M.db.shadowSize } or nil)
end

local function HideDivider(tooltip)
	if dividers[tooltip] then dividers[tooltip]:Hide() end
	dividerLine[tooltip] = nil
end

local function SkinTooltip(tooltip)
	if not tooltip or skinned[tooltip] or E.FrameCheck(tooltip, "IsForbidden") then return end
	skinned[tooltip] = true
	local bg = CreateFrame("Frame", nil, tooltip)
	bg:SetAllPoints(tooltip)
	backdrops[tooltip] = bg
	if INFO_TOOLTIPS[tooltip:GetName() or ""] then
		local holder = CreateFrame("Frame", nil, tooltip)
		holder:SetAllPoints(tooltip)
		holder:SetFrameLevel(tooltip:GetFrameLevel() + 1)
		dividers[tooltip] = holder:CreateTexture(nil, "ARTWORK")
		dividers[tooltip]:Hide()
		tooltip:HookScript("OnSizeChanged", function(self)
			if dividerLine[self] then PlaceDivider(self) end
			if smartOwner then SmartAdjust(self) end
		end)
	end
	-- Blizzard re-shows the NineSlice whenever it picks a tooltip style.
	tooltip:HookScript("OnShow", function(self)
		UpdateBackdrop(self)
		if smartOwner then SmartAdjust(self) end
	end)
	tooltip:HookScript("OnTooltipCleared", function(self)
		ResetBorder(self)
		HideDivider(self)
		if self == GameTooltip then barColor = nil end
	end)
end

local function SkinStatusBar()
	local bar = GameTooltipStatusBar
	if not bar then return end
	if not barBackdrop then
		barTexture = bar:GetStatusBarTexture() and bar:GetStatusBarTexture():GetTexture()
		barPoints = {}
		for index = 1, bar:GetNumPoints() do barPoints[index] = { bar:GetPoint(index) } end
		barBackdrop = CreateFrame("Frame", nil, bar)
		barBackdrop:SetPoint("TOPLEFT", -E.pixel, E.pixel)
		barBackdrop:SetPoint("BOTTOMRIGHT", E.pixel, -E.pixel)
		-- Blizzard may recolor the bar when the value changes; keep ours.
		bar:HookScript("OnValueChanged", function(self)
			if M.active and barColor then self:SetStatusBarColor(barColor[1], barColor[2], barColor[3]) end
		end)
	end
	E:SetTemplate(barBackdrop)
	barBackdrop:SetFrameLevel(math.max(bar:GetFrameLevel() - 1, 0))

	local db = M.db
	local skin = M.active and Can("skin")
	if skin and db.skin then
		bar:SetStatusBarTexture(E.media.statusbar)
		bar:ClearAllPoints()
		bar:SetPoint("TOPLEFT", GameTooltip, "BOTTOMLEFT", E.pixel, -4)
		bar:SetPoint("TOPRIGHT", GameTooltip, "BOTTOMRIGHT", -E.pixel, -4)
		bar:SetHeight(db.healthBarHeight)
		barBackdrop:Show()
	else
		if barTexture then bar:SetStatusBarTexture(barTexture) end
		bar:ClearAllPoints()
		for _, point in ipairs(barPoints) do bar:SetPoint(unpack(point)) end
		barBackdrop:Hide()
	end
	bar:SetAlpha((skin and not db.healthBar) and 0 or 1)
end

local FONT_OBJECTS = { header = "GameTooltipHeaderText", body = "GameTooltipText", small = "GameTooltipTextSmall" } -- no-L: font object names

local function ApplyFonts()
	for key, name in pairs(FONT_OBJECTS) do
		local object = _G[name]
		if object then
			if not savedFonts[object] then savedFonts[object] = { object:GetFont() } end
			if M.active and M.db.font and Can("skin") then
				local _, _, flags = object:GetFont()
				-- A game font object, not a FontString: set directly (with Large
				-- text, as E:SetFont would), restored from savedFonts.
				object:SetFont(E.media.font, M.db[key .. "Size"] * E:TextScale(), flags or "")
			else
				local saved = savedFonts[object]
				if saved[1] then object:SetFont(saved[1], saved[2], saved[3] or "") end
			end
		end
	end
end

local function ApplyScale()
	for tooltip in pairs(skinned) do
		-- Embedded tooltips sit inside another tooltip and inherit its scale.
		if tooltip ~= EmbeddedItemTooltip then
			tooltip:SetScale((M.active and Can("skin") and M.db.scale) or 1)
		end
	end
end

---------------------------------------------------------------------------
-- Hiding Blizzard lines (GlobalStrings patterns only)
---------------------------------------------------------------------------
local NOISE = {
	madeBy = { "ITEM_CREATED_BY", "ITEM_WRAPPED_BY" },
	clickHints = { "ITEM_SOCKETABLE", "ITEM_OPENABLE", "ITEM_READABLE" },
}
local noisePatterns = {}

local function BuildPatterns()
	for group, names in pairs(NOISE) do
		noisePatterns[group] = {}
		for _, name in ipairs(names) do
			local pattern = PatternOf(_G[name])
			if pattern then table.insert(noisePatterns[group], pattern) end
		end
	end
	noisePatterns.itemLevel = { PatternOf(ITEM_LEVEL) }
end

local function MatchesAny(text, list)
	for _, pattern in ipairs(list or {}) do
		if text:find(pattern) then return true end
	end
end

-- True when a Blizzard line should be skipped on this tooltip right now.
local function SkipLine(tooltip, text, lineType)
	local db = M.db
	local types = Enum.TooltipDataLineType
	if types and lineType == types.SellPrice then
		return db.vendorPrice and INFO_TOOLTIPS[tooltip:GetName() or ""] and E:TooltipSectionShown("value") or false
	end
	if not text then return false end
	if db.hidePvP and text == PVP then return true end
	if db.hideFaction and (text == FACTION_ALLIANCE or text == FACTION_HORDE or text == FACTION_NEUTRAL) then return true end
	if db.hideMadeBy and MatchesAny(text, noisePatterns.madeBy) then return true end
	if db.hideClickHints and MatchesAny(text, noisePatterns.clickHints) then return true end
	if db.itemLevel and db.moveItemLevel and INFO_TOOLTIPS[tooltip:GetName() or ""]
		and E:TooltipSectionShown("details") and MatchesAny(text, noisePatterns.itemLevel) then
		return true
	end
	return false
end

-- Any line-hiding option on? With all of them off a line is drawn as the
-- game sends it, without a look at its text.
local function LineFilterOn(db)
	return db.hidePvP or db.hideFaction or db.hideMadeBy or db.hideClickHints
		or (db.itemLevel and db.moveItemLevel) or db.vendorPrice
end

-- The game asks before it draws each line, so a skipped line is never drawn.
local function OnLinePre(tooltip, lineData)
	if not M.active or not LineFilterOn(M.db) then return end
	if not skinned[tooltip] or E.FrameCheck(tooltip, "IsForbidden") or type(lineData) ~= "table" or not Can("improve") then return end
	local text = Safe(lineData.leftText)
	if type(text) ~= "string" then text = nil end
	local ok, skip = pcall(SkipLine, tooltip, text, Safe(lineData.type))
	if ok and skip then return true end
end

---------------------------------------------------------------------------
-- Unit tooltips
---------------------------------------------------------------------------
local function UnitColor(unit)
	if Safe(UnitIsPlayer(unit)) then
		local _, class = UnitClass(unit)
		class = Safe(class)
		local color = E:ClassColorObject(class)
		if color then return color.r, color.g, color.b end
	end
	local reaction = Safe(UnitReaction(unit, "player"))
	local color = E:ReactionColorObject(reaction)
	if color then return color.r, color.g, color.b end
end

local function GetTooltipUnit(tooltip, data)
	local unit
	if tooltip.GetUnit then
		local ok, _, token = pcall(tooltip.GetUnit, tooltip)
		unit = ok and Safe(token) or nil
	end
	if not unit and data and UnitTokenFromGUID then
		local guid = Safe(data.guid)
		unit = guid and Safe(UnitTokenFromGUID(guid)) or nil
	end
	if not unit and Safe(UnitExists("mouseover")) then unit = "mouseover" end
	return unit
end

local CLASSIFICATION = {
	worldboss = { E:GameText(BOSS, L["Boss"]), 1, 0.2, 0.2 },
	rareelite = { (E:GameText(ITEM_QUALITY3_DESC, L["Rare"])) .. " " .. (E:GameText(ELITE, L["Elite"])), 1, 0.5, 1 },
	elite = { E:GameText(ELITE, L["Elite"]), 1, 0.82, 0 },
	rare = { E:GameText(ITEM_QUALITY3_DESC, L["Rare"]), 0.7, 0.7, 1 },
}

-- "Level 60 Humanoid" stays one line: the level in its difficulty color,
-- the classification added to the same line.
local function StyleLevelLine(tooltip, unit, after)
	local level = Safe(UnitLevel(unit))
	if not level then return end
	local color = (level > 0 and GetCreatureDifficultyColor) and E:DifficultyColor(GetCreatureDifficultyColor(level))
		or { r = 1, g = 0.2, b = 0.2 }
	local mark = level > 0 and E:LevelMark(level) or ""
	local classification = Safe(UnitClassification(unit))
	local tag = classification and CLASSIFICATION[classification]
	-- The level line comes after the guild line (`after`), so a guild named
	-- with the level word ("<Level 60 Heroes>") is never taken for it.
	for index = math.max(2, (after or 0) + 1), tooltip:NumLines() do
		local line, text = LineText(tooltip, index)
		if text and LEVEL and text:find(LEVEL, 1, true) then
			local hex = Hex(color.r, color.g, color.b)
			text = text:gsub("(%d+)", hex .. "%1|r" .. (mark ~= "" and (" (" .. mark .. ")") or ""), 1):gsub("%?%?", hex .. "??|r", 1)
			if tag and not text:find(tag[1], 1, true) then
				text = text .. " " .. Hex(tag[2], tag[3], tag[4]) .. tag[1] .. "|r"
			end
			line:SetText(text)
			return
		end
	end
end

-- <Guild> in the accent color (read now, so a theme change applies), rank
-- gray. Returns the guild line's index.
local function StyleGuildLine(tooltip, unit)
	local guild, rank = GetGuildInfo(unit)
	guild, rank = Safe(guild), Safe(rank)
	if not guild then return end
	for index = 2, tooltip:NumLines() do
		local line, text = LineText(tooltip, index)
		if text and text:find(guild, 1, true) then
			local r, g, b = unpack(E.media.accentColor)
			local value = Hex(r, g, b) .. "<" .. guild .. ">|r"
			if M.db.guildRank and rank then value = value .. " " .. Hex(GREY[1], GREY[2], GREY[3]) .. rank .. "|r" end
			line:SetText(value)
			return index
		end
	end
end

-- One mark on a player: Ignored, then Friend, then Your guild. It goes on
-- the guild line, or the name line when there is none. Read from the
-- friends and ignore lists the game keeps; skipped in combat and on a
-- secret value.
local function RelationTag(unit)
	if InCombatLockdown() or Safe(UnitIsUnit(unit, "player")) then return end
	local guid = Safe(UnitGUID(unit))
	local lists = C_FriendList
	if guid and lists then
		if lists.IsIgnoredByGuid and Safe(lists.IsIgnoredByGuid(guid)) then return E:TextHex("bad") .. L["Ignored"] .. "|r" end
		if lists.IsFriend and Safe(lists.IsFriend(guid)) then return E:TextHex("good") .. L["Friend"] .. "|r" end
	end
	if UnitIsInMyGuild and Safe(UnitIsInMyGuild(unit)) then
		local r, g, b = unpack(E.media.accentColor)
		return Hex(r, g, b) .. L["Your guild"] .. "|r"
	end
end

local function AddRelationTag(tooltip, unit, guildLine)
	local tag = RelationTag(unit)
	if not tag then return end
	local line, text = LineText(tooltip, guildLine or 1)
	if not (line and text) or text:find(tag, 1, true) then return end
	line:SetText(text .. "  " .. tag)
end
M.RelationTag = RelationTag -- for plugins

-- The name line, the target and "targeted by" lines follow the name
-- format.
E:RegisterNameFormatUser("Tooltip", { title = "Tooltip", order = 40,
	desc = "Name format in unit tooltips: the name line, the Target line and the \"Targeted by\" list. Needs Improve for the tooltip on the Blizzard UI page." })

-- The game writes "First Surname" into the first line (maybe with a title
-- or realm around it). Only that exact text is swapped for the chosen
-- format; a secret line or one written differently is left alone.
local function StyleNameLine(tooltip, unit)
	if E:NameFormat("Tooltip") == "blizzard" then return end
	local first, last = E:NameParts(unit, true)
	first, last = Safe(first), Safe(last)
	if not (first and last) then return end
	local line, text = LineText(tooltip, 1)
	if not (line and text) then return end
	local shown = E:FormatName(first, last, "full")
	local at, stop = text:find(shown, 1, true)
	if not at then return end
	local wanted = Safe(E:DisplayName(unit, "Tooltip"))
	if type(wanted) ~= "string" or wanted == shown then return end
	line:SetText(text:sub(1, at - 1) .. wanted .. text:sub(stop + 1))
end
M.StyleNameLine = StyleNameLine -- for plugins

local function AddTargetLine(tooltip, unit)
	local target = unit .. "target"
	if not Safe(UnitExists(target)) then return end
	local text
	if Safe(UnitIsUnit(target, "player")) then
		text = E:TextHex("bad") .. ">> " .. (E:GameText(YOU, L["You"])) .. " <<|r"
	else
		local name = Safe(E:DisplayName(target, "Tooltip"))
		if not name then return end
		local r, g, b = UnitColor(target)
		text = r and (Hex(r, g, b) .. name .. "|r") or name
	end
	tooltip:AddDoubleLine(E:GameText(TARGET, L["Target"]), text, GREY[1], GREY[2], GREY[3], 1, 1, 1)
	return true
end

-- Item level only when the game already knows it: your own, or a player
-- you inspected yourself. EldoUI never sends inspect requests.
local function PlayerItemLevel(unit)
	local level
	if Safe(UnitIsUnit(unit, "player")) then
		if GetAverageItemLevel then
			local _, equipped = GetAverageItemLevel()
			level = Safe(equipped)
		end
	elseif C_PaperDollInfo and C_PaperDollInfo.GetInspectItemLevel then
		level = Safe(C_PaperDollInfo.GetInspectItemLevel(unit))
	end
	if type(level) == "number" and level > 0 then return level end
end

local function OnUnit(tooltip, data)
	if not M.active or tooltip ~= GameTooltip or E.FrameCheck(tooltip, "IsForbidden") then return end
	if HideInCombat(tooltip, "unit") then return end
	local unit = GetTooltipUnit(tooltip, data)
	if not unit then return end
	local db = M.db
	local r, g, b = UnitColor(unit)
	local added = false
	local improve = Can("improve")

	if r then
		if db.classColor and improve then
			local line = LineText(tooltip, 1)
			if line then line:SetTextColor(r, g, b) end
		end
		SetBorder(tooltip, r, g, b)
		if Can("skin") then
			barColor = { r, g, b }
			if GameTooltipStatusBar then GameTooltipStatusBar:SetStatusBarColor(r, g, b) end
		end
	end
	if not improve then return end
	local guildLine
	if Safe(UnitIsPlayer(unit)) then
		StyleNameLine(tooltip, unit)
		guildLine = StyleGuildLine(tooltip, unit)
		if db.relation then AddRelationTag(tooltip, unit, guildLine) end
	end
	if db.levelColor then StyleLevelLine(tooltip, unit, guildLine) end
	if db.target and AddTargetLine(tooltip, unit) then added = true end
	if WriteRows(tooltip, CollectRows(tooltip, "unit", unit, data)) then added = true end
	if added then tooltip:Show() end
	if dividerLine[tooltip] then PlaceDivider(tooltip) end
end

---------------------------------------------------------------------------
-- Item tooltips
---------------------------------------------------------------------------
local function StackCount(tooltip)
	local owner = tooltip:GetOwner()
	if not owner then return 1 end
	if owner.GetBagID and owner.GetID then
		local ok, bag = pcall(owner.GetBagID, owner)
		local info = ok and bag and C_Container.GetContainerItemInfo(bag, owner:GetID())
		if info and info.stackCount then return info.stackCount end
	end
	return type(owner.count) == "number" and owner.count > 0 and owner.count or 1
end


-- The client supplies both the verbose format and the compact stat name.
-- Preserve the captured amount so decimal punctuation follows its locale.
local SHORT_STAT_TYPES = {
	{ "SPELL_POWER", "ITEM_MOD_SPELL_POWER_SHORT" },
	{ "SPELL_DAMAGE", "ITEM_MOD_SPELL_DAMAGE_DONE_SHORT" },
	{ "SPELL_HEALING", "ITEM_MOD_SPELL_HEALING_DONE_SHORT" },
	{ "ATTACK_POWER", "ITEM_MOD_ATTACK_POWER_SHORT" },
	{ "BLOCK_VALUE", "ITEM_MOD_BLOCK_VALUE_SHORT" },
	{ "DEFENSE", "COMBAT_RATING_NAME2" },
	{ "CRIT_PERCENT", "COMBAT_RATING_NAME9", true },
	{ "HIT_PERCENT", "COMBAT_RATING_NAME6", true },
	{ "DODGE_PCT", "COMBAT_RATING_NAME3", true },
	{ "PARRY_PCT", "COMBAT_RATING_NAME4", true },
	{ "EXPERTISE_PCT", "COMBAT_RATING_NAME24", true },
	{ "HASTE_PCT", "ITEM_MOD_HASTE_RATING_SHORT", true },
	{ "MANA_REGEN", "ITEM_MOD_MANA_REGENERATION_SHORT" },
	{ "HEALTH_REGEN", "ITEM_MOD_HEALTH_REGEN_SHORT" },
}
local SHORT_STAT_DIRECTIONS = { "INCREASE", "DECREASE" }
local shortStatPatterns = {}
local function StatPattern(format)
	local pattern = shortStatPatterns[format]
	if pattern == nil then
		pattern = E.ItemScore.StatFormatPattern(format) or false
		shortStatPatterns[format] = pattern
	end
	return pattern or nil
end

local function ShortStatLine(text)
	if type(text) ~= "string" then return end
	local color, plain = text:match("^(|c%x%x%x%x%x%x%x%x)(.-)|r$")
	plain = plain or text
	for _, stat in ipairs(SHORT_STAT_TYPES) do
		local label = Safe(rawget(_G, stat[2]))
		if type(label) == "string" and label ~= "" then
			for _, direction in ipairs(SHORT_STAT_DIRECTIONS) do
				local format = Safe(rawget(_G, "TOOLTIP_ITEM_STAT_" .. stat[1] .. "_" .. direction))
				local pattern = type(format) == "string" and StatPattern(format)
				local amount = pattern and plain:match(pattern)
				if amount then
					local short = (direction == "INCREASE" and "+" or "-") .. amount .. (stat[3] and "% " or " ") .. label
					return color and (color .. short .. "|r") or short
				end
			end
		end
	end
	local short = E.ItemScore:ShortEquipText(plain)
	if short then return color and (color .. short .. "|r") or short end
end

local function ShortenItemStats(tooltip)
	if not M.db.shortStats then return end
	for index = 2, tooltip:NumLines() do
		local line, text = LineText(tooltip, index)
		local short = text and ShortStatLine(text)
		if short then line:SetText(short) end
	end
end

local function OnItem(tooltip, data)
	if not M.active or not skinned[tooltip] or E.FrameCheck(tooltip, "IsForbidden") then return end
	if tooltip == GameTooltip then
		if HideInCombat(tooltip, "item") then return end
	elseif combatHidden and tooltip:GetOwner() == GameTooltip then
		-- A comparison follows the tooltip it sits beside.
		tooltip:Hide()
		return
	end
	local ok, _, link, id = pcall(tooltip.GetItem, tooltip)
	if not ok then return end
	link = Safe(link)
	id = Safe(id) or (data and Safe(data.id))
	if not link and not id then return end
	local _, _, quality = C_Item.GetItemInfo(link or id)

	if quality and quality > 1 then
		local r, g, b
		if C_Item.GetItemQualityColor then
			r, g, b = C_Item.GetItemQualityColor(quality)
		elseif ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality] then
			local color = ITEM_QUALITY_COLORS[quality]
			r, g, b = color.r, color.g, color.b
		end
		if r then SetBorder(tooltip, r, g, b) end
	end

	if not Can("improve") then return end
	ShortenItemStats(tooltip)
	if not INFO_TOOLTIPS[tooltip:GetName() or ""] then return end
	local info = { count = StackCount(tooltip), shift = IsShiftKeyDown() }
	local rows = CollectRows(tooltip, "item", link, id, info)
	if WriteRows(tooltip, rows) then tooltip:Show() end
	if dividerLine[tooltip] then PlaceDivider(tooltip) end
end

-- Which aura a buff or debuff tooltip shows, from the call the game made
-- to fill it: { unit, auraInstanceID or index, filter }, or nil.
local AURA_GETTERS = {
	GetUnitAura = true, GetUnitBuff = "HELPFUL", GetUnitDebuff = "HARMFUL",
	GetUnitBuffByAuraInstanceID = "HELPFUL", GetUnitDebuffByAuraInstanceID = "HARMFUL",
}
local function TooltipAura(tooltip)
	local info
	for _, method in ipairs({ "GetProcessingTooltipInfo", "GetPrimaryTooltipInfo" }) do
		local fn = not info and tooltip[method]
		if type(fn) == "function" then
			local ok, value = pcall(fn, tooltip)
			if ok and not E.Secret(value) and type(value) == "table" then info = value end
		end
	end
	if not info and not E.Secret(tooltip.processingInfo) and type(tooltip.processingInfo) == "table" then info = tooltip.processingInfo end
	if not info then return end
	local getter, args = Safe(info.getterName), info.getterArgs
	local filter = type(getter) == "string" and AURA_GETTERS[getter]
	if not filter or E.Secret(args) or type(args) ~= "table" then return end
	local unit, second, given = Safe(args[1]), Safe(args[2]), Safe(args[3])
	if type(unit) ~= "string" or type(second) ~= "number" then return end
	if filter == true then
		filter = type(given) == "string" and given or "HELPFUL"
	elseif type(given) == "string" and not given:find(filter, 1, true) then
		filter = filter .. "|" .. given
	end
	local aura = { unit = unit, filter = filter }
	if getter:find("AuraInstanceID", 1, true) then aura.auraInstanceID = second else aura.index = second end
	return aura
end
M.TooltipAura = TooltipAura -- for plugins

-- Spells: the Spell ID row, then sections with a `spell` function. Aura
-- tooltips (buffs and debuffs): the Spell ID row, then sections with an
-- `aura` function.
local function SpellRows(tooltip, data, kind)
	if not M.active or not skinned[tooltip] or E.FrameCheck(tooltip, "IsForbidden") then return end
	if HideInCombat(tooltip, "all") or not Can("improve") then return end
	local id = data and Safe(data.id)
	if type(id) ~= "number" then return end
	local rows
	if kind == "aura" then
		local aura = TooltipAura(tooltip)
		rows = aura and CollectRows(tooltip, "aura", aura, data) or {}
	else
		rows = CollectRows(tooltip, "spell", id, data)
	end
	if ModeShows(M.db.ids) then table.insert(rows, 1, { left = L["Spell ID"], right = tostring(id) }) end
	if WriteRows(tooltip, rows) then
		tooltip:Show()
		if dividerLine[tooltip] then PlaceDivider(tooltip) end
	end
end

local function OnSpell(tooltip, data) SpellRows(tooltip, data, "spell") end
local function OnAura(tooltip, data) SpellRows(tooltip, data, "aura") end

-- Cast by: the player or pet who cast a buff or debuff, from the aura data
-- the game gives addons. No row when the caster is secret.
local function AuraData(aura)
	local api = C_UnitAuras
	if not api then return end
	local ok, data
	if aura.auraInstanceID and api.GetAuraDataByAuraInstanceID then
		ok, data = pcall(api.GetAuraDataByAuraInstanceID, aura.unit, aura.auraInstanceID)
	elseif aura.index and api.GetAuraDataByIndex then
		ok, data = pcall(api.GetAuraDataByIndex, aura.unit, aura.index, aura.filter)
	end
	if ok and not E.Secret(data) and type(data) == "table" then return data end
end

local function PetOwner(unit)
	if unit == "pet" then return "player" end
	local kind, index = unit:match("^(%a-)pet(%d+)$")
	if kind == "party" or kind == "raid" then return kind .. index end
end

local function CasterName(unit)
	local name = Safe(E:DisplayName(unit, "Tooltip"))
	if type(name) ~= "string" or name == "" then return end
	local r, g, b = UnitColor(unit)
	return r and (Hex(r, g, b) .. name .. "|r") or name
end

local function CastByAura(_, aura, add)
	local data = AuraData(aura)
	local source = data and Safe(data.sourceUnit)
	if type(source) ~= "string" or source == "" then return end
	local text
	if Safe(UnitIsUnit(source, "player")) then
		text = E:GameText(YOU, L["You"])
	else
		local owner = PetOwner(source)
		if owner == "player" then
			text = L["Your pet"]
		elseif owner then
			local name = CasterName(owner)
			text = name and L["%s's pet"]:format(name)
		else
			text = CasterName(source)
		end
	end
	if text then add(L["Cast by"], text) end
end

-- World objects (herbs, ore veins, chests): sections with an `object`
-- function get the object's name (the tooltip's first line) and the data.
local function ObjectName(tooltip, data)
	local _, name = LineText(tooltip, 1)
	if not name and data and type(data.lines) == "table" and data.lines[1] then
		name = Safe(data.lines[1].leftText)
	end
	if type(name) == "string" and name ~= "" then return name end
end

-- The ID row at the end of the info area, under the one Show IDs choice.
local function IdRow(rows, label, id)
	if type(id) == "number" and ModeShows(M.db.ids) then rows[#rows + 1] = { left = label, right = tostring(id) } end
	return rows
end

local function OnObject(tooltip, data)
	if not M.active or tooltip ~= GameTooltip or E.FrameCheck(tooltip, "IsForbidden") then return end
	if HideInCombat(tooltip, "all") or not Can("improve") then return end
	local name = ObjectName(tooltip, data)
	if not name then return end
	if WriteRows(tooltip, IdRow(CollectRows(tooltip, "object", name, data), L["Object ID"], data and Safe(data.id))) then
		tooltip:Show()
		if dividerLine[tooltip] then PlaceDivider(tooltip) end
	end
end

-- Quest links: sections with a `quest` function get the quest ID.
local function OnQuest(tooltip, data)
	if not M.active or not skinned[tooltip] or E.FrameCheck(tooltip, "IsForbidden") or not Can("improve") then return end
	if not INFO_TOOLTIPS[tooltip:GetName() or ""] then return end
	local id = data and Safe(data.id)
	if type(id) ~= "number" then return end
	if WriteRows(tooltip, IdRow(CollectRows(tooltip, "quest", id, data), L["Quest ID"], id)) then
		tooltip:Show()
		if dividerLine[tooltip] then PlaceDivider(tooltip) end
	end
end

-- Currencies: sections with a `currency` function get the currency ID.
local function OnCurrency(tooltip, data)
	if not M.active or not skinned[tooltip] or E.FrameCheck(tooltip, "IsForbidden") or not Can("improve") then return end
	if not INFO_TOOLTIPS[tooltip:GetName() or ""] or HideInCombat(tooltip, "all") then return end
	local id = data and Safe(data.id)
	if type(id) ~= "number" then return end
	if WriteRows(tooltip, IdRow(CollectRows(tooltip, "currency", id, data), L["Currency ID"], id)) then
		tooltip:Show()
		if dividerLine[tooltip] then PlaceDivider(tooltip) end
	end
end

-- Opposing players who dealt the killing blow to this character.
do
	local Read = E.PlainCall
	local SECTION = "pvpDeaths"
	local RECAPS = "pvpDeathRecaps"
	local life, observed
	E:RegisterPrivate(SECTION, {})
	E:RegisterPrivate(RECAPS, {})

	local function ReadableTable(value)
		return not E.Secret(value) and type(value) == "table"
			and (not canaccesstable or canaccesstable(value))
	end

	local function PlayerGUID(guid)
		return type(guid) == "string" and guid:match("^Player%-%d+%-%x+$") and guid or nil
	end

	local function Faction(tag)
		return (tag == "Alliance" or tag == "Horde") and tag or nil
	end

	local function WholeNumber(value)
		return type(value) == "number" and value >= 0 and value < math.huge and value % 1 == 0
	end

	local function SavedCount(value)
		local count = Safe(value)
		return WholeNumber(count) and count > 0 and count or nil
	end

	local function RecapID(value)
		return WholeNumber(value) and value > 0 and value or nil
	end

	local function RecapStamp(value)
		return type(value) == "number" and value > 0 and value < math.huge and value or nil
	end

	-- The two Skyborne entries can share a race token. A token that does
	-- not identify one faction can only be resolved through a unit.
	local function RaceFaction(guid)
		local _, _, _, race = E.PlainCallEach(GetPlayerInfoByGUID, guid)
		local info = C_CreatureInfo
		if type(race) ~= "string" or not info then return end
		local faction
		for _, id in ipairs({ 1, 2, 3, 4, 5, 6, 7, 8, 95, 96 }) do
			local entry = Read(info.GetRaceInfo, id)
			if ReadableTable(entry) and Safe(entry.clientFileString) == race then
				local group = Read(info.GetFactionInfo, id)
				local tag = ReadableTable(group) and Faction(Safe(group.groupTag))
				if not tag or (faction and faction ~= tag) then return end
				faction = tag
			end
		end
		return faction
	end

	local function KillerFaction(guid)
		if type(UnitTokenFromGUID) == "function" then
			local ok, unit = pcall(UnitTokenFromGUID, guid)
			if not ok or E.Secret(unit) then return end
			if unit ~= nil then
				if type(unit) ~= "string" or Read(UnitGUID, unit) ~= guid then return end
				return Faction(Read(UnitFactionGroup, unit))
			end
		end
		return RaceFaction(guid)
	end

	-- Blizzard marks the first row of this recap as the killing blow.
	-- A readable empty table establishes that there was no earlier recap.
	local function Recap()
		local api = C_DeathRecap
		if not api then return end
		local link = Read(api.GetRecapLink)
		local id = type(link) == "string" and RecapID(tonumber(link:match("|Hdeath:(%d+)|h"))) or nil
		local events = Read(api.GetRecapEvents, id)
		if not ReadableTable(events) then return id and { id = id } end
		local hit = events[1]
		if not ReadableTable(hit) then
			if id or (not E.Secret(hit) and hit == nil) then return { id = id } end
			return
		end
		local stamp = RecapStamp(Safe(hit.timestamp))
		if not (id or stamp) then return end
		return { id = id, stamp = stamp, hit = hit }
	end

	local function NewerRecap(after, id, stamp)
		if not (id or stamp) then return true end
		if id and id == after.id then return false end
		if stamp and after.stamp then return after.stamp > stamp end
		return id and after.id
	end

	local function SameSavedRecap(recap, previous)
		if not ReadableTable(previous) then return false end
		local id = RecapID(Safe(previous.id))
		local stamp = RecapStamp(Safe(previous.stamp))
		if stamp and recap.stamp then
			return stamp == recap.stamp and (not id or not recap.id or id == recap.id)
		end
		return id and id == recap.id
	end

	local function ObserveRecap(owner, recap, baseline)
		local sameSession = observed and observed.owner == owner and observed.private == E.private
		if sameSession and not NewerRecap(recap, observed.id, observed.stamp) then return false end
		local recaps = E:GetPrivate(RECAPS)
		if not recaps then return false end
		-- Only deduplicate the saved identity. Timestamp ordering is
		-- confined to the recaps this session has observed.
		local alreadySaved = SameSavedRecap(recap, recaps[owner])
		if alreadySaved and not baseline then return false end
		if not alreadySaved then recaps[owner] = { id = recap.id, stamp = recap.stamp } end
		observed = {
			owner = owner, private = E.private, id = recap.id,
			stamp = recap.stamp or (sameSession and observed.stamp) or nil,
		}
		return true
	end

	local function Arm()
		life = nil
		if Read(UnitIsDeadOrGhost, "player") ~= false then return end
		local owner = PlayerGUID(Read(UnitGUID, "player"))
		local before = owner and Recap()
		if not before then return end
		if before.id or before.stamp then ObserveRecap(owner, before, true) end
		life = { owner = owner, private = E.private, id = before.id, stamp = before.stamp }
	end

	local function EnterWorld(_, _, initial, reload)
		if initial or reload then observed = nil end
		Arm()
	end

	local function Record(current)
		local after = Recap()
		if not (after and after.hit and NewerRecap(after, current.id, current.stamp)
			and ObserveRecap(current.owner, after)) then return false end

		local hit = after.hit
		local guid = PlayerGUID(Safe(hit.sourceGUID))
		local flags = Safe(hit.sourceFlags)
		local hidden = hit.hideCaster
		local object = Enum and Enum.CombatLogObject
		if not guid or guid == current.owner or not WholeNumber(flags) or flags > 0xFFFFFFFF or not object
			or bit.band(flags, object.TypePlayer) == 0 or bit.band(flags, object.ReactionHostile) == 0
			or E.Secret(hidden) or (hidden ~= nil and hidden ~= false) then return true end

		local mine = Faction(Read(UnitFactionGroup, "player"))
		local theirs = mine and KillerFaction(guid)
		if not theirs or mine == theirs then return true end

		local store = E:GetPrivate(SECTION)
		if not store then return true end
		local counts = store[current.owner]
		if type(counts) ~= "table" then
			counts = {}
			store[current.owner] = counts
		end
		counts[guid] = (SavedCount(counts[guid]) or 0) + 1
		local nemesis = E.modules.Nemesis
		if nemesis and nemesis.OnPvPDeathCountChanged then
			local ok = pcall(nemesis.OnPvPDeathCountChanged, nemesis, current.owner, guid)
			if not ok then E:Debug("The Nemesis history could not refresh.") end
		end
		return true
	end

	local function OnDeath()
		local current = life
		if not current or current.dead or Read(UnitIsDeadOrGhost, "player") ~= true then return end
		current.dead = true
		local function Try()
			if life ~= current or E.private ~= current.private or Read(UnitGUID, "player") ~= current.owner
				or Read(UnitIsDeadOrGhost, "player") ~= true then return true end
			return Record(current)
		end
		-- The recap can arrive just after the death event. Read it once
		-- more while the same death still owns the attempt.
		if not Try() then C_Timer.After(0.3, Try) end
	end

	E:RegisterEvent("PLAYER_ENTERING_WORLD", EnterWorld, M)
	E:RegisterEvent("PLAYER_ALIVE", Arm, M)
	E:RegisterEvent("PLAYER_UNGHOST", Arm, M)
	E:RegisterEvent("PLAYER_DEAD", OnDeath, M)

	E:RegisterTooltipSection(SECTION, {
		order = 58, title = "PvP death count", default = "always",
		desc = "Shows how many times a player from the other faction has killed this character, when the game identified the killer.",
		unit = function(_, unit, add, data)
			if not ReadableTable(data) then return end
			local guid = PlayerGUID(Safe(data.guid))
			local owner = guid and PlayerGUID(Read(UnitGUID, "player"))
			local store = owner and E:GetPrivate(SECTION)
			local counts = store and store[owner]
			local count = type(counts) == "table" and SavedCount(counts[guid])
			if not count then return end
			if Read(UnitGUID, unit) ~= guid or Read(UnitIsPlayer, unit) ~= true then return end
			local mine = Faction(Read(UnitFactionGroup, "player"))
			local theirs = Faction(Read(UnitFactionGroup, unit))
			if mine and theirs and mine ~= theirs then add(L["Killed you"], tostring(count)) end
		end,
	})
end

-- Built-in rows ------------------------------------------------------------
local ITEM_LEVEL_LABEL = E:GameText(STAT_AVERAGE_ITEM_LEVEL, L["Item Level"])

local function DetailsItem(_, link, id, add)
	local db = M.db
	if db.itemLevel and link and C_Item.IsEquippableItem and C_Item.IsEquippableItem(link) and C_Item.GetDetailedItemLevelInfo then
		local level = C_Item.GetDetailedItemLevelInfo(link)
		if type(level) == "number" and level > 1 then add(ITEM_LEVEL_LABEL, tostring(level)) end
	end
	-- How many fit in one stack: the game never says. With Shift.
	if id and IsShiftKeyDown() and C_Item.GetItemMaxStackSizeByID then
		local stack = Safe(C_Item.GetItemMaxStackSizeByID(id))
		if type(stack) == "number" and stack > 1 then add(L["Stack size"], tostring(stack)) end
	end
	if id and ModeShows(db.ids) then add(L["Item ID"], tostring(id)) end
end

-- The NPC ID of a creature from its GUID ("Creature-0-...-<id>-..."), or
-- nil for players, pets and a secret GUID.
local function NpcID(unit)
	local guid = Safe(UnitGUID(unit))
	if type(guid) ~= "string" then return nil end
	local kind, _, _, _, _, id = strsplit("-", guid)
	if kind ~= "Creature" and kind ~= "Vehicle" then return nil end
	return tonumber(id)
end
M.NpcID = NpcID -- for plugins

local function DetailsUnit(_, unit, add)
	if M.db.playerItemLevel and Safe(UnitIsPlayer(unit)) then
		local level = PlayerItemLevel(unit)
		if level then add(ITEM_LEVEL_LABEL, ("%d"):format(level)) end
	end
	local npc = ModeShows(M.db.ids) and NpcID(unit)
	if npc then add(L["NPC ID"], tostring(npc)) end
end

local function ValueItem(tooltip, link, id, add, info)
	local pieces = {}
	local vendorOnly = true
	local count = info and info.count or 1
	-- Plain rows (module off): Blizzard's own money line has the vendor price.
	if M.db.vendorPrice and not (info and info.plain) then
		local sellPrice = select(11, C_Item.GetItemInfo(link or id))
		if type(sellPrice) == "number" and sellPrice > 0 then
			pieces[#pieces + 1] = E:TooltipMoney(sellPrice, count)
		end
	end
	for _, provider in ipairs(values) do
		local ok, text = pcall(provider.item, tooltip, link, id, count)
		if ok and type(text) == "string" and text ~= "" then
			pieces[#pieces + 1] = text
			vendorOnly = false
		end
	end
	if #pieces > 0 then
		-- The game's "Sell Price" only for the vendor price alone; with an
		-- auction or other price in the row it is the section's "Value".
		local label = vendorOnly and SELL_PRICE and SELL_PRICE:gsub(":%s*$", "") or L["Value"]
		add(label, table.concat(pieces, Hex(GREY[1], GREY[2], GREY[3]) .. " · |r"))
	end
end

-- Section order: 10 upgrade, 20 item level and IDs, 30 value, 40 alts, 50 quest and mob info, 55 spell and currency rows, 56 cast by.
E:RegisterTooltipSection("details", { order = 20, title = "Item level and IDs",
	desc = "Item level on gear (moved out of Blizzard's lines), a player's item level, and the item ID as set below.",
	item = DetailsItem, unit = DetailsUnit })
M.DetailsRows = { item = DetailsItem, unit = DetailsUnit } -- for plugins that build their own tooltip
E:RegisterTooltipSection("caster", { order = 56, title = "Cast by",
	desc = "On buff and debuff tooltips: the player or pet who cast it. Not shown when the game keeps the caster hidden.",
	aura = CastByAura })
E:RegisterTooltipSection("value", { order = 30, title = "Value",
	desc = "One line: vendor price (each and stack) plus auction price and its age when an auction module provides them.",
	item = ValueItem })

---------------------------------------------------------------------------
-- Plain rows while the Tooltip module is off: every section (alts and
-- bank, recipes, quests, upgrade, mob info, the Value row's auction and
-- account pieces) still shows, as plain lines under Blizzard's own tooltip
-- with no restyle. Only the module's item level and ID rows stay off.
---------------------------------------------------------------------------

local Plain = E.Plain

local function FallbackRows(tooltip, kind, a, b)
	if M.active or not M.db or E.FrameCheck(tooltip, "IsForbidden") or not Can("improve") then return end
	if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
	local rows = {}
	local function add(left, right, r, g, b2, rr, rg, rb)
		if left == nil and right == nil then return end
		rows[#rows + 1] = { left = left and tostring(left) or " ", right = right and tostring(right),
			r = r, g = g, b = b2, rr = rr, rg = rg, rb = rb }
	end
	for _, section in ipairs(sections) do
		local fn = not MODULE_ONLY[section.key] and section[kind]
		if fn and ModeShows(SectionMode(section)) and SectionLive(section) then
			local ok, err
			if kind == "item" then
				ok, err = pcall(fn, tooltip, a, b, add, { count = 1, shift = IsShiftKeyDown(), plain = true })
			else
				ok, err = pcall(fn, tooltip, a, add, b)
			end
			if not ok then ReportOnce(section, err) end
		end
	end
	if #rows == 0 then return end
	tooltip:AddLine(" ")
	for _, row in ipairs(rows) do
		if row.right then
			tooltip:AddDoubleLine(row.left, row.right, row.r or GREY[1], row.g or GREY[2], row.b or GREY[3],
				row.rr or WHITE[1], row.rg or WHITE[2], row.rb or WHITE[3])
		else
			tooltip:AddLine(row.left, row.r or WHITE[1], row.g or WHITE[2], row.b or WHITE[3])
		end
	end
	tooltip:Show()
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum.TooltipDataType then
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip)
		if M.active or not tooltip.GetItem then return end
		local ok, _, link, id = pcall(tooltip.GetItem, tooltip)
		link, id = ok and Plain(link), ok and Plain(id)
		if link or id then FallbackRows(tooltip, "item", link, id) end
	end)
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip, data)
		if M.active or not tooltip.GetUnit then return end
		local ok, _, unit = pcall(tooltip.GetUnit, tooltip)
		unit = ok and Plain(unit)
		if type(unit) == "string" then FallbackRows(tooltip, "unit", unit, data) end
	end)
	if Enum.TooltipDataType.Object then
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Object, function(tooltip, data)
			if M.active or tooltip ~= GameTooltip or E.FrameCheck(tooltip, "IsForbidden") then return end
			local name = ObjectName(tooltip, data)
			if name then FallbackRows(tooltip, "object", name, data) end
		end)
	end
	if Enum.TooltipDataType.Quest then
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Quest, function(tooltip, data)
			if M.active then return end
			local id = data and Plain(data.id)
			if type(id) == "number" then FallbackRows(tooltip, "quest", id, data) end
		end)
	end
	if Enum.TooltipDataType.UnitAura then
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.UnitAura, function(tooltip)
			if M.active then return end
			local aura = TooltipAura(tooltip)
			if aura then FallbackRows(tooltip, "aura", aura) end
		end)
	end
	for kind, dataType in pairs({ spell = Enum.TooltipDataType.Spell, currency = Enum.TooltipDataType.Currency }) do
		TooltipDataProcessor.AddTooltipPostCall(dataType, function(tooltip, data)
			if M.active then return end
			local id = data and Plain(data.id)
			if type(id) == "number" then FallbackRows(tooltip, kind, id, data) end
		end)
	end
end
M.PlainRows = FallbackRows -- the rows while the module is off
M.SectionHooks = { spell = OnSpell, aura = OnAura, currency = OnCurrency, quest = OnQuest, object = OnObject } -- and the module-on path

---------------------------------------------------------------------------
-- Hooks
---------------------------------------------------------------------------
local function HookDataTypes()
	local types = Enum.TooltipDataType
	TooltipDataProcessor.AddTooltipPostCall(types.Unit, OnUnit)
	TooltipDataProcessor.AddTooltipPostCall(types.Item, OnItem)
	if types.Spell then TooltipDataProcessor.AddTooltipPostCall(types.Spell, OnSpell) end
	if types.UnitAura then TooltipDataProcessor.AddTooltipPostCall(types.UnitAura, OnAura) end
	if types.Currency then TooltipDataProcessor.AddTooltipPostCall(types.Currency, OnCurrency) end
	if types.Object then TooltipDataProcessor.AddTooltipPostCall(types.Object, OnObject) end
	if types.Quest then TooltipDataProcessor.AddTooltipPostCall(types.Quest, OnQuest) end
	M.OnLinePre = OnLinePre
	for _, lineType in pairs(Enum.TooltipDataLineType) do
		if type(lineType) == "number" then
			TooltipDataProcessor.AddLinePreCall(lineType, OnLinePre)
		end
	end
end

-- A unit tooltip whose unit the game keeps secret (a nameplate, a unit the
-- game restricts) or that cannot be read. The game's own redraw of such a
-- tooltip, started from EldoUI's modifier handler, would hand that secret
-- unit to the game's unit color code outside the game's own call and fail
-- there, so that tooltip is left as it is.
local function SecretUnitTooltip(tooltip)
	if type(tooltip.GetUnit) ~= "function" then return false end
	local ok, _, unit = pcall(tooltip.GetUnit, tooltip)
	if not ok or E.Secret(unit) then return true end
	return false
end

-- A tooltip whose lines the game filled with secret values (a secret text
-- color, a secret line). The redraw would hand them to the game's line code
-- outside the game's own call and fail there. Only checked, never read:
-- a secret value is never indexed or compared.
local LINE_FIELDS = { "leftText", "leftColor", "rightText", "rightColor", "unitToken" }
local function SecretLinesTooltip(tooltip)
	if type(tooltip.GetPrimaryTooltipData) ~= "function" then return false end
	local ok, data = pcall(tooltip.GetPrimaryTooltipData, tooltip)
	if not ok or E.Secret(data) then return true end
	if type(data) ~= "table" then return false end
	local lines = data.lines
	if E.Secret(lines) then return true end
	if type(lines) ~= "table" then return false end
	for _, line in ipairs(lines) do
		if E.Secret(line) then return true end
		if type(line) == "table" then
			for _, field in ipairs(LINE_FIELDS) do
				if E.Secret(line[field]) then return true end
			end
		end
	end
	return false
end

-- True when the game's own redraw may run on this tooltip from EldoUI's
-- code: no secret unit and no secret line (a unit the game restricts, as
-- in a battleground, has its name line carry a secret unit).
function M.SafeToRedraw(tooltip)
	return not (SecretUnitTooltip(tooltip) or SecretLinesTooltip(tooltip))
end

-- Holding or releasing a modifier redraws the tooltip, so rows set to
-- "With Shift" appear at once. Only out of combat, only Blizzard's own
-- refresh is used, and never on a tooltip about a secret unit or with
-- secret lines.
local function OnModifier()
	if not M.active then return end
	if InCombatLockdown() then
		-- The "show anyway" key, pressed while pointing at something.
		if combatHidden and GameTooltip:IsShown() and ModifierDown(M.db.combatModifier) then CombatShow(GameTooltip) end
		return
	end
	local tooltip = GameTooltip
	if not tooltip:IsShown() or E.FrameCheck(tooltip, "IsForbidden") or not tooltip.RefreshData then return end
	-- Training adds price, rank and click hints after the game's spell data.
	local training = E.modules.Training
	if training and training:OwnsRowTooltip(tooltip) then return end
	if not M.SafeToRedraw(tooltip) then return end
	pcall(tooltip.RefreshData, tooltip)
end

---------------------------------------------------------------------------
-- Anchor
---------------------------------------------------------------------------
-- The bag zone, bottom-right: empty while the bags are closed. Higher up
-- the tooltip would grow over the quest tracker.
local DEFAULT_POINT = { "BOTTOMRIGHT", "UIParent", "BOTTOMRIGHT", -19, 330 }

local CURSOR_ANCHORS = { cursor = "ANCHOR_CURSOR", cursorLeft = "ANCHOR_CURSOR_LEFT", cursorRight = "ANCHOR_CURSOR_RIGHT" }

local function Forbidden(frame)
	return frame and E.FrameCheck(frame, "IsForbidden")
end

-- Edges of a frame, or nothing when the game does not allow measuring it
-- (a tooltip anchored to a nameplate or another restricted region).
local function Edges(frame)
	if E.FrameCheck(frame, "IsAnchoringRestricted") then return end
	local ok, l, r, t, b = pcall(function() return frame:GetLeft(), frame:GetRight(), frame:GetTop(), frame:GetBottom() end)
	if ok then return l, r, t, b end
end

M.Edges = Edges

local function Overlaps(a, b)
	local al, ar, at, ab = Edges(a)
	local bl, br, bt, bb = Edges(b)
	if not (al and bl and ar and br and at and bt and ab and bb) then return false end
	-- Different scales: compare in screen units.
	local sa, sb = a:GetEffectiveScale(), b:GetEffectiveScale()
	al, ar, at, ab = al * sa, ar * sa, at * sa, ab * sa
	bl, br, bt, bb = bl * sb, br * sb, bt * sb, bb * sb
	return al < br and ar > bl and ab < bt and at > bb
end

-- Smart: the bag zone (or on top of the open bags), and when the tooltip
-- would still cover the frame it belongs to (a unit frame, a button), it
-- moves beside that frame.
function SmartAdjust(tooltip)
	if tooltip ~= GameTooltip or not smartOwner or not M.active or M.db.anchor ~= "smart" then return end
	local owner = tooltip:GetOwner()
	if not Can("move") then return end
	if owner ~= smartOwner or IsWorldOwner(owner) or Forbidden(owner) or not Overlaps(tooltip, owner) then return end
	smartOwner = nil -- move once per show
	tooltip:ClearAllPoints()
	local ownerLeft = (Edges(owner) or 0) * owner:GetEffectiveScale()
	local width = (tooltip:GetWidth() or 0) * tooltip:GetEffectiveScale()
	if ownerLeft - width - 8 > 0 then
		tooltip:SetPoint("BOTTOMRIGHT", owner, "BOTTOMLEFT", -8, 0)
	else
		tooltip:SetPoint("BOTTOMLEFT", owner, "BOTTOMRIGHT", 8, 0)
	end
end

-- The bag window that is open right now: EldoUI's, else Blizzard's combined bags.
local function OpenBagWindow()
	local bags = E.modules.Bags
	local frame = (bags and bags.active and bags.frame) or _G.EldoUI_Bags
	if frame and frame:IsShown() then return frame end
	frame = ContainerFrameCombinedBags
	if frame and frame:IsShown() and not Forbidden(frame) then return frame end
end

local function OnDefaultAnchor(tooltip, parent)
	if not M.active or Forbidden(tooltip) or Forbidden(parent) then return end
	if tooltip == GameTooltip and ShouldHide("all", parent) then
		CombatHide(tooltip)
		return
	end
	CombatShow(tooltip)
	smartOwner = nil
	local mode = M.db.anchor
	if mode == "blizzard" or not Can("move") then return end
	local cursor = CURSOR_ANCHORS[mode]
	if cursor then
		tooltip:SetOwner(parent, cursor, M.db.cursorX, M.db.cursorY)
	elseif M.anchor then
		tooltip:ClearAllPoints()
		local bags = mode == "smart" and OpenBagWindow()
		if bags then
			-- The bags fill the zone; sit on top of them instead.
			tooltip:SetPoint("BOTTOMRIGHT", bags, "TOPRIGHT", 0, 8)
		else
			-- Fixed and Smart rest on the mover (dragged, layout or imported spot).
			tooltip:SetPoint("BOTTOMRIGHT", M.anchor, "BOTTOMRIGHT", 0, 0)
		end
		if mode == "smart" then smartOwner = parent end
	end
end

-- Preview: a sample tooltip (your own unit) for 5 seconds, shown again on
-- every setting change while it is open.
local previewUntil = 0

function M:Preview()
	if not self.active or InCombatLockdown() then return end
	previewUntil = GetTime() + 5
	local tooltip = GameTooltip
	GameTooltip_SetDefaultAnchor(tooltip, UIParent)
	tooltip:SetUnit("player")
	tooltip:Show()
	C_Timer.After(5.05, function()
		if GetTime() >= previewUntil and tooltip:IsShown() and tooltip:GetOwner() == UIParent then tooltip:Hide() end
	end)
end

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------
function M:Apply()
	for _, name in ipairs(TOOLTIPS) do
		local tooltip = _G[name]
		if tooltip then
			SkinTooltip(tooltip)
			UpdateBackdrop(tooltip, true)
		end
	end
	SkinStatusBar()
	ApplyFonts()
	ApplyScale()
	-- Every EldoUI anchor mode keeps the tooltip on the screen.
	local move = self.active and Can("move")
	self:UpdateMover()
	for tooltip in pairs(skinned) do
		if tooltip ~= EmbeddedItemTooltip then
			if move then
				if clamped[tooltip] == nil then clamped[tooltip] = tooltip:IsClampedToScreen() and true or false end
				tooltip:SetClampedToScreen(true)
			elseif clamped[tooltip] ~= nil then
				tooltip:SetClampedToScreen(clamped[tooltip])
				clamped[tooltip] = nil
			end
		end
	end
end

-- The Tooltip mover only matters for the modes that rest on it (Fixed and
-- Smart) while EldoUI may move tooltips; move mode leaves it out otherwise.
function M:UpdateMover()
	local mover = self.anchor and E.movers.EldoUI_Tooltip
	if not mover then return end
	local mode = self.db.anchor
	mover:SetShown(self.active and Can("move") and (mode == "fixed" or mode == "smart") and true or false)
end

-- Back to Blizzard's tooltip (element off, or a switch turned off): every
-- part above checks its switch, so a full pass undoes what is not allowed.
function M:RestoreBlizzard()
	barColor = nil
	for tooltip in pairs(skinned) do
		ResetBorder(tooltip)
		HideDivider(tooltip)
	end
	self:Apply()
end

-- Older settings had an Item ID and a Spell ID choice (once on/off).
-- They become the one Show IDs choice; when they differ, the stricter one
-- is kept.
function M.KeepIdChoice(db)
	local item, spell = rawget(db, "itemID"), rawget(db, "spellID")
	if item == nil and spell == nil then return end
	local rank = { never = 1, [false] = 1, shift = 2, always = 3, [true] = 3 }
	local names = { "never", "shift", "always" }
	db.ids = names[math.min(rank[item] or 3, rank[spell] or 3)]
	db.itemID, db.spellID = nil, nil
end

local function FillSectionDefaults()
	M.db.sections = M.db.sections or {}
	for _, section in ipairs(sections) do
		if M.db.sections[section.key] == nil then M.db.sections[section.key] = section.default end
	end
	M.KeepIdChoice(M.db)
end

function M:OnInitialize()
	FillSectionDefaults()
	BuildPatterns()
end


function M:OnEnable()
	if not self.anchor then
		self.anchor = CreateFrame("Frame", "EldoUI_Tooltip", UIParent)
		self.anchor:SetSize(250, 120)
		E:CreateMover(self.anchor, "EldoUI_Tooltip", L["Tooltip"], DEFAULT_POINT)
	end
	if not self.hooked then
		self.hooked = true
		HookDataTypes()
		hooksecurefunc("GameTooltip_SetDefaultAnchor", OnDefaultAnchor)
		if SharedTooltip_SetBackdropStyle then
			hooksecurefunc("SharedTooltip_SetBackdropStyle", function(tooltip)
				if skinned[tooltip] then UpdateBackdrop(tooltip) end
			end)
		end
		-- Combat hiding also covers tooltips filled after the default anchor
		-- (spells, auras) and those that skip it (frames with their own anchor).
		GameTooltip:HookScript("OnShow", function(tooltip)
			if M.active and not Forbidden(tooltip) then HideInCombat(tooltip) end
		end)
		GameTooltip:HookScript("OnHide", function(tooltip) CombatShow(tooltip) end)
	end
	self:RegisterEvent("MODIFIER_STATE_CHANGED", OnModifier)
	self:RegisterEvent("PLAYER_REGEN_ENABLED", function() CombatShow(GameTooltip) end)
	self:Apply()
end

function M:OnDisable()
	barColor = nil
	self:UpdateMover()
	self:UnregisterEvent("MODIFIER_STATE_CHANGED")
	self:UnregisterEvent("PLAYER_REGEN_ENABLED")
	CombatShow(GameTooltip)
	for tooltip in pairs(skinned) do
		ResetBorder(tooltip)
		HideDivider(tooltip)
		UpdateBackdrop(tooltip, true)
	end
	SkinStatusBar()
	ApplyFonts()
	ApplyScale()
	for tooltip, state in pairs(clamped) do
		tooltip:SetClampedToScreen(state)
		clamped[tooltip] = nil
	end
end

function M:OnProfileChanged()
	FillSectionDefaults()
	if self.active then
		self:Apply()
		if GetTime() < previewUntil then self:Preview() end
	end
end

E:RegisterBlizzardHandler(ELEMENT, {
	owner = "Tooltip",
	apply = function() if M.active then M:Apply() end end,
	undo = function() M:RestoreBlizzard() end,
	install = { skin = true, move = true, improve = true },
	legacy = function() return M.db and M.db.enabled end,
})

---------------------------------------------------------------------------
-- Options
---------------------------------------------------------------------------
local MODIFIERS = { NONE = "None", SHIFT = "Shift", CTRL = "Ctrl", ALT = "Alt" }
local ID_MODES = { never = "Never", shift = "With Shift", always = "Always" }

-- Preview: a sample unit tooltip of your own character in the text
-- sizes, opacity, name color and health bar set below (E:ConfigSample,
-- Core/MoverSamples.lua). The Preview button further down shows the
-- game's real tooltip.
local function UpdatePreview(canvas)
	local db = M.db
	if not (canvas and db) then return end
	local className, class = UnitClass("player")
	local nameColor = E.tokens.text.body
	if db.classColor then
		local r, g, b = E:GetClassColor(class)
		if r then nameColor = { r, g, b } end
	end
	E:ConfigSample(canvas, "tooltip", {
		width = 220, headerSize = db.headerSize, fontSize = db.bodySize, alpha = db.alpha,
		lines = {
			{ UnitName("player") or "", nameColor },
			{ L["Level %d"]:format(UnitLevel("player") or 1) .. " " .. (className or "") },
		},
		barHeight = db.healthBar and db.healthBarHeight or 0,
	})
end

M.options = {
	{ type = "preview", label = "Preview", height = 96, create = UpdatePreview, update = UpdatePreview,
		desc = "A sample tooltip of your character in your text sizes, opacity and colors." },
	{ type = "description", label = "What EldoUI may do with Blizzard's tooltips is set on the Blizzard UI page. These settings shape what each switch does." },
	{ type = "header", label = "Look" },
	{ disabled = E:BlizzardNeeds(ELEMENT, "skin"), type = "toggle", key = "skin", label = "Skin tooltips", desc = "A panel in the EldoUI art style. Off keeps Blizzard's border." },
	{ disabled = E:BlizzardNeeds(ELEMENT, "skin"), dependsOn = "skin", type = "range", percent = true, key = "alpha", label = "Background opacity", min = 0.3, max = 1, step = 0.05, desc = "How dark the panel is. 0.9 matches the game's own tooltips." },
	{ disabled = E:BlizzardNeeds(ELEMENT, "skin"), dependsOn = "skin", type = "toggle", key = "shadow", label = "Soft shadow", desc = "A faint shadow around the panel so it lifts off bright zones." },
	{ disabled = E:BlizzardNeeds(ELEMENT, "skin"), type = "toggle", key = "ownShadow", dependsOn = "shadow", label = "Own shadow look",
		desc = "Give the tooltip shadow its own strength and size. Off follows Frame shadows on Global settings > Textures." },
	{ disabled = E:BlizzardNeeds(ELEMENT, "skin"), type = "range", percent = true, key = "shadowAlpha", dependsOn = "ownShadow", label = "Shadow strength",
		min = E.tokens.shadow.minAlpha, max = 1, step = 0.05, hidden = function() return not M.db.shadow end,
		desc = "How dark the tooltip shadow is." },
	{ disabled = E:BlizzardNeeds(ELEMENT, "skin"), type = "range", key = "shadowSize", dependsOn = "ownShadow", label = "Shadow size", unit = "px",
		min = E.tokens.shadow.minSize, max = E.tokens.shadow.maxSize, step = 1, hidden = function() return not M.db.shadow end,
		desc = "How far the tooltip shadow reaches beyond its edge." },
	{ disabled = E:BlizzardNeeds(ELEMENT, "skin"), type = "toggle", key = "borderColor", label = "Colored border", desc = "Item quality for items, class or reaction for units." },
	{ disabled = E:BlizzardNeeds(ELEMENT, "skin"), type = "toggle", key = "font", label = "Use the EldoUI font", desc = "The theme font for tooltip text. Off keeps the game font." },
	{ disabled = E:BlizzardNeeds(ELEMENT, "skin"), type = "range", key = "headerSize", label = "Title text size", min = 10, max = 24, step = 1, desc = "The first line: item or unit name." },
	{ disabled = E:BlizzardNeeds(ELEMENT, "skin"), type = "range", key = "bodySize", label = "Body text size", min = 8, max = 20, step = 1, desc = "All other lines." },
	{ disabled = E:BlizzardNeeds(ELEMENT, "skin"), type = "range", key = "smallSize", label = "Small text size", min = 8, max = 18, step = 1, desc = "Small lines such as comparison headers." },
	{ disabled = E:BlizzardNeeds(ELEMENT, "skin"), type = "range", percent = true, key = "scale", label = "Scale", min = 0.6, max = 1.6, step = 0.05, desc = "Size of the whole tooltip." },

	{ type = "header", label = "Position" },
	{ disabled = E:BlizzardNeeds(ELEMENT, "move"), type = "select", key = "anchor", label = "Attach to",
		desc = "Fixed: the Tooltip mover. Cursor: above or beside the cursor. Smart: the mover, above open bags, stepping aside from what you point at. Blizzard: the game's spot. Needs Move.",
		values = { fixed = "Fixed (mover)", cursor = "Cursor", cursorLeft = "Cursor left", cursorRight = "Cursor right", smart = "Smart", blizzard = "Blizzard (Edit Mode)" } },
	{ type = "execute", label = "Preview", desc = "Shows a sample tooltip for 5 seconds. It updates as you change settings.",
		func = function() M:Preview() end },
	{ disabled = E:BlizzardNeeds(ELEMENT, "move"), type = "range", unit = "px", key = "cursorX", label = "Cursor offset X", min = -100, max = 100, step = 1, desc = "Horizontal distance from the cursor.", hidden = function() return not CURSOR_ANCHORS[M.db.anchor] end },
	{ disabled = E:BlizzardNeeds(ELEMENT, "move"), type = "range", unit = "px", key = "cursorY", label = "Cursor offset Y", min = -100, max = 100, step = 1, desc = "Vertical distance from the cursor.", hidden = function() return not CURSOR_ANCHORS[M.db.anchor] end },
	{ type = "select", key = "hideInCombat", label = "Hide in combat",
		desc = "Which tooltips stay hidden while you are in combat.",
		values = { never = "Never", world = "Over the world", frames = "Over UI frames", units = "Unit tooltips", all = "All tooltips" },
		disabled = E:BlizzardNeeds(ELEMENT, "hide") },
	{ type = "select", key = "combatModifier", label = "Hold to show in combat", values = MODIFIERS,
		disabled = E:BlizzardNeeds(ELEMENT, "hide", function() return M.db.hideInCombat == "never" and L["Pick which tooltips hide in combat first."] end),
		desc = "Holding this key shows hidden tooltips anyway." },

	{ type = "header", label = "Units" },
	{ type = "toggle", key = "healthBar", label = "Health bar", desc = "Blizzard's own health values in a thin bar under the tooltip." },
	{ type = "range", unit = "px", key = "healthBarHeight", dependsOn = "healthBar", label = "Health bar height", min = 1, max = 12, step = 1, desc = "Thickness of the health bar." },
	{ type = "toggle", key = "classColor", label = "Class-colored names", desc = "Players in their class color, NPCs in their reaction color." },
	{ type = "toggle", key = "guildRank", label = "Show guild rank", desc = "The rank after the guild name, in gray." },
	{ type = "toggle", key = "relation", label = "Mark friends, guild and ignored", desc = "Marks players on your friends or ignore list, and members of your own guild. Not shown in combat." },
	{ type = "toggle", key = "levelColor", label = "Color the level by difficulty", desc = "The level in the game's difficulty color, with elite or rare added." },
	{ type = "toggle", key = "target", label = "Show the unit's target", desc = "Hidden when the game keeps the target secret." },
	{ type = "toggle", key = "playerItemLevel", label = "Player item level", desc = "Your own, or a player you inspected yourself. EldoUI never inspects for you." },
	{ type = "toggle", key = "hidePvP", label = "Hide the PvP line", desc = "Removes the plain \"PvP\" line." },
	{ type = "toggle", key = "hideFaction", label = "Hide the faction line", desc = "Removes the Alliance / Horde line." },

	{ type = "header", label = "Items and spells" },
	{ type = "toggle", key = "itemLevel", label = "Item level", desc = "Item level of gear in the info area." },
	{ type = "toggle", key = "moveItemLevel", label = "Move the game's item level line", desc = "Hides Blizzard's own item level line while the info area shows it, so it appears once." },
	{ type = "toggle", key = "vendorPrice", label = "Vendor price on one line", desc = "Each and stack price in the Value row instead of Blizzard's money line." },
	{ type = "select", key = "ids", label = "Show IDs", values = ID_MODES,
		desc = "IDs the game uses for this item, spell, creature, quest or currency. Useful for bug reports, map notes and searches." },
	{ type = "toggle", key = "shortStats", label = "Short stat lines", desc = "Use compact stat names and amounts for recognized item effects, including comparison tooltips." },
	{ type = "toggle", key = "hideMadeBy", label = "Hide \"Made by\"", desc = "Hides the crafter and gift-wrap lines (matched by the game's own text)." },
	{ type = "toggle", key = "hideClickHints", label = "Hide click hints", desc = "Hides <Right Click to Open>, <Right Click to Read> and <Shift Right Click to Socket>." },

	{ type = "header", label = "Info area" },
	{ type = "description", label = "EldoUI's extra rows sit in one block at the bottom of the tooltip; pick when each shows. Other addons' lines stay below it." },
	{ type = "toggle", key = "divider", label = "Divider line", desc = "A thin line between the game's text and the info area." },
}
local sectionInsert = #M.options + 1

-- A section row is grayed while Blizzard UI > Tooltips: Improve is off, or
-- while the module that provides the section (or its own switch) is off.
local function SectionDisabled(section)
	return E:BlizzardNeeds(ELEMENT, "improve", function() return ProviderOff(sectionByKey[section.key] or section) or false end)
end

function AddSectionOption(section)
	local key = "sections." .. section.key
	for _, option in ipairs(M.options) do
		if option.key == key then
			option.label, option.desc = section.title, section.desc or E.Key("When this part of the info area shows.")
			return
		end
	end
	-- Keep the rows in section order.
	local at = sectionInsert
	while M.options[at] and M.options[at].sectionOrder and M.options[at].sectionOrder <= section.order do at = at + 1 end
	table.insert(M.options, at, { type = "select", key = key, label = section.title, values = MODES, sectionOrder = section.order,
		desc = section.desc or E.Key("When this part of the info area shows."), disabled = SectionDisabled(section) })
end
for _, section in ipairs(sections) do AddSectionOption(section) end

---------------------------------------------------------------------------
-- Style presets (the layout places the fixed tooltip)
---------------------------------------------------------------------------
E:RegisterStyles("Tooltip", {
	{ key = "EldoUI", title = "EldoUI", desc = "Dark panel in the bag zone (Smart), quality and class borders, a thin health bar and the info area.",
		settings = { skin = true, alpha = 0.9, shadow = true, borderColor = true, anchor = "smart", scale = 1, font = true,
			headerSize = 16, bodySize = 14, smallSize = 12, healthBar = true, healthBarHeight = 3, classColor = true, target = true,
			hidePvP = true, hideFaction = false, itemLevel = true, moveItemLevel = true, vendorPrice = true, ids = "shift",
			hideMadeBy = true, divider = true } },
	{ key = "Minimal", title = "Minimal", desc = "Small text, no health bar, IDs only with Shift.",
		settings = { skin = true, alpha = 0.85, shadow = false, borderColor = true, anchor = "fixed", scale = 0.95, font = true,
			headerSize = 14, bodySize = 12, smallSize = 11, healthBar = false, classColor = true, guildRank = false, target = false,
			playerItemLevel = false, hidePvP = true, hideFaction = true, itemLevel = true, vendorPrice = true, ids = "shift",
			hideMadeBy = true, hideClickHints = true, divider = true } },
	{ key = "Cursor", title = "At the cursor", desc = "The EldoUI look, following the mouse.",
		settings = { skin = true, alpha = 0.9, shadow = true, borderColor = true, anchor = "cursorRight", cursorX = 16, cursorY = -16,
			font = true, healthBar = true, healthBarHeight = 3, classColor = true, target = true, hidePvP = true } },
	{ mode = true, key = "Smart", title = "Smart", desc = "In the corner, stepping aside when it would cover the frame you point at.",
		settings = { skin = true, alpha = 0.9, shadow = true, borderColor = true, anchor = "smart", cursorX = 16, cursorY = -16,
			font = true, healthBar = true, healthBarHeight = 3, classColor = true, target = true, hidePvP = true } },
	{ key = "Classic", title = "Classic Blizzard", desc = "Blizzard's own border and font, with the info area added.",
		settings = { skin = false, borderColor = false, anchor = "fixed", font = false, healthBar = true, healthBarHeight = 5,
			classColor = true, target = true, hidePvP = false, hideFaction = false, levelColor = false, hideMadeBy = false } },
	{ key = "InfoRich", title = "Info-rich", desc = "Everything on: IDs always, item level, value, target and guild rank.",
		settings = { skin = true, alpha = 0.95, shadow = true, borderColor = true, anchor = "fixed", font = true, headerSize = 16,
			bodySize = 14, healthBar = true, healthBarHeight = 5, classColor = true, guildRank = true, target = true,
			playerItemLevel = true, levelColor = true, hidePvP = true, hideFaction = false, itemLevel = true, vendorPrice = true,
			ids = "always", hideMadeBy = false, divider = true } },
})
