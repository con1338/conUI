-- EldoUI frame effects: the small pieces the unit frames and
-- the party and raid frames share on top of Core/UnitFX.lua, so both
-- modules look and move the same.
--
--   FX.StateColor(unit, deadLook)      r, g, b and the state key for a dead, ghost,
--                                      offline or tapped unit (General > Colors,
--                                      "Unit states and effects"), or nil
--   FX.Flash(owner, anchor, settings)  target change flash: one accent sweep over
--                                      `anchor` (UnitFX "targetFlash")
--   FX.Pulse(region, on)               status icon breathing (UnitFX "statusPulse")
--   FX.FadeOut(region, hold, onDone)   ready check result: hold, then fade out
--   FX.Badge(parent)                   a small badge (level or class / role)
--   FX.StyleBadge(badge, size, round, bare)  square box in Modern, round in Blizzard /
--                                      Classic, no box when bare
--   FX.PlaceBadge(badge, anchor, ...)  a badge's spot (FX.BADGE_ANCHORS)
--   FX.BadgeClass(badge, unit, mode)   class icon (players), role icon, or nothing
--   FX.RoundArt()                      round looks are allowed (DESIGN section 3)
--   FX.AuraFX(effects)                 the AuraWidget `fx` block from an Effects block
--   FX.Shared(list, get)               one shared value, or nil when they differ
--
-- Rules: every trigger here is a plain game flag (target changed, dead,
-- offline, a pending resurrection or summon, a finished ready check).
-- Animations run on EldoUI regions and children, never on a secure
-- button; with General > Animations off everything is static. Pulses stay
-- at 1 Hz, under UnitFX's 2 Hz cap.
-- Written from scratch for EldoUI.
local _, E = ...

local FX = {}
E.FrameFX = FX

local issecret = issecretvalue or function() return false end

local Plain = E.PlainCall
local Key = E.Key

-- Start opacity of the target change flash (an accent sweep, not a glare).
local FLASH_ALPHA = 0.35

local function Animations()
	return E.db and E.db.general and E.db.general.animations and true or false
end

