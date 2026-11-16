-- Combat HUD: Blizzard's damage meter.
-- Skins Blizzard's own meter windows and places the main window on the
-- EldoUI_Details mover (the layouts' meter corner). The numbers are
-- Blizzard's: values are secret in combat, so EldoUI never reads them and
-- never builds its own meter. "Hide" and "Replace" switch Blizzard's meter
-- off (CVar damageMeterEnabled) so Details! or another meter can take the
-- corner; Details! stays a separate addon with its own setup.
-- Encounter timeline and boss warnings are not on Forever (dropped).
--
-- Skin mode only, for now: EldoUI still draws no meter windows
-- of its own. This file adds
--   * the combat timer: E:GetCombatTime(), the one fight-length source the
--     InfoBar's "Combat time" datatext reads, and an optional small
--     timer display on its own mover (EldoUI_CombatTimer);
--   * /eui meter toggle | reset: show/hide Blizzard's meter and clear its
--     sessions (both only on the player's command; bind a macro to them).
-- Written from scratch for EldoUI.
local _, E = ...
local L = E.L
local K = E.CombatKit
local M = E.CombatHUD

local ID = "damage-meter"
local GROUP = "meter"
local MOVER = "EldoUI_Details"
local WINDOWS = 3 -- DamageMeterSessionWindow1..3

local F = { key = "meter", id = ID, title = "Damage meter", addon = "Blizzard_DamageMeter",
	install = { skin = true, move = true }, reload = { skin = true, move = true } }

F.defaults = {
	width = 440, height = 240,
	dock = "mover", dockGap = 6,
	texture = "", font = "THEME", fontSize = 12,
	colorMode = "blizzard",
	background = 60,
	visibility = E:VisibilityDefaults(), -- the shared visibility rules
	resetOnInstance = "blizzard",
}

local entryHooked = setmetatable({}, { __mode = "k" })
local windowSkinned = setmetatable({}, { __mode = "k" })
local entryColor = setmetatable({}, { __mode = "k" })

local function DB() return M.db.meter end
local function Allowed(action) return M.active and E:BlizzardAllowed(ID, action) end

local function FontFile()
	return K.FontPath(DB().font)
end

---------------------------------------------------------------------------
-- Entries (bars)
---------------------------------------------------------------------------
-- EldoUI color for an entry, or nil to keep Blizzard's.
local function EntryColor(entry)
	local mode = DB().colorMode
	if mode == "accent" then
		local r, g, b = unpack(E.media.accentColor)
		return r, g, b
	elseif mode == "class" then
		local class = entry.classFilename or entry.unitClassFilename
		if class and K.Plain(class) then
			local color = E:ClassColorObject(class)
			if color then return color.r, color.g, color.b end
		end
	end
end

local function ColorEntry(entry)
	local bar = entry.StatusBar
	local texture = bar and bar:GetStatusBarTexture()
	if not texture then return end
	local r, g, b = EntryColor(entry)
	if r then
		entryColor[entry] = true
		texture:SetVertexColor(r, g, b)
	elseif entryColor[entry] then
		-- Back to Blizzard's color (its color object for this entry).
		entryColor[entry] = nil
		local color = entry.statusBarColor
		if color and color.GetRGB then texture:SetVertexColor(color:GetRGB()) end
	end
end

-- The skin's font on a name (K.Font), then the name font of that font, so
-- a name in another alphabet keeps its letters.
local function NameFont(fs, size, outline, font)
	K.Font(GROUP, fs, size, outline, font)
	if type(fs) == "table" and fs.GetFont then
		local path, height, flags = fs:GetFont()
		if path then E:SetNameFont(fs, path, height, flags) end
	end
end

local function SkinEntry(entry)
	if not Allowed("skin") or not K.Usable(entry) then return end
	local db = DB()
	local bar = entry.StatusBar
	if bar then
		K.BarTexture(GROUP, bar, K.TexturePath(db.texture ~= "" and db.texture or nil))
		-- Background art stays invisible; Blizzard resets its alpha in UpdateBackground.
		K.Alpha0(GROUP, bar.Background, bar.BackgroundEdge)
		if bar.Background then bar.Background:SetAlpha(0) end
		if bar.BackgroundEdge then bar.BackgroundEdge:SetAlpha(0) end
		K.Backdrop(GROUP, bar, bar, E.pixel, true)
		NameFont(bar.Name, db.fontSize, nil, FontFile())
		K.Font(GROUP, bar.Value, db.fontSize, nil, FontFile())
	end
	if entry.Icon and entry.Icon.Icon then K.TexCoord(GROUP, entry.Icon.Icon) end
	ColorEntry(entry)
end

local function HookEntry(entry)
	if not K.Usable(entry) then return end
	if not entryHooked[entry] then
		entryHooked[entry] = true
		for _, method in ipairs({ "UpdateStyle", "UpdateBackground", "SetStatusBarColor" }) do
			if type(entry[method]) == "function" then
				hooksecurefunc(entry, method, function(self)
					if Allowed("skin") then SkinEntry(self) end
				end)
			end
		end
	end
	SkinEntry(entry)
end

---------------------------------------------------------------------------
-- Windows
---------------------------------------------------------------------------
local function SkinWindow(window)
	if not K.Usable(window) or not Allowed("skin") then return end
	local db = DB()
	K.Alpha0(GROUP, window.Header)
	local container = window.MinimizeContainer
	local bd = K.Backdrop(GROUP, window, window, 0, true)
	if bd then bd:SetBackdropColor(0, 0, 0, (db.background or 60) / 100) end
	if bd then E:SetStyleEdge(bd) end -- WoW Forever art style frame line
	if container and container.Background then K.Alpha0(GROUP, container.Background) end
	K.Font(GROUP, window.SessionTimer, db.fontSize, nil, FontFile())
	if window.SessionDropdown then K.Font(GROUP, window.SessionDropdown.SessionName, db.fontSize, nil, FontFile()) end
	if window.DamageMeterTypeDropdown then K.Font(GROUP, window.DamageMeterTypeDropdown.TypeName, db.fontSize, nil, FontFile()) end
	if not windowSkinned[window] then
		windowSkinned[window] = true
		-- Core skin helpers (undone by a reload).
		if container then
			E:SkinScrollBar(container.ScrollBar)
			E:HookScrollBoxRows(container.ScrollBox, HookEntry)
			if container.LocalPlayerEntry then HookEntry(container.LocalPlayerEntry) end
			local source = container.SourceWindow
			if source then
				if source.Background then K.Alpha0(GROUP, source.Background) end
				K.Backdrop(GROUP, source, source, 0, true)
				E:SkinScrollBar(source.ScrollBar)
				E:HookScrollBoxRows(source.ScrollBox, HookEntry)
			end
		end
		-- Blizzard resets the window background alpha from its opacity setting.
		if type(window.SetBackgroundAlpha) == "function" then
			hooksecurefunc(window, "SetBackgroundAlpha", function(self)
				if Allowed("skin") and self.MinimizeContainer and self.MinimizeContainer.Background then
					self.MinimizeContainer.Background:SetAlpha(0)
				end
			end)
		end
	end
	if container and container.ScrollBox then
		E:EachScrollBoxRow(container.ScrollBox, SkinEntry)
	end
end

local function SkinAll()
	for index = 1, WINDOWS do
		local window = _G["DamageMeterSessionWindow" .. index]
		if window then SkinWindow(window) end
	end
end

---------------------------------------------------------------------------
-- Placement
---------------------------------------------------------------------------
local function DockHolder(holder)
	local db = DB()
	local mover = E.movers[MOVER]
	holder:ClearAllPoints()
	local gap = db.dockGap or 6
	if db.dock == "chat" and E.movers.EldoUI_Chat then
		-- Bottom-right corner, as tall as the chat (a "right chat" panel).
		local chat = E.movers.EldoUI_Chat
		holder:SetSize(db.width, chat:GetHeight())
		holder:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -(chat:GetLeft() or 19), chat:GetBottom() or 36)
	elseif db.dock == "bags" and E.movers.EldoUI_BagsAnchor then
		holder:SetSize(db.width, db.height)
		holder:SetPoint("TOPRIGHT", E.movers.EldoUI_BagsAnchor, "BOTTOMRIGHT", 0, -gap)
	else
		holder:SetSize(db.width, db.height)
		holder:SetPoint("CENTER", mover, "CENTER")
	end
end

function F:Setup()
	self.holder = K.Holder(M, MOVER, L["Damage Meter"], { "BOTTOMRIGHT", "UIParent", "BOTTOMRIGHT", -19, 36 }, DB().width, DB().height,
		{ sizeKeys = { width = { key = "meter.width", min = 200, max = 800 }, height = { key = "meter.height", min = 100, max = 600 } } })
	-- Session windows created later (a second or third window) get the skin too.
	if DamageMeter and type(DamageMeter.SetupSessionWindow) == "function" then
		hooksecurefunc(DamageMeter, "SetupSessionWindow", function()
			if Allowed("skin") then SkinAll() end
		end)
	end
end

function F:Apply(db)
	local meter = DamageMeter
	if not meter then return end
	-- Hide / Replace: Blizzard's own switch for its meter.
	if E:BlizzardHidden(ID) then
		E:SetCVar("damageMeterEnabled", "0", ID)
	else
		-- The player's own value comes back once; their later choice in the
		-- game's options stays.
		E:ReleaseCVar("damageMeterEnabled", ID)
	end
	if db.resetOnInstance ~= "blizzard" then
		E:SetCVar("damageMeterResetOnNewInstance", db.resetOnInstance == "on" and "1" or "0", ID)
	else
		E:RestoreCVar("damageMeterResetOnNewInstance", ID)
	end
	if Allowed("skin") then SkinAll() else K.Undo(GROUP) end
	if Allowed("move") then
		DockHolder(self.holder)
		K.Pin(meter, {
			anchor = function() return "TOPLEFT", self.holder, "TOPLEFT", 0, 0 end,
			size = function() return self.holder:GetWidth(), self.holder:GetHeight() end,
			active = function() return Allowed("move") end,
		})
	else
		K.Unpin(meter)
	end
	if M.meterHiddenByCommand then
		-- /eui meter toggle: hidden until toggled again (this session only).
		K.Parent(meter, K.Visibility("meter", nil, "never", 0))
	elseif not E:VisibilityIsPlain(db.visibility) then
		K.Parent(meter, K.Visibility("meter", meter, db.visibility))
	else
		K.StopVisibility("meter")
		K.RestoreParent(meter)
	end
end

-- Settings before the shared visibility rules: "Hide out of combat"
-- becomes the In combat rule, once.
function F:Migrate(db)
	if type(db) ~= "table" or db.hideOutOfCombat == nil then return end
	if db.hideOutOfCombat then db.visibility = E:VisibilityDefaults({ show = "combat" }) end
	E:NormalizeVisibility(db.visibility)
	db.hideOutOfCombat = nil
end

function F:Restore()
	local meter = DamageMeter
	if meter then
		K.Unpin(meter)
		K.StopVisibility("meter")
		K.RestoreParent(meter)
	end
	K.Undo(GROUP)
end

---------------------------------------------------------------------------
-- Options
---------------------------------------------------------------------------
local NotSkin, NotMove = M.Off(ID, "skin"), M.Off(ID, "move")
local function Off() return not E:BlizzardAllowed(ID) end
local function Textures() local v = K.TextureValues(); v[""] = L["Theme texture"]; return v end

F.switches = {
	skin = L["EldoUI look: flat bars, theme font and texture, a see-through box behind each window."],
	move = L["Place the main window on the damage meter mover (EldoUI_Details) and size it here."],
	hide = L["Switch Blizzard's damage meter off, for example when you use Details!."],
	replace = L["Same as Hide: Blizzard's meter is switched off so Details! or another meter takes the corner. EldoUI has no meter of its own (the numbers are secret in combat)."],
}
F.note = L["Blizzard decides what the meter counts. Its own settings (Edit Mode and the window's cog menu) still apply."]
F.options = {
	{ type = "header", label = "Position and size", hidden = NotMove },
	{ type = "select", key = "meter.dock", label = "Dock", hidden = NotMove,
		values = { mover = "Own mover", chat = "Bottom right, as tall as the chat", bags = "Below the bags" },
		desc = "Own mover: drag it in move mode. The other choices follow the chat or the bag position." },
	{ type = "range", unit = "px", key = "meter.dockGap", label = "Gap", min = 0, max = 30, step = 1, hidden = NotMove,
		desc = "Space to the frame the meter is docked to." },
	{ type = "range", unit = "px", key = "meter.width", label = "Width", min = 200, max = 800, step = 1, hidden = NotMove,
		desc = "Width of the main meter window." },
	{ type = "range", unit = "px", key = "meter.height", label = "Height", min = 100, max = 600, step = 1, hidden = NotMove,
		desc = "Height of the main meter window (not used when docked as tall as the chat)." },
	{ type = "header", label = "Look", hidden = NotSkin },
	{ type = "select", key = "meter.texture", label = "Bar texture", values = Textures, hidden = NotSkin,
		desc = "Texture of the meter bars." },
	{ type = "media", mediaKind = "font", default = "THEME", defaultLabel = "Theme font", key = "meter.font", label = "Font", hidden = NotSkin,
		desc = "Font of names, values and the window header." },
	{ type = "range", key = "meter.fontSize", label = "Text size", min = 8, max = 20, step = 1, hidden = NotSkin,
		desc = "Size of names and values (Blizzard's text scale still applies on top)." },
	{ type = "select", key = "meter.colorMode", label = "Bar colors", hidden = NotSkin,
		values = { blizzard = "Blizzard's setting", class = "Class colors", accent = "Accent color" },
		desc = "Blizzard's setting follows the game's own class color option. Class colors colors every player by class even when that option is off." },
	{ type = "range", key = "meter.background", label = "Background opacity", unit = "%", min = 0, max = 100, step = 5, hidden = NotSkin,
		desc = "Opacity of the box behind the meter windows, in percent." },
	{ type = "header", label = "Behavior", hidden = Off },
	{ type = "select", key = "meter.resetOnInstance", label = "Reset on new instance", hidden = Off,
		values = { blizzard = "Blizzard setting", on = "Yes", off = "No" },
		desc = "The game's own option to clear the meter when you enter a new instance." },
}

-- The shared visibility rows go before Behavior.
do
	local at = #F.options + 1
	for index, row in ipairs(F.options) do
		if row.type == "header" and row.label == "Behavior" then at = index break end
	end
	for _, row in ipairs(E:VisibilityOptions("meter.visibility", { db = function() return M.db end, hidden = Off })) do
		table.insert(F.options, at, row)
		at = at + 1
	end
end

M:AddFeature(F)

---------------------------------------------------------------------------
-- Combat timer. Fight length from Blizzard's meter session
-- (C_DamageMeter.GetSessionDurationSeconds, current session) while the
-- meter has one, otherwise from the player's own combat state
-- (PLAYER_REGEN_DISABLED / ENABLED). Neither is hidden combat data; a secret
-- duration is never used for math and falls back to the own timer.
---------------------------------------------------------------------------
local issecret = issecretvalue or function() return false end
local combat = { start = nil, last = 0 }

local function MeterSeconds()
	local api = C_DamageMeter and C_DamageMeter.GetSessionDurationSeconds
	local types = Enum and Enum.DamageMeterSessionType
	if not (api and types and types.Current) then return nil end
	local ok, seconds = pcall(api, types.Current)
	if not ok or issecret(seconds) or type(seconds) ~= "number" then return nil end
	return seconds
end

-- Seconds of the current fight (or the last one when out of combat), and
-- whether the player is in combat now.
function E:GetCombatTime()
	local inCombat = combat.start ~= nil
	local own = inCombat and (GetTime() - combat.start) or combat.last
	-- Blizzard's session covers the whole group fight; use it when it has one.
	local meter = MeterSeconds()
	if meter and meter > 0 then return meter, inCombat end
	return own, inCombat
end

-- "m:ss" (or "h:mm:ss") for the display and the datatext.
function E:FormatCombatTime(seconds)
	seconds = math.max(0, math.floor(seconds or 0))
	if seconds >= 3600 then
		return ("%d:%02d:%02d"):format(math.floor(seconds / 3600), math.floor(seconds % 3600 / 60), seconds % 60)
	end
	return ("%d:%02d"):format(math.floor(seconds / 60), seconds % 60)
end

local TIMER_MOVER = "EldoUI_CombatTimer"
local T = { key = "combattimer", title = "Combat timer" }
T.defaults = {
	enabled = false,
	attach = "meter",       -- meter (above Blizzard's meter when EldoUI places it) | mover
	outOfCombat = true,     -- keep the last fight's time on screen
	font = "THEME", fontSize = 14,
	colorCombat = true,     -- accent color while in combat
	background = true,
}

local timer

local function TimerDB() return M.db.combattimer end

local function UpdateTimer()
	if not timer then return end
	-- The fight-end event fires for everyone; a timer that is turned off
	-- (or a Combat HUD that is off) stays hidden.
	local db = M.db and TimerDB()
	if not (M.active and db and db.enabled) then
		timer:Hide()
		return
	end
	local seconds, inCombat = E:GetCombatTime()
	timer.text:SetText(E:FormatCombatTime(seconds))
	if inCombat and db.colorCombat then
		local r, g, b = unpack(E.media.accentColor)
		timer.text:SetTextColor(r, g, b)
	else
		timer.text:SetTextColor(unpack(E.media.text.body))
	end
	timer:SetShown(inCombat or (db.outOfCombat and seconds > 0))
end

local elapsedSince = 0
local ticker = CreateFrame("Frame")
ticker:Hide()
ticker:SetScript("OnUpdate", function(_, elapsed)
	elapsedSince = elapsedSince + elapsed
	if elapsedSince < 0.25 then return end
	elapsedSince = 0
	UpdateTimer()
end)

-- Right after a fight the meter's session length is often still secret
-- (the group fights on, or the restriction has not lifted yet), so the
-- kept time would freeze on the player's own timer. Twice a second it
-- looks again, until the game hands out a plain length or 15 seconds pass.
local SETTLE_TICK, SETTLE_LIMIT = "EldoUI.CombatTimer.settle", 15
local settleUntil = 0
local function Settle()
	if combat.start or MeterSeconds() or GetTime() >= settleUntil then
		E.Ticker:Unsubscribe(SETTLE_TICK)
	end
	if not combat.start then UpdateTimer() end
end

E:RegisterEvent("PLAYER_REGEN_DISABLED", function()
	combat.start = GetTime()
	E.Ticker:Unsubscribe(SETTLE_TICK)
	if timer and M.active and TimerDB().enabled then ticker:Show() UpdateTimer() end
end, combat)
E:RegisterEvent("PLAYER_REGEN_ENABLED", function()
	if combat.start then combat.last = GetTime() - combat.start end
	combat.start = nil
	ticker:Hide()
	UpdateTimer()
	if not MeterSeconds() and C_DamageMeter and C_DamageMeter.GetSessionDurationSeconds then
		settleUntil = GetTime() + SETTLE_LIMIT
		E.Ticker:Unsubscribe(SETTLE_TICK)
		E.Ticker:Subscribe(SETTLE_TICK, 0.5, Settle, combat)
	end
end, combat)

local function PlaceTimer(db)
	local holder = timer.holder
	local meterHolder = K.GetHolder(MOVER)
	timer:ClearAllPoints()
	if db.attach == "meter" and meterHolder and Allowed("move") then
		timer:SetPoint("BOTTOMRIGHT", meterHolder, "TOPRIGHT", 0, 4)
		holder:Hide() -- its own mover is not used
	else
		timer:SetPoint("CENTER", holder, "CENTER")
		holder:Show()
	end
end

function T:Setup()
	local holder = K.Holder(M, TIMER_MOVER, L["Combat Timer"], { "BOTTOMRIGHT", "UIParent", "BOTTOMRIGHT", -474, 140 }, 70, 22)
	holder:Hide()
	timer = CreateFrame("Frame", nil, UIParent)
	timer.holder = holder
	T.frame = timer -- exposed for inspection
	timer:SetSize(70, 22)
	timer:SetFrameStrata("MEDIUM")
	timer.text = E:CreateText(timer, E.tokens.size.cardTitle)
	timer.text:SetPoint("CENTER")
	timer:EnableMouse(true)
	timer:SetScript("OnEnter", function(frame)
		GameTooltip:SetOwner(frame, "ANCHOR_TOP")
		GameTooltip:SetText(L["Combat timer"])
		E.UIKit.TipTitle(GameTooltip, L["Length of your current or last fight."], true)
		GameTooltip:Show()
	end)
	timer:SetScript("OnLeave", GameTooltip_Hide)
	E:BindOptionsLink(timer, { page = "module:CombatHUD", key = "combattimer.enabled" })
end

function T:Apply(db)
	-- A strip, not a panel: the art style's edge (the WoW Forever line)
	-- comes and goes with the background (DESIGN.md §1).
	E:SetTemplate(timer, true)
	E:SetStyleEdge(timer, db.background and true or false)
	if not db.background then
		timer:SetBackdropColor(0, 0, 0, 0)
		timer:SetBackdropBorderColor(0, 0, 0, 0)
	end
	E:SetFont(timer.text, db.fontSize, nil, FontFile)
	timer:SetSize(math.max(50, db.fontSize * 4.5), db.fontSize + 8)
	timer.holder:SetSize(timer:GetSize())
	PlaceTimer(db)
	ticker:SetShown(combat.start ~= nil)
	UpdateTimer()
end

function T:Restore()
	ticker:Hide()
	if timer then
		timer:Hide()
		timer.holder:Hide()
	end
end

local function TimerOff() return not (M.db and M.db.combattimer and M.db.combattimer.enabled) end

T.note = L["How long the current fight has lasted, from Blizzard's damage meter session when it has one. The InfoBar's Combat time reads the same timer."]
T.options = {
	{ type = "toggle", key = "combattimer.enabled", label = "Combat timer", desc = "A small timer with the length of your current fight." },
	{ type = "select", key = "combattimer.attach", label = "Position", hidden = TimerOff,
		values = { meter = "Above the damage meter", mover = "Own mover" },
		desc = "Above the damage meter needs the damage meter's Move switch; otherwise the timer uses its own mover (EldoUI_CombatTimer)." },
	{ type = "toggle", key = "combattimer.outOfCombat", label = "Keep after combat", hidden = TimerOff,
		desc = "Show the last fight's time until the next fight starts." },
	{ less = true, type = "toggle", key = "combattimer.colorCombat", label = "Accent color in combat", hidden = TimerOff,
		desc = "The time is in the accent color while the fight runs." },
	{ type = "toggle", key = "combattimer.background", label = "Background", hidden = TimerOff, desc = "A small box behind the time." },
	{ type = "media", mediaKind = "font", default = "THEME", defaultLabel = "Theme font", key = "combattimer.font", label = "Font", hidden = TimerOff, desc = "Font of the time." },
	{ type = "range", key = "combattimer.fontSize", label = "Text size", min = 10, max = 32, step = 1, hidden = TimerOff, desc = "Size of the time." },
}

M:AddFeature(T)

---------------------------------------------------------------------------
-- Commands: bind a macro with "/eui meter toggle" or "/eui meter reset".
---------------------------------------------------------------------------
E:AddCommand("meter", "[toggle | reset]  Blizzard's damage meter: show/hide it, or clear its fights", function(arg)
	arg = (arg or ""):lower()
	if arg == "reset" then
		if C_DamageMeter and C_DamageMeter.ResetAllCombatSessions then
			C_DamageMeter.ResetAllCombatSessions()
			-- Details! takes over this reset and erases every fight it has
			-- stored as well, so the line says so.
			if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Details") then
				E:Print(L["Damage meter cleared. Details! cleared the fights it stored too."])
			else
				E:Print(L["Damage meter cleared."])
			end
		else
			E:Print(L["Blizzard's damage meter isn't available on this character."])
		end
	elseif arg == "toggle" or arg == "show" or arg == "hide" then
		if not Allowed() then
			E:Print(L["Turn on \"Let EldoUI change this\" for the damage meter first (Combat HUD > Damage meter)."])
			return
		end
		if arg == "toggle" then
			M.meterHiddenByCommand = not M.meterHiddenByCommand
		else
			M.meterHiddenByCommand = arg == "hide"
		end
		M:ApplyFeature(F)
		E:Print(M.meterHiddenByCommand and L["Damage meter hidden."] or L["Damage meter shown."])
	else
		E:ToggleConfig("module:CombatHUD")
	end
end, "Tools")
