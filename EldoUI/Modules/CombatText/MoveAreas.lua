-- Combat Text's own move mode (Move areas in the options, /eui sct move).
-- Only the scroll areas unlock, and each box shows what placing it needs:
--   * the edge where new lines appear, marked with a bar, and a chevron for
--     the way they travel;
--   * sample lines in the area's own font, size and animation, in a loop;
--   * a grip in the corner that resizes the area (width and height, with a
--     readout), keeping the opposite corner where it is;
--   * areas that are off, dimmed and tagged "Off", so they can be placed
--     before they are turned on;
--   * its own menu entries: show or hide the area, move only this area,
--     put every area back on its layout spot.
-- Positions are saved like every other mover: per profile, on the layout.
-- Written from scratch for EldoUI.
local _, E = ...
local L = E.L
local M = E:GetModule("CombatText")

local SAMPLE_EVERY = 0.9 -- seconds between sample lines in each area
local GRIP = 14

M.areaMode = false   -- Combat Text's own move mode is on
M.areaFocus = nil    -- one area key while only that area unlocks

local decor = {}     -- area key -> { bar, chevron, tag, grip, size }

local function Accent()
	local c = E.media.accentColor
	return c[1], c[2], c[3]
end

-- True while the scroll areas are being placed.
function M:AreaModeOn()
	return self.areaMode and E:IsMoveMode() and true or false
end

---------------------------------------------------------------------------
-- Box decoration
---------------------------------------------------------------------------
local function GripUpdate(grip)
	local key, mover = grip.key, grip.mover
	local area = M.db and M.db.areas[key]
	if not (area and mover) then return end
	local scale = mover:GetEffectiveScale()
	local x, y = GetCursorPosition()
	x, y = x / scale, y / scale
	local width = math.floor((x - grip.left) / 2 + 0.5) * 2
	local height = math.floor((grip.top - y) / 2 + 0.5) * 2
	width = math.max(60, math.min(800, width))
	height = math.max(30, math.min(600, height))
	if width == area.width and height == area.height then return end
	area.width, area.height = width, height
	local holder = M:GetAreaFrame(key)
	if holder then holder:SetSize(width, height) end
	-- The top-left corner stays where it was while the box grows.
	E:SaveMoverFromRect(mover.name, grip.left, grip.top - height)
	M:DecorateArea(key)
end

local function MakeGrip(entry, key, mover)
	local grip = CreateFrame("Button", nil, mover.overlay)
	grip:SetSize(GRIP, GRIP)
	grip:SetPoint("BOTTOMRIGHT", -1, 1)
	grip:SetFrameLevel(mover.overlay:GetFrameLevel() + 6)
	grip.key, grip.mover = key, mover
	local texture = grip:CreateTexture(nil, "OVERLAY")
	texture:SetAllPoints()
	texture:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	grip.texture = texture
	grip:SetScript("OnMouseDown", function(self, button)
		if button ~= "LeftButton" or InCombatLockdown() or E:IsMoverLocked(mover.name) then return end
		self.left, self.top = mover:GetLeft(), mover:GetTop()
		if not (self.left and self.top) then return end
		self:SetScript("OnUpdate", GripUpdate)
	end)
	grip:SetScript("OnMouseUp", function(self)
		self:SetScript("OnUpdate", nil)
		if M.active then E:RunOutOfCombat(function() M:ApplyAreas() end, "CombatText:resize") end
		E:RefreshConfig()
	end)
	grip:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		E.UIKit.TipTitle(GameTooltip, L["Resize"])
		E.UIKit.TipText(GameTooltip, L["Drag to change the area's width and height. The opposite corner stays put."])
		GameTooltip:Show()
	end)
	grip:SetScript("OnLeave", GameTooltip_Hide)
	entry.grip = grip
end

