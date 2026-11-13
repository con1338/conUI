-- EldoUI flight view (Quality of Life > Travel, off by default): while you
-- fly a flight path the interface fades and one calm panel shows where you
-- fly to, the zone below you, the time left and the route from the flight
-- timer, with buttons for the map, your bags, landing early and leaving
-- the view.
--
-- Presentation only. It opens when a flight starts and closes when you
-- land, a queue pops (unless switched off), a ready check starts, combat
-- starts, or you click Exit or press Esc; then it stays away until the
-- next flight. The map and bags buttons bring the interface back first.
-- "Land early" asks the game to land only inside your own click, never in
-- combat. It sits on the AFK screen's shell (Modules/AFK.lua): only the
-- interface's alpha changes, so leaving puts everything back, and a
-- reload in mid-air starts clean and opens the view again.
--
-- Written from scratch for EldoUI.
local _, E = ...
local L = E.L

local M = E:GetModule("QoL")

local OWNER = "FlightView"
local PANEL_HEIGHT = 132
local ROUTE_WIDTH = 520
local REDRAW = 0.1
local QUEUE_EVENTS = { LFG_PROPOSAL_SHOW = true, UPDATE_BATTLEFIELD_STATUS = true }

local view
local events = CreateFrame("Frame")

local function OnTaxi()
	if type(UnitOnTaxi) ~= "function" then return false end
	local ok, on = pcall(UnitOnTaxi, "player")
	if not ok or E.Secret(on) then return false end
	return on and true or false
end

