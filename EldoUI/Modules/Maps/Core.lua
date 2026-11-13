-- EldoUI Maps: Blizzard's map windows and widgets in the EldoUI look.
--   * World map and quest log: skin, player and cursor
--     coordinates, fade while moving. Moving and scaling the windowed map
--     is the window mover's (Core/WindowMover.lua).
--   * Flight map and taxi window (G-36d): skin, learned flight time on
--     each destination's tooltip (times from the QoL flight timer); moved
--     and scaled by the window mover.
--   * Battlefield (zone) map, Shift+M: skin, mover, size, opacity, hide.
--   * Unexplored areas dimmed instead of dark: Modules/Maps/Reveal.lua.
--   * UI widgets: top-center widgets on a mover, below-minimap
--     widgets follow the minimap, encounter/alt power bar on a mover; light
--     font skin; hide.
--
-- Each part follows its Blizzard element switch (Core/Blizzard.lua). With a
-- switch off EldoUI leaves that part as Blizzard made it: the hooks below
-- stay installed but check the switch every time they run.
--
-- Taint notes: Blizzard frames only get alpha, textures, fonts, scale and
-- anchors set, and child frames/regions added. Hooks are hooksecurefunc and
-- HookScript only; no Blizzard function is replaced and EldoUI keeps its own
-- state in local tables, never in Blizzard frames. The one state call is
-- BattlefieldMapFrame:Hide() for the battlefield map's Hide switch (the same
-- thing Shift+M does; the frame is not protected). Anything that turns out
-- protected waits for the end of combat.
local _, E = ...
local L = E.L

local Key = E.Key
local WORLD = "world-map-quest-log"
local FLIGHT = "flight-map"
local BATTLEFIELD = "battlefield-map"
local WIDGETS = "ui-widgets"

local M = E:NewModule("Maps", {
	title = "Maps",
	desc = "World map, quest log, flight map, battlefield map and UI widgets: skin, position, scale, coordinates and fading.",
	category = "Interface",
	frames = { "EldoUI_BattlefieldMap", "EldoUI_TopWidgets", "EldoUI_EncounterBar" },
	movers = { "EldoUI_BattlefieldMap", "EldoUI_TopWidgets", "EldoUI_EncounterBar" },
	blizzard = { "world-map-quest-log", "flight-map", "battlefield-map", "ui-widgets" },
	savedKeys = { "profile.modules.Maps", "global.MapReveal" },
	optionsPage = "module:Maps",
	presets = { "Battleground", "Compact", "Glance", "Large", "Navigator", "Plain" },
	defaults = {
		worldMap = {
			skinQuestLog = true,
			coords = true,
			coordsPlayer = true,
			coordsCursor = true,
			coordDecimals = 1,
			coordsSize = 13,
			zoneLevels = true,
			fade = "blizzard",      -- off | blizzard | custom
			-- "custom": the shared visibility rules (Core/Visibility.lua);
			-- by default half see-through while you move.
			visibility = E:VisibilityDefaults({ preset = "custom", fadeMoving = true, fadedAlpha = 0.5 }),
		},
		flight = {
			flightTimes = true,
		},
		battlefield = {
			scale = 1,
			alpha = 1,
			skinTab = true,
		},
		widgets = {
			topScale = 1,
			belowFollow = true,
			belowGap = 4,
			belowScale = 1,
			powerScale = 1,
			fonts = true,
			topBackdrop = false,
			hideTop = true,
			hideBelow = true,
			hidePower = false,
		},
	},
})

local function Allowed(id, action) return E:BlizzardAllowed(id, action) end
local function Can(id, action) return M.active and E:BlizzardAllowed(id, action) end

-- Look up a nested key ("QuestsFrame.ScrollFrame.ScrollBar") without errors
-- on a client where a part is missing.
local function Field(root, path)
	local value = root
	for key in path:gmatch("[^%.]+") do
		if type(value) ~= "table" then return nil end
		value = value[key]
	end
	return value
end

