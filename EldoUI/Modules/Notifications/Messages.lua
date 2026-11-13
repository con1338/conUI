-- EldoUI Notifications: text in the middle of the screen.
--
--   raid-warning  EldoUI font, mover and scale. Hide only drops
--                       player raid warnings (they stay in chat); boss emotes
--                       are encounter information and always show.
--   ui-errors     red error text: font, size, how long it stays, mover
--                       and scale. Hide: by category through Blizzard's own
--                       UIErrorsFrame:SetMessageTypeEnabled, or every error
--                       in combat / always. Yellow quest progress is never
--                       touched. Also hides the "screenshot captured" text.
--   zone-text     zone, subzone and PvP text: font, sizes, mover,
--                       scale, hide all or only the subzone.
--   BG messages  an EldoUI extra, no Blizzard switch: battleground
--                       system messages (flag taken, base assaulted) also
--                       as big text right under the raid warnings, in the
--                       game's own colors. Display only; a message whose
--                       text is a secret value is skipped.
local _, E = ...
local L = E.L
local M = E:GetModule("Notifications")
local U = M.util

local WARNING = "raid-warning"
local ERRORS = "ui-errors"
local ZONE = "zone-text"

---------------------------------------------------------------------------
-- Raid warnings
---------------------------------------------------------------------------
local warningStrings = {}  -- font strings EldoUI gave its font
local warningHooked = false
local warningOff = false

-- Blizzard scales the text height while a warning fades in, so only the
-- font face and outline change; Scale sets the size.
local function SkinWarningStrings()
	local frame = RaidWarningFrame
	if not (frame and frame.fontStringPool) then return end
	for fontString in frame.fontStringPool:EnumerateActive() do
		U.SkinFont(fontString)
		warningStrings[fontString] = true
	end
end

local function RestoreWarningStrings()
	for fontString in pairs(warningStrings) do U.RestoreFont(fontString) end
	wipe(warningStrings)
end

local function ApplyWarning(state)
	E:OnBlizzardAddOn("Blizzard_RaidWarning", function()
		local frame = RaidWarningFrame
		if not frame or not M.active or not E:BlizzardAllowed(WARNING) then return end
		state = E:BlizzardState(WARNING)
		if not warningHooked and type(frame.AddMessage) == "function" then
			warningHooked = true
			hooksecurefunc(frame, "AddMessage", function()
				if U.Allowed(WARNING, "skin") then SkinWarningStrings() end
			end)
		end
		if state.skin then SkinWarningStrings() else RestoreWarningStrings() end
		if state.move then
			U.Pin(frame, U.Holder("RaidWarning"), "TOP", "TOP", 0, 0, function() return U.Allowed(WARNING, "move") end)
			U.SetScale(frame, M.db.raidWarning.scale)
		else
			U.Unpin(frame)
			U.RestoreScale(frame)
		end
		if state.hide and not warningOff then
			frame:UnregisterEvent("CHAT_MSG_RAID_WARNING")
			warningOff = true
		elseif not state.hide and warningOff then
			frame:RegisterEvent("CHAT_MSG_RAID_WARNING")
			warningOff = false
		end
	end)
end

local function RestoreWarning()
	local frame = RaidWarningFrame
	if not frame then return end
	RestoreWarningStrings()
	U.Unpin(frame)
	U.RestoreScale(frame)
	if warningOff then
		frame:RegisterEvent("CHAT_MSG_RAID_WARNING")
		warningOff = false
	end
end

U.Element(WARNING, {
	apply = ApplyWarning,
	restore = RestoreWarning,
	handler = {
		reload = { skin = true },
		install = { skin = true },
	},
})

M.tests.warning = function()
	if not (RaidWarningFrame and _G.ChatTypeInfo and _G.ChatTypeInfo.RAID_WARNING) then return end
	RaidWarningFrame:AddMessage(L["EldoUI test raid warning"], _G.ChatTypeInfo.RAID_WARNING)
end

