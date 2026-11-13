-- Encounter Timeline: the Soon slot and the countdown sound.
--
-- In its last seconds (bigIcon.seconds) the next event leaves the bar and
-- shows as a big icon at the bar's now end, inside the timeline frame: a
-- clock swipe, a big number in the stage color, a glow from the danger
-- time (General > Glows: Encounter Timeline) and a short pop-in. With
-- "Side by side" above 1 the next ones line up away from the bar, 4 px
-- apart; events beyond the slots stay on the bar. Bar.lua's FrameLayout
-- places the slots; the name line sits under the first one.
--
-- The countdown sound (off by default) plays a tick each second from
-- sound.from to 1 and a final sound at 0, for the soonest event only
-- (Store.lua finds the crossings). Blizzard's countdown kits by default,
-- any EldoUI or LibSharedMedia sound through the media rows. No voices are
-- bundled.
local _, E = ...
local M = E:GetModule("EncounterTimeline")

local POP_TIME = 0.15
local POP_FROM = 0.8
local GAP = 4

-- The big icons inside the timeline frame (Core.lua makes the frame).
function M:CreateSoon(parent)
	local soon = CreateFrame("Frame", "EldoUI_EncounterTimelineBig", parent)
	soon:SetAllPoints(parent)
	soon:EnableMouse(false)
	local content = CreateFrame("Frame", nil, soon)
	content:SetAllPoints()
	content:EnableMouse(false)
	content:Hide()
	soon.content = content
	soon.slots = {}
	self.soon = soon
	return soon
end

local function SlotEnter(slot) M:ShowTooltip(slot, slot.row) end

local function NewSlot(soon, index)
	local slot = CreateFrame("Frame", nil, soon.content)
	E:SetTemplate(slot)
	slot.tex = slot:CreateTexture(nil, "ARTWORK")
	E:Hairline(slot.tex, "inset", 1)
	E:TrimIcon(slot.tex)
	slot.cd = CreateFrame("Cooldown", nil, slot, "CooldownFrameTemplate")
	slot.cd:SetAllPoints(slot.tex)
	if slot.cd.SetReverse then slot.cd:SetReverse(true) end
	if slot.cd.SetDrawEdge then slot.cd:SetDrawEdge(false) end
	if slot.cd.SetDrawBling then slot.cd:SetDrawBling(false) end
	if slot.cd.SetHideCountdownNumbers then slot.cd:SetHideCountdownNumbers(true) end
	slot.cd:EnableMouse(false)
	-- Numbers above the swipe.
	slot.top = CreateFrame("Frame", nil, slot)
	slot.top:SetAllPoints()
	slot.top:SetFrameLevel(slot.cd:GetFrameLevel() + 2)
	slot.top:EnableMouse(false)
	slot.num = slot.top:CreateFontString(nil, "OVERLAY")
	slot.num:SetPoint("CENTER")
	slot.name = E:CreateText(slot.top, E.tokens.size.label)
	slot.name:SetPoint("TOP", slot, "BOTTOM", 0, -2)
	slot:SetScript("OnEnter", SlotEnter)
	slot:SetScript("OnLeave", GameTooltip_Hide)
	slot:EnableMouse(false)
	slot.index = index
	slot:Hide()
	soon.slots[index] = slot
	return slot
end

function M:ApplySoonLook()
	local soon = self.soon
	if not soon then return end
	local s = self.cache or self:Settings()
	local layout = self:FrameLayout(s)
	for index = 1, 3 do
		local slot = soon.slots[index] or NewSlot(soon, index)
		slot:SetSize(s.bigSize, s.bigSize)
		slot:ClearAllPoints()
		slot:SetPoint("CENTER", soon, "BOTTOMLEFT", layout.slotX + (index - 1) * layout.stepX,
			layout.slotY + (index - 1) * layout.stepY)
		E:SetTemplate(slot)
		E:SetHeaderFont(slot.num, math.floor(s.bigSize * 0.375 + 0.5))
		E:SetMediaFont(slot.name, s.font, s.fontSize)
		slot.name:SetWidth(s.bigSize + 40)
		slot.cd:SetDrawSwipe(s.bigSwipe)
		slot:EnableMouse(s.tooltip ~= "off")
		if slot.row then self:PaintSlot(slot, slot.row, s) end
	end
	self:ShowContent()
end