---------------------------------------------------------------------------
-- Pins: keep a Blizzard frame on EldoUI's anchor. The panel manager, Edit
-- Mode or the managed-frame container re-anchor these frames; a post-hook
-- on SetPoint puts them back. `wants(frame)` decides each time whether
-- EldoUI anchors the frame at all (false leaves Blizzard's point).
---------------------------------------------------------------------------
local pinned = {} -- frame -> this module's exclusive pin spec
local Secret = E.Secret
local PinOwner, UnpinOwner = E.PinBlizzardFrame, E.UnpinBlizzardFrame
local PinOriginal, IsPinned = E.BlizzardPinOriginal, E.IsBlizzardFramePinned
local SkinUsable = E.SkinUsable
local CurrentProfile, ApplyGeneration = E.IsCurrentProfile, E.GetApplyGeneration
local EnabledValue = E.ModuleEnabledValue
local nativeGetScale, nativeGetParent = UIParent.GetScale, UIParent.GetParent

local function Same(a, b)
	return not Secret(a) and not Secret(b) and rawequal(a, b)
end

local function Number(value)
	return not Secret(value) and type(value) == "number" and value == value and value > 0 and value < math.huge
end

local function SourcesCurrent()
	return not Secret(SkinUsable) and type(SkinUsable) == "function" and Same(E.SkinUsable, SkinUsable)
		and Same(E.PinBlizzardFrame, PinOwner) and Same(E.UnpinBlizzardFrame, UnpinOwner)
		and Same(E.BlizzardPinOriginal, PinOriginal) and Same(E.IsBlizzardFramePinned, IsPinned)
		and not Secret(CurrentProfile) and type(CurrentProfile) == "function"
		and not Secret(ApplyGeneration) and type(ApplyGeneration) == "function"
		and Same(E.IsCurrentProfile, CurrentProfile) and Same(E.GetApplyGeneration, ApplyGeneration)
		and not Secret(EnabledValue) and type(EnabledValue) == "function" and Same(E.ModuleEnabledValue, EnabledValue)
end

local function ProfileCurrent(db, profile, name)
	if not SourcesCurrent() or Secret(db) or Secret(profile) or Secret(name)
		or type(db) ~= "table" or type(profile) ~= "table" or type(name) ~= "string"
		or getmetatable(profile) ~= nil then return false end
	local modules = rawget(profile, "modules")
	if Secret(modules) or type(modules) ~= "table" or getmetatable(modules) ~= nil
		or not Same(rawget(modules, "Maps"), db) then return false end
	local current = CurrentProfile(E, profile, name)
	return not Secret(current) and current == true and SourcesCurrent()
end

local function ModuleEnabled()
	if not SourcesCurrent() then return false end
	local value = EnabledValue(E, M)
	return not Secret(value) and value == true and SourcesCurrent()
end

local function Unpin(frame)
	if Secret(frame) or not frame then return end
	local spec = pinned[frame]
	if not spec or not SourcesCurrent() then return end
	-- Withdraw this exact owner immediately, including inside a scale hook.
	UnpinOwner(E, frame, nil, spec)
	if pinned[frame] == spec then pinned[frame] = nil end
end

local function Pin(frame, anchor, wants, group, scaleKey)
	if Secret(frame) or not SourcesCurrent() or not SkinUsable(E, frame) or not SourcesCurrent() then return end
	local scaled = group ~= nil and scaleKey ~= nil
	local spec = pinned[frame]
	if spec and not PinOriginal(E, frame, spec, "scale") then
		if IsPinned(E, frame) then return end
		spec = nil
	end
	if spec and (spec.anchor ~= anchor or spec.mapsScaled ~= scaled) then
		Unpin(frame)
		if IsPinned(E, frame) then return end
		spec = nil
	end
	if not spec then
		if IsPinned(E, frame) then return end
		local getScale, getParent = frame.GetScale, frame.GetParent
		if Secret(getScale) or Secret(getParent) or type(getScale) ~= "function" or type(getParent) ~= "function"
			or not Same(getScale, nativeGetScale) or not Same(getParent, nativeGetParent) then return end
		spec = {}
		local function Current()
			return not spec.mapsBlocked and SourcesCurrent() and pinned[frame] == spec
				and Same(frame.GetScale, getScale) and Same(frame.GetParent, getParent)
		end
		spec.wants = function()
			return Current() and ProfileCurrent(M.db, E.db, E.profileName) and not Secret(M.active) and M.active == true
				and not Secret(M.db) and type(M.db) == "table"
				and ModuleEnabled()
				and (not spec.mapsWants or spec.mapsWants(frame) == true)
		end
		spec.admit = function()
			spec.mapsBlocked = nil
			if not Current() then return end
			local db, profile, name = M.db, E.db, E.profileName
			if not ProfileCurrent(db, profile, name) then return end
			local generation, profileGeneration = ApplyGeneration(E), ApplyGeneration(E, "profile")
			if Secret(generation) or Secret(profileGeneration) then return end
			return function()
				return Current() and Same(M.db, db) and Same(E.db, profile) and Same(E.profileName, name)
					and Same(ApplyGeneration(E), generation) and Same(ApplyGeneration(E, "profile"), profileGeneration)
					and ProfileCurrent(db, profile, name) and spec.wants()
			end
		end
		spec.parent = function()
			if not Current() then return end
			local parent = getParent(frame)
			if Secret(parent) or parent == nil or not SkinUsable(E, parent) or not Current() then
				spec.mapsBlocked = true
				return
			end
			return parent
		end
		if scaled then
			spec.scale = function()
				if not Current() then return end
				local settings = spec.mapsGroup and M.db[spec.mapsGroup]
				if Secret(settings) or (settings ~= nil and type(settings) ~= "table") then return end
				local desired = settings and spec.mapsScaleKey and settings[spec.mapsScaleKey]
				if Secret(desired) or (desired ~= nil and not Number(desired)) then return end
				if desired ~= nil and desired ~= 1 then return desired end
				local original = PinOriginal(E, frame, spec, "scale")
				if original and Number(original.scale) and Current() then return original.scale end
			end
		end
		spec.mapsScaled = scaled
		spec.releaseChannels = function()
			-- The live pin owns this channel; Core keeps its original value.
			return { scale = scaled, points = spec.anchor ~= nil, parent = false }
		end
	end
	spec.anchor, spec.mapsWants = anchor, wants
	spec.mapsGroup, spec.mapsScaleKey = group, scaleKey
	pinned[frame] = spec
	-- Core remembers the native scale before it resolves spec.scale.
	PinOwner(E, frame, spec)
end

local function ReleaseMissing()
	local names = { BattlefieldMapFrame, UIWidgetTopCenterContainerFrame,
		UIWidgetBelowMinimapContainerFrame, EncounterBar, BattlefieldMapTab }
	for frame in pairs(pinned) do
		local found
		for _, current in pairs(names) do if Same(frame, current) then found = true; break end end
		if not found then Unpin(frame) end
	end
end

-- Alpha EldoUI set (nil = give it back to Blizzard at 1).
local faded = {}

local function SetAlpha(frame, alpha)
	if not E:SkinUsable(frame) then return end
	if alpha then
		frame:SetAlpha(alpha)
		faded[frame] = true
	elseif faded[frame] then
		frame:SetAlpha(1)
		faded[frame] = nil
	end
end

-- A holder frame on a mover, created the first time it is needed.
function M:Holder(key, name, title, width, height, point, opts)
	self.holders = self.holders or {}
	local holder = self.holders[key]
	if not holder then
		holder = CreateFrame("Frame", name, UIParent)
		holder:SetSize(width, height)
		local previous = E.currentModule
		E.currentModule = self -- tag the mover with this module for exports
		holder.mover = E:CreateMover(holder, name, title, point, opts)
		E.currentModule = previous
		self.holders[key] = holder
	end
	holder:Show()
	holder.mover:Show()
	return holder
end

function M:HideHolder(key)
	local holder = self.holders and self.holders[key]
	if holder then
		holder:Hide()
		holder.mover:Hide()
	end
end

-- Make a map window's own art invisible (Blizzard's border frame is in a
-- higher strata than the map, so EldoUI's panel goes under the window
-- instead of on the border frame).
local function SkinMapWindow(window, border)
	if not E:SkinUsable(window) then return end
	local parts = E:GetSkin(window, "eldoMap")
	if parts then return parts end
	parts = {}
	parts.bd = CreateFrame("Frame", nil, window)
	parts.bd:SetAllPoints()
	parts.bd:SetFrameLevel(window:GetFrameLevel())
	E:SetPanelTemplate(parts.bd)
	parts.line = parts.bd:CreateTexture(nil, "ARTWORK")
	parts.line:SetPoint("TOPLEFT", E.pixel, -24)
	parts.line:SetPoint("TOPRIGHT", -E.pixel, -24)
	parts.line:SetHeight(E.pixel * 2)
	E:AccentTexture(parts.line, 1)
	if E:SkinUsable(border) then
		parts.art = { border.NineSlice, border.Bg, border.TopTileStreaks, border.PortraitContainer, border.InsetBorderTop,
			border.TopBorder, border.Underlay }
		E:SkinCloseButton(border.CloseButton)
		local title = (border.TitleContainer and border.TitleContainer.TitleText) or border.TitleText
		if title and title.SetFont then
			E:SetFont(title, E.tokens.size.dialogTitle)
			title:SetTextColor(1, 1, 1)
		end
	end
	return parts
end

-- Skin parts can't be removed again without a reload; turning the skin off
-- hides EldoUI's additions and shows Blizzard's art again.
local mapSkins = {}

local function ShowMapSkin(window, border, on)
	local parts = mapSkins[window]
	if not parts then
		if not on then return end
		parts = SkinMapWindow(window, border)
		if not parts then return end
		mapSkins[window] = parts
	end
	parts.bd:SetShown(on)
	for _, region in pairs(parts.art or {}) do
		if type(region) == "table" and region.SetAlpha then region:SetAlpha(on and 0 or 1) end
	end
end

---------------------------------------------------------------------------
-- World map and quest log
---------------------------------------------------------------------------
local function WorldMap()
	local map = _G.WorldMapFrame
	return E:SkinUsable(map) and map or nil
end

