-- EldoUI unit-frame graphics: the frame art around EldoUI's unit frames
-- and party and raid frames, picked apart from their positions, sizes,
-- bars and portrait content.
--
--   Modern        EldoUI's flat look: draws nothing extra.
--   Vanilla       the skin's material behind the bars, its border round the
--                 frame and a round portrait ring.
--   Portrait Bars a shaped portrait frame (octagon, hexagon, shield or
--                 rounded square, as the skin draws it), a heavy divider
--                 between health and power and a shaded name strip.
--
-- Materials come from the skin in use (Data/SkinData.lua); a skin without
-- art of its own lends the graphics their home material. Party and raid
-- frames always get the compact recipe (material and a fine keyline, no
-- ring and nothing outside the frame), so dense raids keep their room.
-- Party frames that show portraits also get the portrait ring or bezel,
-- drawn inside the portrait's own square. Vanilla adds a crest to the
-- target and focus portrait of an elite (gold) or rare (silver) unit, as
-- the game reports it.
--
-- Texts a unit frame places outside its edge (a name on top, the level
-- above the corner) move out by the painted extent, so the border never
-- runs through them.
--
-- Rules: presentation only. The graphics never touch secure attributes,
-- sizes, frame points or hit insets, and nothing here is protected: every
-- piece is a texture on EldoUI's own art frames, created once per frame
-- and reused. No OnUpdate.
--
-- API (E.UnitGraphics; plugins may read it, providers are EldoUI's own):
--   UG:Register(id, provider)          add a provider { title, desc, order, home,
--                                      Apply(frame, ctx), Release(frame), Measure(frame) }
--   UG:Resolve(frame, db, kind)        id, requested, reason: what a frame draws and why
--   UG:Apply(frame, db, kind)          paint a frame (kind "unit" or "group"); repeat-safe
--   UG:Release(frame)                  hide every piece on a frame
--   UG:Measure(frame)                  { content, hit, paint } insets, hit always 0
--   UG:Metrics(db, kind[, unit])       the same insets from settings alone (no frame):
--                                      the most a frame with these settings paints
--   UG:Classify(frame, rank)           the unit's classification for the crest
--   UG:Values([saved[, follow]])       select values and order (an unknown saved id
--                                      is listed as not available)
--   UG:State(frame)                    id, pieces made, pieces shown, reason (read-only)
--
-- The health fill and its empty well, one rule for unit and group frames:
--   UG.BAR_LEVELS                      part levels over the frame's own level
--   UG:WellColor(mode, unit, custom[, classFile])  r, g, b, a of the empty part
--   UG:PaintWell(bar, mode, unit, custom[, classFile])  paints bar.bg (the well)
--   UG.DarkFillColor()                 r, g, b of the dark health fill
--   UG:DarkFill(bar)                   paints the dark health fill
local _, E = ...
local L = E.L

local UG = E.UnitGraphics or {}
E.UnitGraphics = UG

-- Look values of the graphics. compactHeight: unit frames lower than this
-- get the thin edge; maxOutset: the most any piece reaches outside a frame
-- (the original game art's plates excepted: they keep the classic shape);
-- strip: the name strip shade (share of the health bar, alpha); divider:
-- height of the Portrait Bars divider.
-- crestShare: crest size as a share of the portrait; crestMin: its least size.
E.tokens.unitGraphics = E.tokens.unitGraphics or {
	compactHeight = 40, maxOutset = 4, stripShare = 0.5, stripAlpha = 0.34, divider = 6, keylineLight = 0.55,
	crestShare = 0.42, crestMin = 10,
}

local providers, order = {}, {}
local owned = setmetatable({}, { __mode = "k" }) -- frame -> { id, kind, db, pieces... }
local FOLLOW, MODERN = "FOLLOW", "MODERN"
local SAME = "ALL" -- a frame's own pick that follows the "all frames" pick

local function Token(key) return E.tokens.unitGraphics[key] end

local function Tex(parent, layer, sub)
	local tex = parent:CreateTexture(nil, layer, nil, sub)
	if tex.SetSnapToPixelGrid then tex:SetSnapToPixelGrid(false) end
	if tex.SetTexelSnappingBias then tex:SetTexelSnappingBias(0) end
	return tex
end

local function Record(frame)
	local rec = owned[frame]
	if not rec then
		rec = {}
		owned[frame] = rec
	end
	return rec
end

local function Hide(region) if region then region:Hide() end end

---------------------------------------------------------------------------
-- Health fill and empty well (unit and group frames)
--
-- Every health bar is drawn in one order over its frame's own level, each
-- part on a level of its own (the game draws two frames on one level in no
-- fixed order, so the graphics' material could otherwise cover the well
-- or the fill):
--   art         +1  the frame and the graphics' material
--   well        +2  the empty part of the health bar (bar.bg)
--   fill        +3  the health bar itself
--   prediction  +4  incoming heals and shields, +5 your own heals
-- The well is always the opposite of the fill in lightness, so the lost
-- health reads at a glance in every skin and graphics choice:
--   a light fill (class, reaction, health gradient or own color) sits on a
--   dark well: the theme's panel color, a dark shade of the class color, or
--   the player's own color;
--   the dark fill (class colors off on group frames) sits on a lit well in
--   the member's class color (light gray for anyone without one).
-- Colors come from settings and the unit's class only; the health value
-- itself only ever goes into the status bar.
---------------------------------------------------------------------------
UG.BAR_LEVELS = { art = 1, well = 2, fill = 3, prediction = 4, predictionMine = 5 }

-- classShade: the dark class well's share of the class color; darkFill:
-- the dark health fill; litWell: the lit well for a unit without a class.
E.tokens.healthWell = E.tokens.healthWell or {
	classShade = 0.3, darkFill = { 0.12, 0.12, 0.13 }, litWell = { 0.62, 0.62, 0.62 },
}

local function WellToken(key) return E.tokens.healthWell[key] end

-- The class color of a player unit, or of a class file (sample frames).
local function ClassRGB(unit, classFile)
	if type(classFile) == "string" and E.GetClassColor then
		local r, g, b = E:GetClassColor(classFile)
		if r then return r, g, b end
	end
	if unit and E:UnitShowsClassColor(unit) then
		local ok, r, g, b = pcall(E.ClassColor, E, unit)
		if ok and r then return r, g, b end
	end
end

-- mode: "DEFAULT" (the theme's panel color), "CLASS" (dark class color),
-- "CUSTOM" (custom = { r, g, b }) or "LIT" (under the dark fill).
-- classFile stands in for the unit on sample frames.
function UG:WellColor(mode, unit, custom, classFile)
	if mode == "LIT" then
		local r, g, b = ClassRGB(unit, classFile)
		if r then return r, g, b, 1 end
		local c = WellToken("litWell")
		return c[1], c[2], c[3], 1
	end
	if mode == "CLASS" then
		local r, g, b = ClassRGB(unit, classFile)
		if r then
			local share = WellToken("classShade")
			return r * share, g * share, b * share, 1
		end
	end
	if mode == "CUSTOM" and type(custom) == "table" then
		return custom[1] or 0, custom[2] or 0, custom[3] or 0, 1
	end
	local r, g, b, a = unpack(E.media.backdropColor)
	return r, g, b, a or 1
end

function UG:PaintWell(bar, mode, unit, custom, classFile)
	local well = bar and bar.bg
	if not (well and well.SetBackdropColor) then return end
	well:SetBackdropColor(self:WellColor(mode, unit, custom, classFile))
end

function UG.DarkFillColor()
	local c = WellToken("darkFill")
	return c[1], c[2], c[3]
end

function UG:DarkFill(bar)
	if bar then bar:SetStatusBarColor(UG.DarkFillColor()) end
end

---------------------------------------------------------------------------
-- Heal prediction and absorbs, for unit and group frames alike: Blizzard's
-- calculator does the math and the clamping; the bars only receive its
-- results. "All incoming" sits under "mine", so nothing is ever
-- subtracted, and the health bar clips whatever would leave the frame.
-- One calculator serves every frame and is read with plain method calls,
-- so a health or heal update makes no new function or table.
---------------------------------------------------------------------------
local calculator
local function SetClampModes(calc)
	if Enum.UnitIncomingHealClampMode then calc:SetIncomingHealClampMode(Enum.UnitIncomingHealClampMode.MissingHealth) end
	if Enum.UnitDamageAbsorbClampMode then calc:SetDamageAbsorbClampMode(Enum.UnitDamageAbsorbClampMode.MissingHealth) end
	if Enum.UnitHealAbsorbClampMode then calc:SetHealAbsorbClampMode(Enum.UnitHealAbsorbClampMode.CurrentHealth) end
end

function UG.PredictionCalculator()
	if calculator == nil then
		calculator = false
		if CreateUnitHealPredictionCalculator then
			local ok, calc = pcall(CreateUnitHealPredictionCalculator)
			if ok and calc then
				calculator = calc
				pcall(SetClampModes, calc)
			end
		end
	end
	return calculator or nil
end

-- A unit's predicted amounts: true, then all incoming heals, your own
-- heals, absorbs, heal absorbs and Blizzard's overshield flag (any of them
-- nil when the client gives none). False without the calculator: the
-- caller reads the plain amounts instead.
function UG.ReadPrediction(unit)
	local calc = UG.PredictionCalculator()
	if not (calc and UnitGetDetailedHealPrediction) then return false end
	if not pcall(UnitGetDetailedHealPrediction, unit, "player", calc) then return true end
	local okHeals, all, mine = pcall(calc.GetIncomingHeals, calc)
	local okAbsorbs, absorb, overAbsorbed = pcall(calc.GetDamageAbsorbs, calc)
	local okHealAbsorbs, healAbsorb = pcall(calc.GetHealAbsorbs, calc)
	if not okHeals then all, mine = nil, nil end
	if not okAbsorbs then absorb, overAbsorbed = nil, nil end
	if not okHealAbsorbs then healAbsorb = nil end
	return true, all, mine, absorb, healAbsorb, overAbsorbed
end

-- One prediction bar: shown when its part is on, the health maximum is
-- known and the amount is a number. Amounts may be secret: only their type
-- is checked, never the value.
function UG.SetPredictionBar(bar, on, value, max)
	local show = (on and type(max) ~= "nil" and type(value) == "number") and true or false
	bar:SetShown(show)
	if show then
		pcall(bar.SetMinMaxValues, bar, 0, max)
		pcall(bar.SetValue, bar, value)
	end
end

---------------------------------------------------------------------------
-- Registry and resolution
---------------------------------------------------------------------------
function UG:Register(id, provider)
	if type(id) ~= "string" or not id:match("^%u[%u%d_]*$") or id == FOLLOW or id == SAME then return false end
	if type(provider) ~= "table" or type(provider.Apply) ~= "function" then return false end
	if not providers[id] then order[#order + 1] = id end
	providers[id] = provider
	table.sort(order, function(a, b) return (providers[a].order or 100) < (providers[b].order or 100) end)
	return true
end

function UG:Provider(id) return providers[id] end

local function ModuleDb(name)
	local module = E.modules and E.modules[name]
	return module and module.db
end

-- The skin graphics follow (the unit-frame part of the skin), its manifest.
local function SkinManifest()
	if not (E.SkinManifest and E.SkinPart) then return nil end
	return E:SkinManifest(E:SkinPart("unitframes"))
end

-- What the skin in use asks for (a FOLLOW pick).
local function FromSkin(kind)
	local m = SkinManifest()
	local recipe = m and m.recipes and m.recipes[kind == "group" and "groupframe" or "unitframe"]
	if providers[recipe] then return recipe end
	return MODERN
end

local function Contrast()
	return E.db and E.ArtStyle and E:ArtStyle() == "Contrast"
end

-- id, requested, reason. A frame's own pick wins, then the "all frames"
-- pick (party and raid frames: their module's pick), then the skin. High
-- contrast always draws Modern. An unknown id stays saved and draws Modern.
-- An orb draws Modern too: its ring is the orb's own.
function UG:Resolve(frame, db, kind)
	kind = kind == "group" and "group" or "unit"
	local requested
	if kind == "unit" then
		local own = type(db) == "table" and db.graphics or nil
		if type(own) == "string" and own ~= SAME then requested = own end
		if not requested then
			local uf = ModuleDb("UnitFrames")
			local all = uf and type(uf.allFrames) == "table" and uf.allFrames.graphics
			requested = type(all) == "string" and all or FOLLOW
		end
	else
		local gf = ModuleDb("GroupFrames")
		requested = gf and type(gf.graphics) == "string" and gf.graphics or FOLLOW
	end
	-- An orb (the Orbs unit-frame style, Core/Orb.lua) wears its own ring.
	local orb = kind == "unit" and (frame and frame.orbShape or not frame and type(db) == "table" and db.shape == "ORB")
	if orb then return MODERN, requested, "orb" end
	if Contrast() then return MODERN, requested, "contrast" end
	if requested == FOLLOW then return FromSkin(kind), requested, "skin" end
	if providers[requested] then return requested, requested, "picked" end
	return MODERN, requested, "unknown"
end

-- The art a provider draws with: the skin's own, else the provider's home art.
local function Materials(provider)
	local m = SkinManifest()
	if m and m.data then return m.data, m.id end
	local data = E.skinData and provider.home and E.skinData[provider.home]
	return data, provider.home
end

---------------------------------------------------------------------------
-- Pieces
---------------------------------------------------------------------------
local painters = function() return E.Skins and E.Skins.painters end

-- The material behind the bars: the skin's panel tile.
local function Fill(rec, parent, data, width, height, key)
	key = key or "fill"
	local tex = rec[key]
	if not tex then
		tex = Tex(parent, "BACKGROUND", 2)
		rec[key] = tex
	end
	local inset = E.pixel
	tex:ClearAllPoints()
	tex:SetPoint("TOPLEFT", parent, "TOPLEFT", inset, -inset)
	tex:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -inset, inset)
	if data.files.panel then
		local tile = E.tokens.skin and E.tokens.skin.tile or 64
		tex:SetTexture(data.files.panel, "REPEAT", "REPEAT")
		tex:SetTexCoord(0, math.max(0.01, (width or tile) / tile), 0, math.max(0.01, (height or tile) / tile))
		tex:SetVertexColor(1, 1, 1, 1)
	else
		local c = data.colors.panel
		tex:SetTexture(E.media.flat)
		tex:SetTexCoord(0, 1, 0, 1)
		tex:SetVertexColor(c[1], c[2], c[3], 1)
	end
	tex:Show()
end

-- A one-pixel keyline on the frame's own edge (inside it), the top line in
-- the skin's light edge color: the compact recipe, and the border when the
-- skin painters are missing.
local KEYS = { "top", "bottom", "left", "right" }
local function Keyline(rec, parent, data, field)
	field = field or "keys"
	rec[field] = rec[field] or {}
	local s = E.pixel
	local edge, light = data.colors.edge, data.colors.edgeLight
	for _, side in ipairs(KEYS) do
		local tex = rec[field][side]
		if not tex then
			tex = Tex(parent, "OVERLAY", 7)
			tex:SetTexture(E.media.flat)
			rec[field][side] = tex
		end
		tex:ClearAllPoints()
		tex:Show()
	end
	local k = rec[field]
	k.top:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
	k.top:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
	k.top:SetHeight(s)
	k.bottom:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, 0)
	k.bottom:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
	k.bottom:SetHeight(s)
	k.left:SetPoint("TOPLEFT", k.top, "BOTTOMLEFT")
	k.left:SetPoint("BOTTOMLEFT", k.bottom, "TOPLEFT")
	k.left:SetWidth(s)
	k.right:SetPoint("TOPRIGHT", k.top, "BOTTOMRIGHT")
	k.right:SetPoint("BOTTOMRIGHT", k.bottom, "TOPRIGHT")
	k.right:SetWidth(s)
	local mix = Token("keylineLight")
	k.top:SetVertexColor(edge[1] + (light[1] - edge[1]) * mix, edge[2] + (light[2] - edge[2]) * mix, edge[3] + (light[3] - edge[3]) * mix, 1)
	for _, side in ipairs({ "bottom", "left", "right" }) do k[side]:SetVertexColor(edge[1], edge[2], edge[3], 1) end
end

local function HideKeyline(rec, field)
	local keys = rec[field or "keys"]
	if not keys then return end
	for _, side in ipairs(KEYS) do Hide(keys[side]) end
end

---------------------------------------------------------------------------
-- Painted extent: how far each piece reaches outside what it wraps. Apply
-- and Metrics read the same numbers, so a fit check made from settings
-- matches what the frames draw.
---------------------------------------------------------------------------
-- The bars' border: the thin edge straddles the frame's edge, the full
-- border sits its outset outside it. Without the skin painters the border
-- is a keyline inside the frame.
local function BorderPaint(data, compact)
	if not painters() then return 0 end
	if compact then return math.floor(math.max(1, math.min(E.tokens.skin.edgeThin, data.metrics.band)) / 2) end
	return math.min(data.metrics.outset or 0, Token("maxOutset"))
end

local function PortraitSpec(data, shape)
	local metrics = data.metrics.portrait
	return shape == "ring" and metrics.ring or metrics.bezel
end

local function RingPaint(data, shape)
	return math.min(PortraitSpec(data, shape).outset or 0, Token("maxOutset"))
end

local function CrestPaint(data)
	return math.min(data.metrics.ornamentOutset or 0, Token("maxOutset"))
end

-- Frames that wear the crest of an elite or rare unit.
local CREST_UNITS = { target = true, focus = true }
-- The game's classification: the crest's tint key, or nil for none.
local RANKS = { elite = "elite", worldboss = "elite", rareelite = "rare", rare = "rare" }

local function PortraitMode(db)
	local mode = type(db) == "table" and db.portrait
	return (mode == "left" or mode == "right" or mode == "boxLeft" or mode == "boxRight") and mode or nil
end

-- The deco layer: over the bars, under the texts. Unit frames list their
-- part levels in the module's LEVELS table; other frames keep the deco
-- eight levels over the frame.
local function DecoLevel(rec)
	local uf = E.modules and E.modules.UnitFrames
	local levels = rec.kind ~= "group" and uf and uf.LEVELS
	return levels and levels.graphics or 8
end

local function Deco(rec, frame)
	if not rec.deco then
		rec.deco = CreateFrame("Frame", nil, frame.art)
		rec.deco:SetAllPoints(frame.art)
		rec.deco:EnableMouse(false)
		rec.edge = CreateFrame("Frame", nil, rec.deco)
		rec.edge:EnableMouse(false)
	end
	rec.deco:SetFrameLevel(frame:GetFrameLevel() + DecoLevel(rec))
	-- The border frame keeps the deco's level: a child keeps the level it
	-- was made with, which would tie it with the health bar.
	rec.edge:SetFrameLevel(rec.deco:GetFrameLevel())
	rec.deco:Show()
	return rec.deco
end

-- The skin's border round the bars: full 9-slice with its outset on big
-- frames, the thin edge on small ones. `from` is what it wraps.
local function Border(rec, data, artId, from, compact)
	local p = painters()
	local edge = rec.edge
	edge:ClearAllPoints()
	edge:SetAllPoints(from)
	edge:Show()
	HideKeyline(rec)
	rec.paint = BorderPaint(data, compact)
	if not p then
		Keyline(rec, edge, data)
		return
	end
	local m = { id = artId, data = data }
	if compact then
		p.edge(edge, m)
	else
		p.ring(edge, m, { square = true })
	end
end

-- The portrait ornament sits on a square centered in the portrait holder.
local function Square(rec, frame)
	local holder = frame.portraitHolder
	if not rec.square then
		rec.square = CreateFrame("Frame", nil, holder)
		rec.square:EnableMouse(false)
		holder:HookScript("OnSizeChanged", function() UG.LayoutPortrait(frame) end)
	end
	return rec.square
end

-- The ring or bezel frame: over the bars' border.
local function Medal(rec)
	if not rec.medal then
		rec.medal = CreateFrame("Frame", nil, rec.deco)
		rec.medal:EnableMouse(false)
		rec.ring = Tex(rec.medal, "ARTWORK", 3)
	end
	rec.medal:SetFrameLevel(rec.deco:GetFrameLevel() + 2)
	return rec.medal
end

local function Unmask(rec, frame)
	if rec.masked and frame.portrait and frame.portrait.RemoveMaskTexture then
		frame.portrait:RemoveMaskTexture(rec.mask)
	end
	rec.masked = nil
end

local function HideCrest(rec)
	Hide(rec.crestL)
	Hide(rec.crestR)
	rec.crestShown = nil
end

-- 3D models. A model takes no mask, so the art never lets one reach past
-- its opening: in a plate's round opening the model fills the circle's
-- inner square, beside a ring it fills the ring's square (the skin's
-- border goes round it), and without the art it sits where the picture
-- is. Inside an opening the camera frames the face a little wider
-- (ringFraming, Core/Portrait.lua), so the head sits in it.
E.tokens.unitGraphics.ringFraming = E.tokens.unitGraphics.ringFraming or 0.85

local function PlaceModel(rec, frame)
	local model = frame.model
	if not (model and frame.portrait) then return end
	model:ClearAllPoints()
	local where = rec and rec.modelIn
	if where == "circle" then
		local side = rec.circle / math.sqrt(2)
		model:SetPoint("CENTER", frame.portrait, "CENTER", 0, 0)
		model:SetSize(side, side)
	elseif where == "square" and rec.square then
		model:SetAllPoints(rec.square)
	else
		model:SetAllPoints(frame.portrait)
	end
	if E.Portrait and E.Portrait.Reframe then E.Portrait.Reframe(frame) end
end

local function HidePortrait(rec, frame)
	Unmask(rec, frame)
	Hide(rec.ring)
	Hide(rec.medal)
	Hide(rec.well)
	HideKeyline(rec, "medalKeys")
	HideCrest(rec)
	if rec.medalEdge and E.Skins then E.Skins.Release(rec.medalEdge) end
	rec.portrait, rec.roundOpening = nil, nil
	if rec.modelIn == "square" then
		rec.modelIn = nil
		PlaceModel(rec, frame)
	end
end

-- Square, mask and ornament size from the holder's size (runs again when it
-- changes). The mask matches the opening of the ring art, a little under its
-- band so no gap shows.
function UG.LayoutPortrait(frame)
	local rec = owned[frame]
	local p = rec and rec.portrait
	if not p then return end
	local holder = frame.portraitHolder
	local w, h = holder:GetWidth(), holder:GetHeight()
	if type(w) ~= "number" or type(h) ~= "number" or w <= 0 or h <= 0 then return end
	local s = math.max(math.min(w, h) - 2 * p.px, 1)
	rec.square:ClearAllPoints()
	rec.square:SetPoint("CENTER", holder, "CENTER", 0, 0)
	rec.square:SetSize(s, s)
	if rec.masked then
		local outer = s + 2 * p.outset
		local opening = outer * p.opening + 1
		rec.mask:ClearAllPoints()
		rec.mask:SetPoint("CENTER", rec.square, "CENTER", 0, 0)
		rec.mask:SetSize(math.min(opening, s), math.min(opening, s))
	end
	-- The crest keeps its share of the portrait.
	if rec.crestShown and rec.crestL and rec.crestL:IsShown() then
		local size = math.max(Token("crestMin"), math.floor(s * Token("crestShare")))
		rec.crestL:SetSize(size, size)
		rec.crestR:SetSize(size, size)
	end
