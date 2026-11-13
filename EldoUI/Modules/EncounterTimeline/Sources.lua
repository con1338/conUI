-- Encounter Timeline: where the timers come from.
--
--   DBM      the public callbacks DBM_TimerBegin / Stop / Update / Pause /
--            Resume / UpdateIcon / UpdateName and DBM_Wipe / DBM_Kill
--            (DBM-Core's documented list; DBM no longer fires
--            DBM_TimerStart, so it is never registered)
--   BigWigs  BigWigsLoader.RegisterMessage: BigWigs_StartBar / StopBar /
--            PauseBar / ResumeBar / StopBars / OnBossDisable
--   Blizzard START_PLAYER_COUNTDOWN / CANCEL_PLAYER_COUNTDOWN (the pull),
--            READY_CHECK / READY_CHECK_FINISHED, ENCOUNTER_END,
--            PLAYER_ENTERING_WORLD
--
-- Pull countdowns arrive up to three times (Blizzard's event, DBM's pull
-- bar, BigWigs' pull bar): only Blizzard's makes the pull row. DBM's is
-- dropped by its timer type, BigWigs' by the plugin that sends it, never by
-- comparing a localized text.
--
-- Source choice ("auto") keeps every timer once: DBM while the player uses
-- EldoUI's DBM profile, else BigWigs while the Integrations module runs it,
-- else whichever boss mod is loaded. "both" listens to both and drops the
-- second copy of a timer (Store: same spell id, end within 0.5 s).
local _, E = ...
local M = E:GetModule("EncounterTimeline")

local issecret = issecretvalue or function() return false end
local Number, String = M.Number, M.String

local QUESTION_ICON = 134400 -- INV_Misc_QuestionMark
local KIND_ICON = {
	pull = 132337,  -- Ability_Warrior_Charge
	["break"] = 134062, -- a food icon
	ready = 134376, -- INV_Misc_PocketWatch_01
	other = 134376,
}
M.QUESTION_ICON, M.KIND_ICON = QUESTION_ICON, KIND_ICON

-- DBM's simple timer types that belong to the encounter.
local DBM_BOSS_TYPES = { cd = true, target = true, stage = true, cast = true, berserk = true, cdnp = true, castnp = true }

local function HasDBM()
	local dbm = _G.DBM
	return type(dbm) == "table" and type(dbm.RegisterCallback) == "function"
end

local function HasBigWigs()
	local loader = _G.BigWigsLoader
	return type(loader) == "table" and type(loader.RegisterMessage) == "function"
end

function M:DBMVersion()
	if not HasDBM() then return nil end
	return String(_G.DBM.DisplayVersion) or "loaded"
end

function M:BigWigsVersion()
	if not HasBigWigs() then return nil end
	local ok, version = pcall(C_AddOns.GetAddOnMetadata, "BigWigs", "Version")
	return ok and String(version) or "loaded"
end

-- Which boss mods the timeline listens to right now.
function M:ActiveSources()
	local dbm, bw = HasDBM(), HasBigWigs()
	local choice = self.db and self.db.source or "auto"
	if choice == "dbm" then return { dbm = dbm, bigwigs = false } end
	if choice == "bigwigs" then return { dbm = false, bigwigs = bw } end
	if choice == "both" then return { dbm = dbm, bigwigs = bw } end
	local private = E.GetPrivate and E:GetPrivate("dbm")
	if dbm and type(private) == "table" and private.optedIn then return { dbm = true, bigwigs = false } end
	local integrations = E.modules.Integrations
	if bw and integrations and integrations.active and integrations.On and integrations:On("bigwigs") then
		return { dbm = false, bigwigs = true }
	end
	if dbm then return { dbm = true, bigwigs = false } end
	return { dbm = false, bigwigs = bw }
end

function M:UpdateSources()
	self.listen = self:ActiveSources()
	self:AttachSources()
end

-- A boss-mod timer arrived: a test fight on screen makes room for it.
local function RealTimer()
	if M.testing then M:StopTest() end
end

-- The icon to draw: a secret one becomes the question mark (counted), a
-- plain number or path goes straight to SetTexture.
local function Icon(icon, kind, info)
	if issecret(icon) then
		info.secretIcon = true
		return QUESTION_ICON
	end
	if type(icon) == "number" or (type(icon) == "string" and icon ~= "") then return icon end
	return KIND_ICON[kind] or QUESTION_ICON
end

local function SpellId(value, info)
	if issecret(value) then
		info.secretSpell = true
		return nil
	end
	if type(value) == "number" and value > 0 then return value end
	return nil
end

---------------------------------------------------------------------------
-- DBM
---------------------------------------------------------------------------
-- DBM's own start color for a color type, from the player's DBT options.
local function DBMColor(colorId)
	local dbt = _G.DBT
	if not (colorId and type(dbt) == "table" and type(dbt.GetColorForType) == "function") then return nil end
	local ok, r, g, b = pcall(dbt.GetColorForType, dbt, colorId)
	if not ok then return nil end
	r, g, b = Number(r), Number(g), Number(b)
	if not (r and g and b) then return nil end
	if r >= 0.99 and g >= 0.99 and b >= 0.99 then return nil end
	return { r, g, b }
end

local dbmHandlers = {}

-- Payload (DBM-Core Timer.lua): 1 id, 2 text, 3 duration, 4 icon, 5 simple
-- type, 6 spellId, 7 colorId, 8 mod id, 9 keep, 10 fade, 11 spell name,
-- 12 GUID, 13 count, ... 18 isEnabled, 19 textOnly. Later extra arguments
-- are ignored. isEnabled false still shows: the player may hide DBM's bar,
-- DBM still published the timer.
function dbmHandlers.DBM_TimerBegin(_, id, text, duration, icon, simple, spellId, colorId, _, keep, _, _, _, count)
	if not (M.listen and M.listen.dbm) then return end
	id = String(id)
	if not id then return end
	simple = String(simple)
	local info = { source = "dbm", simple = simple, secretText = issecret(text) }
	if issecret(duration) then
		M:CountSecretDrop()
		info.kind, info.duration = "dropped", 0
		M:NoteReceived(info)
		return
	end
	local kind
	if simple == "pull" then
		kind = nil -- the Blizzard countdown draws the pull
	elseif simple == "break" then
		kind = "break"
	elseif simple and DBM_BOSS_TYPES[simple] then
		kind = "boss"
	else
		kind = "other"
	end
	info.kind, info.duration = kind or "pull (dropped)", Number(duration) or 0
	if not kind then
		M:NoteReceived(info)
		return
	end
	RealTimer()
	colorId = Number(colorId)
	local row = M:Add({
		key = "dbm:" .. id, source = "dbm", kind = kind, text = text,
		icon = Icon(icon, kind, info), spellId = SpellId(spellId, info),
		duration = duration, color = DBMColor(colorId), colorType = colorId,
		count = Number(count), keep = keep == true,
	})
	M:NoteReceived(info)
	if row then M:Refresh() end
end

function dbmHandlers.DBM_TimerStop(_, id)
	id = String(id)
	if id then M:Stop("dbm:" .. id) end
end

-- elapsed and the new total (not a delta).
function dbmHandlers.DBM_TimerUpdate(_, id, elapsed, total)
	id = String(id)
	if id and M:UpdateRow("dbm:" .. id, elapsed, total) then M:Refresh() end
end

function dbmHandlers.DBM_TimerPause(_, id)
	id = String(id)
	if id and M:Pause("dbm:" .. id) then M:Refresh() end
end

function dbmHandlers.DBM_TimerResume(_, id)
	id = String(id)
	if id and M:Resume("dbm:" .. id) then M:Refresh() end
end

function dbmHandlers.DBM_TimerUpdateIcon(_, id, icon)
	id = String(id)
	local row = id and M:Get("dbm:" .. id)
	if not row then return end
	if issecret(icon) then
		row.icon = QUESTION_ICON
	elseif type(icon) == "number" or (type(icon) == "string" and icon ~= "") then
		row.icon = icon
	end
	M:Refresh()
end

function dbmHandlers.DBM_TimerUpdateName(_, id, name)
	id = String(id)
	local row = id and M:Get("dbm:" .. id)
	if not row then return end
	-- A secret name is fine: it only ever reaches SetText.
	if issecret(name) or type(name) == "string" then row.text = name end
	M:Refresh()
end

local function DBMEncounterOver()
	M:ClearSoon(function(row) return row.source == "dbm" and row.kind == "boss" end)
end
dbmHandlers.DBM_Wipe = DBMEncounterOver
dbmHandlers.DBM_Kill = DBMEncounterOver
M.dbmHandlers = dbmHandlers

---------------------------------------------------------------------------
-- BigWigs
---------------------------------------------------------------------------
local bwOwner = {} -- the "addon" table BigWigsLoader keys our messages by

-- Plugins by the name BigWigs gives them (BigWigs_Plugins_<Name>).
local function PluginName(module)
	if type(module) ~= "table" then return nil end
	local name = rawget(module, "name")
	if issecret(name) or type(name) ~= "string" then return nil end
	return name:match("^BigWigs_Plugins_(.+)$")
end

local function ModuleName(module)
	if type(module) ~= "table" then return "api" end
	local name = rawget(module, "name")
	if issecret(name) or type(name) ~= "string" then return "?" end
	return name
end

-- The key of a BigWigs bar: module + text while the text is plain, else
-- BigWigs' event id; a secret text without one is ignored.
local function BWKey(module, text, eventId)
	if not issecret(text) and type(text) == "string" and text ~= "" then
		return "bw:" .. ModuleName(module) .. ":" .. text
	end
	eventId = Number(eventId)
	if eventId then return "bw:e" .. eventId end
	return nil
end

-- The player's BigWigs bar color for this bar (Colors plugin).
local function BWColor(module, key)
	local bigwigs = _G.BigWigs
	if type(bigwigs) ~= "table" or type(bigwigs.GetPlugin) ~= "function" then return nil end
	local ok, colors = pcall(bigwigs.GetPlugin, bigwigs, "Colors", true)
	if not ok or type(colors) ~= "table" or type(colors.GetColorTable) ~= "function" then return nil end
	if issecret(key) then key = nil end
	local okColor, t = pcall(colors.GetColorTable, colors, "barBackground", module, key)
	if not okColor or type(t) ~= "table" then return nil end
	local r, g, b = Number(t[1] or t.r), Number(t[2] or t.g), Number(t[3] or t.b)
	if not (r and g and b) or (r >= 0.99 and g >= 0.99 and b >= 0.99) then return nil end
	return { r, g, b }
end

local bwHandlers = {}

-- (module, key, text, time, icon, isApprox, maxTime, eventId, ...)
function bwHandlers.BigWigs_StartBar(_, module, key, text, time, icon, _, _, eventId)
	if not (M.listen and M.listen.bigwigs) then return end
	local plugin = PluginName(module)
	local info = { source = "bigwigs", simple = plugin and ("plugin " .. plugin) or "bar", secretText = issecret(text) }
	if issecret(time) then
		M:CountSecretDrop()
		info.kind, info.duration = "dropped", 0
		M:NoteReceived(info)
		return
	end
	local kind
	if plugin == "Pull" then
		kind = nil
	elseif plugin == "Break" then
		kind = "break"
	elseif module == nil or plugin then
		kind = "other" -- another addon's API bar, custom bars, test bars
	else
		kind = "boss"
	end
	info.kind, info.duration = kind or "pull (dropped)", Number(time) or 0
	local rowKey = kind and BWKey(module, text, eventId)
	if not rowKey then
		M:NoteReceived(info)
		return
	end
	RealTimer()
	local row = M:Add({
		key = rowKey, source = "bigwigs", kind = kind, text = text, module = ModuleName(module),
		icon = Icon(icon, kind, info), spellId = SpellId(key, info), duration = time,
		color = BWColor(module, key),
	})
	M:NoteReceived(info)
	if row then M:Refresh() end
end

function bwHandlers.BigWigs_StopBar(_, module, text, eventId)
	local key = BWKey(module, text, eventId)
	if key then M:Stop(key) end
end

function bwHandlers.BigWigs_PauseBar(_, module, text, eventId)
	local key = BWKey(module, text, eventId)
	if key and M:Pause(key) then M:Refresh() end
end

function bwHandlers.BigWigs_ResumeBar(_, module, text, eventId)
	local key = BWKey(module, text, eventId)
	if key and M:Resume(key) then M:Refresh() end
end

-- Only the sending module's rows go.
local function BWModuleOff(_, module)
	local name = ModuleName(module)
	M:ClearSoon(function(row) return row.source == "bigwigs" and row.module == name end)
end
bwHandlers.BigWigs_StopBars = BWModuleOff
bwHandlers.BigWigs_OnBossDisable = BWModuleOff
M.bwHandlers = bwHandlers

---------------------------------------------------------------------------
-- Registering
---------------------------------------------------------------------------
function M:AttachSources()
	if not self.active then return end
	if HasDBM() and not self.dbmAttached then
		local dbm = _G.DBM
		local done = {}
		for event, fn in pairs(dbmHandlers) do
			local ok = pcall(dbm.RegisterCallback, dbm, event, fn)
			if ok then done[event] = fn end
		end
		self.dbmAttached = { dbm = dbm, handlers = done }
	end
	if HasBigWigs() and not self.bwAttached then
		local loader = _G.BigWigsLoader
		for message, fn in pairs(bwHandlers) do
			pcall(loader.RegisterMessage, bwOwner, message, fn)
		end
		self.bwAttached = loader
	end
end

function M:DetachSources()
	local attached = self.dbmAttached
	if attached then
		local dbm = attached.dbm
		if type(dbm.UnregisterCallback) == "function" then
			for event, fn in pairs(attached.handlers) do pcall(dbm.UnregisterCallback, dbm, event, fn) end
		end
		self.dbmAttached = nil
	end
	local loader = self.bwAttached
	if loader then
		if type(loader.UnregisterMessage) == "function" then
			for message in pairs(bwHandlers) do pcall(loader.UnregisterMessage, bwOwner, message) end
		end
		self.bwAttached = nil
	end
end

-- A boss mod that loads later (or reloads its options) is picked up here.
local BOSS_ADDONS = { ["DBM-Core"] = true, BigWigs = true, BigWigs_Core = true, BigWigs_Plugins = true }

---------------------------------------------------------------------------
-- Blizzard events
---------------------------------------------------------------------------
local events = {}

-- (initiatedBy, timeRemaining, totalTime, informChat, initiatedByName)
function events.START_PLAYER_COUNTDOWN(_, _, _, remaining, total, _, name)
	if issecret(remaining) or issecret(total) then
		M:CountSecretDrop()
		return
	end
	remaining, total = Number(remaining), Number(total)
	if not (remaining and total) or remaining <= 0 then return end
	if total < remaining then total = remaining end
	RealTimer()
	M:Add({
		key = "pull", source = "blizzard", kind = "pull", text = E.L["Pull"], icon = KIND_ICON.pull,
		duration = total, elapsed = total - remaining, from = String(name),
	})
	M:Refresh()
end

function events.CANCEL_PLAYER_COUNTDOWN()
	M:Stop("pull")
end

-- (initiatorName, readyCheckTimeLeft)
function events.READY_CHECK(_, _, name, timeLeft)
	if issecret(timeLeft) then
		M:CountSecretDrop()
		return
	end
	timeLeft = Number(timeLeft)
	if not timeLeft or timeLeft <= 0 then return end
	M:Add({
		key = "ready", source = "blizzard", kind = "ready", text = _G.READY_CHECK or E.L["Ready check"],
		icon = KIND_ICON.ready, duration = timeLeft, from = String(name),
	})
	M:Refresh()
end

function events.READY_CHECK_FINISHED()
	M:Stop("ready")
end

function events.ENCOUNTER_END()
	M:ClearSoon(function(row) return row.kind == "boss" end)
end

function events.PLAYER_ENTERING_WORLD()
	M:ClearAll(false)
	M:Refresh()
end

function events.ADDON_LOADED(_, _, addon)
	if BOSS_ADDONS[addon] and M.active then M:UpdateSources() end
end

function events.PLAYER_LOGIN()
	if M.active then M:UpdateSources() end
end

M.sourceEvents = events

function M:EnableSources()
	for event, fn in pairs(events) do self:RegisterEvent(event, fn) end
	self:UpdateSources()
end

function M:DisableSources()
	for event in pairs(events) do self:UnregisterEvent(event) end
	self:DetachSources()
	self.listen = nil
end

---------------------------------------------------------------------------
-- Fade DBM's own bars (off by default): DBT Alpha / HugeAlpha in EldoUI's
-- DBM profile, through the DBM module's type-checked writer. Never
-- HideDBMBars (DBM would stop publishing), never a DBT skin.
---------------------------------------------------------------------------
function M:FadeAvailable()
	local dbm = E.modules.DBM
	return dbm and dbm.active and dbm.Writable and dbm:Writable() and type(dbm.SetTimelineFade) == "function" or false
end

function M:ApplyFade()
	local dbm = E.modules.DBM
	if not (dbm and type(dbm.SetTimelineFade) == "function") then return end
	local want = self.active and self.db.fadeDBM and self:FadeAvailable()
	if want then
		dbm:SetTimelineFade(M.Clamp(self.db.fadeDBMAlpha, 0, 0.8, 0))
	elseif dbm.TimelineFadeActive and dbm:TimelineFadeActive() then
		dbm:SetTimelineFade(nil)
	end
end
