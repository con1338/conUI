-- EldoUI Instances: every dungeon run you enter, counted
-- against the server's hourly instance limit.
--
-- This file is the module shell the other Instances files build on:
--   * the module and its settings (E.db.modules.Instances)
--   * the run store EldoUIDB.instances (account-wide, newest first)
--   * the zone state machine: enter and leave on PLAYER_ENTERING_WORLD with
--     IsInInstance / GetInstanceInfo, reloads and logons inside, ghost runs
--     (released or resurrected at the door) that never count twice
--   * the hourly (and optional daily) count per ruleset, shown as an
--     estimate, with a free-slot notice on a timer at the exact expiry
--   * same-run detection: the instance part (zone UID, field 5) of creature
--     and spell cast GUIDs the game hands out; walking out and back into
--     the same instance merges the two entries
--   * the raid lockouts of each character (GetSavedInstanceInfo)
--   * the "Instances" datatext and /eui instances
--   * the run recorder for other modules: M:EnsureRecorder(owner,
--     on) records runs (and their XP, kills, gold, group and bosses) while
--     the Instances module is off, with no notices, summaries, timers or
--     window. My Adventure uses it, so its journal knows your runs.
--     M:Recording() is true while runs are recorded either way.
--     M:Runs(charKey) lists one character's runs (newest first);
--     run.bosses counts the bosses killed (ENCOUNTER_END / BOSS_KILL).
--
-- How the limit works: the server lets an account enter a limited number
-- of new instances per hour (5 on Forever, counted over all characters on
-- the same ruleset, the "realm" on Forever; the Forever dungeon guides give
-- five resets per hour, where the modern game allows ten). EldoUI only sees
-- your own entries, so the count is an estimate and is labeled as one.
-- Whether a raid entry counts is not settled for Forever, so raids count
-- only with "Count raids" on, and the player can set the limit.
--
-- Rules (Midnight / Forever): presentation only. No combat log, nothing is
-- sent to chat or to other players without a click (Reset.lua sends the
-- leader's reset notice as an addon message, never in a PvP match). Every
-- GUID, unit and chat text read is checked with issecretvalue; a secret
-- value is skipped, never stored. The other files reach this module as
-- E.Instances.
local _, E = ...
local L = E.L

local Key = E.Key
local M = E:NewModule("Instances", {
	title = "Instances",
	desc = L["Counts your dungeon entries against the hourly instance limit, logs every run with its XP, kills, gold and reputation, tells you when instances were reset and keeps a battleground log."],
	category = "Group",
	frames = { "EldoUI_InstanceLogAnchor" },
	movers = { "EldoUI_InstanceLog" },
	blizzard = {},
	savedKeys = { "profile.modules.Instances", "EldoUIDB.instances" },
	optionsPage = "module:Instances",
	presets = { "Booster", "Compact", "Full", "Leveling", "MaxLevel", "Quiet" },
	uiAmount = "full",
	reload = false,
	defaults = {
		enabled = false,
		-- Limit
		hourlyLimit = 5,
		dailyLimit = 0,          -- 0: no daily limit
		countRaids = false,
		detectSameRun = true,
		keepRuns = 250,
		-- Notices (own chat only)
		noticeEnter = true,
		noticeRaid = false,
		noticePvP = true,
		noticeMerge = true,
		noticeFree = true,
		freeSound = "none",
		-- End-of-run summary (Stats.lua)
		summary = true,
		summaryOnlyActivity = true,
		show = {
			time = true, kills = true, xp = true, xpPercent = true, xpHour = true, xpKill = false,
			gold = true, rep = true, currency = true, groupLevel = false, runsLevel = true, runsNext = false, honor = true,
		},
		-- Sharing (acts for you: off)
		allowPosting = false,
		-- Reset notices (Reset.lua)
		resetNotice = true,
		leaderSend = false,       -- addon message on every reset you lead: opt-in
		leaderShow = true,
		announceReset = false,
		-- Log window (Log.lua)
		logAlts = true,
		log24h = false,
		logLockoutTime = true,
		durationStyle = "medium", -- long, medium, short
		clock = "infobar",        -- infobar, 24, 12
		transparent = false,
		window = {},              -- scale and last tab of the log window
	},
})
E.Instances = M

local floor, max, min = math.floor, math.max, math.min
local HOUR, DAY = 3600, 86400
local KEEP_MIN, KEEP_MAX = 50, 500
local GHOST_LEAVE_WINDOW = 5   -- PLAYER_LEAVING_WORLD as a ghost
local UNGHOST_WINDOW = 4       -- PLAYER_UNGHOST (resurrected at the door)
local GHOST_RETURN = 30 * 60   -- a death exit may come back this long after
local RELOAD_RETURN = 300      -- a reload resumes the run left on logout
local MANUAL_MERGE = HOUR      -- "Same run as last" for entries this close

-- Status colors, rebuilt when the color-blind safe colors are switched
-- (M.COLORS keeps its table, so the other files read the current ones).
-- UNCOUNTED (dim) is the look of a run that doesn't count; its row also
-- says so in words.
local GREEN, YELLOW, RED, GREY
M.COLORS = {}
E:OnStatusColors(function()
	GREEN, YELLOW, RED, GREY = E:TextHex("good"), E:TextHex("warn"), E:TextHex("bad"), E:TextHex("secondary")
	local colors = M.COLORS
	colors.GREEN, colors.YELLOW, colors.RED, colors.GREY, colors.UNCOUNTED = GREEN, YELLOW, RED, GREY, E:TextHex("dim")
end)

local IsSecret = E.Secret
M.IsSecret = IsSecret

-- A value the game handed us, or nil when it is secret.
local Plain = E.Plain
M.Plain = Plain

local function Try(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a, b, c, d, e, f, g, h, i, j, k, l = pcall(fn, ...)
	if not ok then return nil end
	return a, b, c, d, e, f, g, h, i, j, k, l
end
M.Try = Try

local function AccentHex()
	local c = E.media.accentText
	return ("|cff%02x%02x%02x"):format(c[1] * 255, c[2] * 255, c[3] * 255)
end
M.AccentHex = AccentHex

function M:Now()
	local now = Try(GetServerTime)
	if type(now) ~= "number" then now = time() end
	return now
end

---------------------------------------------------------------------------
-- Events: every Instances file registers here; one game event handler per
-- event fans out to them, and they are on only while the module is.
---------------------------------------------------------------------------
local eventHandlers = {} -- event -> { key -> fn(event, ...) }

local function Dispatch(_, event, ...)
	local list = eventHandlers[event]
	if not list then return end
	for key, fn in pairs(list) do
		local ok, err = pcall(fn, event, ...)
		if not ok then geterrorhandler()(("EldoUI Instances %s (%s): %s"):format(event, tostring(key), tostring(err))) end
	end
end

-- The listeners the run recorder keeps while the module is off: the zone
-- state machine and the run's stats. Notices, resets and lockouts stay off.
local RECORDER_KEYS = { zone = true, stats = true, pvp = true, zoneuid = true, bosses = true }
local recorderFrame = CreateFrame("Frame")
recorderFrame:SetScript("OnEvent", function(_, event, ...)
	if M.active then return end
	local list = eventHandlers[event]
	if not list then return end
	for key, fn in pairs(list) do
		if RECORDER_KEYS[key] then
			local ok, err = pcall(fn, event, ...)
			if not ok then geterrorhandler()(("EldoUI Instances %s (%s): %s"):format(event, tostring(key), tostring(err))) end
		end
	end
end)

local function RecorderWanted(event)
	for key in pairs(eventHandlers[event] or {}) do
		if RECORDER_KEYS[key] then return true end
	end
	return false
end

function M:Listen(event, key, fn)
	eventHandlers[event] = eventHandlers[event] or {}
	eventHandlers[event][key] = fn
	if self.active then self:RegisterEvent(event, Dispatch) end
	if self.recorderOn and RECORDER_KEYS[key] then pcall(recorderFrame.RegisterEvent, recorderFrame, event) end
end

-- Hand one event to this module's listeners only (a plugin can drive
-- the module with it). Does nothing while the module is off.
function M:HandleEvent(event, ...)
	if self.active and eventHandlers[event] then Dispatch(nil, event, ...) end
end

---------------------------------------------------------------------------
-- The run recorder for other modules (My Adventure): runs are recorded
-- while any owner wants them, with the module off too.
---------------------------------------------------------------------------
local recorderOwners = {}

-- Runs are being recorded (the module is on, or the recorder runs).
function M:Recording()
	return self.active or self.recorderOn or false
end

local function SyncRecorder()
	local want = next(recorderOwners) ~= nil and not M.active
	if want == (M.recorderOn or false) then return end
	M.recorderOn = want or nil
	recorderFrame:UnregisterAllEvents()
	if want then
		for event in pairs(eventHandlers) do
			if RecorderWanted(event) then pcall(recorderFrame.RegisterEvent, recorderFrame, event) end
		end
		M:Store()
		-- Pick up where the player stands now, like OnEnable.
		if IsLoggedIn and IsLoggedIn() then
			local open, here = M:OpenRun(), M:Here()
			if open and here and M.SameInstance(open, here) then
				M:SetCurrent(open)
			elseif open and not here then
				M:CloseRun(open, "left")
			end
		end
	elseif not M.active then
		M.current = nil
		M:WatchZoneUID()
	end
end
M.SyncRecorder = SyncRecorder

-- owner: a key ("adventure"); on: true to want runs recorded.
function M:EnsureRecorder(owner, on)
	if type(owner) ~= "string" then return end
	recorderOwners[owner] = on and true or nil
	SyncRecorder()
end

-- One character's runs, newest first. charKey: E.charKey style (the
-- Characters store key) or this module's "Name - Ruleset"; nil: every run.
function M:RunsFor(charKey)
	local runs = self:Store().runs
	if charKey == nil then return runs end
	local key = self:KeyFor(charKey) or charKey
	local out = {}
	for _, run in ipairs(runs) do
		if type(run) == "table" and run.char == key then out[#out + 1] = run end
	end
	return out
end

function M:StopListening(event, key)
	local list = eventHandlers[event]
	if not list then return end
	list[key] = nil
	if next(list) == nil then
		eventHandlers[event] = nil
		self:UnregisterEvent(event)
	end
end

---------------------------------------------------------------------------
-- Change listeners: the datatext, the log window and RaidTools redraw on
-- M:Changed(what) ("runs", "count", "lockouts", "reset").
---------------------------------------------------------------------------
local changeListeners = {}

function M:OnChange(key, fn)
	changeListeners[key] = fn
end

-- Callbacks for other modules: M:RegisterCallback(event, owner, fn),
-- M:UnregisterCallback(event, owner).
--   "RunClosed"(run, how)   a run was left (how as for M:CloseRun); its
--                           stats and the group it saw are final for now
--                           (the run opens again when you walk back in)
-- My Adventure keeps its own copy of every run from here, so the journal
-- keeps a run after this log lets it go.
local callbacks = {}

function M:RegisterCallback(event, owner, fn)
	if type(event) ~= "string" or owner == nil then return end
	callbacks[event] = callbacks[event] or {}
	callbacks[event][owner] = type(fn) == "function" and fn or nil
end

function M:UnregisterCallback(event, owner)
	if callbacks[event] then callbacks[event][owner] = nil end
end

local function FireCallback(event, ...)
	for owner, fn in pairs(callbacks[event] or {}) do
		local ok, err = pcall(fn, ...)
		if not ok then geterrorhandler()(("EldoUI Instances callback %s (%s): %s"):format(event, tostring(owner), tostring(err))) end
	end
end

function M:Changed(what)
	for key, fn in pairs(changeListeners) do
		local ok, err = pcall(fn, what)
		if not ok then geterrorhandler()(("EldoUI Instances listener %s: %s"):format(tostring(key), tostring(err))) end
	end
	local bar = E:GetModule("InfoBar")
	if bar and bar.active and bar.RefreshDataText then Try(bar.RefreshDataText, bar, "Instances") end
end

---------------------------------------------------------------------------
-- Store: EldoUIDB.instances = { version, nextID, runs = { newest first },
-- chars = { [charKey] = { class, lockouts, lockoutsAt } } }
--
-- A run: id, char ("Name - Ruleset"), name, class, realm, instance,
-- instanceID, difficulty, difficultyName, kind ("party", "raid", "pvp"),
-- enter, leave (server time), enterLevel, leaveLevel, enterXP, enterXPMax,
-- leaveXP, enterMoney, leaveMoney, and the stats Stats.lua collects
-- (xp, kills, money, rep, currency, group, honor, ...). zoneUID is the
-- instance part of GUIDs seen inside; merged counts the entries folded in.
-- group = { [name] = { level, class, guild, role, realm, key, first, last,
-- me } }: everyone the roster snapshots saw (dungeons and raids; nobody in
-- battlegrounds), keyed "Name" or "Name-Realm"; role only when the game
-- assigned one, realm only another realm's, key the companion key My
-- Adventure uses, first and last when the member was seen, me on your own
-- entry. Older runs saved a raid as groupSize and an average level only.
---------------------------------------------------------------------------
-- The store is a registered saved store (Core/Database.lua): the first
-- time a session reads it, a copy is kept when an update will change it,
-- and the load check below repairs what it can and sets aside what it
-- cannot read. Runs and the members they list are never trimmed on load:
-- a run saved with its raid members by name keeps them.
--
-- The load check: the runs list closes up a gap in its order, a run that
-- is not a table is set aside, nextID saved as text becomes a number, and
-- a character's lockouts of the wrong kind are set aside.
local function CheckStore(store, C)
	local runs = C.List(store, "runs")
	for index = #runs, 1, -1 do
		if type(runs[index]) ~= "table" then
			C.Keep("runs." .. index, runs[index], "Expected a table.")
			table.remove(runs, index)
		end
	end
	local chars = C.Table(store, "chars")
	for key, record in pairs(chars) do
		if type(record) ~= "table" then
			C.Keep("chars." .. tostring(key), record, "Expected a table.")
			chars[key] = nil
		elseif record.lockouts ~= nil and type(record.lockouts) ~= "table" then
			C.Keep("chars." .. tostring(key) .. ".lockouts", record.lockouts, "Expected a table.")
			record.lockouts = nil
		end
	end
	C.Number(store, "nextID", nil, 1)
end

E:RegisterStore("instances", { title = "Instance log", validate = CheckStore })

local checked = setmetatable({}, { __mode = "k" })

function M:Store()
	if type(EldoUIDB) ~= "table" then EldoUIDB = {} end
	local store = EldoUIDB.instances
	if type(store) ~= "table" then
		-- Anything else saved here is kept inside the new table.
		store = E:KeepInNewTable(store, "instances")
		EldoUIDB.instances = store
	end
	if not checked[store] then
		checked[store] = true
		E:MigrateStore("instances", store)
	end
	if type(store.runs) ~= "table" then store.runs = {} end
	if type(store.chars) ~= "table" then store.chars = {} end
	store.nextID = tonumber(store.nextID) or 1
	if not checked[store.chars] then
		checked[store.chars] = true
		self:MoveCharKey(store)
	end
	return store
end

-- A character whose records moved from its first-name key to its full-name
-- key at login (the GUID named it the owner; Core/Database.lua) takes its
-- instance record and runs with it, once. Another character with the same
-- first name never does.
function M:MoveCharKey(store)
	if type(E.charKeyMovedFrom) ~= "string" then return end
	local old = ("%s - %s"):format(E:PlayerName() or "?", self:RealmKey())
	local new = self:CharKey()
	if old == new then return end
	if store.chars[old] ~= nil and store.chars[new] == nil then
		store.chars[new], store.chars[old] = store.chars[old], nil
		for _, run in ipairs(store.runs) do
			if type(run) == "table" and run.char == old then run.char = new end
		end
	end
end

-- Every run (newest first); with a charKey, that character's runs only.
function M:Runs(charKey)
	if charKey ~= nil then return self:RunsFor(charKey) end
	return self:Store().runs
end

-- The realm key the hourly limit is shared on: the ruleset on Forever.
function M:RealmKey()
	return E:RealmKey()
end

function M:CharKey()
	return ("%s - %s"):format(E:CharacterName() or "?", self:RealmKey())
end

-- The run and record key of a character in the Characters store: the name
-- part of its store key (the full name since the surname keys) and its
-- realm key. Every reader builds the key here, so runs saved under the
-- full name are found again. nil when the realm key is unknown.
function M:KeyFor(charKey)
	if charKey == E.charKey then return self:CharKey() end
	if type(charKey) ~= "string" then return nil end
	local C = E.Characters
	local record = C and C.Get and C:Get(charKey)
	local name = charKey:match("^(.-) %- ") or (type(record) == "table" and record.name)
	if type(name) ~= "string" or name == "" then return nil end
	local realmKey = type(record) == "table" and (record.realmKey
		or (record.realm == GetRealmName() and self:RealmKey())) or nil
	if not realmKey then return nil end
	return ("%s - %s"):format(name, tostring(realmKey))
end

function M:CharRecord(key)
	local chars = self:Store().chars
	key = key or self:CharKey()
	if type(chars[key]) ~= "table" then chars[key] = {} end
	return chars[key]
end

-- A character forgotten on the Alts page (E.Characters:Forget):
-- its lockouts and runs leave the store. Runs of the last day stay,
-- because they still count toward the account's hourly and daily limit.
-- key: "Name - <realm key>" (M:CharKey of that character). Never the
-- current character. Returns how many runs were removed.
function M:ForgetCharacter(key)
	if type(key) ~= "string" or key == self:CharKey() then return 0 end
	local store = self:Store()
	store.chars[key] = nil
	local now, removed = self:Now(), 0
	local runs = store.runs
	for index = #runs, 1, -1 do
		local run = runs[index]
		if type(run) == "table" and run.char == key and run.leave and now - run.leave >= DAY then
			table.remove(runs, index)
			removed = removed + 1
		end
	end
	if removed > 0 then self:Changed("runs") end
	return removed
end

function M:FindRun(id)
	id = tonumber(id)
	if not id then return nil end
	for index, run in ipairs(self:Runs()) do
		if run.id == id then return run, index end
	end
end

-- The run of this character that is still open (entered, not left).
function M:OpenRun()
	local key = self:CharKey()
	for _, run in ipairs(self:Runs()) do
		if run.char == key then
			if not run.leave then return run end
			return nil
		end
	end
end

-- This character's newest run, open or not.
function M:LastRun()
	local key = self:CharKey()
	for _, run in ipairs(self:Runs()) do
		if run.char == key then return run end
	end
end

-- The run of the same character entered before `run`.
function M:PreviousRun(run)
	local _, index = self:FindRun(run.id)
	if not index then return nil end
	local runs = self:Runs()
	for i = index + 1, #runs do
		if runs[i].char == run.char then return runs[i] end
	end
end

function M:Current()
	return self.current
end

function M:Trim()
	local runs = self:Runs()
	local keep = max(KEEP_MIN, min(KEEP_MAX, tonumber(self.db.keepRuns) or 250))
	for index = #runs, keep + 1, -1 do
		if runs[index] ~= self.current then table.remove(runs, index) end
	end
end

---------------------------------------------------------------------------
-- Counting
---------------------------------------------------------------------------
-- Does this run count toward the limit? Dungeons do; raids only with
-- "Count raids"; battlegrounds never.
function M:Counts(run)
	if run.kind == "pvp" or run.uncounted then return false end
	if run.kind == "raid" then return self.db.countRaids and true or false end
	return run.kind == "party"
end

-- The time a run counts from: when it was left, or now while inside.
function M:CountTime(run, now)
	return run.leave or now or self:Now()
end

-- Runs that count in the window (seconds) on this ruleset, oldest first.
function M:CountedRuns(window, now)
	now = now or self:Now()
	local realm = self:RealmKey()
	local list = {}
	for _, run in ipairs(self:Runs()) do
		if run.realm == realm and self:Counts(run) then
			local at = self:CountTime(run, now)
			if now - at < window then list[#list + 1] = run end
		end
	end
	table.sort(list, function(a, b)
		local ta, tb = a.leave or math.huge, b.leave or math.huge
		if ta == tb then return (a.enter or 0) < (b.enter or 0) end
		return ta < tb
	end)
	return list
end

-- Seconds until the count in a window drops below the limit (0: below now;
-- nil: only an open run holds it).
local function WaitFor(list, limit, window, now)
	if #list < limit then return 0 end
	local run = list[#list - limit + 1]
	if not run.leave then return nil end
	return max(0, run.leave + window - now)
end

-- hour count, day count, seconds until the next entry is allowed (0 now,
-- nil when a run you are inside holds the slot), hourly limit, daily limit.
function M:Summary(now)
	now = now or self:Now()
	local hourList = self:CountedRuns(HOUR, now)
	local dayList = self:CountedRuns(DAY, now)
	local hourLimit = max(1, floor(tonumber(self.db.hourlyLimit) or 5))
	local dayLimit = max(0, floor(tonumber(self.db.dailyLimit) or 0))
	local wait = WaitFor(hourList, hourLimit, HOUR, now)
	if dayLimit > 0 and wait ~= nil then
		local dayWait = WaitFor(dayList, dayLimit, DAY, now)
		wait = dayWait and max(wait, dayWait) or nil
	end
	return #hourList, #dayList, wait, hourLimit, dayLimit, hourList
end

---------------------------------------------------------------------------
-- Text helpers
---------------------------------------------------------------------------
local DURATION = {
	long = E:TranslateValues({ E.Key("%d hours"), E.Key("%d minutes"), E.Key("%d seconds"), E.Key("1 hour"), E.Key("1 minute"), E.Key("1 second") }),
	medium = E:TranslateValues({ E.Key("%d hrs"), E.Key("%d mins"), E.Key("%d secs"), E.Key("1 hr"), E.Key("1 min"), E.Key("1 sec") }),
}

-- 1h 23m, 1 hr 23 mins or 1 hour 23 minutes (the "Duration style" option).
function M:Duration(seconds, style)
	seconds = max(0, floor(tonumber(seconds) or 0))
	style = style or self.db.durationStyle
	local hours, minutes, secs = floor(seconds / 3600), floor(seconds % 3600 / 60), seconds % 60
	if style ~= "long" and style ~= "medium" then
		if hours > 0 then return L["%dh %dm"]:format(hours, minutes) end
		if minutes > 0 then return L["%dm"]:format(minutes) end
		return L["%ds"]:format(secs)
	end
	local words = DURATION[style]
	local function Part(value, plural, single)
		return value == 1 and single or plural:format(value)
	end
	if hours > 0 then
		return minutes > 0 and (Part(hours, words[1], words[4]) .. " " .. Part(minutes, words[2], words[5])) or Part(hours, words[1], words[4])
	end
	if minutes > 0 then return Part(minutes, words[2], words[5]) end
	return Part(secs, words[3], words[6])
end

-- Short countdown for the datatext: 23m, 45s, 1h 2m.
function M:Short(seconds)
	return self:Duration(seconds, "short")
end

local function Use24()
	local clock = M.db and M.db.clock
	if clock == "24" then return true end
	if clock == "12" then return false end
	return E:Clock24()
end

-- A clock time ("14:05" or "2:05 PM"), with the date when it is not today.
function M:Clock(stamp)
	if type(stamp) ~= "number" then return "?" end
	local clock = E:FormatTime(stamp, false, Use24())
	if date("%Y%m%d", stamp) ~= date("%Y%m%d", self:Now()) then
		return E:ShortDay(stamp) .. " " .. clock
	end
	return clock
end

function M:Money(copper)
	return E:FormatMoney(floor(tonumber(copper) or 0))
end

-- Instance name with its difficulty when that is not the normal one.
function M:RunTitle(run)
	local name = run.instance or "?"
	if run.difficultyName and run.difficultyName ~= "" and run.difficulty and run.difficulty > 1 and run.kind ~= "pvp" then
		name = ("%s (%s)"):format(name, run.difficultyName)
	end
	return name
end

function M:ShortName(run)
	local name = run.name or (run.char and run.char:match("^(.-) %- ")) or "?"
	local color = E:ClassColorObject(run.class)
	if color then return color:WrapTextInColorCode(name) end
	return name
end

function M:Notice(text)
	E:Print(AccentHex() .. L["Instances"] .. "|r: " .. text)
end

-- The count line: "3/5 this hour (estimate) · 7 in 24 h · next in 23m".
function M:CountLine(now)
	local hour, day, wait, hourLimit, dayLimit = self:Summary(now)
	local color = hour >= hourLimit and RED or (hour >= hourLimit - 1 and YELLOW or GREEN)
	local parts = { (L["%s%d/%d|r this hour (estimate)"]):format(color, hour, hourLimit) }
	if dayLimit > 0 then
		parts[#parts + 1] = (L["%d/%d in 24 h"]):format(day, dayLimit)
	else
		parts[#parts + 1] = (L["%d in 24 h"]):format(day)
	end
	if wait == nil then
		parts[#parts + 1] = L["next slot after you leave"]
	elseif wait > 0 then
		parts[#parts + 1] = (L["next slot in %s"]):format(self:Duration(wait))
	end
	return table.concat(parts, " · ")
end

---------------------------------------------------------------------------
-- Free-slot notice: one timer to the exact moment the count drops below
-- the limit (no polling).
---------------------------------------------------------------------------
function M:ScheduleFree()
	if self.freeTimer then
		self.freeTimer:Cancel()
		self.freeTimer = nil
	end
	if not self.active then return end
	local _, _, wait = self:Summary()
	if not wait or wait <= 0 then return end
	self.freeTimer = C_Timer.NewTimer(wait + 0.5, function()
		self.freeTimer = nil
		if not self.active then return end
		local hour, _, left, hourLimit = self:Summary()
		if left == 0 then
			if self.db.noticeFree then
				self:Notice((L["A slot is free again: %d/%d this hour (estimate)."]):format(hour, hourLimit))
				if self.db.freeSound and self.db.freeSound ~= "none" then E:PlayMedia(self.db.freeSound) end
			end
			self:Changed("count")
		end
		self:ScheduleFree()
	end)
end

---------------------------------------------------------------------------
-- Runs: start, close, resume, delete, merge
---------------------------------------------------------------------------
local function PlayerXP()
	local level = Plain(UnitLevel("player"))
	local xp, xpMax = Plain(UnitXP("player")), Plain(UnitXPMax("player"))
	return type(level) == "number" and level or nil, type(xp) == "number" and xp or nil, type(xpMax) == "number" and xpMax or nil
end
M.PlayerXP = PlayerXP

-- At the level cap XP stops: no XP kills to count.
function M.AtMaxLevel(level, xpMax)
	local cap = Plain(Try(GetMaxPlayerLevel))
	if type(cap) == "number" and type(level) == "number" and level >= cap then return true end
	return xpMax == 0
end

local function Money()
	local money = Plain(GetMoney())
	return type(money) == "number" and money or nil
end

-- The instance you stand in: { instance, instanceID, kind, difficulty,
-- difficultyName, maxPlayers }, or nil outside (or when it is secret).
function M:Here()
	local inside, kind = IsInInstance()
	if IsSecret(inside) or IsSecret(kind) or not inside then return nil end
	if kind == "arena" then kind = "pvp" end
	if kind ~= "party" and kind ~= "raid" and kind ~= "pvp" then return nil end
	local name, _, difficulty, difficultyName, maxPlayers, _, _, instanceID = GetInstanceInfo()
	name, difficulty, difficultyName, instanceID = Plain(name), Plain(difficulty), Plain(difficultyName), Plain(instanceID)
	if type(name) ~= "string" or name == "" then return nil end
	return {
		instance = name, instanceID = type(instanceID) == "number" and instanceID or 0, kind = kind,
		difficulty = type(difficulty) == "number" and difficulty or 0,
		difficultyName = type(difficultyName) == "string" and difficultyName or "",
		maxPlayers = type(Plain(maxPlayers)) == "number" and maxPlayers or nil,
	}
end

local function SameInstance(run, here)
	if not (run and here) then return false end
	if run.instanceID and run.instanceID ~= 0 and here.instanceID ~= 0 then
		return run.instanceID == here.instanceID and (run.difficulty or 0) == (here.difficulty or 0)
	end
	return run.instance == here.instance
end
M.SameInstance = SameInstance

function M:NewRun(here, how)
	local store = self:Store()
	local level, xp, xpMax = PlayerXP()
	local _, class = UnitClass("player")
	local run = {
		id = store.nextID,
		char = self:CharKey(), name = E:PlayerName(), class = Plain(class), realm = self:RealmKey(),
		instance = here.instance, instanceID = here.instanceID, kind = here.kind,
		difficulty = here.difficulty, difficultyName = here.difficultyName, maxPlayers = here.maxPlayers,
		enter = self:Now(), enterLevel = level, enterXP = xp, enterXPMax = xpMax, enterMoney = Money(),
		maxLevel = M.AtMaxLevel(level, xpMax) or nil,
		xp = 0, kills = 0, money = 0,
		how = how, -- "login" when you logged in inside
	}
	store.nextID = store.nextID + 1
	table.insert(store.runs, 1, run)
	self:Trim()
	return run
end

-- Stamp the leave fields.
function M:StampLeave(run)
	local level, xp, xpMax = PlayerXP()
	run.leave = self:Now()
	run.leaveLevel, run.leaveXP, run.leaveXPMax = level, xp, xpMax
	run.leaveMoney = Money()
end

function M:SetCurrent(run)
	self.current = run
	if self.OnCurrentChanged then self:OnCurrentChanged(run) end
	self:WatchZoneUID()
end

function M:Resume(run, why)
	run.leave, run.leaveLevel, run.leaveXP, run.leaveXPMax, run.leaveMoney = nil, nil, nil, nil, nil
	run.logout, run.ghostOut = nil, nil
	self:SetCurrent(run)
	self:Changed("runs")
	self:ScheduleFree()
end

-- how: "left" (a normal exit: summary), "ghost" (released and sent to the
-- graveyard: you will be back), "switch" (straight into another instance),
-- "logout".
function M:CloseRun(run, how)
	if not run or run.leave then return end
	self:StampLeave(run)
	if how == "ghost" then run.ghostOut = true end
	if how == "logout" then run.logout = true end
	if self.current == run then self:SetCurrent(nil) end
	if (how == "left" or how == "switch") and self.OnRunLeft and self.active then self:OnRunLeft(run) end
	FireCallback("RunClosed", run, how)
	self:Changed("runs")
	self:ScheduleFree()
end

function M:StartRun(here, how)
	local run = self:NewRun(here, how)
	self:SetCurrent(run)
	if self.OnRunStarted then self:OnRunStarted(run) end
	self:EnteredNotice(run)
	self:RequestLockouts()
	self:Changed("runs")
	self:ScheduleFree()
	return run
end

function M:DeleteRun(id)
	local run, index = self:FindRun(id)
	if not run then return false end
	table.remove(self:Runs(), index)
	if self.current == run then self:SetCurrent(nil) end
	self:Changed("runs")
	self:ScheduleFree()
	return true
end

local function AddTable(into, from)
	for key, value in pairs(from or {}) do
		if type(value) == "number" then
			into[key] = (into[key] or 0) + value
		elseif type(value) == "table" then
			into[key] = into[key] or {}
			for k, v in pairs(value) do
				if type(v) == "number" and k == "count" then
					into[key].count = (into[key].count or 0) + v
				elseif into[key][k] == nil then
					into[key][k] = v
				end
			end
		end
	end
end

-- Fold `newer` into `older` (the same instance entered twice) and drop it.
function M:Merge(newer, older)
	if not (newer and older) or newer == older then return false end
	for _, key in ipairs({ "xp", "kills", "money", "honor", "hk" }) do
		if newer[key] or older[key] then older[key] = (older[key] or 0) + (newer[key] or 0) end
	end
	older.rep = older.rep or {}
	AddTable(older.rep, newer.rep)
	older.currency = older.currency or {}
	AddTable(older.currency, newer.currency)
	if newer.group then
		older.group = older.group or {}
		for name, info in pairs(newer.group) do
			if not older.group[name] then older.group[name] = info end
		end
	end
	if (newer.groupSize or 0) > (older.groupSize or 0) then
		older.groupSize, older.groupLevelSum, older.groupLevelCount = newer.groupSize, newer.groupLevelSum, newer.groupLevelCount
	end
	older.merged = (older.merged or 0) + 1 + (newer.merged or 0)
	older.zoneUID = older.zoneUID or newer.zoneUID
	older.leave, older.leaveLevel, older.leaveXP, older.leaveXPMax, older.leaveMoney =
		newer.leave, newer.leaveLevel, newer.leaveXP, newer.leaveXPMax, newer.leaveMoney
	older.logout, older.ghostOut = newer.logout, newer.ghostOut
	local _, index = self:FindRun(newer.id)
	if index then table.remove(self:Runs(), index) end
	if self.current == newer then self:SetCurrent(older) end
	self:Changed("runs")
	self:ScheduleFree()
	return true
end

-- Can `run` be merged into the entry before it by hand ("Same run as
-- last")? Same character and instance, entered within an hour of leaving
-- the earlier one, and no reset seen in between.
function M:ManualMergeTarget(run)
	if not run or run.kind == "pvp" then return nil end
	local previous = self:PreviousRun(run)
	if not previous or not SameInstance(previous, run) then return nil end
	local gap = (run.enter or 0) - (previous.leave or previous.enter or 0)
	if gap < 0 or gap > MANUAL_MERGE then return nil end
	local reset = self:Store().lastResetAt
	if reset and previous.leave and reset >= previous.leave and reset <= (run.enter or 0) then return nil end
	return previous
end

function M:ManualMerge(id)
	local run = self:FindRun(id)
	local target = self:ManualMergeTarget(run)
	if not target then
		self:Notice(L["This run can't be merged: the entry before it is another instance, more than an hour older, or the instances were reset in between."])
		return false
	end
	self:Merge(run, target)
	self:Notice((L["%s: merged with the run before (same run)."]):format(self:RunTitle(target)))
	return true
end

---------------------------------------------------------------------------
-- Same-run detection: the zone UID in creature and cast GUIDs
-- ("Creature-0-<server>-<instance>-<zoneUID>-<npc>-<spawn>",
-- "Cast-<kind>-<server>-<instance>-<zoneUID>-<spell>-<cast>").
---------------------------------------------------------------------------
local NPC_TYPES = { Creature = true, Vehicle = true }

function M.ZoneUIDFromGUID(guid, types)
	if type(guid) ~= "string" or IsSecret(guid) then return nil end
	local kind, _, _, _, zoneUID = strsplit("-", guid)
	if not (kind and (types or NPC_TYPES)[kind]) then return nil end
	if type(zoneUID) ~= "string" or zoneUID == "" or zoneUID == "0" then return nil end
	return zoneUID
end

local function UnitZoneUID(unit)
	if InCombatLockdown() then return nil end
	if not Plain(UnitExists(unit)) then return nil end
	local player, controlled = UnitIsPlayer(unit), UnitPlayerControlled(unit)
	if IsSecret(player) or IsSecret(controlled) or player or controlled then return nil end
	return M.ZoneUIDFromGUID(UnitGUID(unit))
end

local CAST_TYPES = { Cast = true }

function M:SeeZoneUID(zoneUID)
	local run = self.current
	if not run or run.zoneUID or not zoneUID or run.kind == "pvp" then return end
	run.zoneUID = zoneUID
	self:WatchZoneUID()
	if not self.db.detectSameRun then return end
	local previous = self:PreviousRun(run)
	if previous and previous.zoneUID == zoneUID and SameInstance(previous, run) then
		self:Merge(run, previous)
		if self.db.noticeMerge then
			self:Notice((L["%s: same run as before, merged (%s)."]):format(self:RunTitle(previous), self:CountLine()))
		end
	end
end

local ZONE_EVENTS = { "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "NAME_PLATE_UNIT_ADDED", "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_SUCCEEDED" }

local function OnZoneEvent(event, unit, castGUID)
	if event == "PLAYER_TARGET_CHANGED" then
		M:SeeZoneUID(UnitZoneUID("target"))
	elseif event == "UPDATE_MOUSEOVER_UNIT" then
		M:SeeZoneUID(UnitZoneUID("mouseover"))
	elseif event == "NAME_PLATE_UNIT_ADDED" then
		if type(unit) == "string" and not IsSecret(unit) then M:SeeZoneUID(UnitZoneUID(unit)) end
	elseif unit == "player" and not InCombatLockdown() then
		M:SeeZoneUID(M.ZoneUIDFromGUID(castGUID, CAST_TYPES))
	end
end

-- The GUID listeners run only while a run inside still needs its zone UID.
function M:WatchZoneUID()
	local run = self.current
	local want = (self.active or self.recorderOn) and run and not run.zoneUID and run.kind ~= "pvp"
	if want and not self.watchingZone then
		self.watchingZone = true
		for _, event in ipairs(ZONE_EVENTS) do self:Listen(event, "zoneuid", OnZoneEvent) end
	elseif not want and self.watchingZone then
		self.watchingZone = nil
		for _, event in ipairs(ZONE_EVENTS) do self:StopListening(event, "zoneuid") end
	end
end

---------------------------------------------------------------------------
-- Entering and leaving
---------------------------------------------------------------------------
-- Was the player a ghost on this loading screen (released, or just
-- resurrected at the instance door)?
function M:GhostZoning()
	local now = GetTime()
	if self.ghostUntil and now <= self.ghostUntil then return true end
	local ghost = UnitIsGhost("player")
	return not IsSecret(ghost) and ghost == true
end

function M:OnEnteringWorld(isLogin, isReload)
	local here = self:Here()
	local open = self:OpenRun()
	local ghost = self:GhostZoning()
	self.ghostUntil = nil
	local now = self:Now()
	if here then
		-- Still in the run you were in (a reload, or a loading screen inside).
		if open and SameInstance(open, here) then
			self:SetCurrent(open)
			self:Changed("runs")
			return
		end
		if open then self:CloseRun(open, "switch") end
		local last = self:LastRun()
		if last and SameInstance(last, here) and last.leave then
			-- A reload brings back the run the logout closed.
			if isReload and last.logout and now - last.leave <= RELOAD_RETURN then
				return self:Resume(last, "reload")
			end
			-- Back after dying: a ghost (or freshly resurrected) entry, or the
			-- run you left as a ghost.
			if (ghost or last.ghostOut) and now - last.leave <= GHOST_RETURN then
				return self:Resume(last, "ghost")
			end
		end
		-- A ghost entry with nothing to come back to is not a new run.
		if ghost then return end
		self:StartRun(here, isLogin and "login" or nil)
	elseif open then
		self:CloseRun(open, ghost and "ghost" or "left")
	end
end

function M:EnteredNotice(run)
	if not self.active then return end
	local db = self.db
	local wanted = (run.kind == "party" and db.noticeEnter) or (run.kind == "raid" and db.noticeRaid) or (run.kind == "pvp" and db.noticePvP)
	if not wanted then return end
	local links = {}
	links[#links + 1] = E:ChatLink("instances", "log", L["Run log"])
	if self:ManualMergeTarget(run) then
		links[#links + 1] = E:ChatLink("instances", "merge:" .. run.id, L["Same run as last"])
	end
	links[#links + 1] = E:ChatLink("instances", "delete:" .. run.id, L["Not a run"], { 0.6, 0.6, 0.65 })
	local text
	if run.kind == "pvp" then
		text = (L["Entered %s (battlegrounds never count toward the limit)."]):format(self:RunTitle(run))
	elseif not self:Counts(run) then
		text = (L["Entered %s (raids don't count toward the hourly limit)."]):format(self:RunTitle(run))
	elseif run.how == "login" then
		text = (L["Logged in inside %s: %s."]):format(self:RunTitle(run), self:CountLine())
	else
		text = (L["Entered %s: %s."]):format(self:RunTitle(run), self:CountLine())
	end
	self:Notice(text .. " " .. table.concat(links, " "))
end

---------------------------------------------------------------------------
-- "Too many instances": the server refused an entry.
---------------------------------------------------------------------------
function M:TooMany()
	local now = GetTime()
	if self.tooManyAt and now - self.tooManyAt < 10 then return end
	self.tooManyAt = now
	local hour, _, wait, hourLimit = self:Summary()
	local text = (L["The server says you entered too many instances: %s."]):format(self:CountLine())
	if hour < hourLimit and hour > 0 then
		text = text .. " " .. (L["It refused at %d entries."]):format(hour) .. " "
			.. E:ChatLink("instances", "limit:" .. hour, (L["Use %d as the limit"]):format(hour))
	elseif wait and wait > 0 then
		text = text .. " " .. (L["Try again in %s."]):format(self:Duration(wait))
	end
	self:Notice(text)
end

local function OnSystemText(event, a, b)
	local text = event == "UI_ERROR_MESSAGE" and b or a
	if E.ChatParse:Parse("tooManyInstances", text) then M:TooMany() end
end

---------------------------------------------------------------------------
-- Raid lockouts (GetSavedInstanceInfo), per character.
---------------------------------------------------------------------------
function M:RequestLockouts()
	local now = GetTime()
	if self.lockoutAsked and now - self.lockoutAsked < 10 then return end
	self.lockoutAsked = now
	Try(RequestRaidInfo)
end

function M:ReadLockouts()
	local count = Plain(Try(GetNumSavedInstances))
	if type(count) ~= "number" then return end
	local now = self:Now()
	local list = {}
	for index = 1, count do
		local name, _, reset, difficulty, locked, extended, _, isRaid, maxPlayers, difficultyName, encounters, progress = Try(GetSavedInstanceInfo, index)
		name, reset, locked, extended = Plain(name), Plain(reset), Plain(locked), Plain(extended)
		if type(name) == "string" and type(reset) == "number" and reset > 0 and (locked or extended) then
			list[#list + 1] = {
				name = name, resetAt = now + reset, isRaid = Plain(isRaid) and true or false,
				difficultyName = type(Plain(difficultyName)) == "string" and difficultyName or nil,
				maxPlayers = type(Plain(maxPlayers)) == "number" and maxPlayers or nil,
				total = type(Plain(encounters)) == "number" and encounters or nil,
				progress = type(Plain(progress)) == "number" and progress or nil,
				difficulty = type(Plain(difficulty)) == "number" and difficulty or nil,
			}
		end
	end
	local record = self:CharRecord()
	local _, class = UnitClass("player")
	record.class = Plain(class) or record.class
	record.realm = self:RealmKey()
	record.lockouts = list
	record.lockoutsAt = now
	self:Changed("lockouts")
end

-- Lockouts not yet expired: { { char, class, name, resetAt, ... } } for
-- this ruleset, current character first. With T5's character store
-- (Core/CharacterStore.lua) a character it knows but this module never
-- saw is not listed: only lockouts read here are shown.
function M:Lockouts()
	local now = self:Now()
	local mine, realm = self:CharKey(), self:RealmKey()
	local list = {}
	for key, record in pairs(self:Store().chars) do
		if type(record) == "table" and type(record.lockouts) == "table" and (record.realm == nil or record.realm == realm) then
			for _, lock in ipairs(record.lockouts) do
				if (lock.resetAt or 0) > now then
					list[#list + 1] = { char = key, class = record.class, mine = key == mine, lock = lock }
				end
			end
		end
	end
	table.sort(list, function(a, b)
		if a.mine ~= b.mine then return a.mine end
		if a.char ~= b.char then return a.char < b.char end
		return a.lock.name < b.lock.name
	end)
	return list
end

---------------------------------------------------------------------------
-- Datatext
---------------------------------------------------------------------------
function M:DataText()
	if not self.active then return GREY .. L["Instances"] .. "|r" end
	local hour, _, wait, hourLimit = self:Summary()
	if wait == 0 then
		local color = hour >= hourLimit - 1 and YELLOW or GREEN
		return ("%s%s|r %d/%d"):format(color, L["Ready"], hour, hourLimit)
	end
	if wait == nil then return ("%s%d/%d|r"):format(RED, hour, hourLimit) end
	return ("%s%d/%d|r · %s"):format(RED, hour, hourLimit, self:Short(wait))
end

function M:FillTooltip(tooltip)
	tooltip:AddLine(L["Instances"])
	if not self.active then
		E.UIKit.TipText(tooltip, E:ModuleOffNote("Instances"))
		return
	end
	local now = self:Now()
	local run = self.current
	if run then
		tooltip:AddLine(" ")
		tooltip:AddDoubleLine(AccentHex() .. self:RunTitle(run) .. "|r", self:Duration(now - (run.enter or now)), 1, 1, 1, 1, 1, 1)
		if self.AddRunStats then self:AddRunStats(tooltip, run, true) end
	end
	local hour, day, wait, hourLimit, dayLimit, hourList = self:Summary(now)
	tooltip:AddLine(" ")
	E.UIKit.TipPair(tooltip, L["This hour (estimate)"], ("%d/%d"):format(hour, hourLimit))
	E.UIKit.TipPair(tooltip, L["Last 24 hours"], dayLimit > 0 and ("%d/%d"):format(day, dayLimit) or tostring(day))
	local nextText
	if wait == 0 then
		nextText = GREEN .. L["Now"] .. "|r"
	elseif wait == nil then
		nextText = YELLOW .. L["After you leave"] .. "|r"
	else
		nextText = RED .. self:Duration(wait) .. "|r"
	end
	E.UIKit.TipPair(tooltip, L["Next instance"], nextText)
	if #hourList > 0 then
		tooltip:AddLine(" ")
		E.UIKit.TipText(tooltip, L["Counting this hour"])
		for index = #hourList, 1, -1 do
			local entry = hourList[index]
			local left = entry.leave and (L["%s left"]):format(self:Short(entry.leave + HOUR - now)) or L["inside"]
			tooltip:AddDoubleLine(("%s  %s"):format(self:RunTitle(entry), self:ShortName(entry)), left, 1, 1, 1, 0.8, 0.8, 0.85)
		end
	end
	local locks = self:Lockouts()
	if #locks > 0 then
		tooltip:AddLine(" ")
		E.UIKit.TipText(tooltip, L["Raid lockouts"])
		for index, entry in ipairs(locks) do
			if index > 8 then
				tooltip:AddLine(GREY .. (L["...and %d more"]):format(#locks - 8) .. "|r")
				break
			end
			local lock = entry.lock
			local name = entry.char:match("^(.-) %- ") or entry.char
			local color = E:ClassColorObject(entry.class)
			if color then name = color:WrapTextInColorCode(name) end
			local progress = (lock.total and lock.total > 0 and lock.progress) and (" " .. GREY .. ("%d/%d"):format(lock.progress, lock.total) .. "|r") or ""
			tooltip:AddDoubleLine(("%s  %s%s"):format(lock.name, name, progress), self:Short(lock.resetAt - now), 1, 1, 1, 0.8, 0.8, 0.85)
		end
	end
	tooltip:AddLine(" ")
	E:TooltipHint(tooltip, { L["Click"], L["run log"] }, { L["Right-click"], L["menu"] })
end

function M:DataMenu(owner)
	E.UIKit.ContextMenu(owner, function(_, root)
		root:CreateTitle(L["Instances"])
		root:CreateButton(L["Run log"], function() M:OpenLog() end)
		root:CreateButton(L["Print the count"], function() M:PrintCount() end)
		if self.current and self:ManualMergeTarget(self.current) then
			root:CreateButton(L["Same run as last"], function() M:ManualMerge(self.current.id) end)
		end
		if self.FillDataMenu then self:FillDataMenu(root) end
	end)
end

E:RegisterDataText("Instances", {
	title = "Instances",
	events = { "PLAYER_ENTERING_WORLD", "UPDATE_INSTANCE_INFO" },
	poll = true,
	interval = 15,
	text = function() return M:DataText() end,
	tooltip = function(tooltip) M:FillTooltip(tooltip) end,
	onClick = function(button, mouseButton)
		if mouseButton == "RightButton" then
			M:DataMenu(button)
		else
			M:OpenLog()
		end
	end,
})

---------------------------------------------------------------------------
-- Chat links in EldoUI's own lines: log, merge:<id>, delete:<id>, limit:<n>
---------------------------------------------------------------------------
function M:AskDelete(id)
	local run = self:FindRun(id)
	if not run then return end
	E:ShowConfirm({ key = "ELDOUI_INSTANCES_DELETE", title = L["Instances"],
		text = L["Remove this run from the log (%s)? It no longer counts toward the limit."]:format(self:RunTitle(run)),
		accept = YES or L["Yes"], cancel = NO or L["No"], danger = true, data = run.id,
		onAccept = function(runID) M:DeleteRun(runID) end })
end

function M:SetLimit(value)
	value = floor(tonumber(value) or 0)
	if value < 1 or value > 10 then return end
	self.db.hourlyLimit = value
	self:Notice((L["Hourly limit set to %d."]):format(value))
	self:Changed("count")
	self:ScheduleFree()
end

E:RegisterChatLink("instances", function(data)
	if not M.active then return end
	local action, arg = tostring(data or ""):match("^(%a+):?(.*)$")
	if action == "log" then
		M:OpenLog()
	elseif action == "merge" then
		M:ManualMerge(arg)
	elseif action == "delete" then
		M:AskDelete(arg)
	elseif action == "limit" then
		M:SetLimit(arg)
	elseif M.OnChatLink then
		M:OnChatLink(action, arg)
	end
end)

---------------------------------------------------------------------------
-- Commands
---------------------------------------------------------------------------
function M:PrintCount()
	self:Notice(self:CountLine())
end

-- Opens the run log (Log.lua), or says why it can't.
function M:OpenLog(tab)
	if not self.active then
		E:Print(L["Turn on the Instances module first (Group > Instances)."])
		return
	end
	if self.ShowLog then self:ShowLog(tab) end
end

function M:ForceRun()
	local here = self:Here()
	if not here then
		self:Notice(L["You are not inside an instance."])
		return
	end
	local open = self:OpenRun()
	if open then self:CloseRun(open, "switch") end
	self:StartRun(here, "manual")
end

local function Command(arg)
	local word, rest = (arg or ""):match("^(%S*)%s*(.-)%s*$")
	word = (word or ""):lower()
	if word == "on" or word == "off" then
		E:SetModuleFromCommand("Instances", word == "on")
		return
	elseif word == "options" or word == "config" or word == "settings" then
		E:ToggleConfig("module:Instances")
		return
	end
	if not M.active then
		E:Print(E:ModuleOffHint("Instances"))
		return
	end
	if word == "add" or word == "new" then
		M:ForceRun()
	elseif word == "count" then
		M:PrintCount()
	elseif word == "stats" then
		if M.StatsCommand then M:StatsCommand(rest) end
	elseif word == "pvp" then
		M:OpenLog("pvp")
	else
		M:OpenLog()
	end
end

E:AddCommand("instances", "[log | add | count | stats | pvp | options | on | off]  run log and hourly instance count", Command, "Tools")

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------
local function OnEnteringWorld(_, isLogin, isReload)
	M:OnEnteringWorld(isLogin == true, isReload == true)
	M:RequestLockouts()
end

local function OnLeavingWorld()
	local ghost = UnitIsGhost("player")
	if not IsSecret(ghost) and ghost then M.ghostUntil = GetTime() + GHOST_LEAVE_WINDOW end
end

local function OnUnghost()
	M.ghostUntil = GetTime() + UNGHOST_WINDOW
end

local function OnLogout()
	local open = M:OpenRun()
	if open then M:CloseRun(open, "logout") end
end

M:Listen("PLAYER_ENTERING_WORLD", "zone", OnEnteringWorld)
M:Listen("PLAYER_LEAVING_WORLD", "zone", OnLeavingWorld)
M:Listen("PLAYER_UNGHOST", "zone", OnUnghost)
M:Listen("PLAYER_LOGOUT", "zone", OnLogout)
M:Listen("UPDATE_INSTANCE_INFO", "lockouts", function() M:ReadLockouts() end)

-- Bosses killed in the open run: ENCOUNTER_END (success) or BOSS_KILL, one
-- count per encounter (the two events of one kill count once).
local function OnBoss(event, encounterID, _, _, _, success)
	local run = M.current
	if not run or run.kind == "pvp" then return end
	if event == "ENCOUNTER_END" and (IsSecret(success) or not (success == 1 or success == true)) then return end
	encounterID = Plain(encounterID)
	if type(encounterID) ~= "number" then return end
	M.bossSeen = M.bossSeen and M.bossSeen.run == run and M.bossSeen or { run = run, ids = {} }
	if M.bossSeen.ids[encounterID] then return end
	M.bossSeen.ids[encounterID] = true
	run.bosses = (run.bosses or 0) + 1
	M:Changed("runs")
end
M:Listen("ENCOUNTER_END", "bosses", OnBoss)
M:Listen("BOSS_KILL", "bosses", OnBoss)
M:Listen("CHAT_MSG_SYSTEM", "toomany", OnSystemText)
M:Listen("SYSMSG", "toomany", OnSystemText)
M:Listen("UI_ERROR_MESSAGE", "toomany", OnSystemText)

function M:OnInitialize()
	self:Store()
end

function M:OnEnable()
	-- The module takes over from the recorder.
	if self.recorderOn then
		self.recorderOn = nil
		recorderFrame:UnregisterAllEvents()
	end
	self:Store()
	for event in pairs(eventHandlers) do self:RegisterEvent(event, Dispatch) end
	-- Turned on (or a login): pick up where the player stands now.
	if IsLoggedIn and IsLoggedIn() then
		local open = self:OpenRun()
		local here = self:Here()
		if open and here and SameInstance(open, here) then
			self:SetCurrent(open)
		elseif open and not here then
			self:CloseRun(open, "left")
		end
		self:RequestLockouts()
	end
	if self.OnEnableParts then self:OnEnableParts() end
	self:ScheduleFree()
	self:Changed("runs")
end

function M:OnDisable()
	for event in pairs(eventHandlers) do self:UnregisterEvent(event) end
	self.current = nil
	self:WatchZoneUID()
	if self.freeTimer then
		self.freeTimer:Cancel()
		self.freeTimer = nil
	end
	if self.OnDisableParts then self:OnDisableParts() end
	-- Another module still wants runs: the recorder goes on.
	SyncRecorder()
	self:Changed("runs")
end

function M:OnProfileChanged()
	if not self.active then return end
	self:Trim()
	self:ScheduleFree()
	if self.ApplyLook then self:ApplyLook() end
	self:Changed("settings")
end
