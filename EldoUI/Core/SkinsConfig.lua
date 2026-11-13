-- Layout and style > Appearance: the skin of the whole UI and of each part,
-- in the options window (Core/Config.lua renders the rows).
--
--   Whole UI    skin cards with a live sample of each skin, the first one
--               "Follow layout" (the skin the layout was made for); the
--               faction look of a skin that has one; window title font;
--               links to the accent color and the bar texture, which keep
--               their one place under Global settings
--   Components  parts with a skin of their own: unit-frame graphics,
--               party and raid graphics, action buttons, the minimap frame
--               and this options window. Each says "Follow skin (now: X)"
--               or names its own pick; Reset parts sets every one back
--   Windows     how Blizzard's own windows look, with what the choice does
--               right now, and a link to the Blizzard UI page
--
-- A skin only paints: it never moves frames, turns modules on or off or
-- gives EldoUI new permissions over Blizzard's UI. The rows edit a small
-- stand-in table; the page writes each change through the skin calls
-- (E:SetSkin, E:SetSkinVariant, E:SetBlizzardWindows), so following the
-- layout, accents and High contrast keep working as they do everywhere.
local _, E = ...
local L = E.L

local Appearance = {}
E.Appearance = Appearance -- exposed for inspection

-- Skin cards: the narrowest card, the gap between cards, the sample height.
Appearance.CARD = { width = 132, gap = 8, sample = 54, pad = 6 }
Appearance.FOLLOW = "Follow"

