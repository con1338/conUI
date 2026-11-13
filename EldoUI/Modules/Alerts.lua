-- EldoUI Danger Alerts: a warning sound when you stand in
-- something bad, plus breath, fatigue and "attacked while AFK" alarms.
--
-- How it stays within the rules: for auras, EldoUI only hands the game a
-- list of spell IDs and a sound through C_UnitAuras.AddAuraSound (or the
-- private-aura version). The game plays the sound itself when the aura
-- lands on you; EldoUI never reads combat data or the combat log.
-- Breath and fatigue come from the mirror timer events the game sends.
--
-- Sounds come from the media list (EldoUI's own tones in Media\Sounds,
-- SharedMedia packs): sound files only, because the game plays the aura
-- sounds itself from a file.
-- Danger sound: spell list, breath running out, attacked while AFK.
-- Fatigue sound: deep water fatigue. Stack sound: a bad aura stacks.
local _, E = ...
local L = E.L

local M = E:NewModule("Alerts", {
	title = "Danger Alerts",
	desc = "Sound alarms when you stand in something harmful (spell list), run out of breath or fatigue, or are attacked while AFK.",
	conflicts = { "GTFO" },
	frames = {},
	movers = {},
	blizzard = {},
	savedKeys = { "profile.modules.Alerts" },
	optionsPage = "module:Alerts",
	presets = { "Explorer", "Fun", "Loud", "Quiet", "Raid", "Standard" },
	reload = false,
	defaults = {
		enabled = false,
		style = "Standard",
		auras = true,
		breath = true,
		fatigue = true,
		afk = true,
		flash = true,
		channel = "Master",
		soundHigh = "eldo:EldoAlarm",   -- media ids (bare keys from before are migrated)
		soundLow = "eldo:EldoChime",
		soundStack = "eldo:EldoWarning",
		stacks = true,
		spells = "",
	},
})

local FALLBACK = "eldo:EldoAlarm"
local FILE_SOUNDS = { playable = "file" }
local CHANNELS = { Master = "Master", SFX = "Effects", Dialog = "Dialog", Ambience = "Ambience" }

-- Spell IDs that alert for everyone. Kept empty until each one is checked
-- in game on Forever; your own IDs go in the option box.
local SHIPPED = {}

local registered = {} -- sound handles we added, so we can remove them again

-- The file the game plays for an aura sound.
local function SoundFile(id)
	local path = E:FetchMedia("sound", id)
	if type(path) ~= "string" then path = E:FetchMedia("sound", FALLBACK) end
	return path
end
M.SoundFile = SoundFile

function M:Play(id)
	E:PlayMedia(id, self.db.channel, { fallback = FALLBACK })
end

-- Saved before the media list: "EldoAlarm" and the other bare keys.
function M:MigrateSounds()
	for _, key in ipairs({ "soundHigh", "soundLow", "soundStack" }) do
		local value = self.db[key]
		if type(value) ~= "string" or value == "" or value == "none" then
			self.db[key] = self.defaults and self.defaults[key] or FALLBACK
		elseif not value:find(":", 1, true) and E:GetMedia("sound", "eldo:" .. value) then
			self.db[key] = "eldo:" .. value
		end
	end
end

---------------------------------------------------------------------------
-- Screen flash
---------------------------------------------------------------------------
-- The shared edge flash (E:ScreenFlash): it follows General > Animations,
-- and its rate limit (at most three in three seconds) keeps a burst of
-- alarms from strobing. The danger color comes from the text tokens.
function M:Flash()
	if not self.db.flash then return false end
	return E:ScreenFlash(E.media.text.bad, 0.45, 0.6, "edges")
end

function M:Alert(sound)
	self:Play(sound)
	self:Flash()
end

---------------------------------------------------------------------------
-- Aura sounds (the game plays them)
---------------------------------------------------------------------------
local function AuraApi()
	local auras = C_UnitAuras
	if not auras then return nil end
	if auras.AddAuraSound and Enum.UnitAuraSoundTrigger then return "full" end
	if auras.AddPrivateAuraAppliedSound then return "private" end
	return nil
end

function M:SpellList()
	local list, seen = {}, {}
	for _, id in ipairs(SHIPPED) do
		if not seen[id] then seen[id] = true; table.insert(list, id) end
	end
	for text in tostring(self.db.spells or ""):gmatch("%d+") do
		local id = tonumber(text)
		if id and not seen[id] then seen[id] = true; table.insert(list, id) end
	end
	return list
end

