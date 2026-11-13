-- EldoUI skins: one registry for the look of the whole UI.
--
-- A skin is what General > Skin picks (saved as `general.artStyle`). The five
-- skins EldoUI always had (Modern, Blizzard, Classic, WoW Forever, High
-- contrast) keep their painters in Core/Media.lua. The native skins
-- (Data/Skins.lua) draw original textures (Data/SkinData.lua,
-- Media/Textures/Skins) through the painters below. Every registered skin
-- joins E.artStyles, E.artStyleOrder and E.artStyleInfo, so every place that
-- offers an art style offers it too.
--
-- Surface API (other files build on these names):
--   E:RegisterSkin(id, manifest)         add a skin (plugins too); true when added
--   E:SkinManifest([id])                 the manifest in effect (variant merged), never nil
--   E:SkinPart([part])                   the skin a part draws in (High contrast wins,
--                                        then the part's own pick, then the skin)
--   E:SkinValues([opts])                 values, order: the skins a picker offers
--   E:SetSkin(id[, opts])                pick a skin (opts.follow: picked by the layout)
--   E:FollowLayoutSkin([layoutKey])      give the profile its layout's skin when it follows it
--   E:PaintSurface(object, kind[, part[, opts]])  paint one surface, repaints on theme changes
--   E:ReleaseSurface(object)             take the skin's pieces off a surface again
--   E:SurfaceMeasure(object)             content, hit and paint insets of a surface
--   E:SkinFlag(name[, id])               a manifest flag of the skin in effect (Data/Skins.lua)
--   E:SkinBronze()                       r, g, b of EldoUI's Bronze marks under the skin
--   E:RegisterSkinSurface(id, info)      add a surface to the surface list (plugins too)
--   E:UnregisterSkinSurface(id)          take a surface off the list again
--   E:SkinSurfaceReport([id])            every listed surface and how a skin draws it
--   E:PaintSkinSample(frame, id)         a small sample of a skin (pickers, cards)
--   E:PinSkinLook(profile, fresh)        profiles saved before skins keep their look
--   E.Skins.Release(frame)               hide every skin piece on a frame
local _, E = ...
local L = E.L

local Skins = E.Skins or {}
E.Skins = Skins

E.defaults.general.skinFollow = true      -- the layout brings its skin (fresh profiles)
E.defaults.general.skinVariant = "auto"   -- Faction Heritage: auto, alliance, horde, neutral
E.defaults.general.skinParts = {}         -- part -> skin id, a part's own skin
E.defaults.general.skinTitleFont = true   -- window titles in the skin's title font
if E.defaults.general.blizzardWindows == nil then E.defaults.general.blizzardWindows = "layout" end

local manifests = {}                                       -- id -> manifest as registered
local merged = {}                                          -- "id|variant" -> manifest in effect
local owned = setmetatable({}, { __mode = "k" })           -- frame -> skin pieces
local hooked = setmetatable({}, { __mode = "k" })          -- frame -> true (OnSizeChanged hook)
local surfaces = setmetatable({}, { __mode = "k" })        -- object -> { kind, part, opts }
local LEGACY_ORDER = { Modern = 10, Blizzard = 30, Classic = 40, Forever = 50, Contrast = 1000 }
local KINDS = { framed = true, framedThin = true, palette = true, edge = true, frame = true, ring = true, iconRing = true }
local PANEL_KINDS = { panel = true, window = true, tooltip = true, chat = true }
local TEXELS = 2                                           -- texels per UI pixel in every skin texture

local function Number(value)
	if type(value) ~= "number" or (issecretvalue and issecretvalue(value)) then return nil end
	return value
end

local function Mix(a, b, t)
	return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t }
end

local function Hex(hex)
	if type(hex) ~= "string" or not hex:match("^%x%x%x%x%x%x$") then return nil end
	return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
end

-- WCAG luminance, the formula E:AccentTextColor and tools/design/contrast.py use.
local function Linear(c)
	if c <= 0.04045 then return c / 12.92 end
	return ((c + 0.055) / 1.055) ^ 2.4
end
local function Luminance(c) return 0.2126 * Linear(c[1]) + 0.7152 * Linear(c[2]) + 0.0722 * Linear(c[3]) end

