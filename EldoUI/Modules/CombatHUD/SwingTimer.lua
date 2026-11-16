-- Combat HUD: swing timers.
--
-- 1. Blizzard's own Forever swing timer (SwingTimerMainHandFrame,
--    SwingTimerOffHandFrame, SwingTimerRangedFrame): skin, one mover per
--    bar, size, texture and colors, title and time. Element "swing-timer".
-- 2. EldoUI's own swing bars (optional, off by default): drawn from the
--    game's PLAYER_SWING event, whose swing duration is handed to the bar
--    as it is. No combat log, no attack-speed math, no guessing.
--    Range dimming comes from PLAYER_SWING_RANGE_UPDATE.
-- Written from scratch for EldoUI.
local _, E = ...
local L = E.L
local Key = E.Key
local K = E.CombatKit
local M = E.CombatHUD

local ID = "swing-timer"
local GROUP = "swing"
local OUT_OF_RANGE_ALPHA = 0.4

local BARS = {
	{ key = "mainHand", global = "SwingTimerMainHandFrame", mover = "EldoUI_SwingMainHand", title = "Swing: Main Hand",
		point = { "CENTER", "UIParent", "CENTER", 0, -300 }, swingType = 0, label = _G.SWING_TIMER_MAIN_HAND or Key("Main Hand") },
	{ key = "offHand", global = "SwingTimerOffHandFrame", mover = "EldoUI_SwingOffHand", title = "Swing: Off Hand",
		point = { "CENTER", "UIParent", "CENTER", 0, -318 }, swingType = 1, label = _G.SWING_TIMER_OFF_HAND or Key("Off Hand") },
	{ key = "ranged", global = "SwingTimerRangedFrame", mover = "EldoUI_SwingRanged", title = "Swing: Ranged",
		point = { "CENTER", "UIParent", "CENTER", 0, -336 }, swingType = 2, label = _G.SWING_TIMER_RANGED or Key("Ranged") },
}

local function DB() return M.db.swing end
-- A kept swing timer addon (Data/Competitors.lua) takes the swing rows.
local function Allowed(action) return M.active and E:BlizzardAllowed(ID, action) and not E:StandsBack("CombatHUD", "swing") end

local function FontFile()
	return K.FontPath(DB().font)
end

local function BarColor(def)
	local db = DB()
	if db.colorMode == "accent" then
		local r, g, b = unpack(E.media.accentColor)
		return r, g, b
	elseif db.colorMode == "class" then
		return E:ClassColor("player")
	end
	return unpack(db.colors[def.key])
end

-- Move mode's stand-in while no swing runs: the bar in its size, color,
-- title and time.
local function StandIn(def)
	return function()
		local db = DB()
		return "bar", {
			width = db.width, height = db.height, color = { BarColor(def) }, fontSize = db.fontSize,
			left = db.showTitle and def.label or nil, right = db.showTime and "1.8" or nil,
		}
	end
end

-- Both features share the three holders and movers.
local function Holders()
	for _, def in ipairs(BARS) do
		if not K.GetHolder(def.mover) then
			K.Holder(M, def.mover, L[def.title], def.point, DB().width, DB().height,
				{ sizeKeys = { width = { key = "swing.width", min = 80, max = 500 }, height = { key = "swing.height", min = 4, max = 40 } },
					sample = { config = StandIn(def) } })
		end
		K.GetHolder(def.mover):SetSize(DB().width, DB().height)
	end
end

---------------------------------------------------------------------------
-- 1. Blizzard's swing timer
---------------------------------------------------------------------------
local F = { key = "swing", id = ID, title = "Swing timer",
	install = { skin = true, move = true }, reload = { skin = true, move = true } }

F.defaults = {
	width = 240, height = 14,
	texture = "", font = "THEME", fontSize = 11,
	colorMode = "blizzard",
	colors = { mainHand = { 0.85, 0.7, 0.3 }, offHand = { 0.6, 0.6, 0.9 }, ranged = { 0.45, 0.8, 0.45 } },
	spark = true,
	showTitle = true, showTime = true,
	hide = { mainHand = true, offHand = true, ranged = true },
}

local hooked = setmetatable({}, { __mode = "k" })

-- Blizzard re-sets the art alpha when the range state changes.
local function AfterRange(frame)
	if not Allowed("skin") then return end
	K.Alpha0(GROUP, frame.Background, frame.Border)
	if frame.Background then frame.Background:SetAlpha(0) end
	if frame.Border then frame.Border:SetAlpha(0) end
	local bd = K.GetBackdrop(frame)
	local alpha = frame.StatusBar and frame.StatusBar:GetAlpha()
	if bd and alpha and K.Plain(alpha) then bd:SetAlpha(alpha) end
