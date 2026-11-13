-- EldoUI Chat, part 7: idle fades for the edit box and the tab strip.
--
--   * Edit box idle fade (skin switch): while the box is shown but has no
--     focus and no mouse over it, it fades to a chosen opacity. Focus or
--     the mouse brings it back at once.
--   * Tabs only on mouse-over (panel): the tabs and the side rail with its
--     Copy, Find and Errors buttons fade out while the mouse is away from
--     the chat.
--     A flashing tab (whisper in another tab) brings them back when
--     "Show the tabs while one flashes" is on.
--
-- Alpha only: no positions, no text, no focus is changed here, so all of
-- it is safe in combat. Fades are one Alpha animation per frame (no
-- OnUpdate), and every alpha goes back to 1 when an option or the module
-- is turned off. Written from scratch for EldoUI.
local _, E = ...

local M = E:GetModule("Chat")

local FADE_TIME = 0.25
local LEAVE_DELAY = 0.4

---------------------------------------------------------------------------
-- One Alpha animation per frame (kept in a local table: no field is
-- written on Blizzard's frames)
---------------------------------------------------------------------------
local groups = setmetatable({}, { __mode = "k" })

local function FadeTo(frame, alpha, instant)
	if not frame then return end
	local group = groups[frame]
	if group then group:Stop() end
	local from = frame:GetAlpha() or 1
	if instant or math.abs(from - alpha) < 0.01 or not frame.CreateAnimationGroup then
		frame:SetAlpha(alpha)
		return
	end
	if not group then
		group = frame:CreateAnimationGroup()
		group.fade = group:CreateAnimation("Alpha")
		group:SetScript("OnFinished", function(self) frame:SetAlpha(self.target or 1) end)
		groups[frame] = group
	end
	group.target = alpha
	group.fade:SetFromAlpha(from)
	group.fade:SetToAlpha(alpha)
	group.fade:SetDuration(FADE_TIME * math.abs(from - alpha))
	group:Play()
end
M.FadeTo = FadeTo

---------------------------------------------------------------------------
-- Edit box idle fade
---------------------------------------------------------------------------
local fadeHooked = setmetatable({}, { __mode = "k" })
local faded = setmetatable({}, { __mode = "k" })    -- edit boxes whose alpha EldoUI changed

local function WantsEditFade()
	return M.active and M:Allowed("skin") and M.db.editBoxFade
end

function M:UpdateEditFade(editBox)
	if not editBox then return end
	if not fadeHooked[editBox] then
		fadeHooked[editBox] = true
		local function Update() M:UpdateEditFade(editBox) end
		editBox:HookScript("OnEditFocusGained", Update)
		editBox:HookScript("OnEditFocusLost", Update)
		editBox:HookScript("OnEnter", Update)
		editBox:HookScript("OnLeave", Update)
		editBox:HookScript("OnShow", Update)
	end
	if not WantsEditFade() then
		if faded[editBox] then
			FadeTo(editBox, 1, true)
			faded[editBox] = nil
		end
		return
	end
	faded[editBox] = true
	local busy = editBox:HasFocus() or editBox:IsMouseOver()
	if busy then
		FadeTo(editBox, 1, true)
	else
		FadeTo(editBox, self.db.editBoxIdleAlpha)
	end
end

---------------------------------------------------------------------------
-- Tabs only on mouse-over
---------------------------------------------------------------------------
local hoverHooked = setmetatable({}, { __mode = "k" })
local flashing = setmetatable({}, { __mode = "k" })  -- chat frame -> true while its tab flashes
local tabsFaded = false
local leaveTimer

local function StripParts()
	local panel = M.panel
	if not panel then return {} end
	return { GeneralDockManager, panel.rail }
end

function M:WantsTabFade()
	return self.active and self:PanelMode() and self.db.tabsOnHover and true or false
end

function M:UpdateTabFade(instant)
	local panel = self.panel
	if not panel then return end
	if not self:WantsTabFade() then
		if tabsFaded then
			for _, part in ipairs(StripParts()) do FadeTo(part, 1, true) end
			panel.strip:SetAlpha(1)
			tabsFaded = false
		end
		return
	end
	tabsFaded = true
	local show = self.hover or self.paneShown ~= nil or (self.db.tabsOnHoverFlash and next(flashing) ~= nil)
	local alpha = show and 1 or 0
	for _, part in ipairs(StripParts()) do FadeTo(part, alpha, instant or show) end
	panel.strip:SetAlpha(alpha)
end

function M:OnChatHover(inside)
	if not self:WantsTabFade() then return end
	if leaveTimer then
		leaveTimer:Cancel()
		leaveTimer = nil
	end
	if inside then
		self.hover = true
		self:UpdateTabFade()
		return
	end
	-- Moving from a tab to the messages leaves one and enters the other:
	-- look again a moment later instead of fading at once.
	leaveTimer = C_Timer.NewTimer(LEAVE_DELAY, function()
		leaveTimer = nil
		M.hover = M.panel and M.panel:IsMouseOver() or false
		M:UpdateTabFade()
	end)
end

function M:HookHover(frame)
	if not frame or hoverHooked[frame] or not frame.HookScript then return end
	hoverHooked[frame] = true
	frame:HookScript("OnEnter", function() M:OnChatHover(true) end)
	frame:HookScript("OnLeave", function() M:OnChatHover(false) end)
end

function M:NoteTabFlash(frame, on)
	if not frame then return end
	flashing[frame] = on and true or nil
	self:UpdateTabFade()
end

---------------------------------------------------------------------------
-- Wiring (Core.lua: Apply and RestoreBlizzard)
---------------------------------------------------------------------------
function M:ApplyFades()
	local panel = self.panel
	if panel then
		self:HookHover(GeneralDockManager)
		for _, button in ipairs({ panel.copy, panel.search, panel.errors }) do self:HookHover(button) end
		if self.hover == nil then self.hover = panel:IsMouseOver() or false end
	end
	self:UpdateTabFade(true)
	for _, frame in self:IterateFrames() do
		local editBox = frame.editBox or _G[frame:GetName() .. "EditBox"]
		if editBox then self:UpdateEditFade(editBox) end
	end
end

function M:RestoreFades()
	if leaveTimer then
		leaveTimer:Cancel()
		leaveTimer = nil
	end
	for editBox in pairs(faded) do FadeTo(editBox, 1, true) end
	wipe(faded)
	if tabsFaded then
		for _, part in ipairs(StripParts()) do FadeTo(part, 1, true) end
		if self.panel then self.panel.strip:SetAlpha(1) end
		tabsFaded = false
	end
end
