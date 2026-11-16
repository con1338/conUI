-- EldoUI installer: a step-by-step setup wizard in the E.WindowKit window
-- shell (the options window's look). It opens on a character's first login
-- and any time with /eui install; /eui install <step> opens one step again.
--
--   Alt setup     a character that never ran the setup, on an account where
--                 another one did, gets one short page instead of the steps
--                 below: attach it to a set-up profile as it is, with its own
--                 chat tabs, game settings, other addons' profiles,
--                 click-casting and class spells (Core/InstallerAlt.lua)
--   Welcome       which profile to set up: the shared "EldoUI 1440p" as it is (an
--                 alt), a fresh one, or the current one; undo; Express setup
--                 (every step's recommended pick at once, then the last page)
--   UI scale      suggestion from the screen size, slider, live preview
--   Layout        one card per layout preset, previewed by applying it for now
--   Styles        full looks (layout, skin, accent, font and the layout's
--                 styles in one click), the skin grid, and one row of style presets
--                 per part of the UI (E.styles)
--   Role          damage, healer or tank layer, class details, healer click-casting
--   Modules       one check box per module, grouped like the options sidebar
--   Blizzard UI   which Blizzard elements EldoUI may change (Core/Blizzard.lua)
--   Chat          keep, EldoUI tabs (whispers, loot, channels) or reset the chat
--                 windows first; font size, class-colored names, a small preview
--   Game settings a few presentation CVars (lock bars, cooldown numbers, tooltips,
--                 tutorials, whispers) through E:SetCVar, so Blizzard default undoes them
--   Other addons  one checkbox per installed addon with an EldoUI profile (Core/AddonSetup.lua),
--                 and one per loaded addon a layout places (Modules/Integrations.lua)
--   Convenience   every helper that acts for the player (Core/Conveniences.lua),
--                 as ticked choices, with "Recommended for me"; auto repair
--                 (own gold unless the player picks the guild bank), sell gray
--                 items and faster auto loot start ticked on a first run
--   Keys and spells  the key set for bars 1 to 3, class spells and
--                 macros on empty buttons and spell rank upgrades in one
--                 preview (Core/KeybindPreview.lua); changes only with its
--                 own Apply, never at Finish. Express stops here too, with
--                 the pack's preset picked
--   <pages>       setup pages of modules and plugins (E:RegisterInstallStep, Core/Plugins.lua)
--   Finish        review with a "Change" button per step; after Finish the
--                 same page lists what changed, each group with "Revert this",
--                 and offers the reload
--
-- Rules:
--   * Every step is optional (Skip). Nothing changes until the player clicks
--     "Apply" on a step or Finish. The only exception is a preview (UI scale,
--     layout), which is undone by Back, the close button or Esc. A step's
--     Apply that worked says so in a short toast over the footer.
--   * Applying a step also keeps the previews picked on the steps before it.
--   * Running it again on a profile that was set up before asks first, and
--     starts with "keep" everywhere, so clicking through changes nothing.
--   * Alt safety: a first run that writes into a profile set up before (the
--     shared one, or the current one) starts the profile-wide steps (scale,
--     layout, role, Blizzard UI, convenience) on "keep"; the character's own
--     steps (chat, game settings, other addons) keep their suggestions.
--     "Start fresh" on a profile other characters use asks twice.
--   * A fresh profile gets its layout's sizes and module settings even when
--     the Layout step is kept, or the whole setup is skipped (ApplyFreshLayout).
--   * Finish applies the Modules step first, then the others in order, so the
--     layout places frames of modules turned on in the same run.
--   * Before the first change of a run the profile is backed up; the Welcome
--     step and /eui install undo put it back.
--   * Closing the window is "do later": previews are undone, the picks stay
--     for this session and /eui install goes on where it stopped. "Skip the
--     setup" on the Welcome step closes it for good.
--   * Anything that touches protected frames goes through E:RunOutOfCombat,
--     so a change clicked in combat waits until combat ends.
--   * Modules can still add their own install step with function M:OnInstall();
--     it runs at Finish when the profile is fresh.
--   * Setup pages from E:RegisterInstallStep show as steps before Finish.
--     They only change something when the player clicks their Apply; pages
--     the player didn't reach show in the plugin setup window after Finish.
--   * Every step owns a declared set of settings (STEP_OWNS) and writes
--     only those, on top of what is set. Applying a step twice changes
--     nothing more than applying it once. A step whose pick changes after
--     it was applied takes back only the values it wrote that still hold
--     them, so a change the player made since stays.
--   * A pick the player made on a step is theirs: the Welcome step's
--     profile choice only changes the suggestions of steps not touched yet.
--   * The last page lists only the parts that really changed.
--
-- For maintainers: the developer notes of the source repository describe
-- the steps, the STEP_OWNS table, the order Finish applies in, the session
-- state, previews, combat rules and how to add a step, and the placement
-- and preset rules the steps follow.
local _, E = ...
local ReadAccountRoot = E.ReadAccountRoot
local L = E.L

local Key = E.Key
local PROFILE = "EldoUI 1440p"
local SIDEBAR = 200
local CONTENT_W = 832          -- width of a step page
-- The footer's primary button, by Installer.PrimaryAction (label, tooltip),
-- kept English and shown as L[text]: L["Customize"], L["Start"],
-- L["Apply and continue"], L["Next"], L["Finish"], L["Close"], L["Attach"].
local PRIMARY_LABELS = { customize = "Customize", start = "Start", apply = "Apply and continue", next = "Next", finish = "Finish", close = "Close",
	attach = "Attach" }
local PRIMARY_TIPS = {
	customize = Key("Goes through the steps with the picked pack filled in; change anything on the way."),
	start = Key("Goes on to the first step."),
	apply = Key("Applies this step's pick and goes on to the next step. It also keeps the previews you picked on the steps before."),
	next = Key("Goes on to the next step."),
	finish = Key("Applies every pick you haven't applied yet and shows what changed."),
	close = Key("The setup is done. Closes this page and asks for a reload only if a change needs one."),
	attach = Key("Puts this character on the profile you picked, as it is, and sets up the parts checked under This character gets. A backup is kept first, and Undo puts everything back."),
}
local WIDTH = CONTENT_W + SIDEBAR + 48
local HEIGHT = 660

local Kit = E.WindowKit
local Installer = {}
E.Installer = Installer -- for plugins

local window
local session      -- choices of the current run, see NewSession
local current = 1  -- index of the shown step
local steps = {}   -- ordered step definitions of this run (base steps, pages, finish)
local finishing = false
-- The loading screen: from login (and from each later loading screen)
-- until the frame after PLAYER_ENTERING_WORLD. The game closes every
-- window when the world shows (CloseAllWindows), so the installer opens
-- after that, and a window it closes then comes back on the same step.
-- The loading screen: world (it shows now), open (a first-run open waits
-- for it), reopen (it closed an open run). A cinematic counts as one too:
-- a new character's intro hides the whole UI and may close every window,
-- so a first-run open waits for its end and an open run comes back after
-- it (cinematic: "scene" for an in-game cinematic, "movie" for a movie).
-- wait: it waits for another addon's first-run window (Installer.RegisterWait).
local loading = { world = true, open = false, reopen = false, cinematic = false, wait = false }
-- Entry points that only this file calls.
local Entry = {}
local ChatAvailable -- the game's chat window functions are there (chat step)
local GAME_SETTINGS -- the game settings the "Game settings" step offers
local CloseDone     -- closes the last page after Finish

---------------------------------------------------------------------------
-- Small helpers (the parts come from E.WindowKit, Core/Skin.lua)
---------------------------------------------------------------------------
local Secondary, Paragraph, Tooltip, Button, Check, Choice =
	Kit.Secondary, Kit.Paragraph, Kit.Tooltip, Kit.Button, Kit.Check, Kit.Choice

local function Accent(alpha)
	local c = E.media.accentColor
	return c[1], c[2], c[3], alpha or 1
end

-- Words in texts: a name or command in the accent (E:Highlight), states in
-- the design tokens' good, warn, dim and secondary colors (DESIGN.md 1b).
local function HL(text) return E:Highlight(text) end

-- A text with highlighted words that is built once: written again when the
-- theme changes, so its highlights always use the accent in effect (a
-- layout preview or a full look changes it while the window is open).
-- `build` returns the text.
local function LiveText(fontString, build)
	local function Paint(fs) fs:SetText(build()) end
	Paint(fontString)
	E:RegisterThemed(fontString, Paint)
	return fontString
end
local function Tinted(token, text) return E:TokenHex(E.tokens.text[token]) .. tostring(text) .. "|r" end
local function Good(text) return Tinted("good", text) end
local function Warn(text) return Tinted("warn", text) end
local function Dim(text) return Tinted("dim", text) end
local function Muted(text) return Tinted("secondary", text) end

local function Installed()
	return EldoUIDB.installed and EldoUIDB.installed[E.charKey]
end

-- A character that finished (or skipped) the installer before, on a
-- profile that was set up. A fresh profile is a first run again.
local function IsRerun()
	return Installed() ~= nil and not E.db.needsSetup
end

-- The run in progress is kept in the saved data of the character, so
-- closing the window ("do later"), a reload or a logout never loses what
-- was picked and applied: the next open goes on with the same choices,
-- each step's "Applied" state and the list of what changed. Dropped when
-- the run is finished, skipped or undone.
local function StoredRuns()
	EldoUIDB.installerRun = type(EldoUIDB.installerRun) == "table" and EldoUIDB.installerRun or {}
	return EldoUIDB.installerRun
end

local function KeepRun(s)
	StoredRuns()[E.charKey] = s
end

local function ForgetRun()
	local runs = EldoUIDB.installerRun
	if type(runs) ~= "table" then return end
	runs[E.charKey] = nil
	if next(runs) == nil then EldoUIDB.installerRun = nil end
end

local StoredRun, Backup -- defined with the private profile safety helpers below

-- A scroll area for long step contents (layout cards, style rows, modules).
local function ScrollArea(parent)
	local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 0, 0)
	scroll:SetPoint("BOTTOMRIGHT", -22, 0)
	if scroll.ScrollBar then E:SkinScrollBar(scroll.ScrollBar) end
	local child = CreateFrame("Frame", nil, scroll)
	child:SetSize(CONTENT_W - 22, 10)
	scroll:SetScrollChild(child)
	return scroll, child
end
Installer.ScrollArea, Installer.CONTENT_W = ScrollArea, CONTENT_W

local function CopyValue(value)
	if type(value) == "table" then return CopyTable(value) end
	return value
end

-- Undo by value: target[key] goes back to `before` only where it still
-- holds `after`, the value the setup wrote. Tables are compared key by
-- key, so a part the player changed since keeps their value.
local function RestoreByValue(target, key, before, after)
	if type(target) ~= "table" then return end
	local now = target[key]
	if E.DeepEqual(now, after) then
		target[key] = CopyValue(before)
		return
	end
	if type(now) ~= "table" or type(after) ~= "table" then return end
	local keys = {}
	for sub in pairs(after) do keys[sub] = true end
	if type(before) == "table" then
		for sub in pairs(before) do keys[sub] = true end
	end
	for sub in pairs(keys) do
		local old
		if type(before) == "table" then old = before[sub] end
		RestoreByValue(now, sub, old, after[sub])
	end
end
Installer.RestoreByValue = RestoreByValue

-- The player picked something on step `key` in this run: from now on the
-- pick is theirs, and a new profile choice on the Welcome step keeps it.
local function Touch(key)
	if not session then return end
	session.touched = session.touched or {}
	session.touched[key] = true
end
Installer.Touch = Touch

local function RefreshModule(module)
	if module and module.active and module.OnProfileChanged then
		E:RunOutOfCombat(function()
			local ok, err = pcall(module.OnProfileChanged, module)
			if not ok then geterrorhandler()(err) end
		end)
	end
end

---------------------------------------------------------------------------
-- Session: what the player picked in this run. Steps keep a state:
--   none     nothing picked or nothing to do
--   preview  shown for now, undone by Back or Cancel
--   applied  done for real
--   skipped  the player skipped the step
---------------------------------------------------------------------------
-- EldoUI is made for 1440p, so the suggestion is always "auto": the
-- 1440-unit canvas on every screen (Core/Scale.lua).
local function SuggestedScale()
	return "auto"
end

-- Modules the setup never offers: the player turns them on in their own
-- options page, never by a setup step or "Turn all on". NPC Dialog changes
-- how every quest and gossip NPC talks to you, so it is a choice of its own.
local NOT_IN_SETUP = { Dialogue = true }
Installer.notInSetup = NOT_IN_SETUP

-- Every module the setup offers and whether it is on now: the Modules
-- step starts there.
local function ModuleStates()
	local states = {}
	for name, module in E:IterateModules() do
		if not NOT_IN_SETUP[name] then states[name] = module:IsEnabled() and true or false end
	end
	return states
end

-- A profile that exists and went through the setup (or was skipped).
local function ProfileSetUp(name)
	local profile = EldoUIDB.profiles[name]
	return type(profile) == "table" and not profile.needsSetup
end

-- The shared EldoUI profile is set up and this character doesn't use it
-- yet (an alt): the Welcome step offers to use it as it is.
local function SharedProfileReady()
	return E.profileName ~= PROFILE and ProfileSetUp(PROFILE)
end

-- The other characters on profile `name`, for the texts ("" when none).
local function OtherUsers(name)
	local list = {}
	for _, char in ipairs(E:ProfileUsers(name)) do
		if char ~= E.charKey then list[#list + 1] = char end
	end
	return table.concat(list, ", "), #list
end

-- The Convenience step's rows a first run starts with ticked (and Express
-- turns on): repairs, selling gray items and faster auto loot.
Installer.convenienceFirstRun = { "repair", "sellJunk", "fastLoot" }

-- Alt safety: when the run writes into a profile that is already set up,
-- the steps that change the whole profile (scale, layout, role, Blizzard
-- UI, convenience) start on "keep"; the per-character steps (chat tabs,
-- other addons, click-casting) keep their suggestions. `keep` false puts
-- the first-run suggestions back. A step the player already picked
-- something on (session.touched) keeps that pick either way.
local function SetProfilePicks(s, keep)
	local suggested = s.suggested
	if not suggested then return end
	local touched = s.touched or {}
	s.picksKept = keep and true or false
	if not touched.scale then s.scale.choice = not keep and suggested.scale or nil end
	if not touched.layout then s.layout.key = not keep and suggested.layout or nil end
	if not touched.role then
		s.role.choice = not keep and suggested.role or nil
		if keep then
			s.role.classLayer = E.db.general.roleClass and true or false
		else
			s.role.classLayer = suggested.classLayer
		end
	end
	if not touched.blizzard then s.blizzard.mode = keep and "keep" or suggested.blizzard end
	if not touched.convenience then
		for _, key in ipairs(Installer.convenienceFirstRun) do s.convenience[key] = not keep end
	end
end

-- Does the profile mode the player picked write into a set-up profile?
local function TargetSetUp(mode)
	if mode == "use" then return true end
	if mode == "current" then return ProfileSetUp(E.profileName) end
	return false
end

-- The Welcome step's pick changed (first run only): the profile-wide steps
-- follow whether the target profile is set up.
local function PickProfileMode(mode)
	if session.profile.mode == mode then return end
	session.profile.mode = mode
	if session.suggested and not session.profile.done then SetProfilePicks(session, TargetSetUp(mode)) end
end

local function NewSession()
	-- A first run starts with EldoUI's suggestions picked; a second run
	-- starts with "keep" everywhere, so clicking through changes nothing.
	local rerun = IsRerun()
	local firstRun = not rerun
	local detected = firstRun and E:DetectRole() or nil
	-- The profile the class profile rule gave a new character stays when it
	-- is set up: the shared profile is offered only when it is not.
	local mode = "current"
	if not rerun and not (E.IsClassProfile and E:IsClassProfile(E.profileName) and ProfileSetUp(E.profileName)) then
		mode = SharedProfileReady() and "use" or "new"
	end
	local s = {
		rerun = rerun,
		version = E.version,
		reached = 1,
		profile = { mode = mode, done = false, fresh = false, state = "none" },
		scale = { choice = firstRun and SuggestedScale() or nil, state = "none" },
		layout = { key = firstRun and (E.db.general.layout or E.defaults.general.layout) or nil, state = "none" },
		styles = { choices = {}, state = "none" },
		-- Role: detection only pre-selects (first run); click-casting is
		-- never ticked for the player.
		role = { choice = detected, classLayer = firstRun and E:GetRoleClassLayer() ~= nil or (E.db.general.roleClass and true or false),
			clickCast = false, picks = {}, state = "none" },
		modules = { states = ModuleStates(), state = "none" },
		-- Addons you already use: key "addon|job" -> "eldoui" or "keep";
		-- a job not listed keeps what is set. disabled: addons this run
		-- turned off (Revert this turns them back on).
		competitors = { picks = {}, disabled = {}, state = "none" },
		blizzard = { mode = firstRun and "recommended" or "keep", state = "none" },
		-- What this run changed, for "Revert this" on the last page.
		undo = { list = {}, groups = {} },
		finished = false,
		-- Chat windows are the character's own: suggested on every first run
		-- of a character, also on a profile set up before.
		chat = { mode = firstRun and ChatAvailable() and "tabs" or "keep", whispers = true, loot = true, channels = true,
			classColors = firstRun, fontSize = nil, state = "none" },
		-- Game settings: ticked on a first run (only the ones that would
		-- change something count), unticked on a second run.
		cvars = { picks = {}, state = "none" },
		-- place: the placement rows' ticks that differ from the switch (keep);
		-- guide: the leveling guide picked here (nil: keep the saved pick).
		addons = { selected = {}, place = {}, guide = nil, state = "none" },
		-- Accessibility only offers: nothing is ticked, on any run.
		access = { picks = {}, state = "none" },
		-- Controller: Keep is picked, on any run.
		controller = { choice = nil, state = "none" },
		-- First run: repairs, selling gray items and faster auto loot are
		-- ticked, and the step says so (design decision: Express setup turns
		-- on the same three); every other helper starts unticked. Repairs
		-- pay from the player's own gold; the guild bank is a choice they
		-- make. A second run starts unticked, so clicking through changes
		-- nothing.
		convenience = { repair = firstRun, repairMode = "personal", sellJunk = firstRun, fastLoot = firstRun, state = "none" },
		-- Steps the player picked something on in this run (Touch).
		touched = {},
		-- The preset pack picked on the Welcome step (Express and Customize).
		pack = E.packOrder and E.packOrder[1] or nil,
		finish = { state = "none" },
		needsReload = false,
	}
	if firstRun then
		for _, info in ipairs(GAME_SETTINGS) do s.cvars.picks[info.key] = true end
		-- EldoUI is the recommended pick for every job another addon does.
		for _, row in ipairs(Installer.Competitors and Installer.Competitors.Rows() or {}) do s.competitors.picks[row.key] = "eldoui" end
		for _, name in ipairs(E.addonSetupOrder) do
			-- A setup marked preselect = false waits for the player's own tick.
			if E:GetAddonSetupStatus(name) == "ready" and E.addonSetups[name].preselect ~= false then s.addons.selected[name] = true end
		end
		s.suggested = { scale = s.scale.choice, layout = s.layout.key, role = s.role.choice, classLayer = s.role.classLayer, blizzard = s.blizzard.mode }
		if TargetSetUp(mode) then SetProfilePicks(s, true) end
	end
	for _, step in ipairs(steps) do
		if not s[step.key] then s[step.key] = { state = "none" } end
	end
	return s
end

---------------------------------------------------------------------------
-- A question inside the window: the dialog shell, centered over a shade
-- on the window. Also shows the "?" help of a step. Escape closes it
-- like Cancel. buttons: { { label, onClick }, ... }; title (optional).
---------------------------------------------------------------------------
local confirm

local function Confirm(text, buttons, title)
	if not confirm then
		confirm = CreateFrame("Frame", nil, window)
		confirm:SetAllPoints(window)
		confirm:SetFrameLevel(window:GetFrameLevel() + 50)
		confirm:EnableMouse(true)
		local shade = confirm:CreateTexture(nil, "BACKGROUND")
		shade:SetAllPoints()
		shade:SetColorTexture(unpack(E.tokens.shade))
		confirm.box = E.UIKit.CreateDialog("EldoUIInstallerQuestion", { width = 520 })
		confirm.box:HookScript("OnHide", function() confirm:Hide() end)
		confirm:SetScript("OnHide", function() confirm.box:Hide() end)
		confirm.text = confirm.box.text
		confirm.buttons = confirm.box.buttons
	end
	local list = {}
	for index, info in ipairs(buttons) do list[index] = { label = info[1], onClick = info[2] } end
	confirm.box.title:SetText(title or L["EldoUI setup"])
	confirm.box.text:SetText(text)
	confirm.box:SetButtons(list)
	confirm:Show()
	confirm.box:Show()
end
Installer.Confirm = Confirm

-- Click button `index` of the open question (for plugins).
function Installer.AnswerConfirm(index)
	if not (confirm and confirm:IsShown()) then return false end
	local button = confirm.buttons[index or 1]
	if not (button and button:IsShown()) then return false end
	button:GetScript("OnClick")(button)
	return true
end

---------------------------------------------------------------------------
-- Profile safety: one backup per character, taken before the first change
-- of a run, and the undo that puts it back.
---------------------------------------------------------------------------
local Work = {}
do
-- The budget only stops runaway data: a profile with every layout and
-- style applied, and a kept run's list of changes, hold tens of thousands
-- of values each.
local function InstallData(value)
	local budget, visiting = 1000000, {}
	local function Visit(item, depth)
		budget = budget - 1
		if budget < 0 or E.Secret(item) then return false end
		local kind = type(item)
		if kind == "nil" or kind == "string" or kind == "boolean" then return true end
		if kind == "number" then return item == item and item > -math.huge and item < math.huge end
		if kind ~= "table" or depth > 64 or getmetatable(item) ~= nil or visiting[item] then return false end
		visiting[item] = true
		for key, child in next, item do
			if type(key) == "table" or not Visit(key, depth + 1) or not Visit(child, depth + 1) then return false end
		end
		visiting[item] = nil
		return true
	end
	return Visit(value, 0)
end

local function InstallTarget(expected)
	local root, profile, name = ReadAccountRoot(), E.db, E.profileName
	local character = E.charKey
	local admit, getter, active = E.IsCurrentProfile, E.GetApplyGeneration, E.IsApplyGenerationCurrent
	if E.Secret(root) or type(root) ~= "table" or E.Secret(profile) or type(profile) ~= "table"
		or E.Secret(name) or type(name) ~= "string" or E.Secret(character) or type(character) ~= "string"
		or E.Secret(admit) or type(admit) ~= "function"
		or E.Secret(getter) or type(getter) ~= "function" or E.Secret(active) or type(active) ~= "function" then return nil end
	if expected and (root ~= expected.root or profile ~= expected.profile or name ~= expected.name
		or character ~= expected.character or admit ~= expected.admit or getter ~= expected.getter
		or active ~= expected.active) then return nil end
	local read, generation = pcall(getter, E, "profile")
	if not read or E.Secret(generation) or type(generation) ~= "number" or generation < 1
		or generation >= math.huge or generation % 1 ~= 0
		or (expected and generation ~= expected.generation) then return nil end
	local ok, admittedNow = pcall(admit, E, profile, name)
	local checked, live = pcall(active, E, generation, "profile")
	if not ok or E.Secret(admittedNow) or admittedNow ~= true or not checked or E.Secret(live) or live ~= true
		or E.IsCurrentProfile ~= admit or E.GetApplyGeneration ~= getter or E.IsApplyGenerationCurrent ~= active
		or ReadAccountRoot() ~= root or E.db ~= profile or E.profileName ~= name or E.charKey ~= character then return nil end
	return expected or { root = root, profile = profile, name = name, character = character,
		admit = admit, getter = getter, active = active, generation = generation }
end
Work.ProfileTarget = InstallTarget

-- The kept run, when it still fits: same EldoUI version, same kind of run
-- (first or second), and the profile it writes into is still in use.
StoredRun = function()
	local context = InstallTarget()
	if not context then return nil end
	local function Plain(value)
		return not E.Secret(value) and type(value) == "table" and getmetatable(value) == nil
	end
	local function Same(owner, key, value)
		local currentValue = rawget(owner, key)
		return not E.Secret(currentValue) and currentValue == value
	end
	local root = context.root
	local runs = rawget(root, "installerRun")
	if not Plain(runs) then return nil end
	local s = rawget(runs, context.character)
	if not Plain(s) then return nil end
	local profile = rawget(s, "profile")
	if not Plain(profile) or not InstallData(profile) then return nil end
	local version, rerun, finished = rawget(s, "version"), rawget(s, "rerun"), rawget(s, "finished")
	local done, name = rawget(profile, "done"), rawget(s, "profileName")
	local installed, needsSetup = rawget(root, "installed"), rawget(context.profile, "needsSetup")
	if E.Secret(version) or type(version) ~= "string" or E.Secret(rerun) or type(rerun) ~= "boolean"
		or E.Secret(finished) or (finished ~= nil and type(finished) ~= "boolean")
		or E.Secret(done) or (done ~= nil and type(done) ~= "boolean")
		or E.Secret(name) or (name ~= nil and type(name) ~= "string")
		or E.Secret(needsSetup) or (needsSetup ~= nil and type(needsSetup) ~= "boolean")
		or E.Secret(installed) or (installed ~= nil and not Plain(installed)) then return nil end
	local installedHere = installed and rawget(installed, context.character)
	if E.Secret(installedHere) then return nil end
	local ownVersion = E.version
	if E.Secret(ownVersion) or type(ownVersion) ~= "string" then return nil end
	local undo = rawget(s, "undo")
	if E.Secret(undo) or (undo ~= nil and not Plain(undo)) then return nil end
	local groups = undo and rawget(undo, "groups")
	if E.Secret(groups) or (groups ~= nil and not Plain(groups)) then return nil end
	-- Only the groups are authoritative. The saved list is derived and may
	-- have lost its aliases during serialization; never edit a malformed map.
	if not InstallData(groups) then return nil end
	local list, bindings = {}, {}
	for key, group in next, groups or {} do
		if type(key) ~= "string" or not Plain(group) then return nil end
		local order, parts, partOrder, texts = rawget(group, "order"), rawget(group, "parts"), rawget(group, "partOrder"), rawget(group, "texts")
		if rawget(group, "key") ~= key or type(rawget(group, "title")) ~= "string"
			or (order ~= nil and (type(order) ~= "number" or order ~= order or order <= -math.huge or order >= math.huge))
			or not Plain(parts) or not Plain(partOrder) or (texts ~= nil and not Plain(texts)) then return nil end
		for _, field in ipairs({ "reverted", "failed" }) do
			local value = rawget(group, field)
			if value ~= nil and type(value) ~= "boolean" then return nil end
		end
		if rawget(group, "note") ~= nil and type(rawget(group, "note")) ~= "string" then return nil end
		local count, seen = 0, {}
		for index, part in next, partOrder do
			if type(index) ~= "number" or index < 1 or index % 1 ~= 0 or type(part) ~= "string" or seen[part] then return nil end
			count = count + 1
			seen[part] = true
		end
		for index = 1, count do if rawget(partOrder, index) == nil then return nil end end
		for part in next, parts do if type(part) ~= "string" then return nil end end
		for step, text in next, texts or {} do
			if type(step) ~= "string" or type(text) ~= "string" then return nil end
		end
		list[#list + 1] = group
		bindings[key] = { group = group, order = order, title = rawget(group, "title"), parts = parts,
			partOrder = partOrder, texts = texts, note = rawget(group, "note"),
			reverted = rawget(group, "reverted"), failed = rawget(group, "failed") }
	end
	-- No saved-data writes until the actual profile owner and source entry
	-- have survived its callbacks. A changed group is never normalized here.
	if not InstallTarget(context) or E.Secret(E.version) or E.version ~= ownVersion or not Same(root, "installerRun", runs)
		or not Same(runs, context.character, s) or not Same(s, "profile", profile)
		or not Same(s, "version", version) or not Same(s, "rerun", rerun) or not Same(s, "finished", finished)
		or not Same(profile, "done", done) or not Same(s, "profileName", name)
		or not Same(root, "installed", installed) or not Same(context.profile, "needsSetup", needsSetup)
		or (installed and (not Plain(installed) or not Same(installed, context.character, installedHere)))
		or not Same(s, "undo", undo) or (undo and not Same(undo, "groups", groups))
		or not Plain(s) or not Plain(profile) or not Plain(runs) or (undo and not Plain(undo))
		or not InstallData(profile) or not InstallData(groups) then return nil end
	local count = 0
	for key, group in next, groups or {} do
		local saved = bindings[key]
		if not saved or group ~= saved.group or not Same(group, "key", key) or not Same(group, "order", saved.order)
			or not Same(group, "title", saved.title) or not Same(group, "parts", saved.parts)
			or not Same(group, "partOrder", saved.partOrder) or not Same(group, "texts", saved.texts)
			or not Same(group, "note", saved.note) or not Same(group, "reverted", saved.reverted)
			or not Same(group, "failed", saved.failed) then return nil end
		count = count + 1
	end
	if count ~= #list then return nil end
	if version ~= ownVersion or finished or rerun ~= IsRerun() or (done and name ~= context.name) then
		ForgetRun()
		return nil
	end
	table.sort(list, function(a, b)
		local left, right = a.order or 0, b.order or 0
		if left == right then return a.key < b.key end
		return left < right
	end)
	undo = undo or {}
	undo.groups, undo.list = groups or {}, list
	s.undo = undo
	return s
end


-- Forget drops the character's setup backup (a whole profile copy).
E:RegisterCharacterForget(function(db, key)
	local backups = rawget(db, "installerBackup")
	if type(backups) == "table" then backups[key] = nil end
end)

local function Backups(create)
	if not InstallTarget() then return nil end
	local backups = rawget(EldoUIDB, "installerBackup")
	if type(backups) == "nil" and create then backups = {}; EldoUIDB.installerBackup = backups end
	if not E.Secret(backups) and type(backups) == "table" and getmetatable(backups) == nil then return backups end
end

-- A refused copy is different from a profile that did not exist. Keep the
-- source and its database generation current until the backup is published.
local function CopyInstallProfile(context, name, allowMissing)
	local profiles = rawget(context.root, "profiles")
	local copy, compact, supported, detach = E.CopyProfileTable, E.CompactProfile, E.IsSupportedProfileData, CopyTable
	if E.Secret(profiles) or type(profiles) ~= "table" or getmetatable(profiles) ~= nil
		or E.Secret(copy) or type(copy) ~= "function" or E.Secret(compact) or type(compact) ~= "function"
		or E.Secret(supported) or type(supported) ~= "function" or E.Secret(detach) or type(detach) ~= "function" then return nil end
	local source = rawget(profiles, name)
	if E.Secret(source) then return nil end
	local function Current()
		local currentProfiles, currentSource = rawget(context.root, "profiles"), rawget(profiles, name)
		return not E.Secret(E.CopyProfileTable) and E.CopyProfileTable == copy
			and not E.Secret(E.CompactProfile) and E.CompactProfile == compact
			and not E.Secret(E.IsSupportedProfileData) and E.IsSupportedProfileData == supported
			and not E.Secret(CopyTable) and CopyTable == detach
			and not E.Secret(currentProfiles) and currentProfiles == profiles
			and not E.Secret(currentSource) and currentSource == source and InstallTarget(context)
	end
	if not Current() then return nil end
	if source == nil then
		if allowMissing then return false, Current end
		return nil
	end
	if type(source) ~= "table" or getmetatable(source) ~= nil then return nil end
	local copied, data = pcall(copy, E, name)
	if not copied or not Current() or type(data) ~= "table" or not InstallData(data) then return nil end
	-- A producer can hand back a source table or shared nested values. Compact
	-- only our own detached copy so a backup never trims the live profile.
	local detached, privateData = pcall(detach, data)
	if not detached or not Current() or privateData == data or not InstallData(privateData) then return nil end
	data = privateData
	local compacted = pcall(compact, E, data)
	if not compacted or not Current() or not InstallData(data) then return nil end
	local checked, allowed = pcall(supported, E, data)
	if not checked or E.Secret(allowed) or allowed ~= true or not Current() then return nil end
	return data, Current
end

-- `target`: the profile the run writes into; `previous`: the profile the
-- character used before (the run may switch to a new one).
Backup = function(target, previous)
	local context = InstallTarget()
	if not context or E.Secret(target) or type(target) ~= "string" or target == "" or E.Secret(previous)
		or (type(previous) ~= "nil" and type(previous) ~= "string") then return false end
	local data, isCurrent = CopyInstallProfile(context, target, true)
	if data == nil then return false end
	local at = time()
	if E.Secret(at) or type(at) ~= "number" or at < 0 or at >= math.huge or at ~= at or not isCurrent() then return false end
	local backups = Backups(true)
	if not backups or not isCurrent() then return false end
	backups[E.charKey] = { profile = target, previous = previous, data = data, time = at, version = E.version,
		profileBaseline = E.PROFILE_BASELINE }
	return true
end
Installer.Backup = Backup

-- Addons the setup turned off at Finish: kept with this character's
-- backup, so Undo the setup turns them on again, after a reload too.
-- `title` is the addon's own title, for the question. Revert this on the
-- last page clears them again (`addon` nil clears the whole list).
function Installer.NoteAddonOff(addon, title)
	local backups = Backups()
	local backup = backups and rawget(backups, E.charKey)
	if E.Secret(backup) or type(backup) ~= "table" or E.Secret(addon) then return false end
	if addon == nil then
		backup.addonsOff = nil
		return true
	end
	if type(addon) ~= "string" then return false end
	if type(backup.addonsOff) ~= "table" then backup.addonsOff = {} end
	backup.addonsOff[addon] = (not E.Secret(title) and type(title) == "string") and title or addon
	return true
end

function Installer.GetBackup()
	local context = InstallTarget()
	if not context then return nil end
	local backups = Backups()
	local backup = backups and rawget(backups, E.charKey)
	if type(backup) ~= "table" or not InstallData(backup)
		or rawget(backup, "profileBaseline") ~= E.PROFILE_BASELINE then return nil end
	local profile, previous, data = rawget(backup, "profile"), rawget(backup, "previous"), rawget(backup, "data")
	if E.Secret(profile) or type(profile) ~= "string" or profile == "" or E.Secret(previous)
		or (type(previous) ~= "nil" and (type(previous) ~= "string" or previous == "")) then return nil end
	for _, key in ipairs({ "attach", "copy" }) do
		local value = rawget(backup, key)
		if type(value) ~= "nil" and type(value) ~= "boolean" then return nil end
	end
	local at = rawget(backup, "time")
	if type(at) ~= "nil" and (type(at) ~= "number" or at < 0) then return nil end
	if data ~= false then
		local supported = E.IsSupportedProfileData
		if E.Secret(supported) or type(supported) ~= "function" then return nil end
		local ok, allowed = pcall(supported, E, data)
		if not ok or E.Secret(allowed) or allowed ~= true or E.IsSupportedProfileData ~= supported then return nil end
	end
	if not InstallTarget(context) then return nil end
	return backup
end

-- "Back up my setup" (Welcome step): a named copy of the profile in use,
-- listed with the other profiles. Returns the new profile's name.
function Installer.BackupProfile()
	local context, run = InstallTarget(), session
	if not context then return nil end
	local data, isCurrent = CopyInstallProfile(context, context.name, false)
	if not data then return nil end
	local base = L["%s backup %s"]:format(context.name, date("%Y-%m-%d"))
	if not isCurrent() or session ~= run then return nil end
	local profiles = rawget(context.root, "profiles")
	local name, count = base, 1
	while rawget(profiles, name) do
		count = count + 1
		name = ("%s (%d)"):format(base, count)
	end
	if not isCurrent() or session ~= run then return nil end
	profiles[name] = data
	if run then run.backedUp = name end
	return name
end

-- Put the profile back as it was before the last setup, and switch to the
-- profile the character used then. Asks first; waits for the end of combat.
function E:UndoInstall(skipConfirm)
	local target = InstallTarget()
	local readBackup = Installer.GetBackup
	if E.Secret(readBackup) or type(readBackup) ~= "function" then return false end
	local backup = readBackup()
	if not target or not backup then
		self:Print(L["There is no setup to undo on this character."])
		return false
	end
	local backups, loader, equal = Backups(), self.LoadDatabase, self.DeepEqual
	local switch, reset, delete, alt = self.SetProfile, self.ResetProfile, self.DeleteProfile, self.InstallerAlt
	if E.Secret(alt) or (type(alt) ~= "nil" and (type(alt) ~= "table" or getmetatable(alt) ~= nil)) then return false end
	local undoAttach = alt and alt.UndoAttach
	if E.Secret(loader) or type(loader) ~= "function" or E.Secret(equal) or type(equal) ~= "function"
		or E.Secret(switch) or type(switch) ~= "function" or E.Secret(reset) or type(reset) ~= "function"
		or E.Secret(delete) or type(delete) ~= "function" then return false end
	local snapshot = CopyTable(backup)
	-- Deleting the profile the setup made also drops its backup (the
	-- profile owner clears every reference to a deleted profile), so from
	-- then on the backup is gone on purpose.
	local released = false
	local function Current()
		local kept = not released and backup or nil
		if not (InstallTarget(target) and self.LoadDatabase == loader and Backups() == backups
			and rawget(backups, self.charKey) == kept and Installer.GetBackup == readBackup
			and not E.Secret(self.Installer) and self.Installer == Installer and readBackup() == kept
			and self.SetProfile == switch and self.ResetProfile == reset and self.DeleteProfile == delete
			and not E.Secret(self.InstallerAlt) and self.InstallerAlt == alt and (not alt or alt.UndoAttach == undoAttach)
			and self.DeepEqual == equal) then return false end
		if released then return InstallTarget(target) and true or false end
		local ok, same = pcall(equal, backup, snapshot)
		return ok and not E.Secret(same) and same == true and InstallTarget(target)
	end
	local function Adopt(name)
		if E.Secret(self.IsCurrentProfile) or E.Secret(self.GetApplyGeneration) or E.Secret(self.IsApplyGenerationCurrent)
			or self.IsCurrentProfile ~= target.admit or self.GetApplyGeneration ~= target.getter
			or self.IsApplyGenerationCurrent ~= target.active then return false end
		local rebound = InstallTarget()
		if not rebound or rebound.root ~= target.root or rebound.character ~= target.character or rebound.name ~= name
			or rebound.admit ~= target.admit or rebound.getter ~= target.getter or rebound.active ~= target.active then return false end
		target = rebound
		return Current()
	end
	local function Undo()
		if not Current() then return false end
		local completed = false
		local pending = self:PendingOutOfCombat("installer-undo")
		local ran = self:RunOutOfCombat(function()
			if not Current() then return end
			local name
			if backup.attach and self.InstallerAlt then
				-- An alt attached to a profile changed nothing in it: the
				-- character goes back to the profile it used before, and its
				-- own parts go back too (Core/InstallerAlt.lua).
				if E.Secret(undoAttach) or type(undoAttach) ~= "function" then return end
				name = undoAttach(backup)
			else
				local profiles, before = target.root.profiles, target.root.profiles[backup.profile]
				name = backup.previous or backup.profile
				if not profiles[name] then name = backup.profile end
				if backup.data then
					local copied = CopyTable(backup.data)
					if not Current() then return end
					profiles[backup.profile] = copied
					-- Replacing the active slot invalidates the old runtime binding.
					-- The database owner must admit it before a normal profile switch.
					local installed = profiles[backup.profile]
					local expectedActive = backup.profile == target.name and installed or target.profile
					local ok, loaded = pcall(loader, self)
					if not ok or loaded ~= true or ReadAccountRoot() ~= target.root
						or self.LoadDatabase ~= loader or target.root.profiles ~= profiles
						or self.charKey ~= target.character or self.profileName ~= target.name
						or (expectedActive ~= nil and self.db ~= expectedActive) or not self:IsCurrentProfile() then
						if ReadAccountRoot() == target.root and target.root.profiles == profiles
							and profiles[backup.profile] == installed and self.LoadDatabase == loader
							and self.charKey == target.character and self.profileName == target.name
							and target.root.profileKeys[target.character] == target.name then
							profiles[backup.profile] = before
							pcall(loader, self)
						end
						return
					end
					if not Adopt(target.name) or switch(self, name, true) ~= true then return end
				else
					-- Leave a newly created profile while it is still admitted,
					-- then let the profile owner delete it. A loader cannot admit
					-- an account whose active binding points to a deleted slot.
					if self.SetProfile ~= switch or switch(self, name, true) ~= true then return end
					if not Adopt(name) then return end
					if name == backup.profile then
						if self.ResetProfile ~= reset or reset(self) ~= true then return end
					elseif profiles[backup.profile] then
						if self.DeleteProfile ~= delete then return end
						released = true
						if delete(self, backup.profile) ~= true then return end
					end
				end
			end
			if ReadAccountRoot() ~= target.root or self.LoadDatabase ~= loader
				or self.profileName ~= name or not self:IsCurrentProfile() then return end
			if not Adopt(name) then return end
			self:UpdateAccent()
			if not Current() then return end
			self:ApplyScale()
			if not Current() then return end
			if self.RefreshTheme then self:RefreshTheme() end
			if not Current() then return end
			if window and window:IsShown() then
				finishing = true
				window:Hide()
				finishing = false
			end
			if not Current() then return end
			session = nil
			ForgetRun()
			backups[self.charKey] = nil
			completed = true
			-- The addons the setup turned off are on again from the reload.
			for addon in pairs(type(snapshot.addonsOff) == "table" and snapshot.addonsOff or {}) do
				if self.TurnCompetitorBackOn then
					local ok, err = pcall(self.TurnCompetitorBackOn, self, addon)
					if not ok then geterrorhandler()(err) end
				end
			end
			if backup.attach then
				self:ShowReloadPrompt(L["This character uses profile %s again, as before the alt setup. Reload to finish?"]:format(HL(name)))
			else
				self:ShowReloadPrompt(L["Profile %s is back as it was before the setup. Reload to finish?"]:format(HL(name)))
			end
		end, "installer-undo")
		-- In combat it waits; say so, and a second undo replaces the first.
		if not ran and not pending then self:Print(L["The undo runs when combat ends."]) end
		return not ran or completed
	end
	if skipConfirm then
		return Undo()
	end
	local when = backup.time and E:ShortDate(backup.time) or "?"
	local text = L["Profile %s goes back to how it was before the setup of %s, and this character uses %s again. Chat tabs and other addons' profiles stay as they are."]:format(
		HL(backup.profile), when, HL(backup.previous or backup.profile))
	if backup.attach then
		text = L["This character goes back to profile %s, as before the alt setup of %s, and its chat tabs, game settings, click-casting and class spells go back too. Profile %s stays as it is, and other addons' profiles stay as they are."]:format(
			HL(backup.previous or backup.profile), when, HL(backup.profile))
		if backup.copy then
			text = L["This character goes back to profile %s, as before the alt setup of %s, and its chat tabs, game settings, click-casting and class spells go back too. The copy %s made for it is deleted, and other addons' profiles stay as they are."]:format(
				HL(backup.previous or backup.profile), when, HL(backup.profile))
		end
	end
	local addonsOff = {}
	for _, title in pairs(type(backup.addonsOff) == "table" and backup.addonsOff or {}) do
		addonsOff[#addonsOff + 1] = tostring(title)
	end
	if #addonsOff > 0 then
		table.sort(addonsOff)
		text = text .. "\n\n" .. L["The addons the setup turned off are turned on again: %s."]:format(table.concat(addonsOff, ", "))
	end
	self:ShowConfirm({
		title = L["Undo the setup?"],
		text = text,
		accept = L["Undo"], cancel = E:GameText(CANCEL, L["Cancel"]),
		onAccept = Undo,
	})
	return true
end

end -- private saved-run and profile safety helpers

---------------------------------------------------------------------------
-- Step: profile. Nothing else may be applied before the player said
-- which profile the setup writes into.
---------------------------------------------------------------------------
local function ProfileDone(onDone)
	session.profile.done = true
	session.profileName = E.profileName
	session.profile.state = "applied"
	if onDone then onDone() end
	Installer.Update()
end

-- Modules re-read their settings when the profile changes, which can move
-- protected frames, so the switch waits for the end of combat.
local function SwitchProfile(name, fresh, onDone)
	local run = session
	E:RunOutOfCombat(function()
		if session ~= run then return end
		Backup(name, E.profileName)
		E:SetProfile(name, true)
		if fresh then E:ResetProfile() end
		-- A fresh profile keeps EldoUI's chat and bars on screen meanwhile,
		-- and gets its layout's spots and bar shapes now, as at the first
		-- login: a pack on the same layout skips the preview, so the screen
		-- would otherwise wait for Finish.
		E:ApplyFreshLayout()
		E:UpdateAccent()
		E:ApplyScale()
		if E.RefreshTheme then E:RefreshTheme() end
		session.profile.fresh = fresh and true or false
		session.needsReload = true
		-- Module states and the role follow the profile now in use.
		session.modules.states = ModuleStates()
		if not session.role.choice then session.role.classLayer = E.db.general.roleClass and true or false end
		E:Print(L["Setting up the profile %s."]:format(HL(name)))
		ProfileDone(onDone)
	end)
end
Installer.ProfileDone = ProfileDone

-- Run onDone once the profile question is answered (asks only once per run).
local function EnsureProfile(onDone)
	local p = session.profile
	if p.done then
		if onDone then onDone() end
		return
	end
	if p.mode == "use" and E.profileName ~= PROFILE then
		-- Alt safety: the shared profile as it is, nothing reset.
		SwitchProfile(PROFILE, false, onDone)
		return
	end
	if p.mode == "new" and E.profileName ~= PROFILE then
		if ProfileSetUp(PROFILE) then
			-- Set up, maybe by other characters: asked twice, naming them.
			local users, count = OtherUsers(PROFILE)
			local who = count > 0 and L["It is set up and used by %s."]:format(E:Highlight(users)) or L["It is already set up."]
			Confirm(L["The profile %s exists. %s Starting it fresh resets its layout, styles and settings for every character that uses it."]:format(E:Highlight(PROFILE), who), {
				{ L["Start fresh"], function()
					local whom = count > 0 and L["%s and this character"]:format(E:Highlight(users)) or L["this character"]
					Confirm(L["Really start %s fresh? It goes back to EldoUI's defaults for %s. A backup is kept, and the Welcome step can undo it on this character."]:format(E:Highlight(PROFILE), whom), {
						{ L["Start fresh"], function() SwitchProfile(PROFILE, true, onDone) end },
						{ E:GameText(CANCEL, L["Cancel"]) },
					})
				end },
				{ L["Use it as it is"], function()
					PickProfileMode("use")
					SwitchProfile(PROFILE, false, onDone)
				end },
				{ E:GameText(CANCEL, L["Cancel"]) },
			})
		else
			-- Missing, or made but never set up: nothing in it to lose.
			SwitchProfile(PROFILE, true, onDone)
		end
		return
	end
	if session.rerun or (p.mode == "new" and E.profileName == PROFILE) then
		Confirm(L["You set up EldoUI on this character before. Each step you apply now overwrites that part of your profile %s. A backup is kept: the Welcome step can undo it. Continue?"]:format(HL(E.profileName)), {
			{ L["Continue"], function()
				Backup(E.profileName, E.profileName)
				ProfileDone(onDone)
			end },
			{ E:GameText(CANCEL, L["Cancel"]) },
		})
		return
	end
	Backup(E.profileName, E.profileName)
	ProfileDone(onDone)
end
Installer.EnsureProfile = EnsureProfile

---------------------------------------------------------------------------
-- Step: UI scale
---------------------------------------------------------------------------
local function ScaleValue(choice)
	if choice == "auto" then return E:GetAutoScale() end
	if choice == "pixel" then return E:GetPixelPerfectScale() end
	return tonumber(choice) or E:GetTargetScale()
end

local function PreviewScale()
	local s = session.scale
	if s.choice == nil then return end
	if not s.snapshot then s.snapshot = { value = E.db.general.uiScale } end
	E.db.general.uiScale = s.choice
	E:ApplyScale()
	s.state = "preview"
end

local function RevertScale()
	local s = session.scale
	if s.snapshot then
		E.db.general.uiScale = s.snapshot.value
		E:ApplyScale()
		s.snapshot = nil
	end
	if s.state == "preview" then s.state = "none" end
end

-- What each step's Apply does (one table: a Lua chunk has room for 200 locals).

function Work.ApplyScaleStep()
	local s = session.scale
	if s.choice == nil then return end
	E.db.general.uiScale = s.choice
	E:ApplyScale()
	s.snapshot = nil
	s.state = "applied"
end

---------------------------------------------------------------------------
-- Step: layout. A preview applies the preset and remembers everything
-- E:ApplyLayout changes, so Back or Cancel can put it back.
---------------------------------------------------------------------------
local function SnapshotLayout()
	local general = E.db.general
	local snapshot = { layout = general.layout, accent = general.accent, movers = CopyTable(E.db.movers or {}), modules = {},
		hidden = CopyTable(general.layoutHidden or {}), pending = CopyTable(general.layoutPending or {}),
		roleMovers = CopyTable(general.roleMovers or {}) }
	local function Save(moduleName, setting)
		local module = E.modules[moduleName]
		if not (module and module.db) then return end
		local saved = snapshot.modules[moduleName] or {}
		snapshot.modules[moduleName] = saved
		if saved[setting] == nil then saved[setting] = { value = CopyValue(module.db[setting]) } end
	end
	-- Every layout, retired ones too, so a preview of any of them is taken back.
	for _, key in ipairs(E:AllLayoutKeys()) do
		local layout = E.layouts[key]
		for moduleName, settings in pairs(layout.modules or {}) do
			for setting in pairs(settings) do Save(moduleName, setting) end
		end
		-- Frames a layout switches off (or the previous one switched off).
		local names = CopyTable(layout.hidden or {})
		for name in pairs(general.layoutHidden or {}) do names[#names + 1] = name end
		for _, name in ipairs(names) do
			local mover = E.movers[name]
			if mover and mover.module and mover.enabledPath then Save(mover.module, mover.enabledPath[1]) end
		end
	end
	return snapshot
end

-- After a preset was applied: what it wrote into each kept module setting,
-- so taking it back is done by value (RestoreByValue).
local function SnapshotAfter(snapshot)
	if type(snapshot) ~= "table" then return end
	for moduleName, saved in pairs(snapshot.modules or {}) do
		local module = E.modules[moduleName]
		if module and module.db then
			for setting, entry in pairs(saved) do entry.after = CopyValue(module.db[setting]) end
		end
	end
	snapshot.applied = E.db.general.layout
end

local function RestoreLayout(snapshot)
	E:RunOutOfCombat(function()
		local general = E.db.general
		general.layout = snapshot.layout
		local accentChanged = general.accent ~= snapshot.accent
		general.accent = snapshot.accent
		general.layoutHidden = CopyTable(snapshot.hidden or {})
		general.layoutPending = CopyTable(snapshot.pending or {})
		-- A layout change clears the role's saved positions (Core/Roles.lua);
		-- a preview that is taken back puts them back.
		general.roleMovers = CopyTable(snapshot.roleMovers or {})
		E.db.movers = E.db.movers or {}
		wipe(E.db.movers)
		for name, point in pairs(snapshot.movers) do E.db.movers[name] = CopyTable(point) end
		E:UpdateAccent()
		for moduleName, saved in pairs(snapshot.modules) do
			local module = E.modules[moduleName]
			if module and module.db then
				for setting, entry in pairs(saved) do
					-- Only what the preset wrote and still holds goes back: a
					-- style or the player's own change since stays.
					if entry.after ~= nil or snapshot.applied then
						RestoreByValue(module.db, setting, entry.value, entry.after)
					else
						module.db[setting] = CopyValue(entry.value)
					end
				end
				RefreshModule(module)
			end
		end
		if accentChanged then E:RefreshTheme() end
		E:RefreshMovers()
	end)
end

local function RevertLayout()
	local l = session.layout
	if l.snapshot then
		RestoreLayout(l.snapshot)
		l.snapshot = nil
	end
	if l.state == "preview" then l.state = "none" end
end

local function PreviewLayout(key)
	local l = session.layout
	l.key = key
	if not key then
		RevertLayout()
		return
	end
	-- In combat the pick waits for Apply or Finish, like a layout click
	-- anywhere else. A preview queued for after combat would show up on
	-- whatever step is open by then, and Back could no longer undo it.
	if InCombatLockdown() then
		E:ConfigNotice(L["Layouts can't be changed in combat."], true)
		Installer.Update()
		return
	end
	E:RunOutOfCombat(function()
		-- Back to the state before any preview, then the new preset on top.
		-- The layout in use is not applied again: that would put back every
		-- frame the player dragged.
		local original = l.snapshot and l.snapshot.layout or E.db.general.layout
		if l.snapshot then RestoreLayout(l.snapshot) end
		if key == original then
			l.snapshot = nil
			if l.state == "preview" then l.state = "none" end
		else
			l.snapshot = l.snapshot or SnapshotLayout()
			if Installer.SetupLayout(key) then
				SnapshotAfter(l.snapshot)
				l.state = "preview"
				-- Styles applied before go on top of the new layout again.
				local styles = session.styles
				if next(styles.choices) then
					styles.reapply = true
					if styles.state == "applied" then styles.state = "none" end
				end
			end
		end
		Installer.Update()
	end)
end

Installer.PreviewLayout = PreviewLayout

-- The layout part of the setup goes through the one setup change
-- (E:ApplySetup, Core/Layout.lua) like every other route: frames the player
-- dragged stay, and the look is left to the Styles step. The setup keeps
-- its own record for Back, Cancel and Revert this.
function Installer.SetupLayout(key)
	return E:ApplySetup({ layout = key, look = "keep", source = "setup", silent = true, undo = false })
end

-- Repeat-safe: a preset that is already in use (shown as a preview, or
-- the profile's layout) is not applied again, so frames the player
-- dragged stay where they are. `kept` is what "Revert this" puts back.
function Work.ApplyLayoutStep(kept)
	local l = session.layout
	if not l.key then return end
	local key = l.key
	local run = session
	E:RunOutOfCombat(function()
		if E.db.general.layout == key then return end
		if Installer.SetupLayout(key) then
			SnapshotAfter(kept)
			-- Blizzard windows that follow the layout may need a reload to
			-- take a skin off: the installer ends with its own question.
			if E.BlizzardWindowsSummary and E:BlizzardWindowsSummary().reload then run.needsReload = true end
			E:HideReloadPrompt()
			-- A new layout puts every frame back in its place, so styles
			-- applied before it are applied again at Finish.
			local styles = run.styles
			if next(styles.choices) then
				styles.reapply = true
				if styles.state == "applied" then styles.state = "none" end
			end
		end
	end)
	l.snapshot = nil
	l.state = "applied"
end

---------------------------------------------------------------------------
-- Layout map: Core/InstallerMap.lua (Installer.LayoutMap and
-- Installer.DrawLayoutMap).
---------------------------------------------------------------------------

---------------------------------------------------------------------------
-- Step: styles
---------------------------------------------------------------------------
-- The parts of the UI players change most come first, the rest by title.
local STYLE_ORDER = { "UnitFrames", "ActionBars", "GroupFrames", "Nameplates", "Chat", "Minimap", "InfoBar", "Bags", "Tooltip" }

local function StyleCategories()
	local list, seen = {}, {}
	for _, name in ipairs(STYLE_ORDER) do
		if E.styles[name] and E.modules[name] then
			list[#list + 1] = name
			seen[name] = true
		end
	end
	local rest = {}
	for name in pairs(E.styles) do
		if not seen[name] and E.modules[name] then rest[#rest + 1] = name end
	end
	table.sort(rest, function(a, b) return E.modules[a].title < E.modules[b].title end)
	for _, name in ipairs(rest) do list[#list + 1] = name end
	return list
end

local function FindStyle(name, key)
	for _, style in ipairs(E.styles[name] or {}) do
		if style.key == key then return style end
	end
end

-- The style `layout` suggests for part `name`, when it exists, fits the
-- layout and doesn't act for the player.
local function LayoutSuggestion(layoutKey, name)
	local layout = layoutKey and E.layouts[layoutKey]
	local styleKey = layout and type(layout.suggest) == "table" and layout.suggest[name]
	local style = styleKey and FindStyle(name, styleKey)
	if style and not style.acts and E:StyleFits(layoutKey, name, styleKey) then return styleKey end
end

-- The layout picked on this run suggests styles (`suggest` in its preset,
-- one per part of the UI). They are preselected on the Styles step until
-- the player picks a style in that row; a run that keeps the layout
-- suggests nothing, so a second run changes nothing, unless a full look
-- or a pack was picked (it brings its layout's styles).
local function SuggestedStyle(name)
	local look = session and session.styles.look
	local layout = session and session.layout
	-- Picking the layout already in use keeps the player's current look.
	-- A changed layout, full look or pack still brings its suggestions.
	if session and (session.rerun or session.picksKept) and not (session.profile and session.profile.fresh) and not look and layout
		and not layout.snapshot and layout.state ~= "preview" and layout.state ~= "applied" then return nil end
	local key = session and (session.layout.key or (look and look.layout))
	return LayoutSuggestion(key, name)
end

local function SuggestStyles()
	local s = session and session.styles
	if not s then return end
	s.picked, s.auto = s.picked or {}, s.auto or {}
	for _, name in ipairs(StyleCategories()) do
		if not s.picked[name] then
			local suggested = SuggestedStyle(name)
			local before = s.choices[name]
			if suggested then
				s.choices[name], s.auto[name] = suggested, true
			elseif s.auto[name] then
				s.choices[name], s.auto[name] = nil, nil
			end
			if s.choices[name] ~= before and s.state == "applied" then s.state = "none" end
		end
	end
end

-- The styles a map of layout `layoutKey` is drawn with: the run's own picks,
-- else what the layout suggests.
local function MapStyles(layoutKey)
	local styles, s = {}, session and session.styles
	for _, name in ipairs(StyleCategories()) do
		local key
		if s and s.picked and s.picked[name] then key = s.choices[name] else key = LayoutSuggestion(layoutKey, name) end
		if key and E:StyleFits(layoutKey, name, key) then styles[name] = key end
	end
	return styles
end

-- The role this run ends with (the Role step's pick, else the profile's).
local function RunRole()
	local role = session and session.role.choice
	if role == nil then role = E.db.general.role end
	return role
end

-- Parts of a module whose size the role owns (the healer's group frames):
-- a style keeps only its look there.
local function RoleSizing(name)
	return E:RoleSizedParts(RunRole(), name)
end

---------------------------------------------------------------------------
-- Style previews: on the Styles step every pick shows on the live frames
-- at once. Each preview keeps what it changed (`before`) and what it wrote
-- (`after`), so Back, Esc and the close button take it back by value, and
-- "Revert this" and the last page compare with the settings from before
-- the preview. In combat a pick waits for Apply or Finish.
---------------------------------------------------------------------------
local Preview = {}

function Preview.Undo(name)
	local s = session.styles
	local preview = s.preview and s.preview[name]
	if not preview then return end
	s.preview[name] = nil
	local module = E.modules[name]
	if not (module and module.db) then return end
	for setting, before in pairs(preview.before) do RestoreByValue(module.db, setting, before.value, preview.after[setting]) end
	RefreshModule(module)
end

function Preview.Show(name, key)
	local s = session.styles
	s.preview = s.preview or {}
	local shown = s.preview[name]
	if (shown and shown.key) == key then return end
	Preview.Undo(name)
	local module = E.modules[name]
	local style = key and FindStyle(name, key)
	-- A style this run applied already is in place; Keep shows the frames as they are.
	if not (style and module and module.db) or (s.applied and s.applied[name] == key) then return end
	local sizedBy = RoleSizing(name)
	local before, after = { style = { value = CopyValue(module.db.style) } }, {}
	for setting in pairs(E:StyleSettings(style, sizedBy)) do before[setting] = { value = CopyValue(module.db[setting]) } end
	-- What the style sets back to the default is undone with it.
	for _, path in ipairs(E:StyleRestores(name, style, sizedBy)) do
		local setting = path:match("^[^%.]+")
		before[setting] = before[setting] or { value = CopyValue(module.db[setting]) }
	end
	if E:ApplyStyle(name, key, true, sizedBy) then
		for setting in pairs(before) do after[setting] = CopyValue(module.db[setting]) end
		s.preview[name] = { key = key, before = before, after = after }
	end
end

-- Make the previews match the picks (called while the Styles step shows).
function Preview.Sync()
	local s = session and session.styles
	if not s or InCombatLockdown() then return false end
	local changed = false
	for _, name in ipairs(StyleCategories()) do
		local key = s.choices[name] or nil
		local preview = s.preview and s.preview[name]
		local shown = preview and preview.key or nil
		local applied = s.applied and s.applied[name] or nil
		if shown ~= key and not (shown == nil and applied == key) then
			Preview.Show(name, key)
			changed = true
		end
	end
	if s.preview and next(s.preview) and s.state ~= "applied" then s.state = "preview" end
	return changed
end

function Preview.Revert()
	local s = session and session.styles
	if not (s and s.preview) then return end
	for name in pairs(s.preview) do Preview.Undo(name) end
	if s.state == "preview" then s.state = "none" end
end

-- The settings a module had before this run's preview (for "Revert this").
function Preview.Without(name, data)
	local preview = session and session.styles.preview and session.styles.preview[name]
	if not (preview and type(data) == "table") then return data end
	for setting, before in pairs(preview.before) do data[setting] = CopyValue(before.value) end
	return data
end

-- Styles merge on top of each part's settings. A style applied in this run
-- that the player picked away from (another style, or Keep) is taken back
-- by value first: what it wrote and still holds goes back to the value
-- from before the run (`kept`, PARTS.styles). Repeat-safe: a style already
-- applied in this run is not applied again, unless a new layout put the
-- frames back since (reapply). A previewed style becomes the applied one.
-- Where the role owns a part's size (the healer's group frames) the
-- style sets only its look.
function Work.ApplyStylesStep(kept)
	local s = session.styles
	s.applied = s.applied or {}
	for _, name in ipairs(StyleCategories()) do
		local key = s.choices[name] or nil
		local previous = s.applied[name]
		local module = E.modules[name]
		local preview = s.preview and s.preview[name]
		if preview and preview.key ~= key then Preview.Undo(name) end
		if previous and previous ~= key then
			local style = FindStyle(name, previous)
			local before = type(kept) == "table" and kept[name] or nil
			if style and module and module.db and type(before) == "table" then
				-- A part the style also set back to the default is compared
				-- with the whole part as the style left it.
				local written = s.written and s.written[name] or {}
				for setting, value in pairs(style.settings or {}) do
					if written[setting] == nil then RestoreByValue(module.db, setting, before[setting], value) end
				end
				for setting, value in pairs(written) do RestoreByValue(module.db, setting, before[setting], value) end
				RestoreByValue(module.db, "style", before.style, previous)
				RefreshModule(module)
			end
			s.applied[name] = nil
			if s.written then s.written[name] = nil end
		end
		if key and (key ~= previous or s.reapply) and E:ApplyStyle(name, key, true, RoleSizing(name)) then
			s.applied[name] = key
			-- The parts the style set back to the default, as it left them.
			local style, written = FindStyle(name, key), {}
			for _, path in ipairs(style and E:StyleRestores(name, style, RoleSizing(name)) or {}) do
				local setting = path:match("^[^%.]+")
				written[setting] = CopyValue(module.db[setting])
			end
			s.written = s.written or {}
			s.written[name] = next(written) and written or nil
		end
		if s.preview then s.preview[name] = nil end
	end
	s.reapply = nil
	s.state = "applied"
end

-- Something for the Styles step to do: a style picked, or one applied
-- earlier in this run that the player picked away from.
local function StylesHaveChoice()
	local s = session.styles
	if s.state == "preview" then return true end
	for name, key in pairs(s.choices) do
		if s.applied == nil or s.applied[name] ~= key or s.reapply then return true end
	end
	for name in pairs(s.applied or {}) do
		if s.choices[name] == nil then return true end
	end
	return false
end

---------------------------------------------------------------------------
-- Step: Blizzard UI
---------------------------------------------------------------------------
local BLIZZARD_MODES = {
	{ key = "keep", title = "Keep my switches", desc = "Leave the Blizzard UI switches as they are now." },
	{ key = "recommended", title = "Recommended", desc = "EldoUI changes what its modules are made for: its own frames replace Blizzard's, the windows it skins get the EldoUI look, and every Blizzard window can be dragged and scaled. Other switches you set stay." },
	{ key = "own", title = "Only EldoUI's own frames", desc = "EldoUI only hides the Blizzard frames its own frames replace and changes no other Blizzard window. Switches you set before stay." },
	{ key = "all", title = "Everything", desc = "Every Blizzard element an EldoUI module can change gets the EldoUI look, extra info and EldoUI movers, plus the recommended replacements. Switches you set before stay." },
	{ key = "blizzard", title = "Blizzard's own UI", desc = "EldoUI changes no Blizzard element. Blizzard's frames stay as Blizzard made them, and EldoUI's own frames for the same parts step aside, so nothing shows twice. Hidden Blizzard frames come back after the reload." },
}

-- What one element should look like for a mode; nil = leave it.
local function BlizzardTarget(id, mode)
	local data = E.blizzardElements[id]
	if not data or #data.handlers == 0 then return nil end
	local install = {}
	for _, handler in ipairs(data.handlers) do
		for action, on in pairs(handler.install or {}) do
			if on and data.allowed[action] then install[action] = true end
		end
	end
	local target = { enabled = false }
	for _, action in ipairs(data.actions) do target[action] = false end
	if mode == "own" then
		if install.replace or install.hide then
			target.enabled = true
			target.replace = install.replace or false
			target.hide = install.hide or false
		end
	elseif mode == "all" then
		target.enabled = true
		for action in pairs(install) do target[action] = true end
		for _, action in ipairs({ "skin", "move", "improve" }) do
			if data.allowed[action] then target[action] = true end
		end
	end
	return target
end

-- Put one element's switches toward `target`. Modes are deltas: an
-- element the target leaves off is left as it is, an element that is on
-- keeps every switch the player set and only gains what the target turns
-- on, and an element that is off is turned on with exactly the target's
-- switches. `exact` (Blizzard's own UI) sets the target as it is, which
-- is what that card says it does.
local function SetElement(id, target, exact)
	local state = E:BlizzardState(id)
	if not state then return end
	if exact then
		if state.enabled and not target.enabled then E:SetBlizzardElement(id, "enabled", false) end
		for key, value in pairs(target) do
			if key ~= "enabled" and (state[key] and true or false) ~= value then E:SetBlizzardElement(id, key, value) end
		end
		if target.enabled and not state.enabled then E:SetBlizzardElement(id, "enabled", true) end
		return
	end
	if not target.enabled then return end
	local wasOn = state.enabled and true or false
	for key, value in pairs(target) do
		if key ~= "enabled" then
			local on = state[key] and true or false
			if value and not on then
				E:SetBlizzardElement(id, key, true)
			elseif not value and on and not wasOn then
				E:SetBlizzardElement(id, key, false)
			end
		end
	end
	if not wasOn then E:SetBlizzardElement(id, "enabled", true) end
end

-- "Recommended" for one element: what its modules ask for, on top of the
-- switches as they are. An element that is on keeps every switch the
-- player set and only gains what is asked for; one that is off is turned
-- on with exactly what is asked for. nil = nothing asked, leave it.
local function RecommendedTarget(id)
	local data = E.blizzardElements[id]
	local state = E:BlizzardState(id)
	if not (data and state) then return nil end
	local target, asked = { enabled = true }, false
	for _, handler in ipairs(data.handlers or {}) do
		for action, on in pairs(handler.install or {}) do
			if data.allowed[action] then
				asked = true
				if on then
					target[action] = true
				elseif not state.enabled and target[action] == nil then
					target[action] = false
				end
			end
		end
	end
	if not asked then return nil end
	return target
end
Installer.RecommendedTarget = RecommendedTarget

-- "Recommended": what each module asks for, and every Blizzard window can
-- be dragged and scaled. Other switches stay as they are.
local function ApplyRecommendedBlizzard()
	for _, id in ipairs(E.blizzardElementOrder) do
		local target = RecommendedTarget(id)
		if target then SetElement(id, target) end
	end
	if E.AllowAllWindowMoves then
		E:AllowAllWindowMoves()
		if E.db.windowMover then E.db.windowMover.movesAllowed = true end
	end
end
Installer.ApplyRecommendedBlizzard = ApplyRecommendedBlizzard

-- What a mode changed: each switch as { id, key, from, to }, the "enabled"
-- switches last, so taking them back turns an element off first.
local function BlizzardChanges(before, after)
	local list, enabled = {}, {}
	for _, id in ipairs(E.blizzardElementOrder) do
		local old, new = before[id], after[id]
		if type(old) == "table" and type(new) == "table" then
			local keys = {}
			for key in pairs(old) do keys[key] = true end
			for key in pairs(new) do keys[key] = true end
			for key in pairs(keys) do
				local from, to = old[key] and true or false, new[key] and true or false
				if from ~= to then
					local entry = { id, key, from, to }
					if key == "enabled" then enabled[#enabled + 1] = entry else list[#list + 1] = entry end
				end
			end
		end
	end
	for _, entry in ipairs(enabled) do list[#list + 1] = entry end
	return list
end

-- Undo by value: the switches a mode applied earlier in this run go back,
-- each only while it still holds what the mode set.
local function UndoBlizzardMode(b)
	local changes = b.changes or {}
	for index = #changes, 1, -1 do
		local entry = changes[index]
		local state = E:BlizzardState(entry[1])
		if state and (state[entry[2]] and true or false) == entry[4] then E:SetBlizzardElement(entry[1], entry[2], entry[3]) end
	end
	local windows, mover = b.windows, E.db.windowMover
	if type(windows) == "table" and type(mover) == "table" then
		local keys = {}
		for key in pairs(windows.before or {}) do keys[key] = true end
		for key in pairs(windows.after or {}) do keys[key] = true end
		for key in pairs(keys) do RestoreByValue(mover, key, (windows.before or {})[key], (windows.after or {})[key]) end
		if E.SyncWindowSwitches then E:SyncWindowSwitches() end
		if E.WindowMoverApply then E:WindowMoverApply() end
	end
	b.changes, b.windows = nil, nil
end

-- Repeat-safe: the mode applied last in this run is not applied again. A
-- new pick first takes back what the old one set (by value), so going
-- from Everything to Recommended doesn't keep Everything's extras.
function Work.ApplyBlizzardStep()
	local b = session.blizzard
	local modeChanged = b.mode ~= (b.appliedMode or "keep")
	if not modeChanged and not Installer.WindowsChoiceChanged(b) then
		b.state = "applied"
		return
	end
	local mode, run, windows = b.mode, session, b.windowsMode
	b.appliedMode = mode
	E:RunOutOfCombat(function()
		if session ~= run then return end
		if modeChanged then Installer.ApplyBlizzardMode(b, mode) end
		-- The Blizzard windows choice: only the Skin switch of windows the
		-- player lets EldoUI change, recorded so it can be put back.
		if windows and E.SetBlizzardWindows then
			local _, needed = E:SetBlizzardWindows(windows, true)
			if needed then run.needsReload = true end
		end
		-- The installer ends with its own reload question.
		E:HideReloadPrompt()
	end)
	session.needsReload = true
	b.state = "applied"
end

-- Blizzard UI step: the Blizzard windows row, one small card per choice
-- (Keep as set, Follow layout, Original, Match skin) under the modes.
-- Its parts sit in the step's scroll area (frame.child).
function Installer.BuildWindowsRow(frame)
	local W = E.Appearance and E.Appearance.WINDOWS
	if not (W and E.SetBlizzardWindows) then return end
	local parent = frame.child
	frame.windowsLabel = E:CreateText(parent, E.tokens.size.body, "LEFT")
	frame.windowsLabel:SetText(L["Blizzard windows"])
	frame.windowsChoices = {}
	for _, key in ipairs(W.order) do
		local button = Choice(parent, 10, 24, L[W.titles[key]], nil, function()
			Touch("blizzard")
			session.blizzard.windowsMode = key
			if session.blizzard.state == "applied" then session.blizzard.state = "none" end
			Installer.Update()
		end)
		button.key = key
		Tooltip(button, L[W.titles[key]], L[W.descs[key]])
		frame.windowsChoices[#frame.windowsChoices + 1] = button
	end
	frame.windowsNote = Secondary(Paragraph(parent, E.tokens.size.label, L["How Blizzard's own windows look. Only windows EldoUI may change are touched; this never lets EldoUI change more."]))
end

-- Lays the row out from y down and returns where it ends.
function Installer.LayoutWindowsRow(frame, y)
	if not frame.windowsChoices then return y end
	local maxX = frame.child:GetWidth()
	local picked = session.blizzard.windowsMode or E:BlizzardWindowsMode()
	frame.windowsLabel:ClearAllPoints()
	frame.windowsLabel:SetPoint("TOPLEFT", 0, -y - 4)
	local labelWidth = math.max(170, math.ceil(frame.windowsLabel:GetStringWidth() or 0) + 12)
	local height = math.max(24, math.ceil(E.tokens.size.body * (E.TextScale and E:TextScale() or 1)) + 8)
	local x, rowY = labelWidth, y
	for _, button in ipairs(frame.windowsChoices) do
		local width = math.max(72, math.ceil(button.title:GetStringWidth()) + 20)
		button:SetSize(width, height)
		if x + width > maxX and x > labelWidth then
			x, rowY = labelWidth, rowY + height + 4
		end
		button:ClearAllPoints()
		button:SetPoint("TOPLEFT", x, -rowY)
		x = x + width + 4
		button:SetSelected(button.key == picked)
	end
	frame.windowsNote:ClearAllPoints()
	frame.windowsNote:SetPoint("TOPLEFT", labelWidth, -(rowY + height + 6))
	frame.windowsNote:SetWidth(maxX - labelWidth)
	return rowY + height + 6 + math.ceil(frame.windowsNote:GetStringHeight() or 0)
end

-- The windows choice of this run differs from the profile's.
function Installer.WindowsChoiceChanged(b)
	return b.windowsMode ~= nil and E.BlizzardWindowsMode ~= nil and b.windowsMode ~= E:BlizzardWindowsMode()
end

-- Switch Blizzard's elements to `mode`, after taking back what the mode
-- applied before in this run set (by value).
function Installer.ApplyBlizzardMode(b, mode)
	UndoBlizzardMode(b)
	if mode ~= "keep" then
		local before = { switches = E:SnapshotBlizzard(), windows = CopyTable(E.db.windowMover or {}) }
		if mode == "recommended" then
			ApplyRecommendedBlizzard()
		else
			for _, id in ipairs(E.blizzardElementOrder) do
				local target = BlizzardTarget(id, mode)
				if target then SetElement(id, target, mode == "blizzard") end
			end
		end
		b.changes = BlizzardChanges(before.switches, E:SnapshotBlizzard())
		local windows = CopyTable(E.db.windowMover or {})
		if not E.DeepEqual(before.windows, windows) then b.windows = { before = before.windows, after = windows } end
	end
end
Installer.BlizzardTarget = BlizzardTarget

---------------------------------------------------------------------------
-- Step: chat. Uses the game's own chat window functions, the same ones
-- the chat tab menu uses; the player can change or close the tabs later.
---------------------------------------------------------------------------
local CHAT_TABS = {
	{ key = "whispers", title = "Whispers", label = "Whispers tab", desc = "Whispers and Battle.net whispers also get their own tab. The main window keeps them too.",
		groups = { "WHISPER", "BN_WHISPER" } },
	{ key = "loot", title = "Loot", label = "Loot and rewards tab", desc = "Loot, money, currency, skill-ups, XP, honor and reputation also get their own tab. The main window keeps them too.",
		groups = { "LOOT", "MONEY", "CURRENCY", "SKILL", "COMBAT_XP_GAIN", "COMBAT_HONOR_GAIN", "COMBAT_FACTION_CHANGE", "TRADESKILLS", "OPENING" } },
	{ key = "channels", title = "Channels", label = "Public channels tab", desc = "General, Trade, LookingForGroup and the other numbered channels also get their own tab. The main window keeps them too.",
		groups = { "CHANNEL" }, channels = true },
}

function ChatAvailable()
	return type(FCF_OpenNewWindow) == "function" and type(FCF_GetChatWindowInfo) == "function"
		and ChatFrame1 and type(ChatFrame1.AddMessageGroup) == "function"
end
Installer.ChatAvailable = function() return ChatAvailable() end
Installer.CHAT_TABS = CHAT_TABS -- read-only, for plugins

local function FindChatWindow(name)
	local max = Constants and Constants.ChatFrameConstants and Constants.ChatFrameConstants.MaxChatWindows or 10
	for index = 2, max do
		local windowName, _, _, _, _, _, shown, _, docked = FCF_GetChatWindowInfo(index)
		if windowName == name and (shown or docked) then return _G["ChatFrame" .. index] end
	end
end

-- The chat step's tables and helpers.
local ChatData = {}

-- What the main window shows: everything people talk in plus system, loot,
-- reward, pet, target icon and voice transcription lines. The tabs ticked
-- on the step show their part as well; the main window keeps it. Only
-- groups the client knows.
ChatData.MAIN_GROUPS = {
	"SAY", "EMOTE", "YELL", "WHISPER", "BN_WHISPER", "PARTY", "PARTY_LEADER", "RAID", "RAID_LEADER", "RAID_WARNING",
	"INSTANCE_CHAT", "INSTANCE_CHAT_LEADER", "GUILD", "OFFICER", "GUILD_ACHIEVEMENT", "ACHIEVEMENT",
	"MONSTER_SAY", "MONSTER_EMOTE", "MONSTER_YELL", "MONSTER_WHISPER", "MONSTER_BOSS_EMOTE", "MONSTER_BOSS_WHISPER",
	"SYSTEM", "ERRORS", "AFK", "DND", "IGNORED", "BG_HORDE", "BG_ALLIANCE", "BG_NEUTRAL", "PING", "TARGETICONS",
	"BN_INLINE_TOAST_ALERT", "CHANNEL", "LOOT", "MONEY", "CURRENCY", "SKILL", "COMBAT_XP_GAIN", "COMBAT_HONOR_GAIN",
	"COMBAT_FACTION_CHANGE", "TRADESKILLS", "OPENING", "PET_INFO", "COMBAT_MISC_INFO", "VOICE_TEXT",
}

-- Groups whose sender names can be class colored (the chat settings'
-- "Color Names" column uses the same call).
ChatData.CLASS_GROUPS = {
	"SAY", "EMOTE", "YELL", "WHISPER", "PARTY", "PARTY_LEADER", "RAID", "RAID_LEADER", "RAID_WARNING",
	"INSTANCE_CHAT", "INSTANCE_CHAT_LEADER", "GUILD", "OFFICER", "ACHIEVEMENT", "GUILD_ACHIEVEMENT",
}

-- Sizes from the game's own chat font list.
ChatData.CHAT_FONT_SIZES = { 12, 14, 16, 18 }

function ChatData.KnownGroup(group)
	local groups = _G.ChatTypeGroup
	return type(groups) ~= "table" or groups[group] ~= nil
end

local function ChatWindows()
	local list = {}
	for _, name in ipairs(CHAT_FRAMES or { "ChatFrame1" }) do
		local frame = _G[name]
		if frame then list[#list + 1] = frame end
	end
	return list
end

-- The main window back to EldoUI's message groups after a reset.
function ChatData.FillMainWindow(main)
	main:RemoveAllMessageGroups()
	for _, group in ipairs(ChatData.MAIN_GROUPS) do
		if ChatData.KnownGroup(group) then main:AddMessageGroup(group) end
	end
end

-- The chat types whose sender names "Class-colored names" colors.
local function ClassColorTypes()
	local list = {}
	for _, group in ipairs(ChatData.CLASS_GROUPS) do
		local groups = _G.ChatTypeGroup
		local types = type(groups) == "table" and groups[group]
		if type(types) == "table" then
			for _, event in pairs(types) do
				if type(event) == "string" and event:sub(1, 9) == "CHAT_MSG_" then list[#list + 1] = event:sub(10) end
			end
		else
			list[#list + 1] = group
		end
	end
	local channels = Constants and Constants.ChatFrameConstants and Constants.ChatFrameConstants.MaxChatChannels or 20
	for index = 1, channels do list[#list + 1] = "CHANNEL" .. index end
	return list
end

-- The names of the channels you are in (General, Trade and your own), in
-- the game's order.
function ChatData.JoinedChannels()
	local names = {}
	if type(GetChannelList) ~= "function" then return names end
	local values = { GetChannelList() }
	for index = 1, #values, 3 do
		local name = values[index + 1]
		if type(name) == "string" and not E:IsSecret(name) and name ~= "" then names[#names + 1] = name end
	end
	return names
end

function ChatData.ColorNamesByClass()
	local setColor = _G.SetChatColorNameByClass
	if type(setColor) ~= "function" then return end
	for _, chatType in ipairs(ClassColorTypes()) do setColor(chatType, true) end
end

-- The chat setup. options: mode ("tabs" or "reset"), whispers, loot,
-- channels (tabs), fontSize (number or nil), classColors. Never sends a
-- chat message; only the game's own chat window functions are used.
-- `record` (optional) collects what changed, so "Revert this" can put the
-- windows back: windows opened, groups and channels moved.
local function SetupChat(options, record)
	if not ChatAvailable() then return false end
	local main = ChatFrame1
	local made = {}
	if options.mode == "reset" and type(FCF_ResetChatWindows) == "function" then
		FCF_ResetChatWindows()
		ChatData.FillMainWindow(main)
	else
		-- Keeping the windows: the main window gets every message group it
		-- lacks, also the ones an earlier setup moved to a tab, and every
		-- channel you are in that it no longer shows.
		for _, group in ipairs(ChatData.MAIN_GROUPS) do
			if ChatData.KnownGroup(group) and not main:ContainsMessageGroup(group) then
				main:AddMessageGroup(group)
				if record then record.added[#record.added + 1] = { main, group } end
			end
		end
		for _, name in ipairs(ChatData.JoinedChannels()) do
			if not main:ContainsChannel(name) then
				main:AddChannel(name)
				if record then record.joined[#record.joined + 1] = { main, name } end
			end
		end
	end
	for _, tab in ipairs(CHAT_TABS) do
		if options[tab.key] then
			-- The tab gets its name in the player's language; one made earlier
			-- under the English name is reused.
			local frame = FindChatWindow(L[tab.title]) or FindChatWindow(tab.title)
			if not frame then
				frame = FCF_OpenNewWindow(L[tab.title], true)
				if frame and record then record.opened[#record.opened + 1] = frame end
			end
			if not frame then
				E:Print(L["No free chat window left for the %s tab."]:format(L[tab.title]))
				break
			end
			for _, group in ipairs(tab.groups) do
				if not frame:ContainsMessageGroup(group) then
					frame:AddMessageGroup(group)
					if record then record.added[#record.added + 1] = { frame, group } end
				end
			end
			if tab.channels then
				local names = {}
				for _, name in pairs(main.channelList or {}) do names[#names + 1] = name end
				for _, name in ipairs(names) do
					if not frame:ContainsChannel(name) then
						frame:AddChannel(name)
						if record then record.joined[#record.joined + 1] = { frame, name } end
					end
				end
			end
			made[#made + 1] = L[tab.title]
		end
	end
	local size = tonumber(options.fontSize)
	if size and type(FCF_SetChatWindowFontSize) == "function" then
		for _, frame in ipairs(ChatWindows()) do FCF_SetChatWindowFontSize(nil, frame, size) end
	end
	if options.classColors then ChatData.ColorNamesByClass() end
	if FCF_SelectDockFrame then FCF_SelectDockFrame(main) end
	-- The main chat into EldoUI's chat panel when the Blizzard UI switches
	-- let EldoUI move it (Modules/Chat/Core.lua re-anchors after Edit Mode and
	-- after the game saves a window position); the game keeps that spot.
	local chat = E.modules and E.modules.Chat
	if chat and chat.active and chat.PanelMode and chat:PanelMode() then
		chat:Apply()
		if type(FCF_SavePositionAndDimensions) == "function" then FCF_SavePositionAndDimensions(main) end
		if type(FCF_StopDragging) == "function" then FCF_StopDragging(main) end
	end
	-- No chat line: the step's toast (or the Finish summary) confirms it
	-- inside the window (DESIGN.md 5).
	return true, made
end
Installer.SetupChat = SetupChat

-- Does the chat step change anything with these picks?
local function ChatHasChoice(c)
	if c.mode == "reset" then return true end
	if c.mode ~= "tabs" then return false end
	return (c.whispers or c.loot or c.channels or c.fontSize or c.classColors) and true or false
end

-- What the chat looks like before the setup: font size per window and
-- which chat types color names by class. "Revert this" puts both back.
local function ChatBefore()
	local data = { sizes = {}, colors = {}, opened = {}, added = {}, moved = {}, joined = {}, channels = {} }
	if not ChatAvailable() then return data end
	for _, frame in ipairs(ChatWindows()) do
		local id = frame.GetID and frame:GetID()
		local size = id and select(2, FCF_GetChatWindowInfo(id))
		if tonumber(size) then data.sizes[#data.sizes + 1] = { frame, tonumber(size) } end
	end
	local info = type(_G.ChatTypeInfo) == "table" and _G.ChatTypeInfo
	for _, chatType in ipairs(ClassColorTypes()) do
		local entry = info and info[chatType]
		if type(entry) == "table" then data.colors[chatType] = entry.colorNameByClass and true or false end
	end
	return data
end

-- Undo a chat setup from its record. A reset of every window can't be
-- undone (the game drops the old windows), so that record has `reset`.
local function RevertChat(data)
	if data.reset or not ChatAvailable() then return false end
	local main = ChatFrame1
	for _, pair in ipairs(data.added) do
		if pair[1]:ContainsMessageGroup(pair[2]) then pair[1]:RemoveMessageGroup(pair[2]) end
	end
	for _, pair in ipairs(data.joined) do
		if pair[1]:ContainsChannel(pair[2]) then pair[1]:RemoveChannel(pair[2]) end
	end
	for _, group in ipairs(data.moved) do
		if not main:ContainsMessageGroup(group) then main:AddMessageGroup(group) end
	end
	for _, name in ipairs(data.channels) do
		if not main:ContainsChannel(name) then main:AddChannel(name) end
	end
	if type(FCF_Close) == "function" then
		for _, frame in ipairs(data.opened) do FCF_Close(frame) end
	end
	if type(FCF_SetChatWindowFontSize) == "function" then
		for _, pair in ipairs(data.sizes) do FCF_SetChatWindowFontSize(nil, pair[1], pair[2]) end
	end
	local setColor = _G.SetChatColorNameByClass
	if type(setColor) == "function" then
		for chatType, on in pairs(data.colors) do setColor(chatType, on) end
	end
	if FCF_SelectDockFrame then FCF_SelectDockFrame(main) end
	return true
end
Installer.RevertChat = RevertChat

function Work.ApplyChatStep(record)
	local c = session.chat
	if ChatHasChoice(c) then
		if record and c.mode == "reset" then record.reset = true end
		E:RunOutOfCombat(function()
			local ok, err = pcall(SetupChat, c, record)
			if not ok then geterrorhandler()(err) end
		end)
	end
	c.state = "applied"
end

---------------------------------------------------------------------------
-- Step: other addons
---------------------------------------------------------------------------
-- The leveling guide row: one pick of the guide that takes the layout's
-- guide spot (Modules/Integrations.lua, E:GuideProvider). nil keeps the
-- saved pick; the row shows only while Eldostar is part of this EldoUI.
function Work.GuidePick(a)
	return (a and a.guide) or (E.GuideProviderChoice and E:GuideProviderChoice()) or "auto"
end

function Work.GuidePickChanged(a)
	return a and a.guide ~= nil and E.modules.Eldostar ~= nil and E.GuideProviderChoice ~= nil
		and a.guide ~= E:GuideProviderChoice()
end

---------------------------------------------------------------------------
-- Some addons ask the player in their own window, so a result
-- can come after the step was applied, even after Finish. An addon that
-- was declined or failed loses its tick; when none was imported the step
-- counts as skipped, so the summary and Finish don't claim or retry it.
-- The placement rows (Modules/Integrations.lua) write the switch of each
-- tick that differs from it, at once (`place`: key = true or false).
local addonApplySerial = 0
function Work.ApplyAddonsStep()
	local ownSession, profile, profileName = session, E.db, E.profileName
	local a = ownSession.addons
	local placed = {}
	for _, pick in ipairs(E:AddonPlacementChanges(a.place)) do placed[#placed + 1] = { entry = pick.entry, on = pick.on } end
	-- The leveling guide on the guide spot (Eldostar's provider pick).
	local guideChanged = Work.GuidePickChanged(a)
	local guide = guideChanged and a.guide or nil
	if guideChanged and (E:IsSecret(a.guide) or type(a.guide) ~= "string" or not E.GUIDE_PROVIDER_TITLES[a.guide]) then a.state = "none" return false end
	addonApplySerial = addonApplySerial + 1
	local serial = addonApplySerial
	local guideModule = E.modules.Eldostar
	local guideDB = guideModule and guideModule.db
	if guide and type(guideDB) ~= "table" then a.state = "none" return false end
	local databases, selected = {}, {}
	for _, pick in ipairs(placed) do
		local module = E.modules[pick.entry.module]
		if module then databases[module] = module.db end
	end
	for name, value in pairs(a.selected) do selected[name] = value end
	local function Current()
		if session ~= ownSession or ownSession.addons ~= a or E.db ~= profile or E.profileName ~= profileName
			or addonApplySerial ~= serial or E.modules.Eldostar ~= guideModule or (guideModule and guideModule.db ~= guideDB) then return false end
		if guide and guideDB.provider ~= guide then return false end
		for module, database in pairs(databases) do if module.db ~= database then return false end end
		return true
	end
	a.state = "applied"
	-- Both choices belong to this same Apply. Choose the guide before its
	-- position is written, so the position never goes to an unselected guide.
	if guide then
		guideDB.provider = guide
		E:GuideProviderChanged()
	end
	if not Current() then return false end
	for _, pick in ipairs(placed) do
		if not Current() then return false end
		E:SetAddonPlacement(pick.entry, pick.on)
	end
	if not Current() then return false end
	if not next(selected) then return end
	local open, imported = 0, 0
	for _ in pairs(selected) do open = open + 1 end
	E:RunOutOfCombat(function()
		if not Current() then return end
		E:ApplyAddonSetups(selected, function(name, ok)
			if not Current() then return end
			open = open - 1
			if ok then
				imported = imported + 1
			elseif a.state == "applied" then
				a.selected[name] = nil
			end
			if open <= 0 and imported == 0 and #placed == 0 and not guide and a.state == "applied" then a.state = "skipped" end
			if session and session.addons == a then Installer.Update() end
		end)
	end)
end

---------------------------------------------------------------------------
-- Step: accessibility. Three of the switches from General >
-- Accessibility (Core/Accessibility.lua), offered once so a player who
-- needs them finds them at the start. Each tick shows the switch as it is
-- now; changing a tick turns that switch on or off with Apply, through
-- the page's own path. Nothing changes while the ticks stay as they are.
-- Sound cues and the fine settings stay on that page.
---------------------------------------------------------------------------
local ACCESS_CHOICES = {
	{ key = "highContrast", label = "High contrast",
		desc = "Black opaque panels with bright 2-pixel borders and a thick outline on every EldoUI text. It takes the place of the skin; turning it off in /eui puts that skin back.",
		on = function(access) return access.highContrast == true end,
		set = function(access) access.highContrast = true end,
		unset = function(access) access.highContrast = false end },
	{ key = "largeText", label = "Large text",
		desc = "Every EldoUI text at 130 %. The size can be changed later, from 100 to 160 %.",
		on = function(access) return access.largeText == true end,
		-- On a small screen, at least the size that brings the smallest text
		-- to 9 pixels (E:SmallTextAdvice).
		set = function(access)
			access.largeText = true
			local _, need = E:SmallTextAdvice()
			if need and need > (tonumber(access.textScale) or 1.3) then access.textScale = need end
		end,
		unset = function(access) access.largeText = false end },
	{ key = "colorBlind", label = "Color-blind safe colors",
		desc = "Safe colors for reactions, threat, dispel types, unit states and good, warning and bad text, with a mark next to each so color alone never carries the meaning. The kind (red, green or blue) can be picked later.",
		on = function(access) return access.colorBlind == "on" end,
		set = function(access)
			access.colorBlind = "on"
			if access.shapeMarks == nil then access.shapeMarks = true end
		end,
		unset = function(access) access.colorBlind = "game" end },
}
Installer.ACCESS_CHOICES = ACCESS_CHOICES -- read-only, for plugins

local function AccessSettings()
	local general = E.db and E.db.general
	return general and general.access
end

-- A tick changed from the switch as it is: picks[key] is true (turn on)
-- or false (turn off). What Apply would change: { info, on } entries.
local function AccessPicked()
	local access, picked = AccessSettings(), {}
	if not access then return picked end
	for _, info in ipairs(ACCESS_CHOICES) do
		local want = session.access.picks[info.key]
		if want ~= nil and (want and true or false) ~= info.on(access) then picked[#picked + 1] = { info = info, on = want and true or false } end
	end
	return picked
end

function Work.ApplyAccessStep()
	local target, run = Work.ProfileTarget(), session
	if not target or E.Secret(run) or type(run) ~= "table" then return end
	local access = AccessSettings()
	if E.Secret(access) or type(access) ~= "table" or getmetatable(access) ~= nil then return end
	local function Current()
		if session ~= run or not Work.ProfileTarget(target) then return false end
		local value = AccessSettings()
		return not E.Secret(value) and value == access
	end
	local picked = AccessPicked()
	if not Current() then return end
	if #picked > 0 then
		for _, entry in ipairs(picked) do
			entry.apply = entry.on and entry.info.set or entry.info.unset
			if E.Secret(entry.apply) or type(entry.apply) ~= "function" then return end
		end
		local changed = E.AccessibilityChanged
		if E.Secret(changed) or (changed ~= nil and type(changed) ~= "function") then return end
		E:RunOutOfCombat(function()
			if not Current() or E.Secret(E.AccessibilityChanged) or E.AccessibilityChanged ~= changed then return end
			for _, entry in ipairs(picked) do
				local apply = entry.on and entry.info.set or entry.info.unset
				if E.Secret(apply) or apply ~= entry.apply or not Current() then return end
				entry.apply(access)
			end
			-- The page's own path: applies, repaints and keeps Undo working.
			if not Current() or E.Secret(E.AccessibilityChanged) or E.AccessibilityChanged ~= changed then return end
			if changed then changed(E) end
			if Current() then run.access.state = "applied" end
		end, "installer-access")
	else
		run.access.state = "applied"
	end
end

---------------------------------------------------------------------------
-- Step: convenience. Every helper that acts for the player is listed here,
-- one row each, from the list the modules keep (Core/Conveniences.lua):
-- repairs, selling gray items, restocking, the quest helpers, declining
-- strangers and the rest. Each is off until the player ticks it, except
-- three that start ticked on a first run: repairs, selling gray items and
-- faster auto loot. The step's heading says so (design decision: one
-- click gives a finished UI, and nothing that acts for the player is
-- hidden). Repairs pay from the player's own gold unless they pick the
-- guild bank. "Recommended for me" ticks the rows that suit this
-- character (class and level) and unticks the rest; nothing changes
-- until Apply. A row whose module is off is grayed with the reason. A
-- tick taken away after Apply puts back the value from before, while the
-- setting still holds what the step set; unticked ones are otherwise left
-- as they are. Rows that belong to the Keys and spells step are only
-- named here, so each setting has one home.
---------------------------------------------------------------------------
local REPAIR_MODES = {
	{ key = "personal", title = "Own gold only", desc = "Always pays with your own gold." },
	{ key = "guild", title = "Guild bank first", desc = "Uses guild bank repair money when your guild allows it, then your own gold." },
}

-- The rows this step ticks (the Keys and spells ones live on that step).
local function ConvenienceRows()
	local list = {}
	for _, row in ipairs(E:Conveniences()) do
		if row.group ~= "keys" then list[#list + 1] = row end
	end
	return list
end

-- Why a row is grayed: its module is off, also by the Modules step's pick.
local function ConvenienceOff(row)
	return E:ConvenienceOffReason(row, session and session.modules and session.modules.states)
end

-- What Apply would change, or (write true) changes: a ticked helper that
-- isn't on yet is turned on; an unticked one this run turned on goes back.
-- A row whose module is off is left as it is.
local function ConvenienceWork(c, write)
	c.set = c.set or {}
	local count, refresh = 0, {}
	for _, row in ipairs(ConvenienceRows()) do
		local module = row.module and E.modules and E.modules[row.module]
		if (module == nil or module.db) and not ConvenienceOff(row) then
			local now, set = E:ConvenienceValue(row), c.set[row.id]
			if c[row.id] then
				local want = E:ConvenienceOnValue(row, c)
				if now ~= want then
					count = count + 1
					if write then
						-- The oldest value is the one to go back to.
						local from = now
						if set then from = set.from end
						c.set[row.id] = { from = from, to = want }
						E:WriteConvenienceValue(row, want)
						refresh[module] = true
					end
				end
			elseif set then
				if now == set.to then
					count = count + 1
					if write then
						E:WriteConvenienceValue(row, set.from)
						refresh[module] = true
					end
				end
				if write then c.set[row.id] = nil end
			end
		end
	end
	for module in pairs(refresh) do RefreshModule(module) end
	return count
end

function Work.ApplyConvenienceStep()
	local c = session.convenience
	ConvenienceWork(c, true)
	c.state = "applied"
end

---------------------------------------------------------------------------
-- Game settings: a few of the game's own interface settings (CVars) that
-- fit EldoUI. Presentation only: nothing here plays or acts for the
-- player. Each goes through E:SetCVar(name, value, "installer"), which
-- remembers the player's value first, so "Blizzard default" in /eui puts
-- it back. A setting the game already has is not written again, and one
-- this client doesn't know is not shown.
---------------------------------------------------------------------------
local CVAR_OWNER = "installer"

GAME_SETTINGS = {
	{ key = "lockActionBars", values = { { "lockActionBars", "1" } }, label = "Lock action bars",
		desc = "Buttons can't be dragged off your bars by accident. Hold the game's pick-up key (Shift unless you changed it) to move one anyway.",
		-- EldoUI's action bars can hold this setting themselves.
		owner = function()
			local bars = E.modules and E.modules.ActionBars
			if bars and bars.active and bars.db and bars.db.lockBars and bars.db.lockBars ~= "game" then
				return L["Set by EldoUI's action bars (Action Bars > Lock action bars)."]
			end
		end },
	{ key = "countdownForCooldowns", values = { { "countdownForCooldowns", "1" } }, label = "Numbers on cooldowns",
		desc = "Game buttons that EldoUI doesn't style show the seconds left on a cooldown. EldoUI's own buttons have their own cooldown numbers." },
	{ key = "statusText", values = { { "statusTextDisplay", "BOTH" }, { "statusText", "1" } }, label = "Numbers on the game's bars",
		desc = "The game's own health, power and experience bars show the value and the percent." },
	{ key = "UberTooltips", values = { { "UberTooltips", "1" } }, label = "Detailed tooltips",
		desc = "Spell and ability tooltips show their full description." },
	{ key = "showTutorials", values = { { "showTutorials", "0" } }, label = "No tutorial pop-ups",
		desc = "The game's tutorial hints stay away. Turn them back on in the game's Interface settings." },
	{ key = "whisperMode", values = { { "whisperMode", "inline" } }, label = "Whispers in the chat",
		desc = "New whispers show in your chat (and its Whispers tab) instead of opening a window of their own." },
}

local function GameCVar(name)
	return C_CVar and C_CVar.GetCVar and C_CVar.GetCVar(name)
end

-- "missing" (not on this client), "owned" (an EldoUI module holds it),
-- "set" (the game already uses this value) or "ready".
local function GameSettingStatus(info)
	for _, pair in ipairs(info.values) do
		if GameCVar(pair[1]) == nil then return "missing" end
	end
	local owner = info.owner and info.owner()
	if owner then return "owned", owner end
	for _, pair in ipairs(info.values) do
		if tostring(GameCVar(pair[1])) ~= pair[2] then return "ready" end
	end
	return "set"
end

-- The ticked settings that would change something.
local function GameSettingsPicked(c)
	local list = {}
	for _, info in ipairs(GAME_SETTINGS) do
		if c.picks[info.key] and GameSettingStatus(info) == "ready" then list[#list + 1] = info end
	end
	return list
end

function Work.ApplyGameSettingsStep()
	local c = session.cvars
	local list = GameSettingsPicked(c)
	if #list > 0 then
		E:RunOutOfCombat(function()
			for _, info in ipairs(list) do
				for _, pair in ipairs(info.values) do
					-- Only a value that differs is written (and remembered).
					if tostring(GameCVar(pair[1])) ~= pair[2] then E:SetCVar(pair[1], pair[2], CVAR_OWNER) end
				end
			end
		end)
	end
	c.state = "applied"
end

Installer.GAME_SETTINGS = GAME_SETTINGS -- read-only, for plugins
Installer.GameSettingStatus = GameSettingStatus

---------------------------------------------------------------------------
-- Role: a small layer over the layout (Core/Roles.lua), the class
-- layer and, for healers, click-cast bindings the player ticks.
---------------------------------------------------------------------------
local function PickKey(item) return (item.mods or "") .. item.key end

-- The suggestions the player ticked (only while click-casting is ticked).
local function PickedBindings()
	local r = session.role
	local list = {}
	if (r.choice or E:GetRole()) ~= "healer" or not r.clickCast then return list end
	for _, item in ipairs(E:GetRoleClickCast()) do
		if r.picks[PickKey(item)] then list[#list + 1] = item end
	end
	return list
end

---------------------------------------------------------------------------
-- Role previews: a role card shows its layer on the live frames at once,
-- like a style pick. The preview keeps the role's settings from before it
-- (`before`) and what it wrote (`after`), so Back, Esc and the close
-- button take it back by value. Class details and click-casting wait for
-- Apply. In combat a pick waits for Apply or Finish.
---------------------------------------------------------------------------
local RolePreview = {}

-- The modules a role or the class layer may change.
function RolePreview.Modules()
	local names = {}
	local function Add(settings)
		for name in pairs(settings or {}) do names[name] = true end
	end
	for _, profile in pairs(E.roleProfiles or {}) do Add(profile.settings) end
	local layer = E:GetRoleClassLayer()
	if layer then Add(layer.settings) end
	return names
end

function RolePreview.Store()
	return E.GetPrivate and E:GetPrivate("premade") or nil
end

-- The parts of two copies that differ, as two sparse tables: only the
-- values the preview wrote are kept, so a paused run stays small.
local function DiffValues(before, after)
	local b, a, changed = {}, {}, false
	local keys = {}
	for key in pairs(before) do keys[key] = true end
	for key in pairs(after) do keys[key] = true end
	for key in pairs(keys) do
		local old, new = before[key], after[key]
		if type(old) == "table" and type(new) == "table" then
			local subBefore, subAfter, subChanged = DiffValues(old, new)
			if subChanged then b[key], a[key], changed = subBefore, subAfter, true end
		elseif not E.DeepEqual(old, new) then
			b[key], a[key], changed = CopyValue(old), CopyValue(new), true
		end
	end
	return b, a, changed
end
RolePreview.DiffValues = DiffValues

-- The modules the preview turned on that are still on.
local function PreviewTurnedOn(snap)
	local names = {}
	for name in pairs(snap.turnedOn or {}) do
		local module = E.modules[name]
		if module and module:IsEnabled() then names[#names + 1] = name end
	end
	return names
end

-- Puts the values from before the preview back, as data only. Returns
-- the modules whose settings it wrote.
local function UndoPreviewData(snap)
	local general = E.db.general
	if general.role == snap.key then general.role = snap.role end
	general.roleRestore = CopyTable(snap.restore or {})
	general.roleMovers = CopyTable(snap.movers or {})
	local touched = {}
	for name, saved in pairs(snap.modules or {}) do
		local module = E.modules[name]
		if module and type(module.db) == "table" then
			local before, after = saved.before or {}, saved.after or {}
			local keys = {}
			for key in pairs(before) do keys[key] = true end
			for key in pairs(after) do keys[key] = true end
			for key in pairs(keys) do
				if not E.DeepEqual(before[key], after[key]) then RestoreByValue(module.db, key, before[key], after[key]) end
			end
			touched[#touched + 1] = module
		end
	end
	-- The class setup follows the role: its record goes back too.
	local store = RolePreview.Store()
	if store then store.applied = CopyValue(snap.premade) end
	return touched
end

function RolePreview.Undo()
	local r = session and session.role
	local snap = r and r.preview
	if not snap then return end
	r.preview = nil
	if r.state == "preview" then r.state = "none" end
	E:RunOutOfCombat(function()
		local turnedOn = PreviewTurnedOn(snap)
		for _, module in ipairs(UndoPreviewData(snap)) do RefreshModule(module) end
		for _, name in ipairs(turnedOn) do E:SetModuleEnabled(name, false) end
		E:RefreshMovers()
	end, "installer-role-preview")
end

-- At logout a shown preview goes back as data only: nothing is drawn any
-- more, and a refresh waiting for the end of combat would never run. The
-- pick stays, so the Role step shows it again on the next open.
function RolePreview.UndoData()
	local r = session and session.role
	local snap = r and r.preview
	if not snap then return end
	r.preview = nil
	if r.state == "preview" then r.state = "none" end
	local turnedOn = PreviewTurnedOn(snap)
	UndoPreviewData(snap)
	for _, name in ipairs(turnedOn) do E.modules[name].db.enabled = false end
end
E:RegisterEvent("PLAYER_LOGOUT", function()
	local ok, err = pcall(RolePreview.UndoData)
	if not ok then geterrorhandler()(err) end
end, RolePreview)

-- Show role `key` on the live frames (nil: keep, the frames as they are).
-- The preview keeps only the values it changed (before and after), not
-- whole module copies.
function RolePreview.Show(key)
	local r = session.role
	local shown = r.preview and r.preview.key or nil
	if shown == key then return false end
	if InCombatLockdown() then return false end
	RolePreview.Undo()
	if key == nil or key == E:GetRole() or r.state == "applied" then return true end
	local general = E.db.general
	local store = RolePreview.Store()
	local snap = { key = key, role = general.role, restore = CopyTable(general.roleRestore or {}),
		movers = CopyTable(general.roleMovers or {}), modules = {}, turnedOn = {}, premade = store and CopyValue(store.applied) }
	local copies = {}
	for name in pairs(RolePreview.Modules()) do
		local module = E.modules[name]
		if module and type(module.db) == "table" then copies[name] = CopyTable(module.db) end
	end
	local statesBefore = ModuleStates()
	if not E:ApplyRole(key) then return true end
	for name, copy in pairs(copies) do
		local before, after, changed = DiffValues(copy, CopyTable(E.modules[name].db))
		if changed then snap.modules[name] = { before = before, after = after } end
	end
	for name, on in pairs(ModuleStates()) do
		if on and statesBefore[name] == false then snap.turnedOn[name] = true end
	end
	r.preview = snap
	r.state = "preview"
	return true
end

-- Make the preview match the pick (called while the Role step shows).
function RolePreview.Sync()
	local r = session and session.role
	if not r or r.state == "applied" then return false end
	return RolePreview.Show(r.choice)
end

RolePreview.Revert = RolePreview.Undo
Installer.RolePreview = RolePreview

local function RoleHasChoice()
	local r = session.role
	if r.state == "preview" then return true end
	if r.choice ~= nil and r.choice ~= E:GetRole() then return true end
	if r.classLayer ~= (E.db.general.roleClass and true or false) then return true end
	return #PickedBindings() > 0
end

function Work.ApplyRoleStep()
	local r = session.role
	local bindings = PickedBindings()
	-- A preview of the same role is kept as it is; ApplyRole is repeat-safe.
	r.preview = nil
	E:ApplyRole(r.choice or E:GetRole(), { classLayer = r.classLayer, bindings = #bindings > 0 and bindings or nil })
	-- Bound once; a second Apply in this run doesn't bind again. The
	-- character's alts can copy that it did (Core/InstallerAlt.lua).
	r.clickCastBound = r.clickCastBound or #bindings > 0
	r.clickCast = false
	wipe(r.picks)
	r.state = "applied"
end

---------------------------------------------------------------------------
-- Modules: switched at Finish, one reload for all of them.
---------------------------------------------------------------------------
local function ModuleChanges()
	local list = {}
	for name, module in E:IterateModules() do
		local wanted = session.modules.states[name]
		if wanted ~= nil and wanted ~= (module:IsEnabled() and true or false) then list[#list + 1] = name end
	end
	return list
end

function Work.ApplyModulesStep()
	local m = session.modules
	local off = false
	for _, name in ipairs(ModuleChanges()) do
		local on = m.states[name] and true or false
		E:SetModuleEnabled(name, on)
		if not on then off = true end
	end
	-- Blizzard's own versions of switched-off parts come back fully after a reload.
	if off then session.needsReload = true end
	m.state = "applied"
end

---------------------------------------------------------------------------
-- What this run changed, and "Revert this". Before a step applies for the
-- first time in a run, the values it is about to change are kept (one
-- copy per part, the oldest wins). The last page lists the changes in
-- groups, each with a button that puts that group back as it was:
-- settings in place, CVars through E:SetCVar, Blizzard elements through
-- their own undo (E:RestoreBlizzard). Some changes can't be put back from
-- here; their row says where to change them instead.
---------------------------------------------------------------------------
local CHANGE_GROUPS = {
	-- The profile an alt was attached to (Core/InstallerAlt.lua).
	{ key = "profile", title = "Profile" },
	{ key = "scale", title = "UI scale" },
	{ key = "layout", title = "Layout" },
	{ key = "look", title = "Look" },
	{ key = "access", title = "Accessibility" },
	{ key = "role", title = "Role" },
	{ key = "competitors", title = "Your addons" },
	{ key = "modules", title = "Modules" },
	{ key = "blizzard", title = "Blizzard UI" },
	{ key = "chat", title = "Chat" },
	{ key = "cvars", title = "Game settings" },
	{ key = "addons", title = "Addon profiles", note = Key("Switch back in each addon's profiles") },
	{ key = "convenience", title = "Convenience" },
	{ key = "class", title = "Class setup" },
	{ key = "keys", title = "Keys and spells" },
	{ key = "controller", title = "Controller" },
	{ key = "clickcast", title = "Click-casting" },
}
local GROUP_INFO = {}
for index, info in ipairs(CHANGE_GROUPS) do
	info.order = index
	GROUP_INFO[info.key] = info
end
-- Steps that belong to another group.
local STEP_GROUP = { styles = "look" }

-- How to keep (capture) and put back (restore) each part.
local PARTS = {}

-- Put a module's settings back in place. Its on/off switch stays: that
-- belongs to the Modules group (E:SetModuleEnabled).
local function RestoreSettings(target, saved)
	for key in pairs(target) do
		if saved[key] == nil and key ~= "enabled" then target[key] = nil end
	end
	for key, value in pairs(saved) do
		if key ~= "enabled" then target[key] = CopyValue(value) end
	end
end

PARTS.scale = {
	capture = function()
		local s = session.scale
		return { value = s.snapshot and s.snapshot.value or E.db.general.uiScale }
	end,
	restore = function(data)
		E.db.general.uiScale = data.value
		E:ApplyScale()
	end,
}

PARTS.layout = {
	-- A preview already kept the positions from before it.
	capture = function() return session.layout.snapshot or SnapshotLayout() end,
	restore = function(data) RestoreLayout(data) end,
}

-- Skin, accent and font (the Styles step's cards and full looks), with
-- whether the skin follows the layout and the faction look.
PARTS.art = {
	capture = function()
		local general = E.db.general
		return { artStyle = general.artStyle, accent = general.accent, accentFromArt = general.accentFromArt,
			accentCustom = CopyValue(general.accentCustom), font = general.font, skinFollow = general.skinFollow,
			skinVariant = general.skinVariant }
	end,
	restore = function(data)
		local general = E.db.general
		for key, value in pairs(data) do general[key] = CopyValue(value) end
		E:RefreshTheme()
	end,
}

-- The settings of every part of the UI a style can change, as they were
-- before a preview shown now.
PARTS.styles = {
	capture = function()
		local data = {}
		for _, name in ipairs(StyleCategories()) do
			local module = E.modules[name]
			if module and module.db then data[name] = Preview.Without(name, CopyTable(module.db)) end
		end
		return data
	end,
	restore = function(data)
		for name, saved in pairs(data) do
			local module = E.modules[name]
			if module and module.db then
				RestoreSettings(module.db, saved)
				RefreshModule(module)
			end
		end
	end,
}

PARTS.access = {
	capture = function() return CopyTable(AccessSettings() or {}) end,
	restore = function(data)
		local access = AccessSettings()
		if not access then return end
		for key in pairs(access) do
			if data[key] == nil then access[key] = nil end
		end
		for key, value in pairs(data) do access[key] = CopyValue(value) end
		if E.AccessibilityChanged then E:AccessibilityChanged() end
	end,
}

-- The role layer, and the click-cast bindings it may add (the Click
-- Casting module's own settings and its on/off switch).
PARTS.role = {
	capture = function()
		-- A preview shown now: the role from before it.
		local preview = session.role.preview
		local data = { role = preview and preview.role or E:GetRole(), classLayer = E.db.general.roleClass and true or false }
		local clickCast = E.modules.ClickCast
		if #PickedBindings() > 0 and clickCast and clickCast.db then
			data.clickCast = CopyTable(clickCast.db)
			data.clickCastOn = clickCast:IsEnabled() and true or false
		end
		return data
	end,
	restore = function(data)
		E:ApplyRole(data.role, { classLayer = data.classLayer })
		local clickCast = E.modules.ClickCast
		if data.clickCast and clickCast and clickCast.db then
			RestoreSettings(clickCast.db, data.clickCast)
			RefreshModule(clickCast)
			if not data.clickCastOn and clickCast:IsEnabled() then
				E:SetModuleEnabled("ClickCast", false)
				session.needsReload = true
			end
		end
	end,
}

PARTS.modules = {
	capture = function() return ModuleStates() end,
	restore = function(data)
		for name, module in E:IterateModules() do
			local on = data[name]
			if on ~= nil and on ~= (module:IsEnabled() and true or false) then E:SetModuleEnabled(name, on) end
		end
		session.needsReload = true
	end,
}

PARTS.blizzard = {
	capture = function()
		local general = E.db.general
		return { switches = E:SnapshotBlizzard(), windows = CopyTable(E.db.windowMover or {}),
			windowsMode = general.blizzardWindows, windowsRecord = CopyValue(general.blizzardWindowsRestore) }
	end,
	restore = function(data)
		E:RestoreBlizzard(data.switches)
		local general = E.db.general
		general.blizzardWindows, general.blizzardWindowsRestore = data.windowsMode, CopyValue(data.windowsRecord)
		local mover = E.db.windowMover
		if type(mover) == "table" then
			for key in pairs(mover) do
				if data.windows[key] == nil then mover[key] = nil end
			end
			for key, value in pairs(data.windows) do mover[key] = CopyValue(value) end
			if E.SyncWindowSwitches then E:SyncWindowSwitches() end
			if E.WindowMoverApply then E:WindowMoverApply() end
		end
		-- The installer's own reload offer covers it.
		E:HideReloadPrompt()
		session.needsReload = true
	end,
}

PARTS.chat = {
	capture = ChatBefore,
	restore = RevertChat,
	-- Resetting every chat window can't be undone.
	note = function(data) return data.reset and L["A chat reset can't be undone"] or nil end,
}

PARTS.cvars = {
	capture = function()
		local data = {}
		for _, info in ipairs(GAME_SETTINGS) do
			for _, pair in ipairs(info.values) do
				local value = GameCVar(pair[1])
				if value ~= nil and data[pair[1]] == nil then data[pair[1]] = tostring(value) end
			end
		end
		return data
	end,
	restore = function(data)
		local snapshot = EldoUIDB.cvarSnapshot
		for name, value in pairs(data) do
			if tostring(GameCVar(name)) ~= value then E:SetCVar(name, value, CVAR_OWNER) end
			-- The player's own value is back: nothing left to remember.
			local saved = snapshot and snapshot[name]
			if saved and saved.owner == CVAR_OWNER and tostring(saved.value) == value then snapshot[name] = nil end
		end
	end,
}

PARTS.convenience = {
	-- Every row's setting, by the row's id (Core/Conveniences.lua).
	capture = function()
		local data = {}
		for _, row in ipairs(ConvenienceRows()) do data[row.id] = CopyValue(E:ConvenienceValue(row)) end
		return data
	end,
	restore = function(data)
		local refresh = {}
		for _, row in ipairs(ConvenienceRows()) do
			local value = data[row.id]
			if value ~= nil and not E.DeepEqual(E:ConvenienceValue(row), value) then
				E:WriteConvenienceValue(row, CopyValue(value))
				local module = row.module and E.modules[row.module]
				if module then refresh[module] = true end
			end
		end
		for module in pairs(refresh) do RefreshModule(module) end
	end,
}

-- Keys and spells: the Apply this run made (Core/KeybindPreview.lua keeps
-- the record). Revert this puts back its keys, class spells and ranks,
-- only where they still hold what was put; the class setup's slots and
-- macros belong to the Class setup group.
local function KeysHistory()
	local store = E.GetPrivate and E:GetPrivate("keysAndSpells")
	return type(store) == "table" and type(store.history) == "table" and store.history or {}
end

PARTS.keys = {
	capture = function()
		local history = KeysHistory()
		return { last = history[#history] or false }
	end,
	restore = function(data)
		local record = E.KeysAndSpellsRecord and E:KeysAndSpellsRecord()
		if record and record ~= data.last and E.RestoreKeysAndSpells then
			E:RestoreKeysAndSpells(false, { keys = true, spells = true, ranks = true })
		end
	end,
	changed = function(data)
		local record = E.KeysAndSpellsRecord and E:KeysAndSpellsRecord()
		return record ~= nil and record ~= data.last
	end,
}

-- The class setup's action slots and macros (Express setup): what the
-- class setup record held before. Revert this takes back only what this
-- run placed, while the slot still holds that spell and the macro still
-- has that text; a slot or macro the player changed since stays.
PARTS.premade = {
	capture = function()
		local record = E.PremadeApplied and E:PremadeApplied()
		return { bars = CopyTable(record and record.bars or {}), macros = CopyTable(record and record.macros or {}) }
	end,
	restore = function(data)
		if E.RevertPremadeParts then E:RevertPremadeParts({ bars = true, macros = true }, data) end
	end,
	changed = function(data)
		local record = E.PremadeApplied and E:PremadeApplied()
		if not record then return false end
		for slot in pairs(record.bars or {}) do
			if data.bars[slot] == nil then return true end
		end
		for name in pairs(record.macros or {}) do
			if data.macros[name] == nil then return true end
		end
		return false
	end,
}

-- The Controller step's Gamepad Mode UI switches (Core/GamepadMode.lua).
PARTS.controller = {
	capture = function()
		local db = type(E.db.gamepadUI) == "table" and E.db.gamepadUI or {}
		return { always = db.always and true or false, ask = db.ask ~= false }
	end,
	restore = function(data)
		if type(E.db.gamepadUI) ~= "table" then return end
		E.db.gamepadUI.ask = data.ask
		E:SetGamepadModeAlways(data.always)
	end,
}

-- Did a part really change since it was kept? Compares what is set now
-- with the kept copy, so the last page lists what changed, not what was
-- picked. true, false, or nil when it can't be told (then it is listed).
PARTS.scale.changed = function(data) return data.value ~= E.db.general.uiScale end
PARTS.layout.changed = function(data)
	local general = E.db.general
	if data.layout ~= general.layout or data.accent ~= general.accent then return true end
	if not E.DeepEqual(data.movers or {}, E.db.movers or {}) or not E.DeepEqual(data.hidden or {}, general.layoutHidden or {}) then return true end
	for moduleName, saved in pairs(data.modules or {}) do
		local module = E.modules[moduleName]
		if module and module.db then
			for setting, entry in pairs(saved) do
				if not E.DeepEqual(entry.value, module.db[setting]) then return true end
			end
		end
	end
	return false
end
PARTS.role.changed = function(data)
	if data.role ~= E:GetRole() or data.classLayer ~= (E.db.general.roleClass and true or false) then return true end
	local clickCast = E.modules.ClickCast
	if data.clickCast and clickCast and clickCast.db and not E.DeepEqual(data.clickCast, clickCast.db) then return true end
	return false
end
PARTS.chat.changed = function(data)
	if data.reset or #data.opened > 0 or #data.added > 0 or #data.moved > 0 or #data.joined > 0 or #data.channels > 0 then return true end
	local now = ChatBefore()
	local sizes = {}
	for _, pair in ipairs(now.sizes) do sizes[pair[1]] = pair[2] end
	for _, pair in ipairs(data.sizes) do
		if sizes[pair[1]] ~= nil and sizes[pair[1]] ~= pair[2] then return true end
	end
	for chatType, on in pairs(data.colors) do
		if now.colors[chatType] ~= nil and now.colors[chatType] ~= on then return true end
	end
	return false
end

local function PartChanged(part, data)
	local info = PARTS[part]
	if not (info and data) then return nil end
	local ok, result
	if info.changed then
		ok, result = pcall(info.changed, data)
	else
		ok, result = pcall(function() return not E.DeepEqual(info.capture(), data) end)
	end
	if not ok then return nil end
	return result and true or false
end

-- A part of the run's own (capture, restore and optionally changed,
-- note), for a page that keeps its own parts (Core/InstallerAlt.lua).
function Installer.AddPart(name, part) PARTS[name] = part end

-- Put a kept part back outside a run (the alt setup's undo). Returns true
-- when it ran without an error.
function Installer.RestorePart(name, data)
	local info = PARTS[name]
	if not (info and info.restore and data) then return false end
	local ok, err = pcall(info.restore, data)
	if not ok then geterrorhandler()(err) end
	return ok
end

-- The group of a run, made when it first changes something.
local function ChangeGroup(key, title)
	local undo = session.undo
	local group = undo.groups[key]
	if not group then
		local info = GROUP_INFO[key] or {}
		group = { key = key, title = title or info.title or key, order = info.order or (100 + #undo.list),
			note = info.note, parts = {}, partOrder = {} }
		undo.groups[key] = group
		undo.list[#undo.list + 1] = group
		table.sort(undo.list, function(a, b) return a.order < b.order end)
	end
	group.reverted = nil
	return group
end
Installer.ChangeGroup = ChangeGroup

-- Keep part `part` of group `key` before it changes (once per run).
-- Returns the kept data.
local function Remember(key, part, title)
	if not session then return nil end
	local group = ChangeGroup(key, title)
	if group.parts[part] == nil and PARTS[part] then
		local ok, data = pcall(PARTS[part].capture)
		if ok then
			group.parts[part] = data
			group.partOrder[#group.partOrder + 1] = part
		else
			geterrorhandler()(data)
			group.parts[part] = false
		end
	end
	return group.parts[part] or nil
end
Installer.Remember = Remember

-- Before a step applies: keep what it changes, and what it says it does.
local function RememberStep(step)
	if not session then return nil end
	local key = STEP_GROUP[step.key] or step.key
	local group
	if step.manual then
		group = ChangeGroup(step.key, step.title)
		group.note = Key("Change it in its own options")
	else
		Remember(key, step.key)
		group = ChangeGroup(key)
	end
	local ok, text = pcall(step.Summary)
	group.texts = group.texts or {}
	group.texts[step.key] = ok and text or nil
	return group.parts[step.key] or nil
end

-- Is a group on the last page? Only when one of its parts really changed
-- (or can't be told), when it was reverted or hit an error, or when its
-- own options are the place to change it (setup pages).
local function GroupChanged(group)
	if group.reverted or group.failed or group.note then return true end
	-- In combat the changes may still wait for the end of combat.
	if InCombatLockdown() then return true end
	local any = false
	for _, part in ipairs(group.partOrder) do
		any = true
		if PartChanged(part, group.parts[part]) ~= false then return true end
	end
	return not any
end
Installer.GroupChanged = GroupChanged

-- What the last page says about a group: the summary of each step whose
-- part really changed.
local function ChangeText(group)
	local parts = {}
	if group.parts.art and PartChanged("art", group.parts.art) ~= false then
		local info = E.artStyleInfo[E.db.general.artStyle]
		parts[#parts + 1] = L["Skin: %s"]:format(info and L[info.title] or tostring(E.db.general.artStyle))
	end
	for stepKey, text in pairs(group.texts or {}) do
		if group.parts[stepKey] == nil or PartChanged(stepKey, group.parts[stepKey]) ~= false then parts[#parts + 1] = text end
	end
	if #parts == 0 then return L[group.title] end
	table.sort(parts)
	return table.concat(parts, "; ")
end

-- Why a group has no Revert this button (nil when it has one).
local function ChangeNote(group)
	if group.note then return L[group.note] end
	local any = false
	for _, part in ipairs(group.partOrder) do
		local data, info = group.parts[part], PARTS[part]
		if info and info.note and data then
			local note = info.note(data)
			if note then return note end
		end
		any = any or (data and info and info.restore ~= nil)
	end
	if not any then return L["Change it in its own options"] end
end

-- Put group `key` back as it was before this run.
local function RevertGroup(key)
	local group = session and session.undo.groups[key]
	if not group or group.reverted or ChangeNote(group) then return false end
	local run = session
	E:RunOutOfCombat(function()
		if session ~= run then return end
		local failed = false
		-- Newest part first, so parts that overlap end on the oldest values.
		for index = #group.partOrder, 1, -1 do
			local part = group.partOrder[index]
			local data = group.parts[part]
			if data and PARTS[part].restore then
				local ok, err = pcall(PARTS[part].restore, data)
				if not ok then
					failed = true
					geterrorhandler()(err)
				end
			end
		end
		group.reverted = true
		-- The step can be applied again in a later run; this one is over.
		Installer.Update()
		if Installer.ShowToast then
			Installer.ShowToast(failed and L["%s hit an error and was skipped. The error log has the details."]:format(L[group.title])
				or L["%s is back as it was"]:format(L[group.title]), failed)
		end
	end, "installer-revert-" .. key)
	return true
end
Installer.RevertGroup = RevertGroup

---------------------------------------------------------------------------
-- Full looks: one click for a whole look, made from what EldoUI already
-- has: a layout preset (its points, its accent and the styles it
-- suggests), a skin, the accent that goes with it and EldoUI's font. The
-- layout shows as a preview like a layout card; skin, accent and font
-- change at once like a skin card; the suggested styles apply with the
-- Styles step.
---------------------------------------------------------------------------
-- The three full looks for a layout: its own look (the skin it was made
-- for, which keeps following the layout), the client's own look and
-- Modern (flat). A look that is already the layout's own makes room for
-- Minimal Modern. High contrast is an accessibility choice, never a look.
local function FullLookArts(layoutKey)
	local own = E:LayoutSkin(layoutKey)
	local list = { { key = own, follow = true } }
	local client = E:ClientLook().artStyle
	local second = (client ~= own and E.artStyles[client]) and client or "MinimalModern"
	local third = "Modern"
	if third == own or third == second then third = (second ~= "MinimalModern" and own ~= "MinimalModern") and "MinimalModern" or "Blizzard" end
	for _, key in ipairs({ second, third }) do
		if E.artStyles[key] then list[#list + 1] = { key = key } end
	end
	return list
end
Installer.FullLookArts = FullLookArts

-- The layout a full look uses: the one picked on this run, else the profile's.
local function FullLookLayout()
	local key = session and session.layout.key or E.db.general.layout
	if E.layouts[key] then return key end
	return E.defaults.general.layout
end

-- r, g, b of an accent value ("RRGGBB" or "class").
local function AccentColor(accent)
	if accent == "class" then return E:ClassColor("player") end
	if type(accent) == "string" and accent:match("^%x%x%x%x%x%x$") then
		return tonumber(accent:sub(1, 2), 16) / 255, tonumber(accent:sub(3, 4), 16) / 255, tonumber(accent:sub(5, 6), 16) / 255
	end
	return Accent()
end

-- `follow`: the skin is the layout's own and keeps following the layout.
local function ApplyFullLook(art, key, accent, follow)
	if not (session and (E.artStyles[art] or follow)) then return false end
	key = key or FullLookLayout()
	local layout = E.layouts[key]
	if not layout then return false end
	Remember("look", "art")
	-- Repeat-safe: the layout in use (shown as a preview, applied in this
	-- run or the profile's own) is not applied again, so frames the player
	-- dragged stay where they are.
	local l = session.layout
	if E.db.general.layout ~= key then
		PreviewLayout(key)
	elseif l.key ~= nil and l.key ~= key then
		l.key = key
	end
	local run = session
	E:RunOutOfCombat(function()
		if session ~= run then return end
		local general = E.db.general
		E:SetSkin(art, { follow = follow and true or nil })
		if accent then
			general.accent, general.accentFromArt = accent, false
		else
			general.accent, general.accentFromArt = E:FullLookAccent(art, layout.accent)
		end
		general.font = E.defaults.general.font
		E:RefreshTheme()
		Installer.Update()
	end)
	local s = session.styles
	s.look = { art = art, layout = key, follow = follow and true or nil }
	-- The layout's suggested styles, in place of earlier picks.
	s.picked = {}
	SuggestStyles()
	if s.state == "applied" then s.state = "none" end
	return true
end
Installer.ApplyFullLook = ApplyFullLook

-- One full look card: its title, tag, text, sample and map, and whether it
-- is the look picked on this run.
function Installer.PaintFullLook(card, layoutKey, layout, layoutTitle, look, art)
	local accent = E:FullLookAccent(card.key, layout and layout.accent)
	local r, g, b = AccentColor(accent)
	local info = E.artStyleInfo[card.key]
	local skinTitle = info and L[info.title] or L["%s (not available): Modern is used"]:format(tostring(card.key))
	local accentName = E.accentNames[accent]
	accentName = accentName and L[accentName] or accent
	if card.follow then
		card.title:SetText(L["%s's own look"]:format(layoutTitle))
		card.desc:SetText(L["%s, the skin this layout was made for. It changes with the next layout you pick. Accent: %s."]:format(skinTitle, accentName))
		Tooltip(card, L["Full look: %s"]:format(card.title:GetText()), L["Sets the %s layout (a preview until Apply or Finish), the skin it was made for (%s) with its accent, EldoUI's font and the styles the layout suggests. The skin keeps following your layout. Back puts the old positions back."]:format(layoutTitle, skinTitle))
	else
		card.title:SetText(skinTitle)
		card.desc:SetText(L["%s Accent: %s."]:format(info and L[info.short or info.desc] or "", accentName))
		Tooltip(card, L["Full look: %s"]:format(skinTitle), L["Sets the %s layout (a preview until Apply or Finish), the %s skin with its accent, EldoUI's font and the styles the layout suggests. Back puts the old positions back."]:format(layoutTitle, skinTitle))
	end
	card.tag:SetShown(card.follow and true or false)
	local tagWidth = card.follow and math.ceil(card.tag:GetStringWidth() or 0) + 6 or 0
	card.title:SetWidth(math.max(40, (card:GetWidth() or 200) - 20 - tagWidth))
	card.tag:SetTextColor(E:TokenColor("accent"))
	E:PaintSkinSample(card.sample, card.key)
	Installer.DrawLayoutMap(card.map, layoutKey, { r, g, b }, MapStyles(layoutKey))
	local same = look ~= nil and look.layout == layoutKey and (look.follow and true or false) == (card.follow and true or false)
		and look.art == card.key and art == card.key
	card:SetSelected(same and session and (session.layout.key or E.db.general.layout) == layoutKey or false)
end

-- The skin cards of the Styles step as a grid under their label: as many
-- columns as fit (cards grow a little with Large text), every card as tall
-- as the tallest title. Returns where the style rows start.
Installer.SKIN_SAMPLE = 40
function Installer.LayoutSkinGrid(frame)
	local cards = frame.artCards or {}
	local top = frame.artTop + 5 + math.ceil(frame.artLabel:GetStringHeight() or 0) + 8
	local width = frame.maxX
	local scale = E.TextScale and E:TextScale() or 1
	local gap = 8
	local least = math.floor(132 * math.sqrt(math.max(1, scale)))
	local columns = math.max(1, math.min(#cards, math.floor((width + gap) / (least + gap))))
	local cardWidth = math.floor((width - (columns - 1) * gap) / columns)
	local height = 78
	for _, card in ipairs(cards) do
		card:SetWidth(cardWidth)
		card.title:SetWidth(cardWidth - 16)
		height = math.max(height, 8 + Installer.SKIN_SAMPLE + 6 + math.ceil(card.title:GetStringHeight() or 0) + 8)
	end
	for index, card in ipairs(cards) do
		-- The kit card keeps its least height on a resize: that is this one.
		card.minHeight = height
		card:SetHeight(height)
		card:ClearAllPoints()
		card:SetPoint("TOPLEFT", ((index - 1) % columns) * (cardWidth + gap), -(top + math.floor((index - 1) / columns) * (height + gap)))
	end
	local rows = math.ceil(#cards / columns)
	local bottom = top + rows * height + math.max(0, rows - 1) * gap + 10
	frame.artDivider:ClearAllPoints()
	frame.artDivider:SetPoint("TOPLEFT", 0, -bottom + 4)
	frame.artDivider:SetPoint("TOPRIGHT", 0, -bottom + 4)
	return bottom
end

---------------------------------------------------------------------------
-- Express setup: EldoUI's recommended pick on every step, applied in one
-- click from the Welcome step, then the list of what changed. It ends
-- where clicking Next through every step ends: auto repair (own gold),
-- junk selling and fast loot are turned on, and its text names them.
-- The accessibility switches stay as they are. Writing into a profile
-- another character set up keeps that profile's layout, look and
-- convenience features (alt safety), as the step by step setup does.
---------------------------------------------------------------------------
local function ExpressKeepsProfile(s)
	return TargetSetUp(s.profile.mode) and not s.rerun
end

-- The pack a run uses: the one picked on the Welcome step, else the first.
local Pack = {}

-- The other addons the pack turns off (it hands every overlapping job to
-- EldoUI), named before the click: "Also turns off A and B: ...", or nil.
function Pack.TurnsOffText()
	local C = Installer.Competitors
	if not (session and C and C.Changes) then return nil end
	local ok, _, off = pcall(C.Changes)
	if not ok or type(off) ~= "table" or #off == 0 then return nil end
	return L["Also turns off %s: EldoUI's modules take over their jobs."]:format(C.JoinNames(off))
end

function Pack.Run(key)
	key = key or (session and session.pack)
	return E.packs and (E.packs[key] or E.packs[E.packOrder[1]]) or {}
end

-- The layout a pack uses in this run: its own, else EldoUI's suggestion
-- for the screen.
function Pack.LayoutKey(pack)
	if pack.layout and E.layouts[pack.layout] then return pack.layout end
	local suggested = session and session.suggested and session.suggested.layout
	return E.layouts[suggested] and suggested or FullLookLayout()
end

-- The picks of every step from a pack: its layout, skin and accent, the
-- layout's styles with the pack's own on top, its role and modes.
-- Writing into a profile another character set up keeps that profile's
-- layout, look and role (alt safety), as Express always did.
function Pack.Picks(pack, full)
	local s = session
	-- The Keys and spells step's picks: the pack's key set and answers.
	if Installer.Keys and Installer.Keys.FromPack then Installer.Keys.FromPack(pack) end
	if not ExpressKeepsProfile(s) then
		local layoutKey = Pack.LayoutKey(pack)
		s.scale.choice = SuggestedScale()
		s.layout.key = layoutKey
		s.role.choice = pack.role or E:DetectRole() or s.role.choice
		s.role.classLayer = E:GetRoleClassLayer() ~= nil
		s.blizzard.mode = pack.blizzard or "recommended"
		s.blizzard.windowsMode = pack.blizzardWindows
		if pack.artStyle then
			ApplyFullLook(E:PackArtStyle(pack), layoutKey, pack.accent)
		else
			ApplyFullLook(E:LayoutSkin(layoutKey), layoutKey, pack.accent, true)
		end
		s.styles.picked, s.styles.auto = s.styles.picked or {}, s.styles.auto or {}
		for name, key in pairs(E:PackStyles({ layout = layoutKey, styles = pack.styles })) do
			if E.modules[name] then
				s.styles.choices[name], s.styles.picked[name] = key, true
				s.styles.auto[name] = nil
			end
		end
		for name, on in pairs(pack.modules or {}) do
			if E.modules[name] and not NOT_IN_SETUP[name] then s.modules.states[name] = on and true or false end
		end
		-- The pack's UI amount: only the modules that level lists, through
		-- the Modules step (its list and its undo).
		for name, on in pairs(pack.uiAmount and E.UIAmountTargets and E:UIAmountTargets(pack.uiAmount) or {}) do
			if not NOT_IN_SETUP[name] then s.modules.states[name] = on end
		end
	end
	if not full then return end
	if ChatAvailable() and pack.chat ~= "keep" then
		s.chat.mode = "tabs"
		s.chat.whispers, s.chat.loot, s.chat.channels, s.chat.classColors = true, true, true, true
	end
	for _, info in ipairs(GAME_SETTINGS) do s.cvars.picks[info.key] = true end
	for _, name in ipairs(E.addonSetupOrder) do
		if E:GetAddonSetupStatus(name) == "ready" and E.addonSetups[name].preselect ~= false then s.addons.selected[name] = true end
	end
	-- The same three the Convenience step starts with ticked; a profile
	-- set up before keeps its own.
	local convenience = not ExpressKeepsProfile(s)
	for _, key in ipairs(Installer.convenienceFirstRun) do s.convenience[key] = convenience end
	wipe(s.access.picks)
	-- EldoUI for every job another addon does (the recommended pick); the
	-- Finish page names every addon this turns off.
	for _, row in ipairs(Installer.Competitors.Rows()) do s.competitors.picks[row.key] = "eldoui" end
	s.express = true
end

-- Express: the pack's picks on every step, then Finish.
local function ExpressPicks(pack)
	session.modules.states = ModuleStates()
	Pack.Picks(pack or Pack.Run(), true)
end

---------------------------------------------------------------------------
-- Setup pages of modules and plugins (Core/Plugins.lua) as steps. They
-- only change something through their own Apply button.
---------------------------------------------------------------------------
local pageSteps = {} -- page key -> step

local function PageStep(page)
	local step = pageSteps[page.key]
	if step and step.page == page then return step end
	step = {
		key = "page:" .. page.key, page = page, manual = true,
		short = page.short, title = page.title, desc = page.desc,
		Build = function(frame)
			local ok, err = pcall(page.Build, frame, E:GetInstallKit())
			if not ok then geterrorhandler()(("EldoUI setup page %s failed to build: %s"):format(page.key, tostring(err))) end
		end,
		Refresh = function(frame)
			local ok, err = pcall(page.Refresh, frame)
			if not ok then geterrorhandler()(err) end
		end,
		HasChoice = function()
			local ok, result = pcall(page.HasChoice)
			return ok and result and true or false
		end,
		Summary = function()
			local ok, text = pcall(page.Summary)
			return ("%s: %s"):format(page.owner or "", ok and tostring(text) or page.title)
		end,
	}
	if page.Apply then
		step.Apply = function()
			E:SetInstallStepState(page.key, "applied")
			E:RunOutOfCombat(function()
				local ok, err = pcall(page.Apply)
				if not ok then geterrorhandler()(("EldoUI setup page %s failed: %s"):format(page.key, tostring(err))) end
			end)
			session[step.key].state = "applied"
		end
	end
	pageSteps[page.key] = step
	return step
end

---------------------------------------------------------------------------
-- Step definitions. Each step: key, title, short (sidebar label), desc,
-- Build(frame), Refresh(frame), and optionally Apply(), Revert(),
-- HasChoice(), Summary() and help (the "?" text, or a function that
-- returns it). A text built once in Build that highlights words goes
-- through LiveText, so a new accent repaints it.
---------------------------------------------------------------------------
local function StateWord(state, hasChoice)
	if state == "applied" then return Good(L["Applied"]) end
	if state == "preview" then return Warn(L["Showing now: Apply or Finish keeps it"]) end
	if hasChoice then return Warn(L["Applies at Finish"]) end
	if state == "skipped" then return Dim(L["Skipped"]) end
	return Dim(L["No change"])
end

---------------------------------------------------------------------------
-- What each step owns. A step's Apply (and its preview) writes only these
-- parts of the profile, merged on top of what is there:
--   db       profile paths ("general.uiScale"); a path owns everything under it
--   paths    a function that adds paths known only at run time (the module
--            settings a layout preset or a role names)
--   cvars    game settings (CVars) it may change, through E:SetCVar
--   game     what it changes outside the profile, in words
-- Every step of the installer's own (BASE) declares one; a setup page of
-- a module or plugin changes only what its own Apply says.
---------------------------------------------------------------------------
local STEP_OWNS = {
	-- Which profile the setup writes into: a profile switch, nothing in it.
	profile = { db = {}, game = "the profile this character uses" },
	scale = { db = { "general.uiScale" } },
	layout = {
		db = { "movers", "general.layout", "general.accent", "general.accentFromArt", "general.layoutHidden",
			"general.layoutPending", "general.roleMovers", "layoutApplied",
			-- A profile that follows its layout takes the layout's skin.
			"general.artStyle", "general.skinFollow", "general.accessBackup",
			-- Blizzard windows that follow the layout take its window look:
			-- the Skin switch of each window the player lets EldoUI change.
			"general.blizzardWindowsRestore" },
		-- Every module setting a preset names, and the switches of frames a
		-- preset keeps off.
		paths = function(list)
			for _, id in ipairs(E.windowLookElements or {}) do list[#list + 1] = ("blizzard.%s.skin"):format(id) end
			for _, key in ipairs(E:AllLayoutKeys()) do
				local layout = E.layouts[key]
				for moduleName, settings in pairs(layout.modules or {}) do
					for setting in pairs(settings) do list[#list + 1] = ("modules.%s.%s"):format(moduleName, setting) end
				end
			end
			for _, mover in pairs(E.movers or {}) do
				if mover.module and mover.enabledPath then list[#list + 1] = ("modules.%s.%s"):format(mover.module, mover.enabledPath[1]) end
			end
		end,
	},
	-- The full looks and skin cards change the skin (and whether it follows
	-- the layout), accent and font; Apply merges the picked style of each part.
	styles = {
		db = { "general.artStyle", "general.accent", "general.accentFromArt", "general.accentCustom", "general.font",
			"general.skinFollow", "general.skinVariant", "general.skinParts", "general.skinTitleFont" },
		paths = function(list)
			for name in pairs(E.styles) do list[#list + 1] = "modules." .. name end
		end,
	},
	access = { db = { "general.access", "general.accessBackup", "general.textScale" } },
	role = {
		db = { "general.role", "general.roleClass", "general.roleRestore", "general.roleMovers", "modules.ClickCast" },
		paths = function(list)
			local function Add(settings)
				for moduleName in pairs(settings or {}) do list[#list + 1] = "modules." .. moduleName end
			end
			for _, profile in pairs(E.roleProfiles or {}) do Add(profile.settings) end
			local layer = E.GetRoleClassLayer and E:GetRoleClassLayer()
			if layer then
				Add(layer.settings)
				-- The modules the class premade turns on, with their style.
				for _, moduleName in ipairs(layer.modules or {}) do list[#list + 1] = "modules." .. moduleName end
			end
		end,
	},
	modules = {
		db = {},
		paths = function(list)
			for name in E:IterateModules() do list[#list + 1] = ("modules.%s.enabled"):format(name) end
		end,
	},
	-- A replaced Blizzard frame sets the module mode that mirrors its
	-- switch (EldoUI's bags or Blizzard's, the loot windows).
	-- The Blizzard windows choice writes only the Skin switch of windows the
	-- player lets EldoUI change, and records what it wrote.
	blizzard = { db = { "blizzard", "windowMover", "general.blizzardWindows", "general.blizzardWindowsRestore", "modules.Bags.bagMode", "modules.Bags.bankMode", "modules.Bags.bagModeSynced",
		"modules.Bags.bankModeSynced", "modules.Loot.rollMode", "modules.Loot.lootMode" } },
	chat = { db = {}, game = "the character's chat windows, tabs, font size and class-colored names" },
	cvars = {
		db = {},
		cvars = function(list)
			for _, info in ipairs(GAME_SETTINGS) do
				for _, pair in ipairs(info.values) do list[#list + 1] = pair[1] end
			end
		end,
	},
	addons = { db = { "modules.Eldostar.provider" }, game = "other addons' own profiles, through their import functions",
		paths = function(list) if E.AddonPlacementPaths then E:AddonPlacementPaths(list) end end },
	-- The setting of every row the step lists (Core/Conveniences.lua).
	convenience = {
		db = {},
		paths = function(list)
			for _, row in ipairs(ConvenienceRows()) do
				if row.module then
					list[#list + 1] = ("modules.%s.%s"):format(row.module, row.setting)
				elseif not row.root then
					list[#list + 1] = row.setting
				end
			end
		end,
	},
	-- Account-wide picks (Core/AddonConflicts.lua); in the profile only the
	-- "show both" switches a part's pick writes.
	competitors = { db = { "modules.Characters.countsWithBagAddons", "modules.Battlegrounds.alongside" },
		game = "which other addons stay on for this character (turned off at Finish, after one reload)" },
	-- Keys and action buttons belong to the character, not the profile; the
	-- key map choice (how you play, later spells, other characters, keys
	-- shown on bars 1 to 3) and the paging fix belong to the profile.
	keys = { db = { "keymap" }, game = "the character's keys of bars 1 to 3, class spells and macros on empty buttons, and the spell ranks checked",
		paths = function(list)
			for bar = 1, 3 do
				for _, field in ipairs({ "pageShift", "pageCtrl", "pageAlt" }) do
					list[#list + 1] = ("modules.ActionBars.bars.%d.%s"):format(bar, field)
				end
			end
		end },
	-- Gamepad Mode UI's two switches; the game's gamepad interface stays
	-- the player's own setting.
	controller = { db = { "gamepadUI.always", "gamepadUI.ask" } },
	-- The alt setup (Core/InstallerAlt.lua): which profile this character
	-- uses, and of the profile only the click-cast list of this class when
	-- it has none yet; the rest is the character's own, through the chat,
	-- game settings, other addons and keys steps' own code.
	alt = { db = { "modules.ClickCast.sets" },
		game = "the profile this character uses, its chat windows and tabs, game settings, other addons' own profiles, and class spells and macros on empty buttons" },
}
Installer.STEP_OWNS = STEP_OWNS -- read-only, for plugins

-- Every profile path step `key` owns, the run-time ones included.
function Installer.OwnedPaths(key)
	local owns = STEP_OWNS[key]
	if not owns then return nil end
	local list = {}
	for _, path in ipairs(owns.db or {}) do list[#list + 1] = path end
	if owns.paths then owns.paths(list) end
	return list
end

-- The CVars step `key` may change.
function Installer.OwnedCVars(key)
	local owns = STEP_OWNS[key]
	local list = {}
	if owns and type(owns.cvars) == "function" then owns.cvars(list) end
	return list
end

local BASE = {}   -- the installer's own steps, in order (Finish comes last)
local FINISH      -- defined at the end

-- A profile EldoUI never touched gets its layout preset's module settings
-- and points (Minimap, Chat and Info Bar sizes, bar shapes, frames the
-- preset keeps off) at first login, before the setup is finished, and when
-- the setup is skipped. Of Blizzard's switches only the chat and action
-- bar ones change (Core/InstallerFirstRun.lua): EldoUI's chat and bars
-- show from the first load; every other Blizzard frame shows alone until
-- the Blizzard UI step lets EldoUI change it. Done once per profile.
function E:ApplyFreshLayout()
	local db = self.db
	if not (db and db.needsSetup) then return false end
	if self.InstallerFirstRun then self.InstallerFirstRun.TakeOver() end
	if db.layoutApplied then return false end
	-- In combat the request waits for the end of combat. Finish and Skip
	-- clear the setup marks right after asking, so the wait checks only
	-- the profile and the applied mark: a setup finished in combat still
	-- gets its layout, ahead of the steps Finish queued after it.
	self:RunOutOfCombat(function()
		if self.db ~= db or db.layoutApplied then return end
		local key = self.layouts[db.general.layout] and db.general.layout or self.defaults.general.layout
		-- A new profile: the layout's spots and settings, nothing dragged yet.
		if self:ApplySetup({ layout = key, look = "keep", resetPositions = true, source = "setup", silent = true, undo = false })
			and db.needsSetup then
			db.layoutApplied = true
		end
	end, "setup:freshlayout")
	return true
end

-- Close for good: no resume, and it doesn't open at login again.
local function SkipForGood()
	for index = #steps, 1, -1 do
		local step = steps[index]
		if step.Revert and session and session[step.key] and session[step.key].state == "preview" then step.Revert() end
	end
	EldoUIDB.installed = EldoUIDB.installed or {}
	if not Installed() then EldoUIDB.installed[E.charKey] = "skipped" end
	Installer.RecordSeen()
	-- A skipped setup still gets the layout's sizes and points.
	E:ApplyFreshLayout()
	E.db.needsSetup, E.db.layoutApplied, E.db.blizzardTakeover, E.db.blizzardTakeoverPending = nil, nil, nil, nil
	session = nil
	ForgetRun()
	finishing = true
	window:Hide()
	finishing = false
	E:Print(L["Setup skipped. Run it any time with %s."]:format(HL("/eui install")))
	Installer.SetupDone()
end
Installer.SkipForGood = SkipForGood

-- Runs when the profile's setup marks are cleared (Finish or Skip the
-- setup). Modules that hold something back until the setup is done hook
-- it: hooksecurefunc(E.Installer, "SetupDone", fn).
function Installer.SetupDone() end

-- EldoUI's language on the Welcome step. It reads and writes the one
-- saved language that General > EldoUI language edits, from the same list
-- (English (US) and every installed language pack, named without loading
-- it). A pick that differs from the language in use asks for the reload
-- at once; going back to the language in use takes that question back.
local languageReasons = {}

function Installer.LanguageValues()
	local values, order = E:LanguageChoices()
	local list = {}
	for _, code in ipairs(order) do list[#list + 1] = { code, values[code] } end
	return list
end

function Installer.SavedLanguage()
	local locale = E.global and E.global.locale
	return locale and locale.language
end

function Installer.PickLanguage(code)
	local locale = E.global and E.global.locale
	if not locale or locale.language == code then return end
	locale.language = code
	if code ~= E:GetLanguage() then
		local reason = L["EldoUI switches to %s after a reload."]:format(HL(E:LanguageChoices()[code] or code))
		languageReasons[reason] = true
		if session then session.needsReload = true end
		E:ShowReloadPrompt(reason)
		return
	end
	-- Back to the language in use: a question that only asked for the
	-- language goes away.
	local prompt = E:GetReloadPrompt()
	if not (prompt and prompt:IsShown() and type(prompt.reasons) == "table") then return end
	for _, reason in ipairs(prompt.reasons) do
		if not languageReasons[reason] then return end
	end
	E:HideReloadPrompt()
end

BASE[#BASE + 1] = {
	-- `short` stays English (/eui install <step> matches it) and is shown as
	-- L[step.short]: L["Welcome"], L["Finish"]
	key = "profile", short = "Welcome", title = "Welcome to EldoUI",
	desc = "A few short steps set up the whole UI. Every step is optional: Skip leaves that part as it is.",
	help = Key("EldoUI keeps its settings in profiles. \"The EldoUI profile\" starts a new one from EldoUI's defaults and leaves your current profile untouched, so you can switch back in /eui > Profiles. \"My current profile\" sets up the profile you use now.\n\nWhen another character already set up the EldoUI profile, \"Use the EldoUI profile as it is\" puts this character on it and changes nothing in it: the layout, scale, role and Blizzard UI steps start on keep, and only this character's chat tabs, addon profiles and click-casting are suggested. Starting it fresh asks twice and names the characters that use it.\n\nA preset pack is a whole UI: a layout, a skin, a style for each part of the UI, a role and the Blizzard UI and chat setup. Apply sets up every step with it; Customize goes through the steps with its picks filled in.\n\nEldoUI's chat and action bars show from your first login. For every other part, until the Blizzard UI step lets EldoUI replace a Blizzard frame, EldoUI's version of it steps aside, so nothing shows twice.\n\nBefore the first change EldoUI keeps a backup of the profile it writes into. \"Undo the last setup\" (or /eui install undo) puts it back, and \"Back up my setup\" keeps a named copy in your profiles."),
	Build = function(frame)
		local intro = LiveText(Paragraph(frame, E.tokens.size.body), function()
			return L["Apply a preset pack in one click, or go through the steps: each one shows its pick at once, and %s puts it back."]:format(HL(L["Back"]))
		end)
		frame.intro = intro
		intro:SetPoint("TOPLEFT", 0, 0)
		intro:SetPoint("TOPRIGHT", 0, 0)
		local header = E:CreateText(frame, E.tokens.size.cardTitle, "LEFT")
		header:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", 0, -16)
		header:SetText(L["Which profile should the setup write into?"])
		frame.header = header
		-- EldoUI's language, at the right end of the header's line: the same
		-- choice as General > EldoUI language (one saved language, the same
		-- list and flags). Shown only when there is more than one language
		-- to pick.
		local language = CreateFrame("Frame", nil, frame)
		language:SetPoint("RIGHT", header, "LEFT", CONTENT_W, 0)
		language.label = E:CreateText(language, E.tokens.size.body, "LEFT")
		language.label:SetText(L["EldoUI language"])
		language.box = Kit.Dropdown(language, {
			values = Installer.LanguageValues,
			get = Installer.SavedLanguage,
			set = Installer.PickLanguage,
			icon = function(code) return E:LocaleFlag(code) end,
			tipTitle = L["EldoUI language"],
			tip = L["Language of EldoUI's own texts: settings, windows, tooltips and chat messages. The game's own texts keep the game's language. EldoUI builds its windows once, so the change shows after a reload."],
		})
		language.box:SetPoint("RIGHT", 0, 0)
		language.label:SetPoint("RIGHT", language.box, "LEFT", -8, 0)
		frame.language = language
		frame.choices = {}
		-- "use" shows only when the shared EldoUI profile is set up (alts).
		for index, mode in ipairs({ "use", "new", "current" }) do
			local choice = Choice(frame, 400, 84, "", "", function()
				PickProfileMode(mode)
				Installer.Update()
			end)
			choice.mode = mode
			frame.choices[index] = choice
		end
		frame.note = Secondary(Paragraph(frame, E.tokens.size.label, ""))
		frame.note:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -106)
		frame.note:SetWidth(CONTENT_W)

		-- Preset packs: a whole UI in one click (Express setup), or the
		-- steps with the pack's picks filled in (Customize).
		-- The options window's section card (E.UIKit.SectionCard): the
		-- label above the box, the pack's text beside the Apply button.
		local express = E.UIKit.SectionCard(frame, { label = L["Preset packs"] })
		express:SetPoint("TOPLEFT", frame.note, "BOTTOMLEFT", 0, -12)
		express:SetWidth(CONTENT_W)
		express.desc = Secondary(Paragraph(express.body, E.tokens.size.label, ""))
		express.desc:SetPoint("TOPLEFT", 12, -10)
		express.desc:SetWidth(CONTENT_W - 24)
		express.cards = {}
		local count = math.max(1, #E.packOrder)
		local gap = 8
		local cardWidth = math.floor((CONTENT_W - 24 - (count - 1) * gap) / count)
		local screenW, screenH = UIParent:GetWidth(), UIParent:GetHeight()
		local shape = (screenW and screenH and screenH > 0) and math.min(screenW / screenH, 3.6) or 16 / 9
		express.shape = shape
		-- The miniature keeps the screen's shape, at most 64 units tall
		-- (50 with Large text, so the page keeps its room).
		local function PackMapSize()
			local width = cardWidth - 20
			local height = math.floor(width / shape + 0.5)
			local cap = E.db.general.access and E.db.general.access.largeText and 50 or 64
			if height > cap then height, width = cap, math.floor(cap * shape + 0.5) end
			express.mapWidth, express.mapHeight = width, height
		end
		express.MapSize = PackMapSize
		PackMapSize()
		express.cardWidth, express.gap = cardWidth, gap
		for index, key in ipairs(E.packOrder) do
			local pack = E.packs[key]
			local card = Choice(express, cardWidth, express.mapHeight + 40, L[pack.title], "", function()
				session.pack = key
				Installer.Update()
			end)
			card.desc:Hide()
			card.minHeight = nil
			card.key = key
			card.map = E.UIKit.SectionCard(card)
			card.map:SetSize(express.mapWidth, express.mapHeight)
			card.map:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", 0, -6)
			card.map:EnableMouse(false)
			Tooltip(card, L[pack.title], L[pack.desc])
			express.cards[index] = card
		end
		express.button = Button(express.body, { text = L["Apply"], kind = "primary", minWidth = 150, onClick = function() Installer.Express() end })
		express.button:SetPoint("TOPRIGHT", -12, -10)
		Tooltip(express.button, L["Apply the pack"], function(tooltip)
			Kit.TipText(tooltip, L["Sets up every step with the pack at once: also chat tabs, game settings and other addons' profiles, and it turns on auto repair (your own gold), junk selling and fast loot. Then it shows your keys and spells, which change only when you press Apply there, and afterwards what changed, each part with Revert this."])
			local off = Pack.TurnsOffText()
			if off then Kit.TipText(tooltip, off) end
		end)
		frame.express = express

		-- Undo and skip, at the bottom of the page.
		frame.undo = Button(frame, L["Undo the last setup"], 200, function() E:UndoInstall() end)
		frame.undo:SetPoint("BOTTOMLEFT", 0, 0)
		frame.undoText = Secondary(E:CreateText(frame, E.tokens.size.label, "LEFT"))
		frame.undoText:SetPoint("LEFT", frame.undo, "RIGHT", 12, 0)
		-- Up to the buttons on the right (Refresh), two lines at most; the
		-- button's tooltip has the whole text.
		frame.undoText:SetMaxLines(2)
		frame.skipAll = Button(frame, L["Skip the setup"], 160, function() SkipForGood() end)
		frame.skipAll:SetPoint("BOTTOMRIGHT", 0, 0)
		-- A named copy of the profile before anything changes.
		frame.backup = Button(frame, { text = L["Back up my setup"], minWidth = 160, onClick = function()
			local name = Installer.BackupProfile()
			if name then Installer.ShowToast(L["Saved a copy as %s. It is in /eui > Profiles."]:format(HL(name))) end
			Installer.Update()
		end })
		frame.backup:SetPoint("RIGHT", frame.skipAll, "LEFT", -8, 0)
		Tooltip(frame.backup, L["Back up my setup"], L["Keeps a copy of the profile you use now under a new name, before the setup changes anything. Switch to it in /eui > Profiles."])
		Tooltip(frame.skipAll, L["Skip the setup"], L["Close the setup for good: it doesn't open at login again. Closing the window instead pauses it, and /eui install goes on where you stopped."])
	end,
	Refresh = function(frame)
		-- The language row takes no room of its own: it sits beside the
		-- header, and its label steps aside when the line is too short for
		-- it (Large text); the box's tooltip names it then.
		local language = frame.language
		local languages = #Installer.LanguageValues() > 1
		language:SetShown(languages)
		if languages then
			local scale = E:TextScale()
			local box = language.box
			box:SetSize(math.floor(150 * scale + 0.5), math.max(E.tokens.height.button, math.ceil(E.tokens.size.label * scale + 8)))
			box:Refresh()
			local room = CONTENT_W - math.ceil(frame.header:GetUnboundedStringWidth() or 0) - 24
			local labelWidth = math.ceil(language.label:GetUnboundedStringWidth() or 0) + 8
			local labeled = labelWidth + box:GetWidth() <= room
			language.label:SetShown(labeled)
			language:SetSize((labeled and labelWidth or 0) + box:GetWidth(), box:GetHeight())
		end
		local p = session.profile
		local shared = SharedProfileReady() or p.mode == "use"
		local users, count = OtherUsers(PROFILE)
		local texts = {
			use = { L["Use the EldoUI profile as it is"], (count > 0 and L["\"%s\" is set up (on %s). Its layout and styles stay; this character gets its own chat tabs, addon profiles and click-casting."]:format(PROFILE, users)
				or L["\"%s\" is set up. Its layout and styles stay; this character gets its own chat tabs, addon profiles and click-casting."]:format(PROFILE)) },
			new = shared and { L["Start the EldoUI profile fresh"], L["\"%s\" goes back to EldoUI's defaults, for every character that uses it. You are asked twice."]:format(PROFILE) }
				or { L["The EldoUI profile"], L["A profile called \"%s\", fresh from EldoUI's defaults. Your current profile stays as it is, so you can switch back in /eui > Profiles."]:format(PROFILE) },
			current = { L["My current profile"], L["Set up \"%s\", the profile this character uses now. Parts you skip keep their settings."]:format(E.profileName) },
		}
		local shown = {}
		for _, choice in ipairs(frame.choices) do
			local visible = choice.mode ~= "use" or shared
			choice:SetShown(visible)
			if visible then shown[#shown + 1] = choice end
		end
		local gap = 12
		local width = math.floor((CONTENT_W - gap * (#shown - 1)) / #shown)
		for index, choice in ipairs(shown) do
			local text = texts[choice.mode]
			choice.title:SetText(text[1])
			choice.desc:SetText(text[2])
			choice:SetWidth(math.min(400, width))
			choice:ClearAllPoints()
			if index == 1 then
				choice:SetPoint("TOPLEFT", frame.header, "BOTTOMLEFT", 0, -10)
			else
				choice:SetPoint("LEFT", shown[index - 1], "RIGHT", gap, 0)
			end
			choice:SetSelected(choice.mode == p.mode)
			choice:SetEnabledLook(not p.done)
		end
		-- The cards share the height of the tallest text; the note
		-- starts under them.
		local height = 0
		for _, choice in ipairs(shown) do
			choice.minHeight = 84
			height = math.max(height, choice:FitHeight())
		end
		for _, choice in ipairs(shown) do
			choice.minHeight = height
			choice:FitHeight()
		end
		frame.note:ClearAllPoints()
		frame.note:SetPoint("TOPLEFT", frame.header, "BOTTOMLEFT", 0, -(10 + height + 12))
		if p.done then
			-- A run is kept per profile: on another profile, /eui install
			-- starts over and asks the profile question again.
			frame.note:SetText(L["Setting up the profile %s. To set up another profile instead, switch to it (or make a new one) on the Profiles page, then run %s: the setup starts over there."]:format(HL(E.profileName), HL("/eui install")))
		elseif session.rerun then
			frame.note:SetText(L["You ran the setup on this character before. Every step starts on \"keep\", so clicking through changes nothing, and EldoUI asks before it changes your profile."])
		else
			frame.note:SetText(L["%s goes through the steps with the pack filled in. Closing this window pauses the setup."]:format(HL(L["Customize"])))
		end
		-- The pack cards: the picked one's text, each with its own map.
		local express = frame.express
		local pack = Pack.Run()
		local off = Pack.TurnsOffText()
		if ExpressKeepsProfile(session) then
			express.desc:SetText(L["This profile is set up already, so Apply keeps its scale, layout, look, role, Blizzard UI switches and convenience features, and sets up this character's chat tabs, game settings and other addons' profiles."]
				.. (off and (" " .. off) or ""))
		else
			express.desc:SetText(("%s %s"):format(L[pack.desc or ""], L["Apply also turns on auto repair (your own gold), junk selling and fast loot."])
				.. (off and (" " .. off) or ""))
		end
		express.MapSize()
		local cardHeight = 0
		for _, card in ipairs(express.cards) do
			card.map:SetSize(express.mapWidth, express.mapHeight)
			cardHeight = math.max(cardHeight, 8 + math.ceil(card.title:GetStringHeight() or 0) + 6 + express.mapHeight + 6)
		end
		-- The text sits beside the Apply button; the cards start under the
		-- taller of the two.
		express.button:SetText(L["Apply %s"]:format(L[pack.title or ""]))
		E.UIKit.FitButton(express.button, 150)
		express.desc:SetWidth(CONTENT_W - 24 - math.ceil(express.button:GetWidth() or 150) - 12)
		local top = math.max(E.tokens.height.button, math.ceil(express.desc:GetStringHeight() or 0))
		for index, card in ipairs(express.cards) do
			local cardPack = E.packs[card.key]
			local layoutKey = Pack.LayoutKey(cardPack)
			local art = cardPack.artStyle and E:PackArtStyle(cardPack) or E:LayoutSkin(layoutKey)
			local accent = cardPack.accent or E:FullLookAccent(art, E.layouts[layoutKey] and E.layouts[layoutKey].accent)
			local r, g, b = AccentColor(accent)
			Installer.DrawLayoutMap(card.map, layoutKey, { r, g, b }, E:PackStyles({ layout = layoutKey, styles = cardPack.styles }))
			card.minHeight = cardHeight
			card:SetHeight(cardHeight)
			card:ClearAllPoints()
			card:SetPoint("TOPLEFT", express.body, "TOPLEFT", 12 + (index - 1) * (express.cardWidth + express.gap), -(10 + top + 10))
			card:SetSelected(card.key == session.pack)
			card:SetEnabledLook(not ExpressKeepsProfile(session))
		end
		express:SetBodyHeight(10 + top + 10 + cardHeight + 12)
		frame.backup:SetEnabled(not session.backedUp)
		frame.backup:SetText(session.backedUp and L["Backed up"] or L["Back up my setup"])
		local backup = Installer.GetBackup()
		frame.undo:SetShown(backup ~= nil)
		frame.undoText:SetShown(backup ~= nil)
		if backup then
			local when = backup.time and E:ShortDate(backup.time) or "?"
			local undoText = backup.attach and L["Puts this character back on %s, as before the alt setup of %s."]:format(HL(backup.previous or backup.profile), when)
				or L["Puts %s back as it was on %s."]:format(HL(backup.profile), when)
			frame.undoText:SetText(undoText)
			Tooltip(frame.undo, L["Undo the last setup"], undoText)
			local left, right = frame.undo:GetRight(), (frame.backup:IsShown() and frame.backup or frame.skipAll):GetLeft()
			frame.undoText:SetWidth(left and right and math.max(right - left - 24, 60) or 260)
		end
		frame.skipAll:SetShown(not session.rerun)
	end,
	HasChoice = function() return true end,
	Summary = function()
		local p = session.profile
		if p.done then
			return (p.fresh and L["Profile %s (fresh)"] or L["Profile %s"]):format(HL(E.profileName))
		end
		if p.mode == "use" then return L["Profile %s (as it is)"]:format(E:Highlight(PROFILE)) end
		return L["Profile %s"]:format(HL(p.mode == "new" and PROFILE or E.profileName))
	end,
}

BASE[#BASE + 1] = {
	key = "scale", short = "UI scale", title = "UI scale",
	desc = "How big the whole UI is. EldoUI is made for 1440p; Auto keeps that size on every screen.",
	Build = function(frame)
		local width, height = GetPhysicalScreenSize()
		local info = Paragraph(frame, E.tokens.size.body, "")
		info:SetPoint("TOPLEFT", 0, 0)
		info:SetPoint("TOPRIGHT", 0, 0)
		frame.info = info
		local pixel = E:GetPixelPerfectScale()
		local auto = E:GetAutoScale()
		LiveText(info, function()
			local text = L["Your screen is %s. EldoUI is made for 1440p, so Auto draws every screen as the 2560x1440 canvas (%s), a little taller on a screen narrower than 16:9: every layout looks exactly as designed, smaller on a smaller screen and bigger on a bigger one."]:format(HL(("%dx%d"):format(width or 0, height or 0)), HL(("%.4f"):format(E:GetLayoutCanvasScale())))
			if math.abs(auto - pixel) < 0.0001 then
				text = text .. " " .. L["On your screen that is also pixel perfect: one UI unit is one screen pixel."]
			end
			return text
		end)

		frame.choices = {}
		local function Add(choiceValue, title, desc)
			local choice = Choice(frame, 260, 64, title, desc, function()
				Touch("scale")
				session.scale.choice = choiceValue
				PreviewScale()
				Installer.Update()
			end)
			choice.value = choiceValue
			local index = #frame.choices + 1
			if index == 1 then
				choice:SetPoint("TOPLEFT", info, "BOTTOMLEFT", 0, -16)
			else
				choice:SetPoint("TOPLEFT", frame.choices[index - 1], "TOPRIGHT", 12, 0)
			end
			frame.choices[index] = choice
		end
		Add("auto", L["Auto: 1440p (%.4f)"]:format(auto), L["The 1440p canvas the layouts are made for, on any screen. Follows your screen if it changes."])
		if math.abs(auto - pixel) >= 0.0001 then
			local _, advice = E:ScaleAdvice("pixel")
			Add("pixel", L["Pixel perfect (%.4f)"]:format(pixel),
				L["One UI unit is one screen pixel on this screen. Frames keep their 1440p size, so on a smaller screen they can overlap."]
					.. (advice and ("\n\n" .. advice) or ""))
		end
		-- The cards grow with their descriptions; the row is as tall as the
		-- tallest, so what follows sits under all of them at any text size.
		local row = CreateFrame("Frame", nil, frame)
		row:SetPoint("TOPLEFT", frame.choices[1], "TOPLEFT")
		row:SetSize(1, 1)
		local function FitRow()
			local tallest = 1
			for _, choice in ipairs(frame.choices) do tallest = math.max(tallest, choice:GetHeight() or 0) end
			row:SetHeight(tallest)
		end
		for _, choice in ipairs(frame.choices) do choice:HookScript("OnSizeChanged", FitRow) end
		FitRow()

		-- Custom value: slider and value box.
		local label = E:CreateText(frame, E.tokens.size.body, "LEFT")
		label:SetPoint("TOPLEFT", row, "BOTTOMLEFT", 0, -24)
		label:SetText(L["Custom scale"])
		local slider = CreateFrame("Slider", nil, frame)
		slider:SetOrientation("HORIZONTAL")
		slider:SetSize(320, 10)
		slider:SetPoint("LEFT", label, "RIGHT", 16, 0)
		E:SetTemplate(slider, true)
		slider:SetThumbTexture(E.media.flat)
		local thumb = slider:GetThumbTexture()
		thumb:SetSize(8, 18)
		thumb:SetVertexColor(Accent())
		slider:SetMinMaxValues(0.4, 1.2)
		slider:SetValueStep(0.01)
		slider:SetObeyStepOnDrag(true)
		E.UIKit.CollectKeyControl(slider, nil, E.UIKit.StepKeySlider)
		local value = E:CreateText(frame, E.tokens.size.body, "LEFT")
		value:SetPoint("LEFT", slider, "RIGHT", 12, 0)
		frame.slider, frame.value = slider, value
		local function Round(v) return math.floor(v * 100 + 0.5) / 100 end
		-- The UI changes size with the scale, so the preview waits until the
		-- mouse lets go of the slider (E.UIKit.SliderCommit).
		local Feed = E.UIKit.SliderCommit(slider, {
			preview = function(v)
				if not session then return end
				session.scale.choice = Round(v)
				for _, choice in ipairs(frame.choices) do choice:SetSelected(false) end
			end,
			commit = function(v)
				if not session then return end
				Touch("scale")
				session.scale.choice = Round(v)
				PreviewScale()
				Installer.Update()
			end,
		})
		-- How the value under the slider suits the layouts (E:ScaleAdvice).
		local advice = Paragraph(frame, E.tokens.size.label, "")
		advice:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -14)
		advice:SetWidth(CONTENT_W)
		frame.advice = advice
		local TIER_COLOR = { recommended = "good", supported = "secondary", small = "warn", large = "warn" }
		function frame.ShowAdvice(choice)
			local tier, text = E:ScaleAdvice(choice)
			advice:SetText(text or "")
			local color = E.tokens.text[TIER_COLOR[tier or ""] or "secondary"]
			advice:SetTextColor(color[1], color[2], color[3])
		end
		slider:SetScript("OnValueChanged", function(_, v)
			value:SetText(("%.2f"):format(Round(v)))
			frame.ShowAdvice(Round(v))
			if frame.updating then return end
			Feed(v)
		end)
		Tooltip(slider, L["Custom scale"], L["Drag and let go to preview. 0.40 to 1.20."])

		local note = Secondary(Paragraph(frame, E.tokens.size.label, L["The preview changes the UI at once. Back or closing this window puts your old scale back. You can change it later in /eui > General or with /eui scale."]))
		note:SetPoint("TOPLEFT", advice, "BOTTOMLEFT", 0, -14)
		-- A width, not a right anchor: the text keeps the height of its lines.
		note:SetWidth(CONTENT_W)
	end,
	Refresh = function(frame)
		local choice = session.scale.choice
		local matched = false
		for _, button in ipairs(frame.choices) do
			local on = choice ~= nil and button.value == choice
			button:SetSelected(on)
			matched = matched or on
		end
		frame.updating = true
		frame.slider:SetValue(ScaleValue(choice))
		frame.value:SetText(("%.2f"):format(ScaleValue(choice)))
		frame.updating = false
		frame.ShowAdvice(choice or E.db.general.uiScale)
		frame.value:SetTextColor(matched and 0.68 or 1, matched and 0.68 or 1, matched and 0.72 or 1)
	end,
	Apply = Work.ApplyScaleStep,
	Revert = RevertScale,
	HasChoice = function() return session.scale.choice ~= nil end,
	Summary = function()
		local choice = session.scale.choice
		if choice == nil then return L["UI scale: keep"] end
		if choice == "auto" then return L["UI scale: %s"]:format(L["auto, 1440p (%.4f)"]:format(E:GetAutoScale())) end
		if choice == "pixel" then return L["UI scale: %s"]:format(L["pixel perfect (%.4f)"]:format(E:GetPixelPerfectScale())) end
		return L["UI scale: %s"]:format(("%.2f"):format(choice))
	end,
}

BASE[#BASE + 1] = {
	key = "layout", short = "Layout", title = "Layout",
	desc = "Where every frame sits. Click a layout to preview it, then Apply or go on; Back puts your old positions back.",
	Build = function(frame)
		frame.keep = Choice(frame, 200, 26, L["Keep my layout"], nil, function()
			Touch("layout")
			PreviewLayout(nil)
			Installer.Update()
		end)
		frame.keep:SetPoint("TOPLEFT", 0, 0)
		Tooltip(frame.keep, L["Keep my layout"], L["Leave every frame where it is now."])
		-- Quick path: the suggestions of every other step, straight to the review.
		local quick = Button(frame, L["Review and finish"], 160, function() Installer.Go(#steps) end)
		quick:SetPoint("TOPRIGHT", 0, 0)
		Tooltip(quick, L["Review and finish"], L["Go straight to the review page with this layout and the picks of the other steps as they are. Finish applies them; Change goes back to any step."])
		-- The whole description of the picked layout (or the one under the
		-- mouse) reads under the grid; the cards show the title and the map.
		frame.detail = Paragraph(frame, E.tokens.size.body, "")
		frame.detail:SetPoint("BOTTOMLEFT", 0, 0)
		frame.detail:SetPoint("BOTTOMRIGHT", 0, 0)
		frame.detail:SetJustifyV("BOTTOM")
		local holder = CreateFrame("Frame", nil, frame)
		holder:SetPoint("TOPLEFT", 0, -36)
		holder:SetPoint("BOTTOMRIGHT", frame.detail, "TOPRIGHT", 0, 10)
		local _, child = ScrollArea(holder)
		frame.child = child
		frame.cards = {}
		local columns, gap = 4, 8
		local cardWidth = math.floor((CONTENT_W - 22 - (columns - 1) * gap) / columns)
		-- The map has the screen's shape (16:9 if the screen size isn't known yet).
		local mapWidth = cardWidth - 20
		local screenW, screenH = UIParent:GetWidth(), UIParent:GetHeight()
		local shape = (screenW and screenH and screenH > 0) and math.min(screenW / screenH, 3.6) or 16 / 9
		local mapHeight = math.floor(mapWidth / shape + 0.5)
		local cardHeight = mapHeight + 40
		frame.columns, frame.gap, frame.cardWidth, frame.mapHeight = columns, gap, cardWidth, mapHeight
		local function ShowDetail(key)
			local shown = E.layouts[key]
			if shown then
				frame.detail:SetText(("%s  %s"):format(HL(E:LayoutTitle(key)), shown.desc and L[shown.desc] or ""))
			else
				frame.detail:SetText(L["Keep my layout"] .. "  " .. L["Leave every frame where it is now."])
			end
		end
		frame.ShowDetail = ShowDetail
		for index, key in ipairs(E.layoutOrder) do
			local layout = E.layouts[key]
			local title = E:LayoutTitle(key)
			local card = Choice(child, cardWidth, cardHeight, title, "", function()
				Touch("layout")
				PreviewLayout(key)
				Installer.Update()
			end)
			card.desc:Hide()
			card.minHeight = nil
			card:HookScript("OnEnter", function() ShowDetail(key) end)
			card:HookScript("OnLeave", function() ShowDetail(session and session.layout.key) end)
			card.key = key
			-- The layout's own accent color: a stripe and the HUD on its map.
			local accent
			if type(layout.accent) == "string" and layout.accent:match("^%x%x%x%x%x%x$") then
				accent = { tonumber(layout.accent:sub(1, 2), 16) / 255, tonumber(layout.accent:sub(3, 4), 16) / 255, tonumber(layout.accent:sub(5, 6), 16) / 255 }
				local stripe = card:CreateTexture(nil, "ARTWORK")
				stripe:SetPoint("TOPLEFT", E.pixel, -E.pixel)
				stripe:SetPoint("BOTTOMLEFT", E.pixel, E.pixel)
				stripe:SetWidth(3)
				stripe:SetColorTexture(accent[1], accent[2], accent[3], 1)
			end
			local map = E.UIKit.SectionCard(card)
			map:SetSize(mapWidth, mapHeight)
			map:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", 0, -6)
			map:EnableMouse(false)
			card.map, card.accent = map, accent
			Installer.DrawLayoutMap(map, key, accent, MapStyles(key))
			Tooltip(card, layout.title or key, layout.desc and L[layout.desc])
			frame.cards[#frame.cards + 1] = card
		end
	end,
	Refresh = function(frame)
		local l = session.layout
		frame.keep:SetSelected(l.key == nil)
		for _, card in ipairs(frame.cards) do
			card:SetSelected(card.key == l.key)
			-- The map shows the frames as large as the picked styles make them.
			Installer.DrawLayoutMap(card.map, card.key, card.accent, MapStyles(card.key))
		end
		frame.ShowDetail(l.key)
		-- Cards as tall as their title (Large text) plus the map.
		local height = 0
		for _, card in ipairs(frame.cards) do
			height = math.max(height, 8 + math.ceil(card.title:GetStringHeight() or 0) + 6 + frame.mapHeight + 10)
		end
		for index, card in ipairs(frame.cards) do
			card:SetHeight(height)
			card:ClearAllPoints()
			local column = (index - 1) % frame.columns
			local row = math.floor((index - 1) / frame.columns)
			card:SetPoint("TOPLEFT", column * (frame.cardWidth + frame.gap), -row * (height + frame.gap))
		end
		frame.child:SetHeight(math.ceil(#frame.cards / frame.columns) * (height + frame.gap))
	end,
	Apply = Work.ApplyLayoutStep,
	Revert = RevertLayout,
	-- The layout in use is never applied again (frames the player dragged
	-- stay), so picking it changes nothing.
	HasChoice = function()
		local l = session.layout
		return l.key ~= nil and (l.state == "preview" or l.key ~= E.db.general.layout)
	end,
	Summary = function()
		local l = session.layout
		local key = l.key
		if not key then return L["Layout: keep"] end
		local title = E.layouts[key] and E.layouts[key].title or key
		if l.state ~= "preview" and l.state ~= "applied" and key == E.db.general.layout then
			return L["Layout: %s (in use)"]:format(title)
		end
		return L["Layout: %s"]:format(title)
	end,
}

-- The style rows of the Styles step: buttons wrap to a new line when the
-- row is full, and each row is as tall as its buttons and its label (both
-- grow with Large text). Returns the height used under the skins.
local function LayoutStyleRows(frame)
	local y = frame.rowsTop
	local labelWidth, maxX = frame.labelWidth, frame.maxX
	local buttonHeight = math.max(24, math.ceil(E.tokens.size.body * (E.TextScale and E:TextScale() or 1)) + 8)
	for _, row in ipairs(frame.rows) do
		row.label:ClearAllPoints()
		row.label:SetPoint("TOPLEFT", 0, -y - 5)
		local x, rowY = labelWidth, y
		for _, button in ipairs(row.buttons) do
			local width = math.max(56, math.ceil(button.title:GetStringWidth()) + 20)
			button:SetSize(width, buttonHeight)
			if x + width > maxX and x > labelWidth then
				x = labelWidth
				rowY = rowY + buttonHeight + 4
			end
			button:ClearAllPoints()
			button:SetPoint("TOPLEFT", x, -rowY)
			x = x + width + 4
		end
		y = math.max(rowY + buttonHeight + 4, y + 5 + math.ceil(row.label:GetStringHeight()) + 6) + 6
		row.divider:ClearAllPoints()
		row.divider:SetPoint("TOPLEFT", 0, -y + 4)
		row.divider:SetPoint("TOPRIGHT", 0, -y + 4)
	end
	return y
end

BASE[#BASE + 1] = {
	key = "styles", short = "Styles", title = "Styles",
	desc = "Pick a skin for every window and panel, then a look for each part of the UI, or Keep to leave a part as it is. Looks that don't fit your layout are grayed out.",
	Build = function(frame)
		local _, child = ScrollArea(frame)
		frame.rows = {}
		local labelWidth = 170
		local maxX = CONTENT_W - 22 - 4
		-- Full looks: layout, skin, accent, font and the layout's styles in
		-- one click, each card a small preview of the look.
		local lookLabel = E:CreateText(child, E.tokens.size.body, "LEFT")
		lookLabel:SetPoint("TOPLEFT", 0, -5)
		lookLabel:SetText(L["Full looks"])
		-- What every card sets is said once here (Refresh names the layout and font).
		frame.lookNote = Secondary(Paragraph(child, E.tokens.size.label, ""))
		frame.lookNote:SetPoint("TOPLEFT", labelWidth, -6)
		frame.lookNote:SetPoint("TOPRIGHT", child, "TOPRIGHT", 0, -6)
		frame.lookCards = {}
		local arts = FullLookArts(FullLookLayout())
		local gap = 8
		local lookWidth = math.floor((CONTENT_W - 22 - (#arts - 1) * gap) / math.max(1, #arts))
		local sampleWidth = lookWidth - 20
		local sampleHeight = math.floor(sampleWidth * 9 / 16 + 0.5)
		local lookHeight = sampleHeight + 88
		local lookTop = 34
		frame.lookGap, frame.lookWidth, frame.sampleHeight = gap, lookWidth, sampleHeight
		for index, look in ipairs(arts) do
			local card
			card = Choice(child, lookWidth, lookHeight, "", "", function()
				Touch("layout")
				Touch("styles")
				ApplyFullLook(card.key, nil, nil, card.follow)
				Installer.Update()
			end)
			card:SetPoint("TOPLEFT", (index - 1) * (lookWidth + gap), -lookTop)
			card.key, card.follow = look.key, look.follow
			-- The client's own look carries a tag instead of a second pair of brackets.
			card.tag = E:CreateText(card, E.tokens.size.small, "RIGHT")
			card.tag:SetPoint("TOPRIGHT", -10, -9)
			card.tag:SetText(L["Recommended"])
			card.title:ClearAllPoints()
			-- Left of the tag, three lines at most so a long layout name
			-- still fits under Large text (the width is set in
			-- Installer.PaintFullLook, by the tag shown).
			card.title:SetPoint("TOPLEFT", 10, -8)
			card.title:SetWordWrap(true)
			card.title:SetMaxLines(3)
			-- The preview: a panel in the look's skin with the layout's map in it.
			card.sample = CreateFrame("Frame", nil, card)
			card.sample:SetSize(sampleWidth, sampleHeight)
			card.sample:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", 0, -6)
			card.sample:EnableMouse(false)
			card.map = CreateFrame("Frame", nil, card.sample)
			card.map:SetPoint("TOPLEFT", 4, -4)
			card.map:SetSize(sampleWidth - 8, sampleHeight - 8)
			card.map:EnableMouse(false)
			-- The whole description shows: the cards grow with it (Relayout).
			card.desc:ClearAllPoints()
			card.desc:SetPoint("TOPLEFT", card.sample, "BOTTOMLEFT", 0, -6)
			card.desc:SetWidth(lookWidth - 20)
			card.minHeight = nil
			frame.lookCards[index] = card
		end
		-- Everything under the full looks sits in one frame that Relayout
		-- moves down when the note or the cards above grow.
		local artTop = 0
		local below = CreateFrame("Frame", nil, child)
		below:SetPoint("TOPLEFT", 0, -(lookTop + lookHeight + 14))
		below:SetPoint("TOPRIGHT", child, "TOPRIGHT", 0, -(lookTop + lookHeight + 14))
		below:SetHeight(1)
		frame.below = below
		local lookDivider = below:CreateTexture(nil, "ARTWORK")
		lookDivider:SetColorTexture(unpack(E.tokens.edge.divider))
		E:Hairline(lookDivider, "h", 1)
		lookDivider:SetPoint("TOPLEFT", 0, -artTop + 6)
		lookDivider:SetPoint("TOPRIGHT", 0, -artTop + 6)
		-- Skin cards: a live sample of each skin, applied at once, in a grid
		-- under the label that wraps to more rows (Installer.LayoutSkinGrid).
		frame.artCards = {}
		local artLabel = E:CreateText(below, E.tokens.size.body, "LEFT")
		artLabel:SetPoint("TOPLEFT", 0, -artTop - 5)
		artLabel:SetText(L["Skin"])
		frame.artLabel = artLabel
		frame.artNote = Secondary(E:CreateText(below, E.tokens.size.label, "LEFT"))
		frame.artNote:SetPoint("LEFT", artLabel, "RIGHT", 10, 0)
		frame.artNote:SetText(L["Applies at once. The first full look keeps following your layout's skin."])
		local _, skinOrder = E:SkinValues()
		for _, key in ipairs(skinOrder) do
			local info = E.artStyleInfo[key]
			local card = Choice(below, 132, 78, info and L[info.title] or key, nil, function(self)
				if session then Remember("look", "art") end
				E:SetSkin(self.key)
				Installer.Update()
			end)
			card.title:ClearAllPoints()
			card.title:SetJustifyH("LEFT")
			card.title:SetWordWrap(true)
			card.sample = CreateFrame("Frame", nil, card)
			card.sample:SetPoint("TOPLEFT", 8, -8)
			card.sample:SetPoint("TOPRIGHT", -8, -8)
			card.sample:SetHeight(Installer.SKIN_SAMPLE)
			card.sample:EnableMouse(false)
			card.title:SetPoint("TOPLEFT", card.sample, "BOTTOMLEFT", 0, -6)
			card.key = key
			Tooltip(card, info and L[info.title] or key, info and L[info.desc or info.short or ""] or nil)
			frame.artCards[#frame.artCards + 1] = card
		end
		frame.artTop, frame.artDivider = artTop, below:CreateTexture(nil, "ARTWORK")
		frame.artDivider:SetColorTexture(unpack(E.tokens.edge.divider))
		E:Hairline(frame.artDivider, "h", 1)
		frame.maxX = maxX
		local y = Installer.LayoutSkinGrid(frame)
		frame.rowsTop, frame.labelWidth = y, labelWidth
		for _, name in ipairs(StyleCategories()) do
			local module = E.modules[name]
			-- A long module name wraps to a second line; the row grows with it.
			local label = Paragraph(below, E.tokens.size.body, L[module.title])
			label:SetWidth(labelWidth - 8)
			local buttons = {}
			local list = { { key = false, title = L["Keep"], desc = L["Leave %s as it is."]:format(E:InSentence(L[module.title])) } }
			-- Styles that act for the player (acts = true, e.g. Fast questing)
			-- stay on their module page; a look step never turns on automation.
			for _, style in ipairs(E.styles[name]) do
				if not style.acts then list[#list + 1] = style end
			end
			for _, style in ipairs(list) do
				local button = Choice(below, 10, 24, L[style.title], nil, function()
					Touch("styles")
					session.styles.choices[name] = style.key or nil
					session.styles.picked = session.styles.picked or {}
					session.styles.picked[name] = true
					if session.styles.state == "applied" then session.styles.state = "none" end
					Installer.Update()
				end)
				button.key = style.key or false
				button.tip = style.desc and L[style.desc]
				Tooltip(button, L[style.title], button.tip)
				buttons[#buttons + 1] = button
			end
			local divider = below:CreateTexture(nil, "ARTWORK")
			divider:SetColorTexture(unpack(E.tokens.edge.divider))
			E:Hairline(divider, "h", 1)
			frame.rows[#frame.rows + 1] = { name = name, buttons = buttons, label = label, divider = divider }
		end
		y = LayoutStyleRows(frame)
		if #frame.rows == 0 then
			local none = Secondary(Paragraph(below, E.tokens.size.body, L["No module offers style presets."]))
			none:SetPoint("TOPLEFT", 0, -y)
			y = y + 20
		end
		frame.belowHeight = math.max(10, y)
		frame.child = child
		child:SetHeight(lookTop + lookHeight + 14 + frame.belowHeight)
	end,
	Refresh = function(frame)
		local art = E.db.general.artStyle
		local look = session and session.styles.look
		local layoutKey = FullLookLayout()
		local layout = E.layouts[layoutKey]
		local layoutTitle = E:LayoutTitle(layoutKey)
		if frame.lookNote then
			frame.lookNote:SetText(L["One click sets the %s layout, a skin with its accent, the %s font and the styles that fit the layout. Below, change any part on its own."]:format(
				HL(layoutTitle), E.defaults.general.font))
		end
		-- The full looks follow the layout picked on this run.
		local looks = FullLookArts(layoutKey)
		for index, card in ipairs(frame.lookCards or {}) do
			local entry = looks[index]
			card:SetShown(entry ~= nil)
			if entry then
				card.key, card.follow = entry.key, entry.follow
				Installer.PaintFullLook(card, layoutKey, layout, layoutTitle, look, art)
			end
		end
		for _, card in ipairs(frame.artCards or {}) do
			card:SetSelected(card.key == art)
			E:PaintSkinSample(card.sample, card.key)
		end
		frame.rowsTop = Installer.LayoutSkinGrid(frame)
		-- The note and the full look cards are as tall as their texts; what
		-- is below them moves down with them.
		local lookTop = math.max(34, 6 + math.ceil(frame.lookNote:GetStringHeight() or 0) + 10)
		local lookHeight = 0
		for _, card in ipairs(frame.lookCards or {}) do
			local need = 8 + math.ceil(card.title:GetStringHeight() or 0) + 6 + frame.sampleHeight + 6 + math.ceil(card.desc:GetStringHeight() or 0) + 8
			lookHeight = math.max(lookHeight, need)
		end
		for index, card in ipairs(frame.lookCards or {}) do
			-- The kit card keeps its least height on a resize (its own fit
			-- doesn't count the preview).
			card.minHeight = lookHeight
			card:SetHeight(lookHeight)
			card:ClearAllPoints()
			card:SetPoint("TOPLEFT", (index - 1) * (frame.lookWidth + frame.lookGap), -lookTop)
		end
		if frame.rows and #frame.rows > 0 then frame.belowHeight = math.max(10, LayoutStyleRows(frame)) end
		local belowTop = lookTop + lookHeight + 14
		frame.below:ClearAllPoints()
		frame.below:SetPoint("TOPLEFT", 0, -belowTop)
		frame.below:SetPoint("TOPRIGHT", frame.child, "TOPRIGHT", 0, -belowTop)
		frame.child:SetHeight(belowTop + frame.belowHeight)
		-- A pick that doesn't fit the run's layout goes back to the
		-- layout's suggestion; styles that don't fit are grayed out.
		local runLayout = session and (session.layout.key or (look and look.layout)) or E.db.general.layout
		local s = session and session.styles
		for _, row in ipairs(frame.rows) do
			local chosen = s and s.choices[row.name]
			if chosen and not E:StyleFits(runLayout, row.name, chosen) then
				s.choices[row.name], s.picked[row.name] = nil, nil
			end
		end
		SuggestStyles()
		for _, row in ipairs(frame.rows) do
			local chosen = s and s.choices[row.name] or false
			for _, button in ipairs(row.buttons) do
				button:SetSelected(button.key == chosen)
				local fits, reason = true, nil
				if button.key then fits, reason = E:StyleFits(runLayout, row.name, button.key) end
				button:SetEnabledLook(fits)
				Tooltip(button, button.title:GetText(), fits and button.tip or reason)
			end
			-- The healer's group frames: the role owns their size.
			local module = E.modules[row.name]
			local sized = RoleSizing(row.name)
			local roleTitle = sized and E.roleProfiles[RunRole()] and L[E.roleProfiles[RunRole()].title]
			-- A list whose styles show nothing yet says so under its name (the
			-- minimap styles shape EldoUI's minimap, not the game's).
			local notice = E:StyleNotice(row.name, "setup")
			local note = sized and L["Size set by the %s role"]:format(roleTitle or "") or notice
			row.label:SetText(note and ("%s\n%s"):format(L[module.title], Muted(note)) or L[module.title])
		end
		if frame.rows and #frame.rows > 0 then
			frame.belowHeight = math.max(10, LayoutStyleRows(frame))
			frame.child:SetHeight(belowTop + frame.belowHeight)
		end
		-- The picks show on the live frames (not in combat).
		if session and Installer.GetStep and select(2, Installer.GetStep()) == "styles" then Preview.Sync() end
	end,
	Apply = Work.ApplyStylesStep,
	Revert = Preview.Revert,
	HasChoice = StylesHaveChoice,
	Summary = function()
		local parts = {}
		for _, name in ipairs(StyleCategories()) do
			local key = session.styles.choices[name]
			if key then
				for _, style in ipairs(E.styles[name]) do
					if style.key == key then parts[#parts + 1] = ("%s %s"):format(L[E.modules[name].title], L[style.title]) end
				end
			end
		end
		if #parts == 0 then return L["Styles: keep"] end
		if #parts > 3 then
			return L["Styles: %s and %d more"]:format(table.concat(parts, ", ", 1, 3), #parts - 3)
		end
		return L["Styles: %s"]:format(table.concat(parts, ", "))
	end,
}

BASE[#BASE + 1] = {
	key = "access", short = "Accessibility", title = "Accessibility",
	desc = "Optional: easier to read for low vision and color blindness. Nothing here is on unless you check it.",
	help = function()
		return L["Each switch works on its own and can be turned off any time in %s > General > Accessibility, which puts back what you had. That page also has sound cues, the text size and the kind of color blindness."]:format(HL("/eui"))
	end,
	Build = function(frame)
		frame.rows = {}
		for index, info in ipairs(ACCESS_CHOICES) do
			local check = Check(frame, L[info.label], L[info.desc], function(on)
				local access = AccessSettings() or {}
				-- The tick as the switch is now: nothing to change.
				if (on and true or false) == info.on(access) then
					session.access.picks[info.key] = nil
				else
					session.access.picks[info.key] = on and true or false
				end
				if session.access.state == "applied" then session.access.state = "none" end
				Installer.Update()
			end)
			check:SetPoint("TOPLEFT", 0, -(index - 1) * 30)
			check.info = info
			check.status = Secondary(E:CreateText(frame, E.tokens.size.label, "LEFT"))
			check.status:SetPoint("LEFT", check, "LEFT", 300, 0)
			check.status:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
			frame.rows[index] = check
		end
		frame.note = Secondary(LiveText(Paragraph(frame, E.tokens.size.label), function()
			local text = L["Change these later, and add sound cues, in %s > General > Accessibility."]:format(HL("/eui"))
			local hint = E.SmallTextHint and E:SmallTextHint()
			return hint and (hint .. "\n" .. text) or text
		end))
		frame.note:SetPoint("TOPLEFT", 0, -#ACCESS_CHOICES * 30 - 12)
		frame.note:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -#ACCESS_CHOICES * 30 - 12)
	end,
	Refresh = function(frame)
		local access = AccessSettings() or {}
		for _, check in ipairs(frame.rows) do
			local on = check.info.on(access)
			local want = session.access.picks[check.info.key]
			if want == nil then want = on end
			check:SetChecked(want and true or false)
			check:SetEnabledLook(true)
			-- A hint only: the tick can still be turned off.
			check.status:SetText(on and want and Good(L["Already on"]) or "")
		end
	end,
	Apply = Work.ApplyAccessStep,
	HasChoice = function() return #AccessPicked() > 0 end,
	Summary = function()
		local parts = {}
		for _, info in ipairs(ACCESS_CHOICES) do
			local want = session.access.picks[info.key]
			if want then
				parts[#parts + 1] = L[info.label]
			elseif want == false then
				parts[#parts + 1] = L["%s off"]:format(L[info.label])
			end
		end
		if #parts == 0 then return L["Accessibility: keep"] end
		return L["Accessibility: %s"]:format(table.concat(parts, ", "))
	end,
}


BASE[#BASE + 1] = {
	key = "role", short = "Role", title = "Role",
	desc = "A small layer over your layout for the job you do in groups. Boss frames, boss mod bars and your cast bar never move by role.",
	help = Key("A role is not a layout. Healer moves your party and raid frames next to the center (a few frames that sat there step outward) and turns on dispel and boss debuff highlights. Tank adds threat colors and the threat meter. Melee and Ranged keep the layout as it is; Ranged also shows the five-second rule on your mana bar.\n\nClick-casting (healers): a binding casts a spell on the frame you click, e.g. Shift + left click casts your fast heal on that party member. EldoUI suggests spells from your spellbook; only the ones you tick are bound, plain left and right click stay target and menu, and nothing casts by itself. Change or remove them any time in /eui > Click Casting."),
	Build = function(frame)
		frame.cards = {}
		-- Five cards share the row, so each card says its role in one short
		-- line; the full description is the card's tooltip.
		local SHORT = {
			melee = L["Frames stay where the layout puts them."],
			ranged = L["Frames stay put; the mana bar shows the five-second rule."],
			healer = L["Party and raid frames move next to the center."],
			tank = L["Threat colors and the threat meter."],
		}
		local list = { { key = false, title = L["Keep"], desc = L["Leave the role layer as it is."] } }
		for _, key in ipairs(E.roleOrder) do
			local profile = E.roleProfiles[key]
			list[#list + 1] = { key = key, title = L[profile.title], short = SHORT[key], desc = L[profile.desc] }
		end
		local gap = 8
		local width = math.floor((CONTENT_W - (#list - 1) * gap) / #list)
		for index, info in ipairs(list) do
			local card = Choice(frame, width, 96, info.title, info.short or info.desc, function()
				Touch("role")
				session.role.choice = info.key or nil
				if session.role.state == "applied" then session.role.state = "none" end
				Installer.Update()
			end)
			card.key = info.key
			card:SetPoint("TOPLEFT", (index - 1) * (width + gap), 0)
			Tooltip(card, info.title, info.desc)
			frame.cards[index] = card
		end
		frame.detected = Secondary(Paragraph(frame, E.tokens.size.label, ""))
		-- Top corners only: a RIGHT point would also pin the text's middle to
		-- the page's middle, which turns it upside down under Large text.
		frame.detected:SetPoint("TOPLEFT", frame.cards[1], "BOTTOMLEFT", 0, -10)
		frame.detected:SetPoint("TOPRIGHT", frame.cards[#frame.cards], "BOTTOMRIGHT", 0, -10)
		frame.class = Check(frame, L["Class details"], L["Turn on the resources and frames your class uses (combo points, form mana, totem timers, pet frames)."], function(on)
			Touch("role")
			session.role.classLayer = on
			if session.role.state == "applied" then session.role.state = "none" end
			Installer.Update()
		end)
		-- Placed under the suggestion text in Refresh (Large text makes the
		-- cards and the text above taller).
		frame.class:SetPoint("TOPLEFT", frame.detected, "BOTTOMLEFT", 0, -12)
		-- The suggested talent path for the role, when the class has one
		-- (Modules/Talents/Builds.lua). It only names it; nothing is planned.
		frame.talentPath = E.Talents and E.Talents.CreateRoleHint and E.Talents:CreateRoleHint(frame)
		if frame.talentPath then
			frame.talentPath:SetPoint("TOPLEFT", frame.detected, "BOTTOMLEFT", 0, -8)
			frame.talentPath:SetPoint("TOPRIGHT", frame.detected, "BOTTOMRIGHT", 0, -8)
		end
		-- One line next to the switch (the full list is the switch's tooltip).
		frame.classText = Secondary(E:CreateText(frame, E.tokens.size.label, "LEFT"))
		frame.classText:SetPoint("LEFT", frame.class.label, "RIGHT", 10, 0)
		frame.classText:SetWordWrap(false)
		frame.classText:SetMaxLines(1)

		-- Healer: click-casting on group frames, only what the player ticks.
		local healer = CreateFrame("Frame", nil, frame)
		healer:SetPoint("TOPLEFT", frame.class, "TOPLEFT", 0, -36)
		healer:SetPoint("BOTTOMRIGHT", 0, 0)
		frame.healer = healer
		Kit.Divider(healer, 0)
		local title = E:CreateText(healer, E.tokens.size.cardTitle, "LEFT")
		title:SetPoint("TOPLEFT", 0, -10)
		title:SetText(L["Click-casting on party and raid frames"])
		healer.clickCast = Check(healer, L["Set up click-casting"], L["Bind the spells checked below to clicks on party and raid frames. Nothing is bound unless this is checked."], function(on)
			local r = session.role
			r.clickCast = on
			if on and not next(r.picks) then
				-- Suggested: every free click. A click you already use stays yours.
				for _, item in ipairs(E:GetRoleClickCast()) do
					if not item.conflict and not item.bound then r.picks[PickKey(item)] = true end
				end
			end
			if r.state == "applied" then r.state = "none" end
			Installer.Update()
		end)
		healer.clickCast:SetPoint("TOPLEFT", 0, -36)
		healer.rows = {}
		healer.none = Secondary(Paragraph(healer, E.tokens.size.label, ""))
		healer.none:SetPoint("TOPLEFT", 28, -68)
		healer.none:SetPoint("TOPRIGHT", healer, "TOPRIGHT", 0, -68)
		healer.note = Secondary(LiveText(Paragraph(healer, E.tokens.size.label), function()
			return L["Plain left and right click stay target and menu. Change or remove bindings any time in %s > Click Casting."]:format(HL("/eui"))
		end))
		healer.note:SetPoint("BOTTOMLEFT", 0, 0)
		healer.note:SetPoint("BOTTOMRIGHT", healer, "BOTTOMRIGHT", 0, 0)
		frame.other = Secondary(LiveText(Paragraph(frame, E.tokens.size.label), function()
			return L["Healers get a click-cast setup here. Your role can be changed any time in %s > Role, or with %s."]:format(HL("/eui"), HL("/eui install role"))
		end))
		frame.other:SetPoint("TOPLEFT", frame.class, "TOPLEFT", 0, -46)
		frame.other:SetWidth(CONTENT_W)
	end,
	Refresh = function(frame)
		local r = session.role
		-- The picked role shows on the live frames (not in combat).
		if Installer.GetStep and select(2, Installer.GetStep()) == "role" then RolePreview.Sync() end
		for _, card in ipairs(frame.cards) do card:SetSelected(card.key == (r.choice or false)) end
		-- The cards share the height of the tallest text.
		local height = 0
		for _, card in ipairs(frame.cards) do
			card.minHeight = 96
			height = math.max(height, card:FitHeight())
		end
		for _, card in ipairs(frame.cards) do
			card.minHeight = height
			card:FitHeight()
		end
		local detected, source = E:DetectRole()
		local now = E:GetRole()
		local text = now == "none" and L["No role layer is in use now."] or L["In use now: %s."]:format(HL(L[E.roleProfiles[now].title]))
		if detected then
			local suggestion = source == "spec" and L["From your specialization EldoUI suggests %s."]
				or source == "group" and L["From your group role EldoUI suggests %s."]
				or L["From your class EldoUI suggests %s."]
			text = text .. " " .. suggestion:format(HL(L[E.roleProfiles[detected].title]))
		end
		frame.detected:SetText(text)
		-- Talent paths name the three roles: Melee and Ranged read as damage.
		local pathShown = frame.talentPath and frame.talentPath:Update(E:RoleGroup(r.choice or now))
		frame.class:ClearAllPoints()
		frame.class:SetPoint("TOPLEFT", pathShown and frame.talentPath or frame.detected, "BOTTOMLEFT", 0, -12)
		local layer = E:GetRoleClassLayer()
		frame.class:SetChecked(layer ~= nil and r.classLayer and true or false)
		frame.class:SetEnabledLook(layer ~= nil)
		frame.classText:SetText(layer and L[layer.text] or L["Your class has nothing to add."])
		-- Up to the page's right edge (set in Refresh: the switch's label
		-- grows with Large text).
		local right, labelRight = frame:GetRight(), frame.class.label:GetRight()
		frame.classText:SetWidth(right and labelRight and math.max(right - labelRight - 10, 40) or CONTENT_W / 2)
		Tooltip(frame.class, L["Class details"], layer and (layer.detail or layer.text) and L["For your class: %s."]:format(layer.detail or layer.text)
			or L["Turn on the resources and frames your class uses (combo points, form mana, totem timers, pet frames)."])

		-- What follows starts under the class row, which Large text makes taller.
		local rowHeight = math.max(frame.class:GetHeight() or 0, frame.classText:GetStringHeight() or 0)
		frame.healer:SetPoint("TOPLEFT", frame.class, "TOPLEFT", 0, -math.max(36, rowHeight + 12))
		frame.other:SetPoint("TOPLEFT", frame.class, "TOPLEFT", 0, -math.max(46, rowHeight + 22))
		local isHealer = (r.choice or now) == "healer"
		frame.healer:SetShown(isHealer)
		frame.other:SetShown(not isHealer)
		if not isHealer then return end
		local healer = frame.healer
		local list = E:GetRoleClickCast()
		healer.clickCast:SetChecked(r.clickCast and true or false)
		healer.clickCast:SetEnabledLook(#list > 0)
		for index, item in ipairs(list) do
			local row = healer.rows[index]
			if not row then
				row = Check(healer, "", nil, function(on)
					local run = session.role
					run.picks[row.pick] = on or nil
					if run.state == "applied" then run.state = "none" end
					Installer.Update()
				end)
				row:SetPoint("TOPLEFT", 28, -66 - (index - 1) * 26)
				healer.rows[index] = row
			end
			row.pick = PickKey(item)
			local line = ("%s: |cffffffff%s|r %s"):format(item.label or item.key, item.spell, Muted("(" .. item.what:lower() .. ")"))
			if item.bound then
				line = line .. " " .. Good(L["already set"])
			elseif item.conflict then
				line = line .. " " .. Warn(L["replaces %s"]:format(tostring(item.conflict)))
			end
			row.label:SetText(line)
			row:SetHitRectInsets(0, -math.max(40, row.label:GetStringWidth() + 8), 0, 0)
			row:SetChecked(r.picks[row.pick] and true or false)
			row:SetEnabledLook(r.clickCast and not item.bound and true or false)
			row:Show()
		end
		for index = #list + 1, #healer.rows do healer.rows[index]:Hide() end
		healer.none:SetShown(#list == 0)
		if #list == 0 then
			healer.none:SetText(L["No healing or dispel spells of your class were found in your spellbook yet. Bind spells yourself any time in /eui > Click Casting."])
		end
	end,
	Apply = Work.ApplyRoleStep,
	Revert = RolePreview.Revert,
	HasChoice = RoleHasChoice,
	Summary = function()
		local r = session.role
		local role = r.choice or E:GetRole()
		local parts = { role == "none" and L["Role: none"]
			or (r.choice == nil and L["Role: %s (keep)"] or L["Role: %s"]):format(L[E.roleProfiles[role].title]) }
		if r.classLayer and E:GetRoleClassLayer() then parts[#parts + 1] = L["class details"] end
		local picked = #PickedBindings()
		if picked > 0 then parts[#parts + 1] = (picked == 1 and L["%d click-cast binding"] or L["%d click-cast bindings"]):format(picked) end
		return table.concat(parts, ", ")
	end,
}

---------------------------------------------------------------------------
-- Addons you already use: other addons that do the same job as part of
-- EldoUI (Core/AddonConflicts.lua). One pick per job, EldoUI preselected
-- on a first run (Recommended). Nothing changes before Finish: Finish
-- turns off, for this character and after one reload, the addons whose
-- job the player gave to EldoUI, and its summary names every one of them.
-- A part both can run on turns nothing off. Shown only when an addon is
-- found.
---------------------------------------------------------------------------
local Competitors = {}
Installer.Competitors = Competitors

-- The jobs the step offers: rows of E:DetectedAddons that are not already
-- EldoUI's (a pick of EldoUI waiting for a reload counts as made).
function Competitors.Rows()
	local list = {}
	if not E.DetectedAddons then return list end
	for _, row in ipairs(E:DetectedAddons()) do
		if row.state ~= "reload" and not (row.state == "eldoui" and not row.loaded) then
			row.key = row.addon .. "|" .. row.job
			list[#list + 1] = row
		end
	end
	return list
end

-- What a job is set to now: "eldoui" or "keep".
function Competitors.CurrentPick(row)
	return (row.state == "eldoui" or row.state == "reload") and "eldoui" or "keep"
end

function Competitors.Pick(row)
	local c = session and session.competitors
	local pick = c and c.picks[row.key]
	return pick or Competitors.CurrentPick(row)
end

-- The picks that change something, and the addons Finish turns off.
function Competitors.Changes()
	local changes, off, seen = {}, {}, {}
	for _, row in ipairs(Competitors.Rows()) do
		local pick = Competitors.Pick(row)
		if pick ~= Competitors.CurrentPick(row) or (pick == "eldoui" and row.state == "fallback") then
			changes[#changes + 1] = row
			if pick == "eldoui" and E:CompetitorNeedsDisable(row) and not seen[row.addon] then
				seen[row.addon] = true
				off[#off + 1] = row.title
			end
		end
	end
	return changes, off
end

-- The pick the module step shows for a held module: "eldoui", "keep" or nil.
function Competitors.ModulePick(name)
	for _, row in ipairs(Competitors.Rows()) do
		if row.module == name and not row.feature then return Competitors.Pick(row), row.title end
	end
	return nil
end

-- "A", "A and B", "A, B and C".
function Competitors.JoinNames(names)
	if #names <= 1 then return names[1] or "" end
	return L["%s and %s"]:format(table.concat(names, ", ", 1, #names - 1), names[#names])
end

function Competitors.Apply()
	local c = session.competitors
	c.disabled = c.disabled or {}
	for _, row in ipairs((Competitors.Changes())) do
		if Competitors.Pick(row) == "eldoui" then
			local result = E:UseEldoUIFor(row.addon, row.job)
			if result == "reload" then
				c.disabled[row.addon] = true
				Installer.NoteAddonOff(row.addon, row.title)
				session.needsReload = true
			end
		else
			E:KeepCompetitor(row.addon, row.job)
		end
	end
	-- The picks are made now; a later run starts from what is set.
	wipe(c.picks)
	c.state = "applied"
end

-- The "show both" switches a pick writes (module settings), by module and key.
function Competitors.Settings()
	local list = {}
	for _, item in ipairs(E.competitors and E.competitors.list or {}) do
		local setting = item.setting
		local module = type(setting) == "table" and E.modules[setting[1]]
		if module and module.db then
			list[setting[1]] = list[setting[1]] or {}
			list[setting[1]][setting[2]] = module.db[setting[2]] and true or false
		end
	end
	return list
end

PARTS.competitors = {
	capture = function()
		local store = E:GetGlobal("competitors")
		return { choices = CopyTable(store and store.choices or {}), settings = Competitors.Settings() }
	end,
	restore = function(data)
		local c = session.competitors
		for addon in pairs(c.disabled or {}) do
			if E:CompetitorDisabledNow(addon) then E:KeepCompetitor(addon) end
		end
		wipe(c.disabled or {})
		Installer.NoteAddonOff(nil)
		local store = E:GetGlobal("competitors")
		if store then store.choices = CopyTable(data.choices) end
		for name, keys in pairs(data.settings or {}) do
			local module = E.modules[name]
			if module and module.db then
				for key, value in pairs(keys) do module.db[key] = value end
			end
		end
	end,
	changed = function(data)
		local c = session.competitors
		if next(c.disabled or {}) then return true end
		local store = E:GetGlobal("competitors")
		return not E.DeepEqual(data.choices, store and store.choices or {})
			or not E.DeepEqual(data.settings or {}, Competitors.Settings())
	end,
}

BASE[#BASE + 1] = {
	key = "competitors", short = "Your addons", title = "Addons you already use",
	desc = "EldoUI found addons that do the same job as parts of EldoUI. Pick which one you want for each. You can change this later on the Other addons page.",
	help = Key("EldoUI never runs two addons on the same frames. When you give EldoUI a job another addon does, that addon is turned off for this character at Finish, after one reload; Finish names every one. A part both can run on turns nothing off: EldoUI's part runs next to the other addon. Settings > Other addons or /eui addons changes it later."),
	-- Only when an addon is found; otherwise the step is left out.
	Available = function() return #Competitors.Rows() > 0 end,
	-- The picks act at Finish only, never on Apply and continue.
	finishOnly = true,
	Build = function(frame)
		frame.count = Secondary(E:CreateText(frame, E.tokens.size.label, "LEFT"))
		frame.count:SetPoint("TOPLEFT", 0, -4)
		local holder = CreateFrame("Frame", nil, frame)
		holder:SetPoint("TOPLEFT", 0, -26)
		holder:SetPoint("BOTTOMRIGHT", 0, 0)
		local _, child = ScrollArea(holder)
		frame.child = child
		frame.rows = {}
		frame.captions = {}
	end,
	Refresh = function(frame)
		local child = frame.child
		local rows = Competitors.Rows()
		local cardWidth = math.floor((CONTENT_W - 22 - 180 - 8) / 2)
		local y, lastModule = 0, nil
		local captionIndex = 0
		for _, caption in ipairs(frame.captions) do caption:Hide() end
		for index, row in ipairs(rows) do
			local moduleTitle = row.moduleTitle ~= "" and row.moduleTitle or row.job
			if moduleTitle ~= lastModule then
				lastModule = moduleTitle
				captionIndex = captionIndex + 1
				local caption = frame.captions[captionIndex]
				if not caption then
					caption = E:CreateText(child, E.tokens.size.label, "LEFT")
					frame.captions[captionIndex] = caption
				end
				caption:ClearAllPoints()
				caption:SetPoint("TOPLEFT", 0, -y)
				caption:SetText(E:CaptionText(moduleTitle))
				caption:SetTextColor(E:TokenColor("accent"))
				caption:Show()
				y = y + 20
			end
			local line = frame.rows[index]
			if not line then
				line = CreateFrame("Frame", nil, child)
				line:SetSize(CONTENT_W - 22, 64)
				line.label = E:CreateText(line, E.tokens.size.body, "LEFT")
				line.label:SetPoint("TOPLEFT", 0, -6)
				line.label:SetWidth(176)
				line.label:SetWordWrap(true)
				line.eldo = Choice(line, cardWidth, 58, L["EldoUI"], "", function()
					session.competitors.picks[line.key] = "eldoui"
					if session.competitors.state == "applied" then session.competitors.state = "none" end
					Touch("competitors")
					Installer.Update()
				end)
				line.eldo:SetPoint("TOPLEFT", 180, 0)
				line.eldo.tag = E:CreateText(line.eldo, E.tokens.size.small, "RIGHT")
				line.eldo.tag:SetPoint("TOPRIGHT", -10, -9)
				line.eldo.tag:SetText(L["Recommended"])
				line.eldo.title:ClearAllPoints()
				line.eldo.title:SetPoint("TOPLEFT", 10, -8)
				line.eldo.title:SetPoint("TOPRIGHT", line.eldo.tag, "TOPLEFT", -6, 1)
				line.keep = Choice(line, cardWidth, 58, "", "", function()
					session.competitors.picks[line.key] = "keep"
					if session.competitors.state == "applied" then session.competitors.state = "none" end
					Touch("competitors")
					Installer.Update()
				end)
				line.keep:SetPoint("LEFT", line.eldo, "RIGHT", 8, 0)
				frame.rows[index] = line
			end
			line.key = row.key
			line:ClearAllPoints()
			line:SetPoint("TOPLEFT", 0, -y)
			line.label:SetText(row.feature and row.label or L["The whole module"])
			line.eldo.tag:SetTextColor(E:TokenColor("accent"))
			local off = E:CompetitorNeedsDisable(row)
			line.eldo.desc:SetText(off and L["EldoUI's %s; %s is turned off at Finish"]:format(E:CompetitorJobText(row), row.title)
				or L["Both keep running; EldoUI's part turns on"])
			line.keep.title:SetText(L["Keep %s"]:format(row.title))
			line.keep.desc:SetText(L["%s keeps this job and EldoUI stands back"]:format(row.title))
			local pick = Competitors.Pick(row)
			line.eldo:SetSelected(pick == "eldoui")
			line.keep:SetSelected(pick == "keep")
			Tooltip(line.eldo, L["EldoUI"], off and L["At Finish, %s is turned off for this character (after one reload) and EldoUI does this job."]:format(row.title)
				or L["EldoUI's part runs next to %s. Nothing is turned off."]:format(row.title))
			Tooltip(line.keep, L["Keep %s"]:format(row.title), L["%s keeps doing this job; EldoUI's part stays off while it is loaded."]:format(row.title))
			line:Show()
			y = y + 68
		end
		for index = #rows + 1, #frame.rows do frame.rows[index]:Hide() end
		child:SetHeight(math.max(10, y))
		local changes, off = Competitors.Changes()
		local count = (#rows == 1 and L["%d job"] or L["%d jobs"]):format(#rows)
		if #changes > 0 then
			count = count .. ", " .. Warn((#changes == 1 and L["%d change at Finish"] or L["%d changes at Finish"]):format(#changes))
		end
		if #off > 0 then count = count .. "  " .. L["%s: off for this character at Finish"]:format(Competitors.JoinNames(off)) end
		frame.count:SetText(count)
	end,
	Apply = Competitors.Apply,
	HasChoice = function() return #(Competitors.Changes()) > 0 end,
	Summary = function()
		local _, off = Competitors.Changes()
		if #off == 0 then return L["Your addons: no addon is turned off"] end
		return L["%s will be disabled for this character"]:format(Competitors.JoinNames(off))
	end,
}

BASE[#BASE + 1] = {
	key = "modules", short = "Modules", title = "Modules",
	desc = "Every part of EldoUI is a module. Uncheck the ones you don't want; they switch at Finish.",
	help = Key("A module that is off does nothing and costs nothing; Blizzard's own version of that part of the UI stays. Turning a module off fully brings back Blizzard's version after a reload, which Finish offers. Every module can be switched later in /eui > Modules or with the switch next to it in the options sidebar."),
	Build = function(frame)
		local allOn = Button(frame, L["Turn all on"], 120, function()
			for name in pairs(session.modules.states) do session.modules.states[name] = true end
			session.modules.state = "none"
			Installer.Update()
		end)
		allOn:SetPoint("TOPLEFT", 0, 0)
		local allOff = Button(frame, L["Turn all off"], 120, function()
			for name in pairs(session.modules.states) do session.modules.states[name] = false end
			session.modules.state = "none"
			Installer.Update()
		end)
		allOff:SetPoint("LEFT", allOn, "RIGHT", 8, 0)
		frame.count = Secondary(E:CreateText(frame, E.tokens.size.label, "LEFT"))
		frame.count:SetPoint("LEFT", allOff, "RIGHT", 16, 0)
		local holder = CreateFrame("Frame", nil, frame)
		holder:SetPoint("TOPLEFT", 0, -36)
		holder:SetPoint("BOTTOMRIGHT", 0, 0)
		local _, child = ScrollArea(holder)

		-- Group by the options sidebar's module groups, in its order.
		local groups, order = {}, {}
		for _, category in ipairs(E.moduleGroups or {}) do order[#order + 1] = category end
		for name, module in E:IterateModules() do
			local category = E.GetModuleGroup and E:GetModuleGroup(module) or "Other"
			if not NOT_IN_SETUP[name] then
				if not groups[category] then
					groups[category] = {}
					local known = false
					for _, entry in ipairs(order) do known = known or entry == category end
					if not known then order[#order + 1] = category end
				end
				table.insert(groups[category], name)
			end
		end
		local columns = 3
		local columnWidth = math.floor((CONTENT_W - 22) / columns)
		local heights = {}
		for column = 1, columns do heights[column] = 0 end
		frame.checks = {}
		for _, category in ipairs(order) do
			local names = groups[category]
			if names then
				table.sort(names, function(a, b) return E.modules[a].title < E.modules[b].title end)
				local column = 1
				for index = 2, columns do
					if heights[index] < heights[column] then column = index end
				end
				local x, y = (column - 1) * columnWidth, heights[column]
				local caption = E:CreateText(child, E.tokens.size.label, "LEFT")
				caption:SetPoint("TOPLEFT", x, -y)
				caption:SetText(E:CaptionText(E.CategoryTitle and E:CategoryTitle(category) or L[category]))
				caption:SetTextColor(E:TokenColor("accent"))
				y = y + 20
				for _, name in ipairs(names) do
					local module = E.modules[name]
					local desc = module.desc ~= "" and L[module.desc] or L["Switch %s on or off."]:format(L[module.title])
					local check = Check(child, L[module.title], desc, function(on)
						session.modules.states[name] = on
						if session.modules.state == "applied" then session.modules.state = "none" end
						Installer.Update()
					end)
					check:SetPoint("TOPLEFT", x, -y)
					check.name = name
					frame.checks[#frame.checks + 1] = check
					y = y + 24
				end
				heights[column] = y + 12
			end
		end
		local tallest = 0
		for column = 1, columns do tallest = math.max(tallest, heights[column]) end
		child:SetHeight(math.max(10, tallest))
	end,
	Refresh = function(frame)
		local states = session.modules.states
		local on, total = 0, 0
		for _, check in ipairs(frame.checks) do
			local module = E.modules[check.name]
			local conflict = module and select(2, E:GetModuleConflict(module))
			-- A held module follows the pick on the Addons you already use step.
			local pick = conflict and Competitors.ModulePick(check.name)
			check:SetChecked(states[check.name] and true or false)
			check:SetEnabledLook(not conflict or pick == "eldoui")
			if not module then
				check.label:SetText(check.name)
			elseif conflict and pick == "eldoui" then
				check.label:SetText(L[module.title] .. " " .. Good(L["(EldoUI after the reload)"]))
			elseif conflict then
				check.label:SetText(L[module.title] .. " " .. Warn(L["(handled by %s)"]:format(conflict)))
			else
				check.label:SetText(L[module.title])
			end
			total = total + 1
			if states[check.name] then on = on + 1 end
		end
		local changes = #ModuleChanges()
		local count = L["%d of %d on"]:format(on, total)
		if changes > 0 then
			count = count .. ", " .. Warn((changes == 1 and L["%d change at Finish"] or L["%d changes at Finish"]):format(changes))
		end
		frame.count:SetText(count)
	end,
	Apply = Work.ApplyModulesStep,
	HasChoice = function() return #ModuleChanges() > 0 end,
	Summary = function()
		local changes = ModuleChanges()
		if #changes == 0 then return L["Modules: no change"] end
		local onList, offList = {}, {}
		for _, name in ipairs(changes) do
			local list = session.modules.states[name] and onList or offList
			list[#list + 1] = L[E.modules[name].title]
		end
		-- "A, B, C" or "A, B, C and 2 more"
		local function Names(names)
			local shown = table.concat(names, ", ", 1, math.min(3, #names))
			return #names > 3 and L["%s and %d more"]:format(shown, #names - 3) or shown
		end
		local parts = {}
		if #onList > 0 then parts[#parts + 1] = L["on: %s"]:format(Names(onList)) end
		if #offList > 0 then parts[#parts + 1] = L["off: %s"]:format(Names(offList)) end
		return L["Modules %s"]:format(table.concat(parts, "; "))
	end,
}

BASE[#BASE + 1] = {
	key = "blizzard", short = "Blizzard UI", title = "Blizzard UI",
	desc = "Which of Blizzard's own frames and windows EldoUI may change. Anything EldoUI may not change stays exactly as Blizzard made it.",
	help = Key("Every Blizzard element (player frame, minimap, bags, the spellbook and so on) has its own switch. Off means Blizzard's own version, untouched. On, an element can allow up to four things: replace (EldoUI's frame instead of Blizzard's), skin (the EldoUI look), move (drag and scale it) and improve (small extras).\n\nRecommended turns on what EldoUI's modules are made for. You can change every element later on the Blizzard UI page; some changes come fully back only after a reload."),
	Build = function(frame)
		-- In a scroll area: Large text makes the cards taller than the page.
		local _, child = ScrollArea(frame)
		frame.child = child
		frame.choices = {}
		local width = math.floor((child:GetWidth() - 12) / 2)
		for index, info in ipairs(BLIZZARD_MODES) do
			local choice = Choice(child, width, 76, L[info.title], L[info.desc], function()
				Touch("blizzard")
				session.blizzard.mode = info.key
				if session.blizzard.state == "applied" then session.blizzard.state = "none" end
				Installer.Update()
			end)
			choice.mode = info.key
			frame.choices[index] = choice
		end
		frame.note = Secondary(Paragraph(child, E.tokens.size.label, L["Every element (player frame, minimap, bags, ...) has its own switch on the Blizzard UI page, where you can change each one later. Off always means Blizzard's own version. Some changes come fully back only after a reload, which Finish offers."]))
		Installer.BuildWindowsRow(frame)
	end,
	Refresh = function(frame)
		for _, choice in ipairs(frame.choices) do choice:SetSelected(choice.mode == session.blizzard.mode) end
		-- Two cards a row; each row as tall as its tallest text, so a long
		-- text or Large text wraps instead of running into the next row.
		local y = 0
		for first = 1, #frame.choices, 2 do
			local height = 0
			for index = first, math.min(first + 1, #frame.choices) do
				local choice = frame.choices[index]
				choice.minHeight = 76
				height = math.max(height, choice:FitHeight())
			end
			for index = first, math.min(first + 1, #frame.choices) do
				local choice = frame.choices[index]
				choice.minHeight = height
				choice:FitHeight()
				choice:ClearAllPoints()
				choice:SetPoint("TOPLEFT", (index - first) * (choice:GetWidth() + 12), -y)
			end
			y = y + height + 12
		end
		frame.note:ClearAllPoints()
		frame.note:SetPoint("TOPLEFT", 0, -y - 8)
		frame.note:SetWidth(frame.child:GetWidth())
		y = y + 8 + math.ceil(frame.note:GetStringHeight() or 0)
		y = Installer.LayoutWindowsRow(frame, y + 16)
		frame.child:SetHeight(math.max(10, y + 8))
	end,
	Apply = Work.ApplyBlizzardStep,
	-- A mode other than the one in effect (keep, or the one applied in
	-- this run; going back to keep takes that one back).
	HasChoice = function()
		local b = session.blizzard
		return b.mode ~= (b.appliedMode or "keep") or Installer.WindowsChoiceChanged(b)
	end,
	Summary = function()
		local text = L["Blizzard UI: keep"]
		for _, info in ipairs(BLIZZARD_MODES) do
			if info.key == session.blizzard.mode then text = L["Blizzard UI: %s"]:format(L[info.title]) end
		end
		local b = session.blizzard
		local W = E.Appearance and E.Appearance.WINDOWS
		if W and Installer.WindowsChoiceChanged(b) then
			text = text .. "; " .. L["Blizzard windows: %s"]:format(L[W.titles[b.windowsMode]])
		end
		return text
	end,
}

-- Chat step: the mode cards share the height of the tallest text, and
-- the tabs, the font sizes, the preview and the notes move down with them,
-- so Large text wraps instead of running into the next part.
function Installer.LayoutChat(frame)
	local height = 0
	for _, choice in ipairs(frame.choices) do
		choice.minHeight = 64
		height = math.max(height, choice:FitHeight())
	end
	for _, choice in ipairs(frame.choices) do
		choice.minHeight = height
		choice:FitHeight()
	end
	local top = height + 12
	local left = 412
	local rowHeight = math.max(30, math.ceil(frame.checks[1] and frame.checks[1]:GetHeight() or 24) + 6)
	for index, check in ipairs(frame.checks) do
		check:ClearAllPoints()
		check:SetPoint("TOPLEFT", left, -(top + (index - 1) * rowHeight))
	end
	local y = top + #frame.checks * rowHeight
	frame.classColors:ClearAllPoints()
	frame.classColors:SetPoint("TOPLEFT", left, -y)
	y = y + rowHeight
	local buttonHeight = math.max(24, math.ceil(E.tokens.size.body * (E.TextScale and E:TextScale() or 1)) + 8)
	frame.sizeLabel:ClearAllPoints()
	frame.sizeLabel:SetPoint("LEFT", frame, "TOPLEFT", left, -(y + buttonHeight / 2))
	local x = left + math.max(90, math.ceil(frame.sizeLabel:GetStringWidth() or 0) + 12)
	for _, button in ipairs(frame.sizes) do
		local width = math.max(button.size and 44 or 60, math.ceil(button.title:GetStringWidth() or 0) + 16)
		button:SetSize(width, buttonHeight)
		button:ClearAllPoints()
		button:SetPoint("TOPLEFT", x, -y)
		x = x + width + 4
	end
	y = y + buttonHeight
	local preview = frame.preview
	preview:ClearAllPoints()
	preview:SetPoint("TOPLEFT", 0, -top)
	preview:SetHeight(math.max(y - top, 36 + math.ceil(preview.lines:GetStringHeight() or 0) + 8))
	y = math.max(y, top + preview:GetHeight()) + 16
	frame.note:ClearAllPoints()
	frame.note:SetPoint("TOPLEFT", 0, -y)
	frame.note:SetPoint("TOPRIGHT", 0, -y)
end

BASE[#BASE + 1] = {
	key = "chat", short = "Chat", title = "Chat",
	desc = "Your chat windows for this character: EldoUI's tabs, a font size and class-colored names. The look of the chat panel itself is on the Styles step.",
	help = Key("Chat windows belong to the character, so this step is offered on every character, also one that uses a profile set up before.\n\nEldoUI chat tabs adds the checked tabs next to your main chat and moves those messages there. Reset chat windows first puts every chat window back to the game's defaults (custom tabs are closed), then adds EldoUI's tabs. Nothing is ever sent in chat.\n\nWhen the Blizzard UI step lets EldoUI move the chat, the main window sits in EldoUI's chat panel and stays there after Edit Mode changes."),
	Build = function(frame)
		frame.choices = {}
		local modes = {
			{ key = "keep", title = L["Keep my chat windows"], desc = L["Leave your chat tabs and what they show as they are."] },
			{ key = "tabs", title = L["EldoUI chat tabs"], desc = L["Your windows stay. The tabs checked below get their own window, docked next to the main chat."] },
			{ key = "reset", title = L["Reset chat windows"], desc = L["Every chat window back to the game's defaults, custom tabs closed, then EldoUI's tabs."] },
		}
		local gap = 12
		local width = math.floor((CONTENT_W - gap * (#modes - 1)) / #modes)
		for index, info in ipairs(modes) do
			local choice = Choice(frame, width, 64, info.title, info.desc, function()
				session.chat.mode = info.key
				if session.chat.state == "applied" then session.chat.state = "none" end
				Installer.Update()
			end)
			choice.mode = info.key
			choice:SetPoint("TOPLEFT", (index - 1) * (width + gap), 0)
			frame.choices[index] = choice
		end
		frame.checks = {}
		for index, tab in ipairs(CHAT_TABS) do
			local check = Check(frame, L[tab.label], L[tab.desc], function(on)
				session.chat[tab.key] = on
				if session.chat.state == "applied" then session.chat.state = "none" end
				Installer.Update()
			end)
			check:SetPoint("TOPLEFT", 412, -76 - (index - 1) * 30)
			check.key = tab.key
			frame.checks[index] = check
		end
		local y = -76 - #CHAT_TABS * 30
		frame.classColors = Check(frame, L["Class-colored names"], L["Names in say, party, raid, guild, whispers and channels show in their class color."], function(on)
			session.chat.classColors = on
			if session.chat.state == "applied" then session.chat.state = "none" end
			Installer.Update()
		end)
		frame.classColors:SetPoint("TOPLEFT", 412, y)
		frame.sizeLabel = E:CreateText(frame, E.tokens.size.body, "LEFT")
		frame.sizeLabel:SetPoint("TOPLEFT", 412, y - 36)
		frame.sizeLabel:SetText(L["Font size"])
		frame.sizes = {}
		local sizes = { false }
		for _, size in ipairs(ChatData.CHAT_FONT_SIZES) do sizes[#sizes + 1] = size end
		local x = 412 + 90
		for _, size in ipairs(sizes) do
			local button = Choice(frame, size and 44 or 60, 24, size and tostring(size) or L["Keep"], nil, function()
				session.chat.fontSize = size or nil
				if session.chat.state == "applied" then session.chat.state = "none" end
				Installer.Update()
			end)
			button:SetPoint("TOPLEFT", x, y - 30)
			x = x + (size and 44 or 60) + 4
			button.size = size
			Tooltip(button, L["Font size"], size and L["Every chat window uses size %d."]:format(size) or L["Each chat window keeps its own font size."])
			frame.sizes[#frame.sizes + 1] = button
		end
		frame.note = Secondary(Paragraph(frame, E.tokens.size.label, L["Tabs that already exist with these names are reused. You can rename, move or close them later from the tab's right-click menu, like any chat tab."]))
		-- Top corners only: a text below the middle of the page keeps the
		-- height of its own lines.
		frame.note:SetPoint("TOPLEFT", 0, y - 76)
		frame.note:SetPoint("TOPRIGHT", 0, y - 76)
		frame.place = Secondary(Paragraph(frame, E.tokens.size.label, ""))
		frame.place:SetPoint("TOPLEFT", frame.note, "BOTTOMLEFT", 0, -10)
		frame.place:SetPoint("TOPRIGHT", frame.note, "BOTTOMRIGHT", 0, -10)
		-- Preview: the tab row as the chat panel draws it (flat boxes, the
		-- open tab lifted with the accent underline), then where each kind
		-- of message goes.
		local preview = E.UIKit.SectionCard(frame)
		preview:SetPoint("TOPLEFT", 0, -76)
		preview:SetSize(400, -y - 76 + 60)
		preview.tabs = {}
		function preview.Tab(index)
			local tab = preview.tabs[index]
			if tab then return tab end
			tab = CreateFrame("Frame", nil, preview)
			tab:SetHeight(E.tokens.height.button)
			tab.box = tab:CreateTexture(nil, "BACKGROUND")
			tab.box:SetAllPoints()
			tab.lift = tab:CreateTexture(nil, "BORDER")
			tab.lift:SetAllPoints()
			tab.line = tab:CreateTexture(nil, "ARTWORK")
			tab.line:SetPoint("BOTTOMLEFT")
			tab.line:SetPoint("BOTTOMRIGHT")
			tab.line:SetHeight(2)
			tab.text = E:CreateText(tab, E.tokens.size.label, "CENTER")
			tab.text:SetPoint("CENTER")
			preview.tabs[index] = tab
			return tab
		end
		preview.lines = Secondary(Paragraph(preview, E.tokens.size.small, ""))
		preview.lines:SetPoint("TOPLEFT", 8, -36)
		preview.lines:SetWidth(400 - 16)
		frame.preview = preview
	end,
	Refresh = function(frame)
		local c = session.chat
		local available = ChatAvailable()
		for _, choice in ipairs(frame.choices) do
			choice:SetSelected(choice.mode == c.mode)
			if choice.mode ~= "keep" then choice:SetEnabledLook(available and true or false) end
		end
		local active = c.mode ~= "keep"
		for _, check in ipairs(frame.checks) do
			check:SetChecked(c[check.key] and true or false)
			check:SetEnabledLook(active)
		end
		frame.classColors:SetChecked(c.classColors and true or false)
		frame.classColors:SetEnabledLook(active)
		for _, button in ipairs(frame.sizes) do
			button:SetSelected((button.size or nil) == c.fontSize)
			button:SetEnabledLook(active)
		end
		local chat = E.modules.Chat
		local moves = chat and chat.active and chat.PanelMode and chat:PanelMode()
		frame.place:SetText(moves and L["Your main chat sits in EldoUI's chat panel and stays there after Edit Mode changes."]
			or L["Your main chat stays where the game puts it. The Blizzard UI step can let EldoUI move it into EldoUI's chat panel."])
		local general = L["General"]
		local tabs = { general }
		local lines = { L["Say, party, guild, raid and the rest: %s"]:format(E:Highlight(general)) }
		for _, tab in ipairs(CHAT_TABS) do
			local own = active and c[tab.key]
			if own then tabs[#tabs + 1] = L[tab.title] end
			lines[#lines + 1] = ("%s: %s"):format(L[tab.title], E:Highlight(own and L[tab.title] or general))
		end
		if c.mode == "reset" then lines[#lines + 1] = L["Other tabs you made are closed."] end
		local preview = frame.preview
		local r, g, b = Accent()
		local br, bg, bb = unpack(E.media.backdropColor)
		-- Roomy tabs, narrower when large text would push them past the edge.
		local textWidth = 0
		for index, name in ipairs(tabs) do
			local tab = preview.Tab(index)
			tab.text:SetText(name)
			textWidth = textWidth + math.ceil(tab.text:GetStringWidth())
		end
		local room = (preview:GetWidth() or 400) - 16 - (#tabs - 1) * 2 - textWidth
		local pad = math.max(6, math.min(20, math.floor(room / #tabs)))
		for index in ipairs(tabs) do
			local tab = preview.tabs[index]
			local open = index == 1
			tab:SetWidth(math.ceil(tab.text:GetStringWidth()) + pad)
			tab:ClearAllPoints()
			if open then
				tab:SetPoint("TOPLEFT", preview, "TOPLEFT", 8, -6)
			else
				tab:SetPoint("LEFT", preview.tabs[index - 1], "RIGHT", 2, 0)
			end
			tab.box:SetColorTexture(br, bg, bb, open and 1 or 0.6)
			tab.lift:SetColorTexture(1, 1, 1, E.tokens.hover.control)
			tab.lift:SetShown(open)
			tab.line:SetColorTexture(r, g, b, 1)
			tab.line:SetShown(open)
			if open then tab.text:SetTextColor(r, g, b) else tab.text:SetTextColor(unpack(E.media.text.secondary)) end
			tab:Show()
		end
		for index = #tabs + 1, #preview.tabs do preview.tabs[index]:Hide() end
		preview.lines:SetText(table.concat(lines, "\n"))
		Installer.LayoutChat(frame)
	end,
	Apply = Work.ApplyChatStep,
	HasChoice = function() return ChatHasChoice(session.chat) end,
	Summary = function()
		local c = session.chat
		if c.mode == "keep" or not ChatHasChoice(c) then return L["Chat: keep"] end
		local parts = {}
		if c.mode == "reset" then parts[#parts + 1] = L["windows reset"] end
		for _, tab in ipairs(CHAT_TABS) do
			if c[tab.key] then parts[#parts + 1] = L[tab.title] end
		end
		if c.fontSize then parts[#parts + 1] = L["font size %d"]:format(c.fontSize) end
		if c.classColors then parts[#parts + 1] = L["class-colored names"] end
		return L["Chat: %s"]:format(table.concat(parts, ", "))
	end,
}

do
-- Other addons step: the status column, and the room the name has
-- before it (the check box and its gap come first).
local ADDON_STATUS_X = 300
local ADDON_LABEL_W = ADDON_STATUS_X - 28 - 16

local function StatusText(status)
	if status == "missing" then return Dim(L["Not installed"]) end
	-- Nothing the player can do about it: information, not a warning.
	if status == "noprofile" then return Dim(L["No EldoUI profile yet"]) end
	if status == "ready" then return Good(L["Ready"]) end
	return status
end

BASE[#BASE + 1] = {
	key = "cvars", short = "Game settings", title = "Game settings",
	desc = "A few of the game's own interface settings that fit EldoUI. Only what is checked changes, and \"Blizzard default\" in /eui puts your own values back.",
	help = Key("These are settings from the game's own options window (Esc > Options). They only change how things look or read: nothing here plays for you.\n\nA setting the game already uses shows as set and is not written again. EldoUI remembers your value before it changes one, so Blizzard default in /eui puts it back.\n\nA second run starts with nothing checked, so clicking through changes nothing."),
	Build = function(frame)
		frame.rows = {}
		for index, info in ipairs(GAME_SETTINGS) do
			local check = Check(frame, L[info.label], L[info.desc], function(on)
				session.cvars.picks[info.key] = on
				if session.cvars.state == "applied" then session.cvars.state = "none" end
				Installer.Update()
			end)
			check.info = info
			check.status = Secondary(E:CreateText(frame, E.tokens.size.label, "LEFT"))
			check.status:SetPoint("LEFT", check, "LEFT", 360, 0)
			check.status:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
			frame.rows[index] = check
		end
		frame.note = Secondary(Paragraph(frame, E.tokens.size.label, L["Settings that act for you (auto loot, auto accept and the like) are never changed here."]))
	end,
	Refresh = function(frame)
		local c = session.cvars
		local y = 0
		for _, check in ipairs(frame.rows) do
			local status, owner = GameSettingStatus(check.info)
			check:SetShown(status ~= "missing")
			check.status:SetShown(status ~= "missing")
			if status ~= "missing" then
				check:ClearAllPoints()
				check:SetPoint("TOPLEFT", 0, y)
				y = y - 30
				local ready = status == "ready"
				check:SetChecked(ready and c.picks[check.info.key] and true or false)
				check:SetEnabledLook(ready)
				if status == "set" then
					check.status:SetText(Good(L["Already set"]))
				elseif status == "owned" then
					check.status:SetText(owner)
				else
					check.status:SetText("")
				end
			end
		end
		frame.note:ClearAllPoints()
		frame.note:SetPoint("TOPLEFT", 0, y - 12)
		frame.note:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, y - 12)
	end,
	Apply = Work.ApplyGameSettingsStep,
	HasChoice = function() return #GameSettingsPicked(session.cvars) > 0 end,
	Summary = function()
		local parts = {}
		for _, info in ipairs(GameSettingsPicked(session.cvars)) do parts[#parts + 1] = L[info.label] end
		if #parts == 0 then return L["Game settings: keep"] end
		return L["Game settings: %s"]:format(table.concat(parts, ", "))
	end,
}

BASE[#BASE + 1] = {
	key = "addons", short = "Addon profiles", title = "Addon profiles",
	desc = "EldoUI profiles for other addons you use, imported with each addon's own import function.",
	Build = function(frame)
		frame.rows = {}
		for index, name in ipairs(E.addonSetupOrder) do
			local setup = E.addonSetups[name]
			local check = Check(frame, setup.title, nil, function(on)
				session.addons.selected[name] = on or nil
				if session.addons.state == "applied" then session.addons.state = "none" end
				Installer.Update()
			end)
			-- The name keeps to its column and wraps there (Large text), so
			-- it never runs under the status beside it.
			check.label:SetWidth(ADDON_LABEL_W)
			check.label:SetJustifyH("LEFT")
			check:SetHitRectInsets(0, -math.min(ADDON_LABEL_W, math.ceil(check.label:GetStringWidth())) - 8, 0, 0)
			check.status = E:CreateText(frame, E.tokens.size.label, "LEFT")
			check.status:SetPoint("LEFT", check, "LEFT", ADDON_STATUS_X, 0)
			check.name = name
			frame.rows[index] = check
		end
		local note = Secondary(LiveText(Paragraph(frame, E.tokens.size.label), function()
			return L["Some addons ask once more in their own window before they import. A profile you made yourself can be saved with %s and is then used here."]:format(HL("/eui capture <addon>"))
		end))
		-- Refresh moves the note under the rows that show.
		note:SetPoint("TOPLEFT", 0, -12)
		note:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -12)
		-- A boss mod can pick its profile per specialization (its own Profiles
		-- page); EldoUI never changes that mapping, so it says so here.
		frame.specNote = Secondary(Paragraph(frame, E.tokens.size.label, L["BigWigs: if BigWigs switches profiles by specialization, a spec change can move it off the EldoUI profile. EldoUI leaves that setting alone; set the EldoUI profile for each spec in BigWigs' own Profiles page if you want it everywhere."]))
		frame.specNote:SetPoint("TOPLEFT", note, "BOTTOMLEFT", 0, -8)
		frame.specNote:SetPoint("TOPRIGHT", note, "BOTTOMRIGHT", 0, -8)
		frame.note = note
		-- Placement: one row per loaded addon a layout places (Modules/Integrations.lua).
		frame.places = CreateFrame("Frame", nil, frame)
		frame.places:SetPoint("TOPLEFT", frame.specNote, "BOTTOMLEFT", 0, 0)
		frame.places:SetPoint("TOPRIGHT", frame.specNote, "BOTTOMRIGHT", 0, 0)
		frame.places:SetHeight(1)
		frame.placesTitle = E:CreateText(frame.places, E.tokens.size.body, "LEFT")
		frame.placesTitle:SetPoint("TOPLEFT", 0, -12)
		frame.placesTitle:SetText(L["Placement in your layout"])
		frame.placeRows = {}
		for _, entry in ipairs(E.addonPlacements) do
			local check = Check(frame.places, entry.label, entry.desc, function(on)
				-- The tick as the switch is now: nothing to change.
				on = on and true or false
				if on == E:GetAddonPlacement(entry) then on = nil end
				session.addons.place[entry.key] = on
				if session.addons.state == "applied" then session.addons.state = "none" end
				Installer.Update()
			end)
			check.entry = entry
			frame.placeRows[#frame.placeRows + 1] = check
		end
		-- Next to the title, on its line: which addons EldoUI places with
		-- the ticks as they are, and which keep their own settings. One
		-- line, so the rows under it keep their room under Large text.
		frame.placesState = Secondary(E:CreateText(frame.places, E.tokens.size.label, "LEFT"))
		frame.placesState:SetPoint("BOTTOMLEFT", frame.placesTitle, "BOTTOMRIGHT", 16, 0)
		frame.placesState:SetWordWrap(false)
		-- The leveling guide: one pick for the layout's guide spot, under
		-- the placement rows, or on the placement title's line when every
		-- row is taken. What the pick does is in its tooltip.
		if E.modules.Eldostar and E.GUIDE_PROVIDER_ORDER then
			local guide = CreateFrame("Frame", nil, frame)
			guide:SetHeight(22)
			guide.label = E:CreateText(guide, E.tokens.size.body, "LEFT")
			guide.label:SetPoint("LEFT", 0, 0)
			guide.label:SetText(L["Leveling guide"])
			guide.box = Kit.Dropdown(guide, {
				width = 180,
				values = function()
					local list = {}
					for _, key in ipairs(E.GUIDE_PROVIDER_ORDER) do list[#list + 1] = { key, E.GUIDE_PROVIDER_TITLES[key] } end
					return list
				end,
				get = function() return Work.GuidePick(session.addons) end,
				set = function(value)
					session.addons.guide = value
					if session.addons.state == "applied" then session.addons.state = "none" end
					Installer.Update()
				end,
				tipTitle = L["Leveling guide"],
				tip = function(tooltip)
					E.UIKit.TipText(tooltip, L[E.GUIDE_PROVIDER_ROW_DESC])
					tooltip:AddLine(" ")
					E.UIKit.TipText(tooltip, E:GuideProviderStatus(Work.GuidePick(session.addons)))
				end,
			})
			guide.box:SetPoint("LEFT", guide.label, "RIGHT", 10, 0)
			frame.guide = guide
		end
	end,
	Refresh = function(frame)
		-- A row is 30 px, or taller when its name wraps; the check and
		-- the status stay centered on the name. An addon whose profile
		-- comes from a saved export string shows only while there is one
		-- for this layout or spec, so the step offers only what exists.
		local top = 0
		for _, check in ipairs(frame.rows) do
			local setup = E.addonSetups[check.name]
			local offered = not (setup and not setup.profile and E:GetAddonSetupStatus(check.name) == "noprofile")
			check:SetShown(offered)
			check.status:SetShown(offered)
			if offered then
				local height = math.max(30, math.ceil(check.label:GetStringHeight() or 0) + 12)
				check:ClearAllPoints()
				check:SetPoint("TOPLEFT", 0, -(top + (height - 30) / 2))
				top = top + height
			end
		end
		frame.note:ClearAllPoints()
		frame.note:SetPoint("TOPLEFT", 0, -top - 12)
		frame.note:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -top - 12)
		for _, check in ipairs(frame.rows) do
			local status = E:GetAddonSetupStatus(check.name)
			local text = StatusText(status)
			-- EldoUI ships a newer profile than the one this addon got before.
			if status == "ready" and E.AddonProfileUpdate and E:AddonProfileUpdate(check.name) then text = Warn(L["Newer profile ready"]) end
			-- A setup per class or spec names it in the player's words.
			local label = status == "noprofile" and E:AddonSetupKeyLabel(check.name)
			if label then text = Dim(L["Not available for %s yet"]:format(label)) end
			-- A missing addon may carry a hint, e.g. which boss mod works on Forever.
			local setup = E.addonSetups[check.name]
			if status == "missing" and setup and setup.missingHint then
				local ok, hint = pcall(setup.missingHint)
				if ok and type(hint) == "string" and hint ~= "" then text = text .. "\n" .. Muted(hint) end
			end
			check.status:SetText(text)
			if status ~= "ready" then session.addons.selected[check.name] = nil end
			check:SetChecked(session.addons.selected[check.name] and true or false)
			check:SetEnabledLook(status == "ready")
		end
		if frame.specNote then frame.specNote:SetShown(E:GetAddonSetupStatus("BigWigs") ~= "missing") end
		local above = frame.specNote:IsShown() and frame.specNote or frame.note
		frame.places:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, 0)
		frame.places:SetPoint("TOPRIGHT", above, "BOTTOMRIGHT", 0, 0)
		local shown, y, rowHeight = 0, 8, 30
		local managed, kept = {}, {}
		for _, check in ipairs(frame.placeRows) do
			local entry = check.entry
			local visible = E:AddonPlacementShown(entry)
			check:SetShown(visible)
			if visible then
				local want = session.addons.place[entry.key]
				if want == nil then want = E:GetAddonPlacement(entry) end
				check:SetChecked(want)
				local list = E:AddonPlacementStatus(entry, want) == "managed" and managed or kept
				list[#list + 1] = entry.title
				check:ClearAllPoints()
				-- Two columns, so five rows fit under the profile rows. A long
				-- name wraps inside its column (Large text), and the row
				-- grows with it.
				local label = check.label
				if label then
					label:SetWidth(CONTENT_W / 2 - 40)
					label:SetJustifyH("LEFT")
				end
				local column = shown % 2
				if column == 0 and shown > 0 then y, rowHeight = y + rowHeight, 30 end
				rowHeight = math.max(rowHeight, label and math.ceil(label:GetStringHeight() or 0) + 12 or 30)
				check:SetPoint("TOPLEFT", frame.placesTitle, "BOTTOMLEFT", column * CONTENT_W / 2, -y)
				shown = shown + 1
			end
		end
		local parts = {}
		if #managed > 0 then parts[#parts + 1] = Good(L["Managed by EldoUI"]) .. ": " .. table.concat(managed, ", ") end
		if #kept > 0 then parts[#parts + 1] = Dim(L["Keep my settings"]) .. ": " .. table.concat(kept, ", ") end
		frame.placesState:SetWidth(math.max(40, CONTENT_W - math.ceil(frame.placesTitle:GetStringWidth() or 0) - 16))
		frame.placesState:SetText(table.concat(parts, "    "))
		frame.places:SetShown(shown > 0)
		local guide = frame.guide
		if guide then
			guide:ClearAllPoints()
			guide:SetWidth(math.ceil(guide.label:GetStringWidth() or 0) + 10 + 180)
			if shown > 4 then
				-- Every row is taken: on the title's line, at its right end.
				guide:SetPoint("BOTTOMLEFT", frame.placesTitle, "BOTTOMLEFT", CONTENT_W - guide:GetWidth(), -5)
				frame.placesState:SetWidth(math.max(40, CONTENT_W - math.ceil(frame.placesTitle:GetStringWidth() or 0)
					- 32 - guide:GetWidth()))
			elseif shown > 0 then
				guide:SetPoint("TOPLEFT", frame.placesTitle, "BOTTOMLEFT", 0, -(y + rowHeight + 4))
			else
				guide:SetPoint("TOPLEFT", frame.specNote:IsShown() and frame.specNote or frame.note, "BOTTOMLEFT", 0, -16)
			end
			guide.box:Refresh()
		end
	end,
	Apply = Work.ApplyAddonsStep,
	HasChoice = function()
		return next(session.addons.selected) ~= nil or #E:AddonPlacementChanges(session.addons.place) > 0
			or Work.GuidePickChanged(session.addons)
	end,
	Summary = function()
		local parts = {}
		for _, name in ipairs(E.addonSetupOrder) do
			if session.addons.selected[name] then parts[#parts + 1] = E.addonSetups[name].title end
		end
		for _, entry in ipairs(E.addonPlacements) do
			local want = session.addons.place[entry.key]
			if want ~= nil and E:AddonPlacementShown(entry) then
				parts[#parts + 1] = (want and L["%s placed by the layout"] or L["%s left in its own spot"]):format(entry.title)
			end
		end
		if Work.GuidePickChanged(session.addons) then
			parts[#parts + 1] = L["Leveling guide: %s"]:format(L[E.GUIDE_PROVIDER_TITLES[session.addons.guide]])
		end
		if #parts == 0 then return L["Other addons: none"] end
		return L["Other addons: %s"]:format(table.concat(parts, ", "))
	end,
}

end

-- The rows in two columns, one group per module under its title (each
-- group goes into the shorter column). The repair row has the guild/own
-- gold pick under it: two cards of the same height, which grows with
-- their text. A label wraps inside its column (Large text) and its row
-- grows with it. The notes follow under both columns.
local function LayoutConvenience(frame)
	local CONVENIENCE_GAP = 16
	local childWidth = CONTENT_W - 22
	local columnWidth = math.floor((childWidth - CONVENIENCE_GAP) / 2)
	local heights = { 0, 0 }
	for _, group in ipairs(frame.groups) do
		local column = heights[2] < heights[1] and 2 or 1
		local x, y = (column - 1) * (columnWidth + CONVENIENCE_GAP), heights[column]
		group.caption:ClearAllPoints()
		group.caption:SetPoint("TOPLEFT", x, -y)
		y = y + 20
		for _, check in ipairs(group.checks) do
			check.label:SetWidth(columnWidth - 32)
			check.label:SetWordWrap(true)
			check.label:SetJustifyH("LEFT")
			check:SetLabel(check.label:GetText())
			local height = math.max(26, math.ceil(check.label:GetStringHeight() or 0) + 10)
			check:ClearAllPoints()
			check:SetPoint("TOPLEFT", x, -(y + (height - 24) / 2))
			y = y + height
			if check.row.id == "repair" then
				local cardWidth = math.floor((columnWidth - 28 - 8) / 2)
				local cards = 0
				for _, choice in ipairs(frame.modes) do
					choice:SetWidth(cardWidth)
					choice.minHeight = 40
					cards = math.max(cards, choice:FitHeight())
				end
				for index, choice in ipairs(frame.modes) do
					choice.minHeight = cards
					choice:FitHeight()
					choice:ClearAllPoints()
					choice:SetPoint("TOPLEFT", x + 28 + (index - 1) * (cardWidth + 8), -y)
				end
				y = y + cards + 8
			end
		end
		heights[column] = y + 12
	end
	local y = math.max(heights[1], heights[2])
	for _, note in ipairs({ frame.keysNote, frame.note }) do
		if note:IsShown() then
			note:ClearAllPoints()
			note:SetPoint("TOPLEFT", 0, -y)
			note:SetWidth(childWidth)
			y = y + math.ceil(note:GetStringHeight() or 0) + 8
		end
	end
	frame.child:SetHeight(math.max(10, y))
end

BASE[#BASE + 1] = {
	key = "convenience", short = "Convenience", title = "Convenience",
	desc = "Every helper that acts for you, one line each. Repairs, selling gray items and faster auto loot start checked on a first setup; uncheck any you don't want. The others stay off until you check them.",
	Build = function(frame)
		local function Changed()
			Touch("convenience")
			if session.convenience.state == "applied" then session.convenience.state = "none" end
			Installer.Update()
		end
		-- "Recommended for me": the rows that suit this character, and only those.
		local recommend = Button(frame, { text = L["Recommended for me"], tipTitle = L["Recommended for me"],
			tip = L["Checks the helpers that suit this character (its class and level) and unchecks the others. Nothing changes until you apply."],
			onClick = function()
				for _, row in ipairs(ConvenienceRows()) do session.convenience[row.id] = E:ConvenienceSuits(row) end
				Changed()
			end })
		recommend:SetPoint("TOPLEFT", 0, 0)
		frame.recommend = recommend
		frame.count = Secondary(E:CreateText(frame, E.tokens.size.label, "LEFT"))
		frame.count:SetPoint("LEFT", recommend, "RIGHT", 16, 0)
		local holder = CreateFrame("Frame", nil, frame)
		holder:SetPoint("TOPLEFT", 0, -36)
		holder:SetPoint("BOTTOMRIGHT", 0, 0)
		local _, child = ScrollArea(holder)
		frame.child = child
		frame.checks, frame.groups = {}, {}
		local group, keys = nil, {}
		for _, row in ipairs(E:Conveniences()) do
			if row.group == "keys" then
				keys[#keys + 1] = row
			else
				if not group or group.module ~= (row.module or "") then
					local module = row.module and E.modules[row.module]
					group = { module = row.module or "", checks = {} }
					group.caption = E:CreateText(child, E.tokens.size.label, "LEFT")
					group.caption:SetText(E:CaptionText(module and L[module.title] or L["General"]))
					group.caption:SetTextColor(E:TokenColor("accent"))
					frame.groups[#frame.groups + 1] = group
				end
				local check = Check(child, L[row.label], L[row.desc], function(on)
					session.convenience[row.id] = on
					Changed()
				end)
				check.row = row
				group.checks[#group.checks + 1] = check
				frame.checks[#frame.checks + 1] = check
			end
		end
		frame.modes = {}
		for index, info in ipairs(REPAIR_MODES) do
			local choice = Choice(child, 180, 40, L[info.title], L[info.desc], function()
				session.convenience.repairMode = info.key
				Changed()
			end)
			choice.mode = info.key
			frame.modes[index] = choice
		end
		-- Helpers of the Keys and spells step are only named here.
		local names = {}
		for _, row in ipairs(keys) do names[#names + 1] = L[row.label] end
		frame.keysNote = Secondary(Paragraph(child, E.tokens.size.label))
		frame.keysNote:SetText(#names > 0 and L["On the Keys and spells step: %s."]:format(table.concat(names, ", ")) or "")
		frame.keysNote:SetShown(#names > 0)
		frame.note = Secondary(LiveText(Paragraph(child, E.tokens.size.label), function()
			return L["Only what is checked is turned on. Change any of these later on the Conveniences page in %s, or on each module's own page."]:format(HL("/eui"))
		end))
		LayoutConvenience(frame)
	end,
	Refresh = function(frame)
		local c = session.convenience
		local ticked = 0
		for _, check in ipairs(frame.checks) do
			local row = check.row
			local off = ConvenienceOff(row)
			local on = c[row.id] and not off and true or false
			check:SetChecked(on)
			check:SetEnabledLook(not off)
			local module = row.module and E.modules[row.module]
			check:SetLabel(off and module and (L[row.label] .. " " .. Dim(L["(%s is off)"]:format(L[module.title]))) or L[row.label])
			-- The tooltip says why a row is grayed, or what else it waits for.
			local reason = off or E:ConvenienceBlocked(row)
			Tooltip(check, L[row.label], reason and (L[row.desc] .. "\n\n" .. reason) or L[row.desc])
			if on then ticked = ticked + 1 end
		end
		local repair = E:Convenience("repair")
		local repairOn = c.repair and repair and not ConvenienceOff(repair)
		for _, choice in ipairs(frame.modes) do
			choice:SetSelected(choice.mode == c.repairMode)
			choice:SetEnabledLook(repairOn and true or false)
		end
		frame.count:SetText(L["%d of %d checked"]:format(ticked, #frame.checks))
		LayoutConvenience(frame)
	end,
	Apply = Work.ApplyConvenienceStep,
	HasChoice = function() return ConvenienceWork(session.convenience) > 0 end,
	Summary = function()
		local c = session.convenience
		local parts = {}
		for _, row in ipairs(ConvenienceRows()) do
			if c[row.id] and not ConvenienceOff(row) then
				if row.id == "repair" then
					parts[#parts + 1] = c.repairMode == "guild" and L["repair (guild bank first)"] or L["repair (own gold)"]
				else
					-- The label as a list item: its first letter in lower case.
					local label = L[row.label]
					parts[#parts + 1] = label:match("^%u") and (label:sub(1, 1):lower() .. label:sub(2)) or label
				end
			end
		end
		if #parts == 0 then return L["Convenience: none"] end
		return L["Convenience: %s"]:format(table.concat(parts, ", "))
	end,
}

---------------------------------------------------------------------------
-- Keys and spells: the key set, the class spells and macros and
-- the spell rank upgrades in one preview (Core/KeybindPreview.lua), and
-- the player's key map choice (Core/KeymapSync.lua): how they play, the
-- keyboard, what happens with spells learned later and on their other
-- characters, keys shown on bars 1 to 3. Each answer starts on the
-- profile's choice, or the pack's pick on a first run. The last of the
-- installer's own steps, before the setup pages and Finish, on every
-- path: Express shows it too, with the pack's picks. Nothing touches a
-- key, a button or the choice until this step's own Apply; Finish never
-- applies it for you, and Skip leaves keys and buttons alone.
---------------------------------------------------------------------------
local Keys = {}
Installer.Keys = Keys

-- What keeps the picked key set from working well (paging on a key set's
-- modifier, key text hidden on bars 1 to 3), or an empty list.
function Keys.Issues(k)
	if not E.KeymapIssues or k.own then return {} end
	return E:KeymapIssues(k.preset)
end

function Keys.HasIssue(list, kind)
	for _, issue in ipairs(list) do
		if issue.kind == kind then return true end
	end
	return false
end

-- The step's picks: preset (or own keys), the boxes, the key map answers,
-- rank ticks and manual keys given to the preset. A first run ticks the
-- class spells and macros; a re-run starts from the profile's choice.
function Keys.Picks()
	local k = session.keys
	if not k then
		k = { state = "none" }
		session.keys = k
		local record = E.KeymapRecord and E:KeymapRecord()
		if record then
			if record.preset == "none" then
				k.own = true
			elseif E:KeybindPresetKey(record.preset) then
				k.preset = E:KeybindPresetKey(record.preset)
			end
			if record.spells == false then k.spells = false end
			k.newSpells, k.alts = E:KeymapSetting("newSpells"), E:KeymapSetting("alts")
			if E:KeymapSetting("showKeys") then k.showKeys = true end
		end
		local global = E.global and E.global.keymap
		k.keyboard = type(global) == "table" and type(global.keyboard) == "string" and global.keyboard or ""
	end
	if not (k.preset and E.keybindPresets[k.preset]) then
		local recommended = E.keybindPresetOrder[1]
		for _, id in ipairs(E.keybindPresetOrder) do
			if E.keybindPresets[id].recommended then recommended = id end
		end
		k.preset = recommended
	end
	if k.spells == nil then k.spells = true end
	if k.macros == nil then k.macros = not session.rerun end
	k.newSpells, k.alts = k.newSpells or "offer", k.alts or "offer"
	k.keyboard = k.keyboard or ""
	if k.paging == nil then k.paging = true end
	k.ranks, k.take = k.ranks or {}, k.take or {}
	return k
end

function Keys.Plan()
	local k = Keys.Picks()
	k.plan = E:KeysAndSpellsPlan({ id = k.preset, take = k.take, spells = k.spells, macros = k.macros, ranks = k.ranks })
	-- Keys the player set by hand stay, and own keys write none.
	if E.KeymapKeysAndSpells then E:KeymapKeysAndSpells(k.plan, k.own) end
	return k.plan
end

-- Keys on bars 1 to 3: the player's or the pack's pick, else ticked
-- while the text style hides them there (the style is the one the run
-- applied before this step).
function Keys.ShowKeys(k)
	if k.showKeys ~= nil then return k.showKeys end
	return E.KeymapStyleHidesKeys and E:KeymapStyleHidesKeys() ~= nil or false
end

-- The answers as the profile's key map choice.
function Keys.Choice(k)
	return { preset = k.own and "none" or k.preset, spells = k.spells, newSpells = k.newSpells, alts = k.alts,
		showKeys = Keys.ShowKeys(k), keyboard = k.keyboard }
end

-- A pack's key map picks (Data/Packs.lua), on top of the profile's.
function Keys.FromPack(pack)
	local keymap = type(pack) == "table" and type(pack.keymap) == "table" and pack.keymap or {}
	local k = Keys.Picks()
	local preset = E:KeybindPresetKey(keymap.preset or pack.keybinds)
	if preset then k.preset, k.own = preset, nil end
	if keymap.preset == "none" then k.own = true end
	for _, field in ipairs({ "newSpells", "alts" }) do
		if keymap[field] then k[field] = keymap[field] end
	end
	if keymap.showKeys ~= nil then k.showKeys = keymap.showKeys and true or false end
	k.plan = nil
end

-- Something Apply would write besides keys and buttons: an answer that
-- differs from the profile's choice, or a fix that is ticked.
function Keys.ChoiceChanged(k)
	if not E.KeymapSetting then return false end
	local choice = Keys.Choice(k)
	for _, field in ipairs({ "preset", "spells", "newSpells", "alts", "showKeys" }) do
		if E:KeymapSetting(field) ~= choice[field] then return true end
	end
	local global = E.global and E.global.keymap
	if type(global) == "table" and (global.keyboard or "") ~= k.keyboard then return true end
	return k.paging and Keys.HasIssue(Keys.Issues(k), "paging") or false
end

-- Writes the answers into the profile and fixes the ticked issues.
function Keys.Record(k)
	if not E.SetKeymap then return end
	local fix = {}
	if k.paging then
		for _, issue in ipairs(Keys.Issues(k)) do
			if issue.kind == "paging" then fix[#fix + 1] = issue end
		end
	end
	E:SetKeymap(Keys.Choice(k))
	if #fix > 0 then E:FixKeymapIssues(fix) end
end

-- A pick changed: the step is not applied any more.
local function KeysChanged()
	Touch("keys")
	if session.keys.state == "applied" or session.keys.state == "skipped" then session.keys.state = "none" end
	Installer.Update()
end

-- The class setup's part of an Apply: kept first for Revert this, and
-- named on the last page. Runs only from this step's Apply.
function Entry.ExpressPremade(plan)
	local slots, macros = plan.counts.premade, plan.counts.macros
	if slots + macros == 0 then return end
	local group = ChangeGroup("class")
	Remember("class", "premade")
	group.texts = group.texts or {}
	group.texts.premade = L["Class setup: %s, %s"]:format(
		(slots == 1 and L["%d action slot"] or L["%d action slots"]):format(slots),
		(macros == 1 and L["%d macro"] or L["%d macros"]):format(macros))
	if E.SetInstallStepState then E:SetInstallStepState("EldoUI:classPremade", "applied") end
end
Installer.NotePremade = Entry.ExpressPremade

-- Apply: the answers go into the profile, then the plan shown, checked
-- once more and written out of combat. Returns false when the keys could
-- not be set (a spell on the cursor, keys changed since the preview): the
-- step then stays, with its warning, and nothing says "applied".
function Work.ApplyKeysStep()
	local k = Keys.Picks()
	local plan = k.plan or Keys.Plan()
	Keys.Record(k)
	Entry.ExpressPremade(plan)
	local ok, why = E:ApplyKeysAndSpells(plan, false)
	k.plan = nil
	if not ok and why ~= "queued" then
		if why ~= "same" and Installer.ShowToast then
			local _, notice = E:KeysAndSpellsBlocked(plan)
			Installer.ShowToast(notice or L["Your keys or action buttons changed since the preview. Look at the preview again before you apply."], true)
		end
		if why ~= "same" then return false end
		return
	end
	k.state = "applied"
end

-- The answers' dropdowns: { value, text } lists.
function Keys.ModeValues()
	local list = {}
	for _, mode in ipairs(E.keymapModes or { "offer", "auto", "off" }) do
		list[#list + 1] = { mode, (E.keymapModeText or {})[mode] or mode }
	end
	return list
end

function Keys.KeyboardValues()
	local guess = E.keyboardLayouts[E:KeyboardLanguageGuess()]
	local list = { { "", L["Guess from the game language (%s)"]:format(L[guess.title]) } }
	for _, id in ipairs(E.keyboardLayoutOrder) do list[#list + 1] = { id, L[E.keyboardLayouts[id].title] } end
	return list
end

-- One label over its dropdown.
function Keys.Answer(frame, title, tip, opts)
	local holder = CreateFrame("Frame", nil, frame)
	holder:SetSize(opts.width, 44)
	holder.label = E:CreateText(holder, E.tokens.size.label, "LEFT")
	holder.label:SetPoint("TOPLEFT", 0, 0)
	holder.label:SetPoint("TOPRIGHT", 0, 0)
	holder.label:SetText(Muted(title))
	opts.tipTitle, opts.tip = title, tip
	holder.box = Kit.Dropdown(holder, opts)
	holder.box:SetPoint("TOPLEFT", holder.label, "BOTTOMLEFT", 0, -4)
	return holder
end

local function KeysLayout(frame)
	local width = CONTENT_W - 22
	local y = 0
	frame.text:SetWidth(width)
	frame.text:ClearAllPoints()
	frame.text:SetPoint("TOPLEFT", 0, 0)
	y = y + math.ceil(frame.text:GetStringHeight() or 0) + 10
	for _, fix in ipairs({ frame.showKeys, frame.paging }) do
		if fix:IsShown() then
			fix:ClearAllPoints()
			fix:SetPoint("TOPLEFT", 0, -y)
			y = y + math.max(fix:GetHeight(), 22) + 6
		end
	end
	if frame.gameKeys:IsShown() then
		frame.gameKeys:SetWidth(width)
		frame.gameKeys:ClearAllPoints()
		frame.gameKeys:SetPoint("TOPLEFT", 0, -y)
		y = y + math.ceil(frame.gameKeys:GetStringHeight() or 0) + 10
	end
	frame.ranksLabel:ClearAllPoints()
	frame.ranksLabel:SetPoint("TOPLEFT", 0, -y)
	y = y + math.ceil(frame.ranksLabel:GetStringHeight() or 0) + 6
	frame.autoRanks:ClearAllPoints()
	frame.autoRanks:SetPoint("TOPLEFT", 0, -y)
	y = y + frame.autoRanks:GetHeight() + 6
	for _, row in ipairs(frame.rankRows) do
		if row:IsShown() then
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", 0, -y)
			row.keep:ClearAllPoints()
			row.keep:SetPoint("TOPRIGHT", frame.list, "TOPLEFT", width, -y)
			y = y + math.max(row:GetHeight(), row.keep:GetHeight()) + 6
		end
	end
	if frame.noRanks:IsShown() then
		frame.noRanks:SetWidth(width)
		frame.noRanks:ClearAllPoints()
		frame.noRanks:SetPoint("TOPLEFT", 0, -y)
		y = y + math.ceil(frame.noRanks:GetStringHeight() or 0) + 6
	end
	y = y + 6
	frame.protected:SetWidth(width)
	frame.protected:ClearAllPoints()
	frame.protected:SetPoint("TOPLEFT", 0, -y)
	y = y + math.ceil(frame.protected:GetStringHeight() or 0) + 8
	frame.list:SetHeight(y)
end

-- The game's own shortcuts, with where each one goes after the key set.
function Keys.GameKeysText(plan, own)
	if not E.GameKeysList then return nil end
	local ok, rows = pcall(E.GameKeysList, E, not own and plan.keys or nil)
	if not ok or type(rows) ~= "table" or #rows == 0 then return nil end
	local lines = { Muted(L["Where the game's own shortcuts are"]) }
	for _, row in ipairs(rows) do
		local keys = {}
		for _, key in ipairs(type(row.keys) == "table" and row.keys or {}) do keys[#keys + 1] = E:KeybindKeyText(key) end
		local now = #keys > 0 and table.concat(keys, ", ") or L["no key"]
		local label = E:Translate(row.label) or row.command or "?"
		if not own and type(row.home) == "string" and row.home ~= "" and not tContains(row.keys or {}, row.home) then
			lines[#lines + 1] = L["%s: %s, then %s"]:format(label, now, E:KeybindKeyText(row.home))
		else
			lines[#lines + 1] = L["%s: %s"]:format(label, now)
		end
	end
	return table.concat(lines, "\n")
end

BASE[#BASE + 1] = {
	key = "keys", short = "Keys and spells", title = "Keys and spells",
	desc = "Set up keys for bars 1 to 3 and fill empty buttons with your class spells, and see every change first. Only this step's Apply changes your keys and buttons, and Finish leaves them alone.",
	-- Applied only by its own Apply, never by Finish.
	explicit = true,
	Build = function(frame)
		frame.presets = {}
		local function Card(id, title, desc, onClick)
			local choice = Choice(frame, 200, 64, title, desc, onClick)
			choice.preset = id
			frame.presets[#frame.presets + 1] = choice
		end
		for _, id in ipairs(E.keybindPresetOrder) do
			local preset = E.keybindPresets[id]
			local title = preset.recommended and L["%s (recommended)"]:format(L[preset.title]) or L[preset.title]
			Card(id, title, L[preset.short or preset.movementText], function()
				local k = Keys.Picks()
				k.preset, k.own = id, nil
				wipe(session.keys.take)
				KeysChanged()
			end)
		end
		if E.KeymapManaged then
			Card("none", L["I manage my own keys"],
				L["EldoUI never writes a key. Class spells on empty buttons, the preview and hover binding still work."], function()
					Keys.Picks().own = true
					wipe(session.keys.take)
					KeysChanged()
				end)
		end
		frame.spells = Check(frame, L["Also put class spells on empty buttons"],
			L["Your known class spells go on the empty buttons of their category on bars 1 to 3. A button with your own action keeps it, and a spell already on your bars is not moved."],
			function(on)
				Keys.Picks().spells = on and true or false
				KeysChanged()
			end)
		frame.macros = Check(frame, L["Also add the class macros"],
			L["Your class setup's character macros, each under its own name. A macro you already have by that name is never changed."],
			function(on)
				Keys.Picks().macros = on and true or false
				KeysChanged()
			end)
		frame.open = Button(frame, { text = L["Show every key"], minWidth = 140,
			tip = L["Opens the keyboard view of this plan: each key, its category and the spell meant for it."],
			onClick = function()
				local k = Keys.Picks()
				E:OpenKeysAndSpells(nil, { id = k.preset, spells = k.spells, macros = k.macros, ranks = k.ranks })
			end })
		frame.answers = {}
		if E.KeymapSetting then
			local third = math.floor((CONTENT_W - 24) / 3)
			frame.newSpells = Keys.Answer(frame, L["Spells you learn later"],
				L["A spell you learn at a trainer or with a talent, when its button is empty. Ask me: one alert with a preview. Automatic: it goes on its button out of combat, with Undo. Off: nothing happens."],
				{ width = third - 12, values = Keys.ModeValues, get = function() return Keys.Picks().newSpells end,
					set = function(value) Keys.Picks().newSpells = value KeysChanged() end })
			frame.alts = Keys.Answer(frame, L["Your other characters"],
				L["A character on this profile whose keys differ from this key set (a new character, or keys the game reset). Ask me: one alert with a preview. Automatic: its keys are set out of combat, with a backup and Undo. Off: nothing happens. Keys you set yourself are never written over."],
				{ width = third - 12, values = Keys.ModeValues, get = function() return Keys.Picks().alts end,
					set = function(value) Keys.Picks().alts = value KeysChanged() end })
			frame.answers = { frame.newSpells, frame.alts }
			frame.keyboard = Keys.Answer(frame, L["Keyboard"],
				L["The key sets use the keys in the same places on every keyboard. Pick yours, or let EldoUI guess from the game language."],
				{ width = third - 12, values = Keys.KeyboardValues, get = function() return Keys.Picks().keyboard end,
					set = function(value) Keys.Picks().keyboard = value KeysChanged() end })
			frame.answers[3] = frame.keyboard
		end
		local holder = CreateFrame("Frame", nil, frame)
		frame.holder = holder
		local _, child = ScrollArea(holder)
		frame.list = child
		frame.text = Paragraph(child, E.tokens.size.body)
		frame.showKeys = Check(child, L["Show the keys on bars 1 to 3"],
			L["Your text style hides the keys on the action buttons. This shows them on bars 1 to 3 only, so you can see the keys you set; the other bars keep the style."],
			function(on)
				Keys.Picks().showKeys = on and true or false
				KeysChanged()
			end)
		frame.paging = Check(child, L["Keep bars 1 to 3 from switching on Shift, Ctrl or Alt"],
			L["One of bars 1 to 3 shows another bar while Shift, Ctrl or Alt is held, and this key set puts keys on that modifier there. Checked, the bar keeps its own buttons, so those keys press them. The Action Bars page can change it back."],
			function(on)
				Keys.Picks().paging = on and true or false
				KeysChanged()
			end)
		frame.gameKeys = Paragraph(child, E.tokens.size.body)
		frame.ranksLabel = E:CreateText(child, E.tokens.size.body, "LEFT")
		-- The automatic rank upgrade (Modules/ActionBars/Ranks.lua): a
		-- setting, saved when ticked; it moves no button by itself here.
		frame.autoRanks = Check(child, L["Upgrade spell ranks automatically"],
			L["From now on, move lower ranks on every bar you use to the highest rank you know after you learn one and at login, out of combat, with a chat line. Saved when you check it; the rows below still change only with Apply."],
			function(on)
				local module = E.modules.ActionBars
				if module and module.db and module.db.ranks then module.db.ranks.auto = on and true or false end
			end)
		frame.noRanks = Secondary(Paragraph(child, E.tokens.size.label))
		frame.rankRows = {}
		frame.protected = Paragraph(child, E.tokens.size.body)
	end,
	Refresh = function(frame)
		local k = Keys.Picks()
		local plan = Keys.Plan()
		local P = E.KeybindPreview
		-- The cards: up to four in a row.
		local gap, count = 12, #frame.presets
		local perRow = count <= 4 and count or 3
		local cardW = math.floor((CONTENT_W - gap * (perRow - 1)) / perRow)
		local heights = {}
		for index, choice in ipairs(frame.presets) do
			local row = math.floor((index - 1) / perRow) + 1
			choice:SetWidth(cardW)
			if choice.FitHeight then choice:FitHeight() end
			heights[row] = math.max(heights[row] or 64, math.ceil(choice:GetHeight() or 64))
			choice:SetSelected(k.own and choice.preset == "none" or (not k.own and choice.preset == k.preset))
		end
		local top, rowTop = 0, {}
		for row, height in ipairs(heights) do
			rowTop[row] = top
			top = top + height + gap
		end
		for index, choice in ipairs(frame.presets) do
			local col, row = (index - 1) % perRow, math.floor((index - 1) / perRow) + 1
			choice:ClearAllPoints()
			choice:SetPoint("TOPLEFT", col * (cardW + gap), -rowTop[row])
			choice:SetHeight(heights[row])
		end
		frame.spells:ClearAllPoints()
		frame.spells:SetPoint("TOPLEFT", 0, -top)
		frame.spells:SetChecked(k.spells)
		frame.macros:ClearAllPoints()
		frame.macros:SetPoint("TOPLEFT", 0, -(top + 30))
		frame.macros:SetChecked(k.macros)
		frame.macros:SetEnabledLook(plan.premade.adds > 0)
		frame.open:ClearAllPoints()
		frame.open:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -top)
		local below = top + 66
		if #frame.answers > 0 then
			local third = math.floor((CONTENT_W - 24) / 3)
			local tallest = 0
			for index, answer in ipairs(frame.answers) do
				answer:ClearAllPoints()
				answer:SetPoint("TOPLEFT", (index - 1) * (third + 12), -below)
				answer.box:Refresh()
				local height = math.ceil(answer.label:GetStringHeight() or 0) + 4 + answer.box:GetHeight()
				answer:SetHeight(height)
				tallest = math.max(tallest, height)
			end
			if frame.alts then frame.alts.box:SetAlpha(k.own and 0.5 or 1) end
			below = below + tallest + 8
		end
		frame.holder:ClearAllPoints()
		frame.holder:SetPoint("TOPLEFT", 0, -below)
		frame.holder:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
		-- What changes: keys, then the class spells and macros.
		local lines = { Muted(L["What Apply changes"]) }
		local c = plan.counts
		if k.own then
			lines[#lines + 1] = L["You manage your own keys: no key changes, and EldoUI never offers keys on your other characters."]
		else
			lines[#lines + 1] = E:Plural(c.keys, "%d key changes on bars 1 to 3.", "%d keys change on bars 1 to 3."):format(c.keys)
			-- Keys of manual bars are listed under Kept as they are.
			for _, change in ipairs(P.KeyChangeLines(plan.keys)) do
				if not change.take then lines[#lines + 1] = change.text end
			end
			local own = plan.keys.own and #plan.keys.own or 0
			if own > 0 then
				lines[#lines + 1] = E:Plural(own, "%d key you set yourself stays as it is.", "%d keys you set yourself stay as they are."):format(own)
			end
		end
		if k.spells then
			for _, text in ipairs(P.PremadeLines(plan)) do lines[#lines + 1] = text end
		end
		lines[#lines + 1] = L["Bar 4 and the other bars stay manual: their keys and spells are yours."]
		if E.KeymapBindingSetText and not k.own then lines[#lines + 1] = E:KeymapBindingSetText() end
		frame.text:SetText(table.concat(lines, "\n"))
		-- What gets in the way, each with its fix ticked.
		local issues = Keys.Issues({ own = k.own, preset = k.preset })
		local hidden = E.KeymapStyleHidesKeys and E:KeymapStyleHidesKeys()
		frame.showKeys:SetShown(hidden and not k.own or false)
		frame.showKeys:SetChecked(Keys.ShowKeys(k))
		frame.paging:SetShown(Keys.HasIssue(issues, "paging"))
		frame.paging:SetChecked(k.paging)
		local gameKeys = Keys.GameKeysText(plan, k.own)
		frame.gameKeys:SetText(gameKeys or "")
		frame.gameKeys:SetShown(gameKeys ~= nil)
		-- Spell ranks: bars 1-3 ticked, manual bars unticked.
		frame.ranksLabel:SetText(Muted(L["Spell ranks"]))
		local ranksDB = E.modules.ActionBars and E.modules.ActionBars.db and E.modules.ActionBars.db.ranks
		frame.autoRanks:SetChecked(ranksDB and ranksDB.auto and true or false)
		local index = 0
		for _, entry in ipairs(plan.ranks) do
			if entry.status == "upgrade" then
				index = index + 1
				local row = frame.rankRows[index]
				if not row then
					row = Check(frame.list, "", L["Move this button to the highest rank you know when you apply."], function(on)
						if row.slot then
							Keys.Picks().ranks[row.slot] = on and true or false
							KeysChanged()
						end
					end)
					row.keep = Button(frame.list, { text = L["Keep this rank"], minWidth = 110,
						tip = L["Keeps this one button at its rank on purpose (a low rank for mana, for example). It is never upgraded or lit up until you change what it holds."],
						onClick = function()
							local module = E.modules.ActionBars
							if row.slot and module and module.KeepRank then
								module:KeepRank(row.slot, row.from)
								Keys.Picks().ranks[row.slot] = nil
								KeysChanged()
							end
						end })
					frame.rankRows[index] = row
				end
				row.slot, row.from = entry.slot, entry.from
				row:SetLabel(P.RankText(entry))
				row:SetChecked(entry.tick)
				row:Show()
				row.keep:Show()
			end
		end
		for i = index + 1, #frame.rankRows do
			frame.rankRows[i]:Hide()
			frame.rankRows[i].keep:Hide()
		end
		frame.noRanks:SetText(L["Every spell on your action bars uses the highest rank you know."])
		frame.noRanks:SetShown(index == 0)
		-- Protected: what stays, and why.
		local kept = P.ProtectedLines(plan)
		local protected = { Muted(L["Kept as they are"]) }
		if #kept == 0 then protected[2] = L["Nothing: every button and key in the plan is free to change."] end
		for _, text in ipairs(kept) do protected[#protected + 1] = "- " .. text end
		frame.protected:SetText(table.concat(protected, "\n"))
		KeysLayout(frame)
	end,
	Apply = Work.ApplyKeysStep,
	HasChoice = function()
		local k = Keys.Picks()
		-- Skipped means "leave my keys and buttons".
		if k.state == "skipped" then return false end
		local plan = k.plan or Keys.Plan()
		return plan.counts.total > 0 or Keys.ChoiceChanged(k)
	end,
	Summary = function()
		local k = Keys.Picks()
		local preset = E.keybindPresets[k.preset]
		local parts = { k.own and L["your own keys"] or (preset and L[preset.title] or k.preset) }
		if k.spells then parts[#parts + 1] = L["class spells on empty buttons"] end
		if k.macros then parts[#parts + 1] = L["class macros"] end
		return L["Keys and spells: %s"]:format(table.concat(parts, ", "))
	end,
}

---------------------------------------------------------------------------
-- Step: controller. Only with a controller: Gamepad Mode UI places
-- EldoUI's frames for controller play while the game's gamepad interface
-- is on (Core/GamepadMode.lua). Keep changes nothing; Use Gamepad Mode UI
-- applies at Finish and lives in the profile. EldoUI never switches the
-- game's gamepad interface: that stays in the game's Controller settings.
---------------------------------------------------------------------------
local function GamepadOn()
	return type(E.db.gamepadUI) == "table" and E.db.gamepadUI.always == true
end

BASE[#BASE + 1] = {
	key = "controller", short = "Controller", title = "Controller",
	desc = "You have a controller. EldoUI can place its frames for controller play while the game's gamepad interface is on: centered above the game's gamepad bar and clear of its radial menu.",
	help = Key("Your normal layout and dragged frames stay saved and come back when the game's gamepad interface is off. EldoUI never turns the game's gamepad interface on or off: that switch is in the game's Controller settings. Change this later in /eui > Layouts > Gamepad Mode UI."),
	Available = function() return E:GamepadDeviceKnown() or E:GamepadUIActive() end,
	Build = function(frame)
		frame.cards = {}
		local list = {
			{ key = false, title = L["Keep"], desc = L["Nothing changes here. You can turn Gamepad Mode UI on later in /eui > Layouts."] },
			{ key = "use", title = L["Use Gamepad Mode UI"], desc = L["Your frames move for controller play whenever the game's gamepad interface is on."] },
		}
		local gap = 12
		local width = math.floor((CONTENT_W - gap) / 2)
		for index, info in ipairs(list) do
			local card = Choice(frame, width, 84, info.title, info.desc, function()
				Touch("controller")
				-- Keep drops a Gamepad Mode UI change still waiting for combat to end.
				if info.key ~= "use" then E:CancelOutOfCombat("installer-controller") end
				session.controller.choice = info.key or nil
				if session.controller.state == "applied" then session.controller.state = "none" end
				Installer.Update()
			end)
			card.key = info.key
			card:SetPoint("TOPLEFT", (index - 1) * (width + gap), 0)
			frame.cards[index] = card
		end
		frame.now = Secondary(Paragraph(frame, E.tokens.size.label, ""))
		frame.now:SetPoint("TOPLEFT", frame.cards[1], "BOTTOMLEFT", 0, -12)
		frame.now:SetWidth(CONTENT_W)
		frame.spells = Button(frame, { text = L["Show controller spells"], minWidth = 160,
			tip = L["Opens the Controller view of the Key sets window: where your role's spells go on the game's controller bars. Nothing is placed until you choose Apply there."],
			onClick = function() E:OpenKeysAndSpells(nil, { view = "controller" }) end })
		frame.spells:SetPoint("TOPLEFT", frame.now, "BOTTOMLEFT", 0, -12)
	end,
	Refresh = function(frame)
		local c = session.controller
		for _, card in ipairs(frame.cards) do card:SetSelected(card.key == (c.choice or false)) end
		local text
		if E:GamepadModeActive() then
			text = L["In use now: Gamepad Mode UI is on."]
		elseif GamepadOn() then
			text = L["In use now: Gamepad Mode UI starts when you turn on the game's gamepad interface."]
		else
			text = L["In use now: your normal layout, also with a controller."]
		end
		local _, title = E:ControllerAddon()
		if title then
			text = text .. " " .. L["%s binds your controller's buttons, so EldoUI only places its frames."]:format(title)
		end
		frame.now:SetText(text)
	end,
	Apply = function()
		local c = session.controller
		if c.choice == "use" and not GamepadOn() then
			E:RunOutOfCombat(function() E:SetGamepadModeAlways(true) end, "installer-controller")
		end
		c.state = "applied"
	end,
	HasChoice = function() return session.controller.choice == "use" and not GamepadOn() end,
	Summary = function()
		if session.controller.choice == "use" then return L["Controller: %s"]:format(L["Use Gamepad Mode UI"]) end
		return L["Controller: keep"]
	end,
}

local function StepState(step)
	return session[step.key] and session[step.key].state
end

-- What a step will do, for the review page and the footer.
local function StepWord(step)
	local state = StepState(step)
	if step.key == "profile" then
		return session.profile.done and Good(L["Applied"]) or Warn(L["Applies at Finish"])
	end
	if step.manual or step.explicit then
		if state == "applied" then return Good(L["Applied"]) end
		if step.manual and not step.Apply then return Dim(L["Information"]) end
		if state == "skipped" then return Dim(L["Skipped"]) end
		return Dim(L["Only with Apply on its page"])
	end
	return StateWord(state, step.HasChoice())
end

-- The last page's list of what changed.
local DonePage = {}

-- The last page after Finish: one row per group of changes, each with
-- "Revert this" (or where to change it instead), the reload and the undo
-- of the whole setup.
DonePage.DONE_ROW = 28

-- Long texts on the review and done lists wrap, and each row is as tall
-- as its text (DESIGN.md 6: text never clips).
local LIST_W = CONTENT_W - 22  -- the scroll child's width (ScrollArea)
DonePage.DONE_STATE_W = 110
DonePage.DONE_BUTTON_W = 130

-- Placement check after Finish: frames of the combat screen this run
-- moved or resized (a style's size, a frame dragged in move mode) that
-- now cover another frame of the combat screen by more than a few units.
-- Frames that show one at a time (party and raid frames, the vehicle bar
-- and the bars it replaces) are left out. Returns a list of
-- { name, other, title, otherTitle, dragged }.
function Installer.PlacementCheck(applied)
	local combat = { ["Unit frames"] = true, ["Action bars"] = true, ["Group frames"] = true, Combat = true }
	local changed = {}
	for name in pairs(E.db.movers or {}) do changed[name] = "dragged" end
	for moduleName, styleKey in pairs(applied or {}) do
		local fp = E.StyleFootprint and E:StyleFootprint(moduleName, styleKey)
		if fp then
			for name in pairs(fp.movers) do changed[name] = changed[name] or "style" end
			for index in pairs(fp.bars) do
				local name = "EldoUI_ActionBar" .. index
				changed[name] = changed[name] or "style"
			end
		end
	end
	local function Rect(mover)
		local l, b, w, h = mover:GetRect()
		if not (l and w and w > 0 and h > 0) then return nil end
		return l, b, l + w, b + h
	end
	-- Frames of one module that show one at a time: party and raid frames,
	-- the vehicle, possess and gamepad bars in place of the others.
	local function OneAtATime(a, b)
		if not a.module or a.module ~= b.module then return false end
		if a.module == "GroupFrames" then return true end
		if a.module == "ActionBars" then
			return not (a.name:find("^EldoUI_ActionBar%d") and b.name:find("^EldoUI_ActionBar%d"))
		end
		return false
	end
	local found, seen = {}, {}
	for name, why in pairs(changed) do
		local mover = E.movers[name]
		if mover and E:IsMoverActive(mover) and combat[E:GetMoverGroup(name) or ""] and E:IsCombatMover(mover) then
			local l, b, r, t = Rect(mover)
			for otherName, other in pairs(E.movers) do
				local key = name < otherName and (name .. "|" .. otherName) or (otherName .. "|" .. name)
				if otherName ~= name and not seen[key] and not OneAtATime(mover, other)
					and E:IsMoverActive(other) and combat[E:GetMoverGroup(otherName) or ""] and E:IsCombatMover(other) and l then
					local ol, ob, orr, ot = Rect(other)
					if ol and math.min(r, orr) - math.max(l, ol) > 4 and math.min(t, ot) - math.max(b, ob) > 4 then
						seen[key] = true
						found[#found + 1] = { name = name, other = otherName, dragged = why == "dragged",
							title = L[mover.title or name] or name, otherTitle = L[other.title or otherName] or otherName }
					end
				end
			end
		end
	end
	table.sort(found, function(a, b) return a.name .. a.other < b.name .. b.other end)
	return found
end

function DonePage.BuildDone(frame)
	local done = CreateFrame("Frame", nil, frame)
	done:SetAllPoints()
	local _, child = ScrollArea(done)
	done.child = child
	done.rows = {}
	done.empty = Secondary(LiveText(Paragraph(child, E.tokens.size.body), function()
		return L["Nothing was changed. Run the setup again any time with %s."]:format(HL("/eui install"))
	end))
	done.empty:SetPoint("TOPLEFT", 0, 0)
	done.empty:SetPoint("TOPRIGHT", child, "TOPRIGHT", 0, 0)
	-- The reload comes from the player's own click (secure /reload button).
	done.reload = E:CreateReloadButton(child, L["Reload now"], 160, E.tokens.height.button, function() CloseDone(true) end)
	done.reload.primary = true
	done.undoAll = Button(child, L["Undo the whole setup"], 200, function() E:UndoInstall() end)
	done.undoAll:SetPoint("LEFT", done.reload, "RIGHT", 8, 0)
	Tooltip(done.undoAll, L["Undo the whole setup"], L["Puts the whole profile back as it was before this setup, after one more question. Chat tabs and other addons' profiles stay as they are."])
	done.note = Secondary(LiveText(Paragraph(child, E.tokens.size.label), function()
		return L["Some changes (profile, Blizzard frames, modules) take full effect after a reload. Everything can be changed later in %s, and %s runs this setup again."]:format(HL("/eui"), HL("/eui install"))
	end))
	done.note:SetPoint("TOPLEFT", done.reload, "BOTTOMLEFT", 0, -12)
	done.note:SetWidth(LIST_W)
	-- The placement check: one line per overlap, with its fixes.
	done.place = E.UIKit.SectionCard(child)
	done.place:SetWidth(LIST_W)
	done.place.text = Paragraph(done.place, E.tokens.size.label)
	done.place.text:SetPoint("TOPLEFT", 10, -8)
	done.place.text:SetWidth(LIST_W - 20)
	done.place.reset = Button(done.place, { text = L["Use the layout's spot"], minWidth = 150, onClick = function()
		for _, overlap in ipairs(done.overlaps or {}) do
			if overlap.dragged then E:ResetMover(overlap.name) end
		end
		C_Timer.After(0.1, Installer.Update)
	end })
	done.place.reset:SetPoint("BOTTOMLEFT", 10, 8)
	Tooltip(done.place.reset, L["Use the layout's spot"], L["Puts every frame you dragged that now covers another back on the spot the layout gives it."])
	done.place.move = Button(done.place, { text = L["Open move mode"], minWidth = 130, onClick = function()
		CloseDone()
		E:ToggleMoveMode(true)
	end })
	done.place.move:SetPoint("LEFT", done.place.reset, "RIGHT", 8, 0)
	Tooltip(done.place.move, L["Open move mode"], L["Closes the setup and opens move mode, so you can drag the frames apart."])
	frame.done = done
end

function DonePage.DoneRow(done, index)
	local row = done.rows[index]
	if row then return row end
	local child = done.child
	row = {}
	-- Name and state on the left, Revert this (or where to change it) on the right.
	local nameW = LIST_W - DonePage.DONE_STATE_W - DonePage.DONE_BUTTON_W - 20
	row.name = Paragraph(child, E.tokens.size.body)
	row.name:SetWidth(nameW)
	row.state = E:CreateText(child, E.tokens.size.label, "LEFT")
	row.state:SetPoint("TOPLEFT", row.name, "TOPRIGHT", 10, 0)
	row.state:SetWidth(DonePage.DONE_STATE_W)
	row.revert = Button(child, L["Revert this"], DonePage.DONE_BUTTON_W, function()
		if row.key then RevertGroup(row.key) end
	end)
	-- The note reads under the name, so a long one wraps instead of clipping.
	row.note = Secondary(Paragraph(child, E.tokens.size.label))
	row.note:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -2)
	row.note:SetWidth(LIST_W - DonePage.DONE_BUTTON_W - 10)
	done.rows[index] = row
	return row
end

-- The groups the last page lists: only what really changed.
local function DoneList()
	local list = {}
	for _, group in ipairs(session.undo.list) do
		if GroupChanged(group) then list[#list + 1] = group end
	end
	return list
end
Installer.DoneList = function() return session and DoneList() or {} end

function DonePage.RefreshDone(frame)
	local done = frame.done
	local list = DoneList()
	local y = 4
	for index, group in ipairs(list) do
		local row = DonePage.DoneRow(done, index)
		row.key = group.key
		row.name:ClearAllPoints()
		row.name:SetPoint("TOPLEFT", 0, -y)
		row.revert:ClearAllPoints()
		row.revert:SetPoint("TOPRIGHT", done.child, "TOPRIGHT", 0, -y + 4)
		-- Each summary names its part ("UI scale: auto"), as on the review page.
		row.name:SetText(ChangeText(group))
		local note = ChangeNote(group)
		local stepState = session[group.key] and session[group.key].state
		if group.reverted then
			row.state:SetText(Dim(L["Reverted"]))
		elseif stepState == "skipped" then
			-- Nothing was imported in the end (Other addons).
			row.state:SetText(Dim(L["Skipped"]))
		elseif group.failed then
			row.state:SetText(Warn(L["Hit an error"]))
		else
			row.state:SetText(Good(L["Applied"]))
		end
		row.revert:SetShown(note == nil and not group.reverted)
		Tooltip(row.revert, L["Revert this"], L["Puts %s back as it was before this setup."]:format(L[group.title]))
		row.note:SetText(note or "")
		row.note:SetShown(note ~= nil)
		row.name:Show()
		row.state:Show()
		local height = math.ceil(row.name:GetStringHeight())
		if note then height = height + 2 + math.ceil(row.note:GetStringHeight()) end
		y = y + math.max(DonePage.DONE_ROW, height + 10)
	end
	for index = #list + 1, #done.rows do
		local row = done.rows[index]
		row.name:Hide()
		row.state:Hide()
		row.revert:Hide()
		row.note:Hide()
	end
	done.empty:SetShown(#list == 0)
	if #list == 0 then y = DonePage.DONE_ROW + 4 end
	-- Overlaps of frames this run moved or resized (out of combat only:
	-- frames may still wait to move).
	local overlaps = (not InCombatLockdown()) and Installer.PlacementCheck(session.styles and session.styles.applied) or {}
	done.overlaps = overlaps
	done.place:SetShown(#overlaps > 0)
	if #overlaps > 0 then
		local lines, dragged = { Warn(L["Some frames cover each other now:"]) }, false
		for index, overlap in ipairs(overlaps) do
			if index > 4 then
				lines[#lines + 1] = L["and %d more"]:format(#overlaps - 4)
				break
			end
			lines[#lines + 1] = L["%s covers %s"]:format(HL(overlap.title), HL(overlap.otherTitle))
			dragged = dragged or overlap.dragged
		end
		done.place.text:SetText(table.concat(lines, "\n"))
		done.place.reset:SetShown(dragged)
		done.place.move:ClearAllPoints()
		if dragged then
			done.place.move:SetPoint("LEFT", done.place.reset, "RIGHT", 8, 0)
		else
			done.place.move:SetPoint("BOTTOMLEFT", 10, 8)
		end
		local height = 8 + math.ceil(done.place.text:GetStringHeight()) + 10 + E.tokens.height.button + 8
		done.place:SetHeight(height)
		done.place:ClearAllPoints()
		done.place:SetPoint("TOPLEFT", 0, -y - 12)
		y = y + 12 + height
	end
	done.reload:ClearAllPoints()
	done.reload:SetPoint("TOPLEFT", 0, -y - 12)
	local backup = Installer.GetBackup()
	done.undoAll:SetShown(backup ~= nil)
	if backup and backup.attach then
		Tooltip(done.undoAll, L["Undo the whole setup"], L["Puts this character back on the profile it used before, after one more question, with its chat tabs, game settings, click-casting and class spells as they were. The profile it was attached to stays as it is."])
	else
		Tooltip(done.undoAll, L["Undo the whole setup"], L["Puts the whole profile back as it was before this setup, after one more question. Chat tabs and other addons' profiles stay as they are."])
	end
	done.child:SetHeight(y + 12 + E.tokens.height.button + 12 + math.ceil(done.note:GetStringHeight()) + 8)
end

-- A step's summary on its review card, without the step's name in front
-- ("Game settings: Lock action bars" reads "Lock action bars"): the
-- card's title names the step already.
function Installer.ReviewValue(step)
	local ok, text = pcall(step.Summary)
	text = ok and tostring(text or "") or ""
	local label, rest = text:match("^([^:|]+): (.+)$")
	if label and #label <= 32 then return (rest:gsub("^%l", string.upper)) end
	return text
end

FINISH = {
	key = "finish", short = "Finish", title = "All set",
	desc = "Finish applies the steps marked \"Applies at Finish\", and Change goes back to a step or Revert undoes one. Afterwards this page lists every change, each with Revert this.",
	Build = function(frame)
		frame.review = CreateFrame("Frame", nil, frame)
		frame.review:SetAllPoints()
		local _, child = ScrollArea(frame.review)
		frame.list = child
		frame.lines = {}
		frame.note = Secondary(LiveText(Paragraph(child, E.tokens.size.label), function()
			return L["Everything can be changed later in %s. Run this setup again any time with %s, or one step with %s (for example %s)."]:format(HL("/eui"), HL("/eui install"), HL("/eui install <step>"), HL("/eui install role"))
		end))
		DonePage.BuildDone(frame)
	end,
	Refresh = function(frame)
		local finished = session.finished
		frame.review:SetShown(not finished)
		frame.done:SetShown(finished and true or false)
		if finished then
			DonePage.RefreshDone(frame)
			return
		end
		local list = frame.list
		-- Two columns of cards, one per step: its name, what it does (the
		-- summary without the step's name in front), its state, Change and,
		-- for a step applied in this run, Revert.
		local gap = 12
		local colW = math.floor((LIST_W - gap) / 2)
		local buttonH = E.tokens.height.button
		local y, rowHeight = 0, 0
		for index = 1, #steps - 1 do
			local step = steps[index]
			local line = frame.lines[index]
			if not line then
				line = {}
				line.box = E.UIKit.SectionCard(list)
				line.title = E:CreateText(line.box, E.tokens.size.body, "LEFT")
				line.title:SetPoint("TOPLEFT", 10, -8)
				line.state = E:CreateText(line.box, E.tokens.size.label, "RIGHT")
				line.state:SetWordWrap(true)
				line.state:SetJustifyV("TOP")
				line.state:SetPoint("TOPRIGHT", -10, -8)
				line.name = Secondary(Paragraph(line.box, E.tokens.size.label))
				line.name:SetPoint("TOPLEFT", line.title, "BOTTOMLEFT", 0, -4)
				line.change = Button(line.box, { text = L["Change"], minWidth = 80, onClick = function() Installer.Go(line.index) end })
				line.change:SetPoint("BOTTOMLEFT", 10, 8)
				line.revert = Button(line.box, { text = L["Revert"], minWidth = 80, onClick = function()
					if line.group then RevertGroup(line.group) end
				end })
				line.revert:SetPoint("LEFT", line.change, "RIGHT", 8, 0)
				frame.lines[index] = line
			end
			line.index = index
			line.box:SetWidth(colW)
			line.title:SetText(L[step.short or step.key])
			line.state:SetWidth(0)
			line.state:SetText(StepWord(step))
			local stateW = math.min(math.ceil(line.state:GetStringWidth()) + 2, math.floor(colW / 2))
			line.state:SetWidth(stateW)
			line.title:SetWidth(colW - 20 - stateW - 8)
			line.name:SetWidth(colW - 20)
			line.name:SetText(Installer.ReviewValue(step))
			Tooltip(line.change, L["Change"], L["Goes back to %s."]:format(HL(L[step.short or step.key])))
			-- Revert: a step applied in this run whose change can be put back.
			local groupKey = STEP_GROUP[step.key] or step.key
			local group = session.undo.groups[groupKey]
			local revertable = StepState(step) == "applied" and group and not group.reverted
				and GroupChanged(group) and ChangeNote(group) == nil
			line.group = revertable and groupKey or nil
			line.revert:SetShown(revertable and true or false)
			if revertable then
				Tooltip(line.revert, L["Revert"], L["Puts %s back as it was before this setup."]:format(L[group.title]))
			end
			-- The summary starts under the taller of the title and the state.
			local headH = math.max(math.ceil(line.title:GetStringHeight()), math.ceil(line.state:GetStringHeight()))
			line.name:ClearAllPoints()
			line.name:SetPoint("TOPLEFT", 10, -(8 + headH + 4))
			local textH = headH + 4 + math.ceil(line.name:GetStringHeight())
			line.height = 8 + textH + 10 + buttonH + 8
			line.box:Show()
			-- Place it: odd steps on the left, even ones on the right; a
			-- row is as tall as its taller card.
			local column = (index - 1) % 2
			if column == 0 then
				y = y + rowHeight + (index > 1 and gap or 0)
				rowHeight = 0
			end
			line.box:ClearAllPoints()
			line.box:SetPoint("TOPLEFT", column * (colW + gap), -y)
			rowHeight = math.max(rowHeight, line.height)
			if column == 1 or index == #steps - 1 then
				local left = frame.lines[index - column]
				left.box:SetHeight(rowHeight)
				if column == 1 then line.box:SetHeight(rowHeight) end
			end
		end
		y = y + rowHeight
		for index = #steps, #frame.lines do frame.lines[index].box:Hide() end
		frame.note:ClearAllPoints()
		frame.note:SetPoint("TOPLEFT", 0, -y - 12)
		frame.note:SetWidth(LIST_W)
		list:SetHeight(y + 12 + math.ceil(frame.note:GetStringHeight()) + 8)
	end,
	HasChoice = function() return false end,
	Summary = function() return L["Finish"] end,
}

-- Each of the installer's own steps carries what it owns.
for _, step in ipairs(BASE) do step.owns = STEP_OWNS[step.key] end

-- This run's steps: the installer's own, the setup pages, then Finish.
-- `focus` (optional): a short setup with only these step keys, after the
-- Welcome step (New in this version). Setup pages come only in a full run.
local function BuildSteps(focus)
	wipe(steps)
	-- The alt setup: one page, then the last page (Core/InstallerAlt.lua).
	if focus == "alt" and E.InstallerAlt and E.InstallerAlt.STEP then
		steps[1] = E.InstallerAlt.STEP
		steps[2] = FINISH
		return
	end
	local only
	if type(focus) == "table" and #focus > 0 then
		only = { profile = true }
		for _, key in ipairs(focus) do only[key] = true end
	end
	for _, step in ipairs(BASE) do
		-- A step with nothing to offer this time (no addon found) is left out.
		local available = true
		if step.Available then
			local ok, result = pcall(step.Available)
			available = ok and result and true or false
		end
		if available and (not only or only[step.key]) then steps[#steps + 1] = step end
	end
	if E.GetPluginInstallerPages and not only then
		for _, page in ipairs(E:GetPluginInstallerPages()) do steps[#steps + 1] = PageStep(page) end
	end
	steps[#steps + 1] = FINISH
end
BuildSteps()

-- An installer step by key (also one this run leaves out), or nil.
function Installer.BaseStep(key)
	for _, step in ipairs(BASE) do
		if step.key == key then return step end
	end
end

-- The alt page is open and not attached yet.
function Entry.OnAltPage()
	return session ~= nil and not session.finished and session.focus == "alt"
end

-- Another kind of run on the open window: "alt" (the alt page) or nil
-- (the full setup from its Welcome step). The picks made so far stay;
-- previews are taken back first.
function Installer.SwitchRun(focus)
	if not session or session.finished then return end
	for index = #steps, 1, -1 do
		local step = steps[index]
		if step.Revert and session[step.key] and session[step.key].state == "preview" then step.Revert() end
	end
	for _, step in ipairs(steps) do
		if step.frame then step.frame:Hide() end
	end
	BuildSteps(focus)
	session.focus = focus
	for _, step in ipairs(steps) do session[step.key] = session[step.key] or { state = "none" } end
	current, session.reached = 1, 1
	if focus == "alt" and E.InstallerAlt then E.InstallerAlt.Start(session) end
	KeepRun(session)
	Installer.Update()
end

-- A step of the full setup was asked for on the alt page: the full setup.
function Entry.LeaveAlt()
	if Entry.OnAltPage() then Installer.SwitchRun(nil) end
end

---------------------------------------------------------------------------
-- Window: the E.WindowKit shell, steps in the sidebar
---------------------------------------------------------------------------
local NAV_ROW = 24

local function NavButton(index)
	-- The options window's sidebar row (E.WindowKit.NavRow).
	local button = Kit.NavRow(window.sidebar, SIDEBAR - 16, NAV_ROW)
	button.mark = button:CreateTexture(nil, "ARTWORK")
	button.mark:SetSize(8, 8)
	button.mark:SetPoint("CENTER", button, "LEFT", 12, 0)
	button.label = E:CreateText(button, E.tokens.size.body, "LEFT")
	button.label:SetPoint("LEFT", 24, 0)
	button.label:SetPoint("RIGHT", -4, 0)
	button.label:SetWordWrap(false)
	button:SetScript("OnClick", function(self) Installer.Go(self.index) end)
	-- The kit's tooltip (E.UIKit.Tooltip): the step's title and heading,
	-- its state in words as the footer and the Finish page say it, and why
	-- a step further on can't be clicked yet.
	E.UIKit.Tooltip(button, nil, function(tooltip)
		local step = steps[button.index]
		if not step then return end
		local Tip = E.UIKit
		Tip.TipTitle(tooltip, E:Translate(step.title))
		Tip.TipText(tooltip, E:Translate(step.desc))
		if session and step.key ~= "finish" then Tip.TipText(tooltip, StepWord(step)) end
		if not button:IsEnabled() then Tip.TipText(tooltip, L["Reach this step with Next first."]) end
	end)
	button:SetMotionScriptsWhileDisabled(true)
	button.index = index
	return button
end

local function UpdateNav()
	local nav = window.nav
	for index, step in ipairs(steps) do
		local button = nav[index]
		if not button then
			button = NavButton(index)
			nav[index] = button
		end
		button:ClearAllPoints()
		button:SetPoint("TOPLEFT", 8, -64 - (index - 1) * NAV_ROW)
		button.label:SetText(L[step.short])
		local state = StepState(step)
		if step.key == "profile" and session.profile.done then state = "applied" end
		-- Visited steps can be clicked; the rest wait for Next.
		button:SetEnabled(index <= session.reached)
		Kit.SoftNavRow(button, index == current)
		-- The state as a shape too, not only a color: a check for applied,
		-- a cross for skipped, a dot for everything else.
		local glyph = state == "applied" and "check" or state == "skipped" and "cross" or "dot"
		if button.glyph ~= glyph then
			button.glyph = glyph
			E.UIKit.SetGlyph(button.mark, glyph)
			button.mark:SetSize(glyph == "dot" and 8 or 10, glyph == "dot" and 8 or 10)
		end
		if index == current then
			button.mark:SetVertexColor(unpack(E.media.accentColor))
			button.label:SetTextColor(1, 1, 1)
		else
			if state == "applied" then
				button.mark:SetVertexColor(unpack(E.tokens.text.good))
			else
				button.mark:SetVertexColor(unpack(E.tokens.text.dim))
			end
			if index <= session.reached then
				button.label:SetTextColor(unpack(E.media.text.body))
			else
				button.label:SetTextColor(unpack(E.media.text.dim))
			end
		end
		button:Show()
	end
	for index = #steps + 1, #nav do nav[index]:Hide() end
end

local function Cancel()
	if not session then return end
	-- After Finish, closing the window is "done", not "do later".
	if session.finished then
		CloseDone()
		return
	end
	-- Undo every preview that wasn't applied; keep the picks for this session.
	for index = #steps, 1, -1 do
		local step = steps[index]
		if step.Revert and StepState(step) == "preview" then step.Revert() end
	end
	session.step = current
	-- Paused by the player: the next login reminds instead of opening.
	session.paused = true
	session = nil
	Entry.Paused()
end

local function ShowHelp()
	local step = steps[current]
	if step and step.help then
		-- A function builds its text now, so highlights use the current accent.
		local help = type(step.help) == "function" and step.help() or L[step.help]
		Confirm(help, { { E:GameText(OKAY, L["OK"]) } }, E:Translate(step.title))
	end
end

-- "Step done": a small panel over the footer for a moment after a step's
-- Apply worked, or a warning when it hit an error (warn: the warn-colored
-- bar, shown twice as long). The shared in-window notice, E.UIKit.Toast.
local function ShowToast(text, warn)
	if not window then return end
	E.UIKit.Toast(window, text, { anchor = window.footer, warn = warn, maxWidth = CONTENT_W })
end
Installer.ShowToast = ShowToast

local HEADER = 64 -- the kit window's header height at normal text size

-- The last page's title and subtitle.
local function DoneTitle()
	return L["EldoUI is set up"], L["Here is what the setup changed. Revert this puts one part back as it was before."]
end

-- The header grows with its title and the whole subtitle, the way the
-- kit's dialogs do (Large text makes both taller), and the window grows
-- with it, so the page keeps its room. It is as tall as the tallest
-- header of all pages, so the window keeps one size from step to step.
local function FitHeader()
	if not window then return end
	local title, subtitle = window.title, window.subtitle
	local shownTitle, shownText = title:GetText() or "", subtitle:GetText() or ""
	local function Need(text)
		local titleHeight = math.ceil(title:GetStringHeight() or 0)
		local subtitleHeight = text ~= "" and math.ceil(subtitle:GetStringHeight() or 0) or 0
		return 8 + titleHeight + (subtitleHeight > 0 and 6 + subtitleHeight or 0) + 4
	end
	local need = Need(shownText)
	local pages = { { DoneTitle() } }
	for _, step in ipairs(steps) do pages[#pages + 1] = { E:Translate(step.title) or "", E:Translate(step.desc) or "" } end
	for _, page in ipairs(pages) do
		title:SetText(page[1])
		subtitle:SetText(page[2])
		need = math.max(need, Need(page[2]))
	end
	title:SetText(shownTitle)
	subtitle:SetText(shownText)
	-- The subtitle sits under the title and wraps at the width the kit
	-- gives it from the header. One top point only: a second one on the
	-- header, rounded apart from the title's real height, would disagree
	-- with the first and leave the box without a place.
	subtitle:ClearAllPoints()
	subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
	local height = math.max(HEADER, need)
	if math.abs((window.header:GetHeight() or 0) - height) > 0.5 then
		window.header:SetHeight(height)
		window:SetHeight(HEIGHT + height - HEADER)
	end
end

function Installer.KeyWindowFocused()
	return window and window:IsVisible() and window.keyNavigation.active and E.UIKit.TopWindow() == window
		and not E.UIKit.KeyboardMenuActive()
end

function Installer.KeyTargets()
	local targets = {}
	local step = steps[current]
	local function Read(owner)
		for _, control in ipairs(owner.kitKeyOrder) do
			if E.UIKit.KeyControlUsable(control) then
				targets[#targets + 1] = {
					control = control, order = #targets + 1,
					y = math.floor((E.PlainCall(control.GetTop, control) or 0) + 0.5),
					x = E.PlainCall(control.GetLeft, control) or 0,
				}
			end
		end
	end
	Read(window)
	if step and step.frame then Read(step.frame) end
	table.sort(targets, function(a, b)
		if a.y ~= b.y then return a.y > b.y end
		if a.x ~= b.x then return a.x < b.x end
		return a.order < b.order
	end)
	for index, entry in ipairs(targets) do targets[index] = entry.control end
	return targets
end

function Installer.HandleKey(name)
	if InCombatLockdown() or not Installer.KeyWindowFocused() then return false end
	local nav = window.keyNavigation
	if nav:Handle(name) then return true end
	if name == "ENTER" and not nav.control then
		return E.UIKit.RunKeyAction(window.next, window.next:GetScript("OnClick"), "LeftButton", false)
	end
	return false
end

local function CreateWindow()
	window = Kit.CreateWindow("EldoUIInstaller", {
		width = WIDTH, height = HEIGHT, sidebar = SIDEBAR, logo = true, keys = Installer.HandleKey,
	})
	window.nav = {}
	window.kitKeyControls, window.kitKeyOrder = {}, {}
	window.keyNavigation = E.UIKit.FocusNavigation(window, E.UIKit.FocusRing(window), Installer.KeyTargets, function(control)
		local owner = control:GetParent()
		while owner and owner ~= window do
			if owner:GetObjectType() == "ScrollFrame" then E.UIKit.RevealKeyControl(owner, control); return end
			owner = owner:GetParent()
		end
	end)
	window.kitKeyEdit = function(control) window.keyNavigation:BindEdit(control, Installer.KeyWindowFocused) end
	window:HookScript("OnShow", function() window.keyNavigation.active = true end)
	window:HookScript("OnHide", function() window.keyNavigation.active = false end)
	-- The whole subtitle shows: the header grows instead (FitHeader).
	window.subtitle:SetMaxLines(0)
	E:RegisterThemed(window.header, FitHeader)

	window.counter = Secondary(E:CreateText(window.headerRight, E.tokens.size.small, "RIGHT"))
	window.counter:SetPoint("RIGHT", 0, 0)
	window.help = Button(window.headerRight, "?", 26, ShowHelp)
	window.help:SetPoint("RIGHT", window.counter, "LEFT", -10, 0)
	Tooltip(window.help, L["Help"], L["A short explanation of this step."])

	local footer = window.footer
	window.back = Button(footer, L["Back"], 110, function() Installer.Back() end, true)
	window.back:SetPoint("BOTTOMLEFT", 0, 6)
	-- One primary button per step: "Apply and continue" on a step with a
	-- pick, Next, Finish or Close otherwise (Installer.Primary). Back is
	-- secondary and Skip a plain text link beside the primary button.
	window.next = Button(footer, { text = L["Next"], kind = "primary", minWidth = 130, large = true, onClick = function() Installer.Primary() end })
	window.next:SetPoint("BOTTOMRIGHT", 0, 6)
	local skip = CreateFrame("Button", nil, footer)
	skip:SetHeight(E.tokens.height.buttonLarge)
	skip.text = Secondary(E:CreateText(skip, E.tokens.size.label, "CENTER"))
	skip.text:SetPoint("CENTER")
	skip.text:SetText(L["Skip this step"])
	skip:SetWidth(math.ceil(skip.text:GetStringWidth() + 16))
	skip:SetPoint("RIGHT", window.next, "LEFT", -12, 0)
	skip:SetScript("OnEnter", function(self) self.text:SetTextColor(Accent()) end)
	skip:HookScript("OnLeave", function(self) self.text:SetTextColor(unpack(Kit.SECONDARY)) end)
	skip:SetScript("OnClick", function()
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		Installer.Skip()
	end)
	E:RegisterThemed(skip, function(self) self:SetWidth(math.ceil(self.text:GetStringWidth() + 16)) end)
	window.skip = E.UIKit.CollectKeyControl(skip, true)
	Tooltip(window.skip, L["Skip this step"], L["Leave this part of the UI as it is and go on."])
	-- How far along the setup is: an accent line over the footer.
	-- Two screen pixels tall at the window's own scale (E:Hairline).
	window.progressTrack = footer:CreateTexture(nil, "ARTWORK")
	window.progressTrack:SetPoint("TOPLEFT")
	window.progressTrack:SetPoint("TOPRIGHT")
	E:Hairline(window.progressTrack, "h", 2)
	window.progressTrack:SetColorTexture(unpack(E.tokens.track))
	window.progress = footer:CreateTexture(nil, "OVERLAY")
	window.progress:SetPoint("TOPLEFT", window.progressTrack, "TOPLEFT")
	E:Hairline(window.progress, "h", 2)
	window.progressDriver = CreateFrame("Frame", nil, footer)
	window.status = Secondary(E:CreateText(footer, E.tokens.size.label, "LEFT"))
	window.status:SetPoint("LEFT", window.back, "RIGHT", 12, 0)
	window.status:SetPoint("RIGHT", window.skip, "LEFT", -12, 0)
	Tooltip(window.close, L["Close: do it later"], L["Undoes the previews and pauses the setup. /eui install goes on where you stopped."])

	window:SetScript("OnHide", function()
		-- Alt+Z hides UIParent and with it this window: that isn't a cancel.
		if finishing or not UIParent:IsShown() then return end
		-- Closed by a cinematic, a movie or the question that skips one.
		-- The game's own cinematic window starts before EldoUI hears of
		-- the scene and closes every window first, so this is checked
		-- here: the run waits for the scene's end and comes back on the
		-- same step, never paused.
		if session and Entry.SceneBusy() then
			Entry.HeldByScene()
			return
		end
		-- Closed by the loading screen: open again on the same step after it.
		if loading.world and session then
			loading.reopen = true
			return
		end
		Cancel()
	end)
	-- The options window the setup put aside comes back once the setup is
	-- closed for good (not for a scene or a loading screen it returns from).
	window:HookScript("OnHide", function()
		if not window.configBack or not UIParent:IsShown() then return end
		if loading.reopen or (session and Entry.SceneBusy()) then return end
		window.configBack = nil
		C_Timer.After(0, function()
			if not window:IsShown() and E.ReopenConfigAfterMoveMode then E:ReopenConfigAfterMoveMode() end
		end)
	end)
	window:RegisterEvent("PLAYER_REGEN_DISABLED")
	window:RegisterEvent("PLAYER_REGEN_ENABLED")
	window:RegisterEvent("GLOBAL_MOUSE_DOWN")
	window:SetScript("OnEvent", function(_, event)
		local nav = window.keyNavigation
		if event == "GLOBAL_MOUSE_DOWN" then
			if window:IsVisible() and not E.UIKit.KeyboardMenuUnderMouse() then
				nav.active = window:IsMouseOver() and E.UIKit.TopWindow() == window
				if not (nav.active and nav.control and nav.control:IsMouseOver()) then nav:Clear() end
			end
			return
		end
		if event == "PLAYER_REGEN_DISABLED" then
			nav.active = false
			nav:Clear()
		end
		Installer.Update()
		-- Changes that waited for the end of combat run now: the list of
		-- what changed reads them a moment later.
		if event == "PLAYER_REGEN_ENABLED" then C_Timer.After(0.2, Installer.Update) end
	end)
end

-- The progress line glides to its new width: 0.25 s,
-- easing out, with Animations on (General page); at once with them off.
local PROGRESS_TIME = 0.25

function Installer.SetProgress(target)
	local bar, driver = window.progress, window.progressDriver
	local from = bar:GetWidth() or 0
	if not E.db.general.animations or from <= 0 or math.abs(from - target) < 0.5 or not window:IsVisible() then
		driver:SetScript("OnUpdate", nil)
		bar:SetWidth(target)
		return
	end
	driver.from, driver.to, driver.elapsed = from, target, 0
	driver:SetScript("OnUpdate", function(self, elapsed)
		self.elapsed = self.elapsed + elapsed
		local t = math.min(self.elapsed / PROGRESS_TIME, 1)
		local eased = 1 - (1 - t) * (1 - t)
		bar:SetWidth(self.from + (self.to - self.from) * eased)
		if t >= 1 then self:SetScript("OnUpdate", nil) end
	end)
end

function Installer.Update()
	if not window or not window:IsShown() or not session then return end
	local step = steps[current]
	session.step = current
	window.counter:SetText(L["Step %d of %d"]:format(current, #steps))
	local width = window.footer:GetWidth()
	if width and width > 0 then
		Installer.SetProgress(math.max(E:PixelFor(window.footer), width * current / #steps))
		window.progress:SetColorTexture(Accent())
	end
	local finished = session.finished
	if finished then
		window:SetTitle(DoneTitle())
		Tooltip(window.close, L["Close"], L["The setup is done. Closes this page and asks for a reload only if a change needs one."])
	else
		window:SetTitle(E:Translate(step.title), E:Translate(step.desc))
		Tooltip(window.close, L["Close: do it later"], L["Undoes the previews and pauses the setup. /eui install goes on where you stopped."])
	end
	FitHeader()
	window.help:SetShown(step.help ~= nil and not finished)
	for index, other in ipairs(steps) do
		if other.frame then other.frame:SetShown(index == current) end
	end
	if not step.frame then
		step.frame = CreateFrame("Frame", nil, window.content)
		step.frame:SetAllPoints()
		step.frame.kitKeyControls, step.frame.kitKeyOrder = {}, {}
		step.frame.kitKeyEdit = window.kitKeyEdit
		step.Build(step.frame)
	end
	step.frame:Show()
	step.Refresh(step.frame)
	UpdateNav()
	-- After Finish the steps are done: the last page is all that is left.
	if finished then
		for _, button in ipairs(window.nav) do button:SetEnabled(false) end
	end

	window.back:SetEnabled(current > 1 and not finished)
	window.skip:SetShown(current < #steps and not finished and step.key ~= "alt")
	local action = Installer.PrimaryAction()
	window.next:SetText(PRIMARY_LABELS[action] and L[PRIMARY_LABELS[action]] or L["Next"])
	E.UIKit.FitButton(window.next, 130)
	Tooltip(window.next, L[PRIMARY_LABELS[action] or "Next"], L[PRIMARY_TIPS[action] or PRIMARY_TIPS.next])
	-- The Welcome page's own main action is the pack's Apply.
	E.UIKit.SetButtonKind(window.next, step.key == "profile" and not finished and "secondary" or "primary")
	-- Attach waits for a profile to be picked.
	window.next:SetEnabled(action ~= "attach" or (E.InstallerAlt and E.InstallerAlt.CanAttach()) and true or false)

	local status = ""
	if InCombatLockdown() then
		status = Warn(L["In combat: changes wait until combat ends."])
	elseif current > 1 and current < #steps then
		status = StepWord(step)
	end
	window.status:SetText(status)
	window.keyNavigation:Refresh()
end

-- Show step `index`. Going back undoes the previews of the steps left
-- behind; going forward keeps them as the pending choice.
function Installer.Go(index)
	if Entry.OnAltPage() and index ~= current then Entry.LeaveAlt() end
	if not session or session.finished or index < 1 or index > #steps or index == current then return end
	if index < current then
		for i = current, index + 1, -1 do
			local step = steps[i]
			if step.Revert and StepState(step) == "preview" then step.Revert() end
		end
		current = index
		Installer.Update()
		return
	end
	local function Show()
		current = index
		session.reached = math.max(session.reached, index)
		Installer.Update()
	end
	-- Leaving the welcome step forward answers the profile question.
	if steps[current].key == "profile" then
		EnsureProfile(Show)
		return
	end
	Show()
end

function Installer.Next()
	if current == #steps then
		Installer.Finish()
	else
		Installer.Go(current + 1)
	end
end

function Installer.Back()
	Installer.Go(current - 1)
end

function Installer.Skip()
	Entry.LeaveAlt()
	if not session or session.finished then return end
	local step = steps[current]
	local data = session[step.key]
	if step.key == "profile" then
		-- Skipping the welcome keeps the current profile (asked again before
		-- the first change on a profile that was set up before).
		PickProfileMode("current")
		current = 2
		session.reached = math.max(session.reached, 2)
		Installer.Update()
		return
	end
	if step.Revert and data and data.state == "preview" then step.Revert() end
	if data and data.state ~= "applied" then
		data.state = "skipped"
		-- Skipped means "leave it": drop the pending choice.
		if step.key == "scale" then data.choice = nil
		elseif step.key == "layout" then data.key = nil
		elseif step.key == "styles" then
			-- Styles applied earlier in this run stay as they are.
			wipe(data.choices)
			for name, key in pairs(data.applied or {}) do data.choices[name] = key end
		elseif step.key == "role" then
			data.choice, data.clickCast = nil, false
			data.classLayer = E.db.general.roleClass and true or false
			wipe(data.picks)
		elseif step.key == "modules" then data.states = ModuleStates()
		elseif step.key == "blizzard" then data.mode, data.windowsMode = data.appliedMode or "keep", nil
		elseif step.key == "chat" then data.mode = "keep"
		elseif step.key == "addons" then
			wipe(data.selected)
			data.place = {}
		elseif step.key == "access" then wipe(data.picks)
		elseif step.key == "cvars" then wipe(data.picks)
		elseif step.key == "convenience" then
			-- What was turned on earlier in this run stays on.
			local set = data.set or {}
			for _, row in ipairs(ConvenienceRows()) do data[row.id] = set[row.id] ~= nil end
		end
	end
	-- Express: skipping the keys finishes without them.
	if session.express and step.key == "keys" then
		Installer.Finish()
		return
	end
	Installer.Go(current + 1)
end

-- A step's Apply runs protected: when one part of the UI errors on this
-- client, the other steps still apply, Finish still completes and the
-- reload still comes. The failed step names are printed once.
local function SafeApply(step, failed)
	-- What the step changes is kept first, for "Revert this" on the last page.
	local kept = RememberStep(step)
	local ok, err = pcall(step.Apply, kept)
	-- A step that could not apply this time (it said why itself) is no
	-- error: it is not marked applied and the setup does not move on.
	if ok and err == false then return false, "blocked" end
	if ok then
		-- The character's own picks, for its alts (Core/InstallerAlt.lua).
		if E.InstallerAlt and session then
			local noted, why = pcall(E.InstallerAlt.NoteStep, step.key, session)
			if not noted then geterrorhandler()(why) end
		end
		return true
	end
	geterrorhandler()(err)
	local group = session and session.undo.groups[STEP_GROUP[step.key] or step.key]
	if group then group.failed = true end
	if session and session[step.key] and session[step.key].state ~= "applied" then
		session[step.key].state = "applied" -- not retried by Finish
	end
	if failed then table.insert(failed, { key = step.key, title = L[step.short or step.key] }) end
	return false
end
Installer.SafeApply = SafeApply

-- Steps whose choice is only a preview so far are kept when a later step
-- is applied, so Cancel can't undo part of what the player applied.
local function KeepEarlierPreviews(index, failed)
	for i = 1, index - 1 do
		local step = steps[i]
		if StepState(step) == "preview" and step.Apply then SafeApply(step, failed) end
	end
end

-- Steps that hit an error (the error itself is in the error log): a warn
-- toast while the window is open, else an alert that opens the first one
-- again. Returns true when something was reported.
local function ReportFailed(failed)
	if #failed == 0 then return false end
	local titles = {}
	for index, entry in ipairs(failed) do titles[index] = entry.title end
	local names = table.concat(titles, ", ")
	if window and window:IsShown() then
		ShowToast(L["%s hit an error and was skipped. The error log has the details."]:format(names), true)
		return true
	end
	local first = failed[1].key
	E:PushAlert({ key = "EldoUI_SetupFailed", title = L["EldoUI setup"], options = { page = "general" },
		text = L["Part of the setup hit an error and was skipped: %s. Everything else is set up."]:format(names),
		actions = {
			{ label = L["Open that step"], tip = L["Opens the setup on that step, so you can try it again."], func = function() E:ShowInstaller(first) end },
			{ label = L["Later"], tip = L["%s opens it any time."]:format(HL("/eui install")) },
		} })
	return true
end

-- `andThen`: runs after the step applied (Apply and continue goes on).
function Installer.ApplyCurrent(andThen)
	local step = steps[current]
	if not step.Apply or not step.HasChoice() or step.finishOnly then return end
	local index = current
	EnsureProfile(function()
		local failed = {}
		KeepEarlierPreviews(index, failed)
		local ok, why = SafeApply(step, failed)
		Installer.Update()
		if why == "blocked" then return end
		if not ReportFailed(failed) and ok then
			local name = L[step.short or step.key]
			ShowToast(InCombatLockdown() and L["%s: applies when combat ends"]:format(name) or L["%s applied"]:format(name))
		end
		if andThen and session and not session.finished and current == index then andThen() end
	end)
end

-- What the footer's primary button does on this page: "customize" (the
-- Welcome page of a first run: the steps with the picked pack filled in),
-- "apply" (a step with a pick not applied yet: apply it, then go on),
-- "next", "finish" (the last step) or "close" (after Finish).
function Installer.PrimaryAction()
	if not session then return "next" end
	if session.finished then return "close" end
	local step = steps[current]
	if step.key == "alt" then return "attach" end
	if step.key == "profile" then
		if not session.profile.done and not session.rerun and not ExpressKeepsProfile(session) then return "customize" end
		return session.profile.done and "next" or "start"
	end
	if current == #steps then return "finish" end
	if step.Apply and step.HasChoice() and StepState(step) ~= "applied" and not step.finishOnly then return "apply" end
	return "next"
end

function Installer.Primary()
	if not session then return end
	local action, index = Installer.PrimaryAction(), current
	if action == "customize" then
		Installer.Customize()
	elseif action == "attach" then
		if E.InstallerAlt then E.InstallerAlt.Attach() end
	elseif action == "apply" then
		-- Express: the Keys and spells Apply also finishes the setup.
		local finish = session.express and steps[index].key == "keys"
		Installer.ApplyCurrent(function()
			if finish then Installer.Finish() else Installer.Go(index + 1) end
		end)
	elseif session.express and steps[index].key == "keys" then
		Installer.Finish()
	else
		Installer.Next()
	end
end

-- Close the last page after Finish. Setup pages of plugins and modules
-- (Core/Plugins.lua) not reached come next; a reload question waits until
-- they are done, and only comes when a change needs one.
function CloseDone(quiet)
	if not (session and session.finished) then return end
	local needsReload = session.needsReload and not quiet
	local failed = session.failedSteps or {}
	-- The alt setup takes the profile as it is, setup pages included.
	local attached = session.focus == "alt"
	session = nil
	ForgetRun()
	if window and window:IsShown() then
		finishing = true
		window:Hide()
		finishing = false
	end
	if quiet then return end
	-- Steps that hit an error: an alert that opens the first one again.
	ReportFailed(failed)
	local function Done()
		-- Asked, so any copy box an addon setup opened stays usable.
		if needsReload then E:ShowReloadPrompt(L["EldoUI is set up. Reload the UI now to finish?"]) end
	end
	if attached then
		Done()
		return
	end
	-- A plugin page that errors must not take the reload question with it.
	local ok, err = pcall(function() E:RunPluginSetup(Done) end)
	if not ok then
		geterrorhandler()(err)
		Done()
	end
end
Installer.CloseDone = CloseDone

-- Apply every step with a pending choice, mark the character set up and
-- show the last page as the list of what changed.
local function RunFinish()
	if not session then return end
	local failed = {}
	-- A fresh profile whose Layout step was kept gets its preset's sizes.
	E:ApplyFreshLayout()
	-- Modules switch first: a module turned on here builds its frames
	-- before the layout places them and switches off the ones it keeps
	-- off (the layout also catches movers made later, Core/Layout.lua).
	-- Addons you already use comes before them, so the module ticks follow
	-- the picks made there.
	for _, key in ipairs({ "competitors", "modules" }) do
		for _, step in ipairs(steps) do
			if step.key == key and StepState(step) ~= "applied" and step.HasChoice() then SafeApply(step, failed) end
		end
	end
	for index, step in ipairs(steps) do
		local state = StepState(step)
		if step.manual then
			-- A setup page the player saw but didn't apply counts as
			-- answered; one they never reached opens after Finish.
			if index <= session.reached and state ~= "applied" and E:GetInstallStepState(step.page.key) == nil then
				E:SetInstallStepState(step.page.key, step.page.Apply and "skipped" or "seen")
			end
		elseif step.Apply and state ~= "applied" and not step.explicit and step.HasChoice() then
			SafeApply(step, failed)
		end
	end
	-- Module install steps on a fresh profile.
	if session.profile.fresh then
		for _, module in E:IterateModules() do
			if module.OnInstall then
				local ok, err = pcall(module.OnInstall, module)
				if not ok then geterrorhandler()(err) end
			end
		end
	end
	Entry.Done(failed)
end

-- The run is over: mark the character set up and show the last page.
-- attach: the alt setup, which changes nothing in the profile, so the
-- profile's own setup marks stay as they are.
function Entry.Done(failed, attach)
	EldoUIDB.installed = EldoUIDB.installed or {}
	EldoUIDB.installed[E.charKey] = E.version
	if not attach then
		E.db.needsSetup, E.db.layoutApplied, E.db.blizzardTakeover, E.db.blizzardTakeoverPending = nil, nil, nil, nil
		Installer.RecordSeen()
	end
	Installer.SetupDone()
	if E.InstallerAlt then
		local ok, err = pcall(E.InstallerAlt.NoteFinish, session, attach)
		if not ok then geterrorhandler()(err) end
	end
	session.finished = true
	ForgetRun()
	session.failedSteps = failed
	current = #steps
	session.reached = #steps
	if window and window:IsShown() then
		Installer.Update()
		ReportFailed(failed)
	else
		-- Closed in the meantime: the list can't show, the rest goes on.
		CloseDone()
	end
end

-- The alt setup attached the character (Core/InstallerAlt.lua).
function Installer.CompleteAttach(failed)
	if session and not session.finished then Entry.Done(failed or {}, true) end
end

function Installer.Finish()
	if session and session.finished then
		CloseDone()
		return
	end
	-- On the alt page Finish is its Attach.
	if Entry.OnAltPage() then
		if E.InstallerAlt then E.InstallerAlt.Attach() end
		return
	end
	EnsureProfile(RunFinish)
end

-- The Keys and spells step's place in this run, or nil.
local function KeysIndex()
	for index, step in ipairs(steps) do
		if step.key == "keys" then return index end
	end
end

-- Express setup (Welcome step): a pack's picks on every step (the pack
-- picked there, else the first), then the Keys and spells step with the
-- pack's preset picked: its Apply sets the keys and finishes, and nothing
-- touches a key or a button before it. Without that step, Finish.
function Installer.Express(packKey)
	Entry.LeaveAlt()
	if not session or session.finished then return end
	if packKey and E.packs[packKey] then session.pack = packKey end
	EnsureProfile(function()
		if not session then return end
		local pack = Pack.Run()
		ExpressPicks(pack)
		local index = KeysIndex()
		if not index then
			RunFinish()
			return
		end
		Keys.FromPack(pack)
		current = index
		session.reached = math.max(session.reached, index)
		Installer.Update()
	end)
end

-- Customize (Welcome step): the pack's picks on the look steps, then the
-- steps one by one from the UI scale on.
function Installer.Customize(packKey)
	Entry.LeaveAlt()
	if not session or session.finished then return end
	if packKey and E.packs[packKey] then session.pack = packKey end
	EnsureProfile(function()
		if not session then return end
		Pack.Picks(Pack.Run(), false)
		Touch("layout")
		Touch("styles")
		current = 1
		Installer.Go(2)
	end)
end

---------------------------------------------------------------------------
-- Entry points
---------------------------------------------------------------------------
-- The step for a word from /eui install <step>: a key ("role", "layout"),
-- a sidebar label ("ui scale") or a setup page key.
function Entry.FindStep(word)
	word = strtrim(tostring(word or "")):lower()
	if word == "" then return nil end
	for index, step in ipairs(steps) do
		if step.key:lower() == word or step.short:lower() == word or L[step.short]:lower() == word or step.key:lower() == "page:" .. word then return index end
	end
	for index, step in ipairs(steps) do
		if step.short:lower():sub(1, #word) == word or step.key:lower():sub(1, #word) == word then return index end
	end
end

function Entry.StepNames()
	local names = {}
	for _, step in ipairs(steps) do
		if not step.manual and step.key ~= "finish" then names[#names + 1] = step.key end
	end
	return table.concat(names, ", ")
end

-- stepKey (optional): open that step ("undo" undoes the last setup).
function E:ShowInstaller(stepKey)
	if InCombatLockdown() then
		local open, admit = self.ShowInstaller, Work.ProfileTarget
		local target = admit()
		if not target then return end
		local pending = self:PendingOutOfCombat("installer-open")
		self:RunOutOfCombat(function()
			if not E.Secret(self.ShowInstaller) and self.ShowInstaller == open and Work.ProfileTarget == admit and admit(target) then
				open(self, stepKey)
			end
		end, "installer-open")
		if not pending then self:Print(L["The setup opens after combat."]) end
		return
	end
	if type(stepKey) == "string" and strtrim(stepKey):lower() == "undo" then
		self:UndoInstall()
		return
	end
	if not window then CreateWindow() end
	-- Opened while it waited for another addon's first-run window: the
	-- player asked, so the wait is over.
	if loading.wait and not loading.cinematic then
		loading.wait, loading.world, loading.open, loading.reopen = false, false, false, false
	end
	-- Asked for again while the last page of a finished run is open: a new run.
	local explicit = stepKey ~= nil and strtrim(tostring(stepKey)) ~= ""
	if session and session.finished and window:IsShown() and explicit then CloseDone(true) end
	-- A step asked for by name on the alt page: the full setup.
	if explicit and window:IsShown() then Entry.LeaveAlt() end
	if not window:IsShown() then
		-- "Do later", a reload or a logout earlier: go on where the player
		-- stopped, with the same picks (a short setup stays short).
		local stored = StoredRun()
		-- A step asked for by name: the full setup, not the alt page.
		if stored and stored.focus == "alt" and explicit then
			ForgetRun()
			stored = nil
		end
		local focus = stored and stored.focus or (not stored and Entry.focus) or nil
		Entry.focus = nil
		-- A character that never ran the setup, on an account where another
		-- one set a profile up: the alt page instead of Welcome.
		if not stored and focus == nil and not explicit and E.InstallerAlt and E.InstallerAlt.Qualifies() then focus = "alt" end
		BuildSteps(focus)
		if stored then
			session, current = stored, tonumber(stored.step) or 1
		else
			session, current = NewSession(), 1
			session.focus = focus
			if focus == "alt" and E.InstallerAlt then E.InstallerAlt.Start(session) end
			KeepRun(session)
		end
		for _, step in ipairs(steps) do session[step.key] = session[step.key] or { state = "none" } end
		current = math.min(current, #steps)
		session.reached = math.min(math.max(session.reached, current), #steps)
		session.paused = nil
		window:Show()
	end
	-- The options window steps aside while the setup shows, the way it
	-- does for move mode, so it never shows through the setup.
	if E.CloseConfigForMoveMode and E:CloseConfigForMoveMode() then window.configBack = true end
	-- The setup is open: no reminder competes with it.
	Entry.ClearRemind()
	Installer.Update()
	if stepKey and strtrim(tostring(stepKey)) ~= "" then
		local index = Entry.FindStep(stepKey)
		if not index then
			self:Print(L["No setup step %q. Steps: %s."]:format(tostring(stepKey), Entry.StepNames()))
		elseif index ~= current then
			-- One step on its own sets up the profile in use.
			if not session.profile.done then PickProfileMode("current") end
			session.reached = math.max(session.reached, index)
			Installer.Go(index)
		end
	end
end

-- The alt page for this character, also one that is set up already
-- (/eui attach, Profiles page): `profile` (optional) is picked on it.
function Installer.ShowAlt(profile)
	if InCombatLockdown() then
		E:Print(L["The setup opens after combat."])
		E:RunOutOfCombat(function() Installer.ShowAlt(profile) end, "installer-alt")
		return
	end
	if session and session.finished and window and window:IsShown() then CloseDone(true) end
	if not (window and window:IsShown()) then
		-- A paused run of the alt page goes on; any other starts over here.
		local stored = StoredRun()
		if stored and stored.focus ~= "alt" then ForgetRun() end
		Entry.focus = "alt"
	end
	E:ShowInstaller()
	if session and not session.finished and session.focus ~= "alt" then Installer.SwitchRun("alt") end
	if session and E.InstallerAlt and profile and profile ~= "" then E.InstallerAlt.Pick(profile) end
	Installer.Update()
end

function Entry.NeedsInstall()
	return not Installed() or (E.db and E.db.needsSetup) and true or false
end

---------------------------------------------------------------------------
-- The setup reminder. A setup that is not finished gets one chat line per
-- login and one small alert, "Finish your EldoUI setup":
--   * Start setup or Continue setup opens the same run as /eui install;
--   * Later: no alert again until the next login (reloads included);
--   * Don't remind me (this profile): no line, no alert, and the setup no
--     longer opens by itself; /eui install still opens it.
-- Never in combat (it comes once after), never over a loading screen or a
-- cinematic, never while the setup is open; repeated asks make one alert.
-- A setup that was finished or skipped stays quiet. A run the player
-- paused with the close button is not opened again at the next login:
-- the line and the alert offer it instead.
---------------------------------------------------------------------------
E.defaults.general.installerRemind = true
Entry.REMIND_KEY = "EldoUI_SetupRemind"

-- What this login already did for this character: hinted (the chat line
-- was printed), later (Later was clicked). Kept over reloads, dropped at
-- the next real login.
function Entry.LoginState()
	local all = type(EldoUIDB.installerLogin) == "table" and EldoUIDB.installerLogin or {}
	EldoUIDB.installerLogin = all
	local mine = type(all[E.charKey]) == "table" and all[E.charKey] or {}
	all[E.charKey] = mine
	return mine
end

function Entry.NewLogin()
	local all = EldoUIDB.installerLogin
	if type(all) ~= "table" then return end
	all[E.charKey] = nil
	if next(all) == nil then EldoUIDB.installerLogin = nil end
end

function Entry.RemindOn()
	local general = E.db and E.db.general
	return not (type(general) == "table" and general.installerRemind == false)
end

-- "continue" when a kept run went past the Welcome step, else "start".
function Entry.RemindKind()
	local stored = StoredRun()
	if stored and (tonumber(stored.reached) or 1) > 1 then return "continue" end
	return "start"
end

-- The run waits for the player: paused with the close button, or the
-- reminders of this profile are off.
function Entry.HoldOpen()
	if not Entry.RemindOn() then return true end
	local stored = StoredRun()
	return stored ~= nil and stored.paused and true or false
end

function Entry.RemindLine(kind)
	if kind == "continue" then
		return L["EldoUI setup is paused. Type %s to continue where you left off."]:format(HL("/eui install"))
	end
	return L["EldoUI setup is not finished. Type %s to get started."]:format(HL("/eui install"))
end

-- The player closed the setup: one chat line now, then the alert.
function Entry.Paused()
	Entry.LoginState().hinted = true
	E:Print(Entry.RemindLine(Entry.RemindKind()))
	Entry.Remind()
end

function Entry.Remind()
	Entry.remindPending = true
	Entry.FlushRemind()
end

function Entry.FlushRemind()
	if not Entry.remindPending then return end
	-- The end of the loading screen or the scene calls again.
	if loading.world or loading.cinematic then return end
	if window and window:IsShown() then
		Entry.remindPending = nil
		return
	end
	if InCombatLockdown() then
		if not Entry.remindAfterCombat then
			Entry.remindAfterCombat = true
			E:RunOutOfCombat(function()
				Entry.remindAfterCombat = nil
				Entry.FlushRemind()
			end)
		end
		return
	end
	Entry.remindPending = nil
	if not (Entry.NeedsInstall() and Entry.RemindOn()) then return end
	local state, kind = Entry.LoginState(), Entry.RemindKind()
	if not state.hinted then
		state.hinted = true
		E:Print(Entry.RemindLine(kind))
	end
	if state.later then return end
	E:PushAlert({ key = Entry.REMIND_KEY, title = L["Finish your EldoUI setup"], options = { page = "general" },
		text = L["Choose your layout and review your addons in one place."],
		actions = {
			{ label = kind == "continue" and L["Continue setup"] or L["Start setup"],
				tip = kind == "continue" and L["Opens the setup on the step where you stopped, with your picks."] or L["Opens the setup on its first step."],
				func = function() E:ShowInstaller() end },
			{ label = L["Later"], tip = L["No reminder again until your next login."],
				func = function() Entry.LoginState().later = true end },
			{ label = L["Don't remind me"], tip = L["No more reminders on this profile, and the setup no longer opens by itself. %s still opens it."]:format(HL("/eui install")),
				func = function()
					if E.db and type(E.db.general) == "table" then E.db.general.installerRemind = false end
				end },
		} })
end

-- Takes the alert away (the setup opened).
function Entry.ClearRemind()
	Entry.remindPending = nil
	if E.DismissAlert then E:DismissAlert(Entry.REMIND_KEY) end
end

-- The setup opens by itself on a character's first login with EldoUI and
-- on every fresh profile (design decision), also one made or reset
-- later in the session. The layout is applied at once; the window opens
-- once the loading screen is gone, since the game closes every open
-- window when the world shows. atLogin: called from PLAYER_LOGIN.
---------------------------------------------------------------------------
-- New in this version: the layouts, preset packs and setup steps a
-- profile's setup has seen are kept in the profile (installerSeen). After
-- an update that brings new ones, an alert offers them once; "Keep my
-- setup" comes first and changes nothing, "Show me" opens a short setup
-- with only the new parts, where every step starts on keep. Setup pages of
-- modules and plugins have their own offer (Core/Plugins.lua).
---------------------------------------------------------------------------
-- The installer's own steps a setup can be new for (not Welcome or Finish).
function Entry.StepKeys()
	local list = {}
	for _, step in ipairs(BASE) do
		if step.key ~= "profile" then list[#list + 1] = step.key end
	end
	return list
end

function Installer.SeenLists()
	local layouts, packs, stepKeys = {}, {}, {}
	for _, key in ipairs(E.layoutOrder or {}) do layouts[key] = true end
	for _, key in ipairs(E.packOrder or {}) do packs[key] = true end
	for _, key in ipairs(Entry.StepKeys()) do stepKeys[key] = true end
	return { layouts = layouts, packs = packs, steps = stepKeys, version = E.version }
end

function Installer.RecordSeen()
	if E.db then E.db.installerSeen = Installer.SeenLists() end
end

-- What is new since the profile's setup: three lists of keys (layouts,
-- packs, steps). A record from before steps were kept counts every step
-- as seen.
function Installer.NewSinceSeen()
	local seen = E.db and E.db.installerSeen
	local layouts, packs, newSteps = {}, {}, {}
	if type(seen) ~= "table" then return layouts, packs, newSteps end
	local seenLayouts = type(seen.layouts) == "table" and seen.layouts or {}
	local seenPacks = type(seen.packs) == "table" and seen.packs or {}
	for _, key in ipairs(E.layoutOrder or {}) do
		if not seenLayouts[key] and E.layouts[key] then layouts[#layouts + 1] = key end
	end
	for _, key in ipairs(E.packOrder or {}) do
		if not seenPacks[key] and E.packs[key] then packs[#packs + 1] = key end
	end
	if type(seen.steps) == "table" then
		for _, key in ipairs(Entry.StepKeys()) do
			if not seen.steps[key] then newSteps[#newSteps + 1] = key end
		end
	end
	return layouts, packs, newSteps
end

-- The short setup for what is new: the Welcome step (where the packs
-- are), the Layout step for new layouts and every new step, then Finish.
-- It opens on the first new part.
function Installer.ShowNew(layouts, packs, newSteps)
	local focus = {}
	if #layouts > 0 then focus[#focus + 1] = "layout" end
	for _, key in ipairs(newSteps) do
		if key ~= "layout" or #layouts == 0 then focus[#focus + 1] = key end
	end
	local open = #packs == 0 and focus[1] or nil
	-- A run that is open or paused goes on as it is, on that part.
	if (window and window:IsShown() and session) or StoredRun() then
		E:ShowInstaller(open or "profile")
		return
	end
	Entry.focus = #focus > 0 and focus or { "layout" }
	E:ShowInstaller(open)
end

-- At login on a profile that is set up: a profile from before this check
-- keeps what it has as seen, quietly; otherwise new parts get one alert.
function Installer.CheckNew()
	if not (E.db and Installed()) then return false end
	local seen = E.db.installerSeen
	if type(seen) ~= "table" then
		Installer.RecordSeen()
		return false
	end
	if type(seen.steps) ~= "table" then seen.steps = Installer.SeenLists().steps end
	local layouts, packs, newSteps = Installer.NewSinceSeen()
	if #layouts + #packs + #newSteps == 0 then return false end
	local names = {}
	for _, key in ipairs(packs) do names[#names + 1] = L["%s pack"]:format(L[E.packs[key].title or key]) end
	for _, key in ipairs(layouts) do names[#names + 1] = L["%s layout"]:format(E:LayoutTitle(key)) end
	for _, key in ipairs(newSteps) do
		for _, step in ipairs(BASE) do
			if step.key == key then names[#names + 1] = L["the %s step"]:format(L[step.short]) end
		end
	end
	E:PushAlert({ key = "EldoUI_SetupNew", title = L["New in this version"], options = { page = "whatsnew" },
		text = L["EldoUI has something new for the setup: %s. Your setup stays as it is unless you pick one."]:format(table.concat(names, ", ")),
		actions = {
			{ label = L["Keep my setup"], tip = L["Changes nothing. The setup does not offer these again; %s shows them any time."]:format(HL("/eui install")),
				func = function() Installer.RecordSeen() end },
			{ label = L["Show me"], tip = L["Opens a short setup with only the new parts. Every step starts on keep, so you only change what you pick."],
				func = function()
					Installer.RecordSeen()
					Installer.ShowNew(layouts, packs, newSteps)
				end },
		} })
	return true
end

function E:CheckInstall(atLogin)
	-- The game could not load the saved settings: this session runs on
	-- defaults, so the setup stays closed and one line says why.
	if self.settingsNotLoaded then
		if not self.settingsNotLoadedTold then
			self.settingsNotLoadedTold = true
			self:Print(L["The game did not have the memory to load EldoUI's saved settings, so this session uses the defaults and the setup stays closed. Turn off some other addons, then reload."])
		end
		return
	end
	if atLogin then loading.world = true end
	if not Entry.NeedsInstall() then
		Installer.CheckNew()
		return
	end
	self:ApplyFreshLayout()
	-- A run the player paused, or a profile without reminders: the setup
	-- waits for /eui install (the reminder says so, when it is on).
	if Entry.HoldOpen() then
		Entry.Remind()
	elseif loading.world then
		loading.open = true
	else
		self:ShowInstaller()
	end
end

function Entry.LoadingScreenStarted()
	loading.world = true
end

-- Runs on the frame after the world shows, after the game's own handler
-- closed the windows.
function Entry.LoadingScreenDone()
	if not loading.world then return end
	-- A cinematic still plays: everything waits for its end. A scene the
	-- game no longer reports (its end event got lost) is over.
	if loading.cinematic == "scene" and InCinematic and not InCinematic() then loading.cinematic = false end
	if loading.cinematic then return end
	-- Another addon's first-run window shows or is about to: the setup
	-- (or its reminder) waits for Installer.WaitChanged.
	local due = loading.open or loading.reopen or Entry.remindPending
		or (session and not session.finished and window and not window:IsShown())
	if due and Entry.WaitBusy() then
		loading.wait = true
		return
	end
	loading.world, loading.wait = false, false
	local open = loading.open
	loading.open, loading.reopen = false, false
	-- An open run (not paused, not finished) whose window the game hid:
	-- closed by the loading screen or the cinematic (reopen), or hidden
	-- while the whole UI was hidden, which fires no OnHide of its own.
	if session and not session.finished and window and not window:IsShown() then
		window:Show()
		Installer.Update()
	elseif open and Entry.NeedsInstall() and not (window and window:IsShown()) then
		E:ShowInstaller()
	end
	-- A reminder that waited for the loading screen or the scene.
	Entry.FlushRemind()
end

E:RegisterEvent("LOADING_SCREEN_ENABLED", Entry.LoadingScreenStarted, Installer)
E:RegisterEvent("PLAYER_ENTERING_WORLD", function(_, _, isInitialLogin)
	-- A real login (not a reload) starts a new login for the reminder.
	if isInitialLogin then Entry.NewLogin() end
	C_Timer.After(0, Entry.LoadingScreenDone)
end, Installer)
-- A fallback, should the world show without PLAYER_ENTERING_WORLD after it.
E:RegisterEvent("LOADING_SCREEN_DISABLED", function()
	C_Timer.After(1, Entry.LoadingScreenDone)
end, Installer)
-- Cinematics and movies (a new character's intro first of all): the setup
-- waits for their end like it waits for the loading screen, then opens or
-- comes back on the same step.
-- Should the end event never come (a reload or a crash during the scene, a
-- skipped scene that sends only one event), a check every few seconds asks
-- the game whether the scene still plays; a movie ends when the movie
-- window it opened is gone, and at the latest after ten minutes. So the
-- setup never waits for good.
Entry.CINEMATIC_CHECK, Entry.MOVIE_LONGEST = 2, 600
function Entry.CinematicStarted(kind)
	loading.cinematic = kind
	loading.world = true
	Entry.StopCinematicWatch()
	if not (C_Timer and C_Timer.NewTicker) then return end
	local started, movieSeen = GetTime(), false
	Entry.cinematicWatch = C_Timer.NewTicker(Entry.CINEMATIC_CHECK, function()
		if loading.cinematic ~= kind then return Entry.StopCinematicWatch() end
		local over
		if kind == "scene" then
			over = not Entry.ScenePlaying()
		else
			local movie = _G.MovieFrame
			local shown = movie and movie.IsShown and movie:IsShown()
			if shown then movieSeen = true end
			over = (movieSeen and not shown) or GetTime() - started >= Entry.MOVIE_LONGEST
		end
		if over then Entry.CinematicDone() end
	end)
end
function Entry.StopCinematicWatch()
	if Entry.cinematicWatch then Entry.cinematicWatch:Cancel() end
	Entry.cinematicWatch = nil
end
function Entry.CinematicDone()
	Entry.StopCinematicWatch()
	if not loading.cinematic then return end
	loading.cinematic = false
	Entry.ShowWhenSettled()
end

-- The game's frames of a scene that the game does not report through
-- InCinematic: the movie window, and the intro's skip question.
Entry.SCENE_FRAMES = { "MovieFrame", "CinematicFrameCloseDialog" }

-- True while the game plays a scene (also while its skip question shows)
-- or shows a movie.
function Entry.ScenePlaying()
	if (InCinematic and InCinematic()) or (IsInCinematicScene and IsInCinematicScene()) then return true end
	for _, name in ipairs(Entry.SCENE_FRAMES) do
		local frame = _G[name]
		if type(frame) == "table" and type(frame.IsShown) == "function" and frame:IsShown() then return true end
	end
	return false
end

-- True while the setup waits for a scene (its start was heard) or the
-- game plays one.
function Entry.SceneBusy()
	if loading.cinematic then return true end
	return Entry.ScenePlaying()
end

-- The window was closed by a scene: wait for its end like for a loading
-- screen. Should the game's start event never reach EldoUI, the check
-- that runs every few seconds starts here, so the wait always ends.
function Entry.HeldByScene()
	loading.world, loading.reopen = true, true
	if not loading.cinematic then
		local movie = _G.MovieFrame
		Entry.CinematicStarted(movie and movie.IsShown and movie:IsShown() and "movie" or "scene")
	end
end

-- After a scene the key that skipped it (Escape, or the answer to the
-- skip question) can still be down, and a window that shows then closes
-- at once. The setup shows half a second after the scene's end; while
-- Escape is still held or a scene frame still shows, it checks again
-- every quarter second, for three seconds at most. It never holds keys
-- back: a close after the setup shows still pauses it.
Entry.SETTLE_FIRST, Entry.SETTLE_STEP, Entry.SETTLE_LONGEST = 0.5, 0.25, 3
function Entry.ShowWhenSettled()
	local token = {}
	Entry.settle = token
	local waited = Entry.SETTLE_FIRST
	local function Try()
		if Entry.settle ~= token then return end
		-- A new scene started: its end calls this again.
		if loading.cinematic then
			Entry.settle = nil
			return
		end
		local busy = (IsKeyDown and IsKeyDown("ESCAPE")) or Entry.ScenePlaying()
		if busy and waited < Entry.SETTLE_LONGEST then
			waited = waited + Entry.SETTLE_STEP
			C_Timer.After(Entry.SETTLE_STEP, Try)
			return
		end
		Entry.settle = nil
		Entry.LoadingScreenDone()
	end
	C_Timer.After(Entry.SETTLE_FIRST, Try)
end
-- Other addons' own first-run windows (a welcome window, a first choice of
-- profile or of how quest objectives show) change data or settings when
-- they are closed or answered, so EldoUI never closes or answers them.
-- The setup waits for them the way it waits for a scene: a module
-- registers a check with Installer.RegisterWait(key, busy), busy() being
-- true while such a window shows or is about to, and calls
-- Installer.WaitChanged() when one closes. A setup nobody has started yet
-- steps aside when such a window opens over it (Installer.StepAside) and
-- comes back on the same step; once the player has moved on it stays.
-- /eui install always opens.
Entry.waits = {}
function Installer.RegisterWait(key, busy)
	if type(key) == "string" then Entry.waits[key] = type(busy) == "function" and busy or nil end
end
function Entry.WaitBusy()
	for key, busy in pairs(Entry.waits) do
		local ok, result = pcall(busy)
		if ok and result then return key end
	end
end
function Installer.Waiting()
	return loading.wait and true or false
end
function Installer.WaitChanged()
	if loading.wait and not Entry.WaitBusy() then
		loading.wait = false
		Entry.ShowWhenSettled()
	end
end
function Installer.StepAside()
	if not (window and window:IsShown() and session and not session.finished) then return false end
	if current > 1 or (tonumber(session.reached) or 1) > 1 then return false end
	loading.world, loading.reopen, loading.wait = true, true, true
	window:Hide()
	return true
end

E:RegisterEvent("CINEMATIC_START", function() Entry.CinematicStarted("scene") end, Installer)
E:RegisterEvent("PLAY_MOVIE", function() Entry.CinematicStarted("movie") end, Installer)
E:RegisterEvent("CINEMATIC_STOP", function() Entry.CinematicDone() end, Installer)
E:RegisterEvent("STOP_MOVIE", function() Entry.CinematicDone() end, Installer)

hooksecurefunc(E, "SetProfile", function(self)
	if not (IsLoggedIn() and self.db and self.db.needsSetup) then return end
	-- After the switch has finished (the installer may be the one switching).
	C_Timer.After(0, function()
		if self.db.needsSetup and not (window and window:IsShown()) then self:CheckInstall() end
	end)
end)

-- For plugins: read-only views of the run.
function Installer.GetSession() return session end
function Installer.GetStep() return current, steps[current] and steps[current].key end
function Installer.GetWindow() return window end
function Installer.IsPaused() return session == nil and StoredRun() ~= nil end
Installer.steps = steps