end

local function SkinBar(def, frame)
	local db = DB()
	local bar = frame.StatusBar
	AfterRange(frame)
	if bar then
		if db.colorMode ~= "blizzard" then
			K.BarTexture(GROUP, bar, K.TexturePath(db.texture ~= "" and db.texture or nil))
			bar:SetStatusBarColor(BarColor(def))
		end
		K.Backdrop(GROUP, frame, bar, E.pixel, true)
		if bar.Pip then
			K.Alpha0(GROUP, bar.Pip)
			if db.spark then bar.Pip:SetAlpha(1) end
		end
		K.Alpha0(GROUP, bar.TypeLabelShadow)
		K.Font(GROUP, bar.TypeLabel, db.fontSize, nil, FontFile())
		K.Font(GROUP, bar.TimeLabel, db.fontSize, nil, FontFile())
	end
end

-- Title and time: EldoUI can only take them away; showing follows Edit Mode.
local function Labels(frame)
	local db = DB()
	local bar = frame.StatusBar
	if not bar then return end
	if not db.showTitle then K.Alpha0(GROUP .. "labels", bar.TypeLabel, bar.TypeLabelShadow)
	else K.Undo(GROUP .. "labels") end
	if not db.showTime then K.Alpha0(GROUP .. "time", bar.TimeLabel)
	else K.Undo(GROUP .. "time") end
end

function F:Setup()
	Holders()
end

function F:Apply(db)
	Holders()
	for _, def in ipairs(BARS) do
		local frame = _G[def.global]
		if frame then
			if not hooked[frame] then
				hooked[frame] = true
				if type(frame.ApplyRangePresentation) == "function" then
					hooksecurefunc(frame, "ApplyRangePresentation", AfterRange)
				end
			end
			if Allowed("skin") then SkinBar(def, frame) end
			Labels(frame)
			local holder = K.GetHolder(def.mover)
			if Allowed("move") then
				K.Pin(frame, {
					anchor = function() return "CENTER", holder, "CENTER", 0, 0 end,
					scale = function() return 1 end,
					size = function() return DB().width, DB().height end,
					active = function() return Allowed("move") end,
				})
			else
				K.Unpin(frame)
			end
			if E:BlizzardHidden(ID) and db.hide[def.key] then
				K.Parent(frame, K.hider)
			else
				K.RestoreParent(frame)
			end
		end
	end
	if not Allowed("skin") then K.Undo(GROUP) end
end

function F:Restore()
	for _, def in ipairs(BARS) do
		local frame = _G[def.global]
		if frame then
			K.Unpin(frame)
			K.RestoreParent(frame)
		end
	end
	K.Undo(GROUP)
	K.Undo(GROUP .. "labels")
	K.Undo(GROUP .. "time")
end

local NotHide = M.Off(ID, "hide")
-- Rows shared with EldoUI's own swing bars show while either is on.
local function Shared(action)
	local blizzard = M.Off(ID, action)
	return function() return blizzard() and not (M.db and M.db.swingbars and M.db.swingbars.enabled) end
end
local function Textures() local v = K.TextureValues(); v[""] = L["Theme texture"]; return v end
local COLOR_MODES = { blizzard = "Blizzard art", custom = "Color per bar", class = "Class color", accent = "Accent color" }