end

-- The portrait ornament: ring (Vanilla) or bezel (Portrait Bars) around a
-- 2D picture or class icon, masked to its opening; a square border around a
-- 3D model, which a mask cannot shape. inside: the ornament stays within
-- the portrait's square (party frames): no outset, and a keyline round a
-- model in place of the skin's border.
local function Portrait(rec, frame, db, data, artId, shape, inside)
	local mode = PortraitMode(db)
	local box = mode == "boxLeft" or mode == "boxRight"
	if not (frame.portraitHolder and frame.portrait and mode) then
		return HidePortrait(rec, frame)
	end
	local spec = PortraitSpec(data, shape)
	local file = shape == "ring" and data.files.ring or data.files.portrait
	local maskFile = E.skinMasks and E.skinMasks[shape == "ring" and "round" or spec.shape]
	-- The picture shown now: a model while the unit shows one (a unit out
	-- of view shows its 2D picture, Core/Portrait.lua).
	local model = frame.model ~= nil and (frame.portraitMode == "3D" or (frame.portraitMode == nil and db.portraitStyle == "3D"))
	local holder = frame.portraitHolder
	local square = Square(rec, frame)
	local medal = Medal(rec)
	medal:ClearAllPoints()
	medal:SetAllPoints(square)
	medal:Show()
	local outset = inside and 0 or RingPaint(data, shape)
	local px = box and E:PixelFor(holder) or 0
	rec.portrait = { px = px, outset = outset, opening = (spec.opening or spec.size) / spec.size }
	rec.paint = math.max(rec.paint or 0, outset)
	-- The well behind a shaped picture: the skin's material.
	if box then
		Fill(rec, holder, data, nil, nil, "well")
		local tile = E.tokens.skin and E.tokens.skin.tile or 64
		rec.well:SetTexCoord(0, (db.portraitWidth or 0) > 0 and db.portraitWidth / tile or db.height / tile, 0, db.height / tile)
	else
		Hide(rec.well)
	end
	HideKeyline(rec, "medalKeys")
	rec.roundOpening = (file and maskFile and frame.portrait.AddMaskTexture) and true or nil
	rec.modelIn = model and "square" or nil
	PlaceModel(rec, frame)
	if model or not rec.roundOpening then
		-- A model (or a client without masks): the skin's border round it.
		Unmask(rec, frame)
		rec.ring:Hide()
		local p = painters()
		if inside then
			if rec.medalEdge and E.Skins then E.Skins.Release(rec.medalEdge) end
			Keyline(rec, medal, data, "medalKeys")
		elseif p then
			rec.medalEdge = rec.medalEdge or CreateFrame("Frame", nil, medal)
			rec.medalEdge:SetAllPoints(medal)
			rec.medalEdge:Show()
			p.ring(rec.medalEdge, { id = artId, data = data }, { square = true })
		end
	else
		if rec.medalEdge and E.Skins then E.Skins.Release(rec.medalEdge) end
		if not rec.mask then rec.mask = holder:CreateMaskTexture() end
		rec.mask:SetTexture(maskFile, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		if not rec.masked then
			frame.portrait:AddMaskTexture(rec.mask)
			rec.masked = true
		end
		rec.ring:SetTexture(file)
		-- Mirrored with the portrait's side, so the target faces the player.
		if mode == "right" or mode == "boxRight" then rec.ring:SetTexCoord(1, 0, 0, 1) else rec.ring:SetTexCoord(0, 1, 0, 1) end
		rec.ring:SetVertexColor(1, 1, 1, 1)
		rec.ring:ClearAllPoints()
		rec.ring:SetPoint("TOPLEFT", medal, "TOPLEFT", -outset, outset)
		rec.ring:SetPoint("BOTTOMRIGHT", medal, "BOTTOMRIGHT", outset, -outset)
		rec.ring:Show()
	end
	UG.LayoutPortrait(frame)
end

-- Portrait Bars: the heavy divider on the seam between health and an
-- attached power bar (three slices of divider.tga), and the name strip.
local function Divider(rec, frame, db, data)
	local power = frame.power
	local attached = (db.powerStyle == nil or db.powerStyle == "ATTACHED") and (db.powerHeight or 0) > 0
	if not (power and attached and data.files.divider and power:GetParent() == frame.art) then
		return Hide(rec.divider)
	end
	local h = Token("divider")
	if not rec.divider then
		rec.divider = CreateFrame("Frame", nil, power)
		rec.divider:EnableMouse(false)
		rec.divL, rec.divC, rec.divR = Tex(rec.divider, "OVERLAY"), Tex(rec.divider, "OVERLAY"), Tex(rec.divider, "OVERLAY")
	end
	local div = rec.divider
	div:ClearAllPoints()
	div:SetPoint("LEFT", power, "TOPLEFT", 0, 0)
	div:SetPoint("RIGHT", power, "TOPRIGHT", 0, 0)
	div:SetHeight(h)
	div:SetFrameLevel(power:GetFrameLevel() + 1)
	local slices = data.metrics.divider and data.metrics.divider.slices or { 0, 112, 144, 256 }
	local a, b = slices[2] / slices[4], slices[3] / slices[4]
	for _, tex in ipairs({ rec.divL, rec.divC, rec.divR }) do
		tex:SetTexture(data.files.divider)
		tex:SetVertexColor(1, 1, 1, 1)
		tex:ClearAllPoints()
	end
	rec.divC:SetPoint("CENTER", div, "CENTER", 0, 0)
	rec.divC:SetSize(h * (slices[3] - slices[2]) / 16, h)
	rec.divC:SetTexCoord(a, b, 0, 1)
	rec.divL:SetPoint("TOPLEFT", div, "TOPLEFT")
	rec.divL:SetPoint("BOTTOMRIGHT", rec.divC, "BOTTOMLEFT")
	rec.divL:SetTexCoord(0, a, 0, 1)
	rec.divR:SetPoint("TOPLEFT", rec.divC, "TOPRIGHT")
	rec.divR:SetPoint("BOTTOMRIGHT", div, "BOTTOMRIGHT")
	rec.divR:SetTexCoord(b, 1, 0, 1)
	div:Show()
end

-- A shade over the top of the health bar, under the name: the name reads
-- on any bar color, and the bar gets the strip of a portrait frame.
local function Strip(rec, frame, data)
	if not frame.health then return end
	if not rec.strip then rec.strip = Tex(rec.deco, "BACKGROUND", 1) end
	local strip = rec.strip
	strip:SetTexture(E.media.flat)
	strip:ClearAllPoints()
	strip:SetPoint("TOPLEFT", frame.health, "TOPLEFT", 0, 0)
	strip:SetPoint("TOPRIGHT", frame.health, "TOPRIGHT", 0, 0)
	strip:SetPoint("BOTTOM", frame.health, "TOP", 0, -math.max(2, ((frame.db and frame.db.height) or 20) * Token("stripShare") * 0.5))
	local c = data.colors.panel
	if strip.SetGradient and CreateColor then
		strip:SetVertexColor(1, 1, 1, 1)
		strip:SetGradient("VERTICAL", CreateColor(c[1], c[2], c[3], 0), CreateColor(c[1], c[2], c[3], Token("stripAlpha")))
	else
		strip:SetVertexColor(c[1], c[2], c[3], Token("stripAlpha") / 2)
	end
	strip:Show()
end

-- The crest (Vanilla, target and focus): the skin's corner ornament on the
-- two top corners of the portrait, and the ring, in gold for an elite or
-- boss and silver for a rare. Drawn only while the game names the rank;
-- it reaches at most the skin's ornament outset out of the portrait.
local function CrestTint(rank)
	if rank == "elite" then return E.tokens.text.gold end
	return E.tokens.money.silver
end

local function Crest(rec, data)
	local rank = rec.wantsCrest and rec.portrait and rec.medal and RANKS[rec.rank or ""]
	local corner = data and data.files and data.files.corner
	rec.paint = rec.basePaint or rec.paint or 0
	if not rank then
		HideCrest(rec)
		if rec.ring then rec.ring:SetVertexColor(1, 1, 1, 1) end
		return
	end
	local c = CrestTint(rank)
	if rec.ring then rec.ring:SetVertexColor(c[1], c[2], c[3], 1) end
	if not corner then
		HideCrest(rec)
		rec.crestShown = rank
		return
	end
	rec.crestShown = rank
	if not rec.crestL then
		rec.crestL, rec.crestR = Tex(rec.medal, "OVERLAY", 4), Tex(rec.medal, "OVERLAY", 4)
	end
	local o = CrestPaint(data)
	local w = rec.square and rec.square:GetWidth() or 0
	local size = math.max(Token("crestMin"), math.floor((type(w) == "number" and w or 0) * Token("crestShare")))
	for _, tex in ipairs({ rec.crestL, rec.crestR }) do
		tex:SetTexture(corner)
		tex:SetVertexColor(c[1], c[2], c[3], 1)
		tex:SetSize(size, size)
		tex:ClearAllPoints()
		tex:Show()
	end
	rec.crestL:SetTexCoord(0, 1, 0, 1)
	rec.crestL:SetPoint("TOPLEFT", rec.medal, "TOPLEFT", -o, o)
	rec.crestR:SetTexCoord(1, 0, 0, 1)
	rec.crestR:SetPoint("TOPRIGHT", rec.medal, "TOPRIGHT", o, o)
	rec.paint = math.max(rec.paint, o)
end

-- Texts placed outside the frame's edge (Modules/UnitFrames.lua lists them
-- in frame.graphicsLift as { text, point, relativeTo, relativePoint, x, y,
-- direction }) move out by the painted extent; with nothing painted they
-- sit where the frame's settings put them.
local function Lift(frame, rec)
	local list = frame.graphicsLift
	if type(list) ~= "table" then return end
	local lift = rec and rec.id ~= MODERN and (rec.lift or rec.paint) or 0
	for _, item in ipairs(list) do
		item[1]:ClearAllPoints()
		item[1]:SetPoint(item[2], item[3], item[4], item[5], item[6] + item[7] * lift)
	end
