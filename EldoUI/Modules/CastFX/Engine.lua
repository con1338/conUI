-- EldoUI CastFX: the effect layers on one status bar and the
-- particle pool. Works on any StatusBar: EldoUI's unit frame cast bars,
-- Blizzard's own cast bars and CastFX's test bars.
--
-- Layers (created the first time a bar gets a themed cast):
--   root   our frame on the bar (hides with it, takes the bar's alpha, so a
--          cast the unit frames hide stays hidden)
--   clip   a clipping frame from the bar's start to the fill texture's edge:
--          the shine, the border light, the trail and the ambient particles
--          only show over the filled part; the client moves the edge
--   spark  on the fill edge; front: a 1x1 frame there the particles start from
--   flash  success / interrupt flash; pulse: pushback tint
-- Particles: textures with one animation group each (move, fade, scale,
-- spin), so the client animates them; Lua only decides how many start, at
-- most 20 times a second, and never above the budget.
local _, E = ...
local M = E.CastFX
local L = E.L

local Engine = {}
M.Engine = Engine

local issecret = issecretvalue or function() return false end
local random, max, min, floor = math.random, math.max, math.min, math.floor

local TICK = 0.05       -- scheduler step (20 Hz)
local MAX_SPAWN = 6     -- particles one bar starts per step at most
local MAX_BURST = 24
local PUSHBACK = { 1, 0.55, 0.1 }

local decos = setmetatable({}, { __mode = "k" })  -- bar -> state
Engine.decos = decos
-- bar -> { width, height } from the cast hook's "layout" call (EldoUI's own
-- numbers). A bar that got SetTimerDuration/SetValue may report a secret
-- size, so these come first.
local hookSizes = setmetatable({}, { __mode = "k" })
Engine.hookSizes = hookSizes
Engine.live = 0           -- particles alive on every bar
local inCombat = false

E:RegisterGlowUser("castfx", {
	title = "Cast bar effects",
	desc = "Glows round a themed cast bar while it casts (Cast Bar Effects, Glow while casting). The color comes from the theme.",
	order = 42,
	default = { style = "pulse", colorMode = "accent", color = { 1, 0.82, 0 }, lines = 8, speed = 0.3, thickness = 2, inset = 0 },
})

local function Rand(a, b) return a + (b - a) * random() end

local function RGB(color, fallback)
	color = type(color) == "table" and color or fallback or { 1, 1, 1 }
	return color[1] or 1, color[2] or 1, color[3] or 1
end

local function Mix(a, b, t)
	local r1, g1, b1 = RGB(a)
	local r2, g2, b2 = RGB(b, a)
	return r1 + (r2 - r1) * t, g1 + (g2 - g1) * t, b1 + (b2 - b1) * t
end

