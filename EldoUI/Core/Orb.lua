-- EldoUI liquid orbs: a vertical status bar drawn as a glass orb of liquid,
-- for the Orbs unit-frame style (the player's health and power).
--
-- The bar keeps doing what any status bar does: the game sets its value
-- (which may be secret) and its color, and Lua never reads either. The orb
-- only dresses it:
--   back     the empty glass behind the liquid (a dark disc)
--   fill     the bar's own texture: the liquid's body, tinted by the bar color
--   clip     a frame that clips its children, anchored from the bar's bottom
--            to the top of the bar's fill texture, so the game itself crops
--            everything inside it at the liquid's level
--   swirl    two counter-rotating copies of soft wisps inside the clip,
--            tinted with the bar color and drawn ADD
--   surface  the bright level line at the top of the clip, cut to the disc
--   glass    rim shade, reflection and glint over the liquid
--   holder   the orb ring of the skin the unit frames draw in, or its
--            portrait ring when it has none (Data/SkinData.lua); a skin
--            without art of its own lends the Minimal Modern ring
--   statue   a carved statue standing beside the orb on its outer side, from
--            the same skin; only skins that draw one (Infernal Stone) show it
-- Every disc is baked into its texture (tools/gen_skin_art.py), so a turned
-- layer stays round; only the level line needs the round mask.
--
-- Motion is AnimationGroups only (no OnUpdate): the wisps turn slowly and
-- breathe out of phase. It stops while General > Animations is off or the
-- frame asks for a still orb.
--
-- Rules: presentation only. The color reaches the layers through a hook on
-- the bar's SetStatusBarColor, passed on to SetVertexColor untouched (a
-- secret color stays a secret color). No protected frame is touched.
--
-- API (E.Orb):
--   Orb:Attach(bar, holder, size[, opts])  dress `bar` as an orb of `size`
--                          units (from settings) in the middle of `holder`;
--                          opts.motion = false keeps the liquid still;
--                          opts.statue = "LEFT" or "RIGHT" stands the skin's
--                          statue on that side of the orb
--   Orb:Detach(bar)        take every orb piece off the bar again
--   Orb:IsOrb(bar)         true while the bar is dressed
--   Orb:Refresh()          follow a new skin or the Animations switch
--   Orb.State(bar)         read-only (tests): the orb's record
--   Orb.StatueFrames()     the statue frames shown now; they stand outside
--                          their unit frame's mover, so placement code that
--                          keeps clear of movers asks for them too
local _, E = ...

local Orb = E.Orb or {}
E.Orb = Orb

-- liquid: the bar's share of the holder (the ring's opening, with the
-- liquid's rim tucked under the ring); back: the empty glass color;
-- statue: its height as a share of the orb and its gap to the ring;
-- swirl: alpha still and the breathing range per wisp layer, seconds per
-- turn and per breath (a `pale` layer keeps its own white and adds light on
-- any bar color); surface: the level line's alpha and its height as a
-- share of the orb; glass: the glass layer's alpha.
E.tokens.orb = E.tokens.orb or {
	liquid = 0.86, back = { 0.035, 0.03, 0.03, 0.92 },
	swirl = {
		{ alpha = 0.32, low = 0.22, high = 0.42, turn = 44, up = 5, down = 4, degrees = 360 },
		{ alpha = 0.26, low = 0.16, high = 0.36, turn = 31, up = 6, down = 3, degrees = -360 },
		{ alpha = 0.07, low = 0.05, high = 0.10, turn = 67, up = 7, down = 5, degrees = 360, pale = true },
	},
	surface = 0.8, surfaceShare = 0.125, glass = 1,
	statue = { share = 0.86, gap = 2 },
}

local LEVEL = { back = -1, clip = 1, inner = 2, glass = 3, holder = 4 }
local owned = setmetatable({}, { __mode = "k" }) -- bar -> record

local function Token(key) return E.tokens.orb[key] end

local function Files() return E.skinOrb and E.skinOrb.files or {} end

local function Tex(parent, layer, sub)
	local tex = parent:CreateTexture(nil, layer, nil, sub)
	if tex.SetSnapToPixelGrid then tex:SetSnapToPixelGrid(false) end
	if tex.SetTexelSnappingBias then tex:SetTexelSnappingBias(0) end
	return tex
end

-- The ring that holds the orb: the unit frames' skin's orb ring, else its
-- portrait ring, else Minimal Modern's.
function Orb.HolderFile()
	local id = E.SkinPart and E:SkinPart("unitframes") or nil
	local manifest = E.SkinManifest and E:SkinManifest(id) or nil
	local data = manifest and manifest.art and E.skinData and E.skinData[manifest.art]
	if not (data and data.files and data.files.ring) then data = E.skinData and E.skinData.MINIMAL end
	return data and data.files and (data.files.orbring or data.files.ring)