end

-- Hide every piece a frame owns (the frame keeps its pieces for later).
local HidePlate -- the original plates (below)
local function ReleasePieces(rec, frame)
	HidePlate(rec, frame)
	Hide(rec.fill)
	HideKeyline(rec)
	if rec.edge and E.Skins then E.Skins.Release(rec.edge) end
	Hide(rec.edge)
	HidePortrait(rec, frame)
	Hide(rec.divider)
	Hide(rec.strip)
	Hide(rec.deco)
	rec.paint, rec.basePaint = 0, 0
end

---------------------------------------------------------------------------
-- Providers
---------------------------------------------------------------------------
-- The bars' border: the whole frame, or the bars only beside a portrait box
-- (the ring or bezel frames the box).
local function BarsArea(rec, frame, db)
	if not rec.bars then
		rec.bars = CreateFrame("Frame", nil, rec.deco)
		rec.bars:EnableMouse(false)
	end
	local bars = rec.bars
	bars:ClearAllPoints()
	local holder = frame.portraitHolder
	if holder and db.portrait == "boxLeft" then
		bars:SetPoint("TOPLEFT", holder, "TOPRIGHT", 0, 0)
		bars:SetPoint("BOTTOMRIGHT", frame.art, "BOTTOMRIGHT", 0, 0)
	elseif holder and db.portrait == "boxRight" then
		bars:SetPoint("TOPLEFT", frame.art, "TOPLEFT", 0, 0)
		bars:SetPoint("BOTTOMRIGHT", holder, "BOTTOMLEFT", 0, 0)
	else
		bars:SetAllPoints(frame.art)
	end
	return bars