-- A plain positive number (a bar's own size), else the fallback.
local function Size(value, fallback)
	if type(value) ~= "number" or issecret(value) or value <= 0 then return fallback end
	return value
end

function Engine.Animations()
	return E.db.general.animations ~= false
end

function Engine.Intensity()
	return max(0, (tonumber(M.db.intensity) or 100) / 100)
end

---------------------------------------------------------------------------
-- Building blocks
---------------------------------------------------------------------------
-- 0 -> peak -> 0; peak set per play.
local function FlashGroup(region, fadeTime)
	local group = region:CreateAnimationGroup()
	local up = group:CreateAnimation("Alpha")
	up:SetFromAlpha(0)
	up:SetToAlpha(1)
	up:SetDuration(0.06)
	up:SetOrder(1)
	local down = group:CreateAnimation("Alpha")
	down:SetFromAlpha(1)
	down:SetToAlpha(0)
	down:SetDuration(fadeTime or 0.3)
	down:SetOrder(2)
	group:SetScript("OnFinished", function() region:SetAlpha(0) end)
	group.up, group.down = up, down
	return group
end

local function PlayFlash(region, group, peak)
	peak = max(0, min(peak, 0.8))  -- never brighter than 0.8 (DESIGN: no strobing)
	group:Stop()
	group.up:SetToAlpha(peak)
	group.down:SetFromAlpha(peak)
	region:SetAlpha(0)
	region:Show()
	group:Play()
end

-- A 3 px side-to-side shake that ends where it started.
local function ShakeGroup(frame)
	local group = frame:CreateAnimationGroup()
	for index, dx in ipairs({ 3, -6, 6, -3 }) do
		local step = group:CreateAnimation("Translation")
		step:SetOffset(dx, 0)
		step:SetDuration(0.04)
		step:SetOrder(index)
	end
	return group
end

local function Build(bar, kind)
	local deco = { bar = bar, kind = kind, pools = { front = {}, ambient = {} }, live = 0, flying = {}, acc = { front = 0, ambient = 0 }, tick = 0 }
	local root = CreateFrame("Frame", nil, bar)
	root:SetAllPoints(bar)
	root:SetFrameLevel(bar:GetFrameLevel() + 3)
	root.deco = deco
	root:SetScript("OnHide", function() Engine.ReleaseFlying(deco) end)
	deco.root = root

	local clip = CreateFrame("Frame", nil, root)
	clip:SetClipsChildren(true)
	clip:SetFrameLevel(root:GetFrameLevel())
	deco.clip = clip

	local shine = clip:CreateTexture(nil, "ARTWORK")
	shine:SetBlendMode("ADD")
	shine:Hide()
	deco.shine = shine
	local shineAnim = shine:CreateAnimationGroup()
	shineAnim:SetLooping("REPEAT")
	deco.shineMove = shineAnim:CreateAnimation("Translation")
	deco.shineAnim = shineAnim

	deco.lightTop = clip:CreateTexture(nil, "OVERLAY")
	deco.lightBottom = clip:CreateTexture(nil, "OVERLAY")
	for _, line in ipairs({ deco.lightTop, deco.lightBottom }) do
		line:SetColorTexture(1, 1, 1, 1)
		line:SetBlendMode("ADD")
		line:Hide()
	end

	local trail = clip:CreateTexture(nil, "OVERLAY", nil, 1)
	trail:SetTexture(M.STREAK)
	trail:SetBlendMode("ADD")
	trail:Hide()
	deco.trail = trail

	local pulse = clip:CreateTexture(nil, "OVERLAY", nil, 2)
	pulse:SetColorTexture(1, 1, 1, 1)
	pulse:SetBlendMode("ADD")
	pulse:SetAlpha(0)
	deco.pulse = pulse
	deco.pulseAnim = FlashGroup(pulse, 0.18)

	local spark = root:CreateTexture(nil, "OVERLAY", nil, 3)
	spark:SetBlendMode("ADD")
	spark:Hide()
	deco.spark = spark
	local sparkAnim = spark:CreateAnimationGroup()
	sparkAnim:SetLooping("BOUNCE")
	local beat = sparkAnim:CreateAnimation("Alpha")
	beat:SetFromAlpha(1)
	beat:SetToAlpha(0.55)
	beat:SetDuration(0.35)
	deco.sparkAnim = sparkAnim

	local front = CreateFrame("Frame", nil, root)
	front:SetSize(1, 1)
	deco.front = front

	local flash = root:CreateTexture(nil, "OVERLAY", nil, 4)
	flash:SetBlendMode("ADD")
	flash:SetAlpha(0)
	deco.flash = flash
	deco.flashAnim = FlashGroup(flash, 0.3)

	deco.glow = CreateFrame("Frame", nil, root)
	deco.glow:SetAllPoints(bar)
	return deco
end

-- The state of a bar; `kind` creates it ("eldo" | "blizzard" | "test").
function Engine.Get(bar, kind)
	local deco = decos[bar]
	if not deco and kind then
		deco = Build(bar, kind)
		decos[bar] = deco
	end
	return deco
end

---------------------------------------------------------------------------
-- Layout: everything hangs on the fill texture's growing edge.
---------------------------------------------------------------------------
function Engine.Layout(deco)
	local bar = deco.bar
	local fill = bar:GetStatusBarTexture()
	if not fill then return end
	local reverse = false
	if bar.GetReverseFill then
		local ok, value = pcall(bar.GetReverseFill, bar)
		reverse = ok and not issecret(value) and value == true
	end
	deco.reverse = reverse
	local edge = reverse and "LEFT" or "RIGHT"
	local known = hookSizes[bar]
	local w = Size(known and known.width, nil) or Size(bar:GetWidth(), 200)
	local h = Size(known and known.height, nil) or Size(bar:GetHeight(), 16)
	deco.width, deco.height = w, h
	deco.root:SetFrameLevel(bar:GetFrameLevel() + 3)

	local clip = deco.clip
	clip:ClearAllPoints()
	if reverse then
		clip:SetPoint("TOPLEFT", fill, "TOPLEFT")
		clip:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT")
	else
		clip:SetPoint("TOPLEFT", bar, "TOPLEFT")
		clip:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT")
	end

	deco.front:ClearAllPoints()
	deco.front:SetPoint("CENTER", fill, edge)
	deco.spark:ClearAllPoints()
	deco.spark:SetPoint("CENTER", fill, edge)

	local trail = deco.trail
	trail:ClearAllPoints()
	trail:SetWidth(min(h * 4, w * 0.5))
	trail:SetPoint("TOP" .. edge, fill, "TOP" .. edge)
	trail:SetPoint("BOTTOM" .. edge, fill, "BOTTOM" .. edge)
	if reverse then trail:SetTexCoord(1, 0, 0, 1) else trail:SetTexCoord(0, 1, 0, 1) end

	local px = max(E.pixel or 1, 1)
	deco.lightTop:ClearAllPoints()
	deco.lightTop:SetPoint("TOPLEFT", bar, "TOPLEFT")
	deco.lightTop:SetPoint("TOPRIGHT", bar, "TOPRIGHT")
	deco.lightTop:SetHeight(px)
	deco.lightBottom:ClearAllPoints()
	deco.lightBottom:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT")
	deco.lightBottom:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT")
	deco.lightBottom:SetHeight(px)

	deco.pulse:ClearAllPoints()
	deco.pulse:SetAllPoints(bar)
	deco.flash:ClearAllPoints()
	deco.flash:SetPoint("TOPLEFT", bar, "TOPLEFT", -h * 0.35, h * 0.35)
	deco.flash:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", h * 0.35, -h * 0.35)

	-- The shine: a band that sweeps from before the bar to past its end.
	local band = min(h * 3, w * 0.4)
	deco.shine:ClearAllPoints()
	deco.shine:SetSize(band, h)
	if reverse then
		deco.shine:SetPoint("RIGHT", bar, "RIGHT", band, 0)
		deco.shineMove:SetOffset(-(w + band), 0)
	else
		deco.shine:SetPoint("LEFT", bar, "LEFT", -band, 0)
		deco.shineMove:SetOffset(w + band, 0)
	end
end

---------------------------------------------------------------------------
-- A cast starts: theme color, spark, trail, shine, light, glow, emitters.
---------------------------------------------------------------------------
-- The bar's own spark: EldoUI's line (castbar.spark) or Blizzard's (Spark).
local function OwnSpark(deco)
	local bar = deco.bar
	if deco.kind == "blizzard" then return bar.Spark end
	return bar.spark
end

local function ShowOwnSpark(deco, show)
	local own = OwnSpark(deco)
	if not (own and own.SetAlpha) then return end
	if show then
		if deco.sparkHidden then
			own:SetAlpha(1)
			deco.sparkHidden = nil
		end
	else
		own:SetAlpha(0)
		deco.sparkHidden = true
	end
end

-- The theme color on the fill. A cast the game marks (or may mark, as a
-- secret) as not interruptible keeps the bar's own locked look: the client
-- chooses between the two colors from the flag.
function Engine.Tint(deco, theme, info)
	local bar = deco.bar
	if not M.db.tint then return end
	local notInterruptible = info and info.notInterruptible
	local r, g, b = RGB(theme.color)
	-- issecret first: comparing a secret with nil errors.
	if issecret(notInterruptible) then
		if deco.kind == "blizzard" then return end
		deco.themeColor = deco.themeColor or CreateColor(r, g, b, 1)
		deco.themeColor:SetRGB(r, g, b)
		local locked = bar.lockedColor or CreateColor(0.45, 0.45, 0.45, 1)
		if C_CurveUtil and C_CurveUtil.EvaluateColorFromBoolean then
			local ok, color = pcall(C_CurveUtil.EvaluateColorFromBoolean, notInterruptible, locked, deco.themeColor)
			if ok and color then pcall(bar.SetStatusBarColor, bar, color:GetRGB()) end
		end
		return
	end
	if notInterruptible then return end
	if deco.kind == "blizzard" and not deco.savedColor then
		local cr, cg, cb = bar:GetStatusBarColor()
		if type(cr) == "number" and not issecret(cr) and not issecret(cg) and not issecret(cb) then deco.savedColor = { cr, cg, cb } end
	end
	bar:SetStatusBarColor(r, g, b)
	local fill = bar:GetStatusBarTexture()
	if theme.gradient and fill and fill.SetGradient and CreateColor then
		local r2, g2, b2 = RGB(theme.color2, theme.color)
		local from, to = CreateColor(r, g, b, 1), CreateColor(r2, g2, b2, 1)
		-- The light end sits at the growing edge.
		if deco.reverse then from, to = to, from end
		pcall(fill.SetGradient, fill, "HORIZONTAL", from, to)
		deco.gradient = true
	end
end

local SHINE_TEX = {
	sheen = M.TEX .. "EldoSheen.tga",
	stripes = M.TEX .. "EldoStripes.tga",
}

local function ApplyShine(deco, theme, animate, intensity)
	local style = M.db.shimmer and theme.shine or "none"
	local shine = deco.shine
	deco.shineAnim:Stop()
	if style == "none" or not M.SHINES[style] then
		shine:Hide()
		return
	end
	if SHINE_TEX[style] then
		shine:SetTexture(SHINE_TEX[style])
		shine:SetTexCoord(0, 1, 0, 1)
	else
		M.SetArt(shine, style)
	end
	shine:SetVertexColor(RGB(theme.shineColor))
	shine:SetAlpha(max(0, min(1, (theme.shineAlpha or 0.35) * min(intensity, 1.5))))
	shine:Show()
	if animate then
		local speed = max(0.2, tonumber(theme.shineSpeed) or 1)
		deco.shineMove:SetDuration(max(0.4, min(4, (deco.width or 200) / 140 / speed)))
		deco.shineAnim:Play()
	end
end

local function ApplySpark(deco, theme, animate)
	local mode = M.db.spark
	local style = theme.spark or "pip"
	local spark = deco.spark
	deco.sparkAnim:Stop()
	spark:Hide()
	if mode == "OFF" then
		ShowOwnSpark(deco, false)
		return false
	end
	if mode == "LINE" or style == "line" then
		ShowOwnSpark(deco, true)
		return true
	end
	ShowOwnSpark(deco, false)
	if style == "none" then return false end
	local h = deco.height or 16
	local size = max(0.3, tonumber(theme.sparkSize) or 1)
	if style == "pip" then
		M.SetArt(spark, "pip")
		spark:SetSize(max(6, h * 0.55) * size, h * 1.7 * size)
	elseif style == "star" then
		M.SetParticle(spark, "eldo:Mote")
		spark:SetSize(h * 1.8 * size, h * 1.8 * size)
	else
		M.SetArt(spark, "pipGlow")
		spark:SetSize(h * 1.3 * size, h * 2 * size)
	end
	spark:SetVertexColor(RGB(theme.sparkColor))
	spark:SetAlpha(1)
	spark:Show()
	if animate then deco.sparkAnim:Play() end
	return true
end

function Engine.Start(deco, themeKey, info)
	local db = M.db
	local theme = M:GetTheme(themeKey) or M.BUILTIN.minimal
	if deco.active then Engine.Stop(deco) end
	deco.theme, deco.themeKey, deco.info = theme, themeKey, info
	deco.active = true
	deco.channel = info and info.channel and true or false
	Engine.Layout(deco)
	deco.root:Show()
	deco.flashAnim:Stop()
	deco.flash:SetAlpha(0)
	local animate = Engine.Animations()
	local intensity = Engine.Intensity()

	Engine.Tint(deco, theme, info)
	if theme.texture and theme.texture ~= "default" and deco.kind ~= "blizzard" then
		local path = E:FetchMedia("statusbar", theme.texture)
		if path then
			deco.bar:SetStatusBarTexture(path)
			deco.textured = true
		end
	end

	local sparkShown = ApplySpark(deco, theme, animate)
	local trail = deco.trail
	if db.trail and theme.trail and sparkShown then
		trail:SetVertexColor(RGB(theme.sparkColor))
		trail:SetAlpha(min(0.85, 0.6 * max(intensity, 0.3)))
		trail:Show()
	else
		trail:Hide()
	end

	ApplyShine(deco, theme, animate, intensity)

	local lightAlpha = db.frameLight and (tonumber(theme.lightAlpha) or 0) or 0
	for _, line in ipairs({ deco.lightTop, deco.lightBottom }) do
		line:SetVertexColor(RGB(theme.lightColor))
		line:SetAlpha(min(1, lightAlpha * max(intensity, 0.3)))
		line:SetShown(lightAlpha > 0)
	end

	if db.castGlow then
		local r, g, b = RGB(theme.color)
		E:ShowUserGlow(deco.glow, "castfx", { color = { r, g, b, 1 } })
		deco.glowing = true
	elseif deco.glowing then
		deco.glowing = nil
		E:HideGlow(deco.glow)
	end

	local particles = db.particles and animate and intensity > 0
	deco.emitFront = particles and theme.frontOn and (tonumber(theme.frontRate) or 0) > 0 or false
	deco.emitAmbient = particles and theme.ambientOn and (tonumber(theme.ambientRate) or 0) > 0 or false
	deco.acc.front, deco.acc.ambient, deco.tick = 0, 0, 0
	Engine.UpdateEmitters(deco)
end

-- The cast is over (or the bar went away): emitters stop, the bar gets its
-- own spark, texture and color back. Particles in flight play out.
function Engine.Stop(deco)
	deco.active = false
	deco.emitFront, deco.emitAmbient = false, false
	Engine.UpdateEmitters(deco)
	deco.shineAnim:Stop()
	deco.sparkAnim:Stop()
	deco.spark:Hide()
	deco.trail:Hide()
	deco.shine:Hide()
	deco.lightTop:Hide()
	deco.lightBottom:Hide()
	ShowOwnSpark(deco, true)
	local bar = deco.bar
	if deco.textured then
		deco.textured = nil
		bar:SetStatusBarTexture(E.media.statusbar)
	end
	if deco.gradient then
		deco.gradient = nil
		local fill = bar:GetStatusBarTexture()
		if fill and fill.SetGradient and CreateColor then
			local white = CreateColor(1, 1, 1, 1)
			pcall(fill.SetGradient, fill, "HORIZONTAL", white, white)
		end
	end
	if deco.savedColor then
		bar:SetStatusBarColor(deco.savedColor[1], deco.savedColor[2], deco.savedColor[3])
		deco.savedColor = nil
	end
	if deco.glowing then
		deco.glowing = nil
		E:HideGlow(deco.glow)
	end
end

---------------------------------------------------------------------------
-- Particles
---------------------------------------------------------------------------
local function Release(deco, p)
	p:Hide()
	p:ClearAllPoints()
	if p.alive then
		p.alive = nil
		deco.flying[p] = nil
		Engine.live = max(0, Engine.live - 1)
		deco.live = max(0, deco.live - 1)
	end
	local pool = deco.pools[p.layer]
	pool[#pool + 1] = p
end

-- Every particle in flight back to the pool (the bar hid, the module went
-- off): nothing keeps counting against the budget.
local function ReleaseFlying(deco)
	for p in pairs(deco.flying) do
		p.group:Stop()
		Release(deco, p)
	end
end
Engine.ReleaseFlying = ReleaseFlying

local function NewParticle(deco, layer)
	local parent = layer == "ambient" and deco.clip or deco.root
	local p = parent:CreateTexture(nil, "OVERLAY", nil, layer == "ambient" and 1 or 5)
	p:Hide()
	p.layer = layer
	local group = p:CreateAnimationGroup()
	p.move = group:CreateAnimation("Translation")
	p.move:SetSmoothing("OUT")
	p.fadeIn = group:CreateAnimation("Alpha")
	p.fadeIn:SetFromAlpha(0)
	p.fadeOut = group:CreateAnimation("Alpha")
	p.fadeOut:SetToAlpha(0)
	p.scale = group:CreateAnimation("Scale")
	p.scale:SetScaleFrom(1, 1)
	p.spin = group:CreateAnimation("Rotation")
	group:SetScript("OnFinished", function() Release(deco, p) end)
	p.group = group
	return p
end

local function Room(deco)
	return Engine.live < (tonumber(M.db.budget) or 80) and deco.live < (tonumber(M.db.barBudget) or 40)
end
Engine.Room = Room

-- opts: texture, color, color2, blend, size, life, dx, dy, anchor,
-- relPoint, x, y, shrink, spin, alpha, layer.
local function Launch(deco, opts)
	if not Room(deco) then return false end
	local layer = opts.layer or "front"
	local pool = deco.pools[layer]
	local p = table.remove(pool) or NewParticle(deco, layer)
	M.SetParticle(p, opts.texture)
	p:SetVertexColor(Mix(opts.color, opts.color2, random()))
	p:SetBlendMode(opts.blend == "BLEND" and "BLEND" or "ADD")
	local size = max(2, (tonumber(opts.size) or 6) * Rand(0.6, 1.4))
	p:SetSize(size, size)
	p:ClearAllPoints()
	p:SetPoint("CENTER", opts.anchor, opts.relPoint or "CENTER", opts.x or 0, opts.y or 0)
	local life = max(0.15, (tonumber(opts.life) or 0.8) * Rand(0.7, 1.3))
	local alpha = max(0.05, min(1, opts.alpha or 0.9))
	p.group:Stop()
	p.move:SetOffset(opts.dx or 0, opts.dy or 0)
	p.move:SetDuration(life)
	p.fadeIn:SetToAlpha(alpha)
	p.fadeIn:SetDuration(min(0.12, life * 0.2))
	p.fadeOut:SetFromAlpha(alpha)
	p.fadeOut:SetStartDelay(life * 0.45)
	p.fadeOut:SetDuration(life * 0.55)
	local shrink = opts.shrink or 0.4
	p.scale:SetScaleTo(shrink, shrink)
	p.scale:SetDuration(life)
	p.spin:SetDegrees(opts.spin and Rand(-200, 200) or 0)
	p.spin:SetDuration(life)
	p:SetAlpha(alpha)
	p:Show()
	p.alive = true
	deco.flying[p] = true
	Engine.live = Engine.live + 1
	deco.live = deco.live + 1
	p.group:Play()
	return true
end
Engine.Launch = Launch

-- One particle from the fill edge, drifting back along the bar.
local function SpawnFront(deco)
	local t = deco.theme
	local h = deco.height or 16
	local life = tonumber(t.frontLife) or 0.8
	local speed = (tonumber(t.frontSpeed) or 20) * Rand(0.6, 1.4)
	local spread = math.sin(math.rad(min(max(tonumber(t.frontSpread) or 60, 0), 180) / 2))
	-- Behind the moving edge: a cast grows, a channel drains.
	local back = (deco.reverse == deco.channel) and -1 or 1
	return Launch(deco, {
		texture = t.frontTexture, color = t.frontColor, color2 = t.frontColor2, blend = t.frontBlend,
		size = t.frontSize, life = life, anchor = deco.front, y = Rand(-h * 0.35, h * 0.35),
		dx = back * speed * life * Rand(0.2, 1), dy = (tonumber(t.frontRise) or 0) * life + Rand(-1, 1) * speed * life * spread,
		spin = t.frontSpin, shrink = 0.35,
	})
end

-- One particle somewhere inside the filled part (the clip frame hides it
-- over the empty part, so nothing is measured).
local function SpawnAmbient(deco)
	local t = deco.theme
	local h, w = deco.height or 16, deco.width or 200
	local life = tonumber(t.ambientLife) or 1.2
	return Launch(deco, {
		layer = "ambient", texture = t.ambientTexture, color = t.ambientColor, blend = t.ambientBlend,
		size = t.ambientSize, life = life, anchor = deco.bar, relPoint = "LEFT", x = Rand(0, w), y = Rand(-h * 0.4, h * 0.4),
		dx = Rand(-6, 6), dy = (tonumber(t.ambientRise) or 0) * life, shrink = 0.6, alpha = 0.7,
	})
end

local function Emit(deco, key, rate, dt, spawn)
	local acc = deco.acc[key] + rate * dt
	local started = 0
	while acc >= 1 and started < MAX_SPAWN do
		acc = acc - 1
		if spawn(deco) then
			started = started + 1
		else
			acc = 0  -- budget reached: skip, never queue
		end
	end
	deco.acc[key] = min(acc, 3)
end

local function OnUpdate(root, elapsed)
	local deco = root.deco
	deco.tick = deco.tick + elapsed
	if deco.tick < TICK then return end
	local dt = deco.tick
	deco.tick = 0
	local db = M.db
	local mult = Engine.Intensity()
	local reduced = false
	if inCombat then
		if db.combat == "OFF" then return end
		if db.combat == "REDUCED" then
			mult = mult * 0.5
			reduced = true
		end
	end
	local t = deco.theme
	if deco.emitFront then Emit(deco, "front", (tonumber(t.frontRate) or 0) * mult, dt, SpawnFront) end
	if deco.emitAmbient and not reduced then Emit(deco, "ambient", (tonumber(t.ambientRate) or 0) * mult, dt, SpawnAmbient) end
end

function Engine.UpdateEmitters(deco)
	local on = deco.emitFront or deco.emitAmbient
	deco.root:SetScript("OnUpdate", on and OnUpdate or nil)
end

---------------------------------------------------------------------------
-- End effects
---------------------------------------------------------------------------
-- Particles flying out of the edge in every direction (success).
local function Burst(deco, count)
	local t = deco.theme
	for _ = 1, count do
		local angle = Rand(0, math.pi * 2)
		local speed = max(20, (tonumber(t.frontSpeed) or 20) * 1.6) * Rand(0.6, 1.2)
		local life = 0.5
		if not Launch(deco, {
			texture = t.frontTexture, color = t.frontColor, color2 = t.successColor, blend = t.frontBlend,
			size = (tonumber(t.frontSize) or 6) * 1.1, life = life, anchor = deco.front,
			dx = math.cos(angle) * speed * life, dy = math.sin(angle) * speed * life, spin = t.frontSpin, shrink = 0.3,
		}) then break end
	end
end

-- Particles dropping off the bar (interrupt).
local function Drop(deco, count)
	local t = deco.theme
	local w, h = deco.width or 200, deco.height or 16
	for _ = 1, count do
		if not Launch(deco, {
			texture = t.frontOn and t.frontTexture or "eldo:Dot", color = t.failColor, color2 = t.frontColor,
			blend = "BLEND", size = max(3, (tonumber(t.frontSize) or 6) * 0.8), life = 0.6, anchor = deco.bar,
			relPoint = "LEFT", x = Rand(0, w), y = Rand(-h * 0.3, h * 0.3), dx = Rand(-4, 4), dy = -Rand(14, 34), shrink = 0.6,
		}) then break end
	end
end

function Engine.Pushback(deco)
	if not (deco.active and M.db.pushback) then return end
	deco.pulse:SetVertexColor(RGB(PUSHBACK))
	PlayFlash(deco.pulse, deco.pulseAnim, 0.45 * min(Engine.Intensity(), 1.5))
end

function Engine.Shake(deco)
	local target = deco.kind == "blizzard" and deco.root or deco.bar
	deco.shakeGroup = deco.shakeGroup or ShakeGroup(target)
	deco.shakeGroup:Stop()
	deco.shakeGroup:Play()
end

-- outcome: "success" | "fail".
function Engine.Finish(deco, outcome)
	if not deco.active then return end
	local db = M.db
	local theme = deco.theme
	Engine.Stop(deco)
	local animate = Engine.Animations()
	local intensity = Engine.Intensity()
	local particles = db.particles and animate and not (inCombat and db.combat == "OFF")
	local flash = deco.flash
	deco.flashed = nil
	if outcome == "success" then
		if db.success ~= "OFF" then
			deco.flashed = true
			M.SetArt(flash, deco.channel and "finishChannel" or "finish")
			flash:SetVertexColor(RGB(theme.successColor))
			PlayFlash(flash, deco.flashAnim, 0.7 * min(intensity, 1.15))
		end
		local count = floor((tonumber(theme.burst) or 0) * intensity + 0.5)
		if db.success == "BURST" and particles and count > 0 then Burst(deco, min(count, MAX_BURST)) end
	else
		if db.fail ~= "OFF" then
			deco.flashed = true
			M.SetArt(flash, "interrupt")
			flash:SetVertexColor(RGB(theme.failColor))
			PlayFlash(flash, deco.flashAnim, 0.75 * min(intensity, 1.1))
		end
		if db.fail == "SHAKE" and animate then
			Engine.Shake(deco)
			if particles then Drop(deco, min(floor(6 * intensity + 0.5), MAX_BURST)) end
		end
	end
end

---------------------------------------------------------------------------
-- Whole-module helpers
---------------------------------------------------------------------------
function Engine.CombatChanged(state)
	inCombat = state and true or false
end

function Engine.InCombat() return inCombat end

-- Settings changed: casts in progress take the new settings.
function Engine.RefreshAll()
	for _, deco in pairs(decos) do
		if deco.active then Engine.Start(deco, deco.themeKey, deco.info) end
	end
end

-- Module off: every bar gets its own look back, effects disappear.
function Engine.ReleaseAll()
	for _, deco in pairs(decos) do
		Engine.Stop(deco)
		deco.flashAnim:Stop()
		deco.flash:SetAlpha(0)
		ReleaseFlying(deco)
		deco.root:Hide()
	end
end

-- Particles alive per bar kind, for /eui diag.
function Engine.Stats()
	local bars, active = 0, 0
	for _, deco in pairs(decos) do
		bars = bars + 1
		if deco.active then active = active + 1 end
	end
	return bars, active, Engine.live
end

E:RegisterDiagnostics("CastFX", function()
	if not (M.db and M.db.enabled) then return end
	local bars, active, live = Engine.Stats()
	return { ("   " .. L["Cast Bar Effects: %d bars decorated, %d casting, %d particles alive (budget %d)"]):format(bars, active, live, M.db.budget or 80) }
end)

inCombat = InCombatLockdown and InCombatLockdown() or false
