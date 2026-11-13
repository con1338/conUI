-- EldoUI Waypoints: /way coordinates, a waypoint list per character, a
-- direction arrow with distance and arrival time, and pins on the world map
-- and minimap (Map.lua), and the Waypoints window (List.lua).
--
-- Rules (WoW: Forever, Midnight restrictions): the arrow only reads the
-- player's own map position and facing, which the game gives addons in the
-- open world and hides in instances. When it is hidden the arrow says so and
-- shows nothing it would have to guess. Nothing here moves, targets or acts
-- for the player: arriving only removes the waypoint (an option) and points
-- the arrow at the next one.
--
-- Other modules and plugins:
--   local W = EldoUI:GetModule("Waypoints")
--   local uid = W:Add(uiMapID, x, y, { title = "Weapon master", persistent = false })
--   W:SetArrow(uid); W:Remove(uid); W:RemoveAll(uiMapID)
local _, E = ...
local L = E.L

local issecret = issecretvalue or function() return false end
local atan2, sqrt, abs, pi, floor = math.atan2 or math.atan, math.sqrt, math.abs, math.pi, math.floor

local M = E:NewModule("Waypoints", {
	title = "Waypoints",
	category = "Quality of Life",
	desc = "Set waypoints with /way or a Ctrl+right-click on the world map, and follow an arrow with distance and arrival time. Pins on the world map and minimap.",
	conflicts = { "TomTom" },
	frames = { "EldoUI_WaypointArrow", "EldoUI_WaypointArrowHolder", "EldoUI_WaypointCoords", "EldoUI_WaypointCoordsHolder" },
	movers = { "EldoUI_WaypointArrow", "EldoUI_WaypointCoords" },
	savedKeys = { "profile.modules.Waypoints" },
	optionsPage = "module:Waypoints",
	presets = { "Accent", "Compact", "Large", "PinsOnly", "Quiet", "Standard" },
	reload = false,
	defaults = {
		arrow = true,
		arrowSize = 48,
		showTitle = true,
		showDistance = true,
		showETA = true,
		headingColours = true,  -- green ahead, yellow to the side, red behind
		arrivalDistance = 10,   -- yards
		clearOnArrival = true,
		autoNext = true,        -- point at the closest waypoint left after arriving
		arrivalSound = "none",
		announce = true,        -- a chat line when a waypoint is added or reached
		worldPins = true,
		minimapPins = true,
		pinSize = 16,
		mapClick = true,        -- Ctrl+right-click on the world map adds one
		gamePin = true,         -- also set the game's own map pin on the arrow's waypoint
		useGamePin = true,      -- the game's map pin (Ctrl+click) becomes a waypoint
		persistent = true,      -- keep waypoints between sessions
		corpseArrow = true,     -- as a ghost, point the arrow at your corpse
		hideInInstance = true,  -- hide the arrow and coordinates in dungeons, raids and battlegrounds
		distanceUnit = "yards", -- "yards" or "metres"
		pinStyle = "diamond",   -- "diamond", "square" or "round"
		coordBox = true,        -- a small box with your coordinates; click it to type a waypoint
		visibility = E:VisibilityDefaults(), -- the shared visibility rules (arrow and coordinate box)
		listSort = "distance",  -- the Waypoints window: "distance" or "added"
	},
})
E.Waypoints = M
-- Both boxes follow the module's one visibility block.
E:RegisterVisibilityFacet("EldoUI_WaypointArrow", "rules", { module = "Waypoints", setting = "visibility" })
E:RegisterVisibilityFacet("EldoUI_WaypointCoords", "rules", { module = "Waypoints", setting = "visibility" })

