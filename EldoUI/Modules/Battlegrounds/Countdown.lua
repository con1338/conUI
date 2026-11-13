-- Battleground Timers: Blizzard element "pvp-start-countdown".
--
-- Blizzard's countdown bars with the big numbers (TimerTracker): the
-- battleground gate timer, the pull countdown from raid tools and every
-- other START_TIMER countdown. Design decision: one look for
-- all of them. With the element's master switch on (Blizzard UI page):
--   skin  flat bar in the theme texture, 1 px box, theme font
--   move  on EldoUI's own mover "Start Countdown", with a scale
--   hide  Blizzard's countdown stays invisible (the Battle start bar of
--         this module still counts down to the gates)
-- TimerTracker is only hooked (HookScript after its own event handler),
-- never replaced; its timer frames get no new fields (state lives in weak
-- tables here). Skin needs a reload to undo; move and hide undo at once.
local _, E = ...
local L = E.L
local M = E:GetModule("Battlegrounds")

local ID = "pvp-start-countdown"
local MOVER = "EldoUI_StartCountdown"
local BLIZZARD_TOP = -155   -- where Blizzard puts the first countdown
local BLIZZARD_STEP = 24
local STEP = 30
local DEFAULT_POINT = { "CENTER", "UIParent", "CENTER", 0, 235 } -- the countdown zone (the boss-mod countdown spot)

local C = M:AddPart({ name = "countdown" })
M.Countdown = C

local skinned = setmetatable({}, { __mode = "k" })  -- timer -> backdrop frame
local moved = setmetatable({}, { __mode = "k" })    -- timer -> true while on our mover
local faded = setmetatable({}, { __mode = "k" })    -- timer -> true while hidden by us
local hooked = false

local function Allowed(action)
	return M.active and E:BlizzardAllowed(ID, action)
end

local function Tracker()
	local tracker = _G.TimerTracker
	if type(tracker) == "table" and type(tracker.timerList) == "table" then return tracker end
end

-- Timers Blizzard is showing now (in creation order).
local function Timers()
	local tracker = Tracker()
	local list = {}
	if not tracker then return list end
	for _, timer in ipairs(tracker.timerList) do
		if type(timer) == "table" and timer.IsShown then list[#list + 1] = timer end
	end
	return list
end

local function Running(timer)
	return timer:IsShown() and not timer.isFree
end

---------------------------------------------------------------------------
-- Skin
---------------------------------------------------------------------------
local function Skin(timer)
	local bar = timer.bar
	if type(bar) ~= "table" or not bar.SetStatusBarTexture then return end
	bar:SetStatusBarTexture(E.media.statusbar)
	if type(bar.border) == "table" and bar.border.SetAlpha then bar.border:SetAlpha(0) end
	local box = skinned[timer]
	if not box then
		box = CreateFrame("Frame", nil, bar)
		box:SetPoint("TOPLEFT", -E.pixel, E.pixel)
		box:SetPoint("BOTTOMRIGHT", E.pixel, -E.pixel)
		box:SetFrameLevel(math.max(bar:GetFrameLevel() - 1, 0))
		skinned[timer] = box
	end
	E:SetTemplate(box)
	box:Show()
	local text = bar.timeText or bar.text
	if type(text) == "table" and text.SetFont then E:SetFont(text, E.tokens.size.label) end
end

---------------------------------------------------------------------------
-- Move
---------------------------------------------------------------------------
function C:CreateHolder()
	if self.holder then return end
	local holder = CreateFrame("Frame", MOVER, UIParent)
	holder:SetSize(206, 26)
	self.holder = holder
	E:CreateMover(holder, MOVER, L["Start Countdown"], DEFAULT_POINT, { sample = { kind = "bar" } })
end

local function PlaceAll()
	local holder = C.holder
	local scale = (M.db.countdownScale or 100) / 100
	local index = 0
	for _, timer in ipairs(Timers()) do
		if Running(timer) then
			timer:SetScale(scale)
			timer:ClearAllPoints()
			timer:SetPoint("TOP", holder, "TOP", 0, -index * STEP / scale)
			moved[timer] = true
			index = index + 1
		end
	end
end

-- Back where Blizzard puts its countdowns.
local function Unplace()
	local index = 0
	for _, timer in ipairs(Timers()) do
		if moved[timer] then
			moved[timer] = nil
			timer:SetScale(1)
			timer:ClearAllPoints()
			timer:SetPoint("TOP", UIParent, "TOP", 0, BLIZZARD_TOP - BLIZZARD_STEP * index)
		end
		if Running(timer) then index = index + 1 end
	end
end

---------------------------------------------------------------------------
-- Hide
---------------------------------------------------------------------------
local function Fade(timer)
	timer:SetAlpha(0)
	faded[timer] = true
end

local function Unfade()
	for timer in pairs(faded) do
		timer:SetAlpha(1)
		faded[timer] = nil
	end
end

---------------------------------------------------------------------------
-- Apply after every countdown change.
---------------------------------------------------------------------------
function C:Update()
	if not E:BlizzardAllowed(ID) or not M.active then
		Unplace()
		Unfade()
		return
	end
	for _, timer in ipairs(Timers()) do
		if Allowed("skin") then Skin(timer) end
		if Allowed("hide") then Fade(timer) end
	end
	if not Allowed("hide") then Unfade() end
	if Allowed("move") then
		self:CreateHolder()
		PlaceAll()
	else
		Unplace()
	end
end

local function Hook()
	if hooked then return end
	local tracker = Tracker()
	if not tracker or not tracker.HookScript then return end
	hooked = true
	-- After Blizzard's handler has made, placed and styled the timers.
	tracker:HookScript("OnEvent", function() C:Update() end)
end

function C:Apply()
	if not E:BlizzardAllowed(ID) then
		self:Update()
		return
	end
	Hook()
	self:Update()
end

-- Part hooks: the module's own switch and settings.
function C:Enable() self:Apply() end
function C:Disable() self:Update() end
function C:Refresh() self:Apply() end

E:RegisterBlizzardHandler(ID, {
	owner = "Battlegrounds",
	apply = function() C:Apply() end,
	undo = function() C:Update() end,
	reload = { skin = true },
	refreshModule = false,
})