---------------------------------------------------------------------------
-- Dead, ghost, offline and tapped colors
---------------------------------------------------------------------------
-- deadLook: the Effects row "Dead and offline look"; tapped mobs always
-- take the tapped color (as Blizzard's frames do).
function FX.StateColor(unit, deadLook)
	if type(unit) ~= "string" then return nil end
	local player = Plain(UnitIsPlayer, unit)
	local key
	if deadLook then
		if player and Plain(UnitIsConnected, unit) == false then
			key = "offline"
		elseif Plain(UnitIsGhost, unit) then
			key = "ghost"
		elseif Plain(UnitIsDead, unit) then
			key = "dead"
		end
	end
	if not key and not player and Plain(UnitIsTapDenied, unit) then key = "tapped" end
	if not key then return nil end
	local r, g, b = E:GetStatusColor(key)
	if type(r) ~= "number" then return nil end
	return r, g, b, key
end

---------------------------------------------------------------------------
-- Heal prediction colors (General > Colors, "Heal prediction"): the bars
-- of a prediction set { other, mine, absorb, healAbsorb, overAbsorb }.
---------------------------------------------------------------------------
local PREDICTION = {
	other = { "healOther", 0.5 }, mine = { "healMine", 0.6 }, absorb = { "absorb", 0.35 }, healAbsorb = { "healAbsorb", 0.55 },
}
function FX.ColorPrediction(p)
	if type(p) ~= "table" then return end
	for key, spec in pairs(PREDICTION) do
		local bar = p[key]
		if bar and bar.SetStatusBarColor then
			local r, g, b = E:GetPredictionColor(spec[1])
			bar:SetStatusBarColor(r or 1, g or 1, b or 1, spec[2])
		end
	end
	if p.overAbsorb then
		local r, g, b = E:GetPredictionColor("overAbsorb")
		p.overAbsorb:SetColorTexture(r or 1, g or 1, b or 1, 0.9)
	end
end

---------------------------------------------------------------------------
-- Target change flash: an accent overlay that fades out once.
---------------------------------------------------------------------------
function FX.Flash(owner, anchor, settings)
	if type(settings) ~= "table" or not settings.enabled or not Animations() then
		if owner.flashTexture then owner.flashTexture:SetAlpha(0) end
		return false
	end
	local texture = owner.flashTexture
	if not texture then
		local layer = CreateFrame("Frame", nil, owner)
		layer:SetAllPoints(anchor or owner)
		layer:SetFrameLevel(owner:GetFrameLevel() + 12)
		if layer.EnableMouse then layer:EnableMouse(false) end
		texture = layer:CreateTexture(nil, "OVERLAY")
		texture:SetAllPoints(layer)
		texture:SetTexture(E.media.flat)
		texture:SetBlendMode("ADD")
		texture:SetAlpha(0)
		local group = texture:CreateAnimationGroup()
		group.fade = group:CreateAnimation("Alpha")
		group.fade:SetFromAlpha(FLASH_ALPHA)
		group.fade:SetToAlpha(0)
		group.fade:SetSmoothing("OUT")
		group:SetScript("OnFinished", function() texture:SetAlpha(0) end)
		texture.anim = group
		owner.flashTexture, owner.flashLayer = texture, layer
	end
	owner.flashLayer:ClearAllPoints()
	owner.flashLayer:SetAllPoints(anchor or owner)
	local r, g, b = unpack(E.media.accentColor)
	texture:SetVertexColor(r, g, b, 1)
	texture.anim:Stop()
	texture.anim.fade:SetDuration(math.max(0.2, math.min(tonumber(settings.duration) or 0.3, 0.5)))
	texture.anim:Play()
	return true
end

---------------------------------------------------------------------------
-- Status icon pulse (resurrection, summon): alpha 1 -> 0.45 and back, 1 Hz.
---------------------------------------------------------------------------
function FX.Pulse(region, on)
	if not region or not region.CreateAnimationGroup then return false end
	local group = region.eldoPulse
	if not (on and Animations()) then
		if group then group:Stop() end
		region:SetAlpha(1)
		return false
	end
	if not group then
		group = region:CreateAnimationGroup()
		local fade = group:CreateAnimation("Alpha")
		fade:SetFromAlpha(1)
		fade:SetToAlpha(0.45)
		fade:SetDuration(0.5)
		fade:SetSmoothing("IN_OUT")
		group:SetLooping("BOUNCE")
		region.eldoPulse = group
	end
	if not group:IsPlaying() then group:Play() end
	return true
end

---------------------------------------------------------------------------
-- Ready check: the result stays `hold` seconds, then fades over one second
-- (instant hide with animations off). A new check cancels it.
---------------------------------------------------------------------------
function FX.CancelFade(region)
	if not region then return end
	if region.eldoFadeTimer then
		region.eldoFadeTimer:Cancel()
		region.eldoFadeTimer = nil
	end
	if region.eldoFadeOut then region.eldoFadeOut:Stop() end
	region:SetAlpha(1)
end

function FX.FadeOut(region, hold, onDone)
	if not region then return end
	FX.CancelFade(region)
	local function Done()
		region:Hide()
		region:SetAlpha(1)
		if onDone then onDone() end
	end
	region.eldoFadeTimer = C_Timer.NewTimer(math.max(1, math.min(tonumber(hold) or 6, 10)), function()
		region.eldoFadeTimer = nil
		if not (Animations() and region.CreateAnimationGroup) then return Done() end
		local group = region.eldoFadeOut
		if not group then
			group = region:CreateAnimationGroup()
			local fade = group:CreateAnimation("Alpha")
			fade:SetFromAlpha(1)
			fade:SetToAlpha(0)
			fade:SetDuration(1)
			group:SetScript("OnFinished", function() if group.done then group.done() end end)
			region.eldoFadeOut = group
		end
		group.done = Done
		group:Play()
	end)
end

---------------------------------------------------------------------------
-- Badges (Boxed look): a level badge and a class or role badge.
---------------------------------------------------------------------------
-- Round looks only outside Modern (DESIGN section 3: no rounded corners in
-- the Modern art style).
function FX.RoundArt()
	local style = E.ArtStyle and E:ArtStyle() or "Modern"
	return style == "Blizzard" or style == "Classic"
end

function FX.Badge(parent)
	local badge = CreateFrame("Frame", nil, parent)
	if badge.EnableMouse then badge:EnableMouse(false) end
	E:SetTemplate(badge)
	badge.icon = badge:CreateTexture(nil, "ARTWORK")
	badge.text = E:CreateText(badge, E.tokens.size.small, "CENTER")
	badge.text:SetPoint("CENTER", 0, 0)
	badge:Hide()
	return badge
end

-- bare: no box at all, for a badge that sits in a circle of the frame's
-- own art (the art is its box).
function FX.StyleBadge(badge, size, round, bare)
	badge:SetSize(size, size)
	badge.round = round and true or false
	E:SetTemplate(badge)
	if bare then
		badge:SetBackdropColor(0, 0, 0, 0)
		badge:SetBackdropBorderColor(0, 0, 0, 0)
	end
	if round then
		-- The round class art carries its own ring: no box behind it.
		badge:SetBackdropColor(0, 0, 0, 0)
		badge:SetBackdropBorderColor(0, 0, 0, 0)
		badge.icon:ClearAllPoints()
		badge.icon:SetAllPoints(badge)
	else
		badge.icon:ClearAllPoints()
		E:Hairline(badge.icon, "inset", 1, badge)
	end
	E:SetFont(badge.text, math.max(8, math.floor(size * 0.55)), "OUTLINE")
end

local CLASS_CIRCLES = "Interface\\TargetingFrame\\UI-Classes-Circles"
local ROLE_ATLAS = { TANK = "roleicon-tiny-tank", HEALER = "roleicon-tiny-healer", DAMAGER = "roleicon-tiny-dps" }

-- mode "CLASS": the class icon for players, the role icon when it has none;
-- "ROLE": the group role. NPCs get no badge (their type is in the name bar).
function FX.BadgeClass(badge, unit, mode)
	local icon = badge.icon
	icon:SetTexCoord(0, 1, 0, 1)
	if mode ~= "ROLE" and Plain(UnitIsPlayer, unit) then
		local ok, _, class = pcall(UnitClass, unit)
		if ok and not issecret(class) and type(class) == "string" then
			local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
			if badge.round and coords then
				icon:SetTexture(CLASS_CIRCLES)
				icon:SetTexCoord(unpack(coords))
				icon:Show()
				return true
			end
			local atlas = GetClassAtlas and GetClassAtlas(class:lower())
			if atlas and E:SetClientAtlas(icon, atlas) then
				E:TrimIcon(icon)
				icon:Show()
				return true
			end
			if coords then
				icon:SetTexture(CLASS_CIRCLES)
				icon:SetTexCoord(coords[1] + 0.02, coords[2] - 0.02, coords[3] + 0.02, coords[4] - 0.02)
				icon:Show()
				return true
			end
		end
	end
	local role = Plain(UnitGroupRolesAssigned, unit)
	local atlas = role and ROLE_ATLAS[role]
	if atlas and E:SetClientAtlas(icon, atlas) then
		icon:Show()
		return true
	end
	icon:Hide()
	return false
end

-- Where a badge sits: on the portrait's outer top or bottom, on the
-- frame's edge, or in the small level circle of a classic plate (`spot`,
-- from E.UnitGraphics:LevelSpot; the portrait's bottom while no plate draws
-- one). `outer` is the side away from the portrait.
local BADGE_POINTS = {
	PORTRAIT_TOP = function(badge, frame, portrait)
		badge:SetPoint("CENTER", portrait or frame, "TOP", 0, 0)
	end,
	PORTRAIT_BOTTOM = function(badge, frame, portrait)
		badge:SetPoint("CENTER", portrait or frame, "BOTTOM", 0, 0)
	end,
	OUTER_TOP = function(badge, frame, _, outer)
		local side = outer == "LEFT" and "TOPLEFT" or "TOPRIGHT"
		badge:SetPoint("CENTER", frame, side, 0, 0)
	end,
	OUTER_BOTTOM = function(badge, frame, _, outer)
		local side = outer == "LEFT" and "BOTTOMLEFT" or "BOTTOMRIGHT"
		badge:SetPoint("CENTER", frame, side, 0, 0)
	end,
	PLATE_CIRCLE = function(badge, frame, portrait, _, spot)
		if spot then
			badge:SetPoint("CENTER", spot, "CENTER", 0, 0)
		else
			badge:SetPoint("CENTER", portrait or frame, "BOTTOM", 0, 0)
		end
	end,
}
-- Translated where the options show them.
FX.BADGE_ANCHORS = { PORTRAIT_TOP = Key("Portrait, top"), PORTRAIT_BOTTOM = Key("Portrait, bottom"),
	OUTER_TOP = Key("Frame edge, top"), OUTER_BOTTOM = Key("Frame edge, bottom"),
	PLATE_CIRCLE = Key("Classic frame circle") }