function M:ClearAuraSounds()
	local auras = C_UnitAuras
	for _, handle in ipairs(registered) do
		if auras.RemoveAuraSound then pcall(auras.RemoveAuraSound, handle)
		elseif auras.RemovePrivateAuraAppliedSound then pcall(auras.RemovePrivateAuraAppliedSound, handle) end
	end
	wipe(registered)
end

local function AddSound(api, spellID, trigger, sound, channel)
	local info = { spellID = spellID, unitToken = "player", soundFileName = SoundFile(sound), outputChannel = channel }
	local ok, handle
	if api == "full" then
		ok, handle = pcall(C_UnitAuras.AddAuraSound, trigger, info)
	else
		ok, handle = pcall(C_UnitAuras.AddPrivateAuraAppliedSound, info)
	end
	if ok and handle then table.insert(registered, handle) end
	return ok and handle
end

-- The game refuses new aura sounds while an addon restriction runs (combat,
-- a boss encounter, a challenge mode or a PvP match). A reload during one
-- would leave the alarms off for the session, so the handles stay as they
-- are and the alarms register once the restriction ends.
local RESTRICTIONS = { "Combat", "Encounter", "ChallengeMode", "PvPMatch" }
local function AuraSoundsRestricted()
	if InCombatLockdown() then return true end
	local restricted, types = C_RestrictedActions, Enum and Enum.AddOnRestrictionType
	if not (restricted and restricted.IsAddOnRestrictionActive and types) then return false end
	for _, key in ipairs(RESTRICTIONS) do
		if types[key] then
			local ok, active = pcall(restricted.IsAddOnRestrictionActive, types[key])
			if ok and active == true then return true end
		end
	end
	return false
end

function M:RetryAuraSounds(event, _, state)
	if not self.pendingRegister then return end
	-- On the event, wait for an end and ask again once it is dispatched.
	if event == "ADDON_RESTRICTION_STATE_CHANGED" then
		E:AfterRestrictionEnds(state, function() M:RetryAuraSounds() end)
		return
	end
	if AuraSoundsRestricted() then return end
	self.pendingRegister = nil
	self:UnregisterEvent("ADDON_RESTRICTION_STATE_CHANGED")
	if self.active then
		self:RegisterAuraSounds()
		self:WatchAfk()
	end
end

function M:RegisterAuraSounds()
	if self.db.auras and AuraApi() and AuraSoundsRestricted() then
		self.pendingRegister = true
		self.auraStatus = L["Aura alarms wait for combat to end."]
		self:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED", "RetryAuraSounds")
		self:RegisterEvent("PLAYER_REGEN_ENABLED", "AfkEvent")
		return
	end
	self.pendingRegister = nil
	self:ClearAuraSounds()
	self.auraStatus = nil
	if not self.db.auras then return end
	local api = AuraApi()
	if not api then
		self.auraStatus = L["Not available in this game client: aura alarms are off. Breath, fatigue and AFK alarms still work."]
		return
	end
	local count = 0
	for _, spellID in ipairs(self:SpellList()) do
		if AddSound(api, spellID, api == "full" and Enum.UnitAuraSoundTrigger.Added, self.db.soundHigh, self.db.channel) then
			count = count + 1
		end
		if api == "full" and self.db.stacks and Enum.UnitAuraSoundTrigger.ApplicationsIncreased then
			AddSound(api, spellID, Enum.UnitAuraSoundTrigger.ApplicationsIncreased, self.db.soundStack, self.db.channel)
		end
	end
	if api == "private" then
		self.auraStatus = E:Plural(count, "%d spell watched (private auras only in this client).", "%d spells watched (private auras only in this client)."):format(count)
	else
		self.auraStatus = E:Plural(count, "%d spell watched.", "%d spells watched."):format(count)
	end
end

---------------------------------------------------------------------------
-- Breath, fatigue and AFK
---------------------------------------------------------------------------
-- The breath bar is checked a few times a second on the shared ticker,
-- only while it runs.
local BREATH = "Alerts:breath"

function M:StopBreathWatch()
	E.Ticker:Unsubscribe(BREATH)
	self.breathWatch = nil
end

function M:MIRROR_TIMER_START(_, timer, _, _, scale)
	if timer == "EXHAUSTION" and self.db.fatigue and (scale or 0) < 0 then
		self:Alert(self.db.soundLow)
	elseif timer == "BREATH" and self.db.breath then
		-- Alarm when the breath bar runs out.
		self.breathWatch = true
		E.Ticker:Subscribe(BREATH, 0.25, function()
			local progress = GetMirrorTimerProgress and GetMirrorTimerProgress("BREATH")
			if type(progress) == "number" and not (issecretvalue and issecretvalue(progress)) and progress <= 0 then
				M:StopBreathWatch()
				M:Alert(M.db.soundHigh)
			end
		end, "Alerts")
	end
