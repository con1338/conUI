-- EldoUI Action Bars: the special bars and buttons.
--
--   Pet and stance bars   EldoUI_PetBar / EldoUI_StanceBar take
--       Blizzard's own pet and stance buttons, so clicks, autocast, keybinds
--       and tooltips stay Blizzard's (secure) and EldoUI only places, sizes,
--       fades and skins them.
--   Vehicle, possess, override   EldoUI's vehicle exit button
--       (also lands taxis early), the possess bar on its own mover, Blizzard's
--       override bar hidden while EldoUI's bar 1 pages to it, the seat
--       indicator moved or hidden.
--   Zone ability   mover, scale, art, skin. WoW: Forever has no extra
--       action button, so the zone ability is all this part places.
--   Shaman totem bar   mover, scale, skin, hide; Blizzard's
--       totem timers can sit on top of it. Totem slots can be secret in
--       combat, so EldoUI never rebuilds the bar, it moves Blizzard's.
--   Gamepad HUD   skin, mover, scale, hide.
--
-- Blizzard frames are only reparented, re-anchored, scaled, faded or
-- skinned, all out of combat. Anchors that Blizzard's frame managers reset
-- are put back by a SetPoint post-hook (hooksecurefunc), queued until combat
-- ends for protected frames.
local _, E = ...
local L = E.L

local M = E:GetModule("ActionBars")

local PET = "pet-stance-bars"
local VEHICLE = "vehicle-possess-override"
local EXTRA = "extra-zone-ability"
local TOTEM = "totem-bar"
local GAMEPAD = "gamepad-hud"

local NUM_PET = 10
local NUM_STANCE = 10

local DEFAULT_POINTS = {
	EldoUI_PetBar = { "BOTTOMRIGHT", "UIParent", "BOTTOM", -320, 144 },
	EldoUI_StanceBar = { "BOTTOMLEFT", "UIParent", "BOTTOM", 320, 144 },
	EldoUI_PossessBar = { "CENTER", "UIParent", "CENTER", -420, -440 },
	EldoUI_VehicleExit = { "CENTER", "UIParent", "CENTER", -347, -440 },
	EldoUI_VehicleSeat = { "RIGHT", "UIParent", "RIGHT", -250, 200 },
	EldoUI_ExtraAbility = { "CENTER", "UIParent", "CENTER", 347, -440 },
	EldoUI_TotemBar = { "BOTTOMRIGHT", "UIParent", "BOTTOM", -320, 180 },
	EldoUI_GamepadBar = { "BOTTOM", "UIParent", "BOTTOM", 0, 40 },
}
M.SPECIAL_POINTS = DEFAULT_POINTS

local Clamp = M.Clamp

---------------------------------------------------------------------------
-- Keeping a Blizzard frame on an EldoUI holder
---------------------------------------------------------------------------
local anchoredTo = {}      -- Blizzard frame -> holder while EldoUI places it
local wantedScale = {}     -- Blizzard frame -> the scale EldoUI gives it (SetOwnScale)

-- Place a Blizzard frame on `holder` and keep it there: the core pin
-- (E:PinBlizzardFrame) follows Edit Mode's layout passes and the managed
-- containers with the plain widget methods, after combat for protected
-- frames.
function M:AnchorBlizzardFrame(frame, holder)
	if not frame or not E:SkinUsable(frame) then return end
	anchoredTo[frame] = holder
	E:PinBlizzardFrame(frame, {
		holder = holder,
		active = function() return anchoredTo[frame] == holder end,
		anchor = function() return "CENTER", holder, "CENTER", 0, 0 end,
		-- Edit Mode re-applies its own scale setting on a layout pass.
		scale = function() return wantedScale[frame] end,
	})
end

-- Let Blizzard place the frame again (its manager or Edit Mode re-applies
-- its own position at the next layout; until then the old points return).
function M:ReleaseBlizzardFrame(frame)
	if not frame or not anchoredTo[frame] then return end
	anchoredTo[frame] = nil
	E:UnpinBlizzardFrame(frame)
end

-- A plain EldoUI frame with a mover, the size of `width` x `height`.
local holders = {}
-- What move mode's test frames draw while a bar is empty (no pet, no
-- vehicle, no zone ability).
local SAMPLES = {
	EldoUI_PetBar = { kind = "icons" },
	EldoUI_ExtraAbility = { kind = "icons", count = 1 },
	EldoUI_VehicleExit = { kind = "icons", count = 1 },
	EldoUI_GamepadBar = { kind = "icons" },
}
local function Holder(name, title, width, height, secure)
	if holders[name] then return holders[name] end
	local frame = CreateFrame("Frame", name, UIParent, secure and "SecureHandlerStateTemplate" or nil)
	frame:SetSize(width, height)
	frame.eldoMover = name
	frame.backdrop = CreateFrame("Frame", nil, frame)
	frame.backdrop:SetFrameLevel(math.max(frame:GetFrameLevel() - 1, 0))
	frame.backdrop:Hide()
	E:CreateMover(frame, name, title, DEFAULT_POINTS[name], { sample = SAMPLES[name] })
	holders[name] = frame
	return frame
