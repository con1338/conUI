-- EldoUI Camera Situations: the camera zooms to your own distance for each
-- situation: talking to an NPC, in combat, your group in combat, mounted or
-- on a flight, in a travel form, indoors, in a city or inn, and out in the
-- world. When a situation ends the camera goes to the next one's distance,
-- or back to where you had it.
--
-- Only the camera distance changes (CameraZoomIn/Out), and only while the
-- module is on. Every situation comes from state the game shows anyway
-- (combat flags, mount, form, zone); a secret answer counts as "no".
--
-- Also here, for every part of EldoUI that sets the camera: the largest
-- camera distance this client allows (E:CameraZoomCap), read rather than
-- assumed, and the yards a distance factor gives (E:CameraYards).
local _, E = ...
local L = E.L

local abs = math.abs

local M = E:NewModule("Camera", {
	title = "Camera Situations",
	category = "Quality of Life",
	desc = "The camera zooms to your chosen distance when you talk to an NPC, fight, ride, go indoors or enter a city, and back again afterwards.",
	conflicts = { "DynamicCam", "Max_Camera_Distance" },
	frames = {},
	movers = {},
	blizzard = {},
	savedKeys = { "profile.modules.Camera" },
	optionsPage = "module:Camera",
	presets = { "Cinematic", "IndoorsOnly", "Overview", "Standard", "Talk" },
	reload = false,
	defaults = {
		enabled = false, -- changes your camera: the player turns it on
		-- Per situation: on, and the distance in yards.
		npcOn = true, npcZoom = 6,
		combatOn = false, combatZoom = 18,
		groupCombatOn = false, groupCombatZoom = 22,
		mountedOn = true, mountedZoom = 20,
		formOn = false, formZoom = 20,
		indoorsOn = true, indoorsZoom = 8,
		cityOn = true, cityZoom = 12,
		worldOn = false, worldZoom = 15,
		minChange = 1.5, -- ignore differences smaller than this (yd)
		returnZoom = true, -- back to your own distance when a situation ends
	},
})
E.Camera = M

-- Highest priority first.
M.SITUATIONS = {
	{ key = "npc", label = "Talking to an NPC", desc = "Zoom the camera while you talk to an NPC, a vendor, a trainer or a flight master." },
	{ key = "combat", label = "In combat", desc = "Zoom the camera while you are in combat." },
	{ key = "groupCombat", label = "Your group in combat", desc = "Zoom the camera while someone in your party or raid is in combat, even before you are." },
	{ key = "mounted", label = "Mounted or flying", desc = "Zoom the camera while you ride a mount or take a flight." },
	{ key = "form", label = "Travel form", desc = "Zoom the camera while you are in a travel form: Ghost Wolf, or a druid's travel, aquatic or flight form." },
	{ key = "indoors", label = "Indoors", desc = "Zoom the camera while you are indoors." },
	{ key = "city", label = "City or inn", desc = "Zoom the camera while you are in a city or an inn." },
	{ key = "world", label = "Out in the world", desc = "Zoom the camera while no other situation applies." },
}

local Clean = E.Plain

-- Camera addons that set the camera distance, zoom speed and shoulder
-- offset themselves: while one is loaded, EldoUI leaves those settings to
-- it (Quality of Life > Camera stands back, this module stays off).
E:RegisterFeatureConflicts("camera", { "DynamicCam", "Max_Camera_Distance" })

---------------------------------------------------------------------------
-- The camera distance cap (shared with Quality of Life > Camera)
---------------------------------------------------------------------------
-- The game's camera distance setting is a factor of 15 yards. Retail-type
-- clients stop at 2.6 (39 yd), Classic-type clients at 4.0 (the camera
-- stops at 50 yd there). Forever runs the Retail game client, so 2.6 is its
-- starting value; its own settings slider ends at 2.0, below that. The
-- real limit is read from the game rather than assumed:
-- E:ProbeCameraZoomCap() sets the top value and keeps what the game
-- accepted, and every value EldoUI sets afterwards is read back the same
-- way (E:NoteCameraZoom).
local ZOOM_CVAR = "cameraDistanceMaxZoomFactor"
local YARDS_PER_FACTOR, YARDS_STOP = 15, 50
local RETAIL_CAP, CLASSIC_CAP = 2.6, 4.0
local learnedCap   -- what the game accepted this session