-- Quest log side panel: flat scroll area, search box, buttons.
function M:SkinQuestLog(on)
	local log = _G.QuestMapFrame
	if not E:SkinUsable(log) then return end
	local regions = {
		log.VerticalSeparator,
		Field(log, "QuestsFrame.ScrollFrame.Background"),
		Field(log, "QuestsFrame.ScrollFrame.Edge"),
		Field(log, "QuestsFrame.BorderFrame"),
		Field(log, "QuestsFrame.DetailsFrame.Bg"),
		Field(log, "QuestsFrame.DetailsFrame.BorderFrame"),
		Field(log, "QuestsFrame.DetailsFrame.SealMaterialBG"),
		Field(log, "DetailsFrame.Bg"),
		Field(log, "DetailsFrame.BorderFrame"),
	}
	for _, region in pairs(regions) do
		if type(region) == "table" and region.SetAlpha then region:SetAlpha(on and 0 or 1) end
	end
	if not on or self.questLogSkinned then return end
	self.questLogSkinned = true
	E:SkinScrollBar(Field(log, "QuestsFrame.ScrollFrame.ScrollBar") or Field(_G.QuestScrollFrame, "ScrollBar"))
	E:SkinEditBox(Field(log, "QuestsFrame.ScrollFrame.SearchBox") or Field(_G.QuestScrollFrame, "SearchBox"))
	for _, path in ipairs({ "QuestsFrame.DetailsFrame", "DetailsFrame" }) do
		local details = Field(log, path)
		if E:SkinUsable(details) then
			E:SkinButton(Field(details, "BackFrame.BackButton"))
			E:SkinButton(details.AbandonButton)
			E:SkinButton(details.ShareButton)
			E:SkinButton(details.TrackButton)
			E:SkinScrollBar(Field(details, "ScrollFrame.ScrollBar"))
		end
	end
end

function M:ApplyWorldMapSkin()
	local map = WorldMap()
	local on = Can(WORLD, "skin")
	ShowMapSkin(map, map.BorderFrame, on)
	self:SkinQuestLog(on and self.db.worldMap.skinQuestLog)
end

-- Coordinates: player and cursor, in the map's bottom-left corner. Empty
-- ("--") where the game gives no position (instances).
local function FormatCoord(x, y, decimals)
	if (issecretvalue and (issecretvalue(x) or issecretvalue(y))) or not x or not y then return "--" end
	if x <= 0 and y <= 0 then return "--" end
	local format = decimals == 2 and "%.2f, %.2f" or decimals == 0 and "%.0f, %.0f" or "%.1f, %.1f"
	return format:format(x * 100, y * 100)
end

local COORDS_TICK = "EldoUI.Maps.coords" -- the shared ticker key of the coordinates

function M:CreateCoords(map)
	local frame = CreateFrame("Frame", nil, map.ScrollContainer or map)
	frame:SetPoint("BOTTOMLEFT", map.ScrollContainer or map, "BOTTOMLEFT", 6, 6)
	frame:SetSize(320, 22)
	frame:SetFrameLevel((map.ScrollContainer or map):GetFrameLevel() + 20)
	E:SetTemplate(frame, true) -- the theme's see-through panel
	frame.text = E:CreateText(frame, E.tokens.size.body, "LEFT")
	frame.text:SetPoint("LEFT", 6, 0)
	local lastMap
	local function Tick()
		local db = M.db.worldMap
		-- Only zone levels: nothing moves unless the map or the hovered zone changes.
		if not db.coordsPlayer and not db.coordsCursor then
			local mapID = map.GetMapID and map:GetMapID()
			local container = map.ScrollContainer
			if mapID == lastMap and not (container and container:IsMouseOver()) then return end
			lastMap = mapID
		end
		M:UpdateCoords()
	end
	frame.tick = Tick
	frame:SetScript("OnShow", function() M:WatchCoords() end)
	frame:SetScript("OnHide", function() M:WatchCoords() end)
	self.coords = frame
	self:WatchCoords()
end

-- Ten times a second on the shared ticker, only while the map shows them.
function M:WatchCoords()
	local frame = self.coords
	if self.active and frame and frame:IsVisible() then
		if not E.Ticker:IsSubscribed(COORDS_TICK) then E.Ticker:Subscribe(COORDS_TICK, 0.1, frame.tick, self) end
	else
		E.Ticker:Unsubscribe(COORDS_TICK)
	end
end