end

-- The statue of the unit frames' skin, or nil when the skin draws none.
function Orb.StatueFile()
	local id = E.SkinPart and E:SkinPart("unitframes") or nil
	local manifest = E.SkinManifest and E:SkinManifest(id) or nil
	local data = manifest and manifest.art and E.skinData and E.skinData[manifest.art]
	return data and data.files and data.files.statue or nil
end

local function Moving(rec)
	return rec.motion ~= false and not (E.db and E.db.general and E.db.general.animations == false)
end

local function Loop(tex, spec)
	local turn = tex:CreateAnimationGroup()
	local rotation = turn:CreateAnimation("Rotation")
	rotation:SetDegrees(spec.degrees)
	rotation:SetDuration(spec.turn)
	turn:SetLooping("REPEAT")
	local breath = tex:CreateAnimationGroup()
	local up = breath:CreateAnimation("Alpha")
	up:SetFromAlpha(spec.low)
	up:SetToAlpha(spec.high)
	up:SetDuration(spec.up)
	up:SetOrder(1)
	local down = breath:CreateAnimation("Alpha")
	down:SetFromAlpha(spec.high)
	down:SetToAlpha(spec.low)
	down:SetDuration(spec.down)
	down:SetOrder(2)
	breath:SetLooping("REPEAT")
	return { turn, breath }
end

local function ApplyMotion(rec)
	local moving = Moving(rec) and rec.attached
	for index, groups in ipairs(rec.groups) do
		for _, group in ipairs(groups) do
			if moving then
				if not group:IsPlaying() then group:Play() end
			else
				group:Stop()
			end
		end
		rec.swirls[index]:SetAlpha(Token("swirl")[index].alpha)
	end
end

local function Tint(rec, r, g, b)
	for index, tex in ipairs(rec.swirls) do
		if not Token("swirl")[index].pale then tex:SetVertexColor(r, g, b) end
	end
end