local function ClassicType()
	local id, mainline = _G.WOW_PROJECT_ID, _G.WOW_PROJECT_MAINLINE
	if id == nil or mainline == nil or id == mainline then return false end
	return not (E.IsForeverClient and E:IsForeverClient())
end

function E:CameraZoomCap()
	if learnedCap then return learnedCap end
	return ClassicType() and CLASSIC_CAP or RETAIL_CAP
end

-- True once the cap was read from the game this session.
function E:CameraZoomCapKnown()
	return learnedCap ~= nil
end

function E:CameraYards(factor)
	factor = tonumber(factor) or 1
	return math.min(factor * YARDS_PER_FACTOR, YARDS_STOP)
end

-- The game's camera setting as a number, or nil.
local function ZoomFactor()
	local value = C_CVar and C_CVar.GetCVar and Clean(C_CVar.GetCVar(ZOOM_CVAR))
	return tonumber(value)
end
M.ZoomFactor = ZoomFactor

-- After EldoUI set `wanted`: when the game kept less, that is the cap.
function E:NoteCameraZoom(wanted)
	local kept = ZoomFactor()
	wanted = tonumber(wanted)
	if not (kept and wanted) then return end
	if kept < wanted - 0.01 then
		learnedCap = math.max(1, kept)
	elseif kept >= wanted - 0.01 and wanted > (learnedCap or 0) and wanted >= CLASSIC_CAP - 0.01 then
		learnedCap = math.min(CLASSIC_CAP, kept)
	end
	M:SizeSliders()
end

-- Set the top value once and keep what the game accepted. Only from the
-- player's click on "Use the largest distance" (the value is the one they
-- asked for); owner "Tweaks", so turning the row off puts theirs back.
function E:ProbeCameraZoomCap()
	if not (C_CVar and C_CVar.GetCVar) or C_CVar.GetCVar(ZOOM_CVAR) == nil then return nil end
	self:SetCVar(ZOOM_CVAR, CLASSIC_CAP, "Tweaks")
	local kept = ZoomFactor()
	if kept then
		learnedCap = math.max(1, math.min(CLASSIC_CAP, kept))
		M:SizeSliders()
	end
	return learnedCap
end

-- The distance sliders reach as far as the client goes.
function M:SizeSliders()
	local top = math.floor(E:CameraYards(E:CameraZoomCap()))
	for _, row in ipairs(self.options or {}) do
		if row.type == "range" and row.zoomSlider then row.max = top end
	end
	if self.OnCapChanged then self:OnCapChanged() end
end

local function Bool(fn, ...)
	if type(fn) ~= "function" then return false end
	local ok, value = pcall(fn, ...)
	return ok and Clean(value) and true or false
end

-- Travel forms by the game's form IDs: Ghost Wolf (16), travel (3),
-- aquatic (4), flight (27) and swift flight form (29).
local TRAVEL_FORMS = { [3] = true, [4] = true, [16] = true, [27] = true, [29] = true }

local function InTravelForm()
	local form = E.PlainCall(GetShapeshiftFormID)
	return form ~= nil and TRAVEL_FORMS[form] == true
end

-- Someone in the party or raid is in combat (the game's own flag; a
-- secret answer counts as no).
local function GroupInCombat()
	local raid = Bool(IsInRaid)
	local count = Clean(GetNumGroupMembers and GetNumGroupMembers()) or 0
	if type(count) ~= "number" or count <= 1 then return false end
	local prefix = raid and "raid" or "party"
	local last = raid and count or count - 1
	for index = 1, last do
		if Bool(UnitAffectingCombat, prefix .. index) then return true end
	end
	return false