local function Entry(key)
	local entry = decor[key]
	local mover = E.movers[M.MoverName(key)]
	if not (mover and mover.overlay) then return nil end
	if entry and entry.mover == mover then return entry end
	entry = { mover = mover }
	local overlay = mover.overlay
	entry.bar = overlay:CreateTexture(nil, "OVERLAY")
	entry.bar:SetHeight(3)
	entry.chevron = E.UIKit.Chevron(overlay, "down", 14)
	entry.tag = E:CreateText(overlay, E.tokens.size.label)
	entry.size = E:CreateText(overlay, E.tokens.size.label)
	entry.size:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMRIGHT", -(GRIP + 4), 3)
	MakeGrip(entry, key, mover)
	decor[key] = entry
	return entry
end

local function SetShown(entry, shown)
	for _, part in ipairs({ entry.bar, entry.chevron, entry.tag, entry.size, entry.grip }) do part:SetShown(shown) end
end

-- Draw (or hide) one area's start edge, travel chevron, Off tag and size.
function M:DecorateArea(key)
	local entry = Entry(key)
	if not entry then return end
	local area = self.db and self.db.areas[key]
	if not (self:AreaModeOn() and area) then
		SetShown(entry, false)
		return
	end
	SetShown(entry, true)
	local overlay = entry.mover.overlay
	local up = area.direction == "up"
	local r, g, b = Accent()
	entry.bar:ClearAllPoints()
	entry.bar:SetPoint(up and "BOTTOMLEFT" or "TOPLEFT", overlay, up and "BOTTOMLEFT" or "TOPLEFT", 2, up and 2 or -2)
	entry.bar:SetPoint(up and "BOTTOMRIGHT" or "TOPRIGHT", overlay, up and "BOTTOMRIGHT" or "TOPRIGHT", -2, up and 2 or -2)
	entry.bar:SetColorTexture(r, g, b, area.enabled and 1 or 0.4)
	E.UIKit.SetGlyph(entry.chevron, up and "chevron-up" or "chevron-down")
	entry.chevron:ClearAllPoints()
	-- The chevron sits on the side the text lines up on, next to the bar.
	local side = area.align == "LEFT" and "LEFT" or (area.align == "RIGHT" and "RIGHT" or "")
	local corner = (up and "BOTTOM" or "TOP") .. side
	local dx = side == "LEFT" and 6 or (side == "RIGHT" and -6 or 0)
	entry.chevron:SetPoint(corner, overlay, corner, dx, up and 8 or -8)
	entry.chevron:SetVertexColor(r, g, b, area.enabled and 1 or 0.4)
	entry.tag:ClearAllPoints()
	entry.tag:SetPoint(up and "TOPLEFT" or "BOTTOMLEFT", overlay, up and "TOPLEFT" or "BOTTOMLEFT", 4, up and -3 or 3)
	if area.enabled then
		entry.tag:SetText(L["Lines start at the bar"])
		entry.tag:SetTextColor(unpack(E.tokens.text.secondary))
	else
		entry.tag:SetText(L["Off: right-click to show it"])
		entry.tag:SetTextColor(unpack(E.tokens.text.warn))
	end
	entry.size:SetText(("%d \195\151 %d"):format(area.width, area.height))
	entry.size:SetTextColor(unpack(E.tokens.text.secondary))
	overlay:SetAlpha(area.enabled and 1 or 0.55)
end

function M:DecorateAreas()
	for _, key in ipairs(self:AreaKeys()) do self:DecorateArea(key) end
	for key in pairs(decor) do
		if not (self.db and self.db.areas[key]) then SetShown(decor[key], false) end
	end
end

---------------------------------------------------------------------------
-- Sample lines
---------------------------------------------------------------------------
local sampler = CreateFrame("Frame")
sampler:Hide()
local elapsedSince, turn = 0, 0

local GREEN, RED, WHITE = { 0.3, 1, 0.3 }, { 1, 0.3, 0.3 }, { 1, 1, 1 }