---------------------------------------------------------------------------
-- Manifests
---------------------------------------------------------------------------
-- The colors a native skin gives small boxes, tabs and see-through panels,
-- worked out from its art colors (E.tokens.skin).
local function DefaultPalette(data)
	local c, t = data.colors, E.tokens.skin
	local panel, edge = c.panel, c.edge
	-- See-through panels: the panel color darkened to the flat panel's
	-- luminance (E.media's backdrop), never lighter than the art.
	local flat = E.tokens.skin.seeThrough
	local want, k = Luminance(flat), 1
	while k > 0 and Luminance({ panel[1] * k, panel[2] * k, panel[3] * k }) > want do k = k - 0.02 end
	k = math.max(0, k)
	local tab = Mix(c.panelAlt or panel, edge, t.tabMix)
	return {
		backdrop = { panel[1], panel[2], panel[3], t.boxAlpha },
		border = { edge[1] * t.borderShade, edge[2] * t.borderShade, edge[3] * t.borderShade, 1 },
		seeThrough = { panel[1] * k, panel[2] * k, panel[3] * k },
		selectedTab = { tab[1], tab[2], tab[3], t.tabAlpha },
		windowEdge = { edge[1], edge[2], edge[3], 1 },
	}
end

local function DefaultCard(data)
	local edge = data.colors.edge
	return { edge = { edge[1], edge[2], edge[3], E.tokens.skin.cardEdge } }
end

local function Copy(t)
	if type(t) ~= "table" then return t end
	local out = {}
	for k, v in pairs(t) do out[k] = Copy(v) end
	return out
end

-- The variant a skin with variants draws: the profile's pick, else the
-- character's faction (the game says which; an unknown one gives Neutral).
local variantSecret = E.Secret
local variantType, variantText = type, tostring
local variantEnvironment = _G
local variantFactionRead = UnitFactionGroup
local function VariantKey(base)
	local variants = base.variants
	local pick = E.db and E.db.general and E.db.general.skinVariant
	if variantType(pick) == "string" and pick ~= "auto" and variantType(variants[pick]) == "table" then return pick end
	local faction = variantFactionRead and variantFactionRead("player")
	if variantSecret(faction) then return end
	if faction == "Alliance" and variants.alliance then return "alliance" end
	if faction == "Horde" and variants.horde then return "horde" end
	if variants.neutral then return "neutral" end
	return variants.order and variants.order[1]
end
local variantEnvironmentMeta = getmetatable(variantEnvironment)
local variantEnvironmentIndex = type(variantEnvironmentMeta) == "table" and rawget(variantEnvironmentMeta, "__index") or nil
Skins.VariantKey = function(id)
	local base = manifests[id]
	return base and base.variants and VariantKey(base) or nil
end

local function Merge(id, base, variant)
	local m = {}
	for k, v in pairs(base) do m[k] = v end
	local over = variant and base.variants[variant]
	if type(over) == "table" then
		-- A variant changes only its art, accent, palette and card.
		for _, k in ipairs({ "art", "accent", "palette", "card" }) do
			if over[k] ~= nil then m[k] = over[k] end
		end
	end
	m.id, m.variant = id, variant
	m.recipes = m.recipes or {}
	m.fonts = m.fonts or {}
	if not m.legacy then
		m.data = E.skinData and E.skinData[m.art] or nil
		if m.data then
			local palette = DefaultPalette(m.data)
			for k, v in pairs(type(m.palette) == "table" and m.palette or {}) do palette[k] = v end
			m.palette = palette
			m.card = m.card or DefaultCard(m.data)
		end
	end
	m.palette = m.palette or {}
	-- Flags: the manifest's own, plus what a native skin brings by itself.
	local flags = {}
	for k, v in pairs(type(base.flags) == "table" and base.flags or {}) do flags[k] = v end
	if m.data then
		if flags.selectedTabTint == nil and m.palette.selectedTab then flags.selectedTabTint = true end
		if flags.iconRing == nil and m.recipes.icon == "iconRing" then flags.iconRing = true end
	end
	m.flags = flags
	return m
end

-- The manifest in effect for a skin (default: the profile's), with its
-- variant merged in and its art data attached. An unknown id gives Modern's
-- manifest; it is never nil.
function E:SkinManifest(id)
	if id == nil then
		id = self.db and self:ArtStyle() or "Modern"
	elseif not manifests[id] or not self.artStyles[id] then
		id = self:ArtStyle(id)
	end
	local base = manifests[id] or manifests.Modern
	if not base then return { id = id or "Modern", legacy = true, recipes = {}, fonts = {}, palette = {} } end
	local variant = base.variants and VariantKey(base) or nil
	local key = id .. "|" .. variantText(variant)
	local m = merged[key]
	if not m then
		m = Merge(id, base, variant)
		merged[key] = m
	end
	return m
end

-- A flag of the skin in effect (default: the profile's skin), see
-- Data/Skins.lua: bronze, selectedTabTint, tabFill, pinShape, iconRing.
function E:SkinFlag(name, id)
	if type(name) ~= "string" then return nil end
	local m = self:SkinManifest(id)
	return m.flags and m.flags[name]
end

-- The color of EldoUI's Bronze marks under the skin in effect: the accent
-- in use (WoW Forever), the skin's own accent (the warm native skins) or
-- the Bronze color itself. Returns r, g, b.
function E:SkinBronze()
	local how = self:SkinFlag("bronze")
	if how == "accent" then
		local c = self.media.accentColor
		return c[1], c[2], c[3]
	end
	if how == "skin" then
		local r, g, b = Hex(self:SkinManifest().accent)
		if r then return r, g, b end
	end
	local c = self.tokens.palette.bronze
	return c[1], c[2], c[3]
end

-- Does this skin draw native art (not one of the five painters in Core/Media.lua)?
function Skins.IsNative(id)
	local base = manifests[id]
	return base ~= nil and not base.legacy and E.skinData ~= nil and E.skinData[base.art] ~= nil
end

-- The palette of a native skin in effect (variant aware), or nil for the
-- legacy skins (Core/Media.lua keeps theirs).
function Skins.PaletteOf(id)
	if not Skins.IsNative(id) then return nil end
	local m = E:SkinManifest(id)
	return m.data and m.palette or nil
end

-- A bar texture name a manifest names, as a path (Smooth when unknown).
function E:SkinBarTexture(id)
	local m = self:SkinManifest(id)
	local name = m.statusbar
	return (name and self.media.statusbars[name]) or self.media.statusbars.Smooth
end

-- The accent a skin brings and how ("bring" or "soft"), or nil.
function E:SkinAccent(id)
	local m = self:SkinManifest(id)
	if m.accent and Hex(m.accent) then return m.accent, m.accentMode or "soft" end
	return nil
end

-- Add a skin. Native skins (an `art` key with art data) get a painter, a
-- place in the picker, their palette and card colors; legacy manifests only
-- describe a painter Core/Media.lua already has. Returns true when added.
function E:RegisterSkin(id, m)
	if type(id) ~= "string" or not id:match("^%a[%w]*$") or #id > 32 or type(m) ~= "table" then return false end
	if id == "Follow" then return false end
	if m.legacy and not self.artStyles[id] then return false end
	manifests[id] = m
	wipe(merged)
	if m.legacy then return true end
	local data = self.skinData and self.skinData[m.art]
	if not data then
		manifests[id] = nil
		return false
	end
	self.artStyles[id] = function(frame, transparent) Skins.PaintPanel(frame, transparent, id) end
	-- The picker order: by `order`, High contrast always last.
	local list = self.artStyleOrder
	for index = #list, 1, -1 do
		if list[index] == id then table.remove(list, index) end
	end
	local order = tonumber(m.order) or 500
	local at = #list + 1
	for index, key in ipairs(list) do
		local other = manifests[key] and tonumber(manifests[key].order) or LEGACY_ORDER[key] or 500
		if key == "Contrast" or other > order then at = index break end
	end
	table.insert(list, at, id)
	self.artStyleInfo[id] = { title = m.title or id, short = m.short, desc = m.desc }
	local palette = self:SkinManifest(id).palette
	if self.RegisterStylePalette then self:RegisterStylePalette(id, palette.backdrop, palette.border) end
	self.tokens.card.styles[id] = self:SkinManifest(id).card
	-- The skin's bar texture joins the bar texture list ("Eldo <name>" for
	-- other addons through LibSharedMedia).
	if type(m.statusbar) == "string" and not self.media.statusbars[m.statusbar] and data.files and data.files.bar then
		self.media.statusbars[m.statusbar] = data.files.bar
		if self.RegisterMedia then self:RegisterMedia("statusbar", m.statusbar, m.statusbar, data.files.bar, { source = "EldoUI" }) end
	end
	return true
end

-- Register what Data/Skins.lua lists (native skins need Data/SkinData.lua).
for id, m in pairs(E.skinManifests or {}) do
	if m.legacy then manifests[id] = m end
end
do
	local ids = {}
	for id, m in pairs(E.skinManifests or {}) do
		if not m.legacy then ids[#ids + 1] = id end
	end
	table.sort(ids, function(a, b)
		return (E.skinManifests[a].order or 500) < (E.skinManifests[b].order or 500)
	end)
	for _, id in ipairs(ids) do E:RegisterSkin(id, E.skinManifests[id]) end
end

-- The manifest cache follows the profile (variant, faction).
E:OnThemeChanged("skins", function() wipe(merged) end)

---------------------------------------------------------------------------
-- The skin of a part, picker values, picking and following the layout
---------------------------------------------------------------------------
-- A part's own pick: general.skinParts[part], the options window's
-- general.configStyle ("Follow" follows the skin).
local function PartPick(general, part)
	if not (general and part) then return nil end
	if part == "config" then return general.configStyle end
	return type(general.skinParts) == "table" and general.skinParts[part] or nil
end

function E:SkinPart(part)
	if not (self.db and self.db.general) then return "Modern" end
	local skin = self:ArtStyle()
	if skin == "Contrast" then return "Contrast" end
	local pick = PartPick(self.db.general, part)
	if type(pick) == "string" and pick ~= "Follow" and pick ~= "Contrast" and self.artStyles[pick] then
		return self:ArtStyle(pick)
	end
	return skin
end

-- What a skin picker offers: values ({ id = title }) and the ids in picker
-- order. High contrast is left out unless opts.contrast; WoW Forever only
-- shows on the Forever client or while in use. A saved skin that is not
-- available (a plugin that is gone) is listed as such. opts.follow = a label
-- adds a "Follow" entry first; opts.extra = { id = title } adds more.
function E:SkinValues(opts)
	opts = type(opts) == "table" and opts or {}
	local values, order = {}, {}
	if opts.follow then
		values.Follow = type(opts.follow) == "string" and opts.follow or L["Follow layout"]
		order[#order + 1] = "Follow"
	end
	local saved = self.db and self.db.general and self.db.general.artStyle
	for _, id in ipairs(self.artStyleOrder) do
		local offered = id ~= "Contrast" or opts.contrast
		if id == "Forever" and not (self:ForeverArt() or saved == "Forever") then offered = false end
		if offered then
			local info = self.artStyleInfo[id]
			values[id] = L[info and info.title or id]
			order[#order + 1] = id
		end
	end
	if type(saved) == "string" and saved ~= "" and not self.artStyles[saved] then
		values[saved] = L["%s (not available): Modern is used"]:format(saved)
		order[#order + 1] = saved
	end
	for id, title in pairs(type(opts.extra) == "table" and opts.extra or {}) do
		if values[id] == nil then order[#order + 1] = id end
		values[id] = title
	end
	return values, order
end

-- The High contrast backup holds the skin while High contrast is on.
local function ContrastBackup(general)
	local backup = type(general.accessBackup) == "table" and general.accessBackup.contrast
	if general.artStyle == "Contrast" and type(backup) == "table" then return backup end
end

local function Repaint(self)
	if self.RefreshTheme then self:RefreshTheme() else self:UpdateAccent(); self:UpdateArtStyle() end
end

-- Pick a skin. An explicit pick stops following the layout; opts.follow
-- marks a pick the layout made. An id that is not available (a plugin skin
-- that is gone) is kept as asked and draws as Modern. While High contrast
-- is on the pick goes to its backup and shows once High contrast is off.
-- Returns true when saved.
function E:SetSkin(id, opts)
	if not (self.db and self.db.general) then return false end
	if type(id) ~= "string" or not id:match("^%a[%w]*$") or #id > 32 or id == "Follow" then return false end
	opts = type(opts) == "table" and opts or {}
	local general = self.db.general
	if opts.follow then general.skinFollow = true else general.skinFollow = false end
	local backup = id ~= "Contrast" and ContrastBackup(general)
	if backup then
		backup.artStyle = id
		return true
	end
	local old = general.artStyle
	if opts.follow and old == id then return true end
	general.artStyle = id
	self:ArtStyleAccent(old, id)
	Repaint(self)
	return true
end

-- Faction Heritage's look (auto, alliance, horde, neutral). The accent the
-- old look brought moves to the new one.
function E:SetSkinVariant(variant)
	if not (self.db and self.db.general) then return false end
	if variant ~= "auto" and variant ~= "alliance" and variant ~= "horde" and variant ~= "neutral" then return false end
	local general = self.db.general
	local oldAccent = self:SkinAccent()
	general.skinVariant = variant
	wipe(merged)
	local newAccent = self:SkinAccent()
	if general.accentFromArt and oldAccent and general.accent == oldAccent and newAccent then general.accent = newAccent end
	Repaint(self)
	return true
end

-- The variants a skin offers for a picker: values and order, "auto" first.
-- Nil for a skin without variants.
function E:SkinVariants(id)
	local base = manifests[id or (self.db and self.db.general.artStyle)]
	if not (base and base.variants) then return nil end
	local values, order = { auto = L["Auto: your character's faction"] }, { "auto" }
	for _, key in ipairs(base.variants.order or {}) do
		local v = base.variants[key]
		values[key] = L[v.title or key]
		order[#order + 1] = key
	end
	return values, order
end

-- The skin a layout was made for: its `skin`, else the client's own look.
function E:LayoutSkin(layoutKey)
	local general = self.db and self.db.general
	local layout = self.layouts and self.layouts[layoutKey or (general and general.layout)]
	local skin = type(layout) == "table" and layout.skin
	if type(skin) == "string" and skin ~= "" then return skin end
	return self:ClientLook().artStyle
end

-- Called after a layout is applied: a profile that follows the layout gets
-- the layout's skin (a repeat changes nothing), and, when Blizzard windows
-- follow the layout, their look. Returns true when the skin changed.
function E:FollowLayoutSkin(layoutKey)
	if not (self.db and self.db.general) then return false end
	local general = self.db.general
	local changed = false
	if general.skinFollow then
		local want = self:LayoutSkin(layoutKey)
		local backup = ContrastBackup(general)
		if backup then
			if backup.artStyle ~= want then backup.artStyle, changed = want, true end
		elseif general.artStyle ~= want then
			self:SetSkin(want, { follow = true })
			changed = true
		end
	end
	if general.blizzardWindows == "layout" and self.ApplyBlizzardWindows then self:ApplyBlizzardWindows() end
	return changed
end

-- Run on a saved profile before the defaults fill it (Core/Database.lua,
-- next to E:PinClientLook): a profile from before skins keeps its skin when
-- a layout is applied and keeps Blizzard's windows as they are.
local SKIN_MARK = "skinLook"
function E:PinSkinLook(profile, fresh)
	if type(profile) ~= "table" or profile[SKIN_MARK] then return end
	profile[SKIN_MARK] = 1
	if fresh then return end
	if type(profile.general) ~= "table" then profile.general = {} end
	if profile.general.skinFollow == nil then profile.general.skinFollow = false end
	if profile.general.blizzardWindows == nil then profile.general.blizzardWindows = "keep" end
end

---------------------------------------------------------------------------
-- Pieces: created once per frame, reused across skins, laid out on one
-- OnSizeChanged hook. Release hides them; nothing is ever destroyed.
---------------------------------------------------------------------------
local RING = { "tl", "t", "tr", "l", "r", "bl", "b", "br" }
local CORNERS = { "tl", "tr", "bl", "br" }
-- Texture coordinates of the corner ornament per corner (the art is the top-left one).
local CORNER_COORDS = {
	tl = { 0, 1, 0, 1 }, tr = { 1, 0, 0, 1 }, bl = { 0, 1, 1, 0 }, br = { 1, 0, 1, 0 },
}

local function Tex(frame, layer, sub)
	local tex = frame:CreateTexture(nil, layer, nil, sub)
	if tex.SetSnapToPixelGrid then tex:SetSnapToPixelGrid(false) end
	if tex.SetTexelSnappingBias then tex:SetTexelSnappingBias(0) end
	return tex
end

local function Record(frame)
	local rec = owned[frame]
	if not rec then
		rec = { ring = {}, corners = {} }
		owned[frame] = rec
	end
	return rec
end

local function Ring(rec, frame, file)
	for _, key in ipairs(RING) do
		local tex = rec.ring[key]
		if not tex then
			tex = Tex(frame, "ARTWORK", 6)
			rec.ring[key] = tex
		end
		tex:SetTexture(file)
		tex:SetVertexColor(1, 1, 1, 1)
		tex:ClearAllPoints()
	end
	return rec.ring
end

local function HideRing(rec)
	for _, key in ipairs(RING) do
		if rec.ring[key] then rec.ring[key]:Hide() end
	end
end

local function HideCorners(rec)
	for _, key in ipairs(CORNERS) do
		if rec.corners[key] then rec.corners[key]:Hide() end
	end
	rec.cornersShown = false
end

-- A ring is laid out again on every size change, and the full and the thin
-- layout anchor different points: each layout starts from no points, so no
-- edge keeps an anchor of the other one and stretches past its frame.
local function ClearRing(ring)
	for _, key in ipairs(RING) do
		if ring[key] then ring[key]:ClearAllPoints() end
	end
end

-- The 9-slice ring: four corners `size` square, four stretched edges, the
-- center left open. `m` is the slice margin as a share of the texture,
-- u0..u1 the part of the texture the ring is cut from (button.tga holds two).
local function LayoutFull(ring, frame, o, size, mu, mv, u0, u1)
	ClearRing(ring)
	local w = u1 - u0
	local a, b = u0 + w * mu, u1 - w * mu
	ring.tl:SetPoint("TOPLEFT", frame, "TOPLEFT", -o, o)
	ring.tl:SetSize(size, size)
	ring.tl:SetTexCoord(u0, a, 0, mv)
	ring.tr:SetPoint("TOPRIGHT", frame, "TOPRIGHT", o, o)
	ring.tr:SetSize(size, size)
	ring.tr:SetTexCoord(b, u1, 0, mv)
	ring.bl:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", -o, -o)
	ring.bl:SetSize(size, size)
	ring.bl:SetTexCoord(u0, a, 1 - mv, 1)
	ring.br:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", o, -o)
	ring.br:SetSize(size, size)
	ring.br:SetTexCoord(b, u1, 1 - mv, 1)
	ring.t:SetPoint("TOPLEFT", ring.tl, "TOPRIGHT")
	ring.t:SetPoint("BOTTOMRIGHT", ring.tr, "BOTTOMLEFT")
	ring.t:SetTexCoord(a, b, 0, mv)
	ring.b:SetPoint("TOPLEFT", ring.bl, "TOPRIGHT")
	ring.b:SetPoint("BOTTOMRIGHT", ring.br, "BOTTOMLEFT")
	ring.b:SetTexCoord(a, b, 1 - mv, 1)
	ring.l:SetPoint("TOPLEFT", ring.tl, "BOTTOMLEFT")
	ring.l:SetPoint("BOTTOMRIGHT", ring.bl, "TOPRIGHT")
	ring.l:SetTexCoord(u0, a, mv, 1 - mv)
	ring.r:SetPoint("TOPLEFT", ring.tr, "BOTTOMLEFT")
	ring.r:SetPoint("BOTTOMRIGHT", ring.br, "TOPRIGHT")
	ring.r:SetTexCoord(b, u1, mv, 1 - mv)
	for _, key in ipairs(RING) do ring[key]:Show() end
end

-- Thin: only the four edges, `s` units thick, cut from the art's outer band
-- (`band` as a share of the texture); for frames too small for corners and
-- for the edge on bars.
local function LayoutThin(ring, frame, o, s, mu, band)
	ClearRing(ring)
	ring.tl:Hide(); ring.tr:Hide(); ring.bl:Hide(); ring.br:Hide()
	ring.t:SetPoint("TOPLEFT", frame, "TOPLEFT", -o, o)
	ring.t:SetPoint("TOPRIGHT", frame, "TOPRIGHT", o, o)
	ring.t:SetHeight(s)
	ring.t:SetTexCoord(mu, 1 - mu, 0, band)
	ring.b:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", -o, -o)
	ring.b:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", o, -o)
	ring.b:SetHeight(s)
	ring.b:SetTexCoord(mu, 1 - mu, 1 - band, 1)
	ring.l:SetPoint("TOPLEFT", ring.t, "BOTTOMLEFT")
	ring.l:SetPoint("BOTTOMLEFT", ring.b, "TOPLEFT")
	ring.l:SetWidth(s)
	ring.l:SetTexCoord(0, band, mu, 1 - mu)
	ring.r:SetPoint("TOPRIGHT", ring.t, "BOTTOMRIGHT")
	ring.r:SetPoint("BOTTOMRIGHT", ring.b, "TOPRIGHT")
	ring.r:SetWidth(s)
	ring.r:SetTexCoord(1 - band, 1, mu, 1 - mu)
	ring.t:Show(); ring.b:Show(); ring.l:Show(); ring.r:Show()
end

local function Layout(frame)
	local rec = owned[frame]
	if not (rec and rec.mode and rec.data) then return end
	local width, height = frame:GetSize()
	width, height = Number(width), Number(height)
	-- A secret size keeps the layout it had until the size reads again.
	if not (width and height) then return end
	local data, tokens = rec.data, E.tokens.skin
	local metrics = data.metrics
	local margin = metrics.sliceMargin
	local mu = margin.texels / 64 -- the slice margin as a share of the 64-texel border
	local band = math.min(0.5, metrics.band * TEXELS / 64)
	if rec.mode == "framed" or rec.mode == "border" then
		local o = metrics.outset
		local thin = width + 2 * o < 2 * margin.ui + 4 or height + 2 * o < 2 * margin.ui + 4
		rec.thin = thin
		if thin then
			LayoutThin(rec.ring, frame, o, metrics.band, mu, band)
		else
			LayoutFull(rec.ring, frame, o, margin.ui, mu, mu, 0, 1)
		end
		local min = tokens.cornerMin
		local corners = rec.wantCorners and data.files.corner and width >= min[1] and height >= min[2]
		if corners then
			local size, oo = tokens.corner, metrics.ornamentOutset
			for _, key in ipairs(CORNERS) do
				local tex = rec.corners[key]
				if not tex then
					tex = Tex(frame, "ARTWORK", 7)
					rec.corners[key] = tex
				end
				tex:SetTexture(data.files.corner)
				tex:SetVertexColor(1, 1, 1, 1)
				tex:SetTexCoord(unpack(CORNER_COORDS[key]))
				tex:ClearAllPoints()
				tex:SetSize(size, size)
				tex:Show()
			end
			rec.corners.tl:SetPoint("TOPLEFT", frame, "TOPLEFT", -oo, oo)
			rec.corners.tr:SetPoint("TOPRIGHT", frame, "TOPRIGHT", oo, oo)
			rec.corners.bl:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", -oo, -oo)
			rec.corners.br:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", oo, -oo)
			rec.cornersShown = true
		else
			HideCorners(rec)
		end
		if rec.fill and rec.fill:IsShown() then
			-- The fill sits under the border, inset so rounded or clipped
			-- corners never show it; one tile covers tokens.skin.tile units.
			local inset = math.max(1, math.floor(metrics.borderSize / 2))
			rec.fill:ClearAllPoints()
			rec.fill:SetPoint("TOPLEFT", frame, "TOPLEFT", inset, -inset)
			rec.fill:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -inset, inset)
			local tile = tokens.tile
			rec.fill:SetTexCoord(0, math.max(0.01, (width - 2 * inset) / tile), 0, math.max(0.01, (height - 2 * inset) / tile))
		end
	elseif rec.mode == "edge" then
		local s = math.max(1, math.min(tokens.edgeThin, metrics.band))
		LayoutThin(rec.ring, frame, math.floor(s / 2), s, mu, band)
		HideCorners(rec)
	elseif rec.mode == "button" then
		local button = metrics.button.sliceMargin
		local size = math.min(button.ui, math.floor(math.min(width, height) / 2))
		-- button.tga: 128 x 64 texels, the frame in its left half.
		LayoutFull(rec.ring, frame, 0, size, button.texels / 64, button.texels / 64, 0, 0.5)
		HideCorners(rec)
	elseif rec.mode == "icon" then
		-- Aura and cooldown icons: a thin ring cut from the skin's border.
		-- Small icons keep their flat keyline, the ring would cover them.
		local s = math.max(1, math.min(tokens.iconRing, metrics.band))
		if math.min(width, height) < tokens.iconMin then
			HideRing(rec)
			rec.thin = false
		else
			LayoutThin(rec.ring, frame, rec.outside and math.max(0, s - E.pixel) or 0, s, mu, band)
			rec.thin = true
		end
		HideCorners(rec)
	elseif rec.mode == "round" then
		local o = metrics.portrait.ring.outset
		rec.round:ClearAllPoints()
		rec.round:SetPoint("TOPLEFT", frame, "TOPLEFT", -o, o)
		rec.round:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", o, -o)
		rec.round:Show()
		HideCorners(rec)
	end
end

local function Hook(frame)
	if hooked[frame] or not frame.HookScript then return end
	hooked[frame] = true
	frame:HookScript("OnSizeChanged", Layout)
end

-- Hide every skin piece on a frame (a legacy painter or another skin takes
-- over). Safe on anything; returns true when pieces were shown.
function Skins.Release(frame)
	local rec = frame and owned[frame]
	if not rec then return false end
	local shown = rec.mode ~= nil
	HideRing(rec)
	HideCorners(rec)
	if rec.fill then rec.fill:Hide() end
	if rec.hover then rec.hover:Hide() end
	if rec.round then rec.round:Hide() end
	rec.mode, rec.id, rec.data, rec.wantCorners, rec.thin, rec.outside = nil, nil, nil, nil, nil, nil
	return shown
end

-- Read-only (tests, plugins): what the skin draws on a frame: mode
-- ("framed", "border", "edge", "button", "round" or nil), skin id, whether
-- the corner ornaments show, whether the ring is thin, and how many pieces
-- the frame owns.
function Skins.State(frame)
	local rec = frame and owned[frame]
	if not rec then return nil, nil, false, false, 0 end
	local count = 0
	for _ in pairs(rec.ring) do count = count + 1 end
	for _ in pairs(rec.corners) do count = count + 1 end
	if rec.fill then count = count + 1 end
	if rec.hover then count = count + 1 end
	if rec.round then count = count + 1 end
	return rec.mode, rec.id, rec.cornersShown == true, rec.thin == true, count
end

-- Lay a painted frame out again from the size it has now (after a layout
-- or setup apply, when a size may have settled without a size change).
function Skins.Relayout(frame)
	if frame and owned[frame] then Layout(frame) end
end

-- The ring pieces a frame carries (tl, t, tr, l, r, bl, b, br), or nil.
function Skins.RingPieces(frame)
	local rec = frame and owned[frame]
	return rec and rec.ring or nil
end

-- A panel's background opacity lives on the fill texture of a material
-- skin (the backdrop under it stays clear, so the panel is not drawn twice).
-- Core/Media.lua calls this after a panel's own opacity is applied.
function Skins.SyncAlpha(frame)
	local rec = frame and owned[frame]
	if not (rec and rec.mode == "framed" and rec.fill and rec.fill:IsShown() and frame.GetBackdropColor) then return end
	local ok, r, g, b, a = pcall(frame.GetBackdropColor, frame)
	a = ok and Number(a)
	if a and a > 0 then
		rec.fill:SetVertexColor(1, 1, 1, a)
		frame:SetBackdropColor(r, g, b, 0)
	end
end

---------------------------------------------------------------------------
-- Painters (recipes): painter(frame, manifest, opts)
---------------------------------------------------------------------------
local painters = {}
Skins.painters = painters

local function CanPaint(frame)
	return type(frame) == "table" and frame.CreateTexture and frame.HookScript and frame.GetSize and true or false
end

-- Panel background: material skins are opaque (their art is the material);
-- flat skins follow General > Panel opacity. See-through panels use the
-- skin's see-through color at the see-through opacity, without the material.
local function PanelBackground(frame, m, opts)
	local rec = Record(frame)
	local palette = m.palette
	local transparent = opts.transparent
	local material = m.data.files.panel and not transparent
	local color = transparent and palette.seeThrough or palette.backdrop
	local r, g, b = color[1], color[2], color[3]
	if m.tint then r, g, b = E:TintBackdrop(r, g, b, nil, m.id) end
	local alpha = material and 1 or E:PanelAlpha(transparent)
	frame:SetBackdrop({ bgFile = E.media.flat })
	frame:SetBackdropColor(r, g, b, alpha)
	if material then
		if not rec.fill then rec.fill = Tex(frame, "BACKGROUND", 1) end
		rec.fill:SetTexture(m.data.files.panel, "REPEAT", "REPEAT")
		rec.fill:SetVertexColor(1, 1, 1, alpha)
		rec.fill:Show()
	elseif rec.fill then
		rec.fill:Hide()
	end
end

local function Framed(frame, m, opts, corners)
	if not CanPaint(frame) then return end
	E:AddBackdrop(frame)
	if E.HideStyleRing then E:HideStyleRing(frame) end
	local rec = Record(frame)
	if rec.hover then rec.hover:Hide() end
	if rec.round then rec.round:Hide() end
	PanelBackground(frame, m, opts)
	E:UpdateShadow(frame, (m.shadows and E.db and E.db.general.shadows) and true or false)
	rec.mode, rec.id, rec.data, rec.wantCorners = "framed", m.id, m.data, corners and true or false
	Ring(rec, frame, m.data.files.border)
	Hook(frame)
	Layout(frame)
	Skins.SyncAlpha(frame)
end

-- Windows and dialogs: border, material and corner ornaments.
painters.framed = function(frame, m, opts) Framed(frame, m, opts or {}, true) end
-- Every other panel (tooltips, chat, see-through panels): no corners.
painters.framedThin = function(frame, m, opts) Framed(frame, m, opts or {}, false) end

-- Small boxes: the skin's colors only, so they stay pixel sharp.
painters.palette = function(frame, _, opts)
	if not (type(frame) == "table" and frame.SetBackdrop or (frame and frame.HookScript)) then return end
	Skins.Release(frame)
	E:SetTemplate(frame, opts and opts.transparent)
end

-- Bars and strips: the thin edge cut from the skin's border.
painters.edge = function(frame, m)
	if not CanPaint(frame) then return end
	local rec = Record(frame)
	if rec.fill then rec.fill:Hide() end
	if rec.hover then rec.hover:Hide() end
	if rec.round then rec.round:Hide() end
	rec.mode, rec.id, rec.data, rec.wantCorners = "edge", m.id, m.data, false
	Ring(rec, frame, m.data.files.border)
	Hook(frame)
	Layout(frame)
end

-- Action buttons: the skin's button frame over the button and a hover
-- overlay (the right half of button.tga) in the highlight color.
painters.frame = function(frame, m)
	if not CanPaint(frame) then return end
	local rec = Record(frame)
	if rec.fill then rec.fill:Hide() end
	if rec.round then rec.round:Hide() end
	HideCorners(rec)
	local file = m.data.files.button
	if not file then return Skins.Release(frame) end
	rec.mode, rec.id, rec.data, rec.wantCorners = "button", m.id, m.data, false
	Ring(rec, frame, file)
	if not rec.hover then
		rec.hover = Tex(frame, "HIGHLIGHT")
		rec.hover:SetAllPoints(frame)
	end
	rec.hover:SetTexture(file)
	rec.hover:SetTexCoord(0.5, 1, 0, 1)
	rec.hover:SetBlendMode("ADD")
	local c = m.data.colors.highlight
	rec.hover:SetVertexColor(c[1], c[2], c[3], E.tokens.skin.hoverAlpha)
	rec.hover:Show()
	Hook(frame)
	Layout(frame)
end

-- Aura and cooldown icons: the thin ring of the skin's border on the icon's
-- edge (opts.outside: around a box that sits just outside the icon). The
-- icon's flat keyline stays under it, and icons under tokens.skin.iconMin
-- keep only the keyline. opts.static: the caller builds the icon again on
-- a theme change, so no size hook is added (aura buttons may only be
-- touched while they are set up).
painters.iconRing = function(frame, m, opts)
	if not CanPaint(frame) then return end
	local rec = Record(frame)
	if rec.fill then rec.fill:Hide() end
	if rec.hover then rec.hover:Hide() end
	if rec.round then rec.round:Hide() end
	rec.mode, rec.id, rec.data, rec.wantCorners = "icon", m.id, m.data, false
	rec.outside = opts and opts.outside and true or nil
	Ring(rec, frame, m.data.files.border)
	if not (opts and opts.static) then Hook(frame) end
	Layout(frame)
end

-- The minimap: the round ring around a round map, the skin's border around
-- a square one (opts.square).
painters.ring = function(frame, m, opts)
	if not CanPaint(frame) then return end
	local rec = Record(frame)
	if rec.fill then rec.fill:Hide() end
	if rec.hover then rec.hover:Hide() end
	HideCorners(rec)
	if opts and opts.square then
		if rec.round then rec.round:Hide() end
		rec.mode, rec.id, rec.data, rec.wantCorners = "border", m.id, m.data, false
		Ring(rec, frame, m.data.files.border)
	else
		HideRing(rec)
		if not rec.round then rec.round = Tex(frame, "ARTWORK", 6) end
		rec.round:SetTexture(m.data.files.ring)
		rec.round:SetTexCoord(0, 1, 0, 1)
		rec.round:SetVertexColor(1, 1, 1, 1)
		rec.mode, rec.id, rec.data, rec.wantCorners = "round", m.id, m.data, false
	end
	Hook(frame)
	Layout(frame)
end

-- The painter of every native skin's panels (E.artStyles[id]): windows
-- (E:SetWindowEdge) get the window recipe, see-through panels the chat
-- recipe, other panels the panel recipe.
function Skins.PaintPanel(frame, transparent, id)
	local m = E:SkinManifest(id)
	if m.legacy or not m.data then return E.artStyles.Modern(frame, transparent) end
	local kind = (E.IsWindowEdge and E:IsWindowEdge(frame)) and "window" or (transparent and "chat" or "panel")
	if kind == "window" and transparent then kind = "chat" end
	local painter = painters[m.recipes[kind]] or painters.framedThin
	painter(frame, m, { transparent = transparent, kind = kind })
end

-- The thin edge on bars and strips under a native skin whose bar recipe is
-- "edge" (E:SetStyleEdge). A panel keeps its own border. Returns true when
-- the edge is drawn.
function Skins.ShowEdge(frame, id)
	local m = E:SkinManifest(id)
	if m.legacy or not m.data or m.recipes.bar ~= "edge" then return false end
	if E.panels and E.panels[frame] then return true end
	painters.edge(frame, m)
	return true
end

---------------------------------------------------------------------------
-- Surfaces
---------------------------------------------------------------------------
local function RepaintSurface(object)
	local s = surfaces[object]
	if s then E:PaintSurface(object, s.kind, s.part, s.opts) end
end

-- Paint one surface in the skin of its part. kind: panel, window, tooltip,
-- chat, box, bar, castbar, button, minimap (or any recipe kind a manifest
-- names). opts.transparent: a see-through panel; opts.square: a square
-- minimap; opts.outside: an icon ring around a box just outside the icon;
-- opts.static: paint once without repainting on theme changes. The surface repaints on every theme change until released.
-- Returns the skin id the surface draws in.
function E:PaintSurface(object, kind, part, opts)
	local id = self:SkinPart(part)
	if type(object) ~= "table" or type(kind) ~= "string" then return id end
	opts = type(opts) == "table" and opts or nil
	-- opts.static: painted once, the caller paints again when the look changes.
	if not (opts and opts.static) then
		if not surfaces[object] then self:RegisterThemed(object, RepaintSurface) end
		surfaces[object] = { kind = kind, part = part, opts = opts }
	end
	local m = self:SkinManifest(id)
	local transparent = opts and opts.transparent or kind == "chat"
	if m.legacy or not m.data then
		-- The five skins of Core/Media.lua draw what they always drew.
		Skins.Release(object)
		if PANEL_KINDS[kind] and CanPaint(object) then
			self:AddBackdrop(object)
			if not self:SkinAllowsShadows(id) then self:UpdateShadow(object, false) end
			self.artStyles[id](object, transparent)
		elseif kind == "box" and object.HookScript then
			self:SetTemplate(object, transparent)
		end
		return id
	end
	local recipe = m.recipes[kind]
	if PANEL_KINDS[kind] and not KINDS[recipe or ""] then recipe = kind == "window" and "framed" or "framedThin" end
	local painter = painters[recipe or ""]
	if painter then
		painter(object, m, { transparent = transparent, kind = kind, square = opts and opts.square,
			outside = opts and opts.outside, static = opts and opts.static })
	else
		Skins.Release(object)
	end
	return id
end

function E:ReleaseSurface(object)
	if type(object) ~= "table" then return end
	Skins.Release(object)
	surfaces[object] = nil
	self:UnregisterThemed(object)
end

-- Insets of a surface in UI units, each { left, right, top, bottom }:
-- content (where content may start), hit (always 0: ornaments never change
-- where a frame takes the mouse) and paint (how far art reaches outside).
function E:SurfaceMeasure(object)
	local s = type(object) == "table" and surfaces[object]
	local id = self:SkinPart(s and s.part)
	local m = self:SkinManifest(id)
	local content, paint = 1, 0
	if m.data then
		local metrics = m.data.metrics
		content, paint = metrics.inset, metrics.outset
		local rec = owned[object]
		if rec and rec.cornersShown then paint = math.max(paint, metrics.ornamentOutset) end
		if rec and rec.mode == "round" then paint = metrics.portrait.ring.outset end
		if rec and rec.mode == "icon" then paint = rec.thin and rec.outside and math.max(0, math.min(self.tokens.skin.iconRing, metrics.band) - self.pixel) or 0 end
		if rec and rec.mode == "edge" then paint = math.floor(math.max(1, math.min(self.tokens.skin.edgeThin, metrics.band)) / 2) end
	elseif id == "Blizzard" or id == "Classic" then
		content = 4
	elseif id == "Contrast" then
		content = 2
	end
	return { content = { content, content, content, content }, hit = { 0, 0, 0, 0 },
		paint = { paint, paint, paint, paint }, id = id }
end

-- The dock retains this source during setup; readers never receive the
-- surface or painter registries.
do
	local secret, equal = E.Secret, rawequal
	local measure, partRead, manifestRead, artRead = E.SurfaceMeasure, E.SkinPart, E.SkinManifest, E.ArtStyle
	local selectionRead, selectionBind = nil, E.BindSkinSelectionRead
	if type(selectionBind) == "function" then selectionBind(E, Skins, function(read) selectionRead = read end) end
	local sourceBind, owner, consumer, binding
	local function Same(value, saved) return not secret(value) and equal(value, saved) end
	local function Table(value) return not secret(value) and type(value) == "table" and getmetatable(value) == nil end
	local function Finite(value) return not secret(value) and type(value) == "number" and value == value and value > -math.huge and value < math.huge end
	local function Source()
		return Same(rawget(E, "Secret"), secret) and Same(secret, variantSecret)
			and Same(getmetatable(variantEnvironment), variantEnvironmentMeta)
			and (type(variantEnvironmentMeta) ~= "table" or Same(rawget(variantEnvironmentMeta, "__index"), variantEnvironmentIndex))
			and Same(rawget(E, "SurfaceMeasure"), measure)
			and Same(rawget(E, "SkinPart"), partRead) and Same(rawget(E, "SkinManifest"), manifestRead)
			and Same(rawget(E, "ArtStyle"), artRead) and Same(rawget(E, "BindSurfaceMeasurementRead"), sourceBind)
			and Same(rawget(E, "BindSkinSelectionRead"), selectionBind) and type(selectionRead) == "function"
	end
	local function Read(object)
		if secret(object) or not Source() then return end
		local pins = {}
		local function Pin(read, keys)
			local value, saved = read(), {}
			if value ~= nil and not Table(value) then return false end
			for _, key in ipairs(keys) do
				local field = value and rawget(value, key)
				if secret(field) then return false end
				saved[key] = field
			end
			pins[#pins + 1] = function()
				local current = read()
				if not Same(current, value) or (current ~= nil and not Table(current)) then return false end
				for _, key in ipairs(keys) do if not Same(current and rawget(current, key), saved[key]) then return false end end
				return true
			end
			return true
		end
		local root = rawget(E, "db")
		local general = Table(root) and rawget(root, "general")
		if not Table(general) then return end
		local parts, styles = rawget(general, "skinParts"), rawget(E, "artStyles")
		local surface, painter = rawget(surfaces, object), rawget(owned, object)
		if (surface ~= nil and not Table(surface)) or (painter ~= nil and not Table(painter))
			or (parts ~= nil and not Table(parts)) or not Table(styles) then return end
		local part = surface and rawget(surface, "part")
		if secret(part) or (part ~= nil and type(part) ~= "string") then return end
		local requested = rawget(general, "artStyle")
		local pick = part == "config" and rawget(general, "configStyle") or (parts and part and rawget(parts, part))
		if secret(requested) or secret(pick) then return end
		if requested ~= "Contrast" and type(pick) == "string" and pick ~= "Follow" and pick ~= "Contrast" and rawget(styles, pick) then requested = pick end
		if not Pin(function() return rawget(E, "db") end, { "general" })
			or not Pin(function() return rawget(root, "general") end, { "artStyle", "skinVariant", "configStyle", "skinParts" })
			or not Pin(function() return rawget(surfaces, object) end, { "part" })
			or not Pin(function() return rawget(owned, object) end, { "cornersShown", "mode", "thin", "outside" }) then return end
		if part and parts and not Pin(function() return rawget(general, "skinParts") end, { part }) then return end
		local id = partRead(E, part)
		if secret(id) or type(id) ~= "string" then return end
		local base = rawget(manifests, id)
		if not Table(base) or not Pin(function() return rawget(manifests, id) end, { "art", "legacy", "variants" }) then return end
		local variants = rawget(base, "variants")
		local usesFaction = false
		if variants ~= nil then
			if not Table(variants) then return end
			local variantPick = rawget(general, "skinVariant")
			local candidate = type(variantPick) == "string" and variantPick ~= "auto" and rawget(variants, variantPick) or nil
			if secret(candidate) then return end
			if type(candidate) == "table" then
				if not Table(candidate) or not Pin(function() return rawget(base, "variants") end, { variantPick }) then return end
			else
				usesFaction = true
				local function FactionSource()
					return not secret(variantFactionRead) and type(variantFactionRead) == "function"
						and Same(rawget(variantEnvironment, "UnitFactionGroup"), variantFactionRead)
				end
				if not FactionSource() then return end
				pins[#pins + 1] = FactionSource
				local keys = { "alliance", "horde", "neutral", "order" }
				if type(variantPick) == "string" and variantPick ~= "auto" then keys[#keys + 1] = variantPick end
				if not Pin(function() return rawget(base, "variants") end, keys) then return end
				local order = rawget(variants, "order")
				if order ~= nil and (not Table(order) or not Pin(function() return rawget(variants, "order") end, { 1 })) then return end
			end
		end
		local manifest = manifestRead(E, id)
		if not Table(manifest) then return end
		local variant, data = rawget(manifest, "variant"), rawget(manifest, "data")
		if secret(variant) or (variant ~= nil and type(variant) ~= "string") or (data ~= nil and not Table(data)) then return end
		local key = id .. "|" .. tostring(variant)
		if usesFaction and variant == nil then return end
		if not Same(rawget(merged, key), manifest)
			or not Pin(function() return rawget(merged, key) end, { "id", "variant", "art", "data" })
			or not Pin(function() return rawget(E, "artStyles") end, { id, requested or id }) then return end
		if variant and (not Table(variants) or not Pin(function() return rawget(variants, variant) end, { "art" })) then return end
		if data then
			local metrics = rawget(data, "metrics")
			if not Table(metrics) or not Finite(rawget(metrics, "inset")) or not Finite(rawget(metrics, "outset")) then return end
			local keys = { "inset", "outset" }
			if painter and rawget(painter, "cornersShown") then
				if not Finite(rawget(metrics, "ornamentOutset")) then return end
				keys[#keys + 1] = "ornamentOutset"
			end
			local mode = painter and rawget(painter, "mode")
			if mode == "round" then
				local portrait = rawget(metrics, "portrait")
				local ring = Table(portrait) and rawget(portrait, "ring")
				if not Table(ring) or not Finite(rawget(ring, "outset"))
					or not Pin(function() return rawget(metrics, "portrait") end, { "ring" })
					or not Pin(function() return rawget(portrait, "ring") end, { "outset" }) then return end
				keys[#keys + 1] = "portrait"
			elseif mode == "edge" or (mode == "icon" and rawget(painter, "thin") and rawget(painter, "outside")) then
				local tokens = rawget(E, "tokens")
				local skin = Table(tokens) and rawget(tokens, "skin")
				local token = mode == "edge" and "edgeThin" or "iconRing"
				if not Table(skin) or not Finite(rawget(skin, token)) or not Finite(rawget(metrics, "band"))
					or not Pin(function() return rawget(E, "tokens") end, { "skin" })
					or not Pin(function() return rawget(tokens, "skin") end, { token }) then return end
				if mode == "icon" then
					local pixel = rawget(E, "pixel")
					if not Finite(pixel) then return end
					pins[#pins + 1] = function() return Same(rawget(E, "pixel"), pixel) end
				end
				keys[#keys + 1] = "band"
			end
			if not Pin(function() return rawget(manifest, "data") end, { "metrics" })
				or not Pin(function() return rawget(data, "metrics") end, keys) then return end
		end
		local selection = selectionRead(requested == "Forever")
		if type(selection) ~= "function" then return end
		local function Current()
			if not Source() or not selection() then return false end
			for _, check in ipairs(pins) do if not check() then return false end end
			return true
		end
		if not Current() then return end
		local value = measure(E, object)
		if not Current() then return end
		return value, Current
	end
	function E:BindSurfaceMeasurementRead(source, accept)
		if binding then binding.invalid = true;return false end
		if not equal(self, E) or not Table(rawget(E, "modules")) or not Same(source, rawget(self.modules, "ActionBars")) or type(source) ~= "table" or type(accept) ~= "function" then return false end
		if owner then return equal(owner, source) and equal(consumer, accept) end
		local request = {};binding = request
		local ok = pcall(accept, measure, Read, Source)
		binding = nil
		if not ok or request.invalid then return false end
		owner, consumer = source, accept
		return true
	end
	sourceBind = E.BindSurfaceMeasurementRead
end

---------------------------------------------------------------------------
-- Surface list and report (Data/SkinSurfaces.lua): every place a skin may
-- draw on, and what each skin draws there. Plugins add their own rows.
---------------------------------------------------------------------------
local SURFACE_VIA = { kit = true, surface = true, graphics = true, windows = true, flag = true }
local surfaceRows, surfaceIndex = {}, {}

-- Add or replace a surface row. info: family, module, kind, part, via,
-- flag, compact, stock, original (see Data/SkinSurfaces.lua). Returns true
-- when added.
function E:RegisterSkinSurface(id, info)
	if type(id) ~= "string" or not id:match("^%a[%w%-]*$") or #id > 48 or type(info) ~= "table" then return false end
	local via = info.stock and "stock" or info.via
	if via ~= "stock" and not SURFACE_VIA[via] then return false end
	if via == "flag" and type(info.flag) ~= "string" then return false end
	if via ~= "stock" and via ~= "flag" and type(info.kind) ~= "string" then return false end
	local row = {
		id = id, family = info.family, module = info.module or "Core", kind = via ~= "stock" and info.kind or nil,
		part = info.part, via = via, flag = info.flag, compact = info.compact, stock = info.stock,
		original = info.original,
	}
	if surfaceIndex[id] then
		surfaceRows[surfaceIndex[id]] = row
	else
		surfaceRows[#surfaceRows + 1] = row
		surfaceIndex[id] = #surfaceRows
	end
	return true
end

-- Take a plugin's row off the list again. Returns true when it was there.
function E:UnregisterSkinSurface(id)
	local index = surfaceIndex[id]
	if not index then return false end
	table.remove(surfaceRows, index)
	surfaceIndex[id] = nil
	for i = index, #surfaceRows do surfaceIndex[surfaceRows[i].id] = i end
	return true
end

for _, info in ipairs(E.skinSurfaceList or {}) do E:RegisterSkinSurface(info.id, info) end

-- What one skin draws on a row: a recipe name, a unit graphics id, a flag
-- value, "legacy" (one of the five classic painters), "keyline" (a flat
-- keyline only), "stock" or "none".
local function SurfaceDraws(row, id)
	if row.via == "stock" then return "stock" end
	local m = E:SkinManifest(id)
	if row.via == "flag" then
		local value = m.flags and m.flags[row.flag]
		if value == nil or value == false then return "none" end
		return type(value) == "table" and "color" or tostring(value)
	end
	local recipe = m.recipes[row.kind]
	if row.via == "graphics" then return recipe or "MODERN" end
	if m.legacy or not m.data then return row.kind == "icon" and "keyline" or "legacy" end
	if PANEL_KINDS[row.kind] and not KINDS[recipe or ""] then recipe = row.kind == "window" and "framed" or "framedThin" end
	if not painters[recipe or ""] then return row.kind == "icon" and "keyline" or "none" end
	return recipe
end

-- The surface report: one row per surface (a copy), each with `skin` (the
-- skin it draws in: `id` when given, else its part's skin in this profile)
-- and `draws` (what that skin draws there). Machine readable: plain
-- strings and booleans only.
function E:SkinSurfaceReport(id)
	local report = {}
	for _, row in ipairs(surfaceRows) do
		local out = {}
		for k, v in pairs(row) do out[k] = v end
		out.skin = id and (manifests[id] and id or self:ArtStyle(id)) or self:SkinPart(row.part)
		out.draws = SurfaceDraws(row, out.skin)
		report[#report + 1] = out
	end
	return report
end

---------------------------------------------------------------------------
-- Samples (skin pickers, installer cards): a framed panel, "Aa" in the
-- title font, a bar strip in the skin's bar texture and, for skins with art,
-- a button frame and a portrait ring.
---------------------------------------------------------------------------
local samples = setmetatable({}, { __mode = "k" })

local function SampleParts(frame)
	local parts = samples[frame]
	if parts then return parts end
	parts = {}
	parts.title = frame:CreateFontString(nil, "OVERLAY")
	parts.title:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -6)
	parts.bar = frame:CreateTexture(nil, "ARTWORK", nil, 2)
	parts.bar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 8, 8)
	parts.bar:SetPoint("BOTTOMRIGHT", frame, "BOTTOM", 6, 8)
	parts.bar:SetHeight(6)
	parts.button = CreateFrame("Frame", nil, frame)
	parts.button:SetSize(18, 18)
	parts.button:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 6)
	parts.ring = frame:CreateTexture(nil, "ARTWORK", nil, 3)
	parts.ring:SetSize(22, 22)
	parts.ring:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, -5)
	samples[frame] = parts
	return parts
end

function E:PaintSkinSample(frame, id)
	if not CanPaint(frame) then return self:ArtStyle(id) end
	id = self:ArtStyle(id)
	local m = self:SkinManifest(id)
	self:AddBackdrop(frame)
	self:UpdateShadow(frame, false)
	if m.data then
		painters.framedThin(frame, m, {})
	else
		Skins.Release(frame)
		self.artStyles[id](frame)
	end
	local parts = SampleParts(frame)
	local font = self:SkinTitleFont(id)
	parts.title:SetFont(font, self.tokens.size.cardTitle, "")
	parts.title:SetText("Aa") -- no-L
	parts.title:SetTextColor(self:TokenColor("body"))
	parts.bar:SetTexture(self:SkinBarTexture(id))
	local accent = m.accent and { Hex(m.accent) } or self.media.accentColor
	parts.bar:SetVertexColor(accent[1], accent[2], accent[3], 1)
	if m.data then
		painters.frame(parts.button, m)
		parts.button:Show()
		parts.ring:SetTexture(m.data.files.ring)
		parts.ring:Show()
	else
		parts.button:Hide()
		parts.ring:Hide()
	end
	return id
end
