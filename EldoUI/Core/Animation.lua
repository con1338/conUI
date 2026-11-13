-- EldoUI animations: one shared slide-and-fade, so loot windows, toasts and
-- popups all move the same way. Frames get an AnimationGroup once and
-- reuse it.
--
--   E:SlideIn(frame, "LEFT")   -- slides 24 px in from the left while fading in
--   E:SlideOut(frame, "RIGHT", function() ... end)  -- fades out, then hides
--   E:FadeIn(frame, 0.15)      -- fades a shown frame in (unit frames, cast bars)
local _, E = ...

E.defaults.general.animations = true

-- Motion: General > Animations and Accessibility > Reduce motion are one
-- saved setting. With motion reduced, glows hold a steady border, pulses
-- and flashes hold a steady highlight and nothing slides; every highlight
-- still shows.
--   E:MotionOn()              false while motion is reduced
--   E:SetReduceMotion(on)
--   E:OnMotionChanged(fn)     fn(motionOn) runs when the setting flips
function E:MotionOn()
	return not (self.db and self.db.general and self.db.general.animations == false)
end

local motionWatchers, shownMotion = {}, nil

function E:OnMotionChanged(fn)
	motionWatchers[#motionWatchers + 1] = fn
end

-- Runs the watchers once per flip (the General page, the Accessibility
-- page and a profile change all call it).
function E:MotionChanged()
	local now = self:MotionOn()
	if now == shownMotion then return end
	local first = shownMotion == nil
	shownMotion = now
	if first then return end
	for _, fn in ipairs(motionWatchers) do fn(now) end
end

function E:SetReduceMotion(on)
	if not (self.db and self.db.general) then return end
	self.db.general.animations = not on
	self:MotionChanged()
end

if E.SetProfile then hooksecurefunc(E, "SetProfile", function() E:MotionChanged() end) end
if E.RegisterEvent then E:RegisterEvent("PLAYER_LOGIN", function() E:MotionChanged() end, motionWatchers) end

local OFFSETS = { LEFT = { -24, 0 }, RIGHT = { 24, 0 }, UP = { 0, 24 }, DOWN = { 0, -24 } }
local DURATION = 0.22

-- Translation animations end where they started, so the frame's real
-- position never changes: "in" jumps out by the offset and glides back,
-- "out" glides away while fading and then hides.
local function Group(frame, key)
	frame.eldoAnim = frame.eldoAnim or {}
	local group = frame.eldoAnim[key]
	if not group then
		group = frame:CreateAnimationGroup()
		group.jump = group:CreateAnimation("Translation")
		group.jump:SetOrder(1)
		group.jump:SetDuration(0.001)
		group.move = group:CreateAnimation("Translation")
		group.move:SetOrder(2)
		group.move:SetSmoothing("OUT")
		group.fade = group:CreateAnimation("Alpha")
		group.fade:SetOrder(2)
		group.fade:SetSmoothing("OUT")
		frame.eldoAnim[key] = group
	end
	group:Stop()
	return group
end

function E:SlideIn(frame, from)
	if frame.eldoAnim and frame.eldoAnim.out then frame.eldoAnim.out:Stop() end
	frame:SetAlpha(1)
	frame:Show()
	if not self.db.general.animations then return end
	local dx, dy = unpack(OFFSETS[from or "DOWN"])
	local group = Group(frame, "in")
	group.jump:SetOffset(dx, dy)
	group.move:SetOffset(-dx, -dy)
	group.move:SetDuration(DURATION)
	group.fade:SetFromAlpha(0)
	group.fade:SetToAlpha(1)
	group.fade:SetDuration(DURATION)
	group:SetScript("OnFinished", nil)
	group:Play()
end

function E:SlideOut(frame, to, onDone)
	if frame.eldoAnim and frame.eldoAnim["in"] then frame.eldoAnim["in"]:Stop() end
	if not self.db.general.animations or not frame:IsShown() then
		frame:Hide()
		if onDone then onDone() end
		return
	end
	local dx, dy = unpack(OFFSETS[to or "DOWN"])
	local group = Group(frame, "out")
	group.jump:SetOffset(0, 0)
	group.move:SetOffset(dx, dy)
	group.move:SetDuration(DURATION)
	group.fade:SetFromAlpha(frame:GetAlpha())
	group.fade:SetToAlpha(0)
	group.fade:SetDuration(DURATION)
	group:SetScript("OnFinished", function()
		frame:Hide()
		if onDone then onDone() end
	end)
	group:Play()
end

-- Pop: the frame grows from `fromScale` to a little over full size and
-- settles (two steps, each under 0.4 s), for attention-grabbing toasts.
function E:PopIn(frame, fromScale)
	if frame.eldoAnim and frame.eldoAnim.out then frame.eldoAnim.out:Stop() end
	frame:SetAlpha(1)
	frame:Show()
	if not self.db.general.animations then return end
	frame.eldoAnim = frame.eldoAnim or {}
	local group = frame.eldoAnim.pop
	if not group then
		group = frame:CreateAnimationGroup()
		group.grow = group:CreateAnimation("Scale")
		group.grow:SetOrder(1)
		group.grow:SetSmoothing("OUT")
		group.settle = group:CreateAnimation("Scale")
		group.settle:SetOrder(2)
		group.settle:SetSmoothing("IN_OUT")
		group.fade = group:CreateAnimation("Alpha")
		group.fade:SetOrder(1)
		group.fade:SetFromAlpha(0)
		group.fade:SetToAlpha(1)
		frame.eldoAnim.pop = group
	end
	group:Stop()
	local from = fromScale or 0.6
	local peak = 1.15
	group.grow:SetScaleFrom(from, from)
	group.grow:SetScaleTo(peak, peak)
	group.grow:SetDuration(0.15)
	group.settle:SetScaleFrom(peak, peak)
	group.settle:SetScaleTo(1, 1)
	group.settle:SetDuration(0.1)
	group.fade:SetDuration(0.15)
	group:Play()
end

-- Fade in: an alpha animation from transparent to opaque over
-- `duration` seconds (0.15 by default, 0.05 to 0.5); when it ends the
-- frame's own alpha applies again. It never shows, hides or moves the
-- frame and never writes its alpha, so it is safe on secure unit buttons
-- in combat and leaves the fader's alpha alone. Call it after the frame
-- is shown. Returns true when it plays (false with animations off).
function E:FadeIn(frame, duration)
	if type(frame) ~= "table" or not frame.CreateAnimationGroup then return false end
	frame.eldoAnim = frame.eldoAnim or {}
	local group = frame.eldoAnim.fadeIn
	if group then group:Stop() end
	if not self.db.general.animations then return false end
	if not group then
		group = frame:CreateAnimationGroup()
		group.fade = group:CreateAnimation("Alpha")
		group.fade:SetFromAlpha(0)
		group.fade:SetToAlpha(1)
		group.fade:SetSmoothing("OUT")
		frame.eldoAnim.fadeIn = group
	end
	duration = tonumber(duration) or 0.15
	group.fade:SetDuration(math.max(0.05, math.min(0.5, duration)))
	group:Play()
	return true
end

---------------------------------------------------------------------------
-- Screen flash: one shared full-screen frame, so modules never stack
-- flashes. Capped for photosensitivity: at most one flash per 0.5 s and
-- three per 3 s, alpha at most 0.6 (0.25 for a full-screen tint), never loops.
--   E:ScreenFlash({ r, g, b }, alpha, duration, style)  style: edges, vignette, full
---------------------------------------------------------------------------
local flashFrame
local flashTimes = {}

local function FlashFrame()
	if flashFrame then return flashFrame end
	local frame = CreateFrame("Frame", nil, UIParent)
	frame:SetAllPoints()
	frame:SetFrameStrata("FULLSCREEN_DIALOG")
	frame:EnableMouse(false)
	frame:Hide()
	local function Edge(p1, p2, w, h)
		local texture = frame:CreateTexture(nil, "OVERLAY")
		texture:SetTexture(E.media.flat)
		texture:SetPoint(p1)
		texture:SetPoint(p2)
		if w then texture:SetWidth(w) else texture:SetHeight(h) end
		return texture
	end
	frame.edges = {
		top = Edge("TOPLEFT", "TOPRIGHT", nil, 40), bottom = Edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, 40),
		left = Edge("TOPLEFT", "BOTTOMLEFT", 40, nil), right = Edge("TOPRIGHT", "BOTTOMRIGHT", 40, nil),
	}
	frame.full = frame:CreateTexture(nil, "OVERLAY")
	frame.full:SetTexture(E.media.flat)
	frame.full:SetAllPoints()
	local group = frame:CreateAnimationGroup()
	group.fade = group:CreateAnimation("Alpha")
	group.fade:SetFromAlpha(1)
	group.fade:SetToAlpha(0)
	group:SetScript("OnFinished", function() frame:Hide() end)
	frame.group = group
	flashFrame = frame
	return frame
