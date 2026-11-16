-- EldoUI Minimap.
--
-- Three Blizzard UI elements, each with its own "Let EldoUI change this"
-- switch (Core/Blizzard.lua). With a switch off EldoUI leaves that part
-- exactly as Blizzard made it.
--
--   "minimap"              replace  EldoUI minimap: Blizzard's map in a square or
--                                   round EldoUI frame, the cluster art hidden
--                          skin     flat square or round look on Blizzard's own
--                                   minimap, in Blizzard's place ("keep cluster")
--                          move     the EldoUI_Minimap mover (off: Edit Mode position)
--                          hide     no minimap at all
--                          improve  zone, coordinates and clock text, Forever's
--                                   day/night indicator, zoom reset, middle-click,
--                                   rotate setting
--   "minimap-buttons"      move     tracking, calendar, mail, addon compartment,
--                                   clock, zoom, expansion and event buttons
--                                   placed in the map's corners or on the
--                                   slim button rail along one edge
--                          hide     buttons set to "Hidden" disappear
--                          replace  addon buttons gathered in EldoUI's button bin
--                          skin     flat buttons, time manager and stopwatch skinned
--   "queue-status-button"  move     the group finder eye on a minimap corner or
--                                   its own EldoUI_QueueStatus mover, with a size
--                          skin     a flat box behind the eye
--
-- Blizzard's Minimap widget always stays the game's own; EldoUI only
-- re-parents, re-anchors and masks it. Coordinates are empty where the game
-- hides them (instances).
local _, E = ...
local L = E.L

local MAP, BUTTONS, QUEUE = "minimap", "minimap-buttons", "queue-status-button"
local SQUARE_MASK = "Interface\\ChatFrame\\ChatFrameBackground"
local ROUND_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local BLIZZARD_MASK = "ui-hud-minimap-frame-generic-mask" -- Blizzard_Minimap/Camelot/Skin.lua

