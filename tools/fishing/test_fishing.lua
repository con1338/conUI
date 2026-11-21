-- Offline test for the Fishing module: soft interact while fishing, Only
-- the splash and the catch log.
-- Run from the repository root:
--   lua5.1 tools/fishing/test_fishing.lua
-- Seen in the game (15.11.2026, WoW: Forever 1.60.1):
-- 1. The fishing key cast, but with the bobber out a press said "You need
--    to be closer to interact with that target.": soft interact had the
--    game's defaults (SoftTargetInteract 1 = gamepad only, range 10, arc 0),
--    so Interact with target never picked the bobber and reached the hard
--    target. With 3, 30 and 1 the key loots the bobber.
-- 2. The catch log stayed at 0: with auto loot the game sends LOOT_READY
--    and LOOT_CLOSED for a catch, never LOOT_OPENED.
-- This loads the real EldoUI/Modules/Fishing.lua and the real CVar part of
-- EldoUI/Core/Blizzard.lua (E:SetCVar, E:RestoreCVar, E:ForgetCVar,
-- E:CVarSecure; cut between fixed markers, so a renamed part makes the test
-- fail instead of testing a stale copy) into a model of the game: the CVars
-- with their secure flags, the override bindings, the loot window and the
-- events. The bar's frames are stand-ins that take every call.
-- Checked: fishing mode raises soft interact to 3/30/1 and puts the
-- player's own values back; higher values stay; 0 becomes 2; with "Same key
-- loots the bobber" off nothing changes; a secure SoftTargetInteract is left
-- alone (the options then show the chat command), the other two still rise;
-- an older version's stale record is dropped once, while a reload during
-- fishing still puts the player's values back. Only the splash turns
-- music, ambience, dialog, emote and pet sounds off and sound in the
-- background on, keeps sound and effects on (and turns them on for a
-- player who keeps them off), skips a setting the client lacks or
-- protects, follows the option at once while fishing and puts every
-- switch back after (also after a reload). Catches count from
-- LOOT_READY, once per loot (a second LOOT_READY and a LOOT_OPENED after it
-- add nothing), from LOOT_OPENED alone too, not before the loot has a slot,
-- never for loot that isn't fishing loot, and again after the next cast
-- when LOOT_CLOSED never came.
local ROOT = (arg and arg[0] or ""):match("^(.-)tools/fishing/") or "./"

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

local FISHING = ReadFile("EldoUI/Modules/Fishing.lua")
local CVARS = Between(ReadFile("EldoUI/Core/Blizzard.lua"), "-- CVars: EldoUI remembers the player's own value",
	"-- Load-on-demand Blizzard addons", "Blizzard.lua CVars")

---------------------------------------------------------------------------
-- Model of the game
---------------------------------------------------------------------------
local world

-- Frames and everything else the bar would build: every field is the
-- stand-in itself and every call returns it.
local Stub = {}
setmetatable(Stub, { __index = function() return Stub end, __call = function() return Stub end })

-- The player's settings as the game had them: soft interact's defaults.
local function NewWorld(cvars, secure)
	world = {
		now = 1000, combat = false, handlers = {}, binding = nil, warnings = {},
		cvars = {
			SoftTargetInteract = "1", SoftTargetInteractRange = "10", SoftTargetInteractArc = "0",
			Sound_SFXVolume = "0.6", Sound_MasterVolume = "0.8", Sound_MusicVolume = "0.4", Sound_AmbienceVolume = "0.5",
			-- The sound switches (this client has no Sound_EnablePingSounds).
			Sound_EnableAllSound = "1", Sound_EnableSFX = "1", Sound_EnableSoundWhenGameIsInBG = "0",
			Sound_EnableMusic = "1", Sound_EnableAmbience = "1", Sound_EnableDialog = "1",
			Sound_EnableErrorSpeech = "0", Sound_EnableEmoteSounds = "1", Sound_EnablePetSounds = "1",
		},
		secure = secure or {},
		loot = nil, -- { fishing = bool, links = { ... } } while a loot is open
	}
	for name, value in pairs(cvars or {}) do world.cvars[name] = value end
end