end

-- A party section's portrait pick in the unit-frame terms Portrait reads.
local function PartyPortrait(rec, db)
	local own = rec.partyDb or {}
	rec.partyDb = own
	own.portrait = db.portraitBox and "boxLeft" or "left"
	own.portraitStyle = db.portrait == "3D" and "3D" or "2D"
	own.height, own.portraitWidth = db.height, 0
	return own
end

local function Framed(shape, extras, crest)
	return function(frame, ctx)
		local rec, data = ctx.rec, ctx.data
		if ctx.kind == "group" then
			-- Compact: material and keyline on the frame's own edge; a
			-- party portrait gets its ring or bezel inside its square.
			Fill(rec, frame.art, data, ctx.width, ctx.height)
			Keyline(rec, frame.art, data)
			rec.paint, rec.basePaint, rec.wantsCrest = 0, 0, nil
			if ctx.party and frame.portraitShown then
				Deco(rec, frame)
				Hide(rec.edge)
				Portrait(rec, frame, PartyPortrait(rec, ctx.db), data, ctx.artId, shape, true)
			else
				HidePortrait(rec, frame)
				Hide(rec.deco)
			end
			return
		end
		Deco(rec, frame)
		Fill(rec, frame.art, data, ctx.width, ctx.height)
		Border(rec, data, ctx.artId, BarsArea(rec, frame, ctx.db), ctx.compact)
		Portrait(rec, frame, ctx.db, data, ctx.artId, shape)
		rec.basePaint = rec.paint
		rec.wantsCrest = crest and not ctx.compact and CREST_UNITS[frame.unit or ""] or nil
		Crest(rec, data)
		if extras and not ctx.compact then
			Divider(rec, frame, ctx.db, data)
			Strip(rec, frame, data)
		else
			Hide(rec.divider)
			Hide(rec.strip)
		end
	end