---------------------------------------------------------------------------
-- Red error text
---------------------------------------------------------------------------
-- Categories from the game's own message type names (LE_GAME_ERR_*) and
-- error names (GetGameMessageInfo). Order matters: "busy" before
-- "cooldown" (global cooldown), "range" before "power" (OUT_OF_RANGE).
local CATEGORY_PATTERNS = {
	{ "busy", { "ANOTHER_IN_PROGRESS", "SPELL_IN_PROGRESS", "INTERRUPTED", "COOLDOWN_GLOBAL" } },
	{ "range", { "OUT_OF_RANGE", "TOO_CLOSE", "TOO_FAR" } },
	{ "cooldown", { "COOLDOWN", "NOT_READY" } },
	{ "power", { "^OUT_OF_", "NO_COMBO_POINTS", "NOT_ENOUGH_POWER" } },
	{ "target", { "NO_TARGET", "NO_ATTACK_TARGET", "INVALID_ATTACK_TARGET", "BAD_TARGET", "BAD_IMPLICIT_TARGET",
		"NO_VALID_TARGETS", "TARGET_NOT_DEAD", "TARGETS_DEAD", "TARGET_FRIENDLY", "TARGET_ENEMY" } },
	{ "facing", { "FACING", "INFRONT", "NOT_BEHIND", "BADATTACKPOS" } },
	{ "moving", { "MOVING" } },
}

local function Classify(name)
	if type(name) ~= "string" or name:find("VOICE") or name:find("QUEST") then return nil end
	name = name:gsub("^ERR_", ""):gsub("^SPELL_FAILED_", ""):gsub("^SPELL_", "")
	for _, entry in ipairs(CATEGORY_PATTERNS) do
		for _, pattern in ipairs(entry[2]) do
			if name:find(pattern) then return entry[1] end
		end
	end
end

local typesByCategory -- [category] = { messageType, ... }

local function BuildTypes()
	if typesByCategory then return typesByCategory end
	typesByCategory = {}
	local seen = {}
	for key, value in pairs(_G) do
		if type(key) == "string" and type(value) == "number" and key:find("^LE_GAME_ERR_") and not seen[value] then
			local category = Classify(key:sub(13))
			if not category and GetGameMessageInfo then
				local ok, errorName = pcall(GetGameMessageInfo, value)
				if ok then category = Classify(errorName) end
			end
			if category then
				seen[value] = true
				typesByCategory[category] = typesByCategory[category] or {}
				table.insert(typesByCategory[category], value)
			end
		end
	end
	return typesByCategory
end

local disabledTypes = {}   -- messageType -> Blizzard's own enabled state before EldoUI
local errorsOff = false
local statusOff = false
local errorsHooked = false
local timeVisible

local function SetTypeHidden(messageType, hide)
	local frame = UIErrorsFrame
	if not (frame and frame.SetMessageTypeEnabled) then return end
	if hide and disabledTypes[messageType] == nil then
		local list = _G.BLACK_LISTED_MESSAGE_TYPES
		disabledTypes[messageType] = not (list and list[messageType])
		frame:SetMessageTypeEnabled(messageType, false)
	elseif not hide and disabledTypes[messageType] ~= nil then
		frame:SetMessageTypeEnabled(messageType, disabledTypes[messageType])
		disabledTypes[messageType] = nil
	end
end

local function SetErrorEvent(hide)
	local frame = UIErrorsFrame
	if not frame then return end
	if hide and not errorsOff then
		frame:UnregisterEvent("UI_ERROR_MESSAGE")
		errorsOff = true
	elseif not hide and errorsOff then
		frame:RegisterEvent("UI_ERROR_MESSAGE")
		errorsOff = false
	end
end

local function SetStatusHidden(hide)
	local status = ActionStatus
	if not status then return end
	if hide and not statusOff then
		status:UnregisterEvent("SCREENSHOT_SUCCEEDED")
		status:UnregisterEvent("SCREENSHOT_FAILED")
		statusOff = true
	elseif not hide and statusOff then
		status:RegisterEvent("SCREENSHOT_SUCCEEDED")
		status:RegisterEvent("SCREENSHOT_FAILED")
		statusOff = false
	end
end