end

---------------------------------------------------------------------------
-- Taking over a row of Blizzard buttons (pet, stance, possess)
---------------------------------------------------------------------------
local taken = {}   -- Blizzard button -> holder

local function TakeButton(button, holder, command)
	if not button then return end
	taken[button] = holder
	button:SetParent(holder)
	if command then E:RegisterKeybindButton(button, command) end
end

local function ReturnButton(button)
	if not button or not taken[button] then return end
	taken[button] = nil
	local container = button.container
	button:SetParent(container or UIParent)
	button:ClearAllPoints()
	button:SetPoint("CENTER", container or UIParent, "CENTER")
	button:SetAttribute("statehidden", nil)
	if container then button:SetSize(container:GetSize()) end
end

-- Blizzard's bar keeps running (its updates drive the buttons) but shows
-- nothing and takes no clicks while EldoUI holds its buttons.
local quieted = {}
local function QuietBar(bar, quiet)
	if not bar then return end
	if quiet then
		quieted[bar] = true
		bar:SetAlpha(0)
		bar:EnableMouse(false)
	elseif quieted[bar] then
		quieted[bar] = nil
		bar:SetAlpha(1)
		bar:EnableMouse(true)
	end
end

-- Alpha, scale and mouse on Blizzard objects change only while EldoUI
-- wants them changed; the original value is put back once, after which
-- EldoUI leaves the object alone (master off = Blizzard untouched).
local ownAlpha, ownScale, ownMouse = {}, {}, {}
local function SetOwnAlpha(object, alpha)
	if not object then return end
	if alpha then
		if ownAlpha[object] == nil then ownAlpha[object] = object:GetAlpha() end
		object:SetAlpha(alpha)
	elseif ownAlpha[object] ~= nil then
		object:SetAlpha(ownAlpha[object])
		ownAlpha[object] = nil
	end
end
-- Plain SetScale (SetScaleBase on Edit Mode systems such as the extra
-- ability container), so Edit Mode's override never runs from EldoUI.
local function SetOwnScale(frame, scale)
	if not frame then return end
	wantedScale[frame] = scale
	if scale then
		if ownScale[frame] == nil then ownScale[frame] = frame:GetScale() end
		E.BlizzardKeep.SetScale(frame, scale)
	elseif ownScale[frame] ~= nil then
		E.BlizzardKeep.SetScale(frame, ownScale[frame])
		ownScale[frame] = nil
	end
end
local function SetOwnMouse(frame, enabled)
	if not frame then return end
	if enabled ~= nil then
		if ownMouse[frame] == nil then ownMouse[frame] = frame:IsMouseEnabled() end
		frame:EnableMouse(enabled)
	elseif ownMouse[frame] ~= nil then
		frame:EnableMouse(ownMouse[frame])
		ownMouse[frame] = nil
	end
end

-- Hidden Blizzard frames stay hidden when Blizzard re-parents them (core
-- SetParent post-hook, after combat for protected frames).
local hiddenFrames = {}
local function HideFrame(frame, hide)
	if not frame then return end
	if hide then
		if not hiddenFrames[frame] then
			hiddenFrames[frame] = true
			E:HideBlizzardFrame(frame, { check = function() return hiddenFrames[frame] == true end })
		end
	elseif hiddenFrames[frame] then
		hiddenFrames[frame] = nil
		E:UnhideBlizzardFrame(frame)
	end
end
M.HideBlizzardFrame = function(_, frame, hide) HideFrame(frame, hide) end

-- Pet, stance and possess "Button size" range (Options.lua uses the same).
local SPECIAL_SIZE_MIN, SPECIAL_SIZE_MAX = 16, 64
M.SPECIAL_SIZE_MIN, M.SPECIAL_SIZE_MAX = SPECIAL_SIZE_MIN, SPECIAL_SIZE_MAX

-- Lay out a holder's buttons and size it from a settings table.
local function LayoutHolder(holder, buttons, count, db)
	local size = Clamp(db.size, SPECIAL_SIZE_MIN, SPECIAL_SIZE_MAX, 30)
	local spacing = Clamp(db.spacing, -1, 20, 4)
	local width, height = M:GridLayout(holder, buttons, count, db.perRow or count, size, spacing, db.growth, nil,
		db.fillOrder == "columns")
	M:SizeFrame(holder, width, height, Clamp(db.scale, 50, 200, 100) / 100)
	M:UpdateBackdrop(holder, db)
	for slot, button in ipairs(buttons) do
		if slot > count then button:SetAttribute("statehidden", true) else button:SetAttribute("statehidden", nil) end
	end
	return size