end

UG:Register(MODERN, {
	order = 10, title = "Modern (flat)",
	desc = "EldoUI's flat frames: nothing drawn round them.",
	Apply = function() end,
})
UG:Register("VANILLA", {
	order = 20, title = "Vanilla", home = "VANILLA", shape = "ring", crest = true,
	desc = "The skin's material behind the bars, its border round the frame and a round portrait ring.",
	Apply = Framed("ring", false, true),
})
UG:Register("PORTRAITBARS", {
	order = 30, title = "Portrait Bars", home = "FORGED", shape = "bezel",
	desc = "A shaped portrait frame, a heavy divider between health and power and a shaded name strip.",
	Apply = Framed("bezel", true),
})

---------------------------------------------------------------------------
-- Original game art (the Vanilla Original skin): the classic plates of the
-- game client itself (E:SetOriginalArt, Core/Media.lua), drawn round
-- EldoUI's own bars. The plate's bar tracks take the frame's health and
-- power bars, so the plate is scaled by the frame's height and its middle
-- stretches with the bars' width; the plate's portrait circle takes the
-- frame's portrait picture. The frame itself keeps its size, points and
-- mover, so it moves and resizes like any frame. A frame far off the
-- classic proportions (or a unit with no classic plate) draws the Vanilla
-- look instead, and party and raid frames always get the compact recipe.
---------------------------------------------------------------------------
local ORIGINAL = "VANILLA_ORIGINAL"
-- The plate a unit wears (the frames the classic game had: focus came
-- later and wears the Vanilla look), and the target's plate per
-- classification (the game's own answer, as the classic target frame swaps
-- its whole sheet).
local PLATES = { player = "plate-player", target = "plate-target", targettarget = "plate-tot", pet = "plate-pet" }
local PLATE_RANKS = { elite = "plate-elite", worldboss = "plate-elite", rare = "plate-rare", rareelite = "plate-rareelite" }
local RANKED_PLATES = { ["plate-target"] = true }
-- Scale of the plate (frame height over the classic track height) and the
-- bars' width over the classic track width that still carry the art.
E.tokens.unitGraphics.originalScale = E.tokens.unitGraphics.originalScale or { 0.6, 1.6 }
E.tokens.unitGraphics.originalWidth = E.tokens.unitGraphics.originalWidth or { 0.75, 2.5 }
-- A portrait box's width over the plate's portrait side that still carries
-- the art (the plate's portrait circle takes the box's place).
E.tokens.unitGraphics.originalBox = E.tokens.unitGraphics.originalBox or { 0.75, 1.33 }