end

-- NPC windows: open from their show event to their close event (EldoUI's
-- own NPC windows replace some Blizzard frames, so the events are the
-- reliable signal). Loading screens clear it.
local function TalkingToNPC()
	return M.npcOpen and true or false
end

-- The situation that applies right now, or nil.
function M:Current()
	local db = self.db
	local checks = {
		npc = TalkingToNPC,
		combat = function() return M.inCombat or Bool(InCombatLockdown) end,
		groupCombat = GroupInCombat,
		mounted = function() return Bool(IsMounted) or Bool(UnitOnTaxi, "player") end,
		form = InTravelForm,
		indoors = function() return Bool(IsIndoors) end,
		city = function() return Bool(IsResting) end,
		world = function() return true end,
	}
	for _, situation in ipairs(self.SITUATIONS) do
		local key = situation.key
		if db[key .. "On"] and checks[key]() then return key end
	end
end

local function Zoom()
	return Clean(GetCameraZoom and GetCameraZoom())
end

-- CameraZoomIn/Out animate: GetCameraZoom gives the distance on the way,
-- not where the camera is going. While a zoom of ours is still in flight
-- the next change is counted from its target, else quick situation changes
-- (a mount right after an NPC window) add up wrong and the camera drifts.
local function ZoomSpeed()
	local value = GetCVar and tonumber(Clean(GetCVar("cameraZoomSpeed")))
	return (value and value > 0) and value or 20
end

-- Where the camera is, or is going while our zoom is in flight.
function M:ZoomBase()
	local now = Zoom()
	if not now then return nil end
	local target = self.target
	if target and self.zoomUntil and GetTime() < self.zoomUntil and abs(now - target) > 0.05 then
		return target
	end
	return now
end

-- Move the camera to a distance.
function M:ZoomTo(distance)
	local now = self:ZoomBase()
	if not (now and distance) then return end
	local delta = distance - now
	if abs(delta) < self.db.minChange then return end
	if delta > 0 then
		if CameraZoomOut then CameraZoomOut(delta) end
	elseif CameraZoomIn then
		CameraZoomIn(-delta)
	end
	self.target = distance
	-- The animation's length at the zoom speed, plus a margin.
	self.zoomUntil = GetTime() + abs(delta) / ZoomSpeed() + 0.5
end

-- `again` applies the current situation's distance even when the situation
-- did not change (a setting changed); the player's own distance is kept.
function M:Update(again)
	if not self.active then return end
	local situation = self:Current()
	if situation == self.situation and not again then return end
	local previous = self.situation
	self.situation = situation
	if situation then
		-- Remember the player's own distance when the first situation starts.
		if not previous then self.ownZoom = self:ZoomBase() end
		self:ZoomTo(self.db[situation .. "Zoom"])
	elseif previous then
		if self.db.returnZoom and self.ownZoom then self:ZoomTo(self.ownZoom) end
		self.ownZoom = nil
	end
end

-- Events come in bursts (a mount fires several); check once a moment later.
-- delay: how long to wait (SETTLE unless given). A later call that asks
-- for a longer wait moves the check; a shorter one joins the waiting check.
local SETTLE = 0.15
-- Closing an NPC window often opens the next one at once (gossip to vendor,
-- one quest page to the next): wait this long before the camera leaves the
-- NPC distance, so a quick reopen keeps the camera where it is.
local NPC_CLOSE_SETTLE = 0.5
local queuedAt
function M:Queue(delay)
	delay = delay or SETTLE
	local after = C_Timer and C_Timer.After
	if not after then
		queuedAt = nil
		return self:Update()
	end
	local at = GetTime() + delay
	if queuedAt and queuedAt >= at then return end
	queuedAt = at
	after(delay, function()
		-- A later, longer wait took this check's place.
		if queuedAt ~= at then return end
		queuedAt = nil
		M:Update()
	end)
