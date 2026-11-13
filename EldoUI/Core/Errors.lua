-- EldoUI error catcher: records Lua errors, warnings and blocked actions
-- into a small capped log instead of showing them. Nothing is printed to
-- chat; the error log window shows it (Core\ErrorWindow.lua, /eui errors),
-- and so does the Chat module's "Errors and help" tab.
--
-- Limits, so the log can never grow in memory:
--   * one entry holds at most MAX_TEXT characters (message + stack)
--   * the same error is counted, not stored again
--   * at most MAX_ENTRIES entries; the oldest seen goes first
--   * at most RATE_LIMIT entries per second, repeats included; the rest
--     only raise the dropped count
--
-- Each entry also keeps a little context for bug reports (EldoUI version,
-- zone, combat, the local variables where it broke), and each session
-- stores the game build, locale, class and the enabled modules. The
-- Report button in the error log turns an entry into a bug report the
-- player can copy; no character names are stored. Text values among the local
-- variables (they can hold names or chat lines) are saved only as their
-- length; numbers, booleans, frame names and EVENT_NAMES stay readable.
--
-- Loaded straight after Core\Init.lua so it also catches errors from the
-- rest of EldoUI while it loads. Saved in EldoUIErrorsDB.
local addonName, E = ...

local MAX_TEXT = 2000
local MAX_ENTRIES = 100
local RATE_LIMIT = 10
local MAX_LOCALS = 600
local MAX_CONTEXTS = 10

local Errors = {
	entries = {},  -- list of { kind, message, stack, addon, count, first, last, session }
	byKey = {},
	unseen = 0,    -- new errors since the log was last opened
	dropped = 0,   -- errors skipped by the rate limit this session
	session = 0,
	listeners = {},
}
E.errors = Errors

local function Truncate(text, size)
	if #text > size then return text:sub(1, size - 3) .. "..." end
	return text
end

local function Safe(value)
	if issecretvalue and issecretvalue(value) then return "(secret value)" end
	return tostring(value)
end