function FX.PlaceBadge(badge, anchor, frame, portrait, outer, spot)
	badge:ClearAllPoints()
	local place = BADGE_POINTS[anchor] or BADGE_POINTS.OUTER_TOP
	place(badge, frame, portrait, outer, spot)
end

---------------------------------------------------------------------------
-- Aura effects for Core/AuraWidget.lua, from an Effects block.
---------------------------------------------------------------------------
function FX.AuraFX(effects)
	if type(effects) ~= "table" then return nil end
	local pop = type(effects.auraPop) == "table" and effects.auraPop.enabled and true or false
	local expiring = type(effects.auraExpiring) == "table" and effects.auraExpiring.enabled and effects.auraExpiring or nil
	if not pop and not expiring then return nil end
	local fx = { pop = pop }
	if expiring then
		local style = expiring.style or "PULSE"
		fx.pulse = style == "PULSE" or style == "BOTH"
		fx.red = (style == "TEXT" or style == "BOTH") and (tonumber(expiring.seconds) or 5) or nil
	end
	-- Motion follows General > Animations; the red time text is a color.
	if not Animations() then fx.pop, fx.pulse = false, false end
	if not fx.pop and not fx.pulse and not fx.red then return nil end
	return fx
end

---------------------------------------------------------------------------
-- "All frames": one value shared by every entry, or nil when they differ.
---------------------------------------------------------------------------
function FX.Shared(list, get)
	local value, first = nil, true
	for _, item in ipairs(list) do
		local v = get(item)
		if first then
			value, first = v, false
		elseif v ~= value then
			return nil
		end
	end
	return value
end