end

function M:MIRROR_TIMER_STOP(_, timer)
	if timer == "BREATH" and self.breathWatch then self:StopBreathWatch() end
end

-- The AFK flag as last seen plain, for a fight that starts while the live
-- read comes back secret or fails. Moving clears it (the game drops AFK
-- then). These events run only while the AFK alarm is on.
local AFK_EVENTS = { "PLAYER_FLAGS_CHANGED", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "PLAYER_STARTED_MOVING" }

local function ReadAfk()
	local ok, afk = pcall(UnitIsAFK, "player")
	if not ok or (issecretvalue and issecretvalue(afk)) then return nil end
	return afk and true or false
end

function M:AfkEvent(event, unit)
	-- With the AFK alarm off this hears only the end of a fight (for
	-- waiting aura alarms).
	if self.db.afk and event == "PLAYER_STARTED_MOVING" then
		self.afkCached = false
	elseif self.db.afk and (event ~= "PLAYER_FLAGS_CHANGED" or unit == "player") then
		local afk = ReadAfk()
		if afk ~= nil then self.afkCached = afk end
	end
	if event == "PLAYER_REGEN_ENABLED" then self:RetryAuraSounds() end
end

function M:WatchAfk()
	local on = self.active and self.db.afk
	for _, event in ipairs(AFK_EVENTS) do
		-- A fight that ends also lets waiting aura alarms register.
		if on or (event == "PLAYER_REGEN_ENABLED" and self.pendingRegister) then
			self:RegisterEvent(event, "AfkEvent")
		else
			self:UnregisterEvent(event)
		end
	end
	if on then
		local afk = ReadAfk()
		if afk ~= nil then self.afkCached = afk end
	else
		self.afkCached = nil
	end
end

function M:PLAYER_REGEN_DISABLED()
	if not self.db.afk then return end
	local afk = ReadAfk()
	if afk == nil then afk = self.afkCached end
	if afk then self:Alert(self.db.soundHigh) end
end

---------------------------------------------------------------------------
-- Enable / disable
---------------------------------------------------------------------------
function M:OnEnable()
	self:MigrateSounds()
	self:RegisterEvent("MIRROR_TIMER_START", "MIRROR_TIMER_START")
	self:RegisterEvent("MIRROR_TIMER_STOP", "MIRROR_TIMER_STOP")
	self:RegisterEvent("PLAYER_REGEN_DISABLED", "PLAYER_REGEN_DISABLED")
	self:RegisterAuraSounds()
	self:WatchAfk()
end

function M:OnDisable()
	self:UnregisterEvent("MIRROR_TIMER_START")
	self:UnregisterEvent("MIRROR_TIMER_STOP")
	self:UnregisterEvent("PLAYER_REGEN_DISABLED")
	self:UnregisterEvent("ADDON_RESTRICTION_STATE_CHANGED")
	for _, event in ipairs(AFK_EVENTS) do self:UnregisterEvent(event) end
	self.pendingRegister, self.afkCached = nil, nil
	self:StopBreathWatch()
	self:ClearAuraSounds()
end

function M:OnProfileChanged()
	self:MigrateSounds()
	if self.active then
		self:RegisterAuraSounds()
		self:WatchAfk()
	end
end