-- Hide modes: filter (categories), combat (all red errors while in combat;
-- that reads the combat state, not combat data), always.
function M:UpdateErrorFilter(inCombat)
	local hide = U.Allowed(ERRORS, "hide")
	local db = self.db.errors
	local mode = hide and db.mode or "off"
	if inCombat == nil then inCombat = InCombatLockdown() end
	SetErrorEvent(mode == "always" or (mode == "combat" and inCombat))
	if mode == "filter" then
		for category, list in pairs(BuildTypes()) do
			for _, messageType in ipairs(list) do SetTypeHidden(messageType, db.categories[category]) end
		end
	else
		for messageType in pairs(disabledTypes) do SetTypeHidden(messageType, false) end
	end
	SetStatusHidden(hide and db.hideStatus)
end

local function ApplyErrors(state)
	E:OnBlizzardAddOn("Blizzard_UIErrorsFrame", function()
		local frame = UIErrorsFrame
		if not frame or not M.active or not E:BlizzardAllowed(ERRORS) then return end
		state = E:BlizzardState(ERRORS)
		local db = M.db.errors
		if not errorsHooked then
			errorsHooked = true
			U.On("PLAYER_REGEN_DISABLED", function() M:UpdateErrorFilter(true) end)
			U.On("PLAYER_REGEN_ENABLED", function() M:UpdateErrorFilter(false) end)
		end
		M:UpdateErrorFilter()
		if state.skin then
			U.SkinFont(frame, db.fontSize)
			if ActionStatus and ActionStatus.Text then U.SkinFont(ActionStatus.Text) end
			if db.duration > 0 and frame.SetTimeVisible then
				if timeVisible == nil then timeVisible = frame:GetTimeVisible() end
				frame:SetTimeVisible(db.duration)
			elseif timeVisible ~= nil then
				frame:SetTimeVisible(timeVisible)
				timeVisible = nil
			end
		else
			U.RestoreFont(frame)
			if ActionStatus and ActionStatus.Text then U.RestoreFont(ActionStatus.Text) end
			if timeVisible ~= nil then
				frame:SetTimeVisible(timeVisible)
				timeVisible = nil
			end
		end
		if state.move then
			U.Pin(frame, U.Holder("Errors"), "TOP", "TOP", 0, 0, function() return U.Allowed(ERRORS, "move") end)
			U.SetScale(frame, db.scale)
		else
			U.Unpin(frame)
			U.RestoreScale(frame)
		end
	end)
end

local function RestoreErrors()
	local frame = UIErrorsFrame
	if not frame then return end
	SetErrorEvent(false)
	for messageType in pairs(disabledTypes) do SetTypeHidden(messageType, false) end
	SetStatusHidden(false)
	U.RestoreFont(frame)
	if ActionStatus and ActionStatus.Text then U.RestoreFont(ActionStatus.Text) end
	if timeVisible ~= nil then
		frame:SetTimeVisible(timeVisible)
		timeVisible = nil
	end
	U.Unpin(frame)
	U.RestoreScale(frame)
end

U.Element(ERRORS, {
	apply = ApplyErrors,
	restore = RestoreErrors,
	handler = {
		reload = {},
		install = { skin = true, move = true },
	},
})

M.tests.errors = function()
	if not UIErrorsFrame then return end
	local r, g, b = 1, 0.1, 0.1
	if _G.RED_FONT_COLOR then r, g, b = _G.RED_FONT_COLOR:GetRGB() end
	UIErrorsFrame:AddMessage(L["EldoUI test: red error text"], r, g, b, 1)
end

---------------------------------------------------------------------------
-- Zone text
---------------------------------------------------------------------------
local function ZoneStrings()
	local db = M.db.zoneText
	return {
		{ ZoneTextString, db.zoneSize },
		{ SubZoneTextString, db.subZoneSize },
		{ PVPInfoTextString, db.pvpSize },
		{ PVPArenaTextString, db.pvpSize },
	}
end