function GetTime() return world.now end
time = os.time
function InCombatLockdown() return world.combat end
function GetInventoryItemID() return nil end
function GetRealZoneText() return "Elwynn Forest" end
function GetSubZoneText() return "Crystal Lake" end
function UnitChannelInfo() return nil end
C_Item = {}
C_Timer = { After = function() end }
C_CVar = {
	GetCVar = function(name) return world.cvars[name] end,
	-- The game refuses a secure setting from an addon.
	SetCVar = function(name, value)
		if world.secure[name] then return false end
		world.cvars[name] = tostring(value)
		return true
	end,
	-- value, default, account, character, locked, secure, read-only
	GetCVarInfo = function(name)
		if world.cvars[name] == nil then return nil end
		return world.cvars[name], nil, false, false, false, world.secure[name] and true or false, false
	end,
}
function ClearOverrideBindings() world.binding = nil end
function SetOverrideBinding(_, _, key, action) world.binding = action and (key .. "=" .. action) or nil end
function SetOverrideBindingClick(_, _, key) world.binding = key .. "=cast" end
function IsFishingLoot() return world.loot and world.loot.fishing or false end
function GetNumLootItems() return world.loot and #world.loot.links or 0 end
function GetLootSlotLink(slot) return world.loot and world.loot.links[slot] end
function GetLootSlotInfo(slot)
	if not (world.loot and world.loot.links[slot]) then return nil end
	return nil, "item", 1
end

---------------------------------------------------------------------------
-- EldoUI's core, as far as the module uses it
---------------------------------------------------------------------------
local L = setmetatable({}, { __index = function(_, key) return key end })

local DEFAULT_DB

local function NewAddon()
	EldoUIDB = {}
	local private, global = {}, {}
	local E = setmetatable({ L = L, modules = {} }, { __index = function() return Stub end })
	function E.Plain(value) return value end
	function E:IsSecret() return false end
	function E:SafeEquals(a, b) return a == b end
	function E:RunOutOfCombat(fn) fn() end
	function E:RegisterPrivate(name, defaults) private[name] = private[name] or defaults end
	function E:GetPrivate(name) return private[name] end
	function E:RegisterGlobal(name, defaults) global[name] = global[name] or defaults end
	function E:GetGlobal(name) return global[name] end
	function E:RegisterEvent(event, handler, owner) world.handlers[event] = { handler = handler, owner = owner } end
	function E:UnregisterEvent(event) world.handlers[event] = nil end
	function E:Plural(n, one, other) return n == 1 and one or other end
	function E:TokenHex() return "" end
	E.errors = { Add = function(_, _, message) table.insert(world.warnings, message) end }
	E.BagCache = { BagIDs = function() return {} end }
	function E:NewModule(_, info)
		DEFAULT_DB = info.defaults
		local module = { db = {} }
		for key, value in pairs(info.defaults) do module.db[key] = value end
		return module
	end
	assert(loadstring("local E = ...\n" .. CVARS, "=Blizzard.lua CVars"))(E)
	assert(loadstring(FISHING, "=Fishing.lua"))("EldoUI", E)
	local M = E.Fishing
	-- The bar's frames are stand-ins.
	function M:BuildBar() self.cast, self.lure, self.swap = Stub, Stub, Stub end
	M:OnInitialize()
	return E, M, private
end

local function Fire(event, ...)
	local entry = world.handlers[event]
	if entry then entry.handler(entry.owner, event, ...) end
end

-- The module on, the fishing key F, fishing mode with the toggle key.
local function Start(settings)
	local E, M, private = NewAddon()
	for key, value in pairs(settings or {}) do M.db[key] = value end
	M.db.enabled, M.db.castKey, M.db.trigger = true, "F", "toggle"
	M.active = true
	M:OnEnable()
	return E, M, private
end

local function FishingOn(M) M.toggled = true M:Evaluate() end
local function FishingOff(M) M.toggled = false M:Evaluate() end

local function Cast()
	world.now = world.now + 1
	Fire("UNIT_SPELLCAST_CHANNEL_START", "player", "Cast-1", 7620)
end

local function StopChannel()
	Fire("UNIT_SPELLCAST_CHANNEL_STOP", "player", "Cast-1", 7620)
end

local FISH = "|cffffffff|Hitem:6303::::::::20:::::|h[Raw Slitherskin Mackerel]|h|r"

local failures, passed = 0, 0
local function Check(ok, message)
	if ok then
		passed = passed + 1
	else
		failures = failures + 1
		print("FAIL: " .. message)
	end
end

local function Soft()
	return world.cvars.SoftTargetInteract .. "/" .. world.cvars.SoftTargetInteractRange .. "/" .. world.cvars.SoftTargetInteractArc
end

