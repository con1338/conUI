-- EldoUI Notifications: ready check, role poll, queue pop-ups and pings.
--
--   Skin     ready check, role poll, battleground ready dialog and PvP role
--            check in the EldoUI look (art invisible, panel behind)
--   Move     the ready check on its own mover; ping wheel scale (out of
--            combat only, the wheel runs in Blizzard's secure environment)
--   Replace  a compact EldoUI ready check: who asked, a countdown, and
--            Blizzard's own Ready / Not ready buttons moved into it (the
--            buttons need a real click, so they stay Blizzard's)
--   Improve  sound on the Master channel and a taskbar flash for ready
--            checks, role polls and queue pops; countdown bars; a
--            "not ready" summary in chat after a ready check; a dungeon
--            ready countdown when a group finder proposal shows
--
-- Nothing here ever accepts or declines anything: every answer is the
-- player's click on Blizzard's own button. Hide is not offered (hiding
-- accept dialogs breaks queues).
local _, E = ...
local L = E.L
local M = E:GetModule("Notifications")
local U = M.util

local ID = "ready-check-popups"
local LFG_PROPOSAL_SECONDS = 40   -- Blizzard's proposal dialog counts down from 40

-- Only this owner's constructed parts enter the Ready-area measurement.
-- Font strings use the existing generic read binding: they are not promoted
-- to the mover owner's intrinsic Frame/Texture class.
local authority = E.MoverAuthoritySource
local bindRead
if type(authority) == "function" then bindRead = select(6, authority()) end
local readyParts = {}
local readyGeneration = 0
local adopted = {}   -- button -> original parent, points and dimensions
local readyLabels = {}
local readingReady, readySerial = false, 0
local readyHolder, holderRead
local holderConstructor = U.Holder
local function Same(a, b)
	return not U.Secret(a) and not U.Secret(b) and rawequal(a, b)
end
local function Number(value)
	return not U.Secret(value) and type(value) == "number" and value == value and math.abs(value) < math.huge
end
local function ReadySource()
	return Same(E.MoverAuthoritySource, authority)
end
-- Returns the ready-check mover holder, or nil when it can't be read. The
-- callers then keep the game's own ready-check position instead.
local function OwnedReadyHolder()
	if not Same(rawget(U, "Holder"), holderConstructor) or type(bindRead) ~= "function" then return end
	local made, holder = pcall(holderConstructor, "ReadyCheck")
	if not made or U.Secret(holder) or type(holder) == "nil" then return end
	if readyHolder then
		if not Same(holder, readyHolder) then return end
		return holder
	end
	-- U.Holder completes its own CreateMover tagging before returning. Copy
	-- only intrinsic handles from this exact constructor result.
	local ok, read = pcall(bindRead, holder)
	if not ok or U.Secret(read) or type(read) ~= "table" or read.native ~= true
		or type(read.source) ~= "function" or not read.source() then return end
	local retained = { object = holder, source = read.source, capture = read.capture, getters = {} }
	for _, name in ipairs({ "GetParent", "IsShown", "IsVisible", "GetRect", "GetEffectiveScale" }) do
		local getter = rawget(read.getters, name)
		if U.Secret(getter) or type(getter) ~= "function" then return end
		retained.getters[name] = getter
	end
	readyHolder, holderRead = holder, retained
	readyGeneration = readyGeneration + 1
	return holder
end
-- Where the ready-check parts sit when the holder can't be read.
local function ReadyAnchor()
	return OwnedReadyHolder() or ReadyCheckFrame or UIParent
end

local function BindReadyPart(object, parent, text, button, field)
	if U.Secret(object) or U.Secret(parent) or type(object) == "nil" then return end
	if readyParts[object] then return end
	local ok, read = pcall(bindRead, object, text == true)
	if not ok or not read or (not text and read.native ~= true) then read = nil end
	readyParts[object] = { object = object, parent = parent, read = read, text = text == true, button = button, field = field }
	readyGeneration = readyGeneration + 1
end
-- The compact presenter owns the adopted label's point only for this lease.
-- A later label/parent/point change is left with its new owner on release.
local readyTextLeases = {}
local readyTextBusy = false
local function TextContext()
	local registry, db, settings, profile, active = rawget(E, "modules"), rawget(E, "db"), rawget(M, "db"), rawget(E, "profileName"), rawget(M, "active")
	if U.Secret(registry) or type(registry) ~= "table" or not Same(rawget(registry, "Notifications"), M)
		or U.Secret(db) or type(db) ~= "table" or U.Secret(settings) or type(settings) ~= "table"
		or U.Secret(profile) or U.Secret(active) or type(active) ~= "boolean" then return end
	return { registry = registry, db = db, settings = settings, profile = profile, active = active, generation = readyGeneration }
end
local function TextOwner(a, b)
	return a and b and Same(a.registry, b.registry) and Same(a.db, b.db)
		and Same(a.settings, b.settings) and Same(a.profile, b.profile)
end
local function TextContextCurrent(context)
	local current = TextContext()
	return TextOwner(context, current) and Same(current.active, context.active) and current.generation == context.generation
end
local function TextSeals(button, row)
	local label = row.label
	return row.read.source() and row.buttonRead.source()
		and Same(button.GetFontString, row.fontMethod)
		and Same(label.ClearAllPoints, row.clear) and Same(label.SetPoint, row.point)
		and Same(row.read.getters.GetParent(label), row.parent) and Same(row.parent, button)
		and row.read.source() and row.buttonRead.source()
end
local function ButtonPoints(button, row, returned)
	local read, saved = row.buttonRead, row.buttonLease
	local points = returned and saved.points or { saved.ownedPoint }
	local parent = returned and saved.parent or saved.ownedPoint[2]
	local width, height = returned and saved.width or 126, returned and saved.height or 22
	if returned and type(adopted[button]) ~= "nil" then return false end
	if not returned and not Same(adopted[button], saved) then return false end
	if not read.source() or not Same(read.getters.GetParent(button), parent)
		or not Same(read.getters.GetWidth(button), width) or not Same(read.getters.GetHeight(button), height)
		or not Same(read.getters.GetNumPoints(button), #points) then return false end
	for index, point in ipairs(points) do
		local current = { read.getters.GetPoint(button, index) }
		for field = 1, 5 do if not Same(current[field], point[field]) then return false end end
	end
	return read.source()
end
local function TextPoints(button, row, expected, context, returned)
	if not TextContextCurrent(context) or not TextSeals(button, row) then return false end
	-- Exhaust the ordinary label resolver before the final point/parent proof.
	if not Same(row.fontMethod(button), row.label) or not TextContextCurrent(context) or not TextSeals(button, row) then return false end
	local count = row.read.getters.GetNumPoints(row.label)
	if not Number(count) or count ~= #expected then return false end
	for index, saved in ipairs(expected) do
		local values = { row.read.getters.GetPoint(row.label, index) }
		for field = 1, 5 do if not Same(values[field], saved[field]) then return false end end
	end
	return ButtonPoints(button, row, returned) and TextContextCurrent(context) and TextSeals(button, row)
end
local function CenterReadyText(button)
	if readyTextBusy or (E.FrameCheck(button, "IsProtected") and InCombatLockdown()) then return end
	local known, buttonPart, context = readyLabels[button], readyParts[button], TextContext()
	if not context or not known or U.Secret(known.object) or type(known.object) == "nil" or not buttonPart or not buttonPart.read then return end
	local part = readyParts[known.object]
	if not part or not part.read or not part.read.source() or not buttonPart.read.source() then return end
	readyTextBusy = true
	pcall(function()
		local label = known.object
		local row = { label = label, parent = button, read = part.read, buttonRead = buttonPart.read, fontMethod = known.method,
			clear = label.ClearAllPoints, point = label.SetPoint, original = {}, buttonLease = adopted[button], owner = context }
		if U.Secret(row.clear) or type(row.clear) ~= "function" or U.Secret(row.point) or type(row.point) ~= "function"
			or not TextSeals(button, row) or not ButtonPoints(button, row, false) then return end
		-- Existing leases are never reclaimed from a later foreign point owner.
		if readyTextLeases[button] then return end
		if not Same(row.fontMethod(button), label) or not TextContextCurrent(context) or not TextSeals(button, row) then return end
		local count = row.read.getters.GetNumPoints(label)
		if not Number(count) or count < 0 or count % 1 ~= 0 then return end
		for index = 1, count do
			local point, relative, relativePoint, x, y = row.read.getters.GetPoint(label, index)
			if U.Secret(point) or type(point) ~= "string" or U.Secret(relative) or U.Secret(relativePoint)
				or type(relativePoint) ~= "string" or not Number(x) or not Number(y) then return end
			row.original[index] = { point, relative, relativePoint, x, y }
		end
		if not TextPoints(button, row, row.original, context, false) then return end
		row.clear(label)
		if not TextPoints(button, row, {}, context, false) then return end
		row.point(label, "CENTER", button, "CENTER", 0, 0)
		row.owned = { { "CENTER", button, "CENTER", 0, 0 } }
		if TextPoints(button, row, row.owned, context, false) then readyTextLeases[button] = row end
	end)
	readyTextBusy = false
end
local function RestoreReadyText()
	if readyTextBusy then return false end
	local context = TextContext()
	if not context then return false end
	readyTextBusy = true
	local completed = true
	for button, row in pairs(readyTextLeases) do
		-- GiveBack retains protected buttons; their label leases stay retained.
		if not adopted[button] then
			readyTextLeases[button] = nil
			local ok = pcall(function()
				if not TextPoints(button, row, row.owned, context, true) then return end
				row.clear(row.label)
				local prefix = {}
				if not TextPoints(button, row, prefix, context, true) then return end
				for _, point in ipairs(row.original) do
					if not TextPoints(button, row, prefix, context, true) then return end
					row.point(row.label, unpack(point, 1, 5))
					prefix[#prefix + 1] = point
				end
				TextPoints(button, row, prefix, context, true)
			end)
			if not ok then completed = false end
		end
	end
	readyTextBusy = false
	-- A callback may have opened a new presenter lease. Do not hide that panel.
	return completed and TextContextCurrent(context)
end

local function ReadyChanged()
	readyGeneration = readyGeneration + 1
	-- A completed owner transition may re-place Zone; measurement never does.
	if not U.Secret(M.active) and M.active == true and E.movers and E.movers.EldoUI_ZoneToast then
		E:ApplyMover("EldoUI_ZoneToast")
	end
end

function M:ReadyAreaBounds()
	local unavailable = { kind = "unavailable" }
	readySerial = readySerial + 1
	if readingReady then return unavailable end
	readingReady = true
	local serial = readySerial
	local ok, result = pcall(function()
		if not Same(self, M) or not ReadySource() or U.Secret(M.active) then return unavailable end
		local active = M.active
		-- A module that was never turned on this session has no state yet; it
		-- owns no ready-area parts, exactly like a module that was turned off.
		if active ~= nil and active ~= true and active ~= false then return unavailable end
		local db, settings, profile = E.db, M.db, E.profileName
		local measure = E.SurfaceMeasure
		if U.Secret(measure) or type(measure) ~= "function" then return unavailable end
		local generation = readyGeneration
		if U.Secret(db) or type(db) ~= "table" or U.Secret(settings) or type(settings) ~= "table" then return unavailable end
		local rows = {}
		for _, part in pairs(readyParts) do
			if active and (not part.button or adopted[part.button]) then
				local read = part.read
				if not read then return unavailable end
				rows[#rows + 1] = { part = part, seal = read.capture(true), lease = part.button and adopted[part.button] }
			end
		end
		local holderRow
		if readyHolder then
			if not holderRead or not holderRead.source() then return unavailable end
			holderRow = { part = { object = readyHolder, parent = UIParent, read = holderRead, holder = true },
				seal = holderRead.capture(true) }
			rows[#rows + 1] = holderRow
		end
		local function Current()
			if serial ~= readySerial or generation ~= readyGeneration or not ReadySource()
				or not Same(E.db, db) or not Same(M.db, settings)
				or not Same(E.profileName, profile) or not Same(M.active, active) or not Same(E.SurfaceMeasure, measure) then return false end
			for _, row in ipairs(rows) do
				local part = row.part
				if (part.holder and (not Same(readyHolder, part.object) or not Same(holderRead, part.read)
					or not Same(rawget(U, "Holder"), holderConstructor)))
					or (not part.holder and not Same(readyParts[part.object], part))
					or (part.button and not Same(adopted[part.button], row.lease))
					or not row.seal() or not part.read.source() then return false end
			end
			for _, row in ipairs(rows) do
				local part = row.part
				if part.field and not Same(part.parent[part.field], part.object) then return false end
				local label = readyLabels[part.object]
				if label and not Same(part.object.GetFontString, label.method) then return false end
			end
			return true
		end
		local function Call(row, method)
			if not Current() then error("Ready-area ownership changed") end
			local values = { row.part.read.getters[method](row.part.object) }
			if not Current() then error("Ready-area ownership changed") end
			return unpack(values)
		end
		if not Current() then return unavailable end
		-- Exhaust ordinary skin/label callbacks before the geometry proof. Their
		-- returned tables are copied; no callback runs during the final joint read.
		for _, row in ipairs(rows) do
			local part, edges = row.part, { 0, 0, 0, 0 }
			local label = readyLabels[part.object]
			if label and (not Same(label.method(part.object), label.object) or not Current()) then return unavailable end
			if not part.text and not part.holder then
				local paint = measure(E, part.object)
				if not Current() or U.Secret(paint) or type(paint) ~= "table" then return unavailable end
				edges = rawget(paint, "paint")
				if U.Secret(edges) or type(edges) ~= "table" then return unavailable end
			end
			row.edges = {}
			for index = 1, 4 do
				local value = rawget(edges, index)
				if not Number(value) or value < 0 then return unavailable end
				row.edges[index] = value
			end
		end
		local function Read(row)
			local parent = Call(row, "GetParent")
			local shown, visible = Call(row, "IsShown"), Call(row, "IsVisible")
			local l, b, w, h = Call(row, "GetRect")
			local scale = Call(row, "GetEffectiveScale")
			if not Same(parent, row.part.parent) or U.Secret(shown) or U.Secret(visible)
				or type(shown) ~= "boolean" or type(visible) ~= "boolean"
				or not (Number(l) and Number(b) and Number(w) and Number(h) and w >= 0 and h >= 0 and Number(scale) and scale > 0) then return end
			return { parent, shown, visible, l, b, w, h, scale }
		end
		-- Frame and texture reads are the game's own. Font string reads are taken
		-- as plain reads of text EldoUI owns. A getter that other code replaced
		-- could still change between reads.
		for _, row in ipairs(rows) do
			row.values = Read(row)
			if not row.values then return unavailable end
		end
		for _, row in ipairs(rows) do
			local values = Read(row)
			if not values then return unavailable end
			for index = 1, 8 do if not Same(values[index], row.values[index]) then return unavailable end end
		end
		if not Current() then return unavailable end
		local bounds
		for _, row in ipairs(rows) do
			local values, edges = row.values, row.edges
			if not row.part.holder and values[2] and values[3] then
				local l, b, w, h, scale = unpack(values, 4, 8)
				local rect = { (l - edges[1]) * scale, (b - edges[4]) * scale,
					(l + w + edges[2]) * scale, (b + h + edges[3]) * scale }
				for _, value in ipairs(rect) do if not Number(value) then return unavailable end end
				if not bounds then bounds = rect else
					bounds[1], bounds[2] = math.min(bounds[1], rect[1]), math.min(bounds[2], rect[2])
					bounds[3], bounds[4] = math.max(bounds[3], rect[3]), math.max(bounds[4], rect[4])
				end
			end
		end
		local holder
		if holderRow then
			local values = holderRow.values
			local l, b, w, h, scale = unpack(values, 4, 8)
			holder = { l * scale, b * scale, (l + w) * scale, (b + h) * scale }
			for _, value in ipairs(holder) do if not Number(value) then return unavailable end end
		end
		if not bounds then return { kind = "none", holder = holder } end
		return { kind = "shown", bounds = bounds, holder = holder }
	end)
	readingReady = false
	if not ok then return unavailable end
	return result
end

---------------------------------------------------------------------------
-- Countdown bars (EldoUI frames; a child of a Blizzard dialog is our own frame)
---------------------------------------------------------------------------
-- Every running bar moves once a second on the shared ticker (one
-- subscription for all of them, none while no bar runs); the seconds are
-- written once a second too.
local COUNTDOWN = "Notifications:countdown"
local running = {}   -- bar -> true while it counts down

local function Step(bar, left)
	bar:SetValue(left)
	if bar.text then bar.text:SetText(("%d"):format(math.ceil(left))) end
end

local function TickCountdowns()
	local now, done = GetTime(), {}
	for bar in pairs(running) do
		local left = bar.expires and (bar.expires - now)
		if not left or not bar:IsShown() then
			running[bar] = nil
		elseif left <= 0 then
			running[bar] = nil
			done[#done + 1] = bar
		else
			Step(bar, left)
		end
	end
	for _, bar in ipairs(done) do
		bar.expires = nil
		bar:Hide()
		if bar.onDone then bar.onDone() end
	end
	if next(running) == nil then E.Ticker:Unsubscribe(COUNTDOWN) end
end

local function CreateCountdown(parent, name)
	local bar = E:CreateStatusBar(parent, name)
	bar:SetHeight(4)
	bar:Hide()
	return bar
end

local function StopCountdown(bar)
	if not bar then return end
	running[bar] = nil
	bar.expires = nil
	bar:Hide()
	-- Another countdown or a new one started by OnHide keeps the shared ticker.
	if next(running) == nil then E.Ticker:Unsubscribe(COUNTDOWN) end
end

local function StartCountdown(bar, seconds)
	if not bar or not seconds or seconds <= 0 then
		StopCountdown(bar)
		return
	end
	bar:SetStatusBarColor(U.Accent())
	bar:SetMinMaxValues(0, seconds)
	bar.expires = GetTime() + seconds
	Step(bar, seconds)
	bar:Show()
	running[bar] = true
	if not E.Ticker:IsSubscribed(COUNTDOWN) then E.Ticker:Subscribe(COUNTDOWN, 1, TickCountdowns, "Notifications") end
end

local function Alert()
	local db = M.db.popups
	if not U.Allowed(ID, "improve") then return end
	if db.masterSound then M:PlayPopupSound() end
	if db.flash and FlashClientIcon then FlashClientIcon() end
end

-- The pop-up sound (ready check, role poll, battleground and dungeon
-- ready), on the Master channel so it plays with game sounds off.
function M:PlayPopupSound()
	E:PlayMedia(self.db.popups.soundID, "Master", { fallback = "kit:READY_CHECK" })
end

---------------------------------------------------------------------------
-- Skin (not undoable without a reload: art is set to alpha 0)
---------------------------------------------------------------------------
local skinned = {}

local function SkinDialog(frame, buttons)
	if not frame or skinned[frame] then return end
	skinned[frame] = true
	E:SkinPanel(frame, { accentLine = false, title = true })
	if frame.Border then E:SkinAlphaZero(frame.Border) end
	for _, button in ipairs(buttons) do
		if button then E:SkinButton(button) end
	end
end

local function SkinAll()
	if ReadyCheckListenerFrame then
		SkinDialog(ReadyCheckListenerFrame, { ReadyCheckFrameYesButton, ReadyCheckFrameNoButton })
		if ReadyCheckListenerFrame.PortraitContainer then E:SkinAlphaZero(ReadyCheckListenerFrame.PortraitContainer) end
		if ReadyCheckListenerFrame.Text then U.SkinFont(ReadyCheckListenerFrame.Text, 13) end
	end
	if RolePollPopup then
		SkinDialog(RolePollPopup, { RolePollPopup.acceptButton })
		if RolePollPopup.CloseButton then E:SkinCloseButton(RolePollPopup.CloseButton) end
	end
	-- The battleground "enter battle" popup is owned here (Social's PvP
	-- page points to this element).
	if PVPReadyDialog then
		SkinDialog(PVPReadyDialog, { PVPReadyDialog.enterButton, PVPReadyDialog.leaveButton })
		E:SkinAlphaZero(PVPReadyDialog.background, PVPReadyDialog.bottomArt)
		if PVPReadyDialog.label then U.SkinFont(PVPReadyDialog.label, 14) end
		if PVPReadyDialog.roleLabel then U.SkinFont(PVPReadyDialog.roleLabel, 16) end
		if PVPReadyDialog.roleDescription then U.SkinFont(PVPReadyDialog.roleDescription, 11) end
		if _G.PVPReadyDialogCloseButton then E:SkinCloseButton(_G.PVPReadyDialogCloseButton) end
	end
	if PVPRoleCheckPopup then
		SkinDialog(PVPRoleCheckPopup, { _G.PVPRoleCheckPopupAcceptButton, _G.PVPRoleCheckPopupDeclineButton })
	end
end

---------------------------------------------------------------------------
-- Replace: compact EldoUI ready check holding Blizzard's buttons
---------------------------------------------------------------------------
local panel

local function CreatePanel()
	panel = CreateFrame("Frame", "EldoUI_ReadyCheckPanel", UIParent)
	panel:SetSize(280, 84)
	panel:SetFrameStrata("FULLSCREEN_DIALOG")
	panel:Hide()
	E:SetPanelTemplate(panel)
	-- The dialog shell's header-font title and body text (E.UIKit).
	panel.title = E.UIKit.Title(panel, E.tokens.size.dialogTitle, "CENTER")
	panel.title:SetPoint("TOP", 0, -8)
	panel.text = E.UIKit.Text(panel, E.tokens.size.label, "CENTER")
	-- The body names who started the check: the name font keeps every alphabet.
	E:UseNameFont(panel.text)
	panel.text:SetPoint("TOP", panel.title, "BOTTOM", 0, -4)
	panel.bar = CreateCountdown(panel)
	panel.bar:SetPoint("TOPLEFT", 8, -44)
	panel.bar:SetPoint("TOPRIGHT", -8, -44)
	panel.bar.text = nil
	BindReadyPart(panel, UIParent)
	BindReadyPart(panel.title, panel, true, nil, "title")
	BindReadyPart(panel.text, panel, true, nil, "text")
	BindReadyPart(panel.bar, panel, false, nil, "bar")
	BindReadyPart(panel.bar.bg, panel.bar, false, nil, "bg")
	return panel
end

local function Adopt(button, point, x)
	if not button or adopted[button] then return end
	local points = {}
	for index = 1, button:GetNumPoints() do points[index] = { button:GetPoint(index) } end
	adopted[button] = { parent = button:GetParent(), points = points, width = button:GetWidth(), height = button:GetHeight(), ownedPoint = { point, panel, "BOTTOM", x, 8 } }
	button:SetParent(panel)
	button:ClearAllPoints()
	button:SetPoint(point, panel, "BOTTOM", x, 8)
	button:SetSize(126, 22)
	BindReadyPart(button, panel, false, button)
	if not readyLabels[button] then
		local method = button.GetFontString
		local label = method(button)
		readyLabels[button] = { method = method, object = label }
		if label then BindReadyPart(label, button, true, button) end
	end
	CenterReadyText(button)
end

local function GiveBack()
	for button, saved in pairs(adopted) do
		if not (E.FrameCheck(button, "IsProtected") and InCombatLockdown()) then
			button:SetParent(saved.parent)
			button:ClearAllPoints()
			for _, point in ipairs(saved.points) do button:SetPoint(unpack(point)) end
			button:SetSize(saved.width, saved.height)
			adopted[button] = nil
		end
	end
	if ReadyCheckListenerFrame then
		U.RestoreAlpha(ReadyCheckListenerFrame)
	end
	if panel then
		if not RestoreReadyText() then return end
		StopCountdown(panel.bar)
		panel:Hide()
	end
	ReadyChanged()
end

local readyCheck = {}  -- initiator, timeLeft, started, notReady

function M:ShowReadyPanel()
	if not (U.Allowed(ID, "replace") and ReadyCheckListenerFrame and ReadyCheckListenerFrame:IsShown()) then return end
	if not panel then CreatePanel() end
	panel:ClearAllPoints()
	panel:SetPoint("CENTER", U.Allowed(ID, "move") and OwnedReadyHolder() or ReadyCheckFrame or UIParent, "CENTER")
	panel:SetScale(U.Allowed(ID, "move") and self.db.popups.scale or 1)
	E:SetPanelTemplate(panel)
	panel.title:SetText(L["Ready check"])
	local initiator = U.Safe(readyCheck.initiator)
	if initiator then
		local _, class = UnitClass(initiator)
		local color = E:ClassColorObject(class)
		local name = UnitName(initiator) or initiator
		panel.text:SetText(color and color:WrapTextInColorCode(name) or name)
	else
		panel.text:SetText("")
	end
	local left = readyCheck.timeLeft and readyCheck.started and (readyCheck.timeLeft - (GetTime() - readyCheck.started))
	StartCountdown(panel.bar, left)
	U.SetAlpha(ReadyCheckListenerFrame, 0)
	Adopt(ReadyCheckFrameYesButton, "BOTTOMRIGHT", -3)
	Adopt(ReadyCheckFrameNoButton, "BOTTOMLEFT", 3)
	E:SlideIn(panel, "DOWN")
	ReadyChanged()
end

---------------------------------------------------------------------------
-- Improve: countdown on Blizzard's ready check, sounds, summary, BG pop and
-- dungeon proposal timers.
---------------------------------------------------------------------------
local readyBar, pvpBar, proposalBar

local function ReadyBar()
	if not readyBar and ReadyCheckListenerFrame then
		readyBar = CreateCountdown(ReadyCheckListenerFrame)
		readyBar:SetPoint("BOTTOMLEFT", 10, 6)
		readyBar:SetPoint("BOTTOMRIGHT", -10, 6)
	end
	return readyBar
end

U.On("READY_CHECK", function(_, initiator, timeLeft)
	readyCheck.initiator = initiator
	readyCheck.timeLeft = U.Safe(timeLeft)
	readyCheck.started = GetTime()
	readyCheck.notReady = {}
	if not U.Allowed(ID) then return end
	local own = U.Safe(initiator) and UnitIsUnit("player", initiator)
	if not own then
		if U.Allowed(ID, "improve") then
			Alert()
			if M.db.popups.timers and not U.Allowed(ID, "replace") then StartCountdown(ReadyBar(), readyCheck.timeLeft) end
		end
		C_Timer.After(0, function() M:ShowReadyPanel() end)
	end
end)

U.On("READY_CHECK_CONFIRM", function(_, unit, isReady)
	if not readyCheck.notReady or not U.Safe(unit) or U.Secret(isReady) then return end
	if isReady == false then
		local name = UnitName(unit)
		if U.Safe(name) then readyCheck.notReady[name] = true end
	end
end)

U.On("READY_CHECK_FINISHED", function()
	if readyBar then readyBar:Hide() end
	GiveBack()
	local notReady = readyCheck.notReady
	readyCheck.notReady = nil
	if not (notReady and U.Allowed(ID, "improve") and M.db.popups.summary) then return end
	-- Members who never answered are still "waiting".
	local prefix = IsInRaid() and "raid" or "party"
	local count = IsInRaid() and GetNumGroupMembers() or GetNumSubgroupMembers()
	local afk = {}
	for index = 1, count do
		local unit = prefix .. index
		local status = GetReadyCheckStatus and GetReadyCheckStatus(unit)
		local name = UnitName(unit)
		if U.Safe(status) == "waiting" and U.Safe(name) then afk[#afk + 1] = name end
	end
	local list = {}
	for name in pairs(notReady) do list[#list + 1] = name end
	table.sort(list)
	if #list == 0 and #afk == 0 then
		M:Print(L["Everyone is ready."])
	else
		if #list > 0 then M:Print(L["Not ready: %s"]:format(table.concat(list, ", "))) end
		if #afk > 0 then M:Print(L["No answer: %s"]:format(table.concat(afk, ", "))) end
	end
end)

U.On("GROUP_LEFT", function() GiveBack() end)

U.On("ROLE_POLL_BEGIN", function()
	if U.Allowed(ID, "improve") then Alert() end
end)

-- Battleground / arena ready: a countdown on Blizzard's dialog when the
-- client tells the time left (GetBattlefieldPortExpiration, feature-checked).
-- The sound and flash come once per pop, whatever the bar does: the game
-- sends the status again and again while the dialog is up.
local pvpAlerted = {}
U.On("UPDATE_BATTLEFIELD_STATUS", function(_, index)
	if not (U.Allowed(ID, "improve") and index and GetBattlefieldStatus) then return end
	local status = GetBattlefieldStatus(index)
	if status ~= "confirm" then
		pvpAlerted[index] = nil
		if pvpBar and pvpBar.index == index then pvpBar:Hide() end
		return
	end
	if not pvpAlerted[index] then
		pvpAlerted[index] = true
		Alert()
	end
	if pvpBar and pvpBar:IsShown() and pvpBar.index == index then return end
	if not (M.db.popups.timers and PVPReadyDialog and GetBattlefieldPortExpiration) then return end
	local seconds = U.Safe(GetBattlefieldPortExpiration(index))
	if not seconds then return end
	if not pvpBar then
		pvpBar = CreateCountdown(PVPReadyDialog)
		pvpBar:SetPoint("BOTTOMLEFT", 12, 8)
		pvpBar:SetPoint("BOTTOMRIGHT", -12, 8)
	end
	pvpBar.index = index
	StartCountdown(pvpBar, seconds)
end)

-- Group finder proposal ("dungeon ready"): Forever has no proposal dialog
-- of its own, so EldoUI shows a small bar with the 40 s Blizzard gives.
local function ProposalBar()
	if proposalBar then return proposalBar end
	proposalBar = CreateCountdown(UIParent, "EldoUI_ProposalTimer")
	proposalBar:SetSize(260, 14)
	proposalBar:SetFrameStrata("DIALOG")
	proposalBar.label = E:CreateText(proposalBar, E.tokens.size.label, "LEFT")
	proposalBar.label:SetPoint("LEFT", 4, 0)
	proposalBar.text = E:CreateText(proposalBar, E.tokens.size.label, "RIGHT")
	proposalBar.text:SetPoint("RIGHT", -4, 0)
	BindReadyPart(proposalBar, UIParent)
	BindReadyPart(proposalBar.bg, proposalBar, false, nil, "bg")
	BindReadyPart(proposalBar.label, proposalBar, true, nil, "label")
	BindReadyPart(proposalBar.text, proposalBar, true, nil, "text")
	proposalBar:HookScript("OnHide", ReadyChanged)
	return proposalBar
end

U.On("LFG_PROPOSAL_SHOW", function()
	if not U.Allowed(ID, "improve") then return end
	-- The sound and flash follow the pop-up sound; the timer only the bar.
	Alert()
	if not M.db.popups.queueTimer then return end
	local bar = ProposalBar()
	bar:ClearAllPoints()
	bar:SetPoint("TOP", ReadyAnchor(), "BOTTOM", 0, -6)
	bar.label:SetText(L["Dungeon ready"])
	StartCountdown(bar, LFG_PROPOSAL_SECONDS)
	ReadyChanged()
end)

for _, event in ipairs({ "LFG_PROPOSAL_FAILED", "LFG_PROPOSAL_SUCCEEDED", "LFG_PROPOSAL_DONE" }) do
	U.On(event, function()
		if proposalBar then proposalBar:Hide() end
	end)
end

---------------------------------------------------------------------------
-- Apply / restore
---------------------------------------------------------------------------
local hooked = false

local function Hook()
	if hooked then return end
	hooked = true
	-- Blizzard sets the dialog's background picture each time it opens.
	if type(_G.PVPReadyDialog_Display) == "function" then
		hooksecurefunc("PVPReadyDialog_Display", function(dialog)
			if U.Allowed(ID, "skin") and dialog then E:SkinAlphaZero(dialog.background, dialog.bottomArt) end
		end)
	end
	if ReadyCheckListenerFrame then
		ReadyCheckListenerFrame:HookScript("OnHide", function() GiveBack() end)
	end
	if ReadyCheckFrame then
		ReadyCheckFrame:HookScript("OnHide", function() GiveBack() end)
	end
end

local function PingWheel()
	return rawget(_G, "PingFrame")
end

local function Apply(state)
	Hook()
	if state.skin then SkinAll() end
	if ReadyCheckListenerFrame and ReadyCheckListenerFrame.Text then
		if state.skin then U.SkinFont(ReadyCheckListenerFrame.Text, 13) else U.RestoreFont(ReadyCheckListenerFrame.Text) end
	end
	if state.move and ReadyCheckFrame then
		local holder = OwnedReadyHolder()
		if holder then
			U.Pin(ReadyCheckFrame, holder, "CENTER", "CENTER", 0, 0, function() return U.Allowed(ID, "move") end)
		else
			U.Unpin(ReadyCheckFrame)
		end
		U.SetScale(ReadyCheckFrame, M.db.popups.scale)
		if PingWheel() then U.SetScale(PingWheel(), M.db.popups.pingScale) end
	else
		U.Unpin(ReadyCheckFrame)
		U.RestoreScale(ReadyCheckFrame)
		if PingWheel() then U.RestoreScale(PingWheel()) end
	end
	if not state.replace then GiveBack() else M:ShowReadyPanel() end
	if not state.improve then
		if readyBar then readyBar:Hide() end
		if pvpBar then pvpBar:Hide() end
		if proposalBar then proposalBar:Hide() end
	end
	ReadyChanged()
end

local function Restore()
	GiveBack()
	U.Unpin(ReadyCheckFrame)
	U.RestoreScale(ReadyCheckFrame)
	if PingWheel() then U.RestoreScale(PingWheel()) end
	if ReadyCheckListenerFrame and ReadyCheckListenerFrame.Text then U.RestoreFont(ReadyCheckListenerFrame.Text) end
	StopCountdown(readyBar)
	StopCountdown(pvpBar)
	StopCountdown(proposalBar)
	ReadyChanged()
end

U.Element(ID, {
	apply = Apply,
	restore = Restore,
	handler = {
		reload = { skin = true },
		install = { skin = true, improve = true },
	},
})

U.OnDisable(GiveBack)