local function ApplyZone(state)
	local db = M.db.zoneText
	for _, entry in ipairs(ZoneStrings()) do
		if entry[1] then
			if state.skin then U.SkinFont(entry[1], entry[2]) else U.RestoreFont(entry[1]) end
		end
	end
	if state.move and ZoneTextFrame then
		U.Pin(ZoneTextFrame, U.Holder("ZoneText"), "TOP", "TOP", 0, 0, function() return U.Allowed(ZONE, "move") end)
		U.SetScale(ZoneTextFrame, db.scale)
		U.SetScale(SubZoneTextFrame, db.scale)
	else
		U.Unpin(ZoneTextFrame)
		U.RestoreScale(ZoneTextFrame)
		U.RestoreScale(SubZoneTextFrame)
	end
	U.Park(ZoneTextFrame, state.hide and db.hidePart == "both")
	U.Park(SubZoneTextFrame, state.hide and true or false)
end

local function RestoreZone()
	for _, entry in ipairs(ZoneStrings()) do U.RestoreFont(entry[1]) end
	U.Unpin(ZoneTextFrame)
	U.RestoreScale(ZoneTextFrame)
	U.RestoreScale(SubZoneTextFrame)
	U.Park(ZoneTextFrame, false)
	U.Park(SubZoneTextFrame, false)
end

U.Element(ZONE, {
	apply = ApplyZone,
	restore = RestoreZone,
	handler = {
		reload = {},
		install = { skin = true },
	},
})

---------------------------------------------------------------------------
-- Battleground messages as big text
---------------------------------------------------------------------------
local BG_EVENTS = {
	CHAT_MSG_BG_SYSTEM_ALLIANCE = "BG_SYSTEM_ALLIANCE",
	CHAT_MSG_BG_SYSTEM_HORDE = "BG_SYSTEM_HORDE",
	CHAT_MSG_BG_SYSTEM_NEUTRAL = "BG_SYSTEM_NEUTRAL",
}
local bgFrame

local function BGFrame()
	if bgFrame then return bgFrame end
	bgFrame = CreateFrame("MessageFrame", "EldoUI_BGMessages", UIParent)
	bgFrame:SetSize(800, 90)
	bgFrame:SetFrameStrata("HIGH")
	bgFrame:SetInsertMode("TOP")
	bgFrame:SetJustifyH("CENTER")
	bgFrame:SetFading(true)
	bgFrame:SetFadeDuration(1)
	bgFrame:EnableMouse(false)
	return bgFrame
end

-- Right under Blizzard's raid warnings (wherever they sit), so both read as
-- one lane.
function M:ApplyBGMessages()
	local db = self.db.bgMessages
	if not (self.active and db.enabled) then
		if bgFrame then
			bgFrame:Clear()
			bgFrame:Hide()
		end
		return
	end
	local frame = BGFrame()
	frame:ClearAllPoints()
	local anchor = RaidWarningFrame
	if anchor then
		frame:SetPoint("TOP", anchor, "BOTTOM", 0, -4)
	else
		frame:SetPoint("TOP", UIParent, "TOP", 0, -300)
	end
	-- Battleground messages are what other players wrote: the name font.
	E:SetNameTextFont(frame, db.fontSize, E.db.general.fontOutline or "OUTLINE")
	frame:SetTimeVisible(db.duration)
	frame:Show()
end

function M:AddBGMessage(text, chatType)
	if not (self.active and self.db.bgMessages.enabled) then return end
	if type(text) ~= "string" or U.Secret(text) then return end
	local frame = BGFrame()
	if not frame:IsShown() then self:ApplyBGMessages() end
	local info = _G.ChatTypeInfo and _G.ChatTypeInfo[chatType]
	local r, g, b = 1, 0.82, 0
	if info and info.r then r, g, b = info.r, info.g, info.b end
	frame:AddMessage(text, r, g, b)
end

for event, chatType in pairs(BG_EVENTS) do
	U.On(event, function(_, text) M:AddBGMessage(text, chatType) end)
end

U.OnEnable(function() E:OnBlizzardAddOn("Blizzard_RaidWarning", function() M:ApplyBGMessages() end) end)
U.OnDisable(function() M:ApplyBGMessages() end)
U.OnProfile(function() M:ApplyBGMessages() end)

M.tests.bg = function()
	if not M.db.bgMessages.enabled then
		E:Print(L["Turn on battleground messages first (Alerts and Banners > Raid warnings)."])
		return
	end
	M:AddBGMessage(L["EldoUI test: the Alliance has taken the flag!"], "BG_SYSTEM_ALLIANCE")
end