M.options = {
	{ type = "description", label = "Sound alarms when you stand in harm, played by the game itself; EldoUI never reads the combat log. Off by default: turn it on under Modules." },
	{ type = "header", label = "What to warn about" },
	{ type = "toggle", key = "auras", label = "Standing in bad stuff", desc = "When one of the spell IDs below lands on you." },
	{ type = "toggle", key = "stacks", label = "Warn again when it stacks", desc = "Play the stack sound each time the same bad aura gains another stack.", dependsOn = "auras" },
	{ type = "toggle", key = "breath", label = "Out of breath", desc = "When the breath bar runs out under water." },
	{ type = "toggle", key = "fatigue", label = "Fatigue", desc = "When you swim into deep water fatigue." },
	{ type = "toggle", key = "afk", label = "Attacked while AFK", desc = "Alarm when something hits you while you are marked AFK." },
	{ type = "toggle", key = "flash", label = "Red screen-edge flash", desc = "For breath, fatigue and AFK alarms and the Test buttons. Aura alarms are sound only, because the game plays them." },
	{ type = "input", key = "spells", label = "Spell IDs", desc = "Your own list, separated by commas or spaces. Find an ID on Wowhead (the number in the link)." },
	{ type = "execute", less = true, label = "Check aura alarms", desc = "Shows whether aura alarms are running and how many spell IDs they watch.", func = function()
		E:Print(M.active and (M.auraStatus or L["Aura alarms are off."]) or E:ModuleOffHint("Alerts"))
	end },
	{ type = "header", label = "Sounds" },
	{ type = "select", key = "channel", label = "Sound channel", desc = "Which game volume slider the alarm sounds follow.", values = CHANNELS },
	{ type = "media", mediaKind = "sound", filter = FILE_SOUNDS, key = "soundHigh", channel = "channel", label = "Danger sound",
		desc = "Played when you stand in something from the spell list, when your breath runs out and when something attacks you while you are AFK. Sound files only: the game plays aura sounds from a file." },
	{ type = "media", mediaKind = "sound", filter = FILE_SOUNDS, key = "soundLow", channel = "channel", label = "Fatigue sound",
		desc = "Played when you swim into deep water fatigue." },
	{ type = "media", mediaKind = "sound", filter = FILE_SOUNDS, key = "soundStack", channel = "channel", label = "Stack sound",
		desc = "Played when a bad aura from the spell list stacks again." },
	{ type = "execute", label = "Test danger", desc = "Play the danger alarm once.", func = function() M:Alert(M.db.soundHigh) end },
	{ type = "execute", label = "Test fatigue", desc = "Play the fatigue alarm once.", func = function() M:Alert(M.db.soundLow) end },
	{ type = "execute", label = "Test stack", desc = "Play the stack sound once.", func = function() M:Play(M.db.soundStack) end },
}

-- Style presets (DESIGN.md §5): sounds, the flash and which alarms are on.
-- They never touch the spell list or a position, and none acts for you.
E:RegisterStyles("Alerts", {
	{ key = "Standard", title = L["Standard"], desc = L["Every alarm on, EldoUI's alarm, chime and warning tones, and the red edge flash."],
		settings = { auras = true, stacks = true, breath = true, fatigue = true, afk = true, flash = true, channel = "Master",
			soundHigh = "eldo:EldoAlarm", soundLow = "eldo:EldoChime", soundStack = "eldo:EldoWarning" } },
	{ key = "Quiet", title = L["Quiet"], desc = L["Soft chimes on the effects volume and no flash, for players who only want a nudge."],
		settings = { auras = true, stacks = false, breath = true, fatigue = true, afk = true, flash = false, channel = "SFX",
			soundHigh = "eldo:EldoChime", soundLow = "eldo:Glass", soundStack = "eldo:Glass" } },
	{ key = "Loud", title = L["Loud"], desc = L["Brass and error beeps on the master volume with the flash, hard to miss with music on."],
		settings = { auras = true, stacks = true, breath = true, fatigue = true, afk = true, flash = true, channel = "Master",
			soundHigh = "eldo:Brass", soundLow = "eldo:EldoWarning", soundStack = "eldo:ErrorBeep" } },
	{ key = "Raid", title = L["Raid focus"], desc = L["Only standing in bad stuff and its stacks, with the flash; breath, fatigue and AFK stay quiet."],
		settings = { auras = true, stacks = true, breath = false, fatigue = false, afk = false, flash = true, channel = "Master",
			soundHigh = "eldo:EldoAlarm", soundLow = "eldo:EldoChime", soundStack = "eldo:EldoWarning" } },
	{ key = "Explorer", title = L["Explorer"], desc = L["Breath, fatigue and attacked while AFK, for questing and swimming; no aura alarms."],
		settings = { auras = false, stacks = false, breath = true, fatigue = true, afk = true, flash = true, channel = "Master",
			soundHigh = "eldo:EldoAlarm", soundLow = "eldo:EldoChime", soundStack = "eldo:EldoWarning" } },
	{ key = "Fun", title = L["Barnyard"], desc = L["Every alarm on with the chicken alarm, an oh no and a squeaky toy, and the flash."],
		settings = { auras = true, stacks = true, breath = true, fatigue = true, afk = true, flash = true, channel = "Master",
			soundHigh = "eldo:ChickenAlarm", soundLow = "eldo:OhNo", soundStack = "eldo:SqueakyToy" } },
})