---------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------
local function Try(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a, b, c = pcall(fn, ...)
	if ok then return a, b, c end
end

local Clean = E.Plain

local function Accent()
	local r, g, b = unpack(E.media.accentColor)
	return ("|cff%02x%02x%02x"):format(r * 255, g * 255, b * 255)
end
M.Accent = Accent

-- Theme text colors from the UI kit (TEXT, SECONDARY, DIM, BAD).
local function Shade(kind)
	local Kit = E.UIKit
	local c = Kit and Kit[kind] or { 1, 1, 1 }
	return c[1], c[2], c[3]
end
M.Shade = Shade

function M:Say(text)
	if self.db.announce then E:Print(text) end
end

-- World position of a map point: continent id and yards (north, west),
-- the game's own world axes. A map's world position is a straight-line
-- function of its x and y, so each map is measured once (three corners)
-- and every point after that is plain arithmetic: no vectors and no call
-- into the game. A map the game can't measure is asked point by point,
-- one vector reused for the question and the last answer kept.
local scratch
local last = {}
local function AskWorld(mapID, x, y)
	if last.mapID == mapID and last.x == x and last.y == y then
		return last.continent, last.north, last.west
	end
	if scratch and scratch.SetXY then
		scratch:SetXY(x, y)
	else
		scratch = CreateVector2D(x, y)
	end
	local continent, position = Try(C_Map.GetWorldPosFromMapPos, mapID, scratch)
	if not Clean(continent) or type(position) ~= "table" or not position.GetXY then return nil end
	local north, west = position:GetXY()
	if not Clean(north) or not Clean(west) then return nil end
	last.mapID, last.x, last.y = mapID, x, y
	last.continent, last.north, last.west = continent, north, west
	return continent, north, west
end

-- mapID -> { continent, north, west at 0,0; north and west per x; per y },
-- or false. Kept for the session (measured again if the game's function
-- is replaced).
local rects, rectSource = {}, nil
local function MapRect(mapID)
	local source = C_Map.GetWorldPosFromMapPos
	if source ~= rectSource then
		wipe(rects)
		rectSource = source
	end
	local rect = rects[mapID]
	if rect ~= nil then return rect end
	rect = false
	local c0, n0, w0 = AskWorld(mapID, 0, 0)
	local c1, n1, w1 = AskWorld(mapID, 1, 0)
	local c2, n2, w2 = AskWorld(mapID, 0, 1)
	if c0 and c0 == c1 and c0 == c2 then
		rect = { c0, n0, w0, n1 - n0, w1 - w0, n2 - n0, w2 - w0 }
	end
	rects[mapID] = rect
	M.mapRects = (M.mapRects or 0) + 1
	return rect
end

function M.WorldPos(mapID, x, y)
	if not (C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return nil end
	if mapID == nil or type(x) ~= "number" or type(y) ~= "number" then return nil end
	local rect = MapRect(mapID)
	if rect then
		return rect[1], rect[2] + x * rect[4] + y * rect[6], rect[3] + x * rect[5] + y * rect[7]
	end
	return AskWorld(mapID, x, y)
end

-- The answer the game gives, point by point (for the check that the
-- arithmetic above matches it).
function M.AskWorldPos(mapID, x, y)
	if not (C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return nil end
	last.mapID = nil
	return AskWorld(mapID, x, y)
end

-- The player's map, map x/y and world position. Nil where the game hides
-- the position (instances, some restricted areas). Every read is kept for
-- the rest of its frame, for M.SharedPlayerPos below.
local shared = {}
local function ReadPlayerPos()
	if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then return nil end
	local mapID = Clean(Try(C_Map.GetBestMapForUnit, "player"))
	if not mapID then return nil end
	local position = Try(C_Map.GetPlayerMapPosition, mapID, "player")
	if type(position) ~= "table" or not position.GetXY then return nil end
	local x, y = position:GetXY()
	x, y = Clean(x), Clean(y)
	if not x or not y or (x == 0 and y == 0) then return nil end
	local continent, north, west = M.WorldPos(mapID, x, y)
	return mapID, x, y, continent, north, west
end

function M.PlayerPos()
	M.playerReads = (M.playerReads or 0) + 1
	shared.at = GetTime()
	shared[1], shared[2], shared[3], shared[4], shared[5], shared[6] = ReadPlayerPos()
	return shared[1], shared[2], shared[3], shared[4], shared[5], shared[6]
end

-- The same for the tickers (the coordinate box, the minimap pins of every
-- map module, the guide's arrival check): a read already made on this
-- frame (the arrow's, or another ticker's) is used again.
function M.SharedPlayerPos()
	if shared.at ~= GetTime() then return M.PlayerPos() end
	return shared[1], shared[2], shared[3], shared[4], shared[5], shared[6]
end

function M.MapName(mapID)
	local info = mapID and C_Map and Try(C_Map.GetMapInfo, mapID)
	local name = info and Clean(info.name)
	return (name and name ~= "") and name or L["Map %s"]:format(tostring(mapID))
end

local function FormatCoords(x, y)
	return ("%.1f, %.1f"):format(x * 100, y * 100)
end
M.FormatCoords = FormatCoords

-- Distance in the unit the player picked (the game's own unit is yards).
local YARD = 0.9144
local function FormatDistance(yards)
	if M.db and M.db.distanceUnit == "metres" then
		local metres = yards * YARD
		if metres >= 1000 then return L["%.1f km"]:format(metres / 1000) end
		return L["%d m"]:format(floor(metres + 0.5))
	end
	if yards >= 1000 then return L["%.1fk yd"]:format(yards / 1000) end
	return L["%d yd"]:format(floor(yards + 0.5))
end
M.FormatDistance = FormatDistance

local function FormatTime(seconds) return E:FormatDuration(seconds, "clock", "round") end

---------------------------------------------------------------------------
-- Waypoint store. Saved per character in E.private.Waypoints.points;
-- waypoints added with persistent = false live only this session.
---------------------------------------------------------------------------
M.points = {}      -- uid -> waypoint
M.order = {}       -- uids in the order they were added
local nextUid = 0

local function Store()
	return E:GetPrivate("Waypoints") or { points = {} }
end

function M:Save()
	local store = Store()
	store.points = {}
	if not self.db.persistent then return end
	for _, uid in ipairs(self.order) do
		local wp = self.points[uid]
		if wp and wp.persistent then
			store.points[#store.points + 1] = { m = wp.mapID, x = wp.x, y = wp.y, t = wp.title, a = (self.arrowUid == uid) or nil }
		end
	end
end

function M:Load()
	local store = Store()
	local arrowUid
	for _, saved in ipairs(store.points or {}) do
		if type(saved) == "table" and type(saved.m) == "number" and type(saved.x) == "number" and type(saved.y) == "number" then
			local uid = self:Add(saved.m, saved.x, saved.y, { title = saved.t, silent = true, noArrow = true, noSave = true })
			if saved.a then arrowUid = uid end
		end
	end
	if arrowUid then self:SetArrow(arrowUid) elseif #self.order > 0 then self:SetArrow(self:Closest()) end
end

function M:Get(uid) return self.points[uid] end

function M:Iterate()
	local i = 0
	return function()
		i = i + 1
		local uid = self.order[i]
		if uid then return uid, self.points[uid] end
	end
end

local function RefreshArrowTitle(self)
	local wp = self.arrowUid and self.points[self.arrowUid]
	if self.arrowFrame then
		self.arrowFrame.title:SetText(wp and (wp.title or FormatCoords(wp.x, wp.y)) or "")
	end
end

-- Add a waypoint. x and y are 0-1 map coordinates. opts: title, persistent
-- (default true), silent, noArrow (don't point the arrow at it), source.
function M:Add(mapID, x, y, opts)
	opts = opts or {}
	-- Titles from other addons can be secret values: drop those.
	if type(opts.title) ~= "string" or issecret(opts.title) then opts.title = nil end
	if type(mapID) ~= "number" or type(x) ~= "number" or type(y) ~= "number" then return nil end
	if x < 0 or x > 1 or y < 0 or y > 1 then return nil end
	-- The same spot twice is one waypoint. The corpse waypoint is always its
	-- own (it must not rename a waypoint of yours, and is removed on revive).
	-- Only you rename any waypoint; another source (the game's map pin, the
	-- Loot Guide, Map Notes) renames only its own.
	if opts.source ~= "corpse" then
		for uid, wp in self:Iterate() do
			if wp.source ~= "corpse" and wp.mapID == mapID and abs(wp.x - x) < 0.0005 and abs(wp.y - y) < 0.0005 then
				local renamed = opts.title and opts.title ~= "" and opts.title ~= wp.title
					and (opts.source == nil or opts.source == wp.source)
				if renamed then
					wp.title = opts.title
					if self.arrowUid == uid then RefreshArrowTitle(self) end
				end
				if not opts.noArrow and self.arrowUid ~= uid then self:SetArrow(uid) end
				if renamed and not opts.noSave then self:Save() end
				return uid
			end
		end
	end
	nextUid = nextUid + 1
	local continent, north, west = M.WorldPos(mapID, x, y)
	local wp = {
		uid = nextUid, mapID = mapID, x = x, y = y,
		title = (opts.title and opts.title ~= "") and opts.title or nil,
		persistent = opts.persistent ~= false, source = opts.source,
		continent = continent, north = north, west = west,
	}
	self.points[nextUid] = wp
	self.order[#self.order + 1] = nextUid
	if not opts.silent then
		self:Say(L["Waypoint added: %s, %s %s"]:format(Accent() .. (wp.title or L["waypoint"]) .. "|r", M.MapName(mapID), FormatCoords(x, y)))
	end
	if not opts.noArrow or not self.arrowUid then self:SetArrow(nextUid) end
	if not opts.noSave then self:Save() end
	self:RefreshPins()
	return nextUid
end

function M:Remove(uid, silent)
	local wp = self.points[uid]
	if not wp then return end
	self.points[uid] = nil
	for i, other in ipairs(self.order) do
		if other == uid then table.remove(self.order, i) break end
	end
	if not silent then self:Say(L["Waypoint removed: %s"]:format(wp.title or FormatCoords(wp.x, wp.y))) end
	if self.arrowUid == uid then
		self:SetArrow(self.db.autoNext and self:Closest() or nil)
	end
	self:Save()
	self:RefreshPins()
end

-- Remove every waypoint, or every one on one map.
function M:RemoveAll(mapID)
	local removed = 0
	for i = #self.order, 1, -1 do
		local uid = self.order[i]
		local wp = self.points[uid]
		if not mapID or (wp and wp.mapID == mapID) then
			self.points[uid] = nil
			table.remove(self.order, i)
			removed = removed + 1
		end
	end
	if self.arrowUid and not self.points[self.arrowUid] then self:SetArrow(self:Closest()) end
	self:Save()
	self:RefreshPins()
	return removed
end

-- How many waypoints there are, or how many on one map.
function M:CountOn(mapID)
	local count = 0
	for _, uid in ipairs(self.order) do
		local wp = self.points[uid]
		if not mapID or (wp and wp.mapID == mapID) then count = count + 1 end
	end
	return count
end

-- Remove every waypoint (or every one on one map) after a question naming
-- the count, so one misclick in a menu doesn't throw away a pasted route.
-- say: print how many went (the /way command).
function M:AskRemoveAll(mapID, say)
	local count = self:CountOn(mapID)
	if count == 0 then return end
	E:ShowConfirm({ key = "ELDOUI_WAYPOINTS_RESET", title = L["Waypoints"],
		text = E:Plural(count, L["Remove %d waypoint? This can't be undone."], L["Remove %d waypoints? This can't be undone."]):format(count),
		accept = L["Remove"], danger = true,
		onAccept = function()
			local removed = M:RemoveAll(mapID)
			if say then E:Print(E:Plural(removed, L["%d waypoint removed."], L["%d waypoints removed."]):format(removed)) end
		end })
end

-- Straight-line yards from the player, or nil (other continent, no position).
function M:Distance(wp)
	local _, _, _, continent, north, west = M.PlayerPos()
	if not continent or not wp.continent or continent ~= wp.continent then return nil end
	local dn, dw = wp.north - north, wp.west - west
	return sqrt(dn * dn + dw * dw), dn, dw
end

function M:Closest()
	local best, bestDistance
	for uid, wp in self:Iterate() do
		local distance = self:Distance(wp)
		if distance and (not bestDistance or distance < bestDistance) then best, bestDistance = uid, distance end
	end
	return best or self.order[1]
end

---------------------------------------------------------------------------
-- The game's own map pin (user waypoint and super-track). Only the arrow's
-- waypoint is mirrored; the player's own Ctrl+click pin can become one of ours.
---------------------------------------------------------------------------
function M:SyncGamePin()
	local mapPoint = rawget(_G, "UiMapPoint")
	if not (self.db.gamePin and C_Map and C_Map.SetUserWaypoint and mapPoint and mapPoint.CreateFromCoordinates) then return end
	local wp = self.arrowUid and self.points[self.arrowUid]
	if not wp then
		if self.ownGamePin and C_Map.ClearUserWaypoint then
			self.settingGamePin = true
			Try(C_Map.ClearUserWaypoint)
			self.settingGamePin = nil
		end
		self.ownGamePin = nil
		return
	end
	if C_Map.CanSetUserWaypointOnMap and not Try(C_Map.CanSetUserWaypointOnMap, wp.mapID) then return end
	local point = Try(mapPoint.CreateFromCoordinates, wp.mapID, wp.x, wp.y)
	if not point then return end
	self.settingGamePin = true
	Try(C_Map.SetUserWaypoint, point)
	if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then Try(C_SuperTrack.SetSuperTrackedUserWaypoint, true) end
	self.settingGamePin = nil
	self.ownGamePin = true
end

function M:OnGamePinChanged()
	if self.settingGamePin or not self.db.useGamePin then return end
	if not (C_Map and C_Map.HasUserWaypoint and C_Map.GetUserWaypoint) or not Try(C_Map.HasUserWaypoint) then return end
	local point = Try(C_Map.GetUserWaypoint)
	if type(point) ~= "table" or not point.uiMapID or not point.position then return end
	local x, y = point.position.x, point.position.y
	if point.position.GetXY then x, y = point.position:GetXY() end
	if type(x) ~= "number" or type(y) ~= "number" then return end
	self.ownGamePin = true
	-- The event for our own SetUserWaypoint can arrive after settingGamePin is
	-- cleared: the pin on the arrow's waypoint is ours, nothing to add.
	local arrow = self.arrowUid and self.points[self.arrowUid]
	if arrow and arrow.mapID == point.uiMapID and abs(arrow.x - x) < 0.0005 and abs(arrow.y - y) < 0.0005 then return end
	self:Add(point.uiMapID, x, y, { title = "Map pin", source = "game" })
end

---------------------------------------------------------------------------
-- Arrow
---------------------------------------------------------------------------
-- Heading colors: ahead, to the side, behind (meaning colors, the same in
-- every theme, like EldoUI's health and threat colors).
local AHEAD, SIDE, BEHIND = { 0.3, 0.9, 0.3 }, { 1, 0.82, 0.2 }, { 0.95, 0.3, 0.25 }

local function Blend(a, b, t)
	return a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t
end

function M:BuildArrow()
	if self.arrowFrame then return end
	local frame = CreateFrame("Button", "EldoUI_WaypointArrow", UIParent)
	frame:SetSize(self.db.arrowSize, self.db.arrowSize)
	frame:SetFrameStrata("MEDIUM")
	frame:RegisterForClicks("RightButtonUp")
	frame.icon = frame:CreateTexture(nil, "ARTWORK")
	frame.icon:SetAllPoints()
	-- The game's own minimap player arrow, rotated to the heading.
	frame.icon:SetTexture("Interface\\Minimap\\MinimapArrow")
	frame.title = E:CreateText(frame, E.tokens.size.section)
	frame.title:SetPoint("TOP", frame, "BOTTOM", 0, -2)
	frame.info = E:CreateText(frame, E.tokens.size.label)
	frame.info:SetPoint("TOP", frame.title, "BOTTOM", 0, -1)
	frame.info:SetTextColor(Shade("SECONDARY"))
	frame:SetScript("OnClick", function(f, button) if button == "RightButton" then M:ArrowMenu(f) end end)
	frame:SetScript("OnEnter", function(f) M:ArrowTooltip(f) end)
	frame:SetScript("OnLeave", GameTooltip_Hide)
	E:BindOptionsLink(frame, { page = "module:Waypoints", key = "arrow" })
	frame:Hide()
	self.arrowFrame = frame

	local holder = CreateFrame("Frame", "EldoUI_WaypointArrowHolder", UIParent)
	holder:SetSize(160, self.db.arrowSize + 34)
	frame:SetPoint("TOP", holder, "TOP", 0, 0)
	self.arrowHolder = holder
	E:CreateMover(holder, "EldoUI_WaypointArrow", "Waypoint Arrow", { "TOP", "UIParent", "TOP", 0, -120 })
end

function M:LayoutArrow()
	local frame, db = self.arrowFrame, self.db
	if not frame then return end
	frame:SetSize(db.arrowSize, db.arrowSize)
	self.arrowHolder:SetSize(160, db.arrowSize + 34)
	E:SetFont(frame.title, db.arrowSize >= 40 and 13 or 11)
	E:SetFont(frame.info, db.arrowSize >= 40 and 12 or 10)
	frame.title:SetShown(db.showTitle)
	frame.info:ClearAllPoints()
	if db.showTitle then
		frame.info:SetPoint("TOP", frame.title, "BOTTOM", 0, -1)
	else
		frame.info:SetPoint("TOP", frame, "BOTTOM", 0, -2)
	end
	self:UpdateArrowShown()
end

-- Inside a dungeon, raid or battleground the game hides your position, so
-- with "Hide in instances" the arrow (and the coordinate box) go away there
-- instead of showing an arrow that can't point anywhere.
function M:HiddenHere()
	if not (self.db.hideInInstance and IsInInstance) then return false end
	return Clean(Try(IsInInstance)) and true or false
end

-- The arrow turns with you on the shared ticker, only while it shows.
local ARROW_TICK = "Waypoints:arrow"
local ELAPSED_STEP = 0.05

function M:UpdateArrowShown()
	local frame = self.arrowFrame
	if not frame then return end
	local show = self.active and self.db.arrow and self.arrowUid ~= nil and self.points[self.arrowUid] ~= nil and not self.arrowHidden and not self:HiddenHere()
	frame:SetShown(show)
	if self.arrowHolder then self.arrowHolder:SetShown(self.active and self.db.arrow) end
	if show then
		if not E.Ticker:IsSubscribed(ARROW_TICK) then
			E.Ticker:Subscribe(ARROW_TICK, ELAPSED_STEP, function(elapsed) M:OnArrowUpdate(elapsed) end, M)
		end
	else
		E.Ticker:Unsubscribe(ARROW_TICK)
	end
end

-- The arrow and the coordinate box follow the shared visibility rules.
function M:ApplyVisibility()
	local block = self.db.visibility
	if type(block) ~= "table" then
		block = E:VisibilityDefaults()
		self.db.visibility = block
	end
	for _, holder in ipairs({ self.arrowHolder, self.coordHolder }) do
		if self.visibilityBlock ~= block then E:DetachVisibility(holder) end
		if E:IsVisibilityAttached(holder) then
			E:UpdateVisibility(holder)
		else
			E:AttachVisibility(holder, block, { forceShow = function() return E:IsMoveMode() end })
		end
	end
	self.visibilityBlock = block
end

function M:SetArrow(uid)
	self.arrowUid = uid
	self.arrowHidden = nil
	self.lastDistance, self.speed, self.arrived = nil, nil, nil
	RefreshArrowTitle(self)
	self:UpdateArrowShown()
	self:SyncGamePin()
	self:RefreshPins()
end

function M:OnArrowUpdate(elapsed)
	self.arrowElapsed = (self.arrowElapsed or 0) + elapsed
	if self.arrowElapsed < ELAPSED_STEP then return end
	local step = self.arrowElapsed
	self.arrowElapsed = 0
	local frame, db = self.arrowFrame, self.db
	local wp = self.arrowUid and self.points[self.arrowUid]
	if not wp then self:UpdateArrowShown() return end

	local _, _, _, continent, north, west = M.PlayerPos()
	if not continent then
		-- Inside an instance the game names the map but hides where you are.
		local here = C_Map and Clean(Try(C_Map.GetBestMapForUnit, "player"))
		frame.icon:SetRotation(0)
		frame.icon:SetVertexColor(Shade("DIM"))
		frame.info:SetText(here and L["No position here"] or L["No position in this area"])
		self.lastDistance = nil
		return
	end
	if not wp.continent then
		wp.continent, wp.north, wp.west = M.WorldPos(wp.mapID, wp.x, wp.y)
	end
	if wp.continent ~= continent then
		frame.icon:SetRotation(0)
		frame.icon:SetVertexColor(Shade("DIM"))
		frame.info:SetText(M.MapName(wp.mapID))
		self.lastDistance = nil
		return
	end

	local dn, dw = wp.north - north, wp.west - west
	local distance = sqrt(dn * dn + dw * dw)
	if distance <= db.arrivalDistance then
		self:Arrive(wp)
		return
	end

	-- Bearing and facing both count anticlockwise from north.
	local facing = Clean(GetPlayerFacing and Try(GetPlayerFacing))
	if facing then
		local angle = (atan2(dw, dn) - facing) % (2 * pi)
		self.angle = angle
		frame.icon:SetRotation(angle)
		if db.headingColours then
			local off = abs(angle > pi and angle - 2 * pi or angle) / pi -- 0 ahead, 1 behind
			if off < 0.5 then
				frame.icon:SetVertexColor(Blend(AHEAD, SIDE, off * 2))
			else
				frame.icon:SetVertexColor(Blend(SIDE, BEHIND, (off - 0.5) * 2))
			end
		else
			frame.icon:SetVertexColor(unpack(E.media.accentColor))
		end
	else
		frame.icon:SetRotation(0)
		frame.icon:SetVertexColor(Shade("DIM"))
	end

	-- Speed towards the waypoint, smoothed, for the arrival time.
	if self.lastDistance then
		local closing = (self.lastDistance - distance) / step
		self.speed = self.speed and (self.speed * 0.9 + closing * 0.1) or closing
	end
	self.lastDistance = distance
	local parts = {}
	if db.showDistance then parts[#parts + 1] = FormatDistance(distance) end
	if db.showETA and self.speed and self.speed > 0.5 then parts[#parts + 1] = FormatTime(distance / self.speed) end
	frame.info:SetText(table.concat(parts, "  "))
end

function M:Arrive(wp)
	if self.arrived == wp.uid then return end
	self.arrived = wp.uid
	self:Say(L["Arrived at %s."]:format(Accent() .. (wp.title or FormatCoords(wp.x, wp.y)) .. "|r"))
	if self.db.arrivalSound and self.db.arrivalSound ~= "none" then E:PlayMedia(self.db.arrivalSound) end
	if self.db.clearOnArrival then
		self:Remove(wp.uid, true)
	elseif self.db.autoNext then
		-- Keep it, but point at the closest other one.
		local best, bestDistance
		for uid, other in self:Iterate() do
			if uid ~= wp.uid then
				local distance = self:Distance(other)
				if distance and (not bestDistance or distance < bestDistance) then best, bestDistance = uid, distance end
			end
		end
		if best then self:SetArrow(best) else self.arrowFrame.info:SetText(L["Arrived"]) end
	else
		self.arrowFrame.info:SetText(L["Arrived"])
	end
end

function M:ArrowTooltip(owner)
	local wp = self.arrowUid and self.points[self.arrowUid]
	if not wp then return end
	GameTooltip:SetOwner(owner, "ANCHOR_BOTTOM")
	local r, g, b = Shade("SECONDARY")
	E.UIKit.TipTitle(GameTooltip, wp.title or L["Waypoint"])
	GameTooltip:AddLine(("%s %s"):format(M.MapName(wp.mapID), FormatCoords(wp.x, wp.y)), r, g, b)
	local distance = self:Distance(wp)
	if distance then GameTooltip:AddLine(FormatDistance(distance), r, g, b) end
	GameTooltip:AddLine(" ")
	E.UIKit.TipText(GameTooltip, L["Move it in move mode (Waypoint Arrow)."])
	E:TooltipHint(GameTooltip, { L["Right-click"], L["options"] })
	GameTooltip:Show()
end

function M:ArrowMenu(owner)
	local uid = self.arrowUid
	E.UIKit.ContextMenu(owner, function(_, root)
		root:CreateTitle(L["Waypoint"])
		root:CreateButton(L["Remove this waypoint"], function() if uid then M:Remove(uid) end end)
		root:CreateButton(L["Point at the closest"], function() M:SetArrow(M:Closest()) end)
		root:CreateButton(L["Type coordinates"], function() M:ShowEntry(owner) end)
		root:CreateButton(L["Waypoint list"], function() M:ShowList() end)
		root:CreateButton(L["Hide the arrow"], function() M.arrowHidden = true M:UpdateArrowShown() end)
		root:CreateDivider()
		root:CreateButton(L["Remove all waypoints"], function() M:AskRemoveAll() end)
	end)
end

---------------------------------------------------------------------------
-- /way parsing
---------------------------------------------------------------------------
local zoneIndex

local function Simplify(text)
	return (E:FoldText(text):gsub("%s", ""))
end

-- Map names to ids, built once on the first named /way. Zones win over
-- other map types with the same name.
local function ZoneIndex()
	if zoneIndex then return zoneIndex end
	zoneIndex = {}
	if not (C_Map and C_Map.GetMapInfo) then return zoneIndex end
	local rank = {}
	local zoneType = Enum and Enum.UIMapType and Enum.UIMapType.Zone or 3
	for mapID = 1, 3000 do
		local info = Try(C_Map.GetMapInfo, mapID)
		local name = info and Clean(info.name)
		if name and name ~= "" then
			local key = Simplify(name)
			local r = (info.mapType == zoneType) and 1 or 2
			if key ~= "" and (not rank[key] or r < rank[key]) then
				zoneIndex[key], rank[key] = mapID, r
			end
		end
	end
	return zoneIndex
end
M.ZoneIndex = ZoneIndex

local function FindMap(words)
	local text = Simplify(words)
	if text == "" then return nil end
	local index = ZoneIndex()
	if index[text] then return index[text] end
	-- A unique start: "/way elwynn 41 65".
	local found
	for key, mapID in pairs(index) do
		if key:sub(1, #text) == text then
			if found and found ~= mapID then return nil, "ambiguous" end
			found = mapID
		end
	end
	return found
end

-- "[zone or #mapID] x y [title]". Returns mapID, x, y, title or nil, error.
function M:Parse(text)
	text = strtrim(text or "")
	-- "45,2 63,8": decimal commas, as many European sites write them, not
	-- four numbers. "45,63" and "45, 63" stay an x and a y.
	text = text:gsub("(%d+),(%d+)(%s+)(%d+),(%d+)", "%1.%2%3%4.%5", 1)
	text = text:gsub("(%d),(%d)", "%1 %2"):gsub(",", " ")
	local tokens = {}
	for token in text:gmatch("%S+") do tokens[#tokens + 1] = token end
	-- The first pair of numbers is the coordinate; words before it name the map.
	local first
	for i = 1, #tokens - 1 do
		if tonumber(tokens[i]) and tonumber(tokens[i + 1]) then first = i break end
	end
	if not first then return nil, L["Give coordinates, like /way 45.2 63.8 or /way Elwynn Forest 45 63 Goldshire."] end
	local x, y = tonumber(tokens[first]), tonumber(tokens[first + 1])
	if x < 0 or x > 100 or y < 0 or y > 100 then return nil, L["Coordinates go from 0 to 100."] end
	local mapID
	local before = table.concat(tokens, " ", 1, first - 1)
	if before ~= "" then
		local id = before:match("^#(%d+)$")
		if id then
			mapID = tonumber(id)
		else
			local err
			mapID, err = FindMap(before)
			if not mapID then
				return nil, err == "ambiguous" and L["More than one map starts with \"%s\"; type more of the name."]:format(before)
					or L["No map called \"%s\"."]:format(before)
			end
		end
	else
		mapID = M.PlayerPos() or Clean(C_Map and Try(C_Map.GetBestMapForUnit, "player"))
		if not mapID then return nil, L["Name the map here, like /way Elwynn Forest 45 63."] end
	end
	local title = table.concat(tokens, " ", first + 2)
	return mapID, x / 100, y / 100, title ~= "" and title or nil
end

function M:List()
	if #self.order == 0 then
		E:Print(L["No waypoints. Add one with /way 45 63 or Ctrl+right-click on the world map."])
		return
	end
	E:Print(E:Plural(#self.order, L["%d waypoint:"], L["%d waypoints:"]):format(#self.order))
	for uid, wp in self:Iterate() do
		local distance = self:Distance(wp)
		E:Print(("%s %s %s %s%s"):format(uid == self.arrowUid and (Accent() .. ">|r") or " ", wp.title or L["waypoint"],
			M.MapName(wp.mapID), FormatCoords(wp.x, wp.y), distance and ("  " .. FormatDistance(distance)) or ""))
	end
end

-- The /way text for one waypoint (shared in chat by the player).
function M:WayText(wp)
	return ("/way #%d %s %s"):format(wp.mapID, FormatCoords(wp.x, wp.y):gsub(",", ""), wp.title or "")
end

-- The chat line "Share in chat" puts in the chat box. A line that starts
-- with /way would run as your own command when you press Enter, so the
-- /way text follows a label; /way paste reads it back from such a line.
function M:ShareText(wp)
	return L["Waypoint: %s"]:format(strtrim(self:WayText(wp)))
end

function M:Command(input)
	local word, rest = strtrim(input or ""):match("^(%S*)%s*(.-)$")
	word = (word or ""):lower()
	if word == "" or word == "help" then
		E:Print(L["/way [zone] x y [title]  add a waypoint (zone defaults to where you are)"])
		E:Print(L["/way list  ·  /way print  ·  /way closest  ·  /way arrow  ·  /way reset [zone|all]  ·  /way paste  ·  /way type"])
		return
	end
	if word == "paste" then return self:ShowPaste() end
	if word == "type" or word == "enter" then return self:ShowEntry() end
	if word == "list" then return self:ToggleList() end
	if word == "print" then return self:List() end
	if word == "closest" or word == "next" then
		local uid = self:Closest()
		if uid then self:SetArrow(uid) else E:Print(L["No waypoints."]) end
		return
	end
	if word == "arrow" then
		self.arrowHidden = not self.arrowHidden and self.arrowFrame and self.arrowFrame:IsShown() or nil
		self:UpdateArrowShown()
		return
	end
	if word == "reset" or word == "clear" then
		local mapID
		if rest ~= "" and rest:lower() ~= "all" then
			mapID = rest:match("^#(%d+)$") and tonumber(rest:match("^#(%d+)$")) or FindMap(rest)
			if not mapID then E:Print((L["No map called \"%s\"."]):format(rest)) return end
		end
		if self:CountOn(mapID) == 0 then
			E:Print(L["No waypoints."])
			return
		end
		self:AskRemoveAll(mapID, true)
		return
	end
	local mapID, x, y, title = self:Parse(input)
	if not mapID then E:Print(x) return end
	self:Add(mapID, x, y, { title = title })
end

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------
local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event)
	if not M.active then return end
	if event == "USER_WAYPOINT_UPDATED" then
		M:OnGamePinChanged()
	elseif event == "ZONE_CHANGED_NEW_AREA" or event == "PLAYER_ENTERING_WORLD" then
		M.lastDistance, M.speed = nil, nil
		M:UpdateCorpse()
		M:RefreshPins()
		M:UpdateArrowShown()
		M:UpdateCoordsShown()
	else -- PLAYER_DEAD, PLAYER_ALIVE, PLAYER_UNGHOST
		M:UpdateCorpse()
	end
end)

---------------------------------------------------------------------------
-- Corpse arrow: as a ghost, a waypoint on your corpse (from the game's own
-- corpse position), removed when you are alive again.
---------------------------------------------------------------------------
function M:UpdateCorpse()
	local ghost = UnitIsGhost and Clean(UnitIsGhost("player"))
	if not (ghost and self.db.corpseArrow) then
		if self.corpseUid then
			local uid = self.corpseUid
			self.corpseUid = nil
			if self.points[uid] then self:Remove(uid, true) end
		end
		return
	end
	local mapID = C_Map and C_Map.GetBestMapForUnit and Clean(Try(C_Map.GetBestMapForUnit, "player"))
	local position = mapID and C_DeathInfo and C_DeathInfo.GetCorpseMapPosition and Try(C_DeathInfo.GetCorpseMapPosition, mapID)
	if type(position) ~= "table" or not position.GetXY then return end
	local x, y = position:GetXY()
	x, y = Clean(x), Clean(y)
	if not (x and y) or (x == 0 and y == 0) then return end
	if self.corpseUid and self.points[self.corpseUid] then
		local wp = self.points[self.corpseUid]
		if wp.mapID == mapID and abs(wp.x - x) < 0.0005 and abs(wp.y - y) < 0.0005 then return end
		self:Remove(self.corpseUid, true)
	end
	self.corpseUid = self:Add(mapID, x, y, { title = L["Your corpse"], persistent = false, silent = true, source = "corpse" })
end

---------------------------------------------------------------------------
-- Paste window: many /way lines at once (from a guide or a friend)
---------------------------------------------------------------------------
-- Returns added, failed and the lines that were not understood (so the
-- paste window can leave them in the box to fix).
function M:AddLines(text)
	local added, failed, rejected = 0, 0, {}
	for raw in tostring(text or ""):gmatch("[^\r\n]+") do
		-- "/way ..." lines, also after a label ("Waypoint: /way #1429 45 63").
		local line = (raw:match("/%a*way%s+(.*)$") or raw):match("^%s*(.-)%s*$")
		if line ~= "" then
			local mapID, x, y, title = self:Parse(line)
			if mapID and self:Add(mapID, x, y, { title = title, silent = true, noArrow = true }) then
				added = added + 1
			else
				failed = failed + 1
				rejected[#rejected + 1] = raw
			end
		end
	end
	return added, failed, rejected
end

-- The result line in the paste window's footer.
function M.PasteResult(added, failed)
	local parts = {}
	if added > 0 then
		parts[#parts + 1] = E:TokenHex(E.tokens.text.good) .. E:Plural(added, L["%d waypoint added."], L["%d waypoints added."]):format(added) .. "|r"
	elseif failed == 0 then
		parts[#parts + 1] = E:TokenHex(E.tokens.text.secondary) .. L["Nothing to add: paste /way lines first."] .. "|r"
	end
	if failed > 0 then
		parts[#parts + 1] = E:TokenHex(E.tokens.text.warn)
			.. E:Plural(failed, L["%d line not understood (left in the box)."], L["%d lines not understood (left in the box)."]):format(failed) .. "|r"
	end
	return table.concat(parts, "  ")
end

-- The paste window: an EldoUI window (E.WindowKit) with a skinned scroll
-- bar, the theme font and kit buttons; Escape closes it.
function M:ShowPaste()
	local Kit = E.WindowKit
	local frame = self.pasteFrame
	if not frame then
		frame = Kit.CreateWindow("EldoUI_WaypointPaste", { width = 460, height = 360, strata = "DIALOG", footer = 40, headerHeight = 54, resizable = true })
		frame:SetTitle(L["Paste waypoints"], L["One per line, like /way Elwynn Forest 45 63 Goldshire. Lines shared from chat work too."])
		local content = frame.content
		local holder = CreateFrame("Frame", nil, content)
		holder:SetAllPoints(content)
		E:SetTemplate(holder, true)
		local scroll = CreateFrame("ScrollFrame", nil, holder, "UIPanelScrollFrameTemplate")
		scroll:SetPoint("TOPLEFT", 6, -6)
		scroll:SetPoint("BOTTOMRIGHT", -24, 6)
		if scroll.ScrollBar then E:SkinScrollBar(scroll.ScrollBar) end
		local box = CreateFrame("EditBox", nil, scroll)
		box:SetMultiLine(true)
		box:SetAutoFocus(false)
		box:SetMaxLetters(0)
		box:SetWidth(380)
		E:SetFont(box, E.tokens.size.label)
		box:SetScript("OnEscapePressed", function() frame:Hide() end)
		box:SetScript("OnTextChanged", function(_, user)
			if user then frame.result:SetText("") end
		end)
		scroll:SetScrollChild(box)
		scroll:SetScript("OnSizeChanged", function(_, width)
			if width and width > 0 then box:SetWidth(width) end
		end)
		holder:EnableMouse(true)
		holder:SetScript("OnMouseDown", function() box:SetFocus() end)
		frame.box = box

		frame.add = Kit.Button(frame.footer, L["Add all"], 100, function()
			local added, failed, rejected = M:AddLines(box:GetText())
			box:SetText(table.concat(rejected, "\n"))
			frame.result:SetText(M.PasteResult(added, failed))
		end)
		frame.add:SetPoint("RIGHT", frame.footer, "RIGHT", 0, 0)
		frame.closeButton = Kit.Button(frame.footer, L["Close"], 100, function() frame:Hide() end)
		frame.closeButton:SetPoint("RIGHT", frame.add, "LEFT", -8, 0)
		frame.result = E:CreateText(frame.footer, E.tokens.size.small, "LEFT")
		frame.result:SetPoint("LEFT", frame.footer, "LEFT", 0, 0)
		frame.result:SetPoint("RIGHT", frame.closeButton, "LEFT", -8, 0)
		frame.result:SetWordWrap(true)
		frame:SetScript("OnHide", function() box:ClearFocus() end)
		self.pasteFrame = frame
	end
	frame.result:SetText("")
	frame:Show()
	frame.box:SetFocus()
end

-- Another addon's /way always wins.
local function SlashTaken(command)
	for key in pairs(SlashCmdList) do
		if type(key) == "string" and not key:find("^ELDOUI") then
			for i = 1, 9 do
				local value = rawget(_G, "SLASH_" .. key .. i)
				if value == nil then break end
				if type(value) == "string" and value:lower() == command then return true end
			end
		end
	end
	return false
end

function M:RegisterSlash()
	if self.slash then return end
	self.slash = true
	local commands = {}
	for _, command in ipairs({ "/way", "/eway" }) do
		if not SlashTaken(command) then commands[#commands + 1] = command end
	end
	for i, command in ipairs(commands) do _G["SLASH_ELDOUIWAY" .. i] = command end
	SlashCmdList.ELDOUIWAY = function(input)
		if not M.active then E:Print(E:ModuleOffHint("Waypoints")) return end
		M:Command(input)
	end
	if not SlashTaken("/cway") then
		_G["SLASH_ELDOUICWAY1"] = "/cway"
		SlashCmdList.ELDOUICWAY = function()
			if M.active then M:Command("closest") end
		end
	end
end

E:AddCommand("way", "[zone] x y [title] | list | print | closest | reset [zone|all]  waypoints and the arrow (also /way)",
	function(arg)
		if M.active then M:Command(arg) else E:Print(E:ModuleOffHint("Waypoints")) end
	end)

function M:OnInitialize()
	E:RegisterPrivate("Waypoints", { points = {} })
end

function M:OnEnable()
	self:RegisterSlash()
	self:BuildArrow()
	self:LayoutArrow()
	self:BuildCoords()
	self:UpdateCoordsShown()
	for _, event in ipairs({ "USER_WAYPOINT_UPDATED", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD", "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST" }) do
		pcall(events.RegisterEvent, events, event)
	end
	if #self.order == 0 then self:Load() end
	self:EnableMap()
	self:UpdateArrowShown()
	self:ApplyVisibility()
end

function M:OnDisable()
	events:UnregisterAllEvents()
	E.Ticker:UnsubscribeOwner(M)
	for _, holder in ipairs({ self.arrowHolder, self.coordHolder }) do E:DetachVisibility(holder) end
	self.visibilityBlock = nil
	if self.arrowFrame then self.arrowFrame:Hide() end
	if self.arrowHolder then self.arrowHolder:Hide() end
	self:UpdateCoordsShown()
	if self.entryFrame then self.entryFrame:Hide() end
	if self.listFrame then self.listFrame:Hide() end
	self:DisableMap()
end

function M:OnProfileChanged()
	if not self.active then return end
	self:LayoutArrow()
	self:UpdateCoordsShown()
	self:ApplyVisibility()
	self:Save()
	self:LayoutPins()
end

-- Map.lua fills these in.
function M:RefreshPins() end
function M:LayoutPins() end
function M:EnableMap() end
function M:DisableMap() end
-- List.lua fills these in.
function M:ShowList() end
function M:ToggleList() end
function M:RefreshList() end
-- Coords.lua fills these in.
function M:BuildCoords() end
function M:UpdateCoordsShown() end
function M:ShowEntry() end

---------------------------------------------------------------------------
-- Options and styles
---------------------------------------------------------------------------
local function ArrowOff() return not M.db.arrow end

M.options = {
	{ type = "description", label = "Add a waypoint with /way 45 63 Goldshire or Ctrl-right-click on the world map. /way list opens the Waypoints window." },
	{ type = "tab", label = "Arrow" },
	{ type = "header", label = "Arrow" },
	{ type = "toggle", key = "arrow", label = "Show the arrow", desc = "An arrow that points at the current waypoint, with its distance and arrival time." },
	{ type = "range", key = "arrowSize", label = "Arrow size", min = 24, max = 96, step = 2, desc = "Size of the arrow in pixels.", dependsOn = "arrow" },
	{ type = "toggle", key = "showTitle", label = "Show the title", desc = "The waypoint's title under the arrow.", hidden = ArrowOff },
	{ type = "toggle", key = "showDistance", label = "Show the distance", desc = "Yards to the waypoint, in a straight line.", hidden = ArrowOff },
	{ type = "toggle", key = "showETA", label = "Show the arrival time", desc = "How long until you arrive at your current speed towards it.", hidden = ArrowOff },
	{ type = "toggle", key = "headingColours", label = "Color by heading", desc = "Green when you face the waypoint, yellow when it is to your side, red when it is behind you. Off uses the accent color.", hidden = ArrowOff },
	{ type = "select", key = "distanceUnit", label = "Distance in", desc = "Show distances under the arrow and in tooltips in yards (the game's unit) or meters.",
		values = { yards = "Yards", metres = "Meters" } },
	{ type = "toggle", key = "hideInInstance", label = "Hide in instances", desc = "Dungeons, raids and battlegrounds hide your position from addons. Hide the arrow and the coordinate box there; off shows the arrow with \"No position here\"." },
	{ type = "header", label = "Coordinate box" },
	{ type = "toggle", key = "coordBox", label = "Show the coordinate box", desc = "A small box with your map coordinates. Click it to type coordinates and add a waypoint; right-click for more. Move it in move mode (Waypoint Coordinates)." },
	{ type = "header", label = "Arriving" },
	{ type = "range", key = "arrivalDistance", label = "Arrival distance", min = 3, max = 50, step = 1, desc = "How close, in yards, counts as arrived." },
	{ type = "toggle", key = "clearOnArrival", label = "Remove on arrival", desc = "Remove a waypoint when you reach it." },
	{ type = "toggle", key = "autoNext", label = "Then point at the closest", desc = "After arriving or removing one, the arrow points at the closest waypoint left." },
	{ type = "media", key = "arrivalSound", label = "Arrival sound", mediaKind = "sound", none = true, desc = "A sound when you arrive. None for silence." },
	{ type = "toggle", key = "announce", label = "Chat messages", desc = "A chat line when a waypoint is added, removed or reached." },
	{ type = "tab", label = "Maps" },
	{ type = "header", label = "Pins" },
	{ type = "toggle", key = "worldPins", label = "World map pins", desc = "Show waypoints on the world map. Hover for details, right-click for options." },
	{ type = "toggle", key = "minimapPins", label = "Minimap pins", desc = "Show waypoints on the minimap; ones out of range sit on its edge." },
	{ type = "range", key = "pinSize", label = "Pin size", min = 10, max = 32, step = 1, desc = "Size of the map and minimap pins." },
	{ type = "select", key = "pinStyle", label = "Pin shape", desc = "The shape of waypoint pins on the world map and minimap.",
		values = { diamond = "Diamond", square = "Square", round = "Round" } },
	{ type = "toggle", key = "mapClick", label = "Ctrl+right-click adds a waypoint", desc = "Hold Ctrl and right-click on the world map to add a waypoint there." },
	{ type = "header", label = "The game's map pin" },
	{ type = "toggle", key = "gamePin", label = "Mirror on the game's map pin", desc = "Also set the game's own map pin and tracking on the waypoint the arrow points at." },
	{ type = "toggle", key = "useGamePin", label = "Use the game's map pin", desc = "When you place the game's own map pin (Ctrl+click on the map), it becomes a waypoint too." },
	{ type = "header", label = "Saving" },
	{ type = "toggle", key = "persistent", label = "Keep between sessions", desc = "Remember this character's waypoints after a logout or reload." },
	{ type = "toggle", key = "corpseArrow", label = "Point to your corpse", desc = "After you release your spirit, a waypoint on your corpse (the arrow points there). It goes away when you are alive again." },
	{ type = "execute", label = "Type coordinates", desc = "Open a small box to type coordinates (x y, or zone x y and a title) and add a waypoint. The coordinate box opens it too.", func = function() M:ShowEntry() end },
	{ type = "execute", label = "Waypoint list", desc = "Open the Waypoints window: every waypoint by zone, to point the arrow at one, remove them or copy them as /way lines. /way list opens it too.", func = function() M:ShowList() end },
	{ type = "execute", label = "Paste waypoints", desc = "Open a box to paste many /way lines at once, e.g. from a guide.", func = function() M:ShowPaste() end },
	{ type = "execute", confirm = true, label = "Remove all waypoints", desc = "Remove every waypoint on this character.", func = function() M:RemoveAll() end },
}

-- The shared visibility rows (arrow and coordinate box), before the
-- coordinate box section.
do
	local at = #M.options + 1
	for index, row in ipairs(M.options) do
		if row.type == "header" and row.label == "Coordinate box" then at = index break end
	end
	for _, row in ipairs(E:VisibilityOptions("visibility", { db = function() return M.db end })) do
		table.insert(M.options, at, row)
		at = at + 1
	end
end

E:RegisterStyles("Waypoints", {
	{ key = "Standard", title = "Standard", desc = "48 px arrow with title, distance and arrival time, colored by heading.",
		settings = { arrow = true, arrowSize = 48, showTitle = true, showDistance = true, showETA = true, headingColours = true } },
	{ key = "Compact", title = "Compact", desc = "32 px arrow with the distance only.",
		settings = { arrow = true, arrowSize = 32, showTitle = false, showDistance = true, showETA = false, headingColours = true } },
	{ key = "Large", title = "Large", desc = "72 px arrow with everything, for big screens.",
		settings = { arrow = true, arrowSize = 72, showTitle = true, showDistance = true, showETA = true, headingColours = true } },
	{ key = "Accent", title = "Accent", desc = "Arrow in the theme's accent color instead of heading colors.",
		settings = { arrow = true, arrowSize = 48, showTitle = true, showDistance = true, showETA = true, headingColours = false } },
	{ key = "PinsOnly", title = "Pins only", desc = "No arrow: waypoints only show as map and minimap pins.",
		settings = { arrow = false, worldPins = true, minimapPins = true } },
	{ mode = true, key = "Quiet", title = "Quiet", desc = "No chat lines and no sound.",
		settings = { announce = false, arrivalSound = "none" } },
})