-- debuglocals output with every quoted string replaced by its length, so
-- names and chat text never reach the saved log. Upper-case
-- identifiers with an underscore (event and constant names) stay.
local function ScrubLocals(text)
	return (text:gsub('"([^"\n]*)"', function(value)
		if value:find("^[A-Z][A-Z0-9]*_[A-Z0-9_]+$") then return '"' .. value .. '"' end
		return ("<text, %d chars>"):format(#value)
	end))
end
Errors.ScrubLocals = ScrubLocals

-- A Lua file name or chunk name ("@Interface/AddOns/...lua", "=[C]",
-- "Interface\AddOns\...lua"): code, never personal, and needed to find
-- where an error comes from.
local function IsCodePath(value)
	if value == "=[C]" then return true end
	return value:find("^@?[%w_%-%./\\]+%.lua$") ~= nil
end

-- An error message or stack with quoted text (chat lines, names) replaced
-- by its length, like ScrubLocals, but file and chunk names stay.
local function ScrubQuoted(text)
	return (text:gsub('"([^"\n]*)"', function(value)
		if IsCodePath(value) or value:find("^[A-Z][A-Z0-9]*_[A-Z0-9_]+$") then return '"' .. value .. '"' end
		return ("<text, %d chars>"):format(#value)
	end))
end
Errors.ScrubQuoted = ScrubQuoted

-- The key that groups an error: kind and message, without memory
-- addresses ("table: 0x1f2e..."), which change on every repeat.
local function KeyOf(kind, message)
	local text = message:sub(1, 300):gsub("0[xX]%x+", "#"):gsub("%x%x%x%x%x%x%x%x+", "#")
	return kind .. "\0" .. text
end
Errors.KeyOf = KeyOf

local function EntryKey(entry)
	return KeyOf(entry.kind, entry.message)
end

-- Drops the entry seen longest ago (and its key) until the log fits.
local function Trim(self)
	while #self.entries > MAX_ENTRIES do
		local oldest = 1
		for index, other in ipairs(self.entries) do
			if (other.last or 0) < (self.entries[oldest].last or 0) then oldest = index end
		end
		local removed = table.remove(self.entries, oldest)
		if self.byKey[EntryKey(removed)] == removed then self.byKey[EntryKey(removed)] = nil end
	end
end
Errors.Trim, Errors.maxEntries = Trim, MAX_ENTRIES

-- First AddOns folder named in the text, so the log can show who it was.
local function FindAddon(text)
	return text:match("[Ii]nterface[\\/][Aa]dd[Oo]ns[\\/]([^\\/:]+)") or text:match("^%[string \"@?[Ii]nterface[\\/][Aa]dd[Oo]ns[\\/]([^\\/]+)")
end

function Errors:Notify()
	for _, fn in pairs(self.listeners) do pcall(fn) end
end

-- A new or repeated entry tells the listeners (the log window, the chat
-- Errors button) at most once per frame, however often it repeats.
local notifyQueued = false
function Errors:NotifySoon()
	if notifyQueued then return end
	if not (C_Timer and C_Timer.After) then return self:Notify() end
	notifyQueued = true
	C_Timer.After(0, function()
		notifyQueued = false
		Errors:Notify()
	end)
end

function Errors:OnChange(owner, fn)
	self.listeners[owner] = fn
end

-- RATE_LIMIT entries a second, repeats included; the rest only raise
-- `dropped`, which the log window shows.
local tokens, tokensAt = RATE_LIMIT, 0
local function TakeToken()
	local clock = GetTime()
	if clock > tokensAt then
		tokens = math.min(RATE_LIMIT, tokens + (clock - tokensAt) * RATE_LIMIT)
		tokensAt = clock
	end
	if tokens < 1 then return false end
	tokens = tokens - 1
	return true
end

-- Where the player was when an error first happened. Every call is guarded;
-- an error report must never raise an error itself.
local function Where()
	local where = {}
	local ok, zone = pcall(GetRealZoneText)
	if ok and zone then where.zone = Safe(zone) end
	local okInstance, _, instanceType = pcall(GetInstanceInfo)
	if okInstance and instanceType then where.instance = Safe(instanceType) end
	local okCombat, combat = pcall(InCombatLockdown)
	where.combat = okCombat and combat == true or false
	return where
end

-- `addon` names the owner when the caller knows it (a blocked action names
-- the addon the game blamed); otherwise the first AddOns path decides.
function Errors:Add(kind, message, stack, count, locals, addon)
	message = Truncate(Safe(message), MAX_TEXT)
	if not TakeToken() then
		self.dropped = self.dropped + (count or 1)
		self:NotifySoon()
		return
	end
	local key = KeyOf(kind, message)
	local now = time()
	local entry = self.byKey[key]
	if entry then
		entry.count = entry.count + (count or 1)
		entry.last = now
		-- Back in a later session (often after an update): the entry takes
		-- this occurrence's stack, locals, version and place, so a report
		-- points at the code that runs now. `first` and the count stay; a
		-- repeat within one session captures nothing new.
		if entry.session ~= self.session then
			entry.session = self.session
			if stack then
				stack = Truncate(Safe(stack), math.max(MAX_TEXT - #message, 0))
				locals = locals and ScrubLocals(Safe(locals)) or ""
				entry.stack = stack
				entry.locals = Truncate(locals, math.min(MAX_LOCALS, math.max(MAX_TEXT - #message - #stack, 0)))
				entry.addon = addon or FindAddon(message) or FindAddon(stack) or entry.addon
			end
			local where = Where()
			entry.version, entry.zone, entry.instance, entry.combat = E.version, where.zone, where.instance, where.combat
		end
	else
		stack = stack and Safe(stack) or ""
		stack = Truncate(stack, math.max(MAX_TEXT - #message, 0))
		locals = locals and ScrubLocals(Safe(locals)) or ""
		locals = Truncate(locals, math.min(MAX_LOCALS, math.max(MAX_TEXT - #message - #stack, 0)))
		local where = Where()
		entry = {
			kind = kind, message = message, stack = stack, locals = locals,
			addon = addon or FindAddon(message) or FindAddon(stack),
			count = count or 1, first = now, last = now, session = self.session,
			version = E.version, zone = where.zone, instance = where.instance, combat = where.combat,
		}
		self.byKey[key] = entry
		table.insert(self.entries, entry)
		Trim(self)
	end
	self.unseen = self.unseen + 1
	self.lastKind = kind
	self:NotifySoon()
end

-- Is this error already logged in this session? Then a repeat needs no
-- new stack or locals: Add only counts it.
function Errors:Known(kind, message)
	local entry = self.byKey[KeyOf(kind, Truncate(Safe(message), MAX_TEXT))]
	return entry ~= nil and entry.session == self.session
end

function Errors:Clear()
	wipe(self.entries)
	wipe(self.byKey)
	self.unseen, self.dropped = 0, 0
	self:Notify()
end

function Errors:MarkSeen()
	if self.unseen == 0 then return end
	self.unseen = 0
	self:Notify()
end

-- One entry as plain text, for the copy box and bug reports.
function Errors:Format(entry)
	local lines = {
		("%s  x%d  %s"):format(date("%Y-%m-%d %H:%M:%S", entry.last), entry.count, entry.addon or "?"),
		entry.message,
	}
	if entry.stack ~= "" then table.insert(lines, entry.stack) end
	return table.concat(lines, "\n")
end

-- The session context saved for an entry, if it is still kept.
function Errors:Context(entry)
	local db = EldoUIErrorsDB
	return db and type(db.contexts) == "table" and db.contexts[entry.session] or nil
end

-- Where players report a bug: the repository's issue forms. Fork
-- (WoW-UI-Addon): this fork's, since a bug may come from its own changes;
-- one that is EldoUI's own goes on to github.com/Eldodeldo/EldoUI from there.
Errors.REPORT_URL = "https://github.com/con1338/WoW-UI-Addon/issues/new?template=bug_report.yml"

-- A short, stable name of an error: the same error from the same version
-- gets the same signature on every PC, so repeated reports can be grouped.
-- Memory addresses ("table: 0x1f2e...") are left out, they change on
-- every run.
function Errors:Signature(entry)
	local text = (entry.kind or "error") .. "\0" .. ((entry.message or ""):match("^[^\n]*") or "")
	text = text:gsub("0x%x+", ""):gsub("%x%x%x%x%x%x%x%x+", "")
	local hash = 5381
	for index = 1, #text do
		hash = (hash * 33 + text:byte(index)) % 4294967296
	end
	return ("%08x"):format(hash)
end

local GUID_KINDS = { "Player", "Creature", "Pet", "GameObject", "Vehicle", "Vignette", "Item", "BattlePet", "Cast", "Corpse" }

-- Word characters: Latin letters and digits, and every byte of a UTF-8
-- letter (accented, Cyrillic, Hangul, Han), so "Élodie" or "Андрей" count
-- as whole words too.
local WORD = "%w\128-\255"

-- Every place the word stands alone (not inside a longer word).
local function ReplaceWord(text, word, by)
	if type(word) ~= "string" or (issecretvalue and issecretvalue(word)) or word == "" then return text end
	local pattern = "%f[" .. WORD .. "]" .. word:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0") .. "%f[^" .. WORD .. "]"
	return (text:gsub(pattern, by))
end

-- A report text with nothing personal left in it: the character's name,
-- realm and guild become placeholders, GUIDs are cut out and quoted text
-- (chat lines, names in variables) is replaced by its length, like the
-- saved variables of an error. Color codes go too.
function Errors:ScrubReport(text)
	text = Safe(text or "")
	text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	for _, kind in ipairs(GUID_KINDS) do
		text = text:gsub("%f[%w]" .. kind .. "%-[%x%-]+%x", "<guid>")
	end
	local okName, name, realm = pcall(UnitName, "player")
	if okName then
		-- The name as shown (with a surname on some builds) first, then the
		-- base name EldoUI keys characters by.
		text = ReplaceWord(text, name, "<character>")
		text = ReplaceWord(text, realm, "<realm>")
	end
	local okBase, base = pcall(E.PlayerName, E)
	if okBase then text = ReplaceWord(text, base, "<character>") end
	for _, getter in ipairs({ "GetRealmName", "GetNormalizedRealmName" }) do
		local fn = rawget(_G, getter)
		if type(fn) == "function" then
			local ok, value = pcall(fn)
			if ok then text = ReplaceWord(text, value, "<realm>") end
		end
	end
	if type(GetGuildInfo) == "function" then
		local ok, guild = pcall(GetGuildInfo, "player")
		if ok then text = ReplaceWord(text, guild, "<guild>") end
	end
	return text
end

-- One entry as a bug report body (Markdown). Quoted text in the message
-- and stack is cut to its length; the signature still comes from the
-- full message, so the same error groups the same way.
function Errors:FormatIssue(entry)
	local context = self:Context(entry) or {}
	local build = context.build
	if not build then
		local ok, version, number, _, interface = pcall(GetBuildInfo)
		if ok then build = ("%s (%s), interface %s"):format(Safe(version), Safe(number), Safe(interface)) end
	end
	local function row(name, value)
		return value ~= nil and value ~= "" and ("| %s | %s |"):format(name, tostring(value)) or nil
	end
	local lines = {
		("**%s** in %s, seen %d %s."):format(entry.kind, entry.addon or "?", entry.count, entry.count == 1 and "time" or "times"),
		"",
		"| | |", "|---|---|",
	}
	for _, line in ipairs({
		row("EldoUI", entry.version or context.version or E.version),
		row("Game build", build),
		row("Error signature", self:Signature(entry)),
		row("Locale", context.locale),
		row("Character", context.class and ("level %s %s"):format(context.level or "?", context.class)),
		row("Zone", entry.zone and (entry.zone .. (entry.instance and entry.instance ~= "none" and (" (" .. entry.instance .. ")") or ""))),
		row("In combat", entry.combat and "yes" or "no"),
		row("First / last seen", date("%Y-%m-%d %H:%M", entry.first) .. " / " .. date("%Y-%m-%d %H:%M", entry.last)),
		row("Enabled modules", context.modules),
	}) do table.insert(lines, line) end
	table.insert(lines, "")
	table.insert(lines, "```")
	table.insert(lines, ScrubQuoted(entry.message))
	table.insert(lines, "```")
	if entry.stack and entry.stack ~= "" then
		table.insert(lines, "<details><summary>Stack</summary>\n\n```\n" .. ScrubQuoted(entry.stack) .. "\n```\n</details>")
	end
	if type(entry.locals) == "string" and entry.locals ~= "" then
		table.insert(lines, "<details><summary>Local variables</summary>\n\n```\n" .. ScrubLocals(entry.locals) .. "\n```\n</details>")
	end
	-- /eui diag of the session the report is made in (client, modules,
	-- restrictions, secret value probes): often the missing context.
	if E.GetDiagnosticsText then
		local ok, diag = pcall(E.GetDiagnosticsText, E)
		if ok and type(diag) == "string" and diag ~= "" then
			table.insert(lines, "<details><summary>Diagnostics (session of this report)</summary>\n\n```\n" .. ScrubLocals(diag) .. "\n```\n</details>")
		end
	end
	-- Lets the issue tracker group reports of the same error.
	table.insert(lines, "")
	table.insert(lines, ("<!-- eldoui-error-sig: %s -->"):format(self:Signature(entry)))
	return table.concat(lines, "\n")
end

-- The text the Report button shows: the issue body, scrubbed. It is also
-- the full preview: nothing else is ever sent, and EldoUI sends nothing
-- by itself; the player copies it into the bug form.
function Errors:ReportText(entry)
	return self:ScrubReport(self:FormatIssue(entry))
end

-- Facts about this session, saved once the modules are running.
function Errors:SaveContext()
	local db = EldoUIErrorsDB
	if not db then return end
	db.contexts = type(db.contexts) == "table" and db.contexts or {}
	local context = { version = E.version }
	local ok, version, build, _, interface = pcall(GetBuildInfo)
	if ok then context.build = ("%s (%s), interface %s"):format(Safe(version), Safe(build), Safe(interface)) end
	context.locale = GetLocale and GetLocale() or nil
	local okClass, className = pcall(UnitClass, "player")
	if okClass and not (issecretvalue and issecretvalue(className)) and className then context.class = className end
	local okLevel, level = pcall(UnitLevel, "player")
	if okLevel and type(level) == "number" and not (issecretvalue and issecretvalue(level)) then context.level = level end
	local modules = {}
	for name, module in pairs(E.modules or {}) do
		if module.active then table.insert(modules, name) end
	end
	table.sort(modules)
	context.modules = table.concat(modules, ", ")
	local others = {}
	if C_AddOns and C_AddOns.GetNumAddOns then
		for index = 1, C_AddOns.GetNumAddOns() do
			local name = C_AddOns.GetAddOnInfo(index)
			if name and name ~= addonName and C_AddOns.IsAddOnLoaded(index) then table.insert(others, name) end
		end
	end
	context.addons = Truncate(table.concat(others, ", "), 600)
	db.contexts[self.session] = context
	for session in pairs(db.contexts) do
		if session <= self.session - MAX_CONTEXTS then db.contexts[session] = nil end
	end
end

---------------------------------------------------------------------------
-- Catching
---------------------------------------------------------------------------
local inside = false
local previous = geterrorhandler()

local function Record(kind, message, stack, locals, addon)
	if inside then return end
	inside = true
	pcall(Errors.Add, Errors, kind, message, stack, nil, locals, addon)
	inside = false
end

-- The call chain of a blocked action without this file's own lines. The
-- game raises the event while the blocked call is still running, so the
-- stack still shows who made it.
local function BlockedStack()
	if not debugstack then return "" end
	local ok, stack = pcall(debugstack, 2)
	if not ok or type(stack) ~= "string" then return "" end
	local lines = {}
	for line in stack:gmatch("[^\n]+") do
		-- The file a stack line starts with; another addon's Core/Errors.lua stays.
		local head = line:match("^%s*([^:]*)") or ""
		local own = head:find("Core[\\/]Errors%.lua") and (head:find("EldoUI[\\/]") or not head:find("[Aa]dd[Oo]ns"))
		if not own then lines[#lines + 1] = line end
	end
	return table.concat(lines, "\n")
end

-- "<folder>/<file>:<line>" of the first file under Interface/AddOns in a stack.
local function FirstCallSite(stack)
	for line in stack:gmatch("[^\n]+") do
		local path, number = line:match("[Ii]nterface[\\/][Aa]dd[Oo]ns[\\/]([^:\"%]]+%.lua)\"?%]?:(%d+)")
		if path then return path:gsub("\\", "/") .. ":" .. number end
	end
end

-- One log line for ADDON_ACTION_BLOCKED and ADDON_ACTION_FORBIDDEN. The
-- game's function name already ends in "()". When the game can't name the
-- function ("UNKNOWN()"), the first addon file in the stack is added, so
-- different call sites stay separate entries.
-- A blocked entry keeps no local variables: at this point they would be
-- this file's own, not the blocked caller's. A repeat of a blocked call
-- already logged this session takes no new stack.
-- One burst on a row of numbered frames ("MultiBar5Button1:SetShown()" to
-- "...Button12") is one entry: the frame's last number becomes "<n>".
local function FoldFrameNumber(fn)
	local frame, method = fn:match("^(.-%a)%d+(:[%w_]+%(%))$")
	if frame then return frame .. "<n>" .. method end
	return fn
end
Errors.FoldFrameNumber = FoldFrameNumber

local function RecordBlocked(event, blamed, name)
	local fn = Safe(name)
	if not fn:find("%)$") then fn = fn .. "()" end
	fn = FoldFrameNumber(fn)
	local owner = Safe(blamed)
	local verb = event == "ADDON_ACTION_FORBIDDEN" and "Forbidden" or "Blocked"
	local addon = type(blamed) == "string" and owner ~= "(secret value)" and owner or nil
	local function Message(text) return ("%s: %s tried to call the protected function %s"):format(verb, owner, text) end
	if fn ~= "UNKNOWN()" and Errors:Known("blocked", Message(fn)) then
		Record("blocked", Message(fn), nil, nil, addon)
		return
	end
	local stack = BlockedStack()
	if fn == "UNKNOWN()" then
		local site = FirstCallSite(stack)
		if site then fn = fn .. " at " .. site end
	end
	Record("blocked", Message(fn), stack, nil, addon)
end

-- Our handler records, then hands the error on unchanged, so Blizzard (or
-- any other error addon) still gets it. Blizzard only pops up a window when
-- the scriptErrors setting is on; it never writes errors to chat.
-- `forwarding` stops a loop: another addon that saved ours as its own
-- "previous" handler (seterrorhandler(function(m) ...; old(m) end)) and
-- that Reclaim below then put behind ours would call us back forever.
local forwarding = false

local function Handler(message, ...)
	if forwarding then return end
	if Errors:Known("error", message) then
		-- A repeat: counted, no new stack or locals.
		Record("error", message)
	else
		-- The level of the function that raised the error, the way the
		-- game's own handler finds it (3 when the client can't tell). Read
		-- and used straight from here, with no pcall in between, so the
		-- level points at the same function for the stack and the locals.
		local level = 3
		local height = type(GetCallstackHeight) == "function" and GetCallstackHeight() or nil
		local errorHeight = type(GetErrorCallstackHeight) == "function" and GetErrorCallstackHeight() or nil
		if type(height) == "number" and type(errorHeight) == "number" and height - (errorHeight - 1) >= 1 then
			level = height - (errorHeight - 1)
		end
		local locals = debuglocals and debuglocals(level) or nil
		local stack = debugstack and debugstack(level) or nil
		Record("error", message, stack, type(locals) == "string" and locals or nil)
	end
	if not previous then return end
	forwarding = true
	local ok, result = pcall(previous, message, ...)
	forwarding = false
	if ok then return result end
end
seterrorhandler(Handler)

-- Another addon may set its own handler later. Forever forbids hooking
-- seterrorhandler, so check after each addon loads and at login instead:
-- put ours back in front and pass errors on to theirs, so both keep working.
local function Reclaim()
	local current = geterrorhandler and geterrorhandler()
	if type(current) ~= "function" or current == Handler then return end
	previous = current
	seterrorhandler(Handler)
end
Errors.Reclaim = Reclaim

-- The game's Lua error window (General > Lua errors): Hide sets the
-- scriptErrors CVar to 0 so no window pops up and waits for a click; the
-- log above still records every error. Don't touch puts back the value the
-- player had before EldoUI changed it.
local POPUP_CVAR = { HIDE = "0", SHOW = "1" }
function Errors:ApplyPopup()
	local general = E.db and E.db.general
	if not (general and E.SetCVar) then return end
	local value = POPUP_CVAR[general.errorPopup]
	if value then
		E:SetCVar("scriptErrors", value, "errorPopup")
	elseif E.RestoreCVars then
		E:RestoreCVars("errorPopup")
	end
end
E:RegisterEvent("PLAYER_LOGIN", function() Errors:ApplyPopup() end, "ErrorPopup", "engines")

-- One notice per session when nothing else shows that an error was logged:
-- the game's error window is hidden and no Chat "Errors" button can show.
-- The flag is set before the alert, and the alert runs inside pcall, so an
-- error in the alert itself can never bring the notice back in a loop.
local loggedIn, noticed, pending = false, false, false

-- True when the Chat module can show its Errors button with a count.
function Errors:ChatButtonShows()
	local chat = E.GetModule and E:GetModule("Chat")
	if not (chat and chat.active and type(chat.Allowed) == "function") then return false end
	local ok, allowed = pcall(chat.Allowed, chat, "replace")
	return ok and allowed and true or false
end

function Errors:WantsNotice()
	if noticed or not loggedIn or self.unseen == 0 or self.lastKind == "warning" then return false end
	local general = E.db and E.db.general
	if not (general and general.errorPopup == "HIDE") then return false end
	return not self:ChatButtonShows()
end

local function Notice()
	pending = false
	if not Errors:WantsNotice() or not E.PushAlert then return end
	noticed = true
	local L = E.L
	pcall(E.PushAlert, E, {
		key = "EldoUI_ErrorLogged", title = L["Lua errors"],
		text = L["A Lua error was logged. Type %s to see it."]:format("/eui errors"),
		actions = {
			{ label = L["Show"], func = function() E:ToggleErrorWindow(true) end },
			{ label = L["Later"] },
		},
	})
end

-- done = true keeps the notice quiet for the rest of the session.
function Errors:ResetNotice(done)
	noticed, pending = done and true or false, false
end

Errors:OnChange("ErrorNotice", function()
	if pending or noticed or not loggedIn then return end
	pending = true
	C_Timer.After(0, Notice)
end)
-- Errors from loading show once the game is up.
E:RegisterEvent("PLAYER_LOGIN", function()
	loggedIn = true
	if not pending then
		pending = true
		C_Timer.After(1, Notice)
	end
end, "ErrorNotice", "modules")

-- The game could not load the saved settings of EldoUI or an EldoUI plugin
-- (`name`): one log entry, and for EldoUI the session runs on defaults.
function Errors:SettingsTooLarge(name)
	if name ~= addonName and not (type(name) == "string" and name:find("^EldoUI_")) then return end
	if name == addonName then E.settingsNotLoaded = true end
	Record("warning", ("Saved settings too large to load: %s"):format(name), nil, nil, name)
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("ADDON_ACTION_BLOCKED")
frame:RegisterEvent("ADDON_ACTION_FORBIDDEN")
pcall(frame.RegisterEvent, frame, "LUA_WARNING")
-- The game could not load an addon's saved settings (too large for the
-- memory it has). It fires before ADDON_LOADED; for EldoUI the session runs
-- on defaults and the setup stays closed (E:CheckInstall).
pcall(frame.RegisterEvent, frame, "SAVED_VARIABLES_TOO_LARGE")
frame:SetScript("OnEvent", function(self, event, arg1, arg2)
	if event == "PLAYER_ENTERING_WORLD" then
		Reclaim()
		-- Modules enable at login; wait a moment so the list is complete.
		C_Timer.After(2, function() pcall(Errors.SaveContext, Errors) end)
	elseif event == "ADDON_LOADED" then
		Reclaim()
		if arg1 ~= addonName or self.loaded then return end
		self.loaded = true
		EldoUIErrorsDB = type(EldoUIErrorsDB) == "table" and EldoUIErrorsDB or {}
		local db = EldoUIErrorsDB
		db.session = (db.session or 0) + 1
		db.entries = type(db.entries) == "table" and db.entries or {}
		-- Errors caught before the saved log loaded join it now.
		local early = Errors.entries
		Errors.entries, Errors.byKey, Errors.session = db.entries, {}, db.session
		for _, entry in ipairs(Errors.entries) do
			-- Logs saved before the scrub may still hold text locals.
			if type(entry.locals) == "string" then entry.locals = ScrubLocals(entry.locals) end
			Errors.byKey[EntryKey(entry)] = entry
		end
		for _, entry in ipairs(early) do
			entry.session = Errors.session
			local key = EntryKey(entry)
			local saved = Errors.byKey[key]
			if saved then
				-- Like a repeat in a new session (Errors:Add): this
				-- session's occurrence brings its stack and context.
				if saved.session ~= entry.session then
					for _, field in ipairs({ "stack", "locals", "addon", "version", "zone", "instance", "combat" }) do
						if entry[field] ~= nil then saved[field] = entry[field] end
					end
				end
				saved.count, saved.last, saved.session = saved.count + entry.count, entry.last, entry.session
			else
				Errors.byKey[key] = entry
				table.insert(Errors.entries, entry)
			end
		end
		-- Same eviction as Add, so no stale byKey row is left behind.
		Trim(Errors)
		Errors:Notify()
	elseif event == "LUA_WARNING" then
		Record("warning", arg2 or arg1)
	elseif event == "SAVED_VARIABLES_TOO_LARGE" then
		-- EldoUI's own settings load just before its ADDON_LOADED; a plugin's
		-- can come later.
		local name = type(arg1) == "string" and not E:IsSecret(arg1) and arg1 or nil
		if name == addonName and self.loaded then return end
		Errors:SettingsTooLarge(name)
	else
		RecordBlocked(event, arg1, arg2)
	end
end)