end

-- Pet and stance buttons can be bound in keybind mode whether they sit in
-- EldoUI's bar or in Blizzard's, while the module is on.
local function RegisterBindings(buttons, command)
	for i, button in ipairs(buttons) do
		if M.active then E:RegisterKeybindButton(button, command .. i) else E:UnregisterKeybindButton(button) end
	end
end

local function SkinButtons(buttons, skin)
	for _, button in ipairs(buttons) do
		if skin then M:SkinBlizzardButton(button) else M:UnskinBlizzardButton(button) end
	end
end

local function NamedButtons(prefix, count)
	local list = {}
	for i = 1, count do
		local button = _G[prefix .. i]
		if button then list[#list + 1] = button end
	end
	return list
end

---------------------------------------------------------------------------
-- Pet bar
---------------------------------------------------------------------------
local HAPPINESS_COLOR = { [1] = { 0.9, 0.2, 0.2 }, [2] = { 1, 0.8, 0.2 }, [3] = { 0.3, 0.85, 0.3 } }

local function UpdateHappiness()
	local holder = holders.EldoUI_PetBar
	if not holder or not holder.eldoTaken then return end
	local db = M.db.pet
	local show = db.happiness and E:BlizzardAllowed(PET, "improve") and C_PetInfo and C_PetInfo.GetPetHappiness
	local happiness = show and C_PetInfo.GetPetHappiness()
	if not (issecretvalue and issecretvalue(happiness)) and happiness and HAPPINESS_COLOR[happiness] then
		local c = HAPPINESS_COLOR[happiness]
		M:UpdateBackdrop(holder, { backdrop = true, backdropPadding = db.backdropPadding }, true)
		holder.backdrop:SetBackdropBorderColor(c[1], c[2], c[3], 1)
	else
		M:UpdateBackdrop(holder, db)
	end
end

local function ApplyPetBar()
	local db = M.db.pet
	local buttons = NamedButtons("PetActionButton", NUM_PET)
	local holder = Holder("EldoUI_PetBar", L["Pet Bar"], 300, 30, true)
	local take = M.active and db.mode == "eldoui" and E:BlizzardAllowed(PET, "replace") and #buttons > 0
	holder.eldoTaken = take
	holder.eldoEnabled = take
	if take then
		for _, button in ipairs(buttons) do TakeButton(button, holder) end
		local count = math.floor(Clamp(db.buttons, 1, NUM_PET, NUM_PET))
		LayoutHolder(holder, buttons, count, db)
		QuietBar(PetActionBar, true)
		M:PlaceFrame(holder, E:BlizzardAllowed(PET, "move"), PetActionBar)
		M:RegisterHolder(holder, db)
		M:SetDriver(holder, M:VisibilityDriver(db, "[nopet] hide"))
		UpdateHappiness()
		M:UpdateFade(holder, true)
	else
		for _, button in ipairs(buttons) do ReturnButton(button) end
		QuietBar(PetActionBar, false)
		M:SetDriver(holder, nil)
		M:ReleaseHolder(holder)
		M:SetMoverActive("EldoUI_PetBar", false)
	end
	HideFrame(PetActionBar, M.active and not take and db.mode == "hide" and E:BlizzardHidden(PET))
	SkinButtons(buttons, M.active and E:BlizzardAllowed(PET, "skin"))
	RegisterBindings(buttons, "BONUSACTIONBUTTON")
	-- Autocast sparkles are Blizzard's; the option only hides them.
	for _, button in ipairs(buttons) do
		if button.AutoCastOverlay then
			SetOwnAlpha(button.AutoCastOverlay, (M.active and E:BlizzardAllowed(PET) and not db.autocastGlow) and 0 or nil)
		end
	end
	if PetActionBar and PetActionBar.BackgroundArtTextures then
		local skin = M.active and E:BlizzardAllowed(PET, "skin")
		for _, texture in ipairs(PetActionBar.BackgroundArtTextures) do SetOwnAlpha(texture, skin and 0 or nil) end
	end
end

---------------------------------------------------------------------------
-- Stance bar
---------------------------------------------------------------------------
-- Vanilla Original: the classic stance bar's stone behind a one-row stance
-- bar (a left end, a middle piece per button between, a right end), the
-- client's own files (E:SetOriginalArt). The classic buttons are 30 px,
-- 37 apart, on pieces 38 high that start 11 left of the first button and
-- 4 below it. Nothing here takes the mouse; other skins draw none of it.
local STANCE_PITCH, STANCE_BUTTON = 37, 30

local function PaintStanceArt(holder, count, db, shown)
	local art = holder.originalArt
	local size = Clamp(db.size, SPECIAL_SIZE_MIN, SPECIAL_SIZE_MAX, 30)
	local spacing = Clamp(db.spacing, -1, 20, 4)
	local oneRow = (db.perRow or count) >= count
	local want = shown and oneRow and M.OriginalArtOn and M:OriginalArtOn()
		and M.OriginalDrawable("stance-left") and M.OriginalDrawable("stance-middle") and M.OriginalDrawable("stance-right")
	if not want then
		if art then art:Hide() end
		return false
	end
	if not art then
		art = CreateFrame("Frame", nil, holder)
		art:EnableMouse(false)
		art.pieces = {}
		holder.originalArt = art
	end
	art:SetFrameLevel(math.max(holder:GetFrameLevel() - 1, 0))
	art:ClearAllPoints()
	art:SetAllPoints(holder)
	local kx, ky = (size + spacing) / STANCE_PITCH, size / STANCE_BUTTON
	local x, bottom = -11 * kx, -4 * ky
	local slots = { "stance-left" }
	for _ = 2, count - 1 do slots[#slots + 1] = "stance-middle" end
	slots[#slots + 1] = "stance-right"
	for index, slot in ipairs(slots) do
		local piece = art.pieces[index] or art:CreateTexture(nil, "BACKGROUND")
		art.pieces[index] = piece
		local width = E:OriginalArt(slot).size[1] * kx
		piece:ClearAllPoints()
		piece:SetPoint("BOTTOMLEFT", art, "BOTTOMLEFT", x, bottom)
		piece:SetSize(width, 38 * ky)
		E:SetOriginalArt(piece, slot)
		piece:Show()
		x = x + width
	end
	for index = #slots + 1, #art.pieces do art.pieces[index]:Hide() end
	art:Show()
	return true
end
M.PaintStanceArt = PaintStanceArt -- exposed for inspection

local function ApplyStanceBar()
	local db = M.db.stance
	local buttons = NamedButtons("StanceButton", NUM_STANCE)
	local holder = Holder("EldoUI_StanceBar", L["Stance Bar"], 300, 30, true)
	local forms = GetNumShapeshiftForms and GetNumShapeshiftForms() or 0
	local take = M.active and db.mode == "eldoui" and E:BlizzardAllowed(PET, "replace") and #buttons > 0
	holder.eldoTaken = take
	holder.eldoEnabled = take and forms > 0
	if take then
		for _, button in ipairs(buttons) do TakeButton(button, holder) end
		LayoutHolder(holder, buttons, math.max(1, forms), db)
		PaintStanceArt(holder, math.max(1, forms), db, forms > 0)
		QuietBar(StanceBar, true)
		M:PlaceFrame(holder, E:BlizzardAllowed(PET, "move"), StanceBar)
		M:RegisterHolder(holder, db)
		M:SetDriver(holder, forms > 0 and M:VisibilityDriver(db) or nil)
		M:UpdateFade(holder, true)
	else
		for _, button in ipairs(buttons) do ReturnButton(button) end
		PaintStanceArt(holder, 1, db, false)
		QuietBar(StanceBar, false)
		M:SetDriver(holder, nil)
		M:ReleaseHolder(holder)
		M:SetMoverActive("EldoUI_StanceBar", false)
	end
	HideFrame(StanceBar, M.active and not take and db.mode == "hide" and E:BlizzardHidden(PET))
	SkinButtons(buttons, M.active and E:BlizzardAllowed(PET, "skin"))
	RegisterBindings(buttons, "SHAPESHIFTBUTTON")
end

---------------------------------------------------------------------------
-- Possess bar, override bar, seat indicator, vehicle exit
---------------------------------------------------------------------------
-- Blizzard's override bar (skinned vehicles) is hidden only while EldoUI's
-- bar 1 is there to page to the vehicle's actions.
function M:OverrideBarHidden()
	return self.active and self.db.vehicle.overrideBar == "eldoui" and E:BlizzardHidden(VEHICLE) and self:BarActive(1)
end

local function ApplyPossess()
	local db = M.db.possess
	local buttons = NamedButtons("PossessButton", 2)
	local holder = Holder("EldoUI_PossessBar", L["Possess Bar"], 64, 30, true)
	local take = M.active and db.mode == "eldoui" and E:BlizzardAllowed(VEHICLE, "replace") and #buttons > 0
	holder.eldoEnabled = take
	if take then
		for _, button in ipairs(buttons) do TakeButton(button, holder) end
		LayoutHolder(holder, buttons, #buttons, { size = db.size, spacing = db.spacing, perRow = #buttons, scale = db.scale })
		M:PlaceFrame(holder, E:BlizzardAllowed(VEHICLE, "move"), PossessActionBar)
		M:SetDriver(holder, "[petbattle] hide; [possessbar] show; hide")
	else
		for _, button in ipairs(buttons) do ReturnButton(button) end
		M:SetDriver(holder, nil)
		M:SetMoverActive("EldoUI_PossessBar", false)
	end
	QuietBar(PossessActionBar, take)
	SkinButtons(buttons, M.active and E:BlizzardAllowed(VEHICLE, "skin"))
end

local function SkinOverrideBar(skin)
	local bar = OverrideActionBar
	if not bar then return end
	for i = 1, 6 do
		local button = bar["SpellButton" .. i] or _G["OverrideActionBarButton" .. i]
		if button then
			if skin then M:SkinBlizzardButton(button) else M:UnskinBlizzardButton(button) end
		end
	end
end

local seatHolder
local function ApplySeat()
	local frame = VehicleSeatIndicator
	local db = M.db.vehicle
	seatHolder = Holder("EldoUI_VehicleSeat", L["Vehicle Seats"], 128, 128)
	local on = M.active and E:BlizzardAllowed(VEHICLE)
	local move = on and db.seat == "move" and E:BlizzardAllowed(VEHICLE, "move")
	local hide = on and db.seat == "hide" and E:BlizzardHidden(VEHICLE)
	M:SetMoverActive("EldoUI_VehicleSeat", move)
	seatHolder:SetShown(move)
	if not frame then return end
	if move then
		M:AnchorBlizzardFrame(frame, seatHolder)
		SetOwnScale(frame, Clamp(db.seatScale, 50, 200, 100) / 100)
	else
		M:ReleaseBlizzardFrame(frame)
		SetOwnScale(frame, nil)
	end
	-- Not protected; hidden by alpha so its frame manager keeps working.
	SetOwnAlpha(frame, hide and 0 or nil)
	for _, button in ipairs(frame.buttons or {}) do SetOwnMouse(button, hide and false or nil) end
end

-- EldoUI's own vehicle exit button. A secure button with Blizzard's
-- "leavevehicle" action, so it works in combat; a state driver shows it
-- whenever the game says the vehicle can be left. On a flight path (never
-- in combat) it asks the flight master to land early instead.
local exitButton

-- Should EldoUI's button exist at all right now?
local function ExitWanted()
	if not M.active then return false end
	local mode = M.db.vehicle.exit
	if mode == "never" then return false end
	if mode == "always" then return true end
	-- auto: only when Blizzard's own leave button is gone (bar 1 hidden or
	-- the override bar hidden).
	return not M:BlizzardBarShown(1) or M:OverrideBarHidden()
end

-- Taxis have no macro condition, so they are handled out of combat here.
local function UpdateExit()
	if not exitButton or InCombatLockdown() then return end
	if exitButton.eldoWanted and UnitOnTaxi and UnitOnTaxi("player") then
		exitButton:Show()
		exitButton:Enable()
	elseif exitButton.eldoWanted and exitButton.eldoDriver then
		-- Let the driver decide again.
		local driver = exitButton.eldoDriver
		exitButton.eldoDriver = nil
		M:SetDriver(exitButton, driver)
	end
end

local function CreateExit()
	if exitButton then return exitButton end
	local holder = Holder("EldoUI_VehicleExit", L["Vehicle Exit"], 32, 32)
	exitButton = CreateFrame("Button", "EldoUI_VehicleExitButton", holder, "SecureActionButtonTemplate")
	exitButton:SetAllPoints(holder)
	exitButton:RegisterForClicks("AnyUp", "AnyDown")
	exitButton:SetAttribute("type", "leavevehicle")
	exitButton:Hide()
	exitButton.backdrop = CreateFrame("Frame", nil, exitButton)
	exitButton.backdrop:SetAllPoints()
	exitButton.backdrop:SetFrameLevel(math.max(exitButton:GetFrameLevel() - 1, 0))
	exitButton.icon = exitButton:CreateTexture(nil, "ARTWORK")
	exitButton.icon:SetTexture("Interface\\Vehicles\\UI-Vehicles-Button-Exit-Up")
	exitButton.icon:SetTexCoord(0.2, 0.8, 0.2, 0.8)
	exitButton.icon:SetPoint("TOPLEFT", E.pixel, -E.pixel)
	exitButton.icon:SetPoint("BOTTOMRIGHT", -E.pixel, E.pixel)
	local highlight = exitButton:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetAllPoints(exitButton.icon)
	highlight:SetColorTexture(1, 1, 1, E.tokens.hover.hud)
	exitButton:HookScript("PostClick", function(self)
		if UnitOnTaxi and UnitOnTaxi("player") and not InCombatLockdown() then
			TaxiRequestEarlyLanding()
			self:Disable()
		end
	end)
	exitButton:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(UnitOnTaxi("player") and (_G.TAXI_CANCEL or L["Land"]) or (_G.LEAVE_VEHICLE or L["Leave vehicle"]))
		GameTooltip:Show()
	end)
	exitButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
	E:RegisterKeybindButton(exitButton, "VEHICLEEXIT")
	return exitButton
end

local function ApplyVehicle()
	local db = M.db.vehicle
	CreateExit()
	local holder = holders.EldoUI_VehicleExit
	local size = Clamp(db.exitSize, 20, 64, 32)
	M:SizeFrame(holder, size, size, 1)
	E:SetTemplate(exitButton.backdrop)
	exitButton.eldoWanted = ExitWanted()
	holder.eldoEnabled = exitButton.eldoWanted
	M:SetMoverActive("EldoUI_VehicleExit", holder.eldoEnabled)
	holder:SetShown(holder.eldoEnabled and true or false)
	M:SetDriver(exitButton, exitButton.eldoWanted and "[petbattle] hide; [canexitvehicle] show; hide" or nil)
	UpdateExit()

	HideFrame(OverrideActionBar, M:OverrideBarHidden())
	SkinOverrideBar(M.active and E:BlizzardAllowed(VEHICLE, "skin"))
	if MainMenuBarVehicleLeaveButton then
		if M.active and E:BlizzardAllowed(VEHICLE, "skin") then
			M:SkinBlizzardButton(MainMenuBarVehicleLeaveButton)
		else
			M:UnskinBlizzardButton(MainMenuBarVehicleLeaveButton)
		end
	end
	ApplyPossess()
	ApplySeat()
end

---------------------------------------------------------------------------
-- Zone ability (WoW: Forever has no extra action button, so nothing here
-- skins it or offers its key)
---------------------------------------------------------------------------
-- The game's own switch says whether the client has an extra action button:
-- "off" (WoW: Forever), "on" (a client that has one) or "unknown" (the
-- switch is missing or fails). Every answer keeps the zone ability path;
-- the answer is kept in M.extraButtonState for the API check.
local function ExtraButtonState()
	local util = ActionButtonUtil
	local check = type(util) == "table" and util.IsExtraActionButtonDisabled
	if type(check) ~= "function" then return "unknown" end
	local ok, disabled = pcall(check)
	if not ok or type(disabled) ~= "boolean" then return "unknown" end
	return disabled and "off" or "on"
end

function M:ExtraButtonDisabled()
	self.extraButtonState = ExtraButtonState()
	return self.extraButtonState ~= "on"
end

local function SkinZoneButtons(skin)
	local frame = ZoneAbilityFrame
	local container = frame and frame.SpellButtonContainer
	if not container then return end
	for _, child in ipairs({ container:GetChildren() }) do
		if child.Icon then
			if skin then M:SkinBlizzardButton(child) else M:UnskinBlizzardButton(child) end
		end
	end
end

local zoneHooked = false
local function HookZone()
	if zoneHooked or not ZoneAbilityFrame or not ZoneAbilityFrame.UpdateDisplayedZoneAbilities then return end
	zoneHooked = true
	hooksecurefunc(ZoneAbilityFrame, "UpdateDisplayedZoneAbilities", function()
		if not M.active then return end
		local db = M.db.extra
		if E:BlizzardAllowed(EXTRA, "skin") and not InCombatLockdown() then SkinZoneButtons(true) end
		SetOwnAlpha(ZoneAbilityFrame.Style, (E:BlizzardAllowed(EXTRA, "hide") and db.hideArt) and 0 or nil)
	end)
end

local function ApplyExtra()
	M:ExtraButtonDisabled()
	local db = M.db.extra
	local holder = Holder("EldoUI_ExtraAbility", L["Zone Ability"], 256, 120)
	local container = ExtraAbilityContainer
	local on = M.active and E:BlizzardAllowed(EXTRA)
	local move = on and E:BlizzardAllowed(EXTRA, "move")
	M:SetMoverActive("EldoUI_ExtraAbility", move)
	holder:SetShown(move and true or false)
	if container then
		if move then
			M:AnchorBlizzardFrame(container, holder)
			SetOwnScale(container, Clamp(db.scale, 50, 200, 100) / 100)
		else
			M:ReleaseBlizzardFrame(container)
			SetOwnScale(container, nil)
		end
	end
	-- "Hide" only ever hides the decorative art, never the button.
	local hideArt = on and E:BlizzardAllowed(EXTRA, "hide") and db.hideArt
	if ZoneAbilityFrame then SetOwnAlpha(ZoneAbilityFrame.Style, hideArt and 0 or nil) end
	SkinZoneButtons(on and E:BlizzardAllowed(EXTRA, "skin"))
	HookZone()
end

---------------------------------------------------------------------------
-- Shaman totem bar (Forever: MultiCastActionBarFrame)
---------------------------------------------------------------------------
local function TotemButtons()
	local list = NamedButtons("MultiCastActionButton", 12)
	if MultiCastSummonSpellButton then list[#list + 1] = MultiCastSummonSpellButton end
	if MultiCastRecallSpellButton then list[#list + 1] = MultiCastRecallSpellButton end
	return list
end

local function SkinTotemSlots(skin)
	for i = 1, 4 do
		local slot = _G["MultiCastSlotButton" .. i]
		if slot and slot.background then
			SetOwnAlpha(slot.background, skin and 0 or nil)
			SetOwnAlpha(slot.overlayTex, skin and 0 or nil)
			if skin then
				M:SkinBlizzardButton(slot)
			else
				M:UnskinBlizzardButton(slot)
			end
		end
	end
end

local function ApplyTotem()
	local db = M.db.totem
	local holder = Holder("EldoUI_TotemBar", L["Totem Bar"], 230, 40)
	local frame = MultiCastActionBarFrame
	local _, class = UnitClass("player")
	-- Shaman Totems' own bar takes Blizzard's totem bar's place while it is on.
	local on = M.active and E:BlizzardAllowed(TOTEM) and frame ~= nil and class == "SHAMAN"
		and not (E.Totems and E.Totems:OwnsBlizzard())
	local move = on and E:BlizzardAllowed(TOTEM, "move")
	M:SetMoverActive("EldoUI_TotemBar", move)
	holder:SetShown(move and true or false)
	if frame then
		if move then
			M:AnchorBlizzardFrame(frame, holder)
			SetOwnScale(frame, Clamp(db.scale, 50, 200, 100) / 100)
		else
			M:ReleaseBlizzardFrame(frame)
			SetOwnScale(frame, nil)
		end
		HideFrame(frame, on and E:BlizzardHidden(TOTEM))
	end
	local skin = on and E:BlizzardAllowed(TOTEM, "skin")
	SkinButtons(TotemButtons(), skin)
	SkinTotemSlots(skin)
	-- Blizzard's totem timers (TotemFrame) belong to Player Power (the
	-- "class-resources" element): its "Totem timers position" can put them
	-- above this bar. Action Bars only owns the bar itself, but when the
	-- bar comes, goes or is hidden, Player Power places the timers again.
	local state = tostring(move) .. tostring(on and E:BlizzardHidden(TOTEM))
	local power = E.modules.ClassPower
	if state ~= M.totemState and power and power.active and power.ApplyBlizzard then
		M.totemState = state
		local ok, err = pcall(power.ApplyBlizzard, power)
		if not ok then geterrorhandler()(err) end
	end
	-- A frame placed on top of a unit frame rises only as far as the moved
	-- bar leaves room for (Unit Frames), so it looks again when the bar
	-- comes or goes.
	local frames = E.modules.UnitFrames
	if (move and true or false) ~= M.totemMoved then
		M.totemMoved = move and true or false
		if frames and frames.active and frames.PlaceTopNeighbors then
			local ok, err = pcall(frames.PlaceTopNeighbors, frames)
			if not ok then geterrorhandler()(err) end
		end
	end
end

---------------------------------------------------------------------------
-- Gamepad HUD (Forever's controller bars)
---------------------------------------------------------------------------
-- Every action-style button inside the gamepad bar, at any depth.
local function GamepadButtons(frame, list, depth)
	list = list or {}
	depth = depth or 0
	if not frame or depth > 5 then return list end
	for _, child in ipairs({ frame:GetChildren() }) do
		if child.icon and child.cooldown and child.GetNormalTexture then
			list[#list + 1] = child
		else
			GamepadButtons(child, list, depth + 1)
		end
	end
	return list
end

-- The game parents its gamepad bar to UIParent. A bar another addon has
-- hidden or moved under a parent of its own is that addon's: EldoUI leaves
-- it alone (no pin, scale, skin or mover). EldoUI's own hiding is not that.
local function GamepadBarTaken(frame)
	if not (frame and frame.GetParent) then return false end
	return frame:GetParent() ~= UIParent and not E:IsBlizzardFrameHidden(frame)
end
M.GamepadBarTaken = function(_, frame) return GamepadBarTaken(frame or GamepadMainActionBarFrame) end

local function ApplyGamepad()
	local frame = GamepadMainActionBarFrame
	local db = M.db.gamepad
	local holder = Holder("EldoUI_GamepadBar", L["Gamepad Bar"], 400, 120)
	local on = M.active and E:BlizzardAllowed(GAMEPAD) and frame ~= nil and not GamepadBarTaken(frame)
	local move = on and E:BlizzardAllowed(GAMEPAD, "move")
	M:SetMoverActive("EldoUI_GamepadBar", move)
	holder:SetShown(move and true or false)
	if not frame then return end
	if move then
		M:AnchorBlizzardFrame(frame, holder)
		SetOwnScale(frame, Clamp(db.scale, 50, 200, 100) / 100)
	else
		M:ReleaseBlizzardFrame(frame)
		SetOwnScale(frame, nil)
	end
	HideFrame(frame, on and E:BlizzardHidden(GAMEPAD))
	SkinButtons(GamepadButtons(frame), on and E:BlizzardAllowed(GAMEPAD, "skin"))
end

---------------------------------------------------------------------------
-- Apply and events
---------------------------------------------------------------------------
local eventsOn = false

-- UNIT_HAPPINESS (hunter pet mood) may be missing on a client; a failed
-- registration must not stop the rest of Apply.
local function RegisterIfValid(event, handler)
	if C_EventUtils and C_EventUtils.IsEventValid and not C_EventUtils.IsEventValid(event) then return false end
	local ok, err = pcall(M.RegisterEvent, M, event, handler)
	if not ok then
		if E.errors and E.errors.Add then E.errors:Add("warning", ("Action Bars: %s can't be registered: %s"):format(event, tostring(err))) end
		pcall(M.UnregisterEvent, M, event)
	end
	return ok
end

-- The same for an event of one unit: the game filters it, so another
-- group member's pet never reaches the handler.
local function RegisterUnitIfValid(event, unit, handler)
	if C_EventUtils and C_EventUtils.IsEventValid and not C_EventUtils.IsEventValid(event) then return false end
	local ok, err = pcall(M.RegisterUnitEvent, M, event, unit, handler)
	if not ok then
		if E.errors and E.errors.Add then E.errors:Add("warning", ("Action Bars: %s can't be registered: %s"):format(event, tostring(err))) end
		pcall(M.UnregisterUnitEvent, M, event, unit)
	end
	return ok
end

local HAPPINESS_UNITS = { "player", "pet" }

local function SpecialEvents(on)
	if on == eventsOn then return end
	eventsOn = on
	local exitEvents = { "UNIT_ENTERED_VEHICLE", "UNIT_EXITED_VEHICLE", "VEHICLE_UPDATE", "UPDATE_BONUS_ACTIONBAR",
		"UPDATE_OVERRIDE_ACTIONBAR", "UPDATE_POSSESS_BAR", "PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED", "UPDATE_MULTI_CAST_ACTIONBAR" }
	for _, event in ipairs(exitEvents) do
		if on then M:RegisterEvent(event, function() UpdateExit() end) else M:UnregisterEvent(event) end
	end
	if on then
		M:RegisterEvent("UPDATE_SHAPESHIFT_FORMS", function()
			E:RunOutOfCombat(function() if M.active then ApplyStanceBar() end end, "actionBars:stance")
		end)
		RegisterUnitIfValid("UNIT_HAPPINESS", HAPPINESS_UNITS, function() UpdateHappiness() end)
		RegisterUnitIfValid("UNIT_PET", "player", function() UpdateHappiness() end)
	else
		M:UnregisterEvent("UPDATE_SHAPESHIFT_FORMS")
		M:UnregisterUnitEvent("UNIT_HAPPINESS", HAPPINESS_UNITS)
		M:UnregisterUnitEvent("UNIT_PET", "player")
	end
end

function M:ApplySpecial()
	ApplyPetBar()
	ApplyStanceBar()
	ApplyVehicle()
	ApplyExtra()
	ApplyTotem()
	E:OnBlizzardAddOn("Blizzard_GamepadActionBars", function()
		E:RunOutOfCombat(function() ApplyGamepad() end)
	end)
	SpecialEvents(self.active)
end

function M:DisableSpecial()
	self:ApplySpecial()
	SpecialEvents(false)
	for name in pairs(holders) do self:SetMoverActive(name, false) end
end

-- Blizzard element switches: each re-applies the whole module, which reads
-- every switch again.
local function Reapply()
	if M.active then M:Apply() end
end

E:RegisterBlizzardHandler(PET, {
	owner = "ActionBars",
	apply = Reapply,
	undo = Reapply,
	reload = { skin = true },
	install = { replace = true, move = true, skin = true, improve = true },
	refreshModule = false,
})

E:RegisterBlizzardHandler(VEHICLE, {
	owner = "ActionBars",
	apply = Reapply,
	undo = Reapply,
	reload = { skin = true, hide = true },
	install = { skin = true, move = true },
	refreshModule = false,
})

E:RegisterBlizzardHandler(EXTRA, {
	owner = "ActionBars",
	apply = Reapply,
	undo = Reapply,
	reload = { skin = true, move = true },
	install = { skin = true, move = true },
	refreshModule = false,
})

E:RegisterBlizzardHandler(TOTEM, {
	owner = "ActionBars",
	apply = Reapply,
	undo = Reapply,
	reload = { skin = true, move = true, hide = true },
	install = { skin = true, move = true },
	refreshModule = false,
})

E:RegisterBlizzardHandler(GAMEPAD, {
	owner = "ActionBars",
	apply = Reapply,
	undo = Reapply,
	reload = { skin = true, move = true, hide = true },
	refreshModule = false,
})