F.switches = {
	skin = L["Flat bar, 1 px border and theme font on Blizzard's swing timer."],
	move = L["One mover per bar (main hand, off hand, ranged) and the size below."],
	hide = L["Hide the bars checked below."],
}
F.note = L["Blizzard's own swing timer shows when Interface > Combat > Swing Timer is on. Its Edit Mode visibility still applies."]
F.options = {
	{ type = "header", label = "Size", hidden = Shared("move") },
	{ type = "range", unit = "px", key = "swing.width", label = "Width", min = 80, max = 500, step = 1, hidden = Shared("move"),
		desc = "Width of every swing bar (also EldoUI's own bars)." },
	{ type = "range", unit = "px", key = "swing.height", label = "Height", min = 4, max = 40, step = 1, hidden = Shared("move"),
		desc = "Height of every swing bar (also EldoUI's own bars)." },
	{ type = "header", label = "Look", hidden = Shared("skin") },
	{ type = "select", key = "swing.colorMode", label = "Bar color", values = COLOR_MODES, hidden = Shared("skin"),
		desc = "Blizzard art keeps Blizzard's fill textures; the others use the texture below." },
	{ type = "select", key = "swing.texture", label = "Bar texture", values = Textures, hidden = Shared("skin"),
		desc = "Texture of the swing bars." },
	{ type = "color", key = "swing.colors.mainHand", label = "Main hand color", hidden = Shared("skin"), desc = "Used with Color per bar." },
	{ type = "color", key = "swing.colors.offHand", label = "Off hand color", hidden = Shared("skin"), desc = "Used with Color per bar." },
	{ type = "color", key = "swing.colors.ranged", label = "Ranged color", hidden = Shared("skin"), desc = "Used with Color per bar." },
	{ type = "toggle", key = "swing.spark", label = "Spark", hidden = Shared("skin"), desc = "The bright tip at the end of the bar." },
	{ type = "media", mediaKind = "font", default = "THEME", defaultLabel = "Theme font", key = "swing.font", label = "Font", hidden = Shared("skin"), desc = "Font of the title and time." },
	{ type = "range", key = "swing.fontSize", label = "Text size", min = 6, max = 20, step = 1, hidden = Shared("skin"),
		desc = "Size of the title and time." },
	{ type = "header", label = "Text", hidden = Shared() },
	{ type = "toggle", key = "swing.showTitle", label = "Show bar title", hidden = Shared(),
		desc = "The \"Main Hand\" / \"Off Hand\" / \"Ranged\" title. Off hides it; on follows Edit Mode." },
	{ type = "toggle", key = "swing.showTime", label = "Show time", hidden = Shared(),
		desc = "The remaining swing time. Off hides it; on follows Edit Mode." },
	{ type = "header", label = "Hide", hidden = NotHide },
	{ type = "toggle", key = "swing.hide.mainHand", label = "Hide main hand", hidden = NotHide, desc = "Blizzard's main-hand swing bar stays hidden." },
	{ type = "toggle", key = "swing.hide.offHand", label = "Hide off hand", hidden = NotHide, desc = "Blizzard's off-hand swing bar stays hidden." },
	{ type = "toggle", key = "swing.hide.ranged", label = "Hide ranged", hidden = NotHide, desc = "Blizzard's ranged swing bar stays hidden." },
}

M:AddFeature(F)

---------------------------------------------------------------------------
-- 2. EldoUI's own swing bars (PLAYER_SWING)
---------------------------------------------------------------------------
local O = { key = "swingbars", title = "Own swing bars" }
O.defaults = {
	enabled = false,
	mainHand = true, offHand = true, ranged = true,
	inCombatOnly = true,
}

local own = {}          -- swingType -> bar

local function OwnUpdate(bar)
	local remaining = bar.endTime - GetTime()
	if remaining <= 0 then
		bar:SetValue(1)
		bar.time:SetText("")
		bar:SetScript("OnUpdate", nil)
		bar.swinging = nil
		if O.ShowState then O.ShowState(bar) end
		return
	end
	bar:SetValue(1 - remaining / bar.duration)
	bar.time:SetFormattedText("%.1f", remaining)
end

local function CreateOwnBar(def)
	local bar = CreateFrame("StatusBar", nil, UIParent)
	bar:SetMinMaxValues(0, 1)
	bar:SetValue(0)
	E:SetTemplate(bar, true)
	bar.title = E:CreateText(bar, E.tokens.size.small, "LEFT")
	bar.title:SetPoint("LEFT", 4, 0)
	bar.time = E:CreateText(bar, E.tokens.size.small, "RIGHT")
	bar.time:SetPoint("RIGHT", -4, 0)
	bar.spark = bar:CreateTexture(nil, "OVERLAY")
	bar.spark:SetColorTexture(1, 1, 1, 0.8)
	bar.spark:SetWidth(2)
	bar.def = def
	bar:Hide()
	return bar
end

function O.ShowState(bar)
	local db = M.db.swingbars
	local show = db.enabled and db[bar.def.key]
	if show and db.inCombatOnly then
		local combat = UnitAffectingCombat("player")
		if not K.Plain(combat) then combat = true end
		show = bar.swinging or (combat and bar.everSwung)
	end
	bar:SetShown(show and true or false)
end