-- The flight saved for a reload (QoL's flight timer keeps it until landing).
local function SavedFlight()
	local store = M.Store and M.Store()
	return type(store) == "table" and type(store.activeFlight) == "table" and store.activeFlight or nil
end

local function ZoneText()
	local zone, sub = E.Plain(GetRealZoneText()), E.Plain(GetSubZoneText())
	zone = type(zone) == "string" and zone or ""
	if type(sub) == "string" and sub ~= "" and sub ~= zone then return ("%s, %s"):format(sub, zone) end
	return zone
end

local function CoordsText()
	local map = C_Map and E.PlainCall(C_Map.GetBestMapForUnit, "player")
	if not map then return "" end
	local ok, position = pcall(C_Map.GetPlayerMapPosition, map, "player")
	if not ok or type(position) ~= "table" or type(position.GetXY) ~= "function" then return "" end
	local x, y = position:GetXY()
	if E.Secret(x) or E.Secret(y) or type(x) ~= "number" or type(y) ~= "number" or (x == 0 and y == 0) then return "" end
	return ("%.1f, %.1f"):format(x * 100, y * 100)
end

---------------------------------------------------------------------------
-- The panel: built once for the screen and once for the options preview.
---------------------------------------------------------------------------
local function BuildPanel(panel, preview)
	local size = E.tokens.size
	panel.flying = E:CreateText(panel, size.label, "LEFT")
	panel.flying:SetPoint("TOPLEFT", 24, -20)
	panel.destination = E:CreateText(panel, size.windowTitle, "LEFT")
	panel.destination:SetPoint("TOPLEFT", panel.flying, "BOTTOMLEFT", 0, -4)
	panel.destination:SetWordWrap(false)
	panel.zone = E:CreateText(panel, size.body, "LEFT")
	panel.zone:SetPoint("TOPLEFT", panel.destination, "BOTTOMLEFT", 0, -8)
	panel.zone:SetWordWrap(false)
	panel.coords = E:CreateText(panel, size.small, "LEFT")
	panel.coords:SetPoint("TOPLEFT", panel.zone, "BOTTOMLEFT", 0, -4)

	-- The one bold thing: the time left.
	panel.left = E:CreateText(panel, size.hero, "CENTER")
	panel.left:SetPoint("TOP", panel, "TOP", 0, -18)
	panel.arrival = E:CreateText(panel, size.label, "CENTER")
	panel.arrival:SetPoint("TOP", panel.left, "BOTTOM", 0, -4)
	panel.route = M.CreateRoute(panel)
	panel.route:SetSize(ROUTE_WIDTH, 24)
	panel.route:SetPoint("BOTTOM", panel, "BOTTOM", 0, 10)
	-- The view says the destination and the time itself.
	panel.route.title:Hide()
	panel.route.time:Hide()

	local Kit = E.UIKit
	local width = 112
	panel.exit = Kit.Button(panel, { text = L["Exit"], width = width, kind = "primary",
		onClick = function() M:CloseFlightView("exit") end })
	panel.exit:SetPoint("BOTTOMRIGHT", -24, 20)
	panel.land = Kit.Button(panel, { text = L["Land early"], width = width,
		onClick = function() M:LandEarly() end })
	panel.land:SetPoint("RIGHT", panel.exit, "LEFT", -8, 0)
	panel.bags = Kit.Button(panel, { text = L["Bags"], width = width,
		onClick = function() M:CloseFlightView("bags") if ToggleAllBags then ToggleAllBags() end end })
	panel.bags:SetPoint("BOTTOM", panel.exit, "TOP", 0, 8)
	-- The map opens through the game's own map button (Kit.GameButton), so
	-- the game opens it; without that button EldoUI opens it.
	panel.map = Kit.Button(panel, { text = L["Map"], width = width,
		secureClick = function() return Kit.GameButton("worldmap") end,
		onClick = function(button)
			M:CloseFlightView("map")
			if not button.secureTarget and ToggleWorldMap then ToggleWorldMap() end
		end })
	panel.map:SetPoint("RIGHT", panel.bags, "LEFT", -8, 0)
	if preview then
		for _, button in ipairs({ panel.exit, panel.land, panel.bags, panel.map }) do button:EnableMouse(false) end
	end
end

-- The left texts get the room between the panel's edge and the route.
local function FitLeft(panel)
	local width = math.max(160, (panel:GetWidth() or 0) / 2 - (panel.route:GetWidth() or ROUTE_WIDTH) / 2 - 40)
	panel.destination:SetWidth(width)
	panel.zone:SetWidth(width)
end

local function StylePanel(panel)
	FitLeft(panel)
	panel.flying:SetTextColor(E:TokenColor("secondary"))
	panel.flying:SetText(L["Flying to"])
	panel.destination:SetTextColor(E:TokenColor("body"))
	panel.zone:SetTextColor(E:TokenColor("secondary"))
	panel.coords:SetTextColor(E:TokenColor("secondary"))
	panel.left:SetTextColor(E:TokenColor("accent"))
	panel.arrival:SetTextColor(E:TokenColor("secondary"))
	E:SetPanelTemplate(panel.route, true)
end

-- Draw `data` ({ destination, known, stops, marks }) `elapsed` seconds in.
local function DrawPanel(panel, data, elapsed, zone, coords)
	panel.destination:SetText(data and data.destination or L["Flight path"])
	panel.zone:SetText(zone or "")
	panel.coords:SetText(coords or "")
	local known = data and tonumber(data.known)
	if known and known > 0 then
		local left = math.max(known - elapsed, 0)
		panel.left:SetText(E:FormatDuration(left, "minutes", "round"))
		panel.arrival:SetText(L["Lands at %s"]:format(E:FormatTime(time() + math.floor(left + 0.5))))
	else
		panel.left:SetText(E:FormatDuration(math.max(elapsed, 0), "minutes", "round"))
		panel.arrival:SetText(L["First flight on this route: learning its time"])
	end
	if data then
		panel.route:Show()
		M.DrawRoute(panel.route, data, elapsed)
	else
		panel.route:Hide()
	end
end

local function Draw()
	if not (view and view:IsShown()) then return end
	local flight = M:CurrentFlight()
	local elapsed = flight and flight.started and (GetTime() - flight.started) or 0
	DrawPanel(view.panel, flight, elapsed, ZoneText(), CoordsText())
	local land = view.panel.land
	if land.landing then return end
	land:SetEnabled(OnTaxi() and not InCombatLockdown() and type(TaxiRequestEarlyLanding) == "function")
end

local function CreateView()
	view = E.ScreenShell.Create("EldoUI_FlightView", false)
	BuildPanel(view.panel)
	local since = 0
	view:SetScript("OnUpdate", function(_, elapsed)
		since = since + (elapsed or 0)
		if since < REDRAW then return end
		since = 0
		Draw()
	end)
	-- However it goes (Esc, a button, combat, landing), the interface comes back.
	view:SetScript("OnHide", function()
		E.ScreenShell.FadeUI(OWNER, false)
		if not M.closing then M:NoteFlightViewClosed("exit") end
	end)
	M.flightView = view
end

---------------------------------------------------------------------------
-- Open and close
---------------------------------------------------------------------------
-- Closed by the player (or a queue, a ready check, combat) for this flight:
-- it stays away until the next one, a reload included.
function M:NoteFlightViewClosed(reason)
	if reason == "landed" then return end
	local saved = SavedFlight()
	if saved then saved.viewClosed = true end
	self.flightViewClosed = true
end

function M:OpenFlightView()
	if not (self.active and self.db.flightView) or InCombatLockdown() then return end
	if not view then CreateView() end
	E.ScreenShell.Style(view, self.db.flightViewDim, PANEL_HEIGHT)
	StylePanel(view.panel)
	view.panel.land.landing = nil
	view.panel.land:SetText(L["Land early"])
	view:SetAlpha(1)
	view:Show()
	E.ScreenShell.FadeUI(OWNER, true)
	Draw()
end

function M:CloseFlightView(reason)
	if reason then self:NoteFlightViewClosed(reason) end
	if view and view:IsShown() then
		self.closing = true
		view:Hide()
		self.closing = nil
	end
	E.ScreenShell.FadeUI(OWNER, false)
end

function M:IsFlightViewShown()
	return view ~= nil and view:IsShown()
end

-- From the flight timer's taxi checks (take-off, landing, a reload).
function M:UpdateFlightView()
	if not OnTaxi() then
		self.flightViewClosed = nil
		if view and view:IsShown() then self:CloseFlightView("landed") end
		return
	end
	local saved = SavedFlight()
	if saved and saved.viewClosed then self.flightViewClosed = true end
	if self.flightViewClosed or (view and view:IsShown()) then return end
	self:OpenFlightView()
end

-- "Land early": only from the player's click, out of combat, on a taxi.
function M:LandEarly()
	if InCombatLockdown() or not OnTaxi() or type(TaxiRequestEarlyLanding) ~= "function" then return end
	TaxiRequestEarlyLanding()
	if view then
		local land = view.panel.land
		land.landing = true
		land:SetText(L["Landing..."])
		land:SetEnabled(false)
	end
end

local function OnEvent(_, event, ...)
	if event == "PLAYER_REGEN_DISABLED" then
		M:CloseFlightView("combat")
	elseif event == "READY_CHECK" then
		M:CloseFlightView("ready")
	elseif QUEUE_EVENTS[event] and M.db.flightViewExitOnQueue then
		if event == "UPDATE_BATTLEFIELD_STATUS" then
			local index = ...
			local ok, status = pcall(GetBattlefieldStatus, index)
			if not ok or status ~= "confirm" then return end
		end
		M:CloseFlightView("queue")
	end
end

function M:EnableFlightView()
	events:SetScript("OnEvent", OnEvent)
	for _, event in ipairs({ "PLAYER_REGEN_DISABLED", "READY_CHECK", "LFG_PROPOSAL_SHOW", "UPDATE_BATTLEFIELD_STATUS" }) do
		pcall(events.RegisterEvent, events, event)
	end
end

function M:RefreshFlightView()
	if not (view and view:IsShown()) then return end
	if not self.db.flightView then
		self:CloseFlightView()
		return
	end
	E.ScreenShell.Style(view, self.db.flightViewDim, PANEL_HEIGHT)
	StylePanel(view.panel)
	Draw()
end

-- Module off: the view goes and the interface comes back.
function M:DisableFlightView()
	events:UnregisterAllEvents()
	self:CloseFlightView()
end

---------------------------------------------------------------------------
-- Options
---------------------------------------------------------------------------
local function Preview()
	return { type = "preview", label = "Flight view preview", height = PANEL_HEIGHT + 8,
		desc = "The flight view's panel with a sample flight, in your art style and accent.",
		create = function(frame)
			if not frame then return end
			local panel = CreateFrame("Frame", nil, frame)
			panel:SetPoint("TOPLEFT", 0, -4)
			panel:SetPoint("TOPRIGHT", 0, -4)
			panel:SetHeight(PANEL_HEIGHT)
			-- The real panel spans the screen; the sample is drawn at the
			-- width of the page.
			panel.line = panel:CreateTexture(nil, "ARTWORK")
			panel.line:SetPoint("TOPLEFT", 0, 0)
			panel.line:SetPoint("TOPRIGHT", 0, 0)
			BuildPanel(panel, true)
			panel.route:SetWidth(ROUTE_WIDTH * 0.6)
			frame.flightPanel = panel
			local start = GetTime()
			panel:SetScript("OnUpdate", function(self)
				local sample = M.FlightSample
				local elapsed = (GetTime() - start) % (sample.known + 3)
				DrawPanel(self, sample, math.min(elapsed, sample.known), L["Loch Modan"], "33.9, 50.9")
			end)
		end,
		update = function(frame)
			local panel = frame and frame.flightPanel
			if not panel then return end
			E:SetPanelTemplate(panel)
			panel.line:SetHeight(E.pixel * 2)
			E:AccentTexture(panel.line, 1)
			StylePanel(panel)
			DrawPanel(panel, M.FlightSample, M.FlightSample.known * 0.4, L["Loch Modan"], "33.9, 50.9")
		end }
end

M:AddOptions("Travel", {
	{ type = "header", label = "Flight view" },
	{ type = "toggle", key = "flightView", label = "Calm screen while flying",
		desc = "On a flight path the interface fades to one calm panel with where you fly, the time left and buttons for the map and bags. Landing or combat brings it back. Off by default." },
	Preview(),
	{ type = "toggle", key = "flightViewExitOnQueue", label = "Leave it when a queue pops", dependsOn = "flightView",
		desc = "A dungeon or battleground invite brings the interface back at once, so you can answer it." },
	{ type = "range", percent = true, key = "flightViewDim", label = "Darken the world", dependsOn = "flightView",
		desc = "How dark the world behind the flight view gets.", min = 0, max = 0.6, step = 0.05 },
	{ type = "execute", label = "Show it now", dependsOn = "flightView",
		desc = "Opens the flight view while you are on a flight path.",
		disabled = function() return not OnTaxi() and L["Only while you fly a flight path"] or false end,
		func = function()
			M.flightViewClosed = nil
			local saved = SavedFlight()
			if saved then saved.viewClosed = nil end
			M:OpenFlightView()
		end },
})