-- How far a frame's bars sit in from its edges past the 1-pixel inset, as
-- the unit frames lay them out from the settings: { left, right, top,
-- bottom }. A portrait box or a portrait beside the bars takes its side,
-- the info panel its edge.
local function BarsRoom(db)
	local px = E.pixel
	local width, height = db.width or 0, db.height or 0
	local room = { 0, 0, 0, 0 }
	local info = type(db.infoPanel) == "table" and db.infoPanel or {}
	if info.enabled then
		local band = math.max(info.height or 14, 4) + px
		if info.position == "TOP" then room[3] = band else room[4] = band end
	end
	local mode = PortraitMode(db)
	if mode == "boxLeft" or mode == "boxRight" then
		local box = (db.portraitWidth or 0) > 0 and db.portraitWidth or height
		room[mode == "boxLeft" and 1 or 2] = math.max(math.min(box, width - 24), 8) - px
	elseif mode == "left" or mode == "right" then
		local size = math.max(height - room[3] - room[4] - 2 * px, 1)
		room[mode == "left" and 1 or 2] = size + px
	end
	return room
end

-- The plate slot, its scale and the bars' room for a frame's settings, or
-- nil when the unit has no classic plate, the frame has no portrait box for
-- the plate's circle or it is too far off its proportions. The scale is the bars' height (the frame less its info
-- panel) over the classic track height.
local function PlateFor(unit, db)
	local slot = PLATES[unit or ""]
	local row = slot and E.OriginalArt and E:OriginalArt(slot)
	local anatomy = row and row.anatomy
	if not anatomy or type(db) ~= "table" then return nil end
	local room = BarsRoom(db)
	-- The bars' real height: the frame less its info panel and the pixel
	-- the bars keep from the frame's top and bottom edge. The art scales
	-- by it, the same across and down, so its ring stays round on the
	-- portrait circle.
	local height = (db.height or 0) - room[3] - room[4] - 2 * E.pixel
	if height <= 0 then return nil end
	local scale = height / anatomy.bars[2]
	local range = Token("originalScale")
	if scale < range[1] or scale > range[2] then return nil end
	if (db.width or 0) > 0 then
		local share = (db.width - room[1] - room[2]) / (anatomy.bars[1] * scale)
		local widths = Token("originalWidth")
		if share < widths[1] or share > widths[2] then return nil end
	end
	-- The plate is built round its portrait circle: it needs a portrait box
	-- where the circle sits, about as wide as that side of the plate. A
	-- frame without one, or with any other box, is a design of its own.
	local mode = PortraitMode(db)
	if mode ~= "boxLeft" and mode ~= "boxRight" then return nil end
	local side = mode == "boxLeft" and 1 or 2
	local share = (room[side] + E.pixel) / (anatomy.outset[side] * scale)
	local boxes = Token("originalBox")
	if share < boxes[1] or share > boxes[2] then return nil end
	return slot, scale, anatomy, room
end

-- How far a plate reaches past the bars (room nil) or past the frame
-- (room from PlateFor): { left, right, top, bottom }. The bars sit a pixel
-- in from the frame's edges, and the room the frame keeps round them (a
-- portrait box, the name panel) holds that much more of the plate.
local function PlatePaint(anatomy, scale, room)
	local o = anatomy.outset
	local paint = {}
	for side = 1, 4 do
		paint[side] = room and math.max(o[side] * scale - room[side] - E.pixel, 0) or o[side] * scale
	end
	return paint
end

-- The portrait box and the info panel keep their place under a plate but
-- draw no box of their own: the plate is the frame's art there.
local function HasBox(box)
	return box and box.GetBackdrop and box:GetBackdrop() ~= nil
end

-- The boxes give up their backdrop under the plate, not only its colors:
-- with no backdrop there is nothing a later repaint could bring back.
local function ClearBoxes(rec, frame)
	for _, box in ipairs({ frame.portraitHolder, frame.infoPanel }) do
		if HasBox(box) then
			box:SetBackdropColor(0, 0, 0, 0)
			box:SetBackdropBorderColor(0, 0, 0, 0)
			box:SetBackdrop(nil)
			rec.boxesCleared = true
		end
	end
end

local function RestoreBoxes(rec, frame)
	if not rec.boxesCleared then return end
	rec.boxesCleared = nil
	local db = type(rec.db) == "table" and rec.db or {}
	local holder = frame.portraitHolder
	if holder and (db.portrait == "boxLeft" or db.portrait == "boxRight") then E:SetTemplate(holder) end
	local panel, info = frame.infoPanel, type(db.infoPanel) == "table" and db.infoPanel or {}
	if panel and info.enabled then E:SetTemplate(panel, info.transparent) end
end

-- Does the plate own the frame's boxes right now (the unit frames leave
-- them without a backdrop then)?
function UG:OwnsBoxes(frame)
	local rec = frame and owned[frame]
	return rec ~= nil and rec.boxesCleared == true
end

local function RestorePortrait(rec, frame)
	if not rec.portraitMoved then return end
	rec.portraitMoved = nil
	local holder = frame.portraitHolder
	if not holder then return end
	local mode = PortraitMode(rec.db)
	local px = (mode == "boxLeft" or mode == "boxRight") and E:PixelFor(holder) or 0
	frame.portrait:ClearAllPoints()
	frame.portrait:SetPoint("TOPLEFT", holder, "TOPLEFT", px, -px)
	frame.portrait:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", -px, px)
	if rec.modelIn == "circle" then rec.modelIn = nil end
	PlaceModel(rec, frame)
end

function HidePlate(rec, frame)
	Hide(rec.plate)
	for _, tex in ipairs(rec.plateCols or {}) do tex:Hide() end
	Hide(rec.hole)
	Hide(rec.levelSpot)
	rec.levelScale = nil
	RestorePortrait(rec, frame)
	RestoreBoxes(rec, frame)
	rec.plateSlot, rec.lift, rec.paintBox = nil, nil, nil
end

-- The plate's three columns: the part left of the bar tracks, the tracks
-- (stretched with the bars) and the part right of them.
local function PaintPlate(rec, slot)
	if rec.baseSlot and slot ~= rec.baseSlot and E:OriginalArtState(slot) == "missing" then slot = rec.baseSlot end
	local row = E:OriginalArt(slot)
	local a, c = row.anatomy, row.coords or { 0, 1, 0, 1 }
	local total = a.outset[1] + a.bars[1] + a.outset[2]
	local edges = { 0, a.outset[1], a.outset[1] + a.bars[1], total }
	for index, tex in ipairs(rec.plateCols) do
		E:SetOriginalArt(tex, slot)
		local u0 = c[1] + (c[2] - c[1]) * edges[index] / total
		local u1 = c[1] + (c[2] - c[1]) * edges[index + 1] / total
		tex:SetTexCoord(u0, u1, c[3], c[4])
		tex:SetVertexColor(1, 1, 1, 1)
		tex:Show()
	end
	rec.plateSlot = slot
end