local function StyleOwn(bar)
	local db = DB()
	local holder = K.GetHolder(bar.def.mover)
	bar:ClearAllPoints()
	bar:SetPoint("CENTER", holder, "CENTER")
	bar:SetSize(db.width, db.height)
	bar:SetStatusBarTexture(K.TexturePath(db.texture ~= "" and db.texture or nil))
	local r, g, b
	if db.colorMode == "blizzard" then r, g, b = unpack(db.colors[bar.def.key]) else r, g, b = BarColor(bar.def) end
	bar:SetStatusBarColor(r, g, b)
	bar.spark:ClearAllPoints()
	bar.spark:SetPoint("TOP", bar:GetStatusBarTexture(), "TOPRIGHT")
	bar.spark:SetPoint("BOTTOM", bar:GetStatusBarTexture(), "BOTTOMRIGHT")
	bar.spark:SetShown(db.spark)
	E:SetFont(bar.title, db.fontSize, nil, FontFile)
	E:SetFont(bar.time, db.fontSize, nil, FontFile)
	bar.title:SetText(E:Translate(bar.def.label))
	bar.title:SetShown(db.showTitle)
	bar.time:SetShown(db.showTime)
end

local function OnSwing(_, _, duration, swingType)
	local bar = K.Plain(swingType) and own[swingType]
	if not bar or not M.db.swingbars[bar.def.key] then return end
	-- The duration is the game's own; a secret one (never seen so far) is skipped.
	if not K.Plain(duration) or not duration or duration <= 0 then return end
	bar.duration = duration
	bar.endTime = GetTime() + duration
	bar.swinging = true
	bar.everSwung = true
	bar:SetValue(0)
	bar:SetScript("OnUpdate", OwnUpdate)
	O.ShowState(bar)
end

local function OnRange(_, _, swingType, inRange, checksRange)
	local bar = K.Plain(swingType) and own[swingType]
	if not bar then return end
	local out = K.Plain(inRange, checksRange) and checksRange and not inRange
	bar:SetAlpha(out and OUT_OF_RANGE_ALPHA or 1)
end

local function OnCombat(_, event)
	for _, bar in pairs(own) do
		if event == "PLAYER_REGEN_ENABLED" then bar.everSwung = nil end
		O.ShowState(bar)
	end
end

-- PLAYER_SWING exists on Forever only; never register an unknown event.
local function Register(event, fn)
	if C_EventUtils and C_EventUtils.IsEventValid and not C_EventUtils.IsEventValid(event) then return end
	E:RegisterEvent(event, fn, O)
end

function O:Setup()
	Holders()
	for _, def in ipairs(BARS) do own[def.swingType] = CreateOwnBar(def) end
end

function O:Apply()
	Holders()
	for _, bar in pairs(own) do
		StyleOwn(bar)
		O.ShowState(bar)
	end
	Register("PLAYER_SWING", OnSwing)
	Register("PLAYER_SWING_RANGE_UPDATE", OnRange)
	Register("PLAYER_REGEN_DISABLED", OnCombat)
	Register("PLAYER_REGEN_ENABLED", OnCombat)
end

function O:Restore()
	for _, event in ipairs({ "PLAYER_SWING", "PLAYER_SWING_RANGE_UPDATE", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do
		E:UnregisterEvent(event, O)
	end
	for _, bar in pairs(own) do
		bar:SetScript("OnUpdate", nil)
		bar.swinging, bar.everSwung, bar.duration, bar.endTime = nil, nil, nil, nil
		bar:SetValue(0)
		bar.time:SetText("")
		bar:SetAlpha(1)
		bar:Hide()
	end
end

local function OwnOff() return not (M.db and M.db.swingbars and M.db.swingbars.enabled) end
O.note = L["EldoUI's swing bars, drawn from the game's swing event, with the movers and settings of the Swing timer tab. Hide Blizzard's bars there."]
O.options = {
	{ type = "toggle", key = "swingbars.enabled", label = "Own swing bars", desc = "Show EldoUI's own swing bars." },
	{ type = "toggle", key = "swingbars.mainHand", label = "Main hand", hidden = OwnOff, desc = "A bar for main-hand swings." },
	{ type = "toggle", key = "swingbars.offHand", label = "Off hand", hidden = OwnOff, desc = "A bar for off-hand swings." },
	{ type = "toggle", key = "swingbars.ranged", label = "Ranged", hidden = OwnOff, desc = "A bar for ranged and wand shots." },
	{ type = "toggle", key = "swingbars.inCombatOnly", label = "Only in combat", hidden = OwnOff,
		desc = "Bars show from the first swing in combat and hide when combat ends." },
}

M:AddFeature(O)