function M:PaintSlot(slot, row, s)
	slot.tex:SetTexture(row.icon or M.QUESTION_ICON)
	local c = self:BorderColor(row, s)
	slot:SetBackdropBorderColor(c[1], c[2], c[3], 1)
	slot.name:SetShown(s.bigName)
	if s.bigName then slot.name:SetText(M.DisplayText(row.text, "")) end
end

function M:ReleaseSoonSlot(row)
	local soon = self.soon
	if not soon then return end
	for _, slot in ipairs(soon.slots) do
		if slot.row == row then self:ClearSlot(slot) end
	end
end

function M:ClearSlot(slot)
	slot.row = nil
	slot.glowing = nil
	E:HideGlow(slot)
	if slot.cd.Clear then slot.cd:Clear() end
	slot:SetScale(1)
	slot:Hide()
end

local list, inSoon = {}, {}

-- The rows the big icons show, soonest first: inside bigIcon.seconds,
-- still running, at most bigIcon.max. Returns a set of them too (the bar
-- leaves them out).
function M:SoonRows(rows, s)
	wipe(list)
	wipe(inSoon)
	if s.big and self.soon and self.soon.content:IsShown() then
		for _, row in ipairs(rows) do
			if #list >= s.bigMax then break end
			if row.left > 0 and row.left <= s.bigSeconds and not row.stopping and not row.ending then
				list[#list + 1] = row
				inSoon[row] = true
			end
		end
	end
	return inSoon, list
end

-- Every frame: the big icons, from the list SoonRows made for the bar.
function M:LayoutSoon(now, numbers)
	local soon = self.soon
	if not soon then return end
	local s = self.cache
	if not self.bar.content:IsShown() then self:SoonRows(self.shownList or {}, s) end
	for index, slot in ipairs(soon.slots) do
		local row = list[index]
		if not row then
			if slot.row then self:ClearSlot(slot) end
		else
			if slot.row ~= row then
				-- A new event entered the slot.
				if slot.row then self:ClearSlot(slot) end
				slot.row = row
				slot.popStart = now
				slot.cdStart, slot.cdDuration, slot.cdPaused = nil, nil, nil
				self:PaintSlot(slot, row, s)
				if not row.sample then self.stats.soon = self.stats.soon + 1 end
			end
			-- The swipe follows the timer, frozen while it is paused.
			if slot.cdStart ~= row.start or slot.cdDuration ~= row.duration then
				slot.cdStart, slot.cdDuration = row.start, row.duration
				slot.cd:SetCooldown(row.start, row.duration)
				slot.cdPaused = nil
			end
			local paused = row.pausedAt ~= nil
			if paused ~= (slot.cdPaused or false) then
				slot.cdPaused = paused
				if paused and slot.cd.Pause then slot.cd:Pause() elseif not paused and slot.cd.Resume then slot.cd:Resume() end
			end
			slot.tex:SetDesaturated(paused and not row.sample)
			slot:SetAlpha((paused and not row.sample) and E.tokens.disabledAlpha or 1)
			-- Pop-in
			local scale = 1
			if s.motion and slot.popStart then
				local t = (now - slot.popStart) / POP_TIME
				if t < 1 then scale = POP_FROM + (1 - POP_FROM) * math.max(t, 0) end
			end
			slot:SetScale(scale)
			-- Glow from the danger time
			local glow = s.bigGlow and row.left <= s.bad
			if glow and not slot.glowing then
				slot.glowing = true
				E:ShowUserGlow(slot, "encounterTimeline")
				if not row.sample then self.stats.glow = self.stats.glow + 1 end
			elseif not glow and slot.glowing then
				slot.glowing = nil
				E:HideGlow(slot)
			end
			if numbers then
				slot.num:SetText(self:FormatSeconds(row.left, s.tenths))
				local stage = self:Stage(row.left, s)
				-- The event left the bar: its color stages count here.
				if stage ~= row.stage and not row.sample then
					if stage == "warn" then self.stats.warn = self.stats.warn + 1 end
					if stage == "bad" then self.stats.bad = self.stats.bad + 1 end
				end
				row.stage = stage
				local c = self:StageColor(stage)
				slot.num:SetTextColor(c[1], c[2], c[3])
			end
			slot:Show()
		end
	end
	soon.shownCount = #list
end

---------------------------------------------------------------------------
-- Countdown sound
---------------------------------------------------------------------------
function M:PlayCountdown(final)
	local sound = self.db.sound
	if final then
		self.stats.final = self.stats.final + 1
	else
		self.stats.sound = self.stats.sound + 1
	end
	E:PlayMedia(final and sound.final or sound.tick, sound.channel)
end