end

local NPC_SHOW = {
	GOSSIP_SHOW = true, QUEST_GREETING = true, QUEST_DETAIL = true, QUEST_PROGRESS = true,
	QUEST_COMPLETE = true, MERCHANT_SHOW = true, TRAINER_SHOW = true, TAXIMAP_OPENED = true,
}
local NPC_CLOSE = {
	GOSSIP_CLOSED = true, QUEST_FINISHED = true, MERCHANT_CLOSED = true, TRAINER_CLOSED = true, TAXIMAP_CLOSED = true,
}

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, ...)
	if not M.active then return end
	if event == "PLAYER_REGEN_DISABLED" then
		M.inCombat = true
	elseif event == "PLAYER_REGEN_ENABLED" then
		M.inCombat = false
	elseif NPC_SHOW[event] then
		M.npcOpen = true
	elseif NPC_CLOSE[event] then
		M.npcOpen = false
		M:Queue(NPC_CLOSE_SETTLE)
		return
	elseif event == "PLAYER_ENTERING_WORLD" then
		M.npcOpen = false
	elseif event == "UNIT_FLAGS" then
		-- Only group members' combat flags matter here.
		if not M.db.groupCombatOn then return end
		local unit = ...
		if type(unit) ~= "string" or not (unit:find("^party%d") or unit:find("^raid%d")) then return end
	end
	M:Queue()
end)

local EVENTS = {
	"PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_MOUNT_DISPLAY_CHANGED", "PLAYER_UPDATE_RESTING",
	"ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD", "PLAYER_CONTROL_LOST",
	"PLAYER_CONTROL_GAINED", "UPDATE_SHAPESHIFT_FORM", "GROUP_ROSTER_UPDATE", "UNIT_FLAGS",
}

function M:OnEnable()
	for _, event in ipairs(EVENTS) do pcall(events.RegisterEvent, events, event) end
	for event in pairs(NPC_SHOW) do pcall(events.RegisterEvent, events, event) end
	for event in pairs(NPC_CLOSE) do pcall(events.RegisterEvent, events, event) end
	self.situation, self.ownZoom, self.npcOpen = nil, nil, false
	self.inCombat = Bool(InCombatLockdown)
	self:Update()
end

function M:OnDisable()
	events:UnregisterAllEvents()
	-- Hand the camera back where the player had it.
	if self.situation and self.db.returnZoom and self.ownZoom then self:ZoomTo(self.ownZoom) end
	self.situation, self.ownZoom = nil, nil
end

function M:OnProfileChanged()
	if not self.active then return end
	self:Update(true)
end

local function Label(key)
	for _, situation in ipairs(M.SITUATIONS) do
		if situation.key == key then return situation.label end
	end
	return "none"
end

-- "2.6 (39 yd)"
local function FactorText(factor)
	if not factor then return "?" end
	return L["%.1f (%d yd)"]:format(factor, math.floor(E:CameraYards(factor)))
end