-- The plate on a frame: slot, scale, anatomy and room from PlateFor.
local function Plate(rec, frame, ctx, slot, scale, anatomy, room)
	local deco = Deco(rec, frame)
	if rec.edge and E.Skins then E.Skins.Release(rec.edge) end
	Hide(rec.edge)
	Hide(rec.fill)
	HideKeyline(rec)
	HidePortrait(rec, frame)
	Hide(rec.divider)
	Hide(rec.strip)
	rec.wantsCrest = nil
	if not rec.plate then
		rec.plate = CreateFrame("Frame", nil, deco)
		rec.plate:EnableMouse(false)
		rec.plateCols = { Tex(rec.plate, "ARTWORK", 1), Tex(rec.plate, "ARTWORK", 1), Tex(rec.plate, "ARTWORK", 1) }
	end
	local plate = rec.plate
	plate:SetFrameLevel(deco:GetFrameLevel())
	-- The tracks: the health bar on top, the attached power bar under it.
	local top = frame.health or frame.art
	local bottom = top
	local power = frame.power
	if power and power:GetParent() == frame.art and power:IsShown() and (ctx.db.powerHeight or 0) > 0 then bottom = power end
	local reach = PlatePaint(anatomy, scale)
	plate:ClearAllPoints()
	plate:SetPoint("TOPLEFT", top, "TOPLEFT", -reach[1], reach[3])
	plate:SetPoint("BOTTOMRIGHT", bottom, "BOTTOMRIGHT", reach[2], -reach[4])
	local cols = rec.plateCols
	for _, tex in ipairs(cols) do tex:ClearAllPoints() end
	cols[1]:SetPoint("TOPLEFT", plate, "TOPLEFT")
	cols[1]:SetPoint("BOTTOMLEFT", plate, "BOTTOMLEFT")
	cols[1]:SetWidth(reach[1])
	cols[3]:SetPoint("TOPRIGHT", plate, "TOPRIGHT")
	cols[3]:SetPoint("BOTTOMRIGHT", plate, "BOTTOMRIGHT")
	cols[3]:SetWidth(reach[2])
	cols[2]:SetPoint("TOPLEFT", cols[1], "TOPRIGHT")
	cols[2]:SetPoint("BOTTOMRIGHT", cols[3], "BOTTOMLEFT")
	rec.baseSlot = slot
	PaintPlate(rec, RANKED_PLATES[slot] and PLATE_RANKS[rec.rank or ""] or slot)
	plate:Show()
	ClearBoxes(rec, frame)
	-- The portrait circle: a dark well, and the frame's portrait picture in it.
	local p = anatomy.portrait
	local size = p[3] * scale
	if not rec.hole then rec.hole = Tex(frame.art, "BACKGROUND", 3) end
	local hole = rec.hole
	-- Round, like the opening: no corner shows where the art is open.
	hole:SetTexture(E.skinMasks and E.skinMasks.round or E.media.flat)
	local well = ctx.colors.barBg
	hole:SetVertexColor(well[1], well[2], well[3], 1)
	-- From the bars' edge on the circle's side: the art's middle stretches
	-- with the bars, its sides keep the plate's scale.
	local fromRight = p[1] >= anatomy.bars[1]
	local x = fromRight and (p[1] - anatomy.bars[1]) * scale or p[1] * scale
	local corner = fromRight and "TOPRIGHT" or "TOPLEFT"
	hole:ClearAllPoints()
	hole:SetPoint("TOPLEFT", top, corner, x, p[2] * scale)
	hole:SetSize(size, size)
	hole:Show()
	if frame.portraitShown and PortraitMode(ctx.db) and frame.portrait then
		frame.portrait:ClearAllPoints()
		frame.portrait:SetPoint("TOPLEFT", top, corner, x, p[2] * scale)
		frame.portrait:SetSize(size, size)
		rec.portraitMoved = true
		rec.modelIn, rec.circle = "circle", size
		PlaceModel(rec, frame)
	else
		RestorePortrait(rec, frame)
	end
	-- The small level circle under the portrait (player and target): an
	-- empty frame on its center and size, for the unit frames to put the
	-- level and the classic state icons in (UG:LevelSpot).
	local spot = anatomy.level
	if spot then
		if not rec.levelSpot then
			rec.levelSpot = CreateFrame("Frame", nil, plate)
			rec.levelSpot:EnableMouse(false)
		end
		local fromRightSpot = spot[1] >= anatomy.bars[1]
		local sx = fromRightSpot and (spot[1] - anatomy.bars[1]) * scale or spot[1] * scale
		rec.levelSpot:ClearAllPoints()
		rec.levelSpot:SetPoint("CENTER", top, fromRightSpot and "TOPRIGHT" or "TOPLEFT", sx, spot[2] * scale)
		rec.levelSpot:SetSize(spot[3] * scale, spot[3] * scale)
		rec.levelSpot:Show()
		rec.levelScale = scale
	else
		Hide(rec.levelSpot)
		rec.levelScale = nil
	end
	-- Texts over the plate stay where the frame's settings put them: the
	-- plate has its own name area above the tracks.
	local paint = PlatePaint(anatomy, scale, room)
	rec.paintBox = paint
	rec.paint = math.max(paint[1], paint[2], paint[3], paint[4])
	rec.basePaint, rec.lift = rec.paint, 0
end

local vanillaLook = Framed("ring", false, true)

UG:Register(ORIGINAL, {
	order = 25, title = "Original game art", home = "VANILLA", shape = "ring", crest = true, original = true,
	desc = "The game's own classic frames round the bars: portrait circle, name area and the elite dragon. Made for the Classic frames style (thin bars at the classic proportions beside a portrait box as wide as the plate's portrait side); other frames, and party and raid frames, get the Vanilla look.",
	Apply = function(frame, ctx)
		local rec = ctx.rec
		local slot, scale, anatomy, room
		if ctx.kind == "unit" then slot, scale, anatomy, room = PlateFor(frame.unit, ctx.db) end
		local missing = slot and E:OriginalArtState(slot) == "missing" and not E:OriginalArt(slot).shipped
		if slot and not missing then
			Plate(rec, frame, ctx, slot, scale, anatomy, room)
			rec.reason = "original"
			return
		end
		HidePlate(rec, frame)
		vanillaLook(frame, ctx)
		rec.reason = ctx.kind == "group" and "compact" or (missing and "missing")
			or (PLATES[frame.unit or ""] and "proportions" or "noplate")
	end,
	-- The target's sheet follows its classification.
	Classify = function(frame, rec)
		if not (rec.plateSlot and rec.baseSlot and RANKED_PLATES[rec.baseSlot]) then return false end
		local slot = PLATE_RANKS[rec.rank or ""] or rec.baseSlot
		if slot ~= rec.plateSlot then PaintPlate(rec, slot) end
		return true
	end,
	-- The extent from settings: the plate's, or the Vanilla look's.
	Metrics = function(db, kind, unit)
		if kind ~= "unit" then return nil end
		local slot, scale, anatomy, room = PlateFor(unit, db)
		if slot and not (E:OriginalArtState(slot) == "missing" and not E:OriginalArt(slot).shipped) then
			return PlatePaint(anatomy, scale, room)
		end
	end,
})

---------------------------------------------------------------------------
-- Apply, release, measure
---------------------------------------------------------------------------
-- The level circle a frame's plate draws now: its size and plate scale,
-- or nil without one (to see whether an Apply moved it).
local function SpotKey(rec)
	local spot = rec and rec.levelScale and rec.levelSpot
	if not spot then return nil end
	return ("%.3f:%.3f"):format(spot:GetWidth(), rec.levelScale)
end

local ApplyNow
function UG:Apply(frame, db, kind)
	if type(frame) ~= "table" or not frame.art then return MODERN end
	local before = SpotKey(owned[frame])
	local id, requested, reason = ApplyNow(self, frame, db, kind)
	-- The level circle came, went or changed size: the frame places what it
	-- shows there again (Modules/UnitFrames.lua).
	if SpotKey(owned[frame]) ~= before and type(frame.OnLevelSpot) == "function" then frame:OnLevelSpot() end
	return id, requested, reason
end