---------------------------------------------------------------------------
-- Soft interact while fishing
---------------------------------------------------------------------------
do
	-- The game's defaults, as on the player's client.
	NewWorld()
	local _, M, private = Start()
	Check(Soft() == "1/10/0", "nothing changes before fishing mode: " .. Soft())
	FishingOn(M)
	Check(M.fishingMode == true, "fishing mode is on")
	Check(Soft() == "3/30/1", "fishing mode: soft interact for mouse and keyboard, 30 yards, in front: " .. Soft())
	Check(world.cvars.Sound_SFXVolume == "1", "the louder splash still works")
	Check(world.binding == "F=cast", "the key casts: " .. tostring(world.binding))
	Cast()
	Check(world.binding == "F=INTERACTTARGET", "with the bobber out the key interacts: " .. tostring(world.binding))
	FishingOff(M)
	Check(Soft() == "1/10/0", "fishing mode off: the player's own values are back: " .. Soft())
	Check(world.cvars.Sound_SFXVolume == "0.6", "the player's own volume is back")
	Check(next(private.Fishing.cvars) == nil, "no fishing record is left")
	Check(next(EldoUIDB.cvarSnapshot or {}) == nil, "no snapshot entry is left")
	Check(#world.warnings == 0, "no warning: " .. tostring(world.warnings[1]))
end

do
	-- Values above what fishing needs stay as they are, and get no record.
	NewWorld({ SoftTargetInteract = "3", SoftTargetInteractRange = "40", SoftTargetInteractArc = "2" })
	local _, M, private = Start()
	FishingOn(M)
	Check(Soft() == "3/40/2", "higher values stay while fishing: " .. Soft())
	Check(private.Fishing.cvars.SoftTargetInteract == nil and private.Fishing.cvars.SoftTargetInteractRange == nil,
		"no record for a setting fishing left alone")
	FishingOff(M)
	Check(Soft() == "3/40/2", "and stay after: " .. Soft())
end

do
	-- Soft interact off: mouse and keyboard only, the gamepad stays off.
	NewWorld({ SoftTargetInteract = "0", SoftTargetInteractRange = "25" })
	local _, M = Start()
	FishingOn(M)
	Check(Soft() == "2/30/1", "0 becomes 2 (mouse and keyboard): " .. Soft())
	FishingOff(M)
	Check(Soft() == "0/25/0", "the player's values are back: " .. Soft())
end

do
	-- "Same key loots the bobber" off: soft interact is not touched.
	NewWorld()
	local _, M = Start({ interact = false })
	FishingOn(M)
	Check(Soft() == "1/10/0", "with the option off nothing changes: " .. Soft())
	Cast()
	Check(world.binding == "F=cast", "and the key keeps casting: " .. tostring(world.binding))
	FishingOff(M)
end

do
	-- The option turned off while fishing: the values come back at once.
	NewWorld()
	local _, M = Start()
	FishingOn(M)
	M.db.interact = false
	M:OnProfileChanged()
	Check(Soft() == "1/10/0", "option off while fishing: values back: " .. Soft())
	M.db.interact = true
	M:OnProfileChanged()
	Check(Soft() == "3/30/1", "option on again: raised again: " .. Soft())
	FishingOff(M)
	Check(Soft() == "1/10/0", "and back after: " .. Soft())
end

do
	-- A client that protects SoftTargetInteract: EldoUI leaves it, the
	-- options show the player's own chat command, range and arc still rise.
	NewWorld(nil, { SoftTargetInteract = true })
	local E, M, private = Start()
	FishingOn(M)
	Check(Soft() == "1/30/1", "secure SoftTargetInteract stays, the rest rises: " .. Soft())
	Check(private.Fishing.cvars.SoftTargetInteract == nil, "no record for the secure setting")
	Check(#world.warnings == 0, "fishing doesn't even try the secure setting: " .. tostring(world.warnings[1]))
	local note
	for _, option in ipairs(M.options) do
		if option.type == "execute" and option.label == "Copy command" then note = option end
	end
	Check(note and note.hidden() == false, "the options offer the chat command")
	FishingOff(M)
	Check(Soft() == "1/10/0", "values back: " .. Soft())
	-- Not secure: the chat command stays hidden even while soft interact is off.
	world.secure = {}
	Check(note.hidden() == true, "where EldoUI can set it, no chat command")
	Check(E:CVarSecure("SoftTargetInteract") == false, "E:CVarSecure reads the game's flag")
end

do
	-- An older version's stale SoftTargetInteract record (its write was
	-- refused): dropped once, never written back.
	NewWorld({ SoftTargetInteract = "3" })
	local _, M, private = NewAddon()
	private.Fishing.cvars = { SoftTargetInteract = "1" }
	EldoUIDB.cvarSnapshot = { SoftTargetInteract = { value = "1", owner = "fishing", held = true } }
	M.db.castKey, M.db.trigger, M.active = "F", "toggle", true
	M:OnEnable()
	Check(world.cvars.SoftTargetInteract == "3", "a stale record is not written back: " .. world.cvars.SoftTargetInteract)
	Check(EldoUIDB.cvarSnapshot.SoftTargetInteract == nil, "the stale snapshot entry is gone")
	Check(private.Fishing.softRecords == 2, "dropped once")
end

do
	-- A reload while fishing: the next start puts the player's values back
	-- (the records written by this version are kept).
	NewWorld()
	local _, M, private = Start()
	FishingOn(M)
	Check(Soft() == "3/30/1", "raised before the reload")
	-- The reload: a new module run on the same saved data, no pole and no
	-- toggle, so fishing mode stays off.
	M.fishingMode, M.toggled = false, false
	M:OnEnable()
	Check(Soft() == "1/10/0", "after a reload during fishing the player's values are back: " .. Soft())
	Check(next(private.Fishing.cvars) == nil, "no record left after the reload")
end

---------------------------------------------------------------------------
-- Only the splash: every sound channel but the effects off while fishing
---------------------------------------------------------------------------
local SWITCHES = { "Sound_EnableAllSound", "Sound_EnableSFX", "Sound_EnableSoundWhenGameIsInBG", "Sound_EnableMusic",
	"Sound_EnableAmbience", "Sound_EnableDialog", "Sound_EnableErrorSpeech", "Sound_EnableEmoteSounds", "Sound_EnablePetSounds" }

local function Switches()
	local parts = {}
	for _, name in ipairs(SWITCHES) do parts[#parts + 1] = world.cvars[name] end
	return table.concat(parts)
end

do
	-- Off (the default): fishing leaves the switches alone.
	NewWorld()
	local _, M = Start()
	FishingOn(M)
	Check(Switches() == "110111011", "with the option off the switches stay: " .. Switches())
	FishingOff(M)
end

do
	-- On: music, ambience, dialog, emote and pet sounds off, sound in the
	-- background on; sound and effects stay on and get no record.
	NewWorld()
	local _, M, private = Start({ onlySplash = true })
	FishingOn(M)
	Check(Switches() == "111000000", "only the effects stay on while fishing: " .. Switches())
	local cvars = private.Fishing.cvars
	Check(cvars.Sound_EnableAllSound == nil and cvars.Sound_EnableSFX == nil and cvars.Sound_EnableErrorSpeech == nil,
		"no record for a switch that already had its value")
	Check(world.cvars.Sound_EnablePingSounds == nil, "a setting this client lacks is not made up")
	Check(world.cvars.Sound_SFXVolume == "1", "the louder splash still works with it")
	Check(#world.warnings == 0, "no warning: " .. tostring(world.warnings[1]))
	FishingOff(M)
	Check(Switches() == "110111011", "fishing mode off: the player's own switches are back: " .. Switches())
	Check(next(private.Fishing.cvars) == nil, "no fishing record is left")
	Check(next(EldoUIDB.cvarSnapshot or {}) == nil, "no snapshot entry is left")
end

do
	-- The player keeps all sound off: fishing turns sound and effects on
	-- for the splash, and off again after.
	NewWorld({ Sound_EnableAllSound = "0", Sound_EnableSFX = "0" })
	local _, M = Start({ onlySplash = true, soundBoost = false })
	FishingOn(M)
	Check(Switches() == "111000000", "sound and effects come on for the splash: " .. Switches())
	Check(world.cvars.Sound_SFXVolume == "0.6", "without Louder splash the volume stays the player's")
	FishingOff(M)
	Check(Switches() == "000111011", "and go off again after: " .. Switches())
end

do
	-- Turned on and off while fishing: at once, and back after.
	NewWorld()
	local _, M = Start()
	FishingOn(M)
	M.db.onlySplash = true
	M:OnProfileChanged()
	Check(Switches() == "111000000", "option on while fishing: the other sound goes off: " .. Switches())
	M.db.onlySplash = false
	M:OnProfileChanged()
	Check(Switches() == "110111011", "option off while fishing: the switches are back: " .. Switches())
	FishingOff(M)
end

do
	-- A reload while fishing: the player's switches come back.
	NewWorld()
	local _, M, private = Start({ onlySplash = true })
	FishingOn(M)
	M.fishingMode, M.toggled = false, false
	M:OnEnable()
	Check(Switches() == "110111011", "after a reload during fishing the switches are back: " .. Switches())
	Check(next(private.Fishing.cvars) == nil, "no record left after the reload")
end

do
	-- A secure switch is left alone and gets no record.
	NewWorld(nil, { Sound_EnableMusic = true })
	local _, M, private = Start({ onlySplash = true })
	FishingOn(M)
	Check(world.cvars.Sound_EnableMusic == "1" and private.Fishing.cvars.Sound_EnableMusic == nil, "a secure switch stays")
	Check(world.cvars.Sound_EnableAmbience == "0", "the others still go off")
	Check(#world.warnings == 0, "fishing doesn't even try the secure switch: " .. tostring(world.warnings[1]))
	FishingOff(M)
	Check(Switches() == "110111011", "values back: " .. Switches())
end

---------------------------------------------------------------------------
-- Catch log
---------------------------------------------------------------------------
local function Catches(M) return M.session and M.session.catches or 0 end

do
	NewWorld()
	local E, M = Start()
	FishingOn(M)
	Cast()
	-- Auto loot on WoW: Forever: the channel ends, LOOT_READY (twice here),
	-- LOOT_CLOSED. No LOOT_OPENED.
	StopChannel()
	world.loot = { fishing = true, links = { FISH } }
	Fire("LOOT_READY", true)
	Check(Catches(M) == 1, "a catch counts from LOOT_READY: " .. Catches(M))
	Fire("LOOT_READY", true)
	Check(Catches(M) == 1, "a second LOOT_READY for the same loot adds nothing: " .. Catches(M))
	Fire("LOOT_OPENED", true, false)
	Check(Catches(M) == 1, "nor does a LOOT_OPENED after it: " .. Catches(M))
	world.loot = nil
	Fire("LOOT_CLOSED")
	Fire("LOOT_CLOSED")
	local log = E:GetGlobal("FishingLog")
	local spot = log.zones["Elwynn Forest"] and log.zones["Elwynn Forest"].spots["Crystal Lake"]
	Check(spot and spot.catches == 1 and spot.items[6303] == 1, "the catch log has the fish at its spot")
	Check(world.binding == "F=cast", "after the catch the key casts again: " .. tostring(world.binding))

	-- The next catch counts again.
	Cast()
	StopChannel()
	world.loot = { fishing = true, links = { FISH } }
	Fire("LOOT_READY", true)
	world.loot = nil
	Fire("LOOT_CLOSED")
	Check(Catches(M) == 2, "the next catch counts: " .. Catches(M))

	-- A client that sends only LOOT_OPENED still counts.
	Cast()
	StopChannel()
	world.loot = { fishing = true, links = { FISH } }
	Fire("LOOT_OPENED", true, false)
	world.loot = nil
	Fire("LOOT_CLOSED")
	Check(Catches(M) == 3, "LOOT_OPENED alone counts: " .. Catches(M))

	-- A LOOT_READY before the loot has a slot waits for the next one.
	Cast()
	StopChannel()
	world.loot = { fishing = true, links = {} }
	Fire("LOOT_READY", true)
	Check(Catches(M) == 3, "an empty LOOT_READY doesn't count yet: " .. Catches(M))
	world.loot.links = { FISH }
	Fire("LOOT_READY", true)
	Check(Catches(M) == 4, "the LOOT_READY with the fish counts: " .. Catches(M))
	world.loot = nil
	Fire("LOOT_CLOSED")

	-- Loot that isn't fishing loot (a mob between casts) never counts.
	world.loot = { fishing = false, links = { "|Hitem:2589::::::::20:::::|h[Linen Cloth]|h" } }
	Fire("LOOT_READY", true)
	world.loot = nil
	Fire("LOOT_CLOSED")
	Check(Catches(M) == 4, "other loot doesn't count: " .. Catches(M))

	-- LOOT_CLOSED never came: the next cast starts a new catch.
	Cast()
	StopChannel()
	world.loot = { fishing = true, links = { FISH } }
	Fire("LOOT_READY", true)
	Cast()
	StopChannel()
	Fire("LOOT_READY", true)
	Check(Catches(M) == 6, "after a lost LOOT_CLOSED the next cast counts again: " .. Catches(M))
	world.loot = nil
	Fire("LOOT_CLOSED")

	-- Outside fishing mode nothing counts.
	FishingOff(M)
	world.loot = { fishing = true, links = { FISH } }
	Fire("LOOT_READY", true)
	world.loot = nil
	Fire("LOOT_CLOSED")
	Check(Catches(M) == 6, "outside fishing mode nothing counts: " .. Catches(M))
end

Check(DEFAULT_DB and DEFAULT_DB.interact == true, "the option is on by default")
Check(DEFAULT_DB and DEFAULT_DB.onlySplash == false, "Only the splash is off by default")

print(("%d passed, %d failed"):format(passed, failures))
if failures > 0 then os.exit(1) end