end

function E:ScreenFlash(color, alpha, duration, style)
	local now = GetTime()
	if flashTimes[#flashTimes] and now - flashTimes[#flashTimes] < 0.5 then return false end
	while flashTimes[1] and now - flashTimes[1] > 3 do table.remove(flashTimes, 1) end
	if #flashTimes >= 3 then return false end
	table.insert(flashTimes, now)

	local frame = FlashFrame()
	local r, g, b = 1, 0.1, 0.05
	if type(color) == "table" then r, g, b = color[1] or r, color[2] or g, color[3] or b end
	style = style or "edges"
	alpha = math.max(0, math.min(alpha or 0.35, style == "full" and 0.25 or 0.6))
	for side, texture in pairs(frame.edges) do
		texture:SetShown(style ~= "full")
		if style == "vignette" then
			-- Color at the screen edge, fading out towards the center.
			local size = 240
			if side == "top" or side == "bottom" then texture:SetHeight(size) else texture:SetWidth(size) end
			local from, to = CreateColor(r, g, b, alpha), CreateColor(r, g, b, 0)
			texture:SetVertexColor(1, 1, 1, 1)
			if side == "top" then texture:SetGradient("VERTICAL", to, from)
			elseif side == "bottom" then texture:SetGradient("VERTICAL", from, to)
			elseif side == "left" then texture:SetGradient("HORIZONTAL", from, to)
			else texture:SetGradient("HORIZONTAL", to, from) end
		else
			if side == "top" or side == "bottom" then texture:SetHeight(40) else texture:SetWidth(40) end
			local white = CreateColor(1, 1, 1, 1)
			texture:SetGradient("VERTICAL", white, white)
			texture:SetVertexColor(r, g, b, alpha)
		end
	end
	frame.full:SetShown(style == "full")
	frame.full:SetVertexColor(r, g, b, alpha)
	frame.group:Stop()
	frame.group.fade:SetDuration(self.db.general.animations and (duration or 0.4) or 0.15)
	frame:SetAlpha(1)
	frame:Show()
	frame.group:Play()
	return true
end