-- Parts on the Components tab. Each has the place it is saved: general
-- (general.skinParts[part]), config (general.configStyle) or graphics (a
-- module's graphics pick, Core/UnitGraphics.lua).
Appearance.PARTS = {
	{ key = "unitGraphics", kind = "graphics", module = "UnitFrames", path = { "allFrames", "graphics" }, graphics = "unit",
		label = "Unit-frame graphics",
		desc = "The frame art around player, target, pet and the other unit frames: portrait ring or box, bar frame and fill. It never changes positions, sizes, bars or what the portrait shows." },
	{ key = "groupGraphics", kind = "graphics", module = "GroupFrames", path = { "graphics" }, graphics = "group",
		label = "Party and raid graphics",
		desc = "The frame art of party and raid frames: the skin's material and a fine edge. They stay compact, so a full raid keeps its room." },
	{ key = "actionbuttons", kind = "general", part = "actionbuttons",
		label = "Action buttons",
		desc = "The frame drawn around EldoUI's action buttons. The buttons, their keys and what they cast never change." },
	{ key = "minimap", kind = "general", part = "minimap",
		label = "Minimap frame",
		desc = "The ring or border around the minimap. A minimap without a border keeps none." },
	{ key = "configStyle", kind = "config",
		label = "Options window",
		desc = "The frame of this options window. Follow skin frames it like every other EldoUI window." },
}

local proxy = {}

---------------------------------------------------------------------------
-- Reading and naming
---------------------------------------------------------------------------
local function General() return E.db.general end

local function SkinTitle(id)
	local info = E.artStyleInfo[id]
	if info then return L[info.title] end
	return L["%s (not available): Modern is used"]:format(tostring(id))
end
Appearance.SkinTitle = SkinTitle

-- The skin the player picked (while High contrast is on: the one that
-- comes back after it).
function Appearance.Picked()
	local general = General()
	local backup = general.artStyle == "Contrast" and type(general.accessBackup) == "table" and general.accessBackup.contrast
	if type(backup) == "table" and type(backup.artStyle) == "string" then return backup.artStyle end
	return general.artStyle
end

function Appearance.LayoutTitle()
	return E:LayoutTitle(General().layout)
end

local function ModuleTable(part)
	local module = E.modules and E.modules[part.module]
	return module and module.db
end

local function PartValue(part)
	local general = General()
	if part.kind == "config" then return general.configStyle or Appearance.FOLLOW end
	if part.kind == "general" then
		local parts = type(general.skinParts) == "table" and general.skinParts or {}
		return parts[part.part] or Appearance.FOLLOW
	end
	local db = ModuleTable(part)
	local value = db and E.GetPath(db, table.concat(part.path, "."))
	return type(value) == "string" and value or "FOLLOW"
end

local function FollowValue(part)
	return part.kind == "graphics" and "FOLLOW" or Appearance.FOLLOW
end

-- The graphics a Follow skin pick draws now, by name.
local function GraphicsNow(kind)
	local UG = E.UnitGraphics
	local m = E:SkinManifest(E:SkinPart("unitframes"))
	local id = m and m.recipes and m.recipes[kind == "group" and "groupframe" or "unitframe"]
	if E:ArtStyle() == "Contrast" then id = "MODERN" end
	local provider = UG and UG.Provider and UG:Provider(id or "MODERN")
	return provider and L[provider.title] or L["Modern (flat)"]
end

-- Values and order of a part's select.
function Appearance.PartValues(part)
	if part.kind == "graphics" then
		local UG = E.UnitGraphics
		local saved = PartValue(part)
		local follow = L["Follow skin (now: %s)"]:format(GraphicsNow(part.graphics))
		if UG and UG.Values then return UG:Values(saved, follow) end
		return { FOLLOW = follow }, { "FOLLOW" }
	end
	local saved = PartValue(part)
	local extra
	if saved ~= Appearance.FOLLOW and not E.artStyles[saved] then extra = { [saved] = SkinTitle(saved) } end
	return E:SkinValues({ follow = L["Follow skin (now: %s)"]:format(SkinTitle(E:ArtStyle())), extra = extra })
end

-- Why a part can't be picked right now, or nil.
function Appearance.PartDisabled(part)
	if part.kind == "graphics" then
		if not E.UnitGraphics then return L["Unit-frame graphics are not available in this version."] end
		if not ModuleTable(part) then return L["This module is not loaded."] end
	end
	return nil
end

-- How many parts have a pick of their own.
function Appearance.CustomCount()
	local count = 0
	for _, part in ipairs(Appearance.PARTS) do
		if not Appearance.PartDisabled(part) and PartValue(part) ~= FollowValue(part) then count = count + 1 end
	end
	return count
end

---------------------------------------------------------------------------
-- Writing
---------------------------------------------------------------------------
-- Pick a skin on a card; "Follow" gives the profile its layout's skin and
-- keeps following it.
function Appearance.Pick(id)
	if id == Appearance.FOLLOW then
		local general = General()
		general.skinFollow = true
		E:SetSkin(E:LayoutSkin(), { follow = true })
		return true
	end
	return E:SetSkin(id)
end

local function WritePart(part, value)
	local general = General()
	if part.kind == "config" then
		general.configStyle = value
	elseif part.kind == "general" then
		if type(general.skinParts) ~= "table" then general.skinParts = {} end
		general.skinParts[part.part] = value ~= Appearance.FOLLOW and value or nil
	else
		local db = ModuleTable(part)
		if not db then return end
		-- The theme refresh after the change repaints the frames.
		E.SetPath(db, table.concat(part.path, "."), value)
	end
end

-- Every part back to Follow skin.
function Appearance.ResetParts()
	for _, part in ipairs(Appearance.PARTS) do
		if not Appearance.PartDisabled(part) and PartValue(part) ~= FollowValue(part) then WritePart(part, FollowValue(part)) end
	end
	E:RefreshTheme()
	if E.RefreshConfig then E:RefreshConfig() end
end

-- The stand-in table the rows edit, filled from the profile.
local function Target()
	local general = General()
	proxy.skinVariant = general.skinVariant or "auto"
	proxy.titleFont = general.skinTitleFont ~= false
	proxy.blizzardWindows = E.BlizzardWindowsMode and E:BlizzardWindowsMode() or general.blizzardWindows or "keep"
	for _, part in ipairs(Appearance.PARTS) do proxy[part.key] = PartValue(part) end
	return proxy
end
Appearance.Target = Target

-- After a row changed the stand-in: write what differs through the skin calls.
local function Apply()
	local general = General()
	local repaint = false
	if proxy.skinVariant ~= (general.skinVariant or "auto") then E:SetSkinVariant(proxy.skinVariant) end
	if proxy.titleFont ~= (general.skinTitleFont ~= false) then
		general.skinTitleFont = proxy.titleFont and true or false
		repaint = true
	end
	for _, part in ipairs(Appearance.PARTS) do
		local value = proxy[part.key]
		if value ~= nil and value ~= PartValue(part) and not Appearance.PartDisabled(part) then
			WritePart(part, value)
			repaint = true
		end
	end
	local mode = E.BlizzardWindowsMode and E:BlizzardWindowsMode()
	if E.SetBlizzardWindows and proxy.blizzardWindows and proxy.blizzardWindows ~= mode then
		local _, needed = E:SetBlizzardWindows(proxy.blizzardWindows, true)
		if needed and E.ConfigNeedsReload then E:ConfigNeedsReload("blizzardWindows", L["Blizzard windows"]) end
	end
	if repaint then E:RefreshTheme() end
	Target()
end
Appearance.Apply = Apply

local function Defaults()
	local list = { skinVariant = "auto", titleFont = true, blizzardWindows = E.defaults.general.blizzardWindows or "layout" }
	for _, part in ipairs(Appearance.PARTS) do list[part.key] = FollowValue(part) end
	return list
end

---------------------------------------------------------------------------
-- Skin cards
---------------------------------------------------------------------------
-- The ids of the cards in order: Follow layout first, then the picker's.
function Appearance.CardIds()
	local _, order = E:SkinValues()
	local list = { Appearance.FOLLOW }
	for _, id in ipairs(order) do list[#list + 1] = id end
	return list
end

-- Which card is selected now.
function Appearance.SelectedCard()
	if General().skinFollow then return Appearance.FOLLOW end
	return Appearance.Picked()
end

local function CardTooltip(card)
	local Kit = E.UIKit
	if card.id == Appearance.FOLLOW then
		Kit.Tooltip(card, L["Follow layout"], L["Uses the skin your layout was made for (now %s). It changes with the next layout you pick."]:format(SkinTitle(E:LayoutSkin())))
		return
	end
	local info = E.artStyleInfo[card.id]
	local m = E:SkinManifest(card.id)
	local text = info and L[info.desc or info.short or ""] or L["%s (not available): Modern is used"]:format(card.id)
	if m and m.variants and E:SkinVariants(card.id) then text = text .. "\n" .. L["Pick the faction look below."] end
	Kit.Tooltip(card, SkinTitle(card.id), text)
end

local function MakeCard(canvas, id)
	local Kit = E.WindowKit
	local card = Kit.Choice(canvas, Appearance.CARD.width, 96, "", nil, function(self)
		E:RunConfigRow(function()
			Appearance.Pick(self.id)
			if E.RefreshConfig then E:RefreshConfig() end
		end)
	end)
	card.id = id
	card.minHeight = nil
	local pad = Appearance.CARD.pad
	card.sample = CreateFrame("Frame", nil, card)
	card.sample:SetPoint("TOPLEFT", pad, -pad)
	card.sample:SetPoint("TOPRIGHT", -pad, -pad)
	card.sample:SetHeight(Appearance.CARD.sample)
	card.sample:EnableMouse(false)
	card.title:ClearAllPoints()
	card.title:SetPoint("TOPLEFT", card.sample, "BOTTOMLEFT", 2, -6)
	card.title:SetPoint("TOPRIGHT", card.sample, "BOTTOMRIGHT", -16, -6)
	card.title:SetJustifyH("LEFT")
	card.title:SetWordWrap(true)
	if card.title.SetMaxLines then card.title:SetMaxLines(2) end
	card.check = card:CreateTexture(nil, "OVERLAY")
	card.check:SetSize(12, 12)
	card.check:SetPoint("TOPRIGHT", card.sample, "BOTTOMRIGHT", 0, -8)
	E.UIKit.SetGlyph(card.check, "check")
	card.sub = E.WindowKit.Secondary(E:CreateText(card, E.tokens.size.small, "LEFT"))
	card.sub:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", 0, -2) -- its width follows the card (LayoutCards)
	card.sub:SetWordWrap(true)
	return card
end

-- Lay the cards out for `width`; returns the grid's height.
function Appearance.LayoutCards(canvas, width)
	local cards = canvas.cards
	if not cards then return 1 end
	local spec = Appearance.CARD
	local scale = E.TextScale and E:TextScale() or 1
	local least = math.floor(spec.width * math.sqrt(math.max(1, scale)))
	local columns = math.max(1, math.floor((width + spec.gap) / (least + spec.gap)))
	columns = math.min(columns, #cards)
	local cardWidth = math.floor((width - (columns - 1) * spec.gap) / columns)
	local height = 0
	for _, card in ipairs(cards) do
		card:SetWidth(cardWidth)
		card.title:SetWidth(math.max(cardWidth - 2 * spec.pad - 18, 1))
		card.sub:SetWidth(math.max(cardWidth - 2 * spec.pad - 2, 1))
		local need = spec.pad + spec.sample + 6 + math.ceil(card.title:GetStringHeight() or 0)
		if card.sub:IsShown() and (card.sub:GetText() or "") ~= "" then need = need + 2 + math.ceil(card.sub:GetStringHeight() or 0) end
		height = math.max(height, need + spec.pad + 4)
	end
	for index, card in ipairs(cards) do
		local column = (index - 1) % columns
		local row = math.floor((index - 1) / columns)
		card:ClearAllPoints()
		card:SetPoint("TOPLEFT", canvas, "TOPLEFT", column * (cardWidth + spec.gap), -row * (height + spec.gap))
		card:SetHeight(height)
	end
	canvas.columns = columns
	local rows = math.ceil(#cards / columns)
	return rows * height + (rows - 1) * spec.gap
end

-- Build or rebuild the cards (a plugin skin can come or go) and paint them.
function Appearance.UpdateCards(canvas)
	if not canvas then return end
	local ids = Appearance.CardIds()
	canvas.cards = canvas.cards or {}
	canvas.pool = canvas.pool or {}
	local same = #canvas.cards == #ids
	for index, id in ipairs(ids) do
		if not canvas.cards[index] or canvas.cards[index].id ~= id then same = false end
	end
	if not same then
		for _, card in ipairs(canvas.cards) do card:Hide() end
		wipe(canvas.cards)
		for index, id in ipairs(ids) do
			local card = canvas.pool[id] or MakeCard(canvas, id)
			canvas.pool[id] = card
			card:Show()
			canvas.cards[index] = card
		end
	end
	local selected = Appearance.SelectedCard()
	local inUse = E:ArtStyle()
	for _, card in ipairs(canvas.cards) do
		local id = card.id
		if id == Appearance.FOLLOW then
			local skin = E:LayoutSkin()
			card.title:SetText(L["Follow layout"])
			card.sub:SetText(L["%s: %s"]:format(Appearance.LayoutTitle(), SkinTitle(skin)))
			card.sub:Show()
			E:PaintSkinSample(card.sample, skin)
		else
			card.title:SetText(SkinTitle(id))
			-- The skin in use while High contrast draws over it.
			local note = inUse == "Contrast" and id == Appearance.Picked() and not General().skinFollow
			card.sub:SetText(note and L["After High contrast"] or "")
			card.sub:SetShown(note and true or false)
			E:PaintSkinSample(card.sample, id)
		end
		card:SetSelected(card.id == selected)
		card.check:SetShown(card.id == selected)
		card.check:SetVertexColor(E:TokenColor("accent"))
		CardTooltip(card)
	end
end

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------
-- The Blizzard windows choices, shared with the setup's Blizzard UI step.
-- Shown translated: L["Keep as set"], L["Follow layout"], L["Original"],
-- L["Match skin"] and their texts.
Appearance.WINDOWS = {
	order = { "keep", "layout", "original", "match" },
	titles = { keep = "Keep as set", layout = "Follow layout", original = "Original", match = "Match skin" },
	descs = {
		keep = "Each window keeps the look set on the Blizzard UI page.",
		layout = "Your layout picks Original or Match skin.",
		original = "Blizzard's own look. Taking a skin off needs a reload.",
		match = "Windows EldoUI may change take your skin.",
	},
}

local function WindowsValues()
	local values = {}
	for key, title in pairs(Appearance.WINDOWS.titles) do values[key] = L[title] end
	return values
end

function Appearance.WindowsSummary()
	if not E.BlizzardWindowsSummary then return L["Blizzard windows keep the look set on the Blizzard UI page."] end
	local s = E:BlizzardWindowsSummary()
	local parts = {}
	if s.mode == "keep" then
		parts[1] = L["Each window keeps the look set on the Blizzard UI page."]
	elseif s.allowed == 0 then
		parts[1] = L["EldoUI may change none of Blizzard's windows yet; the Blizzard UI page lets it."]
	else
		parts[1] = L["Windows EldoUI may change: %d of %d (in your skin: %d, original: %d)."]:format(s.allowed, s.listed, s.skinned, s.original)
	end
	if s.mode == "layout" then
		parts[#parts + 1] = L["Your layout asks for: %s."]:format(s.look == "original" and L["Original"] or L["Match skin"])
	end
	-- Listed windows with no EldoUI skin yet: counted apart, so the line
	-- above adds up.
	if (s.unhandled or 0) > 0 then parts[#parts + 1] = L["No EldoUI skin yet, so they keep Blizzard's look: %d."]:format(s.unhandled) end
	if s.own > 0 then parts[#parts + 1] = L["Set by hand on the Blizzard UI page and kept that way: %d."]:format(s.own) end
	if s.reload then parts[#parts + 1] = L["Needs a reload to bring Blizzard's look fully back."] end
	return table.concat(parts, " ")
end

local function Options()
	local options = {
		{ type = "tab", label = "Whole UI" },
		{ type = "header", label = "Skin",
			status = function()
				if General().skinFollow then return L["Follows %s"]:format(Appearance.LayoutTitle()) end
				return SkinTitle(Appearance.Picked())
			end },
		{ type = "preview", label = "Skin", noCaption = true, keywords = "skin art style theme look",
			create = function(canvas) Appearance.UpdateCards(canvas) end,
			height = function(canvas, width)
				-- Asked before the block has its canvas: the height of one row.
				if not canvas then return Appearance.CARD.sample + 2 * Appearance.CARD.pad + 40 end
				Appearance.UpdateCards(canvas)
				return Appearance.LayoutCards(canvas, width)
			end,
			update = function(canvas) Appearance.UpdateCards(canvas) end },
		{ type = "description", tone = "warning",
			label = "High contrast is on (Accessibility). Your skin shows again once it is off.",
			hidden = function() return E:ArtStyle() ~= "Contrast" end },
		{ type = "header", label = "Details" },
		{ type = "select", key = "skinVariant", label = "Faction look", keywords = "alliance horde neutral heritage",
			desc = "The materials of a skin that comes in a look per faction. Auto follows your character's faction.",
			values = function()
				local values = E:SkinVariants(Appearance.Picked())
				return values or { auto = L["Auto: your character's faction"] }
			end,
			order = { "auto", "alliance", "horde", "neutral" },
			disabled = function()
				if not E:SkinVariants(Appearance.Picked()) then return L["This skin has one look."] end
				return false
			end },
		{ type = "toggle", key = "titleFont", label = "Skin title font", keywords = "font header title",
			desc = function()
				local m = E:SkinManifest(Appearance.Picked())
				local name = m and m.fonts and m.fonts.title
				if name then return L["Window titles use the skin's own font (now %s). Off keeps EldoUI's title font."]:format(name) end
				return L["Window titles use the skin's own font when it has one. This skin uses EldoUI's title font."]
			end },
		{ type = "execute", label = "Accent color", keywords = "accent color theme",
			desc = function()
				local accent = General().accent
				local name = E.accentNames[accent]
				return L["Now: %s. Set on Global settings > General. A skin brings its own accent only while yours is the default blue."]:format(name and L[name] or tostring(accent))
			end,
			func = function() E:ToggleConfig("general", true, "accent") end },
		{ type = "execute", label = "Bar texture", keywords = "statusbar texture bars",
			desc = function()
				local bar = General().statusbar
				return L["Now: %s. Set on Global settings > Textures. Follow skin uses your skin's bar texture."]:format(bar == "Skin" and L["Follow skin"] or tostring(bar))
			end,
			func = function() E:ToggleConfig("textures", true, "general.statusbar") end },

		{ type = "tab", label = "Components", oneColumn = true },
		{ type = "header", label = "Parts",
			status = function()
				local count = Appearance.CustomCount()
				if count == 0 then return L["All follow the skin"] end
				return E:Plural(count, "%d has its own skin", "%d have their own skin"):format(count)
			end },
		{ type = "description", label = "Give one part its own skin. Follow skin keeps it with the rest." },
	}
	for _, part in ipairs(Appearance.PARTS) do
		options[#options + 1] = { type = "select", key = part.key, label = part.label, desc = part.desc, wide = true,
			values = function() return (Appearance.PartValues(part)) end,
			order = function() return select(2, Appearance.PartValues(part)) end,
			valueDescs = part.kind == "graphics" and function()
				local UG = E.UnitGraphics
				return UG and UG.Descs and UG:Descs() or {}
			end or nil,
			disabled = function() return Appearance.PartDisabled(part) or false end }
	end
	options[#options + 1] = { type = "execute", label = "Reset parts", noUndo = true,
		desc = "Every part above follows the skin again.",
		disabled = function() return Appearance.CustomCount() == 0 and L["Every part follows the skin."] or false end,
		func = Appearance.ResetParts }

	options[#options + 1] = { type = "tab", label = "Windows", oneColumn = true }
	options[#options + 1] = { type = "header", label = "Blizzard windows" }
	options[#options + 1] = { type = "select", key = "blizzardWindows", label = "Window look", keywords = "blizzard windows original skin", wide = true,
		desc = "How Blizzard's own windows look. Only windows you let EldoUI change on the Blizzard UI page are touched. Original needs a reload.",
		values = WindowsValues, order = Appearance.WINDOWS.order, valueDescs = Appearance.WINDOWS.descs,
		disabled = function() return not E.SetBlizzardWindows and L["Not available in this version."] or false end }
	options[#options + 1] = { type = "description", tone = "body", label = function() return Appearance.WindowsSummary() end }
	options[#options + 1] = { type = "execute", label = "Open Blizzard UI page", keywords = "blizzard permissions",
		desc = "Choose which Blizzard windows EldoUI may change at all.",
		func = function() E:ToggleConfig("blizzard", true) end }
	return options
end
Appearance.Options = Options

-- Shown translated: L["Whole UI"], L["Components"], L["Windows"], L["Skin"],
-- L["Details"], L["Parts"], L["Faction look"], L["Skin title font"],
-- L["Accent color"], L["Bar texture"], L["Reset parts"], L["Blizzard windows"], L["Window look"],
-- L["Open Blizzard UI page"], L["Unit-frame graphics"], L["Party and raid graphics"],
-- L["Action buttons"], L["Minimap frame"], L["Options window"], L["Appearance"]

E:RegisterEvent("PLAYER_LOGIN", function()
	if not E.RegisterConfigPage then return end
	local page = E:RegisterConfigPage("appearance", "Appearance", Options(), Target, Apply, 2.4)
	if page then page.defaults = Defaults end
end, Appearance, "pages")
