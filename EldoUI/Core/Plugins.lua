-- EldoUI plugin API: the plugin list, version requirements, setup
-- pages for the installer and the optional version notice.
-- The full guide for plugin authors is docs/PLUGINS.md.
--
-- A plugin is a separate addon with `## Dependencies: EldoUI` in its .toc.
-- It talks to EldoUI through the global `EldoUI` and usually registers one
-- or more modules:
--
--   local E = EldoUI
--   local M = E:NewModule("MyBars", {
--       title = "My Bars", desc = "Extra bars.",
--       plugin = "MyBarsAddon",      -- the plugin's addon folder name
--       version = "1.2.0",           -- optional, read from the .toc otherwise
--       minEldoUI = "0.6.0",         -- optional: warn on an older EldoUI
--   })
--   M.options = { ... }              -- its page, listed under Plugins
--
-- Plugins without a module (only tags, datatexts, styles ...) list
-- themselves with E:RegisterPlugin(addon, info).
--
-- API:
--   E:RegisterPlugin(addon, info)    list a plugin; info: title, version,
--                                    author, desc, minEldoUI, url (all
--                                    optional, the .toc fills the gaps)
--   E:GetPlugin(addon) / E:IteratePlugins()
--   E:CompareVersions(a, b)          -1, 0 or 1; nil if one isn't a version
--   E:IsVersionAtLeast(version)      true when this EldoUI is that new
--   E:RegisterInstallStep(step)      a setup page (see below)
--   E:GetPluginInstallerPages([opts]) the setup pages in order;
--                                    opts.pending = only the ones this
--                                    character hasn't answered yet
--   E:SetInstallStepState(key, state) "applied", "skipped" or "seen" (a
--                                    page without Apply); nil asks again
--   E:RunPluginSetup([onDone], [opts]) show setup pages in the plugin setup
--                                    window; onDone runs when it closes
--                                    (at once when nothing is pending)
--   E:GetInstallKit()                the text/button/check helpers that a
--                                    step's Build receives
--
-- A setup page (install step) for a module or plugin:
--   E:RegisterInstallStep({
--       key = "MyBars:layout",       -- unique, required
--       plugin = "MyBarsAddon",      -- or module = "MyBars"
--       title = "Bar layout",        -- required
--       short = "Bars",              -- step dot label (default: title)
--       desc = "One line under the title.",
--       order = 100,                 -- lower first
--       text = "A paragraph",        -- drawn when there is no Build
--       Build = function(frame, kit) end,  -- draw once
--       Refresh = function(frame) end,     -- every time it shows
--       Apply = function() end,      -- the player clicked Apply (out of combat)
--       HasChoice = function() return true end,
--       Summary = function() return "Bars: compact" end,
--       when = function() return true end, -- false leaves it out
--       version = 1,                 -- raise to ask again after an update
--   })
-- Pages change nothing on their own: only Apply does, and only when the
-- player clicks it. The EldoUI installer shows the pages as its own steps
-- before Finish, and the ones the player didn't reach right after Finish;
-- pages of a plugin installed later open once at login.
--
-- Version notice: EldoUI and each plugin send their version to the guild
-- and the group (an addon message, never during an encounter, PvP or
-- chat lockdown, at most once a minute per channel). A newer version seen
-- gives one chat line per addon and session. One switch turns both off.
local _, E = ...
local L = E.L

E.plugins = {}
E.pluginOrder = {}

local installSteps = {}   -- key -> normalized step
local stepOrder = {}      -- keys in registration order
local loggedIn = false

local PREFIX = "EldoUIVer"
local SEND_GAP = 60        -- seconds between two messages on one channel
local MAX_MESSAGE = 250

local Refresh -- forward: rebuilds the Plugins page

local function StripCodes(text)
	if type(text) ~= "string" then return text end
	return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""))
end

local function Metadata(addon, field)
	if not (C_AddOns and C_AddOns.GetAddOnMetadata) or type(addon) ~= "string" then return nil end
	local ok, value = pcall(C_AddOns.GetAddOnMetadata, addon, field)
	if ok and type(value) == "string" and value ~= "" then return value end
end

