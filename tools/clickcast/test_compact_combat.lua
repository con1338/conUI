-- Offline test for Blizzard compact frames made or set up in combat
-- (review F17, first open part).
-- Run from the repository root:
--   lua5.1 tools/clickcast/test_compact_combat.lua
-- It cuts the real code out of EldoUI/Modules/ClickCast.lua (between fixed
-- markers, so a renamed part makes the test fail instead of testing a stale
-- copy): the binding attributes, the frame list, ClearFrame/ApplyFrame, the
-- compact frame pickup and M:OnEnable. Around it: a model of the game where
-- SetAttribute is blocked in combat, and of E:RunOutOfCombat (one queued
-- call per key, run when combat ends).
-- Checked: frames set up or found (GROUP_ROSTER_UPDATE) in combat get their
-- bindings when combat ends, with one queued job however many there are;
-- nothing is set in combat; the switches (module, Blizzard frames,
-- Improve) and forbidden frames are respected.
local ROOT = (arg and arg[0] or ""):match("^(.-)tools/clickcast/") or "./"

local function ReadFile(path)
	local file = assert(io.open(ROOT .. path, "rb"), "can't open " .. path)
	local text = file:read("*a")
	file:close()
	return (text:gsub("\r\n", "\n"))
end

-- The text from `first` up to (not including) `last`.
local function Between(text, first, last, where)
	local from = text:find(first, 1, true)
	assert(from, where .. ": marker not found: " .. first)
	local to = text:find(last, from + #first, true)
	assert(to, where .. ": end marker not found after " .. first .. ": " .. last)
	return text:sub(from, to - 1)
end

local clickcast = ReadFile("EldoUI/Modules/ClickCast.lua")
local function Cut(first, last) return Between(clickcast, first, last, "ClickCast.lua") end
local chunk = assert(loadstring(table.concat({
	"local M, E = ...",
	-- Defined elsewhere in the file; not part of what is tested here.
	"local HookTooltips, WantedOwner = function() end, function() return false end",
	Cut("local ACTION_TYPE = ", "local MOUSE_FROM_CLICK"),
	Cut("local function IsMouseKey(key)", "local function CurrentMods()"),
	Cut("local function VirtualButton(key)", "local function SetKey()"),
	Cut("local function BindingAttributes(binding, out)", "local frames = setmetatable"),
	Cut("local frames = setmetatable", "-- Out of combat only. Also switches the hover keys off"),
	Cut("function M:ClearFrame(frame)", "-- Serialized as name"),
	Cut("-- Blizzard's compact frames are created and re-used by the game", "-- The element switches:"),
	Cut("function M:OnEnable()", "function M:OnDisable()"),
	"return { frames = frames, applied = applied, setUpInCombat = setUpInCombat, COMPACT_JOB = COMPACT_JOB }",
}, "\n"), "=extracted"))

---------------------------------------------------------------------------
-- Model of the game and of EldoUI's core
---------------------------------------------------------------------------
local world -- fresh for every Setup

function InCombatLockdown() return world.combat end
function CompactUnitFrame_SetUpFrame() end
function hooksecurefunc(name, fn) world.hooks[name] = fn end
C_Timer = { After = function() end }
GameTooltip = { IsShown = function() return false end }

local function NewFrame(name, options)
	local frame = { name = name, attributes = {}, forbidden = options and options.forbidden }
	function frame:GetName() return self.name end
	function frame:GetAttribute(key) return self.attributes[key] end
	function frame:SetAttribute(key, value)
		-- A protected frame in combat: the game blocks the call.
		if world.combat then
			world.blocked = world.blocked + 1
			return
		end
		self.attributes[key] = value
	end
	_G[name] = frame
	world.globals[#world.globals + 1] = name
	return frame
end

local function Setup(options)
	options = options or {}
	if world then
		for _, name in ipairs(world.globals) do _G[name] = nil end
	end
	world = { combat = false, hooks = {}, events = {}, globals = {}, queue = {}, keys = {}, blocked = 0,
		improve = options.improve ~= false }
	local E = { Tour = { Seen = function() return true end } }
	function E.FrameCheck(frame, method)
		if method == "IsForbidden" then return frame.forbidden == true end
	end
	function E.Secret() return false end
	function E:BlizzardAllowed() return world.improve end
	function E:OnBlizzardAddOn() end
	-- One queued call per key; a later call with the same key replaces it.
	function E:RunOutOfCombat(fn, key)
		if not world.combat then
			fn()
			return true
		end
		local index = key ~= nil and world.keys[key]
		if index then
			world.queue[index] = fn
		else
			table.insert(world.queue, fn)
			if key ~= nil then world.keys[key] = #world.queue end
		end
		return false
	end
	local M = {
		active = true,
		db = { bindingsEnabled = true, bindBlizzard = options.bindBlizzard ~= false, bindUnitFrames = true, hoverKeys = true },
		applies = 0,
	}
	function M:GetBindings()
		return { { key = "BUTTON1", mods = "SHIFT-", action = "spell", value = "Flash Heal" },
			{ key = "F", mods = "", action = "spell", value = "Renew" } }
	end
	function M:RegisterEvent(event, fn) world.events[event] = fn end
	function M:Apply() self.applies = self.applies + 1 end
	function M:WrapHover() end
	local test = { M = M, E = E }
	test.api = chunk(M, E)
	M:OnEnable()
	return test
end

local function StartCombat() world.combat = true end
local function EndCombat()
	world.combat = false
	local queue = world.queue
	world.queue, world.keys = {}, {}
	for _, fn in ipairs(queue) do fn() end
end
-- Blizzard sets a compact frame up (creates or re-uses it).
local function SetUp(frame)
	CompactUnitFrame_SetUpFrame(frame)
	if world.hooks.CompactUnitFrame_SetUpFrame then world.hooks.CompactUnitFrame_SetUpFrame(frame) end
end
local function RosterUpdate() world.events.GROUP_ROSTER_UPDATE() end
local function Bound(frame)
	return frame.attributes["shift-type1"] == "spell" and frame.attributes["shift-spell1"] == "Flash Heal"
end

---------------------------------------------------------------------------
-- Checks
---------------------------------------------------------------------------
local passed, failed = 0, 0
local function Check(ok, what)
	if ok then passed = passed + 1 else failed = failed + 1; print("FAIL: " .. what) end
end

-- Wiring and the attributes themselves.
do
	local test = Setup()
	Check(world.hooks.CompactUnitFrame_SetUpFrame ~= nil, "OnEnable hooks CompactUnitFrame_SetUpFrame")
	Check(world.events.GROUP_ROSTER_UPDATE ~= nil, "OnEnable listens to GROUP_ROSTER_UPDATE")
	Check(test.M.applies == 1, "OnEnable applies once")
	local frame = NewFrame("CompactRaidFrame1")
	SetUp(frame)
	Check(Bound(frame), "out of combat: bindings at once")
	Check(frame.attributes["type-eldof"] == nil, "a key binding stays off the frame (it belongs to the hover button)")
	Check(test.api.frames[frame] == "blizzard", "out of combat: frame listed")
end

-- Frames set up in combat wait for its end; one job for all of them.
do
	local test = Setup()
	local early = NewFrame("CompactRaidFrame1")
	SetUp(early)
	StartCombat()
	local raid = NewFrame("CompactRaidFrame2")
	local party = NewFrame("CompactPartyFrameMember1")
	local pooled = NewFrame("CompactRaidGroup1Member1")
	SetUp(raid)
	SetUp(party)
	SetUp(pooled)
	SetUp(early) -- an existing frame set up again
	Check(not Bound(raid) and not Bound(party) and not Bound(pooled), "in combat: nothing bound yet")
	Check(world.blocked == 0, "in combat: no SetAttribute at all")
	Check(#world.queue == 1, ("in combat: one queued job for four setups (got %d)"):format(#world.queue))
	Check(world.keys[test.api.COMPACT_JOB] ~= nil, "the job has its key")
	RosterUpdate()
	Check(#world.queue == 1, "GROUP_ROSTER_UPDATE in combat: still one job")
	Check(world.blocked == 0, "GROUP_ROSTER_UPDATE in combat: no SetAttribute")
	EndCombat()
	Check(Bound(raid) and Bound(party) and Bound(pooled), "after combat: frames set up in combat are bound")
	Check(Bound(early), "after combat: the frame set up again still has its bindings")
	Check(next(test.api.setUpInCombat) == nil, "after combat: nothing left waiting")
	Check(world.blocked == 0, "after combat: nothing was blocked")
end

-- A frame the game made in combat without the hook (found by name on the
-- roster update).
do
	Setup()
	StartCombat()
	local frame = NewFrame("CompactRaidFrame7")
	RosterUpdate()
	Check(not Bound(frame), "roster update in combat: not yet")
	EndCombat()
	Check(Bound(frame), "roster update in combat: bound when combat ends")
	local later = NewFrame("CompactPartyFrameMember2")
	RosterUpdate()
	Check(Bound(later), "roster update out of combat: bound at once")
end

-- The module is switched off before combat ends.
do
	local test = Setup()
	StartCombat()
	local frame = NewFrame("CompactRaidFrame3")
	SetUp(frame)
	test.M.active = false
	EndCombat()
	Check(not Bound(frame), "module off: nothing bound after combat")
	Check(next(test.api.setUpInCombat) == nil, "module off: nothing left waiting")
end

-- "Blizzard's frames" off: no job at all.
do
	local test = Setup({ bindBlizzard = false })
	StartCombat()
	local frame = NewFrame("CompactRaidFrame4")
	SetUp(frame)
	RosterUpdate()
	Check(#world.queue == 0, "Blizzard frames off: nothing queued")
	EndCombat()
	Check(not Bound(frame), "Blizzard frames off: nothing bound")
	Check(next(test.api.setUpInCombat) == nil, "Blizzard frames off: nothing waiting")
end

-- The element's Improve switch off: the frame is listed but not bound.
do
	Setup({ improve = false })
	StartCombat()
	local frame = NewFrame("CompactRaidFrame5")
	SetUp(frame)
	EndCombat()
	Check(not Bound(frame), "Improve off: nothing bound after combat")
end

-- Forbidden frames (nameplates) and frames that aren't compact frames.
do
	local test = Setup()
	StartCombat()
	local plate = NewFrame("CompactRaidFrame6", { forbidden = true })
	local other = NewFrame("SomeAddonFrame")
	SetUp(plate)
	SetUp(other)
	Check(#world.queue == 0, "forbidden or foreign frames: nothing queued")
	Check(test.api.frames[plate] == nil and test.api.frames[other] == nil, "forbidden or foreign frames: not listed")
	EndCombat()
end

print(("%d checks passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