function ApplyNow(self, frame, db, kind)
	kind = kind == "group" and "group" or "unit"
	local id, requested, reason = self:Resolve(frame, db, kind)
	local provider = providers[id]
	local data, artId
	if id ~= MODERN then
		data, artId = Materials(provider)
		if not (data and data.files and data.metrics) then id, reason, provider = MODERN, "noart", providers[MODERN] end
	end
	local rec = owned[frame]
	if id == MODERN then
		-- Modern draws nothing: a frame that never drew keeps no record.
		if rec then
			ReleasePieces(rec, frame)
			rec.id, rec.kind, rec.db, rec.reason, rec.requested = id, kind, db, reason, requested
		end
		Lift(frame, rec)
		return id, requested, reason
	end
	rec = Record(frame)
	if rec.id ~= id then ReleasePieces(rec, frame) end
	rec.id, rec.kind, rec.db, rec.reason, rec.requested = id, kind, db, reason, requested
	rec.data = data
	local width = type(db) == "table" and db.width or nil
	local height = type(db) == "table" and db.height or nil
	local gf = kind == "group" and ModuleDb("GroupFrames")
	local ctx = {
		rec = rec, db = type(db) == "table" and db or {}, kind = kind, data = data, artId = artId,
		skin = SkinManifest(), colors = data.colors, metrics = data.metrics, files = data.files,
		width = width, height = height,
		compact = kind == "group" or (height or 0) < Token("compactHeight"),
		party = gf and db ~= nil and gf.party == db or false,
	}
	provider.Apply(frame, ctx)
	Lift(frame, rec)
	return id, requested, reason
end

-- The opening the portrait picture shows through, for its coordinates:
-- "square" when a plate moved the picture into its portrait circle, "round"
-- when a ring mask shows the middle of the picture's box, nil when the
-- picture fills its box.
function UG:PortraitOpening(frame)
	local rec = owned[frame]
	if not rec then return nil end
	if rec.portraitMoved then return "square" end
	if rec.masked or rec.roundOpening then return "round" end
	return nil
end

-- The small level circle of the frame's classic plate and the plate's
-- scale (classic frame units to the frame's), or nil when no plate with
-- such a circle is drawn.
function UG:LevelSpot(frame)
	local rec = frame and owned[frame]
	if not (rec and rec.levelScale and rec.levelSpot and rec.plateSlot) then return nil end
	return rec.levelSpot, rec.levelScale
end

-- The camera share a model's framing keeps (1, or ringFraming while the
-- model sits in an opening of the art).
function UG:ModelFraming(frame)
	local rec = frame and owned[frame]
	if rec and rec.modelIn and rec.id ~= MODERN then return Token("ringFraming") end
	return 1
end

-- The picture switched between the 2D picture and the model (a unit came
-- into or left view): the ornament follows it.
function UG:PictureChanged(frame)
	local rec = frame and owned[frame]
	if rec and rec.id ~= MODERN and rec.db and frame.art then
		self:Apply(frame, rec.db, rec.kind)
	end
end

-- The unit's classification as the game reports it (a plain string, or
-- nil when unknown or hidden): shows or hides the crest at once.
function UG:Classify(frame, rank)
	local rec = frame and owned[frame]
	if type(rank) ~= "string" then rank = nil end
	if not rec or rec.rank == rank then return end
	rec.rank = rank
	if rec.id == MODERN then return end
	local provider = providers[rec.id]
	if provider and provider.Classify and provider.Classify(frame, rec) then return end
	if not rec.wantsCrest then return end
	Crest(rec, rec.data)
	Lift(frame, rec)
end

function UG:Release(frame)
	local rec = frame and owned[frame]
	if not rec then return end
	ReleasePieces(rec, frame)
	rec.id = MODERN
end

-- Insets in UI units, each { left, right, top, bottom }: content (where the
-- bars start), hit (always 0: graphics never change where a frame takes the
-- mouse) and paint (how far pieces reach outside the frame).
local function Insets(paint, id)
	local content = E.pixel
	if type(paint) == "table" then paint = { paint[1], paint[2], paint[3], paint[4] } else paint = { paint, paint, paint, paint } end
	return { content = { content, content, content, content }, hit = { 0, 0, 0, 0 }, paint = paint, id = id }
end

function UG:Measure(frame)
	local rec = frame and owned[frame]
	local drawn = rec and rec.id ~= MODERN
	return Insets(drawn and (rec.paintBox or rec.paint) or 0, rec and rec.id or MODERN)
end

-- The same insets from settings alone, for fit checks before a frame
-- exists (style footprints, layout checks): db is a unit's settings (or a
-- group section's), unit the unit it shows ("target" for the crest). The
-- answer is the most such a frame paints: the crest counts on the target
-- and focus whatever they show now. Under the skin and picks in use.
function UG:Metrics(db, kind, unit)
	kind = kind == "group" and "group" or "unit"
	db = type(db) == "table" and db or {}
	local id = self:Resolve(nil, db, kind)
	local provider = providers[id]
	local data = id ~= MODERN and Materials(provider) or nil
	if id ~= MODERN and not (data and data.files and data.metrics) then id = MODERN end
	if id == MODERN or kind == "group" then return Insets(0, id) end
	local own = provider.Metrics and provider.Metrics(db, kind, unit)
	if own then return Insets(own, id) end
	local compact = (db.height or 0) < Token("compactHeight")
	local paint = BorderPaint(data, compact)
	local portrait = PortraitMode(db) and provider.shape
	if portrait then paint = math.max(paint, RingPaint(data, provider.shape)) end
	if portrait and provider.crest and not compact and CREST_UNITS[unit or ""] and data.files.corner then
		paint = math.max(paint, CrestPaint(data))
	end
	return Insets(paint, id)
end

-- Read-only (tests, plugins): what a frame draws, how many pieces it made
-- and how many show now.
function UG:State(frame)
	local rec = frame and owned[frame]
	if not rec then return MODERN, 0, 0 end
	local made, shown = 0, 0
	local function Count(region)
		if not region then return end
		made = made + 1
		if region:IsShown() and (not region.GetParent or not region:GetParent() or region:GetParent():IsShown()) then shown = shown + 1 end
	end
	for _, key in ipairs({ "fill", "well", "ring", "strip", "divL", "divC", "divR", "crestL", "crestR", "hole" }) do Count(rec[key]) end
	for _, tex in ipairs(rec.plateCols or {}) do Count(tex) end
	for _, field in ipairs({ "keys", "medalKeys" }) do
		if rec[field] then for _, side in ipairs(KEYS) do Count(rec[field][side]) end end
	end
	if rec.masked then shown = shown + 1 end
	if rec.mask then made = made + 1 end
	if E.Skins and E.Skins.State then
		for _, key in ipairs({ "edge", "medalEdge" }) do
			if rec[key] then
				local mode, _, _, _, count = E.Skins.State(rec[key])
				made = made + count
				if mode and rec[key]:IsShown() then shown = shown + 1 end
			end
		end
	end
	return rec.id or MODERN, made, shown, rec.reason
end

-- Read-only (tests): the pieces a frame owns, by name (an empty table when none).
function UG.Pieces(frame)
	return frame and owned[frame] or {}
end

-- Select values: { id = title } and their order. follow: the label of the
-- Follow entry (default "Follow skin (now: X)"); saved: a saved id that is
-- no provider is listed as not available.
function UG:Values(saved, follow)
	local values, list = {}, {}
	local now = providers[FromSkin("unit")]
	values[FOLLOW] = follow or L["Follow skin (now: %s)"]:format(L[now and now.title or "Modern (flat)"])
	list[1] = FOLLOW
	for _, id in ipairs(order) do
		values[id] = L[providers[id].title]
		list[#list + 1] = id
	end
	if type(saved) == "string" and saved ~= "" and saved ~= FOLLOW and saved ~= SAME and not providers[saved] then
		values[saved] = L["%s (not available): Modern is used"]:format(saved)
		list[#list + 1] = saved
	end
	return values, list
end

-- One line per value for the select menu.
function UG:Descs()
	local descs = {
		[FOLLOW] = L["Draws what your skin brings: every skin names its own graphics."],
		[SAME] = L["Uses the Unit-frame graphics row at the top of this tab."],
	}
	for _, id in ipairs(order) do descs[id] = L[providers[id].desc] end
	return descs
end

-- Theme changes (skin, part, faction look): repaint every frame that draws.
local function Repaint()
	for frame, rec in pairs(owned) do
		if rec.db and frame.art then UG:Apply(frame, rec.db, rec.kind) end
	end
end
UG.Repaint = Repaint
if E.OnThemeChanged then E:OnThemeChanged("UnitGraphics", Repaint) end