---------------------------------------------------------------------------
-- Versions
---------------------------------------------------------------------------
-- "1.2.3", "v1.2", "0.6.0-beta2" -> { 1, 2, 3 }. Anything else (the "dev"
-- checkout, a git hash) is not a version.
local function Parts(version)
	if type(version) == "number" then version = tostring(version) end
	if type(version) ~= "string" or #version > 32 then return nil end
	local core = version:match("^%s*[vV]?(%d+[%.%d]*)")
	if not core then return nil end
	local parts = {}
	for number in core:gmatch("%d+") do
		parts[#parts + 1] = tonumber(number)
		if #parts == 4 then break end
	end
	return parts
end

function E:CompareVersions(a, b)
	local pa, pb = Parts(a), Parts(b)
	if not (pa and pb) then return nil end
	for index = 1, math.max(#pa, #pb) do
		local x, y = pa[index] or 0, pb[index] or 0
		if x ~= y then return x < y and -1 or 1 end
	end
	return 0
end

-- A developer checkout ("dev") counts as new enough for everything.
function E:IsVersionAtLeast(version)
	local result = self:CompareVersions(self.version, version)
	return result == nil or result >= 0
end

---------------------------------------------------------------------------
-- Plugin list
---------------------------------------------------------------------------
-- Fill the gaps from the plugin's .toc and work out the version warning.
local function Update(plugin)
	local addon = plugin.addon
	plugin.title = plugin.info.title or StripCodes(Metadata(addon, "Title")) or addon
	plugin.version = plugin.info.version or Metadata(addon, "Version")
	plugin.author = plugin.info.author or StripCodes(Metadata(addon, "Author"))
	plugin.desc = plugin.info.desc or StripCodes(Metadata(addon, "Notes"))
	plugin.url = plugin.info.url or Metadata(addon, "X-Website")
	plugin.minEldoUI = plugin.info.minEldoUI or Metadata(addon, "X-Min-EldoUI")
	plugin.tooOld = plugin.minEldoUI ~= nil and not E:IsVersionAtLeast(plugin.minEldoUI)
end

local function Warn(plugin)
	if not (plugin.tooOld and loggedIn) or plugin.warned then return end
	plugin.warned = true
	E:Print(L["%s needs EldoUI %s or newer (you have %s). Update EldoUI, or parts of the plugin may not work."]
		:format(plugin.title, plugin.minEldoUI, E.version))
end

function E:RegisterPlugin(addon, info)
	assert(type(addon) == "string" and addon ~= "", "EldoUI:RegisterPlugin(addon, info): addon must be the plugin's folder name")
	local plugin = self.plugins[addon]
	if not plugin then
		plugin = { addon = addon, info = {}, modules = {} }
		self.plugins[addon] = plugin
		table.insert(self.pluginOrder, addon)
	end
	-- Later calls add to what an earlier call (or NewModule) gave.
	for key, value in pairs(info or {}) do
		if key ~= "modules" then plugin.info[key] = value end
	end
	Update(plugin)
	Warn(plugin)
	if Refresh then Refresh() end
	return plugin
end

-- Called by E:NewModule for a module with a `plugin` field.
function E:AttachPluginModule(module, info)
	if self:IsFirstPartyModule(module) then return end
	local plugin = self:RegisterPlugin(module.plugin, {
		version = info and info.version, minEldoUI = info and info.minEldoUI,
		author = info and info.author, url = info and info.url,
	})
	if not tContains(plugin.modules, module.name) then table.insert(plugin.modules, module.name) end
	if Refresh then Refresh() end
	return plugin
end

function E:GetPlugin(addon)
	return self.plugins[addon]
end

-- Plugins in the order they registered.
function E:IteratePlugins()
	local index = 0
	return function()
		index = index + 1
		local addon = self.pluginOrder[index]
		if addon then return addon, self.plugins[addon] end
	end
end

local function PluginEnabled(plugin)
	if #plugin.modules == 0 then return true end
	for _, name in ipairs(plugin.modules) do
		local module = E.modules[name]
		if module and module:IsEnabled() then return true end
	end
	return false
end

---------------------------------------------------------------------------
-- Settings: account-wide switches, per-character setup answers
---------------------------------------------------------------------------
local SETTINGS = { versionCheck = true, setupPopup = true }
E:RegisterGlobal("plugins", SETTINGS, { title = "Plugins" })
E:RegisterPrivate("pluginSetup", { done = {} })

local function Settings()
	return E:GetGlobal("plugins") or SETTINGS
end

local function Answers()
	local private = E:GetPrivate("pluginSetup")
	if not private then return {} end
	private.done = type(private.done) == "table" and private.done or {}
	return private.done
end

---------------------------------------------------------------------------
-- Install steps
---------------------------------------------------------------------------
local function OwnerTitle(step)
	local plugin = step.plugin and E.plugins[step.plugin]
	if plugin then return plugin.title end
	local module = step.module and E.modules[step.module]
	if module then return module.title end
	return step.plugin or step.module or "EldoUI"
end

function E:RegisterInstallStep(step)
	assert(type(step) == "table", "EldoUI:RegisterInstallStep(step): step must be a table")
	assert(type(step.key) == "string" and step.key ~= "", "EldoUI:RegisterInstallStep: step.key is required")
	assert(type(step.title) == "string", "EldoUI:RegisterInstallStep: step.title is required")
	-- Every field the installer reads exists, so it never checks for nil.
	step.short = step.short or step.title
	step.desc = step.desc or ""
	step.order = tonumber(step.order) or 100
	step.version = step.version or 1
	if type(step.HasChoice) ~= "function" then
		local hasApply = type(step.Apply) == "function"
		step.HasChoice = function() return hasApply end
	end
	if type(step.Summary) ~= "function" then
		step.Summary = function() return E:Translate(step.title) end
	end
	if type(step.Refresh) ~= "function" then step.Refresh = function() end end
	if type(step.Build) ~= "function" then
		local text = step.text
		step.Build = function(frame, kit)
			if text then
				local paragraph = kit.Paragraph(frame, 13, text)
				paragraph:SetPoint("TOPLEFT")
				paragraph:SetPoint("TOPRIGHT", frame, "TOPRIGHT")
			end
		end
	end
	if step.plugin and not E.plugins[step.plugin] then self:RegisterPlugin(step.plugin) end
	if not installSteps[step.key] then table.insert(stepOrder, step.key) end
	installSteps[step.key] = step
	if Refresh then Refresh() end
	-- A plugin that loads after login (load on demand) still gets asked.
	if loggedIn then E:QueuePluginSetupCheck() end
	return step
end

local function StepAvailable(step)
	if type(step.when) ~= "function" then return true end
	local ok, result = pcall(step.when)
	return ok and result ~= false
end

local function Answered(step)
	local answer = Answers()[step.key]
	return type(answer) == "table" and tostring(answer.version) == tostring(step.version)
end

-- opts: pending (only unanswered), plugin (one plugin's or module's pages).
function E:GetPluginInstallerPages(opts)
	opts = opts or {}
	local list = {}
	for _, key in ipairs(stepOrder) do
		local step = installSteps[key]
		if StepAvailable(step) and not (opts.pending and Answered(step))
			and (not opts.plugin or step.plugin == opts.plugin or step.module == opts.plugin) then
			step.owner = OwnerTitle(step)
			list[#list + 1] = step
		end
	end
	local position = {}
	for index, key in ipairs(stepOrder) do position[key] = index end
	table.sort(list, function(a, b)
		if a.order ~= b.order then return a.order < b.order end
		return position[a.key] < position[b.key]
	end)
	return list
end

-- "applied", "skipped" or "seen"; nil forgets the answer (asked again).
function E:SetInstallStepState(key, state)
	local step = installSteps[key]
	if not step then return end
	if state == nil then
		Answers()[key] = nil
	else
		Answers()[key] = { version = step.version, state = state }
	end
end

function E:GetInstallStepState(key)
	local step = installSteps[key]
	if not (step and Answered(step)) then return nil end
	return Answers()[key].state
end

---------------------------------------------------------------------------
-- Plugin setup window
---------------------------------------------------------------------------
local WIDTH, HEIGHT = 640, 440
local window
local run -- { steps, index, onDone, states = {} }

local function Accent(alpha)
	local c = E.media.accentColor
	return c[1], c[2], c[3], alpha or 1
end
-- Text in a token color (good, warn, secondary).
local function Tinted(kind, text) return E:TokenHex(E.tokens.text[kind]) .. tostring(text) .. "|r" end

-- Footer buttons of the setup window (E.WindowKit, footer height).
local function Button(parent, text, width, onClick)
	return E.WindowKit.Button(parent, text, width, onClick, true)
end

-- Helpers a step's Build gets, so plugin pages look like EldoUI's own.
-- One kit: the check, tooltip and paragraph are the E.UIKit /
-- E.WindowKit parts, looked up when called (Core/UIKit.lua loads later).
local kit = {}
function kit.Text(parent, size, text, justify)
	local fontString = E:CreateText(parent, size or E.tokens.size.body, justify or "LEFT")
	fontString:SetText(text or "")
	return fontString
end
function kit.Paragraph(parent, size, text)
	local fontString = E.WindowKit.Paragraph(parent, size, text)
	fontString:SetSpacing(3)
	return fontString
end
function kit.Secondary(fontString)
	return E.WindowKit.Secondary(fontString)
end
kit.Button = Button
function kit.Check(parent, label, desc, onClick)
	return E.UIKit.Check(parent, label, desc, onClick)
end
function kit.Tooltip(frame, title, text)
	return E.UIKit.Tooltip(frame, title, text)
end
function kit.Accent() return Accent() end

function E:GetInstallKit()
	return kit
end

local function Finish()
	local current = run
	run = nil
	if window and window:IsShown() then
		window.finishing = true
		window:Hide()
		window.finishing = false
	end
	if current and current.onDone then
		local ok, err = pcall(current.onDone)
		if not ok then geterrorhandler()(err) end
	end
end

local UpdateWindow

local function Go(index)
	if not run then return end
	if index > #run.steps then
		Finish()
		return
	end
	run.index = math.max(1, index)
	UpdateWindow()
end

local function Answer(state)
	local step = run and run.steps[run.index]
	if not step then return end
	run.states[step.key] = state
	E:SetInstallStepState(step.key, state)
end

local function ApplyCurrent()
	local step = run and run.steps[run.index]
	if not (step and step.Apply) then return end
	local index = run.index
	Answer("applied")
	-- Apply may move protected frames: it waits for the end of combat.
	E:RunOutOfCombat(function()
		local ok, err = pcall(step.Apply)
		if not ok then geterrorhandler()(("EldoUI setup page %s failed: %s"):format(step.key, tostring(err))) end
	end)
	Go(index + 1)
end

local function CreateWindow()
	-- The E.WindowKit shell (Core/Skin.lua): the same look as the installer
	-- and the options window.
	window = E.WindowKit.CreateWindow("EldoUIPluginSetup", { width = WIDTH, height = HEIGHT })
	window.counter = kit.Secondary(E:CreateText(window.headerRight, E.tokens.size.small, "RIGHT"))
	window.counter:SetPoint("RIGHT", 0, 0)
	window.caption = kit.Secondary(E:CreateText(window.headerRight, E.tokens.size.small, "RIGHT"))
	window.caption:SetPoint("RIGHT", window.counter, "LEFT", -12, 0)
	window.desc = window.subtitle
	window.line = window.headerLine

	window.next = Button(window, L["Next"], 110, function()
		local step = run and run.steps[run.index]
		if step and not run.states[step.key] then Answer(step.Apply and "skipped" or "seen") end
		Go(run.index + 1)
	end)
	window.next:SetPoint("BOTTOMRIGHT", window.footer, "BOTTOMRIGHT", 0, 6)
	window.apply = Button(window, L["Apply"], 110, ApplyCurrent)
	window.apply:SetPoint("RIGHT", window.next, "LEFT", -8, 0)
	window.back = Button(window, L["Back"], 90, function() Go(run.index - 1) end)
	window.back:SetPoint("BOTTOMLEFT", window.footer, "BOTTOMLEFT", 0, 6)
	window.status = kit.Secondary(E:CreateText(window, E.tokens.size.label, "LEFT"))
	window.status:SetPoint("LEFT", window.back, "RIGHT", 12, 0)

	window:SetScript("OnHide", function()
		if window.finishing or not run then return end
		-- Closed early: the pages shown count as skipped, so they don't
		-- open again at the next login. The Plugins page runs them again.
		for index = 1, run.index do
			local step = run.steps[index]
			if step and not run.states[step.key] then E:SetInstallStepState(step.key, "skipped") end
		end
		E:Print(L["Plugin setup closed. Run it again any time from the Plugins page or with /eui plugins setup."])
		Finish()
	end)
	window:RegisterEvent("PLAYER_REGEN_DISABLED")
	window:RegisterEvent("PLAYER_REGEN_ENABLED")
	window:SetScript("OnEvent", function() UpdateWindow() end)
end

UpdateWindow = function()
	if not (window and window:IsShown() and run) then return end
	local step = run.steps[run.index]
	window.line:SetColorTexture(Accent())
	window.caption:SetText(L["Plugin setup: %s"]:format(step.owner or OwnerTitle(step)))
	window.counter:SetText(L["Page %d of %d"]:format(run.index, #run.steps))
	window.title:SetText(E:Translate(step.title))
	window.desc:SetText(E:Translate(step.desc))
	for _, other in ipairs(run.steps) do
		if other.setupFrame then other.setupFrame:SetShown(other == step) end
	end
	if not step.setupFrame then
		step.setupFrame = CreateFrame("Frame", nil, window.content)
		step.setupFrame:SetAllPoints()
		local ok, err = pcall(step.Build, step.setupFrame, kit)
		if not ok then geterrorhandler()(("EldoUI setup page %s failed to build: %s"):format(step.key, tostring(err))) end
	end
	step.setupFrame:Show()
	local ok, err = pcall(step.Refresh, step.setupFrame)
	if not ok then geterrorhandler()(err) end

	local okChoice, hasChoice = pcall(step.HasChoice)
	hasChoice = okChoice and hasChoice
	local state = run.states[step.key]
	window.back:SetEnabled(run.index > 1)
	window.apply:SetShown(step.Apply ~= nil and hasChoice and state ~= "applied")
	local last = run.index == #run.steps
	if step.Apply and state ~= "applied" then
		window.next:SetText(last and L["Skip and close"] or L["Skip"])
	else
		window.next:SetText(last and L["Done"] or L["Next"])
	end
	if InCombatLockdown() then
		window.status:SetText(Tinted("warn", L["In combat: Apply waits until combat ends."]))
	elseif state == "applied" then
		window.status:SetText(Tinted("good", L["Applied"]))
	else
		window.status:SetText("")
	end
end

-- Show setup pages. opts: all (also pages answered before), plugin (one
-- plugin's or module's pages). onDone runs once the window closes, or at
-- once when there is nothing to show.
function E:RunPluginSetup(onDone, opts)
	opts = opts or {}
	if run then
		-- Already open: chain the callback.
		if onDone then
			local previous = run.onDone
			run.onDone = function()
				if previous then previous() end
				onDone()
			end
		end
		return true
	end
	local steps = self:GetPluginInstallerPages({ pending = not opts.all, plugin = opts.plugin })
	if #steps == 0 then
		if onDone then onDone() end
		return false
	end
	if InCombatLockdown() then
		self:RunOutOfCombat(function() self:RunPluginSetup(onDone, opts) end)
		return true
	end
	if not window then CreateWindow() end
	run = { steps = steps, index = 1, onDone = onDone, states = {} }
	E:SetPanelTemplate(window)
	window:Show()
	UpdateWindow()
	return true
end

function E:IsPluginSetupShown()
	return window ~= nil and window:IsShown()
end

-- For plugins: the window and the current run.
function E:GetPluginSetupWindow()
	return window, run
end

-- At login (or when a late plugin registers a page): open the pages this
-- character hasn't answered, unless the EldoUI installer still has to run
-- (it shows them after its own Finish) or is open right now.
local checkQueued = false
function E:QueuePluginSetupCheck(delay)
	if checkQueued then return end
	checkQueued = true
	C_Timer.After(delay or 3, function()
		checkQueued = false
		if not Settings().setupPopup or run then return end
		local installed = type(EldoUIDB) == "table" and EldoUIDB.installed and EldoUIDB.installed[E.charKey]
		if installed == nil then return end
		local installer = _G.EldoUIInstaller
		if installer and installer:IsShown() then return end
		E:RunOutOfCombat(function() E:RunPluginSetup() end)
	end)
end

---------------------------------------------------------------------------
-- Version notice
---------------------------------------------------------------------------
local CHANNELS = { GUILD = true, PARTY = true, RAID = true, INSTANCE_CHAT = true }
local lastSent = {}    -- channel -> time
local pendingSend = {} -- channel -> true while waiting for the restriction to end
local noticed = {}     -- addon -> newest version reported this session
local prefixReady = false
local wasInGroup = false

local function RegisterPrefix()
	if prefixReady then return true end
	if not (C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix) then return false end
	pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
	prefixReady = true
	return true
end

local function Restricted()
	if InCombatLockdown() then return true end
	if C_ChatInfo and C_ChatInfo.AreOutgoingAddonChatMessagesRestricted then
		local ok, restricted = pcall(C_ChatInfo.AreOutgoingAddonChatMessagesRestricted)
		if ok and restricted then return true end
	end
	return E.AddonCommsRestricted ~= nil and E:AddonCommsRestricted() or false
end

-- "1;0.6.0;MyBarsAddon=1.2.0,Other=0.3"
function E:GetVersionMessage()
	local parts = { "1", Parts(self.version) and self.version or "-" }
	local plugins = {}
	local length = #parts[1] + #parts[2] + 2
	for addon, plugin in self:IteratePlugins() do
		if Parts(plugin.version) and not addon:find("[;,=]") then
			local item = addon .. "=" .. plugin.version
			if length + #item + 1 > MAX_MESSAGE then break end
			plugins[#plugins + 1] = item
			length = length + #item + 1
		end
	end
	parts[3] = table.concat(plugins, ",")
	return table.concat(parts, ";")
end

local RetrySend
local function Send(channel)
	if not Settings().versionCheck or not CHANNELS[channel] then return false end
	if channel == "GUILD" and not IsInGuild() then return false end
	if (channel == "PARTY" or channel == "RAID" or channel == "INSTANCE_CHAT") and not IsInGroup() then return false end
	local now = GetTime()
	if lastSent[channel] and now - lastSent[channel] < SEND_GAP then return false end
	if Restricted() then
		pendingSend[channel] = true
		RetrySend()
		return false
	end
	if not RegisterPrefix() or not E.SendComm then return false end
	pendingSend[channel] = nil
	lastSent[channel] = now
	-- One plain message on the shared addon message queue, in the format
	-- every EldoUI version reads.
	return E:SendComm(PREFIX, E:GetVersionMessage(), channel, nil, { raw = true }) and true or false
end

local retryQueued = false
RetrySend = function()
	if retryQueued then return end
	retryQueued = true
	C_Timer.After(30, function()
		retryQueued = false
		for channel in pairs(pendingSend) do Send(channel) end
	end)
end

local function GroupChannel()
	-- Instance groups (battlegrounds, finder groups), where the client has them.
	local instance = _G.LE_PARTY_CATEGORY_INSTANCE
	if instance and IsInGroup(instance) then return "INSTANCE_CHAT" end
	if IsInRaid() then return "RAID" end
	if IsInGroup() then return "PARTY" end
end

-- Send to the guild and the group now (each at most once a minute).
function E:AnnounceVersions()
	local sent = Send("GUILD")
	local group = GroupChannel()
	if group then sent = Send(group) or sent end
	return sent
end

local function Notice(addon, title, mine, theirs)
	if noticed[addon] and E:CompareVersions(theirs, noticed[addon]) ~= 1 then return end
	local first = noticed[addon] == nil
	noticed[addon] = theirs
	if first then
		E:Print(L["A newer version of %s is out: %s (you have %s)."]:format(title, theirs, mine))
	end
	if Refresh then Refresh() end
end

-- A version from another player as it may be shown in chat: digits and
-- dots with an optional "-beta2" style suffix. Parts() reads only the
-- start, so "99 get it at …" or text codes would be printed otherwise.
local function ShownVersion(version)
	return type(version) == "string" and #version <= 24 and version:match("^[vV]?%d+[%d%.]*%-?[%w%.]*$") ~= nil
end

-- One message from another player. Only guild and group channels count;
-- secret or malformed messages are dropped.
function E:HandleVersionMessage(prefix, message, channel, sender)
	if prefix ~= PREFIX then return end
	if issecretvalue and (issecretvalue(message) or issecretvalue(channel) or issecretvalue(sender)) then return end
	if type(message) ~= "string" or not CHANNELS[channel] or #message > 255 then return end
	-- Our own message comes back on guild and group channels.
	if type(sender) == "string" then
		local short = Ambiguate and Ambiguate(sender, "none")
		if type(short) ~= "string" or short == "" then short = sender:gsub("%-.*$", "") end
		if E:IsMe(short) then return end
	end
	if not Settings().versionCheck then return end
	local format, eldo, plugins = message:match("^(%d+);([^;]*);?(.*)$")
	if format ~= "1" then return end
	if ShownVersion(eldo) and Parts(eldo) and Parts(self.version) and self:CompareVersions(eldo, self.version) == 1 then
		Notice("EldoUI", "EldoUI", self.version, eldo)
	end
	for addon, version in (plugins or ""):gmatch("([^,=]+)=([^,]+)") do
		local plugin = self.plugins[addon]
		if plugin and ShownVersion(version) and Parts(plugin.version) and Parts(version) and self:CompareVersions(version, plugin.version) == 1 then
			Notice(addon, plugin.title, plugin.version, version)
		end
	end
end

-- Newest version seen this session, when newer than the installed one.
function E:GetNewerVersionSeen(addon)
	return noticed[addon or "EldoUI"]
end

---------------------------------------------------------------------------
-- Plugins page
---------------------------------------------------------------------------
local proxy = {}
local page

local function PluginRows(options, index, plugin)
	local title = plugin.title .. (plugin.version and ("  " .. Tinted("secondary", plugin.version)) or "")
	table.insert(options, { type = "header", label = title })
	local lines = {}
	if plugin.desc and plugin.desc ~= "" then lines[#lines + 1] = plugin.desc end
	local facts = {}
	if plugin.author then facts[#facts + 1] = L["By %s."]:format(plugin.author) end
	if plugin.minEldoUI then facts[#facts + 1] = L["Needs EldoUI %s or newer."]:format(plugin.minEldoUI) end
	if plugin.url then facts[#facts + 1] = plugin.url end
	if #facts > 0 then lines[#lines + 1] = Tinted("secondary", table.concat(facts, "  ")) end
	if plugin.tooOld then
		lines[#lines + 1] = Tinted("warn", L["This EldoUI (%s) is older than the plugin needs. Update EldoUI."]:format(E.version))
	end
	local newer = noticed[plugin.addon]
	if newer then
		lines[#lines + 1] = E:Highlight(L["Version %s was seen in your guild or group."]:format(newer))
	end
	if #lines > 0 then table.insert(options, { type = "description", label = table.concat(lines, "\n") }) end
	if #plugin.modules > 0 then
		table.insert(options, { type = "toggle", key = "enabled" .. index, label = L["Use %s"]:format(plugin.title), reload = "off",
			desc = L["Switch every part of %s on or off. Blizzard's own version comes fully back after a reload."]:format(plugin.title) })
		for _, name in ipairs(plugin.modules) do
			local module = E.modules[name]
			if module and (module.options or E.styles[name]) then
				local label = #plugin.modules > 1 and L["Settings: %s"]:format(module.title) or L["Open settings"]
				table.insert(options, { type = "execute", label = label, testSafe = true,
					desc = L["Open the settings page of %s."]:format(module.title),
					func = function() E:ToggleConfig("module:" .. name) end })
			end
		end
	end
	if #E:GetPluginInstallerPages({ plugin = plugin.addon }) > 0 then
		table.insert(options, { type = "execute", label = L["Run setup pages"],
			desc = L["Show the setup pages of %s again. Nothing changes until you click Apply on a page."]:format(plugin.title),
			func = function() E:RunPluginSetup(nil, { all = true, plugin = plugin.addon }) end })
	end
end

local function BuildOptions()
	local options = {
		{ type = "description", label = L["Plugins are separate addons that build on EldoUI. Their settings pages are in the sidebar under Plugins."] },
		{ type = "header", label = L["Notices"] },
		{ type = "toggle", key = "versionCheck", label = L["Version check"],
			desc = L["Tells guild and group members who run EldoUI your version in a hidden addon message, never in chat. One chat line when someone has a newer one. Never sent in combat, boss fights or PvP matches."] },
		{ type = "toggle", key = "setupPopup", label = L["Setup pages of new plugins"],
			desc = L["When a newly installed plugin has setup pages, they open once after login. Off: run them from this page."] },
	}
	local any = false
	local index = 0
	for _, plugin in E:IteratePlugins() do
		index = index + 1
		PluginRows(options, index, plugin)
		any = true
	end
	if not any then
		table.insert(options, { type = "header", label = L["Installed plugins"] })
		table.insert(options, { type = "description", label = L["No plugins are installed. EldoUI works fully without them."] })
	end
	if #E:GetPluginInstallerPages() > 0 then
		table.insert(options, { type = "header", label = L["Setup pages"] })
		table.insert(options, { type = "execute", label = L["Run all setup pages"],
			desc = L["Show every setup page of your plugins and modules again. Nothing changes until you click Apply on a page."],
			func = function() E:RunPluginSetup(nil, { all = true }) end })
	end
	return options
end

local function Target()
	local settings = Settings()
	proxy.versionCheck = settings.versionCheck
	proxy.setupPopup = settings.setupPopup
	local index = 0
	for _, plugin in E:IteratePlugins() do
		index = index + 1
		proxy["enabled" .. index] = PluginEnabled(plugin)
	end
	return proxy
end

local function Apply()
	local settings = Settings()
	local switchedOn = proxy.versionCheck and not settings.versionCheck
	settings.versionCheck = proxy.versionCheck and true or false
	settings.setupPopup = proxy.setupPopup and true or false
	local index = 0
	for _, plugin in E:IteratePlugins() do
		index = index + 1
		local on = proxy["enabled" .. index]
		if on ~= nil and on ~= PluginEnabled(plugin) then
			for _, name in ipairs(plugin.modules) do E:SetModuleEnabled(name, on) end
		end
	end
	if switchedOn then E:AnnounceVersions() end
end

Refresh = function()
	if not page then return end
	-- Rebuilt the next time it shows (a plugin registered later).
	page.options = nil
	page.tabs = nil
end

local function RegisterPage()
	if page or not E.RegisterConfigPage then return end
	page = E:RegisterConfigPage("plugins", L["Plugins"], nil, Target, Apply, 1.6)
	page.build = BuildOptions
	page.desc = L["Installed plugins, their versions and setup pages, and the version check."]
	page.defaults = function() return SETTINGS end
end

---------------------------------------------------------------------------
-- Diagnostics and slash command
---------------------------------------------------------------------------
-- The status part of /eui diag: screen size and every plugin's version.
E:RegisterDiagnostics("Plugins", function()
	local lines = {}
	if GetPhysicalScreenSize then
		local width, height = GetPhysicalScreenSize()
		if width then table.insert(lines, ("   Resolution: %dx%d"):format(width, height)) end
	end
	table.insert(lines, ("   Plugins: %d"):format(#E.pluginOrder))
	for _, plugin in E:IteratePlugins() do
		local state = PluginEnabled(plugin) and "on" or "off"
		local warn = plugin.tooOld and (" " .. Tinted("warn", ("needs EldoUI %s"):format(plugin.minEldoUI))) or ""
		table.insert(lines, ("      %s (%s) %s, %s%s"):format(plugin.title, plugin.addon, plugin.version or "no version", state, warn))
	end
	local newer = noticed.EldoUI
	if newer then table.insert(lines, ("   Newer EldoUI seen: %s"):format(newer)) end
	return lines
end)

local function PrintList()
	if #E.pluginOrder == 0 then
		E:Print(L["No plugins are installed."])
		return
	end
	E:Print(L["Plugins:"])
	for _, plugin in E:IteratePlugins() do
		local line = ("  %s %s%s"):format(plugin.title, plugin.version or "", PluginEnabled(plugin) and "" or " " .. L["(off)"])
		if plugin.tooOld then line = line .. " " .. Tinted("warn", L["needs EldoUI %s"]:format(plugin.minEldoUI)) end
		local frame = _G.DEFAULT_CHAT_FRAME
		if frame then frame:AddMessage(line) end
	end
end

E:AddCommand("plugins", "[list | setup [name]]  the Plugins page; list = print them; setup = their setup pages again", function(arg)
	arg = strtrim(arg or "")
	local word, rest = arg:match("^(%S*)%s*(.-)$")
	word = (word or ""):lower()
	if word == "list" then
		PrintList()
	elseif word == "setup" then
		local target
		if rest ~= "" then
			local wanted = rest:lower()
			for addon, plugin in E:IteratePlugins() do
				if addon:lower() == wanted or plugin.title:lower() == wanted then target = addon end
			end
			if not target then
				E:Print(L["No plugin named %s."]:format(rest))
				return
			end
		end
		if not E:RunPluginSetup(nil, { all = true, plugin = target }) then E:Print(L["No setup pages to show."]) end
	else
		E:ToggleConfig("plugins")
	end
end, "General")

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local owner = {}

E:RegisterEvent("PLAYER_LOGIN", function()
	loggedIn = true
	RegisterPage()
	for _, plugin in E:IteratePlugins() do
		Update(plugin)
		Warn(plugin)
	end
	RegisterPrefix()
	E:RegisterEvent("CHAT_MSG_ADDON", function(_, _, ...) E:HandleVersionMessage(...) end, owner)
	E:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED", function(_, _, _, state)
		if not next(pendingSend) then return end
		E:AfterRestrictionEnds(state, function()
			if next(pendingSend) and not Restricted() then
				for channel in pairs(pendingSend) do Send(channel) end
			end
		end)
	end, owner)
	E:RegisterEvent("PLAYER_REGEN_ENABLED", function()
		if next(pendingSend) then RetrySend() end
	end, owner)
	E:RegisterEvent("GROUP_ROSTER_UPDATE", function()
		local inGroup = IsInGroup() and true or false
		-- Only when this character joins a group, not on every roster change.
		if inGroup and not wasInGroup then
			local channel = GroupChannel()
			if channel then C_Timer.After(5, function() Send(channel) end) end
		end
		wasInGroup = inGroup
	end, owner)
	wasInGroup = IsInGroup() and true or false
	C_Timer.After(15, function() E:AnnounceVersions() end)
	E:QueuePluginSetupCheck(8)
end, owner, "modules")