-- The camera state for /eui cam: situation, distance, the max distance
-- setting, the client's limit and the camera settings EldoUI holds.
function M:StatusLines()
	local lines = {}
	if self.active then
		local zoom = Zoom()
		lines[#lines + 1] = L["Camera: %s, %s yd."]:format(Label(self.situation), zoom and ("%.1f"):format(zoom) or "?")
	else
		lines[#lines + 1] = E:ModuleOffHint("Camera")
	end
	lines[#lines + 1] = L["Max camera distance: %s. This client allows up to %s%s."]:format(FactorText(ZoomFactor()),
		FactorText(E:CameraZoomCap()), E:CameraZoomCapKnown() and "" or " " .. L["(not read from the game yet)"])
	local addon, title = E:FeatureConflict("camera")
	if addon then lines[#lines + 1] = L["%s handles the camera settings while it is loaded."]:format(title) end
	local owned = {}
	local snapshot = type(EldoUIDB) == "table" and type(EldoUIDB.cvarSnapshot) == "table" and EldoUIDB.cvarSnapshot or {}
	for name, saved in pairs(snapshot) do
		if type(saved) == "table" and (name:find("^camera") or name:find("^test_camera")) then
			owned[#owned + 1] = ("%s = %s"):format(name, tostring(C_CVar and C_CVar.GetCVar and Clean(C_CVar.GetCVar(name)) or "?"))
		end
	end
	table.sort(owned)
	if #owned > 0 then
		lines[#lines + 1] = L["Camera settings EldoUI holds: %s."]:format(table.concat(owned, ", "))
	else
		lines[#lines + 1] = L["EldoUI holds none of your camera settings."]
	end
	return lines
end

E:AddCommand("cam", "the camera situation, distance, the max distance and the camera settings EldoUI holds", function()
	for _, line in ipairs(M:StatusLines()) do E:Print(line) end
end)

---------------------------------------------------------------------------
-- Options and styles
---------------------------------------------------------------------------
M.options = {
	{ type = "description", label = "A camera distance per situation; the first that applies wins, in the order below. Otherwise the camera goes back to your own distance." },
}
for _, situation in ipairs(M.SITUATIONS) do
	local key = situation.key
	M.options[#M.options + 1] = { type = "header", label = situation.label }
	M.options[#M.options + 1] = { type = "toggle", key = key .. "On", label = "Use this situation", desc = situation.desc }
	M.options[#M.options + 1] = { type = "range", key = key .. "Zoom", label = "Distance", unit = "yd", min = 2, max = 39, step = 1, zoomSlider = true,
		desc = "How far the camera sits behind you. The camera stops at the max camera distance (Quality of Life > Sound and misc).", dependsOn = key .. "On" }
end
M.options[#M.options + 1] = { type = "header", label = "General" }
M.options[#M.options + 1] = { type = "toggle", key = "returnZoom", label = "Back to your distance", desc = "When no situation applies, zoom back to the distance you had before." }
M.options[#M.options + 1] = { type = "range", key = "minChange", label = "Smallest change", unit = "yd", min = 0.5, max = 5, step = 0.5, desc = "Leave the camera alone when it is already this close to the distance." }
M:SizeSliders()

E:RegisterStyles("Camera", {
	{ key = "Standard", title = "Standard", desc = "Closer at NPCs, indoors and in cities, further out on a mount.",
		settings = { npcOn = true, npcZoom = 6, combatOn = false, mountedOn = true, mountedZoom = 20, indoorsOn = true, indoorsZoom = 8, cityOn = true, cityZoom = 12, worldOn = false } },
	{ key = "Cinematic", title = "Cinematic", desc = "Very close at NPCs and indoors, wide in the world.",
		settings = { npcOn = true, npcZoom = 3, indoorsOn = true, indoorsZoom = 5, cityOn = true, cityZoom = 9, mountedOn = true, mountedZoom = 24, worldOn = true, worldZoom = 18 } },
	{ key = "Overview", title = "Overview", desc = "Far out in combat and on a mount, for a wide view.",
		settings = { combatOn = true, combatZoom = 30, mountedOn = true, mountedZoom = 30, npcOn = false, indoorsOn = true, indoorsZoom = 12, cityOn = false, worldOn = false } },
	{ key = "IndoorsOnly", title = "Indoors only", desc = "Only pulls in indoors, so walls don't block the view.",
		settings = { npcOn = false, combatOn = false, mountedOn = false, indoorsOn = true, indoorsZoom = 7, cityOn = false, worldOn = false } },
	{ key = "Talk", title = "Talk", desc = "Only zooms in while you talk to an NPC.",
		settings = { npcOn = true, npcZoom = 4, combatOn = false, mountedOn = false, indoorsOn = false, cityOn = false, worldOn = false } },
})