local M = E:NewModule("Minimap", {
	title = "Minimap",
	desc = "Square or round minimap with zone, coordinates, clock, button placement and an addon button bin.",
	conflicts = { "EllesmereUIMinimap" },
	frames = { "EldoUI_Minimap", "EldoUI_QueueStatus", "EldoUI_ButtonBin", "EldoUI_ButtonBinAnchor", "EldoUI_MinimapButton" },
	movers = { "EldoUI_Minimap", "EldoUI_QueueStatus", "EldoUI_ButtonBinAnchor" },
	blizzard = { "minimap", "minimap-buttons", "queue-status-button" },
	savedKeys = { "profile.modules.Minimap" },
	optionsPage = "module:Minimap",
	presets = { "Clock", "Framed", "Large", "Minimal", "Rail", "Round", "Square" },
	defaults = {
		size = 237,
		shape = "square",          -- square, round
		border = "thin",           -- thin, thick, none
		accentBorder = false,
		showZone = true,
		pingNames = true,
		zonePosition = "inside",   -- inside, outside, hover
		zoneSize = 14,
		showCoords = true,
		coordDecimals = 0,
		coordPosition = "BOTTOM",
		showClock = true,
		clockRealm = false,
		clockPosition = "TOPLEFT",
		textSize = 13,
		diel = true,               -- Forever's day/night indicator
		dielPosition = "TOPRIGHT",
		layer = true,              -- the layer chip (Modules/MinimapLayer.lua)
		layerPosition = "BOTTOMLEFT",
		layerNotice = false,       -- a chat line when your layer changes
		layerHelp = false,         -- answer other players' hop requests (with a click to invite)
		layerNetwork = false,      -- join the hidden layer network channel
		layerAddon = true,         -- with the layer addon installed, the chip opens it instead
		wheelZoom = true,
		overlaySize = 0.75,
		overlayOpacity = 0.45,
		overlayCombat = true,
		overlayCompass = false,
		overlayCircle = false,
		zoomReset = 0,             -- seconds; 0 keeps the zoom
		rotate = "blizzard",       -- blizzard (leave the game setting), on, off
		middleClick = "tracking",  -- tracking, calendar, none
		iconScale = 1,
		trackingIcon = true,       -- the flat tracking box shows the active tracking ability
		binMode = "drawer",        -- off, bar, drawer, rail, hover
		binSize = 26,
		binPerRow = 6,
		binSpacing = 2,
		binSide = "AUTO",          -- where the bin opens: AUTO (toward the screen's middle), BOTTOM, LEFT
		binExclude = {},           -- addon buttons kept on the map: frame name -> true
		binManage = "",            -- "Manage buttons" pick, taken at once (TakeManagePick)
		binInclude = {},           -- addon buttons added by frame name: name -> true
		binAdd = "",               -- "Add a button by name", taken at once (TakeAddName)
		binGrow = "AUTO",          -- AUTO (the bin side decides) or a fill direction then a wrap direction, e.g. RIGHTDOWN
		binMover = false,          -- the toggle (or the strip) on its own mover, EldoUI_ButtonBinAnchor
		binKeepOpen = false,       -- the click drawer stays open or closed across reloads
		binOpen = false,           -- the click drawer's last state, for binKeepOpen
		badge = true,              -- EldoUI's own minimap button (gathered first in the bin)
		badgeAngle = 200,          -- where it sits on the map's edge while not in the bin: degrees, 0 = east
		railSide = "LEFT",         -- the edge of the button rail: LEFT, RIGHT (buttons set to "RAIL" sit on it)
		buttons = {
			tracking = "TOPLEFT",
			calendar = "TOPRIGHT",
			mail = "BOTTOMLEFT",
			event = "LEFT",          -- the game's link button during special events
			compartment = "TOPRIGHT",
			clock = "hide",          -- Blizzard's clock button; EldoUI's clock text is "Show clock"
			zoom = "hide",
			expansion = "hide",
			queue = "BOTTOMRIGHT",
			bin = "BOTTOMRIGHT",
		},
		queue = { anchor = "minimap", scale = 0.8 }, -- anchor: minimap, free
		-- When the EldoUI minimap shows and how it fades (Core/Visibility.lua).
		visibility = E:VisibilityDefaults(),
		-- Settings from v0.5.0, read once and moved to the keys above.
		buttonBin = nil,
		hideCompartment = nil,
	},
})

local POSITIONS = {
	TOPLEFT = "Top left", TOP = "Top", TOPRIGHT = "Top right",
	LEFT = "Left", RIGHT = "Right",
	BOTTOMLEFT = "Bottom left", BOTTOM = "Bottom", BOTTOMRIGHT = "Bottom right",
}
local BUTTON_POSITIONS = { hide = "Hidden" }
for key, label in pairs(POSITIONS) do BUTTON_POSITIONS[key] = label end
-- The slim button rail along one edge of the map (Kit.IconRail): a place
-- for every button but the group finder eye.
local RAIL = "RAIL"
local RAIL_POSITIONS = { [RAIL] = "On the side rail" }
for key, label in pairs(BUTTON_POSITIONS) do RAIL_POSITIONS[key] = label end
local function Placed(position) return POSITIONS[position] ~= nil or position == RAIL end
-- How far the rail takes the corner items in from each side edge.
local railPad = { LEFT = 0, RIGHT = 0 }

-- The core's hidden parent: E:HideBlizzardFrame keeps hidden parts there
-- whenever Blizzard re-parents them.
local hider = E.BlizzardKeep.hider
local Keep = E.BlizzardKeep

local function Usable(frame)
	return type(frame) == "table" and frame.GetObjectType and not E.FrameCheck(frame, "IsForbidden")
end

---------------------------------------------------------------------------
-- Blizzard frames EldoUI moved, with what to put back.
---------------------------------------------------------------------------
local saved = {}

local function Remember(frame)
	if saved[frame] then return end
	local points = {}
	for index = 1, frame:GetNumPoints() do points[index] = { frame:GetPoint(index) } end
	saved[frame] = {
		parent = frame:GetParent(), points = points, scale = frame:GetScale(),
		level = frame:GetFrameLevel(), alpha = frame:GetAlpha(),
		width = frame:GetWidth(), height = frame:GetHeight(),
		mouse = E.FrameMouse(frame, "IsMouseEnabled"),
	}
end

-- Plain widget methods (SetPointBase ... on Edit Mode systems such as the
-- minimap cluster), so Edit Mode's overrides never run from EldoUI.
local function Restore(frame, keepSize)
	local state = saved[frame]
	if not state then return end
	saved[frame] = nil
	E:UnhideBlizzardFrame(frame, state.parent)
	E:UnpinBlizzardFrame(frame, true)
	frame:SetParent(state.parent)
	if frame.SetScale then Keep.SetScale(frame, state.scale) end
	frame:SetAlpha(state.alpha)
	if frame.SetFrameLevel then frame:SetFrameLevel(state.level) end
	if not keepSize and state.width > 0 then frame:SetSize(state.width, state.height) end
	if state.mouse ~= nil and frame.EnableMouse then frame:EnableMouse(state.mouse) end
	Keep.ClearAllPoints(frame)
	for _, point in ipairs(state.points) do Keep.SetPoint(frame, unpack(point)) end
end

local function HidePart(frame)
	if not Usable(frame) then return end
	Remember(frame)
	E:HideBlizzardFrame(frame, { check = function() return saved[frame] ~= nil end })
end

-- Some Blizzard parts must keep running while invisible (the clock button
-- checks the alarm in its OnUpdate), so they are faded instead of hidden.
local function FadePart(frame)
	if not Usable(frame) then return end
	Remember(frame)
	frame:SetAlpha(0)
	if frame.EnableMouse then frame:EnableMouse(false) end
end

local IsSecret = E.Secret

local function ZoneColor()
	local pvpType = C_PvP and C_PvP.GetZonePVPInfo and C_PvP.GetZonePVPInfo()
	if pvpType == "sanctuary" then return 0.41, 0.8, 0.94 end
	if pvpType == "friendly" then return 0.1, 1, 0.1 end
	-- Hostile in the light status red, which keeps its contrast on the
	-- text plate over a bright map.
	if pvpType == "hostile" then return unpack(E.tokens.text.bad) end
	if pvpType == "contested" then return 1, 0.7, 0 end
	return 1, 1, 1
end

---------------------------------------------------------------------------
-- Text plates: zone, coordinates and clock each sit on a small plate in the
-- panel color at the see-through floor opacity, so they read over a bright
-- map as well as a dark one. A plate shows only while its text says
-- something, so no empty dark box stays where the game hides a value.
---------------------------------------------------------------------------
local PLATE_PAD_X, PLATE_PAD_Y = 3, 1
M.plates = setmetatable({}, { __mode = "k" }) -- FontString -> its plate

function M:UpdatePlate(fs)
	if not fs then return end
	local plate = self.plates[fs]
	if not plate then
		plate = fs:GetParent():CreateTexture(nil, "BACKGROUND")
		self.plates[fs] = plate
	end
	local r, g, b = unpack(E.media.backdropColor)
	plate:SetColorTexture(r, g, b, E.tokens.panel.transparentFloor)
	local text = fs:GetText()
	local width = fs:GetStringWidth() or 0
	local box = fs:GetWidth() or 0
	if box > 0 and width > box then width = box end
	local shown = fs:IsShown() and fs:GetAlpha() > 0 and type(text) == "string" and text ~= "" and width > 0
	plate:SetShown(shown and true or false)
	if not shown then return end
	local _, size = fs:GetFont()
	local height = math.max(fs:GetStringHeight() or 0, size or 0)
	plate:ClearAllPoints()
	plate:SetPoint("CENTER", fs, "CENTER")
	plate:SetSize(width + 2 * PLATE_PAD_X, height + 2 * PLATE_PAD_Y)
end

function M:UpdatePlates()
	if not self.overlay then return end
	self:UpdatePlate(self.zone)
	self:UpdatePlate(self.coords)
	self:UpdatePlate(self.clock.text)
	local chip = self.Layer and self.Layer.chip
	if chip then self:UpdatePlate(chip.text) end
end

---------------------------------------------------------------------------
-- Settings from v0.5.0
---------------------------------------------------------------------------
function M:OnInitialize()
	local db = self.db
	if db.buttonBin ~= nil then
		if db.buttonBin and db.binMode == "off" then db.binMode = "drawer" end
		db.buttonBin = nil
	end
	if db.hideCompartment ~= nil then
		if db.hideCompartment then db.buttons.compartment = "hide" end
		db.hideCompartment = nil
	end
end

-- Forever's minimap has no instance difficulty flag any more, so its
-- position setting is dropped once from every profile.
E:RegisterProfileMigration(function(profile)
	local modules = type(profile.modules) == "table" and profile.modules or nil
	local db = modules and type(modules.Minimap) == "table" and modules.Minimap or nil
	if db and type(db.buttons) == "table" then db.buttons.difficulty = nil end
end, "minimap:difficulty", 1)

-- A fresh profile gathers the addon buttons behind one closed toggle,
-- opening toward the middle of the screen. A profile set up before keeps
-- its own choice, and so does a choice already made on the fresh one.
E:RegisterProfileMigration(function(profile)
	if not profile.needsSetup then return end
	if type(profile.modules) ~= "table" then profile.modules = {} end
	local db = profile.modules.Minimap
	if type(db) ~= "table" then
		db = {}
		profile.modules.Minimap = db
	end
	if db.binMode == nil then db.binMode = "drawer" end
	if db.binSide == nil then db.binSide = "AUTO" end
end, "minimap:drawer", 1)

---------------------------------------------------------------------------
-- The EldoUI frame around the map, the text overlay and the day/night icon
---------------------------------------------------------------------------
function M:CreateHolder()
	local holder = CreateFrame("Frame", "EldoUI_Minimap", UIParent)
	holder:SetFrameStrata("LOW")
	holder:SetSize(self.db.size, self.db.size)
	E:AddBackdrop(holder)
	self.holder = holder

	-- Round border: a disc of border color behind the round map.
	local ring = holder:CreateTexture(nil, "BACKGROUND")
	ring:SetPoint("CENTER")
	local ringMask = holder:CreateMaskTexture()
	ringMask:SetTexture(ROUND_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	ringMask:SetAllPoints(ring)
	ring:AddMaskTexture(ringMask)
	holder.ring = ring

	E:CreateMover(holder, "EldoUI_Minimap", L["Minimap"], { "TOPRIGHT", "UIParent", "TOPRIGHT", -15, -49 }, { followShown = true })
end

-- Text and EldoUI icons sit on their own frame above the map.
function M:CreateOverlay()
	local overlay = CreateFrame("Frame", nil, Minimap)
	overlay:SetAllPoints(Minimap)
	overlay:SetFrameLevel(Minimap:GetFrameLevel() + 10)
	self.overlay = overlay

	self.zone = E:CreateText(overlay, self.db.zoneSize)
	self.zone:SetWidth(200)

	self.coords = E:CreateText(overlay, self.db.textSize)

	-- The clock is a button: left-click the calendar, right-click the time manager.
	local clock = CreateFrame("Button", nil, overlay)
	clock:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	clock.text = E:CreateText(clock, self.db.textSize)
	clock.text:SetPoint("CENTER")
	clock:SetScript("OnClick", function(clicked, button)
		if E:IsOptionsLinkClick(clicked, button) or InCombatLockdown() then return end
		if button == "RightButton" then
			if ToggleTimeManager then ToggleTimeManager() end
		elseif ToggleCalendar then
			ToggleCalendar()
		end
	end)
	clock:SetScript("OnEnter", function(button)
		GameTooltip:SetOwner(button, "ANCHOR_BOTTOMLEFT")
		local hour, minute = GetGameTime()
		local r, g, b = unpack(E.media.accentColor)
		GameTooltip:AddLine(E:GameText(TIMEMANAGER_TITLE, L["Clock"]), r, g, b)
		local now = date("*t")
		E.UIKit.TipPair(GameTooltip, L["Local time"], E:FormatClock(now.hour, now.min))
		E.UIKit.TipPair(GameTooltip, L["Realm time"], E:FormatClock(hour, minute))
		GameTooltip:AddLine(" ")
		E:TooltipHint(GameTooltip, { L["Click"], L["calendar"] }, { L["Right-click"], L["alarm and stopwatch"] })
		GameTooltip:Show()
	end)
	clock:SetScript("OnLeave", GameTooltip_Hide)
	-- The shared hover and pressed look: the clock can be clicked.
	E:SkinHoverPress(clock)
	E:BindOptionsLink(clock, { page = "module:Minimap", key = "showClock" })
	self.clock = clock

	-- Forever's day/night cycle (Blizzard_Minimap/Camelot/Diel.lua), drawn with
	-- Blizzard's own atlas on a small icon instead of the round ring.
	local diel = CreateFrame("Frame", nil, overlay)
	diel:SetSize(20, 20)
	diel.icon = diel:CreateTexture(nil, "ARTWORK")
	diel.icon:SetAllPoints()
	diel:EnableMouse(true)
	diel:SetScript("OnEnter", function(frame)
		GameTooltip:SetOwner(frame, "ANCHOR_BOTTOMLEFT")
		GameTooltip:SetText(frame.isDay and L["Day"] or L["Night"])
		GameTooltip:Show()
	end)
	diel:SetScript("OnLeave", GameTooltip_Hide)
	self.diel = diel
	if self.Layer then self.Layer.CreateChip(overlay) end

	-- Everything starts hidden; ApplyImprove shows what is switched on.
	self.zone:Hide()
	self.coords:Hide()
	clock:Hide()
	diel:Hide()
end

-- Zone, coordinates and clock: twice a second on the shared tick
-- (E.Ticker) while the module is on and its texts show.
local TEXT_TICK = "Minimap:texts"
function M:StartTextTick()
	E.Ticker:Subscribe(TEXT_TICK, 0.5, function()
		if M.overlay and M.overlay:IsVisible() then M:UpdateTexts() end
	end, self)
end

function M:UpdateDiel()
	if not (C_DateAndTime and C_DateAndTime.IsDayTime) then return end
	local isDay = C_DateAndTime.IsDayTime()
	self.diel.isDay = isDay
	self.diel.icon:SetAtlas(isDay and "UI-HUD-Minimap-DayCycle" or "UI-HUD-Minimap-NightCycle")
end

function M:UpdateZone()
	if not self.zone then return end
	self.zone:SetText(GetMinimapZoneText())
	self.zone:SetTextColor(ZoneColor())
	self:RefitZone()
	self:UpdatePlate(self.zone)
end

-- Coordinates are hidden by the game in some places (instances); then the
-- text stays empty instead of guessing.
function M:UpdateCoords()
	local mapID = C_Map.GetBestMapForUnit("player")
	local position = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
	if position then
		local x, y = position:GetXY()
		if not (IsSecret(x) or IsSecret(y)) and x and y and (x > 0 or y > 0) then
			local decimals = self.db.coordDecimals or 0
			local pattern = ("%%.%df, %%.%df"):format(decimals, decimals)
			self.coords:SetText(pattern:format(x * 100, y * 100))
			self:UpdatePlate(self.coords)
			return
		end
	end
	self.coords:SetText("")
	self:UpdatePlate(self.coords)
end

function M:UpdateClock()
	local text
	-- The clock format is shared (General > Clock and durability).
	if self.db.clockRealm then
		text = E:FormatClock(GetGameTime())
	else
		local now = date("*t")
		text = E:FormatClock(now.hour, now.min)
	end
	self.clock.text:SetText(text)
	local width = self.clock:GetWidth()
	self.clock:SetSize(self.clock.text:GetStringWidth() + 4, self.clock.text:GetStringHeight() + 2)
	if math.abs((self.clock:GetWidth() or 0) - (width or 0)) > 0.5 then self:RefitZone() end
	self:UpdatePlate(self.clock.text)
end

function M:UpdateTexts()
	if not self.improved then return end
	if self.db.showCoords then self:UpdateCoords() end
	if self.db.showClock then self:UpdateClock() end
end

---------------------------------------------------------------------------
-- Corner placement: every item set to a position is stacked from that
-- corner or edge inwards, 2 px apart, 4 px from the map edge.
---------------------------------------------------------------------------
local ORDER = { "zone", "clock", "tracking", "calendar", "compartment", "diel", "event", "mail", "layer", "coords", "queue", "zoom", "expansion", "bin" }

-- Blizzard frames per button key (some keys hold more than one frame).
local function ButtonFrames(key)
	local cluster = MinimapCluster
	if key == "tracking" then return { cluster and cluster.Tracking } end
	if key == "calendar" then return { GameTimeFrame } end
	if key == "mail" then return { cluster and cluster.IndicatorFrame } end
	if key == "event" then return { MinimapBackdrop and MinimapBackdrop.ExternalEventURLButton } end
	if key == "compartment" then return { AddonCompartmentFrame } end
	if key == "clock" then return { TimeManagerClockButton } end
	if key == "zoom" then return { Minimap.ZoomIn, Minimap.ZoomOut } end
	if key == "expansion" then return { ExpansionLandingPageMinimapButton } end
	if key == "queue" then return { QueueStatusButton } end
	return {}
end
local BUTTON_KEYS = { "tracking", "calendar", "mail", "event", "compartment", "clock", "zoom", "expansion" }
-- Name and option text of each button (the rail's tooltips name them too).
local BUTTON_LABELS = {
	tracking = { "Tracking", E.Key("Blizzard's tracking menu (herbs, ore, vendors).") },
	calendar = { "Calendar", E.Key("Blizzard's calendar button with the date and invites.") },
	mail = { "Mail", E.Key("The new-mail icon.") },
	event = { E.Key("Event button"), E.Key("The game's link button during special events. It shows only while an event runs.") },
	compartment = { E.Key("Addon compartment"), E.Key("Blizzard's menu of addon buttons.") },
	clock = { E.Key("Blizzard clock"), E.Key("Blizzard's clock button (alarm and stopwatch). EldoUI's own clock text is under Text.") },
	zoom = { E.Key("Zoom buttons"), E.Key("The + and - buttons; Blizzard shows them while you point at the map.") },
	expansion = { E.Key("Expansion button"), E.Key("The expansion landing page button, if the game shows one.") },
	queue = { "Group finder eye", E.Key("Where the eye sits when it is attached to the minimap (Blizzard UI: Queue status eye).") },
	bin = { E.Key("Button bin toggle"), E.Key("The \"...\" button that opens the addon button bin.") },
}

local cornerPlacing = false
local INSET = 4

-- Items in the middle of the top or bottom edge (the zone name, or the
-- coordinates) share their row with the corner stacks next to them. They
-- take the first row, counted in from the edge, where the room between the
-- corner items beside them is wide enough; the zone ends in "..." when it is
-- longer. They never go past the middle of the map, so the zone name can't
-- run into the bottom texts however tall the corner stacks are.
local ZONE_MIN = 80
local CORNER_GAP = 6

-- On a small map a side's bottom stack can reach up into its top stack
-- (or the items in the middle of that side). It then steps in from the
-- edge, past the widest item it would meet, so no corner item touches
-- another. Returns how far the bottom stack of `side` steps in.
local function BottomStep(stacks, side, docked)
	local bottom = stacks["BOTTOM" .. side]
	if not bottom then return 0 end
	local mapHeight = Minimap:GetHeight() or 0
	local height, shown = 0, false
	for index, entry in ipairs(bottom) do
		height = height + (entry.frame:GetHeight() or 0) * (entry.scale or 1) + (index > 1 and 2 or 0)
		shown = shown or entry.frame:IsShown()
	end
	if not shown then return 0 end
	-- The top of the bottom stack, measured down from the map's top edge.
	local from = mapHeight - INSET - (docked or 0) - height
	local widest = 0
	local function Upper(list, where)
		local offset = 0
		for _, entry in ipairs(list or {}) do
			local scale = entry.scale or 1
			local itemHeight = (entry.frame:GetHeight() or 0) * scale
			local top = where == "TOP" and INSET + offset or mapHeight / 2 + offset - itemHeight / 2
			if entry.frame:IsShown() and top + itemHeight + 2 > from then
				widest = math.max(widest, (entry.frame:GetWidth() or 0) * scale)
			end
			offset = offset + itemHeight + 2
		end
	end
	Upper(stacks["TOP" .. side], "TOP")
	Upper(stacks[side], "SIDE")
	return widest > 0 and widest + CORNER_GAP or 0
end

-- One side column of the map (LEFT or RIGHT): every item of its top, side
-- and bottom stacks as a band measured down from the map's top edge,
-- { from, to, width }, the way PlaceInCorner stacks them. A hidden item
-- takes its room but no width; a bottom stack that steps in counts its step.
local function Column(stacks, side, docked)
	local mapHeight = Minimap:GetHeight() or 0
	local bands = {}
	local step = BottomStep(stacks, side, docked)
	local function Add(list, where)
		local offset = where == "BOTTOM" and docked or 0
		for _, entry in ipairs(list or {}) do
			local scale = entry.scale or 1
			local height = (entry.frame:GetHeight() or 0) * scale
			local width = entry.frame:IsShown() and (entry.frame:GetWidth() or 0) * scale or 0
			if width > 0 and where == "BOTTOM" then width = width + step end
			local from
			if where == "TOP" then
				from = INSET + offset
			elseif where == "BOTTOM" then
				from = mapHeight - INSET - offset - height
			else
				from = mapHeight / 2 + offset - height / 2
			end
			bands[#bands + 1] = { from = from, to = from + height, width = width }
			offset = offset + height + 2
		end
	end
	Add(stacks["TOP" .. side], "TOP")
	Add(stacks[side], "SIDE")
	Add(stacks["BOTTOM" .. side], "BOTTOM")
	return bands
end

local function SideAt(bands, from, to)
	local width = 0
	for _, band in ipairs(bands) do
		if band.width > 0 and band.from < to and band.to > from then width = math.max(width, band.width) end
	end
	return width
end

-- The row of a middle stack on the TOP or BOTTOM edge, `height` high and
-- needing `need` of width, `base` in from its edge (docked panels): how
-- far in it goes and the room it gets there. It stays in its half of the
-- map; when no row is wide enough it keeps the edge row.
local function FitRow(stacks, edge, height, need, base, docked)
	local mapWidth, mapHeight = Minimap:GetWidth() or 0, Minimap:GetHeight() or 0
	local left, right = Column(stacks, "LEFT", docked), Column(stacks, "RIGHT", docked)
	-- The band a drop gives, measured down from the top.
	local function Band(drop)
		if edge == "TOP" then return INSET + drop, INSET + drop + height end
		local bottom = mapHeight - INSET - base - drop
		return bottom - height, bottom
	end
	local function RoomAt(drop)
		local from, to = Band(drop)
		local l, r = SideAt(left, from, to), SideAt(right, from, to)
		local side = math.max(railPad.LEFT + l + (l > 0 and CORNER_GAP or 0), railPad.RIGHT + r + (r > 0 and CORNER_GAP or 0))
		return mapWidth - 2 * (INSET + side)
	end
	local candidates = { 0 }
	for _, bands in ipairs({ left, right }) do
		for _, band in ipairs(bands) do
			local drop = edge == "TOP" and (band.to + 2 - INSET) or (mapHeight - band.from + 2 - INSET - base)
			if drop > 0 then candidates[#candidates + 1] = drop end
		end
	end
	table.sort(candidates)
	for _, drop in ipairs(candidates) do
		local from, to = Band(drop)
		if (edge == "TOP" and to > mapHeight / 2) or (edge ~= "TOP" and from < mapHeight / 2) then break end
		local room = RoomAt(drop)
		if room >= need then return drop, room end
	end
	return 0, RoomAt(0)
end

-- The zone name inside the map at the top: the first row where the room
-- between the corner items beside it is wide enough, ending in "..." when
-- the name is longer. When no row in the top half has room, it stays out
-- of sight rather than squeezed to a dot.
function M:FitZone()
	local stacks = self.zoneStacks
	if not stacks then return 0 end
	local zone = self.zone
	local text = zone.GetUnboundedStringWidth and zone:GetUnboundedStringWidth() or zone:GetStringWidth() or 0
	local height = zone:GetHeight() or 0
	local need = math.min(text, ZONE_MIN)
	local drop, room = FitRow(stacks, "TOP", height, need, 0, self.zoneDocked or 0)
	zone:SetWordWrap(false)
	zone:SetWidth(math.max(1, room))
	zone:ClearAllPoints()
	zone:SetPoint("TOP", Minimap, "TOP", 0, -INSET - drop)
	zone:SetAlpha(room >= math.min(need, ZONE_MIN / 2) and 1 or 0)
	self.zoneDrop = drop
	self:UpdatePlate(zone)
	return drop + height + 2
end

-- A new zone name or a wider clock: fit the zone again, and place the
-- corners again when the zone moves to another row.
function M:RefitZone()
	if not self.zoneStacks then return end
	local drop = self.zoneDrop
	self:FitZone()
	if self.zoneDrop ~= drop then
		E:RunOutOfCombat(function() M:LayoutCorners() end, "minimap:corners")
	end
end

-- The bottom middle stack (the coordinates by default): the row in from
-- the bottom where it clears the corner items beside it.
local function BottomOffset(stacks, docked)
	local list = stacks.BOTTOM
	if not list then return 0 end
	local width, height = 0, 0
	for index, entry in ipairs(list) do
		local scale = entry.scale or 1
		local frame = entry.frame
		local w = frame.GetStringWidth and frame:GetStringWidth() or frame:GetWidth()
		width = math.max(width, (w or 0) * scale)
		height = height + (frame:GetHeight() or 0) * scale + (index > 1 and 2 or 0)
	end
	return (FitRow(stacks, "BOTTOM", height, width, docked, docked))
end

function M:PlaceInCorner(entries)
	cornerPlacing = true
	self.cornerEntries = entries
	local stacks = {}
	for _, entry in ipairs(entries) do
		stacks[entry.position] = stacks[entry.position] or {}
		table.insert(stacks[entry.position], entry)
	end
	local inset = INSET
	-- Info Bar data panels docked on the map's bottom edge push the bottom
	-- icons and texts up.
	local infoBar = E.modules.InfoBar
	local docked = infoBar and infoBar.AttachedHeight and infoBar:AttachedHeight("minimap") or 0
	self.zoneStacks = nil
	self.pingStacks, self.pingDocked, self.pingBottom = stacks, docked, docked
	if stacks.TOP and stacks.TOP[1] and stacks.TOP[1].frame == self.zone then
		self.zoneStacks, self.zoneDocked = stacks, docked
	else
		self.zone:SetAlpha(1)
	end
	-- How far each side's bottom stack steps in to clear its top stack.
	local steps = { BOTTOMLEFT = BottomStep(stacks, "LEFT", docked), BOTTOMRIGHT = BottomStep(stacks, "RIGHT", docked) }
	self.cornerSteps = steps
	for position, list in pairs(stacks) do
		local offset = position:find("BOTTOM") and docked or 0
		local step = steps[position] or 0
		local first = 1
		if position == "TOP" and self.zoneStacks then
			-- The zone is placed by FitZone; the rest of the stack goes under it.
			offset = self:FitZone()
			first = 2
		elseif position == "BOTTOM" then
			offset = offset + BottomOffset(stacks, docked)
		end
		for index = first, #list do
			local entry = list[index]
			local frame = entry.frame
			local scale = entry.scale or 1
			local x, y = 0
			if position:find("LEFT") then x = inset + railPad.LEFT + step elseif position:find("RIGHT") then x = -inset - railPad.RIGHT - step end
			-- Top items stack downwards, bottom items upwards, side items downwards
			-- from the middle of the edge.
			if position:find("TOP") then y = -inset - offset elseif position:find("BOTTOM") then y = inset + offset else y = -offset end
			Keep.ClearAllPoints(frame)
			Keep.SetPoint(frame, position, Minimap, position, x / scale, y / scale)
			offset = offset + frame:GetHeight() * scale + 2
		end
		if position == "BOTTOM" then self.pingBottom = offset end
	end
	cornerPlacing = false
end

-- Minimap pings arrive as an ordinary frame event, separate from world
-- pings. The game's own event callback table is closed to addons, so the
-- module listens through its regular event registration.
do
	local EVENT, TICK = "MINIMAP_PING", "Minimap:ping-name"
	local HOLD, FADE, REPEAT = 3, 0.4, 0.25
	local RECENT_LIMIT = 16
	local recent, nextRecent = {}, 1

	local function Enabled()
		return M.active and M.db.pingNames and M.improved and E:BlizzardAllowed(MAP, "improve")
	end

	local function Finite(value)
		return not IsSecret(value) and type(value) == "number" and value == value and math.abs(value) < math.huge
	end

	local function SenderName(unit)
		local name = E.PlainCallAll(UnitName, unit)
		if type(name) ~= "string" or name == "" or name == _G.UNKNOWNOBJECT then return nil end
		local displayName = E.PlainCall(E.DisplayName, E, unit)
		if type(displayName) == "string" and displayName ~= "" then return displayName end
	end

	function M:PositionPingName()
		local text = self.pingName
		if not (self.activePing and self.pingStacks and text) then return end
		E:SetWindowFont(text, self.db.textSize)
		text.kitSize = self.db.textSize
		local _, height = text:GetFont()
		height = height or self.db.textSize
		local width = text:GetUnboundedStringWidth() or 0
		local maxWidth = Minimap:GetWidth() * 0.5
		local need = math.min(width, maxWidth) + 2 * PLATE_PAD_X
		local drop, room = FitRow(self.pingStacks, "BOTTOM", height + 2 * PLATE_PAD_Y, need, self.pingBottom, self.pingDocked)
		text:ClearAllPoints()
		text:SetPoint("BOTTOM", Minimap, "BOTTOM", 0, INSET + self.pingBottom + drop + PLATE_PAD_Y)
		text:SetWidth(math.max(1, math.min(width, room - 2 * PLATE_PAD_X, maxWidth)))
		text:SetShown(room >= math.min(need, 24))
		self:UpdatePlate(text)
	end

	function M:HidePingName()
		self.activePing = nil
		E.Ticker:Unsubscribe(TICK)
		if self.pingLabel then
			self.pingName:SetText("")
			self.pingLabel:Hide()
		end
	end

	local function UpdatePing()
		local ping = M.activePing
		if not ping then return end
		local left = ping.expires - GetTime()
		if left <= 0 or not Enabled() or not M.overlay:IsVisible()
			or E.PlainCall(UnitGUID, ping.unit) ~= ping.guid then
			M:HidePingName()
			return
		end
		-- Names and stream aliases can change while the label is on screen.
		local name = SenderName(ping.unit)
		if not name then
			M:HidePingName()
			return
		end
		if name ~= M.pingName:GetText() then
			M.pingName:SetText(name)
			M:PositionPingName()
		end
		M.pingLabel:SetAlpha(math.min(1, left / FADE))
	end

	local function GroupToken(unit)
		return unit == "player" or unit:match("^party%d+$") or unit:match("^raid%d+$")
	end

	local function OnPing(unit, y, x)
		if not Enabled() or not (M.overlay and M.overlay:IsVisible()) then return end
		if IsSecret(unit) or type(unit) ~= "string" or not Finite(y) or not Finite(x) then return end
		local guid = E.PlainCall(UnitGUID, unit)
		if type(guid) ~= "string" or not guid:match("^Player%-") then return end
		local name = SenderName(unit)
		if not name then return end

		local now = GetTime()
		for _, ping in ipairs(recent) do
			if now - ping.at <= REPEAT and guid == ping.guid and x == ping.x and y == ping.y then
				-- Prefer a group token over a target that can change during the hold.
				if ping == M.activePing and GroupToken(unit) and not GroupToken(ping.unit) then ping.unit = unit end
				return
			end
		end
		local ping = { unit = unit, guid = guid, x = x, y = y, at = now, expires = now + HOLD + FADE }
		recent[nextRecent] = ping
		nextRecent = nextRecent % RECENT_LIMIT + 1

		if not M.pingLabel then
			local label = CreateFrame("Frame", nil, M.overlay)
			label:SetAllPoints(M.overlay)
			label:EnableMouse(false)
			M.pingLabel = label
			M.pingName = E.UIKit.Text(label, M.db.textSize, "CENTER")
			M.pingName:SetWordWrap(false)
			M.pingName:SetMaxLines(1)
		end
		local _, class = E.PlainCallEach(UnitClass, unit)
		local r, g, b
		if type(class) == "string" then r, g, b = E:GetClassColor(class) end
		if not r then r, g, b = unpack(E.tokens.text.body) end
		M.pingName:SetTextColor(r, g, b)
		M.pingName:SetText(name)
		M.activePing = ping
		M:PositionPingName()
		M.pingLabel:SetAlpha(1)
		M.pingLabel:Show()
		if not E.Ticker:IsSubscribed(TICK) then E.Ticker:Subscribe(TICK, 0.1, UpdatePing, M) end
	end

	function M:StopPingNames()
		self:HidePingName()
		wipe(recent)
		nextRecent = 1
		self:UnregisterEvent(EVENT)
	end

	local function OnPingEvent(_, _, unit, y, x)
		OnPing(unit, y, x)
	end

	function M:ApplyPingNames()
		if not Enabled() then
			self:StopPingNames()
			return
		end
		self:RegisterEvent(EVENT, OnPingEvent)
	end
end

function M:LayoutCorners()
	if not self.overlay then return end
	self:LayoutRail()
	local db = self.db
	local entries = {}
	local function Add(key, frame, position, scale)
		if frame and position and POSITIONS[position] then
			entries[#entries + 1] = { key = key, frame = frame, position = position, scale = scale }
		end
	end
	local improve = self.improved
	for _, key in ipairs(ORDER) do
		if key == "zone" then
			if improve and db.showZone and db.zonePosition ~= "outside" then Add(key, self.zone, "TOP") end
		elseif key == "clock" then
			if improve and db.showClock then Add(key, self.clock, db.clockPosition) end
			if self.buttonsMoved and db.buttons.clock ~= "hide" then
				Add(key, TimeManagerClockButton, db.buttons.clock, db.iconScale)
			end
		elseif key == "coords" then
			if improve and db.showCoords then Add(key, self.coords, db.coordPosition) end
		elseif key == "diel" then
			if improve and db.diel and C_DateAndTime and C_DateAndTime.IsDayTime then Add(key, self.diel, db.dielPosition) end
		elseif key == "layer" then
			local chip = self.Layer and self.Layer.chip
			if chip and self.Layer.ChipShown() then Add(key, chip, db.layerPosition) end
		elseif key == "queue" then
			if self.queueOnMap then Add(key, QueueStatusButton, db.buttons.queue, db.queue.scale) end
		elseif key == "bin" then
			if self.binToggle and self.binToggle:IsShown() and not self.binOnRail and not self.binFree then Add(key, self.binToggle, db.buttons.bin) end
		elseif self.buttonsMoved then
			local position = db.buttons[key]
			for _, frame in ipairs(ButtonFrames(key)) do
				-- The event button shows itself only while an event runs, so it
				-- takes no room in its corner the rest of the time.
				if Usable(frame) and frame:GetParent() ~= hider and (key ~= "event" or frame:IsShown()) then
					Add(key, frame, position, db.iconScale)
				end
			end
		end
	end
	self:PlaceInCorner(entries)
	self:PositionPingName()
	-- Zone text above the map.
	if improve and db.showZone and db.zonePosition == "outside" then
		self.zone:ClearAllPoints()
		-- As wide as the map: long names fit a large map, and a small map
		-- shortens them instead of letting them stick out.
		self.zone:SetWidth(math.max(1, (Minimap:GetWidth() or 200) - 8))
		self.zone:SetPoint("BOTTOM", Minimap, "TOP", 0, 6)
	end
	self:UpdatePlates()
	if not self.layingOut and E.RefreshMinimapCluster then E:RefreshMinimapCluster() end
end

---------------------------------------------------------------------------
-- Element "minimap"
---------------------------------------------------------------------------
local anchoring, masking = false, false

-- Cluster art that the EldoUI minimap replaces.
local function ClusterArt()
	local cluster = MinimapCluster
	return {
		cluster and cluster.ZoneTextButton,
		cluster and cluster.DielFrame,
		cluster and cluster.MinimapContainer and cluster.MinimapContainer.PlayerCoords,
	}
end

-- Forever's header and minimap buttons draw their look with two textures:
-- StateTexture (the art) and AddTexture (the hover glow, whose alpha the
-- game sets on every mouse-over). While flat, both stay at alpha 0; the
-- alpha the game asked for last is put back when the flat look ends.
local flatArt = setmetatable({}, { __mode = "k" })  -- texture -> alpha to put back
local flatHooked = setmetatable({}, { __mode = "k" })
local zeroing = false

local function FlattenTexture(texture, on)
	if not Usable(texture) or not texture.SetAlpha then return end
	if on then
		if flatArt[texture] == nil then flatArt[texture] = texture:GetAlpha() end
		if not flatHooked[texture] then
			flatHooked[texture] = true
			hooksecurefunc(texture, "SetAlpha", function(self, alpha)
				if zeroing or flatArt[self] == nil then return end
				flatArt[self] = alpha
				zeroing = true
				self:SetAlpha(0)
				zeroing = false
			end)
		end
		zeroing = true
		texture:SetAlpha(0)
		zeroing = false
	elseif flatArt[texture] ~= nil then
		local alpha = flatArt[texture]
		flatArt[texture] = nil
		texture:SetAlpha(alpha)
	end
end

local function FlattenButtonArt(button, on)
	if not Usable(button) then return end
	FlattenTexture(button.StateTexture, on)
	FlattenTexture(button.AddTexture, on)
end

function M:SetMask()
	masking = true
	local mask = self.db.shape == "round" and ROUND_MASK or SQUARE_MASK
	Minimap:SetMaskTexture(mask)
	if HybridMinimap and HybridMinimap.CircleMask then HybridMinimap.CircleMask:SetTexture(mask) end
	masking = false
end

-- Force the map texture to redraw at a new size or mask.
local function Redraw()
	local zoom = Minimap:GetZoom()
	Minimap:SetZoom(zoom > 0 and zoom - 1 or zoom + 1)
	Minimap:SetZoom(zoom)
end

function M:AnchorMinimap()
	if anchoring or E:MinimapHostOwner() then return end
	anchoring = true
	local inset = self.borderSize or E.pixel
	Minimap:SetParent(self.holder)
	Minimap:ClearAllPoints()
	Minimap:SetPoint("TOPLEFT", self.holder, "TOPLEFT", inset, -inset)
	Minimap:SetPoint("BOTTOMRIGHT", self.holder, "BOTTOMRIGHT", -inset, inset)
	anchoring = false
end

-- Holder placement: EldoUI's mover, or (Move off) follow Blizzard's own
-- minimap container wherever Edit Mode puts it.
function M:AnchorHolder()
	local holder = self.holder
	local container = MinimapCluster and MinimapCluster.MinimapContainer
	holder:ClearAllPoints()
	if E:BlizzardAllowed(MAP, "move") or not container then
		holder:SetPoint("CENTER", E.movers.EldoUI_Minimap, "CENTER")
	else
		holder:SetPoint("CENTER", container, "CENTER")
	end
end

-- The skin's frame around the map (Core/Skins.lua), on its own frame just
-- above the map and below the texts and buttons: the skin's ring around a
-- round map, the skin's border around a square one. Native skins only, with
-- a border (None stays none) and without Accent border (the player's flat
-- accent edge wins). The art reaches a little past the map; where the map
-- takes the mouse does not change. Returns true when the skin draws it.
function M:PaintSkinFrame(target)
	local db = self.db
	local id = E:SkinPart("minimap")
	local native = target and db.border ~= "none" and not db.accentBorder and E.Skins and E.Skins.IsNative(id)
	local frame = self.skinRing
	self.paintPad = 0
	if not native then
		self:PaintOriginalHardware(nil)
		if frame then
			E:ReleaseSurface(frame)
			frame:Hide()
		end
		return false
	end
	if not frame then
		frame = CreateFrame("Frame", nil, Minimap)
		frame:EnableMouse(false)
		self.skinRing = frame
	end
	frame:SetParent(Minimap)
	frame:SetFrameLevel(Minimap:GetFrameLevel() + 2)
	local round = db.shape == "round"
	-- Vanilla Original on a round map: the game's own classic border.
	if round and self:PaintOriginalHardware(target, id) then
		E:ReleaseSurface(frame)
		frame:Hide()
		return true
	end
	self:PaintOriginalHardware(nil)
	-- A round ring is a portrait ring scaled up: half its band lies over the
	-- map's edge, half outside it.
	local pad = 0
	if round then
		local m = E:SkinManifest(id)
		local ring = m.data and m.data.metrics.portrait and m.data.metrics.portrait.ring
		local size = target == self.holder and db.size or target:GetWidth() or db.size
		pad = math.max(0, math.floor(size * 0.04 + 0.5) - (ring and ring.outset or 0))
	end
	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", target, "TOPLEFT", -pad, pad)
	frame:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", pad, -pad)
	frame:Show()
	E:PaintSurface(frame, "minimap", "minimap", { square = not round })
	-- How far the drawn ring reaches past the map's box: the frames beside
	-- and under the map keep their gap to it (Core/Layout.lua).
	self.paintPad = pad
	return true
end

-- The classic minimap border of the game client itself (E:SetOriginalArt,
-- Core/Media.lua) round a round map, for a skin that draws the original
-- art (Vanilla Original). It keeps the classic proportions: the map at its
-- classic size of 140 scales the whole border evenly. A map that moves or
-- resizes takes it along; it never takes the mouse. target nil (or a skin
-- without original art, or a client without the file) hides it. Returns
-- true when the border is drawn.
function M:PaintOriginalHardware(target, skinId)
	local frame = self.originalHardware
	local slot = "minimap-border"
	local row = target and E.OriginalArtSkin and E:OriginalArtSkin(skinId) and E:OriginalArt(slot)
	if not row or E:OriginalArtState(slot) == "missing" and not row.shipped then
		if frame then frame:Hide() end
		return false
	end
	if not frame then
		frame = CreateFrame("Frame", nil, Minimap)
		frame:EnableMouse(false)
		frame.border = frame:CreateTexture(nil, "ARTWORK")
		self.originalHardware = frame
	end
	frame:SetParent(Minimap)
	frame:SetFrameLevel(Minimap:GetFrameLevel() + 2)
	frame:ClearAllPoints()
	frame:SetAllPoints(target)
	local size = target == self.holder and self.db.size or target:GetWidth() or self.db.size
	local k = (size or row.map) / row.map
	local border = frame.border
	border:ClearAllPoints()
	border:SetPoint("CENTER", target, "CENTER", row.offset[1] * k, row.offset[2] * k)
	border:SetSize(row.size[1] * k, row.size[2] * k)
	E:SetOriginalArt(border, slot)
	border:Show()
	frame:Show()
	return true
end

-- The map's border: the panel edge of the art style (two pixels under
-- high contrast), three of them for Thick.
local function BorderSize(db)
	local edge = E:EdgeSize()
	return db.border == "thick" and 3 * edge or (db.border == "none" and 0 or edge)
end

function M:StyleHolder()
	local db, holder = self.db, self.holder
	local border = BorderSize(db)
	self.borderSize = border
	local r, g, b, a = unpack(E.media.borderColor)
	if db.accentBorder then r, g, b = unpack(E.media.accentColor) end
	local skinned = self:PaintSkinFrame(holder)
	if db.shape == "round" then
		holder:SetBackdrop(nil)
		holder.ring:SetShown(border > 0 and not skinned)
		holder.ring:SetSize(db.size, db.size)
		holder.ring:SetColorTexture(r, g, b, a or 1)
	else
		holder.ring:Hide()
		holder:SetBackdrop({ bgFile = E.media.flat, edgeFile = E.media.flat, edgeSize = math.max(border, E.pixel) })
		holder:SetBackdropColor(unpack(E.media.backdropColor))
		if border > 0 and not skinned then holder:SetBackdropBorderColor(r, g, b, a or 1) else holder:SetBackdropBorderColor(0, 0, 0, 0) end
	end
end

-- Skin without replacing: a flat border around Blizzard's map in its place.
function M:SkinBlizzardMinimap(on)
	local db = self.db
	if on then
		if not self.skinFrame then
			local frame = CreateFrame("Frame", nil, Minimap)
			frame:SetFrameLevel(math.max(Minimap:GetFrameLevel() - 1, 0))
			frame.ring = frame:CreateTexture(nil, "BACKGROUND")
			frame.ring:SetAllPoints()
			local mask = frame:CreateMaskTexture()
			mask:SetTexture(ROUND_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
			mask:SetAllPoints(frame.ring)
			frame.ring:AddMaskTexture(mask)
			E:AddBackdrop(frame)
			self.skinFrame = frame
		end
		local frame = self.skinFrame
		local border = BorderSize(db)
		frame:ClearAllPoints()
		frame:SetPoint("TOPLEFT", Minimap, "TOPLEFT", -border, border)
		frame:SetPoint("BOTTOMRIGHT", Minimap, "BOTTOMRIGHT", border, -border)
		local r, g, b, a = unpack(E.media.borderColor)
		if db.accentBorder then r, g, b = unpack(E.media.accentColor) end
		local skinned = self:PaintSkinFrame(frame)
		if db.shape == "round" then
			frame:SetBackdrop(nil)
			frame.ring:SetShown(not skinned)
			frame.ring:SetColorTexture(r, g, b, a or 1)
		else
			frame.ring:Hide()
			frame:SetBackdrop({ bgFile = E.media.flat, edgeFile = E.media.flat, edgeSize = math.max(border, E.pixel) })
			frame:SetBackdropColor(unpack(E.media.backdropColor))
			frame:SetBackdropBorderColor(r, g, b, (border > 0 and not skinned) and (a or 1) or 0)
		end
		frame:Show()
		for _, region in ipairs({ MinimapCompassTexture, MinimapCompassTextureUnderlay }) do
			if Usable(region) then region:SetAlpha(0) end
		end
		local cluster = MinimapCluster
		-- The header keeps the zone name and loses its button art.
		FlattenButtonArt(cluster and cluster.ZoneTextButton, true)
		if Usable(MinimapZoneText) then E:SetFont(MinimapZoneText, db.zoneSize) end
		if cluster and Usable(cluster.DielFrame) then cluster.DielFrame:SetAlpha(0) end
	elseif self.skinFrame then
		self:PaintSkinFrame(nil)
		self.skinFrame:Hide()
		for _, region in ipairs({ MinimapCompassTexture, MinimapCompassTextureUnderlay }) do
			if Usable(region) then region:SetAlpha(1) end
		end
		local cluster = MinimapCluster
		FlattenButtonArt(cluster and cluster.ZoneTextButton, false)
		if cluster and Usable(cluster.DielFrame) then cluster.DielFrame:SetAlpha(1) end
	end
end

-- Move without replacing: Blizzard's whole cluster follows the EldoUI mover.
-- The cluster is an Edit Mode system: the core pin re-applies this after
-- every layout pass, with the plain widget methods.
function M:AnchorCluster()
	if anchoring or not MinimapCluster then return end
	anchoring = true
	Remember(MinimapCluster)
	self.holder:SetBackdrop(nil)
	self.holder.ring:Hide()
	self.holder:SetSize(MinimapCluster:GetWidth(), MinimapCluster:GetHeight())
	local holder = self.holder
	E:PinBlizzardFrame(MinimapCluster, {
		holder = holder,
		active = function() return M.active and M.clusterMoved and true or false end,
		anchor = function() return "TOPRIGHT", holder, "TOPRIGHT", 0, 0 end,
	})
	anchoring = false
end

function M:HookMinimap()
	if self.hooked then return end
	self.hooked = true
	-- Edit Mode may move the map or the cluster back; put them straight back.
	hooksecurefunc(Minimap, "SetPoint", function()
		-- Shown large in another EldoUI frame (the dungeon view's Live mode):
		-- that frame puts it back.
		if anchoring or not M.active or M.mode ~= "replace" or E:MinimapHostOwner() then return end
		E:RunOutOfCombat(function() if M.mode == "replace" then M:AnchorMinimap() end end, "minimap:anchor")
	end)
	-- Forever's skin resets the mask when the rotate setting changes.
	hooksecurefunc(Minimap, "SetMaskTexture", function()
		if masking or not M.active or not M.masked then return end
		C_Timer.After(0, function()
			if M.active and M.masked then M:SetMask() end
		end)
	end)
	-- Blizzard zooms with the wheel itself; EldoUI only adds the zoom reset.
	Minimap:HookScript("OnMouseWheel", function()
		if M.active and not M.minimapOverlay and E:BlizzardAllowed(MAP, "improve") then M:ScheduleZoomReset() end
	end)
	Minimap:HookScript("OnMouseUp", function(_, button)
		if button ~= "MiddleButton" or not M.active or not E:BlizzardAllowed(MAP, "improve") then return end
		M:MiddleClick()
	end)
	Minimap:HookScript("OnEnter", function() M:HoverZone(true) end)
	Minimap:HookScript("OnLeave", function() M:HoverZone(false) end)
	-- Blizzard's Toggle Minimap key only calls Minimap:Hide() and :Show().
	-- The holder follows it, so its border, texts and buttons don't stay
	-- around an empty square. Method hooks, not OnHide/OnShow, so
	-- hiding the whole UI (Alt+Z) doesn't count as the player's choice.
	hooksecurefunc(Minimap, "Hide", function()
		M:CloseMinimapOverlay()
		M:FollowMapShown()
	end)
	hooksecurefunc(Minimap, "Show", function() M:FollowMapShown() end)
end

function M:FollowMapShown()
	if not self.active or self.minimapOverlay or self.mode ~= "replace" or not self.holder then return end
	E:RunOutOfCombat(function()
		if M.active and not M.minimapOverlay and M.mode == "replace" and M.holder then
			M.holder:SetShown(Minimap:IsShown())
		end
	end, "minimap:shown")
end

-- On mouseover: the zone name shows while the cursor is anywhere on the
-- map, the clock, the layer chip and the corner buttons included. Leaving
-- the map for one of them is not leaving the map, so the name hides only
-- once the cursor is off the map's area.
local function CursorOnMap()
	local area = (M.mode == "replace" and M.holder) or Minimap
	return area:IsMouseOver() or Minimap:IsMouseOver()
end

function M:HoverZone(over)
	if not self.zone or not self.improved then return end
	if not (self.db.showZone and self.db.zonePosition == "hover") then return end
	local watch = self.zoneWatch
	if over or CursorOnMap() then
		self.zone:Show()
		self:UpdatePlate(self.zone)
		if not over then
			if not watch then
				watch = CreateFrame("Frame", nil, Minimap)
				watch.wait = 0
				watch:SetScript("OnUpdate", function(frame, elapsed)
					frame.wait = frame.wait + elapsed
					if frame.wait < 0.1 then return end
					frame.wait = 0
					if not CursorOnMap() then
						frame:Hide()
						M:HoverZone(false)
					end
				end)
				self.zoneWatch = watch
			end
			watch:Show()
		end
		return
	end
	if watch then watch:Hide() end
	self.zone:Hide()
	self:UpdatePlate(self.zone)
end

function M:MiddleClick()
	local action = self.db.middleClick
	if InCombatLockdown() then return end
	if action == "tracking" then
		local tracking = MinimapCluster and MinimapCluster.Tracking and MinimapCluster.Tracking.Button
		if tracking and tracking.OpenMenu then tracking:OpenMenu() end
	elseif action == "calendar" and ToggleCalendar then
		ToggleCalendar()
	end
end

-- Zoom back out a while after the last wheel turn.
function M:ScheduleZoomReset()
	if self.zoomTimer then self.zoomTimer:Cancel() end
	self.zoomTimer = nil
	local delay = self.db.zoomReset
	if not delay or delay <= 0 then return end
	self.zoomTimer = C_Timer.NewTimer(delay, function()
		self.zoomTimer = nil
		if self.active then Minimap:SetZoom(0) end
	end)
end

-- replace: EldoUI minimap. hide: no minimap. keep: Blizzard's minimap in
-- Blizzard's cluster, maybe skinned and moved. nil: switch off.
local function MapMode()
	if not E:BlizzardAllowed(MAP) then return nil end
	if E:BlizzardAllowed(MAP, "replace") then return "replace" end
	if E:BlizzardAllowed(MAP, "hide") then return "hide" end
	return "keep"
end

function M:ApplyMap()
	if self:RefreshMinimapOverlay() then return end
	local db = self.db
	local mode = MapMode()
	local skinned = mode == "keep" and E:BlizzardAllowed(MAP, "skin")
	local clusterMoved = mode == "keep" and E:BlizzardAllowed(MAP, "move")
	-- Coming from another mode: undo it first, then build the new one.
	if self.mode ~= mode or self.skinned ~= skinned or self.clusterMoved ~= clusterMoved then self:RestoreMap() end
	self.mode, self.skinned, self.clusterMoved = mode, skinned, clusterMoved
	if not mode then return end
	self:HookMinimap()

	if mode == "hide" then
		HidePart(MinimapCluster)
		if self.holder then self.holder:Hide() end
	elseif mode == "replace" then
		if not self.holder then self:CreateHolder() end
		for _, part in ipairs(ClusterArt()) do HidePart(part) end
		for _, region in ipairs({ MinimapCompassTexture, MinimapCompassTextureUnderlay }) do
			if Usable(region) then region:SetAlpha(0) end
		end
		if MinimapCluster then
			Remember(MinimapCluster)
			MinimapCluster:EnableMouse(false) -- the empty cluster must not block clicks
		end
		Remember(Minimap)
		self:StyleHolder()
		self.holder:SetSize(db.size, db.size)
		-- A new map size re-places the frames the layout moves for a larger
		-- map (the timer and the quest list under it).
		if self.placedSize ~= db.size then
			self.placedSize = db.size
			if E.ApplyWidePoints then E:ApplyWidePoints() end
		end
		-- Stays hidden while the player has the map toggled off.
		self.holder:SetShown(Minimap:IsShown())
		self:AnchorHolder()
		self:AnchorMinimap()
		if not E:MinimapHostOwner() then Minimap:SetSize(db.size - 2 * self.borderSize, db.size - 2 * self.borderSize) end
		self.masked = true
		self:SetMask()
		Redraw()
	else
		if skinned then
			self:SkinBlizzardMinimap(true)
			self.masked = true
			self:SetMask()
			Redraw()
		end
		if clusterMoved then
			if not self.holder then self:CreateHolder() end
			self.holder:Show()
			self.holder:ClearAllPoints()
			self.holder:SetPoint("CENTER", E.movers.EldoUI_Minimap, "CENTER")
			self:AnchorCluster()
		elseif self.holder then
			self.holder:Hide()
		end
	end
	self:ApplyImprove()
	self:ApplyVisibility()
end

-- Visibility: the shared rules fade the EldoUI minimap (Replace)
-- together with the addon button bin. Alpha only, so the map keeps working
-- in combat; hovering the map or the bin shows it again.
local function InMoveMode() return E:IsMoveMode() end
local function BinAlpha(_, alpha)
	if M.bin then M.bin:SetAlpha(alpha) end
end

function M:ApplyVisibility()
	local holder = self.holder
	if not holder then return end
	if self.active and self.mode == "replace" then
		E:AttachVisibility(holder, self.db.visibility, {
			watch = self.bin and { holder, self.bin } or holder,
			forceShow = InMoveMode,
			onAlpha = BinAlpha,
		})
	elseif E:IsVisibilityAttached(holder) then
		E:DetachVisibility(holder)
	end
end

function M:ApplyImprove()
	local db = self.db
	self.improved = E:BlizzardAllowed(MAP, "improve") and self.mode ~= "hide"
	if (self.improved or self.buttonsMoved) and not self.overlay then self:CreateOverlay() end
	if self.overlay then
		self.overlay:SetShown(self.mode ~= nil and self.mode ~= "hide")
		self.overlay:SetFrameLevel(Minimap:GetFrameLevel() + 10)
		E:SetFont(self.zone, db.zoneSize)
		E:SetFont(self.coords, db.textSize)
		E:SetFont(self.clock.text, db.textSize)
		local on = self.improved
		self.zone:SetShown(on and db.showZone and db.zonePosition ~= "hover")
		self.coords:SetShown(on and db.showCoords)
		self.clock:SetShown(on and db.showClock)
		self.diel:SetShown(on and db.diel and C_DateAndTime and C_DateAndTime.IsDayTime and true or false)
	end
	local coords = MinimapCluster and MinimapCluster.MinimapContainer and MinimapCluster.MinimapContainer.PlayerCoords
	if self.improved then
		self:UpdateZone()
		self:UpdateDiel()
		self:UpdateTexts()
		Minimap:EnableMouseWheel(db.wheelZoom and true or false)
		if db.rotate ~= "blizzard" then
			E:SetCVar("rotateMinimap", db.rotate == "on" and 1 or 0, MAP)
		else
			E:RestoreCVar("rotateMinimap", MAP)
		end
		-- Blizzard's own coordinates under the map would show twice.
		if db.showCoords and self.mode == "keep" then HidePart(coords) end
	else
		Minimap:EnableMouseWheel(true)
		E:RestoreCVar("rotateMinimap", MAP)
	end
	if self.mode == "keep" and not (self.improved and db.showCoords) and Usable(coords) then Restore(coords) end
	if self.Layer then self.Layer.Refresh() end
	self:LayoutCorners()
	self:ApplyPingNames()
end

-- Back to Blizzard's minimap. Size and mask come back at once; the cluster
-- art may need a reload (handler reload = skin, replace).
function M:RestoreMap()
	self:CloseMinimapOverlay(true)
	self:StopPingNames()
	self:PaintSkinFrame(nil)
	if self.holder then
		if E:IsVisibilityAttached(self.holder) then E:DetachVisibility(self.holder) end
		self.holder:Hide()
	end
	self:SkinBlizzardMinimap(false)
	if saved[Minimap] then
		anchoring = true
		Restore(Minimap)
		anchoring = false
	end
	if self.masked then
		self.masked = false
		masking = true
		Minimap:SetMaskTexture(BLIZZARD_MASK)
		if HybridMinimap and HybridMinimap.CircleMask then HybridMinimap.CircleMask:SetTexture(ROUND_MASK) end
		masking = false
		Redraw()
	end
	for _, part in ipairs(ClusterArt()) do Restore(part) end
	for _, region in ipairs({ MinimapCompassTexture, MinimapCompassTextureUnderlay }) do
		if Usable(region) then region:SetAlpha(1) end
	end
	if MinimapCluster then
		anchoring = true
		Restore(MinimapCluster, true)
		anchoring = false
	end
	Minimap:EnableMouseWheel(true)
	self.mode, self.skinned, self.clusterMoved = nil, nil, nil
	if self.overlay then
		self.improved = false
		self.overlay:Hide()
	end
end

---------------------------------------------------------------------------
-- Element "minimap-buttons"
---------------------------------------------------------------------------
local buttonBoxes = {}

-- The button art the skin lays flat: Forever's state and glow textures, and
-- with `allArt` (the addon compartment, whose round button art only frames
-- its count) the normal, pushed and highlight art too. The count stays.
local function FlattenOwnArt(frame, on, allArt)
	FlattenButtonArt(frame, on)
	if not allArt then return end
	for _, getter in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture" }) do
		local texture = type(frame[getter]) == "function" and frame[getter](frame)
		if texture then FlattenTexture(texture, on) end
	end
end

-- The compartment's count in the EldoUI font while it sits on the box; the
-- game's own font, size and shadow come back with its art.
local countFonts = setmetatable({}, { __mode = "k" })
local function CountFont(text, on)
	if not (Usable(text) and text.GetFont) then return end
	local old = countFonts[text]
	if on then
		if not old then
			local font, size, flags = text:GetFont()
			local sx, sy = text:GetShadowOffset()
			old = { font = font, size = size, flags = flags, sx = sx, sy = sy, shadow = { text:GetShadowColor() } }
			countFonts[text] = old
		end
		E:SetFont(text, E.tokens.size.small)
	elseif old then
		countFonts[text] = nil
		if old.font then text:SetFont(old.font, old.size, old.flags or "") end
		if old.sx then text:SetShadowOffset(old.sx, old.sy) end
		if old.shadow[1] then text:SetShadowColor(unpack(old.shadow)) end
	end
end

-- An EldoUI box behind a Blizzard minimap button (tracking, calendar, addon
-- compartment) while the buttons are skinned. The calendar keeps its own
-- icon (its state art, the only icon Forever gives it) over the box; the
-- compartment shows its count on the box.
local function SkinButton(frame, on, allArt)
	if not Usable(frame) then return end
	-- The compartment's count is its content: without one its art stays.
	allArt = allArt and Usable(frame.Text) and true or false
	local box = buttonBoxes[frame]
	if on then
		if not box then
			box = CreateFrame("Frame", nil, frame)
			box:SetPoint("TOPLEFT", 1, -1)
			box:SetPoint("BOTTOMRIGHT", -1, 1)
			box:SetFrameLevel(math.max(frame:GetFrameLevel() - 1, 0))
			buttonBoxes[frame] = box
		end
		E:SetTemplate(box, true)
		box:Show()
		if frame.Background then frame.Background:SetAlpha(0) end
		if frame ~= GameTimeFrame then FlattenOwnArt(frame, true, allArt) end
		if allArt then CountFont(frame.Text, true) end
		-- Forever's tracking button draws its icon inside its round button
		-- art. The art goes flat and the box shows the plain tracking icon.
		local button = frame.Button
		if Usable(button) and Usable(button.StateTexture) then
			FlattenButtonArt(button, true)
			if not box.icon then
				box.icon = box:CreateTexture(nil, "ARTWORK")
				box.icon:SetPoint("TOPLEFT", 1, -1)
				box.icon:SetPoint("BOTTOMRIGHT", -1, 1)
				E:SetClientAtlas(box.icon, "UI-HUD-Minimap-Tracking-Up", E.UIKit and E.UIKit.GLYPHS and E.UIKit.GLYPHS.dot)
			end
			box.icon:Show()
		end
	elseif box then
		box:Hide()
		if frame.Background then frame.Background:SetAlpha(1) end
		FlattenButtonArt(frame.Button, false)
		FlattenOwnArt(frame, false, true)
		CountFont(frame.Text, false)
	end
end
M.SkinMinimapButton = SkinButton

-- The active tracking ability (its name and icon), or nil: the first active
-- spell in the game's tracking list. Town tracking (not a spell) is not one.
local function ActiveTracking()
	local C = C_Minimap
	if not (C and C.GetNumTrackingTypes and C.GetTrackingInfo) then return nil end
	local count = C.GetNumTrackingTypes()
	if E.Secret(count) or type(count) ~= "number" then return nil end
	for index = 1, count do
		local info = C.GetTrackingInfo(index)
		if type(info) == "table" and not E.Secret(info.active) and info.active == true
			and not E.Secret(info.name) and not E.Secret(info.texture)
			and (info.type == "spell" or (info.type == nil and info.spellID)) then
			return info.name, info.texture
		end
	end
	return nil
end
M.ActiveTracking = ActiveTracking

-- The flat tracking box: the active ability's icon, or the plain tracking
-- glyph a little dimmed while nothing is tracked. Display only: the button
-- still opens the game's own menu.
function M:UpdateTrackingIcon()
	local frame = MinimapCluster and MinimapCluster.Tracking
	local box = frame and buttonBoxes[frame]
	if not (box and box.icon) then return end
	local name, texture
	local wanted = self.active and self.db.trackingIcon ~= false
	if wanted then name, texture = ActiveTracking() end
	if texture then
		box.icon:SetTexture(texture)
		E:TrimIcon(box.icon)
		box.icon:SetAlpha(1)
	else
		E:SetClientAtlas(box.icon, "UI-HUD-Minimap-Tracking-Up", E.UIKit and E.UIKit.GLYPHS and E.UIKit.GLYPHS.dot)
		box.icon:SetAlpha(wanted and 0.6 or 1)
	end
	self.trackingName = name
	-- The tooltip names it: "Tracking: Find Herbs".
	local button = frame.Button
	if Usable(button) and not box.tipHooked then
		box.tipHooked = true
		button:HookScript("OnEnter", function(hovered)
			if not (M.trackingName and box:IsShown() and GameTooltip:IsOwned(hovered)) then return end
			E.UIKit.TipText(GameTooltip, L["Tracking: %s"]:format(M.trackingName))
			GameTooltip:Show()
		end)
	end
end
-- Read-only: the EldoUI box behind a skinned Blizzard minimap button.
function M:ButtonBox(frame) return buttonBoxes[frame] end

-- The Blizzard buttons the minimap buttons skin puts on a box.
local function SkinButtons(on)
	SkinButton(MinimapCluster and MinimapCluster.Tracking, on)
	SkinButton(GameTimeFrame, on)
	SkinButton(AddonCompartmentFrame, on, true)
end

---------------------------------------------------------------------------
-- The stopwatch as a compact EldoUI timer: one row on a flat chip, the
-- digits on the left and start/pause and reset on the right, both on the
-- row's middle. Blizzard's title tab still fades in while you point at the
-- timer; it becomes a slim strip on top of the chip with the title and
-- the close button. Blizzard keeps every script: clicks, dragging, the
-- tab's fade and the timing itself stay the game's own.
---------------------------------------------------------------------------
local Stopwatch = { PAD = 6, GAP = 4, ICON_INSET = 3, tips = setmetatable({}, { __mode = "k" }) }

function Stopwatch.TipEnter(button)
	local tip = Stopwatch.tips[button]
	if not tip then return end
	local Kit = E.UIKit
	Kit.AnchorTooltip(button)
	Kit.TipTitle(GameTooltip, tip[1])
	Kit.TipText(GameTooltip, tip[2])
	GameTooltip:Show()
end

function Stopwatch.TipLeave(button)
	if Stopwatch.tips[button] and GameTooltip:IsOwned(button) then GameTooltip_Hide() end
end

-- The digit size: the display size of the type ramp where the theme has
-- one, else the dialog title size.
function Stopwatch.DigitSize()
	return E.tokens.size.display or E.tokens.size.dialogTitle
end

function Stopwatch.Build()
	if Stopwatch.parts then return Stopwatch.parts end
	local frame = StopwatchFrame
	local parts = {}
	-- Blizzard's own width, so the chip never gets narrower than the timer was.
	parts.width = frame:GetWidth() or 0
	E:StripTextures(frame)
	parts.chip = CreateFrame("Frame", nil, frame)
	parts.chip:SetFrameLevel(math.max(frame:GetFrameLevel() - 1, 0))
	E:SetPanelTemplate(parts.chip)
	E:SetWindowEdge(parts.chip)
	-- The widest time the timer shows, measured in the digit font.
	parts.probe = parts.chip:CreateFontString(nil, "ARTWORK")
	parts.probe:Hide()
	local tab = StopwatchTabFrame
	if Usable(tab) then
		E:StripTextures(tab)
		-- The strip is part of the tab, so it fades in and out with it.
		parts.strip = CreateFrame("Frame", nil, tab)
		parts.strip:SetFrameLevel(math.max(tab:GetFrameLevel() - 1, 0))
		E:SetPanelTemplate(parts.strip)
		E:SetWindowEdge(parts.strip)
	end
	local tips = {
		{ StopwatchPlayPauseButton, L["Start or pause"], L["Starts the stopwatch, or pauses it while it runs."] },
		{ StopwatchResetButton, L["Reset"], L["Sets the stopwatch back to zero."] },
	}
	for _, tip in ipairs(tips) do
		local button = tip[1]
		if Usable(button) then
			-- The box is the button's hit rect; the game's icon stays, in
			-- the body ink, so start, pause and reset still read as they did.
			E:SkinButton(button, { keepTextures = true })
			local highlight = button.GetHighlightTexture and button:GetHighlightTexture()
			if highlight then highlight:SetAlpha(0) end
			-- A tooltip naming the action (kept here, never on Blizzard's button).
			Stopwatch.tips[button] = { tip[2], tip[3] }
			button:HookScript("OnEnter", Stopwatch.TipEnter)
			button:HookScript("OnLeave", Stopwatch.TipLeave)
		end
	end
	-- A theme or text size change re-measures the row.
	E:RegisterThemed(frame, function() Stopwatch.Layout() end)
	Stopwatch.parts = parts
	return parts
end

-- An icon inside its box in the body ink, whatever texture the game gives
-- it (start and pause swap theirs).
function Stopwatch.Ink(texture)
	if not texture then return end
	local inset = Stopwatch.ICON_INSET
	texture:ClearAllPoints()
	texture:SetPoint("TOPLEFT", inset, -inset)
	texture:SetPoint("BOTTOMRIGHT", -inset, inset)
	texture:SetDesaturated(true)
	texture:SetVertexColor(unpack(E.tokens.text.body))
end

function Stopwatch.Layout()
	local parts, frame = Stopwatch.parts, StopwatchFrame
	if not (parts and Usable(frame)) then return end
	local scale = E:TextScale()
	local pad, gap = Stopwatch.PAD, Stopwatch.GAP
	local digits = Stopwatch.DigitSize()
	local probe = parts.probe
	E:SetWindowFont(probe, digits)
	probe:SetText("00:00:00")
	local digitWidth = math.ceil(probe:GetStringWidth() or 0)
	-- Row height: the large button height, more with Large text.
	local height = math.max(E.tokens.height.buttonLarge, math.ceil(digits * scale) + 2 * gap)
	local box = height - 2 * gap
	frame:SetWidth(math.max(parts.width, pad + digitWidth + 2 * gap + 2 * box + gap + pad))
	if (frame:GetHeight() or 0) < height then frame:SetHeight(height) end

	local chip = parts.chip
	chip:ClearAllPoints()
	chip:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
	chip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
	chip:SetHeight(height)

	-- Reset at the right end, start/pause left of it.
	local anchor, offset = chip, -pad
	for _, button in ipairs({ StopwatchResetButton, StopwatchPlayPauseButton }) do
		if Usable(button) then
			button:SetSize(box, box)
			button:ClearAllPoints()
			button:SetPoint("RIGHT", anchor, anchor == chip and "RIGHT" or "LEFT", offset, 0)
			Stopwatch.Ink(button:GetNormalTexture())
			Stopwatch.Ink(button:GetPushedTexture())
			anchor, offset = button, -gap
		end
	end

	-- The digits read left to right from the chip's left edge.
	local ticker = StopwatchTicker
	if Usable(ticker) then
		ticker:ClearAllPoints()
		ticker:SetPoint("LEFT", chip, "LEFT", pad, 0)
		ticker:SetSize(digitWidth, height)
		local previous
		for _, fs in ipairs({ StopwatchTickerHour, StopwatchTickerMinute, StopwatchTickerSecond }) do
			if Usable(fs) then
				E:SetWindowFont(fs, digits)
				fs:SetTextColor(unpack(E.tokens.text.body))
				fs:ClearAllPoints()
				fs:SetPoint("LEFT", previous or ticker, previous and "RIGHT" or "LEFT", 0, 0)
				previous = fs
			end
		end
	end

	local strip = parts.strip
	if not strip then return end
	local stripHeight = math.max(E.tokens.height.row, math.ceil(E.tokens.size.label * scale) + 2 * gap)
	strip:ClearAllPoints()
	strip:SetPoint("BOTTOMLEFT", chip, "TOPLEFT", 0, -E.pixel)
	strip:SetPoint("BOTTOMRIGHT", chip, "TOPRIGHT", 0, -E.pixel)
	strip:SetHeight(stripHeight)
	local close = StopwatchCloseButton
	if Usable(close) then
		-- As tall as the strip; sized before the skin, which fits the hit
		-- rect to the size it finds.
		close:SetSize(stripHeight, stripHeight)
		if not parts.closeSkinned then
			E:SkinCloseButton(close)
			parts.closeSkinned = true
		end
		close:ClearAllPoints()
		close:SetPoint("RIGHT", strip, "RIGHT", 0, 0)
	end
	local title = StopwatchTitle
	if Usable(title) then
		E:SetWindowFont(title, E.tokens.size.label)
		title:SetTextColor(unpack(E.tokens.text.secondary))
		title:SetJustifyH("LEFT")
		title:ClearAllPoints()
		title:SetPoint("LEFT", strip, "LEFT", pad, 0)
		if Usable(close) then title:SetPoint("RIGHT", close, "LEFT", -gap, 0) end
	end
end

-- Read-only: the chip behind the stopwatch row and its title strip.
function M:StopwatchChip() return Stopwatch.parts and Stopwatch.parts.chip end
function M:StopwatchStrip() return Stopwatch.parts and Stopwatch.parts.strip end

function M:SkinTimeManager()
	if not E:BlizzardAllowed(BUTTONS, "skin") then return end
	if Usable(TimeManagerFrame) and E.SkinPanel then E:SkinPanel(TimeManagerFrame) end
	if Usable(StopwatchFrame) then
		Stopwatch.Build()
		-- Blizzard's timer art stays out of sight on every pass.
		E:StripTextures(StopwatchFrame)
		if Usable(StopwatchTabFrame) then E:StripTextures(StopwatchTabFrame) end
		Stopwatch.Layout()
	end
	if Usable(TimeManagerClockTicker) then E:SetFont(TimeManagerClockTicker, self.db.textSize) end
end

function M:ApplyButtons()
	if self:RefreshMinimapOverlay() then return end
	local db = self.db
	local allowed = E:BlizzardAllowed(BUTTONS)
	self.buttonsMoved = allowed and E:BlizzardAllowed(BUTTONS, "move")
	local hideOn = allowed and E:BlizzardAllowed(BUTTONS, "hide")
	local skinOn = allowed and E:BlizzardAllowed(BUTTONS, "skin")
	if not allowed then return end
	if self.buttonsMoved and not self.overlay then self:CreateOverlay() end
	for _, key in ipairs(BUTTON_KEYS) do
		local position = db.buttons[key]
		for _, frame in ipairs(ButtonFrames(key)) do
			if Usable(frame) then
				if position == "hide" and hideOn then
					if key == "clock" then FadePart(frame) else HidePart(frame) end
				elseif self.buttonsMoved and Placed(position) then
					Remember(frame)
					E:UnhideBlizzardFrame(frame, saved[frame].parent)
					frame:SetAlpha(saved[frame].alpha)
					frame:SetParent(self.overlay)
					frame:SetScale(db.iconScale)
					frame:SetFrameLevel(self.overlay:GetFrameLevel() + 2)
				else
					Restore(frame, true)
				end
			end
		end
	end
	SkinButtons(skinOn)
	if skinOn then self:UpdateTrackingIcon() end
	self:HookButtonMoves()
	E:OnBlizzardAddOn("Blizzard_TimeManager", function()
		if M.active then M:SkinTimeManager() end
	end)
	-- Blizzard's clock button is created when Blizzard_TimeManager loads.
	if not self.timeManagerHooked then
		self.timeManagerHooked = true
		E:OnBlizzardAddOn("Blizzard_TimeManager", function()
			if M.active and E:BlizzardAllowed(BUTTONS) then E:RunOutOfCombat(function() M:ApplyButtons() end, "minimap:buttons") end
		end)
	end
	self:ApplyBin()
	self:LayoutCorners()
	self:ApplyVisibility() -- the bin may be new: watch it too
end

-- Blizzard moves some buttons back on its own: Edit Mode's "header
-- underneath" re-anchors the mail icon and the addon compartment, and the
-- event button comes and goes with the event. The corners are placed again
-- after each.
local function Relayout()
	if not (M.active and M.buttonsMoved) then return end
	E:RunOutOfCombat(function()
		if M.active and M.buttonsMoved then M:LayoutCorners() end
	end, "minimap:corners")
end

function M:HookButtonMoves()
	local cluster = MinimapCluster
	if not self.headerHooked and Usable(cluster) and type(cluster.SetHeaderUnderneath) == "function" then
		self.headerHooked = true
		hooksecurefunc(cluster, "SetHeaderUnderneath", Relayout)
	end
	local event = MinimapBackdrop and MinimapBackdrop.ExternalEventURLButton
	if not self.eventHooked and Usable(event) and event.HookScript then
		self.eventHooked = true
		event:HookScript("OnShow", Relayout)
		event:HookScript("OnHide", Relayout)
	end
end

function M:RestoreButtons()
	self.buttonsMoved = false
	for _, key in ipairs(BUTTON_KEYS) do
		for _, frame in ipairs(ButtonFrames(key)) do
			if Usable(frame) then Restore(frame, true) end
		end
	end
	SkinButtons(false)
	self:ReleaseButtons()
	self:LayoutCorners()
end

---------------------------------------------------------------------------
-- Button bin: addon minimap buttons gathered behind one button, or as a
-- strip next to the map. Only addon buttons; Blizzard's are placed above.
-- A button its addon hides stays hidden and takes no place in the bin; a
-- button the player keeps on the map ("Manage buttons") stays with its
-- addon. While another addon that gathers minimap buttons is loaded, the
-- bin stands back and leaves every button to it.
---------------------------------------------------------------------------
local binned = {}       -- addon button -> { parent, points, scale }
local binOrder = {}
local binHooked = {}    -- addon button -> true once its hooks are in (hooks can't be removed)
local placing = false
local railHeld = {}     -- addon button -> true while it sits on the rail
local Bin = {
	-- Blizzard's own parts by name: never addon buttons, wherever they sit.
	BLIZZARD = { MinimapBackdrop = true, MiniMapPing = true, MinimapNorthTag = true,
		ExpansionLandingPageMinimapButton = true, GarrisonLandingPageMinimapButton = true, QueueStatusMinimapButton = true },
	-- Every addon button found so far, gathered or kept on the map: name -> button.
	seen = {},
	-- Between the map and the open bin.
	GAP = 4,
	NAME = "EldoUI_ButtonBin",
}

-- Other addons that gather the minimap buttons in one place make the bin
-- stand back while one is loaded (Data/Competitors.lua), so the two never
-- fight over a button.
-- The title of the addon that gathers the buttons instead, or nil.
function Bin.StandsBack()
	local back, addon, title = E:StandsBack("Minimap", "buttonbin")
	if back then return title or addon end
end

-- Blizzard's own minimap buttons, as EldoUI places them.
function Bin.Native()
	local set = {}
	for _, key in ipairs(BUTTON_KEYS) do
		for _, frame in ipairs(ButtonFrames(key)) do set[frame] = true end
	end
	for _, frame in ipairs(ButtonFrames("queue")) do set[frame] = true end
	return set
end

local function IsAddonButton(child, native)
	if not Usable(child) or child:GetObjectType() ~= "Button" then return false end
	if E.FrameCheck(child, "IsProtected") then return false end
	if native and native[child] then return false end
	local name = child:GetName()
	if not name or Bin.BLIZZARD[name] then return false end
	return (name:find("^LibDBIcon10_") or name:find("MinimapButton$") or name:find("MinimapIcon$") or name:find("_Minimap$")) and true or false
end

-- A button the player adds by name: any addon button, but never a
-- protected frame, one of Blizzard's own (a global the game's own code
-- made) or one of EldoUI's. Returns true, or false and the reason.
function Bin.Addable(frame, native)
	if not Usable(frame) or frame:GetObjectType() ~= "Button" then return false, L["That frame is not a button."] end
	if E.FrameCheck(frame, "IsProtected") then return false, L["That button is protected, so it stays where the game put it."] end
	local name = frame:GetName()
	local own = not name or Bin.BLIZZARD[name] or (native and native[frame]) or name:find("^EldoUI")
	if not own and issecurevariable then
		local ok, secure = pcall(issecurevariable, name)
		own = ok and secure
	end
	if own then return false, L["That is one of the game's or EldoUI's own buttons."] end
	return true
end

-- The short name of a button for the "Manage buttons" list: the addon's
-- name where the frame name carries it.
function Bin.Title(name)
	local short = name:match("^LibDBIcon10_(.+)$") or name:match("^(.-)_?MinimapButton$")
		or name:match("^(.-)_?MinimapIcon$") or name:match("^(.-)_Minimap$")
	if not short or short == "" then return name end
	return short
end

function Bin.Icons()
	return _G.LibStub and _G.LibStub("LibDBIcon-1.0", true)
end

-- Addon buttons on the map, on the map's backdrop, and the ones LibDBIcon
-- made (some addons keep theirs elsewhere), each once.
function Bin.Candidates()
	local list, found, native = {}, {}, Bin.Native()
	local function Add(frame)
		if frame and not found[frame] and IsAddonButton(frame, native) then
			found[frame] = true
			list[#list + 1] = frame
		end
	end
	-- EldoUI's own button first, so it leads the bin.
	if M.badge and M.db and M.db.badge then
		found[M.badge] = true
		list[1] = M.badge
	end
	for _, child in ipairs({ Minimap:GetChildren() }) do Add(child) end
	if Usable(MinimapBackdrop) then
		for _, child in ipairs({ MinimapBackdrop:GetChildren() }) do Add(child) end
	end
	local icons = Bin.Icons()
	if icons and type(icons.GetButtonList) == "function" then
		local ok, names = pcall(icons.GetButtonList, icons)
		for _, name in ipairs(ok and type(names) == "table" and names or {}) do
			local button
			if type(icons.GetMinimapButton) == "function" then
				local got, value = pcall(icons.GetMinimapButton, icons, name)
				if got then button = value end
			end
			Add(button)
		end
	end
	-- Buttons the player added by name, whatever their frame name says.
	for name in pairs(M.db and M.db.binInclude or {}) do
		local frame = _G[name]
		if frame and not found[frame] and Bin.Addable(frame, native) then
			found[frame] = true
			list[#list + 1] = frame
		end
	end
	return list
end

-- The gathered buttons their addons show right now.
function Bin.Visible()
	local list = {}
	for _, button in ipairs(binOrder) do
		if button:IsShown() then list[#list + 1] = button end
	end
	return list
end

-- An addon showed or hid one of its buttons, or moved it: the bin is laid
-- out again once, on the next frame.
function Bin.Queue()
	Bin.refreshPending = true
	if Bin.queued then return end
	Bin.queued = true
	C_Timer.After(0, function()
		Bin.queued = false
		if M.active and M.db.binMode ~= "off" and #binOrder > 0 then
			E:RunOutOfCombat(function() M:RefreshBin() end, "minimap:bin")
		end
	end)
end

-- Escape closes the open drawer (the game's list of frames Escape
-- closes); the strip next to the map stays.
function Bin.Escape(on)
	local list = UISpecialFrames
	if type(list) ~= "table" then return end
	local at
	for index, name in ipairs(list) do
		if name == Bin.NAME then at = index break end
	end
	if on and not at then
		table.insert(list, Bin.NAME)
	elseif not on and at then
		table.remove(list, at)
	end
end

-- Automatic side: beside the map toward the middle of the screen where
-- the bin fits there, else under the map (over it on a map near the
-- bottom), on the map's inner edge. Returns point, relative point, x, y.
function Bin.AutoPoint(anchor, bin)
	local gap = Bin.GAP
	local l, r, t, b = anchor:GetLeft(), anchor:GetRight(), anchor:GetTop(), anchor:GetBottom()
	local sw, sh = UIParent:GetWidth() or 0, UIParent:GetHeight() or 0
	if not (l and r and t and b) or sw <= 0 then return "TOPRIGHT", "BOTTOMRIGHT", 0, -gap end
	local scale = (anchor:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
	l, r, t, b = l * scale, r * scale, t * scale, b * scale
	local w = bin:GetWidth() or 0
	local right = (l + r) / 2 > sw / 2
	local top = (t + b) / 2 > sh / 2
	local edge = top and "TOP" or "BOTTOM"
	if right and l - gap - w >= 0 then return edge .. "RIGHT", edge .. "LEFT", -gap, 0 end
	if not right and r + gap + w <= sw then return edge .. "LEFT", edge .. "RIGHT", gap, 0 end
	local side = right and "RIGHT" or "LEFT"
	if top then return "TOP" .. side, "BOTTOM" .. side, 0, -gap end
	return "BOTTOM" .. side, "TOP" .. side, 0, gap
end

function M:CreateBin()
	local toggle = CreateFrame("Button", nil, Minimap)
	toggle:SetSize(18, 18)
	E:SetTemplate(toggle)
	toggle.text = E:CreateText(toggle, E.tokens.size.label)
	toggle.text:SetPoint("CENTER")
	toggle.text:SetText("...")
	local bin = CreateFrame("Frame", Bin.NAME, UIParent)
	bin:SetFrameStrata("HIGH")
	bin:SetClampedToScreen(true)
	E:SetPanelTemplate(bin)
	bin:Hide()
	toggle:SetScript("OnEnter", function(b)
		b:SetBackdropBorderColor(unpack(E.media.accentColor))
		if M.db.binMode == "hover" then
			M:OpenBin(true)
		else
			GameTooltip:SetOwner(b, "ANCHOR_LEFT")
			GameTooltip:SetText(L["Addon buttons"])
			GameTooltip:Show()
		end
	end)
	toggle:SetScript("OnLeave", function(b)
		b:SetBackdropBorderColor(unpack(E.media.borderColor))
		GameTooltip_Hide()
		if M.db.binMode == "hover" then M:CloseBinLater() end
	end)
	toggle:SetScript("OnClick", function(clicked, button)
		if E:IsOptionsLinkClick(clicked, button) then return end
		if M.db.binMode == "drawer" or M.db.binMode == "rail" then M:OpenBin(not bin:IsShown()) end
	end)
	bin:SetScript("OnLeave", function()
		if M.db.binMode == "hover" then M:CloseBinLater() end
	end)
	-- A click anywhere but the open drawer and its toggle closes it.
	bin:SetScript("OnShow", function(frame) frame:RegisterEvent("GLOBAL_MOUSE_DOWN") end)
	bin:SetScript("OnHide", function(frame)
		frame:UnregisterEvent("GLOBAL_MOUSE_DOWN")
		-- Escape closed the drawer: remembered as closed.
		if not Bin.quiet and M.db.binMode == "drawer" then M.db.binOpen = false end
	end)
	bin:SetScript("OnEvent", function(frame)
		if M.db.binMode == "bar" or frame:IsMouseOver() or toggle:IsMouseOver() then return end
		M:OpenBin(false)
	end)
	bin:EnableMouse(true)
	E:BindOptionsLink(toggle, { page = "module:Minimap", key = "binMode" })
	self.bin, self.binToggle = bin, toggle
end

function M:OpenBin(open)
	local bin = self.bin
	if not bin then return end
	if open then
		self:CollectButtons(true)
		if #Bin.Visible() == 0 then return end
	end
	if self.db.binMode == "drawer" then self.db.binOpen = open and true or false end
	if open and not bin:IsShown() then
		-- The map may have moved since the bin was laid out.
		self:PlaceBin()
		E:SlideIn(bin, "UP")
	elseif not open and bin:IsShown() then
		E:SlideOut(bin, "UP")
	end
end

-- Hover drawer: close once the mouse has left both the toggle and the bin.
function M:CloseBinLater()
	if self.binCloseTimer then self.binCloseTimer:Cancel() end
	self.binCloseTimer = C_Timer.NewTimer(0.4, function()
		self.binCloseTimer = nil
		if not self.bin or self.db.binMode ~= "hover" then return end
		if self.bin:IsMouseOver() or self.binToggle:IsMouseOver() then return self:CloseBinLater() end
		self:OpenBin(false)
	end)
end

-- With a growth picked, the bin hangs from the side of its anchor (the
-- toggle's own mover, or the map) the growth points to: the bin's point,
-- the anchor's point and the gap's direction.
local GROW_POINT = {
	RIGHTDOWN = { "TOPLEFT", "BOTTOMLEFT", 0, -1 }, LEFTDOWN = { "TOPRIGHT", "BOTTOMRIGHT", 0, -1 },
	RIGHTUP = { "BOTTOMLEFT", "TOPLEFT", 0, 1 }, LEFTUP = { "BOTTOMRIGHT", "TOPRIGHT", 0, 1 },
	DOWNRIGHT = { "TOPLEFT", "TOPRIGHT", 1, 0 }, DOWNLEFT = { "TOPRIGHT", "TOPLEFT", -1, 0 },
	UPRIGHT = { "BOTTOMLEFT", "BOTTOMRIGHT", 1, 0 }, UPLEFT = { "BOTTOMRIGHT", "BOTTOMLEFT", -1, 0 },
}

-- The growth's side of the anchor, or the opposite side where the bin
-- would leave the screen there (a toggle at the bottom edge opens its
-- downward bin upward); along that side it lines up with the anchor's
-- other edge where it would run off the screen. Returns point,
-- relative point, x, y.
function Bin.GrowPoint(key, anchor, bin)
	local grow, gap = GROW_POINT[key], Bin.GAP
	local point, relative, gx, gy = grow[1], grow[2], grow[3], grow[4]
	local l, r, t, b = anchor:GetLeft(), anchor:GetRight(), anchor:GetTop(), anchor:GetBottom()
	local sw, sh = UIParent:GetWidth() or 0, UIParent:GetHeight() or 0
	if l and r and t and b and sw > 0 then
		local scale = (anchor:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
		l, r, t, b = l * scale, r * scale, t * scale, b * scale
		local w, h = bin:GetWidth() or 0, bin:GetHeight() or 0
		local Swap = function(text, a, z) return (text:gsub(a, "#"):gsub(z, a):gsub("#", z)) end
		if gy ~= 0 then
			if (gy < 0 and b - gap - h < 0) or (gy > 0 and t + gap + h > sh) then
				point, relative, gy = Swap(point, "TOP", "BOTTOM"), Swap(relative, "TOP", "BOTTOM"), -gy
			end
			if (point:find("LEFT") and l + w > sw) or (point:find("RIGHT") and r - w < 0) then
				point, relative = Swap(point, "LEFT", "RIGHT"), Swap(relative, "LEFT", "RIGHT")
			end
		else
			if (gx > 0 and r + gap + w > sw) or (gx < 0 and l - gap - w < 0) then
				point, relative, gx = Swap(point, "LEFT", "RIGHT"), Swap(relative, "LEFT", "RIGHT"), -gx
			end
			if (point:find("TOP") and t - h < 0) or (point:find("BOTTOM") and b + h > sh) then
				point, relative = Swap(point, "TOP", "BOTTOM"), Swap(relative, "TOP", "BOTTOM")
			end
		end
	end
	return point, relative, gx * gap, gy * gap
end

-- What the bin opens from: the toggle's own mover, or the map.
function M:BinAnchorFrame()
	if self.binFree and self.binHolder and self.binHolder:IsShown() then return self.binHolder end
	return self.holder and self.holder:IsShown() and self.holder or Minimap
end

-- Where the bin opens: the way the growth points, or (Automatic) below
-- the map, left of it, or toward the middle of the screen
-- (Bin.AutoPoint). It never leaves the screen.
function M:PlaceBin()
	local bin = self.bin
	if not bin then return end
	local anchor = self:BinAnchorFrame()
	local side, gap = self.db.binSide, Bin.GAP
	bin:ClearAllPoints()
	if GROW_POINT[self.db.binGrow] then
		local point, relative, x, y = Bin.GrowPoint(self.db.binGrow, anchor, bin)
		bin:SetPoint(point, anchor, relative, x, y)
	elseif self.binFree then
		local point, relative, x, y = Bin.AutoPoint(anchor, bin)
		bin:SetPoint(point, anchor, relative, x, y)
	elseif side == "LEFT" then
		bin:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -gap, 0)
	elseif side == "AUTO" then
		local point, relative, x, y = Bin.AutoPoint(anchor, bin)
		bin:SetPoint(point, anchor, relative, x, y)
	else
		bin:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -gap)
	end
end

-- Growth (binGrow): the way a row fills, then the way the next row goes.
-- RIGHTDOWN fills left to right and wraps downward (the drawer's own
-- order, also what Automatic uses); DOWNRIGHT fills a column downward
-- and wraps to the right.
local GROW = {
	RIGHTDOWN = { "RIGHT", "DOWN" }, RIGHTUP = { "RIGHT", "UP" }, LEFTDOWN = { "LEFT", "DOWN" }, LEFTUP = { "LEFT", "UP" },
	DOWNRIGHT = { "DOWN", "RIGHT" }, DOWNLEFT = { "DOWN", "LEFT" }, UPRIGHT = { "UP", "RIGHT" }, UPLEFT = { "UP", "LEFT" },
}
Bin.GROW = GROW

-- The corner of the bin the first button sits in, the horizontal and
-- vertical way the buttons go, and whether a line is a row.
function Bin.Start(key)
	local grow = GROW[key] or GROW.RIGHTDOWN
	local fill, wrap = grow[1], grow[2]
	local row = fill == "LEFT" or fill == "RIGHT"
	local h = row and fill or wrap
	local v = row and wrap or fill
	return (v == "DOWN" and "TOP" or "BOTTOM") .. (h == "RIGHT" and "LEFT" or "RIGHT"), h, v, row
end

function M:PlaceBinButtons()
	if not self.bin then return end
	placing = true
	local db = self.db
	local size, per, gap = db.binSize, math.max(1, db.binPerRow), db.binSpacing
	local corner, h, v, row = Bin.Start(db.binGrow)
	local dx, dy = h == "RIGHT" and 1 or -1, v == "DOWN" and -1 or 1
	-- Buttons on the rail are placed by LayoutRail; the rest fill the bin,
	-- without a gap where an addon hid its button.
	local index = 0
	for _, button in ipairs(binOrder) do
		if not railHeld[button] then
			button:SetParent(self.bin)
			if button:IsShown() then
				index = index + 1
				local scale = size / math.max(button:GetWidth(), 1)
				button:SetScale(scale)
				button:ClearAllPoints()
				local along, across = (index - 1) % per, math.floor((index - 1) / per)
				local column, line = along, across
				if not row then column, line = across, along end
				button:SetPoint(corner, self.bin, corner, dx * (4 + column * (size + gap)) / scale, dy * (4 + line * (size + gap)) / scale)
			end
		end
	end
	local lines = math.max(1, math.ceil(index / per))
	local count = math.max(1, math.min(index, per))
	local columns, rows = count, lines
	if not row then columns, rows = lines, count end
	self.bin:SetSize(8 + columns * (size + gap) - gap, 8 + rows * (size + gap) - gap)
	placing = false
	self:PlaceBin()
end

-- The toggle and the strip show only while a gathered button shows.
function M:ShowBinParts(closeDrawer)
	local mode, count = self.db.binMode, #Bin.Visible()
	self.binToggle:SetShown(count > 0 and mode ~= "bar" and mode ~= "rail")
	Bin.quiet = true
	if mode == "bar" then
		self.bin:SetShown(count > 0)
	elseif count == 0 or (closeDrawer and not self.bin:IsMouseOver()) then
		self.bin:Hide()
	end
	Bin.quiet = false
end

-- "Keep the drawer open": after a reload the click drawer opens again if
-- it was open when the player left.
function M:RestoreDrawer()
	local db = self.db
	if not (self.bin and db.binKeepOpen and db.binMode == "drawer" and db.binOpen) then return end
	if #Bin.Visible() > 0 and not self.bin:IsShown() then
		self:PlaceBin()
		self.bin:Show()
	end
end

-- The toggle on its own mover (binMover): a small holder the mover
-- places, by default in the map's bottom-right corner where the toggle
-- sits on the map, so turning it on moves nothing until it is dragged.
function M:BinHolder()
	if not self.binHolder then
		local holder = CreateFrame("Frame", "EldoUI_ButtonBinAnchor", UIParent)
		holder:SetSize(18, 18)
		holder:SetFrameStrata("MEDIUM")
		holder:Hide()
		self.binHolder = holder
		local point = _G.EldoUI_MinimapMover and { "BOTTOMRIGHT", "EldoUI_MinimapMover", "BOTTOMRIGHT", -4, 4 }
			or { "TOPRIGHT", "UIParent", "TOPRIGHT", -24, -260 }
		E:CreateMover(holder, "EldoUI_ButtonBinAnchor", L["Addon buttons"], point, { followShown = true, sample = false })
	end
	return self.binHolder
end

function M:PlaceToggle()
	local toggle = self.binToggle
	if not toggle then return end
	local mode = self.db.binMode
	local free = self.db.binMover and mode ~= "off" and mode ~= "rail"
	self.binFree = free and true or false
	if free then
		local holder = self:BinHolder()
		holder:Show()
		if toggle:GetParent() ~= holder then toggle:SetParent(holder) end
		toggle:ClearAllPoints()
		toggle:SetPoint("CENTER", holder, "CENTER")
	else
		if self.binHolder then self.binHolder:Hide() end
		if toggle:GetParent() ~= Minimap then toggle:SetParent(Minimap) end
	end
end

-- After an addon showed, hid or moved one of its gathered buttons.
function M:RefreshBin()
	if Bin.collectPending then
		Bin.refreshPending = true
		return self:CollectButtons(Bin.collectPending == "discovery")
	end
	Bin.refreshPending = nil
	if not self.bin then return end
	self:PlaceBinButtons()
	self:ShowBinParts(false)
	self:LayoutCorners()
end

-- Back to where a button was before the bin took it: parent, scale and
-- points. LibDBIcon buttons are re-placed by LibDBIcon itself (their saved
-- angle on the map edge).
function M:ReleaseButton(button, icons)
	local stored = binned[button]
	if not stored then return end
	binned[button] = nil
	railHeld[button] = nil
	button:SetParent(stored.parent or Minimap)
	button:SetScale(stored.scale or 1)
	button:ClearAllPoints()
	for _, point in ipairs(stored.points or {}) do
		local rel = point[2]
		-- A point on the bin itself (already re-placed once) goes to the map center.
		if rel == self.bin or rel == nil then rel = Minimap end
		button:SetPoint(point[1], rel, point[3], point[4], point[5])
	end
	if not stored.points or #stored.points == 0 then button:SetPoint("CENTER", Minimap, "CENTER") end
	local name = button:GetName()
	local iconName = icons and name and name:match("^LibDBIcon10_(.+)$")
	if iconName and icons.Refresh then pcall(icons.Refresh, icons, iconName) end
	if button == self.badge then self:PlaceBadge() end
end

function M:CollectButtons(discoveryOnly)
	if self.minimapOverlay then
		self:RefreshMinimapOverlay()
		if self.minimapOverlay then return end
	end
	if not self.active or self.db.binMode == "off" or not E:BlizzardAllowed(BUTTONS, "replace") then return end
	if InCombatLockdown() then
		if not discoveryOnly or not Bin.collectPending then
			Bin.collectPending = discoveryOnly and "discovery" or "full"
		end
		E:RunOutOfCombat(function() M:CollectButtons(Bin.collectPending == "discovery") end, "minimap:bin")
		return
	end
	Bin.collectPending = nil
	local refreshPending = Bin.refreshPending
	Bin.refreshPending = nil
	if Bin.StandsBack() then return self:ReleaseButtons() end
	local changed = not self.bin
	if not self.bin then self:CreateBin() end
	local exclude = self.db.binExclude
	-- Buttons the player keeps on the map go back to their addon first.
	local icons = Bin.Icons()
	for index = #binOrder, 1, -1 do
		local button = binOrder[index]
		local name = button:GetName()
		if name and exclude[name] then
			self:ReleaseButton(button, icons)
			table.remove(binOrder, index)
			changed = true
		end
	end
	for _, child in ipairs(Bin.Candidates()) do
		local name = child:GetName()
		Bin.seen[name] = child
		if not binned[child] and not exclude[name] then
			changed = true
			local points = {}
			for i = 1, child:GetNumPoints() do points[i] = { child:GetPoint(i) } end
			binned[child] = { parent = child:GetParent(), points = points, scale = child:GetScale() }
			table.insert(binOrder, child)
			child:SetParent(self.bin)
			if not binHooked[child] then
				binHooked[child] = true
				local function Changed()
					if not placing and binned[child] and M.db.binMode ~= "off" then Bin.Queue() end
				end
				-- The calls, not OnShow and OnHide: those don't run for a
				-- button inside the closed drawer.
				for _, method in ipairs({ "SetPoint", "Show", "Hide", "SetShown" }) do
					hooksecurefunc(child, method, Changed)
				end
			end
		end
	end
	-- EldoUI's own button leads the bin, also when it joined later.
	for index = 2, #binOrder do
		if binOrder[index] == self.badge then
			table.insert(binOrder, 1, table.remove(binOrder, index))
			changed = true
			break
		end
	end
	if discoveryOnly and not changed and not refreshPending then return false end
	self:PlaceToggle()
	self:PlaceBinButtons()
	self:ShowBinParts(not discoveryOnly)
	if not discoveryOnly then self:RestoreDrawer() end
	self:LayoutCorners()
	return changed
end

function M:ReleaseButtons()
	Bin.collectPending, Bin.refreshPending = nil, nil
	local icons = #binOrder > 0 and Bin.Icons()
	for _, button in ipairs(binOrder) do self:ReleaseButton(button, icons) end
	wipe(binOrder)
	if self.bin then
		Bin.quiet = true
		self.bin:Hide()
		Bin.quiet = false
		self.binToggle:Hide()
	end
	self.binFree = false
	if self.binHolder then self.binHolder:Hide() end
end

---------------------------------------------------------------------------
-- EldoUI's own minimap button. It is drawn like the other addon buttons
-- (round border, dark backing, the EldoUI icon in a round cut), so it
-- looks at home among them in the bin, which gathers it first. With the
-- bin off it rides the map's edge, where the player drags it. A click
-- does what the addon compartment entry does.
---------------------------------------------------------------------------
local Badge = {}
M.Badge = Badge

-- The offset of the button's center from the map's center for an angle
-- in degrees: just outside a round map's rim, or on a square map's edge
-- (the corners rounded off, so it never sits on a corner stack's tip).
function Badge.Offset(angle, round, width, height)
	local radians = math.rad(angle or 0)
	local x, y = math.cos(radians), math.sin(radians)
	local w, h = width / 2 + 5, height / 2 + 5
	if round then return x * w, y * h end
	local dw, dh = math.sqrt(2 * w * w) - 10, math.sqrt(2 * h * h) - 10
	return math.max(-w, math.min(x * dw, w)), math.max(-h, math.min(y * dh, h))
end

-- The angle of the cursor around the map's center, in degrees.
function Badge.CursorAngle()
	local cx, cy = Minimap:GetCenter()
	if not cx then return nil end
	local x, y = GetCursorPosition()
	local scale = Minimap:GetEffectiveScale()
	return math.deg(math.atan2(y / scale - cy, x / scale - cx)) % 360
end

function M:PlaceBadge()
	local badge = self.badge
	if not badge or binned[badge] then return end
	if badge:GetParent() ~= Minimap then badge:SetParent(Minimap) end
	local x, y = Badge.Offset(self.db.badgeAngle, self.db.shape == "round", Minimap:GetWidth(), Minimap:GetHeight())
	badge:SetScale(1)
	badge:ClearAllPoints()
	badge:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

function M:CreateBadge()
	local badge = CreateFrame("Button", "EldoUI_MinimapButton", Minimap)
	badge:SetSize(31, 31)
	badge:SetFrameStrata("MEDIUM")
	badge:SetFrameLevel(8)
	badge:RegisterForClicks("AnyUp")
	badge:RegisterForDrag("LeftButton")
	badge:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")
	local back = badge:CreateTexture(nil, "BACKGROUND")
	back:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	back:SetSize(24, 24)
	back:SetPoint("CENTER")
	local icon = badge:CreateTexture(nil, "ARTWORK")
	icon:SetTexture(E.media.icon)
	icon:SetSize(20, 20)
	icon:SetPoint("CENTER")
	local cut = badge:CreateMaskTexture()
	cut:SetTexture(ROUND_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	cut:SetAllPoints(icon)
	icon:AddMaskTexture(cut)
	local ring = badge:CreateTexture(nil, "OVERLAY")
	ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	ring:SetSize(53, 53)
	ring:SetPoint("TOPLEFT")
	badge.icon = icon
	badge:SetScript("OnClick", function(_, button) EldoUI_OnAddonCompartmentClick(nil, button) end)
	badge:SetScript("OnEnter", function(frame) EldoUI_OnAddonCompartmentEnter(nil, frame) end)
	badge:SetScript("OnLeave", function() EldoUI_OnAddonCompartmentLeave() end)
	-- Dragged around the map's edge while it is not in the bin.
	badge:SetScript("OnDragStart", function(frame)
		if binned[frame] then return end
		frame:LockHighlight()
		frame:SetScript("OnUpdate", function()
			local angle = Badge.CursorAngle()
			if angle then
				M.db.badgeAngle = math.floor(angle + 0.5) % 360
				M:PlaceBadge()
			end
		end)
	end)
	badge:SetScript("OnDragStop", function(frame)
		frame:SetScript("OnUpdate", nil)
		frame:UnlockHighlight()
	end)
	self.badge = badge
	return badge
end

-- Shown with its switch on; the bin (when it gathers) picks it up from
-- the map on its next pass.
function M:ApplyBadge()
	local badge = self.badge
	if not self.db.badge then
		if badge then badge:Hide() end
		return
	end
	badge = badge or self:CreateBadge()
	badge:Show()
	self:PlaceBadge()
end

function M:ApplyBin()
	local mode = self.db.binMode
	if mode ~= "off" and E:BlizzardAllowed(BUTTONS, "replace") then
		Bin.Escape(mode ~= "bar")
		self:CollectButtons()
		-- Addons that load late add their buttons later.
		C_Timer.After(3, function() M:CollectButtons() end)
		-- LibDBIcon may come with an addon that loads later: the callback
		-- goes in on the first pass that finds it.
		local icons = not self.ldbHooked and Bin.Icons()
		if icons and icons.RegisterCallback then
			self.ldbHooked = true
			pcall(icons.RegisterCallback, M, "LibDBIcon_IconCreated", function()
				C_Timer.After(0, function() M:CollectButtons() end)
			end)
		end
	else
		Bin.Escape(false)
		self:ReleaseButtons()
	end
end

-- "Manage buttons": every addon button found, gathered or kept on the map.
function Bin.ManageValues()
	local values = { [""] = L["Pick a button"] }
	local exclude = M.db and M.db.binExclude or {}
	for name in pairs(Bin.seen) do
		values[name] = (exclude[name] and L["%s: kept on the map"] or L["%s: in the bin"]):format(Bin.Title(name))
	end
	return E:RawValues(values)
end

-- A pick in "Manage buttons" moves that button between the bin and the map.
function M:TakeManagePick()
	local name = self.db.binManage
	if type(name) ~= "string" or name == "" then return end
	self.db.binManage = ""
	local exclude = self.db.binExclude
	exclude[name] = not exclude[name] or nil
end

-- "Add a button by name": the name typed in, taken at once. The button
-- must be on the screen now; it is gathered again after every reload.
function M:TakeAddName()
	local name = strtrim(self.db.binAdd or "")
	self.db.binAdd = ""
	if name == "" then return end
	local frame = _G[name]
	if type(frame) ~= "table" then
		E:Print(L["No frame named %s is loaded. Check the name; capitals count."]:format(name))
		return false
	end
	local ok, reason = Bin.Addable(frame, Bin.Native())
	if not ok then
		E:Print(reason)
		return false
	end
	self.db.binInclude[name] = true
	self.db.binExclude[name] = nil
	E:Print(L["%s goes in the addon button bin."]:format(name))
	return true
end

-- The bin's state for the header: who gathers the buttons and how many.
function Bin.Status()
	local db = M.db
	if not db or db.binMode == "off" then return nil end
	local back = Bin.StandsBack()
	if back then return L["Gathered by %s"]:format(back) end
	local kept = 0
	for name in pairs(db.binExclude) do
		if Bin.seen[name] then kept = kept + 1 end
	end
	return L["%d in the bin, %d kept on the map"]:format(#binOrder, kept)
end
M.Bin = Bin

---------------------------------------------------------------------------
-- The button rail: buttons set to "On the side rail" (and addon buttons
-- gathered there) sit one under the other on the kit's slim icon rail
-- along the map's left or right edge, each on a slot whose tooltip names
-- it. On a square map the rail runs the map's height (above any docked
-- Info Bar panels); on a round one it is as tall as its buttons and
-- centered on the edge. When the addon buttons don't all fit, the last
-- slot is the "..." toggle and the rest wait in the drawer.
---------------------------------------------------------------------------
M.rails = {}
local railTitles = setmetatable({}, { __mode = "k" }) -- button on the rail -> its name
local railTipHooked = setmetatable({}, { __mode = "k" })

-- A button that shows no tooltip of its own gets one naming it.
local function RailTipEnter(frame)
	local title = railTitles[frame]
	if not title or (GameTooltip:IsOwned(frame) and GameTooltip:NumLines() > 0) then return end
	GameTooltip:SetOwner(frame, M.db.railSide == "RIGHT" and "ANCHOR_LEFT" or "ANCHOR_RIGHT")
	GameTooltip:SetText(title, unpack(E.media.accentColor))
	GameTooltip:Show()
end
local function RailTipLeave(frame)
	if railTitles[frame] and GameTooltip:IsOwned(frame) then GameTooltip_Hide() end
end

local function RailFor(side)
	local rail = M.rails[side]
	if not rail then
		rail = E.UIKit.IconRail(M.overlay, { side = side })
		rail.bg = rail:CreateTexture(nil, "BACKGROUND")
		rail.bg:SetAllPoints()
		M.rails[side] = rail
	end
	local r, g, b = unpack(E.media.backdropColor)
	rail.bg:SetColorTexture(r, g, b, E.tokens.panel.transparentFloor)
	rail:SetFrameLevel(M.overlay:GetFrameLevel() + 1)
	return rail
end

local function RailSlot(rail, key, title)
	local slot = rail.buttons[key]
	if not slot then slot = rail:Add({ key = key, tipTitle = title }) end
	slot.kitTipTitle = title
	return slot
end

-- Put a button on its slot at the rail's button size.
local function OnSlot(frame, slot, rail)
	local size = math.max(frame:GetWidth() or 0, frame:GetHeight() or 0, 1)
	local scale = E.tokens.rail.button / size
	Keep.SetScale(frame, scale)
	Keep.ClearAllPoints(frame)
	Keep.SetPoint(frame, "CENTER", slot, "CENTER", 0, 0)
	frame:SetFrameLevel(rail:GetFrameLevel() + 3)
end

function M:LayoutRail()
	local db = self.db
	local T = E.tokens.rail
	local items = {}
	if self.buttonsMoved and self.overlay then
		for _, key in ipairs(BUTTON_KEYS) do
			if db.buttons[key] == RAIL then
				for index, frame in ipairs(ButtonFrames(key)) do
					if Usable(frame) and frame:GetParent() ~= hider and (key ~= "event" or frame:IsShown()) then
						items[#items + 1] = { key = key .. index, frame = frame, title = L[BUTTON_LABELS[key][1]] }
					end
				end
			end
		end
	end
	local toggle = self.binToggle
	local addons = (db.binMode == "rail" and self.bin) and Bin.Visible() or {}
	local wantToggle = toggle and db.binMode ~= "rail" and db.buttons.bin == RAIL and toggle:IsShown() and not self.binFree
	local side = db.railSide == "RIGHT" and "RIGHT" or "LEFT"
	for _, button in ipairs(binOrder) do railHeld[button] = nil end
	for frame in pairs(railTitles) do railTitles[frame] = nil end
	self.binOnRail = false
	if #items == 0 and #addons == 0 and not wantToggle then
		for _, rail in pairs(self.rails) do rail:Hide() end
		railPad.LEFT, railPad.RIGHT = 0, 0
		if toggle and db.binMode == "rail" then toggle:Hide() end
		return
	end
	for other, rail in pairs(self.rails) do
		if other ~= side then rail:Hide() end
	end
	local rail = RailFor(side)
	local infoBar = E.modules.InfoBar
	local docked = infoBar and infoBar.AttachedHeight and infoBar:AttachedHeight("minimap") or 0
	local round = db.shape == "round"
	local height = (Minimap:GetHeight() or 0) - (round and 0 or docked)
	local capacity = math.max(1, math.floor((height - T.gap) / (T.button + T.gap)))

	-- What goes on the rail, in order: the game's buttons, then the addon
	-- buttons (the last slot is the toggle when they don't all fit).
	local list = {}
	for _, item in ipairs(items) do list[#list + 1] = item end
	local room = capacity - #list
	local overflow = #addons > room
	for index, button in ipairs(addons) do
		if overflow and index >= room then break end
		list[#list + 1] = { key = "addon" .. index, frame = button, title = button:GetName() or L["Addon buttons"], addon = true }
	end
	if (overflow and toggle) or wantToggle then
		list[#list + 1] = { key = "toggle", frame = toggle, title = L["Addon buttons"], toggle = true }
	end
	if toggle and db.binMode == "rail" then toggle:SetShown(overflow) end
	self.binOnRail = (overflow or wantToggle) and true or false

	-- Slots stack in this order, whatever order they were first made in
	-- (a button put on the rail later still takes its own place).
	local used, ordered = {}, {}
	for _, item in ipairs(list) do
		local slot = RailSlot(rail, item.key, item.title)
		slot:Show()
		used[slot] = true
		ordered[#ordered + 1] = slot
	end
	for _, slot in ipairs(rail.order) do
		if not used[slot] then
			slot:Hide()
			ordered[#ordered + 1] = slot
		end
	end
	for index, slot in ipairs(ordered) do rail.order[index] = slot end
	rail:ClearAllPoints()
	if round then
		rail:SetHeight(#list * (T.button + T.gap) + T.gap)
		rail:SetPoint(side, Minimap, side, 0, 0)
	else
		rail:SetPoint("TOP" .. side, Minimap, "TOP" .. side, 0, 0)
		rail:SetPoint("BOTTOM" .. side, Minimap, "BOTTOM" .. side, 0, docked)
	end
	rail:Show()
	rail:Layout()
	placing = true
	for _, item in ipairs(list) do
		local slot = rail.buttons[item.key]
		local frame = item.frame
		if item.addon then
			railHeld[frame] = true
			frame:SetParent(rail)
		end
		OnSlot(frame, slot, rail)
		if not item.toggle then
			railTitles[frame] = item.title
			if not railTipHooked[frame] and frame.HookScript then
				railTipHooked[frame] = true
				frame:HookScript("OnEnter", RailTipEnter)
				frame:HookScript("OnLeave", RailTipLeave)
			end
		end
	end
	placing = false
	if #addons > 0 then self:PlaceBinButtons() end
	railPad.LEFT, railPad.RIGHT = 0, 0
	railPad[side] = rail:GetWidth()
	-- Addon buttons on the rail: the first time explains itself.
	if #addons > 0 then E.Tour:Offer("minimap:rail") end
end

---------------------------------------------------------------------------
-- Element "queue-status-button": the group finder eye
---------------------------------------------------------------------------
local queueAnchoring = false
local queueBox

function M:AnchorQueue()
	if queueAnchoring or not Usable(QueueStatusButton) then return end
	queueAnchoring = true
	local db = self.db.queue
	Remember(QueueStatusButton)
	-- QueueStatusButton is an Edit Mode system (group finder): the plain
	-- widget methods, so Edit Mode's overrides never run from EldoUI.
	Keep.SetScale(QueueStatusButton, db.scale)
	if db.anchor == "free" then
		if not self.queueHolder then
			local holder = CreateFrame("Frame", "EldoUI_QueueStatus", UIParent)
			holder:SetSize(36, 36)
			self.queueHolder = holder
			-- Left of the minimap, under the buffs (on the minimap edge).
			E:CreateMover(holder, "EldoUI_QueueStatus", L["Group Finder Eye"], { "TOPRIGHT", "UIParent", "TOPRIGHT", -260, -250 }, { followShown = true })
		end
		self.queueHolder:Show()
		self.queueOnMap = false
		Keep.ClearAllPoints(QueueStatusButton)
		Keep.SetPoint(QueueStatusButton, "CENTER", self.queueHolder, "CENTER")
	else
		if self.queueHolder then self.queueHolder:Hide() end
		self.queueOnMap = true
		self:LayoutCorners()
	end
	queueAnchoring = false
end

function M:ApplyQueue()
	if not Usable(QueueStatusButton) then return end
	local moved = E:BlizzardAllowed(QUEUE, "move")
	if moved then
		if not self.queueHooked then
			self.queueHooked = true
			-- Blizzard re-anchors it to the minimap when the scale changes.
			hooksecurefunc(QueueStatusButton, "SetPoint", function()
				if queueAnchoring or cornerPlacing or M.layingOut or not M.active or not E:BlizzardAllowed(QUEUE, "move") then return end
				E:RunOutOfCombat(function() M:AnchorQueue() end, "minimap:queue")
			end)
		end
		self:AnchorQueue()
	else
		self.queueOnMap = false
		if self.queueHolder then self.queueHolder:Hide() end
		Restore(QueueStatusButton)
	end
	local skin = E:BlizzardAllowed(QUEUE, "skin")
	if skin then
		if not queueBox then
			queueBox = CreateFrame("Frame", nil, QueueStatusButton)
			queueBox:SetPoint("CENTER")
			queueBox:SetSize(34, 34)
			queueBox:SetFrameLevel(math.max(QueueStatusButton:GetFrameLevel() - 1, 0))
		end
		E:SetTemplate(queueBox, true)
		queueBox:Show()
	elseif queueBox then
		queueBox:Hide()
	end
end

function M:RestoreQueue()
	self.queueOnMap = false
	if self.queueHolder then self.queueHolder:Hide() end
	if queueBox then queueBox:Hide() end
	if Usable(QueueStatusButton) then Restore(QueueStatusButton) end
end

---------------------------------------------------------------------------
-- Handlers
---------------------------------------------------------------------------
E:RegisterBlizzardHandler(MAP, {
	owner = "Minimap",
	apply = function() M:ApplyMap() end,
	undo = function() M:RestoreMap() end,
	reload = { skin = true, replace = true },
	install = { replace = true, move = true, improve = true },
	legacy = function() return M.db and M.db.enabled end,
})

E:RegisterBlizzardHandler(BUTTONS, {
	owner = "Minimap",
	apply = function() M:ApplyButtons() end,
	undo = function() M:RestoreButtons() end,
	reload = { skin = true },
	install = { move = true, hide = true, replace = true, skin = true },
	legacy = function() return M.db and M.db.enabled end,
})

E:RegisterBlizzardHandler(QUEUE, {
	owner = "Minimap",
	apply = function() M:ApplyQueue() end,
	undo = function() M:RestoreQueue() end,
	install = { move = true, skin = true },
	legacy = function() return false end,
})

---------------------------------------------------------------------------
-- Minimap overlay
---------------------------------------------------------------------------
do
	local OWNER, COMPASS_TICK = "minimap-overlay", "Minimap:overlay-compass"
	local compass = { E.Key("N"), E.Key("W"), E.Key("S"), E.Key("E") }
	local chromeKeys = { "holder", "overlay", "skinRing", "originalHardware", "bin", "binToggle", "badge" }
	local view, menuHooked

	local function Allowed(module)
		local mode = MapMode()
		return module.active and mode ~= nil and mode ~= "hide" and E.PlainCall(IsInInstance) == false
	end

	local function AddMenuEntry(root)
		root:CreateButton(L["Toggle minimap overlay"], function() M:ToggleMinimapOverlay() end)
	end

	function M:HookMinimapOverlayMenu()
		if menuHooked or not (Menu and Menu.ModifyMenu) then return end
		menuHooked = true
		Menu.ModifyMenu("MENU_MINIMAP_TRACKING", function(_, root)
			if Allowed(M) then AddMenuEntry(root) end
		end)
	end

	local function CreateView()
		local frame = CreateFrame("Frame", nil, UIParent)
		frame:SetPoint("CENTER")
		frame:SetFrameStrata("LOW")
		frame:Hide()
		frame.guide = CreateFrame("Frame", nil, frame)
		frame.guide:SetAllPoints()
		frame.guide:SetFrameLevel(frame:GetFrameLevel() + 20)
		frame.letters = {}
		for index = 1, 4 do
			frame.letters[index] = E:CreateText(frame.guide, E.tokens.size.body, "CENTER")
		end
		frame.lines = {}
		-- The exit menu stays in the corner so it never takes a click on the map.
		frame.menu = E.UIKit.Button(UIParent, { text = L["Minimap overlay"], height = E.tokens.height.row,
			onClick = function(button)
				E.UIKit.ContextMenu(button, function(_, root) AddMenuEntry(root) end, { at = "owner" })
			end })
		frame.menu:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -16, -48)
		frame.menu:Hide()
		return frame
	end

	local function PlaceCompass(frame)
		local rotating = E.PlainCall(GetCVar, "rotateMinimap") == "1"
		local facing = 0
		if rotating then facing = E.PlainCall(GetPlayerFacing) end
		if type(facing) ~= "number" then facing = false end
		if facing == frame.compassFacing then return end
		frame.compassFacing = facing
		local radius = frame:GetWidth() * 0.46
		for index, text in ipairs(frame.letters) do
			text:SetShown(type(facing) == "number")
			if type(facing) == "number" then
				local angle = (index - 1) * math.pi / 2 - facing
				text:SetText(L[compass[index]])
				text:ClearAllPoints()
				text:SetPoint("CENTER", frame.guide, "CENTER", -math.sin(angle) * radius, math.cos(angle) * radius)
			end
		end
	end

	local function LayoutView(frame, db)
		local size = math.floor(UIParent:GetHeight() * db.overlaySize + 0.5)
		if size ~= frame:GetWidth() then
			frame:SetSize(size, size)
			E:FitHostedMinimap(OWNER)
		end
		frame:SetAlpha(db.overlayOpacity)
		frame.menu:SetText(L["Minimap overlay"])
		E.UIKit.RefitButton(frame.menu)
		if frame.menu:GetWidth() + 20 > (UIParent:GetWidth() - size) / 2 then
			frame.menu:SetText(L["Close"])
			E.UIKit.RefitButton(frame.menu)
		end
		if db.overlayCompass then
			frame.compassFacing = nil
			PlaceCompass(frame)
			if not E.Ticker:IsSubscribed(COMPASS_TICK) then
				E.Ticker:Subscribe(COMPASS_TICK, 0.1, function() PlaceCompass(frame) end, frame)
			end
		else
			E.Ticker:Unsubscribe(COMPASS_TICK)
			for _, text in ipairs(frame.letters) do text:Hide() end
		end
		if db.overlayCircle then
			local radius = size * 0.42
			local r, g, b = E:TokenColor("body")
			for index = 1, 48 do
				local line = frame.lines[index]
				if not line then
					line = frame.guide:CreateLine(nil, "ARTWORK")
					frame.lines[index] = line
				end
				local start = (index - 1) * math.pi / 24
				local finish = index * math.pi / 24
				line:SetStartPoint("CENTER", frame.guide, math.cos(start) * radius, math.sin(start) * radius)
				line:SetEndPoint("CENTER", frame.guide, math.cos(finish) * radius, math.sin(finish) * radius)
				line:SetThickness(E.pixel)
				line:SetColorTexture(r, g, b, 0.55)
				line:Show()
			end
		else
			for _, line in ipairs(frame.lines) do line:Hide() end
		end
	end

	local function HideChrome(overlay, frame)
		if not (Usable(frame) and frame.IsShown and frame.Hide) then return end
		if E.PlainCall(frame.IsShown, frame) ~= true or E.FrameCheck(frame, "IsProtected") then return end
		overlay.chrome[frame] = true
		frame:Hide()
	end

	local function HideMapChrome(module, overlay)
		HideChrome(overlay, MinimapCluster)
		for _, key in ipairs(chromeKeys) do
			HideChrome(overlay, module[key])
		end
		for _, key in ipairs(BUTTON_KEYS) do
			for _, frame in ipairs(ButtonFrames(key)) do HideChrome(overlay, frame) end
		end
		if module.queueMoved and module.db.queue.anchor == "minimap" then HideChrome(overlay, QueueStatusButton) end
	end

	function M:RefreshMinimapOverlay()
		local overlay = self.minimapOverlay
		if not overlay then return false end
		if not Allowed(self) or overlay.db ~= self.db or overlay.map ~= Minimap then
			self:CloseMinimapOverlay(true)
			return self.minimapOverlay ~= nil
		end
		overlay.refresh = true
		if not overlay.closing and not InCombatLockdown() then
			HideMapChrome(self, overlay)
			LayoutView(overlay.frame, self.db)
		end
		return true
	end

	function M:CloseMinimapOverlay(skipRefresh)
		local overlay = self.minimapOverlay
		if not overlay then return end
		overlay.closing = true
		E.Ticker:Unsubscribe(COMPASS_TICK)
		-- The empty overlay can hide at once. Native geometry and input wait.
		if E.FrameCheck(overlay.frame, "IsProtected") then overlay.frame:SetAlpha(0) else overlay.frame:Hide() end
		overlay.frame.menu:Hide()
		E:RunOutOfCombat(function()
			if M.minimapOverlay ~= overlay then return end
			M.minimapOverlay = nil
			if E:MinimapHostOwner() == OWNER then
				overlay.map:SetMouseClickEnabled(overlay.clicks)
				overlay.map:EnableMouseWheel(overlay.wheel)
				E:SetMinimapPinClickThrough(false)
				E:ReleaseMinimap(OWNER, true)
			end
			for frame in pairs(overlay.chrome) do
				if not E.FrameCheck(frame, "IsProtected") then frame:Show() end
			end
			if overlay.refresh and not skipRefresh and M.active then M:Apply() end
			M:FollowMapShown()
		end, OWNER)
	end

	function M:ToggleMinimapOverlay()
		if self.minimapOverlay then return self:CloseMinimapOverlay() end
		local map = Minimap
		if not (Allowed(self) and Usable(map) and E.PlainCall(map.IsVisible, map) == true)
			or InCombatLockdown() or E:MinimapHostOwner() or E.FrameCheck(map, "IsProtected") then return end
		local clicks = E.FrameMouse(map, "IsMouseClickEnabled")
		local wheel = E.FrameMouse(map, "IsMouseWheelEnabled")
		if clicks == nil or wheel == nil then return end
		view = view or CreateView()
		local size = math.floor(UIParent:GetHeight() * self.db.overlaySize + 0.5)
		view:SetSize(size, size)
		if not E:HostMinimap(OWNER, view) then return end
		local overlay = { frame = view, map = map, db = self.db, clicks = clicks, wheel = wheel, chrome = {} }
		self.minimapOverlay = overlay
		if self.zoomTimer then self.zoomTimer:Cancel() self.zoomTimer = nil end
		map:SetMouseClickEnabled(false)
		map:EnableMouseWheel(true)
		E:SetMinimapPinClickThrough(true)
		HideMapChrome(self, overlay)
		LayoutView(view, self.db)
		view:Show()
		view.menu:Show()
	end
end

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------
-- A new UI scale or screen size: the border and the map inside it are
-- sized again in whole screen pixels.
if E.RegisterPixelCallback then
	E:RegisterPixelCallback(function()
		if M.active and M.db then E:RunOutOfCombat(function() if M.active then M:ApplyMap() end end, "minimap:pixel") end
	end)
end

function M:Apply()
	if self:RefreshMinimapOverlay() then return end
	self.layingOut = true
	self:ApplyMap()
	self:ApplyBadge()
	self:ApplyButtons()
	self:ApplyQueue()
	if self.Layer then self.Layer.Apply() end
	self:LayoutCorners()
	self.layingOut = false
	if E.RefreshMinimapCluster then E:RefreshMinimapCluster() end
end

-- A queued layout runs only while the module is still on, so turning the
-- minimap off during combat keeps it off after the fight.
function M:OnEnable()
	self:HookMinimapOverlayMenu()
	E:RunOutOfCombat(function() if M.active then M:Apply() end end, "minimap:apply")
	self:StartTextTick()
	self:RegisterEvent("ZONE_CHANGED", "UpdateZone")
	self:RegisterEvent("ZONE_CHANGED_INDOORS", "UpdateZone")
	self:RegisterEvent("ZONE_CHANGED_NEW_AREA", "UpdateZone")
	self:RegisterEvent("DIEL_CYCLE_CHANGED", function() if M.diel then M:UpdateDiel() end end)
	self:RegisterEvent("MINIMAP_UPDATE_TRACKING", function() M:UpdateTrackingIcon() end)
	self:RegisterEvent("PLAYER_REGEN_DISABLED", function()
		if M.minimapOverlay and M.db.overlayCombat then M:CloseMinimapOverlay() end
	end)
	self:RegisterEvent("ADDON_LOADED", function()
		if M.minimapOverlay then M:RefreshMinimapOverlay() end
	end)
	self:RegisterEvent("PLAYER_ENTERING_WORLD", function()
		if M.minimapOverlay and E.PlainCall(IsInInstance) ~= false then M:CloseMinimapOverlay() end
		if M.active then E:RunOutOfCombat(function() if M.active then M:Apply() end end, "minimap:apply") end
	end)
	-- Square mask for the indoor (hybrid) map as well.
	E:OnBlizzardAddOn("Blizzard_HybridMinimap", function()
		if M.active and M.masked then M:SetMask() end
	end)
end

function M:OnDisable()
	self:CloseMinimapOverlay(true)
	self:StopPingNames()
	E.Ticker:Unsubscribe(TEXT_TICK)
	self:UnregisterEvent("ZONE_CHANGED")
	self:UnregisterEvent("ZONE_CHANGED_INDOORS")
	self:UnregisterEvent("ZONE_CHANGED_NEW_AREA")
	self:UnregisterEvent("DIEL_CYCLE_CHANGED")
	self:UnregisterEvent("MINIMAP_UPDATE_TRACKING")
	self:UnregisterEvent("PLAYER_ENTERING_WORLD")
	self:UnregisterEvent("PLAYER_REGEN_DISABLED")
	self:UnregisterEvent("ADDON_LOADED")
	if self.Layer then self.Layer.Disable() end
	if self.badge then self.badge:Hide() end
	E:RunOutOfCombat(function()
		if M.active then return end
		M:RestoreQueue()
		M:RestoreButtons()
		M:RestoreMap()
		if E.RefreshMinimapCluster then E:RefreshMinimapCluster() end
	end, "minimap:restore")
	E:ShowReloadPrompt(L["Minimap switched off. Anything of Blizzard's minimap that is still missing comes back after a reload."])
end

function M:OnProfileChanged()
	if not self.db.pingNames then self:StopPingNames() end
	self:TakeManagePick()
	self:TakeAddName()
	if self.active then E:RunOutOfCombat(function() if M.active then M:Apply() end end) end
end

---------------------------------------------------------------------------
-- Options
---------------------------------------------------------------------------
local function Not(id, action) return function() return not E:BlizzardAllowed(id, action) end end

local function SwitchButton(id, action, label, desc)
	return { type = "execute", label = label, desc = desc,
		hidden = function() return E:BlizzardAllowed(id, action) end,
		func = function()
			E:SetBlizzardElement(id, "enabled", true)
			E:SetBlizzardElement(id, action, true)
			if E.RefreshConfig then E:RefreshConfig() end
		end }
end


-- Preview: a sample map in its shape, with the zone name and the clock
-- as set on the Text tab, scaled to the strip (E:ConfigSample,
-- Core/MoverSamples.lua).
local function UpdatePreview(canvas)
	local db = M.db
	if not (canvas and db) then return end
	E:ConfigSample(canvas, "minimap", {
		size = db.size, round = db.shape == "round", fontSize = db.zoneSize,
		zone = db.showZone and (GetZoneText and GetZoneText() or "") or false,
		clock = db.showClock and "12:30" or nil,
	})
end

M.options = {
	{ type = "tab", label = "Map" },
	{ type = "preview", label = "Preview", height = 140, create = UpdatePreview, update = UpdatePreview,
		desc = "A sample map in its shape, with the zone name and clock as set on the Text tab." },
	{ type = "description", label = "Blizzard UI decides: Replace gives the EldoUI minimap, Skin gives Blizzard's a flat look, Improve adds the text and extras below." },
	SwitchButton(MAP, "replace", E.Key("Use the EldoUI minimap"), E.Key("Turns on the Blizzard UI switch for the minimap with Replace.")),
	{ type = "header", label = "Minimap overlay" },
	{ type = "execute", label = "Toggle minimap overlay", func = function() M:ToggleMinimapOverlay() end,
		desc = "Centers the game's minimap with its pins. Click through to the world and use the mouse wheel to zoom. You can also set a key binding." },
	{ type = "range", key = "overlaySize", label = "Overlay size", desc = "Size as a share of the screen height.",
		min = 0.60, max = 1, step = 0.05, percent = true },
	{ type = "range", key = "overlayOpacity", label = "Overlay opacity", desc = "How much of the world shows through the large map.",
		min = 0.15, max = 1, step = 0.05, percent = true },
	{ type = "toggle", key = "overlayCombat", label = "Close overlay when combat starts",
		desc = "Hide the large map when combat starts and return it to its normal position after combat." },
	{ type = "toggle", key = "overlayCompass", label = "Overlay compass letters", desc = "Show the four compass directions around the large map." },
	{ type = "toggle", key = "overlayCircle", label = "Overlay range circle", desc = "Show a thin circle near the edge of the large map." },
	{ type = "header", label = "Shape and size" },
	{ type = "select", key = "shape", label = "Shape", desc = "Square or round map.", values = { square = "Square", round = "Round" } },
	{ type = "range", key = "size", label = "Size", desc = "Width and height of the EldoUI minimap (Replace).", min = 120, max = 400, step = 1,
		hidden = Not(MAP, "replace") },
	{ type = "select", key = "border", label = "Border", desc = "Border around the map.", values = { thin = "Thin", thick = "Thick", none = "None" } },
	{ less = true, type = "toggle", key = "accentBorder", label = "Accent border", desc = "Draw the border in the accent color." },
	{ type = "header", label = "Mouse" },
	{ type = "toggle", key = "wheelZoom", label = "Mouse-wheel zoom", desc = "Zoom with the mouse wheel over the map (Blizzard's own zoom).", hidden = Not(MAP, "improve") },
	{ type = "range", key = "zoomReset", label = "Zoom out again after", unit = "s", desc = "After you zoom with the mouse wheel, the map zooms back out after this many seconds. 0 keeps your zoom.",
		min = 0, max = 60, step = 1, hidden = Not(MAP, "improve") },
	{ type = "select", key = "middleClick", label = "Middle-click", desc = "What a middle-click on the map opens.",
		values = { tracking = "Tracking menu", calendar = "Calendar", none = "Nothing" }, hidden = Not(MAP, "improve") },
	{ type = "select", key = "rotate", label = "Rotate minimap", desc = "Blizzard's rotate setting. \"Leave as it is\" never changes it.",
		values = { blizzard = "Leave as it is", on = "Rotate", off = "North up" }, hidden = Not(MAP, "improve") },
}
-- Visibility: the shared rules (Replace only: they fade the EldoUI frame).
for _, row in ipairs(E:VisibilityOptions("visibility", { db = function() return M.db end, hidden = Not(MAP, "replace") })) do
	table.insert(M.options, row)
end
for _, row in ipairs({
	{ type = "description", label = "Visibility rules need the EldoUI minimap (Replace in Blizzard UI).",
		hidden = function() return E:BlizzardAllowed(MAP, "replace") end },

	{ type = "tab", label = "Text" },
	{ type = "description", label = "Needs Improve switched on for the minimap in Blizzard UI.", hidden = function() return E:BlizzardAllowed(MAP, "improve") end },
	{ type = "header", label = "Zone" },
	{ type = "toggle", key = "showZone", label = "Show zone name", desc = "Zone name on top, colored by PvP status." },
	{ type = "select", key = "zonePosition", label = "Zone position", desc = "Inside the top of the map, above it, or only while you point at the map.",
		values = { inside = "Top inside", outside = "Above the map", hover = "On mouseover" } },
	{ type = "range", key = "zoneSize", label = "Zone text size", desc = "Font size of the zone name.", min = 8, max = 20, step = 1 },
	{ type = "header", label = "Coordinates" },
	{ type = "toggle", key = "showCoords", label = "Show coordinates", desc = "Your position on the map. Empty where the game hides it (instances)." },
	{ type = "select", key = "coordDecimals", label = "Coordinate precision", desc = "Whole numbers, one or two decimals.",
		values = { [0] = "45, 62", [1] = "45.3, 62.1", [2] = "45.27, 62.08" } },
	{ type = "select", key = "coordPosition", label = "Coordinate position", desc = "Corner or edge of the map.", values = POSITIONS },
	{ type = "header", label = "Clock" },
	{ type = "toggle", key = "showClock", label = "Show clock", desc = "EldoUI's clock text. Click opens the calendar, right-click the alarm and stopwatch." },
	{ type = "execute", label = "Clock format", keywords = "24-hour 12-hour time",
		desc = "24-hour or 12-hour time is set once for every EldoUI clock, on the General page (Clock and durability).",
		func = function() E:ToggleConfig("general") end },
	{ type = "toggle", key = "clockRealm", label = "Realm time", desc = "Show the server's time instead of your computer's." },
	{ type = "select", key = "clockPosition", label = "Clock position", desc = "Corner or edge of the map.", values = POSITIONS },
	{ type = "range", key = "textSize", label = "Text size", desc = "Font size of the clock and coordinates.", min = 8, max = 20, step = 1 },
	{ type = "toggle", key = "pingNames", label = "Show minimap ping names",
		desc = "Briefly shows who pinged the minimap, in their class color." },
	{ type = "header", label = "Day and night" },
	{ type = "toggle", key = "diel", label = "Day/night indicator", desc = "Forever's day and night cycle as a small icon on the map." },
	{ type = "select", key = "dielPosition", label = "Indicator position", desc = "Corner or edge of the map.", values = POSITIONS },

	{ type = "tab", label = "Layer hop" },
	{ type = "description", label = "The chip needs Improve switched on for the minimap in Blizzard UI.", hidden = function() return E:BlizzardAllowed(MAP, "improve") end },
	{ type = "toggle", key = "layer", label = "Layer chip",
		desc = "The layer you are on as a short code on the map, read from the creatures around you. Click it to hop to another layer. Hidden in instances." },
	{ type = "select", key = "layerPosition", label = "Chip position", desc = "Corner or edge of the map.", values = POSITIONS },
	{ type = "toggle", key = "layerNotice", label = "Say when your layer changes", desc = "A line in your chat each time the layer you are on changes." }, -- lint: unused-key ok (Modules/MinimapLayer.lua reads it)
	{ type = "header", label = "Hopping" },
	{ type = "description", label = "A player on another layer invites you; you accept in the game's popup and leave the group once your layer changes. Each step is a click." },
	{ type = "toggle", key = "layerNetwork", label = "Join the layer network", -- lint: unused-key ok (Modules/MinimapLayer.lua reads it)
		desc = function()
			return L["Joins a hidden chat channel shared by EldoUI and %s for asking for and offering layer hops. Off: use your guild only."]:format(E.LayerNetwork.folder)
		end },
	{ type = "toggle", key = "layerHelp", label = "Help others hop", -- lint: unused-key ok (Modules/MinimapLayer.lua reads it)
		desc = "Answers hop requests from your guild and, while you are in the layer network, from its players. Each request shows a card: Invite or Not now. Never in combat or in an instance." },
	{ type = "toggle", key = "layerAddon", label = function() return L["Use %s"]:format(E.LayerNetwork.folder) end, -- lint: unused-key ok (Modules/MinimapLayer.lua reads it)
		desc = function()
			return L["Opens the %s window from the layer chip and lets it handle layer network requests."]:format(E.LayerNetwork.folder)
		end,
		hidden = function() return not (M.Layer and M.Layer.AddonLoaded()) end },

	{ type = "tab", label = "Buttons" },
	{ type = "description", label = "Places Blizzard's minimap buttons in the map's corners. Needs \"Minimap buttons\" on in Blizzard UI (Move to place, Hide for \"Hidden\")." },
	SwitchButton(BUTTONS, "move", E.Key("Let EldoUI place the minimap buttons"), E.Key("Turns on the Blizzard UI switch for the minimap buttons with Move.")),
	{ type = "range", percent = true, key = "iconScale", label = "Button scale", desc = "Scale of Blizzard's minimap buttons.", min = 0.5, max = 1.5, step = 0.05, hidden = Not(BUTTONS, "move") },
	{ type = "toggle", key = "trackingIcon", label = "Show the active tracking",
		desc = "The flat tracking button shows the icon of the tracking you have on, such as Find Herbs, and is dimmed while nothing is tracked. It still opens the game's tracking menu.",
		hidden = Not(BUTTONS, "skin") },
}) do
	table.insert(M.options, row)
end
for _, key in ipairs({ "tracking", "calendar", "mail", "event", "compartment", "clock", "zoom", "expansion", "queue", "bin" }) do
	local label = BUTTON_LABELS[key]
	table.insert(M.options, { type = "select", key = "buttons." .. key, label = label[1], desc = label[2],
		values = key == "queue" and BUTTON_POSITIONS or RAIL_POSITIONS, hidden = Not(BUTTONS, "move") })
end
table.insert(M.options, { type = "select", key = "railSide", label = "Rail side",
	desc = "The edge of the map that holds the slim button rail. Buttons set to \"On the side rail\" sit on it one under the other, each with a tooltip naming it.",
	values = { LEFT = "Left edge", RIGHT = "Right edge" }, hidden = Not(BUTTONS, "move"),
	disabled = function()
		for key, position in pairs(M.db.buttons) do
			if position == RAIL and key ~= "queue" then return false end
		end
		if M.db.binMode == "rail" then return false end
		return L["Put a button on the side rail first."]
	end })
local BIN_OPTIONS = {
	{ type = "header", label = "Addon button bin", status = function() return Bin.Status() end },
	{ type = "select", key = "binMode", label = "Addon buttons", desc = "Gathers addon minimap buttons in a strip, on the side rail, or in a drawer behind one button. A button its addon hides stays hidden. Needs Replace for \"Minimap buttons\".",
		values = { off = "Leave them", bar = "Strip", rail = "On the side rail", drawer = "Drawer (click)", hover = "Drawer (mouseover)" },
		order = { "off", "drawer", "hover", "bar", "rail" },
		disabled = function()
			local back = Bin.StandsBack()
			if back then return L["Another addon gathers the minimap buttons: %s."]:format(back) end
		end },
	{ type = "toggle", key = "badge", label = "EldoUI button",
		desc = "EldoUI's own minimap button: click for Move frames, right-click for keybind mode. It leads the addon button bin; while the bin is off it sits on the map's edge, and you can drag it around the map." },
	{ type = "select", key = "binManage", label = "Manage buttons", noUndo = true, values = function() return Bin.ManageValues() end,
		desc = "Pick an addon button to keep it on the map with its addon, or to gather it in the bin again. The list shows every addon button found since you logged in." },
	{ type = "execute", label = "Gather every button again", noUndo = true,
		desc = "Puts every addon button you kept on the map back in the bin.",
		hidden = function() return next(M.db.binExclude) == nil end,
		func = function()
			wipe(M.db.binExclude)
			if M.active then E:RunOutOfCombat(function() M:ApplyBin() end) end
			if E.RefreshConfig then E:RefreshConfig() end
		end },
	{ type = "range", unit = "px", key = "binSize", label = "Bin button size", desc = "Size of each addon button in the bin.", min = 14, max = 40, step = 1 },
	{ type = "range", key = "binPerRow", label = "Buttons per row", desc = "Addon buttons per row in the bin.", min = 1, max = 12, step = 1 },
	{ type = "range", unit = "px", key = "binSpacing", label = "Bin spacing", desc = "Gap between addon buttons.", min = 0, max = 8, step = 1 },
	{ type = "select", key = "binSide", label = "Bin side",
		desc = "Where the bin opens. Automatic opens beside the map on the side that faces the middle of the screen, or below it where there is no room, and always stays on the screen.",
		values = { AUTO = "Automatic", BOTTOM = "Below the map", LEFT = "Left of the map" }, order = { "AUTO", "BOTTOM", "LEFT" } },
	{ type = "select", key = "binGrow", label = "Bin growth",
		desc = "The way the buttons fill the bin, then the way the next row goes. The bin opens on that side of its button. Automatic fills rows to the right and follows Bin side.",
		values = { AUTO = "Automatic", RIGHTDOWN = "Right, then down", RIGHTUP = "Right, then up", LEFTDOWN = "Left, then down",
			LEFTUP = "Left, then up", DOWNRIGHT = "Down, then right", DOWNLEFT = "Down, then left", UPRIGHT = "Up, then right", UPLEFT = "Up, then left" },
		order = { "AUTO", "RIGHTDOWN", "RIGHTUP", "LEFTDOWN", "LEFTUP", "DOWNRIGHT", "DOWNLEFT", "UPRIGHT", "UPLEFT" } },
	{ type = "toggle", key = "binMover", label = "Bin on its own mover",
		desc = "Takes the bin's button (or the strip) off the map and puts it on a mover of its own, so you can place it anywhere in Move frames. It starts in the map's corner." },
	{ type = "toggle", key = "binKeepOpen", label = "Remember the drawer",
		desc = "The click drawer stays open or closed the way you left it, also after a reload." },
	{ type = "input", key = "binAdd", label = "Add a button by name", noUndo = true,
		desc = "Type the frame name of an addon button the bin does not find by itself, then press Enter. The game's own buttons and protected buttons stay where they are." },
	{ type = "execute", label = "Forget added buttons", noUndo = true,
		desc = "Removes every button you added by name from the bin. They go back to their addons.",
		hidden = function() return next(M.db.binInclude) == nil end,
		func = function()
			wipe(M.db.binInclude)
			if M.active then E:RunOutOfCombat(function() M:ReleaseButtons() M:ApplyBin() end) end
			if E.RefreshConfig then E:RefreshConfig() end
		end },
	{ type = "header", label = "Group finder eye" },
	{ type = "select", key = "queue.anchor", label = "Eye position", desc = "On a minimap corner (see Group finder eye above) or on its own mover. Needs \"Queue status eye\" with Move in Blizzard UI.",
		values = { minimap = "On the minimap", free = "Own mover" } },
	{ type = "range", percent = true, key = "queue.scale", label = "Eye scale", desc = "Scale of the group finder eye.", min = 0.5, max = 1.5, step = 0.05 },
	{ type = "execute", label = "Open Blizzard UI switches", desc = "Open the switches for the minimap, its buttons and the group finder eye.",
		func = function() if E.ToggleConfig then E:ToggleConfig("blizzard") end end },
}
for _, option in ipairs(BIN_OPTIONS) do table.insert(M.options, option) end

-- Rows that wait on a switch are grayed with the reason while it is off.
do
	local TEXT_ROWS = { showZone = true, zonePosition = "showZone", zoneSize = "showZone", showCoords = true,
		coordDecimals = "showCoords", coordPosition = "showCoords", showClock = true, clockRealm = "showClock",
		clockPosition = "showClock", textSize = true, pingNames = true, diel = true, dielPosition = "diel", layer = true, layerPosition = "layer" }
	local BIN_ROWS = { binSize = true, binPerRow = true, binSpacing = true, binSide = true, binManage = true,
		binGrow = true, binMover = true, binKeepOpen = true, binAdd = true }
	local needsImprove = E:BlizzardNeeds(MAP, "improve")
	-- Text size also sets Blizzard's own clock while the minimap buttons
	-- are skinned, so it stays live then.
	local function NoText()
		if E:BlizzardAllowed(BUTTONS, "skin") then return false end
		local reason = E:BlizzardNeedsReason(MAP, "improve")
		if reason then return reason end
		if not (M.db.showClock or M.db.showCoords) then return L["Turn on the clock or the coordinates first."] end
		return false
	end
	local function NoBin()
		local reason = E:BlizzardNeedsReason(BUTTONS, "replace")
		if reason then return reason end
		local back = Bin.StandsBack()
		if back then return L["Another addon gathers the minimap buttons: %s."]:format(back) end
		if M.db.binMode == "off" then return L["Pick how to gather the addon buttons first."] end
	end
	for _, row in ipairs(M.options) do
		local text = TEXT_ROWS[row.key]
		if text then
			row.disabled = row.key == "textSize" and NoText or needsImprove
			if type(text) == "string" then row.dependsOn = text end
		elseif row.key == "binManage" then
			row.disabled = function()
				local reason = NoBin()
				if reason then return reason end
				if next(Bin.seen) == nil then return L["No addon buttons found yet."] end
			end
		elseif row.key == "binSide" then
			row.disabled = function()
				local reason = NoBin()
				if reason then return reason end
				if M.db.binGrow ~= "AUTO" then return L["Bin growth decides the side. Set it to Automatic first."] end
			end
		elseif row.key == "binMover" then
			row.disabled = function()
				local reason = NoBin()
				if reason then return reason end
				if M.db.binMode == "rail" then return L["The rail holds the buttons. Pick another way to gather them first."] end
			end
		elseif row.key == "binKeepOpen" then
			row.disabled = function()
				local reason = NoBin()
				if reason then return reason end
				if M.db.binMode ~= "drawer" then return L["Only the click drawer stays open."] end
			end
		elseif BIN_ROWS[row.key] then
			row.disabled = NoBin
		elseif row.key == "zoomReset" then
			row.dependsOn = "wheelZoom"
		end
	end
end

---------------------------------------------------------------------------
-- Style presets: size, shape, border and the texts on the map. A style
-- never moves the map (the layout owns its place).
---------------------------------------------------------------------------
local function Square(size, showZone, showCoords, showClock)
	return { shape = "square", border = "thin", accentBorder = false, zonePosition = "inside", size = size,
		showZone = showZone, showCoords = showCoords, showClock = showClock }
end

E:RegisterStyles("Minimap", {
	{ key = "Square", title = "Square", desc = "237 px square with zone, coordinates and clock.",
		settings = Square(237, true, true, true) },
	{ key = "Large", title = "Large", desc = "280 px for gatherers and explorers.",
		settings = Square(280, true, true, true) },
	{ key = "Minimal", title = "Minimal", desc = "180 px with no text at all.",
		settings = Square(180, false, false, false) },
	{ key = "Clock", title = "Clock only", desc = "200 px with just the clock.",
		settings = Square(200, false, false, true) },
	{ key = "Framed", title = "Framed", desc = "237 px square with a thick border in the accent color.",
		settings = { size = 237, shape = "square", border = "thick", accentBorder = true, zonePosition = "inside", showZone = true, showCoords = true, showClock = true } },
	{ key = "Round", title = "Round", desc = "237 px round map with a thin border, zone above it.",
		settings = { size = 237, shape = "round", border = "thin", showZone = true, zonePosition = "outside", showCoords = true, showClock = true,
			clockPosition = "BOTTOMLEFT", coordPosition = "BOTTOM" } },
	-- The tidy-buttons pick: every button on one slim rail instead of
	-- spread over the corners.
	{ key = "Rail", title = "Button rail", desc = "Square map with the tracking, calendar and mail buttons and the addon button toggle on a slim rail along its left edge.",
		settings = { size = 237, shape = "square", railSide = "LEFT",
			buttons = { tracking = RAIL, calendar = RAIL, mail = RAIL, event = RAIL, compartment = RAIL, bin = RAIL,
				clock = "hide", zoom = "hide", expansion = "hide" } } },
}, { restores = { "showZone", "showCoords", "showClock" },
	-- The styles shape EldoUI's minimap: while the game's own minimap is
	-- shown, the style list and the setup say so.
	notice = function(where)
		if M.active and E:BlizzardAllowed(MAP, "replace") then return nil end
		if where == "setup" then
			return L["Shows on EldoUI's minimap, which the Blizzard UI step turns on (Recommended, Only EldoUI's own frames or Everything)."]
		end
		if not M.active then return E:ModuleOffNote("Minimap") end
		local reason = E:BlizzardNeedsReason(MAP, "replace")
		return L["These styles shape EldoUI's minimap, not the game's own."] .. (reason and (" " .. reason) or "")
	end })

---------------------------------------------------------------------------
-- Tour help: the first time addon buttons are gathered on the side rail
---------------------------------------------------------------------------
local function ShownRail()
	local rail = M.rails[M.db and M.db.railSide == "RIGHT" and "RIGHT" or "LEFT"]
	if rail and rail:IsVisible() then return rail end
end

E.Tour:Register("minimap:rail", {
	form = "spot", word = "rail",
	offer = function(_, force)
		return E.Tour:Spot("minimap:rail", {
			-- Offered again at the next redraw, so it never waits in the queue.
			force = force, now = true, target = ShownRail,
			title = L["Addon buttons"],
			text = L["Your addons' minimap buttons sit on this rail beside the map. When they don't all fit, the last button opens the rest. Minimap > Addon buttons puts them somewhere else."],
		})
	end,
	replay = function(def) def.offer(def, true) end,
})