local function Build(bar)
	local rec = { swirls = {}, groups = {} }
	local parent = bar:GetParent()
	local files = Files()
	rec.backFrame = CreateFrame("Frame", nil, parent)
	rec.back = Tex(rec.backFrame, "BACKGROUND")
	rec.back:SetTexture(files.fill)
	rec.back:SetAllPoints(bar)

	local clip = CreateFrame("Frame", nil, bar)
	clip:SetClipsChildren(true)
	rec.clip = clip
	local inner = CreateFrame("Frame", nil, clip)
	inner:SetAllPoints(bar)
	rec.inner = inner
	for index, spec in ipairs(Token("swirl")) do
		local tex = Tex(inner, "ARTWORK", index - 1)
		tex:SetTexture(files.swirl)
		tex:SetBlendMode("ADD")
		tex:SetAllPoints(bar)
		rec.swirls[index] = tex
		rec.groups[index] = Loop(tex, spec)
	end
	rec.surface = Tex(inner, "OVERLAY", 1)
	rec.surface:SetTexture(files.surface)
	rec.surface:SetBlendMode("ADD")
	local maskFile = E.skinMasks and E.skinMasks.round
	if maskFile and inner.CreateMaskTexture then
		local mask = inner:CreateMaskTexture()
		mask:SetTexture(maskFile, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		rec.mask = mask
		rec.surface:AddMaskTexture(mask)
	end

	rec.glassFrame = CreateFrame("Frame", nil, bar)
	rec.glassFrame:SetAllPoints(bar)
	rec.glass = Tex(rec.glassFrame, "ARTWORK")
	rec.glass:SetTexture(files.glass)
	rec.glass:SetAllPoints(bar)

	rec.holderFrame = CreateFrame("Frame", nil, parent)
	rec.holder = Tex(rec.holderFrame, "ARTWORK")
	rec.holder:SetAllPoints(rec.holderFrame)

	rec.statueFrame = CreateFrame("Frame", nil, parent)
	rec.statueFrame:EnableMouse(false)
	rec.statue = Tex(rec.statueFrame, "ARTWORK")
	rec.statue:SetAllPoints(rec.statueFrame)

	hooksecurefunc(bar, "SetStatusBarColor", function(self, r, g, b)
		local own = owned[self]
		if own and own.attached then Tint(own, r, g, b) end
	end)
	return rec
end

local function Show(rec, shown)
	for _, region in ipairs({ rec.backFrame, rec.clip, rec.glassFrame, rec.holderFrame }) do region:SetShown(shown) end
end

-- The statue on the orb's outer side, standing on the ring's bottom; the
-- right one is the left one mirrored.
local function PlaceStatue(rec)
	local file = rec.attached and rec.side and Orb.StatueFile()
	if not file then
		rec.statueFrame:Hide()
		return
	end
	local spec = Token("statue")
	local height = rec.size * spec.share
	rec.statueFrame:ClearAllPoints()
	if rec.side == "LEFT" then
		rec.statueFrame:SetPoint("BOTTOMRIGHT", rec.holderFrame, "BOTTOMLEFT", -spec.gap, 0)
		rec.statue:SetTexCoord(0, 1, 0, 1)
	else
		rec.statueFrame:SetPoint("BOTTOMLEFT", rec.holderFrame, "BOTTOMRIGHT", spec.gap, 0)
		rec.statue:SetTexCoord(1, 0, 0, 1)
	end
	rec.statueFrame:SetSize(height / 2, height)
	rec.statueFrame:SetFrameLevel(rec.holderFrame:GetFrameLevel())
	rec.statue:SetTexture(file)
	rec.statueFrame:Show()
end

function Orb:Attach(bar, holder, size, opts)
	if type(bar) ~= "table" or not bar.GetStatusBarTexture or type(holder) ~= "table" then return nil end
	size = tonumber(size) or 0
	if size <= 0 then return nil end
	local rec = owned[bar]
	if not rec then
		rec = Build(bar)
		owned[bar] = rec
	end
	rec.motion = not (type(opts) == "table" and opts.motion == false)
	local side = type(opts) == "table" and opts.statue
	rec.side = (side == "LEFT" or side == "RIGHT") and side or nil
	local files = Files()
	rec.attached, rec.holderRef, rec.size = true, holder, size

	-- The bar: a square in the middle of the holder, filling upward.
	local liquid = size * Token("liquid")
	bar:ClearAllPoints()
	bar:SetPoint("CENTER", holder, "CENTER")
	bar:SetSize(liquid, liquid)
	bar:SetOrientation("VERTICAL")
	bar:SetReverseFill(false)
	if bar.SetRotatesTexture then bar:SetRotatesTexture(false) end
	bar:SetStatusBarTexture(files.fill)
	if bar.bg then bar.bg:SetAlpha(0) end
	if E.statusBars then E.statusBars[bar] = nil end

	local level = bar:GetFrameLevel()
	rec.backFrame:SetFrameLevel(math.max(level + LEVEL.back, 0))
	local back = Token("back")
	rec.back:SetVertexColor(back[1], back[2], back[3], back[4])
	local fill = bar:GetStatusBarTexture()
	rec.clip:ClearAllPoints()
	rec.clip:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT")
	rec.clip:SetPoint("TOPRIGHT", fill, "TOPRIGHT")
	rec.clip:SetFrameLevel(level + LEVEL.clip)
	rec.inner:SetFrameLevel(level + LEVEL.inner)
	rec.surface:ClearAllPoints()
	rec.surface:SetPoint("TOPLEFT", fill, "TOPLEFT")
	rec.surface:SetPoint("TOPRIGHT", fill, "TOPRIGHT")
	rec.surface:SetHeight(math.max(liquid * Token("surfaceShare"), 4))
	rec.surface:SetAlpha(Token("surface"))
	if rec.mask then rec.mask:SetAllPoints(bar) end
	rec.glassFrame:SetFrameLevel(level + LEVEL.glass)
	rec.glass:SetAlpha(Token("glass"))
	rec.holderFrame:ClearAllPoints()
	rec.holderFrame:SetPoint("CENTER", holder, "CENTER")
	rec.holderFrame:SetSize(size, size)
	rec.holderFrame:SetFrameLevel(level + LEVEL.holder)
	rec.holder:SetTexture(Orb.HolderFile())
	Show(rec, true)
	PlaceStatue(rec)
	ApplyMotion(rec)
	return rec
end

function Orb:Detach(bar)
	local rec = bar and owned[bar]
	if not (rec and rec.attached) then return end
	rec.attached = false
	for _, groups in ipairs(rec.groups) do
		for _, group in ipairs(groups) do group:Stop() end
	end
	Show(rec, false)
	rec.statueFrame:Hide()
	-- The bar goes back to the bar texture in use; its owner lays it out again.
	if bar.bg then bar.bg:SetAlpha(1) end
	E:UseBarTexture(bar)
end

function Orb:IsOrb(bar)
	local rec = bar and owned[bar]
	return rec ~= nil and rec.attached == true
end

function Orb:Refresh()
	local file = Orb.HolderFile()
	for _, rec in pairs(owned) do
		if rec.attached then
			rec.holder:SetTexture(file)
			PlaceStatue(rec)
			ApplyMotion(rec)
		end
	end
end

function Orb.State(bar)
	return bar and owned[bar] or nil
end

function Orb.StatueFrames()
	local list = {}
	for _, rec in pairs(owned) do
		local frame = rec.statueFrame
		if frame and frame:IsShown() and frame:IsVisible() then list[#list + 1] = frame end
	end
	return list
end

if E.OnThemeChanged then E:OnThemeChanged("Orb", function() Orb:Refresh() end) end