local function SampleLine(key)
	local area = M.db.areas[key]
	if not (area and area.enabled) then return end
	if key == "incoming" then
		if turn % 2 == 0 then
			M:Show("-" .. M:FormatNumber(1234), key, { color = RED })
		else
			M:Show("+" .. M:FormatNumber(567), key, { color = GREEN })
		end
	elseif key == "target" then
		M:Show(M:FormatNumber(2468), key, { color = WHITE, sticky = turn % 4 == 0 })
	else
		M:Show(L["%s: sample line"]:format(M:AreaTitle(key)), key, { color = E.media.accentColor })
	end
end

sampler:SetScript("OnUpdate", function(self, elapsed)
	if not M:AreaModeOn() or InCombatLockdown() then
		self:Hide()
		return
	end
	elapsedSince = elapsedSince + elapsed
	if elapsedSince < SAMPLE_EVERY then return end
	elapsedSince = 0
	turn = turn + 1
	for _, key in ipairs(M:AreaKeys()) do
		if not M.areaFocus or M.areaFocus == key then SampleLine(key) end
	end
end)

---------------------------------------------------------------------------
-- The mode
---------------------------------------------------------------------------
local function Filter(mover)
	if not mover.name:find("^EldoUI_SCT") then return false end
	return not M.areaFocus or mover.name == M.MoverName(M.areaFocus)
end

-- Open Combat Text's move mode: every area, or only `key`. A second call
-- closes it.
function M:MoveAreas(key)
	if InCombatLockdown() then
		E:Print(L["Frames can't be moved in combat."])
		return
	end
	if E:IsMoveMode() then
		E:ToggleMoveMode(false)
		return
	end
	if not self.active then
		E:Print(E:ModuleOffHint("CombatText"))
		return
	end
	local conflict, title = self:Conflict()
	if conflict then
		E:Print(L["%s is loaded, so EldoUI's scrolling text stays off."]:format(title))
		return
	end
	self.areaMode = true
	self.areaFocus = type(key) == "string" and self.db.areas[key] and key or nil
	self:ApplyAreas()
	E:ToggleMoveMode(true, Filter)
	if not E:IsMoveMode() then
		self.areaMode, self.areaFocus = false, nil
		self:ApplyAreas()
		return
	end
	self:DecorateAreas()
	if self.areaFocus then
		local mover = E.movers[self.MoverName(self.areaFocus)]
		if mover and E.SelectMover then E:SelectMover(mover) end
	end
	elapsedSince, turn = SAMPLE_EVERY, 0
	sampler:Show()
end

-- Leaving move mode (Done, Escape, combat) ends the area mode too.
hooksecurefunc(E, "ToggleMoveMode", function()
	if E:IsMoveMode() or not M.areaMode then return end
	M.areaMode, M.areaFocus = false, nil
	sampler:Hide()
	if M.active then
		M:ReleaseAll()
		E:RunOutOfCombat(function() M:ApplyAreas() end, "CombatText:areaMode")
	end
	M:DecorateAreas()
end)

-- Put every area back on its layout spot.
function M:ResetAreaPositions()
	for _, key in ipairs(self:AreaKeys()) do E:ResetMover(self.MoverName(key)) end
end

-- The box menu's Combat Text entries.
function M.AreaMenu(root, mover)
	local key
	for _, areaKey in ipairs(M:AreaKeys()) do
		if M.MoverName(areaKey) == mover.name then key = areaKey end
	end
	local area = key and M.db.areas[key]
	if not area then return end
	root:CreateDivider()
	root:CreateCheckbox(L["Show this area"], function() return area.enabled end, function()
		area.enabled = not area.enabled
		E:RunOutOfCombat(function()
			M:ApplyAreas()
			M:DecorateAreas()
		end, "CombatText:areaToggle")
		E:RefreshConfig()
	end)
	if M:AreaModeOn() and not M.areaFocus then
		root:CreateButton(L["Move only this area"], function()
			E:ToggleMoveMode(false)
			M:MoveAreas(key)
		end)
	end
	root:CreateButton(L["Reset every area"], function() M:ResetAreaPositions() end)
end