-- The readout reuses one list and touches its text and width only when
-- the text changed.
local coordParts = {}
function M:UpdateCoords()
	local map, frame, db = WorldMap(), self.coords, self.db.worldMap
	if not map or not frame then return end
	local parts = coordParts
	wipe(parts)
	local mapID = map.GetMapID and map:GetMapID()
	if db.coordsPlayer then
		local position = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
		local x, y
		if position then x, y = position:GetXY() end
		parts[#parts + 1] = E:TextHex("secondary") .. L["Player"] .. "|r " .. FormatCoord(x, y, db.coordDecimals)
	end
	if db.coordsCursor then
		local container = map.ScrollContainer
		local x, y
		if container and container:IsMouseOver() and map.GetNormalizedCursorPosition then
			x, y = map:GetNormalizedCursorPosition()
			if x and (x < 0 or x > 1 or y < 0 or y > 1) then x, y = nil, nil end
		end
		parts[#parts + 1] = E:TextHex("secondary") .. L["Cursor"] .. "|r " .. FormatCoord(x, y, db.coordDecimals)
	end
	if db.zoneLevels then
		local levels = self:ZoneLevels(map, mapID)
		if levels then parts[#parts + 1] = levels end
	end
	local text = table.concat(parts, "    ")
	if frame.shownText == text then return end
	frame.shownText = text
	frame.text:SetText(text)
	frame:SetWidth(math.max(60, frame.text:GetStringWidth() + 12))
end

-- Level range of the zone under the cursor (on a continent map) or of the
-- map shown: the game's map data, else EldoUI's zone table.
function M:ZoneLevels(map, mapID)
	if not mapID then return nil end
	local target, name = mapID, nil
	local container = map.ScrollContainer
	if C_Map.GetMapInfoAtPosition and container and container:IsMouseOver() and map.GetNormalizedCursorPosition then
		local x, y = map:GetNormalizedCursorPosition()
		if x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
			local info = C_Map.GetMapInfoAtPosition(mapID, x, y)
			if info and info.mapID and info.mapID ~= mapID then target, name = info.mapID, info.name end
		end
	end
	-- A map's level range never changes: read it once per map, and keep
	-- only answers that came back.
	self.levelCache = self.levelCache or {}
	local range = self.levelCache[target]
	if range == nil then
		local low, high = E:ZoneLevelRange(target)
		if low then
			range = low == high and tostring(low) or ("%d-%d"):format(low, high)
			self.levelCache[target] = range
		end
	end
	if not range then return nil end
	return (E:TextHex("secondary") .. "%s|r %s"):format(name or L["Levels"], range)
end

-- Fading: "blizzard" uses the game's own setting (mapFade); "custom" puts
-- the map on the shared visibility rules, alpha only.
-- v0.6 kept its own "opacity while moving" and "solid under the mouse";
-- they become the shared block once (the mouse always shows it now).
function M:MigrateVisibility()
	local db = self.db and self.db.worldMap
	if type(db) ~= "table" or (db.fadeAlpha == nil and db.fadeHover == nil) then return end
	if type(db.visibility) ~= "table" then db.visibility = E:VisibilityDefaults({ preset = "custom", fadeMoving = true, fadedAlpha = 0.5 }) end
	local alpha = tonumber(db.fadeAlpha)
	if alpha then
		db.visibility.preset = "custom"
		db.visibility.fadeMoving = true
		db.visibility.fadedAlpha = math.max(0, math.min(1, alpha))
	end
	db.fadeAlpha, db.fadeHover = nil, nil
end

function M:ApplyWorldMapFade(map, custom)
	if custom then
		-- A window, not HUD: the idle rule and the Show HUD key leave it alone.
		E:AttachVisibility(map, self.db.worldMap.visibility, { exempt = true })
	elseif E:IsVisibilityAttached(map) then
		E:DetachVisibility(map)
	end
end

-- The game draws its own world map coordinates (its "show player" and "show
-- cursor coordinates" settings) on a panel among the map's overlay frames.
-- Next to EldoUI's they would show twice, so each reading EldoUI shows
-- hides the game's matching one. The gamepad crosshair reading stays:
-- EldoUI has none. Turned off, the game's readings come back as they were.
local gameCoords = {}
local function GameCoordsPanel(map)
	local frames = map and rawget(map, "overlayFrames")
	if type(frames) ~= "table" then return nil end
	for _, frame in ipairs(frames) do
		if type(frame) == "table" and frame.PlayerCoords and frame.CursorCoords then return frame end
	end
end

function M:HideGameCoords(map, player, cursor)
	local panel = GameCoordsPanel(map)
	if not panel then return end
	for part, hide in pairs({ PlayerCoords = player, CursorCoords = cursor }) do
		local frame = panel[part]
		if type(frame) == "table" and frame.GetParent then
			if hide and not gameCoords[frame] then
				gameCoords[frame] = true
				E:HideBlizzardFrame(frame, { check = function() return gameCoords[frame] ~= nil end })
			elseif not hide and gameCoords[frame] then
				gameCoords[frame] = nil
				E:UnhideBlizzardFrame(frame)
			end
		end
	end
end

function M:ApplyWorldMapImprove()
	local map = WorldMap()
	local db = self.db.worldMap
	local on = Can(WORLD, "improve")
	if on and db.coords and not self.coords then self:CreateCoords(map) end
	if self.coords then
		self.coords:SetShown(on and db.coords and (db.coordsPlayer or db.coordsCursor or db.zoneLevels) and true or false)
		E:SetFont(self.coords.text, db.coordsSize)
		self.coords.shownText = nil
		E:SetTemplate(self.coords, true) -- theme colors may have changed
		if self.coords:IsShown() then self:UpdateCoords() end
		self:WatchCoords()
	end
	local shown = self.coords and self.coords:IsShown()
	self:HideGameCoords(map, shown and db.coordsPlayer, shown and db.coordsCursor)
	if on then
		if db.fade == "blizzard" then
			E:SetCVar("mapFade", "1", WORLD)
		else
			E:SetCVar("mapFade", "0", WORLD)
		end
	elseif self.mapFadeSet then
		E:RestoreCVars(WORLD)
	end
	self.mapFadeSet = on
	self:MigrateVisibility()
	self:ApplyWorldMapFade(map, on and db.fade == "custom")
end

-- Native map and quest-log work finishes before the owned view is measured.
-- A cold or disabled view never installs these observations.
local canvasObservation
function M:ObserveWorldCanvasHost(host, admitOnly)
	local secret, call = E.Secret, E.PlainCallAll
	local function same(a, b) return not secret(a) and not secret(b) and a == b end
	local map = rawget(_G, "WorldMapFrame")
	local get, refresh = self.WorldCanvasPinView, self.RefreshWorldCanvasHost
	if self ~= M or secret(get) or type(get) ~= "function" or secret(refresh) or type(refresh) ~= "function" then return false end
	if not secret(map) and type(map) == "nil" then return end
	if secret(map) or type(map) ~= "table" or not same(rawget(map, "ScrollContainer"), host) then return false end
	if admitOnly then return true end
	local binding = call(get, self)
	if not binding or not same(binding.host, host) or not same(call(binding.current), true) then return false end
	if canvasObservation then
		if same(canvasObservation.map, map) and same(canvasObservation.host, host) and canvasObservation.current() then
			return true, canvasObservation.current
		end
		return false
	end
	local setMap, hookScript, hook = map.SetMapID, host.HookScript, hooksecurefunc
	if secret(setMap) or type(setMap) ~= "function" or secret(hookScript) or type(hookScript) ~= "function"
		or secret(hook) or type(hook) ~= "function" then return false end
	local record = { map = map, host = host }
	canvasObservation = record
	local function owned()
		return canvasObservation == record and same(M.active, true) and same(rawget(_G, "WorldMapFrame"), map)
			and same(rawget(map, "ScrollContainer"), host) and same(M.WorldCanvasPinView, get)
			and same(M.RefreshWorldCanvasHost, refresh) and same(host.HookScript, hookScript)
			and same(map.SetMapID, record.setMap) and same(hooksecurefunc, hook)
	end
	record.current = owned
	local function changed()
		if not owned() then return end
		call(refresh, M)
	end
	local ok = pcall(hook, map, "SetMapID", changed)
	record.setMap = map.SetMapID
	for _, event in ipairs({ "OnShow", "OnHide", "OnSizeChanged" }) do
		if not ok or not same(rawget(_G, "WorldMapFrame"), map) or not same(rawget(map, "ScrollContainer"), host)
			or not same(host.HookScript, hookScript) then return false end
		ok = pcall(hookScript, host, event, changed)
	end
	return ok and same(call(binding.current), true) and owned(), owned
end

function M:RefreshWorldMap()
	if not WorldMap() then
		if self.active then E:OnBlizzardAddOn("Blizzard_WorldMap", function() if WorldMap() then M:RefreshWorldMap() end end) end
		return
	end
	self:ApplyWorldMapSkin()
	self:ApplyWorldMapImprove()
end

---------------------------------------------------------------------------
-- Flight map (Blizzard_FlightMap, load on demand) and taxi window
---------------------------------------------------------------------------
local function FormatTime(seconds) return E:FormatDuration(seconds, "minutes", "round") end

local function CurrentTaxiNode()
	for index = 1, NumTaxiNodes() do
		if TaxiNodeGetType(index) == "CURRENT" then return TaxiNodeName(index) end
	end
end

-- Flight times the QoL flight timer learned, keyed "From > To", kept at
-- normal flight speed and shown at this character's. Read only.
local function LearnedTime(destination)
	local store = EldoUIDB and EldoUIDB.qol and EldoUIDB.qol.flights
	local from = CurrentTaxiNode()
	if not store or not from or not destination or from == destination then return nil end
	local base = tonumber(store[from .. " > " .. destination])
	return base and math.floor(base * E:FlightTimeFactor() + 0.5) or nil
end

local function AddFlightTime(tooltip, destination)
	if not (Can(FLIGHT, "improve") and M.db.flight.flightTimes) then return end
	local seconds = LearnedTime(destination)
	if seconds then
		tooltip:AddLine(L["Flight time: %s"]:format(FormatTime(seconds)), E:TokenColor("secondary"))
	else
		E.UIKit.TipText(tooltip, L["Flight time: not learned yet"])
	end
	tooltip:Show()
end

function M:HookFlightTooltips()
	if not self.taxiTooltipHooked and type(_G.TaxiNodeOnButtonEnter) == "function" then
		self.taxiTooltipHooked = true
		hooksecurefunc("TaxiNodeOnButtonEnter", function(button)
			local index = button and button:GetID()
			if index and TaxiNodeGetType(index) == "REACHABLE" then
				AddFlightTime(GameTooltip, TaxiNodeName(index))
			end
		end)
	end
	local mixin = _G.FlightMap_FlightPointPinMixin
	if not self.flightPinHooked and mixin and type(mixin.OnMouseEnter) == "function" then
		self.flightPinHooked = true
		hooksecurefunc(mixin, "OnMouseEnter", function(pin)
			local data = pin.taxiNodeData
			local reachable = Enum.FlightPathState and Enum.FlightPathState.Reachable
			if data and data.name and (reachable == nil or data.state == reachable) then
				AddFlightTime(GameTooltip, data.name)
			end
		end)
	end
end

local flightMoves = {
	-- window global, border frame key (moving and scaling: Core/WindowMover.lua)
	{ name = "TaxiFrame" },
	{ name = "FlightMapFrame", border = "BorderFrame" },
}

function M:ApplyFlightWindows()
	local skin = Can(FLIGHT, "skin")
	for _, info in ipairs(flightMoves) do
		local window = _G[info.name]
		if E:SkinUsable(window) then
			-- Skin
			if info.border then
				ShowMapSkin(window, window[info.border], skin)
			elseif skin or E:GetSkin(window, "panel") then
				local inset = window.InsetBg
				if skin and not E:GetSkin(window, "panel") then
					E:SkinPanel(window, { keep = inset and { [inset] = true } or nil, insets = false })
				end
				local parts = E:GetSkin(window, "panel")
				if parts and parts.bd then parts.bd:SetShown(skin) end
			end
		end
	end
end

function M:RefreshFlight()
	if Can(FLIGHT) then
		self:HookFlightTooltips()
		if not self.flightMapWaiting and not _G.FlightMapFrame then
			self.flightMapWaiting = true
			E:OnBlizzardAddOn("Blizzard_FlightMap", function()
				M:HookFlightTooltips()
				M:ApplyFlightWindows()
			end)
		end
	end
	self:ApplyFlightWindows()
end

---------------------------------------------------------------------------
-- Battlefield map (Blizzard_BattlefieldMap, load on demand; Shift+M)
---------------------------------------------------------------------------
local function BattlefieldMap()
	local map = _G.BattlefieldMapFrame
	return E:SkinUsable(map) and map or nil
end

function M:SkinBattlefield(on)
	local map = BattlefieldMap()
	local border = map.BorderFrame
	if on and not self.battlefieldBorder and E:SkinUsable(border) then
		-- The border frame sits above the map, so the 1 px frame goes there
		-- with a clear background.
		local bd = CreateFrame("Frame", nil, border)
		bd:SetAllPoints(map)
		E:SetTemplate(bd)
		bd:SetBackdropColor(0, 0, 0, 0)
		self.battlefieldBorder = bd
		E:SkinCloseButton(border.CloseButton)
	end
	if E:SkinUsable(border) then
		for _, key in ipairs({ "TopLeft", "TopRight", "BottomLeft", "BottomRight", "Top", "Bottom", "Left", "Right" }) do
			local region = border[key]
			if region and region.SetAlpha then region:SetAlpha(on and 0 or 1) end
		end
	end
	if self.battlefieldBorder then self.battlefieldBorder:SetShown(on) end
	-- The tab above the map (right-click menu, drag).
	local tab = _G.BattlefieldMapTab
	local tabOn = on and self.db.battlefield.skinTab
	if E:SkinUsable(tab) then
		for _, key in ipairs({ "Left", "Middle", "Right" }) do
			local region = tab[key]
			if region and region.SetAlpha then region:SetAlpha(tabOn and 0 or 1) end
		end
		if tabOn and not self.battlefieldTab then
			local bd = CreateFrame("Frame", nil, tab)
			bd:SetPoint("TOPLEFT", 2, -4)
			bd:SetPoint("BOTTOMRIGHT", -2, 0)
			bd:SetFrameLevel(math.max(tab:GetFrameLevel() - 1, 0))
			E:SetTemplate(bd, true)
			self.battlefieldTab = bd
			local text = tab.Text or (tab.GetFontString and tab:GetFontString())
			if text and text.SetFont then E:SetFont(text, E.tokens.size.label) end
		end
		if self.battlefieldTab then self.battlefieldTab:SetShown(tabOn) end
	end
end

local function BattlefieldAnchor() return "TOPLEFT", M.holders.battlefield, "TOPLEFT", 0, 0 end
local function BattlefieldTabAnchor() return "BOTTOMLEFT", M.holders.battlefield, "TOPLEFT", 0, 4 end

function M:ApplyBattlefield()
	ReleaseMissing()
	local map = BattlefieldMap()
	if not map then self:HideHolder("battlefield"); return end
	local db = self.db.battlefield
	self:SkinBattlefield(Can(BATTLEFIELD, "skin"))
	local move = Can(BATTLEFIELD, "move")
	local hidden = Can(BATTLEFIELD, "hide")
	if move then
		local holder = self:Holder("battlefield", "EldoUI_BattlefieldMap", L["Battlefield Map"], 300, 200,
			{ "TOPLEFT", "UIParent", "TOPLEFT", 15, -60 })
		holder:SetSize(300 * db.scale, 200 * db.scale)
		Pin(map, BattlefieldAnchor, function() return Can(BATTLEFIELD, "move") end, "battlefield", "scale")
		local tab = _G.BattlefieldMapTab
		if E:SkinUsable(tab) then
			Pin(tab, BattlefieldTabAnchor, function() return Can(BATTLEFIELD, "move") end)
		end
	else
		self:HideHolder("battlefield")
		Unpin(map)
		Unpin(_G.BattlefieldMapTab)
	end
	SetAlpha(map, Can(BATTLEFIELD) and db.alpha < 1 and db.alpha or nil)
	-- Hide: closed again whenever it opens (Shift+M or entering a zone).
	if hidden and map:IsShown() then
		C_Timer.After(0, function() if Can(BATTLEFIELD, "hide") and BattlefieldMapFrame:IsShown() then BattlefieldMapFrame:Hide() end end)
	end
	if not self.battlefieldHooked then
		self.battlefieldHooked = true
		map:HookScript("OnShow", function(frame)
			if Can(BATTLEFIELD, "hide") then
				C_Timer.After(0, function() if Can(BATTLEFIELD, "hide") then frame:Hide() end end)
			end
		end)
	end
end

function M:RefreshBattlefield()
	ReleaseMissing()
	if BattlefieldMap() then
		self:ApplyBattlefield()
	elseif Can(BATTLEFIELD) and not self.battlefieldWaiting then
		self.battlefieldWaiting = true
		E:OnBlizzardAddOn("Blizzard_BattlefieldMap", function()
			if BattlefieldMap() and M.active then M:ApplyBattlefield() end
		end)
	end
end

---------------------------------------------------------------------------
-- UI widgets
---------------------------------------------------------------------------
local function TopWidgets() return E:SkinUsable(_G.UIWidgetTopCenterContainerFrame) and _G.UIWidgetTopCenterContainerFrame or nil end
local function BelowWidgets() return E:SkinUsable(_G.UIWidgetBelowMinimapContainerFrame) and _G.UIWidgetBelowMinimapContainerFrame or nil end
local function EncounterBar() return E:SkinUsable(_G.EncounterBar) and _G.EncounterBar or nil end

-- What the below-minimap widgets hang from: EldoUI's minimap when it is on
-- screen, else Blizzard's minimap cluster.
local function MinimapAnchor()
	local eldo = _G.EldoUI_Minimap
	if eldo and eldo:IsShown() then return eldo end
	return _G.MinimapCluster or _G.Minimap
end

-- Light font skin: EldoUI font face on every text of a widget (and one
-- level of child frames), Blizzard's size kept. Widgets rebuild their text
-- often, so this runs after each layout.
local fontSkinned = setmetatable({}, { __mode = "k" }) -- FontString -> Blizzard's font

local function SkinWidgetText(frame, on)
	if not E:SkinUsable(frame) then return end
	for _, region in ipairs({ frame:GetRegions() }) do
		if region:IsObjectType("FontString") then
			local font, size, flags = region:GetFont()
			if on and font and (font ~= E.media.font or not fontSkinned[region]) then
				-- Keep Blizzard's original from the first time only: after a
				-- theme font change the region holds EldoUI's old font, which
				-- must not become the "original".
				if not fontSkinned[region] then fontSkinned[region] = { font, size, flags } end
				-- A direct call on purpose: Blizzard's own size stays, and the
				-- original comes back when the skin is off (E:SetFont would scale it).
				region:SetFont(E.media.font, size, E.db.general.fontOutline)
			elseif not on and fontSkinned[region] then
				region:SetFont(unpack(fontSkinned[region]))
				fontSkinned[region] = nil
			end
		end
	end
end

local function SkinWidgetContainer(container)
	if not E:SkinUsable(container) or type(container.widgetFrames) ~= "table" then return end
	local on = Can(WIDGETS, "skin") and M.db.widgets.fonts
	if not on and not next(fontSkinned) then return end
	for _, widget in pairs(container.widgetFrames) do
		SkinWidgetText(widget, on)
		for _, child in ipairs({ widget:GetChildren() }) do SkinWidgetText(child, on) end
	end
	-- Backdrop behind the top-center widgets (only while some show).
	if container == TopWidgets() then M:UpdateTopBackdrop() end
end

function M:UpdateTopBackdrop()
	local top = TopWidgets()
	if not top then return end
	local on = Can(WIDGETS, "skin") and self.db.widgets.topBackdrop
		and not (Can(WIDGETS, "hide") and self.db.widgets.hideTop)
	if on and not self.topBackdrop then
		local bd = CreateFrame("Frame", nil, top)
		bd:SetPoint("TOPLEFT", top, "TOPLEFT", -8, 6)
		bd:SetPoint("BOTTOMRIGHT", top, "BOTTOMRIGHT", 8, -6)
		bd:SetFrameLevel(math.max(top:GetFrameLevel() - 1, 0))
		E:SetPanelTemplate(bd, true)
		self.topBackdrop = bd
	end
	if self.topBackdrop then
		local showing = top.HasAnyWidgetsShowing and top:HasAnyWidgetsShowing()
		self.topBackdrop:SetShown(on and showing and true or false)
	end
end

-- Hidden containers: invisible and parked off screen, so no Blizzard
-- OnHide code runs from EldoUI and the game info comes back with one click.
local function Offscreen()
	return "TOPRIGHT", UIParent, "TOPLEFT", -400, 0
end

local function TopAnchor() return "TOP", M.holders.topWidgets, "TOP", 0, 0 end
local function BelowAnchor() return "TOPRIGHT", MinimapAnchor(), "BOTTOMRIGHT", 0, -M.db.widgets.belowGap end
local function EncounterAnchor() return "CENTER", M.holders.encounterBar, "CENTER", 0, 0 end

function M:ApplyWidgets()
	ReleaseMissing()
	local db = self.db.widgets
	local move, hide = Can(WIDGETS, "move"), Can(WIDGETS, "hide")

	-- Top center: BG scores, capture bars, world PvP objectives.
	local top = TopWidgets()
	if top then
		local hideTop = hide and db.hideTop
		if move and not hideTop then
			local holder = self:Holder("topWidgets", "EldoUI_TopWidgets", L["Top-center Widgets"], 260, 40, { "TOP", "UIParent", "TOP", 0, -44 })
			Pin(top, TopAnchor, function() return Can(WIDGETS, "move") and not (Can(WIDGETS, "hide") and M.db.widgets.hideTop) end, "widgets", "topScale")
			holder:SetSize(260 * db.topScale, 40 * db.topScale)
		elseif hideTop then
			self:HideHolder("topWidgets")
			Pin(top, Offscreen, function() return Can(WIDGETS, "hide") and M.db.widgets.hideTop end)
		else
			self:HideHolder("topWidgets")
			Unpin(top)
		end
		SetAlpha(top, hideTop and 0 or nil)
	end

	-- Below the minimap: follows the minimap EldoUI or Blizzard shows.
	local below = BelowWidgets()
	if below then
		local hideBelow = hide and db.hideBelow
		if hideBelow then
			Pin(below, Offscreen, function() return Can(WIDGETS, "hide") and M.db.widgets.hideBelow end)
		elseif move and db.belowFollow then
			Pin(below, BelowAnchor, function() return Can(WIDGETS, "move") and M.db.widgets.belowFollow and not (Can(WIDGETS, "hide") and M.db.widgets.hideBelow) end, "widgets", "belowScale")
		elseif move then
			Pin(below, nil, function() return Can(WIDGETS, "move") and not M.db.widgets.belowFollow and not (Can(WIDGETS, "hide") and M.db.widgets.hideBelow) end, "widgets", "belowScale")
		else
			Unpin(below)
		end
		SetAlpha(below, hideBelow and 0 or nil)
	end

	-- Encounter bar: the alternate power bar and power-bar widgets.
	local bar = EncounterBar()
	if bar then
		local hidePower = hide and db.hidePower
		if move and not hidePower then
			local holder = self:Holder("encounterBar", "EldoUI_EncounterBar", L["Encounter Bar"], 250, 60, { "CENTER", "UIParent", "CENTER", 0, 300 },
				{ sample = { kind = "bar" } })
			holder:SetSize(250 * db.powerScale, 60 * db.powerScale)
			Pin(bar, EncounterAnchor, function() return Can(WIDGETS, "move") and not (Can(WIDGETS, "hide") and M.db.widgets.hidePower) end, "widgets", "powerScale")
		elseif hidePower then
			self:HideHolder("encounterBar")
			Pin(bar, Offscreen, function() return Can(WIDGETS, "hide") and M.db.widgets.hidePower end)
		else
			self:HideHolder("encounterBar")
			Unpin(bar)
		end
		SetAlpha(bar, hidePower and 0 or nil)
		-- Alternate power bar text in the EldoUI font.
		local text = Field(_G.PlayerPowerBarAlt, "statusFrame.text")
		if text and text.SetFont then
			local on = Can(WIDGETS, "skin") and db.fonts
			if on then
				-- Blizzard's font is saved once; the theme font is applied on
				-- every pass, so a font change shows here too.
				if not fontSkinned[text] then fontSkinned[text] = { text:GetFont() } end
				text:SetFont(E.media.font, fontSkinned[text][2] or 12, E.db.general.fontOutline)
			elseif not on and fontSkinned[text] then
				text:SetFont(unpack(fontSkinned[text]))
				fontSkinned[text] = nil
			end
		end
	end

	for _, container in ipairs({ top or false, below or false, _G.UIWidgetPowerBarContainerFrame or false }) do
		if container then SkinWidgetContainer(container) end
	end
	self:UpdateTopBackdrop()
end

function M:HookWidgets()
	if self.widgetsHooked then return end
	self.widgetsHooked = true
	for _, container in ipairs({ TopWidgets() or false, BelowWidgets() or false, _G.UIWidgetPowerBarContainerFrame or false }) do
		if container and E:SkinUsable(container) and type(container.UpdateWidgetLayout) == "function" then
			hooksecurefunc(container, "UpdateWidgetLayout", SkinWidgetContainer)
		end
	end
end

function M:RefreshWidgets()
	ReleaseMissing()
	if not TopWidgets() then self:HideHolder("topWidgets") end
	if not EncounterBar() then self:HideHolder("encounterBar") end
	if not TopWidgets() and not BelowWidgets() and not EncounterBar() then return end
	if Can(WIDGETS) then self:HookWidgets() end
	self:ApplyWidgets()
end

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------
function M:Refresh()
	self:RefreshWorldMap()
	self:RefreshFlight()
	self:RefreshBattlefield()
	self:RefreshWidgets()
end

local function Handler(owner, refresh, reload, install)
	return {
		owner = owner,
		apply = function() M[refresh](M) end,
		undo = function() M[refresh](M) end, -- each step puts back what it changed when its switch is off
		reload = reload,
		install = install,
	}
end

function M:OnInitialize()
	self:MigrateVisibility()
	if self.reveal then self.reveal:Initialize() end
	E:AddCommand("map", "reset  put the world map, flight map and taxi window back where Blizzard places them", function(arg)
		if (arg or ""):lower():match("reset") then
			M:ResetPositions()
		else
			E:ToggleConfig("module:Maps")
		end
	end, "Layout & frames")
end

function M.ResetPositions()
	for _, key in ipairs({ "worldMap", "taxi", "flightMap" }) do E:ResetWindow(key, "position") end
	E:Print(L["The world map, flight map and taxi window go back to Blizzard's place."])
end

-- The Blizzard element handlers join the first time the module turns on,
-- so a map module that stays off never claims the map elements. They act
-- only while the module is on; turned off, each Refresh step puts back
-- what it changed.
local handlersAdded = false

function M:OnEnable()
	if not handlersAdded then
		handlersAdded = true
		E:RegisterBlizzardHandler(WORLD, Handler("Maps", "RefreshWorldMap", { skin = true }, { skin = true, improve = true }))
		E:RegisterBlizzardHandler(FLIGHT, Handler("Maps", "RefreshFlight", { skin = true }, { skin = true, improve = true }))
		E:RegisterBlizzardHandler(BATTLEFIELD, Handler("Maps", "RefreshBattlefield", { skin = true, move = true }, { skin = true }))
		E:RegisterBlizzardHandler(WIDGETS, Handler("Maps", "RefreshWidgets", { move = true, hide = true }, { move = true }))
	end
	E:RunOutOfCombat(function() M:Refresh() end)
	-- The battlefield map comes and goes with zones; widgets follow the minimap.
	self:RegisterEvent("PLAYER_ENTERING_WORLD", function()
		E:RunOutOfCombat(function()
			M:RefreshBattlefield()
			M:RefreshWidgets()
		end)
	end)
	if self.reveal then self.reveal:Enable() end
end

function M:OnDisable()
	if self.ReleaseWorldCanvas then self:ReleaseWorldCanvas() end
	self:UnregisterEvent("PLAYER_ENTERING_WORLD")
	E.Ticker:UnsubscribeOwner(self)
	if self.reveal then self.reveal:Disable() end
	-- active is false now, so every Refresh step puts back what it changed.
	E:RunOutOfCombat(function()
		for frame in pairs(pinned) do Unpin(frame) end
		M:Refresh()
	end)
end

function M:OnProfileChanged()
	if self.ReleaseWorldCanvas then self:ReleaseWorldCanvas() end
	if self.active then E:RunOutOfCombat(function() M:Refresh() end) end
	if self.active and self.reveal then self.reveal:Refresh() end
end

---------------------------------------------------------------------------
-- Options
---------------------------------------------------------------------------
local function Off(id, action)
	return function() return not Allowed(id, action) end
end

local function Needs(id, action, text)
	return { type = "description", label = text, hidden = function() return Allowed(id, action) end }
end

M.options = {
	{ type = "tab", label = "World map" },
	{ type = "description", label = "These follow Blizzard UI > World map and quest log. Each group needs one of its switches." },
	{ type = "execute", label = "Open Blizzard UI switches", desc = "Open the Blizzard UI page to switch Skin, Move and Improve for each map.",
		func = function() E:ToggleConfig("blizzard") end },
	{ type = "header", label = "Look (Skin)" },
	Needs(WORLD, "skin", Key("Turn on Skin for the world map to use these.")),
	{ type = "toggle", key = "worldMap.skinQuestLog", label = "Skin the quest log", desc = "The quest list beside the map gets flat scroll bars, search box and buttons.", hidden = Off(WORLD, "skin") },
	{ type = "header", label = "Position and size (Move and scale)" },
	Needs(WORLD, "move", Key("Turn on Move and scale for the world map to drag it by its title bar and scale it.")),
	{ type = "execute", label = "Open Windows", desc = "Dragging, the mouse wheel scale and the reset of the windowed map are on the Move windows page (the full-screen map stays Blizzard's). /eui map reset puts the maps back.",
		func = function() E:ToggleConfig("windows") end, hidden = Off(WORLD, "move") },
	{ type = "header", label = "Coordinates (Improve)" },
	Needs(WORLD, "improve", Key("Turn on Improve for the world map to use these.")),
	{ type = "toggle", key = "worldMap.coords", label = "Show coordinates", desc = "Coordinates in the map's bottom-left corner. The game gives none inside instances; then they show --.", hidden = Off(WORLD, "improve") },
	{ type = "toggle", key = "worldMap.coordsPlayer", label = "Your position", desc = "Where you are on the map you are looking at.", dependsOn = "worldMap.coords", hidden = Off(WORLD, "improve") },
	{ type = "toggle", key = "worldMap.coordsCursor", label = "Cursor position", desc = "Where the mouse points on the map.", dependsOn = "worldMap.coords", hidden = Off(WORLD, "improve") },
	{ type = "select", key = "worldMap.coordDecimals", label = "Precision", desc = "Decimal places of the coordinates.",
		values = { [0] = "45, 62", [1] = "45.3, 62.1", [2] = "45.27, 62.08" }, dependsOn = "worldMap.coords", hidden = Off(WORLD, "improve") },
	{ type = "toggle", key = "worldMap.zoneLevels", label = "Zone level range", desc = "The level range of the zone under the cursor (or of the map shown), from the game's map data.", dependsOn = "worldMap.coords", hidden = Off(WORLD, "improve") },
	{ type = "range", key = "worldMap.coordsSize", label = "Text size", desc = "Font size of the coordinates.", min = 10, max = 18, step = 1, dependsOn = "worldMap.coords", hidden = Off(WORLD, "improve") },
	{ type = "header", label = "Fading (Improve)" },
	{ type = "select", key = "worldMap.fade", label = "Fading", desc = "Blizzard's: the game's own fade, half see-through while you move. EldoUI rules: the visibility settings below (by default see-through while you move, solid under the mouse). Off keeps the map solid.",
		values = { off = "Off", blizzard = "Blizzard's", custom = "EldoUI rules" }, hidden = Off(WORLD, "improve") },
}
local function NoCustomFade()
	return not Allowed(WORLD, "improve") or M.db.worldMap.fade ~= "custom"
end
for _, row in ipairs(E:VisibilityOptions("worldMap.visibility", { label = false, exempt = true, hidden = NoCustomFade,
	db = function() return M.db end })) do
	table.insert(M.options, row)
end
for _, row in ipairs({
	{ type = "description", label = "Party and raid members already show in class colors on Blizzard's map. The zone tick in the quest log is part of Quality of Life." },

	{ type = "tab", label = "Flight map" },
	{ type = "description", label = "These follow Blizzard UI > Flight map and taxi window." },
	Needs(FLIGHT, "move", Key("Turn on Move and scale for the flight map to drag it by its title bar and scale it.")),
	{ type = "execute", label = "Open Windows", desc = "Dragging, the mouse wheel scale and the reset of the flight map and taxi window are on the Move windows page.",
		func = function() E:ToggleConfig("windows") end, hidden = Off(FLIGHT, "move") },
	Needs(FLIGHT, "improve", Key("Turn on Improve for the flight map to see learned flight times.")),
	{ type = "toggle", key = "flight.flightTimes", label = "Learned flight time in tooltips", desc = "Each destination's tooltip shows how long the flight took last time (learned by the Quality of Life flight timer).", hidden = Off(FLIGHT, "improve") },
	{ type = "execute", label = "Flight timer bar settings", desc = "The flight timer bar is part of Quality of Life.", func = function() E:ToggleConfig("module:QoL") end },

	{ type = "tab", label = "Battlefield map" },
	{ type = "description", label = "The small zone map (Shift+M). These follow Blizzard UI > Battlefield (zone) map." },
	{ type = "range", percent = true, key = "battlefield.alpha", label = "Opacity", desc = "Opacity of the whole battlefield map, on top of Blizzard's own opacity setting.", min = 0.2, max = 1, step = 0.05, hidden = Off(BATTLEFIELD) },
	Needs(BATTLEFIELD, "move", Key("Turn on Move and scale to put it on the \"Battlefield Map\" mover and size it.")),
	{ type = "range", percent = true, key = "battlefield.scale", label = "Scale", desc = "Size of the battlefield map.", min = 0.5, max = 2.5, step = 0.05, hidden = Off(BATTLEFIELD, "move") },
	{ type = "toggle", key = "battlefield.skinTab", label = "Skin its tab", desc = "The tab above the map (right-click for Blizzard's options) in the EldoUI look.", hidden = Off(BATTLEFIELD, "skin") },

	{ type = "tab", label = "Widgets" },
	{ type = "description", label = "Blizzard's UI widgets: battleground scores and capture bars, world objectives and the encounter bar. These follow Blizzard UI > UI widgets." },
	{ type = "header", label = "Position (Move and scale)" },
	Needs(WIDGETS, "move", Key("Turn on Move and scale for UI widgets to use these.")),
	{ type = "range", percent = true, key = "widgets.topScale", label = "Top-center scale", desc = "Size of the top-center widgets (on the \"Top-center Widgets\" mover).", min = 0.5, max = 1.5, step = 0.05, hidden = Off(WIDGETS, "move") },
	{ type = "toggle", key = "widgets.belowFollow", label = "Below-minimap widgets follow the minimap", desc = "They hang under EldoUI's minimap wherever you move it.", hidden = Off(WIDGETS, "move") },
	{ type = "range", key = "widgets.belowGap", label = "Gap under the minimap", desc = "Space between the minimap and the widgets below it.", min = 0, max = 40, step = 1, dependsOn = "widgets.belowFollow", hidden = Off(WIDGETS, "move") },
	{ type = "range", percent = true, key = "widgets.belowScale", label = "Below-minimap scale", desc = "Size of the widgets below the minimap.", min = 0.5, max = 1.5, step = 0.05, hidden = Off(WIDGETS, "move") },
	{ type = "range", percent = true, key = "widgets.powerScale", label = "Encounter bar scale", desc = "Size of the encounter / alternate power bar (on the \"Encounter Bar\" mover).", min = 0.5, max = 1.5, step = 0.05, hidden = Off(WIDGETS, "move") },
	{ type = "header", label = "Look (Skin)" },
	Needs(WIDGETS, "skin", Key("Turn on Skin for UI widgets to use these.")),
	{ type = "toggle", key = "widgets.fonts", label = "EldoUI font", desc = "Widget and alternate power text in the EldoUI font. Sizes and colors stay Blizzard's.", hidden = Off(WIDGETS, "skin") },
	{ type = "toggle", key = "widgets.topBackdrop", label = "Panel behind top-center widgets", desc = "A see-through panel behind the top-center widgets while any show.", hidden = Off(WIDGETS, "skin"),
		disabled = function()
			if Allowed(WIDGETS, "hide") and M.db.widgets.hideTop then return L["Turn off \"Hide top-center widgets\" first."] end
		end },
	{ type = "header", label = "Hide" },
	Needs(WIDGETS, "hide", Key("Turn on Hide for UI widgets to choose which ones to hide.")),
	{ type = "description", label = "Hidden widgets take game information with them (battleground scores, capture bars).", tone = "warning", hidden = Off(WIDGETS, "hide") },
	{ type = "toggle", key = "widgets.hideTop", label = "Hide top-center widgets", desc = "Battleground scores, capture bars and world objectives at the top of the screen.", hidden = Off(WIDGETS, "hide") },
	{ type = "toggle", key = "widgets.hideBelow", label = "Hide below-minimap widgets", desc = "Objective widgets under the minimap.", hidden = Off(WIDGETS, "hide") },
	{ type = "toggle", key = "widgets.hidePower", label = "Hide the encounter bar", desc = "The alternate power bar some encounters use.", hidden = Off(WIDGETS, "hide") },
}) do
	table.insert(M.options, row)
end

---------------------------------------------------------------------------
-- Style presets (Core/Styles.lua)
---------------------------------------------------------------------------
E:RegisterStyles("Maps", {
	{ key = "Navigator", title = "Navigator", desc = "Coordinates for you and the cursor, Blizzard's fade while moving.",
		settings = { worldMap = { coords = true, coordsPlayer = true, coordsCursor = true, coordDecimals = 1, zoneLevels = true, fade = "blizzard" } } },
	{ key = "Compact", title = "Compact map", desc = "Your own coordinates only, in whole numbers and small text. The map's size is on the Move windows page.",
		settings = { worldMap = { coords = true, coordsPlayer = true, coordsCursor = false, coordDecimals = 0, coordsSize = 12 } } },
	{ key = "Large", title = "Precise", desc = "Precise coordinates for you and the cursor in larger text. The map's size is on the Move windows page.",
		settings = { worldMap = { coords = true, coordsPlayer = true, coordsCursor = true, coordDecimals = 2, coordsSize = 14 } } },
	{ mode = true, key = "Glance", title = "See-through on the move", desc = "The map fades to 30% while you move and stays solid under the mouse.",
		settings = { worldMap = { fade = "custom", visibility = E:VisibilityDefaults({ preset = "custom", fadeMoving = true, fadedAlpha = 0.3 }) } } },
	{ key = "Battleground", title = "Battleground", desc = "Bigger battlefield map at 85% opacity, top-center scores a bit larger.",
		settings = { battlefield = { scale = 1.4, alpha = 0.85, skinTab = true }, widgets = { topScale = 1.15, topBackdrop = true, fonts = true } } },
	{ key = "Plain", title = "Blizzard-like", desc = "No coordinates, no fading, normal sizes; only the switches you set on the Blizzard UI page apply.",
		settings = { worldMap = { coords = false, fade = "off" }, battlefield = { scale = 1, alpha = 1 },
			widgets = { topScale = 1, belowScale = 1, powerScale = 1, fonts = false, topBackdrop = false } } },
}, { restores = { "worldMap.fade", "worldMap.visibility", "battlefield.alpha" } })
